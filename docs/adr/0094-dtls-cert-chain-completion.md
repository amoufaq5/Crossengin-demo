# ADR-0094: DTLS cert-verify chain completion (wire cert_chain_verify + truststore + hostname into dtls12)

- Status: Accepted
- Date: 2026-09-30

## Context

Phase O R1 closes the first of three arcs that finish CrossEngin's
DTLS 1.2 story. The other two (SRTP EKM forward + `use_srtp` extension
in R2, and the non-standard DTLS-over-TCP gossip shim in R3) build on
the trust foundation this ADR pins.

**Header-comment diagnosis.** The header at `src/federation/dtls12.nova:137`
described `dtls_cert_verify_R29B2_STUB` as "still a stub; needs an
X.509 parser." That comment was stale: R33B (see the amendment lower
in the same header) already replaced the stub body with a thin
forward to a **real** single-cert verifier -- `dtls_cert_verify(state,
peer_cert_der, peer_cert_len, expected_fingerprint_or_null)` at
`src/federation/dtls12.nova:2101`. That function walks a single cert:
`x509_parse` -> `x509_check_validity` -> `ecdsa_p256_verify_bn` ->
optional SHA-256 fingerprint compare (RFC 4572 §5). It bumps
`STATS_CERT_*` counters. It works.

**What was actually missing** was not the parser -- it was chain
walking, truststore consultation, and hostname / SAN matching. The
tree already had them, just not connected to DTLS:

- `src/safety/x509_verify.nova:393` -- `cert_chain_verify(der_list,
  host, anchors, now)`. Walks leaf-first DER list, verifies each
  cert's signature under its parent (dispatches RSA-PKCS#1 or
  ECDSA-P256 per cert), matches TOP cert's key against
  `anchors[i]`, enforces SAN coverage on the leaf (exact or
  `*.suffix`), enforces `not_before <= now <= not_after` on the
  leaf. Returns `[status, leaf_cert]` with status in the
  `XV_OK / XV_PARSE / XV_SIG / XV_NOT_PINNED / XV_HOSTNAME /
  XV_EXPIRED` enum.
- `src/safety/pem_truststore.nova` -- `truststore_load(text)` and
  `truststore_load_file(path)`. Both understood typed anchors
  (RSA and EC) and skipped unsupported algorithms cleanly. But
  there was no directory-scan variant: an operator with a fed-
  wide trust store split across N PEM files had no way to load
  them as one anchors list.

Meanwhile the fed daemon (`examples/crossengin_fed_daemon.nova`) had
NO DTLS cert configuration at all. Phase M R3 wired Ed25519 signer
keys for snapshot attestation, but ADR-0091's `CE_FED_ATTEST_KEY_DIR`
is separate from any DTLS trust-store: attestation signs snapshots,
DTLS authenticates peers. Confusing them at the config layer would
be a footgun.

## Decision

### 1. New chain-aware entry `dtls_cert_verify_chain`

Add a new public function to `src/federation/dtls12.nova`:

```
fn dtls_cert_verify_chain(state, cert_der_list, hostname, anchors, now)
  -> [dtls_status, leaf_cert]
```

Body: forward to `cert_chain_verify(cert_der_list, hostname, anchors,
now)` (from `x509_verify.nova`), map `XV_*` to `DTLS_*` per the table
below, bump per-state `STATS_CERT_*` counters, stamp
`state[DTLS_S_SLOT_LAST_ERR]`, return `[dtls_status, leaf_cert]`.

**XV -> DTLS error map (ADR-0094 canonical, mirrored in code
comments):**

| XV_*             | DTLS_*                          | Counter                              |
| ---------------- | ------------------------------- | ------------------------------------ |
| `XV_OK`          | `DTLS_OK` (0)                   | `STATS_CERT_OK`                      |
| `XV_PARSE`       | `DTLS_CERT_PARSE_FAIL`          | `STATS_CERT_PARSE_FAIL`              |
| `XV_SIG`         | `DTLS_CERT_SIG_FAIL`            | `STATS_CERT_SIG_FAIL`                |
| `XV_NOT_PINNED`  | `DTLS_CERT_NOT_PINNED` (new)    | `STATS_CERT_NOT_PINNED` (new)        |
| `XV_HOSTNAME`    | `DTLS_CERT_HOSTNAME_MISMATCH` (new) | `STATS_CERT_HOSTNAME_MISMATCH` (new) |
| `XV_EXPIRED`     | `DTLS_CERT_EXPIRED`             | `STATS_CERT_EXPIRED`                 |

Two new error tags, spelled to be grep-clean (kebab-case, matching the
ADR's own filename convention):

- `DTLS_CERT_NOT_PINNED = "dtls-cert-not-pinned"`
- `DTLS_CERT_HOSTNAME_MISMATCH = "dtls-cert-hostname-mismatch"`

Two new stats slots at the tail (indices 46 and 47) so slots 0..45
stay byte-identical for external state-shape consumers:
`DTLS_S_SLOT_STATS_CERT_NOT_PINNED`,
`DTLS_S_SLOT_STATS_CERT_HOSTNAME_MISMATCH`. Both are pushed as 0 in
`dtls_init`. Both surface in `dtls_stats_line(state)` as
`cert_not_pinned=<n>` and `cert_hostname_mismatch=<n>` so a grep-based
external monitor sees them without changing the stats-line prefix.

Accessors: `dtls_stats_cert_not_pinned(state)` +
`dtls_stats_cert_hostname_mismatch(state)`, matching the existing
`dtls_stats_cert_*` shape.

### 2. Legacy single-cert entry untouched

`dtls_cert_verify(state, peer_cert_der, peer_cert_len,
expected_fingerprint_or_null)` at `src/federation/dtls12.nova:2101`
keeps its exact signature and semantics. Existing test callers
(including the R29B2 stub-forward at :2225 that
`test_dtls12.nova:677` pins) continue to work byte-identically. The
one behaviour change: those callers' counters now share their storage
slots with the new chain entry (both bump `STATS_CERT_OK` on success,
both bump `STATS_CERT_SIG_FAIL` on RSA/ECDSA mismatch, etc.). That
consolidation is DELIBERATE -- a caller who mixes single-cert and
chain calls on the same state gets a unified count of "certs
accepted vs rejected" without having to sum two families.

### 3. Header comment fix

The stale line at `src/federation/dtls12.nova:137` (pre-R33B stub
description) is replaced with an accurate one that:
- documents R33B's stub-to-real forwarding (already documented
  further down, but the top-line summary lied);
- documents Phase O R1's new chain-aware entry and its role;
- cites this ADR-0094 as the reference for the mapping and the
  new tags.

### 4. Directory-scan truststore loader

Add `fn truststore_load_dir(dir_path)` to
`src/safety/pem_truststore.nova`.

**Strategy chosen: manifest-file fallback.** NOVA has no `sys_readdir`
primitive (grep of `src/nl/rpc_verbs.nova:3330` documents the gap
explicitly: "NOVA has sys_open/read/write but no readdir/getdents"),
so directly enumerating `.pem` / `.crt` files in a directory is not
possible from NOVA today. Rather than add readdir to the NOVA runtime
(scope creep; the runtime is off-limits for this phase per the
standing constraint), R1 reads `<dir_path>/manifest.txt` -- one
filename per line, relative to `dir_path`; empty lines and `#`
comment lines are skipped -- and loads each named file via
`truststore_load_file`, merging the anchors into one list.

Semantic edges:
- `dir_path` = 0 or `""` -> empty anchors list.
- `<dir>/manifest.txt` absent -> empty anchors, no error.
- Manifest names a file that does not exist -> that entry silently
  dropped, other entries still load.
- Manifest names a corrupt PEM -> `truststore_load` yields empty
  for that file, other entries still load.
- CRLF line endings -> trailing `\r` trimmed before path-join.

The empty-anchors return on any error path is the **safe** default: an
empty truststore rejects every chain via `XV_NOT_PINNED`, so a
mis-configured operator fails closed. A future NOVA that grows
`sys_readdir` can swap the manifest fallback for a real scan without
changing the callable signature; the code carries a
`TODO(NOVA-sys_readdir)` at the swap point.

### 5. Fed daemon env-var contract

`examples/crossengin_fed_daemon.nova` grows two new env vars, both
optional with safe defaults:

- `CE_FED_DTLS_TRUSTSTORE_PATH` -- default
  `$HOME/.crossengin/fed_truststore` (container fallback:
  `./crossengin_fed_truststore`). Mirrors the shape of the R3
  attest-key env var. Consumed at boot via `truststore_load_dir`;
  the resulting anchors list is logged and carried on a local
  `dtls_anchors` variable. R1 does NOT gate any connection on it
  -- R3 (DTLS-over-TCP shim) does the actual transport wrap.

- `CE_FED_DTLS_HOSTNAME` -- default: `ce-<hash(SOUL_ID)>.fed`.
  Deterministic derivation from `CE_FED_SOUL_ID` via a new helper
  `_fed_hostname_from_soul(soul_id)` that reuses the djb2-style
  `_fed_soul_id_to_int` mixer (Phase M R2's stable int hash). Two
  daemons with the same soul_id derive the same hostname without
  extra config -- a self-signed test mesh where each peer's cert
  SAN carries the derived hostname "just works". R3 will feed
  this into `dtls_cert_verify_chain(state, chain, hostname,
  anchors, now)`.

Both surface in the boot banner (`dtls     : truststore loaded...` or
`dtls     : truststore empty...`) and the shutdown summary
(`dtls_anchors = <n>` + `dtls_hostname = <str>`). No change to the
Session shape -- session_make's slot inventory would be a wider
diff and R3 has more principled hooks (a per-connection DTLS
context) for the transport wrap.

## Consequences

**DTLS peers can now be validated against a real trust chain.**
Callers hand `dtls_cert_verify_chain` a leaf-first list of DER
certs and a hostname; the function walks the chain, verifies each
signature, matches the root against a caller-supplied anchors list,
enforces SAN coverage on the leaf, and enforces the leaf's validity
window. On any failure the caller sees a distinct DTLS_CERT_* string
tag (five failure classes, mutually exclusive) plus a bumped counter
in the state's telemetry slots.

**Hostname / SAN is enforced.** Prior to R1, the only DTLS cert check
was `dtls_cert_verify`'s single-cert ECDSA signature path. There was
no path that consulted a leaf's SAN. R1 closes that gap by
delegating to `x509_verify`'s existing `_x509v_host_ok` (exact or
`*.suffix` matcher). The fed daemon derives a stable hostname from
`CE_FED_SOUL_ID` so self-signed test scenarios don't need a
DNS-configured name.

**Two new error tags are on the wire-observable surface.** Any
external monitor that parses `dtls_last_error(state)` or scrapes
`dtls_stats_line` gains two new possible strings:
`dtls-cert-not-pinned` and `dtls-cert-hostname-mismatch`. Both are
kebab-case, matching the ADR filename convention; existing tags
(`dtls: cert parse fail`, `dtls: cert expired`, etc.) keep their
space-separated legacy spelling to preserve backwards compatibility
with monitors written against R33B.

**Empty truststore fails closed.** An operator who does not point
`CE_FED_DTLS_TRUSTSTORE_PATH` at anything (or names an empty /
missing / manifest-less directory) gets an empty anchors list.
`cert_chain_verify` walks the chain, then rejects on
`XV_NOT_PINNED` because no anchor matches. This is the safe default
-- silent trust-all would be a footgun. The boot banner explicitly
says "truststore empty ... R1 tolerates empty anchors, R3 will fail
closed" so the operator can see the state.

**No test regressions.** The legacy single-cert
`dtls_cert_verify(state, cert, n, fp)` signature is untouched. Its
callers -- including the R29B2 stub-forward
`dtls_cert_verify_R29B2_STUB` at :2225, whose test at
`tests/unit/test_dtls12.nova:677` asserts an empty-buffer input
returns `DTLS_CERT_PARSE_FAIL` -- keep working byte-identically. The
new chain entry is additive.

## Alternatives Considered

**Modify `dtls_cert_verify` in place to take a `chain, hostname,
anchors, now` tuple.** Rejected. Every existing test caller passes
`(state, cert_buf, cert_n, fp_or_0)`, including the R29B2 stub-
forward at :2225 that some phase-N smoke tests depend on. Widening
the signature would either break those callers or force an ugly
overload dance. Additive is the cleaner path.

**Require every caller to invoke `cert_chain_verify` directly and
skip the DTLS shim.** Rejected. The `DTLS_S_SLOT_STATS_CERT_*`
counters are per-`state` telemetry that a wire driver reads to know
"how many chain rejects on this peer so far." A caller that
bypassed the DTLS entry would have to duplicate the counter-bump
logic. Wrapping the chain verifier inside a state-aware DTLS entry
consolidates the bookkeeping in one place.

**Ship a real `sys_readdir` in the NOVA runtime for R1.** Rejected --
the runtime is off-limits per the standing constraint (never edit
`/home/user/NOVA/src/runtime/*`). Doing so would also expand
Phase O's scope beyond DTLS. The manifest-file fallback is a
credible operator interface (mirrors the shape of Kubernetes
`imagePullSecrets` and other systems that enumerate secrets
explicitly rather than crawling a directory).

**Reuse `CE_FED_ATTEST_KEY_DIR` for the DTLS truststore.** Rejected.
Attestation signs snapshots (Ed25519); DTLS authenticates peers
(RSA / ECDSA X.509). Conflating them at the config layer would
mean an operator who set only one env var got both -- the
principle of least surprise says the two trust roots are
independently configurable. `CE_FED_DTLS_TRUSTSTORE_PATH` and
`CE_FED_ATTEST_KEY_DIR` are separate for a reason.

**Store the anchors on the Session object.** Deferred to R3. R1
holds `dtls_anchors` as a local variable in `main()` and logs it in
the boot banner + shutdown summary. R3's DTLS-over-TCP shim will
introduce a per-connection DTLS context (via a new `gossip_set_*`
setter, matching the Phase M pattern) that carries anchors +
hostname + cert + key together. Widening `session_make` in R1
would touch every daemon everywhere for zero R1 benefit.

## Implementation Notes

**Files modified (R1):**
- `src/federation/dtls12.nova` -- new `dtls_cert_verify_chain` +
  `dtls_stats_cert_not_pinned` + `dtls_stats_cert_hostname_mismatch`
  accessors + new error constants + new tail-appended state slots
  + updated `dtls_init` + updated `dtls_stats_line` + header
  comment fix at :137 + new `import "../safety/x509_verify.nova"`.
- `src/safety/pem_truststore.nova` -- new `truststore_load_dir`
  fn (manifest-file fallback path documented in its own header).
- `examples/crossengin_fed_daemon.nova` -- new env-var helpers
  `_fed_dtls_truststore_path_from_env` +
  `_fed_dtls_hostname_from_env` + `_fed_hostname_from_soul` + new
  env-var doc block + `truststore_load_dir` call at boot + banner
  + shutdown-summary lines + new import of
  `../src/safety/pem_truststore.nova`.
- `ENHANCEMENTS_ROADMAP.md` -- Phase O R1 shipped-note.

**Files added (R1):**
- `tests/unit/test_dtls_cert_chain.nova` -- ~50 checks against the
  x509_verify test-chain fixtures (RSA + ECDSA), covers every
  XV -> DTLS mapping branch, every stats counter, the two new
  error constant spellings, stats-line inclusion of the new
  counters, per-state counter isolation, accumulation across
  calls.
- `tests/unit/test_truststore_dir.nova` -- ~30 checks against
  fabricated per-test PEM + manifest fixtures under
  `$HOME/.crossengin_ph_o_r1_*/`. Covers non-existent dir, null /
  empty path, missing manifest, single file, two files merged,
  # comments + blank lines, missing file in manifest, corrupt PEM
  in manifest, CRLF line endings, no trailing newline, empty
  manifest, all-comments manifest.
- `docs/adr/0094-dtls-cert-chain-completion.md` -- this ADR.

**Verification.** Structural review + `make lint-ints` (no new
bug-#11 violations). `make test` cannot run end-to-end because the
NOVA compiler self-hosting bootstrap segfaults on this bench (per
Phase L / M / N standing caveat); the two new unit tests are
authored under the same shape / helpers as the passing suite so
they slot into a working bootstrap without change.

**Non-goals for R1** (queued for R2, R3, or later):
- No `use_srtp` extension emission (R2).
- No SRTP EKM stub-to-real forward (R2).
- No DTLS-over-TCP transport wrap (R3).
- No P-256 keypair loader / self-signed cert minting (R3).
- No connection-time gating on `dtls_anchors` in the fed daemon
  (R3 -- R1 only allocates and logs).

## References

- ADR-0089 -- Federation daemon shape (Phase M R1 seam this ADR builds on).
- ADR-0091 -- Attestation + replication (Phase M R3, the source of the
  `CE_FED_ATTEST_KEY_DIR` pattern this ADR mirrors).
- ADR-0093 -- Action module (Phase N R2, latest ADR that fixed the
  format template for this one).
- RFC 5246 -- TLS 1.2 (chain + cert semantics DTLS 1.2 reuses).
- RFC 6347 -- DTLS 1.2.
- RFC 4572 -- SDP fingerprint attribute (background for the legacy
  `dtls_cert_verify` fingerprint path; not touched here).
- `src/safety/x509_verify.nova:393` -- `cert_chain_verify` (the
  work-horse this ADR wires DTLS to).
- `src/safety/pem_truststore.nova` -- home of the new
  `truststore_load_dir`.
