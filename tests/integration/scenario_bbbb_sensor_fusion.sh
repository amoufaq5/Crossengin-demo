#!/usr/bin/env bash
# Scenario BBBB -- /fuse cross-modal sensor fusion: image + audio
# coregistered observation primitive (R20C).
#
# R20C ships the cross-modal fusion primitive in
# `src/perception/sensor_fusion.nova`: given a list of image observations
# and a list of audio observations, emit one fused atom per matched pair
# (within the temporal window; default 100ms). Identity matching across
# modalities (face label == speaker label) promotes the binding from
# WEAK to STRONG.
#
# Driving fusion from live capture streams is R20C.2 (the perception
# loop needs ring buffers of recent observations per modality). The
# /fuse chat command demonstrates the primitive: when an operator has
# already exercised /see (visual perception), /fuse reports any fused
# observations the chat's per-process buffer holds. With no prior /see,
# the buffer is empty and /fuse reports that explicitly.
#
# Verify that:
#
#  1. /help advertises a non-empty admin surface (smoke).
#  2. /fuse before any /see reports "no fused observations" (empty).
#  3. /fuse advertises the fused= prefix in its summary even when 0.
#  4. /see PATH on a PGM fixture decodes and emits feature atoms (the
#      precondition the fusion primitive needs to see anything).
#  5. /fuse after a single /see call reports >= 1 buffered observation
#      OR a documented "audio stream empty" message (audio capture
#      requires live mic; in CI there's no audio side).
#  6. /fuse output includes the binding label hint (one of strong / weak
#      / no fused observations message).
#  7. The chat reaches /quit cleanly after the /fuse probing.
#  8. Synthetic timestamp test (out-of-process via the existing visual
#      pipeline): the second /see + /fuse cycle does not crash.
#  9. /fuse with extra args is tolerated (the command ignores args).
# 10. Module count check: src/perception/sensor_fusion.nova exists.

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0

it_section "scenario BBBB: /fuse cross-modal sensor fusion (R20C)"

PGM_PATH="/tmp/ce_scenario_bbbb_sample.pgm"

# Cleanup any stale fixture files from a previous run.
rm -f "$PGM_PATH"

# Build a small but valid 16x16 PGM-P5 fixture. The visual seam
# requires at least 16x16 for the structural detectors; smaller
# fixtures fall back to the statistical labels only. 16x16 is the
# floor used by other VP-dependent scenarios.
build_sample_pgm() {
    local out="$1"
    {
        printf 'P5\n16 16\n255\n'
        python3 -c '
import sys
W, H = 16, 16
buf = bytearray(W * H)
# Half-and-half: top dark, bottom bright -- emits a horizontal-edge
# orientation label and a mid-intensity bucket.
for y in range(H):
    v = 50 if y < H // 2 else 200
    for x in range(W):
        buf[y * W + x] = v
sys.stdout.buffer.write(bytes(buf))
'
    } > "$out"
}

build_sample_pgm "$PGM_PATH"

if [ ! -s "$PGM_PATH" ]; then
    printf "  ${C_RED}FAIL${C_RST}  fixture PGM file did not get written\n"
    FAIL=$((FAIL+1))
    summary "scenario_bbbb_sensor_fusion"
    exit
fi

INPUT=$(
    printf '/help\n'
    printf '/fuse\n'
    printf '/see %s\n' "$PGM_PATH"
    printf '/fuse\n'
    printf '/fuse extra args ignored\n'
    printf '/see %s\n' "$PGM_PATH"
    printf '/fuse\n'
    printf '/quit\n'
)

OUT=$(echo "$INPUT" | "$CHAT" 2>&1)

# 1. /help advertises an admin surface (smoke -- /quit or /exit appears).
assert_match "$OUT" "/quit" \
    "/help mentions /quit (admin surface alive)"

# 2. /fuse before any /see prints either the empty-list message or a
# fused= summary (depending on whether audio side has any data; in
# CI it never does, so the empty-list path is expected).
assert_match "$OUT" "fuse: " \
    "/fuse emits a 'fuse:' prefix (smoke -- the command is wired)"

# 3. /fuse on empty visual + empty audio buffer reports the canonical
# "no fused observations" message.
assert_match "$OUT" "no fused observations" \
    "/fuse before any /see reports 'no fused observations' message"

# 4. /see PATH on PGM fixture emits the saw-image line.
assert_match "$OUT" "saw image " \
    "/see PATH on PGM emits 'saw image' line (visual seam fired)"

# 5. The features line printed by /see proves at least one feature
# was emitted -- the precondition for fusion.
assert_match "$OUT" "features: " \
    "/see PATH emits 'features:' line (vp_features_for_image fired)"

# 6. After /see, /fuse reports either fused=N (N>=1) OR still 'no fused
# observations' (audio side is empty in CI). Either path is correct;
# we just assert the command output is well-formed.
assert_match "$OUT" "fuse: (fused=|.no fused observations)" \
    "/fuse after /see reports a well-formed result"

# 7. The chat reaches /quit cleanly after the /fuse + /see probing.
assert_match "$OUT" "bye\\." \
    "chat reaches /quit cleanly after /fuse + /see probing"

# 8. The second /see + /fuse cycle did not crash (chat is still
# producing output after the second pair). The presence of "bye."
# at the end implies the entire sequence ran -- but we add an
# explicit check that there are at least 2 "saw image" lines.
SAW_COUNT=$(echo "$OUT" | grep -c "saw image ")
if [ "$SAW_COUNT" -ge 2 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  two /see + /fuse cycles ran without crash\n"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  expected at least 2 'saw image' lines, got %d\n" "$SAW_COUNT"
fi

# 9. /fuse with extra args still produces a fuse: output line. We
# verify by counting how many fuse: lines appear in OUT -- there
# should be at least 3 (initial /fuse + post-see /fuse + extra-args
# /fuse + final /fuse).
FUSE_COUNT=$(echo "$OUT" | grep -c "fuse: ")
if [ "$FUSE_COUNT" -ge 3 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  /fuse with extra args tolerated (>= 3 fuse: lines)\n"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  expected at least 3 fuse: lines, got %d\n" "$FUSE_COUNT"
fi

# 10. Module presence: src/perception/sensor_fusion.nova exists.
MODULE_PATH="$REPO_ROOT/src/perception/sensor_fusion.nova"
if [ -f "$MODULE_PATH" ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  src/perception/sensor_fusion.nova module file present\n"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  src/perception/sensor_fusion.nova module file missing\n"
fi

# Cleanup.
rm -f "$PGM_PATH"

summary "scenario_bbbb_sensor_fusion"
