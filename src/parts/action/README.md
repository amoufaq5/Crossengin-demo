# Action part

Pure-substrate output: concept-activation patterns flow down through language nodes to motor effectors. No LLM in output (ADR-0013, ADR-0014). Every outward action passes the effector safety gate (ADR-0041) — every SPEAK writes an INTENT + OUTCOME to the append-only decision log (ADR-0043).

**Status:** Accepted.

**Governing ADRs:** ADR-0013, ADR-0014, ADR-0041, ADR-0043, ADR-0093.

## Module layout

- **`action_atoms.nova`** — the `Intent` record type. 12 slots covering timestamp, kind (`IN_KIND_SPEAK` / `_TOOL_CALL` / `_FILE_OP` / `_HTTP_ACTION` / `_CODE_EXEC` / `_MCP` / `_AUDIO` / `_INTERNAL`), text payload, role, goal id, confidence, source Percept id, effector class (`EFF_CLASS_SPEAK` / `_TOOL` / `_FILE` / `_HTTP` / `_CODE` / `_MCP` / `_AUDIO` / `_INTERNAL`), linked Percept, trace ref, and internal reason. Constructors: `intent_speak_new`, `intent_internal_new`, `intent_tool_new`. Accessors: `in_timestamp_ns`, `in_kind`, `in_text`, `in_role`, `in_goal_id`, `in_confidence`, `in_source_percept_id`, `in_effector_class`, `in_linked_percept`, `in_trace_ref`, `in_reason`, `in_is_intent`, `in_is_speak`, `in_is_internal`, `in_kind_name`, `in_effector_class_name`, `in_kind_to_effector_class`, `in_summary`.
- **`action_module.nova`** — the orchestrator. `action_module_init(dl, goal_engine)` returns a handle; `action_derive_intent(am, ctx, percept, now)` maps ctx state (unknown / percept-present / neither) to a SPEAK or INTERNAL intent; `action_submit(am, intent, halted, user_approved, soul_ref, now)` submits SPEAK intents through `effector_gate.effector_submit` + `effector_speak` (writing INTENT + OUTCOME to the decision log); `action_complete(am, intent_seq, success, now)` writes the outcome referencing the intent; `action_run(am, ctx, percept, halted, user_approved, soul_ref, now)` cascades derive → submit → complete → cache. A module-level singleton (`action_module_singleton_for(dl, ge)`) preserves the pre-R2 `loop_action_step(ctx, lang_kg)` signature — the examples binaries and the existing unit test are byte-untouched.
- **`motor_map.nova`** — the substrate-activation → effector-class registry. Ships empty at MVP: `motor_map_new()`, `motor_map_register(mm, activation_key, effector_class)`, `motor_map_lookup(mm, signature)` (returns `EFF_CLASS_INTERNAL` on miss), `motor_map_size(mm)`, `motor_map_keys(mm)`, `motor_map_entries(mm)`, `motor_map_unregister(mm, key)`. Populated by future rounds; the action_module derive path does not currently consult it (the MVP picks SPEAK or INTERNAL directly from ctx state).

## Loop integration

`src/agent/loop_action.nova::loop_action_step` now routes every call through `action_run` on the module-level singleton. Contract:

- **Signature preserved.** Still `loop_action_step(ctx, lang_kg) -> string`. Callers in `examples/crossengin_chat.nova`, `examples/crossengin_daemon.nova`, and the existing `tests/unit/test_loop_action.nova` remain unchanged.
- **`ctx_output` byte-identical.** For the three pre-R2 fixtures — unknown → `"i do not fully understand that yet"`; percept-present → `"understood"`; else → `"i have nothing to say"` — the emitted `ctx_output` matches pre-R2 verbatim. INTERNAL intents carry the "nothing" template on `IN_TEXT` so the shim can unconditionally write `in_text(intent)` and preserve byte-identity. Asserted in `tests/unit/test_loop_action.nova::test_byte_identity_*` and `tests/unit/test_action_module.nova`.
- **Effector-gate integration.** SPEAK intents call `effector_submit(ACT_SPEAK, ...)` (writing DLK_INTENT), then, if the gate permits, drive the text through `effector_speak` (which writes its own INTENT + OUTCOME pair for the ACT_SPEAK submission). `action_complete` then writes the module's own OUTCOME. When the daemon-wire slot `_la_dl_slot` is 0 (chat REPL, unit-test fixture with no daemon), the submit path short-circuits silently — byte-identical to pre-R2 in that case.
- **Perception link.** The action module reads `pm_last_percept(pm)` from the perception module's singleton (ADR-0092) and attaches it to the intent's `IN_LINKED_PERCEPT` slot for future R3 reasoning tie-back. Today the derive path uses only ctx state; the linked Percept is available for R3+ policy.

The `AG_ACTION_MODULE` slot on `src/agent/autonomous_loop.nova::agent_new` carries a per-agent handle constructed via `action_module_init(agent_dl(a), 0)` — so a future round can drive `action_run` over the SAME per-agent module handle, and decision-log writes land in the agent's own log rather than a global default.

## Reused primitives

- `src/io/effectors/effector_gate.nova::{effector_submit, effector_speak, effector_speak_governed, effector_complete}` — the ADR-0041 safety chain. Returns one of `EFF_EXECUTED` / `EFF_NOTIFIED` / `EFF_SUSPENDED` / `EFF_VETOED` / `EFF_HALTED`; `eff_runs(result)` says whether the effector actually ran.
- `src/safety/reversibility_classifier.nova::ACT_SPEAK` — the action-type integer that `effector_submit` uses to look up the SPEAK permission tier + reversibility class.
- `src/audit/decision_log.nova::{dl_new, dl_append, dl_get, dl_count}` — the append-only decision log the gate writes to.
- `src/parts/goals/goal_engine.nova::goal_arbitrate(engine)` — returns the currently-active goal id when the module was initialized with a non-zero goal engine.
- `src/parts/perception/perception_module.nova::pm_last_percept(pm)` — the Percept minted by the perception loop (ADR-0092), consumed here for source-percept-id + linked-percept cross-refs.

## Follow-ups (post-Phase-N)

- **Populate `motor_map`.** Register real activation-pattern → effector-class mappings so `action_derive_intent` can mint TOOL_CALL / FILE_OP / HTTP_ACTION intents when the substrate's active-concept signature matches a registered pattern. The MVP short-circuits non-SPEAK non-INTERNAL kinds to `EFF_SUSPENDED`; a follow-up round wires the map lookup into derive and dispatches through the corresponding effector primitive.
- **Governed speak.** For intents attached to a soul, switch the submit path from `effector_speak` to `effector_speak_governed(dl, sl, text, ...)` so a constitutionally-forbidden utterance is vetoed at the text level rather than only at the action-type level.
- **Live daemon wiring.** `_la_get_dl_or_null` + `_la_get_goal_engine_or_null` today read the module-level `_la_*_slot` (populated by tests). A follow-up round wires the running daemon's decision log / goal engine into those slots at daemon boot (mirrors ADR-0086's `_ac_config_load` module-cached-config pattern) so every chat-REPL turn writes its INTENT + OUTCOME under the daemon's own log.

See [`docs/adr/`](../../../docs/adr/) for the decisions that bind this component, and the repository [README](../../../README.md) for the substrate overview.
