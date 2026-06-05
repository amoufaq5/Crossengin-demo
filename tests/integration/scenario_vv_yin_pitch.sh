#!/usr/bin/env bash
# Scenario VV -- R11B: YIN-class F0 estimator (cumulative mean normalized
# difference function) -- end-to-end head-to-head against R10F autocorrelation.
#
# YIN (de Cheveigne & Kawahara 2002) is the textbook cure for the
# first-formant snap that R10F's autocorrelation pitch estimator suffers on
# harmonic-rich natural speech. This scenario exercises the new
# pitch_estimate_frame_yin / pitch_track_yin entry points on the JFK
# whisper.cpp sample (16 kHz adult-male voice) and asserts:
#
#   1. R10F autocorrelation reports a mean F0 in the formant-snap region
#      (~220 Hz, not the true ~120-140 Hz glottal F0).
#   2. YIN reports a mean F0 in the plausible adult-male range [80..180] Hz,
#      substantially closer to the textbook ground truth.
#   3. Both algorithms agree (within tolerance) on the pure synthetic
#      fixture (200 Hz sine) -- the YIN extension doesn't regress R10F on
#      simple periodic inputs.
#
# Pre-conditions: NOVA toolchain at $NOVA_ROOT/nova.
# Optional: whisper.cpp's bundled jfk.wav at /tmp/whisper.cpp/samples/jfk.wav
#           (the R8B installer drops it there). Without it the JFK head-to-
#           head SKIPS and only the synthetic-sine assertions run.
# Side-effects: writes /tmp/ce_scenario_vv_sine.wav and the on-the-fly
#               NOVA driver under tests/integration/_scenario_vv_drivers/.

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

it_section "scenario VV: R11B YIN-class F0 vs R10F autocorrelation"

NOVA_BIN="${NOVA_ROOT:-/home/user/NOVA}/nova"
if [ ! -x "$NOVA_BIN" ]; then
    printf "  ${C_RED}ERROR${C_RST}: NOVA launcher not found at %s (set NOVA_ROOT)\n" "$NOVA_BIN" >&2
    FAIL=$((FAIL+1))
    summary "scenario_vv_yin_pitch"
    exit $?
fi

SINE_WAV="/tmp/ce_scenario_vv_sine.wav"
DRV_DIR="$REPO_ROOT/tests/integration/_scenario_vv_drivers"
DRV_SRC="$DRV_DIR/yin_pipeline_driver.nova"
DRV_OUT="/tmp/ce_scenario_vv_driver.out"

JFK_WAV="${CE_WHISPER_JFK_WAV:-/tmp/whisper.cpp/samples/jfk.wav}"
HAVE_JFK=0
if [ -f "$JFK_WAV" ]; then HAVE_JFK=1; fi

mkdir -p "$DRV_DIR"
trap 'rm -f "$SINE_WAV" "$DRV_OUT"; rm -rf "$DRV_DIR"' EXIT

cat > "$DRV_SRC" <<'NOVA'
// Auto-generated YIN vs autocorrelation pipeline driver for
// scenario_vv_yin_pitch.sh.
//
// Steps:
//   1. Synthesize a 200 Hz pure sine (1.5 seconds @ 8 kHz = 12000 samples).
//      Write to /tmp/ce_scenario_vv_sine.wav. Run both pitch_track (R10F)
//      and pitch_track_yin (R11B) -- assert both produce ~200 Hz.
//   2. (Optional, conditional on the bundled JFK wav being installed)
//      Decode the JFK fixture and run BOTH algorithms. Emit one line per
//      algorithm with mean_f0, voiced_count, and range.
//
// Output format:
//   SINE_AC sr=<sr> frames=<n> voiced=<v> mean_f0=<centi> range=<lo>-<hi>
//   SINE_YIN sr=<sr> frames=<n> voiced=<v> mean_f0=<centi> range=<lo>-<hi>
//   JFK_AC sr=<sr> frames=<n> voiced=<v> mean_f0=<centi> range=<lo>-<hi>
//   JFK_YIN sr=<sr> frames=<n> voiced=<v> mean_f0=<centi> range=<lo>-<hi>

import "std/syscall"
import "../../../src/io/effectors/audio_synth.nova"
import "../../../src/io/transducers/audio_capture.nova"
import "../../../src/io/transducers/audio_pitch.nova"

fn _report_ac(label, samples, sample_rate) {
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

fn _report_yin(label, samples, sample_rate) {
    let contour = pitch_track_yin(samples, sample_rate)
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
    // Synthesize a 200 Hz pure sine at 8 kHz (matches audio_synth's rate).
    let sine = synth_sine(200, 12000, 8000)
    let ok = audio_write_wav(sine, "/tmp/ce_scenario_vv_sine.wav")
    println("wrote sine wav: " + int_to_str(ok))

    // Re-load to exercise the WAV path.
    let r = audio_capture_to_pcm("/tmp/ce_scenario_vv_sine.wav")
    let pcm = audio_capture_pcm_samples(r)
    let sr = audio_capture_pcm_rate(r)
    _report_ac("SINE_AC", pcm, sr)
    _report_yin("SINE_YIN", pcm, sr)
}

main()
NOVA

DRIVER_OUT=$("$NOVA_BIN" run "$DRV_SRC" 2>&1)
DRIVER_RC=$?
printf '%s\n' "$DRIVER_OUT" > "$DRV_OUT"

assert_eq "$DRIVER_RC" "0" "YIN pipeline driver exits 0"
assert_match "$DRIVER_OUT" "wrote sine wav: 1" "sine WAV written"
assert_file_exists "$SINE_WAV" "sine WAV exists on disk"

# Sine fixture: 200 Hz @ 8 kHz. Both algorithms should hit mean F0 in the
# tight 19500-20500 centi-Hz band (200 Hz +/- 5 Hz).
SINE_AC_LINE=$(printf '%s\n' "$DRIVER_OUT" | grep -E '^SINE_AC ' | head -1)
SINE_AC_MEAN=$(echo "$SINE_AC_LINE" | grep -oE 'mean_f0=[0-9]+' | head -1 | cut -d= -f2)
if [ -n "$SINE_AC_MEAN" ] && [ "$SINE_AC_MEAN" -ge 19500 ] && [ "$SINE_AC_MEAN" -le 20500 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  R10F AC sine: mean_f0=%s centi in [19500..20500]\n" "$SINE_AC_MEAN"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  R10F AC sine: mean_f0='%s' centi out of [19500..20500]\n" "$SINE_AC_MEAN"
fi

SINE_YIN_LINE=$(printf '%s\n' "$DRIVER_OUT" | grep -E '^SINE_YIN ' | head -1)
SINE_YIN_MEAN=$(echo "$SINE_YIN_LINE" | grep -oE 'mean_f0=[0-9]+' | head -1 | cut -d= -f2)
if [ -n "$SINE_YIN_MEAN" ] && [ "$SINE_YIN_MEAN" -ge 19500 ] && [ "$SINE_YIN_MEAN" -le 20500 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  YIN sine: mean_f0=%s centi in [19500..20500]\n" "$SINE_YIN_MEAN"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  YIN sine: mean_f0='%s' centi out of [19500..20500]\n" "$SINE_YIN_MEAN"
fi

# ===========================================================================
# JFK head-to-head: R10F autocorrelation vs R11B YIN
# ===========================================================================

if [ $HAVE_JFK -eq 1 ]; then
    cat > "$DRV_SRC.jfk" <<'NOVA2'
import "std/syscall"
import "../../../src/io/transducers/audio_capture.nova"
import "../../../src/io/transducers/audio_pitch.nova"

fn _report_ac(label, samples, sample_rate) {
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

fn _report_yin(label, samples, sample_rate) {
    let contour = pitch_track_yin(samples, sample_rate)
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
    let r = audio_capture_to_pcm(_JFK_PATH_)
    let pcm = audio_capture_pcm_samples(r)
    let sr = audio_capture_pcm_rate(r)
    println("JFK loaded: " + int_to_str(len(pcm)) + " samples @ " + int_to_str(sr) + " Hz")
    _report_ac("JFK_AC", pcm, sr)
    _report_yin("JFK_YIN", pcm, sr)
}

main()
NOVA2
    # Patch the JFK path into the driver.
    sed -i "s|_JFK_PATH_|\"$JFK_WAV\"|" "$DRV_SRC.jfk"

    JFK_OUT=$("$NOVA_BIN" run "$DRV_SRC.jfk" 2>&1)
    JFK_RC=$?
    rm -f "$DRV_SRC.jfk"

    assert_eq "$JFK_RC" "0" "JFK driver exits 0"

    # R10F autocorrelation on JFK: expected ~220 Hz (formant snap).
    # Accept [150..280] Hz mean (centi-Hz [15000..28000]) -- the formant-
    # snap region.
    JFK_AC_LINE=$(printf '%s\n' "$JFK_OUT" | grep -E '^JFK_AC ' | head -1)
    JFK_AC_MEAN=$(echo "$JFK_AC_LINE" | grep -oE 'mean_f0=[0-9]+' | head -1 | cut -d= -f2)
    if [ -n "$JFK_AC_MEAN" ] && [ "$JFK_AC_MEAN" -ge 15000 ] && [ "$JFK_AC_MEAN" -le 28000 ]; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}PASS${C_RST}  R10F AC JFK: mean_f0=%s centi in [15000..28000] (~200-220 Hz formant snap)\n" "$JFK_AC_MEAN"
    else
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  R10F AC JFK: mean_f0='%s' centi out of [15000..28000]\n" "$JFK_AC_MEAN"
    fi

    # YIN on JFK: expected in the adult-male band [80..180] Hz
    # (centi-Hz [8000..18000]). This is the KEY assertion -- it
    # demonstrates that YIN cures the formant snap.
    JFK_YIN_LINE=$(printf '%s\n' "$JFK_OUT" | grep -E '^JFK_YIN ' | head -1)
    JFK_YIN_MEAN=$(echo "$JFK_YIN_LINE" | grep -oE 'mean_f0=[0-9]+' | head -1 | cut -d= -f2)
    if [ -n "$JFK_YIN_MEAN" ] && [ "$JFK_YIN_MEAN" -ge 8000 ] && [ "$JFK_YIN_MEAN" -le 18000 ]; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}PASS${C_RST}  R11B YIN JFK: mean_f0=%s centi in adult-male [80..180] Hz band\n" "$JFK_YIN_MEAN"
    else
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  R11B YIN JFK: mean_f0='%s' centi out of [8000..18000]\n" "$JFK_YIN_MEAN"
    fi

    # YIN should report STRICTLY LOWER mean F0 than R10F on JFK (it
    # cures the formant snap to a lower, true F0).
    if [ -n "$JFK_YIN_MEAN" ] && [ -n "$JFK_AC_MEAN" ] && [ "$JFK_YIN_MEAN" -lt "$JFK_AC_MEAN" ]; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}PASS${C_RST}  YIN F0 (%s) < AC F0 (%s) on JFK -- formant snap cured\n" "$JFK_YIN_MEAN" "$JFK_AC_MEAN"
    else
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  YIN F0 (%s) should be < AC F0 (%s) on JFK\n" "$JFK_YIN_MEAN" "$JFK_AC_MEAN"
    fi
else
    printf "  ${C_YEL}SKIP${C_RST}  JFK head-to-head (%s not found; set CE_WHISPER_JFK_WAV to override)\n" "$JFK_WAV"
fi

summary "scenario_vv_yin_pitch"
