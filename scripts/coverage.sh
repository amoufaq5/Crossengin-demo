#!/usr/bin/env bash
# Report CrossEngin unit-test coverage at the MODULE level (NL_AND_COVERAGE C2).
#
# A source module under src/ counts as *covered* iff it is reachable, through
# the transitive `import` graph, from some test under tests/unit/. This is the
# exact metric NL_AND_COVERAGE.md's baseline used; this script makes it a
# repeatable target instead of a hand count, so a newly-added module that no
# test exercises is caught immediately.
#
# Usage:
#   bash scripts/coverage.sh            # summary + list any uncovered modules
#   bash scripts/coverage.sh --list     # also list every covered module
#   make coverage                       # same, via the Makefile
#
# Exit status: 0 if every source module is covered, 1 if any is uncovered (so
# CI / `make coverage` fails loudly on a regression). No NOVA toolchain needed
# -- this is pure static analysis of import lines.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

LIST_COVERED=0
if [ "${1:-}" = "--list" ]; then LIST_COVERED=1; fi

# All implemented source modules (the universe we measure), normalised to
# repo-relative paths. `.pending` modules are not built, so not measured.
mapfile -t SRC_MODULES < <(find src -name '*.nova' ! -name '*.pending' 2>/dev/null \
    | sed 's#^\./##' | sort)

if [ ${#SRC_MODULES[@]} -eq 0 ]; then
  echo "coverage: no implemented modules under src/."
  exit 0
fi

declare -A IS_SRC=()
for m in "${SRC_MODULES[@]}"; do IS_SRC["$m"]=1; done

# Extract the quoted target of every `import "..."` line in a file.
imports_of() {
  grep -oE '^[[:space:]]*import[[:space:]]+"[^"]+"' "$1" 2>/dev/null \
    | sed -E 's#^[[:space:]]*import[[:space:]]+"([^"]+)".*#\1#'
}

# Resolve an import target (relative to the importing file's directory) to a
# normalised repo-relative path.
resolve() {
  local from_dir="$1" rel="$2"
  realpath -m --relative-to="$REPO_ROOT" "$from_dir/$rel" 2>/dev/null
}

# BFS the import graph from every unit test, marking every reachable .nova file.
declare -A SEEN=()
queue=()
shopt -s nullglob
for t in tests/unit/*.nova; do
  SEEN["$t"]=1
  queue+=("$t")
done

while [ ${#queue[@]} -gt 0 ]; do
  f="${queue[0]}"
  queue=("${queue[@]:1}")
  [ -f "$f" ] || continue
  from_dir="$(dirname "$f")"
  while IFS= read -r imp; do
    [ -n "$imp" ] || continue
    target="$(resolve "$from_dir" "$imp")"
    [ -n "$target" ] || continue
    if [ -z "${SEEN[$target]:-}" ]; then
      SEEN["$target"]=1
      queue+=("$target")
    fi
  done < <(imports_of "$f")
done

# Partition the source universe into covered / uncovered.
covered=()
uncovered=()
for m in "${SRC_MODULES[@]}"; do
  if [ -n "${SEEN[$m]:-}" ]; then covered+=("$m"); else uncovered+=("$m"); fi
done

total=${#SRC_MODULES[@]}
ncov=${#covered[@]}
nunc=${#uncovered[@]}

echo "=== CrossEngin module coverage ==="
if [ $LIST_COVERED -eq 1 ]; then
  echo "covered modules:"
  for m in "${covered[@]}"; do echo "  + $m"; done
fi
if [ $nunc -gt 0 ]; then
  echo "uncovered modules (no unit test imports them, directly or transitively):"
  for m in "${uncovered[@]}"; do echo "  - $m"; done
fi
echo "----------------------------------------"
echo "  covered: $ncov   uncovered: $nunc   total: $total"
if [ $nunc -ne 0 ]; then
  echo "coverage: INCOMPLETE -- $nunc module(s) untested."
  exit 1
fi
echo "coverage: COMPLETE -- all $total module(s) covered."
