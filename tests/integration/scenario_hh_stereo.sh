#!/usr/bin/env bash
# Scenario HH -- /depth PGM admin command end-to-end (R7E,
# block-matching SAD stereo disparity from PGM-P5 stereo pairs).
#
# Build two PGM fixtures in /tmp -- a textured "left" image (40x40
# deterministic pseudo-noise) and the corresponding "right" image
# which is the left shifted LEFT by SHIFT=8 pixels. Feed `/depth L R`
# to the chat for several cases:
#
#   1. Identical inputs (left twice): disparity ~= 0 across the image.
#      We expect the mean_disp field to read a single-digit number
#      (small enough that the density bucket is "low" or "mid"; the
#      4-bucket "low" label is the most likely answer for noise-free
#      identical inputs).
#
#   2. Shifted pair (left + left-shifted-by-8): the mean disparity
#      should be substantially > 0 -- the SAD search across textured
#      pixels recovers the shift. We assert `mean_disp=` followed by a
#      number >= 4 (under the chosen window/shift this consistently
#      lands in 6..10 in the unit test).
#
#   3. Dimension mismatch (40x40 vs 32x32): /depth must print a clear
#      "dim mismatch" error and the chat survive.
#
#   4. Missing file: /depth must print a parser error wrapped in parens.
#
# We also verify:
#   - `/help` advertises `/depth L.pgm R.pgm`.
#   - `/depth` with no arg / one arg prints the usage line.
#   - The chat reaches /quit cleanly after all probing.

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0

it_section "scenario HH: /depth PGM admin command (R7E SAD block-matching stereo disparity)"

LEFT="/tmp/ce_scenario_hh_left.pgm"
RIGHT_SHIFTED="/tmp/ce_scenario_hh_right_shifted.pgm"
RIGHT_SMALL="/tmp/ce_scenario_hh_right_small.pgm"
MISSING="/tmp/ce_scenario_hh_nonexistent.pgm"

# Cleanup any stale fixture files from a previous run.
rm -f "$LEFT" "$RIGHT_SHIFTED" "$RIGHT_SMALL" "$MISSING"

build_textured_pgm() {
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
        buf[y * W + x] = (x * 37 + y * 13) % 256
sys.stdout.buffer.write(bytes(buf))
"
    } > "$out"
}

build_shifted_pgm() {
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
            buf[y * W + x] = (sx * 37 + y * 13) % 256
        else:
            buf[y * W + x] = 0
sys.stdout.buffer.write(bytes(buf))
"
    } > "$out"
}

build_textured_pgm "$LEFT" 40 40
build_shifted_pgm  "$RIGHT_SHIFTED" 40 40 8
build_textured_pgm "$RIGHT_SMALL" 32 32

if [ ! -s "$LEFT" ] || [ ! -s "$RIGHT_SHIFTED" ] || [ ! -s "$RIGHT_SMALL" ]; then
    printf "  ${C_RED}FAIL${C_RST}  fixture files did not get written\n"
    FAIL=$((FAIL+1))
    summary "scenario_hh_stereo"
    exit
fi

INPUT=$(
    printf '/help\n'
    printf '/depth\n'
    printf '/depth %s\n' "$LEFT"
    printf '/depth %s %s\n' "$LEFT" "$LEFT"
    printf '/depth %s %s\n' "$LEFT" "$RIGHT_SHIFTED"
    printf '/depth %s %s\n' "$LEFT" "$RIGHT_SMALL"
    printf '/depth %s %s\n' "$MISSING" "$LEFT"
    printf '/quit\n'
)

OUT=$(echo "$INPUT" | "$CHAT" 2>&1)

# 1. /help advertises /depth.
assert_match "$OUT" "/depth L.pgm R.pgm +block-matching SAD stereo" \
    "/help advertises /depth"

# 2. /depth with no arg prints the usage line.
assert_match "$OUT" "/depth needs two PATHs" \
    "/depth with no arg prints usage"

# 3. /depth with only one arg prints the 'got 1' usage line.
assert_match "$OUT" "/depth needs TWO paths -- got 1" \
    "/depth with one arg prints usage"

# 4. /depth on identical inputs prints the depth summary line.
assert_match "$OUT" "depth 40x40 mean_disp=" \
    "/depth identical inputs emits depth summary"

# 5. /depth on identical inputs reports mean_disp=0 (every pixel matches at d=0).
assert_match "$OUT" "depth 40x40 mean_disp=0 " \
    "/depth identical inputs reports mean_disp=0"

# 6. /depth on shifted pair (SHIFT=8) reports mean_disp >= 4 -- the SAD
#    block-matching recovers some non-trivial chunk of the shift over
#    textured pixels.
assert_match "$OUT" "depth 40x40 mean_disp=([4-9]|1[0-9]|2[0-9]|3[0-9]|4[0-9]|5[0-9]|6[0-9])" \
    "/depth shifted pair reports mean_disp >= 4"

# 7. /depth on a shifted pair emits a density label (low / mid / high).
assert_match "$OUT" "image_stereo_density_(low|mid|high)" \
    "/depth shifted pair emits a density label"

# 8. /depth on dim-mismatched inputs prints the mismatch error.
assert_match "$OUT" "depth FAILED: dim mismatch" \
    "/depth on dim mismatch prints clear error"

# 9. /depth on missing file surfaces the PGM parser's bracketed error.
assert_match "$OUT" "depth FAILED on L:" \
    "/depth on missing L file prints parser error"

# 10. The chat survives all the malformed inputs and reaches /quit.
assert_match "$OUT" "bye\\." \
    "chat reaches /quit cleanly after /depth probing"

# Cleanup.
rm -f "$LEFT" "$RIGHT_SHIFTED" "$RIGHT_SMALL"

summary "scenario_hh_stereo"
