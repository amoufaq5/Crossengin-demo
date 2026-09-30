# ADR-0092: Perception module (parts/perception atoms + module + loop wiring)

- Status: Accepted
- Date: 2026-09-30

## Context

Phase N opens with `src/parts/perception/` in a placeholder state:
`src/parts/perception/README.md` was a 10-line "Status: Pending" stub, and
`src/agent/loop_perception.nova` delegated its entire body -- 6 lines of
substance -- straight to `src/reader/reader.nova::reader_read`, writing four
context slots and returning the reader's matched-token count. Nothing under
`src/parts/perception/*` was on the loop's chain.

Meanwhile the perception primitives ALREADY existed at
`src/perception/*` and were unit-tested but wire-orphaned:

- `src/perception/input_classifier.nova::classify_input(text)` returns a
  `[category, confidence_milli, signals]` triple over ten categories
  (`CAT_GREETING` through `CAT_FACTUAL` plus `CAT_UNKNOWN`).
- `src/perception/sensor_fusion.nova` (R20C) has `fuse_image_observation` /
  `fuse_audio_observation` / `fuse_observation` for cross-modal binding
  under a temporal window plus identity-agreement -- the primitive the
  substrate needs to bind "someone speaks while their face is on camera"
  into one atom.
- `src/perception/lipsync.nova::lipsync_detect(video_frames, audio_pcm, sample_rate)`
  correlates mouth-open per-frame scores against per-frame voicing energy
  and returns `[sync_score_milli, is_synced]`.

The loop was calling none of them. The classifier's category / confidence /
signals were unavailable to downstream action; the fusion binding was
invisible; lipsync ran only in scenario drivers.

Meanwhile the sibling subtree `src/parts/reasoning/` had accumulated 11
files -- atoms + strategy module + auxiliary modules (proof checker,
argumentation, contradiction, debate, steelman, promotion pass, multi-KG
consistency, decision record, epistemic status) -- so a mature parts
subtree's shape is well-established: an atom / record module + an
orchestrator + auxiliary modules on top.

Phase N R1 fills the perception subtree with two real modules and wires
`loop_perception_step` through them, preserving every observable behavior
of the pre-R1 loop.

## Decision

**New module `src/parts/perception/perception_atoms.nova`.** The `Percept`
record type. A 14-slot list-of-slots atom with a `PC_OBJ_TAG` sentinel so
runtime type-checks can distinguish it from an ambient list. Slots:

| Slot | Contents |
| --- | --- |
| `PC_TAG` | sentinel |
| `PC_TIMESTAMP_NS` | caller-supplied moment nanoseconds |
| `PC_MODALITY` | `PC_MODALITY_TEXT=1` / `_IMAGE=2` / `_AUDIO=3` / `_VIDEO=4` / `_MULTIMODAL=5` |
| `PC_CATEGORY` | classifier `CAT_*` enum (0 for non-text) |
| `PC_CONFIDENCE_MILLI` | 0..1000 |
| `PC_LABELS` | fusion feature labels (image / audio); empty for text |
| `PC_SIGNALS` | classifier signals list (text); empty for non-text |
| `PC_SOURCE_ATOM_ID` | KG atom id, or 0 pre-birth |
| `PC_IDENTITY_LABEL` | cross-modally agreed identity from sensor_fusion; `""` if unset |
| `PC_LINKED_IMAGE` | image half of a multimodal Percept, or 0 |
| `PC_LINKED_AUDIO` | audio half of a multimodal Percept, or 0 |
| `PC_CORR_MILLI` | fusion / lipsync correlation score in milli |
| `PC_ROUTES` | reader routes list (text path) |
| `PC_UNKNOWN` | reader unknown-token count (text path) |

Four constructors -- `percept_text_new`, `percept_image_new`,
`percept_audio_new`, `percept_multimodal_new` -- plus accessors and a
`pc_summary` one-liner. `pc_category_name` delegates to
`input_classifier::cat_name`; `pc_modality_name` maps `PC_MODALITY_*` to
short strings and returns `"unknown"` on a bad enum. `pc_is_percept(p)`
guards against `p == 0` and short-list impostors (`len(p) < 14`).

**New module `src/parts/perception/perception_module.nova`.** The
orchestrator. A 5-slot handle (`PM_RENV`, `PM_LAST_PERCEPT`,
`PM_STEP_COUNT`, `PM_LAST_MATCHED`) plus these entry points:

- `perception_module_init(reader_env, ctx)` — mints a handle. `ctx` is
  accepted for signature-parity but not captured; the module runs over
  whatever ctx is handed to it per step, so two loops sharing the module
  get parallel ctx state without contamination.
- `perception_step_text(pm, ctx, text, now) -> Percept` — the pre-Phase-N
  inline body, refactored. Runs `classify_input`, mints a
  `percept_text_new`, runs `reader_read(renv, text, [])`, writes the same
  four ctx slots (`percept`, `active`, `routes`, `unknown`) as the
  pre-R1 path -- VERBATIM, in the same order, from the same
  `rctx_active` / `rctx_routes` / `reader_unknown` accessors -- caches the
  reader's `matched` scalar on `PM_LAST_MATCHED`, and returns the Percept.
- `perception_step_image(pm, ctx, labels, identity, source_id, conf, ts)`
  — wraps `fuse_image_observation` + `percept_image_new`.
- `perception_step_audio(pm, ctx, labels, identity, source_id, conf, ts)`
  — wraps `fuse_audio_observation` + `percept_audio_new`.
- `perception_step_multimodal(pm, ctx, img_p, aud_p, video_frames, audio_pcm, sample_rate, ts)`
  — reconstructs the two observation atoms from the per-modality
  Percepts, invokes `fuse_observation` for the binding + identity
  agreement, and invokes `lipsync_detect` ONLY when both `video_frames`
  and `audio_pcm` (and a positive `sample_rate`) are present. The
  correlation score is written to `PC_CORR_MILLI`; identity is read
  back from the fused atom so a STRONG upgrade in `fuse_observation`
  (both sides agreeing) is reflected on the multimodal Percept.
- `pm_last_percept(pm)` — the accessor R2 (parts/action) will consume.

**Loop wiring: keep the 2-arg signature; add a module-level singleton.**
`src/agent/loop_perception.nova::loop_perception_step(ctx, renv)` retains
its exact signature; internally it fetches
`perception_module_singleton_for(renv)` and calls `perception_step_text`.
The singleton lazy-inits on first call and rebuilds when `renv` changes
(a test flipping readers gets a fresh module). Reader `matched` is
returned from `pm_last_matched(pm)` -- the module cached it on the same
`reader_read` call that produced the ctx writes, so the shim never runs
the reader twice.

Rejected alternative -- change the loop signature to
`loop_perception_step(ctx, pm, now)` and update every caller. Cost:
three files under `examples/*` and `tests/unit/*` change. Benefit: no
module-level state. Trade-off decided the other way: the plan's
"simpler alternative" avoids the caller cascade and matches the
lazy-init pattern already used by `_ac_config_load` (ADR-0086) and
`_nb_xref_config_load` (ADR-0088). A test-only
`_perception_module_singleton_reset` clears the singleton for a
per-test fresh-module fixture.

**Autonomous loop wiring:** add `AG_PERCEPTION_MODULE = 21` to
`autonomous_loop.nova`, populated from `perception_module_init(0, 0)` in
`agent_new` (the autonomous loop does not itself drive perception yet --
`agent_cycle` operates on the task world, not on utterances). The slot
exists so R2 can fetch the last Percept from `agent_perception_module(a)`
instead of a global. When the autonomous loop is later extended to
consume external utterances, `agent_new` should accept a real reader env
and thread it in; the shim's module-level singleton is the current
production path.

## Consequences

**Behavior-preservation contract.** For every text input, the four ctx
slots (`ctx_percept`, `ctx_active`, `ctx_routes`, `ctx_unknown`) are
byte-identical to the pre-Phase-N reader-only path. Both
`tests/unit/test_perception_module.nova::test_perception_step_text_byte_identity`
and `tests/unit/test_loop_perception.nova::test_ctx_byte_identity_vs_reader_only`
assert this against the `"fever"` fixture. `loop_perception_step`'s return
value (`reader_matched(c)`) is also unchanged.

**Additive Percept handle.** Every text step now caches a Percept on the
module. Downstream R2 (parts/action) will consume it via `pm_last_percept`
to derive Intents whose confidence and category come from the classifier
rather than pure-substrate templating. R1 does NOT touch action policy --
that's R2's remit -- but the Percept is available for it.

**Multimodal is optional at MVP.** No caller under `examples/*` currently
ships image or audio bytes through the perception loop today, so
`perception_step_image` / `_audio` / `_multimodal` are ship-and-ready but
uncalled. This is intentional: the perception primitives already exist and
have their own unit tests under `tests/unit/test_sensor_fusion*.nova` and
`tests/unit/test_lipsync*.nova`; the module's job is to make them
composable behind one API, not to invent new capture pipelines. A
follow-up round can drive them from the video capture pipeline
(`src/io/transducers/visual_perception.nova`) and the STT seam
(`src/io/transducers/stt_seam.nova`) once the daemon's perception loop
maintains ring buffers per modality (R20C.2 in `sensor_fusion.nova`'s own
follow-up notes).

**No compiler proof.** Per Phase L/M findings, the NOVA compiler
self-hosting bootstrap segfaults in this container, so `make test` cannot
run end-to-end. Verification here is:

1. Structural review: the diff is additive-only for the new modules;
   loop_perception.nova retains its signature and return value; the
   ctx-slot writes are line-for-line identical to the pre-R1 body.
2. `make lint-ints` -- no new bug-#11 large-literal violations.
3. Grep-check: `reader_read` no longer appears at the top level of
   `loop_perception.nova`; `perception_step_text` does.

## Alternatives considered

**Signature change to `loop_perception_step(ctx, pm, now)`.** Rejected -- see
above. Zero-caller-update is worth a module-level singleton, especially
when the autonomous loop and the chat REPL both construct their own
readers and the singleton keys on `renv` for isolation.

**Fold classifier + reader into one module `perception_step`.** Rejected --
the two primitives serve different roles: `classify_input` is a
text-taxonomy signal (a hint for downstream policy), and the reader is
the concept-activation engine (routes and unknown counts feed the
learning signal). Keeping them separate at the primitive layer and
composed at the module layer matches the atoms + module + auxiliary
shape that `src/parts/reasoning/` already uses.

**Re-implement fusion inside the perception module.** Rejected -- the
fusion primitive is already 500+ lines of R20C-authored code with its
own unit-test suite. The module wraps it; it does not duplicate it.

**Extend the Percept schema with reader-scope scalars (`matched`, seed list).**
Rejected -- `matched` is a per-step counter, not a percept property; it
belongs on the loop-scope handle. Cached on `PM_LAST_MATCHED` on the
module instead, where the shim reads it back.

## Implementation notes

- **NOVA quirk: `len(0)` segfaults.** All identity-label fields default to
  `""` (never 0), so downstream `len(pc_identity_label(p)) > 0` guards
  are safe. Constructors that receive `identity_label == 0` skip the
  assignment and keep the shell's `""`.
- **NOVA quirk: `str_eq` unreliable on short literals.** The Percept
  identity comparison inside `percept_multimodal_new` uses `len(...) > 0`
  rather than `str_eq(..., "")` for the empty-string test.
- **Module-level singleton lazy-init.** `_perception_module_singleton`
  starts at 0; the first `perception_module_singleton_for(renv)` call
  builds it. A subsequent call with a different `renv` rebuilds it (a
  test flipping readers gets a fresh module). Mirrors the lazy-init
  pattern in ADR-0086 (`_ac_config_load`).
- **Not on `agent_cycle`'s hot path.** The autonomous loop's `agent_cycle`
  runs the task world; it does not call perception (per-cycle perception
  would drive external-input hallucination). `AG_PERCEPTION_MODULE` is a
  handle allocated for R2; it is not read inside `agent_cycle` in R1.
- **File count.** New: 2 modules + 2 tests + this ADR = 5 files.
  Modified: `perception/README.md` (Pending -> Accepted, rewritten),
  `loop_perception.nova` (delegate through singleton),
  `autonomous_loop.nova` (allocate the slot), `ENHANCEMENTS_ROADMAP.md`
  (Phase N R1 note), `tests/unit/test_loop_perception.nova` (add the
  byte-identity regression).

## R2 preview

R2 will fill `src/parts/action/` with `action_atoms.nova` (Intent record) +
`action_module.nova` (orchestrator: Percept + ctx conclusions -> Intent
-> `effector_submit`) + optional `motor_map.nova` (substrate-activation ->
effector-class registry). The loop_action templating body (three
hard-coded strings written straight to `ctx_output`, bypassing
`effector_gate` -- a real README gap called out in the plan §Context)
will submit through the effector gate, so every SPEAK writes an INTENT
plus an OUTCOME to the decision log (audit trail for every emit, per
ADR-0041). The perception Percept minted here is what R2's
`action_derive_intent` reads to set the Intent's confidence and category
signal. See the plan file at `/root/.claude/plans/gentle-toasting-zephyr.md`
§R2 for the full spec.
