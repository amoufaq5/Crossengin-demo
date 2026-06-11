# ADR-0052: Predictive coding + three-factor learning + Forward-Forward (P2)

## Status

Proposed

## Date

2026-06-11

## Context

The substrate's plasticity (ADR-0007) is a fused two-factor Hebbian + error
rule: a weight moves the instant its pre and post nodes co-fire. That cannot do
**temporal credit assignment** — a reward that arrives a few ticks *after* the
moment that earned it has nothing left to act on — so learning plateaus on any
task where outcome and action are separated in time. ADR-0024 (predictive
coding) is documented but the runtime was thin: error math and a prediction
buffer, with no predictor that actually *improves* and no link to reward. And
the project's design invariant forbids the usual fixes (global backprop, an
offline training run): all learning must be **local, online, gradient-free,
auditable**.

P2 of the enhancement roadmap addresses this with the best-known local
approximations to credit assignment: three-factor / neuromodulated plasticity
with eligibility traces (Frémaux & Gerstner 2016), predictive coding with a
reward-gated loop (Rao & Ballard; Friston), and Forward-Forward (Hinton 2022)
for gradient-free representation learning.

## Decision

Three coordinated additions, each gated so existing behaviour is unchanged.

**1. Three-factor plasticity + STDP asymmetry (`src/substrate/synapse_graph.nova`).**
Split learning into two phases:
- an unsupervised **eligibility** trace deposited by co-firing and decaying over
  time (the existing non-negative `SG_ELIG` trace, now also fed by an
  STDP-shaped deposit), and
- a single broadcast **neuromodulator** scalar that multiplies the trace to move
  the weight: `dw_ij = eta_3f * neuromod * eligibility_ij`.

Because the trace persists, a reward at t+k still credits the synapses that
co-fired at t. New functions: `syn_stdp_kernel`, `syn_coactivate`,
`syn_eligibility_step` (deposit from a per-node fire-tick snapshot), and
`syn_neuromodulate`. The original `syn_learn_one` / `syn_plasticity_step` fused
rule is untouched.

**STDP asymmetry.** The eligibility a pairing deposits depends on spike order:
`syn_stdp_kernel(dt)` with `dt = post_tick - pre_tick` gives a large gain for
causal pairings (pre before post) and a much smaller one for acausal, so under
the same reward an A→B synapse wires forward more strongly than B→A.

**2. Predictive-coding loop (`src/learning/predictive_coding_runtime.nova`).**
Add a gradient-free, delta-rule **adaptive predictor** keyed on a context (e.g. a
signature of the previous moment): each observation nudges the stored estimate
toward what was seen, so on a repeating sequence the error falls toward zero —
the predict→error→learn loop closing locally. Add `pc_neuromod_scalar(reward,
pred_error, surprise)`: the single signed scalar that drives `syn_neuromodulate`,
with reward (from `XSIG_REWARD`, or valence via `emotion_valence_signed`) setting
the sign and surprise / |error| amplifying salience.

**3. Forward-Forward (`src/learning/forward_forward.nova`, new).** A per-layer
**goodness** objective (sum of squared relu activations) trained HIGH on positive
(real) data and LOW on negative (corrupted/imagined) data, via a local Hebbian /
anti-Hebbian update. No gradient crosses a layer boundary — each layer learns
from its own input and goodness only; layers are chained with `ff_forward` +
`ff_normalize` (a forward-only handoff).

## Options Considered

- **Eligibility-trace three-factor rule (CHOSEN).** Standard, biologically
  grounded, and the only one of these that yields delayed credit assignment. The
  trace already existed (for pruning); we reuse it.
- **Immediate `pre*post*neuromod` only (rejected as insufficient).** The roadmap
  lists this form, but without a persisted trace it still requires reward to be
  simultaneous with co-firing — the exact limitation P2 exists to remove. We
  implement the full trace-based rule, of which it is the zero-delay special case.
- **Signed STDP eligibility for active LTD (rejected for now).** A signed trace
  would let "post before pre" actively *weaken* a synapse. But `SG_ELIG` is
  non-negative by contract (the prune/decay logic and snapshot format depend on
  it), so a signed trace means a new parallel array and snapshot-format churn. We
  keep the trace non-negative and realise asymmetry as *reduced potentiation* for
  acausal pairings; the sign of learning comes from the neuromodulator. See
  Honest gaps.
- **Backprop / offline training (rejected).** Violates the design invariant.
- **Full hierarchical predictive coding (deferred).** The delta-rule predictor is
  the minimal closed loop that satisfies the acceptance metric; a multi-level PC
  hierarchy is future work.
- **Forward-Forward with local per-layer gradients (rejected).** A Hebbian /
  anti-Hebbian approximation keeps it gradient-free and integer-friendly while
  preserving FF's defining property (local goodness, no inter-layer gradient).

## Consequences

- **Positive.** Real temporal credit assignment without backprop: measured, a
  reward 5 ticks after a co-firing potentiates the synapse, while the pure-Hebbian
  baseline does nothing. STDP asymmetry is measurable (causal weight ≈ 4× acausal
  under the same reward). The predict→error→reward loop reduces mean prediction
  error by **99%** (1013→9 milli) over 150 ticks on a repeating cycle
  (`bench_predictive_coding`). Forward-Forward separates real from corrupted data
  (every positive scores above every negative; a calibrated threshold classifies
  all samples correctly) with no gradient crossing layers.
- **Negative / costs.** Three learning rates plus an STDP window to tune; the
  neuromodulator combination is a heuristic; bundling/goodness have the usual
  capacity limits. The mechanisms are not yet wired into the live tick loop.

## Honest gaps

- **Asymmetry is reduced-potentiation, not active LTD.** Because eligibility
  stays non-negative, "B then A" simply earns *less* potentiation than "A then
  B"; it is not actively depressed by the timing itself. Active LTD only happens
  when the neuromodulator is negative (punishment), which is global, not
  pair-specific. A signed STDP trace would be more faithful but is deferred (see
  Options).
- **The neuromodulator is hand-tuned, not learned.** `pc_neuromod_scalar` is a
  fixed weighted combination (reward × salience), not a learned reward-prediction
  error with a critic. It is the broadcast third factor the rule needs, not a
  solved RPE.
- **The predictor is Markov-1.** Context is a signature of the *previous* moment,
  so it predicts one step on a first-order-deterministic sequence. Longer-range
  or hierarchical structure needs a richer context (or the deferred PC hierarchy).
- **Forward-Forward goodness can be class-skewed.** One positive class can reach a
  much higher goodness than another (observed P1 ≫ P2); the groups still separate,
  so `ff_calibrate_threshold` uses the min-positive / max-negative midpoint rather
  than the mean-of-means, which a single high-goodness sample would skew.
- **Module path deviates from the roadmap.** The roadmap names
  `src/parts/reasoning/predictive_coding.nova`; the predictive-coding logic already
  lives in `src/learning/predictive_coding_runtime.nova`, so we extended that
  rather than fork a near-duplicate. Substance over path.
- **Not yet wired into the tick loop.** `syn_eligibility_step` /
  `syn_neuromodulate` and the adaptive predictor are mechanisms; the agent loop
  (`tick_driver` / the `src/agent/loop_*` parts) does not yet call them each tick,
  and FF negatives are not yet sourced from `dream_recombination`. Wiring is the
  follow-up (and the natural P4/P5 integration point).

## Implementation Notes

- **Non-breaking.** Every change is additive: new functions in `synapse_graph`
  and `predictive_coding_runtime`, a new `forward_forward` module. `test_synapse_graph`
  (55 checks) and `test_predictive_coding_runtime`'s original cases pass unchanged,
  as do all reverse-dependency suites (resonance, tick_driver, snapshot_synapses,
  plasticity_modulation, output_generation, …).
- **Layering.** The substrate stays free of any reward/emotion dependency:
  `syn_neuromodulate` takes a bare scalar; `pc_neuromod_scalar` (which knows about
  reward/error/surprise) lives in the learning layer; the caller wires
  `appraisal.emotion_valence_signed` → `pc_neuromod_scalar` → `syn_neuromodulate`.
- **NOVA codegen bug #11.** Forward-Forward's deterministic weight init uses the
  overflow-safe `int_mul`/`int_mod`/`int_div` builtins; the milli arithmetic in
  bind/goodness/learn keeps every multiply operand under 0x100000.
- **Tests.** `tests/unit/test_three_factor.nova` (18 checks: STDP kernel, the
  delayed-reward-beats-Hebbian acceptance, asymmetry, punishment, snapshot
  deposit, decay), `test_predictive_coding_runtime.nova` (+adaptive predictor,
  context-keyed prediction, neuromod scalar → 30 checks),
  `test_forward_forward.nova` (8 checks: separation, calibrated classification,
  layer locality, anti-Hebbian), and `tests/benchmark/bench_predictive_coding.nova`
  (the 99% error-reduction acceptance metric).
- **Next (P2 → P4/P5).** Wire the eligibility/neuromodulate pass and the predictor
  into `tick_driver`; source FF negatives from `dream_recombination`; consider a
  signed STDP trace and a learned critic for the neuromodulator.
```
P1 HDC embeddings  ──►  P2 predictive coding + 3-factor  ──►  P3 ingestion/OpenIE
```
