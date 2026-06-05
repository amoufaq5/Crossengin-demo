#!/usr/bin/env bash
# Failure mode -- /load on a truncated snapshot reports a clear error and the
# running session is unaffected.
#
# Steps:
#   1. Build a real, valid snapshot via /save.
#   2. Truncate it at byte 100 (mid-header, before the KGS section).
#   3. Boot a fresh chat, teach a word, then /load the truncated file.
#   4. Assert (load FAILED ...) is printed.
#   5. The previously taught word must still be perceivable (the running
#      session was NOT clobbered by the failed load).

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0

SNAP=/tmp/ce_int_truncsnap_$$.snap
trap 'rm -f "$SNAP" "$SNAP.tmp"' EXIT
rm -f "$SNAP" "$SNAP.tmp"

it_section "failmode: /load on truncated snapshot keeps running session intact"

# --- Step 1: write a good snapshot. ---------------------------------------
OUT_SAVE=$(run_chat "/save $SNAP")
assert_match "$OUT_SAVE" "saved soul=.*-> $SNAP durably" "baseline /save succeeded"
assert_file_exists "$SNAP" "baseline snapshot present"
ORIG_SIZE=$(stat -c '%s' "$SNAP" 2>/dev/null || echo 0)
if [ "$ORIG_SIZE" -gt 200 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  snapshot is at least 200 bytes (got %s) so truncating to 100 is meaningful\n" "$ORIG_SIZE"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  snapshot too small to truncate meaningfully: %s bytes\n" "$ORIG_SIZE"
fi

# --- Step 2: truncate at byte 100. ----------------------------------------
# Use dd to clamp the file to 100 bytes -- portable to bash without GNU truncate.
dd if="$SNAP" of="$SNAP.trunc" bs=1 count=100 status=none 2>/dev/null
mv "$SNAP.trunc" "$SNAP"
NEW_SIZE=$(stat -c '%s' "$SNAP" 2>/dev/null || echo -1)
assert_eq "$NEW_SIZE" "100" "snapshot truncated to exactly 100 bytes"

# --- Step 3 & 4: try to load it inside a session that has taught widget. -
# Use a FIFO so we can drive teach -> load -> widget interactively and have
# the post-load query reach the SAME chat process.
mkfifo /tmp/ce_int_truncfifo_$$
( "$CHAT" </tmp/ce_int_truncfifo_$$ >/tmp/ce_int_truncchat_$$.out 2>&1 ) &
CHAT_PID=$!
exec 9>/tmp/ce_int_truncfifo_$$
sleep 0.5
echo "/teach widget" >&9
sleep 0.4
echo "/load $SNAP"   >&9
sleep 0.6
# Query widget AFTER the failed load -- it must still be recognized.
echo "widget"        >&9
sleep 0.5
echo "/quit"         >&9
wait "$CHAT_PID" 2>/dev/null || true
exec 9>&-
rm -f /tmp/ce_int_truncfifo_$$

OUT_RUN=$(cat /tmp/ce_int_truncchat_$$.out 2>/dev/null || true)
rm -f /tmp/ce_int_truncchat_$$.out

assert_match "$OUT_RUN" "ingested 'widget'" "pre-load teach acknowledged"
assert_match "$OUT_RUN" "load FAILED.*$SNAP" "/load on truncated file reports FAILED"
# The widget query must still hit (m>=1, unk=0) -- the failed load did NOT
# wipe the live KG.
PERCEIVES=$(echo "$OUT_RUN" | grep -oE "perceive\(m=[0-9]+,unk=[0-9]+\)")
# Look at the last perceive line (the widget query after the failed load).
LAST_PERCEIVE=$(echo "$PERCEIVES" | tail -1)
assert_match "$LAST_PERCEIVE" "perceive\\(m=[1-9][0-9]*,unk=0\\)" \
    "widget still perceived after failed /load (session unaffected)"

summary "failmode_corrupt_snap_recovery"
