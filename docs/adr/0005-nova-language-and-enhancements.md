# ADR-0005: NOVA as implementation language with required enhancements

## Status

Proposed

## Date

2026-05-25

## Context
CrossEngin is the application; NOVA is the language and runtime it is built on (ADR-0001, ADR-0002). We must decide *deliberately* whether to implement on NOVA or on a mainstream stack, and — having chosen — enumerate exactly which NOVA enhancements CrossEngin depends on, since those gaps are submitted upstream to the NOVA repo and every ADR ASSUMES they will land. This is a foundational decision because the entire substrate (1M-node arenas, sparse synapses, 100Hz ticking, plasticity kernels) bottoms out in runtime capabilities that do not yet fully exist.

The constraints cut both ways. We are 2 founders, 8h/day, bootstrapping, on an 18-30 month v1 timeline. A mainstream stack (Rust/C++, or Python+PyTorch) is battle-tested with vast libraries and hiring pools. But CrossEngin's value is precisely its *cognitive primitives*: NOVA already ships `core/node.nova`, `core/signal.nova`, `core/channel.nova`, `core/moment.nova`, `core/knowledge.nova`, `core/belief.nova`, `core/goal.nova`, `core/concept.nova`, `core/soul.nova`, `core/imagination.nova`, `core/safety.nova`, plus the cognitive `mind/` and `agent/` layers and a `runtime/` with SIMD/tensor/BLAS/GPU, persistence, and a package manager (`pkg/pkg.nova`). NOVA is self-hosting (its own `compiler/`) and currently passes 129/135 tests. Rebuilding these primitives on another stack would consume most of the v1 budget before any CrossEngin-specific work began.

The decisive risk is therefore not "is NOVA capable" but "can the *missing* runtime pieces land in time," since CrossEngin and NOVA are co-developed by the same two founders and every hour spent on NOVA enhancements is an hour not spent on CrossEngin.

## Decision
**CrossEngin is implemented in NOVA.** We build directly on NOVA's existing core/mind/agent/runtime primitives and contribute the substrate-enabling gaps upstream as a numbered enhancement program. The seven primitives (ADR-0002) map onto real NOVA modules; CrossEngin adds `synapse_new`, `gate_new`, `atom_new`, multi-KG namespacing, and the 18-signal tag extension in NOVA idiom.

CrossEngin formally depends on the following **14 NOVA enhancements**; ADRs across all groups flag them by number. They cluster into four programs:
- **Substrate scale & compute:** #1 pre-allocated node arenas (1M->1B), #2 sparse synapse adjacency (CSR, O(1) update/grow/prune), #4 SIMD/GPU batched propagation, #12 Hebbian + error-driven plasticity kernels. (ADR-0003, ADR-0006, ADR-0007.)
- **Dynamics & concurrency:** #3 true concurrent execution units for the 6 loops, #5 100Hz tick fused with event-driven coordination, #13 idle-detection + background scheduling for imagination/replay. (ADR-0036, ADR-0037, ADR-0022, ADR-0032.)
- **Knowledge & routing:** #6 18+ signal tag space with typed fast-dispatch, #7 learned content-based gate routing, #8 multi-KG namespacing + cross-KG reference edges. (ADR-0008, ADR-0009, ADR-0004/017.)
- **Safety, persistence & I/O:** #9 append-only crash-safe audit log, #10 substrate snapshot + ordered rehydration, #11 whitelisted rate-limited HTTP fetch, #14 STT/TTS modality-bridge isolation. (ADR-0043, ADR-0048, ADR-0028, ADR-0014.)

Critically, **#14 hardens the boundary that enforces the NO-LLM-COGNITION principle** (ADR-0014): `runtime/llm.nova` + `runtime/llm_bridge.c` are restricted to STT/TTS modality conversion with no path into cognition.

## Options Considered
**1. NOVA + upstream enhancement program (CHOSEN).** *Pros:* the cognitive primitives already exist (node/signal/channel/moment/knowledge/belief/goal/concept/soul/safety/imagination) — reusing them saves the bulk of the v1 budget; NOVA is self-hosting with a working compiler and 129/135 tests; one language across substrate, runtime, and tooling minimizes context-switching for 2 founders; enhancements benefit both repos. *Cons:* we own the runtime gaps (#1-#14) ourselves — no external community to land them; NOVA's ecosystem and hiring pool are essentially us; tooling/debuggers are immature relative to mainstream. Chosen because the primitive reuse is decisive and the gaps, though real, are tractable and co-owned.

**2. Rust or C++ from scratch (rejected).** *Pros:* mature toolchains, excellent performance, strong memory control ideal for fixed arenas and SIMD, large libraries and hiring pool. *Cons:* every cognitive primitive — soul, beliefs, concept layer, goal engine, knowledge graph, imagination — would be rebuilt from zero, almost certainly blowing the 18-30 month v1 budget before CrossEngin-specific work starts; we would also lose NOVA's self-hosting tooling. Rejected: it optimizes the *runtime* problem we mostly don't have and ignores the *primitive* problem we do.

**3. Python + PyTorch (rejected).** *Pros:* fastest prototyping, unrivaled numerical/GPU ecosystem, trivial to express plasticity kernels and batched propagation. *Cons:* the GIL and GC are hostile to genuine concurrency for the 6 loops (#3) and to deterministic 100Hz ticking (#5); pre-allocated fixed arenas (#1) and crash-safe substrate snapshots (#10) fight the runtime; and the gravitational pull toward dropping in an LLM directly threatens the NO-LLM-COGNITION principle (ADR-0014). Rejected: wrong concurrency/determinism model and a standing temptation against our core principle.

## Consequences
- **Positive:** Maximum reuse of existing cognitive primitives; a single coherent language for substrate + runtime + tooling; enhancements compound value across both repos; self-hosting compiler gives full control over codegen for SIMD/arena needs.
- **Negative:** The 14 enhancements are a hard dependency owned entirely by the same 2 founders — schedule risk concentrates here; immature ecosystem/tooling; bus-factor and hiring risk from a niche language. Any slipped enhancement blocks the dependent ADRs.
- **Future work:** Sequence the enhancements against the build plan (ADR-0050) so each lands just before its dependent milestone; #4/#12 gate the substrate-scale milestone (ADR-0003); #3/#5 gate the concurrent-loops milestone (ADR-0036/037); #14 must land before any speech I/O ships (ADR-0014); #9/#10 before desktop v1 persistence (ADR-0046/048).

## Implementation Notes
Build on `core/*`, `mind/*`, `agent/agent.nova`, and `runtime/*` as named in §3; new CrossEngin primitives follow NOVA's constructor/accessor idiom (`synapse_new`, `gate_new`, `atom_new`, `kg_spawn`). Manage the dependency via `pkg/pkg.nova`, pinning NOVA versions per enhancement landing. The enhancement map: #1/#2 over `runtime/persistent_alloc.nova`+`alloc.nova`+`mem.nova`; #4/#12 over `runtime/simd.nova`+`tensor.nova`+`blas.nova`+`gpu.nova`; #3/#5/#13 over `runtime/coroutine.nova`+`taskpool.nova`+`chan.nova`+`scheduler.nova`; #6 over `core/signal.nova`; #7 over `core/channel.nova`; #8 over `core/knowledge.nova`+`similarity.nova`; #9 over `runtime/db.nova`+`core/safety.nova`; #10 over `runtime/persistent_alloc.nova`+`db.nova`; #11 over `runtime/io.nova`+`syscall.nova`; #14 over `runtime/llm.nova`+`llm_bridge.c`.

DEPENDS ON: NOVA enhancements #1-#14 — the full substrate-enabling program enumerated above.

Testing: each enhancement ships with NOVA-side tests folded into the 129/135 suite (target full green before the dependent CrossEngin milestone); a CrossEngin integration fixture per cluster; and the ADR-0049 capability tests — including an explicit no-LLM-cognition verification asserting the only call path into `runtime/llm.nova` is STT/TTS (#14).
