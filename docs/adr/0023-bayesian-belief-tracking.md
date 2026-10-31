# ADR-0023: Bayesian belief tracking refinement (alpha/beta per atom, decay, conflict)

## Status

Proposed

## Date

2026-05-25

## Context
Atoms (ADR-0016) carry confidence, and NOVA's `core/belief.nova` already implements Bayesian beliefs as Beta-distribution alpha/beta counts. But raw alpha/beta accumulation is naive for a continuously-learning agent: (1) old evidence should lose weight as the world changes (a medical guideline learned two years ago should not forever dominate a fresh contradicting one — ADR-0029); (2) confidence must be readable as a single number for thresholds (ADR-0030 "learned enough") and for routing decisions; (3) when two sources genuinely conflict, the belief must represent *contested* state rather than silently averaging into false certainty. We must refine `core/belief.nova` for these three needs without abandoning the principled Beta model.

This matters now because beliefs gate behavior across the system: the reader (ADR-0012) routes on confidence, the self-learning triggers (ADR-0026) fire on low confidence or high conflict, source-authority resolution (ADR-0029) feeds weighted evidence here, and the override mechanism (ADR-0044) edits beliefs directly. A weak belief model corrupts all of them. Constraint: 2 founders — the update must be a cheap, closed-form arithmetic step runnable on the 100Hz substrate, not an MCMC sampler.

## Decision
We refine each atom's belief into a **per-atom decaying Beta state with explicit conflict tracking**: `belief = [TAG_BELIEF, alpha, beta, last_update_tick, conflict]`. Confidence (the point estimate) is the Beta mean `alpha / (alpha + beta)`; epistemic certainty is its concentration `alpha + beta` (more evidence => tighter). We expose `belief_confidence`, `belief_strength` (= alpha+beta), and `belief_conflict`.

**Weighted evidence:** evidence is not unit-counted. An evidential signal (ADR-0008) carries a weight derived from source tier (ADR-0029): Tier A `w=1.0`, Tier B `w=0.6`, Tier C `w=0.3`, direct user teaching (ADR-0027) `w=1.5`. Supporting evidence does `alpha += w`; contradicting does `beta += w`.

**Time decay:** before each update we age the counts toward the uniform prior so stale evidence fades: with `tau_belief = 180 days` (in ticks), `decay = exp(-dt / tau_belief)`, then `alpha = 1 + (alpha-1)*decay`, `beta = 1 + (beta-1)*decay` (decaying toward the Beta(1,1) prior, never below it). This makes confidence revisable: a long-unreinforced belief drifts back toward uncertainty rather than ossifying. For atoms tagged "classical/stable" (ADR-0029 oldest-wins domains), `tau_belief = 5 years` so foundational facts barely decay.

**Conflict:** `conflict` is an EWMA of contradiction pressure. On each contradicting update, `conflict = 0.9*conflict + 0.1*(w_contra / (w_contra + w_support_recent))`. When `conflict > 0.4` AND `belief_strength > 8` (i.e. genuinely contested with enough evidence on both sides — not just noisy early data), the atom is flagged CONTESTED: confidence is reported with a contested marker, the atom emits a `SIG_CORRECTION`/curiosity signal to trigger self-learning (ADR-0026), and for hard conflicts the user is flagged (ADR-0029). CONTESTED beliefs are never silently collapsed to a confident mean.

## Options Considered
**1. Decaying weighted Beta with explicit conflict EWMA (CHOSEN).** Keeps the principled, closed-form Beta model (cheap on the tick), makes confidence revisable via decay, honors source authority via weights (ADR-0029), and surfaces genuine disagreement instead of hiding it. Cost: three extra fields and a decay step per update, plus threshold tuning. Chosen because it satisfies all three needs (decay, weighting, conflict) with O(1) arithmetic.

**2. Plain alpha/beta counting, no decay, no weights (status-quo `core/belief.nova`).** Simplest. Rejected: evidence never expires, so the agent cannot revise long-held beliefs as guidelines change (breaks ADR-0029 newest-wins); all sources count equally, so a low-authority web page rivals a Tier-A source; and contradictions just inflate both counts, yielding a falsely confident ~0.5 mean instead of a *contested* flag.

**3. Single scalar confidence with manual nudges.** Store one float per atom, adjust up/down heuristically. Rejected: throws away the distinction between "uncertain because little evidence" (low concentration) and "uncertain because conflicting evidence" (high concentration, split) — a distinction ADR-0026 and ADR-0030 need. It is also unprincipled and hard to calibrate thresholds against.

**4. Full Bayesian network with inter-atom dependencies.** Model joint distributions across related atoms. Rejected for v1: intractable to keep consistent over 1M-node parts at 100Hz with a 2-founder team, and the closed-form per-atom Beta is sufficient for the decisions beliefs gate. Cross-atom influence is instead handled by the substrate (synapses, predictive coding ADR-0024), not by an explicit Bayes net. Revisit post-v2.

## Consequences
- **Positive:** Confidence is principled, cheap, and revisable; source authority (ADR-0029) and user teaching (ADR-0027) flow in as evidence weights; genuine disagreement becomes a first-class CONTESTED state that drives curiosity-based self-learning (ADR-0026) and user-facing conflict flags. The strength (concentration) signal lets ADR-0030 distinguish "needs more evidence" from "settled."
- **Negative:** Several hand-tuned constants (`tau_belief`, weights, conflict threshold 0.4, strength gate 8) need empirical calibration and may differ per domain; per-atom `last_update_tick` adds state to every atom (1M-scale memory cost, mitigated by it being two extra numbers).
- **Future work:** Learned, domain-specific decay/weight schedules; tying conflict resolution into theory-of-mind (ADR-0039) when conflicts stem from different users; richer interaction with predictive-coding error (ADR-0024) so prediction failures also update beliefs.

## Implementation Notes
- Refine `core/belief.nova`: extend layout to `[TAG_BELIEF, alpha, beta, last_update_tick, conflict]`; fns `belief_new`, `belief_update(weight, supports:bool, now_tick)` (does decay-then-update-then-conflict), `belief_confidence`, `belief_strength`, `belief_conflict`, `belief_is_contested`. Decay uses `runtime/math.nova`/`runtime/float.nova` `exp`.
- Evidence weights are set by ADR-0029 source tiers and ADR-0027 user teaching; CONTESTED atoms emit ADR-0008 curiosity/`SIG_CORRECTION` signals consumed by ADR-0026. Override edits (ADR-0044) call `belief_new` to reset counts deliberately.
- Beliefs attach to atoms (ADR-0016); confidence feeds reader routing (ADR-0012) and "learned enough" (ADR-0030).
- Testing: `fixture_belief_decay` (unreinforced belief drifts to ~0.5 over 180d; classical atom barely moves over same span), `fixture_weighted_evidence` (Tier-A vs Tier-C move confidence proportionally), `fixture_conflict` (balanced contradicting Tier-A sources -> CONTESTED flag + emitted curiosity signal, NOT a confident 0.5).
- Dependencies: ADR-0016 (atoms own beliefs), ADR-0008 (evidential/curiosity/correction signals), ADR-0029 (source tiers/weights), ADR-0027 (user teaching weight), ADR-0026 (curiosity trigger), ADR-0030 (thresholds), ADR-0044 (override edits), ADR-0024 (prediction-error updates).
- No new NOVA enhancement strictly required — closed-form arithmetic runs on existing `runtime/math.nova`; benefits from #12 (plasticity kernels) only if belief updates are later batched alongside synapse weights.

## Implementation status

**FORMAL decay exemption (landed, ADR-0088 increment 4).** The time decay this
ADR specifies (an unreinforced belief drifts toward the Beta(1,1) prior) is now
gated by `atom_decay_exempt(a)` (atom_store.nova): a verified FORMAL atom
(ADR-0088) is exempt -- a theorem does not become less true while unobserved.
The per-atom hook a future periodic decay sweep calls is `atom_decay_belief(a,
retain)`, which skips exempt atoms and otherwise applies the standard geometric
step (shared `bel_decay`). The exemption is grade-derived, so the proof
kernel's unpin path automatically re-enables decay when a FORMAL grade is
withdrawn. Verified: `decay_exemption` 13 checks. (The "classical atom barely
moves" fixture intent of this ADR is the same idea, now realised for the
proof-backed grade specifically.)
