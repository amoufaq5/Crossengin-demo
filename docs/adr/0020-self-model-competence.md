# ADR-0020: Self-model competence tracking (what the system knows it can do)

## Status

Proposed

## Date

2026-05-25

## Context
Self-awareness of capability is one of CrossEngin's eight target capabilities (ADR-0049). For initiative, honest interaction, and self-directed learning, the system must maintain an explicit, queryable model of *what it can do and how reliably* — not infer it ad hoc. When a user asks "can you do X?", or when the goal engine considers committing to a long-horizon goal (ADR-0040), or when the curiosity drive looks for gaps to fill (ADR-0026), the answer must come from a maintained self-model rather than guesswork. This is the representational substrate that the self-model query API (ADR-0038) renders into language and that self-learning triggers (ADR-0026) consume.

The decision is needed now, alongside the rest of Group D, because competence is defined over the very structures we have just specified: declarative coverage (atoms/KGs, ADR-0016/017), conceptual grounding (schemas, ADR-0018), and procedural skill reliability (ADR-0019). The self-model is the integrating layer over them. Building it later would mean each consumer (ADR-0026, ADR-0038, ADR-0040) re-deriving competence inconsistently.

Constraints: 2 founders, 8h/day, bootstrap, no-LLM cognition (ADR-0014) — the self-model must be computed from substrate state, never narrated by an LLM. It lives in the meta part and is part of the soul's slow-changing self-knowledge (ADR-0034), persisted in the snapshot (ADR-0048).

## Decision
**A competence registry in the meta part, derived from substrate state.** The self-model is a collection of `competence` records `[TAG_COMPETENCE, domain, kind, grounding, reliability, evidence_count, last_used_moment, gaps]`. Each record summarizes the system's ability in a (domain, kind) cell, where `domain` is a `kg_id` (ADR-0017) and `kind` is declarative (`COMP_KNOW`), procedural (`COMP_DO`, backed by `KG-skills`, ADR-0019), or conceptual (`COMP_UNDERSTAND`, backed by concept schema completeness, ADR-0018). Crucially, competence is **computed, not asserted**: `reliability` aggregates the underlying `core/belief.nova` posteriors (mean atom confidence for `COMP_KNOW`, mean skill reliability for `COMP_DO`, schema-slot fill ratio for `COMP_UNDERSTAND`), and `evidence_count` carries the summed observation counts so the system distinguishes confident competence from thinly-evidenced competence.

**Competence tiers.** From the aggregated posterior mean we derive a tier: `TIER_CAPABLE` (mean ≥ 0.75 and evidence_count ≥ 20), `TIER_PARTIAL` (mean ≥ 0.5), `TIER_AWARE` (the concept/skill exists but mean < 0.5 — "I know of it but can't reliably do it"), and `TIER_UNKNOWN` (no grounding atom/skill at all). The `TIER_UNKNOWN` and `TIER_AWARE` cells are precisely the inputs to the curiosity drive and unknown-query trigger in ADR-0026.

**Recomputation cadence and gap detection.** The registry is refreshed on a slow meta cadence (event-driven, ADR-0037 — not every 100Hz tick) and opportunistically when a relevant atom/skill is updated. `gaps` lists unfilled high-salience concept slots (ADR-0018) and retired/low-reliability skills (ADR-0019) within the cell. A self-model query (ADR-0038) reads a competence record directly; the language rendering flows through pure-substrate output (ADR-0013). The self-model never overstates: if asked about a `TIER_AWARE` domain, the honest answer ("I have some knowledge but low confidence") is generated from the tier and `evidence_count`, supporting calibrated, non-confabulated responses.

## Options Considered
**No explicit self-model; answer capability questions by live-querying the KGs each time.** Rejected: it is expensive to recompute on every question, gives inconsistent answers across the loops (ADR-0036), and provides nothing for the goal engine (ADR-0040) or curiosity drive (ADR-0026) to plan against. A maintained registry is cheap to read and consistent. (We still *derive* it from the KGs, but cache the derivation.)

**Self-assessment via a learned confidence scalar per domain.** Train a single number for "how good am I at medicine". Rejected: it collapses the declarative/procedural/conceptual distinction, hides evidence volume, and cannot point at specific gaps. Aggregating the existing alpha/beta posteriors (ADR-0016/019/023) gives a principled, decomposable tier plus an actionable `gaps` list for free.

**Let an LLM introspect and describe the system's abilities.** Rejected outright: violates ADR-0014. The self-model must be computed from substrate state; the LLM bridge is STT/TTS only (NOVA enhancement #14).

**Bake competence into the soul identity directly (no separate registry).** Rejected: identity (ADR-0034) changes only by deliberate revision and is slow; competence changes continuously as the system learns. Competence is fast-moving self-*knowledge* that the soul references, so it lives in the meta part and is snapshotted with, but kept distinct from, slow identity.

## Consequences
- **Positive:** A consistent, cheap-to-read, decomposable model of capability with honest tiers and explicit gaps. Directly powers self-learning triggers (ADR-0026), the self-model API (ADR-0038), and long-horizon goal feasibility checks (ADR-0040). Enables calibrated, non-confabulated self-description — central to the self-awareness capability test (ADR-0049).
- **Negative:** The aggregation heuristics (how to roll up atom/skill posteriors into a cell, tier thresholds) need calibration during the multi-day test (ADR-0049) and could misreport if the underlying beliefs are skewed. Adds a meta-part recomputation pass and another snapshot section.
- **Future work:** Confidence-calibration validation (does `TIER_CAPABLE` predict actual success?) folded into ADR-0049 benchmarks. Theory-of-mind reuse: an analogous model of the *user's* competence (ADR-0039). Cross-session competence trends feeding goal selection (ADR-0040).

## Implementation Notes
Create a `self_model` module in the meta part over `core/knowledge.nova` (it indexes KGs but is not itself a domain KG). Constructors/accessors: `competence_recompute(domain)`, `competence_tier(domain, kind)`, `competence_gaps(domain)`, `self_model_snapshot()`. Tag constants `TAG_COMPETENCE`, `COMP_KNOW|DO|UNDERSTAND`, `TIER_CAPABLE|PARTIAL|AWARE|UNKNOWN`. Aggregation reads `core/belief.nova` posteriors via `runtime/confidence.nova`, skill reliability from `KG-skills` (ADR-0019), and schema fill ratios from `core/concept.nova` (ADR-0018). Recompute is scheduled on the event-driven layer (ADR-0037), persisted with the soul/meta state early in rehydration order (ADR-0048). Test fixtures: a domain with high-confidence atoms and a reliable skill reports `TIER_CAPABLE` with the correct `evidence_count`; removing the skill drops the `COMP_DO` cell to `TIER_AWARE`; `competence_gaps` returns the unfilled high-salience slot from ADR-0018; a self-model query (ADR-0038) over a `TIER_AWARE` cell yields a calibrated "limited confidence" response with no LLM involvement (ADR-0014). Feeds ADR-0026 (triggers) and ADR-0038 (API) as the authoritative competence source.
