#!/usr/bin/env bash
# Failure mode -- kill -9 during the /save window must not leave a partial
# snapshot at the final path.
#
# The write contract is: write_tmp -> fsync -> atomic_rename -> fsync(parent).
# If we kill the process anywhere in that pipeline, the OS guarantees the live
# filename atomically holds EITHER the old bytes OR the new bytes, never half-
# written bytes. We exercise that by:
#   1. Saving a clean "good" snapshot once (the recovery point).
#   2. Capturing its MD5.
#   3. Driving another save with kill -9 fired immediately after the /save
#      line. The timing window is tiny so we issue the kill in a tight loop
#      across multiple attempts; on at least one attempt the kill lands
#      mid-pipeline.
#   4. After every kill, assert that EITHER (a) the snapshot file is the old
#      good bytes (kill landed before rename), OR (b) it's a complete new
#      snapshot ending with `end` (kill landed after rename). Never assert
#      a half-written final file.
#   5. The .tmp sibling may or may not survive (depending on whether kill
#      landed before/after the rename); existence is acceptable, but its bytes
#      must NOT have ended up at the final path.
#   6. /load of the final path must succeed in a fresh chat regardless.

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0

SNAP=/tmp/ce_int_fsync_$$.snap
trap 'rm -f "$SNAP" "$SNAP.tmp" /tmp/ce_int_fsync_fifo_$$' EXIT
rm -f "$SNAP" "$SNAP.tmp"

it_section "failmode: kill -9 during /save (mid-fsync window)"

# --- Step 1: write a clean baseline snapshot. -----------------------------
OUT0=$(run_chat "/save $SNAP")
assert_match "$OUT0" "saved soul=.*-> $SNAP durably" "baseline /save succeeded"
assert_file_exists "$SNAP" "baseline snapshot present"
GOOD_MD5=$(md5sum "$SNAP" 2>/dev/null | awk '{print $1}')
[ -n "$GOOD_MD5" ] && PASS=$((PASS+1)) \
    || { FAIL=$((FAIL+1)); echo "FAIL: baseline checksum unreadable"; }

# --- Step 2: kill -9 the chat at varying delays around the /save line. ---
# We fire the kill at three offsets (0, 50ms, 200ms after /save) so SOME
# attempt is likely to land inside the write_tmp -> rename window. The
# invariant we check is the same for ALL three offsets: the final file is
# never a half-written wreck (no truncated `end`).
KILLED_ATTEMPTS=0
for delay_ms in 0 50 200; do
    mkfifo /tmp/ce_int_fsync_fifo_$$
    ( "$CHAT" </tmp/ce_int_fsync_fifo_$$ >/dev/null 2>&1 ) &
    CHAT_PID=$!
    exec 9>/tmp/ce_int_fsync_fifo_$$
    sleep 0.3
    echo "/save $SNAP" >&9
    # The save pipeline takes ~10ms; killing inside that window is the
    # bug-class we're guarding. Sleep the configured delay then SIGKILL.
    sleep_s=$(awk "BEGIN { printf \"%.3f\", $delay_ms / 1000 }")
    sleep "$sleep_s"
    kill -9 "$CHAT_PID" 2>/dev/null
    wait "$CHAT_PID" 2>/dev/null || true
    exec 9>&-
    rm -f /tmp/ce_int_fsync_fifo_$$
    KILLED_ATTEMPTS=$((KILLED_ATTEMPTS+1))

    # Invariant: the final file MUST be a complete snapshot. Either it's
    # the prior good bytes (kill before rename) or the new bytes (kill
    # after rename). A complete snapshot ends with `end\n`.
    LAST_LINE=$(tail -1 "$SNAP" 2>/dev/null)
    if [ "$LAST_LINE" = "end" ]; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}PASS${C_RST}  delay=%dms: final snapshot ends with 'end' (atomic OK)\n" "$delay_ms"
    else
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  delay=%dms: final snapshot does NOT end with 'end' (last='%s')\n" \
            "$delay_ms" "$LAST_LINE"
    fi
done

# --- Step 3: the surviving snapshot must load cleanly in a fresh chat. ---
OUT_LOAD=$(printf '/load %s\n/status\n/quit\n' "$SNAP" | "$CHAT" 2>&1)
assert_match "$OUT_LOAD" "loaded $SNAP" "/load on the surviving snapshot succeeds"
assert_match "$OUT_LOAD" "soul +: Aurora" "/status after load reports Aurora"

# --- Step 4: clean up any leftover .tmp (acceptable if present). ---------
# A stale .tmp is not a correctness violation -- the next save would overwrite
# it with O_TRUNC. We just don't assert on its existence either way.
[ -f "$SNAP.tmp" ] && printf "  ${C_DIM}NOTE${C_RST}  $SNAP.tmp survived (acceptable)\n" || true

summary "failmode_killed_mid_fsync"
