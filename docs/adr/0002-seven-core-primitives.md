# ADR-0002: Seven core primitives (node/synapse/signal/atom/moment/gate/KG/reader)

## Status

Proposed

## Date

2026-05-25

## Context
ADR-0001 commits CrossEngin to a substrate. A substrate is only as coherent as its vocabulary of primitives. Before designing any subsystem, we must fix the *minimal closed set* of first-class concepts from which everything else is composed, define each precisely, and map each onto a concrete NOVA primitive so that engineers build on real code rather than metaphor. Getting this set right is load-bearing: every ADR from ADR-0006 onward elaborates exactly one of these primitives, and ambiguity here propagates everywhere.

NOVA already supplies most of the raw material: `core/node.nova` (6 node types, inbox/outbox), `core/signal.nova` (8 base signal types, priority, trace, metadata), `core/channel.nova` (4 channel types including filtered/weighted), `core/moment.nova` (timestamped perception), `core/knowledge.nova` (KG with embeddings), and `core/belief.nova` (Bayesian alpha/beta). The task is to *select, name, and constrain* seven primitives over this base — adding the two genuinely new ones (synapse, gate) and the persistent data unit (atom) and KG-organization concept that the substrate needs.

The team constraint (2 founders, 8h/day, bootstrapping) argues for *exactly seven* primitives — enough to express the architecture, few enough that two people can hold the whole model in their heads and reuse one mechanism instead of inventing many.

## Decision
CrossEngin is built from **seven core primitives**, each first-class and each mapped to a NOVA primitive:

1. **NODE** — where computation happens. Uniform behavior across all nodes; specialization comes from learned *state*, not type (ADR-0006). Pre-allocated at startup, 1M per part (ADR-0003), sparse ~1000 synapses each. Maps to `core/node.nova` `[TAG, name, type, state, inbox, outbox, config]`; the 6 NOVA node types (`NTYPE_PERCEIVER`...`NTYPE_ACTOR`) become *bias hints*, not behavioral switches.
2. **SYNAPSE** — persistent weighted connection between nodes (and nodes-to-parts). Carries any signal type; weight learned via Hebbian + error-driven plasticity; grows and prunes with experience (ADR-0007). New primitive `synapse_new` built atop `core/channel.nova` (`CHAN_WEIGHTED`).
3. **SIGNAL** — ephemeral typed message flowing through synapses. CrossEngin defines 18 types (ADR-0008) extending the 8 base tags in `core/signal.nova`, preserving its `priority`/`trace`/`metadata` layout.
4. **ATOM** — persistent, mutable data unit produced by nodes only for *novel* patterns; stored in a domain KG; cross-KG referenced; carries Bayesian confidence (ADR-0016). New `atom_new` over `core/knowledge.nova` + `core/belief.nova`.
5. **MOMENT** — timestamped perception record; the entry point for external input; lives in episodic memory after processing (ADR-0021). Maps directly to `core/moment.nova`.
6. **GATE** — learned, content-based routing checkpoint between signals and nodes; can broadcast to multiple parts (ADR-0009). New `gate_new` over `core/channel.nova` (`CHAN_FILTERED`/`CHAN_BROADCAST`).
7. **KG (multi)** — domain-organized knowledge store, one per domain, spawned on new-domain detection, linked by similarity-weighted cross-references (ADR-0004, ADR-0017). Namespaced `core/knowledge.nova` + `core/similarity.nova`.

**Composition:** a moment enters perception's first nodes (ADR-0010); nodes emit signals; gates route signals across synapses to parts; nodes read/write atoms in KGs; output emerges from concept-activated nodes (ADR-0013). Higher constructs — soul, concepts, episodic memory, reasoning — are *organizations of these seven*, never new primitive kinds.

## Options Considered
**1. Seven primitives as above (CHOSEN).** *Pros:* minimal closed set; each maps to an existing or thin-new NOVA primitive; two founders can fully internalize it; clean 1:1 correspondence with ADRs 006-009/016/021. *Cons:* "node" carries heavy uniform-behavior assumptions (ADR-0006) that must hold; "atom vs concept" boundary needs the discipline of ADR-0018. Chosen because it is the smallest vocabulary that still expresses the full substrate.

**2. Fewer primitives — fold synapse into node, gate into signal-routing (rejected).** Treat connections as node-internal adjacency and routing as a signal field on `core/channel.nova`. *Pros:* fewer concepts, less new NOVA code. *Cons:* synapse plasticity (ADR-0007) and learned gate routing (ADR-0009) are *central* mechanisms with their own lifecycles, weights, and tests; hiding them inside nodes/signals makes them unaddressable as first-class objects and cripples observability. Rejected — under-modeling the two things that actually learn.

**3. More primitives — promote concept, soul, episode, drive to primitive status (rejected).** *Pros:* every major noun gets first-class type support and dedicated tests. *Cons:* explodes the vocabulary to a dozen-plus types, duplicates NOVA's existing `core/concept.nova`/`core/soul.nova`/`core/goal.nova`, and contradicts ADR-0001's thesis that complexity should *emerge from* a small substrate, not be enumerated. Two founders cannot maintain that surface area. Rejected — these are compositions, not primitives.

## Consequences
- **Positive:** A small, closed, NOVA-grounded vocabulary that every later ADR reuses; one mechanism per concern; uniform nodes mean specialization scales without new types (ADR-0003); clean mapping minimizes new NOVA code.
- **Negative:** Two genuinely new primitives (synapse, gate) require runtime enhancements (#2, #7) that do not yet exist; the node/atom/concept boundaries demand ongoing discipline; collapsing NOVA's 6 node types into bias-hints discards type-based dispatch we could otherwise lean on.
- **Future work:** Each primitive gets a dedicated ADR — node (ADR-0006), synapse (ADR-0007), signal taxonomy (ADR-0008), gate (ADR-0009), atom (ADR-0016), moment (ADR-0021), multi-KG (ADR-0017). First nodes (ADR-0010) specialize the node entry points; the reader (ADR-0011/012) operates over all seven.

## Implementation Notes
Constructors and accessors follow NOVA idiom (tag-prefixed lists/maps): `node_new`/`node_receive`/`node_emit`/`node_get_state` already exist in `core/node.nova`; add `synapse_new`, `synapse_weight`, `synapse_strengthen`, `synapse_prune`; `gate_new`, `gate_route`, `gate_broadcast`; `atom_new`, `atom_update`, `atom_confidence`, `atom_xref`. Define tag constants `TAG_SYNAPSE`, `TAG_GATE`, `TAG_ATOM`. Synapses use a sparse adjacency structure (#2); atoms namespace into per-domain KGs (#8). Signal tags extend `core/signal.nova` (#6).

DEPENDS ON: NOVA enhancement #2 — sparse synapse adjacency with O(1) weight update/growth/pruning.
DEPENDS ON: NOVA enhancement #6 — extended 18-type signal tag space with typed fast-dispatch.
DEPENDS ON: NOVA enhancement #7 — learned content-based gate routing tables.
DEPENDS ON: NOVA enhancement #8 — multi-KG namespacing + cross-KG reference edges.

Testing: a primitive-conformance fixture per type (construct, mutate, serialize, rehydrate) plus a composition test that walks a moment -> signal -> gate -> synapse -> node -> atom round trip, anchoring ADR-0050's earliest milestones.
