#!/usr/bin/env bash
# Scenario FFF -- R13F: incremental delta-snapshot writes.
#
# Verifies the new src/persistence/snapshot_delta.nova module:
#
#   1. A 1000-atom KG round-trips through a full snapshot + a 10-op delta
#      and reload preserves the post-delta state (1010 atoms).
#   2. The compaction path collapses 5 sibling deltas into a fresh full
#      snapshot and prunes them (5 -> 0).
#   3. The episodic blob in the parent survives the delta + compact
#      round-trip (R6F preservation).
#   4. The delta-write hot path is at least 1.5x faster than the full
#      snapshot write on a 1000-atom KG, and at least 2x faster on a
#      5000-atom KG (where serialize+write dominate the fsync floor).
#
# Implementation: an in-process NOVA driver (./_scenario_fff_drivers/
# delta_bench_driver.nova) does the heavy lifting and prints
# `key=value\n` lines that this script greps for and asserts on. The
# driver pattern matches scenario_pp's federated-byz driver -- a
# single binary that exercises the module via its real API rather
# than going through the chat (which would need delta-aware admin
# commands that R13F deliberately does not ship -- the substrate's
# delta hook is library-level, not operator-level, for this round).

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

PARENT="/tmp/ce_int_scenario_fff.snap"
DRIVER="$(dirname "$0")/_scenario_fff_drivers/delta_bench_driver.nova"
trap 'rm -f "$PARENT" "$PARENT".delta.* "$PARENT".tmp "$PARENT".warm_tmp \
            "$PARENT".big "$PARENT".big.delta.* "$PARENT".big.tmp \
            "$PARENT".big.warm_tmp' EXIT
rm -f "$PARENT" "$PARENT".delta.* "$PARENT".tmp "$PARENT".warm_tmp \
      "$PARENT".big "$PARENT".big.delta.* "$PARENT".big.tmp \
      "$PARENT".big.warm_tmp

it_section "scenario FFF: incremental delta-snapshot writes (R13F)"

# Pre-flight: the driver file must exist.
if [ ! -f "$DRIVER" ]; then
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  driver not found at %s\n" "$DRIVER"
    summary "scenario_fff_snap_delta"
    exit 1
fi

NOVA_ROOT="${NOVA_ROOT:-$HOME/NOVA}"
NOVA="$NOVA_ROOT/nova"

if [ ! -x "$NOVA" ]; then
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  NOVA launcher missing at %s\n" "$NOVA"
    summary "scenario_fff_snap_delta"
    exit 1
fi

# Run the driver. CE_FFF_PARENT names the parent-snapshot path the
# driver writes / reads (cleaned at start + end).
DRIVER_OUT=$(CE_FFF_PARENT="$PARENT" "$NOVA" run "$DRIVER" 2>&1)
DRIVER_RC=$?

if [ $DRIVER_RC -ne 0 ]; then
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  driver exited %d\n" "$DRIVER_RC"
    echo "$DRIVER_OUT" | sed 's/^/        /'
    summary "scenario_fff_snap_delta"
    exit 1
fi

# Parse the kv lines.
get_val() {
    echo "$DRIVER_OUT" | grep "^$1=" | tail -1 | cut -d'=' -f2-
}

ATOMS=$(get_val atoms)
FULL_NS=$(get_val full_write_ns)
FULL_BYTES=$(get_val full_write_bytes)
DELTA_NS=$(get_val delta_write_ns)
DELTA_BYTES=$(get_val delta_write_bytes)
DELTA_SER_NS=$(get_val delta_serialize_ns)
DELTA_COUNT_BEFORE=$(get_val delta_count_before)
COMPACT_REMOVED=$(get_val compact_removed)
DELTA_COUNT_AFTER=$(get_val delta_count_after)
RELOAD_OK=$(get_val reload_ok)
RELOAD_ATOMS=$(get_val reload_atom_count)
EP_OK=$(get_val episodic_preserved)
BIG_FULL_NS=$(get_val big_full_write_ns)
BIG_FULL_BYTES=$(get_val big_full_write_bytes)
BIG_DELTA_NS=$(get_val big_delta_write_ns)

# ---- structural assertions on the driver output --------------------------

assert_eq "$ATOMS" "1000" "driver reports 1000-atom KG (bench population)"

if [ -n "$FULL_NS" ] && [ "$FULL_NS" -gt 0 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  full-snapshot write took ${FULL_NS}ns (==%sms)\n" \
        "$((FULL_NS / 1000000))"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  full_write_ns missing or zero\n"
fi

if [ -n "$DELTA_NS" ] && [ "$DELTA_NS" -gt 0 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  delta-snapshot write took ${DELTA_NS}ns (==%sms)\n" \
        "$((DELTA_NS / 1000000))"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  delta_write_ns missing or zero\n"
fi

assert_eq "$FULL_BYTES" "152861" "full snapshot of 1000-atom KG is 152861 bytes"

if [ -n "$DELTA_BYTES" ] && [ "$DELTA_BYTES" -gt 0 ] && [ "$DELTA_BYTES" -lt 1024 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  delta of 10 ADDs is ${DELTA_BYTES} bytes (< 1KB)\n"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  delta size unexpected: %s bytes\n" "${DELTA_BYTES:-MISSING}"
fi

# Serialize cost should be very low (microseconds) -- proves the cost is
# really in the syscall + fsync, not in text formatting.
if [ -n "$DELTA_SER_NS" ] && [ "$DELTA_SER_NS" -lt 1000000 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  delta serialize cost %sns (< 1ms)\n" "$DELTA_SER_NS"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  delta serialize too slow: %sns\n" "${DELTA_SER_NS:-MISSING}"
fi

# ---- delta-vs-full speedup on the 1000-atom KG ---------------------------
#
# The hot path is dominated by the fsync floor on this test machine
# (~2 ms on tmpfs/ext4), so a 1.5x speedup is the realistic target at
# 1000 atoms. The big-KG bench (5000 atoms) shows the architecture's
# scaling characteristics where serialize+write dominate.
SPEEDUP_X100=$((FULL_NS * 100 / DELTA_NS))
if [ "$SPEEDUP_X100" -ge 150 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  delta is %d.%02dx faster than full on 1000-atom KG\n" \
        "$((SPEEDUP_X100 / 100))" "$((SPEEDUP_X100 % 100))"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  delta speedup only %d.%02dx (need >= 1.5x)\n" \
        "$((SPEEDUP_X100 / 100))" "$((SPEEDUP_X100 % 100))"
fi

# ---- 5000-atom bench: serialize+write dominate; expect bigger gap --------

if [ -n "$BIG_FULL_NS" ] && [ -n "$BIG_DELTA_NS" ] && [ "$BIG_DELTA_NS" -gt 0 ]; then
    BIG_SPEEDUP_X100=$((BIG_FULL_NS * 100 / BIG_DELTA_NS))
    if [ "$BIG_SPEEDUP_X100" -ge 200 ]; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}PASS${C_RST}  delta is %d.%02dx faster than full on 5000-atom KG (big_full=%sns big_delta=%sns)\n" \
            "$((BIG_SPEEDUP_X100 / 100))" "$((BIG_SPEEDUP_X100 % 100))" \
            "$BIG_FULL_NS" "$BIG_DELTA_NS"
    else
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  big-KG delta speedup only %d.%02dx (need >= 2x)\n" \
            "$((BIG_SPEEDUP_X100 / 100))" "$((BIG_SPEEDUP_X100 % 100))"
    fi
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  big-KG bench numbers missing\n"
fi

# ---- compaction ----------------------------------------------------------

assert_eq "$DELTA_COUNT_BEFORE" "5" "5 deltas pending pre-compact"
assert_eq "$COMPACT_REMOVED" "5" "snap_delta_compact pruned 5 deltas"
assert_eq "$DELTA_COUNT_AFTER" "0" "0 deltas remain post-compact"

# ---- reload + state verification -----------------------------------------

assert_eq "$RELOAD_OK" "1" "reload after compact reproduces post-delta state"
# 1000 original + 10 from first delta + 4 from compact-prep deltas = 1014
assert_eq "$RELOAD_ATOMS" "1014" "reloaded atom count = 1014 (1000 parent + 14 from deltas)"

# ---- R6F episodic preservation -------------------------------------------

assert_eq "$EP_OK" "1" "episodic blob preserved through delta + compact round-trip"

# ---- final cleanup is in the trap ---------------------------------------

summary "scenario_fff_snap_delta"
