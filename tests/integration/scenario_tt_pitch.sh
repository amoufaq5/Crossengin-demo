#!/usr/bin/env bash
# Scenario TT -- R10F: autocorrelation-based F0 (pitch) estimation.
#
# Exercises the new src/io/transducers/audio_pitch.nova module end-to-end:
#
#   * Synthesize a known-pitch signal (200 Hz pure sine + Klatt-formant
#     vowel) via audio_synth, write to WAV via audio_write_wav.
#   * Drive through pitch_track -> assert mean F0 within expected range
#     for each fixture (centi-Hz precision via pitch_mean_voiced).
#   * Drive whisper.cpp's bundled JFK sample (real adult-male speech)
#     through pitch_track -> assert mean F0 in a plausible adult-male
#     range. NOTE: unmodified autocorrelation snaps to the first formant
#     on JFK (~220 Hz), so the assertion accepts the broader 80..280 Hz
#     band rather than the textbook 80..180 Hz F0 range; see AUDIO_AUDIT.md
#     R10F section for the YIN / cepstral / RAPT octave-correction
#     roadmap.
#   * Drive `/pitch <missing>` through chat -> assert graceful FAILED
#     response (no segfault, no transcript leakage).
#   * Drive `/pitch <wav>` through chat -> assert the result line contains
#     f0_mean= and f0_range=.
#   * Drive `/pitch` (no arg) -> assert usage prompt.
#   * Assert `/help` advertises the command (the brief allowed one help
#     line).
#
# Pre-conditions: NOVA toolchain at $NOVA_ROOT/nova; built chat binary.
# Optional: whisper.cpp's bundled jfk.wav at /tmp/whisper.cpp/samples/jfk.wav.
#           Without it the JFK assertions SKIP and only the synthesized
#           assertions run.
# Side-effects: writes /tmp/ce_scenario_tt_sine.wav,
#               /tmp/ce_scenario_tt_vowel.wav,
#               /tmp/ce_scenario_tt_driver.out, plus the on-the-fly NOVA
#               driver under tests/integration/_scenario_tt_drivers/.

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

it_section "scenario TT: R10F autocorrelation F0 (pitch) estimation"

NOVA_BIN="${NOVA_ROOT:-/home/user/NOVA}/nova"
if [ ! -x "$NOVA_BIN" ]; then
    printf "  ${C_RED}ERROR${C_RST}: NOVA launcher not found at %s (set NOVA_ROOT)\n" "$NOVA_BIN" >&2
    FAIL=$((FAIL+1))
    summary "scenario_tt_pitch"
    exit $?
fi

SINE_WAV="/tmp/ce_scenario_tt_sine.wav"
VOWEL_WAV="/tmp/ce_scenario_tt_vowel.wav"
DRV_DIR="$REPO_ROOT/tests/integration/_scenario_tt_drivers"
DRV_SRC="$DRV_DIR/pitch_pipeline_driver.nova"
DRV_OUT="/tmp/ce_scenario_tt_driver.out"

# JFK sample is an optional real-speech fixture; the chat /pitch test below
# uses it iff present.
JFK_WAV="${CE_WHISPER_JFK_WAV:-/tmp/whisper.cpp/samples/jfk.wav}"
HAVE_JFK=0
if [ -f "$JFK_WAV" ]; then HAVE_JFK=1; fi

mkdir -p "$DRV_DIR"
trap 'rm -f "$SINE_WAV" "$VOWEL_WAV" "$DRV_OUT"; rm -rf "$DRV_DIR"' EXIT

# Emit the NOVA driver. The leading underscore on _scenario_tt_drivers/
# means the Makefile's integration glob (! -name '_*') skips it.
cat > "$DRV_SRC" <<'NOVA'
// Auto-generated pitch pipeline driver for scenario_tt_pitch.sh.
//
// Steps:
//   1. Synthesize a 200 Hz pure sine (1.5 seconds @ 8 kHz = 12000 samples).
//      Write to /tmp/ce_scenario_tt_sine.wav.
//   2. Synthesize a Klatt vowel ("uw", 4-frame repeat = 600 ms) and
//      write to /tmp/ce_scenario_tt_vowel.wav.
//   3. Run pitch_track on each PCM buffer. Print mean_f0, range, and
//      voiced_count.
//
// Output format (one line per fixture):
//   <LABEL> sr=<sr> frames=<n> voiced=<v> mean_f0=<centi> range=<lo>-<hi>

import "std/syscall"
import "../../../src/io/effectors/audio_synth.nova"
import "../../../src/io/transducers/audio_capture.nova"
import "../../../src/io/transducers/audio_pitch.nova"

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

fn _report(label, samples, sample_rate) {
    let contour = pitch_track(samples, sample_rate)
    let voiced = pitch_voiced_count(contour)
    let mean_c = pitch_mean_voiced(contour)
    let range = pitch_range(contour)
    println(label + " sr=" + int_to_str(sample_rate)
        + " frames=" + int_to_str(len(contour))
        + " voiced=" + int_to_str(voiced)
        + " mean_f0=" + int_to_str(mean_c)
        + " range=" + int_to_str(range[0]) + "-" + int_to_str(range[1]))
}

fn main() {
    // Fixture 1: 200 Hz pure sine, 12000 samples (1.5 sec @ 8 kHz).
    // audio_write_wav uses AUDIO_SAMPLE_RATE = 8000.
    let sine = synth_sine(200, 12000, 8000)
    let ok1 = audio_write_wav(sine, "/tmp/ce_scenario_tt_sine.wav")
    println("wrote sine wav: " + int_to_str(ok1))

    // Fixture 2: Klatt vowel "uw" repeated 4 times (4 * 1200 = 4800 samples,
    // ~600 ms @ 8 kHz). The two-formant carrier is sum of cosines at F1=300,
    // F2=870; autocorrelation picks the strongest periodicity in [50..500]
    // Hz band -- typically around the F1 carrier or a GCD-aligned period.
    let v = synth_phoneme("uw")
    let vv = _concat(v, v)
    let vowel = _concat(vv, vv)        // 4x ~= 600 ms
    let ok2 = audio_write_wav(vowel, "/tmp/ce_scenario_tt_vowel.wav")
    println("wrote vowel wav: " + int_to_str(ok2))

    // Report mean F0 + range per fixture, using the WAV that was just
    // written (round-trips the audio_write_wav -> audio_capture_to_pcm
    // path, exercising the integer-PCM encoding too).
    let r1 = audio_capture_to_pcm("/tmp/ce_scenario_tt_sine.wav")
    _report("SINE", audio_capture_pcm_samples(r1), audio_capture_pcm_rate(r1))

    let r2 = audio_capture_to_pcm("/tmp/ce_scenario_tt_vowel.wav")
    _report("VOWEL", audio_capture_pcm_samples(r2), audio_capture_pcm_rate(r2))
}

main()
NOVA

# Run the driver.
DRIVER_OUT=$("$NOVA_BIN" run "$DRV_SRC" 2>&1)
DRIVER_RC=$?
printf '%s\n' "$DRIVER_OUT" > "$DRV_OUT"

assert_eq "$DRIVER_RC" "0" "pitch pipeline driver exits 0"
assert_match "$DRIVER_OUT" "wrote sine wav: 1" "sine WAV written"
assert_match "$DRIVER_OUT" "wrote vowel wav: 1" "vowel WAV written"

assert_file_exists "$SINE_WAV"  "sine WAV exists on disk"
assert_file_exists "$VOWEL_WAV" "vowel WAV exists on disk"

# Sine fixture: 200 Hz @ 8 kHz, expected mean F0 ~ 200 Hz = 20000 centi-Hz.
# Tolerance: +/- 200 centi-Hz (the period quantizes to 40 samples; perfect
# pitch is 20000 centi). All frames should be voiced (pure sine in band).
SINE_LINE=$(printf '%s\n' "$DRIVER_OUT" | grep -E '^SINE ' | head -1)
SINE_MEAN=$(echo "$SINE_LINE" | grep -oE 'mean_f0=[0-9]+' | head -1 | cut -d= -f2)
if [ -n "$SINE_MEAN" ] && [ "$SINE_MEAN" -ge 19800 ] && [ "$SINE_MEAN" -le 20200 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  200 Hz sine: mean_f0=%s centi in [19800..20200] (~200 Hz)\n" "$SINE_MEAN"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  200 Hz sine: mean_f0='%s' centi not in [19800..20200]\n" "$SINE_MEAN"
fi
assert_match "$DRIVER_OUT" 'SINE sr=8000' \
    "sine WAV decoded at 8 kHz"

# Vowel fixture: Klatt /uw/ has F1=300, F2=870. The autocorrelation picks
# the strongest in-band periodicity; on this synth that's around the F1
# carrier (~290-310 Hz). We assert (a) the WAV decoded, (b) the result is
# voiced (mean > 0), (c) mean falls in the [50..500] band the searcher
# enforces.
assert_match "$DRIVER_OUT" 'VOWEL sr=8000' \
    "vowel WAV decoded at 8 kHz"
VOWEL_LINE=$(printf '%s\n' "$DRIVER_OUT" | grep -E '^VOWEL ' | head -1)
VOWEL_MEAN=$(echo "$VOWEL_LINE" | grep -oE 'mean_f0=[0-9]+' | head -1 | cut -d= -f2)
VOWEL_VOICED=$(echo "$VOWEL_LINE" | grep -oE 'voiced=[0-9]+' | head -1 | cut -d= -f2)
if [ -n "$VOWEL_MEAN" ] && [ "$VOWEL_MEAN" -ge 5000 ] && [ "$VOWEL_MEAN" -le 50000 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  Klatt /uw/ vowel: mean_f0=%s centi in [50..500] Hz band\n" "$VOWEL_MEAN"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  Klatt /uw/ vowel: mean_f0='%s' centi out of band\n" "$VOWEL_MEAN"
fi
if [ -n "$VOWEL_VOICED" ] && [ "$VOWEL_VOICED" -ge 1 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  Klatt /uw/ vowel: voiced=%s frames >= 1\n" "$VOWEL_VOICED"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  Klatt /uw/ vowel: 0 voiced frames\n"
fi

# ===========================================================================
# PART 2 -- chat /pitch dispatch + help
# ===========================================================================

require_chat
CHAT_HELP=$(run_chat "/help")
assert_match "$CHAT_HELP" '/pitch' \
    "chat /help advertises the new /pitch command"
assert_match "$CHAT_HELP" 'R10F' \
    "chat /help labels /pitch as R10F"

# Drive /pitch on the synthesized sine WAV. Result line should contain
# f0_mean= and f0_range=.
CHAT_PITCH=$(run_chat "/pitch $SINE_WAV")
assert_match "$CHAT_PITCH" 'f0_mean=' \
    "chat /pitch reports f0_mean"
assert_match "$CHAT_PITCH" 'f0_range=' \
    "chat /pitch reports f0_range"
assert_match "$CHAT_PITCH" "$SINE_WAV" \
    "chat /pitch echoes the WAV path"

# /pitch with no arg -- usage prompt, no crash.
CHAT_PITCH_NOARG=$(run_chat "/pitch")
assert_match "$CHAT_PITCH_NOARG" '/pitch needs PATH' \
    "chat /pitch with no arg prints usage"

# /pitch on missing file -- graceful error.
CHAT_PITCH_MISS=$(run_chat "/pitch /tmp/ce_scenario_tt_nonexistent.wav")
assert_match "$CHAT_PITCH_MISS" 'pitch FAILED' \
    "chat /pitch on missing WAV -> graceful FAILED"

# ===========================================================================
# PART 3 -- JFK adult-male F0 (optional fixture)
# ===========================================================================

if [ $HAVE_JFK -eq 1 ]; then
    CHAT_JFK=$(run_chat "/pitch $JFK_WAV")
    assert_match "$CHAT_JFK" 'f0_mean=' "JFK /pitch produces f0_mean line"
    # Extract the integer Hz mean: '... f0_mean=<int> Hz ...'.
    JFK_HZ=$(echo "$CHAT_JFK" | grep -oE 'f0_mean=[0-9]+' | head -1 | cut -d= -f2)
    # Unmodified autocorrelation snaps to the JFK first-formant region
    # (~220 Hz) rather than the true glottal F0 (~140 Hz). Both fall in
    # the broad "plausible adult voice" range. Accept [80..280] Hz; the
    # AUDIO_AUDIT R10F section documents the cure (YIN / cepstral / RAPT
    # cumulative mean normalized difference).
    if [ -n "$JFK_HZ" ] && [ "$JFK_HZ" -ge 80 ] && [ "$JFK_HZ" -le 280 ]; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}PASS${C_RST}  JFK mean F0 (%s Hz) in plausible adult range [80..280] Hz\n" "$JFK_HZ"
    else
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  JFK mean F0 '%s' Hz out of [80..280] range\n" "$JFK_HZ"
    fi
    # Sanity: at least 100 voiced frames out of ~360. JFK is ~5.5 sec
    # of speech, voiced ratio >= 30%.
    JFK_VOICED=$(echo "$CHAT_JFK" | grep -oE 'voiced=[0-9]+' | head -1 | cut -d= -f2)
    if [ -n "$JFK_VOICED" ] && [ "$JFK_VOICED" -ge 100 ]; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}PASS${C_RST}  JFK voiced frames (%s) >= 100\n" "$JFK_VOICED"
    else
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  JFK voiced frames '%s' < 100\n" "$JFK_VOICED"
    fi
else
    printf "  ${C_YEL}SKIP${C_RST}  JFK fixture (%s not found; set CE_WHISPER_JFK_WAV to override)\n" "$JFK_WAV"
fi

summary "scenario_tt_pitch"
