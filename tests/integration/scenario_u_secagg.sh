#!/usr/bin/env bash
# Scenario U -- secure aggregation (SecAgg) protocol v3n-sa (P3.8 / ADR-0055,
# A1 interim fixes).
#
# Souls join a SecAgg-mode federated coordinator, mask their stats with
# pairwise masks and the coordinator publishes only the SUM. v3n-sa:
#   - SECAGG_PEER carries the peer id only; the pair token stays local.
#   - every soul sends a fresh SECAGG_NONCE that enters the mask KDF; the
#     coordinator relays the other souls' nonces and always ends with ACK 0.
#   - the coordinator persists its SecAgg round counter in the run dir.
#   - reconciliation is off by default: a dropout aborts the round.
#   - DH mode needs CE_SECAGG_ALLOW_WEAK_DH=1 (unauthenticated relay).
#
# Sub-scenarios (each with its own fresh CE_RUN_DIR under one mktemp dir):
#   U         two chat souls, token mode; coordinator wire log
#             (CE_FED_WIRE_LOG) shows no token anywhere, token-free
#             SECAGG_PEER, nonces sent + relayed, ACK 0; sums cancel.
#   U.parity  scripts/secagg_smoke_soul.py --selftest / --print-mask match
#             the fixed KDF vector pinned in test_secure_aggregation.nova.
#   U.leave   FED_LEAVE after a masked stat counts as a dropout (correct
#             reconciled sum with a second dropout).
#   U.round   the round counter persists: a second coordinator run in the
#             same run dir opens round 2; a corrupt, overflowing or
#             symlinked counter is fatal; a second coordinator on the same
#             run dir is refused (flock).
#   U.replay  two sessions with the same round id, tokens and values:
#             nonces and FED_STAT_MASKED shares differ, both sums correct.
#   U.r0      dropout with default env -> round ABORTED, no FED_DROPOUT,
#             no sum.
#   U.r1      coordinator allows recon but the survivors do not -> they
#             refuse, nothing reconciled, no sum.
#   U.r       dropout with CE_SECAGG_ALLOW_RECON=1 everywhere -> reconciled
#             sum of the survivors.
#   U.peerset handshake refusals: old HELLO, 3-field SECAGG_PEER, no nonce,
#             no peers, DH key without the weak-DH flag, duplicate soul id,
#             CE_FED_SOULS=1.
#   U.dh      DH without CE_SECAGG_ALLOW_WEAK_DH is refused by the chat;
#             with it (chats + coordinator) the round completes.
#   U.dh2048  same with the 2048-bit group -- slow, only when CE_IT_SLOW=1.
#
# Env: CE_IT_STRICT=1 (CI) turns every environment SKIP (socket bind
# denied, python3 missing) into a FAIL, so a broken environment cannot
# report green. CE_IT_SLOW=1 adds the U.dh2048 stage.
#
# KNOWN LIMITATIONS: accept_conn is blocking; every stage has a hard
# deadline and force-kills stragglers.

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0
STRICT="${CE_IT_STRICT:-0}"
SLOW="${CE_IT_SLOW:-0}"

it_section "scenario U: secure aggregation v3n-sa (ADR-0055 / A1)"

COORD_BIN="$REPO_ROOT/bin/crossengin-fed-coordinator"
CHAT_BIN="$REPO_ROOT/bin/crossengin-chat"
SOUL_HELPER="$REPO_ROOT/scripts/secagg_smoke_soul.py"

if [ ! -x "$COORD_BIN" ] || [ ! -x "$CHAT_BIN" ]; then
    printf "  ${C_RED}ERROR${C_RST}: %s or %s missing. Run: make install\n" \
        "$COORD_BIN" "$CHAT_BIN" >&2
    FAIL=$((FAIL+1))
    summary "scenario_u_secagg"
    exit $?
fi

SCEN_TMP="$(mktemp -d)"
chmod 700 "$SCEN_TMP"
PIDS=()
cleanup() {
    local p
    for p in "${PIDS[@]}"; do pkill -9 -P "$p" 2>/dev/null; kill -9 "$p" 2>/dev/null; done
    rm -rf "$SCEN_TMP"
}
trap cleanup EXIT

# An environment SKIP: never a PASS; a FAIL under CE_IT_STRICT=1.
skip() {
    if [ "$STRICT" = "1" ]; then
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  (strict) SKIP not allowed: %s\n" "$1"
    else
        printf "  ${C_YEL}SKIP${C_RST}  %s\n" "$1"
    fi
}

finish() { summary "scenario_u_secagg"; exit $?; }

# wait_all <deadline_s> <pid>... ; force-kills on deadline, returns 1 then.
wait_all() {
    local deadline="$1"; shift
    local elapsed=0 alive p
    while [ "$elapsed" -lt "$deadline" ]; do
        alive=0
        for p in "$@"; do kill -0 "$p" 2>/dev/null && alive=1; done
        [ "$alive" -eq 0 ] && break
        sleep 1
        elapsed=$((elapsed + 1))
    done
    local rc=0
    if [ "$elapsed" -ge "$deadline" ]; then
        # A hang is a failure (a coordinator or soul that never exits must
        # not pass just because its earlier output looked right).
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  process(es) hung past %ss, force-killed\n" "$deadline"
        for p in "$@"; do kill -9 "$p" 2>/dev/null; done
        rc=1
    fi
    for p in "$@"; do wait "$p" 2>/dev/null; done
    return $rc
}

# Per-stage files: $SCEN_TMP/<stage>/{run,coord.out,wire.log,...}
stage_dir() { mkdir -p "$SCEN_TMP/$1/run"; chmod 700 "$SCEN_TMP/$1" "$SCEN_TMP/$1/run"; echo "$SCEN_TMP/$1"; }

# start_coord <stage_dir> <port> <souls> [ENV=VAL ...] -> sets COORD_PID.
# The run dir (round counter) is <stage_dir>/run unless RUN_DIR overrides.
start_coord() {
    local d="$1" port="$2" souls="$3"; shift 3
    local run="${RUN_DIR:-$d/run}"
    (
        export CE_RUN_DIR="$run"
        export CE_FED_PORT="$port"
        export CE_FED_BIND="127.0.0.1"
        export CE_FED_SOULS="$souls"
        export CE_FED_MAX_ROUNDS=1
        export CE_SECAGG_ENABLED=1
        export CE_FED_WIRE_LOG="$d/wire.log"
        for kv in "$@"; do export "$kv"; done
        "$COORD_BIN" >>"$d/coord.out" 2>&1
        echo "coord-exit=$?" >>"$d/coord.out"
    ) &
    COORD_PID=$!
    PIDS+=("$COORD_PID")
}

# Returns 1 (and SKIPs) when the coordinator could not bind.
bind_ok() {
    local d="$1" what="$2"
    local i=0
    while [ $i -lt 20 ]; do
        grep -q "fed-coord: listening\|ERROR cannot bind\|FATAL" "$d/coord.out" 2>/dev/null && break
        sleep 0.25; i=$((i+1))
    done
    if grep -q "ERROR cannot bind / listen" "$d/coord.out" 2>/dev/null; then
        skip "socket bind denied by sandbox -- $what skipped"
        return 1
    fi
    return 0
}

# py_soul <outfile> [args...] -> sets PY_PID (python soul in background).
py_soul() {
    local out="$1"; shift
    python3 -I "$SOUL_HELPER" --host 127.0.0.1 "$@" >"$out" 2>&1 &
    PY_PID=$!
    PIDS+=("$PY_PID")
}

sums_plausible() {
    echo "$1" | grep -oE "sum_promo=-?[0-9]+ sum_atr=-?[0-9]+" \
        | awk -F'[= ]' '{ if ($2 < 0 || $2 > 2000 || $4 < 0 || $4 > 2000) print }' | wc -l
}

SHARED_TOKEN="ce-secagg-shared-token-u1"
SHARED_TOKEN2="ce-secagg-shared-token-u2"
PORT_BASE=$(( 32000 + (RANDOM % 900) * 4 ))
NEXT_PORT=$PORT_BASE
# Call as a plain command (not in $(...)), then read $NEXT_PORT.
next_port() { NEXT_PORT=$((NEXT_PORT + 1)); }

# chat_input <port> <second-topic>
chat_input() {
    printf '/teach widget\n/teach %s\n/cap grant network_send\n/fed_join 127.0.0.1:%s\n/fed_leave\n/quit\n' "$2" "$1"
}

# start_chat <stage_dir> <soul> <peer> <port> <topic> [ENV=VAL ...] -> CHAT_PID
start_chat() {
    local d="$1" soul="$2" peer="$3" port="$4" topic="$5"; shift 5
    local input; input="$(chat_input "$port" "$topic")"
    (
        export CE_RUN_DIR="$d/run_$soul"
        mkdir -p "$CE_RUN_DIR"; chmod 700 "$CE_RUN_DIR"
        export CE_SECAGG_ENABLED=1
        export CE_SECAGG_PEERS="$peer"
        export CE_SESSION_ID="$soul"
        export CE_FED_SOUL_ID="$soul"
        export CE_SNAP_PATH="$d/$soul.snap"
        export CE_DLOG_PATH="$d/$soul.dlog"
        for kv in "$@"; do export "$kv"; done
        echo "$input" | "$CHAT_BIN" >"$d/chat_$soul.out" 2>&1
    ) &
    CHAT_PID=$!
    PIDS+=("$CHAT_PID")
}

HAVE_PY=1
if [ ! -x "$SOUL_HELPER" ] || ! command -v python3 >/dev/null 2>&1; then HAVE_PY=0; fi

# ===========================================================================
# U: two chat souls, token mode, coordinator wire log.
# ===========================================================================
D=$(stage_dir u)
next_port; PORT=$NEXT_PORT
start_coord "$D" "$PORT" 2
CP=$COORD_PID
if bind_ok "$D" "SecAgg scenario"; then
    start_chat "$D" alice bob "$PORT" gadget "CE_FED_TOKEN_bob=$SHARED_TOKEN"
    CA=$CHAT_PID
    sleep 1
    start_chat "$D" bob alice "$PORT" sprocket "CE_FED_TOKEN_alice=$SHARED_TOKEN"
    CB=$CHAT_PID
    wait_all 30 "$CP" "$CA" "$CB"
    COORD_TXT=$(cat "$D/coord.out" 2>/dev/null || true)
    CHAT_A_TXT=$(cat "$D/chat_alice.out" 2>/dev/null || true)
    CHAT_B_TXT=$(cat "$D/chat_bob.out" 2>/dev/null || true)
    WIRE=$(cat "$D/wire.log" 2>/dev/null || true)

    assert_match "$COORD_TXT" "mode=v3n-sa \\(SecAgg; recon=off\\)" \
        "coordinator started in SecAgg v3n-sa mode, reconciliation off by default"
    assert_match "$COORD_TXT" "round-deadline-ms=5000" \
        "coordinator reports default 5000 ms round deadline"
    assert_match "$COORD_TXT" "fed-coord: SECAGG JOIN soul=alice peers=1" "coordinator joined alice"
    assert_match "$COORD_TXT" "fed-coord: SECAGG JOIN soul=bob peers=1" "coordinator joined bob"
    assert_match "$COORD_TXT" "relayed 2 SECAGG_NONCE line\\(s\\); ACK 0 sent to 2 soul" \
        "coordinator relayed both nonces and ended the relay with ACK 0"
    assert_match "$COORD_TXT" "round-counter=1 persisted" "coordinator persisted round 1 before opening it"
    assert_match "$COORD_TXT" "opening round 1" "coordinator opened round 1"
    assert_match "$COORD_TXT" "MASKED_STAT soul=.*masked-value-opaque" \
        "coordinator received masked stat lines"
    assert_match "$COORD_TXT" "\\[SECAGG\\] AGGREGATE_SUM round=1" \
        "coordinator broadcast a SUM aggregate (not avg)"
    assert_eq "$(sums_plausible "$COORD_TXT")" "0" "all SecAgg sums are plausible (masks cancelled)"
    assert_nomatch "$COORD_TXT" "fed-coord: STAT soul=.*promo=" \
        "coordinator did NOT log v1 raw-promo STAT lines"
    assert_nomatch "$COORD_TXT" "fed-coord: AGGREGATE round=1 tag=.*avg_promo=" \
        "coordinator did NOT log v1 AVG aggregate lines"
    # Wire log: what actually crossed the coordinator's sockets.
    assert_match "$WIRE" "C>S SECAGG_HELLO ce-fed v3n-sa$" "wire: souls sent the v3n-sa HELLO"
    assert_match "$WIRE" "S>C OK ce-fed v3n-sa protocol accepted$" "wire: exact v3n-sa OK reply"
    assert_match "$WIRE" "C>S SECAGG_PEER bob$" "wire: alice's SECAGG_PEER carries the id only"
    assert_match "$WIRE" "C>S SECAGG_PEER alice$" "wire: bob's SECAGG_PEER carries the id only"
    assert_nomatch "$WIRE" "SECAGG_PEER [^ ]+ [^ ]+" "wire: no 3-field (token-carrying) SECAGG_PEER"
    assert_nomatch "$WIRE" "$SHARED_TOKEN" "wire: the pair token never appears on the wire"
    assert_nomatch "$COORD_TXT$CHAT_A_TXT$CHAT_B_TXT" "$SHARED_TOKEN" \
        "the pair token appears in no coordinator or chat log"
    assert_match "$WIRE" "C>S SECAGG_NONCE alice [0-9a-f]{32}$" "wire: alice sent a 32-hex nonce"
    assert_match "$WIRE" "C>S SECAGG_NONCE bob [0-9a-f]{32}$" "wire: bob sent a 32-hex nonce"
    BOB_NONCE=$(echo "$WIRE" | sed -n 's/.*C>S SECAGG_NONCE bob \([0-9a-f]*\)$/\1/p' | head -1)
    assert_match "$WIRE" "S>C SECAGG_NONCE bob ${BOB_NONCE:-MISSING}$" \
        "wire: bob's nonce was relayed unchanged (to alice)"
    assert_eq "$(echo "$WIRE" | grep -c 'S>C ACK 0$')" "2" "wire: ACK 0 ended the relay for both souls"
    assert_match "$WIRE" "S>C FED_ROUND 1 " "wire: FED_ROUND 1 broadcast"
    if [ -f "$D/wire.log" ]; then
        assert_eq "$(stat -c %a "$D/wire.log")" "600" "wire log is mode 0600"
    else
        assert_eq "missing" "present" "wire log written"
    fi
    assert_eq "$(cat "$D/run/crossengin_fed_secagg_round" 2>/dev/null)" "1" "round counter file holds 1"
    assert_eq "$(stat -c %a "$D/run/crossengin_fed_secagg_round" 2>/dev/null)" "600" "round counter file is mode 0600"
    # Chat-side invariants.
    assert_match "$CHAT_A_TXT" "as soul=alice" "alice chat used soul id alice"
    assert_match "$CHAT_B_TXT" "as soul=bob" "bob chat used soul id bob"
    assert_match "$CHAT_A_TXT" "fed_join: \\[SECAGG\\] enabled .v3n-sa" "alice chat entered SecAgg v3n-sa mode"
    assert_match "$CHAT_A_TXT" "HELLO ce-fed v3n-sa \\+ FED_JOIN exchange complete, peers=1 nonces=1 recon=0" \
        "alice chat completed the v3n-sa handshake with bob's nonce"
    assert_match "$CHAT_B_TXT" "HELLO ce-fed v3n-sa \\+ FED_JOIN exchange complete, peers=1 nonces=1 recon=0" \
        "bob chat completed the v3n-sa handshake with alice's nonce"
    assert_match "$CHAT_A_TXT" "fed: \\[SECAGG\\] round 1 complete" "alice chat completed round 1"
    assert_match "$CHAT_B_TXT" "fed: \\[SECAGG\\] round 1 complete" "bob chat completed round 1"
fi

# ===========================================================================
# Python-soul stages.
# ===========================================================================
if [ "$HAVE_PY" -ne 1 ]; then
    skip "python3 or $SOUL_HELPER unavailable -- Python-soul stages skipped"
    finish
fi

it_section "scenario U.parity: Python mirror of the v3n-sa mask KDF"
PAR=$(python3 -I "$SOUL_HELPER" --selftest 2>&1)
assert_match "$PAR" "selftest parity .* OK$" "secagg_smoke_soul.py --selftest (fixed vector, symmetry, nonce sensitivity)"
PM=$(python3 -I "$SOUL_HELPER" --print-mask --soul-id alice --peer bob --token tok-ab \
    --nonce 00000000000000000000000000000001 --peer-nonce 00000000000000000000000000000002 \
    --round 1 --dim 0 --tag topic:test 2>&1)
assert_eq "$PM" "4135031036" "Python mask == the vector pinned in test_secure_aggregation.nova"

# py_pair_session <stage_dir> <port> -> alice(100,50) + bob(30,20)
py_pair_session() {
    local d="$1" port="$2"
    start_coord "$d" "$port" 2
    local cp=$COORD_PID
    bind_ok "$d" "Python pair session" || return 1
    py_soul "$d/alice.out" --soul-id alice --peer bob --token "$SHARED_TOKEN2" --port "$port" \
        --x-promo 100 --x-atr 50 --wire-log "$d/alice.wire"
    local pa=$PY_PID
    sleep 0.5
    py_soul "$d/bob.out" --soul-id bob --peer alice --token "$SHARED_TOKEN2" --port "$port" \
        --x-promo 30 --x-atr 20 --wire-log "$d/bob.wire"
    local pb=$PY_PID
    wait_all 25 "$cp" "$pa" "$pb"
    return 0
}

# ---------------------------------------------------------------------------
it_section "scenario U.round: persisted SecAgg round counter"
D=$(stage_dir round)
next_port
if RUN_DIR="$D/run" py_pair_session "$D" "$NEXT_PORT"; then
    T1=$(cat "$D/coord.out")
    assert_match "$T1" "opening round 1 " "first coordinator run opens round 1"
    assert_eq "$(cat "$D/run/crossengin_fed_secagg_round" 2>/dev/null)" "1" "counter holds 1 after the first run"
    : >"$D/coord.out"; : >"$D/wire.log"
    next_port
    RUN_DIR="$D/run" py_pair_session "$D" "$NEXT_PORT"
    T2=$(cat "$D/coord.out")
    W2=$(cat "$D/wire.log" 2>/dev/null || true)
    assert_match "$T2" "opening round 2 " "second coordinator process continues at round 2"
    assert_match "$W2" "S>C FED_ROUND 2 " "wire: FED_ROUND 2 broadcast"
    assert_match "$W2" "C>S FED_STAT_MASKED 2 topic:test " "Python soul parsed the round id from FED_ROUND"
    assert_match "$T2" "AGGREGATE_SUM round=2 tag=topic:test sum_promo=130 sum_atr=70 n_part=2" \
        "round-2 sum is correct"
    assert_eq "$(cat "$D/run/crossengin_fed_secagg_round" 2>/dev/null)" "2" "counter holds 2 after the second run"
    assert_nomatch "$W2" "$SHARED_TOKEN2" "wire: no token on the wire (Python souls)"
    # A corrupt counter is fatal (fail closed, never reset to round 1).
    printf 'garbage\n' >"$D/run/crossengin_fed_secagg_round"
    D3=$(stage_dir round_corrupt)
    next_port
    RUN_DIR="$D/run" start_coord "$D3" "$NEXT_PORT" 2
    wait_all 10 "$COORD_PID"
    TC=$(cat "$D3/coord.out")
    assert_match "$TC" "FATAL SecAgg round counter .* corrupt" "corrupt round counter is refused"
    assert_match "$TC" "coord-exit=70" "coordinator exits 70 on a corrupt counter"
    assert_nomatch "$TC" "opening round" "no round opened with a corrupt counter"
    # A counter too large for a NOVA int is fatal (it would wrap backwards).
    D4=$(stage_dir round_overflow)
    printf '9223372036854775807\n' >"$D4/run/crossengin_fed_secagg_round"
    next_port
    start_coord "$D4" "$NEXT_PORT" 2
    wait_all 10 "$COORD_PID"
    TO=$(cat "$D4/coord.out")
    assert_match "$TO" "FATAL SecAgg round counter .* out of range" "overflowing counter is refused"
    assert_match "$TO" "coord-exit=70" "coordinator exits 70 on an overflowing counter"
    # A symlink at the counter path is fatal, not "missing" (ELOOP), so the
    # counter cannot be silently reset to round 1.
    D5=$(stage_dir round_symlink)
    printf '5\n' >"$D5/target"
    ln -s "$D5/target" "$D5/run/crossengin_fed_secagg_round"
    next_port
    start_coord "$D5" "$NEXT_PORT" 2
    wait_all 10 "$COORD_PID"
    TS=$(cat "$D5/coord.out")
    assert_match "$TS" "FATAL cannot open SecAgg round counter .*errno 40" "symlinked counter is refused (ELOOP)"
    assert_match "$TS" "coord-exit=70" "coordinator exits 70 on a symlinked counter"
    # One coordinator per run dir: a second one on the same run dir refuses
    # to start while the first holds the lock.
    D6=$(stage_dir round_lock)
    next_port
    start_coord "$D6" "$NEXT_PORT" 2
    FIRST_PID=$COORD_PID
    sleep 1
    D7=$(stage_dir round_lock2)
    next_port
    RUN_DIR="$D6/run" start_coord "$D7" "$NEXT_PORT" 2
    wait_all 10 "$COORD_PID"
    TL=$(cat "$D7/coord.out")
    assert_match "$TL" "FATAL another coordinator is using this run dir" "second coordinator on one run dir is refused"
    assert_match "$TL" "coord-exit=70" "second coordinator exits 70"
    # FIRST_PID is the wrapper subshell; stop the coordinator it started too.
    pkill -P "$FIRST_PID" 2>/dev/null
    kill "$FIRST_PID" 2>/dev/null; wait "$FIRST_PID" 2>/dev/null
fi

# ---------------------------------------------------------------------------
it_section "scenario U.replay: same round id in two sessions -> different shares"
DA=$(stage_dir replay_a)
DB=$(stage_dir replay_b)
next_port; PORT_A=$NEXT_PORT
next_port; PORT_B=$NEXT_PORT
if py_pair_session "$DA" "$PORT_A" && py_pair_session "$DB" "$PORT_B"; then
    TA=$(cat "$DA/coord.out"); TB=$(cat "$DB/coord.out")
    assert_match "$TA" "opening round 1 " "session A opened round 1 (fresh run dir)"
    assert_match "$TB" "opening round 1 " "session B opened round 1 too (counter reset: worst case)"
    NA=$(grep -oE "^> SECAGG_NONCE alice [0-9a-f]{32}" "$DA/alice.wire" | head -1)
    NB=$(grep -oE "^> SECAGG_NONCE alice [0-9a-f]{32}" "$DB/alice.wire" | head -1)
    SA=$(grep -oE "^> FED_STAT_MASKED 1 topic:test [0-9]+ [0-9]+" "$DA/alice.wire" | head -1)
    SB=$(grep -oE "^> FED_STAT_MASKED 1 topic:test [0-9]+ [0-9]+" "$DB/alice.wire" | head -1)
    assert_match "$SA" "FED_STAT_MASKED 1" "session A: alice's share captured"
    assert_match "$SB" "FED_STAT_MASKED 1" "session B: alice's share captured"
    if [ -n "$SA" ] && [ "$SA" != "$SB" ]; then R=differ; else R=same; fi
    assert_eq "$R" "differ" "replayed round id: alice's masked shares differ between sessions"
    if [ -n "$NA" ] && [ "$NA" != "$NB" ]; then R=differ; else R=same; fi
    assert_eq "$R" "differ" "each session used a fresh nonce"
    assert_match "$TA" "AGGREGATE_SUM round=1 tag=topic:test sum_promo=130 sum_atr=70 n_part=2" "session A sum correct"
    assert_match "$TB" "AGGREGATE_SUM round=1 tag=topic:test sum_promo=130 sum_atr=70 n_part=2" "session B sum correct"
fi

# py_dropout_session <stage_dir> <port> <soul-recon 0|1> [coord ENV=VAL ...]
# alice(100,50) + carol(30,20) survive; bob drops after the relay.
py_dropout_session() {
    local d="$1" port="$2" srecon="$3"; shift 3
    start_coord "$d" "$port" 3 "$@"
    local cp=$COORD_PID
    bind_ok "$d" "dropout session" || return 1
    local env_recon=""
    [ "$srecon" = "1" ] && env_recon="CE_SECAGG_ALLOW_RECON=1"
    env $env_recon python3 -I "$SOUL_HELPER" --host 127.0.0.1 --mode survivor --soul-id alice \
        --peer bob,carol --token "$SHARED_TOKEN2" --port "$port" --x-promo 100 --x-atr 50 \
        --wire-log "$d/alice.wire" >"$d/alice.out" 2>&1 &
    local pa=$!; PIDS+=("$pa")
    env $env_recon python3 -I "$SOUL_HELPER" --host 127.0.0.1 --mode survivor --soul-id carol \
        --peer alice,bob --token "$SHARED_TOKEN2" --port "$port" --x-promo 30 --x-atr 20 \
        --wire-log "$d/carol.wire" >"$d/carol.out" 2>&1 &
    local pc=$!; PIDS+=("$pc")
    sleep 1
    py_soul "$d/bob.out" --mode dropout --soul-id bob --peer alice,carol --token "$SHARED_TOKEN2" --port "$port"
    local pb=$PY_PID
    wait_all 25 "$cp" "$pa" "$pc" "$pb"
    return 0
}

# ---------------------------------------------------------------------------
it_section "scenario U.r0: dropout with default env -> round aborted"
D=$(stage_dir r0)
next_port
if py_dropout_session "$D" "$NEXT_PORT" 0; then
    T=$(cat "$D/coord.out"); W=$(cat "$D/wire.log" 2>/dev/null || true)
    assert_match "$T" "mode=v3n-sa \\(SecAgg; recon=off\\)" "coordinator: reconciliation off"
    assert_match "$T" "fed-coord: DROPOUT soul=bob" "coordinator detected bob's dropout"
    assert_match "$T" "round 1 ABORTED: dropped=bob; reconciliation disabled" "round aborted (no reconciliation)"
    assert_nomatch "$W" "FED_DROPOUT" "wire: no FED_DROPOUT sent"
    assert_nomatch "$W" "FED_AGGREGATE_SUM" "wire: no sum published"
    assert_nomatch "$T" "AGGREGATE_SUM" "coordinator log: no sum"
    assert_match "$W" "S>C BYE$" "wire: session ended with BYE"
    assert_match "$(cat "$D/alice.out" "$D/carol.out")" "BYE before FED_AGGREGATE_SUM: round aborted" \
        "survivors saw the abort"
fi

# ---------------------------------------------------------------------------
it_section "scenario U.r1: coordinator allows recon, survivors refuse it"
D=$(stage_dir r1)
next_port
if py_dropout_session "$D" "$NEXT_PORT" 0 CE_SECAGG_ALLOW_RECON=1; then
    T=$(cat "$D/coord.out"); W=$(cat "$D/wire.log" 2>/dev/null || true)
    assert_match "$T" "recon=on" "coordinator: reconciliation on"
    assert_match "$W" "S>C FED_DROPOUT 1 bob$" "wire: FED_DROPOUT broadcast"
    S=$(cat "$D/alice.out" "$D/carol.out")
    assert_eq "$(echo "$S" | grep -c 'refusing reconciliation (CE_SECAGG_ALLOW_RECON not set)')" "2" \
        "both survivors refused reconciliation"
    assert_nomatch "$W" "FED_RECON_MASKED" "wire: no FED_RECON_MASKED sent"
    assert_nomatch "$T" "AGGREGATE_SUM" "no sum published"
fi

# ---------------------------------------------------------------------------
it_section "scenario U.r: dropout with CE_SECAGG_ALLOW_RECON=1 -> reconciled sum"
D=$(stage_dir r)
next_port
if py_dropout_session "$D" "$NEXT_PORT" 1 CE_SECAGG_ALLOW_RECON=1; then
    T=$(cat "$D/coord.out"); W=$(cat "$D/wire.log" 2>/dev/null || true)
    assert_match "$T" "mode=v3n-sa \\(SecAgg; recon=on\\)" "coordinator boots with reconciliation on"
    assert_match "$T" "fed-coord: SECAGG JOIN soul=bob" "coordinator accepted bob"
    assert_match "$T" "fed-coord: DROPOUT soul=bob" "coordinator detected bob's dropout"
    assert_match "$T" "FED_DROPOUT round=1 dropped=bob broadcast to survivors" \
        "coordinator broadcast FED_DROPOUT to survivors"
    assert_match "$T" "RECON_MASKED soul=alice" "coordinator received alice's reconciled stat"
    assert_match "$W" "C>S FED_RECON_MASKED 1 carol topic:test " "wire: carol's reconciled stat (soul id = sender)"
    assert_match "$T" "round 1 reconciled" "coordinator round 1 reconciled (recon path)"
    # alice + carol: promo 100 + 30, atr 50 + 20, from two participants.
    assert_match "$T" "AGGREGATE_SUM round=1 tag=topic:test sum_promo=130 sum_atr=70 n_part=2" \
        "coordinator sum equals alice + carol after bob's dropout (masks cancel)"
    assert_match "$(cat "$D/alice.out")" "FED_DROPOUT" "alice survivor saw FED_DROPOUT"
    assert_nomatch "$W" "$SHARED_TOKEN2" "wire: no token on the wire"
fi

# ---------------------------------------------------------------------------
it_section "scenario U.leave: FED_LEAVE after a masked stat is a dropout"
# 4 souls with reconciliation opted in: carol sends her masked stat and then
# FED_LEAVE instead of ACK; bob drops after the relay. Both must be treated
# as dropped, so the reconciled sum is exactly alice + dave (100+30, 50+20).
# Before the fix carol's masks with the survivors were never stripped and
# the published sum was wrong.
D=$(stage_dir leave)
next_port
start_coord "$D" "$NEXT_PORT" 4 CE_SECAGG_ALLOW_RECON=1
CL=$COORD_PID
if bind_ok "$D" "leave session"; then
    for spec in "alice:100:50:bob,carol,dave" "dave:30:20:alice,bob,carol"; do
        IFS=: read -r sid xp xa peers <<<"$spec"
        CE_SECAGG_ALLOW_RECON=1 python3 -I "$SOUL_HELPER" --host 127.0.0.1 --mode survivor \
            --soul-id "$sid" --peer "$peers" --token "$SHARED_TOKEN2" --port "$NEXT_PORT" \
            --x-promo "$xp" --x-atr "$xa" --wire-log "$D/$sid.wire" >"$D/$sid.out" 2>&1 &
        PIDS+=("$!"); eval "P_$sid=$!"
    done
    python3 -I "$SOUL_HELPER" --host 127.0.0.1 --mode survivor --fault leave-after-stat \
        --soul-id carol --peer alice,bob,dave --token "$SHARED_TOKEN2" --port "$NEXT_PORT" \
        --x-promo 7 --x-atr 7 >"$D/carol.out" 2>&1 &
    PC=$!; PIDS+=("$PC")
    sleep 1
    py_soul "$D/bob.out" --mode dropout --soul-id bob --peer alice,carol,dave --token "$SHARED_TOKEN2" --port "$NEXT_PORT"
    PB=$PY_PID
    wait_all 30 "$CL" "$P_alice" "$P_dave" "$PC" "$PB"
    T=$(cat "$D/coord.out")
    assert_match "$T" "DROPOUT soul=carol round=1 \(FED_LEAVE before ACK\)" "FED_LEAVE after a stat counts as a dropout"
    assert_match "$T" "DROPOUT soul=bob" "bob's dropout detected"
    assert_match "$T" "AGGREGATE_SUM round=1 tag=topic:test sum_promo=130 sum_atr=70 n_part=2" \
        "reconciled sum is exactly the survivors' (alice + dave)"
fi

# ---------------------------------------------------------------------------
it_section "scenario U.peerset: handshake refusals"
D=$(stage_dir peerset)
next_port; PORT=$NEXT_PORT
start_coord "$D" "$PORT" 2
CP=$COORD_PID
if bind_ok "$D" "peer-set refusal scenario"; then
    for f in legacy-hello legacy-peer no-nonce no-peer dh-public; do
        python3 -I "$SOUL_HELPER" --host 127.0.0.1 --soul-id "f_$f" --peer alice --token tok \
            --port "$PORT" --fault "$f" --timeout 5 >"$D/fault_$f.out" 2>&1
        echo "exit=$?" >>"$D/fault_$f.out"
    done
    py_soul "$D/alice.out" --soul-id alice --peer bob --token tok --port "$PORT" --x-promo 1 --x-atr 1
    PA=$PY_PID
    sleep 1
    python3 -I "$SOUL_HELPER" --host 127.0.0.1 --soul-id alice --peer bob --token tok \
        --port "$PORT" --timeout 5 >"$D/dup.out" 2>&1
    echo "exit=$?" >>"$D/dup.out"
    py_soul "$D/bob.out" --soul-id bob --peer alice --token tok --port "$PORT" --x-promo 2 --x-atr 3
    PB=$PY_PID
    wait_all 25 "$CP" "$PA" "$PB"
    T=$(cat "$D/coord.out"); W=$(cat "$D/wire.log" 2>/dev/null || true)
    assert_match "$W" "S>C ERR expected SECAGG_HELLO ce-fed v3n-sa$" "old v3-sa HELLO rejected"
    assert_match "$W" "S>C ERR bad SecAgg setup line" "3-field (token-carrying) SECAGG_PEER rejected"
    assert_match "$W" "S>C ERR SECAGG_NONCE required$" "soul without SECAGG_NONCE rejected"
    assert_match "$W" "S>C ERR empty peer set" "soul without SECAGG_PEER rejected"
    assert_match "$W" "S>C ERR DH mode refused" "FED_DH_PUBLIC without CE_SECAGG_ALLOW_WEAK_DH rejected"
    assert_match "$T" "REFUSE duplicate soul id alice" "duplicate soul id refused"
    assert_nomatch "$T" "SECAGG JOIN soul=f_" "no faulty soul was admitted"
    assert_match "$(cat "$D/fault_legacy-hello.out")" "server rejected HELLO" "legacy soul saw the HELLO rejection"
    assert_match "$T" "AGGREGATE_SUM round=1 tag=topic:test sum_promo=3 sum_atr=4 n_part=2" \
        "the valid pair still completed its round"
fi
D=$(stage_dir onesoul)
next_port; PORT=$NEXT_PORT
start_coord "$D" "$PORT" 1
CP=$COORD_PID
if bind_ok "$D" "single-soul refusal"; then
    py_soul "$D/alice.out" --soul-id alice --peer bob --token tok --port "$PORT" --timeout 5
    wait_all 15 "$CP" "$PY_PID"
    T=$(cat "$D/coord.out"); W=$(cat "$D/wire.log" 2>/dev/null || true)
    assert_match "$T" "REFUSE session: CE_FED_SOULS must be at least 2" "CE_FED_SOULS=1 refused in SecAgg mode"
    assert_nomatch "$W" "FED_ROUND" "single-soul session: no FED_ROUND"
    assert_nomatch "$W" "S>C SECAGG_NONCE" "single-soul session: nothing relayed"
fi

# ===========================================================================
it_section "scenario U.dh: DH key exchange needs CE_SECAGG_ALLOW_WEAK_DH=1"
D=$(stage_dir dh_refused)
next_port
start_chat "$D" alice bob "$NEXT_PORT" gadget CE_SECAGG_DH=1
wait_all 30 "$CHAT_PID"
T=$(cat "$D/chat_alice.out")
assert_match "$T" "\\[SECAGG-DH\\] refusing: DH mode is unauthenticated" "DH without the weak-DH flag refused"
assert_nomatch "$T" "dialing 127" "refused before dialing"
D=$(stage_dir dh2048_refused)
next_port
start_chat "$D" alice bob "$NEXT_PORT" gadget CE_SECAGG_DH_2048=1
wait_all 30 "$CHAT_PID"
assert_match "$(cat "$D/chat_alice.out")" "\\[SECAGG-DH\\] refusing: DH mode is unauthenticated" \
    "DH-2048 without the weak-DH flag refused too"

# dh_session <stage> <deadline> <extra ENV...>
dh_session() {
    local name="$1" deadline="$2"; shift 2
    local d; d=$(stage_dir "$name")
    next_port
    local port=$NEXT_PORT
    start_coord "$d" "$port" 2 CE_SECAGG_ALLOW_WEAK_DH=1
    local cp=$COORD_PID
    bind_ok "$d" "$name scenario" || return 1
    start_chat "$d" alice bob "$port" gadget CE_SECAGG_ALLOW_WEAK_DH=1 "$@"
    local ca=$CHAT_PID
    sleep 1
    start_chat "$d" bob alice "$port" sprocket CE_SECAGG_ALLOW_WEAK_DH=1 "$@"
    local cb=$CHAT_PID
    wait_all "$deadline" "$cp" "$ca" "$cb"
    DH_DIR="$d"
    return 0
}

if dh_session dh 40 CE_SECAGG_DH=1; then
    T=$(cat "$DH_DIR/coord.out"); A=$(cat "$DH_DIR/chat_alice.out"); B=$(cat "$DH_DIR/chat_bob.out")
    W=$(cat "$DH_DIR/wire.log" 2>/dev/null || true)
    assert_match "$T" "\\[SECAGG-DH\\] WARNING: DH mode enabled by CE_SECAGG_ALLOW_WEAK_DH=1" \
        "coordinator printed the weak-DH banner"
    assert_match "$A" "\\[SECAGG-DH\\] WARNING weak DH mode enabled .*UNAUTHENTICATED" \
        "alice chat printed the unauthenticated-DH banner"
    assert_match "$A" "\\[SECAGG\\] enabled .v3n-sa-dh" "alice chat entered DH mode"
    assert_match "$T" "\\[SECAGG-DH\\] FED_DH_PUBLIC soul=[a-z]+ pubkey=" "coordinator received FED_DH_PUBLIC"
    assert_match "$T" "\\[SECAGG-DH\\] broadcasting 2 DH pubkey" "coordinator relayed both DH pubkeys"
    assert_match "$T" "\\[SECAGG-DH\\] DH key-exchange phase complete" "coordinator completed the DH relay"
    assert_match "$W" "C>S SECAGG_PEER bob$" "DH souls also announce token-free SECAGG_PEER lines"
    assert_match "$A" "\\[SECAGG-DH\\] received 1 peer pubkey" "alice received bob's DH pubkey"
    assert_match "$B" "\\[SECAGG-DH\\] received 1 peer pubkey" "bob received alice's DH pubkey"
    assert_match "$A" "exchange complete, peers=1 nonces=1" "alice received bob's nonce in DH mode"
    assert_match "$B" "exchange complete, peers=1 nonces=1" "bob received alice's nonce in DH mode"
    assert_match "$T" "\\[SECAGG\\] AGGREGATE_SUM round=1" "DH-scenario coordinator broadcast AGGREGATE_SUM"
    assert_eq "$(sums_plausible "$T")" "0" "DH-scenario sums are plausible (DH masks cancelled)"
    assert_match "$A" "fed: \\[SECAGG\\] round 1 complete" "alice completed round 1 under DH mode"
    assert_match "$B" "fed: \\[SECAGG\\] round 1 complete" "bob completed round 1 under DH mode"
fi

# ===========================================================================
it_section "scenario U.dh2048: DH key exchange, 2048-bit group (CE_IT_SLOW=1)"
if [ "$SLOW" != "1" ]; then
    printf "  ${C_DIM}INFO${C_RST}  U.dh2048 not selected (set CE_IT_SLOW=1 to run it)\n"
else
    if dh_session dh2048 240 CE_SECAGG_DH_2048=1; then
        T=$(cat "$DH_DIR/coord.out"); A=$(cat "$DH_DIR/chat_alice.out"); B=$(cat "$DH_DIR/chat_bob.out")
        assert_match "$A" "\\[SECAGG\\] enabled .v3n-sa-dh-2048" "alice chat entered DH-2048 mode"
        assert_match "$B" "\\[SECAGG\\] enabled .v3n-sa-dh-2048" "bob chat entered DH-2048 mode"
        assert_match "$A" "\\[SECAGG-DH-2048\\] generated keypair, sent FED_DH_PUBLIC" "alice sent a 2048-bit pubkey"
        assert_match "$B" "\\[SECAGG-DH-2048\\] generated keypair, sent FED_DH_PUBLIC" "bob sent a 2048-bit pubkey"
        assert_match "$T" "\\[SECAGG\\] AGGREGATE_SUM round=1" "DH-2048 coordinator broadcast AGGREGATE_SUM"
        assert_eq "$(sums_plausible "$T")" "0" "DH-2048 sums are plausible"
        assert_match "$A" "fed: \\[SECAGG\\] round 1 complete" "alice completed round 1 under DH-2048"
    fi
fi

finish
