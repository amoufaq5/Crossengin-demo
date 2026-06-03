#!/usr/bin/env bash
# Scenario RRRR -- R24F: video temporal smoothing -- Kalman over R23D
# tracker outputs.
#
# R23D ships per-track Kalman + greedy Hungarian assignment; R24F builds
# scene-level smoothing on top: given a sequence of per-frame detection
# results (possibly noisy / missing / false-positive), produce a
# temporally-smoothed sequence of confirmed tracks with predicted
# positions for missing frames.
#
# Assertions:
#   1. /smooth no arg -> usage
#   2. /smooth missing dir -> graceful FAILED
#   3. /smooth on 5-frame fixture scans 5 frames
#   4. /smooth dense field has 5 frame slot(s)
#   5. /smooth reports tracks_in_field=1
#   6. /smooth track #1 present=5/5 (all frames)
#   7. /smooth track #1 real=4 (frame 3 has dropped detection)
#   8. /smooth track #1 predicted=1
#   9. /smooth track #1 continuity_milli=800 (4/5 real)
#  10. /help advertises /smooth
#  11. /help labels /smooth as R24F

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

it_section "scenario RRRR: R24F video temporal smoothing (chat /smooth)"

require_chat

FRAME_DIR="/tmp/ce_scenario_rrrr_frames"
MISSING_DIR="/tmp/ce_scenario_rrrr_definitely_missing_dir"

rm -rf "$FRAME_DIR"
mkdir -p "$FRAME_DIR"
trap 'rm -rf "$FRAME_DIR"' EXIT

build_frame_pgm() {
    local out="$1"; local cx="$2"; local cy="$3"
    {
        printf 'P5\n40 40\n255\n'
        python3 -c "
import sys
W, H = 40, 40
CX, CY = $cx, $cy
buf = bytearray(W * H)
half = 3
for y in range(H):
    for x in range(W):
        if abs(x - CX) <= half and abs(y - CY) <= half:
            buf[y * W + x] = 255
        else:
            buf[y * W + x] = 0
sys.stdout.buffer.write(bytes(buf))
"
    } > "$out"
}

build_black_pgm() {
    local out="$1"
    {
        printf 'P5\n40 40\n255\n'
        python3 -c "
import sys
W, H = 40, 40
sys.stdout.buffer.write(bytes(W * H))
"
    } > "$out"
}

# 5-frame fixture: bright spot moves (10,10) -> (15,15) -> MISSING -> (25,25) -> (30,30).
# Frame 3 is black -- centroid detector returns 0 detections, exercising
# the missing-frame Kalman interpolation path.
build_frame_pgm  "$FRAME_DIR/frame_0001.pgm" 10 10
build_frame_pgm  "$FRAME_DIR/frame_0002.pgm" 15 15
build_black_pgm  "$FRAME_DIR/frame_0003.pgm"
build_frame_pgm  "$FRAME_DIR/frame_0004.pgm" 25 25
build_frame_pgm  "$FRAME_DIR/frame_0005.pgm" 30 30

for f in "$FRAME_DIR"/*.pgm; do
    if [ ! -s "$f" ]; then
        printf "  ${C_RED}FAIL${C_RST}  fixture frame %s did not get written\n" "$f"
        FAIL=$((FAIL+1))
        summary "scenario_rrrr_video_smooth"
        exit
    fi
done

NOARG_OUT=$(run_chat "/smooth")
assert_match "$NOARG_OUT" "/smooth needs VIDEO_DIR" \
    "/smooth with no arg shows usage hint"

MISSING_OUT=$(run_chat "/smooth $MISSING_DIR")
assert_match "$MISSING_OUT" "smooth FAILED" \
    "/smooth on missing dir reports graceful FAILED"

GAP_OUT=$(run_chat "/smooth $FRAME_DIR")
assert_match "$GAP_OUT" "smooth scanned 5 frame" \
    "/smooth scans all 5 frames"
assert_match "$GAP_OUT" "dense field of 5 frame slot" \
    "/smooth dense field has 5 frame slot(s)"
assert_match "$GAP_OUT" "tracks_in_field=1" \
    "/smooth reports a single track across the dense field"
assert_match "$GAP_OUT" "present=5/5" \
    "/smooth track #1 present in all 5 frames (including the gap)"
assert_match "$GAP_OUT" "real=4" \
    "/smooth track #1 had 4 real detections (frame 3 was a gap)"
assert_match "$GAP_OUT" "predicted=1" \
    "/smooth track #1 had 1 Kalman-predicted frame"
assert_match "$GAP_OUT" "continuity_milli=800" \
    "/smooth track #1 continuity_milli=800 (4/5 real)"

HELP_OUT=$(run_chat "/help")
assert_match "$HELP_OUT" "/smooth" \
    "/help advertises /smooth command"
assert_match "$HELP_OUT" "R24F" \
    "/help labels /smooth as R24F"

summary "scenario_rrrr_video_smooth"
