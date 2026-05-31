#!/usr/bin/env bash
# Scenario S -- /play Y4M admin command end-to-end (P3.2 / ADR-0014).
#
# Build a hand-rolled raw Y4M (YUV4MPEG2) fixture in /tmp with 5 frames
# at 4x4 4:2:0 chroma, boot the chat, feed `/play /tmp/<fixture>.y4m
# 5`, verify the chat (a) prints the operator-readable summary line
# with frame count and scene-change tally, (b) emits per-frame event
# lines carrying the image features + motion + scene-change labels,
# and (c) /help advertises the command.
#
# Acceptance:
#   - /help advertises /play PATH [N] (one line, in the visual / video
#     admin block).
#   - /play <fixture> 5 prints "(played /tmp/<fixture>.y4m: 5 frame(s),
#     4x4, ..., scene changes: <K>, decoder=y4m)".
#   - Each of the 5 frame lines contains "frame N:" with N in 0..4.
#   - Frame 0 carries image_dim_small (4x4 = 16 px area).
#   - Frames after a forced delta (constant -> 255) include scene_change
#     and motion_high atoms.
#   - /play with no arg prints the usage line; the chat keeps running.
#   - /play on a non-Y4M file (truncated random bytes) prints the
#     parser's bracketed error message; the chat keeps running.

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0

it_section "scenario S: /play Y4M video admin command (ADR-0014 video seam)"

FIX="/tmp/ce_scenario_s.y4m"
BAD="/tmp/ce_scenario_s_bad.bin"
MV="/tmp/ce_scenario_s_mv.y4m"

rm -f "$FIX" "$BAD" "$MV"

# Build a 5-frame 4x4 Y4M 4:2:0 fixture.
# Per-frame: "FRAME\n" + 16 Y bytes + 4 Cb bytes + 4 Cr bytes = 30 bytes.
# Frame Y values: frame 0 = 50, frame 1 = 60 (small delta -> motion_low),
# frame 2 = 200 (huge delta -> motion_high + scene_change), frame 3 = 210
# (small delta), frame 4 = 30 (huge delta again -> motion_high +
# scene_change). Chroma stays at 128 (neutral) throughout.
{
    printf 'YUV4MPEG2 W4 H4 F30:1 Ip A1:1 C420\n'
    # frame 0 -- Y=50 chroma=128 (4:2:0 = 1x1 chroma plane = 1 byte? NO --
    # at 4x4 it's 2x2 = 4 bytes per plane).
    printf 'FRAME\n'
    head -c 16 /dev/zero | tr '\000' '\062'   # 0x32 == 50
    head -c 4  /dev/zero | tr '\000' '\200'   # 0x80 == 128 (Cb)
    head -c 4  /dev/zero | tr '\000' '\200'   # Cr
    # frame 1 -- Y=60 (motion_low: |60-50|=10 < 15)
    printf 'FRAME\n'
    head -c 16 /dev/zero | tr '\000' '\074'   # 0x3c == 60
    head -c 4  /dev/zero | tr '\000' '\200'
    head -c 4  /dev/zero | tr '\000' '\200'
    # frame 2 -- Y=200 (motion_high: |200-60|=140; scene_change too)
    printf 'FRAME\n'
    head -c 16 /dev/zero | tr '\000' '\310'   # 0xc8 == 200
    head -c 4  /dev/zero | tr '\000' '\200'
    head -c 4  /dev/zero | tr '\000' '\200'
    # frame 3 -- Y=210 (motion_low: |210-200|=10)
    printf 'FRAME\n'
    head -c 16 /dev/zero | tr '\000' '\322'   # 0xd2 == 210
    head -c 4  /dev/zero | tr '\000' '\200'
    head -c 4  /dev/zero | tr '\000' '\200'
    # frame 4 -- Y=30 (motion_high: |30-210|=180; scene_change too)
    printf 'FRAME\n'
    head -c 16 /dev/zero | tr '\000' '\036'   # 0x1e == 30
    head -c 4  /dev/zero | tr '\000' '\200'
    head -c 4  /dev/zero | tr '\000' '\200'
} > "$FIX"

# Build a bad fixture: 16 bytes with the wrong magic. We need >= 9 bytes
# (Y4M_MAGIC_LEN) so the parser reaches the magic check rather than
# bailing out with "buffer too short".
printf '\x4e\x4f\x54\x59\x34\x4d\x32\x42\x41\x44\x42\x59\x54\x45\x53\x21' > "$BAD"

# Build a 32x32 Y4M fixture with KNOWN LEFTWARD MOTION. Frames contain a
# 16x16 white block on a black background. The block moves from x=16 in
# frame 0 to x=12 in frame 1 to x=8 in frame 2 (4 pixels left per frame).
# The motion vector field's per-block search finds the block's PREVIOUS
# position to the RIGHT of its current position -> positive dx ->
# motion_dir_left. At 32x32 with 16x16 blocks we have a 2x2 block grid.
# Per frame Y plane: 32*32 = 1024 bytes; chroma planes: 16*16 = 256 bytes
# each; per frame total: 6 + 1024 + 256 + 256 = 1542 bytes.
python3 - <<'PY' > "$MV"
import sys, struct
sys.stdout = sys.stdout.buffer if hasattr(sys.stdout, "buffer") else sys.stdout

def emit(b):
    sys.stdout.write(b)

# Header.
emit(b"YUV4MPEG2 W32 H32 F30:1 Ip A1:1 C420\n")

W = 32
H = 32

def frame_with_block(bx, by, bsize=16):
    # Y plane: 0 everywhere except 255 inside the block.
    plane = bytearray(W * H)
    for y in range(by, by + bsize):
        if 0 <= y < H:
            for x in range(bx, bx + bsize):
                if 0 <= x < W:
                    plane[y * W + x] = 255
    return plane

# 3 frames with the block moving leftward by 4 px each frame.
for bx in (16, 12, 8):
    emit(b"FRAME\n")
    emit(bytes(frame_with_block(bx, 8)))
    emit(b"\x80" * (16 * 16))   # Cb
    emit(b"\x80" * (16 * 16))   # Cr
PY

if [ ! -s "$FIX" ]; then
    printf "  ${C_RED}FAIL${C_RST}  fixture %s did not get written\n" "$FIX"
    FAIL=$((FAIL+1))
    summary "scenario_s_video_play"
    exit
fi

INPUT=$(
    printf '/help\n'
    printf '/play\n'
    printf '/play %s 5\n' "$FIX"
    printf '/play %s 3\n' "$MV"
    printf '/play %s\n' "$BAD"
    printf '/quit\n'
)

OUT=$(echo "$INPUT" | "$CHAT" 2>&1)

# 1. /help advertises /play PATH [N].
assert_match "$OUT" "/play PATH \[N\] +decode N frames" \
    "/help advertises /play"

# 2. /play with no arg prints the usage line.
assert_match "$OUT" "/play needs PATH" \
    "/play with no arg prints usage"

# 3. /play on the fixture prints the operator-readable summary.
assert_match "$OUT" "played $FIX: 5 frame\(s\), 4x4" \
    "/play prints frame count + dims on 4x4 fixture"

# 4. Scene change tally is 2 (frame 2 vs 1; frame 4 vs 3).
assert_match "$OUT" "scene changes: 2" \
    "/play reports two scene changes"

# 5. Decoder is named y4m in the summary.
assert_match "$OUT" "decoder=y4m" \
    "/play summary names the y4m decoder"

# 6. Frame 0 line carries image_dim_small (4x4 = 16 px area).
assert_match "$OUT" "frame 0:.*image_dim_small" \
    "/play frame 0 carries image_dim_small"

# 7. Frame 2 line carries motion_high (delta 140 >= 50).
assert_match "$OUT" "frame 2:.*motion_high" \
    "/play frame 2 carries motion_high"

# 8. Frame 2 line carries scene_change.
assert_match "$OUT" "frame 2:.*scene_change" \
    "/play frame 2 carries scene_change"

# 9. Frame 4 line carries motion_high.
assert_match "$OUT" "frame 4:.*motion_high" \
    "/play frame 4 carries motion_high"

# 10. Frame 4 line carries scene_change.
assert_match "$OUT" "frame 4:.*scene_change" \
    "/play frame 4 carries scene_change"

# 11. /play on bad bytes surfaces the parser's bracketed error.
assert_match "$OUT" "play FAILED: y4m: bad magic" \
    "/play on non-Y4M bytes prints the parser's error"

# 12. The chat survives the bad input and reaches /quit.
assert_match "$OUT" "bye\." \
    "chat reaches /quit cleanly after malformed /play"

# ---- P3.3 motion vector field on 32x32 leftward-motion fixture ----------

# 13. /play on the 32x32 motion fixture prints its summary.
assert_match "$OUT" "played $MV: 3 frame\(s\), 32x32" \
    "/play prints frame count + dims on 32x32 motion fixture"

# 14. The motion vector field detects LEFTWARD motion on frames 1 and 2
# (the white block moves left between consecutive frames). The per-frame
# event line includes motion_dir_left.
assert_match "$OUT" "frame 1:.*motion_dir_left" \
    "/play frame 1 of 32x32 fixture carries motion_dir_left"

# 15. The motion is simple (uniform translation of one block), so the
# complexity label is motion_complexity_simple on at least frame 2.
assert_match "$OUT" "frame 2:.*motion_complexity_simple" \
    "/play frame 2 of 32x32 fixture carries motion_complexity_simple"

# Cleanup.
rm -f "$FIX" "$BAD" "$MV"

summary "scenario_s_video_play"
