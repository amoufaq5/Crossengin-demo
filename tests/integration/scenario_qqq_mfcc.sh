#!/usr/bin/env bash
# Scenario QQQ -- R17B MFCC (Mel-Frequency Cepstral Coefficients) chat
# round-trip and vowel discriminability.
#
# Exercises the full /mfcc admin command path on three synthetic Klatt
# vowels (/ae/, /iy/, /uw/) plus error paths. MFCC is the canonical
# input to classical speech recognizers, wake-word matched filters, and
# speaker-ID nearest-neighbour classifiers; the discriminability
# property (distinct vowels produce distinct MFCC vectors with non-
# trivial pairwise L2 distances) is the property every downstream user
# relies on.
#
# Assertions:
#
#   1. /mfcc on /ae/ -> valid frame count, frame_size=256, n_mfcc=13
#   2. /mfcc on /iy/ -> different mfcc1 from /ae/
#   3. /mfcc on /uw/ -> different mfcc1 from both /ae/ and /iy/
#   4. /mfcc on JFK 16 kHz WAV (if available) -> frames >= 600, n_mfcc=13
#   5. /mfcc with a missing path -> graceful error
#   6. /mfcc with no argument -> usage message
#
# Discriminability is asserted by comparing the mfcc1 milli values: in
# the integer-only path the vowel-specific formant structure shows up
# in coefs 1..3 of the first frame (coef 0 is the energy term and is
# similar across loudness-matched fixtures).
#
# Pre-conditions: NOVA toolchain at $NOVA_ROOT/nova; built chat binary
# at bin/crossengin-chat.
#
# Side-effects: writes /tmp/ce_scenario_qqq_*.wav and the on-the-fly
# NOVA driver under tests/integration/_scenario_qqq_drivers/.

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

it_section "scenario QQQ: R17B MFCC chat /mfcc round-trip + vowel discriminability"

NOVA_BIN="${NOVA_ROOT:-/home/user/NOVA}/nova"
if [ ! -x "$NOVA_BIN" ]; then
    printf "  ${C_RED}ERROR${C_RST}: NOVA launcher not found at %s (set NOVA_ROOT)\n" "$NOVA_BIN" >&2
    FAIL=$((FAIL+1))
    summary "scenario_qqq_mfcc"
    exit $?
fi

require_chat

JFK_WAV="${CE_WHISPER_JFK_WAV:-/tmp/whisper.cpp/samples/jfk.wav}"
HAVE_JFK=0
if [ -f "$JFK_WAV" ]; then HAVE_JFK=1; fi

AE_WAV="/tmp/ce_scenario_qqq_ae.wav"
IY_WAV="/tmp/ce_scenario_qqq_iy.wav"
UW_WAV="/tmp/ce_scenario_qqq_uw.wav"
MISSING_WAV="/tmp/ce_scenario_qqq_definitely_missing.wav"
DRV_DIR="$REPO_ROOT/tests/integration/_scenario_qqq_drivers"
DRV_SRC="$DRV_DIR/qqq_fixture_writer.nova"
DRV_OUT="/tmp/ce_scenario_qqq_driver.out"

mkdir -p "$DRV_DIR"
trap 'rm -f "$AE_WAV" "$IY_WAV" "$UW_WAV" "$MISSING_WAV" "$DRV_OUT" "$DRV_SRC"; rmdir "$DRV_DIR" 2>/dev/null || true' EXIT

# Driver: write three Klatt vowel fixtures. The chat /mfcc command does
# the actual MFCC round-trip.
cat > "$DRV_SRC" <<'NOVA'
// Auto-generated fixture writer for scenario_qqq_mfcc.sh.
//
// Writes three Klatt vowel fixtures (/ae/, /iy/, /uw/) to /tmp,
// each a 1200-sample WAV @ 8 kHz with distinct formant structure.
// MFCC of these fixtures should be pairwise distinct (vowels are
// discriminable in the spectral domain).

import "std/syscall"
import "../../../src/io/effectors/audio_synth.nova"

fn main() {
    let ae = synth_phoneme_klatt("ae")
    let ok1 = audio_write_wav(ae, "/tmp/ce_scenario_qqq_ae.wav")
    println("wrote ae: " + int_to_str(ok1))

    let iy = synth_phoneme_klatt("iy")
    let ok2 = audio_write_wav(iy, "/tmp/ce_scenario_qqq_iy.wav")
    println("wrote iy: " + int_to_str(ok2))

    let uw = synth_phoneme_klatt("uw")
    let ok3 = audio_write_wav(uw, "/tmp/ce_scenario_qqq_uw.wav")
    println("wrote uw: " + int_to_str(ok3))

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
    summary "scenario_qqq_mfcc"
    exit $?
fi

DRV_TXT=$(cat "$DRV_OUT")
assert_match "$DRV_TXT" "wrote ae: 1"  "/ae/ Klatt WAV written by fixture driver"
assert_match "$DRV_TXT" "wrote iy: 1"  "/iy/ Klatt WAV written by fixture driver"
assert_match "$DRV_TXT" "wrote uw: 1"  "/uw/ Klatt WAV written by fixture driver"
assert_file_exists "$AE_WAV" "/ae/ WAV exists on disk"
assert_file_exists "$IY_WAV" "/iy/ WAV exists on disk"
assert_file_exists "$UW_WAV" "/uw/ WAV exists on disk"

# ===========================================================================
# Assertion: /mfcc on each vowel reports valid frame count + n_mfcc=13
# ===========================================================================

MFCC_AE=$(run_chat "/mfcc $AE_WAV")
assert_match "$MFCC_AE" "mfcc $AE_WAV: frames=[0-9]+" \
    "/mfcc /ae/ reports a frame count"
assert_match "$MFCC_AE" "n_mfcc=13" \
    "/mfcc /ae/ reports n_mfcc=13"
assert_match "$MFCC_AE" "frame_size=256" \
    "/mfcc /ae/ @ 8 kHz uses frame_size=256"

MFCC_IY=$(run_chat "/mfcc $IY_WAV")
assert_match "$MFCC_IY" "mfcc $IY_WAV: frames=[0-9]+" \
    "/mfcc /iy/ reports a frame count"
assert_match "$MFCC_IY" "n_mfcc=13" \
    "/mfcc /iy/ reports n_mfcc=13"

MFCC_UW=$(run_chat "/mfcc $UW_WAV")
assert_match "$MFCC_UW" "mfcc $UW_WAV: frames=[0-9]+" \
    "/mfcc /uw/ reports a frame count"

# ===========================================================================
# Assertion: vowels are discriminable -- mfcc1 (first non-energy coef)
# differs across /ae/ vs /iy/ vs /uw/
# ===========================================================================

AE_C1=$(printf '%s\n' "$MFCC_AE" | grep -oE 'mfcc1=-?[0-9]+ milli' | head -1 | sed -E 's/mfcc1=(-?[0-9]+) milli/\1/')
IY_C1=$(printf '%s\n' "$MFCC_IY" | grep -oE 'mfcc1=-?[0-9]+ milli' | head -1 | sed -E 's/mfcc1=(-?[0-9]+) milli/\1/')
UW_C1=$(printf '%s\n' "$MFCC_UW" | grep -oE 'mfcc1=-?[0-9]+ milli' | head -1 | sed -E 's/mfcc1=(-?[0-9]+) milli/\1/')

if [ -n "$AE_C1" ] && [ -n "$IY_C1" ] && [ "$AE_C1" != "$IY_C1" ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  /ae/ mfcc1 (%s) distinct from /iy/ mfcc1 (%s)\n" "$AE_C1" "$IY_C1"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  /ae/ vs /iy/ mfcc1 NOT discriminable (ae=%s iy=%s)\n" "$AE_C1" "$IY_C1"
fi

if [ -n "$IY_C1" ] && [ -n "$UW_C1" ] && [ "$IY_C1" != "$UW_C1" ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  /iy/ mfcc1 (%s) distinct from /uw/ mfcc1 (%s)\n" "$IY_C1" "$UW_C1"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  /iy/ vs /uw/ mfcc1 NOT discriminable (iy=%s uw=%s)\n" "$IY_C1" "$UW_C1"
fi

if [ -n "$AE_C1" ] && [ -n "$UW_C1" ] && [ "$AE_C1" != "$UW_C1" ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  /ae/ mfcc1 (%s) distinct from /uw/ mfcc1 (%s)\n" "$AE_C1" "$UW_C1"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  /ae/ vs /uw/ mfcc1 NOT discriminable (ae=%s uw=%s)\n" "$AE_C1" "$UW_C1"
fi

# ===========================================================================
# Assertion: /mfcc on missing WAV -> graceful error
# ===========================================================================

MFCC_MISSING=$(run_chat "/mfcc $MISSING_WAV")
assert_match "$MFCC_MISSING" "mfcc FAILED: could not parse WAV at $MISSING_WAV" \
    "/mfcc missing WAV reports graceful error"

# ===========================================================================
# Assertion: /mfcc with no argument -> usage message
# ===========================================================================

MFCC_NOARG=$(run_chat "/mfcc")
assert_match "$MFCC_NOARG" "/mfcc needs PATH" \
    "/mfcc with no arg shows usage hint"

# ===========================================================================
# Optional: JFK 16 kHz WAV (skip gracefully if not installed)
# ===========================================================================

if [ "$HAVE_JFK" -eq 1 ]; then
    MFCC_JFK=$(run_chat "/mfcc $JFK_WAV")
    assert_match "$MFCC_JFK" "mfcc $JFK_WAV: frames=[0-9]+" \
        "/mfcc JFK reports a frame count"
    assert_match "$MFCC_JFK" "frame_size=512" \
        "/mfcc JFK @ 16 kHz uses frame_size=512"
    JFK_FRAMES=$(printf '%s\n' "$MFCC_JFK" | grep -oE 'frames=[0-9]+' | head -1 | cut -d= -f2)
    if [ -n "$JFK_FRAMES" ] && [ "$JFK_FRAMES" -ge 600 ] && [ "$JFK_FRAMES" -le 750 ]; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}PASS${C_RST}  /mfcc JFK frame count in [600, 750] (got %s)\n" "$JFK_FRAMES"
    else
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  /mfcc JFK frame count out of band (got %s, expected [600, 750])\n" "$JFK_FRAMES"
    fi
else
    printf "  ${C_YEL}SKIP${C_RST}  JFK WAV not at %s -- JFK assertion skipped\n" "$JFK_WAV"
fi

# ===========================================================================
# Negative: fixture driver must not emit FAIL lines
# ===========================================================================

assert_nomatch "$DRV_TXT" "^FAIL" \
    "fixture driver did not emit FAIL lines"

summary "scenario_qqq_mfcc"
