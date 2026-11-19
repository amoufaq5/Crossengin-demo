# E2 pre-registration: does per-source trust give better-calibrated beliefs?

**Status.** This file was registered before any run on the study datasets
(modes M0–M4, seeds 1–20, 2,000 facts). It is part of the commit that adds the
harness (B6). The study run (B8) uses that commit's code unchanged. Any later
change is listed under "Deviations" in the results' `REPORT.md`.

## 1. Question

CrossEngin keeps one Beta belief per fact and can weight each source's
evidence by trust: a fixed tier, or a learned reliability from the
meta-observer. E2 (audit §8) asks the following, when sources of known but
hidden reliability make conflicting yes/no claims:

1. Does weighting by trust give better-calibrated beliefs than counting every
   claim equally?
2. How does CrossEngin compare with standard truth-discovery methods?

## 2. Data

`e2.py gen` builds each dataset deterministically from (mode, seed).

**Facts and sources.**
- 2,000 facts, each true or false with probability 1/2.
- 10 sources, `s00`–`s09`, with nominal reliabilities spaced evenly from 0.55
  to 0.95.
- Each source claims each fact independently with probability 0.30, which
  gives about 3 claims per fact.
- A claim is the true value with the source's reliability, and the false value
  otherwise.
- The claims are shuffled into an arrival order.

**Modes.**

| Mode | What changes from M0 |
|---|---|
| M0 | nothing: independent errors |
| M1 | copying: on every fact that s00 (the least reliable source) claims, s01 and s02 each claim s00's value with probability 0.8, whether or not they would otherwise have covered the fact; on the other facts they behave as in M0 |
| M2 | a liar: s08 always asserts the false value and covers 60% of facts |
| M3 | sparse experts: s08 and s09 cover 5% of facts; s00–s02 cover 60% |
| M4 | collusion: s05–s07 assert the false value on every fact in a target 20% of facts; elsewhere they are honest |

**Files.** `facts.tsv` holds the truth and is read only for scoring;
`claims.tsv` and `tiers.tsv` are the inputs. The graded arm's tiers come from
the *nominal* reliability: A for 0.85 and above, B for 0.70 and above, C
otherwise. They are not updated for M1–M4: a curator would not know that s08
lies.

**Design.** Five modes × 20 seeds (1–20) = 100 datasets. Every arm sees every
dataset.

## 3. Arms

Each CrossEngin arm runs the production ingest pipeline (`pip_ingest_ex`, B5)
in-process through `e2_driver.nova`.
- Every fact is declared once at 500, a neutral Beta(2500, 2500).
- Every claim is an OBS line of weight 1000, sign +1 for true and −1 for false.
- The flags are `PIP_F_NO_RESEED` and `PIP_F_SIGNED_ATTR`.
- The claims are split into 5 contiguous batches in arrival order.
- A fact's prediction is its belief mean (`atom_confidence`).

| Arm | What it does |
|---|---|
| flat | Every claim at weight 1000. |
| graded | `PIP_F_TIER_WEIGHT`, with the tiers from `tiers.tsv` (A 1000, B 500, C 200). |
| mo | `PIP_F_TIER_WEIGHT`, with weights relearned before each batch from `mo_source_reliability`. |

**How mo sets its weights.**
- Batch 1 uses 1000 for every source.
- Before each later batch, every source gets `w = 1000·(rel − 500)/(best − 500)`, clamped to 0..1000.
- `best` is the highest current reliability estimate.

This mapping was chosen on a development dataset (§7). An absolute mapping,
`(rel − 500)·2`, shrank every weight to about 100–150, because the declaration
prior compresses reliability estimates toward 500.

**Baselines,** computed in Python (`e2.py`) on the same claims:
- **majority:** (true claims + 1) / (claims + 2).
- **dawid_skene:** one-coin Dawid–Skene EM.
  - Prior 0.5; source accuracies start at 0.7.
  - Accuracies are smoothed (agree + 1)/(n + 2) and clipped to [0.01, 0.99].
  - At most 50 iterations.
- **truthfinder:** Yin, Han & Yu (2008) for binary facts.
  - Parameters: t0 = 0.9, γ = 0.3, ρ = 0.5, at most 20 iterations.
  - Output: s(true) / (s(true) + s(false)).

All predictions are integer milli in 0..1000. A fact with no claims gets 500
from every method.

## 4. Outcome

**Primary:** the Brier score over the 2,000 facts, computed exactly as
`src/bench/calibration.nova` computes it, in integer milli. Lower is better.
The Python port is checked against the driver's own `calibration.nova` output
on every CrossEngin run.
- A single mismatch blocks the statistics. `run` writes no `stats.tsv`.
- `stats` refuses such a run.

**Secondary (descriptive):**
- ECE (10 bins, as in `calibration.nova`);
- accuracy (predict true when p ≥ 500);
- for M4, accuracy on the target facts.

## 5. Analysis

Five comparisons, each run in every mode, give 25 tests:

| Comparison | Arm vs comparator |
|---|---|
| C1 | graded vs flat |
| C2 | mo vs flat |
| C3 | mo vs dawid_skene |
| C4 | mo vs majority |
| C5 | mo vs truthfinder |

**Statistic.** For each test, d = Brier(arm) − Brier(comparator) per seed. The
statistic is the mean of d over the 20 seeds. Negative means the arm is better.

**Test.** A paired bootstrap over seeds: 10,000 resamples with a fixed RNG
seed, a 95% percentile CI, and a two-sided p = 2·min(share ≤ 0, share ≥ 0).
The 25 p-values are Holm-adjusted, and a test is significant if its adjusted
p < 0.05.

## 6. Predictions

These are based on the mechanism and on the development runs in §7.

**H1: tier weighting does not help** (graded vs flat).
- It is not significantly better in any mode.
- It is significantly worse in M2, because the liar s08 has nominal tier A.
- Reason: tier weights only ever lower a source's weight (1000, 500, 200), so
  a fact holds less evidence and its belief stays closer to 500.

**H2: the meta-observer helps only against a liar** (mo vs flat).
- Significantly better in M2, where the liar's estimated reliability falls
  below the best source's, so its weight drops.
- Not significantly better in M0, M1 and M3.

**H3: Dawid–Skene beats the meta-observer except under collusion**
(mo vs dawid_skene).
- mo is significantly worse in M0–M3.
- Reason: every CrossEngin arm is under-confident by construction. The
  neutral declaration adds 5 pseudo-observations to about 3 claims, so means
  stay near the middle. Dawid–Skene produces a sharp posterior.
- In M4, mo is significantly better. One-coin Dawid–Skene trusts the
  agreeing colluders and becomes confidently wrong on the target facts. This
  prediction was made after seeing the M4 development run (§7).

**H4 and H5: majority and TruthFinder.** No direction is predicted. Both are
reported.

**Implication if H3 holds.** CrossEngin's source-trust machinery is not a
calibrated truth-discovery method on this task. Improving it would mean
changing the belief model: the declaration prior, and a likelihood-based
source weight. Tuning the meta-observer would not be enough.

## 7. Development runs and disclosure

The harness was tested only on development datasets: seeds 998 and 999, with
150 or 2,000 facts, in modes M0, M2 and M4. These are not study datasets. The
CI smoke test (`scenario_e2_harness.sh`) runs M0, M2 and M4 on seed 999 with
150 facts.

Brier scores on seed 999, 150 facts:

| Mode | flat | graded | mo | majority | dawid_skene | truthfinder |
|---|---|---|---|---|---|---|
| M0 | 183 | 185 | 188 | 158 | 104 | 189 |
| M2 | 221 | 238 | 217 | 217 | 36 | 218 |
| M4 | 222 | 227 | 234 | 216 | 378 | 231 |

M0, seed 998, 2,000 facts: flat Brier 181.

After an adversarial review, and before registration, two things changed:
- M1 was regenerated so that it matches the wording in §2. The copiers used
  to copy only on facts they would have covered anyway.
- H3 was restated for M4 in the light of the table above.

The mo weight mapping (§3) was changed after the first development run, as
described there. No run was made on seeds 1–20 before registration.

## 8. Known threats

- The data are synthetic. Errors are binary flips at a constant rate per
  source, which is the one-coin model Dawid–Skene assumes, so it is favoured.
- The CrossEngin arms share the production belief model, including its
  declaration prior. E2 measures that system as it is, not an ideal Bayesian
  version of it.
- The mo arm's reliability estimate includes the source's own weighted
  evidence (`docs/E2_INGEST.md`), so it can reinforce its own early estimate.

## 9. Outputs

`e2.py run` writes the following:
- `data/<mode>-sNN/`: the dataset, every arm's beliefs, and the mo weights per batch;
- `scores.tsv`;
- `stats.tsv`: the 25 tests;
- `summary.tsv`: mean Brier, ECE and accuracy per mode and arm;
- `manifest.json`: SHA-256 of the driver and the inputs, plus the number of metric cross-check failures, which must be 0.

The B8 run commits these with a `REPORT.md` under `results/<tag>/`.
