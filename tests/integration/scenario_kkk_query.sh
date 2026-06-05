#!/usr/bin/env bash
# Scenario KKK -- mini-SPARQL declarative query language (R15D).
#
# Companion to scenario_rr_semantic_search.sh (R10C /find textual
# ranker), scenario_mm_episodic_recall.sh (R8F /recall),
# scenario_xx_communities.sh (R11F /communities),
# scenario_zz_louvain.sh (R12C /louvain),
# scenario_eee_pagerank.sh (R13E /pagerank). Those are PROGRAMMATIC
# read paths: the operator picks which `_cmd` to invoke. R15D ships
# the DECLARATIVE one: a single text-based query language that
# composes triple patterns + FILTER conditions + LIMIT, so the
# operator can write "SELECT ?a WHERE { ?a kind FACT . FILTER alpha
# > 500 . }" without learning CrossEngin's atom field names first.
#
# This scenario drives the chat dispatch path. The unit test suite
# (~55 assertions in test_kg_query.nova) covers the parser /
# executor on a small fixture KG; here we just verify the wiring
# all the way through the chat REPL is sound:
#   1. /query with a simple FACT query returns 0+ bindings without
#      crashing (chat KG has CONCEPT atoms by default; CONCEPT
#      should hit at least one);
#   2. LIMIT clamps the result set;
#   3. FILTER on an int field works;
#   4. Bad syntax produces a graceful QUERY error= line (no crash).

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

it_section "scenario KKK: mini-SPARQL declarative query language + /query command"

if [ ! -x "$CHAT" ]; then
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  CHAT binary not built at %s\n" "$CHAT"
    summary "scenario_kkk_query"
    exit 1
fi

# --- step 1: empty arg shows usage --------------------------------------
CHAT_OUT=$(run_chat '/query')
assert_match "$CHAT_OUT" "usage: /query <SPARQL_string>" \
    "/query with no arg prints usage line"
assert_match "$CHAT_OUT" "QUERY store_size=" \
    "/query with no arg prints store_size diagnostic"

# --- step 2: simple CONCEPT query returns bindings ----------------------
# Seed pack includes CONCEPT atoms; assert /query routes through the
# parser/executor and emits at least the QUERY header + QUERY_END.
CHAT_OUT=$(run_chat '/query SELECT ?a WHERE { ?a kind CONCEPT . } LIMIT 3')
assert_match "$CHAT_OUT" "QUERY bindings=" \
    "/query CONCEPT prints QUERY header"
assert_match "$CHAT_OUT" "QUERY bindings=[0-9]+ vars=1 limit=3" \
    "/query CONCEPT reports vars=1 limit=3"
assert_match "$CHAT_OUT" "^QUERY_END$" \
    "/query CONCEPT emits END marker"

# Pull the binding count and verify <= 3 (LIMIT 3).
BIND_COUNT=$(echo "$CHAT_OUT" | grep -E 'QUERY bindings=' | head -1 \
    | sed -E 's/.*bindings=([0-9]+).*/\1/')
if [ -n "$BIND_COUNT" ] && [ "$BIND_COUNT" -le 3 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  /query CONCEPT respects LIMIT 3 (got %s bindings)\n" "$BIND_COUNT"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  /query CONCEPT exceeded LIMIT 3 (got %s)\n" "$BIND_COUNT"
fi

# --- step 3: FACT query (the seed pack rarely contains FACTs but the
# parser must still run + return cleanly; bindings>=0)
CHAT_OUT=$(run_chat '/query SELECT ?a WHERE { ?a kind FACT . } LIMIT 5')
assert_match "$CHAT_OUT" "QUERY bindings=" \
    "/query FACT prints QUERY header"
assert_match "$CHAT_OUT" "^QUERY_END$" \
    "/query FACT emits END marker"

# --- step 4: two-pattern query exercises the linked-pair path ----------
# ?a kind CONCEPT . ?a links ?b -- the binding count may be zero if
# CONCEPTs in the seed pack have no xrefs, but the dispatcher must NOT
# crash; the QUERY header + END must both land.
CHAT_OUT=$(run_chat '/query SELECT ?a ?b WHERE { ?a kind CONCEPT . ?a links ?b . } LIMIT 5')
assert_match "$CHAT_OUT" "QUERY bindings=" \
    "/query two-pattern prints QUERY header"
assert_match "$CHAT_OUT" "vars=2" \
    "/query two-pattern reports vars=2"
assert_match "$CHAT_OUT" "^QUERY_END$" \
    "/query two-pattern emits END marker"

# --- step 5: FILTER on alpha works -------------------------------------
# alpha > 500 should match every atom whose belief alpha is above the
# uniform prior 1000 -- which is every atom that has received at least
# one observation. The seed pack runs through the substrate, so most
# CONCEPTs have alpha == 1000 (the prior), satisfying > 500.
CHAT_OUT=$(run_chat '/query SELECT ?a WHERE { ?a kind CONCEPT . FILTER alpha > 500 . } LIMIT 3')
assert_match "$CHAT_OUT" "QUERY bindings=" \
    "/query FILTER prints QUERY header"
assert_match "$CHAT_OUT" "^QUERY_END$" \
    "/query FILTER emits END marker"

# --- step 6: bad syntax produces graceful error ------------------------
CHAT_OUT=$(run_chat '/query bogus syntax not even SPARQL')
assert_match "$CHAT_OUT" "QUERY error=" \
    "/query bad syntax prints QUERY error= line"
assert_nomatch "$CHAT_OUT" "Segmentation fault" \
    "/query bad syntax does NOT segfault"

# --- step 7: empty WHERE block ----------------------------------------
# SELECT ?a WHERE {} returns the seed binding (one empty binding) since
# there's no triple pattern to extend; vars list has 1 entry.
CHAT_OUT=$(run_chat '/query SELECT ?a WHERE { } LIMIT 1')
assert_match "$CHAT_OUT" "QUERY bindings=" \
    "/query empty WHERE prints QUERY header (no crash)"

# --- step 8: unterminated brace prints graceful error -----------------
CHAT_OUT=$(run_chat '/query SELECT ?a WHERE { ?a kind FACT .')
assert_match "$CHAT_OUT" "QUERY error=" \
    "/query missing brace prints error line"

# --- step 9: unknown predicate prints graceful error ------------------
CHAT_OUT=$(run_chat '/query SELECT ?a WHERE { ?a frobnicate FACT . }')
assert_match "$CHAT_OUT" "QUERY error=.*unknown predicate" \
    "/query unknown predicate prints error with reason"

summary "scenario_kkk_query"
