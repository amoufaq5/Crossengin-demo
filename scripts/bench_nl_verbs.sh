#!/usr/bin/env bash
# CrossEngin R106 -- NL-verb latency bench driver (Phase H, ADR-0208).
#
# Runs tests/benchmark/bench_nl_verbs.nova, captures its
# `crossengin-bench-v1` JSON payload (or its SKIP line on a
# broken-nanotime host), and optionally compares to a saved baseline.
#
# Modes:
#   scripts/bench_nl_verbs.sh                          -- run, print JSON
#   scripts/bench_nl_verbs.sh --json <path>            -- run + save JSON
#   scripts/bench_nl_verbs.sh --compare <baseline>     -- run + diff vs baseline
#   scripts/bench_nl_verbs.sh --help
#
# Exit codes:
#   0  success (or graceful-skip; or empty baseline)
#   1  bench failed to compile / run
#   2  --compare regression detected (any median_ns > 1.5 * baseline)
#   3  bad invocation
#
# Graceful-skip: the bench prints a `SKIP: nanotime not functional...`
# line and exits 0 when the NOVA runtime clock is broken on the host
# (see docs/NOVA_RUNTIME_GAPS.md R-2). This driver treats that as a
# non-error and writes the SKIP line into any --json output file for
# audit traceability. --compare over a SKIP output is a no-op (there
# are no measurements to diff).

set -euo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"

NOVA_ROOT="${NOVA_ROOT:-$HOME/NOVA}"
if [ ! -x "$NOVA_ROOT/nova" ] && [ -x "/home/user/NOVA/nova" ]; then
    NOVA_ROOT="/home/user/NOVA"
fi
export NOVA_ROOT

MODE="stdout"       # stdout | json | compare
JSON_PATH=""
COMPARE_FILE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --json)
            MODE="json"
            shift
            if [ $# -eq 0 ]; then
                echo "error: --json requires a path" >&2
                exit 3
            fi
            JSON_PATH="$1"
            shift
            ;;
        --compare)
            MODE="compare"
            shift
            if [ $# -eq 0 ]; then
                echo "error: --compare requires a baseline path" >&2
                exit 3
            fi
            COMPARE_FILE="$1"
            shift
            ;;
        --help|-h)
            sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "error: unknown arg '$1'" >&2
            echo "try $0 --help" >&2
            exit 3
            ;;
    esac
done

if [ ! -x "$NOVA_ROOT/nova" ]; then
    echo "error: NOVA compiler missing at $NOVA_ROOT/nova" >&2
    exit 1
fi

BENCH_FILE="tests/benchmark/bench_nl_verbs.nova"
if [ ! -f "$BENCH_FILE" ]; then
    echo "error: bench file missing: $BENCH_FILE" >&2
    exit 1
fi

# Run the bench; capture stdout+stderr into RAW, strip nova's compile
# line so downstream JSON parsers see clean payload.
RAW="$(mktemp)"
trap 'rm -f "$RAW"' EXIT

if ! "$NOVA_ROOT/nova" run "$BENCH_FILE" >"$RAW" 2>&1; then
    echo "error: bench_nl_verbs.nova failed to run" >&2
    tail -40 "$RAW" >&2
    exit 1
fi

# Strip the "Compiled: ..." line the NOVA runner prints on stdout so
# the JSON payload is clean.
OUT="$(mktemp)"
grep -v '^Compiled:' "$RAW" > "$OUT" || true
trap 'rm -f "$RAW" "$OUT"' EXIT

# Detect graceful-skip.
IS_SKIP=0
if grep -q '^SKIP: nanotime not functional' "$OUT"; then
    IS_SKIP=1
fi

if [ "$IS_SKIP" = "1" ]; then
    # Represent SKIP as a valid crossengin-bench-v1 JSON with empty
    # results so downstream tooling stays uniform.
    SKIP_JSON=$(cat <<'EOF'
{
  "schema": "crossengin-bench-v1",
  "bench": "nl_verb_latency",
  "scale": "SMALL",
  "skip_reason": "nanotime not functional (docs/NOVA_RUNTIME_GAPS.md R-2)",
  "results": []
}
EOF
)
    case "$MODE" in
        stdout)
            echo "$SKIP_JSON"
            ;;
        json)
            mkdir -p "$(dirname "$JSON_PATH")"
            printf '%s\n' "$SKIP_JSON" > "$JSON_PATH"
            echo "wrote SKIP payload to $JSON_PATH"
            ;;
        compare)
            echo "SKIP: nanotime not functional; --compare is a no-op"
            ;;
    esac
    exit 0
fi

# Extract just the JSON braces (the bench prints "=== ..." headers
# before and "bench_nl_verbs complete" after). Everything between the
# first "{" line and the matching "}" line at column 0 IS the payload.
JSON_TXT="$(mktemp)"
awk '/^\{$/{on=1} on{print} /^\}$/{on=0}' "$OUT" > "$JSON_TXT"
if [ ! -s "$JSON_TXT" ]; then
    echo "error: no JSON payload found in bench output" >&2
    tail -20 "$OUT" >&2
    exit 1
fi

case "$MODE" in
    stdout)
        cat "$JSON_TXT"
        ;;
    json)
        mkdir -p "$(dirname "$JSON_PATH")"
        cp "$JSON_TXT" "$JSON_PATH"
        echo "wrote $JSON_PATH"
        ;;
    compare)
        if [ ! -f "$COMPARE_FILE" ]; then
            echo "error: baseline '$COMPARE_FILE' not found" >&2
            exit 3
        fi
        # Empty-baseline handling: if the baseline has zero results,
        # there is nothing to compare -- exit 0 with a message.
        HAS_RESULTS="$(python3 -c "
import json, sys
try:
    b = json.load(open(sys.argv[1]))
    print('1' if b.get('results') else '0')
except Exception:
    print('0')
" "$COMPARE_FILE")"
        if [ "$HAS_RESULTS" = "0" ]; then
            echo "note: baseline '$COMPARE_FILE' has no results -- nothing to compare"
            cat "$JSON_TXT"
            exit 0
        fi
        # Diff current vs baseline. Regression = median_ns > 1.5x.
        python3 -c "
import json, sys

baseline = json.load(open(sys.argv[1]))
current  = json.load(open(sys.argv[2]))

base_by_name = {r['name']: r for r in baseline.get('results', [])}
cur_by_name  = {r['name']: r for r in current.get('results', [])}

print('| bench                          | baseline_ns | current_ns  |   delta% | verdict  |')
print('|--------------------------------|-------------|-------------|----------|----------|')
worst = 0.0
seen = set(base_by_name) | set(cur_by_name)
for name in sorted(seen):
    b = base_by_name.get(name)
    c = cur_by_name.get(name)
    b_ns = b['median_ns'] if b else None
    c_ns = c['median_ns'] if c else None
    if b_ns is None:
        verdict = 'NEW'
        delta = 0.0
    elif c_ns is None:
        verdict = 'MISSING'
        delta = 0.0
    elif b_ns == 0:
        verdict = 'ZERO'
        delta = 0.0
    else:
        delta = (c_ns - b_ns) * 100.0 / b_ns
        if delta > 50:
            verdict = 'REGRESS'
        elif delta > 20:
            verdict = 'SLOWER'
        elif delta < -20:
            verdict = 'FASTER'
        else:
            verdict = 'NOMINAL'
        if delta > worst:
            worst = delta
    b_str = '   --      ' if b_ns is None else f'{b_ns:>11d}'
    c_str = '   --      ' if c_ns is None else f'{c_ns:>11d}'
    d_str = '   --   ' if (b_ns is None or c_ns is None) else f'{delta:>+7.1f}%'
    print(f'| {name:<30} | {b_str} | {c_str} | {d_str} | {verdict:<8} |')

print(f'\\nworst slowdown: {worst:+.1f}%')
if worst > 50:
    sys.exit(2)
" "$COMPARE_FILE" "$JSON_TXT"
        rc=$?
        if [ "$rc" -eq 2 ]; then exit 2; fi
        exit 0
        ;;
esac

exit 0
