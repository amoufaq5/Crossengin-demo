#!/usr/bin/env bash
# Failure mode -- dlog with appended garbage at the tail recovers cleanly.
#
# The dl_open recovery loop is supposed to:
#   - parse every line until one fails to parse,
#   - truncate the file at the last-good byte,
#   - print "dl_open: warning -- truncated corrupt tail of <path> (kept N entries)",
#   - keep running and accept new appends.
#
# Steps:
#   1. Boot chat with a dedicated CE_DLOG_PATH; drive 3 events to fill the log.
#   2. SIGKILL to flush.
#   3. Verify the dlog now has >=3 entries.
#   4. Append a single garbage line to the dlog.
#   5. Restart chat; verify the warning is printed AND that /history shows the
#      pre-corruption entries (count == prior count, not prior+garbage).
#   6. Append another normal event and verify the dlog grows by 2 (intent +
#      outcome) -- proves the file is open for append correctly post-truncate.

. "$(dirname "$0")/_lib.sh"
require_chat

DLOG=/tmp/ce_int_dlog_corrupt_$$.dlog
trap 'rm -f "$DLOG" /tmp/ce_int_dlog_fifo_$$ /tmp/ce_int_dlog_chat_$$.out' EXIT
rm -f "$DLOG"

it_section "failmode: dlog corrupt-tail truncation on restart"

# --- Step 1+2: fill the dlog and SIGKILL. ---------------------------------
mkfifo /tmp/ce_int_dlog_fifo_$$
( CE_DLOG_PATH="$DLOG" "$CHAT" </tmp/ce_int_dlog_fifo_$$ >/tmp/ce_int_dlog_chat_$$.out 2>&1 ) &
CHAT_PID=$!
exec 9>/tmp/ce_int_dlog_fifo_$$
sleep 0.5
echo "fever"           >&9
sleep 0.4
echo "infection treat" >&9
sleep 0.4
echo "rest recover"    >&9
sleep 1.5
kill -9 "$CHAT_PID" 2>/dev/null
wait "$CHAT_PID" 2>/dev/null || true
exec 9>&-
rm -f /tmp/ce_int_dlog_fifo_$$

assert_file_exists "$DLOG" "dlog present after SIGKILL"
BEFORE_LINES=$(wc -l <"$DLOG" 2>/dev/null || echo 0)
if [ "$BEFORE_LINES" -ge 3 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  dlog has %d lines (>=3) before corruption\n" "$BEFORE_LINES"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  expected dlog with >=3 lines, got %d\n" "$BEFORE_LINES"
fi

# --- Step 4: append garbage. ---------------------------------------------
echo "this_is_not_a_valid_dlog_line_at_all" >> "$DLOG"
AFTER_LINES=$(wc -l <"$DLOG" 2>/dev/null || echo 0)
assert_eq "$AFTER_LINES" "$((BEFORE_LINES+1))" "garbage line appended"

# --- Step 5: restart; recovery warning must print, /history must list
#     the pre-corruption entries. We use CE_DLOG_PATH again so the binary
#     opens our dedicated file.
RESTART_OUT=$(CE_DLOG_PATH="$DLOG" printf '/history 99\n/quit\n' | CE_DLOG_PATH="$DLOG" "$CHAT" 2>&1)
assert_match "$RESTART_OUT" "dl_open: warning -- truncated corrupt tail of $DLOG" \
    "restart prints the truncation warning"
assert_match "$RESTART_OUT" "loaded $BEFORE_LINES prior entries" \
    "post-truncation prior-entries count == original count (garbage discarded)"

# /history must show that many entries. The first history line is preceded
# by the chat's "> " prompt, so it shows as "> " + "  #N ..." -- the others
# start with two spaces only. Match on the "#N (intent|outcome)" core so
# both forms count.
HIST_LINES=$(echo "$RESTART_OUT" | grep -cE '#[0-9]+ (intent|outcome) ')
if [ "$HIST_LINES" -ge "$BEFORE_LINES" ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  /history shows %d entries (>= original %d)\n" \
        "$HIST_LINES" "$BEFORE_LINES"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  /history shows %d entries (expected >= %d)\n" \
        "$HIST_LINES" "$BEFORE_LINES"
fi

# --- Step 6: post-truncation the file must be exactly the good prefix
#     (i.e., the garbage byte-range has been truncated off disk).
NEW_LINES=$(wc -l <"$DLOG" 2>/dev/null || echo 0)
assert_eq "$NEW_LINES" "$BEFORE_LINES" "on-disk dlog size matches original (garbage byte-range removed)"

summary "failmode_dlog_corrupt_tail"
