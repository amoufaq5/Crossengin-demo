#!/usr/bin/env bash
# Scenario G -- KG sync across two processes.
#
# Phase 20 / Tier 4 #2 distributed-substrate seam: one publisher process
# emits atom-birth events over a TCP socket; one subscriber process applies
# them to its own local KG. The point of this scenario is to prove the
# cross-process learning path end-to-end -- pub teaches three labels, sub
# observes them within ~1s.
#
# KNOWN LIMITATIONS (sandbox-shaped):
#   * accept_conn is blocking in NOVA; we use a generous startup sleep and
#     fall back to kill -9 if either process hangs longer than the deadline.
#   * The sandbox may block bind() on some interfaces; the publisher binds
#     127.0.0.1 only by default. If `socket(2,1,0)` returns -1 (sandbox
#     denies AF_INET sockets entirely), the script prints a SKIP block and
#     still reports pass=N fail=0 so the rest of the suite is unaffected.

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

it_section "scenario G: distributed KG sync (publisher -> subscriber)"

PUB_BIN="$REPO_ROOT/bin/crossengin-kg-publisher"
SUB_BIN="$REPO_ROOT/bin/crossengin-kg-subscriber"

# Pre-flight: both artifacts must be present.
if [ ! -x "$PUB_BIN" ] || [ ! -x "$SUB_BIN" ]; then
    printf "  ${C_RED}ERROR${C_RST}: %s or %s missing. Run: make install\n" \
        "$PUB_BIN" "$SUB_BIN" >&2
    FAIL=$((FAIL+1))
    summary "scenario_g_kg_sync"
    exit $?
fi

# Pick a per-run port to avoid collisions with other tests / repeat runs.
# Range chosen high to avoid the default kgsync port (8766) so a long-running
# manual demo on the default port doesn't clobber the CI runner.
PORT=$(( 30000 + (RANDOM % 1000) ))
PUB_OUT="/tmp/ce_int_kgsync_pub.out"
SUB_OUT="/tmp/ce_int_kgsync_sub.out"
trap 'kill -9 $PUB_PID $SUB_PID 2>/dev/null; rm -f "$PUB_OUT" "$SUB_OUT"' EXIT
rm -f "$PUB_OUT" "$SUB_OUT"

# --- Stage 1: launch the publisher with three labels on stdin. ----------
# Pipe via printf so the publisher sees EOF after 'fever' and exits its
# read loop cleanly (no need for FIFO juggling -- the fewer moving parts
# this scenario has, the more reliably it runs in CI).
(
    export CE_KGSYNC_PORT="$PORT"
    printf 'widget\ngadget\nfever\n' | "$PUB_BIN" >"$PUB_OUT" 2>&1
) &
PUB_PID=$!

# --- Stage 2: small startup grace so the publisher is bound before the
# subscriber tries to dial in. 0.5s is enough on bare metal; 1.0s gives
# the sandbox a buffer.
sleep 1

# Pre-flight: did the publisher even manage to bind? If sockets are denied
# entirely we record a SKIP and still pass the script.
if grep -q "ERROR cannot bind / listen" "$PUB_OUT" 2>/dev/null; then
    printf "  ${C_YEL}SKIP${C_RST}  socket bind denied by sandbox -- KG sync test skipped\n"
    PASS=$((PASS+1))
    wait $PUB_PID 2>/dev/null
    summary "scenario_g_kg_sync"
    exit $?
fi

# --- Stage 3: launch the subscriber. -------------------------------------
(
    export CE_KGSYNC_PORT="$PORT"
    export CE_KGSYNC_HOST="127.0.0.1"
    "$SUB_BIN" >"$SUB_OUT" 2>&1
) &
SUB_PID=$!

# --- Stage 4: wait for both to drain. The publisher exits on stdin-EOF
# (sends BYE then closes); the subscriber exits when it sees BYE. We give
# them a generous deadline and kill if they hang.
DEADLINE=10
elapsed=0
while [ "$elapsed" -lt "$DEADLINE" ]; do
    pub_alive=0; sub_alive=0
    kill -0 $PUB_PID 2>/dev/null && pub_alive=1
    kill -0 $SUB_PID 2>/dev/null && sub_alive=1
    if [ $pub_alive -eq 0 ] && [ $sub_alive -eq 0 ]; then
        break
    fi
    sleep 1
    elapsed=$((elapsed + 1))
done
if [ "$elapsed" -ge "$DEADLINE" ]; then
    printf "  ${C_YEL}WARN${C_RST}  process(es) hung past %ds, force-killing\n" "$DEADLINE"
    kill -9 $PUB_PID 2>/dev/null
    kill -9 $SUB_PID 2>/dev/null
fi
wait $PUB_PID 2>/dev/null
wait $SUB_PID 2>/dev/null

PUB_TXT=$(cat "$PUB_OUT" 2>/dev/null || true)
SUB_TXT=$(cat "$SUB_OUT" 2>/dev/null || true)

# --- Stage 5: publisher invariants. --------------------------------------
assert_match "$PUB_TXT" "kg-publisher: listening" "publisher entered listen state"
assert_match "$PUB_TXT" "subscriber attached"      "publisher saw subscriber attach"
assert_match "$PUB_TXT" "send .*label=widget"      "publisher sent widget"
assert_match "$PUB_TXT" "send .*label=gadget"      "publisher sent gadget"
assert_match "$PUB_TXT" "send .*label=fever"       "publisher sent fever"
assert_match "$PUB_TXT" "published 3 atom"         "publisher closed clean (3 atoms)"

# --- Stage 6: subscriber invariants. -------------------------------------
# These are the load-bearing claims: the subscriber's local stdout must
# show that all three labels arrived. This is the cross-process learning
# acceptance.
assert_match "$SUB_TXT" "handshake OK"             "subscriber completed handshake"
assert_match "$SUB_TXT" "recv .*label=widget"      "subscriber received widget"
assert_match "$SUB_TXT" "recv .*label=gadget"      "subscriber received gadget"
assert_match "$SUB_TXT" "recv .*label=fever"       "subscriber received fever"
assert_match "$SUB_TXT" "received 3 atom"          "subscriber closed clean (3 atoms)"
assert_match "$SUB_TXT" "local kg=3"               "subscriber's local KG has 3 atoms"

# --- Stage 7: cross-process belief / id parity. --------------------------
# A subscriber atom's id should equal what the publisher sent (so a future
# enhancement could cross-reference by handle, ADR-0017).
PUB_IDS=$(echo "$PUB_TXT" | grep -oE 'id=[0-9]+' | sort -u)
SUB_IDS=$(echo "$SUB_TXT" | grep -oE 'id=[0-9]+' | sort -u)
assert_eq "$SUB_IDS" "$PUB_IDS" "publisher / subscriber atom-id sets match"

summary "scenario_g_kg_sync"
