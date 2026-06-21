# ADR-0086: Truth-seeking reasoning engine — master architecture and roadmap

## Status

Proposed

## Date

2026-06-15

## Context
ADR-0001 committed CrossEngin to a non-LLM substrate; ADR-0046 scoped v1 as a
single-user desktop companion and ADR-0047 scoped v2 as a single-tenant
enterprise pilot. The product scope has now expanded well beyond that ladder.
The thesis is no longer "a companion that learns" but **a truth-seeking
reasoning engine** that (a) reasons better than LLMs on questions with a
checkable answer, (b) spans many domains — beginning with mathematics, logic,
and computer science and extending to the physical, life, social, and language
sciences, (c) keeps itself current by researching on its own initiative, (d)
scales from a single embedded device to a distributed cluster, and (e) never
fabricates: every claim it emits is traceable to evidence with a stated
confidence. This ADR is the keystone that frames that expansion and indexes the
ADR family implementing it; it does not itself specify mechanisms — each axis
gets its own ADR.

This decision is forced now, not deferrable, because the expansion changes
constraints that ripple back into already-accepted ADRs. Four of those changes
are foundational, were each decided deliberately (see *Options Considered*), and
together define the engine:

1. **Where the whole stack runs.** Rule 1 of this project is *no third-party
   dependencies* — the system is NOVA top to bottom, cognition *and*
   infrastructure. That makes NOVA, not just CrossEngin, responsible for durable
   storage, distributed coordination, and serving. Today CrossEngin persists to
   a text file (`src/persistence/chat_state.nova`; gap noted in ANALYSIS.md) and
   NOVA has transport (the DTLS/ICE/STUN/TURN federation stack) but no storage
   engine or consensus. "Massive scale" is therefore an *earned* property gated
   on NOVA growing real systems infrastructure, not a claim we may assert today.

2. **What "truth" means in the store.** Beyond the source tiers and provenance
   already in ADR-0029 and the Beta beliefs of ADR-0023, every atom must carry
   an **evidence grade** and a **license**, and claims in formally tractable
   domains must carry a **machine-checkable proof reference**. Provenance is the
   floor; formal verification is the ceiling where the domain permits it.

3. **How the engine reasons.** Spreading activation and the reasoning operators
   of ADR-0031 are retained, but the answer path gains a **structured
   argumentation layer** (arguments, attack relations, acceptability semantics)
   adjudicated by the **Bayesian beliefs** of ADR-0023. This hybrid — symbolic
   argument structure over probabilistic confidence — is the mechanism by which
   the engine out-reasons next-token prediction on checkable questions, and it
   produces an argument trace as a first-class, auditable output (ADR-0043).

4. **How it ships and how it handles contested questions.** The product ships in
   **tiered editions** (Edge / Enterprise / Research) over one shared core, and
   in genuinely contested domains it **steelmans every evidenced position** with
   provenance rather than asserting a single truth.

## Decision
We adopt the truth-seeking reasoning engine as the macro-thesis and commit to
the four foundational choices above, each elaborated in a dedicated ADR. This
ADR fixes the family, its numbering, and the order of construction.

**ADR family (this expansion).**

| ADR | Axis | Extends |
|---|---|---|
| 0086 (this) | Master architecture & roadmap | 0001, 0046, 0047 |
| 0087 | Provenance & licensing ledger (per-atom license + evidence grade) | 0016, 0029 |
| 0088 | Formal-verification path for math/logic/CS atoms | 0023, 0031, 0087 |
| 0089 | Argumentation + Bayesian adjudication debate engine | 0023, 0031, 0043 |
| 0090 | Contested-domain steelman policy | 0023, 0029, 0089 |
| 0091 | Tiered editions: Edge / Enterprise / Research | 0046, 0047, 0003 |
| 0092 | Autonomous self-update governance & safety gates | r39, r50, 0089 |
| 0093 | Domain rollout: math / logic / CS first | 0088, 0089 |
| NOVA-0006 | NOVA-as-full-stack infrastructure boundary | NOVA self-hosting line |
| NOVA-0007 | Durable storage engine (WAL + recovery) | NOVA-0006 |
| NOVA-0008 | Distributed consensus (Raft over federation transport) | NOVA-0006 |

**Phased roadmap (each phase lands its own implementation ADRs/rounds).**

- **Phase 0 — Governance.** This ADR, ADR-0087's schema, and the licensing
  ledger. No new code. *(Current phase.)*
- **Phase 1 — Provenance substrate.** Extend the atom layout (ADR-0016) with
  license + evidence grade (ADR-0087); replace the text-file persistence with
  NOVA's storage engine (NOVA-0007).
- **Phase 2 — Debate engine on a verifiable proving ground.** Build the
  argumentation + Bayesian adjudication core (ADR-0089) and the formal path
  (ADR-0088) on math/logic/CS first (ADR-0093), where correctness is objectively
  checkable and the LLM-beating claim can be measured, not asserted.
- **Phase 3 — Domain ontologies & curated ingestion.** Roll domains out in
  slices per ADR-0093, each with provenance and licensing cleared.
- **Phase 4 — Autonomous self-update with governance.** Gate promotion of
  researched claims to facts through the debate engine and safety gates
  (ADR-0092).
- **Phase 5 — Distributed scale.** Consensus (NOVA-0008) and sharded KGs; the
  1M→1B node jump of ADR-0003 becomes a multi-node reality, not a config change.
- **Phase 6 — Tiered editions.** Edge distillation, enterprise multi-tenant,
  research harness (ADR-0091).
- **Phase 7 — Benchmarking & expansion.** Measure reasoning quality against LLMs
  on the verifiable domains; expand domain coverage.

No phase may claim a capability a later phase is responsible for proving; in
particular "massive scale" is not asserted before Phase 5 lands.

## Options Considered
**A. Reasoning core.** *(1) Retain spreading activation + reasoning operators
only* — cheapest, but produces no inspectable argument and no principled
adjudication of competing claims, so it cannot demonstrably beat LLM reasoning
or explain itself. *(2) Wrap an LLM for the hard reasoning steps* — rejected
outright: violates ADR-0014, and an unauditable reasoner cannot be a
truth-seeking engine. *(3) Hybrid argumentation + Bayesian adjudication
(CHOSEN, ADR-0089)* — structured arguments give explainability and a defensible
notion of which conclusions survive; Beta beliefs give calibrated confidence.
The integration is novel and squarely inside the no-LLM line.

**B. Truth model.** *(1) Source tiers only (status quo, ADR-0029)* — good for
empirical claims, but treats a provable theorem like a reputable web page and
carries no license. *(2) Pure formal verification* — rejected: most of the
world's useful knowledge (medicine, economics, current events) is not formally
provable, so a proof-only store would be nearly empty. *(3) Provenance floor +
formal ceiling (CHOSEN, ADR-0087/0088)* — every atom is sourced, graded, and
licensed; formally tractable atoms additionally carry a checkable proof. Matches
the real epistemic shape of knowledge.

**C. Infrastructure.** *(1) NOVA everywhere (CHOSEN, NOVA-0006..0008)* — maximum
novelty, zero dependency, total control; honest cost is that NOVA must build
storage, consensus, and serving the industry took decades to harden, so scale is
deferred behind real engineering. *(2) Borrow a database/consensus library* —
faster, but violates Rule 1 and surrenders the zero-dependency differentiator
that makes the system ownable and auditable end to end. Rejected.

**D. Contested questions.** *(1) Pick the highest-confidence position* — rejected
for value-laden/contested domains: it manufactures false certainty and is the
LLM failure mode we exist to avoid. *(2) Refuse to answer* — unhelpful. *(3)
Steelman every evidenced position with provenance (CHOSEN, ADR-0090)* — extends
the CONTESTED state of ADR-0023 into an output discipline.

## Consequences
- **Positive:** The four axes compose into one coherent, auditable, zero-
  dependency engine whose central claim (better reasoning on checkable
  questions) is *measurable* on the math/logic/CS proving ground; provenance +
  licensing make the knowledge base defensibly clean for commercial use (Rule
  3); the roadmap sequences risk so each layer is real before the next depends
  on it.
- **Negative:** "NOVA everywhere" makes scale a multi-year systems build, not a
  near-term feature; the debate engine and formal path are substantial net-new
  cognition; the surface area (eight CrossEngin ADRs + three NOVA ADRs) is large
  for a small team and must be paced phase by phase.
- **Future work:** Each row of the ADR family is the future work; this ADR is
  revisited only to re-sequence phases or admit a fifth foundational axis.

## Implementation Notes
Phase 0 produces documents only (this ADR, ADR-0087's schema spec at
`docs/design/atom-provenance-schema.md`, the engine overview at
`docs/design/truth-seeking-overview.md`, and the licensing ledger). No NOVA
source changes in Phase 0. Every later phase opens with its ADR(s) in
`docs/adr/`, updates `docs/design/` where the design narrative moves, and
updates the README Status table and `NEXT_SESSION.md` per the contributor model
(ANALYSIS.md §3). Cross-repo: NOVA infrastructure ADRs (NOVA-0006..0008) are
authored in the NOVA repo and referenced here by `NOVA-00xx`; CrossEngin depends
on them landing before Phases 1 (storage) and 5 (consensus).

DEPENDS ON: NOVA-0006 (infrastructure boundary) for Phases 1 and 5.
DEPENDS ON: the existing belief (ADR-0023), provenance (ADR-0029), and
autonomous-research (r50) machinery as the substrate the expansion extends.

## Implementation status

**Phase 7 (down-payment landed): the reasoning benchmark.**
`src/bench/reasoning_bench.nova` measures the central claim instead of asserting
it, on the math/logic proving ground (ADR-0093 slice 1). Rule 1 forbids running
a third-party LLM, so the harness measures the property the claim rests on and
that next-token prediction cannot structurally guarantee: SOUNDNESS ON
CHECKABLE QUESTIONS. A mixed bank of provable theorems (each with a real kernel
proof) and UNPROVABLE claims (no proof / a bogus proof) is run through the
ADR-0088 kernel; the scorecard tallies proven (with machine-checked proofs),
refused (honest abstention), correct vs ground truth, missed (incompleteness --
refused a true theorem, still sound), and the load-bearing FALSE PROOFS count,
which must be 0. The built-in bank (axiom / MP / AND-intro / hypothetical
syllogism / biconditional + two unprovable claims) scores 5 proven, 2 refused,
100% accuracy, 0 false proofs -- SOUND. The `/bench` chat command prints the
scorecard live. Verified via the bootstrap: `reasoning_bench` 27 checks (the
perfect-soundness scorecard; the harness FLAGS a deliberately-mislabeled false
proof and reports UNSOUND, so a kernel regression cannot hide behind a green
bench; incompleteness is scored as missed, never as unsound; empty-bank guards).
The gap an LLM cannot close: on the unprovable items, the engine refuses while a
next-token model answers confidently -- its false-confident rate is bounded by
training, not by a soundness guarantee. Recording actual LLM baselines on a
shared bank (and broadening the bank beyond the seed rules) is the remaining
Phase 7 expansion work.
