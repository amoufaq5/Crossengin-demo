#!/usr/bin/env bash
# Scenario Q -- /see PGM admin command end-to-end (P3.1 / ADR-0014).
#
# Build a hand-rolled binary PGM (P5) fixture in /tmp, boot the chat,
# feed `/see /tmp/<fixture>.pgm`, verify the chat (a) prints the
# dimensions and operator-readable summary line, (b) emits the expected
# feature atoms (image_dim_small + image_mid + image_bucket_<N>), and
# (c) /help advertises the command.
#
# Acceptance:
#   - /help advertises /see PATH (one line, in the speak/see admin block).
#   - /see <fixture> prints "(saw image ...  4x4 mean=120 ...)".
#   - The features line lists image_dim_small (4x4 = 16 px area).
#   - The features line lists image_mid (mean=120, between 80 and 175).
#   - The features line lists image_bucket_0 (gradient: each bin holds 2
#     pixels; the first-tie-wins ordering picks bucket 0).
#   - A second /see on a uniform grey image yields image_hist_peaked
#     (zero entropy -- all pixels identical) and image_bucket_6
#     (mean 200 / 32 == 6).
#   - /see with no arg prints the usage line; the chat keeps running.
#   - /see on a non-PGM file (truncated random bytes) prints the
#     parser's bracketed error message; the chat keeps running.

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0

it_section "scenario Q: /see PGM image admin command (ADR-0014 visual seam)"

FIX="/tmp/ce_scenario_q.pgm"
FLAT="/tmp/ce_scenario_q_flat.pgm"
BAD="/tmp/ce_scenario_q_bad.bin"
EDGE="/tmp/ce_scenario_q_edge.pgm"

# Cleanup any stale fixture files from a previous run.
rm -f "$FIX" "$FLAT" "$BAD" "$EDGE"

# Build the 4x4 gradient: pixels 0, 16, 32, ..., 240 (mean = 120).
# Header: P5\n4 4\n255\n  (11 bytes)
{
    printf 'P5\n4 4\n255\n'
    # 16 bytes: 0x00, 0x10, 0x20, ..., 0xf0
    printf '\x00\x10\x20\x30\x40\x50\x60\x70\x80\x90\xa0\xb0\xc0\xd0\xe0\xf0'
} > "$FIX"

# Build the uniform-grey 4x4 fixture at intensity 200 (mean=200, bucket=6).
{
    printf 'P5\n4 4\n255\n'
    head -c 16 /dev/zero | tr '\000' '\310'   # 0xC8 == 200
} > "$FLAT"

# Build a bad fixture: 8 random bytes with no PGM magic.
printf '\x4e\x4f\x54\x50\x47\x4d\x00\x00' > "$BAD"

# Build a 16x16 vertical-edge fixture: left half intensity 0 (black),
# right half intensity 255 (white). This trips the P3.3 structural
# detectors: Sobel finds a strong vertical-edge column producing
# image_edge_dense + image_orient_0 (horizontal gradient = vertical edge).
# Harris finds NO strong corners on a pure edge so image_corner_count_low
# fires.
{
    printf 'P5\n16 16\n255\n'
    # 16 rows. Each row: 8 zero bytes + 8 0xFF bytes.
    for i in $(seq 1 16); do
        head -c 8 /dev/zero
        head -c 8 /dev/zero | tr '\000' '\377'
    done
} > "$EDGE"

if [ ! -s "$FIX" ]; then
    printf "  ${C_RED}FAIL${C_RST}  fixture %s did not get written\n" "$FIX"
    FAIL=$((FAIL+1))
    summary "scenario_q_image_see"
    exit
fi

INPUT=$(
    printf '/help\n'
    printf '/see\n'
    printf '/see %s\n' "$FIX"
    printf '/see %s\n' "$FLAT"
    printf '/see %s\n' "$EDGE"
    printf '/see %s\n' "$BAD"
    printf '/quit\n'
)

OUT=$(echo "$INPUT" | "$CHAT" 2>&1)

# 1. /help advertises /see PATH. (Help text covers both PGM and PNG
# after P3.1.PNG; the original PGM-only wording was relaxed to match
# the broader "decode the PGM ... PNG ... image" line.)
assert_match "$OUT" "/see PATH +decode the PGM .* image" \
    "/help advertises /see"

# 2. /see with no arg prints the usage line.
assert_match "$OUT" "/see needs PATH" \
    "/see with no arg prints usage"

# 3. /see on the gradient fixture prints the summary line.
assert_match "$OUT" "saw image $FIX \[4x4 mean=120" \
    "/see prints dims + mean on 4x4 gradient"

# 4. Features line lists image_dim_small (area 16 << 4096 threshold).
assert_match "$OUT" "features:.*image_dim_small" \
    "/see features contain image_dim_small for 4x4"

# 5. Features line lists image_mid (mean 120 in [80, 175]).
assert_match "$OUT" "features:.*image_mid" \
    "/see features contain image_mid for mean=120"

# 6. Features line lists image_bucket_0 (gradient -> ties; first-bin wins).
assert_match "$OUT" "features:.*image_bucket_0" \
    "/see features contain image_bucket_0 for gradient"

# 7. Uniform grey at intensity 200 -> mean=200, bucket=6.
assert_match "$OUT" "saw image $FLAT \[4x4 mean=200.*dom_bucket=6" \
    "/see prints dims + mean=200 + bucket=6 on uniform grey"

# 8. Uniform grey is image_bright (mean=200 > 175 threshold).
assert_match "$OUT" "features:.*image_bright" \
    "/see features contain image_bright for mean=200"

# 9. Uniform grey is image_hist_peaked (entropy=0 < 3000 milli-bits).
assert_match "$OUT" "features:.*image_hist_peaked" \
    "/see features contain image_hist_peaked for uniform image"

# 10. /see on bad bytes surfaces the parser's bracketed error.
assert_match "$OUT" "see FAILED: pgm: not a PGM" \
    "/see on non-PGM bytes prints the parser's error"

# 11. The chat survives the bad input and reaches /quit.
assert_match "$OUT" "bye\." \
    "chat reaches /quit cleanly after malformed /see"

# ---- P3.3 structural features on 16x16 vertical-edge fixture -------------

# 12. /see on the 16x16 edge fixture prints the summary line.
assert_match "$OUT" "saw image $EDGE \[16x16" \
    "/see prints dims on 16x16 edge fixture"

# 13. The 16x16 edge fixture triggers Sobel: image_edge_dense (transition
# column has many high-magnitude pixels).
assert_match "$OUT" "features:.*image_edge_dense" \
    "/see surfaces image_edge_dense on 16x16 vertical-edge fixture"

# 14. The 16x16 edge fixture has a vertical edge (intensity changes
# horizontally), so the dominant orientation is bucket 0 = horizontal
# gradient. The label image_orient_0 appears.
assert_match "$OUT" "features:.*image_orient_0" \
    "/see surfaces image_orient_0 on vertical edge"

# 15. Harris on a pure-edge fixture finds few corners: image_corner_count_low.
assert_match "$OUT" "features:.*image_corner_count_low" \
    "/see surfaces image_corner_count_low on edge-only fixture"

# Cleanup.
rm -f "$FIX" "$FLAT" "$BAD" "$EDGE"

summary "scenario_q_image_see"
