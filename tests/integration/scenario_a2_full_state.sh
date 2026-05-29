#!/usr/bin/env bash
# Scenario A2 -- Full-state durability across abrupt restart.
#
# Extends scenario_a (which only checks widget survives) to verify the
# Phase 11 follow-up: moments + (synapse strengths) + competence tier all
# round-trip through SIGKILL + /load. Feeds multiple messages to grow the
# moment stream, /saves, SIGKILLs, relaunches, /loads, and /status to read
# back the moment count.
#
# The synapse-strength probe is best-effort: the chat's route-and-inject
# path uses the gate but does not trigger Hebbian plasticity (no co-fire
# events fire syn_learn_one in the chat's path), so the live syn count
# stays at 0 -- the durability check is that the count survives as 0 (i.e.
# the section parses and applies cleanly). The unit tests in
# tests/unit/test_snapshot_synapses.nova cover the populated-graph
# round-trip directly.

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0

SNAP_PATH="/tmp/ce_int_scenario_a2.snap"
DLOG_PATH="/tmp/ce_int_scenario_a2.dlog"
trap 'rm -f "$SNAP_PATH" "$SNAP_PATH.tmp" "$DLOG_PATH" /tmp/ce_int_fifo_a2' EXIT
rm -f "$SNAP_PATH" "$SNAP_PATH.tmp" "$DLOG_PATH"

export CE_SNAP_PATH="$SNAP_PATH"
export CE_DLOG_PATH="$DLOG_PATH"

it_section "scenario A2: full-state durability (episodic + synapses + selfmodel)"

# --- step 1: build state via /teach + a few messages -----------------------
mkfifo /tmp/ce_int_fifo_a2
( "$CHAT" </tmp/ce_int_fifo_a2 >/tmp/ce_int_chat_a2.out 2>&1 ) &
CHAT_PID=$!
exec 9>/tmp/ce_int_fifo_a2
sleep 0.5
echo "/teach widget"        >&9
sleep 0.3
echo "/teach gadget"        >&9
sleep 0.3
echo "widget"               >&9
sleep 0.3
echo "widget gadget"        >&9
sleep 0.3
echo "widget gadget fever"  >&9
sleep 0.3
echo "fever infection"      >&9
sleep 0.3
echo "/save"                >&9
sleep 1.5
kill -9 "$CHAT_PID" 2>/dev/null
wait "$CHAT_PID" 2>/dev/null || true
exec 9>&-
rm -f /tmp/ce_int_fifo_a2

OUT1=$(cat /tmp/ce_int_chat_a2.out 2>/dev/null || true)
rm -f /tmp/ce_int_chat_a2.out

assert_match "$OUT1" "ingested 'widget'" "teach widget acknowledged"
assert_match "$OUT1" "ingested 'gadget'" "teach gadget acknowledged"
assert_match "$OUT1" "moment\\(s\\)" "save line mentions moments"
assert_file_exists "$SNAP_PATH" "snapshot file exists post-SIGKILL"

# Extract the moment count reported on save (text like "+ 4 moment(s)").
SAVED_MOMENTS=$(echo "$OUT1" | grep -oE '\+ [0-9]+ moment\(s\)' | head -1 | grep -oE '[0-9]+')
[ -n "$SAVED_MOMENTS" ] && [ "$SAVED_MOMENTS" -gt 0 ] && PASS=$((PASS+1)) \
    || { FAIL=$((FAIL+1)); echo "FAIL: expected >0 moments saved, got '$SAVED_MOMENTS'"; }

# --- step 2: relaunch, /load, /status; check moments restored ---------------
OUT2=$(printf '/load\n/status\n/quit\n' | "$CHAT" 2>&1)

assert_match "$OUT2" "loaded $SNAP_PATH" "load reports the snapshot file"
assert_match "$OUT2" "moment\\(s\\) \\+ [0-9]+ episode\\(s\\) restored" "load reports moments + episodes restored"
assert_match "$OUT2" "synapses: [0-9]+ edge\\(s\\) restored" "load reports synapse edges restored"
assert_match "$OUT2" "selfmodel: [0-9]+ competence record\\(s\\) restored" "load reports selfmodel records restored"

# The /status line `moments  : N moment(s), M episode(s)` must match the saved
# moment count.
RESTORED_MOMENTS=$(echo "$OUT2" | grep -oE 'moments  : [0-9]+ moment' | head -1 | grep -oE '[0-9]+')
assert_eq "$RESTORED_MOMENTS" "$SAVED_MOMENTS" "moment count survives SIGKILL + /load"

# /status should also report the moments/synapses/selfmodel lines verbatim.
assert_match "$OUT2" "moments  : " "/status emits moments line"
assert_match "$OUT2" "synapses : " "/status emits synapses line"
assert_match "$OUT2" "selfmodel: " "/status emits selfmodel line"

# Knowledge count must survive too (overlaps with scenario_a but verifies
# the full-state load doesn't regress the KGS rehydrate).
assert_match "$OUT2" "knowledge: [0-9]+ atoms" "/status reports knowledge atom count"
KNOWLEDGE=$(echo "$OUT2" | grep -oE 'knowledge: [0-9]+ atoms' | head -1 | grep -oE '[0-9]+')
[ -n "$KNOWLEDGE" ] && [ "$KNOWLEDGE" -ge 574 ] && PASS=$((PASS+1)) \
    || { FAIL=$((FAIL+1)); echo "FAIL: expected knowledge >=574 atoms post-load, got '$KNOWLEDGE'"; }

# The widget and gadget concepts must perceive cleanly after reload.
OUT3=$(printf '/load\nwidget gadget\n/quit\n' | "$CHAT" 2>&1)
assert_match "$OUT3" "perceive\\(m=[1-9][0-9]*,unk=0\\)" "widget + gadget perceived after reload"

summary "scenario_a2_full_state"
