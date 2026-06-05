#!/usr/bin/env bash
# Scenario YY -- R12B: SLIC superpixel segmentation.
#
# Exercises the new src/io/transducers/image_superpixels.nova module
# end-to-end:
#
#   * Synthesize a 64x64 4-quadrant PGM (TL=0, TR=85, BL=170, BR=255)
#     via a tiny NOVA driver.
#   * Drive `/slic <pgm> 16` through chat. Assert:
#       - dims echoed
#       - k=16 clusters detected
#       - step=16 reported
#       - boundary_px > 0 (mesh visible)
#       - writes /tmp/slic_overlay.pgm
#   * Drive `/slic <missing>` through chat -> graceful FAILED.
#   * Drive `/slic` (no arg) -> usage prompt.
#   * `/help` advertises the new command with the R12B label.
#
# Pre-conditions: NOVA toolchain at $NOVA_ROOT/nova; built chat binary.
# Side-effects: writes /tmp/ce_scenario_yy_quad.pgm,
#               /tmp/ce_scenario_yy_driver.out, plus the on-the-fly NOVA
#               fixture driver under tests/integration/_scenario_yy_drivers/.
#               The chat call also writes /tmp/slic_overlay.pgm.

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

it_section "scenario YY: R12B SLIC superpixel segmentation"

NOVA_BIN="${NOVA_ROOT:-/home/user/NOVA}/nova"
if [ ! -x "$NOVA_BIN" ]; then
    printf "  ${C_RED}ERROR${C_RST}: NOVA launcher not found at %s (set NOVA_ROOT)\n" "$NOVA_BIN" >&2
    FAIL=$((FAIL+1))
    summary "scenario_yy_slic"
    exit $?
fi

QUAD_PGM="/tmp/ce_scenario_yy_quad.pgm"
DRV_DIR="$REPO_ROOT/tests/integration/_scenario_yy_drivers"
DRV_SRC="$DRV_DIR/slic_fixture_driver.nova"
DRV_OUT="/tmp/ce_scenario_yy_driver.out"
SLIC_OUT="/tmp/slic_overlay.pgm"

mkdir -p "$DRV_DIR"
trap 'rm -f "$QUAD_PGM" "$DRV_OUT" "$SLIC_OUT"; rm -rf "$DRV_DIR"' EXIT

# Emit the NOVA fixture driver. The leading underscore on
# _scenario_yy_drivers/ means the Makefile's integration glob skips it.
cat > "$DRV_SRC" <<'NOVA'
// Auto-generated 4-quadrant PGM-fixture driver for scenario_yy_slic.sh.
//
// Builds a 64x64 grayscale image with each 32x32 quadrant at a distinct
// intensity:
//   TL = 0     (black)
//   TR = 85
//   BL = 170
//   BR = 255   (white)
// Writes PGM-P5 bytes to /tmp/ce_scenario_yy_quad.pgm so the chat
// `/slic` admin can decode it.

import "std/syscall"

let W = 64
let H = 64
let OUT_PATH = "/tmp/ce_scenario_yy_quad.pgm"
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

# ---- chat /help advertises /slic with R12B label -------------------------

CHAT_HELP=$(run_chat "/help")
assert_match "$CHAT_HELP" '/slic' \
    "chat /help advertises the new /slic command"
assert_match "$CHAT_HELP" 'R12B' \
    "chat /help labels /slic as R12B"

# ---- chat /slic on the quadrant fixture ----------------------------------

CHAT_SLIC=$(run_chat "/slic $QUAD_PGM 16")
assert_match "$CHAT_SLIC" 'slic 64x64' \
    "chat /slic echoes dims 64x64"
assert_match "$CHAT_SLIC" 'k=16' \
    "chat /slic detects k=16 clusters"
assert_match "$CHAT_SLIC" 'step=16' \
    "chat /slic reports step=16 on 64x64 K=16"
assert_match "$CHAT_SLIC" 'iterations=' \
    "chat /slic reports iteration count"
assert_match "$CHAT_SLIC" 'boundary_px=' \
    "chat /slic reports boundary pixel count"
assert_match "$CHAT_SLIC" 'wrote=yes' \
    "chat /slic writes the overlay PGM"
assert_match "$CHAT_SLIC" '/tmp/slic_overlay.pgm' \
    "chat /slic echoes the output path"

# Verify boundary count > 0 (the mesh is visible).
SLIC_BOUNDARY=$(echo "$CHAT_SLIC" | grep -oE 'boundary_px=[0-9]+' | head -1 | cut -d= -f2)
if [ -n "$SLIC_BOUNDARY" ] && [ "$SLIC_BOUNDARY" -gt 0 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  /slic boundary_px=%s > 0 (mesh visible)\n" "$SLIC_BOUNDARY"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  /slic boundary_px='%s' not > 0\n" "$SLIC_BOUNDARY"
fi

assert_file_exists "$SLIC_OUT" "/tmp/slic_overlay.pgm written by /slic"

# ---- chat /slic with no arg -- usage prompt ------------------------------

CHAT_SLIC_NOARG=$(run_chat "/slic")
assert_match "$CHAT_SLIC_NOARG" '/slic needs PATH' \
    "chat /slic with no arg prints usage"

# ---- chat /slic on missing file -- graceful error ------------------------

CHAT_SLIC_MISS=$(run_chat "/slic /tmp/ce_scenario_yy_does_not_exist.pgm")
assert_match "$CHAT_SLIC_MISS" 'slic FAILED' \
    "chat /slic on missing PGM -> graceful FAILED"

summary "scenario_yy_slic"
