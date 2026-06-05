#!/usr/bin/env bash
# Scenario EE -- /orb_match PGM admin command end-to-end (P3.3 cont. v3,
# the patent-free SIFT alternative: Oriented FAST + Rotated BRIEF +
# Hamming-distance matcher with Lowe's ratio test).
#
# Build two PGM fixtures in /tmp -- the SAME scene (40x40 four-spots) and
# a structurally-different scene (40x40 vertical edge). Feed
# `/orb_match A B` to the chat for two cases:
#
#   1. A and B are identical (same four-spots PGM, decoded twice):
#      every keypoint in A should self-match in B at Hamming distance 0,
#      so we expect `orb matched N` with N >= 1.
#
#   2. A is four-spots, B is the vertical-edge fixture -- structurally
#      different. The Harris-proximity filter rejects FAST candidates on
#      the straight edge (no Harris corners on a single-direction edge),
#      so B has zero descriptors and the matcher returns
#      `orb matched 0`.
#
# We also verify:
#   - `/help` advertises `/orb_match A B`.
#   - `/orb_match` with no arg / one arg prints the usage line.
#   - `/orb_match` on a missing file prints the parser's bracketed error.
#   - The chat survives all of the above and reaches /quit.
#
# The 40x40 dimension matches the unit-test fixture so the integration
# scenario stays comparable to the hermetic unit suite.

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0

it_section "scenario EE: /orb_match PGM admin command (P3.3 cont. v3 ORB feature detector + Hamming matcher)"

SPOTS_A="/tmp/ce_scenario_ee_spots_a.pgm"
SPOTS_B="/tmp/ce_scenario_ee_spots_b.pgm"
EDGE="/tmp/ce_scenario_ee_edge.pgm"
MISSING="/tmp/ce_scenario_ee_nonexistent.pgm"

# Cleanup any stale fixture files from a previous run.
rm -f "$SPOTS_A" "$SPOTS_B" "$EDGE" "$MISSING"

build_four_spots_pgm() {
    local out="$1"
    {
        printf 'P5\n40 40\n255\n'
        python3 -c '
import sys
W, H = 40, 40
buf = [0] * (W * H)
for sx, sy in ((4, 4), (W - 9, 4), (4, H - 9), (W - 9, H - 9)):
    for dy in range(5):
        for dx in range(5):
            buf[(sy + dy) * W + (sx + dx)] = 255
sys.stdout.buffer.write(bytes(buf))
'
    } > "$out"
}

build_edge_pgm() {
    local out="$1"
    {
        printf 'P5\n40 40\n255\n'
        python3 -c '
import sys
W, H = 40, 40
buf = bytearray(W * H)
for y in range(H):
    for x in range(W):
        buf[y * W + x] = 0 if x < W // 2 else 255
sys.stdout.buffer.write(bytes(buf))
'
    } > "$out"
}

build_four_spots_pgm "$SPOTS_A"
build_four_spots_pgm "$SPOTS_B"
build_edge_pgm "$EDGE"

if [ ! -s "$SPOTS_A" ] || [ ! -s "$SPOTS_B" ] || [ ! -s "$EDGE" ]; then
    printf "  ${C_RED}FAIL${C_RST}  fixture files did not get written\n"
    FAIL=$((FAIL+1))
    summary "scenario_ee_orb_match"
    exit
fi

INPUT=$(
    printf '/help\n'
    printf '/orb_match\n'
    printf '/orb_match %s\n' "$SPOTS_A"
    printf '/orb_match %s %s\n' "$SPOTS_A" "$SPOTS_B"
    printf '/orb_match %s %s\n' "$SPOTS_A" "$EDGE"
    printf '/orb_match %s %s\n' "$MISSING" "$SPOTS_B"
    printf '/quit\n'
)

OUT=$(echo "$INPUT" | "$CHAT" 2>&1)

# 1. /help advertises /orb_match.
assert_match "$OUT" "/orb_match A B +ORB" \
    "/help advertises /orb_match"

# 2. /orb_match with no arg prints the usage line.
assert_match "$OUT" "/orb_match needs two PATHs" \
    "/orb_match with no arg prints usage"

# 3. /orb_match with only one arg prints the usage line.
assert_match "$OUT" "/orb_match needs TWO paths -- got 1" \
    "/orb_match with one arg prints usage"

# 4. Same image twice: orb matched N where N >= 1.
assert_match "$OUT" "orb matched [1-9][0-9]* keypoint" \
    "/orb_match on identical PGMs reports >= 1 match"

# 5. A=spots B=spots: A and B keypoint counts equal and >= 1.
assert_match "$OUT" "A=[1-9][0-9]*kps B=[1-9][0-9]*kps" \
    "/orb_match reports per-image keypoint counts"

# 6. A=spots B=edge: 0 matches expected (edge has no Harris corners ->
#    no kept FAST candidates -> orb_match returns empty).
assert_match "$OUT" "orb matched 0 keypoint" \
    "/orb_match on structurally different (spots vs edge) -> 0 matches"

# 7. /orb_match on a missing file surfaces the PGM parser's bracketed error.
assert_match "$OUT" "orb_match FAILED on A:" \
    "/orb_match on missing file prints parser error"

# 8. The chat survives the malformed inputs and reaches /quit.
assert_match "$OUT" "bye\\." \
    "chat reaches /quit cleanly after /orb_match probing"

# Cleanup.
rm -f "$SPOTS_A" "$SPOTS_B" "$EDGE"

summary "scenario_ee_orb_match"
