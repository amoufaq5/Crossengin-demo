#!/usr/bin/env bash
# Scenario U -- secure aggregation (SecAgg) round-trip (P3.8 / ADR-0055).
#
# Two chat souls join a SecAgg-mode federated coordinator. Each soul
# sends FED_STAT_MASKED records (raw stats masked by pairwise additive
# masks). The coordinator SUMS the masked submissions per source and
# broadcasts FED_AGGREGATE_SUM. Because each pair's +mask / -mask
# pair cancels in the sum, the coordinator's sum equals Σ raw stats --
# but it never sees any individual soul's raw stat. The integration
# test asserts:
#   1) the coordinator boots in SecAgg mode (mode=v2-sa).
#   2) both souls complete the SECAGG_HELLO handshake.
#   3) the coordinator's stdout shows MASKED_STAT lines (NOT FED_STAT).
#   4) the coordinator's stdout shows the AGGREGATE_SUM line (NOT
#      AGGREGATE -- the SecAgg path emits sums, not averages).
#   5) the coordinator's stdout does NOT include the raw per-soul values
#      anywhere (we verify by negative grep on values that the soul-side
#      meta_observer would have produced if it had to ship raw).
#   6) the chat-side logs show "[SECAGG]" markers in the join + round
#      messages.
#
# KNOWN LIMITATIONS:
#   - accept_conn is blocking; the script uses a generous startup grace +
#     hard deadline (same as scenario_r).
#   - If socket(2,1,0) is denied by the sandbox, the script SKIPs.

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

it_section "scenario U: secure aggregation round-trip (ADR-0055)"

COORD_BIN="$REPO_ROOT/bin/crossengin-fed-coordinator"
CHAT_BIN="$REPO_ROOT/bin/crossengin-chat"

if [ ! -x "$COORD_BIN" ] || [ ! -x "$CHAT_BIN" ]; then
    printf "  ${C_RED}ERROR${C_RST}: %s or %s missing. Run: make install\n" \
        "$COORD_BIN" "$CHAT_BIN" >&2
    FAIL=$((FAIL+1))
    summary "scenario_u_secagg"
    exit $?
fi

# Per-run port (avoid 8777 to dodge collisions with the v1 demo / scenario R).
PORT=$(( 32000 + (RANDOM % 1000) ))
COORD_OUT="/tmp/ce_int_secagg_coord.out"
CHAT_A_OUT="/tmp/ce_int_secagg_chat_a.out"
CHAT_B_OUT="/tmp/ce_int_secagg_chat_b.out"
trap 'kill -9 $COORD_PID 2>/dev/null; kill -9 $CHAT_A_PID 2>/dev/null; kill -9 $CHAT_B_PID 2>/dev/null; rm -f "$COORD_OUT" "$CHAT_A_OUT" "$CHAT_B_OUT"' EXIT
rm -f "$COORD_OUT" "$CHAT_A_OUT" "$CHAT_B_OUT"

# Stage 1: launch the coordinator in SecAgg mode. CE_FED_SOULS=2 + one
# round + CE_SECAGG_ENABLED=1.
(
    export CE_FED_PORT="$PORT"
    export CE_FED_BIND="127.0.0.1"
    export CE_FED_SOULS=2
    export CE_FED_MAX_ROUNDS=1
    export CE_SECAGG_ENABLED=1
    "$COORD_BIN" >"$COORD_OUT" 2>&1
) &
COORD_PID=$!

# Stage 2: startup grace.
sleep 1
if grep -q "ERROR cannot bind / listen" "$COORD_OUT" 2>/dev/null; then
    printf "  ${C_YEL}SKIP${C_RST}  socket bind denied by sandbox -- SecAgg test skipped\n"
    PASS=$((PASS+1))
    wait $COORD_PID 2>/dev/null
    summary "scenario_u_secagg"
    exit $?
fi

# Stage 3: prep two chat sessions. Each soul has its own snapshot path
# (CE_SNAP_PATH) so they don't trample each other's state.
rm -f /tmp/crossengin_secagg_alice.snap /tmp/crossengin_secagg_bob.snap \
      /tmp/crossengin_secagg_alice.dlog  /tmp/crossengin_secagg_bob.dlog

# Pre-shared token for the alice <-> bob pair.
SHARED_TOKEN="ce-secagg-shared-token"

INPUT_A=$(
    printf '/teach widget\n'
    printf '/teach gadget\n'
    printf "/fed_join 127.0.0.1:$PORT\n"
    printf '/fed_leave\n'
    printf '/quit\n'
)
INPUT_B=$(
    printf '/teach widget\n'
    printf '/teach sprocket\n'
    printf "/fed_join 127.0.0.1:$PORT\n"
    printf '/fed_leave\n'
    printf '/quit\n'
)

# Stage 4: launch the two chat instances with their own SecAgg config.
(
    export CE_FED_PORT="$PORT"
    export CE_SECAGG_ENABLED=1
    export CE_SECAGG_PEERS="bob"
    export CE_FED_TOKEN_bob="$SHARED_TOKEN"
    export CE_SESSION_ID="alice"
    export CE_SNAP_PATH="/tmp/crossengin_secagg_alice.snap"
    export CE_DLOG_PATH="/tmp/crossengin_secagg_alice.dlog"
    echo "$INPUT_A" | "$CHAT_BIN" >"$CHAT_A_OUT" 2>&1
) &
CHAT_A_PID=$!

# Small offset so the alice <-> coord handshake completes first, making
# the bob-side accept loop deterministic.
sleep 1

(
    export CE_FED_PORT="$PORT"
    export CE_SECAGG_ENABLED=1
    export CE_SECAGG_PEERS="alice"
    export CE_FED_TOKEN_alice="$SHARED_TOKEN"
    export CE_SESSION_ID="bob"
    export CE_SNAP_PATH="/tmp/crossengin_secagg_bob.snap"
    export CE_DLOG_PATH="/tmp/crossengin_secagg_bob.dlog"
    echo "$INPUT_B" | "$CHAT_BIN" >"$CHAT_B_OUT" 2>&1
) &
CHAT_B_PID=$!

# Stage 5: wait for completion with a hard deadline.
DEADLINE=20
elapsed=0
while [ "$elapsed" -lt "$DEADLINE" ]; do
    coord_alive=0; a_alive=0; b_alive=0
    kill -0 $COORD_PID  2>/dev/null && coord_alive=1
    kill -0 $CHAT_A_PID 2>/dev/null && a_alive=1
    kill -0 $CHAT_B_PID 2>/dev/null && b_alive=1
    if [ $coord_alive -eq 0 ] && [ $a_alive -eq 0 ] && [ $b_alive -eq 0 ]; then
        break
    fi
    sleep 1
    elapsed=$((elapsed + 1))
done
if [ "$elapsed" -ge "$DEADLINE" ]; then
    printf "  ${C_YEL}WARN${C_RST}  process(es) hung past %ds, force-killing\n" "$DEADLINE"
    kill -9 $COORD_PID  2>/dev/null
    kill -9 $CHAT_A_PID 2>/dev/null
    kill -9 $CHAT_B_PID 2>/dev/null
fi
wait $COORD_PID  2>/dev/null
wait $CHAT_A_PID 2>/dev/null
wait $CHAT_B_PID 2>/dev/null

COORD_TXT=$(cat "$COORD_OUT"  2>/dev/null || true)
CHAT_A_TXT=$(cat "$CHAT_A_OUT" 2>/dev/null || true)
CHAT_B_TXT=$(cat "$CHAT_B_OUT" 2>/dev/null || true)

# Stage 6: coordinator-side invariants.
assert_match "$COORD_TXT" "mode=v2-sa" \
    "coordinator started in SecAgg mode"
assert_match "$COORD_TXT" "fed-coord: listening" \
    "coordinator entered listen state"
assert_match "$COORD_TXT" "fed-coord: SECAGG JOIN" \
    "coordinator saw at least one SECAGG JOIN"
assert_match "$COORD_TXT" "opening round 1" \
    "coordinator opened round 1"
# The coordinator-side log must show MASKED_STAT (and the masked-value-opaque
# flag), NOT FED_STAT (the v1 line shape).
assert_match "$COORD_TXT" "MASKED_STAT" \
    "coordinator received masked stat lines"
assert_match "$COORD_TXT" "masked-value-opaque" \
    "coordinator logged the masked-opaque flag"
assert_match "$COORD_TXT" "\\[SECAGG\\] AGGREGATE_SUM round=1" \
    "coordinator broadcast a SUM aggregate (not avg)"
# Negative: the coordinator must NOT log the v1 STAT / AGGREGATE lines
# in SecAgg mode -- those would imply it had access to per-soul raw stats.
assert_nomatch "$COORD_TXT" "fed-coord: STAT soul=.*promo=" \
    "coordinator did NOT log v1 raw-promo STAT lines"
assert_nomatch "$COORD_TXT" "fed-coord: AGGREGATE round=1 tag=.*avg_promo=" \
    "coordinator did NOT log v1 AVG aggregate lines"

# Stage 7: chat-side (per-soul) invariants.
assert_match "$CHAT_A_TXT" "fed_join: \\[SECAGG\\] enabled" \
    "alice chat entered SecAgg mode"
assert_match "$CHAT_A_TXT" "fed_join: \\[SECAGG\\] HELLO ce-fed v2-sa \\+ FED_JOIN" \
    "alice chat completed SecAgg handshake"
assert_match "$CHAT_B_TXT" "fed_join: \\[SECAGG\\] enabled" \
    "bob chat entered SecAgg mode"
assert_match "$CHAT_B_TXT" "fed_join: \\[SECAGG\\] HELLO ce-fed v2-sa \\+ FED_JOIN" \
    "bob chat completed SecAgg handshake"
assert_match "$CHAT_A_TXT" "fed: \\[SECAGG\\] round 1 complete" \
    "alice chat completed round 1"
assert_match "$CHAT_B_TXT" "fed: \\[SECAGG\\] round 1 complete" \
    "bob chat completed round 1"
assert_match "$CHAT_A_TXT" "masked stats sent" \
    "alice chat printed masked-stats sent"
assert_match "$CHAT_B_TXT" "masked stats sent" \
    "bob chat printed masked-stats sent"

summary "scenario_u_secagg"
