# ADR-0056: Follow-up integration round (P1–P5 "Honest gaps")

## Status

Proposed

## Date

2026-06-11

## Context

ADRs 0051–0055 (the P1–P5 roadmap) each shipped a tested mechanism behind a
flag/new file and recorded an explicit "Honest gaps" list — mostly *wiring* the
mechanisms into each other and into the live loop. This ADR records the round
that closed the tractable, additive parts of those gaps. The work was done as
five parallel, file-disjoint workstreams (one per phase); every change is
additive, and the full affected-test sweep (23 suites, 873 checks) passes over
the combined tree.

## Decision (what got wired, per phase)

**P1 — HDC representation (`hdc_embed`, `concept_layer`, `ann_index`).**
- Bounded symbol cache: a CLOCK-style eviction policy with a configurable cap
  (`hdc_cache_set_cap`/`hdc_cache_cap`) so the memo can't grow unbounded; evicted
  vectors are recomputed bit-identically (eviction trades a cache miss for
  memory, never correctness).
- Live mode switch: `hdc_reembed_atom` / `hdc_reembed_lang_kg` re-embed existing
  `ATOM_LANG` atoms under the current mode (for a runtime LEGACY→HDC flip).
- Signed coherence: `concept_layer` coherence now uses signed `hdc_cosine` in HDC
  mode (so anti-correlated clusters are correctly rejected); `ann_index` documents
  why `vec_cosine` ranking is adequate.

**P2 — three-factor learning into the live loop (`tick_driver`).**
- An OPT-IN three-factor pass (`tick_three_factor_pass` + in-loop `*_3f` tick
  entry points, gated by `td_enable_three_factor`, default OFF): builds a
  per-node fire-tick snapshot → `syn_eligibility_step` → `pc_neuromod_scalar`
  (reward from appraisal valence) → `syn_neuromodulate` → decay. The default tick
  path is byte-identical; with the flag on, a rewarded co-firing moves weights
  (and delayed reward credits the right synapse through the loop), an unrewarded
  one does not.

**P3 — ingestion wiring (`learn_pipeline`, `pdf_text`).**
- `lp_ingest_resolved`: OpenIE-extract triples, then resolve each mention through
  `er_resolve_or_create` (with a neighbourhood hypervector) BEFORE linking, so
  synonyms collapse to one atom ("car"/"automobile" → one in HDC mode; graceful
  exact+alias degradation in LEGACY). The original `lp_ingest` is untouched.
- `pdf_extract_text_auto`: inflates FlateDecoded content streams via the in-tree
  `deflate_decode` (zlib header stripped) then extracts; uncompressed PDFs flow
  through unchanged.

**P4 — tool ↔ cognition wiring (`tool_use`, `effector_http_action`, new
`tool_goal_plan`).**
- `tool_goal_plan`: `goal_to_plan` / `goal_plan_build` / `goal_run` decompose a
  `goal_engine` goal's active leaf sub-goals into a tool plan and execute it,
  rolling success back up the goal tree.
- Live HTTP: `effector_http_action` `simulated==0` now fetches through the gated
  `lp_fetch` transport (default stays simulated/offline for tests); a pure
  `http_action_run_live(url, fetched_body)` seam is also exposed.
- Moments: `plan_execute_moments` emits each tool result into `moment_stream`
  (`MODALITY_INTERNAL`, salience by success); `tool_presimulate_via_fwd` is the
  `forward_sim` pre-check seam.

**P5 — self-improvement deepening (`self_improve`, `world_model`).**
- Lookahead planning: `world_peek_at` (pure predict from an arbitrary state) +
  `si_plan_action`/`si_eval_plan` do depth-limited model-based rollouts bootstrapped
  by the learned value.
- HDC state features: `si_state_vector` (a state's D=10000 hypervector) — the seam
  toward function approximation.
- Persistence: `si_q_serialize`/`si_q_restore` round-trip the value table.
- Applied self-edit: `si_apply_edit` mints an `ATOM_RULE` ("in state S take action
  A") only when the constitutional gate accepts, with the decision-log INTENT/
  OUTCOME pair as the rollback record.

## Consequences

- The P1↔P3 tie is now live (entity resolution runs in the ingest path); the
  substrate's three-factor learning can run inside the real tick loop; tools are
  driven from goals and emit moments; the self-improver plans with the world model,
  persists what it learns, and turns accepted reflections into real rule atoms.
- Everything stays additive and flag-gated: 23 affected test suites (873 checks)
  pass over the combined tree, including all pre-existing ones unchanged.

## Honest gaps (what remains after this round)

- **Still opt-in, not the default agent.** The three-factor tick pass and the
  self-improvement loop are wired but gated/standalone; a single always-on
  autonomous agent loop that runs perception → three-factor learning →
  goal-driven tool use → self-improvement every tick is the next frontier.
- **Seams, not full internal engines.** Live HTTP/MCP default to simulated;
  `forward_sim` pre-check and the adaptive predictor are exposed as parameter
  seams (their persistent state belongs to an engine/agent object that spans
  modules) rather than hardwired.
- **Persistence not snapshotted.** The value table can serialize but isn't yet
  written through the ADR-0048 snapshot system, so cross-process-restart
  continuity is still manual.
- **PDF inflate covers stored blocks end-to-end in tests**; Huffman-coded streams
  rely on `deflate_decode`'s own suite (no in-tree DEFLATE encoder to build a
  Huffman fixture). Real arbitrary sandboxed code-exec (vs arithmetic) and fully
  automated self-directed tool acquisition remain future work (now *composable*
  from P3 ingestion + P4 `goal_run`).

## Implementation Notes

- Five file-disjoint workstreams, run as parallel agents, integrated centrally;
  no module was edited by two workstreams. All changes respect the NOVA
  discipline (int_* for large multiplies, one `let` per line, additive/flagged).
- New/changed tests (counts after this round): `test_hdc_embed` 69,
  `test_concept_layer` 34, `test_learn_pipeline` 21, `test_pdf_text` 18,
  `test_tool_use` 28, `test_tool_goal_plan` 15 (new), `test_world_model` 40,
  `test_self_improve` 55, `test_tick_driver` 38 — all green alongside the
  untouched suites.
- The full `make test` green-gate still can't be run here (the NOVA compiler
  hangs on the unrelated `src/federation/dtls12.nova`); verification is the
  per-module compile + the affected-test sweep, as throughout the roadmap.
