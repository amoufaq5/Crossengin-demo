# ADR-0093: Action module (parts/action atoms + module + motor_map + effector-gate wiring)

- Status: Accepted
- Date: 2026-09-30

## Context

Phase N R2 closes the last "Status: Pending" placeholder under
`src/parts/action/`. Before this round, `src/parts/action/README.md`
was a 10-line stub and `src/agent/loop_action.nova` inlined a
three-branch template that wrote one of three strings straight to
`ctx_output`:

```nova
if ctx_unknown(ctx) > 0 {
    out = "i do not fully understand that yet"
} else {
    if len(ctx_percept(ctx)) > 0 {
        out = "understood"
    } else {
        out = "i have nothing to say"
    }
}
```

Nothing under `src/parts/action/*` was on the loop's chain, and the
loop never called `src/io/effectors/effector_gate.nova` -- the
README's own promise ("actions pass the safety gate, ADR-0041") went
un-honored. Every output side-stepped the append-only decision log.
For a substrate whose safety story rests on "every outward action
writes an INTENT before it runs and an OUTCOME after" (ADR-0043), an
audit-invisible SPEAK is a real gap, not a cosmetic one.

Meanwhile the effector primitives ALREADY existed at
`src/io/effectors/effector_gate.nova` and were unit-tested but the
loop wasn't calling them:

- `effector_submit(log, action_type, const_veto, halted, user_approved, goal, trace, soul_ref, now)` -- runs the safety gate + writes DLK_INTENT; returns `[eff_result, intent_seq]`.
- `effector_speak(log, text, ...)` -- gates ACT_SPEAK + emits the text if permitted, writing its own INTENT + OUTCOME pair.
- `effector_speak_governed(log, sl, text, ...)` -- derives the constitutional veto from the soul before emit.
- `effector_complete(log, intent_seq, success, now)` -- writes DLK_OUTCOME referencing the intent.
- Result constants: `EFF_EXECUTED` (1), `EFF_NOTIFIED` (2), `EFF_SUSPENDED` (3), `EFF_VETOED` (4), `EFF_HALTED` (5).
- Action-type integers: `ACT_SPEAK` (9) at `src/safety/reversibility_classifier.nova:25`.

R1 (ADR-0092) had already delivered the shape a mature parts subtree
takes -- atoms + orchestrator + module-level singleton so the loop
shim's signature stays intact. R2 mirrors that shape for
`parts/action`.

## Decision

**New module `src/parts/action/action_atoms.nova`.** The `Intent`
record type. A 12-slot list-of-slots atom with an `IN_OBJ_TAG`
sentinel so runtime type-checks can distinguish it from an ambient
list. Slots:

| Slot | Contents |
| --- | --- |
| `IN_TAG` | sentinel |
| `IN_TIMESTAMP_NS` | caller-supplied moment nanoseconds |
| `IN_KIND` | `IN_KIND_SPEAK=1` / `_TOOL_CALL=2` / `_FILE_OP=3` / `_HTTP_ACTION=4` / `_CODE_EXEC=5` / `_MCP=6` / `_AUDIO=7` / `_INTERNAL=8` |
| `IN_TEXT` | phrase or command payload (`""` when unset) |
| `IN_ROLE` | grammatical role or effector role, may be `""` |
| `IN_GOAL_ID` | `goal_arbitrate` result, 0 if no goal attached |
| `IN_CONFIDENCE_MILLI` | 0..1000 |
| `IN_SOURCE_PERCEPT_ID` | Percept's source atom id, or 0 |
| `IN_EFFECTOR_CLASS` | `EFF_CLASS_INTERNAL=0` / `_SPEAK=1` / `_TOOL=2` / `_FILE=3` / `_HTTP=4` / `_CODE=5` / `_MCP=6` / `_AUDIO=7` |
| `IN_LINKED_PERCEPT` | full Percept handle, or 0 (R3 tie-back slot) |
| `IN_TRACE_REF` | audit-trail hint the gate stores on the intent record |
| `IN_REASON` | internal-intent reason payload; also seeds `IN_TEXT` for INTERNAL |

Three constructors -- `intent_speak_new`, `intent_internal_new`,
`intent_tool_new` (placeholder for future rounds) -- plus accessors,
predicates (`in_is_speak`, `in_is_internal`), name mappings
(`in_kind_name`, `in_effector_class_name`), a static routing map
(`in_kind_to_effector_class`), and a `in_summary` one-liner.
`in_is_intent(i)` guards against `i == 0` and short-list impostors
(`len(i) < 12`).

**INTERNAL text mapping.** The pre-R2 else-branch wrote
`"i have nothing to say"` verbatim. R2 preserves byte-identity by
having `intent_internal_new(ts, "nothing")` seed `IN_TEXT` with that
exact literal. The loop shim then writes `in_text(intent)`
unconditionally, so the pre-R2 template output is reproduced by
reading the intent record instead of hard-coding the string in the
loop body.

**New module `src/parts/action/action_module.nova`.** The
orchestrator. A 7-slot handle (`AM_DL`, `AM_GOAL_ENGINE`,
`AM_LAST_INTENT`, `AM_INTENT_COUNT`, `AM_LAST_EFF_RESULT`,
`AM_LAST_INTENT_SEQ`) plus these entry points:

- `action_module_init(dl, goal_engine)` -- mints a handle. Either
  argument may be `0`; the submit path treats a null dl as
  "no daemon wired" and short-circuits without writing to the log.
- `action_derive_intent(am, ctx, percept, now) -> Intent` -- pure
  decision. Unknown ctx (`ctx_unknown(ctx) > 0`) mints a SPEAK intent
  carrying the not-understood text at confidence 500; percept-present
  ctx (`len(ctx_percept(ctx)) > 0`) mints a SPEAK intent carrying
  "understood" at confidence 800; neither mints an INTERNAL intent
  with reason "nothing". When a non-zero goal engine is threaded in,
  `goal_arbitrate(ge)` attaches the currently-active leaf's id.
- `action_submit(am, intent, halted, user_approved, soul_ref, now) -> [eff_result, intent_seq]` --
  routes SPEAK intents through `effector_submit(dl, ACT_SPEAK, ...)` +
  (if permitted) `effector_speak(dl, in_text(intent), ...)`. INTERNAL
  intents are a no-op with no decision-log side effect. Non-SPEAK
  non-INTERNAL kinds return `[EFF_SUSPENDED, -1]` (motor_map is empty
  at MVP; a follow-up round wires the map).
- `action_complete(am, intent_seq, success, now)` -- writes DLK_OUTCOME
  via `effector_complete`. Skipped when `intent_seq == -1` (INTERNAL
  intent, unrouted kind, or null decision log).
- `action_run(am, ctx, percept, halted, user_approved, soul_ref, now) -> Intent` --
  the convenience the loop shim calls; cascades
  derive → submit → complete → cache and returns the Intent.
- `am_last_intent(am)`, `am_intent_count(am)`,
  `am_last_eff_result(am)`, `am_last_intent_seq(am)` -- read-only
  accessors for the trace + unit tests.

**New module `src/parts/action/motor_map.nova`.** The
substrate-activation → effector-class registry. A 2-slot handle
(`MM_ENTRIES` -- a linear list of `[key, class]` pairs) with
`motor_map_new()`, `motor_map_register(mm, key, class)`,
`motor_map_lookup(mm, sig)` (returns `EFF_CLASS_INTERNAL` on miss),
`motor_map_size(mm)`, `motor_map_keys(mm)`, `motor_map_entries(mm)`,
`motor_map_unregister(mm, key)`. Ships empty at MVP; the
action_module does not consult it today.

**Loop wiring: keep the 2-arg signature; add a module-level singleton.**
`src/agent/loop_action.nova::loop_action_step(ctx, lang_kg)` retains
its exact signature; internally it fetches
`action_module_singleton_for(dl, ge)` and calls `action_run`. The dl
and goal-engine handles come from three module-level slots
(`_la_dl_slot`, `_la_ge_slot`, `_la_halted_slot`) that default to 0;
tests populate them via `_la_set_dl`, `_la_set_ge`, `_la_set_halted`,
and a follow-up round wires them from the running daemon at boot.

The Percept comes from `pm_last_percept(perception_module_singleton_for(0))`
-- ADR-0092's cached-Percept slot. When no perception step has run
this tick (an action-only unit-test fixture), `pm_last_percept`
returns 0 and derive falls back to `source_percept_id = 0`.

Rejected alternative -- change the loop signature to
`loop_action_step(ctx, lang_kg, am, pm)` and update every caller.
Cost: the two examples binaries and every existing unit test change.
Benefit: no module-level state. Trade-off decided the other way: the
"simpler alternative" avoids the caller cascade and matches the
lazy-init pattern already used by R1's `perception_module_singleton_for`,
ADR-0086's `_ac_config_load`, and ADR-0088's `_nb_xref_config_load`.
A test-only `_action_module_singleton_reset` clears the singleton for a
per-test fresh-module fixture, and `_la_wiring_reset` clears the
daemon-wire slots.

**Autonomous loop wiring:** add `AG_ACTION_MODULE = 22` to
`autonomous_loop.nova`, populated from `action_module_init(a[AG_DLOG], 0)`
in `agent_new` (the autonomous loop's own decision log is threaded in;
the goal engine stays 0 until a future round adds a user-facing goal
engine there). The slot exists so a future round can drive `action_run`
over the per-agent module handle instead of the singleton. Also add
an `agent_action_module(a)` accessor and a convenience `agent_dl(a)`
reader for the decision log.

## Consequences

**Audit trail closed.** For every SPEAK intent when a decision log is
wired in, four records land in the log: the action_module's own
INTENT (from `effector_submit`), the ACT_SPEAK INTENT + OUTCOME that
`effector_speak` writes for its own gate submission, and the
action_module's own OUTCOME (from `action_complete`). A halted /
vetoed SPEAK writes only the action_module's INTENT with
OUT_VETOED / OUT_PENDING and does not invoke `effector_speak` --
zero emit, plus a record explaining why the emit was refused.

**Backwards-compat contract.** For the three pre-R2 loop_action
fixtures, the emitted `ctx_output` text is BYTE-IDENTICAL to pre-R2:

| Fixture | Pre-R2 output | Post-R2 output |
| --- | --- | --- |
| `ctx_unknown > 0` | `"i do not fully understand that yet"` | `"i do not fully understand that yet"` |
| `len(ctx_percept) > 0` | `"understood"` | `"understood"` |
| neither | `"i have nothing to say"` | `"i have nothing to say"` |

Asserted in `tests/unit/test_loop_action.nova::test_byte_identity_percept`,
`test_byte_identity_unknown`, `test_byte_identity_silent`, plus
`tests/unit/test_action_module.nova::test_run_unknown_end_to_end` /
`test_run_empty_no_log`.

**Zero-caller-update.** The two examples binaries
(`examples/crossengin_chat.nova`, `examples/crossengin_daemon.nova`)
and the pre-R2 unit test call `loop_action_step(ctx, lang_kg)` with
no daemon plumbing. In that state, `_la_dl_slot` is 0, the action
module's submit path short-circuits silently, and `ctx_output`
carries the pre-R2 text -- so those binaries need no code change.

**No compiler proof.** Per Phase L/M/N-R1 findings, the NOVA compiler
self-hosting bootstrap segfaults in this container, so `make test`
cannot run end-to-end. Verification here is:

1. Structural review: the diff is additive-only for the new modules;
   `loop_action.nova` retains its signature and return value; the
   INTERNAL intent's `IN_TEXT` seed preserves byte-identity of the
   pre-R2 else-branch output.
2. `make lint-ints` -- no new bug-#11 large-literal violations.
3. Grep-check: `effector_submit` now appears where the inline
   templating body sat in `loop_action.nova` (via `action_run` on
   the action module singleton); the pre-R2 template strings are
   no longer top-level literals in `loop_action.nova` -- they moved
   into `action_atoms.nova`'s constructors and `action_module.nova`'s
   derive path.

## Alternatives considered

**Signature change to `loop_action_step(ctx, lang_kg, am, pm)`.**
Rejected -- see above. The module-level singleton preserves every
caller and matches the R1 pattern.

**Fold action-atoms into action_module.** Rejected -- the atom
schema is stable and independently testable; keeping the two files
separate matches the reasoning subtree's shape and lets a follow-up
round add TOOL_CALL / FILE_OP intent constructors without touching
the orchestrator.

**Have the derive path call `goal_arbitrate` and pick the intent's
kind from the goal.** Rejected for MVP -- the pre-R2 loop's
three-branch policy is what the fixtures assert; a goal-driven
derive is a follow-up round's work (with its own tests + ADR). R2
attaches the goal id to the intent so R3+ can pick up the thread
without touching the record schema.

**Emit through `effector_speak_governed` instead of
`effector_speak`.** Rejected for MVP -- the governed variant needs
a soul handle, and the loop_action shim doesn't have one threaded in
today. The submit path passes `soul_ref = 0` -- when a follow-up
round threads a soul through the daemon wiring, the submit path
flips to `effector_speak_governed(dl, sl, text, ...)` so
constitutionally-forbidden utterances are vetoed at the text level.

**Duplicate the effector-class integers from effector_gate.**
Accepted -- the `EFF_CLASS_*` integers live in `action_atoms.nova`
as small ints (`SPEAK=1`, `TOOL=2`, `FILE=3`, `HTTP=4`, `CODE=5`,
`MCP=6`, `AUDIO=7`, `INTERNAL=0`). The alternative -- import from a
new "action_types" module -- adds a cross-module coupling for no
benefit; the atoms module has no runtime dependency on the effector
gate.

## Implementation notes

- **NOVA quirk: `len(0)` segfaults.** The `IN_TEXT` slot defaults to
  `""` (never 0), so downstream `len(in_text(i)) > 0` guards are
  safe. Constructors that receive `text == 0` skip the assignment
  and keep the shell's `""`.
- **NOVA quirk: `str_eq` unreliable on short literals.** The
  "nothing" check inside `intent_internal_new` walks bytes via
  `char_at` rather than calling `str_eq`. The motor_map's key
  comparison does the same.
- **Module-level singleton lazy-init.** `_action_module_singleton`
  starts at 0; the first `action_module_singleton_for(dl, ge)` call
  builds it. A subsequent call with a different `dl` or `ge`
  rebuilds it (a test flipping fixtures gets a fresh module).
  Mirrors the R1 pattern and the ADR-0086 `_ac_config_load` shape.
- **`ACT_SPEAK` constant.** Found at
  `src/safety/reversibility_classifier.nova:25`. The action_module
  imports that file for the `ACT_SPEAK` int; the effector_gate
  transitively re-exports the same constant.
- **Decision-log record shapes.** `effector_submit` uses `DLK_INTENT`
  (kind = 1) with the effector descriptor `[action_type, action_type,
  perm_tier, rev_class]`. `effector_complete` uses `DLK_OUTCOME`
  (kind = 2) referencing the intent's seq id.
- **File count.** New: 3 modules + 3 tests + this ADR = 7 files.
  Modified: `action/README.md` (Pending → Accepted, rewritten),
  `loop_action.nova` (delegate through singleton),
  `autonomous_loop.nova` (allocate the slot + import the module +
  add `agent_action_module` / `agent_dl` accessors),
  `ENHANCEMENTS_ROADMAP.md` (Phase N R2 note, Phase N COMPLETE),
  `tests/unit/test_loop_action.nova` (add the byte-identity + wired
  regression tests).

## R3 preview

Follow-up rounds -- not scheduled in this plan -- would populate
`motor_map` with real activation-pattern → effector-class mappings,
wire the map lookup into `action_derive_intent` so the substrate can
mint TOOL_CALL / FILE_OP / HTTP_ACTION intents when a matching
activation signature appears, and add live daemon wiring so the
`_la_dl_slot` / `_la_ge_slot` module slots are populated at daemon
boot rather than only in tests. Together those close the loop from
"substrate concept activation → intent → gated effector → outcome
record" for every effector class, not just SPEAK.

## Phase N status

This round CLOSES Phase N -- the "README-only parts" arc is done. Both
`src/parts/perception/` (R1, ADR-0092) and `src/parts/action/` (R2,
this ADR) now have real atom + orchestrator modules and loop
integration that honors their README-called-out promises.
