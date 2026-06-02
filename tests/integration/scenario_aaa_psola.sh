#!/usr/bin/env bash
# Scenario AAA -- R12D: TD-PSOLA pitch shifting + time stretching.

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

it_section "scenario AAA: R12D TD-PSOLA pitch shift + time stretch"

NOVA_BIN="${NOVA_ROOT:-/home/user/NOVA}/nova"
if [ ! -x "$NOVA_BIN" ]; then
    printf "  ${C_RED}ERROR${C_RST}: NOVA launcher not found at %s (set NOVA_ROOT)\n" "$NOVA_BIN" >&2
    FAIL=$((FAIL+1))
    summary "scenario_aaa_psola"
    exit $?
fi

VOWEL_WAV="/tmp/ce_scenario_aaa_vowel.wav"
SHIFT_WAV="/tmp/ce_scenario_aaa_shifted.wav"
STRETCH_WAV="/tmp/ce_scenario_aaa_stretched.wav"
DRV_DIR="$REPO_ROOT/tests/integration/_scenario_aaa_drivers"
DRV_SRC="$DRV_DIR/psola_pipeline_driver.nova"
DRV_OUT="/tmp/ce_scenario_aaa_driver.out"

mkdir -p "$DRV_DIR"
trap 'rm -f "$VOWEL_WAV" "$SHIFT_WAV" "$STRETCH_WAV" "$DRV_OUT"; rm -rf "$DRV_DIR"' EXIT

cat > "$DRV_SRC" <<'NOVA'
import "std/syscall"
import "../../../src/io/effectors/audio_synth.nova"
import "../../../src/io/transducers/audio_capture.nova"
import "../../../src/io/transducers/audio_pitch.nova"
import "../../../src/io/transducers/audio_psola.nova"

fn _report(label, samples, sample_rate) {
    let contour = pitch_track_yin(samples, sample_rate)
    let voiced = pitch_voiced_count(contour)
    let mean_c = pitch_mean_voiced(contour)
    println(label + " samples=" + int_to_str(len(samples))
        + " sample_rate=" + int_to_str(sample_rate)
        + " f0_mean=" + int_to_str(mean_c)
        + " voiced=" + int_to_str(voiced))
}

fn main() {
    let sine = synth_sine(200, 9600, 8000)
    let ok = audio_write_wav(sine, "/tmp/ce_scenario_aaa_vowel.wav")
    println("wrote input wav: " + int_to_str(ok))
    _report("INPUT", sine, 8000)

    let shifted = psola_pitch_shift(sine, 8000, 2000)
    let ok2 = audio_write_wav(shifted, "/tmp/ce_scenario_aaa_shifted.wav")
    println("wrote shifted wav: " + int_to_str(ok2))
    _report("SHIFTED", shifted, 8000)

    let stretched = psola_time_stretch(sine, 8000, 2000)
    let ok3 = audio_write_wav(stretched, "/tmp/ce_scenario_aaa_stretched.wav")
    println("wrote stretched wav: " + int_to_str(ok3))
    _report("STRETCHED", stretched, 8000)
}

main()
NOVA

DRIVER_OUT=$("$NOVA_BIN" run "$DRV_SRC" 2>&1)
DRIVER_RC=$?
printf '%s\n' "$DRIVER_OUT" > "$DRV_OUT"

assert_eq "$DRIVER_RC" "0" "psola pipeline driver exits 0"
assert_match "$DRIVER_OUT" "wrote input wav: 1" "input WAV written"
assert_match "$DRIVER_OUT" "wrote shifted wav: 1" "shifted WAV written"
assert_match "$DRIVER_OUT" "wrote stretched wav: 1" "stretched WAV written"

assert_file_exists "$VOWEL_WAV"   "input WAV exists on disk"
assert_file_exists "$SHIFT_WAV"   "shifted WAV exists on disk"
assert_file_exists "$STRETCH_WAV" "stretched WAV exists on disk"

INPUT_LINE=$(printf '%s\n' "$DRIVER_OUT" | grep -E '^INPUT ' | head -1)
INPUT_MEAN=$(echo "$INPUT_LINE" | grep -oE 'f0_mean=[0-9]+' | head -1 | cut -d= -f2)
if [ -n "$INPUT_MEAN" ] && [ "$INPUT_MEAN" -ge 19800 ] && [ "$INPUT_MEAN" -le 20200 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  INPUT: f0_mean=%s centi in [19800..20200] (~200 Hz)\n" "$INPUT_MEAN"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  INPUT: f0_mean='%s' centi out of [19800..20200]\n" "$INPUT_MEAN"
fi

SHIFTED_LINE=$(printf '%s\n' "$DRIVER_OUT" | grep -E '^SHIFTED ' | head -1)
SHIFTED_MEAN=$(echo "$SHIFTED_LINE" | grep -oE 'f0_mean=[0-9]+' | head -1 | cut -d= -f2)
if [ -n "$SHIFTED_MEAN" ] && [ "$SHIFTED_MEAN" -ge 35000 ] && [ "$SHIFTED_MEAN" -le 45000 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  SHIFTED (2x): f0_mean=%s centi in [35000..45000] (~400 Hz)\n" "$SHIFTED_MEAN"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  SHIFTED (2x): f0_mean='%s' centi out of [35000..45000]\n" "$SHIFTED_MEAN"
fi

STRETCHED_LINE=$(printf '%s\n' "$DRIVER_OUT" | grep -E '^STRETCHED ' | head -1)
STRETCHED_LEN=$(echo "$STRETCHED_LINE" | grep -oE 'samples=[0-9]+' | head -1 | cut -d= -f2)
if [ -n "$STRETCHED_LEN" ] && [ "$STRETCHED_LEN" -ge 17280 ] && [ "$STRETCHED_LEN" -le 21120 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  STRETCHED (2x): samples=%s in [17280..21120] (~2x 9600)\n" "$STRETCHED_LEN"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  STRETCHED (2x): samples='%s' out of [17280..21120]\n" "$STRETCHED_LEN"
fi

require_chat
CHAT_HELP=$(run_chat "/help")
assert_match "$CHAT_HELP" '/pitch_shift' \
    "chat /help advertises the new /pitch_shift command"
assert_match "$CHAT_HELP" 'R12D' \
    "chat /help labels /pitch_shift as R12D"

CHAT_SHIFT=$(run_chat "/pitch_shift $VOWEL_WAV 2000")
assert_match "$CHAT_SHIFT" 'factor=2000' \
    "chat /pitch_shift reports factor=2000"
assert_match "$CHAT_SHIFT" "$VOWEL_WAV" \
    "chat /pitch_shift echoes the WAV path"

CHAT_SHIFT_NOARG=$(run_chat "/pitch_shift")
assert_match "$CHAT_SHIFT_NOARG" '/pitch_shift needs PATH FACTOR' \
    "chat /pitch_shift with no arg prints usage"

CHAT_SHIFT_MISS=$(run_chat "/pitch_shift /tmp/ce_scenario_aaa_nonexistent.wav 2000")
assert_match "$CHAT_SHIFT_MISS" 'pitch_shift FAILED' \
    "chat /pitch_shift on missing WAV -> graceful FAILED"

summary "scenario_aaa_psola"
