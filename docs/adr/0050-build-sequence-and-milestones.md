# ADR-0050: Build sequence and milestones (12-step ordered plan from substrate kernel through enterprise pilot)

## Status

Proposed

## Date

2026-05-25

## Context
This is the capstone ADR: it sequences everything the other 49 decided into an ordered, buildable plan for 2 founders working 8h/day each on a bootstrap budget over an 18-30 month v1 horizon (plus a v2 enterprise pilot). Without an explicit order the team would thrash — for example, building cognition before the substrate kernel exists, or chasing capability tests before persistence works. The plan must be genuinely actionable: each step has entry conditions, the concrete NOVA modules/ADRs it implements, an exit gate tied to the test regime (ADR-0049), and a rough share of the timeline. It must also respect that the foundation already exists — NOVA provides the 6 base node types, soul, KG, beliefs, goals, safety, imagination, concepts, the 6-loop agent, and is at 129/135 tests passing — so CrossEngin is extending a real codebase, not starting from zero.

The ordering principle is bottom-up dependency: nothing is built before the thing it stands on. Substrate primitives precede the reader; the reader precedes KGs being usefully populated; memory precedes learning loops (you cannot consolidate what you cannot store); cognition precedes the soul governing it; safety wraps cognition before any deployment; persistence is in place before the multi-day test; and the enterprise pilot is last because it is the v1 substrate re-deployed per tenant. Capacity is the hard limit: ~16 founder-hours/day means roughly 2-3 of these steps can be genuinely in flight at once, so the plan front-loads the load-bearing enhancements (#1, #2, #3, #5, #12).

## Decision
Execute the following 12 ordered milestones. Each lists its core ADRs, key NOVA enhancements, the exit gate (ADR-0049 tier), and an approximate timeline slice of the 18-30 month v1 (v2 sits beyond month 30).

**Step 1 — Substrate kernel (months 0-3).** Land the node arenas and sparse synapse fabric and the concurrency/tick spine: NOVA enhancements #1 (pre-allocated 1M-node arenas), #2 (sparse CSR-like adjacency), #3 (true concurrent loops), #5 (100Hz tick). Implements ADR-0001/003/036/037 foundations atop `runtime/persistent_alloc.nova`, `runtime/coroutine.nova`, `runtime/scheduler.nova`. Exit gate: Tier-1 primitive tests for arena allocation, synapse growth/prune, and a stable 100Hz tick under load.

**Step 2 — Core primitives (months 2-5).** Implement the seven CrossEngin primitives on the kernel: node behavior (ADR-0006), synapse plasticity Hebbian + error-driven (ADR-0007, enhancement #12), the 18 signal types (ADR-0008, enhancement #6), gates (ADR-0009, enhancement #7), atoms (ADR-0016), moments (ADR-0021), first nodes (ADR-0010). New constructors `synapse_new`, `gate_new`, `atom_new` over `core/*`. Exit gate: Tier-1 substrate-primitive suite green, including signal-tag fast-dispatch and gate routing.

**Step 3 — Reader (months 4-8).** Build the five-stage hybrid reader (ADR-0011/012): lexical anchor, context bias, spreading activation, coherence check, fetch/route/learn — explicitly not a parser, not an LLM (ADR-0014). Language atoms (ADR-0015) seeded. Exit gate: Tier-2 reader fixtures pass on held-out inputs with correct route/learn decisions.

**Step 4 — Knowledge graphs (months 6-10).** Multi-KG with spawn-on-new-domain and similarity-weighted cross-references (ADR-0004/017, enhancement #8) over `core/knowledge.nova` + `core/similarity.nova`; atom birth/death (ADR-0025); Bayesian confidence (ADR-0023, `core/belief.nova`); concept layer (ADR-0018). Exit gate: Tier-2 KG spawn/cross-ref tests + first Tier-3 domain-QA pass on a seed domain.

**Step 5 — Memory (months 8-12).** Episodic memory storage, decay, consolidation, and idle replay (ADR-0022, enhancement #13) over `mind/memory.nova`; moment lifecycle into episodic (ADR-0021). Exit gate: Tier-2 episodic tests (decay/consolidation/replay) green.

**Step 6 — Learning loops (months 10-15).** Self-directed learning: triggers (ADR-0026), ask-user-to-teach (ADR-0027), whitelisted internet fetch (ADR-0028, enhancement #11), source-authority weighting (ADR-0029), "learned enough" thresholds (ADR-0030). Predictive coding between layers (ADR-0024). Exit gate: capability tests #1 (continuous learning) and #2 (self-directed skill acquisition, with skills KG ADR-0019) pass.

**Step 7 — Cognition (months 13-18).** Reasoning hybrid (ADR-0031, `mind/reasoning.nova`), imagination evolution (ADR-0032, `core/imagination.nova`), goal engine evolution with sub-goal trees (ADR-0033), emotion/OCC appraisal (ADR-0035). Exit gate: capability test #5 (counterfactual) passes; reasoning QA stable.

**Step 8 — Soul (months 16-20).** Soul as wrapper governing cognition (ADR-0034): identity slow, state fast, goals medium, values/constitution/themes/loyalty; theory of mind (ADR-0039); self-model competence (ADR-0020) and self-model query API (ADR-0038); long-horizon goal persistence (ADR-0040). Exit gate: capability tests #3 (theory of mind), #4 (initiative), #7 (self-awareness) pass.

**Step 9 — Safety (months 18-22).** Permission tiers (ADR-0041), reversibility classifier (ADR-0042), append-only decision log (ADR-0043, enhancement #9), override + kill switch (ADR-0044), constitutional hard inhibitory rules (ADR-0045) over `core/safety.nova`. Safety wraps cognition before any ship. Exit gate: Tier-2 safety tests + adversarial constitution/override tests green.

**Step 10 — Persistence + Desktop v1 (months 20-26).** Snapshot + ordered rehydration soul -> KGs -> episodic (ADR-0048, enhancement #10); package the single-process desktop companion (ADR-0046) for x86-64/arm64. Exit gate: the **multi-day companion-quality test** (ADR-0049) passes across real restarts, and capability test #6 (long-horizon goals) and #8 (NO-LLM-COGNITION verification) pass. This is the v1 acceptance milestone.

**Step 11 — Hardening (months 24-30).** Performance (SIMD/GPU batched propagation, enhancement #4, `runtime/simd.nova`/`runtime/gpu.nova`), memory-budget tuning to the ADR-0003 cap, crash-safety soak, snapshot size/incremental work, flaky-capability-test stabilization (ADR-0049 tolerance bands). Exit gate: full suite green to 135/135 NOVA + all CrossEngin tiers; resident set within budget on a 16GB host.

**Step 12 — Enterprise pilot v2 (month 30+).** Extract the matured base-brain snapshot; build the one-tenant-per-process supervisor and base/overlay snapshot split (ADR-0047); enforce the non-negotiable constitution per tenant (ADR-0045). Exit gate: two-tenant isolation test (ADR-0049) proves no cross-tenant leakage; one paying pilot tenant live in a real domain.

## Options Considered
- **Strict bottom-up dependency ordering, 12 milestones (CHOSEN).** Each step stands on a tested floor, so debugging is local and the team is never blocked on an unbuilt dependency. Cost is that visible "intelligence" arrives late (Step 6-8); we accept it because building cognition on an unproven substrate would be far more expensive to unwind.
- **Capability-first / vertical-slice ordering (rejected).** Build one end-to-end capability (e.g., continuous learning) through all layers, then the next. Demos sooner, but it forces repeated half-builds of the substrate, reader, and persistence, and a 2-founder team cannot afford to re-touch the kernel that many times. High rework risk.
- **Parallel workstreams across both founders on independent tracks (rejected as primary).** With only ~16 hours/day total, deep parallelism fragments attention and creates integration debt between, say, the reader and KGs before either is stable. We allow limited overlap (steps share boundary months) but keep a single critical path.
- **Buy/borrow an LLM to bootstrap cognition and replace it later (rejected, principle violation).** Would speed early demos but directly violates ADR-0014 and would contaminate the substrate's learned state with model-shaped dependencies that the no-LLM test (ADR-0049 #8) is designed to forbid.

## Consequences
- **Positive:** A single, ordered critical path that fits 2 founders / 8h-day capacity, with every milestone gated on concrete ADR-0049 tests so "done" is unambiguous. Front-loading enhancements #1/#2/#3/#5/#12 de-risks the hardest substrate work first. v1 (Step 10) and v2 (Step 12) map cleanly onto ADR-0046 and ADR-0047.
- **Negative:** Demonstrable intelligence is back-loaded to ~month 13+; early steps produce infrastructure with little outward magic, which is a morale/funding risk for a bootstrap team. The 18-30mo range is wide because substrate performance (enhancement #4) and capability-test stochasticity are genuine unknowns. Boundary-month overlaps require disciplined integration to avoid the very rework the ordering exists to prevent.
- **Future work:** Federation (ADR-0046 hooks), additional v2 verticals (ADR-0047), incremental snapshots (ADR-0048), and pushing node pools toward the 1B target (ADR-0003) all sit beyond Step 12.

## Implementation Notes
Track milestones as gated phases in the repo (one tracking issue per step, exit gate = the named ADR-0049 tier). Land NOVA enhancements upstream in dependency order: #1, #2, #3, #5 (Step 1) -> #6, #7, #12 (Step 2) -> #8 (Step 4) -> #13 (Step 5) -> #11, #9 (Step 6/9) -> #10 (Step 10) -> #4 (Step 11) -> #14 hardened and asserted continuously from Step 3 onward (DEPENDS ON: NOVA enhancements #1-#14 across the listed steps). Keep the NOVA test runner authoritative: the 129/135 baseline must trend to 135/135 by Step 11, and CrossEngin tiers (ADR-0049) attach to the same runner so one command reports overall health. Do not advance a step until its exit gate is green; allow only the explicit boundary-month overlaps shown above. Each step's primary modules: Step 1 `runtime/*` (alloc/scheduler/coroutine/chan); Step 2 `core/node|signal|channel`; Step 3 reader + `core/concept`; Step 4 `core/knowledge|similarity|belief`; Step 5 `mind/memory`; Step 6 `agent/*` + fetch over `runtime/io|syscall`; Step 7 `mind/reasoning` + `core/imagination|goal`; Step 8 `core/soul` + self-model; Step 9 `core/safety`; Step 10 snapshot over `runtime/db|persistent_alloc` + `pkg/pkg`; Step 11 `runtime/simd|gpu|tensor|blas`; Step 12 supervisor + base/overlay split. Dependencies: this ADR sequences all others; it consumes ADR-0046, ADR-0047, ADR-0048, and ADR-0049 directly as its final gates.
