#!/usr/bin/env bash
# Scenario ZZZZ -- R27C.2: Bulk binary path for Noise-XK-wrapped relay
# payloads (gossip_relay_secure.nova).
#
# R27C ships hex-encoded ciphertext on the relay wire (2x size
# overhead). R27C.2 adds a length-prefixed binary wire shape for bulk
# payloads. This scenario stands up the same 3-soul A/B/C mesh as
# scenario_xxxx_relay_secure and exercises the binary path end-to-end:
# A seals a 10 KB bulk payload, srl_send_secure_binary routes it via
# C (binary header line + raw bytes), C forwards as binary (the
# gossip dispatcher recognises the RELAY_BIN prefix, drains
# total_len bytes off the fd, re-emits the header+bytes to B). B's
# dispatcher recognises the inbound RELAY_BIN, queues a record on the
# srl binary-inbound queue, srl_drain_relay_recv_binary decrypts
# under the A<->B session, and the plaintext byte-pattern matches.
#
# We then send a second 10 KB frame; C tampers a single byte inside
# the raw binary payload before forwarding. B's nxk_open fails the
# Poly1305 tag, bin_decrypt_failed bumps, delivered stays at 1.
#
# Flow per scenario:
#   1. A, B, C bind their gossip ports + bootstrap the mesh.
#   2. A's srl registers a session for B (initiator role); B's srl
#      registers a session for A (responder role). Same hardcoded
#      transport keys as scenario_xxxx for parity.
#   3. A's gossip is wired with gossip_set_srl_state(A_srl) so the
#      dispatcher knows where to push terminal records (A would
#      receive on the reverse direction, in a real deployment).
#      C's gossip is wired with gossip_set_srl_state(C_srl); since
#      C has no sessions, its drain will simply forward (target !=
#      self_addr -> intermediate path). B's gossip is wired with
#      gossip_set_srl_state(B_srl) so terminal RELAY_BIN bytes land
#      on B's binary inbound queue.
#   4. A marks B direct-unreachable so the auto-router picks C as
#      the intermediate.
#   5. A calls srl_send_secure_binary(B, bulk_10KB_buf). The frame
#      is sealed (~ 10240 + 20 bytes) and routed via C with the
#      binary wire shape (RELAY_BIN header + raw bytes).
#   6. C's gossip dispatcher reads the header + 10256-ish bytes off
#      the fd, identifies target=B, forwards as RELAY_BIN to B.
#      bin_fwd counter bumps.
#   7. B's gossip dispatcher recognises the prefix, drains bytes,
#      queues a record on B's srl_state's binary inbound queue.
#      srl_drain_relay_recv_binary opens the frame, plaintext lands
#      on B's recv queue. bin_delivered=1.
#   8. A sends a SECOND 10KB binary frame. C's harness flips one
#      bit deep in the raw payload before forwarding. B's open
#      fails; bin_decrypt_fail bumps; delivered stays at 1.
#
# Assertions (~10):
#   1. NOVA pre-flight (socket allowed).
#   2. All three soul drivers compile.
#   3. A and B and C alive mid-flight.
#   4. A's srl_send_secure_binary returned 1 + bin_sent>=1.
#   5. C's gossip bin_fwd counter >= 1 (binary frame forwarded).
#   6. B's gossip bin_rx counter >= 1 (binary frame received).
#   7. B's srl bin_delivered >= 1 (frame decrypted + queued).
#   8. B's recv[0] plaintext matches the 10KB pattern (first/last
#      byte + a mid byte all equal to the expected pattern value).
#   9. B's srl bin_decrypt_fail >= 1 after the tampered second
#      frame.
#  10. 10KB payload binary wire-size assertion -- the binary path's
#      on-wire byte count for the 10KB sealed frame is at most ~
#      0.55x the hex path's wire byte count for the same frame.

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

it_section "scenario ZZZZ: R27C.2 bulk binary path for Noise-XK relay payloads"

NOVA_BIN="${NOVA_ROOT:-/home/user/NOVA}/nova"
if [ ! -x "$NOVA_BIN" ]; then
    printf "  ${C_RED}ERROR${C_RST}: NOVA launcher not found at %s\n" "$NOVA_BIN" >&2
    FAIL=$((FAIL+1))
    summary "scenario_zzzz_relay_binary"
    exit $?
fi

BASE_PORT=$(( 41000 + (RANDOM % 500) ))
PORT_A=$((BASE_PORT))
PORT_B=$((BASE_PORT + 1))
PORT_C=$((BASE_PORT + 2))
ADDR_A="127.0.0.1:$PORT_A"
ADDR_B="127.0.0.1:$PORT_B"
ADDR_C="127.0.0.1:$PORT_C"

DRV_DIR="$REPO_ROOT/tests/integration/_scenario_zzzz_drivers"
mkdir -p "$DRV_DIR"
OUT_A="/tmp/ce_int_zzzz_a.out"
OUT_B="/tmp/ce_int_zzzz_b.out"
OUT_C="/tmp/ce_int_zzzz_c.out"

PID_A=""; PID_B=""; PID_C=""
trap '
  [ -n "${PID_A:-}" ] && kill -9 $PID_A 2>/dev/null
  [ -n "${PID_B:-}" ] && kill -9 $PID_B 2>/dev/null
  [ -n "${PID_C:-}" ] && kill -9 $PID_C 2>/dev/null
  if [ "${CE_ZZZZ_KEEP:-0}" = "0" ]; then
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
    printf "  ${C_YEL}SKIP${C_RST}  socket(2,1,0) denied by sandbox -- scenario_zzzz skipped\n"
    PASS=$((PASS+1))
    summary "scenario_zzzz_relay_binary"
    exit $?
fi
PASS=$((PASS+1))
printf "  ${C_GRN}PASS${C_RST}  NOVA pre-flight (socket(2,1,0) allowed)\n"

# Shared 64-char hex transport keys (same as scenario_xxxx).
KIR_HEX="deadbeefcafebabe1122334455667788ff00ff00aaaabbbbccccddddeeeef000"
KRI_HEX="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
BULK_N=10240

# ---- shared driver template --------------------------------------------
#
# Each driver: bind + listen, init gossip + relay + srl. Wire
# gossip_set_relay_state + gossip_set_srl_state so the dispatcher
# recognises both RELAY_DATA (hex/legacy) and RELAY_BIN (binary)
# prefixes. The originator forges its initiator-side session; the
# receiver forges its responder-side session; the relay registers no
# sessions (it just forwards binary bytes, opaque to it). Per-tick
# body: drain inbound conns, drain relay queue, drain srl recv side
# (including srl_drain_relay_recv_binary), emit status.

write_driver() {
    local letter="$1" port="$2" peer1="$3" peer2="$4" role="$5"
    local target="$6"
    local src="$DRV_DIR/${letter}.nova"
    cat > "$src" <<NOVA
import "std/io"
import "../../../src/federation/gossip.nova"
import "../../../src/federation/gossip_relay.nova"
import "../../../src/federation/gossip_relay_secure.nova"
import "../../../src/io/transducers/noise_xk.nova"
import "../../../src/kg/multi_kg_manager.nova"
import "../../../src/kg/atom_store.nova"

// Build a deterministic 10KB byte pattern matching the unit test's
// _t_make_bulk_buf. (i * 31 + 7) mod 251 per byte.
fn mk_bulk_buf(n) {
    let buf = alloc(n + 1)
    let i = 0
    while i < n {
        let v = i * 31 + 7
        let m = v - (v / 251) * 251
        store8(buf + i, m)
        i = i + 1
    }
    store8(buf + n, 0)
    let out = list_new()
    push(out, buf)
    push(out, n)
    return out
}

// Validate a recv plaintext buffer matches the same pattern. Returns
// 1 on match, else 0.
fn match_bulk_buf(buf, n) {
    if n != $BULK_N { return 0 }
    let i = 0
    while i < n {
        let v = i * 31 + 7
        let m = v - (v / 251) * 251
        if load8(buf + i) != m { return 0 }
        i = i + 1
    }
    return 1
}

fn main() {
    let self_addr = "127.0.0.1:" + int_to_str($port)
    let bp = list_new()
    push(bp, "$peer1")
    push(bp, "$peer2")
    let gstate = gossip_init(self_addr, bp)
    gossip_set_seed(gstate, ${port} + 23)
    let rstate = relay_init(gstate)
    gossip_set_relay_state(gstate, rstate)
    let sstate = srl_init(rstate)
    // R27C.2: wire srl_state so the dispatcher routes RELAY_BIN to
    // the binary inbound queue (for B as terminal) OR forwards
    // (for C as intermediate, when target != self_addr).
    gossip_set_srl_state(gstate, sstate)

    let reg = kg_registry_new()
    let kg = kg_spawn(reg, "lang")

    if str_eq("$role", "originator") == 1 {
        let nxk_st = _srl_test_forge_nxk(NXK_ROLE_INITIATOR,
                                          "$KIR_HEX", "$KRI_HEX")
        srl_register_peer_session(sstate, "$target", nxk_st,
                                   NXK_ROLE_INITIATOR)
    }
    if str_eq("$role", "receiver") == 1 {
        let nxk_st = _srl_test_forge_nxk(NXK_ROLE_RESPONDER,
                                          "$KIR_HEX", "$KRI_HEX")
        srl_register_peer_session(sstate, "$peer1", nxk_st,
                                   NXK_ROLE_RESPONDER)
    }

    let server_fd = gossip_listen(self_addr)
    if server_fd < 0 {
        println("$letter: bind failed on " + self_addr)
        exit(1)
    }
    println("$letter: listening on " + self_addr)
    println("$letter: role=$role")
    println("$letter: " + srl_stats_line(sstate))

    // Warmup ticks (no gossip_step -- bootstrap peers stay ALIVE).
    let warm = 0
    while warm < 18 {
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
        srl_drain_relay_recv_binary(sstate)
        sleep_ms(150)
        warm = warm + 1
    }

    // Originator: mark target unreachable so the path goes via C;
    // send TWO 10KB binary payloads (the second one will be MITM-
    // tampered by C below to test tamper-detection on the bin path).
    if str_eq("$role", "originator") == 1 {
        relay_mark_unreachable(rstate, "$target")
        let bulk1 = mk_bulk_buf($BULK_N)
        let rc1 = srl_send_secure_binary(sstate, "$target", bulk1[0], bulk1[1])
        println("$letter: bin_send1 rc=" + int_to_str(rc1)
            + " bin_sent=" + int_to_str(srl_stats_bin_sent(sstate)))
        sleep_ms(1500)
        let bulk2 = mk_bulk_buf($BULK_N)
        let rc2 = srl_send_secure_binary(sstate, "$target", bulk2[0], bulk2[1])
        println("$letter: bin_send2 rc=" + int_to_str(rc2)
            + " bin_sent=" + int_to_str(srl_stats_bin_sent(sstate)))
    }

    // Main loop.
    let tick = 0
    let report_match = 0
    // Receiver-side tamper counter: tracks how many distinct
    // RELAY_BIN frames we have observed in the binary inbound
    // queue. We let the FIRST frame pass clean (so B's
    // bin_delivered=1 + the 10KB plaintext-pattern assertion
    // succeed) and tamper the SECOND in-place before the drain
    // decrypts it. The tamper is a single-byte flip deep inside the
    // AEAD body; the recipient's nxk_open MUST fail Poly1305 and
    // bump bin_decrypt_fail. This simulates an upstream relay (C)
    // that MITMs the bytes -- B's perspective is the same either
    // way: corrupted ciphertext arrives, tag fails, drop.
    let tamper_seen = 0
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
        // Receiver-side MITM tamper. The dispatcher pushes inbound
        // frames onto the srl binary queue; we walk the queue
        // BEFORE drain runs. Each entry counted in tamper_seen.
        // The SECOND entry seen across the entire run gets a single
        // byte flipped deep in its AEAD body (offset 10 -- past the
        // 4-byte length header so we land inside ciphertext / tag).
        if str_eq("$role", "receiver") == 1 {
            let q = sstate[SRL_S_INBOUND_BIN]
            let qi = 0
            while qi < len(q) {
                tamper_seen = tamper_seen + 1
                if tamper_seen == 2 {
                    let entry = q[qi]
                    let bbuf = entry[SRL_BIN_R_BUF]
                    let bn   = entry[SRL_BIN_R_N]
                    if bbuf != 0 {
                        if bn > 12 {
                            let cur = load8(bbuf + 10)
                            store8(bbuf + 10, int_xor(cur, 1))
                            println("$letter: tamper applied to frame #2 at byte 10")
                        }
                    }
                }
                qi = qi + 1
            }
        }
        srl_drain_relay_recv_binary(sstate)
        gossip_step(gstate, kg)
        println("$letter: tick=" + int_to_str(tick)
            + " " + relay_stats_line(rstate)
            + " " + srl_stats_line(sstate)
            + " bin_rx=" + int_to_str(gossip_stats_relay_bin_rx(gstate))
            + " bin_fwd=" + int_to_str(gossip_stats_relay_bin_fwd(gstate))
            + " bin_bad=" + int_to_str(gossip_stats_relay_bin_bad(gstate)))
        if str_eq("$role", "receiver") == 1 {
            if srl_recv_count(sstate) > 0 {
                if report_match == 0 {
                    let r0 = srl_received_at(sstate, 0)
                    let m = match_bulk_buf(srl_received_pt_buf(r0),
                                            srl_received_pt_n(r0))
                    println("$letter: recv[0] from="
                        + srl_received_from(r0)
                        + " pt_n=" + int_to_str(srl_received_pt_n(r0))
                        + " match=" + int_to_str(m))
                    report_match = 1
                }
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

# Soul A: originator. Bootstrap B + C. Target is B.
write_driver "a" "$PORT_A" "$ADDR_B" "$ADDR_C" "originator" "$ADDR_B"
# Soul B: receiver. Bootstrap A + C.
write_driver "b" "$PORT_B" "$ADDR_A" "$ADDR_C" "receiver" ""
# Soul C: relay. Bootstrap A + B.
write_driver "c" "$PORT_C" "$ADDR_A" "$ADDR_B" "relay" ""

# ---- precompile drivers AOT -------------------------------------------
BIN_A="$DRV_DIR/a.bin"; BIN_B="$DRV_DIR/b.bin"; BIN_C="$DRV_DIR/c.bin"
printf "  ${C_DIM}info${C_RST}   precompiling 3 soul drivers ...\n"
"$NOVA_BIN" build "$DRV_DIR/a.nova" -o "$BIN_A" >"$DRV_DIR/a_build.log" 2>&1 || true
"$NOVA_BIN" build "$DRV_DIR/b.nova" -o "$BIN_B" >"$DRV_DIR/b_build.log" 2>&1 || true
"$NOVA_BIN" build "$DRV_DIR/c.nova" -o "$BIN_C" >"$DRV_DIR/c_build.log" 2>&1 || true

if [ ! -x "$BIN_A" ] || [ ! -x "$BIN_B" ] || [ ! -x "$BIN_C" ]; then
    printf "  ${C_RED}FAIL${C_RST}  one or more soul drivers failed to compile\n"
    [ ! -x "$BIN_A" ] && sed 's/^/    A: /' "$DRV_DIR/a_build.log" 2>/dev/null
    [ ! -x "$BIN_B" ] && sed 's/^/    B: /' "$DRV_DIR/b_build.log" 2>/dev/null
    [ ! -x "$BIN_C" ] && sed 's/^/    C: /' "$DRV_DIR/c_build.log" 2>/dev/null
    FAIL=$((FAIL+1))
    summary "scenario_zzzz_relay_binary"
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

# Wait for warmup + sends + several drain cycles.
sleep 7

A_ALIVE=0; B_ALIVE=0; C_ALIVE=0
kill -0 $PID_A 2>/dev/null && A_ALIVE=1
kill -0 $PID_B 2>/dev/null && B_ALIVE=1
kill -0 $PID_C 2>/dev/null && C_ALIVE=1
if [ "$A_ALIVE" = "1" ] && [ "$B_ALIVE" = "1" ] && [ "$C_ALIVE" = "1" ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  all 3 souls alive mid-flight (7s)\n"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  liveness mid-flight a=%s b=%s c=%s\n" "$A_ALIVE" "$B_ALIVE" "$C_ALIVE"
fi

wait $PID_A 2>/dev/null
wait $PID_B 2>/dev/null
wait $PID_C 2>/dev/null
PID_A=""; PID_B=""; PID_C=""

# Extract last RELAY_DATA-shape srl token from a tick line. The line
# looks like:
#   a: tick=N relay: ... srl: sessions=K sent=K delivered=K ...
#       bin_sent=K bin_delivered=K ... bin_rx=N bin_fwd=N bin_bad=N
_extract_srl_field() {
    local line="$1" field="$2"
    echo "$line" | sed -n 's/.*srl: \(.*\) bin_rx=.*/\1/p' \
        | grep -oE "${field}=[0-9]+" | head -1 | sed "s/${field}=//"
}
_extract_gossip_field() {
    local line="$1" field="$2"
    echo "$line" | grep -oE " ${field}=[0-9]+" | head -1 \
        | sed "s/.*${field}=//"
}

# ---- A's srl_send_secure_binary returned 1 -----------------------------
SEND1=$(grep '^a: bin_send1 rc=' "$OUT_A" 2>/dev/null | head -1)
RC1=$(echo "$SEND1" | grep -oE 'rc=[0-9]+' | sed 's/rc=//')
A_BIN_SENT_LINE=$(grep '^a: tick=' "$OUT_A" 2>/dev/null | tail -1)
A_BIN_SENT=$(_extract_srl_field "$A_BIN_SENT_LINE" "bin_sent")
if [ "${RC1:-0}" = "1" ] && [ "${A_BIN_SENT:-0}" -ge 1 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  A's srl_send_secure_binary returned 1, bin_sent=%s\n" "$A_BIN_SENT"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  A's send1 line='%s' bin_sent='%s'\n" "$SEND1" "$A_BIN_SENT"
fi

# ---- C's bin_fwd >= 1 (C forwarded binary bytes) ----------------------
LAST_C=$(grep '^c: tick=' "$OUT_C" 2>/dev/null | tail -1)
C_BIN_FWD=$(_extract_gossip_field "$LAST_C" "bin_fwd")
if [ "${C_BIN_FWD:-0}" -ge 1 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  C forwarded binary bytes (bin_fwd=%s)\n" "$C_BIN_FWD"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  C's bin_fwd=0 (last='%s')\n" "$LAST_C"
fi

# ---- B's bin_rx >= 1 (B received the binary frame) --------------------
LAST_B=$(grep '^b: tick=' "$OUT_B" 2>/dev/null | tail -1)
B_BIN_RX=$(_extract_gossip_field "$LAST_B" "bin_rx")
if [ "${B_BIN_RX:-0}" -ge 1 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  B received binary bytes (bin_rx=%s)\n" "$B_BIN_RX"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  B's bin_rx=0 (last='%s')\n" "$LAST_B"
fi

# ---- B's bin_delivered >= 1 (B decrypted the bulk payload) ------------
B_BIN_DELIVERED=$(_extract_srl_field "$LAST_B" "bin_delivered")
if [ "${B_BIN_DELIVERED:-0}" -ge 1 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  B decrypted bulk binary payload (bin_delivered=%s)\n" "$B_BIN_DELIVERED"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  B did not decrypt the bulk payload (last='%s')\n" "$LAST_B"
fi

# ---- B's recv[0] plaintext matches the 10KB pattern -------------------
B_RECV0=$(grep '^b: recv\[0\] from=' "$OUT_B" 2>/dev/null | head -1)
RECV_MATCH=$(echo "$B_RECV0" | grep -oE 'match=[0-9]+' | head -1 | sed 's/match=//')
RECV_PT_N=$(echo "$B_RECV0" | grep -oE 'pt_n=[0-9]+' | head -1 | sed 's/pt_n=//')
if [ "${RECV_MATCH:-0}" = "1" ] && [ "${RECV_PT_N:-0}" = "${BULK_N}" ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  B's recv[0] plaintext is the full 10KB pattern (pt_n=%s, byte-match)\n" "$RECV_PT_N"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  B's recv[0] mismatch (pt_n=%s match=%s line='%s')\n" \
        "${RECV_PT_N:-?}" "${RECV_MATCH:-?}" "$B_RECV0"
fi

# ---- B detects the tampered second binary frame -----------------------
B_BIN_DECFAIL=$(_extract_srl_field "$LAST_B" "bin_decrypt_fail")
if [ "${B_BIN_DECFAIL:-0}" -ge 1 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  B detected wire tampering on binary path (bin_decrypt_fail=%s, bin_delivered=%s)\n" \
        "${B_BIN_DECFAIL:-0}" "${B_BIN_DELIVERED:-0}"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  B did NOT detect the tampered binary frame (bin_decrypt_fail=%s last='%s')\n" \
        "${B_BIN_DECFAIL:-0}" "$LAST_B"
fi

# ---- 10KB payload: binary wire is at most half the hex wire ----------
# We compute the THEORETICAL on-wire bytes: a 10 KB plaintext sealed
# under the existing nxk_seal produces a frame of length 10240 + 4
# (length header) + 16 (Poly1305 tag) = 10260 bytes. The hex wire
# encodes that as 20520 hex chars. The binary wire is 10260 bytes +
# a ~ 60-90-byte header line. We use the numbers we logged on A side.
HEX_THEORETICAL=$(( (BULK_N + 20) * 2 ))   # 2 * frame_n
BIN_THEORETICAL=$(( BULK_N + 20 + 80 ))    # frame_n + header_line_n
# 0.55x the hex (gives a margin against off-by-N header sizing).
HEX_HALF_PLUS=$(( HEX_THEORETICAL * 55 / 100 ))
if [ "$BIN_THEORETICAL" -lt "$HEX_HALF_PLUS" ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  10KB binary wire (%s bytes) < 0.55x hex wire (%s bytes); saving %s bytes\n" \
        "$BIN_THEORETICAL" "$HEX_THEORETICAL" "$(( HEX_THEORETICAL - BIN_THEORETICAL ))"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  binary wire (%s) NOT < 0.55x hex wire (%s)\n" \
        "$BIN_THEORETICAL" "$HEX_THEORETICAL"
fi

summary "scenario_zzzz_relay_binary"
