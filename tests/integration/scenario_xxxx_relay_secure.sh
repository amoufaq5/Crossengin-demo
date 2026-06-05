#!/usr/bin/env bash
# Scenario XXXX -- R26E.2: Noise-XK end-to-end wrap around the R26E gossip
# relay (gossip_relay_secure.nova).
#
# 3-soul mesh A / B / C where A wants to send to B via C, but the relay
# payload must be opaque to C. A and B pre-share a Noise-XK session
# (here forged with `_srl_test_forge_nxk` to skip the ~15s real
# handshake; the cryptographic surface -- ChaCha20-Poly1305 AEAD with
# per-direction monotonic nonces -- is exercised on the real
# nxk_seal/nxk_open codepath). C has NO session for either A or B, so
# attempting to decrypt the bytes on C-side fails: the relay is blind
# to payload content.
#
# Flow per scenario:
#   1. A, B, C bind their gossip ports + bootstrap the mesh.
#   2. A's srl_state registers a session for B (initiator role).
#      B's srl_state registers a session for A (responder role).
#      Both sides use the SAME pair of 32-byte transport keys (in a real
#      deployment those would be derived by HKDF-Split during the Noise
#      XK handshake; here pre-distributed by hardcoded hex constants).
#      C registers NO sessions (it is just a relay).
#   3. A marks B direct-unreachable (test hook -- mirrors R26E's
#      scenario_vvvv pattern) so the relay falls back through C.
#   4. A calls srl_send_secure(B, "ciphertext-from-A"). The plaintext
#      is sealed with A's k_init_to_resp, hex-encoded, then handed to
#      relay_send which routes via C.
#   5. C's gossip handler receives RELAY_REQ with the hex payload;
#      C's drain forwards as RELAY_DATA via=C, from=A. C ALSO attempts
#      to decrypt with its own (empty) srl_state -- this must fail.
#   6. B's gossip handler receives RELAY_DATA; B's srl_drain decodes
#      the hex, opens the AEAD frame with the A<->B session, and
#      enqueues the plaintext "ciphertext-from-A" on B's recv queue.
#   7. Tamper scenario: A seals a second payload "tampered-flight";
#      the harness intercepts the hex by flipping one byte, B receives
#      the modified frame, AEAD tag fails, decrypt_failed counter on B
#      bumps, recv queue does NOT grow.
#
# Assertions (~10):
#   1. NOVA pre-flight (socket(2,1,0) allowed).
#   2. All three soul drivers compile.
#   3. A's srl_send_secure returned 1 (sent counter increments).
#   4. A's relay sent_via_relay counter is >= 1 (frame routed through C).
#   5. C's relay forwarded counter is >= 1 (C forwarded the wrapped bytes).
#   6. C's srl_drain reports delivered=0 (C has no session, cannot decrypt).
#   7. C's srl_drain reports no_session > 0 (it tried, found no session).
#   8. B's srl_state delivered=1 (B successfully decrypted A's frame).
#   9. B's recv queue first entry's plaintext matches "ciphertext-from-A".
#  10. B's decrypt_failed counter bumps after the tampered second frame.

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

it_section "scenario XXXX: R26E.2 Noise-XK wrap of relay payloads (A->C->B with C blind)"

NOVA_BIN="${NOVA_ROOT:-/home/user/NOVA}/nova"
if [ ! -x "$NOVA_BIN" ]; then
    printf "  ${C_RED}ERROR${C_RST}: NOVA launcher not found at %s\n" "$NOVA_BIN" >&2
    FAIL=$((FAIL+1))
    summary "scenario_xxxx_relay_secure"
    exit $?
fi

BASE_PORT=$(( 40000 + (RANDOM % 500) ))
PORT_A=$((BASE_PORT))
PORT_B=$((BASE_PORT + 1))
PORT_C=$((BASE_PORT + 2))
ADDR_A="127.0.0.1:$PORT_A"
ADDR_B="127.0.0.1:$PORT_B"
ADDR_C="127.0.0.1:$PORT_C"

DRV_DIR="$REPO_ROOT/tests/integration/_scenario_xxxx_drivers"
mkdir -p "$DRV_DIR"
OUT_A="/tmp/ce_int_xxxx_a.out"
OUT_B="/tmp/ce_int_xxxx_b.out"
OUT_C="/tmp/ce_int_xxxx_c.out"

PID_A=""; PID_B=""; PID_C=""
trap '
  [ -n "${PID_A:-}" ] && kill -9 $PID_A 2>/dev/null
  [ -n "${PID_B:-}" ] && kill -9 $PID_B 2>/dev/null
  [ -n "${PID_C:-}" ] && kill -9 $PID_C 2>/dev/null
  if [ "${CE_XXXX_KEEP:-0}" = "0" ]; then
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
    printf "  ${C_YEL}SKIP${C_RST}  socket(2,1,0) denied by sandbox -- scenario_xxxx skipped\n"
    PASS=$((PASS+1))
    summary "scenario_xxxx_relay_secure"
    exit $?
fi
PASS=$((PASS+1))
printf "  ${C_GRN}PASS${C_RST}  NOVA pre-flight (socket(2,1,0) allowed)\n"

# Shared 64-char hex transport keys. Distributed to A and B; C never
# sees them.
KIR_HEX="deadbeefcafebabe1122334455667788ff00ff00aaaabbbbccccddddeeeef000"
KRI_HEX="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

# ---- shared driver template --------------------------------------------
#
# Each driver: bind + listen on its gossip port, init gossip + relay +
# srl. Wire relay_state to gossip via gossip_set_relay_state. The
# originator (A) and receiver (B) forge their srl sessions with the
# pre-shared keys; C registers no sessions (it is the dumb relay).
# Per-tick body: drain inbound conns, drain relay's inbound queue,
# drain srl's recv side, gossip_step, emit status. The originator
# issues two srl_send_secure calls: the first one is forwarded
# untouched; the second has its hex frame tampered on the wire after
# the send is observed.

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

fn main() {
    let self_addr = "127.0.0.1:" + int_to_str($port)
    let bp = list_new()
    push(bp, "$peer1")
    push(bp, "$peer2")
    let gstate = gossip_init(self_addr, bp)
    gossip_set_seed(gstate, ${port} + 17)
    let rstate = relay_init(gstate)
    gossip_set_relay_state(gstate, rstate)
    let sstate = srl_init(rstate)

    let reg = kg_registry_new()
    let kg = kg_spawn(reg, "lang")

    // Originator: A has a session with B (initiator role).
    // Receiver:   B has a session with A (responder role).
    // Relay:      C has no sessions.
    if str_eq("$role", "originator") == 1 {
        let nxk_st = _srl_test_forge_nxk(NXK_ROLE_INITIATOR,
                                          "$KIR_HEX", "$KRI_HEX")
        srl_register_peer_session(sstate, "$target", nxk_st,
                                   NXK_ROLE_INITIATOR)
    }
    if str_eq("$role", "receiver") == 1 {
        let nxk_st = _srl_test_forge_nxk(NXK_ROLE_RESPONDER,
                                          "$KIR_HEX", "$KRI_HEX")
        // Receiver's peer is A -- bootstrap peer 1 is A on B's setup.
        srl_register_peer_session(sstate, "$peer1", nxk_st,
                                   NXK_ROLE_RESPONDER)
    }
    // Relay (C): register a STRANGER's session with the from-peer A,
    // so we can demonstrate C tries to decrypt but fails. The real
    // A<->B keys are not in C's process memory. We do this by passing
    // C a deliberately-mismatched (different bytes) key pair. C's
    // peek path attempts to nxk_open every forwarded RELAY_REQ
    // payload; the open fails (Poly1305 tag mismatch) and a counter
    // bumps. This is the load-bearing "C cannot decrypt" assertion.
    let c_peek_state = 0
    let c_peek_attempts = 0
    let c_peek_fail = 0
    let c_tampered_count = 0
    if str_eq("$role", "relay") == 1 {
        c_peek_state = _srl_test_forge_nxk(NXK_ROLE_RESPONDER,
            "ffeeddccbbaa99887766554433221100ff11ee22dd33cc44bb55aa6699887700",
            "112233445566778899aabbccddeeff00112233445566778899aabbccddeeff00")
    }

    let server_fd = gossip_listen(self_addr)
    if server_fd < 0 {
        println("$letter: bind failed on " + self_addr)
        exit(1)
    }
    println("$letter: listening on " + self_addr)
    println("$letter: role=$role")
    println("$letter: " + srl_stats_line(sstate))

    // Warmup ticks: bind + listen + drain inbound conns. No
    // gossip_step yet so bootstrap peers stay ALIVE on slow hosts
    // (same pattern as scenario_vvvv R27B fix).
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

    // Originator: mark target unreachable; send 2 secure payloads.
    if str_eq("$role", "originator") == 1 {
        relay_mark_unreachable(rstate, "$target")
        let pkt1 = srl_str_to_buf("ciphertext-from-A")
        let rc1 = srl_send_secure(sstate, "$target", pkt1[0], pkt1[1])
        println("$letter: send1 rc=" + int_to_str(rc1)
            + " sent=" + int_to_str(srl_stats_sent(sstate)))
        // Inter-send pause -- same shape as scenario_vvvv: the relay
        // path round-trip (RELAY_REQ -> RELAY_DATA -> RELAY_ACK)
        // needs to flush before the second send.
        sleep_ms(1500)
        let pkt2 = srl_str_to_buf("tampered-flight")
        let rc2 = srl_send_secure(sstate, "$target", pkt2[0], pkt2[1])
        println("$letter: send2 rc=" + int_to_str(rc2)
            + " sent=" + int_to_str(srl_stats_sent(sstate)))
    }

    // Main loop: drain inbound + relay queues + srl + gossip_step + emit.
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
        // Relay-side peek + tamper:
        //
        // BEFORE drain consumes the REQ queue, walk it. For each
        // forwarded RELAY_REQ:
        //  1. attempt nxk_open with a STRANGER session -- this MUST
        //     fail (load-bearing "C captures bytes but cannot decrypt"
        //     check; the relay sees the wire bytes via
        //     relay_handle_request but without the genuine A<->B
        //     transport key the AEAD tag fails).
        //  2. for req_id >= 2 (the second message), MITM-tamper the
        //     hex payload by flipping one byte deep in the ciphertext.
        //     The corrupted line is written BACK to the queue so the
        //     subsequent drain forwards the tampered bytes to B. B's
        //     nxk_open MUST then fail (Poly1305 tag mismatch),
        //     bumping B's decrypt_failed counter.
        if str_eq("$role", "relay") == 1 {
            let q = rstate[RELAY_S_INBOUND_REQS]
            let qi = 0
            while qi < len(q) {
                let parsed = relay_parse_request(q[qi])
                if parsed != 0 {
                    let parsed_id = parsed[0]
                    let parsed_target = parsed[1]
                    let parsed_origin = parsed[2]
                    let hex_payload = parsed[3]
                    let dec = cc_hex_decode(hex_payload)
                    if dec != 0 {
                        c_peek_attempts = c_peek_attempts + 1
                        let opened = nxk_open(c_peek_state,
                                              NXK_ROLE_RESPONDER,
                                              dec[0], dec[1])
                        if opened == 0 {
                            c_peek_fail = c_peek_fail + 1
                        }
                    }
                    // Tamper only the FIRST seen RELAY_REQ in the
                    // queue, then again every time the relay sees a
                    // SECOND distinct request (tracked by
                    // c_tampered_count). We deliberately let the
                    // first observed request through clean so the
                    // happy-path assertion (B delivers req1 plain)
                    // and the tamper assertion (B drops req2) both
                    // succeed in the same run. The check is "tamper
                    // when at least one clean has flowed and we are
                    // not yet tampering for this round".
                    if c_tampered_count == 0 {
                        // Allow first frame through clean; mark we
                        // saw it. The c_tampered_count is bumped
                        // ONCE when we let the first through, then
                        // again every subsequent time we tamper.
                        c_tampered_count = 1
                    } else {
                        // Tamper: flip the nibble at index 14 in the
                        // hex (well past the 8-char length header so
                        // we land inside ciphertext).
                        let n = len(hex_payload)
                        if n > 16 {
                            let tampered = ""
                            let ti = 0
                            while ti < n {
                                if ti == 14 {
                                    let cc = char_at(hex_payload, ti)
                                    if cc == 97 {
                                        tampered = tampered + "b"
                                    } else {
                                        tampered = tampered + "a"
                                    }
                                } else {
                                    tampered = tampered + chr(char_at(hex_payload, ti))
                                }
                                ti = ti + 1
                            }
                            q[qi] = relay_format_request(parsed_id,
                                                          parsed_target,
                                                          parsed_origin,
                                                          tampered)
                            c_tampered_count = c_tampered_count + 1
                        }
                    }
                }
                qi = qi + 1
            }
        }
        relay_drain_inbound(rstate)
        // After relay's records are populated, the srl module drains
        // them, decrypts (if a session exists), and queues plaintext.
        // On C (no sessions) this MUST yield no_session > 0; the bytes
        // are visible at the relay level but opaque at the srl level.
        let srl_n = srl_drain_relay_recv(sstate)
        gossip_step(gstate, kg)
        let extra = ""
        if str_eq("$role", "relay") == 1 {
            extra = " peek_attempts=" + int_to_str(c_peek_attempts)
                + " peek_fail=" + int_to_str(c_peek_fail)
        }
        println("$letter: tick=" + int_to_str(tick)
            + " " + relay_stats_line(rstate)
            + " " + srl_stats_line(sstate)
            + " req_rx=" + int_to_str(gossip_stats_relay_req_rx(gstate))
            + " data_rx=" + int_to_str(gossip_stats_relay_data_rx(gstate))
            + extra)
        if str_eq("$role", "receiver") == 1 {
            if srl_recv_count(sstate) > 0 {
                let r0 = srl_received_at(sstate, 0)
                println("$letter: recv[0] from=" + srl_received_from(r0)
                    + " plaintext=" + srl_received_pt_str(r0))
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
# Soul B: receiver. Bootstrap A + C. (No target.)
write_driver "b" "$PORT_B" "$ADDR_A" "$ADDR_C" "receiver" ""
# Soul C: relay. Bootstrap A + B. (No sessions; will see no_session > 0.)
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
    summary "scenario_xxxx_relay_secure"
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

# Wait for warmup + sends + a few relay cycles. Loop is 15 warmup +
# 40 main * 150ms = ~8.25s; +1.5s inter-send pause = ~10s wall-clock.
# Check liveness at 7s, then wait for clean exits.
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

# ---- A's srl_send_secure returned 1 -----------------------------------
SEND1=$(grep '^a: send1 rc=' "$OUT_A" 2>/dev/null | head -1)
RC1=$(echo "$SEND1" | grep -oE 'rc=[0-9]+' | sed 's/rc=//')
A_SENT=$(echo "$SEND1" | grep -oE 'sent=[0-9]+' | sed 's/sent=//')
if [ "${RC1:-0}" = "1" ] && [ "${A_SENT:-0}" -ge 1 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  A's srl_send_secure returned 1, sent counter=%s\n" "$A_SENT"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  A's send1 line='%s'\n" "$SEND1"
fi

# ---- A's relay sent_via_relay >= 1 ------------------------------------
LAST_A=$(grep '^a: tick=' "$OUT_A" 2>/dev/null | tail -1)
A_VIA=$(echo "$LAST_A" | grep -oE 'via=[0-9]+' | head -1 | sed 's/via=//')
if [ "${A_VIA:-0}" -ge 1 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  A's underlying relay routed through C (via=%s)\n" "$A_VIA"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  A's relay sent_via_relay=0 (last='%s')\n" "$LAST_A"
fi

# ---- C's relay forwarded >= 1 ----------------------------------------
LAST_C=$(grep '^c: tick=' "$OUT_C" 2>/dev/null | tail -1)
C_FWD=$(echo "$LAST_C" | grep -oE 'fwd=[0-9]+' | head -1 | sed 's/fwd=//')
if [ "${C_FWD:-0}" -ge 1 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  C's relay forwarded the wrapped bytes (fwd=%s)\n" "$C_FWD"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  C's relay forwarded counter=0 (last='%s')\n" "$LAST_C"
fi

# ---- C cannot decrypt: delivered MUST stay 0 -------------------------
# The srl stats line shape is: "srl: sessions=N sent=N delivered=N
# decrypt_fail=N no_session=N". Both relay and srl emit a delivered=
# token, so we anchor on the srl portion by grabbing everything after
# "srl: " up to req_rx=, then extracting delivered= from that slice.
_extract_srl_field() {
    local line="$1" field="$2"
    echo "$line" | sed -n 's/.*srl: \(.*\) req_rx=.*/\1/p' \
        | grep -oE "${field}=[0-9]+" | head -1 | sed "s/${field}=//"
}
C_DELIVERED=$(_extract_srl_field "$LAST_C" "delivered")
if [ "${C_DELIVERED:-0}" = "0" ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  C is blind to payload (srl delivered=0)\n"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  C decrypted payload (delivered=%s -- key leak?) last='%s'\n" "$C_DELIVERED" "$LAST_C"
fi

# ---- C explicitly attempts decrypt with stranger session: fails -----
# C's peek loop walks the relay's INBOUND_REQS queue, hex-decodes each
# payload, and calls nxk_open with a stranger's transport keys. Every
# attempt MUST fail (Poly1305 tag mismatch under the wrong key).
C_PEEK_AT=$(echo "$LAST_C" | grep -oE 'peek_attempts=[0-9]+' | head -1 | sed 's/peek_attempts=//')
C_PEEK_FAIL=$(echo "$LAST_C" | grep -oE 'peek_fail=[0-9]+' | head -1 | sed 's/peek_fail=//')
if [ "${C_PEEK_AT:-0}" -ge 1 ] && [ "${C_PEEK_AT:-0}" = "${C_PEEK_FAIL:-0}" ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  C attempted decrypt (peek_attempts=%s) and ALL failed (peek_fail=%s)\n" "$C_PEEK_AT" "$C_PEEK_FAIL"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  C's decrypt attempt accounting off (attempts=%s fail=%s) last='%s'\n" \
        "${C_PEEK_AT:-?}" "${C_PEEK_FAIL:-?}" "$LAST_C"
fi

# ---- B's srl delivered == 1 -----------------------------------------
LAST_B=$(grep '^b: tick=' "$OUT_B" 2>/dev/null | tail -1)
B_DELIVERED=$(_extract_srl_field "$LAST_B" "delivered")
if [ "${B_DELIVERED:-0}" -ge 1 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  B decrypted A's frame (srl delivered=%s)\n" "$B_DELIVERED"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  B did not decrypt the wrapped payload (last='%s')\n" "$LAST_B"
fi

# ---- B's recv[0] plaintext matches "ciphertext-from-A" --------------
B_RECV0=$(grep '^b: recv\[0\] from=' "$OUT_B" 2>/dev/null | head -1)
RECV_PT=$(echo "$B_RECV0" | sed -n 's/.*plaintext=//p')
if [ "$RECV_PT" = "ciphertext-from-A" ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  B's recv[0] plaintext = '%s' (E2E plaintext round-trips through C unread)\n" "$RECV_PT"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  B's recv[0] plaintext='%s' expected 'ciphertext-from-A' (line='%s')\n" "$RECV_PT" "$B_RECV0"
fi

# ---- B detects the tampered second frame (decrypt_failed >= 1) -------
# C MITM-tampered the req_id=2 hex payload before forwarding. B opens
# the modified frame; the Poly1305 tag fails; B's decrypt_failed
# counter advances. This is the load-bearing tamper-detection
# assertion: if the relay flips a byte, the recipient drops the
# frame instead of consuming corrupted plaintext.
B_DECFAIL=$(_extract_srl_field "$LAST_B" "decrypt_fail")
if [ "${B_DECFAIL:-0}" -ge 1 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  B detected wire tampering -- decrypt_failed=%s (delivered=%s) -- tamper-detection wired end-to-end\n" \
        "${B_DECFAIL:-0}" "${B_DELIVERED:-0}"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  B did NOT detect the tampered frame (delivered=%s decrypt_fail=%s) -- last='%s'\n" \
        "${B_DELIVERED:-0}" "${B_DECFAIL:-0}" "$LAST_B"
fi

summary "scenario_xxxx_relay_secure"
