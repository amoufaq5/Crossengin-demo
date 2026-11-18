#!/usr/bin/env bash
# Run the full E1 study (all arms x all permutations) on bin/crossengin-chat.
# Usage: bash experiments/e1/run_e1.sh TAG   (results in experiments/e1/results/TAG)
# Env: E1_JOBS (default 4). See experiments/e1/PREREG.md.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHAT="$REPO_ROOT/bin/crossengin-chat"
TAG="${1:?usage: run_e1.sh TAG}"
if [ ! -x "$CHAT" ]; then echo "missing $CHAT -- run: make install" >&2; exit 2; fi
E1="$REPO_ROOT/experiments/e1/e1.py"
python3 -I "$E1" --selftest
python3 -I "$E1" lint
python3 -I "$E1" run --chat "$CHAT" --out "$REPO_ROOT/experiments/e1/results/$TAG" --jobs "${E1_JOBS:-4}"
