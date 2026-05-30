#!/usr/bin/env bash
# Scenario P -- /dp_status + /dp_query DP budget tracking (P3.6 / ADR-0053).
#
# Boot the chat, query /dp_status (initial budget), run /dp_query atoms many
# times consuming 0.1 eps each, then verify /dp_status reports the budget
# drain and a /dp_query past exhaustion returns the refusal line.
#
# Acceptance:
#   - /dp_status before any DP query shows the full budget remaining.
#   - /dp_query atoms prints `true=<n>` AND `noisy=<n>` -- both fields.
#   - Across 100+ noisy queries, the noisy values differ from the true
#     count (variance > 0; otherwise the DP mechanism is degenerate).
#   - After enough /dp_query atoms calls to drain the 10000 milli-eps
#     budget, /dp_status reports 10000 consumed / 0 remaining.
#   - A /dp_query atoms call past exhaustion returns "budget exhausted".
#   - /help advertises both new commands.
#
# Note on input volume: the chat REPL buffers `io_input` reads in chunks
# and occasionally drops one line per ~70-line block (a pre-existing
# chat-REPL behavior, NOT a DP module issue). The test sends 130 queries
# -- comfortably more than the 100 needed to drain a 10000 milli-eps
# budget -- so the budget is robustly drained even with a few buffered
# drops.

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0

it_section "scenario P: /dp_status + /dp_query DP budget tracking (ADR-0053)"

# Clean snapshot/dlog: the DP budget tests run against a fresh session so
# the seed atom count is stable for the assertions below.
rm -f /tmp/crossengin.snap /tmp/crossengin.default.snap \
      /tmp/crossengin.dlog /tmp/crossengin.default.dlog

# Build the input. 130 dp_query atoms calls is well over the 100 needed
# to drain 10000 milli-eps even with chat REPL buffer drops.
INPUT=$(
    printf '/dp_status\n'
    for i in $(seq 1 130); do
        printf '/dp_query atoms\n'
    done
    printf '/dp_status\n'
    printf '/dp_query atoms\n'
    printf '/help\n'
    printf '/quit\n'
)

OUT=$(echo "$INPUT" | "$CHAT" 2>&1)

# 1. Initial /dp_status before any DP query: full budget remaining, no
#    queries consumed.
assert_match "$OUT" "dp budget: 0 / 10000 milli-eps consumed.*remaining 10000 milli-eps" \
    "initial /dp_status shows zero consumed of 10000"
assert_match "$OUT" "0 queries\\)" \
    "initial /dp_status reports 0 queries"

# 2. /dp_query atoms outputs both true and noisy fields.
assert_match "$OUT" "dp_query atoms: true=[0-9]+ noisy=-?[0-9]+" \
    "/dp_query atoms prints true=... noisy=... format"

# 3. Each /dp_query atoms call lists the epsilon and remaining.
assert_match "$OUT" "epsilon=100 milli, remaining [0-9]+\\)" \
    "/dp_query atoms reports per-call epsilon + remaining"

# 4. After enough successful /dp_query atoms calls, the budget is fully
#    drained (10000 consumed) and the second /dp_status reports zero
#    remaining. With 130 attempted calls and 100 needed to drain the
#    budget, the second /dp_status MUST see 10000 / 10000 consumed.
assert_match "$OUT" "dp budget: 10000 / 10000 milli-eps consumed.*remaining 0 milli-eps over 100 queries" \
    "/dp_status after >=100 queries: full drain (0 remaining, 100 queries)"

# 5. At least one /dp_query atoms past the budget drain returns the
#    refusal line ("budget exhausted").
assert_match "$OUT" "dp_query atoms: budget exhausted \\(remaining 0 milli-eps\\)" \
    "post-exhaustion /dp_query is refused"

# 6. /help advertises both commands (one /help line each).
assert_match "$OUT" "/dp_status +print the session.*differential-privacy budget" \
    "/help advertises /dp_status"
assert_match "$OUT" "/dp_query TARGET +run a DP-noised KG query" \
    "/help advertises /dp_query"

# 7. Variance check: across all calls, at least one noisy answer should
#    differ from the true count (otherwise variance is zero and the
#    privacy claim is empty). Extract every `true=N noisy=M` pair and
#    count those where N != M.
NONZERO=$(echo "$OUT" | grep -oE "true=[0-9]+ noisy=-?[0-9]+" \
    | awk -F'[= ]+' '{ if ($2 != $4) print }' | wc -l)
if [ "$NONZERO" -ge 5 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  noise variance > 0 across drained queries (%d distinct from true)\n" "$NONZERO"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  noise variance was zero -- DP mechanism is degenerate\n"
fi

# 8. The remaining-budget field across consecutive queries should be
#    monotonically decreasing (until 0 / refused). Sanity check: extract
#    the remaining values and confirm strict decrease over the first 10.
REMAINING=$(echo "$OUT" | grep -oE "remaining [0-9]+\\)" \
    | grep -oE "[0-9]+" | head -10)
PREV=999999
MONO=1
for r in $REMAINING; do
    if [ "$r" -ge "$PREV" ]; then MONO=0; fi
    PREV=$r
done
if [ "$MONO" -eq 1 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  remaining budget strictly decreases across the first 10 queries\n"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  remaining budget NOT monotonically decreasing\n"
fi

summary "scenario_p_dp_budget"
