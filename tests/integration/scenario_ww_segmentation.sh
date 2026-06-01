#!/usr/bin/env bash
# Scenario WW -- R11E: spatial k-means image segmentation.
#
# Exercises the new src/io/transducers/image_segmentation.nova module
# end-to-end:
#
#   * Synthesize a 64x64 4-quadrant PGM (TL=0, TR=85, BL=170, BR=255)
#     via a tiny NOVA driver.
#   * Drive `/segment <pgm> 4` through chat. Assert:
#       - k=4 clusters detected
#       - iterations <= 5 (one Lloyd step on the grid-aligned init)
#       - converged=yes
#       - writes /tmp/segmented.pgm
#       - report echoes "segment 64x64 k=4"
#   * Drive `/segment <missing>` through chat -> graceful FAILED.
#   * Drive `/segment` (no arg) -> usage prompt.
#   * `/help` advertises the new command with the R11E label.
#
# Pre-conditions: NOVA toolchain at $NOVA_ROOT/nova; built chat binary.
# Side-effects: writes /tmp/ce_scenario_ww_quad.pgm,
#               /tmp/ce_scenario_ww_driver.out, plus the on-the-fly NOVA
#               fixture driver under tests/integration/_scenario_ww_drivers/.
#               The chat call also writes /tmp/segmented.pgm.

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

it_section "scenario WW: R11E spatial k-means image segmentation"

NOVA_BIN="${NOVA_ROOT:-/home/user/NOVA}/nova"
if [ ! -x "$NOVA_BIN" ]; then
    printf "  ${C_RED}ERROR${C_RST}: NOVA launcher not found at %s (set NOVA_ROOT)\n" "$NOVA_BIN" >&2
    FAIL=$((FAIL+1))
    summary "scenario_ww_segmentation"
    exit $?
fi

QUAD_PGM="/tmp/ce_scenario_ww_quad.pgm"
DRV_DIR="$REPO_ROOT/tests/integration/_scenario_ww_drivers"
DRV_SRC="$DRV_DIR/seg_fixture_driver.nova"
DRV_OUT="/tmp/ce_scenario_ww_driver.out"
SEG_OUT="/tmp/segmented.pgm"

mkdir -p "$DRV_DIR"
trap 'rm -f "$QUAD_PGM" "$DRV_OUT" "$SEG_OUT"; rm -rf "$DRV_DIR"' EXIT

# Emit the NOVA fixture driver. The leading underscore on
# _scenario_ww_drivers/ means the Makefile's integration glob skips it.
cat > "$DRV_SRC" <<'NOVA'
// Auto-generated 4-quadrant PGM-fixture driver for scenario_ww_segmentation.sh.
//
// Builds a 64x64 grayscale image with each 32x32 quadrant at a distinct
// intensity:
//   TL = 0     (black)
//   TR = 85
//   BL = 170
//   BR = 255   (white)
// Writes PGM-P5 bytes to /tmp/ce_scenario_ww_quad.pgm so the chat
// `/segment` admin can decode it.

import "std/syscall"

let W = 64
let H = 64
let OUT_PATH = "/tmp/ce_scenario_ww_quad.pgm"
let FILE_MODE = 420  // 0644

fn _write_dec(buf, off, n) {
    if n <= 0 {
        store8(buf + off, 48)
        return off + 1
    }
    let d = 0
    let v = n
    while v > 0 {
        d = d + 1
        v = v / 10
    }
    let i = d - 1
    v = n
    while i >= 0 {
        store8(buf + off + i, 48 + v - (v / 10) * 10)
        v = v / 10
        i = i - 1
    }
    return off + d
}

fn main() {
    let area = W * H
    // Header: "P5\n64 64\n255\n" = 13 bytes.
    let total = 13 + area
    let buf = alloc(total + 1)
    let off = 0
    store8(buf + off, 80) off = off + 1   // P
    store8(buf + off, 53) off = off + 1   // 5
    store8(buf + off, 10) off = off + 1
    off = _write_dec(buf, off, W)
    store8(buf + off, 32) off = off + 1   // space
    off = _write_dec(buf, off, H)
    store8(buf + off, 10) off = off + 1
    store8(buf + off, 50) off = off + 1   // 2
    store8(buf + off, 53) off = off + 1   // 5
    store8(buf + off, 53) off = off + 1   // 5
    store8(buf + off, 10) off = off + 1
    // Pixel payload.
    let half_x = W / 2
    let half_y = H / 2
    let y = 0
    while y < H {
        let row = y * W
        let x = 0
        while x < W {
            let v = 0
            if x >= half_x {
                if y < half_y { v = 85 }
                else { v = 255 }
            } else {
                if y >= half_y { v = 170 }
            }
            store8(buf + off + row + x, v)
            x = x + 1
        }
        y = y + 1
    }
    let flags = O_WRONLY + O_CREAT + O_TRUNC
    let fd = sys_open(OUT_PATH, flags, FILE_MODE)
    if fd < 0 {
        println("FIXTURE FAIL: sys_open returned fd=" + int_to_str(fd))
        exit(1)
    }
    let written = sys_write(fd, buf, total)
    if written != total {
        sys_close(fd)
        println("FIXTURE FAIL: short write " + int_to_str(written)
            + "/" + int_to_str(total))
        exit(1)
    }
    sys_fsync(fd)
    sys_close(fd)
    println("FIXTURE OK: wrote " + int_to_str(total) + " bytes to " + OUT_PATH)
}

main()
NOVA

# Build the fixture.
FIXTURE_OUT=$("$NOVA_BIN" run "$DRV_SRC" 2>&1)
FIXTURE_RC=$?
printf '%s\n' "$FIXTURE_OUT" > "$DRV_OUT"
assert_eq "$FIXTURE_RC" "0" "fixture driver exits 0"
assert_match "$FIXTURE_OUT" "FIXTURE OK" "fixture writes the quadrant PGM"
assert_file_exists "$QUAD_PGM" "quadrant PGM exists on disk"

require_chat

# ---- chat /help advertises /segment with R11E label ----------------------

CHAT_HELP=$(run_chat "/help")
assert_match "$CHAT_HELP" '/segment' \
    "chat /help advertises the new /segment command"
assert_match "$CHAT_HELP" 'R11E' \
    "chat /help labels /segment as R11E"

# ---- chat /segment on the quadrant fixture -------------------------------

CHAT_SEG=$(run_chat "/segment $QUAD_PGM 4")
assert_match "$CHAT_SEG" 'segment 64x64' \
    "chat /segment echoes dims 64x64"
assert_match "$CHAT_SEG" 'k=4' \
    "chat /segment detects k=4 clusters"
assert_match "$CHAT_SEG" 'iterations=' \
    "chat /segment reports iteration count"
assert_match "$CHAT_SEG" 'converged=yes' \
    "chat /segment converges on the quadrant fixture"
assert_match "$CHAT_SEG" 'wrote=yes' \
    "chat /segment writes the segmented PGM"
assert_match "$CHAT_SEG" '/tmp/segmented.pgm' \
    "chat /segment echoes the output path"
assert_match "$CHAT_SEG" 'dominant=image_segmentation_dominant_' \
    "chat /segment reports a dominant cluster label"

# Verify the iter count is <=5 (convergence in a few steps).
SEG_ITERS=$(echo "$CHAT_SEG" | grep -oE 'iterations=[0-9]+' | head -1 | cut -d= -f2)
if [ -n "$SEG_ITERS" ] && [ "$SEG_ITERS" -le 5 ] && [ "$SEG_ITERS" -ge 1 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  /segment iterations=%s in [1..5] (fast convergence)\n" "$SEG_ITERS"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  /segment iterations='%s' not in [1..5]\n" "$SEG_ITERS"
fi

assert_file_exists "$SEG_OUT" "/tmp/segmented.pgm written by /segment"

# ---- chat /segment with no arg -- usage prompt ---------------------------

CHAT_SEG_NOARG=$(run_chat "/segment")
assert_match "$CHAT_SEG_NOARG" '/segment needs PATH' \
    "chat /segment with no arg prints usage"

# ---- chat /segment on missing file -- graceful error --------------------

CHAT_SEG_MISS=$(run_chat "/segment /tmp/ce_scenario_ww_does_not_exist.pgm")
assert_match "$CHAT_SEG_MISS" 'segment FAILED' \
    "chat /segment on missing PGM -> graceful FAILED"

summary "scenario_ww_segmentation"
