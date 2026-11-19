#!/usr/bin/env bash
# Scenario e2-harness -- B6 (E2 conflicting-sources harness, experiments/e2).
#   1. e2.py selftest (metric port, generator, baselines, bootstrap, Holm).
#   2. The driver builds from experiments/e2/e2_driver.nova.
#   3. A development dataset (seed 999, 150 facts; not a study dataset) runs
#      through every arm, and the Python metric port matches the driver's own
#      calibration.nova output exactly.

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0
it_section "scenario e2-harness: selftest, driver build, dev-dataset smoke"

E2="$REPO_ROOT/experiments/e2/e2.py"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
NOVA="${NOVA_ROOT:-$HOME/NOVA}/nova"
if [ ! -x "$NOVA" ]; then
    echo "SKIP: NOVA launcher not found at $NOVA"
    if [ "${CE_IT_STRICT:-0}" = "1" ]; then exit 1; fi
    exit 0
fi

assert_match "$(python3 -I "$E2" --selftest 2>&1)" "[-]> OK$" "e2 selftest"
"$NOVA" build "$REPO_ROOT/experiments/e2/e2_driver.nova" -o "$WORK/e2-driver" >/dev/null 2>&1
assert_eq "$([ -x "$WORK/e2-driver" ] && echo built)" "built" "driver builds"
OUT=$(python3 -I "$E2" run --driver "$WORK/e2-driver" --out "$WORK/r" --modes M0,M2,M4 \
      --seeds 999 --facts 150 --jobs 2 --partial 2>&1)
assert_match "$OUT" "^ok: 18 run" "every arm runs on the dev datasets"
assert_eq "$(python3 -c "import json;print(json.load(open('$WORK/r/manifest.json'))['metric_crosscheck_failures'])" 2>/dev/null)" "0" "metric port matches calibration.nova"
assert_eq "$(tail -n +2 "$WORK/r/scores.tsv" 2>/dev/null | wc -l | tr -d ' ')" "18" "18 score rows"
assert_eq "$(python3 -I "$E2" run --driver "$WORK/e2-driver" --out "$WORK/r2" --seeds 999 2>&1 | head -1 | grep -c 'pass --partial')" "1" "non-registered design refused without --partial"

summary "scenario_e2_harness"
