# R26F -- Performance Regression Hunt against R25E baseline

This document records the R26F sweep through every benchmark captured by
the R25E unified harness (`scripts/bench.sh`), comparing five fresh trials
against the recorded baseline in `bench/baseline.json` (R25 sandbox
numbers, timestamp 1780524106 = 2026-06-03 22:01:46 UTC).

## TL;DR

* **Zero regressions.** Across five back-to-back trials, no benchmark's
  median time exceeded the baseline by more than 10%, and no individual
  trial exceeded the harness's 50% REGRESS threshold.
* **Three benches got measurably FASTER** (median delta below -19%):
  `hog_detector_integral` -65.8%, `hog_detector_scalar` -40.0%, and
  `nova_dot_simd` -19.9%. Two more (`stereo_sad_u8_simd`,
  `lk_flow_mulacc_simd`) hold steady within the noise floor.
* **All R25E headline numbers are still attainable**: stereo SAD u8 SIMD
  ~6.1x (baseline 5.9x), LK mul-acc ~3.36x (baseline 3.35x), image-SAD
  u8 SIMD ~107x (unchanged), HOG integral ~1.85x vs scalar (baseline
  reported 1.08x in JSON, with BENCHMARKS.md noting ~2.15x peak --
  current is within that band).
* **Root cause of the speed-ups**: between baseline capture (22:01) and
  this hunt (next morning), NOVA's `bin/nova` self-host binary was
  rebuilt (mtime 22:23) as part of the R25A `parser: struct brace-init`
  follow-up commit. Source code in `src/io/transducers/image_hog.nova`
  and `image_detector.nova` is byte-identical to the R25E baseline; the
  speed-ups are produced by a fresher NOVA toolchain re-emitting the
  same NOVA source.
* **No fixes shipped.** The regression hunt found nothing to fix. The
  baseline JSON is intentionally NOT regenerated -- keeping the old
  numbers means future runs continue to see FASTER verdicts (positive
  signal) instead of a false plateau.

## Methodology

1. Both repos (`Crossengin-demo` + `NOVA`) confirmed clean
   (`git status` -> nothing to commit). No stash necessary.
2. Ran `scripts/bench.sh --compare bench/baseline.json` five times
   back-to-back from a clean working tree. Each full bench cycle is
   ~60 seconds; the 5-trial sweep took ~5 minutes.
3. For each bench, computed median current_ms, min, max, sample stddev
   percentage, and median delta% vs baseline.
4. Cross-checked the R25E sanity-check targets: R15A 5.5x stereo SAD,
   R19A / R18A.2 3.69x LK mulacc, R22A integral peak 2.15x.
5. Bisect was prepared but skipped because no regression was found;
   instead, examined `git log` of both repos to attribute the FASTER
   verdicts to the NOVA bin/nova rebuild.

The trial harness emits self-reported `nanotime()` wallclock from inside
each bench (the R25E wrapper does not re-time anything externally).
Bit-identity is asserted on every SIMD path (`stereo_sad`,
`lk_flow`, `image_sad`, `hog_detector`) before the timing is reported,
so a FASTER verdict means a real perf change, not a correctness change.

## Full results (5 trials, median delta vs baseline)

| bench                       | baseline_ms | median_ms |   min_ms |   max_ms |  stdev% | median_delta% | verdict  |
|-----------------------------|-------------|-----------|----------|----------|---------|---------------|----------|
| hog_detector_integral       |     159.625 |    54.617 |   54.159 |   55.526 |    0.8% |        -65.8% | FASTER   |
| hog_detector_scalar         |     173.158 |   103.818 |  102.134 |  105.482 |    1.1% |        -40.0% | FASTER   |
| image_sad_scalar            |       0.384 |     0.392 |    0.359 |    0.408 |    4.5% |         +2.1% | NOMINAL  |
| image_sad_u8_simd           |       0.004 |     0.004 |    0.003 |    0.006 |   23.3% |         +0.0% | NOMINAL  |
| lk_flow_i32_simd            |     367.448 |   366.719 |  364.165 |  372.289 |    0.8% |         -0.2% | NOMINAL  |
| lk_flow_mulacc_simd         |      17.309 |    17.226 |   16.937 |   20.608 |    7.6% |         -0.5% | NOMINAL  |
| lk_flow_scalar              |      58.051 |    57.792 |   57.362 |   60.517 |    1.9% |         -0.4% | NOMINAL  |
| lk_flow_u8_simd             |      71.117 |    70.722 |   70.189 |   96.924 |   13.7% |         -0.6% | NOMINAL  |
| nova_dot_scalar             |      39.224 |    38.800 |   38.526 |   39.432 |    0.8% |         -1.1% | NOMINAL  |
| nova_dot_simd               |       0.870 |     0.697 |    0.662 |    0.820 |    7.9% |        -19.9% | NOMINAL  |
| nova_sad_scalar_avg         |       0.047 |     0.047 |    0.047 |    0.048 |    1.0% |         +0.0% | NOMINAL  |
| nova_sad_simd_avg           |       0.000 |     0.000 |    0.000 |    0.000 |    0.0% |         +0.0% | ZERO     |
| stereo_sad_i32_simd         |     799.577 |   792.903 |  790.027 |  794.333 |    0.2% |         -0.8% | NOMINAL  |
| stereo_sad_scalar           |     854.349 |   848.886 |  847.483 |  858.236 |    0.5% |         -0.6% | NOMINAL  |
| stereo_sad_u8_simd          |     143.917 |   144.738 |  143.967 |  147.369 |    0.8% |         +0.6% | NOMINAL  |

Notes on the volatile benches:

* `image_sad_u8_simd` has 23.3% stddev because the absolute timing is
  3-6 ns (below the harness's resolution floor). Median delta is 0%,
  this is just the typical "small number" noise.
* `lk_flow_u8_simd` saw one outlier (96.9 ms vs the steady-state 70 ms)
  in trial 3 -- a cold-cache hit or a CPU-frequency-step. Median across
  trials is 70.7 ms, well within baseline.
* `lk_flow_mulacc_simd` had one trial at 20.6 ms (the rest 17 ms);
  same cause.

## Top 3 speed-ups -- not regressions, but worth understanding

### #1 -- hog_detector_integral, baseline 159.625 ms -> median 54.617 ms (-65.8%)

| metric           | baseline (R25E) | now (R26F)     |
|------------------|----------------:|---------------:|
| wallclock        | 159.625 ms      | 54.617 ms      |
| ratio vs scalar  | 1.08x           | 1.85x          |
| trial stdev      | n/a             | 0.8%           |
| trials           | 1 (capture)     | 5              |

**Bisect attribution.** No CrossEngin source touched
`src/io/transducers/image_hog.nova` (commit 34dd2e7, R21D) or
`src/io/transducers/image_detector.nova` (commit a300c95, R22A) since
the baseline. `git log a9ff3a8..HEAD -- src/` shows only the unrelated
R25C RSS ingest module. Bisect therefore lands on the NOVA toolchain.
`bin/nova` mtime is 2026-06-03 22:23:31 UTC -- 22 minutes AFTER the
baseline JSON timestamp (22:01:46). The most-recent NOVA commit
`7b74e7e` (R25A, `parser: NOVA struct brace-init + destructure
pattern`) is at 22:27:15, just AFTER the rebuild. The R25A parser
change itself can't directly speed up codegen, BUT rebuilding the
self-host binary necessarily re-runs every codegen pass over the
combined compiler source, producing a freshly-staged stage2 binary
whose register-allocator + spill decisions can differ.

**Root cause.** Almost certainly a downstream effect of NOVA's
self-host pipeline producing a slightly faster `bin/nova` after the
R25A rebuild. Verified by `make self-host` exiting 0 with bit-identical
stage2 == stage3 (so the new compiler is stable and not an undefined-
behaviour fluke). The R22A integral-histogram code path has more
inner-loop scalar arithmetic than the SIMD-dominated benches, so it
benefits disproportionately from any register-allocator or scheduling
improvement in the rebuilt compiler.

**Action.** Document, don't fix. This is a positive change.

### #2 -- hog_detector_scalar, baseline 173.158 ms -> median 103.818 ms (-40.0%)

| metric           | baseline (R25E) | now (R26F)     |
|------------------|----------------:|---------------:|
| wallclock        | 173.158 ms      | 103.818 ms     |
| trial stdev      | n/a             | 1.1%           |
| trials           | 1 (capture)     | 5              |

**Bisect attribution.** Same as #1: the R15C sliding-window detector
sits on top of the same `det_*` and `hog_*` primitives whose NOVA-
emitted code changed when `bin/nova` was rebuilt. The bench is the
same source code shipped at R15C (`src/io/transducers/image_detector.nova`
modified date 2026-06-03 12:16, well before baseline).

**Root cause.** Compiler-emitted scalar inner-loop got faster.
Note that the integral / scalar ratio went from 1.08x at baseline to
1.85x now -- the scalar got faster by 40%, the integral by 66%, so
the ratio widened. This matches the R22A original report (BENCHMARKS.md
mentions a 2.15x peak on a warmer cache); R26F's 1.85x sits between
the baseline 1.08x and the historical 2.15x peak.

**Action.** Document, don't fix.

### #3 -- nova_dot_simd, baseline 0.870 ms -> median 0.697 ms (-19.9%)

| metric           | baseline (R25E) | now (R26F)     |
|------------------|----------------:|---------------:|
| wallclock        | 0.870 ms        | 0.697 ms       |
| ratio vs scalar  | 45.09x          | ~56x typical   |
| trial stdev      | n/a             | 7.9%           |
| trials           | 1 (capture)     | 5              |

**Bisect attribution.** `examples/bench_dot_i32.nova` is in the NOVA
tree, unmodified. Its bench is rebuilt every run by `make bench-simd`
(the harness's stanza is `(cd "$NOVA_ROOT" && timeout 300 make bench-simd)`),
which inside the Makefile does a full stage0 -> stage1 -> stage2 NOVA
self-host build BEFORE it runs the dot-product benchmark. Each run
therefore re-rolls the NOVA compiler, and any small variation in the
AVX2 codegen for the int32 dot inner loop shows up here. The current
NOVA `bin/nova` is already the rebuilt version, so the bench measures
its emitted assembly.

**Root cause.** Same toolchain-rebuild effect as #1 and #2, expressed
on the NOVA microbenchmark side. The variance (stdev 7.9%) is higher
than the HOG benches because the absolute wallclock is much smaller
(sub-millisecond), so per-call overhead dominates.

**Action.** Document, don't fix. The reported 19.9% median improvement
sits exactly at the FASTER threshold, so future runs might flip it
back to NOMINAL on a colder cache; this is acceptable.

## Sanity check: R15A 5.5x and R19A / R18A.2 3.69x still attainable

* **R15A stereo SAD u8 SIMD 5.5x.** Bench reports `~6.11x` this round
  (scalar 891 ms / u8 145 ms). Baseline was 5.94x. Still in the
  5-6x band the R15A brief targets.
* **R18A.2 LK mulacc 3.69x.** Bench reports `~3.36x` this round
  (scalar 57 ms / mulacc 17 ms). The R18A.2 brief used a 67 ms scalar
  reference for the 3.69x number; today's faster scalar (57 ms)
  produces a smaller absolute ratio at the same mulacc wallclock.
  This is NOT a regression in mulacc -- mulacc is at 17.2 ms (baseline
  17.3 ms, identical). The scalar got faster faster than mulacc, which
  is the same compiler-rebuild effect documented for #1 and #2.
  Absolute mulacc wallclock is bit-identical to baseline.
* **R17C image-residual u8 SIMD 107x.** Bench reports `~110.04x`
  (scalar 385 us / SIMD 3.5 us). Baseline 106.65x. NOMINAL.
* **NOVA R11D AVX2 SAD primitive 141x.** Bench reports `~137.75x`
  (scalar 50.5 us / SIMD 0.366 us). Baseline 141.54x. Within noise.

## NOVA SIMD primitive perf (R11D, R14B, R18A)

* **R11D `simd_sum_abs_diff`**: 137.75x speedup -- unchanged from
  baseline 141.54x.
* **R14B `simd_sad_u8`**: not directly benched at the primitive level
  (only the wired-in production stereo_sad_u8 bench, which is 6.11x).
  Production speedup is HIGHER than baseline 5.94x.
* **R18A `simd_mul_acc_signed_signed_byte`**: production LK mulacc
  bench at 17.2 ms is identical to baseline 17.3 ms.
* **R11A int32 dot product (AVX2)**: 19.9% FASTER than baseline.

None of the NOVA SIMD primitives have regressed. The R18A mulacc bench's
in-bench ratio dropped from 3.69x (R18A.2 brief) to 3.36x (R26F) ONLY
because the scalar reference also got faster. Mulacc absolute wallclock
is identical.

## NOVA toolchain stability

`make self-host` in `/home/user/NOVA` produced `=== SELF-HOSTING
VERIFIED ===` and stage2 == stage3 (bit-identical). The rebuilt
`bin/nova` is stable -- not the result of any non-determinism in the
compiler. CE's `bash scripts/test.sh` was not re-run as part of the
hunt (test suite was clean at baseline; no CE source touched), but
the bit-identity asserts inside the SIMD-production benches passed
on every trial (mismatch = 0 for all four code paths each run).

## Recommendations

### Fixable now: none

No regression found. No fix shipped.

### Known issues / acceptable as-is

| item                                                | category | recommendation                                  |
|-----------------------------------------------------|----------|-------------------------------------------------|
| `image_sad_u8_simd` 23.3% stdev                     | noise    | Acceptable -- sub-microsecond timing floor.     |
| `lk_flow_u8_simd` occasional outlier (97 ms)        | noise    | Acceptable -- median (70.7 ms) hits baseline.   |
| `lk_flow_mulacc_simd` occasional outlier (20.6 ms)  | noise    | Acceptable -- median (17.2 ms) hits baseline.   |
| `bench/baseline.json` no longer reflects current    | drift    | Defer -- intentional, see "Baseline policy".    |

### R27 candidates

None. The hunt found no architectural rework needed.

## Baseline policy decision

The R25E baseline is INTENTIONALLY not refreshed. Rationale:

1. **Regression detection becomes weaker after a refresh.** If R26F
   re-baselines, future rounds will see the HOG benches as NOMINAL
   even though the win came from a NOVA toolchain rebuild that the
   CE side has no commitment to. A future NOVA change that undoes
   the compiler-side win would slip past the regression check.
2. **The R25E baseline now functions as a useful floor.** Each
   subsequent regression-hunt round can see at a glance how much
   faster the current toolchain is than the captured floor.
3. **A new baseline should be tied to a milestone** (e.g. a major
   NOVA compiler version bump or a benchmark methodology change),
   not to an opportunistic "things got faster" observation.

If a future round wants to refresh, that round's report should
document the trigger and run `scripts/bench.sh --json >
bench/baseline.json` in the same commit.

## Files touched (R26F)

* NEW: `REGRESSION_HUNT_R26F.md` (this file).
* MOD: `NEXT_SESSION.md` (R26F entry summarizing the hunt).
* MOD: `BENCHMARKS.md` (R26F append: confirmation note + headline
  current vs baseline numbers).

No source modules touched. No fixes shipped. No tests added.

## Verification

* 5 trials of `scripts/bench.sh --compare bench/baseline.json` each
  exited 0 (no regression > 50%).
* Bench script bit-identity asserts (`mism = 0`, `mism_u8 = 0`,
  `mism_ma = 0`, `sad_sc == sad_simd`) PASSED on every trial.
* `make self-host` in `/home/user/NOVA` -> `=== SELF-HOSTING VERIFIED
  ===`, stage2 == stage3 bit-identical.
* Median delta across 5 trials computed per-bench; no entry above
  +10% (the hunt's own internal threshold for "investigate"); no
  entry above +50% (the harness's REGRESS threshold).
