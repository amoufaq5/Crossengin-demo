#!/usr/bin/env bash
# Scenario U4 -- SecAgg v4 (double masking) over the network (A2.3c),
# protocol v4-sa3 (verifiable shares, A2.4b; complaint round and blame,
# A2.4c).
#
# A v4 fed coordinator (CE_SECAGG_MODE=v4) runs one round with NOVA chat
# souls (/fed_join) and independent Python souls (scripts/sa4_ref.py
# --connect). Every soul is pinned by a roster of Ed25519 keys made with
# scripts/secagg_keygen.sh; the tag set is pinned with CE_SECAGG_V4_TAGS.
#
# Stages (each with its own run dirs under one mktemp dir):
#   U4.mixed    2 chat souls + 1 Python soul, N = 3: every party prints the
#               same sums, equal to the inputs each soul printed locally;
#               wire log: v4-sa3 hello / OK / FED_JOIN / SA4_ROUND, the
#               6-token SHARE (one-time key), SHSIG, SET 5 and END 4 of the
#               check phase, no ACCUSE (no complaint: the open phase is
#               skipped), the Python soul's plain input words never cross
#               the wire; the round counter and a chat soul's last-round file
#               are 0600. (A fresh chat session's promo/atr rates are 0, so
#               for chat souls the sums check the present words; the Python
#               soul's non-zero values check the rest.)
#   U4.replay   chat soul1 and the Python soul (with their recorded last
#               round) plus a fresh soul against a fresh coordinator that
#               reopens round 1: the two refuse it (stale_round), nothing
#               is published.
#   U4.dropout  N = 4 Python souls: one leaves after its check reply (in U2,
#               not U3: its s-shares are revealed), or one leaves after its
#               shares (in U2', removed at the check close): the sums cover
#               the other three.
#   U4.silent   one soul joins and never answers: disconnected at the phase
#               deadline, the round completes over the other three (the
#               souls read after it still get their buffered lines read).
#   U4.drip     a soul sends its ADV one byte every 0.2 s: cut off at the
#               phase deadline (the timeout is re-armed per byte).
#   U4.faults   a swapped reveal kind (that soul's reveals are refused, the
#               sum still covers all four).
#   U4.blame    v4-sa3 complaint round (N = 4, CE_SECAGG_EVIDENCE_DIR set):
#               a sender whose share does not open / has wrong fields /
#               misses its commitment is blamed with code 1 (the receiver
#               complains, stays in U3, the round is published over the
#               other three; evidence file 0644, verdict "sender" from
#               sa4_ref.py --judge, refused when tampered); a false
#               complaint gives the complainer code 2 (evidence, verdict
#               "complainer"); an accused that does not open (no-open) or
#               reveals a key that does not match its e_pk (foreign-e) gets
#               code 3; a bad share with a bad SHSIG gets code 4; a bad SHSIG
#               alone is harmless; a low-order one-time key leaves the sender
#               out at receipt (code 0, no complaint); a soul that leaves at
#               the check is dropped. No evidence for codes 3 / 4.
#   U4.faults2  stop after ADV / Y / SIG3, a bad ADV signature, a bad SIG3:
#               the expected sets and sums.
#   U4.vshares  verifiable shares (v4-sa2): a revealer alters one b-share
#               (N = 4: the sums still equal the inputs, the coordinator
#               logs the excluded revealer); a revealer alters one s-share
#               of a soul that dropped out after the check (N = 7: sums
#               correct, excluded); a dealer commits to an off-polynomial
#               b-share (every proof verifies, the rebuild fails: the round
#               is refused and that dealer is blamed).
#   U4.minpresent  a tag only two souls have is withheld (min-present t).
#   U4.writeahead  a chat soul records the round id when the round opens,
#               even when the round is then cancelled.
#   U4.layout   a soul with another tag set refuses the round (bad_len /
#               bad_layout) and is not in U1.
#   U4.join     an id not in the roster and a second connection with an
#               already-joined id are rejected; too few souls -> no round.
#   U4.refuse   configuration refusals: CE_SECAGG_MODE without
#               CE_SECAGG_ENABLED and an unknown CE_SECAGG_MODE (both
#               sides), CE_SECAGG_ALLOW_RECON in v4, no tags, CE_FED_SOULS
#               below t, CE_FED_SOUL_ID not the roster name, a corrupt
#               last-round file; v3n-sa and v4 refuse each other's hello;
#               a v4-sa3 coordinator refuses the v4-sa (v1) and v4-sa2
#               hellos; v4-sa3 souls refuse a coordinator that answers with
#               the v4-sa2 OK.
#
# Env: CE_IT_STRICT=1 (CI) turns an environment SKIP (socket bind denied,
# python3 or openssl missing) into a FAIL.

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0
STRICT="${CE_IT_STRICT:-0}"
it_section "scenario U4: SecAgg v4 double masking over the network (A2.3c, protocol v4-sa3)"

COORD_BIN="$REPO_ROOT/bin/crossengin-fed-coordinator"
CHAT_BIN="$REPO_ROOT/bin/crossengin-chat"
REF="$REPO_ROOT/scripts/sa4_ref.py"
KG="$REPO_ROOT/scripts/secagg_keygen.sh"

skip() {
    if [ "$STRICT" = "1" ]; then
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  (strict) SKIP not allowed: %s\n" "$1"
    else
        printf "  ${C_YEL}SKIP${C_RST}  %s\n" "$1"
    fi
}
finish() { summary "scenario_u4_secagg"; exit $?; }

if [ ! -x "$COORD_BIN" ] || [ ! -x "$CHAT_BIN" ]; then
    printf "  ${C_RED}ERROR${C_RST}: %s or %s missing. Run: make install\n" "$COORD_BIN" "$CHAT_BIN" >&2
    FAIL=$((FAIL+1)); finish
fi
command -v python3 >/dev/null 2>&1 || { skip "python3 not on PATH"; finish; }
command -v openssl >/dev/null 2>&1 || { skip "openssl not on PATH"; finish; }

T="$(mktemp -d)"
chmod 700 "$T"
PIDS=()
cleanup() {
    local p
    for p in "${PIDS[@]}"; do pkill -9 -P "$p" 2>/dev/null; kill -9 "$p" 2>/dev/null; done
    rm -rf "$T"
}
trap cleanup EXIT

# wait_all <deadline_s> <pid>... ; force-kills on deadline (counts a FAIL).
wait_all() {
    local deadline="$1"; shift
    local elapsed=0 alive p
    while [ "$elapsed" -lt "$deadline" ]; do
        alive=0
        for p in "$@"; do kill -0 "$p" 2>/dev/null && alive=1; done
        [ "$alive" -eq 0 ] && break
        sleep 1; elapsed=$((elapsed + 1))
    done
    # Recheck after the loop: a process that exited during the last sleep
    # is not a hang.
    alive=0
    for p in "$@"; do kill -0 "$p" 2>/dev/null && alive=1; done
    if [ "$alive" -ne 0 ]; then
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  process(es) hung past %ss, force-killed\n" "$deadline"
        # The coordinator and chats run inside a subshell: kill its
        # children (the binaries) as well as the subshell itself.
        for p in "$@"; do pkill -9 -P "$p" 2>/dev/null; kill -9 "$p" 2>/dev/null; done
    fi
    for p in "$@"; do wait "$p" 2>/dev/null; done
}

# Every process a stage starts goes into SP; stage_wait waits for all of
# them with a hang guard (never a bare `wait`).
SP=()
stage_wait() { wait_all "$1" "${SP[@]}"; SP=(); }

# Keys and rosters: souls 1..7 with ids 10..70; R3 = souls 1-3, R4 = 1-4,
# R7 = 1-7.
for i in 1 2 3 4 5 6 7; do
    bash "$KG" "$T/k$i" $((i * 10)) "soul$i" | sed -n 's/^roster line: //p' > "$T/line$i"
done
mkroster() {   # mkroster <file> <soul numbers...>
    local f="$1"; shift
    { echo "crossengin-secagg-roster v1"; for i in "$@"; do cat "$T/line$i"; done; } > "$f"
    chmod 644 "$f"
}
mkroster "$T/R3" 1 2 3
mkroster "$T/R4" 1 2 3 4
mkroster "$T/R3b" 1 2 5
mkroster "$T/R7" 1 2 3 4 5 6 7
assert_match "$(cat "$T/R4")" '^crossengin-secagg-roster v1' "rosters written"

TAGS="seed,user-teach"
# Below the Linux ephemeral range (32768+), apart from the U4 evil scenario.
PORT=$(( 12000 + (RANDOM % 900) * 4 ))
next_port() { PORT=$((PORT + 1)); }

# start_coord <dir> <roster> [ENV=VAL ...] -> COORD_PID; output <dir>/coord.out
start_coord() {
    local d="$1" ro="$2"; shift 2
    mkdir -p "$d/run"; chmod 700 "$d" "$d/run"
    (
        export CE_RUN_DIR="${RUN_DIR:-$d/run}" CE_FED_PORT="$PORT" CE_FED_BIND=127.0.0.1
        export CE_SECAGG_ENABLED=1 CE_SECAGG_MODE=v4 CE_SECAGG_ROSTER="$ro" CE_SECAGG_V4_TAGS="$TAGS"
        export CE_FED_WIRE_LOG="$d/wire.log" CE_SECAGG_V4_JOIN_MS=20000 CE_SECAGG_V4_PHASE_MS=20000
        for kv in "$@"; do export "$kv"; done
        "$COORD_BIN" >>"$d/coord.out" 2>&1
        echo "coord-exit=$?" >>"$d/coord.out"
    ) &
    COORD_PID=$!; PIDS+=("$COORD_PID"); SP+=("$COORD_PID")
    local n=0
    while [ $n -lt 40 ]; do
        grep -q "listening\|REFUSE\|cannot bind" "$d/coord.out" 2>/dev/null && break
        sleep 0.25; n=$((n + 1))
    done
}

# wait_log <file> <regex> <seconds>: until the pattern appears.
wait_log() {
    local n=0
    while [ $n -lt $(( $3 * 4 )) ]; do
        grep -qE "$2" "$1" 2>/dev/null && return 0
        sleep 0.25; n=$((n + 1))
    done
    return 1
}
now_ms() { date +%s%3N; }

bind_ok() {
    if grep -q "ERROR cannot bind / listen" "$1/coord.out" 2>/dev/null; then
        skip "socket bind denied -- $2 skipped"
        return 1
    fi
    return 0
}

# py_soul <dir> <name> <roster> <soul#> <x> [extra args] -> PY_PID
py_soul() {
    local d="$1" name="$2" ro="$3" k="$4" x="$5"; shift 5
    CE_SECAGG_ROSTER="$ro" CE_SECAGG_ID_KEY="$T/k$k.priv" \
        python3 -I "$REF" --connect "127.0.0.1:$PORT" --tags "${PYTAGS:-$TAGS}" --x "$x" --state "${PYSTATE:-$d/state_$name}" \
        --timeout 30 "$@" > "$d/$name.out" 2>&1 &
    PY_PID=$!; PIDS+=("$PY_PID"); SP+=("$PY_PID")
}

# chat_soul <dir> <name> <roster> <soul#> [ENV=VAL ...] -> CHAT_PID
chat_soul() {
    local d="$1" name="$2" ro="$3" k="$4"; shift 4
    (
        export CE_RUN_DIR="$T/chatrun_$name"
        mkdir -p "$CE_RUN_DIR"; chmod 700 "$CE_RUN_DIR"
        export CE_SECAGG_ENABLED=1 CE_SECAGG_MODE=v4 CE_SECAGG_ROSTER="$ro" CE_SECAGG_ID_KEY="$T/k$k.priv"
        export CE_SECAGG_V4_TAGS="$TAGS" CE_SESSION_ID="$name"
        export CE_SNAP_PATH="$d/$name.snap" CE_DLOG_PATH="$d/$name.dlog"
        for kv in "$@"; do export "$kv"; done
        printf '/teach widget\n/teach gadget%s\n/cap grant network_send\n/fed_join 127.0.0.1:%s\n/fed_leave\n/quit\n' "$k" "$PORT" \
            | "$CHAT_BIN" > "$d/$name.out" 2>&1
    ) &
    CHAT_PID=$!; PIDS+=("$CHAT_PID"); SP+=("$CHAT_PID")
}

# sum_of <file...>: total of "input (stays local)" values for <tag> <field>
local_input() {   # local_input <file> <tag> <field>
    sed -n "s/.*input (stays local) tag=$2 promo=\([0-9]*\) atr=\([0-9]*\) present=\([0-9]*\).*/\1 \2 \3/p" "$1" \
        | awk -v f="$3" '{ if (f == "promo") print $1; else if (f == "atr") print $2; else print $3 }'
}

# ===========================================================================
# U4.mixed: 2 chat souls + 1 Python soul.
# ===========================================================================
D="$T/mixed"; mkdir -p "$D"
next_port
start_coord "$D" "$T/R3"
CP=$COORD_PID
if bind_ok "$D" "U4.mixed"; then
    chat_soul "$D" soul1 "$T/R3" 1; C1=$CHAT_PID
    chat_soul "$D" soul2 "$T/R3" 2; C2=$CHAT_PID
    py_soul "$D" py3 "$T/R3" 3 "seed=11:22,user-teach=33:44"; P3=$PY_PID
    stage_wait 120
    CO=$(cat "$D/coord.out"); O1=$(cat "$D/soul1.out"); O2=$(cat "$D/soul2.out"); O3=$(cat "$D/py3.out")
    W=$(cat "$D/wire.log" 2>/dev/null)
    assert_match "$CO" "mode=v4-sa3 \\(SecAgg double masking, verifiable shares and blame\\)" "coordinator in v4 mode (protocol v4-sa3)"
    assert_match "$CO" "\\[SA4\\] JOIN id=10 " "soul 10 joined"
    assert_match "$CO" "\\[SA4\\] JOIN id=20 " "soul 20 joined"
    assert_match "$CO" "\\[SA4\\] JOIN id=30 " "soul 30 joined"
    assert_match "$CO" "round-counter=1 persisted" "round counter persisted before the round"
    assert_match "$CO" "phase 1 closed: \\|U2'\\|=3" "all three shares routed (U2')"
    assert_match "$CO" "phase check closed: 0 complaint\\(s\\) against 0 soul\\(s\\)" "check phase: no complaint"
    assert_match "$CO" "phase open skipped: \\|U2\\|=3" "no complaint: the open phase is skipped"
    assert_match "$CO" "phase 3 closed: \\|U4\\|=3" "all three souls signed U3"
    assert_nomatch "$CO" "blamed:" "honest round: nobody blamed"
    assert_match "$CO" "coord-exit=0" "coordinator exited 0"
    for tag in seed user-teach; do
        EP=$(( $(local_input "$D/soul1.out" $tag promo) + $(local_input "$D/soul2.out" $tag promo) + $( [ $tag = seed ] && echo 11 || echo 33) ))
        EA=$(( $(local_input "$D/soul1.out" $tag atr) + $(local_input "$D/soul2.out" $tag atr) + $( [ $tag = seed ] && echo 22 || echo 44) ))
        EN=$(( $(local_input "$D/soul1.out" $tag present) + $(local_input "$D/soul2.out" $tag present) + 1 ))
        L="AGGREGATE_SUM round=1 tag=$tag sum_promo=$EP sum_atr=$EA n_part=$EN"
        assert_match "$CO" "\\[SA4\\] $L" "coordinator: $tag sum = the souls' local inputs ($EP/$EA/$EN)"
        assert_match "$O1" "fed: \\[SA4\\] $L" "chat soul1 received the $tag sum"
        assert_match "$O2" "fed: \\[SA4\\] $L" "chat soul2 received the $tag sum"
        assert_match "$O3" "sa4_ref: $L" "Python soul received the $tag sum"
    done
    assert_match "$O1" "fed: \\[SA4\\] round 1 complete \\(2 sum aggregate" "chat soul1 completed the round"
    assert_match "$O2" "fed: \\[SA4\\] round 1 complete \\(2 sum aggregate" "chat soul2 completed the round"
    assert_match "$O3" "BYE after 2 aggregate" "Python soul completed the round"
    assert_match "$W" "C>S SECAGG_HELLO ce-fed v4-sa3$" "wire: v4-sa3 hello"
    assert_match "$W" "S>C OK ce-fed v4-sa3 protocol accepted$" "wire: exact v4-sa3 OK"
    assert_match "$W" "C>S SA4_ADV 1 30 [0-9a-f]{64} [0-9a-f]{64} [0-9a-f]{64} [0-9a-f]{64} [0-9a-f]{128}$" "wire: ADV (c_pk, s_pk, B, M, sig)"
    assert_match "$W" "C>S SA4_SHARE 1 30 10 [0-9a-f]{64} [0-9a-f]{324}$" "wire: v4-sa3 share: one-time key e_pk + ciphertext (N = 3: 98 + 32 * 2 bytes)"
    assert_match "$W" "C>S SA4_SHSIG 1 30 [0-9a-f]{128}$" "wire: the Python soul's share-root signature (SHSIG)"
    assert_match "$W" "C>S SA4_SHSIG 1 10 [0-9a-f]{128}$" "wire: a chat soul's share-root signature (SHSIG)"
    assert_match "$W" "S>C SA4_SET 1 5 [0-9a-f]{64}$" "wire: SET 5 (U2') starts the check phase"
    assert_match "$W" "C>S SA4_END 1 4 30 0$" "wire: the Python soul ends the check with no complaint"
    assert_match "$W" "C>S SA4_END 1 4 20 0$" "wire: a chat soul ends the check with no complaint"
    assert_nomatch "$W" "SA4_COMPLAINT|SA4_ACCUSE|SA4_OPEN" "wire: no complaint, accusation or opening in an honest round"
    assert_match "$W" "C>S SA4_REVEAL 1 30 10 b [0-9a-f]{64} [0-9a-f]{192}$" "wire: v4-sa2 reveal with its proof (other hash + 2 path nodes)"
    assert_match "$W" "C>S FED_JOIN 10 1000$" "wire: FED_JOIN with the roster id"
    assert_match "$W" "S>C SA4_ROUND 1 [0-9a-f]{64} 6 [0-9a-f]{64}$" "wire: SA4_ROUND with L = 6 and the layout hash"
    assert_match "$W" "C>S SA4_Y 1 30 0 1 [0-9a-f]{48}$" "wire: the Python soul's masked vector (6 words)"
    assert_nomatch "$W" "0000000b0000001600000001000000210000002c00000001" "wire: the Python soul's plain input words never appear"
    assert_nomatch "$W" "SECAGG_NONCE|SECAGG_PEER|FED_STAT_MASKED" "wire: no v3n-sa lines"
    CF="$D/run/$(ls "$D/run" | grep '^crossengin_fed_sa4_round_[0-9a-f]*$' | head -1)"
    assert_eq "$(cat "$CF" 2>/dev/null)" "1" "coordinator round counter holds 1"
    assert_eq "$(stat -c %a "$CF" 2>/dev/null)" "600" "coordinator round counter is 0600"
    LR=$(ls "$T/chatrun_soul1" | grep '^crossengin_sa4_last_round_[0-9a-f]*_10$' | head -1)
    assert_match "$(cat "$T/chatrun_soul1/$LR" 2>/dev/null)" "^crossengin-sa4-last-round v1 [0-9a-f]{64} 10 1$" "chat soul1 last-round file records round 1"
    assert_eq "$(stat -c %a "$T/chatrun_soul1/$LR" 2>/dev/null)" "600" "chat last-round file is 0600"
fi

# ===========================================================================
# U4.replay: a fresh coordinator reopens round 1; the souls refuse it.
# ===========================================================================
D="$T/replay"; mkdir -p "$D"
next_port
start_coord "$D" "$T/R3" CE_SECAGG_V4_PHASE_MS=5000
CP=$COORD_PID
if bind_ok "$D" "U4.replay"; then
    chat_soul "$D" soul1 "$T/R3" 1; C1=$CHAT_PID
    PYSTATE="$T/mixed/state_py3" py_soul "$D" py3 "$T/R3" 3 "seed=11:22"; P3=$PY_PID
    py_soul "$D" py2 "$T/R3" 2 "seed=1:2"; P2=$PY_PID
    stage_wait 90
    CO=$(cat "$D/coord.out")
    assert_match "$CO" "opening round 1 " "fresh coordinator reopened round 1"
    assert_match "$(cat "$D/soul1.out")" "last-round=1" "chat soul1 loaded its last round (1)"
    assert_match "$(cat "$D/soul1.out")" "round 1 is not after the last round" "chat soul1 refused the replayed round 1"
    assert_match "$(cat "$D/py3.out")" "not after the last round" "Python soul refused the replayed round 1"
    assert_match "$CO" "left out id=10: aborted the round \\(stale_round\\)" "coordinator saw the chat soul's stale_round abort"
    assert_match "$CO" "left out id=30: aborted the round \\(stale_round\\)" "coordinator saw the Python soul's stale_round abort"
    assert_nomatch "$CO" "AGGREGATE_SUM" "replay: nothing published"
fi

# ===========================================================================
# U4.dropout: N = 4, one Python soul leaves after its check reply (in U2,
# never sends Y: its s-shares are revealed), or after its shares (in U2',
# removed at the check close, before any y).
# ===========================================================================
D="$T/dropout"; mkdir -p "$D"
next_port
start_coord "$D" "$T/R4"
CP=$COORD_PID
if bind_ok "$D" "U4.dropout"; then
    for k in 1 2 3; do py_soul "$D" p$k "$T/R4" $k "seed=$((k * 100)):$((k * 7)),user-teach=$k:$k"; done
    P1=$PY_PID
    py_soul "$D" p4 "$T/R4" 4 "seed=4000:4000" --fault stop-after-check
    stage_wait 90
    CO=$(cat "$D/coord.out")
    assert_match "$CO" "phase 1 closed: \\|U2'\\|=4" "dropout: the leaving soul sent its shares (in U2')"
    assert_match "$CO" "phase open skipped: \\|U2\\|=4" "dropout: it answered the check (in U2)"
    assert_match "$CO" "phase 2 closed: \\|U3\\|=3" "dropout: it is not in U3"
    assert_match "$CO" "AGGREGATE_SUM round=1 tag=seed sum_promo=600 sum_atr=42 n_part=3" "dropout: sum over the other three (s-shares revealed)"
    assert_match "$CO" "AGGREGATE_SUM round=1 tag=user-teach sum_promo=6 sum_atr=6 n_part=3" "dropout: second tag summed too"
fi
D="$T/dropout2"; mkdir -p "$D"
next_port
start_coord "$D" "$T/R4"
CP=$COORD_PID
if bind_ok "$D" "U4.dropout (after shares)"; then
    for k in 1 2 3; do py_soul "$D" p$k "$T/R4" $k "seed=$((k * 100)):$((k * 7)),user-teach=$k:$k"; done
    py_soul "$D" p4 "$T/R4" 4 "seed=4000:4000" --fault stop-after-shares
    stage_wait 90
    CO=$(cat "$D/coord.out")
    assert_match "$CO" "phase 1 closed: \\|U2'\\|=4" "dropout after shares: its shares were routed (in U2')"
    # It closes right after its shares: routing SET 5 to it fails, or (if the
    # send still lands in the socket buffer) the check phase reads EOF.
    assert_match "$CO" "disconnected id=40 in phase (1: send failed|check: )" "dropout after shares: disconnected when routing the check phase or in it"
    assert_match "$CO" "left out id=40: did not finish the check phase \\(code 0\\)" "dropout after shares: removed at the check close, not blamed (code 0)"
    assert_match "$CO" "phase open skipped: \\|U2\\|=3" "dropout after shares: not in U2 (removed before any y)"
    assert_match "$CO" "AGGREGATE_SUM round=1 tag=seed sum_promo=600 sum_atr=42 n_part=3" "dropout after shares: sum over the other three"
    assert_nomatch "$CO" "blamed:" "dropout after shares: a dropout is not blamed"
fi

# ===========================================================================
# U4.silent: a soul joins and never answers.
# ===========================================================================
D="$T/silent"; mkdir -p "$D"
next_port
start_coord "$D" "$T/R4" CE_SECAGG_V4_PHASE_MS=3000
CP=$COORD_PID
if bind_ok "$D" "U4.silent"; then
    # The silent soul joins first, so it is read first in every phase: the
    # others are read after the deadline and must still be read (grace).
    py_soul "$D" p4 "$T/R4" 4 "seed=9:9" --fault silent
    wait_log "$D/coord.out" "JOIN id=40 " 10
    for k in 1 2 3; do py_soul "$D" p$k "$T/R4" $k "seed=$((k * 100)):$((k * 7)),user-teach=$k:$k"; done
    wait_log "$D/coord.out" "opening round 1" 20
    T0=$(now_ms)
    wait_log "$D/coord.out" "disconnected id=40" 20
    CUT=$(( $(now_ms) - T0 ))
    stage_wait 90
    CO=$(cat "$D/coord.out")
    assert_match "$CO" "disconnected id=40 in phase 0: phase deadline passed" "silent soul disconnected at the phase deadline"
    assert_eq "$([ "$CUT" -ge 2500 ] && echo yes || echo "no (${CUT} ms)")" "yes" "silent: cut no earlier than the 3 s deadline (${CUT} ms after the round opened)"
    assert_match "$CO" "phase 0 closed: \\|U1\\|=3" "silent: the souls read after the deadline still got their ADV read"
    assert_match "$CO" "AGGREGATE_SUM round=1 tag=seed sum_promo=600 sum_atr=42 n_part=3" "silent: round completed over the other three"
fi

# ===========================================================================
# U4.drip: a soul trickles its ADV one byte every 0.2 s; the phase deadline
# still holds (the receive timeout is re-armed per byte).
# ===========================================================================
D="$T/drip"; mkdir -p "$D"
next_port
start_coord "$D" "$T/R4" CE_SECAGG_V4_PHASE_MS=3000
CP=$COORD_PID
if bind_ok "$D" "U4.drip"; then
    py_soul "$D" p4 "$T/R4" 4 "seed=9:9" --fault drip
    wait_log "$D/coord.out" "JOIN id=40 " 10
    for k in 1 2 3; do py_soul "$D" p$k "$T/R4" $k "seed=$((k * 100)):$((k * 7)),user-teach=$k:$k"; done
    SECONDS=0
    stage_wait 90
    ELAPSED=$SECONDS
    CO=$(cat "$D/coord.out")
    assert_match "$CO" "disconnected id=40 in phase 0: phase deadline passed" "a dripping soul is cut off at the phase deadline"
    assert_match "$CO" "AGGREGATE_SUM round=1 tag=seed sum_promo=600 sum_atr=42 n_part=3" "drip: round completed over the other three"
    assert_match "$ELAPSED" '^([3-9]|1[0-9])$' "drip: the round took ${ELAPSED}s (at least the 3 s deadline, bounded by it, not by the drip)"
fi

# ===========================================================================
# U4.faults: swapped reveal kind. (A corrupted share is U4.blame.)
# ===========================================================================
D="$T/swap"; mkdir -p "$D"
next_port
start_coord "$D" "$T/R4"
CP=$COORD_PID
if bind_ok "$D" "U4.faults (swap reveal)"; then
    py_soul "$D" p2 "$T/R4" 2 "seed=200:14,user-teach=2:2" --fault swap-reveal
    for k in 1 3 4; do py_soul "$D" p$k "$T/R4" $k "seed=$((k * 100)):$((k * 7)),user-teach=$k:$k"; done
    stage_wait 90
    CO=$(cat "$D/coord.out")
    assert_match "$CO" "left out id=20: wrong share kind for that soul" "a swapped reveal kind is refused"
    assert_match "$CO" "AGGREGATE_SUM round=1 tag=seed sum_promo=1000 sum_atr=70 n_part=4" "swap reveal: sum still covers all four (t reveals remain)"
fi

# ===========================================================================
# U4.blame: the v4-sa3 complaint round (A2.4c), N = 4 (t = 3). Faults are
# aimed by soul 1 (id 10) at the lowest other x (soul 2, id 20); the false
# complaint by soul 3 (id 30) is about the lowest other x (id 10). Evidence
# of codes 1 / 2 goes to CE_SECAGG_EVIDENCE_DIR and is checked with the
# standalone judge (sa4_ref.py --judge).
# ===========================================================================
# blame_stage <name> <faulty soul#> <fault> -> D, CO
blame_stage() {
    local name="$1" fk="$2" fm="$3" k
    D="$T/blame_$name"; mkdir -p "$D/ev"
    next_port
    start_coord "$D" "$T/R4" CE_SECAGG_EVIDENCE_DIR="$D/ev"
    CP=$COORD_PID
    CO=""
    bind_ok "$D" "U4.blame $name" || return 1
    for k in 1 2 3 4; do
        if [ "$k" = "$fk" ]; then
            py_soul "$D" p$k "$T/R4" $k "seed=$((k * 100)):$((k * 7)),user-teach=$k:$k" --fault "$fm"
        else
            py_soul "$D" p$k "$T/R4" $k "seed=$((k * 100)):$((k * 7)),user-teach=$k:$k"
        fi
    done
    stage_wait 90
    CO=$(cat "$D/coord.out")
    return 0
}

# Code 1, share does not open (the A2.3c "bad share"; was: receiver aborts
# bad_share and is left out as "possibly a victim", sender not blamed).
if blame_stage open 1 bad-share-open; then
    assert_match "$(cat "$D/p2.out")" "sa4_ref: complained about 10$" "bad share (open): the receiver complains about the sender"
    assert_nomatch "$(cat "$D/p2.out")" "abort code" "bad share (open): the receiver does not abort"
    assert_match "$CO" "phase check closed: 1 complaint\\(s\\) against 1 soul\\(s\\)" "bad share (open): one complaint forwarded"
    assert_match "$(cat "$D/p1.out")" "sa4_ref: accused: 1 opening\\(s\\)" "bad share (open): the accused sender opens its one-time key"
    assert_match "$CO" "blamed: 10:1$" "bad share (open): the sender is blamed, code 1"
    assert_match "$CO" "soul 10: proven: sent soul 20 a share that fails the open check$" "bad share (open): exact why text"
    assert_match "$CO" "disconnected id=10 in phase open: not in U2" "bad share (open): the blamed sender is disconnected (not in U2)"
    assert_nomatch "$CO" "left out id=20" "bad share (open): the receiver is kept"
    assert_match "$CO" "phase open closed: \\|U2\\|=3" "bad share (open): U2 = the other three"
    assert_match "$CO" "phase 2 closed: \\|U3\\|=3" "bad share (open): the receiver is in U3"
    assert_match "$CO" "AGGREGATE_SUM round=1 tag=seed sum_promo=900 sum_atr=63 n_part=3" "bad share (open): published over the other three"
    assert_match "$(cat "$D/p2.out")" "sa4_ref: AGGREGATE_SUM round=1 tag=seed sum_promo=900 sum_atr=63 n_part=3" "bad share (open): the receiver gets the sum"
    EV="$D/ev/sa4_evidence_r1_10.txt"
    assert_match "$CO" "evidence against id=10 \\(code 1\\): $EV$" "bad share (open): evidence file logged"
    assert_eq "$(stat -c %a "$EV" 2>/dev/null)" "644" "bad share (open): evidence file is 0644"
    assert_eq "$(head -1 "$EV" 2>/dev/null)" "crossengin-sa4-evidence v1" "bad share (open): evidence header"
    J=$(python3 -I "$REF" --judge "$EV" --roster "$T/R4" 2>&1)
    assert_eq "$?" "0" "bad share (open): the judge accepts the evidence"
    assert_eq "$J" "verdict: sender 10" "bad share (open): the judge's verdict is the sender"
    J=$(CE_SECAGG_ROSTER="$T/R4" python3 -I "$REF" --judge "$EV" 2>&1)
    assert_eq "$J" "verdict: sender 10" "bad share (open): the judge reads the roster from CE_SECAGG_ROSTER"
    sed 's/^complainer 20$/complainer 30/' "$EV" > "$D/ev_bad.txt"
    J=$(python3 -I "$REF" --judge "$D/ev_bad.txt" --roster "$T/R4" 2>&1)
    assert_eq "$?" "2" "bad share (open): evidence naming another complainer is refused"
    assert_match "$J" "^invalid: " "bad share (open): the judge prints invalid"
    J=$(python3 -I "$REF" --judge "$EV" --roster "$T/R3b" 2>&1)
    assert_eq "$?" "2" "bad share (open): evidence against another roster is refused"
fi

# Code 1, wrong fields (x_to of the plaintext).
if blame_stage fields 1 bad-share-fields; then
    assert_match "$CO" "blamed: 10:1$" "bad share (fields): sender code 1"
    assert_match "$CO" "soul 10: proven: sent soul 20 a share that fails the fields check$" "bad share (fields): exact why text"
    assert_match "$CO" "AGGREGATE_SUM round=1 tag=seed sum_promo=900 sum_atr=63 n_part=3" "bad share (fields): published over the other three"
    assert_eq "$(python3 -I "$REF" --judge "$D/ev/sa4_evidence_r1_10.txt" --roster "$T/R4" 2>&1)" "verdict: sender 10" "bad share (fields): judged against the sender"
fi

# Code 1, share does not match its commitment (v4-sa2: the receiver aborted
# bad_commit, the round went on without it and the dealer was not blamed).
if blame_stage commit 1 bad-commit-share; then
    assert_match "$(cat "$D/p2.out")" "sa4_ref: complained about 10$" "bad commit share: the receiver complains instead of aborting bad_commit"
    assert_match "$CO" "blamed: 10:1$" "bad commit share: the dealer is blamed, code 1"
    assert_match "$CO" "soul 10: proven: sent soul 20 a share that fails the commit check$" "bad commit share: exact why text"
    assert_nomatch "$CO" "left out id=20" "bad commit share: the receiver is kept"
    assert_match "$CO" "AGGREGATE_SUM round=1 tag=seed sum_promo=900 sum_atr=63 n_part=3" "bad commit share: published over the other three"
    assert_eq "$(python3 -I "$REF" --judge "$D/ev/sa4_evidence_r1_10.txt" --roster "$T/R4" 2>&1)" "verdict: sender 10" "bad commit share: judged against the dealer"
fi

# Code 2: soul 3 complains falsely about soul 1's valid share.
if blame_stage false 3 false-complaint; then
    assert_match "$(cat "$D/p3.out")" "sa4_ref: complained about 10$" "false complaint: soul 30 complains about 10"
    assert_match "$(cat "$D/p1.out")" "sa4_ref: accused: 1 opening\\(s\\)" "false complaint: the honest accused opens (the complaint is valid in form)"
    assert_match "$CO" "blamed: 30:2$" "false complaint: the complainer is blamed, code 2"
    assert_match "$CO" "soul 30: proven: false complaint about soul 10 \\(the share opens and matches\\)$" "false complaint: exact why text"
    assert_nomatch "$CO" "left out id=10" "false complaint: the accused is kept"
    assert_match "$CO" "AGGREGATE_SUM round=1 tag=seed sum_promo=700 sum_atr=49 n_part=3" "false complaint: published without the liar"
    EV="$D/ev/sa4_evidence_r1_30.txt"
    assert_match "$(grep '^path ' "$EV" 2>/dev/null)" "^path -$" "false complaint: code-2 evidence carries no path"
    J=$(python3 -I "$REF" --judge "$EV" --roster "$T/R4" 2>&1)
    assert_eq "$?" "0" "false complaint: the judge accepts the evidence"
    assert_eq "$J" "verdict: complainer 30" "false complaint: the judge's verdict is the complainer"
    sed 's/^code 2$/code 1/' "$EV" > "$D/ev_bad.txt"
    assert_match "$(python3 -I "$REF" --judge "$D/ev_bad.txt" --roster "$T/R4" 2>&1)" "^invalid: " "false complaint: evidence with the code changed is refused"
fi

# Code 3: the accused does not open (END 5 0).
if blame_stage noopen 1 bad-share-open,no-open; then
    assert_match "$(cat "$D/p1.out")" "sa4_ref: accused: 0 opening\\(s\\)" "silent accused: no opening"
    assert_match "$CO" "blamed: 10:3$" "silent accused: code 3"
    assert_match "$CO" "soul 10: did not open its share to soul 20 with its one-time key \\(not proven\\)$" "silent accused: exact why text"
    assert_match "$CO" "AGGREGATE_SUM round=1 tag=seed sum_promo=900 sum_atr=63 n_part=3" "silent accused: published over the other three"
    assert_nomatch "$CO" "evidence against" "silent accused: no evidence (code 3 is not proof)"
    assert_eq "$(ls "$D/ev" | wc -l)" "0" "silent accused: no evidence file"
fi

# Code 3: the accused reveals a key that does not match its e_pk.
if blame_stage foreign 1 foreign-e; then
    assert_match "$(cat "$D/p2.out")" "sa4_ref: complained about 10$" "foreign key: the receiver complains"
    assert_match "$CO" "blamed: 10:3$" "foreign key: code 3 (the opening does not match e_pk)"
    assert_nomatch "$CO" "left out id=20" "foreign key: the victim stays"
    assert_match "$CO" "AGGREGATE_SUM round=1 tag=seed sum_promo=900 sum_atr=63 n_part=3" "foreign key: published over the other three"
    assert_nomatch "$CO" "evidence against" "foreign key: no evidence"
fi

# Code 4: a bad share and a bad share-root signature.
if blame_stage badshsig 1 bad-shsig,bad-share-open; then
    assert_match "$CO" "blamed: 10:4$" "bad SHSIG + bad share: code 4"
    assert_match "$CO" "soul 10: share signature does not verify over the shares it sent \\(not proven\\)$" "bad SHSIG + bad share: exact why text"
    assert_match "$CO" "AGGREGATE_SUM round=1 tag=seed sum_promo=900 sum_atr=63 n_part=3" "bad SHSIG + bad share: published over the other three"
    assert_nomatch "$CO" "evidence against" "bad SHSIG + bad share: no evidence (code 4 is not proof)"
fi

# A bad SHSIG alone is harmless: the root is only checked for a complaint.
if blame_stage shsigonly 1 bad-shsig; then
    assert_nomatch "$CO" "blamed:" "bad SHSIG alone: nobody blamed"
    assert_match "$CO" "AGGREGATE_SUM round=1 tag=seed sum_promo=1000 sum_atr=70 n_part=4" "bad SHSIG alone: published over all four"
fi

# A low-order one-time key: structural, the sender is left out at receipt.
if blame_stage lowepk 1 low-epk; then
    assert_match "$CO" "refused a line from id=10: .*share one-time key is not a valid X25519 key" "low-order e_pk: refused at receipt"
    assert_match "$CO" "left out id=10: share one-time key is not a valid X25519 key \\(code 0\\)" "low-order e_pk: left out, code 0 (not proven)"
    assert_match "$CO" "phase 1 closed: \\|U2'\\|=3" "low-order e_pk: the sender is not in U2'"
    assert_match "$CO" "phase check closed: 0 complaint\\(s\\)" "low-order e_pk: the line is never routed, no complaint"
    assert_nomatch "$CO" "blamed:" "low-order e_pk: nobody blamed"
    assert_match "$CO" "AGGREGATE_SUM round=1 tag=seed sum_promo=900 sum_atr=63 n_part=3" "low-order e_pk: published over the other three"
fi

# A soul that leaves right after SET 5 without answering the check.
if blame_stage silentcheck 1 silent-check; then
    assert_match "$(cat "$D/p1.out")" "fault silent-check: leaving" "silent check: the soul leaves after SET 5"
    assert_match "$CO" "left out id=10: did not finish the check phase \\(code 0\\)" "silent check: removed at the check close (code 0)"
    assert_match "$CO" "AGGREGATE_SUM round=1 tag=seed sum_promo=900 sum_atr=63 n_part=3" "silent check: published over the other three"
fi

# ===========================================================================
# U4.faults2: the other fault modes, one round each (N = 4, t = 3).
# ===========================================================================
for spec in "1 stop-after-adv 900 63 3" "2 bad-adv-sig 800 56 3" "3 bad-sig3 1000 70 4" "4 stop-after-y 1000 70 4" "4 stop-after-sig3 1000 70 4"; do
    set -- $spec
    FK=$1; FM=$2; SP_=$3; SA_=$4; SN_=$5
    D="$T/f_$FM"; mkdir -p "$D"
    next_port
    start_coord "$D" "$T/R4"
    CP=$COORD_PID
    if bind_ok "$D" "U4.faults2 $FM"; then
        for k in 1 2 3 4; do
            if [ "$k" = "$FK" ]; then
                py_soul "$D" p$k "$T/R4" $k "seed=$((k * 100)):$((k * 7)),user-teach=$k:$k" --fault "$FM"
            else
                py_soul "$D" p$k "$T/R4" $k "seed=$((k * 100)):$((k * 7)),user-teach=$k:$k"
            fi
        done
        stage_wait 90
        assert_match "$(cat "$D/coord.out")" "AGGREGATE_SUM round=1 tag=seed sum_promo=$SP_ sum_atr=$SA_ n_part=$SN_" \
            "$FM (soul $FK): seed sum $SP_/$SA_ over $SN_"
    fi
done
assert_match "$(cat "$T/f_bad-adv-sig/coord.out" 2>/dev/null)" "left out id=20: ADV signature does not verify" "bad ADV signature: that soul is left out of U1"
assert_match "$(cat "$T/f_bad-sig3/coord.out" 2>/dev/null)" "left out id=30: SIG3 does not verify" "bad SIG3: that soul is left out of U4 (its input still counts: it is in U3)"

# ===========================================================================
# U4.vshares: verifiable shares (v4-sa2, A2.4b). Every share is committed in
# the dealer's signed ADV (B_u, Merkle root M_u); a receiver checks its share
# and path in R2; the coordinator rebuilds b_u / s_u robustly.
# ===========================================================================
# bad-b-reveal, N = 4 (t = 3, |R| = 4): soul 2 alters one b-share it reveals
# (proof kept). The rebuild excludes it and the sums are still the inputs.
D="$T/badbrev"; mkdir -p "$D"
next_port
start_coord "$D" "$T/R4"
CP=$COORD_PID
if bind_ok "$D" "U4.vshares (bad b reveal)"; then
    py_soul "$D" p2 "$T/R4" 2 "seed=200:14,user-teach=2:2" --fault bad-b-reveal
    for k in 1 3 4; do py_soul "$D" p$k "$T/R4" $k "seed=$((k * 100)):$((k * 7)),user-teach=$k:$k"; done
    stage_wait 90
    CO=$(cat "$D/coord.out")
    assert_match "$CO" "phase 3 closed: \\|U4\\|=4" "bad b reveal: all four signed U3"
    assert_match "$CO" "unmasked over \\|U3\\|=4" "bad b reveal: the round is unmasked (was a silently wrong sum in v4-sa)"
    assert_match "$CO" "\\[SA4\\] excluded revealer\\(s\\): 20$" "bad b reveal: the coordinator logs the excluded revealer (id 20)"
    assert_match "$CO" "AGGREGATE_SUM round=1 tag=seed sum_promo=1000 sum_atr=70 n_part=4" "bad b reveal: seed sum equals the inputs"
    assert_match "$CO" "AGGREGATE_SUM round=1 tag=user-teach sum_promo=10 sum_atr=10 n_part=4" "bad b reveal: user-teach sum equals the inputs"
    assert_match "$(cat "$D/p1.out")" "sa4_ref: AGGREGATE_SUM round=1 tag=seed sum_promo=1000 sum_atr=70 n_part=4" "bad b reveal: a soul received the correct sum"
    assert_match "$(cat "$D/p2.out")" "sa4_ref: round 1 done" "bad b reveal: the lying soul itself finished its round"
fi

# two bad-b-reveal souls, N = 4 (t = 3, |R| = 4): |R| - t + 1 liars leave
# fewer than t good shares, so the round is refused; the coordinator still
# names both connections that lied.
D="$T/badbrev2"; mkdir -p "$D"
next_port
start_coord "$D" "$T/R4"
CP=$COORD_PID
if bind_ok "$D" "U4.vshares (two bad b reveals)"; then
    py_soul "$D" p2 "$T/R4" 2 "seed=200:14,user-teach=2:2" --fault bad-b-reveal
    py_soul "$D" p3 "$T/R4" 3 "seed=300:21,user-teach=3:3" --fault bad-b-reveal
    for k in 1 4; do py_soul "$D" p$k "$T/R4" $k "seed=$((k * 100)):$((k * 7)),user-teach=$k:$k"; done
    stage_wait 90
    CO=$(cat "$D/coord.out")
    assert_match "$CO" "\\[SA4\\] excluded revealer\\(s\\): 20,30$" "two bad b reveals: both liars logged although the round is refused"
    assert_match "$CO" "round 1 not unmasked: refused: fewer than t good shares about soul [0-9]+; nothing published" "two bad b reveals: round refused"
    assert_nomatch "$CO" "AGGREGATE_SUM" "two bad b reveals: nothing published"
fi

# bad-s-reveal with a dropout, N = 7 (t = 5): soul 7 leaves after its check
# reply (in U2, not U3; v4-sa3 removes a soul that leaves right after its
# shares before any y), so its s_u is rebuilt from the six others' s
# reveals (|R| = t + 1); soul 1 alters its s reveal. v4-sa refused the
# whole round.
D="$T/badsrev"; mkdir -p "$D"
next_port
start_coord "$D" "$T/R7"
CP=$COORD_PID
if bind_ok "$D" "U4.vshares (bad s reveal)"; then
    py_soul "$D" p1 "$T/R7" 1 "seed=100:7,user-teach=1:1" --fault bad-s-reveal
    for k in 2 3 4 5 6; do py_soul "$D" p$k "$T/R7" $k "seed=$((k * 100)):$((k * 7)),user-teach=$k:$k"; done
    py_soul "$D" p7 "$T/R7" 7 "seed=7000:7000" --fault stop-after-check
    stage_wait 120
    CO=$(cat "$D/coord.out")
    assert_match "$CO" "phase 1 closed: \\|U2'\\|=7" "bad s reveal: the leaving soul sent its shares (in U2')"
    assert_match "$CO" "phase open skipped: \\|U2\\|=7" "bad s reveal: the leaving soul answered the check (in U2)"
    assert_match "$CO" "phase 2 closed: \\|U3\\|=6" "bad s reveal: it is not in U3"
    assert_match "$CO" "\\[SA4\\] excluded revealer\\(s\\): 10$" "bad s reveal: the coordinator logs the excluded revealer (id 10)"
    assert_match "$CO" "AGGREGATE_SUM round=1 tag=seed sum_promo=2100 sum_atr=147 n_part=6" "bad s reveal: seed sum over the six (the dropout's mask removed)"
    assert_match "$CO" "AGGREGATE_SUM round=1 tag=user-teach sum_promo=21 sum_atr=21 n_part=6" "bad s reveal: user-teach sum over the six"
    assert_nomatch "$CO" "not unmasked" "bad s reveal: the round is not refused"
fi

# inconsistent-deal, N = 4: soul 1 commits to an off-polynomial b-share for
# soul 2. Soul 2's check passes (the share matches the commitment), every
# reveal proof verifies, but the t verified shares do not rebuild B_1: the
# round is refused and dealer 10 is blamed.
D="$T/inconsistent"; mkdir -p "$D"
next_port
start_coord "$D" "$T/R4"
CP=$COORD_PID
if bind_ok "$D" "U4.vshares (inconsistent deal)"; then
    py_soul "$D" p1 "$T/R4" 1 "seed=100:7,user-teach=1:1" --fault inconsistent-deal
    for k in 2 3 4; do py_soul "$D" p$k "$T/R4" $k "seed=$((k * 100)):$((k * 7)),user-teach=$k:$k"; done
    stage_wait 90
    CO=$(cat "$D/coord.out")
    assert_match "$CO" "phase 3 closed: \\|U4\\|=4" "inconsistent deal: every soul accepted its shares and signed U3"
    assert_match "$CO" "round 1 not unmasked: refused: soul 10 dealt shares that do not match its commitment; nothing published" "inconsistent deal: round refused, the Python dealer (id 10) blamed"
    assert_nomatch "$CO" "AGGREGATE_SUM" "inconsistent deal: nothing published"
    assert_nomatch "$CO" "excluded revealer" "inconsistent deal: no honest revealer is excluded (the list is logged on refusal too)"
fi

# ===========================================================================
# U4.minpresent: a tag only two souls have is withheld (min-present = t = 3).
# ===========================================================================
D="$T/minpresent"; mkdir -p "$D"
next_port
start_coord "$D" "$T/R4"
CP=$COORD_PID
if bind_ok "$D" "U4.minpresent"; then
    py_soul "$D" p1 "$T/R4" 1 "seed=100:7,user-teach=1:1"
    py_soul "$D" p2 "$T/R4" 2 "seed=200:14,user-teach=2:2"
    py_soul "$D" p3 "$T/R4" 3 "seed=300:21"
    py_soul "$D" p4 "$T/R4" 4 "seed=400:28"
    stage_wait 90
    CO=$(cat "$D/coord.out")
    assert_match "$CO" "AGGREGATE_SUM round=1 tag=seed sum_promo=1000 sum_atr=70 n_part=4" "minpresent: a tag all four have is published"
    assert_match "$CO" "withheld tag user-teach: present in 2 soul\\(s\\), below min-present 3" "minpresent: a tag only two have is withheld"
    assert_nomatch "$(cat "$D/p3.out")" "tag=user-teach" "minpresent: no soul receives the withheld tag"
fi

# ===========================================================================
# U4.writeahead: a soul records the round id when the round opens, even if
# the round then fails (|U2'| < t cancels it at the shares close).
# ===========================================================================
D="$T/writeahead"; mkdir -p "$D"
next_port
start_coord "$D" "$T/R3"
CP=$COORD_PID
if bind_ok "$D" "U4.writeahead"; then
    chat_soul "$D" wa1 "$T/R3" 1
    py_soul "$D" p2 "$T/R3" 2 "seed=1:1"
    py_soul "$D" p3 "$T/R3" 3 "seed=1:1" --fault stop-after-adv
    stage_wait 120
    CO=$(cat "$D/coord.out")
    assert_match "$CO" "cancelled: \\|U2'\\| 2 below t; nothing published" "writeahead: the round is cancelled at U2'"
    LR=$(ls "$T/chatrun_wa1" 2>/dev/null | grep '^crossengin_sa4_last_round_[0-9a-f]*_10$' | head -1)
    assert_match "$(cat "$T/chatrun_wa1/$LR" 2>/dev/null)" " 10 1$" "writeahead: the chat soul saved round 1 although the round failed"
    assert_match "$(cat "$D/wa1.out")" "round not completed" "writeahead: the chat soul reports the failed round"
fi

# ===========================================================================
# U4.layout: a soul with another tag set.
# ===========================================================================
D="$T/layout"; mkdir -p "$D"
next_port
start_coord "$D" "$T/R4"
CP=$COORD_PID
if bind_ok "$D" "U4.layout"; then
    for k in 1 2 3; do py_soul "$D" p$k "$T/R4" $k "seed=$((k * 100)):$((k * 7)),user-teach=$k:$k"; done
    PYTAGS="seed,topic:other" py_soul "$D" p4 "$T/R4" 4 "seed=9:9"
    stage_wait 90
    CO=$(cat "$D/coord.out")
    assert_match "$(cat "$D/p4.out")" "refused: vector layout differs" "a soul with another tag set refuses the round"
    assert_match "$CO" "phase 0 closed: \\|U1\\|=3" "it is not in U1"
    assert_match "$CO" "AGGREGATE_SUM round=1 tag=seed sum_promo=600 sum_atr=42 n_part=3" "layout: round over the other three"
fi

# ===========================================================================
# U4.join: unknown id, duplicate id, too few souls.
# ===========================================================================
D="$T/join"; mkdir -p "$D"
next_port
start_coord "$D" "$T/R3" CE_SECAGG_V4_JOIN_MS=6000
CP=$COORD_PID
if bind_ok "$D" "U4.join"; then
    python3 -I - "$PORT" > "$D/raw.out" 2>&1 <<'PYEOF'
import socket, sys
s = socket.create_connection(("127.0.0.1", int(sys.argv[1])), timeout=10)
f = s.makefile("rb")
s.sendall(b"SECAGG_HELLO ce-fed v4-sa3\n"); print(f.readline().decode().strip())
s.sendall(b"FED_JOIN 999 1000\n"); print(f.readline().decode().strip())
PYEOF
    py_soul "$D" p1 "$T/R3" 1 "seed=1:1"
    sleep 1
    py_soul "$D" p1b "$T/R3" 1 "seed=1:1"
    stage_wait 60
    CO=$(cat "$D/coord.out")
    assert_match "$(cat "$D/raw.out")" "ERR id 999 is not in the roster" "an id not in the roster is rejected"
    assert_match "$CO" "REJECT handshake: id 10 has already joined" "a second connection with a joined id is rejected"
    assert_match "$CO" "REFUSE round: only 1 soul\\(s\\) joined, below t = 3" "too few souls: no round"
    assert_match "$CO" "coord-exit=1" "coordinator exits 1 without a round"
fi

# ===========================================================================
# U4.refuse: configuration refusals and cross-version hellos.
# ===========================================================================
D="$T/refuse"; mkdir -p "$D/run"; chmod 700 "$D" "$D/run"
coord_once() {   # coord_once <ENV=VAL...> -> output
    ( export CE_RUN_DIR="$D/run" CE_FED_PORT="$PORT" CE_FED_BIND=127.0.0.1 CE_SECAGG_ENABLED=1
      export CE_SECAGG_MODE=v4 CE_SECAGG_ROSTER="$T/R3" CE_SECAGG_V4_TAGS="$TAGS"
      for kv in "$@"; do export "$kv"; done
      timeout 20 "$COORD_BIN" 2>&1; echo "exit=$?" )
}
OUT=$(coord_once CE_SECAGG_ENABLED=0)
assert_match "$OUT" "REFUSE: CE_SECAGG_MODE is set but CE_SECAGG_ENABLED is not 1" "coordinator: v4 without CE_SECAGG_ENABLED refused (no plain v1 fallback)"
OUT=$(coord_once CE_SECAGG_MODE=v5)
assert_match "$OUT" "REFUSE: CE_SECAGG_MODE must be v3n-sa or v4" "coordinator: unknown mode refused"
assert_match "$OUT" "exit=1" "coordinator: unknown mode exits 1"
OUT=$(coord_once CE_SECAGG_ALLOW_RECON=1)
assert_match "$OUT" "REFUSE: CE_SECAGG_ALLOW_RECON is not used in v4" "coordinator: reconciliation flag refused in v4"
OUT=$(coord_once CE_SECAGG_V4_TAGS=)
assert_match "$OUT" "REFUSE: CE_SECAGG_V4_TAGS is empty" "coordinator: tags required"
OUT=$(coord_once CE_FED_SOULS=2)
assert_match "$OUT" "below the roster threshold t = 3" "coordinator: CE_FED_SOULS below t refused"
OUT=$(coord_once CE_SECAGG_ROSTER="$T/missing")
assert_match "$OUT" "REFUSE: roster: .*not found" "coordinator: missing roster refused"

chat_once() {   # chat_once <name> <ENV=VAL...> -> output (no coordinator)
    local name="$1"; shift
    ( export CE_RUN_DIR="$T/chatrun_$name"; mkdir -p "$CE_RUN_DIR"; chmod 700 "$CE_RUN_DIR"
      export CE_SECAGG_ENABLED=1 CE_SECAGG_MODE=v4 CE_SECAGG_ROSTER="$T/R3" CE_SECAGG_ID_KEY="$T/k1.priv"
      export CE_SECAGG_V4_TAGS="$TAGS" CE_SESSION_ID="$name" CE_SNAP_PATH="$D/$name.snap" CE_DLOG_PATH="$D/$name.dlog"
      for kv in "$@"; do export "$kv"; done
      printf '/cap grant network_send\n/fed_join 127.0.0.1:%s\n/quit\n' "$PORT" | timeout 60 "$CHAT_BIN" 2>&1 )
}
OUT=$(chat_once r0 CE_SECAGG_ENABLED=0)
assert_match "$OUT" "refusing: CE_SECAGG_MODE is set but CE_SECAGG_ENABLED is not 1" "chat: v4 without CE_SECAGG_ENABLED refused (no plain v1 fallback)"
OUT=$(chat_once r1 CE_SECAGG_MODE=v5)
assert_match "$OUT" "fed_join: \\[SA4\\] refusing: CE_SECAGG_MODE must be v3n-sa or v4" "chat: unknown mode refused"
OUT=$(chat_once r2 CE_FED_SOUL_ID=someone)
assert_match "$OUT" "refusing: CE_FED_SOUL_ID someone is not this identity's roster name soul1" "chat: CE_FED_SOUL_ID must be the roster name"
OUT=$(chat_once r3 CE_SECAGG_ALLOW_RECON=1)
assert_match "$OUT" "refusing: CE_SECAGG_ALLOW_RECON is not used in v4" "chat: reconciliation flag refused in v4"
OUT=$(chat_once r4 CE_SECAGG_ID_KEY="$T/k5.priv")
assert_match "$OUT" "refusing: identity: this key .* is not in the roster" "chat: an identity not in the roster is refused"
mkdir -p "$T/chatrun_r5"; chmod 700 "$T/chatrun_r5"
FP=$(sed -n 's/.*roster fp=\([0-9a-f]*\) .*/\1/p' "$T/mixed/soul1.out" | head -1)
if [ -n "$FP" ]; then
    printf 'crossengin-sa4-last-round v1 %s 10 x\n' "$FP" > "$T/chatrun_r5/crossengin_sa4_last_round_${FP:0:16}_10"
    chmod 600 "$T/chatrun_r5/crossengin_sa4_last_round_${FP:0:16}_10"
    OUT=$(chat_once r5)
    assert_match "$OUT" "refusing: last round: .*corrupt" "chat: a corrupt last-round file is refused (never reset)"
fi

# v3n-sa chat -> v4 coordinator, v4 Python soul -> v3n-sa coordinator.
D="$T/cross"; mkdir -p "$D"
next_port
start_coord "$D" "$T/R3" CE_SECAGG_V4_JOIN_MS=8000
CP=$COORD_PID
if bind_ok "$D" "U4.cross"; then
    OUT=$( export CE_RUN_DIR="$T/chatrun_v3"; mkdir -p "$CE_RUN_DIR"; chmod 700 "$CE_RUN_DIR"
           export CE_SECAGG_ENABLED=1 CE_SECAGG_PEERS=bob CE_FED_TOKEN_bob=tok CE_FED_SOUL_ID=alice CE_SESSION_ID=alice
           export CE_SNAP_PATH="$D/a.snap" CE_DLOG_PATH="$D/a.dlog"
           printf '/cap grant network_send\n/fed_join 127.0.0.1:%s\n/quit\n' "$PORT" | timeout 60 "$CHAT_BIN" 2>&1 )
    assert_match "$OUT" "ERROR cannot connect / SecAgg handshake" "v3n-sa chat refuses a v4 coordinator"
    stage_wait 40
    assert_match "$(cat "$D/coord.out")" "REJECT handshake: expected SECAGG_HELLO ce-fed v4-sa3" "v4 coordinator rejects the v3n-sa hello"
fi
# A v4-sa (v1) soul and a v4-sa2 soul -> a v4-sa3 coordinator: refused at
# the hello (no fallback, never a mid-round bad_sig).
D="$T/crossv1"; mkdir -p "$D"
next_port
start_coord "$D" "$T/R3" CE_SECAGG_V4_JOIN_MS=5000
CP=$COORD_PID
if bind_ok "$D" "U4.cross (v1 / v4-sa2 hello)"; then
    python3 -I - "$PORT" > "$D/raw.out" 2>&1 <<'PYEOF'
import socket, sys
for v in ("v4-sa", "v4-sa2"):
    s = socket.create_connection(("127.0.0.1", int(sys.argv[1])), timeout=10)
    f = s.makefile("rb")
    s.sendall(("SECAGG_HELLO ce-fed %s\n" % v).encode())
    print("reply_%s=%s" % (v, f.readline().decode().strip()))
    s.close()
PYEOF
    stage_wait 40
    CO=$(cat "$D/coord.out")
    assert_eq "$(grep -c 'REJECT handshake: expected SECAGG_HELLO ce-fed v4-sa3' "$D/coord.out")" "2" "v4-sa3 coordinator rejects the v4-sa (v1) and v4-sa2 hellos"
    assert_match "$(cat "$D/raw.out")" "reply_v4-sa=ERR expected SECAGG_HELLO ce-fed v4-sa3" "the v1 soul gets an ERR naming the v4-sa3 hello, no OK"
    assert_match "$(cat "$D/raw.out")" "reply_v4-sa2=ERR expected SECAGG_HELLO ce-fed v4-sa3" "the v4-sa2 soul gets an ERR naming the v4-sa3 hello, no OK"
    assert_nomatch "$CO" "JOIN id=" "neither old soul joins"
fi
# v4-sa3 souls -> a v4-sa2 coordinator (a stand-in that answers every hello
# with the v4-sa2 OK): the Python soul and the chat soul both refuse.
D="$T/crossv1b"; mkdir -p "$D"
next_port
python3 -I - "$PORT" > "$D/fake.out" 2>&1 <<'PYEOF' &
import socket, sys
srv = socket.socket(); srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", int(sys.argv[1]))); srv.listen(4); srv.settimeout(40)
for _ in range(2):
    c, _a = srv.accept(); c.settimeout(20)
    f = c.makefile("rb")
    hello = f.readline().decode().strip()
    print("hello=" + hello, flush=True)
    c.sendall(b"OK ce-fed v4-sa2 protocol accepted\n")
    try:
        print("next=" + f.readline().decode().strip(), flush=True)
    except OSError:
        print("next=(none)", flush=True)
    c.close()
PYEOF
FK=$!; PIDS+=("$FK")
sleep 0.5
py_soul "$D" p1 "$T/R3" 1 "seed=1:1"
wait "$PY_PID" 2>/dev/null
assert_match "$(cat "$D/p1.out")" "handshake refused" "v4-sa3 Python soul refuses a v4-sa2 coordinator"
OUT=$( export CE_RUN_DIR="$T/chatrun_v1b"; mkdir -p "$CE_RUN_DIR"; chmod 700 "$CE_RUN_DIR"
       export CE_SECAGG_ENABLED=1 CE_SECAGG_MODE=v4 CE_SECAGG_ROSTER="$T/R3" CE_SECAGG_ID_KEY="$T/k2.priv"
       export CE_SECAGG_V4_TAGS="$TAGS" CE_SESSION_ID=v1b CE_SNAP_PATH="$D/v1b.snap" CE_DLOG_PATH="$D/v1b.dlog"
       printf '/cap grant network_send\n/fed_join 127.0.0.1:%s\n/quit\n' "$PORT" | timeout 60 "$CHAT_BIN" 2>&1 )
assert_match "$OUT" "fed_join: ERROR cannot connect / v4 handshake" "v4-sa3 chat soul refuses a v4-sa2 coordinator"
assert_match "$OUT" "enabled \\(v4-sa3 double masking, verifiable shares and blame\\)" "chat soul status names v4-sa3"
wait_all 30 "$FK"
assert_eq "$(grep -c '^hello=SECAGG_HELLO ce-fed v4-sa3$' "$D/fake.out")" "2" "both souls sent the v4-sa3 hello"
assert_nomatch "$(cat "$D/fake.out")" "next=FED_JOIN" "neither soul sent FED_JOIN after the v4-sa2 OK"
D="$T/cross2"; mkdir -p "$D/run"; chmod 700 "$D" "$D/run"
next_port
( export CE_RUN_DIR="$D/run" CE_FED_PORT="$PORT" CE_FED_BIND=127.0.0.1 CE_FED_SOULS=2 CE_FED_MAX_ROUNDS=1 CE_SECAGG_ENABLED=1
  timeout 20 "$COORD_BIN" > "$D/coord.out" 2>&1 ) &
CP=$!; PIDS+=("$CP")
sleep 1
py_soul "$D" p1 "$T/R3" 1 "seed=1:1"
wait "$PY_PID" 2>/dev/null
assert_match "$(cat "$D/p1.out")" "handshake refused" "v4 soul refuses a v3n-sa coordinator"
kill -9 "$CP" 2>/dev/null; wait "$CP" 2>/dev/null

finish
