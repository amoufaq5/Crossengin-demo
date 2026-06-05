#!/usr/bin/env bash
# Scenario A -- Durability across abrupt restart.
#
# Boot fresh -> /teach widget -> /save -> SIGKILL -> relaunch -> /load ->
# ask "widget" -> verify perceive(m>=1,unk=0).
#
# This is the P11 acceptance test, now codified. The failure mode we guard
# against is "save claims success but a restart loses the atom." We force-kill
# (kill -9) instead of letting the process exit cleanly so the
# write_tmp -> fsync -> atomic_rename durability claim is actively exercised.

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0

# Clean slate.
SNAP_PATH="/tmp/ce_int_scenario_a.snap"
trap 'rm -f "$SNAP_PATH" "$SNAP_PATH.tmp" /tmp/ce_int_fifo_a' EXIT
rm -f "$SNAP_PATH" "$SNAP_PATH.tmp"

it_section "scenario A: durability across SIGKILL restart"

# --- step 1: boot a chat, teach widget, save, then SIGKILL ----------------
mkfifo /tmp/ce_int_fifo_a
( "$CHAT" </tmp/ce_int_fifo_a >/tmp/ce_int_chat_a.out 2>&1 ) &
CHAT_PID=$!
# Hold the write end open ourselves so the chat does not see EOF.
exec 9>/tmp/ce_int_fifo_a
# Give the chat a beat to print its banner.
sleep 0.5
echo "/teach widget"                 >&9
sleep 0.5
echo "/save $SNAP_PATH"              >&9
# Give the save time to complete before kill -9.
sleep 1.5
kill -9 "$CHAT_PID" 2>/dev/null
wait "$CHAT_PID" 2>/dev/null || true
exec 9>&-
rm -f /tmp/ce_int_fifo_a

OUT1=$(cat /tmp/ce_int_chat_a.out 2>/dev/null || true)
rm -f /tmp/ce_int_chat_a.out

assert_match "$OUT1" "ingested 'widget'" "teach widget acknowledged"
assert_match "$OUT1" "saved soul=.*-> $SNAP_PATH durably" "save reports durable write"
assert_file_exists "$SNAP_PATH" "snapshot file exists post-SIGKILL"

# --- step 2: also assert no orphan .tmp left behind -----------------------
if [ -f "$SNAP_PATH.tmp" ]; then
    assert_eq "tmp_present" "no_tmp" "no orphan snap.tmp left after kill"
else
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  %s\n" "no orphan snap.tmp left after kill"
fi

# --- step 3: capture checksum of the saved snap ---------------------------
CHK1=$(md5sum "$SNAP_PATH" 2>/dev/null | awk '{print $1}')
[ -n "$CHK1" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL: checksum unreadable"; }

# --- step 4: relaunch fresh, /load, ask widget ---------------------------
OUT2=$(printf '/load %s\nwidget\n/quit\n' "$SNAP_PATH" | "$CHAT" 2>&1)

assert_match "$OUT2" "loaded $SNAP_PATH" "load reports the snapshot file"
assert_match "$OUT2" "soul: name=" "soul rehydrated"
# widget must be comprehended -- m>=1 means at least one matched concept,
# unk=0 means none unknown. This is the load-bearing durability claim.
assert_match "$OUT2" "perceive\\(m=[1-9][0-9]*,unk=0\\)" "widget perceived after reload (m>=1, unk=0)"

# --- step 5: snapshot file unchanged by load (read-only operation) -------
CHK2=$(md5sum "$SNAP_PATH" 2>/dev/null | awk '{print $1}')
assert_eq "$CHK2" "$CHK1" "snapshot checksum unchanged by load"

summary "scenario_a_durability"
