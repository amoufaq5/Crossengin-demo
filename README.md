# CrossEngin

CrossEngin is a non-LLM cognitive **substrate** system, implemented in
[NOVA](https://github.com/amoufaq5/nova). It targets AGI-relevant capability —
continuous learning, self-directed skill acquisition, theory of mind,
initiative, counterfactual reasoning, long-horizon goals, and self-awareness of
identity, state, and goals over time — by running a fabric of uniform
computational units rather than orchestrating a pipeline of modules.

> **Status: v0.2 — Phases 1 and 3 of 10 complete (substrate kernel + knowledge
> representation). There is no end-user cognitive agent yet.** Implemented in
> NOVA and verified against the real self-hosting toolchain: 16 modules compile
> (`make build`), 16 unit-test suites pass (`make test`, 463 assertions), three
> benchmarks report metrics (`make benchmark`), and the substrate self-check
> boots the kernel end-to-end (`make run`). See
> [`NEXT_SESSION.md`](./NEXT_SESSION.md) for exactly what works, what does not,
> and where to continue.

## What works now (v0.2)

The Phase 1 substrate kernel (`src/substrate/`):

- **node_pool_manager** — the uniform leaky-integrate-and-fire node kernel over
  a pre-allocated pool, with novelty tracking and the integer milli-fixed-point
  convention (ADR-0006).
- **signal_dispatch** — the 18 `XSIG_*` signal types with ADR-0008 priorities
  and a priority-bucketed FIFO dispatch queue.
- **synapse_graph** — sparse weighted synapses with Hebbian + error-driven
  plasticity, eligibility decay, growth, and idle prune/reclaim (ADR-0007).
- **first_nodes** — stable per-part input blocks and modality presets (ADR-0010).
- **part_registry / part_lifecycle** — the seven fixed parts plus dynamic,
  per-domain KG parts (ADR-0001).
- **gate_router** — learned content-based routing with the privileged,
  non-learnable constitutional broadcast (ADR-0009, ADR-0045).
- **resonance_engine** — bidirectional co-activation reinforcement into stable
  assemblies.
- **tick_driver** — the four-phase substrate tick: snapshot → integrate →
  propagate → learn (ADR-0006, ADR-0001).

The Phase 3 knowledge layer (`src/kg/`):

- **atom_store** — the persistent knowledge atom with immutable (kg_id, id)
  identity, versioned mutation, and a Bayesian alpha/beta belief; also the
  shared milli belief + integer-cosine vector helpers (ADR-0016, ADR-0023).
- **multi_kg_manager** — per-domain knowledge graphs with embedding centroids
  (ADR-0004).
- **cross_kg_references** — automatic + earned cross-KG links and the
  spawn-on-new-domain heuristic (ADR-0017).
- **schemas** — entity-type validation with required/optional fields and
  min/max constraints (ADR-0018).
- **concept_layer** — the concept DAG with promotion, schema slots, facet
  vectors, members, and kg_span (ADR-0018).
- **skills_kg** — procedural skills (ATOM_SKILL) with Bayesian reliability,
  step rules, activation, and retirement (ADR-0019).
- **competence_tracker** — the self-model: per-domain competence (know/do/
  understand) computed from belief/skill/concept state, with four tiers
  (ADR-0020).

Everything else (Phase 2 reader/language atoms, episodic memory, the learning
fabric, self-directed learning, cognitive subsystems, agent loops, safety/audit,
IO, persistence) is specified in the ADRs but **not yet implemented**.

## What "substrate, not workflow" means

Intelligence is intended to emerge from substrate dynamics, not from a
controller calling cognitive modules in sequence. The primitives are:

- **node** — uniform computational unit; specialization comes from learned
  state, not type. ~1M per part in v1 (target 1B), sparsely connected.
- **synapse** — persistent weighted connection; learns via Hebbian +
  error-driven plasticity; grows and prunes.
- **signal** — ephemeral typed message flowing through synapses (18 types).
- **atom** — persistent, mutable knowledge unit produced by nodes, stored in a
  domain knowledge graph, cross-referenced across graphs.
- **moment** — timestamped perception record; the entry point for input.
- **gate** — learned, content-based router between signals and parts.
- **KG (multi)** — domain-organized knowledge stores, spawned per domain.
- **reader** — five-stage hybrid input processor (not a parser, not an LLM).

A first principle runs through the whole design: **no LLM participates in
cognition.** The NOVA LLM bridge is reserved for speech-to-text / text-to-speech
modality conversion only (ADR-0014).

## Repository layout

```
docs/
  adr/        50 Architecture Decision Records (ADR-0001 .. ADR-0050)
  design/     architecture overview and supporting design docs
  runbook/    build / test / operational docs
src/
  substrate/  node pool, synapse, signal, tick, resonance  (the kernel)
  reader/     five-stage reader (ADR-0011, ADR-0012)
  gates/      learned signal routing (ADR-0009)
  parts/      perception, episodic, soul, reasoning, imagination, action, meta
  kg/         multi knowledge-graph store (ADR-0016, ADR-0017)
  learning/   self-directed learning (ADR-0026 .. ADR-0030)
  safety/     permission tiers, reversibility, constitution (ADR-0041 .. 0045)
  io/         transducers (STT/TTS modality) and motor effectors
  scheduler/  hybrid 100Hz tick + event scheduler (ADR-0037)
  audit/      append-only decision log (ADR-0043)
tests/        unit / integration / benchmark
scripts/      bootstrap.sh, run.sh, test.sh
examples/     runnable demos (kernel self-check)
```

Directories without code yet contain a `README.md` describing their
responsibility and governing ADRs.

## Building and running

CrossEngin compiles with the NOVA self-hosting toolchain in a sibling checkout
(`$HOME/NOVA` by default). NOVA has no third-party dependencies; it needs only
GNU `as`, `ld`, `make`, and `gcc`.

```sh
# one-time: verify host tools, locate/build the NOVA compiler
bash scripts/bootstrap.sh

# compile every implemented substrate module
make build

# compile and run the unit tests
make test

# run the substrate self-check (no full agent yet)
bash scripts/run.sh
```

Point the build at a NOVA checkout elsewhere with `make NOVA_ROOT=/path/to/NOVA build`.

See [`docs/runbook/build.md`](./docs/runbook/build.md) and
[`docs/runbook/test.md`](./docs/runbook/test.md) for details, and
[`docs/design/overview.md`](./docs/design/overview.md) for the architecture.

## NOVA dependency and version note

The CrossEngin specification was written against an assumed "NOVA v4.1". The
NOVA checkout this repository builds against reports **v0.2.0**
(`src/version.nova`) / **v0.9.0** (launcher). CrossEngin pins to that actual
self-hosting toolchain and treats the larger capabilities (1M-node arenas,
sparse synapse adjacency at scale, true concurrency, 100Hz wall-clock pacing,
multi-KG, outbound fetch) as **upstream NOVA enhancements** that the ADRs assume
will land. Those enhancements are enumerated in
[`nova-deps.toml`](./nova-deps.toml) (`#1`..`#14`) and referenced throughout the
ADRs as `DEPENDS ON: NOVA enhancement #N`. Code that cannot yet be implemented
against the current toolchain is checked in as `*.nova.pending` (interface only)
and tracked in [`NEXT_SESSION.md`](./NEXT_SESSION.md).

## Decision records

Every architectural decision is recorded under [`docs/adr/`](./docs/adr/),
numbered `0001`–`0050` and grouped Foundation → Computation substrate → Reader
and language → Knowledge representation → Memory and learning → Self-directed
learning → Cognitive subsystems → Agent architecture → Safety and audit →
Operations and milestones. Start at
[`docs/adr/0001-substrate-architecture.md`](./docs/adr/0001-substrate-architecture.md).

## License

Proprietary and confidential. See [`LICENSE`](./LICENSE).
