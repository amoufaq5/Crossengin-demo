#!/usr/bin/env bash
# Scenario XX -- KG graph clustering / community detection (R11F).
#
# Companion to scenario_rr_semantic_search.sh. R10C shipped /find -- a
# textual TF-IDF ranker over atom labels. R11F adds /communities --
# label-propagation community detection over the GRAPH STRUCTURE of
# atom xrefs. Together with /find they form the structural+textual
# read story: /find says "atoms whose LABELS look alike", /communities
# says "atoms whose LINKS keep them in the same neighbourhood".
#
# This scenario drives both surfaces:
#   1. The stand-alone driver (examples/graph_clustering_demo.nova),
#      which builds a barbell fixture (2 cliques + a bridge), a
#      three-triangle fixture, and an empty-graph edge case, and
#      exercises gc_label_propagation + gc_modularity +
#      gc_communities_cmd directly. Asserts on DRIVER * lines and the
#      formatted COMMUNITIES line.
#   2. The chat dispatch path: launch the chat binary, type
#      "/communities", and assert that the same COMMUNITIES line lands
#      with sensible values for the seed-pack KG. Also asserts that
#      /help lists the command.
#
# Together these cover the unit-test surface (~71 assertions in
# test_graph_clustering.nova) plus the end-to-end wiring through the
# chat REPL.

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

NOVA_ROOT="${NOVA_ROOT:-$HOME/NOVA}"
NOVA="$NOVA_ROOT/nova"
DEMO_DRIVER="$REPO_ROOT/examples/graph_clustering_demo.nova"

it_section "scenario XX: KG graph clustering + /communities command"

# --- guard: NOVA toolchain available ---
if [ ! -x "$NOVA" ]; then
    FAIL=$((FAIL+1))
    echo "FAIL: NOVA launcher not found at '$NOVA'"
    summary "scenario_xx_communities"
    exit 1
fi

assert_file_exists "$DEMO_DRIVER" "demo driver source exists"

# --- step 1: run the graph-clustering driver end-to-end ------------------
OUT="$("$NOVA" run "$DEMO_DRIVER" 2>&1)"
RC=$?
echo "$OUT" | sed 's/^/    /'

assert_eq "$RC" "0" "demo driver exits 0"

# --- step 2: empty KG reports 0 communities + 0 edges --------------------
EMPTY_N=$(echo "$OUT" | grep -E '^DRIVER empty_n=' | head -1 | cut -d= -f2)
EMPTY_E=$(echo "$OUT" | grep -E '^DRIVER empty_edges=' | head -1 | cut -d= -f2)
assert_eq "$EMPTY_N" "0" "empty KG -> 0 communities"
assert_eq "$EMPTY_E" "0" "empty KG -> 0 edges"

# --- step 3: barbell fixture: 2 communities + 13 edges + 2 iters ---------
# Two 4-cliques (C(4,2)=6 edges each) + 1 bridge = 13 edges.
ATOMS=$(echo "$OUT" | grep -E '^DRIVER atoms=' | head -1 | cut -d= -f2)
BARBELL_N=$(echo "$OUT" | grep -E '^DRIVER barbell_n=' | head -1 | cut -d= -f2)
BARBELL_LG=$(echo "$OUT" | grep -E '^DRIVER barbell_largest=' | head -1 | cut -d= -f2)
BARBELL_Q=$(echo "$OUT" | grep -E '^DRIVER barbell_modularity=' | head -1 | cut -d= -f2)
BARBELL_E=$(echo "$OUT" | grep -E '^DRIVER barbell_edges=' | head -1 | cut -d= -f2)
BARBELL_I=$(echo "$OUT" | grep -E '^DRIVER barbell_iter=' | head -1 | cut -d= -f2)

assert_eq "$ATOMS"      "8"  "barbell fixture has 8 atoms"
assert_eq "$BARBELL_N"  "2"  "barbell -> 2 communities (one per clique)"
assert_eq "$BARBELL_E"  "13" "barbell -> 13 undirected edges (6+6+1)"
# Largest community is one of the 4-cliques (with bridge atom on its side
# so size could be 4 or 5 depending on shuffle; we assert >= 4).
if [ -n "$BARBELL_LG" ] && [ "$BARBELL_LG" -ge 4 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  barbell largest community >= 4 (got %s)\n" "$BARBELL_LG"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  expected barbell largest >= 4 (got %s)\n" "$BARBELL_LG"
fi
# Modularity must exceed the 200-milli "well-separated" threshold.
if [ -n "$BARBELL_Q" ] && [ "$BARBELL_Q" -gt 200 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  barbell modularity > 200 milli (got %s)\n" "$BARBELL_Q"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  expected barbell modularity > 200 milli (got %s)\n" "$BARBELL_Q"
fi
# Convergence in <= 5 iterations per Raghavan's empirical bound.
if [ -n "$BARBELL_I" ] && [ "$BARBELL_I" -le 5 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  barbell converges in <= 5 iterations (got %s)\n" "$BARBELL_I"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  expected barbell <= 5 iterations (got %s)\n" "$BARBELL_I"
fi

# --- step 4: COMMUNITIES emit-line shape ---------------------------------
# The driver calls gc_communities_cmd which prints exactly:
#   COMMUNITIES n=N largest=L modularity=M milli edges=E iter=I
assert_match "$OUT" "^COMMUNITIES n=2 largest=" \
    "COMMUNITIES line emitted with n=2 for the barbell"
assert_match "$OUT" "^COMMUNITIES n=2 .* modularity=[0-9]+ milli" \
    "COMMUNITIES line carries modularity in milli"
assert_match "$OUT" "^COMMUNITIES n=2 .* edges=13 iter=[0-9]+\$" \
    "COMMUNITIES line carries edges=13 + iter=N"

# --- step 5: three-triangle fixture: exactly 3 communities ---------------
# Three disjoint 3-cliques with NO inter-cluster edges -> LPA settles
# on exactly 3 communities, one per triangle.
TRI_N=$(echo "$OUT" | grep -E '^DRIVER tri_n=' | head -1 | cut -d= -f2)
TRI_LG=$(echo "$OUT" | grep -E '^DRIVER tri_largest=' | head -1 | cut -d= -f2)
TRI_Q=$(echo "$OUT" | grep -E '^DRIVER tri_modularity=' | head -1 | cut -d= -f2)
TRI_E=$(echo "$OUT" | grep -E '^DRIVER tri_edges=' | head -1 | cut -d= -f2)

assert_eq "$TRI_N"  "3" "3-triangle fixture -> exactly 3 communities"
assert_eq "$TRI_LG" "3" "3-triangle largest community has 3 members"
assert_eq "$TRI_E"  "9" "3-triangle fixture has 9 undirected edges (3*C(3,2))"
if [ -n "$TRI_Q" ] && [ "$TRI_Q" -gt 200 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  3-triangle modularity > 200 milli (got %s)\n" "$TRI_Q"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  expected 3-triangle modularity > 200 milli (got %s)\n" "$TRI_Q"
fi

# --- step 6: chat dispatch /communities ----------------------------------
# Run the chat binary on a stub session; the seed pack populates a KG
# with hundreds of atoms but few inter-atom xrefs (seed atoms are
# mostly isolated, so the LPA finds many small communities). We assert
# that the COMMUNITIES line lands and parses correctly.
if [ -x "$CHAT" ]; then
    CHAT_OUT=$(run_chat '/communities')
    assert_match "$CHAT_OUT" "COMMUNITIES n=[0-9]+ largest=" \
        "/communities prints the COMMUNITIES headline"
    assert_match "$CHAT_OUT" "COMMUNITIES n=[0-9]+ .* modularity=[0-9-]+ milli" \
        "/communities reports modularity in milli"

    # /communities listed in /help.
    HELP_OUT=$(run_chat '/help')
    assert_match "$HELP_OUT" "/communities" "/help lists /communities"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  CHAT binary not built at %s\n" "$CHAT"
fi

summary "scenario_xx_communities"
