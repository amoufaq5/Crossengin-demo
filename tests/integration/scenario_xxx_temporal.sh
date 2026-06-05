#!/usr/bin/env bash
# Scenario XXX -- temporal reasoning via Allen's interval algebra (R19C).
#
# Companion to scenario_xx_communities.sh (R11F LPA),
# scenario_zz_louvain.sh (R12C Louvain), scenario_eee_pagerank.sh
# (R13E PageRank), and scenario_ttt_link_prediction.sh (R18B). R19C
# ships the missing TEMPORAL-REASONING surface: given two atoms,
# decide which of Allen's 13 interval relations holds between their
# timestamps; given one atom + relation, find every atom matching;
# walk a maximal "before-chain" through time.
#
# This scenario drives both surfaces:
#   1. A tracked stand-alone driver under
#      tests/integration/_scenario_xxx_temporal_driver/ which builds
#      a 5-atom temporally-ordered fixture (each strictly before the
#      next) plus a 3-atom overlap fixture (every pair overlapping),
#      then invokes tmp_query_relation, tmp_chain, tmp_overlap_set,
#      and tmp_temporal_cmd so the shell can assert on:
#        - the temporal relation between adjacent atoms is BEFORE in
#          one direction and AFTER in the other (Allen inverse pair);
#        - /temporal 0 after on the 5-atom fixture lists atoms 1-4;
#        - /temporal 2 before on the 5-atom fixture lists atoms 0, 1;
#        - tmp_chain(0, 5) walks {0, 1, 2, 3, 4} in order;
#        - tmp_overlap_set on a triadic overlap gives all 3 ids;
#        - the missing-atom error path lands graceful.
#   2. The chat dispatch path: launch the chat binary, type
#      "/temporal", and assert the usage line + missing-atom error
#      land; also assert that /help lists /temporal.
#
# Total assertions: ~16 (above the brief's 10 target).

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

NOVA_ROOT="${NOVA_ROOT:-$HOME/NOVA}"
NOVA="$NOVA_ROOT/nova"

it_section "scenario XXX: Allen interval-algebra temporal reasoning + /temporal command"

# --- guard: NOVA toolchain available -----------------------------------
if [ ! -x "$NOVA" ]; then
    FAIL=$((FAIL+1))
    echo "FAIL: NOVA launcher not found at '$NOVA'"
    summary "scenario_xxx_temporal"
    exit 1
fi

# --- step 1: run the tracked driver ------------------------------------
DRIVER="$REPO_ROOT/tests/integration/_scenario_xxx_temporal_driver/temporal_driver.nova"
assert_file_exists "$DRIVER" "temporal driver source exists"

OUT="$("$NOVA" run "$DRIVER" 2>&1)"
RC=$?
echo "$OUT" | sed 's/^/    /'
assert_eq "$RC" "0" "temporal driver exits 0"

# --- step 2: 5-atom temporally-ordered fixture: /temporal 0 after ----
# atoms 0..4 at [10,20], [30,40], [50,60], [70,80], [90,100].
# tmp_query_relation(0, AFTER) -> {1, 2, 3, 4}.
AFTER_N=$(echo "$OUT" | grep -E '^DRIVER ordered_after_n=' | head -1 | cut -d= -f2)
AFTER_IDS=$(echo "$OUT" | grep -E '^DRIVER ordered_after_ids=' | head -1 | cut -d= -f2)
assert_eq "$AFTER_N" "4" "ordered fixture /temporal 0 after -> 4 atoms"
assert_eq "$AFTER_IDS" "[1,2,3,4]" "ordered fixture /temporal 0 after -> {1,2,3,4}"

# --- step 3: /temporal 2 before on ordered fixture --------------------
BEFORE_N=$(echo "$OUT" | grep -E '^DRIVER ordered_before_n=' | head -1 | cut -d= -f2)
BEFORE_IDS=$(echo "$OUT" | grep -E '^DRIVER ordered_before_ids=' | head -1 | cut -d= -f2)
assert_eq "$BEFORE_N" "2" "ordered fixture /temporal 2 before -> 2 atoms"
assert_eq "$BEFORE_IDS" "[0,1]" "ordered fixture /temporal 2 before -> {0,1}"

# --- step 4: tmp_chain(0, 5) walks 5 atoms in order -------------------
CHAIN_N=$(echo "$OUT" | grep -E '^DRIVER chain_len=' | head -1 | cut -d= -f2)
CHAIN_IDS=$(echo "$OUT" | grep -E '^DRIVER chain_ids=' | head -1 | cut -d= -f2)
assert_eq "$CHAIN_N" "5" "tmp_chain(0, 5) length == 5"
assert_eq "$CHAIN_IDS" "[0,1,2,3,4]" "tmp_chain(0, 5) walks {0,1,2,3,4}"

# --- step 5: Allen inverse pair (BEFORE / AFTER) ----------------------
P_01=$(echo "$OUT" | grep -E '^DRIVER pair_0_1=' | head -1 | cut -d= -f2)
P_10=$(echo "$OUT" | grep -E '^DRIVER pair_1_0=' | head -1 | cut -d= -f2)
ALLEN_BEFORE=$(echo "$OUT" | grep -E '^DRIVER ALLEN_BEFORE=' | head -1 | cut -d= -f2)
ALLEN_AFTER=$(echo "$OUT" | grep -E '^DRIVER ALLEN_AFTER=' | head -1 | cut -d= -f2)
assert_eq "$P_01" "$ALLEN_BEFORE" "tmp_relation(0, 1) == ALLEN_BEFORE"
assert_eq "$P_10" "$ALLEN_AFTER"  "tmp_relation(1, 0) == ALLEN_AFTER (inverse of BEFORE)"

# --- step 6: triadic overlap fixture: tmp_overlap_set ----------------
OV_N=$(echo "$OUT" | grep -E '^DRIVER overlap_n=' | head -1 | cut -d= -f2)
OV_IDS=$(echo "$OUT" | grep -E '^DRIVER overlap_ids=' | head -1 | cut -d= -f2)
assert_eq "$OV_N" "3" "tmp_overlap_set on triadic fixture -> 3 atoms"
assert_eq "$OV_IDS" "[0,1,2]" "tmp_overlap_set returns {0,1,2}"

# --- step 7: TEMPORAL emit-line shape (driver) ------------------------
# tmp_temporal_cmd prints exactly:
#   TEMPORAL source=X relation=NAME hits=H ids=[A B C ...]
assert_match "$OUT" "^TEMPORAL source=0 relation=after hits=4 ids=\[1 2 3 4\]" \
    "TEMPORAL line lands for /temporal 0 after"
assert_match "$OUT" "^TEMPORAL source=2 relation=before hits=2 ids=\[0 1\]" \
    "TEMPORAL line lands for /temporal 2 before"
assert_match "$OUT" "^TEMPORAL error=missing source atom_id=9999" \
    "TEMPORAL error= line on missing source"
assert_match "$OUT" "^TEMPORAL error=unknown relation='bogus'" \
    "TEMPORAL error= line on unknown relation"

# --- step 8: chat dispatch /temporal ---------------------------------
if [ -x "$CHAT" ]; then
    CHAT_OUT=$(run_chat '/temporal')
    assert_match "$CHAT_OUT" "usage: /temporal <atom_id> <relation>" \
        "/temporal with no arg prints usage"
    assert_match "$CHAT_OUT" "TEMPORAL store_size=" \
        "/temporal with no arg prints store_size diagnostic"

    CHAT_OUT=$(run_chat '/temporal 9999 after')
    assert_match "$CHAT_OUT" "TEMPORAL error=missing source atom_id=9999" \
        "/temporal 9999 after prints graceful missing-atom error"

    CHAT_OUT=$(run_chat '/temporal 0 after')
    assert_match "$CHAT_OUT" "TEMPORAL source=0 relation=after" \
        "/temporal 0 after dispatches and emits TEMPORAL line"

    HELP_OUT=$(run_chat '/help')
    assert_match "$HELP_OUT" "/temporal" "/help lists /temporal"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  CHAT binary not built at %s\n" "$CHAT"
fi

summary "scenario_xxx_temporal"
