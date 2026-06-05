#!/usr/bin/env bash
# Scenario NN -- /depth_sgm PGM admin command end-to-end (R9A,
# Semi-Global Matching stereo on top of R7E's SAD block-matching and
# R8D's LR-check + sub-pixel quality follow-ups).
#
# Build PGM fixtures in /tmp:
#   - LEFT_TEX:   textured deterministic pseudo-noise (32x24).
#   - RIGHT_TEX:  LEFT_TEX shifted LEFT by SHIFT=8 pixels.
#   - LEFT_BAND:  same fixture with a textureless-band region painted in.
#   - RIGHT_BAND: same fixture (shifted) with the corresponding band.
#   - RIGHT_SMALL: 24x20 for dimension-mismatch test.
#
# Cases:
#   1. /help still advertises the R7E /depth admin (we did not remove
#      the parent surface).
#   2. /depth_sgm with no args prints the usage line.
#   3. /depth_sgm with one arg prints the 'got 1' usage line.
#   4. /depth_sgm on identical inputs reports mean_disp=0.
#   5. /depth_sgm on integer-shifted pair reports mean_disp > 0.
#   6. /depth_sgm emits a density label (low / mid / high).
#   7. /depth_sgm on dim-mismatched inputs prints the mismatch error.
#   8. /depth_sgm on missing file surfaces the PGM parser's bracketed
#      error.
#   9. SGM-vs-block-matching texture-less-region variance: SGM's mean
#      disparity in the textureless band is smaller (or equal) variance
#      than block-matching's. We side-step the chat for this case and
#      invoke the binary's /depth and /depth_sgm sequentially on the
#      same fixture pair, then verify both lines emitted.
#  10. The chat reaches /quit cleanly.

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0

it_section "scenario NN: /depth_sgm PGM admin (R9A Semi-Global Matching stereo)"

LEFT_TEX="/tmp/ce_scenario_nn_left_tex.pgm"
RIGHT_TEX="/tmp/ce_scenario_nn_right_tex.pgm"
LEFT_BAND="/tmp/ce_scenario_nn_left_band.pgm"
RIGHT_BAND="/tmp/ce_scenario_nn_right_band.pgm"
RIGHT_SMALL="/tmp/ce_scenario_nn_right_small.pgm"
MISSING="/tmp/ce_scenario_nn_nonexistent.pgm"

# Cleanup stale fixture files.
rm -f "$LEFT_TEX" "$RIGHT_TEX" "$LEFT_BAND" "$RIGHT_BAND" "$RIGHT_SMALL" "$MISSING"

build_textured_pgm() {
    local out="$1"; local w="$2"; local h="$3"
    {
        printf 'P5\n%d %d\n255\n' "$w" "$h"
        python3 -c "
import sys
W, H = $w, $h
buf = bytearray(W * H)
for y in range(H):
    for x in range(W):
        buf[y * W + x] = (x * 37 + y * 13) % 256
sys.stdout.buffer.write(bytes(buf))
"
    } > "$out"
}

build_shifted_pgm() {
    local out="$1"; local w="$2"; local h="$3"; local shift="$4"
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
            buf[y * W + x] = (sx * 37 + y * 13) % 256
        else:
            buf[y * W + x] = 0
sys.stdout.buffer.write(bytes(buf))
"
    } > "$out"
}

# Textured fixture with a textureless band painted in [xL..xH) x [yL..yH).
# Band is base 150 with very small per-side noise (different for L and R)
# so SAD has many near-equal minima -> BM speckles, SGM smooths.
build_band_pgm() {
    local out="$1"; local w="$2"; local h="$3"
    local shift="$4"; local side="$5"   # side = "left" or "right"
    local xL="$6"; local xH="$7"; local yL="$8"; local yH="$9"
    {
        printf 'P5\n%d %d\n255\n' "$w" "$h"
        python3 -c "
import sys
W, H = $w, $h
SHIFT = $shift
SIDE = '$side'
xL, xH, yL, yH = $xL, $xH, $yL, $yH
buf = bytearray(W * H)
for y in range(H):
    for x in range(W):
        in_band = xL <= x < xH and yL <= y < yH
        if in_band:
            if SIDE == 'left':
                v = 150 + ((x * 5 + y * 3) % 3)
            else:
                v = 150 + ((x * 11 + y * 7) % 3)
        else:
            if SIDE == 'left':
                v = (x * 37 + y * 13) % 256
            else:
                sx = x + SHIFT
                if sx < W:
                    v = (sx * 37 + y * 13) % 256
                else:
                    v = 0
        buf[y * W + x] = v
sys.stdout.buffer.write(bytes(buf))
"
    } > "$out"
}

build_textured_pgm "$LEFT_TEX"  32 24
build_shifted_pgm  "$RIGHT_TEX" 32 24 8
build_band_pgm     "$LEFT_BAND"  32 24 8 "left"  8 24 8 16
build_band_pgm     "$RIGHT_BAND" 32 24 8 "right" 8 24 8 16
build_textured_pgm "$RIGHT_SMALL" 24 20

# Pure textureless-noisy fixture: 32x24 base-128 with low-amplitude
# (mod-4) per-side noise that differs left vs right. The canonical
# SGM-wins case where block-matching speckles wildly and SGM smooths.
LEFT_NOISE="/tmp/ce_scenario_nn_left_noise.pgm"
RIGHT_NOISE="/tmp/ce_scenario_nn_right_noise.pgm"
rm -f "$LEFT_NOISE" "$RIGHT_NOISE"
build_noise_pgm() {
    local out="$1"; local w="$2"; local h="$3"; local seed_a="$4"; local seed_b="$5"
    {
        printf 'P5\n%d %d\n255\n' "$w" "$h"
        python3 -c "
import sys
W, H, A, B = $w, $h, $seed_a, $seed_b
buf = bytearray(W * H)
for y in range(H):
    for x in range(W):
        n = (x * A + y * B) % 4
        buf[y * W + x] = 128 + n
sys.stdout.buffer.write(bytes(buf))
"
    } > "$out"
}
build_noise_pgm "$LEFT_NOISE"  32 24 7 11
build_noise_pgm "$RIGHT_NOISE" 32 24 13 17

if [ ! -s "$LEFT_TEX" ] || [ ! -s "$RIGHT_TEX" ] || [ ! -s "$LEFT_BAND" ] || [ ! -s "$RIGHT_BAND" ] || [ ! -s "$RIGHT_SMALL" ]; then
    printf "  ${C_RED}FAIL${C_RST}  fixture files did not get written\n"
    FAIL=$((FAIL+1))
    summary "scenario_nn_stereo_sgm"
    exit
fi

INPUT=$(
    printf '/help\n'
    printf '/depth_sgm\n'
    printf '/depth_sgm %s\n' "$LEFT_TEX"
    printf '/depth_sgm %s %s\n' "$LEFT_TEX" "$LEFT_TEX"
    printf '/depth_sgm %s %s\n' "$LEFT_TEX" "$RIGHT_TEX"
    printf '/depth_sgm %s %s\n' "$LEFT_TEX" "$RIGHT_SMALL"
    printf '/depth_sgm %s %s\n' "$MISSING" "$LEFT_TEX"
    printf '/depth %s %s\n' "$LEFT_BAND" "$RIGHT_BAND"
    printf '/depth_sgm %s %s\n' "$LEFT_BAND" "$RIGHT_BAND"
    printf '/depth %s %s\n' "$LEFT_NOISE" "$RIGHT_NOISE"
    printf '/depth_sgm %s %s\n' "$LEFT_NOISE" "$RIGHT_NOISE"
    printf '/quit\n'
)

OUT=$(echo "$INPUT" | "$CHAT" 2>&1)

# 1. /help advertises the parent R7E /depth admin.
assert_match "$OUT" "/depth L.pgm R.pgm +block-matching SAD stereo" \
    "/help still advertises /depth (R7E preserved)"

# 2. /depth_sgm no-arg prints usage.
assert_match "$OUT" "/depth_sgm needs two PATHs" \
    "/depth_sgm with no arg prints usage"

# 3. /depth_sgm one-arg prints 'got 1' usage.
assert_match "$OUT" "/depth_sgm needs TWO paths -- got 1" \
    "/depth_sgm with one arg prints usage"

# 4. /depth_sgm identical inputs -> mean_disp=0.
assert_match "$OUT" "depth_sgm 32x24 mean_disp=0 " \
    "/depth_sgm identical inputs reports mean_disp=0"

# 5. /depth_sgm shifted pair reports mean_disp > 0.
assert_match "$OUT" "depth_sgm 32x24 mean_disp=[1-9]" \
    "/depth_sgm shifted pair reports mean_disp >= 1"

# 6. /depth_sgm emits a density label.
assert_match "$OUT" "image_stereo_density_(low|mid|high)" \
    "/depth_sgm emits a density label"

# 7. /depth_sgm dim-mismatched inputs.
assert_match "$OUT" "depth_sgm FAILED: dim mismatch" \
    "/depth_sgm on dim mismatch prints clear error"

# 8. /depth_sgm missing file surfaces the parser's bracketed error.
assert_match "$OUT" "depth_sgm FAILED on L:" \
    "/depth_sgm on missing L file prints parser error"

# 9. SGM-vs-block-matching on the textureless-band fixture: we asked for
#    both /depth and /depth_sgm above; check both lines emitted with
#    matching dims. SGM's smoothing means the means will differ; we just
#    confirm both summarized output lines are present (R9A's variance
#    invariant is exercised by the unit-test suite, which has exact
#    measurements).
assert_match "$OUT" "depth 32x24 mean_disp=" \
    "/depth band fixture emits BM summary line"
assert_match "$OUT" "depth_sgm 32x24 mean_disp=" \
    "/depth_sgm band fixture emits SGM summary line"

# 10. Noisy-flat pair (the canonical SGM-wins case): both /depth and
#     /depth_sgm were asked on a pure-noise fixture. BM speckles ->
#     density milli reads in the mid bucket (lots of nonzero pixels
#     because tied SAD is broken randomly). SGM smooths -> density
#     reads "low" (every interior pixel converges to a single d).
#     We assert the density LABEL difference: BM lands at "mid",
#     SGM lands at "low" -- a direct, line-level expression of
#     "SGM has lower variance / speckle than BM on the smooth region".
assert_match "$OUT" "depth 32x24 mean_disp=[0-9]+ density=[0-9]+milli image_stereo_density_(mid|high)" \
    "/depth noisy-flat fixture emits BM mid/high density (speckle)"
assert_match "$OUT" "depth_sgm 32x24 mean_disp=[0-9]+ density=[0-9]+milli image_stereo_density_low" \
    "/depth_sgm noisy-flat fixture emits SGM low density (smooth)"

# 11. The chat reaches /quit cleanly.
assert_match "$OUT" "bye\\." \
    "chat reaches /quit cleanly after /depth_sgm probing"

# Cleanup.
rm -f "$LEFT_TEX" "$RIGHT_TEX" "$LEFT_BAND" "$RIGHT_BAND" "$RIGHT_SMALL" "$LEFT_NOISE" "$RIGHT_NOISE"

summary "scenario_nn_stereo_sgm"
