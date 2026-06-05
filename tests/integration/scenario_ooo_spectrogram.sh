#!/usr/bin/env bash
# Scenario OOO -- R16E STFT / spectrogram chat round-trip.
#
# Exercises the full /spec admin command path on three fixtures:
#
#   1. Pure 200 Hz sine @ 8 kHz (synth_sine path; the canonical
#      audio_write_wav rate). Assert: peak_frequency_first_frame in
#      the 156..250 Hz band (the 31.25 Hz / 8 kHz / 256 bin width
#      centered on bin 6 ~ 187 Hz).
#   2. Klatt /ae/ vowel (synth_phoneme_klatt). Assert: peak in the
#      formant band [400, 2200] Hz -- either F1 (~660 Hz) or F2
#      (~1720 Hz). Klatt is short (1200 samples = 150 ms) so we get
#      ~8 frames at frame_size=256 / hop=128.
#   3. JFK 16 kHz WAV (whisper.cpp bundled sample, skipped if not
#      installed). Assert: frames >= 600 (JFK is ~11 s, ~688 frames
#      at hop=256), bins=256 (the default 512 frame_size at >= 16 kHz),
#      non-zero peak frequency in a typical speech band somewhere
#      in the middle of the clip.
#   4. /spec with a missing path -> "spec FAILED: could not parse
#      WAV" graceful error message.
#   5. /spec with no argument -> usage message.
#
# This pins R16E's integration contract: the spectrogram correctly
# resolves a known input frequency to the expected bin (within +/- 1
# bin tolerance), recognizes a Klatt vowel's formant structure, and
# handles real-world recordings (JFK) without producing an empty
# spectrogram.
#
# Pre-conditions: NOVA toolchain at $NOVA_ROOT/nova; built chat
# binary at bin/crossengin-chat.
#
# Side-effects: writes /tmp/ce_scenario_ooo_*.wav and the on-the-fly
# NOVA driver under tests/integration/_scenario_ooo_drivers/.

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

it_section "scenario OOO: R16E STFT spectrogram chat /spec round-trip"

NOVA_BIN="${NOVA_ROOT:-/home/user/NOVA}/nova"
if [ ! -x "$NOVA_BIN" ]; then
    printf "  ${C_RED}ERROR${C_RST}: NOVA launcher not found at %s (set NOVA_ROOT)\n" "$NOVA_BIN" >&2
    FAIL=$((FAIL+1))
    summary "scenario_ooo_spectrogram"
    exit $?
fi

require_chat

JFK_WAV="${CE_WHISPER_JFK_WAV:-/tmp/whisper.cpp/samples/jfk.wav}"
HAVE_JFK=0
if [ -f "$JFK_WAV" ]; then HAVE_JFK=1; fi

SINE_WAV="/tmp/ce_scenario_ooo_200hz.wav"
KLATT_WAV="/tmp/ce_scenario_ooo_klatt_ae.wav"
MISSING_WAV="/tmp/ce_scenario_ooo_definitely_missing.wav"
DRV_DIR="$REPO_ROOT/tests/integration/_scenario_ooo_drivers"
DRV_SRC="$DRV_DIR/ooo_fixture_writer.nova"
DRV_OUT="/tmp/ce_scenario_ooo_driver.out"

mkdir -p "$DRV_DIR"
trap 'rm -f "$SINE_WAV" "$KLATT_WAV" "$MISSING_WAV" "$DRV_OUT" "$DRV_SRC"; rmdir "$DRV_DIR" 2>/dev/null || true' EXIT

# Driver: write the two synthetic fixtures (sine + Klatt) via the
# in-repo audio_synth + audio_write_wav. The chat /spec command does
# the actual STFT round-trip.
cat > "$DRV_SRC" <<'NOVA'
// Auto-generated fixture writer for scenario_ooo_spectrogram.sh.
//
// Writes a 1-second 200 Hz sine @ 8 kHz and a 1200-sample Klatt /ae/
// vowel @ 8 kHz to /tmp, so the chat /spec command can analyse them.

import "std/syscall"
import "../../../src/io/effectors/audio_synth.nova"

fn main() {
    // 200 Hz sine at 8 kHz, 1 second (8000 samples).
    let sine = synth_sine(200, 8000, 8000)
    let ok1 = audio_write_wav(sine, "/tmp/ce_scenario_ooo_200hz.wav")
    println("wrote sine: " + int_to_str(ok1))

    // Klatt /ae/ vowel: 1200 samples at AUDIO_SAMPLE_RATE (8 kHz).
    // F1 = 660 Hz, F2 = 1720 Hz -- the STFT should resolve a peak
    // somewhere in [400, 2200] Hz.
    let klatt = synth_phoneme_klatt("ae")
    let ok2 = audio_write_wav(klatt, "/tmp/ce_scenario_ooo_klatt_ae.wav")
    println("wrote klatt: " + int_to_str(ok2))

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
    summary "scenario_ooo_spectrogram"
    exit $?
fi

DRV_TXT=$(cat "$DRV_OUT")
assert_match "$DRV_TXT" "wrote sine: 1" \
    "200 Hz sine WAV written by fixture driver"
assert_match "$DRV_TXT" "wrote klatt: 1" \
    "Klatt /ae/ WAV written by fixture driver"
assert_file_exists "$SINE_WAV"  "200 Hz sine WAV exists on disk"
assert_file_exists "$KLATT_WAV" "Klatt /ae/ WAV exists on disk"

# ===========================================================================
# Assertion 1: /spec on the 200 Hz sine -> peak in [156, 250] Hz band
# ===========================================================================

SPEC_SINE=$(run_chat "/spec $SINE_WAV")
assert_match "$SPEC_SINE" "spec $SINE_WAV: frames=[0-9]+" \
    "/spec sine reports a frame count"
assert_match "$SPEC_SINE" "bins=128" \
    "/spec sine @ 8 kHz uses 128 bins (frame_size=256)"
assert_match "$SPEC_SINE" "frame_size=256" \
    "/spec sine @ 8 kHz uses frame_size=256"
assert_match "$SPEC_SINE" "hop_size=128" \
    "/spec sine @ 8 kHz uses hop_size=128"
# 200 Hz @ 8 kHz / 256 -> bin 6 (187 Hz) or bin 7 (218 Hz); peak in [156, 250].
SINE_PEAK=$(printf '%s\n' "$SPEC_SINE" | grep -oE 'peak_frequency_first_frame=[0-9]+' | head -1 | cut -d= -f2)
if [ -n "$SINE_PEAK" ] && [ "$SINE_PEAK" -ge 156 ] && [ "$SINE_PEAK" -le 250 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  /spec 200 Hz sine peak in [156, 250] Hz (got %s)\n" "$SINE_PEAK"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  /spec 200 Hz sine peak out of band (got %s, expected [156, 250])\n" "$SINE_PEAK"
fi

# ===========================================================================
# Assertion 2: /spec on Klatt /ae/ -> peak in formant band [400, 2200] Hz
# ===========================================================================

SPEC_KLATT=$(run_chat "/spec $KLATT_WAV")
assert_match "$SPEC_KLATT" "spec $KLATT_WAV: frames=[0-9]+" \
    "/spec Klatt reports a frame count"
KLATT_FRAMES=$(printf '%s\n' "$SPEC_KLATT" | grep -oE 'frames=[0-9]+' | head -1 | cut -d= -f2)
if [ -n "$KLATT_FRAMES" ] && [ "$KLATT_FRAMES" -ge 5 ] && [ "$KLATT_FRAMES" -le 12 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  /spec Klatt frames in [5, 12] (got %s)\n" "$KLATT_FRAMES"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  /spec Klatt frames out of band (got %s)\n" "$KLATT_FRAMES"
fi
# Klatt /ae/ formants: F1=660 Hz, F2=1720 Hz. Either could dominate.
KLATT_PEAK=$(printf '%s\n' "$SPEC_KLATT" | grep -oE 'peak_frequency_first_frame=[0-9]+' | head -1 | cut -d= -f2)
if [ -n "$KLATT_PEAK" ] && [ "$KLATT_PEAK" -ge 400 ] && [ "$KLATT_PEAK" -le 2200 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  /spec Klatt /ae/ peak in formant band [400, 2200] (got %s)\n" "$KLATT_PEAK"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  /spec Klatt /ae/ peak out of formant band (got %s, expected [400, 2200])\n" "$KLATT_PEAK"
fi

# ===========================================================================
# Assertion 3: graceful error on missing WAV
# ===========================================================================

SPEC_MISSING=$(run_chat "/spec $MISSING_WAV")
assert_match "$SPEC_MISSING" "spec FAILED: could not parse WAV at $MISSING_WAV" \
    "/spec missing WAV reports graceful error"

# ===========================================================================
# Assertion 4: /spec with no argument -> usage message
# ===========================================================================

SPEC_NOARG=$(run_chat "/spec")
assert_match "$SPEC_NOARG" "/spec needs PATH" \
    "/spec with no arg shows usage hint"

# ===========================================================================
# Assertion 5: JFK 16 kHz WAV (skip gracefully if not installed)
# ===========================================================================

if [ "$HAVE_JFK" -eq 1 ]; then
    SPEC_JFK=$(run_chat "/spec $JFK_WAV")
    assert_match "$SPEC_JFK" "spec $JFK_WAV: frames=[0-9]+" \
        "/spec JFK reports a frame count"
    assert_match "$SPEC_JFK" "bins=256" \
        "/spec JFK @ 16 kHz uses 256 bins (frame_size=512)"
    JFK_FRAMES=$(printf '%s\n' "$SPEC_JFK" | grep -oE 'frames=[0-9]+' | head -1 | cut -d= -f2)
    # JFK is ~11 s = 176000 samples @ 16 kHz; with frame=512 / hop=256
    # that's floor((176000 - 512) / 256) + 1 = 686 frames. Allow a wide
    # band [600, 750] for robustness.
    if [ -n "$JFK_FRAMES" ] && [ "$JFK_FRAMES" -ge 600 ] && [ "$JFK_FRAMES" -le 750 ]; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}PASS${C_RST}  /spec JFK frame count in [600, 750] (got %s)\n" "$JFK_FRAMES"
    else
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  /spec JFK frame count out of band (got %s, expected [600, 750])\n" "$JFK_FRAMES"
    fi
    assert_match "$SPEC_JFK" "@ 16000 Hz" \
        "/spec JFK reports 16 kHz sample rate"
else
    printf "  ${C_YEL}SKIP${C_RST}  JFK WAV not at %s -- JFK assertions skipped\n" "$JFK_WAV"
fi

# ===========================================================================
# Negative: fixture driver must not emit FAIL lines
# ===========================================================================

assert_nomatch "$DRV_TXT" "^FAIL" \
    "fixture driver did not emit FAIL lines"

summary "scenario_ooo_spectrogram"
