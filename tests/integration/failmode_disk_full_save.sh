#!/usr/bin/env bash
# Failure mode -- /save to a write-denied path reports failure cleanly.
#
# We can't realistically exhaust /tmp in a sandbox, so we exercise the
# equivalent failure path: write to a path whose parent directory either
# (a) does not exist, or (b) exists but is read-only. Either way, the
# write_tmp -> rename pipeline must fail predictably, the chat must
# surface `(save FAILED: ...)`, and the chat process must stay alive to
# accept the next command.

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0

it_section "failmode: /save to write-denied path"

# Case 1: parent directory does not exist.
BAD1="/this_dir_does_not_exist_xyzqq/snap.snap"
OUT=$(run_chat "/save $BAD1
/status")
assert_match "$OUT" "save FAILED.*$BAD1" "/save reports FAILED on non-existent dir"
# The daemon must still respond to /status after the failed save.
assert_match "$OUT" "soul +: Aurora" "/status still works after save failure"

# Case 2: parent is read-only.
RO_DIR=/tmp/ce_int_ro_save_$$
mkdir -p "$RO_DIR"
chmod 0555 "$RO_DIR"
trap 'chmod 0755 "$RO_DIR" 2>/dev/null; rm -rf "$RO_DIR"' EXIT

# If running as root, the read-only chmod is ignored -- root can still write.
# Detect that and skip case 2 in that case (still pass the script).
if [ "$(id -u)" -eq 0 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}SKIP${C_RST}  running as root; chmod 0555 is bypassed -- read-only case skipped\n"
else
    BAD2="$RO_DIR/snap.snap"
    OUT2=$(run_chat "/save $BAD2
/status")
    assert_match "$OUT2" "save FAILED.*$BAD2" "/save reports FAILED on read-only dir"
    assert_match "$OUT2" "soul +: Aurora" "/status still works after read-only dir failure"
fi

# Case 3: After a failed save, a SUBSEQUENT save to a good path must succeed
# (no lingering state corruption). The same chat session would be ideal but
# run_chat spawns a fresh chat each call; we make the assertion across two
# back-to-back run_chats which is what the harness can express.
GOOD=/tmp/ce_int_save_recovery_$$.snap
rm -f "$GOOD"
trap 'chmod 0755 "$RO_DIR" 2>/dev/null; rm -rf "$RO_DIR" "$GOOD" "$GOOD.tmp"' EXIT
OUT3=$(run_chat "/save $BAD1
/save $GOOD")
assert_match "$OUT3" "save FAILED.*$BAD1" "first save (bad path) FAILED"
assert_match "$OUT3" "saved soul=.*-> $GOOD durably" "subsequent save (good path) succeeded"
assert_file_exists "$GOOD" "post-failure snapshot exists"

summary "failmode_disk_full_save"
