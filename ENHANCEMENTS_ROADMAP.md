# CrossEngin Enhancement Roadmap

> **Purpose.** A self-contained, execute-in-a-new-session plan to evolve
> CrossEngin from a symbolic substrate with weak language/representation layers
> into a moment-signal cognitive system with real (non-gradient) learning,
> rich ingestion, semantic representations, and agentic tooling.
>
> **Design invariant (do not violate).** No tokenization-as-LLM, no global
> backpropagation, no offline "training run." All learning is **local, online,
> gradient-free, auditable**, driven by the moment→signal→plasticity loop on the
> existing tick driver. Every new atom carries provenance + confidence.
>
> **Research lineage (read before building).**
> - Predictive coding: Rao & Ballard 1999; Friston free-energy; Millidge & Bogacz.
> - Three-factor / neuromodulated plasticity: Frémaux & Gerstner 2016.
> - Forward-Forward (gradient-free representation learning): Hinton 2022.
> - Hyperdimensional Computing / VSA: Kanerva 2009; Plate (HRR).
> - STDP (spike-timing): Bi & Poo 1998.

---

## Execution order (strict — each unlocks the next)

| Phase | Theme | Why first |
|---|---|---|
| **P1** | HDC/VSA embeddings (representation) | Keystone. Entity resolution, retrieval, reasoning, tool-selection all depend on meaning-bearing vectors. The current 8-dim lexical hash makes everything downstream brittle. |
| **P2** | Predictive coding + three-factor learning | Gives the substrate real credit assignment without backprop. |
| **P3** | Ingestion / formats / OpenIE | Fills the KG at scale (books, papers, tables, multimodal). |
| **P4** | Agentic tooling | Lets the agent act, then learn from outcomes. |
| **P5** | Simulation / self-improvement harness | Closes the autonomy loop. |

Do **not** reorder. Building ingestion (P3) on top of the weak embedding (P1
unfixed) wastes effort because entity resolution will fragment the KG.

> **ALL FIVE PHASES IMPLEMENTED + FOLLOW-UPS WIRED (2026-06-11).** P1–P5 each
> shipped behind a flag/new file (ADRs 0051–0055). A follow-up integration round
> (ADR-0056) then closed the tractable "Honest gaps": HDC cache eviction +
> re-embed + signed coherence; the three-factor pass wired into `tick_driver`
> (opt-in); OpenIE+entity-resolution ingest (`lp_ingest_resolved`) and
> FlateDecode PDFs; tools driven from `goal_engine` + live HTTP + moment
> emission; and self-improvement with lookahead planning, value-table
> persistence, and minting accepted self-edits as rule atoms. 23 affected test
> suites (873 checks) green over the combined tree. Remaining frontier: a single
> always-on autonomous loop, live MCP transport, and snapshot-backed
> cross-session persistence — see ADR-0056 "Honest gaps".

> **CAPSTONE — ONE AUTONOMOUS LOOP (2026-06-11, ADR-0057).**
> `src/agent/autonomous_loop.nova` composes all five phases into a single
> deterministic cycle: act+learn the task (P5) → reward drives three-factor
> substrate plasticity (P2) → goal-driven gated tool plan emitting moments (P4)
> → entity-resolved ingestion (P1+P3) → bounded, audited self-edit (P5+safety).
> Measured over a 30-cycle run (`test_autonomous_loop`, 13 checks): task return
> −100→95 (optimal path learned from its own experience); task-value synapse
> 0→65; 90 moments; KG stable at a handful of atoms (no fragmentation); 3 gated
> self-edits, audit chain verifies; **0** self-edits when approval is withheld.
> Remaining: make tool calls the task actions, fold the cycle into `tick_driver`,
> snapshot agent state across restarts, live MCP. See ADR-0057 "Honest gaps".

---

## P1 — HDC/VSA embedding layer  *(keystone)*

> **STATUS: implemented + full cutover wired (2026-06-11), behind
> `ATOM_EMBED_MODE` (default LEGACY).**
> Module `src/kg/hdc_embed.nova` (D=10000 bipolar VSA: bind/bundle/permute/
> unbind/cosine + symbol/encode + a memoising symbol cache), flag + accessors in
> `atom_store.nova`, and ADR-0051. **All three embed producers honour the flag:**
> `word_atom_new` (`word_embed_vec`), `snapshot_disk` rehydration, and
> `concept_layer` semantic facets (`hdc_bundle` in HDC mode). Acceptance met
> (measured): bind self-inverse exact; `(France⊗capital)→Paris`;
> `cos(encode(car),encode(automobile))=731 (>700)`; capacity 35/35 perfect,
> 58/60 at N=60. Tests: `test_hdc_embed` (45 checks) + HDC concept-promotion +
> HDC snapshot round-trip + a `word_atoms` mode case. Every bounded-time test
> passes; prior results byte-identical at the LEGACY default.
> **Remaining (not blocking):** cache eviction policy; re-embedding pre-existing
> atoms on a live mode switch; `entity_resolve.nova` (P3) as the first real
> `hdc_cosine` consumer. See ADR-0051 "Honest gaps".

**Problem.** `atom_store` uses `ATOM_EMBED_DIMS = 8` from `word_lexical_vec` →
captures spelling, not meaning. "car" and "automobile" are far apart.

**Target.** High-dimensional (D = 10,000) Vector Symbolic Architecture with
`bind` / `bundle` / `permute`, one-shot learning, compositional query.

### New module: `src/kg/hdc_embed.nova`
```
hdc_dims()                       -> 10000
hdc_random_atom_vector(seed)     -> deterministic random ±1 hypervector
hdc_bind(a, b)                   -> elementwise mult (role⊗filler)  [self-inverse]
hdc_bundle(list_of_vecs)         -> majority/sum then sign          [superposition]
hdc_permute(v, k)                -> cyclic shift by k               [sequence/order]
hdc_unbind(c, a)                 -> hdc_bind(c, a)  (recover filler)
hdc_cosine(a, b)                 -> similarity in milli (reuse semantic_search math)
hdc_encode_atom(atom)            -> bundle of (relation ⊗ neighbor) over its edges
```

### Wiring
- Add `ATOM_EMBED_MODE` flag in `atom_store.nova`; keep `word_lexical_vec` as
  the legacy fallback so existing tests stay byte-identical until cut over.
- Re-point `semantic_search.nova` cosine + `ann_index.nova` LSH at the HDC
  vectors (LSH scales fine to D=10k; raise K from 8 to ~16).
- Extend `concept_layer.nova` facet vectors to HDC (it already has multi-facet).

### Acceptance
- `hdc_bind` is its own inverse to within bundle noise (unit test).
- `hdc_cosine(encode("car"), encode("automobile")) > 700` after both are
  ingested from text mentioning shared neighbors.
- `(France ⊗ capital)` unbinds to recover `Paris` from a bundled record.
- All prior `semantic_search` / `ann_index` tests pass with mode flag = legacy.

**Tests:** `tests/unit/test_hdc_embed.nova` (bind/bundle/permute algebra,
inverse property, capacity/crosstalk at N bundled pairs, query round-trip).

---

## P2 — Predictive coding + three-factor learning

> **STATUS: implemented (2026-06-11), ADR-0052.** Additive (no behaviour change
> to existing rules). `synapse_graph.nova` gains three-factor plasticity
> (`dw = eta·neuromod·eligibility`) + STDP-asymmetric eligibility deposit
> (`syn_stdp_kernel`/`syn_coactivate`/`syn_eligibility_step`/`syn_neuromodulate`);
> `predictive_coding_runtime.nova` gains a gradient-free adaptive predictor +
> `pc_neuromod_scalar`; new `src/learning/forward_forward.nova` (goodness-based,
> no cross-layer gradient). Acceptance met (measured): delayed reward (t+5)
> potentiates where pure Hebbian can't; STDP forward ≈4× backward; the
> predict→err→reward bench cuts mean error **99%** (1013→9) over 150 ticks; FF
> separates real vs corrupted data. Tests: `test_three_factor` (18),
> `test_predictive_coding_runtime` (30), `test_forward_forward` (8),
> `bench_predictive_coding`; `test_synapse_graph` (55) green = no regression.
> **Remaining (not blocking):** wire the eligibility/neuromodulate pass + the
> predictor into `tick_driver`; source FF negatives from `dream_recombination`;
> consider a signed STDP trace + a learned critic. See ADR-0052 "Honest gaps".

**Problem.** Current plasticity is two-factor Hebbian (`pre × post`) → no credit
assignment → plateaus. ADR-0024 (predictive coding) is documented but the
runtime is thin.

### Upgrade `src/substrate/synapse_graph.nova` plasticity rule
```
Δw_ij = pre_i × post_j × neuromod
  where neuromod = f(reward, prediction_error, surprise)   // single broadcast scalar
```
- Add **eligibility traces**: per-synapse decaying memory of recent co-fire so a
  reward arriving *after* the moment still credits the right synapses
  (temporal credit assignment).
- Add **STDP asymmetry**: "A then B" wires forward stronger than "B then A"
  (use the moment timestamps already in `moment_stream.nova`).

### New/upgraded module: `src/parts/reasoning/predictive_coding.nova`
- Each part emits a **prediction** of next-moment signals.
- Compute **local prediction error** → emit as `XSIG_ERROR` (already priority 7).
- Neuromodulator scalar sourced from `emotion/appraisal.nova`
  (`XSIG_REWARD` / `XSIG_VALENCE`).

### New module: `src/learning/forward_forward.nova`  *(representation learner)*
- Positive pass = real moment; negative pass = corrupted/imagined moment from
  `imagination/dream_recombination.nova` (already generates these).
- Each layer locally maximizes "goodness" on positive, minimizes on negative.
- No gradient flows between layers.

### Acceptance
- A predict→err→reward loop measurably reduces prediction error over N ticks on
  a synthetic repeating moment sequence (regression metric in a bench).
- Three-factor rule learns a delayed-reward association pure Hebbian cannot
  (eligibility-trace unit test with reward at t+k).

**Tests:** `test_predictive_coding_runtime.nova` (extend), `test_three_factor.nova`,
`test_forward_forward.nova`.

---

## P3 — Ingestion, formats, scraping

> **STATUS: core implemented (2026-06-11), ADR-0053.** Four new, individually
> tested modules (no existing module changed → existing suite unaffected):
> `src/data/table.nova` (CSV + Markdown → GROUP BY-queryable row-atoms),
> `src/data/pdf_text.nova` (PDF text-object extraction), `src/learning/openie.nova`
> (shallow SVO + n-ary OpenIE with *discovered* predicates), and
> `src/learning/entity_resolve.nova` (exact → alias → **HDC** resolution — the
> first real `hdc_cosine` consumer). All three acceptance criteria met
> (measured): PDF text → provenanced triples (`plants absorb_from air`);
> car/automobile → ONE atom via HDC (unrelated mentions not merged); CSV →
> GROUP BY (west=400, east=250). Tests: `test_entity_resolve` (19), `test_table`
> (24), `test_openie` (33), `test_pdf_text` (10).
> **Remaining (follow-ups, not blocking):** wire `openie_triples` +
> `er_resolve_or_create` into `learn_pipeline`; FlateDecode PDFs via the existing
> `deflate_decode`; politeness crawler + arXiv/PubMed/Wikidata connectors;
> multimodal (OCR/STT) → triple routing; ingest-time source-authority +
> contradiction gating. See ADR-0053 "Honest gaps".

**Problem.** `preprocess.nova` is English-only, 6 fixed patterns, 2 triples/
sentence, no PDF/CSV/table. Cannot read books or papers; fragments entities.

### Format decoders (match the `src/data/json.nova` shape)
- `src/data/pdf_text.nova`   — PDF → text + coarse layout (start with text streams).
- `src/data/table.nova`      — CSV / HTML `<table>` / Markdown table → one atom per
                               row, column-header → relation.
- `src/data/latex_math.nova` — LaTeX/MathML → equation atoms (for papers).

### Extraction upgrade: `src/learning/openie.nova`
- Dependency-parse-style **Open Information Extraction**: emit n-ary relations
  with discovered predicates, not just 6 binary patterns.
- **Event extraction**: who-did-what-to-whom-when → process knowledge.
- Confidence gate; provenance mandatory.

### Entity resolution: `src/learning/entity_resolve.nova`  *(critical)*
- Resolve mentions ("car" / "automobile" / "the vehicle") to a **canonical atom**
  *before* insertion, using P1 HDC similarity + alias tables.
- Without this the KG fragments and the "one atom answers many phrasings"
  property breaks.

### Active scraping: extend `internet_fetch.nova` + `kg_rss_ingest.nova`
- Politeness-aware crawler (robots.txt, rate-limit, sitemap).
- Structured connectors via `json.nova`: arXiv, PubMed, Wikidata, generic REST.
- Crawl targets driven by `XSIG_CURIOSITY` (scrape what it's uncertain about).

### Multimodal ingestion (wire existing vision/audio into learning)
- Route `image_ocr`, `image_detector`, STT (`whisper`/`vosk`) outputs into the
  **same** triple-ingest path → diagrams and lectures become atoms.

### Ingest-time quality gates
- Source-authority weighting (ADR-0029, exists) + contradiction detection
  (R73 opposite-aware) + confidence thresholds so low-trust can't poison
  high-trust atoms.

### Acceptance
- A research-paper PDF ingests to provenanced atoms with > X triples/page.
- "car" and "automobile" mentions resolve to one atom (entity-resolution test).
- A CSV ingests to row-atoms queryable via `query.nova` GROUP BY.

---

## P4 — Agentic tooling

> **STATUS: core implemented (2026-06-11), ADR-0054.** Six new modules (no
> existing module changed → existing suite unaffected): `io/effectors/tool.nova`
> (tools as skill-atoms with Bayesian competence + registry + selection +
> permission/reversibility gate), four effectors (`effector_code_exec`,
> `effector_file_ops`, `effector_http_action`, `effector_mcp`), and
> `agent/tool_use.nova` (plan → select-by-competence → gate → invoke → thread →
> learn). Acceptance met (measured): a 3-step plan search→compute→write runs
> end-to-end (file holds "42"); a failing tool's competence falls 800→400 and
> selection flips to the alternative; irreversible actions (send/spend) gated to
> APPROVE. Tests: `test_tool` (25), `test_effectors` (16), `test_tool_use` (11).
> **Remaining (follow-ups, not blocking):** drive plans from `goal_engine`; route
> pre-sim through `forward_sim`; emit results into `moment_stream` + feed the P2
> reward loop; wire live HTTP/MCP transports; automate self-directed tool
> acquisition (P3 docs → mint skill-atom → try → competence). See ADR-0054.

**Problem.** Effectors are speech-centric; no code-exec / web-action / API tools;
tool use isn't planned or learned.

### Tools as skill-atoms (reuse `skills_kg.nova` + `competence_tracker.nova`)
- Each tool = a skill atom with signature (inputs/outputs), competence score, cost.
- Agent reasons about tools as knowledge → selects via the same KG.

### New effectors under `src/io/effectors/`
- `effector_code_exec.nova` — sandboxed code execution.
- `effector_http_action.nova` — outbound API calls (reuse HTTP client).
- `effector_file_ops.nova` — read/write within permission tier.
- `effector_mcp.nova` — MCP-style connector to external services.
- **Every effector emits its result back as a moment** → ingested → learned from.

### Tool use as planning
- `goals/goal_engine` decomposes goal → plan.
- Each step selects a tool-atom by competence.
- `imagination/forward_sim` pre-simulates the call (predict result first).
- `permission_tiers` + `reversibility_classifier` gate irreversible actions
  (safety scaffolding already exists — USE it).

### Self-directed tool acquisition
- Read an API's docs (P3 ingestion) → mint a new skill-atom → try it →
  `competence_tracker` records success/failure → `XSIG_REWARD` → three-factor
  plasticity improves future selection. **No retraining.**

### Acceptance
- Agent completes a 3-step tool plan (search → compute → write) end-to-end.
- A failed tool call lowers that tool's competence and changes next selection.

---

## P5 — Simulation environment + self-improvement

> **STATUS: core implemented (2026-06-11), ADR-0055.** Two new modules (no
> existing module changed → existing suite unaffected): `src/sim/world_model.nova`
> (deterministic tickable grid micro-world; states=cells, actions=moves,
> reward+done; `world_peek` = forward-sim predict-before-act) and
> `src/parts/meta/self_improve.nova` (gradient-free TD value learning from logged
> experience + a bounded self-edit gated by `constitutional_filter` and recorded
> in the hash-chained `decision_log`). Acceptance met (measured): on a 5x5 grid
> the greedy return rose from -200 (untrained) to 93 — the **optimal 8-step
> path** — learning only from its own logged transitions (+293, no teaching);
> self-edits bounded (benign-approved executes, unapproved suspends, forbidden
> vetoed), all audited and `dl_verify`-clean. Tests: `test_world_model` (29),
> `test_self_improve` (20), `bench_self_improve`.
> **Remaining (follow-ups, not blocking):** drive the value update from the P2
> three-factor reward loop; HDC (P1) state features; `forward_sim` engine over
> `world_peek`; mint accepted self-edits as real rule atoms with rollback;
> persist the value table + drive from `tick_driver`. See ADR-0055.

**Problem.** No sandbox world to practice/plan in; no self-modification loop.

### Simulation: `src/sim/world_model.nova`
- A deterministic, tickable toy environment the agent can act in *imaginarily*
  via `imagination/forward_sim.nova` before acting for real.
- States are moments; actions are effector calls; rewards feed appraisal.
- Start with grid/text micro-worlds; expand to API/tool sandboxes.

### Self-improvement: `src/parts/meta/self_improve.nova`
- `meta/reflection_loop` reviews prediction-error + competence trends.
- Proposes new rules (`rule_inference`), new skill-atoms, new crawl goals.
- **Bounded**: all self-edits go through `constitutional_filter` +
  `decision_log` (audited, reversible). No unbounded self-rewrite.

### Acceptance
- Agent improves a task metric across sessions using only its own logged
  experience (no human teaching) — measured in a bench.

---

## Cross-cutting requirements

- **Every phase ships unit tests** (`tests/unit/test_<module>.nova`) and an
  integration scenario. Keep the `make test` green-gate.
- **Provenance + confidence mandatory** on every atom written.
- **Mode flags** for risky cutovers (e.g. embedding mode) so prior tests stay
  byte-identical until explicit switch.
- **ADRs**: write one ADR per new subsystem (continue the `docs/adr/` series).
- **Honest-gaps section** in each ADR (the project's existing discipline).

## Sequencing summary
```
P1 HDC embeddings  ──►  P2 predictive coding + 3-factor  ──►  P3 ingestion/OpenIE
                                                                     │
                          P5 sim + self-improve  ◄──  P4 agentic tooling
```

---

## Phase L — Memory-lifecycle GC arc completion (in progress)

Three focused rounds closing the open threads left by ADR-0072..0085:

- **R1 -- Auto-compact trigger (SHIPPED, ADR-0086).** A rate-limited freelist
  watcher in the autonomous loop samples per-KG `freelist/atoms_alive` every
  `CROSSENGIN_AUTOCOMPACT_CHECK_EVERY_TICKS` and invokes `kg_compact` when the
  ratio crosses `CROSSENGIN_AUTOCOMPACT_THRESHOLD_PERMILLE`, subject to a
  per-KG `MIN_INTERVAL_TICKS` cooldown. Wired into `agent_cycle`; primary
  production caller of ADR-0079's in-place compactor.
- **R2 -- GC observability (SHIPPED, ADR-0087).** Per-agent GC-metrics
  registry at `src/kg/gc_metrics.nova` counts reclaim / sweep /
  operator-premise / operator-conclusion / episodic-member / alias
  protection events, plus compact runs (with atoms removed + last tick) and
  the latest freelist size + ratio sample per KG. The autonomous loop
  threads the registry through `adm_sweep_ep_metric`, `kg_compact_metric`,
  and the ADR-0086 auto-compact watcher; `agent_new` installs it as the
  module-level default so the new `/gc-stats [kg=<label>]` chat command
  can read it back without an agent in scope. Existing GC callers stay
  unchanged (a `metrics_reg == 0` sentinel disables attribution).
- **R3 -- Cross-KG xref query-time traversal (SHIPPED, ADR-0088).** The
  reader's `find_neighbors_full` now folds in a bounded transitive walk over
  persisted cross-KG xrefs via `nb_xref_traversal` /
  `_nb_follow_xrefs` in `src/reader/neighborhood.nova`, layered on top of the
  existing operator / xref / word-sense / cofire / slot walks. Ordered DESC
  by `XR_COACT` so the fanout cap keeps the strongest edges;
  `CROSSENGIN_READER_XREF_MAX_DEPTH` / `_MAX_FANOUT` / `_MIN_COACT` are the
  three levers (defaults 1 / 8 / 2). Dangling xrefs are a silent skip; a
  visited-handle set makes cycles safe. Closes the memory-lifecycle GC arc.

**Phase L status: COMPLETE.** ADR-0074 (freelist) through ADR-0088
(xref query-time traversal) now form a closed loop: reclaim -> sweep ->
compact-remap -> observability -> query-side consumption.

## Phase M — Federation Daemon (COMPLETE)

`src/federation/` has 23 unit-tested modules (gossip, kg_sync, distributed
query, distributed rules, leader election, snapshot attestation + replication,
DTLS 1.2 with R29B2 stubs, ICE/STUN/TURN/WebRTC, NAT traversal, gossip relays,
Raft). Every one is unit-tested. Until Phase M, none were wired into a
runnable daemon; the chat REPL slash commands (`/gossip`, `/gossip_add_peer`,
`/gossip_noise`, `/leader`, `/attest_log`, `/nat`, `/drule_add`, ...) were
stubs that printed a link to the integration scenario and returned.

Three focused rounds unify the mesh under a single binary
(`examples/crossengin_fed_daemon.nova`) and lift the chat REPL stubs to real
handlers:

- **R1 -- MVP federation daemon (SHIPPED, ADR-0089).** New
  `examples/crossengin_fed_daemon.nova` composes gossip + kg_sync +
  distributed_query into one event-driven binary over plain TCP (DTLS 1.2
  stubs at `src/federation/dtls12.nova:137, 140` block wire encryption
  until the R29B2 unstub). Env-var contract: `CE_FED_LISTEN_ADDR`
  (default `127.0.0.1:8790`), `CE_FED_PEERS` (falls back to
  `CE_GOSSIP_PEERS`), `CE_FED_SOUL_ID`, `CE_FED_TICK_MS` (default 250,
  clamped to [50, 10000]). Component alloc order: `kg_registry_new` ->
  `mo_new` -> `reasoning_kg_init` -> `gossip_init` -> `gossip_listen` ->
  `kgd_state_new` -> `dq_init`; wrapped in a Session for R3's snapshot
  hooks. Chat REPL now grows four real handlers -- `/gossip_start [addr]`,
  `/gossip_peer add <addr>`, `/gossip_peers`, `/gossip_dq <query>` --
  replacing the R18E "this REPL has no gossip daemon" stubs. Argument
  parsers + output formatters live in `src/chat/fed_slash.nova` for
  testability. Cross-Windows build target and `install` seat under
  `crossengin-fed-daemon`.
- **R2 -- coordination + inference (SHIPPED, ADR-0090).** Extends the R1
  fed daemon with `le_init(gs, self_id)` and `dr_init(gs, rule_engine_new())`
  under two opt-out env flags (`CE_FED_LEADER_ELECTION_ENABLED`,
  `CE_FED_DR_ENABLED`; default on, only `"0"` disables). Tick body adds
  `le_step` alongside `gossip_step`; distributed-rules runs on explicit
  operator invocation (rule evaluation is expensive; drift-free between
  rounds). Chat REPL: R21B `/drule_add`, `/drule_run` stubs plus the
  R19E `/leader` stub become real handlers; `/drule_fixpoint` and
  `/leader elect` newly dispatched; `_chat_fed_le` / `_chat_fed_dr` /
  `_chat_fed_dr_engine` module singletons allocated alongside the R1
  gossip state inside `_admin_gossip_start`. Argument parsers + line
  formatters in `src/chat/fed_slash.nova` (5 new helpers). `soul_id`
  string maps to Bully's numeric `self_id` via a djb2 mixer masked to
  24 bits (`_fed_soul_id_to_int`); the chat mirrors the same mixer so
  chat + daemon at the same address agree on id. New ADR-0090 covers
  Bully corner cases (split-brain during partition, deferred outbound
  message queue, gossip-derived convergence shortcut), boundedness
  (`DR_DEFAULT_MAX_ROUNDS=50` cap on fixpoint), and the R3 preview.
  Two new test files (`test_fed_daemon_leader.nova`,
  `test_fed_daemon_rules.nova`; ~30 checks each) exercise the env
  resolver, mixer, le/dr bootstrap, message-handler flows, and the
  env-disabled skip path.
- **R3 -- durability (SHIPPED, ADR-0091).** Extends the R2 fed daemon
  with `att_store_new()` + `sr_init(gs, local_snap_dir)` under three
  new env flags (`CE_FED_ATTEST_ENABLED` and
  `CE_FED_SNAP_REPLICATION_ENABLED` default-on; `CE_FED_SNAP_SERVE`
  default-OFF -- opt-in per plan). Signer identity loads via
  `merkle_signing_keypair_load(<CE_FED_ATTEST_KEY_DIR>/signer)`; a
  missing key file WARN-disables attestation without crashing the mesh
  peer. Own pubkey registered under own peer_id via
  `gossip_register_att_pubkey` so same-node round-trips verify. New
  `sr_set_serving(sr, on)` + `SR_S_SERVING` slot in
  snapshot_replication.nova gate `sr_serve_snap_request` on the
  opt-in flag; new `att_store_recent(store, N)` enumerates the tail
  across all peers. Chat REPL: `/attest_log`, `/attest_verify <soul>`,
  `/snap_fetch <root>`, `/snap_serve on|off` become live handlers;
  `_chat_fed_att` / `_chat_fed_sr` module singletons allocated
  alongside R1's `_chat_fed_gs` / R2's `_chat_fed_le` inside
  `_admin_gossip_start`. Argument parsers + line formatters in
  `src/chat/fed_slash.nova` (7 new helpers). Two new test files
  (`test_fed_daemon_attest.nova` ~40 checks,
  `test_fed_daemon_replication.nova` ~40 checks) exercise env
  resolvers, keypair-path precedence, att/sr bootstrap, serve gating,
  and the chat REPL formatters. **This closes the federation-daemon
  arc for the plain-TCP era**: every one of the 23 modules under
  `src/federation/` that CAN be wired without unstubbing DTLS 1.2 now
  IS wired into the fed daemon and/or the chat REPL. Follow-up work
  (DTLS 1.2 unstub at `src/federation/dtls12.nova:137, 140`, NAT
  hole-punch R23E.2, WebRTC data plane, Raft wire integration,
  auto-broadcast attestation on snapshot save) deferred to
  post-Phase-M rounds.

**Phase M COMPLETE.** R1+R2+R3 unify the mesh substrate under a single
`examples/crossengin_fed_daemon.nova` binary and lift every R18E/R19E/
R20E/R20F/R21B/R23C chat REPL stub to a real handler. Under-covered
edges (DTLS 1.2 cert-verify, NAT UDP hole-punch, WebRTC data plane,
Raft wire integration, auto-broadcast) are documented as post-Phase-M
candidates below.

## Phase N — Fill README-only parts subtrees (COMPLETE)

Two rounds close the "Status: Pending" placeholders under
`src/parts/perception/` and `src/parts/action/` -- the last two parts
subtrees whose READMEs promised modules the loop layer never called.

- **R1 -- Perception module (SHIPPED, ADR-0092).** Two new modules
  under `src/parts/perception/`: `perception_atoms.nova` (the 14-slot
  `Percept` record, four constructors for text / image / audio /
  multimodal, accessors + name mappings + a summary formatter) and
  `perception_module.nova` (the orchestrator -- composes
  `classify_input` + the five-stage reader + optional
  `fuse_image_observation` / `fuse_audio_observation` /
  `fuse_observation` + optional `lipsync_detect` behind
  `perception_step_text` / `_image` / `_audio` / `_multimodal`; caches
  the most-recent Percept on `PM_LAST_PERCEPT` for R2 to consume; a
  module-level singleton `perception_module_singleton_for(renv)` lets
  `src/agent/loop_perception.nova::loop_perception_step` delegate
  without a signature change, so `examples/crossengin_chat.nova`,
  `examples/crossengin_daemon.nova`, and the existing unit test are
  byte-untouched). `src/agent/autonomous_loop.nova::agent_new` now
  allocates `AG_PERCEPTION_MODULE` at slot 21; the accessor
  `agent_perception_module(a)` exposes it for R2. Behavior-preservation
  contract asserted in `test_perception_module.nova` +
  `test_loop_perception.nova`: the four ctx slots (`percept`, `active`,
  `routes`, `unknown`) are byte-identical to the pre-R1 reader-only
  path for a fixture text input.
- **R2 -- Action module (SHIPPED, ADR-0093).** Three new modules
  under `src/parts/action/`: `action_atoms.nova` (the 12-slot
  `Intent` record, three constructors for SPEAK / INTERNAL /
  TOOL_CALL, accessors + kind & effector-class name mappings +
  `in_kind_to_effector_class` routing + a summary formatter),
  `action_module.nova` (the orchestrator -- `action_derive_intent`
  maps ctx state to SPEAK/INTERNAL intents, `action_submit` routes
  SPEAK intents through `effector_gate.effector_submit` +
  `effector_speak` writing INTENT + OUTCOME to the decision log,
  `action_complete` writes the outcome, `action_run` cascades
  derive → submit → complete; a module-level singleton
  `action_module_singleton_for(dl, ge)` lets
  `src/agent/loop_action.nova::loop_action_step` delegate without a
  signature change), and `motor_map.nova` (the
  substrate-activation → effector-class registry, ships empty at
  MVP; a follow-up round populates it with real activation-signature
  → TOOL / FILE / HTTP mappings). `src/agent/autonomous_loop.nova::agent_new`
  now allocates `AG_ACTION_MODULE` at slot 22 via
  `action_module_init(agent_dl(a), 0)`; accessors
  `agent_action_module(a)` + `agent_dl(a)` expose the wire. The
  pre-R2 three-branch template body has been retired from the loop:
  every SPEAK now writes an INTENT + OUTCOME to the decision log
  when the daemon-wire `_la_dl_slot` is populated (chat REPL /
  existing unit tests pass no slot so the submit path
  short-circuits silently -- byte-identical to pre-R2 in that
  case). Backwards-compat contract asserted in
  `test_action_module.nova` + the extended `test_loop_action.nova`:
  for the three pre-R2 fixtures the emitted `ctx_output` text is
  byte-identical to pre-R2 (`"i do not fully understand that yet"`
  / `"understood"` / `"i have nothing to say"`). This CLOSES the
  README-only parts arc.

**Phase N COMPLETE.** R1+R2 fill both formerly-Pending parts subtrees
(`src/parts/perception/`, `src/parts/action/`) with real atom +
orchestrator modules and loop integration that honors the READMEs'
promises. The last README-only parts subtree is done; every parts
subtree with a Status now has an Accepted README backed by real
modules on the loop's chain.

## Phase O — DTLS 1.2 completion + gossip transport wrap (COMPLETE)

Phase O closes the DTLS 1.2 work in `src/federation/dtls12.nova` and
wraps gossip's TCP transport in DTLS records via a non-RFC-standard
TCP shim (user-selected because gossip is line-oriented TCP today
and NOVA lacks the UDP primitives an RFC-compliant DTLS transport
would need).

- **R1 -- DTLS cert-chain + truststore + hostname wire
  (SHIPPED, ADR-0094).** Explore surfaced that the header comment at
  `src/federation/dtls12.nova:137` mis-described `dtls_cert_verify` as
  a "stub" -- R33B had already shipped the real single-cert path.
  What was actually missing was chain walking, truststore
  consultation, and SAN-based hostname matching. R1 adds a new
  `dtls_cert_verify_chain(state, cert_der_list, hostname, anchors,
  now)` entry that forwards to
  `src/safety/x509_verify.nova::cert_chain_verify` and maps XV_* to
  DTLS_* error codes (five failure classes, two of them new:
  `DTLS_CERT_NOT_PINNED = "dtls-cert-not-pinned"` and
  `DTLS_CERT_HOSTNAME_MISMATCH = "dtls-cert-hostname-mismatch"`, each
  with its own tail-appended `STATS_CERT_*` counter). The legacy
  single-cert `dtls_cert_verify(state, cert, n, fp)` signature is
  untouched so existing test callers (including the R29B2 stub-forward
  pinned in `tests/unit/test_dtls12.nova:677`) keep working
  byte-identically. `src/safety/pem_truststore.nova` grows
  `truststore_load_dir(dir_path)` -- since NOVA has no `sys_readdir`
  primitive (documented at `src/nl/rpc_verbs.nova:3330`), R1 takes
  the manifest-file fallback path: a `<dir>/manifest.txt` lists one
  PEM filename per line (empty lines + `#` comments skipped) and
  each is loaded via `truststore_load_file` and merged. Missing dir
  or missing manifest -> empty anchors, no error (safe fail-closed:
  every chain then rejects with XV_NOT_PINNED).
  `examples/crossengin_fed_daemon.nova` adds two env vars:
  `CE_FED_DTLS_TRUSTSTORE_PATH` (default
  `$HOME/.crossengin/fed_truststore`, container fallback
  `./crossengin_fed_truststore`) and `CE_FED_DTLS_HOSTNAME` (default:
  `ce-<hash(SOUL_ID)>.fed` via a deterministic djb2 mixer over the
  soul_id, so a self-signed test mesh where every peer's cert SAN
  carries the derived hostname "just works"). R1 only ALLOCATES
  anchors at boot and logs them in the banner + shutdown summary;
  R3 wires the actual transport-time gating when the DTLS-over-TCP
  shim lands. Tests: `tests/unit/test_dtls_cert_chain.nova` (~50
  checks against the openssl-minted RSA + ECDSA chain fixtures
  reused from `test_x509_verify.nova`; covers every XV -> DTLS
  mapping, every counter bump, per-state isolation, error
  accumulation, stats-line inclusion of the new counters, and
  the two new tag spellings) and `tests/unit/test_truststore_dir.nova`
  (~30 checks against fabricated per-test PEM + manifest fixtures
  under `$HOME/.crossengin_ph_o_r1_*/`; covers non-existent dir,
  null/empty path, missing manifest, single file, two files
  merged, `#` comments + blank lines, missing/corrupt manifest
  entries, CRLF endings, no trailing newline, empty and
  all-comments manifests).
- **R2 -- SRTP EKM forward + `use_srtp` extension
  (SHIPPED, ADR-0095).** Explore surfaced that the header comment at
  `src/federation/dtls12.nova:140` (now :161 after R1's rewrite) still
  called `dtls_extract_srtp_keys_R29B2_STUB` a stub, when R36B had
  already shipped the full RFC 5764 §4.2 exporter
  `dtls_export_srtp_keying_material` (60-byte PRF expansion under the
  "EXTRACTOR-dtls_srtp" label, cached in DTLS_S_SLOT_SRTP_KM_CACHED).
  R2 flips the legacy `_R29B2_STUB` wrapper into a thin forward to
  the real exporter (`if state == 0 { return 0 } else return
  dtls_export_srtp_keying_material(state)`); the suffix is kept for
  grep-compat but the body is no longer a sentinel-returner. Two
  public accessors that R33B skipped are also exposed:
  `dtls_client_random(state)` and `dtls_server_random(state)` read
  slots 17 and 18 respectively, so callers that need to bind SRTP
  (or a DTLS-SCTP keyfile) to the PRF seed no longer index raw slot
  numbers. Four RFC 5764 §4.1.2 profile IDs
  (`SRTP_PROFILE_AES128_CM_SHA1_80 = 1`,
  `SRTP_PROFILE_AES128_CM_SHA1_32 = 2`,
  `SRTP_PROFILE_NULL_SHA1_80 = 5`,
  `SRTP_PROFILE_NULL_SHA1_32 = 6`), the extension type
  `DTLS_EXT_USE_SRTP = 14`, and a fresh tail-appended state slot
  `DTLS_S_SLOT_SRTP_OFFER = 48` back a public setter
  `dtls_offer_srtp(state, profile)` that validates the profile
  argument (unknown values become a no-op with `last_err` stamped
  to `"DTLS_ERR_BAD_SRTP_PROFILE"`). When the slot is non-zero at
  `dtls_client_init` time, the ClientHello body builder splices the
  9-byte wire sequence `[00, 14, 00, 05, 00, 02, 00, <profile>, 00]`
  (RFC 5764 §4.1.1: `use_srtp` with a single-profile
  `SRTPProtectionProfiles<>` list and an empty `srtp_mki<>`) into
  the extensions block, growing the CH body from 42 to 53 bytes; a
  zero slot leaves the wire bytes byte-identical to the pre-R2 42-
  byte body so existing wire-byte assertions
  (`tests/unit/test_dtls12.nova:448`) keep passing. Extension
  PARSING remains deferred (a follow-up round); ServerHello echo is
  deferred alongside since no ServerHello builder exists in this
  file yet -- ADR-0095 documents both as known limitations plus the
  `_dtls_build_use_srtp_ext(profile)` helper it leaves ready for
  the ServerHello builder when it lands. Tests: ~70 new
  `ce_check`/`ce_eq` assertions across 12 new
  `test_r2_*` functions in `tests/unit/test_dtls12.nova` (forward
  equivalence + cache-pointer identity vs the real exporter, the
  RFC 5764 §4.2 60-byte layout with per-slice boundary probes,
  cross-handshake determinism, both random-accessors round-tripped
  through slots 17/18, both accessors after a two-side ECDHE derive,
  all four SRTP profiles accepted by the setter + garbage / reserved
  / zero rejected, and the 9-byte wire shape emitted in ClientHello
  with two different profile IDs plus default-absent when no offer
  is set). The pre-R2 `test_stubs_return_DTLS_ERR_STUB` check for
  the SRTP wrapper was updated to assert the new forward semantics
  (state=0 or fresh state -> 0, not DTLS_ERR_STUB). `make lint-ints`
  clean (12 pre-existing findings unchanged; none in dtls12.nova
  or test_dtls12.nova).
- **R3 -- non-standard DTLS-1.2-over-TCP shim for gossip
  (SHIPPED, ADR-0096).** The user selected the shim path over waiting
  for NOVA `sendto`/`recvfrom` primitives (blocked per NAT-traversal
  R23E.2). R3 wraps each gossip TCP connection in DTLS records by
  prepending a 2-byte big-endian length header to every record before
  writing to the TCP socket and stripping it on read. This is NOT RFC
  6347 compliant -- the RFC assumes UDP datagram boundaries for
  record framing, retransmit semantics, and replay-window sizing --
  and a standards-compliant DTLS peer WILL NOT interop with a gossip
  node using this transport. ADR-0096 flags this loudly in its
  opening callout and documents the migration path (swap the framing
  helpers for `sendto`/`recvfrom` internals when the primitives
  land; the DTLS record body stays unchanged, so the migration
  becomes RFC-standard). New files:
  `src/safety/p256_keypair.nova` (~275 lines; `p256_keypair_load` /
  `p256_keypair_save` / `p256_keypair_generate_deterministic` mirror
  the `merkle_signing_keypair_load` shape for the ECDSA-P256 keys
  DTLS wants instead of the ed25519 seeds Phase M R3 loads),
  `src/federation/gossip_dtls_shim.nova` (~340 lines; length-prefix
  framing via `_gds_send_record` / `_gds_recv_record`, line-oriented
  seal/open via `gds_send_line` / `gds_recv_line`, handshake driver
  seams via `gds_handshake_client` / `_server` -- flight builders
  themselves return "not-yet-wired" today per the pending follow-up
  round, but the wire framing + AEAD round-trip + `gds_close`
  `close_notify` emission all work end-to-end via the
  `gds_keyed_shortcut` fast path where both peers pre-derive the
  cipher state via `dtls_ecdhe_derive` directly), and ADR-0096
  itself (~340 lines with the mandatory "NON-STANDARD" callout up
  top). Modified files: `src/federation/gossip.nova` grows three
  opt-in DTLS-aware handler variants (`gossip_handle_conn_dtls`,
  `gossip_handle_conn_kg_dtls`, `_gossip_dial_dtls`) at end-of-file
  plus one new import; the plaintext handlers are untouched.
  `examples/crossengin_fed_daemon.nova` grows the transport gate
  (`CE_FED_TRANSPORT` = `"tcp"` (default) or `"dtls"`;
  `CE_FED_DTLS_CERT_DIR` default `$HOME/.crossengin/fed_dtls_keys/`
  container-fallback `./crossengin_fed_dtls_keys/`), a P-256 keypair
  load at boot when DTLS is requested (missing keypair -> WARN +
  fall back to tcp with a loud banner line, per ADR-0096
  §"Alternatives Considered (e)"), and an accept-loop wrap that
  drives `gds_handshake_server` on each newly-accepted fd before
  handing off to `gossip_handle_conn_kg_dtls`. Chat REPL grows
  `/gossip_transport` (info-only, env-driven at first `/gossip_start`;
  see `docs/CHAT_USAGE.md`) backed by
  `_fed_transport_line(mode)` in `src/chat/fed_slash.nova`. Tests:
  `tests/unit/test_p256_keypair_load.nova` (~30 checks against
  missing / wrong-size / bad-SEC1-tag files plus save+load round-trip
  and deterministic-generator vectors),
  `tests/unit/test_gossip_dtls_shim.nova` (~50 checks against the
  2-byte BE length header shape, the send-side validation guards,
  `gds_is_ready` / `gds_keyed_shortcut` / handshake seams, and the
  AEAD seal/frame/unframe/open round-trip built in-memory since
  NOVA lacks socketpair -- includes a tamper check that pins
  DTLS_DECRYPT_FAIL on flipped ciphertext), and
  `tests/unit/test_fed_daemon_transport.nova` (~20 checks pinning
  the env resolver + cert-base fallback semantics + the missing-
  keypair refuse shape + the `_fed_transport_line` REPL output).
  `make lint-ints` clean (12 pre-existing findings unchanged; none
  in the new / modified files). Phase O is now COMPLETE: R1 + R2
  closed the DTLS 1.2 stack (cert-chain + SRTP EKM + `use_srtp`),
  R3 puts the wire under DTLS AEAD (mesh-only per ADR-0096).

## Phase P — DTLS 1.2 handshake flight completion (IN PROGRESS)

Phase P closes the handshake-flight caveat Phase O R3 documented:
`gds_handshake_server` and `gds_handshake_client` in
`src/federation/gossip_dtls_shim.nova` both returned
`"dtls-hs-flight-not-wired"`, so cross-mesh peers had to skip the
handshake via `gds_keyed_shortcut` and pre-derive the cipher state.
R1 ships the SERVER-SIDE half; R2 ships the CLIENT-SIDE half + server
flight-2; R3 ships extension parsing + DTLS-aware gossip stream
helpers so the SNAP_FETCH / DELTA / RELAY_* handlers stop being
silently dropped under DTLS.

- **R1 -- server-side handshake flight (SHIPPED, ADR-0097).** Explore
  surfaced that the 12-byte HS header serialize/parse pair
  (`dtls_handshake_serialize` / `dtls_handshake_parse`) at
  `src/federation/dtls12.nova:1037-1078` and the R2 ClientHello body
  builder at `:1147` gave the shape; the server-side quartet
  (ServerHello / Certificate / ServerKeyExchange / ServerHelloDone),
  the ClientHello PARSER, the transcript-hash accumulator, and the
  server-side state-machine drivers were all missing. R1 adds:
  `_dtls_parse_client_hello_body(buf, n)` (RFC 5246 §7.4.1.2 + RFC
  6347 §4.2.2, refuses on the four documented malformed shapes:
  missing null-compression, wrong cipher suite, short body,
  overflowing length prefixes); `_dtls_parse_ext_block_stub` (R3 will
  replace with a real per-extension walker; R1 validates only the
  outer 2-byte envelope); the four body builders
  (`_dtls_build_server_hello_body` splices in the R2 `use_srtp`
  extension via `_dtls_build_use_srtp_ext` when the SRTP_OFFER slot
  is set; `_dtls_build_certificate_body` composes an RFC 5246 §7.4.2
  cert chain with 3-byte length prefixes; `_dtls_build_ske_body`
  emits the ECDHE ECDSA-signed SKE per RFC 4492 §5.4 with a DER-
  encoded signature per RFC 3279 §2.2.3;
  `_dtls_build_server_hello_done_body` returns the empty body per
  RFC 5246 §7.4.5); an ECDSA-P-256 SIGN helper
  (`_dtls_ecdsa_p256_sign`, added inline in `dtls12.nova` because
  `src/safety/ecdsa.nova` shipped only verify pre-R1; a future round
  promotes it into `ecdsa.nova` when a second caller lands); the
  DER encoder helpers (`_dtls_der_encode_ecdsa_sig` +
  `_dtls_der_encode_bn_as_integer`); and the transcript-hash
  accumulator (three new state functions:
  `dtls_transcript_init` / `dtls_transcript_absorb` /
  `dtls_transcript_finalize`, backed by a growing byte buffer rather
  than a live SHA-256 ctx because `sha256_final` consumes the ctx and
  R2 needs to finalize twice at different transcript prefixes).
  Five new server-side state constants (`DTLS_S_CLIENT_HELLO_RECVD =
  10` .. `DTLS_S_SHD_SENT = 14`, appended so the R29B client-side
  enum 0..6 stays byte-identical) + the matching edges in
  `_dtls_valid_edge`. Three new tail slots:
  `DTLS_S_SLOT_TRANSCRIPT_CTX = 49`,
  `DTLS_S_SLOT_TRANSCRIPT_N = 50`,
  `DTLS_S_SLOT_SERVER_RANDOM_OVERRIDE = 51` (test-mode hook so
  ServerHello bytes stay reproducible under `secure_random`
  unavailability). Wire-level flight driver
  `_gds_server_flight_1(conn_fd, dtls_state, priv_bn, pub_point,
  cert_der)` in `src/federation/gossip_dtls_shim.nova` composes the
  four builders + the transcript feed + the state-machine walk +
  the `_gds_send_record` framing; `gds_handshake_server` re-wired to
  call it (returning `[flight_ok, state]`); every failure path
  stamps a distinct string tag on `LAST_ERR` and transitions to
  `DTLS_S_FAILED`. `gds_handshake_client` still returns
  `"dtls-hs-flight-not-wired"` until R2. Tests:
  `tests/unit/test_dtls_server_flight.nova` (~50 checks: parser
  round-trip + four refusal paths + ext-block stub + all four body
  builders' shapes + SKE signature verifies against `ecdsa_p256_
  verify_bn` + transcript matches `sha256_oneshot` over concatenation
  + non-destructive finalize + server-side state edges + server
  flight driver refuse path + slot-index pinning). ADR-0097
  (~300 lines) covers the design + alternatives (streaming SHA-256
  vs buffer, raw r||s vs DER, deterministic-k RFC 6979 as follow-up).
  `make lint-ints` clean (12 pre-existing findings unchanged; none
  in the R1 files).

## What this roadmap does NOT claim
- It does not claim AGI. It builds the mechanisms a moment-signal AGI bet
  *requires*; whether they compose into general intelligence is unproven and is
  the research wager.
- "Feel" = functional appraisal (control/motivation signal), not sentience.
- Credit assignment without backprop at scale is an open problem; P2 uses the
  best-known local approximations, not a solved method.
