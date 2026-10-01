# ADR-0101: `str_eq` → `str_eq_bytes` migration (R3b)

## Status

Accepted. Shipped by Phase Q R3b. Co-numbered with
`0101-data-acquisition-pipeline.md` (per the two-ADR-0100 precedent set
by `0100-moment-signal-cognition.md` + `0100-nova-bootstrap-setarch-
workaround.md`).

## Context

Phase Q R3a (`docs/SEGFAULT_TRIAGE_R3A.md`, commit `6b746e7`) diagnosed
a cluster of ~22-26 SIGSEGV unit-test crashes as all tracing to the
same NOVA runtime quirk: the `str_eq` builtin is empirically unreliable
on short literal strings. Short-literal `str_eq("op", "op")` can return
0 (byte-identical strings compared unequal) — documented in
`src/util/str_safe.nova:3-14`:

> two byte-identical strings can compare unequal. Empirically confirmed
> 2026-08: `str_eq("op", "op")` returns 0 (FALSE); same for "num",
> "CONST", "INVALID", and other short literal pairs. … 1465 str_eq
> call sites exist across src/; the migration is incremental.

The crash chain, confirmed by dmesg decode of
`test_atom_birth_monitor` and four other representative failures (R3a
§3): a `_find` / `_lookup` helper's `str_eq` falsely reports
non-match → helper returns the "not-found" sentinel 0 → caller uses
that 0 as a list → NOVA list indexing dereferences the tagged-int-zero
bit-pattern `1` → SIGSEGV at virtual address `1` (or at an odd address
for a non-zero tagged int). The already-shipped mitigation,
`src/util/str_safe.nova::str_eq_bytes`, is a length-check +
`char_at`-based byte-wise comparator that is unaffected by the
builtin's flakiness.

## Decision

Mechanically migrate vulnerable `str_eq` call sites to `str_eq_bytes`
across the import graph of the 26 class-A segfaulting tests. "Vulnerable"
means either operand is a short literal, or the call lives in a
`_find`/`_lookup` / dispatch helper where a short literal is plausible.
No runtime, grammar, or codegen changes; the migration is call-site-only.

33 files migrated, 367 call sites rewritten. Full module list in the
Phase Q R3b roadmap entry. Four sites are explicitly left on raw
`str_eq` because they compare long dynamic strings (not the vulnerable
pattern per `str_safe.nova:3-14`):

- `src/learning/internet_fetch.nova:74` — URL cache lookup (full URL).
- `src/federation/snapshot_replication.nova:339,349,488` — ROOT_HEX
  (SHA-256 hex, 64 chars) compares.

Every migrated file imports `src/util/str_safe.nova` (relative path per
the file's own `use`/`import` style; `../util/str_safe.nova`,
`../../util/str_safe.nova`, etc.). `src/learning/secure_aggregation.
nova` has an internal wrapper `_sa_str_eq`; its body was rewired to
call `str_eq_bytes` rather than migrate every caller.

One ancillary bug surfaced and was fixed in the same round
(`src/io/transducers/http_client.nova:_hc_str_lower`): the function
returned a raw `alloc`'d NUL-terminated byte buffer, which the original
`str_eq` builtin (strcmp) accepted but `str_eq_bytes` (which uses
`len` + `char_at`) cannot. Replaced with a one-line delegate to NOVA's
`str_lower` builtin, matching the pattern in
`src/chat/helpers.nova:417`.

## Consequences

Measured against the 26 class-A SEGV tests enumerated in R3a §2 (one
cell per test; `./scripts/test.sh` isolation, per the roadmap
`setarch -R` NOVA):

Flipped SEGV → PASS (6):
`test_atom_birth_monitor`, `test_competence_tracker`,
`test_entity_resolve`, `test_gossip_noise`, `test_kg_sync`,
`test_kg_sync_delta`.

Flipped SEGV → clean non-crash FAIL (5): `test_episodic`,
`test_fed_daemon_attest`, `test_gossip`, `test_gossip_relay`,
`test_internet_fetch`. The test harness now has real signal on these
instead of a 139 that hides the underlying logic bug.

Still SEGV after R3b (15): `test_audio_wakeword`,
`test_chat_state_persistence`, `test_decision_log_durable`,
`test_distributed_rules`, `test_fed_daemon_boot`,
`test_fed_daemon_replication`, `test_fed_daemon_transport`,
`test_federated_aggregator`, `test_gossip_dtls_shim`,
`test_http_client`, `test_ingest_file_multimodal`, `test_kg_query`,
`test_kg_query_agg`, `test_kg_query_ext`, `test_kg_rss_ingest`.

The residual SEGVs are **not** `str_eq` crashes — spot-checked and
confirmed for `test_kg_query` (dies inside `_qry_parse_limit` for the
input `"SELECT ... LIMIT 3"` with no str_eq on the fault path),
`test_http_client` (dies inside `_hc_chunked_decode`, which uses an
`alloc`'d byte buffer the way `_hc_str_lower` did), and
`test_federated_aggregator` (dies after `test_fed_agg_join_leave_flags`,
inside the DP/meta-observer path, no str_eq on the fault path). R3a's
clustering overcounted: not every ~26 segfaults share the str_eq root
cause the way the dmesg sample suggested. These residuals need a
separate round and are tracked below.

Side-benefit: three non-SEGV tests saw their fail counts drop as a
consequence of migrating their deps (`src/persistence/merkle.nova`,
`src/learning/byzantine_aggregation.nova`,
`src/federation/leader_election.nova`):

- `test_merkle`: 48/12 → 57/3 fail.
- `test_byzantine_aggregation`: 55/15 → 68/2 fail.
- `test_leader_election`: 26/14 → 31/9 fail.

No regressions on spot-checked non-SEGV tests (`test_arithmetic`,
`test_perception_module`, `test_episodic_retrieval`, `test_identity`,
`test_atom_birth_monitor`).

## Follow-up

- **R3c (SIMD / pointer-arithmetic cluster, still open)**: three tests
  R3a Class B (`test_lk_u8_simd`, `test_lk_mulacc_simd`,
  `test_image_ocr`) still SEGV. Separate bug class, out of R3b scope.
- **R3d (residual non-str_eq SEGVs, newly surfaced)**: the 15 class-A
  tests above hit a different SIGSEGV path. Need per-test triage. Early
  patterns suggest `alloc`'d byte-buffer sites that NOVA `len` /
  `char_at` cannot consume (as fixed inline for `_hc_str_lower`); may
  need a sweep of `fn.*{ let buf = alloc.*return buf }` across src/.
- The ~124 raw `str_eq` sites still outside this migration (image /
  video / audio / stream transducers, dp_budget_ui, sensor_fusion,
  cognitive_router, …) are not in the import graph of any of the 26
  class-A tests. Fold them into a later low-priority round rather than
  grow R3b's commit.
