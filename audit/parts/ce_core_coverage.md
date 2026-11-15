# ce_core coverage

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
