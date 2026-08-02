#!/usr/bin/env bash
# Compile and run every CrossEngin unit test under tests/unit/.
# A test passes iff its program exits 0 and prints no assertion failure.
# Exits non-zero if any test fails, times out, or crashes. Each test is capped
# at CE_TEST_TIMEOUT seconds (default 60) so a single hang can't block the suite.
# --fail-fast (or CE_FAIL_FAST=1) stops on the first failing test.
# Run from the repository root (the Makefile `test` target does this for you),
# or:  bash scripts/test.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

NOVA_ROOT="${NOVA_ROOT:-$HOME/NOVA}"
NOVA="$NOVA_ROOT/nova"
CE_TEST_TIMEOUT="${CE_TEST_TIMEOUT:-60}"
CE_FAIL_FAST="${CE_FAIL_FAST:-0}"

if [ "${1:-}" = "--fail-fast" ]; then
  CE_FAIL_FAST=1
fi

if [ ! -x "$NOVA" ]; then
  echo "ERROR: NOVA launcher not found at '$NOVA'. Set NOVA_ROOT=/path/to/NOVA." >&2
  exit 2
fi
if ! command -v timeout >/dev/null 2>&1; then
  echo "ERROR: 'timeout' not found (needed for per-test cap CE_TEST_TIMEOUT=${CE_TEST_TIMEOUT}s)." >&2
  exit 2
fi

shopt -s nullglob
tests=(tests/unit/*.nova)
if [ ${#tests[@]} -eq 0 ]; then
  echo "No unit tests found under tests/unit/."
  exit 0
fi

pass=0
fail=0
failed_names=()

echo "=== CrossEngin unit tests (NOVA: $NOVA; per-test timeout ${CE_TEST_TIMEOUT}s) ==="
for t in "${tests[@]}"; do
  printf '  %-36s ' "$(basename "$t")"
  # Per-test timeout so a single hang can't block the whole suite. `timeout`
  # exits 124 on TERM (its default signal) or 137 on KILL if the child didn't
  # respect TERM; we surface both distinctly from a normal FAIL.
  out="$(timeout --preserve-status "${CE_TEST_TIMEOUT}s" "$NOVA" run "$t" 2>&1)"
  rc=$?
  if [ $rc -eq 124 ] || [ $rc -eq 137 ]; then
    echo "TIMEOUT (>${CE_TEST_TIMEOUT}s, exit $rc)"
    sed 's/^/        /' <<<"$out"
    fail=$((fail + 1))
    failed_names+=("$(basename "$t"):timeout")
  elif [ $rc -eq 0 ] && ! grep -qiE 'assertion failed|(^| )FAIL' <<<"$out"; then
    echo "PASS"
    pass=$((pass + 1))
  else
    echo "FAIL (exit $rc)"
    sed 's/^/        /' <<<"$out"
    fail=$((fail + 1))
    failed_names+=("$(basename "$t")")
  fi
  if [ "$CE_FAIL_FAST" = "1" ] && [ $fail -gt 0 ]; then
    echo "----------------------------------------"
    echo "  --fail-fast: stopping after $((pass + fail)) test(s)."
    echo "  passed: $pass   failed: $fail"
    echo "  failing: ${failed_names[*]}"
    exit 1
  fi
done

echo "----------------------------------------"
echo "  passed: $pass   failed: $fail   total: $((pass + fail))"
if [ $fail -ne 0 ]; then
  echo "  failing: ${failed_names[*]}"
  exit 1
fi
echo "=== all unit tests passed ==="
