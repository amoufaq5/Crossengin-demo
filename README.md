# CrossEngin

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/amoufaq5/Crossengin-demo)

CrossEngin is a non-LLM cognitive **substrate** system, implemented in
[NOVA](https://github.com/amoufaq5/nova). It targets AGI-relevant capability —
continuous learning, self-directed skill acquisition, theory of mind,
initiative, counterfactual reasoning, long-horizon goals, and self-awareness of
identity, state, and goals over time — by running a fabric of uniform
computational units rather than orchestrating a pipeline of modules.

> **Status: v1.0 — all 10 phases complete and assembled into one unified agent
> process.** Implemented in NOVA and verified against the real self-hosting
> toolchain: 88 modules compile (`make build`), 90 unit-test suites pass
> (`make test`, 1579 assertions, +1 suite / +22 assertions from
> `test_learn_tag.nova` added in Phase 15 Tier-2 #3 multi-source `/learn`),
> three benchmarks report metrics
> (`make benchmark`), and three runnable artifacts build and run
> (`make install`): the substrate kernel self-check, the safety+IO+persistence
> companion spine, and **`bin/crossengin` — the whole agent in one process**
> (substrate + knowledge + soul + goals + scheduler + IO + safety + persistence,
> no LLM). The unified assembly was previously blocked by NOVA's import-path
> dedup (blocker #10); that is now **fixed in the toolchain** (path
> canonicalization — see [`NEXT_SESSION.md`](./NEXT_SESSION.md)). What remains is
> production hardening of the documented runtime seams (fsync-durable
> persistence, TLS fetch, STT/TTS bridge, a sub-second wall-clock pacer, SIMD) so
> the daemon can run continuously across real restarts. NEXT_SESSION.md records
> exactly what works, what does not, and where to continue.

## What works now (v1.0)

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

The Phase 2 language layer (`src/language/`) and reader (`src/reader/`):

- **word_atoms / phoneme_atoms / syntax_atoms** — words (with lexical vectors
  and weighted concept senses), phonemes, and ordered syntax patterns as
  ATOM_LANG atoms in a language KG (ADR-0015).
- **reader** (five stages, ADR-0011/0012, no LLM per ADR-0014):
  - **lexical_anchor** — tokenize and match to word atoms; SENSORY on a hit,
    CURIOSITY on an out-of-vocabulary token.
  - **context_bias** — resolve polysemy by similarity to the active context.
  - **spreading_activation** — spread over cross-KG edges and settle on an
    active concept set.
  - **coherence_check** — accept a mutually-referencing reading or escalate.
  - **fetch_route_learn** — route a comprehended percept and strengthen
    anchors, or trigger ask-user / fetch learning.

The Phase 4 memory and learning fabric (`src/parts/episodic/`, `src/learning/`):

- **moment_stream** — timestamped, append-only moment records with a
  PERCEIVED→SETTLED→CONSOLIDATED lifecycle (ADR-0021).
- **episode_storage** — episodes over moments with decay, recall reinforcement,
  tiering, and drop (ADR-0022).
- **consolidation** — recurring co-activation signatures become atom-birth
  candidates (ADR-0022).
- **bayesian_updates** — tracked beliefs with decay, tiered evidence, conflict,
  and a CONTESTED flag (ADR-0023).
- **predictive_coding_runtime** — precision-weighted prediction error with
  suppression/surprise thresholds and the upward error signal (ADR-0024).
- **atom_birth_monitor / atom_death_monitor** — novelty/frequency/stability
  gated atom birth, and decay/belief gated death with tombstoning (ADR-0025).
- **plasticity_modulation** — the learning-rate modulator from emotional
  arousal/valence/reward (ADR-0035/0007).

The Phase 5 self-directed learning layer (`src/learning/`):

- **self_learning_triggers** — gap detection (prediction error, curiosity,
  imagination gap, unknown query, user request), priority scoring, and an
  arbitration queue with user pre-emption (ADR-0026).
- **confidence_thresholds** — the low/high-stakes "learned enough" gates and
  hard caps that close a learning episode (ADR-0030).
- **ask_user_to_teach** — gap→question with an ask budget; ingests the reply as
  Beta(4,1) user-taught Tier-A evidence (ADR-0027).
- **source_whitelist / source_authority** — the allowed-domain gate, source
  tiers (A/B/C) with evidence weights, recency-policy conflict resolution, and
  user-taught precedence (ADR-0028/0029).
- **internet_fetch** — whitelist + rate-limit + cache + validation + tiered
  ingestion (ADR-0028); the TLS transport itself is a deferred seam (NOVA
  enhancement #11).

The Phase 6 cognitive subsystems (`src/parts/`):

- **goals** (`goals/`) — priority-sorted goal trees with rollup, block
  propagation, leaf arbitration, and staleness decay; the four intrinsic drives;
  and serialization with load-time validation (ADR-0033).
- **soul** (`soul/`) — the behavioral identity: slow identity (gated, audited
  revision) + OCEAN, fast state, medium goal summary, and the cross-cutting
  values, constitution (privileged XSIG_CONST veto), themes, and loyalty
  hierarchy (ADR-0034).
- **emotion** (`emotion/`) — OCC appraisal → valence/arousal/emotion-type, OCEAN
  conditioning, and emotion-modulated plasticity + episodic encoding (ADR-0035).
- **reasoning** (`reasoning/`) — operator atoms (causal/implicative/analogical/
  evidential) and five thin strategies: forward chaining, abduction, analogical
  transfer, evidential combination, and means-ends decomposition (ADR-0031).
- **imagination** (`imagination/`) — learned pattern atoms and four modes:
  forward simulation, counterfactual, dream recombination, and scenario planning
  (ADR-0032).

The Phase 7 agent architecture (`src/scheduler/`, `src/agent/`, `src/parts/meta/`):

- **scheduler** (`scheduler/`) — the hybrid 100Hz tick (`tick_loop` over the
  substrate) + event-driven coordination (`event_dispatch`), fused with idle
  detection in `hybrid_scheduler` (ADR-0037).
- **agent loops** (`agent/`) — the six cognitive loops (perception, memory,
  reasoning, emotion, goals, action) + the idle-gated imagination loop, over a
  shared `loop_coordination` blackboard (ADR-0036).
- **meta** (`parts/meta/`) — the self-model query API ("what/state/goals/
  competence", ADR-0038), theory-of-mind user model (ADR-0039), and
  long-horizon goal accrual + revisit scan (ADR-0040).

The Phase 8 safety and audit stack (`src/safety/`, `src/audit/`):

- **reversibility_classifier** — classifies each action class as reversible /
  recoverable / irreversible, defaulting any unlisted action to irreversible
  (fail-safe); also home to the shared `ACT_*` action-class constants (ADR-0042).
- **permission_tiers** — the AUTO / NOTIFY / APPROVE tiers as the MAX of a
  static per-class default and the reversibility floor, so irreversible actions
  are always ≥ APPROVE; unknown classes default to APPROVE (ADR-0041).
- **decision_log** — the append-only, hash-chained decision record: every entry
  links to its predecessor so mutation, reorder, and tail-truncation all fail
  `dl_verify` (ADR-0043).
- **audit_writer / audit_reader** — the write path (intent entry before the
  effector, outcome after; corrections and overrides appended) and the
  inspection path (chain verification + plain-language "why did you do X?"
  rendered purely from stored state, no LLM) (ADR-0043, ADR-0038).
- **override_mechanism** — the four graded user interventions: belief edit
  (privileged α/β write + pin), goal veto (subtree prune + standing regen-block),
  hard stop (drain actions, substrate alive), and kill switch (clean snapshots,
  panic skips); all but panic-kill are logged (ADR-0044).
- **constitutional_filter** — the safety gate: constitutional veto (terminal,
  unclearable by user approval) → hard stop → permission tier, plus the soul
  loyalty resolution (constitution > enterprise > user > system) (ADR-0045).

The Phase 9 IO and effectors layer (`src/io/`):

- **output_generation** (`io/effectors/`) — pure-substrate language production
  (ADR-0013), the reverse of the reader: a communicative intent (role→concept
  assignments) resolves to real word atoms, a learned syntax-pattern atom orders
  them, and the text is emitted; well-formed patterns win, ill-formed are pruned,
  and accepted phrasings strengthen via plasticity. NO LLM (ADR-0014).
- **effector_gate** (`io/effectors/`) — the action chokepoint: every outward
  action runs the Phase 8 `safety_gate` (constitutional veto → hard stop →
  permission tier), logs an intent entry **before** the effector and an outcome
  **after** (ADR-0043). The text/SPEAK effector is fully implemented; governed
  speak vetoes a constitutionally-forbidden utterance by its text and never
  emits it.
- **input_transducer** (`io/transducers/`) — modality → reader-ready normalized
  percept (ADR-0011/0012, ADR-0021); strictly outside cognition (ADR-0014).
  Text/file are normalized now; audio (STT) is the honest deferred bridge seam.

The Phase 10 persistence layer (`src/persistence/`):

- **snapshot_writer** (ADR-0048) — the substrate-snapshot container: a tagged,
  versioned image with fixed, ordered sections `[SOUL][KGS][EPISODIC][SYNAPSES]
  [SELFMODEL]`, each holding a subsystem-serialized blob. Generic over the blobs
  (so it stays standalone); the crash-safe disk write (temp → fsync → atomic
  rename) is the runtime seam.
- **snapshot_reader** (ADR-0048) — parse + tag/version rejection, and the
  **load-bearing mandatory rehydration order** (soul → KGs → episodic): it
  refuses to load KGs before the soul (constitution must be live before any atom
  is admitted) or episodic before KGs (moments would dangle), and emits the
  ordered rehydration plan. The decision log persists independently and is not
  rolled back by a restore.

Three runnable artifacts build via `make install`: `examples/kernel_selfcheck.nova`
boots the substrate kernel; `examples/companion_spine.nova` runs the safety + IO +
persistence spine; and **`examples/crossengin_daemon.nova` → `bin/crossengin` is
the whole agent in one process**, driven by the ADR-0037 hybrid scheduler as a
real event-driven loop: input arrives as events; each step drains one and ticks
the substrate; on an event the full ADR-0036 six-loop cycle runs (perception via
the five-stage reader → memory → reasoning → emotion → goals → action) over a
shared concept KG, so a word read in perception seeds reasoning and imagination.
Affect emerges from the agent's own comprehension and becomes the tick's
plasticity modulator (with a predictive-coding residual as its error); a run of
empty ticks throttles the scheduler 100Hz→10Hz idle, gating imagination and
triggering a checkpoint. Output emerges from the substrate's reasoning: a reverse concept→word lookup
finds the naming word for a new conclusion and speaks it through the gated
effector ("see treat" after reading "fever"), no LLM picking the wording. The
agent also *grows its knowledge graphs at runtime*: unknown surface forms fire
self-learning triggers; at idle the arbiter drains them and `ask_user_to_teach`
ingests new word atoms + concept bindings (Beta(4,1) Tier-A prior) — a
follow-up event with the freshly-taught vocabulary is then comprehended. Forbidden actions are vetoed and logged; on shutdown the agent reboots
by rehydrating in mandatory order. This unified cross-subtree assembly is what
the import-path fix unblocked.

> Integration note: each loop is a self-contained unit over the shared
> blackboard, so the loops compose without tripping NOVA's import-dedup limit
> (blocker #10). Wiring all loops + the scheduler together in one program is the
> Phase 10 `main`, which will need a `nova_packages/` shim (see NEXT_SESSION.md).

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
  persistence/ ordered substrate snapshot + rehydration (ADR-0048)
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

# compile every module under src/
make build

# compile and run every unit test
make test

# build all three runnable artifacts into ./bin/
make install
./bin/crossengin                # the whole agent in one process
./bin/crossengin-selfcheck      # substrate kernel spine
./bin/crossengin-spine          # safety + IO + persistence spine
```

Point the build at a NOVA checkout elsewhere with `make NOVA_ROOT=/path/to/NOVA build`.

**For a complete walkthrough — prerequisites, three artifacts with expected
output, writing a new test, and troubleshooting — see [`MANUAL.md`](./MANUAL.md).**
Per-topic references: [`docs/runbook/build.md`](./docs/runbook/build.md),
[`docs/runbook/test.md`](./docs/runbook/test.md),
[`docs/runbook/run.md`](./docs/runbook/run.md), and
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
