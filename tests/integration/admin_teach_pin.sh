#!/usr/bin/env bash
# Admin commands -- /teach and /pin edge cases.

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0

# -------------------- /teach --------------------
it_section "admin: /teach"

# Empty arg: usage hint, no crash.
OUT=$(run_chat '/teach')
assert_match "$OUT" "\\(/teach needs a word\\)" "/teach with no arg prints usage hint"

# Valid arg: ingestion success, atom count goes up.
OUT=$(run_chat '/status
/teach widget
/status')
B=$(echo "$OUT" | grep "knowledge:" | sed -n '1p' | grep -oE '[0-9]+' | head -1)
A=$(echo "$OUT" | grep "knowledge:" | sed -n '2p' | grep -oE '[0-9]+' | head -1)
if [ -n "$B" ] && [ -n "$A" ] && [ "$A" -gt "$B" ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  /teach grew the KG: %s -> %s\n" "$B" "$A"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  /teach did not grow the KG: %s -> %s\n" "$B" "$A"
fi
assert_match "$OUT" "ingested 'widget'" "/teach acknowledges ingestion"

# Twice with same word: second is a no-op (au_ingest is idempotent by label).
OUT=$(run_chat '/teach widget
/teach widget
/status')
# Two "(ingested 'widget' ...)" lines should appear, and the final atom
# count should be exactly one more than the seed (584). The second call is
# a no-op at the KG level.
COUNT_LINES=$(echo "$OUT" | grep -c "ingested 'widget'")
assert_eq "$COUNT_LINES" "2" "/teach prints ingestion line both times"
FINAL=$(echo "$OUT" | grep "knowledge:" | grep -oE '[0-9]+' | head -1)
assert_eq "$FINAL" "585" "/teach W twice yields exactly one new atom (no double-count)"

# -------------------- /pin --------------------
it_section "admin: /pin"

# Missing args: usage hint.
OUT=$(run_chat '/pin')
assert_match "$OUT" "usage: /pin WORD CONFIDENCE" "/pin with no args prints usage"

# Single arg: usage hint with the word echoed.
OUT=$(run_chat '/pin widget')
assert_match "$OUT" "usage: /pin widget CONFIDENCE" "/pin with one arg prints usage for that word"

# Word that doesn't exist.
OUT=$(run_chat '/pin nonsuchword 500')
assert_match "$OUT" "no such word: 'nonsuchword'" "/pin unknown word prints error"

# Valid pin on a known word.
OUT=$(run_chat '/teach widget
/pin widget 900')
assert_match "$OUT" "pinned 'widget' to confidence 900/1000" "/pin valid word prints confirmation"

# Out-of-range confidence: capped at 1000 (not an error).
OUT=$(run_chat '/teach widget
/pin widget 9999')
assert_match "$OUT" "pinned 'widget' to confidence 1000/1000" "/pin C>1000 caps at 1000"

# Out-of-range below 0: capped at 0.
OUT=$(run_chat '/teach widget
/pin widget -50')
# rt_str_to_int may parse "-50" as 0 or as a negative -- either way the
# cap should drive the displayed confidence to 0.
assert_match "$OUT" "pinned 'widget' to confidence 0/1000" "/pin C<0 caps at 0"

summary "admin_teach_pin"
