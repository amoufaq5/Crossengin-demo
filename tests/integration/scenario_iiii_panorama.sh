#!/usr/bin/env bash
# Scenario IIII -- R22D: image-pair panorama stitching.
#
# Verifies the R22D pipeline end-to-end through the chat /pano admin:
#
#   * Synthesize a 64x32 wide checkerboard PGM via a tiny NOVA driver.
#   * Split it into left half (cols 0..36) + right half (cols 28..63),
#     creating a 36x32 left + 36x32 right pair with 10-pixel overlap.
#   * Drive `/pano LEFT RIGHT` through chat. Assert:
#       - pano command recognised (no "unknown command")
#       - matches=N reported
#       - output dimensions echoed (62x32 = 2*36 - 10 overlap)
#       - wrote=yes
#       - /tmp/stitched.pgm exists on disk
#       - file size is reasonable (> 1 KB: header + 62*32 = 1995 bytes)
#   * Drive `/pano /tmp/missing.pgm /tmp/also_missing.pgm` -> graceful FAILED.
#   * Drive `/pano` (no arg) -> usage prompt.
#   * `/help` advertises the new command with the R22D label.
#
# Pre-conditions: NOVA toolchain at $NOVA_ROOT/nova; built chat binary.
# Side-effects: writes /tmp/ce_scenario_iiii_*.pgm, /tmp/stitched.pgm,
#               plus the on-the-fly NOVA fixture driver under
#               tests/integration/_scenario_iiii_drivers/.

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

it_section "scenario IIII: R22D image-pair panorama stitching"

NOVA_BIN="${NOVA_ROOT:-/home/user/NOVA}/nova"
if [ ! -x "$NOVA_BIN" ]; then
    printf "  ${C_RED}ERROR${C_RST}: NOVA launcher not found at %s (set NOVA_ROOT)\n" "$NOVA_BIN" >&2
    FAIL=$((FAIL+1))
    summary "scenario_iiii_panorama"
    exit $?
fi

LEFT_PGM="/tmp/ce_scenario_iiii_left.pgm"
RIGHT_PGM="/tmp/ce_scenario_iiii_right.pgm"
STITCH_OUT="/tmp/stitched.pgm"
DRV_DIR="$REPO_ROOT/tests/integration/_scenario_iiii_drivers"
DRV_SRC="$DRV_DIR/pano_fixture_driver.nova"
DRV_OUT="/tmp/ce_scenario_iiii_driver.out"

mkdir -p "$DRV_DIR"
trap 'rm -f "$LEFT_PGM" "$RIGHT_PGM" "$STITCH_OUT" "$DRV_OUT"; rm -rf "$DRV_DIR"' EXIT

# Emit the NOVA fixture driver. The leading underscore on
# _scenario_iiii_drivers/ means the Makefile's integration glob skips
# the directory, matching the scenario_ww pattern.
cat > "$DRV_SRC" <<'NOVA'
// Auto-generated panorama-pair fixture driver for scenario_iiii_panorama.sh.
//
// Builds a 36x32 checkerboard left half (cells 4x4 px) and a 36x32
// checkerboard right half offset by (36 - 10 = 26) px, so the two
// halves overlap on 10 columns of identical content. Writes PGM-P5
// bytes to /tmp/ce_scenario_iiii_left.pgm and .._right.pgm so the
// chat `/pano` admin can decode them.

import "std/syscall"

let W = 36
let H = 32
let CELL = 4
let LEFT_OUT  = "/tmp/ce_scenario_iiii_left.pgm"
let RIGHT_OUT = "/tmp/ce_scenario_iiii_right.pgm"
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

// Build a checkerboard pixel value for global (gx, gy). cells are
// 4x4 px; alternating cells are intensity 30 (dark) and 220 (bright).
fn checker_pixel(gx, gy) {
    let cx = gx / CELL
    let cy = gy / CELL
    let s = cx + cy - (cx + cy) / 2 * 2
    if s == 0 { return 220 }
    return 30
}

fn write_pgm(path, x_offset) {
    let area = W * H
    let total = 13 + area  // "P5\n36 32\n255\n" = 13 bytes
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
    // Pixel payload. Local (x, y) -> global (x + x_offset, y).
    let y = 0
    while y < H {
        let row = y * W
        let x = 0
        while x < W {
            let gx = x + x_offset
            let v = checker_pixel(gx, y)
            store8(buf + off + row + x, v)
            x = x + 1
        }
        y = y + 1
    }
    let flags = O_WRONLY + O_CREAT + O_TRUNC
    let fd = sys_open(path, flags, FILE_MODE)
    if fd < 0 {
        println("FIXTURE FAIL: sys_open returned fd=" + int_to_str(fd) + " for " + path)
        return 0
    }
    let written = sys_write(fd, buf, total)
    if written != total {
        sys_close(fd)
        println("FIXTURE FAIL: short write " + int_to_str(written)
            + "/" + int_to_str(total) + " for " + path)
        return 0
    }
    sys_fsync(fd)
    sys_close(fd)
    return total
}

fn main() {
    // Left half: global cols [0, 36).
    let n_left = write_pgm(LEFT_OUT, 0)
    if n_left <= 0 {
        exit(1)
    }
    // Right half: global cols [26, 62) -- 10-column overlap with the
    // left half at global cols [26, 36).
    let n_right = write_pgm(RIGHT_OUT, 26)
    if n_right <= 0 {
        exit(1)
    }
    println("FIXTURE OK: wrote " + int_to_str(n_left) + " bytes to " + LEFT_OUT)
    println("FIXTURE OK: wrote " + int_to_str(n_right) + " bytes to " + RIGHT_OUT)
}

main()
NOVA

# Build the fixture pair.
FIXTURE_OUT=$("$NOVA_BIN" run "$DRV_SRC" 2>&1)
FIXTURE_RC=$?
printf '%s\n' "$FIXTURE_OUT" > "$DRV_OUT"
assert_eq "$FIXTURE_RC" "0" "fixture driver exits 0"
assert_match "$FIXTURE_OUT" "FIXTURE OK: wrote .* $LEFT_PGM" \
    "fixture writes the left-half PGM"
assert_match "$FIXTURE_OUT" "FIXTURE OK: wrote .* $RIGHT_PGM" \
    "fixture writes the right-half PGM"
assert_file_exists "$LEFT_PGM" "left half PGM exists on disk"
assert_file_exists "$RIGHT_PGM" "right half PGM exists on disk"

require_chat

# ---- chat /help advertises /pano with R22D label ------------------------

CHAT_HELP=$(run_chat "/help")
assert_match "$CHAT_HELP" '/pano LEFT RIGHT' \
    "chat /help advertises the new /pano command"
assert_match "$CHAT_HELP" 'R22D' \
    "chat /help labels /pano as R22D"

# ---- chat /pano on the checkerboard pair --------------------------------

# Make sure no stale stitched.pgm influences the file-exists checks.
rm -f "$STITCH_OUT"

CHAT_PANO=$(run_chat "/pano $LEFT_PGM $RIGHT_PGM")
assert_match "$CHAT_PANO" 'pano 36x32' \
    "chat /pano echoes input dims 36x32"
assert_match "$CHAT_PANO" 'matches=' \
    "chat /pano reports the matches count"
assert_match "$CHAT_PANO" 'wrote=yes' \
    "chat /pano writes the stitched PGM"
assert_match "$CHAT_PANO" '/tmp/stitched.pgm' \
    "chat /pano echoes the output path"
assert_file_exists "$STITCH_OUT" "/tmp/stitched.pgm written by /pano"

# Stitched output size: header (13 bytes for "P5\n62 32\n255\n") + 62*32
# = 13 + 1984 = 1997 bytes. The brief asks for >= 1 KB.
if [ -f "$STITCH_OUT" ]; then
    SIZE=$(wc -c < "$STITCH_OUT" | tr -d ' ')
    if [ "$SIZE" -gt 1024 ]; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}PASS${C_RST}  stitched.pgm size %s bytes > 1024\n" "$SIZE"
    else
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  stitched.pgm size %s bytes <= 1024\n" "$SIZE"
    fi
    # Verify it starts with the P5 magic (a valid PGM file).
    HEADER=$(head -c 2 "$STITCH_OUT")
    if [ "$HEADER" = "P5" ]; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}PASS${C_RST}  stitched.pgm begins with P5 magic\n"
    else
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  stitched.pgm begins with '%s' (expected P5)\n" "$HEADER"
    fi
fi

# Verify the stitched output width is 62 (2*36 - 10 overlap).
assert_match "$CHAT_PANO" '62x32' \
    "stitched output is 62x32 (2*W - overlap = 72 - 10)"

# ---- chat /pano with no arg -- usage prompt -----------------------------

CHAT_PANO_NOARG=$(run_chat "/pano")
assert_match "$CHAT_PANO_NOARG" '/pano needs two PATHs' \
    "chat /pano with no arg prints usage"

# ---- chat /pano on missing file -- graceful error ----------------------

CHAT_PANO_MISS=$(run_chat "/pano /tmp/ce_scenario_iiii_does_not_exist.pgm /tmp/ce_scenario_iiii_also_missing.pgm")
assert_match "$CHAT_PANO_MISS" 'pano FAILED' \
    "chat /pano on missing PGM -> graceful FAILED"

summary "scenario_iiii_panorama"
