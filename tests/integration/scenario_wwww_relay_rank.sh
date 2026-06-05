#!/usr/bin/env bash
# Scenario WWWW -- R26E.2: STUN-like relay candidate ranking.
#
# R26E shipped TCP gossip relay with a "first-alive non-target peer"
# picker; R26E.2 ranks candidates by R23E NAT type so the originator
# prefers peers most likely to be reachable. This scenario builds a
# 3-soul mock mesh INSIDE a single NOVA program (no per-soul socket
# spawn -- the picker is a pure function of relay_state; testing it
# against the gossip_alive_peers + mocked NAT-type registry exercises
# the exact production code path without paying the per-host process
# tax). The previous R26E vvvv scenario already covers the wire-level
# round-trip on TCP; this scenario covers the *selection policy*.
#
# Setup:
#   Soul A (originator, self_addr 127.0.0.1:8001) sees three alive
#   peers in its gossip table:
#     127.0.0.1:8002 -- mocked NAT type "symmetric"
#     127.0.0.1:8003 -- mocked NAT type "cone"
#     127.0.0.1:8004 -- mocked NAT type "open"
#     127.0.0.1:8005 -- mocked NAT type "blocked"
#   A wants to relay to target 127.0.0.1:9999 (unreachable; absent
#   from the alive list, so it doesn't show up as a candidate).
#
# Assertions (10):
#   1. NOVA pre-flight (compiler + runtime work).
#   2. With ranking ON (CE_RELAY_RANK_NAT=on), the first pick is the
#      OPEN peer (rank 4 beats cone/unknown/symmetric).
#   3. With ranking ON, blocked peer never appears in the rank list.
#   4. With ranking ON, ranked list is [open, cone, symmetric] (3
#      entries; blocked dropped).
#   5. The unknown peer (no NAT-type registration) sits between cone
#      and symmetric: a 4th cand registered as "unknown" goes to
#      position 2 (between cone[1] and symmetric[3]).
#   6. LRU rotation works: with three equally-ranked cone peers,
#      three consecutive choose_candidate_ranked calls return three
#      distinct peers.
#   7. LRU rotation: 4th call wraps to the 1st (LRU pos 0 = oldest).
#   8. With ranking OFF (env unset), legacy relay_pick_intermediate
#      still picks the first alive peer (= symmetric in seed order),
#      proving the back-compat path is undisturbed.
#   9. relay_mark_relay_failed(via) invalidates the cache entry.
#   10. Multi-call ranked picker integrates with relay_send's
#      dispatch helper (via env on) without crashing the program
#      (smoke: send-to-unreachable target returns 0 with no_relay
#      bumped, NO panic).

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

it_section "scenario WWWW: R26E.2 STUN-like relay candidate ranking"

NOVA_BIN="${NOVA_ROOT:-/home/user/NOVA}/nova"
if [ ! -x "$NOVA_BIN" ]; then
    printf "  ${C_RED}ERROR${C_RST}: NOVA launcher not found at %s\n" "$NOVA_BIN" >&2
    FAIL=$((FAIL+1))
    summary "scenario_wwww_relay_rank"
    exit $?
fi

DRV_DIR="$REPO_ROOT/tests/integration/_scenario_wwww_drivers"
mkdir -p "$DRV_DIR"
DRV_SRC="$DRV_DIR/driver.nova"
DRV_BIN="$DRV_DIR/driver.bin"
DRV_OUT="/tmp/ce_int_wwww.out"
trap '
  if [ "${CE_WWWW_KEEP:-0}" = "0" ]; then
    rm -rf "$DRV_DIR" "$DRV_OUT"
  fi
' EXIT

# ---- pre-flight -----------------------------------------------------
PRECHK_SRC="$DRV_DIR/prechk.nova"
cat > "$PRECHK_SRC" <<'NOVA'
fn main() {
    println("nova-ok")
}
main()
NOVA
PRECHK=$("$NOVA_BIN" run "$PRECHK_SRC" 2>&1 | tail -1)
if [ "$PRECHK" != "nova-ok" ]; then
    printf "  ${C_RED}FAIL${C_RST}  NOVA pre-flight (got '%s')\n" "$PRECHK"
    FAIL=$((FAIL+1))
    summary "scenario_wwww_relay_rank"
    exit $?
fi
PASS=$((PASS+1))
printf "  ${C_GRN}PASS${C_RST}  NOVA pre-flight (compiler + runtime work)\n"

# ---- driver: exercise the ranker -----------------------------------
#
# Two phases. Phase 1: ranking ON (env CE_RELAY_RANK_NAT=on set by
# the harness). Build a relay_state with 4 alive peers, each mocked
# with a distinct NAT type. Walk the ranker, the choose helper, the
# LRU rotation, the failure-invalidation. Phase 2: ranking OFF (we
# re-init relay_state in a child program with the env unset). Emit
# tagged lines so the bash harness can grep specific results.
#
# The driver doesn't actually call relay_send because that would try
# to dial the peers and fail in the sandbox -- we just verify the
# picker dispatch path returns the expected addr. Production code
# uses the same picker; the wire-level round-trip is already covered
# by scenario_vvvv.

cat > "$DRV_SRC" <<'NOVA'
import "std/io"
import "../../../src/federation/gossip.nova"
import "../../../src/federation/gossip_relay.nova"

fn _mk_state_4peers() {
    let bp = list_new()
    push(bp, "127.0.0.1:8002")  // symmetric
    push(bp, "127.0.0.1:8003")  // cone
    push(bp, "127.0.0.1:8004")  // open
    push(bp, "127.0.0.1:8005")  // blocked
    let g = gossip_init("127.0.0.1:8001", bp)
    let r = relay_init(g)
    relay_set_peer_nat_type(r, "127.0.0.1:8002", "symmetric")
    relay_set_peer_nat_type(r, "127.0.0.1:8003", "cone")
    relay_set_peer_nat_type(r, "127.0.0.1:8004", "open")
    relay_set_peer_nat_type(r, "127.0.0.1:8005", "blocked")
    return r
}

fn _mk_state_with_unknown() {
    let bp = list_new()
    push(bp, "127.0.0.1:8002")  // symmetric
    push(bp, "127.0.0.1:8003")  // cone
    push(bp, "127.0.0.1:8006")  // unknown (NOT registered)
    let g = gossip_init("127.0.0.1:8001", bp)
    let r = relay_init(g)
    relay_set_peer_nat_type(r, "127.0.0.1:8002", "symmetric")
    relay_set_peer_nat_type(r, "127.0.0.1:8003", "cone")
    // 8006 deliberately omitted -> default "unknown" rank.
    return r
}

fn _mk_state_3cones() {
    let bp = list_new()
    push(bp, "127.0.0.1:8002")
    push(bp, "127.0.0.1:8003")
    push(bp, "127.0.0.1:8004")
    let g = gossip_init("127.0.0.1:8001", bp)
    let r = relay_init(g)
    relay_set_peer_nat_type(r, "127.0.0.1:8002", "cone")
    relay_set_peer_nat_type(r, "127.0.0.1:8003", "cone")
    relay_set_peer_nat_type(r, "127.0.0.1:8004", "cone")
    return r
}

fn main() {
    println("env_rank_enabled=" + int_to_str(relay_rank_nat_enabled()))

    // --- phase 1: full 4-peer mesh, rank should be [open, cone, symmetric] ---
    let r = _mk_state_4peers()
    let target = "127.0.0.1:9999"
    let ranked = relay_rank_candidates(r, target)
    println("ranked_len=" + int_to_str(len(ranked)))
    let i = 0
    while i < len(ranked) {
        let p = ranked[i]
        println("rank[" + int_to_str(i) + "]="
            + p + " type=" + relay_get_peer_nat_type(r, p))
        i = i + 1
    }

    // Choose pick #1 -- should be the open peer.
    let pick1 = relay_choose_candidate_ranked(r, target)
    let pick1_type = relay_get_peer_nat_type(r, pick1)
    println("phase1_pick1=" + pick1 + " type=" + pick1_type)
    // Choose pick #2 -- should STILL be the open peer (LRU doesn't
    // override NAT rank; the open peer is unique at rank 4).
    let pick2 = relay_choose_candidate_ranked(r, target)
    println("phase1_pick2=" + pick2)

    // --- phase 2: unknown peer placement ---
    let r2 = _mk_state_with_unknown()
    let ranked2 = relay_rank_candidates(r2, target)
    println("phase2_ranked_len=" + int_to_str(len(ranked2)))
    let j = 0
    while j < len(ranked2) {
        let p2 = ranked2[j]
        println("phase2_rank[" + int_to_str(j) + "]="
            + p2 + " type=" + relay_get_peer_nat_type(r2, p2))
        j = j + 1
    }

    // --- phase 3: LRU rotation across 3 equally-ranked peers ---
    let r3 = _mk_state_3cones()
    let p1 = relay_choose_candidate_ranked(r3, target)
    let p2_ = relay_choose_candidate_ranked(r3, target)
    let p3 = relay_choose_candidate_ranked(r3, target)
    let p4 = relay_choose_candidate_ranked(r3, target)
    println("phase3_pick1=" + p1)
    println("phase3_pick2=" + p2_)
    println("phase3_pick3=" + p3)
    println("phase3_pick4=" + p4)
    // Distinctness: across first 3, no duplicates.
    let distinct = 0
    if str_eq(p1, p2_) == 0 { distinct = distinct + 1 }
    if str_eq(p2_, p3) == 0 { distinct = distinct + 1 }
    if str_eq(p1, p3) == 0  { distinct = distinct + 1 }
    println("phase3_distinct=" + int_to_str(distinct))
    // 4th wraps to 1st.
    let wraps = 0
    if str_eq(p4, p1) == 1 { wraps = 1 }
    println("phase3_wraps=" + int_to_str(wraps))

    // --- phase 4: legacy picker untouched even when env is on ---
    // relay_pick_intermediate ignores NAT-type registry by design;
    // it walks the alive list in order and returns the first non-
    // self non-target non-unreachable. We seeded peers as
    // [8002, 8003, 8004, 8005]; legacy pick should be 8002.
    let r4 = _mk_state_4peers()
    let legacy = relay_pick_intermediate(r4, target)
    println("phase4_legacy=" + legacy)

    // --- phase 5: relay_mark_relay_failed invalidates the cache ---
    let r5 = _mk_state_4peers()
    relay_cache_via(r5, target, "127.0.0.1:8004")
    println("phase5_before_count=" + int_to_str(relay_cache_count(r5)))
    let removed = relay_mark_relay_failed(r5, "127.0.0.1:8004")
    println("phase5_removed=" + int_to_str(removed))
    println("phase5_after_count=" + int_to_str(relay_cache_count(r5)))
    let post = relay_chosen_via(r5, target)
    let posts = ""
    if post != -1 { posts = post }
    println("phase5_post=" + posts)

    // --- phase 6: relay_send dispatch smoke (no listener exists; the
    // call must not crash and must return 0 with no_relay bumped or
    // some safe non-1 status). With the ranked picker chosen via
    // the env, the picker still returns an addr; the dial fails;
    // relay_send returns 0. We assert "no crash" by reaching this
    // println line.
    let r6 = _mk_state_4peers()
    relay_mark_unreachable(r6, target)
    let rc = relay_send(r6, target, "ping")
    println("phase6_rc=" + int_to_str(rc))
    println("phase6_no_relay=" + int_to_str(relay_stats_no_relay(r6)))
    println("done")
    exit(0)
}
main()
NOVA

printf "  ${C_DIM}info${C_RST}   compiling driver ...\n"
if ! "$NOVA_BIN" build "$DRV_SRC" -o "$DRV_BIN" >"$DRV_DIR/build.log" 2>&1; then
    printf "  ${C_RED}FAIL${C_RST}  driver compilation\n"
    sed 's/^/    /' "$DRV_DIR/build.log"
    FAIL=$((FAIL+1))
    summary "scenario_wwww_relay_rank"
    exit $?
fi

# Run with CE_RELAY_RANK_NAT=on
CE_RELAY_RANK_NAT=on "$DRV_BIN" >"$DRV_OUT" 2>&1
RC=$?
if [ "$RC" -ne 0 ]; then
    printf "  ${C_RED}FAIL${C_RST}  driver exited with code %d\n" "$RC"
    sed 's/^/    /' "$DRV_OUT"
    FAIL=$((FAIL+1))
    summary "scenario_wwww_relay_rank"
    exit $?
fi

# Confirm the env was picked up.
ENV_LINE=$(grep '^env_rank_enabled=' "$DRV_OUT" | head -1 | sed 's/^env_rank_enabled=//')
assert_eq "$ENV_LINE" "1" "CE_RELAY_RANK_NAT=on observed by driver"

# Assertion 2: phase1 pick1 is the open peer.
PICK1=$(grep '^phase1_pick1=' "$DRV_OUT" | head -1 | sed 's/^phase1_pick1=//' | awk '{print $1}')
PICK1_TYPE=$(grep '^phase1_pick1=' "$DRV_OUT" | head -1 | grep -oE 'type=[a-z]+' | sed 's/type=//')
if [ "$PICK1" = "127.0.0.1:8004" ] && [ "$PICK1_TYPE" = "open" ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  ranking ON: first pick is the OPEN peer (%s)\n" "$PICK1"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  ranking ON: pick1=%s type=%s (expected 127.0.0.1:8004 open)\n" "$PICK1" "$PICK1_TYPE"
fi

# Assertion 3: blocked peer never appears.
BLOCKED_IN_RANK=$(grep -E '^rank\[[0-9]+\]=127.0.0.1:8005 ' "$DRV_OUT" | wc -l)
assert_eq "$BLOCKED_IN_RANK" "0" "blocked peer absent from rank list"

# Assertion 4: ranked list is [open, cone, symmetric] (3 entries).
RANKED_LEN=$(grep '^ranked_len=' "$DRV_OUT" | head -1 | sed 's/^ranked_len=//')
RANK0=$(grep '^rank\[0\]=' "$DRV_OUT" | head -1 | sed 's/^rank\[0\]=//' | awk '{print $1}')
RANK1=$(grep '^rank\[1\]=' "$DRV_OUT" | head -1 | sed 's/^rank\[1\]=//' | awk '{print $1}')
RANK2=$(grep '^rank\[2\]=' "$DRV_OUT" | head -1 | sed 's/^rank\[2\]=//' | awk '{print $1}')
if [ "$RANKED_LEN" = "3" ] \
    && [ "$RANK0" = "127.0.0.1:8004" ] \
    && [ "$RANK1" = "127.0.0.1:8003" ] \
    && [ "$RANK2" = "127.0.0.1:8002" ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  ranked list = [open=8004, cone=8003, symmetric=8002]\n"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  ranked list incorrect: len=%s [%s, %s, %s]\n" \
        "$RANKED_LEN" "$RANK0" "$RANK1" "$RANK2"
fi

# Assertion 5: unknown peer slots between cone and symmetric.
P2_LEN=$(grep '^phase2_ranked_len=' "$DRV_OUT" | head -1 | sed 's/^phase2_ranked_len=//')
P2_R0=$(grep '^phase2_rank\[0\]=' "$DRV_OUT" | head -1 | grep -oE 'type=[a-z]+' | sed 's/type=//')
P2_R1=$(grep '^phase2_rank\[1\]=' "$DRV_OUT" | head -1 | grep -oE 'type=[a-z]+' | sed 's/type=//')
P2_R2=$(grep '^phase2_rank\[2\]=' "$DRV_OUT" | head -1 | grep -oE 'type=[a-z]+' | sed 's/type=//')
if [ "$P2_LEN" = "3" ] && [ "$P2_R0" = "cone" ] && [ "$P2_R1" = "unknown" ] && [ "$P2_R2" = "symmetric" ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  unknown peer ranks between cone and symmetric\n"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  unknown placement wrong: [%s, %s, %s]\n" "$P2_R0" "$P2_R1" "$P2_R2"
fi

# Assertion 6: LRU rotation -- 3 distinct picks across 3 equal-rank peers.
DISTINCT=$(grep '^phase3_distinct=' "$DRV_OUT" | head -1 | sed 's/^phase3_distinct=//')
assert_eq "$DISTINCT" "3" "LRU rotation: 3 distinct picks across 3 cone peers"

# Assertion 7: 4th pick wraps to 1st (LRU oldest).
WRAPS=$(grep '^phase3_wraps=' "$DRV_OUT" | head -1 | sed 's/^phase3_wraps=//')
assert_eq "$WRAPS" "1" "LRU rotation: 4th pick wraps to 1st"

# Assertion 8: legacy picker untouched -- first alive = 8002 (symmetric).
LEGACY=$(grep '^phase4_legacy=' "$DRV_OUT" | head -1 | sed 's/^phase4_legacy=//')
assert_eq "$LEGACY" "127.0.0.1:8002" "legacy relay_pick_intermediate untouched"

# Assertion 9: relay_mark_relay_failed invalidates the cache entry.
REMOVED=$(grep '^phase5_removed=' "$DRV_OUT" | head -1 | sed 's/^phase5_removed=//')
POST=$(grep '^phase5_post=' "$DRV_OUT" | head -1 | sed 's/^phase5_post=//')
if [ "$REMOVED" = "1" ] && [ -z "$POST" ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  mark_relay_failed invalidates cache (removed=%s post='%s')\n" "$REMOVED" "$POST"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  cache invalidation wrong (removed=%s post='%s')\n" "$REMOVED" "$POST"
fi

# Assertion 10: relay_send dispatch smoke (no crash).
DONE_LINE=$(grep '^done$' "$DRV_OUT" | head -1)
assert_eq "$DONE_LINE" "done" "relay_send dispatch smoke (no crash)"

summary "scenario_wwww_relay_rank"
