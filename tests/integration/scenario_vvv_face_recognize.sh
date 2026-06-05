#!/usr/bin/env bash
# Scenario VVV -- /face_enroll + /face_recognize LBP-gallery nearest-
# neighbor face identity matching admin commands end-to-end (R18D,
# Ahonen et al. 2006 LBP-recognition pipeline; built on R17D's
# image_lbp.nova descriptor + chi-squared distance).
#
# Build four PGM fixtures in /tmp:
#   * face_a.pgm: 32x32 vertical edge (left half dark / right bright)
#     -- "identity A".
#   * face_b.pgm: 32x32 four bright 4x4 spots on a dark field
#     -- "identity B". A structurally different LBP fingerprint.
#   * face_c.pgm: 32x32 horizontal edge (top half dark / bottom
#     bright) -- "identity C". LBP is NOT rotation-invariant so this
#     is distinct from face_a.
#   * face_d.pgm: 32x32 pseudo-random high-entropy texture (a fourth
#     identity NOT enrolled in the gallery, picked so its LBP
#     descriptor is far from each of A/B/C). Used for the
#     unknown-rejection probe.
#
# Verify that:
#
#   1. /help advertises /face_enroll and /face_recognize.
#   2. /face_enroll with no arg prints the usage line.
#   3. /face_recognize with no arg prints the usage line.
#   4. /face_recognize before any enrollment prints "gallery empty".
#   5. /face_enroll on a missing PGM prints the parser error.
#   6. Enrolling alice (face_a), bob (face_b), carol (face_c) all
#      succeed and the gallery size grows monotonically.
#   7. /face_recognize on face_a returns matched=alice with distance 0.
#   8. /face_recognize on face_b returns matched=bob with distance 0.
#   9. /face_recognize on face_c returns matched=carol with distance 0.
#  10. /face_recognize on face_d (NOT in gallery) returns "unknown"
#      (the diagonal LBP signature is far enough from each of
#      alice/bob/carol that no entry passes the chi-squared cutoff).
#  11. The chat survives all probing and reaches /quit cleanly.

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0

it_section "scenario VVV: /face_enroll + /face_recognize LBP-gallery face recognition (R18D)"

FACE_A="/tmp/ce_scenario_vvv_face_a.pgm"
FACE_B="/tmp/ce_scenario_vvv_face_b.pgm"
FACE_C="/tmp/ce_scenario_vvv_face_c.pgm"
FACE_D="/tmp/ce_scenario_vvv_face_d.pgm"
MISSING="/tmp/ce_scenario_vvv_nonexistent.pgm"

# Cleanup any stale fixture files from a previous run.
rm -f "$FACE_A" "$FACE_B" "$FACE_C" "$FACE_D" "$MISSING"

build_face_a_pgm() {
    # 32x32 vertical edge: left half = 50, right half = 200.
    local out="$1"
    {
        printf 'P5\n32 32\n255\n'
        python3 -c '
import sys
W, H = 32, 32
buf = bytearray(W * H)
half = W // 2
for y in range(H):
    for x in range(W):
        buf[y * W + x] = 50 if x < half else 200
sys.stdout.buffer.write(bytes(buf))
'
    } > "$out"
}

build_face_b_pgm() {
    # 32x32 four bright 4x4 spots on a dark field.
    local out="$1"
    {
        printf 'P5\n32 32\n255\n'
        python3 -c '
import sys
W, H = 32, 32
buf = [50] * (W * H)
for sx, sy in ((3, 3), (W - 7, 3), (3, H - 7), (W - 7, H - 7)):
    for dy in range(4):
        for dx in range(4):
            buf[(sy + dy) * W + (sx + dx)] = 200
sys.stdout.buffer.write(bytes(buf))
'
    } > "$out"
}

build_face_c_pgm() {
    # 32x32 horizontal edge: top half = 50, bottom half = 200.
    local out="$1"
    {
        printf 'P5\n32 32\n255\n'
        python3 -c '
import sys
W, H = 32, 32
buf = bytearray(W * H)
half = H // 2
for y in range(H):
    v = 50 if y < half else 200
    for x in range(W):
        buf[y * W + x] = v
sys.stdout.buffer.write(bytes(buf))
'
    } > "$out"
}

build_face_d_pgm() {
    # 32x32 pseudo-random high-entropy texture. Each pixel value is
    # a deterministic mix of (x*17 + y*31 + (x*y)%7*53) mod 256 -- a
    # spread-spectrum LBP signature that's far from any of the three
    # band/spot fixtures used for A/B/C. Confirmed empirically to
    # exceed the default 500-unit chi-squared threshold against each
    # of alice/bob/carol so the recognize() call correctly returns
    # "unknown" rather than a forced nearest-neighbor.
    local out="$1"
    {
        printf 'P5\n32 32\n255\n'
        python3 -c '
import sys
W, H = 32, 32
buf = bytearray(W * H)
for y in range(H):
    for x in range(W):
        v = (x * 17 + y * 31 + (x * y) % 7 * 53) % 256
        buf[y * W + x] = v
sys.stdout.buffer.write(bytes(buf))
'
    } > "$out"
}

build_face_a_pgm "$FACE_A"
build_face_b_pgm "$FACE_B"
build_face_c_pgm "$FACE_C"
build_face_d_pgm "$FACE_D"

if [ ! -s "$FACE_A" ] || [ ! -s "$FACE_B" ] || [ ! -s "$FACE_C" ] || [ ! -s "$FACE_D" ]; then
    printf "  ${C_RED}FAIL${C_RST}  fixture files did not get written\n"
    FAIL=$((FAIL+1))
    summary "scenario_vvv_face_recognize"
    exit
fi

INPUT=$(
    printf '/help\n'
    printf '/face_enroll\n'
    printf '/face_recognize\n'
    printf '/face_recognize %s\n' "$FACE_A"
    printf '/face_enroll missing %s\n' "$MISSING"
    printf '/face_enroll alice %s\n' "$FACE_A"
    printf '/face_enroll bob %s\n' "$FACE_B"
    printf '/face_enroll carol %s\n' "$FACE_C"
    printf '/face_recognize %s\n' "$FACE_A"
    printf '/face_recognize %s\n' "$FACE_B"
    printf '/face_recognize %s\n' "$FACE_C"
    printf '/face_recognize %s\n' "$FACE_D"
    printf '/quit\n'
)

OUT=$(echo "$INPUT" | "$CHAT" 2>&1)

# 1. /help advertises /face_enroll and /face_recognize.
assert_match "$OUT" "/face_enroll L PGM" \
    "/help advertises /face_enroll"
assert_match "$OUT" "/face_recognize PGM" \
    "/help advertises /face_recognize"

# 2. /face_enroll with no arg prints usage.
assert_match "$OUT" "/face_enroll needs LABEL PATH\\.pgm" \
    "/face_enroll with no arg prints usage"

# 3. /face_recognize with no arg prints usage.
assert_match "$OUT" "/face_recognize needs PATH\\.pgm" \
    "/face_recognize with no arg prints usage"

# 4. /face_recognize before any enrollment prints gallery-empty error.
assert_match "$OUT" "face_recognize FAILED: gallery empty" \
    "/face_recognize on empty gallery prints gallery-empty error"

# 5. /face_enroll on missing PGM prints parser error (graceful).
assert_match "$OUT" "face_enroll FAILED on .*: pgm:" \
    "/face_enroll on missing PGM prints parser error gracefully"

# 6a. Successful enrollments report monotonically-growing size.
assert_match "$OUT" "face_enroll OK label=alice size=1" \
    "alice enrolled: gallery size = 1"
assert_match "$OUT" "face_enroll OK label=bob size=2" \
    "bob enrolled: gallery size = 2"
assert_match "$OUT" "face_enroll OK label=carol size=3" \
    "carol enrolled: gallery size = 3"

# 7. /face_recognize on face_a returns alice with distance 0.
assert_match "$OUT" "face_recognize matched=alice distance=0 " \
    "/face_recognize face_a -> alice with distance 0"

# 8. /face_recognize on face_b returns bob with distance 0.
assert_match "$OUT" "face_recognize matched=bob distance=0 " \
    "/face_recognize face_b -> bob with distance 0"

# 9. /face_recognize on face_c returns carol with distance 0.
assert_match "$OUT" "face_recognize matched=carol distance=0 " \
    "/face_recognize face_c -> carol with distance 0"

# 10. /face_recognize on face_d (4th unrelated identity, chosen so
#     its LBP descriptor is far from all enrolled faces) returns
#     "unknown" -- the canonical unknown-rejection probe.
assert_match "$OUT" "face_recognize unknown distance=-1 threshold=500" \
    "/face_recognize face_d (NOT enrolled) -> unknown (correct rejection)"

# 11. The chat reaches /quit cleanly.
assert_match "$OUT" "bye\\." \
    "chat reaches /quit cleanly after /face_enroll + /face_recognize probing"

# Cleanup.
rm -f "$FACE_A" "$FACE_B" "$FACE_C" "$FACE_D"

summary "scenario_vvv_face_recognize"
