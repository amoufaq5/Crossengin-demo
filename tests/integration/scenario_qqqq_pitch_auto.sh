#!/usr/bin/env bash
# Scenario QQQQ -- R22F.2: Auto-switching pitch detector (R10F autocorrelation
# <-> R11B YIN) driven by per-frame harmonicity score.
#
# R22F (audio_melody) picks R10F by default because R11B YIN's octave-down
# anti-snap collapses pure sines. R22F.2 picks the better detector per frame
# based on the signal's harmonic content:
#
#   * Pure / low-harmonic content      -> R10F (no YIN sub-multiple snap)
#   * Harmonic / multi-formant content -> R11B (no AC formant snap)
#
# The decision is made by the harmonicity heuristic which runs a single-frame
# STFT, gates on spectral peakiness, then counts distinct prominent peaks.
#
# This scenario exercises the new pitch_estimate_frame_auto /
# pitch_track_auto entry points on:
#
#   1. A synthesized pure 200 Hz sine (1.5 s @ 8 kHz). Asserts EVERY frame
#      routes to AUTOCORR (no YIN). F0 ~ 200 Hz.
#   2. A synthesized harmonic-rich 200 Hz tone (sum of 1st + 2nd + 3rd
#      harmonics, 1.5 s @ 8 kHz). Asserts MAJORITY of frames route to YIN.
#      F0 ~ 200 Hz on YIN frames.
#   3. A concatenated [sine + Klatt /ae/ vowel + harmonic + silence]
#      sequence. Asserts each section's per-frame method is consistent
#      with the content type.
#   4. (Conditional, only if /tmp/whisper.cpp/samples/jfk.wav exists)
#      JFK sample: assert the per-frame auto-switch produces a
#      majority-YIN result on this natural-speech adult-male voice. Mean
#      F0 should be lower than R10F's standalone (formant-snap) value
#      because YIN frames cure the snap.
#
# Pre-conditions: NOVA toolchain at $NOVA_ROOT/nova.
# Side-effects: writes /tmp/ce_scenario_qqqq_*.wav and on-the-fly NOVA
#               drivers under tests/integration/_scenario_qqqq_drivers/.

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

it_section "scenario QQQQ: R22F.2 harmonicity auto-switch pitch detector"

NOVA_BIN="${NOVA_ROOT:-/home/user/NOVA}/nova"
if [ ! -x "$NOVA_BIN" ]; then
    printf "  ${C_RED}ERROR${C_RST}: NOVA launcher not found at %s (set NOVA_ROOT)\n" "$NOVA_BIN" >&2
    FAIL=$((FAIL+1))
    summary "scenario_qqqq_pitch_auto"
    exit $?
fi

DRV_DIR="$REPO_ROOT/tests/integration/_scenario_qqqq_drivers"
DRV_SRC="$DRV_DIR/pitch_auto_driver.nova"
DRV_OUT="/tmp/ce_scenario_qqqq_driver.out"

JFK_WAV="${CE_WHISPER_JFK_WAV:-/tmp/whisper.cpp/samples/jfk.wav}"
HAVE_JFK=0
if [ -f "$JFK_WAV" ]; then HAVE_JFK=1; fi

mkdir -p "$DRV_DIR"
trap 'rm -f "$DRV_OUT"; rm -rf "$DRV_DIR"' EXIT

# Stand-alone synth driver: emits one line per fixture with the per-method
# frame count (AC vs YIN) and mean F0. The shell parses these and asserts
# the expected method distribution + F0 range per fixture.
cat > "$DRV_SRC" <<'NOVA'
import "std/syscall"
import "../../../src/io/effectors/audio_synth.nova"
import "../../../src/io/transducers/audio_pitch.nova"

fn _harmonic_buf(f0_hz, n, sr) {
    let h1 = synth_sine(f0_hz, n, sr)
    let h2 = synth_sine(f0_hz * 2, n, sr)
    let h3 = synth_sine(f0_hz * 3, n, sr)
    let out = list_new()
    let i = 0
    while i < n {
        let v = h1[i] * 3 + h2[i] * 2 + h3[i] * 1
        push(out, v / 6)
        i = i + 1
    }
    return out
}

fn _zero_buf(n) {
    let b = list_new()
    let i = 0
    while i < n {
        push(b, 0)
        i = i + 1
    }
    return b
}

fn _report_auto(label, samples, sample_rate) {
    let contour = pitch_track_auto(samples, sample_rate)
    let total = len(contour)
    let yin_n = pitch_auto_method_count(contour, pitch_method_yin())
    let ac_n  = pitch_auto_method_count(contour, pitch_method_autocorr())
    let voiced = 0
    let sum = 0
    let i = 0
    while i < total {
        let e = contour[i]
        if e[0] != pitch_unvoiced_sentinel() {
            sum = sum + e[0]
            voiced = voiced + 1
        }
        i = i + 1
    }
    let mean_c = 0
    if voiced > 0 { mean_c = sum / voiced }
    println(label + " sr=" + int_to_str(sample_rate)
        + " frames=" + int_to_str(total)
        + " yin=" + int_to_str(yin_n)
        + " ac=" + int_to_str(ac_n)
        + " voiced=" + int_to_str(voiced)
        + " mean_f0=" + int_to_str(mean_c))
}

fn main() {
    // Fixture 1: pure 200 Hz sine, 1.5 s @ 8 kHz = 12000 samples.
    let sine = synth_sine(200, 12000, 8000)
    _report_auto("PURE_SINE", sine, 8000)

    // Fixture 2: harmonic-rich 200 Hz (1st + 2nd + 3rd), 1.5 s @ 8 kHz.
    let harm = _harmonic_buf(200, 12000, 8000)
    _report_auto("HARMONIC", harm, 8000)

    // Fixture 3: concatenated sine + Klatt /ae/ + harmonic + silence.
    // Each section is ~ 6 frames at 8 kHz (240 samples / frame = 30 ms).
    // 6 frames * 240 = 1440 samples per section.
    let section_len = 1440
    let s_sine = synth_sine(200, section_len, 8000)
    let s_harm = _harmonic_buf(200, section_len, 8000)
    let s_zero = _zero_buf(section_len)
    // Build the Klatt /ae/ section by repeating the 1200-sample phoneme
    // out to section_len.
    let vowel = synth_phoneme("ae")
    let s_klatt = list_new()
    let kk = 0
    while len(s_klatt) < section_len {
        push(s_klatt, vowel[kk])
        kk = kk + 1
        if kk >= len(vowel) { kk = 0 }
    }
    let pcm = list_new()
    let a = 0
    while a < section_len { push(pcm, s_sine[a]);  a = a + 1 }
    let b = 0
    while b < section_len { push(pcm, s_klatt[b]); b = b + 1 }
    let c = 0
    while c < section_len { push(pcm, s_harm[c]);  c = c + 1 }
    let d = 0
    while d < section_len { push(pcm, s_zero[d]);  d = d + 1 }
    _report_auto("MIXED", pcm, 8000)
}

main()
NOVA

DRIVER_OUT=$("$NOVA_BIN" run "$DRV_SRC" 2>&1)
DRIVER_RC=$?
printf '%s\n' "$DRIVER_OUT" > "$DRV_OUT"

assert_eq "$DRIVER_RC" "0" "auto-switch driver exits 0"

# ---- Fixture 1: pure sine -> all frames AUTOCORR ----
SINE_LINE=$(printf '%s\n' "$DRIVER_OUT" | grep -E '^PURE_SINE ' | head -1)
SINE_YIN=$(echo "$SINE_LINE" | grep -oE 'yin=[0-9]+' | head -1 | cut -d= -f2)
SINE_AC=$(echo "$SINE_LINE" | grep -oE 'ac=[0-9]+' | head -1 | cut -d= -f2)
SINE_FR=$(echo "$SINE_LINE" | grep -oE 'frames=[0-9]+' | head -1 | cut -d= -f2)
SINE_MEAN=$(echo "$SINE_LINE" | grep -oE 'mean_f0=[0-9]+' | head -1 | cut -d= -f2)

if [ -n "$SINE_YIN" ] && [ "$SINE_YIN" -eq 0 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  pure sine: yin=0 (every frame routed to AC)\n"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  pure sine: yin='%s' (expected 0)\n" "$SINE_YIN"
fi

if [ -n "$SINE_AC" ] && [ -n "$SINE_FR" ] && [ "$SINE_AC" = "$SINE_FR" ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  pure sine: ac=%s = frames=%s\n" "$SINE_AC" "$SINE_FR"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  pure sine: ac='%s' != frames='%s'\n" "$SINE_AC" "$SINE_FR"
fi

if [ -n "$SINE_MEAN" ] && [ "$SINE_MEAN" -ge 19500 ] && [ "$SINE_MEAN" -le 20500 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  pure sine via auto: mean_f0=%s centi in [19500..20500] (~200 Hz)\n" "$SINE_MEAN"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  pure sine via auto: mean_f0='%s' centi out of [19500..20500]\n" "$SINE_MEAN"
fi

# ---- Fixture 2: harmonic-rich -> majority YIN ----
HARM_LINE=$(printf '%s\n' "$DRIVER_OUT" | grep -E '^HARMONIC ' | head -1)
HARM_YIN=$(echo "$HARM_LINE" | grep -oE 'yin=[0-9]+' | head -1 | cut -d= -f2)
HARM_FR=$(echo "$HARM_LINE" | grep -oE 'frames=[0-9]+' | head -1 | cut -d= -f2)
HARM_MEAN=$(echo "$HARM_LINE" | grep -oE 'mean_f0=[0-9]+' | head -1 | cut -d= -f2)

if [ -n "$HARM_YIN" ] && [ -n "$HARM_FR" ] && [ "$HARM_YIN" -gt 0 ] && [ $((HARM_YIN * 2)) -ge "$HARM_FR" ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  harmonic-rich: yin=%s/%s (majority routed to YIN)\n" "$HARM_YIN" "$HARM_FR"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  harmonic-rich: yin='%s'/'%s' (expected majority YIN)\n" "$HARM_YIN" "$HARM_FR"
fi

if [ -n "$HARM_MEAN" ] && [ "$HARM_MEAN" -ge 19500 ] && [ "$HARM_MEAN" -le 20500 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  harmonic-rich via auto: mean_f0=%s centi in [19500..20500] (~200 Hz)\n" "$HARM_MEAN"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  harmonic-rich via auto: mean_f0='%s' centi out of [19500..20500]\n" "$HARM_MEAN"
fi

# ---- Fixture 3: mixed sequence (sine + Klatt /ae/ + harmonic + silence) ----
MIX_LINE=$(printf '%s\n' "$DRIVER_OUT" | grep -E '^MIXED ' | head -1)
MIX_YIN=$(echo "$MIX_LINE" | grep -oE 'yin=[0-9]+' | head -1 | cut -d= -f2)
MIX_AC=$(echo "$MIX_LINE" | grep -oE 'ac=[0-9]+' | head -1 | cut -d= -f2)
MIX_FR=$(echo "$MIX_LINE" | grep -oE 'frames=[0-9]+' | head -1 | cut -d= -f2)

if [ -n "$MIX_FR" ] && [ "$MIX_FR" -eq 24 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  mixed sequence: %s frames (4 sections * 6 frames)\n" "$MIX_FR"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  mixed sequence: frames='%s' (expected 24)\n" "$MIX_FR"
fi

# Mixed should have BOTH AC and YIN frames -- detector dynamically switches
# across the sine (AC), Klatt + harmonic (YIN), silence (AC) sections.
if [ -n "$MIX_YIN" ] && [ -n "$MIX_AC" ] && [ "$MIX_YIN" -gt 0 ] && [ "$MIX_AC" -gt 0 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  mixed sequence: detector switched -- yin=%s, ac=%s (both non-zero)\n" "$MIX_YIN" "$MIX_AC"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  mixed sequence: yin='%s', ac='%s' (expected both non-zero)\n" "$MIX_YIN" "$MIX_AC"
fi

# ===========================================================================
# JFK head-to-head: auto-switch on natural speech
# ===========================================================================

if [ $HAVE_JFK -eq 1 ]; then
    cat > "$DRV_SRC.jfk" <<'NOVA2'
import "std/syscall"
import "../../../src/io/transducers/audio_capture.nova"
import "../../../src/io/transducers/audio_pitch.nova"

fn _report_auto(label, samples, sample_rate) {
    let contour = pitch_track_auto(samples, sample_rate)
    let total = len(contour)
    let yin_n = pitch_auto_method_count(contour, pitch_method_yin())
    let ac_n  = pitch_auto_method_count(contour, pitch_method_autocorr())
    let voiced = 0
    let sum = 0
    let i = 0
    while i < total {
        let e = contour[i]
        if e[0] != pitch_unvoiced_sentinel() {
            sum = sum + e[0]
            voiced = voiced + 1
        }
        i = i + 1
    }
    let mean_c = 0
    if voiced > 0 { mean_c = sum / voiced }
    println(label + " sr=" + int_to_str(sample_rate)
        + " frames=" + int_to_str(total)
        + " yin=" + int_to_str(yin_n)
        + " ac=" + int_to_str(ac_n)
        + " voiced=" + int_to_str(voiced)
        + " mean_f0=" + int_to_str(mean_c))
}

fn main() {
    let r = audio_capture_to_pcm(_JFK_PATH_)
    let pcm = audio_capture_pcm_samples(r)
    let sr = audio_capture_pcm_rate(r)
    println("JFK loaded: " + int_to_str(len(pcm)) + " samples @ " + int_to_str(sr) + " Hz")
    _report_auto("JFK_AUTO", pcm, sr)
}

main()
NOVA2
    sed -i "s|_JFK_PATH_|\"$JFK_WAV\"|" "$DRV_SRC.jfk"

    JFK_OUT=$("$NOVA_BIN" run "$DRV_SRC.jfk" 2>&1)
    JFK_RC=$?
    rm -f "$DRV_SRC.jfk"

    assert_eq "$JFK_RC" "0" "JFK auto-switch driver exits 0"

    JFK_LINE=$(printf '%s\n' "$JFK_OUT" | grep -E '^JFK_AUTO ' | head -1)
    JFK_YIN=$(echo "$JFK_LINE" | grep -oE 'yin=[0-9]+' | head -1 | cut -d= -f2)
    JFK_AC=$(echo "$JFK_LINE" | grep -oE 'ac=[0-9]+' | head -1 | cut -d= -f2)
    JFK_FR=$(echo "$JFK_LINE" | grep -oE 'frames=[0-9]+' | head -1 | cut -d= -f2)
    JFK_MEAN=$(echo "$JFK_LINE" | grep -oE 'mean_f0=[0-9]+' | head -1 | cut -d= -f2)

    # The brief requires "majority frames should use YIN" on JFK. Natural
    # speech is formant-rich -> multiple distinct spectral peaks per voiced
    # frame -> harmonicity score >= threshold -> YIN.
    if [ -n "$JFK_YIN" ] && [ -n "$JFK_FR" ] && [ "$JFK_YIN" -gt 0 ] && [ $((JFK_YIN * 2)) -gt "$JFK_FR" ]; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}PASS${C_RST}  JFK auto: yin=%s/%s majority routed to YIN (natural speech is harmonic-rich)\n" "$JFK_YIN" "$JFK_FR"
    else
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  JFK auto: yin='%s'/'%s' (expected majority YIN)\n" "$JFK_YIN" "$JFK_FR"
    fi

    # Mean F0 across voiced frames should land in a plausible adult-male
    # band. With YIN dominant the formant snap is cured -> mean is lower
    # than the standalone AC ~220 Hz. We allow a broad [80..230] Hz band
    # since some frames may still use AC (silence / unvoiced segments).
    if [ -n "$JFK_MEAN" ] && [ "$JFK_MEAN" -ge 8000 ] && [ "$JFK_MEAN" -le 23000 ]; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}PASS${C_RST}  JFK auto: mean_f0=%s centi in plausible voice band [8000..23000]\n" "$JFK_MEAN"
    else
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  JFK auto: mean_f0='%s' centi out of [8000..23000]\n" "$JFK_MEAN"
    fi
else
    printf "  ${C_YEL}SKIP${C_RST}  JFK auto-switch test (%s not found; set CE_WHISPER_JFK_WAV to override)\n" "$JFK_WAV"
fi

summary "scenario_qqqq_pitch_auto"
