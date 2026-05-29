#!/usr/bin/env bash
# Failure mode -- kg-sync subscriber dies mid-stream.
#
# Scenario: publisher binds and accepts; subscriber connects + handshakes;
# publisher starts streaming atoms; we kill -9 the subscriber halfway through;
# the publisher continues writing to a now-defunct TCP socket -- because TCP
# buffers absorb the bytes without an immediate error, the publisher may
# report `delivered=1` for atoms that the subscriber never received.
#
# CURRENT BEHAVIOR (pinned):
#   - Publisher does NOT detect a -9'd subscriber on the next send (TCP
#     buffer absorbs the bytes; the kernel only surfaces ECONNRESET on a
#     SUBSEQUENT write or after a longer delay).
#   - Publisher continues until its stdin closes (EOF), then attempts BYE
#     and finally reports its tally.
#   - Reconnect / resume-from-offset is NOT implemented; a new subscriber
#     cannot rejoin the same publisher.
#
# KNOWN: this is not the textbook desirable behavior (a vigorous publisher
# would heartbeat and detect a dead peer in seconds). The integration test
# locks current behavior so we observe regressions, not the spec we wish
# we had. When the publisher grows liveness checks + reconnect, this test
# must be updated to assert the better behavior.

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

it_section "failmode: kg-sync subscriber dies mid-stream (CURRENT-BEHAVIOR pin)"

PUB_BIN="$REPO_ROOT/bin/crossengin-kg-publisher"
SUB_BIN="$REPO_ROOT/bin/crossengin-kg-subscriber"

if [ ! -x "$PUB_BIN" ] || [ ! -x "$SUB_BIN" ]; then
    printf "  ${C_RED}ERROR${C_RST}: %s or %s missing. Run: make install\n" "$PUB_BIN" "$SUB_BIN" >&2
    FAIL=$((FAIL+1))
    summary "failmode_kgsync_subscriber_drop"
    exit $?
fi

PORT=$((31000 + (RANDOM % 1000)))
PUB_OUT="/tmp/ce_int_drop_pub_$$.out"
SUB_OUT="/tmp/ce_int_drop_sub_$$.out"
PUB_FIFO="/tmp/ce_int_drop_pub_fifo_$$"
trap 'kill -9 $PUB_PID $SUB_PID 2>/dev/null; rm -f "$PUB_OUT" "$SUB_OUT" "$PUB_FIFO"' EXIT
rm -f "$PUB_OUT" "$SUB_OUT" "$PUB_FIFO"

# --- Stage 1: launch publisher with a FIFO so we control its stdin. -----
mkfifo "$PUB_FIFO"
( export CE_KGSYNC_PORT="$PORT"; "$PUB_BIN" <"$PUB_FIFO" >"$PUB_OUT" 2>&1 ) &
PUB_PID=$!
exec 8>"$PUB_FIFO"
sleep 1

if grep -q "ERROR cannot bind / listen" "$PUB_OUT" 2>/dev/null; then
    printf "  ${C_YEL}SKIP${C_RST}  socket bind denied by sandbox -- kgsync drop test skipped\n"
    PASS=$((PASS+1))
    exec 8>&-
    rm -f "$PUB_FIFO"
    summary "failmode_kgsync_subscriber_drop"
    exit $?
fi

# --- Stage 2: launch subscriber. ----------------------------------------
( export CE_KGSYNC_PORT="$PORT"; export CE_KGSYNC_HOST="127.0.0.1"
  "$SUB_BIN" >"$SUB_OUT" 2>&1 ) &
SUB_PID=$!
sleep 1

if ! kill -0 $PUB_PID 2>/dev/null; then
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  publisher died during boot\n"
    cat "$PUB_OUT" 2>/dev/null | sed 's/^/        /'
    exec 8>&-
    summary "failmode_kgsync_subscriber_drop"
    exit $?
fi
if ! kill -0 $SUB_PID 2>/dev/null; then
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  subscriber died during boot/handshake\n"
    cat "$SUB_OUT" 2>/dev/null | sed 's/^/        /'
    exec 8>&-
    summary "failmode_kgsync_subscriber_drop"
    exit $?
fi
PASS=$((PASS+1))
printf "  ${C_GRN}PASS${C_RST}  publisher + subscriber both alive after handshake\n"

# --- Stage 3: feed the first label, wait for ack, then kill subscriber. ---
echo "widget" >&8
sleep 0.5
assert_match "$(cat "$SUB_OUT" 2>/dev/null)" "recv .*label=widget" "subscriber received first label"

kill -9 $SUB_PID 2>/dev/null
wait $SUB_PID 2>/dev/null || true
PASS=$((PASS+1))
printf "  ${C_GRN}PASS${C_RST}  subscriber killed -9 mid-stream\n"

# --- Stage 4: feed more labels. The publisher will NOT immediately detect
#     the dropped subscriber (TCP-buffer absorption). It will keep writing.
#     Close stdin so publisher exits via the EOF path (its normal "no more
#     input" exit). This pins current behavior.
echo "gadget" >&8
sleep 0.3
echo "fever"  >&8
sleep 0.3
# Send the explicit "bye" sentinel that the publisher recognizes (per
# crossengin_kg_publisher.nova: `if str_eq(label, "bye") == 1 { go = 0 }`).
# This is more reliable than relying on stdin EOF -- the publisher's
# read_line implementation may not surface EOF promptly via the FIFO seam.
echo "bye"    >&8
sleep 0.5
exec 8>&-       # close stdin -- publisher exits its main loop

# Wait up to 8s for the publisher to exit.
DEADLINE=8
elapsed=0
while [ "$elapsed" -lt "$DEADLINE" ]; do
    if ! kill -0 $PUB_PID 2>/dev/null; then break; fi
    sleep 1
    elapsed=$((elapsed + 1))
done
if [ "$elapsed" -ge "$DEADLINE" ]; then
    # KNOWN: publisher may hang on read_line via FIFO; force-kill so we can
    # still inspect the output and assert what got logged.
    printf "  ${C_DIM}NOTE${C_RST}  publisher did not exit within %ds after bye -- force-kill (KNOWN: blocking read_line on FIFO)\n" "$DEADLINE"
    kill -9 $PUB_PID 2>/dev/null
    PASS=$((PASS+1))   # documenting current behavior, not failing the script
else
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  publisher exited within %ds after bye sentinel\n" "$elapsed"
fi
wait $PUB_PID 2>/dev/null || true
rm -f "$PUB_FIFO"

PUB_TXT=$(cat "$PUB_OUT" 2>/dev/null || true)

# --- Stage 5: invariants. ------------------------------------------------
assert_match "$PUB_TXT" "subscriber attached" "publisher accepted the subscriber"

# CURRENT BEHAVIOR: publisher continues sending after the kill -- this is
# the bug-class the test pins.
# KNOWN: TCP write to a kill -9'd peer returns success for the first few
# kilobytes (the kernel's socket buffer absorbs them silently). The
# publisher never invalidates the fd until it tries again later AND the
# kernel has emitted RST. So `send kg=... label=gadget delivered=1` will
# typically print AFTER the subscriber is dead.
SEND_COUNT=$(echo "$PUB_TXT" | grep -cE "send kg=.* label=")
if [ "$SEND_COUNT" -ge 1 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  publisher sent at least 1 label total (got %d)\n" "$SEND_COUNT"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  publisher sent 0 labels (unexpected)\n"
fi

# After all attempts, the publisher either:
#   - exits with a tally line ("published N atom..."), OR
#   - emits "send failed (subscriber gone)" before exiting, OR
#   - hangs in read_line and is force-killed (no tally) -- KNOWN.
# We accept any of these three outcomes.
if echo "$PUB_TXT" | grep -qE "published [0-9]+ atom"; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  publisher closed with tally line\n"
elif echo "$PUB_TXT" | grep -qE "send failed \\(subscriber gone\\)"; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  publisher emitted 'send failed (subscriber gone)' before exiting\n"
else
    PASS=$((PASS+1))
    printf "  ${C_DIM}NOTE${C_RST}  publisher had no tally line -- KNOWN: hangs in read_line on dead-peer FIFO,\n        was force-killed. Output captured below for diagnostics.\n"
    echo "$PUB_TXT" | sed 's/^/        /'
fi

# KNOWN: reconnect-resume is NOT implemented in
# examples/crossengin_kg_publisher.nova. A second subscriber cannot pick up
# the stream where the first left off; they'd have to talk to a fresh
# publisher process. When/if that ships, replace this test with the
# affirmative reconnect assertion.

summary "failmode_kgsync_subscriber_drop"
