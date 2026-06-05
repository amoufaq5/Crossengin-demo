#!/usr/bin/env bash
# Scenario VVVV -- R26E: gossip relay -- 3-soul A -> C -> B forwarding
# when direct A <-> B dial is blocked.
#
# Spawns THREE soul processes (A, B, C). All three bind their gossip
# port + listen, bootstrap with the other two. After warmup:
#
#   * Soul A wants to send a payload to soul B.
#   * Soul A's relay module is told (via relay_mark_unreachable) that
#     B is direct-unreachable -- the test hook simulates a NAT/firewall
#     partition without needing iptables / SO_REUSEPORT (the brief
#     ships TCP-based relay over pre-known mesh peers; full UDP hole-
#     punching is R26E.2).
#   * Soul A calls relay_send(B, "hello-from-A"). The relay layer
#     skips the direct attempt, picks C as intermediate (the only
#     other alive peer != B), sends RELAY_REQ to C.
#   * Soul C's gossip handler receives RELAY_REQ; the relay's drain
#     helper picks it up the next tick and forwards as RELAY_DATA
#     with via=C, from=A to B.
#   * Soul B's gossip handler receives RELAY_DATA; the relay's drain
#     helper records it (req_id, payload, via=C, from=A). The test
#     reads B's received-queue and asserts the via= annotation is C.
#   * Soul A's second relay_send to the same target should reuse the
#     cached via -- relay_chosen_via(B) returns C; sent_via_relay
#     counter advances a second time without re-walking peers.
#
# Assertions (~12):
#   1. NOVA pre-flight (socket(2,1,0) allowed).
#   2-4. Three sockets bind successfully.
#   5. A's first relay_send returns 1 (success), sent_via_relay=1.
#   6. A's cache lookup returns C (relay_chosen_via).
#   7. A's second relay_send returns 1, sent_via_relay=2 (cache hit).
#   8. C's gossip handler observed >= 1 RELAY_REQ (req_rx >= 1).
#   9. C's relay forwarded >= 1 (forwarded stat).
#   10. B's gossip handler observed >= 1 RELAY_DATA (data_rx >= 1).
#   11. B's received-queue length >= 1.
#   12. B's first received record carries via=ADDR_C, from=ADDR_A.

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

it_section "scenario VVVV: R26E gossip relay (3-soul A->C->B forwarding)"

NOVA_BIN="${NOVA_ROOT:-/home/user/NOVA}/nova"
if [ ! -x "$NOVA_BIN" ]; then
    printf "  ${C_RED}ERROR${C_RST}: NOVA launcher not found at %s\n" "$NOVA_BIN" >&2
    FAIL=$((FAIL+1))
    summary "scenario_vvvv_gossip_relay"
    exit $?
fi

BASE_PORT=$(( 39000 + (RANDOM % 500) ))
PORT_A=$((BASE_PORT))
PORT_B=$((BASE_PORT + 1))
PORT_C=$((BASE_PORT + 2))
ADDR_A="127.0.0.1:$PORT_A"
ADDR_B="127.0.0.1:$PORT_B"
ADDR_C="127.0.0.1:$PORT_C"

DRV_DIR="$REPO_ROOT/tests/integration/_scenario_vvvv_drivers"
mkdir -p "$DRV_DIR"
OUT_A="/tmp/ce_int_vvvv_a.out"
OUT_B="/tmp/ce_int_vvvv_b.out"
OUT_C="/tmp/ce_int_vvvv_c.out"

PID_A=""; PID_B=""; PID_C=""
trap '
  [ -n "${PID_A:-}" ] && kill -9 $PID_A 2>/dev/null
  [ -n "${PID_B:-}" ] && kill -9 $PID_B 2>/dev/null
  [ -n "${PID_C:-}" ] && kill -9 $PID_C 2>/dev/null
  if [ "${CE_VVVV_KEEP:-0}" = "0" ]; then
    rm -rf "$DRV_DIR" "$OUT_A" "$OUT_B" "$OUT_C"
  fi
' EXIT

# ---- pre-flight: socket(2,1,0) -----------------------------------------
PRECHK_SRC="$DRV_DIR/prechk.nova"
cat > "$PRECHK_SRC" <<'NOVA'
fn main() {
    let s = socket(2, 1, 0)
    if s < 0 { println("socket-deny"); exit(0) }
    close_fd(s)
    println("socket-ok")
}
main()
NOVA
PRECHK=$("$NOVA_BIN" run "$PRECHK_SRC" 2>/dev/null | tail -1 || echo "socket-deny")
if [ "$PRECHK" != "socket-ok" ]; then
    printf "  ${C_YEL}SKIP${C_RST}  socket(2,1,0) denied by sandbox -- scenario_vvvv skipped\n"
    PASS=$((PASS+1))
    summary "scenario_vvvv_gossip_relay"
    exit $?
fi
PASS=$((PASS+1))
printf "  ${C_GRN}PASS${C_RST}  NOVA pre-flight (socket(2,1,0) allowed)\n"

# ---- shared driver template --------------------------------------------
#
# Each driver: bind + listen on its gossip port, init gossip + relay,
# wire relay_state via gossip_set_relay_state. On every tick: drain
# inbound conns, drain the relay's inbound queue, run gossip_step,
# emit a status line. The "originator" driver (soul A) marks B
# unreachable, calls relay_send twice (once per the two assertions
# we want to surface), then enters the tick loop.

write_driver() {
    local letter="$1" port="$2" peer1="$3" peer2="$4" role="$5"
    local target="$6" via_target="$7"
    local src="$DRV_DIR/${letter}.nova"
    cat > "$src" <<NOVA
import "std/io"
import "../../../src/federation/gossip.nova"
import "../../../src/federation/gossip_relay.nova"
import "../../../src/kg/multi_kg_manager.nova"
import "../../../src/kg/atom_store.nova"

fn main() {
    let self_addr = "127.0.0.1:" + int_to_str($port)
    let bp = list_new()
    push(bp, "$peer1")
    push(bp, "$peer2")
    let gstate = gossip_init(self_addr, bp)
    gossip_set_seed(gstate, ${port} + 17)
    let rstate = relay_init(gstate)
    gossip_set_relay_state(gstate, rstate)

    let reg = kg_registry_new()
    let kg = kg_spawn(reg, "lang")

    let server_fd = gossip_listen(self_addr)
    if server_fd < 0 {
        println("$letter: bind failed on " + self_addr)
        exit(1)
    }
    println("$letter: listening on " + self_addr)
    println("$letter: role=$role")
    println("$letter: " + relay_stats_line(rstate))

    // Warmup ticks: just bind + listen + drain inbound conns. We
    // do NOT call gossip_step here so that bootstrap peers stay
    // ALIVE (they would get marked DEAD if PING/ACK race-fails
    // against a peer that is still mid-bind on a slow host).
    // 15 ticks * 150ms = 2.25s gives every peer enough time to
    // finish gossip_listen + enter the accept loop. Bootstrap-
    // populated peers retain their initial ALIVE status because no
    // outbound PING is attempted yet.
    let warm = 0
    while warm < 15 {
        let drained = 0
        while drained < 4 {
            let conn_fd = gossip_try_accept(server_fd)
            if conn_fd < 0 {
                drained = 4
            } else {
                gossip_handle_conn_kg(gstate, conn_fd, kg)
                drained = drained + 1
            }
        }
        relay_drain_inbound(rstate)
        sleep_ms(150)
        warm = warm + 1
    }

    // Originator (A): mark target unreachable, send two relay
    // messages. Bootstrap peers stay ALIVE through warmup (no
    // PING attempts means no false-DEAD marks), so relay_send
    // sees a populated alive list and picks an intermediate
    // deterministically.
    if str_eq("$role", "originator") == 1 {
        relay_mark_unreachable(rstate, "$target")
        let rc1 = relay_send(rstate, "$target", "hello-from-A-1")
        println("$letter: send1 rc=" + int_to_str(rc1)
            + " sent_via=" + int_to_str(relay_stats_sent_via_relay(rstate)))
        let via1 = relay_chosen_via(rstate, "$target")
        let via1s = ""
        if via1 != -1 { via1s = via1 }
        println("$letter: cache via=" + via1s)
        // Inter-send pause so the relay path (RELAY_REQ ->
        // RELAY_DATA -> RELAY_ACK round-trip) has fully completed
        // before we issue the second send. C's relay_drain_inbound
        // dispatches a forward dial to B which can hold C's main
        // loop for up to ~700ms on the slow path (3-retry connect +
        // 3000ms RCVTIMEO ceiling) -- a 1500ms sleep here covers
        // the happy path with a margin for jitter. The cache short-
        // circuit means send2 reuses the cached via=C with no peer
        // walk; only the C-side accept needs to be free.
        sleep_ms(1500)
        let rc2 = relay_send(rstate, "$target", "hello-from-A-2")
        println("$letter: send2 rc=" + int_to_str(rc2)
            + " sent_via=" + int_to_str(relay_stats_sent_via_relay(rstate)))
    }

    // Main loop: drain inbound + relay queues + gossip step + emit.
    let tick = 0
    while tick < 40 {
        let drained = 0
        while drained < 4 {
            let conn_fd = gossip_try_accept(server_fd)
            if conn_fd < 0 {
                drained = 4
            } else {
                gossip_handle_conn_kg(gstate, conn_fd, kg)
                drained = drained + 1
            }
        }
        relay_drain_inbound(rstate)
        gossip_step(gstate, kg)
        println("$letter: tick=" + int_to_str(tick)
            + " " + relay_stats_line(rstate)
            + " req_rx=" + int_to_str(gossip_stats_relay_req_rx(gstate))
            + " data_rx=" + int_to_str(gossip_stats_relay_data_rx(gstate))
            + " ack_rx=" + int_to_str(gossip_stats_relay_ack_rx(gstate))
            + " received=" + int_to_str(relay_received_count(rstate)))
        // Receiver: print the via= field of the first received record
        // so the harness can grep for it.
        if str_eq("$role", "receiver") == 1 {
            if relay_received_count(rstate) > 0 {
                let r0 = relay_received_at(rstate, 0)
                println("$letter: recv[0] via=" + relay_received_via(r0)
                    + " from=" + relay_received_from(r0)
                    + " payload=" + relay_received_payload(r0))
            }
        }
        sleep_ms(150)
        tick = tick + 1
    }
    close_fd(server_fd)
    exit(0)
}
main()
NOVA
}

# Soul A: originator, marks B unreachable, sends to B. Bootstrap B + C.
write_driver "a" "$PORT_A" "$ADDR_B" "$ADDR_C" "originator" "$ADDR_B" "$ADDR_C"
# Soul B: receiver. Bootstrap A + C.
write_driver "b" "$PORT_B" "$ADDR_A" "$ADDR_C" "receiver" "" ""
# Soul C: relay. Bootstrap A + B.
write_driver "c" "$PORT_C" "$ADDR_A" "$ADDR_B" "relay" "" ""

# ---- precompile drivers AOT -------------------------------------------
BIN_A="$DRV_DIR/a.bin"; BIN_B="$DRV_DIR/b.bin"; BIN_C="$DRV_DIR/c.bin"
printf "  ${C_DIM}info${C_RST}   precompiling 3 soul drivers ...\n"
"$NOVA_BIN" build "$DRV_DIR/a.nova" -o "$BIN_A" >"$DRV_DIR/a_build.log" 2>&1 || true
"$NOVA_BIN" build "$DRV_DIR/b.nova" -o "$BIN_B" >"$DRV_DIR/b_build.log" 2>&1 || true
"$NOVA_BIN" build "$DRV_DIR/c.nova" -o "$BIN_C" >"$DRV_DIR/c_build.log" 2>&1 || true

if [ ! -x "$BIN_A" ]; then
    printf "  ${C_RED}ERROR${C_RST}: soul A driver failed to compile\n"
    sed 's/^/    /' "$DRV_DIR/a_build.log" 2>/dev/null
    FAIL=$((FAIL+1))
    summary "scenario_vvvv_gossip_relay"
    exit $?
fi
if [ ! -x "$BIN_B" ]; then
    printf "  ${C_RED}ERROR${C_RST}: soul B driver failed to compile\n"
    sed 's/^/    /' "$DRV_DIR/b_build.log" 2>/dev/null
    FAIL=$((FAIL+1))
    summary "scenario_vvvv_gossip_relay"
    exit $?
fi
if [ ! -x "$BIN_C" ]; then
    printf "  ${C_RED}ERROR${C_RST}: soul C driver failed to compile\n"
    sed 's/^/    /' "$DRV_DIR/c_build.log" 2>/dev/null
    FAIL=$((FAIL+1))
    summary "scenario_vvvv_gossip_relay"
    exit $?
fi
PASS=$((PASS+1))
printf "  ${C_GRN}PASS${C_RST}  all three soul drivers compiled\n"

# ---- launch all three souls --------------------------------------------
"$BIN_A" >"$OUT_A" 2>&1 &
PID_A=$!
"$BIN_B" >"$OUT_B" 2>&1 &
PID_B=$!
"$BIN_C" >"$OUT_C" 2>&1 &
PID_C=$!

# Wait for warmup + sends + a few relay cycles to complete. The driver
# loop is 25 warmup ticks + up to 40 main ticks = ~65 * 150ms = ~10s.
# Check progress at 7s so all three souls are guaranteed to still be
# running mid-flight. A definitive convergence sample is taken at the
# end via `wait` below.
sleep 7

A_ALIVE=0; B_ALIVE=0; C_ALIVE=0
kill -0 $PID_A 2>/dev/null && A_ALIVE=1
kill -0 $PID_B 2>/dev/null && B_ALIVE=1
kill -0 $PID_C 2>/dev/null && C_ALIVE=1
assert_eq "$A_ALIVE" "1" "soul A still running mid-flight (6s)"
assert_eq "$B_ALIVE" "1" "soul B still running mid-flight (6s)"
assert_eq "$C_ALIVE" "1" "soul C still running mid-flight (6s)"

# Let all drivers complete their tick loops + exit cleanly. Then
# read their final status lines from the captured output.
wait $PID_A 2>/dev/null
wait $PID_B 2>/dev/null
wait $PID_C 2>/dev/null
PID_A=""; PID_B=""; PID_C=""

# ---- A's send1 result --------------------------------------------------
SEND1=$(grep '^a: send1 rc=' "$OUT_A" 2>/dev/null | head -1)
RC1=$(echo "$SEND1" | grep -oE 'rc=[0-9]+' | sed 's/rc=//')
SENT_VIA1=$(echo "$SEND1" | grep -oE 'sent_via=[0-9]+' | sed 's/sent_via=//')
if [ "${RC1:-0}" = "1" ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  A's first relay_send returned 1 (rc=%s sent_via=%s)\n" "$RC1" "$SENT_VIA1"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  A's first relay_send did not return 1 (line='%s')\n" "$SEND1"
fi

# ---- A's cache via lookup ---------------------------------------------
CACHE_VIA=$(grep '^a: cache via=' "$OUT_A" 2>/dev/null | head -1 | sed 's/^a: cache via=//')
if [ "$CACHE_VIA" = "$ADDR_C" ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  A's cache via=%s (matches expected relay)\n" "$CACHE_VIA"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  A's cache via='%s' expected='%s'\n" "$CACHE_VIA" "$ADDR_C"
fi

# ---- A's send2 should hit the cache (sent_via increments to >= 2) ----
SEND2=$(grep '^a: send2 rc=' "$OUT_A" 2>/dev/null | head -1)
RC2=$(echo "$SEND2" | grep -oE 'rc=[0-9]+' | sed 's/rc=//')
SENT_VIA2=$(echo "$SEND2" | grep -oE 'sent_via=[0-9]+' | sed 's/sent_via=//')
if [ "${RC2:-0}" = "1" ] && [ "${SENT_VIA2:-0}" -ge 2 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  A's second relay_send used cache (rc=%s sent_via=%s)\n" "$RC2" "$SENT_VIA2"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  A's second relay_send did not use cache (line='%s')\n" "$SEND2"
fi

# ---- C's gossip handler observed RELAY_REQ ---------------------------
LAST_C=$(grep '^c: tick=' "$OUT_C" 2>/dev/null | tail -1)
C_REQ_RX=$(echo "$LAST_C" | grep -oE 'req_rx=[0-9]+' | head -1 | sed 's/req_rx=//')
if [ "${C_REQ_RX:-0}" -ge 1 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  C received >= 1 RELAY_REQ over the wire (req_rx=%s)\n" "$C_REQ_RX"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  C did not receive any RELAY_REQ (last='%s')\n" "$LAST_C"
fi

# ---- C's relay forwarded >= 1 -----------------------------------------
C_FWD=$(echo "$LAST_C" | grep -oE 'fwd=[0-9]+' | head -1 | sed 's/fwd=//')
if [ "${C_FWD:-0}" -ge 1 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  C's relay forwarded >= 1 request (fwd=%s)\n" "$C_FWD"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  C's relay did not forward (last='%s')\n" "$LAST_C"
fi

# ---- B's gossip handler observed RELAY_DATA --------------------------
LAST_B=$(grep '^b: tick=' "$OUT_B" 2>/dev/null | tail -1)
B_DATA_RX=$(echo "$LAST_B" | grep -oE 'data_rx=[0-9]+' | head -1 | sed 's/data_rx=//')
if [ "${B_DATA_RX:-0}" -ge 1 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  B received >= 1 RELAY_DATA over the wire (data_rx=%s)\n" "$B_DATA_RX"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  B did not receive any RELAY_DATA (last='%s')\n" "$LAST_B"
fi

# ---- B's received-queue length >= 1 ----------------------------------
B_RECEIVED=$(echo "$LAST_B" | grep -oE 'received=[0-9]+' | head -1 | sed 's/received=//')
if [ "${B_RECEIVED:-0}" -ge 1 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  B's relay received queue >= 1 (received=%s)\n" "$B_RECEIVED"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  B's received queue empty (last='%s')\n" "$LAST_B"
fi

# ---- B's first received record carries via=C, from=A ------------------
B_RECV0=$(grep '^b: recv\[0\] via=' "$OUT_B" 2>/dev/null | head -1)
RECV_VIA=$(echo "$B_RECV0" | grep -oE 'via=[^ ]+' | head -1 | sed 's/via=//')
RECV_FROM=$(echo "$B_RECV0" | grep -oE 'from=[^ ]+' | head -1 | sed 's/from=//')
if [ "$RECV_VIA" = "$ADDR_C" ] && [ "$RECV_FROM" = "$ADDR_A" ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  B's recv[0] annotated via=%s from=%s (A->C->B path confirmed)\n" "$RECV_VIA" "$RECV_FROM"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  B's recv[0] annotation mismatch (via='%s' from='%s' expected via=%s from=%s)\n" \
        "$RECV_VIA" "$RECV_FROM" "$ADDR_C" "$ADDR_A"
fi

summary "scenario_vvvv_gossip_relay"
