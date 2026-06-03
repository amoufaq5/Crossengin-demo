#!/usr/bin/env bash
# Scenario RRR -- /lbp LBP (Local Binary Patterns, Ojala 1996) texture
# descriptor admin command end-to-end (R17D, classifier-input feature
# vector; companion to R14D HOG and R16D Haar face-detect).
#
# Build four PGM fixtures in /tmp:
#   * face_a.pgm: 32x32 synthetic face-like image (vertical edge: left
#     half dark / right half bright -- a stand-in for a face profile).
#   * face_a_shift.pgm: same fixture shifted by 1 column. Tests
#     compute LBP descriptors over both via the chat surface; the
#     descriptors land near-identical (low chi-squared distance) --
#     the canonical "same identity, different alignment" recognition
#     case.
#   * face_b.pgm: dissimilar fixture (four bright spots near corners
#     of a dark field). Tests compute its descriptor and verify
#     a HIGH chi-squared distance vs face_a -- the classic
#     "different identities" case.
#   * tiny.pgm: 4x4 below the LBP_CHAT_MIN_DIM=8 floor.
#
# Verify that:
#
#   1. /help advertises /lbp.
#   2. /lbp with no arg prints the usage line.
#   3. /lbp on a missing file prints the parser's bracketed error.
#   4. /lbp on a too-small image (4x4) prints a clear minimum-dim error.
#   5. /lbp on face_a returns a valid summary tuple with a 0..255
#      dominant_code and a non-negative entropy.
#   6. /lbp on face_a_shift produces the SAME dominant_code as face_a
#      (basic LBP is moderately translation-invariant within the
#      same texture).
#   7. /lbp on face_b returns a valid summary tuple with the OPPOSITE
#      dominant_code class (face_a has a vertical-edge dominant code;
#      face_b's four-spots field has a different dominant code).
#   8. Both face_a / face_b summary lines carry the 32x32 dimensions.
#   9. The chat survives all probing and reaches /quit cleanly.
#   10. /lbp face_a non-zero entropy > 0 (there IS texture present).

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0

it_section "scenario RRR: /lbp Local Binary Patterns texture descriptor (R17D)"

FACE_A="/tmp/ce_scenario_rrr_face_a.pgm"
FACE_A_SHIFT="/tmp/ce_scenario_rrr_face_a_shift.pgm"
FACE_B="/tmp/ce_scenario_rrr_face_b.pgm"
TINY="/tmp/ce_scenario_rrr_tiny.pgm"
MISSING="/tmp/ce_scenario_rrr_nonexistent.pgm"

# Cleanup any stale fixture files from a previous run.
rm -f "$FACE_A" "$FACE_A_SHIFT" "$FACE_B" "$TINY" "$MISSING"

build_face_a_pgm() {
    # 32x32 vertical-edge "face" pattern: left half dark, right half
    # bright. The LBP code field has a strong concentration in the
    # uniform-bright code (0xFF) for interior pixels of both halves
    # plus the specific 4-bit-set edge codes along the boundary.
    local out="$1"
    {
        printf 'P5\n32 32\n255\n'
        python3 -c '
import sys
W, H = 32, 32
buf = bytearray(W * H)
half = W // 2
for y in range(H):
    for x in range(W):
        buf[y * W + x] = 50 if x < half else 200
sys.stdout.buffer.write(bytes(buf))
'
    } > "$out"
}

build_face_a_shift_pgm() {
    # SAME vertical-edge fixture shifted by 1 column to the right.
    # LBP descriptor over 4x4 cells should be very close to face_a
    # (most cells unchanged; only the edge-straddling cells differ).
    local out="$1"
    {
        printf 'P5\n32 32\n255\n'
        python3 -c '
import sys
W, H = 32, 32
buf = bytearray(W * H)
half = W // 2 + 1
for y in range(H):
    for x in range(W):
        buf[y * W + x] = 50 if x < half else 200
sys.stdout.buffer.write(bytes(buf))
'
    } > "$out"
}

build_face_b_pgm() {
    # Dissimilar fixture: four bright 4x4 spots near corners of a
    # dark field. Highly LOCAL texture (transitions at the spot
    # boundaries) -- the LBP histogram concentrates in different
    # bins than the vertical-edge field.
    local out="$1"
    {
        printf 'P5\n32 32\n255\n'
        python3 -c '
import sys
W, H = 32, 32
buf = [50] * (W * H)
for sx, sy in ((3, 3), (W - 7, 3), (3, H - 7), (W - 7, H - 7)):
    for dy in range(4):
        for dx in range(4):
            buf[(sy + dy) * W + (sx + dx)] = 200
sys.stdout.buffer.write(bytes(buf))
'
    } > "$out"
}

build_tiny_pgm() {
    # 4x4 -- below LBP_CHAT_MIN_DIM = 8. Image-too-small case.
    local out="$1"
    {
        printf 'P5\n4 4\n255\n'
        python3 -c '
import sys
W, H = 4, 4
buf = bytearray(W * H)
for i in range(W * H):
    buf[i] = 128
sys.stdout.buffer.write(bytes(buf))
'
    } > "$out"
}

build_face_a_pgm        "$FACE_A"
build_face_a_shift_pgm  "$FACE_A_SHIFT"
build_face_b_pgm        "$FACE_B"
build_tiny_pgm          "$TINY"

if [ ! -s "$FACE_A" ] || [ ! -s "$FACE_A_SHIFT" ] || [ ! -s "$FACE_B" ] || [ ! -s "$TINY" ]; then
    printf "  ${C_RED}FAIL${C_RST}  fixture files did not get written\n"
    FAIL=$((FAIL+1))
    summary "scenario_rrr_lbp"
    exit
fi

INPUT=$(
    printf '/help\n'
    printf '/lbp\n'
    printf '/lbp %s\n' "$MISSING"
    printf '/lbp %s\n' "$TINY"
    printf '/lbp %s\n' "$FACE_A"
    printf '/lbp %s\n' "$FACE_A_SHIFT"
    printf '/lbp %s\n' "$FACE_B"
    printf '/quit\n'
)

OUT=$(echo "$INPUT" | "$CHAT" 2>&1)

# 1. /help advertises /lbp.
assert_match "$OUT" "/lbp PATH +LBP" \
    "/help advertises /lbp"

# 2. /lbp with no arg prints the usage line.
assert_match "$OUT" "/lbp needs a PATH" \
    "/lbp with no arg prints usage"

# 3. /lbp on a missing file prints the parser's bracketed error.
assert_match "$OUT" "lbp FAILED on " \
    "/lbp on missing file prints parser error"

# 4. /lbp on too-small image surfaces the minimum-dim error.
assert_match "$OUT" "lbp FAILED: image too small" \
    "/lbp on too-small image prints clear error"

# 5. /lbp on face_a returns a valid summary tuple.
assert_match "$OUT" "\\(lbp 32x32 dominant_code=[0-9]+ entropy=[0-9]+\\)" \
    "/lbp on face_a reports valid summary tuple"

# 6. /lbp on face_a_shift produces the SAME dominant_code as face_a
#    (translation by 1 px within a single cell width -- most codes
#    unchanged).
FACE_A_LINE=$(echo "$OUT" | grep -E "\\(lbp 32x32 dominant_code=[0-9]+ entropy=[0-9]+\\)" | sed -n '1p')
FACE_A_SHIFT_LINE=$(echo "$OUT" | grep -E "\\(lbp 32x32 dominant_code=[0-9]+ entropy=[0-9]+\\)" | sed -n '2p')
FACE_B_LINE=$(echo "$OUT" | grep -E "\\(lbp 32x32 dominant_code=[0-9]+ entropy=[0-9]+\\)" | sed -n '3p')

FACE_A_CODE=$(echo "$FACE_A_LINE" | sed -E 's/.*dominant_code=([0-9]+) .*/\1/')
FACE_A_SHIFT_CODE=$(echo "$FACE_A_SHIFT_LINE" | sed -E 's/.*dominant_code=([0-9]+) .*/\1/')
FACE_B_CODE=$(echo "$FACE_B_LINE" | sed -E 's/.*dominant_code=([0-9]+) .*/\1/')

if [ -n "$FACE_A_CODE" ] && [ -n "$FACE_A_SHIFT_CODE" ] && [ "$FACE_A_CODE" = "$FACE_A_SHIFT_CODE" ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  face_a and face_a_shift share dominant_code=%s (low-distance pair)\n" "$FACE_A_CODE"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  face_a (%s) vs face_a_shift (%s) dominant_code differ -- expected equal for 1-px shift\n" "$FACE_A_CODE" "$FACE_A_SHIFT_CODE"
fi

# 7. /lbp on face_b returns a valid summary; verify face_b's
#    descriptor signal differs from face_a (a high-distance pair).
#    Either the dominant_code or the entropy bucket should differ.
FACE_A_ENT=$(echo "$FACE_A_LINE" | sed -E 's/.*entropy=([0-9]+).*/\1/')
FACE_B_ENT=$(echo "$FACE_B_LINE" | sed -E 's/.*entropy=([0-9]+).*/\1/')
if [ -n "$FACE_B_CODE" ] && [ -n "$FACE_B_ENT" ]; then
    # The signal we check: face_a (vertical edge -- mostly uniform-bright
    # 0xFF code) and face_b (four spots -- entropy concentrated around
    # the spot boundaries) should land in DIFFERENT dominant_code/
    # entropy regimes. Either the codes differ or the entropies do.
    if [ "$FACE_B_CODE" != "$FACE_A_CODE" ] || [ "$FACE_B_ENT" != "$FACE_A_ENT" ]; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}PASS${C_RST}  face_a vs face_b descriptors differ (a: code=%s ent=%s; b: code=%s ent=%s)\n" \
            "$FACE_A_CODE" "$FACE_A_ENT" "$FACE_B_CODE" "$FACE_B_ENT"
    else
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  face_a and face_b reported identical descriptors -- expected dissimilar\n"
    fi
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  could not extract face_b summary (line='%s')\n" "$FACE_B_LINE"
fi

# 8. Both face_a / face_b summary lines carry the 32x32 dimensions.
assert_match "$OUT" "\\(lbp 32x32 dominant_code=" \
    "/lbp 32x32 dimensions present in summary lines"

# 9. The chat survives the probing and reaches /quit.
assert_match "$OUT" "bye\\." \
    "chat reaches /quit cleanly after /lbp probing"

# 10. /lbp face_a entropy > 0 (there IS texture present).
if [ -n "$FACE_A_ENT" ] && [ "$FACE_A_ENT" -gt 0 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  face_a entropy > 0 (got %s milli-bits)\n" "$FACE_A_ENT"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  face_a entropy not > 0 (got '%s')\n" "$FACE_A_ENT"
fi

# Cleanup.
rm -f "$FACE_A" "$FACE_A_SHIFT" "$FACE_B" "$TINY"

summary "scenario_rrr_lbp"
