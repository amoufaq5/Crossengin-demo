#!/usr/bin/env bash
# Scenario ZZ -- Louvain modularity-optimising community detection (R12C).
#
# Companion to scenario_xx_communities.sh. R11F shipped label
# propagation (/communities) -- O(V+E) per sweep, decent quality.
# R12C ships Louvain (/louvain) -- the gold-standard greedy modularity
# optimiser (Blondel 2008). Louvain is provably at least as good as
# LPA on modularity, often 10..15% higher on real-world graphs.
#
# This scenario drives both surfaces:
#   1. A tracked stand-alone driver (NOVA program under
#      _scenario_zz_louvain_driver/) which builds the brief's three
#      fixtures (barbell, 3-triangle, Zachary's karate club) and
#      prints DRIVER lines for the shell to parse. It also runs R11F's
#      gc_label_propagation on the SAME fixtures so the shell asserts
#      Louvain >= LPA on modularity for each.
#   2. The chat dispatch path: launch the chat binary, type
#      "/louvain", and assert the LOUVAIN line lands. Also asserts
#      /help lists /louvain.
#
# Total assertions: ~18 (above the brief's 10-12 target).

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

NOVA_ROOT="${NOVA_ROOT:-$HOME/NOVA}"
NOVA="$NOVA_ROOT/nova"

it_section "scenario ZZ: Louvain community detection + /louvain command"

# --- guard: NOVA toolchain available ---
if [ ! -x "$NOVA" ]; then
    FAIL=$((FAIL+1))
    echo "FAIL: NOVA launcher not found at '$NOVA'"
    summary "scenario_zz_louvain"
    exit 1
fi

# --- step 1: run the tracked driver --------------------------------------
# The driver under tests/integration/_scenario_zz_louvain_driver/ builds
# the brief's three fixtures (barbell, 3-triangle, Zachary's karate
# club) and prints DRIVER lines for the shell to parse. It also runs
# R11F's gc_label_propagation on the SAME fixtures so the shell can
# assert Louvain >= LPA on modularity.

DRIVER="$REPO_ROOT/tests/integration/_scenario_zz_louvain_driver/louvain_driver.nova"
assert_file_exists "$DRIVER" "louvain driver source exists"

OUT="$("$NOVA" run "$DRIVER" 2>&1)"
RC=$?
echo "$OUT" | sed 's/^/    /'
assert_eq "$RC" "0" "louvain driver exits 0"

# --- step 2: barbell --- Louvain >= R11F on modularity -------------------
BARBELL_LV_N=$(echo "$OUT" | grep -E '^DRIVER barbell_lv_n=' | head -1 | cut -d= -f2)
BARBELL_LV_Q=$(echo "$OUT" | grep -E '^DRIVER barbell_lv_q=' | head -1 | cut -d= -f2)
BARBELL_GC_Q=$(echo "$OUT" | grep -E '^DRIVER barbell_gc_q=' | head -1 | cut -d= -f2)
BARBELL_LV_E=$(echo "$OUT" | grep -E '^DRIVER barbell_lv_edges=' | head -1 | cut -d= -f2)

assert_eq "$BARBELL_LV_N" "2" "barbell -> 2 Louvain communities"
assert_eq "$BARBELL_LV_E" "13" "barbell -> 13 undirected edges"

if [ -n "$BARBELL_LV_Q" ] && [ "$BARBELL_LV_Q" -ge "$BARBELL_GC_Q" ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  barbell Louvain modularity >= LPA (lv=%s milli vs gc=%s milli)\n" "$BARBELL_LV_Q" "$BARBELL_GC_Q"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  expected Louvain >= LPA on barbell (lv=%s vs gc=%s)\n" "$BARBELL_LV_Q" "$BARBELL_GC_Q"
fi

# --- step 3: three triangles ---------------------------------------------
TRI_LV_N=$(echo "$OUT" | grep -E '^DRIVER tri_lv_n=' | head -1 | cut -d= -f2)
TRI_LV_Q=$(echo "$OUT" | grep -E '^DRIVER tri_lv_q=' | head -1 | cut -d= -f2)
TRI_GC_Q=$(echo "$OUT" | grep -E '^DRIVER tri_gc_q=' | head -1 | cut -d= -f2)
TRI_LV_E=$(echo "$OUT" | grep -E '^DRIVER tri_lv_edges=' | head -1 | cut -d= -f2)

assert_eq "$TRI_LV_N" "3" "3-triangle -> 3 Louvain communities"
assert_eq "$TRI_LV_E" "9" "3-triangle -> 9 edges"

if [ -n "$TRI_LV_Q" ] && [ "$TRI_LV_Q" -ge "$TRI_GC_Q" ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  3-triangle Louvain modularity >= LPA (lv=%s milli vs gc=%s milli)\n" "$TRI_LV_Q" "$TRI_GC_Q"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  expected Louvain >= LPA on 3-triangle (lv=%s vs gc=%s)\n" "$TRI_LV_Q" "$TRI_GC_Q"
fi

# --- step 4: Zachary karate club -- Louvain >> LPA -----------------------
KARATE_LV_N=$(echo "$OUT" | grep -E '^DRIVER karate_lv_n=' | head -1 | cut -d= -f2)
KARATE_LV_Q=$(echo "$OUT" | grep -E '^DRIVER karate_lv_q=' | head -1 | cut -d= -f2)
KARATE_GC_Q=$(echo "$OUT" | grep -E '^DRIVER karate_gc_q=' | head -1 | cut -d= -f2)
KARATE_LV_E=$(echo "$OUT" | grep -E '^DRIVER karate_lv_edges=' | head -1 | cut -d= -f2)
KARATE_LV_D=$(echo "$OUT" | grep -E '^DRIVER karate_lv_depth=' | head -1 | cut -d= -f2)

assert_eq "$KARATE_LV_E" "78" "Zachary karate edge count = 78"
if [ -n "$KARATE_LV_N" ] && [ "$KARATE_LV_N" -ge 3 ] && [ "$KARATE_LV_N" -le 5 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  karate Louvain finds %s communities (in [3..5])\n" "$KARATE_LV_N"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  expected karate Louvain communities in [3..5] (got %s)\n" "$KARATE_LV_N"
fi

if [ -n "$KARATE_LV_Q" ] && [ "$KARATE_LV_Q" -gt 350 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  karate Louvain modularity > 350 milli (got %s)\n" "$KARATE_LV_Q"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  expected karate Louvain modularity > 350 milli (got %s)\n" "$KARATE_LV_Q"
fi

if [ -n "$KARATE_LV_Q" ] && [ "$KARATE_LV_Q" -ge "$KARATE_GC_Q" ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  karate Louvain modularity >= LPA (lv=%s milli vs gc=%s milli)\n" "$KARATE_LV_Q" "$KARATE_GC_Q"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  expected karate Louvain >= LPA (lv=%s vs gc=%s)\n" "$KARATE_LV_Q" "$KARATE_GC_Q"
fi

if [ -n "$KARATE_LV_D" ] && [ "$KARATE_LV_D" -ge 2 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  karate Louvain depth >= 2 (got %s)\n" "$KARATE_LV_D"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  expected karate Louvain depth >= 2 (got %s)\n" "$KARATE_LV_D"
fi

# --- step 5: LOUVAIN emit-line shape -------------------------------------
# louvain_communities_cmd prints exactly:
#   LOUVAIN n=N largest=L modularity=M milli edges=E depth=D
assert_match "$OUT" "^LOUVAIN n=2 largest=" \
    "LOUVAIN line emitted with n=2 for the barbell"
assert_match "$OUT" "^LOUVAIN n=2 .* modularity=[0-9]+ milli" \
    "LOUVAIN line carries modularity in milli"
assert_match "$OUT" "^LOUVAIN n=2 .* edges=13 depth=[0-9]+\$" \
    "LOUVAIN line carries edges=13 + depth=N"

# --- step 6: chat dispatch /louvain --------------------------------------
if [ -x "$CHAT" ]; then
    CHAT_OUT=$(run_chat '/louvain')
    assert_match "$CHAT_OUT" "LOUVAIN n=[0-9]+ largest=" \
        "/louvain prints the LOUVAIN headline"
    assert_match "$CHAT_OUT" "LOUVAIN n=[0-9]+ .* modularity=[0-9-]+ milli" \
        "/louvain reports modularity in milli"

    HELP_OUT=$(run_chat '/help')
    assert_match "$HELP_OUT" "/louvain" "/help lists /louvain"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  CHAT binary not built at %s\n" "$CHAT"
fi

summary "scenario_zz_louvain"
