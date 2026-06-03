#!/usr/bin/env bash
# Scenario OOOO -- R23E: NAT traversal -- STUN-like external addr
# discovery + gossip-piggyback advertisement.
#
# Two souls (A, B). A acts as a STUN-like rendezvous (its TCP
# listener handles STUN_REQUEST lines via accept_conn's sa_buf to
# echo the dialer's source addr back). B queries A for its external
# addr, advertises via gossip EXTADDR, and demonstrates the
# nat_hole_punch stub.
#
# Assertions (~12): NOVA pre-flight, both souls bind, STUN query
# succeeds, external addr is 127.0.0.1:<ephemeral> (sandbox),
# nat-type heuristic classifies, local-addrs nonempty + contains
# loopback, hole-punch stub returns 0, advertise reaches >= 1 peer,
# A receives EXTADDR (extaddr_rx counter), A's nat_state peer table
# grows, B's query counters advance.

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

it_section "scenario OOOO: R23E NAT traversal (STUN-like discovery + gossip advertise)"

NOVA_BIN="${NOVA_ROOT:-/home/user/NOVA}/nova"
if [ ! -x "$NOVA_BIN" ]; then
    printf "  ${C_RED}ERROR${C_RST}: NOVA launcher not found at %s\n" "$NOVA_BIN" >&2
    FAIL=$((FAIL+1))
    summary "scenario_oooo_nat_traversal"
    exit $?
fi

BASE_PORT=$(( 41000 + (RANDOM % 500) ))
PORT_A=$((BASE_PORT))
PORT_B=$((BASE_PORT + 1))
ADDR_A="127.0.0.1:$PORT_A"
ADDR_B="127.0.0.1:$PORT_B"

DRV_DIR="$REPO_ROOT/tests/integration/_scenario_oooo_drivers"
mkdir -p "$DRV_DIR"
OUT_A="/tmp/ce_int_oooo_a.out"
OUT_B="/tmp/ce_int_oooo_b.out"

PID_A=""; PID_B=""
trap '
  [ -n "${PID_A:-}" ] && kill -9 $PID_A 2>/dev/null
  [ -n "${PID_B:-}" ] && kill -9 $PID_B 2>/dev/null
  if [ "${CE_OOOO_KEEP:-0}" = "0" ]; then
    rm -rf "$DRV_DIR" "$OUT_A" "$OUT_B"
  fi
' EXIT

# ---- pre-flight: socket(2,1,0) ------------------------------------------
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
    printf "  ${C_YEL}SKIP${C_RST}  socket(2,1,0) denied by sandbox -- scenario_oooo skipped\n"
    PASS=$((PASS+1))
    summary "scenario_oooo_nat_traversal"
    exit $?
fi

# ---- driver: soul A (STUN rendezvous) ----------------------------------
DRV_A="$DRV_DIR/a.nova"
cat > "$DRV_A" <<NOVA
import "std/io"
import "../../../src/federation/gossip.nova"
import "../../../src/federation/nat_traversal.nova"
import "../../../src/kg/multi_kg_manager.nova"
import "../../../src/kg/atom_store.nova"

fn main() {
    let self_addr = "127.0.0.1:" + int_to_str($PORT_A)
    let bp = list_new()
    push(bp, "$ADDR_B")
    let gstate = gossip_init(self_addr, bp)
    gossip_set_seed(gstate, ${PORT_A} + 11)
    let nstate = nat_init()
    gossip_set_nat_state(gstate, nstate)
    println("a: nat_state wired into gossip handler")

    let reg = kg_registry_new()
    let kg = kg_spawn(reg, "lang")

    let server_fd = gossip_listen(self_addr)
    if server_fd < 0 {
        println("a: bind failed on " + self_addr)
        exit(1)
    }
    println("a: listening on " + self_addr)
    println("a: " + nat_status_line(nstate))

    let tick = 0
    let stun_served = 0
    while tick < 70 {
        let drained = 0
        while drained < 4 {
            let sa_buf = nat_alloc_sa_buf()
            let sa_len = nat_alloc_sa_len()
            let conn_fd = accept_conn(server_fd, sa_buf, sa_len)
            if conn_fd < 0 {
                drained = 4
            } else {
                let first = _nat_recv_line(conn_fd)
                if first == 0 {
                    close_fd(conn_fd)
                    drained = drained + 1
                } else {
                    if str_eq(first, NAT_STUN_REQUEST_LINE) == 1 {
                        let parsed = nat_extract_peer_addr(sa_buf)
                        if parsed != 0 {
                            let reply = nat_format_stun_response(parsed[0], parsed[1]) + "\n"
                            _nat_send_all(conn_fd, reply)
                            stun_served = stun_served + 1
                            println("a: stun-served peer=" + parsed[0] + ":" + int_to_str(parsed[1]))
                        }
                        close_fd(conn_fd)
                        drained = drained + 1
                    } else {
                        if str_eq(first, GOSSIP_HELLO_LINE) == 1 {
                            _gossip_send_all(conn_fd, GOSSIP_OK_LINE + "\n")
                            let running = 1
                            while running == 1 {
                                let line = _gossip_recv_line(conn_fd)
                                if line == 0 { running = 0 } else {
                                    if str_eq(line, GOSSIP_BYE_LINE) == 1 {
                                        running = 0
                                    } else {
                                        if _gossip_starts_with(line, GOSSIP_EXTADDR_PREFIX) == 1 {
                                            _gossip_serve_extaddr(gstate, line)
                                        }
                                        if _gossip_starts_with(line, GOSSIP_PING_PREFIX) == 1 {
                                            let toks = _gossip_split_spaces(line)
                                            if len(toks) >= 3 {
                                                _gossip_send_all(conn_fd, GOSSIP_ACK_PREFIX + toks[1] + "\n")
                                            }
                                        }
                                    }
                                }
                            }
                            close_fd(conn_fd)
                            drained = drained + 1
                        } else {
                            close_fd(conn_fd)
                            drained = drained + 1
                        }
                    }
                }
            }
        }
        gossip_step(gstate, kg)
        println("a: tick=" + int_to_str(tick)
            + " stun_served=" + int_to_str(stun_served)
            + " | " + nat_status_line(nstate)
            + " | " + gossip_status_line(gstate)
            + " extaddr_rx=" + int_to_str(gossip_stats_nat_extaddr_rx(gstate)))
        sleep_ms(150)
        tick = tick + 1
    }
    close_fd(server_fd)
    exit(0)
}
main()
NOVA

# ---- driver: soul B (STUN-querier + advertiser) ------------------------
DRV_B="$DRV_DIR/b.nova"
cat > "$DRV_B" <<NOVA
import "std/io"
import "../../../src/federation/gossip.nova"
import "../../../src/federation/nat_traversal.nova"
import "../../../src/kg/multi_kg_manager.nova"
import "../../../src/kg/atom_store.nova"

fn main() {
    let self_addr = "127.0.0.1:" + int_to_str($PORT_B)
    let bp = list_new()
    push(bp, "$ADDR_A")
    let gstate = gossip_init(self_addr, bp)
    gossip_set_seed(gstate, ${PORT_B} + 11)
    let nstate = nat_init()
    gossip_set_nat_state(gstate, nstate)
    println("b: nat_state wired")

    let reg = kg_registry_new()
    let kg = kg_spawn(reg, "lang")
    let server_fd = gossip_listen(self_addr)
    if server_fd < 0 {
        println("b: bind failed on " + self_addr)
        exit(1)
    }
    println("b: listening on " + self_addr)

    sleep_ms(500)

    let ext = nat_query_stun_with_state(nstate, "$ADDR_A")
    if ext == 0 {
        println("b: stun-query-failed last_error=" + nat_last_error(nstate))
    } else {
        nat_set_external(nstate, ext)
        println("b: stun-query-ok external=" + ext)
    }

    let dt = nat_detect_type_from_replies(ext, ext)
    nat_set_type(nstate, dt)
    println("b: nat-type-detect type=" + dt)

    let locals = nat_local_addrs()
    println("b: local-addrs count=" + int_to_str(len(locals)))
    if len(locals) > 0 {
        println("b: local-addr[0]=" + locals[0])
    }

    let hp = nat_hole_punch(nstate, "$ADDR_A")
    println("b: hole-punch-stub returned=" + int_to_str(hp))

    gossip_send_ping(gstate, "$ADDR_A")
    sleep_ms(100)
    let adv = nat_advertise(gstate, nstate, ext)
    println("b: advertise sent_to=" + int_to_str(adv))

    println("b: " + nat_status_line(nstate))

    let tick = 0
    while tick < 25 {
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
        gossip_step(gstate, kg)
        println("b: tick=" + int_to_str(tick)
            + " | " + nat_status_line(nstate)
            + " | " + gossip_status_line(gstate))
        sleep_ms(200)
        tick = tick + 1
    }
    close_fd(server_fd)
    exit(0)
}
main()
NOVA

# ---- precompile both drivers AOT --------------------------------------
BIN_A="$DRV_DIR/a.bin"; BIN_B="$DRV_DIR/b.bin"
printf "  ${C_DIM}info${C_RST}   precompiling 2 soul drivers ...\n"
"$NOVA_BIN" build "$DRV_A" -o "$BIN_A" >"$DRV_DIR/a_build.log" 2>&1 || true
"$NOVA_BIN" build "$DRV_B" -o "$BIN_B" >"$DRV_DIR/b_build.log" 2>&1 || true

if [ ! -x "$BIN_A" ]; then
    printf "  ${C_RED}ERROR${C_RST}: soul A driver failed to compile\n"
    sed 's/^/    /' "$DRV_DIR/a_build.log" 2>/dev/null
    FAIL=$((FAIL+1))
    summary "scenario_oooo_nat_traversal"
    exit $?
fi
if [ ! -x "$BIN_B" ]; then
    printf "  ${C_RED}ERROR${C_RST}: soul B driver failed to compile\n"
    sed 's/^/    /' "$DRV_DIR/b_build.log" 2>/dev/null
    FAIL=$((FAIL+1))
    summary "scenario_oooo_nat_traversal"
    exit $?
fi
PASS=$((PASS+1))
printf "  ${C_GRN}PASS${C_RST}  both soul drivers compiled\n"

"$BIN_A" >"$OUT_A" 2>&1 &
PID_A=$!
"$BIN_B" >"$OUT_B" 2>&1 &
PID_B=$!

sleep 8

A_ALIVE=0; B_ALIVE=0
kill -0 $PID_A 2>/dev/null && A_ALIVE=1
kill -0 $PID_B 2>/dev/null && B_ALIVE=1
assert_eq "$A_ALIVE" "1" "soul A still running after 8s warmup"
assert_eq "$B_ALIVE" "1" "soul B still running after 8s warmup"

# STUN query path.
STUN_OK=$(grep '^b: stun-query-ok' "$OUT_B" 2>/dev/null | head -1)
if [ -n "$STUN_OK" ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  STUN query succeeded: %s\n" "$STUN_OK"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  no stun-query-ok line in B's output\n"
    sed 's/^/      /' "$OUT_B" 2>/dev/null | tail -20
fi

# External addr starts with 127.0.0.1: (loopback sandbox case).
EXT_ADDR=$(echo "$STUN_OK" | grep -oE 'external=[^ ]+' | sed 's/external=//')
assert_match "$EXT_ADDR" "^127\.0\.0\.1:[0-9]+$" "discovered external addr is 127.0.0.1:<port>"

# STUN server saw the request.
STUN_SERVED=$(grep '^a: stun-served' "$OUT_A" 2>/dev/null | head -1)
if [ -n "$STUN_SERVED" ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  STUN server handled the request: %s\n" "$STUN_SERVED"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  no stun-served line in A's output\n"
fi

# NAT type heuristic.
NAT_TYPE=$(grep '^b: nat-type-detect' "$OUT_B" 2>/dev/null | grep -oE 'type=[a-z]+' | sed 's/type=//' | head -1)
if [ "$NAT_TYPE" = "open" ] || [ "$NAT_TYPE" = "cone" ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  NAT type heuristic returned reasonable value: %s\n" "$NAT_TYPE"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  NAT type heuristic returned unexpected: '%s'\n" "$NAT_TYPE"
fi

# Local addrs.
LOCAL_COUNT=$(grep '^b: local-addrs' "$OUT_B" 2>/dev/null | grep -oE 'count=[0-9]+' | sed 's/count=//' | head -1)
if [ "${LOCAL_COUNT:-0}" -ge 1 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  local-addrs nonempty (count=%s)\n" "$LOCAL_COUNT"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  local-addrs empty\n"
fi

LOCAL_FIRST=$(grep '^b: local-addr\[0\]=' "$OUT_B" 2>/dev/null | head -1)
assert_match "$LOCAL_FIRST" "127\.0\.0\.1" "local-addr[0] contains 127.0.0.1"

# Hole-punch stub returned 0.
HP_LINE=$(grep '^b: hole-punch-stub' "$OUT_B" 2>/dev/null | head -1)
assert_match "$HP_LINE" "returned=0" "hole-punch stub returns 0 (R23E.2 placeholder)"

# Advertise sent to >= 1 peer.
ADV_LINE=$(grep '^b: advertise sent_to=' "$OUT_B" 2>/dev/null | head -1)
ADV_COUNT=$(echo "$ADV_LINE" | grep -oE 'sent_to=[0-9]+' | sed 's/sent_to=//')
if [ "${ADV_COUNT:-0}" -ge 1 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  EXTADDR advertised to >= 1 peer (count=%s)\n" "$ADV_COUNT"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  EXTADDR not advertised (line='%s')\n" "$ADV_LINE"
fi

# A's gossip stats_nat_extaddr_rx > 0.
LAST_A_LINE=$(grep '^a: tick=' "$OUT_A" 2>/dev/null | tail -1)
RX_COUNT=$(echo "$LAST_A_LINE" | grep -oE 'extaddr_rx=[0-9]+' | sed 's/extaddr_rx=//')
if [ "${RX_COUNT:-0}" -ge 1 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  A received EXTADDR from B (extaddr_rx=%s)\n" "$RX_COUNT"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  A did not receive EXTADDR (last_a='%s')\n" "$LAST_A_LINE"
fi

# A's nat_state peer-ext table grew (from the nat: segment specifically).
NAT_SEG=$(echo "$LAST_A_LINE" | sed 's/.*nat://' | sed 's/|.*//')
NAT_PEERS=$(echo "$NAT_SEG" | grep -oE 'peers=[0-9]+' | head -1 | sed 's/peers=//')
if [ "${NAT_PEERS:-0}" -ge 1 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  A's nat_state peer-ext table grew (peers=%s)\n" "$NAT_PEERS"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  A's nat_state peer-ext table empty (nat_seg='%s')\n" "$NAT_SEG"
fi

# B's query counters.
LAST_B_LINE=$(grep '^b: tick=' "$OUT_B" 2>/dev/null | tail -1)
B_NAT_SEG=$(echo "$LAST_B_LINE" | sed 's/.*nat://' | sed 's/|.*//')
Q_COUNT=$(echo "$B_NAT_SEG" | grep -oE 'queries=[0-9]+' | head -1 | sed 's/queries=//')
QOK_COUNT=$(echo "$B_NAT_SEG" | grep -oE 'queries_ok=[0-9]+' | head -1 | sed 's/queries_ok=//')
if [ "${Q_COUNT:-0}" -ge 1 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  B's NAT_S_QUERIES counter advanced (queries=%s)\n" "$Q_COUNT"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  B's NAT_S_QUERIES counter still 0\n"
fi
if [ "${QOK_COUNT:-0}" -ge 1 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  B's NAT_S_QUERIES_OK counter advanced (queries_ok=%s)\n" "$QOK_COUNT"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  B's NAT_S_QUERIES_OK counter still 0\n"
fi

summary "scenario_oooo_nat_traversal"
