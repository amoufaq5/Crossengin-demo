# nova_msc coverage

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
