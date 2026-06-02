#!/usr/bin/env bash
# Scenario EEE -- PageRank centrality (R13E).
#
# Companion to scenario_xx_communities.sh (R11F LPA) and
# scenario_zz_louvain.sh (R12C Louvain). R13E ships the missing
# CENTRALITY surface: a per-atom importance score that answers
# "which atoms are most important?" Brin & Page's classic PageRank
# (integer milli-units, deterministic, no randomness) sits beside
# the clustering algorithms as the third KG-read primitive.
#
# This scenario drives both surfaces:
#   1. A tracked stand-alone driver under
#      tests/integration/_scenario_eee_pagerank_driver/ which builds
#      a barbell (8 atoms, two 4-cliques + bridge), the Zachary 1977
#      karate-club graph (34 atoms, 78 edges), and an empty-graph
#      edge case. It prints DRIVER lines for the shell to parse, and
#      also invokes pagerank_cmd directly so the shell can assert on
#      the PAGERANK emit-line shape.
#   2. The chat dispatch path: launch the chat binary, type
#      "/pagerank", and assert the PAGERANK line lands. Also asserts
#      that /help lists /pagerank.

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

NOVA_ROOT="${NOVA_ROOT:-$HOME/NOVA}"
NOVA="$NOVA_ROOT/nova"

it_section "scenario EEE: PageRank centrality + /pagerank command"

# --- guard: NOVA toolchain available ---
if [ ! -x "$NOVA" ]; then
    FAIL=$((FAIL+1))
    echo "FAIL: NOVA launcher not found at '$NOVA'"
    summary "scenario_eee_pagerank"
    exit 1
fi

# --- step 1: run the tracked driver -------------------------------------
DRIVER="$REPO_ROOT/tests/integration/_scenario_eee_pagerank_driver/pagerank_driver.nova"
assert_file_exists "$DRIVER" "pagerank driver source exists"

OUT="$("$NOVA" run "$DRIVER" 2>&1)"
RC=$?
echo "$OUT" | sed 's/^/    /'
assert_eq "$RC" "0" "pagerank driver exits 0"

# --- step 2: empty KG -> graceful "no atoms" ----------------------------
EMPTY_N=$(echo "$OUT" | grep -E '^DRIVER empty_n=' | head -1 | cut -d= -f2)
EMPTY_C=$(echo "$OUT" | grep -E '^DRIVER empty_converged=' | head -1 | cut -d= -f2)
assert_eq "$EMPTY_N" "0" "empty KG -> 0 atoms"
assert_eq "$EMPTY_C" "1" "empty KG -> trivially converged"

# --- step 3: barbell fixture -- bridge atoms own top-2 ------------------
BARBELL_N=$(echo "$OUT" | grep -E '^DRIVER barbell_n=' | head -1 | cut -d= -f2)
BARBELL_C=$(echo "$OUT" | grep -E '^DRIVER barbell_converged=' | head -1 | cut -d= -f2)
BARBELL_TOP0=$(echo "$OUT" | grep -E '^DRIVER barbell_top0=' | head -1 | cut -d= -f2)
BARBELL_TOP1=$(echo "$OUT" | grep -E '^DRIVER barbell_top1=' | head -1 | cut -d= -f2)
BARBELL_PR3=$(echo "$OUT" | grep -E '^DRIVER barbell_pr_atom3=' | head -1 | cut -d= -f2)
BARBELL_PR4=$(echo "$OUT" | grep -E '^DRIVER barbell_pr_atom4=' | head -1 | cut -d= -f2)
BARBELL_PR0=$(echo "$OUT" | grep -E '^DRIVER barbell_pr_atom0=' | head -1 | cut -d= -f2)
BARBELL_MASS=$(echo "$OUT" | grep -E '^DRIVER barbell_total_mass=' | head -1 | cut -d= -f2)

assert_eq "$BARBELL_N" "8" "barbell -> 8 atoms"
assert_eq "$BARBELL_C" "1" "barbell converges"
# Bridge atoms 3 and 4 must be the top 2 (in some order).
if [ "$BARBELL_TOP0" = "3" ] && [ "$BARBELL_TOP1" = "4" ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  barbell top-2 = bridge atoms (3, 4)\n"
elif [ "$BARBELL_TOP0" = "4" ] && [ "$BARBELL_TOP1" = "3" ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  barbell top-2 = bridge atoms (4, 3)\n"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  expected barbell top-2 = {3, 4}, got {%s, %s}\n" "$BARBELL_TOP0" "$BARBELL_TOP1"
fi
# Bridge symmetry: PR(3) == PR(4).
assert_eq "$BARBELL_PR3" "$BARBELL_PR4" "barbell bridge symmetry: PR(3) == PR(4)"
# Bridge dominance: PR(3) > PR(0) (clique-interior atom).
if [ -n "$BARBELL_PR3" ] && [ -n "$BARBELL_PR0" ] && [ "$BARBELL_PR3" -gt "$BARBELL_PR0" ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  barbell bridge dominance: PR(3)=%s > PR(0)=%s\n" "$BARBELL_PR3" "$BARBELL_PR0"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  expected barbell PR(3) > PR(0): got %s, %s\n" "$BARBELL_PR3" "$BARBELL_PR0"
fi
# Mass conservation: total within +/- 50 milli of 1000.
if [ -n "$BARBELL_MASS" ] && [ "$BARBELL_MASS" -ge 950 ] && [ "$BARBELL_MASS" -le 1050 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  barbell total mass in [950, 1050] milli (got %s)\n" "$BARBELL_MASS"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  expected barbell mass in [950, 1050]: got %s\n" "$BARBELL_MASS"
fi

# --- step 4: karate club -- Mr Hi (0) + Officer (33) own top-2 ---------
KARATE_N=$(echo "$OUT" | grep -E '^DRIVER karate_n=' | head -1 | cut -d= -f2)
KARATE_ITERS=$(echo "$OUT" | grep -E '^DRIVER karate_iters=' | head -1 | cut -d= -f2)
KARATE_C=$(echo "$OUT" | grep -E '^DRIVER karate_converged=' | head -1 | cut -d= -f2)
KARATE_TOP0=$(echo "$OUT" | grep -E '^DRIVER karate_top0=' | head -1 | cut -d= -f2)
KARATE_TOP1=$(echo "$OUT" | grep -E '^DRIVER karate_top1=' | head -1 | cut -d= -f2)
KARATE_PR0=$(echo "$OUT" | grep -E '^DRIVER karate_pr_0=' | head -1 | cut -d= -f2)
KARATE_PR33=$(echo "$OUT" | grep -E '^DRIVER karate_pr_33=' | head -1 | cut -d= -f2)

assert_eq "$KARATE_N" "34" "karate -> 34 atoms"
# Convergence within the brief's 30-iter cap.
if [ -n "$KARATE_ITERS" ] && [ "$KARATE_ITERS" -le 30 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  karate converges <= 30 iters (got %s)\n" "$KARATE_ITERS"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  expected karate <= 30 iters: got %s\n" "$KARATE_ITERS"
fi
assert_eq "$KARATE_C" "1" "karate converges"
# Top-2 must be {0, 33} in some order.
if { [ "$KARATE_TOP0" = "0" ] && [ "$KARATE_TOP1" = "33" ]; } || { [ "$KARATE_TOP0" = "33" ] && [ "$KARATE_TOP1" = "0" ]; }; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  karate top-2 = {0 (Mr Hi), 33 (Officer)}\n"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  expected karate top-2 = {0, 33}, got {%s, %s}\n" "$KARATE_TOP0" "$KARATE_TOP1"
fi
# Both hubs have positive PR.
if [ -n "$KARATE_PR0" ] && [ "$KARATE_PR0" -gt 0 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  karate PR(Mr Hi) > 0 (got %s milli)\n" "$KARATE_PR0"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  expected karate PR(0) > 0: got %s\n" "$KARATE_PR0"
fi
if [ -n "$KARATE_PR33" ] && [ "$KARATE_PR33" -gt 0 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  karate PR(Officer) > 0 (got %s milli)\n" "$KARATE_PR33"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  expected karate PR(33) > 0: got %s\n" "$KARATE_PR33"
fi

# --- step 5: PAGERANK emit-line shape (driver) --------------------------
# pagerank_cmd prints exactly:
#   PAGERANK n=N iterations=I converged=yes/no top=[id=X,pr=Y ...]
assert_match "$OUT" "^PAGERANK n=8 iterations=" \
    "PAGERANK line emitted with n=8 for the barbell"
assert_match "$OUT" "^PAGERANK n=8 .* converged=yes" \
    "PAGERANK line carries converged=yes for barbell"
assert_match "$OUT" "^PAGERANK n=8 .* top=\[id=[0-9]+,pr=[0-9]+" \
    "PAGERANK line carries top=[id=X,pr=Y ...]"

# --- step 6: chat dispatch /pagerank ------------------------------------
if [ -x "$CHAT" ]; then
    CHAT_OUT=$(run_chat '/pagerank')
    assert_match "$CHAT_OUT" "PAGERANK n=[0-9]+ iterations=" \
        "/pagerank prints the PAGERANK headline"
    assert_match "$CHAT_OUT" "PAGERANK n=[0-9]+ .* converged=(yes|no)" \
        "/pagerank reports convergence yes/no"
    assert_match "$CHAT_OUT" "PAGERANK n=[0-9]+ .* top=\[" \
        "/pagerank reports top= list"

    HELP_OUT=$(run_chat '/help')
    assert_match "$HELP_OUT" "/pagerank" "/help lists /pagerank"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  CHAT binary not built at %s\n" "$CHAT"
fi

summary "scenario_eee_pagerank"
