# ADR-0006: Node design (uniform behavior, sparse connectivity, atom production)

## Status

Proposed

## Date

2026-05-25

## Context
ADR-0001 commits CrossEngin to a substrate rather than a modular workflow, and ADR-0002 names the node as the locus of computation. We must now fix the node's internal design before any other substrate primitive (synapse, signal, gate) can be built, because every later ADR assumes a concrete node contract: how a node receives signals, what it computes, when it produces atoms, and how it specializes. NOVA's `core/node.nova` already gives us a node primitive with layout `[TAG, name, type, state, inbox, outbox, config]` and six base types (`NTYPE_PERCEIVER`, `NTYPE_KNOWER`, `NTYPE_REMEMBERER`, `NTYPE_REASONER`, `NTYPE_FEELER`, `NTYPE_ACTOR`) plus `node_receive`, `node_emit`, `node_drain_outbox`, `node_set_state`, `node_get_state`. The question is how CrossEngin extends this primitive to scale.

The scaling target from ADR-0003 is unforgiving: 1M nodes per part in v1, target 1B long-term, ~1000 synapses per node, 1B signals per part at peak. With nine parts that is 9M nodes in v1 living in pre-allocated arenas on a single desktop (the v1 deployment, ADR-0046). At that scale we cannot afford per-node heap objects, per-node vtables, or branchy type-dispatch in the hot signal-propagation loop running at 100Hz (ADR-0037). The two founders, working 8h/day on a bootstrap budget, also cannot maintain six divergent node implementations.

A core tension: ADR-0002's substrate thesis says specialization should EMERGE from learned state, not be hand-assigned. Yet `core/node.nova` ships six concrete node types. We must reconcile NOVA's typed node with CrossEngin's uniform-behavior ambition, and decide what role (if any) the six `NTYPE_*` constants play.

## Decision
All CrossEngin nodes share one uniform behavior function. A node is a small fixed-size record built on `core/node.nova`'s layout; CrossEngin specializes only the `state` and `config` slots. On each tick a node executes the same kernel: drain `inbox`, integrate incoming signals weighted by the synapse that delivered them (ADR-0007), update an activation level held in `state`, and on threshold crossing `node_emit` outgoing signals down its synapses. Specialization (a node that behaves like a medicine-concept detector vs. a phoneme detector) is entirely a function of which synapses it has and the weights/biases learned into them — NOT of its type tag.

The six `NTYPE_*` constants are retained but demoted to a PART-AFFINITY hint and a default-config selector, not a behavior switch. Every node in the KG-medicine part is tagged `NTYPE_KNOWER`; every perception-part node `NTYPE_PERCEIVER`; etc. The tag seeds initial connectivity bias and default plasticity constants but never branches the kernel. This keeps the hot loop branch-free and SIMD-friendly (enhancement #4) while preserving a human-readable map of the substrate.

Atom production is gated on novelty. A node produces an atom (ADR-0016, via a new `atom_new`) ONLY when its sustained co-activation pattern is not already explained by an existing atom — the birth rule formalized in ADR-0025. Routine firing produces signals, not atoms. Crucially, any node may READ atoms it did not create (cross-KG reads via ADR-0004/ADR-0017), so a reasoner node consumes knower-authored medicine atoms without owning them.

## Options Considered
**Typed nodes with per-type behavior (one kernel per `NTYPE_*`).** Use NOVA's six types as genuine polymorphism: perceiver nodes run perception logic, knower nodes run retrieval logic, etc. Rejected. It contradicts the ADR-0002 emergence thesis, hard-codes a cognitive ontology we want the system to discover, and puts a six-way branch in the 100Hz inner loop over 9M nodes, defeating the batched SIMD propagation of enhancement #4. It also triples maintenance for a 2-person team.

**Fully untyped nodes (drop `NTYPE_*` entirely).** Maximally pure substrate: one type, no affinity hints, connectivity learned from zero. Rejected for v1. With ~1000 synapses/node and 1M nodes/part, learning all structure from a uniform random init is sample-inefficient and would blow the 18-30 month timeline; we would spend months waiting for parts to differentiate. The affinity hint is a cheap prior that costs nothing at runtime.

**Heavyweight "agent" nodes (each node a coroutine).** Give each node its own `runtime/coroutine.nova` fiber so nodes are truly independent actors. Rejected: 9M fibers is far beyond enhancement #3's intent (which targets the SIX loops, ADR-0036), and the scheduler/memory overhead per fiber makes 1B nodes impossible on a desktop. Concurrency belongs at the loop and part granularity, not the node.

**Chosen:** uniform kernel + demoted type tag + novelty-gated atom production. It satisfies the emergence thesis where it matters (behavior), keeps a pragmatic prior where it helps (initial wiring), and stays within the desktop memory and the team's maintenance budget.

## Consequences
- **Positive:** One kernel to write, test, and optimize; trivially vectorizable across millions of nodes (enhancement #4). Specialization is observable as learned synapse structure, giving genuine emergence. Atom store stays small because routine activity never mints atoms. Part affinity gives a debuggable map without runtime cost.
- **Negative:** Behavior is harder to inspect — you cannot read a node's type to know what it does; you must inspect its learned synapses and state, which demands new tooling (a node-probe in the test harness). Uniformity pushes complexity into the synapse/plasticity layer (ADR-0007) and the gate layer (ADR-0009). A buggy kernel is a single point of failure for all 9M nodes.
- **Future work:** Defines the substrate for ADR-0007 (synapse), ADR-0009 (gate routing into nodes), ADR-0010 (first nodes as specialized receivers), and ADR-0024 (predictive-coding nodes that emit predictive/error signals). Node-pool expansion toward 1B (ADR-0003) reuses this record unchanged.

## Implementation Notes
Extend `core/node.nova` rather than fork it. Add a CrossEngin `xnode_state` map stored in the node's `state` slot with keys `activation` (float), `threshold` (float), `bias` (float), `last_fired_tick` (int), `novelty_accum` (float for the ADR-0025 birth rule). Keep `name`/`type`/`config` from the base layout; `type` holds the `NTYPE_*` affinity constant. Implement one function `xnode_tick(node, tick)` that calls `node_drain_outbox`/`node_receive` and reuses `node_set_state`/`node_get_state`; never branch on `type` inside it. Atom emission calls into the ADR-0016 `atom_new` only when `novelty_accum` exceeds the ADR-0025 birth threshold.

Pre-allocation: all 9M node records live in fixed arenas — `DEPENDS ON: NOVA enhancement #1 — pre-allocated fixed-capacity node arenas`. Batched activation update across a part's node array — `DEPENDS ON: NOVA enhancement #4 — SIMD/GPU batched signal propagation`. Tick cadence from `runtime/scheduler.nova` — `DEPENDS ON: NOVA enhancement #5 — 100Hz deterministic tick scheduler`.

Testing: fixture `fixture_part_1k` instantiates a 1k-node part; assert (a) identical kernel output for two nodes with identical synapses but different `NTYPE_*` tags (proves tag does not alter behavior), (b) no atom minted under repeated known input, exactly one minted on a genuinely novel co-activation, and (c) a reasoner-affinity node successfully reads a knower-authored atom (cross-KG read). Depends on ADR-0002 (primitive definitions) and ADR-0003 (arena sizing); consumed by ADR-0007, ADR-0009, ADR-0010, ADR-0024, ADR-0025.
