#!/usr/bin/env bash
# Scenario SS -- /flow PGM admin command end-to-end (R10D, Lucas-Kanade
# dense optical flow on PGM-P5 frame pairs).
#
# Build two PGM fixtures in /tmp -- a "prev" frame with a smooth
# quadratic-bowl texture (so gradients are well-conditioned but the
# pattern is smooth enough for first-order LK linearization) and a
# "next" frame which is the prev shifted right by SHIFT=3 pixels.
# Feed `/flow prev next` to the chat for several cases:
#
#   1. Identical frames (prev twice): mean magnitude ~ 0 -- every
#      pixel has Ix*It == Iy*It == 0 so the LK solve gives u, v = 0.
#      The density label reads "low".
#
#   2. Shifted pair (prev + prev shifted right by 3): mean magnitude
#      > 1000 milli -- LK recovers a non-trivial motion signal even
#      though the 3-pixel shift is at the upper edge of the first-
#      order Taylor regime.
#
#   3. Dimension mismatch (40x32 vs 32x32): /flow must print a clear
#      "dim mismatch" error and the chat survive.
#
#   4. Missing file: /flow must print a parser error wrapped in parens.
#
# We also verify:
#   - `/help` advertises `/flow prev next`.
#   - `/flow` with no arg / one arg prints the usage line.
#   - The chat reaches /quit cleanly after all probing.

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0

it_section "scenario SS: /flow PGM admin command (R10D Lucas-Kanade dense optical flow)"

PREV="/tmp/ce_scenario_ss_prev.pgm"
NEXT_SHIFTED="/tmp/ce_scenario_ss_next_shifted.pgm"
NEXT_SMALL="/tmp/ce_scenario_ss_next_small.pgm"
MISSING="/tmp/ce_scenario_ss_nonexistent.pgm"

# Cleanup any stale fixture files from a previous run.
rm -f "$PREV" "$NEXT_SHIFTED" "$NEXT_SMALL" "$MISSING"

# Smooth quadratic bowl: I(x, y) = (x*x + 3*y*y) / 8 capped at 255. This
# matches the unit-test fixture so the unit + integration results
# correlate: gradients are non-zero throughout, the 2x2 normal-equation
# matrix is well-conditioned, and the first-order LK Taylor approximation
# holds for sub-pixel and 1-pixel shifts (multi-pixel shifts pay a
# precision tax but stay above the density-"low" floor).
build_quadratic_pgm() {
    local out="$1"
    local w="$2"
    local h="$3"
    {
        printf 'P5\n%d %d\n255\n' "$w" "$h"
        python3 -c "
import sys
W, H = $w, $h
buf = bytearray(W * H)
for y in range(H):
    for x in range(W):
        v = (x * x + 3 * y * y) // 8
        if v > 255: v = 255
        buf[y * W + x] = v
sys.stdout.buffer.write(bytes(buf))
"
    } > "$out"
}

build_shifted_quadratic_pgm() {
    local out="$1"
    local w="$2"
    local h="$3"
    local shift="$4"
    {
        printf 'P5\n%d %d\n255\n' "$w" "$h"
        python3 -c "
import sys
W, H, SHIFT = $w, $h, $shift
buf = bytearray(W * H)
for y in range(H):
    for x in range(W):
        sx = x - SHIFT
        if 0 <= sx < W:
            v = (sx * sx + 3 * y * y) // 8
            if v > 255: v = 255
            buf[y * W + x] = v
        else:
            buf[y * W + x] = 0
sys.stdout.buffer.write(bytes(buf))
"
    } > "$out"
}

build_quadratic_pgm        "$PREV"          40 32
build_shifted_quadratic_pgm "$NEXT_SHIFTED" 40 32 3
build_quadratic_pgm        "$NEXT_SMALL"    32 32

if [ ! -s "$PREV" ] || [ ! -s "$NEXT_SHIFTED" ] || [ ! -s "$NEXT_SMALL" ]; then
    printf "  ${C_RED}FAIL${C_RST}  fixture files did not get written\n"
    FAIL=$((FAIL+1))
    summary "scenario_ss_optical_flow"
    exit
fi

INPUT=$(
    printf '/help\n'
    printf '/flow\n'
    printf '/flow %s\n' "$PREV"
    printf '/flow %s %s\n' "$PREV" "$PREV"
    printf '/flow %s %s\n' "$PREV" "$NEXT_SHIFTED"
    printf '/flow %s %s\n' "$PREV" "$NEXT_SMALL"
    printf '/flow %s %s\n' "$MISSING" "$PREV"
    printf '/quit\n'
)

OUT=$(echo "$INPUT" | "$CHAT" 2>&1)

# 1. /help advertises /flow.
assert_match "$OUT" "/flow prev next +Lucas-Kanade per-pixel optical flow" \
    "/help advertises /flow"

# 2. /flow with no arg prints the usage line.
assert_match "$OUT" "/flow needs two PATHs" \
    "/flow with no arg prints usage"

# 3. /flow with only one arg prints the 'got 1' usage line.
assert_match "$OUT" "/flow needs TWO paths -- got 1" \
    "/flow with one arg prints usage"

# 4. /flow on identical inputs prints the flow summary line.
assert_match "$OUT" "flow 40x32 mean_mag=" \
    "/flow identical inputs emits flow summary"

# 5. /flow on identical inputs reports mean_mag=0 (no motion).
assert_match "$OUT" "flow 40x32 mean_mag=0milli " \
    "/flow identical inputs reports mean_mag=0"

# 6. /flow on identical inputs emits the "density_low" atom (stationary).
assert_match "$OUT" "image_optical_flow_density_low" \
    "/flow identical inputs reports density_low"

# 7. /flow on shifted pair reports mean_mag > 1000 milli -- LK recovers
#    non-trivial motion even at integer-pixel shifts.
assert_match "$OUT" "flow 40x32 mean_mag=([1-9][0-9]{3}|[0-9]{5,})milli" \
    "/flow shifted pair reports mean_mag >= 1000 milli"

# 8. /flow on shifted pair has a positive valid-pixel count.
assert_match "$OUT" "valid=[1-9][0-9]*" \
    "/flow shifted pair has valid > 0"

# 9. /flow on dim-mismatched inputs prints the mismatch error.
assert_match "$OUT" "flow FAILED: dim mismatch" \
    "/flow on dim mismatch prints clear error"

# 10. /flow on missing file surfaces the PGM parser's bracketed error.
assert_match "$OUT" "flow FAILED on prev:" \
    "/flow on missing prev file prints parser error"

# 11. The chat survives all malformed inputs and reaches /quit.
assert_match "$OUT" "bye\\." \
    "chat reaches /quit cleanly after /flow probing"

# Cleanup.
rm -f "$PREV" "$NEXT_SHIFTED" "$NEXT_SMALL"

summary "scenario_ss_optical_flow"
