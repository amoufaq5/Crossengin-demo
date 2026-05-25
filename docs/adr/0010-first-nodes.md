# ADR-0010: First nodes (specialized sensory input receivers per part)

## Status

Proposed

## Date

2026-05-25

## Context
External input enters CrossEngin as a moment (ADR-0002, ADR-0021) and must be injected into the substrate somewhere. Since nodes are uniform (ADR-0006) and gates route signals to PARTS (ADR-0009), we need a well-defined ENTRY POINT within each part where routed input lands and begins propagating. ADR-0002 names these FIRST NODES: "specialized nodes in each part that receive sensory input routed through gates; entry points to each part's substrate." We must decide how first nodes are designated, how gates address them, and how they specialize per part — without violating the uniform-behavior decision of ADR-0006.

This matters now because first nodes are the seam between three already-decided pieces: moments/perception (sensory `XSIG_SENSORY` signals, ADR-0008), gate routing (ADR-0009, which routes to a part), and the node kernel (ADR-0006). If gates route only to "a part" but a part has 1M uniform nodes, the signal has no defined landing site. First nodes resolve that: they are the part's named, stable input surface. They are also where the predictive-coding stack bottoms out (ADR-0024) — top-down predictions meet bottom-up sensory signals at the first nodes of perception.

The constraint, again, is reconciling specialization with uniformity. ADR-0006 forbids per-type behavior. Yet a phoneme first-node in perception and a goal-cue first-node in reasoning clearly do different jobs. The resolution must keep the kernel uniform while letting first nodes differ only in their wiring and config, and it must give each first node a stable index so gate routing tables (ADR-0009) and inter-part synapse blocks (ADR-0007) can target them across restarts (ADR-0048).

## Decision
Each part reserves a small, fixed block of its 1M nodes — the FIRST-NODE block (e.g. the first 1,024 indices per part) — as its sensory/input receiver surface. First nodes are ordinary ADR-0006 nodes running the identical kernel; they are "specialized" only by (a) a stable, well-known index range that gates and inter-part synapses address, (b) a richer initial fan-out of synapses into the rest of the part, and (c) per-part config presets matching the part's input modality. No kernel branch distinguishes them — their distinct behavior is entirely learned wiring plus config, consistent with ADR-0006.

Gates (ADR-0009) route to a part by delivering to that part's first-node block, not to arbitrary interior nodes. The routing table's destination is therefore (part-id, first-node-block); a `CHAN_BROADCAST` from a gate fans a signal across the relevant first nodes. Per-part specialization of first nodes: perception first nodes receive `XSIG_SENSORY` from moments (sub-grouped by modality — text/phoneme, and audio via the STT bridge, ADR-0014); reasoning first nodes receive `XSIG_GOAL`, `XSIG_CAUSAL`, `XSIG_IMPLY`; episodic first nodes receive `XSIG_RECALL`; soul/meta first nodes receive `XSIG_VALENCE`/`XSIG_AROUSAL`/`XSIG_CONST`. Each part's first-node config seeds which signal types it expects, but gates can LEARN to deliver additional types (ADR-0009) so the input surface adapts.

First nodes are the canonical bottom of the predictive-coding hierarchy (ADR-0024): perception first nodes emit `XSIG_ERROR` upward when incoming `XSIG_SENSORY` mismatches the `XSIG_PREDICT` arriving top-down. They mint atoms under the same novelty rule as any node (ADR-0006/ADR-0025) — typically the first to do so for genuinely new percepts.

## Options Considered
**Designated first-node block (reserved index range per part).** The chosen approach: a fixed, named slice of each part's node arena. Chosen because it gives gates and inter-part synapses a stable, restart-safe target (ADR-0048), keeps the kernel uniform (ADR-0006), costs nothing at runtime (just an index convention), and is trivial to pre-allocate (enhancement #1). Its only cost is reserving capacity that is fixed in size.

**A separate node TYPE for receivers (e.g. lean on `NTYPE_PERCEIVER`).** Make first nodes a distinct type with receiver-specific behavior. Rejected: it reintroduces per-type behavior, directly violating ADR-0006, and `NTYPE_*` is already demoted to an affinity hint there. We get the labeling benefit by part affinity + index range without a behavioral branch.

**Dynamic/learned entry points (any node may be a receiver; gates learn which).** Maximally flexible — no reserved block; gates learn to route input to whichever interior nodes prove useful. Rejected for v1: with 1M nodes/part the routing table's destination space becomes enormous and unstable across restarts, breaking persistence (ADR-0048) and making gate learning (ADR-0009) far slower to converge. A fixed entry surface is the right cold-start prior; interior adaptation still happens via synapse growth beyond the first nodes.

**Chosen:** reserved per-part first-node block with per-part config presets and learned-extendable gate delivery. It is stable, uniform-kernel-compatible, cheap, and gives predictive coding a defined bottom layer.

## Consequences
- **Positive:** A stable, addressable input surface per part that gates and inter-part synapses can target deterministically across restarts (ADR-0048). Keeps ADR-0006 uniformity intact (no new type, no kernel branch). Gives ADR-0024 a concrete bottom layer for sensory-vs-prediction error. Per-part config presets give sensible day-one behavior; gate learning lets the surface adapt later.
- **Negative:** Reserving a fixed first-node block per part is a static capacity decision — too small bottlenecks input, too large wastes arena; the size (e.g. 1,024) needs tuning. First nodes are a higher-traffic hotspot, concentrating load and making them a potential propagation bottleneck under peak 1B-signal bursts. A bug in first-node wiring blocks all input to a part.
- **Future work:** Directly underpins ADR-0021 (moments inject at perception first nodes), ADR-0024 (predictive-coding bottom layer), and ADR-0013 (output is the inverse path, from concept activation toward motor effectors). v2 enterprise (ADR-0047) replicates the first-node convention per tenant process. Snapshot/rehydration (ADR-0048) must restore first-node indices before general nodes.

## Implementation Notes
No new core module is required — first nodes are a CONVENTION over ADR-0006 nodes plus ADR-0009 routing. Add to `core/node.nova` usage a per-part constant `FIRST_NODE_COUNT` (e.g. 1024) and reserve indices `[0, FIRST_NODE_COUNT)` of each part's arena. Provide helpers `part_first_nodes(part)` (returns the block) and `part_inject(part, signal)` (delivers a routed signal across the block via `core/channel.nova` `CHAN_BROADCAST`). First-node config presets are a static per-part table mapping part-id → expected `XSIG_*` types (ADR-0008), used to seed gate routes (ADR-0009) and initial synapse fan-out (ADR-0007).

`DEPENDS ON: NOVA enhancement #1 — pre-allocated fixed-capacity node arenas` (the reserved block lives at the front of each arena). Input delivery and fan-out use `DEPENDS ON: NOVA enhancement #4 — SIMD/GPU batched signal propagation`. The STT-only modality path that may feed perception first nodes is isolated per `DEPENDS ON: NOVA enhancement #14 — STT/TTS modality bridge isolation guaranteeing no cognition path` — first nodes receive only `XSIG_SENSORY` content, never LLM-derived cognition (NO-LLM-COGNITION principle).

Testing: `fixture_inject_moment` builds a moment (ADR-0021), routes it through a gate (ADR-0009), and asserts it lands on perception's first-node block and raises their activation; `fixture_first_node_error` sends a mismatched `XSIG_PREDICT` and asserts a first node emits `XSIG_ERROR` upward (pre-check for ADR-0024); `fixture_first_node_uniform` asserts a first node and an interior node with identical synapses produce identical kernel output (proves no behavioral specialization, upholding ADR-0006). Depends on ADR-0006, ADR-0008, ADR-0009; feeds ADR-0021, ADR-0024, ADR-0013, ADR-0048.
