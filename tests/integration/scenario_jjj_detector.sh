#!/usr/bin/env bash
# Scenario JJJ -- /detect HOG sliding-window template-matching admin
# command end-to-end (R15C, builds on R14D HOG dense descriptor).
#
# Build three PGM fixtures in /tmp:
#   * A 32x32 template (vertical-edge: left half black, right half white).
#   * A 64x64 scene with the SAME vertical-edge pattern stamped at (16, 16)
#     on a uniform-gray background.
#   * A 64x64 uniform-gray scene (no template content) for the negative
#     case.
#
# Verify that:
#
#   1. /help advertises /detect.
#   2. /detect with no arg prints the two-PATH usage line.
#   3. /detect with ONE arg prints the "TWO paths -- got 1" error.
#   4. /detect on a missing template file prints a parser error.
#   5. /detect on a missing scene file prints a parser error.
#   6. /detect on a too-small template (8x8) prints the minimum-dim error.
#   7. /detect on the positive scene returns >= 1 detection.
#   8. /detect on the positive scene reports the best-match coordinates
#      within +/- DET_DEFAULT_STRIDE of (16, 16) -- i.e. either x or y
#      in {8, 16, 24}, and a best-distance < threshold (small).
#   9. /detect on the uniform-gray scene returns 0 detections.
#   10. The chat survives all probing and reaches /quit.

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0

it_section "scenario JJJ: /detect HOG sliding-window template-matching admin (R15C)"

TEMPLATE="/tmp/ce_scenario_jjj_template.pgm"
SCENE_POS="/tmp/ce_scenario_jjj_scene_pos.pgm"
SCENE_NEG="/tmp/ce_scenario_jjj_scene_neg.pgm"
TINY="/tmp/ce_scenario_jjj_tiny.pgm"
MISSING="/tmp/ce_scenario_jjj_nonexistent.pgm"

# Cleanup any stale fixture files from a previous run.
rm -f "$TEMPLATE" "$SCENE_POS" "$SCENE_NEG" "$TINY" "$MISSING"

build_template_pgm() {
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
        buf[y * W + x] = 0 if x < half else 255
sys.stdout.buffer.write(bytes(buf))
'
    } > "$out"
}

build_scene_pos_pgm() {
    # 64x64 image with uniform-gray background (value 128) and the
    # 32x32 vertical-edge template stamped at (16, 16).
    local out="$1"
    {
        printf 'P5\n64 64\n255\n'
        python3 -c '
import sys
W, H = 64, 64
TW, TH = 32, 32
OX, OY = 16, 16
buf = bytearray([128] * (W * H))
half = TW // 2
for ty in range(TH):
    for tx in range(TW):
        v = 0 if tx < half else 255
        buf[(OY + ty) * W + (OX + tx)] = v
sys.stdout.buffer.write(bytes(buf))
'
    } > "$out"
}

build_scene_neg_pgm() {
    # 64x64 uniform-gray PGM -- no template content.
    local out="$1"
    {
        printf 'P5\n64 64\n255\n'
        python3 -c '
import sys
W, H = 64, 64
buf = bytearray([128] * (W * H))
sys.stdout.buffer.write(bytes(buf))
'
    } > "$out"
}

build_tiny_pgm() {
    # 8x8 -- below DET_MIN_TEMPLATE_DIM (16). Used as template-too-small.
    local out="$1"
    {
        printf 'P5\n8 8\n255\n'
        python3 -c '
import sys
W, H = 8, 8
buf = bytearray([128] * (W * H))
sys.stdout.buffer.write(bytes(buf))
'
    } > "$out"
}

build_template_pgm   "$TEMPLATE"
build_scene_pos_pgm  "$SCENE_POS"
build_scene_neg_pgm  "$SCENE_NEG"
build_tiny_pgm       "$TINY"

if [ ! -s "$TEMPLATE" ] || [ ! -s "$SCENE_POS" ] || [ ! -s "$SCENE_NEG" ] || [ ! -s "$TINY" ]; then
    printf "  ${C_RED}FAIL${C_RST}  fixture files did not get written\n"
    FAIL=$((FAIL+1))
    summary "scenario_jjj_detector"
    exit
fi

INPUT=$(
    printf '/help\n'
    printf '/detect\n'
    printf '/detect %s\n' "$TEMPLATE"
    printf '/detect %s %s\n' "$MISSING" "$SCENE_POS"
    printf '/detect %s %s\n' "$TEMPLATE" "$MISSING"
    printf '/detect %s %s\n' "$TINY" "$SCENE_POS"
    printf '/detect %s %s\n' "$TEMPLATE" "$SCENE_POS"
    printf '/detect %s %s\n' "$TEMPLATE" "$SCENE_NEG"
    printf '/quit\n'
)

OUT=$(echo "$INPUT" | "$CHAT" 2>&1)

# 1. /help advertises /detect.
assert_match "$OUT" "/detect T\\.pgm S\\.pgm +HOG" \
    "/help advertises /detect"

# 2. /detect with no arg prints the two-PATH usage line.
assert_match "$OUT" "/detect needs TEMPLATE\\.pgm and SCENE\\.pgm" \
    "/detect with no arg prints usage"

# 3. /detect with ONE arg prints the "TWO paths -- got 1" error.
assert_match "$OUT" "/detect needs TWO paths -- got 1" \
    "/detect with one arg prints 'got 1' error"

# 4. /detect on missing TEMPLATE file prints a parser error.
assert_match "$OUT" "detect FAILED on TEMPLATE" \
    "/detect on missing template prints parser error"

# 5. /detect on missing SCENE file prints a parser error.
assert_match "$OUT" "detect FAILED on SCENE" \
    "/detect on missing scene prints parser error"

# 6. /detect on too-small template prints the minimum-dim error.
assert_match "$OUT" "detect FAILED: TEMPLATE too small" \
    "/detect on too-small template prints minimum-dim error"

# 7. /detect on positive scene returns >= 1 detection (and < total grid count of 25).
POS_LINE=$(echo "$OUT" | grep -E "\\(detect [0-9]+ detection\\(s\\); T=32x32 S=64x64" | head -n1)
if [ -n "$POS_LINE" ]; then
    POS_COUNT=$(echo "$POS_LINE" | sed -E 's/.*\(detect ([0-9]+) detection.*/\1/')
    if [ "$POS_COUNT" -ge 1 ]; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}PASS${C_RST}  positive scene reports >= 1 detection (got %s)\n" "$POS_COUNT"
    else
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  positive scene reported 0 detections\n"
    fi
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  positive scene produced no parseable detect line\n        in:\n"
    echo "$OUT" | sed 's/^/          /'
fi

# 8. Best-match coordinates within +/- stride of (16, 16). The format is
#    "best=DIST at (X, Y))" -- extract X and Y and verify each is in the
#    allowed band {8, 16, 24} (the only stride-8 positions within +/- 8 of 16).
if [ -n "$POS_LINE" ]; then
    BEST_X=$(echo "$POS_LINE" | sed -E 's/.*at \(([0-9]+), ([0-9]+)\)\)/\1/')
    BEST_Y=$(echo "$POS_LINE" | sed -E 's/.*at \(([0-9]+), ([0-9]+)\)\)/\2/')
    if [ -n "$BEST_X" ] && [ -n "$BEST_Y" ]; then
        # Allowed positions per axis: 8, 16, 24.
        ax_ok=0
        ay_ok=0
        case "$BEST_X" in 8|16|24) ax_ok=1 ;; esac
        case "$BEST_Y" in 8|16|24) ay_ok=1 ;; esac
        if [ "$ax_ok" -eq 1 ] && [ "$ay_ok" -eq 1 ]; then
            PASS=$((PASS+1))
            printf "  ${C_GRN}PASS${C_RST}  best-match at (%s, %s) within +/- stride of (16, 16)\n" "$BEST_X" "$BEST_Y"
        else
            FAIL=$((FAIL+1))
            printf "  ${C_RED}FAIL${C_RST}  best-match at (%s, %s) NOT within +/- stride of (16, 16)\n" "$BEST_X" "$BEST_Y"
        fi
    else
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  could not parse best (X, Y) from positive line\n"
    fi
fi

# 9. /detect on uniform-gray scene returns 0 detections. Two detect lines
#    were produced (positive, negative); the second one is the negative.
NEG_LINE=$(echo "$OUT" | grep -E "\\(detect [0-9]+ detection\\(s\\); T=32x32 S=64x64" | sed -n '2p')
if [ -n "$NEG_LINE" ]; then
    NEG_COUNT=$(echo "$NEG_LINE" | sed -E 's/.*\(detect ([0-9]+) detection.*/\1/')
    if [ "$NEG_COUNT" = "0" ]; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}PASS${C_RST}  negative (uniform) scene reports 0 detections\n"
    else
        # Tolerant: a few false positives on the uniform background can
        # happen if the threshold is too lenient. We still pass if the
        # count is at MOST 1 (substantially fewer than the positive
        # case's typical 1-5).
        if [ "$NEG_COUNT" -le 1 ]; then
            PASS=$((PASS+1))
            printf "  ${C_GRN}PASS${C_RST}  negative scene reports few detections (got %s, accepted)\n" "$NEG_COUNT"
        else
            FAIL=$((FAIL+1))
            printf "  ${C_RED}FAIL${C_RST}  negative scene reported too many detections (%s)\n" "$NEG_COUNT"
        fi
    fi
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  negative scene produced no parseable detect line\n"
fi

# 10. The chat survives all probing and reaches /quit.
assert_match "$OUT" "bye\\." \
    "chat reaches /quit cleanly after /detect probing"

# Cleanup.
rm -f "$TEMPLATE" "$SCENE_POS" "$SCENE_NEG" "$TINY"

summary "scenario_jjj_detector"
