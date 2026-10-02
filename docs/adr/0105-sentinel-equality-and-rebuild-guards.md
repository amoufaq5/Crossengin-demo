# ADR-0105 -- sentinel-equality (bug-#11) workarounds and rebuild-guard reinforcement

Status: Accepted
Date: 2026-10-02
Context: Phase Q R3f (segfault-arc tail close-out). Follows ADR-0104
(type_of + Cluster D/E).

## Context

R3e (`e5dcaf9`) honestly-deferred four tests to R3f: `test_distributed_rules`,
`test_federated_aggregator`, `test_gossip_dtls_shim`,
`test_ingest_file_multimodal`. ADR-0104 §Follow-up queued them under
"NOVA bug-#11 family: sentinel equality on tagged pointers whose high
bit is set".

R3f ships four sub-passes targeting these tests plus a hygiene pass
(R3f.5) that converts three DEAD rebuild guards in `parts/perception`
and `parts/action` singletons from list-identity `!=` to generation-id
int-equality. R3f.6 seeds `docs/UPSTREAM_NOVA_BUGS.md`. Standing
constraint: `/home/user/NOVA/src/runtime/*` and `codegen.nova` remain
off-limits.

## Diagnosis

Four-thread code-bytes breakdown of the R3f queue, with each test's
real root (two surprises noted below):

- **R3f.1 `test_distributed_rules` (SEGV in `drule_chat_add_cmd` /
  `_run_cmd`).** `io_println` in `src/runtime/io.nova` crashes on BOTH
  long literals (its tagged-literal walker reads past the literal's
  terminator) AND on dynamically-concatenated string arguments: the
  `str_data` / `str_len` codegen for `io_println` assumes a flat literal
  and dereferences a `concat`-node operand as if it were a buffer. The
  Phase-1 inference from R3e was "long literal only"; the actual bug
  class is broader. **Surprise**: switching to the `println` NOVA
  builtin fixes both because `println` normalizes concat nodes before
  dispatch. All four crash sites also chunk-split to <=128 B segments
  as a belt-and-braces guard.
- **R3f.2 `test_federated_aggregator` (SEGV, no output).** The
  `dp_is_refused(v)` helper's `v == DP_REFUSED` with `DP_REFUSED =
  -(2^31 - 1)` reaches NOVA codegen bug-#11: two large-magnitude
  operands whose tagged representation flips a high bit are forwarded
  to the sentinel-equality path which treats one operand as a pointer
  and dereferences a non-pointer page. The DP value space is bounded
  far from `|v| > 2 * 10^9`, so a magnitude-probe idiom (`v < 0 -
  2000000000`) is observationally equivalent and sidesteps the
  codegen path entirely.
- **R3f.3 `test_gossip_dtls_shim` (SEGV, early tests fail).** Phase-1
  hypothesis was "same sentinel-equality class as R3f.2". **Surprise**:
  real root is a test-side ABI mismatch. `_priv_alice_bn` / `_bob_bn`
  built a 32-byte buffer, but `dtls_ecdhe_keygen_seeded` forwards to
  `p256_keygen_seeded` which expects a bn256 limb list. Passing bytes
  segfaulted deep in `p256_scalar_mult`. Fix mirrors `test_dtls12`:
  build the scalar via `bn256_from_hex`. Gets past `_setup_ready_pair`
  but a second unrelated crash remains at `test_extract_keys_null`
  (see §Follow-up / R3g).
- **R3f.4 `test_ingest_file_multimodal` (SEGV).** The test called a
  non-existent helper `rpc_ctx_set_presented_holder` (dispatch to null
  callee). In the shared path, `perceptual_capsule.nova` wrote raw
  list-indexed bytes with `store8(buf+i, byte_list[i])`; `byte_list[i]`
  returns tagged small-ints whose high tag bits corrupt the stored byte
  and cause OOB writes (ret-to-stack err 15 reproduced). Fix: mask with
  `int_and(x, 255)`; re-mint the test's presented holder via
  `capability_registry` + `rpc_ctx_set_presented_token`.

## Decision

Per-sub-pass workarounds, one commit:

- **R3f.1** -- `src/federation/distributed_rules.nova`: migrate
  `io_println` to `println` + chunk-split <=128 B in `drule_chat_add_cmd`
  and `drule_chat_run_cmd`.
- **R3f.2** -- `src/safety/differential_privacy.nova`: replace the
  `v == DP_REFUSED` equality in `dp_is_refused` with a magnitude probe
  `v < 0 - 2000000000`.
- **R3f.3** -- `tests/unit/test_gossip_dtls_shim.nova`: rebuild the two
  bn256 scalar helpers via `bn256_from_hex` (test-side only; no module
  change).
- **R3f.4** -- `src/ingest/perceptual_capsule.nova`: tag-strip
  `byte_list[i]` with `int_and(x, 255)` in both `perc_hash_from_bytes`
  and `perc_hash_full_from_bytes`.
  `tests/unit/test_ingest_file_multimodal.nova`: rewire
  `test_ownership_stamping_on_image` through `capability_registry` +
  `rpc_ctx_set_presented_token`.
- **R3f.5** -- `src/util/gen_id.nova` (new): monotonic counter +
  `gen_id_new`/`stamp`/`matches`. Append `REN_GEN`/`DL_GEN`/`GE_GEN`
  slots to `renv_new`, `dl_new`, `goal_engine_new` (tail-append).
  Rewire the DEAD guards at `perception_module.nova:304` and
  `action_module.nova:337,343` to compare on the stamped int.
- **R3f.6** -- `docs/UPSTREAM_NOVA_BUGS.md` (new): seed manifest of six
  upstream items (five NOVA bugs + the container sandbox O_CREAT
  policy) consolidating ADR-0101 through ADR-0105 so the upstream fix
  recipe is in one place.

## Consequences

Per-test tally against the dirty + R3f.5 tree:

- **R3f.1** `test_distributed_rules`: SEGV -> OK (42 checks).
- **R3f.2** `test_federated_aggregator`: SEGV before any output ->
  SEGV before any output (no change). The DP equality fix is correct
  for its own bug class, but the module-init path crashes elsewhere.
  **Partial-defer to R3g.**
- **R3f.3** `test_gossip_dtls_shim`: SEGV in `_setup_ready_pair` ->
  SEGV past `test_extract_keys_null` (crashes test 26 of 31 after a
  clean "FAIL: client hs last_err" diagnostic). The ABI fix moves the
  crash boundary forward 25 tests. **Partial-defer the tail to R3g.**
- **R3f.4** `test_ingest_file_multimodal`: SEGV -> OK (28 checks).
- **R3f.5** `test_perception_module`: OK (45 checks) -> OK (45 checks).
  `test_action_module`: 53 passed / 2 FAIL (pre-existing, per R3e
  commit message) -> 53 passed / 2 FAIL (unchanged).

Regression canaries (`test_fed_daemon_replication`,
`test_kg_query`/`_agg`/`_ext`, `test_arithmetic`): all still OK. Known
non-SEGV neighbors (`test_merkle`, `test_merkle_signing`): status
unchanged (SEGV/3-FAIL present on R3e tip; not in R3f's scope).

## Follow-up

**R3g queue** (two tests, both honest-defer from R3f):

1. `test_federated_aggregator` -- SEGV earlier than R3f.2's call site;
   needs instrumentation inside `fed_agg_emit_noised_stats`'s callees
   (likely a second sentinel-equality or tag-strip site in
   `fed_aggregator.nova` or its boot path).
2. `test_gossip_dtls_shim` -- SEGV at `test_extract_keys_null` (test
   26/31). Likely a separate class entirely (null-state probe on an
   uninitialized dtls state); not sentinel-equality.

**Upstream NOVA** (see `docs/UPSTREAM_NOVA_BUGS.md`):

- bug-#11 sentinel equality on tagged pointers (R3f.2 workaround).
- `io_println` tagged-literal walker + concat-node handling (R3f.1
  workaround).
- (Carried: memcpy_raw codegen, `rt_str_to_int` load8 on tagged
  string, type_of regression, sandbox O_CREAT policy.)

Closing all six upstream items retires
`src/util/{str_safe,mem_safe,type_safe,gen_id}.nova` and the R3b-R3f
call-site migrations in a single sweep. Operator action.
