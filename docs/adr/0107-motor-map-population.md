# ADR-0107 -- motor_map population + action_module wiring (Phase R1)

Date: 2026-10-03.  Supersedes: --.  Related: ADR-0093 (Phase N R2 action
module; motor_map shell), ADR-0106 (Phase Q segfault-arc closeout).

## Context

ADR-0093 shipped `src/parts/action/motor_map.nova` -- a 177-line
substrate-activation -> effector-class registry with a complete tested
public API (`motor_map_new`, `_register`, `_lookup`, `_size`, `_keys`,
`_entries`, `_unregister`) -- but deferred the "R3 preview" items:

1. No startup seed data: `motor_map_default()` did not exist, every
   `action_module_init` got an empty registry.
2. No integration into `action_derive_intent`: the derive path
   short-circuited non-SPEAK/non-INTERNAL kinds to `[EFF_SUSPENDED, -1]`
   without ever consulting the map.
3. No signature builder: the ADR-0093 R3-preview "canonical vocabulary"
   (`"search_the_web"`, `"write_a_note"`, `"call_tool"`) was implied by
   test fixtures but had no helper canonicalizing `(ctx, goal_id)` into
   a lookup key.

Phase Q (ADR-0100 .. ADR-0106) closed the 29-SEGV arc; motor_map
population is the first post-Q feature item.

## Decision

Phase R1 ships (1), (2), (3) as one commit. **Non-goal**: the effector
primitives (`src/io/effectors/{tool,file,http,code,audio,mcp}.nova`)
and `action_submit`'s dispatch rewrite are deferred to Phase R2. New
non-SPEAK intents mint and are visible to downstream observers but
`action_submit` continues to return `[EFF_SUSPENDED, -1]` for them
(unchanged behavior at the gate).

### Three additions

1. **`motor_map_default()`** -- returns a `motor_map_new()`
   pre-registered with the canonical vocabulary:
   `search_the_web`, `fetch_url` -> HTTP; `write_a_note`, `read_file`
   -> FILE; `call_tool` -> TOOL; `run_code` -> CODE; `play_audio`,
   `synth_audio` -> AUDIO; `invoke_mcp` -> MCP.  (Non-exhaustive on
   purpose; Phase R2 expands the vocabulary alongside the effector
   primitives.)

2. **`mm_activation_signature(ctx, goal_id) -> string`** -- a
   deterministic key builder.  Shape:
   `"g<goal_id>:a<active0>:a<active1>:..."` when ctx carries active
   concept handles, degrading to `"g<goal_id>"` on a null or
   active-less ctx.  Reads `ctx[5]` positionally rather than importing
   `AC_ACTIVE` (motor_map is a leaf module).  Guards against the
   `len(0)` NOVA quirk with an explicit 0-check before `len`.
   Hashed-signature variants are deliberately deferred.

3. **`AM_MOTOR_MAP` slot** -- **tail-appended at index 7** to preserve
   the existing seven slot offsets, satisfying the ADR-0093
   byte-identity contract (any test asserting `AM_DL=1`, `AM_LAST_INTENT=3`,
   etc stays correct). Seeded with `motor_map_default()` at
   `action_module_new`. `action_derive_intent` consults it BEFORE the
   pre-R2 SPEAK/INTERNAL decision tree -- on an EFF_CLASS_TOOL/FILE/
   HTTP/CODE/AUDIO/MCP hit, mint the matching kind; otherwise fall
   through unchanged. Also exposes `am_motor_map(am)` and
   `am_set_motor_map(am, mm)` for integration/tests.

### Intent constructors

`action_atoms.nova` already shipped `intent_speak_new`, `intent_internal_new`,
and a placeholder `intent_tool_new`. Phase R1 adds parallel
constructors for the remaining classes: `intent_file_new`,
`intent_http_new`, `intent_code_new`, `intent_audio_new`,
`intent_mcp_new`. Each mirrors `intent_tool_new`'s shape (text payload
+ goal_id + confidence + source_percept_id), sets `IN_KIND` and
`IN_EFFECTOR_CLASS` directly, and takes no `effector_class` override --
the mapping is fixed per constructor.

## Consequences

- **Byte-identity preserved.** The tail-append and lookup-then-fallthrough
  shape keep the pre-R2 three fixtures (`"i do not fully understand
  that yet"`, `"understood"`, `"i have nothing to say"`) byte-identical.
  `test_action_module.nova` holds at 53 passed / 2 pre-existing FAILs
  (`submit result EXECUTED` + `run unknown eff EXECUTED`, carried from
  R3e at tip `e5dcaf9`; unchanged by this round).  Six new subtests
  (`test_motor_map`: 2 added, 52 total checks; `test_action_module`: 2
  added, 61 total passed) all PASS.
- **Non-SPEAK intents visible but non-executing.** `action_submit`'s
  SUSPENDED-fallback is UNCHANGED. A motor_map hit mints a TOOL/FILE/
  HTTP/CODE/AUDIO/MCP intent that reaches the decision log via the
  `_am_record_intent` tally but returns `[EFF_SUSPENDED, -1]` at the
  gate. Phase R2 is required for execution.
- **No NOVA quirk hit.** The signature builder uses the proven
  `"literal" + int_to_str(x)` concat pattern (same as
  `action_module.nova:249` trace-ref builder); no raw `type_of`, no
  raw `str_eq`, no `memcpy_raw`.  `len(0)` dodged with 0-check.
- **Spot-check canaries.** `test_perception_module`, `test_arithmetic`,
  `test_type_of_probe`, `test_distributed_rules`, `test_fed_daemon_boot`
  all still OK.

## Follow-up (Phase R2)

Ship `src/io/effectors/{tool,file,http,code,audio,mcp}.nova` and rewrite
`action_submit` so non-SPEAK intents dispatch per-class instead of
hitting the SUSPENDED fallback. Separate ADR. Expand `motor_map_default`'s
vocabulary alongside the new primitives.

Potential later: a hashed-signature variant (string salt collisions
grow with the active-concepts count); currently deferred -- the
plain-string key is intentional for debuggability.
