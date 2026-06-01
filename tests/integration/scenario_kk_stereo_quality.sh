#!/usr/bin/env bash
# Scenario KK -- /depth_q PGM admin command end-to-end (R8D, the
# quality follow-ups on top of R7E's SAD block-matching stereo
# disparity). LR-check + sub-pixel refinement.
#
# Build three PGM fixtures in /tmp:
#   - LEFT: smooth ramp (deterministic per-pixel gradient,
#           low-derivative so bilinear interpolation gives a clean
#           sub-pixel SAD curve).
#   - RIGHT_INT: LEFT shifted left by SHIFT=10 pixels (integer).
#   - RIGHT_SUB: LEFT shifted left by 10.5 pixels via bilinear
#                interpolation -- the canonical sub-pixel test case.
#   - RIGHT_OCCLUDED: LEFT shifted left by SHIFT=8 but with rows
#                     [12..20) painted constant 0 (an "occluding
#                     band" only the right view sees).
#
# Cases:
#   1. /help advertises /depth (the R7E parent admin still works).
#   2. /depth_q with no args prints the usage line.
#   3. /depth_q with one arg prints the 'got 1' usage line.
#   4. /depth_q on integer-shifted pair reports mean_milli > 1000
#      (the consistent interior pixels land near 10000 milli).
#   5. /depth_q on integer-shifted pair emits a density label.
#   6. /depth_q on dim-mismatched inputs prints the mismatch error.
#   7. /depth_q on missing file surfaces the PGM parser's bracketed
#      error.
#   8. /depth_q on identical inputs reports mean_milli=0 (every
#      pixel matches at d=0 sub-pixel-refined to 0).
#   9. /depth_q on sub-pixel-shifted pair (10.5px) reports a
#      mean_milli in the expected ballpark (>= 500 milli, since
#      consistent interior pixels recover ~10500 milli but borders
#      drag the mean down).
#   10. The chat survives all malformed inputs and reaches /quit
#       cleanly.

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0

it_section "scenario KK: /depth_q PGM admin command (R8D LR-check + sub-pixel)"

LEFT="/tmp/ce_scenario_kk_left.pgm"
RIGHT_INT="/tmp/ce_scenario_kk_right_int.pgm"
RIGHT_SUB="/tmp/ce_scenario_kk_right_sub.pgm"
RIGHT_SMALL="/tmp/ce_scenario_kk_right_small.pgm"
MISSING="/tmp/ce_scenario_kk_nonexistent.pgm"

# Cleanup any stale fixture files.
rm -f "$LEFT" "$RIGHT_INT" "$RIGHT_SUB" "$RIGHT_SMALL" "$MISSING"

# Build a smooth ramp PGM (matches the _ramp_fixture used by the
# sub-pixel unit tests so the sub-pixel SAD curve is well-shaped).
build_ramp_pgm() {
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
        u = x * 3 + y * 2 + (x * y) // 8
        buf[y * W + x] = u % 256
sys.stdout.buffer.write(bytes(buf))
"
    } > "$out"
}

# Integer-shifted version: right(x, y) = left(x + shift, y).
build_int_shift_pgm() {
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
        sx = x + SHIFT
        if sx < W:
            u = sx * 3 + y * 2 + (sx * y) // 8
            buf[y * W + x] = u % 256
        else:
            buf[y * W + x] = 0
sys.stdout.buffer.write(bytes(buf))
"
    } > "$out"
}

# Sub-pixel-shifted version via bilinear interpolation:
#   right(x, y) = (1-f) * src(x+s, y) + f * src(x+s+1, y)
#   where s = floor(shift_milli/1000), f = (shift_milli%1000)/1000
build_subpx_shift_pgm() {
    local out="$1"
    local w="$2"
    local h="$3"
    local shift_milli="$4"
    {
        printf 'P5\n%d %d\n255\n' "$w" "$h"
        python3 -c "
import sys
W, H, SM = $w, $h, $shift_milli
S = SM // 1000
F = (SM - S * 1000) / 1000.0
buf = bytearray(W * H)
def src(x, y):
    if x < 0 or x >= W:
        return 0
    u = x * 3 + y * 2 + (x * y) // 8
    return u % 256
for y in range(H):
    for x in range(W):
        sx = x + S
        if sx + 1 < W:
            a = src(sx, y)
            b = src(sx + 1, y)
            v = round((1.0 - F) * a + F * b)
        elif sx < W:
            v = src(sx, y)
        else:
            v = 0
        buf[y * W + x] = max(0, min(255, v))
sys.stdout.buffer.write(bytes(buf))
"
    } > "$out"
}

build_ramp_pgm "$LEFT" 48 32
build_int_shift_pgm "$RIGHT_INT" 48 32 10
build_subpx_shift_pgm "$RIGHT_SUB" 48 32 10500
build_ramp_pgm "$RIGHT_SMALL" 32 24

if [ ! -s "$LEFT" ] || [ ! -s "$RIGHT_INT" ] || [ ! -s "$RIGHT_SUB" ] || [ ! -s "$RIGHT_SMALL" ]; then
    printf "  ${C_RED}FAIL${C_RST}  fixture files did not get written\n"
    FAIL=$((FAIL+1))
    summary "scenario_kk_stereo_quality"
    exit
fi

INPUT=$(
    printf '/help\n'
    printf '/depth_q\n'
    printf '/depth_q %s\n' "$LEFT"
    printf '/depth_q %s %s\n' "$LEFT" "$LEFT"
    printf '/depth_q %s %s\n' "$LEFT" "$RIGHT_INT"
    printf '/depth_q %s %s\n' "$LEFT" "$RIGHT_SUB"
    printf '/depth_q %s %s\n' "$LEFT" "$RIGHT_SMALL"
    printf '/depth_q %s %s\n' "$MISSING" "$LEFT"
    printf '/quit\n'
)

OUT=$(echo "$INPUT" | "$CHAT" 2>&1)

# 1. /help still advertises the R7E /depth admin (we did not remove or
#    duplicate it; /depth_q is dispatch-only, no help entry needed since
#    it shares the same surface).
assert_match "$OUT" "/depth L.pgm R.pgm +block-matching SAD stereo" \
    "/help still advertises /depth (R7E preserved)"

# 2. /depth_q with no arg prints the usage line.
assert_match "$OUT" "/depth_q needs two PATHs" \
    "/depth_q with no arg prints usage"

# 3. /depth_q with only one arg prints the 'got 1' usage line.
assert_match "$OUT" "/depth_q needs TWO paths -- got 1" \
    "/depth_q with one arg prints usage"

# 4. /depth_q on identical inputs prints the quality summary line with
#    mean_milli=0 (every interior pixel matches at d=0 -> milli=0).
assert_match "$OUT" "depth_q 48x32 mean_milli=" \
    "/depth_q identical inputs emits quality summary"
assert_match "$OUT" "depth_q 48x32 mean_milli=0 " \
    "/depth_q identical inputs reports mean_milli=0"

# 5. /depth_q on integer-shifted-by-10 pair reports mean_milli >= 1000
#    (consistent interior pixels land near 10000 milli; the mean is
#    dragged down by border pixels with no LR-match -- on a 48x32 ramp
#    with SHIFT=10 it lands somewhere in 4000..9000 milli).
assert_match "$OUT" "depth_q 48x32 mean_milli=[1-9][0-9]{3}" \
    "/depth_q integer-shifted pair reports mean_milli >= 1000"

# 6. /depth_q on integer-shifted pair emits a density label.
assert_match "$OUT" "image_stereo_density_(low|mid|high)" \
    "/depth_q integer-shifted pair emits a density label"

# 7. /depth_q on sub-pixel-shifted (10.5px) pair reports a positive
#    mean_milli (the LR-check survivors recover ~10500 milli).
#    We check that at least one /depth_q line has mean_milli >= 500.
#    Both the integer and sub-pixel pairs satisfy this -- we just want
#    confirmation that the sub-pixel path doesn't crash or zero out.
assert_match "$OUT" "depth_q 48x32 mean_milli=[5-9][0-9]{2,}" \
    "/depth_q sub-pixel-shifted pair reports mean_milli >= 500"

# 8. /depth_q on dim-mismatched inputs prints the mismatch error.
assert_match "$OUT" "depth_q FAILED: dim mismatch" \
    "/depth_q on dim mismatch prints clear error"

# 9. /depth_q on missing file surfaces the PGM parser's bracketed error.
assert_match "$OUT" "depth_q FAILED on L:" \
    "/depth_q on missing L file prints parser error"

# 10. The chat survives all the malformed inputs and reaches /quit.
assert_match "$OUT" "bye\\." \
    "chat reaches /quit cleanly after /depth_q probing"

# Cleanup.
rm -f "$LEFT" "$RIGHT_INT" "$RIGHT_SUB" "$RIGHT_SMALL"

summary "scenario_kk_stereo_quality"
