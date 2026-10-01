# ADR-0103 — `memcpy_raw` + `rt_str_to_int` tagged-pointer workarounds

Status: Accepted (2026-10-01, Phase Q R3d).
Supersedes: none. Extends: ADR-0102 (R3c class-B SEGV diagnoses).

## Context

R3a catalogued 29 SEGVs. R3b (`b64b382`) migrated six to `str_eq_bytes`
(ADR-0101) and five flipped to clean FAIL. R3c (`0d9248d`) fixed the
LK SIMD pair + `image_ocr` and discovered the underlying NOVA codegen
bug: `memcpy_raw` at `/home/user/NOVA/src/compiler/codegen.nova:22248`
emits a bare `rep movsb` label that does NOT untag `(rdi, rsi, rdx)`.
Since NOVA stores ints and pointers in tagged `2x+1` form, any call
site that reaches `rep movsb` with runtime values faults.

R3d reproduces + classifies the 16 residual SEGVs (the 15 R3b
holdovers + `test_stereo_u8_simd` fallout from R3c). The crash
signatures sort cleanly into five clusters.

## Diagnosis

| Cluster | Signature | Tests (count) | Root path |
|---|---|---|---|
| A — direct `memcpy_raw` | `fc f3 a4` at user call | `test_stereo_u8_simd` (1) | `image_stereo.nova:406` passes tagged ptrs to `memcpy_raw` |
| B — `substr(raw_alloc, 0, n)` | `f3 a4` inside `_nova_substr` | `test_http_client`, `test_kg_rss_ingest` (2) | runtime `substr(buf, …)` reaches the same codepath |
| C — `rt_str_to_int(substr(…))` | `48 8a 07` at `rt_str_to_int:load8` | `test_kg_query`, `test_kg_query_agg`, `test_kg_query_ext`, `test_fed_daemon_boot` (4) | runtime `rt_str_to_int` iterates with `load8(s + i)` which does not untag string handles returned by `substr(tagged_string, …)` |
| D — type-probe tagged-0 | `48 83 3f ff` on `_nova_index`/`_nova_len` | `test_audio_wakeword`, `test_chat_state_persistence`, `test_decision_log_durable`, `test_distributed_rules`, `test_fed_daemon_replication`, `test_federated_aggregator`, `test_gossip_dtls_shim` (7) | downstream of a `save`/`open`/`serve` returning 0; the test then indexes a null; roots differ per test |
| E — stack corruption | ret-to-stack | `test_ingest_file_multimodal` (1) | out of scope; needs standalone bisect |

Instrumentation (stripped before commit) narrowed Cluster C to the
runtime helper `rt_str_to_int` in `src/runtime/string.nova:226`,
which iterates with `load8(s + i)` directly. The builtin `str_to_int`
walks via `char_at` and is unaffected; swapping the call site is the
smallest safe workaround. The plan hypothesis (`str_concat` on `+`
with `_tok_text`) was wrong — strings themselves work with `+`; it is
`load8` on a `substr`-returned handle that faults.

A separate R3d finding (not a SEGV, so not fixed here): the runtime
`type_of` on strings and lists both return `1`, not the historical
`2`/`3` the kg/query guards assume. This causes a batch of
"expected=1 got=0" FAILs on error-path tests, but these FAILs are
behavioural and exit 3, not SEGV. Rolled to R3e; see Follow-up.

## Decision

New module `src/util/mem_safe.nova` with two helpers:

- `byte_copy(dst, src, n)` — scalar `store8(load8)` loop; replaces
  `memcpy_raw(dst, src, n)` at user call sites. `load8`/`store8` DO
  untag their args (confirmed by R3c disasm), so the loop is correct
  on tagged inputs. Verbatim extraction of R3c's `_lk_byte_copy`.
- `buf_to_str(buf, n)` — walks a raw alloc'd buffer byte-by-byte via
  `load8 + chr` and appends each byte to an `""`-seeded string.
  Replaces `substr(raw_alloc_buf, 0, n)` where the buffer came from
  `alloc(…)` + `store8` (not a tagged string).

Per-cluster application:

- **Cluster A**: `image_stereo.nova:406` → `byte_copy(…)`.
- **Cluster B**: `http_client.nova:770`, `kg_rss_ingest.nova:373` →
  `buf_to_str(buf, n)` (both `buf` are from `alloc(cap+1)` locally).
- **Cluster C**: migrate every `rt_str_to_int(…)` call site that is
  fed by `substr(tagged_string, …)` to the `str_to_int` builtin.
  Covers `src/kg/query.nova` (9 sites: 2 token-value sites +
  7 object-term sites), `examples/crossengin_fed_daemon.nova` (2),
  `tests/unit/test_fed_daemon_boot.nova` (1), plus speculative
  pre-emptive migration of `src/kg/{episodic,temporal,rule_inference,
  link_prediction,semantic_search}.nova` (same pattern, caught by
  grep but not individually test-pinned).
- **Regression canary**: rewire `image_optical_flow.nova` to use
  the new shared `byte_copy` and drop its module-local
  `_lk_byte_copy` body. The R3c SIMD canaries
  (`test_lk_u8_simd`, `test_lk_mulacc_simd`, `test_image_ocr`) must
  still pass.

## Consequences

Verified exit codes after R3d (`cd /home/user/Crossengin-demo &&
setarch -R /home/user/NOVA/nova run tests/unit/<name>.nova`):

- **Cluster A — 1/1 flipped PASS**: `test_stereo_u8_simd` (25 checks).
- **R3c regression canaries — 3/3 still PASS**: `test_lk_u8_simd`
  (34), `test_lk_mulacc_simd` (28), `test_image_ocr` (40).
- **Cluster B — 2/2 flipped PASS**: `test_http_client` (103),
  `test_kg_rss_ingest` (51).
- **Cluster C — 4/4 flipped non-SEGV**: `test_fed_daemon_boot` PASS
  (49 checks); `test_kg_query`, `test_kg_query_agg`,
  `test_kg_query_ext` exit 3 with clean behavioural FAILs on
  `type_of` regression (see Follow-up), SEGV gone.
- **Cluster D — 0/7 flipped**: all seven still SEGV on indexing a
  null returned by an unrelated save/serve. Investigation shows the
  SEGV is downstream of a module-internal failure that is NOT a
  tagged-pointer bug (sr/dq modules + fed daemon transport); the
  Cluster-C-induced blast-radius hypothesis in the plan was wrong.
  Rolled to R3e.
- **Non-SEGV neighbours**: `test_perception_module`, `test_arithmetic`
  still PASS. `test_action_module` carries the same two pre-R3d FAILs
  (verified against `0d9248d` tip).

Net: 7 of 15 R3b residual SEGVs resolved (Clusters A+B+C), plus
`test_stereo_u8_simd` (R3c fallout) closed.

## Follow-up (R3e queue)

- `test_ingest_file_multimodal` (Cluster E — stack corruption).
- `test_fed_daemon_transport` reclassified (exit 3, behavioural).
- 7 Cluster D tests (`save`/`serve` returns 0 → test indexes null).
  Per-test module diagnosis needed; the save/serve surface uses the
  flaky `str_eq` and the `type_of` regression; neither is purely a
  tagged-pointer workaround target.
- `type_of` runtime regression: strings AND lists both read `1` now
  (historical: `str=2`, `list=3`). Caller code in `src/kg/query.nova`
  (`_qry_is_error`), `src/data/table.nova`, and anywhere else that
  compares `type_of(x)` to `3`/`4` is silently wrong. Not fixed in
  R3d; needs an audit + either runtime restoration or caller
  migration.
- **Upstream NOVA** (operator action): fix `memcpy_raw` codegen
  (`sar rdi,1; sar rsi,1; sar rdx,1` before `rep movsb`); fix
  `rt_str_to_int` to use `char_at` or add the SAR there too. Closes
  the whole R3c/R3d workaround family and lets us revert
  `mem_safe.nova` + the `str_to_int` migration.
