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

rm -f "$FIX" "$BAD"

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

# Cleanup.
rm -f "$FIX" "$BAD"

summary "scenario_s_video_play"
