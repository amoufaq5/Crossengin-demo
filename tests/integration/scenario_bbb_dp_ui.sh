#!/usr/bin/env bash
# Scenario BBB -- /dp admin command + status pane DP budget reporting (R12F /
# ADR-0053 follow-up).
#
# Drives a chat session through the new `/dp <subcommand>` surface to assert:
#   - `/dp` with no args prints the usage block (5+ lines).
#   - `/dp status` renders the ASCII bar + percent + remaining budget.
#   - A few DP queries via `/dp_query atoms` are reflected in /dp status
#     (consumption increases; "last query Ts ago" replaces "no queries yet").
#   - `/dp log [N]` lists the last N queries with label "count" + eps_milli.
#   - `/dp warn <threshold>` accepts a value and is reflected in subsequent
#     status reads (the command echoes the new threshold).
#   - `/dp reset <T>` without 'confirm' is a NOOP that prints PENDING.
#   - `/dp reset <T> confirm` resets the total budget (subsequent /dp status
#     reports the new total).
#   - `/dp <bad-subcommand>` prints an unknown-subcommand message + usage.
#   - `/status` pane includes the new `dp       :` line with consumption %.
#   - `/help` advertises all four /dp sub-commands.
#
# 15+ assertions.

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0

it_section "scenario BBB: /dp admin command + status pane (R12F / ADR-0053)"

rm -f /tmp/crossengin.snap /tmp/crossengin.default.snap \
      /tmp/crossengin.dlog /tmp/crossengin.default.dlog

INPUT=$(
    printf '/dp\n'
    printf '/dp status\n'
    printf '/dp_query atoms\n'
    printf '/dp_query atoms\n'
    printf '/dp_query atoms\n'
    printf '/dp status\n'
    printf '/dp log 3\n'
    printf '/dp warn 700\n'
    printf '/dp warn 500\n'
    printf '/dp reset 5000\n'
    printf '/dp reset 5000 confirm\n'
    printf '/dp status\n'
    printf '/dp bogus\n'
    printf '/status\n'
    printf '/help\n'
    printf '/quit\n'
)

OUT=$(echo "$INPUT" | "$CHAT" 2>&1)

# 1. /dp with no args prints the usage headline.
assert_match "$OUT" "/dp <subcommand> -- differential-privacy budget management" \
    "/dp prints usage headline when called with no args"

# 2. Usage lists the 4 subcommands.
assert_match "$OUT" "/dp status +consumption bar \\+ remaining budget" \
    "usage lists 'status' subcommand"
assert_match "$OUT" "/dp log \\[N\\] +last N queries" \
    "usage lists 'log' subcommand"
assert_match "$OUT" "/dp warn <threshold> +set warn-at-consumption threshold" \
    "usage lists 'warn' subcommand"
assert_match "$OUT" "/dp reset <new_total> +admin reset" \
    "usage lists 'reset' subcommand"

# 3. Initial /dp status: full budget remaining, no queries yet.
assert_match "$OUT" "DP budget: \\[----------\\] 0% \\(0/10000 milli eps consumed; no queries yet\\)" \
    "/dp status (fresh) renders empty bar + 'no queries yet'"

# 4. After 3 /dp_query atoms calls (100 milli each = 300 spent), /dp status
#    reflects 3% consumption. The bar at 3% rounds to 0 filled cells (3/10
#    of a cell rounds down to 0 with our half-up rule when <5%).
assert_match "$OUT" "DP budget: \\[----------\\] 3% \\(300/10000 milli eps consumed; last query [0-9]+s ago\\)" \
    "/dp status after 3 queries: 3% consumed, last-query age present"

# 5. /dp log 3 lists 3 entries labelled 'count' (label set by kg_atom_count_dp).
assert_match "$OUT" "DP query log \\(last 3 of 3\\):" \
    "/dp log 3 prints header (last 3 of 3)"
assert_match "$OUT" "  1\\. count -> 100 milli-eps \\([0-9]+s ago\\)" \
    "/dp log entry 1: count label, 100 milli-eps"
assert_match "$OUT" "  3\\. count -> 100 milli-eps \\([0-9]+s ago\\)" \
    "/dp log entry 3: count label, 100 milli-eps"

# 6. /dp warn 700 echoes the new threshold.
assert_match "$OUT" "dp warn threshold set to 700 milli-eps" \
    "/dp warn 700 sets and echoes threshold"
assert_match "$OUT" "dp warn threshold set to 500 milli-eps" \
    "/dp warn 500 sets and echoes lowered threshold"

# 7. /dp reset 5000 (no 'confirm') is a NOOP that prints PENDING.
assert_match "$OUT" "dp reset PENDING: would set total to 5000 milli-eps \\(re-run with 'confirm' to apply\\)" \
    "/dp reset without confirm is a NOOP pending notice"

# 8. /dp reset 5000 confirm actually resets the budget (echoes OK + old/new).
assert_match "$OUT" "dp reset OK: total 10000 -> 5000 milli-eps \\(was 300 consumed; reset_count=1\\)" \
    "/dp reset 5000 confirm resets total to 5000"

# 9. /dp status after reset: total now 5000, consumed 0.
assert_match "$OUT" "DP budget: \\[----------\\] 0% \\(0/5000 milli eps consumed" \
    "/dp status post-reset: total 5000, consumed 0"

# 10. /dp bogus: unknown subcommand message.
assert_match "$OUT" "\\(/dp: unknown subcommand 'bogus'\\)" \
    "/dp bogus prints unknown-subcommand message"

# 11. /status pane includes the new dp line (post-reset, 0% used).
assert_match "$OUT" "^dp       : 0% used \\(0/5000 milli eps; no queries yet\\)" \
    "/status pane includes dp line (post-reset, 0% used)"

# 12. /help advertises all four /dp sub-commands.
assert_match "$OUT" "/dp status +DP budget bar" \
    "/help advertises /dp status"
assert_match "$OUT" "/dp log \\[N\\] +last N DP queries" \
    "/help advertises /dp log"
assert_match "$OUT" "/dp warn THRESH +set warn-at-consumption" \
    "/help advertises /dp warn"
assert_match "$OUT" "/dp reset T confirm +reset budget" \
    "/help advertises /dp reset"

summary "scenario_bbb_dp_ui"
