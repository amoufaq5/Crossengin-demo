#!/usr/bin/env bash
# Scenario LLLL -- /lipsync audio-vision lip sync detection (R23B).
#
# R23B ships a structural lip-sync detector
# (`src/perception/lipsync.nova`) that correlates per-frame mouth-open
# intensity gradient against per-frame VAD voicing. The chat dispatch
# /lipsync <video_dir> <audio.wav> reads PGM frames named
# frame_001.pgm..frame_NNN.pgm + a canonical WAV; it reports a
# sync_score_milli (Pearson-style milli correlation, clamped to >= 0)
# and a 1/0 is_synced verdict against SYNC_THRESHOLD_MILLI = 400.
#
# This scenario builds two synthetic 5-frame PGM fixtures + two WAVs:
#   MATCHED   -- mouth opens (frames 0, 2, 4) when audio is voiced
#                (frames 0, 2, 4); silence on the closed frames.
#                Expected: is_synced=true.
#   MISMATCHED -- same MATCHED video, but audio is voiced where the
#                mouth is closed (anti-correlated). Expected:
#                is_synced=false.
#
# Verify that:
#
#  1. /help advertises the /lipsync command (smoke).
#  2. /lipsync with no args returns the usage hint.
#  3. /lipsync with only one arg returns the usage hint.
#  4. /lipsync with a missing video_dir reports a graceful error.
#  5. /lipsync with a missing WAV reports a graceful error.
#  6. /lipsync on the MATCHED fixture reports is_synced=true.
#  7. /lipsync on the MATCHED fixture's sync_score >= threshold (400).
#  8. /lipsync on the MISMATCHED fixture reports is_synced=false.
#  9. /lipsync output prints the threshold so operators can interpret
#      the score.
# 10. Module presence: src/perception/lipsync.nova exists.

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

it_section "scenario LLLL: /lipsync audio-vision lip sync detection (R23B)"

NOVA_BIN="${NOVA_ROOT:-/home/user/NOVA}/nova"
if [ ! -x "$NOVA_BIN" ]; then
    printf "  ${C_RED}ERROR${C_RST}: NOVA launcher not found at %s (set NOVA_ROOT)\n" "$NOVA_BIN" >&2
    FAIL=$((FAIL+1))
    summary "scenario_llll_lipsync"
    exit $?
fi

require_chat

MATCHED_DIR="/tmp/ce_scenario_llll_matched_frames"
MISMATCHED_DIR="/tmp/ce_scenario_llll_mismatched_frames"
MATCHED_WAV="/tmp/ce_scenario_llll_matched.wav"
MISMATCHED_WAV="/tmp/ce_scenario_llll_mismatched.wav"
MISSING_DIR="/tmp/ce_scenario_llll_definitely_missing_dir"
MISSING_WAV="/tmp/ce_scenario_llll_definitely_missing.wav"

# Clean up any stale fixtures from a previous run.
rm -rf "$MATCHED_DIR" "$MISMATCHED_DIR"
rm -f "$MATCHED_WAV" "$MISMATCHED_WAV"
trap 'rm -rf "$MATCHED_DIR" "$MISMATCHED_DIR"; rm -f "$MATCHED_WAV" "$MISMATCHED_WAV"' EXIT

mkdir -p "$MATCHED_DIR" "$MISMATCHED_DIR"

# Build the 5 PGM frames into each directory. We need:
#   * frame_001..005.pgm in MATCHED_DIR
#   * frame_001..005.pgm in MISMATCHED_DIR (identical to MATCHED's frames)
# Frames 1,3,5 (1-indexed) are "open mouth": uniform bright pixels with a
# dark interior box in the lower-third's center. Frames 2,4 are "closed
# mouth": uniform skin tone. 48x48 each (R16D's min face window is 24x24
# so 48x48 leaves ample room for the cascade).
build_pgm() {
    local path="$1"
    local kind="$2"   # "open" or "closed"
    local w=48
    local h=48
    {
        printf 'P5\n%d %d\n255\n' "$w" "$h"
        python3 -c "
import sys
W, H = $w, $h
buf = bytearray(W * H)
# Skin tone everywhere.
for i in range(W * H):
    buf[i] = 200
if '$kind' == 'open':
    # Dark interior box in lower-third's center.
    mouth_y1 = (H * 2) // 3
    mouth_h = H - mouth_y1
    inner_h = max(1, (mouth_h * 3) // 10)
    inner_w = max(1, W // 2)
    inner_x1 = (W - inner_w) // 2
    inner_y1 = mouth_y1 + (mouth_h - inner_h) // 2
    for y in range(inner_y1, inner_y1 + inner_h):
        for x in range(inner_x1, inner_x1 + inner_w):
            buf[y * W + x] = 30
sys.stdout.buffer.write(bytes(buf))
"
    } > "$path"
}

# Build matched / mismatched share the SAME video (open/closed/open/closed/open).
for i in 1 2 3 4 5; do
    if [ "$i" = "1" ] || [ "$i" = "3" ] || [ "$i" = "5" ]; then
        kind="open"
    else
        kind="closed"
    fi
    name=$(printf "frame_%03d.pgm" "$i")
    build_pgm "$MATCHED_DIR/$name" "$kind"
    build_pgm "$MISMATCHED_DIR/$name" "$kind"
done

# Sanity check: at least one fixture frame exists.
if [ ! -s "$MATCHED_DIR/frame_001.pgm" ]; then
    printf "  ${C_RED}FAIL${C_RST}  matched fixture frame_001.pgm did not get written\n"
    FAIL=$((FAIL+1))
    summary "scenario_llll_lipsync"
    exit $?
fi

# Build the WAV fixtures via a small NOVA driver. Each frame's audio
# chunk is 1600 samples (100 ms @ 16 kHz; comfortably above the VAD's
# default 30 ms frame). Voiced chunk = 250 Hz sawtooth (~50 cycles
# over the chunk, energy ~= chunk_size * peak_amplitude, ZCR moderate).
# Silent chunk = pure zero.
DRV_DIR="$REPO_ROOT/tests/integration/_scenario_llll_drivers"
DRV_SRC="$DRV_DIR/llll_fixture_writer.nova"
DRV_OUT="/tmp/ce_scenario_llll_driver.out"
mkdir -p "$DRV_DIR"
trap 'rm -rf "$MATCHED_DIR" "$MISMATCHED_DIR"; rm -f "$MATCHED_WAV" "$MISMATCHED_WAV" "$DRV_OUT" "$DRV_SRC"; rmdir "$DRV_DIR" 2>/dev/null || true' EXIT

cat > "$DRV_SRC" <<'NOVA'
// Auto-generated fixture writer for scenario_llll_lipsync.sh.
//
// Writes two WAV fixtures: MATCHED (voiced where mouth is open) and
// MISMATCHED (voiced where mouth is closed). Each WAV is 5 chunks of
// 1600 samples (one chunk per video frame at 16 kHz).

import "../../../src/io/effectors/audio_synth.nova"

let CHUNK = 1600

fn _voiced_chunk() {
    let pcm = list_new()
    let i = 0
    let period = 64
    let half = period / 2
    let amp = 12000
    while i < CHUNK {
        let phase = i - (i / period) * period
        let sign = 1
        if phase >= half { sign = 0 - 1 }
        let ramp = phase
        if phase >= half { ramp = phase - half }
        let v = (amp * ramp) / half
        if sign < 0 { v = 0 - v }
        push(pcm, v)
        i = i + 1
    }
    return pcm
}

fn _silent_chunk() {
    let pcm = list_new()
    let i = 0
    while i < CHUNK {
        push(pcm, 0)
        i = i + 1
    }
    return pcm
}

fn _concat(a, b) {
    let out = list_new()
    let i = 0
    while i < len(a) { push(out, a[i]); i = i + 1 }
    i = 0
    while i < len(b) { push(out, b[i]); i = i + 1 }
    return out
}

fn _build_pattern(p0, p1, p2, p3, p4) {
    // Each pX is either _voiced_chunk() or _silent_chunk().
    let a = _concat(p0, p1)
    let b = _concat(a, p2)
    let c = _concat(b, p3)
    return _concat(c, p4)
}

fn main() {
    // MATCHED: voiced on frames 0, 2, 4 (the open ones).
    let m = _build_pattern(_voiced_chunk(), _silent_chunk(),
                            _voiced_chunk(), _silent_chunk(),
                            _voiced_chunk())
    let ok1 = audio_write_wav(m, "/tmp/ce_scenario_llll_matched.wav")
    println("wrote matched: " + int_to_str(ok1))

    // MISMATCHED: voiced on frames 1, 3 (the closed ones); silence on
    // frames 0, 2, 4 (the open ones). Anti-correlated with the video.
    let mm = _build_pattern(_silent_chunk(), _voiced_chunk(),
                             _silent_chunk(), _voiced_chunk(),
                             _silent_chunk())
    let ok2 = audio_write_wav(mm, "/tmp/ce_scenario_llll_mismatched.wav")
    println("wrote mismatched: " + int_to_str(ok2))

    println("driver complete")
}

main()
NOVA

"$NOVA_BIN" run "$DRV_SRC" > "$DRV_OUT" 2>&1
DRIVER_RC=$?

if [ "$DRIVER_RC" -ne 0 ]; then
    printf "  ${C_RED}FAIL${C_RST}  fixture driver exited non-zero (rc=%d). Output:\n" "$DRIVER_RC"
    sed 's/^/        /' "$DRV_OUT"
    FAIL=$((FAIL+1))
    summary "scenario_llll_lipsync"
    exit $?
fi

DRV_TXT=$(cat "$DRV_OUT")
assert_match "$DRV_TXT" "wrote matched: 1"    "matched WAV written by fixture driver"
assert_match "$DRV_TXT" "wrote mismatched: 1" "mismatched WAV written by fixture driver"

# ===========================================================================
# Assertion 1: /help advertises /lipsync.
# ===========================================================================
HELP_OUT=$(run_chat "/help")
assert_match "$HELP_OUT" "/lipsync " \
    "/help advertises the /lipsync command"

# ===========================================================================
# Assertion 2: /lipsync with no args -> usage hint.
# ===========================================================================
NOARG_OUT=$(run_chat "/lipsync")
assert_match "$NOARG_OUT" "/lipsync needs" \
    "/lipsync with no args shows usage hint"

# ===========================================================================
# Assertion 3: /lipsync with only one arg -> usage hint.
# ===========================================================================
ONEARG_OUT=$(run_chat "/lipsync $MATCHED_DIR")
assert_match "$ONEARG_OUT" "/lipsync needs" \
    "/lipsync with only one arg shows usage hint"

# ===========================================================================
# Assertion 4: /lipsync with a missing video_dir -> graceful error.
# ===========================================================================
MISSING_DIR_OUT=$(run_chat "/lipsync $MISSING_DIR $MATCHED_WAV")
assert_match "$MISSING_DIR_OUT" "lipsync FAILED: need >= 2 PGM frames" \
    "/lipsync with missing video_dir reports graceful error"

# ===========================================================================
# Assertion 5: /lipsync with a missing WAV -> graceful error.
# ===========================================================================
MISSING_WAV_OUT=$(run_chat "/lipsync $MATCHED_DIR $MISSING_WAV")
assert_match "$MISSING_WAV_OUT" "lipsync FAILED: could not parse WAV" \
    "/lipsync with missing WAV reports graceful error"

# ===========================================================================
# Assertion 6+7: /lipsync on MATCHED fixture -> is_synced=true,
# sync_score >= 400.
# ===========================================================================
MATCHED_OUT=$(run_chat "/lipsync $MATCHED_DIR $MATCHED_WAV")
assert_match "$MATCHED_OUT" "is_synced=true" \
    "/lipsync on MATCHED fixture reports is_synced=true"

# Extract the sync_score_milli value and verify >= 400 numerically.
SCORE_LINE=$(echo "$MATCHED_OUT" | grep -oE "sync_score_milli=[0-9-]+" | head -1)
SCORE=$(echo "$SCORE_LINE" | sed 's/sync_score_milli=//')
if [ -n "$SCORE" ] && [ "$SCORE" -ge 400 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  /lipsync on MATCHED reports sync_score_milli=%s (>= 400 threshold)\n" "$SCORE"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  /lipsync on MATCHED: expected sync_score_milli >= 400; got '%s'\n        full output:\n" "$SCORE"
    echo "$MATCHED_OUT" | sed 's/^/          /'
fi

# ===========================================================================
# Assertion 8: /lipsync on MISMATCHED fixture -> is_synced=false.
# ===========================================================================
MISMATCHED_OUT=$(run_chat "/lipsync $MISMATCHED_DIR $MISMATCHED_WAV")
assert_match "$MISMATCHED_OUT" "is_synced=false" \
    "/lipsync on MISMATCHED fixture reports is_synced=false"

# ===========================================================================
# Assertion 9: /lipsync output prints the threshold so operators can
# interpret the score.
# ===========================================================================
assert_match "$MATCHED_OUT" "threshold=400" \
    "/lipsync output prints the sync threshold (400) for interpretation"

# ===========================================================================
# Assertion 10: Module presence.
# ===========================================================================
MODULE_PATH="$REPO_ROOT/src/perception/lipsync.nova"
if [ -f "$MODULE_PATH" ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  src/perception/lipsync.nova module file present\n"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  src/perception/lipsync.nova module file missing\n"
fi

summary "scenario_llll_lipsync"
