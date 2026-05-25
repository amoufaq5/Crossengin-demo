# ADR-0003: Scaling plan (1M v1 -> 1B target, sparse connectivity, growth strategy)

## Status

Proposed

## Date

2026-05-25

## Context
ADR-0001 and ADR-0002 commit us to a substrate of uniform nodes connected by synapses. That immediately raises the hardest engineering question in the project: *how many* nodes and synapses, allocated *how*, and *growing how* — on hardware we can actually afford? The answer must satisfy two seemingly opposed forces. v1 must run on a single consumer desktop as a personal companion (ADR-0046); the long-term thesis needs a substrate large enough for rich emergent capability. We therefore commit to **1M nodes per part in v1** with a **1B-node-per-part long-term target**, and we must show the v1 number fits in a desktop memory budget.

The forces to state: 2 founders, 8h/day, bootstrapping (no budget for GPU clusters or server farms); v1 on commodity hardware (assume a 32-64 GB desktop); the substrate runs ~100Hz (ADR-0037) with up to 1B signals per part at peak throughput. Crucially, ADR-0006 mandates *uniform node behavior* and *sparse connectivity* (~1000 synapses/node initially) — both of which are what make the memory math survivable.

A naive dense substrate is fatal: 1M nodes with all-to-all connectivity is 10^12 synapses *per part* — impossible on a desktop and unnecessary, since real associative structure is sparse. The plan must instead exploit sparsity hard, pre-allocate to avoid runtime fragmentation, and grow capability primarily by *adding and reweighting synapses* before ever expanding the node pool.

## Decision
We adopt a **two-axis scaling plan**: a fixed node-pool axis and an elastic synapse axis, with growth driven primarily by synapses.

**Node axis (pre-allocated, fixed per generation).** Each part pre-allocates its full node arena at startup — 1M nodes in v1 — in one contiguous fixed-capacity region (#1). No runtime node allocation; nodes are *recruited* from the idle pool by learned state, not malloc'd. This makes the working set predictable and crash-safe to snapshot (ADR-0048). The 1B target is a *future generation*, reached by enlarging the arena on capable hardware (v2+), not by per-request growth.

**Synapse axis (sparse, elastic).** Connectivity starts at ~1000 synapses/node and grows with experience, pruning weak connections (ADR-0007). Synapses live in a CSR-like sparse adjacency (#2), giving O(1) weight update, growth append, and prune. This is the primary growth mechanism: the substrate gets *smarter* mainly by re-wiring and reweighting, only secondarily by recruiting idle nodes.

**v1 desktop memory budget (per part).** 1M nodes x ~1000 synapses = 10^9 synapse slots/part. At a packed 12 bytes/synapse (≈4B weight + ≈4B target index + ≈4B metadata/plasticity trace) that is ~12 GB of synapse adjacency per part. Node records (state map, inbox/outbox handles) at ~256 B/node add ~256 MB/part. We therefore run **a small number of active parts simultaneously per desktop process** (not all nine at full density at once): the perception/reasoning/episodic/soul working set fits comfortably in 32-64 GB, while domain KGs page their cold atoms to `runtime/db.nova`. Signal objects are *ephemeral* and pooled — the "1B signals/part" figure is peak *throughput* across a tick window, not 1B resident objects.

## Options Considered
**1. Pre-allocated fixed pool + sparse elastic synapses (CHOSEN).** *Pros:* predictable memory, no fragmentation, trivially snapshot-able (ADR-0048), and the synapse-first growth model matches biological and associative reality; the 12 GB/part math fits a desktop. *Cons:* the node ceiling per generation is hard — if 1M nodes/part proves too few for a capability, we cannot grow nodes without a generation bump and re-snapshot. Chosen because predictability and desktop-fit dominate for a 2-founder v1.

**2. Fully dynamic allocation — grow nodes and synapses on demand (rejected).** *Pros:* no arbitrary ceiling; the substrate sizes itself to the workload. *Cons:* runtime allocation under a 100Hz tick causes fragmentation and GC pauses that wreck determinism; memory becomes unbounded and unpredictable on a fixed desktop; snapshots become hard. Rejected as incompatible with ADR-0037's tick guarantees and ADR-0046's fixed budget.

**3. Dense connectivity at smaller node counts (rejected).** Trade node count for all-to-all richness — e.g. 50K dense nodes/part. *Pros:* simpler adjacency (a matrix), trivially SIMD/GPU-batched (#4). *Cons:* 50K dense = 2.5x10^9 synapses for *one tenth* the spreading-activation reach, and dense matrices waste >99% of capacity on connections that never carry useful signal; it also caps the associative fan-out that cross-domain reasoning (ADR-0004) needs. Rejected — sparsity buys far more useful structure per byte.

## Consequences
- **Positive:** Fits a commodity desktop (ADR-0046); deterministic memory enables 100Hz ticking (ADR-0037) and clean snapshots (ADR-0048); synapse-first growth gives continuous learning a natural substrate; sparse representation scales reach without quadratic cost.
- **Negative:** Hard per-generation node ceiling; the 1M->1B jump is a discontinuous re-architecture (sharding, possibly multi-process/multi-device), not a config change; sparse adjacency plus 100Hz propagation makes SIMD/GPU batching (#4) essential, not optional.
- **Future work:** The 1B target requires partitioning parts across processes/devices (federation-ready v1, ADR-0046; tenant-per-process v2, ADR-0047). Plasticity kernels (ADR-0007, #12) and batched propagation (#4) must be benchmarked under ADR-0049's multi-day test before committing to denser generations.

## Implementation Notes
Node arenas extend `runtime/persistent_alloc.nova` + `runtime/alloc.nova`; the sparse synapse store is a new CSR-like structure over `runtime/mem.nova`. Per-tick propagation batches over synapse weight arrays via `runtime/simd.nova`/`runtime/tensor.nova`/`runtime/blas.nova`, with `runtime/gpu.nova` as the scale path. Cold atoms page to `runtime/db.nova`. Snapshot/rehydration follows ADR-0048 ordering (soul -> KGs -> episodic).

DEPENDS ON: NOVA enhancement #1 — pre-allocated fixed-capacity node arenas (1M+/part, target 1B).
DEPENDS ON: NOVA enhancement #2 — sparse synapse adjacency (CSR-like) with O(1) update/growth/prune.
DEPENDS ON: NOVA enhancement #4 — SIMD/GPU batched signal propagation across millions of synapses/tick.
DEPENDS ON: NOVA enhancement #12 — Hebbian + error-driven plasticity kernels over synapse weight arrays.

Testing: a memory-budget fixture asserting per-part resident bytes stay under target on a 32 GB box; a propagation-throughput benchmark (synapses/tick) feeding ADR-0049; a growth/prune test verifying synapse count converges rather than diverging.
