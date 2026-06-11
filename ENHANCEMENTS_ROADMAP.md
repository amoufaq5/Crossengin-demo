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

## What this roadmap does NOT claim
- It does not claim AGI. It builds the mechanisms a moment-signal AGI bet
  *requires*; whether they compose into general intelligence is unproven and is
  the research wager.
- "Feel" = functional appraisal (control/motivation signal), not sentience.
- Credit assignment without backprop at scale is an open problem; P2 uses the
  best-known local approximations, not a solved method.
