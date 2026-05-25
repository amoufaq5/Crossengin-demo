# CrossEngin — Next Session

This file is the source of truth for what works, what does not, and where to
continue. It is updated at every session boundary.

## Phase progress

- Phase 1 substrate kernel: **complete**
- Phase 2 reader and language: **complete**
- Phase 3 knowledge representation: **complete**
- Phase 4 memory and learning: not started
- Phase 5 self-directed learning: not started
- Phase 6 cognitive subsystems: not started
- Phase 7 agent architecture: not started
- Phase 8 safety and audit: not started
- Phase 9 IO and effectors: not started
- Phase 10 persistence and operations: not started

## Completed modules — Phase 1 (substrate kernel)

All under `src/substrate/`. Each compiles with `nova build` and has a matching
`tests/unit/test_<module>.nova` suite (happy path + edge + failure cases).

| Module | ADRs | Unit asserts | Status |
|--------|------|--------------|--------|
| node_pool_manager.nova | 0006, 0002, 0010 | 40 | done |
| signal_dispatch.nova | 0008, 0002 | 49 | done |
| synapse_graph.nova | 0007, 0002 | 55 | done |
| first_nodes.nova | 0010, 0006 | 29 | done |
| part_registry.nova | 0001, 0002 | 26 | done |
| part_lifecycle.nova | 0001 | 21 | done |
| gate_router.nova | 0009, 0045 | 24 | done |
| resonance_engine.nova | 0001, 0007, 0008 | 20 | done |
| tick_driver.nova | 0006, 0001 | 20 | done |

Also delivered:
- `tests/ce_test.nova` — shared assertion harness (lives outside `tests/unit/`
  so the runner does not treat it as a test).
- `examples/kernel_selfcheck.nova` — the runnable v0.1 artifact (`make run` /
  `make install`); boots all 9 modules end-to-end and asserts liveness.
- `tests/benchmark/bench_tick_rate.nova`, `tests/benchmark/bench_node_throughput.nova`.
- `make benchmark` target added to the Makefile.
- Docs: `docs/runbook/{build,test,run,troubleshooting}.md`,
  `docs/design/{overview,data_flow}.md`.

## Completed modules — Phase 3 (knowledge representation)

All under `src/kg/`, each compiling with a matching unit-test suite. Built on
the substrate's milli-fixed-point convention; belief and vector cosine are
implemented in-house (see NOVA blockers).

| Module | ADRs | Unit asserts | Status |
|--------|------|--------------|--------|
| atom_store.nova | 0016, 0023 | 42 | done |
| multi_kg_manager.nova | 0004, 0016 | 23 | done |
| cross_kg_references.nova | 0017, 0004 | 20 | done |
| schemas.nova | 0018 | 13 | done |
| concept_layer.nova | 0018 | 28 | done |
| skills_kg.nova | 0019 | 26 | done |
| competence_tracker.nova | 0020 | 27 | done |

Also delivered: `tests/benchmark/bench_kg_query.nova` (insertion, id/label
lookup, observation throughput).

## Completed modules — Phase 2 (reader and language)

Language atoms under `src/language/`; the five-stage reader under `src/reader/`.
Each compiles with a matching unit-test suite. No LLM is touched (ADR-0014); the
reader operates purely over the language KG, concept layer, and substrate
signals.

| Module | ADRs | Unit asserts | Status |
|--------|------|--------------|--------|
| language/word_atoms.nova | 0015 | 20 | done |
| language/phoneme_atoms.nova | 0015 | 12 | done |
| language/syntax_atoms.nova | 0015, 0013 | 14 | done |
| reader/lexical_anchor.nova | 0012 (stage 1), 0011 | 19 | done |
| reader/context_bias.nova | 0012 (stage 2) | 9 | done |
| reader/spreading_activation.nova | 0012 (stage 3), 0017 | 8 | done |
| reader/coherence_check.nova | 0012 (stage 4) | 11 | done |
| reader/fetch_route_learn.nova | 0012 (stage 5) | 11 | done |
| reader/reader.nova | 0011, 0012 | 13 | done |

README updated to v0.3.

## Partially completed modules

None. There are no stubs, no `.pending` files, and no `TODO`s in committed code.
Every Phase 1, 2, and 3 module is fully implemented and tested.

## Modules not yet started (in plan order)

- Phase 4: `src/parts/episodic/{moment_stream,episode_storage,consolidation}.nova`,
  `src/learning/{bayesian_updates,predictive_coding_runtime,atom_birth_monitor,atom_death_monitor,plasticity_modulation}.nova`
- Phases 5–10: as listed in the master plan.

## Tests status

- Total unit suites: 25 (9 substrate + 7 knowledge + 9 reader/language); **580 assertions**.
- Total integration tests: 0 (Phase 7+ deliverable).
- Total benchmarks: 3 (`bench_tick_rate`, `bench_node_throughput`, `bench_kg_query`).
- All passing: **yes**. Failures: none.
- Latest benchmark numbers (NOVA v0.x, single container, second-resolution
  clock): single-part ~60k ticks/sec; full 7-part substrate ~35k part-ticks/sec;
  node throughput ~768k integrations/sec; KG O(1) id-lookup ~300k/sec; KG O(n)
  label scan is the slow path (linear over atoms) -- a scalable name index is a
  future optimization. These bound the current scalar implementation.

## ADR ambiguities encountered

1. **resonance_engine has no dedicated ADR.** The master plan lists
   `resonance_engine.nova` in Phase 1, but ADRs 0001–0010 define no separate
   resonance primitive. Interpretation: implemented resonance as the
   bidirectional co-activation reinforcement of reciprocally connected nodes
   (the `<=>` dynamic), grounded in ADR-0001 (emergent dynamics), ADR-0007
   (synapse weights/eligibility), and ADR-0008 (XSIG_BIND assemblies). Revisit
   if a future ADR specifies different resonance semantics.
2. **Phase ordering vs. dependencies.** Phase 2 (reader) precedes Phase 3
   (atoms/KG) and Phase 4 (moments), yet the five-stage reader (ADR-0011/0012)
   anchors input to *word atoms* and spreads activation over a *KG* — both
   later-phase primitives. Recommendation below resolves this.
3. **Persistence: "day one" rule vs. Phase 10 ordering.** The master plan's
   rule 8 says every state-bearing module should implement save/load "from day
   one," but its own phase plan places persistence at Phase 10, and ADR-0048
   specifies a *single ordered* snapshot/rehydration scheme (soul → KGs →
   episodic) rather than ad-hoc per-module files. The Phase 1 substrate is
   therefore in-memory only; bolting on per-module save/load now would risk
   diverging from the ADR-0048 design. Decision: defer persistence to a coherent
   Phase 10 implementation against ADR-0048, but keep node/synapse/part state in
   plain integer arrays and stable first-node index ranges precisely so it
   snapshots cleanly. Flagged for human review.
4. **Scale targets are aspirational for v0.x NOVA.** ADRs target 1M nodes/part,
   ~1000 synapses/node, 100Hz wall-clock, true concurrency. Phase 1 implements
   the correct *semantics* at configurable capacity; the scale/throughput/
   concurrency aspects are the upstream NOVA enhancements in `nova-deps.toml`
   (#1–#14), cited per module header. No ADR was contradicted.

## NOVA blockers and footguns (important — read before Phase 2)

The CrossEngin spec assumes "NOVA v4.1 + N1–N29"; the actual toolchain is the
self-hosting NOVA in the sibling checkout (launcher reports v0.9.0, core
v0.2.0). It builds and runs CrossEngin fine, but these real toolchain behaviors
shaped the implementation and must be respected going forward:

1. **Builtin `map` caps at 16 keys — hard hang past that.** Inserting a 17th
   distinct key into a `map_new()` map linear-probes forever (no resize).
   Discovered when a synapse graph with >16 source nodes hung. **Workaround
   applied:** synapse adjacency, the part registry, and the gate table are now
   id/type-indexed *arrays*, not maps (this is also more ADR-faithful: CSR by
   source, O(1) typed dispatch). **Do not** use the builtin map for any set that
   can exceed 16 distinct keys. (Upstream: NOVA map needs auto-resize.)
2. **Undefined function calls segfault — no link error.** Calling a function
   that was never imported compiles silently and crashes at runtime. Import
   every module whose functions you call. (Cost me a debugging cycle on the
   self-check.)
3. **`map_has` treats a stored value of 0 as absent.** Avoid 0-valued map
   entries, or store `value+1`. (Now moot since we avoid maps, but true.)
4. **`float_*` builtins are IEEE-754 doubles, not the "scaled-by-1000"
   the language reference implies.** The substrate uses integer milli-fixed-point
   (`fp_mul`, scale 1000) exclusively and never touches `float_*`. Keep doing
   this for determinism.
5. **stdout is block-buffered; flushes on exit.** A hung program prints nothing,
   even past the hang point. Bisect hangs by making the suspect region exit.
6. **No sub-second clock.** Only `time()` (epoch seconds) exists; benchmarks run
   enough work to span ≥1s. A real 100Hz wall-clock pacer (ADR-0037) needs a
   finer timer — NOVA enhancement #5.
7. **Global names are one flat namespace across imports.** Two files defining
   the same top-level `let`/`fn` name collide at assembly time. Prefix module
   constants (we use `NS_`, `SG_`, `PART_`, `GATE_`, `XSIG_`, `TD_`, ...).
8. **Reserved word `asm`.** Cannot be used as an identifier.
9. **NOVA's knowledge modules do not std-import cleanly (v0.x).** `core/belief.nova`
   is not in the std-package registry (segfaults on use); `import "std/embed"`
   fails with duplicate-symbol link errors; `import "std/map"` segfaults the
   *compiler*. **Workaround applied (Phase 3):** CrossEngin implements its own
   minimal alpha/beta belief and integer cosine vectors in `atom_store.nova`
   (milli-fixed-point, same semantics as `core/belief.nova`), and uses id-indexed
   lists + linear-scan for name lookup. `contains()` does work for string lists.
10. **Import dedup is by accumulated path string, not canonical path.** A shared
   module reached via two different relative-path accumulations (e.g.
   `.../kg/../substrate/node_pool_manager.nova` via the kg subtree and
   `.../substrate/node_pool_manager.nova` via a substrate sibling) is included
   *twice* -> duplicate-symbol link errors. NOVA does not normalize `..`.
   **Consequence (Phase 2):** the reader stays within the kg + signal_dispatch
   layer (signal_dispatch is standalone, so it does not drag node_pool); it does
   NOT import the substrate part registry / gate router. Mapping the reader's
   symbolic route targets to gate-routed part signals is therefore deferred to
   the agent layer (Phase 7), which is the right layering anyway. When Phase 7
   must bridge subtrees, either route everything through one subtree's import
   prefix, or introduce a `nova_packages/` shim so shared modules resolve to one
   canonical string.

None of these is a hard blocker (all worked around with correct, non-stub code).
#1, #6, #9, #10 are the ones most likely to constrain later phases; #1/#6 have
upstream-enhancement entries, #9/#10 want NOVA to make cognitive-core modules
std-importable and to canonicalize import paths.

## Recommended next session start point

**Phase 4 — episodic memory and the learning fabric.** Now the natural next
step (the reader exists and produces percepts to remember/learn from). Suggested
order:

1. `src/parts/episodic/moment_stream.nova` (ADR-0021) — the timestamped moment
   record and the append-only moment stream. This gives atoms real
   `created_moment` timestamps (currently a passed-in logical tick) and the
   reader a place to record each read.
2. `src/parts/episodic/{episode_storage,consolidation}.nova` (ADR-0022) —
   episodes over the moment stream; consolidation into semantic atoms.
3. `src/learning/bayesian_updates.nova` (ADR-0023) — formalizes the alpha/beta
   evidence updates atoms/skills already use (build on `atom_store`'s `bel_*`).
4. `src/learning/{predictive_coding_runtime,atom_birth_monitor,atom_death_monitor,plasticity_modulation}.nova`
   (ADR-0024, 0025) — the error term `tick_driver` currently passes as 0, and
   novelty-gated atom birth / decay-gated death (atoms already track a version
   and belief; nodes already track novelty).

Reuse what exists: `atom_store` `bel_*`/`vec_*`/`handle_*`, the substrate node
novelty accumulator, and the reader's `rctx`. Do not reach for NOVA's
core/belief or std/embed (NOVA blocker #9).

Cross-cutting, also valuable: **inter-part signal emission + reader→substrate
wiring** — today `tick_driver` propagates *within* a part and the reader routes
to symbolic targets. Wiring fired nodes (and reader percepts) through
`gate_router` to other parts' first nodes is the bridge to the six-loop agent
architecture (Phase 7). Mind NOVA blocker #10 when bridging the kg and substrate
subtrees in one compile unit (use one import-prefix convention or a
`nova_packages/` shim).

## Build/test commands verified working

`$HOME` in this environment is `/root`, but NOVA is at `/home/user/NOVA`, so
pass `NOVA_ROOT` explicitly (or set it in your shell):

```sh
# from the CrossEngin repo root, with NOVA built at /home/user/NOVA
make build      NOVA_ROOT=/home/user/NOVA   # compiles all 25 modules -> OK
make test       NOVA_ROOT=/home/user/NOVA   # 25/25 unit suites PASS
make benchmark  NOVA_ROOT=/home/user/NOVA   # prints tick-rate + throughput metrics
make install    NOVA_ROOT=/home/user/NOVA   # builds bin/crossengin-selfcheck
bash scripts/run.sh                          # (honors $NOVA_ROOT env) prints "substrate self-check: OK"
```

To build the NOVA toolchain itself (one time): `cd /home/user/NOVA && make`
(produces `bin/nova` and the `nova` launcher; needs GNU `as`, `ld`).
