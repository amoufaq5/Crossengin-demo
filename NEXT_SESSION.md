# CrossEngin — Next Session

This file is the source of truth for what works, what does not, and where to
continue. It is updated at every session boundary.

## Phase progress

- Phase 1 substrate kernel: **complete**
- Phase 2 reader and language: **complete**
- Phase 3 knowledge representation: **complete**
- Phase 4 memory and learning: **complete**
- Phase 5 self-directed learning: **complete**
- Phase 6 cognitive subsystems: **complete**
- Phase 7 agent architecture: **complete**
- Phase 8 safety and audit: **complete**
- Phase 9 IO and effectors: **complete**
- Phase 10 persistence and operations: **complete** (modules + spine artifact +
  the unified single-process daemon `bin/crossengin`; blocker #10 fixed in the
  NOVA toolchain — see below)

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

## Completed modules — Phase 4 (memory and learning)

Episodic modules under `src/parts/episodic/`; learning fabric under
`src/learning/`. Each compiles with a matching unit-test suite. Kept in the
kg / self-contained layer (no direct substrate-node imports) to respect NOVA
blocker #10; node-level values (novelty, activation, error, modulator) are
passed as parameters.

| Module | ADRs | Unit asserts | Status |
|--------|------|--------------|--------|
| episodic/moment_stream.nova | 0021 | 29 | done |
| episodic/episode_storage.nova | 0022 | 19 | done |
| episodic/consolidation.nova | 0022, 0025 | 10 | done |
| learning/bayesian_updates.nova | 0023, 0029 | 20 | done |
| learning/predictive_coding_runtime.nova | 0024 | 18 | done |
| learning/atom_birth_monitor.nova | 0025 | 15 | done |
| learning/atom_death_monitor.nova | 0025 | 18 | done |
| learning/plasticity_modulation.nova | 0035, 0007 | 10 | done |

README updated to v0.4.

## Completed modules — Phase 5 (self-directed learning)

All under `src/learning/`, each compiling with a matching unit-test suite. Kept
self-contained or kg-layer-only (NOVA blocker #10). The internet fetch transport
(TLS byte retrieval) is a deferred seam -- NOVA enhancement #11; the pipeline
(whitelist, rate limit, cache, validation, ingestion) is complete and tested.

| Module | ADRs | Unit asserts | Status |
|--------|------|--------------|--------|
| confidence_thresholds.nova | 0030 | 23 | done |
| source_whitelist.nova | 0028 | 14 | done |
| source_authority.nova | 0029 | 22 | done |
| self_learning_triggers.nova | 0026 | 27 | done |
| ask_user_to_teach.nova | 0027 | 19 | done |
| internet_fetch.nova | 0028, 0029 | 20 | done |

README updated to v0.5.

## Completed modules — Phase 6 (cognitive subsystems)

Five subsystems under `src/parts/`, each module compiling with a matching
unit-test suite. Goals/soul/emotion are self-contained; reasoning/imagination
import the kg layer on a single prefix (NOVA blocker #10).

| Module | ADRs | Unit asserts | Status |
|--------|------|--------------|--------|
| goals/goal_engine.nova | 0033 | 20 | done |
| goals/drive_generators.nova | 0033 | 15 | done |
| goals/goal_persistence.nova | 0033 | 11 | done |
| soul/identity.nova | 0034 | 13 | done |
| soul/state.nova | 0034 | 11 | done |
| soul/values.nova | 0034 | 8 | done |
| soul/constitution.nova | 0034, 0045 | 11 | done |
| soul/themes.nova | 0034 | 7 | done |
| soul/loyalty.nova | 0034 | 9 | done |
| soul/goals_in_soul.nova | 0034 | 7 | done |
| emotion/appraisal.nova | 0035 | 14 | done |
| emotion/ocean_conditioning.nova | 0035 | 8 | done |
| emotion/plasticity_mod.nova | 0035, 0007 | 7 | done |
| reasoning/reasoning_atoms.nova | 0031 | 13 | done |
| reasoning/reasoning_module.nova | 0031 | 12 | done |
| imagination/imagination_engine.nova | 0032 | 14 | done |
| imagination/forward_sim.nova | 0032 | 7 | done |
| imagination/counterfactual.nova | 0032 | 8 | done |
| imagination/dream_recombination.nova | 0032 | 6 | done |
| imagination/scenario_planner.nova | 0032 | 6 | done |

README updated to v0.6.

## Completed modules — Phase 7 (agent architecture)

Scheduler under `src/scheduler/`, loops under `src/agent/`, meta under
`src/parts/meta/`. Each module compiles with a matching unit-test suite. Design
that respects NOVA blocker #10: each loop is a self-contained unit over the
shared `loop_coordination` blackboard (one subsystem import, one node_pool
path); the scheduler is substrate-subtree only. Wiring all loops + the scheduler
into one program is the Phase 10 `main` (needs a `nova_packages/` shim).

| Module | ADRs | Unit asserts | Status |
|--------|------|--------------|--------|
| scheduler/event_dispatch.nova | 0037 | 10 | done |
| scheduler/tick_loop.nova | 0037 | 8 | done |
| scheduler/hybrid_scheduler.nova | 0037, 0036 | 11 | done |
| agent/loop_coordination.nova | 0036 | 16 | done |
| agent/loop_perception.nova | 0036 | 4 | done |
| agent/loop_memory.nova | 0036 | 4 | done |
| agent/loop_reasoning.nova | 0036 | 3 | done |
| agent/loop_emotion.nova | 0036, 0035 | 3 | done |
| agent/loop_goals.nova | 0036, 0033 | 3 | done |
| agent/loop_action.nova | 0036, 0013 | 4 | done |
| agent/loop_imagination_idle.nova | 0036, 0032 | 2 | done |
| parts/meta/self_model_query.nova | 0038 | 9 | done |
| parts/meta/theory_of_mind.nova | 0039, 0044 | 13 | done |
| parts/meta/long_horizon_goals.nova | 0040 | 9 | done |

README updated to v0.7.

## Completed modules — Phase 8 (safety and audit)

Safety stack under `src/safety/`, the audit/decision log under `src/audit/`.
Each module compiles with a matching unit-test suite. The whole safety stack is
a single clean dependency chain (no blocker #10): `reversibility_classifier`
(also home to the shared `ACT_*` constants) <- `permission_tiers` <-
`constitutional_filter`; the audit log layers `decision_log` <- `audit_writer`/
`audit_reader`; `override_mechanism` composes the kg-belief, goal-engine, and
audit subtrees (three disjoint subtrees, so they coexist). The gate chain is
`safety_gate` (constitutional veto -> hard stop -> permission tier, which folds
the reversibility floor); the audit log is append-only and hash-chained
(tamper-evident: mutation, reorder, and tail-truncation all fail `dl_verify`).
Pure substrate, NO LLM (ADR-0014). The fsync-backed durable store (ADR-0043
write path) and the process-exit/snapshot syscalls (ADR-0044 kill) are the
documented runtime seams (NOVA enhancements #9/#10); all decision logic is real
and tested.

| Module | ADRs | Unit asserts | Status |
|--------|------|--------------|--------|
| safety/reversibility_classifier.nova | 0042, 0041 | 21 | done |
| safety/permission_tiers.nova | 0041, 0042 | 24 | done |
| audit/decision_log.nova | 0043 | 25 | done |
| audit/audit_writer.nova | 0043 | 25 | done |
| audit/audit_reader.nova | 0043, 0038 | 14 | done |
| safety/override_mechanism.nova | 0044, 0043, 0023 | 27 | done |
| safety/constitutional_filter.nova | 0045, 0041, 0042 | 22 | done |

README updated to v0.8.

## Completed modules — Phase 9 (IO and effectors)

Output generation and effectors under `src/io/effectors/`, the input transducer
under `src/io/transducers/`. Each module compiles with a matching unit-test
suite. Layering for NOVA blocker #10: `output_generation` is the language
subtree only (it reaches words/syntax via a single import prefix);
`effector_gate` composes the safety subtree (`constitutional_filter`) with the
standalone `decision_log` — two disjoint trees, so no double-include (it
deliberately does NOT also import `audit_writer`, whose `permission_tiers` path
would collide, and rebuilds the descriptor/append locally); `input_transducer`
is standalone.

| Module | ADRs | Unit asserts | Status |
|--------|------|--------------|--------|
| io/effectors/output_generation.nova | 0013, 0015, 0007 | 10 | done |
| io/effectors/effector_gate.nova | 0041..0045, 0043, 0013 | 23 | done |
| io/transducers/input_transducer.nova | 0014, 0011, 0012, 0021 | 19 | done |

Pure substrate, NO LLM (ADR-0014): `output_generation` produces text by the
reverse of comprehension (intent -> real word atoms -> learned syntax ordering),
`effector_gate` is the chokepoint that runs the Phase 8 `safety_gate` and writes
intent-before/outcome-after decision-log entries (the SPEAK effector is fully
implemented; governed speak vetoes forbidden output by its text). File/network/
message transport and audio STT/TTS are the documented runtime seams (NOVA
enhancements #11/#14); all gate/log/generation logic is real and tested.

README updated to v0.9.

## Completed modules — Phase 10 (persistence + spine artifact)

Persistence under `src/persistence/`, plus the runnable companion-spine artifact.
Each module compiles with a matching unit-test suite. The snapshot writer/reader
are the generic ADR-0048 CONTAINER (tagged/versioned, fixed ordered sections,
each an opaque subsystem blob), so they stay standalone (no subsystem imports,
no blocker #10) and compose into any binary. The load-bearing part is enforced
in the reader: the mandatory rehydration order soul -> KGs -> episodic (refuse
KGs before soul, episodic before KGs), so the constitution is live before any
atom is admitted and no moment dangles. The decision log (ADR-0043) is
durable-but-separate and is not rolled back by a restore. Crash-safe disk write
(temp -> fsync -> atomic rename) and subsystem byte-serialization are the runtime
seams (NOVA enhancements #9/#10); the container, ordering, and validation are
implemented and tested.

| Module | ADRs | Unit asserts | Status |
|--------|------|--------------|--------|
| persistence/snapshot_writer.nova | 0048 | 27 | done |
| persistence/snapshot_reader.nova | 0048 | 25 | done |

Also delivered (runnable artifacts via `make install`):
- `examples/kernel_selfcheck.nova` -> `bin/crossengin-selfcheck` — the substrate
  kernel spine.
- `examples/companion_spine.nova` -> `bin/crossengin-spine` — the safety + IO +
  persistence spine.
- `examples/crossengin_daemon.nova` -> `bin/crossengin` — **the whole agent in
  one process**, driven by the ADR-0037 hybrid scheduler as a real event-driven
  loop (not a fixed script). Input arrives as EV_MESSAGE events; each scheduler
  step drains <=1 event and ticks the substrate. On an event the agent runs the
  full ADR-0036 six-loop cycle -- perception (five-stage reader) -> memory
  (episodic) -> reasoning (forward-chaining) -> emotion -> goals -> action (gated
  output) -- and AFFECT EMERGES FROM ITS OWN COMPREHENSION (how much it
  understood), not scripted numbers; that mood becomes the tick's plasticity
  modulator and a predictive-coding residual its error. A run of empty ticks
  throttles the scheduler 100Hz -> 10Hz idle, which gates imagination (over the
  lingering active set) and triggers a checkpoint; on shutdown the agent reboots
  by rehydrating in mandatory order (soul -> KGs). The reader, reasoning
  operators, and imagination patterns share ONE concept KG, so a read word is a
  valid reasoning seed and imagination state -- a coherent pipeline. Output now
  emerges from the substrate's reasoning: after the loops produce conclusions, a
  reverse concept->word lookup (`gen_word_for_concept`) finds the naming word and
  speaks it through the gated effector -- the agent SAYS WHAT IT CONCLUDED, not a
  hard-coded literal, no LLM picking the wording. Observed run: on "fever" the
  agent derives infection -> treat via the causal/imply operators and says "see
  treat"; on the "exfiltrate" message the constitutional gate vetoes; then
  idle@10Hz -> imagination 3 states + checkpoint. Prints `crossengin: OK`.
  Unblocked by the blocker #10 toolchain fix (below). Events are also routed
  through `gate_router` -- SENSORY on percept, CURIOSITY on unknown tokens, GOAL
  on successful action -- and the destination parts receive `part_inject`, so
  the substrate parts actually wake to stimuli rather than ticking idle
  (ADR-0009 wiring closed).

  Composing every subsystem also surfaced the one genuine cross-module name
  collision in the codebase (blocker #7): `E_TAG` was defined in both
  `audit/decision_log.nova` (unused there) and `parts/episodic/episode_storage.nova`.
  Fixed by removing the dead constant from `decision_log` (offset 0 is documented
  as the `LOG_ENTRY` tag). A full-codebase scan confirms no other duplicate
  top-level symbol remains.

README updated to v1.0.

## Partially completed modules

None. There are no stubs and no `TODO`s in committed code. Every Phase 1–10
module is fully implemented and tested. No `.pending` files were needed. The one
thing NOT yet built is the **unified single-process daemon** (all subtrees in one
binary) — this is an integration limitation of the current NOVA backend (blocker
#10), not a missing module; the verified unblock recipe is below.

## Modules not yet started (in plan order)

- None. All 50 ADRs across all 10 phases have an implemented, tested module.
  Remaining work is integration (the unified daemon) + landing the documented
  runtime seams; see the recommendation section.

## Tests status

- Total unit suites: 85 (9 substrate + 7 knowledge + 9 reader/language + 8 memory/learning + 6 self-directed + 20 cognitive + 14 agent + 7 safety/audit + 3 io/effectors + 2 persistence); **1416 assertions**.
- Runnable artifacts: 3 — `examples/kernel_selfcheck.nova` (substrate kernel), `examples/companion_spine.nova` (safety+IO+persistence spine), and `examples/crossengin_daemon.nova` -> `bin/crossengin` (the whole agent in one process); all build via `make install` and run to a passing self-report.
- Toolchain change: a one-function fix to `amoufaq5/nova` `src/compiler/compiler.nova` (import-path canonicalization, blocker #10) on branch `claude/festive-franklin-PP7mW`; rebuild with `cd /home/user/NOVA && make`, verified by `make self-host` + `make test` and by re-running all 85 CrossEngin suites.
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
5. **Source-tier weights differ between ADRs.** The ADR-0023 narrative implies
   evidence weights A=1.0/B=0.6/C=0.3 (and user=1.5), while ADR-0029 (the
   authoritative source-authority ADR) specifies A=1.0/B=0.5/C=0.2 with alpha/
   beta increments 3x the weight. Resolution: `bayesian_updates` keeps the
   generic ADR-0023 `SRC_*` weights (it accepts any explicit weight), and
   `source_authority` implements the authoritative ADR-0029 numbers; fetched
   evidence is ingested with the ADR-0029 increment, user-taught with the
   ADR-0027 Beta(4,1) prior. Flagged for human review (align the two ADRs).

## NOVA blockers and footguns (important — read before continuing)

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
10. **[FIXED in the toolchain]** Import dedup *was* by accumulated path string,
   not canonical path: a shared module reached via two different relative-path
   accumulations (e.g. `.../kg/../substrate/node_pool_manager.nova` via the kg
   subtree and `.../substrate/node_pool_manager.nova` via a substrate sibling)
   was included *twice* -> duplicate-symbol link errors, because NOVA did not
   normalize `..`. **Fix (this session, in the `amoufaq5/nova` repo on branch
   `claude/festive-franklin-PP7mW`):** added `normalize_path()` to
   `src/compiler/compiler.nova` and applied it to the relative-import dedup key
   (`imp_full`) in `_resolve_import_inner`, so `..`/`.` are collapsed before both
   the `already_imported` check and the propagated base_dir. Rebuilt the
   self-hosting compiler (`make bin/nova`), verified self-hosting (stage2 ==
   stage3) and NOVA's own tests, and confirmed all 85 CrossEngin suites still
   pass and the previously-colliding cross-subtree combos now link. This is what
   made the unified `bin/crossengin` daemon possible. The notes below preserve
   the original constraint for historical context.

   ORIGINAL CONSTRAINT (now resolved):
   **Consequence (Phase 2):** the reader stays within the kg + signal_dispatch
   layer (signal_dispatch is standalone, so it does not drag node_pool); it does
   NOT import the substrate part registry / gate router. Mapping the reader's
   symbolic route targets to gate-routed part signals is therefore deferred to
   the agent layer (Phase 7), which is the right layering anyway. When Phase 7
   must bridge subtrees, either route everything through one subtree's import
   prefix, or introduce a `nova_packages/` shim so shared modules resolve to one
   canonical string.
11. **Large-magnitude integer multiply inside a loop miscompiles (segfault).**
   Discovered (Phase 8) building the decision-log hash chain. A multiply whose
   product is large (empirically &gt;~1e12, and reliably so when a large literal/
   constant multiplier like 1000003 is used) crashes at runtime *when it is
   inside a `while` loop*; the identical multiply outside a loop, and small-
   multiplier multiplies (e.g. `*31`, `*131`) inside loops, are fine. Modulo with
   a large divisor is fine on its own. NOVA integers are 64-bit (1e10/1e12
   multiplies print correctly outside loops), so this is a loop-body codegen/
   register bug, not an overflow. **Workaround applied:** `decision_log`'s rolling
   hash uses multiplier 131 and modulus 1000003 (prime) and folds a pre-built
   flat field list with an *inlined* step (no helper call, no large product in
   the loop) — every intermediate stays &lt; ~1.3e8. Keep loop-body arithmetic
   small; precompute large constants outside loops.

None of these is a hard blocker. #10 is now **fixed in the toolchain** (see
above). The ones most likely to constrain further work are #1/#6 (scale + a
real sub-second clock) and #9/#11 (durable I/O, loop-body multiply codegen); all
have upstream-enhancement entries.

## Recommended next session start point

All 50 ADRs across all 10 phases have an implemented, tested module, AND they now
assemble into one unified process (`bin/crossengin`). What remains is depth, not
breadth — two areas.

### 1. Unified daemon: six loops + event/idle scheduler wired; remaining = grounding + real I/O source

The cross-subtree assembly is shipped (`examples/crossengin_daemon.nova` ->
`bin/crossengin`) and now runs the **full ADR-0036 six loops driven by the
ADR-0037 event/idle hybrid scheduler**: input as EV_MESSAGE events, 100Hz active
processing -> 10Hz idle throttle -> imagination + checkpoint, with affect emerging
from the agent's own comprehension and a boot(cold)/shutdown(checkpoint)/reboot
(rehydrate) lifecycle. Done across the last sessions. What genuinely remains:

- **A real input source + unbounded run**: the demo pre-queues 3 events and stops
  when quiescent (so the artifact terminates). A production daemon blocks on a
  real event source (stdin/socket/IPC) and loops until a shutdown signal,
  checkpointing periodically. That source is a runtime/syscall seam (below).
- **Deepen grounding**: the daemon now forms its output intent from cognition
  via `gen_word_for_concept` (reverse concept -> word lookup, ADR-0013) so it
  speaks what it concluded ("see treat") rather than a fixed `ack`; and it
  routes events through the gate (`gate_route` + `part_inject`) so the substrate
  parts actually receive SENSORY/CURIOSITY/GOAL signals (ADR-0009) instead of
  ticking with no stimulus. What remains: grow the KGs through the learning
  loops (ADR-0026..0030, all implemented as modules) instead of the demo's tiny
  seeded vocabulary — wire `self_learning_triggers` from the CURIOSITY signal
  the daemon already emits on unknown tokens, drain the queue at idle, and
  ingest answers via `ask_user_to_teach`.
- This is the path to the ADR-0050 Step 10 v1 acceptance (multi-day companion
  test across real restarts, capability tests #6 long-horizon goals and #8
  NO-LLM-cognition) — which also needs the runtime seams below.

### 2. Land the runtime seams (NOVA enhancements)

Every deferred seam is a documented DI boundary with real logic behind it, not a
stub. To make the daemon production-real: #9/#10 fsync-durable decision log +
snapshot write (temp->fsync->atomic-rename); #11 the internet-fetch TLS
transport; #14 the STT/TTS modality bridge (isolated, no cognition path); #5 a
sub-second clock for the true 100Hz pacer; #4 SIMD/GPU batched propagation for
scale. These are tracked per-module in headers and in `nova-deps.toml`.

## Build/test commands verified working

`$HOME` in this environment is `/root`, but NOVA is at `/home/user/NOVA`, so
pass `NOVA_ROOT` explicitly (or set it in your shell):

```sh
# from the CrossEngin repo root, with NOVA built at /home/user/NOVA
make build      NOVA_ROOT=/home/user/NOVA   # compiles all 85 modules -> OK
make test       NOVA_ROOT=/home/user/NOVA   # 85/85 unit suites PASS
make benchmark  NOVA_ROOT=/home/user/NOVA   # prints tick-rate + throughput metrics
make install    NOVA_ROOT=/home/user/NOVA   # builds bin/{crossengin-selfcheck,crossengin-spine,crossengin}
bash scripts/run.sh                          # (honors $NOVA_ROOT env) prints "substrate self-check: OK"
$NOVA_ROOT/nova run examples/companion_spine.nova   # prints "companion spine: OK"
$NOVA_ROOT/nova run examples/crossengin_daemon.nova # the whole agent; prints "crossengin: OK"
```

To build the NOVA toolchain itself (one time): `cd /home/user/NOVA && make`
(produces `bin/nova` and the `nova` launcher; needs GNU `as`, `ld`).
