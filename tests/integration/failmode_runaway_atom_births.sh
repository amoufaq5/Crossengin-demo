#!/usr/bin/env bash
# Failure mode -- feeding many distinct unknown words rapidly must not blow up
# the KG. The atom_birth_monitor's gating + the seed/teach paths should result
# in growth proportional to the input but bounded by reasonable expectations.
#
# We feed 200 distinct invented words (zlork0..zlork199, none in seed). The
# chat's "auto-learn unknown word" path admits a new atom per unique unknown
# token. We assert:
#   - the process does not crash,
#   - /status reports a knowledge count that's grown, but by a sane delta
#     (<= 200 * 2 = 400 per token allowance + safety margin),
#   - the chat is still responsive to a final /status request.
#
# This is a runaway-input smoke test, not a precise growth claim -- the exact
# slope depends on the seed shape and the auto-learn policy. We accept any
# growth in [200, 800] inclusive.

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0

it_section "failmode: 200 distinct unknown words -- runaway gate check"

# Build the input: a single /status, then 200 distinct fake words one per line,
# then a final /status, then /quit.
INPUT_FILE=/tmp/ce_int_runaway_input_$$.txt
trap 'rm -f "$INPUT_FILE"' EXIT
{
    echo "/status"
    for i in $(seq 0 199); do
        echo "zlork${i}"
    done
    echo "/status"
    echo "/quit"
} > "$INPUT_FILE"

# Capture full output. Allow up to 60s -- 200 turns each doing perceive +
# auto-learn is non-trivial but should finish well inside that.
START_TS=$(date +%s)
OUT=$(timeout 60 "$CHAT" <"$INPUT_FILE" 2>&1)
END_TS=$(date +%s)
DURATION=$((END_TS - START_TS))

# The chat must have actually returned within the timeout. timeout exits 124
# on TLE -- we test by checking that bye. is in the output.
assert_match "$OUT" "bye\\." "chat returned cleanly within timeout (${DURATION}s)"

# Extract before/after knowledge atom counts.
BEFORE=$(echo "$OUT" | grep -E "^knowledge: " | sed -n '1p' | grep -oE '[0-9]+' | head -1)
AFTER=$( echo "$OUT" | grep -E "^knowledge: " | sed -n '2p' | grep -oE '[0-9]+' | head -1)

if [ -n "$BEFORE" ] && [ -n "$AFTER" ]; then
    DELTA=$((AFTER - BEFORE))
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  knowledge grew %d -> %d (delta=%d) -- both readings captured\n" \
        "$BEFORE" "$AFTER" "$DELTA"
    # Lower bound: at least one atom per unique word. 200 is the floor; the
    # auto-learn may admit additional binding atoms (concept + word atom), so
    # we allow up to 4x as the upper bound.
    if [ "$DELTA" -ge 200 ] && [ "$DELTA" -le 800 ]; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}PASS${C_RST}  delta=%d falls in [200, 800] -- gate not runaway\n" "$DELTA"
    else
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  delta=%d outside expected [200, 800] -- gate may be runaway\n" "$DELTA"
    fi
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  could not extract knowledge counts (before='%s', after='%s')\n" \
        "$BEFORE" "$AFTER"
fi

# Auto-learn confirmation: every unknown word should trigger a
# "(learned N new word(s) -- M atoms total)" line at least once.
assert_match "$OUT" "learned [0-9]+ new word\\(s\\)" "auto-learn fired for at least one unknown"

# Per-event perceive lines: every input message produces one perceive output.
# Expect close to 200 of them (one per fake word). Allow some slack.
PERCEIVE_COUNT=$(echo "$OUT" | grep -cE "perceive\\(m=[0-9]+,unk=[0-9]+\\)")
if [ "$PERCEIVE_COUNT" -ge 100 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  %d perceive lines (>=100) -- input loop processed the flood\n" \
        "$PERCEIVE_COUNT"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  only %d perceive lines (expected >=100)\n" "$PERCEIVE_COUNT"
fi

# Final /status must include the standard lines: chat is still healthy.
assert_match "$OUT" "scheduler: tick=" "post-flood /status still reports scheduler"
assert_match "$OUT" "goal +: " "post-flood /status still reports goal"

summary "failmode_runaway_atom_births"
