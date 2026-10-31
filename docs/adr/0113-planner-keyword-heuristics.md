# ADR-0113 -- planner keyword heuristics for operand materialization (Phase R5)

Date: 2026-10-05.  Supersedes: --.  Related: ADR-0093 (Phase N R2 action
module), ADR-0107 (Phase R1 motor_map wiring), ADR-0108 (Phase R2
payload-shim), ADR-0109 (Phase R3 operand materialization), ADR-0112
(Phase R4 goal-template registry).

## Context

ADR-0112 (Phase R4) shipped `src/parts/action/goal_templates.nova`, a
per-goal operand-template registry probed by `operand_builder_build`
on an exact-match of `goal_name`. ADR-0112 §Follow-up explicitly queued
Phase R5 as the natural layer on top: option (b) from the phase-1
explore -- a planner that extracts operands from natural-language-ish
`goal_name` strings via keyword heuristics -- stacks between the R4
registry and the R3 convention floor. The three options from
ADR-0112's explore were (a) goal-atom schema extension (HIGH risk,
breaks `goal_persistence` + ADR-0033 contract), (b) planner (MEDIUM
risk, needs its own module/ADR), (c) template registry (LOW, shipped
as R4). This ADR ships option (b) as the middle layer. Option (a)
remains deferred to Phase R6+ when a demand neither templates nor
planner can cover surfaces.

## Decision

Ship a new `src/parts/goals/planner.nova` leaf module and insert a
planner probe into `operand_builder_build` between the R4 template
probe and the R3 convention switch:

### 1. `src/parts/goals/planner.nova` (new, ~160 LOC)

- Public API: `planner_materialize(goal_name, eff_class, goal_id) ->
  list`. Returns a populated operand tuple on heuristic hit; returns
  `list_new()` (empty) on miss. The caller interprets empty as
  "no planner hit -- fall through to R3 fallback".
- Four heuristics ship this round, one per payload-bearing effector
  class. Each heuristic's prefix ends with a **SPACE**:
  - `PL_FILE_PREFIX  = "write note "` -- `EFF_CLASS_FILE` -> emits
    `["/tmp/ce_note_<goal_id>.txt", <tail>]`.
  - `PL_HTTP_PREFIX  = "fetch "`      -- `EFF_CLASS_HTTP` -> emits
    `[<tail>, ""]` (bare URL; no scheme validation).
  - `PL_CODE_PREFIX  = "run "`        -- `EFF_CLASS_CODE` -> emits
    `[<tail>]`.
  - `PL_AUDIO_PREFIX = "say "`        -- `EFF_CLASS_AUDIO` -> emits
    `["/tmp/ce_speech.wav"]` (text comes from `in_text`; operand is
    just the output path).
  - `EFF_CLASS_MCP` / `_TOOL` / `_INTERNAL` -- no heuristic this
    round. Return empty so the caller falls through to R3 convention
    (MCP) or the pre-R2 5-arg path (TOOL / INTERNAL).
- Constants prefixed `PL_` to dodge the UPSTREAM §9/§10 module-level
  `let` collision class.
- Local `_pl_starts_with(s, prefix)` byte-walker: mirrors
  `motor_map.nova:71-82`'s `_mm_key_eq` shape, tweaked for
  "starts-with" semantics (allow `s` longer than `prefix`). Dodges
  UPSTREAM §1 (`str_eq` on short literals is unreliable).
- Local `_pl_tail_after(s, n)` returns `substr(s, n, len(s) - n)`
  with explicit `len == 0` and `n > len(s)` guards (SEGV avoidance
  per the standing NOVA quirks note).
- Imports: `../action/action_atoms.nova` for the `EFF_CLASS_*`
  constants.

### 2. `src/parts/action/operand_builder.nova` -- planner probe insertion

- New import: `../goals/planner.nova`.
- A planner probe sits between the R4 template-miss fallthrough and
  the R3 convention switch:
  ```
  let planner_ops = planner_materialize(name, eff_class, goal_id)
  if len(planner_ops) > 0 { return planner_ops }
  // ...R3 convention switch continues unchanged...
  ```
- `operand_builder_build` signature is unchanged (6 args).
- Three-layer precedence (highest first): R4 templates -> R5 planner
  -> R3 convention.

### 3. Byte-identity contract (trailing-space-prefix invariant)

Every planner heuristic's prefix ends with a **SPACE**. Motor_map's
default vocabulary uses **UNDERSCORES** (`"write_a_note"`,
`"run_code"`, ...). Therefore:
- `_pl_starts_with("write_a_note", "write note ")` returns 0 (mismatch
  at offset 5: `_` vs space).
- `_pl_starts_with("run_code", "run ")` returns 0 (mismatch at
  offset 3: `_` vs space).
Every pre-R5 R3+R4 test exercises underscore vocabulary, so no planner
heuristic can trigger on their call paths. Byte-identity is preserved
across the whole R3+R4 test surface.

## Consequences

- **Semantics**: goals carrying natural-language-ish phrases
  (`"write note shopping list"`, `"fetch https://example.com"`,
  `"run 2 + 3"`, `"say hello"`) now mint executable operands without
  requiring a template registration. Operators can wire new behaviors
  by naming goals accordingly -- no code change, no registry edit.
- **Motor_map default vocabulary unaffected**: `"write_a_note"` and
  `"run_code"` continue to flow through the R4 default-templates path
  (and, with `templates=0`, through the R3 convention floor).
  Byte-identity canary passes.
- **HTTP operand is a bare URL**: no scheme validation. Operator
  expectation this round is sim-mode effectors; live HTTP + TLS +
  rate-limit audit remains on the R5+ follow-up queue.
- **AUDIO operand is just the output path**: the actual speech text
  comes from `in_text`, which `action_submit` already extracts from
  the Intent record. The planner emits only the sim-mode output
  wav path.
- **Class-mismatch is a miss**: `"fetch url"` matches `PL_HTTP_PREFIX`
  only when `eff_class == EFF_CLASS_HTTP`. Dispatching it under FILE
  (or any other class) falls through to R3.
- **Empty goal_name is a miss**: an explicit short-circuit before the
  per-class switch returns `list_new()` for `""`. Guards the "no goal
  engine wired" case that `operand_builder_build` already tolerates.
- **Schema impact zero**: no goal atom slot changed; no persistence
  format changed; ADR-0033 / ADR-0048 contracts untouched; snapshot
  module untouched.
- **NOVA quirks dodged**: `PL_` constant prefix, local
  `_pl_starts_with` + `_pl_tail_after` byte-walkers (no `str_eq` on
  short literals), `len == 0` guard first, `substr` byte-walker.

## Follow-up

- **Phase R6+ -- richer parser**: quoted-string support (`"write note
  \"hello world\""`), multi-argument syntax, operand escaping.
- **MCP + TOOL + INTERNAL heuristics**: once a canonical service /
  tool-name vocabulary surfaces, extend the planner table.
- **Ctx-driven heuristics**: scan `AC_ACTIVE` concept handles for
  operand hints (e.g. a resolved URL in the active-concept set
  overrides a planner-inferred tail).
- **Lowercase-normalization / stemming** in `planner_materialize`
  once a canonical goal-name normalization policy exists -- same
  dependency as `motor_map_lookup` and `goal_templates_lookup`.
- **Phase R6+ -- goal-atom schema extension** (option (a)) if a demand
  surfaces that neither templates nor planner cover.
