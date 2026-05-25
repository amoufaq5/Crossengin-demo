#!/usr/bin/env bash
# Set up a CrossEngin development environment.
#   - verifies the host build tools (GNU as/ld, make, gcc)
#   - locates the NOVA toolchain (sibling checkout by default)
#   - builds the NOVA compiler if it has not been built yet
#   - runs a one-line sanity check
# Run from anywhere:  bash scripts/bootstrap.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NOVA_ROOT="${NOVA_ROOT:-$HOME/NOVA}"

echo "=== CrossEngin bootstrap ==="
echo "repo:      $REPO_ROOT"
echo "NOVA_ROOT: $NOVA_ROOT"

echo "--- checking host build tools ---"
missing=0
for tool in as ld make gcc; do
  if command -v "$tool" >/dev/null 2>&1; then
    echo "  ok: $tool ($(command -v "$tool"))"
  else
    echo "  MISSING: $tool"
    missing=1
  fi
done
if [ $missing -ne 0 ]; then
  echo "Install GNU binutils + make + gcc, then re-run." >&2
  exit 1
fi

echo "--- checking NOVA toolchain ---"
if [ ! -d "$NOVA_ROOT" ]; then
  echo "  NOVA checkout not found at $NOVA_ROOT." >&2
  echo "  Clone it next to this repo (git clone https://github.com/amoufaq5/nova \"$NOVA_ROOT\")" >&2
  echo "  or set NOVA_ROOT=/path/to/NOVA and re-run." >&2
  exit 1
fi
if [ ! -x "$NOVA_ROOT/bin/nova" ]; then
  echo "  NOVA compiler not built; building (cd $NOVA_ROOT && make) ..."
  ( cd "$NOVA_ROOT" && make )
fi
echo "  NOVA built: $NOVA_ROOT/bin/nova"

echo "--- sanity check ---"
"$NOVA_ROOT/nova" version || true

echo "=== bootstrap complete ==="
echo "Next:  make build   # compile substrate modules"
echo "       make test    # run unit tests"
