# Coverage ledger

Every tracked file in both repositories (2,009 = 597 NOVA + 1,412 CrossEngin-demo, per `git ls-files`) appears in one of the nine section tables below; a script cross-check found 0 tracked paths missing. Paths are prefixed `NOVA/` or `CE/`.

**Status meanings.** *reviewed* = read in full. *skimmed* = header, function inventory, targeted greps, and (where noted) its test executed — used for long, repetitive, generated or vendored files; the reason is given per section or per row. Skimmed files were not read line by line, so defects inside them may be missed.

## Summary

| Section | Scope | Rows | reviewed | skimmed |
|---|---|---:|---:|---:|
| nova_compiler | NOVA compiler, bootstrap seed, pkg, stdlib, tooling, storage, build scripts | 30 | 16 | 14 |
| nova_msc | NOVA src/core, mind, agent, cognitive, runtime, examples | 146 | 57 | 89 |
| nova_tools_tests_docs | NOVA tools/, tests/, docs/, root docs, packaging, CI | 421 | 21 | 400 |
| ce_core | CE substrate, parts, gates, scheduler, kg, mind, learning, seed, sim, preference, perception | 144 | 54 | 90 |
| ce_surface | CE language, reader, nl, agent(s), chat, skills, capsules, persona, session, factory, editions, data, bench, util, audit, ingest, sandbox, examples | 143 | 32 | 111 |
| ce_security | CE federation, safety, net, persistence, infra, web, network scripts, licence | 125 | 64 | 61 |
| ce_io | CE src/io, media audit docs, media scripts | 80 | 40 | 40 |
| ce_tests | CE tests, bench, data, Makefile, CI, remaining scripts | 675 | 93 | 582 |
| ce_docs | CE docs/ and root markdown | 245 | 47 | 198 |
| **Total rows** | (some files appear in two sections) | 2009 | 424 | 1585 |

Not verifiable in this audit: anything requiring Ollama, Whisper, Vosk, OpenBLAS, llama.cpp, a GPU, Windows, macOS or ARM hardware; live GitHub CI status; repository visibility; authorship of the knowledge packs.

---

## Section: nova_compiler


Reviewer: `nova_compiler`. Scope: NOVA `src/compiler/*`, `src/pkg/*`, `src/stdlib/*`, `src/tooling/*`, `src/storage/*`, `src/version.nova`, `boot/*`, `Makefile`, `build_compiler.sh`, `nova`, `scripts/*`, `VERSION`.

**Row count: 30 files** — matches `git ls-files src/compiler src/pkg src/stdlib src/tooling src/storage src/version.nova boot Makefile build_compiler.sh nova scripts VERSION | wc -l` = 30 (145,138 lines total, of which 106,045 are the generated seed `boot/nova_boot.s`).

"reviewed" = read in full or read all load-bearing parts and exercised by execution. "skimmed" = structure, function inventory and targeted sections read; reason given.

| path | status | LOC | actual status | what it really does |
|---|---|---|---|---|
| NOVA/src/compiler/ast.nova | reviewed | 795 | Working | 71 constructor/accessor functions; every AST node is a plain list `[tag, field..., line]`. Includes `AST_MIND/SOUL/SYSTEM/FLOW` tags. |
| NOVA/src/compiler/lexer.nova | reviewed | 1000 | Working (no diagnostics) | Hand-written byte-at-a-time tokenizer. Emits no errors at all: unknown characters are skipped (`:985`), unterminated strings and overflowing integer literals are accepted silently. |
| NOVA/src/compiler/parser.nova | skimmed (5.7k lines; read error path, type-check pass, program driver, pattern/generic handling; rest inventoried by function) | 5768 | Working | Recursive-descent parser producing list-ASTs; desugars match/patterns/struct-init in the parser; stops at first error (`par_error` → `exit`). Contains a "type-check" pass (`tc_*`, `:4827-5743`) that only prints warnings for literal arguments. |
| NOVA/src/compiler/ir.nova | reviewed | 486 | Dead | Defines 49 IR opcodes, emit helpers and a live-range calculator. Compiled into the binary but never called by the compile path. |
| NOVA/src/compiler/regalloc.nova | reviewed | 197 | Dead | Linear-scan register allocator over IR live ranges. Never called. |
| NOVA/src/compiler/lower_x64.nova | skimmed (dead code; read entry points) | 684 | Dead | IR → x86-64 lowering. Compiled into the binary, never called (`lx_init`/`lx_lower_function` have no caller outside the file). |
| NOVA/src/compiler/lower_arm64.nova | skimmed (dead code; read header + function list) | 772 | Dead | IR → AArch64 lowering. Not in `COMPILER_SRC`, no caller anywhere; only "reachable" as an importable std package name. `--target=arm64` uses a separate AST walker in codegen.nova. |
| NOVA/src/compiler/codegen.nova | skimmed (24k lines; read driver, expr/stmt core, identifier resolution, optimizer entry, classifier/arith/alloc/index/map/float/exit runtime, MSC desugaring, ARM header; the 8.3k-line `gen_runtime` and WASM runtime inventoried by label) | 24119 | Partial | The real compiler back end. AST-walking stack-machine emitter of GAS Intel-syntax text for 6 targets, plus the whole runtime library written as ~7,500 `out("asm line")` calls. Linux x86-64 works with significant bugs (see findings); other targets partial/stub. |
| NOVA/src/compiler/compiler.nova | reviewed | 816 | Working (wrong exit codes) | CLI driver: arg parsing, textual import splicing (imports only honoured at top of file), then `tokenize → parse_program → fold → DCE → gen_program → write_file`. Exits 1 on success paths that call `exit(0)`. |
| NOVA/src/pkg/pkg.nova | reviewed | 520 | Partial | Edits a `nova.pkg` key=value manifest; `install` copies std files from `src/runtime` into `nova_packages/`. No registry, no versions, no remote fetch ("remote packages not yet supported", `:425`). Also holds the hard-coded list of 62 std package names. |
| NOVA/src/stdlib/float.nova | reviewed + executed | 180 | Partial (broken at HEAD) | 17 small float helpers (clamp, lerp, sign, distance…) over builtin `f_*` functions. Not on the import path (must be `cat`-ed). All four functions I executed returned 0.0. |
| NOVA/src/stdlib/list.nova | reviewed + executed | 197 | Partial (broken at HEAD) | 13 list helpers; most are one-line wrappers over builtins (`map_list`, `filter`, `sum`, `list_slice`, `reduce`). Not on the import path. Executed: `sum` gives 12 for [1,2,3,4], `list_take(l,2)` returns 3 elements, because the builtins underneath are wrong. |
| NOVA/src/storage/wal.nova | reviewed + executed | 274 | Partial (test fails at HEAD) | Append-only log file: 20-byte header (magic, seq, len, CRC-32) + payload ≤4096 bytes; sequential reader stops at first bad record; truncate helper. Real code; its test fails at HEAD and is skipped by the runner. |
| NOVA/src/tooling/visualizer.nova | skimmed (library outside compiler path; read function list + export) | 342 | Working (per lead's suite: PASS) | Records node/synapse/signal events in lists; writes an HTML file with inline SVG circles and lines. |
| NOVA/src/tooling/time_machine.nova | skimmed (read replay/record functions) | 328 | Working; name overstates | "Time-travel debugger" = a capped list of snapshot copies indexed by tick. "Replay" copies stored snapshots and overwrites fields; nothing is re-executed. |
| NOVA/src/tooling/kg_visualizer.nova | skimmed | 521 | Partial (its test fails to compile at HEAD) | BFS subgraph extraction over a knowledge-graph list structure; exports HTML/SVG and Graphviz DOT text. |
| NOVA/src/tooling/profiler.nova | skimmed (read tick/section/export functions) | 280 | Working; name overstates | Counts manually-advanced integer "ticks" between `start_section`/`end_section` calls and event counters. No clock, no sampling. "Flamegraph export" writes `name total` lines. |
| NOVA/src/version.nova | reviewed | 14 | Dead | Returns/prints "0.2.0". Referenced by nothing. Disagrees with `VERSION` (0.1.0) and the launcher (0.9.0). |
| NOVA/boot/nova_boot.s | skimmed (generated; verified provenance, symbol set, old classifier) | 106045 | Working (stale seed) | Compiler-emitted assembly of an older compiler, committed as the bootstrap seed. Last changed 2026-05-31; 304 functions vs 479 in today's source. |
| NOVA/boot/Makefile | reviewed | 15 | Working | `as` + `ld` on nova_boot.s. |
| NOVA/Makefile | reviewed | 706 | Working | Three-step bootstrap (seed → stage1 → stage2 = bin/nova), self-host diff, cross targets, smoke targets (most skip silently when toolchains are missing), packaging wrappers. Uses fixed `/tmp/nova_*` paths. |
| NOVA/build_compiler.sh | reviewed | 15 | Dead / stale | Concatenates only 5 of the 9 compiler sources and calls the seed an "interpreter". Superseded by the Makefile. |
| NOVA/nova | reviewed | 107 | Working (minor defects) | Bash launcher: `run`/`build`/`pkg`/`test`/`self-host`/`version`. Hard-codes "v0.9.0"; hides assembler errors; leaks the compiler's "Compiled:" line into program stdout. |
| NOVA/VERSION | reviewed | 1 | Doc | `0.1.0`. |
| NOVA/scripts/build-deb.sh | skimmed (packaging script; read header, version handling, destructive commands) | 149 | Working (unexecuted) | Stages `bin/nova` and runs `dpkg-deb --build`; writes a recipe file instead when the tool is missing. |
| NOVA/scripts/build-msi.sh | skimmed | 135 | Partial (unexecuted) | WiX candle/light wrapper; "recipe-only mode" when WiX is absent. |
| NOVA/scripts/build-pkg.sh | skimmed | 163 | Partial (unexecuted) | macOS pkgbuild/productbuild wrapper; recipe-only on Linux. Placeholder team id `XXXXXXXXXX` (`:94`). |
| NOVA/scripts/sign.sh | skimmed | 115 | Partial (unexecuted) | Wraps gpg / productsign+notarytool / signtool; reads credentials from environment variables; skips when unset. No secrets committed. |
| NOVA/scripts/wgpu_dispatch/Cargo.toml | reviewed | 33 | Working (unexecuted) | Rust crate manifest: depends on `wgpu 0.20`, `pollster`, `bytemuck`. |
| NOVA/scripts/wgpu_dispatch/src/main.rs | skimmed (read header + config parsing) | 361 | Working (unexecuted) | Rust program that runs a WGSL vector-add shader via wgpu and compares with a CPU loop. This Rust sidecar is the whole of Nova's "GPU" support; Nova only writes the shader text and a config file. |

TODO/FIXME/HACK/XXX inventory in scope (excluding the generated seed): **1** hit (`scripts/build-pkg.sh:94`, a placeholder team id). The code base records known defects as prose comments ("Bug #13", "UPSTREAM_NOVA_BUGS §17", "pre-fix") instead: 19 such references in codegen.nova.


---

## Section: nova_msc


Row count: **146** = `git ls-files src/core src/mind src/agent src/cognitive src/runtime examples | wc -l` = 146 (core 19, mind 5, agent 4, cognitive 10, runtime 40 incl. llm_bridge.c, examples 68). The only C/header file under src is `src/runtime/llm_bridge.c`. HEAD = 663bf0e.

"skimmed" = header, function list and risk greps read, plus executed via its test/demo where one exists; bodies not read line by line (generic stdlib or demo code). All 66 `.nova` examples were executed with `timeout 20 $S/NOVA/nova run`; "as shipped" refers to that run. Paths are relative to `NOVA/`.

| path | status | LOC | actual status | what it really does |
|---|---|---|---|---|
| examples/active_inference_demo.nova | skimmed | 82 | Partial | No imports -> "undeclared callee: ai_new" as shipped; with module concatenated it hangs and is killed (calls ai_new(3), API needs 3 args). |
| examples/associative_demo.nova | skimmed | 61 | Partial | Hopfield demo; fails as shipped (no imports); with deps still fails: "undeclared callee: list_to_str". |
| examples/atom_lifecycle_demo.nova | skimmed | 97 | Partial | Fails as shipped (no imports); runs to completion when concatenated with the module; output computed. |
| examples/audio_demo.nova | skimmed | 109 | Partial | Fails as shipped; concatenated: segfault after "From Samples". |
| examples/basic_mind.nova | reviewed | 63 | Fake | Aspirational `mind Agent { memory working(capacity: 7) ... }` syntax with `--` comments; does not parse ("error[line 1]: unexpected :"). Dates from first commits; cited by docs/TOUR.md. |
| examples/bench_dot_i32.nova | skimmed | 117 | Partial | Benchmark; fails: "undeclared callee: sys_open". |
| examples/bench_int_safe.nova | skimmed | 168 | Partial | Benchmark; fails: "undeclared callee: sys_open". |
| examples/bench_secure_random.nova | skimmed | 113 | Partial | Runs, prints "WARMUP FAILED: secure_random returned wrong byte count", rc=3. |
| examples/bench_simd_sad.nova | skimmed | 132 | Partial | Benchmark; fails: "undeclared callee: sys_open". |
| examples/binary_search.nova | skimmed | 68 | Working | Language demo; runs, computed. |
| examples/brainfuck.nova | skimmed | 83 | Working | Brainfuck interpreter; runs, prints "Hi". |
| examples/calculator.nova | skimmed | 62 | Working | Arithmetic demo; runs, computed. |
| examples/causal_library_demo.nova | skimmed | 68 | Partial | Fails as shipped; concatenated: segfault while printing search results. |
| examples/concurrency.nova | skimmed | 188 | Partial | Generators print Fibonacci then SEGFAULT (rc 139). |
| examples/federation_demo.nova | skimmed | 84 | Partial | Fails as shipped; concatenated: segfault after node setup. |
| examples/ffi_demo.nova | skimmed | 69 | Working | extern fn + inline asm rdtsc; runs. |
| examples/ffi_demo_libc.nova | skimmed | 59 | Partial | Needs --link-libc build; under `nova run`: "undeclared callee: ffi_open". |
| examples/fibonacci.nova | skimmed | 23 | Working | Runs, computed. |
| examples/file_wasm.nova | skimmed | 52 | Working | File round-trip smoke (run natively here): OK. |
| examples/fizzbuzz.nova | skimmed | 24 | Working | Runs. |
| examples/float_demo.nova | skimmed | 81 | Working | Runs to completion (values not individually verified). |
| examples/flow_operators.nova | skimmed | 90 | Partial | `~>`/`=>>` signal-flow operators; as shipped "undeclared callee: scheduler_get_soul"; with soul+scheduler added: "Runtime error: index out of bounds: 1" at the broadcast step. |
| examples/full_mind.nova | reviewed | 219 | Working | Self-contained 219-line toy that re-implements moment/memory/knowledge inline (does not use src/core): 5-fact lookup table, counters; output computed from that table. |
| examples/game_of_life.nova | skimmed | 116 | Working | Runs, computed. |
| examples/gpu_vector_add.nova | skimmed | 82 | Partial | Only writes a WGSL shader + cfg file and prints "next step: run wgpu_dispatch"; performs no GPU computation itself. |
| examples/hdc_demo.nova | skimmed | 77 | Partial | Fails as shipped (no imports); runs to completion when concatenated; computed. |
| examples/hello.nova | skimmed | 8 | Working | Hello world. |
| examples/hello_arm64.nova | skimmed | 32 | Working | Target smoke test; runs natively. |
| examples/hello_arm64_android_reference.s | skimmed | 39 | Doc | Hand-written reference assembly (not Nova). |
| examples/hello_arm64_ios_reference.s | skimmed | 39 | Doc | Hand-written reference assembly (not Nova). |
| examples/hello_dwarf.nova | skimmed | 40 | Working | DWARF smoke; runs. |
| examples/hello_macos.nova | skimmed | 49 | Working | Target smoke; runs natively. |
| examples/hello_secure_random_wasm.nova | skimmed | 27 | Partial | Runs natively but prints "secure_random WASM: FAIL". |
| examples/hello_secure_random_winarm64.nova | skimmed | 45 | Working | Runs natively, prints nonzero return. |
| examples/hello_wasm.nova | skimmed | 27 | Working | Target smoke; runs natively. |
| examples/hello_win32.nova | skimmed | 51 | Working | Target smoke; runs natively. |
| examples/higher_order.nova | reviewed | 50 | Partial | Runs but prints WRONG results: "Add 3+4 = 0", "Mul 3*4 = 0". |
| examples/json_config.nova | skimmed | 101 | Working | JSON parse/serialize demo; runs. |
| examples/kg_visualizer_demo.nova | skimmed | 123 | Partial | Fails as shipped (no imports); runs when concatenated with db+embed+knowledge+kg_visualizer. |
| examples/knowledge_demo.nova | reviewed | 235 | Partial | Runs (13 imports). Embeddings are hand-typed 6-int lists; KG queries computed; db saves 4 entries and reports "Reloaded 3". |
| examples/linked_list.nova | skimmed | 96 | Working | Runs, computed. |
| examples/mind_declaration.nova | skimmed | 103 | Partial | `mind Nova { nodes {...} channels {...} }` syntax; as shipped "undeclared callee: soul_bias"; runs when soul.nova is added. |
| examples/moment_signal.nova | reviewed | 64 | Fake | Aspirational `moment Greeting { what_happened: ... felt: warmth 0.7 }` / `node Analyst : reasoner` syntax; does not parse ("expected : but got {"). Never implemented. |
| examples/node_pool_demo.nova | skimmed | 88 | Partial | Fails as shipped; concatenated: segfault at pool describe. |
| examples/pipe_win32.nova | skimmed | 43 | Partial | Windows-only; natively prints "recv FAIL n=-9". |
| examples/predictive_coding_demo.nova | skimmed | 70 | Partial | Fails as shipped; concatenated: segfault after printing layer. |
| examples/profiler_demo.nova | skimmed | 80 | Partial | Fails as shipped; concatenated: segfault near end. |
| examples/resonance_demo.nova | skimmed | 88 | Partial | Fails as shipped; runs to completion when concatenated; computed. |
| examples/sdr_demo.nova | skimmed | 88 | Partial | Fails as shipped; concatenated: segfault at set operations. |
| examples/security_demo.nova | skimmed | 139 | Working | Runs (14 imports): sha256, validators, sbuf; computed. |
| examples/self_model_demo.nova | skimmed | 82 | Partial | Fails as shipped; concatenated: segfault at trend analysis. |
| examples/showcase.nova | skimmed | 179 | Working | Language feature tour; runs. |
| examples/sieve.nova | skimmed | 55 | Working | Runs, 25 primes. |
| examples/signal_processing.nova | reviewed | 155 | Partial | Self-contained MSC toy; INFINITE LOOP printing "[Perceiver] Received: user says hello" (514 MB of output in 20 s). |
| examples/skill_demo.nova | skimmed | 75 | Partial | Fails as shipped; concatenated: segfault at describe. |
| examples/sock_win32.nova | skimmed | 103 | Partial | Windows-only; natively segfaults after recv. |
| examples/soul_demo.nova | skimmed | 194 | Working | `soul` declaration syntax; runs; drive/feeling numbers computed by soul.nova rules. |
| examples/stream_demo.nova | skimmed | 184 | Working | Signal stream + scheduler demo; runs. |
| examples/string_utils.nova | skimmed | 89 | Partial | Exits rc=1 with no output. |
| examples/system_demo.nova | skimmed | 124 | Working | Multi-mind registry demo; runs; prints counts of registered records. |
| examples/system_syntax_demo.nova | skimmed | 134 | Working | `system` declaration syntax; runs. |
| examples/tcp_echo_server.nova | skimmed | 44 | Working | Binds :8080 and blocks in accept (timed out as expected for a server). |
| examples/time_machine_demo.nova | skimmed | 106 | Partial | Fails as shipped; runs when concatenated with tooling/time_machine. |
| examples/timeseries_demo.nova | skimmed | 91 | Partial | Fails as shipped; runs when concatenated; computed. |
| examples/tower_of_hanoi.nova | skimmed | 26 | Working | Runs. |
| examples/visualizer_demo.nova | skimmed | 84 | Partial | Fails as shipped; runs when concatenated with tooling/visualizer. |
| examples/wasi_file_roundtrip.nova | skimmed | 124 | Partial | WASI-only; natively "FAIL: wasi_close" rc=3. |
| examples/win32_argv_envp.nova | skimmed | 48 | Working | argv/envp smoke; runs natively. |
| src/agent/agent.nova | reviewed | 952 | Partial | REPL chatbot: classify_input = ~35 ordered substring rules -> category; pipeline_reason = per-category canned sentence templates filled from the triple store; "teaching" inserts (X,is_a/has,Y). Does not use nodes/channels/paths/scheduler. `make agent` FAILS at HEAD (missing files in concat list); runs once scheduler/db/safety/goal/imagination are added. |
| src/agent/cognitive_llm.nova | reviewed | 331 | Fake | Named "Cognitive LLM pipeline" but never calls an LLM: cognitive_generate(text) returns its own input wrapped with a keyword-derived confidence (50 +-15 for "maybe"/"definitely"...). cognitive_embed_text = 64-dim hashed bag of words. Its test fails at HEAD (float_cmp). |
| src/agent/preprocess.nova | reviewed | 279 | Dead | Text -> sentences -> (subject, rel, object) by splitting on " is "/" has "/... (7 patterns), stop-word stripping, dedup. No callers, no tests. |
| src/agent/rag.nova | reviewed | 589 | Dead | TF-IDF vectors over growing vocabulary in float tensors, cosine top-k, builds a "Context:...Query:" prompt string. Never sent to any model. No callers, no tests; ranking depends on broken float_cmp. |
| src/cognitive/active_inference.nova | reviewed | 357 | Working | Discrete states with Beta pseudo-counts and likelihood table (x1000 ints); ai_observe adds lik/10 to alpha or (1000-lik)/10 to beta per state; "free energy" via crude integer log; action = argmin expected FE. Passes its test; its demo hangs/killed (API mismatch ai_new(3)). |
| src/cognitive/associative.nova | reviewed | 238 | Partial | Classical Hopfield net: W[i][j] += s_i*s_j (Hebbian outer product) in a float tensor, sign-update recall. Test fails to compile in harness (mem_free undeclared); passes 10/10 with a 3-line mem_free stub. |
| src/cognitive/atom_lifecycle.nova | reviewed | 310 | Working | Counts occurrences of sorted co-activation index sets by hash; "birth" when count>=threshold; "death" when decayed activity stays below threshold N ticks. Counter-based. Passes test; demo runs. |
| src/cognitive/causal_library.nova | reviewed | 692 | Working | 51 hand-written (precondition, action, effect, strength) rows x 19 adverb modifiers ("rapidly","slowly",...) = "1000+ causal patterns"; keyword substring search. Passes test (count>=1000 is satisfied by the multiplication); demo segfaults. |
| src/cognitive/hdc.nova | reviewed | 146 | Working | Bipolar +-1 hypervectors as f64 blocks: LCG random vector, bind = elementwise multiply, bundle = sum+sign, permute = rotate, cosine. Standard VSA. Passes test; demo runs. |
| src/cognitive/predictive_coding.nova | reviewed | 339 | Working | Stack of linear layers (int x1000 weights, deterministic init); error = actual - prediction; w += lr*err*input (delta rule), clamp +-5000. A real, tiny gradient-style learner. Passes test; demo segfaults. |
| src/cognitive/resonance.nova | reviewed | 251 | Working | Per-signal-type preference vector; activation = sum(dot(pref, pattern)*magnitude*weight) through relu/sigmoid-ish; update: pref += lr*(observed - pref) (exponential moving average). Passes test; demo runs. |
| src/cognitive/sdr.nova | reviewed | 266 | Working | Sparse binary vectors as sorted index lists: overlap, union, intersection, scalar bucket encoder, LCG random. Passes test; demo segfaults mid-way. |
| src/cognitive/self_model.nova | reviewed | 306 | Working | Record of last emotion/focus/confidence + goal list + history ring; "describe yourself" string templating from soul OCEAN ints; trend = compare first/last history halves. Passes test; demo segfaults. |
| src/cognitive/skill.nova | reviewed | 245 | Working | Skill record: trigger substrings, action strings, preconditions, success/attempt counters (success_rate = s*1000/n); applicability = keyword overlap score. Passes test; demo segfaults at describe. |
| src/core/belief.nova | reviewed | 119 | Working | Beta(alpha,beta) pseudo-count pair, fixed-point x1000: mean=a/(a+b), add weight to a or b, decay toward floor. Passes test_belief. Used only by its test. |
| src/core/channel.nova | reviewed | 226 | Working | Channel = record {source name, list of dest nodes, type, msg counter}; route = append signal to each dest inbox; filtered = salience threshold; weighted = temporarily scale priority. |
| src/core/concept.nova | reviewed | 510 | Working | Global list of named concepts with single parent + property list (is-a tree walk, inherited property lookup, depth-based Wu-Palmer-like similarity), schema required-field validation, multi-facet embedding blend. Compiles/passes only if db.nova is added to the harness concat list. |
| src/core/gates.nova | reviewed | 356 | Dead | Rule list (condition,value)->destinations with integer weight; gate_learn adds lr/10 to matching rules containing the correct dest, subtracts lr/20 otherwise. Does NOT parse at HEAD (variable named `match`, now a keyword, line 194). No users, no tests. |
| src/core/goal.nova | reviewed | 249 | Working | Goal record {name, priority 0-100, deadline, status, progress, subgoals}; "drives" are if-threshold rules that create named goals; goal_evaluate_action = keyword substring scoring. Passes test_goal. |
| src/core/imagination.nova | reviewed | 342 | Partial | 10 hard-coded keyword->consequence rows ("break"->"object broken", valence -30). imagine_* = substring match over that table + random() for likelihood; "dream" = random pairing of episode strings. test_imagination SEGFAULTS in imagine_best_scenario at HEAD. |
| src/core/knowledge.nova | reviewed | 563 | Partial | In-memory knowledge graph: entity list (name, optional int embedding, attrs) + triple list with weights; linear-scan queries, brute-force cosine nearest (O(E^2) sort), BFS path, save/load via db.nova. Works in memory; persistence reload unreliable at HEAD (test_knowledge fails/segfaults). |
| src/core/moment.nova | reviewed | 275 | Working | Moment = 9-slot list [tag, what(string), who, valence, arousal, consequence, salience, urgency(const 50), time(counter)]; Entity, Emotion(VAD ints), Consequence records; intensity=(/v-50/+a)/2; emotion_drift = linear interpolation. |
| src/core/node.nova | reviewed | 831 | Working | Node = {name, type(1..6), state map, inbox, outbox, config}; node_process dispatches each inbox signal to one of six hand-written handlers (perceiver/knower/rememberer/reasoner/feeler/actor) = keyword match, list lookup, weighted integer sums. Requires soul.nova+scheduler.nova (actor calls scheduler_get_soul). |
| src/core/parts.nova | reviewed | 262 | Dead | Named groups of node names + registry + in/out counters. Bookkeeping only. No users, no tests (smoke-probed OK). |
| src/core/path.nova | reviewed | 295 | Working | Path = ordered list of nodes; path_execute feeds a signal through each node in turn (receive, process, take first output); reflex variant skips middle nodes when urgency>80. Covered by test_m7_core. |
| src/core/reader.nova | reviewed | 431 | Dead | "5-stage reader": split text into words, look each up as KG entity name, bias by recent-context list, spread integer activation over KG edges, coherence = fraction of activated entities that are connected, reader_learn adds a KG relation if absent. No users, no tests (smoke-probed OK). |
| src/core/safety.nova | reviewed | 294 | Working | Global permission tier int, action-name substring -> reversibility class table, ring-buffer decision log, override list, rate limiter by time(); safety_check_content only checks 0<len<=10000. Passes test_safety_audit. |
| src/core/signal.nova | reviewed | 493 | Working | Signal = 8-slot list [tag, type(1..22), moment, origin, dest, priority, trace list, meta map]; 22 constructors differing only in type code and default priority; O(n) sorted-insert priority queue; pull stream wrapper. |
| src/core/signal_flow.nova | reviewed | 322 | Dead | Allow/deny table for (source,target,signal type, priority range) with violation log. No users, no tests (smoke-probed OK). |
| src/core/similarity.nova | reviewed | 276 | Working | similarity_score = fixed weighted sum 0.35 content + 0.20 entity + 0.15 emotion + 0.15 recency + 0.10 frequency + 0.05 consequence (ints 0-100); Jaccard on string lists; L1 emotion distance; linear recency; BFS spread_activation with geometric decay. |
| src/core/soul.nova | reviewed | 796 | Working | Soul = name + key/value lists (identity, values, drives 0-100, feelings 0-100) + phase table + reaction table + interaction counter (+OCEAN ints, "constitution" forbidden-substring list, themes, loyalties). soul_tick: counters++, +-warmth/alertness by (v-50)/5, fire reaction by valence class, feelings drift 1/tick to 50. soul_preprocess = ~25 substring keyword rules. Passes test_soul. |
| src/core/synapse.nova | reviewed | 259 | Dead | Edge list (source,target,weight 0-1000, fire count); tick subtracts decay and prunes below threshold; "hebbian_update" = add correlation*growth/1000 (caller must supply the correlation). No users, no tests (smoke-probed OK). |
| src/core/system.nova | reviewed | 293 | Working | "Multi-mind system" = named groups of nodes/channels + bridge records + shared db handle; system_init registers everything with the one global scheduler. Passes test_system; system_demo runs. |
| src/mind/academic.nova | reviewed | 562 | Working | Global triple store (subject, relation, object) in a list + relation->relation rules with confidence; query = linear scan; derive = bounded recursive rule chaining with confidence product; contradiction check for "exclusive" relations; save/load via db. |
| src/mind/emotion.nova | reviewed | 412 | Working | Three global ints (valence, arousal, dominance 0-100) moved toward each moment by weight=salience/2 %; decay to baseline; mood = slow moving average; emotion_describe maps ranges to words (calm/content/...). History ring for trend. |
| src/mind/experiential.nova | reviewed | 495 | Working | Per-trigger-string pattern record with running mean valence and count; at count>=threshold promoted to a "tendency" with strength=count*10 and bias approach/avoid by mean>=50. Counter-based. |
| src/mind/memory.nova | reviewed | 504 | Working | Global episode list (moment, importance, access_count, last_access, tags, links) + 7-slot working memory; recall_similar = exact-string content match*3 + who*2 + emotion*2 + recency + frequency, O(E^2) selection sort; consolidate merges adjacent same-text episodes; decay drops low importance. |
| src/mind/reasoning.nova | reviewed | 827 | Working | Rule list condition->consequence(conf) with exact string match; deduce=recursive forward chain (conf product), abduce=reverse, "analogize"=content-word overlap with past episode strings, causal links with observation counter (+5 strength per repeat). Strategy chosen by signal type code. |
| src/runtime/alloc.nova | skimmed | 134 | Partial | mmap-backed bump arena + simple heap wrappers via inline-asm syscalls. test_runtime fails at HEAD with "sys_mmap failed". |
| src/runtime/audio.nova | skimmed | 497 | Working | Integer (x1000) sin/cos/log approximations, naive DFT-based STFT, mel filterbank MFCC, energy-threshold VAD. Passes test_audio; demo segfaults. |
| src/runtime/blas.nova | reviewed | 81 | Dead | dlopen("libopenblas.so"/"libblas.so") and call cblas_dgemm via hand-written asm; optional hook from tensor_matmul. Needs --link-libc. No callers/tests; not exercised. |
| src/runtime/chan.nova | skimmed | 105 | Working | In-memory bounded FIFO with send/recv counters (no blocking, single address space). Passes test_channel. |
| src/runtime/confidence.nova | skimmed | 89 | Partial | [value, float] pair helpers (merge=product etc.). test_confidence passes; any float_cmp(...)>0 path is wrong at HEAD. |
| src/runtime/coroutine.nova | skimmed | 191 | Partial | Generators/task groups/pipelines over coro_* builtins (cooperative). test_coroutine passes; test_coro_advanced and examples/concurrency segfault. |
| src/runtime/crypto.nova | reviewed | 223 | Partial | Pure-Nova SHA-256 (passes test_security), plus xor_encrypt (repeating-key XOR presented as encryption) and djb2 checksum. |
| src/runtime/csv.nova | skimmed | 153 | Working | Comma/newline splitter with RFC-4180 quote handling. Passes test_csv. |
| src/runtime/db.nova | reviewed | 212 | Partial | Whole-file key=value text store; O(n) linear key scan; no escaping of "=" or newline; rewrite whole file on save. Save works; reload loses records at HEAD (probe: 3 saved, 0 reloaded; knowledge_demo: 4 saved, 3 reloaded). |
| src/runtime/effects.nova | skimmed | 255 | Dead | Named effect-handler table + choice-point stack for backtracking search. Calls list_get which is not defined in the default build ("undeclared callee: list_get"). No users/tests. |
| src/runtime/embed.nova | reviewed | 292 | Working | Fixed-dimension integer vectors: dot, integer-sqrt cosine (0-100), L1/L2, lerp, centroid, serialize. No text->vector function: all vectors are supplied by the caller (hand-typed in demos). |
| src/runtime/embedding.nova | reviewed | 342 | Partial | BM25/TF-IDF bag-of-words + character-trigram counts over a growing vocabulary -> float tensor; "Tier 2 neural via Python" is a comment only. Test only prints (cannot fail on similarity); printed sim values are 0.000000 for both related and unrelated pairs. |
| src/runtime/federation.nova | reviewed | 218 | Partial | Single-process simulation: "nodes" are lists with inbox/outbox, trust ints, string-hash "anonymization" (hash*31 mod 999983). No networking. Test passes only if db.nova is added to harness list; demo segfaults. |
| src/runtime/ffi.nova | skimmed | 156 | Partial | mem_read/write asm helpers + malloc/free/calloc via dlopen libc (needs --link-libc + gcc link). Tensor tests segfault under this path. |
| src/runtime/ffi_syscall.nova | skimmed | 632 | Partial | ELF .so loader/symbol resolver using raw syscalls, plus socket/connect/bind wrappers and inet_addr. test_ffi_syscall 9/11 (IP octet parsing wrong). |
| src/runtime/float.nova | skimmed | 420 | Partial | 45 float helpers built on float_* builtins. test_float_utils 16/32 at HEAD (abs/min/max/clamp/ceil/sign all wrong) - consequence of float_cmp returning 0 for "greater". |
| src/runtime/gpu.nova | skimmed | 349 | Dead | dlopen libcuda.so / libOpenCL.so and call cuInit etc. through FFI; CPU fallback. Needs --link-libc. No callers/tests; untestable here. |
| src/runtime/http.nova | reviewed | 457 | Dead | Hand-rolled HTTP/1.1 client over raw sockets (plain TCP, no TLS, caller passes IP). Whitelist checks the caller-supplied Host header, not the IP connected to; no CRLF sanitisation. No callers/tests. |
| src/runtime/io.nova | skimmed | 313 | Partial | Buffered file handles over syscall wrappers; println helpers. Used by benches/tests; several bench examples fail "undeclared callee: sys_open". |
| src/runtime/json.nova | skimmed | 290 | Working | Recursive-descent JSON parser/serializer to maps/lists. Passes test_json; json_config example runs. |
| src/runtime/list.nova | skimmed | 183 | Dead | Raw-memory growable array (alloc/load64/store64). Superseded by compiler builtin lists; nothing imports it (name collisions with builtins make the usage scan noisy). |
| src/runtime/llm.nova | reviewed | 433 | Dead | FFI wrapper over libnovabridge.so -> llama.cpp (local GGUF model; no HTTP, no API keys). Nothing in src/tests/examples calls llm_*; libnovabridge.so is not built by the Makefile. |
| src/runtime/llm_bridge.c | reviewed | 348 | Dead | 348-line C shim around llama.h (model/context params, tokenize, decode, sampler chain, nova_generate with bounded output buffer). Not compiled by any build target; no llama.cpp in repo. |
| src/runtime/map.nova | skimmed | 233 | Dead | Raw-memory open-addressing hash map. Superseded by builtin maps; not imported. |
| src/runtime/math.nova | skimmed | 342 | Working | Integer math (gcd, pow, isqrt, primes) + float wrappers. Passes test_math. |
| src/runtime/mem.nova | reviewed | 117 | Partial | Inline-asm typed peek/poke (i8..i64, f64) with no bounds checks. Lacks mem_free, which tensor.nova calls -> every tensor-based test fails to compile since the Oct-2026 undeclared-callee check. |
| src/runtime/node_pool.nova | skimmed | 156 | Working | Fixed-slot pool in one raw block with embedded free list (O(1) claim/release). Passes test_node_pool; demo segfaults at describe. The only NOVA module CrossEngin imports besides syscall/io/string. |
| src/runtime/path.nova | skimmed | 123 | Working | File-path string utilities (join, basename, ext). Passes test_path. |
| src/runtime/persistent_alloc.nova | skimmed | 310 | Partial | mmap(MAP_SHARED) file-backed bump pool with header + checksum, free is a no-op-style list. test_persistent_alloc fails/segfaults at HEAD ("open new pool"). |
| src/runtime/python.nova | skimmed | 638 | Dead | dlopen libpython3 and drive CPython C-API (PyRun_SimpleString, PyImport, numpy<->tensor copy). Needs --link-libc. py_exec runs arbitrary strings. No callers/tests. |
| src/runtime/scheduler.nova | reviewed | 653 | Working | THE MSC LOOP: global priority queue of signals; dispatch_one = pop, find dest node by name (linear), drop if dest already in trace, node_process, route outputs along channels whose source==node, soul_tick. Batched/secure/stream/timer variants. Passes when soul.nova is in the concat list. |
| src/runtime/secure_mem.nova | reviewed | 163 | Partial | Zeroing alloc/free, constant-time compare, bounded buffer; "secure_random_int"/"secure_token" are a 31-bit LCG seeded from global_time^48271 (predictable). |
| src/runtime/set.nova | skimmed | 149 | Working | Set on top of builtin map. Passes test_set. |
| src/runtime/simd.nova | skimmed | 375 | Working | SSE2 inline-asm loops over f64 arrays (add/mul/dot/scale/norm/relu). Exercised via tensor tests (pass with mem_free stub). |
| src/runtime/string.nova | skimmed | 486 | Partial | NUL-terminated string helpers over raw memory (compare, concat, find, int<->str). test_runtime/test_stdlib fail at HEAD. |
| src/runtime/syscall.nova | skimmed | 266 | Partial | Inline-asm Linux syscall wrappers (read/write/open/mmap/...). sys_mmap reported failing in test_runtime at HEAD. |
| src/runtime/taskpool.nova | skimmed | 121 | Partial | fork()+pipe per task, parent reads int result. test_taskpool times out at HEAD. |
| src/runtime/tensor.nova | reviewed | 688 | Partial | Row-major f64 matrix in raw memory: add/sub/scale, tiled matmul, transpose, relu/sigmoid/softmax/tanh approximations, cosine. No autograd/backprop. Works (tests pass 18/18) only when a mem_free definition is supplied; harness build fails; libc build segfaults. |
| src/runtime/timeseries.nova | skimmed | 388 | Working | Ring buffer of (t, value x1000) with windowed sum/mean/min/max, exponential decay, temporal join. Passes test; demo runs. |
| src/runtime/validate.nova | skimmed | 291 | Working | Range/length checks, character-class validators, HTML escape, blacklist of characters as "injection" check, simple rate limiter. Passes test_security. |


---

## Section: nova_tools_tests_docs


Rows: 421 files. `git ls-files tools tests docs packaging .github .gitignore` = 405 + 16 root-level *.md = 421. Row count matches.

Status key: reviewed = read; skimmed = classified by script and/or executed, or boilerplate. Test rows carry the runner result from the lead's HEAD run (`nova_testall.log`).

| path | status | LOC | actual status | what it really does |
|---|---|---|---|---|
| .github/workflows/release.yml | reviewed | 264 | Partial | Tag-triggered release workflow (tarballs + deb/pkg/msi). Never fired: repo has 0 tags / 0 releases. No test job; only CI workflow in repo. |
| .gitignore | reviewed | 95 | Doc | Ignores bin/, build outputs, editor files. |
| docs/COMPARISON.md | skimmed (headings + grep for checkable claims) | 1001 | Doc | 1,001-line Nova vs C vs Python marketing comparison; performance figures (3-5x, 50-100x) have no benchmark artifacts behind them in this repo. |
| docs/GETTING_STARTED.md | skimmed (headings + grep for checkable claims) | 300 | Doc | Getting Started with NOVA |
| docs/IDE_SETUP.md | skimmed (headings + grep for checkable claims) | 385 | Doc | VS Code IDE Setup for NOVA |
| docs/INFRASTRUCTURE_ROADMAP.md | skimmed (headings + grep for checkable claims) | 124 | Doc | NOVA Infrastructure Roadmap |
| docs/LANGUAGE_REFERENCE.md | reviewed (lines 1-335 read + 25 probes compiled) | 1341 | Doc | Informal reference (no grammar). Stale: documents floats as fixed-point x1000, omits tuples/generics/sum types/if-let/IEEE floats; several documented constructs miscompile at HEAD (see spot-check). |
| docs/PTR_TAGGING_PLAN.md | reviewed (partly) | 226 | Doc | Plan + progress log for low-bit value tagging; records "164 pass / 13 fail" and "bin/nova must NOT be replaced until these clear". |
| docs/STDLIB.md | skimmed (headings + grep for checkable claims) | 435 | Doc | Nova Standard Library Reference — N12–N29 |
| docs/TOUR.md | skimmed (headings + grep for checkable claims) | 100 | Doc | NOVA: A 5-Minute Tour |
| docs/USE_CASES.md | skimmed (headings + grep for checkable claims) | 1756 | Doc | 1,756 lines of aspirational use-case write-ups with code samples; not verified by any test. |
| docs/adr/0001-nova-language-design.md | skimmed (headings + grep for checkable claims) | 133 | Doc | ADR 0001: NOVA language design -- minimalism and what's intentionally absent |
| docs/adr/0002-self-hosting.md | skimmed (headings + grep for checkable claims) | 118 | Doc | ADR: claims stage1 is "106,045 lines of handwritten x86-64 assembly" (false: compiler output) and that self-host is a "pre-merge CI gate" (no CI exists); references non-existent compiler/main.nova. |
| docs/adr/0003-pattern-matching-evolution.md | skimmed (headings + grep for checkable claims) | 123 | Doc | ADR 0003: Pattern matching evolution -- R17A enums to R33C if-let + guards |
| docs/adr/0004-lsp-dap-tooling-strategy.md | skimmed (headings + grep for checkable claims) | 140 | Doc | ADR: says LSP is pygls-based (false: stdlib only). |
| docs/adr/0005-static-slot-closure-lowering.md | skimmed (headings + grep for checkable claims) | 147 | Doc | ADR 0005: Static-slot closure lowering (R35C) -- choice + the "last write wins" caveat |
| docs/adr/0006-nova-full-stack-infrastructure.md | skimmed (headings + grep for checkable claims) | 167 | Doc | ADR 0006: NOVA as full-stack infrastructure -- boundary + roadmap |
| docs/adr/0007-durable-storage-engine.md | skimmed (headings + grep for checkable claims) | 206 | Doc | ADR 0007: Durable storage engine -- WAL + crash recovery |
| docs/adr/0008-distributed-consensus-raft.md | skimmed (headings + grep for checkable claims) | 201 | Doc | ADR 0008: Distributed consensus -- Raft over the federation transport |
| docs/adr/0009-module-system-and-symbol-mangling.md | skimmed (headings + grep for checkable claims) | 207 | Doc | ADR 0009: Module system and symbol mangling for module-private names |
| docs/adr/0010-two-tier-tag-poly-contract.md | skimmed (headings + grep for checkable claims) | 268 | Doc | ADR 0010: Two-tier tag-polymorphism contract for runtime builtins |
| packaging/debian/changelog | skimmed | 11 | Partial | Nova Project <maintainers@nova-lang.org>  Mon, 01 Jun 2026 00:00:00 +0000 |
| packaging/debian/control | reviewed | 25 | Partial | Debian control file; Depends: binutils, libc6 (contradicts "no libc/zero dependencies" for the toolchain); Homepage nova-lang/nova. |
| packaging/debian/copyright | reviewed | 28 | Doc | MIT text, "Copyright 2025-2026 The Nova Project" (git history starts 2026-05-15). |
| packaging/debian/install | skimmed | 8 | Partial | install |
| packaging/debian/postinst | skimmed | 23 | Partial | postinst — runs after `dpkg -i nova_*.deb` succeeds. |
| packaging/debian/rules | skimmed | 26 | Partial | debian/rules for nova. |
| packaging/debian/source/format | skimmed | 1 | Partial | format |
| packaging/homebrew/README.md | skimmed (headings + grep for checkable claims) | 39 | Doc | Homebrew packaging |
| packaging/homebrew/bump-formula.sh | skimmed | 128 | Partial | Rewrites formula sha256/version from a release; no release exists to bump from. |
| packaging/macos/nova-distribution.xml | skimmed | 39 | Partial | nova-distribution.xml |
| packaging/macos/resources/conclusion.txt | skimmed | 19 | Partial | conclusion.txt |
| packaging/macos/resources/license.txt | reviewed | 22 | Doc | MIT license text — the only license text in the repo; there is no top-level LICENSE file. |
| packaging/macos/resources/welcome.txt | skimmed | 20 | Partial | welcome.txt |
| packaging/macos/scripts/postinstall | skimmed | 21 | Partial | /usr/local/bin/nova permission fix-up + man-page rebuild. |
| packaging/man/nova.1 | skimmed | 92 | Doc | Man page for nova CLI. |
| packaging/windows/build-msi.bat | skimmed | 60 | Partial | cmd wrapper for WiX build; untested here. |
| packaging/windows/nova.wxs | skimmed | 135 | Partial | WiX MSI definition template; never built in a release. |
| tests/bench_simd.sh | skimmed | 170 | Working | SAD microbenchmark scalar vs AVX2 builtin; prints timings, not a pass/fail test. |
| tests/bench_simd_wasm.sh | skimmed | 191 | Working | WASM v128 vs scalar SAD benchmark; skips without wat2wasm/wasmtime. |
| tests/run_tests.sh | reviewed | 392 | Partial | Test runner: compiles each tests/test_*.nova (some concatenated with src/ modules), assembles, links, runs; PASS iff exit code 0. No output comparison. Uses fixed /tmp paths. |
| tests/run_wasm_test.sh | reviewed | 37 | Working | Compiles one .nova to WASM and runs it under Node WASI (needs wat2wasm). |
| tests/test_7th_param.nova | skimmed (auto-classified + executed) | 60 | Working |  —  ~1 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: PASS |
| tests/test_accept_null_addr.nova | skimmed (auto-classified + executed) | 34 | Working | accept_conn(fd, 0, 0) must accept the connection. The tagged literal 0  —  ~2 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: PASS |
| tests/test_active_inference.nova | skimmed (auto-classified + executed) | 59 | Working |  —  ~11 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: PASS |
| tests/test_add.nova | skimmed (auto-classified + executed) | 10 | Partial |  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: PASS |
| tests/test_advanced_builtins.nova | skimmed (auto-classified + executed) | 54 | Partial | Test: Advanced list/map builtins  —  ~18 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_args.nova | skimmed (auto-classified + executed) | 10 | Partial |  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: PASS |
| tests/test_asm.nova | skimmed (auto-classified + executed) | 46 | Partial | Test inline assembly support  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: PASS |
| tests/test_associative.nova | skimmed (auto-classified + executed) | 76 | Partial |  —  ~10 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: FAIL (compile error) |
| tests/test_atom_lifecycle.nova | skimmed (auto-classified + executed) | 78 | Working |  —  ~14 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: PASS |
| tests/test_audio.nova | skimmed (auto-classified + executed) | 59 | Working |  —  ~6 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: PASS |
| tests/test_belief.nova | skimmed (auto-classified + executed) | 69 | Working | Test: Belief system (Beta distribution)  —  ~1 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: PASS |
| tests/test_bitwise_assign.nova | skimmed (auto-classified + executed) | 75 | Working | Test bitwise compound assignment operators  —  ~10 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: PASS |
| tests/test_bitwise_not.nova | skimmed (auto-classified + executed) | 38 | Working | Test bitwise NOT operator (~)  —  ~4 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: PASS |
| tests/test_bitwise_range.nova | skimmed (auto-classified + executed) | 44 | Partial | Bitwise ops  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: PASS |
| tests/test_break_continue_if.nova | skimmed (auto-classified + executed) | 53 | Partial |  —  ~6 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_causal_library.nova | skimmed (auto-classified + executed) | 45 | Working |  —  ~8 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: PASS |
| tests/test_chained_cmp.nova | skimmed (auto-classified + executed) | 40 | Partial | Basic chained <  —  ~12 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_channel.nova | skimmed (auto-classified + executed) | 126 | Partial | Test: Channels for inter-coroutine communication  —  ~24 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_closures.nova | skimmed (auto-classified + executed) | 42 | Partial | Test: Closures (lambdas capturing outer variables)  —  ~15 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_cognitive_llm.nova | skimmed (auto-classified + executed) | 59 | Partial | Test: Cognitive LLM Pipeline  —  ~0 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: FAIL (compile error) |
| tests/test_compiler_pattern.nova | skimmed (auto-classified + executed) | 54 | Partial |  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: PASS |
| tests/test_complex.nova | skimmed (auto-classified + executed) | 25 | Partial |  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: PASS |
| tests/test_compound_assign.nova | skimmed (auto-classified + executed) | 37 | Partial | Test: Compound assignment operators  —  ~9 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_concept.nova | skimmed (auto-classified + executed) | 265 | Partial | Test: Concept layer (hierarchy, schemas, multi-vector embeddings)  —  ~19 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: FAIL (compile error) |
| tests/test_confidence.nova | skimmed (auto-classified + executed) | 51 | Partial | Test: Confidence Annotations (@)  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: PASS |
| tests/test_const.nova | skimmed (auto-classified + executed) | 16 | Partial | Test: Const enforcement  —  ~4 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_const_folding.nova | skimmed (auto-classified + executed) | 152 | Partial | Test: R12E constant folding pass.  —  ~29 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_coro_advanced.nova | skimmed (auto-classified + executed) | 167 | Partial | Test: Advanced Coroutine Features  —  ~36 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: FAIL (exit code: 139) |
| tests/test_coroutine.nova | skimmed (auto-classified + executed) | 121 | Partial | Test: Coroutines  —  ~30 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_cross_fn_throw.nova | skimmed (auto-classified + executed) | 65 | Partial |  —  ~7 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_csv.nova | skimmed (auto-classified + executed) | 55 | Working | Test: CSV Parser  —  ~9 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: PASS |
| tests/test_dce.nova | skimmed (auto-classified + executed) | 187 | Partial | Test: R12E dead code elimination pass.  —  ~16 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_default_params.nova | skimmed (auto-classified + executed) | 61 | Partial |  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: PASS |
| tests/test_defer.nova | skimmed (auto-classified + executed) | 71 | Partial |  —  ~6 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_destructure.nova | skimmed (auto-classified + executed) | 36 | Partial |  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: PASS |
| tests/test_do_expr.nova | skimmed (auto-classified + executed) | 39 | Partial | basic do expression  —  ~4 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_dp_refused_eq.nova | skimmed (auto-classified + executed) | 30 | Partial | Empirical probe for Bug #4 (sentinel equality on two-large-operand `==`).  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: PASS |
| tests/test_elif.nova | skimmed (auto-classified + executed) | 50 | Partial |  —  ~4 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_embedding.nova | skimmed (auto-classified + executed) | 41 | Partial | Test: Embedding system  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: FAIL (compile error) |
| tests/test_enum.nova | skimmed (auto-classified + executed) | 38 | Partial | Test: Enum types  —  ~7 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_enum_cross_target.sh | skimmed | 225 | Partial | Compiles enum fixtures for 6 targets and greps emitted asm; most target legs skip when cross toolchains absent. |
| tests/test_enumerate.nova | skimmed (auto-classified + executed) | 27 | Partial |  —  ~7 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_exhaustiveness.nova | skimmed (auto-classified + executed) | 146 | Partial | R17A: exhaustiveness checking on `match` against a sum type.  —  ~15 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_exhaustiveness_warn.nova | skimmed (auto-classified + executed) | 52 | Partial | R17A: exhaustiveness WARN integration.  —  ~4 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_extern_fn.nova | skimmed (auto-classified + executed) | 48 | Partial | Test extern fn declaration and C FFI  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: PASS |
| tests/test_fails_unresolved_call.nova | skimmed (auto-classified + executed) | 9 | Working | Crossengin UPSTREAM §8 — compile-failure fixture.  —  ~0 assertion calls; negative test: runner requires compile error + message substring; runner result at HEAD: PASS (compile fail as expected: undeclared callee) |
| tests/test_federation.nova | skimmed (auto-classified + executed) | 65 | Partial |  —  ~12 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: FAIL (compile error) |
| tests/test_ffi.nova | skimmed (auto-classified + executed) | 63 | Dead | Load libc  —  ~4 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: SKIP (requires --link-libc; run via 'make ffi FILE=tests/test_ffi.nova') |
| tests/test_ffi_extended.nova | skimmed (auto-classified + executed) | 92 | Dead | Test: Extended FFI - ffi_calln, ffi_callf1/2, system_exec  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: SKIP (requires --link-libc; run via 'make ffi FILE=tests/test_ffi_extended.nova') |
| tests/test_ffi_syscall.nova | skimmed (auto-classified + executed) | 76 | Partial | Test: Syscall-based FFI (no libc)  —  ~12 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: FAIL (exit code: 3) |
| tests/test_fileio.nova | skimmed (auto-classified + executed) | 18 | Dead |  —  ~1 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: SKIP (requires special setup) |
| tests/test_finally.nova | skimmed (auto-classified + executed) | 57 | Partial | Finally runs after try (no error)  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: PASS |
| tests/test_float.nova | skimmed (auto-classified + executed) | 54 | Partial | Test: Fixed-point floating-point arithmetic (scale factor 1000)  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: PASS |
| tests/test_float_utils.nova | skimmed (auto-classified + executed) | 130 | Partial | Test: Float Utilities  —  ~32 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: FAIL (exit code: 3) |
| tests/test_flow_ops.nova | skimmed (auto-classified + executed) | 226 | Partial | Test: Flow Operators (~>, <~, =>>, <<~, ~~>, <=>,  — ~>)  —  ~1 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: FAIL (exit code: 1) |
| tests/test_fn_call_type_check.nova | skimmed (auto-classified + executed) | 148 | Partial | R24A: lightweight type-check pass extended from R23A's let-annotated  —  ~19 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_fn_ref.nova | skimmed (auto-classified + executed) | 47 | Partial |  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: PASS |
| tests/test_for_else.nova | skimmed (auto-classified + executed) | 70 | Partial | for...else with no break - else runs  —  ~6 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_for_indexed.nova | skimmed (auto-classified + executed) | 31 | Partial | for i, v in list  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: PASS |
| tests/test_generic_enum.nova | skimmed (auto-classified + executed) | 131 | Partial | R21A: NOVA generic enum payload types — `Result<T, E>` truly parametric.  —  ~25 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_generic_fn.nova | skimmed (auto-classified + executed) | 132 | Partial | R22B: NOVA generic function signatures — extend R21A from enums to fns.  —  ~20 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: FAIL (exit code: 1) |
| tests/test_generic_struct.nova | skimmed (auto-classified + executed) | 109 | Partial | R23A: NOVA generic struct payload types — parser-only feature, same  —  ~18 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_globals.nova | skimmed (auto-classified + executed) | 23 | Partial |  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: PASS |
| tests/test_goal.nova | skimmed (auto-classified + executed) | 76 | Working | Test: Goal engine  —  ~5 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: PASS |
| tests/test_guard.nova | skimmed (auto-classified + executed) | 30 | Partial |  —  ~8 assertion calls; counts failures but always exits 0 -> runner cannot see failures; runner result at HEAD: PASS |
| tests/test_hdc.nova | skimmed (auto-classified + executed) | 57 | Working |  —  ~10 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: PASS |
| tests/test_ieee754.nova | skimmed (auto-classified + executed) | 109 | Partial | Test 1: Float literal loading  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: PASS |
| tests/test_imagination.nova | skimmed (auto-classified + executed) | 77 | Partial | Test: Imagination subsystem  —  ~2 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: FAIL (exit code: 139) |
| tests/test_impl_blocks.nova | skimmed (auto-classified + executed) | 66 | Working | Test: impl blocks  —  ~3 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: PASS |
| tests/test_implicit_return.nova | skimmed (auto-classified + executed) | 29 | Partial |  —  ~5 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_import.nova | skimmed (auto-classified + executed) | 12 | Dead |  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: SKIP (requires special setup) |
| tests/test_import_lib.nova | skimmed (auto-classified + executed) | 7 | Dead |  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: SKIP (requires special setup) |
| tests/test_in_unless_until.nova | skimmed (auto-classified + executed) | 58 | Partial | in with strings  —  ~11 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_inclusive_range.nova | skimmed (auto-classified + executed) | 26 | Partial | inclusive range: 1..=5 -> [1, 2, 3, 4, 5]  —  ~7 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_interpolation.nova | skimmed (auto-classified + executed) | 62 | Partial | String interpolation  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: PASS |
| tests/test_io_println.nova | skimmed (auto-classified + executed) | 39 | Partial | Regression test for Crossengin UPSTREAM §5 (NOVA Bug #5).  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: PASS |
| tests/test_io_random.nova | skimmed (auto-classified + executed) | 35 | Dead | Test random  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: SKIP (requires special setup) |
| tests/test_is_operator.nova | skimmed (auto-classified + executed) | 33 | Partial |  —  ~11 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_json.nova | skimmed (auto-classified + executed) | 125 | Partial | Test: JSON Parser & Serializer  —  ~23 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_keywords.nova | skimmed (auto-classified + executed) | 51 | Partial |  —  ~16 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_kg_visualizer.nova | skimmed (auto-classified + executed) | 61 | Partial |  —  ~9 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: FAIL (compile error) |
| tests/test_knowledge.nova | skimmed (auto-classified + executed) | 326 | Partial |  —  ~59 assertion calls; counts failures but always exits 0 -> runner cannot see failures; runner result at HEAD: FAIL (exit code: 139) |
| tests/test_labeled_loops.nova | skimmed (auto-classified + executed) | 49 | Partial | Labeled break  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: - |
| tests/test_lambda.nova | skimmed (auto-classified + executed) | 46 | Partial | Test: Lambda expressions and higher-order functions  —  ~14 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_list_comp.nova | skimmed (auto-classified + executed) | 45 | Partial | Simple list comprehension  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: PASS |
| tests/test_list_repeat.nova | skimmed (auto-classified + executed) | 70 | Partial | Basic list repeat  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: PASS |
| tests/test_literals.nova | skimmed (auto-classified + executed) | 48 | Partial | Hex literals  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: PASS |
| tests/test_loop.nova | skimmed (auto-classified + executed) | 41 | Partial | Basic loop with break  —  ~3 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_m7_core.nova | skimmed (auto-classified + executed) | 350 | Partial | M7 Test: Core Moment-Signal Types  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: PASS |
| tests/test_m8_mind.nova | skimmed (auto-classified + executed) | 339 | Partial | M8 Test: Cognitive Systems  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: FAIL (compile error) |
| tests/test_m9_fullsystem.nova | skimmed (auto-classified + executed) | 509 | Partial | M9 Full System Verification Test  —  ~8 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: FAIL (compile error) |
| tests/test_m9_selfhost.sh | skimmed | 163 | Working | Stage2==stage3 fixpoint diff plus full-system compile; real exit-1 on mismatch. |
| tests/test_map_comp.nova | skimmed (auto-classified + executed) | 32 | Partial | Basic map comprehension  —  ~12 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_map_iter.nova | skimmed (auto-classified + executed) | 38 | Partial | for k, v in map  —  ~8 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_map_list.nova | skimmed (auto-classified + executed) | 83 | Partial | Map operations  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: PASS |
| tests/test_map_literal.nova | skimmed (auto-classified + executed) | 36 | Partial | Empty map  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: PASS |
| tests/test_match.nova | skimmed (auto-classified + executed) | 44 | Partial |  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: PASS |
| tests/test_match_expression.nova | skimmed (auto-classified + executed) | 215 | Partial | test_match_expression — match used in expression context.  —  ~22 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_match_guards.nova | skimmed (auto-classified + executed) | 81 | Partial | Guard on wildcard  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: PASS |
| tests/test_match_if_expr.nova | skimmed (auto-classified + executed) | 54 | Partial | match as expression - literal patterns  —  ~8 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_math.nova | skimmed (auto-classified + executed) | 147 | Partial | Test: Math Utilities  —  ~65 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_memcpy_raw_tagged.nova | skimmed (auto-classified + executed) | 42 | Working | Regression test for Crossengin UPSTREAM §1 (NOVA Bug #1).  —  ~1 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: PASS |
| tests/test_method_calls.nova | skimmed (auto-classified + executed) | 39 | Partial | Test: Method call syntax (obj.method(args) → method(obj, args))  —  ~16 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_mind.nova | skimmed (auto-classified + executed) | 234 | Partial | Test: Mind Declaration  —  ~18 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: FAIL (compile error) |
| tests/test_mini_lexer.nova | skimmed (auto-classified + executed) | 156 | Partial |  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: PASS |
| tests/test_moment_signal.nova | skimmed (auto-classified + executed) | 126 | Partial | Test the core Moment-Signal types  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: PASS |
| tests/test_multi_assign.nova | skimmed (auto-classified + executed) | 31 | Partial | Multi-assignment with let  —  ~12 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_multiline_strings.nova | skimmed (auto-classified + executed) | 36 | Partial | Multi-line string  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: PASS |
| tests/test_named_args.nova | skimmed (auto-classified + executed) | 24 | Partial | Named arguments (positional, names are documentation-only)  —  ~3 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_nanotime_tag.nova | skimmed (auto-classified + executed) | 63 | Working | Regression test for Crossengin UPSTREAM §7 (NOVA Bug #7).  —  ~4 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: PASS |
| tests/test_negative_index.nova | skimmed (auto-classified + executed) | 39 | Partial | Negative list indexing (already works)  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: PASS |
| tests/test_new_features.nova | skimmed (auto-classified + executed) | 68 | Working | Comprehensive test for new features:  —  ~20 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: PASS |
| tests/test_node_pool.nova | skimmed (auto-classified + executed) | 67 | Working |  —  ~18 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: PASS |
| tests/test_not_in.nova | skimmed (auto-classified + executed) | 28 | Partial | not in with list  —  ~11 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_nova10_sys_read_untag.nova | skimmed (auto-classified + executed) | 50 | Partial | nova#10 regression: sys_read / sys_write must accept a tagged `buf`  —  ~5 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_nova12_exec_path_argv.nova | skimmed (auto-classified + executed) | 36 | Working | nova#12 regression: _nova_exec's Linux branch must untag the path  —  ~0 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: PASS |
| tests/test_nova7_fork_return.nova | skimmed (auto-classified + executed) | 24 | Partial | nova#7 regression: fork_process() must return a tagged pid so that  —  ~1 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: PASS |
| tests/test_nova8_store64_zero.nova | skimmed (auto-classified + executed) | 37 | Partial | nova#8 regression: store64(ptr, 0) must write a raw 0 to memory so  —  ~4 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_null_access.nova | skimmed (auto-classified + executed) | 30 | Partial | Normal field access  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: PASS |
| tests/test_nullish.nova | skimmed (auto-classified + executed) | 39 | Partial | Basic nullish: non-zero returns left  —  ~8 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_numeric_sep.nova | skimmed (auto-classified + executed) | 24 | Partial | Decimal separators  —  ~6 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_optimize.nova | skimmed (auto-classified + executed) | 99 | Working | Test: Compiler Optimizations  —  ~0 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: PASS |
| tests/test_path.nova | skimmed (auto-classified + executed) | 74 | Partial | Test: Path Utilities  —  ~28 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_persistent_alloc.nova | skimmed (auto-classified + executed) | 97 | Partial | Test: Persistent Allocator  —  ~15 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: FAIL (exit code: 139) |
| tests/test_pipe.nova | skimmed (auto-classified + executed) | 35 | Partial |  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: PASS |
| tests/test_pkg.nova | skimmed (auto-classified + executed) | 32 | Partial | Test: Package management system  —  ~13 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_power_op.nova | skimmed (auto-classified + executed) | 54 | Partial | Basic exponentiation  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: PASS |
| tests/test_predictive_coding.nova | skimmed (auto-classified + executed) | 71 | Working |  —  ~10 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: PASS |
| tests/test_profiler.nova | skimmed (auto-classified + executed) | 76 | Working |  —  ~13 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: PASS |
| tests/test_ptr_threshold_fix.nova | skimmed (auto-classified + executed) | 96 | Partial | Regression test for the PTR_THRESHOLD root fix.  —  ~23 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: FAIL (compile error) |
| tests/test_range.nova | skimmed (auto-classified + executed) | 29 | Partial | Range literal: 0..5 => range_list(0, 5) => [0,1,2,3,4]  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: PASS |
| tests/test_range_step.nova | skimmed (auto-classified + executed) | 36 | Partial | range with step: 0..10..2 -> [0, 2, 4, 6, 8]  —  ~14 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_real_lexer.nova | skimmed (auto-classified + executed) | 225 | Partial | Test: compile the real Nova lexer and run it on a simple program  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: PASS |
| tests/test_resonance.nova | skimmed (auto-classified + executed) | 77 | Working |  —  ~8 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: PASS |
| tests/test_rest_pattern.nova | skimmed (auto-classified + executed) | 35 | Partial | Basic rest pattern  —  ~15 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_result.nova | skimmed (auto-classified + executed) | 146 | Partial | R20A: stdlib Result<T, E> + postfix `?` propagation operator.  —  ~26 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: FAIL (exit code: 139) |
| tests/test_runtime.nova | skimmed (auto-classified + executed) | 366 | Partial | Test: Runtime primitives (store64, load64, store8, load8, memcpy_raw, asm syscalls)  —  ~51 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: FAIL (exit code: 3) |
| tests/test_safety.nova | skimmed (auto-classified + executed) | 42 | Partial | Test bounds checking  —  ~2 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_safety_audit.nova | skimmed (auto-classified + executed) | 75 | Working | Test: Safety audit layer (permissions, logging, overrides)  —  ~10 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: PASS |
| tests/test_scheduler.nova | skimmed (auto-classified + executed) | 332 | Partial | Test: Signal Scheduler  —  ~15 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: FAIL (compile error) |
| tests/test_sdr.nova | skimmed (auto-classified + executed) | 70 | Working |  —  ~11 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: PASS |
| tests/test_secure_random.nova | skimmed (auto-classified + executed) | 93 | Partial | Test the secure_random(buf, n) builtin.  —  ~5 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_security.nova | skimmed (auto-classified + executed) | 269 | Partial |  —  ~71 assertion calls; counts failures but always exits 0 -> runner cannot see failures; runner result at HEAD: PASS |
| tests/test_self_model.nova | skimmed (auto-classified + executed) | 65 | Working |  —  ~14 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: PASS |
| tests/test_set.nova | skimmed (auto-classified + executed) | 115 | Partial | Test: Set Data Structure  —  ~30 assertion calls; counts failures but always exits 0 -> runner cannot see failures; runner result at HEAD: PASS |
| tests/test_simd_intrinsics.nova | skimmed (auto-classified + executed) | 210 | Partial | R11D — SIMD i32x8 intrinsics correctness test.  —  ~27 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: FAIL (compile error) |
| tests/test_simd_intrinsics_inlined.nova | skimmed (auto-classified + executed) | 261 | Partial | R13A — SIMD intrinsic INLINING correctness test.  —  ~16 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: FAIL (compile error) |
| tests/test_simd_mul_acc.nova | skimmed (auto-classified + executed) | 411 | Partial | R18A -- simd_mul_acc_byte_signed_byte / simd_mul_acc_signed_signed_byte  —  ~35 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: FAIL (compile error) |
| tests/test_simd_sad_u8.nova | skimmed (auto-classified + executed) | 280 | Partial | R14B -- simd_sad_u8 correctness test.  —  ~21 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: FAIL (compile error) |
| tests/test_simd_wasm_v128.nova | skimmed (auto-classified + executed) | 241 | Working | R15B — WASM v128 SIMD intrinsics correctness test.  —  ~22 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: PASS |
| tests/test_simd_wasm_v128.sh | skimmed | 76 | Partial | WASM v128 SIMD check; skips without wat2wasm/wasmtime. |
| tests/test_skill.nova | skimmed (auto-classified + executed) | 62 | Working |  —  ~17 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: PASS |
| tests/test_slice.nova | skimmed (auto-classified + executed) | 33 | Partial | Slice: nums[1:3] => [20, 30]  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: PASS |
| tests/test_smart_ops.nova | skimmed (auto-classified + executed) | 32 | Partial |  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: PASS |
| tests/test_soul.nova | skimmed (auto-classified + executed) | 172 | Partial |  —  ~27 assertion calls; counts failures but always exits 0 -> runner cannot see failures; runner result at HEAD: PASS |
| tests/test_spread_call.nova | skimmed (auto-classified + executed) | 36 | Partial |  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: PASS |
| tests/test_stats.nova | skimmed (auto-classified + executed) | 13 | Partial | Test that --stats flag works (basic program)  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: PASS |
| tests/test_stdlib.nova | skimmed (auto-classified + executed) | 56 | Partial | Test: Extended standard library functions  —  ~18 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: FAIL (exit code: 1) |
| tests/test_stream.nova | skimmed (auto-classified + executed) | 234 | Partial |  —  ~33 assertion calls; counts failures but always exits 0 -> runner cannot see failures; runner result at HEAD: PASS |
| tests/test_strength_reduce.nova | skimmed (auto-classified + executed) | 63 | Working | Test compiler optimizations: identity elimination, division strength reduction  —  ~17 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: PASS |
| tests/test_streq.nova | skimmed (auto-classified + executed) | 26 | Partial |  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: PASS |
| tests/test_string_iter.nova | skimmed (auto-classified + executed) | 73 | Working | Test for-in iteration over strings  —  ~6 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: PASS |
| tests/test_string_multiply.nova | skimmed (auto-classified + executed) | 35 | Partial | String * int  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: PASS |
| tests/test_string_utils.nova | skimmed (auto-classified + executed) | 27 | Partial | pad_right  —  ~9 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_strings.nova | skimmed (auto-classified + executed) | 34 | Partial |  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: PASS |
| tests/test_struct_brace_cross_target.sh | skimmed | 198 | Partial | Cross-target compile/grep assertions for struct brace-init; toolchain-dependent skips. |
| tests/test_struct_brace_init.nova | skimmed (auto-classified + executed) | 138 | Partial | R25A: brace-init struct construction `Foo { field: val, ... }`.  —  ~26 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_struct_const_fold.nova | skimmed (auto-classified + executed) | 111 | Partial | R27A.2: NOVA struct const-fold optimisation — collapse all-literal  —  ~18 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_struct_ctor_type_check.nova | skimmed (auto-classified + executed) | 151 | Partial | R24A: lightweight type-check pass extended from R23A's enum-ctor  —  ~24 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_struct_destructure.nova | skimmed (auto-classified + executed) | 119 | Partial | R25A: struct destructure pattern — `let Foo { field: binder } = x`  —  ~15 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_struct_methods.nova | skimmed (auto-classified + executed) | 42 | Partial |  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: PASS |
| tests/test_struct_update_cross_target.sh | skimmed | 204 | Partial | Cross-target compile/grep assertions for struct update syntax; toolchain-dependent skips. |
| tests/test_struct_update_syntax.nova | skimmed (auto-classified + executed) | 167 | Partial | R26A: struct update-syntax `Point { x: 10, ..p }` — construct a new  —  ~39 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_sum_types.nova | skimmed (auto-classified + executed) | 148 | Partial | R17A: NOVA sum types with payloads + variant patterns in match.  —  ~27 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: FAIL (exit code: 139) |
| tests/test_sys_syntax.nova | skimmed (auto-classified + executed) | 130 | Partial |  —  ~6 assertion calls; counts failures but always exits 0 -> runner cannot see failures; runner result at HEAD: PASS |
| tests/test_system.nova | skimmed (auto-classified + executed) | 317 | Partial |  —  ~39 assertion calls; counts failures but always exits 0 -> runner cannot see failures; runner result at HEAD: PASS |
| tests/test_taskpool.nova | skimmed (auto-classified + executed) | 66 | Partial | Test: Process-based Task Pool  —  ~12 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: FAIL (timeout) |
| tests/test_tco.nova | skimmed (auto-classified + executed) | 39 | Partial | Test tail call optimization  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: PASS |
| tests/test_tensor.nova | skimmed (auto-classified + executed) | 95 | Partial | Test: Tensor/Matrix Operations  —  ~1 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: FAIL (compile error) |
| tests/test_tensor_perf.nova | skimmed (auto-classified + executed) | 138 | Partial | Test: Tensor Performance Benchmarks  —  ~18 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: FAIL (compile error) |
| tests/test_ternary_dowhile.nova | skimmed (auto-classified + executed) | 51 | Partial | Test: Ternary expressions and do-while loops  —  ~9 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_time_machine.nova | skimmed (auto-classified + executed) | 86 | Working |  —  ~11 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: PASS |
| tests/test_timeseries.nova | skimmed (auto-classified + executed) | 64 | Working |  —  ~12 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: PASS |
| tests/test_trailing_comma.nova | skimmed (auto-classified + executed) | 28 | Partial | Trailing comma in function calls  —  ~6 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_try_catch.nova | skimmed (auto-classified + executed) | 34 | Partial | Basic try/catch  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: PASS |
| tests/test_try_catch_var.nova | skimmed (auto-classified + executed) | 51 | Partial | Basic try/catch with error variable  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: PASS |
| tests/test_try_expr.nova | skimmed (auto-classified + executed) | 38 | Partial | try as expression - success path (no throw)  —  ~6 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_type_annotations.nova | skimmed (auto-classified + executed) | 28 | Partial | Test: Type annotations (parsed and ignored)  —  ~6 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_type_check_warn.nova | skimmed (auto-classified + executed) | 106 | Partial | R23A.2: lightweight type-check pass. Walks the AST after parsing  —  ~22 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_type_match.nova | skimmed (auto-classified + executed) | 40 | Partial |  —  ~7 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_type_name.nova | skimmed (auto-classified + executed) | 16 | Partial | typename with variables  —  ~7 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_udp_syscalls.nova | skimmed (auto-classified + executed) | 186 | Working | Test the R28C UDP-syscall builtins.  —  ~20 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: PASS |
| tests/test_visualizer.nova | skimmed (auto-classified + executed) | 58 | Working |  —  ~11 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: PASS |
| tests/test_wal.nova | skimmed (auto-classified + executed) | 145 | Dead | Tests for the write-ahead log (src/storage/wal.nova) -- ADR NOVA-0007.  —  ~25 assertion calls; has real failure path (non-zero exit on mismatch); runner result at HEAD: SKIP (requires special setup) |
| tests/test_wasi_preopens.sh | skimmed | 101 | Partial | WASI filesystem smoke via wasmtime; skips cleanly if absent. |
| tests/test_wasm_basic.nova | skimmed (auto-classified + executed) | 23 | Partial | Simple WASM test  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: PASS |
| tests/test_wasm_features.nova | skimmed (auto-classified + executed) | 122 | Partial | Comprehensive WASM target test  —  ~36 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_while.nova | skimmed (auto-classified + executed) | 40 | Partial |  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: PASS |
| tests/test_while_else.nova | skimmed (auto-classified + executed) | 37 | Partial | while...else with no break - else runs  —  ~3 assertion calls; CANNOT FAIL on wrong values: uses only builtin assert(), which is a no-op for false at HEAD; runner result at HEAD: PASS |
| tests/test_winarm64_emitter.sh | skimmed | 114 | Partial | Checks PE/AArch64 binary invariants; cannot run the binary (no ARM Windows host); skips without toolchain. |
| tests/test_windows.nova | skimmed (auto-classified + executed) | 55 | Partial |  —  ~0 assertion calls; print-only, zero assertions (pass = did not crash); runner result at HEAD: PASS |
| tests/unit/test_closures.nova | skimmed (auto-classified + executed) | 408 | Partial | R37A: closure literals (` — x —  x + 1`, ` — x, y —  { ... }`, ` —  —  42`) with  —  85 checks; NOT run by run_tests.sh or any Makefile target; manual run at HEAD: runs, rc=0, 0 failed. |
| tests/unit/test_codegen_poll.nova | skimmed (auto-classified + executed) | 240 | Partial | R29A: tests for the new sys_poll(2) syscall builtin in codegen.  —  19 checks; NOT run by run_tests.sh or any Makefile target; manual run at HEAD: runs, passes. |
| tests/unit/test_codegen_wasm_poll.nova | skimmed (auto-classified + executed) | 405 | Partial | R30D: tests for the WASM-target sys_poll translation shim that  —  48 checks; NOT run by run_tests.sh or any Makefile target; manual run at HEAD: runs, passes. |
| tests/unit/test_floats.nova | skimmed (auto-classified + executed) | 384 | Dead | R38A: IEEE 754 double-precision float arithmetic + helpers.  —  87 checks; NOT run by run_tests.sh or any Makefile target; manual run at HEAD: 57 of 76 checks FAIL at HEAD yet exit code 0. |
| tests/unit/test_if_let.nova | skimmed (auto-classified + executed) | 255 | Dead | R33C: `if let PAT = expr { ... } [else ...]` shorthand for the  —  34 checks; NOT run by run_tests.sh or any Makefile target; manual run at HEAD: FAILS at HEAD (index out of bounds, rc=1). |
| tests/unit/test_let_destructure.nova | skimmed (auto-classified + executed) | 295 | Dead | R32D: irrefutable `let` destructure for structs (R25A consumer) and  —  39 checks; NOT run by run_tests.sh or any Makefile target; manual run at HEAD: FAILS at HEAD (panic, rc=3). |
| tests/unit/test_match_expr.nova | skimmed (auto-classified + executed) | 569 | Dead | R31D: match expression with enum-variant binding + exhaustiveness +  —  84 checks; NOT run by run_tests.sh or any Makefile target; manual run at HEAD: FAILS at HEAD (segfault). |
| tests/unit/test_match_guards.nova | skimmed (auto-classified + executed) | 305 | Dead | R33C: match arm guards. `Pat if expr => body` runs the body iff the  —  46 checks; NOT run by run_tests.sh or any Makefile target; manual run at HEAD: FAILS at HEAD (segfault). |
| tests/unit/test_stdlib_list.nova | skimmed (auto-classified + executed) | 382 | Dead | R37E: stdlib list combinators unit suite.  —  145 checks; NOT run by run_tests.sh or any Makefile target; manual run at HEAD: FAILS at HEAD (index out of bounds). |
| tests/unit/test_tuples.nova | skimmed (auto-classified + executed) | 379 | Dead | R36C: tuple literals + tuple types + tuple destructure.  —  71 checks; NOT run by run_tests.sh or any Makefile target; manual run at HEAD: FAILS at HEAD (12 of 70 checks fail, rc=3). |
| tools/Formula/nova.rb | reviewed | 121 | Stub | Homebrew formula template: sha256 fields are literal REPLACE_WITH_RELEASE_SHA256_* placeholders; URLs point at nova-lang/nova releases that do not exist; its test asserts `nova --version` exits 0 but the compiler exits 1. |
| tools/RELEASE.md | reviewed | 89 | Doc | Release procedure notes (tag push -> workflow). |
| tools/install.sh | reviewed | 135 | Partial | curl/sh installer: downloads tarball from GitHub releases of nova-lang/nova (not the origin repo; no releases exist), no checksum verification, on macOS installs an unlinked .o file. |
| tools/nova-dap/README.md | skimmed (headings + grep for checkable claims) | 626 | Doc | nova-dap |
| tools/nova-dap/nova_dap/__init__.py | skimmed | 10 | Working | Nova Debug Adapter Protocol implementation. |
| tools/nova-dap/nova_dap/__main__.py | skimmed | 5 | Working | Allow `python -m nova_dap` to launch the DAP server. |
| tools/nova-dap/nova_dap/breakpoints.py | skimmed | 411 | Working | Source-line breakpoint bookkeeping with conditional + hit-count gating. |
| tools/nova-dap/nova_dap/disassembly.py | skimmed | 737 | Working | Instruction-level disassembly + instruction breakpoints for the NOVA DAP server. |
| tools/nova-dap/nova_dap/evaluator.py | skimmed | 250 | Working | Expression evaluation for the NOVA DAP server. |
| tools/nova-dap/nova_dap/function_breakpoints.py | skimmed | 283 | Working | Function breakpoints for the NOVA DAP server. |
| tools/nova-dap/nova_dap/gdb_bridge.py | skimmed | 455 | Working | GDB Machine Interface (MI3) bridge. |
| tools/nova-dap/nova_dap/profiler.py | skimmed | 760 | Working | Sample-based profiler for the NOVA DAP server. |
| tools/nova-dap/nova_dap/server.py | skimmed (executed via tests) | 4100 | Working | DAP server (4,100 lines) translating DAP requests to gdb MI3 commands; verified end-to-end against a Nova-built ELF (breakpoint at main, 5 locals) and gcc-built C fixtures. |
| tools/nova-dap/nova_dap/source_refs.py | skimmed | 545 | Working | Synthetic-source / ``sourceReference`` cache for the nova-dap DAP server. |
| tools/nova-dap/nova_dap/variables.py | skimmed | 661 | Working | Structured DAP ``variables`` + ``scopes`` support (R38F). |
| tools/nova-dap/nova_dap/watchpoints.py | skimmed | 364 | Working | Data breakpoints (watchpoints) for the NOVA DAP server. |
| tools/nova-dap/pyproject.toml | reviewed | 26 | Working | Python package metadata: version 0.1.0, MIT, no runtime dependencies declared. |
| tools/nova-dap/tests/dap_multi_thread.py | skimmed (executed) | 645 | Working | End-to-end multi-thread test for the Nova DAP server. / exit code 0; integration legs print SKIP and still exit 0 when bin/hello_dwarf or gcc is missing. |
| tools/nova-dap/tests/dap_smoke.py | skimmed (executed) | 336 | Working | End-to-end smoke test for the Nova DAP server. / exit code 0; integration legs print SKIP and still exit 0 when bin/hello_dwarf or gcc is missing. |
| tools/nova-dap/tests/fixtures/multi_thread.c | skimmed | 89 | Working | C pthread fixture compiled with gcc for the multi-thread DAP test (DAP tests largely exercise C fixtures, not Nova programs). |
| tools/nova-dap/tests/test_conditional_breakpoint.py | skimmed (executed) | 676 | Working | Tests for DAP conditional breakpoints (``setBreakpoints`` with a ``condition`` arg). / exit code 0; integration legs print SKIP and still exit 0 when bin/hello_dwarf or gcc is missing. |
| tools/nova-dap/tests/test_data_breakpoints.py | skimmed (executed) | 1200 | Working | Tests for DAP data breakpoints (watchpoints) — the 19th capability for ``nova-dap``. / exit code 0; integration legs print SKIP and still exit 0 when bin/hello_dwarf or gcc is missing. |
| tools/nova-dap/tests/test_evaluate.py | skimmed (executed) | 735 | Working | Tests for DAP ``evaluate`` (REPL / watch / hover) — the 18th DAP capability for ``nova-dap``. / exit code 0; integration legs print SKIP and still exit 0 when bin/hello_dwarf or gcc is missing. |
| tools/nova-dap/tests/test_exception_breakpoints.py | skimmed (executed) | 1097 | Working | Tests for DAP exception breakpoints (R33F). / exit code 0; integration legs print SKIP and still exit 0 when bin/hello_dwarf or gcc is missing. |
| tools/nova-dap/tests/test_function_breakpoints.py | skimmed (executed) | 1197 | Working | Tests for DAP function breakpoints — the 20th capability for ``nova-dap``. / exit code 0; integration legs print SKIP and still exit 0 when bin/hello_dwarf or gcc is missing. |
| tools/nova-dap/tests/test_hit_count_breakpoints.py | skimmed (executed) | 1464 | Working | Tests for DAP hit-count + conditional breakpoint gating (R29E). / exit code 0; integration legs print SKIP and still exit 0 when bin/hello_dwarf or gcc is missing. |
| tools/nova-dap/tests/test_instruction_stepping.py | skimmed (executed) | 2423 | Working | Tests for DAP instruction-level stepping — the 21st capability for ``nova-dap``. / exit code 0; integration legs print SKIP and still exit 0 when bin/hello_dwarf or gcc is missing. |
| tools/nova-dap/tests/test_profiler.py | skimmed (executed) | 1023 | Working | Tests for the DAP sample-based profiler — custom-request channel extension to ``nova-dap``. / exit code 0; integration legs print SKIP and still exit 0 when bin/hello_dwarf or gcc is missing. |
| tools/nova-dap/tests/test_reverse_debug.py | skimmed (executed) | 1151 | Working | Tests for DAP reverse-debugging (R31E). / exit code 0; integration legs print SKIP and still exit 0 when bin/hello_dwarf or gcc is missing. |
| tools/nova-dap/tests/test_source_reference.py | skimmed (executed) | 1199 | Working | Tests for R34F: DAP ``disassemble`` + ``sourceReference`` mechanism. / exit code 0; integration legs print SKIP and still exit 0 when bin/hello_dwarf or gcc is missing. |
| tools/nova-dap/tests/test_variables.py | skimmed (executed) | 1656 | Working | Tests for R38F: structured DAP ``scopes`` + ``variables`` (Variables panel). / exit code 0; integration legs print SKIP and still exit 0 when bin/hello_dwarf or gcc is missing. |
| tools/nova-lsp/README.md | skimmed (headings + grep for checkable claims) | 741 | Doc | nova-lsp |
| tools/nova-lsp/nova_lsp/__init__.py | skimmed | 7 | Working | Nova Language Server Protocol implementation. |
| tools/nova-lsp/nova_lsp/__main__.py | skimmed | 5 | Working | Allow `python -m nova_lsp` to launch the server. |
| tools/nova-lsp/nova_lsp/base_spread_completion.py | skimmed | 509 | Working | Base-spread completion for `textDocument/completion`. |
| tools/nova-lsp/nova_lsp/call_hierarchy.py | skimmed | 648 | Working | Call hierarchy (`textDocument/prepareCallHierarchy`, `callHierarchy/incomingCalls`, `callHierarchy/outgoingCalls`). |
| tools/nova-lsp/nova_lsp/code_lens.py | skimmed | 889 | Working | Code lens (`textDocument/codeLens` + `codeLens/resolve`). |
| tools/nova-lsp/nova_lsp/completion.py | skimmed | 838 | Working | R38E completion enrichment: keywords + snippets + scope-aware identifiers. |
| tools/nova-lsp/nova_lsp/document_link.py | skimmed | 240 | Working | Document links (`textDocument/documentLink`). |
| tools/nova-lsp/nova_lsp/document_symbols.py | skimmed | 703 | Working | Document symbols for ``textDocument/documentSymbol``. |
| tools/nova-lsp/nova_lsp/exhaustiveness_fix.py | skimmed | 777 | Working | Auto-fix for non-exhaustive ``match`` expressions. |
| tools/nova-lsp/nova_lsp/extract_function.py | skimmed | 972 | Working | Extract-function refactor (`textDocument/codeAction`, kind `refactor.extract`). |
| tools/nova-lsp/nova_lsp/folding_ranges.py | skimmed | 445 | Working | Folding ranges for ``textDocument/foldingRange``. |
| tools/nova-lsp/nova_lsp/hover_docs.py | skimmed | 175 | Working | Doc-comment extraction for `textDocument/hover`. |
| tools/nova-lsp/nova_lsp/imports.py | skimmed | 220 | Working | Import-graph walker + per-file definition cache. |
| tools/nova-lsp/nova_lsp/inlay_hints.py | skimmed | 738 | Working | Inlay hints (`textDocument/inlayHint`) — parameter-name hints at function call sites. |
| tools/nova-lsp/nova_lsp/inline_variable.py | skimmed | 746 | Working | Inline-variable refactor (`textDocument/codeAction`, kind `refactor.inline`). |
| tools/nova-lsp/nova_lsp/prepare_rename.py | skimmed | 402 | Working | `textDocument/prepareRename` + new-name validation for R32E. |
| tools/nova-lsp/nova_lsp/rename_workspace.py | skimmed | 412 | Working | Workspace-wide rename (`textDocument/rename` across imports). |
| tools/nova-lsp/nova_lsp/scope_index.py | skimmed | 721 | Working | Lexical scope index for NOVA source files. |
| tools/nova-lsp/nova_lsp/semantic_tokens.py | skimmed | 903 | Working | Semantic tokens for `textDocument/semanticTokens/full`. |
| tools/nova-lsp/nova_lsp/server.py | reviewed (partially read; executed) | 2736 | Working | Stdlib-only JSON-RPC LSP server (no pygls despite docs). Regex/line-scan analysis of Nova source; diagnostics shell out to `nova --check` but the output regex does not match the compiler's `error[line N]:` format, so real syntax errors yield zero diagnostics (verified). |
| tools/nova-lsp/nova_lsp/struct_field_completion.py | skimmed | 531 | Working | Struct brace-init field completion for `textDocument/completion`. |
| tools/nova-lsp/nova_lsp/type_completion.py | skimmed | 758 | Working | Type-aware completion for `textDocument/completion`. |
| tools/nova-lsp/nova_lsp/type_hierarchy.py | skimmed | 953 | Working | Type hierarchy (`textDocument/prepareTypeHierarchy`, `typeHierarchy/supertypes`, `typeHierarchy/subtypes`). |
| tools/nova-lsp/nova_lsp/workspace_diagnostics.py | skimmed | 361 | Working | Workspace-wide diagnostics aggregation (`workspace/diagnostic`). |
| tools/nova-lsp/nova_lsp/workspace_symbols.py | skimmed | 406 | Working | Workspace symbol index for `workspace/symbol`. |
| tools/nova-lsp/pyproject.toml | reviewed | 26 | Working | Python package metadata: version 0.1.0, MIT, no runtime dependencies declared. |
| tools/nova-lsp/tests/_harness.py | skimmed (executed) | 117 | Working | Tiny in-process LSP harness used by the smoke tests. / script-style test (plain asserts, no pytest); exit code n/a when run. |
| tools/nova-lsp/tests/code_action_smoke.py | skimmed (executed) | 235 | Working | Smoke test for `textDocument/codeAction`. / script-style test (plain asserts, no pytest); exit code 0 when run. |
| tools/nova-lsp/tests/completion_smoke.py | skimmed (executed) | 79 | Working | Smoke test for `textDocument/completion`. / script-style test (plain asserts, no pytest); exit code 0 when run. |
| tools/nova-lsp/tests/definition_cross_file_smoke.py | skimmed (executed) | 241 | Working | Smoke test for cross-file `textDocument/definition`. / script-style test (plain asserts, no pytest); exit code 0 when run. |
| tools/nova-lsp/tests/references_smoke.py | skimmed (executed) | 97 | Working | Smoke test for `textDocument/references`. / script-style test (plain asserts, no pytest); exit code 0 when run. |
| tools/nova-lsp/tests/rename_smoke.py | skimmed (executed) | 98 | Working | Smoke test for `textDocument/rename`. / script-style test (plain asserts, no pytest); exit code 0 when run. |
| tools/nova-lsp/tests/test_base_spread_completion.py | skimmed (executed) | 728 | Working | Unit + wire tests for base-spread completion (R26A.2 follow-up to R26D). / script-style test (plain asserts, no pytest); exit code 0 when run. |
| tools/nova-lsp/tests/test_call_hierarchy.py | skimmed (executed) | 755 | Working | Unit + smoke + integration tests for call hierarchy. / script-style test (plain asserts, no pytest); exit code 0 when run. |
| tools/nova-lsp/tests/test_code_lens.py | skimmed (executed) | 778 | Working | Unit + smoke + integration tests for code lens. / script-style test (plain asserts, no pytest); exit code 0 when run. |
| tools/nova-lsp/tests/test_code_lens_r33d.py | skimmed (executed) | 438 | Working | R33D — Run/Debug code lens tests for top-level ``fn test_*`` decls. / script-style test (plain asserts, no pytest); exit code 0 when run. |
| tools/nova-lsp/tests/test_completion_r38e.py | skimmed (executed) | 907 | Working | Unit + wire tests for R38E `textDocument/completion`. / script-style test (plain asserts, no pytest); exit code 0 when run. |
| tools/nova-lsp/tests/test_document_link.py | skimmed (executed) | 481 | Working | R33D — `textDocument/documentLink` tests. / script-style test (plain asserts, no pytest); exit code 0 when run. |
| tools/nova-lsp/tests/test_document_symbols.py | skimmed (executed) | 434 | Working | Unit + smoke + integration tests for document symbols. / script-style test (plain asserts, no pytest); exit code 0 when run. |
| tools/nova-lsp/tests/test_exhaustiveness_fix.py | skimmed (executed) | 1176 | Working | Unit + integration tests for the exhaustiveness-fix code action. / script-style test (plain asserts, no pytest); exit code 0 when run. |
| tools/nova-lsp/tests/test_extract_function.py | skimmed (executed) | 971 | Working | Unit + integration tests for the extract-function refactor. / script-style test (plain asserts, no pytest); exit code 0 when run. |
| tools/nova-lsp/tests/test_extract_function_scope_aware.py | skimmed (executed) | 544 | Working | R36D — extract-function tightening via scope index. / script-style test (plain asserts, no pytest); exit code 0 when run. |
| tools/nova-lsp/tests/test_folding_ranges.py | skimmed (executed) | 423 | Working | Unit + smoke + integration tests for folding ranges. / script-style test (plain asserts, no pytest); exit code 0 when run. |
| tools/nova-lsp/tests/test_hover_docs.py | skimmed (executed) | 611 | Working | Tests for `textDocument/hover` `///` doc-comment surfacing. / script-style test (plain asserts, no pytest); exit code 0 when run. |
| tools/nova-lsp/tests/test_inlay_hints.py | skimmed (executed) | 918 | Working | Unit + smoke + integration tests for inlay hints. / script-style test (plain asserts, no pytest); exit code 0 when run. |
| tools/nova-lsp/tests/test_inline_variable.py | skimmed (executed) | 833 | Working | Unit + integration tests for the inline-variable refactor. / script-style test (plain asserts, no pytest); exit code 0 when run. |
| tools/nova-lsp/tests/test_prepare_rename_r32e.py | skimmed (executed) | 945 | Working | R32E — `textDocument/prepareRename` + cross-file `textDocument/rename` tests. / script-style test (plain asserts, no pytest); exit code 0 when run. |
| tools/nova-lsp/tests/test_r35f_code_action.py | skimmed (executed) | 857 | Working | R35F — code action coverage for organize-imports + extract-function. / script-style test (plain asserts, no pytest); exit code 0 when run. |
| tools/nova-lsp/tests/test_rename_workspace.py | skimmed (executed) | 860 | Working | Unit + smoke + integration tests for workspace-wide rename. / script-style test (plain asserts, no pytest); exit code 0 when run. |
| tools/nova-lsp/tests/test_scope_index.py | skimmed (executed) | 749 | Working | Unit tests for the R36D scope index. / script-style test (plain asserts, no pytest); exit code 0 when run. |
| tools/nova-lsp/tests/test_semantic_tokens.py | skimmed (executed) | 709 | Working | Smoke + unit + integration tests for `textDocument/semanticTokens/full`. / script-style test (plain asserts, no pytest); exit code 0 when run. |
| tools/nova-lsp/tests/test_semantic_tokens_r29d.py | skimmed (executed) | 540 | Working | R29D semantic-tokens follow-ups. / script-style test (plain asserts, no pytest); exit code 0 when run. |
| tools/nova-lsp/tests/test_struct_field_completion.py | skimmed (executed) | 664 | Working | Unit + wire + integration tests for struct brace-init field completion (R26D). / script-style test (plain asserts, no pytest); exit code 0 when run. |
| tools/nova-lsp/tests/test_type_completion.py | skimmed (executed) | 721 | Working | Unit + smoke + integration tests for type-aware completion (R24E). / script-style test (plain asserts, no pytest); exit code 0 when run. |
| tools/nova-lsp/tests/test_type_hierarchy.py | skimmed (executed) | 763 | Working | Unit + smoke + integration tests for type hierarchy. / script-style test (plain asserts, no pytest); exit code 0 when run. |
| tools/nova-lsp/tests/test_workspace_diagnostics.py | skimmed (executed) | 617 | Working | Unit + smoke + integration tests for workspace diagnostics. / script-style test (plain asserts, no pytest); exit code 0 when run. |
| tools/nova-lsp/tests/test_workspace_symbols.py | skimmed (executed) | 336 | Working | Smoke + unit + integration tests for `workspace/symbol`. / script-style test (plain asserts, no pytest); exit code 0 when run. |
| tools/release-dry-run.sh | skimmed | 186 | Working | Local equivalent of release workflow: builds, tars, sha256s artifacts into dist/. |
| tools/tree-sitter-nova/.editorconfig | skimmed (tree-sitter CLI template boilerplate) | 39 | Working | Standard language-binding / build scaffolding as emitted by `tree-sitter init` (MIT-licensed template code); not built here. src/parser.c is git-ignored so bindings cannot build without running tree-sitter generate. |
| tools/tree-sitter-nova/.gitattributes | skimmed (tree-sitter CLI template boilerplate) | 11 | Working | Standard language-binding / build scaffolding as emitted by `tree-sitter init` (MIT-licensed template code); not built here. src/parser.c is git-ignored so bindings cannot build without running tree-sitter generate. |
| tools/tree-sitter-nova/.gitignore | skimmed (tree-sitter CLI template boilerplate) | 44 | Working | Standard language-binding / build scaffolding as emitted by `tree-sitter init` (MIT-licensed template code); not built here. src/parser.c is git-ignored so bindings cannot build without running tree-sitter generate. |
| tools/tree-sitter-nova/Cargo.toml | skimmed (tree-sitter CLI template boilerplate) | 23 | Working | Standard language-binding / build scaffolding as emitted by `tree-sitter init` (MIT-licensed template code); not built here. src/parser.c is git-ignored so bindings cannot build without running tree-sitter generate. |
| tools/tree-sitter-nova/INSTALL_NEOVIM.md | skimmed (headings + grep for checkable claims) | 139 | Doc | Using tree-sitter-nova in Neovim |
| tools/tree-sitter-nova/Makefile | skimmed (tree-sitter CLI template boilerplate) | 112 | Working | Standard language-binding / build scaffolding as emitted by `tree-sitter init` (MIT-licensed template code); not built here. src/parser.c is git-ignored so bindings cannot build without running tree-sitter generate. |
| tools/tree-sitter-nova/Package.swift | skimmed (tree-sitter CLI template boilerplate) | 47 | Working | Standard language-binding / build scaffolding as emitted by `tree-sitter init` (MIT-licensed template code); not built here. src/parser.c is git-ignored so bindings cannot build without running tree-sitter generate. |
| tools/tree-sitter-nova/README.md | skimmed (headings + grep for checkable claims) | 230 | Doc | tree-sitter-nova |
| tools/tree-sitter-nova/binding.gyp | skimmed (tree-sitter CLI template boilerplate) | 30 | Working | Standard language-binding / build scaffolding as emitted by `tree-sitter init` (MIT-licensed template code); not built here. src/parser.c is git-ignored so bindings cannot build without running tree-sitter generate. |
| tools/tree-sitter-nova/bindings/c/tree-sitter-nova.h | skimmed (tree-sitter CLI template boilerplate) | 16 | Working | Standard language-binding / build scaffolding as emitted by `tree-sitter init` (MIT-licensed template code); not built here. src/parser.c is git-ignored so bindings cannot build without running tree-sitter generate. |
| tools/tree-sitter-nova/bindings/c/tree-sitter-nova.pc.in | skimmed (tree-sitter CLI template boilerplate) | 11 | Working | Standard language-binding / build scaffolding as emitted by `tree-sitter init` (MIT-licensed template code); not built here. src/parser.c is git-ignored so bindings cannot build without running tree-sitter generate. |
| tools/tree-sitter-nova/bindings/go/binding.go | skimmed (tree-sitter CLI template boilerplate) | 13 | Working | Standard language-binding / build scaffolding as emitted by `tree-sitter init` (MIT-licensed template code); not built here. src/parser.c is git-ignored so bindings cannot build without running tree-sitter generate. |
| tools/tree-sitter-nova/bindings/go/binding_test.go | skimmed (tree-sitter CLI template boilerplate) | 15 | Working | Standard language-binding / build scaffolding as emitted by `tree-sitter init` (MIT-licensed template code); not built here. src/parser.c is git-ignored so bindings cannot build without running tree-sitter generate. |
| tools/tree-sitter-nova/bindings/go/go.mod | skimmed (tree-sitter CLI template boilerplate) | 5 | Working | Standard language-binding / build scaffolding as emitted by `tree-sitter init` (MIT-licensed template code); not built here. src/parser.c is git-ignored so bindings cannot build without running tree-sitter generate. |
| tools/tree-sitter-nova/bindings/node/binding.cc | skimmed (tree-sitter CLI template boilerplate) | 20 | Working | Standard language-binding / build scaffolding as emitted by `tree-sitter init` (MIT-licensed template code); not built here. src/parser.c is git-ignored so bindings cannot build without running tree-sitter generate. |
| tools/tree-sitter-nova/bindings/node/index.d.ts | skimmed (tree-sitter CLI template boilerplate) | 28 | Working | Standard language-binding / build scaffolding as emitted by `tree-sitter init` (MIT-licensed template code); not built here. src/parser.c is git-ignored so bindings cannot build without running tree-sitter generate. |
| tools/tree-sitter-nova/bindings/node/index.js | skimmed (tree-sitter CLI template boilerplate) | 7 | Working | Standard language-binding / build scaffolding as emitted by `tree-sitter init` (MIT-licensed template code); not built here. src/parser.c is git-ignored so bindings cannot build without running tree-sitter generate. |
| tools/tree-sitter-nova/bindings/python/tree_sitter_nova/__init__.py | skimmed (tree-sitter CLI template boilerplate) | 5 | Working | Standard language-binding / build scaffolding as emitted by `tree-sitter init` (MIT-licensed template code); not built here. src/parser.c is git-ignored so bindings cannot build without running tree-sitter generate. |
| tools/tree-sitter-nova/bindings/python/tree_sitter_nova/__init__.pyi | skimmed (tree-sitter CLI template boilerplate) | 1 | Working | Standard language-binding / build scaffolding as emitted by `tree-sitter init` (MIT-licensed template code); not built here. src/parser.c is git-ignored so bindings cannot build without running tree-sitter generate. |
| tools/tree-sitter-nova/bindings/python/tree_sitter_nova/binding.c | skimmed (tree-sitter CLI template boilerplate) | 27 | Working | Standard language-binding / build scaffolding as emitted by `tree-sitter init` (MIT-licensed template code); not built here. src/parser.c is git-ignored so bindings cannot build without running tree-sitter generate. |
| tools/tree-sitter-nova/bindings/python/tree_sitter_nova/py.typed | skimmed (tree-sitter CLI template boilerplate) | 0 | Working | Standard language-binding / build scaffolding as emitted by `tree-sitter init` (MIT-licensed template code); not built here. src/parser.c is git-ignored so bindings cannot build without running tree-sitter generate. |
| tools/tree-sitter-nova/bindings/rust/build.rs | skimmed (tree-sitter CLI template boilerplate) | 22 | Working | Standard language-binding / build scaffolding as emitted by `tree-sitter init` (MIT-licensed template code); not built here. src/parser.c is git-ignored so bindings cannot build without running tree-sitter generate. |
| tools/tree-sitter-nova/bindings/rust/lib.rs | skimmed (tree-sitter CLI template boilerplate) | 54 | Working | Standard language-binding / build scaffolding as emitted by `tree-sitter init` (MIT-licensed template code); not built here. src/parser.c is git-ignored so bindings cannot build without running tree-sitter generate. |
| tools/tree-sitter-nova/bindings/swift/TreeSitterNova/nova.h | skimmed (tree-sitter CLI template boilerplate) | 16 | Working | Standard language-binding / build scaffolding as emitted by `tree-sitter init` (MIT-licensed template code); not built here. src/parser.c is git-ignored so bindings cannot build without running tree-sitter generate. |
| tools/tree-sitter-nova/grammar.js | reviewed | 1455 | Working | Hand-written tree-sitter grammar (1,455 lines). Generates cleanly; 150/150 corpus tests pass; parses 355/365 NOVA .nova files and 899/924 CrossEngin .nova files without ERROR nodes (executed). |
| tools/tree-sitter-nova/pyproject.toml | skimmed (tree-sitter CLI template boilerplate) | 29 | Working | Standard language-binding / build scaffolding as emitted by `tree-sitter init` (MIT-licensed template code); not built here. src/parser.c is git-ignored so bindings cannot build without running tree-sitter generate. |
| tools/tree-sitter-nova/queries/folds.scm | skimmed | 104 | Working | tree-sitter query file (folds.scm) for editor highlighting/folding/scopes. |
| tools/tree-sitter-nova/queries/highlights.scm | skimmed | 288 | Working | tree-sitter query file (highlights.scm) for editor highlighting/folding/scopes. |
| tools/tree-sitter-nova/queries/locals.scm | skimmed | 219 | Working | tree-sitter query file (locals.scm) for editor highlighting/folding/scopes. |
| tools/tree-sitter-nova/setup.py | skimmed (tree-sitter CLI template boilerplate) | 60 | Working | Standard language-binding / build scaffolding as emitted by `tree-sitter init` (MIT-licensed template code); not built here. src/parser.c is git-ignored so bindings cannot build without running tree-sitter generate. |
| tools/tree-sitter-nova/test/corpus/basics.txt | skimmed (executed) | 542 | Working | tree-sitter corpus tests (source -> expected S-expression); all pass under tree-sitter-cli 0.24.7. |
| tools/tree-sitter-nova/test/corpus/declarations.txt | skimmed (executed) | 138 | Working | tree-sitter corpus tests (source -> expected S-expression); all pass under tree-sitter-cli 0.24.7. |
| tools/tree-sitter-nova/test/corpus/literals.txt | skimmed (executed) | 112 | Working | tree-sitter corpus tests (source -> expected S-expression); all pass under tree-sitter-cli 0.24.7. |
| tools/tree-sitter-nova/test/corpus/r17_enums.txt | skimmed (executed) | 150 | Working | tree-sitter corpus tests (source -> expected S-expression); all pass under tree-sitter-cli 0.24.7. |
| tools/tree-sitter-nova/test/corpus/r20_result_question.txt | skimmed (executed) | 98 | Working | tree-sitter corpus tests (source -> expected S-expression); all pass under tree-sitter-cli 0.24.7. |
| tools/tree-sitter-nova/test/corpus/r21_generic_enums.txt | skimmed (executed) | 142 | Working | tree-sitter corpus tests (source -> expected S-expression); all pass under tree-sitter-cli 0.24.7. |
| tools/tree-sitter-nova/test/corpus/r22_generic_fns.txt | skimmed (executed) | 156 | Working | tree-sitter corpus tests (source -> expected S-expression); all pass under tree-sitter-cli 0.24.7. |
| tools/tree-sitter-nova/test/corpus/r23_generic_structs.txt | skimmed (executed) | 132 | Working | tree-sitter corpus tests (source -> expected S-expression); all pass under tree-sitter-cli 0.24.7. |
| tools/tree-sitter-nova/test/corpus/r24_named_args_and_misc.txt | skimmed (executed) | 421 | Working | tree-sitter corpus tests (source -> expected S-expression); all pass under tree-sitter-cli 0.24.7. |
| tools/tree-sitter-nova/test/corpus/r25_brace_init.txt | skimmed (executed) | 239 | Working | tree-sitter corpus tests (source -> expected S-expression); all pass under tree-sitter-cli 0.24.7. |
| tools/tree-sitter-nova/test/corpus/r25_struct_destructure.txt | skimmed (executed) | 239 | Working | tree-sitter corpus tests (source -> expected S-expression); all pass under tree-sitter-cli 0.24.7. |
| tools/tree-sitter-nova/test/corpus/r31_match_expression.txt | skimmed (executed) | 258 | Working | tree-sitter corpus tests (source -> expected S-expression); all pass under tree-sitter-cli 0.24.7. |
| tools/tree-sitter-nova/test/corpus/r32_let_destructure.txt | skimmed (executed) | 141 | Working | tree-sitter corpus tests (source -> expected S-expression); all pass under tree-sitter-cli 0.24.7. |
| tools/tree-sitter-nova/test/corpus/r33_if_let.txt | skimmed (executed) | 323 | Working | tree-sitter corpus tests (source -> expected S-expression); all pass under tree-sitter-cli 0.24.7. |
| tools/tree-sitter-nova/test/corpus/r35_closures.txt | skimmed (executed) | 192 | Working | tree-sitter corpus tests (source -> expected S-expression); all pass under tree-sitter-cli 0.24.7. |
| tools/tree-sitter-nova/test/corpus/r36_tuples.txt | skimmed (executed) | 191 | Working | tree-sitter corpus tests (source -> expected S-expression); all pass under tree-sitter-cli 0.24.7. |
| tools/tree-sitter-nova/tree-sitter.json | skimmed (tree-sitter CLI template boilerplate) | 38 | Working | Standard language-binding / build scaffolding as emitted by `tree-sitter init` (MIT-licensed template code); not built here. src/parser.c is git-ignored so bindings cannot build without running tree-sitter generate. |
| tools/vscode-nova/.gitignore | skimmed (tree-sitter CLI template boilerplate) | 16 | Working | VS Code extension build/ignore config. |
| tools/vscode-nova/.vscodeignore | skimmed | 27 | Working | .vscodeignore |
| tools/vscode-nova/CHANGELOG.md | skimmed (headings + grep for checkable claims) | 59 | Doc | Changelog |
| tools/vscode-nova/README.md | skimmed (headings + grep for checkable claims) | 240 | Doc | NOVA Language — VS Code extension |
| tools/vscode-nova/language-configuration.json | skimmed | 33 | Working | language-configuration.json |
| tools/vscode-nova/package.json | reviewed | 246 | Working | Extension manifest; dep vscode-languageclient ^9 (MIT); publisher "crossengin"; not published. |
| tools/vscode-nova/scripts/build-vsix.sh | skimmed | 58 | Working | build-vsix.sh — produce nova-language-<version>.vsix |
| tools/vscode-nova/snippets/nova.snippets.json | skimmed | 114 | Working | nova.snippets.json |
| tools/vscode-nova/src/extension.ts | skimmed | 359 | Partial | VS Code client: spawns `python -m nova_lsp` and registers nova-dap adapter; not built/packaged here (npm install needs network). |
| tools/vscode-nova/syntaxes/nova.tmLanguage.json | skimmed | 194 | Working | TextMate regex grammar for highlighting (third copy of Nova lexical rules). |
| tools/vscode-nova/tests/__init__.py | skimmed | 0 | Working | __init__.py |
| tools/vscode-nova/tests/test_build.py | skimmed | 109 | Partial | Runs the VSIX build (npm install); timed out at 60s in audit sandbox, not verified. |
| tools/vscode-nova/tests/test_extension_manifest.py | skimmed | 201 | Working | Asserts package.json fields; passes (executed). |
| tools/vscode-nova/tests/test_textmate_grammar.py | skimmed | 125 | Working | Asserts TextMate grammar regexes match sample tokens; passes (executed). |
| tools/vscode-nova/tsconfig.json | skimmed | 33 | Working | tsconfig.json |
| ANALYSIS.md | reviewed (partly) | 163 | Doc | AI-written self-assessment; correctly flags 4.2.0 vs 0.1.0 version conflict and that nothing is published; still repeats "handwritten assembly seed". |
| ARCHITECTURE.md | skimmed (headings + grep for checkable claims) | 1062 | Doc | Module map. Line counts stale (says compiler ~27,873; actual 34,637), "178 tests (172 pass, 6 skip)" false at HEAD. |
| COMPAT.md | skimmed (headings + grep for checkable claims) | 101 | Doc | Compatibility / stability promise notes for builtins and targets. |
| DWARF_AUDIT.md | skimmed (headings + grep for checkable claims) | 185 | Doc | DWARF Debug Info: Status and Scope |
| GPU_AUDIT.md | skimmed (headings + grep for checkable claims) | 226 | Doc | NOVA GPU Compute Backend Audit |
| INSTALL.md | reviewed (partly) | 299 | Doc | Seven install paths; admits only build-from-source works today; others await a v0.1.0 tag that was never pushed. URLs point to nova-lang/nova. |
| MACOS_AUDIT.md | skimmed (headings + grep for checkable claims) | 100 | Doc | NOVA macOS Backend Audit |
| MOBILE_AUDIT.md | skimmed (headings + grep for checkable claims) | 136 | Doc | NOVA Mobile (iOS / Android ARM64) — Audit & Status |
| NEXT_SESSION.md | skimmed (headings + grep for checkable claims) | 8930 | Doc | 8,930-line reverse-chronological per-round agent log (R38 down to R9): what each AI session shipped, test counts claimed (always "0 failed"), known gaps. Skimmed by headings + grep. |
| NOVA_BUG_THRESHOLD.md | skimmed (headings + grep for checkable claims) | 259 | Doc | History of the int-vs-pointer misclassification bug (1 MB heuristic -> range check -> value tagging) and the 2026-06-16 self-host segfault incident. |
| README.md | reviewed (lines 1-340, 690-900 read; rest grepped) | 1205 | Doc | Project overview. Many stale/false numbers: version 4.2.0, "182 tests (176 pass)", compiler 16,467 lines, "handwritten assembly", "LSP (pygls)", "See LICENSE". See Claims table. |
| RETROSPECTIVE_26_ROUNDS.md | reviewed | 72 | Doc | Pointer to CrossEngin retrospective + list of notable rounds; describes multi-agent "rounds" process. |
| SIMD_AUDIT.md | skimmed (headings + grep for checkable claims) | 173 | Doc | NOVA SIMD / AVX2 Backend Audit |
| STABILITY_AUDIT.md | skimmed (headings + grep for checkable claims) | 187 | Doc | Honest target matrix: Windows "Wine-only", macOS "no real-Darwin run", WASM "hello-world", ARM64 "STUBBED" (partly outdated). |
| WASM_AUDIT.md | skimmed (headings + grep for checkable claims) | 196 | Doc | NOVA WebAssembly Backend Audit |
| WIN32_AUDIT.md | skimmed (headings + grep for checkable claims) | 208 | Doc | NOVA Windows Backend Audit |


---

## Section: ce_core


Rows: 144 files (substrate 9, parts 56, gates 1, scheduler 4, kg 25, mind 9, learning 29, seed 6, sim 1, preference 1, perception 3 = 144). Verified against `find src/<dir> -type f` (the working copy has no .git, so `git ls-files` was unavailable). Total 41,567 LOC.

"reviewed" = code read line-by-line (comments stripped). "skimmed" = header + function inventory + targeted greps, and unit test executed where noted in findings; skimmed because the file is long, repetitive accessor/formatting code, or off the answer path.

Last column: imported (transitively) by `examples/crossengin_chat.nova` / `crossengin_daemon.nova`. Import-reachable does not mean called; see findings.

| path | status | LOC | actual status | what it really does | imported by chat/daemon |
|---|---|---|---|---|---|
| CE/src/substrate/first_nodes.nova | reviewed | 159 | Working | Reserves first N node ids of a pool as an input block; static table part-kind -> accepted signal types; inject = add strength to each block node inbox. | chat+daemon |
| CE/src/substrate/gate_router.nova | reviewed | 218 | Partial | Table signal-type -> [(part, weight)]; route = parts with weight > 100; CONST broadcasts to all. reinforce/decay/prune ("learned routing") have no live callers. | chat+daemon |
| CE/src/substrate/node_pool_manager.nova | reviewed | 218 | Working (inert live) | Leaky integrate-and-fire node: 8 ints/node in milli fixed-point; act=0.9*act+inbox+bias, fire if >=thresh, reset. Live pools are 128 slots, 8 used per part. | chat+daemon |
| CE/src/substrate/part_lifecycle.nova | reviewed | 90 | Working | Add/retire "kg-<domain>" parts by flipping an alive flag. | chat+daemon |
| CE/src/substrate/part_registry.nova | reviewed | 161 | Working | List of parts; each part = {name, preset, node pool, synapse graph, first-node ids}. Linear name lookup. | chat+daemon |
| CE/src/substrate/resonance_engine.nova | reviewed | 113 | Dead (tests + kernel_selfcheck only) | "Resonance" = if both directions of a synapse pair exist and both nodes have activation >= 400, add +50 to both weights. | no |
| CE/src/substrate/signal_dispatch.nova | reviewed | 230 | Partial | 18 integer type ids + fixed priority table + 7-field signal list + 10-bucket FIFO priority queue. The queue is never used outside tests. | chat+daemon |
| CE/src/substrate/synapse_graph.nova | reviewed | 462 | Working (mostly unused live) | Struct-of-arrays synapse list (pre,post,w in [-1000,1000],elig,mask) + adjacency; Hebbian/error/STDP/3-factor updates, pruning. Live path uses only find/grow/set_weight as an atom-pair weight table. | chat+daemon |
| CE/src/substrate/tick_driver.nova | reviewed | 323 | Working (inert live) | Per part: snapshot activations, integrate all slots, deliver w*1.0 down out-synapses of fired nodes, Hebbian step; optional 3-factor pass (OFF by default). | chat+daemon |
| CE/src/parts/imagination/README.md | skimmed | 9 | Doc (stale) | Says "Pending". | no |
| CE/src/parts/imagination/counterfactual.nova | reviewed | 61 | Dead (tests only) | Run forward_simulate on a set and on the set with one id removed/added; count symmetric difference. | no |
| CE/src/parts/imagination/dream_recombination.nova | reviewed | 46 | Dead (tests only) | Keep each id with probability creativity/1000 using seeded random(); "discover" = store as pattern. | no |
| CE/src/parts/imagination/forward_sim.nova | reviewed | 73 | Working | Production-rule step: pick highest-belief pattern whose situation set is contained in state and adds something; union successor; repeat. | chat+daemon |
| CE/src/parts/imagination/imagination_engine.nova | reviewed | 116 | Working | Patterns = atoms with situation/successor id lists; seed_patterns mints synthetic "seed_i: {i}->{100+i}" placeholders. | chat+daemon |
| CE/src/parts/imagination/scenario_planner.nova | reviewed | 79 | Dead (tests only) | For each candidate id: add to state, forward_simulate, score = count of goal ids present; pick max/min. | no |
| CE/src/parts/reasoning/README.md | skimmed | 9 | Doc (stale) | Says "Pending". | no |
| CE/src/parts/reasoning/argumentation.nova | skimmed | 242 | Working | Dung abstract argumentation: grounded labelling by fixpoint; preferred extensions by bitmask enumeration (exponential, small n). | chat |
| CE/src/parts/reasoning/contradiction.nova | skimmed | 325 | Working | Finds P and (P->FALSE) among axioms (direct + one transitive step), builds an MP proof checked by the kernel. | chat |
| CE/src/parts/reasoning/debate.nova | skimmed | 377 | Working | Binds arguments to claims; sums surviving argument weights into Beta(alpha,beta) -> confidence; strict (proof) arguments win. | chat |
| CE/src/parts/reasoning/decision_record.nova | skimmed | 184 | Working | Formats debate/steelman/promotion verdicts into decision-log entries. | chat |
| CE/src/parts/reasoning/epistemic_status.nova | skimmed | 111 | Working | If-ladder over grade/proof/belief mean -> PROVEN/CORROBORATED/BELIEVED/CONTESTED/REFUTED/UNKNOWN label. | chat |
| CE/src/parts/reasoning/multi_kg_consistency.nova | skimmed | 173 | Working | Hash same-label atoms across KGs; report pairs whose belief means straddle 0.5 by more than a threshold. | chat |
| CE/src/parts/reasoning/promotion_pass.nova | skimmed | 151 | Working | Runs license/protected-conflict/grade/debate gates on a candidate claim and logs the outcome. | chat |
| CE/src/parts/reasoning/proof_checker.nova | skimmed | 421 | Working | BFS over operator edges from premise atom to conclusion atom up to depth D; strength = product of confidences. (Path search, not logic.) | chat |
| CE/src/parts/reasoning/reasoning_atoms.nova | reviewed | 143 | Working | Operator = RELATION atom with payload {op kind, premise id, conclusion id}; adjacency index by premise/conclusion id. Core of answering. | chat+daemon |
| CE/src/parts/reasoning/reasoning_module.nova | reviewed | 170 | Working | BFS forward chain over CAUSAL/IMPLY operators; abduction = best-confidence incoming CAUSAL; chain conf = product; noisy-OR support. | chat+daemon |
| CE/src/parts/reasoning/steelman.nova | skimmed | 183 | Working | Summarizes each preferred extension as (stance, strength) and renders text. | chat |
| CE/src/parts/goals/drive_generators.nova | reviewed | 74 | Working | Four if-threshold rules that create goals with fixed names ("explore gap", "engage user", ...). | chat+daemon |
| CE/src/parts/goals/goal_engine.nova | reviewed | 237 | Working | Goal tree records (name, priority, progress, status, parent/children); progress roll-up = mean of children. | chat+daemon |
| CE/src/parts/goals/goal_persistence.nova | skimmed | 105 | Dead (tests only) | Serialize/deserialize goal list; repair parent links. | no |
| CE/src/parts/goals/planner.nova | reviewed | 169 | Dead (tests only) | "Planner" = string-prefix match on goal name ("write note ", "fetch ", "run ", "say ") -> operand tuple. | no |
| CE/src/parts/episodic/README.md | skimmed | 9 | Doc (stale) | Says "Pending". | no |
| CE/src/parts/episodic/consolidation.nova | reviewed | 137 | Dead (tests only) | Counts identical sorted trace-id signatures across episodes; marks episodes with count>=3 as CONSOLIDATED. | no |
| CE/src/parts/episodic/episode_storage.nova | reviewed | 238 | Working | Episode list with strength (decay multiply, +reinforce), tiers recent/archived/consolidated/dropped, cap on recent. | chat+daemon |
| CE/src/parts/episodic/moment_cache.nova | reviewed | 160 | Working (no unit test) | Reply cache: list of (10k-dim HDC key, reply, trace, ops); linear cosine scan, hit if >=0.9; move-to-front LRU; hit/miss counters. Source of mc_hits/mc_misses. | chat |
| CE/src/parts/episodic/moment_stream.nova | reviewed | 232 | Working | Append-only list of "moments" = {id, ts, modality, raw text, salience, trace ids, status}; status flips after 20 ticks. | chat+daemon |
| CE/src/parts/emotion/appraisal.nova | reviewed | 84 | Working | valence=clamp(500+(d+p+a)/6), arousal=mean|.|, label = arg-max of three inputs (joy/distress/pride/shame/liking/disliking). | chat+daemon |
| CE/src/parts/emotion/ocean_conditioning.nova | reviewed | 45 | Working | Linear shift of valence/arousal by 5 personality integers with fixed gains. | chat+daemon |
| CE/src/parts/emotion/plasticity_mod.nova | reviewed | 36 | Working | Maps valence/arousal/reward to a scalar "modulator" via pm_modulator. | chat+daemon |
| CE/src/parts/meta/README.md | skimmed | 9 | Doc (stale) | Says "Pending". | no |
| CE/src/parts/meta/gaps_register.nova | skimmed | 307 | Working | Bounded ring buffer of refusal events (holder, topic, reason) with counts by reason. | chat |
| CE/src/parts/meta/long_horizon_goals.nova | skimmed | 82 | Dead (tests only) | Adds progress to a goal; revisit salience = priority + staleness + horizon proximity. | no |
| CE/src/parts/meta/meta_observer.nova | skimmed | 542 | Working | Per-source counters of atoms crossing belief thresholds (promotion/atrophy rates); can bump a source host up/down a trust tier. | chat+daemon |
| CE/src/parts/meta/override_wire.nova | skimmed | 276 | Partial (rpc daemon only) | Audit-list wrapper around operator overrides with undo snapshot of (alpha,beta) and per-hour budget. | no |
| CE/src/parts/meta/reflection_loop.nova | skimmed | 197 | Working | Runs forward_sim from current conclusions, stores new ids as tentative Beta(2,1) atoms in a side KG; promotes when later percept matches the label. | chat |
| CE/src/parts/meta/self_improve.nova | reviewed | 422 | Dead (tests only) | Tabular Q-learning (alpha=1, deterministic) + epsilon-greedy on a toy gridworld; LCG rng; mints "rule" text atoms from the greedy policy. | no |
| CE/src/parts/meta/self_model_query.nova | skimmed | 74 | Working | String templates over soul name/mood ints, goal list, competence tiers ("I am X ..."). | chat |
| CE/src/parts/meta/theory_of_mind.nova | skimmed | 100 | Dead (tests only) | Key/value user properties stored as atoms with Beta counts; export/delete. | no |
| CE/src/parts/perception/README.md | skimmed | 37 | Doc | Describes percept record. | no |
| CE/src/parts/perception/perception_atoms.nova | skimmed | 315 | Working | Percept record (list of slots) constructors/accessors. | chat+daemon |
| CE/src/parts/perception/perception_module.nova | skimmed | 340 | Working | Orchestrator: calls classify_input + reader (+ fusion/lipsync for media) and stores a Percept; singleton per reader env. | chat+daemon |
| CE/src/parts/soul/README.md | skimmed | 9 | Doc (stale) | Says "Pending". | no |
| CE/src/parts/soul/constitution.nova | reviewed | 222 | Working | List of forbidden substrings / concept labels with severity; check = str_find of rule text in action text (plus neighbor-concept match). | chat+daemon |
| CE/src/parts/soul/goals_in_soul.nova | skimmed | 55 | Dead (tests only) | Copies [name,priority,status] goal summaries into the soul record. | no |
| CE/src/parts/soul/identity.nova | skimmed | 121 | Working | "Soul" = record {name, purpose, nature, 5 OCEAN ints, revision count}. | chat+daemon |
| CE/src/parts/soul/loyalty.nova | skimmed | 69 | Working | Named entities with integer levels; rank/dominant = sort by level. | chat+daemon |
| CE/src/parts/soul/state.nova | skimmed | 44 | Working | Mood = valence/arousal/attention/energy integers 0..1000, set by caller. | chat+daemon |
| CE/src/parts/soul/themes.nova | skimmed | 67 | Working | Named strings with a strength integer; reinforce adds, capped at 1000. | chat |
| CE/src/parts/soul/values.nova | skimmed | 51 | Dead (tests only) | name -> principle string map. | no |
| CE/src/parts/action/README.md | skimmed | 40 | Doc | Describes action part. | no |
| CE/src/parts/action/action_atoms.nova | skimmed | 534 | Dead (tests only) | Intent record (list of ~16 slots) constructors/accessors for SPEAK/FILE/HTTP/CODE/MCP/AUDIO intents; HTTP carries a "canned" body slot. | no |
| CE/src/parts/action/action_module.nova | skimmed | 686 | Dead (tests only) | Derives an Intent from ctx + motor_map lookup and submits through effector gate; HTTP dispatch pinned to simulated=1 with canned body (action_module.nova:493-496). | no |
| CE/src/parts/action/goal_templates.nova | skimmed | 237 | Dead (tests only) | Map goal-name -> operand template with %ID%/%NAME% string substitution. | no |
| CE/src/parts/action/motor_map.nova | skimmed | 255 | Dead (tests only) | Key/value registry: activation-signature string -> effector class; linear lookup. | no |
| CE/src/parts/action/operand_builder.nova | skimmed | 174 | Dead (tests only) | Synthesizes placeholder operands (e.g. /tmp/ce_goal_<id>.txt, "1 + <id>") per effector class. | no |
| CE/src/gates/README.md | reviewed | 9 | Doc (stale) | 9-line README saying gates are "Pending"; real code is substrate/gate_router.nova. | no |
| CE/src/scheduler/event_dispatch.nova | reviewed | 86 | Working | List-based priority queue of (kind,payload); O(n) max scan on drain. | chat+daemon |
| CE/src/scheduler/hybrid_scheduler.nova | reviewed | 105 | Working | hs_step: pop <=1 event, bump idle counter, run one substrate tick. | chat+daemon |
| CE/src/scheduler/realtime_pacer.nova | reviewed | 167 | Working | Sleeps the remainder of a 10ms/100ms tick budget; counts overruns. Uses inline asm imul. | chat+daemon |
| CE/src/scheduler/tick_loop.nova | reviewed | 59 | Working | Wraps tick engine with a "rate" field (100/10 Hz label only; no timing here). | chat+daemon |
| CE/src/kg/README.md | skimmed | 9 | Doc (stale) | Says "Pending". | no |
| CE/src/kg/ann_index.nova | skimmed | 482 | Working | Single-table LSH: 8 seeded random hyperplanes -> 256 buckets; query ranks bucket by cosine. | chat+daemon |
| CE/src/kg/atom_store.nova | reviewed | 677 | Working | Atom record (id, kind, label, payload k/v list, Beta(alpha,beta) milli counts, embed, xrefs, provenance); belief update = add to alpha or beta; 15-bit label hash. | chat+daemon |
| CE/src/kg/chain_compiler.nova | reviewed | 152 | Working (no unit test) | On /good: if two consecutive chain legs both have synapse weight >=500, add a direct A->C IMPLY operator labelled "cc:". | chat |
| CE/src/kg/competence_tracker.nova | skimmed | 270 | Working | Mean atom confidence / skill reliability / slot fill per domain -> CAPABLE/PARTIAL/AWARE/UNKNOWN tier. | chat+daemon |
| CE/src/kg/concept_layer.nova | skimmed | 368 | Working | Concept = member handles + slots; promote cluster if mean pairwise cosine > 0.7. | chat+daemon |
| CE/src/kg/cross_kg_references.nova | skimmed | 260 | Working | xref edge records; auto-link if cosine > threshold; "earned" after K co-activations; spawn-new-KG heuristic. | chat+daemon |
| CE/src/kg/episodic.nova | skimmed | 921 | Working | Tallies recurring sorted atom-id sets across recent moments; mints "episodic atom" (member ids + Beta counts) when count >= threshold; recall by member/window. | chat+daemon |
| CE/src/kg/gc_metrics.nova | skimmed | 326 | Working | Per-KG counters for GC events. | chat+daemon |
| CE/src/kg/graph_clustering.nova | skimmed | 760 | Working | Label-propagation community detection over xref edges (seeded LCG shuffle) + modularity. | chat |
| CE/src/kg/hdc_embed.nova | reviewed | 458 | Working | Hyperdimensional computing: 10,000-dim +/-1 vectors (one 64-bit int per element) from LCG seeded by FNV(label); bind=multiply, bundle=majority, permute=rotate, integer cosine. | chat+daemon |
| CE/src/kg/kg_router.nova | reviewed | 146 | Working (no unit test) | Table (topic_hash, shape_hash) -> hits and mean latency in ticks (always 0 in chat); kg label is the constant "reasoning". | chat |
| CE/src/kg/licenses.nova | skimmed | 152 | Working | Static table of 5 license codes -> flags. | chat+daemon |
| CE/src/kg/link_prediction.nova | skimmed | 587 | Working | Common-neighbours / Jaccard / Adamic-Adar scores over xref graph; top-k. | chat |
| CE/src/kg/louvain.nova | skimmed | 1131 | Working | Louvain modularity optimisation with aggregation levels over xref graph. | chat |
| CE/src/kg/multi_kg_manager.nova | reviewed | 963 | Working | KG = atom list indexed by id + 256-bucket label hash + kind index + premise/conclusion adjacency; registry of KGs by label; freelist/compaction. | chat+daemon |
| CE/src/kg/pagerank.nova | skimmed | 641 | Working | Power-iteration PageRank (integer) over xref graph. | chat |
| CE/src/kg/proofs.nova | skimmed | 134 | Working | Proof record table (claim, status, axioms, blob) + dependency invalidation. | chat+daemon |
| CE/src/kg/query.nova | skimmed | 2708 | Working | Hand-written tokenizer/parser/evaluator for a SPARQL-like subset (SELECT/WHERE/FILTER/OPTIONAL/UNION/ORDER/LIMIT/GROUP BY aggregates) by nested-loop joins. | chat+daemon |
| CE/src/kg/rule_explain.nova | skimmed | 567 | Working | Recursive walk of rule-engine derivation records into a proof tree text. | chat |
| CE/src/kg/rule_inference.nova | skimmed | 1123 | Working | Mini-Datalog: parse rules, naive fixpoint forward chaining with iteration cap. | chat |
| CE/src/kg/schemas.nova | skimmed | 226 | Dead (tests only) | Required/optional field + min/max validation over k/v lists. | no |
| CE/src/kg/semantic_search.nova | skimmed | 793 | Working | TF-IDF inverted index over atom labels with integer cosine ranking. (Lexical, not semantic.) | chat |
| CE/src/kg/skills_kg.nova | skimmed | 139 | Working | Skill atoms = trigger + ordered step list; reliability = Beta mean. | chat+daemon |
| CE/src/kg/temporal.nova | skimmed | 508 | Working | Allen interval relations between atoms from created/updated timestamps. | chat |
| CE/src/mind/bignum.nova | skimmed | 385 | Working | Base-10000 bignum add/sub/mul/compare. | chat |
| CE/src/mind/cascade.nova | skimmed | 67 | Working | When a proof is invalidated, unpin atoms whose proof is no longer VERIFIED. | chat |
| CE/src/mind/proof_serial.nova | skimmed | 315 | Working | Text serialisation/parsing of terms and proof trees. | chat |
| CE/src/mind/recheck.nova | skimmed | 175 | Working | Periodically re-runs kernel on a window of registered proofs; unpins on failure. | chat |
| CE/src/mind/search.nova | skimmed | 158 | Working | Saturating forward proof search to a budget; result re-checked by kernel. | chat |
| CE/src/mind/search_back.nova | skimmed | 106 | Working | Backward goal-directed proof search with depth budget. | chat |
| CE/src/mind/search_uni.nova | skimmed | 84 | Dead (tests only) | Backward search using unification to find universal instantiation. | no |
| CE/src/mind/unify.nova | skimmed | 133 | Dead (tests only) | First-order syntactic unification with occurs check. | no |
| CE/src/mind/verify.nova | skimmed | 1040 | Working | Small natural-deduction proof checker (axiom, and-I/E, MP, or-I, iff, hyp. syllogism, arithmetic eval, UI/EI/UG/EE). Only code that grants FORMAL grade. | chat |
| CE/src/learning/README.md | skimmed | 9 | Doc (stale) | Says "Pending". | no |
| CE/src/learning/ask_user_to_teach.nova | skimmed | 127 | Working | Rate-limited "ask user" decision; ingest answer as atom at Beta(4,1). | chat+daemon |
| CE/src/learning/atom_birth_monitor.nova | reviewed | 125 | Dead (tests only) | Counts signature recurrences; births an atom when freq>=5 (3 if surprise), >=3 distinct moments, max cosine to existing <0.9 (linear scan). | no |
| CE/src/learning/atom_death_monitor.nova | skimmed | 418 | Partial (sweep disabled in chat) | Two-phase GC: tombstone atoms with low activation + weak belief + unreferenced; remove next sweep. | chat |
| CE/src/learning/autonomous_research.nova | skimmed | 375 | Working (env-gated) | State machine: pop unknown-word trigger -> derive Wikipedia URL -> permit -> fetch -> ingest. Has a test-only body-injection seam. | chat+daemon |
| CE/src/learning/bayesian_updates.nova | reviewed | 119 | Dead (tests only) | Beta counts += tier weight (user 1.5, A 1.0, B 0.6, C 0.3) + EWMA conflict ratio. | no |
| CE/src/learning/belief_decay.nova | reviewed | 93 | Working | Sweep all atoms: alpha,beta <- 1 + r*(x-1) (pull toward uniform prior), skipping FORMAL/tombstoned. | chat |
| CE/src/learning/byzantine_aggregation.nova | skimmed | 387 | Working | Coordinate-wise trimmed mean / median over integer vectors. | chat |
| CE/src/learning/confidence_thresholds.nova | reviewed | 98 | Dead (tests only) | Fixed threshold table deciding "learning episode done". | no |
| CE/src/learning/corroboration.nova | reviewed | 108 | Working | claim -> list of distinct source labels; strong if >=2. Linear scans. | chat |
| CE/src/learning/dns_resolver.nova | reviewed | 217 | Working (insecure) | Hand-rolled DNS A query over UDP to 8.8.8.8; fixed txn id 0x1234, id not checked, no host-length bound on 512-byte buffer. | chat |
| CE/src/learning/entity_resolve.nova | skimmed | 194 | Working | Resolve mention: exact label -> alias table -> best HDC cosine over atoms. | chat |
| CE/src/learning/federated_aggregator.nova | skimmed | 1398 | Working (framework) | "Federated learning" = each node sends two Laplace-noised per-source rates; coordinator averages; local trust tier nudged by 90/10 blend. No model parameters are federated. | chat |
| CE/src/learning/formal_ingest.nova | skimmed | 90 | Working | Ingest a claim with a supplied derivation: license gate -> kernel check -> pin. | chat |
| CE/src/learning/forward_forward.nova | reviewed | 215 | Working (display-only live) | One dense ReLU layer, goodness = sum(a^2); update dW = +/- lr*a*x (Hebbian/anti-Hebbian), clamp +/-1000; seeded LCG init. Live output is only printed. | chat |
| CE/src/learning/internet_fetch.nova | skimmed | 454 | Working | Whitelist + rate-limit + cache gate; plain-HTTP in-process transport; https "deferred to scripts/learn.sh" (curl). | chat+daemon |
| CE/src/learning/learn_pipeline.nova | reviewed | 481 | Working | fetch -> strip HTML -> pattern triples -> create concept atoms + operator atoms. The real knowledge-acquisition path. | chat |
| CE/src/learning/learning_policy.nova | reviewed | 120 | Dead (tests only) | Hard-coded table labelling techniques PERMITTED/FORBIDDEN; enforces nothing. | no |
| CE/src/learning/maintenance.nova | reviewed | 146 | Working | Every N ticks run belief-decay sweep; optional GC sweep (off in chat). | chat |
| CE/src/learning/openie.nova | skimmed | 412 | Working | Rule-based subject-verb-object extractor with closed word lists (aux, prep, negation). | chat |
| CE/src/learning/plasticity_modulation.nova | reviewed | 55 | Working | modulator = clamp(1 + arousal + 0.5*reward + 0.3*|valence|, 0.2, 2.5). | chat+daemon |
| CE/src/learning/predictive_coding_runtime.nova | reviewed | 204 | Partial | error = actual - predicted; predictor = per-(ctx,node) EMA p += lr*(a-p). Live use: one scalar EMA of "arousal". | chat+daemon |
| CE/src/learning/preprocess.nova | skimmed | 904 | Working | HTML strip, sentence split, tokenize, stopwords, and 5 hard-coded "X is a/has/causes/part of Y" triple patterns. | chat |
| CE/src/learning/promotion.nova | skimmed | 221 | Working | Candidate -> promoted state machine with license/protected/grade gates. | chat+daemon |
| CE/src/learning/research_sources.nova | skimmed | 323 | Working | Builds candidate Wikipedia/Wiktionary/dictionary URLs for a topic; parses dictionary JSON fields. | chat |
| CE/src/learning/secure_aggregation.nova | reviewed | 1374 | Working (cryptographically weak) | Pairwise additive masks from a 15-bit LCG; optional DH whose private key is seeded from 15 bits of nanotime. | chat |
| CE/src/learning/self_learning_triggers.nova | skimmed | 194 | Working | Priority queue (max 8) of learning triggers; priority = weight*gap*alignment. | chat+daemon |
| CE/src/learning/source_authority.nova | skimmed | 193 | Working | Host -> tier table (A/B/C weights 1.0/0.5/0.2) with hard-coded default hosts; conflict resolution rules. | chat+daemon |
| CE/src/learning/source_whitelist.nova | skimmed | 62 | Working | Extract host from URL; membership in a hard-coded domain list. | chat+daemon |
| CE/src/seed/first_atoms.nova | reviewed | 421 | Working (hand-written data) | Hard-coded vocabulary lists (~570 words) + 43 hand-written operators (incl. the fever chain) + imagination patterns + 6 output templates. | chat+daemon |
| CE/src/seed/pack_registry.nova | skimmed | 156 | Working | Dispatch table of 4 seed packs + idempotency check by label. | chat |
| CE/src/seed/packs/code_review_pack.nova | skimmed | 213 | Working (hand-written data) | ~80 code-review words + 37 smell->remedy operators. | chat |
| CE/src/seed/packs/logic_pack.nova | skimmed | 205 | Working (hand-written data) | ~50 logic vocabulary words + 38 operators. | chat |
| CE/src/seed/packs/medical_pack.nova | skimmed | 151 | Working (hand-written data) | ~60 hand-written medical words + 11 operators. | chat |
| CE/src/seed/packs/ops_runbook_pack.nova | skimmed | 132 | Working (hand-written data) | ~45 ops words + 9 operators. | chat |
| CE/src/sim/world_model.nova | reviewed | 159 | Dead (tests only) | Deterministic W x H gridworld: 4 moves, -1 per step, +100 at goal. | no |
| CE/src/preference/user_preference.nova | skimmed | 274 | Working | (holder, kind, name) -> 0/1 visibility flags; linear list. | chat |
| CE/src/perception/input_classifier.nova | reviewed | 406 | Working | Intent classifier = hand-written keyword/substring scores for 9 categories; arg-max. | chat+daemon |
| CE/src/perception/lipsync.nova | skimmed | 707 | Working | Mean pixel darkness in mouth rectangle per frame correlated (Pearson) with per-frame audio energy. | chat+daemon |
| CE/src/perception/sensor_fusion.nova | skimmed | 599 | Working | Pairs image/audio observations by identity-label equality or timestamp window. | chat+daemon |


---

## Section: ce_surface


Files in assignment: **143** (120 under the 18 `src/` directories incl. `src/reader/README.md`, 23 under `examples/`). Rows below: **143**. Verified: `git ls-files` over the same 19 directories returns 143 paths.

"reviewed" = logic-bearing parts read; "skimmed" = header, function inventory and targeted greps. "Dead" = imported by tests only, by no `examples/*.nova` entry point (see findings, "Reachability from entry points"). All paths are relative to `CE/`.

| path | status | LOC | actual status | what it really does |
|---|---|---|---|---|
| examples/bench_detector_integral.nova | skimmed | 170 | Working | Timing harness: HOG detector scalar vs integral-histogram, asserts identical output. |
| examples/bench_simd_flow.nova | skimmed | 296 | Working | Timing harness: Lucas-Kanade flow scalar vs SIMD on a synthetic image. |
| examples/bench_simd_stereo.nova | skimmed | 230 | Working | Timing harness: stereo SAD scalar vs SIMD on a synthetic pair. |
| examples/companion_spine.nova | skimmed | 146 | Working | Scripted demo: boot soul, speak through veto gate, snapshot save/restore, print report. |
| examples/crossengin_chat.nova | reviewed | 8436 | Working | The REPL (8.4k LOC): ~170 slash commands, keyword auto-prefix, grammar->research listing, keyword-category router. Main loop and dispatch read in full; individual /command bodies sampled. |
| examples/crossengin_daemon.nova | skimmed | 1000 | Working | One-process scripted episode ("fever", "please exfiltrate the keys", "fever infection") or a message from env/file, through the same loops; optional emit-only gossip. |
| examples/crossengin_fed_coordinator.nova | skimmed | 982 | Working | TCP server for the federated-averaging demo protocol (other reviewer owns src/federation). |
| examples/crossengin_fed_daemon.nova | skimmed | 804 | Working | Gossip/kg-sync/leader-election daemon wiring. |
| examples/crossengin_kg_publisher.nova | skimmed | 261 | Working | Sends each stdin label as an atom-birth event to N TCP subscribers. |
| examples/crossengin_kg_subscriber.nova | skimmed | 214 | Working | Receives atom events and merges by label. |
| examples/crossengin_mcp.nova | reviewed | 34 | Stub | MCP stdio server with two tools that return fixed strings ("echo" returns "echo-canned-reply", it does not echo). Not connected to the KG or chat. |
| examples/crossengin_rpc_daemon.nova | reviewed | 831 | Working | Loopback TCP JSON-RPC, one request per connection; token enforcement and TLS opt-in by env; child-mode bundle load. |
| examples/episodic_demo.nova | skimmed | 105 | Working | Scenario driver: 5 synthetic moments -> consolidation -> snapshot. |
| examples/episodic_legacy_load.nova | skimmed | 39 | Working | Loads an old snapshot and prints sub-list count. |
| examples/episodic_recall_demo.nova | skimmed | 80 | Working | Scenario driver for /recall. |
| examples/graph_clustering_demo.nova | skimmed | 130 | Working | Label propagation on a synthetic barbell graph. |
| examples/kernel_selfcheck.nova | skimmed | 94 | Working | Boots node pool, injects a stimulus, checks a node fired and activity propagated; prints OK. |
| examples/migrate_schema.nova | skimmed | 148 | Working | Atom-shape migration driver. |
| examples/migrate_snap.nova | skimmed | 188 | Working | Snapshot v1->v2 converter. |
| examples/semantic_search_demo.nova | skimmed | 107 | Working | TF-IDF search over a 10-document fixture. |
| examples/snap_keygen.nova | skimmed | 52 | Working | Generates an Ed25519 keypair to two files. |
| examples/voice_conversation.nova | skimmed | 575 | Partial | Library (no main) behind /converse: external whisper.cpp/vosk STT -> 3 regex question shapes -> KG query -> formant TTS. STT is a pretrained neural model outside the repo. |
| examples/voice_dialog.nova | skimmed | 2560 | Partial | Library (no main) behind /dialog: multi-turn wrapper around the above with follow-up phrase patterns. |
| src/agent/autonomous_loop.nova | skimmed | 616 | Dead | Test-only (not imported by any example): grid-world TD value-table agent + ingest + audit in one cycle. This is the "P5 bounded self-improvement" agent; no shipped binary runs it. |
| src/agent/cognitive_router.nova | reviewed | 846 | Working | The chat reply generator: switch on keyword category -> canned sentence templates; for "academic/unknown/procedural/financial" greedy <=3-hop walk over causal/imply edges from any recognised word and print "A leads to D (A->B->C->D)". /good,/bad add +/-1 Beta observation and +/-100 to an edge weight. |
| src/agent/cowork_planner.nova | reviewed | 203 | Stub | Substring-matches ~domain trigger words in a task description and prints one line per hit; self-described "print-only", no execution, no dependencies computed in practice (all "-" in the run). |
| src/agent/formal_chat.nova | skimmed | 1101 | Working | Glue from /axiom,/imply,/derive,/and,/hs,/iff,/calc,/forall,/fact,/syllogism,/retract to the proof kernel in src/mind; keeps a label->term table; save/restore to a text file. |
| src/agent/ingestion_agent.nova | skimmed | 297 | Working | Holds whitelist + format registry + review queue; routes parsed records either straight to the pipeline (trusted source prefix) or to the queue. |
| src/agent/loop_action.nova | skimmed | 152 | Dead | Test-only: picks one of three canned utterance templates (ack / not-understood / silence). |
| src/agent/loop_coordination.nova | skimmed | 130 | Working | A 12-slot list ("blackboard") with getters/setters and a fixed loop order table. |
| src/agent/loop_emotion.nova | reviewed | 29 | Working | One function: calls appraisal + OCEAN conditioning, stores two integers (valence, arousal). |
| src/agent/loop_goals.nova | reviewed | 24 | Working | One function: calls drive generator + arbitration, stores the winning goal id. |
| src/agent/loop_imagination_idle.nova | reviewed | 72 | Partial | If idle flag set, runs a 3-step forward simulation and returns a count; chat never sets idle, so it does not run there. |
| src/agent/loop_memory.nova | skimmed | 86 | Working | Appends the input as a "moment" + "episode" record; periodic co-occurrence consolidation. |
| src/agent/loop_perception.nova | reviewed | 55 | Working | One function: runs the reader on the input and returns matched-token count. |
| src/agent/loop_reasoning.nova | reviewed | 38 | Working | For each percept concept, depth-3 forward chain; union of conclusions stored on the blackboard. |
| src/agent/tool_goal_plan.nova | skimmed | 192 | Dead | Test-only: converts a hand-built goal tree into a list of tool steps. |
| src/agent/tool_use.nova | reviewed | 247 | Dead | Test-only: executes plan steps; "code exec" = arithmetic evaluator, HTTP tool always simulated (returns canned string), MCP tool returns its configured string. |
| src/agents/agent_manifest.nova | skimmed | 334 | Working | Record + text parser for a named list of capsule/skill/pattern dependencies. |
| src/agents/agent_registry.nova | skimmed | 240 | Working | List registry with registered/installed/retired flags and dependency presence checks. |
| src/agents/agent_run.nova | skimmed | 338 | Partial | Runs each listed skill in order and returns the first result above a confidence threshold. Reachable only via RPC verb agent.run. |
| src/audit/audit_reader.nova | skimmed | 71 | Dead | Test-only: chain verify + plain-language rendering of log entries. |
| src/audit/audit_writer.nova | skimmed | 77 | Working | Append INTENT then OUTCOME entry around an effector call. |
| src/audit/decision_log.nova | skimmed | 536 | Working | Append-only list with a polynomial rolling hash chained entry to entry (file states it is not cryptographic); optional file persistence. |
| src/bench/bench_bank_ext.nova | skimmed | 183 | Dead | Test-only: 24 more hand-written kernel-checkable items. |
| src/bench/calibration.nova | skimmed | 146 | Dead | Test-only: bins (stated confidence, outcome) pairs and computes calibration error. |
| src/bench/llm_transcript.nova | skimmed | 163 | Partial | Parser for "<id> affirm\|deny" lines. Only tests call it; the shipped data file is itself labelled "illustrative". |
| src/bench/reasoning_bench.nova | reviewed | 408 | Fake | 12 hand-written items the proof kernel checks (real, but the kernel is checking items written to fit it). The "/vs" LLM comparison scores verdicts synthesised by an if-statement (bench_default_pairs), yet prints "LLM correct: 9/12". |
| src/capsules/capsule.nova | skimmed | 152 | Working | Named record listing atom refs + deps + license + installed flag. |
| src/capsules/capsule_dep.nova | skimmed | 163 | Working | Semver parse/compare and DFS topological sort with cycle refusal. |
| src/capsules/capsule_registry.nova | skimmed | 217 | Working | List registry; install in dependency order. |
| src/capsules/pattern_capsule.nova | reviewed | 456 | Working | (trigger words -> advice string) tables; two built-in tables (12 debugging + 5 research-hygiene entries); token-subset matcher. |
| src/capsules/style_capsule.nova | skimmed | 316 | Working | Record of ~30 wording strings the templater reads; a few built-in styles. |
| src/chat/fed_slash.nova | skimmed | 502 | Working | Pure argument parsers and output-line formatters for the /gossip_* and /leader commands. |
| src/chat/helpers.nova | reviewed | 689 | Working | String helpers: command split, cache-tag sanitiser (basename + [A-Za-z0-9_-]), self-identity phrase matcher (exact/prefix list), pronoun replacement ("it/they" -> last topic word). |
| src/data/json.nova | skimmed | 307 | Working | Recursive-descent JSON parser into tagged lists (used by /define and JSON importer). |
| src/data/pdf_text.nova | skimmed | 292 | Dead | Test-only: scans BT..ET blocks for (..)Tj / [..]TJ literals in uncompressed PDFs. |
| src/data/table.nova | skimmed | 318 | Dead | Test-only: CSV / Markdown-pipe table parser -> row atoms. |
| src/editions/edition_gate.nova | skimmed | 155 | Dead | Test-only: static 3-edition x N-feature boolean matrix. Nothing in any binary consults it. |
| src/factory/agent_bundle.nova | skimmed | 231 | Working | Reads header lines / signer-pk trailer / section counts from a bundle file for /agent list\|info. |
| src/factory/bake.nova | reviewed | 600 | Partial | "Mother bakes child": concatenates text sections (personas, ownership, policies, patterns, skill names, agents, filtered KG atoms as "ATOM ..." lines) and appends an Ed25519 signature + signer pk. Verification against a pinned key is real. The #KG section it writes is not read back by the child loader. |
| src/factory/bake_manifest.nova | skimmed | 379 | Working | Text recipe parser: allow-lists of capsule/skill/pattern/persona/policy names and KG source prefixes. |
| src/factory/child_mode.nova | reviewed | 430 | Partial | Reads bundle path + base64 anchor key from env, verifies signature, returns text; table of RPC verbs refused in child mode; fingerprint state file. |
| src/factory/kg_filter.nova | skimmed | 194 | Working | Per-atom predicate: capsule membership OR KG-label prefix OR license code. |
| src/factory/update_delta.nova | skimmed | 1340 | Working | Signed text delta (+ATOM/-ATOM/+CAPSULE... lines) between two watermarks with parent-fingerprint chaining; apply side does mutate the KG. |
| src/ingest/curriculum.nova | skimmed | 268 | Working | Canonical record shape (kg, source, atoms, implications, observations, citations) + validator. |
| src/ingest/importers/audio_records.nova | skimmed | 308 | Working | WAV/RIFF header reader -> one metadata record (rate, channels, duration, hash). |
| src/ingest/importers/conceptnet.nova | skimmed | 258 | Working | Tab-separated ConceptNet assertion rows -> atoms + relation implications. |
| src/ingest/importers/csv_facts.nova | skimmed | 277 | Working | CSV with header: first column -> atom, other columns -> implication to a column-value atom. |
| src/ingest/importers/image_records.nova | skimmed | 359 | Working | PNG IHDR / JPEG SOF header reader -> one metadata record (dims, hash). No pixel understanding. |
| src/ingest/importers/json_records.nova | skimmed | 407 | Working | JSON array of record objects -> curriculum records. |
| src/ingest/importers/nt_triples.nova | skimmed | 368 | Working | N-Triples line parser -> atoms (URI tail as label) + implications. |
| src/ingest/importers/paper_meta.nova | skimmed | 283 | Working | Tab-separated title/authors/year/abstract -> one record per paper. |
| src/ingest/importers/records.nova | skimmed | 448 | Working | .cerec line format parser (KG/SRC/ATOM/IMP/OBS/CITE/CAPSULE directives). |
| src/ingest/importers/video_records.nova | skimmed | 255 | Working | Y4M header reader -> one metadata record. |
| src/ingest/importers/wikidata.nova | skimmed | 229 | Working | N-Triples with optional Q/P label lookup file. |
| src/ingest/importers/wordnet.nova | skimmed | 190 | Working | Simple SYNSET/HYPERNYM/ANTONYM line file -> atoms + relations (not the real WordNet DB format). |
| src/ingest/importers/yaml_records.nova | skimmed | 972 | Working | Hand-written YAML subset parser -> curriculum records. |
| src/ingest/llm_extractor.nova | reviewed | 161 | Working | Reads a .cerec file an external LLM produced; rewrites source tag to src:extractor:llm:*, caps belief at 800, downgrades FORMAL to EMPIRICAL, forces everything into the review queue. |
| src/ingest/pattern_pack.nova | skimmed | 493 | Working | Parses a .cerec-shaped file into trigger->advice pattern tables. |
| src/ingest/perceptual_capsule.nova | skimmed | 290 | Working | Record shape for image/audio/video metadata atoms (modality tag, blob hash, dims). |
| src/ingest/pipeline.nova | skimmed | 361 | Working | Turns a validated record into atoms + implication atoms in the named KG, attributes source. |
| src/ingest/policy.nova | skimmed | 368 | Working | Ordered predicate->action rules that auto-approve/deny review-queue entries. |
| src/ingest/review_queue.nova | skimmed | 177 | Working | List of pending/approved/denied records with reasons. |
| src/ingest/source_registry.nova | skimmed | 125 | Working | format name -> parser tag table. |
| src/ingest/web_scheduler.nova | skimmed | 231 | Dead | Test-only: whitelist-gated fetch loop taking a caller-supplied fetch function (stub in tests). |
| src/language/arithmetic.nova | reviewed | 355 | Working | Tokenises digits/operators/number-words in a sentence and evaluates + - * / and "N% of M" in x1000 fixed point; used by router arithmetic category and /calc. |
| src/language/nl_audit.nova | skimmed | 42 | Working | Wrapper: calls nlq_respond and, if answer flagged contested, appends a record to the decision log. |
| src/language/nl_generate.nova | skimmed | 220 | Working | String templates: a/an by first vowel, naive pluralise (+s/+es), "X leads to Y" clause rendering, underscore->space. |
| src/language/nl_query.nova | reviewed | 630 | Partial | Keyword-set question classifier (yes/no, what, why, how-many) + label lookup of strongest outgoing/incoming operator; only yes/no and how-many forms are consulted on the chat path (cognitive_router.nova:646-651), and only after the grammar parser has declined the line. |
| src/language/number_words.nova | skimmed | 348 | Working | English number-word table ("three hundred", "a dozen") -> milli integer; unit-name canonicaliser. |
| src/language/phoneme_atoms.nova | skimmed | 69 | Working | CRUD for atoms tagged LPHONEME (a string symbol); attaches a phoneme-id list to a word atom. |
| src/language/syntax_atoms.nova | skimmed | 87 | Working | Atoms holding an ordered list of role names; syntax_apply fills slots from an intent list. Chat uses two patterns ("ack","see_topic") only in the legacy fallback. |
| src/language/word_atoms.nova | reviewed | 558 | Working | Language-KG word store: lowercase normalise, exact lookup, ~100-entry irregular-form table + suffix stripping (s/es/ed/ing/ly) for lemma fallback, per-word gloss string, sense xrefs, Beta-belief counter. |
| src/nl/executor.nova | reviewed | 362 | Partial | Maps a parsed query kind to an action. RESEARCH, RELATE, CONTRADICT_SCAN and IS_A all collapse to the same call: join the slot words and run the "research" skill (label substring listing). Admin kinds are handed back to the caller. |
| src/nl/grammar_parser.nova | reviewed | 1435 | Working | ~45 hand-written English prefix/infix/suffix token patterns tried in fixed order after stripping polite preambles; yields one of 11 query kinds or UNPARSED. No grammar in the linguistic sense. |
| src/nl/intent_adaptive.nova | skimmed | 151 | Partial | Per-category bundled bag-of-words hypervector, updated only by /good; overrides the keyword classifier when cosine >= 0.5. |
| src/nl/llm_parser.nova | skimmed | 295 | Working | Parses the "KIND x / ARG y" text an external LLM script prints into a query record; validates arity. |
| src/nl/nl_intent_classifier.nova | reviewed | 1130 | Working | Bag-of-words nearest-prototype classifier: random +/-1 10k-dim vector per token, majority-bundle per utterance, cosine vs 10 prototypes built from an embedded hand-written phrase list; then strips "signal words" to fill slots. |
| src/nl/nl_llm_sidecar.nova | reviewed | 517 | Partial | Env-gated fork+exec of scripts/nl_parse_llm.sh (ollama / llama.cpp / OpenAI curl) with the user text as argv. Off by default. On the audited toolchain the pipe2 shim passes a tagged pointer and fails with EFAULT, so the live path cannot work; only TESTMODE (canned wire from an env var) works. |
| src/nl/nl_metrics.nova | skimmed | 262 | Working | Per-holder integer counters (total, unparsed, classifier hit/miss, LLM attempts). |
| src/nl/nl_pipeline.nova | reviewed | 66 | Working | 13 lines of logic: if grammar UNPARSED try the prototype classifier, else the LLM sidecar. |
| src/nl/ollama_spawn.nova | reviewed | 42 | Working | fork + execve(script, argv) + waitpid. No shell, no pipe. Used by /ingest_ollama and /learn_prepare. |
| src/nl/query_shape.nova | skimmed | 266 | Working | Record constructors/accessors/arity validator for the 11 query kinds. |
| src/nl/reply_composer_ollama.nova | reviewed | 278 | Partial | Env-gated (CE_OLLAMA_COMPOSER=1) fork+exec of scripts/llm_compose.sh to have an LLM reword the templated reply; output replaces the reply with no marker. Observed under strace: writes /tmp/crossengin_compose_in.txt then never forks, so it is inert on this toolchain. |
| src/nl/rpc_server.nova | skimmed | 237 | Working | One JSON line in -> rpc_dispatch -> one JSON line out; hand-rolled encoder/escaper. |
| src/nl/rpc_verbs.nova | skimmed | 5277 | Working | ~55 JSON-RPC verbs (5.3k LOC, skimmed: dispatch table, ingest.file, session name checks): thin wrappers over registries (skills, capsules, personas, tokens, snapshots, bake/delta, agents). Token enforcement only when the daemon sets it. |
| src/nl/templater.nova | skimmed | 415 | Working | Deterministic string rendering of a skill result (atom list, "Sources cited", disagreement block, confidence trailer) with wording knobs from a style record. |
| src/persona/persona.nova | skimmed | 364 | Working | Per-user record: name, 5 OCEAN ints, valence/arousal, risk ints, history/preference/reflection lists; setters clamp 0..1000. |
| src/persona/persona_export.nova | skimmed | 424 | Working | Line-based text serialise/parse of the persona record. |
| src/persona/persona_project.nova | skimmed | 283 | Working | Token-overlap between a proposal text and stored history/preferences -> advisory integers (risk score etc.). Never alters the reply. |
| src/persona/persona_registry.nova | skimmed | 113 | Working | One-per-user list registry. |
| src/reader/README.md | reviewed | 9 | Doc | Nine-line description of the five reader stages. |
| src/reader/cofire_index.nova | skimmed | 298 | Working | Pair-count table: how many moments two atom ids co-occurred in; neighbours by count. |
| src/reader/coherence_check.nova | skimmed | 88 | Working | Counts xref edges among active atoms / active count (milli); accept if above threshold and no unknown tokens. |
| src/reader/context_bias.nova | skimmed | 111 | Working | Picks the word sense whose concept vector is closest to the centroid of context concepts; else highest-weight sense. |
| src/reader/fetch_route_learn.nova | skimmed | 61 | Partial | Sets symbolic route names and a "learn trigger" flag on the read context; does not itself fetch or learn. |
| src/reader/lexical_anchor.nova | skimmed | 210 | Working | Whitespace/punctuation tokeniser + exact/morph lookup of each token in the word store; emits matched/unmatched lists. |
| src/reader/neighborhood.nova | skimmed | 677 | Working | Additive neighbour scoring from operator edges, xrefs, shared word senses, co-fire counts and slot fills (clamped 0..1000); env-tunable depth/fanout. |
| src/reader/reader.nova | skimmed | 60 | Working | Calls the five stages in order and returns the context record. |
| src/reader/slot_index.nova | skimmed | 284 | Working | Histogram of which atom ids filled each (pattern, role) slot; similarity = shared-slot count normalised. |
| src/reader/spreading_activation.nova | skimmed | 201 | Working | Bounded-hop activation spread over xref edges with per-hop decay; threshold selects the active set. |
| src/sandbox/capability.nova | reviewed | 843 | Working | Bearer-token registry: token = random 32-hex id + holder + list of permission strings + expiry + per-window request counter. Not cryptographic tokens (no signature/MAC); lookup by string equality. verb -> required-permission table. Inert unless CE_RPC_REQUIRE_TOKEN=1. |
| src/sandbox/holder_rate.nova | skimmed | 281 | Working | Per-holder request counter per time window. |
| src/sandbox/ownership.nova | skimmed | 274 | Working | (kind,name)->owner table used to filter list verbs. |
| src/sandbox/session_snapshot.nova | reviewed | 1692 | Working | Text serialise/parse of persona, ownership, trust-anchor, token, policy, pattern, skill, preference, agent registries. Recognises 9 section markers; "#KG v1" is not one of them. |
| src/sandbox/skill_signature.nova | skimmed | 324 | Working | Canonicalises a skill manifest to text, Ed25519 sign/verify against a trust-anchor list. Signs the manifest only (skills have no shippable code). |
| src/session/session.nova | skimmed | 517 | Working | Bundles soul/KGs/log/scheduler handles into a record keyed by id; registry + /switch support. |
| src/skills/skill_dispatch.nova | skimmed | 137 | Working | switch on integer policy_id -> one of three compiled-in functions; wraps with refusal checks. |
| src/skills/skill_manifest.nova | skimmed | 150 | Working | Record of name/version/deps/effector names/refusal conditions. |
| src/skills/skill_registry.nova | skimmed | 229 | Working | List registry with install flag; install checks capsule deps are installed. |
| src/skills/skill_supervisor.nova | skimmed | 333 | Working | Holds references + counters; builds the result record; attaches persona projection. |
| src/skills/skills/coding_helper.nova | reviewed | 194 | Stub | Matches 12 hard-coded debugging trigger phrases ("null pointer", "race condition"...) and prints the paired advice sentence. Writes no code, runs no code; "write a python function" -> "no debug pattern matched" (executed). |
| src/skills/skills/echo_skill.nova | skimmed | 217 | Working | Lists atoms whose label contains a query token. |
| src/skills/skills/research_skill.nova | reviewed | 304 | Working | Lists atoms whose label contains a topic token across KGs, plus cross-KG belief spread. No fetching, no synthesis. This is what every grammar-parsed question returns. |
| src/util/chat_cli_polish.nova | skimmed | 302 | Working | JSON-mode/colour/history-file helpers for the REPL. |
| src/util/env_resolve.nova | skimmed | 140 | Working | getenv-with-default helpers shared by daemons. |
| src/util/gen_id.nova | skimmed | 68 | Working | Monotonic counter used as a rebuild guard. |
| src/util/list_safe.nova | skimmed | 36 | Working | list_remove replacement (works around a Nova tagged-index bug). |
| src/util/mem_safe.nova | skimmed | 45 | Working | Byte-loop memcpy (works around Nova memcpy_raw not untagging). |
| src/util/str_safe.nova | skimmed | 99 | Working | Byte-wise string equality/find (works around flaky Nova str_eq). |
| src/util/sys_tagged.nova | skimmed | 127 | Working | Inline-asm read/write wrappers that untag count and re-tag the return. |
| src/util/type_safe.nova | skimmed | 51 | Working | type_of probes. |


---

## Section: ce_security


Row count: **125** files. Verified against `git -C /home/user/Crossengin-demo ls-files`: src/federation 24, src/safety 34 (33 .nova + README), src/net 14, src/persistence 10, infra 22, web 3, .devcontainer 3 = 110 directory files (all present, none missing), plus 10 assigned scripts, LICENSE, .gitignore and 3 key-like files under docs/. Other `*.example`/`*.conf` files are inside infra/ and counted there.

"reviewed" = read in full or all non-comment code read. "skimmed" = header contract, function list, and targeted greps (RNG, sockets, file I/O, stubs, compare loops) read; done for long codec files whose bodies are repetitive byte-packing and whose behaviour is pinned by the unit tests I executed. "(test-only)" = no file under CE/examples imports it, directly or transitively (import-graph walk, CE/examples/*.nova).

Additional files read because the assignment questions depend on them (not in my row count): CE/src/learning/secure_aggregation.nova, CE/src/learning/federated_aggregator.nova, CE/src/io/transducers/noise_xk.nova, CE/src/io/transducers/tls13_client.nova (parts), CE/src/sandbox/capability.nova (parts), CE/src/nl/rpc_verbs.nova (dispatcher + file verbs), CE/src/parts/soul/constitution.nova (check fn), CE/examples/crossengin_rpc_daemon.nova, crossengin_fed_daemon.nova (parts), crossengin_chat.nova (gate + command dispatch), NOVA/src/compiler/codegen.nova (secure_random).

| path | status | LOC | actual status | what it really does |
|---|---|---|---|---|
| CE/src/federation/raft_core.nova | reviewed | 216 | Working (test-only) | Pure in-memory Raft rules (term, vote, append, majority commit) on lists; no network/timers; imported only by tests. |
| CE/src/federation/raft_cluster.nova | reviewed | 181 | Working (test-only) | Loops over N in-process raft_core nodes delivering votes/appends synchronously; a simulation harness. |
| CE/src/federation/raft_membership.nova | reviewed | 106 | Working (test-only) | Joint-consensus majority arithmetic over lists of node ids; no log, no RPC. |
| CE/src/federation/raft_partition.nova | reviewed | 114 | Working (test-only) | In-process partition simulator: delivers calls only to a member subset, counts majority vs full cluster. |
| CE/src/federation/snapshot_broadcast_hook.nova | skimmed | 125 | Working | Glue: after snapshot save, builds a signed attestation tuple and calls gossip broadcast (opt-in env, daemon only). |
| CE/src/federation/ice.nova | skimmed | 436 | Partial (test-only) | ICE candidate list + RFC 8445 priority formulas + pair state enum; connectivity check `ice_check_pair` is a stub returning 0. |
| CE/src/federation/snapshot_attestation.nova | skimmed | 553 | Working | Formats/parses/verifies `soul_id|ts|merkle_root|ed25519 sig` tuples and keeps a per-soul latest table. |
| CE/src/federation/leader_election.nova | reviewed | 571 | Partial | "Bully": queues ELECTION/OK/VICTORY in an outbox nobody drains; effective result = highest id among locally gossip-alive peers after a timeout. |
| CE/src/federation/distributed_query.nova | skimmed | 608 | Working | Sends a mini-SPARQL query line to each gossip-alive peer over TCP, merges rows with provenance; unauthenticated. |
| CE/src/federation/snapshot_replication.nova | skimmed | 609 | Working | Tracks observed attestations, serves/fetches snapshot bytes by merkle root over gossip TCP, checks root on receipt. |
| CE/src/federation/webrtc.nova | reviewed | 649 | Stub (test-only) | SDP offer/answer string builder/parser with placeholder ufrag/pwd/fingerprint; rtc_send/rtc_recv return "needs DTLS" error. |
| CE/src/federation/kg_sync.nova | skimmed | 677 | Working | KG delta protocol: per-KG revision counter, KG_DELTA_REQ/RESP text lines (INS/UPD/RETR), 256KB cap. |
| CE/src/federation/ice_turn.nova | skimmed | 717 | Partial (test-only) | State glue between ICE agent and TURN client codec (relay candidate escalation); no live sockets. |
| CE/src/federation/gossip_relay_secure.nova | skimmed | 965 | Working (test-only) | Wraps relay payloads in the Noise-XK-derived ChaCha20-Poly1305 session; only tests import it. |
| CE/src/federation/gossip_relay.nova | skimmed | 976 | Working | RELAY_REQ/DATA/ACK text lines so peer A can ask peer C to forward to B over TCP; plaintext, unauthenticated. |
| CE/src/federation/srtp.nova | skimmed | 998 | Working codec (test-only) | SRTP AES-CM-128 + HMAC-SHA1-80 packet protect/unprotect + key derivation + replay window; RFC 3711 vectors; no media path uses it. |
| CE/src/federation/turn_server.nova | skimmed | 1289 | Partial (test-only) | TURN server allocation state machine as pure functions on byte buffers; no socket I/O, no data forwarding. |
| CE/src/federation/stun_rfc8489.nova | skimmed | 1300 | Working codec (test-only) | STUN message encode/decode, MESSAGE-INTEGRITY (HMAC-SHA1), FINGERPRINT (CRC32); RFC 5769 vectors. |
| CE/src/federation/nat_traversal.nova | skimmed | 1475 | Partial (test-only) | STUN-like external-address query over TCP text or UDP; NAT type guess from two answers; `nat_hole_punch` returns 0 (stub). |
| CE/src/federation/gossip_dtls_shim.nova | skimmed | 1510 | Partial | Non-standard "DTLS records over TCP with 2-byte length prefix" wrapper for gossip; self-interop only; opt-in CE_FED_TRANSPORT=dtls. |
| CE/src/federation/distributed_rules.nova | skimmed | 2243 | Working | Mini-Datalog rule/derivation exchange between gossip peers (RULE/DERIV/DRFETCH lines) over TCP; unauthenticated. |
| CE/src/federation/turn.nova | skimmed | 2768 | Working codec (test-only) | TURN (RFC 5766) message codec + client allocation state machine + long-term credential (MD5 key, HMAC-SHA1); no live relay. |
| CE/src/federation/gossip.nova | reviewed | 3657 | Working | SWIM-like membership + KG delta gossip over short-lived plaintext TCP connections; xorshift peer pick; optional Noise/DTLS wrappers; no auth by default. |
| CE/src/federation/dtls12.nova | reviewed | 4331 | Partial | DTLS 1.2 record/handshake codec, ECDHE-ECDSA-AES128-GCM flights, cert chain verify, replay window; no UDP transport, no retransmit timers, no cookie exchange; 5 dead *_R29B2_STUB fns. |
| CE/src/safety/README.md | reviewed | 14 | Doc | 14-line status note for the safety directory. |
| CE/src/safety/reversibility_classifier.nova | reviewed | 72 | Working | Constant table: 10 action-type ints -> reversible/recoverable/irreversible. |
| CE/src/safety/safety_log.nova | reviewed | 86 | Working | Appends an "attest cap -> allow/deny" record to the decision log; renders/list them. |
| CE/src/safety/approval_prompt.nova | reviewed | 89 | Working | Prints "approve? [y/N/why]" and reads a line from stdin; y/yes = approve. |
| CE/src/safety/permission_tiers.nova | reviewed | 91 | Working | Constant table action-type -> auto/notify/approve, max() with reversibility floor. |
| CE/src/safety/constitutional_filter.nova | reviewed | 113 | Working | Decision ladder (veto > halted > tier); veto = case-sensitive substring match of rule text in input, or KG-neighbor match of a concept label. |
| CE/src/safety/override_mechanism.nova | reviewed | 144 | Working | Sets halt/kill flags in a 4-slot list, overwrites an atom alpha/beta, marks goal subtree vetoed; writes audit entries. |
| CE/src/safety/capability_gate.nova | reviewed | 164 | Working | Pure function (capability int, 4 context flags) -> allow/require_approval/deny via if-chain. |
| CE/src/safety/rsa.nova | skimmed | 191 | Working | RSA signature VERIFY only (PKCS#1 v1.5 + PSS, SHA-256) on bn2048; 5 checks vs one openssl-made vector. |
| CE/src/safety/pem_truststore.nova | skimmed | 201 | Working | Splits a PEM bundle, base64-decodes, extracts RSA/EC public keys as trust anchors; directory mode needs a manifest file (TODO readdir). |
| CE/src/safety/hkdf_sha256.nova | skimmed | 210 | Working | HKDF extract/expand over HMAC-SHA256; RFC 5869 vectors. |
| CE/src/safety/cap_session.nova | reviewed | 213 | Working | Per-session allow/deny override array per capability + parser for `cap = allow|deny` config file. |
| CE/src/safety/x25519.nova | skimmed | 219 | Working | X25519 Montgomery ladder on field25519; RFC 7748 vectors. |
| CE/src/safety/ecdsa.nova | reviewed | 295 | Working | ECDSA P-256 verify (range check r,s in [1,n-1]; no low-s rule); RFC 6979 A.2.5 vectors; verify only. |
| CE/src/safety/chacha20_poly1305.nova | skimmed | 296 | Working | RFC 8439 AEAD seal/open with XOR-fold tag compare; RFC vectors. |
| CE/src/safety/p256_keypair.nova | skimmed | 310 | Working | Reads/writes raw 32-byte P-256 private + 33-byte public key files. |
| CE/src/safety/rng.nova | reviewed | 322 | Partial | RNG interface: OS backend (always fails on Linux x86-64 because NOVA secure_random passes tagged ptr -> EFAULT), deterministic test backend, FIFO callback backend. |
| CE/src/safety/chacha20.nova | skimmed | 359 | Working | ChaCha20 block/stream; RFC 7539 vectors. |
| CE/src/safety/dp_budget_ui.nova | skimmed | 401 | Working | ASCII bar + status text for the epsilon counter. |
| CE/src/safety/x509_verify.nova | reviewed | 437 | Partial | RSA/ECDSA chain signature check to pinned anchor + leaf SAN + leaf validity; no basicConstraints/CA check, no intermediate expiry, no revocation. |
| CE/src/safety/poly1305.nova | skimmed | 451 | Working | Poly1305 MAC with 5x26-bit limbs; RFC vectors. |
| CE/src/safety/sha1.nova | skimmed | 511 | Working (test-only) | SHA-1 + HMAC-SHA1 (for STUN/SRTP); FIPS/RFC 2202 vectors. |
| CE/src/safety/md5.nova | skimmed | 538 | Working (test-only) | MD5 (for TURN long-term key); RFC 1321 vectors. |
| CE/src/safety/differential_privacy.nova | reviewed | 591 | Partial | Integer epsilon counter + two-sided geometric noise from a 15-bit LCG seeded with constant (budget+7919); noise shrinks for eps<0.01 (cap bug). |
| CE/src/safety/sha256.nova | reviewed | 592 | Working | SHA-256 + HMAC-SHA256, oneshot and streaming; FIPS 180-4 / RFC 4231 vectors. |
| CE/src/safety/bignum.nova | skimmed | 721 | Working | 256-bit bignum with shift-subtract modmul (legacy; used by SecAgg DH helper). |
| CE/src/safety/scram.nova | skimmed | 725 | Working | SCRAM-SHA-256 message math + PBKDF2-HMAC-SHA256 + base64; RFC 7677 vectors; MAC compare not constant-time. |
| CE/src/safety/field25519.nova | skimmed | 839 | Working | GF(2^255-19) arithmetic for x25519. |
| CE/src/safety/aes_gcm.nova | skimmed | 854 | Working | AES-128/256 (table S-box) + GCM; FIPS 197 / SP 800-38D vectors; self-described as cache-timing exposed. |
| CE/src/safety/p256.nova | reviewed | 890 | Working (weak keygen) | P-256 field/group ops, ECDH, keygen; double-and-add (not constant time); key bytes fall back to 15-bit LCG when secure_random fails (always on Linux x86-64). |
| CE/src/safety/x509.nova | skimmed | 906 | Partial | X.509 DER parser for ECDSA-P256 certs + validity check; no SAN/basicConstraints/keyUsage/revocation (documented). |
| CE/src/safety/bignum_256.nova | skimmed | 966 | Working | 256-bit bignum with Montgomery REDC and ladder modpow. |
| CE/src/safety/bignum_2048.nova | skimmed | 1010 | Working | 2048-bit bignum, Montgomery modpow, MODP group-14 constants. |
| CE/src/safety/ed25519.nova | reviewed | 1292 | Working (weak keygen) | Ed25519 keygen/sign/verify + SHA-512; RFC 8032 vectors; keygen seed falls back to 15-bit LCG (32,767 possible keys) when secure_random fails. |
| CE/src/net/tls/tls_state.nova | skimmed | 212 | Working (test-only) | Enum + legal-transition table for a TLS 1.3 state machine; not imported by any binary. |
| CE/src/net/tls/tls_wire_hook.nova | skimmed | 554 | Partial | Wraps an accepted fd in the in-house TLS 1.3 server session when a config is supplied; pass-through otherwise (default). |
| CE/src/net/tls/base64.nova | skimmed | 149 | Working | Base64 decoder for env-supplied DER/key material. |
| CE/src/net/tls/der.nova | skimmed | 258 | Working | Minimal ASN.1 DER tag/length walker. |
| CE/src/net/tls/tls_handshake.nova | skimmed | 915 | Working | Serialize/parse six TLS 1.3 handshake message types (single suite/group). |
| CE/src/net/tls/x509.nova | skimmed | 1033 | Partial | Ed25519-only X.509 subset parser + 2-cert (leaf,root) chain check with validity; rejects everything else. |
| CE/src/net/tls/tls_transcript.nova | skimmed | 155 | Working | Rolling SHA-256 transcript hash. |
| CE/src/net/tls/tls_record.nova | skimmed | 437 | Working | TLS 1.3 record header + ChaCha20-Poly1305 record protect/unprotect (has a stale TODO(R94) comment). |
| CE/src/net/tls/tls_kdf.nova | skimmed | 258 | Working | HKDF-Expand-Label / Derive-Secret; RFC 8448 trace vectors. |
| CE/src/net/tls/tls_session.nova | skimmed | 1301 | Partial | TLS 1.3 handshake driver (x25519 + Ed25519 + ChaCha20-Poly1305 only); tested only against itself in-process. |
| CE/src/net/tls/tls_keyshare.nova | skimmed | 183 | Working | x25519 keyshare glue reading 32 bytes from rng_ctx. |
| CE/src/net/tls/tls_alerts.nova | skimmed | 201 | Working | Alert code enum + 2-byte serialize/parse. |
| CE/src/net/tls/tls_cert.nova | skimmed | 344 | Working | CertificateVerify sign/verify (Ed25519) over the transcript context string. |
| CE/src/net/tls/tls_config.nova | skimmed | 247 | Working | Holder for server cert DER, raw Ed25519 seed, root DER. |
| CE/src/persistence/snapshot_reader.nova | skimmed | 149 | Working | Checks container tag/version and returns sections in fixed order soul->KGs->episodic. |
| CE/src/persistence/bundle_signing.nova | skimmed | 236 | Working | Signs/verifies child bundle text with Ed25519; loads signer seed from env var hex. |
| CE/src/persistence/merkle.nova | reviewed | 438 | Working | SHA-256 Merkle root/proof over canonical atom strings; duplicate-last pairing, no leaf/node domain separation. |
| CE/src/persistence/snapshot_writer.nova | skimmed | 475 | Working | In-memory 5-section snapshot container (lists) + names of durable-write steps. |
| CE/src/persistence/schema_migration.nova | skimmed | 502 | Working | Versioned atom-schema migration step registry applied on load. |
| CE/src/persistence/snapshot_compaction.nova | skimmed | 522 | Working | Drops low-belief atoms / old episodes / dead synapses from a snapshot by thresholds. |
| CE/src/persistence/merkle_signing.nova | reviewed | 555 | Working | Ed25519 sign/verify of the Merkle root hex; reads/writes raw 32-byte key files (0600 priv) via tmp+rename. |
| CE/src/persistence/snapshot_delta.nova | skimmed | 827 | Working | Writes/reads incremental delta files (changed atoms since parent fingerprint), mode 0644, tmp+rename. |
| CE/src/persistence/chat_state.nova | skimmed | 1232 | Dead (test-only) | Alternative chat-state save/load to /tmp/crossengin/chat_state.dat; no binary imports it. |
| CE/src/persistence/snapshot_disk.nova | reviewed | 3066 | Working | Line-oriented `key value` text snapshot encode/decode, tmp+fsync+rename write (0644, no O_EXCL/O_NOFOLLOW), optional Merkle root + Ed25519 sig over KGS section only. |
| CE/infra/tls/nginx.rpc.conf.example | reviewed | 45 | Doc/config | nginx stream TLS terminator example in front of the plaintext RPC daemon. |
| CE/infra/tls/stunnel.rpc.conf.example | reviewed | 68 | Doc/config | stunnel TLS terminator example (accept 0.0.0.0:9977 -> 127.0.0.1:9876). |
| CE/infra/vercel-proxy/SECURITY.md | skimmed | 166 | Doc | Threat-model notes; acknowledges admin commands reachable via /chat and missing rate limiting. |
| CE/infra/vercel-proxy/ARCHITECTURE.md | skimmed | 156 | Doc | Describes browser -> Vercel function -> Python wrapper -> chat binary. |
| CE/infra/vercel-proxy/web/app/api/chat/route.ts | reviewed | 131 | Working | Unauthenticated public POST handler; forwards {session_id,input} to backend with server-held bearer token; 8KB input cap. |
| CE/infra/vercel-proxy/web/app/page.tsx | reviewed | 162 | Working | React chat page; random UUID session id; posts to /api/chat; renders text (no innerHTML). |
| CE/infra/vercel-proxy/web/app/layout.tsx | reviewed | 16 | Working | Next.js root layout boilerplate. |
| CE/infra/vercel-proxy/web/README.md | skimmed | 116 | Doc | Deploy instructions. |
| CE/infra/vercel-proxy/web/vercel.json | reviewed | 19 | Config | Function runtime/duration + two response headers. |
| CE/infra/vercel-proxy/web/package.json | reviewed | 27 | Config | next ^14.2.5, react 18; no lockfile committed. |
| CE/infra/vercel-proxy/web/next.config.js | reviewed | 15 | Config | reactStrictMode only. |
| CE/infra/vercel-proxy/web/.env.example | reviewed | 18 | Config | Two placeholders: CROSSENGIN_URL, CROSSENGIN_TOKEN (no real secret; no LLM provider keys). |
| CE/infra/vercel-proxy/web/tsconfig.json | reviewed | 21 | Config | TypeScript config. |
| CE/infra/vercel-proxy/web/next-env.d.ts | reviewed | 5 | Config | Next type shim. |
| CE/infra/vercel-proxy/backend/README.md | skimmed | 165 | Doc | Backend run instructions. |
| CE/infra/vercel-proxy/backend/docker-compose.yml | reviewed | 59 | Config | Publishes 8080 on all interfaces with hard-coded token "local-dev-token" + CE_ALLOW_DEV_TOKEN=1. |
| CE/infra/vercel-proxy/backend/Dockerfile | reviewed | 84 | Config | Ubuntu 24.04; unauthenticated git clone of NOVA + Crossengin-demo `main` from GitHub (unpinned); builds; runs as root. |
| CE/infra/vercel-proxy/backend/entrypoint.sh | reviewed | 51 | Working | Checks binary + token env, refuses dev token unless override flag, execs server.py. |
| CE/infra/vercel-proxy/backend/server.py | reviewed | 377 | Working | Python http.server on 0.0.0.0:8080; bearer check (hmac.compare_digest); pipes input line to a per-session chat subprocess stdin; one-shot mode uses shared /tmp/crossengin_input. |
| CE/infra/vercel-proxy/tests/test_backend_health.py | reviewed | 109 | Working | Smoke test: GET /health returns expected JSON. |
| CE/infra/vercel-proxy/tests/test_chat_route.ts | reviewed | 149 | Working | 5 route tests with mocked fetch (env missing, empty input, too large, unreachable, happy path). |
| CE/infra/vercel-proxy/tests/README.md | skimmed | 41 | Doc | How to run the two tests. |
| CE/web/styles.css | skimmed | 555 | Working | CSS for the RPC web UI. |
| CE/web/app.js | reviewed | 790 | Working | Vanilla-JS SPA calling /rpc/<verb>; stores cap token in localStorage; several innerHTML sinks interpolating server error strings. |
| CE/web/index.html | reviewed | 250 | Working | Static HTML shell for the SPA. |
| CE/.devcontainer/setup.sh | reviewed | 48 | Working | Installs build-essential, clones github.com/amoufaq5/nova (unpinned), builds. |
| CE/.devcontainer/README.md | reviewed | 31 | Doc | Codespaces instructions. |
| CE/.devcontainer/devcontainer.json | reviewed | 27 | Config | Ubuntu 24.04 devcontainer running setup.sh. |
| CE/scripts/web.py | reviewed | 1164 | Working | Python HTTP server (loopback default, no auth, no Origin check) that pipes each POSTed message into a per-cookie chat subprocess; /api/sessions lists all session ids. |
| CE/scripts/rpc_web_shim.py | reviewed | 419 | Working | Static file server + POST /rpc/<verb> -> TCP RPC daemon bridge; verb allow-list, traversal guard, opt-in CORS; no auth, no Origin/Host check. |
| CE/scripts/serve_web.sh | reviewed | 50 | Working | Execs rpc_web_shim.py. |
| CE/scripts/rpc.sh | reviewed | 105 | Working | Sends one JSON-RPC line via nc or /dev/tcp; verb interpolated into JSON unescaped. |
| CE/scripts/rpc_daemon.sh | reviewed | 76 | Working | Launches RPC daemon; refuses non-loopback bind without override flag. |
| CE/scripts/gen_tls_cert.sh | reviewed | 146 | Working | openssl self-signed cert/key generator for the TLS sidecar (0600 key). |
| CE/scripts/snap_keygen.sh | reviewed | 67 | Working | openssl Ed25519 keypair -> raw 32-byte .priv/.pub (safe alternative to the Nova keygen). |
| CE/scripts/secure_channel_echo.py | reviewed | 278 | Working | Independent Python ChaCha20-Poly1305 PSK echo server used as interop counterpart in one integration test. |
| CE/scripts/fed_smoke_client.py | reviewed | 66 | Working | Connects to fed coordinator, sends HELLO + FED_JOIN, closes. |
| CE/scripts/secagg_smoke_soul.py | reviewed | 217 | Working | Python SecAgg soul client re-implementing the same 15-bit LCG mask derivation. |
| CE/LICENSE | reviewed | 41 | Doc | 41-line custom "Proprietary and Confidential" license; no rights granted. |
| CE/.gitignore | reviewed | 44 | Config | Ignores build output, *.cesnap/*.celog, pycache; does NOT ignore *.priv/*.key/.env*. |
| CE/docs/caps.sample.conf | reviewed | 26 | Doc/config | Commented sample capability policy file. |
| CE/docs/samples/sample_agent.bundle | reviewed | 26 | Doc/sample | Sample child bundle text with an Ed25519 signature line; no private key. |
| CE/docs/samples/sample_agent.pub | reviewed | 1 | Doc/sample | 32 raw bytes: Ed25519 public key for the sample bundle (public only). |


---

## Section: ce_io


Rows: 80 = 65 files from `git ls-files src/io` (verified: 65) + 8 root docs + 7 scripts. Total LOC src/io = 47,327.

"reviewed" = core logic read and/or executed. "skimmed" = header, function list, self-declared scope notes and unit test read; algorithm body not read line by line (these are 400-3,000-line textbook routines of repetitive integer arithmetic; I sampled rather than read all 47k lines). Unit tests for 16 of them were executed.

| path | status | LOC | actual status | what it really does |
|---|---|---|---|---|
| CE/src/io/effectors/README.md | reviewed | 14 | Doc | 14-line index; says STT/TTS and file/network transport are "deferred" — stale vs the code beside it. |
| CE/src/io/effectors/audio_speak.nova | reviewed | 253 | Working | /speak: tries `espeak -w` via fork+/bin/sh -c, else in-house formant synth; then best-effort `aplay`/`paplay`. Shell args single-quote-escaped. |
| CE/src/io/effectors/audio_synth.nova | skimmed | 1223 | Working | Integer two-formant ("simplified Klatt") phoneme synthesizer + older sine synth; writes 8 kHz 16-bit mono WAV. 150 ms fixed per phoneme. 13 tests (synthetic). |
| CE/src/io/effectors/audio_tts.nova | skimmed | 829 | Partial | Text->phoneme (G2P) via a 122-word hard-coded dictionary + letter rules, then audio_synth; /say. Playback shell-out interpolates path into single quotes without escaping (audio_tts.nova:788,793). |
| CE/src/io/effectors/audio_voice_clone.nova | skimmed | 1010 | Partial | "Voice cloning" = estimate mean F0 (YIN) + LPC formant centres from a reference WAV, then re-run the formant synth with those parameters. Parameter transfer, not cloning in the modern sense. Tested only on its own synthetic vowels. |
| CE/src/io/effectors/effector_code_exec.nova | reviewed | 20 | Working | "Sandboxed code execution" = evaluates one arithmetic expression via language/arithmetic.nova. No code is executed. Not reachable from any example entry point. |
| CE/src/io/effectors/effector_file_ops.nova | reviewed | 40 | Partial | read_file/write_file if path starts with "/tmp/ce_tool_". No ".." check -> traversal CONFIRMED by probe. Not reachable from any example entry point. |
| CE/src/io/effectors/effector_gate.nova | reviewed | 137 | Working | Looks up permission tier for an action type, checks a veto flag + halt flag, appends INTENT/OUTCOME rows to the decision log. "speak effector" returns the text unchanged if allowed, else "". |
| CE/src/io/effectors/effector_http_action.nova | reviewed | 65 | Partial | Returns a caller-supplied canned body when simulated==1 (the default used by the planner); otherwise calls learn_pipeline.lp_fetch. Not reachable from any example entry point. |
| CE/src/io/effectors/effector_mcp.nova | reviewed | 49 | Stub | "MCP connector" = list of (service name -> canned response string); call returns the canned string. No transport. |
| CE/src/io/effectors/mcp_server_stdio.nova | reviewed | 434 | Partial | Line-based JSON-RPC over stdin/stdout: initialize, tools/list, tools/call. tools/call returns a canned string loaded from a registry file (mcp_server_stdio.nova:362-366); substring "parser", no JSON escaping. No unit test imports it. |
| CE/src/io/effectors/output_generation.nova | reviewed | 241 | Working | Template slot-filling: intent = list of (role, lemma); pick the syntax pattern that fills the most slots; join word forms with spaces. gen_word_for_concept = linear scan for the word atom with the highest-weight xref to a concept. |
| CE/src/io/effectors/tool.nova | reviewed | 152 | Working | Tool record (name, kind, action type, cost, alpha/beta success counter); select = highest success-ratio tool for a capability label; gate = permission-tier lookup. |
| CE/src/io/transducers/README.md | reviewed | 15 | Doc | 15-line index; says audio STT/TTS are deferred — stale. |
| CE/src/io/transducers/audio_capture.nova | reviewed | 519 | Working | fork+`/bin/sh -c "bash scripts/audio_capture.sh ..."`; RIFF/WAV PCM16 parser (1 MiB cap) — survived 400 mutated WAVs with no crash. |
| CE/src/io/transducers/audio_dsp.nova | skimmed | 622 | Working | Schroeder reverb (4 comb + 2 allpass), noise gate, compressor; integer. /reverb, /gate write a WAV and print stats. Synthetic tests. |
| CE/src/io/transducers/audio_melody.nova | skimmed | 603 | Working | F0 track -> MIDI note segmentation -> printed string "(melody: A4-440ms ...)". Synthetic sine tests. |
| CE/src/io/transducers/audio_mfcc.nova | skimmed | 732 | Working | STFT magnitude -> mel triangular filterbank -> integer log -> DCT-II (Bhaskara sine approximation). /mfcc prints coefficients. Synthetic tests; not compared with a reference MFCC implementation. |
| CE/src/io/transducers/audio_noise_reduce.nova | skimmed | 774 | Working | Spectral subtraction with a spectral floor, noise PSD from the first 300 ms; called "Wiener". /denoise writes a WAV. Synthetic tone+LCG-noise tests. |
| CE/src/io/transducers/audio_pitch.nova | skimmed | 1425 | Working | Autocorrelation F0 and YIN (cumulative mean normalised difference) + octave-error heuristics. /pitch, /pitch_yin print Hz. Tested on synthetic sines/harmonic stacks with known frequency (35+ checks pass). |
| CE/src/io/transducers/audio_psola.nova | skimmed | 513 | Working | TD-PSOLA pitch shift / time stretch using YIN pitch marks + Hann overlap-add. /pitch_shift writes WAV. Synthetic tests. |
| CE/src/io/transducers/audio_speaker_id.nova | skimmed | 831 | Partial | Enroll = store MFCC frame sequence per label; recognise = DTW nearest neighbour under a threshold. Text-dependent template matching, not speaker modelling. Tested on synthetic tones only. |
| CE/src/io/transducers/audio_spectrogram.nova | skimmed | 750 | Working | Integer radix-2 FFT/STFT magnitude spectrogram with Hann window. /spec prints peak bins. Synthetic sine tests (peak lands in the expected bin). |
| CE/src/io/transducers/audio_vad.nova | skimmed | 678 | Working | Energy + zero-crossing-rate voice activity detector with hangover and noise-floor calibration; 86 synthetic checks. Used by /listen and lipsync. |
| CE/src/io/transducers/audio_wakeword.nova | skimmed | 705 | Partial | One reference utterance -> MFCC template; detection = DTW distance below threshold. Tested on synthetic tone sequences only. |
| CE/src/io/transducers/deflate_decode.nova | reviewed | 934 | Working | RFC 1951 inflate (stored, fixed, dynamic Huffman) with 1.1 MB output cap and distance checks. Verified bit-exact via PNG ground truth; Adler-32 not checked. |
| CE/src/io/transducers/http_client.nova | reviewed | 1052 | Partial | Plain HTTP/1.1 GET over a TCP socket; chunked + Content-Length; 4 MiB cap. NO DNS resolver: host must be a dotted quad or listed in env HTTP_DNS_HOST_TO_IP (http_client.nova:357-369). No private-address filter of its own. |
| CE/src/io/transducers/image_canny.nova | skimmed | 517 | Working | 3x3 Gaussian blur -> Sobel -> non-max suppression -> double threshold + hysteresis. Synthetic step-edge tests. |
| CE/src/io/transducers/image_detector.nova | skimmed | 888 | Partial | "Object detector" = HOG descriptor of one example patch used as template; slide window, L2 distance < threshold, NMS. No classifier, no training set. |
| CE/src/io/transducers/image_face_detect.nova | reviewed | 759 | Partial | Integral image + 3 hand-set Haar-like band tests (dark/light/dark) + NMS. File header states thresholds are tuned to the synthetic test pattern and accuracy on real photos "WILL BE POOR" (image_face_detect.nova:10-19,117-122). |
| CE/src/io/transducers/image_face_recognize.nova | skimmed | 822 | Partial | LBP histogram gallery + chi-squared nearest neighbour with threshold; gallery saved to a file. Tested on synthetic textures, no faces. |
| CE/src/io/transducers/image_harris.nova | skimmed | 427 | Working | Harris corner response (det - 0.04*trace^2) on Sobel gradients + 3x3 NMS. Synthetic square tests. |
| CE/src/io/transducers/image_hog.nova | skimmed | 1138 | Working | HOG: L1 gradient magnitude, 9 orientation bins, 8x8 cells, 2x2 block L2 normalisation; integral-histogram variant. Synthetic tests. |
| CE/src/io/transducers/image_lbp.nova | skimmed | 590 | Working | 8-neighbour LBP codes, per-cell 256-bin histograms, chi-squared distance. Synthetic tests. |
| CE/src/io/transducers/image_ocr.nova | reviewed | 806 | Partial | "OCR" = slide built-in 8x8 bitmap glyphs over the image, per-pixel L2 match, NMS, sort into reading order. Only recognises text rendered with its own glyphs (header says so, image_ocr.nova:90-96). |
| CE/src/io/transducers/image_optical_flow.nova | skimmed | 2986 | Working | Lucas-Kanade dense flow (window sums of Ix,Iy,It; 2x2 solve), pyramid + per-pixel variants, 4 SIMD variants. Tested on synthetically shifted patterns with known displacement. |
| CE/src/io/transducers/image_orb.nova | skimmed | 1167 | Working | FAST-9 corners + Harris ranking + intensity-centroid orientation + 256-bit rotated BRIEF + Hamming ratio-test matcher. Synthetic tests. |
| CE/src/io/transducers/image_panorama.nova | skimmed | 1085 | Partial | Feature matches -> RANSAC homography (integer DLT) -> warp + blend of one image pair. Synthetic translated-image tests. |
| CE/src/io/transducers/image_pgm.nova | reviewed | 545 | Working | Binary PGM (P5) parser with 1024x1024 cap, histogram, mean, entropy, nearest-neighbour resize. Fuzzed 400x: no crash. |
| CE/src/io/transducers/image_segmentation.nova | skimmed | 722 | Working | k-means over (intensity, x, y) with grid-initialised centroids. Synthetic tests. |
| CE/src/io/transducers/image_sift.nova | skimmed | 1253 | Partial | DoG extrema over 3 octaves with [1 2 1]/16 blur, orientation histogram, 128-D descriptor with table-approximated Gaussian, ratio-test matcher. No sub-pixel refinement; header comment still says detection-only (stale). |
| CE/src/io/transducers/image_sobel.nova | skimmed | 323 | Working | 3x3 Sobel gradients, magnitude threshold, 4-way orientation bucket counts -> labels image_edge_dense/sparse, image_orient_N. |
| CE/src/io/transducers/image_stereo.nova | skimmed | 2188 | Working | SAD block-matching disparity, left-right consistency/sub-pixel "quality" pass, 4-path semi-global matching, i32/u8 SIMD variants. Tested on synthetically shifted pairs. SIMD output bit-identical to scalar (re-ran). |
| CE/src/io/transducers/image_superpixels.nova | skimmed | 996 | Working | SLIC: grid seeds moved to lowest-gradient neighbour, local k-means in 2Sx2S windows, connectivity enforcement. /slic prints counts. Synthetic tests. |
| CE/src/io/transducers/image_tracker.nova | reviewed | 628 | Partial | Per-track constant-velocity filter with scalar variance ("Kalman") + greedy nearest-distance assignment (called "greedy Hungarian" — it is not the Hungarian algorithm). /track uses a brightness-centroid as the "detection". |
| CE/src/io/transducers/input_transducer.nova | reviewed | 105 | Working | Text normalisation: trim, lowercase, collapse whitespace, count tokens. Reports audio as "not ready". |
| CE/src/io/transducers/jpeg_decode.nova | reviewed | 1598 | Working | Baseline sequential 8-bit GRAYSCALE JPEG only (Huffman decode, dequantise, integer IDCT, restart markers); rejects colour/progressive; 512x512 cap. Ground-truth verified by me: max pixel diff 1 vs libjpeg on 5 real files. |
| CE/src/io/transducers/kg_rss_ingest.nova | reviewed | 904 | Working | Hand-rolled RSS 2.0 / Atom tag scanner; each item becomes a KG atom with guid dedup. Fetch via http_get or file://ANY-PATH with no gate/whitelist (kg_rss_ingest.nova:677-727; chat line 7590). Fetches the feed twice per /rss. |
| CE/src/io/transducers/kg_sync.nova | skimmed | 1964 | Working | Line-based TCP pub/sub of atom birth/promote/atrophy/delete events between processes; optional shared token; optional Noise XK wrapping. 101 functions; largest protocol module. |
| CE/src/io/transducers/noise_xk.nova | skimmed | 1293 | Partial | Noise XK handshake over 2048-bit finite-field DH (MODP group 14) + ChaCha20-Poly1305. If secure_random fails it silently falls back to a 15-bit LCG seeded from nanotime (noise_xk.nova:444-454). |
| CE/src/io/transducers/png_decode.nova | reviewed | 760 | Working | PNG 8-bit GRAYSCALE non-interlaced only; CRC32 verified per chunk; all 5 filters; zlib via deflate_decode. Ground-truth verified by me: bit-exact on 5 real files; 400 mutations all rejected cleanly. |
| CE/src/io/transducers/secure_channel.nova | skimmed | 692 | Partial | Pre-shared-key ChaCha20-Poly1305 framing over TCP (not TLS). Handshake nonce = nanotime + counter (secure_channel.nova:324-345), not random. |
| CE/src/io/transducers/stream_audio.nova | reviewed | 394 | Dead | Would poll an env-supplied shell command (CE_AUDIO_CAPTURE_CMD) then STT then post a message event. Imported by NO source file or example — only by its own unit test. |
| CE/src/io/transducers/stream_http.nova | skimmed | 680 | Partial | Loopback HTTP server for the daemon: POST /api/event {"message":..} -> message event; one request per poll, 64 KiB cap, no auth (loopback default). |
| CE/src/io/transducers/stream_stdin.nova | skimmed | 378 | Working | Non-blocking stdin line reader -> normalised text -> message event for the daemon. |
| CE/src/io/transducers/stream_unix_socket.nova | skimmed | 386 | Partial | Unix-domain socket (default /tmp/crossengin.sock) line reader -> message events; one connection drained per poll. |
| CE/src/io/transducers/stt_seam.nova | reviewed | 885 | Working | Dispatcher: picks whisper.cpp if binary+model files exist, else Vosk, else a stub that returns "[stt unavailable]"; also a `bash scripts/transcribe.sh` subprocess path. Contains no speech recognition itself. |
| CE/src/io/transducers/tls13_client.nova | reviewed | 838 | Partial | TLS 1.3 client (P-256 ECDHE, ChaCha20-Poly1305). Default mode does NOT authenticate the server; server Finished MAC is computed but never compared (tls13_client.nova:712-721); built-in trust anchors are two pinned "sandbox egress-gateway" RSA keys (268-273). |
| CE/src/io/transducers/video_motion_vectors.nova | skimmed | 315 | Working | 16x16 block matching, +/-8 px SAD search vs previous frame; dominant direction label. Synthetic tests. |
| CE/src/io/transducers/video_perception.nova | reviewed | 502 | Working | /play: per Y4M frame compute image labels + mean-abs-diff motion + scene-change flag; returns text lines that the chat prints. |
| CE/src/io/transducers/video_smooth.nova | skimmed | 406 | Partial | Runs image_tracker over a directory of frame_NNNN.pgm and fills gaps with predicted positions; prints a summary. |
| CE/src/io/transducers/video_y4m.nova | reviewed | 568 | Working | YUV4MPEG2 (uncompressed) reader, 4:2:0 only, 768x432 / 16 MiB caps. Fuzzed 400x: no crash. Real video needs `ffmpeg` first. |
| CE/src/io/transducers/visual_perception.nova | reviewed | 800 | Working | /see: decode PGM/PNG/JPEG by extension, compute stats + Sobel/Harris/SIFT/Canny/ORB/HOG/LBP/SLIC counts, turn them into label strings (e.g. image_dark, image_edge_dense). The chat prints them; nothing is stored. |
| CE/src/io/transducers/vosk_backend.nova | reviewed | 515 | Working | fork+exec `python3 -c <inline script>` that imports the `vosk` package and a downloaded Kaldi model directory; parses "OK <conf> <text>". |
| CE/src/io/transducers/whisper_backend.nova | reviewed | 884 | Working | fork+exec whisper.cpp binary with `-m ggml-tiny.en.bin -f WAV`; captures stdout as the transcript; optional JSON confidence via fixed path /tmp/ce_whisper_out.json. |
| CE/AUDIO_AUDIT.md | skimmed | 3812 | Doc | 3,812-line build log / design notes for the audio modules, round by round. Not an audit: no independent measurements, no real-speech results. |
| CE/IMAGE_AUDIT.md | skimmed | 2550 | Doc | 2,550-line roadmap + build log for vision modules. States the feature->atom binding "is a separate follow-up" (IMAGE_AUDIT.md:632-635) — still true. |
| CE/JPEG_AUDIT.md | skimmed | 249 | Doc | Design memo for the grayscale baseline JPEG decoder; accurate about scope. |
| CE/VIDEO_AUDIT.md | skimmed | 264 | Doc | Roadmap memo: why only Y4M; H.264 etc. not attempted. Accurate. |
| CE/STT_AUDIT.md | reviewed | 220 | Doc | Memo explaining that pure-Nova STT is not feasible and recommending whisper.cpp / Vosk subprocesses. Frames STT as a "modality bridge" outside cognition. |
| CE/TLS_AUDIT.md | reviewed | 225 | Doc | Layered status notes; top says TLS 1.3 client shipped, body section "Why TLS isn't here yet" (TLS_AUDIT.md:113) is stale. Does not mention the unverified server Finished. |
| CE/SNAPSHOT_FORMAT.md | skimmed | 616 | Doc | Snapshot file format/version history (persistence, not io). Skimmed only: format tables; code is another reviewer's area. |
| CE/BENCHMARKS.md | reviewed | 190 | Doc | SIMD-vs-scalar timings of Nova code against Nova code; no external baseline. Stereo 5.9x reproduced (6.2x); LK 3.35x NOT reproduced (1.1-1.25x); HOG bench no longer compiles. |
| CE/scripts/audio_capture.sh | reviewed | 236 | Working | Records via parecord/arecord/sox; if none available writes a SILENT WAV and exits 0. |
| CE/scripts/transcribe.sh | reviewed | 126 | Working | Runs whisper-cli / whisper.cpp `main` / vosk-transcriber; prints "[stt: no backend installed]" and exits 0 otherwise. |
| CE/scripts/image_to_pgm.sh | reviewed | 156 | Working | Converts via ImageMagick convert/magick or ffmpeg; if none (or all fail) writes a 16x16 grey placeholder PGM and exits 0. |
| CE/scripts/video_to_y4m.sh | reviewed | 103 | Working | ffmpeg -> yuv4mpegpipe; exits with a skip message if ffmpeg is absent. |
| CE/scripts/gen_test_jpeg.py | reviewed | 207 | Working | Writes a test JPEG with Pillow, or a hand-rolled NON-decodable stub if Pillow is missing. Docstring stale (says decoder is structural-only). |
| CE/scripts/gen_test_png.py | reviewed | 170 | Working | Writes a grayscale PNG using struct+zlib (no Pillow). |
| CE/scripts/bench_simd_production.sh | reviewed | 786 | Partial | Generates and runs three Nova bench programs (stereo, flow, HOG detector). The generated HOG bench fails to compile with the current Nova ("undeclared callee: str_data"). |


---

## Section: ce_tests


Rows: 675. Assignment file count: tests/** + bench/** + data/** + .github/** = 654 files (find; repo copy is not a git checkout so git ls-files is unavailable), plus Makefile, nova-deps.toml and 19 assigned scripts = 675.

'reviewed' = read by hand; 'skimmed (script-analysed)' = assertion statistics extracted by script (probes/ce_tests/tq.py), not read line by line (478 repetitive test files, 132k LOC). Unit-test status 'Working' means the file is a real assertion-bearing test; pass/fail comes from the lead's make test run (see findings).

| path | status | LOC | actual status | what it really does |
|---|---|---|---|---|
| CE/Makefile | reviewed | 362 | Working | Build driver: compiles each src module to fixed /tmp/ce_build_check.bin, runs scripts/test.sh, builds 10 binaries, runs integration *.sh; default NOVA_ROOT=$HOME/NOVA, no NOVA version check |
| CE/nova-deps.toml | reviewed | 144 | Doc | Declarative note of NOVA 'version 0.2.0/0.9.0' + 14 upstream enhancements (7 marked 'required', i.e. not available); read by no tool |
| CE/.github/workflows/build-and-smoke.yml | reviewed | 84 | Partial | Only CI: checks out NOVA default branch unpinned, plain make (non-setarch), make install, pipes 10x 'fever' into chat and greps 5 exact counters; no make test/integration/coverage/lint |
| CE/tests/ce_test.nova | reviewed | 88 | Working | Assertion harness: ce_check/ce_eq/ce_str_eq/ce_near bump global pass/fail counters and print 'FAIL:'; ce_summary exit(1) on any failure |
| CE/tests/benchmark/README.md | reviewed | 17 | Doc | Says benchmark status 'Pending'; quotes ~1132x operator-index speedup |
| CE/tests/benchmark/bench_ann_query.nova | reviewed | 192 | Working | Times LSH bucket lookup vs linear cosine scan on 1000 synthetic atoms (re-run: 79x; ANN returns 23600 of 25000 linear results) |
| CE/tests/benchmark/bench_kg_query.nova | reviewed | 179 | Partial | Insert/lookup rates with 1-second clock (prints count as rate when elapsed=0) + label-index vs scan timing (re-run 74x) |
| CE/tests/benchmark/bench_nl_verbs.nova | reviewed | 426 | Partial | nanotime latency of grammar parse/classifier/executor/RPC on synthetic 1000-atom KG; re-run OOM-killed at 13.6 GB RSS after 6 of 10 phases |
| CE/tests/benchmark/bench_node_throughput.nova | reviewed | 65 | Partial | 8000 ticks of a 96-node pool timed with 1-second clock; reported integrations/sec is just the loop count when elapsed<=1s |
| CE/tests/benchmark/bench_operator_lookup.nova | reviewed | 121 | Working | Edge-index lookup vs full atom scan, 2000 atoms, parity check (re-run 1901x vs documented ~1132x) |
| CE/tests/benchmark/bench_predictive_coding.nova | reviewed | 106 | Dead | Delta-rule predictor on a fixed period-3 sequence; does not compile on current tree ('undeclared callee: sys_open') |
| CE/tests/benchmark/bench_self_improve.nova | reviewed | 43 | Working | Tabular Q-learning on a 5x5 deterministic grid world; before/after greedy return (-200 -> 93, optimal 8 steps); no baseline |
| CE/tests/benchmark/bench_tick_rate.nova | reviewed | 86 | Partial | Tick-loop iterations per second with 1-second clock; output equals the loop count (60000, 5000) |
| CE/tests/benchmark/kg_synthetic_loader.nova | reviewed | 200 | Working | Builds synthetic KG (1000 atoms/5000 relations/10 capsules) for bench_nl_verbs |
| CE/bench/baseline.json | reviewed | 174 | Working | 15 SIMD/vision kernel timings captured once on host 'vm' (2026-06-03); documented as stale (HOG now 40-66% faster) |
| CE/bench/latency_v1/baseline.json | reviewed | 7 | Stub | Empty results array; self-described 'Empty baseline' so --compare is a no-op |
| CE/bench/latency_v1/README.md | reviewed | 129 | Doc | Explains NL latency harness and that baseline is an empty stub |
| CE/data/packs/biology.cerec | reviewed | 279 | Working | Hand-authored fact list: 77 ATOM, 86 IMP, 4 OBS, 5 CITE (cites textbooks by name; no licence line) |
| CE/data/packs/folk_astronomy.cerec | reviewed | 37 | Working | 5 deliberately low-belief atoms (pluto planet etc.) to trigger cross-KG conflict demo |
| CE/data/packs/physics.cerec | reviewed | 152 | Working | 35 ATOM, 35 IMP, 3 OBS; label overlap with solar_system by design |
| CE/data/packs/politics.cerec | reviewed | 236 | Working | 73 ATOM, 58 IMP; descriptive taxonomy of political systems |
| CE/data/packs/religion.cerec | reviewed | 222 | Working | 58 ATOM, 68 IMP; descriptive taxonomy of religions |
| CE/data/packs/solar_system.cerec | reviewed | 170 | Working | 33 ATOM, 49 IMP; only pack with CAPSULE/VERSION/LICENSE (CC-BY-4.0) header |
| CE/data/packs/world_history.cerec | reviewed | 170 | Working | 43 ATOM, 50 IMP; dated historical milestones |
| CE/data/packs/README.md | reviewed | 120 | Doc | Pack catalogue; atom counts (324 total) match files |
| CE/data/packs/samples/climate_facts.yaml | reviewed | 92 | Working | Sample record: 10 atoms/7 implications for YAML adapter |
| CE/data/packs/samples/climate_facts.json | reviewed | 43 | Working | Same sample for JSON adapter |
| CE/data/patterns/security_review.cerec | reviewed | 132 | Working | 25 trigger-phrase -> canned guidance strings (OWASP/CWE paraphrases) for coding_helper substring match |
| CE/data/nl_intent/prototypes.txt | reviewed | 164 | Working | ~130 example utterances for 10 intent kinds; duplicate of corpus hard-coded in src/nl/nl_intent_classifier.nova (file not read at runtime) |
| CE/data/llm_baseline_sample.txt | reviewed | 40 | Fake | 12 invented 'LLM verdicts' (affirm/deny) for the reasoning bench; header calls it both 'illustrative' and 'recorded' |
| CE/data/llm_baseline_ext.txt | reviewed | 65 | Fake | Same, for the extended bank; invented |
| CE/scripts/test.sh | reviewed | 91 | Working | Runs each tests/unit/*.nova via nova run with 60s timeout; PASS iff exit 0 and no 'assertion failed'/' FAIL' in output |
| CE/scripts/coverage.sh | reviewed | 103 | Working | Static BFS over import lines from tests/unit; 'covered' = imported; re-run: 385/397, exits 1 |
| CE/scripts/bench.sh | reviewed | 556 | Partial | Wrapper: runs scripts/bench_*.sh + make -C NOVA bench targets, parses self-reported ns, emits JSON/compare; hard-coded /home/user/NOVA fallback; not re-run |
| CE/scripts/bench_nl_verbs.sh | reviewed | 234 | Partial | Runs bench_nl_verbs.nova, extracts JSON, compares to (empty) baseline |
| CE/scripts/bootstrap.sh | reviewed | 50 | Working | Checks as/ld/make/gcc, runs plain make in $NOVA_ROOT if unbuilt; does not clone or pin NOVA |
| CE/scripts/chat.sh | reviewed | 72 | Working | Loop that boots a fresh daemon per typed line |
| CE/scripts/run.sh | reviewed | 27 | Working | Runs kernel_selfcheck; header still says 'there is no end-user cognitive agent yet' |
| CE/scripts/preload.sh | reviewed | 82 | Working | Calls rpc.sh skill.install for echo+research on a running daemon; no knowledge preloading |
| CE/scripts/learn.sh | reviewed | 389 | Working | curl Wikipedia/URL/file -> top-30 frequent 4-14 letter words + awk regex triples (X is/causes/has Y) into fixed /tmp files; drops negation |
| CE/scripts/learn_smoke.sh | reviewed | 65 | Working | Writes fake vocab+triples to /tmp, runs /learn in chat, checks 2 words and 4-5 operators |
| CE/scripts/learn_smoke_multi.sh | reviewed | 312 | Working | Exercises learn.sh source kinds (topic/url/file/batch/rss/dir); network parts skip when offline |
| CE/scripts/llm_compose.sh | reviewed | 202 | Working | Sends templated reply to Ollama (default llama3.2:3b-instruct)/llama.cpp/OpenAI-compatible API for rewording; falls back to template |
| CE/scripts/llm_extract.sh | reviewed | 231 | Working | Sends a text file to an LLM (ollama/llama-cli/OpenAI API) with a prompt to emit ATOM/IMP/OBS lines; writes .cerec |
| CE/scripts/nl_parse_llm.sh | reviewed | 259 | Working | Sends one user sentence to an LLM to classify into KIND/ARG wire record |
| CE/scripts/crossengin-doctor.sh | reviewed | 250 | Working | Environment checklist (tools, /tmp, binaries, TCP probe to en.wikipedia.org) |
| CE/scripts/migrate_snapshot.sh | reviewed | 74 | Working | Wrapper that runs examples/migrate_snap.nova on two paths |
| CE/scripts/snap_diff.sh | reviewed | 244 | Working | Text diff of two key/value snapshot files (atoms, beliefs, mood) |
| CE/scripts/bake_sample.sh | reviewed | 109 | Working | Generates a signed sample agent bundle + pubkey into docs/samples |
| CE/scripts/int_safety_lint.py | reviewed | 174 | Working | Regex lint for large integer literals in * / comparisons (NOVA codegen bug #11); re-run: 12 findings, exit 1 |
| CE/tests/unit/test_action_atoms.nova | skimmed (script-analysed) | 194 | Working | 79 assertions (77 vs literal, 2 weak >=0/!=0/const); exercises action_atoms |
| CE/tests/unit/test_action_module.nova | skimmed (script-analysed) | 590 | Working | 100 assertions (74 vs literal, 8 weak >=0/!=0/const); has skip-as-pass path; exercises action_module |
| CE/tests/unit/test_admin_bake_child_verb.nova | skimmed (script-analysed) | 181 | Working | 20 assertions (13 vs literal, 0 weak >=0/!=0/const); exercises rpc_verbs, capability, bake_manifest, str_safe |
| CE/tests/unit/test_admin_emit_delta_verb.nova | skimmed (script-analysed) | 207 | Working | 24 assertions (13 vs literal, 0 weak >=0/!=0/const); exercises rpc_verbs, capability, child_mode, str_safe |
| CE/tests/unit/test_admin_list_holder_qps_verb.nova | skimmed (script-analysed) | 160 | Working | 30 assertions (4 vs literal, 0 weak >=0/!=0/const); exercises capability, holder_rate, rpc_verbs, str_safe |
| CE/tests/unit/test_admin_set_holder_qps_verb.nova | skimmed (script-analysed) | 185 | Working | 26 assertions (5 vs literal, 0 weak >=0/!=0/const); exercises capability, holder_rate, rpc_verbs, str_safe |
| CE/tests/unit/test_aes_gcm.nova | skimmed (script-analysed) | 393 | Working | 31 assertions (24 vs literal, 5 weak >=0/!=0/const); exercises aes_gcm |
| CE/tests/unit/test_agent_manifest.nova | skimmed (script-analysed) | 268 | Working | 86 assertions (72 vs literal, 0 weak >=0/!=0/const); exercises agent_manifest, str_safe |
| CE/tests/unit/test_agent_registry.nova | skimmed (script-analysed) | 191 | Working | 51 assertions (49 vs literal, 2 weak >=0/!=0/const); exercises agent_manifest, agent_registry, skill_manifest, skill_registry |
| CE/tests/unit/test_agent_run.nova | reviewed (assert lines sampled) | 291 | Working | 31 assertions (23 vs literal, 1 weak >=0/!=0/const); exercises agent_manifest, agent_registry, agent_run, skill_manifest |
| CE/tests/unit/test_agent_snapshot.nova | skimmed (script-analysed) | 145 | Working | 40 assertions (25 vs literal, 3 weak >=0/!=0/const); exercises session_snapshot, agent_manifest, agent_registry, str_safe |
| CE/tests/unit/test_agent_verbs.nova | skimmed (script-analysed) | 332 | Working | 56 assertions (6 vs literal, 1 weak >=0/!=0/const); exercises rpc_verbs, agent_manifest, agent_registry, skill_registry |
| CE/tests/unit/test_ann_index.nova | skimmed (script-analysed) | 335 | Working | 46 assertions (24 vs literal, 6 weak >=0/!=0/const); exercises atom_store, ann_index, multi_kg_manager |
| CE/tests/unit/test_answer_exclusion.nova | skimmed (script-analysed) | 45 | Working | 5 assertions (4 vs literal, 0 weak >=0/!=0/const); exercises reasoning_atoms, promotion |
| CE/tests/unit/test_appraisal.nova | skimmed (script-analysed) | 44 | Working | 14 assertions (12 vs literal, 0 weak >=0/!=0/const); exercises appraisal |
| CE/tests/unit/test_argumentation.nova | skimmed (script-analysed) | 145 | Working | 37 assertions (37 vs literal, 0 weak >=0/!=0/const); exercises argumentation |
| CE/tests/unit/test_arithmetic.nova | skimmed (script-analysed) | 63 | Working | 23 assertions (23 vs literal, 0 weak >=0/!=0/const); exercises arithmetic |
| CE/tests/unit/test_ask_user_to_teach.nova | skimmed (script-analysed) | 75 | Working | 19 assertions (14 vs literal, 2 weak >=0/!=0/const); exercises ask_user_to_teach |
| CE/tests/unit/test_atom_birth_monitor.nova | skimmed (script-analysed) | 84 | Working | 15 assertions (13 vs literal, 2 weak >=0/!=0/const); exercises atom_birth_monitor |
| CE/tests/unit/test_atom_death_attribution.nova | skimmed (script-analysed) | 227 | Working | 28 assertions (27 vs literal, 0 weak >=0/!=0/const); exercises atom_death_monitor, meta_observer, str_safe |
| CE/tests/unit/test_atom_death_monitor.nova | skimmed (script-analysed) | 198 | Working | 45 assertions (38 vs literal, 4 weak >=0/!=0/const); exercises atom_death_monitor |
| CE/tests/unit/test_atom_store.nova | reviewed (assert lines sampled) | 196 | Working | 77 assertions (74 vs literal, 0 weak >=0/!=0/const); exercises atom_store |
| CE/tests/unit/test_atom_store_index.nova | skimmed (script-analysed) | 305 | Working | 61 assertions (29 vs literal, 21 weak >=0/!=0/const); exercises atom_store, multi_kg_manager |
| CE/tests/unit/test_audio_capture.nova | skimmed (script-analysed) | 320 | Working | 28 assertions (27 vs literal, 1 weak >=0/!=0/const); exercises audio_capture |
| CE/tests/unit/test_audio_dsp.nova | skimmed (script-analysed) | 416 | Working | 34 assertions (12 vs literal, 3 weak >=0/!=0/const); exercises audio_dsp, audio_synth |
| CE/tests/unit/test_audio_melody.nova | skimmed (script-analysed) | 366 | Working | 40 assertions (40 vs literal, 0 weak >=0/!=0/const); exercises audio_melody, audio_pitch, audio_synth |
| CE/tests/unit/test_audio_mfcc.nova | skimmed (script-analysed) | 399 | Working | 41 assertions (14 vs literal, 6 weak >=0/!=0/const); exercises audio_mfcc, audio_synth |
| CE/tests/unit/test_audio_noise_reduce.nova | skimmed (script-analysed) | 318 | Working | 33 assertions (23 vs literal, 1 weak >=0/!=0/const); exercises audio_noise_reduce, audio_synth |
| CE/tests/unit/test_audio_pitch.nova | skimmed (script-analysed) | 530 | Working | 52 assertions (30 vs literal, 1 weak >=0/!=0/const); exercises audio_pitch, audio_synth |
| CE/tests/unit/test_audio_pitch_yin.nova | skimmed (script-analysed) | 436 | Working | 35 assertions (17 vs literal, 0 weak >=0/!=0/const); exercises audio_pitch, audio_synth |
| CE/tests/unit/test_audio_records.nova | skimmed (script-analysed) | 222 | Working | 31 assertions (27 vs literal, 4 weak >=0/!=0/const); exercises audio_records, perceptual_capsule, curriculum, atom_store |
| CE/tests/unit/test_audio_speak.nova | skimmed (script-analysed) | 37 | Working | 6 assertions (4 vs literal, 1 weak >=0/!=0/const); exercises audio_speak |
| CE/tests/unit/test_audio_spectrogram.nova | skimmed (script-analysed) | 507 | Working | 49 assertions (32 vs literal, 3 weak >=0/!=0/const); exercises audio_spectrogram, audio_synth |
| CE/tests/unit/test_audio_synth.nova | skimmed (script-analysed) | 887 | Working | 157 assertions (92 vs literal, 5 weak >=0/!=0/const); exercises audio_synth |
| CE/tests/unit/test_audio_tts.nova | skimmed (script-analysed) | 302 | Working | 68 assertions (53 vs literal, 1 weak >=0/!=0/const); exercises audio_tts |
| CE/tests/unit/test_audio_vad.nova | skimmed (script-analysed) | 646 | Working | 86 assertions (65 vs literal, 4 weak >=0/!=0/const); exercises audio_vad |
| CE/tests/unit/test_audio_wakeword.nova | skimmed (script-analysed) | 399 | Working | 42 assertions (28 vs literal, 8 weak >=0/!=0/const); exercises audio_wakeword, audio_synth |
| CE/tests/unit/test_audit_reader.nova | skimmed (script-analysed) | 62 | Working | 14 assertions (6 vs literal, 8 weak >=0/!=0/const); exercises audit_writer, audit_reader |
| CE/tests/unit/test_audit_writer.nova | skimmed (script-analysed) | 74 | Working | 25 assertions (24 vs literal, 0 weak >=0/!=0/const); exercises audit_writer |
| CE/tests/unit/test_autocompact_trigger.nova | skimmed (script-analysed) | 265 | Working | 50 assertions (42 vs literal, 0 weak >=0/!=0/const); exercises autonomous_loop |
| CE/tests/unit/test_autonomous_loop.nova | reviewed (assert lines sampled) | 102 | Working | 20 assertions (8 vs literal, 3 weak >=0/!=0/const); exercises autonomous_loop |
| CE/tests/unit/test_autonomous_research.nova | skimmed (script-analysed) | 290 | Working | 58 assertions (55 vs literal, 0 weak >=0/!=0/const); exercises autonomous_research, self_learning_triggers, multi_kg_manager, atom_store |
| CE/tests/unit/test_bake.nova | skimmed (script-analysed) | 315 | Working | 53 assertions (28 vs literal, 1 weak >=0/!=0/const); exercises bake, bake_manifest, bundle_signing, multi_kg_manager |
| CE/tests/unit/test_bake_manifest.nova | skimmed (script-analysed) | 280 | Working | 88 assertions (80 vs literal, 8 weak >=0/!=0/const); exercises bake_manifest, str_safe |
| CE/tests/unit/test_base64.nova | skimmed (script-analysed) | 131 | Working | 35 assertions (35 vs literal, 0 weak >=0/!=0/const); exercises base64 |
| CE/tests/unit/test_bayesian_updates.nova | reviewed (assert lines sampled) | 74 | Working | 20 assertions (16 vs literal, 1 weak >=0/!=0/const); exercises bayesian_updates |
| CE/tests/unit/test_belief_decay.nova | skimmed (script-analysed) | 116 | Working | 12 assertions (8 vs literal, 0 weak >=0/!=0/const); exercises verify, belief_decay |
| CE/tests/unit/test_bench_bank_ext.nova | skimmed (script-analysed) | 40 | Working | 9 assertions (8 vs literal, 1 weak >=0/!=0/const); exercises bench_bank_ext |
| CE/tests/unit/test_bignum.nova | skimmed (script-analysed) | 509 | Working | 66 assertions (63 vs literal, 3 weak >=0/!=0/const); exercises bignum |
| CE/tests/unit/test_bignum_2048.nova | skimmed (script-analysed) | 423 | Working | 65 assertions (61 vs literal, 3 weak >=0/!=0/const); exercises bignum_2048 |
| CE/tests/unit/test_bignum_256.nova | skimmed (script-analysed) | 448 | Working | 70 assertions (66 vs literal, 3 weak >=0/!=0/const); exercises bignum_256 |
| CE/tests/unit/test_bignum_mind.nova | skimmed (script-analysed) | 133 | Working | 18 assertions (16 vs literal, 1 weak >=0/!=0/const); exercises bignum |
| CE/tests/unit/test_bundle_signing.nova | skimmed (script-analysed) | 183 | Working | 25 assertions (22 vs literal, 2 weak >=0/!=0/const); exercises bundle_signing, ed25519, str_safe |
| CE/tests/unit/test_byzantine_aggregation.nova | skimmed (script-analysed) | 485 | Working | 74 assertions (68 vs literal, 1 weak >=0/!=0/const); exercises byzantine_aggregation, federated_aggregator, str_safe |
| CE/tests/unit/test_calibration.nova | reviewed (assert lines sampled) | 103 | Working | 18 assertions (16 vs literal, 1 weak >=0/!=0/const); exercises calibration |
| CE/tests/unit/test_capability.nova | skimmed (script-analysed) | 439 | Working | 84 assertions (47 vs literal, 2 weak >=0/!=0/const); exercises capability, rpc_verbs, multi_kg_manager, capsule_registry |
| CE/tests/unit/test_capability_gate.nova | skimmed (script-analysed) | 118 | Working | 40 assertions (34 vs literal, 4 weak >=0/!=0/const); exercises capability_gate |
| CE/tests/unit/test_capability_rate_limit.nova | skimmed (script-analysed) | 317 | Working | 48 assertions (31 vs literal, 5 weak >=0/!=0/const); exercises capability, session_snapshot, rpc_verbs, multi_kg_manager |
| CE/tests/unit/test_capability_wire.nova | skimmed (script-analysed) | 1652 | Working | 265 assertions (98 vs literal, 4 weak >=0/!=0/const); exercises capability, holder_rate, rpc_verbs, multi_kg_manager |
| CE/tests/unit/test_capsule.nova | skimmed (script-analysed) | 84 | Working | 35 assertions (35 vs literal, 0 weak >=0/!=0/const); exercises capsule |
| CE/tests/unit/test_capsule_dep.nova | skimmed (script-analysed) | 140 | Working | 32 assertions (31 vs literal, 1 weak >=0/!=0/const); exercises capsule_dep |
| CE/tests/unit/test_capsule_registry.nova | skimmed (script-analysed) | 148 | Working | 36 assertions (34 vs literal, 1 weak >=0/!=0/const); exercises capsule_registry |
| CE/tests/unit/test_cascade.nova | skimmed (script-analysed) | 202 | Working | 28 assertions (24 vs literal, 0 weak >=0/!=0/const); exercises cascade |
| CE/tests/unit/test_ce_test.nova | reviewed (assert lines sampled) | 51 | Working | 15 assertions (12 vs literal, 0 weak >=0/!=0/const); exercises harness only |
| CE/tests/unit/test_chacha20.nova | skimmed (script-analysed) | 171 | Working | 25 assertions (24 vs literal, 0 weak >=0/!=0/const); exercises chacha20 |
| CE/tests/unit/test_chacha20_poly1305.nova | skimmed (script-analysed) | 389 | Working | 55 assertions (55 vs literal, 0 weak >=0/!=0/const); exercises chacha20, poly1305, chacha20_poly1305 |
| CE/tests/unit/test_chat_cli_polish.nova | skimmed (script-analysed) | 361 | Working | 53 assertions (51 vs literal, 1 weak >=0/!=0/const); exercises chat_cli_polish, str_safe |
| CE/tests/unit/test_chat_fed_slash_commands.nova | skimmed (script-analysed) | 313 | Working | 44 assertions (44 vs literal, 0 weak >=0/!=0/const); exercises fed_slash, gossip, distributed_query, atom_store |
| CE/tests/unit/test_chat_helpers.nova | skimmed (script-analysed) | 264 | Working | 100 assertions (95 vs literal, 0 weak >=0/!=0/const); exercises helpers |
| CE/tests/unit/test_chat_intent_dispatch.nova | skimmed (script-analysed) | 197 | Working | 67 assertions (67 vs literal, 0 weak >=0/!=0/const); exercises helpers |
| CE/tests/unit/test_chat_state_persistence.nova | reviewed (assert lines sampled) | 813 | Working | 165 assertions (131 vs literal, 25 weak >=0/!=0/const); has skip-as-pass path; exercises chat_state, reasoning_atoms, word_atoms |
| CE/tests/unit/test_child_mode.nova | skimmed (script-analysed) | 269 | Working | 23 assertions (17 vs literal, 5 weak >=0/!=0/const); exercises child_mode, bake, bake_manifest, bundle_signing |
| CE/tests/unit/test_child_mode_wire.nova | skimmed (script-analysed) | 282 | Working | 16 assertions (16 vs literal, 0 weak >=0/!=0/const); exercises rpc_verbs, capability, child_mode, multi_kg_manager |
| CE/tests/unit/test_code_review_pack.nova | skimmed (script-analysed) | 90 | Working | 10 assertions (1 vs literal, 7 weak >=0/!=0/const); exercises code_review_pack, imagination_engine |
| CE/tests/unit/test_coding_helper.nova | skimmed (script-analysed) | 365 | Working | 58 assertions (33 vs literal, 1 weak >=0/!=0/const); exercises skill_dispatch, coding_helper, capsule_registry, pattern_capsule |
| CE/tests/unit/test_cofire_index.nova | skimmed (script-analysed) | 181 | Working | 35 assertions (35 vs literal, 0 weak >=0/!=0/const); exercises cofire_index |
| CE/tests/unit/test_cognitive_router.nova | skimmed (script-analysed) | 308 | Working | 55 assertions (48 vs literal, 6 weak >=0/!=0/const); has skip-as-pass path; exercises cognitive_router, str_safe |
| CE/tests/unit/test_coherence_check.nova | skimmed (script-analysed) | 79 | Working | 11 assertions (9 vs literal, 0 weak >=0/!=0/const); exercises context_bias, spreading_activation, coherence_check |
| CE/tests/unit/test_competence_tracker.nova | skimmed (script-analysed) | 138 | Working | 27 assertions (21 vs literal, 1 weak >=0/!=0/const); exercises competence_tracker |
| CE/tests/unit/test_concept_layer.nova | skimmed (script-analysed) | 180 | Working | 34 assertions (28 vs literal, 3 weak >=0/!=0/const); exercises concept_layer |
| CE/tests/unit/test_confidence_thresholds.nova | skimmed (script-analysed) | 66 | Working | 23 assertions (23 vs literal, 0 weak >=0/!=0/const); exercises confidence_thresholds |
| CE/tests/unit/test_consolidation.nova | reviewed | 68 | Working | 10 assertions (10 vs literal, 0 weak >=0/!=0/const); exercises consolidation |
| CE/tests/unit/test_constitution.nova | skimmed (script-analysed) | 45 | Working | 11 assertions (11 vs literal, 0 weak >=0/!=0/const); exercises constitution |
| CE/tests/unit/test_constitutional_filter.nova | skimmed (script-analysed) | 83 | Working | 22 assertions (22 vs literal, 0 weak >=0/!=0/const); exercises constitutional_filter |
| CE/tests/unit/test_context_bias.nova | skimmed (script-analysed) | 90 | Working | 9 assertions (6 vs literal, 0 weak >=0/!=0/const); exercises context_bias |
| CE/tests/unit/test_contradiction.nova | skimmed (script-analysed) | 349 | Working | 52 assertions (34 vs literal, 0 weak >=0/!=0/const); exercises contradiction |
| CE/tests/unit/test_corroboration.nova | skimmed (script-analysed) | 98 | Working | 20 assertions (20 vs literal, 0 weak >=0/!=0/const); exercises corroboration |
| CE/tests/unit/test_counterfactual.nova | reviewed | 51 | Working | 8 assertions (7 vs literal, 0 weak >=0/!=0/const); exercises counterfactual |
| CE/tests/unit/test_cross_kg_references.nova | skimmed (script-analysed) | 109 | Working | 20 assertions (18 vs literal, 1 weak >=0/!=0/const); exercises cross_kg_references |
| CE/tests/unit/test_daemon_tls_bootstrap.nova | skimmed (script-analysed) | 147 | Working | 9 assertions (7 vs literal, 0 weak >=0/!=0/const); exercises base64, tls_config, ed25519 |
| CE/tests/unit/test_debate.nova | skimmed (script-analysed) | 266 | Working | 46 assertions (43 vs literal, 2 weak >=0/!=0/const); exercises debate |
| CE/tests/unit/test_decay_exemption.nova | skimmed (script-analysed) | 91 | Working | 13 assertions (6 vs literal, 0 weak >=0/!=0/const); exercises verify, bayesian_updates |
| CE/tests/unit/test_decision_log.nova | skimmed (script-analysed) | 106 | Working | 25 assertions (23 vs literal, 0 weak >=0/!=0/const); exercises decision_log |
| CE/tests/unit/test_decision_log_durable.nova | skimmed (script-analysed) | 232 | Working | 38 assertions (36 vs literal, 2 weak >=0/!=0/const); has skip-as-pass path; exercises decision_log, sys_tagged |
| CE/tests/unit/test_decision_record.nova | skimmed (script-analysed) | 127 | Working | 33 assertions (31 vs literal, 0 weak >=0/!=0/const); exercises decision_record |
| CE/tests/unit/test_deflate.nova | skimmed (script-analysed) | 395 | Working | 46 assertions (45 vs literal, 1 weak >=0/!=0/const); exercises deflate_decode |
| CE/tests/unit/test_der.nova | skimmed (script-analysed) | 503 | Working | 73 assertions (71 vs literal, 0 weak >=0/!=0/const); exercises der |
| CE/tests/unit/test_detector_integral.nova | skimmed (script-analysed) | 366 | Working | 23 assertions (13 vs literal, 1 weak >=0/!=0/const); exercises image_detector |
| CE/tests/unit/test_differential_privacy.nova | skimmed (script-analysed) | 300 | Working | 52 assertions (40 vs literal, 3 weak >=0/!=0/const); exercises differential_privacy |
| CE/tests/unit/test_distributed_query.nova | skimmed (script-analysed) | 299 | Working | 36 assertions (33 vs literal, 2 weak >=0/!=0/const); exercises distributed_query, atom_store, multi_kg_manager, str_safe |
| CE/tests/unit/test_distributed_rules.nova | skimmed (script-analysed) | 365 | Working | 42 assertions (31 vs literal, 4 weak >=0/!=0/const); exercises gossip, distributed_rules, atom_store, multi_kg_manager |
| CE/tests/unit/test_dns_resolver.nova | skimmed (script-analysed) | 80 | Working | 17 assertions (16 vs literal, 0 weak >=0/!=0/const); exercises dns_resolver |
| CE/tests/unit/test_domain_contested.nova | skimmed (script-analysed) | 125 | Working | 23 assertions (14 vs literal, 6 weak >=0/!=0/const); exercises nl_query |
| CE/tests/unit/test_dp_budget_ui.nova | skimmed (script-analysed) | 398 | Working | 81 assertions (72 vs literal, 2 weak >=0/!=0/const); exercises differential_privacy, dp_budget_ui |
| CE/tests/unit/test_dr_async_fetch.nova | skimmed (script-analysed) | 731 | Working | 99 assertions (88 vs literal, 8 weak >=0/!=0/const); has skip-as-pass path; exercises gossip, distributed_rules, atom_store, multi_kg_manager |
| CE/tests/unit/test_dream_recombination.nova | reviewed | 42 | Working | 6 assertions (5 vs literal, 0 weak >=0/!=0/const); exercises dream_recombination |
| CE/tests/unit/test_drive_generators.nova | skimmed (script-analysed) | 58 | Working | 15 assertions (10 vs literal, 5 weak >=0/!=0/const); exercises drive_generators |
| CE/tests/unit/test_dtls12.nova | skimmed (script-analysed) | 2981 | Working | 519 assertions (439 vs literal, 41 weak >=0/!=0/const); exercises dtls12, str_safe |
| CE/tests/unit/test_dtls_cert_chain.nova | skimmed (script-analysed) | 425 | Working | 46 assertions (39 vs literal, 5 weak >=0/!=0/const); exercises dtls12, x509_verify, str_safe |
| CE/tests/unit/test_dtls_client_flight.nova | skimmed (script-analysed) | 661 | Working | 93 assertions (77 vs literal, 13 weak >=0/!=0/const); exercises dtls12, gossip_dtls_shim, sha256, p256 |
| CE/tests/unit/test_dtls_ext_parse.nova | skimmed (script-analysed) | 305 | Working | 45 assertions (43 vs literal, 0 weak >=0/!=0/const); exercises dtls12 |
| CE/tests/unit/test_dtls_server_flight.nova | skimmed (script-analysed) | 507 | Working | 93 assertions (86 vs literal, 4 weak >=0/!=0/const); exercises dtls12, gossip_dtls_shim, sha256, p256 |
| CE/tests/unit/test_ecdsa.nova | skimmed (script-analysed) | 435 | Working | 25 assertions (25 vs literal, 0 weak >=0/!=0/const); exercises ecdsa |
| CE/tests/unit/test_ed25519.nova | skimmed (script-analysed) | 558 | Working | 62 assertions (58 vs literal, 1 weak >=0/!=0/const); exercises ed25519 |
| CE/tests/unit/test_edition_gate.nova | skimmed (script-analysed) | 114 | Working | 50 assertions (33 vs literal, 14 weak >=0/!=0/const); exercises edition_gate |
| CE/tests/unit/test_effector_gate.nova | skimmed (script-analysed) | 86 | Working | 23 assertions (22 vs literal, 0 weak >=0/!=0/const); exercises effector_gate |
| CE/tests/unit/test_effectors.nova | skimmed (script-analysed) | 67 | Working | 19 assertions (18 vs literal, 0 weak >=0/!=0/const); exercises effector_code_exec, effector_file_ops, effector_http_action, effector_mcp |
| CE/tests/unit/test_emotion_plasticity_mod.nova | reviewed | 31 | Working | 7 assertions (6 vs literal, 0 weak >=0/!=0/const); exercises plasticity_mod |
| CE/tests/unit/test_entity_resolve.nova | skimmed (script-analysed) | 159 | Working | 29 assertions (22 vs literal, 0 weak >=0/!=0/const); exercises entity_resolve |
| CE/tests/unit/test_episode_storage.nova | skimmed (script-analysed) | 72 | Working | 19 assertions (18 vs literal, 1 weak >=0/!=0/const); exercises episode_storage |
| CE/tests/unit/test_episodic.nova | skimmed (script-analysed) | 370 | Working | 79 assertions (60 vs literal, 1 weak >=0/!=0/const); exercises episodic, snapshot_disk |
| CE/tests/unit/test_episodic_retrieval.nova | skimmed (script-analysed) | 411 | Working | 77 assertions (76 vs literal, 1 weak >=0/!=0/const); exercises episodic |
| CE/tests/unit/test_epistemic_status.nova | skimmed (script-analysed) | 113 | Working | 23 assertions (16 vs literal, 2 weak >=0/!=0/const); exercises epistemic_status |
| CE/tests/unit/test_event_dispatch.nova | skimmed (script-analysed) | 48 | Working | 15 assertions (13 vs literal, 0 weak >=0/!=0/const); exercises event_dispatch |
| CE/tests/unit/test_face_detect.nova | skimmed (script-analysed) | 346 | Working | 37 assertions (27 vs literal, 5 weak >=0/!=0/const); exercises image_face_detect |
| CE/tests/unit/test_face_recognize.nova | skimmed (script-analysed) | 416 | Working | 48 assertions (48 vs literal, 0 weak >=0/!=0/const); exercises image_face_recognize |
| CE/tests/unit/test_fed_daemon_attest.nova | skimmed (script-analysed) | 454 | Working | 54 assertions (47 vs literal, 6 weak >=0/!=0/const); exercises gossip, snapshot_attestation, ed25519, fed_slash |
| CE/tests/unit/test_fed_daemon_boot.nova | skimmed (script-analysed) | 361 | Working | 49 assertions (37 vs literal, 12 weak >=0/!=0/const); exercises atom_store, multi_kg_manager, reasoning_atoms, meta_observer |
| CE/tests/unit/test_fed_daemon_leader.nova | skimmed (script-analysed) | 388 | Working | 49 assertions (38 vs literal, 4 weak >=0/!=0/const); exercises gossip, leader_election |
| CE/tests/unit/test_fed_daemon_replication.nova | skimmed (script-analysed) | 439 | Working | 59 assertions (49 vs literal, 4 weak >=0/!=0/const); exercises gossip, snapshot_attestation, snapshot_replication, ed25519 |
| CE/tests/unit/test_fed_daemon_rules.nova | skimmed (script-analysed) | 336 | Working | 44 assertions (32 vs literal, 4 weak >=0/!=0/const); exercises atom_store, multi_kg_manager, rule_inference, gossip |
| CE/tests/unit/test_fed_daemon_transport.nova | skimmed (script-analysed) | 229 | Working | 21 assertions (19 vs literal, 2 weak >=0/!=0/const); exercises p256_keypair, fed_slash |
| CE/tests/unit/test_federated_aggregator.nova | skimmed (script-analysed) | 495 | Working | 90 assertions (72 vs literal, 10 weak >=0/!=0/const); exercises federated_aggregator |
| CE/tests/unit/test_fetch_route_learn.nova | skimmed (script-analysed) | 80 | Working | 11 assertions (10 vs literal, 0 weak >=0/!=0/const); exercises context_bias, spreading_activation, coherence_check, fetch_route_learn |
| CE/tests/unit/test_field25519.nova | skimmed (script-analysed) | 376 | Working | 25 assertions (11 vs literal, 0 weak >=0/!=0/const); exercises field25519 |
| CE/tests/unit/test_first_atoms.nova | skimmed (script-analysed) | 82 | Working | 18 assertions (2 vs literal, 13 weak >=0/!=0/const); exercises first_atoms |
| CE/tests/unit/test_first_nodes.nova | skimmed (script-analysed) | 84 | Working | 29 assertions (29 vs literal, 0 weak >=0/!=0/const); exercises first_nodes |
| CE/tests/unit/test_formal_chat.nova | skimmed (script-analysed) | 567 | Working | 76 assertions (59 vs literal, 6 weak >=0/!=0/const); exercises formal_chat, recheck, cascade |
| CE/tests/unit/test_formal_consistency.nova | skimmed (script-analysed) | 747 | Working | 117 assertions (97 vs literal, 7 weak >=0/!=0/const); exercises formal_chat, recheck, cascade, contradiction |
| CE/tests/unit/test_formal_ingest.nova | skimmed (script-analysed) | 123 | Working | 18 assertions (14 vs literal, 2 weak >=0/!=0/const); exercises formal_ingest |
| CE/tests/unit/test_forward_forward.nova | reviewed | 109 | Working | 8 assertions (4 vs literal, 0 weak >=0/!=0/const); exercises forward_forward |
| CE/tests/unit/test_forward_sim.nova | reviewed | 51 | Working | 7 assertions (7 vs literal, 0 weak >=0/!=0/const); exercises forward_sim |
| CE/tests/unit/test_gaps_register.nova | skimmed (script-analysed) | 286 | Working | 83 assertions (83 vs literal, 0 weak >=0/!=0/const); exercises gaps_register |
| CE/tests/unit/test_gate_router.nova | skimmed (script-analysed) | 115 | Working | 24 assertions (22 vs literal, 0 weak >=0/!=0/const); exercises gate_router |
| CE/tests/unit/test_gc_metrics.nova | skimmed (script-analysed) | 240 | Working | 86 assertions (80 vs literal, 4 weak >=0/!=0/const); exercises gc_metrics |
| CE/tests/unit/test_goal_engine.nova | skimmed (script-analysed) | 94 | Working | 20 assertions (17 vs literal, 0 weak >=0/!=0/const); exercises goal_engine |
| CE/tests/unit/test_goal_persistence.nova | skimmed (script-analysed) | 60 | Working | 11 assertions (10 vs literal, 0 weak >=0/!=0/const); exercises goal_persistence |
| CE/tests/unit/test_goal_templates.nova | skimmed (script-analysed) | 134 | Working | 34 assertions (31 vs literal, 3 weak >=0/!=0/const); exercises goal_templates |
| CE/tests/unit/test_goals_in_soul.nova | skimmed (script-analysed) | 35 | Working | 7 assertions (7 vs literal, 0 weak >=0/!=0/const); exercises goals_in_soul |
| CE/tests/unit/test_gossip.nova | skimmed (script-analysed) | 268 | Working | 34 assertions (28 vs literal, 2 weak >=0/!=0/const); exercises gossip |
| CE/tests/unit/test_gossip_dtls_shim.nova | skimmed (script-analysed) | 483 | Working | 57 assertions (45 vs literal, 7 weak >=0/!=0/const); exercises gossip_dtls_shim, dtls12 |
| CE/tests/unit/test_gossip_dtls_streams.nova | skimmed (script-analysed) | 254 | Working | 24 assertions (22 vs literal, 0 weak >=0/!=0/const); exercises gossip, gossip_dtls_shim, dtls12 |
| CE/tests/unit/test_gossip_noise.nova | skimmed (script-analysed) | 388 | Working | 44 assertions (25 vs literal, 7 weak >=0/!=0/const); exercises gossip |
| CE/tests/unit/test_gossip_relay.nova | skimmed (script-analysed) | 369 | Working | 61 assertions (55 vs literal, 6 weak >=0/!=0/const); exercises gossip, gossip_relay, str_safe |
| CE/tests/unit/test_gossip_relay_bin_dtls.nova | skimmed (script-analysed) | 285 | Working | 27 assertions (16 vs literal, 2 weak >=0/!=0/const); exercises gossip, gossip_dtls_shim, dtls12 |
| CE/tests/unit/test_graph_clustering.nova | skimmed (script-analysed) | 375 | Working | 57 assertions (30 vs literal, 0 weak >=0/!=0/const); exercises atom_store, multi_kg_manager, cross_kg_references, graph_clustering |
| CE/tests/unit/test_hdc_embed.nova | reviewed (assert lines sampled) | 371 | Working | 69 assertions (43 vs literal, 2 weak >=0/!=0/const); exercises hdc_embed, ann_index, multi_kg_manager, word_atoms |
| CE/tests/unit/test_hkdf_sha256.nova | skimmed (script-analysed) | 312 | Working | 29 assertions (29 vs literal, 0 weak >=0/!=0/const); exercises sha256, hkdf_sha256 |
| CE/tests/unit/test_hog_integral.nova | skimmed (script-analysed) | 517 | Working | 34 assertions (21 vs literal, 3 weak >=0/!=0/const); exercises image_hog |
| CE/tests/unit/test_holder_rate.nova | skimmed (script-analysed) | 318 | Working | 73 assertions (56 vs literal, 10 weak >=0/!=0/const); exercises holder_rate, str_safe |
| CE/tests/unit/test_http_client.nova | skimmed (script-analysed) | 358 | Working | 103 assertions (93 vs literal, 3 weak >=0/!=0/const); exercises http_client, internet_fetch |
| CE/tests/unit/test_hybrid_scheduler.nova | skimmed (script-analysed) | 38 | Working | 11 assertions (11 vs literal, 0 weak >=0/!=0/const); exercises hybrid_scheduler |
| CE/tests/unit/test_ice.nova | skimmed (script-analysed) | 466 | Working | 70 assertions (63 vs literal, 4 weak >=0/!=0/const); exercises ice, str_safe |
| CE/tests/unit/test_ice_turn.nova | skimmed (script-analysed) | 895 | Working | 142 assertions (130 vs literal, 7 weak >=0/!=0/const); exercises ice_turn, str_safe |
| CE/tests/unit/test_identity.nova | skimmed (script-analysed) | 41 | Working | 13 assertions (13 vs literal, 0 weak >=0/!=0/const); exercises identity |
| CE/tests/unit/test_image_canny.nova | skimmed (script-analysed) | 334 | Working | 22 assertions (14 vs literal, 4 weak >=0/!=0/const); exercises image_canny, image_sobel |
| CE/tests/unit/test_image_detector.nova | skimmed (script-analysed) | 381 | Working | 32 assertions (26 vs literal, 2 weak >=0/!=0/const); exercises image_detector |
| CE/tests/unit/test_image_harris.nova | skimmed (script-analysed) | 233 | Working | 19 assertions (15 vs literal, 1 weak >=0/!=0/const); exercises image_harris, str_safe |
| CE/tests/unit/test_image_hog.nova | skimmed (script-analysed) | 596 | Working | 58 assertions (47 vs literal, 5 weak >=0/!=0/const); exercises image_hog |
| CE/tests/unit/test_image_ocr.nova | skimmed (script-analysed) | 318 | Working | 40 assertions (35 vs literal, 1 weak >=0/!=0/const); exercises image_ocr |
| CE/tests/unit/test_image_panorama.nova | skimmed (script-analysed) | 457 | Working | 59 assertions (46 vs literal, 8 weak >=0/!=0/const); exercises image_panorama |
| CE/tests/unit/test_image_pgm.nova | skimmed (script-analysed) | 334 | Working | 43 assertions (38 vs literal, 5 weak >=0/!=0/const); exercises image_pgm |
| CE/tests/unit/test_image_records.nova | skimmed (script-analysed) | 315 | Working | 40 assertions (37 vs literal, 3 weak >=0/!=0/const); exercises image_records, perceptual_capsule, curriculum, atom_store |
| CE/tests/unit/test_image_segmentation.nova | skimmed (script-analysed) | 333 | Working | 69 assertions (61 vs literal, 3 weak >=0/!=0/const); exercises image_segmentation |
| CE/tests/unit/test_image_sift.nova | skimmed (script-analysed) | 273 | Working | 27 assertions (20 vs literal, 1 weak >=0/!=0/const); exercises image_sift |
| CE/tests/unit/test_image_sobel.nova | skimmed (script-analysed) | 216 | Working | 30 assertions (23 vs literal, 5 weak >=0/!=0/const); exercises image_sobel |
| CE/tests/unit/test_image_tracker.nova | skimmed (script-analysed) | 262 | Working | 40 assertions (40 vs literal, 0 weak >=0/!=0/const); exercises image_tracker |
| CE/tests/unit/test_imagination_engine.nova | reviewed | 58 | Working | 14 assertions (14 vs literal, 0 weak >=0/!=0/const); exercises imagination_engine |
| CE/tests/unit/test_ingest_chat_integration.nova | skimmed (script-analysed) | 106 | Working | 20 assertions (19 vs literal, 0 weak >=0/!=0/const); exercises ingestion_agent, llm_extractor |
| CE/tests/unit/test_ingest_conceptnet.nova | skimmed (script-analysed) | 94 | Working | 26 assertions (26 vs literal, 0 weak >=0/!=0/const); exercises conceptnet |
| CE/tests/unit/test_ingest_csv.nova | skimmed (script-analysed) | 114 | Working | 21 assertions (20 vs literal, 0 weak >=0/!=0/const); exercises csv_facts |
| CE/tests/unit/test_ingest_curriculum.nova | skimmed (script-analysed) | 99 | Working | 21 assertions (17 vs literal, 4 weak >=0/!=0/const); exercises curriculum, atom_store |
| CE/tests/unit/test_ingest_file_multimodal.nova | skimmed (script-analysed) | 329 | Working | 28 assertions (2 vs literal, 1 weak >=0/!=0/const); exercises rpc_verbs, capability, ingestion_agent, review_queue |
| CE/tests/unit/test_ingest_file_wire.nova | skimmed (script-analysed) | 1132 | Working | 143 assertions (14 vs literal, 0 weak >=0/!=0/const); exercises rpc_verbs, capability, ingestion_agent, review_queue |
| CE/tests/unit/test_ingest_llm_extractor.nova | skimmed (script-analysed) | 103 | Working | 15 assertions (14 vs literal, 0 weak >=0/!=0/const); exercises llm_extractor |
| CE/tests/unit/test_ingest_nt.nova | skimmed (script-analysed) | 98 | Working | 30 assertions (19 vs literal, 5 weak >=0/!=0/const); exercises nt_triples |
| CE/tests/unit/test_ingest_paper_meta.nova | skimmed (script-analysed) | 101 | Working | 20 assertions (18 vs literal, 0 weak >=0/!=0/const); exercises paper_meta |
| CE/tests/unit/test_ingest_pipeline.nova | skimmed (script-analysed) | 191 | Working | 26 assertions (20 vs literal, 5 weak >=0/!=0/const); exercises pipeline |
| CE/tests/unit/test_ingest_pipeline_capsule.nova | skimmed (script-analysed) | 153 | Working | 28 assertions (26 vs literal, 1 weak >=0/!=0/const); exercises pipeline, capsule_registry |
| CE/tests/unit/test_ingest_policy.nova | skimmed (script-analysed) | 816 | Working | 106 assertions (59 vs literal, 5 weak >=0/!=0/const); exercises policy, curriculum, review_queue, multi_kg_manager |
| CE/tests/unit/test_ingest_records.nova | skimmed (script-analysed) | 156 | Working | 39 assertions (36 vs literal, 0 weak >=0/!=0/const); exercises records |
| CE/tests/unit/test_ingest_records_capsule.nova | skimmed (script-analysed) | 132 | Working | 33 assertions (32 vs literal, 0 weak >=0/!=0/const); exercises records |
| CE/tests/unit/test_ingest_review_queue.nova | skimmed (script-analysed) | 133 | Working | 28 assertions (23 vs literal, 5 weak >=0/!=0/const); exercises review_queue |
| CE/tests/unit/test_ingest_source_registry.nova | skimmed (script-analysed) | 81 | Working | 26 assertions (25 vs literal, 1 weak >=0/!=0/const); exercises source_registry |
| CE/tests/unit/test_ingest_web_scheduler.nova | skimmed (script-analysed) | 103 | Working | 20 assertions (17 vs literal, 2 weak >=0/!=0/const); exercises web_scheduler |
| CE/tests/unit/test_ingest_wikidata.nova | skimmed (script-analysed) | 97 | Working | 24 assertions (24 vs literal, 0 weak >=0/!=0/const); exercises wikidata |
| CE/tests/unit/test_ingest_wordnet.nova | skimmed (script-analysed) | 94 | Working | 18 assertions (17 vs literal, 0 weak >=0/!=0/const); exercises wordnet |
| CE/tests/unit/test_ingestion_agent.nova | skimmed (script-analysed) | 133 | Working | 28 assertions (21 vs literal, 2 weak >=0/!=0/const); exercises ingestion_agent |
| CE/tests/unit/test_input_classifier.nova | skimmed (script-analysed) | 80 | Working | 35 assertions (34 vs literal, 1 weak >=0/!=0/const); exercises input_classifier |
| CE/tests/unit/test_input_transducer.nova | skimmed (script-analysed) | 55 | Working | 19 assertions (19 vs literal, 0 weak >=0/!=0/const); exercises input_transducer |
| CE/tests/unit/test_internet_fetch.nova | skimmed (script-analysed) | 147 | Working | 36 assertions (20 vs literal, 1 weak >=0/!=0/const); exercises internet_fetch |
| CE/tests/unit/test_jpeg_decode.nova | reviewed (assert lines sampled) | 672 | Working | 88 assertions (70 vs literal, 14 weak >=0/!=0/const); has skip-as-pass path; exercises jpeg_decode |
| CE/tests/unit/test_json.nova | skimmed (script-analysed) | 107 | Working | 47 assertions (46 vs literal, 0 weak >=0/!=0/const); exercises json |
| CE/tests/unit/test_json_records.nova | skimmed (script-analysed) | 314 | Working | 65 assertions (49 vs literal, 2 weak >=0/!=0/const); exercises json_records, curriculum, source_registry, ingestion_agent |
| CE/tests/unit/test_kg_filter.nova | skimmed (script-analysed) | 243 | Working | 22 assertions (22 vs literal, 0 weak >=0/!=0/const); exercises kg_filter, bake_manifest, multi_kg_manager, atom_store |
| CE/tests/unit/test_kg_query.nova | skimmed (script-analysed) | 327 | Working | 50 assertions (48 vs literal, 1 weak >=0/!=0/const); exercises atom_store, multi_kg_manager, cross_kg_references, query |
| CE/tests/unit/test_kg_query_agg.nova | skimmed (script-analysed) | 373 | Working | 67 assertions (67 vs literal, 0 weak >=0/!=0/const); exercises atom_store, multi_kg_manager, cross_kg_references, query |
| CE/tests/unit/test_kg_query_ext.nova | skimmed (script-analysed) | 367 | Working | 60 assertions (60 vs literal, 0 weak >=0/!=0/const); exercises atom_store, multi_kg_manager, cross_kg_references, query |
| CE/tests/unit/test_kg_rss_ingest.nova | skimmed (script-analysed) | 351 | Working | 59 assertions (46 vs literal, 7 weak >=0/!=0/const); has skip-as-pass path; exercises kg_rss_ingest, multi_kg_manager, atom_store, sys_tagged |
| CE/tests/unit/test_kg_sync.nova | skimmed (script-analysed) | 574 | Working | 169 assertions (137 vs literal, 26 weak >=0/!=0/const); exercises kg_sync, multi_kg_manager |
| CE/tests/unit/test_kg_sync_delta.nova | skimmed (script-analysed) | 502 | Working | 93 assertions (89 vs literal, 2 weak >=0/!=0/const); exercises kg_sync |
| CE/tests/unit/test_kg_temporal.nova | skimmed (script-analysed) | 539 | Working | 80 assertions (80 vs literal, 0 weak >=0/!=0/const); exercises atom_store, multi_kg_manager, temporal |
| CE/tests/unit/test_lbp.nova | skimmed (script-analysed) | 531 | Working | 45 assertions (37 vs literal, 3 weak >=0/!=0/const); exercises image_lbp |
| CE/tests/unit/test_leader_election.nova | skimmed (script-analysed) | 328 | Working | 40 assertions (39 vs literal, 1 weak >=0/!=0/const); exercises leader_election |
| CE/tests/unit/test_learn_pipeline.nova | reviewed (assert lines sampled) | 172 | Working | 21 assertions (15 vs literal, 5 weak >=0/!=0/const); exercises learn_pipeline |
| CE/tests/unit/test_learn_tag.nova | skimmed (script-analysed) | 356 | Working | 40 assertions (31 vs literal, 0 weak >=0/!=0/const); exercises harness only |
| CE/tests/unit/test_learning_policy.nova | skimmed (script-analysed) | 71 | Working | 24 assertions (18 vs literal, 0 weak >=0/!=0/const); exercises learning_policy |
| CE/tests/unit/test_lexical_anchor.nova | skimmed (script-analysed) | 109 | Working | 27 assertions (26 vs literal, 1 weak >=0/!=0/const); exercises lexical_anchor |
| CE/tests/unit/test_licenses.nova | skimmed (script-analysed) | 90 | Working | 38 assertions (35 vs literal, 0 weak >=0/!=0/const); exercises licenses |
| CE/tests/unit/test_link_prediction.nova | skimmed (script-analysed) | 461 | Working | 77 assertions (67 vs literal, 0 weak >=0/!=0/const); exercises atom_store, multi_kg_manager, cross_kg_references, link_prediction |
| CE/tests/unit/test_lipsync.nova | skimmed (script-analysed) | 522 | Working | 41 assertions (25 vs literal, 0 weak >=0/!=0/const); exercises lipsync |
| CE/tests/unit/test_list_safe.nova | skimmed (script-analysed) | 77 | Working | 23 assertions (23 vs literal, 0 weak >=0/!=0/const); exercises list_safe |
| CE/tests/unit/test_lk_mulacc_simd.nova | skimmed (script-analysed) | 438 | Working | 28 assertions (5 vs literal, 0 weak >=0/!=0/const); exercises image_optical_flow |
| CE/tests/unit/test_lk_u8_simd.nova | skimmed (script-analysed) | 376 | Working | 34 assertions (12 vs literal, 1 weak >=0/!=0/const); exercises image_optical_flow |
| CE/tests/unit/test_llm_transcript.nova | skimmed (script-analysed) | 74 | Working | 10 assertions (10 vs literal, 0 weak >=0/!=0/const); exercises llm_transcript |
| CE/tests/unit/test_long_horizon_goals.nova | skimmed (script-analysed) | 46 | Working | 9 assertions (8 vs literal, 0 weak >=0/!=0/const); exercises long_horizon_goals |
| CE/tests/unit/test_loop_action.nova | skimmed (script-analysed) | 137 | Working | 11 assertions (8 vs literal, 1 weak >=0/!=0/const); exercises loop_action |
| CE/tests/unit/test_loop_coordination.nova | skimmed (script-analysed) | 39 | Working | 16 assertions (16 vs literal, 0 weak >=0/!=0/const); exercises loop_coordination |
| CE/tests/unit/test_loop_emotion.nova | reviewed | 24 | Working | 3 assertions (0 vs literal, 0 weak >=0/!=0/const); exercises loop_emotion |
| CE/tests/unit/test_loop_goals.nova | reviewed | 18 | Working | 3 assertions (0 vs literal, 1 weak >=0/!=0/const); exercises loop_goals |
| CE/tests/unit/test_loop_imagination_idle.nova | reviewed | 30 | Working | 2 assertions (1 vs literal, 0 weak >=0/!=0/const); exercises loop_imagination_idle |
| CE/tests/unit/test_loop_memory.nova | reviewed | 31 | Working | 4 assertions (4 vs literal, 0 weak >=0/!=0/const); exercises loop_memory |
| CE/tests/unit/test_loop_perception.nova | reviewed | 73 | Working | 8 assertions (3 vs literal, 0 weak >=0/!=0/const); exercises loop_perception |
| CE/tests/unit/test_loop_reasoning.nova | reviewed | 32 | Working | 3 assertions (2 vs literal, 0 weak >=0/!=0/const); exercises loop_reasoning |
| CE/tests/unit/test_louvain.nova | skimmed (script-analysed) | 431 | Working | 67 assertions (30 vs literal, 2 weak >=0/!=0/const); exercises atom_store, multi_kg_manager, cross_kg_references, louvain |
| CE/tests/unit/test_loyalty.nova | skimmed (script-analysed) | 33 | Working | 9 assertions (9 vs literal, 0 weak >=0/!=0/const); exercises loyalty |
| CE/tests/unit/test_lp_audit.nova | skimmed (script-analysed) | 88 | Working | 15 assertions (14 vs literal, 0 weak >=0/!=0/const); exercises learn_pipeline |
| CE/tests/unit/test_lp_corroboration.nova | skimmed (script-analysed) | 75 | Working | 5 assertions (5 vs literal, 0 weak >=0/!=0/const); exercises learn_pipeline |
| CE/tests/unit/test_maintenance.nova | skimmed (script-analysed) | 122 | Working | 18 assertions (16 vs literal, 0 weak >=0/!=0/const); exercises maintenance |
| CE/tests/unit/test_md5.nova | skimmed (script-analysed) | 285 | Working | 16 assertions (10 vs literal, 0 weak >=0/!=0/const); exercises md5 |
| CE/tests/unit/test_medical_pack.nova | skimmed (script-analysed) | 156 | Working | 22 assertions (2 vs literal, 17 weak >=0/!=0/const); exercises medical_pack, str_safe, imagination_engine |
| CE/tests/unit/test_merkle.nova | skimmed (script-analysed) | 550 | Working | 58 assertions (43 vs literal, 3 weak >=0/!=0/const); exercises merkle, str_safe |
| CE/tests/unit/test_merkle_signing.nova | skimmed (script-analysed) | 367 | Working | 51 assertions (44 vs literal, 4 weak >=0/!=0/const); exercises merkle_signing, ed25519 |
| CE/tests/unit/test_meta_observer.nova | skimmed (script-analysed) | 202 | Working | 35 assertions (33 vs literal, 2 weak >=0/!=0/const); exercises meta_observer, reflection_loop |
| CE/tests/unit/test_meta_observer_feedback.nova | skimmed (script-analysed) | 273 | Working | 54 assertions (53 vs literal, 0 weak >=0/!=0/const); exercises meta_observer, source_authority |
| CE/tests/unit/test_mkgc_scale.nova | reviewed | 121 | Working | 5 assertions (5 vs literal, 0 weak >=0/!=0/const); exercises multi_kg_consistency |
| CE/tests/unit/test_moment_stream.nova | skimmed (script-analysed) | 76 | Working | 29 assertions (29 vs literal, 0 weak >=0/!=0/const); exercises moment_stream |
| CE/tests/unit/test_motor_map.nova | skimmed (script-analysed) | 169 | Working | 52 assertions (51 vs literal, 0 weak >=0/!=0/const); exercises motor_map |
| CE/tests/unit/test_multi_kg_consistency.nova | skimmed (script-analysed) | 138 | Working | 15 assertions (9 vs literal, 0 weak >=0/!=0/const); exercises multi_kg_consistency |
| CE/tests/unit/test_multi_kg_manager.nova | skimmed (script-analysed) | 308 | Working | 86 assertions (80 vs literal, 0 weak >=0/!=0/const); exercises multi_kg_manager, cross_kg_references, reasoning_atoms, episodic |
| CE/tests/unit/test_nat_traversal.nova | reviewed (assert lines sampled) | 1204 | Working | 217 assertions (190 vs literal, 22 weak >=0/!=0/const); exercises nat_traversal, str_safe |
| CE/tests/unit/test_neighborhood_activation.nova | skimmed (script-analysed) | 486 | Working | 47 assertions (12 vs literal, 18 weak >=0/!=0/const); exercises context_bias, neighborhood, spreading_activation |
| CE/tests/unit/test_nl_audit.nova | skimmed (script-analysed) | 87 | Working | 13 assertions (11 vs literal, 2 weak >=0/!=0/const); exercises nl_audit |
| CE/tests/unit/test_nl_chat_llm_fallback.nova | skimmed (script-analysed) | 150 | Working | 26 assertions (23 vs literal, 0 weak >=0/!=0/const); exercises nl_llm_sidecar, nl_metrics, grammar_parser, query_shape |
| CE/tests/unit/test_nl_chat_wire.nova | skimmed (script-analysed) | 223 | Working | 29 assertions (17 vs literal, 1 weak >=0/!=0/const); exercises grammar_parser, executor, templater, multi_kg_manager |
| CE/tests/unit/test_nl_contested.nova | skimmed (script-analysed) | 87 | Working | 14 assertions (6 vs literal, 5 weak >=0/!=0/const); exercises nl_query |
| CE/tests/unit/test_nl_executor.nova | skimmed (script-analysed) | 530 | Working | 76 assertions (66 vs literal, 7 weak >=0/!=0/const); exercises executor, grammar_parser |
| CE/tests/unit/test_nl_generate.nova | reviewed (assert lines sampled) | 99 | Working | 35 assertions (35 vs literal, 0 weak >=0/!=0/const); exercises nl_generate |
| CE/tests/unit/test_nl_grammar_parser.nova | skimmed (script-analysed) | 1263 | Working | 314 assertions (314 vs literal, 0 weak >=0/!=0/const); exercises grammar_parser |
| CE/tests/unit/test_nl_intent_classifier.nova | reviewed (assert lines sampled) | 339 | Working | 71 assertions (53 vs literal, 1 weak >=0/!=0/const); exercises nl_intent_classifier, nl_metrics, query_shape, str_safe |
| CE/tests/unit/test_nl_llm_parser.nova | skimmed (script-analysed) | 271 | Working | 66 assertions (57 vs literal, 9 weak >=0/!=0/const); exercises llm_parser, query_shape, str_safe |
| CE/tests/unit/test_nl_llm_sidecar.nova | skimmed (script-analysed) | 237 | Working | 53 assertions (51 vs literal, 2 weak >=0/!=0/const); exercises nl_llm_sidecar, nl_metrics, llm_parser, query_shape |
| CE/tests/unit/test_nl_metrics.nova | skimmed (script-analysed) | 224 | Working | 74 assertions (69 vs literal, 0 weak >=0/!=0/const); exercises nl_metrics, str_safe |
| CE/tests/unit/test_nl_pipeline_gap_recording.nova | skimmed (script-analysed) | 237 | Working | 17 assertions (5 vs literal, 2 weak >=0/!=0/const); exercises rpc_verbs, multi_kg_manager, atom_store, skill_registry |
| CE/tests/unit/test_nl_query.nova | skimmed (script-analysed) | 224 | Working | 55 assertions (53 vs literal, 0 weak >=0/!=0/const); exercises nl_query |
| CE/tests/unit/test_nl_query_shape.nova | skimmed (script-analysed) | 237 | Working | 86 assertions (74 vs literal, 7 weak >=0/!=0/const); exercises query_shape |
| CE/tests/unit/test_nl_rpc_llm_fallback.nova | skimmed (script-analysed) | 262 | Working | 43 assertions (29 vs literal, 0 weak >=0/!=0/const); exercises rpc_verbs, nl_llm_sidecar, nl_intent_classifier, nl_metrics |
| CE/tests/unit/test_nl_rpc_metrics_verb.nova | skimmed (script-analysed) | 481 | Working | 90 assertions (10 vs literal, 0 weak >=0/!=0/const); exercises rpc_verbs, nl_llm_sidecar, nl_metrics, query_shape |
| CE/tests/unit/test_nl_rpc_server.nova | skimmed (script-analysed) | 259 | Working | 37 assertions (4 vs literal, 0 weak >=0/!=0/const); exercises rpc_server, rpc_verbs, multi_kg_manager, atom_store |
| CE/tests/unit/test_nl_rpc_verbs.nova | skimmed (script-analysed) | 461 | Working | 87 assertions (10 vs literal, 0 weak >=0/!=0/const); exercises rpc_verbs, query_shape, multi_kg_manager, atom_store |
| CE/tests/unit/test_nl_templater.nova | skimmed (script-analysed) | 388 | Working | 60 assertions (15 vs literal, 3 weak >=0/!=0/const); exercises templater, executor, query_shape, skill_supervisor |
| CE/tests/unit/test_node_pool_manager.nova | reviewed (assert lines sampled) | 114 | Working | 40 assertions (37 vs literal, 2 weak >=0/!=0/const); exercises node_pool_manager |
| CE/tests/unit/test_noise_xk.nova | skimmed (script-analysed) | 353 | Working | 44 assertions (27 vs literal, 10 weak >=0/!=0/const); exercises chacha20, noise_xk, str_safe |
| CE/tests/unit/test_number_words.nova | skimmed (script-analysed) | 112 | Working | 45 assertions (45 vs literal, 0 weak >=0/!=0/const); exercises number_words |
| CE/tests/unit/test_ocean_conditioning.nova | skimmed (script-analysed) | 43 | Working | 8 assertions (6 vs literal, 0 weak >=0/!=0/const); exercises ocean_conditioning |
| CE/tests/unit/test_openie.nova | skimmed (script-analysed) | 168 | Working | 64 assertions (55 vs literal, 9 weak >=0/!=0/const); exercises openie |
| CE/tests/unit/test_operand_builder.nova | skimmed (script-analysed) | 206 | Working | 41 assertions (38 vs literal, 0 weak >=0/!=0/const); exercises operand_builder, goal_templates |
| CE/tests/unit/test_ops_pack.nova | skimmed (script-analysed) | 88 | Working | 10 assertions (1 vs literal, 7 weak >=0/!=0/const); exercises ops_runbook_pack, imagination_engine |
| CE/tests/unit/test_optical_flow.nova | skimmed (script-analysed) | 429 | Working | 53 assertions (49 vs literal, 3 weak >=0/!=0/const); exercises image_optical_flow, str_safe |
| CE/tests/unit/test_optical_flow_perpixel.nova | skimmed (script-analysed) | 475 | Working | 34 assertions (18 vs literal, 3 weak >=0/!=0/const); exercises image_optical_flow, str_safe |
| CE/tests/unit/test_optical_flow_pyramid.nova | skimmed (script-analysed) | 424 | Working | 52 assertions (38 vs literal, 5 weak >=0/!=0/const); exercises image_optical_flow, str_safe |
| CE/tests/unit/test_orb.nova | skimmed (script-analysed) | 478 | Working | 43 assertions (23 vs literal, 4 weak >=0/!=0/const); exercises image_orb |
| CE/tests/unit/test_output_generation.nova | skimmed (script-analysed) | 123 | Working | 14 assertions (8 vs literal, 3 weak >=0/!=0/const); exercises output_generation |
| CE/tests/unit/test_override_mechanism.nova | skimmed (script-analysed) | 96 | Working | 27 assertions (27 vs literal, 0 weak >=0/!=0/const); exercises override_mechanism |
| CE/tests/unit/test_override_wire.nova | skimmed (script-analysed) | 333 | Working | 89 assertions (79 vs literal, 8 weak >=0/!=0/const); exercises override_wire, override_mechanism, multi_kg_manager, atom_store |
| CE/tests/unit/test_ownership.nova | skimmed (script-analysed) | 1059 | Working | 173 assertions (84 vs literal, 0 weak >=0/!=0/const); exercises ownership, capability, rpc_verbs, multi_kg_manager |
| CE/tests/unit/test_p256.nova | skimmed (script-analysed) | 401 | Working | 52 assertions (38 vs literal, 11 weak >=0/!=0/const); exercises p256, str_safe |
| CE/tests/unit/test_p256_keypair_load.nova | skimmed (script-analysed) | 254 | Working | 31 assertions (19 vs literal, 7 weak >=0/!=0/const); exercises p256_keypair |
| CE/tests/unit/test_pack_biology.nova | skimmed (script-analysed) | 109 | Working | 23 assertions (6 vs literal, 17 weak >=0/!=0/const); exercises ingestion_agent, multi_kg_consistency |
| CE/tests/unit/test_pack_physics.nova | skimmed (script-analysed) | 80 | Working | 6 assertions (6 vs literal, 0 weak >=0/!=0/const); exercises ingestion_agent, multi_kg_consistency |
| CE/tests/unit/test_pack_politics.nova | skimmed (script-analysed) | 103 | Working | 17 assertions (6 vs literal, 11 weak >=0/!=0/const); exercises ingestion_agent, multi_kg_consistency |
| CE/tests/unit/test_pack_registry.nova | skimmed (script-analysed) | 163 | Working | 27 assertions (9 vs literal, 5 weak >=0/!=0/const); exercises pack_registry, imagination_engine |
| CE/tests/unit/test_pack_religion.nova | skimmed (script-analysed) | 99 | Working | 14 assertions (6 vs literal, 8 weak >=0/!=0/const); exercises ingestion_agent, multi_kg_consistency |
| CE/tests/unit/test_pack_solar_system.nova | skimmed (script-analysed) | 108 | Working | 16 assertions (15 vs literal, 0 weak >=0/!=0/const); exercises ingestion_agent, multi_kg_consistency |
| CE/tests/unit/test_pack_world_history.nova | skimmed (script-analysed) | 62 | Working | 9 assertions (5 vs literal, 4 weak >=0/!=0/const); exercises ingestion_agent |
| CE/tests/unit/test_pagerank.nova | skimmed (script-analysed) | 537 | Working | 87 assertions (49 vs literal, 6 weak >=0/!=0/const); exercises atom_store, multi_kg_manager, cross_kg_references, pagerank |
| CE/tests/unit/test_part_lifecycle.nova | skimmed (script-analysed) | 78 | Working | 21 assertions (18 vs literal, 0 weak >=0/!=0/const); exercises part_lifecycle |
| CE/tests/unit/test_part_registry.nova | skimmed (script-analysed) | 76 | Working | 26 assertions (24 vs literal, 1 weak >=0/!=0/const); exercises part_registry |
| CE/tests/unit/test_pattern_capsule.nova | skimmed (script-analysed) | 338 | Working | 68 assertions (43 vs literal, 7 weak >=0/!=0/const); exercises pattern_capsule, str_safe |
| CE/tests/unit/test_pattern_pack.nova | skimmed (script-analysed) | 902 | Working | 144 assertions (85 vs literal, 6 weak >=0/!=0/const); exercises pattern_pack, pattern_capsule, rpc_verbs, capability |
| CE/tests/unit/test_pdf_text.nova | skimmed (script-analysed) | 168 | Working | 18 assertions (15 vs literal, 0 weak >=0/!=0/const); exercises pdf_text, openie |
| CE/tests/unit/test_pem_truststore.nova | skimmed (script-analysed) | 50 | Working | 5 assertions (5 vs literal, 0 weak >=0/!=0/const); exercises pem_truststore |
| CE/tests/unit/test_perception_atoms.nova | skimmed (script-analysed) | 200 | Working | 77 assertions (69 vs literal, 5 weak >=0/!=0/const); exercises perception_atoms |
| CE/tests/unit/test_perception_module.nova | skimmed (script-analysed) | 221 | Working | 45 assertions (30 vs literal, 1 weak >=0/!=0/const); exercises perception_module |
| CE/tests/unit/test_perceptual_capsule.nova | skimmed (script-analysed) | 187 | Working | 61 assertions (59 vs literal, 0 weak >=0/!=0/const); exercises perceptual_capsule, curriculum, atom_store, str_safe |
| CE/tests/unit/test_permission_tiers.nova | skimmed (script-analysed) | 63 | Working | 24 assertions (24 vs literal, 0 weak >=0/!=0/const); exercises permission_tiers |
| CE/tests/unit/test_persona.nova | skimmed (script-analysed) | 204 | Working | 85 assertions (84 vs literal, 1 weak >=0/!=0/const); exercises persona |
| CE/tests/unit/test_persona_export.nova | skimmed (script-analysed) | 185 | Working | 59 assertions (52 vs literal, 6 weak >=0/!=0/const); exercises persona_export |
| CE/tests/unit/test_persona_project.nova | skimmed (script-analysed) | 180 | Working | 37 assertions (27 vs literal, 4 weak >=0/!=0/const); exercises persona_project |
| CE/tests/unit/test_persona_registry.nova | skimmed (script-analysed) | 117 | Working | 36 assertions (33 vs literal, 1 weak >=0/!=0/const); exercises persona_registry |
| CE/tests/unit/test_phoneme_atoms.nova | skimmed (script-analysed) | 54 | Working | 12 assertions (10 vs literal, 1 weak >=0/!=0/const); exercises phoneme_atoms |
| CE/tests/unit/test_pitch_auto.nova | skimmed (script-analysed) | 336 | Working | 31 assertions (16 vs literal, 0 weak >=0/!=0/const); exercises audio_pitch, audio_synth |
| CE/tests/unit/test_planner.nova | skimmed (script-analysed) | 124 | Working | 21 assertions (20 vs literal, 0 weak >=0/!=0/const); exercises planner |
| CE/tests/unit/test_plasticity_modulation.nova | skimmed (script-analysed) | 40 | Working | 10 assertions (10 vs literal, 0 weak >=0/!=0/const); exercises plasticity_modulation |
| CE/tests/unit/test_png_decode.nova | skimmed (script-analysed) | 504 | Working | 44 assertions (35 vs literal, 9 weak >=0/!=0/const); exercises deflate_decode, png_decode |
| CE/tests/unit/test_poly1305.nova | skimmed (script-analysed) | 334 | Working | 47 assertions (47 vs literal, 0 weak >=0/!=0/const); exercises chacha20, poly1305 |
| CE/tests/unit/test_predictive_coding_runtime.nova | skimmed (script-analysed) | 95 | Working | 30 assertions (22 vs literal, 0 weak >=0/!=0/const); exercises predictive_coding_runtime |
| CE/tests/unit/test_preference_snapshot.nova | skimmed (script-analysed) | 188 | Working | 36 assertions (29 vs literal, 1 weak >=0/!=0/const); exercises session_snapshot, user_preference, str_safe |
| CE/tests/unit/test_preprocess.nova | skimmed (script-analysed) | 460 | Working | 100 assertions (76 vs literal, 5 weak >=0/!=0/const); exercises preprocess, str_safe |
| CE/tests/unit/test_promotion.nova | skimmed (script-analysed) | 141 | Working | 38 assertions (37 vs literal, 0 weak >=0/!=0/const); exercises promotion |
| CE/tests/unit/test_promotion_pass.nova | skimmed (script-analysed) | 168 | Working | 23 assertions (22 vs literal, 1 weak >=0/!=0/const); exercises promotion_pass |
| CE/tests/unit/test_proof_checker.nova | skimmed (script-analysed) | 285 | Working | 56 assertions (42 vs literal, 1 weak >=0/!=0/const); exercises proof_checker, str_safe |
| CE/tests/unit/test_proof_serial.nova | skimmed (script-analysed) | 188 | Working | 20 assertions (20 vs literal, 0 weak >=0/!=0/const); exercises proof_serial |
| CE/tests/unit/test_proofs.nova | skimmed (script-analysed) | 65 | Working | 15 assertions (15 vs literal, 0 weak >=0/!=0/const); exercises proofs |
| CE/tests/unit/test_psola.nova | skimmed (script-analysed) | 297 | Working | 34 assertions (9 vs literal, 3 weak >=0/!=0/const); exercises audio_psola, audio_pitch, audio_synth |
| CE/tests/unit/test_raft_cluster.nova | skimmed (script-analysed) | 104 | Working | 21 assertions (21 vs literal, 0 weak >=0/!=0/const); exercises raft_cluster |
| CE/tests/unit/test_raft_core.nova | skimmed (script-analysed) | 160 | Working | 35 assertions (35 vs literal, 0 weak >=0/!=0/const); exercises raft_core |
| CE/tests/unit/test_raft_membership.nova | skimmed (script-analysed) | 94 | Working | 22 assertions (22 vs literal, 0 weak >=0/!=0/const); exercises raft_membership |
| CE/tests/unit/test_raft_partition.nova | skimmed (script-analysed) | 81 | Working | 15 assertions (15 vs literal, 0 weak >=0/!=0/const); exercises raft_partition |
| CE/tests/unit/test_reader.nova | skimmed (script-analysed) | 62 | Working | 13 assertions (12 vs literal, 0 weak >=0/!=0/const); exercises reader |
| CE/tests/unit/test_reader_xref_traversal.nova | skimmed (script-analysed) | 440 | Working | 51 assertions (45 vs literal, 3 weak >=0/!=0/const); exercises neighborhood |
| CE/tests/unit/test_realtime_pacer.nova | skimmed (script-analysed) | 149 | Working | 27 assertions (20 vs literal, 3 weak >=0/!=0/const); exercises realtime_pacer |
| CE/tests/unit/test_reasoning_atoms.nova | skimmed (script-analysed) | 147 | Working | 30 assertions (26 vs literal, 0 weak >=0/!=0/const); exercises reasoning_atoms |
| CE/tests/unit/test_reasoning_bench.nova | reviewed (assert lines sampled) | 223 | Working | 45 assertions (37 vs literal, 2 weak >=0/!=0/const); exercises reasoning_bench |
| CE/tests/unit/test_reasoning_module.nova | skimmed (script-analysed) | 72 | Working | 12 assertions (11 vs literal, 0 weak >=0/!=0/const); exercises reasoning_module |
| CE/tests/unit/test_reasoning_workflow.nova | skimmed (script-analysed) | 231 | Working | 37 assertions (31 vs literal, 2 weak >=0/!=0/const); exercises formal_chat, recheck, contradiction |
| CE/tests/unit/test_recheck.nova | skimmed (script-analysed) | 198 | Working | 27 assertions (23 vs literal, 1 weak >=0/!=0/const); exercises recheck, formal_ingest |
| CE/tests/unit/test_reflection_loop.nova | skimmed (script-analysed) | 157 | Working | 16 assertions (6 vs literal, 3 weak >=0/!=0/const); exercises reflection_loop |
| CE/tests/unit/test_relay_ranking.nova | skimmed (script-analysed) | 310 | Working | 42 assertions (41 vs literal, 0 weak >=0/!=0/const); exercises gossip, gossip_relay, str_safe |
| CE/tests/unit/test_relay_secure.nova | skimmed (script-analysed) | 376 | Working | 44 assertions (40 vs literal, 4 weak >=0/!=0/const); exercises gossip, gossip_relay, gossip_relay_secure, noise_xk |
| CE/tests/unit/test_relay_secure_binary.nova | skimmed (script-analysed) | 432 | Working | 51 assertions (41 vs literal, 7 weak >=0/!=0/const); exercises gossip, gossip_relay, gossip_relay_secure, noise_xk |
| CE/tests/unit/test_research_skill.nova | skimmed (script-analysed) | 280 | Working | 25 assertions (24 vs literal, 0 weak >=0/!=0/const); exercises skill_dispatch, research_skill, ingestion_agent |
| CE/tests/unit/test_research_sources.nova | skimmed (script-analysed) | 214 | Working | 58 assertions (42 vs literal, 0 weak >=0/!=0/const); exercises research_sources, str_safe |
| CE/tests/unit/test_resonance_engine.nova | skimmed (script-analysed) | 100 | Working | 20 assertions (20 vs literal, 0 weak >=0/!=0/const); exercises resonance_engine |
| CE/tests/unit/test_reversibility_classifier.nova | skimmed (script-analysed) | 53 | Working | 21 assertions (21 vs literal, 0 weak >=0/!=0/const); exercises reversibility_classifier |
| CE/tests/unit/test_rng.nova | skimmed (script-analysed) | 474 | Working | 56 assertions (52 vs literal, 0 weak >=0/!=0/const); exercises sha256, chacha20, rng |
| CE/tests/unit/test_router_audit.nova | skimmed (script-analysed) | 72 | Working | 6 assertions (5 vs literal, 1 weak >=0/!=0/const); exercises cognitive_router |
| CE/tests/unit/test_rsa.nova | skimmed (script-analysed) | 66 | Working | 5 assertions (5 vs literal, 0 weak >=0/!=0/const); exercises rsa |
| CE/tests/unit/test_rule_explain.nova | skimmed (script-analysed) | 360 | Working | 54 assertions (39 vs literal, 5 weak >=0/!=0/const); exercises atom_store, multi_kg_manager, rule_inference, rule_explain |
| CE/tests/unit/test_rule_inference.nova | reviewed (assert lines sampled) | 358 | Working | 47 assertions (43 vs literal, 0 weak >=0/!=0/const); exercises atom_store, multi_kg_manager, rule_inference |
| CE/tests/unit/test_scenario_planner.nova | skimmed (script-analysed) | 43 | Working | 6 assertions (6 vs literal, 0 weak >=0/!=0/const); exercises scenario_planner |
| CE/tests/unit/test_schema_migration.nova | skimmed (script-analysed) | 407 | Working | 78 assertions (68 vs literal, 2 weak >=0/!=0/const); exercises schema_migration, snapshot_disk, snapshot_reader, atom_store |
| CE/tests/unit/test_schemas.nova | skimmed (script-analysed) | 78 | Working | 13 assertions (13 vs literal, 0 weak >=0/!=0/const); exercises schemas, str_safe |
| CE/tests/unit/test_scram.nova | skimmed (script-analysed) | 515 | Working | 43 assertions (40 vs literal, 0 weak >=0/!=0/const); exercises scram, str_safe |
| CE/tests/unit/test_search.nova | skimmed (script-analysed) | 124 | Working | 11 assertions (10 vs literal, 1 weak >=0/!=0/const); exercises search |
| CE/tests/unit/test_search_back.nova | skimmed (script-analysed) | 85 | Working | 10 assertions (9 vs literal, 1 weak >=0/!=0/const); exercises search_back |
| CE/tests/unit/test_search_uni.nova | skimmed (script-analysed) | 81 | Working | 6 assertions (6 vs literal, 0 weak >=0/!=0/const); exercises search_uni |
| CE/tests/unit/test_secure_aggregation.nova | skimmed (script-analysed) | 942 | Working | 170 assertions (114 vs literal, 21 weak >=0/!=0/const); exercises secure_aggregation, str_safe |
| CE/tests/unit/test_secure_channel.nova | skimmed (script-analysed) | 169 | Working | 16 assertions (13 vs literal, 2 weak >=0/!=0/const); exercises chacha20, secure_channel, str_safe |
| CE/tests/unit/test_self_confidence_verb.nova | skimmed (script-analysed) | 335 | Working | 46 assertions (6 vs literal, 0 weak >=0/!=0/const); exercises rpc_verbs, multi_kg_manager, atom_store, capability |
| CE/tests/unit/test_self_gaps_verb.nova | skimmed (script-analysed) | 307 | Working | 51 assertions (5 vs literal, 0 weak >=0/!=0/const); exercises rpc_verbs, capability, gaps_register, str_safe |
| CE/tests/unit/test_self_improve.nova | reviewed (assert lines sampled) | 195 | Working | 55 assertions (32 vs literal, 2 weak >=0/!=0/const); exercises self_improve, state, skills_kg |
| CE/tests/unit/test_self_learning_triggers.nova | reviewed (assert lines sampled) | 90 | Working | 27 assertions (27 vs literal, 0 weak >=0/!=0/const); exercises self_learning_triggers |
| CE/tests/unit/test_self_model_query.nova | reviewed | 44 | Working | 9 assertions (0 vs literal, 9 weak >=0/!=0/const); exercises self_model_query, str_safe |
| CE/tests/unit/test_self_override_list_verb.nova | skimmed (script-analysed) | 252 | Working | 42 assertions (5 vs literal, 0 weak >=0/!=0/const); exercises rpc_verbs, capability, override_wire, str_safe |
| CE/tests/unit/test_self_override_verb.nova | skimmed (script-analysed) | 447 | Working | 66 assertions (14 vs literal, 0 weak >=0/!=0/const); exercises rpc_verbs, capability, override_wire, override_mechanism |
| CE/tests/unit/test_semantic_search.nova | reviewed (assert lines sampled) | 387 | Working | 74 assertions (62 vs literal, 2 weak >=0/!=0/const); exercises semantic_search |
| CE/tests/unit/test_sensor_fusion.nova | skimmed (script-analysed) | 360 | Working | 59 assertions (51 vs literal, 0 weak >=0/!=0/const); exercises sensor_fusion, str_safe |
| CE/tests/unit/test_session.nova | skimmed (script-analysed) | 255 | Working | 66 assertions (57 vs literal, 5 weak >=0/!=0/const); exercises session, identity, state, str_safe |
| CE/tests/unit/test_session_attach_fed.nova | skimmed (script-analysed) | 125 | Working | 29 assertions (29 vs literal, 0 weak >=0/!=0/const); exercises session, str_safe |
| CE/tests/unit/test_session_paths.nova | skimmed (script-analysed) | 200 | Working | 22 assertions (22 vs literal, 0 weak >=0/!=0/const); exercises session |
| CE/tests/unit/test_session_snapshot.nova | skimmed (script-analysed) | 1204 | Working | 228 assertions (136 vs literal, 12 weak >=0/!=0/const); exercises session_snapshot, capability, skill_signature, ownership |
| CE/tests/unit/test_sha1.nova | skimmed (script-analysed) | 352 | Working | 17 assertions (12 vs literal, 0 weak >=0/!=0/const); exercises sha1 |
| CE/tests/unit/test_sha256.nova | skimmed (script-analysed) | 373 | Working | 20 assertions (16 vs literal, 0 weak >=0/!=0/const); exercises sha256 |
| CE/tests/unit/test_sift_descriptor.nova | skimmed (script-analysed) | 495 | Working | 33 assertions (24 vs literal, 1 weak >=0/!=0/const); exercises image_sift |
| CE/tests/unit/test_signal_dispatch.nova | skimmed (script-analysed) | 127 | Working | 51 assertions (47 vs literal, 0 weak >=0/!=0/const); exercises signal_dispatch |
| CE/tests/unit/test_simd_production.nova | skimmed (script-analysed) | 368 | Working | 35 assertions (12 vs literal, 1 weak >=0/!=0/const); exercises image_stereo, image_optical_flow |
| CE/tests/unit/test_skill_install_wire.nova | skimmed (script-analysed) | 370 | Working | 23 assertions (2 vs literal, 0 weak >=0/!=0/const); exercises rpc_verbs, capability, skill_signature, ed25519 |
| CE/tests/unit/test_skill_manifest.nova | skimmed (script-analysed) | 95 | Working | 36 assertions (36 vs literal, 0 weak >=0/!=0/const); exercises skill_manifest |
| CE/tests/unit/test_skill_registry.nova | skimmed (script-analysed) | 169 | Working | 44 assertions (39 vs literal, 4 weak >=0/!=0/const); exercises skill_registry |
| CE/tests/unit/test_skill_run_scoping.nova | skimmed (script-analysed) | 276 | Working | 28 assertions (13 vs literal, 0 weak >=0/!=0/const); exercises ownership, capability, rpc_verbs, multi_kg_manager |
| CE/tests/unit/test_skill_signature.nova | skimmed (script-analysed) | 344 | Working | 50 assertions (34 vs literal, 2 weak >=0/!=0/const); exercises skill_signature, ed25519, skill_manifest, echo_skill |
| CE/tests/unit/test_skill_supervisor.nova | skimmed (script-analysed) | 284 | Working | 46 assertions (32 vs literal, 11 weak >=0/!=0/const); exercises skill_dispatch, echo_skill, capsule_registry, persona |
| CE/tests/unit/test_skills_kg.nova | skimmed (script-analysed) | 112 | Working | 26 assertions (24 vs literal, 0 weak >=0/!=0/const); exercises skills_kg |
| CE/tests/unit/test_slic.nova | skimmed (script-analysed) | 364 | Working | 61 assertions (32 vs literal, 7 weak >=0/!=0/const); exercises image_superpixels |
| CE/tests/unit/test_slot_index.nova | skimmed (script-analysed) | 154 | Working | 23 assertions (22 vs literal, 0 weak >=0/!=0/const); exercises slot_index |
| CE/tests/unit/test_snapshot_attestation.nova | skimmed (script-analysed) | 390 | Working | 66 assertions (62 vs literal, 4 weak >=0/!=0/const); exercises snapshot_attestation, ed25519 |
| CE/tests/unit/test_snapshot_broadcast_hook.nova | skimmed (script-analysed) | 228 | Working | 27 assertions (21 vs literal, 6 weak >=0/!=0/const); exercises snapshot_broadcast_hook, snapshot_attestation, gossip, ed25519 |
| CE/tests/unit/test_snapshot_compaction.nova | skimmed (script-analysed) | 411 | Working | 48 assertions (42 vs literal, 4 weak >=0/!=0/const); exercises snapshot_disk, snapshot_compaction, str_safe |
| CE/tests/unit/test_snapshot_delta.nova | skimmed (script-analysed) | 654 | Working | 84 assertions (68 vs literal, 13 weak >=0/!=0/const); exercises snapshot_disk, snapshot_delta |
| CE/tests/unit/test_snapshot_disk.nova | skimmed (script-analysed) | 127 | Working | 31 assertions (29 vs literal, 2 weak >=0/!=0/const); exercises snapshot_disk |
| CE/tests/unit/test_snapshot_disk_full.nova | skimmed (script-analysed) | 628 | Working | 127 assertions (94 vs literal, 24 weak >=0/!=0/const); exercises snapshot_disk, state, values, ask_user_to_teach |
| CE/tests/unit/test_snapshot_episodic.nova | skimmed (script-analysed) | 261 | Working | 51 assertions (47 vs literal, 4 weak >=0/!=0/const); exercises snapshot_disk |
| CE/tests/unit/test_snapshot_migrate.nova | skimmed (script-analysed) | 182 | Working | 37 assertions (30 vs literal, 7 weak >=0/!=0/const); exercises snapshot_disk, snapshot_reader |
| CE/tests/unit/test_snapshot_reader.nova | skimmed (script-analysed) | 111 | Working | 25 assertions (25 vs literal, 0 weak >=0/!=0/const); exercises snapshot_reader |
| CE/tests/unit/test_snapshot_replication.nova | skimmed (script-analysed) | 313 | Working | 73 assertions (68 vs literal, 3 weak >=0/!=0/const); exercises snapshot_replication, snapshot_attestation, ed25519, snapshot_writer |
| CE/tests/unit/test_snapshot_selfmodel.nova | skimmed (script-analysed) | 194 | Working | 38 assertions (30 vs literal, 8 weak >=0/!=0/const); exercises snapshot_disk |
| CE/tests/unit/test_snapshot_synapses.nova | skimmed (script-analysed) | 427 | Working | 89 assertions (76 vs literal, 13 weak >=0/!=0/const); exercises snapshot_disk, part_registry, first_nodes |
| CE/tests/unit/test_snapshot_writer.nova | skimmed (script-analysed) | 69 | Working | 27 assertions (27 vs literal, 0 weak >=0/!=0/const); exercises snapshot_writer |
| CE/tests/unit/test_soul_state.nova | skimmed (script-analysed) | 40 | Working | 11 assertions (11 vs literal, 0 weak >=0/!=0/const); exercises state |
| CE/tests/unit/test_source_authority.nova | skimmed (script-analysed) | 59 | Working | 22 assertions (16 vs literal, 0 weak >=0/!=0/const); exercises source_authority |
| CE/tests/unit/test_source_whitelist.nova | skimmed (script-analysed) | 42 | Working | 14 assertions (6 vs literal, 0 weak >=0/!=0/const); exercises source_whitelist |
| CE/tests/unit/test_speaker_id.nova | skimmed (script-analysed) | 401 | Working | 53 assertions (51 vs literal, 2 weak >=0/!=0/const); exercises audio_speaker_id, audio_synth |
| CE/tests/unit/test_spreading_activation.nova | reviewed | 78 | Working | 9 assertions (6 vs literal, 0 weak >=0/!=0/const); exercises context_bias, spreading_activation |
| CE/tests/unit/test_srtp.nova | skimmed (script-analysed) | 1088 | Working | 131 assertions (100 vs literal, 8 weak >=0/!=0/const); exercises srtp |
| CE/tests/unit/test_steelman.nova | skimmed (script-analysed) | 80 | Working | 11 assertions (9 vs literal, 2 weak >=0/!=0/const); exercises steelman |
| CE/tests/unit/test_stereo.nova | skimmed (script-analysed) | 350 | Working | 54 assertions (48 vs literal, 4 weak >=0/!=0/const); exercises image_stereo, str_safe |
| CE/tests/unit/test_stereo_quality.nova | skimmed (script-analysed) | 453 | Working | 42 assertions (32 vs literal, 5 weak >=0/!=0/const); exercises image_stereo, str_safe |
| CE/tests/unit/test_stereo_sgm.nova | skimmed (script-analysed) | 452 | Working | 39 assertions (20 vs literal, 5 weak >=0/!=0/const); exercises image_stereo, str_safe |
| CE/tests/unit/test_stereo_u8_simd.nova | skimmed (script-analysed) | 389 | Working | 25 assertions (15 vs literal, 2 weak >=0/!=0/const); exercises image_stereo |
| CE/tests/unit/test_str_safe.nova | skimmed (script-analysed) | 68 | Working | 27 assertions (27 vs literal, 0 weak >=0/!=0/const); exercises str_safe |
| CE/tests/unit/test_stream_audio.nova | skimmed (script-analysed) | 29 | Working | 10 assertions (8 vs literal, 2 weak >=0/!=0/const); exercises stream_audio |
| CE/tests/unit/test_stream_http.nova | skimmed (script-analysed) | 78 | Working | 24 assertions (24 vs literal, 0 weak >=0/!=0/const); exercises stream_http |
| CE/tests/unit/test_stream_stdin.nova | skimmed (script-analysed) | 134 | Working | 28 assertions (27 vs literal, 1 weak >=0/!=0/const); exercises stream_stdin, hybrid_scheduler, part_lifecycle |
| CE/tests/unit/test_stream_unix_socket.nova | skimmed (script-analysed) | 46 | Working | 14 assertions (13 vs literal, 1 weak >=0/!=0/const); exercises stream_unix_socket |
| CE/tests/unit/test_stt_seam.nova | skimmed (script-analysed) | 218 | Working | 27 assertions (25 vs literal, 1 weak >=0/!=0/const); exercises stt_seam |
| CE/tests/unit/test_stun_rfc8489.nova | skimmed (script-analysed) | 632 | Working | 135 assertions (91 vs literal, 20 weak >=0/!=0/const); exercises stun_rfc8489, str_safe |
| CE/tests/unit/test_style_capsule.nova | skimmed (script-analysed) | 342 | Working | 52 assertions (25 vs literal, 0 weak >=0/!=0/const); exercises style_capsule, templater, skill_supervisor, persona |
| CE/tests/unit/test_synapse_graph.nova | reviewed (assert lines sampled) | 165 | Working | 55 assertions (49 vs literal, 2 weak >=0/!=0/const); exercises synapse_graph, signal_dispatch |
| CE/tests/unit/test_syntax_atoms.nova | skimmed (script-analysed) | 74 | Working | 14 assertions (13 vs literal, 1 weak >=0/!=0/const); exercises syntax_atoms |
| CE/tests/unit/test_table.nova | skimmed (script-analysed) | 92 | Working | 24 assertions (24 vs literal, 0 weak >=0/!=0/const); exercises table, query, str_safe |
| CE/tests/unit/test_themes.nova | skimmed (script-analysed) | 31 | Working | 7 assertions (7 vs literal, 0 weak >=0/!=0/const); exercises themes |
| CE/tests/unit/test_theory_of_mind.nova | reviewed | 47 | Working | 13 assertions (12 vs literal, 0 weak >=0/!=0/const); exercises theory_of_mind |
| CE/tests/unit/test_three_factor.nova | reviewed | 113 | Working | 18 assertions (6 vs literal, 6 weak >=0/!=0/const); exercises synapse_graph |
| CE/tests/unit/test_tick_driver.nova | skimmed (script-analysed) | 263 | Working | 38 assertions (24 vs literal, 7 weak >=0/!=0/const); exercises tick_driver |
| CE/tests/unit/test_tick_loop.nova | reviewed | 31 | Working | 8 assertions (7 vs literal, 0 weak >=0/!=0/const); exercises tick_loop |
| CE/tests/unit/test_tls13_keyschedule.nova | skimmed (script-analysed) | 136 | Working | 6 assertions (5 vs literal, 0 weak >=0/!=0/const); exercises tls13_client |
| CE/tests/unit/test_tls_alerts.nova | skimmed (script-analysed) | 142 | Working | 31 assertions (26 vs literal, 4 weak >=0/!=0/const); exercises tls_alerts, str_safe |
| CE/tests/unit/test_tls_cert.nova | skimmed (script-analysed) | 365 | Working | 41 assertions (40 vs literal, 0 weak >=0/!=0/const); exercises ed25519, tls_cert |
| CE/tests/unit/test_tls_cert_chain.nova | skimmed (script-analysed) | 323 | Working | 14 assertions (14 vs literal, 0 weak >=0/!=0/const); exercises ed25519, tls_cert, x509 |
| CE/tests/unit/test_tls_config.nova | skimmed (script-analysed) | 173 | Working | 22 assertions (22 vs literal, 0 weak >=0/!=0/const); exercises tls_config, ed25519 |
| CE/tests/unit/test_tls_handshake_msgs.nova | skimmed (script-analysed) | 406 | Working | 54 assertions (46 vs literal, 8 weak >=0/!=0/const); exercises tls_handshake |
| CE/tests/unit/test_tls_kdf.nova | skimmed (script-analysed) | 339 | Working | 27 assertions (24 vs literal, 0 weak >=0/!=0/const); exercises sha256, hkdf_sha256, tls_kdf |
| CE/tests/unit/test_tls_keyshare.nova | skimmed (script-analysed) | 191 | Working | 14 assertions (13 vs literal, 1 weak >=0/!=0/const); exercises field25519, x25519, tls_keyshare |
| CE/tests/unit/test_tls_keyshare_rng.nova | skimmed (script-analysed) | 211 | Working | 27 assertions (27 vs literal, 0 weak >=0/!=0/const); exercises field25519, x25519, rng, tls_keyshare |
| CE/tests/unit/test_tls_record_aead.nova | skimmed (script-analysed) | 315 | Working | 41 assertions (37 vs literal, 0 weak >=0/!=0/const); exercises chacha20, poly1305, chacha20_poly1305, tls_record |
| CE/tests/unit/test_tls_scaffold.nova | skimmed (script-analysed) | 207 | Working | 70 assertions (65 vs literal, 5 weak >=0/!=0/const); exercises tls_config, tls_record, tls_handshake, tls_wire_hook |
| CE/tests/unit/test_tls_session.nova | skimmed (script-analysed) | 251 | Working | 23 assertions (21 vs literal, 0 weak >=0/!=0/const); exercises rng, ed25519, tls_session, tls_handshake |
| CE/tests/unit/test_tls_session_tamper.nova | skimmed (script-analysed) | 332 | Working | 15 assertions (15 vs literal, 0 weak >=0/!=0/const); exercises rng, ed25519, tls_session, tls_handshake |
| CE/tests/unit/test_tls_state.nova | skimmed (script-analysed) | 174 | Working | 68 assertions (67 vs literal, 1 weak >=0/!=0/const); exercises tls_state, str_safe |
| CE/tests/unit/test_tls_transcript.nova | skimmed (script-analysed) | 227 | Working | 16 assertions (16 vs literal, 0 weak >=0/!=0/const); exercises tls_transcript, sha256 |
| CE/tests/unit/test_tls_wire_hook.nova | skimmed (script-analysed) | 292 | Working | 40 assertions (35 vs literal, 3 weak >=0/!=0/const); exercises tls_config, tls_wire_hook, rng, ed25519 |
| CE/tests/unit/test_tool.nova | skimmed (script-analysed) | 94 | Working | 25 assertions (24 vs literal, 0 weak >=0/!=0/const); exercises tool |
| CE/tests/unit/test_tool_goal_plan.nova | skimmed (script-analysed) | 122 | Working | 15 assertions (14 vs literal, 0 weak >=0/!=0/const); exercises tool_goal_plan |
| CE/tests/unit/test_tool_use.nova | skimmed (script-analysed) | 152 | Working | 28 assertions (27 vs literal, 0 weak >=0/!=0/const); exercises tool_use, moment_stream |
| CE/tests/unit/test_truststore_dir.nova | skimmed (script-analysed) | 221 | Working | 20 assertions (20 vs literal, 0 weak >=0/!=0/const); exercises pem_truststore |
| CE/tests/unit/test_turn.nova | skimmed (script-analysed) | 2197 | Working | 406 assertions (326 vs literal, 4 weak >=0/!=0/const); exercises turn |
| CE/tests/unit/test_turn_server.nova | skimmed (script-analysed) | 792 | Working | 111 assertions (90 vs literal, 6 weak >=0/!=0/const); exercises turn, turn_server |
| CE/tests/unit/test_type_of_probe.nova | skimmed (script-analysed) | 51 | Working | 11 assertions (11 vs literal, 0 weak >=0/!=0/const); exercises harness only |
| CE/tests/unit/test_unify.nova | skimmed (script-analysed) | 82 | Working | 14 assertions (10 vs literal, 4 weak >=0/!=0/const); exercises unify |
| CE/tests/unit/test_update_apply_verb.nova | skimmed (script-analysed) | 176 | Working | 17 assertions (14 vs literal, 0 weak >=0/!=0/const); exercises rpc_verbs, capability, child_mode, str_safe |
| CE/tests/unit/test_update_delta.nova | skimmed (script-analysed) | 482 | Working | 67 assertions (45 vs literal, 4 weak >=0/!=0/const); exercises update_delta, bake, bake_manifest, bundle_signing |
| CE/tests/unit/test_user_preference.nova | skimmed (script-analysed) | 297 | Working | 78 assertions (78 vs literal, 0 weak >=0/!=0/const); exercises user_preference, str_safe |
| CE/tests/unit/test_user_preference_verbs.nova | skimmed (script-analysed) | 386 | Working | 48 assertions (21 vs literal, 1 weak >=0/!=0/const); has skip-as-pass path; exercises rpc_verbs, capability, user_preference, str_safe |
| CE/tests/unit/test_values.nova | reviewed | 28 | Working | 8 assertions (8 vs literal, 0 weak >=0/!=0/const); exercises values |
| CE/tests/unit/test_verify.nova | skimmed (script-analysed) | 710 | Working | 87 assertions (84 vs literal, 1 weak >=0/!=0/const); exercises verify |
| CE/tests/unit/test_verify_big.nova | skimmed (script-analysed) | 118 | Working | 11 assertions (11 vs literal, 0 weak >=0/!=0/const); exercises proof_serial |
| CE/tests/unit/test_video_motion_vectors.nova | skimmed (script-analysed) | 239 | Working | 30 assertions (25 vs literal, 3 weak >=0/!=0/const); exercises video_motion_vectors |
| CE/tests/unit/test_video_perception.nova | skimmed (script-analysed) | 37 | Working | 11 assertions (11 vs literal, 0 weak >=0/!=0/const); exercises video_perception |
| CE/tests/unit/test_video_records.nova | skimmed (script-analysed) | 194 | Working | 35 assertions (31 vs literal, 4 weak >=0/!=0/const); exercises video_records, perceptual_capsule, curriculum, atom_store |
| CE/tests/unit/test_video_smooth.nova | skimmed (script-analysed) | 214 | Working | 25 assertions (24 vs literal, 0 weak >=0/!=0/const); exercises video_smooth |
| CE/tests/unit/test_video_y4m.nova | skimmed (script-analysed) | 284 | Working | 34 assertions (30 vs literal, 4 weak >=0/!=0/const); exercises video_y4m |
| CE/tests/unit/test_visibility_composed.nova | skimmed (script-analysed) | 173 | Working | 25 assertions (25 vs literal, 0 weak >=0/!=0/const); exercises ownership, user_preference |
| CE/tests/unit/test_visual_perception.nova | skimmed (script-analysed) | 36 | Working | 12 assertions (12 vs literal, 0 weak >=0/!=0/const); exercises visual_perception |
| CE/tests/unit/test_voice_clone.nova | skimmed (script-analysed) | 407 | Working | 55 assertions (39 vs literal, 8 weak >=0/!=0/const); exercises audio_voice_clone, audio_synth, audio_pitch |
| CE/tests/unit/test_voice_conversation.nova | skimmed (script-analysed) | 264 | Working | 27 assertions (16 vs literal, 0 weak >=0/!=0/const); exercises harness only |
| CE/tests/unit/test_voice_dialog.nova | skimmed (script-analysed) | 2142 | Working | 319 assertions (241 vs literal, 0 weak >=0/!=0/const); exercises atom_store, multi_kg_manager, whisper_backend |
| CE/tests/unit/test_vosk_backend.nova | skimmed (script-analysed) | 307 | Working | 45 assertions (36 vs literal, 5 weak >=0/!=0/const); has skip-as-pass path; exercises vosk_backend, stt_seam |
| CE/tests/unit/test_webrtc.nova | skimmed (script-analysed) | 321 | Working | 59 assertions (50 vs literal, 9 weak >=0/!=0/const); exercises webrtc, str_safe |
| CE/tests/unit/test_whisper_backend.nova | skimmed (script-analysed) | 465 | Working | 50 assertions (47 vs literal, 1 weak >=0/!=0/const); exercises whisper_backend, stt_seam |
| CE/tests/unit/test_wire_pagination.nova | skimmed (script-analysed) | 790 | Working | 147 assertions (20 vs literal, 0 weak >=0/!=0/const); exercises rpc_verbs, nl_metrics, multi_kg_manager, atom_store |
| CE/tests/unit/test_word_atoms.nova | skimmed (script-analysed) | 332 | Working | 115 assertions (110 vs literal, 1 weak >=0/!=0/const); exercises word_atoms |
| CE/tests/unit/test_world_model.nova | skimmed (script-analysed) | 108 | Working | 40 assertions (38 vs literal, 0 weak >=0/!=0/const); exercises world_model |
| CE/tests/unit/test_x25519.nova | skimmed (script-analysed) | 296 | Working | 15 assertions (15 vs literal, 0 weak >=0/!=0/const); exercises field25519, x25519 |
| CE/tests/unit/test_x509.nova | skimmed (script-analysed) | 612 | Working | 55 assertions (49 vs literal, 2 weak >=0/!=0/const); exercises x509 |
| CE/tests/unit/test_x509_r92.nova | skimmed (script-analysed) | 507 | Working | 60 assertions (60 vs literal, 0 weak >=0/!=0/const); exercises der, x509 |
| CE/tests/unit/test_x509_verify.nova | skimmed (script-analysed) | 105 | Working | 14 assertions (13 vs literal, 0 weak >=0/!=0/const); exercises x509_verify, str_safe |
| CE/tests/unit/test_yaml_records.nova | skimmed (script-analysed) | 637 | Working | 129 assertions (93 vs literal, 1 weak >=0/!=0/const); exercises yaml_records, curriculum, source_registry, atom_store |
| CE/tests/unit/fixtures/x509_test_certs.nova | skimmed (data) | 441 | Working | Hard-coded test certificate byte arrays for x509 tests |
| CE/tests/integration/README.md | reviewed | 100 | Doc | Describes scenario/admin/failmode scripts |
| CE/tests/integration/_lib.sh | reviewed | 130 | Working | Shared integration-test helpers. Source this from every tests/integration/*.sh script. It exports: [0 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/admin_help_status.sh | skimmed (header+grep) | 146 | Working | Admin commands -- /help, /status, /history, unknown command, quit/exit/empty. These are the read-only commands plus the exit paths; bundled together s [33 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/admin_learn_meta.sh | skimmed (header+grep) | 78 | Working | Admin commands -- /learn (TOPIC/URL/FILE source-kind tagging) and /meta. [7 assert calls; ext: whisper; skip refs: 0] |
| CE/tests/integration/admin_reflect_halt.sh | skimmed (header+grep) | 66 | Working | Admin commands -- /reflect, /halt, /resume. [8 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/admin_save_load.sh | skimmed (header+grep) | 61 | Working | Admin commands -- /save and /load edge cases. [12 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/admin_teach_pin.sh | skimmed (header+grep) | 75 | Working | Admin commands -- /teach and /pin edge cases. [10 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/failmode_chat_long_line.sh | skimmed (header+grep) | 91 | Working | Failure mode -- piping a long line into chat stdin. The original test target was 10K characters; while writing this test we [6 assert calls; ext: python3; skip refs: 0] |
| CE/tests/integration/failmode_constitution_bypass_attempts.sh | reviewed | 105 | Working | Failure mode -- multiple rephrasings of the "exfiltrate" intent must all trigger the constitutional veto, even the ones that AVOID the literal [2 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/failmode_corrupt_snap_recovery.sh | skimmed (header+grep) | 77 | Working | Failure mode -- /load on a truncated snapshot reports a clear error and the running session is unaffected. [6 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/failmode_disk_full_save.sh | skimmed (header+grep) | 58 | Partial | Failure mode -- /save to a write-denied path reports failure cleanly. We can't realistically exhaust /tmp in a sandbox, so we exercise the [7 assert calls; ext: none; skip refs: 2] |
| CE/tests/integration/failmode_dlog_corrupt_tail.sh | skimmed (header+grep) | 90 | Working | Failure mode -- dlog with appended garbage at the tail recovers cleanly. The dl_open recovery loop is supposed to: [5 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/failmode_kgsync_subscriber_drop.sh | skimmed (header+grep) | 180 | Partial | Failure mode -- kg-sync subscriber dies mid-stream. Scenario: publisher binds and accepts; subscriber connects + handshakes; [2 assert calls; ext: none; skip refs: 1] |
| CE/tests/integration/failmode_killed_mid_fsync.sh | skimmed (header+grep) | 90 | Working | Failure mode -- kill -9 during the /save window must not leave a partial snapshot at the final path. [4 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/failmode_runaway_atom_births.sh | skimmed (header+grep) | 94 | Working | Failure mode -- feeding many distinct unknown words rapidly must not blow up the KG. The atom_birth_monitor's gating + the seed/teach paths should res [4 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/failmode_save_load_ping_pong.sh | skimmed (header+grep) | 101 | Working | Failure mode -- alternating /save and /load 20 times in ONE chat session must not progressively corrupt state. After 20 round-trips, the knowledge [8 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/failmode_session_eviction.sh | skimmed (header+grep) | 118 | Partial | Failure mode -- web.py LRU eviction: with CE_WEB_MAX_SESSIONS=2, hitting 5 unique cookies must evict the first 3 (LRU) and keep the most-recent 2 [8 assert calls; ext: python3,curl; skip refs: 3] |
| CE/tests/integration/failmode_soul_mood_overflow.sh | skimmed (header+grep) | 85 | Working | Failure mode -- repeated high-arousal triggers must not overflow the mood valence / arousal counters. [1 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/failmode_unknown_kg_load.sh | skimmed (header+grep) | 52 | Partial | Failure mode -- /load on a snapshot containing a kgs.atoms[N].kg label that the running daemon does not know. [7 assert calls; ext: none; skip refs: 4] |
| CE/tests/integration/failmode_web_concurrent_burst.sh | skimmed (header+grep) | 156 | Partial | Failure mode -- 20 concurrent POSTs to /api/chat with the same cookie must serialize. The web.py ChatChild.send acquires request_lock for the whole [4 assert calls; ext: python3,curl; skip refs: 3] |
| CE/tests/integration/failmode_web_huge_payload.sh | skimmed (header+grep) | 171 | Partial | Failure mode -- POSTing a 1MB body to /api/chat must not crash the server. The web.py handler reads Content-Length bytes and json.loads them. A huge [1 assert calls; ext: python3,curl; skip refs: 3] |
| CE/tests/integration/scenario_a2_full_state.sh | skimmed (header+grep) | 100 | Working | Scenario A2 -- Full-state durability across abrupt restart. Extends scenario_a (which only checks widget survives) to verify the [14 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_a3_dlog.sh | skimmed (header+grep) | 67 | Working | Scenario A3 -- Decision-log durability across abrupt restart (P0.7). Boot fresh -> send 3 messages (each generates dlog entries) -> SIGKILL -> [3 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_a_durability.sh | skimmed (header+grep) | 74 | Working | Scenario A -- Durability across abrupt restart. Boot fresh -> /teach widget -> /save -> SIGKILL -> relaunch -> /load -> [8 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_aa_atom_search.sh | skimmed (header+grep) | 180 | Partial | Scenario AA -- /api/atoms search endpoint (web atom-search UI). python3 scripts/web.py (background) -> GET /api/atoms?q=fever -> verify the [7 assert calls; ext: python3,curl; skip refs: 2] |
| CE/tests/integration/scenario_aaa_psola.sh | skimmed (header+grep) | 129 | Working | Scenario AAA -- R12D: TD-PSOLA pitch shifting + time stretching. [13 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_aaaa_rule_inference.sh | skimmed (header+grep) | 252 | Working | Scenario AAAA -- forward-chaining rule inference over the KG (R20B). Companion to scenario_kkk_query.sh (R15D mini-SPARQL declarative [19 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_aaaaa_dialog.sh | skimmed (header+grep) | 164 | Working | Scenario AAAAA -- R25B.2: multi-turn voice dialogue (conversation state + follow-up handling). Letter `aaaaa` (5x) is the first free 5-letter [13 assert calls; ext: whisper; skip refs: 0] |
| CE/tests/integration/scenario_b_neighborhood.sh | skimmed (header+grep) | 42 | Working | Scenario B -- Neighborhood paraphrase. Boot fresh -> ask "fever" -> verify the reasoning surfaces a related [4 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_bb_why_deep.sh | skimmed (header+grep) | 107 | Working | Scenario BB -- /why-deep [N] recursive decision tree. Boot the chat, teach a word (`/teach widget`), ask it back, then run [10 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_bbb_dp_ui.sh | skimmed (header+grep) | 121 | Working | Scenario BBB -- /dp admin command + status pane DP budget reporting (R12F / ADR-0053 follow-up). [21 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_bbbb_sensor_fusion.sh | skimmed (header+grep) | 167 | Working | Scenario BBBB -- /fuse cross-modal sensor fusion: image + audio coregistered observation primitive (R20C). [7 assert calls; ext: python3; skip refs: 0] |
| CE/tests/integration/scenario_bbbbb_kg_delta.sh | skimmed (header+grep) | 351 | Working | Scenario BBBBB -- R29F: kg_sync delta-compression on top of R23C snapshot replication. Verifies the new src/federation/kg_sync.nova module: [22 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_c_learn.sh | skimmed (header+grep) | 134 | Partial | Scenario C -- Multi-source /learn. Two passes: [5 assert calls; ext: curl; skip refs: 1] |
| CE/tests/integration/scenario_cc_image_match.sh | skimmed (header+grep) | 120 | Working | Scenario CC -- /match_images PGM admin command end-to-end (P3.3 cont. v2, the deferred half of SIFT: 128-D descriptor + Lowe-ratio-test matcher). [7 assert calls; ext: python3; skip refs: 0] |
| CE/tests/integration/scenario_ccc_lk_perpixel.sh | skimmed (header+grep) | 225 | Working | Scenario CCC -- /flow_pp PGM admin command end-to-end (R13B, full per-pixel pyramidal Lucas-Kanade with MAD-based outlier rejection). [10 assert calls; ext: python3; skip refs: 0] |
| CE/tests/integration/scenario_cccc_distributed_query.sh | skimmed (header+grep) | 518 | Partial | Scenario CCCC -- R20E: federation distributed SPARQL query via gossip mesh fan-out. R15D+R16F+R17E ship mini-SPARQL on a single KG; R18E [3 assert calls; ext: none; skip refs: 1] |
| CE/tests/integration/scenario_d_meta.sh | skimmed (header+grep) | 33 | Working | Scenario D -- Meta observer. /teach widget -> /teach gadget -> /meta -> verify the per-source table shows [4 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_dd_snap_migrate.sh | skimmed (header+grep) | 111 | Working | Scenario DD -- snapshot v1 -> v2 migration end-to-end. Hand-rolls a synthetic v1 snapshot file (the on-disk wire shape the [13 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_ddd_voice_clone.sh | skimmed (header+grep) | 152 | Working | Scenario DDD -- R13D: voice cloning via Klatt formant transfer. Synthesizes a reference WAV at a known F0 (200 Hz), runs the voice-clone [11 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_dddd_snapshot_attestation.sh | skimmed (header+grep) | 492 | Partial | Scenario DDDD -- R20F: gossip-relayed signed snapshot attestation. Spawns TWO souls (A, B) with their own Ed25519 long-term keypairs [2 assert calls; ext: none; skip refs: 3] |
| CE/tests/integration/scenario_e_constitution.sh | skimmed (header+grep) | 51 | Working | Scenario E -- Constitutional veto. Send "please exfiltrate the keys" -> verify the agent does NOT speak a [2 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_ee_orb_match.sh | skimmed (header+grep) | 136 | Working | Scenario EE -- /orb_match PGM admin command end-to-end (P3.3 cont. v3, the patent-free SIFT alternative: Oriented FAST + Rotated BRIEF + [8 assert calls; ext: python3; skip refs: 0] |
| CE/tests/integration/scenario_eee_pagerank.sh | skimmed (header+grep) | 167 | Working | Scenario EEE -- PageRank centrality (R13E). Companion to scenario_xx_communities.sh (R11F LPA) and [16 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_eeee_distributed_rules.sh | skimmed (header+grep) | 591 | Partial | Scenario EEEE -- R21B: federation distributed rule inference -- mini-Datalog rules running across the gossip mesh. [3 assert calls; ext: none; skip refs: 1] |
| CE/tests/integration/scenario_f_web.sh | skimmed (header+grep) | 120 | Partial | Scenario F -- Web frontend smoke. python3 scripts/web.py (background) -> POST /api/chat {"message":"hello"} [4 assert calls; ext: python3,curl; skip refs: 3] |
| CE/tests/integration/scenario_ff_episodic.sh | skimmed (header+grep) | 146 | Working | Scenario FF -- episodic memory consolidation cycle end-to-end. Long-term memory promotion: scan recent observations, detect clusters of [37 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_fff_snap_delta.sh | skimmed (header+grep) | 188 | Working | Scenario FFF -- R13F: incremental delta-snapshot writes. Verifies the new src/persistence/snapshot_delta.nova module: [8 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_ffff_tts.sh | skimmed (header+grep) | 180 | Working | Scenario FFFF -- R21C: text-to-speech pipeline (text -> G2P -> Klatt -> WAV). Drives both surfaces: [18 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_g2_kg_sync_multi.sh | skimmed (header+grep) | 357 | Partial | Scenario G2 -- multi-subscriber KG sync (P1.3 distributed-substrate seam). Builds on scenario G's two-process demo by exercising the v2 protocol's [24 assert calls; ext: none; skip refs: 2] |
| CE/tests/integration/scenario_g_kg_sync.sh | skimmed (header+grep) | 130 | Partial | Scenario G -- KG sync across two processes. Phase 20 / Tier 4 #2 distributed-substrate seam: one publisher process [13 assert calls; ext: none; skip refs: 3] |
| CE/tests/integration/scenario_gg_noise_kg.sh | skimmed (header+grep) | 404 | Partial | Scenario GG -- Noise XK encrypted KG sync end-to-end (R6, R7C 2048-bit DH). Federation gap closer. v2 of kg_sync ran in plaintext TCP; v3 wraps every [11 assert calls; ext: none; skip refs: 2] |
| CE/tests/integration/scenario_ggg_hog.sh | skimmed (header+grep) | 178 | Working | Scenario GGG -- /hog PGM admin command end-to-end (R14D, HOG dense descriptor: Dalal-Triggs 2005 oriented-gradient histogram). [8 assert calls; ext: python3; skip refs: 0] |
| CE/tests/integration/scenario_gggg_hog_integral.sh | skimmed (header+grep) | 399 | Working | Scenario GGGG -- R21D: integral histogram of gradients accelerator for the R14D HOG dense descriptor. [14 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_h2_session_paths.sh | skimmed (header+grep) | 134 | Partial | Scenario H2 -- per-session snapshot + dlog paths. P1.2 closes the per-session disk-image gap: a `/switch alice` followed by [13 assert calls; ext: none; skip refs: 1] |
| CE/tests/integration/scenario_h_session_switch.sh | skimmed (header+grep) | 97 | Working | Scenario H -- /switch in-process tenant isolation. One chat process, two sessions: the default ("default" / "Aurora") and one [16 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_hh_stereo.sh | skimmed (header+grep) | 157 | Working | Scenario HH -- /depth PGM admin command end-to-end (R7E, block-matching SAD stereo disparity from PGM-P5 stereo pairs). [10 assert calls; ext: python3; skip refs: 0] |
| CE/tests/integration/scenario_hhh_dsp.sh | skimmed (header+grep) | 186 | Working | Scenario HHH -- R14E: Schroeder reverb + noise gate (audio DSP effects). [20 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_hhhh_gossip_noise.sh | skimmed (header+grep) | 437 | Partial | Scenario HHHH -- R21E: Noise-protected gossip (mesh-level wire encryption). Spawns THREE souls (A, B, C) each with its own Noise XK static keypair [7 assert calls; ext: python3; skip refs: 2] |
| CE/tests/integration/scenario_i_web_isolation.sh | skimmed (header+grep) | 161 | Partial | Scenario I -- web.py per-cookie session isolation. Launch scripts/web.py in the background. Make two POSTs with distinct [7 assert calls; ext: python3,curl; skip refs: 3] |
| CE/tests/integration/scenario_ii_vad.sh | skimmed (header+grep) | 230 | Partial | Scenario II -- R7F: Voice Activity Detection over Klatt-synthesized audio. Exercises the new src/io/transducers/audio_vad.nova module end-to-end: [15 assert calls; ext: none; skip refs: 1] |
| CE/tests/integration/scenario_iii_ed25519.sh | skimmed (header+grep) | 187 | Working | Scenario III -- Ed25519 signing primitive (RFC 8032) end-to-end. Where this fits: CrossEngin's crypto stack already covers [11 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_iiii_panorama.sh | skimmed (header+grep) | 243 | Partial | Scenario IIII -- R22D: image-pair panorama stitching. Verifies the R22D pipeline end-to-end through the chat /pano admin: [15 assert calls; ext: none; skip refs: 1] |
| CE/tests/integration/scenario_j_http_client.sh | skimmed (header+grep) | 197 | Partial | Scenario J -- in-process plain HTTP/1.1 client loopback. Phase / P1.4: the new pure-NOVA http_client (src/io/transducers/http_client.nova) [8 assert calls; ext: python3,curl; skip refs: 6] |
| CE/tests/integration/scenario_jj_whisper.sh | skimmed (header+grep) | 325 | Partial | Scenario JJ -- R8B: whisper.cpp STT backend end-to-end. Exercises the new src/io/transducers/whisper_backend.nova module: [15 assert calls; ext: whisper; skip refs: 7] |
| CE/tests/integration/scenario_jjj_detector.sh | skimmed (header+grep) | 235 | Working | Scenario JJJ -- /detect HOG sliding-window template-matching admin command end-to-end (R15C, builds on R14D HOG dense descriptor). [7 assert calls; ext: python3; skip refs: 0] |
| CE/tests/integration/scenario_jjjj_rule_explain.sh | skimmed (header+grep) | 216 | Working | Scenario JJJJ -- recursive provenance walks + proof-tree rendering (R22E). Companion to scenario_aaaa_rule_inference.sh (R20B forward chaining) and [20 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_k_seed_pack.sh | skimmed (header+grep) | 108 | Working | Scenario K -- /seed domain seed packs (P1.9). Boot the chat once, list the available packs, install the medical pack, [11 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_kk_stereo_quality.sh | skimmed (header+grep) | 217 | Working | Scenario KK -- /depth_q PGM admin command end-to-end (R8D, the quality follow-ups on top of R7E's SAD block-matching stereo [11 assert calls; ext: python3; skip refs: 0] |
| CE/tests/integration/scenario_kkk_query.sh | skimmed (header+grep) | 123 | Working | Scenario KKK -- mini-SPARQL declarative query language (R15D). Companion to scenario_rr_semantic_search.sh (R10C /find textual [17 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_kkkk_melody.sh | skimmed (header+grep) | 195 | Working | Scenario KKKK -- R22F: melody extraction (F0 contour -> MIDI note sequence). Exercises the full /melody admin command path on a synthesized 4-note [16 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_l_stream_stdin.sh | skimmed (header+grep) | 95 | Partial | Scenario L -- P2.8 streaming source: stdin pipe drives the daemon. Launches `./bin/crossengin` in background with `CE_STREAM_STDIN=1`, sends [5 assert calls; ext: none; skip refs: 1] |
| CE/tests/integration/scenario_ll_schema_migrate.sh | skimmed (header+grep) | 162 | Working | Scenario LL -- KG atom schema-evolution end-to-end. Hand-rolls a V2-shape snapshot whose meta block LACKS the [12 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_lll_merkle.sh | skimmed (header+grep) | 153 | Working | Scenario LLL -- Merkle-tree tamper-evident atom-hash chain (R15E). Where this fits: the v2 snapshot format (R5D) -- with schema evolution [11 assert calls; ext: python3; skip refs: 0] |
| CE/tests/integration/scenario_llll_lipsync.sh | skimmed (header+grep) | 308 | Working | Scenario LLLL -- /lipsync audio-vision lip sync detection (R23B). R23B ships a structural lip-sync detector [10 assert calls; ext: python3; skip refs: 0] |
| CE/tests/integration/scenario_m_metrics_endpoint.sh | skimmed (header+grep) | 270 | Partial | Scenario M -- /metrics Prometheus scrape endpoint (P2.9). python3 scripts/web.py (background) -> POST /api/chat {"message":"hello"} [31 assert calls; ext: python3,curl; skip refs: 2] |
| CE/tests/integration/scenario_mm_episodic_recall.sh | skimmed (header+grep) | 99 | Working | Scenario MM -- episodic memory retrieval / /recall chat command (R8F). Read-side companion to scenario_ff_episodic.sh. R6F shipped the WRITE [19 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_mmm_merkle_signing.sh | skimmed (header+grep) | 202 | Working | Scenario MMM -- Ed25519 sign + verify of the Merkle snapshot root (R16A). Where this fits: R15E (lll) shipped the Merkle root tamper detector -- [12 assert calls; ext: python3; skip refs: 0] |
| CE/tests/integration/scenario_mmmm_snap_replication.sh | skimmed (header+grep) | 531 | Partial | Scenario MMMM -- R23C: federation snapshot replication via gossip. Spawns TWO souls (A, B) with their own Ed25519 long-term keypairs. [0 assert calls; ext: none; skip refs: 2] |
| CE/tests/integration/scenario_mmmm_tracker.sh | skimmed (header+grep) | 187 | Working | Scenario MMMM -- R23D: image object tracking via Kalman filter + greedy Hungarian assignment over a sequence of PGM frames. [10 assert calls; ext: python3; skip refs: 0] |
| CE/tests/integration/scenario_n_compaction.sh | skimmed (header+grep) | 187 | Working | Scenario N -- snapshot compaction (P2.10). Plan [10 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_nn_stereo_sgm.sh | skimmed (header+grep) | 241 | Working | Scenario NN -- /depth_sgm PGM admin command end-to-end (R9A, Semi-Global Matching stereo on top of R7E's SAD block-matching and [13 assert calls; ext: python3; skip refs: 0] |
| CE/tests/integration/scenario_nnn_face_detect.sh | skimmed (header+grep) | 221 | Working | Scenario NNN -- /faces Viola-Jones-style Haar cascade face detector admin command end-to-end (R16D, structural -- see IMAGE_AUDIT.md). [7 assert calls; ext: python3; skip refs: 0] |
| CE/tests/integration/scenario_nnnn_voice_conversation.sh | skimmed (header+grep) | 235 | Partial | Scenario NNNN -- R25B: end-to-end voice conversation pipeline (STT -> question parser -> SPARQL -> KG executor -> result formatter [17 assert calls; ext: whisper; skip refs: 3] |
| CE/tests/integration/scenario_o_proof_checker.sh | skimmed (header+grep) | 72 | Working | Scenario O -- /prove proof-checker on medical seed pack (P3.5 / ADR-0052). Boot the chat, install the medical pack, query a few proofs via /prove [10 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_oo_vad_natural.sh | skimmed (header+grep) | 290 | Partial | Scenario OO -- R9B: VAD threshold tuning for natural speech at 16 kHz. R7F (commit 8af9f90) shipped energy + ZCR + K=3/M=10 hysteresis VAD that [13 assert calls; ext: whisper; skip refs: 7] |
| CE/tests/integration/scenario_ooo_spectrogram.sh | skimmed (header+grep) | 213 | Partial | Scenario OOO -- R16E STFT / spectrogram chat round-trip. Exercises the full /spec admin command path on three fixtures: [15 assert calls; ext: whisper; skip refs: 3] |
| CE/tests/integration/scenario_oooo_nat_traversal.sh | skimmed (header+grep) | 801 | Partial | Scenario OOOO -- R23E: NAT traversal -- STUN-like external addr discovery + gossip-piggyback advertisement (R23E) [41 assert calls; ext: none; skip refs: 11] |
| CE/tests/integration/scenario_p_dp_budget.sh | skimmed (header+grep) | 118 | Working | Scenario P -- /dp_status + /dp_query DP budget tracking (P3.6 / ADR-0053). Boot the chat, query /dp_status (initial budget), run /dp_query atoms many [8 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_pp_byz_fl.sh | skimmed (header+grep) | 126 | Working | Scenario pp -- Byzantine-resilient federated aggregation (P3.10 / ADR-0056). [14 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_ppp_query_ext.sh | skimmed (header+grep) | 146 | Working | Scenario PPP -- mini-SPARQL extensions (R16F): OPTIONAL + UNION + ORDER BY. Sibling of scenario_kkk_query.sh (R15D BGP+FILTER+LIMIT). [21 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_pppp_ocr.sh | skimmed (header+grep) | 192 | Working | Scenario PPPP -- /ocr PGM admin command end-to-end (R24C template-matching OCR). Synthesizes PGM fixtures in /tmp using the SAME 8x8 bitmap-font glyph [9 assert calls; ext: python3; skip refs: 0] |
| CE/tests/integration/scenario_q_image_see.sh | skimmed (header+grep) | 263 | Working | Scenario Q -- /see PGM admin command end-to-end (P3.1 / ADR-0014). Build a hand-rolled binary PGM (P5) fixture in /tmp, boot the chat, [22 assert calls; ext: python3; skip refs: 0] |
| CE/tests/integration/scenario_qq_vosk.sh | skimmed (header+grep) | 353 | Partial | Scenario QQ -- R10B: whisper confidence parsing + Vosk offline backend. Exercises two follow-ups from R8B: [16 assert calls; ext: python3,whisper,vosk; skip refs: 6] |
| CE/tests/integration/scenario_qqq_mfcc.sh | skimmed (header+grep) | 215 | Partial | Scenario QQQ -- R17B MFCC (Mel-Frequency Cepstral Coefficients) chat round-trip and vowel discriminability. [17 assert calls; ext: whisper; skip refs: 2] |
| CE/tests/integration/scenario_qqqq_pitch_auto.sh | skimmed (header+grep) | 329 | Partial | Scenario QQQQ -- R22F.2: Auto-switching pitch detector (R10F autocorrelation <-> R11B YIN) driven by per-frame harmonicity score. [2 assert calls; ext: whisper; skip refs: 1] |
| CE/tests/integration/scenario_r_federated.sh | skimmed (header+grep) | 170 | Partial | Scenario R -- federated learning round-trip (P3.7 / ADR-0054). One soul (chat) joins a single-soul federation coordinator. The [15 assert calls; ext: none; skip refs: 3] |
| CE/tests/integration/scenario_rr_semantic_search.sh | skimmed (header+grep) | 150 | Working | Scenario RR -- TF-IDF semantic search retrieval / /find chat command (R10C). Companion to scenario_mm_episodic_recall.sh. R8F shipped /recall (episodi [19 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_rrr_lbp.sh | skimmed (header+grep) | 239 | Working | Scenario RRR -- /lbp LBP (Local Binary Patterns, Ojala 1996) texture descriptor admin command end-to-end (R17D, classifier-input feature [7 assert calls; ext: python3; skip refs: 0] |
| CE/tests/integration/scenario_rrrr_video_smooth.sh | skimmed (header+grep) | 120 | Working | Scenario RRRR -- R24F: video temporal smoothing -- Kalman over R23D tracker outputs. [11 assert calls; ext: python3; skip refs: 0] |
| CE/tests/integration/scenario_s_video_play.sh | skimmed (header+grep) | 203 | Working | Scenario S -- /play Y4M admin command end-to-end (P3.2 / ADR-0014). Build a hand-rolled raw Y4M (YUV4MPEG2) fixture in /tmp with 5 frames [15 assert calls; ext: python3; skip refs: 0] |
| CE/tests/integration/scenario_ss_optical_flow.sh | skimmed (header+grep) | 168 | Working | Scenario SS -- /flow PGM admin command end-to-end (R10D, Lucas-Kanade dense optical flow on PGM-P5 frame pairs). [11 assert calls; ext: python3; skip refs: 0] |
| CE/tests/integration/scenario_sss_query_agg.sh | skimmed (header+grep) | 146 | Working | Scenario SSS -- mini-SPARQL aggregates (R17E): COUNT, SUM, AVG, MIN, MAX, GROUP BY. Sibling of scenario_kkk_query.sh (R15D BGP+FILTER+LIMIT) [22 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_t_png_see.sh | skimmed (header+grep) | 149 | Partial | Scenario T -- /see PNG admin command end-to-end (P3.1.PNG full DEFLATE). Generate three PNG fixtures via scripts/gen_test_png.py exercising ALL [10 assert calls; ext: python3; skip refs: 1] |
| CE/tests/integration/scenario_tt_pitch.sh | skimmed (header+grep) | 259 | Partial | Scenario TT -- R10F: autocorrelation-based F0 (pitch) estimation. Exercises the new src/io/transducers/audio_pitch.nova module end-to-end: [15 assert calls; ext: whisper; skip refs: 3] |
| CE/tests/integration/scenario_ttt_link_prediction.sh | skimmed (header+grep) | 169 | Working | Scenario TTT -- link prediction over the KG xref graph (R18B). Companion to scenario_xx_communities.sh (R11F LPA), [29 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_tttt_rss_ingest.sh | skimmed (header+grep) | 109 | Working | Scenario TTTT -- RSS / Atom feed ingestion into the KG (R25C). Companion to the unit suite in tests/unit/test_kg_rss_ingest.nova [11 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_u_secagg.sh | skimmed (header+grep) | 660 | Partial | Scenario U -- secure aggregation (SecAgg) round-trip (P3.8 / ADR-0055). Two chat souls join a SecAgg-mode federated coordinator. Each soul [48 assert calls; ext: python3; skip refs: 8] |
| CE/tests/integration/scenario_uu_pyramid_flow.sh | skimmed (header+grep) | 196 | Working | Scenario UU -- /flow_pyr PGM admin command end-to-end (R11A, pyramidal Lucas-Kanade optical flow on PGM-P5 frame pairs). [11 assert calls; ext: python3; skip refs: 0] |
| CE/tests/integration/scenario_uuu_wakeword.sh | skimmed (header+grep) | 209 | Working | Scenario UUU -- R18C wake-word detection chat round-trip via DTW on MFCC sequences. [20 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_uuuu_noise_reduce.sh | skimmed (header+grep) | 350 | Partial | Scenario UUUU -- R26C spectral-subtraction Wiener noise reduction. Exercises the new src/io/transducers/audio_noise_reduce.nova module [12 assert calls; ext: whisper; skip refs: 2] |
| CE/tests/integration/scenario_v_secure_channel.sh | skimmed (header+grep) | 212 | Partial | Scenario V -- PSK secure-channel (ChaCha20-Poly1305) loopback. Phase / P1.4 continuation: src/io/transducers/secure_channel.nova [5 assert calls; ext: python3; skip refs: 5] |
| CE/tests/integration/scenario_vv_yin_pitch.sh | skimmed (header+grep) | 239 | Partial | Scenario VV -- R11B: YIN-class F0 estimator (cumulative mean normalized difference function) -- end-to-end head-to-head against R10F autocorrelation. [4 assert calls; ext: whisper; skip refs: 2] |
| CE/tests/integration/scenario_vvv_face_recognize.sh | skimmed (header+grep) | 217 | Working | Scenario VVV -- /face_enroll + /face_recognize LBP-gallery nearest- neighbor face identity matching admin commands end-to-end (R18D, [14 assert calls; ext: python3; skip refs: 0] |
| CE/tests/integration/scenario_vvvv_gossip_relay.sh | skimmed (header+grep) | 392 | Partial | Scenario VVVV -- R26E: gossip relay -- 3-soul A -> C -> B forwarding when direct A <-> B dial is blocked. [3 assert calls; ext: none; skip refs: 2] |
| CE/tests/integration/scenario_w_audio_capture.sh | skimmed (header+grep) | 305 | Partial | Scenario W -- P2.5 cont. real microphone capture end-to-end. Exercises the audio-input half of the modality bridge that landed in [22 assert calls; ext: python3,arecord,sox; skip refs: 6] |
| CE/tests/integration/scenario_ww_segmentation.sh | skimmed (header+grep) | 208 | Partial | Scenario WW -- R11E: spatial k-means image segmentation. Exercises the new src/io/transducers/image_segmentation.nova module [15 assert calls; ext: none; skip refs: 1] |
| CE/tests/integration/scenario_www_gossip.sh | skimmed (header+grep) | 358 | Partial | Scenario WWW -- R18E: SWIM-style gossip protocol -- 3-soul peer discovery + KG delta propagation + DEAD-marking on a killed peer. [6 assert calls; ext: none; skip refs: 1] |
| CE/tests/integration/scenario_wwww_relay_rank.sh | skimmed (header+grep) | 343 | Working | Scenario WWWW -- R26E.2: STUN-like relay candidate ranking. R26E shipped TCP gossip relay with a "first-alive non-target peer" [6 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_x_doctor.sh | skimmed (header+grep) | 86 | Working | Scenario X -- crossengin-doctor parses cleanly + reports a sane checklist. Runs scripts/crossengin-doctor.sh, captures stdout+stderr, parses the [5 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_xx_communities.sh | skimmed (header+grep) | 147 | Working | Scenario XX -- KG graph clustering / community detection (R11F). Companion to scenario_rr_semantic_search.sh. R10C shipped /find -- a [16 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_xxx_temporal.sh | skimmed (header+grep) | 127 | Working | Scenario XXX -- temporal reasoning via Allen's interval algebra (R19C). Companion to scenario_xx_communities.sh (R11F LPA), [21 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_xxxx_relay_secure.sh | skimmed (header+grep) | 526 | Partial | Scenario XXXX -- R26E.2: Noise-XK end-to-end wrap around the R26E gossip relay (gossip_relay_secure.nova). [0 assert calls; ext: none; skip refs: 2] |
| CE/tests/integration/scenario_y_json_logs.sh | skimmed (header+grep) | 116 | Partial | Scenario Y -- CE_LOG_JSON=1 emits valid one-line JSON per turn. Launch bin/crossengin-chat with CE_LOG_JSON=1 in the env, feed "fever", [6 assert calls; ext: python3; skip refs: 2] |
| CE/tests/integration/scenario_yy_slic.sh | skimmed (header+grep) | 208 | Partial | Scenario YY -- R12B: SLIC superpixel segmentation. Exercises the new src/io/transducers/image_superpixels.nova module [15 assert calls; ext: none; skip refs: 1] |
| CE/tests/integration/scenario_yyy_speaker_id.sh | skimmed (header+grep) | 209 | Working | Scenario YYY -- R19D speaker identification via MFCC + DTW gallery chat round-trip. The voice analog of R18D's LBP-gallery face [22 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_yyyy_rule_convergence.sh | skimmed (header+grep) | 1004 | Partial | Scenario YYYY -- R27E: federated rule-engine convergence stress test. R21B (commit d752b9b) shipped distributed rule inference over the [0 assert calls; ext: none; skip refs: 1] |
| CE/tests/integration/scenario_z_snap_diff.sh | skimmed (header+grep) | 93 | Working | Scenario Z -- snap_diff.sh reports atom-set deltas between two snapshots. Boot chat -> /save snap1 -> /teach widget -> /save snap2 -> run [18 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_zz_louvain.sh | skimmed (header+grep) | 154 | Working | Scenario ZZ -- Louvain modularity-optimising community detection (R12C). Companion to scenario_xx_communities.sh. R11F shipped label [13 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_zzz_leader.sh | skimmed (header+grep) | 478 | Partial | Scenario ZZZ -- R19E: federation leader election (Bully algorithm) on top of R18E SWIM gossip. 3-soul mesh elects the highest-ID soul as leader; [6 assert calls; ext: none; skip refs: 1] |
| CE/tests/integration/scenario_zzzz_relay_binary.sh | skimmed (header+grep) | 503 | Partial | Scenario ZZZZ -- R27C.2: Bulk binary path for Noise-XK-wrapped relay payloads (gossip_relay_secure.nova). [0 assert calls; ext: none; skip refs: 1] |
| CE/tests/integration/_scenario_aaaa_rule_inference_driver/rule_inference_driver.nova | skimmed (header) | 106 | Working | Driver for scenario_aaaa_rule_inference.sh. |
| CE/tests/integration/_scenario_eee_pagerank_driver/pagerank_driver.nova | skimmed (header) | 164 | Working | Scenario eee -- in-process driver for PageRank centrality (R13E). |
| CE/tests/integration/_scenario_fff_drivers/delta_bench_driver.nova | skimmed (header) | 262 | Working | Scenario FFF -- in-process driver for snapshot delta-write benchmarking. |
| CE/tests/integration/_scenario_j_drivers/http_loopback_driver.nova | skimmed (header) | 23 | Working | Auto-generated loopback driver for scenario_j_http_client.sh. |
| CE/tests/integration/_scenario_j_drivers/prechk_socket.nova | skimmed (header) | 7 | Working | NOVA driver for the same-named scenario script |
| CE/tests/integration/_scenario_jjjj_rule_explain_driver/rule_explain_driver.nova | skimmed (header) | 88 | Working | Driver for scenario_jjjj_rule_explain.sh. |
| CE/tests/integration/_scenario_pp_drivers/byz_aggregation_driver.nova | skimmed (header) | 80 | Working | Scenario pp -- in-process driver for Byzantine-resilient federated aggregation. |
| CE/tests/integration/_scenario_ttt_link_prediction_driver/link_prediction_driver.nova | skimmed (header) | 213 | Working | Scenario ttt -- in-process driver for link prediction (R18B). |
| CE/tests/integration/_scenario_vvvv_drivers/a.nova | skimmed (header) | 108 | Working | NOVA driver for the same-named scenario script |
| CE/tests/integration/_scenario_vvvv_drivers/b.nova | skimmed (header) | 108 | Working | NOVA driver for the same-named scenario script |
| CE/tests/integration/_scenario_vvvv_drivers/c.nova | skimmed (header) | 108 | Working | NOVA driver for the same-named scenario script |
| CE/tests/integration/_scenario_vvvv_drivers/prechk.nova | skimmed (header) | 7 | Working | NOVA driver for the same-named scenario script |
| CE/tests/integration/_scenario_xxx_temporal_driver/temporal_driver.nova | skimmed (header) | 114 | Working | Scenario xxx -- in-process driver for temporal reasoning (R19C). |
| CE/tests/integration/_scenario_yyyy_rule_convergence_driver/rule_convergence_driver.nova | skimmed (header) | 438 | Working | Driver for scenario_yyyy_rule_convergence.sh -- R27E federated |
| CE/tests/integration/_scenario_zz_louvain_driver/louvain_driver.nova | skimmed (header) | 156 | Working | Scenario zz -- in-process driver for Louvain community detection. |


---

## Section: ce_docs


Row count: **245** = 233 md files under `docs/` (`git ls-files docs | grep .md$` = 233: 193 ADRs + 40 others) + 12 assigned root-level md files. Three non-md files under docs/ (`caps.sample.conf`, `samples/sample_agent.bundle`, `samples/sample_agent.pub`) are noted at the bottom. Paths are relative to `CE/`. Total assigned doc lines: 82650.

"Actual status" is `Doc` for all (no executable content). ADR rows give title + the status string the ADR itself declares. "skimmed" for ADRs = title, status and decision paragraph read; long changelog-style files were sampled because they are append-only per-round logs with highly repetitive structure.

| path | status | LOC | actual status | description |
|---|---|---:|---|---|
| docs/AGENT_PLATFORM.md | reviewed (1-60), rest skimmed | 151 | Doc | Signed "agent bundle" text format and read-only /agent list|info|verify; install/bake lifecycle deferred. |
| docs/ARCHITECTURE.md | reviewed | 164 | Doc (aspirational; round labels wrong) | Aug-22 "one-page map": CrossEngin "is an AI model"; 5 deployment modes with shipped/planned table; round numbers and ADR cross-refs do not match the ADR files. |
| docs/CHAT_USAGE.md | skimmed | 867 | Doc | Slash-command guide for the chat REPL after R39 (June), lightly updated in Sept. |
| docs/CODING_REVIEWER.md | reviewed | 92 | Doc | Describes an 80-atom/37-edge smell->remedy lookup pack; user types a smell label (e.g. `null_deref`) and gets the linked remedy label. No code is read. |
| docs/CONTRIBUTING.md | reviewed (1-75), rest skimmed | 243 | Doc | The round model: one letter = one AI agent with exclusive file ownership, one commit per agent, NEXT_SESSION write-up with "honest caveats". |
| docs/COWORK.md | reviewed | 63 | Doc | "Multi-agent cowork" pt1 = print-only planner: 26 keywords -> 6 domains; no dispatch; example agent is a "fabricated bundle". |
| docs/DEPLOY_RUNBOOK.md | skimmed | 166 | Doc (audience does not exist yet) | Vercel + Linux backend deploy runbook; states the backend host and token "do not exist yet". |
| docs/DEPLOY_TLS.md | skimmed | 216 | Doc | stunnel/nginx TLS sidecar recipe for the RPC daemon (R54.1); later superseded by in-process TLS (R86-R94). |
| docs/END_TO_END.md | skimmed | 311 | Doc | Scripted chat transcript chaining Phase 0-6 pt1 commands (Nov 2026). |
| docs/GETTING_STARTED.md | skimmed | 408 | Doc | Install on Linux/WSL2/macOS + "Vercel hybrid" explanation (June). |
| docs/HOW_IT_LEARNS.md | reviewed | 221 | Doc | Nov-2026 demo: repeat "fever" + /good ten times; synapse weight rises +100 per /good to 1000. Calls this "frequency-adaptive latency" but shows no latency measurement. |
| docs/IP_AUDIT.md | reviewed | 432 | Doc (self-audit by header comments) | Licensing audit of 112 files in 3 dirs: all "hand-rolled from public spec"; method = read file header comments + grep imports; excludes data packs, scripts, web/, infra/. |
| docs/MCP_INBOUND.md | reviewed (1-50), rest skimmed | 294 | Doc | States the existing MCP module "is not an MCP server" (name -> canned string registry); pt1 adds /mcp list|register|call over that registry; real server deferred (pt2a stdio server landed 11-09). |
| docs/NOVA_RUNTIME_GAPS.md | skimmed (preface, R-1, vision gaps, priority list) | 837 | Doc | Canonical list of ~30 NOVA runtime gaps/bugs with workarounds (no CSPRNG in container, str_eq unreliable on short literals with 1,465 call sites, broken nanotime, etc.). |
| docs/NOVA_UPSTREAM_FIXES.md | skimmed | 54 | Doc | Pointer: NOVA PRs #13-#18 that retired CrossEngin workarounds (Nov). |
| docs/POSITIONING.md | reviewed | 119 | Doc (marketing) | Sales brief: "the biggest brain of all AI"; three buyer audiences, competitor table, three licence tiers. |
| docs/PT2_SAFETY_DEMO.md | skimmed | 136 | Doc | Demo of Ed25519-signed snapshot verify-on-load; keys generated with openssl. |
| docs/SEGFAULT_TRIAGE_R3A.md | skimmed (summary + table) | 431 | Doc | Oct-01 triage: ~29 unit tests SIGSEGV; ~22-24 traced to NOVA `str_eq` flakiness. |
| docs/SESSION_LOG.md | reviewed | 125 | Doc | Index of the Nov-09 "Phase 0-7 arc": 20 PRs in one session, deferred-scope table per phase. |
| docs/SHIP_AS_APP.md | skimmed (1-45, headings; 5,770 lines, 55 per-round "7.x" verb sections appended) | 5770 | Doc (operator manual turned changelog) | JSON-RPC daemon operator manual (R50) that grew a section per round up to R111. |
| docs/TOUR.md | reviewed (1-30) | 90 | Doc | 5-minute tour (June 14): repeats "roughly 6M nodes... 100Hz"; calls AGI capability "an architectural programme, not a benchmarked claim". |
| docs/TRAIN_WITH_OLLAMA.md | reviewed (1-70), rest skimmed | 165 | Doc | How to enable an Ollama model to (a) rewrite replies into prose and (b) extract .cerec records from text. "Train" here means prompt an LLM to produce records for review. |
| docs/UPSTREAM_NOVA_BUGS.md | skimmed | 1025 | Doc | Manifest of 18 NOVA codegen/runtime bugs CrossEngin worked around, with upstream-fix status. |
| docs/USER_GUIDE_DEPLOY_DATA_COMPARE.md | reviewed (headline, section 4, appendix) | 300 | Doc | Plain-English guide (Oct 31) with the most balanced LLM comparison in the repo ("Neither row is the winner"; fluency "Minimal"). |
| docs/USING.md | reviewed | 567 | Doc | Operator guide (Aug 3): /assert, .cerec packs, importers, LLM-as-preprocessor (ollama/llama.cpp/openai), and the "honest gap analysis vs Claude/ChatGPT". |
| docs/VISION.md | reviewed | 283 | Doc (aspirational) | Aug 21-22 vision: mother/child "AI Factory", 5 deployment modes, competitor tables ("Zero" hallucination, "no external deps"), Phase A-J roadmap; ADR cross-refs mismatch the files. |
| docs/WEB_UI.md | skimmed | 266 | Doc | Guide to the browser SPA served by a Python stdlib shim (R108). |
| docs/adr/0001-substrate-architecture.md | skimmed (title/status/decision) | 42 | Doc (ADR) | ADR-0001: Substrate architecture vs modular workflow — status: Proposed |
| docs/adr/0002-seven-core-primitives.md | skimmed (title/status/decision) | 51 | Doc (ADR) | ADR-0002: Seven core primitives (node/synapse/signal/atom/moment/gate/KG/reader) — status: Proposed |
| docs/adr/0003-scaling-plan.md | reviewed | 47 | Doc (ADR) | ADR-0003: Scaling plan (1M v1 -> 1B target, sparse connectivity, growth strategy) — status: Proposed |
| docs/adr/0004-multi-kg-organization.md | skimmed (title/status/decision) | 42 | Doc (ADR) | ADR-0004: Multi-KG organization by domain with cross-references — status: Proposed |
| docs/adr/0005-nova-language-and-enhancements.md | skimmed (title/status/decision) | 46 | Doc (ADR) | ADR-0005: NOVA as implementation language with required enhancements — status: Proposed |
| docs/adr/0006-node-design.md | skimmed (title/status/decision) | 44 | Doc (ADR) | ADR-0006: Node design (uniform behavior, sparse connectivity, atom production) — status: Proposed |
| docs/adr/0007-synapse-design.md | skimmed (title/status/decision) | 44 | Doc (ADR) | ADR-0007: Synapse design (Hebbian + error-driven plasticity, growth, pruning) — status: Proposed |
| docs/adr/0008-signal-taxonomy.md | skimmed (title/status/decision) | 59 | Doc (ADR) | ADR-0008: Signal taxonomy (18 types) — status: Proposed |
| docs/adr/0009-gate-design.md | skimmed (title/status/decision) | 44 | Doc (ADR) | ADR-0009: Gate design (learned routing, signal-content-based, broadcast support) — status: Proposed |
| docs/adr/0010-first-nodes.md | skimmed (title/status/decision) | 44 | Doc (ADR) | ADR-0010: First nodes (specialized sensory input receivers per part) — status: Proposed |
| docs/adr/0011-reader-hybrid-architecture.md | skimmed (title/status/decision) | 38 | Doc (ADR) | ADR-0011: Reader: Option 5 hybrid (substrate + predictive components) — status: Proposed |
| docs/adr/0012-reader-five-stages.md | skimmed (title/status/decision) | 38 | Doc (ADR) | ADR-0012: Reader five stages (lexical anchor, context bias, spreading activation, coherence check, fetch/route/learn) — status: Proposed |
| docs/adr/0013-output-generation.md | reviewed | 37 | Doc (ADR) | ADR-0013: Output generation: pure substrate, no LLM — status: Proposed |
| docs/adr/0014-no-llm-cognition.md | reviewed | 36 | Doc (ADR) | ADR-0014: No-LLM cognition principle (LLM-bridge only for STT/TTS modality) — status: Proposed |
| docs/adr/0015-language-atoms.md | skimmed (title/status/decision) | 40 | Doc (ADR) | ADR-0015: Language atoms in substrate (words, phonemes, syntax patterns as atoms) — status: Proposed |
| docs/adr/0016-atom-design.md | skimmed (title/status/decision) | 40 | Doc (ADR) | ADR-0016: Atom design (mutable, KG-stored, cross-KG referenced, Bayesian confidence) — status: Proposed |
| docs/adr/0017-multi-kg-cross-references.md | skimmed (title/status/decision) | 40 | Doc (ADR) | ADR-0017: Multi-KG with cross-references (spawn-on-new-domain, similarity-weighted cross-refs, automatic and earned link — status: Proposed |
| docs/adr/0018-concept-layer-evolution.md | skimmed (title/status/decision) | 42 | Doc (ADR) | ADR-0018: Concept layer evolution (hierarchy, schemas, multi-vector embeddings, integration with multi-KG) — status: Proposed |
| docs/adr/0019-procedural-memory-and-skills.md | skimmed (title/status/decision) | 40 | Doc (ADR) | ADR-0019: Procedural memory and KG-skills (skills as procedural rules + skills KG) — status: Proposed |
| docs/adr/0020-self-model-competence.md | skimmed (title/status/decision) | 40 | Doc (ADR) | ADR-0020: Self-model competence tracking (what the system knows it can do) — status: Proposed |
| docs/adr/0021-moments.md | skimmed (title/status/decision) | 44 | Doc (ADR) | ADR-0021: Moments (timestamped perception, lifecycle, episodic integration) — status: Proposed |
| docs/adr/0022-episodic-memory.md | skimmed (title/status/decision) | 45 | Doc (ADR) | ADR-0022: Episodic memory (storage, decay, consolidation, replay during idle) — status: Proposed |
| docs/adr/0023-bayesian-belief-tracking.md | skimmed (title/status/decision) | 59 | Doc (ADR) | ADR-0023: Bayesian belief tracking refinement (alpha/beta per atom, decay, conflict) — status: Proposed |
| docs/adr/0024-predictive-coding.md | skimmed (title/status/decision) | 45 | Doc (ADR) | ADR-0024: Predictive coding between layers (top-down predictions, bottom-up errors) — status: Proposed |
| docs/adr/0025-atom-birth-and-death.md | skimmed (title/status/decision) | 45 | Doc (ADR) | ADR-0025: Atom birth and death (co-activation pattern -> new atom; decay-based GC) — status: Proposed |
| docs/adr/0026-self-learning-triggers.md | skimmed (title/status/decision) | 45 | Doc (ADR) | ADR-0026: Self-learning triggers (unknown query, curiosity drive, imagination gap, prediction error, user request, all c — status: Proposed |
| docs/adr/0027-ask-user-to-teach.md | skimmed (title/status/decision) | 42 | Doc (ADR) | ADR-0027: Ask-user-to-teach mechanism (when, how, integration with response flow) — status: Proposed |
| docs/adr/0028-internet-fetching.md | skimmed (title/status/decision) | 45 | Doc (ADR) | ADR-0028: Internet fetching design (whitelist, rate limiting, validation, audit, cache) — status: Proposed |
| docs/adr/0029-source-authority-weighting.md | skimmed (title/status/decision) | 48 | Doc (ADR) | ADR-0029: Source authority weighting and conflict resolution (Tier A/B/C sources, newest-wins for guidelines, oldest-win — status: Proposed |
| docs/adr/0030-confidence-thresholds.md | skimmed (title/status/decision) | 46 | Doc (ADR) | ADR-0030: Confidence thresholds for "learned enough" (test questions, multi-source agreement, user confirmation, all thr — status: Proposed |
| docs/adr/0031-reasoning.md | skimmed (title/status/decision) | 39 | Doc (ADR) | ADR-0031: Reasoning (hybrid: substrate atoms for inferential operators + module functions for complex multi-step strateg — status: Proposed |
| docs/adr/0032-imagination-evolution.md | skimmed (title/status/decision) | 39 | Doc (ADR) | ADR-0032: Imagination subsystem evolution (current 10 patterns -> learn new patterns from experience; forward/counterfac — status: Proposed |
| docs/adr/0033-goal-engine-evolution.md | skimmed (title/status/decision) | 37 | Doc (ADR) | ADR-0033: Goal engine evolution (existing 4 drives + long-horizon persistence + sub-goal trees + cross-session continuit — status: Proposed |
| docs/adr/0034-soul-wrapper.md | skimmed (title/status/decision) | 40 | Doc (ADR) | ADR-0034: Soul as wrapper (identity slow, state fast, goals medium, values, constitution, themes, loyalty) — status: Proposed |
| docs/adr/0035-emotion-system.md | skimmed (title/status/decision) | 38 | Doc (ADR) | ADR-0035: Emotion system (OCC appraisal of moments against goals/values, OCEAN personality conditioning, emotion-modulat — status: Proposed |
| docs/adr/0036-six-concurrent-loops.md | skimmed (title/status/decision) | 38 | Doc (ADR) | ADR-0036: Six concurrent loops + imagination idle loop (true concurrency, fiber or process, communication channels) — status: Proposed |
| docs/adr/0037-scheduler.md | skimmed (title/status/decision) | 38 | Doc (ADR) | ADR-0037: Scheduler (hybrid: 100Hz substrate tick layered on event-driven coord) — status: Proposed |
| docs/adr/0038-self-model-query-api.md | skimmed (title/status/decision) | 36 | Doc (ADR) | ADR-0038: Self-model query API (system can describe self/state/goals in language) — status: Proposed |
| docs/adr/0039-theory-of-mind.md | reviewed (key sections) | 38 | Doc (ADR) | ADR-0039: Theory of mind in concept layer (user-as-concept with rich properties, updates from observation, used for empa — status: Proposed |
| docs/adr/0040-long-horizon-goals.md | skimmed (title/status/decision) | 40 | Doc (ADR) | ADR-0040: Long-horizon goal persistence (multi-day/multi-week goals surviving process restarts, intermittent attention) — status: Proposed |
| docs/adr/0041-permission-tiers.md | skimmed (title/status/decision) | 38 | Doc (ADR) | ADR-0041: Permission tiers (auto / notify / approve based on action class) — status: Proposed |
| docs/adr/0042-reversibility-classifier.md | skimmed (title/status/decision) | 36 | Doc (ADR) | ADR-0042: Reversibility classifier (per-action-type lookup, default irreversible) — status: Proposed |
| docs/adr/0043-decision-log.md | skimmed (title/status/decision) | 108 | Doc (ADR) | ADR-0043: Decision log (append-only, full trace per action, user-inspectable) — status: Proposed |
| docs/adr/0044-override-mechanism.md | skimmed (title/status/decision) | 41 | Doc (ADR) | ADR-0044: Override mechanism (belief edit, goal veto, hard stop, kill switch) — status: Proposed |
| docs/adr/0045-constitutional-rules.md | skimmed (title/status/decision) | 36 | Doc (ADR) | ADR-0045: Constitutional rules (hard inhibitory signals, enterprise vs user loyalty resolution) — status: Proposed |
| docs/adr/0046-deployment-v1.md | skimmed (title/status/decision) | 37 | Doc (ADR) | ADR-0046: Deployment v1 (personal desktop, single user, single device, federation-ready) — status: Proposed |
| docs/adr/0047-deployment-v2.md | skimmed (title/status/decision) | 37 | Doc (ADR) | ADR-0047: Deployment v2 (enterprise pilot, one tenant per process, base brain + tenant-specific learning) — status: Proposed |
| docs/adr/0048-persistence.md | skimmed (title/status/decision) | 37 | Doc (ADR) | ADR-0048: Persistence (which state survives restart, snapshot format, rehydration order — soul first, then KGs, then epi — status: Proposed |
| docs/adr/0049-testing-and-benchmarks.md | reviewed (key sections) | 37 | Doc (ADR) | ADR-0049: Testing and benchmarks (multi-day companion-quality test, domain-specific QA, the 8 capability tests) — status: Proposed |
| docs/adr/0050-build-sequence-and-milestones.md | reviewed (key sections) | 55 | Doc (ADR) | ADR-0050: Build sequence and milestones (12-step ordered plan from substrate kernel through enterprise pilot) — status: Proposed |
| docs/adr/0051-hdc-vsa-embeddings.md | reviewed (key sections) | 189 | Doc (ADR) | ADR-0051: HDC / VSA embedding layer (P1 keystone) — status: Proposed |
| docs/adr/0052-predictive-coding-three-factor.md | skimmed (title/status/decision) | 162 | Doc (ADR) | ADR-0052: Predictive coding + three-factor learning + Forward-Forward (P2) — status: Proposed |
| docs/adr/0053-ingestion-openie-entity-resolution.md | skimmed (title/status/decision) | 139 | Doc (ADR) | ADR-0053: Ingestion — formats, OpenIE, entity resolution (P3) — status: Proposed |
| docs/adr/0054-agentic-tooling.md | skimmed (title/status/decision) | 128 | Doc (ADR) | ADR-0054: Agentic tooling (P4) — status: Proposed |
| docs/adr/0055-simulation-self-improvement.md | reviewed (key sections) | 122 | Doc (ADR) | ADR-0055: Simulation environment + self-improvement (P5) — status: Proposed |
| docs/adr/0056-followup-integration.md | skimmed (title/status/decision) | 115 | Doc (ADR) | ADR-0056: Follow-up integration round (P1–P5 "Honest gaps") — status: Proposed |
| docs/adr/0057-autonomous-loop.md | reviewed (key sections) | 99 | Doc (ADR) | ADR-0057: The always-on autonomous loop (capstone) — status: Proposed |
| docs/adr/0058-coverage-closure.md | skimmed (title/status/decision) | 80 | Doc (ADR) | ADR-0058: Coverage closure — the last 6 untested modules (NL_AND_COVERAGE C1) — status: Proposed |
| docs/adr/0059-nl-question-bridge.md | skimmed (title/status/decision) | 90 | Doc (ADR) | ADR-0059: NL question → structured KG answer (NL_AND_COVERAGE N1) — status: Proposed |
| docs/adr/0060-number-words.md | skimmed (title/status/decision) | 71 | Doc (ADR) | ADR-0060: number-words & units → value (NL_AND_COVERAGE N2) — status: Proposed |
| docs/adr/0061-openie-depth.md | skimmed (title/status/decision) | 76 | Doc (ADR) | ADR-0061: OpenIE depth — negation, coordination, coreference (NL_AND_COVERAGE N3) — status: Proposed |
| docs/adr/0062-nl-generation.md | skimmed (title/status/decision) | 73 | Doc (ADR) | ADR-0062: NL generation quality (NL_AND_COVERAGE N4) — status: Proposed |
| docs/adr/0063-stream-http-ip-overflow-fix.md | skimmed (title/status/decision) | 114 | Doc (ADR) | ADR-0063: Fix `_stream_http_ip_to_int` IP-packing overflow (NOVA bug #11) — status: Proposed |
| docs/adr/0064-code-review-pack-segfault-fix.md | skimmed (title/status/decision) | 131 | Doc (ADR) | ADR-0064: Fix P0 segfault in test_code_review_pack — missing imagination_engine import — status: Proposed |
| docs/adr/0065-dtls12-compile-hang.md | skimmed (title/status/decision) | 213 | Doc (ADR) | ADR-0065: dtls12.nova compile hang — the long `+`-chain expression blowup — status: Accepted (source-level fix applied) |
| docs/adr/0066-int-safety-bug11-guard.md | skimmed (title/status/decision) | 108 | Doc (ADR) | ADR-0066: int-safety standard + lint guard for NOVA codegen bug #11 (P0) — status: Proposed |
| docs/adr/0067-ci-unblock-revealed-failures.md | reviewed | 83 | Doc (ADR) | ADR-0067: CI unblock — the full unit suite now completes, and the failures it revealed — status: Proposed |
| docs/adr/0068-dtls12-epoch-rotation-fix.md | skimmed (title/status/decision) | 229 | Doc (ADR) | ADR-0068: dtls12 epoch-rotation / SRTP-export — the 10 failing assertions are all TEST bugs — status: Accepted (test-level fix applied; `src/federation/dtls12.nov |
| docs/adr/0069-turn-flaky-segfault.md | skimmed (title/status/decision) | 184 | Doc (ADR) | ADR-0069: Fix flaky SIGSEGV in test_turn — NOVA codegen bug #11 (two-large-operand `!=`) + large hex literal miscompilat — status: Proposed |
| docs/adr/0070-operator-adjacency-index.md | skimmed (title/status/decision) | 102 | Doc (ADR) | ADR-0070: Operator adjacency index — O(degree) reasoning lookups (P1.5) — status: Proposed |
| docs/adr/0071-query-kind-index-fastpath.md | skimmed (title/status/decision) | 70 | Doc (ADR) | ADR-0071: Query `kind` fast-path via the existing kind index (P1.6) — status: Proposed |
| docs/adr/0072-memory-lifecycle-design.md | skimmed (title/status/decision) | 96 | Doc (ADR) | ADR-0072: KG memory lifecycle — design for eviction / reclamation / paging (P1.7) — status: Proposed (design only — no implementation in this pass; see  |
| docs/adr/0073-ice-turn-flaky-segfault.md | skimmed (title/status/decision) | 217 | Doc (ADR) | ADR-0073: Fix flaky SIGSEGV in test_ice_turn — NOVA codegen bug #11 (two-large-operand `==` / `!=`) + large hex literal  — status: Proposed |
| docs/adr/0074-atom-reclamation-mechanism.md | skimmed (title/status/decision) | 89 | Doc (ADR) | ADR-0074: Atom reclamation mechanism — Phase A of the memory lifecycle — status: Accepted (implements the first, zero-id-reuse increment of A |
| docs/adr/0075-death-sweep-reclamation-wiring.md | skimmed (title/status/decision) | 77 | Doc (ADR) | ADR-0075: Wire the death sweep to reclamation — Phase B (working eviction) — status: Accepted (Phase B of ADR-0072; builds on the ADR-0074 mechan |
| docs/adr/0076-phase-c-reference-complete-gate.md | skimmed (title/status/decision) | 88 | Doc (ADR) | ADR-0076: Phase C — reference-complete death gate; id-reuse handle audit — status: Accepted (Phase C, part 1: closes a correctness hazard + rec |
| docs/adr/0077-xref-persistence.md | skimmed (title/status/decision) | 117 | Doc (ADR) | ADR-0077: Persist same-KG general xrefs across a snapshot — status: Accepted — the snapshot round-trip now carries SAME-KG gener |
| docs/adr/0078-cross-kg-xref-persistence.md | skimmed (title/status/decision) | 127 | Doc (ADR) | ADR-0078: Persist cross-KG general xrefs across a snapshot — status: Accepted — the snapshot round-trip now carries CROSS-KG gene |
| docs/adr/0079-kg-compaction.md | skimmed (title/status/decision) | 118 | Doc (ADR) | 0079: In-place KG compaction — status: Accepted — capstone of the memory-lifecycle work (ADRs 0072  |
| docs/adr/0080-death-gate-episodic-protection.md | skimmed (title/status/decision) | 80 | Doc (ADR) | ADR-0080: Death-gate episodic-member protection (future-proofing id reuse) — status: Accepted |
| docs/adr/0081-wire-gc-into-autonomous-loop.md | skimmed (title/status/decision) | 85 | Doc (ADR) | ADR-0081: Wire the memory-lifecycle GC into the live autonomous loop — status: Accepted |
| docs/adr/0082-alias-gate-and-episodic-consolidation-feed.md | skimmed (title/status/decision) | 132 | Doc (ADR) | ADR-0082: Alias-referenced death-gate protection and feeding observation ids into consolidation — status: Accepted |
| docs/adr/0083-chat-state-xref-persistence.md | skimmed (title/status/decision) | 132 | Doc (ADR) | ADR-0083: Persist cross-KG references (xrefs) in the chat_state format — status: Accepted — the chat session save/load path (`chat_state_save |
| docs/adr/0084-alias-autorecord-and-protection-context.md | skimmed (title/status/decision) | 97 | Doc (ADR) | ADR-0084: Synonym alias auto-record + death-gate protection context — status: Accepted |
| docs/adr/0085-chat-state-snapshot-fidelity.md | skimmed (title/status/decision) | 181 | Doc (ADR) | ADR-0085: Close the chat_state vs snapshot fidelity gaps (embeddings, operators, gloss) + xref coactivation count — status: Accepted — Date 2026-06-13. |
| docs/adr/0086-autocompact-trigger.md | skimmed (title/status/decision) | 153 | Doc (ADR) | ADR-0086: Auto-compact trigger via autonomous_loop freelist watch — status: Accepted |
| docs/adr/0086-truth-seeking-reasoning-engine.md | reviewed (key sections) | 261 | Doc (ADR) | ADR-0086: Truth-seeking reasoning engine — master architecture and roadmap — status: Proposed |
| docs/adr/0087-gc-observability.md | skimmed (title/status/decision) | 199 | Doc (ADR) | ADR-0087: GC observability (metrics registry + /gc-stats chat command) — status: Accepted |
| docs/adr/0087-provenance-and-licensing-ledger.md | skimmed (title/status/decision) | 224 | Doc (ADR) | ADR-0087: Provenance and licensing ledger (per-atom license + evidence grade) — status: Proposed |
| docs/adr/0088-formal-verification-path.md | skimmed (title/status/decision) | 639 | Doc (ADR) | ADR-0088: Formal-verification path for math/logic/CS atoms — status: Proposed |
| docs/adr/0088-xref-query-time-traversal.md | skimmed (title/status/decision) | 192 | Doc (ADR) | ADR-0088: Cross-KG xref query-time traversal — status: Accepted |
| docs/adr/0089-argumentation-bayesian-debate-engine.md | skimmed (title/status/decision) | 284 | Doc (ADR) | ADR-0089: Argumentation + Bayesian adjudication debate engine — status: Proposed |
| docs/adr/0089-federation-daemon-mvp.md | skimmed (title/status/decision) | 306 | Doc (ADR) | ADR-0089: MVP federation daemon (gossip + kg_sync + distributed_query) — status: Accepted |
| docs/adr/0090-contested-domain-steelman-policy.md | skimmed (title/status/decision) | 116 | Doc (ADR) | ADR-0090: Contested-domain steelman policy (represent every evidenced position at its strongest, never average into fals — status: Proposed |
| docs/adr/0090-federation-coordination-inference.md | skimmed (title/status/decision) | 293 | Doc (ADR) | ADR-0090: Federation coordination + inference (leader election + distributed rules) — status: Accepted |
| docs/adr/0091-federation-durability.md | skimmed (title/status/decision) | 330 | Doc (ADR) | ADR-0091: Federation durability (snapshot attestation + replication) — status: Accepted |
| docs/adr/0091-tiered-editions.md | reviewed | 46 | Doc (ADR) | ADR-0091: Tiered editions — Edge / Enterprise / Research — status: Proposed |
| docs/adr/0092-autonomous-self-update-governance.md | reviewed (key sections) | 315 | Doc (ADR) | ADR-0092: Autonomous self-update governance & safety gates — status: Proposed |
| docs/adr/0092-perception-module.md | skimmed (title/status/decision) | 271 | Doc (ADR) | ADR-0092: Perception module (parts/perception atoms + module + loop wiring) — status: Accepted |
| docs/adr/0093-action-module.md | skimmed (title/status/decision) | 326 | Doc (ADR) | ADR-0093: Action module (parts/action atoms + module + motor_map + effector-gate wiring) — status: Accepted |
| docs/adr/0093-domain-rollout-math-logic-cs.md | skimmed (title/status/decision) | 175 | Doc (ADR) | ADR-0093: Domain rollout strategy — math/logic/CS first — status: Proposed |
| docs/adr/0094-dtls-cert-chain-completion.md | skimmed (title/status/decision) | 332 | Doc (ADR) | ADR-0094: DTLS cert-verify chain completion (wire cert_chain_verify + truststore + hostname into dtls12) — status: Accepted |
| docs/adr/0094-security-architecture-and-threat-model.md | skimmed (title/status/decision) | 160 | Doc (ADR) | ADR-0094: Security architecture and threat model for the truth-seeking engine — status: Proposed |
| docs/adr/0095-dtls-srtp-completion.md | skimmed (title/status/decision) | 441 | Doc (ADR) | ADR-0095: DTLS-SRTP EKM stub-forward + `use_srtp` ClientHello extension (Phase O R2) — status: Accepted |
| docs/adr/0095-embodiment-sensorimotor-and-robotics.md | skimmed (title/status/decision) | 131 | Doc (ADR) | ADR-0095: Embodiment — sensorimotor architecture and robotics control — status: Proposed |
| docs/adr/0096-dtls-over-tcp-shim.md | reviewed (key sections) | 387 | Doc (ADR) | ADR-0096: Non-standard DTLS-1.2-over-TCP shim for gossip transport (Phase O R3) — status: Accepted |
| docs/adr/0096-machine-learning-policy.md | reviewed (key sections) | 133 | Doc (ADR) | ADR-0096: Machine-learning policy (online local learning yes, LLM/frozen-model cognition no) — status: Proposed |
| docs/adr/0097-dtls-server-flight.md | skimmed (title/status/decision) | 444 | Doc (ADR) | ADR-0097: DTLS 1.2 server-side handshake flight -- ClientHello parser + 4 body builders + transcript accumulator (Phase  — status: Accepted |
| docs/adr/0098-dtls-client-flight-finished.md | skimmed (title/status/decision) | 516 | Doc (ADR) | ADR-0098: DTLS 1.2 client-side handshake flight + Finished MAC + server flight-2 (Phase P R2) — status: Accepted |
| docs/adr/0099-dtls-extensions-and-streams.md | skimmed (title/status/decision) | 452 | Doc (ADR) | ADR-0099: DTLS extensions-block parser + `use_srtp` per-extension parser + DTLS-aware gossip stream helpers (Phase P R3) — status: Accepted |
| docs/adr/0100-moment-signal-cognition.md | reviewed | 214 | Doc (ADR) | ADR-0100: Moment-Signal Cognition (MSC) — the named cognitive architecture — status: Proposed |
| docs/adr/0100-nova-bootstrap-setarch-workaround.md | skimmed (title/status/decision) | 405 | Doc (ADR) | ADR-0100: NOVA bootstrap setarch -R workaround — status: Accepted |
| docs/adr/0101-data-acquisition-pipeline.md | skimmed (title/status/decision) | 422 | Doc (ADR) | ADR-0101: Data Acquisition Pipeline — status: Accepted (codifies R43+; documents the pipeline that R43 shi |
| docs/adr/0101-str-eq-migration.md | skimmed (title/status/decision) | 128 | Doc (ADR) | ADR-0101: `str_eq` → `str_eq_bytes` migration (R3b) — status: Accepted. Shipped by Phase Q R3b. Co-numbered with |
| docs/adr/0102-persona.md | reviewed (key sections) | 363 | Doc (ADR) | ADR-0102: Persona — full, per-user, advise-only — status: Proposed |
| docs/adr/0102-simd-ocr-segv-fixes.md | skimmed (title/status/decision) | 120 | Doc (ADR) | ADR-0102: SIMD / OCR SEGV fixes — class-B outliers (R3c) — status: Accepted. Shipped by Phase Q R3c. Co-numbered with |
| docs/adr/0103-memcpy-raw-tagged-ptr-workarounds.md | skimmed (title/status/decision) | 121 | Doc (ADR) | ADR-0103 — `memcpy_raw` + `rt_str_to_int` tagged-pointer workarounds — status: Accepted (2026-10-01, Phase Q R3d). |
| docs/adr/0103-skill-runtime.md | skimmed (title/status/decision) | 414 | Doc (ADR) | ADR-0103: Skill Runtime — the composition point where knowledge serves users — status: Proposed |
| docs/adr/0104-nl-surface.md | reviewed (key sections) | 463 | Doc (ADR) | ADR-0104: NL Surface Layer — grammar-first + LLM-preprocessor fallback — status: Proposed |
| docs/adr/0104-type-of-regression-and-cluster-d-fixes.md | skimmed (title/status/decision) | 195 | Doc (ADR) | ADR-0104 -- type_of() runtime regression and Cluster D/E residual fixes — status: Superseded by NOVA commit 651a507 (type_of codegen fix, 2026 |
| docs/adr/0105-sandbox-architecture.md | skimmed (title/status/decision) | 341 | Doc (ADR) | ADR-0105: Sandbox Architecture — capability separation, TLS, signed skill install — status: Proposed (R54 delivers capability tokens + verb-cap map; TLS |
| docs/adr/0105-sentinel-equality-and-rebuild-guards.md | skimmed (title/status/decision) | 140 | Doc (ADR) | ADR-0105 -- sentinel-equality (bug-#11) workarounds and rebuild-guard reinforcement — status: Accepted |
| docs/adr/0106-capsules.md | skimmed (title/status/decision) | 311 | Doc (ADR) | ADR-0106: Capsules — named shareable bundles on top of atoms — status: Proposed |
| docs/adr/0106-segfault-arc-closeout.md | skimmed (title/status/decision) | 110 | Doc (ADR) | ADR-0106 -- segfault-arc close-out (R3g residuals) — status: Accepted |
| docs/adr/0107-motor-map-population.md | skimmed (title/status/decision) | 107 | Doc (ADR) | ADR-0107 -- motor_map population + action_module wiring (Phase R1) — status: none stated |
| docs/adr/0107-pattern-capsules.md | skimmed (title/status/decision) | 243 | Doc (ADR) | ADR-0107: Pattern Capsules — reusable heuristics for skills — status: Proposed (R53) |
| docs/adr/0108-action-submit-dispatch.md | skimmed (title/status/decision) | 135 | Doc (ADR) | ADR-0108 -- payload-shim + per-class dispatch in `action_submit` (Phase R2) — status: none stated |
| docs/adr/0108-style-capsules.md | skimmed (title/status/decision) | 231 | Doc (ADR) | ADR-0108: Style Capsules — persona-owned rendering variants — status: Proposed (R52) |
| docs/adr/0109-operand-materialization.md | skimmed (title/status/decision) | 140 | Doc (ADR) | ADR-0109 -- operand materialization + reach-ability + SPEAK tier fix (Phase R3) — status: none stated |
| docs/adr/0109-ship-as-app.md | skimmed (title/status/decision) | 226 | Doc (ADR) | ADR-0109: Ship as App — packaging, distribution, and the daemon story — status: Proposed (R50) |
| docs/adr/0110-relay-bin-dtls-sealed-frame.md | skimmed (title/status/decision) | 143 | Doc (ADR) | ADR-0110 -- RELAY_BIN sealed-frame under DTLS (Phase P R4) — status: none stated |
| docs/adr/0111-auto-broadcast-on-snapshot-save.md | skimmed (title/status/decision) | 255 | Doc (ADR) | ADR-0111 -- Auto-broadcast attestation on snapshot save (Phase M R5) — status: none stated |
| docs/adr/0112-goal-template-registry.md | skimmed (title/status/decision) | 136 | Doc (ADR) | ADR-0112 -- goal-template registry for operand materialization (Phase R4) — status: none stated |
| docs/adr/0113-planner-keyword-heuristics.md | skimmed (title/status/decision) | 133 | Doc (ADR) | ADR-0113 -- planner keyword heuristics for operand materialization (Phase R5) — status: none stated |
| docs/adr/0114-dtls12-handshake-completion.md | skimmed (title/status/decision) | 215 | Doc (ADR) | ADR-0114: DTLS 1.2 handshake state-machine completion (close test_dtls12 to 519/0) — status: Proposed (2026-10-09); §1 superseded by R17 (2026-10-10). |
| docs/adr/adr-0200-crossengin-as-ai-factory.md | reviewed (key sections) | 522 | Doc (ADR) | ADR-0200: CrossEngin as AI Factory (Mother/Child Architecture) — status: Proposed (north-star). This ADR names the platform frame tha |
| docs/adr/adr-0201-nl-surface-small-llm-adapter.md | reviewed (key sections) | 270 | Doc (ADR) | ADR-0201: Sidecar Small-LLM NL Adapter (Fallback) — status: Proposed. Fixes the long-term shape of the small-LLM natural |
| docs/adr/adr-0202-cognitive-sandbox-and-multimodal-learning.md | skimmed (title/status/decision) | 276 | Doc (ADR) | ADR-0202: Cognitive Sandbox and Multimodal Learning — status: Proposed. Names the COGNITIVE sandbox as a first-class runti |
| docs/adr/adr-0203-mother-child-factory-runtime.md | skimmed (title/status/decision) | 286 | Doc (ADR) | ADR-0203: Mother/Child Factory Runtime — status: Proposed. Realizes the bake pipeline promised by ADR-0200 |
| docs/adr/adr-0204-slim-runtime-mode.md | skimmed (title/status/decision) | 212 | Doc (ADR) | ADR-0204: Slim Runtime Mode (`--child-mode`) — status: Proposed. Defines the boot-time flag that turns the standard |
| docs/adr/adr-0205-per-user-selective-load.md | skimmed (title/status/decision) | 200 | Doc (ADR) | ADR-0205: Per-User Selective Load — status: Proposed. Names the third consumption mode — same mother, pe |
| docs/adr/adr-0206-beliefs-and-self-awareness.md | reviewed (key sections) | 248 | Doc (ADR) | ADR-0206: Beliefs and Self-Awareness (First-Class Cognitive State) — status: Proposed. Promotes belief and self-awareness from scattered  |
| docs/adr/adr-0207-rag-and-fine-tuning-obsolescence.md | reviewed | 225 | Doc (ADR) | ADR-0207: RAG and Fine-Tuning Obsolescence — status: Proposed. Names the claim explicitly: given the CrossEngin s |
| docs/adr/adr-0208-latency-and-inference-budget.md | reviewed (key sections) | 227 | Doc (ADR) | ADR-0208: Latency and Inference Budget (Parity with LLMs) — status: Proposed. Establishes per-query-kind latency budgets that ke |
| docs/adr/adr-0209-deployment-form-factors.md | skimmed (title/status/decision) | 254 | Doc (ADR) | ADR-0209: Deployment Form Factors (Five Modes) — status: Proposed. Enumerates the five consumption modes named by ADR |
| docs/adr/adr-0210-agent-production.md | skimmed (title/status/decision) | 242 | Doc (ADR) | ADR-0210: Agent Production (Skills + Patterns + Composed Agents) — status: Tier 1 shipped (R47 -- ADR-0103); tier 2 shipped R109 -- Pha |
| docs/adr/adr-0211-llm-free-nlp-primary-path.md | reviewed (key sections) | 232 | Doc (ADR) | ADR-0211: LLM-Free NLP as Primary Path — status: Proposed. Locks the intended long-term shape of the NL surfa |
| docs/adr/r36f-0001-language-choice-nova.md | reviewed (key sections) | 103 | Doc (ADR) | ADR R36F-0001: NOVA as the implementation language — status: Accepted (R36F) -- decision originally made pre-R0, restated |
| docs/adr/r36f-0002-federated-learning-shape.md | skimmed (title/status/decision) | 91 | Doc (ADR) | ADR R36F-0002: Federated learning shape -- DP composition, EMA pull, Sybil model — status: Accepted (R36F) -- learning loop shape coalesced over R8 (in |
| docs/adr/r36f-0003-federation-stack-dtls-ice-turn-srtp.md | skimmed (title/status/decision) | 103 | Doc (ADR) | ADR R36F-0003: Federation transport -- DTLS 1.2 + ICE + STUN + TURN + SRTP — status: Accepted (R36F) -- transport stack assembled across R30C (IC |
| docs/adr/r36f-0004-substrate-not-pipeline.md | skimmed (title/status/decision) | 102 | Doc (ADR) | ADR R36F-0004: Cognitive substrate over modular pipeline — status: Accepted (R36F) -- restates the core decision originally cap |
| docs/adr/r36f-0005-self-hosting-bit-identical.md | skimmed (title/status/decision) | 89 | Doc (ADR) | ADR R36F-0005: Bit-identical self-hosting as a regression-detection invariant — status: Accepted (R36F) -- ratifies a property of the NOVA toolchain |
| docs/adr/r36f-0006-canonical-crypto-primitives.md | skimmed (title/status/decision) | 111 | Doc (ADR) | ADR R36F-0006: Canonical crypto primitives under `safety/` — status: Accepted (R36F) -- crystallises the pattern established at R |
| docs/adr/r39-autonomous-learning-architecture.md | skimmed (title/status/decision) | 326 | Doc (ADR) | R39: Autonomous learning architecture (trigger -> research -> preprocess -> ingest) — status: Accepted -- R39 round wiring of pre-existing ADR primitives  |
| docs/adr/r39-persistence-and-rehydration.md | skimmed (title/status/decision) | 250 | Doc (ADR) | R39: Persistence and rehydration (chat-state save/load + R40 chat-integration plan) — status: Accepted -- R39 round adds a per-process chat-state save/loa |
| docs/adr/r39-self-identification-wiring.md | reviewed (key sections) | 206 | Doc (ADR) | R39: Self-identification wiring (chat -> self_model_query bridge) — status: Accepted -- R39 round wiring of the pre-existing `self_model |
| docs/adr/r40-per-category-cognition.md | skimmed (title/status/decision) | 161 | Doc (ADR) | R40: Per-category cognition (classify → route → strategy) — status: Accepted — R40 round. Introduces ADR-0055 (input classificat |
| docs/adr/r41-live-internet-learning.md | skimmed (title/status/decision) | 120 | Doc (ADR) | R41: Live internet `/learn` (resolve → fetch → preprocess → ingest) — status: Accepted — R41 round. Closes the "/learn is not connected to |
| docs/adr/r42-tls13-https-client.md | skimmed (title/status/decision) | 94 | Doc (ADR) | R42: In-engine TLS 1.3 client (HTTPS for /learn) — status: Accepted — R42 round. Advances TLS_AUDIT.md from "PSK channe |
| docs/adr/r43-tls-certificate-verification.md | skimmed (title/status/decision) | 102 | Doc (ADR) | R43: Strict TLS authentication — RSA cert-chain verification + pinned anchor — status: Accepted — R43 round. Adds certificate verification to the R |
| docs/adr/r44-triple-extraction-quality.md | skimmed (title/status/decision) | 64 | Doc (ADR) | R44: Cleaner triple extraction (content-word reasoning edges) — status: Accepted — R44 round. Improves `src/learning/preprocess.nova |
| docs/adr/r45-noun-phrase-chunking.md | skimmed (title/status/decision) | 71 | Doc (ADR) | R45: Noun-phrase chunking + block-aware sentence splitting — status: Accepted — R45 round. Extends R44's clean triple extraction  |
| docs/adr/r46-pluggable-pem-trust-store.md | skimmed (title/status/decision) | 75 | Doc (ADR) | R46: Pluggable PEM trust store (anchors not hard-coded) — status: Accepted — R46 round. Generalises the R43 strict-TLS pin fro |
| docs/adr/r47-ecdsa-certificate-verification.md | skimmed (title/status/decision) | 61 | Doc (ADR) | R47: ECDSA certificate verification (key-type-agnostic strict TLS) — status: Accepted — R47 round. Extends the strict-TLS verifier (R43/R |
| docs/adr/r48-reader-bigram-anchoring.md | skimmed (title/status/decision) | 61 | Doc (ADR) | R48: Reader-side bigram anchoring (free-text compounds) — status: Accepted — R48 round. Closes the loop opened by R45: compoun |
| docs/adr/r49-morphological-normalization.md | skimmed (title/status/decision) | 60 | Doc (ADR) | R49: Morphological normalization (inflected free text hits learned atoms) — status: Accepted — R49 round. Improves lexical recall: a user typing |
| docs/adr/r50-autonomous-research.md | skimmed (title/status/decision) | 81 | Doc (ADR) | R50: Autonomous research (self-initiated /learn on unknowns) — status: Accepted — R50 round. Wires the self-learning-trigger queue  |
| docs/adr/r51-persistence.md | skimmed (title/status/decision) | 99 | Doc (ADR) | R51: Persistence of reasoning operators (learned chains survive a restart) — status: Accepted — R51 round. Closes the durability gap so learned k |
| docs/adr/r52-same-turn-reanswer.md | skimmed (title/status/decision) | 91 | Doc (ADR) | R52: Same-turn re-answer after autonomous research — status: Accepted — R52 round (the "h" enhancement). Closes the idle- |
| docs/adr/r53-multi-source-research.md | skimmed (title/status/decision) | 93 | Doc (ADR) | R53: Multi-source, disambiguation-aware research — status: Accepted — R53 round (the "i" enhancement). Replaces R50's s |
| docs/adr/r54-irregular-morphology.md | skimmed (title/status/decision) | 79 | Doc (ADR) | R54: Irregular morphology (a lemma table lifts R49's regular-only limit) — status: Accepted — R54 round (the "j" enhancement). Adds an irregula |
| docs/adr/r55-search-and-independent-sources.md | skimmed (title/status/decision) | 87 | Doc (ADR) | R55: Real search/disambiguation + a genuinely independent source — status: Accepted — R55 round (the "k" enhancement). Adds a real sear |
| docs/adr/r56-reperceived-counts.md | skimmed (title/status/decision) | 69 | Doc (ADR) | R56: Surface re-perceived counts on the same-turn answer — status: Accepted — R56 round (the "l" enhancement). Makes the `perce |
| docs/adr/r57-derivational-morphology.md | skimmed (title/status/decision) | 81 | Doc (ADR) | R57: Derivational morphology (the part-of-speech layer past inflection) — status: Accepted — R57 round (the "m" enhancement). Adds derivationa |
| docs/adr/r58-json-parser.md | skimmed (title/status/decision) | 77 | Doc (ADR) | R58: A real JSON parser (cleaner OpenSearch + a dictionary-API source) — status: Accepted — R58 round (the "n" enhancement). Adds a recursive |
| docs/adr/r59-dictionary-enrichment.md | skimmed (title/status/decision) | 71 | Doc (ADR) | R59: Always-aggregate dictionary definitions in research — status: Accepted — R59 round (the "o" enhancement). Makes the dictio |
| docs/adr/r60-autodefine-unknown-words.md | skimmed (title/status/decision) | 68 | Doc (ADR) | R60: Autodefine unknown words (a dictionary sense without full research) — status: Accepted — R60 round (the "p" enhancement). An unknown conte |
| docs/adr/r61-same-turn-autodefine.md | skimmed (title/status/decision) | 71 | Doc (ADR) | R61: Same-turn autodefine (a defined word answers in one turn) — status: Accepted — R61 round (the "q" enhancement). Extends R52's sa |
| docs/adr/r62-deverbal-morphology.md | skimmed (title/status/decision) | 68 | Doc (ADR) | R62: Deverbal morphology (-tion/-sion via a curated lemma table) — status: Accepted — R62 round (the "r" enhancement). Adds the -tion / |
| docs/adr/r63-definition-genus-operator.md | skimmed (title/status/decision) | 68 | Doc (ADR) | R63: Link a defined word to its definition's genus (so it reasons) — status: Accepted — R63 round (the "s" enhancement). When a word is d |
| docs/adr/r64-why-sources.md | skimmed (title/status/decision) | 57 | Doc (ADR) | R64: Cite knowledge sources in /why — status: Accepted — R64 round (the "t" enhancement). `/why` now lists |
| docs/adr/r65-persist-gloss.md | skimmed (title/status/decision) | 66 | Doc (ADR) | R65: Persist dictionary glosses across a snapshot — status: Accepted — R65 round (the "u" enhancement). The autodefine g |
| docs/adr/r66-synonym-antonym-edges.md | skimmed (title/status/decision) | 63 | Doc (ADR) | R66: Synonym / antonym edges widen the reasoning graph — status: Accepted — R66 round (the "v" enhancement). When a word is d |
| docs/adr/r67-opposite-relation.md | skimmed (title/status/decision) | 61 | Doc (ADR) | R67: A first-class ROP_OPPOSITE relation for antonyms — status: Accepted — R67 round (the "w" enhancement). Antonyms get the |
| docs/adr/r68-knowledge-command.md | skimmed (title/status/decision) | 54 | Doc (ADR) | R68: A consolidated /knowledge WORD view — status: Accepted — R68 round (the "x" enhancement). One read-only co |
| docs/adr/r69-define-sets-gloss.md | skimmed (title/status/decision) | 56 | Doc (ADR) | R69: /define sets the gloss (consistent dictionary learning) — status: Accepted — R69 round (the "y" enhancement). Moves the gloss- |
| docs/adr/r70-knowledge-incoming-senses.md | skimmed (title/status/decision) | 55 | Doc (ADR) | R70: /knowledge shows incoming edges + senses — status: Accepted — R70 round. Extends `/knowledge WORD` (R68) with t |
| docs/adr/r71-source-weighted-chain.md | skimmed (title/status/decision) | 58 | Doc (ADR) | R71: Source-weighted forward chaining — status: Accepted — R71 round. The academic forward-chain now weights |
| docs/adr/r72-opposite-aware-contrast.md | skimmed (title/status/decision) | 57 | Doc (ADR) | R72: Opposite-aware contrast in forward-chain replies — status: Accepted — R72 round. When the academic strategy forward-cha |
| docs/adr/r73-opposite-belief-update.md | skimmed (title/status/decision) | 53 | Doc (ADR) | R73: Opposite-aware belief update (X asserted ⇒ its opposite less likely) — status: Accepted — R73 round. R72 surfaced an antonym as a contrast  |
| docs/adr/r74-confidence-qualified-answers.md | skimmed (title/status/decision) | 54 | Doc (ADR) | R74: Confidence-qualified answers — status: Accepted — R74 round. The academic forward-chain answer is n |
| docs/adr/r75-anaphora-resolution.md | skimmed (title/status/decision) | 58 | Doc (ADR) | R75: Anaphora resolution (a pronoun follows the last topic) — status: Accepted — R75 round. A follow-up pronoun ("it", "they", …)  |
| docs/adr/r86-in-process-tls-scaffolding.md | skimmed (title/status/decision) | 408 | Doc (ADR) | R86: In-process TLS for wire endpoints (scaffolding only) — status: Accepted — R86 round; wire-enabled in R94. R86 scaffolded th |
| docs/bench-capture.md | reviewed (1-16) | 106 | Doc | How to paste an offline LLM transcript for the reasoning benchmark; shipped transcripts are "illustrative", not recorded. |
| docs/design/atom-provenance-schema.md | skimmed | 157 | Doc | Field-level spec for per-atom licence/evidence-grade ledger (ADR-0087). |
| docs/design/data_flow.md | skimmed | 76 | Doc | One substrate tick traced through signal dispatch/gates (Phase 1 kernel). |
| docs/design/int-safety.md | skimmed | 118 | Doc | Developer warning: NOVA miscompiles integer arithmetic reaching 2^20; use int_* builtins + lint. |
| docs/design/overview.md | skimmed | 77 | Doc (stale, 2026-05-25) | Still describes "v0.1, Phase 1 of 10". |
| docs/design/system-architecture.md | skimmed | 190 | Doc | June-15 "single current source of truth" after the truth-seeking expansion; itself superseded by docs/ARCHITECTURE.md in August. |
| docs/design/truth-seeking-overview.md | reviewed (1-60) | 118 | Doc | Narrative for ADR-0086: scope "expanded" from companion to "truth-seeking reasoning engine" that "out-reasons LLMs on checkable questions". |
| docs/runbook/build.md | skimmed | 55 | Doc | Build steps (May). |
| docs/runbook/run.md | skimmed | 94 | Doc | Per-binary run reference (May). |
| docs/runbook/test.md | skimmed | 53 | Doc | Test commands (May). |
| docs/runbook/troubleshooting.md | skimmed | 54 | Doc | NOVA_ROOT path issues etc. (May). |
| docs/runbook/windows.md | skimmed | 171 | Doc | WSL2/Docker instructions (May). |
| docs/session_log/archive.md | skimmed (headings, R44..R38 sections, R28E/R29B, tail "Recommended next session", targeted greps; 18.5k lines of per-agent round write-ups) | 18507 | Doc | Reverse-chronological archive of every round write-up from Phase 1 (May) to R43 (Aug). Primary evidence for process and for the Aug "99 passing / 220 failing" test table. |
| README.md | skimmed (lines 1-140, 4105-4590 read; 43-4104 is an append-only per-round changelog in one blockquote, sampled+grepped) | 4590 | Doc (stale) | Project front page. 20 lines of MSC/substrate pitch + "Status (through R39)" table, then ~4,000 lines of per-round changelog, then a May-era "What works now (v1.0)" module list and a layout section that still says 50 ADRs. |
| ARCHITECTURE.md | skimmed (1-120 read, rest module catalog) | 1094 | Doc (stale, R25D 2026-06-03) | Layout guide + per-module catalog as of round 25 (~190 modules, "50 ADRs"); claims "zero external runtime dependencies" beside scripts/web.py. |
| ANALYSIS.md | reviewed | 173 | Doc (2026-06-14) | Self-analysis: "verified achievements" table (incl. "~6M-node fabric") + candid "Honest gaps" table (AGI is "a programme, not a benchmark"); Vercel deployment options. |
| MANUAL.md | skimmed | 623 | Doc | Build/run/test walkthrough (Codespaces quickstart, make targets); last touched 2026-08-03. |
| NEXT_SESSION.md | reviewed | 126 | Doc (stale) | Says it is "source of truth... updated at every session boundary" but is frozen at R44 (2026-08-03); R44 notes: chat REPL had been segfaulting ~10+ commits, 4 packs/116 atoms. |
| NL_AND_COVERAGE.md | skimmed | 150 | Doc (roadmap, 2026-06-11) | NL + test-coverage roadmap N1-N4/C1-C2; admits full `make test` could not run (compiler hang on dtls12); "covered" = some test imports the module. |
| ENHANCEMENTS_ROADMAP.md | skimmed (1-60, headings, 1925-1960 read; bulk is per-round status log) | 5963 | Doc (roadmap turned changelog) | Began 2026-06-11 as P1-P5 plan (HDC, predictive coding, ingestion, tooling, self-improvement); first lower-case use of "moment-signal"; then accreted 5,900 lines of Phase L-R / NOVA-bug round logs. Contains "does NOT claim AGI". |
| FEDERATED_AUDIT.md | skimmed (head + grep; 6.5k-line per-round addenda) | 6535 | Doc | Federated "multi-soul" learning audit; append-only per-round addenda about gossip/DTLS/TURN/relay rounds. |
| SECAGG_AUDIT.md | skimmed | 1188 | Doc | Secure-aggregation audit: pairwise masking, dropout recovery, DH-256 "strawman" then DH-2048; mask derivation is an LCG. |
| DP_AUDIT.md | skimmed | 319 | Doc | Differential-privacy audit: discrete Laplace on integer milli values; notes NOVA had no floats. |
| REGRESSION_HUNT_R26F.md | reviewed (TL;DR), rest skimmed | 275 | Doc | One-off perf regression sweep vs bench/baseline.json: zero regressions; speed-ups attributed to a rebuilt compiler. |
| RETROSPECTIVE_26_ROUNDS.md | reviewed (sections 1-4, 8), appendices skimmed | 1181 | Doc | Retrospective of 26 rounds / "~156 parallel-agent dispatches" (2026-05-25..06-03): round headlines, file-ownership protocol, failure modes, honest-disclosure notes, open R*.2 follow-ups. |

Non-md files in docs/ (not counted above): `docs/caps.sample.conf` (sample capability config), `docs/samples/sample_agent.bundle` (616-byte signed sample bundle), `docs/samples/sample_agent.pub` (32-byte Ed25519 public key).
