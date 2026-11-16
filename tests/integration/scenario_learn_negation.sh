#!/usr/bin/env bash
# Scenario learn-negation -- audit F-20: scripts/learn.sh used to turn
# "X is not Y" into X|is_a|Y (and "X does not cause Y" into X|causal|Y),
# storing the negated claim as a fact. Runs learn.sh on a local file (no
# network) and checks the extracted triples.

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0
it_section "scenario learn-negation: learn.sh drops negated claims"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK" /tmp/crossengin_learn_negfix*' EXIT
SRC="$WORK/negfix.txt"
cat > "$SRC" <<'TXT'
The earth is not flat. The earth is round.
Smoking does not cause happiness. Smoking causes cancer.
The planet isn't square. Whales are never fishes. Whales are mammals.
TXT

bash "$REPO_ROOT/scripts/learn.sh" "$SRC" >/dev/null 2>&1
TRIPLES="$(cat /tmp/crossengin_learn_negfix_triples.txt 2>/dev/null)"

assert_match   "$TRIPLES" 'earth\|is_a\|round'      "positive is_a kept"
assert_match   "$TRIPLES" 'smoking\|causal\|cancer' "positive causal kept"
assert_match   "$TRIPLES" 'whales\|is_a\|mammals'   "plural positive kept"
assert_nomatch "$TRIPLES" 'earth\|is_a\|flat'        "'is not' not stored as is_a"
assert_nomatch "$TRIPLES" 'smoking\|causal\|happiness' "'does not cause' not stored"
assert_nomatch "$TRIPLES" 'planet\|is_a\|square'     "\"isn't\" not stored as is_a"
assert_nomatch "$TRIPLES" 'whales\|is_a\|fishes'     "'are never' not stored as is_a"

summary "scenario_learn_negation"
