#!/usr/bin/env bash
# Scenario PPPP -- /ocr PGM admin command end-to-end (R24C template-matching OCR).
#
# Synthesizes PGM fixtures in /tmp using the SAME 8x8 bitmap-font glyphs the
# image_ocr.nova module's default gallery ships, feeds them through the chat
# /ocr admin, and asserts the recognized text + detection counts match.
#
# Acceptance:
#   - /help advertises /ocr PATH.
#   - /ocr <hi-fixture> returns text="HI" with 2 detections.
#   - /ocr <hello-fixture> returns text="HELLO" with 5 detections.
#   - /ocr <abc-fixture> returns text="ABC" with 3 detections.
#   - /ocr <gibberish-fixture> (uniform mid-grey, no glyphs) returns
#     text="" with 0 detections.
#   - /ocr on a missing file surfaces the parser's bracketed error;
#     the chat keeps running.
#   - /ocr with no arg prints the usage line; the chat keeps running.
#   - The chat reaches /quit cleanly after the malformed /ocr probing.

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0

it_section "scenario PPPP: /ocr PGM image admin command (R24C template-matching OCR)"

HI_FIX="/tmp/ce_scenario_pppp_hi.pgm"
HELLO_FIX="/tmp/ce_scenario_pppp_hello.pgm"
ABC_FIX="/tmp/ce_scenario_pppp_abc.pgm"
GIB_FIX="/tmp/ce_scenario_pppp_gibberish.pgm"
MISSING="/tmp/ce_scenario_pppp_nonexistent.pgm"

# Cleanup any stale fixture files from a previous run.
rm -f "$HI_FIX" "$HELLO_FIX" "$ABC_FIX" "$GIB_FIX" "$MISSING"

# Build a PGM whose pixels are the concatenation of one or more 8x8 glyphs
# from image_ocr.nova's default gallery. The masks must match exactly --
# any drift here breaks the test.
gen_ocr_pgm() {
    local out="$1"; local text="$2"
    local width=$((${#text} * 8))
    {
        printf 'P5\n%d 8\n255\n' "$width"
        python3 -c "
import sys
GLYPHS = {
    '0': [124, 198, 206, 214, 230, 198, 124, 0],
    '1': [24, 56, 120, 24, 24, 24, 126, 0],
    '2': [124, 198, 6, 28, 112, 192, 254, 0],
    '3': [124, 198, 6, 60, 6, 198, 124, 0],
    '4': [12, 28, 60, 108, 254, 12, 12, 0],
    '5': [254, 192, 252, 6, 6, 198, 124, 0],
    '6': [60, 96, 192, 252, 198, 198, 124, 0],
    '7': [254, 198, 12, 24, 48, 48, 48, 0],
    '8': [124, 198, 198, 124, 198, 198, 124, 0],
    '9': [124, 198, 198, 126, 6, 12, 120, 0],
    'A': [56, 108, 198, 198, 254, 198, 198, 0],
    'B': [252, 198, 198, 252, 198, 198, 252, 0],
    'C': [124, 198, 192, 192, 192, 198, 124, 0],
    'D': [248, 204, 198, 198, 198, 204, 248, 0],
    'E': [254, 192, 192, 252, 192, 192, 254, 0],
    'F': [254, 192, 192, 252, 192, 192, 192, 0],
    'G': [124, 198, 192, 206, 198, 198, 124, 0],
    'H': [198, 198, 198, 254, 198, 198, 198, 0],
    'I': [126, 24, 24, 24, 24, 24, 126, 0],
    'J': [6, 6, 6, 6, 6, 198, 124, 0],
    'K': [198, 204, 216, 240, 216, 204, 198, 0],
    'L': [192, 192, 192, 192, 192, 192, 254, 0],
    'M': [198, 238, 254, 214, 198, 198, 198, 0],
    'N': [198, 230, 246, 222, 206, 198, 198, 0],
    'O': [124, 198, 198, 198, 198, 198, 124, 0],
    'P': [252, 198, 198, 252, 192, 192, 192, 0],
    'Q': [124, 198, 198, 198, 214, 204, 118, 0],
    'R': [252, 198, 198, 252, 216, 204, 198, 0],
    'S': [124, 198, 192, 124, 6, 198, 124, 0],
    'T': [126, 24, 24, 24, 24, 24, 24, 0],
    'U': [198, 198, 198, 198, 198, 198, 124, 0],
    'V': [198, 198, 198, 198, 198, 108, 56, 0],
    'W': [198, 198, 198, 214, 254, 238, 198, 0],
    'X': [198, 108, 56, 16, 56, 108, 198, 0],
    'Y': [198, 198, 108, 56, 24, 24, 24, 0],
    'Z': [254, 6, 12, 24, 48, 96, 254, 0],
}

def render_glyph(masks):
    rows = []
    for m in masks:
        row = []
        for col in range(8):
            shift = 7 - col
            bit = (m >> shift) & 1
            row.append(255 if bit else 0)
        rows.append(row)
    return rows

text = '''$text'''
chars = {c: render_glyph(GLYPHS[c]) for c in set(text)}
buf = []
for r in range(8):
    for ch in text:
        buf.extend(chars[ch][r])
sys.stdout.buffer.write(bytes(buf))
"
    } > "$out"
}

gen_ocr_pgm "$HI_FIX" "HI"
gen_ocr_pgm "$HELLO_FIX" "HELLO"
gen_ocr_pgm "$ABC_FIX" "ABC"

# Build a gibberish-but-syntactically-valid PGM: 16x8 uniform mid-grey
# (value 128). Every sliding window position has the same patch, so no
# template scores >= 950 -- the OCR result must be empty.
{
    printf 'P5\n16 8\n255\n'
    head -c 128 /dev/zero | tr '\000' '\200'
} > "$GIB_FIX"

if [ ! -s "$HI_FIX" ] || [ ! -s "$HELLO_FIX" ] || [ ! -s "$ABC_FIX" ] || [ ! -s "$GIB_FIX" ]; then
    printf "  ${C_RED}FAIL${C_RST}  fixture files did not get written\n"
    FAIL=$((FAIL+1))
    summary "scenario_pppp_ocr"
    exit
fi

INPUT=$(
    printf '/help\n'
    printf '/ocr\n'
    printf '/ocr %s\n' "$HI_FIX"
    printf '/ocr %s\n' "$HELLO_FIX"
    printf '/ocr %s\n' "$ABC_FIX"
    printf '/ocr %s\n' "$GIB_FIX"
    printf '/ocr %s\n' "$MISSING"
    printf '/quit\n'
)

OUT=$(echo "$INPUT" | "$CHAT" 2>&1)

# 1. /help advertises /ocr PATH.
assert_match "$OUT" "/ocr PATH +template-matching OCR" \
    "/help advertises /ocr"

# 2. /ocr with no arg prints the usage line.
assert_match "$OUT" "/ocr needs a PATH" \
    "/ocr with no arg prints usage"

# 3. /ocr on the HI fixture returns text="HI" with detections=2.
assert_match "$OUT" "ocr $HI_FIX: text=\"HI\" detections=2" \
    "/ocr recognizes 'HI' from synthetic 2-char fixture"

# 4. /ocr on the HELLO fixture returns text="HELLO" with detections=5.
assert_match "$OUT" "ocr $HELLO_FIX: text=\"HELLO\" detections=5" \
    "/ocr recognizes 'HELLO' from synthetic 5-char fixture"

# 5. /ocr on the ABC fixture returns text="ABC" with detections=3.
assert_match "$OUT" "ocr $ABC_FIX: text=\"ABC\" detections=3" \
    "/ocr recognizes 'ABC' from synthetic 3-char fixture"

# 6. /ocr on uniform-mid-grey gibberish returns text="" with detections=0.
assert_match "$OUT" "ocr $GIB_FIX: text=\"\" detections=0" \
    "/ocr on uniform-grey gibberish returns empty text"

# 7. /ocr on a missing file surfaces the PGM parser's bracketed error.
assert_match "$OUT" "ocr FAILED on $MISSING:" \
    "/ocr on missing file prints parser error"

# 8. The chat survives the malformed inputs and reaches /quit.
assert_match "$OUT" "bye\\." \
    "chat reaches /quit cleanly after /ocr probing"

# 9. The HELLO output appears before the gibberish output (chat ordering
# sanity -- ensures the chat processed each /ocr in order without
# bailing early).
HELLO_LINE=$(echo "$OUT" | grep -n "text=\"HELLO\"" | head -n1 | cut -d: -f1)
GIB_LINE=$(echo "$OUT" | grep -n "$GIB_FIX: text=\"\"" | head -n1 | cut -d: -f1)
if [ -n "$HELLO_LINE" ] && [ -n "$GIB_LINE" ] && [ "$HELLO_LINE" -lt "$GIB_LINE" ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  chat processes /ocr commands in order\n"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  chat ordering check: HELLO line=%s gibberish line=%s\n" \
        "$HELLO_LINE" "$GIB_LINE"
fi

# 10. ABC output appears (additional ordering / completeness sanity).
assert_match "$OUT" "text=\"ABC\"" \
    "ABC detection appears in chat output"

# Cleanup.
rm -f "$HI_FIX" "$HELLO_FIX" "$ABC_FIX" "$GIB_FIX"

summary "scenario_pppp_ocr"
