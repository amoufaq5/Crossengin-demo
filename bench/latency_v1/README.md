# `bench/latency_v1/` -- NL-verb latency baseline

R106 / **Phase H** performance gate. Cross-reference: ADR-0208
`docs/adr/adr-0208-latency-and-inference-budget.md`.

## Purpose

This directory holds the baseline JSON that the R106 harness
(`tests/benchmark/bench_nl_verbs.nova` +
`scripts/bench_nl_verbs.sh`) compares against on subsequent rounds.
A per-round regression that pushes any measured phase's `median_ns`
past 1.5x its baseline value fails the check (exit 2). The exit code
maps directly to CI's regression-gate contract; see ADR-0208
"Regression gate".

The bench measures per-phase latency on a synthetic KG at
**SCALE_SMALL** (1000 atoms + 5000 relation atoms + 10 capsules),
built by `tests/benchmark/kg_synthetic_loader.nova`.
`SCALE_MEDIUM` / `SCALE_LARGE` are supported by the loader; the
harness core stays at SMALL so results are comparable across hosts.
`SCALE_LARGE` is gated behind `CROSSENGIN_BENCH_LARGE=1` because 10^5
atoms + 10^6 edges is memory-heavy.

## What the JSON shape looks like

```json
{
  "schema": "crossengin-bench-v1",
  "bench": "nl_verb_latency",
  "scale": "SMALL",
  "results": [
    {"name": "grammar_parse",         "iterations": 1000, "median_ns": ..., "p99_ns": ..., "time_ms": ...},
    {"name": "nl_ic_try_classify",    "iterations": 1000, "median_ns": ..., "p99_ns": ..., "time_ms": ...},
    {"name": "nl_llm_try_fallback",   "iterations": 1000, "median_ns": ..., "p99_ns": ..., "time_ms": ...},
    {"name": "nl_execute_scoped_ex",  "iterations":  100, "median_ns": ..., "p99_ns": ..., "time_ms": ...},
    {"name": "templater_render",      "iterations": 1000, "median_ns": ..., "p99_ns": ..., "time_ms": ...},
    {"name": "rpc_nl_ask_research",   "iterations":  100, "median_ns": ..., "p99_ns": ..., "time_ms": ...},
    {"name": "rpc_nl_ask_relate",     "iterations":  100, "median_ns": ..., "p99_ns": ..., "time_ms": ...},
    {"name": "rpc_nl_ask_contradict_scan", "iterations": 100, "median_ns": ..., "p99_ns": ..., "time_ms": ...},
    {"name": "rpc_nl_ask_is_a",       "iterations":  100, "median_ns": ..., "p99_ns": ..., "time_ms": ...},
    {"name": "rpc_nl_ask_skill_run_echo",  "iterations": 100, "median_ns": ..., "p99_ns": ..., "time_ms": ...}
  ]
}
```

## Capturing a real baseline (permissive host)

The container this repo currently ships in has a broken
`nanotime()` (see `docs/NOVA_RUNTIME_GAPS.md` R-2). On such a host
the harness prints:

```
SKIP: nanotime not functional in this environment
(see docs/NOVA_RUNTIME_GAPS.md R-2; harness graceful-skip)
```

and exits 0. This is the graceful-skip contract -- `make test` is
never broken by a broken-clock host. `baseline.json` shipped in this
directory is an **empty stub** for that reason; capture a real one on
a permissive host and commit it:

```
$ make bench-nl-baseline
$ git add bench/latency_v1/baseline.json
$ git commit -m 'perf(bench): R106 baseline captured on <host>'
```

The stub answer of `--compare` over an empty baseline is a no-op
(exit 0 with a `nothing to compare` note).

## Running the harness

Three Makefile targets wrap the driver script:

```
make bench-nl              # print JSON to stdout (or SKIP)
make bench-nl-compare      # run + diff vs bench/latency_v1/baseline.json
make bench-nl-baseline     # run + overwrite bench/latency_v1/baseline.json
```

Direct-invocation forms:

```
scripts/bench_nl_verbs.sh                       # stdout
scripts/bench_nl_verbs.sh --json out.json       # save
scripts/bench_nl_verbs.sh --compare baseline.json
```

## Regression-gate semantics

`--compare` diffs current-vs-baseline per phase name; verdicts:

- **REGRESS** -- current median_ns > 1.5x baseline. Exit code 2.
- **SLOWER**  -- current median_ns > 1.2x baseline. Warn only.
- **FASTER**  -- current median_ns < 0.8x baseline.
- **NOMINAL** -- within +/- 20%.
- **NEW / MISSING** -- name only on one side of the diff.

A CI wire-up should treat exit 2 as a hard failure; the author
either fixes the regression or bumps the budget in ADR-0208 (with
justification) per the ADR's Regression-gate discipline.

## Broken-nanotime graceful-skip

The harness's very first act inside `main()` is:

```nova
if _bench_nanotime_ok() == 0 {
    println("SKIP: nanotime not functional in this environment")
    ...
    return 0
}
```

`_bench_nanotime_ok` samples `nanotime()` twice; if both come back 0
or the second is <= the first, the runtime clock is treated as
non-monotonic and the harness gracefully exits 0. Same pattern as
`tests/unit/test_ed25519.nova:498-513`. The driver script recognizes
the SKIP line and emits an empty-results JSON payload with a
`skip_reason` field so downstream tooling stays uniform.

## Cross-references

- ADR-0208 `docs/adr/adr-0208-latency-and-inference-budget.md`
  budget table at lines 47-58.
- `docs/NOVA_RUNTIME_GAPS.md` R-2 -- the broken-nanotime record.
- `docs/SHIP_AS_APP.md` sec 7.55 -- R106 log-line.
- `scripts/bench.sh` -- the R25E master-bench harness that inspired
  the `crossengin-bench-v1` JSON schema this harness reuses.
