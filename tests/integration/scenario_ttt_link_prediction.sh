#!/usr/bin/env bash
# Scenario TTT -- link prediction over the KG xref graph (R18B).
#
# Companion to scenario_xx_communities.sh (R11F LPA),
# scenario_zz_louvain.sh (R12C Louvain), and scenario_eee_pagerank.sh
# (R13E PageRank). R18B ships the missing LINK-PREDICTION surface:
# given two atoms not currently linked, score how likely they SHOULD
# be linked based on neighbourhood overlap. Three classical scores
# (Common Neighbors, Jaccard, Adamic-Adar) on integer milli-units,
# fully deterministic.
#
# This scenario drives both surfaces:
#   1. A tracked stand-alone driver under
#      tests/integration/_scenario_ttt_link_prediction_driver/ which
#      builds:
#        - triangle-with-missing-edge ({0,1,2} with only 0--1 and 1--2);
#        - 4-clique-minus-one ({0,1,2,3} with every edge except 0--3);
#        - two disjoint triangles ({0,1,2} and {3,4,5});
#        - a hub-vs-rare fixture where Jaccard and Adamic-Adar disagree
#          on the top-1 candidate.
#      It prints DRIVER lines for the shell to parse, and also invokes
#      lp_predict_cmd directly so the shell can assert on the PREDICT
#      emit-line shape (both methods + the missing-atom error path).
#   2. The chat dispatch path: launch the chat binary, type
#      "/predict <id>", and assert the PREDICT line lands. Also asserts
#      that /help lists /predict.
#
# Total assertions: ~22 (above the brief's 10-12 target).

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

NOVA_ROOT="${NOVA_ROOT:-$HOME/NOVA}"
NOVA="$NOVA_ROOT/nova"

it_section "scenario TTT: link prediction + /predict command"

# --- guard: NOVA toolchain available -----------------------------------
if [ ! -x "$NOVA" ]; then
    FAIL=$((FAIL+1))
    echo "FAIL: NOVA launcher not found at '$NOVA'"
    summary "scenario_ttt_link_prediction"
    exit 1
fi

# --- step 1: run the tracked driver ------------------------------------
DRIVER="$REPO_ROOT/tests/integration/_scenario_ttt_link_prediction_driver/link_prediction_driver.nova"
assert_file_exists "$DRIVER" "link prediction driver source exists"

OUT="$("$NOVA" run "$DRIVER" 2>&1)"
RC=$?
echo "$OUT" | sed 's/^/    /'
assert_eq "$RC" "0" "link prediction driver exits 0"

# --- step 2: triangle-with-missing-edge ranks the predicted edge -------
# {0, 1, 2} with edges 0--1 and 1--2 (the 0--2 edge is missing).
# N(0) = {1}; N(2) = {1, 3? no, just 1}. With just 3 atoms:
#   N(0) = {1}; N(2) = {1}; intersect = {1}; union = {1}.
# CN(0, 2) = 1; J(0, 2) = 1000; AA(0, 2) = 1000.
TRI_CN=$(echo "$OUT" | grep -E '^DRIVER triangle_cn_02=' | head -1 | cut -d= -f2)
TRI_J=$(echo "$OUT" | grep -E '^DRIVER triangle_j_02=' | head -1 | cut -d= -f2)
TRI_AA=$(echo "$OUT" | grep -E '^DRIVER triangle_aa_02=' | head -1 | cut -d= -f2)
TRI_TOP_ID=$(echo "$OUT" | grep -E '^DRIVER triangle_top0_id=' | head -1 | cut -d= -f2)
TRI_TOP_SCORE=$(echo "$OUT" | grep -E '^DRIVER triangle_top0_score=' | head -1 | cut -d= -f2)
assert_eq "$TRI_CN" "1" "triangle CN(0, 2) = 1 (shared neighbour 1)"
assert_eq "$TRI_J" "1000" "triangle J(0, 2) = 1000 milli (full overlap)"
assert_eq "$TRI_AA" "1000" "triangle AA(0, 2) = 1000 milli"
assert_eq "$TRI_TOP_ID" "2" "triangle /predict 0 -> top hit is atom 2"
assert_eq "$TRI_TOP_SCORE" "1000" "triangle /predict 0 -> top score 1000 milli"

# --- step 3: 4-clique-minus-one -- CN(0, 3) = 2 wins ranking -----------
# {0, 1, 2, 3} with every edge EXCEPT 0--3. So:
#   N(0) = {1, 2}; N(3) = {1, 2}; intersect = {1, 2}; union = {1, 2}.
# CN(0, 3) = 2; J(0, 3) = 1000; AA(0, 3) = 1000 + 1000 = 2000.
K4_CN=$(echo "$OUT" | grep -E '^DRIVER k4_cn_03=' | head -1 | cut -d= -f2)
K4_J=$(echo "$OUT" | grep -E '^DRIVER k4_j_03=' | head -1 | cut -d= -f2)
K4_AA=$(echo "$OUT" | grep -E '^DRIVER k4_aa_03=' | head -1 | cut -d= -f2)
K4_TOP_ID=$(echo "$OUT" | grep -E '^DRIVER k4_top0_id=' | head -1 | cut -d= -f2)
K4_TOP_SCORE=$(echo "$OUT" | grep -E '^DRIVER k4_top0_score=' | head -1 | cut -d= -f2)
assert_eq "$K4_CN" "2" "k4-minus-one CN(0, 3) = 2 (shared {1, 2})"
assert_eq "$K4_J" "1000" "k4-minus-one J(0, 3) = 1000 milli"
assert_eq "$K4_AA" "2000" "k4-minus-one AA(0, 3) = 2000 milli"
assert_eq "$K4_TOP_ID" "3" "k4 /predict 0 -> top hit is atom 3"
assert_eq "$K4_TOP_SCORE" "2" "k4 /predict 0 (CN) -> top score 2"

# --- step 4: disjoint subgraphs -- no shared neighbours ----------------
D_CN=$(echo "$OUT" | grep -E '^DRIVER disjoint_cn_03=' | head -1 | cut -d= -f2)
D_J=$(echo "$OUT" | grep -E '^DRIVER disjoint_j_03=' | head -1 | cut -d= -f2)
D_AA=$(echo "$OUT" | grep -E '^DRIVER disjoint_aa_03=' | head -1 | cut -d= -f2)
assert_eq "$D_CN" "0" "disjoint subgraphs CN -> 0"
assert_eq "$D_J" "0" "disjoint subgraphs J -> 0"
assert_eq "$D_AA" "0" "disjoint subgraphs AA -> 0"

# --- step 5: J vs AA ranking divergence on hub-vs-rare fixture ---------
# Jaccard ties candidates 1 and 2 at 500 milli each (same overlap
# ratio); ASCENDING-id tiebreak puts atom 1 first.
# Adamic-Adar strictly prefers candidate 2 (rare neighbour 4 has
# deg 2 -> weight 1000 milli) over candidate 1 (hub neighbour 3 has
# deg 5 -> weight ~500 milli); atom 2 wins strictly.
HUB_J_TOP=$(echo "$OUT" | grep -E '^DRIVER hub_j_top0_id=' | head -1 | cut -d= -f2)
HUB_AA_TOP=$(echo "$OUT" | grep -E '^DRIVER hub_aa_top0_id=' | head -1 | cut -d= -f2)
HUB_J_01=$(echo "$OUT" | grep -E '^DRIVER hub_j_01=' | head -1 | cut -d= -f2)
HUB_J_02=$(echo "$OUT" | grep -E '^DRIVER hub_j_02=' | head -1 | cut -d= -f2)
HUB_AA_01=$(echo "$OUT" | grep -E '^DRIVER hub_aa_01=' | head -1 | cut -d= -f2)
HUB_AA_02=$(echo "$OUT" | grep -E '^DRIVER hub_aa_02=' | head -1 | cut -d= -f2)
assert_eq "$HUB_J_TOP" "1" "hub-vs-rare J top-1 = atom 1 (ASCENDING tiebreak)"
assert_eq "$HUB_AA_TOP" "2" "hub-vs-rare AA top-1 = atom 2 (rare neighbour up-weighted)"
# Critical: the two methods produce different orderings on the same query.
if [ -n "$HUB_J_TOP" ] && [ -n "$HUB_AA_TOP" ] && [ "$HUB_J_TOP" != "$HUB_AA_TOP" ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  Jaccard vs Adamic-Adar produce DIFFERENT top-1 (j=%s, aa=%s)\n" "$HUB_J_TOP" "$HUB_AA_TOP"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  expected J and AA to disagree on top-1 (got j=%s, aa=%s)\n" "$HUB_J_TOP" "$HUB_AA_TOP"
fi
# AA must strictly prefer the rare-neighbour candidate.
if [ -n "$HUB_AA_02" ] && [ -n "$HUB_AA_01" ] && [ "$HUB_AA_02" -gt "$HUB_AA_01" ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  AA(0, 2) > AA(0, 1) (rare > hub; aa02=%s vs aa01=%s)\n" "$HUB_AA_02" "$HUB_AA_01"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  expected AA(0,2) > AA(0,1) got %s vs %s\n" "$HUB_AA_02" "$HUB_AA_01"
fi
# J ties on the two pairs (same overlap ratio).
assert_eq "$HUB_J_01" "$HUB_J_02" "J(0, 1) == J(0, 2) on hub-vs-rare (overlap ratio tie)"

# --- step 6: PREDICT emit-line shape (driver) --------------------------
# lp_predict_cmd prints exactly:
#   PREDICT source=X method=NAME top_k=K hits=H edges=[id=A,score=B ...]
assert_match "$OUT" "^PREDICT source=0 method=jaccard top_k=" \
    "PREDICT line emitted with source=0 method=jaccard"
assert_match "$OUT" "^PREDICT source=0 method=aa top_k=" \
    "PREDICT line emitted with method=aa"
assert_match "$OUT" "^PREDICT source=0 method=(jaccard|aa) .* edges=\[id=[0-9]+,score=[0-9]+" \
    "PREDICT line carries edges=[id=X,score=Y ...]"
assert_match "$OUT" "^PREDICT error=missing source atom_id=9999" \
    "PREDICT error= line lands on missing source"

# --- step 7: chat dispatch /predict ------------------------------------
if [ -x "$CHAT" ]; then
    CHAT_OUT=$(run_chat '/predict')
    assert_match "$CHAT_OUT" "usage: /predict <atom_id>" \
        "/predict with no arg prints usage"
    assert_match "$CHAT_OUT" "PREDICT store_size=" \
        "/predict with no arg prints store_size diagnostic"

    CHAT_OUT=$(run_chat '/predict 0')
    assert_match "$CHAT_OUT" "PREDICT source=0 method=jaccard" \
        "/predict 0 dispatches with default method jaccard"
    assert_match "$CHAT_OUT" "PREDICT source=0 .* top_k=5" \
        "/predict 0 uses default top_k=5"

    CHAT_OUT=$(run_chat '/predict 9999')
    assert_match "$CHAT_OUT" "PREDICT error=missing source atom_id=9999" \
        "/predict 9999 prints graceful missing-atom error"

    CHAT_OUT=$(run_chat '/predict 0 3 cn')
    assert_match "$CHAT_OUT" "PREDICT source=0 method=cn top_k=3" \
        "/predict 0 3 cn parses both top_k and method"

    HELP_OUT=$(run_chat '/help')
    assert_match "$HELP_OUT" "/predict" "/help lists /predict"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  CHAT binary not built at %s\n" "$CHAT"
fi

summary "scenario_ttt_link_prediction"
