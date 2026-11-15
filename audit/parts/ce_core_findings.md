# ce_core findings — MSC substrate, parts, KG, mind, learning, seed

Scope: `CE/src/{substrate,parts,gates,scheduler,kg,mind,learning,seed,sim,preference,perception}` (144 files, 41,567 LOC) plus the claim docs `CE/docs/adr/0100-moment-signal-cognition.md`, `CE/docs/HOW_IT_LEARNS.md`, `CE/docs/END_TO_END.md`. To trace the live path I also read the relevant parts of `CE/examples/crossengin_chat.nova` and `CE/src/agent/cognitive_router.nova`.

Labels: CONFIRMED = read in code or executed; LIKELY; SUSPECTED.

## Plain-language summary

- There are two different things called "MSC" in this repo. ADR-0100 defines it as *atoms with a Beta belief, updated by source-tagged observations* (a knowledge graph with counters). The older ADRs and `src/substrate` define it as *a fabric of spiking nodes, synapses and 18 signal types*. Both exist in code. Only the first one produces answers.
- What answers a chat message is ordinary procedural code: a keyword/substring intent classifier picks one of 9 handlers; the handler walks hand-seeded "operator" edges (premise atom -> conclusion atom) with a greedy depth-3 search and fills a sentence template ("X leads to Y (chain)").
- The spiking substrate is real, correct at unit-test level, and runs on the live path, but it is inert: 8 parts x 128 slots with 8 nodes each (64 nodes total), no synapses between those nodes, one tick per user message. Nothing reads its state to decide anything. The "~6M node / 1M nodes per part" figure is a design target in ADRs, never instantiated.
- The 18 signal types differ operationally only by a routing-table row and a priority number. The priority queue, the inhibit sign and the per-synapse type mask have no callers outside unit tests. In chat, three types are ever emitted (SENSORY, CURIOSITY, GOAL) and CURIOSITY has no route.
- The "synapse graph" used in chat is a small weight table keyed by *atom ids* (10 entries in the smoke test). `/good` adds +100 to the weights of the edges just used; `/bad` subtracts 100. The Hebbian/STDP/three-factor rules never change these weights on the live path.
- It does learn, in three modest senses: (1) it stores new words/facts (from the user, or from fetched text via hand-written "X is a Y" patterns); (2) `/good`/`/bad` move Beta counters and edge weights, which can change which hand-seeded chain is chosen (I observed this after 6x `/bad`); (3) a reply cache returns the previous answer for a repeated input.
- No test or benchmark in these directories shows a capability improving with experience (accuracy, generalisation, latency). The "frequency-adaptive latency" claim in HOW_IT_LEARNS.md has no latency measurement behind it; the only latency counter is always 0.
- "Forward-Forward" is a genuine, simplified single 8x8 layer with weights and positive/negative passes; its unit test separates 2 toy patterns from 2 others. On the live path its output is only printed (`ff_goodness=`); nothing uses it.
- "Predictive coding" on the live path is one exponential moving average of a single number ("arousal"). "Federated learning" shares two noised rates per source; no model is federated.
- The five CI smoke numbers are deterministic counters. They prove the code path did not regress; they do not measure learning quality. I reproduced all five exactly.
- Solid, honest pieces: Beta belief bookkeeping with provenance, a small LCF-style proof checker (`mind/verify.nova`), textbook HDC ops, textbook graph algorithms (PageRank, Louvain, LPA, Adamic-Adar), a mini-Datalog and a SPARQL-like query parser. All 32 unit tests I ran pass and assert real behaviour.
- No LLM, neural library or Python call exists inside these directories. Adjacent code does have an optional Ollama "reply composer" and `scripts/llm_*.sh`; https fetching is delegated to `scripts/learn.sh` (curl).
- Two real security defects: the secure-aggregation DH private key has at most 15 bits of entropy, and the DNS client uses a fixed transaction id it never checks.
- All demo knowledge is hand-written: ~570 seed words and 43 seed operators, including the exact `fever` chain the CI smoke test exercises.

## Findings table

| ID | Sev | Category | Title | file:line | Evidence | Impact | Fix | Effort | Conf |
|---|---|---|---|---|---|---|---|---|---|
| C1 | Critical | Overstated function | Spiking "fabric" does not compute answers | CE/examples/crossengin_chat.nova:151-152, 7725-7726, 8048, 8070, 8204-8209; CE/src/agent/cognitive_router.nova:155-225, 785-796 | Pools are `CE_CAP=128`, `CE_FIRST=8`. Per message: one `hs_step` tick, inject 700 into perception first nodes, then `router_reply(...)` builds the reply from KG operators. No code reads node activation/fires to choose a reply. | Core architectural claim ("fabric of uniform units") is not what produces behaviour | State plainly in README/ADR-0001 that the substrate is experimental and off the answer path; or wire it in and measure | L | CONFIRMED |
| C2 | Critical | Overstated function | "6M-node fabric" is a design constant, not an instance | CE/docs/adr/0003-scaling-plan.md:21,25; CE/docs/adr/r36f-0001-language-choice-nova.md:8; CE/examples/crossengin_chat.nova:151 | Only instantiations: chat/daemon 8 parts x 128 slots; `kernel_selfcheck`. My probe: 420k node-ticks took 0.71 s and 405 MB peak RSS | Scale claims unsupported; current kernel would need ~10 s and GBs of garbage per 6M-node tick | Remove scale claims until measured | S | CONFIRMED (measurement), LIKELY (extrapolation) |
| C3 | High | Overstated function | Hebbian / three-factor plasticity is a no-op on the live path | CE/src/substrate/tick_driver.nova:54-63, 96, 251; CE/src/substrate/synapse_graph.nova:257-270; CE/src/agent/cognitive_router.nova:213 | Live synapses are keyed by atom id (e.g. 534, 463); `snapshot` has 128 entries, so `pre_act=post_act=0` and `dw=0`. Three-factor flag defaults 0 and `td_enable_three_factor` has no caller. Observed weights are exact multiples of 100 | HOW_IT_LEARNS.md table ("Hebbian plasticity: yes", "tick-driver fires three-factor plasticity") is wrong | Fix the doc; rename to "feedback-weighted edges" | S | CONFIRMED |
| C4 | High | Overstated function | Signal taxonomy is mostly decorative | CE/src/substrate/signal_dispatch.nova:99-119, 180-230; CE/src/substrate/first_nodes.nova:58-87; CE/examples/crossengin_chat.nova:845-853 | `sigq_*`, `sig_inbox_delta`, `syn_carries`, `syn_mask_add` have zero callers outside their module/tests. `_route_and_inject` builds a signal only to look up destinations, then injects a bare integer. CURIOSITY has no seeded route so its injection goes nowhere | "18-signal dispatch" is not exercised | Document; delete or wire | M | CONFIRMED |
| C5 | High | Tests / CI | CI "learning invariants" are deterministic counters | CE/.github/workflows/build-and-smoke.yml:78-83 | See "CI numbers" section. Reproduced exactly | CI passing says nothing about learning quality; risks being read as evidence of learning | Keep as regression test, rename; add a before/after task metric | M | CONFIRMED |
| C6 | High | Overstated function | Reply cache presented as cognition speed-up | CE/src/parts/episodic/moment_cache.nova:68-93; CE/examples/crossengin_chat.nova:8199-8230; CE/docs/HOW_IT_LEARNS.md ("Why this isn't just a database") | 9 of 10 smoke replies are the stored string from turn 1. Key = bundle of HDC vectors of *known atoms in the percept*, so word order and unknown words are ignored: "fever", "is fever", "fever is" share one entry (observed hit). No invalidation call exists (`mc_` has only new/lookup/store) | "Gets faster on hot queries" is memoisation; cache can return an answer to a different question | Key on full normalised utterance + KG watermark; describe as a cache | S | CONFIRMED |
| C7 | High | Security | SecAgg DH private key has <=15 bits of entropy | CE/src/learning/secure_aggregation.nova:498-520, 640-660, 256-258 | `mixed = and(xor(lo,hi), 32767)` seeds a 15-bit LCG that generates all key limbs, for both the 256-bit and RFC 7919 2048-bit modes. Masks are also 15-bit LCG outputs | Any observer can brute-force 32,767 seeds and recover every mask; "secure aggregation" gives no confidentiality | Use `/dev/urandom` (getrandom syscall) and a real KDF | M | CONFIRMED (code read) |
| C8 | High | Security | DNS resolver is spoofable and unbounded | CE/src/learning/dns_resolver.nova:30, 108-130, 200-217 | Fixed id `0x1234`; `_dns_parse_answer` receives `query_id` but never compares it; no source-port randomisation; `alloc(512)` with no host length check; no 63-byte label check | Off-path spoofing of fetch targets (and fetched text becomes "knowledge"); buffer overrun on long host | Random id + verify, bound host <= 253 | S | CONFIRMED (code read) |
| C9 | Medium | Overstated function | Forward-Forward output is display-only | CE/examples/crossengin_chat.nova:3363-3368, 7360-7366, 7848; CE/src/learning/forward_forward.nova:132-162 | `ff_goodness` is called only in `_admin_learning`. Negative example on `/good` is the zero vector, for which every `post=0`, so the negative pass does nothing. Input is an 8-bucket histogram of `atom_id % 8` | Named as a learning layer on the live path; has no behavioural effect | Either use it (e.g. gate the cache) or label it experimental | S | CONFIRMED |
| C10 | Medium | Overstated function | Live "predictive coding" is one scalar EMA with no consumer | CE/examples/crossengin_chat.nova:8088-8094; CE/src/learning/predictive_coding_runtime.nova:171-178 | `pc_pred_learn(_pc_pred, 0, 0, aro, 300)`; `error` is passed into the tick where it multiplies `pre_act=0` | No effect on behaviour | Document | S | CONFIRMED |
| C11 | Medium | Overstated function | Chain compiler cannot shorten anything | CE/src/kg/chain_compiler.nova:64-109; CE/src/agent/cognitive_router.nova:229-246 | It adds a direct A->C operator, but `_cr_best_chain` prefers the *longest* chain; `kgr` latency is `hs_now - hs_now` = 0 always (CE/examples/crossengin_chat.nova:8233-8236; END_TO_END.md shows `mean_lat_ticks=0`) | "Short-circuit" claim has no observable effect; adds derived edges without provenance moment (`moment=0`) | Measure or remove | S | CONFIRMED (code), LIKELY (no effect) |
| C12 | Medium | Correctness | Atom ids and node ids share one synapse graph | CE/examples/crossengin_chat.nova:7734-7740; CE/src/substrate/tick_driver.nova:78-93 | Reasoning part's graph holds atom-id edges; the tick driver interprets `pre/post` as pool node ids. Atoms with id < 128 alias real pool slots (first nodes 0..7 fire after each reply via GOAL=800) | Latent cross-talk: a fired first node can deliver "spikes" along an edge that means "atom 4 -> atom 3" | Give the router its own table | S | LIKELY |
| C13 | Medium | Correctness | Answer for a word can drop the word | CE/src/agent/cognitive_router.nova:229-246 | After 6x `/bad`, input `fever` returned "doctor leads to recover (doctor->prescription->medicine->recover)" (my run). Longest-chain-from-any-percept-seed wins | Replies can be unrelated to the query | Require the query atom in the chain | S | CONFIRMED (run) |
| C14 | Medium | Hard-coded demo data | The smoke-test answer is a hand-written seed chain | CE/src/seed/first_atoms.nova:328-333 | `virus->infection`, `infection->symptom`, `symptom->fever`, `fever->infection`, `fever->headache` typed in by hand; reply "infection leads to headache" is that chain rendered through a template | Demo shows retrieval of authored data, not inference from learned knowledge | Say so in the demo doc | S | CONFIRMED |
| C15 | Medium | Scale | HDC vectors are 10,000 boxed 64-bit ints each | CE/src/kg/hdc_embed.nova:51, 88-102, 137; CE/src/parts/episodic/moment_cache.nova:38, 68-81 | >=80 KB per vector; symbol cache cap 8192 (~650 MB); moment cache 1024 entries scanned linearly with a 10k-dim cosine each (up to ~10M multiply-adds per message) | Memory/time blow-up beyond toy sizes | Bit-pack (1 bit/dim), popcount | M | CONFIRMED (code), LIKELY (sizes) |
| C16 | Medium | Scale | Node kernel allocates on every field read | CE/src/substrate/node_pool_manager.nova:109-123; NOVA/src/runtime/node_pool.nova:91-102 | `npm_get` -> `pool_get_values` builds a fresh list per call; tick calls it ~3x per slot including unused slots. 405 MB peak for 420k node-ticks | Substrate cannot scale as written | Read words in place | M | CONFIRMED |
| C17 | Medium | Overstated function | "Federated learning" federates two scalars per source | CE/src/learning/federated_aggregator.nova:568-600 | Blend `(local*9 + global)/10` then bump a host's trust tier if >=700 or <=300 | Name suggests model training | Rename "federated source-reputation" | S | CONFIRMED |
| C18 | Low | Docs | ADR-0100 points to wrong file for moments | CE/docs/adr/0100-moment-signal-cognition.md ("`src/kg/temporal.nova`, `ms_new()`") | `ms_new` is in CE/src/parts/episodic/moment_stream.nova:108; temporal.nova is Allen interval algebra. "A subsequent moment can reactivate a prior moment's cluster by label match" has no implementation I could find in moment_stream | Contract doc inaccurate | Fix | S | CONFIRMED |
| C19 | Low | Docs | Stale "Status: Pending" READMEs | CE/src/{gates,kg,learning,parts/*}/README.md:7 | Code exists for all of them | Confusing | Update | S | CONFIRMED |
| C20 | Low | Dead code | 25 files reachable only from unit tests | see coverage file ("Dead (tests only)") | Entire `parts/action` (1,886 LOC), `atom_birth_monitor`, `bayesian_updates`, `confidence_thresholds`, `learning_policy`, `self_improve`, `sim/world_model`, `theory_of_mind`, `planner`, 3 imagination files, `resonance_engine`, `unify`, `search_uni`, `schemas` | 4,370 LOC presented as features but not wired | Mark experimental | S | CONFIRMED (import graph) |
| C21 | Low | Overstated naming | `learning_policy.nova` enforces nothing | CE/src/learning/learning_policy.nova:67-88 | A literal table says "forward-forward: PERMITTED", "llm-cognition: FORBIDDEN"; not imported by any entry point | Policy-as-comment | Remove or enforce | S | CONFIRMED |
| C22 | Low | Overstated naming | `semantic_search` is TF-IDF; `proof_checker` is BFS path search; `soul` is a config record | CE/src/kg/semantic_search.nova; CE/src/parts/reasoning/proof_checker.nova; CE/src/parts/soul/identity.nova | see coverage | Names overstate | Rename | S | CONFIRMED |
| C23 | Low | Correctness | Intent-prototype "bundle" degenerates | CE/src/nl/intent_adaptive.nova:103-116 (adjacent) | Re-binarises after each 2-way majority with ties -> +1; "strength" is just a `/good` count | `ia_proto_strength` is a counter | Keep integer accumulators | S | CONFIRMED |
| C24 | Info | Inventory | TODO/FIXME/HACK/XXX count = 1 | CE/src/learning/secure_aggregation.nova:709 | grep over all 11 dirs | — | — | — | CONFIRMED |
| C25 | Info | Inventory | `.pending` files: none in CE | `find CE -name '*.pending*'` -> 0 | — | — | — | — | CONFIRMED |

## The CI numbers — what each really measures

Reproduced with a fresh build of `examples/crossengin_chat.nova` (10x `fever` + `/good`, then `/__learning__`): `mc_hits=9 mc_misses=1 ff_goodness=486000 synapse_mean_weight=300 ia_proto_strength_unknown=10 tick=10`. Per-turn series: mean weight 30,60,...,300; ff_goodness 37882, 386558, 486000, 486000, ... (constant from turn 3).

| Counter | Produced at | What it is |
|---|---|---|
| `mc_hits=9`, `mc_misses=1` | CE/src/parts/episodic/moment_cache.nova:83,91; printed CE/examples/crossengin_chat.nova:3373-3375 | Number of times the reply cache returned a stored string. Turn 1 computes; turns 2-10 replay. |
| `synapse_mean_weight=300` | CE/src/agent/cognitive_router.nova:810-836 (`cur + sign*100`); mean at CE/examples/crossengin_chat.nova:3343-3356 | 10 edges were created at weight 0 by the first chain search (cognitive_router.nova:213). The reply used 3 operators; each `/good` adds 100 to those 3 edges, clamped at 1000. (3 x 1000 + 7 x 0)/10 = 300. It counts `/good` presses. |
| `ff_goodness=486000` | CE/src/learning/forward_forward.nova:110-120, 132-156; chat:3365, 7363 | Sum over 8 ReLU units of (w.x)^2 on an 8-bucket histogram of percept atom ids. Each `/good` multiplies active weights by about 1.3 until they hit the +/-1000 clamp (turn 3). 486000 is the clamp-saturated value for this fixed input and seed 42. Printed only. |
| `ia_proto_strength_unknown=10` | CE/src/nl/intent_adaptive.nova:114; chat:7376, 3379-3384 | Count of `/good` presses while the keyword classifier's category was "unknown" (the classifier does not recognise bare "fever"). |
| `tick=10` | CE/src/substrate/tick_driver.nova:263-267 | One substrate tick per message. |

## MSC as implemented in CrossEngin (precise definition)

All quantities are 64-bit integers in milli fixed-point (`FP_SCALE=1000`, `fp_mul(a,b)=a*b/1000`, truncating) — CE/src/substrate/node_pool_manager.nova:33-37. No floats.

### A. Substrate layer (implemented, unit-tested, inert on live path)

**Node** (node_pool_manager.nova:45-53): 8 integers `[activation, threshold, bias, last_fired, novelty, ntype, inbox, fires]`. `ntype` (6 values) is never read by the kernel.

Node update per tick (node_pool_manager.nova:155-185):
```
a'  = clamp(0.9*a + inbox + bias, 0, 4.0)
nov = 0.85*nov
if a' >= threshold (default 0.5): fired=1; last_fired=t; fires+=1; nov=min(1, nov+0.2); a'=0
inbox = 0
```
This is a discrete leaky integrate-and-fire neuron with hard reset.

**Synapse** (synapse_graph.nova:36-57): parallel lists `pre, post, w in [-1000,1000], elig in [0,1000], last, mask, alive`; adjacency list indexed by `pre`. Weights are integers.

**Tick** (tick_driver.nova:48-99), per part, O(capacity + fired*out_degree + synapses):
```
snap[i] = a_i (before integrate)
F = { i : integrate(i) fired }
for i in F, for s in out(i): inbox[post(s)] += w_s * 1.0
for every live synapse s:                      # "plasticity step"
    dw = mod * (0.02*snap[pre]*snap[post] + 0.03*snap[pre]*err)
    w_s = clamp(w_s + dw);  elig_s += snap[pre]*snap[post] (if both > 0)
elig_s *= 0.9
```
Optional three-factor pass (OFF: tick_driver.nova:251, 298-301):
```
K(dt) = A*(20-|dt|)/20 for |dt|<20, A=1.0 if dt>=0 else 0.25   # triangular STDP window
elig_s += K(last_fired[post] - last_fired[pre])
nm = clamp(reward * (1 + surprise/2 + |pred_err|/2), -1, 1)
w_s += 0.04 * nm * elig_s
```
**Signal** (signal_dispatch.nova:14-21): list `[type 1..18, priority 0..9, src, dst, strength, trace, meta]`. Operational differences between types: a fixed priority lookup (lines 99-119), INHIBIT negates in `sig_inbox_delta` (unused), CONST broadcasts in `gate_route`, and one routing-table row per type.

**Gate** (gate_router.nova:120-136): `dests(type) = { part : W[type][part] > 0.1 }`, seeded at 0.7 from a static table (first_nodes.nova:58-87). "Learning" = `W += delta`, `W *= rate`, drop if <= 0.03 — never called live.

**Resonance** (resonance_engine.nova:69-93): for reciprocal pairs with both snapshot activations >= 0.4, `w_ab += 0.05; w_ba += 0.05`. Tests only.

**Part**: `{name, preset, pool, synapse graph, first-node ids}`. Live: 7 fixed + "kg-world", each 128 slots / 8 nodes.

**Moment** (moment_stream.nova:37-61): record `{id, ts, modality, raw text, salience, origin, trace ids, status}` appended per message.

**Attribution**: atom provenance ledger `[tier, part, license, grade, ts, proof_ref]` (atom_store.nova:223-230) plus `src:` prefixes in labels, plus per-source counters in meta_observer.

### B. Knowledge layer (this is what computes answers)

**Atom** (atom_store.nova:202-215): `[id, kg, kind, label, payload k/v list, belief (alpha,beta), embed, xrefs, provenance, created, updated, version]`.

**Belief** (atom_store.nova:53-113) — Beta-Bernoulli pseudo-counts:
```
conf = alpha/(alpha+beta)                      prior alpha=beta=1
observe(+): alpha += g ; observe(-): beta += g     g=1, or 0.25..1.0 by evidence grade
FORMAL: alpha=999, beta=1 (pinned)
decay:  alpha = 1 + r*(alpha-1), beta = 1 + r*(beta-1)     r=0.99 every 64 ticks
```
**Operator** (parts/reasoning/reasoning_atoms.nova:46-57): a RELATION atom with payload `{op in {causal, imply, analogy, evidence, opposite}, premise id, conclusion id}`, indexed by adjacency on premise/conclusion.

**Answer rule** (cognitive_router.nova:155-246): greedy path, depth <= 3, from each percept atom; keep the longest:
```
score(op) = conf(op) * src_weight(label substring) * (1 + w_syn(cur, concl))     # last factor only if an edge exists
next = argmax_op score, over causal/imply ops to unvisited conclusions
reply = "<head> leads to <tail> (<a->b->c>)."  hedged by min conf along chain
```
**Feedback** (cognitive_router.nova:810-845): for each operator used, `alpha or beta += 1` and `w_syn += sign*0.1` (clamped +/-1).

**HDC** (kg/hdc_embed.nova): D=10,000 bipolar; `symbol(label)` = LCG stream seeded by FNV-1a(label); bind = elementwise product; bundle = sign of sum (ties -> +1); permute = cyclic shift; cosine = dot/(isqrt*isqrt) in milli. Faithful textbook VSA. Legacy embedding is 8-dim.

**Forward-Forward** (learning/forward_forward.nova): `y_u = relu(sum_i W_ui x_i)`, `G = sum_u y_u^2`, `dW_ui = +/- lr * y_u * x_i`, clamp. Missing versus Hinton 2022: the logistic loss factor `(1 - sigmoid(G - theta))`, layer normalisation in the update path, multiple layers, label embedding. Sign-only Hebbian/anti-Hebbian variant.

**Predictive coding**: `e = (actual - predicted) * precision`; predictor `p += lr*(actual - p)` (predictive_coding_runtime.nova:39-41, 171-178). No hierarchy, no generative model.

**Consolidation** (kg/episodic.nova:389-428): group recent moments by sorted set of atom ids; if a set recurs >= threshold, mint/refresh an "episodic atom" with its own Beta counts.

**Atom birth**: gated monitor (freq >= 5, >= 3 moments, cosine < 0.9) exists but is test-only (learning/atom_birth_monitor.nova:107-124). Live birth = any unknown token becomes a word atom ("learned N new word(s)").
**Atom death**: two-phase tombstone sweep (atom_death_monitor.nova); the periodic GC is not enabled in chat (crossengin_chat.nova:7809-7810, `maint_new(0, 64, 990)` with no `maint_enable_gc`).

**EMA pulls**: federated blend `(9*local + global)/10`; predictor EMA; eligibility decay 0.9; belief decay above.

## What decides an answer (trace)

Input `fever` (CE/examples/crossengin_chat.nova):
1. 8022-8026: slash commands (`_try_admin`), then a grammar front end (`_try_nl`), else cognition path.
2. 8048: one `hs_step` -> one substrate tick over 8 parts (no effect on reply).
3. 8052-8058: reader maps tokens to atoms via label hash lookup -> `percept` list of `[form, atom_id]`.
4. 8070: inject 700 into perception first nodes (they fire next tick into no synapses).
5. 8175: `classify_input` — keyword/substring scoring (CE/src/perception/input_classifier.nova:261-400) -> category "unknown" for a bare word.
6. 8201-8209: reply cache lookup; on hit, return stored string.
7. 8210: `router_reply` -> `_cr_unknown` -> `_cr_best_chain` -> template string.
8. 8245: governed speak (substring veto list from the "constitution").

Asserting then querying a fact (my run): `/teach zorb` creates an atom; `/correct zorb causes fever` creates one operator atom `zorb -> fever`; `zorb` then answers "zorb leads to treat (zorb->fever->infection->treat)". Deciding data structures: label hash bucket -> atom id -> premise adjacency list -> operator atoms' Beta means -> string template. A plain declarative sentence ("cats are mammals") is *not* stored: reply was "noted -- 'cats' is new to me. teach me with /learn so it sticks." and "what is a cat" then returned "(no matches across 4 scanned KGs)".

## Learning mechanisms

| Mechanism | Update | file:line | On live path? | Class | Evidence it improves anything |
|---|---|---|---|---|---|
| New word/atom minting | create atom for unknown token | chat `_drain_and_teach` (crossengin_chat.nova:2992) | Yes | Fact storage | Vocabulary grows; no quality metric |
| `/teach`, `/correct`, `/learn` text ingest | create atoms + operator per extracted triple | CE/src/learning/learn_pipeline.nova:188-240; CE/src/learning/preprocess.nova:746-824 | Yes | Fact storage via 5 hand-written patterns / rule-based SVO | New facts become answerable (observed with `/correct`) |
| Beta belief observe | alpha or beta += g | CE/src/kg/atom_store.nova:70-90, 521-527 | Yes | Bayesian counter | Changes hedging phrase and edge ranking |
| `/good` `/bad` edge weight | w += +/-0.1 | CE/src/agent/cognitive_router.nova:821-829 | Yes | Counter (called Hebbian) | `/bad` x6 changed chosen chain (observed); no accuracy test |
| Belief decay | pull to prior, r=0.99 / 64 ticks | CE/src/learning/belief_decay.nova:49-75 | Yes | Forgetting | none |
| Reply cache | store reply by percept key | CE/src/parts/episodic/moment_cache.nova | Yes | Memoisation | fewer router calls; no timing |
| Intent prototype | bundle utterance; count++ | CE/src/nl/intent_adaptive.nova:103-116 | Yes | Counter + HDC prototype | none shown |
| Chain compiler | add A->C op if both legs w >= 0.5 | CE/src/kg/chain_compiler.nova:64-109 | Yes | Rule caching | none (see C11) |
| Episodic consolidation | mint atom for recurring id-set | CE/src/kg/episodic.nova:389-428; CE/src/agent/loop_memory.nova:76-82 | Yes | Frequency counting | not used for answers |
| Reflection promotion | tentative atom promoted when re-perceived | CE/src/parts/meta/reflection_loop.nova | Yes | Fact storage | none |
| Source tier feedback | host tier +/-1 from promotion rates | CE/src/parts/meta/meta_observer.nova:480 | Yes (idle) | Counter thresholds | none |
| Forward-Forward | dW = +/- lr*y*x | CE/src/learning/forward_forward.nova:132-162 | Runs, output unused | Simplified FF (real weights, pos/neg passes) | Unit test separates 2+2 toy vectors |
| Predictive coding | p += 0.3(a-p) | CE/src/learning/predictive_coding_runtime.nova:171-178 | Runs, output unused | EMA | none |
| Tick Hebbian | dw = mod*(0.02 pre*post + 0.03 pre*err) | CE/src/substrate/synapse_graph.nova:226-240 | Runs, always dw=0 | Hebbian (inert) | unit tests only |
| STDP three-factor | see above | CE/src/substrate/synapse_graph.nova:304-380 | No (flag off) | Three-factor Hebbian | unit tests only |
| Resonance, gate learning | +0.05 / +delta | resonance_engine.nova:69-93; gate_router.nova:153-212 | No | Hebbian-like | unit tests only |
| Atom birth monitor | threshold gates | CE/src/learning/atom_birth_monitor.nova | No | Counter | unit tests only |
| Q-learning self-improve | Q(s,a) = r + 0.9 max Q(s') | CE/src/parts/meta/self_improve.nova:74-78 | No | Tabular RL on gridworld | Unit test shows return rising on the toy grid — the only before/after improvement test found |
| Federated | blend 90/10 | CE/src/learning/federated_aggregator.nova:568-600 | Separate daemon | Averaging | none |
| Gradient-based | — | — | — | None present | — |

## Prior-art mapping

| CrossEngin mechanism | Known technique | Fidelity |
|---|---|---|
| Node kernel | Leaky integrate-and-fire neuron | Faithful, simplified (discrete, no refractory period beyond reset) |
| Tick propagation | Spiking network / spreading activation | Faithful mechanics; not used for cognition |
| Synapse rules | Hebb rule, delta rule, STDP with eligibility traces, reward-modulated (three-factor) plasticity | Simplified but recognisable; test-only in effect |
| Resonance | Cell-assembly reinforcement | Name-level simplification |
| Parts + gates + signals | Blackboard / global-workspace style module routing; ACT-R/Soar-like module split | Name-only on the live path (static table) |
| Atoms + operators | Semantic network / property graph | Faithful, small |
| Belief (alpha,beta) | Beta-Bernoulli conjugate updating (as in subjective logic, Thompson-sampling bookkeeping) | Faithful |
| `_cr_chain`, `reason_forward_chain` | Greedy best-first / BFS over a rule graph; forward chaining in production systems | Simplified (single-premise rules only) |
| `rule_inference.nova` | Datalog naive evaluation | Simplified, real |
| `query.nova` | SPARQL-like triple-pattern queries | Subset, real |
| `mind/verify.nova` + search | LCF-style proof kernel, natural deduction, resolution-free search, Robinson unification | Small but faithful |
| `argumentation.nova` | Dung abstract argumentation (grounded/preferred) | Faithful for small n |
| `hdc_embed.nova` | Hyperdimensional computing / VSA (Kanerva, MAP architecture) | Faithful; inefficient storage |
| `ann_index.nova` | Random-hyperplane LSH (SimHash) | Single table, faithful |
| `semantic_search.nova` | TF-IDF vector-space retrieval | Faithful |
| pagerank / louvain / LPA / link_prediction | Named algorithms | Faithful |
| `temporal.nova` | Allen interval algebra | Relations only |
| `forward_forward.nova` | Hinton's Forward-Forward | Simplified one-layer variant; display-only live |
| `predictive_coding_runtime.nova` | Predictive coding | Name-level (EMA + residual) |
| Consolidation | Frequent-itemset counting | Simplified |
| `self_improve.nova` | Tabular Q-learning / value iteration | Faithful on a toy |
| Federated + DP + SecAgg + Byzantine | FedAvg-style averaging, Laplace mechanism, pairwise-mask SecAgg, trimmed mean/median | Structure faithful; data is 2 scalars; crypto unsound (C7) |
| Emotion / OCEAN | OCC appraisal labels, Big-Five traits | Arithmetic on a few integers |
| Input classifier | Keyword rule-based intent detection | Faithful to that technique |
| OpenIE / preprocess | Pattern-based information extraction | Simplified |

## Stubs, constants, hard-coded knowledge

- No `.pending` files in CE (C25). "Pending" appears only in stale READMEs.
- Hard-coded seed: CE/src/seed/first_atoms.nova:120-300 vocabulary lists; :310-324 15 xrefs; :328-380 43 operators; :383-406 imagination patterns; :415-420 six output templates. Four packs in CE/src/seed/packs/ are likewise hand-typed word lists + operators.
- Placeholder data: `seed_patterns` mints `seed_i: {i} -> {100+i}` (CE/src/parts/imagination/imagination_engine.nova:101-109); operand_builder placeholders (CE/src/parts/action/operand_builder.nova:21-22); action HTTP pinned to `simulated=1` with canned body (CE/src/parts/action/action_module.nova:493-496).
- Constants standing in for computation: `kg_router` kg label is always "reasoning" (CE/src/kg/kg_router.nova header + chat:8234); latency always 0; source weights by URL substring (cognitive_router.nova:120-128); `learning_policy` table.
- Honest-scope notes found in code headers (credit to the author): federated_aggregator.nova:17-28 ("FRAMEWORK + AUDIT, not production"), secure_aggregation.nova:22-25, internet_fetch.nova:10-14, mind/verify.nova:16-17, promotion.nova:6-9.

## Randomness and canned outputs

- No random numbers are presented as measurements in these directories. Uses of randomness: seeded LCGs for FF init, HDC vectors, LSH planes, label-propagation order, Q-learning exploration; `random()` in dream_recombination (dead); Laplace noise for DP.
- A metric that cannot move: `mean_lat_ticks` (always 0).
- Canned outputs: reply templates in the router; canned HTTP body slot in dead action code.

## Hidden ML / LLM dependence

- Inside these directories: none (grep for ollama/llm/curl/exec/python/whisper found only comments and a whitelist host). CONFIRMED.
- Adjacent, affecting these modules: optional Ollama reply composer whose output is stored in the moment cache (CE/examples/crossengin_chat.nova:8212-8224, gated by `CE_OLLAMA_COMPOSER=1`); `/ingest ... llm` format and `scripts/llm_extract.sh`, `llm_compose.sh`, `nl_parse_llm.sh`; ADR-0100 itself lists `src:extractor:llm:MODEL:RUN` as a signal source and references a "sidecar LLM". https fetch falls back to `scripts/learn.sh` (CE/src/learning/internet_fetch.nova:264-268). Other reviewers own those files.

## Complexity and scale limits

| Operation | Cost | Note |
|---|---|---|
| Substrate tick | O(parts x capacity) list allocations + O(synapses) | scans unused slots; ~1 KB garbage per node-tick measured |
| Label lookup | O(n/256) per lookup | 256 buckets, 15-bit hash (atom_store.nova:567-590) |
| Operators from atom | O(out-degree) | adjacency by id — fine |
| Atom payload get | O(keys) string compares | k/v list (atom_store.nova:467-476) |
| Chain search | O(seeds x 3 x degree) | fine |
| Moment cache lookup | O(entries x 10,000) | up to 1024 entries |
| HDC symbol | 10,000 LCG steps + 80 KB | cached, cap 8192 |
| Birth novelty check, belief decay, consolidation | O(atoms) linear scans | per sweep |
| Preferred extensions | O(2^n) | small n only |
| Memory | lists never shrink; per-call list allocation in hot loops | 405 MB peak in a 0.7 s substrate benchmark |

## Unit tests executed (all from `$S/CE`, `timeout 120 $S/NOVA/nova run tests/unit/<file>`)

All passed: node_pool_manager (40 checks), synapse_graph (55), tick_driver (38), signal_dispatch (55), gate_router (24), resonance_engine (20), atom_store (77), forward_forward (8), predictive_coding_runtime (30), hdc_embed (69), three_factor (18), self_improve (55), bayesian_updates (20), atom_birth_monitor (15), consolidation (10), federated_aggregator (91), secure_aggregation (170), verify (87), cognitive_router (55), learn_pipeline (21), ann_index (46), graph_clustering (71), louvain (72), pagerank (90), kg_query (62), rule_inference (47), semantic_search (73), link_prediction (77), episodic (79), preprocess (99), openie (64).

Quality: the harness (`CE/tests/ce_test.nova:82-88`) exits 1 on any failed check, and the tests I read assert specific computed values (e.g. tick_driver: "spike delivered to node 1 inbox == 900", "synapse potentiated within tick == 107"; forward_forward: positives score above negatives after training). They are genuine unit tests of each mechanism in isolation. None tests that the substrate influences an answer, and `moment_cache`, `chain_compiler`, `kg_router` and `intent_adaptive` — four of the five things CI asserts on — have no unit test at all.

## Not verified

- The exact percept list for "fever" (I did not print it); so the precise arithmetic behind 486000 is inferred from the code plus the observed series, not reconstructed term by term.
- Why the second `fever` after `/bad` missed the cache (the percept key must have changed; cause not traced into the reader, which is outside my scope).
- Daemon (`crossengin_daemon.nova`) behaviour beyond confirming it builds the same 8 x 128 substrate (line 77-78, 304-305) and does not call `router_reply`.
- Live network paths (DNS, fetch, federation) were read, not executed.
- "skimmed" files in the coverage table were judged from headers, function inventories, greps and their passing unit tests rather than line-by-line reading.
