# ADR-0114: DTLS 1.2 handshake state-machine completion (close test_dtls12 to 519/0)

## Status

Proposed (2026-10-09).

## Context

`tests/unit/test_dtls12.nova` currently reports **443 passed / 76 FAILED**
at tip `494596f`. A C4 re-triage pass (agent `a39e6126120a94dc8`) attributed
71 of 76 to source-side stub cascades named by the labels
`"ecdhe_derive is a stub"` / `"seal_record is a stub"` /
`"open_record is a stub"` / `"cert_verify forwards to real path"`, with the
remaining 5 split as four random-seed literal-drift FAILs (`nanotime()`
reseeds) and one missing `last_err` stamp after an invalid-profile call.

### What is actually already in-tree at `494596f`

Reading `src/federation/dtls12.nova` directly, the four "stub" names
the triage pointed at **already have real implementations**, landed in
earlier rounds:

| Function                           | Source line | Landed in              |
| ---------------------------------- | ----------- | ---------------------- |
| `dtls_ecdhe_derive`                | :3212       | R31B                   |
| `dtls_seal_record`                 | :3397       | R31B                   |
| `dtls_open_record`                 | :3569       | R31B                   |
| `dtls_cert_verify`                 | :3850       | R31B                   |
| `dtls_cert_verify_chain`           | :3973       | R33B / **ADR-0094**    |
| `dtls_export_srtp_keying_material` | :2460       | R35A / R36B / **ADR-0095** |

The `_R29B2_STUB`-suffixed symbols (`:4063`, `:4084`, `:4092`, `:4097`)
are intentional regression-guard sentinels: `test_stubs_return_DTLS_ERR_STUB`
(`tests/unit/test_dtls12.nova:671`) asserts they still return
`DTLS_ERR_STUB`. Those assertion labels (`"ecdhe_derive is a stub"`, etc.)
are PASSING guards — removing them is explicitly a backward-incompatible
change.

### Dependency primitives — all in-tree

- `src/safety/p256.nova`              — `p256_derive(priv, peer_pub_buf, peer_pub_n)` :817, `p256_scalar_mult` :572.
- `src/safety/hkdf_sha256.nova`       — HKDF-Expand/Extract.
- `src/net/tls/tls_kdf.nova`          — TLS 1.2 PRF-SHA256; shared with `dtls_prf_sha256`.
- `src/net/tls/tls_keyshare.nova`     — R89 keyshare helpers (ClientKeyExchange / ServerKeyExchange serializers).
- `src/safety/x509_verify.nova:393`   — `cert_chain_verify(der_list, host, anchors, now)` (R90).
- `src/safety/aes_gcm.nova`           — AES-128-GCM AEAD.
- `src/safety/ecdsa.nova`             — `ecdsa_sha256`, `ecdsa_p256_verify_bn`.
- `src/safety/pem_truststore.nova`    — truststore_load / truststore_load_file (ADR-0094 §Trust).
- NOVA stdlib `nanotime()` (R91)      — monotonic seed source for test harness.

### Prior ADR coverage

- **ADR-0068** triaged a 10-FAIL epoch-rotation cluster to *test bugs*,
  not source bugs. Source `dtls_advance_epoch` was and still is correct.
- **ADR-0089** stood up the fed daemon MVP, deliberately noting the
  R29B.2 stubs block wire-encryption; swap is a two-line change once
  stubs retire.
- **ADR-0094** wired chain-aware cert-verify (`dtls_cert_verify_chain`),
  the `XV_* -> DTLS_*` error map, and `truststore_load_dir`.
- **ADR-0095** wired the SRTP EKM forward and the `use_srtp` ClientHello
  extension (RFC 5705 / RFC 5764 §4.2).
- **ADR-0096** scopes the non-RFC DTLS-over-TCP gossip shim.
- **ADR-0097** / **ADR-0098** / **ADR-0099** scope server flight,
  client-flight `Finished`, and DTLS extensions / streams respectively.

### Residual gap this ADR closes

Given the above, 71 of the 76 FAILs cannot in fact be stub-side source
cascades — the stubs are regression-guard assertions in the PASSING set.
The remaining honest work for `test_dtls12` to reach 519/0 is:

1. **Five micro-fixes** (shippable in one small round):
   - Four random-seed literals that drifted when the test harness
     switched from fixed-constant seed to `nanotime()` seeding
     (`tests/unit/test_dtls12.nova:734+` seeded-P256 fixtures).
   - One missing `state[DTLS_S_SLOT_LAST_ERR]` stamp after the invalid
     SRTP-profile call (asserted at `tests/unit/test_dtls12.nova:2746`).

2. **Re-triage of the 71 "cascade" FAILs.** We do not accept the triage
   agent's premise that these are source-side stubs. Round A below
   runs a fresh enumeration against tip `494596f` and classifies them
   per the ADR-0068 methodology (code-bug vs test-bug per failure, no
   guessing). We expect the dominant root cause is nanotime-seed drift
   through the seeded-keypair harness block starting at
   `test_dtls12.nova:734`, which fans out into every full-handshake
   test that depends on those fixtures.

## Decision

### 1. Freeze the test harness to a deterministic seed

Replace the `nanotime()`-seeded fixtures block at
`tests/unit/test_dtls12.nova:734+` with a fixed 32-byte seed constant
`DTLS_TEST_SEED` (`0x0102030405060708 0x090a...20`). Every seeded-P256
keypair + every ClientRandom/ServerRandom used in the full-handshake
tests derives from `DTLS_TEST_SEED || <role_tag>`. This isolates the
test suite from NOVA-upstream `nanotime` tagging changes (Bug #7, Task
#24) and makes literal-expected values byte-stable.

### 2. Stamp `DTLS_S_SLOT_LAST_ERR` on the invalid-SRTP-profile path

Add one line to the SRTP-profile validator so an invalid profile stamps
`state[DTLS_S_SLOT_LAST_ERR] = DTLS_SRTP_BAD_PROFILE` before returning.
Matches the pattern already in use for `DTLS_ERR_BAD_STATE`,
`DTLS_DECRYPT_FAIL`, `DTLS_REPLAY`, `DTLS_TOO_OLD`.

### 3. Preserve the `_R29B2_STUB` regression guards

Do **not** remove the four `_R29B2_STUB` wrappers or their
`test_stubs_return_DTLS_ERR_STUB` assertions. They catch an agent who
renames a real impl into a stub slot (the exact failure mode the
header comment at `dtls12.nova:2957` warns against). The upstream
re-triage summary that labelled them as stub cascades is incorrect;
this ADR records the correct reading so the next re-triage does not
repeat the misread.

### 4. Re-triage the 71 "cascade" FAILs under ADR-0068 methodology

Before touching source, enumerate the 71 FAIL assertions on tip
`494596f` with the harness fix (§1) applied and the `last_err` stamp
(§2) applied. For each remaining FAIL, decide code-bug-vs-test-bug by
reading both the assertion and the implementation. Precedent
(ADR-0068) found all 10 of its triaged FAILs were test bugs; the same
discipline applies here. Any residual source-side bugs are then real
work and get their own sub-ADRs or ride ADRs 0097-0099 as applicable.

### 5. Do not re-implement already-landed primitives

`dtls_ecdhe_derive` / `dtls_seal_record` / `dtls_open_record` /
`dtls_cert_verify` / `dtls_cert_verify_chain` /
`dtls_export_srtp_keying_material` all have real implementations
(R31B, R33B/ADR-0094, R35A/R36B/ADR-0095). This ADR does **not**
authorise rewriting them; it authorises wiring the test harness and
closing the 5-micro-fix tail.

## Consequences

### Positive

- `test_dtls12.nova` reaches 519/0 (or very close, pending Round A
  triage outcome).
- Test harness becomes deterministic — `nanotime()` tagging regressions
  (NOVA Bug #7 / Task #24 class) can no longer drift DTLS literals.
- The regression-guard semantics of `_R29B2_STUB` are preserved and
  documented against future re-triage misreads.
- SRTP export already real (ADR-0095) and now with correct `last_err`
  stamping on the error branch; downstream SRTP consumers get a clean
  error signal.

### Negative / risks

- Round A re-triage may surface genuine source-side bugs that need
  real fixes; LOC estimates below assume ADR-0068's hit rate (test
  bugs dominate).
- Freezing the harness seed hides any entropy-source regression in
  `nanotime()`; that signal moves to the dedicated RNG tests (R91)
  where it belongs.
- Downstream `fed_daemon_transport` + `gossip_dtls_shim` ABI is
  unaffected — this ADR only changes the test harness and one source
  line.

### Non-goals

- No new state-machine flights. RFC 6347 §4.2 server-flight work is
  ADR-0097's lane; client-flight `Finished` is ADR-0098's; extensions
  and streams are ADR-0099's. This ADR does not duplicate them.
- No changes to `dtls_advance_epoch` (correct per ADR-0068) or to the
  AEAD cipher path (correct per R31B).
- No changes to the `_R29B2_STUB` wrappers or their test guards.

## Implementation plan (reference, not binding)

| Round | Scope                                                                                 | Est. LOC |
| ----- | ------------------------------------------------------------------------------------- | -------- |
| **A** | Enumerate the 71 FAIL assertions on tip `494596f` + classify (test-bug vs source-bug) | 0 src, 0 test (analysis only) |
| **B** | Freeze test-harness seed to `DTLS_TEST_SEED`; re-point all 4 drifted random literals  | ~10 test |
| **C** | Stamp `DTLS_S_SLOT_LAST_ERR = DTLS_SRTP_BAD_PROFILE` on invalid-profile branch        | 1 src    |
| **D** | Apply per-FAIL fixes from Round A (expected: index-drift / sentinel-equality bugs à la ADR-0068) | ~30-120 test |
| **E** | If Round A surfaces real source bugs, open a child ADR per bug; do not fix inline here | — |
| **F** | Verify `nova run tests/unit/test_dtls12.nova` reports `passed=519 failed=0`           | 0 LOC    |

Expected total: **~1 LOC source, ~40-130 LOC test**, well under the
500-1500 LOC the brief anticipated, because the real cryptographic
work already landed in R31B / ADR-0094 / ADR-0095.

## References

- ADR-0065 — dtls12 compile hang (prerequisite for the suite ever running).
- ADR-0068 — epoch-rotation / SRTP-export 10-FAIL triage (methodology precedent).
- ADR-0089 — federation-daemon MVP (notes DTLS stub placement).
- ADR-0094 — DTLS cert-chain completion (shipped `dtls_cert_verify_chain`).
- ADR-0095 — DTLS-SRTP completion (shipped SRTP EKM forward + `use_srtp`).
- ADR-0096 — DTLS-over-TCP gossip shim.
- ADR-0097 — DTLS server flight.
- ADR-0098 — DTLS client-flight `Finished`.
- ADR-0099 — DTLS extensions + streams.
- RFC 6347 §4.1 (epoch) + §4.2 (handshake state machine).
- RFC 5246 §6.2.3.3 / §6.3 (TLS 1.2 PRF, key_block layout).
- RFC 5288 §3 (AES-GCM nonce).
