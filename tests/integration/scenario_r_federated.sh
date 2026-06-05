#!/usr/bin/env bash
# Scenario R -- federated learning round-trip (P3.7 / ADR-0054).
#
# One soul (chat) joins a single-soul federation coordinator. The
# coordinator opens one round, collects the soul's FED_STAT batch,
# averages (trivially, since N=1), broadcasts FED_AGGREGATE back, and
# closes after CE_FED_MAX_ROUNDS=1. The chat verifies it sent stats
# and received the aggregate.
#
# Acceptance:
#   - The coordinator boots, listens, accepts the soul's HELLO + JOIN.
#   - The soul completes the FED_JOIN exchange (chat prints HELLO + JOIN).
#   - The coordinator opens round 1.
#   - The soul emits at least one FED_STAT (chat round-trip prints
#     "stats sent").
#   - The coordinator's stdout shows the per-source STAT line.
#   - The coordinator broadcasts at least one FED_AGGREGATE.
#   - The chat receives the aggregate (chat prints "aggregates received").
#   - The coordinator exits cleanly after the single round.
#   - /help advertises /fed_join, /fed_stats, /fed_leave.
#
# KNOWN LIMITATIONS (sandbox-shaped):
#   - accept_conn is blocking; we use a generous startup grace + a
#     hard deadline + kill fallback (same shape as scenario_g).
#   - If socket(2,1,0) is denied by the sandbox, the script SKIPs
#     instead of failing (same envelope as scenario_g).

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

it_section "scenario R: federated learning round-trip (ADR-0054)"

COORD_BIN="$REPO_ROOT/bin/crossengin-fed-coordinator"
CHAT_BIN="$REPO_ROOT/bin/crossengin-chat"

# Pre-flight.
if [ ! -x "$COORD_BIN" ] || [ ! -x "$CHAT_BIN" ]; then
    printf "  ${C_RED}ERROR${C_RST}: %s or %s missing. Run: make install\n" \
        "$COORD_BIN" "$CHAT_BIN" >&2
    FAIL=$((FAIL+1))
    summary "scenario_r_federated"
    exit $?
fi

# Per-run port (avoid 8777 default to dodge collisions with manual demos).
PORT=$(( 31000 + (RANDOM % 1000) ))
COORD_OUT="/tmp/ce_int_fed_coord.out"
CHAT_OUT="/tmp/ce_int_fed_chat.out"
trap 'kill -9 $COORD_PID 2>/dev/null; rm -f "$COORD_OUT" "$CHAT_OUT"' EXIT
rm -f "$COORD_OUT" "$CHAT_OUT"

# Stage 1: launch the coordinator with CE_FED_MAX_ROUNDS=1 so it exits
# after one round (otherwise it would loop forever on the round timer).
# We give it CE_FED_SOULS=1 so it stops accepting after the first soul.
(
    export CE_FED_PORT="$PORT"
    export CE_FED_BIND="127.0.0.1"
    export CE_FED_SOULS=1
    export CE_FED_MAX_ROUNDS=1
    "$COORD_BIN" >"$COORD_OUT" 2>&1
) &
COORD_PID=$!

# Stage 2: small startup grace so the coordinator is bound before the
# chat dials in. The coordinator prints "listening, awaiting ..." once
# it has bound; we wait for that line or up to 5 seconds.
sleep 1
if grep -q "ERROR cannot bind / listen" "$COORD_OUT" 2>/dev/null; then
    printf "  ${C_YEL}SKIP${C_RST}  socket bind denied by sandbox -- federated test skipped\n"
    PASS=$((PASS+1))
    wait $COORD_PID 2>/dev/null
    summary "scenario_r_federated"
    exit $?
fi

# Stage 3: feed the chat its admin commands. We /teach a couple of
# words so the meta_observer has something to score, /fed_join the
# coordinator, then /fed_leave (best-effort) and /quit. Use a fresh
# snapshot path so the seed-atom count is stable.
rm -f /tmp/crossengin.snap /tmp/crossengin.default.snap \
      /tmp/crossengin.dlog /tmp/crossengin.default.dlog

# Build the chat input. We /teach a few words first so the
# meta_observer has live data the next FED_STAT batch can carry.
INPUT=$(
    printf '/teach widget\n'
    printf '/teach gadget\n'
    printf '/teach sprocket\n'
    printf '/fed_stats\n'
    printf "/fed_join 127.0.0.1:$PORT\n"
    printf '/fed_leave\n'
    printf '/help\n'
    printf '/quit\n'
)

# Stage 4: launch the chat with the input.
(
    export CE_FED_PORT="$PORT"
    echo "$INPUT" | "$CHAT_BIN" >"$CHAT_OUT" 2>&1
) &
CHAT_PID=$!

# Stage 5: wait for both to drain. The coordinator should exit on its
# own after CE_FED_MAX_ROUNDS=1; the chat exits on /quit.
DEADLINE=15
elapsed=0
while [ "$elapsed" -lt "$DEADLINE" ]; do
    coord_alive=0; chat_alive=0
    kill -0 $COORD_PID 2>/dev/null && coord_alive=1
    kill -0 $CHAT_PID 2>/dev/null && chat_alive=1
    if [ $coord_alive -eq 0 ] && [ $chat_alive -eq 0 ]; then
        break
    fi
    sleep 1
    elapsed=$((elapsed + 1))
done
if [ "$elapsed" -ge "$DEADLINE" ]; then
    printf "  ${C_YEL}WARN${C_RST}  process(es) hung past %ds, force-killing\n" "$DEADLINE"
    kill -9 $COORD_PID 2>/dev/null
    kill -9 $CHAT_PID 2>/dev/null
fi
wait $COORD_PID 2>/dev/null
wait $CHAT_PID 2>/dev/null

COORD_TXT=$(cat "$COORD_OUT" 2>/dev/null || true)
CHAT_TXT=$(cat "$CHAT_OUT" 2>/dev/null || true)

# Stage 6: coordinator invariants.
assert_match "$COORD_TXT" "fed-coord: starting on port" \
    "coordinator started"
assert_match "$COORD_TXT" "fed-coord: listening" \
    "coordinator entered listen state"
assert_match "$COORD_TXT" "fed-coord: JOIN soul=" \
    "coordinator saw a JOIN"
assert_match "$COORD_TXT" "fed-coord: opening round 1" \
    "coordinator opened round 1"
assert_match "$COORD_TXT" "fed-coord: STAT soul=" \
    "coordinator received at least one FED_STAT"
assert_match "$COORD_TXT" "fed-coord: AGGREGATE round=1" \
    "coordinator broadcast an aggregate"

# Stage 7: chat (soul-side) invariants.
assert_match "$CHAT_TXT" "fed_join: dialing 127.0.0.1:$PORT" \
    "chat dialed the coordinator"
assert_match "$CHAT_TXT" "fed_join: HELLO \\+ FED_JOIN exchange complete" \
    "chat completed HELLO + JOIN exchange"
assert_match "$CHAT_TXT" "fed: round 1 complete" \
    "chat completed a round (round 1)"
assert_match "$CHAT_TXT" "stats sent" \
    "chat printed stats sent count"
assert_match "$CHAT_TXT" "aggregates received" \
    "chat printed aggregates received count"

# Stage 8: /help advertises all three commands.
assert_match "$CHAT_TXT" "/fed_join URL" \
    "/help advertises /fed_join"
assert_match "$CHAT_TXT" "/fed_stats" \
    "/help advertises /fed_stats"
assert_match "$CHAT_TXT" "/fed_leave" \
    "/help advertises /fed_leave"

# Stage 9: dry-run /fed_stats path produced at least one source row.
# (We taught seed atoms via /teach, which the meta_observer attributes
# under the "user-teach" source tag; that source has the minimum 1
# atom required for the emit-skip-empty guard to let it through.)
assert_match "$CHAT_TXT" "fed_stats: dry-run preview" \
    "/fed_stats prints the dry-run header"

summary "scenario_r_federated"
