# CrossEngin Architecture Decision Records — Substrate Architecture

Status: Proposed · Date: 2026-05-24

CrossEngin is a non-LLM cognitive substrate system implemented in the [NOVA](https://github.com/amoufaq5/nova) language. This document records the 50 architecture decisions that define the substrate: a fabric of uniform computational **nodes** connected by weighted **synapses**, along which typed **signals** flow, **gated** and routed to specialized **parts**, producing and reading mutable **atoms** in domain **knowledge graphs**. Intelligence is intended to emerge from substrate dynamics — co-firing, plasticity, spreading activation, prediction and error correction — rather than from an orchestrator calling cognitive modules in sequence (ADR-001).

A first principle runs through the whole set: **no LLM participates in cognition** (ADR-014). The NOVA LLM bridge is reserved for STT/TTS modality conversion only; reasoning, knowledge retrieval, and output generation are pure substrate.

Every ADR uses the same template — **Context**, **Decision**, **Options Considered**, **Consequences** (Positive / Negative / Future work), and **Implementation Notes** — and is grounded in the real NOVA codebase (`core/`, `mind/`, `agent/`, `runtime/`). Where an ADR depends on a NOVA language or runtime capability that does not yet exist, the Implementation Notes carry a `DEPENDS ON: NOVA enhancement #N` flag; those enhancements are tracked and submitted upstream to the NOVA repository. All 50 decisions are currently **Proposed** and awaiting ratification.

> **Relationship to the v0 ADRs.** This substrate-architecture set (ADR-001…ADR-050) is distinct from the earlier per-file Michael-Nygard ADRs (`0001`–`0023`) in this same directory. Those captured a v0 design that explicitly chose a Python/PyTorch stack over NOVA; this set records the NOVA-first substrate direction. Where the two conflict, this set reflects the current architectural intent and supersedes the corresponding v0 decisions.

## Index

**Group A — Foundation**
- ADR-001 — Substrate architecture vs modular workflow
- ADR-002 — Seven core primitives (node/synapse/signal/atom/moment/gate/KG)
- ADR-003 — Scaling plan (1M v1 → 1B target, sparse connectivity, growth strategy)
- ADR-004 — Multi-KG organization by domain with cross-references
- ADR-005 — NOVA as implementation language with required enhancements

**Group B — Computation substrate**
- ADR-006 — Node design (uniform behavior, sparse connectivity, atom production)
- ADR-007 — Synapse design (Hebbian + error-driven plasticity, growth, pruning)
- ADR-008 — Signal taxonomy (18 types)
- ADR-009 — Gate design (learned routing, signal-content-based, broadcast support)
- ADR-010 — First nodes (specialized sensory input receivers per part)

**Group C — Reader and language**
- ADR-011 — Reader: Option 5 hybrid (substrate + predictive components)
- ADR-012 — Reader five stages (lexical anchor, context bias, spreading activation, coherence check, fetch/route/learn)
- ADR-013 — Output generation: pure substrate, no LLM
- ADR-014 — No-LLM cognition principle (LLM-bridge only for STT/TTS modality)
- ADR-015 — Language atoms in substrate (words, phonemes, syntax patterns as atoms)

**Group D — Knowledge representation**
- ADR-016 — Atom design (mutable, KG-stored, cross-KG referenced, Bayesian confidence)
- ADR-017 — Multi-KG with cross-references (spawn-on-new-domain, similarity-weighted cross-refs, automatic and earned link formation)
- ADR-018 — Concept layer evolution (hierarchy, schemas, multi-vector embeddings, integration with multi-KG)
- ADR-019 — Procedural memory and KG-skills (skills as procedural rules + skills KG)
- ADR-020 — Self-model competence tracking (what the system knows it can do)

**Group E — Memory and learning**
- ADR-021 — Moments (timestamped perception, lifecycle, episodic integration)
- ADR-022 — Episodic memory (storage, decay, consolidation, replay during idle)
- ADR-023 — Bayesian belief tracking refinement (α/β per atom, decay, conflict)
- ADR-024 — Predictive coding between layers (top-down predictions, bottom-up errors)
- ADR-025 — Atom birth and death (co-activation pattern → new atom; decay-based GC)

**Group F — Self-directed learning**
- ADR-026 — Self-learning triggers (unknown query, curiosity drive, imagination gap, prediction error, user request, all combined)
- ADR-027 — Ask-user-to-teach mechanism (when, how, integration with response flow)
- ADR-028 — Internet fetching design (whitelist, rate limiting, validation, audit, cache)
- ADR-029 — Source authority weighting and conflict resolution (Tier A/B/C sources, newest-wins for guidelines, oldest-wins for classical, flag hard conflicts)
- ADR-030 — Confidence thresholds for "learned enough" (test questions, multi-source agreement, user confirmation, all three)

**Group G — Cognitive subsystems**
- ADR-031 — Reasoning (hybrid: substrate atoms for inferential operators + module functions for complex multi-step strategies)
- ADR-032 — Imagination subsystem evolution (current 10 patterns → learn new patterns from experience; forward/counterfactual/dream/scenarios)
- ADR-033 — Goal engine evolution (existing 4 drives + long-horizon persistence + sub-goal trees + cross-session continuity)
- ADR-034 — Soul as wrapper (identity slow, state fast, goals medium, values, constitution, themes, loyalty)
- ADR-035 — Emotion system (OCC appraisal of moments against goals/values, OCEAN personality conditioning, emotion-modulated plasticity)

**Group H — Agent architecture**
- ADR-036 — Six concurrent loops + imagination idle loop (true concurrency, fiber or process, communication channels)
- ADR-037 — Scheduler (hybrid: 100Hz substrate tick layered on event-driven coord)
- ADR-038 — Self-model query API (system can describe self/state/goals in language)
- ADR-039 — Theory of mind in concept layer (user-as-concept with rich properties, updates from observation, used for empathy and anticipation)
- ADR-040 — Long-horizon goal persistence (multi-day/multi-week goals surviving process restarts, intermittent attention)

**Group I — Safety and audit**
- ADR-041 — Permission tiers (auto / notify / approve based on action class)
- ADR-042 — Reversibility classifier (per-action-type lookup, default irreversible)
- ADR-043 — Decision log (append-only, full trace per action, user-inspectable)
- ADR-044 — Override mechanism (belief edit, goal veto, hard stop, kill switch)
- ADR-045 — Constitutional rules (hard inhibitory signals, enterprise vs user loyalty resolution)

**Group J — Operations and milestones**
- ADR-046 — Deployment v1 (personal desktop, single user, single device, federation-ready)
- ADR-047 — Deployment v2 (enterprise pilot, one tenant per process, base brain + tenant-specific learning)
- ADR-048 — Persistence (which state survives restart, snapshot format, rehydration order — soul first, then KGs, then episodic)
- ADR-049 — Testing and benchmarks (multi-day companion-quality test, domain-specific QA, the 8 capability tests)
- ADR-050 — Build sequence and milestones (12-step ordered plan from substrate kernel through enterprise pilot)

---

# ADR-001: Substrate architecture vs modular workflow

Status: Proposed
Date: 2026-05-24

## Context
CrossEngin targets AGI-relevant capabilities — continuous learning, self-directed skill acquisition, theory of mind, initiative, counterfactual reasoning, long-horizon goals, and self-awareness of identity and state over time. The single most consequential architectural choice is the macro-shape of the system: is intelligence produced by a *pipeline of cognitive modules* (perceive -> parse -> retrieve -> reason -> plan -> act, each a callable component), or by the *dynamics of a computational fabric* in which many uniform units exchange typed messages and capability emerges from learned connection structure? Every later ADR inherits this choice; it cannot be deferred.

The constraints are real and shape the answer. We are 2 founders at 8h/day each, bootstrapping with no outside funding, on an 18-30 month v1 timeline. v1 ships as a personal desktop companion (single user, single device); v2 is a single-tenant enterprise pilot. We are not building on an LLM — the NO-LLM-COGNITION principle (ADR-014) forbids using any language model as cognition. That removes the usual shortcut of wrapping orchestration logic around a frozen model, and forces the architecture itself to carry the learning and reasoning.

A modular workflow is far easier to build, test, and debug with a small team: each module has a signature, a unit test, and a clear owner. But a fixed pipeline bakes in a fixed processing order and a fixed division of labor. The capabilities we want are precisely the ones that resist being decomposed into a static call graph — initiative and continuous learning are *cross-cutting* and *always-on*, not stages you visit once per request.

## Decision
CrossEngin is a **substrate**, not a modular workflow. The system is a fabric of uniform computational units — **nodes** — connected by persistent weighted **synapses**, along which ephemeral typed **signals** flow, **gated** and routed to specialized regions. Nodes are organized into **parts** (perception, KG-medicine, KG-[domain], episodic, soul, reasoning, imagination, action, meta), each holding 1M nodes in v1. Intelligence is an emergent property of substrate dynamics — co-firing, plasticity, spreading activation, prediction and error correction — rather than the output of an orchestrator calling modules in sequence.

Concretely: there is no top-level controller that decides "now reason, now retrieve." Instead, perception produces **moments**, gates route the resulting signals to parts, activation spreads across synapses, atoms are read and written in domain KGs, and output emerges from concept-activation patterns flowing down to motor effectors (ADR-013). Six genuinely concurrent loops (ADR-036) and a background imagination loop run continuously over the same substrate, tick-driven at ~100Hz (ADR-037) and layered on event-driven coordination. "Modules" survive only as *substrate-adjacent helpers* for genuinely algorithmic work (e.g. multi-step reasoning strategies in `mind/reasoning.nova`, ADR-031) — they read and write the substrate, they do not orchestrate it.

## Options Considered
**1. Pure modular workflow (rejected).** A classic cognitive pipeline of typed components with explicit control flow. *Pros:* cheapest to build for 2 people; trivially unit-testable; deterministic and debuggable; maps cleanly onto NOVA's existing `mind/` modules. *Cons:* the request-response, fixed-order shape is hostile to always-on initiative, continuous background learning, and emergent cross-domain association. New capabilities require new modules and new wiring rather than new learned structure. Self-awareness of state-over-time has nowhere natural to live. Rejected because it optimizes for our short-term ease at the direct expense of the long-term capability thesis.

**2. Pure substrate (CHOSEN).** Uniform nodes + synapses + signals + gates + multi-KG; emergence from dynamics. *Pros:* directly fits the AGI goals — learning *is* plasticity, initiative *is* a continuously-running loop, cross-domain reasoning *is* spreading activation across cross-KG references (ADR-004). One mechanism (the substrate) generalizes instead of N bespoke modules. *Cons:* much harder to debug ("why did this signal fire?"), demands heavy NOVA runtime enhancements (#1-#5, #12) that do not yet exist, and risks the substrate failing to produce useful behavior at all. We accept these by mandating the decision log (ADR-043) and signal traces as first-class observability.

**3. Hybrid orchestrated substrate (considered, partially adopted).** Small substrate islands wrapped and sequenced by a workflow controller. *Pros:* a pragmatic middle path; keeps an escape hatch to imperative code. *Cons:* the orchestrator re-imposes fixed processing order and becomes the true locus of intelligence, demoting the substrate to a subroutine — quietly collapsing back into option 1. We rejected it *as the macro-architecture* but retained its useful kernel: algorithmic helpers (ADR-031) may be called *from within* substrate dynamics without ever sitting above them.

## Consequences
- **Positive:** A single uniform mechanism underlies all cognition, so capabilities compound rather than being re-implemented per feature; continuous learning, initiative, and cross-domain association become structural rather than bolted-on; the design is honestly aligned with the AGI thesis and the NO-LLM principle (ADR-014).
- **Negative:** Debuggability drops sharply versus a pipeline — we trade step-through clarity for emergent behavior; we take on substantial NOVA runtime risk (enhancements #1-#5, #12); there is genuine uncertainty that emergence yields useful behavior on the v1 timeline, and a 2-founder team has thin margin for that risk.
- **Future work:** Defines the seven primitives (ADR-002), the scaling plan (ADR-003), multi-KG organization (ADR-004), and the NOVA enhancement program (ADR-005). Forces investment in observability (ADR-043) and a careful build sequence (ADR-050) that proves substrate viability early.

## Implementation Notes
The substrate is assembled in `core/system.nova` from the seven primitives of ADR-002, built on NOVA's existing `core/node.nova`, `core/channel.nova`, `core/signal.nova`, `core/moment.nova`, and `core/knowledge.nova`. Parts are node collections allocated up-front; signal paths use `core/path.nova`. The concurrent loops (ADR-036) communicate over `runtime/chan.nova`; ticking is driven by `runtime/scheduler.nova` (ADR-037). Observability is non-negotiable: every signal carries a `trace` (visited-node list) per `core/signal.nova`, and decisions append to the log of ADR-043.

DEPENDS ON: NOVA enhancement #1 — pre-allocated fixed-capacity node arenas (1M+ nodes/part).
DEPENDS ON: NOVA enhancement #3 — true concurrent execution units for the 6 loops (current scheduling is cooperative).
DEPENDS ON: NOVA enhancement #5 — 100Hz deterministic tick scheduler fused with event-driven coordination.

Testing strategy: a "substrate-liveness" fixture that boots one part, injects a `SIG_EVENT`, and asserts measurable spreading activation and a written atom — the earliest go/no-go gate in the build sequence (ADR-050), validated under the capability tests of ADR-049.

---

# ADR-002: Seven core primitives (node/synapse/signal/atom/moment/gate/KG)

Status: Proposed
Date: 2026-05-24

## Context
ADR-001 commits CrossEngin to a substrate. A substrate is only as coherent as its vocabulary of primitives. Before designing any subsystem, we must fix the *minimal closed set* of first-class concepts from which everything else is composed, define each precisely, and map each onto a concrete NOVA primitive so that engineers build on real code rather than metaphor. Getting this set right is load-bearing: every ADR from ADR-006 onward elaborates exactly one of these primitives, and ambiguity here propagates everywhere.

NOVA already supplies most of the raw material: `core/node.nova` (6 node types, inbox/outbox), `core/signal.nova` (8 base signal types, priority, trace, metadata), `core/channel.nova` (4 channel types including filtered/weighted), `core/moment.nova` (timestamped perception), `core/knowledge.nova` (KG with embeddings), and `core/belief.nova` (Bayesian alpha/beta). The task is to *select, name, and constrain* seven primitives over this base — adding the two genuinely new ones (synapse, gate) and the persistent data unit (atom) and KG-organization concept that the substrate needs.

The team constraint (2 founders, 8h/day, bootstrapping) argues for *exactly seven* primitives — enough to express the architecture, few enough that two people can hold the whole model in their heads and reuse one mechanism instead of inventing many.

## Decision
CrossEngin is built from **seven core primitives**, each first-class and each mapped to a NOVA primitive:

1. **NODE** — where computation happens. Uniform behavior across all nodes; specialization comes from learned *state*, not type (ADR-006). Pre-allocated at startup, 1M per part (ADR-003), sparse ~1000 synapses each. Maps to `core/node.nova` `[TAG, name, type, state, inbox, outbox, config]`; the 6 NOVA node types (`NTYPE_PERCEIVER`...`NTYPE_ACTOR`) become *bias hints*, not behavioral switches.
2. **SYNAPSE** — persistent weighted connection between nodes (and nodes-to-parts). Carries any signal type; weight learned via Hebbian + error-driven plasticity; grows and prunes with experience (ADR-007). New primitive `synapse_new` built atop `core/channel.nova` (`CHAN_WEIGHTED`).
3. **SIGNAL** — ephemeral typed message flowing through synapses. CrossEngin defines 18 types (ADR-008) extending the 8 base tags in `core/signal.nova`, preserving its `priority`/`trace`/`metadata` layout.
4. **ATOM** — persistent, mutable data unit produced by nodes only for *novel* patterns; stored in a domain KG; cross-KG referenced; carries Bayesian confidence (ADR-016). New `atom_new` over `core/knowledge.nova` + `core/belief.nova`.
5. **MOMENT** — timestamped perception record; the entry point for external input; lives in episodic memory after processing (ADR-021). Maps directly to `core/moment.nova`.
6. **GATE** — learned, content-based routing checkpoint between signals and nodes; can broadcast to multiple parts (ADR-009). New `gate_new` over `core/channel.nova` (`CHAN_FILTERED`/`CHAN_BROADCAST`).
7. **KG (multi)** — domain-organized knowledge store, one per domain, spawned on new-domain detection, linked by similarity-weighted cross-references (ADR-004, ADR-017). Namespaced `core/knowledge.nova` + `core/similarity.nova`.

**Composition:** a moment enters perception's first nodes (ADR-010); nodes emit signals; gates route signals across synapses to parts; nodes read/write atoms in KGs; output emerges from concept-activated nodes (ADR-013). Higher constructs — soul, concepts, episodic memory, reasoning — are *organizations of these seven*, never new primitive kinds.

## Options Considered
**1. Seven primitives as above (CHOSEN).** *Pros:* minimal closed set; each maps to an existing or thin-new NOVA primitive; two founders can fully internalize it; clean 1:1 correspondence with ADRs 006-009/016/021. *Cons:* "node" carries heavy uniform-behavior assumptions (ADR-006) that must hold; "atom vs concept" boundary needs the discipline of ADR-018. Chosen because it is the smallest vocabulary that still expresses the full substrate.

**2. Fewer primitives — fold synapse into node, gate into signal-routing (rejected).** Treat connections as node-internal adjacency and routing as a signal field on `core/channel.nova`. *Pros:* fewer concepts, less new NOVA code. *Cons:* synapse plasticity (ADR-007) and learned gate routing (ADR-009) are *central* mechanisms with their own lifecycles, weights, and tests; hiding them inside nodes/signals makes them unaddressable as first-class objects and cripples observability. Rejected — under-modeling the two things that actually learn.

**3. More primitives — promote concept, soul, episode, drive to primitive status (rejected).** *Pros:* every major noun gets first-class type support and dedicated tests. *Cons:* explodes the vocabulary to a dozen-plus types, duplicates NOVA's existing `core/concept.nova`/`core/soul.nova`/`core/goal.nova`, and contradicts ADR-001's thesis that complexity should *emerge from* a small substrate, not be enumerated. Two founders cannot maintain that surface area. Rejected — these are compositions, not primitives.

## Consequences
- **Positive:** A small, closed, NOVA-grounded vocabulary that every later ADR reuses; one mechanism per concern; uniform nodes mean specialization scales without new types (ADR-003); clean mapping minimizes new NOVA code.
- **Negative:** Two genuinely new primitives (synapse, gate) require runtime enhancements (#2, #7) that do not yet exist; the node/atom/concept boundaries demand ongoing discipline; collapsing NOVA's 6 node types into bias-hints discards type-based dispatch we could otherwise lean on.
- **Future work:** Each primitive gets a dedicated ADR — node (ADR-006), synapse (ADR-007), signal taxonomy (ADR-008), gate (ADR-009), atom (ADR-016), moment (ADR-021), multi-KG (ADR-017). First nodes (ADR-010) specialize the node entry points; the reader (ADR-011/012) operates over all seven.

## Implementation Notes
Constructors and accessors follow NOVA idiom (tag-prefixed lists/maps): `node_new`/`node_receive`/`node_emit`/`node_get_state` already exist in `core/node.nova`; add `synapse_new`, `synapse_weight`, `synapse_strengthen`, `synapse_prune`; `gate_new`, `gate_route`, `gate_broadcast`; `atom_new`, `atom_update`, `atom_confidence`, `atom_xref`. Define tag constants `TAG_SYNAPSE`, `TAG_GATE`, `TAG_ATOM`. Synapses use a sparse adjacency structure (#2); atoms namespace into per-domain KGs (#8). Signal tags extend `core/signal.nova` (#6).

DEPENDS ON: NOVA enhancement #2 — sparse synapse adjacency with O(1) weight update/growth/pruning.
DEPENDS ON: NOVA enhancement #6 — extended 18-type signal tag space with typed fast-dispatch.
DEPENDS ON: NOVA enhancement #7 — learned content-based gate routing tables.
DEPENDS ON: NOVA enhancement #8 — multi-KG namespacing + cross-KG reference edges.

Testing: a primitive-conformance fixture per type (construct, mutate, serialize, rehydrate) plus a composition test that walks a moment -> signal -> gate -> synapse -> node -> atom round trip, anchoring ADR-050's earliest milestones.

---

# ADR-003: Scaling plan (1M v1 -> 1B target, sparse connectivity, growth strategy)

Status: Proposed
Date: 2026-05-24

## Context
ADR-001 and ADR-002 commit us to a substrate of uniform nodes connected by synapses. That immediately raises the hardest engineering question in the project: *how many* nodes and synapses, allocated *how*, and *growing how* — on hardware we can actually afford? The answer must satisfy two seemingly opposed forces. v1 must run on a single consumer desktop as a personal companion (ADR-046); the long-term thesis needs a substrate large enough for rich emergent capability. We therefore commit to **1M nodes per part in v1** with a **1B-node-per-part long-term target**, and we must show the v1 number fits in a desktop memory budget.

The forces to state: 2 founders, 8h/day, bootstrapping (no budget for GPU clusters or server farms); v1 on commodity hardware (assume a 32-64 GB desktop); the substrate runs ~100Hz (ADR-037) with up to 1B signals per part at peak throughput. Crucially, ADR-006 mandates *uniform node behavior* and *sparse connectivity* (~1000 synapses/node initially) — both of which are what make the memory math survivable.

A naive dense substrate is fatal: 1M nodes with all-to-all connectivity is 10^12 synapses *per part* — impossible on a desktop and unnecessary, since real associative structure is sparse. The plan must instead exploit sparsity hard, pre-allocate to avoid runtime fragmentation, and grow capability primarily by *adding and reweighting synapses* before ever expanding the node pool.

## Decision
We adopt a **two-axis scaling plan**: a fixed node-pool axis and an elastic synapse axis, with growth driven primarily by synapses.

**Node axis (pre-allocated, fixed per generation).** Each part pre-allocates its full node arena at startup — 1M nodes in v1 — in one contiguous fixed-capacity region (#1). No runtime node allocation; nodes are *recruited* from the idle pool by learned state, not malloc'd. This makes the working set predictable and crash-safe to snapshot (ADR-048). The 1B target is a *future generation*, reached by enlarging the arena on capable hardware (v2+), not by per-request growth.

**Synapse axis (sparse, elastic).** Connectivity starts at ~1000 synapses/node and grows with experience, pruning weak connections (ADR-007). Synapses live in a CSR-like sparse adjacency (#2), giving O(1) weight update, growth append, and prune. This is the primary growth mechanism: the substrate gets *smarter* mainly by re-wiring and reweighting, only secondarily by recruiting idle nodes.

**v1 desktop memory budget (per part).** 1M nodes x ~1000 synapses = 10^9 synapse slots/part. At a packed 12 bytes/synapse (≈4B weight + ≈4B target index + ≈4B metadata/plasticity trace) that is ~12 GB of synapse adjacency per part. Node records (state map, inbox/outbox handles) at ~256 B/node add ~256 MB/part. We therefore run **a small number of active parts simultaneously per desktop process** (not all nine at full density at once): the perception/reasoning/episodic/soul working set fits comfortably in 32-64 GB, while domain KGs page their cold atoms to `runtime/db.nova`. Signal objects are *ephemeral* and pooled — the "1B signals/part" figure is peak *throughput* across a tick window, not 1B resident objects.

## Options Considered
**1. Pre-allocated fixed pool + sparse elastic synapses (CHOSEN).** *Pros:* predictable memory, no fragmentation, trivially snapshot-able (ADR-048), and the synapse-first growth model matches biological and associative reality; the 12 GB/part math fits a desktop. *Cons:* the node ceiling per generation is hard — if 1M nodes/part proves too few for a capability, we cannot grow nodes without a generation bump and re-snapshot. Chosen because predictability and desktop-fit dominate for a 2-founder v1.

**2. Fully dynamic allocation — grow nodes and synapses on demand (rejected).** *Pros:* no arbitrary ceiling; the substrate sizes itself to the workload. *Cons:* runtime allocation under a 100Hz tick causes fragmentation and GC pauses that wreck determinism; memory becomes unbounded and unpredictable on a fixed desktop; snapshots become hard. Rejected as incompatible with ADR-037's tick guarantees and ADR-046's fixed budget.

**3. Dense connectivity at smaller node counts (rejected).** Trade node count for all-to-all richness — e.g. 50K dense nodes/part. *Pros:* simpler adjacency (a matrix), trivially SIMD/GPU-batched (#4). *Cons:* 50K dense = 2.5x10^9 synapses for *one tenth* the spreading-activation reach, and dense matrices waste >99% of capacity on connections that never carry useful signal; it also caps the associative fan-out that cross-domain reasoning (ADR-004) needs. Rejected — sparsity buys far more useful structure per byte.

## Consequences
- **Positive:** Fits a commodity desktop (ADR-046); deterministic memory enables 100Hz ticking (ADR-037) and clean snapshots (ADR-048); synapse-first growth gives continuous learning a natural substrate; sparse representation scales reach without quadratic cost.
- **Negative:** Hard per-generation node ceiling; the 1M->1B jump is a discontinuous re-architecture (sharding, possibly multi-process/multi-device), not a config change; sparse adjacency plus 100Hz propagation makes SIMD/GPU batching (#4) essential, not optional.
- **Future work:** The 1B target requires partitioning parts across processes/devices (federation-ready v1, ADR-046; tenant-per-process v2, ADR-047). Plasticity kernels (ADR-007, #12) and batched propagation (#4) must be benchmarked under ADR-049's multi-day test before committing to denser generations.

## Implementation Notes
Node arenas extend `runtime/persistent_alloc.nova` + `runtime/alloc.nova`; the sparse synapse store is a new CSR-like structure over `runtime/mem.nova`. Per-tick propagation batches over synapse weight arrays via `runtime/simd.nova`/`runtime/tensor.nova`/`runtime/blas.nova`, with `runtime/gpu.nova` as the scale path. Cold atoms page to `runtime/db.nova`. Snapshot/rehydration follows ADR-048 ordering (soul -> KGs -> episodic).

DEPENDS ON: NOVA enhancement #1 — pre-allocated fixed-capacity node arenas (1M+/part, target 1B).
DEPENDS ON: NOVA enhancement #2 — sparse synapse adjacency (CSR-like) with O(1) update/growth/prune.
DEPENDS ON: NOVA enhancement #4 — SIMD/GPU batched signal propagation across millions of synapses/tick.
DEPENDS ON: NOVA enhancement #12 — Hebbian + error-driven plasticity kernels over synapse weight arrays.

Testing: a memory-budget fixture asserting per-part resident bytes stay under target on a 32 GB box; a propagation-throughput benchmark (synapses/tick) feeding ADR-049; a growth/prune test verifying synapse count converges rather than diverging.

---

# ADR-004: Multi-KG organization by domain with cross-references

Status: Proposed
Date: 2026-05-24

## Context
CrossEngin must accumulate durable knowledge across many domains — medicine, law, the user's life, language itself — and reason *across* them (a drug interaction informed by the user's diet; a legal concept anchored to a medical fact). ADR-002 fixes **atoms** as the persistent knowledge unit and **KG** as their store. The decision here is the *organization* of that knowledge: one monolithic graph for everything, or many domain-scoped graphs linked by cross-references. Because atoms are produced continuously by nodes (ADR-006) and the system learns new domains over its lifetime (ADR-026 self-learning), this structure must support *growth of new domains at runtime*, not just a fixed schema.

NOVA provides `core/knowledge.nova` (KG with embeddings) and `core/similarity.nova` (vector similarity). The constraints: a desktop v1 (ADR-046) where most domains are *cold* most of the time and should not consume hot memory; a 2-founder team that cannot hand-curate domain boundaries; and v2 enterprise (ADR-047) where a tenant's private domain knowledge must be isolatable from the shared base brain. These forces all push toward *separable, independently-loadable* knowledge stores.

A single global KG is simplest to query (no cross-store joins) but couples everything: it cannot page cold domains out, cannot isolate a tenant's data, grows one giant index whose embedding search degrades as it fills with unrelated atoms, and offers no natural unit for the spawn-on-new-domain behavior the system needs.

## Decision
Knowledge is organized as **multiple domain-scoped KGs, one per domain**, linked by **similarity-weighted cross-KG references**. Each KG (e.g. `kg-medicine`, `kg-law`, `kg-user`, `kg-language` per ADR-015) is an independently namespaced `core/knowledge.nova` store with its own atom set, embedding index, and Bayesian beliefs (ADR-016, `core/belief.nova`). Atoms are addressed as `(kg_id, atom_id)`; an atom in one KG references related atoms in others via cross-reference edges weighted by `core/similarity.nova` cosine similarity (#8).

**Spawn-on-new-domain.** The system starts with a small seed set of KGs and *spawns a new KG automatically* when it detects a coherent cluster of atoms that is poorly served by existing domains — operationally, when a run of incoming atoms shows high mutual similarity but low maximum similarity (below a tier threshold) to every existing KG centroid. The new KG is created via `kg_spawn`, seeded with the cluster, and given a centroid for future routing. The detailed heuristic and link-formation policy live in ADR-017.

**Cross-references: automatic vs earned.** Cheap automatic links form when two atoms exceed a similarity threshold at write time. Stronger *earned* links form when atoms in different KGs *co-activate repeatedly* during reasoning (Hebbian over the synapse layer, ADR-007) — i.e. cross-domain association is itself learned, consistent with the substrate thesis (ADR-001). Cross-KG references are what let spreading activation (the reader, ADR-012) cross domain boundaries.

## Options Considered
**1. Multiple domain KGs + cross-references (CHOSEN).** *Pros:* cold domains page to disk (`runtime/db.nova`), keeping the desktop hot set small (ADR-046); per-domain embedding indices stay small and fast; clean tenant isolation for v2 (ADR-047) — a tenant KG layers over the shared base; gives a natural unit for spawn-on-new-domain; cross-domain reasoning is explicit and learnable. *Cons:* cross-KG queries require following reference edges rather than a single index scan; routing an atom to the right KG can be wrong and needs the ADR-017 heuristic; cross-references add storage and maintenance. Chosen because separability and isolation are decisive for both deployments.

**2. Single monolithic KG (rejected).** All atoms in one `core/knowledge.nova` store. *Pros:* simplest possible model; no routing decision; no cross-store joins; one index to maintain. *Cons:* cannot page cold domains out (fatal on a desktop budget, ADR-003); a single growing embedding index degrades in precision and latency as unrelated atoms accumulate; no tenant isolation for v2; no natural spawn unit. Rejected — it fails the desktop budget and the enterprise isolation requirement simultaneously.

**3. Fixed hand-defined domain partitions, no runtime spawning (rejected).** Founders pre-declare a fixed set of KGs; nothing new spawns. *Pros:* predictable; no risky auto-spawn heuristic; clean ownership. *Cons:* a personal companion encounters open-ended domains we cannot enumerate in advance; forcing novel knowledge into ill-fitting buckets corrupts per-domain centroids and cross-reference quality; contradicts continuous self-directed learning (ADR-026). Rejected — incompatible with the open-world companion goal.

## Consequences
- **Positive:** Memory-efficient on a desktop (cold KGs evicted); fast per-domain retrieval; clean v2 tenant isolation (ADR-047); explicit, learnable cross-domain reasoning; auto-spawn lets the knowledge map grow with the user.
- **Negative:** Cross-KG traversal is costlier than a single-index scan; the spawn heuristic and routing can misclassify (mitigated by ADR-017 and mutable atoms, ADR-016); cross-reference edges add storage and a pruning obligation; an atom's "home KG" can become wrong as domains drift.
- **Future work:** ADR-017 specifies the spawn heuristic, similarity weighting, and automatic-vs-earned link formation; ADR-018 integrates the concept layer across KGs; ADR-029 layers source-authority tiers onto atom confidence; v2 isolation realized in ADR-047.

## Implementation Notes
Extend `core/knowledge.nova` with a namespace/registry layer (`kg_registry`, `kg_spawn`, `kg_get`, `kg_evict`) and cross-reference edges `xref_new(src_kg, src_atom, dst_kg, dst_atom, weight)` weighted by `core/similarity.nova`. Atoms carry global `(kg_id, atom_id)` handles (ADR-016) and Bayesian alpha/beta via `core/belief.nova`. Cold KGs persist/rehydrate through `runtime/db.nova` per ADR-048 ordering. Earned links update through the synapse plasticity path (ADR-007).

DEPENDS ON: NOVA enhancement #8 — multi-KG namespacing + cross-KG reference edges with similarity weights.

Testing: a spawn fixture feeding a synthetic novel-domain atom stream and asserting a new KG is created with a sensible centroid; a cross-reference fixture asserting a `kg-medicine` atom links to a related `kg-user` atom above threshold; an eviction/rehydration round-trip verifying cold-KG persistence.

---

# ADR-005: NOVA as implementation language with required enhancements

Status: Proposed
Date: 2026-05-24

## Context
CrossEngin is the application; NOVA is the language and runtime it is built on (ADR-001, ADR-002). We must decide *deliberately* whether to implement on NOVA or on a mainstream stack, and — having chosen — enumerate exactly which NOVA enhancements CrossEngin depends on, since those gaps are submitted upstream to the NOVA repo and every ADR ASSUMES they will land. This is a foundational decision because the entire substrate (1M-node arenas, sparse synapses, 100Hz ticking, plasticity kernels) bottoms out in runtime capabilities that do not yet fully exist.

The constraints cut both ways. We are 2 founders, 8h/day, bootstrapping, on an 18-30 month v1 timeline. A mainstream stack (Rust/C++, or Python+PyTorch) is battle-tested with vast libraries and hiring pools. But CrossEngin's value is precisely its *cognitive primitives*: NOVA already ships `core/node.nova`, `core/signal.nova`, `core/channel.nova`, `core/moment.nova`, `core/knowledge.nova`, `core/belief.nova`, `core/goal.nova`, `core/concept.nova`, `core/soul.nova`, `core/imagination.nova`, `core/safety.nova`, plus the cognitive `mind/` and `agent/` layers and a `runtime/` with SIMD/tensor/BLAS/GPU, persistence, and a package manager (`pkg/pkg.nova`). NOVA is self-hosting (its own `compiler/`) and currently passes 129/135 tests. Rebuilding these primitives on another stack would consume most of the v1 budget before any CrossEngin-specific work began.

The decisive risk is therefore not "is NOVA capable" but "can the *missing* runtime pieces land in time," since CrossEngin and NOVA are co-developed by the same two founders and every hour spent on NOVA enhancements is an hour not spent on CrossEngin.

## Decision
**CrossEngin is implemented in NOVA.** We build directly on NOVA's existing core/mind/agent/runtime primitives and contribute the substrate-enabling gaps upstream as a numbered enhancement program. The seven primitives (ADR-002) map onto real NOVA modules; CrossEngin adds `synapse_new`, `gate_new`, `atom_new`, multi-KG namespacing, and the 18-signal tag extension in NOVA idiom.

CrossEngin formally depends on the following **14 NOVA enhancements**; ADRs across all groups flag them by number. They cluster into four programs:
- **Substrate scale & compute:** #1 pre-allocated node arenas (1M->1B), #2 sparse synapse adjacency (CSR, O(1) update/grow/prune), #4 SIMD/GPU batched propagation, #12 Hebbian + error-driven plasticity kernels. (ADR-003, ADR-006, ADR-007.)
- **Dynamics & concurrency:** #3 true concurrent execution units for the 6 loops, #5 100Hz tick fused with event-driven coordination, #13 idle-detection + background scheduling for imagination/replay. (ADR-036, ADR-037, ADR-022, ADR-032.)
- **Knowledge & routing:** #6 18+ signal tag space with typed fast-dispatch, #7 learned content-based gate routing, #8 multi-KG namespacing + cross-KG reference edges. (ADR-008, ADR-009, ADR-004/017.)
- **Safety, persistence & I/O:** #9 append-only crash-safe audit log, #10 substrate snapshot + ordered rehydration, #11 whitelisted rate-limited HTTP fetch, #14 STT/TTS modality-bridge isolation. (ADR-043, ADR-048, ADR-028, ADR-014.)

Critically, **#14 hardens the boundary that enforces the NO-LLM-COGNITION principle** (ADR-014): `runtime/llm.nova` + `runtime/llm_bridge.c` are restricted to STT/TTS modality conversion with no path into cognition.

## Options Considered
**1. NOVA + upstream enhancement program (CHOSEN).** *Pros:* the cognitive primitives already exist (node/signal/channel/moment/knowledge/belief/goal/concept/soul/safety/imagination) — reusing them saves the bulk of the v1 budget; NOVA is self-hosting with a working compiler and 129/135 tests; one language across substrate, runtime, and tooling minimizes context-switching for 2 founders; enhancements benefit both repos. *Cons:* we own the runtime gaps (#1-#14) ourselves — no external community to land them; NOVA's ecosystem and hiring pool are essentially us; tooling/debuggers are immature relative to mainstream. Chosen because the primitive reuse is decisive and the gaps, though real, are tractable and co-owned.

**2. Rust or C++ from scratch (rejected).** *Pros:* mature toolchains, excellent performance, strong memory control ideal for fixed arenas and SIMD, large libraries and hiring pool. *Cons:* every cognitive primitive — soul, beliefs, concept layer, goal engine, knowledge graph, imagination — would be rebuilt from zero, almost certainly blowing the 18-30 month v1 budget before CrossEngin-specific work starts; we would also lose NOVA's self-hosting tooling. Rejected: it optimizes the *runtime* problem we mostly don't have and ignores the *primitive* problem we do.

**3. Python + PyTorch (rejected).** *Pros:* fastest prototyping, unrivaled numerical/GPU ecosystem, trivial to express plasticity kernels and batched propagation. *Cons:* the GIL and GC are hostile to genuine concurrency for the 6 loops (#3) and to deterministic 100Hz ticking (#5); pre-allocated fixed arenas (#1) and crash-safe substrate snapshots (#10) fight the runtime; and the gravitational pull toward dropping in an LLM directly threatens the NO-LLM-COGNITION principle (ADR-014). Rejected: wrong concurrency/determinism model and a standing temptation against our core principle.

## Consequences
- **Positive:** Maximum reuse of existing cognitive primitives; a single coherent language for substrate + runtime + tooling; enhancements compound value across both repos; self-hosting compiler gives full control over codegen for SIMD/arena needs.
- **Negative:** The 14 enhancements are a hard dependency owned entirely by the same 2 founders — schedule risk concentrates here; immature ecosystem/tooling; bus-factor and hiring risk from a niche language. Any slipped enhancement blocks the dependent ADRs.
- **Future work:** Sequence the enhancements against the build plan (ADR-050) so each lands just before its dependent milestone; #4/#12 gate the substrate-scale milestone (ADR-003); #3/#5 gate the concurrent-loops milestone (ADR-036/037); #14 must land before any speech I/O ships (ADR-014); #9/#10 before desktop v1 persistence (ADR-046/048).

## Implementation Notes
Build on `core/*`, `mind/*`, `agent/agent.nova`, and `runtime/*` as named in §3; new CrossEngin primitives follow NOVA's constructor/accessor idiom (`synapse_new`, `gate_new`, `atom_new`, `kg_spawn`). Manage the dependency via `pkg/pkg.nova`, pinning NOVA versions per enhancement landing. The enhancement map: #1/#2 over `runtime/persistent_alloc.nova`+`alloc.nova`+`mem.nova`; #4/#12 over `runtime/simd.nova`+`tensor.nova`+`blas.nova`+`gpu.nova`; #3/#5/#13 over `runtime/coroutine.nova`+`taskpool.nova`+`chan.nova`+`scheduler.nova`; #6 over `core/signal.nova`; #7 over `core/channel.nova`; #8 over `core/knowledge.nova`+`similarity.nova`; #9 over `runtime/db.nova`+`core/safety.nova`; #10 over `runtime/persistent_alloc.nova`+`db.nova`; #11 over `runtime/io.nova`+`syscall.nova`; #14 over `runtime/llm.nova`+`llm_bridge.c`.

DEPENDS ON: NOVA enhancements #1-#14 — the full substrate-enabling program enumerated above.

Testing: each enhancement ships with NOVA-side tests folded into the 129/135 suite (target full green before the dependent CrossEngin milestone); a CrossEngin integration fixture per cluster; and the ADR-049 capability tests — including an explicit no-LLM-cognition verification asserting the only call path into `runtime/llm.nova` is STT/TTS (#14).


---

# ADR-006: Node design (uniform behavior, sparse connectivity, atom production)

Status: Proposed
Date: 2026-05-24

## Context
ADR-001 commits CrossEngin to a substrate rather than a modular workflow, and ADR-002 names the node as the locus of computation. We must now fix the node's internal design before any other substrate primitive (synapse, signal, gate) can be built, because every later ADR assumes a concrete node contract: how a node receives signals, what it computes, when it produces atoms, and how it specializes. NOVA's `core/node.nova` already gives us a node primitive with layout `[TAG, name, type, state, inbox, outbox, config]` and six base types (`NTYPE_PERCEIVER`, `NTYPE_KNOWER`, `NTYPE_REMEMBERER`, `NTYPE_REASONER`, `NTYPE_FEELER`, `NTYPE_ACTOR`) plus `node_receive`, `node_emit`, `node_drain_outbox`, `node_set_state`, `node_get_state`. The question is how CrossEngin extends this primitive to scale.

The scaling target from ADR-003 is unforgiving: 1M nodes per part in v1, target 1B long-term, ~1000 synapses per node, 1B signals per part at peak. With nine parts that is 9M nodes in v1 living in pre-allocated arenas on a single desktop (the v1 deployment, ADR-046). At that scale we cannot afford per-node heap objects, per-node vtables, or branchy type-dispatch in the hot signal-propagation loop running at 100Hz (ADR-037). The two founders, working 8h/day on a bootstrap budget, also cannot maintain six divergent node implementations.

A core tension: ADR-002's substrate thesis says specialization should EMERGE from learned state, not be hand-assigned. Yet `core/node.nova` ships six concrete node types. We must reconcile NOVA's typed node with CrossEngin's uniform-behavior ambition, and decide what role (if any) the six `NTYPE_*` constants play.

## Decision
All CrossEngin nodes share one uniform behavior function. A node is a small fixed-size record built on `core/node.nova`'s layout; CrossEngin specializes only the `state` and `config` slots. On each tick a node executes the same kernel: drain `inbox`, integrate incoming signals weighted by the synapse that delivered them (ADR-007), update an activation level held in `state`, and on threshold crossing `node_emit` outgoing signals down its synapses. Specialization (a node that behaves like a medicine-concept detector vs. a phoneme detector) is entirely a function of which synapses it has and the weights/biases learned into them — NOT of its type tag.

The six `NTYPE_*` constants are retained but demoted to a PART-AFFINITY hint and a default-config selector, not a behavior switch. Every node in the KG-medicine part is tagged `NTYPE_KNOWER`; every perception-part node `NTYPE_PERCEIVER`; etc. The tag seeds initial connectivity bias and default plasticity constants but never branches the kernel. This keeps the hot loop branch-free and SIMD-friendly (enhancement #4) while preserving a human-readable map of the substrate.

Atom production is gated on novelty. A node produces an atom (ADR-016, via a new `atom_new`) ONLY when its sustained co-activation pattern is not already explained by an existing atom — the birth rule formalized in ADR-025. Routine firing produces signals, not atoms. Crucially, any node may READ atoms it did not create (cross-KG reads via ADR-004/ADR-017), so a reasoner node consumes knower-authored medicine atoms without owning them.

## Options Considered
**Typed nodes with per-type behavior (one kernel per `NTYPE_*`).** Use NOVA's six types as genuine polymorphism: perceiver nodes run perception logic, knower nodes run retrieval logic, etc. Rejected. It contradicts the ADR-002 emergence thesis, hard-codes a cognitive ontology we want the system to discover, and puts a six-way branch in the 100Hz inner loop over 9M nodes, defeating the batched SIMD propagation of enhancement #4. It also triples maintenance for a 2-person team.

**Fully untyped nodes (drop `NTYPE_*` entirely).** Maximally pure substrate: one type, no affinity hints, connectivity learned from zero. Rejected for v1. With ~1000 synapses/node and 1M nodes/part, learning all structure from a uniform random init is sample-inefficient and would blow the 18-30 month timeline; we would spend months waiting for parts to differentiate. The affinity hint is a cheap prior that costs nothing at runtime.

**Heavyweight "agent" nodes (each node a coroutine).** Give each node its own `runtime/coroutine.nova` fiber so nodes are truly independent actors. Rejected: 9M fibers is far beyond enhancement #3's intent (which targets the SIX loops, ADR-036), and the scheduler/memory overhead per fiber makes 1B nodes impossible on a desktop. Concurrency belongs at the loop and part granularity, not the node.

**Chosen:** uniform kernel + demoted type tag + novelty-gated atom production. It satisfies the emergence thesis where it matters (behavior), keeps a pragmatic prior where it helps (initial wiring), and stays within the desktop memory and the team's maintenance budget.

## Consequences
- **Positive:** One kernel to write, test, and optimize; trivially vectorizable across millions of nodes (enhancement #4). Specialization is observable as learned synapse structure, giving genuine emergence. Atom store stays small because routine activity never mints atoms. Part affinity gives a debuggable map without runtime cost.
- **Negative:** Behavior is harder to inspect — you cannot read a node's type to know what it does; you must inspect its learned synapses and state, which demands new tooling (a node-probe in the test harness). Uniformity pushes complexity into the synapse/plasticity layer (ADR-007) and the gate layer (ADR-009). A buggy kernel is a single point of failure for all 9M nodes.
- **Future work:** Defines the substrate for ADR-007 (synapse), ADR-009 (gate routing into nodes), ADR-010 (first nodes as specialized receivers), and ADR-024 (predictive-coding nodes that emit predictive/error signals). Node-pool expansion toward 1B (ADR-003) reuses this record unchanged.

## Implementation Notes
Extend `core/node.nova` rather than fork it. Add a CrossEngin `xnode_state` map stored in the node's `state` slot with keys `activation` (float), `threshold` (float), `bias` (float), `last_fired_tick` (int), `novelty_accum` (float for the ADR-025 birth rule). Keep `name`/`type`/`config` from the base layout; `type` holds the `NTYPE_*` affinity constant. Implement one function `xnode_tick(node, tick)` that calls `node_drain_outbox`/`node_receive` and reuses `node_set_state`/`node_get_state`; never branch on `type` inside it. Atom emission calls into the ADR-016 `atom_new` only when `novelty_accum` exceeds the ADR-025 birth threshold.

Pre-allocation: all 9M node records live in fixed arenas — `DEPENDS ON: NOVA enhancement #1 — pre-allocated fixed-capacity node arenas`. Batched activation update across a part's node array — `DEPENDS ON: NOVA enhancement #4 — SIMD/GPU batched signal propagation`. Tick cadence from `runtime/scheduler.nova` — `DEPENDS ON: NOVA enhancement #5 — 100Hz deterministic tick scheduler`.

Testing: fixture `fixture_part_1k` instantiates a 1k-node part; assert (a) identical kernel output for two nodes with identical synapses but different `NTYPE_*` tags (proves tag does not alter behavior), (b) no atom minted under repeated known input, exactly one minted on a genuinely novel co-activation, and (c) a reasoner-affinity node successfully reads a knower-authored atom (cross-KG read). Depends on ADR-002 (primitive definitions) and ADR-003 (arena sizing); consumed by ADR-007, ADR-009, ADR-010, ADR-024, ADR-025.

---

# ADR-007: Synapse design (Hebbian + error-driven plasticity, growth, pruning)

Status: Proposed
Date: 2026-05-24

## Context
Nodes (ADR-006) are uniform; all CrossEngin specialization therefore lives in the synapses that connect them. The synapse is the substrate's only long-term learnable parameter, so its design determines whether CrossEngin can satisfy its headline capability — continuous learning — at all. We must decide the synapse's representation, its weight update rule(s), and its lifecycle (growth and pruning), and we must do so within hard limits: 1M nodes/part, ~1000 synapses/node means ~1 billion synapse slots per part, ~9 billion across nine parts in v1, all on a single desktop (ADR-046).

NOVA's `core/channel.nova` gives carriers with layout `[TAG, name, source, destinations, chan_type, filter_min_salience, message_count]` and four channel types (`CHAN_DIRECT`, `CHAN_BROADCAST`, `CHAN_FILTERED`, `CHAN_WEIGHTED`). A synapse is a weighted point-to-point carrier — conceptually `CHAN_WEIGHTED` with exactly one destination plus a learned scalar. But `core/channel.nova` was not built for billions of instances with per-tick weight math, so the representation must change even though the conceptual mapping holds.

The constraints force two non-obvious choices. First, we cannot store synapses as individual channel objects — 9B heap records would exhaust desktop RAM and destroy cache locality in the 100Hz propagation loop. Second, plasticity must be cheap: a weight update that runs over billions of active synapses each tick must be a vectorized array kernel, not a per-object method call. The two-founder team needs one plasticity implementation that serves Hebbian co-firing, error-driven correction (for predictive coding, ADR-024), and emotion-modulated learning (ADR-035) without three separate code paths.

## Decision
A synapse is a row in a sparse, CSR-like adjacency structure per part, not an object. For each part we store parallel typed arrays: `pre[]` (source node index), `post[]` (destination node index), `weight[]` (float, bounded), `eligibility[]` (recent co-activation trace), `last_active_tick[]`, and `sig_type_mask[]` (which of the 18 signal types from ADR-008 this synapse carries). Indexing is CSR by source node so a node's ~1000 outgoing synapses are contiguous. Cross-part synapses (node-to-other-part, per ADR-002) live in a separate inter-part block keyed by destination part + first-node index (ADR-010).

Weight learning is a single fused rule with two additive terms. The Hebbian term strengthens co-firing: `dw_hebb = eta_h * pre_act * post_act` (with the eligibility trace decaying between co-fires). The error-driven term corrects prediction mismatch: `dw_err = eta_e * pre_act * error_signal`, where `error_signal` is the ADR-008 error-type signal arriving at the post-node during predictive coding (ADR-024). Both terms are computed in one pass over the active-synapse arrays. A global modulator scales `eta_h`/`eta_e` from emotional arousal/valence (ADR-035) — emotion conditions plasticity rate, not a separate rule. Weights are clamped to `[w_min, w_max]` (e.g. `[-1.0, +1.0]`, sign carrying excitatory vs inhibitory intent per ADR-008) to prevent runaway potentiation.

Lifecycle: synapses are SPARSE at startup (well below ~1000/node) and GROW. When two unconnected nodes co-activate above a growth threshold for N ticks, a new synapse row is appended (O(1) amortized). PRUNING runs as a periodic GC during idle (enhancement #13): synapses whose `|weight|` and `eligibility` stay below a death threshold for a decay window are removed and their slots reclaimed, capping each node near ~1000 live synapses.

## Options Considered
**Per-synapse channel objects (literal `CHAN_WEIGHTED`).** Most faithful to `core/channel.nova`; each synapse a real channel with its own weight field. Rejected on scale: 9B objects is infeasible in desktop RAM, pointer-chasing wrecks the 100Hz loop, and weight updates become billions of virtual calls. The conceptual mapping is preserved in spirit but the storage must be arrays.

**Dense weight matrices per part.** A 1M×1M matrix per part trivially supports BLAS-style updates (enhancement #4) and is simple to reason about. Rejected: a dense 1M² float matrix is ~4TB per part — utterly impossible. Even at lower precision it is orders of magnitude over budget. Sparsity is not an optimization here; it is mandatory, and it is also biologically and cognitively correct (real connectivity is sparse).

**Hebbian-only plasticity (no error term).** Simpler: one rule, no dependence on error signals. Rejected because it cannot support predictive coding (ADR-024), which is the mechanism behind self-learning triggers via prediction error (ADR-026) and a key capability test (ADR-049). Pure Hebbian learning also drifts and lacks a corrective signal, tending toward degenerate all-strong or all-weak regimes.

**Chosen:** CSR sparse arrays + fused Hebbian/error rule + grow/prune lifecycle. It is the only option that fits ~9B synapses on a desktop, supports both learning signals in one kernel, and gives the continuous-learning and predictive-coding capabilities downstream ADRs require.

## Consequences
- **Positive:** Memory fits the desktop budget (sparse rows, typed arrays, no per-object overhead). One vectorized kernel serves Hebbian, error-driven, and emotion-modulated learning. Growth lets structure expand with experience (continuous learning); pruning bounds memory and removes noise. Sign-as-weight unifies excitatory/inhibitory synapses with the ADR-008 taxonomy.
- **Negative:** CSR with growth/pruning is complex — appends and compaction must stay crash-safe and not fragment (work for enhancement #2). Debugging a learned weight matrix is hard; we need a synapse-inspector in the harness. Bounded weights and dual learning rates introduce hyperparameters (`eta_h`, `eta_e`, growth/death thresholds, decay window) that must be tuned, a real cost for a 2-person team.
- **Future work:** Directly enables ADR-024 (predictive coding consumes the error term), ADR-025 (atom birth/death parallels synapse growth/pruning), ADR-035 (emotion modulates `eta`). Synapse persistence is part of the substrate snapshot (ADR-048). Inter-part synapse blocks feed first nodes (ADR-010) and gate routing (ADR-009).

## Implementation Notes
New module `core/synapse.nova` exposing `synapse_new(part, pre, post, sig_mask)` (appends a CSR row), `synapse_weight(idx)`, `synapse_set_weight`, and batch entry points `synapse_plasticity_step(part, tick)` (fused Hebbian+error pass) and `synapse_prune(part)` (idle GC). Reuse `core/channel.nova` semantics conceptually (a synapse is the `CHAN_WEIGHTED`, single-destination case) and `core/similarity.nova` for weighting inter-part/cross-KG connections (ADR-017). Store the CSR arrays in part-owned arenas alongside the node arrays from ADR-006.

`DEPENDS ON: NOVA enhancement #2 — sparse synapse adjacency (CSR-like) with O(1) weight update, growth, and pruning.` `DEPENDS ON: NOVA enhancement #12 — Hebbian + error-driven plasticity kernels over synapse weight arrays.` Batched propagation along synapses uses `DEPENDS ON: NOVA enhancement #4 — SIMD/GPU batched signal propagation`. Idle pruning hook: `DEPENDS ON: NOVA enhancement #13 — idle-detection + background scheduling hooks`.

Testing: fixture `fixture_two_node_cofire` verifies a synapse strengthens under repeated co-firing and saturates at `w_max`; `fixture_predict_error` injects an ADR-008 error signal and asserts the error term moves the weight toward reduced future error; `fixture_prune_cycle` runs the decay window and asserts weak synapses are reclaimed and a node stays near its ~1000-synapse cap. Depends on ADR-006 (node kernel, activation) and ADR-008 (signal types carried). Validated end-to-end by ADR-024 and the continuous-learning capability test in ADR-049.

---

# ADR-008: Signal taxonomy (18 types)

Status: Proposed
Date: 2026-05-24

## Context
Signals are the substrate's ephemeral currency: ADR-002 defines them as typed messages flowing through synapses, and ADR-003 budgets 1B signals per part at peak. Because nodes are uniform (ADR-006) and synapses carry "any signal type" (ADR-007), the SIGNAL TYPE is what tells a node how to treat an incoming message and tells a gate (ADR-009) how to route it. The taxonomy is therefore load-bearing for the entire substrate, and many later ADRs reference specific types by name — ADR-024 needs predictive and error, ADR-045 needs inhibitory and constitutional, ADR-035 needs valence and arousal, ADR-026 needs curiosity and goal-drive. We must define the full set precisely and once.

NOVA's `core/signal.nova` provides the base primitive: layout `[TAG, type, moment, origin, destination, priority, trace, metadata]` with eight base types (`SIG_EVENT`, `SIG_QUESTION`, `SIG_ORDER`, `SIG_COMMAND`, `SIG_REQUEST`, `SIG_RESPONSE`, `SIG_CORRECTION`, `SIG_REFLECTION`). These eight are coarse, conversational message kinds — they describe agent-level intents, not substrate dynamics. CrossEngin needs a finer, dynamics-level vocabulary that captures excitation/inhibition, prediction/error, affect, and control. The decision is how many types, what they are, and how they extend the existing tag space without breaking it.

The constraint is dispatch cost. At 1B signals/part the type check sits in the hottest loop in the system, so the type must be a small integer enabling table dispatch, and the 18 types must fit a single dispatch table shared by nodes and gates. We also must not duplicate the eight base types; CrossEngin's 18 are an EXTENSION of the same tag space, not a replacement.

## Decision
We define exactly 18 CrossEngin signal types as an extension of `core/signal.nova`'s tag space (enhancement #6). They occupy a reserved CrossEngin tag range above the eight base `SIG_*` constants and reuse the existing layout — `type` holds one of the 18 `XSIG_*` constants, `priority` holds the per-type priority below, and `metadata` carries type-specific payload (e.g. an error signal's magnitude, a binding signal's group id). Priority is an integer 0 (lowest) to 9 (highest) read by gates for scheduling and by nodes for inbox ordering; constitutional signals are deliberately highest so they cannot be starved.

The 18 types, each with its role and priority/intuition:

1. **excitatory** (`XSIG_EXCITE`, pri 4) — the default carrier; raises the destination node's activation toward firing. The substrate's baseline "push."
2. **inhibitory** (`XSIG_INHIBIT`, pri 6) — lowers/suppresses activation; implements competition, gating-off, and the hard veto path used by constitutional rules. Higher priority than excitatory so suppression wins ties (safety-relevant, ADR-045).
3. **sensory** (`XSIG_SENSORY`, pri 5) — raw perception entering the substrate at first nodes (ADR-010) from a moment (ADR-021). The bottom of the predictive-coding stack (ADR-024).
4. **predictive** (`XSIG_PREDICT`, pri 5) — a top-down expectation sent from a higher layer to a lower one; what the system thinks it will perceive next (ADR-024).
5. **error** (`XSIG_ERROR`, pri 7) — bottom-up prediction mismatch (perceived minus predicted). Drives the error term of synapse plasticity (ADR-007) and triggers self-learning (ADR-026). High priority — surprises must propagate fast.
6. **causal** (`XSIG_CAUSAL`, pri 4) — asserts a cause→effect relation between activated atoms; substrate-level material for reasoning operators (ADR-031) and counterfactuals (ADR-032).
7. **implicative** (`XSIG_IMPLY`, pri 4) — logical/definitional entailment (A implies B) distinct from physical causation; feeds inferential reasoning (ADR-031).
8. **analogical** (`XSIG_ANALOGY`, pri 3) — signals a structural similarity/mapping between concepts in different KGs; rides cross-KG references (ADR-017) and supports transfer and imagination (ADR-032).
9. **evidential** (`XSIG_EVIDENCE`, pri 5) — carries support/confirmation or disconfirmation for an atom's belief, updating its alpha/beta counts (ADR-016, ADR-023). Source-tier weighting (ADR-029) rides here.
10. **attentive** (`XSIG_ATTEND`, pri 6) — a salience/focus boost that biases which parts and nodes are prioritized this tick; raises effective priority of co-located signals. Shapes gate routing (ADR-009).
11. **binding** (`XSIG_BIND`, pri 5) — temporarily groups co-active atoms into a single bound percept/thought (the binding problem); `metadata` carries a transient group id. Underlies coherent moments (ADR-021) and reader coherence checks (ADR-012).
12. **valence** (`XSIG_VALENCE`, pri 4) — affective good/bad appraisal of a moment against goals/values (OCC, ADR-035); a global modulator of plasticity sign/strength (ADR-007).
13. **arousal** (`XSIG_AROUSAL`, pri 5) — intensity/activation level of emotional state; scales learning rate `eta` (ADR-007) and tick urgency (ADR-035).
14. **curiosity** (`XSIG_CURIOSITY`, pri 3) — an intrinsic novelty/uncertainty drive marking a knowledge gap worth exploring; a self-learning trigger (ADR-026) sourced from the goal engine's drives (ADR-033).
15. **goal-drive** (`XSIG_GOAL`, pri 6) — top-down activation from an active goal/sub-goal biasing the substrate toward goal-relevant atoms (ADR-033, ADR-040). High priority so goals steer cognition.
16. **reward** (`XSIG_REWARD`, pri 6) — reinforcement (positive or negative) on goal satisfaction or user feedback; consolidates the synapses and atoms that produced the rewarded outcome (ADR-007, ADR-022).
17. **recall** (`XSIG_RECALL`, pri 4) — a retrieval cue that reactivates stored atoms/episodes from memory (ADR-022) and drives spreading activation in the reader (ADR-012).
18. **constitutional** (`XSIG_CONST`, pri 9) — the highest-priority control signal; carries hard, non-negotiable inhibitory rules from the soul's constitution (ADR-034) and is implemented as an unconditionable inhibitory veto (ADR-045). Cannot be overridden, decayed, or pruned away.

## Options Considered
**Keep only NOVA's 8 base `SIG_*` types.** Reuse `SIG_EVENT`/`SIG_QUESTION`/etc. and encode dynamics in `metadata`. Rejected: these are agent-conversation intents, not substrate dynamics; packing excitation, inhibition, prediction, error and affect into metadata strings would put string parsing in the 1B-signal/tick hot loop and lose typed fast-dispatch. The semantics we need (e.g. inhibitory must out-prioritize excitatory) cannot be expressed by eight conversational tags.

**A very large, open-ended type set (40+ fine types).** Maximally expressive — a distinct type per cognitive nuance. Rejected: a 40+ way dispatch table is slower and the distinctions (e.g. ten flavors of error) are better expressed in `metadata` than in the type tag. A bloated taxonomy also raises the maintenance burden for two founders and makes gate routing tables (ADR-009) explode combinatorially.

**Two-axis encoding (a small base type × a modulator flag) instead of 18 flat types.** E.g. {excite, inhibit} × {predict, recall, ...}. Rejected for v1: the cross-product is harder to route on and many combinations are meaningless (an inhibitory-curiosity signal is ill-defined). A flat, well-chosen set of 18 is simpler to dispatch and to reference precisely from other ADRs, which matters because so many depend on exact names.

**Chosen:** 18 flat `XSIG_*` types extending the base tag space with per-type integer priority. It is expressive enough to cover excitation/inhibition, predictive coding, reasoning relations, affect, drives, and control, yet small enough for a single fast dispatch table, and each type has a stable name other ADRs can cite.

## Consequences
- **Positive:** A precise, shared vocabulary the whole substrate and all downstream ADRs can reference by name. Small-integer types give branchless table dispatch at 1B signals/part (enhancement #6). Per-type priority bakes in safety ordering (constitutional > inhibitory > excitatory) and attention/goal steering. Reuses `core/signal.nova`'s layout untouched, so trace/metadata/moment plumbing is free.
- **Negative:** Eighteen types is a real surface area to implement, route, and test; gates (ADR-009) must learn routing for all of them. Fixing the set now risks under- or over-fitting future needs — adding a 19th type later means touching the dispatch table and gate tables. Some semantic boundaries (causal vs implicative, valence vs reward) require discipline to keep distinct in practice.
- **Future work:** ADR-009 builds routing tables keyed on these types; ADR-024 wires predictive/error into the layer loop; ADR-035 emits valence/arousal/reward; ADR-026 consumes curiosity/error; ADR-045 hardens constitutional/inhibitory. Persistence (ADR-048) need not store signals (they are ephemeral) but must preserve the type registry.

## Implementation Notes
Extend `core/signal.nova`: add the 18 `XSIG_*` tag constants in a reserved range above the eight `SIG_*` constants, plus a static `xsig_priority[]` table and a `signal_is_constitutional(sig)` predicate used on the safety fast-path. Reuse `signal_new` (set `type` to the `XSIG_*` constant, `priority` from the table, `metadata` for payload such as error magnitude or binding group id). Provide a single `xsig_dispatch(type)` index into the shared node/gate handler table. `DEPENDS ON: NOVA enhancement #6 — extended signal tag space (18+ types) with typed fast-dispatch.`

Testing: `fixture_sig_priority` asserts inhibitory out-orders excitatory and constitutional out-orders everything in a node's inbox; `fixture_sig_roundtrip` verifies each of the 18 types survives `signal_new`→synapse→`node_receive` with metadata intact; `fixture_const_veto` asserts a constitutional signal suppresses a competing excitatory signal regardless of weights (pre-check for ADR-045). Honors the NO-LLM-COGNITION principle: signal generation is pure substrate, never produced by the LLM bridge. Consumed by ADR-007, ADR-009, ADR-010, ADR-024, ADR-026, ADR-031, ADR-033, ADR-035, ADR-045.

---

# ADR-009: Gate design (learned routing, signal-content-based, broadcast support)

Status: Proposed
Date: 2026-05-24

## Context
A signal (ADR-008) leaving a node must reach the right destination part(s) — a sensory signal to perception's first nodes (ADR-010), an error signal up the predictive-coding stack (ADR-024), a constitutional signal everywhere with veto priority (ADR-045). With nine parts, 1M nodes each, and 1B signals/part, hard-wiring every routing path is impossible and would freeze the substrate's organization. ADR-002 specifies gates as learned routing checkpoints that "decide which parts receive which signals based on signal content," start with basic rules, develop sophistication, and can broadcast to multiple parts at once. We must now design that mechanism concretely.

NOVA's `core/channel.nova` gives the raw material: layout `[TAG, name, source, destinations, chan_type, filter_min_salience, message_count]` and four channel types. Two are directly relevant: `CHAN_FILTERED` (route by a salience/content filter) and `CHAN_BROADCAST` (one-to-many), plus `CHAN_WEIGHTED`. A gate is essentially a `CHAN_FILTERED`/`CHAN_BROADCAST` channel whose filter is LEARNED rather than static. But `core/channel.nova` filters are fixed thresholds; CrossEngin needs the routing decision to adapt with experience while remaining cheap enough for the 100Hz loop and inspectable enough for the safety layer (ADR-043).

The bootstrapping constraint shapes this heavily. We cannot ship a system that learns all routing from scratch — it would behave randomly for months. We need sensible seed rules (sensory→perception, goal-drive→reasoning, constitutional→broadcast) that work on day one, with learning layered on top to refine and add routes. And every routing decision involving an action-class signal must be loggable for ADR-043.

## Decision
A gate is a learned, content-based router built atop `core/channel.nova`, placed between a source (a node's outbox or an inter-part synapse block) and one-or-more destination parts. Each gate holds a small routing TABLE keyed primarily on signal type (the 18 `XSIG_*` constants, ADR-008) and secondarily on lightweight signal content: the signal's `priority`, salient `metadata` keys, and a coarse activation/topic vector. The table entry yields a set of destination parts each with a routing WEIGHT; destinations whose weight exceeds the gate's admit threshold receive the signal. When two or more destinations qualify, the gate uses a `CHAN_BROADCAST` fan-out; when one qualifies, a `CHAN_DIRECT`/`CHAN_FILTERED` delivery.

Routing weights are SEEDED with hand-written rules and then LEARNED. Seed rules encode obvious priors: `XSIG_SENSORY`→perception first nodes; `XSIG_GOAL`→reasoning+action; `XSIG_RECALL`→episodic; `XSIG_CONST`→broadcast to all parts at top priority. Learning is reinforcement-style and reuses the plasticity machinery of ADR-007: when a routed signal contributes to a rewarded outcome (an `XSIG_REWARD`, ADR-008) or reduces downstream prediction error (`XSIG_ERROR`, ADR-024), the route weight to that destination is strengthened; consistently useless routes decay and are pruned, exactly mirroring synapse growth/pruning. Thus gates "develop sophistication" without a separate learning subsystem.

Constitutional routing is privileged and NOT learnable: `XSIG_CONST` signals always broadcast at priority 9 and the gate cannot down-weight or prune that route (enforced, ADR-045). This is the one hard exception to learned routing.

## Options Considered
**Static rule-based routing (fixed `CHAN_FILTERED` filters).** Hand-write all routes once; no learning. Simplest and most predictable, and it ships fastest for two founders. Rejected as the sole mechanism: it freezes the substrate's organization, contradicting ADR-002's "develops sophistication," and cannot discover that, say, a particular medical pattern should also reach the imagination part. We keep its strength by using it as the SEED layer beneath learning.

**Full broadcast everywhere (no gating).** Every signal goes to every part; let nodes ignore irrelevant input. Trivially simple. Rejected on cost: broadcasting 1B signals/part to nine parts is ~9B deliveries/tick — far beyond the desktop and the SIMD budget (enhancement #4) — and it removes the attentional focusing that `XSIG_ATTEND` (ADR-008) is meant to provide. Broadcast is retained only where semantically required (constitutional, some attentive signals).

**A learned neural classifier per gate (a small network deciding routes).** Maximally adaptive content-based routing. Rejected for v1: it adds a second, opaque learning system distinct from synapse plasticity, doubling the machinery the team must build and tune, and an opaque router conflicts with the inspectability the decision log (ADR-043) and override mechanism (ADR-044) require. A weighted table learned by the SAME reinforcement rule as synapses is adaptive enough and stays auditable.

**Chosen:** seeded-then-learned weighted routing tables on `core/channel.nova`, reusing ADR-007 plasticity, with a privileged non-learnable constitutional path. It works on day one, improves with experience, costs little in the hot loop, and remains inspectable.

## Consequences
- **Positive:** Day-one sensible behavior from seed rules with no cold-start; routing improves automatically using machinery already built for ADR-007 (no new learner). Content-based admission plus selective broadcast keeps signal volume tractable and supports attention. Constitutional broadcast is structurally guaranteed (ADR-045). Tables are human-readable, satisfying ADR-043/ADR-044 inspection.
- **Negative:** A learned routing layer adds a tuning surface (admit threshold, route learning rate, decay) and a failure mode where mis-learned routes misdeliver signals — needs a gate-trace tool in the harness. Sharing the reinforcement signal with synapse plasticity couples two systems; a reward-attribution bug affects both. Per-gate tables consume memory that must be budgeted within the desktop limit.
- **Future work:** Gates feed first nodes (ADR-010) and are the routing backbone for predictive/error flow (ADR-024), goal-driven biasing (ADR-033), recall cues (ADR-022/ADR-012), and constitutional veto (ADR-045). Gate routes are part of the substrate snapshot (ADR-048). v2 multi-tenant (ADR-047) keeps the constitutional path non-negotiable across tenants.

## Implementation Notes
New module `core/gate.nova` exposing `gate_new(name, source, seed_rules)`, `gate_route(gate, signal)` (returns destination set; emits via `core/channel.nova` `CHAN_BROADCAST` or `CHAN_DIRECT`), `gate_reinforce(gate, dest, delta)` (route-weight update reusing the ADR-007 kernel), and `gate_prune(gate)`. Represent each gate's table as a map from `XSIG_*` type to a small weighted destination list; store the coarse content vector with `core/similarity.nova` for content matching. Seed rules are a static table loaded at startup. Mark the `XSIG_CONST` route immutable.

`DEPENDS ON: NOVA enhancement #7 — learned, content-based gate routing tables atop core/channel.nova (filtered/weighted channels).` Reinforcement reuses `DEPENDS ON: NOVA enhancement #12 — Hebbian + error-driven plasticity kernels` (same update applied to route weights). Broadcast fan-out across millions of signals uses `DEPENDS ON: NOVA enhancement #4 — SIMD/GPU batched signal propagation`.

Testing: `fixture_gate_seed` asserts seed rules deliver `XSIG_SENSORY`→perception and `XSIG_CONST`→all parts on tick 0 with no learning; `fixture_gate_learn` rewards a route and asserts its weight rises and an unrewarded route decays/prunes; `fixture_gate_const_immutable` attempts to down-weight the constitutional route and asserts it cannot change (gate to ADR-045). Honors NO-LLM-COGNITION: routing is pure substrate. Depends on ADR-008 (signal types/priority) and ADR-007 (plasticity kernel); feeds ADR-010, ADR-024, ADR-043, ADR-045.

---

# ADR-010: First nodes (specialized sensory input receivers per part)

Status: Proposed
Date: 2026-05-24

## Context
External input enters CrossEngin as a moment (ADR-002, ADR-021) and must be injected into the substrate somewhere. Since nodes are uniform (ADR-006) and gates route signals to PARTS (ADR-009), we need a well-defined ENTRY POINT within each part where routed input lands and begins propagating. ADR-002 names these FIRST NODES: "specialized nodes in each part that receive sensory input routed through gates; entry points to each part's substrate." We must decide how first nodes are designated, how gates address them, and how they specialize per part — without violating the uniform-behavior decision of ADR-006.

This matters now because first nodes are the seam between three already-decided pieces: moments/perception (sensory `XSIG_SENSORY` signals, ADR-008), gate routing (ADR-009, which routes to a part), and the node kernel (ADR-006). If gates route only to "a part" but a part has 1M uniform nodes, the signal has no defined landing site. First nodes resolve that: they are the part's named, stable input surface. They are also where the predictive-coding stack bottoms out (ADR-024) — top-down predictions meet bottom-up sensory signals at the first nodes of perception.

The constraint, again, is reconciling specialization with uniformity. ADR-006 forbids per-type behavior. Yet a phoneme first-node in perception and a goal-cue first-node in reasoning clearly do different jobs. The resolution must keep the kernel uniform while letting first nodes differ only in their wiring and config, and it must give each first node a stable index so gate routing tables (ADR-009) and inter-part synapse blocks (ADR-007) can target them across restarts (ADR-048).

## Decision
Each part reserves a small, fixed block of its 1M nodes — the FIRST-NODE block (e.g. the first 1,024 indices per part) — as its sensory/input receiver surface. First nodes are ordinary ADR-006 nodes running the identical kernel; they are "specialized" only by (a) a stable, well-known index range that gates and inter-part synapses address, (b) a richer initial fan-out of synapses into the rest of the part, and (c) per-part config presets matching the part's input modality. No kernel branch distinguishes them — their distinct behavior is entirely learned wiring plus config, consistent with ADR-006.

Gates (ADR-009) route to a part by delivering to that part's first-node block, not to arbitrary interior nodes. The routing table's destination is therefore (part-id, first-node-block); a `CHAN_BROADCAST` from a gate fans a signal across the relevant first nodes. Per-part specialization of first nodes: perception first nodes receive `XSIG_SENSORY` from moments (sub-grouped by modality — text/phoneme, and audio via the STT bridge, ADR-014); reasoning first nodes receive `XSIG_GOAL`, `XSIG_CAUSAL`, `XSIG_IMPLY`; episodic first nodes receive `XSIG_RECALL`; soul/meta first nodes receive `XSIG_VALENCE`/`XSIG_AROUSAL`/`XSIG_CONST`. Each part's first-node config seeds which signal types it expects, but gates can LEARN to deliver additional types (ADR-009) so the input surface adapts.

First nodes are the canonical bottom of the predictive-coding hierarchy (ADR-024): perception first nodes emit `XSIG_ERROR` upward when incoming `XSIG_SENSORY` mismatches the `XSIG_PREDICT` arriving top-down. They mint atoms under the same novelty rule as any node (ADR-006/ADR-025) — typically the first to do so for genuinely new percepts.

## Options Considered
**Designated first-node block (reserved index range per part).** The chosen approach: a fixed, named slice of each part's node arena. Chosen because it gives gates and inter-part synapses a stable, restart-safe target (ADR-048), keeps the kernel uniform (ADR-006), costs nothing at runtime (just an index convention), and is trivial to pre-allocate (enhancement #1). Its only cost is reserving capacity that is fixed in size.

**A separate node TYPE for receivers (e.g. lean on `NTYPE_PERCEIVER`).** Make first nodes a distinct type with receiver-specific behavior. Rejected: it reintroduces per-type behavior, directly violating ADR-006, and `NTYPE_*` is already demoted to an affinity hint there. We get the labeling benefit by part affinity + index range without a behavioral branch.

**Dynamic/learned entry points (any node may be a receiver; gates learn which).** Maximally flexible — no reserved block; gates learn to route input to whichever interior nodes prove useful. Rejected for v1: with 1M nodes/part the routing table's destination space becomes enormous and unstable across restarts, breaking persistence (ADR-048) and making gate learning (ADR-009) far slower to converge. A fixed entry surface is the right cold-start prior; interior adaptation still happens via synapse growth beyond the first nodes.

**Chosen:** reserved per-part first-node block with per-part config presets and learned-extendable gate delivery. It is stable, uniform-kernel-compatible, cheap, and gives predictive coding a defined bottom layer.

## Consequences
- **Positive:** A stable, addressable input surface per part that gates and inter-part synapses can target deterministically across restarts (ADR-048). Keeps ADR-006 uniformity intact (no new type, no kernel branch). Gives ADR-024 a concrete bottom layer for sensory-vs-prediction error. Per-part config presets give sensible day-one behavior; gate learning lets the surface adapt later.
- **Negative:** Reserving a fixed first-node block per part is a static capacity decision — too small bottlenecks input, too large wastes arena; the size (e.g. 1,024) needs tuning. First nodes are a higher-traffic hotspot, concentrating load and making them a potential propagation bottleneck under peak 1B-signal bursts. A bug in first-node wiring blocks all input to a part.
- **Future work:** Directly underpins ADR-021 (moments inject at perception first nodes), ADR-024 (predictive-coding bottom layer), and ADR-013 (output is the inverse path, from concept activation toward motor effectors). v2 enterprise (ADR-047) replicates the first-node convention per tenant process. Snapshot/rehydration (ADR-048) must restore first-node indices before general nodes.

## Implementation Notes
No new core module is required — first nodes are a CONVENTION over ADR-006 nodes plus ADR-009 routing. Add to `core/node.nova` usage a per-part constant `FIRST_NODE_COUNT` (e.g. 1024) and reserve indices `[0, FIRST_NODE_COUNT)` of each part's arena. Provide helpers `part_first_nodes(part)` (returns the block) and `part_inject(part, signal)` (delivers a routed signal across the block via `core/channel.nova` `CHAN_BROADCAST`). First-node config presets are a static per-part table mapping part-id → expected `XSIG_*` types (ADR-008), used to seed gate routes (ADR-009) and initial synapse fan-out (ADR-007).

`DEPENDS ON: NOVA enhancement #1 — pre-allocated fixed-capacity node arenas` (the reserved block lives at the front of each arena). Input delivery and fan-out use `DEPENDS ON: NOVA enhancement #4 — SIMD/GPU batched signal propagation`. The STT-only modality path that may feed perception first nodes is isolated per `DEPENDS ON: NOVA enhancement #14 — STT/TTS modality bridge isolation guaranteeing no cognition path` — first nodes receive only `XSIG_SENSORY` content, never LLM-derived cognition (NO-LLM-COGNITION principle).

Testing: `fixture_inject_moment` builds a moment (ADR-021), routes it through a gate (ADR-009), and asserts it lands on perception's first-node block and raises their activation; `fixture_first_node_error` sends a mismatched `XSIG_PREDICT` and asserts a first node emits `XSIG_ERROR` upward (pre-check for ADR-024); `fixture_first_node_uniform` asserts a first node and an interior node with identical synapses produce identical kernel output (proves no behavioral specialization, upholding ADR-006). Depends on ADR-006, ADR-008, ADR-009; feeds ADR-021, ADR-024, ADR-013, ADR-048.


---

# ADR-011: Reader: Option 5 hybrid (substrate + predictive components)

Status: Proposed
Date: 2026-05-24

## Context
Every external input to CrossEngin — typed text, a transcribed utterance, a document the user pastes — must be turned into substrate activity: a pattern of firing across the perception and KG parts that the six loops (ADR-036) can reason over. The component that does this is the READER. It must decide which concepts a piece of language refers to, bias that interpretation by current context and soul state, pull the relevant atoms out of the right KGs (ADR-004, ADR-017), and learn from the interaction. This decision fixes WHAT KIND of thing the reader is, because it shapes the entire input path and every downstream ADR in this group.

The temptation is to reach for a parser or an LLM. Both are rejected on principle: per §2 and the NO-LLM-COGNITION rule formalized in ADR-014, the reader is NOT a parser and NOT an LLM. A classical parser imposes a fixed grammar and produces brittle symbolic trees that cannot degrade gracefully or learn; an LLM would smuggle opaque cognition into the input path, defeating CrossEngin's entire thesis that intelligence emerges from substrate dynamics (ADR-001). At the same time, a purely associative spreading-activation reader with no predictive machinery is too slow and too ambiguous to resolve real language in real time at our 100Hz tick budget (ADR-037).

The forces are sharp. We are 2 founders at 8h/day, bootstrapping, with an 18-30 month v1 horizon. We cannot build and train a language model, nor maintain a large hand-written grammar. We need something that is cheap to start, learns continuously, runs inside the substrate, and produces signal activity rather than parse trees.

## Decision
We adopt **Option 5: a hybrid reader combining substrate spreading-activation with lightweight predictive components.** The reader is implemented as a coordinated five-stage pipeline (detailed in ADR-012): lexical anchor, context bias, spreading activation, coherence check, and fetch/route/learn. Its substrate half does the conceptual work — token surface forms anchor to language atoms (ADR-015), activation spreads across cross-KG references, and `NTYPE_KNOWER` nodes settle on an interpretation. Its predictive half is a thin layer of `SIG_PREDICTIVE` signals (ADR-008) that pre-bias likely next concepts and likely senses from context, sharpening and accelerating the substrate settle so it converges within the tick budget.

Concretely, the reader is not a separate module that "calls" the substrate; it is a configuration of nodes, gates, and signals. Stage outputs are `SIG_EVENT` and `SIG_REQUEST` signals routed by learned gates (ADR-009) to the appropriate KG parts. The predictive component is itself learned (Hebbian + error-driven, ADR-007): when a prediction mismatches the eventual settle, the `SIG_ERROR` drives weight updates, so the reader gets faster and more accurate with experience rather than being frozen at design time. This is predictive coding (ADR-024) applied to comprehension.

## Options Considered
1. **Pure symbolic parser (grammar + lexicon).** Deterministic, debuggable, fast. Rejected: brittle on noisy/novel input, requires hand-maintained grammar we have no capacity to build or grow, produces parse trees rather than substrate activity, and cannot learn continuously — it contradicts ADR-001's emergence thesis.
2. **Pure statistical / n-gram model.** Cheap, robust to noise, learns from data. Rejected: shallow — captures surface co-occurrence, not concept reference or cross-domain meaning; needs a training corpus we do not have; still external to the substrate.
3. **LLM-based reader.** Most capable at raw comprehension. Rejected outright on principle (ADR-014, §2): an LLM in the input path IS cognition; it is opaque, unauditable against the decision log (ADR-043), and dissolves the substrate thesis. The LLM bridge is confined to STT/TTS modality only (enhancement #14).
4. **Pure-substrate spreading-activation only (no predictive layer).** Fully in-substrate, learns, no external model. Rejected as insufficient ALONE: without top-down bias, activation is ambiguous and slow to settle, blowing the 100Hz budget on long or polysemous input. It is, however, the core of the chosen option.
5. **Substrate + predictive hybrid (CHOSEN).** Keeps spreading activation as the meaning engine but adds learned predictive bias to disambiguate and accelerate. Captures the strengths of option 4 while fixing its latency/ambiguity weakness, stays fully inside the substrate, honors NO-LLM-COGNITION, and learns continuously.

## Consequences
- **Positive:** Input comprehension lives entirely in the substrate and improves with use; no training corpus or grammar to maintain; graceful degradation on novel/noisy input; full auditability (every stage emits traced signals); predictive bias keeps comprehension inside the tick budget; uniform mechanism reused for the self-model API (ADR-038).
- **Negative:** Emergent behavior is harder to debug than a parse tree; early reader (cold substrate) will be weak until language atoms and synapses accumulate; tuning the balance between bottom-up activation and top-down prediction is delicate and ongoing; two interacting learning signals (Hebbian + error) can oscillate if gains are mis-set.
- **Future work:** ADR-012 specifies the five stages; ADR-015 supplies the language atoms it anchors to; ADR-024 generalizes the predictive coding; the fetch/learn stage feeds self-learning triggers (ADR-026) and internet fetching (ADR-028).

## Implementation Notes
Place the reader in `crossengin/reader/reader.nova` as a substrate configuration, not a monolithic function: constructors `reader_new(parts_ref)`, stage drivers `reader_anchor`, `reader_bias`, `reader_spread`, `reader_cohere`, `reader_route` (each defined fully in ADR-012). Anchoring queries the language KG via `core/knowledge.nova` accessors; spreading uses `core/similarity.nova` for cross-KG reference weights. Predictive bias is carried by `SIG_PREDICTIVE` signals on `core/signal.nova`'s extended tag space; mismatch raises `SIG_ERROR`. Reuse learned gates from ADR-009 for routing settled interpretations.
Testing: fixture `tests/reader_settle.nova` feeds canned token streams to a pre-seeded language KG and asserts the settled atom set and tick count; a polysemy fixture asserts context bias flips the chosen sense.
DEPENDS ON: NOVA enhancement #6 — extended signal tag space for `SIG_PREDICTIVE`/`SIG_ERROR`. DEPENDS ON: NOVA enhancement #8 — multi-KG cross-reference edges for spreading activation. DEPENDS ON: NOVA enhancement #12 — Hebbian + error-driven plasticity kernels so the predictive layer learns.

---

# ADR-012: Reader five stages (lexical anchor, context bias, spreading activation, coherence check, fetch/route/learn)

Status: Proposed
Date: 2026-05-24

## Context
ADR-011 chose the Option 5 hybrid reader but deliberately deferred its internal structure. This ADR specifies that structure: the five concrete stages through which incoming language becomes settled substrate activity and routed signals. We need this specified now because the reader sits on the critical path of every interaction; its stage boundaries determine where gates route (ADR-009), where signals are typed (ADR-008), where learning hooks attach (ADR-007, ADR-024), and where the system decides it does not know something and must learn (ADR-026, ADR-028).

The constraint is the 100Hz substrate tick (ADR-037) layered on event-driven coordination: a normal utterance must settle within a small number of ticks, while genuinely novel input may legitimately spill into a slower fetch/learn path. The stages must therefore be a graded pipeline — fast common case, explicit slow case — not a fixed-cost monolith. As always: 2 founders, 8h/day, bootstrapping; the design must be implementable incrementally and testable stage by stage.

## Decision
The reader runs **five ordered stages**, each emitting typed signals that the next consumes; stages overlap across ticks rather than blocking.

1. **Lexical anchor.** Incoming surface tokens (from text, or from the STT modality bridge — ADR-014) are matched to word/phoneme atoms in the language KG (ADR-015). Each match fires the anchoring `NTYPE_PERCEIVER` first nodes (ADR-010) of the perception part, emitting `SIG_SENSORY` signals tagged with the matched atom ids. Unmatched tokens emit a low-confidence anchor plus a `SIG_CURIOSITY` marker for stage 5.
2. **Context bias.** Before activation spreads freely, current context — the active concepts from the last few moments (ADR-021), soul state (ADR-034), and the running goal set — injects `SIG_PREDICTIVE` signals that pre-weight likely senses and likely next concepts. This is the predictive half of the Option 5 hybrid; it disambiguates polysemy and primes the spread so it converges quickly.
3. **Spreading activation.** Anchored, biased activation propagates across synapses and cross-KG reference edges (ADR-017) via `SIG_EXCITATORY`/`SIG_INHIBITORY` signals (ADR-008). `NTYPE_KNOWER` nodes accumulate activation; inhibition suppresses competing interpretations. The substrate settles toward the most coherent concept set — this is where meaning is actually constructed, not parsed.
4. **Coherence check.** The settled pattern is evaluated for internal consistency: do the co-active atoms mutually reference and predict one another, or is activation diffuse/contradictory? A `SIG_BINDING` pass groups mutually-supporting atoms; residual `SIG_ERROR` signals measure mismatch between top-down predictions (stage 2) and the bottom-up settle (stage 3). High coherence -> accept; low coherence -> escalate to stage 5.
5. **Fetch / route / learn.** On a coherent, known interpretation, the reader routes `SIG_EVENT`/`SIG_REQUEST` signals through learned gates (ADR-009) to the relevant KG and reasoning parts. On low coherence or unmatched anchors, it triggers learning: ask-the-user (ADR-027), or whitelisted internet fetch (ADR-028), gated by "learned enough" thresholds (ADR-030). Either way, Hebbian + error-driven plasticity (ADR-007) updates anchor strengths, bias weights, and cross-KG references so the next encounter is faster — closing the predictive-coding loop (ADR-024).

## Options Considered
1. **Single-pass associative settle (no explicit stages).** Simpler to write. Rejected: no clean place to inject prediction, measure coherence, or trigger learning; un-debuggable; cannot separate fast/slow paths.
2. **Strict blocking pipeline (each stage fully completes before the next).** Easy to reason about. Rejected: violates the 100Hz budget — blocking on spreading activation for long input stalls every other loop. Chosen design overlaps stages across ticks instead.
3. **Three stages (anchor, activate, route) without separate bias/coherence.** Leaner. Rejected: folding bias into activation loses the predictive sharpening that makes ADR-011's hybrid work, and folding coherence into routing removes the explicit "I don't understand" signal that drives self-learning (ADR-026). The five-stage split (CHOSEN) makes prediction and coherence first-class.

## Consequences
- **Positive:** Clear stage boundaries give precise hooks for gating, typing, learning, and auditing; fast common case stays within the tick budget while novel input flows to an explicit learn path; coherence check yields a principled "unknown" trigger; each stage is independently testable.
- **Negative:** Five interacting stages with overlap across ticks are more complex to schedule and debug than a single settle; coherence thresholds and bias gains require empirical tuning; mis-tuned bias can over-commit to a wrong sense before stage 4 catches it.
- **Future work:** Stage 5 is the integration point for ADR-026/027/028/030; stage 2's predictive signals generalize into ADR-024 predictive coding; stage 1 depends on the language-atom schema in ADR-015.

## Implementation Notes
Implement each stage as a driver function in `crossengin/reader/reader.nova`: `reader_anchor`, `reader_bias`, `reader_spread`, `reader_cohere`, `reader_route`, sharing a `reader_state` map keyed `{active_anchors, bias_vec, settle, coherence, route_targets}`. Anchoring/spreading read the language KG and other KGs via `core/knowledge.nova` + `core/similarity.nova`. Signals use the extended `core/signal.nova` tag space; routing reuses ADR-009 gates over `core/channel.nova` `CHAN_FILTERED`/`CHAN_WEIGHTED`. Coherence binding uses `SIG_BINDING`; learning hooks call into the ADR-007 plasticity kernels.
Testing: per-stage fixtures under `tests/reader/` — `anchor_unknown.nova` (asserts `SIG_CURIOSITY` on OOV token), `bias_polysemy.nova` (asserts sense flip), `cohere_escalate.nova` (asserts low coherence triggers stage-5 learn path).
DEPENDS ON: NOVA enhancement #6 — extended signal tags. DEPENDS ON: NOVA enhancement #7 — learned content-based gate routing for stage 5. DEPENDS ON: NOVA enhancement #5 — 100Hz tick fused with event-driven coordination so stages can overlap across ticks.

---

# ADR-013: Output generation: pure substrate, no LLM

Status: Proposed
Date: 2026-05-24

## Context
CrossEngin must produce language: answers, questions back to the user (ADR-027), descriptions of its own state (ADR-038). The industry-default way to do this is to hand a context buffer to an LLM and stream tokens back. CrossEngin rejects this. Per §2 and ADR-014, output is pure-substrate generation: it flows from concept activation patterns down through language nodes to motor effectors, with NO LLM anywhere in the path. This ADR fixes the output mechanism, the mirror image of the reader (ADR-011/012).

The reason is foundational, not stylistic. If an LLM generates output, then the LLM — not the substrate — is choosing what the system says, which means it is doing the cognition that CrossEngin exists to do in the substrate (ADR-001). Output would become unauditable (we could not trace a sentence back through the decision log, ADR-043), unlearnable in our framework, and severed from the soul's identity and values (ADR-034). The hard question this raises — how do you get fluent language without a language model? — is exactly what this ADR must answer.

Constraints: 2 founders, 8h/day, bootstrapping, 18-30 month v1. We cannot train a generator. Fluency must therefore emerge from the same language atoms (ADR-015) and substrate dynamics already built for the reader, reused in the production direction.

## Decision
We adopt **pure-substrate output generation**. Generation is the reverse flow of comprehension. A communicative intent — a settled pattern of active concept atoms produced by the reasoning/goal loops — propagates downward: active concepts emit `SIG_EXCITATORY` signals to the language nodes that name them (the same word/phoneme/syntax atoms of ADR-015 that the reader anchored to), syntax-pattern atoms sequence them via `SIG_BINDING` and ordering constraints, and the resulting ordered language signals drive `NTYPE_ACTOR` motor-effector nodes (ADR-006) that render text — or hand phonemes to the TTS modality bridge (ADR-014).

Fluency without a language model comes from three substrate sources: (a) the language KG stores not just words but learned syntax-pattern atoms and collocations, so well-formed sequences are high-weight paths that win the downward spread; (b) the same predictive machinery used in comprehension (ADR-012 stage 2, ADR-024) runs forward here, predicting the next language node and pruning ill-formed continuations via `SIG_INHIBITORY`; (c) Hebbian + error-driven plasticity (ADR-007) strengthens phrasings that the user accepts and weakens awkward ones, so fluency is learned and personalized over time. The soul (ADR-034) and emotion system (ADR-035) modulate tone by biasing which language atoms activate.

## Options Considered
1. **LLM generation (or LLM "polish" of substrate drafts).** Maximally fluent. Rejected on principle (ADR-014, §2): any LLM in the output path IS cognition, is unauditable, and breaks the substrate thesis. Even "polish-only" lets the LLM choose final wording — disqualifying.
2. **Fixed templates / grammar-based surface realization.** Fully controllable, no LLM, cheap to start. Rejected as the primary mechanism: rigid, doesn't learn, can't personalize, and produces stilted output — though template fallbacks may seed the cold-start language KG.
3. **Statistical n-gram surface generator.** Learns phrasing, no LLM. Rejected as standalone: external to the substrate, severed from concept activation and soul, and shallow. Its insight (sequence statistics matter) is absorbed into the syntax-pattern atoms and predictive pruning of the chosen design.
4. **Pure-substrate downward generation (CHOSEN).** Concept activation -> language nodes -> motor effectors, with learned syntax atoms and predictive pruning supplying fluency. Keeps generation in the substrate, auditable, learnable, soul-modulated. Weaker fluency at cold start, but improves with use and honors every principle.

## Consequences
- **Positive:** Output is fully in-substrate, auditable end-to-end, and traceable to the concepts and goals that produced it; fluency is learned and personalized; tone is governed by soul/emotion, not a foreign model; one language KG and one predictive mechanism serve both reading and writing.
- **Negative:** Cold-start output is markedly less fluent than an LLM and may need template scaffolding early; building learned syntax-pattern atoms is substantial work (ADR-015); long, complex utterances are hard to keep coherent via spreading alone and will need ordering/coherence safeguards analogous to the reader's stage 4.
- **Future work:** ADR-015 must define syntax-pattern atoms rich enough to carry word order and agreement; ADR-038 builds the self-description API on this path; ADR-027's clarifying questions are generated here; ADR-024 supplies the forward predictive pruning.

## Implementation Notes
Implement in `crossengin/output/generate.nova`: `gen_from_intent(active_concepts)` -> downward spread, `gen_sequence` applying syntax-pattern atoms via `SIG_BINDING`, `gen_emit` driving `NTYPE_ACTOR` nodes from `core/node.nova`. Reuse the language KG accessors (`core/knowledge.nova`) and `SIG_EXCITATORY`/`SIG_INHIBITORY`/`SIG_PREDICTIVE` from `core/signal.nova`. Soul/emotion bias hooks read `core/soul.nova` and `mind/emotion.nova`. Phoneme output for speech is handed to `runtime/llm.nova` + `runtime/llm_bridge.c` strictly as TTS modality (ADR-014) — never for word choice.
Testing: `tests/output/intent_to_text.nova` asserts a fixed active-concept set yields a well-formed sentence; `tests/output/no_llm_path.nova` asserts (via trace inspection) that no signal in the generation trace ever enters the LLM bridge except the final TTS hand-off.
DEPENDS ON: NOVA enhancement #14 — STT/TTS bridge isolation guaranteeing no cognition path. DEPENDS ON: NOVA enhancement #12 — plasticity kernels for learned fluency. DEPENDS ON: NOVA enhancement #6 — extended signal tags for binding/prediction.

---

# ADR-014: No-LLM cognition principle (LLM-bridge only for STT/TTS modality)

Status: Proposed
Date: 2026-05-24

## Context
CrossEngin is built on NOVA, which ships an LLM bridge (`runtime/llm.nova` + `runtime/llm_bridge.c`) and LLM-flavored agent modules (`agent/cognitive_llm.nova`, `agent/rag.nova`). Their presence is a standing temptation: at every hard step — comprehension (ADR-011/012), reasoning (ADR-031), output (ADR-013), knowledge retrieval (ADR-017) — it would be faster for 2 founders to "just call the model." This ADR exists to make that impossible by principle and by enforcement, because the temptation will recur on nearly every other ADR and must have one authoritative ruling to point to.

The principle is foundational to CrossEngin's identity (§2): intelligence must emerge from substrate dynamics (ADR-001), not from an opaque external model. If an LLM does the cognition, then CrossEngin is a wrapper around an LLM — unauditable (its choices cannot be traced in the decision log, ADR-043), unlearnable in our Bayesian/Hebbian framework (ADR-007, ADR-023), and severed from the soul (ADR-034). The capability tests in ADR-049 explicitly include no-LLM-cognition verification; this ADR defines what that test enforces.

The legitimate need that remains is modality. Users may want to speak and listen. Speech-to-text and text-to-speech are signal-format conversions, not cognition. Drawing that line precisely is the whole job of this ADR.

## Decision
We adopt the **NO-LLM-COGNITION principle as a hard, non-negotiable constraint.** The system NEVER uses an LLM for cognition — not for comprehension, knowledge retrieval, reasoning, planning, output generation, or self-modeling. The ONLY permitted use of the NOVA LLM bridge is STT/TTS modality conversion at the system's sensory/motor boundary: raw audio -> token surface forms on the way in, and phoneme/text -> audio on the way out (enhancement #14).

The line is drawn architecturally, not by convention. The LLM bridge is reachable only from two named adapters — `crossengin/io/stt_adapter.nova` and `crossengin/io/tts_adapter.nova` — which sit OUTSIDE the substrate. The STT adapter's only output is a token stream into the reader's lexical-anchor stage (ADR-012 stage 1); it produces no concepts, no atoms, no interpretation. The TTS adapter's only input is already-generated phonemes from the pure-substrate output path (ADR-013); it makes no word choices. No substrate node (`core/node.nova`), gate (ADR-009), or signal path (`core/path.nova`) may carry a reference into the bridge. The LLM-flavored agent modules (`agent/cognitive_llm.nova`, `agent/rag.nova`) are NOT used by CrossEngin.

## Options Considered
1. **Allow LLM as a fallback when the substrate is uncertain.** Pragmatic; would improve early answers. Rejected: the fallback becomes a crutch the substrate never outgrows, every fallback answer is unauditable and unlearnable, and the boundary erodes immediately. Directly violates §2.
2. **Allow LLM for "non-core" tasks (summarization, retrieval) but not final reasoning.** Seemingly narrow. Rejected: summarization and retrieval ARE cognition (they decide what matters); this is the camel's nose. There is no stable line short of modality-only.
3. **Soft principle enforced by code review / convention only.** Cheap. Rejected: with 2 founders under time pressure, convention fails exactly when it matters; the principle is too foundational to leave unenforced. We need an architectural seam plus a test.
4. **Hard principle, modality-only bridge, enforced by isolation + test (CHOSEN).** The bridge is reachable only via two boundary adapters; an automated test verifies no cognition path touches it. Preserves the substrate thesis, auditability, and learnability, while still allowing voice I/O.

## Consequences
- **Positive:** CrossEngin's core thesis is protected and enforceable, not aspirational; all cognition is auditable (ADR-043) and learnable (ADR-007, ADR-023); the system genuinely owns its competence and can report it honestly (ADR-020, ADR-038); voice I/O remains available without compromise.
- **Negative:** Forgoes the easy fluency/coverage an LLM would give, especially at cold start — the substrate must earn every capability; comprehension and output (ADR-011/013) are weaker early; founders must resist a constant pragmatic pull.
- **Future work:** ADR-049 implements the automated no-LLM-cognition verification test; ADR-046/047 must ensure deployment configs never wire the bridge into a cognition path; ADR-028 (internet fetch) must route retrieved text through the reader, not an LLM.

## Implementation Notes
Enforcement seam: confine all imports of `runtime/llm.nova` / `runtime/llm_bridge.c` to `crossengin/io/stt_adapter.nova` and `crossengin/io/tts_adapter.nova`. Provide `stt_to_tokens(audio) -> tokens` (feeds ADR-012 stage 1) and `tts_from_phonemes(phonemes) -> audio` (consumes ADR-013 output). Add a build-time/CI guard (`tests/no_llm_cognition.nova`) that statically asserts no module under `crossengin/reader/`, `crossengin/output/`, `mind/`, or `agent/agent.nova` references the bridge symbols, and a runtime trace assertion that no `SIG_*` trace path (`core/signal.nova` trace field) ever visits a bridge node. Explicitly exclude `agent/cognitive_llm.nova` and `agent/rag.nova` from the CrossEngin build manifest in `pkg/pkg.nova`.
DEPENDS ON: NOVA enhancement #14 — STT/TTS modality bridge isolation guaranteeing no cognition path through `runtime/llm.nova` + `runtime/llm_bridge.c`.

---

# ADR-015: Language atoms in substrate (words, phonemes, syntax patterns as atoms)

Status: Proposed
Date: 2026-05-24

## Context
The reader (ADR-011/012) anchors surface tokens to "language atoms," and the output path (ADR-013) realizes concepts through "language nodes" and "syntax-pattern atoms." Both presuppose that language itself is represented IN the substrate as data the system can learn and change. This ADR defines that representation. It must be decided now because it is the shared substrate that comprehension and generation both stand on, and because storing language as atoms (rather than as a hard-coded lexicon or an external model) is what makes the NO-LLM-COGNITION principle (ADR-014) actually workable.

The constraint is consistency with the substrate model (§2): everything persistent is an ATOM, mutable and KG-stored (ADR-016), living in domain-organized KGs (ADR-004, ADR-017). Language must obey the same rules — no privileged hard-coded dictionary, no frozen grammar. A 2-founder team cannot hand-author and maintain a large lexicon and grammar anyway; language must be learned and grow like every other domain. The open question is the schema: what exactly is a word atom, a phoneme atom, a syntax-pattern atom, and how do they reference concept atoms in other KGs.

## Decision
We store **words, phonemes, and syntax patterns as mutable atoms in a dedicated language KG** (`KG-language`), structured per the general atom design of ADR-016 and integrated via the multi-KG cross-reference mechanism of ADR-017.

Three atom kinds, all built with `atom_new` and carrying Bayesian confidence (alpha/beta via `core/belief.nova`):
- **Word atoms:** surface form + cross-KG references to the concept atom(s) they name (in `KG-medicine`, `KG-general`, etc.), weighted by `core/similarity.nova`. Polysemy = multiple weighted references; the reader's context bias (ADR-012 stage 2) selects among them.
- **Phoneme atoms:** sound units referenced by word atoms, used at the modality boundary by the STT/TTS adapters (ADR-014). They let the system align spoken and written forms without an LLM.
- **Syntax-pattern atoms:** learned ordering/agreement templates (e.g., a slot pattern over concept roles) that sequence word atoms during generation (ADR-013) and group them during the reader's binding/coherence stage (ADR-012 stage 4).

All three are LEARNED and MUTABLE. New words are born from co-activation when an unknown token co-occurs reliably with a concept (atom birth, ADR-025) — often via ask-the-user (ADR-027) or fetch (ADR-028). Confidence updates with use (ADR-023); weak, stale language atoms decay and are GC'd (ADR-025). Syntax-pattern atoms strengthen via Hebbian + error-driven plasticity (ADR-007) when phrasings succeed. `KG-language` is thus a first-class learning domain, not configuration.

## Options Considered
1. **Hard-coded lexicon + grammar tables (compiled in).** Fast, deterministic, no cold start. Rejected: immutable and unlearnable, violates the substrate model (§2) and the everything-is-an-atom rule (ADR-016), unmaintainable by 2 founders at scale, and cannot personalize or acquire new terms — exactly the brittleness ADR-011 rejected.
2. **Embeddings-only (words as vectors, no discrete atoms).** Smooth similarity, integrates with concept layer (ADR-018). Rejected as the representation: vectors alone can't carry discrete cross-KG references, Bayesian confidence, or syntax structure, and aren't individually auditable/mutable as units. Embeddings are retained as a FACET of word atoms (multi-vector, ADR-018), not the whole.
3. **Language baked into the concept layer (no separate language KG).** Fewer moving parts. Rejected: conflates "the concept of a dog" with "the word dog" and "the sound /dawg/"; a single concept may have many words across registers/languages, and words decay/change independently of concepts. A dedicated `KG-language` with cross-refs keeps these orthogonal (ADR-017).
4. **Words/phonemes/syntax as mutable atoms in a dedicated language KG (CHOSEN).** Obeys the substrate and atom models, learnable and auditable, cleanly separated from concepts yet linked by weighted cross-refs, and shared identically by reader and output. Cold-start weakness is accepted and mitigated by ADR-027/028 seeding.

## Consequences
- **Positive:** Language is just another learnable, auditable domain — no privileged hard-coding; comprehension (ADR-012) and generation (ADR-013) share one representation; polysemy, multilingualism, and personalized vocabulary fall out naturally from weighted cross-refs; supports NO-LLM-COGNITION by giving the substrate its own linguistic knowledge.
- **Negative:** Cold start with an empty `KG-language` is weak and depends heavily on early teaching (ADR-027) and fetch (ADR-028); syntax-pattern atoms are a hard representational problem (encoding order/agreement as atoms) and the riskiest part of this ADR; large language KGs stress the multi-KG indexing of ADR-017.
- **Future work:** ADR-016 fixes the concrete atom layout this builds on; ADR-018 integrates word embeddings as a multi-vector facet; ADR-025 governs language-atom birth/death; ADR-027/028 seed and grow `KG-language`; ADR-039 (theory of mind) may add per-user vocabulary cross-refs.

## Implementation Notes
Define `crossengin/language/lang_atoms.nova`: tag constants `ATOM_WORD`, `ATOM_PHONEME`, `ATOM_SYNTAX`; constructors `word_atom_new(form, concept_refs)`, `phoneme_atom_new(symbol)`, `syntax_atom_new(slot_pattern)`; accessors for surface form, references, and alpha/beta. Store all in `KG-language` via `core/knowledge.nova`; cross-KG references use `core/similarity.nova` weights per ADR-017. Confidence via `core/belief.nova`; plasticity for syntax patterns via the ADR-007 kernels. The reader (`crossengin/reader/reader.nova`) and output (`crossengin/output/generate.nova`) both import this module — it is their shared substrate.
Testing: `tests/language/word_birth.nova` asserts an unknown token + repeated concept co-activation creates a `word_atom` (ADR-025); `tests/language/polysemy_refs.nova` asserts a word atom holds multiple weighted concept references and the reader selects by context; `tests/language/syntax_order.nova` asserts a syntax-pattern atom imposes correct word order in generation.
DEPENDS ON: NOVA enhancement #8 — multi-KG namespacing + cross-KG reference edges with similarity weights (for `KG-language` and word->concept refs). DEPENDS ON: NOVA enhancement #12 — plasticity kernels so syntax-pattern atoms learn from successful phrasings.

---

# ADR-016: Atom design (mutable, KG-stored, cross-KG referenced, Bayesian confidence)

Status: Proposed
Date: 2026-05-24

## Context
The atom is the persistent unit of knowledge in CrossEngin. As defined in ADR-002, nodes produce atoms only for novel patterns, atoms live in domain-specific KGs, and nodes can read atoms they did not create. Before we can build the multi-KG layer (ADR-017), the concept layer (ADR-018), procedural memory (ADR-019), or belief refinement (ADR-023), we need one canonical atom representation that every part of the substrate agrees on. Getting this layout wrong is expensive: atoms are the most numerous persistent objects (millions per KG), are read on nearly every reasoning step, and must be serialized in the persistence snapshot (ADR-048).

The hard requirement is that an atom must be (1) mutable — updated as new evidence arrives rather than re-created, so that identity is stable across learning; (2) confidence-bearing — every atom carries a Bayesian belief so the system can reason about how much it trusts a fact and decay it over time; (3) cross-KG referable — an atom in KG-medicine can point at an atom in KG-biology without copying it, which is how cross-domain concepts are built; and (4) cheap to read foreign — a reasoner node in another part must be able to dereference and evaluate an atom it never produced.

Constraints: 2 founders at 8h/day on a bootstrap budget mean we cannot afford a bespoke object database; we reuse `core/knowledge.nova` for storage and `core/belief.nova` for confidence rather than inventing parallel machinery. NOVA values are tag-prefixed lists/maps, so the atom must read as a normal NOVA structure with a constructor and accessors, and must serialize through `runtime/json.nova` / `runtime/db.nova` for snapshots.

## Decision
We define the atom as a tag-prefixed NOVA structure with the layout `[TAG_ATOM, id, kg_id, kind, label, payload, belief, embed_ref, xrefs, provenance, created_moment, updated_moment, version]`. `id` is a KG-local stable identifier; `kg_id` names the owning KG (ADR-017); `kind` is one of `ATOM_FACT`, `ATOM_RELATION`, `ATOM_CONCEPT`, `ATOM_SKILL`, `ATOM_LANG` (the language atoms of ADR-015) and `ATOM_RULE` (procedural, ADR-019); `payload` is a kind-specific map; `belief` is a `core/belief.nova` (alpha/beta) handle; `embed_ref` references the multi-vector embedding held by the concept layer (ADR-018); `xrefs` is a list of cross-KG reference edges (ADR-017); `provenance` records source tier (ADR-029) and producing node/part; `version` increments on every mutation.

Confidence is Bayesian, not a scalar. We do NOT store a float "confidence". We store alpha/beta counts via `belief_new(alpha0, beta0)` and expose `atom_confidence(a)` which returns the posterior mean `alpha / (alpha + beta)` through `runtime/confidence.nova`. Supporting evidence calls `atom_observe(a, +1)` (increment alpha); contradicting evidence calls `atom_observe(a, -1)` (increment beta). This gives us both an expectation and a variance, so the system distinguishes "0.7 from 3 observations" from "0.7 from 300 observations" — essential for the self-learning thresholds in ADR-030 and conflict handling in ADR-023.

Mutation is in-place by identity. `atom_update(a, payload_delta)` merges new payload fields, bumps `version`, sets `updated_moment`, and leaves `id`/`kg_id` fixed so all inbound synapses and xrefs remain valid. Atoms are never silently replaced; superseding facts are recorded as evidence against the old belief, which is how decay-based death (ADR-025) eventually garbage-collects an atom whose posterior mean falls below the GC threshold.

## Options Considered
**Immutable atoms with versioned append (event-sourced).** Every change writes a new atom and supersedes the old one. Rejected as the default: it breaks reference stability (every xref and synapse would need rewriting on each update), multiplies storage for the millions of atoms per KG, and makes "the current belief about X" a query rather than a field. We keep an append-only *audit* trail at the decision-log level (ADR-043) but not at the atom level.

**Scalar confidence float instead of alpha/beta.** Simpler and smaller. Rejected because a single float cannot express evidence volume or support principled decay and conflict resolution; ADR-023, ADR-029 and ADR-030 all require the count-based posterior. Reusing `core/belief.nova` costs us nothing extra since it already exists.

**Atoms as opaque blobs keyed in one global KG.** Store all knowledge in a single `core/knowledge.nova` instance with a domain field. Rejected in favor of multi-KG (ADR-004 organizational decision, ADR-017 mechanism): a global store defeats domain-local spreading activation in the reader (ADR-012) and makes cross-tenant isolation in v2 (ADR-047) far harder. The `kg_id` field on every atom is what makes namespacing cheap.

**Embedding stored inline on the atom.** Rejected: multi-vector embeddings (ADR-018) are large and shared across the concept hierarchy; we store an `embed_ref` and let the concept layer own the vectors, keeping the atom small enough to keep millions resident.

## Consequences
- **Positive:** One uniform, small, serializable knowledge unit usable by every part. Stable identity under mutation keeps synapses and cross-KG references valid for the life of the atom. Bayesian confidence is first-class, enabling principled learning-enough decisions (ADR-030), conflict handling (ADR-023), and decay-based GC (ADR-025). Reuse of `core/belief.nova` and `core/knowledge.nova` minimizes founder effort.
- **Negative:** In-place mutation means we must be disciplined about the audit trail living elsewhere (ADR-043) to retain history. The `version` field and `updated_moment` add bookkeeping on every write. Cross-KG dereference cost is paid on read; hot atoms may need a small resident cache.
- **Future work:** ADR-017 defines how `xrefs` are formed and weighted; ADR-018 defines `embed_ref` and concept promotion of atoms; ADR-023 refines decay and conflict on `belief`; ADR-025 sets the birth/death thresholds that act on `belief` posterior mean and `updated_moment`.

## Implementation Notes
Add an `atom` module layered on `core/knowledge.nova`: `atom_new(kg_id, kind, label, payload)` (initializes `belief_new(1,1)` as a uniform prior, sets `created_moment` from `core/moment.nova`, `version=0`); accessors `atom_id`, `atom_kg`, `atom_kind`, `atom_payload`, `atom_belief`, `atom_xrefs`, `atom_confidence`; mutators `atom_update`, `atom_observe`, `atom_add_xref`. Tag constants `TAG_ATOM`, `ATOM_FACT|RELATION|CONCEPT|SKILL|LANG|RULE` live next to the existing `core/knowledge.nova` tags. Serialize via `runtime/json.nova` and persist through `runtime/db.nova` for the snapshot (ADR-048). Test fixtures: an atom round-trips through update/observe with stable `id`; `atom_confidence` matches the alpha/beta posterior mean from `runtime/confidence.nova`; a foreign part reads and evaluates an atom it did not create. DEPENDS ON: NOVA enhancement #8 — multi-KG namespacing + cross-KG reference edges (the `kg_id`/`xrefs` fields rely on it). No LLM is involved in atom creation, mutation, or evaluation (ADR-014).

---

# ADR-017: Multi-KG with cross-references (spawn-on-new-domain, similarity-weighted cross-refs, automatic and earned link formation)

Status: Proposed
Date: 2026-05-24

## Context
ADR-004 made the organizational decision that CrossEngin stores knowledge in many domain-specific KGs (KG-medicine, KG-biology, …) rather than one monolith, with cross-references linking related concepts across domains. This ADR specifies the *mechanism*: when a new KG is spawned, how cross-KG reference edges are created and weighted, and the difference between automatically formed links and links that must be earned. ADR-016 already gave every atom a `kg_id` and an `xrefs` list; here we define what populates and weights those xrefs and what triggers a new `kg_id` to exist at all.

This must be decided now because the reader's spreading-activation stage (ADR-012) traverses cross-KG references, the concept layer (ADR-018) builds cross-domain concepts on top of them, and self-directed learning (ADR-026) frequently encounters material in a domain the system has never separated before. Without a spawn heuristic the system either dumps everything into one KG (defeating domain-local activation and v2 tenant isolation, ADR-047) or fragments into thousands of tiny KGs.

Constraints: 2 founders, 8h/day, bootstrap. We cannot hand-curate a domain taxonomy. Spawning and linking must be automatic, driven by substrate signals and vector similarity, and cheap enough to run online. We build directly on `core/knowledge.nova` for the stores and `core/similarity.nova` for the cosine weighting of cross-references.

## Decision
**Spawn-on-new-domain heuristic.** A new KG is spawned when a cluster of recently created atoms is persistently *dissimilar* from every existing KG centroid yet *self-coherent*. Concretely: each KG maintains a running centroid embedding. When a window of N=200 newly produced atoms (over a moment window) has mean max-similarity to all existing KG centroids below `SPAWN_DISSIM = 0.35` (via `core/similarity.nova`), AND the cluster's internal mean pairwise similarity exceeds `SPAWN_COHERE = 0.55`, the meta part calls `kg_spawn(label)`, allocates the new KG namespace, and migrates the cluster's atoms into it (their `id` stays, `kg_id` changes, xrefs are preserved). This prevents both premature splitting (incoherent noise) and a runaway monolith.

**Similarity-weighted cross-references.** A cross-KG reference is an edge `[XREF, src_atom, dst_kg, dst_atom, weight, kind, earned]`. `weight` is the cosine similarity of the two atoms' embeddings (`similarity_cosine` over `embed_ref`, ADR-018), recomputed lazily and decayed if not reinforced. `kind` is `XREF_SIMILAR`, `XREF_CAUSAL`, `XREF_ANALOGICAL`, or `XREF_PARTOF`. The reader's spreading activation (ADR-012) propagates activation across an xref scaled by `weight`, so strong cross-domain links carry more signal.

**Automatic vs earned links.** *Automatic* links (`earned=false`) form when two atoms exceed `XREF_AUTO = 0.82` similarity at creation/update time — cheap, embedding-only, and revocable if similarity later decays. *Earned* links (`earned=true`) form only after repeated co-activation in successful reasoning or confirmed predictions: an `XREF_CAUSAL` or `XREF_ANALOGICAL` edge is promoted to earned once it has been co-activated and not contradicted across `EARN_K = 5` distinct moments, at which point its `weight` is floored at 0.5 and it resists similarity decay. Earned links are how the system encodes hard-won cross-domain insight that raw embedding proximity would never capture (e.g., a medicine→economics analogy).

## Options Considered
**Single monolithic KG with a domain tag (no spawning).** Simplest. Rejected (consistent with ADR-004): domain-local spreading activation degrades when every atom is in one graph, cross-tenant isolation for v2 (ADR-047) becomes a query-time filter rather than a structural boundary, and the centroid signal that drives curiosity-based learning (ADR-026) disappears.

**Manual/predeclared domain taxonomy.** An engineer defines the KGs up front. Rejected: 2 founders cannot anticipate the domains a continuously learning companion will enter, and a fixed taxonomy contradicts the self-directed-learning thesis. The spawn heuristic lets domains emerge from the data.

**Pure embedding-similarity links only (no earned tier).** All cross-refs are cosine-weighted and nothing is "earned." Rejected: embedding proximity captures surface similarity but misses causal/analogical structure discovered through reasoning; without an earned tier those edges would decay away between uses. We keep automatic links for breadth and earned links for durable insight.

**Spawn purely on atom count per topic.** Split a KG when it exceeds a size threshold. Rejected: size is not domain-ness; it would split coherent large domains and merge unrelated small ones. Similarity-coherence is the right signal.

## Consequences
- **Positive:** Domains emerge automatically and stay coherent; cross-domain reasoning is supported by weighted edges that the reader can traverse; the automatic/earned distinction lets cheap links scale while durable insight is protected from decay. Structural KG boundaries give v2 tenant isolation (ADR-047) for free.
- **Negative:** Spawn/merge thresholds (`SPAWN_DISSIM`, `SPAWN_COHERE`, `XREF_AUTO`, `EARN_K`) are tuning parameters that need empirical calibration during the multi-day test (ADR-049). Migrating a cluster into a new KG is a non-trivial transactional operation that must be crash-safe (ADR-048). Lazy xref-weight recomputation adds bookkeeping.
- **Future work:** A KG-merge operation (inverse of spawn) for domains that converge. ADR-018 consumes xrefs to build cross-domain concept nodes. ADR-029 source-authority tiers feed xref provenance. ADR-025's decay GC must also prune dead xrefs.

## Implementation Notes
Extend `core/knowledge.nova` with a `kg_registry` (map of `kg_id -> {centroid, atom_index}`) and constructors `kg_spawn(label)`, `kg_centroid(kg_id)`, plus xref ops `xref_new(src, dst_kg, dst_atom, kind)`, `xref_weight(x)` (delegates to `core/similarity.nova` `similarity_cosine`), `xref_promote_earned(x)`. Tag constants `TAG_XREF`, `XREF_SIMILAR|CAUSAL|ANALOGICAL|PARTOF`. The spawn evaluator runs in the meta part on a slow cadence (not every 100Hz tick — ADR-037 event-driven layer). Test fixtures: feeding a coherent off-domain atom cluster triggers exactly one `kg_spawn`; an automatic xref above 0.82 forms and later drops below threshold and is pruned; a co-activated causal xref reaches earned status after 5 moments and survives a similarity-decay pass. DEPENDS ON: NOVA enhancement #8 — multi-KG namespacing + cross-KG reference edges with similarity weights. This is the mechanism realizing ADR-004's organizational decision; cross-reference ADR-016 (atom `xrefs`/`kg_id`), ADR-012 (spreading activation), ADR-018 (concepts over xrefs). No LLM participates in spawning or linking (ADR-014).

---

# ADR-018: Concept layer evolution (hierarchy, schemas, multi-vector embeddings, integration with multi-KG)

Status: Proposed
Date: 2026-05-24

## Context
NOVA ships a concept layer (`core/concept.nova`) with multi-vector embeddings. CrossEngin needs more than the base: a concept must sit at the top of an abstraction hierarchy over the per-domain atoms of ADR-016, carry a *schema* (typed slots) so it can structure knowledge rather than just cluster it, hold *multiple* embedding vectors capturing different facets of meaning, and span the multiple KGs introduced in ADR-017. Concepts are what the reader activates during comprehension (ADR-012), what output generation flows down from (ADR-013), what theory-of-mind models the user with (ADR-039), and what reasoning operates over (ADR-031). The base layer is a clustering primitive; we must evolve it into a structured, cross-domain abstraction layer.

This decision is needed now because ADR-017's cross-KG references are the raw material from which cross-domain concepts are assembled, and the self-model (ADR-020) and theory-of-mind (ADR-039) both depend on concepts having rich, schema-typed properties. Deferring it would force ad-hoc concept handling into each consumer.

Constraints: 2 founders, 8h/day, bootstrap. We extend `core/concept.nova` rather than rewrite it, reuse `core/similarity.nova` for facet matching, and keep concept vectors out of the atom (ADR-016 stores only an `embed_ref`) so atoms stay small.

## Decision
**Hierarchy.** A concept is `[TAG_CONCEPT, id, parents, children, schema, vectors, members, kg_span, salience]`. `parents`/`children` form a DAG (multiple inheritance allowed: "antibiotic" is-a "drug" and is-a "chemical-compound"). Member atoms attach at the most specific concept; activation and property inheritance flow up `parents`. Promotion is automatic: when a set of atoms across one or more KGs shares schema slots and clusters tightly (mean pairwise `similarity_cosine` > `CONCEPT_PROMOTE = 0.7`), `concept_promote(members)` creates or attaches a concept node above them.

**Schemas.** Each concept carries a `schema`: a map of typed slots (e.g. drug → {mechanism, dose_range, contraindications, evidence_tier}). Slots are filled by member atoms and inherited by children; an unfilled slot on a frequently activated concept is a concrete *imagination gap* that triggers self-directed learning (ADR-026). Schemas are themselves learned and mutable — a slot is added when ≥`SCHEMA_K = 3` members independently exhibit a shared property dimension.

**Multi-vector embeddings.** Each concept holds `vectors` = a small map of named facets: `VEC_LEXICAL` (surface/word form, ties to language atoms ADR-015), `VEC_SEMANTIC` (meaning), `VEC_RELATIONAL` (its role in the xref graph), and optionally `VEC_AFFECTIVE` (valence/arousal association from ADR-035). The reader and similarity queries select the facet relevant to the task, so lexical lookup and semantic reasoning use different vectors of the same concept. This is the evolution of `core/concept.nova`'s existing multi-vector support into named, task-selected facets.

**Multi-KG integration.** `kg_span` lists the KGs whose atoms are members. A concept is *cross-domain* iff `len(kg_span) > 1`; such concepts are assembled from earned cross-KG references (ADR-017) and are exactly where analogical reasoning (ADR-031) lives. Concepts do not belong to a KG — they sit above the KG layer and index into it, preserving ADR-017's structural boundaries while still allowing cross-domain abstraction.

## Options Considered
**Flat concepts (clusters only, no hierarchy or schema).** The base `core/concept.nova` behavior. Rejected: without a hierarchy, property inheritance and abstraction are impossible, and without schemas the system cannot represent "what it doesn't know yet" about a concept — which ADR-026 needs to drive curiosity. Insufficient for theory of mind (ADR-039).

**Single embedding per concept.** Simpler and smaller. Rejected: lexical similarity and semantic similarity genuinely diverge (homonyms, synonyms), and the reader needs to match on different facets at different stages (ADR-012). Multi-vector is already in the base layer; we leverage and name the facets rather than collapse them.

**Concepts owned by a single KG.** Put each concept inside one KG. Rejected: it would forbid cross-domain concepts, the very thing ADR-017's earned cross-refs make possible, and would re-introduce the monolith problem at the concept level. Concepts indexing across KGs via `kg_span` is the right structure.

**Rigid predefined schemas per domain.** Hand-author schemas. Rejected: contradicts continuous learning and exceeds founder capacity; learned, mutable schemas (slots added after `SCHEMA_K` confirmations) scale with experience.

## Consequences
- **Positive:** Structured, inheritable, cross-domain abstraction over atoms; schemas make knowledge gaps explicit and machine-actionable (feeding ADR-026); facet vectors give the reader and reasoner the right similarity signal per task; cross-domain concepts unlock analogy (ADR-031) and rich user models (ADR-039).
- **Negative:** A DAG with multiple inheritance complicates activation/inheritance traversal and demands cycle prevention. Maintaining multiple vectors per concept costs memory and recompute. Promotion/schema thresholds need calibration (ADR-049).
- **Future work:** Concept death/merge mirroring atom GC (ADR-025). Affective facet integration with the emotion system (ADR-035). The self-model (ADR-020) reads concept schemas to know which competences are grounded; ADR-039 specializes a user concept with theory-of-mind slots.

## Implementation Notes
Extend `core/concept.nova`: `concept_new(schema)`, `concept_promote(members)`, `concept_link(parent, child)`, accessors `concept_parents`, `concept_schema`, `concept_vector(name)`, `concept_kg_span`, mutators `concept_fill_slot`, `concept_add_slot`. Tag constants `TAG_CONCEPT`, `VEC_LEXICAL|SEMANTIC|RELATIONAL|AFFECTIVE`. Facet matching delegates to `core/similarity.nova`. Concepts reference member atoms by `(kg_id, atom_id)` (ADR-016) and are assembled from xrefs (ADR-017). Persist concepts after KGs in the rehydration order (ADR-048). Test fixtures: promoting a tight cross-KG atom cluster yields a concept with `len(kg_span)==2`; an unfilled high-salience slot raises an imagination-gap signal consumable by ADR-026; lexical vs semantic facet queries return different nearest neighbors for a homonym. DEPENDS ON: NOVA enhancement #8 (multi-KG/cross-refs the concepts index over). No LLM is used to form or label concepts (ADR-014); concept labels come from associated language atoms (ADR-015).

---

# ADR-019: Procedural memory and KG-skills (skills as procedural rules + skills KG)

Status: Proposed
Date: 2026-05-24

## Context
So far the knowledge representation (ADR-016 atoms, ADR-017 multi-KG, ADR-018 concepts) is *declarative* — it captures what is true. CrossEngin also needs *procedural* memory: how to do things. A companion that can acquire skills (one of the eight capability tests, ADR-049) must represent "to convert a recipe to metric, do X then Y then Z", "to summarize a document, …", "to greet this user, …" as executable knowledge that can be invoked, sequenced, evaluated for success, and improved. This is distinct from reasoning strategies (ADR-031, which are module-level multi-step procedures); skills are learned, fine-grained, substrate-resident procedures the system accumulates over its lifetime.

The decision is needed now because self-directed learning (ADR-026) and the ask-user-to-teach mechanism (ADR-027) frequently produce procedures, not facts, and the self-model (ADR-020) tracks competence largely in terms of which skills exist and how reliable they are. Without a procedural representation, taught procedures would be flattened into inert facts and could never execute.

Constraints: 2 founders, 8h/day, bootstrap, no LLM in cognition (ADR-014) — so skills cannot be LLM-generated code; they must be substrate structures. We reuse the atom (ADR-016, `ATOM_RULE`/`ATOM_SKILL` kinds), the multi-KG layer (ADR-017), and `core/belief.nova` so a skill's reliability is tracked exactly like an atom's confidence.

## Decision
**Skills as procedural rules in a dedicated skills KG.** We spawn a standing `KG-skills` namespace (via ADR-017's `kg_spawn`, but seeded at startup since it is always needed). A *skill* is an atom of kind `ATOM_SKILL` whose payload is `{trigger, steps, preconditions, effects, reliability}`. `trigger` is a concept/condition pattern (ADR-018) that activates the skill; `steps` is an ordered list of *procedural rules* (`ATOM_RULE` atoms), each `{condition -> action_signal}` where `action_signal` is one of the 18 signal types (ADR-008) emitted toward the action part. `preconditions` and `effects` are concept-slot assertions used for planning and for verifying success. `reliability` is a `core/belief.nova` (alpha/beta) updated on every execution outcome.

**Invocation.** Skills are not called by name from outside; they are *activated* by the substrate. When the reader/reasoning loop activates a concept matching a skill's `trigger` and the `preconditions` hold, the skill emits its `steps` as ordered `SIG_COMMAND`/`SIG_ORDER` signals (ADR-008) through gates (ADR-009) to the action part. A goal (ADR-033) can also recruit a skill whose `effects` satisfy a sub-goal. On completion, observed `effects` are compared to predicted `effects`; a match calls `skill_observe(s, +1)` (alpha), a mismatch `skill_observe(s, -1)` (beta), feeding predictive coding (ADR-024).

**Learning and refinement.** Skills are born three ways: (1) taught explicitly by the user (ADR-027) — the taught steps are parsed by the reader into `ATOM_RULE` atoms; (2) extracted from episodic replay (ADR-022) when a successful action sequence recurs; (3) composed from existing skills when a sub-goal tree (ADR-033) repeatedly chains them. A skill whose `reliability` posterior mean falls below `SKILL_RETIRE = 0.4` over `RETIRE_N = 8` executions is flagged for relearning rather than silently deleted, and its decay follows the same GC path as other atoms (ADR-025).

## Options Considered
**Skills as compiled NOVA functions / generated code.** Maximum performance. Rejected: it would require either hand-authoring every skill (infeasible for 2 founders and contrary to continuous learning) or generating code at runtime, which would invite an LLM into the cognition path (violating ADR-014) and bypass the substrate. Skills must be learnable substrate data.

**Fold procedures into declarative atoms (no separate procedural kind).** Store "steps" as ordinary fact atoms. Rejected: declarative atoms have no execution semantics, no precondition/effect contract, and no per-execution reliability; the system could describe a procedure but not run it. The `ATOM_SKILL`/`ATOM_RULE` kinds give us executable structure while reusing the atom machinery.

**One skill library shared across all domains (no KG-skills namespace).** Rejected: skills are domain-organized like everything else (ADR-004/ADR-017); a contraindication-checking skill belongs near KG-medicine via cross-refs, and v2 tenant isolation (ADR-047) requires tenant-specific skills to live in a separable namespace. A dedicated `KG-skills` with cross-refs to domain KGs fits the existing model.

**Reuse the reasoning module (ADR-031) for all procedures.** Rejected: ADR-031 covers complex multi-step *strategies* implemented as module functions; lifetime-accumulated fine-grained skills are too numerous and too learned to be module code. The two are complementary — strategies can recruit skills.

## Consequences
- **Positive:** The system represents and executes learned procedures purely in the substrate, with per-skill Bayesian reliability driving honest self-assessment (ADR-020) and predictive-coding updates (ADR-024). Skills compose into sub-goal plans (ADR-033) and can be taught (ADR-027) or mined from experience (ADR-022). No LLM is needed to act.
- **Negative:** Executing a skill as a stream of signals through gates is harder to debug than a function call; failures may be partial (some steps fire, some don't). Success verification depends on accurate `effects` schemas (ADR-018). Composition can create deep skill chains needing depth limits.
- **Future work:** A skill-debugger/trace view tied to the decision log (ADR-043). Skill generalization (lifting concrete steps to schema-typed ones). ADR-020 consumes `KG-skills` reliability to report competence; ADR-026 triggers acquisition of missing skills.

## Implementation Notes
Build `KG-skills` on `core/knowledge.nova`; skills and rules are `atom_new(..., ATOM_SKILL|ATOM_RULE, ...)` (ADR-016). Add `skill_new(trigger, steps, pre, eff)`, `skill_activate(s, ctx)` (emits ordered `SIG_COMMAND` via `core/channel.nova` weighted channels and ADR-009 gates), `skill_observe(s, outcome)` (updates `core/belief.nova`), `skill_compose(s1, s2)`. Reliability read via `runtime/confidence.nova`. Triggers/preconditions/effects reference concepts (ADR-018). Episodic mining hooks into `mind/memory.nova` replay (ADR-022, NOVA enhancement #13 idle scheduling). Test fixtures: a taught 3-step procedure becomes a `KG-skills` skill that activates on its trigger and emits 3 ordered command signals; a deliberately failing skill drives `reliability` posterior below `SKILL_RETIRE` after 8 runs and is flagged for relearning; a sub-goal recruits a skill by matching `effects`. DEPENDS ON: NOVA enhancement #8 (skills KG + cross-refs to domain KGs). Skills are substrate data and signals only — no LLM in skill creation or execution (ADR-014).

---

# ADR-020: Self-model competence tracking (what the system knows it can do)

Status: Proposed
Date: 2026-05-24

## Context
Self-awareness of capability is one of CrossEngin's eight target capabilities (ADR-049). For initiative, honest interaction, and self-directed learning, the system must maintain an explicit, queryable model of *what it can do and how reliably* — not infer it ad hoc. When a user asks "can you do X?", or when the goal engine considers committing to a long-horizon goal (ADR-040), or when the curiosity drive looks for gaps to fill (ADR-026), the answer must come from a maintained self-model rather than guesswork. This is the representational substrate that the self-model query API (ADR-038) renders into language and that self-learning triggers (ADR-026) consume.

The decision is needed now, alongside the rest of Group D, because competence is defined over the very structures we have just specified: declarative coverage (atoms/KGs, ADR-016/017), conceptual grounding (schemas, ADR-018), and procedural skill reliability (ADR-019). The self-model is the integrating layer over them. Building it later would mean each consumer (ADR-026, ADR-038, ADR-040) re-deriving competence inconsistently.

Constraints: 2 founders, 8h/day, bootstrap, no-LLM cognition (ADR-014) — the self-model must be computed from substrate state, never narrated by an LLM. It lives in the meta part and is part of the soul's slow-changing self-knowledge (ADR-034), persisted in the snapshot (ADR-048).

## Decision
**A competence registry in the meta part, derived from substrate state.** The self-model is a collection of `competence` records `[TAG_COMPETENCE, domain, kind, grounding, reliability, evidence_count, last_used_moment, gaps]`. Each record summarizes the system's ability in a (domain, kind) cell, where `domain` is a `kg_id` (ADR-017) and `kind` is declarative (`COMP_KNOW`), procedural (`COMP_DO`, backed by `KG-skills`, ADR-019), or conceptual (`COMP_UNDERSTAND`, backed by concept schema completeness, ADR-018). Crucially, competence is **computed, not asserted**: `reliability` aggregates the underlying `core/belief.nova` posteriors (mean atom confidence for `COMP_KNOW`, mean skill reliability for `COMP_DO`, schema-slot fill ratio for `COMP_UNDERSTAND`), and `evidence_count` carries the summed observation counts so the system distinguishes confident competence from thinly-evidenced competence.

**Competence tiers.** From the aggregated posterior mean we derive a tier: `TIER_CAPABLE` (mean ≥ 0.75 and evidence_count ≥ 20), `TIER_PARTIAL` (mean ≥ 0.5), `TIER_AWARE` (the concept/skill exists but mean < 0.5 — "I know of it but can't reliably do it"), and `TIER_UNKNOWN` (no grounding atom/skill at all). The `TIER_UNKNOWN` and `TIER_AWARE` cells are precisely the inputs to the curiosity drive and unknown-query trigger in ADR-026.

**Recomputation cadence and gap detection.** The registry is refreshed on a slow meta cadence (event-driven, ADR-037 — not every 100Hz tick) and opportunistically when a relevant atom/skill is updated. `gaps` lists unfilled high-salience concept slots (ADR-018) and retired/low-reliability skills (ADR-019) within the cell. A self-model query (ADR-038) reads a competence record directly; the language rendering flows through pure-substrate output (ADR-013). The self-model never overstates: if asked about a `TIER_AWARE` domain, the honest answer ("I have some knowledge but low confidence") is generated from the tier and `evidence_count`, supporting calibrated, non-confabulated responses.

## Options Considered
**No explicit self-model; answer capability questions by live-querying the KGs each time.** Rejected: it is expensive to recompute on every question, gives inconsistent answers across the loops (ADR-036), and provides nothing for the goal engine (ADR-040) or curiosity drive (ADR-026) to plan against. A maintained registry is cheap to read and consistent. (We still *derive* it from the KGs, but cache the derivation.)

**Self-assessment via a learned confidence scalar per domain.** Train a single number for "how good am I at medicine". Rejected: it collapses the declarative/procedural/conceptual distinction, hides evidence volume, and cannot point at specific gaps. Aggregating the existing alpha/beta posteriors (ADR-016/019/023) gives a principled, decomposable tier plus an actionable `gaps` list for free.

**Let an LLM introspect and describe the system's abilities.** Rejected outright: violates ADR-014. The self-model must be computed from substrate state; the LLM bridge is STT/TTS only (NOVA enhancement #14).

**Bake competence into the soul identity directly (no separate registry).** Rejected: identity (ADR-034) changes only by deliberate revision and is slow; competence changes continuously as the system learns. Competence is fast-moving self-*knowledge* that the soul references, so it lives in the meta part and is snapshotted with, but kept distinct from, slow identity.

## Consequences
- **Positive:** A consistent, cheap-to-read, decomposable model of capability with honest tiers and explicit gaps. Directly powers self-learning triggers (ADR-026), the self-model API (ADR-038), and long-horizon goal feasibility checks (ADR-040). Enables calibrated, non-confabulated self-description — central to the self-awareness capability test (ADR-049).
- **Negative:** The aggregation heuristics (how to roll up atom/skill posteriors into a cell, tier thresholds) need calibration during the multi-day test (ADR-049) and could misreport if the underlying beliefs are skewed. Adds a meta-part recomputation pass and another snapshot section.
- **Future work:** Confidence-calibration validation (does `TIER_CAPABLE` predict actual success?) folded into ADR-049 benchmarks. Theory-of-mind reuse: an analogous model of the *user's* competence (ADR-039). Cross-session competence trends feeding goal selection (ADR-040).

## Implementation Notes
Create a `self_model` module in the meta part over `core/knowledge.nova` (it indexes KGs but is not itself a domain KG). Constructors/accessors: `competence_recompute(domain)`, `competence_tier(domain, kind)`, `competence_gaps(domain)`, `self_model_snapshot()`. Tag constants `TAG_COMPETENCE`, `COMP_KNOW|DO|UNDERSTAND`, `TIER_CAPABLE|PARTIAL|AWARE|UNKNOWN`. Aggregation reads `core/belief.nova` posteriors via `runtime/confidence.nova`, skill reliability from `KG-skills` (ADR-019), and schema fill ratios from `core/concept.nova` (ADR-018). Recompute is scheduled on the event-driven layer (ADR-037), persisted with the soul/meta state early in rehydration order (ADR-048). Test fixtures: a domain with high-confidence atoms and a reliable skill reports `TIER_CAPABLE` with the correct `evidence_count`; removing the skill drops the `COMP_DO` cell to `TIER_AWARE`; `competence_gaps` returns the unfilled high-salience slot from ADR-018; a self-model query (ADR-038) over a `TIER_AWARE` cell yields a calibrated "limited confidence" response with no LLM involvement (ADR-014). Feeds ADR-026 (triggers) and ADR-038 (API) as the authoritative competence source.


---

# ADR-021: Moments (timestamped perception, lifecycle, episodic integration)

Status: Proposed
Date: 2026-05-24

## Context
Every external input to CrossEngin — a user utterance, a sensor reading, a clock event, an internet-fetch result (ADR-028) — must enter the substrate through a single, uniform, timestamped record. Without one canonical entry point, perception, episodic memory, and emotion would each invent their own input representation and the system would lose the ability to say *when* something happened, *what state it was in* at the time, and *which downstream activity that input caused*. The substrate thesis (ADR-001) demands that input become signals flowing through nodes; the question is what durable object anchors that flow to wall-clock time and to the episodic record.

NOVA already provides `core/moment.nova` — a timestamped perception record (singular file, per §3). We are deciding the moment's full lifecycle: how raw input is wrapped into a moment, how a moment is fanned out into signals at the perception part's first nodes (ADR-010), how the moment is correlated with the resulting cognition, and how it is finally handed to episodic memory (ADR-022). The constraint is a 2-founder team on a 100Hz tick: moment creation must be cheap (allocation-free on the hot path) and must not stall the perception loop (ADR-036). A desktop v1 single user generates perhaps 10^3-10^4 moments/day, so storage volume is modest but the *correlation* machinery (linking a moment to the trace of signals it spawned) must be designed once and reused for v2.

The moment is also the unit the No-LLM-Cognition principle (ADR-014) protects: when STT converts audio to text via the modality bridge, the *text* enters as a moment payload — the bridge never reasons, it only fills a moment's `raw` field.

## Decision
We adopt the moment as the immutable timestamped envelope for all external perception, with a four-phase lifecycle: **capture -> fan-out -> correlation -> consolidation handoff**. Extend `core/moment.nova` with a richer layout `[TAG_MOMENT, id, timestamp, modality, raw, salience, origin_part, signal_trace, soul_state_ref, status]` and a constructor `moment_new(modality, raw, salience)`. `timestamp` is the 100Hz tick index plus monotonic ns (from `runtime/scheduler.nova`); `modality` is an enum (TEXT, AUDIO_STT, SENSOR, CLOCK, FETCH, INTERNAL). The moment is created at the gate boundary (ADR-009) before any node sees it, so the entry point is uniform regardless of source.

On **capture**, the moment is stamped and a snapshot reference to current soul state (ADR-034 — fast-changing state vector) is copied into `soul_state_ref` so the episode later records "what mood/goal-context surrounded this perception." On **fan-out**, the gate emits `SIG_EVENT` (or `SIG_QUESTION`/`SIG_ORDER` per `core/signal.nova`) signals carrying `moment=id` in the signal's `moment` field (already in the `core/signal.nova` layout) to the perception part's first nodes. As those signals propagate, each visited node appends to the signal's `trace`; a lightweight **correlation collector** in the memory loop accumulates the union of traces keyed by `moment.id` into `signal_trace`. After a bounded settle window (default 200ms / 20 ticks, or earlier on quiescence), the moment's `status` flips PERCEIVED -> SETTLED and it is handed to episodic memory (ADR-022) for storage and eventual consolidation. Moments are append-only and never mutated after SETTLED; corrections arrive as *new* moments (modality INTERNAL, `SIG_CORRECTION`), preserving an honest history for the decision log (ADR-043).

## Options Considered
**1. Moment as immutable timestamped envelope with trace correlation (CHOSEN).** Gives a single uniform entry point, a wall-clock anchor, and a causal bridge from input to the cognition it triggered (via `signal_trace`). Reuses `core/moment.nova` and the existing `trace` field on signals. Cost: the correlation collector adds a per-moment accumulation pass. Accepted because the trace is exactly what episodic recall, emotion appraisal (ADR-035), and the decision log all need, so the cost is amortized across three consumers.

**2. No moment object — input becomes signals directly.** Simpler: the gate just emits signals and skips the envelope. Rejected because signals are ephemeral (§2) and carry no durable timestamp or soul-state snapshot; episodic memory would have nothing concrete to store, and we would lose the ability to reconstruct *when* and *in what state* perception occurred. The substrate would be amnesic about its own inputs.

**3. Moment as a mutable record updated throughout cognition.** Let downstream parts write conclusions back into the moment. Rejected: mutation destroys the honest "what was actually perceived vs. what was inferred" boundary that the safety/audit layer (ADR-009/ADR-043) depends on, and it creates write-contention on a hot object across the six concurrent loops (ADR-036). We instead keep moments immutable and let inference live in atoms (ADR-016).

**4. Per-modality record types (TextMoment, SensorMoment, ...).** Type-specialized envelopes. Rejected for the same reason nodes are uniform (ADR-006): specialization belongs in learned state and in the `modality` enum, not in proliferating types that the gate, episodic store, and consolidation would each have to branch on.

## Consequences
- **Positive:** A single uniform, timestamped entry point for all input; honest immutable perception history; a built-in causal link (moment -> signal trace -> atoms) that powers episodic recall (ADR-022), emotion appraisal of moments against goals (ADR-035), and full per-action traces in the decision log (ADR-043). STT/TTS isolation (ADR-014) is structurally clean: the bridge only fills `raw`.
- **Negative:** The correlation collector adds bookkeeping on every perception and a bounded settle latency (200ms) before episodic handoff; tuning the settle window per modality is future tuning work. Immutability means corrections cost an extra moment rather than an in-place edit.
- **Future work:** Adaptive settle windows driven by quiescence detection; moment compaction for high-frequency sensor modalities in v2; richer `soul_state_ref` snapshots once the soul wrapper (ADR-034) stabilizes.

## Implementation Notes
- Extend `core/moment.nova`: constructor `moment_new`, accessors `moment_timestamp`, `moment_trace`, mutator `moment_set_status` (PERCEIVED/SETTLED/CONSOLIDATED), tag constant `TAG_MOMENT`, modality enum constants.
- Capture happens at the gate (ADR-009) using `channel_new`-derived gate routing; fan-out emits via `node_emit` to ADR-010 first nodes; the signal carries `moment` per the `core/signal.nova` layout. Correlation collector lives in the memory loop (ADR-036) and reads signal `trace` lists.
- Handoff target is `mind/memory.nova` (ADR-022); soul-state snapshot reads from `core/soul.nova` (ADR-034).
- Testing: fixtures `fixture_moment_text`, `fixture_moment_stt`, `fixture_moment_clock`; assert (a) timestamp monotonicity across a 100Hz tick burst, (b) `signal_trace` captures the exact node set a known input reaches, (c) immutability — post-SETTLED writes rejected, (d) bridge fills only `raw`.
- Dependencies: ADR-008 (signal types), ADR-009 (gates), ADR-010 (first nodes), ADR-022 (episodic store), ADR-034 (soul state), ADR-043 (decision log).
- DEPENDS ON: NOVA enhancement #5 — 100Hz deterministic tick scheduler (for `timestamp` tick index and the settle window).
- DEPENDS ON: NOVA enhancement #6 — extended signal tag space (so `SIG_EVENT`/`SIG_CORRECTION` and CrossEngin's 18 types carry `moment` ids with fast dispatch).

---

# ADR-022: Episodic memory (storage, decay, consolidation, replay during idle)

Status: Proposed
Date: 2026-05-24

## Context
Settled moments (ADR-021) must be retained as episodes so CrossEngin can recall specific past events ("what did the user ask last Tuesday?"), ground emotional appraisal in history (ADR-035), and feed the imagination/replay loop (ADR-032, ADR-036). A flat, ever-growing log is untenable on a desktop: a multi-day companion accumulating 10^3-10^4 moments/day would bloat storage and slow recall, and most raw episodes have little long-term value. We therefore need a memory that *forgets gracefully* (decay), *distills* recurring structure into durable knowledge (consolidation into atoms, ADR-016), and *rehearses* during idle to strengthen what matters (replay).

NOVA provides `mind/memory.nova` and `runtime/db.nova`. The decision is the storage tier structure, the decay schedule, the consolidation pipeline (episode -> atoms in domain KGs, ADR-004/ADR-017), and how replay is scheduled in the background imagination idle loop without competing with live cognition. Constraints: 2 founders, 8h/day; we cannot build a database engine, so we layer on `runtime/db.nova`. The replay loop must run only when idle (no live perception) so it never steals tick budget from the six live loops (ADR-036) at 100Hz.

This ADR is explicitly flagged as a NOVA-enhancement consumer: idle-detection and background scheduling hooks are enhancement #13, and replay is the mechanism that links to the ADR-036 imagination idle loop.

## Decision
We implement episodic memory as a **three-tier decaying store with idle consolidation and replay**, all in `mind/memory.nova` over `runtime/db.nova`. Tiers: **recent** (in-memory ring buffer, last ~24h or 4096 episodes, full fidelity), **archived** (on-disk via `runtime/db.nova`, decayed and gist-compressed), and **consolidated** (no longer episodes at all — distilled into atoms in domain KGs). An episode is `episode_new(moment_ref, salience, last_access, strength)` where `strength` starts at the moment's `salience` (ADR-021) and `moment_ref` points back to the immutable moment.

**Decay:** each episode's `strength` decays exponentially with retrieval-based reinforcement: `strength *= exp(-dt / tau)` on each consolidation pass, with `tau = 7 days` for ordinary episodes and `tau = 90 days` for emotionally-tagged ones (high arousal/valence per ADR-008 valence/arousal signals and ADR-035). Each successful recall resets `last_access` and adds `+0.3` to `strength` (capped at 1.0). When `strength < 0.05`, the episode drops from `recent`/`archived` (but any atoms it already produced persist — memory of the *gist* survives loss of the *episode*).

**Consolidation:** during idle, a pass scans `recent`+`archived` for episodes whose traces (`moment.signal_trace`) repeatedly co-activate the same node clusters; recurring structure is handed to ADR-025's atom-birth detector to mint or reinforce atoms, and the episode is marked CONSOLIDATED. **Replay:** the imagination idle loop (ADR-036) samples episodes with probability proportional to `strength * salience`, re-injects their moments as INTERNAL signals (no new external moment), and lets the substrate re-traverse them — strengthening synapses (ADR-007 Hebbian) and surfacing prediction errors (ADR-024) for offline learning. Replay is strictly idle-gated via enhancement #13.

## Options Considered
**1. Three-tier decaying store with idle consolidation + replay (CHOSEN).** Bounds memory, distills durable knowledge into atoms, and rehearses high-value episodes for free during idle. Matches the brain-inspired substrate thesis and reuses `runtime/db.nova`. Cost: tuning decay constants and a non-trivial consolidation pass. Chosen because it is the only option that both bounds storage *and* turns experience into reusable knowledge.

**2. Flat append-only episodic log, never forget.** Keep everything forever in `runtime/db.nova`. Rejected: unbounded growth on a desktop, linearly slowing recall, and no distillation — the system would hoard raw episodes instead of learning from them. It also conflates the audit log (ADR-043, which *is* append-only by design) with cognitive memory, which should forget.

**3. Pure consolidation, no episodic retention (everything becomes atoms immediately).** Convert each settled moment straight into atoms and discard the episode. Rejected: destroys the ability to recall *specific* events with their temporal context ("the conversation we had yesterday"), which is a named v1 capability (self-awareness over time, ADR-049). Episodic and semantic memory are complementary; we need both.

**4. LRU cache eviction instead of strength-based decay.** Evict least-recently-used episodes. Rejected: LRU ignores emotional salience and recall frequency; a single emotionally pivotal episode accessed once could be evicted before trivial recent chatter. Strength-based decay with reinforcement and emotional `tau` extension models retention far better and ties cleanly to ADR-035.

## Consequences
- **Positive:** Bounded, self-pruning memory on a desktop; specific-event recall with temporal+emotional context; automatic distillation of experience into durable atoms (ADR-016/ADR-025); free offline learning via replay that strengthens synapses (ADR-007) and exercises predictive coding (ADR-024). Emotionally significant episodes persist far longer (90d vs 7d tau).
- **Negative:** Decay constants (`tau`, reinforcement `+0.3`, drop threshold `0.05`) are hand-tuned and will need empirical calibration; consolidation and replay add background CPU that must be carefully idle-gated to avoid stealing from live loops; a bug in idle-gating could degrade live responsiveness.
- **Future work:** Learned (rather than fixed) decay schedules; cross-session replay prioritization tied to long-horizon goals (ADR-040); per-tenant memory isolation for v2 (ADR-047); sharper consolidation heuristics co-developed with ADR-025.

## Implementation Notes
- `mind/memory.nova`: `episode_new`, accessors `episode_strength`/`episode_last_access`, `episode_decay(dt)`, `episode_reinforce`, tier-move fns `mem_archive`/`mem_consolidate`/`mem_drop`. Persist `archived`/`consolidated` via `runtime/db.nova`; `recent` is an in-memory ring.
- Replay re-injects via INTERNAL moments (ADR-021) and `node_emit`; consolidation calls into ADR-025 atom-birth. Salience/valence/arousal tags come from ADR-008 and ADR-035.
- Testing: fixtures `fixture_episode_burst` (decay-curve assertions), `fixture_emotional_episode` (90d tau retention vs 7d ordinary), `fixture_replay_idle` (replay fires only when idle flag set, strengthens expected synapses), `fixture_consolidation` (recurring trace -> atom minted via ADR-025).
- Dependencies: ADR-021 (moments), ADR-016 (atoms), ADR-025 (atom birth), ADR-007 (synapse plasticity), ADR-024 (prediction error during replay), ADR-032/ADR-036 (imagination idle loop), ADR-035 (emotional tagging), ADR-048 (rehydration order — episodic last).
- DEPENDS ON: NOVA enhancement #13 — idle-detection + background scheduling hooks (imagination/replay). Gates the consolidation and replay passes.
- DEPENDS ON: NOVA enhancement #10 — substrate snapshot + ordered rehydration (episodic restored last, after soul and KGs, per ADR-048).

---

# ADR-023: Bayesian belief tracking refinement (alpha/beta per atom, decay, conflict)

Status: Proposed
Date: 2026-05-24

## Context
Atoms (ADR-016) carry confidence, and NOVA's `core/belief.nova` already implements Bayesian beliefs as Beta-distribution alpha/beta counts. But raw alpha/beta accumulation is naive for a continuously-learning agent: (1) old evidence should lose weight as the world changes (a medical guideline learned two years ago should not forever dominate a fresh contradicting one — ADR-029); (2) confidence must be readable as a single number for thresholds (ADR-030 "learned enough") and for routing decisions; (3) when two sources genuinely conflict, the belief must represent *contested* state rather than silently averaging into false certainty. We must refine `core/belief.nova` for these three needs without abandoning the principled Beta model.

This matters now because beliefs gate behavior across the system: the reader (ADR-012) routes on confidence, the self-learning triggers (ADR-026) fire on low confidence or high conflict, source-authority resolution (ADR-029) feeds weighted evidence here, and the override mechanism (ADR-044) edits beliefs directly. A weak belief model corrupts all of them. Constraint: 2 founders — the update must be a cheap, closed-form arithmetic step runnable on the 100Hz substrate, not an MCMC sampler.

## Decision
We refine each atom's belief into a **per-atom decaying Beta state with explicit conflict tracking**: `belief = [TAG_BELIEF, alpha, beta, last_update_tick, conflict]`. Confidence (the point estimate) is the Beta mean `alpha / (alpha + beta)`; epistemic certainty is its concentration `alpha + beta` (more evidence => tighter). We expose `belief_confidence`, `belief_strength` (= alpha+beta), and `belief_conflict`.

**Weighted evidence:** evidence is not unit-counted. An evidential signal (ADR-008) carries a weight derived from source tier (ADR-029): Tier A `w=1.0`, Tier B `w=0.6`, Tier C `w=0.3`, direct user teaching (ADR-027) `w=1.5`. Supporting evidence does `alpha += w`; contradicting does `beta += w`.

**Time decay:** before each update we age the counts toward the uniform prior so stale evidence fades: with `tau_belief = 180 days` (in ticks), `decay = exp(-dt / tau_belief)`, then `alpha = 1 + (alpha-1)*decay`, `beta = 1 + (beta-1)*decay` (decaying toward the Beta(1,1) prior, never below it). This makes confidence revisable: a long-unreinforced belief drifts back toward uncertainty rather than ossifying. For atoms tagged "classical/stable" (ADR-029 oldest-wins domains), `tau_belief = 5 years` so foundational facts barely decay.

**Conflict:** `conflict` is an EWMA of contradiction pressure. On each contradicting update, `conflict = 0.9*conflict + 0.1*(w_contra / (w_contra + w_support_recent))`. When `conflict > 0.4` AND `belief_strength > 8` (i.e. genuinely contested with enough evidence on both sides — not just noisy early data), the atom is flagged CONTESTED: confidence is reported with a contested marker, the atom emits a `SIG_CORRECTION`/curiosity signal to trigger self-learning (ADR-026), and for hard conflicts the user is flagged (ADR-029). CONTESTED beliefs are never silently collapsed to a confident mean.

## Options Considered
**1. Decaying weighted Beta with explicit conflict EWMA (CHOSEN).** Keeps the principled, closed-form Beta model (cheap on the tick), makes confidence revisable via decay, honors source authority via weights (ADR-029), and surfaces genuine disagreement instead of hiding it. Cost: three extra fields and a decay step per update, plus threshold tuning. Chosen because it satisfies all three needs (decay, weighting, conflict) with O(1) arithmetic.

**2. Plain alpha/beta counting, no decay, no weights (status-quo `core/belief.nova`).** Simplest. Rejected: evidence never expires, so the agent cannot revise long-held beliefs as guidelines change (breaks ADR-029 newest-wins); all sources count equally, so a low-authority web page rivals a Tier-A source; and contradictions just inflate both counts, yielding a falsely confident ~0.5 mean instead of a *contested* flag.

**3. Single scalar confidence with manual nudges.** Store one float per atom, adjust up/down heuristically. Rejected: throws away the distinction between "uncertain because little evidence" (low concentration) and "uncertain because conflicting evidence" (high concentration, split) — a distinction ADR-026 and ADR-030 need. It is also unprincipled and hard to calibrate thresholds against.

**4. Full Bayesian network with inter-atom dependencies.** Model joint distributions across related atoms. Rejected for v1: intractable to keep consistent over 1M-node parts at 100Hz with a 2-founder team, and the closed-form per-atom Beta is sufficient for the decisions beliefs gate. Cross-atom influence is instead handled by the substrate (synapses, predictive coding ADR-024), not by an explicit Bayes net. Revisit post-v2.

## Consequences
- **Positive:** Confidence is principled, cheap, and revisable; source authority (ADR-029) and user teaching (ADR-027) flow in as evidence weights; genuine disagreement becomes a first-class CONTESTED state that drives curiosity-based self-learning (ADR-026) and user-facing conflict flags. The strength (concentration) signal lets ADR-030 distinguish "needs more evidence" from "settled."
- **Negative:** Several hand-tuned constants (`tau_belief`, weights, conflict threshold 0.4, strength gate 8) need empirical calibration and may differ per domain; per-atom `last_update_tick` adds state to every atom (1M-scale memory cost, mitigated by it being two extra numbers).
- **Future work:** Learned, domain-specific decay/weight schedules; tying conflict resolution into theory-of-mind (ADR-039) when conflicts stem from different users; richer interaction with predictive-coding error (ADR-024) so prediction failures also update beliefs.

## Implementation Notes
- Refine `core/belief.nova`: extend layout to `[TAG_BELIEF, alpha, beta, last_update_tick, conflict]`; fns `belief_new`, `belief_update(weight, supports:bool, now_tick)` (does decay-then-update-then-conflict), `belief_confidence`, `belief_strength`, `belief_conflict`, `belief_is_contested`. Decay uses `runtime/math.nova`/`runtime/float.nova` `exp`.
- Evidence weights are set by ADR-029 source tiers and ADR-027 user teaching; CONTESTED atoms emit ADR-008 curiosity/`SIG_CORRECTION` signals consumed by ADR-026. Override edits (ADR-044) call `belief_new` to reset counts deliberately.
- Beliefs attach to atoms (ADR-016); confidence feeds reader routing (ADR-012) and "learned enough" (ADR-030).
- Testing: `fixture_belief_decay` (unreinforced belief drifts to ~0.5 over 180d; classical atom barely moves over same span), `fixture_weighted_evidence` (Tier-A vs Tier-C move confidence proportionally), `fixture_conflict` (balanced contradicting Tier-A sources -> CONTESTED flag + emitted curiosity signal, NOT a confident 0.5).
- Dependencies: ADR-016 (atoms own beliefs), ADR-008 (evidential/curiosity/correction signals), ADR-029 (source tiers/weights), ADR-027 (user teaching weight), ADR-026 (curiosity trigger), ADR-030 (thresholds), ADR-044 (override edits), ADR-024 (prediction-error updates).
- No new NOVA enhancement strictly required — closed-form arithmetic runs on existing `runtime/math.nova`; benefits from #12 (plasticity kernels) only if belief updates are later batched alongside synapse weights.

---

# ADR-024: Predictive coding between layers (top-down predictions, bottom-up errors)

Status: Proposed
Date: 2026-05-24

## Context
A substrate that only reacts to input is inert; an AGI-relevant substrate must *anticipate* and learn from the gap between what it expected and what arrived. Predictive coding is the mechanism: higher/abstract parts continuously send top-down predictions to lower/perceptual parts, lower parts compute the residual (prediction error) against actual input, and only the *error* propagates upward to update beliefs and synapse weights. This is the substrate's primary unsupervised learning engine — it is what makes synapse error-driven plasticity (ADR-007) have an error to be driven by, what surfaces surprises that trigger self-learning (ADR-026), and what gives replay (ADR-022) something to correct during idle.

The signal vocabulary already anticipates this: ADR-008 defines **predictive** and **error** signal types among the 18. The decision here is the *protocol* — how predictions flow down, how error is computed and flows up, how the loop is timed against the 100Hz tick (ADR-037), and how it couples to belief updates (ADR-023) and plasticity (ADR-007) — without an LLM anywhere in the loop (ADR-014). Constraint: 2 founders on a 100Hz substrate; prediction/error must be a per-tick local computation at nodes, not a global optimization. We must also avoid runaway feedback (predictions reinforcing themselves into hallucination).

## Decision
We implement predictive coding as a **per-tick bidirectional protocol between adjacent parts**, using the `predictive` and `error` signal types from ADR-008. Each part maintains, at its first nodes (ADR-010), an incoming **prediction buffer** of top-down `predictive` signals for the next tick. When actual bottom-up input arrives (a moment's signals, ADR-021, or lower-part activations), each receiving node computes a residual: `error = actual_activation - predicted_activation`, scaled by precision (confidence). The node emits an `error` signal upward **only when** `|error| > theta_err` (default `theta_err = 0.15` on normalized [0,1] activations) — small, well-predicted input is suppressed and does not propagate, which is the efficiency win of predictive coding. Predictions themselves are generated top-down: higher parts emit `predictive` signals derived from currently-active atoms/concepts (ADR-016/ADR-018) down through their synapses each tick.

Error signals carry high priority in the gate dispatch (ADR-009) — surprise should preempt routine processing. Upward error drives three consumers: (a) **synapse plasticity** — error-driven weight update (ADR-007/enhancement #12), strengthening connections that would have predicted correctly; (b) **belief update** — a persistent prediction failure for an atom contributes contradicting evidence to its Beta belief (ADR-023); (c) **self-learning** — sustained high error (a running mean above `theta_surprise = 0.3` over a 1-second window) emits a curiosity/`SIG_CORRECTION` signal triggering ADR-026.

To prevent runaway feedback, predictions are **precision-weighted and bounded**: a prediction's influence is scaled by the source belief's certainty (`belief_strength`, ADR-023), and prediction signals decay if not refreshed each tick, so a part cannot bootstrap itself into a self-confirming loop. During idle, replay (ADR-022) runs the same loop offline so the system can learn from re-experienced episodes.

## Options Considered
**1. Per-tick bidirectional predictive/error protocol with thresholded error suppression (CHOSEN).** Aligns with the predictive/error signals already budgeted in ADR-008, makes learning unsupervised and local (cheap per tick), suppresses well-predicted input for efficiency, and feeds plasticity, beliefs, and curiosity from one mechanism. Cost: tuning thresholds and guarding against feedback. Chosen because it is the canonical, biologically-grounded fit for the substrate thesis (ADR-001) and unifies three learning consumers.

**2. Pure reactive substrate, no top-down prediction.** Input flows up, responses flow out, no predictions. Rejected: there is no prediction error, so error-driven plasticity (ADR-007) is starved of signal, the system cannot be *surprised* (no prediction-error trigger for ADR-026), and it cannot anticipate the user (undermining initiative and theory-of-mind, ADR-039). Anticipation is a named v1 capability.

**3. Explicit forward-model module that predicts next state globally.** A dedicated module computes a global next-state prediction each tick. Rejected: that is orchestration, not substrate (violates ADR-001), it is a single bottleneck incompatible with 1M-node parts and the six concurrent loops (ADR-036), and a global model is far harder to tune than local per-node residuals.

**4. Backpropagation-style end-to-end error.** Train the whole substrate by backprop. Rejected: backprop requires global differentiability and synchronized passes that the asynchronous, sparse, 100Hz substrate (ADR-003, ADR-037) is not built for, and it is heavy for a 2-founder team. Local predictive coding gives most of the learning benefit with local, tick-friendly updates and maps directly onto enhancement #12 kernels.

## Consequences
- **Positive:** Unifies unsupervised learning (drives ADR-007 plasticity), surprise detection (drives ADR-026 self-learning), and belief revision (ADR-023) under one local mechanism; error suppression of well-predicted input saves signal throughput (relevant to the 1B-signals/part budget, ADR-003); gives the system genuine anticipation for theory-of-mind (ADR-039) and replay-based offline learning (ADR-022).
- **Negative:** Threshold/window constants (`theta_err=0.15`, `theta_surprise=0.3`, 1s window) need calibration and may vary per part; feedback-stability guarding (precision weighting + prediction decay) adds subtlety and a class of hard-to-debug oscillation bugs; bidirectional signaling roughly doubles inter-part signal traffic on poorly-predicted streams.
- **Future work:** Learned per-part precision; hierarchical predictive coding across more than two adjacent layers; coupling prediction-error magnitude into emotion appraisal (surprise as an emotion, ADR-035); using accumulated error maps to prioritize what to learn (ADR-026/ADR-030).
- **NOVA-enhancement flag:** this is a primary consumer of error-driven plasticity kernels.

## Implementation Notes
- Use ADR-008 `predictive` and `error` signal types (extended tags over `core/signal.nova`). Prediction buffers and residual computation live at first nodes (ADR-010); `node_get_state`/`node_set_state` hold `predicted_activation`; residual emitted via `node_emit` as an `error` signal with high `priority` (ADR-009 gate fast-path).
- Error -> plasticity: feed into ADR-007 synapse weight update (enhancement #12 kernels over weight arrays). Error -> belief: call `belief_update(..., supports=false, now_tick)` from ADR-023. Error -> curiosity: emit ADR-008 curiosity/`SIG_CORRECTION` for ADR-026 when running-mean error exceeds `theta_surprise`.
- Precision weighting reads `belief_strength` (ADR-023); prediction decay handled in the per-tick scheduler step (ADR-037).
- Testing: `fixture_predict_match` (well-predicted input -> error below `theta_err` -> NO upward signal), `fixture_predict_miss` (surprising input -> error signal emitted, target synapse weight moves per ADR-007, contradicting evidence applied to belief), `fixture_no_runaway` (unrefreshed predictions decay; no self-confirming oscillation over 1000 ticks), `fixture_surprise_trigger` (sustained error -> curiosity signal to ADR-026).
- Dependencies: ADR-008 (predictive/error signals), ADR-007 (plasticity target), ADR-023 (belief updates + precision), ADR-010 (first nodes), ADR-009 (priority routing), ADR-026 (surprise trigger), ADR-022 (replay reuses the loop), ADR-037 (tick timing).
- DEPENDS ON: NOVA enhancement #12 — Hebbian + error-driven plasticity kernels over synapse weight arrays (the error signal's primary sink).
- DEPENDS ON: NOVA enhancement #4 — SIMD/GPU batched signal propagation (top-down prediction fan-out across millions of synapses per tick).

---

# ADR-025: Atom birth and death (co-activation pattern -> new atom; decay-based GC)

Status: Proposed
Date: 2026-05-24

## Context
Atoms are CrossEngin's durable knowledge units (ADR-016), and ADR-006 establishes that nodes produce atoms **only for novel patterns** and may read atoms they did not create. Two lifecycle questions follow and must be answered concretely: *birth* — under exactly what conditions does a recurring co-activation of nodes crystallize into a new persistent atom (rather than minting noise atoms for every fleeting pattern)? — and *death* — how are atoms that stop earning their keep garbage-collected so the KGs (ADR-004/ADR-017) don't accumulate dead weight over months of continuous learning on a desktop? Without disciplined birth, the KGs bloat with spurious atoms and the 1M-node parts (ADR-003) thrash; without principled death, stale knowledge lingers and storage grows unbounded.

This decision sits at the seam between the substrate (nodes/synapses, ADR-006/ADR-007) and knowledge (atoms/KGs, ADR-016/ADR-017), and it is the concrete mechanism behind consolidation (ADR-022) and is fed by predictive-coding novelty (ADR-024). Constraint: 2 founders, 100Hz substrate — birth detection must be a cheap, incremental co-activation counter, and death must be a periodic background sweep (idle-gated, enhancement #13), not a stop-the-world GC. We need concrete thresholds the team can implement and tune.

## Decision
We define atom **birth** by a **co-activation-frequency + novelty + stability** gate, and atom **death** by **decay-based reference-counted garbage collection**.

**Birth.** Each node tracks short-lived candidate co-activation patterns: when a set of nodes fires together within a 50ms (5-tick) window, an incremental counter for that pattern signature is bumped (signatures hashed from the participating node ids, kept in a small per-part LRU candidate table, capacity ~10k). A new atom is born only when ALL hold: (1) **frequency** — the pattern recurs `>= 5` times; (2) **novelty** — no existing atom already matches it within cosine similarity `0.9` (checked via `core/similarity.nova` over the pattern's embedding), satisfying ADR-006's "novel patterns only"; (3) **stability** — the pattern persists across `>= 3` distinct moments/episodes (ADR-021/ADR-022), not a single burst. On firing, `atom_new(pattern_embedding, kg_id)` is created in the appropriate domain KG (ADR-017, spawning a new KG if the domain is new), with an initial Beta belief (ADR-023) seeded `alpha=1+evidence_weight, beta=1`. Predictive-coding surprise (ADR-024) lowers the frequency threshold to `3` for high-error patterns — the system preferentially crystallizes things that violated expectations.

**Death.** Each atom carries `last_access_tick` and an `activation_strength` that decays exponentially (`tau_atom = 30 days`) and is reinforced `+0.2` on each read/co-activation. A periodic idle GC sweep (default every 6h of idle, enhancement #13) collects an atom when ALL hold: (1) `activation_strength < 0.02`; (2) not referenced by any cross-KG edge (ADR-017) and not cited by a CONSOLIDATED episode's surviving knowledge; (3) `belief_strength < 4` (we never GC a well-evidenced atom, however cold — foundational facts persist). Collected atoms are first **tombstoned** for one sweep cycle (soft-deleted, recoverable) before hard removal, so an atom reactivated just after marking is rescued. Protected classes — constitutional/value atoms (ADR-045), self-model atoms (ADR-020), and atoms tagged classical/stable (ADR-029) — are exempt from death entirely.

## Options Considered
**1. Frequency+novelty+stability birth gate with decay-based reference-counted GC (CHOSEN).** Implements ADR-006's "atoms only on novel patterns" precisely, prevents both noise-atom bloat and unbounded growth, and ties cleanly to similarity (ADR-017), beliefs (ADR-023), predictive surprise (ADR-024), and idle scheduling (#13). Tombstoning makes death safe. Cost: candidate tables, several thresholds, and a background sweep. Chosen as the only option meeting both the novelty mandate and the bounded-storage constraint.

**2. Birth an atom on every distinct co-activation (no gate).** Maximally sensitive. Rejected: explodes the KGs with transient, noise, and near-duplicate atoms, violating ADR-006 and thrashing the 1M-node parts and `core/similarity.nova` lookups (ADR-003); confidence and routing degrade because real atoms are buried in spurious ones.

**3. Never delete atoms (birth only, immortal atoms).** Simple, no GC. Rejected: unbounded KG growth over months of continuous desktop learning, stale/obsolete knowledge competing with current knowledge (worsening conflicts, ADR-023/ADR-029), and ever-slowing spreading activation in the reader (ADR-012). Belief *decay* (ADR-023) softens stale confidence but does not reclaim storage; we need actual death.

**4. Fixed-size atom pool with LRU eviction.** Cap atoms per KG, evict least-recently-used. Rejected: a hard cap is arbitrary across heterogeneous domains, and pure LRU would evict cold-but-foundational atoms (a rarely-recalled but high-evidence fact) — exactly what the `belief_strength`/protected-class guards prevent. Decay+reference-count GC retains by *importance*, not just recency, mirroring the episodic decision in ADR-022.

## Consequences
- **Positive:** Disciplined, novelty-gated atom creation that honors ADR-006 and prevents KG bloat; bounded long-term storage via safe (tombstoned) decay-based GC; preferential crystallization of surprising patterns (via ADR-024 coupling) so the system learns what defied expectation; protected classes guarantee constitution, self-model, and classical facts are never collected.
- **Negative:** Many tuned constants (freq 5/3, cosine 0.9, stability 3 moments, `tau_atom=30d`, GC strength 0.02, belief 4, 6h sweep) requiring empirical calibration; candidate co-activation tables add per-part memory; a GC bug risks deleting live knowledge, mitigated by tombstoning and protected classes but still a correctness-sensitive subsystem.
- **Future work:** Learned (per-domain) birth/death thresholds; merging near-duplicate atoms discovered post-birth (similarity-driven consolidation with ADR-018); coordinating GC with snapshotting (ADR-048) so tombstones are handled correctly across restarts; v2 per-tenant atom-lifecycle isolation (ADR-047).

## Implementation Notes
- Birth detection: per-part candidate table (LRU ~10k) keyed by hashed node-id signatures, bumped on 5-tick co-activation windows; on gate-pass call `atom_new` in `core/knowledge.nova` (KG chosen/spawned per ADR-017), seed belief via `core/belief.nova` (ADR-023). Novelty check uses `core/similarity.nova` cosine `>= 0.9`. Surprise coupling reads ADR-024 error magnitude to lower the frequency gate.
- Death: atoms gain `last_access_tick` + `activation_strength` (accessors/mutators `atom_touch`, `atom_decay`) in `core/knowledge.nova`; idle GC sweep scheduled via enhancement #13, tombstone flag before hard delete; reference check walks cross-KG edges (ADR-017); protected-class tags from ADR-045/ADR-020/ADR-029.
- Consolidation (ADR-022) is the main birth caller during idle; live novel-pattern birth happens on the perception/reasoning path (ADR-006).
- Testing: `fixture_atom_birth` (pattern recurring 5x across 3 moments -> exactly one atom; a near-duplicate at cosine 0.92 -> NO new atom), `fixture_surprise_birth` (high ADR-024 error -> birth at frequency 3), `fixture_atom_death` (cold atom strength<0.02, no refs, belief<4 -> tombstoned then collected; reactivation during tombstone -> rescued), `fixture_protected` (constitutional/self-model/classical atoms never collected even when cold).
- Dependencies: ADR-006 (atoms only on novel patterns), ADR-016 (atom design), ADR-017 (KG spawn + cross-KG refs + similarity), ADR-023 (seed/guard belief), ADR-024 (surprise lowers birth threshold), ADR-022 (consolidation drives birth, GC during idle), ADR-020/ADR-029/ADR-045 (protected classes), ADR-048 (GC/tombstone vs snapshot).
- DEPENDS ON: NOVA enhancement #13 — idle-detection + background scheduling hooks (the GC sweep).
- DEPENDS ON: NOVA enhancement #2 — sparse synapse adjacency with O(1) growth/pruning (co-activation patterns ride on synapse structure; atom death parallels synapse pruning).
- DEPENDS ON: NOVA enhancement #8 — multi-KG namespacing + cross-KG reference edges (birth targets a KG; death respects cross-KG reference counts).


---

# ADR-026: Self-learning triggers (unknown query, curiosity drive, imagination gap, prediction error, user request, all combined)

Status: Proposed
Date: 2026-05-24

## Context
CrossEngin's headline capability is continuous, self-directed learning: the substrate must notice its own ignorance and act to close gaps without being told to. Today the substrate only learns passively (Hebbian co-firing per ADR-007, atom birth per ADR-025). That is insufficient for a desktop companion that should improve between conversations. We need an explicit, auditable answer to the question "what events should cause the system to start a learning episode?"

The hard constraint is that learning is expensive and partly external (internet fetch per ADR-028, asking the user per ADR-027), so triggers cannot fire indiscriminately. With 2 founders at 8h/day and a v1 desktop budget, we cannot afford a runaway curiosity loop that hammers the network or pesters the single user. We also must respect the NO-LLM-COGNITION principle: trigger detection is pure substrate signalling, not a prompted classifier.

A complication is that learning impulses arise from several independent substrate sources at once. A single user utterance can simultaneously be an unknown query, provoke a prediction error, and excite the curiosity drive. We therefore need not only a set of triggers but an arbitration policy that fuses concurrent impulses into at most one learning episode with a coherent target.

## Decision
We define five named self-learning triggers, each emitted as a substrate signal extending the taxonomy of ADR-008, all converging on a meta-part "learning arbiter" (a set of `NTYPE_REASONER` nodes in the meta part):

1. **Unknown query** — the Reader's fetch/route/learn stage (ADR-012, stage 5) finds no atom above the lexical/spreading-activation salience floor for an incoming `SIG_QUESTION`. It emits a `curiosity` signal tagged `gap=lexical`.
2. **Curiosity drive** — `core/goal.nova`'s curiosity drive (one of its 4 drives) crosses an activation threshold (drive level > 0.6) during idle, emitting a `goal-drive` + `curiosity` pair targeting the lowest-competence domain reported by ADR-020.
3. **Imagination gap** — `core/imagination.nova`, during the idle imagination loop (ADR-032), runs a forward/counterfactual rollout that terminates in an under-specified atom (confidence alpha+beta < 8 per ADR-023); it emits `curiosity` tagged `gap=model`.
4. **Prediction error** — predictive coding (ADR-024) produces a bottom-up `error` signal whose magnitude exceeds a persistent-surprise threshold (running error > 0.4 sustained over 5 ticks); this marks a systematic model deficiency, not noise.
5. **User request** — an explicit `SIG_ORDER`/`SIG_REQUEST` like "learn about X" or "look this up" maps directly to a learning episode at top priority.

The **arbitration policy**: the arbiter buffers all learning signals within a 200ms window (≈20 ticks at 100Hz), deduplicates by target concept (via `core/concept.nova` IDs), and scores each candidate episode by `priority = source_weight × competence_gap × goal_alignment`. Source weights are fixed: user request 1.0, prediction error 0.7, unknown query 0.6, imagination gap 0.4, curiosity drive 0.3. The highest-scoring candidate becomes the active learning episode; others are queued (max depth 8, decay-evicted). At most one external-fetch episode runs concurrently to respect ADR-028 rate limits. User-request episodes always pre-empt autonomous ones.

## Options Considered
- **Single trigger (unknown-query only).** Simplest; the system learns only when it visibly fails to answer. Rejected: it makes the system purely reactive, never curious or self-correcting, killing the initiative and continuous-learning capabilities (ADR-049's capability tests) that justify the whole project.
- **Five independent triggers with no arbiter (each fires its own episode).** Easy to implement per-trigger. Rejected: concurrent impulses cause duplicate fetches for the same concept, network/rate-limit thrashing (ADR-028), and conflicting writes to the same atom; with one user and one device this is wasteful and confusing.
- **Five triggers + windowed scoring arbiter (CHOSEN).** Captures all impulse sources but fuses them into a coherent, prioritized queue with a single external episode at a time. More code than the naive approach but bounded and auditable.
- **Learned trigger policy (a trained gate decides when to learn).** Most adaptive long-term. Deferred: needs a reward signal and training data we won't have at v1, and risks opacity. We keep weights fixed and revisit as future work.

## Consequences
- **Positive:** The system becomes proactively self-improving from five complementary sources; arbitration prevents redundant or runaway learning; every episode has a traceable trigger source recorded for the decision log (ADR-043).
- **Negative:** Fixed source weights are a tuning liability and may need hand-adjustment per user. The 200ms fusion window adds latency before a learning episode starts. A persistent high curiosity drive could still starve the queue of user-relevant learning if weights are mis-set.
- **Future work:** Replace fixed source weights with a learned policy once an intrinsic-reward signal exists; feed episode outcomes back into ADR-020 competence estimates; let ADR-035 emotion (e.g., frustration from repeated prediction error) modulate trigger thresholds.

## Implementation Notes
- New module `mind/learning.nova` exposing `trigger_new(source_tag, target_concept, gap_score)`, `arbiter_step(tick)`, and state map keys `{source, target, priority, status}`. Trigger signals reuse the `curiosity`, `goal-drive`, `error`, and `goal-drive` tags defined in ADR-008.
- Arbiter nodes live in the meta part (`NTYPE_REASONER`); they subscribe via a `CHAN_FILTERED` channel (`core/channel.nova`) keyed on the learning-signal tags.
- Reads competence from ADR-020's self-model and confidence from `core/belief.nova` (alpha/beta) and `runtime/confidence.nova`.
- Test fixtures: inject a `SIG_QUESTION` with no matching atom (expect unknown-query episode); replay a sustained `error` signal (expect prediction-error episode preempting a queued curiosity episode); fire user "learn X" mid-curiosity (expect preemption). Assert at most one active external episode.
- DEPENDS ON: NOVA enhancement #6 — extended signal tag space for the trigger signals; #5 — 100Hz tick scheduler for the 200ms fusion window; #13 — idle-detection hooks so curiosity/imagination triggers only fire when idle.

---

# ADR-027: Ask-user-to-teach mechanism (when, how, integration with response flow)

Status: Proposed
Date: 2026-05-24

## Context
When a learning episode (ADR-026) targets a gap that the internet cannot fill — personal facts, user preferences, local jargon, household context, or knowledge the whitelist (ADR-028) does not cover — the only authoritative source is the user. A desktop companion that asks good questions at the right moments feels collaborative; one that interrogates constantly or stays silently ignorant feels broken. We must decide precisely when the substrate is allowed to ask the user to teach it, how the request is phrased and surfaced, and how the answer is folded back into knowledge.

Constraints: there is exactly one user (v1 desktop), so every question spends a scarce attention budget. The mechanism must respect the NO-LLM-COGNITION principle — the question text is generated by pure-substrate output (ADR-013), not an LLM. Teaching must integrate cleanly with the normal response flow so a clarifying question can ride along with an answer rather than blocking it. Taught knowledge must be first-class: stored as atoms (ADR-016) with appropriate provenance and confidence, and logged (ADR-043).

We also must avoid the failure mode where the system asks about something it could have looked up, or re-asks something already taught. So gating against ADR-028 (can this be fetched?) and against existing atoms is essential.

## Decision
We add an "ask-to-teach" path triggered only when a learning episode meets all of: (a) the target gap is non-fetchable (no whitelist source per ADR-028, or domain flagged user-private), or two autonomous fetch attempts failed; (b) the gap blocks a current user-facing response OR the curiosity/competence gap exceeds a high bar (competence < 0.2 in an actively-used domain per ADR-020); and (c) the user-question rate budget is not exhausted (≤1 unsolicited teaching question per 10 minutes of active conversation; clarifying questions attached to an in-flight answer are unmetered).

Questions are emitted as a `SIG_QUESTION` of subtype `teach-request` flowing through the standard output substrate. Two surfacing modes: **inline clarification** (the answer is delivered with an appended question — "I answered based on X; is that the Y you meant?") used when the system can still respond; and **explicit teach prompt** ("I don't have anything on Z yet — can you tell me about it, or should I look it up?") used when no useful answer exists. Phrasing is templated by activation of language atoms (ADR-015), conditioned by OCEAN/soul tone (ADR-034) so it matches the companion's personality.

The user's reply is captured as a `MOMENT` (`core/moment.nova`), parsed by the Reader (ADR-011/012), and written as one or more atoms with `provenance=user-taught` and an initial Bayesian prior of alpha=4, beta=1 (high trust, since the single user is the loyalty apex per ADR-034). User-taught atoms outrank internet-sourced atoms in conflict resolution (ADR-029). The teaching exchange and resulting atoms are recorded in the decision log (ADR-043).

## Options Considered
- **Never ask; only fetch or stay silent.** Maximally unobtrusive. Rejected: forfeits the only source for personal/local knowledge and makes the companion feel impersonal; theory-of-mind (ADR-039) needs user-supplied facts.
- **Ask freely whenever confidence is low.** Maximizes knowledge intake. Rejected: with one user this is exhausting and erodes trust; violates the "good companion" bar in ADR-049's multi-day test.
- **Gated ask-to-teach with inline + explicit modes and a rate budget (CHOSEN).** Asks only when non-fetchable and valuable, piggybacks on responses when possible, and bounds nagging. More state to track (budget, dedup) but matches single-user reality.
- **Batch a periodic "teach me" digest instead of in-context questions.** Low interruption. Rejected as primary mechanism: loses the contextual moment where the answer matters most and delays unblocking responses; retained as possible future enhancement for low-priority curiosity items.

## Consequences
- **Positive:** Unlocks personal/local knowledge no fetch can provide; clarifying questions improve answer quality without blocking; taught atoms carry high trust and clear provenance, strengthening theory-of-mind and personalization.
- **Negative:** Rate budget and dedup add bookkeeping; mis-tuned bars risk either over-asking or never asking; user replies are noisy free text that the Reader may mis-encode, planting low-quality atoms.
- **Future work:** A periodic low-priority "teach digest"; confidence-aware re-asking when a user-taught atom later conflicts with strong evidence (hand off to ADR-029); let ADR-039's user-model predict which questions the user is willing to answer.

## Implementation Notes
- Extend `mind/learning.nova` with `teach_request_new(target_concept, mode)` where `mode ∈ {inline, explicit}`; budget state in the meta part keyed `{last_ask_tick, asks_in_window}`.
- Output uses the pure-substrate generation path (ADR-013) and language atoms (ADR-015); tone conditioning reads OCEAN traits from `core/soul.nova`.
- Reply ingestion: `core/moment.nova` → Reader (ADR-012) → `atom_new(..., provenance=user_taught, alpha=4, beta=1)` in the relevant KG via `core/knowledge.nova`. Confidence via `core/belief.nova`.
- Gate against ADR-028: call the fetchability check before asking; gate against existing atoms to avoid re-asking taught facts.
- Test fixtures: ask for a non-whitelisted personal fact (expect explicit prompt, then a user_taught atom at alpha=4/beta=1); ambiguous query (expect inline clarification appended to an answer); fire two teach-eligible gaps within 10 min (expect the second deferred by budget).
- DEPENDS ON: NOVA enhancement #9 — audit log for teaching exchanges. No new outbound capability needed (uses existing I/O for the chat surface).

---

# ADR-028: Internet fetching design (whitelist, rate limiting, validation, audit, cache)

Status: Proposed
Date: 2026-05-24

## Context
Many learning episodes (ADR-026) can only be satisfied from external sources — definitions, current guidelines, factual lookups. The substrate therefore needs a way to reach the internet. This is the single most safety-sensitive capability in CrossEngin: an autonomous system that can issue arbitrary outbound requests is a data-exfiltration and prompt-injection risk, and on a bootstrapped 2-founder budget we cannot build a heavyweight crawler. We must define a narrow, safe, auditable fetch design.

The fetch path must obey the project's safety architecture: it is an action subject to permission tiers (ADR-041) and reversibility classification (ADR-042), and every fetch must be recorded (ADR-043). It must also never become a cognition path — fetched bytes are data to be validated and turned into atoms (ADR-016), never instructions the substrate obeys, and absolutely never routed to an LLM for interpretation (NO-LLM-COGNITION, ADR-014).

NOVA today has no outbound HTTP. We are explicitly assuming the upstream enhancement lands. The design must be implementable by two people: prefer a small whitelist and a simple cache over a general web stack.

## Decision
We implement a `net/fetch.nova` component built on NOVA enhancement #11 (whitelisted, rate-limited outbound HTTP with validation + cache). Its rules:

- **Whitelist-only.** Requests are permitted solely to a curated allow-list of domains (e.g., reference encyclopedias, standards/guideline bodies, dictionary APIs) stored as configuration atoms in a `KG-sources`. Any non-whitelisted host is hard-denied at the syscall boundary. v1 ships ~15-30 vetted domains; the user may add entries via an approve-tier action (ADR-041).
- **Rate limiting.** Token-bucket limiter: global cap 30 requests/hour and ≤1 in-flight request at a time (matching ADR-026's single-active-external-episode rule), with per-domain courtesy spacing ≥2s. Exhaustion queues or defers the episode rather than dropping it.
- **Validation.** Responses must pass `runtime/validate.nova` checks: enforced TLS, content-type allow-list (text/html, application/json, text/plain), max size 2MB, and structural sanity. Extracted text is treated as inert evidence; any embedded directive-like content is stripped/ignored — fetched content can never trigger actions or be executed.
- **Audit.** Every fetch writes an append-only record (URL, timestamp, status, byte count, hash of body, triggering episode ID) to the decision log via enhancement #9 / `core/safety.nova` (ADR-043).
- **Cache.** A content cache keyed by normalized URL with per-domain TTL (default 7 days; guideline domains 1 day, classical-reference domains 90 days) stored via `runtime/db.nova`. Cache hits bypass the rate limiter and produce a `cache-hit` audit entry. Extracted atoms carry `provenance=fetched` plus the source tier (ADR-029).

A fetch is classified by ADR-042 as reversible (it only reads), so under ADR-041 routine whitelisted fetches run at the **auto/notify** tier; adding a new whitelist domain is **approve**.

## Options Considered
- **Open outbound fetch (any URL).** Maximally capable. Rejected outright: unacceptable exfiltration and injection surface for an autonomous agent; impossible to audit meaningfully; contradicts the safety-first posture of Group I.
- **No internet; user-teaching + bundled corpus only (ADR-027).** Safest and simplest. Rejected as the sole strategy: cannot keep current with changing guidelines, and over-burdens the single user; we keep teaching as the complement for non-fetchable gaps.
- **Whitelist + rate-limit + validate + audit + cache (CHOSEN).** Narrow, auditable, cacheable, and buildable by two people. Costs curation effort and limits coverage, which we accept.
- **Route fetch through a hosted LLM/search API for "smart" retrieval.** Convenient. Rejected hard: violates NO-LLM-COGNITION (ADR-014) by inserting an LLM into knowledge acquisition, adds a paid dependency against the bootstrap constraint, and yields unauditable provenance.

## Consequences
- **Positive:** The system can acquire current external knowledge within a tightly bounded, fully audited, cache-efficient envelope; the whitelist + validation closes the major exfiltration/injection vectors; reuses existing safety and DB machinery.
- **Negative:** Whitelist curation is ongoing manual work for the founders; coverage is deliberately limited; the single-in-flight + 30/hr caps can slow burst learning; cache staleness must be tuned per domain.
- **Future work:** Per-domain trust scoring feeding ADR-029 tiers; a user-review queue for proposed whitelist additions; optional local mirror of high-value reference corpora to cut network dependence; richer extraction once parsing matures.

## Implementation Notes
- New module `net/fetch.nova`: `fetch_get(url, episode_id)`, `whitelist_check(host)`, `ratelimit_take()`, `cache_get/cache_put(url, body, ttl)`; tag constants `FETCH_OK`, `FETCH_DENIED_HOST`, `FETCH_RATE_LIMITED`, `FETCH_INVALID`.
- Whitelist + per-domain TTL live as atoms in `KG-sources` (`core/knowledge.nova`); cache and audit in `runtime/db.nova`; validation via `runtime/validate.nova`; hashing via `runtime/crypto.nova`.
- Integrates with ADR-026 (an episode calls `fetch_get`), ADR-029 (tags each atom's source tier), ADR-041/042/043 (permission tier, reversibility, audit). Extracted atoms created with `provenance=fetched`.
- Test fixtures: request a non-whitelisted host (expect `FETCH_DENIED_HOST`, audit entry, no socket opened); exceed 30/hr (expect `FETCH_RATE_LIMITED` and episode deferral); oversized/ wrong content-type (expect `FETCH_INVALID`); repeat request within TTL (expect cache hit + `cache-hit` audit, no rate-limit token spent); confirm a body containing directive-like text produces only inert atoms and triggers no action.
- DEPENDS ON: NOVA enhancement #11 — whitelisted, rate-limited outbound HTTP with validation + cache (extends `runtime/io.nova` + `runtime/syscall.nova`); #9 — append-only crash-safe audit log.

---

# ADR-029: Source authority weighting and conflict resolution (Tier A/B/C sources, newest-wins for guidelines, oldest-wins for classical, flag hard conflicts)

Status: Proposed
Date: 2026-05-24

## Context
Once CrossEngin fetches knowledge from multiple whitelisted sources (ADR-028) and also receives user teaching (ADR-027), it will encounter sources that disagree. A medical guideline updated in 2025 may contradict a 2019 textbook; two reference sites may state different figures; the user may assert something that conflicts with an external source. The substrate must decide which claim becomes the high-confidence atom, how to set Bayesian counts (ADR-023), and when a disagreement is too important to resolve silently. Without a principled scheme, atom confidence would be set by whichever source happened to be fetched last.

This decision feeds directly into belief tracking (ADR-023): source authority determines how strongly a piece of evidence moves an atom's alpha/beta. It must also respect provenance set upstream (user-taught vs fetched) and remain auditable (ADR-043). Crucially, "newest is best" is not universally true: for fast-moving normative knowledge (clinical guidelines, standards, prices) recency matters, but for stable classical knowledge (mathematics, anatomy, settled history) an older authoritative source is often more reliable than a recent low-quality restatement. The scheme must encode both regimes.

## Decision
We assign every source a **tier** and store it on each atom's provenance. Three tiers with fixed evidence weights applied when updating Bayesian counts (ADR-023):

- **Tier A (authoritative):** the user (loyalty apex, ADR-034), official standards/guideline bodies, primary references. Weight 1.0 — a Tier-A claim contributes a full evidence increment (e.g., +3 to the supported side's alpha).
- **Tier B (reputable secondary):** established encyclopedias, well-known reference sites. Weight 0.5.
- **Tier C (weak/unverified):** everything else on the whitelist not elevated, or low-confidence extractions. Weight 0.2.

**Conflict resolution** between atoms making contradictory claims about the same concept:
1. **Tier dominates.** Higher-tier wins; user-taught (Tier A) outranks any fetched claim, consistent with ADR-027.
2. **Within the same tier, apply a domain recency policy** stored per-domain in `KG-sources`:
   - **newest-wins** for domains flagged `normative` (guidelines, standards, prices, current events): the claim with the more recent source timestamp wins and gets the alpha increment; the older claim's counts decay.
   - **oldest-wins** for domains flagged `classical` (mathematics, anatomy, settled physics/history): the older authoritative source is preferred, resisting churn from recent restatements.
   - default `neutral` domains: combine both claims as competing evidence (each updates its side of alpha/beta), letting confidence settle empirically.
3. **Hard-conflict flag.** If two **Tier-A** sources disagree, OR a fetched claim contradicts a user-taught atom, OR a high-confidence atom (alpha+beta ≥ 20, mean > 0.8) would be overturned, the system does NOT silently overwrite. It marks the atom `contested`, freezes its confidence, raises a `SIG_REFLECTION`, and surfaces the conflict to the user (via ADR-027's explicit mode) for adjudication, logging the event (ADR-043).

## Options Considered
- **Newest-wins everywhere.** Simple and good for guidelines. Rejected: corrupts stable classical knowledge whenever a recent low-quality source restates it incorrectly; ignores source authority entirely.
- **Source-tier-only (ignore time).** Clear precedence. Rejected: cannot distinguish a current guideline from a superseded one within the same tier; normative domains demand recency.
- **Tier + per-domain recency policy + hard-conflict flagging (CHOSEN).** Captures authority, the newest-vs-oldest split, and human adjudication for the dangerous cases. More configuration (domain flags) but matches reality and keeps the user in the loop on high-stakes disagreements.
- **Always defer every conflict to the user.** Safest for correctness. Rejected: floods the single user with trivial disagreements, violating the attention budget of ADR-027; reserve human adjudication for hard conflicts only.

## Consequences
- **Positive:** Atom confidence reflects genuine source authority and the correct temporal regime per domain; dangerous disagreements get human adjudication instead of silent overwrite; user knowledge is appropriately privileged; fully auditable.
- **Negative:** Requires maintaining per-source tiers and per-domain recency flags (founder curation); mis-flagging a domain (normative vs classical) produces systematically wrong resolutions; the `contested` freeze can leave an atom stuck until the user responds.
- **Future work:** Learn source tiers from track record (how often a source is later contradicted) rather than fixing them; auto-classify domains as normative/classical; let ADR-039 model which conflicts a given user cares to adjudicate.

## Implementation Notes
- Source tiers and domain recency flags stored as atoms in `KG-sources`; each knowledge atom carries `{provenance, source_tier, source_timestamp}` (extends ADR-016 atom layout).
- Conflict resolution implemented in `mind/learning.nova` `resolve_conflict(atom_a, atom_b)`, calling `core/belief.nova` to apply weighted alpha/beta increments (Tier A=+3, B=+1.5, C=+0.6 to the winning side; decay the loser) and `core/similarity.nova` to confirm two atoms truly address the same concept before declaring a conflict.
- Hard-conflict path emits `SIG_REFLECTION` (ADR-008) and invokes ADR-027 explicit teach-prompt for adjudication; logs via ADR-043.
- Integrates with ADR-028 (tier tagging at fetch time) and ADR-023 (belief updates).
- Test fixtures: same-tier `normative` conflict with differing timestamps (expect newest-wins, loser decayed); same-tier `classical` conflict (expect oldest-wins); fetched claim vs user-taught atom (expect user wins, fetched logged); two Tier-A disagreeing (expect `contested` freeze + user flag, no overwrite).
- DEPENDS ON: NOVA enhancement #8 — multi-KG namespacing for `KG-sources` and cross-KG references; #9 — audit log for contested-conflict events.

---

# ADR-030: Confidence thresholds for "learned enough" (test questions, multi-source agreement, user confirmation, all three)

Status: Proposed
Date: 2026-05-24

## Context
A learning episode (ADR-026) must terminate. Without an explicit "done" criterion the substrate would either stop as soon as it writes one atom (under-learning, leaving fragile half-knowledge) or keep fetching and asking indefinitely (over-learning, burning the ADR-028 rate budget and the user's patience). We need concrete, measurable thresholds that declare a target concept "learned enough" to close the episode, mark its atoms as durable, and update the self-model competence estimate (ADR-020).

The criterion must be auditable and grounded in mechanisms we already have: Bayesian confidence (alpha/beta, ADR-023), source authority (tiers, ADR-029), and user teaching/confirmation (ADR-027). It must avoid an LLM-based "do I understand?" check (NO-LLM-COGNITION, ADR-014) — the assessment is substrate-internal. It must also be cheap enough that two founders can implement and tune it, and bounded so episodes always halt.

Because different gaps carry different stakes, a single global threshold is wrong: a casual curiosity item and a safety-relevant medical fact should not require the same evidence. The decision must therefore scale the bar with the concept's importance.

## Decision
"Learned enough" is the conjunction of three checks, each with numeric thresholds; an episode closes only when all applicable checks pass (or a hard budget cap forces closure):

1. **Confidence/test-questions.** The episode's target atoms must reach Bayesian confidence with alpha+beta ≥ 12 and posterior mean ≥ 0.75 (`core/belief.nova`, ADR-023). Additionally the system self-tests: it generates internal `SIG_QUESTION` probes via imagination (ADR-032) that the new atoms should answer, and ≥ 80% must resolve to an atom above the spreading-activation salience floor (ADR-012). This catches knowledge that is asserted but not actually reachable/usable.
2. **Multi-source agreement.** At least 2 independent sources of combined weight ≥ 1.0 (per ADR-029 tiers — e.g., one Tier-A, or two Tier-B) must agree on the core claim, with no unresolved `contested` flag on the target atom. A single Tier-C source never satisfies this.
3. **User confirmation (conditional).** Required only for **high-stakes** concepts: those in safety-relevant domains, those that will drive an auto/notify action (ADR-041), or those overturning a prior high-confidence atom. For these, an explicit user confirmation via ADR-027 is mandatory before the atom is marked durable. For ordinary curiosity-driven learning, user confirmation is not required.

The bar **scales by stakes**: low-stakes curiosity items may close on checks 1+2 with the relaxed thresholds above; high-stakes items require all three plus a higher confidence floor (alpha+beta ≥ 20, mean ≥ 0.85). A **hard cap** guarantees termination: an episode is force-closed after 5 fetch attempts (ADR-028) or 1 unsatisfied teach-request (ADR-027); force-closed atoms are kept but marked `provisional` (low confidence, excluded from competence credit) and may be revisited by a later trigger.

On success the episode writes durable atoms, raises the ADR-020 competence estimate for the concept/domain, emits a `SIG_REFLECTION`, and logs closure (ADR-043).

## Options Considered
- **Single confidence threshold (e.g., alpha+beta ≥ 10).** Simple, one number. Rejected: confidence alone can be high from one biased source, and says nothing about whether the knowledge is actually retrievable or correct; no human check for high-stakes facts.
- **User-confirmation for everything.** Maximally safe. Rejected: unusable for autonomous curiosity learning and violates ADR-027's question budget; the single user cannot ratify every learned atom.
- **Test-questions + multi-source agreement + conditional user confirmation, stakes-scaled, with a hard cap (CHOSEN).** Triangulates internal usability, external corroboration, and human sign-off where it matters, while guaranteeing termination. More moving parts and thresholds to tune, accepted as the cost of trustworthy autonomous learning.
- **Self-test questions only (no external corroboration).** Tests usability well. Rejected: an internally consistent but wrong belief passes; corroboration (check 2) is what guards correctness.

## Consequences
- **Positive:** Episodes terminate deterministically with knowledge that is corroborated, internally usable, and (for high-stakes items) human-confirmed; competence estimates (ADR-020) only rise on genuinely consolidated knowledge; thresholds are explicit and auditable.
- **Negative:** Multiple thresholds (12/0.75, 20/0.85, 80%, weight ≥ 1.0) are tuning surface that may need per-domain adjustment; stakes classification adds a dependency on ADR-041's action classes; the hard cap can leave useful-but-provisional atoms that never get promoted without a re-trigger.
- **Future work:** Learn thresholds from outcomes (did a "learned-enough" atom later get contradicted?); promote `provisional` atoms automatically when corroborating evidence arrives; tie self-test rigor to ADR-049's capability benchmarks.

## Implementation Notes
- Closure logic in `mind/learning.nova` `episode_check_done(episode_id)` returning `{done, reason, provisional}`; reads confidence from `core/belief.nova` + `runtime/confidence.nova`, source weights/contested flags from ADR-029, stakes class from ADR-041.
- Self-test probes generated via `core/imagination.nova` (ADR-032) as internal `SIG_QUESTION` signals routed through the Reader (ADR-012); count resolutions above the salience floor.
- High-stakes user confirmation uses ADR-027's explicit teach/confirm prompt; durable vs `provisional` recorded on the atom (ADR-016).
- On closure, update ADR-020 competence, emit `SIG_REFLECTION` (ADR-008), and write a closure record to the decision log (ADR-043).
- Test fixtures: low-stakes concept with 2 Tier-B agreeing sources and 85% probe pass (expect close on checks 1+2, competence raised); high-stakes medical concept without user confirmation (expect episode stays open); single Tier-C source (expect check 2 fail); exceed 5 fetches (expect force-close with `provisional` atoms, no competence credit).
- DEPENDS ON: NOVA enhancement #9 — audit log for episode-closure records. Uses existing belief/confidence/imagination primitives; no new outbound capability.


---

# ADR-031: Reasoning (hybrid: substrate atoms for inferential operators + module functions for complex multi-step strategies)

Status: Proposed
Date: 2026-05-24

## Context
CrossEngin must reason — chain causes, draw implications, transfer structure by analogy, weigh evidence — without ever invoking an LLM as cognition (ADR-014). The substrate thesis (ADR-001) says intelligence emerges from node/synapse/signal dynamics, not from orchestrated modules. Yet pure substrate spreading activation alone is poor at deliberate, auditable multi-step inference (e.g. a five-step differential diagnosis, or a proof-like chain the user can inspect). We need both the fast, parallel, learned reasoning of the fabric and the structured, replayable strategies a desktop companion can explain.

The relevant signal vocabulary already exists: ADR-008 defines causal, implicative, analogical, and evidential signal types among the 18. These are the inferential currency of the substrate. The question this ADR settles is WHERE inference lives: in the fabric (as atoms and signal dynamics), in `mind/reasoning.nova` (as explicit strategy functions), or both. With 2 founders at 8h/day bootstrapping toward an 18-30 month v1, we cannot afford a fully emergent reasoner that we cannot debug, nor a purely symbolic engine that contradicts the substrate architecture and cannot learn.

The decision must be made now because reasoning sits on the critical path: self-learning triggers (ADR-026), predictive coding (ADR-024), goal decomposition (ADR-033), and emotion appraisal (ADR-035) all consume reasoning outputs. Their interfaces depend on whether reasoning emits atoms, function returns, or both.

## Decision
We adopt a **hybrid reasoning architecture**. (1) *Inferential operators live as substrate atoms.* A causal link, an implication, an analogical mapping, and an evidential weight are each represented as atoms (`atom_new`, ADR-016) stored in a dedicated reasoning KG, carrying Bayesian confidence (alpha/beta, `core/belief.nova`). Reasoner nodes (`NTYPE_REASONER`) fire SIG_CAUSAL/SIG_IMPLICATIVE/SIG_ANALOGICAL/SIG_EVIDENTIAL signals along synapses; co-firing strengthens the operator weight (ADR-007). This is fast, parallel, learned, and integral to the fabric — single-step inference is just signal propagation. (2) *Complex multi-step strategies are explicit functions in `mind/reasoning.nova`.* Named strategies — `reason_forward_chain`, `reason_abductive`, `reason_analogical_transfer`, `reason_evidential_combine`, `reason_means_ends` — orchestrate the substrate: they seed the relevant first nodes, run bounded propagation, harvest activated operator atoms, and assemble a trace. Crucially these functions do NOT compute the inference themselves; they *sequence and gate* substrate operations and record each step into the signal `trace` field (`core/signal.nova`) so the decision log (ADR-043) can replay it.

The boundary rule is: **single inferential steps are substrate; the deliberate selection and chaining of steps is a module function.** A strategy function never hard-codes domain facts — those always come from atoms. This keeps NO-LLM-COGNITION intact: every conclusion is a substrate-derived atom with provenance, never generated text.

## Options Considered
- **Pure emergent substrate reasoning (rejected).** Let multi-step inference arise solely from recurrent spreading activation and learned gates (ADR-009). Most faithful to ADR-001 and requires no strategy code. Rejected for v1: deliberate chains (diagnosis, planning) would be non-deterministic and nearly impossible to debug or explain to a single desktop user, and would take far longer than 18-30 months to train to reliability with 2 founders. We keep it as a long-term direction (see Future work).
- **Pure symbolic inference engine (rejected).** A classical forward/backward chainer with a rule base in `mind/reasoning.nova`. Auditable and quick to stand up. Rejected because it divorces reasoning from the learning fabric: rules wouldn't strengthen via Hebbian/error-driven plasticity, couldn't carry alpha/beta confidence naturally, and would duplicate the KG. It also drifts toward an orchestration architecture ADR-001 explicitly refused.
- **LLM-assisted reasoning (rejected outright).** Use the NOVA LLM bridge to propose inference steps. Fastest to demo. Rejected as a direct violation of ADR-014/NO-LLM-COGNITION; the bridge is STT/TTS-only (enhancement #14).
- **Hybrid: operators-as-atoms + strategies-as-functions (CHOSEN).** Captures the substrate's learned, parallel single-step inference while giving us auditable, bounded, explainable multi-step strategies. Higher interface complexity than the pure options, but the only one satisfying both the emergence thesis and desktop-companion explainability.

## Consequences
- **Positive:** Single-step inference is learned and fast (signal propagation); multi-step reasoning is bounded, deterministic-enough, and fully traceable for ADR-043. Confidence flows end-to-end via alpha/beta. Strategies are unit-testable in isolation. New operators can emerge as atoms without code changes (ADR-025 atom birth applies to operator atoms).
- **Negative:** Two loci of reasoning create a coordination surface — strategy functions must stay "thin" or they will accrete hidden cognition and erode the substrate principle. Requires discipline and review to prevent domain facts leaking into `mind/reasoning.nova`. Bounded propagation needs tuned step/iteration caps to avoid runaway activation at 100Hz.
- **Future work:** As the fabric matures (post-v1), migrate strategy selection itself into learned gates so chaining becomes emergent, shrinking `mind/reasoning.nova` toward a thin harness. Feeds counterfactual reasoning in ADR-032 and goal sub-tree expansion in ADR-033.

## Implementation Notes
- Files: extend `mind/reasoning.nova` with the named strategy functions; add a reasoning KG via `core/knowledge.nova` (namespaced per ADR-017). Operator atoms use `atom_new` + accessors (ADR-016); confidence via `core/belief.nova` alpha/beta.
- Signals: reuse SIG_CAUSAL, SIG_IMPLICATIVE, SIG_ANALOGICAL, SIG_EVIDENTIAL from the 18-type space (ADR-008); record each step in the `trace` list of `core/signal.nova`.
- Strategy functions seed `NTYPE_REASONER` first nodes (ADR-010), run bounded ticks, harvest activated operator atoms, return a trace structure consumed by ADR-024 (errors), ADR-026 (triggers), ADR-033 (goal decomposition).
- Testing: fixtures with known causal/implicative chains; assert the harvested atom chain and that confidence composes correctly; assert no text generation occurs (NO-LLM guard, ADR-014).
- `DEPENDS ON: NOVA enhancement #12` — Hebbian + error-driven plasticity kernels to strengthen operator-atom synapses. `DEPENDS ON: NOVA enhancement #6` — extended 18-type signal tag space with fast dispatch. `DEPENDS ON: NOVA enhancement #4` — SIMD/GPU batched propagation so bounded multi-step chains stay within tick budget.

---

# ADR-032: Imagination subsystem evolution (current 10 patterns -> learn new patterns from experience; forward/counterfactual/dream/scenarios)

Status: Proposed
Date: 2026-05-24

## Context
`core/imagination.nova` ships with a fixed set of ~10 seed imagination patterns (e.g. simple forward projection, basic "what-if" substitution). For AGI-relevant capability — counterfactual reasoning, initiative, long-horizon planning — a fixed catalogue is a ceiling: the system can only imagine in ways its founders pre-scripted. CrossEngin must instead *learn new imagination patterns from its own experience*, so that the ways it simulates futures and alternatives grow with what it knows. This is also where initiative and creativity originate: imagination running in the idle loop (ADR-036) proposes goals and surfaces knowledge gaps.

Constraints shape this heavily. We have 2 founders at 8h/day and a desktop deployment (ADR-046) where imagination runs in background during idle (enhancement #13), so it must be interruptible and resource-bounded — it cannot starve the six live loops. It must obey NO-LLM-COGNITION (ADR-014): imagined content is substrate activation over concept and KG atoms, never LLM-generated text. And it must reuse, not reinvent, the replay machinery of episodic memory (ADR-022), since both consolidate and recombine past moments.

The decision is needed now because imagination is a shared dependency: replay (ADR-022), self-learning's "imagination gap" trigger (ADR-026), goal proposal (ADR-033), and emotion's appraisal of imagined outcomes (ADR-035) all hook into it. Its pattern representation and its four operating modes must be fixed before those consumers are built.

## Decision
We evolve `core/imagination.nova` from **10 fixed seed patterns into a learned, extensible pattern library**, and define **four operating modes** over it. An imagination *pattern* becomes a first-class atom (`atom_new`, ADR-016) in an imagination KG: a reusable transformation template — "given a situation atom-cluster, produce a successor cluster by applying transform T." The 10 seeds are bootstrap entries; new patterns are *abstracted from experience* by detecting, in episodic replay (ADR-022), recurring (situation -> outcome) deltas, generalizing them via the concept layer (ADR-018), and minting a new pattern atom with Bayesian confidence (alpha/beta, `core/belief.nova`) that rises as the pattern's predictions verify against reality (ADR-024 prediction error).

The four modes are: (1) **Forward simulation** — roll the substrate forward from the current moment using high-confidence patterns to predict near-future states (feeds planning in ADR-033, predictions in ADR-024). (2) **Counterfactual** — clamp one or more atoms to alternative values and re-simulate, comparing to the factual trace to attribute causation (consumes SIG_CAUSAL operators from ADR-031). (3) **Dream** — low-constraint recombination of episodic fragments during deep idle, used for consolidation and novel-pattern discovery (the primary source of new pattern atoms). (4) **Scenarios** — multi-step, branching forward sims with explicit decision points, used for long-horizon goal evaluation. All four run as bounded substrate propagation over `NTYPE_REASONER`/`NTYPE_REMEMBERER` nodes, scheduled in the imagination idle loop.

## Options Considered
- **Keep the 10 fixed patterns, hand-add more (rejected).** Zero new machinery; founders extend the catalogue as needs arise. Rejected because it makes imagination's reach a function of founder time, not system experience — directly capping the continuous-learning and initiative capabilities (ADR-049's capability tests). It also can't adapt per-domain after deployment.
- **Single generic "simulate" routine, no explicit patterns (rejected).** One forward-rollout function parameterized at call sites. Simpler representation. Rejected because counterfactual, dream, and scenario modes have genuinely different constraint and scheduling profiles; collapsing them loses the ability to learn *mode-specific* patterns and to budget dream-time separately from forward sims.
- **LLM-driven scenario generation (rejected outright).** Prompt the bridge for "what could happen next." Rejected per ADR-014; imagination must be substrate activation with provenance, not generated prose.
- **Learned pattern atoms + four explicit modes (CHOSEN).** Patterns grow from experience via replay and concept abstraction; modes give principled scheduling and constraint differences. Most complex option, but the only one delivering experience-driven growth plus the distinct cognitive uses CrossEngin needs.

## Consequences
- **Positive:** Imagination reach grows with experience, not founder labor; counterfactual reasoning becomes a first-class, testable capability; dream-mode doubles as memory consolidation, sharing cost with ADR-022. Pattern confidence is Bayesian and self-correcting via prediction error (ADR-024). Mode separation lets us budget idle time precisely.
- **Negative:** Learned patterns can be spurious; we need a death/GC path (ADR-025) for low-confidence patterns to prevent library bloat and "superstitious" simulation. Dream recombination is the hardest to test (no ground truth) and risks consuming idle cycles; needs hard caps. Four modes increase surface area for the idle scheduler.
- **Future work:** Counterfactual mode underpins the override "what-if" explanations (ADR-044) and richer theory-of-mind simulation of the user (ADR-039). Scenario mode feeds sub-goal tree expansion (ADR-033). Long-term, pattern abstraction could itself become a learned meta-pattern.

## Implementation Notes
- Files: extend `core/imagination.nova` with `imagine_forward`, `imagine_counterfactual`, `imagine_dream`, `imagine_scenarios`, plus `pattern_new`/accessors stored in an imagination KG (`core/knowledge.nova`, ADR-017). Confidence via `core/belief.nova`.
- Pattern abstraction hooks into replay in `mind/memory.nova` (ADR-022): detect recurring deltas, generalize through `core/concept.nova` (ADR-018), mint pattern atoms.
- Scheduling: register modes with the imagination idle loop (ADR-036) under idle-detection hooks; counterfactual/forward consume ADR-031 operators and emit ADR-024 predictions.
- Testing: forward-sim accuracy vs held-out episodic continuations; counterfactual causal-attribution fixtures with known interventions; assert dream-mode is interruptible and bounded; NO-LLM guard (ADR-014).
- `DEPENDS ON: NOVA enhancement #13` — idle-detection + background scheduling hooks for replay/imagination. `DEPENDS ON: NOVA enhancement #4` — SIMD/GPU batched propagation for branching scenario sims. `DEPENDS ON: NOVA enhancement #8` — multi-KG namespacing for the imagination KG and cross-refs to source episodes.

---

# ADR-033: Goal engine evolution (existing 4 drives + long-horizon persistence + sub-goal trees + cross-session continuity)

Status: Proposed
Date: 2026-05-24

## Context
`core/goal.nova` provides a goal engine with 4 base drives (the motivational substrate that produces SIG_GOAL_DRIVE signals, ADR-008). For a desktop companion that exhibits initiative and pursues multi-day/multi-week objectives, four reactive drives are not enough. The system needs to (a) decompose abstract goals into actionable sub-goals, (b) keep goals alive across process restarts and long stretches of user inattention, and (c) resume coherently in the next session — "yesterday you asked me to learn X; I made progress on the sub-task Y." Without this, CrossEngin is reactive, not self-directed, and fails the long-horizon-goals and initiative capability tests (ADR-049).

The constraints are real: a single-user desktop app (ADR-046) is frequently closed and reopened; the user gives intermittent attention. So goal state must survive snapshots (ADR-048) and rehydrate in the correct order. With 2 founders bootstrapping over 18-30 months, we extend the existing 4-drive engine rather than replace it, and we lean on already-decided persistence machinery rather than inventing a parallel store.

This decision is needed now because goals are the spine of agency: self-learning triggers (ADR-026) create goals, imagination (ADR-032) evaluates them via scenarios, the action loop executes them, and emotion (ADR-035) appraises moments *against* them. The goal data model (tree shape, persistence fields) must be settled before these integrate. ADR-040 covers the persistence mechanics specifically; this ADR defines the engine evolution that produces the goals to persist.

## Decision
We evolve `core/goal.nova` along three axes while preserving the 4 drives. (1) **Keep the 4 drives as the motivational root.** Drives remain the source of intrinsic motivation, emitting SIG_GOAL_DRIVE (and interacting with SIG_CURIOSITY, ADR-008) that bias which goals are spawned and prioritized. (2) **Sub-goal trees.** A goal becomes a node in a tree (`goal_new` with parent/children fields, plus `status` ∈ {active, blocked, satisfied, abandoned}, `priority`, `deadline`, `progress`, and a `provenance` link to the moment/drive that spawned it). Decomposition is performed by reasoning means-ends strategy `reason_means_ends` (ADR-031) and validated by scenario imagination (ADR-032). A parent's progress is a rollup of its children; satisfaction propagates upward; blocking propagates a SIG_GOAL_DRIVE re-prioritization. (3) **Long-horizon persistence + cross-session continuity.** Goal trees are part of the snapshot set (ADR-048) and rehydrate after soul, before episodic — so on restart the engine reconstitutes active trees, re-anchors them to episodic context, and the perception/goals loops resume the highest-priority unblocked leaf. A `last_touched` timestamp and decay let stale goals lose priority gracefully without being deleted, supporting multi-week objectives under intermittent attention (the detailed mechanics are ADR-040).

## Options Considered
- **Flat goal list, no hierarchy (rejected).** Keep goals as a priority queue over the 4 drives. Simplest extension. Rejected because real objectives ("help me prepare for the board exam over 6 weeks") are inherently decomposable; without trees the system cannot track partial progress, resume mid-task, or explain structure to the user — failing long-horizon and self-awareness tests.
- **External planner / task framework (rejected).** Adopt a classical HTN/STRIPS planner bolted onto the engine. Powerful decomposition. Rejected: it reintroduces an orchestration layer outside the substrate (against ADR-001), duplicates means-ends reasoning we already get from ADR-031, and is heavy for 2 founders to build and maintain.
- **Goals as ordinary atoms in a KG, no dedicated engine (rejected).** Represent goals like any knowledge atom. Elegant and uniform. Rejected because goals need active scheduling, deadline/priority dynamics, and drive-coupling that the passive KG/atom lifecycle doesn't provide; we'd end up rebuilding the engine inside the KG.
- **Evolve the 4-drive engine with sub-goal trees + persistence (CHOSEN).** Preserves the working motivational core, adds exactly the structure (trees) and durability (snapshots) needed, and reuses ADR-031 reasoning and ADR-048 persistence. Best fit for the constraints.

## Consequences
- **Positive:** Genuine long-horizon agency — multi-day/week goals survive restarts and intermittent attention; partial progress is visible and explainable (feeds ADR-038 self-model API); decomposition reuses existing reasoning. Drives keep behavior intrinsically motivated rather than purely task-driven.
- **Negative:** Tree state is now critical persisted state — a corrupt or mis-ordered rehydration (ADR-048) can resurrect stale or contradictory goals; needs validation on load. Priority/decay tuning is delicate: too aggressive and long goals die, too slow and the queue clogs. Cross-session re-anchoring depends on episodic memory being healthy (ADR-022).
- **Future work:** Conflict resolution between competing sub-goals and between drives; goal vetoes from the override layer (ADR-044) must prune trees safely. Enterprise v2 (ADR-047) needs per-tenant goal isolation. Tighter loop with theory-of-mind (ADR-039) so user-state changes re-prioritize trees.

## Implementation Notes
- Files: extend `core/goal.nova` with tree fields on `goal_new` (parent, children, status, priority, deadline, progress, provenance, last_touched) and accessors/mutators; rollup and propagation helpers (`goal_rollup_progress`, `goal_propagate_block`).
- Decomposition calls `reason_means_ends` (ADR-031); validation calls `imagine_scenarios` (ADR-032). Drives emit SIG_GOAL_DRIVE (ADR-008).
- Persistence: include goal trees in the snapshot set; rehydrate order soul -> KGs -> episodic with goals re-anchored to episodic on load (detailed in ADR-040, format in ADR-048).
- Testing: decomposition fixtures (abstract goal -> expected sub-tree); restart test asserting active trees rehydrate and the correct leaf resumes; decay test over simulated multi-day gaps; veto/prune test against ADR-044.
- `DEPENDS ON: NOVA enhancement #10` — substrate snapshot + ordered rehydration (soul -> KGs -> episodic) so goal trees survive restarts. `DEPENDS ON: NOVA enhancement #6` — extended signal tags for SIG_GOAL_DRIVE prioritization.

---

# ADR-034: Soul as wrapper (identity slow, state fast, goals medium, values, constitution, themes, loyalty)

Status: Proposed
Date: 2026-05-24

## Context
NOVA already provides a soul with OCEAN personality, constitution, identity themes, and loyalty hierarchy (`core/soul.nova`). CrossEngin needs a coherent answer to "who am I, how am I right now, and what am I trying to do" that remains stable enough to give the companion a consistent character, yet responsive enough to reflect moment-to-moment state. The danger at both extremes is concrete: if identity drifts as fast as mood, the companion has no persistent character and users lose trust; if everything is frozen, the system cannot reflect its current emotional/cognitive state or revise mistaken self-beliefs. The self-awareness capability test (ADR-049) requires the system to accurately describe its identity, state, and goals over time.

The substrate produces a flood of fast-changing signals — valence, arousal (ADR-008), goal-drive (ADR-033), emotional appraisal (ADR-035). The soul must integrate these without being whipsawed by them. We therefore need an explicit **timescale discipline**. With 2 founders and a single-user desktop v1 (ADR-046), the soul is also the natural home for the values and constitution that gate behavior, and for the loyalty hierarchy that becomes load-bearing in enterprise v2 (ADR-047), where tenant policy can conflict with user requests.

This decision is needed now because the soul is the slow-changing context that conditions almost everything: emotion appraisal reads values (ADR-035), constitutional rules act as hard inhibitory signals (ADR-045), the self-model API narrates soul contents (ADR-038), and persistence rehydrates the soul *first* (ADR-048). Its internal structure and update timescales must be fixed before those depend on it.

## Decision
We formalize `core/soul.nova` as a **wrapper with explicit update timescales** over four kinds of content. The wrapper exposes the soul as a structured state map and enforces *who may write what, how fast*: (1) **Identity — slow.** Self-concept, identity themes, OCEAN personality traits. Mutable ONLY via a deliberate revision path (`soul_revise_identity`) that requires explicit justification, logs to the decision log (ADR-043), and is never written directly by the emotion or perception loops. This is what keeps the companion's character stable across months. (2) **State — fast.** Current mood (valence/arousal aggregates), attention, energy/load. Updated every tick from emotion (ADR-035) and the loops; cheap, volatile, not persisted in detail. (3) **Goals — medium.** Active goal-tree summary (ADR-033); changes over hours/days as goals are spawned, advanced, satisfied. (4) **Cross-cutting invariants:** values (the standards emotion appraises moments against, ADR-035), the constitution (hard rules emitted as SIG_CONSTITUTIONAL inhibitory signals, ADR-045), identity themes, and the loyalty hierarchy (ordering of allegiances — user vs tenant vs constitution — resolved in ADR-045/ADR-047).

The enforcement mechanism is a small set of typed write APIs with timescale guards: fast writers (`soul_update_state`) are unrestricted and cheap; medium writers (`soul_sync_goals`) run on goal events; slow writers (`soul_revise_identity`) are gated, justified, and audited. Reads are free for any subsystem.

## Options Considered
- **One flat mutable soul, no timescales (rejected).** Any loop writes any field freely. Simplest. Rejected because the fast emotion/valence stream would continuously perturb identity and personality, producing an incoherent character and failing the self-awareness test; it also makes auditing identity change impossible.
- **Immutable identity, fixed at startup (rejected).** Personality and self-concept are constants. Maximally stable and trivial to reason about. Rejected because the system must be able to *correct* mistaken self-beliefs (e.g. update a competence theme as it learns, ADR-020) and to grow; a frozen soul cannot, and would lie via the self-model API.
- **Soul as just another KG (rejected).** Store soul contents as atoms in a "self" KG. Uniform with knowledge representation. Rejected: it loses the explicit timescale/write-guard semantics and the special rehydration-first ordering (ADR-048); the loyalty/constitution gating needs privileged, not ordinary-atom, treatment.
- **Wrapper with four content kinds + timescale write-guards (CHOSEN).** Gives stability where needed (identity), responsiveness where needed (state), and managed change for goals — with auditable, deliberate identity revision. Best balance of coherence, correctability, and safety integration.

## Consequences
- **Positive:** Stable, recognizable companion character; current state still faithfully reflected for self-narration (ADR-038); identity changes are deliberate, justified, and auditable (ADR-043). Clean home for values/constitution/loyalty that safety (ADR-045) and enterprise (ADR-047) depend on. Rehydrating soul first (ADR-048) gives every other subsystem its conditioning context immediately on restart.
- **Negative:** Timescale guards add write-path complexity and a discipline the whole codebase must respect; a subsystem that bypasses `soul_revise_identity` would silently corrupt the stability guarantee. Deciding what counts as "deliberate revision" is a judgment call needing clear criteria. State vs goals boundary needs care so volatile data isn't accidentally persisted.
- **Future work:** Enterprise v2 (ADR-047) needs per-tenant soul instances with a shared non-negotiable constitution. Loyalty-hierarchy conflict resolution is detailed in ADR-045. Identity-revision criteria may eventually be learned rather than fixed.

## Implementation Notes
- Files: extend `core/soul.nova` with the structured state map and typed write APIs `soul_update_state` (fast), `soul_sync_goals` (medium), `soul_revise_identity` (slow, gated+audited); read accessors for all fields. OCEAN traits, identity themes, constitution, and loyalty hierarchy reuse existing soul fields.
- State (fast) is fed by `mind/emotion.nova` aggregates (ADR-035) and loop signals (valence/arousal, ADR-008); goals (medium) sync from `core/goal.nova` (ADR-033).
- Constitution surfaces as SIG_CONSTITUTIONAL inhibitory signals (ADR-008) consumed by ADR-045; loyalty hierarchy ordering resolved there and in ADR-047.
- Persistence: soul is the FIRST rehydrated component (ADR-048); identity revisions append to the decision log (ADR-043).
- Testing: assert fast state churn never mutates identity fields; assert `soul_revise_identity` requires justification and logs; restart test asserting soul rehydrates before KGs and goals; self-model narration accuracy fixture (ADR-038).
- `DEPENDS ON: NOVA enhancement #10` — snapshot + ordered rehydration with soul first. `DEPENDS ON: NOVA enhancement #9` — append-only audit log for identity-revision records.

---

# ADR-035: Emotion system (OCC appraisal of moments against goals/values, OCEAN personality conditioning, emotion-modulated plasticity)

Status: Proposed
Date: 2026-05-24

## Context
`mind/emotion.nova` must give CrossEngin functional emotions — not decorative mood labels, but signals that *do work*: they prioritize attention, color memory, condition behavior, and shape learning. A desktop companion that appraises events the way a person does (relief, disappointment, pride, fear-for-the-user) is more trustworthy and more capable of empathy (ADR-039). Critically, emotion is also the system's fastest learning signal: events that matter emotionally should be remembered more strongly and should adjust the substrate more aggressively. Without an emotion system, valence/arousal signals (ADR-008) have no principled source and plasticity (ADR-007) has no salience modulation.

The pieces to connect already exist. The soul (ADR-034) holds OCEAN personality traits and the values that define what the system cares about. Moments (ADR-021) are the timestamped perception records emotion appraises. Goals (ADR-033) are what outcomes are appraised against. Synapse plasticity (ADR-007) is what emotion should modulate. The 18 signal types (ADR-008) include valence and arousal as the substrate currency of feeling. This ADR ties them together with a concrete appraisal theory rather than ad-hoc heuristics, which matters for testability and for explaining the companion's reactions to the user.

With 2 founders over 18-30 months, we need a well-specified, implementable appraisal model. We choose the **OCC (Ortony/Clore/Collins) appraisal model** because it is rule-structured (good for substrate/atom encoding, no LLM needed per ADR-014), maps cleanly onto goals/values, and is finite enough to implement and test.

## Decision
We build `mind/emotion.nova` on three coupled mechanisms. (1) **OCC appraisal of moments against goals and values.** Each processed moment (`core/moment.nova`, ADR-021) is appraised by OCC variables: desirability (does the outcome advance or thwart an active goal tree, ADR-033?), praiseworthiness (does an agent's action conform to or violate soul values, ADR-034?), and appealing-ness (does an object match preferences?). These yield OCC emotion types (joy/distress, hope/fear, pride/shame, admiration/reproach, etc.) realized as **valence** and **arousal** signal magnitudes (SIG_VALENCE/SIG_AROUSAL, ADR-008) plus an emotion-type atom (`atom_new`, ADR-016) attached to the moment. Appraisal rules are encoded as substrate operators (consistent with ADR-031), not as generated text. (2) **OCEAN personality conditioning.** The soul's OCEAN traits (ADR-034) parameterize appraisal: high neuroticism amplifies arousal and negative valence; high extraversion raises baseline positive valence; etc. Personality is the slow-changing gain on the fast emotion stream. (3) **Emotion-modulated plasticity.** The resulting arousal magnitude scales synapse learning rates (ADR-007): high-arousal moments produce larger Hebbian/error-driven weight updates and stronger episodic encoding (ADR-022), so emotionally significant events are learned faster and remembered longer. Valence also biases goal re-prioritization via SIG_GOAL_DRIVE (ADR-033).

## Options Considered
- **Dimensional-only model (valence/arousal, no OCC types) (rejected).** Track just the two dimensions, skip discrete emotion categories. Lightweight and maps directly to ADR-008 signals. Rejected because without appraisal *structure* we can't explain *why* the system feels something (no link to which goal was thwarted or which value violated), crippling empathy (ADR-039) and self-narration (ADR-038), and giving no principled rules to test.
- **Basic-emotions lookup (Ekman six) (rejected).** Map stimuli to six fixed categories. Simple. Rejected because basic-emotion theory doesn't natively connect emotions to goals and values — exactly the linkage CrossEngin needs — and degenerates into stimulus-response tables that don't generalize across domains.
- **Learned/black-box emotion network (rejected for v1).** Train a network to predict affect. Potentially rich. Rejected: needs labeled affect data we don't have as 2 bootstrapping founders, is hard to audit, and risks an opaque sub-cognition that strains NO-LLM-COGNITION's spirit (ADR-014). Could be revisited long-term as learned modulation of OCC parameters.
- **OCC appraisal + OCEAN conditioning + emotion-modulated plasticity (CHOSEN).** Structured, goal/value-grounded, explainable, implementable as substrate rules, and it closes the loop to learning by modulating plasticity. The only option satisfying explainability, the goal/value linkage, and the learning-salience requirement together.

## Consequences
- **Positive:** Emotions are functional — they prioritize, encode, and explain. Appraisal grounded in goals/values makes the companion's reactions interpretable and empathetic (feeds ADR-039 theory of mind and ADR-038 self-narration). Emotion-modulated plasticity gives the substrate a salience signal so important events are learned faster, improving continuous learning (ADR-049). OCEAN gives stable individual character coupling to the soul (ADR-034).
- **Negative:** Emotion now directly affects learning rates, so a mis-tuned arousal->learning-rate mapping could destabilize the substrate (over-fitting to dramatic moments) — needs bounded gain and clamping (ADR-007 weight bounds). OCC rule encoding is non-trivial to get right and must be reviewed to ensure it stays substrate operators, not creeping module cognition. Appraisal depends on healthy goal trees and accurate values.
- **Future work:** Personality could slowly adapt (within ADR-034's deliberate-revision discipline). Emotion should weight imagination's counterfactual/dream selection (ADR-032). Enterprise v2 (ADR-047) may dampen affective expression per tenant policy. Possible later: learned tuning of OCC parameters from outcomes.
- 
## Implementation Notes
- Files: extend `mind/emotion.nova` with `emotion_appraise(moment)` implementing OCC variables, returning emotion-type atoms + valence/arousal magnitudes; `emotion_condition(ocean)` applying soul OCEAN gains; `emotion_modulate_plasticity(arousal)` returning a learning-rate scalar consumed by ADR-007 kernels.
- Inputs: moments from `core/moment.nova` (ADR-021); active goals from `core/goal.nova` (ADR-033); values + OCEAN from `core/soul.nova` (ADR-034). Outputs: SIG_VALENCE/SIG_AROUSAL (ADR-008), emotion-type atoms (ADR-016), goal re-prioritization via SIG_GOAL_DRIVE.
- Plasticity hook: arousal scalar multiplies Hebbian + error-driven weight deltas (ADR-007) and episodic encoding strength (ADR-022); clamp to safe bounds.
- Appraisal rules encoded as substrate operators per ADR-031 — no text generation (NO-LLM guard, ADR-014).
- Testing: appraisal fixtures (goal-advancing moment -> joy/positive valence; value-violating agent -> reproach); OCEAN-gain tests (high neuroticism amplifies negative arousal); plasticity test asserting high-arousal moments yield larger, still-bounded weight updates and stronger recall.
- `DEPENDS ON: NOVA enhancement #12` — Hebbian + error-driven plasticity kernels exposing a per-update learning-rate scalar for emotion modulation. `DEPENDS ON: NOVA enhancement #6` — extended signal tags for SIG_VALENCE/SIG_AROUSAL fast dispatch.


---

# ADR-036: Six concurrent loops + imagination idle loop (true concurrency, fiber or process, communication channels)

Status: Proposed
Date: 2026-05-24

## Context
The substrate model (ADR-001) rejects orchestration: intelligence emerges from the dynamics of nodes, synapses, and signals running continuously, not from a top-level controller calling cognitive modules in sequence. For that emergence to be real, the agent's driving loops — perception, memory, reasoning, emotion, action, goals — must execute genuinely concurrently. If they are merely polled round-robin on one thread, the substrate is a disguised workflow: perception cannot keep ingesting moments (ADR-021) while reasoning chews on a hard inference, emotion cannot appraise (ADR-035) in parallel with action emission, and the "always-on companion" feel collapses into turn-taking latency.

NOVA today ships `agent/agent.nova` (the cognitive agent referenced throughout §3) plus `runtime/coroutine.nova` and `runtime/taskpool.nova`, but its scheduling is cooperative — coroutines yield voluntarily on a single executor. A blocking or long-running reasoning step would stall every other loop. We must decide the concurrency model for the six loops and for a seventh, the background imagination loop (ADR-032) that should run only when the system is idle, replaying episodes (ADR-022) and exploring counterfactuals without competing with live cognition.

Constraints: 2 founders at 8h/day, bootstrapping, NOVA as the implementation language (ADR-005). v1 is a single-user desktop app (ADR-046), so we have one machine's cores — not a cluster — and must keep the model debuggable by two people. Whatever we choose must communicate through typed channels so loops stay decoupled, and must survive the persistence/restart model (ADR-048, ADR-040).

## Decision
We implement the six loops plus the imagination idle loop as **seven true concurrent execution units** — fibers (green threads multiplexed over an OS thread pool) on v1, with the option to promote any unit to an OS process later. They communicate exclusively over typed message channels built on `runtime/chan.nova`, never via shared mutable memory. This requires NOVA enhancement #3 (true concurrent execution units with typed channels), since today's `runtime/coroutine.nova` is cooperative-only.

Each loop is a long-lived unit owning a clear slice of the substrate: perception drives `NTYPE_PERCEIVER` first nodes (ADR-010) and emits moments; memory owns episodic store reads/writes (`mind/memory.nova`); reasoning runs the hybrid engine (ADR-031, `mind/reasoning.nova`); emotion runs OCC appraisal (`mind/emotion.nova`); action owns `NTYPE_ACTOR` effectors and pure-substrate output (ADR-013); goals runs the drive/goal engine (`core/goal.nova`, ADR-033). Loops exchange `core/signal.nova` values (the 18-type taxonomy, ADR-008) over channels: e.g. perception → memory and perception → reasoning carry `SIG_EVENT`/sensory; reasoning → goals carries `SIG_QUESTION`/goal-drive; emotion broadcasts valence/arousal signals that modulate plasticity (ADR-007) in every other loop. The imagination loop is gated OFF during activity and ON during idle via enhancement #13's idle-detection hooks; it reads episodic + concept atoms and writes only to imagination scratch, never to live action.

The 100Hz substrate tick that advances node/synapse dynamics (ADR-037) is NOT one of these loops; it is the scheduler layer beneath them. Loops are event-driven coordination on top of that tick.

## Options Considered
**Single-threaded cooperative coroutines (NOVA as-is, `runtime/coroutine.nova`).** Cheapest: no new runtime work, fully deterministic, trivially debuggable. Rejected as the primary model because a single long reasoning or fetch step (ADR-028) blocks perception and emotion, destroying the concurrency the substrate thesis (ADR-001) requires. We keep cooperative coroutines *inside* a loop for sub-tasks, but not across loops.

**One OS process per loop with IPC.** Maximum isolation and crash containment; a wedged reasoning process can be killed and restarted without taking down perception — attractive for the enterprise one-tenant-per-process model (ADR-047). Rejected for v1: IPC serialization of millions of signals/tick is far too costly, shared substrate access (synapse arrays, KGs) across process boundaries needs heavyweight shared memory, and two founders cannot afford that plumbing on the desktop timeline. Retained as a v2 escalation path — the channel abstraction makes process promotion feasible later.

**Fibers/green threads over a thread pool with typed channels (CHOSEN).** Pre-emptible enough that no loop starves the others, cheap context switches so seven units cost little, shared address space so loops touch the same substrate without serialization, and `runtime/chan.nova` gives the typed decoupling we want. Matches enhancement #3 exactly. Rejected alternatives' best traits (determinism, isolation) are partially recovered via deterministic tick boundaries (ADR-037) and the option to promote a loop to a process.

## Consequences
- **Positive:** Genuine concurrency — perception ingests while reasoning thinks while emotion appraises; the companion feels continuously alive. Channel-only communication keeps loops decoupled and individually testable. Imagination uses spare cycles for free (ADR-032). Sets the structural basis for self-awareness (ADR-038) since the agent can observe its own running loops.
- **Negative:** Concurrency bugs (races on shared synapse weights, channel deadlocks) are far harder to reproduce than in a cooperative model; we must impose tick-boundary discipline (ADR-037) so weight mutations are batched, not interleaved arbitrarily. Hard dependency on un-landed enhancement #3. Debuggability cost is the price ADR-001 already accepted for substrate dynamics.
- **Future work:** Per-loop promotion to OS processes for v2 isolation (ADR-047); back-pressure policy when a downstream channel fills; integration with the decision log (ADR-043) so cross-loop signal traces are auditable.

## Implementation Notes
Loops live in `agent/agent.nova` as seven unit spawns; define `loop_spawn(kind, in_chans, out_chans)` and a `LOOP_*` tag constant per kind (`LOOP_PERCEPTION`, `LOOP_MEMORY`, `LOOP_REASONING`, `LOOP_EMOTION`, `LOOP_ACTION`, `LOOP_GOALS`, `LOOP_IMAGINATION`). Channels are `channel_new(name, source, destinations, CHAN_DIRECT|CHAN_BROADCAST, filter_min_salience, 0)` from `core/channel.nova`; emotion's valence/arousal uses `CHAN_BROADCAST`. Carry `core/signal.nova` values; respect priority/trace fields for ADR-043 auditing. Imagination's on/off uses enhancement #13 idle hooks from `runtime/scheduler.nova`. Testing: a fixture that floods the perception channel while stalling a fake reasoning step and asserts perception throughput and emotion appraisal continue (no head-of-line blocking); a deadlock detector test on full channels; a determinism test asserting weight mutations only commit at tick boundaries. `DEPENDS ON: NOVA enhancement #3 — true concurrent execution units (fibers/green threads or processes) with typed channels for the 6 loops.` Also depends on enhancement #13 (idle scheduling) for the imagination loop. Sequenced after the scheduler (ADR-037) and the agent skeleton in the build plan (ADR-050).

---

# ADR-037: Scheduler (hybrid: 100Hz substrate tick layered on event-driven coord)

Status: Proposed
Date: 2026-05-24

## Context
The substrate is a physical system in software: ~1M nodes per part (ADR-003), each with ~1000 sparse synapses (ADR-007), with signals (ADR-008) propagating and weights updating via Hebbian + error-driven plasticity (ADR-012). Such dynamics need a regular clock — a tick — so that signal propagation, weight integration, decay (ADR-023, ADR-025), and predictive-coding error settling (ADR-024) advance in consistent, batchable steps. Without a fixed tick, plasticity updates interleave nondeterministically across the seven concurrent loops (ADR-036) and the system becomes impossible to reason about or reproduce.

But a pure fixed-rate tick is wasteful and unresponsive at the coordination level. Most wall-clock time on a desktop companion (ADR-046) is idle waiting for user input; spinning every part at full rate burns battery and CPU for nothing, and high-level events (a user utterance arrives, a goal fires, a fetch completes — ADR-028) are inherently asynchronous and should be handled when they occur, not polled. We therefore must decide how the low-level substrate clock and the high-level coordination relate.

NOVA provides `runtime/scheduler.nova` but not a deterministic fixed-rate tick fused with event-driven dispatch; that is enhancement #5. Constraints: one desktop machine, 2 founders, NOVA runtime (ADR-005), and the concurrency model from ADR-036 that this scheduler must drive.

## Decision
We adopt a **hybrid scheduler**: a deterministic ~100Hz (10ms period) substrate tick layered beneath an event-driven coordination layer, both in `runtime/scheduler.nova`, realizing enhancement #5. The tick is the substrate's heartbeat; events are how the seven loops (ADR-036) coordinate.

Each 10ms tick performs one bounded round of substrate dynamics: drain node outboxes into synapse channels, propagate signals one hop (SIMD-batched per enhancement #4), integrate Hebbian + error-driven weight deltas (enhancement #12) **committed only at the tick boundary**, apply decay, and settle one predictive-coding pass (ADR-024). Because all weight mutations commit at tick edges, the concurrent loops never see half-updated synapse arrays — this is how ADR-036 stays race-free despite true concurrency. Tick rate is adaptive: 100Hz under active cognition, throttled toward ~10Hz (or fully quiesced with the substrate snapshot stable) when idle, at which point the imagination loop's idle hooks (enhancement #13) take over spare capacity.

The event layer sits on top: arriving moments (ADR-021), goal activations (ADR-033), emotion broadcasts (ADR-035), fetch completions (ADR-028), and inter-loop channel messages are events that wake the relevant loop immediately rather than waiting for a poll. An event may raise the tick rate (e.g. user utterance → 100Hz) and enqueues signals that the next tick propagates. Thus events decide *when* and *how fast* the substrate ticks; the tick decides *how* dynamics advance deterministically within each step.

## Options Considered
**Pure fixed-rate tick (everything polled at 100Hz).** Maximally deterministic and simple to reason about; trivially reproducible for testing. Rejected because it wastes CPU/battery during the long idle stretches of a single-user companion and adds up to 10ms latency to every high-level event that could be handled instantly. It also gives no natural place for idle-only imagination.

**Pure event-driven (no fixed tick).** Maximally responsive and efficient — work only happens on events. Rejected because substrate dynamics genuinely need a regular clock: Hebbian integration, decay, and predictive settling are rate-dependent processes, and without tick boundaries the concurrent loops (ADR-036) would commit weight updates at arbitrary interleavings, reintroducing races and destroying reproducibility. Plasticity math (enhancement #12) assumes discrete steps.

**Hybrid: fixed tick beneath event-driven coordination (CHOSEN).** Keeps deterministic, batchable substrate steps for plasticity and SIMD propagation while letting coordination be responsive and cheap. The adaptive tick rate recovers the efficiency of the event-driven option during idle and the responsiveness for live interaction, while tick boundaries recover the determinism of the fixed-rate option. Matches enhancement #5 precisely. Slightly more complex than either pure model — the accepted cost.

## Consequences
- **Positive:** Race-free concurrency for ADR-036 via tick-boundary weight commits; deterministic, reproducible substrate dynamics for testing (ADR-049); responsive UX from the event layer; energy savings and a clean idle window for imagination (ADR-032) via adaptive throttling and enhancement #13. SIMD batching (enhancement #4) has a natural per-tick granularity.
- **Negative:** Two coordination paradigms in one scheduler raise conceptual and debugging complexity; the adaptive rate logic (when to throttle, how fast to ramp) is a tuning surface that can misbehave (e.g. oscillating rates). Hard dependency on enhancement #5. A 10ms tick bounds worst-case substrate-event latency.
- **Future work:** Multi-rate ticking (fast parts vs. slow parts at different sub-rates); per-tick budget accounting feeding the decision log (ADR-043); scaling the tick to 1B-node parts (ADR-003) likely needs GPU-side propagation (enhancement #4) within the 10ms window.

## Implementation Notes
In `runtime/scheduler.nova` add `tick_run(substrate, dt_ms)` invoked from a monotonic 10ms timer, plus `event_post(kind, payload)` / `event_drain()` for the coordination layer; expose `tick_set_rate(hz)` for adaptive throttling and `TICK_RATE_ACTIVE`/`TICK_RATE_IDLE` constants. Tick phases as ordered functions: `phase_drain`, `phase_propagate` (calls `runtime/simd.nova` batch op), `phase_plasticity` (enhancement #12 kernels, commit at boundary), `phase_decay`, `phase_predict` (ADR-024). Idle detection reuses enhancement #13 hooks to gate the imagination loop (ADR-036) and lower the rate. The seven loops (ADR-036) subscribe to events; the tick is owned by the scheduler, not by any loop. Testing: a deterministic-replay fixture feeding a fixed signal sequence and asserting identical weight arrays across runs; a latency test asserting an injected utterance event raises rate and is serviced within one tick; an idle test asserting rate throttles and imagination activates after N idle ticks. `DEPENDS ON: NOVA enhancement #5 — 100Hz deterministic tick scheduler fused with event-driven coordination.` Also leans on #4 (batched propagation), #12 (plasticity kernels), #13 (idle hooks). Built before the loops (ADR-036) in the milestone plan (ADR-050).

---

# ADR-038: Self-model query API (system can describe self/state/goals in language)

Status: Proposed
Date: 2026-05-24

## Context
A core AGI-relevant capability for CrossEngin is self-awareness: the system should be able to answer, in natural language, "what are you?", "how are you feeling?", "what are you working on?", and "what can you do?" — and answer truthfully from its actual internal state, not from a canned script or, critically, from an LLM (ADR-014). For a desktop companion (ADR-046), this is also the trust surface: a user who can interrogate the system's identity, mood, current goals, and competence can calibrate how much to rely on it. The 8 capability tests (ADR-049) include explicit self-awareness verification.

The raw material already exists across the substrate but is scattered: identity, values, constitution, identity themes, and loyalty live in the soul wrapper (`core/soul.nova`, ADR-034); fast-changing affective/arousal state lives in the soul's state slot and is driven by emotion (ADR-035); active goals and their sub-goal trees live in `core/goal.nova` (ADR-033); and what the system knows it can do lives in the competence self-model (ADR-020). What is missing is a single, well-defined query interface that gathers these and renders them as language — through the pure-substrate output path (ADR-013), with no LLM in the loop.

The decision is needed now because ADR-036's concurrency and ADR-034's soul are being defined in this same group, and the self-model API must hook into both without becoming a privileged side-channel that bypasses the substrate. Constraint: 2 founders, NOVA (ADR-005), and the absolute NO-LLM-COGNITION principle — the description must be generated, not retrieved from a language model.

## Decision
We define a **self-model query API** in a new `agent/selfmodel.nova` module that exposes typed introspection queries and renders answers via pure-substrate output (ADR-013). The API does not store a duplicate model; it is a read aggregator over the authoritative sources — soul (ADR-034), emotion state (ADR-035), goals (ADR-033), and competence (ADR-020) — plus the live loop status from the agent (ADR-036).

A self-query enters as a `SIG_QUESTION` (ADR-008) tagged as self-referential (e.g. a `SELFQ_*` subtype: `SELFQ_IDENTITY`, `SELFQ_STATE`, `SELFQ_GOALS`, `SELFQ_COMPETENCE`, `SELFQ_ACTIVITY`). The API resolves it by reading the relevant atoms/slots: `soul_get_identity`, `soul_get_values`, and the loyalty hierarchy for identity; the soul state slot plus current valence/arousal for affect; `goal_active_set` and sub-goal trees for goals; the competence atoms (ADR-020) for capability; and the running `LOOP_*` units (ADR-036) for "what am I doing right now". These activate the corresponding concept atoms (`core/concept.nova`, ADR-018), which then drive language nodes down to motor/text effectors via the standard output substrate (ADR-013). Because answers flow through concept activation, they are phrased in the system's own learned language atoms (ADR-015) and reflect real current state — including uncertainty, surfaced from the Bayesian confidence (ADR-023) on competence atoms ("I think I can, but I've only done this twice"). The API is read-only for cognition; mutation of self (identity revision) remains the deliberate soul path (ADR-034), and any self-disclosure is logged (ADR-043).

## Options Considered
**Templated string reporting (read fields, fill a sentence template).** Simplest and fully deterministic; two founders could ship it in days. Rejected as the primary mechanism because it violates the substrate/no-LLM spirit obliquely — it is hard-coded language, not generated, so it cannot compose nuance ("focused but a little uncertain about the medication dosage goal") and drifts out of sync as the substrate evolves. We may keep a tiny templated fallback for boot-time before language atoms exist, but not as the real answer path.

**LLM-rendered introspection (dump state to the LLM bridge, ask it to phrase).** Most fluent output with least effort. Rejected outright: it violates ADR-014 — the LLM bridge is STT/TTS modality only (enhancement #14) and must never participate in generation or cognition. Self-description is cognition about the self; routing it through an LLM would be the exact failure the no-LLM-cognition capability test (ADR-049) checks for.

**Pure-substrate aggregator over authoritative sources, rendered through ADR-013 output (CHOSEN).** Truthful (reads live soul/goal/emotion/competence state), composable (concept activation yields graded, nuanced phrasing including confidence from ADR-023), and principle-compliant (no LLM). Costs more — it depends on the output substrate (ADR-013) and concept layer (ADR-018) being mature, and risks disfluency early. Accepted because it is the only option that makes self-awareness a genuine substrate capability rather than a façade.

## Consequences
- **Positive:** Genuine, truthful self-description satisfying the self-awareness capability test (ADR-049); a trust/calibration surface for the desktop user (ADR-046); confidence-aware answers via ADR-023; no new source of truth to keep in sync since it aggregates existing modules. Reuses the same output path as all other speech (ADR-013), so improvements there benefit introspection.
- **Negative:** Quality is bottlenecked by output-substrate fluency (ADR-013) and concept maturity (ADR-018); early answers may be terse or awkward. Aggregating across soul, goals, emotion, competence, and live loops creates coupling the API must isolate behind clean accessors. A self-disclosure API is a privacy/safety surface (must honor constitution, ADR-045) — e.g. it must not reveal another tenant's data in v2 (ADR-047).
- **Future work:** Self-explanation of *reasoning* (why did I conclude X) by reading signal traces (ADR-043); introspective triggers feeding self-learning (ADR-026) when the system notices a competence gap while describing itself; richer mood narratives as emotion (ADR-035) matures.

## Implementation Notes
New `agent/selfmodel.nova`: `selfmodel_answer(question_signal) -> output_signal`; dispatch on `SELFQ_*` subtypes carried in the `core/signal.nova` metadata map. Accessors used: `soul_get_identity`/`soul_get_values`/loyalty from `core/soul.nova`; state + valence/arousal from the soul state slot (ADR-035); `goal_active_set` and sub-goal tree walk from `core/goal.nova`; competence atoms via the ADR-020 self-model store; live loop list from `agent/agent.nova` (ADR-036). Render by activating concept atoms (`core/concept.nova`) and invoking the ADR-013 output pipeline — do NOT touch `runtime/llm.nova` except for optional TTS at the very end (enhancement #14 boundary). Attach Bayesian confidence (`core/belief.nova`, ADR-023) to competence answers. Gate disclosures through `core/safety.nova` (ADR-045) and log via the decision log (ADR-043). Testing: fixtures asserting each `SELFQ_*` reads the right source (mutate a goal, assert the activity answer changes; raise arousal, assert the state answer changes); a strict no-LLM test asserting the cognition path never calls the LLM bridge (capability test, ADR-049). Depends on ADR-013 (output), ADR-018 (concepts), ADR-020/033/034/035 (sources). No new enhancement number required; reuses #14's bridge isolation as a guardrail.

---

# ADR-039: Theory of mind in concept layer (user-as-concept with rich properties, updates from observation, used for empathy and anticipation)

Status: Proposed
Date: 2026-05-24

## Context
A companion that cannot model the person it serves is a tool, not a companion. CrossEngin's target capabilities explicitly include theory of mind: representing the user's knowledge, preferences, goals, emotional state, and habits, updating that model from observation, and using it for empathy (responding to how the user actually feels) and anticipation (acting before being asked). This is one of the 8 capability tests (ADR-049). On the desktop deployment (ADR-046) there is exactly one user to model deeply over months; in the enterprise pilot (ADR-047) the modeled party may be a specific employee, one per tenant process.

The question is *where* this model lives. CrossEngin already has a concept layer (`core/concept.nova`, ADR-018) with hierarchy, schemas, and multi-vector embeddings, and a multi-KG store (ADR-017) where atoms carry Bayesian confidence (ADR-016, ADR-023) and cross-KG references (enhancement #8). The user is not a separate subsystem — they are a *concept the system holds*, exactly the kind of rich, evolving, multi-faceted entity the concept layer was built for. Treating the user as a first-class concept (rather than a flat profile table) lets the model participate in normal substrate dynamics: spreading activation, prediction (ADR-024), emotion appraisal (ADR-035), and reasoning (ADR-031).

This must be decided now because empathy and anticipation touch emotion (ADR-035), goals (ADR-033), and the self-model API (ADR-038) being defined alongside it, and because privacy/safety (ADR-045) constraints on storing a model of a person must be designed in, not bolted on. Constraint: 2 founders, NOVA (ADR-005), no LLM (ADR-014) — the user model is learned from observed moments, not prompted out of a language model.

## Decision
We represent the user as a **first-class `user-as-concept` in `core/concept.nova`**, a rich concept node with multi-vector embeddings and a schema of property atoms, backed by a dedicated KG (e.g. `KG-user`) via the multi-KG mechanism (ADR-017, enhancement #8). It is not a flat profile; it is a concept that participates fully in substrate dynamics.

The concept carries property atoms (ADR-016), each Bayesian-confidence-weighted (ADR-023): stable traits (preferences, communication style, domain expertise, relationships), slow-changing context (current projects, recurring routines), and fast-changing state (inferred mood, energy, attention). Properties are **updated from observation**: every user-originated moment (ADR-021) is appraised and, where it carries evidence about the user, updates the relevant property's alpha/beta counts — co-occurrence strengthening via Hebbian synapses (ADR-007), and prediction mismatches (the user did something the model didn't expect) driving error-based revision (ADR-024). Cross-KG references (enhancement #8) link `user-as-concept` properties to domain atoms — e.g. the user's medication concept references `KG-medicine` atoms — so the model is grounded, not isolated.

The model is *used* two ways. **Empathy:** the user's inferred affective state feeds the emotion system's OCC appraisal (ADR-035), conditioning the system's own valence/arousal and shaping output tone (ADR-013) — a frustrated user yields gentler, briefer responses. **Anticipation:** the goal engine (ADR-033) reads predicted user needs from the model to spawn proactive sub-goals (e.g. surface a reminder before the user asks), generating initiative — itself a capability test (ADR-049). Predictions about the user are imagined forward (ADR-032) before action, and all proactive actions pass permission tiers (ADR-041) and reversibility (ADR-042).

## Options Considered
**Flat user-profile record (key/value store outside the substrate).** Simple, inspectable, easy to edit and to delete for privacy. Rejected as primary because a flat record cannot do spreading activation, cannot carry graded confidence naturally, cannot link to domain knowledge via cross-KG refs, and cannot participate in prediction/appraisal — it would sit outside the dynamics and require special-case orchestration, violating the substrate thesis (ADR-001). A flat *export view* of the concept is still useful for user inspection/deletion (ADR-044) and we keep that as a projection, not the store.

**Dedicated theory-of-mind module separate from the concept layer.** Clean separation of concerns; could be optimized independently. Rejected because it duplicates exactly what `core/concept.nova` (ADR-018) already provides (hierarchy, schemas, multi-vector embeddings) and would need its own update, decay, and reference machinery — wasteful for 2 founders and architecturally redundant. Theory of mind *is* concept modeling applied to a person.

**User-as-concept in the concept layer with a backing KG (CHOSEN).** Reuses the concept layer, multi-KG (ADR-017), Bayesian confidence (ADR-023), and predictive coding (ADR-024) wholesale; integrates natively with emotion (ADR-035) and goals (ADR-033) for empathy and anticipation; grounded via cross-KG refs (enhancement #8). Costs: a person modeled in mutable substrate raises real privacy obligations and the risk of confidently-wrong inferences. Accepted with explicit safety gating (ADR-045) and confidence-aware use.

## Consequences
- **Positive:** Theory-of-mind capability satisfied as an emergent substrate property, not a bolt-on (ADR-049); native empathy via emotion coupling (ADR-035) and initiative via goal coupling (ADR-033); grounded, confidence-weighted, continuously-updated user model that improves over months of companionship; cross-domain grounding through enhancement #8.
- **Negative:** Storing a rich evolving model of a real person is a significant privacy and safety surface — it must be user-inspectable and user-deletable (ADR-044) and constitution-gated (ADR-045), and in v2 must never leak across tenants (ADR-047). Confidently-wrong inferences can produce creepy or misjudged anticipation; we mitigate by gating proactive action on confidence thresholds (ADR-023) and permission tiers (ADR-041). Coupling into emotion and goals widens the blast radius of a bad user-model update.
- **Future work:** Multiple user concepts and modeling third parties the user talks about (relationship graph); explicit "I might be wrong about you" disclosure via the self-model API (ADR-038); decay tuning so stale mood inferences don't persist; consent/onboarding flow for what may be modeled.

## Implementation Notes
Create `user-as-concept` via `concept_new` in `core/concept.nova` with a property schema; back it with a `KG-user` spawned through the ADR-017 mechanism. Property atoms via `atom_new` carrying alpha/beta (`core/belief.nova`, ADR-023); cross-KG links via `core/similarity.nova` weighting (enhancement #8). Observation updates run in the memory + emotion loops (ADR-036): a `user_observe(moment)` routine appraises user-originated moments (ADR-021) and updates properties (Hebbian via ADR-007, error via ADR-024). Empathy hook: feed inferred user affect into `mind/emotion.nova` OCC appraisal (ADR-035). Anticipation hook: `goal_spawn_proactive(predicted_need)` in `core/goal.nova` (ADR-033), with forward simulation via `core/imagination.nova` (ADR-032) and a mandatory pass through `core/safety.nova` permission tiers (ADR-041) and reversibility (ADR-042). Provide a flat projection `usermodel_export()` for inspection/deletion (ADR-044). Testing: feed a scripted multi-day moment stream, assert a preference property's confidence rises and a wrong prediction triggers downward revision; assert a high-confidence predicted need spawns a proactive (but permission-gated) goal; a privacy test asserting export+delete clears the concept and its KG atoms; v2 tenant-isolation test (ADR-047). Depends on ADR-016/017/018/023/024 (representation), ADR-032/033/035 (use), ADR-041/044/045 (safety). Leans on enhancement #8 (multi-KG cross-refs). No LLM anywhere (ADR-014).

---

# ADR-040: Long-horizon goal persistence (multi-day/multi-week goals surviving process restarts, intermittent attention)

Status: Proposed
Date: 2026-05-24

## Context
A companion that forgets every goal when the app closes is not pursuing anything — it is reacting. CrossEngin must hold goals that span days or weeks ("help me taper this medication over three weeks", "learn enough about my research area to be useful by next month") and make progress on them across many short, interrupted interaction sessions, surviving process restarts, reboots, and long idle gaps. Long-horizon goal pursuit is one of the 8 capability tests (ADR-049), and it is the difference between initiative and mere responsiveness.

The goal engine (`core/goal.nova`, ADR-033) is being evolved with 4 drives, sub-goal trees, and cross-session continuity, and the persistence architecture (ADR-048) defines what state survives restart and in what rehydration order (soul → KGs → episodic, enhancement #10). What this ADR must decide is the *specific contract* for long-horizon goals: how a goal and its sub-goal tree are durably stored and rehydrated, how progress accrued across sessions is preserved, and how a goal earns attention intermittently without a continuously-running process — because the desktop app (ADR-046) is not always on, and even when running, the substrate throttles to idle (ADR-037).

This is needed now because it sits at the intersection of three things being defined concurrently: the goal engine (ADR-033), the persistence/snapshot model (ADR-048), and the concurrent goals loop (ADR-036). Constraints: 2 founders, NOVA (ADR-005), single desktop device for v1 (ADR-046), crash-safety is non-negotiable (a lost three-week goal is a serious trust failure).

## Decision
We make long-horizon goals **durable substrate state that survives restarts via the ADR-048 snapshot/rehydration path, with explicit progress accrual and an intermittent-attention scheduler hook.** Goals are not transient loop variables; a long-horizon goal is a persistent atom-backed structure in `core/goal.nova` carrying its sub-goal tree (ADR-033), accrued progress, last-attended timestamp, a deadline/horizon, and a salience that the scheduler uses to decide when to revisit it.

Durability rides ADR-048: long-horizon goals are part of the snapshot, and because goals belong to the soul wrapper (ADR-034, goals = "medium" timescale), they rehydrate in the soul-first phase of the ordered rehydration (enhancement #10) — *before* KGs and episodic — so that on restart the system reconstitutes "what I am pursuing" before reconstructing what it knows. Between snapshots, goal-state mutations (progress increments, sub-goal completion, status changes) are written to the append-only crash-safe log (enhancement #9, ADR-043) so a crash loses at most the work since the last logged mutation, not the whole goal. **Progress accrual:** each session, the goals loop (ADR-036) advances active goals, and increments/sub-goal completions are persisted immediately to the log and folded into the next snapshot — progress is cumulative across sessions, never reset by restart.

**Intermittent attention** is handled by the hybrid scheduler (ADR-037): long-horizon goals do not need a live thread between sessions. On startup and at idle windows, a `goal_revisit_scan` runs over rehydrated goals, computing a revisit salience from horizon proximity, time-since-last-attended, and drive pressure (ADR-033). High-salience goals re-enter the active set, can spawn proactive sub-goals (often informed by the user model, ADR-039), and may use idle imagination cycles (ADR-032, enhancement #13) to plan next steps. Stale or expired goals decay or surface to the user for confirmation rather than silently dying.

## Options Considered
**In-memory goals only, lost on restart (status quo of a naive loop).** Trivial; zero persistence work. Rejected immediately — it makes multi-day goals impossible and fails the long-horizon capability test (ADR-049). A companion that forgets its commitments on every reboot is untrustworthy.

**Snapshot-only persistence (serialize goals at shutdown, restore at startup).** Simple, leans entirely on ADR-048; no per-mutation logging. Rejected as insufficient on its own because a crash or power loss between snapshots loses all intervening progress — exactly when a long-running goal has accrued the most uncommitted work. Snapshots are necessary but must be paired with the append-only mutation log (enhancement #9) for crash safety. We adopt snapshot *plus* log, not snapshot alone.

**Always-on background daemon driving goals continuously between sessions.** Maximum continuity — goals never go cold. Rejected for v1: a single-user desktop app (ADR-046) should not run a heavyweight always-on process burning resources to babysit a three-week goal that needs attention a few times a day; it conflicts with the idle-throttling scheduler (ADR-037) and battery constraints. The revisit-scan-at-idle approach achieves intermittent attention far more cheaply, and the daemon model is revisited only for the always-on enterprise context (ADR-047).

**Snapshot + append-only log + idle revisit-scan (CHOSEN).** Crash-safe (log bounds loss to the last mutation), restart-durable (snapshot + soul-first rehydration), and resource-frugal (no live thread between sessions; attention via idle scan). Costs more machinery than snapshot-only and introduces a revisit-salience tuning surface, but is the only option that is simultaneously durable, crash-safe, and frugal. Accepted.

## Consequences
- **Positive:** Genuine multi-day/multi-week goal pursuit surviving restarts and idle gaps, satisfying the long-horizon capability test (ADR-049); crash-safety with bounded loss via the audit log (ADR-043); resource-frugal intermittent attention fit for a desktop companion (ADR-046); cumulative cross-session progress that makes the system feel committed and reliable; natural synergy with proactive anticipation (ADR-039) and idle planning (ADR-032).
- **Negative:** Adds persistence complexity to the goals loop (every mutation must be logged, enhancement #9) and couples goals tightly to the snapshot/rehydration order (ADR-048). Revisit-salience tuning can misfire — pestering the user about a low-priority goal or letting an important one go cold. Long-lived persisted goals are state that can become stale or wrong and must be user-vetoable (ADR-044).
- **Future work:** Goal-state migration when the snapshot format evolves (ADR-048); negotiation with the user when goals conflict or a deadline slips; always-on goal driving for the enterprise pilot (ADR-047); learned revisit-salience instead of hand-tuned weights.

## Implementation Notes
Extend `core/goal.nova`: long-horizon goal atoms via `atom_new` (ADR-016) with fields `{tree, progress, horizon, last_attended, salience, status}`; constructor `goal_longhorizon_new` and mutators `goal_advance(g, delta)`, `goal_subgoal_complete(g, sub)` that BOTH update memory and append to the crash-safe log. Persistence integrates with ADR-048: include goals in the snapshot and place them in the soul-first rehydration phase (`core/soul.nova`, ADR-034) per enhancement #10; use enhancement #9's append-only fsync log (shared with ADR-043) for inter-snapshot mutations. Intermittent attention: `goal_revisit_scan()` invoked by the scheduler (ADR-037) on startup and at idle hooks (enhancement #13), computing salience from horizon proximity + staleness + drive pressure (ADR-033); high-salience goals re-enter the goals loop active set (ADR-036) and may spawn proactive sub-goals (informed by ADR-039) and plan via imagination (ADR-032). Expose veto/inspection through override (ADR-044). Testing: kill -9 the process mid-goal and assert on restart the goal and its accrued progress rehydrate with at most the last unlogged mutation lost; a multi-session fixture asserting progress accumulates across three simulated restarts; an idle-revisit test asserting a goal nearing its horizon re-enters the active set without a live thread; a staleness test asserting an expired goal surfaces to the user rather than vanishing. `DEPENDS ON: NOVA enhancement #9 — append-only crash-safe (fsync) decision/audit log` and `#10 — substrate snapshot + ordered rehydration (soul -> KGs -> episodic)`; also #13 (idle hooks). Tightly coupled to ADR-033 (goal engine) and ADR-048 (persistence).


---

# ADR-041: Permission tiers (auto / notify / approve based on action class)

Status: Proposed
Date: 2026-05-24

## Context
CrossEngin acts in the world. The action loop (ADR-036) drives `NTYPE_ACTOR` nodes that emit `SIG_COMMAND` and `SIG_ORDER` signals down to motor effectors and external bridges: filesystem writes, whitelisted outbound HTTP fetches (ADR-028), calendar/email integrations, and shell-like tool calls. An autonomous substrate with initiative and long-horizon goals (ADR-033, ADR-040) will originate actions the user never explicitly requested. Some are harmless (re-reading a cached page); some are consequential (sending a message, deleting a file). We cannot treat them identically, and we cannot ask the user to confirm everything — that destroys the companion experience.

This decision must be made now because the action loop is being built and `core/safety.nova` must wrap every effector call before any external integration ships in v1. The constraint is a 2-founder team that cannot maintain a hand-curated approval rule for thousands of action instances, and cannot afford a learned/probabilistic gate whose mistakes are unauditable. We need a small, deterministic, inspectable policy that defaults safe and degrades gracefully.

For v1 (single-user desktop, ADR-046) the user IS the authority. For v2 (enterprise pilot, ADR-047) the same tiering must hold but the authority resolves through the soul loyalty hierarchy (ADR-045). The mechanism must therefore be policy-data-driven, not hardcoded per deployment.

## Decision
We adopt three permission tiers — `PERM_AUTO`, `PERM_NOTIFY`, `PERM_APPROVE` — assigned per **action class**, not per action instance. Every outward action is tagged with an `action_class` symbol (e.g. `ACT_READ_LOCAL`, `ACT_WRITE_LOCAL`, `ACT_NET_FETCH`, `ACT_SEND_MSG`, `ACT_DELETE`, `ACT_SPEND`, `ACT_SELF_MODIFY`). A single classification table in `core/safety.nova` maps `action_class -> tier`. The gate function `safety_gate(action)` looks up the tier and: `PERM_AUTO` executes immediately; `PERM_NOTIFY` executes immediately but emits a `SIG_REFLECTION` to the user-facing notification channel and writes a decision-log entry (ADR-043); `PERM_APPROVE` suspends the action, surfaces an approval request, and blocks the originating action sub-goal until the user responds (approve/deny/always-allow).

The tier for a class is computed, not arbitrary: it is the MAX (most restrictive) of (a) the static class default and (b) the reversibility floor from the reversibility classifier (ADR-042). Irreversible classes are forced to at least `PERM_APPROVE` regardless of their static default. This makes the reversibility classifier the dominant safety input and keeps the table itself small (~20 classes for v1). An optional per-class **rate/scope refinement** (e.g. `ACT_NET_FETCH` is `PERM_AUTO` under the whitelist+rate-limit of ADR-028, else `PERM_APPROVE`) is expressed as a guard predicate attached to the class row, evaluated at gate time.

## Options Considered
1. **Per-action-instance learned permission gate (rejected).** Treat permission as another learned routing decision (like ADR-009 gates), training on user approve/deny feedback. Powerful and adaptive, but its decisions are non-deterministic and hard to audit; a single mis-generalization could auto-execute an irreversible action. For a safety boundary we require deterministic, inspectable behavior. Rejected for v1; revisitable as a *suggestion* layer that proposes table edits, never as the gate itself.

2. **Binary allow/deny with a global confirmation toggle (rejected).** Simplest to build. But it forces a false choice: either nag on everything or trust everything. It cannot express "do it but tell me," which is the most useful default for a companion. Rejected as too coarse.

3. **Capability tokens per integration (considered, partially adopted).** Grant the agent explicit capability tokens (filesystem-write, network, send) that the user mints. Strong isolation, but tokens gate *whether* an integration exists, not *when* a given use needs oversight — orthogonal to tiers. We keep capability scoping at the integration boundary (which effectors are wired at all) and layer the three tiers on top for runtime oversight.

4. **Three-tier class table with reversibility floor (CHOSEN).** Deterministic, tiny, inspectable, and policy-data-driven so v1 and v2 share code. Captures the auto/notify/approve spectrum the companion UX needs and binds the hardest cases to ADR-042. Chosen.

## Consequences
- **Positive:** Deterministic, auditable safety boundary on every action; the common case (`PERM_NOTIFY`) preserves autonomy without silence; irreversible actions can never silently auto-execute because of the reversibility floor; one table serves desktop and enterprise.
- **Negative:** New action types must be classified before they ship, or they fall through to the default (we make the default `PERM_APPROVE` — fail safe), which can feel over-cautious until the table is tuned. Guard predicates add a little per-action cost on the action loop's hot path.
- **Future work:** A learned suggestion layer that proposes table refinements from approve/deny history (ADR-023 belief tracking over per-class outcomes); enterprise admin-locked rows for v2 (ADR-047); a UI for users to inspect and edit their tier table, tied to the override mechanism (ADR-044).

## Implementation Notes
Add to `core/safety.nova`: tier constants `PERM_AUTO | PERM_NOTIFY | PERM_APPROVE`; `perm_table` as a `runtime/map.nova` keyed by `action_class` to a row `[default_tier, guard_fn, reversibility_ref]`; `safety_gate(action) -> decision` that computes `max_tier(default, reversibility_floor(action))` then dispatches. Actions are NOVA tag-prefixed values carrying `action_class` in their metadata, mirroring the `core/signal.nova` metadata-map idiom. `PERM_APPROVE` suspension uses the action loop's coroutine yield (`runtime/coroutine.nova`); the blocked sub-goal parks in `core/goal.nova` until resolved. Notifications and approval prompts are emitted as `SIG_REFLECTION` / `SIG_REQUEST` (ADR-008) so output renders through pure-substrate generation (ADR-013) — NO LLM. Every gate decision writes to the decision log (ADR-043). The reversibility floor is the lookup defined in ADR-042. Tests: a fixture table covering all ~20 classes; assert irreversible classes always resolve `>= PERM_APPROVE`; assert unknown class defaults to `PERM_APPROVE`; assert guard-predicate downgrade only ever *raises* the tier. No new NOVA enhancement strictly required; logging path uses NOVA enhancement #9.

---

# ADR-042: Reversibility classifier (per-action-type lookup, default irreversible)

Status: Proposed
Date: 2026-05-24

## Context
The permission tiers of ADR-041 are only as safe as their ability to recognize which actions cannot be undone. Sending an email, spending money, deleting a file without a trash bin, posting publicly, and overwriting the soul's identity are all irreversible; reading a file, drafting (not sending), and caching a fetched page are reversible. The cost of mis-classifying a reversible action as irreversible is mild annoyance (an unnecessary approval prompt). The cost of mis-classifying an irreversible action as reversible is catastrophic and permanent. These costs are wildly asymmetric, so the classifier must be biased hard toward caution.

This must be decided alongside ADR-041 because the tier table consumes the reversibility verdict as its dominant input (the "reversibility floor"). A 2-founder team cannot enumerate every possible action with a nuanced undo analysis, and an autonomous system with initiative will invent action sequences we did not foresee. We therefore need a lookup that is exhaustive by *default*, not by enumeration.

## Decision
We implement a reversibility classifier in `core/safety.nova` as a per-action-type lookup table, `reversibility_class(action_type) -> {REV_REVERSIBLE, REV_RECOVERABLE, REV_IRREVERSIBLE}`, whose **default for any unlisted type is `REV_IRREVERSIBLE`** (fail-safe). `REV_REVERSIBLE` means a clean programmatic undo exists (e.g. local edit with an in-memory/journaled prior state). `REV_RECOVERABLE` means undo is possible but lossy or delayed (e.g. delete-to-trash, retractable-within-N-seconds send). `REV_IRREVERSIBLE` means no undo (external send, spend, public post, hard delete, identity revision).

The classifier feeds ADR-041 via a fixed floor map: `REV_IRREVERSIBLE -> PERM_APPROVE` (minimum), `REV_RECOVERABLE -> PERM_NOTIFY` (minimum), `REV_REVERSIBLE -> PERM_AUTO` (no floor). ADR-041 then takes the MAX of this floor and the action class's static default. Reversibility is a property of the *effector*, so classification lives next to where effectors are registered: each effector declares its reversibility class at wire-up time, and unregistered/dynamically-composed effectors inherit the irreversible default. Optionally, an effector may register an `undo_fn`; the presence of a working `undo_fn` is what *earns* a `REV_REVERSIBLE`/`REV_RECOVERABLE` classification — you cannot claim reversible without providing the undo path.

## Options Considered
1. **Default reversible / opt-in irreversible (rejected).** Lower friction; matches optimistic-execution UX. But it inverts the safety asymmetry: any forgotten or novel action type is presumed safe, and the one mistake that matters is the one that's unrecoverable. Categorically rejected — violates fail-safe design.

2. **Per-instance reversibility prediction (considered, rejected for the gate).** Predict reversibility from action arguments (e.g. "delete temp file" vs "delete contract.pdf"). More precise, but turns a safety primitive into an inference problem with false negatives that are unbounded in cost. We keep prediction out of the safety gate; it may inform *notifications* but never *lowers* a class below its table value.

3. **Three-bucket table with irreversible default and earned-via-undo_fn downgrade (CHOSEN).** Captures the real spectrum (reversible / recoverable / irreversible) rather than a brittle binary, ties the "reversible" claim to an actual `undo_fn`, and is exhaustive by default. Small enough for two people to maintain. Chosen.

4. **No classifier; fold reversibility into the ADR-041 class defaults (rejected).** Fewer moving parts, but conflates "how consequential is this kind of action" with "can it be undone," which are different axes (a notify-tier action can still be irreversible). Separating them keeps both tables small and lets reversibility act as an independent floor. Rejected.

## Consequences
- **Positive:** A novel or unforeseen action can never bypass approval, because the default is irreversible; the `undo_fn` requirement makes "reversible" an enforceable contract, not a label; three buckets give ADR-041 enough resolution to avoid over-prompting on genuinely safe actions.
- **Negative:** Until the table is populated, many actions prompt for approval (deliberate early-stage friction). Maintaining accurate `undo_fn`s is real engineering work and a place bugs hide — a broken undo silently degrades a "reversible" action into an actual irreversible one. We mitigate with undo round-trip tests.
- **Future work:** Periodic audit that every `REV_REVERSIBLE`/`REV_RECOVERABLE` row still has a passing undo test; enterprise (ADR-047) may pin stricter classifications (e.g. force all `ACT_SEND_MSG` irreversible regardless of retract windows).

## Implementation Notes
In `core/safety.nova`: constants `REV_REVERSIBLE | REV_RECOVERABLE | REV_IRREVERSIBLE`; `rev_table` (`runtime/map.nova`) keyed by `action_type` to `[rev_class, undo_fn_ref]`; `reversibility_class(action_type)` returning the table value or `REV_IRREVERSIBLE` on miss; `reversibility_floor(action)` returning the `PERM_*` minimum consumed by `safety_gate` (ADR-041). Effector registration API gains a `reversibility` field and optional `undo_fn`; registering `REV_REVERSIBLE` without an `undo_fn` is a wire-up error. Undo state for `REV_RECOVERABLE` actions (e.g. trash, retract queue) persists so it survives restart (ADR-048, snapshot order soul -> KGs -> episodic). Tests: assert unlisted action_type -> `REV_IRREVERSIBLE`; assert each reversible/recoverable row's `undo_fn` round-trips (do then undo restores prior state); assert the floor map matches ADR-041's expectations. No dedicated NOVA enhancement needed; recoverable-undo persistence rides on enhancement #10.

---

# ADR-043: Decision log (append-only, full trace per action, user-inspectable)

Status: Proposed
Date: 2026-05-24

## Context
A substrate where intelligence emerges from dynamics (ADR-001) is intrinsically hard to debug and hard to trust: there is no orchestration script to read. For a system that acts autonomously, we need an authoritative, durable record of *what it did and why* — both to honor the safety contract (ADR-041, ADR-042) and to give the user (and, in v2, an enterprise auditor per ADR-047) a way to inspect, challenge, and override decisions (ADR-044). Episodic memory (ADR-022) is lossy by design (it decays and consolidates); it cannot serve as the audit record. We need a separate, non-decaying, append-only log.

The forces: a desktop app can crash or lose power mid-action, so the log must be crash-safe (an action that executed must have a durable log entry, and the log must never be silently truncated). The trace must be rich enough to reconstruct the causal chain that produced an action without re-running the substrate, yet cheap enough to write on the action loop's hot path. And it must be inspectable in plain language through pure-substrate output (ADR-013) — NO LLM in the explanation path.

This is the concrete consumer of NOVA enhancement #9 (append-only, fsync-backed decision/audit log) and ties directly to the internet-fetch audit requirement of ADR-028.

## Decision
We add an append-only, crash-safe decision log to `core/safety.nova`, persisted via `runtime/db.nova` with fsync on commit (NOVA enhancement #9). Every action that passes through `safety_gate` (ADR-041) — auto, notify, or approve — writes one immutable entry BEFORE the effector runs, and a completion/undo record after. Each entry carries a **full per-action trace** reusing the `trace` field already defined in the `core/signal.nova` layout `[TAG, type, moment, origin, destination, priority, trace, metadata]`. The trace is the visited-node list accumulated as the signal propagated, so a log entry records the actual substrate path that culminated in the action.

A log entry is a tag-prefixed record: `[LOG_ENTRY, seq, timestamp, action_class, action_type, perm_tier, rev_class, originating_goal, signal_trace, soul_state_snapshot_ref, outcome]`. `seq` is a monotonic counter; entries are content-hash-chained (each entry stores the hash of the prior entry) so any tampering or truncation is detectable. `originating_goal` links to the `core/goal.nova` node that drove the action (supporting "why did you do this?"). `soul_state_snapshot_ref` points at the relevant soul state/values at decision time (ADR-034) so the user can see the emotional/value context. Entries are never updated or deleted; corrections are themselves appended `SIG_CORRECTION`-tagged entries.

## Options Considered
1. **Reuse episodic memory as the audit trail (rejected).** Zero new machinery. But episodic memory decays, consolidates, and is mutable (ADR-022, ADR-025) — exactly the wrong properties for an audit log. An auditor needs a record that cannot quietly change. Rejected.

2. **Structured DB table with updatable rows (rejected).** Convenient querying. But mutable rows undermine trust and complicate crash-safety guarantees; an append-only file with fsync is simpler to make durable and tamper-evident. Rejected in favor of append-only with a derived/queryable index.

3. **Log only NOTIFY/APPROVE actions, skip AUTO (considered, rejected).** Cheaper hot path. But AUTO actions are precisely the ones the user never sees in real time, so omitting them creates a blind spot for after-the-fact inspection. We log all three tiers; we make AUTO entries lighter (smaller snapshot reference) to control cost. Rejected as written.

4. **Full-trace, hash-chained, fsync append-only log for all gated actions (CHOSEN).** Durable, tamper-evident, complete, and reuses the existing signal `trace` so the cost is mostly already paid. Chosen.

## Consequences
- **Positive:** Every autonomous action is durably explainable and tamper-evident; the user can ask "why did you do X?" and get a real causal trace, not a post-hoc rationalization; satisfies ADR-028's audit requirement and underpins ADR-044 overrides and v2 enterprise audit (ADR-047).
- **Negative:** fsync-on-commit adds latency to the action path (mitigated by batching AUTO entries and only hard-syncing before irreversible actions); the log grows unbounded (mitigated by rotation/compaction of *old* segments while preserving the hash chain across rotations); storing soul-state references couples the log format to ADR-034.
- **Future work:** A queryable index over the append-only log for fast "show me all sends last week"; signed log export for enterprise compliance (ADR-047); replay-for-explanation that re-walks a stored trace to render a natural-language account via pure substrate output (ADR-013, ADR-038).

## Implementation Notes
`core/safety.nova` gains `decision_log_open`, `decision_log_append(entry)`, `decision_log_iter`, and `decision_log_verify` (re-checks the hash chain). Storage uses `runtime/db.nova` segment files with fsync; entries serialized via `runtime/json.nova` or a compact binary record. The `signal_trace` field is taken directly from the gating signal's `trace` per `core/signal.nova`. Hash chaining uses `runtime/crypto.nova`. Write ordering: append intent entry + fsync (for `REV_IRREVERSIBLE`, ADR-042) -> run effector -> append outcome entry. Inspection surfaces through the self-model query API (ADR-038) rendering log entries as language via pure substrate (ADR-013) — explicitly NOT through `runtime/llm.nova`. Snapshot/rehydration (ADR-048) treats the log as durable-but-separate (it is not rolled back by a substrate snapshot restore). DEPENDS ON: NOVA enhancement #9 — append-only, crash-safe (fsync) decision/audit log atop `runtime/db.nova` + `core/safety.nova`. Tests: kill-process-mid-action and assert no executed action lacks an entry; assert hash-chain verification fails on a mutated entry; assert AUTO actions still log.

---

# ADR-044: Override mechanism (belief edit, goal veto, hard stop, kill switch)

Status: Proposed
Date: 2026-05-24

## Context
An autonomous, continuously-learning substrate will sometimes be wrong: it will hold a mistaken belief, pursue a goal the user disapproves of, get stuck in a runaway loop, or simply need to be stopped now. The user must retain final authority at every level — this is both a trust requirement for the v1 companion (ADR-046) and a hard requirement for the v2 enterprise pilot (ADR-047). The decision log (ADR-043) tells the user *what* happened and *why*; the override mechanism is how they *intervene*. Without graded intervention, the only recourse is to kill the process, which is destructive and discards learned state.

This must be decided now because each override hooks a different core module — `core/belief.nova`, `core/goal.nova`, the action loop, and the runtime — and those interfaces should be designed before the loops are wired (ADR-036). The 2-founder constraint means overrides must be a thin, well-defined set, not an open-ended admin console.

## Decision
We define four override mechanisms, graded from surgical to total, all surfaced to the user through the same inspection surface as the decision log (ADR-043) and self-model API (ADR-038):

1. **Belief edit** — the user corrects a specific atom's confidence. Implemented as a privileged write to the Bayesian belief on that atom in `core/belief.nova` (alpha/beta counts): the override sets or pins alpha/beta (e.g. force a near-certain or near-zero belief), emitted as a `SIG_CORRECTION` so downstream nodes update. Edits are logged (ADR-043) and may be marked "pinned" so ordinary plasticity (ADR-023) cannot drift them back.
2. **Goal veto** — the user cancels or forbids a goal/sub-goal in `core/goal.nova`. Vetoing marks the goal node `GOAL_VETOED`, prunes its sub-goal tree, and parks any actions blocked on it (ADR-041 `PERM_APPROVE` queue). A veto can be one-shot or standing (a standing veto becomes a constraint the goal engine will not regenerate).
3. **Hard stop** — immediately halt all in-flight and queued *actions* (the action loop) while leaving the substrate alive (perception/memory/reasoning keep running). This is the "stop what you're doing" control: it flips a `safety_halt` flag that `safety_gate` checks, draining `NTYPE_ACTOR` outboxes without executing them.
4. **Kill switch** — terminate the process. A clean kill triggers an ordered snapshot (soul -> KGs -> episodic, ADR-048) so state survives; a panic kill (double-trigger) skips the snapshot for true immediacy. The kill switch is always available and never gated.

These are mediated by `core/safety.nova`, which exposes them as explicit operations and (except panic-kill) records each as an appended decision-log entry.

## Options Considered
1. **Kill switch only (rejected).** Trivial and unmistakably safe, but maximally destructive — every correction means losing the session and all unsaved learning. It also gives no way to fix a *specific* wrong belief without nuking everything. Insufficient alone; retained as the last of four.

2. **Single generic "undo last action" control (considered, rejected as the whole mechanism).** Intuitive and pairs naturally with ADR-042's `undo_fn`s. But many problems aren't a single action — they're a wrong *belief* or a misguided *goal* that will keep generating bad actions. Undo treats symptoms, not causes. We keep per-action undo (via ADR-042) but it is not the override mechanism. Rejected as sole solution.

3. **Full read/write admin console over substrate state (rejected for v1).** Maximum control. But exposing arbitrary writes to nodes/synapses/atoms is dangerous, unauditable, and far beyond 2-founder capacity to build safely; arbitrary edits could corrupt the substrate. Rejected; the four targeted overrides cover the real needs.

4. **Four graded overrides — belief edit / goal veto / hard stop / kill switch (CHOSEN).** Each targets a distinct causal level (belief, intention, in-flight action, existence), all auditable, all small and well-scoped. Matches how things actually go wrong. Chosen.

## Consequences
- **Positive:** The user can intervene at the right granularity instead of only at the extremes; belief edits and goal vetoes fix root causes durably; hard stop gives instant safety without data loss; kill switch is an always-available backstop. All overrides are logged, preserving the audit chain (ADR-043).
- **Negative:** Privileged writes into `core/belief.nova` and `core/goal.nova` bypass normal learning, so a careless user could pin wrong beliefs or over-veto and degrade the system; we mitigate by logging and by letting pins be un-pinned. Hard stop's "substrate alive but actions frozen" state is a new mode that all action-originating code must respect.
- **Future work:** Standing vetoes feed the constitutional layer (ADR-045) as soft constraints; enterprise (ADR-047) restricts who may belief-edit vs goal-veto via the loyalty hierarchy; an "explain then offer override" flow built on ADR-038.

## Implementation Notes
`core/safety.nova` exposes `override_belief_edit(atom_ref, alpha, beta, pin?)`, `override_goal_veto(goal_ref, standing?)`, `override_hard_stop()`, `override_kill(panic?)`. Belief edit calls a privileged setter in `core/belief.nova` and emits `SIG_CORRECTION` (ADR-008); pinning sets a flag the plasticity path (ADR-023) honors. Goal veto sets `GOAL_VETOED` on the `core/goal.nova` node and prunes children. Hard stop sets a `safety_halt` flag checked at the top of `safety_gate` (ADR-041); `NTYPE_ACTOR` `node_drain_outbox` discards instead of dispatching while halted. Kill uses `runtime/syscall.nova`; clean kill invokes the ordered snapshot of ADR-048 (enhancement #10). All overrides except panic-kill append to the decision log (ADR-043, enhancement #9). Controls surface via the self-model/inspection UI (ADR-038) with pure-substrate rendering (ADR-013) — no LLM. Tests: assert a pinned belief survives subsequent plasticity ticks; assert a standing veto prevents goal regeneration; assert hard stop drains without executing any effector; assert clean kill produces a rehydratable snapshot and panic kill exits immediately.

---

# ADR-045: Constitutional rules (hard inhibitory signals, enterprise vs user loyalty resolution)

Status: Proposed
Date: 2026-05-24

## Context
The permission tiers (ADR-041), reversibility classifier (ADR-042), and overrides (ADR-044) govern *individual actions and corrections*. But some prohibitions must be absolute and substrate-wide: rules the system will not violate no matter what goal, belief, or learned habit pushes toward them (e.g. never exfiltrate the user's private data, never self-modify the constitution without deliberate revision, never take an irreversible action that harms the user). These are constitutional. They cannot be mere high-tier permissions, because a permission is something the user could approve away in the moment; a constitutional rule must be able to *inhibit* an action even against a local approval, and must be expressed in the substrate's own currency so it participates in dynamics rather than sitting outside as a bolt-on checker.

This is decided now because the soul already carries a constitution and a loyalty hierarchy (`core/soul.nova`, ADR-034), and the signal taxonomy (ADR-008) already defines `inhibitory` and `constitutional` signal types — the pieces exist and must be connected before autonomous action ships. The v2 enterprise pilot (ADR-047) sharpens the hardest question: when the deploying enterprise and the end user want different things, who wins, and where is that non-negotiable?

## Decision
Constitutional rules are implemented as **hard inhibitory signals**, using the `constitutional` and `inhibitory` signal types from the 18-type taxonomy (ADR-008), extending `core/signal.nova`'s tag space (enhancement #6). A constitutional rule is a standing watcher in `core/soul.nova` that, when a candidate action or goal matches its prohibition pattern, emits a maximal-priority `constitutional`/`inhibitory` signal targeting the originating `NTYPE_ACTOR`/goal nodes. Unlike ordinary `inhibitory` signals (which lower activation probabilistically), a `constitutional` signal is **hard**: it sets a veto bit on the action that `safety_gate` (ADR-041) treats as terminal — the action cannot execute, and no in-the-moment user approval can clear it (only deliberate constitutional revision can, per ADR-034). Constitutional signals carry top `priority` in the `core/signal.nova` layout so they preempt excitatory/goal-drive signals at every gate (ADR-009).

For **enterprise-vs-user loyalty resolution**, we bind to the soul's existing loyalty hierarchy (`core/soul.nova`, ADR-034). The hierarchy is ordered, and the constitutional layer sits ABOVE both enterprise and user: (1) constitution (non-negotiable, e.g. legal/safety/no-harm), (2) the deploying authority's policy (enterprise in v2), (3) the end user, (4) the system's own goals. Conflicts resolve top-down: a constitutional rule overrides everything; below it, enterprise policy overrides a conflicting user request in v2; in v1 there is no enterprise layer, so the user is the top non-constitutional authority. Critically, neither enterprise nor user can override a constitutional rule via permission or override — constitutional rules are reachable only through deliberate revision, which is itself a constitutional-gated, fully-logged operation.

## Options Considered
1. **Post-hoc policy checker outside the substrate (rejected).** A classic allow/deny filter wrapping effectors. Simple and familiar, but it sits outside substrate dynamics: it cannot *shape* goal formation or activation, only block at the very end, and it duplicates the gating ADR-041 already does. Expressing constitution as signals lets prohibitions damp bad goals *before* they reach action. Rejected as the primary mechanism (we still keep the gate veto bit as the enforcement point).

2. **Constitution as very-high-tier permissions (rejected).** Fold constitution into ADR-041 as a `PERM_APPROVE`-always class. But permissions are user-clearable in the moment; constitution by definition must not be. Conflating them lets a single approval defeat a hard rule. Rejected.

3. **Soft inhibitory-only constitution (rejected).** Use only the probabilistic `inhibitory` signal type, strongly weighted. Elegant and fully substrate-native, but "strongly discouraged" is not "forbidden" — under enough goal pressure a soft inhibition can be overcome, which is unacceptable for hard rules. Rejected; we use the *hard* `constitutional` type for absolutes and reserve soft `inhibitory` for preferences (e.g. standing vetoes from ADR-044).

4. **Hard `constitutional` inhibitory signals + soul loyalty hierarchy (CHOSEN).** Substrate-native (participates in dynamics, can damp goals early), yet terminal at the gate (cannot be approved away), with conflict resolution grounded in the soul structure that already exists. Chosen.

## Consequences
- **Positive:** Absolute prohibitions are both substrate-native and unbypassable; constitutional pressure shapes goals before they become actions, not just blocks at the end; the loyalty hierarchy gives a single, inspectable answer to enterprise-vs-user conflicts; v1 and v2 share the mechanism with only the hierarchy contents differing.
- **Negative:** Authoring correct prohibition-match patterns is hard and high-stakes (a too-broad rule paralyzes the system, a too-narrow one leaks); maximal-priority signals must be implemented carefully so they truly preempt at every gate (ADR-009). The "deliberate revision only" path for changing constitution adds process friction by design.
- **Future work:** A constitutional revision workflow (constitutional-gated, logged via ADR-043) for v1; enterprise admin provisioning of layer-2 policy and lockout of layer-3 overrides for v2 (ADR-047); pattern-authoring tooling and a constitutional test suite among the 8 capability tests (ADR-049).

## Implementation Notes
Extend `core/signal.nova` with the `constitutional` and `inhibitory` tags (ADR-008, enhancement #6 — extended signal tag space with typed fast-dispatch). In `core/soul.nova`: a `constitution` set of rules each `[CONST_RULE, match_pattern, severity]`; `constitution_watch(candidate_action_or_goal)` emits a top-`priority` `constitutional` signal on match. `safety_gate` (ADR-041) checks for a constitutional veto bit before any tier logic and treats it as terminal (no approval clears it). The loyalty hierarchy is read from `core/soul.nova` (ADR-034); add `loyalty_resolve(conflict) -> authority` returning the highest-ranked stakeholder, with constitution pinned above all. Gates (ADR-009) must honor signal `priority` so constitutional signals preempt. Every constitutional inhibition and every revision attempt appends to the decision log (ADR-043, enhancement #9). Enforcement is pure substrate — no `runtime/llm.nova` involvement. Tests: assert a constitutionally-vetoed action cannot be executed even with explicit user approval; assert `loyalty_resolve` returns enterprise over user in a v2 fixture and user (top non-constitutional) in a v1 fixture; assert constitution outranks both in all fixtures; assert a soft `inhibitory` preference can be overridden by sufficient goal drive while a hard `constitutional` cannot.


---

# ADR-046: Deployment v1 (personal desktop, single user, single device, federation-ready)

Status: Proposed
Date: 2026-05-24

## Context
CrossEngin must ship something real before it can ship something big. Two founders working 8h/day each on a bootstrap budget cannot validate a cognitive substrate against a multi-tenant cloud target; the first deployable artifact has to run on hardware the founders already own and a user can install without operations staff. We therefore commit v1 to a single-user, single-device personal desktop companion app. This frames every earlier ADR's resource assumptions: it is the concrete machine the scaling math of ADR-003 (1M nodes/part, ~1000 synapses/node) must fit on, and the concrete process the persistence model of ADR-048 must snapshot and rehydrate.

The decision must be made now because it sets the memory and concurrency budget the substrate is built against. The substrate is one OS process holding all parts (perception, KG-medicine and other domain KGs, episodic, soul, reasoning, imagination, action, meta), each part being 1M pre-allocated nodes (NOVA enhancement #1). It runs the six concurrent loops (ADR-036) plus the idle imagination loop on the host's cores, driven by the 100Hz substrate tick fused with event-driven coordination (ADR-037). There is no network dependency for cognition; the only outbound traffic is the whitelisted, rate-limited fetch path of ADR-028, and the only optional bridge is STT/TTS modality conversion (ADR-014, NOVA enhancement #14) — never cognition.

"Federation-ready" is a forward constraint, not a v1 feature. We must avoid baking in single-instance assumptions (global mutable singletons, hardcoded local paths, implicit "the one user") that would block a future where several desktop instances sync select atoms or where the same brain image seeds the enterprise tenant of ADR-047. So v1 is local-only at runtime but structured so federation can be added without re-architecture.

## Decision
Ship v1 as a single native NOVA-compiled desktop application targeting one user on one device (x86-64 via `compiler/lower_x64.nova` and arm64 via `compiler/lower_arm64.nova`), running the entire substrate as one process. Target hardware baseline: a 16-core / 32GB consumer desktop or laptop; minimum 8-core / 16GB with reduced active-part headroom. Memory budget is derived from ADR-003: at ~1000 synapses/node and ~1M active nodes per part, synapse adjacency (NOVA enhancement #2, CSR-like) dominates; we cap the v1 working set so the resident substrate plus episodic buffers stay under ~12-16GB, leaving room for the OS, the embedding/tensor working sets (`runtime/tensor.nova`, `runtime/simd.nova`), and snapshot scratch. Not all 9 parts hold a full 1M live nodes at install; domain KGs grow via synapse growth and atom birth (ADR-025) as the user interacts, so initial residency is far smaller and expands toward the cap.

All durable state is owned by the persistence layer of ADR-048: the soul (`core/soul.nova`), every domain KG (`core/knowledge.nova`), episodic memory (`mind/memory.nova`), and the append-only decision log (ADR-043, NOVA enhancement #9). On launch, the app rehydrates in the ADR-048 order (soul -> KGs -> episodic, enhancement #10) so identity and constitution are live before any knowledge or memory is loaded.

Federation-readiness is enforced structurally: (1) a stable instance identity stored in the soul's identity block; (2) every atom carries provenance (origin instance + Bayesian alpha/beta from `core/belief.nova`) so atoms could later be merged across instances by source-authority rules (ADR-029) without identity collisions; (3) no code path assumes a singleton — the substrate is addressed through a `system_new` handle (`core/system.nova`), never a global. We ship zero networking-for-sync in v1; we ship the data shapes that make it additive later.

## Options Considered
- **Cloud-hosted multi-user web app first (rejected).** Fastest path to a shareable URL, but it forces multi-tenancy, auth, and ops work before the substrate is even proven, and it contradicts the constraint that cognition has no network dependency. A 2-founder team would burn its 18-30mo budget on infrastructure rather than intelligence. Multi-tenant isolation is exactly the hard problem we deliberately defer to v2 (ADR-047, one tenant per process).
- **Single-device desktop companion, single user (CHOSEN).** Matches the hardware founders own, validates the substrate end-to-end against a real person over real days (the multi-day companion-quality test of ADR-049), and keeps the entire system inspectable in one process. The cost is that it proves nothing about scale-out, which we accept because correctness-of-cognition must come before scale.
- **Local multi-user on one device (rejected for v1).** Several user profiles sharing one substrate process would immediately raise theory-of-mind (ADR-039) and loyalty-resolution (ADR-045) questions about "whose values" the soul holds. One soul, one user keeps the loyalty hierarchy unambiguous in v1 and lets us study a single rich user-concept before generalizing.
- **Embedded/edge (phone/IoT) first (rejected).** The ADR-003 memory budget and the 100Hz tick across millions of synapses (enhancement #4) do not fit a phone in v1; revisiting after node-pool and SIMD maturity is future work.

## Consequences
- **Positive:** A real, installable companion that exercises the whole stack — substrate, reader (ADR-011/012), pure-substrate output (ADR-013), six loops, soul, safety, persistence — on commodity hardware with no cloud bill. One process means one debugger, one log, one snapshot; ideal for a small team. Single user makes the soul's loyalty hierarchy and the user-as-concept model unambiguous.
- **Negative:** No validation of horizontal scale, concurrency-across-machines, or tenant isolation; those risks are pushed entirely to v2. The full 1M-node-per-part target stresses consumer RAM, so v1 ships with a conservative residency cap and relies on growth rather than full pre-fill. Performance is bounded by the user's machine; a weak host degrades tick rate and loop concurrency.
- **Future work:** Federation (cross-instance atom sync under ADR-029 authority weighting), and the base-brain extraction that seeds enterprise tenants in ADR-047. Edge/embedded targets after node-pool (#1) and SIMD (#4) mature.

## Implementation Notes
Package as a single native binary via `pkg/pkg.nova`, compiled through `compiler/codegen.nova` -> `compiler/lower_x64.nova` / `compiler/lower_arm64.nova`. Substrate composed in `core/system.nova` with a `system_new` root handle owning all parts; never a global singleton. Node arenas pre-allocated through `runtime/persistent_alloc.nova` + `runtime/alloc.nova` (DEPENDS ON: NOVA enhancement #1). Synapse adjacency via the sparse CSR-like structure (DEPENDS ON: NOVA enhancement #2). Loops run on `runtime/coroutine.nova`/`runtime/taskpool.nova` with `runtime/chan.nova` channels (DEPENDS ON: NOVA enhancement #3); tick via `runtime/scheduler.nova` (DEPENDS ON: NOVA enhancement #5). Durable state and snapshot/rehydration per ADR-048 (DEPENDS ON: NOVA enhancement #10) over `runtime/db.nova`. Optional STT/TTS only through `runtime/llm.nova` + `runtime/llm_bridge.c`, hardened to carry no cognition path (DEPENDS ON: NOVA enhancement #14). Provide an instance-identity field in the soul and a provenance stamp on `atom_new` (origin instance + alpha/beta) to keep federation additive. Testing: run the ADR-049 multi-day companion test on both a 16GB minimum host and a 32GB baseline host; assert resident-set stays under the cap and tick rate holds near 100Hz under the six-loop load. Dependencies: ADR-003 (budget), ADR-036/037 (concurrency/tick), ADR-048 (persistence), ADR-028 (fetch), ADR-014 (no-LLM), ADR-047 (v2 successor).

---

# ADR-047: Deployment v2 (enterprise pilot, one tenant per process, base brain + tenant-specific learning)

Status: Proposed
Date: 2026-05-24

## Context
Once v1 (ADR-046) proves the substrate produces companion-quality cognition for one person on one device, the first revenue-relevant deployment is an enterprise pilot: a single paying organization running CrossEngin against a real domain (the canonical example is KG-medicine). This decision must be made now because it changes the unit of deployment from "one user" to "one tenant," and that distinction propagates back into how the soul's loyalty hierarchy (ADR-034, ADR-045) and the persistence boundaries (ADR-048) are designed. We want v2 to be additive over v1, not a rewrite.

The hard constraint is isolation. A 2-founder bootstrap team cannot afford a subtle cross-tenant knowledge leak — one client's proprietary atoms surfacing in another client's answers would be fatal commercially and ethically. We therefore adopt the simplest defensible isolation model: ONE TENANT PER PROCESS. Each tenant gets its own substrate process with its own node arenas (enhancement #1), its own domain KGs (`core/knowledge.nova`), its own episodic memory (`mind/memory.nova`), its own soul instance, and its own snapshot file (ADR-048). No shared mutable substrate state crosses the process boundary. This is the same single-process substrate v1 already runs, instantiated once per tenant, which is exactly why building v1 first de-risks v2.

The other constraint is that we must not re-teach the world to every tenant. The substrate that ships should already "know how to think" — language atoms (ADR-015), the reader (ADR-011/012), reasoning operators (ADR-031), general concepts (ADR-018), and a baseline general-knowledge KG. We call this the **base brain**: a frozen snapshot extracted from a matured v1/internal instance. On top of it, each tenant accumulates **tenant-specific learning**: domain atoms, beliefs (alpha/beta), procedural skills (ADR-019), and a user/organization theory-of-mind model (ADR-039) earned during the pilot.

## Decision
Deploy v2 as N isolated single-tenant processes, each launched from a shared, read-only **base-brain snapshot** plus a private, writable **tenant overlay**. At provision time, the tenant process rehydrates the base-brain snapshot in ADR-048 order (soul -> KGs -> episodic; here episodic is empty at provision) and then layers the tenant's own snapshot on top. From that point the process is autonomous: all new atoms, belief updates, episodic moments, and skills are written only to the tenant overlay snapshot. The base brain is never written back from a tenant; improvements to the base brain are a separate, curated release process, not an online merge.

The constitutional layer is non-negotiable in v2. Constitutional rules are hard inhibitory signals (ADR-045, the constitutional signal type of ADR-008) seeded into every tenant's soul and protected from tenant-side revision: a tenant may extend soul values and add organization policy, but cannot weaken or remove the constitution. Where an enterprise directive conflicts with a hard constitutional rule or with user-protective rules, ADR-045's loyalty resolution governs and the constitution wins — the enterprise gets a flagged refusal, recorded in the append-only decision log (ADR-043), not silent compliance.

Multi-tenancy at the host level is process orchestration, not substrate sharing: a thin supervisor places one substrate process per tenant on available cores/RAM, sized by the ADR-003 budget, and routes I/O. Tenants never share an address space, so there is no in-substrate path for one tenant's atoms to reach another.

## Options Considered
- **One tenant per process, base brain + tenant overlay (CHOSEN).** Strongest isolation with the least new code, because it reuses the v1 single-process substrate verbatim and adds only a supervisor and a base/overlay snapshot split. Cost is per-tenant RAM (each process pre-allocates its own arenas, enhancement #1) and weaker host density. We accept the cost: for a pilot with a handful of tenants, correctness and provable isolation beat density.
- **Multi-tenant single process with per-tenant KG namespacing (rejected).** Cheaper on RAM and could lean on multi-KG namespacing (enhancement #8), but it puts every tenant's atoms in one address space and one substrate, where a routing bug in the gates (ADR-009) or a stray cross-KG reference (ADR-017) could leak data. For a bootstrap team, the blast radius is unacceptable and the audit story is far harder.
- **Per-tenant cloud VM/container, no shared base (rejected).** Total isolation, but every tenant would learn language and general reasoning from scratch — wasteful and slow to demonstrate value, and it discards the matured v1 brain we worked 18-30 months to grow.
- **Fine-tuned shared model with tenant adapters (rejected, category error).** This is the LLM mental model; CrossEngin has no model to fine-tune and forbids LLM cognition (ADR-014). The substrate analogue is the base-brain-plus-overlay split we chose.

## Consequences
- **Positive:** Provable data isolation (no shared mutable state across tenants), a fast time-to-value because each tenant starts from a brain that already reasons and speaks, a hard constitutional floor that survives enterprise pressure (ADR-045), and near-total code reuse from v1 — the substrate is identical, only orchestration and the snapshot split are new.
- **Negative:** Per-tenant memory cost is high because each process pre-allocates its own node arenas (enhancement #1); host density is low, limiting how many tenants fit on one box. Base-brain improvements cannot flow to live tenants online; they require a curated re-release and re-rehydration. A supervisor and snapshot-split tooling are net-new work.
- **Future work:** Federation/cross-instance learning (the structural hooks from ADR-046) could later let curated, authority-weighted (ADR-029) atoms flow from tenants back into a future base brain. Higher tenant density would require the rejected namespacing model (enhancement #8) only after isolation is proven another way.

## Implementation Notes
Reuse the v1 binary (ADR-046) unchanged as the per-tenant process. Add a host supervisor (NOVA service over `runtime/syscall.nova`/`runtime/io.nova`) that, per tenant, forks a substrate process, points it at a read-only base-brain snapshot and a writable tenant-overlay path, and applies the ADR-003 RAM/core budget. Snapshot/rehydration via ADR-048 (DEPENDS ON: NOVA enhancement #10): rehydrate base (soul -> KGs -> empty episodic) then overlay (tenant KGs -> tenant episodic). Constitution seeded into `core/soul.nova` and enforced as hard inhibitory constitutional signals (ADR-008, ADR-045) via `core/safety.nova`; mark constitutional atoms non-revisable by tenant-side belief edits (contrast ADR-044's user override, which does not extend to weakening the constitution in enterprise mode). All cross-tenant separation is by OS process boundary — assert in tests that no `core/knowledge.nova` handle or `atom_new` reference can resolve across processes. Audit every constitutional refusal to the append-only log (ADR-043, enhancement #9). Testing: provision two tenants from the same base brain, teach tenant A a private fact, and verify (ADR-049 isolation case) that tenant B cannot retrieve or be influenced by it. Dependencies: ADR-046 (v1 substrate reused), ADR-048 (base/overlay snapshots), ADR-045 (constitution/loyalty), ADR-003 (per-process budget), ADR-029 (future authority-weighted merge).

---

# ADR-048: Persistence (which state survives restart, snapshot format, rehydration order — soul first, then KGs, then episodic)

Status: Proposed
Date: 2026-05-24

## Context
A companion that forgets who it is and what it was doing every time the host reboots is not a companion. CrossEngin must persist enough state that, across an ordinary desktop restart (ADR-046) or a tenant process recycle (ADR-047), the system wakes up as the same self, with the same knowledge, mid-pursuit of its long-horizon goals (ADR-040). This decision must be made now because nearly every other subsystem produces durable state — the soul (`core/soul.nova`), every domain KG (`core/knowledge.nova`), episodic memory (`mind/memory.nova`), goals (`core/goal.nova`), beliefs (`core/belief.nova`), and the decision log (ADR-043) — and they need one coherent contract for what is saved and in what order it comes back.

Not everything should survive. Ephemeral signals (the 18 types of ADR-008) are by definition transient — in-flight signals are dropped on shutdown, not serialized. Transient activation levels, the current contents of node inboxes/outboxes, and the moment-to-moment loop scratch are recomputable and not persisted. What MUST survive is the learned, accumulated substrate: synapse topology and weights (ADR-007), atoms and their Bayesian alpha/beta confidence (ADR-016, ADR-023), the soul's identity/values/constitution/loyalty (ADR-034), goal trees including long-horizon goals (ADR-040), procedural skills (ADR-019), the self-model competence record (ADR-020), and the append-only audit log (ADR-043).

The team constraint shapes the format: 2 founders cannot maintain a bespoke database engine, so persistence builds on `runtime/db.nova` and `runtime/persistent_alloc.nova` with crash safety via fsync. And because the substrate is huge (millions of nodes, ~1000 synapses each), the snapshot must be compact and the restore must be ordered so the system is coherent at each step rather than only at the end.

## Decision
Persist a **substrate snapshot** consisting of: (1) the soul block — identity, OCEAN, constitution, identity themes, loyalty hierarchy, current state, and goal trees; (2) all domain KGs — atoms with their alpha/beta counts and cross-KG reference edges (ADR-017) with similarity weights; (3) episodic memory — moments and their consolidation/decay metadata (ADR-022); (4) the synapse adjacency and weight arrays (ADR-007) and the self-model/skills records. Ephemeral signal traffic and node inbox/outbox/activation scratch are NOT persisted; they are reconstructed by running the loops after rehydration. The append-only decision log (ADR-043, enhancement #9) is persisted continuously and independently of snapshots so audit survives even a crash between snapshots.

Snapshots are written with a tagged, versioned binary layout matching NOVA's tag-prefixed value style: a header (`SNAP` tag, format version, instance identity, timestamp, section offset table), then length-prefixed sections [SOUL][KGS][EPISODIC][SYNAPSES][SELFMODEL]. Writes are crash-safe: serialize to a temp file, fsync, atomically rename over the live snapshot, so a crash mid-write never corrupts the last-good image (this is NOVA enhancement #10). We take periodic checkpoints (e.g., during idle, alongside imagination/replay — enhancement #13) and on clean shutdown.

Rehydration order is mandatory and is the load-bearing part of this ADR (NOVA enhancement #10): **soul first, then KGs, then episodic.** Soul loads first so identity, constitution, and loyalty are live before any knowledge or memory enters — the constitution (ADR-045) must be in force before a single atom is admitted. KGs load second so the knowledge graph and its cross-references exist before episodic memories that point into atoms are restored. Episodic loads last because moments reference atoms (and indirectly the soul's goals) and would dangle if loaded first. Synapse arrays and self-model load with/after KGs since their weights index node and atom structures. Long-horizon goals (ADR-040) ride inside the soul block, so on wake the system immediately knows what it was pursuing.

## Options Considered
- **Full ordered substrate snapshot with soul -> KGs -> episodic rehydration (CHOSEN).** Gives a single coherent self on restart with no dangling references, and the order guarantees the constitution is enforced before any knowledge loads. Cost is snapshot size and write time for the synapse arrays; mitigated by idle-time checkpointing and atomic rename. Chosen because correctness of identity-on-wake is non-negotiable for a companion.
- **Event-sourcing / replay log only, rebuild substrate from scratch (rejected).** Elegant and gives perfect history, but replaying months of moments and learning to reconstruct millions of synapse weights at every boot is far too slow for a desktop launch, and it makes the boot path depend on the entire history being intact. We keep an append-only log for audit (ADR-043) but do not rebuild cognition from it.
- **Persist only soul + KGs, recompute episodic (rejected).** Smaller and faster, but episodic memory (ADR-022) is not recomputable — lost moments mean lost personal history and broken continuity of the relationship, which defeats the companion goal. Episodic must be durable.
- **Live mmap'd persistent arena, no discrete snapshots (considered, deferred).** `runtime/persistent_alloc.nova` could memory-map the substrate so state is implicitly durable. Tempting, but it complicates crash-consistency (a torn write corrupts live cognition), versioning/migration, and the base/overlay split v2 needs (ADR-047). We keep discrete, versioned, atomically-renamed snapshots for v1/v2 and revisit mmap as future work.

## Consequences
- **Positive:** The system wakes as the same self with the same knowledge and mid-goal (ADR-040); the ordered restore guarantees no dangling atom/moment references and a constitution that is live before any knowledge loads. Atomic-rename + fsync makes the last-good snapshot crash-safe. The discrete snapshot format directly enables the v2 base-brain/overlay split (ADR-047).
- **Negative:** Snapshot size is dominated by synapse weight arrays and grows with the substrate; checkpoint writes cost I/O and must be scheduled off the critical path (idle, enhancement #13). A schema version field is mandatory and migrations between format versions are ongoing maintenance. State between the last checkpoint and a crash (other than the append-only log) is lost.
- **Future work:** Incremental/delta snapshots to shrink write cost; possible mmap'd persistent arena; cross-instance snapshot merge for federation (ADR-046) under source-authority rules (ADR-029).

## Implementation Notes
Build on `runtime/db.nova` + `runtime/persistent_alloc.nova` with fsync-then-atomic-rename (DEPENDS ON: NOVA enhancement #10). Define a `snapshot_write(system, path)` and `snapshot_rehydrate(path) -> system` over `core/system.nova`; serialize each subsystem via its own `*_serialize`/`*_deserialize` (e.g., `soul_serialize` over `core/soul.nova`, KG serialization over `core/knowledge.nova` preserving alpha/beta from `core/belief.nova` and cross-refs from `core/similarity.nova`, episodic over `mind/memory.nova`). Header carries a `SNAP` tag constant, `format_version`, instance identity, timestamp, and a section offset table; sections are length-prefixed in fixed order [SOUL][KGS][EPISODIC][SYNAPSES][SELFMODEL]. Enforce rehydration order in code: refuse to load KGs before the soul block is live, refuse episodic before KGs (assert on section order). Drop in-flight signals (ADR-008) and clear node inbox/outbox on load; let the six loops (ADR-036) repopulate activation. Schedule checkpoints from the idle hook (DEPENDS ON: NOVA enhancement #13) and on clean shutdown. The decision log (ADR-043) persists independently and continuously (DEPENDS ON: NOVA enhancement #9). Testing: kill -9 the process mid-checkpoint and assert the prior snapshot still rehydrates; verify a moment whose referenced atom was decayed/GC'd (ADR-025) rehydrates without dangling; verify long-horizon goals (ADR-040) survive a restart and resume. Dependencies: ADR-034 (soul), ADR-040 (long-horizon goals), ADR-022 (episodic), ADR-016/023 (atoms/beliefs), ADR-043 (audit), and consumed directly by ADR-046 and ADR-047.

---

# ADR-049: Testing and benchmarks (multi-day companion-quality test, domain-specific QA, the 8 capability tests)

Status: Proposed
Date: 2026-05-24

## Context
CrossEngin makes an extraordinary claim — AGI-relevant capability with no LLM in the cognition path — so it needs a test regime strong enough to back the claim and cheap enough for 2 founders to run repeatedly. Unit correctness is necessary but nowhere near sufficient: a substrate can pass every primitive test and still fail to be a coherent companion, or quietly drift into using the STT/TTS bridge (ADR-014) as a crutch. This decision must be made now because the test harness shapes how every subsystem exposes observability, and because the milestone plan (ADR-050) gates each phase on tests passing.

For grounding: the underlying NOVA language/runtime is currently at 129/135 tests passing. That suite covers NOVA primitives (`core/node.nova`, `core/signal.nova`, `core/channel.nova`, `core/knowledge.nova`, etc.) and runtime modules; it is the floor CrossEngin builds on, and closing those remaining 6 is part of the enhancement work (#1-#14). CrossEngin's own test pyramid sits above it: NOVA primitive tests (inherited) -> CrossEngin substrate tests (nodes/synapses/signals/gates/atoms) -> subsystem tests (reader, KGs, memory, soul, safety) -> integration/capability tests -> the multi-day companion-quality test.

Three test layers are distinctive to this project and are the subject of this ADR: (1) a **multi-day companion-quality test** that runs a real or scripted user against a persistent instance across several days and process restarts; (2) **domain-specific QA** that validates learned knowledge in a target domain (e.g., KG-medicine) against curated questions with known answers; and (3) the **8 capability tests** that each target one of the AGI-relevant capabilities the project exists to demonstrate.

## Decision
Adopt a four-tier test regime. **Tier 1 — primitives:** keep the inherited NOVA suite green (drive 129/135 to 135/135 as enhancements land) and add CrossEngin substrate-primitive tests for `synapse_new`/weight update (Hebbian + error-driven, ADR-007), `gate_new` routing (ADR-009), `atom_new` birth/death (ADR-025), and the 18 signal tags (ADR-008). **Tier 2 — subsystems:** reader five-stage fixtures (ADR-012), multi-KG spawn and cross-ref (ADR-017), episodic decay/consolidation/replay (ADR-022), soul revision rules (ADR-034), and safety tiers/overrides (ADR-041/044). **Tier 3 — domain QA:** a fixture set of question/expected-answer pairs in the pilot domain, scored for accuracy, calibration (does reported confidence from alpha/beta match correctness, ADR-023/030), and proper "I don't know -> ask to learn" behavior (ADR-027). **Tier 4 — the multi-day companion-quality test and the 8 capability tests.**

The **8 capability tests**, each with explicit pass criteria, are: (1) **continuous learning** — teach a new fact mid-session; verify it is recalled and integrated days later across a restart (ADR-026, ADR-048). (2) **self-directed skill acquisition** — present a gap; verify the system acquires a procedural skill (ADR-019) without being explicitly programmed. (3) **theory of mind** — verify the user-as-concept model (ADR-039) holds correct beliefs/preferences and anticipates needs. (4) **initiative** — verify unprompted, goal-driven action surfaced through the goal engine (ADR-033) under the right permission tier (ADR-041). (5) **counterfactual reasoning** — pose "what if X had been different"; verify the imagination subsystem (ADR-032) produces a coherent counterfactual. (6) **long-horizon goals** — set a multi-day goal; verify persistence and resumption across restarts (ADR-040, ADR-048). (7) **self-awareness of identity/state/goals** — query the self-model API (ADR-038); verify accurate, in-language description of who it is, how it feels, and what it is pursuing. (8) **NO-LLM-COGNITION verification** — the gating test: with the STT/TTS bridge (`runtime/llm.nova`, ADR-014) stubbed to error if invoked for anything but modality conversion, the full suite must still pass; any cognition that touches the bridge fails the build.

The **multi-day companion-quality test** runs a persistent instance over a scripted multi-day timeline with deliberate restarts, measuring continuity (does it remember prior days), relationship coherence (does the user-concept and soul state evolve sensibly), and the absence of contradiction or identity drift. It is the headline acceptance test for desktop v1 (ADR-046).

## Options Considered
- **Four-tier regime: primitives -> subsystems -> domain QA -> capability + multi-day (CHOSEN).** Catches regressions cheaply at the bottom and validates the actual thesis at the top, and the no-LLM test makes the central principle continuously enforceable. Cost is that Tier 4 is slow and partly manual; we accept it by scripting the multi-day timeline so it can run unattended overnight.
- **Unit tests only, manual demos for capability (rejected).** Cheapest, but it leaves the AGI claims and the no-LLM principle unverified between demos — exactly the things most likely to regress silently. Unacceptable for the project's core claim.
- **Benchmark against an LLM baseline on QA accuracy (rejected as a primary metric).** Tempting for marketing, but it frames CrossEngin as a worse/cheaper LLM and ignores what is unique (continuous learning, self-awareness, initiative, no-LLM cognition). We keep domain QA for calibration, not as a leaderboard chase against models we deliberately don't use.
- **Property-based/fuzzing the substrate as the main strategy (considered, partial).** Valuable for synapse-weight bounds (ADR-007) and gate routing, and we fold it into Tier 1, but fuzzing cannot express "is this a good companion," so it can't be the whole regime.

## Consequences
- **Positive:** The no-LLM-cognition test turns the project's defining principle (ADR-014) into a build gate that cannot silently erode. The multi-day test validates persistence (ADR-048) and long-horizon goals (ADR-040) under realistic restarts. The 8 capability tests give the founders an unambiguous, demonstrable definition of "done" for v1.
- **Negative:** Tier 4 is slow, partly stochastic (substrate dynamics aren't bit-deterministic), and needs tolerance bands rather than exact-match assertions; flaky-test management is real work. Scripting a realistic multi-day user timeline is itself a small project. Calibration scoring requires curated ground-truth that must be maintained.
- **Future work:** Expand domain QA per new vertical for v2 tenants (ADR-047); add cross-instance/federation consistency tests (ADR-046); adversarial tests for constitutional rules (ADR-045) and override paths (ADR-044).

## Implementation Notes
Place suites under a `tests/` tree mirroring modules: `tests/core/`, `tests/mind/`, `tests/agent/`, plus `tests/capability/` (one file per capability test) and `tests/companion/` (the multi-day scripted timeline). Reuse NOVA's existing test runner that reports the current 129/135; add CrossEngin tests to the same runner so one command reports the full count. The no-LLM test injects a poisoned `runtime/llm.nova` stub that aborts on any non-STT/TTS call (DEPENDS ON: NOVA enhancement #14 for the bridge-isolation boundary to assert against). The multi-day test drives perception through `core/moment.nova`, forces `snapshot_write`/`snapshot_rehydrate` cycles (ADR-048) between days, and asserts continuity by querying the self-model API (ADR-038) and checking episodic recall (ADR-022). Capability tests assert on observable substrate state (atom alpha/beta from `core/belief.nova`, goal-tree state from `core/goal.nova`, user-concept properties from `core/concept.nova`) rather than only on output text, so they don't depend on phrasing. Use tolerance bands for stochastic outcomes; seed RNG where possible for repeatability. Gate each ADR-050 milestone on the relevant tier passing. Dependencies: nearly all ADRs feed fixtures, but especially ADR-014 (no-LLM gate), ADR-038 (self-model queries), ADR-039 (theory of mind), ADR-040/048 (persistence + long-horizon), ADR-032 (counterfactual), ADR-019/026 (skill acquisition).

---

# ADR-050: Build sequence and milestones (12-step ordered plan from substrate kernel through enterprise pilot)

Status: Proposed
Date: 2026-05-24

## Context
This is the capstone ADR: it sequences everything the other 49 decided into an ordered, buildable plan for 2 founders working 8h/day each on a bootstrap budget over an 18-30 month v1 horizon (plus a v2 enterprise pilot). Without an explicit order the team would thrash — for example, building cognition before the substrate kernel exists, or chasing capability tests before persistence works. The plan must be genuinely actionable: each step has entry conditions, the concrete NOVA modules/ADRs it implements, an exit gate tied to the test regime (ADR-049), and a rough share of the timeline. It must also respect that the foundation already exists — NOVA provides the 6 base node types, soul, KG, beliefs, goals, safety, imagination, concepts, the 6-loop agent, and is at 129/135 tests passing — so CrossEngin is extending a real codebase, not starting from zero.

The ordering principle is bottom-up dependency: nothing is built before the thing it stands on. Substrate primitives precede the reader; the reader precedes KGs being usefully populated; memory precedes learning loops (you cannot consolidate what you cannot store); cognition precedes the soul governing it; safety wraps cognition before any deployment; persistence is in place before the multi-day test; and the enterprise pilot is last because it is the v1 substrate re-deployed per tenant. Capacity is the hard limit: ~16 founder-hours/day means roughly 2-3 of these steps can be genuinely in flight at once, so the plan front-loads the load-bearing enhancements (#1, #2, #3, #5, #12).

## Decision
Execute the following 12 ordered milestones. Each lists its core ADRs, key NOVA enhancements, the exit gate (ADR-049 tier), and an approximate timeline slice of the 18-30 month v1 (v2 sits beyond month 30).

**Step 1 — Substrate kernel (months 0-3).** Land the node arenas and sparse synapse fabric and the concurrency/tick spine: NOVA enhancements #1 (pre-allocated 1M-node arenas), #2 (sparse CSR-like adjacency), #3 (true concurrent loops), #5 (100Hz tick). Implements ADR-001/003/036/037 foundations atop `runtime/persistent_alloc.nova`, `runtime/coroutine.nova`, `runtime/scheduler.nova`. Exit gate: Tier-1 primitive tests for arena allocation, synapse growth/prune, and a stable 100Hz tick under load.

**Step 2 — Core primitives (months 2-5).** Implement the seven CrossEngin primitives on the kernel: node behavior (ADR-006), synapse plasticity Hebbian + error-driven (ADR-007, enhancement #12), the 18 signal types (ADR-008, enhancement #6), gates (ADR-009, enhancement #7), atoms (ADR-016), moments (ADR-021), first nodes (ADR-010). New constructors `synapse_new`, `gate_new`, `atom_new` over `core/*`. Exit gate: Tier-1 substrate-primitive suite green, including signal-tag fast-dispatch and gate routing.

**Step 3 — Reader (months 4-8).** Build the five-stage hybrid reader (ADR-011/012): lexical anchor, context bias, spreading activation, coherence check, fetch/route/learn — explicitly not a parser, not an LLM (ADR-014). Language atoms (ADR-015) seeded. Exit gate: Tier-2 reader fixtures pass on held-out inputs with correct route/learn decisions.

**Step 4 — Knowledge graphs (months 6-10).** Multi-KG with spawn-on-new-domain and similarity-weighted cross-references (ADR-004/017, enhancement #8) over `core/knowledge.nova` + `core/similarity.nova`; atom birth/death (ADR-025); Bayesian confidence (ADR-023, `core/belief.nova`); concept layer (ADR-018). Exit gate: Tier-2 KG spawn/cross-ref tests + first Tier-3 domain-QA pass on a seed domain.

**Step 5 — Memory (months 8-12).** Episodic memory storage, decay, consolidation, and idle replay (ADR-022, enhancement #13) over `mind/memory.nova`; moment lifecycle into episodic (ADR-021). Exit gate: Tier-2 episodic tests (decay/consolidation/replay) green.

**Step 6 — Learning loops (months 10-15).** Self-directed learning: triggers (ADR-026), ask-user-to-teach (ADR-027), whitelisted internet fetch (ADR-028, enhancement #11), source-authority weighting (ADR-029), "learned enough" thresholds (ADR-030). Predictive coding between layers (ADR-024). Exit gate: capability tests #1 (continuous learning) and #2 (self-directed skill acquisition, with skills KG ADR-019) pass.

**Step 7 — Cognition (months 13-18).** Reasoning hybrid (ADR-031, `mind/reasoning.nova`), imagination evolution (ADR-032, `core/imagination.nova`), goal engine evolution with sub-goal trees (ADR-033), emotion/OCC appraisal (ADR-035). Exit gate: capability test #5 (counterfactual) passes; reasoning QA stable.

**Step 8 — Soul (months 16-20).** Soul as wrapper governing cognition (ADR-034): identity slow, state fast, goals medium, values/constitution/themes/loyalty; theory of mind (ADR-039); self-model competence (ADR-020) and self-model query API (ADR-038); long-horizon goal persistence (ADR-040). Exit gate: capability tests #3 (theory of mind), #4 (initiative), #7 (self-awareness) pass.

**Step 9 — Safety (months 18-22).** Permission tiers (ADR-041), reversibility classifier (ADR-042), append-only decision log (ADR-043, enhancement #9), override + kill switch (ADR-044), constitutional hard inhibitory rules (ADR-045) over `core/safety.nova`. Safety wraps cognition before any ship. Exit gate: Tier-2 safety tests + adversarial constitution/override tests green.

**Step 10 — Persistence + Desktop v1 (months 20-26).** Snapshot + ordered rehydration soul -> KGs -> episodic (ADR-048, enhancement #10); package the single-process desktop companion (ADR-046) for x86-64/arm64. Exit gate: the **multi-day companion-quality test** (ADR-049) passes across real restarts, and capability test #6 (long-horizon goals) and #8 (NO-LLM-COGNITION verification) pass. This is the v1 acceptance milestone.

**Step 11 — Hardening (months 24-30).** Performance (SIMD/GPU batched propagation, enhancement #4, `runtime/simd.nova`/`runtime/gpu.nova`), memory-budget tuning to the ADR-003 cap, crash-safety soak, snapshot size/incremental work, flaky-capability-test stabilization (ADR-049 tolerance bands). Exit gate: full suite green to 135/135 NOVA + all CrossEngin tiers; resident set within budget on a 16GB host.

**Step 12 — Enterprise pilot v2 (month 30+).** Extract the matured base-brain snapshot; build the one-tenant-per-process supervisor and base/overlay snapshot split (ADR-047); enforce the non-negotiable constitution per tenant (ADR-045). Exit gate: two-tenant isolation test (ADR-049) proves no cross-tenant leakage; one paying pilot tenant live in a real domain.

## Options Considered
- **Strict bottom-up dependency ordering, 12 milestones (CHOSEN).** Each step stands on a tested floor, so debugging is local and the team is never blocked on an unbuilt dependency. Cost is that visible "intelligence" arrives late (Step 6-8); we accept it because building cognition on an unproven substrate would be far more expensive to unwind.
- **Capability-first / vertical-slice ordering (rejected).** Build one end-to-end capability (e.g., continuous learning) through all layers, then the next. Demos sooner, but it forces repeated half-builds of the substrate, reader, and persistence, and a 2-founder team cannot afford to re-touch the kernel that many times. High rework risk.
- **Parallel workstreams across both founders on independent tracks (rejected as primary).** With only ~16 hours/day total, deep parallelism fragments attention and creates integration debt between, say, the reader and KGs before either is stable. We allow limited overlap (steps share boundary months) but keep a single critical path.
- **Buy/borrow an LLM to bootstrap cognition and replace it later (rejected, principle violation).** Would speed early demos but directly violates ADR-014 and would contaminate the substrate's learned state with model-shaped dependencies that the no-LLM test (ADR-049 #8) is designed to forbid.

## Consequences
- **Positive:** A single, ordered critical path that fits 2 founders / 8h-day capacity, with every milestone gated on concrete ADR-049 tests so "done" is unambiguous. Front-loading enhancements #1/#2/#3/#5/#12 de-risks the hardest substrate work first. v1 (Step 10) and v2 (Step 12) map cleanly onto ADR-046 and ADR-047.
- **Negative:** Demonstrable intelligence is back-loaded to ~month 13+; early steps produce infrastructure with little outward magic, which is a morale/funding risk for a bootstrap team. The 18-30mo range is wide because substrate performance (enhancement #4) and capability-test stochasticity are genuine unknowns. Boundary-month overlaps require disciplined integration to avoid the very rework the ordering exists to prevent.
- **Future work:** Federation (ADR-046 hooks), additional v2 verticals (ADR-047), incremental snapshots (ADR-048), and pushing node pools toward the 1B target (ADR-003) all sit beyond Step 12.

## Implementation Notes
Track milestones as gated phases in the repo (one tracking issue per step, exit gate = the named ADR-049 tier). Land NOVA enhancements upstream in dependency order: #1, #2, #3, #5 (Step 1) -> #6, #7, #12 (Step 2) -> #8 (Step 4) -> #13 (Step 5) -> #11, #9 (Step 6/9) -> #10 (Step 10) -> #4 (Step 11) -> #14 hardened and asserted continuously from Step 3 onward (DEPENDS ON: NOVA enhancements #1-#14 across the listed steps). Keep the NOVA test runner authoritative: the 129/135 baseline must trend to 135/135 by Step 11, and CrossEngin tiers (ADR-049) attach to the same runner so one command reports overall health. Do not advance a step until its exit gate is green; allow only the explicit boundary-month overlaps shown above. Each step's primary modules: Step 1 `runtime/*` (alloc/scheduler/coroutine/chan); Step 2 `core/node|signal|channel`; Step 3 reader + `core/concept`; Step 4 `core/knowledge|similarity|belief`; Step 5 `mind/memory`; Step 6 `agent/*` + fetch over `runtime/io|syscall`; Step 7 `mind/reasoning` + `core/imagination|goal`; Step 8 `core/soul` + self-model; Step 9 `core/safety`; Step 10 snapshot over `runtime/db|persistent_alloc` + `pkg/pkg`; Step 11 `runtime/simd|gpu|tensor|blas`; Step 12 supervisor + base/overlay split. Dependencies: this ADR sequences all others; it consumes ADR-046, ADR-047, ADR-048, and ADR-049 directly as its final gates.

