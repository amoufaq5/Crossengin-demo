#!/usr/bin/env bash
# Compile and run every CrossEngin unit test under tests/unit/.
# A test passes iff its program exits 0 and prints no assertion failure.
# Exits non-zero if any test fails. Run from the repository root (the Makefile
# `test` target does this for you), or:  bash scripts/test.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

NOVA_ROOT="${NOVA_ROOT:-$HOME/NOVA}"
NOVA="$NOVA_ROOT/nova"

if [ ! -x "$NOVA" ]; then
  echo "ERROR: NOVA launcher not found at '$NOVA'. Set NOVA_ROOT=/path/to/NOVA." >&2
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

echo "=== CrossEngin unit tests (NOVA: $NOVA) ==="
for t in "${tests[@]}"; do
  printf '  %-36s ' "$(basename "$t")"
  out="$("$NOVA" run "$t" 2>&1)"
  rc=$?
  if [ $rc -eq 0 ] && ! grep -qiE 'assertion failed|(^| )FAIL' <<<"$out"; then
    echo "PASS"
    pass=$((pass + 1))
  else
    echo "FAIL (exit $rc)"
    sed 's/^/        /' <<<"$out"
    fail=$((fail + 1))
    failed_names+=("$(basename "$t")")
  fi
done

echo "----------------------------------------"
echo "  passed: $pass   failed: $fail   total: $((pass + fail))"
if [ $fail -ne 0 ]; then
  echo "  failing: ${failed_names[*]}"
  exit 1
fi
echo "=== all unit tests passed ==="
