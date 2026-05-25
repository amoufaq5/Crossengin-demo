#!/usr/bin/env bash
# Run the CrossEngin substrate self-check.
#
# NOTE (v0.1): there is no end-user cognitive agent yet. The runnable artifact
# at this stage is the substrate self-check (examples/kernel_selfcheck.nova),
# which boots the implemented substrate primitives and reports liveness. See
# NEXT_SESSION.md for what remains before a full agent can run.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

NOVA_ROOT="${NOVA_ROOT:-$HOME/NOVA}"
NOVA="$NOVA_ROOT/nova"
SELFCHECK="examples/kernel_selfcheck.nova"

if [ ! -x "$NOVA" ]; then
  echo "ERROR: NOVA launcher not found at '$NOVA'. Set NOVA_ROOT=/path/to/NOVA." >&2
  exit 2
fi
if [ ! -f "$SELFCHECK" ]; then
  echo "ERROR: $SELFCHECK not present yet. Run 'make build' and see NEXT_SESSION.md." >&2
  exit 1
fi

echo "=== CrossEngin substrate self-check ==="
exec "$NOVA" run "$SELFCHECK" "$@"
