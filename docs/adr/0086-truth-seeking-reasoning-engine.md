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
training, not by a soundness guarantee.

**Phase 7 (expanded): the head-to-head comparison harness.**
`reasoning_bench.nova` now scores the SAME bank against a recorded LLM
transcript. Rule 1 forbids the engine running an LLM, so the harness ingests
RECORDED verdicts (captured offline) as data and scores both sides against the
same ground truth, on COMMITMENT: affirm the provable, withhold on the
unprovable. `bench_compare` -> a comparative scorecard [engine correct, engine
false-proofs, LLM correct, LLM false-confident]; `bench_compare_render` leads
with the qualitative gap. The engine's false-proof column is 0 BY CONSTRUCTION
(its errors are abstentions); affirming an unprovable claim is the live failure
mode an LLM has and the engine cannot. The chat exposes `/vs`. The shipped
`bench_default_pairs` is ONE illustrative transcript (clearly labelled --
real captured recordings drop in unchanged); on it the engine scores 11/11 with
0 false proofs while the illustrative LLM scores 8/11 with 3 false-confident
commitments (rounding 7/2 to 3, and committing to two unbacked claims). Verified:
`reasoning_bench` 40 checks (the engine invariant holds over the comparison --
all-correct, zero false proofs, regardless of the LLM column; the harness scores
a controlled 3-item bank's LLM verdicts exactly; the default pairs show the gap).
Broadening the bank beyond the seed rules and capturing REAL LLM transcripts is
the remaining expansion -- the harness is ready for them.

**Epistemic-status capstone (landed): "how do I know this?"**
`src/parts/reasoning/epistemic_status.nova` synthesizes every layer's signal
into ONE calibrated, honest classification per atom: EP_PROVEN (a VERIFIED
ADR-0088 FORMAL proof backs it), EP_CORROBORATED (strong grounded belief),
EP_BELIEVED (a modest grounded lean), EP_CONTESTED (grade frozen by the debate
engine, ADR-0090), EP_REFUTED (grounded evidence against it), or EP_UNKNOWN (no
grounding -- a first-class answer). `epistemic_render` gives the plain-language
"how do I know this?" line (no LLM); `epistemic_is_assertable` gates the answer
path so only PROVEN/CORROBORATED claims may be stated unhedged. Pure synthesis
over existing substrate state (grade + belief + proof status) -- it asserts
nothing new (ADR-0020). A FORMAL grade whose proof has LAPSED is deliberately
NOT reported PROVEN (it falls through to the belief ladder), keeping the pin
conditional on re-checkability. Verified: `epistemic_status` 23 checks (each
tier; the lapsed-proof case; the assertable gate). This is the legible face of
the engine's calibration -- a theorem and a rumor are never reported alike.

**Calibration measurement (landed): are the stated confidences honest?**
`src/bench/calibration.nova` is the complement to the soundness benchmark.
Soundness proves the engine never asserts a FALSE proof; calibration measures
whether its GRADED beliefs are honest -- when it says "0.7", are such claims
true ~70% of the time. Two standard metrics in integer milli: the Brier score
(mean squared error of confidence vs 0/1 outcome) and Expected Calibration
Error (ECE -- the count-weighted gap between each reliability bin's mean
confidence and its actual hit-rate). ECE isolates CALIBRATION from accuracy: an
honestly-uncertain engine (0.5 predictions right half the time) scores ECE ~0
even at 50% accuracy, while systematic overconfidence (0.9 predictions right
only half the time) scores a ~0.4 gap. `cal_from_atoms` draws samples straight
from atom beliefs so calibration can be measured over the engine's real graded
knowledge; `cal_render` reports Brier/ECE/accuracy in plain language (no LLM).
Verified: `calibration` 18 checks (perfect -> Brier/ECE 0; overconfident-wrong
-> Brier/ECE 1000; honest-uncertainty -> Brier 250 but ECE 0; exact Brier
values; ECE catches overconfidence; cal_from_atoms over real beliefs). Together
with the soundness bench this gives the two halves of "truth-seeking, measured":
never wrong on a proof, and honest about everything graded.

**Phase 5 down-payment (landed): the Raft consensus core (NOVA-0008).**
`src/federation/raft_core.nova` is the log-and-term abstraction the Bully
leader-election (leader_election.nova) explicitly defers to "when we need to
order WRITES across the federation". It is the SAFETY core of Raft as a pure
state machine -- term management + step-down, the replicated log, the
RequestVote rule (election safety 5.4.1: one vote per term + reject a
less-up-to-date candidate), the AppendEntries rule (Log Matching: reject on a
prev-entry mismatch, truncate conflicting suffixes, append, advance commit), and
majority commit (rf_majority_index). No networking/timers/snapshots/membership
(that I/O shell is separate mechanism); the invariants that make Raft CORRECT
are here and are unit-tested. Verified: `raft_core` 35 checks (vote granted/
stale-term/one-per-term/stale-log; append basic+heartbeat, stale-leader reject,
log-mismatch reject, conflict truncation, idempotent re-delivery; majority index
incl. the no-majority case; candidate + step-down). This is a Phase 5 building
block -- distributed multi-node scale remains gated on the transport shell + the
sharded-KG work, not asserted by this commit.
