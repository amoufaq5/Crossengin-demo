# nova_msc findings — NOVA `src/core`, `src/mind`, `src/agent`, `src/cognitive`, `src/runtime`, `examples`

Reviewer: `nova_msc`. HEAD 663bf0e (2026-11-16). 146 files. All paths are `NOVA/`-relative unless prefixed `CE/`.
Probe programs and logs: `/tmp/claude-0/-home-user/0f6d34e6-ba9a-56d7-bcb5-b0fca8a83a57/scratchpad/probes/nova_msc/` (`run_tests.sh` = the repo runner with private temp paths, `test_results.txt`, `ct.sh` = concat+compile+run helper, `ex/*.out` = output of every example).

## Plain-language summary

- **What MSC is in this code**: a small message-passing framework. A "moment" is a 9-field record (a text string plus a few 0–100 integers). A "signal" is an envelope around a moment with a type code, a destination name and a priority. A "node" is a mailbox plus a key/value state map, processed by one of six hand-written handler functions. A scheduler pops the highest-priority signal, hands it to the named node, and forwards whatever the node emits along statically declared channels. There is no learned representation anywhere in the core loop: all "similarity" is exact string equality, substring match, or fixed-weight sums of small integers.
- **It mostly still works.** The lead's hypothesis that the MSC code no longer compiles after the tagged-integer rework is **mostly refuted**. 10 of the listed failing tests (test_scheduler, test_mind, test_m8_mind, test_m9_fullsystem, test_concept, test_federation, test_tensor, test_tensor_perf, test_embedding, test_associative) pass unchanged once the *test harness concat list* is given the dependency it forgot (`soul.nova`, `db.nova`, or a `mem_free` definition). They broke on 2026-10-06 when the compiler began rejecting calls to undefined functions (commit 0f9d3f2), which exposed latent missing dependencies; previously those calls were silently emitted.
- **Real regressions exist too**: the `float_cmp` builtin returns 0 instead of 1 for "greater than"; `db` reload loses records; `sys_mmap`-based allocators fail; `imagine_best_scenario` segfaults; `random(n)` returned 310266 for n=30 on its first call.
- **The agent** (`make agent`) is a keyword-routed template chatbot over a triple store. It does not use nodes, channels, paths or the scheduler. `make agent` itself is broken at HEAD (same missing-dependency issue) but runs when fixed.
- **Learning**: storage of facts, counters, running means, and Beta pseudo-counts in the main path. Three genuinely adaptive numeric rules exist (Hopfield Hebbian store, a linear delta-rule "predictive coding" layer, an exponential-moving-average "resonance" preference) but they live in `src/cognitive/`, which nothing but its own tests and demos calls.
- **LLM / conventional ML**: `runtime/llm.nova` + `llm_bridge.c` wrap local llama.cpp (no HTTP, no API keys); `python.nova` embeds CPython/numpy; `blas.nova` dlopens OpenBLAS; `gpu.nova` dlopens CUDA/OpenCL. **None of these is called by anything** in src, tests or examples, and none is built by the Makefile. `agent/cognitive_llm.nova` is named as an LLM pipeline but contains no LLM call. So NOVA's MSC path genuinely does not depend on an LLM — and equally, the "LLM integration" is unexercised code.
- **CrossEngin does not use any of this.** CE imports only `std/syscall`, `std/io`, `std/string` (and `std/node_pool` once). NOVA `src/core`, `src/mind`, `src/agent`, `src/cognitive` are orphaned relative to CE.
- **Examples**: 33 of 66 run as shipped; 24 fail with "undeclared callee" because they have no imports; the two examples showing the headline `moment {…}` / `mind Agent {…}` syntax do not parse and never did.
- TODO/FIXME/HACK/XXX count in this area: **0**.

## Findings table

| ID | Sev | Category | Title | file:line | Evidence | Impact | Recommended fix | Effort | Confidence |
|---|---|---|---|---|---|---|---|---|---|
| M1 | High | Build/test rot | Ten "failing" MSC tests fail only because harness concat lists omit a dependency | tests/run_tests.sh:73-88 (scheduler, mind omit soul.nova), :46-72 (m8/m9 omit db.nova), :96-114 and :191-197 (tensor/embedding/associative: mem.nova has no `mem_free`), :152-157 (concept omits db.nova), :296-301 (federation omits db.nova); src/core/node.nova:644 calls `scheduler_get_soul`; src/runtime/tensor.nova:122 calls `mem_free` | `ERROR: undeclared callee: soul_bias` / `db_put_int` / `mem_free`. Re-run with the missing file added: test_scheduler, test_mind, test_m8_mind, test_m9_fullsystem ("M9 full system verification PASSED"), test_concept, test_federation 12/12 all pass; with a 3-line `mem_free` stub test_tensor, test_tensor_perf 18/18, test_embedding, test_associative 10/10 pass | Suite reports 30 failures; ~10 are harness errors, masking the real ones | Add soul.nova/db.nova to the lists; add `mem_free` to mem.nova (or drop the call in tensor_free) | S | CONFIRMED |
| M2 | High | Correctness | `float_cmp` builtin returns 0 (not 1) when a > b | probe fc.nova; used as `float_cmp(..) > 0` in src/runtime/tensor.nova (3), src/agent/rag.nova (4), src/runtime/confidence.nova (3), src/agent/cognitive_llm.nova (3), src/runtime/embedding.nova (2), src/cognitive/hdc.nova (1) | `float_cmp(0.65,0.35)` → 0; `float_cmp(0.35,0.65)` → -1; `float_cmp(3.0,2.0)` → 0. test_cognitive_llm: "Confident 0.650000 / Uncertain 0.350000 / FAIL: expected confident > uncertain". test_float_utils 16/32 | Every float max/sort/threshold in tensor, RAG ranking, relu, confidence is wrong at HEAD | Fix builtin (likely returns raw 1 where a tagged int is expected); add a builtin-level regression test | S | CONFIRMED (root cause LIKELY) |
| M3 | High | Correctness | Key-value DB reload loses records | src/runtime/db.nova:db_open (split on "\n" + `str_find(line,"=")`) | Probe: 3 records saved (file correct on disk), `db_open` → count 0. examples/knowledge_demo: saves 4, prints "Reloaded 3 entries". test_knowledge: "FAIL: db_load_name - expected 'Nova' got ''" then segfault. Probe sp.nova: `split("a=1\nbb=2\nccc=3\n","\n")` returns `[a][1\n][bb][]` | Persistence of academic facts, memory episodes and KG (`*_save`/`*_load`) is unreliable; "memory survives restart" is not true at HEAD | Fix `split`/`str_find` builtins; add round-trip test with assertion on count | S–M | CONFIRMED (cause SUSPECTED: builtin string regression) |
| M4 | High | Overstated naming | `cognitive_llm.nova` contains no LLM call | src/agent/cognitive_llm.nova:243-249 (`cognitive_generate(text,max_tokens)` returns `conf_new(text, keyword_confidence)`), :55-105, :264-290 | "generate" echoes its input; confidence = 0.50 ±0.15/0.10 for words like "maybe", "definitely"; `cognitive_chat` prepends past prompts and calls the same echo | Header says "LLM generation with symbolic reasoning … Nova's differentiator"; reader would believe an LLM is integrated | Rename (e.g. `confidence_annotate`) or actually wire `llm_generate`; delete README claims | S | CONFIRMED |
| M5 | High | Dead code | LLM, Python, BLAS, GPU, HTTP, RAG, preprocess, gates, parts, reader, signal_flow, synapse, effects have zero callers and zero tests | src/runtime/{llm,python,blas,gpu,http,effects}.nova, src/runtime/llm_bridge.c, src/agent/{rag,preprocess}.nova, src/core/{gates,parts,reader,signal_flow,synapse}.nova | Token-level cross-reference over all src/tests/examples (probe users.py): no other file references any function they define. gates.nova does not parse (`let match = …` at :194, `match` is now a keyword). effects.nova: "undeclared callee: list_get". The five core files were added in one commit "Implement N1-N11 cognitive architecture primitives for CrossEngin" (2026-05-24) and CE never imported them | ~5,000 LOC that has never been executed in this repo at HEAD; claims in README about LLM/RAG/Python/GPU are unverifiable | Delete or move to `attic/`; if kept, add one compiling test each | M | CONFIRMED |
| M6 | High | Orphaned | CrossEngin uses none of NOVA core/mind/agent/cognitive | CE imports (all `.nova`): `std/syscall` 454, `std/io` 446, `std/string` 427, `std/node_pool` 1 (CE/src/substrate/node_pool_manager.nova); CE/nova-deps.toml:26-39 lists core/mind modules as "built on conceptually … integrated by composition" | grep for `node_process(`, `signal_new(`, `moment_new(`, `scheduler_dispatch_one(`, `soul_tick(`, `academic_add_axiom(`, `reasoning_deduce(`, `kg_add_entity(`, `embed_cosine(`, `tensor_new(`, `llm_generate(`, `py_init(` in CE: no hits | The "original MSC" and CE's MSC are two unrelated implementations; fixes/experiments in one do not transfer | Decide which is canonical; say so in both READMEs | S (doc) | CONFIRMED |
| M7 | High | Build rot | `make agent` is broken at HEAD | Makefile:621-631 (concat list lacks scheduler.nova, db.nova, safety/goal/imagination) | `ERROR: undeclared callee: scheduler_get_soul`; and because the recipe uses `2>/dev/null &&`, the user just sees nothing. With the 5 files added it builds and runs | The project's only interactive "cognitive agent" cannot be started by its documented command | Fix list (or give agent.nova real imports) | S | CONFIRMED |
| M8 | High | Canned behaviour | Agent "reasoning" is ordered substring classification + sentence templates | src/agent/agent.nova:157-216 (`classify_input`, ~35 `contains`/`starts_with` rules), :394-523 (`pipeline_reason`), :525-629 (`reason_about_topic`) | Transcript (probe): "hello"→"Hello! Nice to interact with you."; "who are you"→fixed sentence; "what is dog"→"dog is a mammal, which is a animal. dog has loyalty."; "why is the sky blue?"→"I don't know much about 'why is the sky blue' yet…"; "I feel terrible today"→"I see." | It is a triple-store lookup bot. Banner claims "Reason about knowledge (structural analogy)", "Imagine scenarios and counterfactuals", "Pursue goals" (agent.nova:821-824); imagination is only `imagination_init()` (:68), never called | Rewrite banner to match; or route input through the node graph it advertises | S | CONFIRMED |
| M9 | Medium | Correctness | Agent's own example questions fail; "constitution" blocks harmless answers | src/agent/agent.nova:218-262 (`extract_topic` keeps "?"), :86-88 + :757-765 + src/core/soul.nova:642-656 (substring check on the *response*) | "/help" suggests "what is dog?" → reply "I don't know much about 'dog?' yet". Teaching "smoking is harmful" → "I can't do that -- it conflicts with my core values." (response contains "harm") and thereafter "what is smoking" is also blocked | Demo fails on first documented input; value check is a 3-word substring blacklist applied to output text | Strip punctuation in extract_topic; remove or redesign constitution check | S | CONFIRMED |
| M10 | Medium | Architecture claim | Agent "five concurrent loops communicating via signal queues" are five sequential function calls over plain lists | src/agent/agent.nova:791-806 (`cognitive_cycle`), :29-56 | `_loop_perceive(); _loop_memory(); _loop_emotion(); _loop_reasoning(); _loop_action()` in fixed order; queues are lists of tuples, not `signal` records; no node/channel/scheduler use | Header comment ("Multi-loop concurrent agent architecture") overstates | Fix comment | S | CONFIRMED |
| M11 | Medium | Fake/aspirational | Headline-syntax examples never parsed | examples/moment_signal.nova:3-8, examples/basic_mind.nova:1-30; docs/TOUR.md:41 cites basic_mind | `error[line 5]: expected : but got {` and `error[line 1]: unexpected :`. Both files date from the first two days (2026-05-16) and were never updated | The picture of the language shown to newcomers is not the language that exists | Rewrite using real `mind`/`soul`/`system` syntax (which does work: mind_declaration, soul_demo, system_syntax_demo) | S | CONFIRMED |
| M12 | Medium | Examples | 24 of 66 examples fail "undeclared callee" as shipped; 11 more crash when their module is supplied | examples/*_demo.nova (no `import` lines) | See coverage table. With module concatenated: atom_lifecycle, hdc, resonance, timeseries, mind_declaration, time_machine, visualizer, kg_visualizer run; active_inference (killed), causal_library, predictive_coding, sdr, self_model, skill, audio, node_pool, federation, profiler segfault; flow_operators "index out of bounds: 1" | Demos are not evidence that the features work. Several crashes look like demo/API drift (e.g. examples/active_inference_demo.nova:9 `ai_new(3)` vs 3-arg `ai_new` at src/cognitive/active_inference.nova:13) | Add imports; add `make examples` smoke target to CI | M | CONFIRMED (cause LIKELY) |
| M13 | Medium | Correctness | `examples/signal_processing.nova` loops forever | examples/signal_processing.nova | 514 MB of "[Perceiver] Received: user says hello" in 20 s | Flagship MSC demo is a runaway | Fix loop / add cycle cap | S | CONFIRMED |
| M14 | Medium | Correctness | `examples/higher_order.nova` prints wrong arithmetic | examples/higher_order.nova:44-48 | "Add 3+4 = 0", "Mul 3*4 = 0" | Closure/fn-ref call path returns 0 (compiler issue surfaced by example) | Investigate in compiler | M | CONFIRMED |
| M15 | Medium | Correctness | `imagine_best_scenario` segfaults; `random(30)` first call returned 310266 | src/core/imagination.nova:314-325; probe rnd.nova | test_imagination exits 139 after "generated 3 scenarios"; probe shows scenario likelihood 95 where code bounds it to 20..49 before clamp, because `random(30)` returned 310266 | Imagination module not usable at HEAD | Compiler/runtime fix (function body is ordinary code) | M | CONFIRMED (cause SUSPECTED: codegen) |
| M16 | Medium | Overstated naming | "Imagination / world model / counterfactual / dream" = 10-row keyword table + random | src/core/imagination.nova:48-60, :138-151, :182-190, :203-215, :217-247, :263-306 | `imagine_consequence("break the vase")` → first table row whose keyword is a substring → "object broken"; scenario likelihood = `40 + random(40)`; dream = random pairs of episode strings joined by a random relation word | Names imply simulation; code is lookup + RNG presented as "likelihood" | Rename or document honestly | S | CONFIRMED |
| M17 | Medium | Overstated naming | "1000+ causal patterns" = 51 hand-written rows × 19 adverbs | src/cognitive/causal_library.nova:68-428 (51 `_causal_add_seed`), :430-452, :515-563; tests/test_causal_library.nova:22 asserts `count >= 1000` | Variations copy the seed and change only a strength offset and a modifier word | Count is inflated; test asserts the inflation | State "51 seed patterns" | S | CONFIRMED |
| M18 | Medium | Test quality | test_embedding cannot fail on similarity and shows both sims = 0 | tests/test_embedding.nova:17-30 | Prints `sim(fox,canine)=0.000000`, `sim(fox,python)=0.000000`, then "PASS embedding" with no assertion | The BM25/n-gram "embedding" is unverified and appears to return 0 for everything at HEAD | Assert related > unrelated | S | CONFIRMED |
| M19 | Medium | Security | "secure" RNG is a predictable LCG; XOR "encryption" | src/runtime/secure_mem.nova (`_sec_auto_seed`: `global_time ^ 48271`; `_sec_next`: `seed*1103515245+12345 & 0x7fffffff`; `secure_token`), src/runtime/crypto.nova (`xor_encrypt`, `checksum` = djb2) | Seed is a small monotonic counter; tokens fully predictable. Repeating-key XOR offered as encrypt/decrypt | Anything using secure_token/xor_encrypt has no security | Use the `secure_random` builtin (getrandom); remove xor_encrypt or rename `xor_obfuscate` | S | CONFIRMED |
| M20 | Medium | Security | http.nova whitelist is bypassable; no TLS; header injection | src/runtime/http.nova:411-433 (`http_get(host_ip, port, path, host_header)` checks whitelist on `host_header`, connects to `host_ip`), :127-153 (no CR/LF filtering of path/host/headers) | Caller-controlled Host string is what is checked | If ever wired to untrusted input: SSRF + request smuggling. Currently dead code | Delete, or check the resolved IP and sanitise | S | CONFIRMED (dead code) |
| M21 | Medium | Security/robustness | db.nova format has no escaping | src/runtime/db.nova:db_save / db_open | Value containing "\n" creates extra records; key containing "=" splits wrongly; whole file rewritten non-atomically | Data corruption / record injection from user-taught facts (agent stores user text) | Length-prefix or escape; write-temp-then-rename | S | CONFIRMED (by reading) |
| M22 | Medium | Memory safety | Raw peek/poke with no bounds, used by tensor/simd/hdc/audio/node_pool | src/runtime/mem.nova:5-115, src/runtime/tensor.nova (`tensor_get/set` no index check), src/runtime/simd.nova | `tensor_set(t, r, c, v)` writes `t[3] + (r*cols+c)*8` unchecked; `tensor_free` then use = UAF | Out-of-range index = silent memory corruption | Add bounds checks in tensor_get/set | S | CONFIRMED (by reading) |
| M23 | Medium | Runtime regressions | mmap-based allocators, taskpool, coroutines failing at HEAD | tests: test_runtime "FAIL: sys_mmap failed"; test_persistent_alloc "FAIL: open new pool" + segfault; test_taskpool timeout; test_coro_advanced segfault; examples/concurrency segfault | from `test_results.txt` | arena/persistent allocators, fork pool and advanced coroutines are not usable | Compiler/runtime owner to triage (likely tagged-int vs inline-asm) | M | CONFIRMED (cause SUSPECTED) |
| M24 | Low | Dead branch | Reflex path can never trigger | src/core/moment.nova:92 (urgency always pushed as 50, no setter), src/core/path.nova:23 (`REFLEX_URGENCY_THRESHOLD = 70`), :174 | `urgency > 70` is false for every moment created by `moment_new` | "Reflex path" feature is inert unless a caller pokes index 7 by hand | Add `moment_set_urgency` or derive urgency | S | LIKELY |
| M25 | Low | Design | Loop prevention forbids any recurrence | src/runtime/scheduler.nova:141-145 | A signal whose trace already contains the destination is dropped | No node can process the same signal twice → no iterative settling/feedback through the graph | Document; it is a deliberate guard | – | CONFIRMED |
| M26 | Low | Overstated naming | `embed.nova` "semantic embeddings" are caller-supplied integer lists | src/runtime/embed.nova:1-45; examples/knowledge_demo.nova (cat = [90,60,30,10,80,20]) | No function maps text to a vector | KG "nearest neighbour by embedding" reflects whatever numbers the programmer typed | Say "feature vectors" | S | CONFIRMED |
| M27 | Low | Unused C | llm_bridge.c never compiled | src/runtime/llm_bridge.c:1-20; Makefile has no rule for libnovabridge.so | `#include "llama.h"`; llama.cpp not vendored | Cannot be verified; bounded memcpy at :296-301 looks correct | Remove or add build rule + CI skip | S | CONFIRMED |

## MSC as implemented in NOVA (precise definition)

Everything below is integer arithmetic on small ints (0–100, or ×1000 fixed point) and strings. There are no vectors, matrices or floats in the MSC core path (`core/moment, signal, node, channel, path, similarity, soul` + `runtime/scheduler`). All containers are Nova lists used as tagged tuples.

### Data records

```
Moment  m = [100, what:string, who:any, valence:0..100, arousal:0..100,
             consequence, salience:0..100, urgency:=50 (constant), time:=++global_time]
                                                     core/moment.nova:82-95
Consequence c = [103, type:1..7, desc:string, certainty:int]      moment.nova:252-259
Emotion e = [102, valence, arousal, dominance]                    moment.nova:206-213
Signal  s = [110, type:1..22, moment, origin:string, dest:string,
             priority:int, trace:list<string>, meta:map]          core/signal.nova:45-56
Node    n = [tag, name, type:1..6, state:map, inbox:list, outbox:list, config:map]
                                                                  core/node.nova:25-35
Channel ch = [tag, name, source:string, dests:list<Node>, type, filter_min/weight, msg_count]
                                                                  core/channel.nova:26-85
Path    p = [tag, name, type, steps:list<Node>, enrichment:list<Node>]  core/path.nova:29-37
```
The 22 signal types (event, question, …, recall) differ only in the type code and a default priority constant (signal.nova:58-136). Types are consulted in exactly three places: reasoner strategy choice (node.nova:460-466), soul classification (`st == 7` → negative feedback, soul.nova:289) and mind/reasoning strategy choice.

### Derived quantities
```
intensity(m)      = (|valence-50| + arousal) / 2                         moment.nova:114-119
emotion_drift(c,t,r) = c + (t-c)*r/100   per V,A,D                       moment.nova:226-237
similarity_score  = .35*content + .20*entity + .15*emotion + .15*recency
                    + .10*frequency + .05*consequence   (ints, clamp 0..100)  similarity.nova:19-29
jaccard(A,B)      = 100*|A∩B| / (|A|+|B|-|A∩B|)   on lists of strings     similarity.nova:36-63
emotion_similarity= 100 - 100*min(|dv|+|da|+|dd|,300)/300                similarity.nova:71-86
recency(t,now)    = clamp(100 - (now-t)/10, 0, 100)                       similarity.nova:94-99
spread_activation = BFS from seed; child_act = parent_act*decay/100; stop < 5  similarity.nova:144-210
```
So "similarity" computes: exact-equality or substring tests on strings turned into 0/10/60/100, combined by fixed hand-chosen weights. No learned metric.

### Node handlers (`node_process`, node.nova:672-690)
For each signal in inbox, by node type; then clear inbox:

- **Perceiver** (node.nova:119-167): for each template (keyword list, boost), `score = Σ 100/|kw|` over keywords that are substrings of `what`; best template; forward the signal iff `min(salience+boost,100) >= threshold(20)`; with no template match forward iff `salience > 20`.
- **Knower** (:210-272): find concept whose name `== what`; BFS ≤3 hops over a hand-built adjacency list with energy 100·(decay 60%)^d; store result list in state; forward signal unchanged.
- **Rememberer** (:280-372): append moment to `episodes`; score every stored episode with `similarity_score(content = 100 if what equal else 10, entity = 100 if who equal else 0, emotion = 100 - (|dv|+|da|)/2, recency, min(access*10,100), 50)`; O(E²) exchange sort; top-3 get `access_count += 1`; forward signal unchanged.
- **Reasoner** (:410-496): strategy by signal type: question→`deduce` (first rule with `cond == what`, return its conclusion), event→`analogize` (case equal → 100, case contains what → 60, best), reflection→`abduce` (first rule with `conclusion == what`). Emits a new RESPONSE signal whose moment is the literal `"analysis complete"` with the conclusion string in the consequence slot, addressed to the incoming signal's origin.
- **Feeler** (:519-549): `emotion ← emotion_drift(emotion, (valence, arousal, 50+salience/4), rate 30%)`; forward iff `intensity > 30`, and again iff new arousal > 70 (can emit the same signal twice).
- **Actor** (:617-667): `activation = .40*salience + .25*habit_strength + .20*arousal + .15*(80 if reflex substring match else 0)`, then `× soul_bias/100` if a soul is registered; if `>= 25` emit an EVENT signal with moment `"action taken"` to dest `"output"`.

### Scheduler loop (runtime/scheduler.nova:128-169, 261-288)
```
queue Q: list kept sorted by priority desc (insert O(|Q|), pop-front O(|Q|))
run():  while Q non-empty:
  s ← pop(Q)
  n ← first registered node with name == s.dest          (linear scan)
  if n missing or s.dest ∈ s.trace:  dropped++ ; continue (loop guard)
  n.inbox.push(s); node_process(n)       (handler appends n.name to s.trace)
  for o in drain(n.outbox):
      for each channel ch with ch.source == n.name:
          for d in ch.dests: Q.insert(copy of o with dest=d.name, trace copied)
      if no channel matched: Q.insert(o)                 (keeps its own dest)
  if soul: soul_tick(soul, s); Q.insert(each soul drive signal)
  processed++          ; hard cap 10000 signals per cycle
```
Variants: batched (group by destination), "secure" (blocked-route list + per-node rate limit), stream-fed, and tick timers (scheduler.nova:175-652). Channels of type filtered/weighted are only honoured by `channel_network_route_all` (channel.nova:202-226); the scheduler's own `scheduler_route_output` ignores channel type, salience filter and weight (scheduler.nova:82-104).

### Path (core/path.nova:90-107)
`for node in steps: receive(node, sig); process(node); sig ← first output, or return 0 if none`. A synchronous pipeline that bypasses the scheduler. Reflex variant skips middle steps when `urgency > 70`, which cannot occur (M24).

### Soul (core/soul.nova)
State: key→int tables for drives and feelings (clamped 0..100), a phase name, interaction and idle counters, reaction table.
```
soul_tick(s, sig):                                           soul.nova:472-496
  interactions++ ; idle = 0
  if valence>60 or <40: warmth += (valence-50)/5
  if arousal>60:        alertness += (arousal-50)/5
  class = "negative_feedback" if type==7 or valence<35
          "positive_feedback" if valence>65
          "novel_input" if salience>70 else "neutral"
  apply reaction effects for class (shift feeling by amount; +5 precision; +10 curiosity/-10 confidence; set phase)
  phase transition if interactions/confidence/idle exceeds configured value
  every feeling moves 1 step toward 50
soul_check_drives: for each drive >= 90: emit signal(type by name) with dest "" ; drive -= 15   :364-390
soul_bias = clamp(100 + {acting:+20, reflecting:+10, awakening:-10, dreaming:-20}
                      + (confidence-70)/3 if >70  - (30-confidence)/3 if <30, 50, 150)       :396-425
soul_preprocess(text): ~25 substring rules ("why"→question, "thanks"→valence 80, "!"→arousal+15 …) :431-466
```
Note: drive signals are emitted with `dest = ""`, so the scheduler drops them as "node not found" unless a node is named "" (scheduler.nova:135-139) — LIKELY inert.

### The "mind" modules (global singletons, used by the agent, not by nodes)
- **academic** (mind/academic.nova): list of (subject, relation, object) triples; query by linear scan; rules `relation A ⇒ relation B (conf)`; `derive` = depth-bounded recursion multiplying confidences.
- **experiential** (mind/experiential.nova:122-230): only moments with `intensity > 30`; per `what` string: `valence_avg ← (avg*count + v)/(count+1)`, `count++`, `bias = approach if avg>=50 else avoid`; when `count >= 3` create tendency with `strength = min(count*10, 100)`.
- **emotion** (mind/emotion.nova:93-140): `w = max(salience/2, 5)`; `V ← V + (v-V)*w/100`, same for A; D nudged ±salience/5 when salience>50; decay toward baseline; `emotion_describe` buckets (V,A) into words.
- **memory** (mind/memory.nova:197-285): `score = 3*[what equal]*100 + 2*[who equal]*100 + 2*max(0,100-|dv|-|da|) + max(0,100-age) + min(5*access,50)`; selection sort; returned episodes get `access_count++`. Decay: drop when `importance - age/10 + 5*access < threshold`.
- **reasoning** (mind/reasoning.nova): rules `cond → cons (conf)` matched by string equality; deduce = recursive chain with `conf = c1*c2/100`, cut below 20; abduce = reverse; analogize = shared content words with stored episode text; `reasoning_observe_causal`: `observations++, strength = min(strength+5, 100)` or create link at 40 (:148-171).
- **belief** (core/belief.nova): Beta(α,β) with ×1000 fixed point: `mean = 1000α/(α+β)`; update `α += w` or `β += w`; `variance ≈ 1000αβ/(α+β)²` (not the Beta variance — missing the `/(α+β+1)` term); "entropy" = `mean*(1000-mean)/max(1,(α+β)/1000)` (a heuristic, not entropy). Used only by test_belief.
- **goal** (core/goal.nova): records + threshold rules that create goals named e.g. "explore_knowledge" when `knowledge_count < 10`; top-N by priority; action scoring by keyword overlap.
- **concept** (core/concept.nova): is-a tree; `taxonomic_similarity = 2*depth(common ancestor)*1000 / (depth1+depth2)`.

**Answer to "numeric computation or message passing?"** Message passing of records between hand-written handlers, with a handful of fixed-weight integer formulas. The only adaptive numeric code is in `src/cognitive/` and is not connected to nodes, signals or the agent.

## Learning mechanisms

"On main path" = reachable from `node_process`/scheduler or from `agent.nova`.

| # | Where | State changed | Rule | Class | On main path? | Changes future behaviour? |
|---|---|---|---|---|---|---|
| L1 | mind/academic.nova:36-61, 229-271 (`academic_add_axiom`, `academic_store`) via agent "teaching" (agent.nova:379-392) | triple list | append (X, is_a/has, Y) parsed from "X is Y" | lookup-table storage | agent | yes: later "what is X" returns it |
| L2 | core/node.nova:280-291, 355-357; mind/memory.nova:82-104, 277-281 | episode list; access_count | append; `access_count += 1` on recall | storage + counter | nodes (rememberer), agent | marginally (frequency term ≤10% of score) |
| L3 | mind/experiential.nova:122-178 | per-trigger running mean valence, count, tendency strength | running mean; promote at count ≥ 3; strength = 10·count | counter / running average | agent | only adds the phrase "This is a familiar topic." / "positive tendency" (agent.nova:441-445, 512-515) |
| L4 | mind/reasoning.nova:148-171 | causal link strength, observation count | +5 per repeat, new link at 40 | counter | defined, **not called** by agent or nodes | no |
| L5 | mind/emotion.nova:93-140; core/node.nova:530-538; core/soul.nova:472-496 | VAD ints; soul feelings/drives | exponential smoothing toward input; ±k shifts; decay to 50 | leaky integrator (state, not learning) | agent / nodes / scheduler | transient mood only; decays back |
| L6 | core/belief.nova:39-45 | α, β | `α += w` / `β += w` | Bayesian (Beta–Bernoulli conjugate update) | **no** (test only) | – |
| L7 | cognitive/active_inference.nova:59-80 | α_s, β_s per state | `α += lik/10` if lik>500 else `β += (1000-lik)/10` | Bayesian-like pseudo-count (heuristic, not exact Bayes) | no (test/demo only) | within its own model |
| L8 | cognitive/associative.nova:54-85 | N×N float weight matrix | `W_ij += s_i s_j` | Hebbian (Hopfield) | no (test/demo only) | yes, pattern completion |
| L9 | cognitive/predictive_coding.nova:88-120, 183-239 | layer weights, biases (int ×1000) | `w += lr·err_j·input_i`, `b += lr·err_j`, clamp ±5000 | gradient-based (delta rule on a linear layer; no backprop through nonlinearity) | no (test/demo only) | yes |
| L10 | cognitive/resonance.nova:125-136 | preference vector | `pref += lr·(obs − pref)` | running average (EMA / prototype learning) | no (test/demo only) | yes |
| L11 | cognitive/atom_lifecycle.nova:92-111, 200-238 | pattern-hash counts; activity levels | `count++`; birth at threshold; decay → death | counter | no (test/demo only) | – |
| L12 | cognitive/skill.nova:91-113 | success/attempt counters | `rate = 1000·s/n` | counter | no | – |
| L13 | core/gates.nova:gate_learn | rule weights | `+lr/10` if rule contains correct dest else `−lr/20`; new rule at 500+lr/10 | supervised counter-style (needs the correct answer supplied) | **no — file does not parse** | – |
| L14 | core/synapse.nova (`synapse_bank_hebbian_update`, `synapse_bank_tick`) | edge weights | `w += corr·growth/1000` (corr supplied by caller); `w −= decay` per tick; prune | Hebbian-like bookkeeping (no co-activity is measured by the code itself) | no (no callers) | – |
| L15 | core/reader.nova (`reader_learn`) | KG relation list | add relation if absent, weight = learn_rate | storage | no (no callers) | – |
| L16 | runtime/embedding.nova (`embedding_add_document`), agent/rag.nova (`rag_add_document`) | vocabulary, document frequencies | TF-IDF/BM25 statistics | counter (corpus statistics) | no (no callers) | – |

**Bottom line**: on the path a user can actually run (the agent, or the node/scheduler graph), "learning" is (a) appending facts/episodes to lists and (b) counters and running means. Nothing on that path adjusts a parameter to reduce an error. The three real update rules (L8–L10) are textbook algorithms from 1982–1999, correctly implemented at toy scale, and disconnected from MSC.

## Q3 — LLM and conventional-ML dependence (detail)

| Module | What it calls | How | Wired into main path? | Keys/hosts |
|---|---|---|---|---|
| runtime/llm.nova:77-144, 201-253 | `libnovabridge.so` → llama.cpp (`nova_load_model`, `nova_generate`…) | `ffi_open("libnovabridge.so")` then `"./libnovabridge.so"`; local GGUF file path | No. Zero callers in src/tests/examples. `.so` not built by Makefile | none; no network |
| runtime/llm_bridge.c | llama.h C API | would be `gcc -shared … -lllama` (comment :15) | Not built | none |
| agent/cognitive_llm.nova | nothing external | – | Only its own test | – |
| agent/rag.nova:522-543 | nothing external; builds a prompt string | TF-IDF tensors | No callers | – |
| runtime/embedding.nova | nothing external; "Tier 2 neural via Python bridge" exists only as a comment (:4) | BM25 + char trigrams | test only | – |
| runtime/python.nova:59-143, 145-154, 447-638 | libpython3 C-API; numpy via `py_exec("import numpy …")` | dlopen through `--link-libc` FFI | No callers | none; `py_exec` executes arbitrary strings |
| runtime/blas.nova:11-36 | `cblas_dgemm` from libopenblas/libblas | dlopen | Optional hook in tensor_matmul; no caller enables it | – |
| runtime/gpu.nova | libcuda / libOpenCL | dlopen | No callers | – |
| runtime/http.nova | raw TCP sockets, plain HTTP | syscalls | No callers | none hard-coded |

No `getenv`, no API key, no hostname, no `curl`/`python` shell-out anywhere in the assigned directories (grep for `getenv|sk-|api.openai|anthropic|ollama|curl` in src/core, mind, agent, cognitive, runtime: no hits). "Embedding" is never a learned embedding: it is either hand-typed integer lists (embed.nova), hashed bag-of-words (cognitive_llm.nova:292-321) or TF-IDF/BM25 (embedding.nova, rag.nova). CONFIRMED.

## Q6 — Runtime notes

- **Shell-outs / sockets**: `taskpool.nova` forks (fork/pipe builtins); `ffi_syscall.nova:466-560` defines socket/connect/bind/listen/accept wrappers; `http.nova` uses them. Nothing executes external programs. `examples/tcp_echo_server.nova` listens on :8080.
- **Allocators**: `alloc.nova` (mmap arena) and `persistent_alloc.nova` (file-backed mmap) both fail at HEAD (M23). `node_pool.nova` works (test passes). `runtime/list.nova` and `runtime/map.nova` are raw-memory reimplementations superseded by compiler builtins (LIKELY dead).
- **Scheduler name clash**: `runtime/coroutine.nova` defines `scheduler_new/spawn/tick/run_all` (a coroutine scheduler) alongside the MSC `runtime/scheduler.nova` `scheduler_*` functions; different names today, but one typo from a silent collision since everything is concatenated into one namespace.
- **Compiler coupling**: the `mind`, `soul`, `system` declarations are lowered by the compiler into calls to `node_new`, `scheduler_register`, `channel_direct`, `soul_new`, `system_new` (src/compiler/codegen.nova:10256-10585). So `core/node, channel, soul, system` + `runtime/scheduler` are load-bearing for language syntax, not merely a library.

## Q8 — Complexity

Let Q = queue length, N = registered nodes, C = channels, D = dests per channel, T = trace length, E = stored episodes/entities, d = embedding dims.

- One scheduler dispatch: pop O(Q) (array shift) + node lookup O(N) string compares + visited check O(T) + per output: scan all channels O(C), per destination copy trace O(T) and sorted insert O(Q) (rebuilds the whole list, signal.nova:326-357) ⇒ **O(Q + N + C + outputs·D·(T+Q))**. A broadcast to all N nodes is O(N·Q). Draining Q signals is O(Q²) minimum.
- Rememberer recall per signal: score O(E) + exchange sort **O(E²)** (node.nova:337-349); `memory_recall_similar` same (memory.nova:232-250). Memory grows by one episode per signal ⇒ processing S signals costs O(S³) total.
- `kg_nearest`: O(E·d) cosine + **O(E²)** sort (knowledge.nova: kg_nearest). `kg` entity/relation lookups are linear scans by name.
- Knower BFS: O(depth · frontier · degree · |visited|) with list-based visited.
- `db`: O(n) per get/put; O(n) full rewrite per save.
- Memory: every `signal_redirect`/`signal_elevate` allocates a new 8-slot list and a new trace; there is no free in the list/map builtins visible from this layer, so long runs grow without bound (LIKELY; not measured).

None of this matters at demo scale (tens of items); all of it prevents the "1M+ nodes" scale mentioned in CE/nova-deps.toml.

## Executed (summary)

- Full test runner (private temp dir): Total 194, Passed 157, Failed 30, Skipped 7.
- Re-ran 10 failing tests with corrected dependency lists → all pass (M1). test_tensor/embedding/cognitive_llm/associative under `--link-libc` + gcc with ffi.nova → segfault (so the libc FFI path is separately broken).
- Built and drove the agent with scripted stdin (three transcripts quoted in M8/M9).
- Ran all 66 `.nova` examples; re-ran 20 with modules concatenated.
- Probes: float_cmp, db round-trip, split/str_find, random, imagination, synapse/flow/parts/reader smoke.

## Not verified

- llm.nova, llm_bridge.c, python.nova, blas.nova, gpu.nova: cannot be executed here (no llama.cpp / libpython / OpenBLAS / CUDA wiring; no build rule). Status from reading only.
- Root causes of M2, M3, M14, M15, M23 lie in compiler builtins/codegen (outside this assignment); I confirmed the symptoms, not the cause.
- Why 10 of the concatenated demos segfault (M12): one case traced to API drift; my own probes showed that `println(f())` where `f` prints and returns nothing segfaults, and several demos use `*_describe` that way — LIKELY the common cause, not checked per demo.
- float_demo, stream_demo, security_demo, showcase outputs were not checked value by value.
