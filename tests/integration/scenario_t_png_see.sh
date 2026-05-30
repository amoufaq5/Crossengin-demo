#!/usr/bin/env bash
# Scenario T -- /see PNG admin command end-to-end (P3.1.PNG / ADR-0014).
#
# Generate a tiny stored-DEFLATE PNG via scripts/gen_test_png.py, boot
# the chat, feed `/see /tmp/ce_scenario_t.png`, verify the chat (a) prints
# the dimensions and operator-readable summary line, (b) reports the PNG
# decoder by name, (c) emits the expected feature atoms, and (d) /help
# advertises the updated /see command description.
#
# Acceptance:
#   - /help advertises /see and mentions PNG support.
#   - /see <png> prints "(saw image ... 16x16 mean=... decoder=png])".
#   - The features line lists image_dim_small (16*16 = 256 px area).
#   - The features line lists image_bucket_<N> for some N.
#   - /see on a corrupt PNG (truncated random bytes with PNG signature
#     prefix only) surfaces the parser's bracketed error.
#   - /see on a .pgm path still routes through the PGM decoder
#     (decoder=pgm in the summary), so the PNG addition does not
#     regress P3.1's PGM happy path.
#   - The chat survives the malformed /see and reaches /quit.

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0

it_section "scenario T: /see PNG image admin command (ADR-0014 PNG decoder)"

PNG_FIX="/tmp/ce_scenario_t.png"
BAD_PNG="/tmp/ce_scenario_t_bad.png"
PGM_FIX="/tmp/ce_scenario_t.pgm"

# Cleanup any stale fixtures from a previous run.
rm -f "$PNG_FIX" "$BAD_PNG" "$PGM_FIX"

# Probe Python first -- the test depends on it for the fixture and is
# otherwise indistinguishable from a sandbox where /see PNG is untested.
if ! command -v python3 >/dev/null 2>&1; then
    printf "  ${C_YEL}SKIP${C_RST}  python3 not on PATH -- cannot generate PNG fixture\n"
    summary "scenario_t_png_see"
    exit 0
fi

# Generate the 16x16 PNG fixture via the dedicated helper script.
GEN="$(dirname "$0")/../../scripts/gen_test_png.py"
if ! python3 "$GEN" 16 16 "$PNG_FIX" >/dev/null 2>&1; then
    printf "  ${C_RED}FAIL${C_RST}  scripts/gen_test_png.py 16 16 $PNG_FIX failed\n"
    FAIL=$((FAIL+1))
    summary "scenario_t_png_see"
    exit
fi

if [ ! -s "$PNG_FIX" ]; then
    printf "  ${C_RED}FAIL${C_RST}  fixture %s did not get written\n" "$PNG_FIX"
    FAIL=$((FAIL+1))
    summary "scenario_t_png_see"
    exit
fi

# Build the bad-PNG fixture: valid 8-byte signature followed by garbage.
printf '\x89PNG\r\n\x1a\nBADCHUNK_NOT_REAL' > "$BAD_PNG"

# Also build a small PGM fixture so we can verify the PNG addition did
# not regress P3.1's PGM routing.
{
    printf 'P5\n4 4\n255\n'
    printf '\xc8\xc8\xc8\xc8\xc8\xc8\xc8\xc8\xc8\xc8\xc8\xc8\xc8\xc8\xc8\xc8'
} > "$PGM_FIX"

INPUT=$(
    printf '/help\n'
    printf '/see %s\n' "$PNG_FIX"
    printf '/see %s\n' "$PGM_FIX"
    printf '/see %s\n' "$BAD_PNG"
    printf '/quit\n'
)

OUT=$(echo "$INPUT" | "$CHAT" 2>&1)

# 1. /help mentions the /see command (we no longer assert on the old
#    exact PGM phrasing -- the help text was updated to cover both
#    PGM and PNG).
assert_match "$OUT" "/see PATH +decode the PGM .* PNG .* image" \
    "/help advertises /see PGM/PNG image command"

# 2. /see on PNG prints dims + decoder=png.
assert_match "$OUT" "saw image $PNG_FIX \[16x16 mean=" \
    "/see PNG prints 16x16 dims + mean"
assert_match "$OUT" "saw image $PNG_FIX \[16x16 .*decoder=png" \
    "/see PNG names the PNG decoder"

# 3. Features line on PNG includes image_dim_small (256 px area).
assert_match "$OUT" "features:.*image_dim_small" \
    "/see PNG features contain image_dim_small for 16x16"

# 4. Features line on PNG contains some image_bucket_* atom.
assert_match "$OUT" "features:.*image_bucket_[0-9]" \
    "/see PNG features contain image_bucket_<N>"

# 5. PGM fallback still works: /see on a .pgm path routes through PGM.
assert_match "$OUT" "saw image $PGM_FIX \[4x4 .*decoder=pgm" \
    "/see PGM path still routes through PGM decoder"

# 6. Bad PNG surfaces the parser's bracketed error.
assert_match "$OUT" "see FAILED: png:" \
    "/see on truncated PNG prints png:-prefixed error"

# 7. Chat survives the malformed /see and reaches /quit cleanly.
assert_match "$OUT" "bye\." \
    "chat reaches /quit cleanly after malformed /see"

# Cleanup.
rm -f "$PNG_FIX" "$BAD_PNG" "$PGM_FIX"

summary "scenario_t_png_see"
