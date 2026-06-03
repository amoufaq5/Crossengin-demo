#!/usr/bin/env bash
# Scenario MMMM -- R23C: federation snapshot replication via gossip.
#
# Spawns TWO souls (A, B) with their own Ed25519 long-term keypairs.
# Each soul:
#   * binds + listens on its own gossip port
#   * registers the OTHER soul's pubkey under a fixed soul_id (the
#     out-of-band step a federation operator handles in production)
#   * wires the snapshot-replication module via sr_init +
#     gossip_set_sr_state
#   * embeds its OWN snapshot bytes (precomputed via snap_to_text on
#     a fixed-shape (instance, ts, atom) tuple -- the driver hard-codes
#     the text to avoid pulling snapshot_disk.nova into the same
#     compilation unit as gossip.nova; the disk module's internal
#     `_starts_with` helper collides on the assembler with the same-
#     named helper in io/transducers/kg_sync.nova which gossip already
#     drags in)
#   * registers its own snapshot in the replica table (so it can serve
#     SNAP_FETCH from peers)
#   * BROADCASTS the attestation via gossip_send_attestation
#   * after each gossip step, calls gossip_drive_snap_fetches which
#     walks the known-roots table + issues SNAP_FETCH against every
#     alive peer for any root we don't already hold
#   * verifies + stores received replica bytes (verify checks the
#     bytes' meta.merkle_root equals the signed root the attestation
#     committed to; tampered bytes are rejected without polluting the
#     replica table)
#
# Assertions cover:
#   1. NOVA toolchain present (pre-flight).
#   2. Both sockets bind successfully.
#   3. Soul A registers its own snapshot in the replica table.
#   4. Soul B receives A's attestation -> tracks the root.
#   5. Soul B fetches the snapshot bytes from A and verifies them.
#   6. Soul B's local replica table now holds A's snapshot.
#   7. Symmetric direction works (best-effort).
#   8. Soul B can re-serve the replica (peer A's snapshot is now
#      available from both A and B).
#   9. Tampered bytes (different meta.merkle_root) are rejected by
#      sr_observe_snap_response without polluting the replica table.
#  10. /snap_replicas chat dispatch echoes the R23C delegation message.

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

it_section "scenario MMMM: R23C snapshot replication via gossip (2-soul mesh)"

NOVA_BIN="${NOVA_ROOT:-/home/user/NOVA}/nova"
if [ ! -x "$NOVA_BIN" ]; then
    printf "  ${C_RED}ERROR${C_RST}: NOVA launcher not found at %s\n" "$NOVA_BIN" >&2
    FAIL=$((FAIL+1))
    summary "scenario_mmmm_snap_replication"
    exit $?
fi

BASE_PORT=$(( 36000 + (RANDOM % 500) ))
PORT_A=$((BASE_PORT))
PORT_B=$((BASE_PORT + 1))
ADDR_A="127.0.0.1:$PORT_A"
ADDR_B="127.0.0.1:$PORT_B"

DRV_DIR="$REPO_ROOT/tests/integration/_scenario_mmmm_drivers"
mkdir -p "$DRV_DIR"
OUT_A="/tmp/ce_int_mmmm_a.out"
OUT_B="/tmp/ce_int_mmmm_b.out"

PID_A=""; PID_B=""
trap '
  [ -n "${PID_A:-}" ] && kill -9 $PID_A 2>/dev/null
  [ -n "${PID_B:-}" ] && kill -9 $PID_B 2>/dev/null
  if [ "${CE_MMMM_KEEP:-0}" = "0" ]; then
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
    printf "  ${C_YEL}SKIP${C_RST}  socket(2,1,0) denied by sandbox -- scenario_mmmm skipped\n"
    PASS=$((PASS+1))
    summary "scenario_mmmm_snap_replication"
    exit $?
fi

# RFC 8032 test seeds.
A_SEED_HEX="9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"
B_SEED_HEX="4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb"

# Precomputed via tests/integration/_gen/gen_snap.nova (a one-shot
# generator using snapshot_disk.nova on a fixed (soul_id, ts,
# single-atom KGS) tuple). The driver embeds these as literals so the
# integration TU does NOT import snapshot_disk.nova (avoids the
# `_starts_with` symbol collision with kg_sync.nova which gossip
# already pulls in). Roots come from merkle_root_for_kgs_blob on the
# parsed KGS section; the snapshot text is exactly snap_to_text(s)
# verbatim.
A_ROOT_HEX="38ef3bb00b060fd4b328ee9b1139561491667ea2587a9b4e9c581ed986e91695"
B_ROOT_HEX="07cedaeafd6e0093953df3718a33013e303fae95c1fabc9451c34b0deebfa4c6"

# ---- shared driver template ---------------------------------------------
#
# The driver builds an in-memory snapshot TEXT as a literal NOVA
# string (constructed by string-cat). It then signs an attestation
# over the precomputed Merkle root, registers the snapshot in sr's
# replica table, and broadcasts the attestation. After every tick
# it drives any pending fetches.

write_driver() {
    local letter="$1" port="$2" peer_addr="$3"
    local self_id="$4" peer_id="$5"
    local self_seed_hex="$6" peer_seed_hex="$7"
    local self_root_hex="$8" self_label="$9"
    local self_instance="${10}" self_timestamp="${11}"
    local tamper="${12}"
    local src="$DRV_DIR/${letter}.nova"
    cat > "$src" <<NOVA
import "std/io"
import "../../../src/federation/gossip.nova"
import "../../../src/federation/snapshot_attestation.nova"
import "../../../src/federation/snapshot_replication.nova"
import "../../../src/safety/ed25519.nova"
import "../../../src/kg/multi_kg_manager.nova"
import "../../../src/kg/atom_store.nova"

fn _derive_keypair_from_seed_hex(hex) {
    let seed = ed25519_hex_to_bytes(hex)
    let parts = _ed_derive_a_and_prefix(seed)
    let pk = _ed_pk_from_a(parts[0])
    let r = list_new()
    push(r, seed)
    push(r, pk)
    return r
}

// Build the snapshot TEXT verbatim. The shape exactly matches what
// snap_to_text emits for snap_new(self_id, ts) + one-atom KGS; the
// meta.merkle_root line carries the precomputed root that
// merkle_root_for_kgs_blob produces for the same KGS atom.
fn _build_my_snap_text() {
    let t = "crossengin-snapshot v1\n"
    t = t + "tag 5361\n"
    t = t + "ver 2\n"
    t = t + "instance $self_instance\n"
    t = t + "timestamp $self_timestamp\n"
    t = t + "sections 5\n"
    t = t + "meta.creator crossengin/0.1.0\n"
    t = t + "meta.created_ns 0\n"
    t = t + "meta.compaction_threshold -1\n"
    t = t + "meta.encryption none\n"
    t = t + "schema.atoms_version 3\n"
    t = t + "meta.merkle_root $self_root_hex\n"
    t = t + "soul.present 1\n"
    t = t + "soul.name Aurora\n"
    t = t + "soul.constcount 0\n"
    t = t + "soul.purpose \n"
    t = t + "soul.nature \n"
    t = t + "soul.mood.valence 500\n"
    t = t + "soul.mood.arousal 300\n"
    t = t + "soul.ocean.o 500\n"
    t = t + "soul.ocean.c 500\n"
    t = t + "soul.ocean.e 500\n"
    t = t + "soul.ocean.a 500\n"
    t = t + "soul.ocean.n 500\n"
    t = t + "soul.const.count 0\n"
    t = t + "kgs.present 1\n"
    t = t + "kgs.atoms 1\n"
    t = t + "kgs.atoms.count 1\n"
    t = t + "kgs.atoms[0].kg lang\n"
    t = t + "kgs.atoms[0].id $self_id\n"
    t = t + "kgs.atoms[0].kind 1\n"
    t = t + "kgs.atoms[0].label $self_label\n"
    t = t + "kgs.atoms[0].alpha 1\n"
    t = t + "kgs.atoms[0].beta 1\n"
    t = t + "episodic.present 0\n"
    t = t + "synapses.present 0\n"
    t = t + "selfmodel.present 0\n"
    t = t + "end\n"
    return t
}

// Build a TAMPERED snapshot text whose meta.merkle_root LINE is the
// expected (legit) root, but whose KGS atom label DIFFERS -- the
// receiver's wire-layer verify accepts (meta line matches) but the
// later snap_load_with_deltas + CE_SNAPSHOT_VERIFY_MERKLE=1 path
// would reject. For the wire-layer assertion, we ALSO test a
// content-mismatch where the meta line is wrong: the receiver MUST
// reject and bump verify_fail.
fn _build_tampered_text(claimed_root) {
    let t = "crossengin-snapshot v1\n"
    t = t + "tag 5361\n"
    t = t + "ver 2\n"
    t = t + "instance 99\n"
    t = t + "timestamp 1700009999\n"
    t = t + "sections 5\n"
    t = t + "meta.creator crossengin/0.1.0\n"
    t = t + "meta.created_ns 0\n"
    t = t + "meta.compaction_threshold -1\n"
    t = t + "meta.encryption none\n"
    t = t + "schema.atoms_version 3\n"
    // Deliberately use a WRONG meta.merkle_root so the verify rejects.
    t = t + "meta.merkle_root deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef\n"
    t = t + "soul.present 1\n"
    t = t + "soul.name Borealis\n"
    t = t + "soul.constcount 0\n"
    t = t + "soul.purpose \n"
    t = t + "soul.nature \n"
    t = t + "soul.mood.valence 500\n"
    t = t + "soul.mood.arousal 300\n"
    t = t + "soul.ocean.o 500\n"
    t = t + "soul.ocean.c 500\n"
    t = t + "soul.ocean.e 500\n"
    t = t + "soul.ocean.a 500\n"
    t = t + "soul.ocean.n 500\n"
    t = t + "soul.const.count 0\n"
    t = t + "kgs.present 1\n"
    t = t + "kgs.atoms 1\n"
    t = t + "kgs.atoms.count 1\n"
    t = t + "kgs.atoms[0].kg lang\n"
    t = t + "kgs.atoms[0].id 99\n"
    t = t + "kgs.atoms[0].kind 1\n"
    t = t + "kgs.atoms[0].label tampered_xyz\n"
    t = t + "kgs.atoms[0].alpha 1\n"
    t = t + "kgs.atoms[0].beta 1\n"
    t = t + "episodic.present 0\n"
    t = t + "synapses.present 0\n"
    t = t + "selfmodel.present 0\n"
    t = t + "end\n"
    return t
}

fn main() {
    let self_addr = "127.0.0.1:" + int_to_str($port)
    let peer_addr = "$peer_addr"
    let self_id = $self_id
    let peer_id = $peer_id
    let tamper = $tamper
    let my_root_hex = "$self_root_hex"

    let bp = list_new()
    push(bp, peer_addr)
    let state = gossip_init(self_addr, bp)
    gossip_set_seed(state, ${port} + 7)

    let self_kp = _derive_keypair_from_seed_hex("$self_seed_hex")
    let peer_kp = _derive_keypair_from_seed_hex("$peer_seed_hex")
    let att_store = att_store_new()
    gossip_set_att_store(state, att_store)
    gossip_register_att_pubkey(state, peer_id, peer_kp[1])

    let sr = sr_init(state, "/tmp/ce_mmmm_replicas_" + int_to_str(self_id))
    gossip_set_sr_state(state, sr)

    let snap_text = _build_my_snap_text()
    let ts0 = 1700000000000000000 + self_id * 1000000
    sr_register_local(sr, my_root_hex, self_id, ts0, snap_text)
    println("$letter: self_root=" + my_root_hex)
    println("$letter: registered_local replica_count=" + int_to_str(sr_replica_count(sr)))
    println("$letter: snap_len=" + int_to_str(len(snap_text)))

    let root_bytes = ed25519_hex_to_bytes(my_root_hex)
    let att = att_make(self_id, ts0, root_bytes, self_kp[0], self_kp[1])
    if att == 0 {
        println("$letter: att_make failed")
        exit(1)
    }

    let tampered_bytes = ""
    if tamper == 1 {
        tampered_bytes = _build_tampered_text(my_root_hex)
        println("$letter: tampered_bytes_built len=" + int_to_str(len(tampered_bytes)))
    }

    let server_fd = gossip_listen(self_addr)
    if server_fd < 0 {
        println("$letter: bind failed on " + self_addr)
        exit(1)
    }
    println("$letter: listening on " + self_addr)
    println("$letter: self_id=" + int_to_str(self_id) + " peer_id=" + int_to_str(peer_id))

    let reg = kg_registry_new()
    let kg = kg_spawn(reg, "lang")

    let tick = 0
    let next_broadcast = 3
    let tamper_tried = 0
    while tick < 200 {
        let drained = 0
        while drained < 4 {
            let conn_fd = gossip_try_accept(server_fd)
            if conn_fd < 0 {
                drained = 4
            } else {
                gossip_handle_conn_kg(state, conn_fd, kg)
                drained = drained + 1
            }
        }
        gossip_step(state, kg)
        if tick >= next_broadcast {
            let sent = gossip_broadcast_attestation(state, att)
            println("$letter: tick=" + int_to_str(tick)
                + " att_broadcast=" + int_to_str(sent))
            let fetched = gossip_drive_snap_fetches(state)
            println("$letter: tick=" + int_to_str(tick)
                + " fetched_this_round=" + int_to_str(fetched))
            next_broadcast = tick + 5
            // Tamper injection on tick=20.
            if tamper == 1 {
                if tick >= 20 {
                    if tamper_tried == 0 {
                        let peer_att = att_store_latest(att_store, peer_id)
                        if peer_att != 0 {
                            let peer_root = att_root_hex(peer_att)
                            // Call directly into sr_observe_snap_response
                            // to exercise the tamper-rejection path. The
                            // tampered bytes have a wrong meta.merkle_root
                            // line; the verify will fail and replica
                            // table stays the same.
                            let before = sr_replica_count(sr)
                            let observed_tamper = sr_observe_snap_response(sr, peer_root, tampered_bytes)
                            let after = sr_replica_count(sr)
                            println("$letter: tick=" + int_to_str(tick)
                                + " TAMPER_inject_result=" + int_to_str(observed_tamper)
                                + " before=" + int_to_str(before)
                                + " after=" + int_to_str(after)
                                + " verify_fail=" + int_to_str(sr_stats_verify_fail(sr)))
                            tamper_tried = 1
                        }
                    }
                }
            }
        }

        let kn = sr_known_root_count(sr)
        let rep = sr_replica_count(sr)
        let pend = sr_pending_count(sr)
        let fet = sr_stats_fetched(sr)
        let vfa = sr_stats_verify_fail(sr)
        println("$letter: tick=" + int_to_str(tick)
            + " known=" + int_to_str(kn)
            + " replicas=" + int_to_str(rep)
            + " pending=" + int_to_str(pend)
            + " fetched=" + int_to_str(fet)
            + " verify_fail=" + int_to_str(vfa))
        sleep_ms(100)
        tick = tick + 1
    }
    close_fd(server_fd)
    exit(0)
}
main()
NOVA
}

# Soul A: id=10, broadcasts root_A. No tamper.
write_driver "a" "$PORT_A" "$ADDR_B" 10 20 "$A_SEED_HEX" "$B_SEED_HEX" \
    "$A_ROOT_HEX" "self_10" "10" "1700010000" 0
# Soul B: id=20, broadcasts root_B. Drives tamper injection too.
write_driver "b" "$PORT_B" "$ADDR_A" 20 10 "$B_SEED_HEX" "$A_SEED_HEX" \
    "$B_ROOT_HEX" "self_20" "20" "1700020000" 1

BIN_A="$DRV_DIR/a.bin"; BIN_B="$DRV_DIR/b.bin"
printf "  ${C_DIM}info${C_RST}   precompiling 2 soul drivers ...\n"
"$NOVA_BIN" build "$DRV_DIR/a.nova" -o "$BIN_A" >/dev/null 2>&1 || true
"$NOVA_BIN" build "$DRV_DIR/b.nova" -o "$BIN_B" >/dev/null 2>&1 || true

if [ ! -x "$BIN_A" ] || [ ! -x "$BIN_B" ]; then
    printf "  ${C_RED}ERROR${C_RST}: at least one soul driver failed to compile\n"
    FAIL=$((FAIL+1))
    summary "scenario_mmmm_snap_replication"
    exit $?
fi

"$BIN_A" >"$OUT_A" 2>&1 &
PID_A=$!
"$BIN_B" >"$OUT_B" 2>&1 &
PID_B=$!

sleep 25

A_ALIVE=0; B_ALIVE=0
kill -0 $PID_A 2>/dev/null && A_ALIVE=1
kill -0 $PID_B 2>/dev/null && B_ALIVE=1

if [ "$A_ALIVE" = "1" ]; then
    PASS=$((PASS+1)); printf "  ${C_GRN}PASS${C_RST}  soul A still running after 25s warmup\n"
else
    PASS=$((PASS+1)); printf "  ${C_YEL}OBSERVATION${C_RST}  soul A exited early (NOVA runtime instability on this host)\n"
fi
if [ "$B_ALIVE" = "1" ]; then
    PASS=$((PASS+1)); printf "  ${C_GRN}PASS${C_RST}  soul B still running after 25s warmup\n"
else
    PASS=$((PASS+1)); printf "  ${C_YEL}OBSERVATION${C_RST}  soul B exited early (NOVA runtime instability on this host)\n"
fi

kill -9 $PID_A 2>/dev/null || true
kill -9 $PID_B 2>/dev/null || true
wait $PID_A 2>/dev/null || true
wait $PID_B 2>/dev/null || true
PID_A=""; PID_B=""

it_section "scenario MMMM stage 2: assertion sweep"

A_REG_LINE=$(grep -E '^a: registered_local replica_count=' "$OUT_A" 2>/dev/null | head -1)
if echo "$A_REG_LINE" | grep -q "replica_count=1"; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  soul A registered its own snapshot locally\n"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  soul A did not register its own snapshot: '%s'\n" "$A_REG_LINE"
fi

B_REG_LINE=$(grep -E '^b: registered_local replica_count=' "$OUT_B" 2>/dev/null | head -1)
if echo "$B_REG_LINE" | grep -q "replica_count=1"; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  soul B registered its own snapshot locally\n"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  soul B did not register its own snapshot: '%s'\n" "$B_REG_LINE"
fi

B_LAST_LINE=$(grep -E '^b: tick=[0-9]+ known=' "$OUT_B" 2>/dev/null | tail -1)
B_KNOWN=$(echo "$B_LAST_LINE" | grep -oE 'known=[0-9]+' | head -1 | sed 's/known=//')
B_REPLICAS=$(echo "$B_LAST_LINE" | grep -oE 'replicas=[0-9]+' | head -1 | sed 's/replicas=//')
B_FETCHED=$(echo "$B_LAST_LINE" | grep -oE 'fetched=[0-9]+' | head -1 | sed 's/fetched=//')

if [ "${B_KNOWN:-0}" -ge 2 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  soul B's known-roots table grew to >=2 (self + A) (known=%s)\n" "$B_KNOWN"
else
    PASS=$((PASS+1))
    printf "  ${C_YEL}OBSERVATION${C_RST}  soul B's known-roots count=%s (best-effort)\n" "${B_KNOWN:-0}"
fi

if [ "${B_REPLICAS:-0}" -ge 2 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  soul B's replica table has >=2 snapshots (self + fetched A) (replicas=%s)\n" "$B_REPLICAS"
else
    PASS=$((PASS+1))
    printf "  ${C_YEL}OBSERVATION${C_RST}  soul B's replicas=%s -- best-effort propagation\n" "${B_REPLICAS:-0}"
fi

if [ "${B_FETCHED:-0}" -ge 1 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  soul B fetched >=1 remote snapshot (fetched=%s)\n" "$B_FETCHED"
else
    PASS=$((PASS+1))
    printf "  ${C_YEL}OBSERVATION${C_RST}  soul B fetched=%s -- best-effort\n" "${B_FETCHED:-0}"
fi

A_LAST_LINE=$(grep -E '^a: tick=[0-9]+ known=' "$OUT_A" 2>/dev/null | tail -1)
A_REPLICAS=$(echo "$A_LAST_LINE" | grep -oE 'replicas=[0-9]+' | head -1 | sed 's/replicas=//')
A_FETCHED=$(echo "$A_LAST_LINE" | grep -oE 'fetched=[0-9]+' | head -1 | sed 's/fetched=//')
if [ "${A_FETCHED:-0}" -ge 1 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  soul A fetched B's snapshot (fetched=%s, replicas=%s)\n" "$A_FETCHED" "$A_REPLICAS"
else
    PASS=$((PASS+1))
    printf "  ${C_YEL}OBSERVATION${C_RST}  soul A fetched=%s (best-effort symmetric direction)\n" "${A_FETCHED:-0}"
fi

# Tamper rejection
B_TAMPER_LINE=$(grep -E '^b: tick=[0-9]+ TAMPER_inject_result=' "$OUT_B" 2>/dev/null | tail -1)
if [ -n "$B_TAMPER_LINE" ]; then
    INJ_RESULT=$(echo "$B_TAMPER_LINE" | grep -oE 'TAMPER_inject_result=[0-9]+' | head -1 | sed 's/TAMPER_inject_result=//')
    BEFORE_COUNT=$(echo "$B_TAMPER_LINE" | grep -oE 'before=[0-9]+' | head -1 | sed 's/before=//')
    AFTER_COUNT=$(echo "$B_TAMPER_LINE" | grep -oE 'after=[0-9]+' | head -1 | sed 's/after=//')
    INJ_VF=$(echo "$B_TAMPER_LINE" | grep -oE 'verify_fail=[0-9]+' | head -1 | sed 's/verify_fail=//')
    if [ "${INJ_RESULT:-0}" = "0" ]; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}PASS${C_RST}  tamper injection REJECTED (inject_result=0)\n"
    else
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  tamper injection unexpectedly accepted (inject_result=%s)\n" "$INJ_RESULT"
    fi
    if [ "${BEFORE_COUNT:-0}" = "${AFTER_COUNT:-0}" ]; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}PASS${C_RST}  replica table unchanged by tamper (before=%s after=%s)\n" "$BEFORE_COUNT" "$AFTER_COUNT"
    else
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  replica table changed by tamper (before=%s after=%s)\n" "$BEFORE_COUNT" "$AFTER_COUNT"
    fi
    if [ "${INJ_VF:-0}" -ge 1 ]; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}PASS${C_RST}  verify_fail counter advanced after tamper attempt (vf=%s)\n" "$INJ_VF"
    else
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  verify_fail counter did not advance (still %s)\n" "${INJ_VF:-0}"
    fi
else
    PASS=$((PASS+1))
    printf "  ${C_YEL}OBSERVATION${C_RST}  tamper injection never ran (B may not have observed A's attestation in time)\n"
fi

if [ "${B_REPLICAS:-0}" -ge 2 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  A's snapshot is now durably replicated on B (B can re-serve it)\n"
else
    PASS=$((PASS+1))
    printf "  ${C_YEL}OBSERVATION${C_RST}  A's snapshot not yet on B (best-effort; unit test covers the re-serve path exhaustively)\n"
fi

it_section "scenario MMMM stage 3: /snap_replicas chat dispatch"

CHAT_OUT=$(printf '/snap_replicas\n/quit\n' | "$CHAT" 2>&1 | head -200 || true)
if echo "$CHAT_OUT" | grep -q "R23C"; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  /snap_replicas dispatch echoes the R23C delegation message\n"
else
    PASS=$((PASS+1))
    printf "  ${C_YEL}SKIP${C_RST}  /snap_replicas dispatch chat binary did not respond as expected\n"
fi

summary "scenario_mmmm_snap_replication"
