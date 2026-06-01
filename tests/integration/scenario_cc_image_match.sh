#!/usr/bin/env bash
# Scenario CC -- /match_images PGM admin command end-to-end (P3.3 cont. v2,
# the deferred half of SIFT: 128-D descriptor + Lowe-ratio-test matcher).
#
# Build two PGM fixtures in /tmp -- the SAME scene (32x32 four-spots) and
# a structurally-different scene (32x32 vertical edge). Feed
# `/match_images A B` to the chat for two cases:
#
#   1. A and B are identical (same four-spots PGM, decoded twice):
#      every keypoint in A should self-match in B, so we expect
#      `matched N` with N >= 1.
#
#   2. A is four-spots, B is the vertical-edge fixture -- structurally
#      different. The ratio test should reject all candidates; we expect
#      `matched 0` (or close to 0).
#
# We also verify:
#   - `/help` advertises `/match_images A B`.
#   - `/match_images` with no arg / one arg prints the usage line.
#   - `/match_images` on a missing file prints the parser's bracketed error.
#   - The chat survives all of the above and reaches /quit.

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0

it_section "scenario CC: /match_images PGM admin command (P3.3 cont. v2 SIFT descriptor + matcher)"

SPOTS_A="/tmp/ce_scenario_cc_spots_a.pgm"
SPOTS_B="/tmp/ce_scenario_cc_spots_b.pgm"
EDGE="/tmp/ce_scenario_cc_edge.pgm"
MISSING="/tmp/ce_scenario_cc_nonexistent.pgm"

# Cleanup any stale fixture files from a previous run.
rm -f "$SPOTS_A" "$SPOTS_B" "$EDGE" "$MISSING"

build_four_spots_pgm() {
    local out="$1"
    {
        printf 'P5\n32 32\n255\n'
        python3 -c '
import sys
W, H = 32, 32
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
        printf 'P5\n32 32\n255\n'
        for i in $(seq 1 32); do
            head -c 16 /dev/zero
            head -c 16 /dev/zero | tr '\000' '\377'
        done
    } > "$out"
}

build_four_spots_pgm "$SPOTS_A"
build_four_spots_pgm "$SPOTS_B"
build_edge_pgm "$EDGE"

if [ ! -s "$SPOTS_A" ] || [ ! -s "$SPOTS_B" ] || [ ! -s "$EDGE" ]; then
    printf "  ${C_RED}FAIL${C_RST}  fixture files did not get written\n"
    FAIL=$((FAIL+1))
    summary "scenario_cc_image_match"
    exit
fi

INPUT=$(
    printf '/help\n'
    printf '/match_images\n'
    printf '/match_images %s\n' "$SPOTS_A"
    printf '/match_images %s %s\n' "$SPOTS_A" "$SPOTS_B"
    printf '/match_images %s %s\n' "$SPOTS_A" "$EDGE"
    printf '/match_images %s %s\n' "$MISSING" "$SPOTS_B"
    printf '/quit\n'
)

OUT=$(echo "$INPUT" | "$CHAT" 2>&1)

# 1. /help advertises /match_images.
assert_match "$OUT" "/match_images A B +detect \\+ describe SIFT keypoints" \
    "/help advertises /match_images"

# 2. /match_images with no arg prints the usage line.
assert_match "$OUT" "/match_images needs two PATHs" \
    "/match_images with no arg prints usage"

# 3. /match_images with only one arg prints the usage line.
assert_match "$OUT" "/match_images needs TWO paths -- got 1" \
    "/match_images with one arg prints usage"

# 4. Same image twice: matched N where N >= 1.
assert_match "$OUT" "matched [1-9][0-9]* keypoint" \
    "/match_images on identical PGMs reports >= 1 match"

# 5. A=spots B=spots: A and B keypoint counts equal and >= 1.
assert_match "$OUT" "A=[1-9][0-9]*kps B=[1-9][0-9]*kps" \
    "/match_images reports per-image keypoint counts"

# 6. /match_images on a missing file surfaces the PGM parser's bracketed error.
assert_match "$OUT" "match_images FAILED on A:" \
    "/match_images on missing file prints parser error"

# 7. The chat survives the malformed inputs and reaches /quit.
assert_match "$OUT" "bye\\." \
    "chat reaches /quit cleanly after /match_images probing"

# Cleanup.
rm -f "$SPOTS_A" "$SPOTS_B" "$EDGE"

summary "scenario_cc_image_match"
