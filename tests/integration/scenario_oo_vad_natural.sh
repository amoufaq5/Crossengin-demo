#!/usr/bin/env bash
# Scenario OO -- R9B: VAD threshold tuning for natural speech at 16 kHz.
#
# R7F (commit 8af9f90) shipped energy + ZCR + K=3/M=10 hysteresis VAD that
# was tested against Klatt-synthesized utterances at 8 kHz with a clean
# zero-amplitude silence baseline. That tuning passed 100% of the Klatt
# tests but produced vad_segments=0 on whisper.cpp's bundled JFK 16 kHz
# WAV -- two bugs:
#
#   1. audio_capture_to_pcm rejected any RIFF/WAVE file with a LIST or
#      INFO sub-chunk between fmt and data (whisper.cpp ships jfk.wav
#      with a LIST/INFO ISFT 'Lavf...' chunk in that slot). The parser
#      now scans forward through optional sub-chunks until it finds
#      'data'.
#   2. Even with the parser fix the energy threshold needed to adapt
#      to the recording's noise floor. R9B adds an adaptive multiplier
#      that takes the leading ~500 ms minimum-frame-energy as the noise
#      floor and lifts the threshold to max(3 * noise_floor, R7F floor).
#      On a clean lead-in the floor wins (R7F behavior preserved
#      bit-identical); on a noisy mic preamp the multiplier kicks in.
#
# This scenario exercises the full /listen path on the JFK 16 kHz WAV:
#   * Run VAD over /tmp/whisper.cpp/samples/jfk.wav -- assert >= 1 segment
#     and filtered PCM in a sensible duration band.
#   * End-to-end `/listen` -- assert non-empty transcript matching
#     "fellow Americans" or "your country" (the JFK quote).
#   * Run VAD over a constructed silent 16 kHz WAV -- assert 0 segments.
#   * Run VAD over a constructed noisy 16 kHz WAV with a 3000-amp speech
#     burst -- assert exactly 1 segment (adaptive threshold filtered
#     the noise floor without losing the speech).
#   * SKIP gracefully if the JFK WAV isn't installed (so CI on
#     non-whisper environments still passes the scenario).
#
# Pre-conditions: NOVA toolchain at $NOVA_ROOT/nova; built chat binary;
# whisper-main + tiny.en model installed for the end-to-end transcript
# check (skipped otherwise).
#
# Side-effects: writes /tmp/ce_scenario_oo_silence.wav,
#               /tmp/ce_scenario_oo_noisy.wav,
#               /tmp/ce_scenario_oo_driver.out, plus the on-the-fly
#               NOVA driver under tests/integration/_scenario_oo_drivers/.

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

it_section "scenario OO: R9B VAD threshold tuning for natural speech"

NOVA_BIN="${NOVA_ROOT:-/home/user/NOVA}/nova"
if [ ! -x "$NOVA_BIN" ]; then
    printf "  ${C_RED}ERROR${C_RST}: NOVA launcher not found at %s (set NOVA_ROOT)\n" "$NOVA_BIN" >&2
    FAIL=$((FAIL+1))
    summary "scenario_oo_vad_natural"
    exit $?
fi

JFK_WAV="${CE_WHISPER_JFK_WAV:-/tmp/whisper.cpp/samples/jfk.wav}"
HAVE_JFK=0
if [ -f "$JFK_WAV" ]; then HAVE_JFK=1; fi

WHISPER_BIN="${CE_WHISPER_BIN:-/usr/local/bin/whisper-main}"
WHISPER_MODEL="${CE_WHISPER_MODEL:-/usr/local/share/whisper/ggml-tiny.en.bin}"
WHISPER_INSTALLED=0
if [ -x "$WHISPER_BIN" ] && [ -f "$WHISPER_MODEL" ]; then
    WHISPER_INSTALLED=1
fi

SILENCE_WAV="/tmp/ce_scenario_oo_silence.wav"
NOISY_WAV="/tmp/ce_scenario_oo_noisy.wav"
DRV_DIR="$REPO_ROOT/tests/integration/_scenario_oo_drivers"
DRV_SRC="$DRV_DIR/oo_vad_driver.nova"
DRV_OUT="/tmp/ce_scenario_oo_driver.out"

mkdir -p "$DRV_DIR"
trap 'rm -f "$SILENCE_WAV" "$NOISY_WAV" "$DRV_OUT" "$DRV_SRC"; rmdir "$DRV_DIR" 2>/dev/null || true' EXIT

# Emit the NOVA driver. The leading underscore on _scenario_oo_drivers/
# means the Makefile's integration glob (! -name '_*') skips it.
cat > "$DRV_SRC" <<'NOVA'
// Auto-generated VAD-natural-speech driver for scenario_oo_vad_natural.sh.
//
// Steps:
//   1. Construct a silent 8 kHz WAV (the synth's canonical rate) and
//      assert audio_capture_to_pcm_vad returns 0 segments.
//   2. Construct a noisy + speech 8 kHz WAV: 500 ms of amp=200 triangle
//      noise + 300 ms of amp=3000 triangle speech + 500 ms of amp=200
//      noise. Assert that with adaptive calibration the VAD detects
//      exactly 1 segment.
//   3. If CE_WHISPER_JFK_WAV is set + exists, run VAD over the 16 kHz
//      JFK WAV. Assert: sample_rate=16000, segments >= 1, filtered_len
//      in a sensible duration band (JFK is ~11 s).

import "std/syscall"
import "../../../src/io/effectors/audio_synth.nova"
import "../../../src/io/transducers/audio_capture.nova"

fn _zero_buf(n) {
    let b = list_new()
    let i = 0
    while i < n {
        push(b, 0)
        i = i + 1
    }
    return b
}

fn _triangle_buf(n, amp, period_samples) {
    let b = list_new()
    let i = 0
    let half = period_samples / 2
    while i < n {
        let phase = i - (i / period_samples) * period_samples
        let v = 0
        if phase < half {
            v = (phase * amp) / half
        } else {
            v = ((phase - half) * amp) / half - amp
        }
        if (i / period_samples) - ((i / period_samples) / 2) * 2 == 1 {
            v = 0 - v
        }
        push(b, v)
        i = i + 1
    }
    return b
}

fn _concat(a, b) {
    let out = list_new()
    let i = 0
    while i < len(a) {
        push(out, a[i])
        i = i + 1
    }
    let j = 0
    while j < len(b) {
        push(out, b[j])
        j = j + 1
    }
    return out
}

fn _report(label, path) {
    let r = audio_capture_to_pcm_vad(path)
    let pcm = audio_capture_vad_samples(r)
    let sr = audio_capture_vad_rate(r)
    let nseg = audio_capture_vad_segments(r)
    println(label + " sr=" + int_to_str(sr)
        + " segments=" + int_to_str(nseg)
        + " filtered_len=" + int_to_str(len(pcm)))
}

fn main() {
    // Fixture 1: pure silence at the synth canonical 8 kHz (5000 zero
    // samples = 625 ms). The adaptive path collapses the threshold
    // back to the R7F floor on pure-zero lead-in, so this MUST still
    // produce 0 segments.
    let sil = _zero_buf(5000)
    let ok_s = audio_write_wav(sil, "/tmp/ce_scenario_oo_silence.wav")
    println("wrote silence wav: " + int_to_str(ok_s))

    // Fixture 2: noisy + speech + noisy at 8 kHz.
    // 4000 samples (500 ms) noise + 2400 samples (300 ms) speech +
    // 4000 samples (500 ms) noise = 10400 samples (1.3 s).
    let n1 = _triangle_buf(4000, 200, 50)   // low-amp lead-in noise
    let sp = _triangle_buf(2400, 3000, 50)  // speech burst
    let n2 = _triangle_buf(4000, 200, 50)   // trailing noise
    let mix = _concat(_concat(n1, sp), n2)
    let ok_n = audio_write_wav(mix, "/tmp/ce_scenario_oo_noisy.wav")
    println("wrote noisy wav: " + int_to_str(ok_n))

    _report("SILENCE", "/tmp/ce_scenario_oo_silence.wav")
    _report("NOISY",   "/tmp/ce_scenario_oo_noisy.wav")

    let jfk = getenv("CE_WHISPER_JFK_WAV")
    if jfk == 0 { jfk = "/tmp/whisper.cpp/samples/jfk.wav" }
    if len(jfk) > 0 {
        _report("JFK", jfk)
    } else {
        println("JFK skip")
    }

    println("driver complete")
}

main()
NOVA

# Run the driver.
CE_WHISPER_JFK_WAV="$JFK_WAV" "$NOVA_BIN" run "$DRV_SRC" > "$DRV_OUT" 2>&1
DRIVER_RC=$?

if [ "$DRIVER_RC" -ne 0 ]; then
    printf "  ${C_RED}FAIL${C_RST}  driver exited non-zero (rc=%d). Output:\n" "$DRIVER_RC"
    sed 's/^/        /' "$DRV_OUT"
    FAIL=$((FAIL+1))
    summary "scenario_oo_vad_natural"
    exit $?
fi

DRV_TXT=$(cat "$DRV_OUT")

# ===========================================================================
# Assertions: synthetic fixtures (always run)
# ===========================================================================

assert_match "$DRV_TXT" "wrote silence wav: 1" \
    "8 kHz silent WAV written"
assert_match "$DRV_TXT" "wrote noisy wav: 1" \
    "8 kHz noisy+speech WAV written"
assert_file_exists "$SILENCE_WAV" "silence WAV exists on disk"
assert_file_exists "$NOISY_WAV"   "noisy+speech WAV exists on disk"

# Silence fixture: must produce zero segments. The adaptive path
# collapses the threshold back to the R7F fixed floor when the leading
# audio is exact zero, so this matches R7F's existing
# scenario_ii_vad.sh silence assertion bit-identical.
assert_match "$DRV_TXT" "SILENCE sr=8000 segments=0 filtered_len=0" \
    "silence WAV -> 0 VAD segments (adaptive floor preserves R7F semantics)"

# Noisy+speech fixture: adaptive calibration should suppress the steady-
# state noise floor (amp=200 triangle, ~24000 energy/frame) and still
# detect exactly 1 speech segment (amp=3000 triangle, ~360000
# energy/frame). The R9B test for this is the headline assertion that
# proves adaptive thresholds work on a recording the R7F fixed
# threshold could not gate cleanly.
assert_match "$DRV_TXT" "NOISY sr=8000 segments=1 filtered_len=[0-9]+" \
    "noisy lead-in WAV -> 1 VAD segment (adaptive threshold isolates speech from noise floor)"

# Driver completed without crash.
assert_match "$DRV_TXT" "driver complete" \
    "driver reached end-of-main without crash"

# ===========================================================================
# Assertions: JFK fixture (skip gracefully if not installed)
# ===========================================================================

if [ "$HAVE_JFK" -eq 1 ]; then
    JFK_LINE=$(printf '%s\n' "$DRV_TXT" | grep -E '^JFK ' | head -1)
    JFK_SR=$(echo "$JFK_LINE" | grep -oE 'sr=[0-9]+' | head -1 | cut -d= -f2)
    JFK_SEGS=$(echo "$JFK_LINE" | grep -oE 'segments=[0-9]+' | head -1 | cut -d= -f2)
    JFK_FLEN=$(echo "$JFK_LINE" | grep -oE 'filtered_len=[0-9]+' | head -1 | cut -d= -f2)

    assert_eq "$JFK_SR" "16000" "JFK WAV decoded at 16 kHz (parser accepts LIST chunk)"
    if [ -n "$JFK_SEGS" ] && [ "$JFK_SEGS" -ge 1 ]; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}PASS${C_RST}  JFK 16 kHz WAV produces >= 1 VAD segment (got %s)\n" "$JFK_SEGS"
    else
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  JFK 16 kHz WAV produced 0 segments\n"
    fi
    # JFK clip is ~11 s = ~176000 samples @ 16 kHz; most should be speech
    # after the brief lead-in. Allow [5s, 13s] = [80000, 208000] samples.
    if [ -n "$JFK_FLEN" ] && [ "$JFK_FLEN" -ge 80000 ] && [ "$JFK_FLEN" -le 208000 ]; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}PASS${C_RST}  JFK filtered PCM in expected duration band [80000, 208000] (got %s)\n" "$JFK_FLEN"
    else
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  JFK filtered PCM out of band (got %s, expected [80000, 208000])\n" "$JFK_FLEN"
    fi

    # End-to-end /listen JFK -- requires whisper installed for the
    # transcript-content assertions. Without whisper we still verify
    # the dispatch path (vad_segments + backend name).
    require_chat
    LISTEN_OUT=$(CE_STT_BACKEND=whisper CE_WHISPER_BIN="$WHISPER_BIN" \
                 CE_WHISPER_MODEL="$WHISPER_MODEL" \
                 run_chat "/listen $JFK_WAV")
    assert_match "$LISTEN_OUT" "vad_segments=" \
        "/listen JFK reports vad_segments via R9B-fixed parser+adaptive VAD"
    assert_nomatch "$LISTEN_OUT" "vad_segments=0" \
        "/listen JFK no longer reports vad_segments=0"

    if [ "$WHISPER_INSTALLED" -eq 1 ]; then
        assert_match "$LISTEN_OUT" "(fellow Americans|your country)" \
            "/listen JFK transcript contains 'fellow Americans' or 'your country'"
        assert_match "$LISTEN_OUT" "backend=whisper" \
            "/listen JFK dispatched through whisper backend"
    else
        printf "  ${C_YEL}SKIP${C_RST}  whisper-main not installed -- transcript content checks skipped\n"
    fi
else
    printf "  ${C_YEL}SKIP${C_RST}  JFK WAV not at %s -- JFK assertions skipped\n" "$JFK_WAV"
fi

# Negative check: no FAIL line in driver output.
assert_nomatch "$DRV_TXT" "^FAIL" \
    "driver did not emit FAIL lines"

summary "scenario_oo_vad_natural"
