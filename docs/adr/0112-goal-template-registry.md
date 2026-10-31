# ADR-0112 -- goal-template registry for operand materialization (Phase R4)

Date: 2026-10-05.  Supersedes: --.  Related: ADR-0093 (Phase N R2 action
module), ADR-0107 (Phase R1 motor_map wiring), ADR-0108 (Phase R2
payload-shim + per-class dispatch), ADR-0109 (Phase R3 operand
materialization).

## Context

ADR-0109 (Phase R3) closed the "motor_map hits visible but not
executable" gap by shipping `src/parts/action/operand_builder.nova`
with convention-driven placeholders -- a FILE intent for the
`"write_a_note"` goal always writes to `/tmp/ce_goal_<id>.txt`, a
CODE intent for `"run_code"` always evaluates `"1 + <id>"`. These
executed end-to-end but had no semantic content: every FILE goal shared
one path, every CODE goal shared one arithmetic. ADR-0109's §Follow-up
queued Phase R4 to replace the convention with per-goal operands.

The Phase-1 explore pass evaluated three options:

- **(a) Goal-atom schema extension** -- add operand slots to the goal
  atom itself. HIGH risk: breaks `goal_persistence.nova` serialization
  and the ADR-0048 goal-atom contract. Snapshot formats need rev-bump.
- **(b) Planner that parses `goal_name`** -- extract operands by
  keyword heuristics on the goal name string. MEDIUM risk: no
  NOVA-safe string-parsing primitives exist in `src/parts/goals/`
  today, and the planner would have to be its own module with its own
  ADR + test surface before shipping.
- **(c) Goal-template registry** -- a new `goal_templates.nova` leaf
  module mirroring `motor_map`'s `[key, value]` layout. LOW risk:
  scope ~200 LOC, zero schema impact, byte-identical fallback for
  every pre-R4 caller.

Phase R4 ships option (c). Option (a) is deferred to Phase R6+ (gated
on a demand templates cannot cover). Option (b) is queued as Phase R5:
layered on top of the registry (planner runs on template miss).

## Decision

Ship a new `src/parts/action/goal_templates.nova` leaf module and
grow `operand_builder_build` with an optional 6th `templates` arg:

### 1. `src/parts/action/goal_templates.nova` (new, ~230 LOC)

- Constants prefixed `GT_` to dodge the UPSTREAM §9/§10
  module-level-let collision class: `GT_OBJ_TAG = 9304` (next free in
  the `930x` family after `motor_map`'s `9302` and `action_module`'s
  `9303`), `GT_TAG = 0`, `GT_ENTRIES = 1`.
- Shape: 2-slot handle `[GT_OBJ_TAG, list_new()]`. Each entry is
  `[goal_name_key, template_list]`. Templates are list-of-strings;
  the first slot is the eff_class tag (`"file"` / `"code"` / ...) and
  the rest are operand strings with `%ID%` / `%NAME%` placeholders.
- Public API: `goal_templates_new()`, `gt_is_map(gt)`,
  `goal_templates_size(gt)`, `goal_templates_register(gt, key, template)`
  (upsert; duplicate key overwrites), `goal_templates_lookup(gt, name)`
  (returns the template list or `0` on miss),
  `goal_templates_expand(template_body, goal_id, goal_name)` (returns a
  fresh list with `%ID%` -> `int_to_str(goal_id)` and `%NAME%` ->
  `goal_name` substituted; caller slices `hit[1..]` before passing),
  `goal_templates_default()` (seeded with FILE + CODE).
- Local `_gt_key_eq(a, b)` byte-walker: verbatim copy of
  `motor_map.nova:71-82` to dodge UPSTREAM §1 (`str_eq` on short
  literals is unreliable).
- Local `_gt_substitute(slot, id_str, name)` byte-walker: scans each
  template slot for `"%ID%"` (4 chars) and `"%NAME%"` (6 chars),
  copies plain chars through via `substr(slot, i, 1)`.
- `goal_templates_default()` seeds two entries:
  - `"write_a_note"` -> `["file", "/tmp/ce_note_%ID%.txt", "%NAME%"]`
  - `"run_code"`     -> `["code", "1 + %ID%"]`

### 2. `src/parts/action/operand_builder.nova` -- 6th arg + template probe

- Signature: `operand_builder_build(eff_class, ctx, goal_id, sig,
  goal_name, templates)`.
- Guard: if `templates != 0` AND `gt_is_map(templates) == 1` AND
  `goal_templates_lookup(templates, name)` hits AND the hit's
  eff_class tag matches the dispatched class (checked via local
  `_ob_tag_eq` byte-walker), the function strips the class tag,
  expands the template, and returns.
- Fallthrough: any mismatch -- `templates == 0`, bad handle, lookup
  miss, wrong class tag -- falls through to the pre-R4 R3 convention
  switch. Byte-identical to pre-R4 output.

### 3. `src/parts/action/action_module.nova` -- `AM_GOAL_TEMPLATES` tail-slot

- Tail-append slot 8 (`AM_GOAL_TEMPLATES`) after R1's `AM_MOTOR_MAP`
  (slot 7). Mirrors ADR-0107's tail-append byte-identity contract.
- `action_module_init` populates via `goal_templates_default()`.
- Accessor `am_goal_templates(am)` with `len(am) <= AM_GOAL_TEMPLATES`
  guard (returns 0 when a pre-R4 handle lacks the slot -- the
  operand_builder's 6th-arg `0` short-circuit covers that case).
- Setter `am_set_goal_templates(am, gt)` for tests / integration
  (parallels `am_set_motor_map`).
- `action_derive_intent` passes `am_goal_templates(am)` as the 6th
  arg to `operand_builder_build`.

## Consequences

- **Semantics**: goals seeded in `goal_templates_default` now produce
  per-goal operand tuples. The `"write_a_note"` FILE path becomes
  `/tmp/ce_note_<id>.txt` (NOT `/tmp/ce_goal_<id>.txt`). The
  `"run_code"` CODE expr is byte-identical to the R3 convention
  (`"1 + <id>"`) -- the template happens to express the same formula.
- **HTTP / MCP / AUDIO stay on R3 fallback** this round. A later
  round picks a `%URL%` / `%SERVICE%` placeholder vocabulary (its
  own ADR) and seeds them.
- **Byte-identity for `templates == 0` callers**: the operand_builder
  short-circuits before any new code path on a null handle, so every
  pre-R4 unit test that passes `0` for the 6th arg gets the exact R3
  output. The pre-existing R3 subtest
  `test_derive_hits_motor_map_by_goal_name_mints_file_with_payload`
  explicitly clears the default templates via
  `am_set_goal_templates(am, 0)` to continue exercising the R3 path.
- **Schema impact zero**: no goal atom slot changed; no persistence
  format changed; ADR-0033 / ADR-0048 contracts untouched.
- **Snapshot compatibility**: `goal_templates_default()` is rebuilt
  on every `action_module_init`; the registry does not persist.
  Snapshot/restore paths are untouched (the `AM_GOAL_TEMPLATES` slot
  is not serialized -- action_module is not a snapshot subject).
- **NOVA quirks dodged**: constants prefixed `GT_`; local
  `_gt_key_eq` + `_ob_tag_eq` byte-walkers (no `str_eq` on short
  literals); `len(0)` guarded with explicit `== 0`; no `type_of`,
  no high-bit sentinel equality.

## Follow-up

- **Phase R5** -- layer option (b)'s planner on top: when
  `goal_templates_lookup` misses, call `planner_materialize(goal_name,
  ctx)` to infer operands via keyword heuristics. New ADR.
- Extend template seed vocabulary: add HTTP / MCP / AUDIO templates
  with proper `%URL%` / `%SERVICE%` placeholders (ADR for the
  placeholder DSL).
- Lowercase-normalization / stemming in `goal_templates_lookup` once
  a canonical goal-name normalization policy exists.
- Phase R6+ -- goal-atom schema extension (option (a)) when a demand
  surfaces that templates cannot cover.
