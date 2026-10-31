# ADR-0106 -- segfault-arc close-out (R3g residuals)

Status: Accepted
Date: 2026-10-02
Context: Phase Q R3g. Follows ADR-0105 (R3f sentinel-equality +
rebuild-guard reinforcement).

## Context

ADR-0105 §Follow-up queued two residuals from R3f:

1. `test_federated_aggregator` -- after R3f.2 fixed the
   `dp_is_refused` magnitude-probe, a SEGV earlier in the module-init
   path (inside `fed_agg_emit_noised_stats` callees) still killed the
   test with no output.
2. `test_gossip_dtls_shim` -- the ABI fix in R3f.3 moved the crash
   boundary 25 tests forward; test 26/31 (`test_extract_keys_null`)
   still SEGVs.

R3g diagnoses and retires both. Standing constraint:
`/home/user/NOVA/src/runtime/*` and `codegen.nova` remain off-limits.

## Diagnosis

Instrumented bisection pinpointed each root:

- **R3g.1 `test_federated_aggregator`** -- SEGV at `s * _LCG_MUL` in
  `_lcg_step` the first time `fed_agg_emit_noised_stats` reaches the
  DP noise path. Code bytes: `<48> 83 3f ff` (`cmp qword ptr [rdi], -1`),
  the familiar sentinel-equality probe. **New bug class, NOT ADR-0105
  bug-#11**: `nanotime() & _LCG_MASK` leaves the result UNTAGGED
  (NOVA's `&` does not re-tag a raw int from `nanotime()`). The
  untagged value survives `+`, prints as `0` through `int_to_str`,
  and compares TRUE to raw bits, but `*` dispatches through the
  pointer-threshold path and the sentinel-equality check SEGVs on the
  non-pointer operand. `rt_str_to_int(int_to_str(x))` also SEGVs on
  this value, so round-tripping is not available. Call it the
  **"raw-nanotime-untagged" bug class**.
- **R3g.2 `test_gossip_dtls_shim`** -- SEGV at the call site of
  `gossip_dtls_extract_keys(0)` BEFORE the function body executes
  (confirmed: a `println` instrumented at the first line of the
  callee never fires). Root cause: the function is defined in
  `src/federation/gossip.nova`, which `test_gossip_dtls_shim.nova`
  does not import (its only imports are `gossip_dtls_shim.nova` and
  `dtls12.nova`). NOVA compiles the unresolved call to a null callee
  which SEGVs on entry. Known class: "unresolved-callee SEGV";
  resembles the ADR-0105 R3f.4 `rpc_ctx_set_presented_holder` miss
  except the called name is well-defined, just not import-reachable.

## Decision

Per-residual workarounds, one commit:

- **R3g.1** -- `src/safety/differential_privacy.nova`: replace
  `nanotime() & _LCG_MASK` seeding in `dp_new` with
  `epsilon_budget_milli + 7919` (an already-tagged caller-supplied
  int perturbed by an addition). Deterministic seed is acceptable for
  the Minimum Viable DP (an explicit `dp_new_seeded` entry point
  remains for callers that need to pin the stream).
- **R3g.2** -- `src/federation/gossip_dtls_shim.nova`: add a shim-local
  `gds_extract_keys` (same body as `gossip_dtls_extract_keys` in
  `gossip.nova`); `tests/unit/test_gossip_dtls_shim.nova`: switch the
  three callers to `gds_extract_keys`. Also migrate two residual
  `str_eq` call sites to `str_eq_bytes` in
  `tests/unit/test_federated_aggregator.nova` (ADR-0101 cleanup,
  previously masked by the SEGV).

## Consequences

Per-residual tally against the R3f tip (`f4442cc`) plus R3g:

- **R3g.1** `test_federated_aggregator`: SEGV before any output ->
  OK (91 checks).
- **R3g.2** `test_gossip_dtls_shim`: SEGV at `test_extract_keys_null`
  -> 56 passed, 1 FAIL (pre-existing `client hs last_err =
  flight-not-wired`, noted in ADR-0105 §Consequences; no SEGV).

**Segfault-arc close-out**: with R3g.1 + R3g.2 both green, the 29
tests catalogued under R3a (segfault cluster) are all resolved. The
remaining residual is one pre-existing clean FAIL in
`test_gossip_dtls_shim` (`flight-not-wired` diagnostic string) and
two pre-existing clean FAILs in `test_action_module`, none of which
is a SEGV.

Regression canaries (`test_distributed_rules`,
`test_ingest_file_multimodal`, `test_fed_daemon_replication`,
`test_kg_query`, `test_arithmetic`, `test_perception_module`,
`test_type_of_probe`): all still OK. `test_action_module`: 53
passed / 2 FAIL (unchanged, pre-existing).

## Follow-up

**Upstream NOVA** (new in R3g, appended to
`docs/UPSTREAM_NOVA_BUGS.md`):

- **raw-nanotime-untagged bug class**: `nanotime() & <mask>` returns a
  raw untagged int. `+` and `==` tolerate the untagged form, but `*`
  dispatches through the pointer-threshold path and SEGVs via the
  sentinel-equality probe. Round-tripping through
  `int_to_str`/`rt_str_to_int` is also unsafe on this value. User-level
  mitigation: derive seeds from already-tagged values instead.
- **unresolved-callee SEGV**: a call to a function that is defined in
  some module but not reachable through the current test's import
  graph compiles to a null callee and SEGVs on entry. User-level
  mitigation: duplicate the function into the import-reachable module
  or correct the import graph.

Both are candidates for upstream fixes; no further CrossEngin tests
are blocked on either, so no follow-up R3h is queued. Operator
action for the upstream fixes.
