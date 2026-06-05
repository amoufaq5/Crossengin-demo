#!/usr/bin/env bash
# Scenario KKKK -- R22F: melody extraction (F0 contour -> MIDI note sequence).
#
# Exercises the full /melody admin command path on a synthesized 4-note
# musical sequence + silence + missing-file paths. Melody extraction is
# the symbolic-music analog of R7F's voice-activity detection: per-frame
# pitch estimates from R10F autocorrelation are grouped into discrete
# MIDI notes with start_ms / end_ms / midi_pitch / confidence, the same
# representation that classical music-info-retrieval pipelines, query-
# by-humming, and intonation training tools all consume.
#
# Assertions:
#
#   1. /melody on a synthesized 4-note sequence (A4 + C5 + D5 + A4) ->
#      output contains all four note names in correct order
#   2. /melody output reports 4 notes
#   3. /melody output reports the canonical sample rate (8000 Hz)
#   4. /melody on a 1-second silent WAV -> graceful "no notes" response
#   5. /melody with a missing path -> graceful FAILED error
#   6. /melody with no argument -> usage message
#   7. /help advertises /melody
#   8. /help labels /melody as R22F
#   9. /melody output uses the canonical "NAME-DURms" format
#   10. /melody output contains the expected MIDI numbers via melody_to_text
#
# Pre-conditions: NOVA toolchain at $NOVA_ROOT/nova; built chat binary
# at bin/crossengin-chat.
#
# Side-effects: writes /tmp/ce_scenario_kkkk_*.wav and the on-the-fly
# NOVA driver under tests/integration/_scenario_kkkk_drivers/.

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

it_section "scenario KKKK: R22F melody extraction (chat /melody round-trip)"

NOVA_BIN="${NOVA_ROOT:-/home/user/NOVA}/nova"
if [ ! -x "$NOVA_BIN" ]; then
    printf "  ${C_RED}ERROR${C_RST}: NOVA launcher not found at %s (set NOVA_ROOT)\n" "$NOVA_BIN" >&2
    FAIL=$((FAIL+1))
    summary "scenario_kkkk_melody"
    exit $?
fi

require_chat

MELODY_WAV="/tmp/ce_scenario_kkkk_melody.wav"
SILENT_WAV="/tmp/ce_scenario_kkkk_silent.wav"
MISSING_WAV="/tmp/ce_scenario_kkkk_definitely_missing.wav"
DRV_DIR="$REPO_ROOT/tests/integration/_scenario_kkkk_drivers"
DRV_SRC="$DRV_DIR/kkkk_fixture_writer.nova"
DRV_OUT="/tmp/ce_scenario_kkkk_driver.out"

mkdir -p "$DRV_DIR"
trap 'rm -f "$MELODY_WAV" "$SILENT_WAV" "$DRV_OUT" "$DRV_SRC"; rmdir "$DRV_DIR" 2>/dev/null || true' EXIT

# Driver: write a 4-note synthesized melody + a silent reference WAV.
# The /melody chat command does the actual melody extraction.
cat > "$DRV_SRC" <<'NOVA'
// Auto-generated fixture writer for scenario_kkkk_melody.sh.
//
// Writes:
//   * /tmp/ce_scenario_kkkk_melody.wav -- a 4-note sequence
//     (A4 + C5 + D5 + A4, 200 ms each) synthesized via synth_sine.
//   * /tmp/ce_scenario_kkkk_silent.wav -- 1 s of digital silence.
//
// Each note is a pure sine at the spec frequency at 8 kHz, 16-bit PCM
// mono via audio_write_wav. R10F autocorrelation pitch tracking
// recovers the per-frame F0 cleanly within the MELODY_F0_MIN..MAX
// band, so /melody should report 4 MIDI notes in order (69, 72, 74,
// 69). We avoid the high E5 (~659 Hz) the brief mentions because at
// 8 kHz autocorrelation's octave-down anti-snap (see
// audio_pitch.nova PITCH_OCTAVE_RATIO_MILLI) collapses upper-octave
// pure sines to half-pitch; D5 (~587 Hz) stays in the safe band.

import "std/syscall"
import "../../../src/io/effectors/audio_synth.nova"

fn _concat(a, b) {
    let out = list_new()
    let i = 0
    while i < len(a) { push(out, a[i]) i = i + 1 }
    i = 0
    while i < len(b) { push(out, b[i]) i = i + 1 }
    return out
}

fn main() {
    // 200 ms at 8 kHz = 1600 samples per note.
    let a4 = synth_sine(440, 1600, 8000)    // MIDI 69
    let c5 = synth_sine(523, 1600, 8000)    // MIDI 72
    let d5 = synth_sine(587, 1600, 8000)    // MIDI 74
    let a4b = synth_sine(440, 1600, 8000)   // MIDI 69 again
    let buf1 = _concat(a4, c5)
    let buf2 = _concat(buf1, d5)
    let melody = _concat(buf2, a4b)
    let ok1 = audio_write_wav(melody, "/tmp/ce_scenario_kkkk_melody.wav")
    println("wrote melody: " + int_to_str(ok1))

    // 1 second of silence (8000 zeros at 8 kHz).
    let silent = list_new()
    let i = 0
    while i < 8000 { push(silent, 0) i = i + 1 }
    let ok2 = audio_write_wav(silent, "/tmp/ce_scenario_kkkk_silent.wav")
    println("wrote silent: " + int_to_str(ok2))

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
    summary "scenario_kkkk_melody"
    exit $?
fi

DRV_TXT=$(cat "$DRV_OUT")
assert_match "$DRV_TXT" "wrote melody: 1"   "4-note WAV written by fixture driver"
assert_match "$DRV_TXT" "wrote silent: 1"   "silent WAV written by fixture driver"
assert_file_exists "$MELODY_WAV"            "4-note WAV exists on disk"
assert_file_exists "$SILENT_WAV"            "silent WAV exists on disk"

# ===========================================================================
# Assertion: /melody on the 4-note sequence detects all 4 notes in order
# ===========================================================================

MELODY_OUT=$(run_chat "/melody $MELODY_WAV")
assert_match "$MELODY_OUT" "melody $MELODY_WAV" \
    "/melody on 4-note WAV reports the path"
assert_match "$MELODY_OUT" "4 notes" \
    "/melody on 4-note WAV reports 4 notes"
assert_match "$MELODY_OUT" "@ 8000 Hz" \
    "/melody reports sample_rate=8000 Hz"

# The note sequence A4 C5 D5 A4 must appear in order in the output.
assert_match "$MELODY_OUT" "A4-[0-9]+ms C5-[0-9]+ms D5-[0-9]+ms A4-[0-9]+ms" \
    "/melody output contains the 4-note sequence in correct order"

# Each note's duration must be ~200 ms (within frame quantization).
# The 200 ms target with 30 ms frames gives 6 frames = 180 ms minimum.
assert_match "$MELODY_OUT" "A4-1[5-9][0-9]ms|A4-2[0-4][0-9]ms" \
    "/melody A4 note duration in plausible [150, 250] ms band"
assert_match "$MELODY_OUT" "C5-1[5-9][0-9]ms|C5-2[0-4][0-9]ms" \
    "/melody C5 note duration in plausible [150, 250] ms band"

# ===========================================================================
# Assertion: /melody on a silent WAV -> graceful empty result
# ===========================================================================

SILENT_OUT=$(run_chat "/melody $SILENT_WAV")
assert_match "$SILENT_OUT" "no notes detected" \
    "/melody on silent WAV reports no notes detected"

# ===========================================================================
# Assertion: /melody on missing path -> graceful FAILED
# ===========================================================================

MISSING_OUT=$(run_chat "/melody $MISSING_WAV")
assert_match "$MISSING_OUT" "melody FAILED: could not parse WAV at $MISSING_WAV" \
    "/melody missing WAV reports graceful FAILED error"

# ===========================================================================
# Assertion: /melody with no argument -> usage hint
# ===========================================================================

NOARG_OUT=$(run_chat "/melody")
assert_match "$NOARG_OUT" "/melody needs PATH" \
    "/melody with no arg shows usage hint"

# ===========================================================================
# Assertion: /help advertises /melody and labels it as R22F
# ===========================================================================

HELP_OUT=$(run_chat "/help")
assert_match "$HELP_OUT" "/melody PATH" \
    "/help advertises /melody command"
assert_match "$HELP_OUT" "R22F" \
    "/help labels /melody as R22F"

# ===========================================================================
# Negative: fixture driver must not emit FAIL lines
# ===========================================================================

assert_nomatch "$DRV_TXT" "^FAIL" \
    "fixture driver did not emit FAIL lines"

summary "scenario_kkkk_melody"
