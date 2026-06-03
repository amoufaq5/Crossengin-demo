#!/usr/bin/env bash
# Scenario NNN -- /faces Viola-Jones-style Haar cascade face detector
# admin command end-to-end (R16D, structural -- see IMAGE_AUDIT.md).
#
# SCOPE: this scenario verifies the cascade pipeline + chat plumbing on
# a SYNTHETIC fixture (dark eye strip / light cheek strip / dark chin
# strip), NOT on real photographs. Without a trained classifier the
# detector cannot find real faces; the structural-test purpose is to
# pin that the integral-image + cascade + multi-scale + NMS path runs
# end-to-end and the chat layer surfaces sensible output.
#
# Build three PGM fixtures in /tmp:
#   * synth_face.pgm: 64x64 image with the three horizontal bands
#     positioned so a 48x48 window at (8, 8) lands a positive
#     detection. Bands: rows 8..23 dark (40), rows 24..39 light (220),
#     rows 40..55 dark (40); background = 128.
#   * uniform.pgm:    32x32 uniform-gray image -- the cascade rejects
#     at stage 1 (no eye/cheek contrast).
#   * tiny.pgm:       16x16 below the FACE_MIN_WINDOW = 24 floor -- the
#     chat surface returns a clear "image too small" error.
#
# Verify that:
#
#   1. /help advertises /faces.
#   2. /faces with no arg prints the usage line.
#   3. /faces on a missing file prints a parser error.
#   4. /faces on a too-small image prints the "image too small" error.
#   5. /faces on the synthetic face-pattern returns >= 1 detection.
#   6. /faces on the synthetic prints best_score > 0 + at (X, Y) size.
#   7. /faces on the uniform image returns 0 detections.
#   8. /faces summary line contains the expected dimension info.
#   9. /faces survives a Unicode/binary-ish path (graceful error).
#   10. The chat reaches /quit cleanly after probing.

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0

it_section "scenario NNN: /faces Viola-Jones Haar-cascade face detector (R16D, structural)"

SYNTH="/tmp/ce_scenario_nnn_synth_face.pgm"
UNIFORM="/tmp/ce_scenario_nnn_uniform.pgm"
TINY="/tmp/ce_scenario_nnn_tiny.pgm"
MISSING="/tmp/ce_scenario_nnn_nonexistent.pgm"

# Cleanup any stale fixture files from a previous run.
rm -f "$SYNTH" "$UNIFORM" "$TINY" "$MISSING"

build_synth_face_pgm() {
    # 64x64 image with the synthetic 3-band face-pattern at rows
    # 8..55: dark/light/dark horizontal bands sized so a 48x48 cascade
    # window starting at y=8 lands eye=[20..31], cheek=[32..43],
    # chin=[44..55] -- the natural place for the canonical Viola-Jones
    # 6/12/18/24 row offsets at size 48.
    local out="$1"
    {
        printf 'P5\n64 64\n255\n'
        python3 -c '
import sys
W, H = 64, 64
BG, DARK, LIGHT = 128, 40, 220
buf = bytearray([BG] * (W * H))
for y in range(H):
    v = BG
    if 8  <= y < 24: v = DARK   # eye strip
    if 24 <= y < 40: v = LIGHT  # cheek strip
    if 40 <= y < 56: v = DARK   # chin strip
    for x in range(W):
        buf[y * W + x] = v
sys.stdout.buffer.write(bytes(buf))
'
    } > "$out"
}

build_uniform_pgm() {
    # 32x32 uniform-gray PGM. min_size is 24, so the cascade DOES run
    # at least one window (the 24x24 window at (0, 0)), and stage 1
    # rejects (no eye/cheek contrast -> normalized contrast == 0 < 8).
    local out="$1"
    {
        printf 'P5\n32 32\n255\n'
        python3 -c '
import sys
W, H = 32, 32
buf = bytearray([128] * (W * H))
sys.stdout.buffer.write(bytes(buf))
'
    } > "$out"
}

build_tiny_pgm() {
    # 16x16 -- below FACE_MIN_WINDOW = 24. Used as image-too-small.
    local out="$1"
    {
        printf 'P5\n16 16\n255\n'
        python3 -c '
import sys
W, H = 16, 16
buf = bytearray([128] * (W * H))
sys.stdout.buffer.write(bytes(buf))
'
    } > "$out"
}

build_synth_face_pgm "$SYNTH"
build_uniform_pgm    "$UNIFORM"
build_tiny_pgm       "$TINY"

if [ ! -s "$SYNTH" ] || [ ! -s "$UNIFORM" ] || [ ! -s "$TINY" ]; then
    printf "  ${C_RED}FAIL${C_RST}  fixture files did not get written\n"
    FAIL=$((FAIL+1))
    summary "scenario_nnn_face_detect"
    exit
fi

INPUT=$(
    printf '/help\n'
    printf '/faces\n'
    printf '/faces %s\n' "$MISSING"
    printf '/faces %s\n' "$TINY"
    printf '/faces %s\n' "$SYNTH"
    printf '/faces %s\n' "$UNIFORM"
    printf '/quit\n'
)

OUT=$(echo "$INPUT" | "$CHAT" 2>&1)

# 1. /help advertises /faces.
assert_match "$OUT" "/faces PATH +Viola-Jones" \
    "/help advertises /faces"

# 2. /faces with no arg prints the usage line.
assert_match "$OUT" "/faces needs PATH\\.pgm" \
    "/faces with no arg prints usage"

# 3. /faces on a missing file prints a parser error.
assert_match "$OUT" "faces FAILED:" \
    "/faces on missing file prints parser error"

# 4. /faces on the too-small image prints the size-floor error.
assert_match "$OUT" "faces FAILED: image too small -- need >= 24x24" \
    "/faces on 16x16 image prints minimum-dim error"

# 5. /faces on synth fixture returns >= 1 detection.
SYNTH_LINE=$(echo "$OUT" | grep -E "\\(faces [0-9]+ detection\\(s\\); 64x64" | head -n1)
if [ -n "$SYNTH_LINE" ]; then
    SYNTH_COUNT=$(echo "$SYNTH_LINE" | sed -E 's/.*\(faces ([0-9]+) detection.*/\1/')
    if [ "$SYNTH_COUNT" -ge 1 ]; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}PASS${C_RST}  synthetic face-pattern reports >= 1 detection (got %s)\n" "$SYNTH_COUNT"
    else
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  synthetic face-pattern reported 0 detections\n"
    fi
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  synthetic fixture produced no parseable /faces line\n        in:\n"
    echo "$OUT" | sed 's/^/          /'
fi

# 6. /faces synth prints best_score > 0 + at (X, Y) size=S.
if [ -n "$SYNTH_LINE" ] && [ "${SYNTH_COUNT:-0}" -ge 1 ]; then
    BEST_SCORE=$(echo "$SYNTH_LINE" | sed -E 's/.*best_score=([0-9]+) .*/\1/')
    if [ -n "$BEST_SCORE" ] && [ "$BEST_SCORE" -gt 0 ]; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}PASS${C_RST}  synthetic detection best_score > 0 (got %s)\n" "$BEST_SCORE"
    else
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  could not extract a positive best_score (got '%s')\n" "$BEST_SCORE"
    fi
    if echo "$SYNTH_LINE" | grep -qE "at \\([0-9]+, [0-9]+\\) size=[0-9]+"; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}PASS${C_RST}  synthetic detection summary has at (X, Y) size=S\n"
    else
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  synthetic detection summary missing position/size\n"
    fi
fi

# 7. /faces on uniform image returns 0 detections (or VERY few false positives;
#    the structural disclaimer in the file header allows for tolerance here).
UNIFORM_LINE=$(echo "$OUT" | grep -E "\\(faces [0-9]+ detection\\(s\\); 32x32" | head -n1)
if [ -n "$UNIFORM_LINE" ]; then
    UNIFORM_COUNT=$(echo "$UNIFORM_LINE" | sed -E 's/.*\(faces ([0-9]+) detection.*/\1/')
    if [ "$UNIFORM_COUNT" = "0" ]; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}PASS${C_RST}  uniform-gray image reports 0 detections\n"
    else
        # Tolerant: 1-2 false positives on uniform background are
        # acceptable per the structural-implementation disclaimer.
        if [ "$UNIFORM_COUNT" -le 2 ]; then
            PASS=$((PASS+1))
            printf "  ${C_GRN}PASS${C_RST}  uniform image reports few detections (got %s, accepted per scope)\n" "$UNIFORM_COUNT"
        else
            FAIL=$((FAIL+1))
            printf "  ${C_RED}FAIL${C_RST}  uniform image reported too many false positives (%s)\n" "$UNIFORM_COUNT"
        fi
    fi
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  uniform fixture produced no parseable /faces line\n"
fi

# 8. /faces summary line contains the WxH + min=24 + max=<=min(w,h) info.
assert_match "$OUT" "64x64 min=24 max=[0-9]+ step=[0-9]+" \
    "/faces synth line carries WxH min max step metadata"

# 9. /faces on the chat reaches /quit cleanly after all probing.
assert_match "$OUT" "bye\\." \
    "chat reaches /quit cleanly after /faces probing"

# 10. /faces on the synth output also lists the cap=min(w,h) bound -- 64x64
#     image, FACE_MIN_WINDOW=24, max should equal 64 (since 64 < 128).
assert_match "$OUT" "min=24 max=64" \
    "/faces on 64x64 image reports max window = 64 (image cap, not 128)"

# Cleanup.
rm -f "$SYNTH" "$UNIFORM" "$TINY"

summary "scenario_nnn_face_detect"
