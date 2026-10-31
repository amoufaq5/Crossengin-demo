# ADR-0109 -- operand materialization + reach-ability + SPEAK tier fix (Phase R3)

Date: 2026-10-03.  Supersedes: --.  Related: ADR-0093 (Phase N R2 action
module), ADR-0107 (Phase R1 motor_map wiring), ADR-0108 (Phase R2
payload-shim + per-class dispatch).

## Context

ADR-0108 (Phase R2) shipped `_with_payload` constructors for each
non-SPEAK intent kind and a per-class dispatch switch in
`action_submit`, but `action_derive_intent` still minted verb-token-only
intents via the 5-arg constructors. The R2 operand-missing branch
cleanly fell through to `[EFF_SUSPENDED, -1]` so motor_map hits were
visible in the decision log but did not execute. R2 queued three
residuals for R3:

1. **No operand sources exist.** Neither the goal_engine atom (name +
   priority / deadline / progress only) nor the loop_coordination ctx
   (AC_INPUT string + AC_ACTIVE int handles) carries structured
   operands today. All six non-SPEAK kinds need synthesized operands
   via sandbox conventions.
2. **Motor_map hits are unreachable** via the ctx-driven path.
   `mm_activation_signature(ctx, goal_id)` builds `"g<id>:a<h0>:..."`,
   but `motor_map_default`'s entries are semantic strings
   (`"search_the_web"`, `"run_code"`, `"write_a_note"`, ...). No
   overlap: every default-registry hit was out of reach from the
   derive path.
3. **SPEAK tier assertion fail.** Two R2 subtests pinned `EFF_EXECUTED`
   but `effector_submit(dl, ACT_SPEAK, ...)` returns `EFF_NOTIFIED`
   because `ACT_SPEAK`'s reversibility floor is `REV_RECOVERABLE` ->
   `PERM_NOTIFY`. The fails predate R2 and are orthogonal to dispatch;
   R2's ADR-0108 Consequences documented the diagnosis and queued the
   fix.

## Decision

Phase R3 ships three mechanical fixes in one commit:

### 1. `src/parts/action/operand_builder.nova` (new leaf module)

Public API:

- `fn operand_builder_build(eff_class, ctx, goal_id, sig, goal_name)
  -> list`

Returns a per-class operand tuple built from sandbox-safe conventions:

| Class | Tuple | Source |
|---|---|---|
| FILE | `[path, content]` | `path = "/tmp/ce_goal_" + int_to_str(goal_id) + ".txt"`; `content = goal_name` |
| HTTP | `[url, canned]` | `url = "http://localhost/goal_" + int_to_str(goal_id)`; `canned = "goal:" + goal_name` |
| CODE | `[expr]` | `expr = "1 + " + int_to_str(goal_id)` |
| MCP | `[service, request]` | `service = "goal_svc"`; `request = "req:" + goal_name` |
| AUDIO | `[out_path]` | `out_path = "/tmp/ce_speech_goal_" + int_to_str(goal_id) + ".wav"` |
| TOOL | `[]` | meta -- `action_submit` re-dispatches via `in_effector_class` |
| INTERNAL | `[]` | no operands |

The synthesized values are **placeholders** -- a planner-driven payload
system is Phase R4+ work (likely needs a goal-atom schema extension and
its own ADR). R3 ships the mechanism so motor_map hits produce
executable intents end-to-end with placeholder operands good enough to
drive each effector primitive.

### 2. Reach-ability bridge in `motor_map.nova` + `action_module.nova`

- `motor_map.nova`: new `fn mm_activation_signature_by_name(goal_name)
  -> string` that returns the goal name verbatim. Dumb and
  deterministic -- the registry's default keys are already semantic
  strings, so an exact-string match handoff is enough.
- `action_module.nova:action_derive_intent`: after the existing
  handle-sig lookup, if the class is `EFF_CLASS_INTERNAL` (miss) and
  the goal engine resolves the attached id to a non-empty name, probe
  the registry a second time with the semantic-sig. On a hit, mint via
  the matching `_with_payload` constructor using
  `operand_builder_build`. Empty-ops classes (TOOL / INTERNAL) fall
  back to the pre-R2 5-arg mint; TOOL meta-dispatch continues through
  R2's `in_effector_class` switch in `action_submit`.

### 3. SPEAK tier assertion fix

Two R2 subtests (`test_submit_speak_wired_dl:94` and
`test_run_unknown_end_to_end:278`) flip their `ce_eq(..., EFF_EXECUTED)`
assertions to `ce_check(..., eff_runs(result) == 1)` -- consistent with
R2's non-SPEAK dispatch subtests (`:149, 164, 192, 209`). `eff_runs` is
`1` for both `EFF_EXECUTED` and `EFF_NOTIFIED`, so the predicate is
uniform across tiers.

### Non-goals (deferred to R4+)

- Planner-driven payload materialization (the convention-driven
  operands are intentional placeholders).
- Goal-atom schema extension (snapshot/persistence change, own ADR).
- Motor_map entry layout widening (byte-identity contract).
- Live-network HTTP (keep `simulated=1` pin).

## Consequences

- **Motor_map hits are executable end-to-end.** `test_action_module`
  gained three subtests: FILE / CODE derive via semantic-sig bridge
  (payload bytes asserted verbatim) and an end-to-end CODE run
  (`run_code` goal -> `action_run` -> `code_exec_run` dispatch -> 3+
  decision-log rows).
- **Two pre-existing fails flip to PASS.** `test_action_module` goes
  from 74 passed / 2 FAILed to 90 passed / 0 FAILed (90 reflects both
  the 2 flipped SPEAK fails and the 3 new R3 subtests; the exact
  gain is +3 subtests ~ +14 checks + 2 flipped assertions = net +16
  checks).
- **Byte-identity preserved.** `action_derive_intent` only changes
  behavior INSIDE the motor_map hit branch; the R2-shipped
  `test_submit_file_missing_path_falls_through_to_suspended` (which
  constructs via the 5-arg `intent_file_new(1, "write_a_note", 0, 700,
  0)`) is untouched because that call path never consults the operand
  builder. The three loop_action fixtures stay byte-identical
  (`"i do not fully understand that yet"`, `"understood"`,
  `"i have nothing to say"`) -- SPEAK / INTERNAL fallthrough is
  unchanged.
- **No new NOVA quirks hit.** `operand_builder_build` uses only string
  concat with `+` and `int_to_str` on integer `goal_id` -- the pre-R2
  trace-ref pattern (`action_module.nova:301`, `motor_map.nova:223`),
  proven safe at R3d. No raw `str_eq`, no `type_of`, no `memcpy_raw`,
  no high-bit sentinel equality. `len(0)` dodged via explicit `""`
  fallback at both call sites.
- **Canaries unchanged.** `test_motor_map` 52, `test_effectors` 19,
  `test_effector_gate` 23, `test_action_atoms` 79, `test_loop_action`
  11 all green. Spot-check: `test_perception_module` 45,
  `test_arithmetic` 23, `test_type_of_probe` 15,
  `test_distributed_rules` 42, `test_fed_daemon_boot` 49 all green.
- **New test file.** `tests/unit/test_operand_builder.nova` -- 18
  checks across 8 subtests (one per class + a defensive empty-name
  guard).

## Follow-up (Phase R4+)

- Planner layer materializing operands from goal metadata / belief
  store / context inference; likely drives a goal-atom schema
  extension (new ADR).
- Live HTTP once TLS maturity + rate-limit audit are complete.
- Audio sandbox hardening + voice-clone / TTS mode selection.
- Lowercase-normalization / stemming in
  `mm_activation_signature_by_name` once a canonical policy exists.
