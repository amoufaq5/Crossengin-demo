# CrossEngin architecture overview

CrossEngin is a non-LLM cognitive **substrate**: a fabric of uniform
computational units whose dynamics are intended to give rise to cognition,
rather than a controller orchestrating cognitive modules in sequence
(ADR-0001). This document orients you in the substrate kernel that exists
today (v0.1, Phase 1 of 10). The binding specification is the ADR set under
[`../adr/`](../adr/); start at
[`0001-substrate-architecture.md`](../adr/0001-substrate-architecture.md).

## The seven core primitives (ADR-0002)

| Primitive | Module | Role |
|-----------|--------|------|
| node | `src/substrate/node_pool_manager.nova` | uniform unit; one kernel for all (ADR-0006) |
| synapse | `src/substrate/synapse_graph.nova` | persistent weighted, plastic connection (ADR-0007) |
| signal | `src/substrate/signal_dispatch.nova` | ephemeral typed message, 18 types (ADR-0008) |
| gate | `src/substrate/gate_router.nova` | learned content-based router (ADR-0009) |
| part | `src/substrate/part_registry.nova` | a region owning a pool + graph + first nodes (ADR-0001) |
| atom / KG | `src/kg/atom_store.nova`, `src/kg/multi_kg_manager.nova` | persistent Bayesian knowledge unit in per-domain KGs (ADR-0016, ADR-0004) |
| moment | (Phase 4) | timestamped perception record, the input entry point |

The Phase 3 knowledge layer adds, on top of those: cross-KG references and the
spawn heuristic (`cross_kg_references.nova`, ADR-0017), the concept DAG
(`concept_layer.nova`, ADR-0018), entity schemas (`schemas.nova`, ADR-0018),
procedural skills (`skills_kg.nova`, ADR-0019), and the self-model competence
tracker (`competence_tracker.nova`, ADR-0020). Belief is alpha/beta Bayesian
(milli) and similarity is integer cosine, both in `atom_store.nova`.

Supporting Phase 1 modules: `first_nodes.nova` (stable input block per part,
ADR-0010), `resonance_engine.nova` (bidirectional co-activation reinforcement),
`part_lifecycle.nova` (dynamic KG spawn/retire), and `tick_driver.nova` (the
substrate tick, ADR-0006/0001).

## Key invariants

- **Uniform kernel.** Every node runs the same leaky-integrate-and-fire kernel
  with a novelty trace; the six `NTYPE_*` values are affinity *hints*, not
  behavioral switches. Specialization emerges from learned synapse structure
  (ADR-0006).
- **Safety ordering of signals.** Priority `XSIG_CONST(9) > XSIG_ERROR(7) >
  XSIG_INHIBIT(6) > ... > XSIG_EXCITE(4)`: constitution and surprise outrun
  routine excitation (ADR-0008).
- **Constitutional routing is privileged.** `XSIG_CONST` always broadcasts to
  every part and can never be down-weighted or pruned by a gate (ADR-0009,
  ADR-0045).
- **Stable first-node blocks.** Each part reserves index range `[0, count)` as
  its input block; stable across restarts for persistence (ADR-0010, ADR-0048).

## Representation conventions

- **Fixed-point.** Real values are integers scaled by 1000 (1.0 == 1000).
  Multiply with `fp_mul`. NOVA's `float_*` builtins are deliberately unused (see
  the troubleshooting runbook).
- **No maps for unbounded key sets.** Adjacency, the part registry, and the gate
  table are id/type-indexed arrays, both for ADR fidelity (CSR-by-source, O(1)
  typed dispatch) and to avoid NOVA's 16-key builtin-map cap.

## Scale and the NOVA enhancement dependencies

The ADRs target 1M nodes/part, ~1000 synapses/node, 100Hz wall-clock ticks, and
true concurrency. The current toolchain (NOVA v0.x) does not yet provide those
at scale; the Phase 1 modules are **functionally correct at configurable
capacity now** and scale unchanged when the upstream enhancements land. The
dependencies are enumerated in [`../../nova-deps.toml`](../../nova-deps.toml)
(`#1`..`#14`) and cited in each module header.

See [`data_flow.md`](./data_flow.md) for how a stimulus flows through one tick.
