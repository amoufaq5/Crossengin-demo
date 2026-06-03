#!/usr/bin/env bash
# Scenario MMMM -- R23D: image object tracking via Kalman filter +
# greedy Hungarian assignment over a sequence of PGM frames.
#
# R15C HOG sliding-window and R16D Haar face detectors produce per-frame
# detections; R23D associates them across frames into persistent tracks
# with stable IDs via per-track Kalman predict + update loop and a
# greedy minimum-L2 assignment step.
#
# Assertions:
#   1. /track no arg -> usage
#   2. /track missing dir -> graceful FAILED
#   3. /track on 5-frame fixture scans 5 frames
#   4. /track reports 1 total track
#   5. /track confirmed=1 after 5 consecutive matches
#   6. /track #1 status=confirmed
#   7. velocity vx ~ +5000 milli/frame
#   8. velocity vy ~ +5000 milli/frame
#   9. final position near (30, 30)
#  10. lost fixture scans 10 frames
#  11. lost=1 after 5 missed frames
#  12. /help advertises /track
#  13. /help labels /track as R23D

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

it_section "scenario MMMM: R23D image object tracking via Kalman filter (chat /track)"

require_chat

FRAME_DIR="/tmp/ce_scenario_mmmm_frames"
LOST_DIR="/tmp/ce_scenario_mmmm_lost"
MISSING_DIR="/tmp/ce_scenario_mmmm_definitely_missing_dir"

rm -rf "$FRAME_DIR" "$LOST_DIR"
mkdir -p "$FRAME_DIR" "$LOST_DIR"
trap 'rm -rf "$FRAME_DIR" "$LOST_DIR"' EXIT

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

build_frame_pgm "$FRAME_DIR/frame_0001.pgm" 10 10
build_frame_pgm "$FRAME_DIR/frame_0002.pgm" 15 15
build_frame_pgm "$FRAME_DIR/frame_0003.pgm" 20 20
build_frame_pgm "$FRAME_DIR/frame_0004.pgm" 25 25
build_frame_pgm "$FRAME_DIR/frame_0005.pgm" 30 30

build_frame_pgm "$LOST_DIR/frame_0001.pgm" 10 10
build_frame_pgm "$LOST_DIR/frame_0002.pgm" 15 15
build_frame_pgm "$LOST_DIR/frame_0003.pgm" 20 20
build_frame_pgm "$LOST_DIR/frame_0004.pgm" 25 25
build_frame_pgm "$LOST_DIR/frame_0005.pgm" 30 30

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
build_black_pgm "$LOST_DIR/frame_0006.pgm"
build_black_pgm "$LOST_DIR/frame_0007.pgm"
build_black_pgm "$LOST_DIR/frame_0008.pgm"
build_black_pgm "$LOST_DIR/frame_0009.pgm"
build_black_pgm "$LOST_DIR/frame_0010.pgm"

for f in "$FRAME_DIR"/*.pgm "$LOST_DIR"/*.pgm; do
    if [ ! -s "$f" ]; then
        printf "  ${C_RED}FAIL${C_RST}  fixture frame %s did not get written\n" "$f"
        FAIL=$((FAIL+1))
        summary "scenario_mmmm_tracker"
        exit
    fi
done

NOARG_OUT=$(run_chat "/track")
assert_match "$NOARG_OUT" "/track needs VIDEO_DIR" \
    "/track with no arg shows usage hint"

MISSING_OUT=$(run_chat "/track $MISSING_DIR")
assert_match "$MISSING_OUT" "track FAILED" \
    "/track on missing dir reports graceful FAILED"

MOVING_OUT=$(run_chat "/track $FRAME_DIR")
assert_match "$MOVING_OUT" "scanned 5 frame" \
    "/track scans all 5 frames"
assert_match "$MOVING_OUT" "1 track\(s\) total" \
    "/track reports 1 total track for the moving object"
assert_match "$MOVING_OUT" "confirmed=1" \
    "/track promotes the object to confirmed after 5 hits"
assert_match "$MOVING_OUT" "track #1 status=confirmed" \
    "/track #1 status=confirmed"

VEL_LINE=$(echo "$MOVING_OUT" | grep -E 'track #1.*vel=' | head -1)
if [ -n "$VEL_LINE" ]; then
    VX=$(echo "$VEL_LINE" | sed -E 's/.*vel=\(([-0-9]+), ([-0-9]+)\).*/\1/')
    VY=$(echo "$VEL_LINE" | sed -E 's/.*vel=\(([-0-9]+), ([-0-9]+)\).*/\2/')
    vx_ok=0
    if [ -n "$VX" ]; then
        if [ "$VX" -ge 2000 ] && [ "$VX" -le 6000 ]; then
            vx_ok=1
        fi
    fi
    if [ "$vx_ok" = "1" ]; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}PASS${C_RST}  track velocity vx ~ +5000 milli/frame (got %s)\n" "$VX"
    else
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  track velocity vx not in [2000, 6000] (got %s)\n" "$VX"
    fi
    vy_ok=0
    if [ -n "$VY" ]; then
        if [ "$VY" -ge 2000 ] && [ "$VY" -le 6000 ]; then
            vy_ok=1
        fi
    fi
    if [ "$vy_ok" = "1" ]; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}PASS${C_RST}  track velocity vy ~ +5000 milli/frame (got %s)\n" "$VY"
    else
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  track velocity vy not in [2000, 6000] (got %s)\n" "$VY"
    fi
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  /track output did not contain a parseable vel= line\n"
    echo "$MOVING_OUT" | sed 's/^/        /'
fi

POS_LINE=$(echo "$MOVING_OUT" | grep -E 'track #1.*pos=' | head -1)
if [ -n "$POS_LINE" ]; then
    PX=$(echo "$POS_LINE" | sed -E 's/.*pos=\(([-0-9]+), ([-0-9]+)\).*/\1/')
    PY=$(echo "$POS_LINE" | sed -E 's/.*pos=\(([-0-9]+), ([-0-9]+)\).*/\2/')
    pos_ok=0
    if [ -n "$PX" ] && [ -n "$PY" ]; then
        if [ "$PX" -ge 20 ] && [ "$PX" -le 40 ]; then
            if [ "$PY" -ge 20 ] && [ "$PY" -le 40 ]; then
                pos_ok=1
            fi
        fi
    fi
    if [ "$pos_ok" = "1" ]; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}PASS${C_RST}  /track final position pos=(%s, %s) within +/- 10 of (30, 30)\n" "$PX" "$PY"
    else
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  /track final position pos=(%s, %s) NOT within +/- 10 of (30, 30)\n" "$PX" "$PY"
    fi
fi

LOST_OUT=$(run_chat "/track $LOST_DIR")
assert_match "$LOST_OUT" "scanned 10 frame" \
    "/track on lost fixture scans 10 frames"
assert_match "$LOST_OUT" "lost=1" \
    "/track marks track as lost after 5 missed frames"

HELP_OUT=$(run_chat "/help")
assert_match "$HELP_OUT" "/track" \
    "/help advertises /track command"
assert_match "$HELP_OUT" "R23D" \
    "/help labels /track as R23D"

summary "scenario_mmmm_tracker"
