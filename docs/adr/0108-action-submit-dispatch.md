# ADR-0108 -- payload-shim + per-class dispatch in `action_submit` (Phase R2)

Date: 2026-10-03.  Supersedes: --.  Related: ADR-0093 (Phase N R2 action
module), ADR-0107 (Phase R1 motor_map wiring).

## Context

ADR-0107 (Phase R1) wired `motor_map_lookup` into
`action_derive_intent` so motor_map hits mint non-SPEAK intents, but
`action_submit` was unchanged -- every non-SPEAK/non-INTERNAL kind
still returned `[EFF_SUSPENDED, -1]`. The six effector primitives
already exist (`effector_file_ops`, `effector_http_action`,
`effector_code_exec`, `effector_mcp`, `audio_speak`, `tool.nova`), but
R1's constructors (`intent_file_new`, `intent_http_new`, etc.) carry
only verb-token strings in `IN_TEXT` ("write_a_note", "fetch_url",
"run_code") -- NO operands. The effector primitives need real args
(`path+content`, `url`, `expr`, `service+request`, `out_path`). R2
cannot dispatch meaningfully without a payload shim first.

## Decision

Phase R2 ships three mechanical additions in one commit:

### 1. Payload-shim slots in `action_atoms.nova`

Eight new slots **tail-appended** after `IN_REASON` (ADR-0093 /
ADR-0107 byte-identity contract preserved -- any caller using the
pre-R2 slot indices 0..11 is unaffected):

- `IN_FILE_PATH` [12], `IN_FILE_CONTENT` [13]
- `IN_HTTP_URL` [14], `IN_HTTP_CANNED` [15]
- `IN_CODE_EXPR` [16]
- `IN_MCP_SERVICE` [17], `IN_MCP_REQUEST` [18]
- `IN_AUDIO_OUT_PATH` [19]

The existing 5-arg constructors (`intent_file_new`, `intent_http_new`,
`intent_code_new`, `intent_audio_new`, `intent_mcp_new`) continue to
work; payload slots default to `""`. New parallel `_with_payload`
constructors populate the operands. Per-kind accessors
(`in_file_path`, `in_file_content`, `in_http_url`, `in_http_canned`,
`in_code_expr`, `in_mcp_service`, `in_mcp_request`,
`in_audio_out_path`) return `""` when the slot is absent (defensive
length check for snapshot-restored or older-schema intents).

### 2. Per-class dispatch in `action_submit`

The pre-R2 "non-SPEAK -> SUSPENDED" fallthrough is replaced by a
switch:

- `IN_KIND_SPEAK` -> `ACT_SPEAK` + `effector_speak` (pre-R2 shape,
  verbatim).
- `IN_KIND_FILE_OP` -> `ACT_WRITE_LOCAL` + `file_ops_write(path, content)`.
- `IN_KIND_HTTP_ACTION` -> `ACT_NET_FETCH` + `http_action_run(url, 1,
  canned)` (simulated=1 pinned for hermeticity).
- `IN_KIND_CODE_EXEC` -> `ACT_READ_LOCAL` + `code_exec_run(expr)`.
- `IN_KIND_MCP` -> `ACT_NET_FETCH` + `mcp_call_direct(service,
  request, request)`.
- `IN_KIND_AUDIO` -> `ACT_SPEAK` + `effector_speak_audio(text, out_path)`.
- `IN_KIND_TOOL_CALL` -> re-dispatch via `in_effector_class`
  (FILE/HTTP/CODE/MCP/AUDIO), else SUSPENDED.
- `IN_KIND_INTERNAL` -> no-op (unchanged).

Each non-SPEAK branch runs the four-step pattern: `effector_submit`
(writes DLK_INTENT) -> `eff_runs(result)` check -> primitive call ->
`effector_complete` (writes DLK_OUTCOME). A null `dl` short-circuits
non-SPEAK branches to SUSPENDED (no audit surface).

### 3. Operand-missing fallthrough

When a kind's required operand slot is empty (R1-era verb-token-only
intent minted by `action_derive_intent`), the branch returns
`[EFF_SUSPENDED, -1]` with no gate call. This preserves R1 behavior:
motor_map hits still mint and are visible to downstream observers but
do not execute until Phase R3 materializes operands at derive time.
`action_derive_intent` is **unchanged** this round -- the stepping-
stone discipline ADR-0107 established keeps backward compatibility.

### Non-goals (deferred to R3)

- Planner / goal-engine operand materialization at derive time.
- Live-network HTTP (ADR-0054 `lp_fetch` gating + TLS maturity).
- Richer audio contract (voice-clone / TTS mode selection beyond
  Mode 1/3 defaults).

## Consequences

- **Byte-identity preserved.** Tail-append + SPEAK verbatim keep the
  three loop_action fixtures (`"i do not fully understand that yet"`,
  `"understood"`, `"i have nothing to say"`) byte-identical.
  `test_loop_action` 11/11 OK unchanged.
- **Six effector classes now executable.** `test_action_module`
  74 passed (up from 61) with 7 new subtests: CODE / HTTP / MCP / TOOL
  meta always run; FILE + AUDIO gate on a `_tmp_write_works()` probe
  (same pattern as R3e.4 / ADR-0104); operand-missing fallthrough
  verified via a verb-token-only `intent_file_new` subtest.
- **The 2 pre-existing fails are UNCHANGED (and NOT about dispatch).**
  `submit result EXECUTED expected=1 got=2` and `run unknown eff
  EXECUTED expected=1 got=2` are SPEAK-path tier semantics:
  `perm_effective_tier(ACT_SPEAK)` = `max(PERM_AUTO,
  reversibility_floor(REV_RECOVERABLE))` = `PERM_NOTIFY` -> `EFF_NOTIFIED`
  (= 2). The tests assert `EFF_EXECUTED` (= 1). This mismatch
  predates R2 and is orthogonal to the per-class dispatch; the plan's
  hope that dispatch work would flip them was incorrect. Fixing the
  tests to accept either `EFF_EXECUTED` or `EFF_NOTIFIED` (via
  `eff_runs`) is a mechanical follow-up for a separate round; this
  ADR documents the diagnosis so a reader can retire the fails
  intentionally rather than by accident.
- **Non-SPEAK result codes.** Most non-SPEAK branches land on
  `EFF_NOTIFIED` (ACT_WRITE_LOCAL / ACT_NET_FETCH / ACT_SPEAK -> NOTIFY
  tier); CODE lands on `EFF_EXECUTED` (ACT_READ_LOCAL -> AUTO).
  `eff_runs` returns 1 for both so the per-class branches drive the
  primitive uniformly; subtests assert `eff_runs(result) == 1` instead
  of pinning a specific code (except CODE / TOOL meta -> code, which
  are EXECUTED-specific).
- **No new NOVA quirks hit.** Reused `tr_ok` + `len(path) == 0`
  guards (defensive length check in each payload accessor); no raw
  `str_eq`, no `type_of`, no `memcpy_raw`; `len(0)` dodged with
  pre-check in each accessor.
- **Spot-check canaries all OK.** `test_motor_map` 52, `test_effectors`
  19, `test_effector_gate` 23, `test_action_atoms` 79,
  `test_perception_module` 45, `test_arithmetic` 23,
  `test_type_of_probe` 15, `test_distributed_rules` 42,
  `test_fed_daemon_boot` 49, `test_loop_action` 11 -- all green.

## Follow-up (Phase R3)

- Teach `action_derive_intent` to materialize operands from the goal
  engine / belief store so motor_map hits produce executable intents
  end-to-end (not just verb-token-only shells).
- Retire the two pre-existing SPEAK-tier fails by rewriting the
  assertions to accept both `EFF_EXECUTED` and `EFF_NOTIFIED` (via
  `eff_runs`) -- the test is older than the current gate semantics.
- Live HTTP once TLS maturity + rate-limit audit are complete.
- Richer audio-mode selection (TTS vs voice-clone vs synth) + the
  audio sidecar protocol.
