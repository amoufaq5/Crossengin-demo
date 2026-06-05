#!/usr/bin/env bash
# Scenario UUU -- R18C wake-word detection chat round-trip via DTW on
# MFCC sequences.
#
# Exercises the full /wake_train + /wake admin command pair against
# synthetic Klatt diphthong fixtures. Wake-word detection (DTW on MFCC
# templates) is the canonical classical-DSP application of the R17B
# MFCC front end -- a non-LLM, integer-only "did the user say the
# magic phrase?" gate.
#
# Assertions:
#
#   1. fixture driver writes /ay ey/ + /uw ow/ + noise fixtures
#   2. /wake_train </ay ey/.wav> -> template written with frame count
#   3. /wake </ay ey/.wav> on the same audio -> detected=true, distance=0
#   4. /wake </uw ow/.wav> different utterance -> detected=false
#   5. /wake <noise.wav> -> detected=false (VAD interlock or DTW high)
#   6. /wake_train </missing/> -> graceful error
#   7. /wake_train (no arg) -> usage hint
#   8. /wake (no arg) -> usage hint
#   9. /wake before any /wake_train (template missing) -> graceful error
#  10. round-trip distance reported with 'milli' unit
#
# Pre-conditions: NOVA toolchain at $NOVA_ROOT/nova; built chat binary
# at bin/crossengin-chat.
#
# Side-effects: writes /tmp/ce_scenario_uuu_*.wav, /tmp/wakeword.template,
# and the on-the-fly NOVA driver under tests/integration/_scenario_uuu_drivers/.

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

it_section "scenario UUU: R18C wake-word DTW chat /wake_train + /wake round-trip"

NOVA_BIN="${NOVA_ROOT:-/home/user/NOVA}/nova"
if [ ! -x "$NOVA_BIN" ]; then
    printf "  ${C_RED}ERROR${C_RST}: NOVA launcher not found at %s (set NOVA_ROOT)\n" "$NOVA_BIN" >&2
    FAIL=$((FAIL+1))
    summary "scenario_uuu_wakeword"
    exit $?
fi

require_chat

WAKE_WAV="/tmp/ce_scenario_uuu_wake.wav"
NONWAKE_WAV="/tmp/ce_scenario_uuu_nonwake.wav"
NOISE_WAV="/tmp/ce_scenario_uuu_noise.wav"
MISSING_WAV="/tmp/ce_scenario_uuu_definitely_missing.wav"
TEMPLATE_PATH="/tmp/wakeword.template"
DRV_DIR="$REPO_ROOT/tests/integration/_scenario_uuu_drivers"
DRV_SRC="$DRV_DIR/uuu_fixture_writer.nova"
DRV_OUT="/tmp/ce_scenario_uuu_driver.out"

mkdir -p "$DRV_DIR"
# Clean up: pre-clear the template so the "no template" assertion runs cleanly,
# and remove fixtures on exit.
rm -f "$TEMPLATE_PATH"
trap 'rm -f "$WAKE_WAV" "$NONWAKE_WAV" "$NOISE_WAV" "$MISSING_WAV" "$DRV_OUT" "$DRV_SRC" "$TEMPLATE_PATH"; rmdir "$DRV_DIR" 2>/dev/null || true' EXIT

# Driver: write three fixtures.
#   wake.wav    -- the wake-word reference: Klatt /ay ey/ diphthong pair
#                  (~2400 samples @ 8 kHz, 300 ms; sounds like "Hi" "May").
#   nonwake.wav -- a different vowel sequence: /uw ow/, distinct formants
#                  so the MFCC vectors are far apart.
#   noise.wav   -- pure-zero "noise" (technically silence here; the VAD
#                  interlock catches it the same way it would catch real
#                  white noise that fails the ZCR ceiling).
cat > "$DRV_SRC" <<'NOVA'
// Auto-generated fixture writer for scenario_uuu_wakeword.sh.
//
// Writes three WAV fixtures: the wake-word reference (Klatt /ay ey/),
// a non-matching utterance (Klatt /uw ow/), and a silence "noise"
// buffer that the VAD interlock will reject.

import "std/syscall"
import "../../../src/io/effectors/audio_synth.nova"

fn _concat(a, b) {
    let out = list_new()
    let i = 0
    while i < len(a) { push(out, a[i]); i = i + 1 }
    i = 0
    while i < len(b) { push(out, b[i]); i = i + 1 }
    return out
}

fn _zero_buf(n) {
    let b = list_new()
    let i = 0
    while i < n { push(b, 0); i = i + 1 }
    return b
}

fn main() {
    let ay = synth_phoneme_klatt("ay")
    let ey = synth_phoneme_klatt("ey")
    let wake_pcm = _concat(ay, ey)
    let ok1 = audio_write_wav(wake_pcm, "/tmp/ce_scenario_uuu_wake.wav")
    println("wrote wake: " + int_to_str(ok1))

    let uw = synth_phoneme_klatt("uw")
    let ow = synth_phoneme_klatt("ow")
    let nonwake_pcm = _concat(uw, ow)
    let ok2 = audio_write_wav(nonwake_pcm, "/tmp/ce_scenario_uuu_nonwake.wav")
    println("wrote nonwake: " + int_to_str(ok2))

    let silence = _zero_buf(2400)
    let ok3 = audio_write_wav(silence, "/tmp/ce_scenario_uuu_noise.wav")
    println("wrote noise: " + int_to_str(ok3))

    println("driver complete")
}

main()
NOVA

"$NOVA_BIN" run "$DRV_SRC" > "$DRV_OUT" 2>&1
DRIVER_RC=$?

if [ "$DRIVER_RC" -ne 0 ]; then
    printf "  ${C_RED}FAIL${C_RST}  fixture driver exited non-zero (rc=%d). Output:\n" "$DRIVER_RC"
    sed 's/^/        /' "$DRV_OUT"
    FAIL=$((FAIL+1))
    summary "scenario_uuu_wakeword"
    exit $?
fi

DRV_TXT=$(cat "$DRV_OUT")
assert_match "$DRV_TXT" "wrote wake: 1"     "wake-word WAV written by fixture driver"
assert_match "$DRV_TXT" "wrote nonwake: 1"  "non-wake-word WAV written by fixture driver"
assert_match "$DRV_TXT" "wrote noise: 1"    "noise (silence) WAV written by fixture driver"
assert_file_exists "$WAKE_WAV"    "wake-word WAV exists on disk"
assert_file_exists "$NONWAKE_WAV" "non-wake-word WAV exists on disk"
assert_file_exists "$NOISE_WAV"   "noise WAV exists on disk"

# ===========================================================================
# Assertion: /wake before any /wake_train -> graceful error
# ===========================================================================

WAKE_BEFORE=$(run_chat "/wake $WAKE_WAV")
assert_match "$WAKE_BEFORE" "wake FAILED: no template at $TEMPLATE_PATH" \
    "/wake without prior train reports missing-template error"

# ===========================================================================
# Assertion: /wake_train succeeds on the wake-word reference
# ===========================================================================

TRAIN_OUT=$(run_chat "/wake_train $WAKE_WAV")
assert_match "$TRAIN_OUT" "wake_train $WAKE_WAV: frames=[0-9]+" \
    "/wake_train reports a frame count"
assert_match "$TRAIN_OUT" "n_mfcc=13" \
    "/wake_train reports n_mfcc=13"
assert_match "$TRAIN_OUT" "saved to $TEMPLATE_PATH" \
    "/wake_train reports template saved to default path"
assert_file_exists "$TEMPLATE_PATH" "template file exists on disk after /wake_train"

# ===========================================================================
# Assertion: /wake on the SAME audio detects with distance=0
# ===========================================================================

WAKE_SAME=$(run_chat "/wake $WAKE_WAV")
assert_match "$WAKE_SAME" "wake $WAKE_WAV: detected=true" \
    "/wake on training audio -> detected=true"
assert_match "$WAKE_SAME" "distance=0 milli" \
    "/wake on training audio -> distance=0 (DTW perfect alignment)"

# ===========================================================================
# Assertion: /wake on DIFFERENT audio fails to detect
# ===========================================================================

WAKE_DIFF=$(run_chat "/wake $NONWAKE_WAV")
assert_match "$WAKE_DIFF" "wake $NONWAKE_WAV: detected=false" \
    "/wake on different utterance -> detected=false"
assert_match "$WAKE_DIFF" "distance=[0-9]+ milli" \
    "/wake on different utterance reports a numeric distance in milli"

# ===========================================================================
# Assertion: /wake on noise / silence rejected (VAD interlock)
# ===========================================================================

WAKE_NOISE=$(run_chat "/wake $NOISE_WAV")
assert_match "$WAKE_NOISE" "wake $NOISE_WAV: detected=false" \
    "/wake on silence/noise -> detected=false (VAD interlock)"

# ===========================================================================
# Assertion: error paths
# ===========================================================================

TRAIN_MISSING=$(run_chat "/wake_train $MISSING_WAV")
assert_match "$TRAIN_MISSING" "wake_train FAILED: could not parse WAV at $MISSING_WAV" \
    "/wake_train missing WAV reports graceful error"

TRAIN_NOARG=$(run_chat "/wake_train")
assert_match "$TRAIN_NOARG" "/wake_train needs PATH" \
    "/wake_train with no arg shows usage hint"

WAKE_NOARG=$(run_chat "/wake")
assert_match "$WAKE_NOARG" "/wake needs PATH" \
    "/wake with no arg shows usage hint"

# ===========================================================================
# Negative: fixture driver must not emit FAIL lines
# ===========================================================================

assert_nomatch "$DRV_TXT" "^FAIL" \
    "fixture driver did not emit FAIL lines"

summary "scenario_uuu_wakeword"
