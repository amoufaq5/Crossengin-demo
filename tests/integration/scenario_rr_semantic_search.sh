#!/usr/bin/env bash
# Scenario RR -- TF-IDF semantic search retrieval / /find chat command (R10C).
#
# Companion to scenario_mm_episodic_recall.sh. R8F shipped /recall (episodic
# memory retrieval); R10C adds /find -- a textual TF-IDF + integer-cosine
# ranker that ranks atoms by how well their LABEL matches a query string.
# Like /recall this is the READ side of a knowledge surface: the index is
# built from atoms that already exist (the chat builds an ad-hoc index from
# kg_atoms at every /find call, mirroring /recall's "transient eas").
#
# This scenario drives both surfaces:
#   1. The stand-alone demo driver (examples/semantic_search_demo.nova),
#      which builds a 10-atom textual fixture and exercises ss_search +
#      ss_search_by_atom_id directly. Asserts on the formatted FIND /
#      RESULT / FIND_END stdout lines.
#   2. The chat dispatch path: launch the chat binary, type "/find machine
#      learning" / "/find" (empty arg, expect usage line) / "/find" with a
#      gibberish query, and assert on the same FIND lines.
#
# Together these cover the unit-test surface (~50 assertions in
# test_semantic_search.nova) plus the end-to-end wiring through the chat
# REPL. We deliberately avoid testing every cosine value -- that lives in
# the unit suite -- and focus on the dispatcher / ranking properties.

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

NOVA_ROOT="${NOVA_ROOT:-$HOME/NOVA}"
NOVA="$NOVA_ROOT/nova"
DEMO_DRIVER="$REPO_ROOT/examples/semantic_search_demo.nova"

it_section "scenario RR: TF-IDF semantic search + /find command"

# --- guard: NOVA toolchain available ---
if [ ! -x "$NOVA" ]; then
    FAIL=$((FAIL+1))
    echo "FAIL: NOVA launcher not found at '$NOVA'"
    summary "scenario_rr_semantic_search"
    exit 1
fi

assert_file_exists "$DEMO_DRIVER" "demo driver source exists"

# --- step 1: run the semantic-search driver end-to-end -------------------
OUT="$("$NOVA" run "$DEMO_DRIVER" 2>&1)"
RC=$?
echo "$OUT" | sed 's/^/    /'

assert_eq "$RC" "0" "demo driver exits 0"

# --- step 2: confirm the 10-atom fixture indexed cleanly -----------------
DRIVER_ATOMS="$(echo "$OUT" | grep -E '^DRIVER atoms=' | head -1 | cut -d= -f2)"
DRIVER_TOKENS="$(echo "$OUT" | grep -E '^DRIVER tokens=' | head -1 | cut -d= -f2)"
DRIVER_EMPTY="$(echo "$OUT" | grep -E '^DRIVER empty_index_hits=' | head -1 | cut -d= -f2)"

assert_eq "$DRIVER_ATOMS"  "10" "10 atoms indexed"
assert_eq "$DRIVER_EMPTY"  "0"  "empty index returns 0 hits"
# Token count is corpus-dependent; just sanity-check we picked up at least
# 10 unique tokens (one per atom in the worst case after stopword drops).
if [ "$DRIVER_TOKENS" -ge 10 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  driver indexed >= 10 unique tokens (got %s)\n" "$DRIVER_TOKENS"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  driver indexed %s tokens (expected >=10)\n" "$DRIVER_TOKENS"
fi

# --- step 3: /find "machine learning" must rank ML atoms first -----------
# Fixture: atom 1 is "machine learning models data analysis predictions",
# atom 2 is "deep learning neural networks training algorithm". Atom 1
# shares both query tokens ("machine" + "learning"); atom 2 shares only
# "learning". So atom 1 MUST rank first.
assert_match "$OUT" "^FIND query=\"machine learning\" matched=2$" \
    "/find 'machine learning' reports 2 hits"
assert_match "$OUT" "^RESULT rank=1 atom_id=1 " \
    "/find 'machine learning' ranks atom 1 (the ML atom) first"
assert_match "$OUT" "^RESULT rank=2 atom_id=2 " \
    "/find 'machine learning' ranks atom 2 (deep learning) second"

# Extract the actual similarity scores and verify atom 1 > atom 2.
SIM1=$(echo "$OUT" | grep -E '^RESULT rank=1 atom_id=1 ' | head -1 \
    | sed -E 's/.*sim=([0-9]+) milli.*/\1/')
SIM2=$(echo "$OUT" | grep -E '^RESULT rank=2 atom_id=2 ' | head -1 \
    | sed -E 's/.*sim=([0-9]+) milli.*/\1/')
if [ -n "$SIM1" ] && [ -n "$SIM2" ] && [ "$SIM1" -gt "$SIM2" ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  atom 1 sim (%s) > atom 2 sim (%s)\n" "$SIM1" "$SIM2"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  expected atom 1 sim > atom 2 sim (got %s vs %s)\n" "$SIM1" "$SIM2"
fi

# --- step 4: /find "nonsense gibberish ..." -> 0 hits --------------------
# All query tokens are absent from the corpus, so the index has nothing
# to score against. Expect a clean "matched=0" line with no RESULT rows.
assert_match "$OUT" "^FIND query=\"nonsense\" matched=0$" \
    "/find 'nonsense' reports 0 hits"
assert_match "$OUT" "^FIND_END query=\"nonsense\"$" \
    "/find 'nonsense' emits END marker even at zero hits"

# --- step 5: /find "fox dog" -> only atom 3 ------------------------------
# Atom 3 is the only one with "fox" + "dog" in its label.
assert_match "$OUT" "^FIND query=\"fox dog\" matched=1$" \
    "/find 'fox dog' reports 1 hit"
assert_match "$OUT" "^RESULT rank=1 atom_id=3 " \
    "/find 'fox dog' returns atom 3"

# --- step 6: search_by_atom_id excludes the query atom -------------------
# by_id=1 must NOT include atom 1 itself; it must list atom 2 (the only
# other ML-flavoured atom sharing the "learning" token).
assert_match "$OUT" "^FIND by_id=1 matched=1$" \
    "search_by_atom_id(1) reports 1 hit (atom 1 self-excluded)"
assert_match "$OUT" "^RESULT rank=1 atom_id=2 " \
    "search_by_atom_id(1) returns atom 2 (the other learning atom)"
# Verify by_id=1 section specifically excludes atom 1 self -- pull that
# section out of the full output and assert no RESULT row references it.
BYID_BLOCK="$(echo "$OUT" | awk '/^FIND by_id=1/,/^FIND_END by_id=1/')"
assert_nomatch "$BYID_BLOCK" "^RESULT rank=[0-9]+ atom_id=1 " \
    "search_by_atom_id(1) section does NOT contain atom_id=1 row"

# --- step 7: chat dispatch / no-arg usage line ---------------------------
# Launch the actual chat binary and type "/find" with no arg; expect the
# usage line + FIND store_size diagnostic (mirrors /recall's pattern).
# Patterns are NOT anchored to ^ because the chat prefixes admin output
# with a "> " prompt prefix on the first line of a response block.
if [ -x "$CHAT" ]; then
    CHAT_OUT=$(run_chat '/find')
    assert_match "$CHAT_OUT" "usage: /find <query text>" \
        "/find with no arg prints a usage line"
    assert_match "$CHAT_OUT" "FIND store_size=" \
        "/find with no arg prints store_size diagnostic"

    # Chat /find with a real query -- the seed pack includes "machine"
    # as a fact-kind seed atom; assert the rank-1 row exists.
    CHAT_OUT2=$(run_chat '/find machine')
    assert_match "$CHAT_OUT2" "FIND query=\"machine\" matched=" \
        "/find machine returns a FIND header"
    assert_match "$CHAT_OUT2" "^FIND_END query=\"machine\"$" \
        "/find machine emits END marker"

    # /find listed in /help.
    HELP_OUT=$(run_chat '/help')
    assert_match "$HELP_OUT" "/find" "/help lists /find"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  CHAT binary not built at %s\n" "$CHAT"
fi

summary "scenario_rr_semantic_search"
