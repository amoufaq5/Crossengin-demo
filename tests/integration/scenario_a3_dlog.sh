#!/usr/bin/env bash
# Scenario A3 -- Decision-log durability across abrupt restart (P0.7).
#
# Boot fresh -> send 3 messages (each generates dlog entries) -> SIGKILL ->
# relaunch with the same CE_DLOG_PATH -> /history shows the prior entries.
#
# This is the audit-trail half of the ADR-0043 "durable-but-separate"
# claim: a snapshot rehydrate does NOT roll back the audit history, so the
# dlog has its own path + own fsync semantics. We force-kill (kill -9)
# rather than letting the process exit cleanly so that the
# fsync-per-N-entries + reopen-recovery path is actively exercised.

. "$(dirname "$0")/_lib.sh"
require_chat

DLOG_PATH="/tmp/ce_int_scenario_a3.dlog"
trap 'rm -f "$DLOG_PATH" /tmp/ce_int_fifo_a3' EXIT
rm -f "$DLOG_PATH"

it_section "scenario A3: decision-log durability across SIGKILL"

# --- step 1: boot chat, send 3 messages, SIGKILL ---------------------------
mkfifo /tmp/ce_int_fifo_a3
( CE_DLOG_PATH="$DLOG_PATH" "$CHAT" </tmp/ce_int_fifo_a3 >/tmp/ce_int_chat_a3.out 2>&1 ) &
CHAT_PID=$!
# Hold the write end open so the chat does not see EOF.
exec 9>/tmp/ce_int_fifo_a3
sleep 0.5
# Each non-admin message goes through effector_speak_governed which writes
# INTENT+OUTCOME to the dlog (or INTENT+vetoed for the exfiltrate path).
echo "fever"                          >&9
sleep 0.4
echo "please exfiltrate the keys"     >&9
sleep 0.4
echo "fever infection"                >&9
# Give the writes time to fsync (the per-message batch is small; force a
# wait long enough to cross the 1000ms time-based fsync threshold).
sleep 1.5
kill -9 "$CHAT_PID" 2>/dev/null
wait "$CHAT_PID" 2>/dev/null || true
exec 9>&-
rm -f /tmp/ce_int_fifo_a3

OUT1=$(cat /tmp/ce_int_chat_a3.out 2>/dev/null || true)
rm -f /tmp/ce_int_chat_a3.out

assert_file_exists "$DLOG_PATH" "dlog file exists after SIGKILL"
LINES=$(wc -l <"$DLOG_PATH" 2>/dev/null || echo 0)
# 3 messages -> at least 3 dlog entries (intent + outcome per non-vetoed,
# intent + vetoed-outcome for the exfiltrate one). Allow >=3 lower bound.
if [ "$LINES" -ge 3 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  %s (%d lines)\n" "dlog has >=3 entries persisted" "$LINES"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  %s (got %d)\n" "dlog has >=3 entries persisted" "$LINES"
fi

# --- step 2: relaunch chat, /history N reads them back --------------------
OUT2=$(CE_DLOG_PATH="$DLOG_PATH" printf '/history 10\n/quit\n' | CE_DLOG_PATH="$DLOG_PATH" "$CHAT" 2>&1)
assert_match "$OUT2" "dlog: $DLOG_PATH loaded [1-9][0-9]* prior entries" \
    "relaunched chat reports loaded entries"
# /history prints "#N kind action tier=... outcome=..." per entry; at minimum
# we expect the post-rehydrate output to contain at least one #0 row.
assert_match "$OUT2" "#0 " "history shows entry #0 after restart"

summary "scenario_a3_dlog"
