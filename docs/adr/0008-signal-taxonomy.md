# ADR-0008: Signal taxonomy (18 types)

## Status

Proposed

## Date

2026-05-25

## Context
Signals are the substrate's ephemeral currency: ADR-0002 defines them as typed messages flowing through synapses, and ADR-0003 budgets 1B signals per part at peak. Because nodes are uniform (ADR-0006) and synapses carry "any signal type" (ADR-0007), the SIGNAL TYPE is what tells a node how to treat an incoming message and tells a gate (ADR-0009) how to route it. The taxonomy is therefore load-bearing for the entire substrate, and many later ADRs reference specific types by name — ADR-0024 needs predictive and error, ADR-0045 needs inhibitory and constitutional, ADR-0035 needs valence and arousal, ADR-0026 needs curiosity and goal-drive. We must define the full set precisely and once.

NOVA's `core/signal.nova` provides the base primitive: layout `[TAG, type, moment, origin, destination, priority, trace, metadata]` with eight base types (`SIG_EVENT`, `SIG_QUESTION`, `SIG_ORDER`, `SIG_COMMAND`, `SIG_REQUEST`, `SIG_RESPONSE`, `SIG_CORRECTION`, `SIG_REFLECTION`). These eight are coarse, conversational message kinds — they describe agent-level intents, not substrate dynamics. CrossEngin needs a finer, dynamics-level vocabulary that captures excitation/inhibition, prediction/error, affect, and control. The decision is how many types, what they are, and how they extend the existing tag space without breaking it.

The constraint is dispatch cost. At 1B signals/part the type check sits in the hottest loop in the system, so the type must be a small integer enabling table dispatch, and the 18 types must fit a single dispatch table shared by nodes and gates. We also must not duplicate the eight base types; CrossEngin's 18 are an EXTENSION of the same tag space, not a replacement.

## Decision
We define exactly 18 CrossEngin signal types as an extension of `core/signal.nova`'s tag space (enhancement #6). They occupy a reserved CrossEngin tag range above the eight base `SIG_*` constants and reuse the existing layout — `type` holds one of the 18 `XSIG_*` constants, `priority` holds the per-type priority below, and `metadata` carries type-specific payload (e.g. an error signal's magnitude, a binding signal's group id). Priority is an integer 0 (lowest) to 9 (highest) read by gates for scheduling and by nodes for inbox ordering; constitutional signals are deliberately highest so they cannot be starved.

The 18 types, each with its role and priority/intuition:

1. **excitatory** (`XSIG_EXCITE`, pri 4) — the default carrier; raises the destination node's activation toward firing. The substrate's baseline "push."
2. **inhibitory** (`XSIG_INHIBIT`, pri 6) — lowers/suppresses activation; implements competition, gating-off, and the hard veto path used by constitutional rules. Higher priority than excitatory so suppression wins ties (safety-relevant, ADR-0045).
3. **sensory** (`XSIG_SENSORY`, pri 5) — raw perception entering the substrate at first nodes (ADR-0010) from a moment (ADR-0021). The bottom of the predictive-coding stack (ADR-0024).
4. **predictive** (`XSIG_PREDICT`, pri 5) — a top-down expectation sent from a higher layer to a lower one; what the system thinks it will perceive next (ADR-0024).
5. **error** (`XSIG_ERROR`, pri 7) — bottom-up prediction mismatch (perceived minus predicted). Drives the error term of synapse plasticity (ADR-0007) and triggers self-learning (ADR-0026). High priority — surprises must propagate fast.
6. **causal** (`XSIG_CAUSAL`, pri 4) — asserts a cause→effect relation between activated atoms; substrate-level material for reasoning operators (ADR-0031) and counterfactuals (ADR-0032).
7. **implicative** (`XSIG_IMPLY`, pri 4) — logical/definitional entailment (A implies B) distinct from physical causation; feeds inferential reasoning (ADR-0031).
8. **analogical** (`XSIG_ANALOGY`, pri 3) — signals a structural similarity/mapping between concepts in different KGs; rides cross-KG references (ADR-0017) and supports transfer and imagination (ADR-0032).
9. **evidential** (`XSIG_EVIDENCE`, pri 5) — carries support/confirmation or disconfirmation for an atom's belief, updating its alpha/beta counts (ADR-0016, ADR-0023). Source-tier weighting (ADR-0029) rides here.
10. **attentive** (`XSIG_ATTEND`, pri 6) — a salience/focus boost that biases which parts and nodes are prioritized this tick; raises effective priority of co-located signals. Shapes gate routing (ADR-0009).
11. **binding** (`XSIG_BIND`, pri 5) — temporarily groups co-active atoms into a single bound percept/thought (the binding problem); `metadata` carries a transient group id. Underlies coherent moments (ADR-0021) and reader coherence checks (ADR-0012).
12. **valence** (`XSIG_VALENCE`, pri 4) — affective good/bad appraisal of a moment against goals/values (OCC, ADR-0035); a global modulator of plasticity sign/strength (ADR-0007).
13. **arousal** (`XSIG_AROUSAL`, pri 5) — intensity/activation level of emotional state; scales learning rate `eta` (ADR-0007) and tick urgency (ADR-0035).
14. **curiosity** (`XSIG_CURIOSITY`, pri 3) — an intrinsic novelty/uncertainty drive marking a knowledge gap worth exploring; a self-learning trigger (ADR-0026) sourced from the goal engine's drives (ADR-0033).
15. **goal-drive** (`XSIG_GOAL`, pri 6) — top-down activation from an active goal/sub-goal biasing the substrate toward goal-relevant atoms (ADR-0033, ADR-0040). High priority so goals steer cognition.
16. **reward** (`XSIG_REWARD`, pri 6) — reinforcement (positive or negative) on goal satisfaction or user feedback; consolidates the synapses and atoms that produced the rewarded outcome (ADR-0007, ADR-0022).
17. **recall** (`XSIG_RECALL`, pri 4) — a retrieval cue that reactivates stored atoms/episodes from memory (ADR-0022) and drives spreading activation in the reader (ADR-0012).
18. **constitutional** (`XSIG_CONST`, pri 9) — the highest-priority control signal; carries hard, non-negotiable inhibitory rules from the soul's constitution (ADR-0034) and is implemented as an unconditionable inhibitory veto (ADR-0045). Cannot be overridden, decayed, or pruned away.

## Options Considered
**Keep only NOVA's 8 base `SIG_*` types.** Reuse `SIG_EVENT`/`SIG_QUESTION`/etc. and encode dynamics in `metadata`. Rejected: these are agent-conversation intents, not substrate dynamics; packing excitation, inhibition, prediction, error and affect into metadata strings would put string parsing in the 1B-signal/tick hot loop and lose typed fast-dispatch. The semantics we need (e.g. inhibitory must out-prioritize excitatory) cannot be expressed by eight conversational tags.

**A very large, open-ended type set (40+ fine types).** Maximally expressive — a distinct type per cognitive nuance. Rejected: a 40+ way dispatch table is slower and the distinctions (e.g. ten flavors of error) are better expressed in `metadata` than in the type tag. A bloated taxonomy also raises the maintenance burden for two founders and makes gate routing tables (ADR-0009) explode combinatorially.

**Two-axis encoding (a small base type × a modulator flag) instead of 18 flat types.** E.g. {excite, inhibit} × {predict, recall, ...}. Rejected for v1: the cross-product is harder to route on and many combinations are meaningless (an inhibitory-curiosity signal is ill-defined). A flat, well-chosen set of 18 is simpler to dispatch and to reference precisely from other ADRs, which matters because so many depend on exact names.

**Chosen:** 18 flat `XSIG_*` types extending the base tag space with per-type integer priority. It is expressive enough to cover excitation/inhibition, predictive coding, reasoning relations, affect, drives, and control, yet small enough for a single fast dispatch table, and each type has a stable name other ADRs can cite.

## Consequences
- **Positive:** A precise, shared vocabulary the whole substrate and all downstream ADRs can reference by name. Small-integer types give branchless table dispatch at 1B signals/part (enhancement #6). Per-type priority bakes in safety ordering (constitutional > inhibitory > excitatory) and attention/goal steering. Reuses `core/signal.nova`'s layout untouched, so trace/metadata/moment plumbing is free.
- **Negative:** Eighteen types is a real surface area to implement, route, and test; gates (ADR-0009) must learn routing for all of them. Fixing the set now risks under- or over-fitting future needs — adding a 19th type later means touching the dispatch table and gate tables. Some semantic boundaries (causal vs implicative, valence vs reward) require discipline to keep distinct in practice.
- **Future work:** ADR-0009 builds routing tables keyed on these types; ADR-0024 wires predictive/error into the layer loop; ADR-0035 emits valence/arousal/reward; ADR-0026 consumes curiosity/error; ADR-0045 hardens constitutional/inhibitory. Persistence (ADR-0048) need not store signals (they are ephemeral) but must preserve the type registry.

## Implementation Notes
Extend `core/signal.nova`: add the 18 `XSIG_*` tag constants in a reserved range above the eight `SIG_*` constants, plus a static `xsig_priority[]` table and a `signal_is_constitutional(sig)` predicate used on the safety fast-path. Reuse `signal_new` (set `type` to the `XSIG_*` constant, `priority` from the table, `metadata` for payload such as error magnitude or binding group id). Provide a single `xsig_dispatch(type)` index into the shared node/gate handler table. `DEPENDS ON: NOVA enhancement #6 — extended signal tag space (18+ types) with typed fast-dispatch.`

Testing: `fixture_sig_priority` asserts inhibitory out-orders excitatory and constitutional out-orders everything in a node's inbox; `fixture_sig_roundtrip` verifies each of the 18 types survives `signal_new`→synapse→`node_receive` with metadata intact; `fixture_const_veto` asserts a constitutional signal suppresses a competing excitatory signal regardless of weights (pre-check for ADR-0045). Honors the NO-LLM-COGNITION principle: signal generation is pure substrate, never produced by the LLM bridge. Consumed by ADR-0007, ADR-0009, ADR-0010, ADR-0024, ADR-0026, ADR-0031, ADR-0033, ADR-0035, ADR-0045.
