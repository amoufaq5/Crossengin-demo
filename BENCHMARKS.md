# CrossEngin Benchmarks

This file is the operator-facing summary of the unified benchmark harness
shipped under `scripts/bench.sh`. See the `Building and running` section in
[`README.md`](./README.md#benchmarks) for invocation details. The companion
machine-readable baseline lives at [`bench/baseline.json`](./bench/baseline.json).

## How to run

```sh
# Run every bench, print the JSON report:
scripts/bench.sh                      # default: --json on stdout
scripts/bench.sh --human              # tee per-bench raw output + summary table
scripts/bench.sh --quick              # skip the slow SIMD-production bench

# Regression detection against a stored baseline:
scripts/bench.sh --json > /tmp/now.json
scripts/bench.sh --compare bench/baseline.json    # markdown verdict table

# Discover what would run without executing:
scripts/bench.sh --list
```

Exit codes: 0 on success, 1 if any bench failed, 2 if `--compare` detected
a regression > 50% slower vs the baseline, 3 on a bad invocation.

The harness honours `NOVA_ROOT` (default `$HOME/NOVA`, falls back to
`/home/user/NOVA`). It skips cleanly when the NOVA compiler is missing.

## Current baseline (captured by R25E)

Measured on the R25 sandbox VM. `time_ms` is the median single-run wallclock
of the inner NOVA `nanotime()` measurement; `speedup_x` is reported vs the
in-category scalar reference.

| bench                       | category       | time_ms      | speedup_x | note                                                   |
|-----------------------------|----------------|-------------:|----------:|--------------------------------------------------------|
| `stereo_sad_scalar`         | stereo_sad     |     854.349  |     1.00x | reference scalar implementation (R12A)                 |
| `stereo_sad_i32_simd`       | stereo_sad     |     799.577  |     1.07x | R12A i32 SIMD lane                                     |
| `stereo_sad_u8_simd`        | stereo_sad     |     143.917  |     5.94x | R15A/R17C u8 raw-byte SIMD                             |
| `lk_flow_scalar`            | lk_flow        |      58.051  |     1.00x | reference scalar implementation (R10D)                 |
| `lk_flow_i32_simd`          | lk_flow        |     367.448  |     0.16x | R12A i32 SIMD (slower on the LK kernel -- structural)  |
| `lk_flow_u8_simd`           | lk_flow        |      71.117  |     0.82x | R15A/R17C u8 raw-byte SIMD (packed-scan locality)      |
| `lk_flow_mulacc_simd`       | lk_flow        |      17.309  |     3.35x | R18A.2 byte mul-acc SIMD (closes R17C ceiling)         |
| `image_sad_scalar`          | image_sad      |       0.384  |     1.00x | R17C image-residual scalar reference                   |
| `image_sad_u8_simd`         | image_sad      |       0.004  |   106.65x | R17C image-residual u8 SIMD (full vectorization)       |
| `hog_detector_scalar`       | hog_detector   |     173.158  |     1.00x | R15C HOG sliding window scalar                         |
| `hog_detector_integral`     | hog_detector   |     159.625  |     1.08x | R22A HOG integral-histogram amortization               |
| `nova_sad_scalar_avg`       | nova_simd_sad  |       0.047  |     1.00x | NOVA R11D scalar SAD 1024 i32 lanes (avg / 200 trials) |
| `nova_sad_simd_avg`         | nova_simd_sad  |     0.00033  |   141.54x | NOVA R11D AVX2 `simd_sum_abs_diff`                     |
| `nova_dot_scalar`           | nova_dot_i32   |      39.224  |     1.00x | NOVA R11A int32 dot product scalar                     |
| `nova_dot_simd`             | nova_dot_i32   |       0.870  |    45.09x | NOVA R11A int32 dot product AVX2                       |

(15 entries; see `bench/baseline.json` for the machine-readable form.)

### Headline numbers

* **Stereo SAD u8 SIMD `~5.9x` over scalar** on 256x256, ws=7, max_disp=16.
* **Optical-flow LK mul-acc SIMD `~3.4x` over scalar** on 256x256, ws=5.
* **HOG detector integral histogram `~1.08x` to `~2.15x`** on 256x256 stride 8
  (varies with candidate window count -- R22A's amortization win grows with
  the grid; R22A's original report measured `~2.15x` on a warmer cache).
* **Image-SAD residual u8 SIMD `~107x`** -- the pure-vectorization case.
* **NOVA microbenches** show the AVX2 primitives (`simd_sum_abs_diff`
  `~141x`, int32 dot product `~45x`) over scalar; the realized end-to-end
  wins are lower because they include per-pixel staging + accumulator
  overhead that isn't part of the SIMD primitive itself.

The LK i32 SIMD path's 0.16x is honest: R10D shipped a tight scalar inner
loop, and R12A's i32 SIMD wrapper added per-call setup that dominates on a
single 5x5 window. R15A's u8 raw-byte path closes most of the gap; R18A.2's
mul-acc primitive (NOVA commit db34532) is the structural fix.

## Categories

Benchmarks group into the following categories. New benches should pick a
category from this list (or extend it):

| category        | what it covers                                            |
|-----------------|-----------------------------------------------------------|
| `stereo_sad`    | stereo disparity / SAD block-match (R12A, R15A, R17C)     |
| `lk_flow`       | optical-flow Lucas-Kanade (R10D scalar, R12A/R15A/R18A.2 SIMD) |
| `image_sad`     | per-pixel image residual SAD (R17C scalar vs u8 SIMD)     |
| `hog_detector`  | HOG sliding-window detector (R15C scalar, R22A integral)  |
| `nova_simd_sad` | NOVA R11D AVX2 primitive microbench (1024 i32 lanes)      |
| `nova_dot_i32`  | NOVA R11A int32 dot product (scalar vs AVX2)              |

## Adding a new bench

Two paths:

### 1. Add a NOVA-only bench (recommended for new modules)

Drop a `tests/benchmark/bench_NAME.nova` file. `make benchmark` runs
everything under `tests/benchmark/` automatically. To pull it into the
unified harness, also add a stanza to `scripts/bench.sh`'s NOVA-side
section that runs it and parses its output (look for `parse_nova_simd_sad`
as a model).

The expected `nanotime()`-bracketed print format for the harness's auto-parser:

```
print("  scalar  wallclock (ns): ")
print_int(scalar_ns)
println("")
print("  simd    wallclock (ns): ")
print_int(simd_ns)
println("")
```

The harness recognizes the substrings `scalar  wallclock (ns)`,
`i32SIMD wallclock (ns)`, `u8 SIMD wallclock (ns)`,
`mulacc  wallclock (ns)`, `integral wallclock (ns)`, `image SAD scalar (ns)`,
and `image SAD u8 SIMD (ns)`.

### 2. Add a shell-level bench script

Drop a `scripts/bench_NAME.sh` file that prints lines in the format above
and the harness will pick it up via `scripts/bench_*.sh` globbing. The
existing `scripts/bench_simd_production.sh` is the model.

### 3. Update the baseline

After adding a new bench, regenerate the JSON baseline:

```sh
scripts/bench.sh --json > bench/baseline.json
```

Commit `bench/baseline.json` alongside the bench. CI can then call
`scripts/bench.sh --compare bench/baseline.json` to flag regressions.

## Interpreting `--compare` output

The verdict column reports:

| verdict   | meaning                                          |
|-----------|--------------------------------------------------|
| `FASTER`  | current >20% faster than baseline                |
| `NOMINAL` | within +-20% of baseline (noise floor)           |
| `SLOWER`  | current 20-50% slower than baseline              |
| `REGRESS` | current >50% slower -- exit code 2               |
| `NEW`     | bench in current run but not baseline            |
| `MISSING` | bench in baseline but not current                |
| `ZERO`    | baseline time was 0 ns (below resolution)        |

The `+-20%` band reflects the run-to-run jitter we see on the R25 sandbox VM
(noise floor includes NOVA compile + assembler + link overhead). Tighter
bands need pinned cores + isolated CPU; the harness intentionally does not
gate on that since it's a developer-facing regression hint, not a
publication-grade benchmark.

## Notes on honesty

These numbers are self-reported by the bench programs (via NOVA's
`nanotime()`); the wrapper does NOT re-time anything. The bench programs
run scalar and SIMD paths back-to-back and assert bit-identical output
before reporting wallclocks, so a regression means a real perf drop, not
a correctness change.

The harness does NOT run any of the destructive integration tests, the
network smoke tests, or the federation pipelines; it only measures core
compute kernels. The NOVA-side `tests/benchmark/bench_*.nova` programs
(`bench_tick_rate.nova`, `bench_kg_query.nova`, `bench_node_throughput.nova`,
`bench_ann_query.nova`) take minutes to run because they exercise long
substrate tick loops; the harness does NOT include them by default. Run
`make benchmark` directly for those.
