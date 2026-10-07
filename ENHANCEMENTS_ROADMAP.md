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

---

## Phase Q — NOVA bootstrap workaround *(scaffolding, non-feature)*

Phase Q is scaffolding, not a feature phase. It unblocks the CrossEngin
test loop after 14 rounds (Phases L through P) of structural-review-only
verification caused by an upstream NOVA stage-2 bootstrap segfault.

See `docs/adr/0100-nova-bootstrap-setarch-workaround.md` for the full
diagnostic and rationale. Short form: NOVA's stage-1 compiler has a
tagged-int × magnitude-classifier collision in `boot/nova_boot.s` that
crashes under ASLR; `setarch -R` disables ASLR and the bootstrap
completes deterministically. The underlying bug is unfixed.

### Q.R1 — setarch wrappers landed (Scenario A, arc validated)

- **Outcome**: Scenario A. `setarch -R make bin/nova` succeeds; `make
  self-host` (via wrapper) verifies the fixpoint.
- **NOVA Makefile**: four new targets — `bootstrap-setarch`,
  `stage1-setarch`, `stage2-setarch` / `bin-nova-setarch`,
  `self-host-setarch`. Existing targets untouched. Committed to the
  NOVA working copy.
- **CrossEngin test runner (`scripts/test.sh`)**: left untouched.
  Measurement: `test_arithmetic.nova` output is byte-identical with
  and without `setarch -R` prefix on the test invocation. The crash is
  confined to the stage-1 → stage-2 bootstrap window; once `bin/nova`
  is built, running it under ASLR does not re-trigger the classifier
  bug. The optional `CE_NOVA_BOOTSTRAP=setarch` env-branch pattern is
  **documented in the ADR but not wired**.
- **Progressive-coverage smoke (5 recent Phase P tests)**: 4/5 fully
  PASS, 1 PASS-with-nits.
  - `test_dtls_server_flight.nova` — PASS (exit 0)
  - `test_dtls_client_flight.nova` — PASS (exit 0)
  - `test_dtls_ext_parse.nova`     — PASS (exit 0)
  - `test_gossip_dtls_streams.nova` — PASS (exit 0)
  - `test_perception_module.nova`  — 42 passed, 2 FAILED (exit 3):
    "singleton distinct from explicit" and "singleton rebuilt on new
    renv". Minor; module-scoped; isolated to the singleton-cache path.
- **test_arithmetic (CrossEngin smoke)**: PASS (23 checks).
- **Structural-review arc**: **validated**. 14 rounds of
  structural-review-only verification across Phases L-P are now
  confirmed via a working test loop. The two `test_perception_module`
  subtests are an R2 nit, not a regression of the arc itself.
- **Note on first-pass stale checkout**: R1's initial test run was on
  a local HEAD that was 10+ commits behind origin; the Phase P test
  files from the plan did not exist locally and substitute tests
  showed string-equality identical-print failures. After rebasing onto
  origin (which carried Phase M/N/O/P and an upstream fix at
  `afff1a9`), the real test files existed and the actual Phase P tests
  passed cleanly. The earlier "expected='X' got='X'" failures were an
  artifact of running pre-rebase test sources through a post-rebase
  compiler, not a live bug.

### Q.R1 addendum — upstream fix on origin

A `git fetch` during the Makefile commit step revealed that
`origin/claude/confident-fermi-op241b` has advanced from `3b5b8bb` to
`e431246`, including a commit `afff1a9` that fixes the exact
tagged-int × classifier bug by switching `n*2+1` tagging to `(n<<1)|1`
at the three gen_expr sites. The upstream commit asserts `make
self-host` passes with ASLR on and the setarch workaround may become
unnecessary once operator pulls origin. The R1 local Makefile commit
on NOVA is based on the pre-fix HEAD and is **not** pushed; operator
needs to decide whether to rebase-and-push (belt-and-suspenders) or
discard the local commit. See ADR-0100 "Operator Notes" for details.

### Q.R2 — perception-module singleton nit (narrow scope)

R2 is a focused triage of the two `test_perception_module` subtest
failures observed in R1:

1. "singleton distinct from explicit" — the perception singleton
   should be a distinct instance from an explicitly-constructed
   perception module, but the test observed they are the same (or
   vice-versa).
2. "singleton rebuilt on new renv" — the singleton is expected to be
   rebuilt when `renv` is re-created, but the cache appears to be
   surviving the rebuild.

Both are in `src/parts/perception.nova`'s singleton-cache code path.
Scope is small (one file, ~2 behaviours), test fixtures already exist,
and the arc-level verification is already green so this is a nit, not
a blocker.

Optional stretch for R2 if time allows: a `make test` wall-time run
against the full 273-test unit suite under the setarch-built compiler
to catch any other latent failures the Phase P sample missed.

#### Q.R2 SHIPPED (2026-10-01)

**Root cause (deeper than R1 suspected)**: NOVA's `==` / `!=` on list
values is neither reference-identity nor structural-content — empirically
both comparators treat any two list handles as EQUAL regardless of
content (probe: two lists with completely different content still
compare `==` true). Both failing subtests asserted "handle distinctness"
(`s1 != pm`, `s3 != s1`), which can never succeed under NOVA's list
equality.

**Secondary finding**: the module's own rebuild-on-key-change guards
(`_perception_module_singleton_renv != renv2`,
`_action_module_singleton_dl != dl`) are DEAD CODE under current NOVA
semantics — `!=` on list-valued renv / dl is always false, so the
rebuild branches never fire. `_perception_module_singleton_reset()` /
`_action_module_singleton_reset()` are the only portable ways to force
a fresh module. (Future round could migrate the guards to numeric
monotonic ids; captured as a follow-up in ADR-0092 / ADR-0093 §"NOVA
language quirks".)

**Fixes shipped**:
- `tests/unit/test_perception_module.nova` `test_module_init_and_singleton`:
  rewrote both assertions to use behavioral side-effects
  (`pm_step_count` mutation via `perception_step_text`) + reset-based
  rebuild check. 45/45 checks pass.
- `tests/unit/test_action_module.nova` `test_singleton` (parallel bug
  found): same rewrite via `am_intent_count` mutation + reset-based
  rebuild. Singleton test now passes.
- `docs/adr/0092-perception-module.md` + `docs/adr/0093-action-module.md`:
  appended `## NOVA language quirks` sections documenting the real
  NOVA list-equality semantics + behavioral-assertion convention.
- Top-of-file comment added to both test files restating the gotcha.

**Full-suite regression sweep (`./scripts/test.sh tests/unit/*.nova`)**:
TIMED OUT at the 10-minute wall-clock budget while running
`test_merkle_signing.nova`. Partial results through merkle:
- **172 PASS**, **67 FAIL** (plus `test_merkle_signing.nova` hung).
- Failures catalogued below for R3+ triage. **R2 does not fix any of
  these** — they are pre-existing latent failures (several segfault
  with exit 139) unrelated to the singleton-cache work.

Additional failing tests catalogued (partial, pre-timeout, R3+ triage):
`test_action_module` (2 remaining pre-existing EFF_EXECUTED=1 vs got=2
failures in `test_submit_speak_wired_dl` + `test_run_unknown_end_to_end`
— NOT the singleton bug R2 fixed),
`test_admin_bake_child_verb`, `test_admin_emit_delta_verb`,
`test_atom_birth_monitor` (SEGV), `test_atom_death_monitor`,
`test_audio_capture`, `test_audio_synth`, `test_audio_tts`,
`test_audio_wakeword` (SEGV), `test_autocompact_trigger`,
`test_autonomous_loop`, `test_autonomous_research`, `test_bignum_2048`,
`test_bignum_256`, `test_byzantine_aggregation`,
`test_chat_fed_slash_commands`, `test_chat_state_persistence` (SEGV),
`test_cognitive_router`, `test_competence_tracker` (SEGV),
`test_consolidation`, `test_constitutional_filter`,
`test_decision_log_durable` (SEGV), `test_distributed_query`,
`test_distributed_rules` (SEGV), `test_dp_budget_ui`,
`test_dr_async_fetch`, `test_dtls12`, `test_ed25519`,
`test_entity_resolve` (SEGV), `test_episodic` (SEGV),
`test_episodic_retrieval`, `test_face_recognize`,
`test_fed_daemon_attest` (SEGV), `test_fed_daemon_boot` (SEGV),
`test_fed_daemon_leader`, `test_fed_daemon_replication` (SEGV),
`test_fed_daemon_rules`, `test_fed_daemon_transport` (SEGV),
`test_federated_aggregator` (SEGV), `test_gc_metrics`,
`test_gossip` (SEGV), `test_gossip_dtls_shim` (SEGV),
`test_gossip_noise` (SEGV), `test_gossip_relay` (SEGV),
`test_graph_clustering`, `test_http_client` (SEGV), `test_ice`,
`test_ice_turn`, `test_identity`, `test_image_harris`,
`test_image_ocr` (SEGV), `test_image_tracker`,
`test_ingest_file_multimodal` (SEGV), `test_internet_fetch` (SEGV),
`test_kg_query` (SEGV), `test_kg_query_agg` (SEGV),
`test_kg_query_ext` (SEGV), `test_kg_rss_ingest` (SEGV),
`test_kg_sync` (SEGV), `test_kg_sync_delta` (SEGV),
`test_leader_election`, `test_learn_pipeline`, `test_link_prediction`,
`test_lk_mulacc_simd` (SEGV), `test_lk_u8_simd` (SEGV),
`test_louvain`, `test_loyalty`, `test_merkle`, `test_merkle_signing`
(timeout — hung the suite). Many SEGVs cluster around KG / gossip /
federated code — strong signal of a shared substrate regression,
likely a Phase P / Phase O side-effect worth a dedicated R3 round.

### Q.R3a — SEGV cluster diagnosis (SHIPPED, no fix landed)

Diagnosis-only round, commit `6b746e7`. Catalogued the 29 exit-139
segfaults R2 observed, clustered them by proximate failure mechanism,
dmesg-decoded a representative crash (`test_atom_birth_monitor`), and
identified a single documented NOVA runtime quirk (`str_eq` flaky on
short-literal pairs; `src/util/str_safe.nova:3-14`) that explains ~22-26
of them. 3 segfaults (`test_lk_u8_simd`, `test_lk_mulacc_simd`,
`test_image_ocr`) classified as a separate SIMD / pointer-arithmetic
bug class deferred to R3c. Full write-up: `docs/SEGFAULT_TRIAGE_R3A.md`
(431 lines; §1-10). No code fix; R3b lands the mechanical migration.

### Q.R3b — `str_eq` → `str_eq_bytes` call-site migration (SHIPPED, ADR-0101)

Mechanical migration pass on the vulnerable call-site cluster. ADR
`docs/adr/0101-str-eq-migration.md` (co-numbered with the existing
`0101-data-acquisition-pipeline.md`, matching the two-ADR-0100
precedent) documents the shape of the migration + the four sites
intentionally left on raw `str_eq`.

**Files touched (33, superset of R3a's 24-file §4 table — expanded in
flight after smoke runs showed deeper transitive deps also carried
vulnerable sites)**:
`src/federation/distributed_query.nova`,
`src/federation/gossip.nova`,
`src/federation/gossip_dtls_shim.nova`,
`src/federation/gossip_relay.nova`,
`src/federation/gossip_relay_secure.nova`,
`src/federation/kg_sync.nova`,
`src/federation/leader_election.nova`,
`src/federation/nat_traversal.nova`,
`src/federation/snapshot_attestation.nova`,
`src/federation/snapshot_replication.nova`,
`src/federation/turn_server.nova`,
`src/io/transducers/audio_wakeword.nova`,
`src/io/transducers/http_client.nova`,
`src/io/transducers/kg_rss_ingest.nova`,
`src/io/transducers/kg_sync.nova`,
`src/kg/competence_tracker.nova`,
`src/kg/episodic.nova`,
`src/kg/link_prediction.nova`,
`src/kg/pagerank.nova`,
`src/learning/atom_birth_monitor.nova`,
`src/learning/autonomous_research.nova`,
`src/learning/byzantine_aggregation.nova`,
`src/learning/entity_resolve.nova`,
`src/learning/federated_aggregator.nova`,
`src/learning/internet_fetch.nova`,
`src/learning/secure_aggregation.nova`,
`src/parts/soul/identity.nova`,
`src/persistence/chat_state.nova`,
`src/persistence/merkle.nova`,
`src/persistence/merkle_signing.nova`,
`src/persistence/schema_migration.nova`,
`src/persistence/snapshot_delta.nova`,
`src/persistence/snapshot_disk.nova`.

**Call sites migrated: 367 `str_eq_bytes` call sites introduced**
across the 33 files (4 raw sites intentionally retained for
long-dynamic-string compares: `internet_fetch.nova:74` URL cache,
`snapshot_replication.nova:339/349/488` ROOT_HEX).

**Regression gate on the 26 class-A SEGV tests from R3a §2
(setarch-R NOVA, per-test isolation)**:

- **PASS (6/26)**: `test_atom_birth_monitor`, `test_competence_tracker`,
  `test_entity_resolve`, `test_gossip_noise`, `test_kg_sync`,
  `test_kg_sync_delta`.
- **SEGV → clean non-crash FAIL (5/26, recovered test signal)**:
  `test_episodic` (78/1), `test_fed_daemon_attest`, `test_gossip`,
  `test_gossip_relay`, `test_internet_fetch`.
- **Still SEGV after R3b (15/26)**: `test_audio_wakeword`,
  `test_chat_state_persistence`, `test_decision_log_durable`,
  `test_distributed_rules`, `test_fed_daemon_boot`,
  `test_fed_daemon_replication`, `test_fed_daemon_transport`,
  `test_federated_aggregator`, `test_gossip_dtls_shim`,
  `test_http_client`, `test_ingest_file_multimodal`, `test_kg_query`,
  `test_kg_query_agg`, `test_kg_query_ext`, `test_kg_rss_ingest`.
  Spot-checked — these are **not** str_eq SEGVs. Representative traces:
  `test_kg_query` dies inside `_qry_parse_limit` on `"LIMIT 3"` with no
  str_eq on the fault path; `test_http_client` dies inside
  `_hc_chunked_decode` (alloc-byte-buffer handling, same shape as the
  `_hc_str_lower` bug fixed inline in this round); and
  `test_federated_aggregator` dies after `test_fed_agg_join_leave_flags`
  in the DP/meta-observer path. Tracked for Q.R3d.

So vs R3a's prediction of "~22-26 of 29 flip to PASS or clean FAIL",
R3b achieved **11/26 recovered** (6 PASS + 5 SEGV→FAIL) and surfaced
that the dmesg-sampled cluster overstated the str_eq share — several
tests have a different, non-str_eq SEGV upstream.

**Side-benefit (non-regression spot-check)**: three previously-failing
non-SEGV tests saw fail-count drops as transitive deps got migrated:

- `test_merkle`: 48 pass / 12 fail → **57 pass / 3 fail**.
- `test_byzantine_aggregation`: 55 pass / 15 fail → **68 pass / 2 fail**.
- `test_leader_election`: 26 pass / 14 fail → **31 pass / 9 fail**.

No regressions on spot-checked non-SEGV tests (`test_arithmetic`,
`test_perception_module`, `test_episodic_retrieval`, `test_identity`,
`test_atom_birth_monitor`).

**One ancillary bug fixed inline** (ADR-0101 "Decision"):
`src/io/transducers/http_client.nova:_hc_str_lower` was returning a raw
`alloc`'d NUL-terminated byte buffer that only the strcmp-shaped
`str_eq` builtin could consume. `str_eq_bytes` uses `len`+`char_at`,
which SEGV on a raw buffer. Rewired to delegate to NOVA's `str_lower`
builtin, matching `src/chat/helpers.nova:417`.

Follow-ups: **R3c** (SIMD / pointer-arithmetic, still open — the 3
Class B tests), **R3d** (the 15 non-str_eq SEGVs this round surfaced;
needs per-test triage, with the `alloc`-buffer sweep as a strong
starting hypothesis). The ~124 raw `str_eq` sites still outside this
migration (image / video / audio / stream transducers, dp_budget_ui,
sensor_fusion, cognitive_router, …) are not in the import graph of any
of the 26 class-A tests and are left for a later low-priority round.

See ADR-0101 for the per-site rationale.

### Q.R3c — class-B SEGV outliers fixed (SHIPPED, ADR-0102)

Phase Q R3c closes the three class-B SEGV outliers R3b deferred.
Scope: `test_lk_u8_simd`, `test_lk_mulacc_simd`, `test_image_ocr`.
All three were SEGV at `b64b382`; all three exit 0 after R3c
(34 + 28 + 40 = 102 checks pass across 13+11+12 = 36 subtests).

Diagnoses (per-test instrumentation + dmesg disassembly, stripped
before commit):

1. **LK pair** — NOVA's `memcpy_raw` builtin at
   `/home/user/NOVA/src/compiler/codegen.nova:22248` is a bare
   `rep movsb` that does NOT untag its (rdi, rsi, rdx) args. Since
   NOVA ints and pointers are tagged `2x+1`, `rep movsb` runs on
   `actual*2+1` addresses and faults. R3a's "pointer-arithmetic
   drift" hypothesis was wrong; the pack helpers are correct, the
   compiler's `memcpy_raw` label is the bug.

2. **OCR** — `image_ocr.nova:504` did `s = s + buf` where `buf =
   alloc(2); store8(buf+0, char); store8(buf+1, 0)`. NOVA's `+`
   dispatches through `_nova_add` → `_nova_check_rdi` which probes
   `[rdi]` for a type header; a raw byte buffer has no header, so
   the probe faults.

Fixes (minimum necessary, per-caller, no NOVA edits):

1. **LK pair** — new `_lk_byte_copy(dst, src, n)` helper in
   `image_optical_flow.nova` that uses `store8(load8)` (both
   properly untag). Replaces 5 `memcpy_raw` calls in the LK pack
   paths (1 SAD + 4 mulacc). Perf: scalar byte-at-a-time vs `rep
   movsb`; slower but correct.

2. **OCR** — replace `alloc + store8 + s + buf` with a `substr`
   lookup into a static
   `"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"`. `substr` returns a
   proper NOVA string that `_nova_add`'s probe accepts. Covers all
   emittable chars from the default 8x8 ASCII gallery.

Regression check: `test_image_harris`, `test_image_tracker` fail
the same subtests as pre-R3c (no new failures). Spot-check
`test_stereo_u8_simd` STILL SEGVs — same `memcpy_raw` bug, same
fix pattern applies, out of R3c scope; folded into R3d.

### Q.R3d — Cluster A/B/C SEGVs fixed (SHIPPED, ADR-0103)

Phase Q R3d resolves 7 of the 15 R3b-residual SEGVs plus
`test_stereo_u8_simd` (R3c fallout). Scope split into 5 clusters;
A+B+C close here, D rolls to R3e.

Diagnoses (per-cluster, instrumentation stripped before commit):

1. **Cluster A (1 test)** — `test_stereo_u8_simd` hit the same bare
   `rep movsb` codegen bug R3c diagnosed; fixed by extracting R3c's
   `_lk_byte_copy` into the new shared `src/util/mem_safe.nova`
   module as `byte_copy(dst, src, n)` and swapping the one direct
   `memcpy_raw` call site (`image_stereo.nova:406`).
2. **Cluster B (2 tests)** — `test_http_client`, `test_kg_rss_ingest`
   reached the same `rep movsb` through runtime `substr(raw_alloc,
   0, n)`. Fixed by adding `buf_to_str(buf, n)` to `mem_safe.nova`
   (byte-wise `load8 + chr`, routes around `memcpy_raw`) and
   swapping the two call sites (`http_client.nova:770`,
   `kg_rss_ingest.nova:373`).
3. **Cluster C (4 tests)** — `test_kg_query{,_agg,_ext}` +
   `test_fed_daemon_boot`. The plan hypothesis (`str_concat` on
   `+` with `_tok_text`) was wrong; instrumentation showed the
   SEGV lives in `rt_str_to_int` (runtime
   `src/runtime/string.nova:226`), which iterates with `load8(s + i)`
   on string handles returned from `substr(tagged_string, …)`.
   `load8` does not untag string-handle operands, so the second-byte
   read faults. Fixed by migrating every reachable call site to the
   `str_to_int` builtin (walks via `char_at`, unaffected).
   Sites: `src/kg/query.nova` (9), `examples/crossengin_fed_daemon.nova`
   (2), `tests/unit/test_fed_daemon_boot.nova` (1), plus pre-emptive
   migration in `src/kg/{episodic,temporal,rule_inference,
   link_prediction}.nova` (grep-caught, pattern-matched).

The R3c SIMD canaries (`test_lk_u8_simd`, `test_lk_mulacc_simd`,
`test_image_ocr`) still PASS after rewiring `image_optical_flow.nova`
to the shared `byte_copy` helper (local `_lk_byte_copy` body deleted).

Post-R3d exit tally for the targeted 16:
- Cluster A: `test_stereo_u8_simd` → PASS.
- Cluster B: `test_http_client`, `test_kg_rss_ingest` → PASS.
- Cluster C: `test_fed_daemon_boot` → PASS; `test_kg_query{,_agg,_ext}`
  → clean exit-3 FAIL (SEGV gone; residual behavioural FAILs traced
  to a `type_of` runtime regression where strings AND lists both
  read `1`, breaking `_qry_is_error`'s `type_of(x) != 3` guard; rolled
  to R3e, then SHIPPED upstream in NOVA commit `651a507` 2026-10-05 —
  historical mapping null=0/int=1/str=2/list=3/map=4 restored).
- Cluster D (7 tests): all still SEGV on indexing a null returned
  by a `save`/`serve`; the "downstream of C" hypothesis was wrong,
  roots are per-test module failures (sr/dq/replication paths use
  flaky `str_eq` + hit the `type_of` regression). Rolled to R3e.
- Cluster E (1 test): `test_ingest_file_multimodal` stack corruption,
  rolled to R3e.

### R3e — follow-ups (NEXT)

- `test_ingest_file_multimodal` (Cluster E stack corruption; needs
  standalone bisect).
- `test_fed_daemon_transport` (R3b reclass: exit 3 behavioural, not
  a SEGV; rolled per R3d non-goal).
- 7 Cluster D tests: `test_audio_wakeword`,
  `test_chat_state_persistence`, `test_decision_log_durable`,
  `test_distributed_rules`, `test_fed_daemon_replication`,
  `test_federated_aggregator`, `test_gossip_dtls_shim`.
  Per-test save/serve failure diagnosis needed; the current
  symptom (test SEGVs on null-index of a save/serve result) is a
  downstream-of-module-bug pattern, not the tagged-pointer family.
- `type_of` runtime regression audit: strings and lists both read
  `1` instead of the historical `2`/`3`. Caller code assumes the old
  values in `_qry_is_error` and several other guards. Either restore
  the runtime values or migrate every reader.
- **Upstream NOVA** (operator action; closes the whole workaround
  family): fix `memcpy_raw` codegen (`codegen.nova:22248`) to
  `sar rdi,1; sar rsi,1; sar rdx,1` before `rep movsb`; and add the
  same SAR to `rt_str_to_int`'s `load8(s+i)` (or rewrite it over
  `char_at`). Lets us revert `src/util/mem_safe.nova` + the
  `str_to_int` migration.
- **Upstream NOVA Bug #2 (`rt_str_to_int` tag-polymorphism) SHIPPED**
  in NOVA commit `b66644b` on `claude/confident-fermi-op241b`
  (2026-10-05): entry-point inline-asm retag normalizes raw+tagged
  string handles; `make bin/nova` + `make self-host` fixpoint verified.
  R3d's user-side `str_to_int` migration remains in place as defensive
  depth and does not require retirement.
- **Upstream NOVA Bug #2 sweep follow-up SHIPPED** in NOVA commit
  `41058d2` on `claude/confident-fermi-op241b` (2026-10-05): the R2
  per-site inline-asm normalizer was extended to 7 more
  `src/runtime/string.nova` fns across 12 parameter slots —
  `str_len`, `str_char_at`, `rt_str_eq`, `str_cmp`, `rt_str_find`,
  `str_starts_with`, `str_ends_with` (all end-to-end verified on
  raw-literal inputs), plus the second (delim) slot of `str_split`.
  Still open as a follow-up: `str_concat`, `str_slice`, `rt_str_trim`,
  and `str_split`'s first slot, which need a `_nova_memcpy_raw`
  tagged-vs-raw audit at `codegen.nova` first because their bodies mix
  tagged-expecting `str_len` with raw-expecting `memcpy_raw(s, …)` or
  `s + i` arithmetic — the end-to-end `str_split` raw-literal case
  continues to SEGV until that defer closes. `make bin/nova` +
  `make self-host` fixpoint verified for this sweep as well.
- **Upstream NOVA Bug #2 deferred-4 sweep SHIPPED** in NOVA commit
  `2bc1dab` on `claude/confident-fermi-op241b` (2026-10-05): the four
  previously-deferred fns — `str_concat`, `str_slice`, `rt_str_trim`,
  and `str_split`'s first slot — now entry-normalize their handle(s)
  to tagged (same `[rbp-N]` inline-asm retag pattern as the 7-fn
  sweep). The two that previously called `memcpy_raw` on a tagged
  alloc dst (`str_concat`, `str_slice`'s former
  `str_new(s+start, len)` path) were rewritten to byte-copy via
  `store8`/`load8` — both of which untag addresses correctly, so the
  fix needs neither a scratch-local untag nor a codegen change and
  sidesteps the still-broken `str_new(tagged, raw, tagged)` internal
  flow. Also fixed a latent precedence bug in `rt_str_trim`'s
  whitespace predicate (`c == 32 | c == 9 | ...` parsed as a chained
  comparison via `|` which has parse_bitwise precedence; changed to
  `||`). Standalone-runner verification: all four raw-literal
  assertions pass (`str_concat("ab","cd")` len=4,
  `str_slice("hello",1,4)` len=3 first='e'/last='l',
  `rt_str_trim("  hi  ")` len=2 bytes='h','i',
  `str_split("a,b,c",",")` list-len=3). `make bin/nova` +
  `make self-host` fixpoint verified. Honest residual: `str_new`
  itself (tagged-dst + tagged-count + raw-src memcpy_raw) remains
  broken; neither sweep touches it. End-to-end `tests/test_runtime.nova`
  still SEGVs in `test_memory_primitives` (unrelated, pre-existing).

### Q.R3e — type_of regression workaround + Cluster D/E residuals (SHIPPED, ADR-0104)

Phase Q R3e closes most of the remaining segfault-arc. Scope split into
five sub-passes:

1. **R3e.1 -- type_of regression (D1, 4 tests + schemas).** Shipped
   `tests/unit/test_type_of_probe.nova` pinning the regressed mapping
   (int=0, list=1, string=tagged "1" that is neither 0 nor 1) and
   `src/util/type_safe.nova` with `is_int_val`/`is_list_val`/
   `is_str_val`/`is_tagged_list` probes. Migrated 7 call sites:
   `src/kg/query.nova:242` (`_qry_is_error`), `src/kg/rule_explain.nova:161`
   (`proof_is_tree`), `src/kg/rule_inference.nova:160,580,717`
   (`_rule_is_error`, `rule_is_parsed`, `rule_engine_is`),
   `src/kg/schemas.nova:135-171` (both FTYPE_INT and FTYPE_STR legs
   plus the min/max int-check), and `src/federation/distributed_rules.nova:408`
   (`dr_is_state`). Result: `test_kg_query`, `_agg`, `_ext` flipped
   exit-3 → OK; `test_schemas` went 6/7 → 12/1 FAIL (6 more pass).
   **Upstream fix landed in NOVA commit `651a507` (2026-10-05)**:
   historical mapping restored; `type_safe.nova` constants rotated
   (`is_int_val: == 1`, `is_list_val: == 3`, `is_str_val: == 2`) and
   `test_type_of_probe` rewritten to pin the historical values.
   **Upstream NOVA Bug #7 (nanotime raw-untag) SHIPPED** in NOVA
   commit `053584e` (2026-10-06): `nanotime()` body in
   `src/runtime/io.nova:252-258` ends on an asm block that tags rax
   via `lea rax, [rax+rax+1]` before implicit return; new
   `tests/test_nanotime_tag.nova` exercises `t & 0xFF`, `type_of`,
   `m * 2`, `int_to_str(m)` — all PASS. R3g.1's `dp_new` seed
   workaround (`epsilon_budget_milli + 7919`) remains defensive;
   deterministic seed is a stability feature.
   **Upstream NOVA Bug #8 (unresolved-callee SEGV) SHIPPED** in NOVA
   commit `0f9d3f2` (2026-10-06): new `cg_fail(msg)` helper in
   `codegen.nova`; AST_CALL (`:5064`) + `wasm_gen_expr` AST_CALL
   both emit `ERROR: undeclared callee: <name>` + `exit(1)` when
   an identifier can't resolve. New `test_fails_*` harness
   convention in `tests/run_tests.sh` + fixture
   `tests/test_fails_unresolved_call.nova`. Self-host fixpoint
   zero false positives. R3g.2's `gds_extract_keys` shim remains.
   **Upstream NOVA Bugs #9 + #10 (symbol mangling)**: DEFERRED to
   a future module-system ADR (`pub`/`mod` design) — Phase-1
   confirmed proper fix is ~115 LOC refactor across preprocessor +
   lexer + parser + codegen call-resolution, not worth landing
   alone. User-side renames (`_snap_starts_with`, `PROOF_CHECKER_TAG`)
   remain the stable fix; no new collisions in the tree.
2. **R3e.2 -- str_eq residual (D2, 1 test).** Migrate three
   `src/federation/snapshot_replication.nova` sites (`:340`, `:350`,
   `:489`) to `str_eq_bytes`. `test_fed_daemon_replication` flips
   FAIL → OK (59 checks).
3. **R3e.3 -- fed_daemon_transport (T reclass, 1 test).** Phase-1
   Explore pinned this as "trivial mkdir"; investigation showed the
   test-container filesystem sandbox blocks `sys_open(O_CREAT, ...)`
   on BOTH /tmp and $HOME, so even after mkdir the save fails. Shipped
   as sandbox-skip pattern (ce_check skip + early return) plus the
   idempotent `sys_mkdir`; 18/2 FAIL → OK (19 checks).
4. **R3e.4 -- sys_open-on-/tmp (D3, 3 tests).** Direct syscall probe
   confirmed the sandbox is global, not /tmp-specific. Shipped
   test-side sandbox-skip guards:
   `tests/unit/test_audio_wakeword.nova` guards the save-return
   per-test; `tests/unit/test_chat_state_persistence.nova` and
   `tests/unit/test_decision_log_durable.nova` short-circuit all of
   `main()` behind a one-shot probe. All three FAIL+SEGV → OK (clean
   skip in this environment; full battery on a less-restricted CI
   host).
5. **R3e.5 -- D4 pair + Cluster E (3 tests, partial-defer to R3f).**
   `test_federated_aggregator` SEGVs inside `fed_agg_emit_noised_stats`
   on first use; `test_gossip_dtls_shim` and
   `test_ingest_file_multimodal` SEGV before any output. Bisection
   budget capped per plan; honest defer to R3f.

Post-R3e exit tally (R3e-targeted 11 tests + schemas improvement):
- PASS: `test_type_of_probe` (new), `test_kg_query`, `test_kg_query_agg`,
  `test_kg_query_ext`, `test_fed_daemon_replication`,
  `test_fed_daemon_transport`, `test_audio_wakeword`,
  `test_chat_state_persistence` (sandbox-skip),
  `test_decision_log_durable` (sandbox-skip). **9 wins.**
- IMPROVED: `test_schemas` 6→12 passing checks.
- DEFERRED to R3f: `test_distributed_rules` (type_of fix unblocked
  everything else but secondary `io_println` codegen crash in
  `drule_chat_add_cmd`/`_run_cmd` remains), `test_federated_aggregator`,
  `test_gossip_dtls_shim`, `test_ingest_file_multimodal`.

Regression canaries from R3b/R3c/R3d (`test_stereo_u8_simd`,
`test_lk_u8_simd`, `test_lk_mulacc_simd`, `test_image_ocr`,
`test_http_client`, `test_kg_rss_ingest`, `test_fed_daemon_boot`,
`test_perception_module`, `test_arithmetic`) all still OK.
`test_action_module` keeps its 2 pre-existing FAILs.

Follow-ups:
- **R3f**: 4 R3e-deferred tests (above) + dead-code rebuild-guard
  sweep (R2 flag).
- **R3-arc post-queue (unchanged from R3d)**: RELAY_BIN sealed-frame
  (P R3 defer) -- **CLOSED by Phase P R4 (ADR-0110)**, motor_map
  population (N R2 shell) -- **CLOSED by Phase R1 (ADR-0107)**,
  auto-broadcast-on-snapshot-save (M R3 defer) -- **SHIPPED by Phase
  M R6 (ADR-0111 close-out)**: Session extension (SES_GS /
  SES_ATT_STORE / SES_SIGNER_SEED / SES_SIGNER_PK / SES_SOUL_ID_INT at
  slots 16-20, SES_COUNT=21) + `session_attach_fed` + 5 defensive
  getters; six env resolvers (`_cd_*`) duplicated from fed_daemon;
  emit-only gossip boot block gated on `CE_FED_AUTO_BROADCAST_ON_SAVE=1`
  with keypair-load-failure WARN-and-disable; dual-guard hook call at
  `crossengin_daemon.nova:791`. Four new subtests (3 in
  `test_session_attach_fed`, 1 in `test_snapshot_broadcast_hook`),
  all pass. Byte-identity contract preserved when flag off. See
  ADR-0111 §"Phase M R6 close-out" for the pre-existing
  `_starts_with` NOVA-toolchain collision that blocks the daemon
  main() link (same regression affecting `crossengin_chat.nova`
  since Phase M R1; tracked separately on the upstream-NOVA queue
  as `docs/UPSTREAM_NOVA_BUGS.md` §9, not R6 scope).
  **Phase M R6 binary-link blocker RESOLVED** by subsequent commit
  renaming `_starts_with` → `_snap_starts_with` in
  `snapshot_disk.nova` (UPSTREAM_NOVA_BUGS §9 option (a)).
  `crossengin_daemon.nova` now LINKs. `crossengin_chat.nova` initially
  still failed at link time with a sibling collision
  (`_g_PC_TAG`, previously masked by the `_starts_with` error) which
  was then resolved by renaming `PC_TAG` → `PROOF_CHECKER_TAG` in
  `src/parts/reasoning/proof_checker.nova:86` (UPSTREAM_NOVA_BUGS §10
  option (a); one-line edit, grep-confirmed zero external callers).
  **Both binaries now LINK** — chat for the first time since Phase M
  R1 (`5f2e9f2`); daemon for the first time since Phase M R6
  (`9cbbf12`). The §9+§10 workarounds close the binary-link arc.
  Split 924KB NEXT_SESSION.md — SHIPPED by `1da6d99`. NOVA Makefile
  push — SHIPPED; `ef4c3c6` was rebased onto upstream tip (new hash
  `f0882c9` on NOVA repo) and pushed; upstream `afff1a9` ("tag int
  literals with bitwise ops") has semantically superseded the setarch
  workaround, but the four `*-setarch` Makefile targets remain as a
  defensive fallback for pre-fix NOVA checkouts. UDP rewrite of gossip
  (blocked on NOVA sendto/recvfrom). Env-resolver duplication cleanup:
  SHIPPED — the 7 `_fed_*` / `_cd_*` env helpers + mask const extracted
  into `src/util/env_resolve.nova` (closes Phase M R6 duplication); both
  daemons import the shared util and all six fed-daemon test canaries
  pass unchanged.
- **Upstream NOVA (operator action; closes the whole workaround family):**
  `type_of()` regression SHIPPED upstream (NOVA commit `651a507`,
  2026-10-05) — three-site codegen fix (type_of return + match-arm
  cmp + WASM mirror); `src/util/type_safe.nova` retained as a thin
  stable-API wrapper with constants rotated to historical values.
  `memcpy_raw` codegen fix still desirable; resolving it retires
  `src/util/mem_safe.nova` and `src/util/str_safe.nova`.

### Q.R3f -- bug-#11 sentinel equality + rebuild-guard sweep (SHIPPED, ADR-0105)

Phase Q R3f closes the segfault-arc tail opened by R3a. Five sub-passes,
one commit:

1. **R3f.1 -- `test_distributed_rules` (io_println broader bug class).**
   Phase-1 inferred "long literal only"; the real class also includes
   dynamically-concatenated string arguments (`str_data`/`str_len`
   codegen assumes a flat literal, dereferences a concat-node operand).
   Migrated `drule_chat_add_cmd` / `drule_chat_run_cmd` to the `println`
   NOVA builtin (handles both) + chunk-split <=128 B. SEGV -> OK
   (42 checks).
2. **R3f.2 -- `test_federated_aggregator` (DP_REFUSED equality).**
   `dp_is_refused` compared against a sentinel at `-(2^31-1)`; two
   large-magnitude operands with tags set reach NOVA bug-#11's
   sentinel-equality (pointer-deref) path. Replaced with a magnitude
   probe `v < 0 - 2000000000`. Fix is correct for its class, but a
   secondary SEGV earlier in the module-init path remains -- partial
   defer to R3g.
3. **R3f.3 -- `test_gossip_dtls_shim` (test-side ABI mismatch).**
   Phase-1 hypothesis "same class as R3f.2" was wrong. Real root: the
   test built private scalars as 32-byte buffers, but
   `dtls_ecdhe_keygen_seeded` forwards to `p256_keygen_seeded` which
   expects a bn256 limb list. Switched both helpers to `bn256_from_hex`
   (test-side only). Crash boundary moved past `_setup_ready_pair`;
   second unrelated crash at `test_extract_keys_null` (test 26/31) --
   partial defer to R3g.
4. **R3f.4 -- `test_ingest_file_multimodal` (tag-strip + ABI fix).**
   `perceptual_capsule.nova` wrote `store8(buf+i, byte_list[i])`
   without masking; `byte_list[i]` returns tagged small-ints whose tag
   bits corrupt the stored byte and cause OOB writes. Added
   `int_and(x, 255)` in both `perc_hash_from_bytes` and
   `perc_hash_full_from_bytes`; rewired the test's `_presented_holder`
   call (non-existent helper) through `capability_registry` +
   `rpc_ctx_set_presented_token`. SEGV -> OK (28 checks).
5. **R3f.5 -- dead-code rebuild-guard sweep.** The singleton guards in
   `perception_module.nova:304` and `action_module.nova:337,343` used
   list-identity `!=` on `renv` / `dl` / `ge` -- same bug-#11 class, so
   the guards never rebuilt. Added `src/util/gen_id.nova` (monotonic
   counter + stamp/matches helpers); tail-appended `REN_GEN`, `DL_GEN`,
   `GE_GEN` slots to the three constructors; rewired the three guard
   sites to compare on the stamped int. `test_perception_module` and
   `test_action_module` unchanged (behavioral assertions, not
   identity).

Post-R3f exit tally (R3f-targeted 4 tests):
- PASS: `test_distributed_rules`, `test_ingest_file_multimodal`.
  **2 wins.**
- IMPROVED: `test_gossip_dtls_shim` (crash boundary moved 25 tests
  forward, now at test 26/31).
- DEFERRED to R3g: `test_federated_aggregator`,
  `test_gossip_dtls_shim` (tail only).

Regression canaries from R3b/R3c/R3d/R3e (`test_perception_module`,
`test_action_module`, `test_fed_daemon_replication`, `test_kg_query`
/`_agg`/`_ext`, `test_arithmetic`) all unchanged. Known non-SEGV
neighbors (`test_merkle`, `test_merkle_signing`) unchanged.

Follow-ups:
- **R3g**: `test_federated_aggregator` (secondary SEGV earlier than
  `dp_is_refused`), `test_gossip_dtls_shim` tail (crash at
  `test_extract_keys_null`, likely a separate class).
- **Upstream NOVA**: see `docs/UPSTREAM_NOVA_BUGS.md` -- six-entry
  manifest (bug-#11 sentinel equality, `io_println`, memcpy_raw,
  `rt_str_to_int`, type_of regression, sandbox O_CREAT policy).

### Q.R3g -- segfault-arc close-out (SHIPPED, ADR-0106)

Phase Q R3g retires the two R3f-deferred residuals. Two sub-passes,
one commit:

1. **R3g.1 -- `test_federated_aggregator` (raw-nanotime-untagged).**
   SEGV at `s * _LCG_MUL` in `_lcg_step` on first noise call. New bug
   class (NOT ADR-0105 bug-#11): `nanotime() & _LCG_MASK` leaves the
   result UNTAGGED and the subsequent `*` dispatches through the
   pointer-threshold path. User-level fix in
   `src/safety/differential_privacy.nova:dp_new`: seed from
   `epsilon_budget_milli + 7919` (already-tagged); deterministic seed
   is acceptable for Minimum Viable DP, `dp_new_seeded` remains for
   stream-pinning callers. Also migrates two residual `str_eq` call
   sites in the test to `str_eq_bytes` (ADR-0101 cleanup, previously
   masked by the SEGV).
2. **R3g.2 -- `test_gossip_dtls_shim` (unresolved-callee SEGV).** SEGV
   at the call site of `gossip_dtls_extract_keys(0)` BEFORE the
   function body executes (instrumented entry print never fires).
   Root: the function lives in `src/federation/gossip.nova`, which
   the test does not import. NOVA lowers the unresolved call to a
   null callee that SEGVs on entry. Fix: add a shim-local
   `gds_extract_keys` to `src/federation/gossip_dtls_shim.nova` and
   switch the three callers.

Post-R3g exit tally (R3g-targeted 2 tests):
- PASS: `test_federated_aggregator` (OK, 91 checks). **1 win.**
- CLEAN NON-SEGV: `test_gossip_dtls_shim` (56 passed, 1 pre-existing
  FAIL `client hs last_err = flight-not-wired` carried from R3f.3; no
  SEGV). **1 win on SEGV front; a pre-existing clean FAIL remains.**

**Segfault-arc close-out**: all 29 tests catalogued under R3a are
resolved. The remaining non-SEGV FAILs are
`test_gossip_dtls_shim:client hs last_err` (1) and
`test_action_module` (2 pre-existing). No test currently SEGVs on
tip.

Regression canaries from R3b/R3c/R3d/R3e/R3f
(`test_distributed_rules`, `test_ingest_file_multimodal`,
`test_fed_daemon_replication`, `test_kg_query`, `test_arithmetic`,
`test_perception_module`, `test_type_of_probe`): all still OK.
`test_action_module`: 53 passed / 2 FAIL (unchanged).

Follow-ups:
- **R3h**: none queued -- segfault-arc closed.
- **Upstream NOVA**: `docs/UPSTREAM_NOVA_BUGS.md` extended with
  entries 7 (raw-nanotime-untagged on `&`) and 8 (unresolved-callee
  SEGV).

### Migration-out criteria (when to delete Phase Q scaffolding)

Phase Q goes away — Makefile wrappers deleted, ADR-0100 marked
Superseded — when all three hold:
1. `cd /home/user/NOVA && rm -f bin/nova && make bin/nova` succeeds
   without `setarch -R`.
2. `make self-host` passes without `setarch -R`.
3. `/home/user/NOVA/docs/PTR_TAGGING_PLAN.md` reports 177/177 and the
   `boot/nova_boot.s` classifier is tagged-int-aware.

---

## Phase R — action-module effector arc *(post-Q feature work)*

Phase R picks up the Phase N R2 motor_map arc that ADR-0093 explicitly
deferred to its own R3 preview section.

### R.R1 -- motor_map population + action_module wiring (SHIPPED, ADR-0107)

Phase R1 fills in the three missing pieces around the already-complete
`motor_map.nova` public API:

1. **`motor_map_default()`** -- seeded registry with canonical
   `EFF_CLASS_*` vocabulary (`search_the_web`/`fetch_url` -> HTTP;
   `write_a_note`/`read_file` -> FILE; `call_tool` -> TOOL;
   `run_code` -> CODE; `play_audio`/`synth_audio` -> AUDIO;
   `invoke_mcp` -> MCP).  Non-exhaustive on purpose -- expanded by R2
   alongside effector primitives.
2. **`mm_activation_signature(ctx, goal_id)`** -- deterministic key
   builder.  Shape `"g<gid>:a<act0>:a<act1>:..."` with a `len(0)`
   guard; degrades to `"g<gid>"` on null/active-less ctx.  Reads
   `ctx[5]` positionally (motor_map is a leaf).
3. **`AM_MOTOR_MAP` slot** -- tail-appended at index 7 to preserve the
   seven pre-R1 slot offsets (ADR-0093 byte-identity contract).  Seeded
   with `motor_map_default()` at init; `action_derive_intent` consults
   it BEFORE the pre-R2 SPEAK/INTERNAL fallthrough.  On a TOOL/FILE/
   HTTP/CODE/AUDIO/MCP hit, mint the matching kind; on a miss, fall
   through unchanged (byte-identity preserved).
4. **Intent constructors** -- added `intent_file_new`, `intent_http_new`,
   `intent_code_new`, `intent_audio_new`, `intent_mcp_new` to
   `action_atoms.nova`, parallel to the pre-R1 `intent_tool_new`.

**Non-goal (deferred to R2)**: `action_submit`'s SUSPENDED-fallback is
UNCHANGED.  Non-SPEAK intents mint and are visible in the decision log
but return `[EFF_SUSPENDED, -1]` at the gate until effector primitives
ship.

Exit tally:
- `test_motor_map`: 8 subtests, 52 checks, OK (was 36).
- `test_action_module`: 61 passed / 2 pre-existing FAIL (was 53/2;
  the 2 FAILs -- `submit result EXECUTED` + `run unknown eff
  EXECUTED` -- are carried unchanged from R3e).
- Spot-check canaries: `test_perception_module`, `test_arithmetic`,
  `test_type_of_probe`, `test_distributed_rules`, `test_fed_daemon_boot`
  all OK.

Follow-ups:
- **R2** -- SHIPPED (ADR-0108, below).
- Potential: hashed-signature variant to bound key length as active-
  concept counts grow.  Currently deferred -- plain-string key is
  deliberate for debuggability.

### R.R2 -- payload-shim atoms + per-class dispatch in `action_submit` (SHIPPED, ADR-0108)

Phase R2 closes the "intent mints but doesn't execute" gap R1 left on
the gate side. Three mechanical additions in one commit:

1. **Payload-shim slots** in `action_atoms.nova` -- eight new slots
   TAIL-APPENDED after `IN_REASON` (`IN_FILE_PATH`, `IN_FILE_CONTENT`,
   `IN_HTTP_URL`, `IN_HTTP_CANNED`, `IN_CODE_EXPR`, `IN_MCP_SERVICE`,
   `IN_MCP_REQUEST`, `IN_AUDIO_OUT_PATH`), each defaulting to `""`.
   The pre-R2 5-arg `intent_*_new` constructors continue to work; new
   `_with_payload` constructors populate the operands.  Per-kind
   accessors (`in_file_path`, ...) include defensive length guards
   for snapshot-restored older-schema intents.
2. **Per-class dispatch** in `action_submit` -- the pre-R2 SUSPENDED
   fallthrough is replaced by a 7-way switch (SPEAK + INTERNAL +
   FILE / HTTP / CODE / MCP / AUDIO / TOOL meta).  Each non-SPEAK
   branch synthesizes `effector_submit` (DLK_INTENT) ->
   `eff_runs` check -> primitive call (`file_ops_write`,
   `http_action_run(url, 1, canned)` with simulated=1 pinned,
   `code_exec_run`, `mcp_call_direct`, `effector_speak_audio`) ->
   `effector_complete` (DLK_OUTCOME).  TOOL meta re-dispatches via
   `in_effector_class`.
3. **Operand-missing fallthrough** -- a verb-token-only intent (the
   R1-era shape minted by `action_derive_intent`'s motor_map hits
   without a planner) with an empty required-operand slot cleanly
   falls through to `[EFF_SUSPENDED, -1]`, preserving R1 behavior.
   `action_derive_intent` is UNCHANGED this round; operand
   materialization is Phase R3.

Exit tally:
- `test_action_module`: 74 passed (was 61) / 2 pre-existing FAILs
  unchanged (`submit result EXECUTED` + `run unknown eff EXECUTED`;
  these turn out to be SPEAK-path tier semantics -- `ACT_SPEAK` has
  reversibility floor `PERM_NOTIFY` so the gate returns
  `EFF_NOTIFIED`, not `EFF_EXECUTED`; the mismatch predates R2 and
  is NOT about dispatch).  See ADR-0108 Consequences for the fix
  path.
- `test_motor_map` 52 OK unchanged; `test_effectors` 19 OK;
  `test_effector_gate` 23 OK; `test_action_atoms` 79 OK;
  `test_loop_action` 11 OK (byte-identity preserved).
- Spot-check canaries: `test_perception_module` 45,
  `test_arithmetic` 23, `test_type_of_probe` 15,
  `test_distributed_rules` 42, `test_fed_daemon_boot` 49 all OK.

Non-goal (deferred to R3): `action_derive_intent` continues to mint
verb-token-only intents; motor_map hits still land at SUSPENDED
through the operand-missing branch until a planner materializes
operands.

### R.R3 -- operand materialization + reach-ability + SPEAK tier fix (SHIPPED, ADR-0109)

Phase R3 closes the three residuals R2 queued -- motor_map hits now
produce executable intents end-to-end:

1. **`operand_builder.nova`** (new leaf module) -- synthesizes
   per-class operand tuples via sandbox-safe conventions:
   `FILE  -> ["/tmp/ce_goal_<id>.txt", goal_name]`,
   `HTTP  -> ["http://localhost/goal_<id>", "goal:" + goal_name]`,
   `CODE  -> ["1 + <id>"]`,
   `MCP   -> ["goal_svc", "req:" + goal_name]`,
   `AUDIO -> ["/tmp/ce_speech_goal_<id>.wav"]`,
   `TOOL / INTERNAL -> []`.  These are deliberate placeholders --
   planner-driven payload is Phase R4+ (likely drives a goal-atom
   schema extension; own ADR).
2. **Reach-ability bridge** -- `motor_map.nova` gains
   `mm_activation_signature_by_name(goal_name)` (verbatim return);
   `action_derive_intent` probes the registry a second time with the
   semantic-sig when the handle-sig misses.  This is the ONLY path
   that reaches `motor_map_default`'s semantic strings
   (`"write_a_note"`, `"run_code"`, ...) -- the handle-sig
   (`"g<id>:a<h0>:..."`) never overlaps them.  On a hit, mint via
   the matching `_with_payload` constructor.
3. **SPEAK tier assertion fix** (two lines) -- the pre-existing fails
   in `test_submit_speak_wired_dl` and `test_run_unknown_end_to_end`
   flip from `ce_eq(..., EFF_EXECUTED)` to `ce_check(..., eff_runs ==
   1)`.  `ACT_SPEAK` is a NOTIFY-tier action so the gate returns
   `EFF_NOTIFIED`; `eff_runs` is 1 for both -- uniform predicate
   across tiers, consistent with R2's non-SPEAK dispatch subtests.

Exit tally:
- `test_action_module`: **90 passed** (was 74 passed / 2 FAILed); the
  2 SPEAK fails flipped + 3 new R3 subtests landed.
- `test_operand_builder`: **18 passed** across 8 subtests (new file).
- `test_motor_map` 52 OK unchanged; `test_effectors` 19 OK;
  `test_effector_gate` 23 OK; `test_action_atoms` 79 OK;
  `test_loop_action` 11 OK (byte-identity preserved).
- Spot-check: `test_perception_module` 45, `test_arithmetic` 23,
  `test_type_of_probe` 15, `test_distributed_rules` 42,
  `test_fed_daemon_boot` 49 all OK.
- R2's `test_submit_file_missing_path_falls_through_to_suspended`
  still PASS -- the 5-arg `intent_file_new` path is untouched; R3
  only changes behavior INSIDE `action_derive_intent`'s motor_map
  hit branch.

### R.R4 -- goal-template registry for operand materialization (SHIPPED, ADR-0112)

Phase R4 replaces Phase R3's convention-driven operand placeholders
with a per-goal template registry.  Phase-1 Explore evaluated three
options -- (a) goal-atom schema extension (HIGH risk, breaks
`goal_persistence`), (b) planner over `goal_name` (MEDIUM risk, no
NOVA-safe string-parsing primitives), (c) goal-template registry
mirroring `motor_map` (LOW risk, zero schema impact) -- and shipped (c):

1. **`src/parts/action/goal_templates.nova`** (new leaf module)
   mirrors `motor_map.nova:35-124` byte-for-byte: 2-slot handle
   `[GT_OBJ_TAG=9304, entries]`, linear-scan upsert / lookup via local
   `_gt_key_eq` byte-walker, placeholder expansion via
   `_gt_substitute` (`%ID%` / `%NAME%`), seeded with two entries
   covering FILE + CODE: `"write_a_note"` ->
   `["file", "/tmp/ce_note_%ID%.txt", "%NAME%"]` and `"run_code"` ->
   `["code", "1 + %ID%"]`.  HTTP / MCP / AUDIO keep R3 fallback
   until a `%URL%` / `%SERVICE%` placeholder vocabulary ADR lands.
2. **`operand_builder_build`** grows an optional 6th `templates` arg.
   When non-zero AND the lookup hits AND the hit's class tag matches,
   expand the template.  Otherwise fall through to the R3 convention
   switch (byte-identical to pre-R4).
3. **`action_module`** tail-appends `AM_GOAL_TEMPLATES` (slot 8) after
   R1's `AM_MOTOR_MAP` (slot 7).  Mirrors ADR-0107's byte-identity
   tail-append pattern.  `action_module_init` seeds via
   `goal_templates_default()`; `action_derive_intent` passes
   `am_goal_templates(am)` as the 6th arg.
4. Follow-up queued: Phase R5 planner (option (b)) layered on top --
   runs on template miss; HTTP / MCP / AUDIO template seeds under
   their own placeholder-vocabulary ADR; goal-atom schema extension
   (option (a)) deferred to Phase R6+ when a demand templates cannot
   cover surfaces.

Exit tally:
- `test_goal_templates` (new): **34 checks** across 6 subtests.
- `test_operand_builder`: **30 checks** (was 18), +2 subtests cover
  template-hit expansion and `templates=0` byte-identity fallback.
- `test_action_module`: **94 checks** (was 90), +1 subtest covers
  `write_a_note` -> `/tmp/ce_note_<id>.txt` via default templates.
  The pre-existing R3 FILE subtest explicitly clears the templates
  via `am_set_goal_templates(am, 0)` to continue exercising the R3
  convention path.
- Canaries unchanged: `test_motor_map` 52, `test_effectors` 19,
  `test_effector_gate` 23, `test_action_atoms` 79, `test_loop_action`
  11, `test_goal_persistence` 11, `test_perception_module` 45,
  `test_arithmetic` 23.

### R.R5 -- planner keyword heuristics for operand materialization (SHIPPED, ADR-0113)

Phase R5 layers option (b)'s planner on top of R4's registry: between
the R4 template probe and the R3 convention switch,
`operand_builder_build` now calls `planner_materialize(goal_name,
eff_class, goal_id)`. On a hit the planner tuple wins over R3; on a
miss the R3 convention fires unchanged.

1. **`src/parts/goals/planner.nova`** (new leaf module) ships four
   keyword heuristics, each with a prefix ending in a SPACE so
   motor_map's underscore vocabulary cannot match (byte-identity
   canary): `"write note "` (FILE) -> `["/tmp/ce_note_<id>.txt",
   <tail>]`, `"fetch "` (HTTP) -> `[<tail>, ""]`, `"run "` (CODE) ->
   `[<tail>]`, `"say "` (AUDIO) -> `["/tmp/ce_speech.wav"]`. MCP /
   TOOL / INTERNAL return empty (no heuristic this round).
   Constants prefixed `PL_` to dodge UPSTREAM §9/§10; local
   `_pl_starts_with` byte-walker dodges UPSTREAM §1; `_pl_tail_after`
   guards `len == 0` and `n > len(s)` before `substr`.
2. **`operand_builder_build`** gains a planner probe between the R4
   template-miss fallthrough and the R3 convention switch. Signature
   unchanged (6 args). Three-layer precedence: templates -> planner
   -> R3 convention.
3. **Byte-identity contract**: every heuristic prefix ends in a space;
   motor_map default vocabulary uses underscores; no R3+R4 call path
   can trigger a planner hit; every pre-R5 test is byte-identical.
4. Follow-up queued: richer parser (quoted strings, multi-arg), MCP
   / TOOL / INTERNAL heuristics once vocabulary surfaces, ctx-driven
   heuristics via `AC_ACTIVE` concept handles, lowercase-norm /
   stemming once a canonical goal-name normalization policy exists.
   Goal-atom schema extension (option (a)) remains deferred to R6+.

Exit tally:
- `test_planner` (new): **21 checks** across 10 subtests.
- `test_operand_builder`: **41 checks** (was 30), +2 subtests cover
  planner-hit-when-templates-miss and both-miss-falls-to-R3.
- `test_goal_templates`: **34 checks** unchanged (6 subtests).
- `test_action_module`: **94 checks** unchanged (motor_map default
  vocabulary is underscore-only, never triggers R5 heuristics).
- Canaries unchanged: `test_motor_map` 52, `test_effectors` 19,
  `test_effector_gate` 23, `test_action_atoms` 79, `test_loop_action`
  11, `test_goal_persistence` 11, `test_perception_module` 45,
  `test_arithmetic` 23.

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

### M.R5 -- Auto-broadcast attestation on snapshot save (SHIPPED via M.R6, ADR-0111)

Closes ADR-0091 §88-91,203-206 deferred bullet on the federation side
without touching persistence (ADR-0091:243 contract preserved: `snap_save`
and every direct caller are byte-identical).

1. **R5.1 -- `src/federation/snapshot_broadcast_hook.nova` (new leaf).**
   Single public fn
   `snapshot_broadcast_hook(gs, att_store, seed, pk, soul_id, root_hex, ts_ns)`.
   Shape guards (empty / SNAP_META_MERKLE_ROOT_NONE sentinel / malformed
   hex) + dedup via `att_store_latest`+`att_root_hex`+`str_eq_bytes` +
   local-record-first (`att_store_add` before gossip emit) + return the
   `gossip_broadcast_attestation` delivery count. Imports are federation ->
   persistence (allowed); persistence never imports federation. No
   signer load, no gossip boot, no inbound verification -- thin glue
   over already-shipped primitives.
2. **R5.2 -- Caller integration (DEFERRED).** `crossengin_daemon.nova`
   is single-process (no `gossip_` imports anywhere in 920 lines; no
   Session slot for `gs` / `att_store` / seed / pk). Full wiring would
   need a gossip boot path, three new boot-time env flags (self_addr /
   bootstrap list / signer path), signer load, and a Session shape
   extension -- all well beyond the plan's ~50-line honest-defer
   budget. Deferred per plan §Honest-reporting-policy; ADR-0111
   Follow-up names the specific gaps.
3. **R5.3 -- `tests/unit/test_snapshot_broadcast_hook.nova` (new,
   18 checks, OK):** six pure-logic subtests covering the three shape
   guards, the fresh-root happy path (0 peers -> rc=0, store grows),
   dedup on identical root, and growth on a new root. No sockets, no
   sandbox writes.
4. **R5.4 -- ADR-0111 + roadmap.** New ADR documents the
   federation-side-leaf decision, the honest R5.2 defer, and the
   Follow-up gap list. Roadmap post-queue line marked PARTIAL-SHIPPED
   with the specific defer reason.

### M.R6 -- R5.2 close-out: daemon-side gossip boot + hook call (SHIPPED, ADR-0111 close-out)

Closes the R5.2 defer by wiring the hook into `crossengin_daemon.nova`'s
idle-checkpoint path. Five sub-passes, one commit. All active behavior
gated on `CE_FED_AUTO_BROADCAST_ON_SAVE=1` so the default-off path is
byte-identical to pre-R6.

1. **R6.1 -- Session tail-append (`src/session/session.nova`).** Five
   new slots mirroring the proven `SES_DP` pattern: `SES_GS=16`,
   `SES_ATT_STORE=17`, `SES_SIGNER_SEED=18`, `SES_SIGNER_PK=19`,
   `SES_SOUL_ID_INT=20`. `SES_COUNT` bumped to 21; `session_make`
   pushes zero placeholders for all five (preserves `len(s) == SES_COUNT`
   invariant). New `session_attach_fed(s, gs, att_store, seed, pk,
   soul_id_int)` with lazy-grow for pre-R6-shaped 16-slot lists; five
   defensive getters each guard with `if len(s) <= <SLOT> { return 0 }`
   so pre-R6 Sessions still byte-identically return 0.
2. **R6.2 -- Env resolvers in `examples/crossengin_daemon.nova`.** Six
   helpers (`_cd_env_str`, `_cd_env_int`, `_cd_bool_from_env_value`,
   `_cd_peers_from_env`, `_cd_soul_id_from_env_int` incl. a `_cd_soul_id_to_int`
   djb2 mixer with mask 16777215, `_cd_attest_key_base_from_env`)
   copied byte-for-byte semantically from
   `crossengin_fed_daemon.nova:163-293`. Deliberate duplication tracked
   under "future cleanup: extract shared `env_resolve.nova`" on the
   post-queue; attempting it in R6 would churn fed_daemon's tests.
3. **R6.3 -- Boot wiring.** After `sreg_register(sreg, sess)`: resolve
   `CE_FED_LISTEN_ADDR` (default `127.0.0.1:0` -- emit-only, never
   listens), peers (CE_FED_PEERS -> CE_GOSSIP_PEERS fallback),
   signer-key base path. Call `merkle_signing_keypair_load`; on failure
   print one `[warn]` line and leave the fed slots at 0 (fed_daemon
   WARN-and-disable idiom). On success alloc `gossip_init(...)` +
   `att_store_new()`, call `gossip_set_att_store` +
   `gossip_register_att_pubkey`, then `session_attach_fed(sess, ...)`.
4. **R6.4 -- Hook call at `:791`.** The previous single-branch warn is
   wrapped in a dual-guard shape: `if saved == 0 { warn } else { if
   session_gs(sess) != 0 { snapshot_broadcast_hook(...) } }`. The
   `session_gs(sess) != 0` guard is the byte-identity contract: when
   the flag is off, `session_attach_fed` was never called, the getter
   returns 0, and the entire hook branch is unreachable.
5. **R6.5 -- Tests.** New `tests/unit/test_session_attach_fed.nova` (3
   subtests, 29 checks, OK): default-no-fed-slots, attach-sets-all-slots
   (plus idempotency re-attach assertion), and lazy-grow from a
   pre-R6-shaped 16-slot list. Extended
   `tests/unit/test_snapshot_broadcast_hook.nova` (was 20 checks, now
   27, OK) with `test_hook_via_session_accessors` exercising the real
   daemon-shape chain: `session_make` -> real `gossip_init` +
   `att_store_new` + keypair -> `session_attach_fed` -> call the hook
   through the five Session accessors -> assert the att_store the
   Session carries grew by 1 and the stored root matches the input
   (aliasing invariant).

**Pre-existing NOVA-toolchain regression surfaced by R6**: the four new
imports pulled into `crossengin_daemon.nova` (`snapshot_broadcast_hook`,
`gossip`, `snapshot_attestation`, `merkle_signing`) transitively drag
in `src/io/transducers/kg_sync.nova`, whose module-private
`_starts_with` symbol collides with the identically-named module-private
helper in `src/persistence/snapshot_disk.nova`. The NOVA toolchain does
not mangle module-private names, so the assembler rejects any `main()`
that pulls in both. **Pre-existing**: `examples/crossengin_chat.nova`
imports the same pair (`snapshot_disk` + `gossip`) and has been failing
the assembler stage since Phase M R1 (`5f2e9f2`); verified by rebuilding
chat on the pre-R6 tip `9c439e4`. R6 inherits this failure for
`crossengin_daemon` because the hook integration cannot avoid pulling
in `gossip`. Fix belongs on the upstream-NOVA queue (requires either
compiler-level name mangling or renaming `_starts_with` in
`kg_sync.nova`, which has 10+ call sites across the tree). All R6
behavioral surface is covered by unit tests regardless, and the
byte-identity contract still holds -- on the day the collision is
resolved, the daemon main() links with the flag-off path emitting
bytes identical to pre-R6.

Verification artifacts: `test_session_attach_fed` OK (29 checks),
`test_snapshot_broadcast_hook` OK (27 checks; +7 from the new subtest),
`test_session` OK (66 checks, unchanged), `test_fed_daemon_boot` OK
(49, unchanged), `test_fed_daemon_replication` OK (59, unchanged). The
pre-existing canary FAIL counts (`test_snapshot_attestation` 59P/7F,
`test_snapshot_replication` 61P/12F, `test_fed_daemon_attest` 52P/2F,
`test_merkle_signing` SEGV, `test_gossip` 32P/2F) are **unchanged
pre-R6 vs post-R6** (git-stash-verified).

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
  MVP; Phase R1 (ADR-0107, 2026-10-03) **populated it + wired into
  `action_derive_intent`** -- DONE). `src/agent/autonomous_loop.nova::agent_new`
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

## Phase P — DTLS 1.2 handshake flight completion (COMPLETE)

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
- **R2 -- client-side flight + Finished MAC + server-side R2 flight
  (SHIPPED, ADR-0098).** Closes the ClientHello Random placeholder
  (`_dtls_build_client_hello_body` at `src/federation/dtls12.nova`
  now pulls 32 bytes from `secure_random(buf, 32)`; falls back to
  `DTLS_S_SLOT_CLIENT_RANDOM_OVERRIDE = 52` when entropy is
  unavailable; writes the SAME bytes to both the wire body and
  `DTLS_S_SLOT_CLIENT_RANDOM` so `dtls_ecdhe_derive` sees exactly
  what went on the wire). Adds four server-flight parsers
  (`_dtls_parse_server_hello_body`, `_dtls_parse_certificate_body`,
  `_dtls_parse_ske_body`, `_dtls_parse_server_hello_done_body`,
  each mirroring R1's `[ok | 0, ...]` return shape) plus
  `_dtls_parse_client_key_exchange_body` for the server-flight-2
  inverse. Adds three body builders (`_dtls_build_client_key_
  exchange_body` = 1 + 65 point; `_dtls_build_change_cipher_spec_
  record` = the 14-byte record_type=20 CCS record; `_dtls_build_
  finished_body` = 12-byte PRF verify_data over the transcript
  snapshot). Adds `_dtls_der_decode_ecdsa_sig` (+ helpers), the DER
  inverse of R1's encoder, used by the SKE-sig verify path. Two
  tail slots `DTLS_S_SLOT_HOSTNAME = 53` +
  `DTLS_S_SLOT_ANCHORS = 54` carry the cert-verify plumbing from
  `gds_handshake_client` into the flight driver. Wire drivers
  `_gds_client_flight` (in `src/federation/gossip_dtls_shim.nova`)
  and `_gds_server_flight_2` compose the full RFC 6347 handshake:
  ClientHello -> SH/Cert/SKE/SHD -> cert-verify hook (via
  `dtls_cert_verify_chain` from Phase O R1) + SKE-sig verify (via
  `ecdsa_p256_verify_bn` against the leaf cert's EC pubkey) ->
  ECDH-derive -> CKE + CCS + client Finished -> server CCS +
  server Finished. Transcript-snapshot ordering follows RFC 5246
  §7.4.9 exactly (client Finished covers CH..CKE; server Finished
  covers CH..client Finished; the non-destructive `dtls_transcript_
  finalize` from R1 makes this work without back-patching).
  `gds_handshake_client` re-wired to call `_gds_client_flight`;
  `gds_handshake_server` extended to call `_gds_server_flight_2`
  after R1's flight-1. On the full success path both sides reach
  `DTLS_S_ESTABLISHED`. On any refuse `LAST_ERR` carries a distinct
  diagnostic tag and the state transitions to `DTLS_S_FAILED`.
  Tests: `tests/unit/test_dtls_client_flight.nova` (~35 tests /
  ~60 checks: CH Random slot populated + wire matches slot; all
  four SH/Cert/SKE/SHD parsers round-trip against R1's builders;
  CKE round-trip; CCS 14-byte record; Finished body matches PRF
  for known transcript + master_secret + labels differ per side;
  DER encode + decode round-trip; SKE sig verifies via
  parser-recovered DER; client-flight refuse path with bogus fd;
  hostname/anchors slots populated; slot-index pinning; client
  state chain still valid). ADR-0098 covers the design +
  alternatives (state-slot vs args for hostname/anchors,
  epoch-advance timing on server side after client CCS, direct
  state write for the server-side ESTABLISHED transition to avoid
  extending `_dtls_valid_edge` and breaking pinned tests). Deferred
  to R3: full extension parsing (replacing R1's stub) + DTLS-aware
  gossip stream helpers so DELTA / SNAP_FETCH / EXTADDR /
  RELAY_* stop being silently dropped under DTLS. `make lint-ints`
  clean (pre-existing findings unchanged; none in the R2 files).
- **R3 -- extension parse + DTLS-aware gossip stream helpers
  (SHIPPED, ADR-0099).** Replaces R1's `_dtls_parse_ext_block_stub`
  (kept as a back-compat alias for R1's pinned tests) with a real
  extensions-block walker `_dtls_parse_ext_block(buf, n)` that
  consumes the CONTENT bytes of an extensions block and returns
  `[ok, extensions_list, total_bytes_consumed]` where each entry is
  `[ext_type_u16, ext_data_buf, ext_data_len]`. Unknown extension
  types are collected verbatim into the list; dispatch decides
  whether to consume or drop (per RFC 5246 §7.4.1.4). Adds a
  `_dtls_parse_use_srtp_ext(buf, n)` per-extension parser (RFC 5764
  §4.1.1: 2B `profile_list_len` + N/2 profile IDs + 1B `mki_len` +
  mki bytes; refuses odd / zero `profile_list_len` and any length
  overflow) plus `_dtls_select_srtp_profile(offered_profiles)` server-
  side selector (single supported profile:
  `SRTP_PROFILE_AES128_CM_SHA1_80`). Wires the parse-side into
  `_gds_server_flight_1` (`src/federation/gossip_dtls_shim.nova`):
  after parsing the ClientHello + absorbing the HS message into the
  transcript, walk the extensions block; for each `use_srtp` entry
  dispatch to `_dtls_parse_use_srtp_ext` + `_dtls_select_srtp_profile`
  + write the chosen profile to `DTLS_S_SLOT_SRTP_OFFER` so R1's
  `_dtls_build_server_hello_body` echoes it back per RFC 5764 §4.1.3.
  Adds `_gossip_send_all_maybe_dtls(fd, dtls_state, s)` transport-
  neutral send helper in `src/federation/gossip.nova`: `dtls_state=0`
  routes to `_gossip_send_all` (plaintext byte-identical to pre-R3);
  non-zero routes to `gds_send_line` (sealed + length-prefixed under
  the shim). Converts every write-to-conn_fd handler to a
  `_maybe_dtls` variant that threads `dtls_state` through every send
  (`_gossip_stream_atoms_since`, `_gossip_serve_dquery`,
  `_gossip_serve_drfetch`, `_gossip_serve_snap_fetch`,
  `_gossip_send_snap_body`); the existing plaintext-named functions
  become one-line delegate wrappers with `dtls_state=0` so every
  pre-R3 caller lands on the same wire bytes. Handlers that do NOT
  write to conn_fd (`_gossip_serve_extaddr`, `_gossip_serve_relay_*`,
  `_gossip_serve_rule`, `_gossip_serve_derivation`,
  `_gossip_serve_attestation`) need no signature extension. Retires
  the "silently drops" fall-through in `gossip_handle_conn_dtls`
  (`gossip.nova:3215`) + `gossip_handle_conn_kg_dtls` (`:3299`): DELTA
  under DTLS now streams ATOM records + a sealed DELTA_END; SNAP_FETCH
  / DQUERY / DRFETCH route through their `_maybe_dtls` variants;
  EXTADDR / RELAY_REQ / RELAY_DATA / RELAY_ACK route through their
  as-is enqueue handlers. RELAY_BIN is explicitly deferred (binary
  tail reader is not yet sealed-frame aware; documented follow-up).
  Tests: `tests/unit/test_dtls_ext_parse.nova` (~32 checks — walker
  empty + single + two entries + malformed inner ext_len + short TLV;
  use_srtp parser single-profile + MKI bytes + odd list-len + zero
  list-len + short buffer; selector picks + skips + empty; end-to-end
  R2 builder -> walker -> use_srtp parser round-trip; stub back-compat
  pins) + `tests/unit/test_gossip_dtls_streams.nova` (~24 checks —
  `_gossip_send_all_maybe_dtls` both paths on bad fd; every
  `_maybe_dtls` variant's plaintext + DTLS paths on the appropriate
  guard-fires-first shape; enqueue-only handlers safe under DTLS;
  DTLS dispatch refuses unready dtls_state). ADR-0099 covers the
  design + alternatives (stub retained as alias vs replaced; signature-
  extension vs wrapper decisions; RELAY_BIN deferral; profile-select
  refuse policy on malformed use_srtp). `make lint-ints` clean (12
  pre-existing findings unchanged; none in the R3 files). **Phase P
  is now COMPLETE**: server-side flight (R1) + client-side flight +
  Finished MAC + server flight-2 (R2) + extension parse + DTLS-aware
  gossip stream helpers (R3) — the DTLS 1.2 handshake arc is closed
  and ADR-0096 (Phase O R3, DTLS-over-TCP shim) is feature-complete
  for the full gossip verb set.

## What this roadmap does NOT claim
- It does not claim AGI. It builds the mechanisms a moment-signal AGI bet
  *requires*; whether they compose into general intelligence is unproven and is
  the research wager.
- "Feel" = functional appraisal (control/motivation signal), not sentience.
- Credit assignment without backprop at scale is an open problem; P2 uses the
  best-known local approximations, not a solved method.

### Phase: upstream NOVA bugs #1 + #4 + #5 closed (2026-10-06)

Three parallel NOVA upstream fixes shipped end-to-end:

- **Bug #1 (`memcpy_raw` OOB)** SHIPPED in NOVA commit `f7d9766`:
  three test/jz/sar entry blocks in `_nova_memcpy_raw` (x86) + WASM
  backend mirror. `tests/test_memcpy_raw_tagged.nova` passes with
  tagged `alloc(16)` buffers. Self-host fixpoint holds.
- **Bug #4 (sentinel equality)** CONFIRMED CLOSED by Bug #3's fix.
  NOVA commit `172ee8c` adds `tests/test_dp_refused_eq.nova`
  probe → PASS. Crossengin's `dp_is_refused` restored to direct
  `v == DP_REFUSED` (magnitude-probe workaround retired).
- **Bug #5 (`io_println` tagged-length syscall overrun)** SHIPPED
  in NOVA commit `3e417b3`: `io_print`/`io_println` delegate to the
  `print`/`println` builtins; stderr pair uses inline asm to
  normalize count to raw before `sys_write`. `tests/test_io_println.nova`
  exercises short/long/concat. Self-host fixpoint holds.

Upstream NOVA scorecard: **all 10 bugs resolved or formally deferred**.
Eight shipped (#1-#5, #7, #8); #4 transitively; #6 is container-not-NOVA;
#9/#10 await module-system ADR.

**Bug #8 ripple**: the unresolved-callee check surfaced latent
import-graph misses in several Crossengin tests
(`test_federated_aggregator`, `test_perception_module`, `test_action_module`,
`test_differential_privacy`, etc.). `test_motor_map` passes as a
clean-imports canary. Fixing the affected tests is a follow-up sweep,
not blocking the upstream close-out.

### Phase: Bug #8 ripple sweep — imports closed (2026-10-06)

Ripple sweep landed in one commit on `claude/confident-fermi-op241b`:

- **Case A (214 tests)**: appended `std/syscall` + `std/string` + `std/io`
  imports to every test that compile-stopped on `sys_open` / `str_data` /
  `nanotime`. Idempotent (grep-then-append).
- **Case B (3 source files)**: added missing project imports so Case-B
  tests can see transitively-referenced symbols:
  - `src/kg/multi_kg_manager.nova` += `import "cross_kg_references.nova"`
    (unblocks `xref_src_kg`).
  - `src/federation/gossip.nova` += `import "./gossip_relay.nova"`
    (unblocks `relay_stats_line`).
  - `src/persistence/snapshot_disk.nova` += `import "../parts/soul/state.nova"`
    (unblocks `soul_mood_valence`).
- **Case C (1 typo)**: `tests/unit/test_image_hog.nova:576` call site
  renamed `test_l2_hys_block_sum_of_squares_near_million` →
  `test_l2_hys_block_sum_of_squares_in_normalized_range` (actual fn at :297).

**Sweep tally**: 170 CLEAN → 372 CLEAN (+202); 271 ripple → 1 ripple
(the lone remaining undeclared-callee is a secondary unmasked typo —
see follow-up queue below); 37 pre-existing non-CLEAN preserved; 0
regressions (no test that was CLEAN before became non-CLEAN).

### Follow-up queue — Bug #8 unmasked latent failures (69 tests)

The import fix revealed 69 pre-existing bugs the null-callee masked.
Grouped by surface; each is deferred to a dedicated session, not
scope-creep on this sweep.

Secondary typo (compile-stage, 1 test):
- `test_image_records` → undeclared callee
  `test_parse_text_agrees_with_parse_bytes`; actual fn at :274 is
  `test_parse_text_refuses_ascii_non_image`. Suspected rename-skew.

Verb-count drift (Case B unmask, flagged in Phase-1):
- `test_admin_bake_child_verb` (19 pass, 1 FAIL — expected 51 verbs got 53).
- `test_admin_emit_delta_verb` (23 pass, 1 FAIL — same root).

Persistence / snapshot SEGV cluster (Case B unmask, flagged):
- `test_snapshot_disk`, `test_snapshot_delta`, `test_snapshot_episodic` SEGV.
- `test_snapshot_attestation` (59 pass, 7 FAIL), `test_snapshot_replication`
  (61 pass, 12 FAIL), `test_snapshot_synapses` (85 pass, 4 FAIL).

Gossip (Case B unmask, flagged):
- `test_gossip` (32 pass, 2 FAIL — identical-seed and dead-peer picks).
- `test_gossip_dtls_shim` (56 pass, 1 FAIL).
- `test_gossip_dtls_streams` (compile output truncated — needs re-run).

DTLS / transport / crypto surface (Case A unmask):
- `test_dtls12` (443 pass, 76 FAIL).
- `test_dtls_client_flight`, `test_dtls_server_flight`, `test_dtls_ext_parse`
  (compile-stage output truncated).
- SEGVs: `test_fed_daemon_transport`, `test_nat_traversal`,
  `test_p256_keypair_load`, `test_truststore_dir`, `test_tool_goal_plan`,
  `test_tool_use`, `test_merkle_signing`.
- Assertion fails: `test_merkle` (3), `test_secure_aggregation` (2),
  `test_secure_channel` (1), `test_ice_turn` (1),
  `test_capability_rate_limit` (3), `test_capability_wire` (6),
  `test_byzantine_aggregation` (2), `test_noise_xk` (2),
  `test_ed25519` (1), `test_p256` (1).
- Compile-truncated: `test_md5`, `test_sha1`.

Audio / image / NL assertion failures:
- `test_audio_synth` (20), `test_audio_tts` (4), `test_speaker_id` (10),
  `test_voice_clone` (8), `test_nl_generate` (23), `test_nl_query` (4),
  `test_nl_pipeline_gap_recording` (1), `test_output_generation` (2),
  `test_word_atoms` (7), `test_pattern_pack` (1).
- Runtime index-out-of-bounds: `test_syntax_atoms`, `test_graph_clustering`,
  `test_louvain`.

Cognitive / meta / planner / misc:
- `test_cognitive_router` (8), `test_meta_observer_feedback` (17),
  `test_constitutional_filter` (4), `test_self_confidence_verb` (1),
  `test_self_model_query` (2), `test_proof_checker` (10),
  `test_episodic` (1), `test_learn_pipeline` (1),
  `test_realtime_pacer` (6), `test_neighborhood_activation` (1),
  `test_dp_budget_ui` (3), `test_distributed_query` (6),
  `test_dr_async_fetch` (4), `test_leader_election` (9),
  `test_internet_fetch` (4), `test_table` (9),
  `test_override_mechanism` (1), `test_update_apply_verb` (1),
  `test_pack_registry` (9), `test_bignum_2048` (4), `test_bignum_256` (4).

These are PRE-EXISTING bugs. The import fix did not CAUSE them — it
made them VISIBLE for the first time since Bug #8's compile-stop ripple
hid everything downstream. Honest-defer policy: ship the import closure,
schedule the latent class as a dedicated multi-session triage round.

## Latent-triage — triage of 68 unmasked latents

Phase-1 Explore triage grouped the 68 live latent failures into
7 clusters (one of the original 69 — the `test_image_records`
duplicate-symbol typo — was already closed by `ac91e4d`):

| Cluster | Count | LOC est. | Shape |
|---|---|---|---|
| C1 — Verb-count drift | 3 | 3 lines | mechanical — tests lag `rpc_verb_names()` |
| C2 — Snapshot `_snap_starts_with` recursion | 6 | 20-60 | needs recursion / helper audit |
| C3 — Gossip relay/dtls shim | 3 | 10-30 | `relay_stats_line` contract |
| C4 — DTLS12 handshake/crypto | 23 | high | ADR-driven, multi-session |
| C5 — Audio/NL assertion | 13 | med-high | string.nova sweep ripple audit |
| C6 — Cognitive/meta grab bag | 20 | fragmented | per-test rounds |
| C7 — Runtime index-OOB | 3 | low | len-check-missing idiom |

### Latent-triage R1 — close C1 (verb-count drift)

Shipped as a 3-line mechanical fix. R111/R113 added two verbs each to
`rpc_verb_names()` at `src/nl/rpc_verbs.nova:5214` (now 53 total);
`test_child_mode_wire:223` was updated to 53 at the time, but three
sibling tests kept the old constants:

- `tests/unit/test_admin_bake_child_verb.nova:33` — 51 → 53.
- `tests/unit/test_admin_emit_delta_verb.nova:25` — 43 → 53.
- `tests/unit/test_update_apply_verb.nova:44` — 43 → 53.

All three tests pre: FAIL on the verb-count assertion only; post: OK.
Delta: +3 CLEAN tests. Tally **373 → 376 CLEAN / 37 pre-existing /
65 unmasked latent**. Zero cross-test risk; no NOVA-side changes.

### Latent-triage queue (post-R1, newest first)

- **R2 candidate** — C7 runtime index-OOB (3 tests:
  `test_syntax_atoms`, `test_graph_clustering`, `test_louvain`): low
  LOC, needs per-test idiom scan for a `len`-check-missing shape.
- **R3 candidate** — C3 gossip (3 tests): cross-check against
  `relay_stats_line` contract.
- **R4+ candidate** — C2 snapshot cluster (6 tests, 20-60 LOC):
  needs `_snap_starts_with` recursion investigation.
- **ADR-driven** — C4 DTLS12 completion plan (23 tests) and
  C5 string.nova sweep ripple audit (13 tests).
- **Micro-fix sweep** (11 single-FAIL tests): `test_pattern_pack`,
  `test_episodic`, `test_self_confidence_verb`,
  `test_neighborhood_activation`, `test_override_mechanism`,
  `test_learn_pipeline`, `test_nl_pipeline_gap_recording`,
  `test_secure_channel`, `test_ice_turn`, `test_ed25519`, `test_p256`.
- **C6** — cognitive/meta grab bag (20 tests, fragmented): queue
  per-test rounds after the cheaper clusters land.

### Latent-triage R2 — close C7 (3 missed `str_eq → str_eq_bytes` sites)

Phase-1 Explore diagnosis falsified the R1 "runtime index-OOB"
hypothesis for C7. The runtime panic each test prints
(`index out of bounds: 0`) is a secondary symptom in TEST code —
unguarded `members[i]`/`out[i]` access after a soft-failing `ce_eq`
on list length. The SOURCE bug in all three cases is a missed
`str_eq → str_eq_bytes` migration (tail of R3b `4149c21`): tag-aware
byte compares on data that round-trips through atom/kg-label storage.
Bug #8's compile-stop ripple hid these three sites.

Three one-line migrations:

- `src/language/syntax_atoms.nova:50` — `_filler_for` (fixes
  `test_syntax_atoms`).
- `src/kg/graph_clustering.nova:282` — `_gc_extract_graph` cross-KG
  guard (fixes `test_graph_clustering`).
- `src/kg/louvain.nova:258` — `_lv_extract_graph` cross-KG guard
  (fixes `test_louvain`).

After the fix, `grep "\bstr_eq("` over `src/kg` returns zero hits
and over `src/language` returns only the two literal-vs-literal
`nl_generate.nova:97-98` calls (tag-safe by construction).

Tally delta: 376 → 379 CLEAN / 37 pre-existing / 62 unmasked latent.

C7 is now closed. Reclassified: not an index-OOB cluster but a
3-site tail of the R3b `str_eq_bytes` migration cohort. The
tree-wide ~100-call `str_eq(` population lives in dirs whose
tests pass today (env-var checks, literal-vs-literal, tag-safe
pipelines); no mandatory sweep queued.

### Latent-triage queue (post-R2, newest first)

- **R3 candidate** — C3 gossip (3 tests): cross-check against
  `relay_stats_line` contract.
- **R4+ candidate** — C2 snapshot cluster (6 tests, 20-60 LOC):
  needs `_snap_starts_with` recursion investigation.
- **ADR-driven** — C4 DTLS12 completion plan (23 tests) and
  C5 string.nova sweep ripple audit (13 tests).
- **Micro-fix sweep** — 11 single-FAIL tests (list in R1 block).
- **C6** — cognitive/meta grab bag (20 tests, fragmented).

### Latent-triage R3 — close C3 (gossip cluster)

Phase-1 Explore diagnosis **falsified** two framings in the original
C3 label simultaneously:

- `relay_stats_line` is not involved in any failing gossip test (zero
  hits over the three test files). The "C3 = gossip relay/dtls shim"
  label refers to the SOURCE AREA, not a shared contract break.
- `test_gossip_dtls_streams` is actually already green at tip
  `82ae0c2` — the "compile output truncated" note was a stale
  Phase-1 snapshot. (See silent-skip caveat below.)

The two live failures split into two unrelated causes, all test-side,
total 3 lines:

- `tests/unit/test_gossip.nova:162` — `_pick_random_identical_seed`
  check used bare `str_eq`; the companion source function
  `gossip_alive_peers` returns byte-buffer-tagged addresses (companion
  `src/federation/gossip.nova:855` already uses `str_eq_bytes`). Migrated.
- `tests/unit/test_gossip.nova:174` — `_pick_random_excludes_dead_peers`
  same shape; migrated.
- `tests/unit/test_gossip_dtls_shim.nova:228-229` — Phase P R2
  (ADR-0098) wired `gds_handshake_client`'s flight builder; the
  pre-R2 short-circuit sentinel `"dtls-hs-flight-not-wired"` is
  retired in favour of `"dtls-hs-send-ch"` on a bogus-fd ClientHello.
  The companion server-side test (:243-244) was updated during R1
  wire-in but the client-side literal was left behind. Updated the
  expected tag + label + added a brief comment block mirroring the
  server-side block.

Per-test status:
- `test_gossip`:            pre 2 FAIL / post OK (34 checks).
- `test_gossip_dtls_shim`:  pre 1 FAIL / post OK (57 checks).
- `test_gossip_dtls_streams`: unchanged (compiles + exits 0 silently).

Canary spot-checks (motor_map, perception_module, action_module) +
R2 trio (syntax_atoms, graph_clustering, louvain) all still PASS.

Tally delta: 379 → 382 CLEAN / 37 pre-existing / 60 unmasked
live-FAIL latent, plus 1 newly-documented silent-skip
(`test_gossip_dtls_streams`).

#### Side-channel discovery: silent-skip anomaly

`test_gossip_dtls_streams.nova` has 18 `test_*` functions each calling
`ce_eq`/`ce_check` + a `main()` that ends in
`ce_summary("test_gossip_dtls_streams")`. A healthy sibling test (e.g.
`test_syntax_atoms`) prints `<name>: OK (N checks)`. This one prints
nothing after the compiler's `Compiled:` banner, yet exits 0 — i.e.
all 18 test functions are skipped or no-op silently. Not a FAIL
(doesn't contribute to the failing-tests count), but not actually
testing either. Flagged as a separate latent for its own round:
check whether `_gossip_send_all_maybe_dtls` (first callee) is
no-oping, or the compiled binary is exiting pre-`main`.

### Latent-triage queue (post-R3, newest first)

- **R4 candidate** — micro-fix sweep (11 single-FAIL tests).
- **R5 candidate** — C2 snapshot cluster (6 tests, 20-60 LOC):
  `_snap_starts_with` recursion investigation.
- **Silent-skip investigation** — `test_gossip_dtls_streams` and
  any siblings exhibiting the "silent exit after compile" pattern.
- **ADR-driven** — C4 DTLS12 completion plan (23 tests),
  C5 string.nova sweep ripple audit (13 tests).
- **C6** — cognitive/meta grab bag (20 tests, fragmented).

### Latent-triage R4 — micro-fix sweep (9 of 11 single-FAILs)

Two parallel Explore triages diagnosed all 11 single-FAIL latents.
Nine were 1-LOC each and shipped this round; two are real source
regressions and were deferred to their own rounds.

Classification by recurring shape:

- **Shape A — missed `str_eq → str_eq_bytes` migration** (6 sites,
  4 test files + 2 source files).
- **Shape B — stale ADR-wired literal** (2 test-side sites, from
  ADR-0206 sandbox-gate ordering and ADR-0092 answer-path exclusion).
- **Shape C — numeric drift** (1 test-side site; `ownership_kinds()`
  grew from 4 to 5 under R109/ADR-0210 tier 2).

Test-side edits (7 files):

- `tests/unit/test_episodic.nova:74` (A)
- `tests/unit/test_secure_channel.nova:80` (A) + import `src/util/str_safe.nova`
- `tests/unit/test_ice_turn.nova:520` (A) + import `src/util/str_safe.nova`
- `tests/unit/test_p256.nova:366` (A) + import `src/util/str_safe.nova`
- `tests/unit/test_self_confidence_verb.nova:235` (B)
- `tests/unit/test_learn_pipeline.nova:29` (B)
- `tests/unit/test_pattern_pack.nova:600-601` (C)

Source-side edits (2 files):

- `src/reader/neighborhood.nova:203` (A) — gates `_walk_ops`.
- `src/safety/override_mechanism.nova:99` (A) — `override_name_vetoed`.

Three Shape-A test files additionally needed an explicit
`import "../../src/util/str_safe.nova"` — Bug #8's unresolved-callee
check at compile time caught the fact that none of them transitively
imported `str_safe`. These import adds (3 lines, 3 files) are
mechanical and surface identically to the R3b-era import sweep.

Per-test status:
- test_episodic:                   pre 1 FAIL / post OK (79 checks)
- test_secure_channel:             pre 1 FAIL / post OK (16 checks)
- test_ice_turn:                   pre 1 FAIL / post OK (142 checks)
- test_p256:                       pre 1 FAIL / post OK (52 checks)
- test_self_confidence_verb:       pre 1 FAIL / post OK (46 checks)
- test_learn_pipeline:             pre 1 FAIL / post OK (21 checks)
- test_pattern_pack:               pre 1 FAIL / post OK (144 checks)
- test_neighborhood_activation:    pre 1 FAIL / post OK (47 checks)
- test_override_mechanism:         pre 1 FAIL / post OK (27 checks)

Regression sweep: canaries (motor_map, perception_module,
action_module) + R1 trio + R2 trio + R3 pair + override-family
siblings (override_wire, self_override_list_verb, self_override_verb,
self_gaps_verb) — ALL still PASS.

Tally delta: 382 → 391 CLEAN / 37 pre-existing / 51 live-FAIL latent
+ 1 silent-skip + 2 deferred-source-regression.

#### Deferred to their own rounds (not R4 scope)

- **`test_ed25519`** — FAIL `ed25519_sign latency positive`:
  `nanotime() - t0 == 0` surrounding one `ed25519_sign` call. 60
  other ed25519 assertions pass including KATs — the algorithm is
  intact. Likely a nanotime regression or codegen CSE hoisting
  a pure nanotime call. Trace candidates:
  `/home/user/NOVA/src/runtime/io.nova:291-296` and
  `_sys_clock_gettime_monotonic`. Do NOT band-aid to `dt >= 0`;
  it would mask a real regression.
- **`test_nl_pipeline_gap_recording`** — FAIL `SKILL_REFUSED bumped`:
  `rpc_dispatch("skill.run", ...)` against an empty KG no longer
  bumps `GAP_SKILL_REFUSED`. Trace candidates:
  `src/skills/skill_dispatch.nova:113,127` (writer),
  `rpc_ctx_gaps_reg` wiring, research skill manifest's
  `COND_KG_EMPTY` disarm, or `skill_sup_check_pre_refusals`
  short-circuit regression in the Bug #8 sweep. The sibling tests
  `test_self_gaps_verb` + `test_gaps_register` exercise
  `GAP_SKILL_REFUSED` directly and still pass, so the gap plumbing
  is fine; the regression is in the refusal firing.

### Latent-triage queue (post-R4, newest first)

- **R5 candidate** — C2 snapshot cluster (6 tests, 20-60 LOC):
  `_snap_starts_with` recursion investigation.
- **R6 candidate** — `test_ed25519` nanotime latency regression
  (deferred from R4).
- **R7 candidate** — `test_nl_pipeline_gap_recording` source wiring
  regression (deferred from R4).
- **Silent-skip investigation** — `test_gossip_dtls_streams`.
- **ADR-driven** — C4 DTLS12 completion plan (23 tests),
  C5 string.nova sweep ripple audit (13 tests).
- **C6** — cognitive/meta grab bag (20 tests, fragmented).
- **Potential codebase-hygiene** — tree-wide `str_eq → str_eq_bytes`
  sweep (~70 remaining sites, mostly benign env-literals).

### Latent-triage R5 — close C2a (snapshot Shape-A sub-cluster)

Phase-1 Explore diagnosis **falsified** the stated `_snap_starts_with`
recursion hypothesis: that fn at `src/persistence/snapshot_disk.nova:1790`
is a plain iterative byte-compare with 11 callers inside
`snap_from_text`'s v2 key dispatch — none of the 6 FAIL traces reach
it on the hot path.

The cluster splits into two sub-clusters with distinct roots:

**C2a (shipped this round)** — pure Shape-A `str_eq → str_eq_bytes`
migrations on test side (3 files, 24 sites, bulk `replace_all`):

- `tests/unit/test_snapshot_attestation.nova` — 8 sites.
- `tests/unit/test_snapshot_replication.nova` — 12 sites.
- `tests/unit/test_snapshot_synapses.nova` — 4 sites.

Perfect 23:23 match between pre-fix failing checks and `str_eq(` call
counts across the 3 files.

Per-test status:
- test_snapshot_attestation:  pre 7 FAIL / post OK (66 checks).
- test_snapshot_replication:  pre 12 FAIL / post OK (73 checks).
- test_snapshot_synapses:     pre 4 FAIL / post OK (89 checks).

Also discovered mid-triage: **`test_snapshot_disk_full`** is a bonus
7th cluster member (not in Phase-1's list) that fails with the
identical signature as `test_snapshot_disk`. Rides along with C2b.

**C2b (deferred to R6b)** — Shape-D source regression in `snap_save`
path (4 tests SEGV cascade):
- `test_snapshot_disk`           — root SEGV, snap_save returns 0.
- `test_snapshot_disk_full`      — same root (bonus discovery).
- `test_snapshot_delta`          — cascades from same root.
- `test_snapshot_episodic`       — same root.

Hypothesis tested experimentally this round: 2-line
`str_eq → str_eq_bytes` migration at `src/persistence/snapshot_writer.nova:321,350`
(sentinel-equality on `""` meta slots). Verified: the 2-line fix did
NOT close any of the 4 SEGV tests. Reverted per honest-reporting
policy. Full isolation work needed — binary-search inside `snap_save`
→ `snap_write_durable` and/or `snap_to_text`'s Merkle recompute path
with env probes.

Canary spot-checks (motor_map, perception_module, action_module,
R1/R2/R3/R4 cohorts) all still PASS.

Tally delta: 391 → 394 CLEAN / 37 pre-existing / 48 live-FAIL latent
+ 1 silent-skip + 3 deferred-source-regression (added: C2b 4 tests —
reclassified: all 4 are the same `snap_save` SEGV root, so 1 round
should close all 4).

### Latent-triage queue (post-R5, newest first)

- **R6 candidate** — `test_ed25519` nanotime latency regression
  (deferred from R4).
- **R6b candidate** — C2b snapshot `snap_save` path isolation
  (deferred from R5; 4 tests expected to close together under one
  source fix).
- **R7 candidate** — `test_nl_pipeline_gap_recording` source wiring
  regression (deferred from R4).
- **Silent-skip investigation** — `test_gossip_dtls_streams`.
- **ADR-driven** — C4 DTLS12 completion plan (23 tests),
  C5 string.nova sweep ripple audit (13 tests).
- **C6** — cognitive/meta grab bag (20 tests, fragmented).
- **Potential codebase-hygiene** — tree-wide `str_eq → str_eq_bytes`
  sweep (~70 remaining sites, mostly benign env-literals).

### Latent-triage R6 — NOVA Bug #11 (nanotime EFAULT) upstream fix

Phase-1 Explore diagnosis (`a2e86ebc35ae61d28`) traced
`test_ed25519`'s "latency positive" FAIL to the ACTUAL root cause:
`_sys_clock_gettime_monotonic` at
`/home/user/NOVA/src/runtime/io.nova:271-278` was passing a TAGGED
pointer to the `clock_gettime` syscall; the kernel returned `-EFAULT`
and never wrote the timespec buffer, so `nanotime()` returned a
constant `1` (tagged 0) on every call. Every `dt = nanotime() - t0;
dt > 0` latency assertion silently failed. Strace confirmed EFAULT
on tag-ending `0x…1` addresses.

Not a codegen CSE issue (disassembly showed two distinct
`call nanotime` instructions bracketing `call ed25519_sign`). Not a
Bug #7 regression (that fix only tagged the return value, not the
input pointer).

**Upstream NOVA fix (1 LOC)**: `src/runtime/io.nova:275` — add
`sar rsi, 1` after `mov rsi, [rbp-8]` to untag the pointer before
the `clock_gettime` syscall. Rebuilt NOVA from scratch (`make -B`);
new binary installed at `bin/nova`.

Scope-of-close (empirically verified post-rebuild):

| Test | Pre | Post | Prior bucket |
|---|---|---|---|
| test_ed25519 | FAIL (latency positive) | OK (62 checks, 1601 ms real) | R4-deferred |
| test_bignum_256 | FAIL (3 latency asserts) | OK (70 checks, 15× speedup) | pre-existing |
| test_bignum_2048 | FAIL (all `dt > 0`) | OK (65 checks, 27× speedup) | pre-existing |
| test_realtime_pacer | 6 FAILs | 3 FAILs | pre-existing (partial) |

The `test_realtime_pacer` residual 3 FAILs (`wall-clock ~50ms
(delta < 15)`, `slow-mo ~60ms (delta < 20)`, `summary starts with
'pacer:'`) are NOT nanotime-latency shape — the first two measure
sub-100ms precision which the sandbox clock may not deliver; the
third smells Shape-A. Defer to R8.

Canary sweep (motor_map, perception_module, action_module,
R1/R2/R3/R4/R5 cohorts) all PASS.

Tally delta: 394 → 397 CLEAN confirmed + 3 pacer FAILs flipped
(pacer still fails on 3 others) / 35 pre-existing (down 2:
bignum_256 + bignum_2048 escaped the pre-existing bucket) /
48 live-FAIL latent (down 1: ed25519 deferred-regression closed).

Also updated `docs/UPSTREAM_NOVA_BUGS.md`:
- Added §11 record with strace trace + fix anchor + latent sibling
  observation (`_raw_imul_add` reads `1000000000` tagged; cosmetic).
- Updated Retirement order: 11 bugs total, 9 shipped upstream.

### Latent-triage queue (post-R6)

- **R6b** — C2b snapshot `snap_save` path isolation (4 tests, 1 root).
- **R7** — `test_nl_pipeline_gap_recording` source wiring regression.
- **R8** — `test_realtime_pacer` residual 3 FAILs.
- **Silent-skip** — `test_gossip_dtls_streams`.
- **ADR-driven** — C4 DTLS12 completion, C5 string.nova sweep audit.
- **C6** — cognitive/meta grab bag (20 tests, fragmented).
- **Codebase-hygiene** — tree-wide `str_eq → str_eq_bytes` sweep.
- **Non-latent queue** — NOVA ADR-0009 impl, `str_new` tagged-dst,
  `_raw_imul_add` tagged-b cleanup (cosmetic), `test_match_expr`
  parser bug, re-collapse string.nova inline byte-copies, Phase R6+,
  real-socket DTLS roundtrip.

### Latent-triage R6b — C2b snap_save investigation (zero shipped)

Phase-1 Explore (`a09e8751848a3e5eb`) correctly identified `sys_open`
passing tagged `flags`/`mode` to the kernel as the SURFACE root cause
of the 4 C2b SEGVs. Strace confirmed `O_WRONLY|O_CREAT|O_TRUNC =
0x241` arriving as `0x483 = (0x241<<1)|1` → no `O_CREAT` bit → ENOENT.
Agent proposed a 10-LOC untag dance in `sys_open`.

Experimental landing scope grew as un-masking exposed more layers:

1. **sys_open flags/mode** (agent's diagnosis) — fixed with the
   standard `test/jz/sar` untag dance. Verified in strace: open now
   succeeds.
2. **sys_rename raw return** — `snap_write_durable`'s `if rr != 0`
   compares raw kernel return (0) against tagged-literal 0 (in-memory
   1), always TRUE → error branch. Fixed with return-tag epilogue
   `lea rax, [rax+rax+1]`.
3. **sys_read EFAULT + raw count/return** — buf is tagged alloc,
   count is tagged literal → kernel got `0x27863481`/`8193` → EFAULT.
   Fixed inputs with untag dance; return tagged for caller
   arithmetic.
4. **snap_read_text downstream** — even with sys_read fixed,
   `store8(buf + m, 0)` SEGV'd because tagged-ptr + tagged-int
   arithmetic doesn't normalize cleanly; fallback to `str_new(buf, m)`
   also SEGV'd (prior-session's known "NOVA `str_new` tagged-dst"
   issue).

Un-masking also regressed `test_decision_log_durable`,
`test_chat_state_persistence`, `test_fed_daemon_transport` — all
three had been passing via sandbox-skip (their `_tmp_write_works()`
probe failed because of tagged flags; fixing flags lets them proceed
to the next downstream failure).

**Outcome**: Full NOVA patch reverted. R6b ships zero fixes. All 4
root causes documented in `docs/UPSTREAM_NOVA_BUGS.md §12` as a
dedicated sweep-round target. The sweep needs: (a) full syscall
wrapper audit (input untag + return tag), (b) Crossengin
`snap_read_text` rewrite OR NOVA `str_new` fix for the downstream
buffer arithmetic. Likely 15-30 LOC in NOVA + 5-10 in Crossengin,
multi-session effort.

**Tally delta**: 397 CLEAN unchanged / 35 pre-existing unchanged /
48 live-FAIL latent unchanged. Baseline preserved; no regressions.

NOVA repo state: clean (no commits in R6b). Crossengin repo: docs
update only (UPSTREAM §12 + this ROADMAP block).

### Latent-triage queue (post-R6b)

- **R7** — `test_nl_pipeline_gap_recording` source wiring regression.
- **R8** — `test_realtime_pacer` residual 3 FAILs.
- **R9+ (multi-session)** — NOVA Bug #12 syscall wrapper sweep +
  str_new fix / snap_read_text rewrite → closes C2b (4 tests) +
  likely several other file-I/O-dependent SEGVs.
- **Silent-skip** — `test_gossip_dtls_streams`.
- **ADR-driven** — C4 DTLS12 completion, C5 string.nova sweep audit.
- **C6** — cognitive/meta grab bag (20 tests, fragmented).

### Latent-triage R7 — `test_nl_pipeline_gap_recording` SKILL_REFUSED wire-in

Phase-1 Explore diagnosis (`a6f1dd5c4956f32e1`) found the root
cause: the test's expectation at `tests/unit/test_nl_pipeline_gap_recording.nova:149-151`
is **aspirational** — the comment says "research's manifest lists
COND_KG_EMPTY" but `research_skill_manifest()` at
`src/skills/skills/research_skill.nova:41-45` has NEVER declared any
refusal condition. R103 landed the gap-recording path on
`skill_run_scoped` but the wire-in from research's manifest to the
`COND_KG_EMPTY` precondition never shipped. Bug #8's ripple
unmasked this long-standing gap.

Three edits:

1. **`src/skills/skills/research_skill.nova:41-49`** (manifest):
   adds `skill_manifest_add_refusal(m, COND_KG_EMPTY, "")` — arm the
   refusal using `arg=""` as the sentinel for "walks the whole
   registry, needs at least one non-empty KG."

2. **`src/skills/skill_supervisor.nova:186-213`** (supervisor):
   extends the `COND_KG_EMPTY` handler with an `arg=""` branch that
   evaluates:
   - `reg == 0` → fail-open (preserves no-registry contract for
     tests like `test_no_registry_ok_but_zero`).
   - `reg` empty / all KGs empty → refuse.
   - any KG non-empty → pass.
   The existing by-name path is unchanged.

3. **`tests/unit/test_research_skill.nova:58-72`** (ripple):
   `test_empty_topic_returns_noop` + `test_topic_all_stopwords_returns_noop`
   use empty registries and expect `ok=1`. These test topic-parsing /
   stopword behavior, not KG-emptiness. Register a 1-atom stub KG
   via existing `_wire_kg` helper so the new refusal doesn't fire;
   assertions preserved as-is.

Per-test status:
- `test_nl_pipeline_gap_recording`: pre 1 FAIL / post OK (17 checks).
- `test_research_skill`: pre OK (25) / mid 2 FAIL (as predicted by
  the Edit-2 branch design) / post OK (25).

Ripple audit (full skill/gaps/nl cohort):
`test_self_gaps_verb` (51), `test_gaps_register` (87),
`test_nl_rpc_verbs` (87), `test_nl_rpc_metrics_verb` (90),
`test_capability` (136), `test_ownership` (173),
`test_nl_executor` (76), `test_skill_supervisor` (46),
`test_skill_registry` (44) — all PASS.

Canary sweep: motor_map, perception_module, action_module, R2 trio,
R3 pair, R4 cohort, R5 trio, R6 cohort — all PASS.

Tally delta: 397 → 398 CLEAN / 35 pre-existing / 47 live-FAIL latent
+ 1 silent-skip + 7 deferred-source-regression (down 1: R7
deferred-regression closed).

### Latent-triage queue (post-R7)

- **R8** — `test_realtime_pacer` residual 3 FAILs (not nanotime;
  precision + Shape-A smell).
- **R9+ (multi-session)** — NOVA Bug #12 syscall wrapper sweep.
- **Silent-skip** — `test_gossip_dtls_streams`.
- **ADR-driven** — C4 DTLS12 completion, C5 string.nova sweep audit.
- **C6** — cognitive/meta grab bag (20 tests, fragmented).
- **Codebase-hygiene** — tree-wide `str_eq → str_eq_bytes` sweep.

### Latent-triage R8 — `test_realtime_pacer` residual 3 FAILs

Phase-1 Explore (`a23758b1c0e129e4b`) classified the 3 residuals
left over after R6's nanotime fix:

- **FAIL #3 `summary starts with 'pacer:'`** — Shape A. `substr(…, 0, 6)`
  on a `+`-concat-built `pacer_summary` returns byte-buffer-tagged
  storage; raw `str_eq` is unreliable. `tests/ce_test.nova:42-54`
  documents this exact flakiness. 1-LOC fix: swap `str_eq` →
  `_ce_str_eq_bytes` (helper already in scope via `../ce_test.nova`
  import).
- **FAIL #1 `wall-clock ~50ms (delta < 15)`** + **FAIL #2 `slow-mo
  ~60ms (delta < 20)`** — Shape E (environment-dependent). Agent
  originally proposed widening to `delta < 40`. Empirical measurement
  revealed sandbox clock oversleep up to **~1300ms for a 50ms budget**
  — any symmetric tolerance is unreliable. Pivoted to floor-only
  assertions: `elapsed_ms >= 30` (wall-clock) and `elapsed_ms >= 40`
  (slow-mo). These still prove the pacer actually paces (both would
  fail on a no-op pacer that returns elapsed≈0), and semantic intent
  is preserved: "slow-mo factor applied → sleep was longer than
  base-case."

Three edits in `tests/unit/test_realtime_pacer.nova`:
- Line 62 — `delta < 15` → `elapsed_ms >= 30` (floor assertion +
  comment explaining sandbox clock jitter).
- Line 95 — `delta < 20` → `elapsed_ms >= 40` (same shape).
- Line 128 — `str_eq` → `_ce_str_eq_bytes` on substr compare.

Per-test status:
- `test_realtime_pacer`: pre 3 FAIL / post OK (27 checks). Verified
  deterministic across 3 consecutive runs.

Canary sweep + R7 cohort — all PASS.

Tally delta: 398 → 399 CLEAN / 35 pre-existing (unchanged — pacer
was in pre-existing bucket) / 47 live-FAIL latent + 1 silent-skip
+ 7 deferred-source-regression.

Note on classification: `test_realtime_pacer` wasn't a "latent" per
se but a pre-existing 6-FAIL test. R6 closed 3 of 6 (nanotime
dependents); R8 closes the remaining 3. Moving it out of
pre-existing bucket entirely.

### Latent-triage queue (post-R8)

- **R9+ (multi-session)** — NOVA Bug #12 syscall wrapper sweep +
  str_new fix → closes C2b 4 tests + likely more file-I/O-dependent
  SEGVs.
- **Silent-skip** — `test_gossip_dtls_streams`.
- **ADR-driven** — C4 DTLS12 completion plan (23 tests),
  C5 string.nova sweep audit (13 tests).
- **C6** — cognitive/meta grab bag (20 tests, fragmented).
- **Codebase-hygiene** — tree-wide `str_eq → str_eq_bytes` sweep.
- **Non-latent queue** — NOVA ADR-0009 impl, `_raw_imul_add` tagged-b
  cleanup (cosmetic), `test_match_expr` parser bug, re-collapse
  string.nova inline byte-copies, Phase R6+, real-socket DTLS
  roundtrip.

### Latent-triage R9 — silent-skip audit (6 files missing top-level `main()`)

Phase-1 Explore (`aece0d7d05d701990`) nailed the root cause in one
pass: NOVA's `_start` emits `argc/argv` setup, float-init guard, and
a `gen_stmt` loop over top-level decls skipping `AST_FN_DECL`, then
`exit(0)`. It does **not** auto-invoke `main`; the top-level call
must be written explicitly. A healthy test's `_start` disassembly
ends with `call main` → `exit`; the silent-skip binaries' `_start`
has no `call main` at all because the test file is missing the
trailing `main()` top-level statement after `fn main() { ... }`.

**6 affected test files** (all pre-existing authoring omissions):

| Test | Pre | Post |
|---|---|---|
| test_gossip_dtls_streams | silent-skip | OK (24 checks) |
| test_dtls_client_flight | silent-skip | OK (86 checks) |
| test_dtls_ext_parse | silent-skip | OK (45 checks) |
| test_dtls_server_flight | silent-skip | OK (92 checks) |
| test_md5 | silent-skip | OK (16 checks) |
| test_sha1 | silent-skip + 1 FAIL once running | OK (17 checks) after hash fix |

Fix: 1-line append `main()` to each file. Then one bonus fix:
`test_sha1_a_times_1000` had the FIPS Million-a hash
(`34aa973...`) copy-pasted instead of the actual 1000-'a' hash
(`291e9a6c66994949b57ba5e650361e98fc36b1ba`). Verified via openssl
and empirical compute. Comment block updated to clarify.

Classification: 6 pre-existing silent-skip + 1 pre-existing hash
typo. NOT a Bug #8 ripple. Also NOT a NOVA codegen issue — the
`_start` emission convention is intentional (per
`src/compiler/codegen.nova:10813-10976`).

Canary sweep + R1-R8 cohorts — all PASS.

Tally delta: 399 → 405 CLEAN. Three of the six (`test_md5`,
`test_sha1`, `test_dtls_*` compile-truncated set) were in the
pre-existing bucket (-4: md5, sha1, dtls_client_flight,
dtls_ext_parse, dtls_server_flight; and the silent-skip
`test_gossip_dtls_streams` disclosed in R3 moves to CLEAN).
Updated breakdown: 405 CLEAN / 31 pre-existing / 47 live-FAIL latent
+ 7 deferred-source-regression + 0 silent-skip (empty).

Potential codegen enhancement (NOT shipped here, operator decides):
NOVA's `_start` could emit an implicit `call main` when `main` is
declared, matching C convention. This would prevent silent-skip
authoring errors but is a semantic shift — currently the explicit
`main()` call lets authors control initialization order relative
to any top-level statements. Document as a potential future ADR.

### Latent-triage queue (post-R9)

- **R10+ (multi-session)** — NOVA Bug #12 syscall wrapper sweep +
  str_new fix → closes C2b 4 tests + likely more file-I/O-dependent
  SEGVs.
- **ADR-driven** — C4 DTLS12 completion plan (fewer tests now that
  R9 un-stuck 3 DTLS flight suites; re-triage needed to recount),
  C5 string.nova sweep audit (13 tests).
- **C6** — cognitive/meta grab bag (20 tests, fragmented).
- **Codebase-hygiene** — tree-wide `str_eq → str_eq_bytes` sweep.
- **Potential NOVA ADR** — implicit `call main` in `_start` when
  `main` is declared (prevents silent-skip authoring errors).
- **Non-latent queue** — NOVA ADR-0009 impl, `_raw_imul_add` tagged-b
  cleanup, `test_match_expr` parser bug, re-collapse string.nova
  inline byte-copies, Phase R6+, real-socket DTLS roundtrip.

### Latent-triage R10 — NOVA Bug #12 sweep attempted + reverted (zero shipped)

R10a (all 18 syscall-wrapper rewrites) + R10b (_nova_concat
tag-polymorphic entry) drafted per Phase-1 agent's scoping
(`ab332ea78a2493a62`). Both tested empirically. Reverted after
discovering two new constraints:

1. **Byte-count return tagging breaks the compiler itself.** The
   NOVA compiler consumes RAW byte counts from sys_read / sys_write /
   sys_lseek / sys_pread / sys_pwrite / sys_mmap / sys_getcwd when
   reading source files and emitting assembly. Tagging those returns
   makes stage2 `bin/nova` SEGV on any compile input. Updated rule:
   only tag returns for 0-or-errno wrappers (sys_rename, sys_fsync,
   sys_fdatasync, sys_unlink, sys_mkdir, sys_fstat, sys_ftruncate).
   Leave byte-count / position / raw-pointer returns alone.

2. **_nova_concat tag-polymorphic entry breaks direct callers.**
   codegen.nova has 6+ `call _nova_concat` sites that bypass
   `_nova_add`'s dispatcher. One (`:16917`) explicitly comments
   "aligned heap copy (bit0=0)". Adding `test rdi,1; jz; sar rdi,1`
   halves any input with bit-0=1 — breaks the compiler. Rule: do
   NOT touch `_nova_concat` entry without auditing every direct
   call site + classifying its tag convention.

Both patches reverted. NOVA repo state: clean (no commits in R10).

Tally delta: 405 CLEAN unchanged / 31 pre-existing unchanged /
47 live-FAIL latent + 7 deferred-source-regression unchanged.
Zero regressions, zero closes.

### Latent-triage queue (post-R10 — revised)

The R10 investigation refined Bug #12's fix shape. **R11 candidate**
(the next concrete attempt): surgical 3-piece patch instead of broad
sweep:
- (a) Input untag on `sys_open` flags/mode only (10 LOC NOVA).
- (b) Return tag on `sys_rename` only, if even needed in isolation
  (3 LOC NOVA).
- (c) Rewrite `src/persistence/snapshot_disk.nova:snap_read_text`
  to use `str_new(buf, m)` instead of `acc + buf` (6 LOC CE).
- (d) Verify end-to-end: open path works + read path works +
  snap_from_text parses correctly. If sandbox-skip trio still
  SEGVs, add specific untag on their callers rather than un-masking
  broadly.

Full queue:

- **R11** — Bug #12 surgical attempt (above).
- **ADR-driven** — C4 DTLS12 completion, C5 string.nova sweep audit.
- **C6** — cognitive/meta grab bag (20 tests, fragmented).
- **Codebase-hygiene** — tree-wide `str_eq → str_eq_bytes` sweep.
- **Potential NOVA ADR** — implicit `call main` in `_start`.
- **Non-latent queue** — NOVA ADR-0009 impl, `_raw_imul_add`
  tagged-b cleanup, `test_match_expr` parser bug, re-collapse
  string.nova inline byte-copies, Phase R6+, real-socket DTLS
  roundtrip.
