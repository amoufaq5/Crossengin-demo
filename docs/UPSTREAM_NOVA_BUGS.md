# Upstream NOVA bugs tracked by CrossEngin workarounds

This manifest consolidates every NOVA runtime / codegen issue (and the
one container-sandbox policy) that CrossEngin currently works around at
user level, under the standing constraint that `/home/user/NOVA/src/
runtime/*` and `/home/user/NOVA/src/compiler/codegen.nova` remain
off-limits for this repository.

When all five NOVA entries land upstream, the entire workaround surface
retires in one sweep: `src/util/{str_safe,mem_safe,type_safe,gen_id}.nova`
and every R3b-R3f call-site migration can be reverted. Operator action.

Each entry carries: the ADR that diagnoses it, the user-level
workaround, the affected test set, and the suggested upstream fix
location.

## 1. `memcpy_raw` codegen -- OOB on tagged source operand

- **ADR**: 0103
- **Workaround**: `src/util/mem_safe.nova:byte_copy`
- **Tests**: `test_stereo_u8_simd`, LK pair (`test_lk_u8_simd`,
  `test_lk_mulacc_simd`), `test_image_ocr`.
- **Suggested fix**: `/home/user/NOVA/src/compiler/codegen.nova:22248`
  -- emit a tag-strip on the source operand before the `rep movsb`
  instruction sequence.

## 2. `rt_str_to_int` -- `load8` on tagged string handle

- **ADR**: 0103
- **Workaround**: migrate call sites to the `str_to_int` NOVA builtin
  (which untags internally).
- **Tests**: `test_kg_query`, `test_kg_query_agg`, `test_kg_query_ext`,
  `test_fed_daemon_boot`.
- **Suggested fix**: `/home/user/NOVA/src/runtime/string.nova:226` --
  untag the string handle in the `load8` operand before dereferencing.

## 3. `type_of()` regression -- new mapping incompatible with historic constants

- **ADR**: 0104
- **Workaround**: `src/util/type_safe.nova` (`is_int_val`,
  `is_list_val`, `is_str_val`, `is_tagged_list`); call-site migrations
  across `src/kg/query.nova`, `rule_explain.nova`, `rule_inference.nova`,
  `src/schemas/schemas.nova`, `src/federation/distributed_rules.nova`.
- **Tests**: `test_distributed_rules`, `test_kg_query*` (all three),
  schema validation across the KG stack.
- **Suggested fix**: `/home/user/NOVA/src/compiler/codegen.nova:18735`
  -- restore the historical mapping (int=1, string=2, list=3, map=4)
  rather than the currently-emitted (int=0, list=1, string=tagged "1").

## 4. bug-#11 sentinel equality on two-large-operand `==`

- **ADR**: 0105
- **Workaround**: magnitude-probe idiom in
  `src/safety/differential_privacy.nova:dp_is_refused` (replaces
  `v == DP_REFUSED` with `v < 0 - 2000000000`); test-side bn256 fix in
  `tests/unit/test_gossip_dtls_shim.nova`.
- **Tests**: `test_federated_aggregator` (R3f.2 fix retires one class;
  R3g.1 retires a second, independent class in the same test -- see
  entry 7 below).
- **Suggested fix**: in codegen's integer-equality lowering, when both
  operands have tags set, lower as a plain int compare rather than
  routing through the sentinel-equality (pointer-dereference) path.

## 5. `io_println` -- tagged-literal walker + concat-node handling

- **ADR**: 0105
- **Workaround**: switch to the `println` NOVA builtin (which
  normalizes concat nodes) + chunk-split call sites to <=128 B
  segments as belt-and-braces.
- **Tests**: `test_distributed_rules` (`drule_chat_add_cmd` /
  `drule_chat_run_cmd`).
- **Suggested fix**: `src/runtime/io.nova` -- fix the long-literal
  walker's bounds check in `io_println`, and extend the `str_data` /
  `str_len` codegen on `io_println` to handle `concat` AST nodes (not
  only flat literals).

## 7. raw-nanotime-untagged on `&` -- subsequent `*` SEGVs

- **ADR**: 0106
- **Workaround**: `src/safety/differential_privacy.nova:dp_new`
  derives the LCG seed from `epsilon_budget_milli + 7919` (an
  already-tagged caller-supplied int) instead of
  `nanotime() & _LCG_MASK`. Deterministic seed is acceptable for the
  Minimum Viable DP; `dp_new_seeded` remains for callers that need
  to pin the stream.
- **Tests**: `test_federated_aggregator` (R3g.1).
- **Suggested fix**: `/home/user/NOVA/src/compiler/codegen.nova` --
  re-tag the result of `&` (and other bitwise ops) when either operand
  is a raw int from `nanotime()` / other asm-returning builtins, OR
  tag `nanotime()`'s return value itself.

## 8. unresolved-callee SEGV on import-graph miss

- **ADR**: 0106
- **Workaround**: `src/federation/gossip_dtls_shim.nova` defines a
  shim-local `gds_extract_keys`; `tests/unit/test_gossip_dtls_shim.nova`
  switches to it (`gossip_dtls_extract_keys` lived in `gossip.nova`,
  which the test does not import).
- **Tests**: `test_gossip_dtls_shim` (R3g.2).
- **Suggested fix**: NOVA's whole-program link should FAIL compilation
  on an unresolved call rather than lower it to a null callee that
  SEGVs on entry.

## 9. Assembler rejects duplicate module-private `_starts_with` symbol

- **ADR**: 0111 (R6 close-out section).
- **Workaround**: **SHIPPED** via option (a): `_starts_with` →
  `_snap_starts_with` in `src/persistence/snapshot_disk.nova`.
  14 occurrences renamed (1 definition + 13 call sites); zero test
  edits (grep confirmed). `crossengin_daemon.nova` now LINKs.
  `crossengin_chat.nova` still fails at link time, but with a
  different collision (`_g_PC_TAG`) — see bug #10 below.
  Hypothetical alternative (b) — rename `_starts_with` →
  `_tkgsync_starts_with` in `src/io/transducers/kg_sync.nova:410`
  (~15 in-module caller sites + 4 call sites in
  `tests/unit/test_kg_sync.nova:336-339`) — was NOT taken because
  option (a) needed no test edits.
- **Tests**: no unit coverage of the collision itself. Affected binary
  builds:
  * `examples/crossengin_chat.nova` — was blocked at link time from
    Phase M R1 (`5f2e9f2`) until this commit; `_starts_with` collision
    is resolved, but a second collision (`_g_PC_TAG`, bug #10) still
    blocks the chat binary.
  * `examples/crossengin_daemon.nova` — was blocked at link time from
    Phase M R6 (`9cbbf12`) until this commit; every R6 unit test passes
    (hook is exercised via the Session accessor chain), and the daemon
    binary now LINKs.
- **Context**: NOVA's whole-program assembly emits one global symbol
  per `fn` definition without module-mangling. Collisions surface only
  when a `main()` transitively pulls BOTH offending modules
  (`persistence/snapshot_disk` + anything importing
  `io/transducers/kg_sync` — e.g. via `federation/gossip`). The other
  20+ `*_starts_with` definitions in the tree all carry a module prefix
  (`_gossip_starts_with`, `_sr_starts_with`, `_att_starts_with`, …)
  and do not collide.
- **Suggested fix**: NOVA compiler should mangle module-private names
  with the module path (e.g.
  `_nova_persistence_snapshot_disk__starts_with`). Alternatively a
  loader-side allow-list of "weak" module-private symbols. The
  user-side rename in option (a) above is a one-line fix that landed
  via this commit; it unblocks `crossengin_daemon.nova`. The compiler
  mangling fix is still desirable because the same shape surfaces on
  module-level `let` globals too (see bug #10).

## 10. Assembler rejects duplicate module-private `_g_PC_TAG` symbol

- **ADR**: TBD (surfaced immediately after bug #9 workaround landed).
- **Workaround**: none shipped. Candidate rename rounds:
  (a) Rename `PC_TAG` → `PR_PC_TAG` (or similar) in
      `src/parts/reasoning/proof_checker.nova:86`; audit callers in the
      proof-checker module.
  (b) Rename `PC_TAG` → `PA_PC_TAG` (or similar) in
      `src/parts/perception/perception_atoms.nova:90`; audit callers
      including `perception_atoms.nova:246` and any transitive
      consumers in the perception subsystem.
  Scope not yet characterised; option (a) likely smaller because
  `perception_atoms` has more downstream readers.
- **Tests**: no unit coverage of the collision itself. Affected binary
  builds:
  * `examples/crossengin_chat.nova` — blocked at link time; this
    collision was previously masked by bug #9's earlier `_starts_with`
    collision, surfaced only after option (a) in bug #9 shipped.
- **Context**: same shape as bug #9 but on module-level `let` bindings
  rather than `fn` definitions. Two modules both declare
  `let PC_TAG = ...` at module scope, which NOVA emits as the global
  symbol `_g_PC_TAG`:
  * `src/parts/reasoning/proof_checker.nova:86`: `let PC_TAG = 1`
  * `src/parts/perception/perception_atoms.nova:90`: `let PC_TAG = 0`
  Collision surfaces when a `main()` transitively pulls BOTH modules
  (chat does; daemon does not, which is why daemon LINKs post bug-#9
  workaround while chat still errors).
- **Suggested fix**: same shape as bug #9's suggested fix — NOVA
  compiler should mangle module-level `let` names with the module
  path (e.g. `_g_nova_parts_reasoning_proof_checker__PC_TAG`). The
  user-side rename in either option above is a short-term unblock.

## 6. Sandbox O_CREAT policy (container, not NOVA)

- **ADR**: 0104
- **Workaround**: sandbox-skip idiom (one-shot probe at test start,
  guarded `main()` short-circuit) applied in `test_audio_wakeword`,
  `test_chat_state_persistence`, `test_decision_log_durable`,
  `test_fed_daemon_transport`.
- **Tests**: as listed above.
- **Context**: not a NOVA bug; the test-container filesystem sandbox
  blocks `sys_open(O_CREAT, ...)` under both `/tmp` and `$HOME`. On a
  less-restricted CI host these tests should run their full battery
  (the skip collapses to the probe + banner). Operator action is to
  relax the sandbox policy for the CI runner, not patch NOVA.

## Retirement order

Fixing (3) first clears four tests on its own and unblocks any schema
validation downstream (the schemas gate rejects every int under the
regression). (1) and (2) can land in either order. (4) and (5) are
independent of the others. (6) is operator / infra, out of band.
(9) workaround SHIPPED; upstream compiler mangling fix still desirable
for defense-in-depth. (10) is a new sibling collision on module-level
`let` bindings (`_g_PC_TAG`), still blocking `crossengin_chat`;
same shape as (9) but on globals rather than functions.
