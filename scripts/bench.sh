#!/usr/bin/env bash
# R25E -- master benchmark harness.
#
# Single entry point that discovers every `scripts/bench_*.sh` shell harness
# under this repo (and the NOVA-side bench targets), runs them, parses the
# per-bench wallclock + speedup measurements out of their text output, and
# emits a unified JSON report on stdout.
#
# Existing per-bench scripts (R11D ... R22A) remain unchanged. This wrapper
# composes; it does NOT replace them.
#
# Modes:
#   scripts/bench.sh                          -- run all benches, print JSON
#   scripts/bench.sh --human                  -- run all benches, plain text
#   scripts/bench.sh --json > out.json        -- explicit JSON (default)
#   scripts/bench.sh --quick                  -- skip the slow benches
#   scripts/bench.sh --compare baseline.json  -- regression report
#   scripts/bench.sh --baseline > baseline.json
#       (same as --json; alias for capturing the current numbers)
#   scripts/bench.sh --list                   -- list discovered benches
#   scripts/bench.sh --help
#
# JSON shape:
#   {
#     "schema": "crossengin-bench-v1",
#     "timestamp_unix": 1234567890,
#     "host": "...",
#     "nova_root": "...",
#     "benchmarks": [
#       {
#         "name":       "stereo_sad_scalar",
#         "source":     "scripts/bench_simd_production.sh",
#         "category":   "stereo_sad",
#         "time_ns":    857496382,
#         "time_ms":    857.49,
#         "throughput": null,
#         "speedup_x":  null,
#         "baseline":   "scalar"
#       },
#       ...
#     ]
#   }
#
# All measurements come from the per-bench script's own self-reported
# numbers. We deliberately do NOT re-time anything from the outside -- the
# inner NOVA `nanotime()` calls are the source of truth (this script's
# wrapper time would include the NOVA compile cost which is bench-irrelevant).
#
# Regression detection: `--compare baseline.json` parses `baseline.json`,
# re-runs all benches, and prints a markdown-table diff with new vs old
# `time_ms` and a colored verdict (FASTER / SLOWER / NOMINAL within +-20%).
#
# Exit codes:
#   0  success (all benches ran; in --compare mode this includes "no
#      regression beyond +50% slowdown")
#   1  one or more benches failed
#   2  --compare regression detected (any bench > 50% slower)
#   3  bad invocation
#
# Skips cleanly when the NOVA compiler is unavailable.

set -euo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"

NOVA_ROOT="${NOVA_ROOT:-$HOME/NOVA}"
if [ ! -x "$NOVA_ROOT/nova" ] && [ -x "/home/user/NOVA/nova" ]; then
    NOVA_ROOT="/home/user/NOVA"
fi
export NOVA_ROOT

# ----- arg parsing ---------------------------------------------------------

MODE="json"        # json | human | compare | list
COMPARE_FILE=""
QUICK=0

while [ $# -gt 0 ]; do
    case "$1" in
        --human)    MODE="human"; shift;;
        --json)     MODE="json"; shift;;
        --baseline) MODE="json"; shift;;
        --list)     MODE="list"; shift;;
        --quick)    QUICK=1; shift;;
        --compare)
            MODE="compare"
            shift
            if [ $# -eq 0 ]; then
                echo "error: --compare requires a path" >&2
                exit 3
            fi
            COMPARE_FILE="$1"
            shift
            ;;
        --help|-h)
            sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "error: unknown arg '$1'" >&2
            echo "try $0 --help" >&2
            exit 3
            ;;
    esac
done

# ----- bench discovery ------------------------------------------------------

BENCH_SCRIPTS=()
for f in scripts/bench_*.sh; do
    [ -f "$f" ] || continue
    BENCH_SCRIPTS+=("$f")
done

if [ "$MODE" = "list" ]; then
    echo "discovered bench scripts:"
    for f in "${BENCH_SCRIPTS[@]}"; do
        echo "  $f"
    done
    echo ""
    if [ -x "$NOVA_ROOT/nova" ]; then
        echo "NOVA-side benches (driven via make bench-simd-* from $NOVA_ROOT):"
        echo "  make -C $NOVA_ROOT bench-simd       (R11A int32 dot product)"
        echo "  make -C $NOVA_ROOT bench-simd-sad   (R11D SAD AVX2 vs scalar)"
        echo "  make -C $NOVA_ROOT bench-int-safe   (R12C int-safe overflow)"
    else
        echo "NOVA toolchain missing at $NOVA_ROOT -- NOVA-side benches skipped"
    fi
    echo ""
    echo "NOVA tests/benchmark/*.nova (driven via 'make benchmark'):"
    for f in tests/benchmark/bench_*.nova; do
        [ -f "$f" ] || continue
        echo "  $f"
    done
    exit 0
fi

# ----- helpers --------------------------------------------------------------

# Detect NOVA availability up front so we can skip the SIMD-production
# bench cleanly without breaking the JSON output.
NOVA_AVAILABLE=0
if [ -x "$NOVA_ROOT/nova" ]; then
    NOVA_AVAILABLE=1
fi

# json_escape STR -- emit a JSON string literal (without surrounding quotes).
# Handles backslash, double-quote, control characters via python3 fallback.
json_escape() {
    python3 -c 'import json, sys; print(json.dumps(sys.argv[1])[1:-1])' "$1"
}

# Capture output of a command into a tmpfile and tee it for human mode.
run_bench() {
    local script="$1"
    local logfile="$2"
    if [ "$MODE" = "human" ]; then
        if NOVA_ROOT="$NOVA_ROOT" timeout 600 bash "$script" 2>&1 | tee "$logfile"; then
            return 0
        else
            return 1
        fi
    else
        if NOVA_ROOT="$NOVA_ROOT" timeout 600 bash "$script" >"$logfile" 2>&1; then
            return 0
        else
            return 1
        fi
    fi
}

# ----- result accumulator ---------------------------------------------------
# Per-bench measurements are emitted as one line per record:
#   NAME|SOURCE|CATEGORY|TIME_NS|SPEEDUP_X100|BASELINE|NOTE
# (NOTE is freeform; SPEEDUP_X100 = -1 means "not applicable")
# We then transform this into JSON at the end.

RESULTS_TSV="$(mktemp)"
trap 'rm -f "$RESULTS_TSV"' EXIT

emit_result() {
    # name, source, category, time_ns, speedup_x100, baseline, note
    printf '%s|%s|%s|%s|%s|%s|%s\n' \
        "$1" "$2" "$3" "$4" "$5" "$6" "$7" >> "$RESULTS_TSV"
}

# ----- parsers for known bench formats -------------------------------------
#
# The SIMD production bench prints lines like:
#   "  scalar  wallclock (ns):  857496382"
#   "  i32SIMD wallclock (ns):  805233052"
#   "  u8 SIMD wallclock (ns):  148588737"
#   "  i32 SIMD speedup vs scalar: ~1.06x"
#
# We extract the ns figures into the JSON.

parse_simd_production() {
    local log="$1"
    local source_name="scripts/bench_simd_production.sh"
    local section="" line key val

    while IFS= read -r line; do
        case "$line" in
            *"R12A stereo SAD benchmark"*)        section="stereo_sad";;
            *"R12A/R17C optical-flow LK"*)        section="lk_flow";;
            *"R22A HOG detector integral"*)       section="hog_detector";;
        esac

        case "$line" in
            *"scalar  wallclock (ns):"*)
                val="$(echo "$line" | awk '{print $NF}')"
                emit_result "${section}_scalar" "$source_name" "$section" \
                    "$val" "100" "scalar" "reference scalar implementation"
                ;;
            *"i32SIMD wallclock (ns):"*)
                val="$(echo "$line" | awk '{print $NF}')"
                emit_result "${section}_i32_simd" "$source_name" "$section" \
                    "$val" "-1" "scalar" "R12A i32 SIMD lane"
                ;;
            *"u8 SIMD wallclock (ns):"*)
                val="$(echo "$line" | awk '{print $NF}')"
                emit_result "${section}_u8_simd" "$source_name" "$section" \
                    "$val" "-1" "scalar" "R15A/R17C u8 raw-byte SIMD"
                ;;
            *"mulacc  wallclock (ns):"*)
                val="$(echo "$line" | awk '{print $NF}')"
                emit_result "${section}_mulacc_simd" "$source_name" "$section" \
                    "$val" "-1" "scalar" "R18A.2 byte mul-acc SIMD"
                ;;
            *"image SAD scalar (ns):"*)
                val="$(echo "$line" | awk '{print $NF}')"
                emit_result "image_sad_scalar" "$source_name" "image_sad" \
                    "$val" "100" "scalar" "R17C image-residual scalar"
                ;;
            *"image SAD u8 SIMD (ns):"*)
                val="$(echo "$line" | awk '{print $NF}')"
                emit_result "image_sad_u8_simd" "$source_name" "image_sad" \
                    "$val" "-1" "scalar" "R17C image-residual u8 SIMD"
                ;;
            *"integral wallclock (ns):"*)
                val="$(echo "$line" | awk '{print $NF}')"
                emit_result "hog_detector_integral" "$source_name" "hog_detector" \
                    "$val" "-1" "scalar" "R22A HOG integral-histogram"
                ;;
        esac
    done < "$log"
}

# NOVA-side R11D SAD microbench (1024 i32 lanes).
parse_nova_simd_sad() {
    local log="$1"
    local source_name="$NOVA_ROOT/tests/bench_simd.sh"
    local val

    val="$(grep '^  scalar avg (ns):' "$log" 2>/dev/null | awk '{print $NF}' | head -1)"
    if [ -n "$val" ]; then
        emit_result "nova_sad_scalar_avg" "$source_name" "nova_simd_sad" \
            "$val" "100" "scalar" "NOVA R11D scalar 1024 i32 lanes (avg of 200 trials)"
    fi
    val="$(grep '^  SIMD   avg (ns):' "$log" 2>/dev/null | awk '{print $NF}' | head -1)"
    if [ -n "$val" ]; then
        emit_result "nova_sad_simd_avg" "$source_name" "nova_simd_sad" \
            "$val" "-1" "scalar" "NOVA R11D AVX2 simd_sum_abs_diff (avg of 200 trials)"
    fi
}

# NOVA-side R11A int32 dot product bench.
parse_nova_dot_i32() {
    local log="$1"
    local source_name="$NOVA_ROOT/examples/bench_dot_i32.nova"
    local val

    # The bench prints lines like "scalar (ns): N" / "SIMD (ns): N";
    # tolerate variations in spacing.
    val="$(grep -i 'scalar.*(ns)' "$log" 2>/dev/null | head -1 | awk '{print $NF}')"
    if [ -n "$val" ]; then
        emit_result "nova_dot_scalar" "$source_name" "nova_dot_i32" \
            "$val" "100" "scalar" "NOVA R11A int32 dot product scalar"
    fi
    val="$(grep -i 'simd.*(ns)' "$log" 2>/dev/null | head -1 | awk '{print $NF}')"
    if [ -n "$val" ]; then
        emit_result "nova_dot_simd" "$source_name" "nova_dot_i32" \
            "$val" "-1" "scalar" "NOVA R11A int32 dot product SIMD"
    fi
}

# ----- main runner ----------------------------------------------------------

HOST="$(hostname 2>/dev/null || echo unknown)"
TS="$(date +%s)"

if [ "$MODE" = "human" ]; then
    echo "=== CrossEngin master benchmark harness ==="
    echo "  host:      $HOST"
    echo "  timestamp: $TS"
    echo "  NOVA root: $NOVA_ROOT (available: $NOVA_AVAILABLE)"
    echo "  quick:     $QUICK"
    echo ""
fi

ANY_FAILED=0

# 1. CrossEngin shell benches.
if [ "$NOVA_AVAILABLE" = "0" ]; then
    if [ "$MODE" = "human" ]; then
        echo "(skip: NOVA compiler missing at $NOVA_ROOT/nova)"
    fi
else
    for script in "${BENCH_SCRIPTS[@]}"; do
        local_name="$(basename "$script" .sh)"
        if [ "$QUICK" = "1" ] && [ "$local_name" = "bench_simd_production" ]; then
            # the production bench runs the full LK+stereo+detector trio, ~50s
            if [ "$MODE" = "human" ]; then
                echo "skip $script (--quick)"
            fi
            continue
        fi
        log="$(mktemp)"
        if [ "$MODE" = "human" ]; then
            echo "--- running $script ---"
        fi
        if run_bench "$script" "$log"; then
            case "$local_name" in
                bench_simd_production) parse_simd_production "$log";;
                *)  # generic fallback -- look for "wallclock (ns)" pairs
                    parse_simd_production "$log"
                    ;;
            esac
        else
            ANY_FAILED=1
            emit_result "${local_name}_FAIL" "$script" "failed" "0" "-1" "scalar" \
                "bench exited non-zero -- see logs"
            if [ "$MODE" = "human" ]; then
                echo "FAIL: $script"
                tail -20 "$log"
            fi
        fi
        rm -f "$log"
    done
fi

# 2. NOVA-side microbenches (driven via tests/bench_simd.sh).
if [ "$QUICK" != "1" ] && [ -x "$NOVA_ROOT/nova" ] && [ -f "$NOVA_ROOT/tests/bench_simd.sh" ]; then
    log="$(mktemp)"
    if [ "$MODE" = "human" ]; then
        echo "--- running NOVA R11D SAD microbench ---"
    fi
    if (cd "$NOVA_ROOT" && timeout 300 bash tests/bench_simd.sh) > "$log" 2>&1; then
        if [ "$MODE" = "human" ]; then
            cat "$log"
        fi
        parse_nova_simd_sad "$log"
    else
        ANY_FAILED=1
        if [ "$MODE" = "human" ]; then
            echo "FAIL: NOVA bench_simd.sh"
            tail -20 "$log"
        fi
    fi
    rm -f "$log"
fi

# 3. NOVA bench-simd (int32 dot product) -- driven via `make bench-simd`.
if [ "$QUICK" != "1" ] && [ -x "$NOVA_ROOT/nova" ] && [ -f "$NOVA_ROOT/examples/bench_dot_i32.nova" ]; then
    log="$(mktemp)"
    if [ "$MODE" = "human" ]; then
        echo "--- running NOVA R11A int32 dot bench ---"
    fi
    # The Makefile target does build + assemble + link + run.
    if (cd "$NOVA_ROOT" && timeout 300 make bench-simd) > "$log" 2>&1; then
        if [ "$MODE" = "human" ]; then
            cat "$log"
        fi
        parse_nova_dot_i32 "$log"
    else
        # NOVA bench-simd is optional -- a build failure here is a warn,
        # not a fatal regression.
        if [ "$MODE" = "human" ]; then
            echo "WARN: NOVA bench-simd (int32 dot) failed"
            tail -10 "$log"
        fi
    fi
    rm -f "$log"
fi

# ----- emit final report ----------------------------------------------------

count=$(wc -l < "$RESULTS_TSV" | awk '{print $1}')

if [ "$MODE" = "human" ]; then
    echo ""
    echo "=== bench summary: $count entries ==="
    # Portable column-align via awk (column is not always available).
    if [ "$count" -gt 0 ]; then
        printf '%-30s %-30s %-16s %-14s %-10s %-10s %s\n' \
            "NAME" "SOURCE" "CATEGORY" "TIME_NS" "SPEEDUPx100" "BASELINE" "NOTE"
        awk -F'|' '{ printf "%-30s %-30s %-16s %-14s %-10s %-10s %s\n", $1, $2, $3, $4, $5, $6, $7 }' "$RESULTS_TSV"
    fi
    if [ "$ANY_FAILED" = "1" ]; then
        echo ""
        echo "WARNING: at least one bench failed -- see entries with category=failed"
        exit 1
    fi
    exit 0
fi

# JSON emission.
emit_json() {
    python3 -c "
import json, sys, time

records = []
with open(sys.argv[1]) as f:
    for line in f:
        line = line.rstrip('\n')
        if not line:
            continue
        parts = line.split('|')
        if len(parts) < 7:
            continue
        name, source, category, time_ns, speedup_x100, baseline, note = parts[:7]
        try:
            t_ns = int(time_ns)
        except Exception:
            t_ns = 0
        try:
            sp_x100 = int(speedup_x100)
        except Exception:
            sp_x100 = -1
        rec = {
            'name': name,
            'source': source,
            'category': category,
            'time_ns': t_ns,
            'time_ms': round(t_ns / 1_000_000.0, 3),
            'throughput': None,
            'speedup_x100': sp_x100 if sp_x100 != -1 else None,
            'baseline': baseline,
            'note': note,
        }
        records.append(rec)

# Second pass: compute speedup vs baseline within each category.
by_cat = {}
for r in records:
    by_cat.setdefault(r['category'], []).append(r)

for cat, rs in by_cat.items():
    base = None
    for r in rs:
        if r['baseline'] == 'scalar' and r['speedup_x100'] == 100:
            base = r
            break
    if base is None or base['time_ns'] == 0:
        continue
    for r in rs:
        if r is base:
            r['speedup_x100'] = 100
            continue
        if r['time_ns'] == 0:
            continue
        r['speedup_x100'] = int(round(base['time_ns'] * 100.0 / r['time_ns']))

out = {
    'schema': 'crossengin-bench-v1',
    'timestamp_unix': int(time.time()),
    'host': sys.argv[2],
    'nova_root': sys.argv[3],
    'nova_available': sys.argv[4] == '1',
    'benchmarks': records,
}
print(json.dumps(out, indent=2))
" "$RESULTS_TSV" "$HOST" "$NOVA_ROOT" "$NOVA_AVAILABLE"
}

if [ "$MODE" = "json" ]; then
    emit_json
    if [ "$ANY_FAILED" = "1" ]; then
        exit 1
    fi
    exit 0
fi

# ----- --compare mode ------------------------------------------------------

if [ "$MODE" = "compare" ]; then
    if [ ! -f "$COMPARE_FILE" ]; then
        echo "error: baseline '$COMPARE_FILE' not found" >&2
        exit 3
    fi
    CURRENT_JSON="$(emit_json)"
    # Use `set +e` for the python3 call so we can capture the regression
    # text AND the python exit code separately. `set -e` would abort the
    # whole script the moment the python interpreter exits non-zero.
    REGRESSION_OUT="$(mktemp)"
    set +e
    python3 -c "
import json, sys

baseline = json.load(open(sys.argv[1]))
current  = json.loads(sys.argv[2])

base_by_name = {b['name']: b for b in baseline.get('benchmarks', [])}
cur_by_name  = {b['name']: b for b in current.get('benchmarks', [])}

print('| bench                       | baseline_ms | current_ms |   delta% | verdict  |')
print('|-----------------------------|-------------|------------|----------|----------|')
worst = 0
seen = set(base_by_name) | set(cur_by_name)
for name in sorted(seen):
    b = base_by_name.get(name)
    c = cur_by_name.get(name)
    b_ms = b['time_ms'] if b else None
    c_ms = c['time_ms'] if c else None
    if b_ms is None:
        verdict = 'NEW'
        delta = 0.0
    elif c_ms is None:
        verdict = 'MISSING'
        delta = 0.0
    elif b_ms == 0:
        verdict = 'ZERO'
        delta = 0.0
    else:
        delta = (c_ms - b_ms) * 100.0 / b_ms
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
    b_str = '   --     ' if b_ms is None else f'{b_ms:>10.3f}'
    c_str = '   --     ' if c_ms is None else f'{c_ms:>10.3f}'
    d_str = '   --   ' if (b_ms is None or c_ms is None) else f'{delta:>+7.1f}%'
    print(f'| {name:<27} | {b_str} | {c_str} | {d_str} | {verdict:<8} |')

print(f'\\nworst slowdown: {worst:+.1f}%')
if worst > 50:
    sys.exit(2)
" "$COMPARE_FILE" "$CURRENT_JSON" > "$REGRESSION_OUT"
    REGRESSION_RC=$?
    set -e
    cat "$REGRESSION_OUT"
    rm -f "$REGRESSION_OUT"
    if [ "$REGRESSION_RC" -eq 2 ]; then
        exit 2
    fi
    exit 0
fi

exit 0
