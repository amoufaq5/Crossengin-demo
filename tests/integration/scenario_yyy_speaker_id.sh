#!/usr/bin/env bash
# Scenario YYY -- R19D speaker identification via MFCC + DTW gallery
# chat round-trip. The voice analog of R18D's LBP-gallery face
# recognition: enrol K named speakers from reference utterances,
# then nearest-neighbour-match an unknown query against the gallery.
#
# Exercises the /spk_enroll + /spk_recognize admin command pair
# against three synthetic Klatt utterances (each with distinct
# vowel formant trajectories standing in for distinct speakers)
# plus a 4th distinct utterance that is NOT enrolled. The 4th
# query confirms the "unknown" rejection path under the default
# threshold.
#
# Assertions:
#
#   1. fixture driver writes alice / bob / carol / dave WAVs
#   2. /help advertises /spk_enroll + /spk_recognize
#   3. /spk_enroll (no arg) -> usage hint
#   4. /spk_recognize (no arg) -> usage hint
#   5. /spk_recognize before any enrolment -> gallery-empty error
#   6. /spk_enroll <missing.wav> -> graceful error
#   7. Enroll alice -> size=1 reported
#   8. Enroll bob   -> size=2 reported
#   9. Enroll carol -> size=3 reported
#  10. Recognize alice utterance -> matched=alice distance=0
#  11. Recognize bob utterance   -> matched=bob   distance=0
#  12. Recognize carol utterance -> matched=carol distance=0
#  13. Recognize dave (NOT enrolled) -> 'unknown' under default threshold
#
# Pre-conditions: NOVA toolchain at $NOVA_ROOT/nova; built chat
# binary at bin/crossengin-chat.

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

it_section "scenario YYY: R19D speaker identification MFCC+DTW gallery chat round-trip"

NOVA_BIN="${NOVA_ROOT:-/home/user/NOVA}/nova"
if [ ! -x "$NOVA_BIN" ]; then
    printf "  ${C_RED}ERROR${C_RST}: NOVA launcher not found at %s (set NOVA_ROOT)\n" "$NOVA_BIN" >&2
    FAIL=$((FAIL+1))
    summary "scenario_yyy_speaker_id"
    exit $?
fi

require_chat

ALICE_WAV="/tmp/ce_scenario_yyy_alice.wav"
BOB_WAV="/tmp/ce_scenario_yyy_bob.wav"
CAROL_WAV="/tmp/ce_scenario_yyy_carol.wav"
DAVE_WAV="/tmp/ce_scenario_yyy_dave.wav"
MISSING_WAV="/tmp/ce_scenario_yyy_definitely_missing.wav"
DRV_DIR="$REPO_ROOT/tests/integration/_scenario_yyy_drivers"
DRV_SRC="$DRV_DIR/yyy_fixture_writer.nova"
DRV_OUT="/tmp/ce_scenario_yyy_driver.out"

mkdir -p "$DRV_DIR"
trap 'rm -f "$ALICE_WAV" "$BOB_WAV" "$CAROL_WAV" "$DAVE_WAV" "$MISSING_WAV" "$DRV_OUT" "$DRV_SRC"; rmdir "$DRV_DIR" 2>/dev/null || true' EXIT

# Driver: write four fixtures with distinct Klatt vowel sequences.
#   alice -> /iy ae iy/  (high front then low front then high front)
#   bob   -> /ae uw ae/  (low front then high back then low front)
#   carol -> /uw ow uw/  (high back then mid-back then high back)
#   dave  -> /a ah a/    (low-back/central -- NOT enrolled; the
#                         "unknown" probe under the default threshold)
#
# These vowel triples have very different formant trajectories
# (F1/F2 sweeps), so the MFCC sequences differ substantially and
# the DTW distance between any two speakers is well above the
# default 30000 milli^2 threshold while a self-match is 0.
cat > "$DRV_SRC" <<'NOVA'
// Auto-generated fixture writer for scenario_yyy_speaker_id.sh.

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

fn _stitch3(p1, p2, p3) {
    let a = synth_phoneme_klatt(p1)
    let b = synth_phoneme_klatt(p2)
    let c = synth_phoneme_klatt(p3)
    return _concat(_concat(a, b), c)
}

fn main() {
    let alice = _stitch3("iy", "ae", "iy")
    let ok1 = audio_write_wav(alice, "/tmp/ce_scenario_yyy_alice.wav")
    println("wrote alice: " + int_to_str(ok1))

    let bob = _stitch3("ae", "uw", "ae")
    let ok2 = audio_write_wav(bob, "/tmp/ce_scenario_yyy_bob.wav")
    println("wrote bob: " + int_to_str(ok2))

    let carol = _stitch3("uw", "ow", "uw")
    let ok3 = audio_write_wav(carol, "/tmp/ce_scenario_yyy_carol.wav")
    println("wrote carol: " + int_to_str(ok3))

    let dave = _stitch3("a", "ah", "a")
    let ok4 = audio_write_wav(dave, "/tmp/ce_scenario_yyy_dave.wav")
    println("wrote dave: " + int_to_str(ok4))

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
    summary "scenario_yyy_speaker_id"
    exit $?
fi

DRV_TXT=$(cat "$DRV_OUT")
assert_match "$DRV_TXT" "wrote alice: 1" "alice fixture WAV written by driver"
assert_match "$DRV_TXT" "wrote bob: 1"   "bob fixture WAV written by driver"
assert_match "$DRV_TXT" "wrote carol: 1" "carol fixture WAV written by driver"
assert_match "$DRV_TXT" "wrote dave: 1"  "dave fixture WAV written by driver"
assert_file_exists "$ALICE_WAV" "alice WAV exists on disk"
assert_file_exists "$BOB_WAV"   "bob WAV exists on disk"
assert_file_exists "$CAROL_WAV" "carol WAV exists on disk"
assert_file_exists "$DAVE_WAV"  "dave WAV exists on disk"

# ===========================================================================
# Drive the full chat session: probe usage / empty-gallery paths first,
# then enrol the three speakers, then recognize each + the unknown 4th.
# ===========================================================================

INPUT=$(
    printf '/help\n'
    printf '/spk_enroll\n'
    printf '/spk_recognize\n'
    printf '/spk_recognize %s\n' "$ALICE_WAV"
    printf '/spk_enroll missing %s\n' "$MISSING_WAV"
    printf '/spk_enroll alice %s\n' "$ALICE_WAV"
    printf '/spk_enroll bob %s\n' "$BOB_WAV"
    printf '/spk_enroll carol %s\n' "$CAROL_WAV"
    printf '/spk_recognize %s\n' "$ALICE_WAV"
    printf '/spk_recognize %s\n' "$BOB_WAV"
    printf '/spk_recognize %s\n' "$CAROL_WAV"
    printf '/spk_recognize %s\n' "$DAVE_WAV"
    printf '/quit\n'
)

OUT=$(echo "$INPUT" | "$CHAT" 2>&1)

# 1. /help advertises /spk_enroll + /spk_recognize.
assert_match "$OUT" "/spk_enroll L WAV.*/spk_recognize WAV" \
    "/help advertises /spk_enroll + /spk_recognize"

# 2. /spk_enroll with no arg -> usage.
assert_match "$OUT" "/spk_enroll needs LABEL PATH\\.wav" \
    "/spk_enroll with no arg prints usage"

# 3. /spk_recognize with no arg -> usage.
assert_match "$OUT" "/spk_recognize needs PATH\\.wav" \
    "/spk_recognize with no arg prints usage"

# 4. /spk_recognize before any enrolment -> gallery-empty error.
assert_match "$OUT" "spk_recognize FAILED: gallery empty" \
    "/spk_recognize on empty gallery prints gallery-empty error"

# 5. /spk_enroll on missing WAV -> graceful error.
assert_match "$OUT" "spk_enroll FAILED on .*: could not parse WAV" \
    "/spk_enroll on missing WAV prints parser error gracefully"

# 6. Successful enrolments report monotonically-growing size.
assert_match "$OUT" "spk_enroll OK label=alice size=1" \
    "alice enrolled: gallery size = 1"
assert_match "$OUT" "spk_enroll OK label=bob size=2" \
    "bob enrolled: gallery size = 2"
assert_match "$OUT" "spk_enroll OK label=carol size=3" \
    "carol enrolled: gallery size = 3"

# 7. Each recognised speaker returns its own label with distance 0.
assert_match "$OUT" "spk_recognize matched=alice distance=0 " \
    "/spk_recognize alice utterance -> alice with distance 0"
assert_match "$OUT" "spk_recognize matched=bob distance=0 " \
    "/spk_recognize bob utterance -> bob with distance 0"
assert_match "$OUT" "spk_recognize matched=carol distance=0 " \
    "/spk_recognize carol utterance -> carol with distance 0"

# 8. Dave (NOT enrolled) -> "unknown" under default threshold.
assert_match "$OUT" "spk_recognize unknown distance=-1 threshold=30000" \
    "/spk_recognize dave utterance (NOT enrolled) -> unknown (correct rejection)"

# 9. The chat reaches /quit cleanly.
assert_match "$OUT" "bye\\." \
    "chat reaches /quit cleanly after /spk_enroll + /spk_recognize probing"

# Negative: driver did not emit FAIL lines.
assert_nomatch "$DRV_TXT" "^FAIL" \
    "fixture driver did not emit FAIL lines"

summary "scenario_yyy_speaker_id"
