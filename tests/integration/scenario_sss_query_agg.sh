#!/usr/bin/env bash
# Scenario SSS -- mini-SPARQL aggregates (R17E): COUNT, SUM, AVG, MIN,
# MAX, GROUP BY. Sibling of scenario_kkk_query.sh (R15D BGP+FILTER+LIMIT)
# and scenario_ppp_query_ext.sh (R16F OPTIONAL+UNION+ORDER BY).
#
# R15D shipped the SPARQL core. R16F added OPTIONAL/UNION/ORDER BY.
# R17E closes the analytical-query gap: aggregate functions wrapped in
# (AGGFN(?var [field]) AS ?alias) tuples, and GROUP BY ?var to
# partition the binding set before aggregation.
#
# The unit-test suite (test_kg_query_agg.nova, 67 checks on the pinned
# 10-atom fixture) covers the parser + executor end-to-end. This
# scenario drives the wiring from the chat REPL all the way through
# the parser / executor / aggregator / emit-line discipline. We use
# the chat's default CONCEPT-heavy seed and check the shape of the
# QUERY / BINDING lines (counts vary across rounds but shape is
# stable).

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

it_section "scenario SSS: mini-SPARQL aggregates COUNT/SUM/AVG/MIN/MAX + GROUP BY (R17E)"

if [ ! -x "$CHAT" ]; then
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  CHAT binary not built at %s\n" "$CHAT"
    summary "scenario_sss_query_agg"
    exit 1
fi

# --- step 1: COUNT(?a) on a single kind returns ONE row -------------------
# A bare COUNT folds the entire binding set into one row. The output
# line always has the form `BINDING 1: n=<digits>`.
CHAT_OUT=$(run_chat '/query SELECT (COUNT(?a) AS ?n) WHERE { ?a kind CONCEPT . }')
assert_match "$CHAT_OUT" "QUERY bindings=1 vars=1 limit=100" \
    "/query COUNT(?a) reports bindings=1 vars=1"
assert_match "$CHAT_OUT" "BINDING 1: n=[0-9]+" \
    "/query COUNT(?a) emits BINDING 1 with n=<int>"
assert_match "$CHAT_OUT" "^QUERY_END\$" \
    "/query COUNT emits END marker"

# --- step 2: SUM(?a alpha) returns one row with `total=<int>` -------------
CHAT_OUT=$(run_chat '/query SELECT (SUM(?a alpha) AS ?total) WHERE { ?a kind CONCEPT . }')
assert_match "$CHAT_OUT" "QUERY bindings=1" \
    "/query SUM reports bindings=1"
assert_match "$CHAT_OUT" "BINDING 1: total=[0-9]+" \
    "/query SUM emits BINDING 1 with total=<int>"

# --- step 3: GROUP BY ?kind returns one row per kind ----------------------
# Seed pack has at least CONCEPT atoms (vars=2: kind + alias n). One
# row per distinct ?kind value -- the seed pack typically has CONCEPT
# (and possibly LANG/RELATION). We assert >= 1 binding rows and that
# `kind=<int>` and `n=<int>` both appear on row 1.
CHAT_OUT=$(run_chat '/query SELECT ?kind (COUNT(?a) AS ?n) WHERE { ?a kind ?kind . } GROUP BY ?kind')
assert_match "$CHAT_OUT" "QUERY bindings=[0-9]+ vars=2 limit=100" \
    "/query GROUP BY reports vars=2"
assert_match "$CHAT_OUT" "BINDING 1: kind=[0-9]+ n=[0-9]+" \
    "/query GROUP BY first row has kind=<int> n=<int>"
# Pull the bindings count -- must be >= 1.
GROUP_COUNT=$(echo "$CHAT_OUT" | grep -E 'QUERY bindings=' | head -1 \
    | sed -E 's/.*bindings=([0-9]+).*/\1/')
if [ -n "$GROUP_COUNT" ] && [ "$GROUP_COUNT" -ge 1 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  /query GROUP BY emits at least 1 group row (got %s)\n" "$GROUP_COUNT"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  /query GROUP BY emits 0 group rows\n"
fi
assert_match "$CHAT_OUT" "^QUERY_END\$" \
    "/query GROUP BY emits END marker"

# --- step 4: MIN/MAX aggregates work --------------------------------------
CHAT_OUT=$(run_chat '/query SELECT (MIN(?a alpha) AS ?lo) (MAX(?a alpha) AS ?hi) WHERE { ?a kind CONCEPT . }')
assert_match "$CHAT_OUT" "QUERY bindings=1 vars=2" \
    "/query MIN+MAX reports bindings=1 vars=2"
assert_match "$CHAT_OUT" "BINDING 1: lo=[0-9-]+ hi=[0-9-]+" \
    "/query MIN+MAX emits both aliases on one row"

# --- step 5: AVG aggregate returns one row with mean ----------------------
CHAT_OUT=$(run_chat '/query SELECT (AVG(?a alpha) AS ?mean) WHERE { ?a kind CONCEPT . }')
assert_match "$CHAT_OUT" "QUERY bindings=1" \
    "/query AVG reports bindings=1"
assert_match "$CHAT_OUT" "BINDING 1: mean=[0-9-]+" \
    "/query AVG emits mean=<int>"

# --- step 6: aggregate + FILTER combination -------------------------------
# FILTER applies BEFORE aggregation (the brief pins this). Filter the
# CONCEPTs by alpha > 500 (all of them satisfy this); COUNT should equal
# the unfiltered count. (We can't pin the exact int across seed rounds,
# but the structural invariant -- filtered count <= unfiltered count --
# always holds.)
CHAT_OUT_ALL=$(run_chat '/query SELECT (COUNT(?a) AS ?n) WHERE { ?a kind CONCEPT . }')
ALL_N=$(echo "$CHAT_OUT_ALL" | grep -oE 'n=[0-9]+' | head -1 | sed 's/n=//')
CHAT_OUT_FLT=$(run_chat '/query SELECT (COUNT(?a) AS ?n) WHERE { ?a kind CONCEPT . FILTER alpha > 500 . }')
FLT_N=$(echo "$CHAT_OUT_FLT" | grep -oE 'n=[0-9]+' | head -1 | sed 's/n=//')
if [ -n "$ALL_N" ] && [ -n "$FLT_N" ] && [ "$FLT_N" -le "$ALL_N" ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  /query COUNT with FILTER alpha>500 <= unfiltered (got %s <= %s)\n" "$FLT_N" "$ALL_N"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  /query FILTER+COUNT invariant violated (filtered=%s, unfiltered=%s)\n" "$FLT_N" "$ALL_N"
fi

# --- step 7: COUNT on an empty result set returns 0 -----------------------
# alpha > 99999999 matches nothing; COUNT must still emit one row with n=0.
CHAT_OUT=$(run_chat '/query SELECT (COUNT(?a) AS ?n) WHERE { ?a kind CONCEPT . FILTER alpha > 99999999 . }')
assert_match "$CHAT_OUT" "QUERY bindings=1" \
    "/query COUNT on empty set still emits 1 row"
assert_match "$CHAT_OUT" "BINDING 1: n=0" \
    "/query COUNT on empty set returns 0"

# --- step 8: multiple aggregates in one SELECT ----------------------------
CHAT_OUT=$(run_chat '/query SELECT (COUNT(?a) AS ?n) (SUM(?a alpha) AS ?total) (MAX(?a alpha) AS ?hi) WHERE { ?a kind CONCEPT . }')
assert_match "$CHAT_OUT" "QUERY bindings=1 vars=3" \
    "/query multi-aggregate reports bindings=1 vars=3"
assert_match "$CHAT_OUT" "BINDING 1: n=[0-9]+ total=[0-9]+ hi=[0-9-]+" \
    "/query multi-aggregate emits all three aliases on one row"

# --- step 9: bad aggregate syntax produces graceful error -----------------
# Missing AS keyword.
CHAT_OUT=$(run_chat '/query SELECT (COUNT(?a) ?n) WHERE { ?a kind CONCEPT . }')
assert_match "$CHAT_OUT" "QUERY error=" \
    "/query bad aggregate syntax prints error line"
assert_nomatch "$CHAT_OUT" "Segmentation fault" \
    "/query bad aggregate syntax does NOT segfault"

# Unknown aggregate function.
CHAT_OUT=$(run_chat '/query SELECT (MEDIAN(?a alpha) AS ?m) WHERE { ?a kind CONCEPT . }')
assert_match "$CHAT_OUT" "QUERY error=" \
    "/query unknown aggregate function prints error line"

# --- step 10: bad GROUP BY syntax produces graceful error -----------------
CHAT_OUT=$(run_chat '/query SELECT ?kind WHERE { ?a kind ?kind . } GROUP BY')
assert_match "$CHAT_OUT" "QUERY error=" \
    "/query GROUP BY missing var prints error line"

# --- step 11: existing R15D and R16F queries still work (regression) ------
CHAT_OUT=$(run_chat '/query SELECT ?a WHERE { ?a kind CONCEPT . } LIMIT 3')
assert_match "$CHAT_OUT" "QUERY bindings=" \
    "/query R15D bare-var SELECT still works (regression)"
CHAT_OUT=$(run_chat '/query SELECT ?a WHERE { ?a kind CONCEPT . } ORDER BY ASC(alpha) LIMIT 3')
assert_match "$CHAT_OUT" "QUERY bindings=3 vars=1 limit=3" \
    "/query R16F ORDER BY still works (regression)"

summary "scenario_sss_query_agg"
