#!/usr/bin/env bash
# Admin commands -- /help, /status, /history, unknown command, quit/exit/empty.
#
# These are the read-only commands plus the exit paths; bundled together so
# the harness only spawns the chat a handful of times.

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0

# -------------------- /help --------------------
it_section "admin: /help"

OUT=$(run_chat '/help')
assert_match "$OUT" "admin commands:" "/help prints a 'admin commands:' header"
assert_match "$OUT" "/help"   "/help lists /help"
assert_match "$OUT" "/status" "/help lists /status"
assert_match "$OUT" "/save"   "/help lists /save"
assert_match "$OUT" "/load"   "/help lists /load"
assert_match "$OUT" "/meta"   "/help lists /meta"
assert_match "$OUT" "/teach"  "/help lists /teach"
assert_match "$OUT" "/learn"  "/help lists /learn"
assert_match "$OUT" "/pin"    "/help lists /pin"
assert_match "$OUT" "/why"    "/help lists /why"
assert_match "$OUT" "/halt"   "/help lists /halt"
assert_match "$OUT" "/resume" "/help lists /resume"
assert_match "$OUT" "/reflect" "/help lists /reflect"
assert_match "$OUT" "/history" "/help lists /history"
assert_match "$OUT" "/quit"   "/help lists /quit"

# -------------------- /status --------------------
it_section "admin: /status"

OUT=$(run_chat '/status')
assert_match "$OUT" "soul +: Aurora"               "/status shows soul name"
assert_match "$OUT" "mood +: valence=[0-9]+"       "/status shows mood valence"
assert_match "$OUT" "knowledge: [0-9]+ atoms in shared KG" "/status shows KG size"
assert_match "$OUT" "audit +: [0-9]+ decision-log" "/status shows audit count"
assert_match "$OUT" "scheduler: tick=[0-9]+ rate=[0-9]+Hz" "/status shows scheduler"
assert_match "$OUT" "goal +: " "/status shows current goal"

# /status exit code: process should still exit 0 after.
if (printf '/status\n/quit\n' | "$CHAT" >/dev/null 2>&1); then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  /status exits 0\n"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  /status exited non-zero\n"
fi

# -------------------- /history --------------------
it_section "admin: /history"

# Before any decision exists.
OUT=$(run_chat '/history')
assert_match "$OUT" "no decisions yet" "/history before any decision says 'no decisions yet'"

# After a decision exists, default 5.
OUT=$(run_chat 'hello
/history')
assert_match "$OUT" "#[0-9]+ (intent|outcome) speak" "/history default lists decision entries"
# Default cap is 5 -- assert at least 1, at most 5 entries shown.
ENTRIES=$(echo "$OUT" | grep -cE '#[0-9]+ (intent|outcome) speak')
if [ "$ENTRIES" -ge 1 ] && [ "$ENTRIES" -le 5 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  /history default cap honoured (saw %s entries, <=5)\n" "$ENTRIES"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  /history default printed %s entries (expected 1..5)\n" "$ENTRIES"
fi

# With explicit N. Each history line is "  #<seq> <kind> <action> tier=...",
# emitted right after a "> " prompt, so the line in stdout looks like
# "  #1 outcome speak tier=notify outcome=ok" with a leading "> " prepended
# only on the first one. Match the unique '#<seq> outcome|intent' anchor.
OUT=$(run_chat 'hello
/history 1')
ENTRIES=$(echo "$OUT" | grep -cE '#[0-9]+ (intent|outcome) speak')
if [ "$ENTRIES" -ge 1 ] && [ "$ENTRIES" -le 1 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  /history 1 caps to 1 entry (saw %s)\n" "$ENTRIES"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  /history 1 produced %s entries\n" "$ENTRIES"
fi

# With N larger than total: should not crash; the entries shown <= what exists.
OUT=$(run_chat 'hello
/history 9999')
TOTAL=$(echo "$OUT" | grep -cE '#[0-9]+ (intent|outcome) speak')
if [ "$TOTAL" -ge 1 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  /history N>total still prints what exists (saw %s)\n" "$TOTAL"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  /history N>total produced no entries\n"
fi

# -------------------- /why before any decision --------------------
it_section "admin: /why before any decision"

OUT=$(run_chat '/why')
assert_match "$OUT" "no decisions yet" "/why before any decision says 'no decisions yet'"

# /why after a decision.
OUT=$(run_chat 'hello
/why')
assert_match "$OUT" "most recent: #[0-9]+ " "/why after a decision shows the most recent entry"
assert_match "$OUT" "tier +: " "/why prints the tier line"
assert_match "$OUT" "outcome : " "/why prints the outcome line"

# -------------------- unknown command --------------------
it_section "admin: unknown command"

OUT=$(run_chat '/bogusbazquux')
assert_match "$OUT" "unknown command: /bogusbazquux -- try /help" "/bogusbazquux yields the expected hint"

# -------------------- quit / exit / empty line --------------------
it_section "admin: exit paths"

OUT=$(printf '/quit\n' | "$CHAT" 2>&1)
assert_match "$OUT" "bye\\." "/quit prints bye."

OUT=$(printf '/exit\n' | "$CHAT" 2>&1)
assert_match "$OUT" "bye\\." "/exit prints bye."

OUT=$(printf 'quit\n' | "$CHAT" 2>&1)
assert_match "$OUT" "bye\\." "bare 'quit' (no slash) prints bye."

OUT=$(printf 'exit\n' | "$CHAT" 2>&1)
assert_match "$OUT" "bye\\." "bare 'exit' (no slash) prints bye."

OUT=$(printf '\n' | "$CHAT" 2>&1)
assert_match "$OUT" "bye\\." "empty line at prompt prints bye."

# Each of these exit paths should leave the process with exit code 0.
if printf '/quit\n' | "$CHAT" >/dev/null 2>&1; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  /quit exits 0\n"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  /quit exited non-zero\n"
fi

summary "admin_help_status"
