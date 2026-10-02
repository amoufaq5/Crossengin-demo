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
- **Tests**: `test_federated_aggregator` (partial; R3f.2 fix is correct
  for its own class but a secondary SEGV remains -- queued for R3g).
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
