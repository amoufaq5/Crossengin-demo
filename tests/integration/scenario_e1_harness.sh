#!/usr/bin/env bash
# Scenario e1-harness -- B4 (E1 ablation harness, experiments/e1).
#   1. e1.py selftest (McNemar, Holm, parsing, gold specs, lint, perms) passes.
#   2. The replay, gold, permutations and arms lint clean.
#   3. One permutation of the full arm runs end to end: the determinism gate
#      (two runs byte-identical) passes and every scored item is parsed.
# No ablation arm runs here; the study itself runs offline (PREREG.md).

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0
it_section "scenario e1-harness: selftest, lint, full-arm smoke"

E1="$REPO_ROOT/experiments/e1/e1.py"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

assert_match "$(python3 -I "$E1" --selftest 2>&1)" "[-]> OK$" "e1 selftest"
assert_eq "$(python3 -I "$E1" lint 2>&1)" "lint: ok" "e1 inputs lint clean"

OUT=$(python3 -I "$E1" run --chat "$CHAT" --out "$WORK/r" --arms full --perms 1 --jobs 2 --partial 2>&1)
assert_match "$OUT" "^ok: 1 arm\(s\) x 1 perm\(s\) \(partial\)" "full arm runs end to end"
assert_eq "$(tail -n +2 "$WORK/r/determinism.tsv" 2>/dev/null)" "$(printf '1\t1')" "determinism gate: two runs identical"
assert_eq "$(tail -n +2 "$WORK/r/scores.tsv" 2>/dev/null | wc -l | tr -d ' ')" "200" "all 200 scored items parsed"

summary "scenario_e1_harness"
