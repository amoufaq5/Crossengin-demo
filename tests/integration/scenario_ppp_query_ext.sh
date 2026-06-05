#!/usr/bin/env bash
# Scenario PPP -- mini-SPARQL extensions (R16F): OPTIONAL + UNION +
# ORDER BY. Sibling of scenario_kkk_query.sh (R15D BGP+FILTER+LIMIT).
#
# R15D shipped the SPARQL core: SELECT vars + WHERE { triples + FILTERs
# } + LIMIT. R16F closes the gap to the W3C "SPARQL 1.0 core" surface:
#
#   - OPTIONAL { ... } (left-outer-join: keep bindings even when the
#     inner block doesn't match; the introduced vars are left unbound
#     and rendered as "?" in the BINDING emit line)
#   - { ... } UNION { ... } (alternation: results of either side are
#     concatenated)
#   - ORDER BY [ASC|DESC] (field | (field)): sort by an int field of
#     the most-recently bound atom; ties broken by atom_id ASC for
#     stability; LIMIT applies AFTER the sort.
#
# The unit-test suite (test_kg_query_ext.nova, ~60 checks) covers the
# parser + executor on a pinned 10-atom fixture. This scenario drives
# the wiring from the chat REPL all the way through the parser /
# executor / emit-line discipline. We use the chat's default CONCEPT
# seed (FACTs and RULEs are essentially absent) and check on the
# shape of the QUERY / BINDING lines rather than exact counts where
# the seed varies.

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

it_section "scenario PPP: mini-SPARQL extensions OPTIONAL/UNION/ORDER BY (R16F)"

if [ ! -x "$CHAT" ]; then
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  CHAT binary not built at %s\n" "$CHAT"
    summary "scenario_ppp_query_ext"
    exit 1
fi

# --- step 1: OPTIONAL { ... } parses + executes ----------------------------
# CONCEPT atoms in the seed pack; OPTIONAL on `?a links ?b` should leave
# the dispatcher's output line intact (QUERY header + END). Some seed
# CONCEPTs have xrefs (the productive seed wires CONCEPTs together);
# OPTIONAL guarantees a binding even when they don't, so the binding
# count equals the number of CONCEPT atoms in scope, and the rendered
# BINDING lines either show `b=<id>` (bound) or `b=?` (unbound).
CHAT_OUT=$(run_chat '/query SELECT ?a ?b WHERE { ?a kind CONCEPT . OPTIONAL { ?a links ?b . } } LIMIT 5')
assert_match "$CHAT_OUT" "QUERY bindings=" \
    "/query OPTIONAL prints QUERY header"
assert_match "$CHAT_OUT" "vars=2" \
    "/query OPTIONAL reports vars=2"
assert_match "$CHAT_OUT" "^QUERY_END\$" \
    "/query OPTIONAL emits END marker"
# Every BINDING line ends with `b=<digits>` (bound) or `b=?` (unbound).
# Make sure the "?" sentinel rendering works at least once on the seed.
# (If the seed wires every CONCEPT, the test passes via the digit path;
# we accept either.)
assert_match "$CHAT_OUT" "BINDING 1: a=" \
    "/query OPTIONAL emits at least one BINDING row"

# --- step 2: UNION { CONCEPT } UNION { LANG } counts > each side alone -----
# CONCEPT vs LANG sides; UNION concatenates with bag semantics. We can't
# pin exact seed counts (they shift across rounds), but UNION's count
# >= max(left, right) is a structural invariant.
CHAT_OUT_LEFT=$(run_chat '/query SELECT ?a WHERE { ?a kind CONCEPT . } LIMIT 10000')
LEFT_COUNT=$(echo "$CHAT_OUT_LEFT" | grep -E 'QUERY bindings=' | head -1 | sed -E 's/.*bindings=([0-9]+).*/\1/')
CHAT_OUT_RIGHT=$(run_chat '/query SELECT ?a WHERE { ?a kind LANG . } LIMIT 10000')
RIGHT_COUNT=$(echo "$CHAT_OUT_RIGHT" | grep -E 'QUERY bindings=' | head -1 | sed -E 's/.*bindings=([0-9]+).*/\1/')
CHAT_OUT_UNION=$(run_chat '/query SELECT ?a WHERE { { ?a kind CONCEPT . } UNION { ?a kind LANG . } } LIMIT 10000')
UNION_COUNT=$(echo "$CHAT_OUT_UNION" | grep -E 'QUERY bindings=' | head -1 | sed -E 's/.*bindings=([0-9]+).*/\1/')
assert_match "$CHAT_OUT_UNION" "QUERY bindings=" \
    "/query UNION prints QUERY header"
assert_match "$CHAT_OUT_UNION" "^QUERY_END\$" \
    "/query UNION emits END marker"
EXPECT=$((LEFT_COUNT + RIGHT_COUNT))
if [ -n "$UNION_COUNT" ] && [ "$UNION_COUNT" -eq "$EXPECT" ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  /query UNION count = left+right (got %s = %s + %s)\n" "$UNION_COUNT" "$LEFT_COUNT" "$RIGHT_COUNT"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  /query UNION count mismatch (got %s, expected %s = %s+%s)\n" "$UNION_COUNT" "$EXPECT" "$LEFT_COUNT" "$RIGHT_COUNT"
fi

# --- step 3: ORDER BY DESC(alpha) LIMIT 3 returns 3 -----------------------
# Top-3 by descending alpha on CONCEPT atoms. Even when alphas tie
# (every prior == 1000), the LIMIT applies after the (stable) sort.
CHAT_OUT=$(run_chat '/query SELECT ?a WHERE { ?a kind CONCEPT . } ORDER BY DESC(alpha) LIMIT 3')
assert_match "$CHAT_OUT" "QUERY bindings=3 vars=1 limit=3" \
    "/query ORDER BY DESC LIMIT 3 reports vars/limit"
assert_match "$CHAT_OUT" "BINDING 3: a=" \
    "/query ORDER BY emits exactly 3 BINDING rows"
assert_match "$CHAT_OUT" "^QUERY_END\$" \
    "/query ORDER BY DESC emits END marker"

# --- step 4: ORDER BY ASC(alpha) returns same count, different lead row ---
# ASC and DESC differ ONLY in direction. We can't pin the first id
# (depends on whether seed alphas vary), but the count is identical
# and BINDING 1 still parses.
CHAT_OUT=$(run_chat '/query SELECT ?a WHERE { ?a kind CONCEPT . } ORDER BY ASC(alpha) LIMIT 3')
assert_match "$CHAT_OUT" "QUERY bindings=3 vars=1 limit=3" \
    "/query ORDER BY ASC LIMIT 3 reports vars/limit"
assert_match "$CHAT_OUT" "^QUERY_END\$" \
    "/query ORDER BY ASC emits END marker"

# --- step 5: ORDER BY default direction is ASC ----------------------------
# "ORDER BY alpha" with no direction keyword == ASC.
CHAT_OUT=$(run_chat '/query SELECT ?a WHERE { ?a kind CONCEPT . } ORDER BY alpha LIMIT 3')
assert_match "$CHAT_OUT" "QUERY bindings=3" \
    "/query ORDER BY default-ASC prints QUERY header"
assert_match "$CHAT_OUT" "^QUERY_END\$" \
    "/query ORDER BY default-ASC emits END marker"

# --- step 6: bad ORDER BY syntax produces graceful error ------------------
CHAT_OUT=$(run_chat '/query SELECT ?a WHERE { ?a kind CONCEPT . } ORDER BY')
assert_match "$CHAT_OUT" "QUERY error=" \
    "/query bad ORDER BY prints error line"
assert_nomatch "$CHAT_OUT" "Segmentation fault" \
    "/query bad ORDER BY does NOT segfault"

# --- step 7: bad OPTIONAL syntax produces graceful error ------------------
CHAT_OUT=$(run_chat '/query SELECT ?a WHERE { OPTIONAL not-a-brace }')
assert_match "$CHAT_OUT" "QUERY error=" \
    "/query bad OPTIONAL prints error line"

# --- step 8: bad UNION (missing right side) produces graceful error -------
CHAT_OUT=$(run_chat '/query SELECT ?a WHERE { { ?a kind CONCEPT . } UNION }')
assert_match "$CHAT_OUT" "QUERY error=" \
    "/query bad UNION prints error line"

# --- step 9: existing R15D query shapes still parse + execute --------------
# (Regression-guard: confirm R16F didn't break the BGP+FILTER+LIMIT
# surface the R15D scenario_kkk_query.sh suite locks in.)
CHAT_OUT=$(run_chat '/query SELECT ?a WHERE { ?a kind CONCEPT . FILTER alpha > 500 . } LIMIT 3')
assert_match "$CHAT_OUT" "QUERY bindings=" \
    "/query R15D FILTER shape still works (regression)"
assert_match "$CHAT_OUT" "^QUERY_END\$" \
    "/query R15D FILTER shape emits END marker"

# --- step 10: combined OPTIONAL + ORDER BY + LIMIT in a single query ------
# Stress: stack all three extensions in one query. The substrate must
# still emit a single QUERY header and a single QUERY_END.
CHAT_OUT=$(run_chat '/query SELECT ?a ?b WHERE { ?a kind CONCEPT . OPTIONAL { ?a links ?b . } } ORDER BY DESC(alpha) LIMIT 3')
assert_match "$CHAT_OUT" "QUERY bindings=3 vars=2 limit=3" \
    "/query combined OPTIONAL+ORDER+LIMIT reports vars/limit"
assert_match "$CHAT_OUT" "^QUERY_END\$" \
    "/query combined OPTIONAL+ORDER+LIMIT emits END marker"

summary "scenario_ppp_query_ext"
