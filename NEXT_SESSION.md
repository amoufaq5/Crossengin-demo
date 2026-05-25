# CrossEngin — Next Session

This file is the source of truth for what works, what does not, and where to
continue. It is updated at every session boundary.

## Phase progress

- Phase 1 substrate kernel: **complete**
- Phase 2 reader and language: not started
- Phase 3 knowledge representation: not started
- Phase 4 memory and learning: not started
- Phase 5 self-directed learning: not started
- Phase 6 cognitive subsystems: not started
- Phase 7 agent architecture: not started
- Phase 8 safety and audit: not started
- Phase 9 IO and effectors: not started
- Phase 10 persistence and operations: not started

## Completed modules this session (Phase 1)

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
  `docs/design/{overview,data_flow}.md`; README updated to v0.1 reality.

## Partially completed modules

None. There are no stubs, no `.pending` files, and no `TODO`s in committed code.
Every Phase 1 module is fully implemented and tested.

## Modules not yet started (in plan order)

- Phase 2: `src/reader/{lexical_anchor,context_bias,spreading_activation,coherence_check,fetch_route_learn,reader}.nova`,
  `src/language/{word_atoms,phoneme_atoms,syntax_atoms}.nova`
- Phase 3: `src/kg/{multi_kg_manager,atom_store,cross_kg_references,concept_layer,schemas,skills_kg,competence_tracker}.nova`
- Phases 4–10: as listed in the master plan.

## Tests status

- Total unit suites: 9 (one per Phase 1 module); **284 assertions**.
- Total integration tests: 0 (Phase 7+ deliverable).
- Total benchmarks: 2 (`bench_tick_rate`, `bench_node_throughput`).
- All passing: **yes**. Failures: none.
- Latest benchmark numbers (NOVA v0.x, single container, second-resolution
  clock): single-part ~60k ticks/sec; full 7-part substrate ~35k part-ticks/sec;
  node throughput ~768k integrations/sec. These bound the current scalar driver;
  see ADR-0001's 100Hz target and enhancements #4/#5.

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
3. **Scale targets are aspirational for v0.x NOVA.** ADRs target 1M nodes/part,
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

None of these is a hard blocker for Phase 1 (all worked around with correct,
non-stub code). #1 and #6 are the ones most likely to constrain later phases at
scale; both have upstream-enhancement entries.

## Recommended next session start point

**Pull Phase 3's atom/KG core forward before the Phase 2 reader**, because the
reader (ADR-0011/0012) cannot anchor or spread without atoms and a KG. Concrete
order:

1. `src/kg/atom_store.nova` (ADR-0016) — the persistent, mutable knowledge atom
   (id, content, belief α/β via NOVA `belief_*`, links). Build on the substrate
   conventions established this session (milli-fixed-point, indexed arrays).
2. `src/kg/multi_kg_manager.nova` (ADR-0004/0016) — per-domain KGs keyed to the
   KG *parts* already supported by `part_lifecycle`.
3. `src/language/word_atoms.nova` (ADR-0015) — word atoms as KG atoms.
4. Then the Phase 2 reader stages, now that atoms/KG exist.

If strict phase order is preferred instead, start at
`src/language/word_atoms.nova` and define a minimal local atom representation,
but expect to refactor onto the Phase 3 KG. Flag this decision for human review.

A second, independent track that needs no new primitives: **inter-part signal
emission** — today `tick_driver` propagates *within* a part; wiring fired nodes
through `gate_router` to other parts' first nodes is the bridge to the six-loop
agent architecture (Phase 7) and would make the self-check multi-part-dynamic.

## Build/test commands verified working

`$HOME` in this environment is `/root`, but NOVA is at `/home/user/NOVA`, so
pass `NOVA_ROOT` explicitly (or set it in your shell):

```sh
# from the CrossEngin repo root, with NOVA built at /home/user/NOVA
make build      NOVA_ROOT=/home/user/NOVA   # compiles all 9 substrate modules -> OK
make test       NOVA_ROOT=/home/user/NOVA   # 9/9 unit suites PASS
make benchmark  NOVA_ROOT=/home/user/NOVA   # prints tick-rate + throughput metrics
make install    NOVA_ROOT=/home/user/NOVA   # builds bin/crossengin-selfcheck
bash scripts/run.sh                          # (honors $NOVA_ROOT env) prints "substrate self-check: OK"
```

To build the NOVA toolchain itself (one time): `cd /home/user/NOVA && make`
(produces `bin/nova` and the `nova` launcher; needs GNU `as`, `ld`).
