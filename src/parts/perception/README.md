# Perception part

First nodes receive moments routed in through gates and raise activation into the substrate; the entry surface for external input. Composes `classify_input` + the five-stage reader + optional cross-modal sensor fusion + lipsync into a first-class `Percept` record that downstream loops consume.

**Status:** Accepted.

**Governing ADRs:** ADR-0010, ADR-0021, ADR-0036, ADR-0092.

## Module layout

- **`perception_atoms.nova`** — the `Percept` record type. 14 slots covering timestamp, modality (`PC_MODALITY_TEXT` / `_IMAGE` / `_AUDIO` / `_VIDEO` / `_MULTIMODAL`), category (from `classify_input`), confidence, labels, signals, source atom id, identity label (from sensor fusion), cross-modal links to the underlying image / audio Percepts (for a multimodal Percept), a fusion / lipsync correlation score, and the reader-side routes + unknown-count. Constructors: `percept_text_new`, `percept_image_new`, `percept_audio_new`, `percept_multimodal_new`. Accessors: `pc_timestamp_ns`, `pc_modality`, `pc_category`, `pc_confidence`, `pc_labels`, `pc_signals`, `pc_source_atom_id`, `pc_identity_label`, `pc_linked_image`, `pc_linked_audio`, `pc_corr_milli`, `pc_routes`, `pc_unknown`, `pc_is_multimodal`, `pc_modality_name`, `pc_category_name` (delegates to `cat_name`).
- **`perception_module.nova`** — the orchestrator. `perception_module_init(reader_env, ctx)` returns a handle; `perception_step_text(pm, ctx, text, now)` runs `classify_input` + `reader_read` and writes the four historical ctx slots (`percept`, `active`, `routes`, `unknown`) byte-identically to the pre-Phase-N inline reader path while minting a Percept and caching it via `pm_last_percept` for R2 (parts/action) to consume. `perception_step_image` / `_audio` wrap the sensor-fusion observation constructors; `perception_step_multimodal` composes them plus optional `lipsync_detect`. A module-level singleton (`perception_module_singleton_for(renv)`) keeps the pre-Phase-N `loop_perception_step(ctx, renv)` signature intact — the two examples binaries and the existing unit tests are byte-untouched.

## Loop integration

`src/agent/loop_perception.nova::loop_perception_step` now routes every call through `perception_step_text` on the module-level singleton (keyed on `renv`). Contract:

- **Signature preserved.** Still `loop_perception_step(ctx, renv) -> int`. Callers in `examples/crossengin_chat.nova`, `examples/crossengin_daemon.nova`, and `tests/unit/test_loop_perception.nova` remain unchanged.
- **Return value preserved.** The reader's `matched` scalar for the current text. The module caches it on `PM_LAST_MATCHED` so the shim reads it back without a second `reader_read`.
- **Ctx slots byte-identical.** `ctx_percept` / `ctx_active` / `ctx_routes` / `ctx_unknown` are written from the same reader-context accessors (`rctx_active` / `rctx_routes` / `reader_unknown`) as the pre-Phase-N inline path. `tests/unit/test_perception_module.nova::test_perception_step_text_byte_identity` and `tests/unit/test_loop_perception.nova::test_ctx_byte_identity_vs_reader_only` assert this against a fixture.

The `AG_PERCEPTION_MODULE` slot on `src/agent/autonomous_loop.nova::agent_new` carries a per-agent handle for R2 (parts/action) to fetch the last Percept without a global lookup.

## Reused primitives

- `src/perception/input_classifier.nova::classify_input(text)` → `[category, confidence_milli, signals]` (10-category enum: greeting, social, personal, academic, debatable, financial, arithmetic, procedural, factual, unknown).
- `src/reader/reader.nova::reader_read(renv, text, seed_list)` → the five-stage reader context.
- `src/perception/sensor_fusion.nova::{fuse_image_observation, fuse_audio_observation, fuse_observation}` — cross-modal binding (temporal window + identity agreement, `FUSE_BINDING_STRONG` / `_WEAK` / `_NONE`).
- `src/perception/lipsync.nova::lipsync_detect(video_frames, audio_pcm, sample_rate)` → `[sync_score_milli, is_synced]`.

## Follow-ups (post-Phase-N)

- Drive `perception_step_image` / `_audio` from the live capture pipelines (video / STT). Today no caller ships bytes through the loop — the modules are structurally in place for the follow-up round.
- Extend `AG_PERCEPTION_MODULE`'s reader env from `0` to a real reader env when the autonomous loop is later extended to consume external utterances.
- Add a `/perception` chat admin command to render `pm_last_percept` via `pc_summary`.

See [`docs/adr/`](../../../docs/adr/) for the decisions that bind this component, and the repository [README](../../../README.md) for the substrate overview.
