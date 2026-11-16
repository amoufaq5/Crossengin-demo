#!/usr/bin/env bash
# CI unit-test gate: run every tests/unit/*.nova (in parallel) and compare the
# failures with tests/unit/known_failures.txt.
#
#   exit 0  no failure outside the list (listed tests that now pass are
#           reported so they can be removed from the list)
#   exit 1  at least one test failed that is not listed (a regression)
#
# Pass/fail per test is decided exactly as scripts/test.sh does: exit 0 and no
# "assertion failed" / "FAIL" in the output, with the same per-test timeout
# and `// CE_TEST_TIMEOUT: N` override. scripts/test.sh stays the
# sequential, everything-must-pass runner behind `make test`.
#
# Env: NOVA_ROOT (default $HOME/NOVA), CE_TEST_JOBS (default: nproc),
#      CE_TEST_TIMEOUT (default 60), KNOWN_FAILURES (default
#      tests/unit/known_failures.txt).
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

NOVA_ROOT="${NOVA_ROOT:-$HOME/NOVA}"
export NOVA="$NOVA_ROOT/nova"
export CE_TEST_TIMEOUT="${CE_TEST_TIMEOUT:-60}"
JOBS="${CE_TEST_JOBS:-$(nproc 2>/dev/null || echo 2)}"
KNOWN="${KNOWN_FAILURES:-tests/unit/known_failures.txt}"

if [ ! -x "$NOVA" ]; then
  echo "ERROR: NOVA launcher not found at '$NOVA'. Set NOVA_ROOT=/path/to/NOVA." >&2
  exit 2
fi

RES="$(mktemp -d)"
trap 'rm -rf "$RES"' EXIT
export RES

run_one() {
  local t="$1" name to override out rc verdict
  name="$(basename "$t" .nova)"
  to="$CE_TEST_TIMEOUT"
  override="$(head -20 "$t" | grep -E '^// CE_TEST_TIMEOUT: *[0-9]+' | head -1 \
              | sed -E 's|^// CE_TEST_TIMEOUT: *([0-9]+).*|\1|')"
  [ -n "$override" ] && to="$override"
  out="$(timeout --preserve-status "${to}s" "$NOVA" run "$t" 2>&1)"
  rc=$?
  if [ $rc -eq 124 ] || [ $rc -eq 137 ]; then
    verdict="TIMEOUT"
  elif [ $rc -eq 0 ] && ! grep -qiE 'assertion failed|(^| )FAIL' <<<"$out"; then
    verdict="PASS"
  else
    verdict="FAIL"
  fi
  printf '%s\n' "$out" > "$RES/$name.log"
  printf '%s %s rc=%s\n' "$verdict" "$name" "$rc" > "$RES/$name.verdict"
  printf '  %-40s %s\n' "$name" "$verdict"
}
export -f run_one

echo "=== CrossEngin unit tests (CI gate; NOVA: $NOVA; jobs: $JOBS) ==="
ls tests/unit/*.nova | xargs -P "$JOBS" -I{} bash -c 'run_one "$@"' _ {}

cat "$RES"/*.verdict > "$RES/all"
pass=$(grep -c '^PASS ' "$RES/all")
fail=$(grep -vc '^PASS ' "$RES/all")
echo "----------------------------------------"
echo "  passed: $pass   failed: $fail   total: $((pass + fail))"

grep -v '^PASS ' "$RES/all" | awk '{print $2}' | sort -u > "$RES/failed"
grep -v '^#' "$KNOWN" 2>/dev/null | grep -v '^$' | sort -u > "$RES/known"
NEW="$(comm -23 "$RES/failed" "$RES/known")"
FIXED="$(comm -13 "$RES/failed" "$RES/known")"

if [ -n "$FIXED" ]; then
  echo ""
  echo "Listed in $KNOWN but passing now (remove them from the list):"
  echo "$FIXED" | sed 's/^/  /'
fi
if [ -n "$NEW" ]; then
  echo ""
  echo "REGRESSION: failing tests not in $KNOWN:"
  for n in $NEW; do
    grep " $n " "$RES/all"
    sed 's/^/      /' "$RES/$n.log" | tail -15
  done
  exit 1
fi
echo ""
echo "No regressions against $KNOWN."
