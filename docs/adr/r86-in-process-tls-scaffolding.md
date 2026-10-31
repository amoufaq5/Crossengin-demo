# R86: In-process TLS for wire endpoints (scaffolding only)

## Status

Accepted — R86 round; **wire-enabled in R94.** R86 scaffolded the
module skeleton, state machine, and alert enum. R87..R92 landed each
primitive (AEAD, KDF, ECDH, cert-verify, RNG, X.509). R93 landed the
handshake state machine with an in-memory test pump. **R94 flipped
`wire_connection_wrap` from a pass-through into a real
TLS-wrapped-fd type and shipped the sidecar recipe.** The in-process
TLS build-out (R86..R94) is now complete; the wire is TLS 1.3 when
the operator sets `CROSSENGIN_TLS=1` and provides cert material.
The full phase status table in "Build-out roadmap" below carries the
per-round ✅ marks; see the post-scriptum for what a hardened
deployment still wants.

## Date

2026-08-18

## Context

R49 exposed CrossEngin's JSON-RPC surface over a raw TCP socket. R54
added capability tokens as the wire's auth boundary, R54.1 shipped a
`stunnel` sidecar recipe for TLS termination, and R55.x layered
signed-skill install, per-user KG ownership, and session persistence on
top. The R54.1 sidecar works but it is an operator tax: two processes
to supervise, a UNIX-domain hop between them, cert paths managed
outside the daemon, and (importantly) capability tokens flow in
cleartext between the sidecar and the daemon over lo. That last part
is a real property: a shared-tenancy box where the daemon co-tenants
with other users has an attack surface no sidecar can close.

The R49 accept loop and the R54 capability model both assume the
socket **is** the auth boundary. Once CrossEngin ships to
multi-user hosts (§7.7 of `SHIP_AS_APP.md` describes the intended
posture) the wire must carry its own confidentiality and integrity,
not rely on a reverse-proxy or a co-tenant-trusting sidecar.

An in-process TLS implementation is many rounds of work in NOVA
(RSA/ECDSA/ECDHE/AES-GCM/ChaCha20-Poly1305/HKDF/SHA-2/X.509 parsing +
chain validation, plus a CSPRNG source at the runtime layer). R86
does **not** attempt the implementation. R86 stakes out the shape:
the modules, the connection-state enum, the alert enum (the one piece
that can be fully implemented from a table now), the wire hook the
daemon will call, and the phased roadmap that hangs each primitive off
a future round.

## Decision

### Chosen algorithm suite (TLS 1.3, minimal)

- **Cipher suite:** `TLS_CHACHA20_POLY1305_SHA256` (0x1303).
  Rationale: ChaCha20 + Poly1305 are 64-bit-word integer operations
  (rotate, add, xor) — no field arithmetic, no timing-sensitive table
  lookups, no need for constant-time AES S-boxes. AES-GCM is the more
  common suite on the wire but its safe software implementation in
  NOVA — a language without SIMD, without carry-less multiply, and
  where table lookups are cache-timing observable — is materially
  harder than ChaCha20-Poly1305. Picking one cipher (not both) keeps
  the handshake, key schedule, and record-layer nonce derivation to a
  single code path; a second cipher slot can land later without
  reshaping the module boundary.
- **Key exchange:** `x25519` (curve25519). Rationale: simpler field
  arithmetic than any NIST P-curve (a single 255-bit prime field with
  a fixed reduction), no big-int-per-parameter setup, no point-format
  serialization (raw 32-byte encoding), and the Montgomery ladder is
  a straightforward loop over 255 bits with constant-time conditional
  swap.
- **Signature scheme for cert auth:** `ed25519`. Rationale:
  deterministic signing (no CSPRNG required for the signing side —
  the daemon can hold a key and sign server hello messages
  reproducibly), the same curve as the key exchange (one field
  implementation instead of two), and a public key is a single 32-byte
  compressed point.
- **KDF:** `HKDF-SHA-256`. Rationale: TLS 1.3 mandates HKDF and the
  suite locks the hash to SHA-256 (Poly1305's design partner).
- **Cert format:** DER-encoded X.509 subset — only the fields TLS 1.3
  requires: `SubjectPublicKeyInfo` (ed25519 key), `Validity`, `Subject`
  (a single CN element), `Issuer`, `SerialNumber`, and one
  `SignatureAlgorithm`/`Signature` pair. No extensions parsing in the
  first cut (SAN handling deferred to a phase that also lands hostname
  match). Cert chain length capped at 2 (leaf + issuer) for the first
  cut; longer chains rejected with a defined alert.

### Module layout (this round)

```
src/net/tls/
    tls_config.nova       // cert/key material + cipher preference + cache config
    tls_state.nova        // connection state enum + transition helpers
    tls_record.nova       // record-layer framing stubs (header + content type)
    tls_handshake.nova    // handshake type enum + message struct stub
    tls_alerts.nova       // TLS 1.3 alert enum + serialize/parse (FULLY IMPLEMENTED)
    tls_wire_hook.nova    // wire_connection_wrap(fd, cfg) -> wrapped_conn
```

All module-level symbols use a `tls_` (or `tls_alert_`, `tls_state_`, …)
prefix to avoid the symbol collisions the NOVA runtime has historically
had with same-named identifiers across modules.

### Wire integration seam

The daemon's `accept_conn` result now flows through
`wire_connection_wrap(fd, tls_config)`. Today `tls_config` is always
null in `_rpcd_build_ctx`, so the hook is a **pass-through**: it
returns the raw fd unchanged. This is the single seam R87+ flips when
the primitives land: the daemon file does not change again, only
`tls_wire_hook.nova` does.

### Missing NOVA runtime capabilities (honest inventory)

R86 documents what R87+ must have from the runtime that today it does
NOT have. Each phase below lists the runtime work first, then the
CrossEngin work.

| Missing runtime primitive | First round it blocks | Cope in the interim |
|---|---|---|
| CSPRNG (e.g. `sys_getrandom` / `/dev/urandom` read) | R87 (client-random / server-random / ephemeral key) | ✅ R91 shipped `src/safety/rng.nova` — pluggable interface with three backends (OS via NOVA's `secure_random` builtin, TEST-ONLY deterministic ChaCha20-CTR, caller-supplied callback). No NOVA runtime change; OS backend is unavailable when the container's seccomp blocks `getrandom` (this project's sandbox is such an environment), so the callback backend is the recommended production integration when a launcher/sidecar supplies bytes. |
| 64-bit unsigned add/xor/rotate that survives NOVA's integer-op smart-dispatch bug #11 | R88 (ChaCha20 block function) | Use `int_add` / `int_xor` / `int_shl` escape hatches the way `stream_http` does for IP parsing |
| Big-int (255-bit) field arithmetic — add, sub, mul, invert mod p25519 | R89 (x25519 Montgomery ladder) | ✅ Delivered as `src/safety/field25519.nova` on top of int_* escape hatches; runtime needed no change |
| DER parsing helpers (`asn1_read_len`, tag reader) | R92 (X.509 subset parse) | ✅ Delivered as `src/net/tls/der.nova` (R92); runtime needed no change. Byte-list buffers with (buf, buf_len, off, out_params) shape, short + long form length, indefinite-length + long-form-tag + >4-length-bytes all refused. |
| Handshake state machine orchestration | R93 (end-to-end in-process TLS 1.3) | ✅ Delivered as `src/net/tls/tls_transcript.nova` + `src/net/tls/tls_session.nova`; runtime needed no change. Session driven by caller-owned inbound/outbound byte queues so R93 needs no wire integration. |
| Non-blocking accept + poll loop | R94 (multi-connection TLS) | R94 stays with the serial accept loop; TLS handshakes serialize behind it, which is acceptable for the single-user first cut but is a scaling ceiling. Concurrent TLS is a candidate for a post-R94 hardening round (see post-scriptum below). |

**Runtime is off-limits for R86** (standing constraint: never edit
`/home/user/NOVA/src/runtime/*`). The two runtime items above
(CSPRNG, non-blocking accept) are RUNTIME work; every other primitive
lands as a NOVA source file under `src/net/tls/prims/` and needs no
runtime change.

### Build-out roadmap (R87..R9X)

Each phase is one round. Phases are independent enough that they can
be reordered if a runtime blocker slips, but the ordering below is
what unlocks the most testable surface earliest.

- **R87 — ✅ Poly1305 + ChaCha20-Poly1305 AEAD.** The AEAD primitive
  phase (previously slated for R88 in the original roadmap; pulled
  into R87 once ChaCha20 and Poly1305 were both already present in
  `src/safety/`). Ships `src/safety/chacha20_poly1305.nova`
  (`caead_seal_buf` / `caead_open_buf` / `caead_ct_eq_buf` per
  RFC 8439 §2.8), extends `src/net/tls/tls_record.nova` with a
  concrete record-body seal/open path (`tls_record_seal_buf` /
  `tls_record_open_buf` per RFC 8446 §5.2 + §5.3), and adds the
  per-direction sequence-number counter (`tls_record_seq_*`). All
  RFC 8439 §2.8.2 + Appendix A.5 vectors green. **Wire hook still a
  pass-through** — the AEAD is exercisable via unit tests only,
  a live connection has to wait on handshake wire-up (R92) and the
  wire-hook flip (R93). The random-source seam and wire-integer
  serializers originally slated for R87 move to whichever later
  round needs them first (they're not on the AEAD path).
- **R88 — ✅ HKDF-SHA-256 + TLS 1.3 key-schedule wrappers.** Pull-in
  from the original R90 slot; every downstream handshake step needs
  the derived secrets before any of them can run. Ships
  `src/safety/hkdf_sha256.nova` (`hkdf_extract` / `hkdf_expand` /
  `hkdf_sha256` per RFC 5869) on top of the existing
  `src/safety/sha256.nova` (SHA-256 + HMAC-SHA-256, already in tree
  from R33A -- no re-implementation), plus `src/net/tls/tls_kdf.nova`
  with the TLS 1.3 wrappers per RFC 8446 §7.1 + §7.3:
  `tls_kdf_hkdf_label_bytes`, `tls_kdf_hkdf_expand_label`,
  `tls_kdf_derive_secret`, and `tls_kdf_derive_key_iv` (the entry
  point the record-layer AEAD from R87 will consume once traffic
  secrets exist). All three RFC 5869 test cases plus the RFC 8448
  §3 `early_secret` and `derived-from-early` spot-checks green
  (29 hkdf + 27 tls_kdf checks). Wire hook still a pass-through.
- **R89 — ✅ x25519 field arithmetic + Montgomery ladder.** Pure
  integer. Every RFC 7748 §5.2 and §6.1 vector byte-exact
  (`test_field25519` / `test_x25519` / `test_tls_keyshare`, +66
  checks total). Ships `src/safety/field25519.nova` (10-limb 26/25
  Bernstein layout), `src/safety/x25519.nova` (Montgomery ladder
  with clamp + all-zero rejection + base-point wrap), and
  `src/net/tls/tls_keyshare.nova` (TLS-facing thin wrapper +
  handshake_secret derivation into the RFC 8446 §7.1 key schedule).
  Wire hook still a pass-through; RNG source still missing (see
  §12 "Runtime gaps R92 must resolve" in `docs/SHIP_AS_APP.md`).
- **R90 — ✅ ed25519 verify + TLS CertificateVerify seam (signing
  deferred).** Audit-only on the pre-existing `src/safety/ed25519.nova`
  (built for R54.2 signed-skill install; RFC 8032 correct, SHA-512
  built inline, y >= p rejection, s >= L rejection, Montgomery-ladder
  scalar-mult). New `src/net/tls/tls_cert.nova` assembles the RFC
  8446 §4.4.3 signed content (64 x 0x20 || "TLS 1.3, {server,client}
  CertificateVerify" || 0x00 || transcript_hash) and wraps
  `ed25519_verify` behind `tls_cert_verify` / `tls_cert_verify_ed25519`.
  Tests: 16 additional RFC 8032 §5.1.7 rejection + determinism
  checks on `test_ed25519` (s == L, s == L+1, non-canonical A/R,
  all-zero pubkey, per-vector bit-flip); 41 new checks on
  `test_tls_cert` (byte-layout of the built input, server-vs-client
  differ in role word only, full sign+verify round-trip, tamper /
  shape rejection). X.509 parsing NOT included -- raw pubkey
  passed in.
- **R91 — ✅ CSPRNG source + pluggable RNG interface.** Ships
  `src/safety/rng.nova` with three backends: OS entropy (wraps
  NOVA's `secure_random` builtin, which itself wraps the Linux
  `getrandom` syscall, folded through a SHA-256 extractor);
  TEST-ONLY deterministic ChaCha20-CTR keyed by SHA-256(seed) for
  reproducible test coverage; and caller-supplied callback for
  integrators to plug in bespoke entropy sources. Wire integration:
  `tls_keyshare_generate(rng_ctx, priv, pub)` and
  `tls_random_generate(rng_ctx, buf, len)` on `tls_keyshare.nova`.
  75 new test checks (48 rng + 27 tls_keyshare_rng); regression
  green. **Caveat**: the OS backend is unavailable in this
  project's sandbox container (seccomp blocks `getrandom`, so
  `secure_random` returns -1); Backend C is the intended path
  there. A full HKDF-based DRBG is a candidate for a later round
  if the OS source proves unreliable across target environments.
- **R92 — ✅ X.509 subset parser + chain verify (chain-len<=2).**
  Ships `src/net/tls/der.nova` (minimal ASN.1 DER TLV walker) +
  `src/net/tls/x509.nova` (cert parser + chain verifier). RFC 5280
  fields extracted: serialNumber, issuer/subject CN, validity,
  SPKI (Ed25519), tbsCertificate byte range, signatureAlgorithm,
  signatureValue. RFC 8410 Ed25519 OID (`1.3.101.112`) recognized
  in both slots; RSA/ECDSA/other refused. UTCTime and
  GeneralizedTime with Z suffix supported (non-Z rejected).
  Non-critical extensions tolerated; critical extensions refused.
  `x509_chain_verify(leaf, root, now_unix, ...)` runs the full
  chain check (Ed25519 rigidity, validity window, root
  self-signature, leaf-signed-by-root, CN-based issuer match,
  self-signed-leaf refusal). `tls_cert.nova` gains
  `tls_cert_verify_chain_and_signature(...)` end-to-end wrapper.
  Test-cert fixture built programmatically via
  `x509_build_test_cert` (RFC 8032 TEST 1 root, TEST 2 leaf).
  147 new checks (73 der + 60 x509 + 14 chain end-to-end);
  regression sweep green. Consumes the R90 `tls_cert.nova` seam.
  **R95's trust-anchor registry lifts the "root supplied
  explicitly by caller" constraint by wiring the R55.1 trust
  material into cert selection.**
- **R93 — ✅ handshake state machine wire-up.** In-memory only
  (both peers instantiated in one process, byte queues as mock
  transport). Replaces the R86 `tls_handshake.nova` stubs with real
  parse / serialize for `ClientHello`, `ServerHello`,
  `EncryptedExtensions`, `Certificate`, `CertificateVerify`,
  `Finished` (RFC 8446 §4). Adds `src/net/tls/tls_transcript.nova`
  (SHA-256 transcript rolling with snapshot-`get`) and
  `src/net/tls/tls_session.nova` (connection state machine +
  per-direction record keys + inbound/outbound byte queues).
  Consumes R91 for RNG, R92 for the peer certificate chain, R88 for
  the RFC 8446 §7.1 key schedule (early / handshake / master +
  application traffic secrets), R89 for the ECDH shared secret, R90
  for CertificateVerify, R87 for the record-layer AEAD, and the
  R86 alert enum for fatal wire failures. **Crown-jewel test:** both
  peers derive byte-identical `client_application_traffic_secret_0`
  and `server_application_traffic_secret_0`; app data round-trips
  in both directions with correct sequence-counter progression;
  close_notify transitions both to CLOSING. **Explicit
  simplifications** (documented at commit): no 0-RTT / no PSK /
  no HelloRetryRequest / no client cert / no key update /
  no post-handshake auth. **Wire still cleartext** — `wire_connection_wrap`
  untouched; R94 flips it.
- **R94 — ✅ Wire-hook flip + sidecar recipe.**
  `wire_connection_wrap(fd, tls_config, rng_ctx, out_conn)` returns a
  real `tls_conn` when `tls_config` is non-null; the accept loop in
  `examples/crossengin_rpc_daemon.nova` opts in via
  `CROSSENGIN_TLS=1` and reads cert material from three base64 env
  vars. A tiny `src/net/tls/base64.nova` decoder unwraps them into
  the byte lists `tls_config_new_server` expects. `tls_config` grew
  new production-shape constructors:
  `tls_config_new_server(cfg_out, leaf_cert_buf, leaf_cert_len,
  leaf_priv_buf, root_cert_buf, root_cert_len)` and
  `tls_config_new_client(cfg_out, root_cert_buf, root_cert_len)`.
  The RNG for the handshake is selected via `CROSSENGIN_RNG_MODE`
  (`os` for Backend A / `test` for Backend B seeded from
  `CROSSENGIN_RNG_SEED` / `callback` for Backend C reading from
  `CROSSENGIN_RNG_FIFO`). This container's seccomp blocks
  `getrandom` (R91 finding), so the daemon MUST use
  `CROSSENGIN_RNG_MODE=callback` here; unrestricted deployments can
  use `os`. Sidecar itself is NOT shipped; the launcher recipe (env
  vars + `exec`) lives in `docs/SHIP_AS_APP.md` §7.44. Tests:
  `test_tls_wire_hook` (40 checks), `test_tls_config` (22 checks),
  `test_base64` (35 checks), `test_daemon_tls_bootstrap` (9 checks).
  Regression sweep across every existing TLS suite green. **Final
  TLS build-out round.**
- **R95 — trust-anchor registry + cert chain validation (len<=2).**
  Layer on the R55.1 trust-anchor pattern.
- **R96 — session-ticket resumption (0-RTT deferred).** Bring back the
  session cache stub in `tls_config.nova`.
- **R97 — alert delivery on live connections, close_notify semantics.**
  Today R86 tests the alert enum; R97 tests alerts actually reaching
  the peer.
- **R98..R9X — hardening.** Constant-time comparisons audit, cache-
  timing audit on ChaCha20 (no S-boxes so light), fuzz the DER parser,
  fuzz the handshake state machine, review the alert mapping against
  RFC 8446 §6.

### What R86 lands that IS testable now

- `tls_state.nova`: full state-machine transition coverage —
  which transitions are legal, which aren't, terminal states are
  terminal. No crypto required.
- `tls_alerts.nova`: alert enum + serialize/parse round-trip for every
  alert code in RFC 8446 §6.
- `tls_config.nova`, `tls_record.nova`, `tls_handshake.nova`: smoke
  tests that the modules load, structs construct, and stubs return
  the correct `TLS_NOT_IMPLEMENTED` sentinel.

## Verification

- **Unit** (`test_tls_state`, `test_tls_alerts`, `test_tls_scaffold`):
  state-machine transitions, alert round-trip, scaffold smoke.
- **Regression:** existing wire tests (`test_nl_rpc_server`,
  `test_capability_wire`) unchanged — the wire hook is a pass-through
  when `tls_config` is null, which is its only current caller.

## Consequences / scope

- **R86 baseline: wire is still cleartext.** The scaffolding round
  does not change what goes on the wire. Operators who need TLS
  before R94 lands continue to use the R54.1 sidecar recipe.
- **R94 update: wire can be TLS 1.3 when `CROSSENGIN_TLS=1`.** The
  R54.1 sidecar recipe stays supported (both paths coexist). R94 is
  the first round where an in-process TLS deployment is possible; it
  remains opt-in (feature-flagged via a non-null `tls_config` on
  daemon boot). Operators who don't set `CROSSENGIN_TLS=1` boot
  byte-identically to pre-R94.
- The daemon accept loop's shape is preserved. R86 added ONE call
  site (`wire_connection_wrap`); R94 kept that call site and changed
  what it returns (raw fd → real `tls_conn` when TLS is on).
- The module tree at `src/net/tls/` is stable — R87..R94 add files
  under `src/net/tls/prims/` and fill in the stubs, they do not
  re-shape the outer layout.
- Future ADRs r87..r9x reference this one for the chosen suite. Any
  cipher/kx/sig change from the choices above requires a new ADR
  because it changes the primitive set every phase depends on.

## Post-scriptum (R94): what a hardened deployment still wants

R94 closes the R86..R94 in-process TLS epic — the wire carries real
TLS 1.3 with cert-authenticated x25519 + ChaCha20-Poly1305, gated by
the operator's own trust anchor. What a hardened multi-user
deployment would still want on top, in rough order of value:

- **Session resumption / 0-RTT / PSK.** R94 does one full handshake
  per accepted connection. `tls_config.session_cache_size` is still
  a stub. RFC 8446 §2.2 + §4.2.10 + §4.2.11 spell out the shape;
  R96 is a candidate.
- **Client-cert authentication (mutual TLS).** R94 authenticates
  server → client only. `session_new_server` never asks for a
  `Certificate` message from the client. A wire path where the
  daemon accepts only whitelisted client certs would fold in with
  the R55.1 signed-skill trust-anchor pattern (RFC 8446 §4.3.2).
- **HelloRetryRequest.** R94 rejects any ClientHello that doesn't
  already offer x25519. A tolerant server would negotiate down to
  the client's best offered group via HRR (RFC 8446 §4.1.4).
- **Post-handshake key update.** RFC 8446 §4.6.3 rotates keys mid-
  connection. Long-lived TLS connections without this leak more
  material to a single-key-compromise attacker over time; R94 has
  no time or byte-count driven rotation.
- **Certificate rotation without downtime.** `tls_config` is
  captured at daemon boot; changing the cert requires a restart.
  A future round could add a `tls_config_reload(cfg, new_material)`
  path that swaps atomically between handshakes.
- **OCSP / CRL revocation checking.** R94 trusts a valid cert chain
  unconditionally once it verifies against the root. Real
  deployments need a way to say "this leaf was revoked" without
  waiting for validity-window expiry (RFC 6960 / RFC 5280 §5).
- **SNI-based multi-cert selection.** R94 presents one leaf. A
  reverse-proxy-style daemon serving multiple hostnames would need
  to pick the leaf from a table keyed by ClientHello.SNI (RFC 6066
  §3).
- **External trust anchor store.** R94 passes the root DER inline
  through `tls_config_new_server` / `tls_config_new_client`. A
  bigger deployment would want a directory (or database) of anchors
  the daemon reloads without a restart, plus a wire verb for
  admin-managed anchor rotation — folds naturally with the R55.1
  trust-anchor registry pattern.
- **Automated cert issuance (ACME / step-ca) in the sidecar.** R94
  ships the sidecar CONTRACT (three env vars) but not the sidecar
  itself. An operator running against Let's Encrypt / an internal
  step-ca still writes the fetch + renewal loop by hand. A
  reference sidecar (shell or NOVA program) would remove that tax.
- **Concurrent TLS handshakes.** The daemon serializes accept +
  handshake. A concurrent handshake path needs a runtime primitive
  (non-blocking accept + poll) that today is not in NOVA; the R86
  runtime-gap table above tracked this. When the runtime gains
  non-blocking I/O this is one of the first daemon-side lifts.

None of these block a real R94 deployment — they extend it. The
primitives + handshake + wire wiring are in tree today; a hardening
round would layer on top.

## Role in the Model Substrate

In-process TLS gates every consumption mode that carries traffic
over a wire — client-app (mode 4) between the frontend and the
daemon, per-user selective-load (mode 2) on the multi-user host,
mother-daemon-direct (mode 1) whenever the mother accepts non-
loopback callers, embedded (mode 5) when a device speaks to its
owner's mother, and baked-child (mode 3) both between the child
and its clients and on the mother-to-child update channel that
ADR-0200's factory frame relies on.

This ADR is not part of the reasoning triad. It is transport for
the substrate — the layer that keeps capability tokens, KG-deltas,
signed child bundles, and RPC payloads confidential and integrity-
checked in flight. The choice of ChaCha20-Poly1305 + x25519 +
ed25519 is what makes the factory's "child polls mother for a
signed KG-delta" step tractable: the mother/child update channel
reuses the same primitives that already sign skills (R54.2) and
that ADR-0209 extends to whole child bundles. Nothing in the
reasoning path or the LLM-free primary NLP path (ADR-0211) is
affected by whether TLS is on — this layer is orthogonal to
cognition.

**See also:** ADR-0200 (AI-factory frame — presumes an encrypted
mother-to-child wire), ADR-0203 (KG-delta update channel — rides
this transport), ADR-0209 (signed child bundle — reuses ed25519
from this suite), ADR-0207 (bake manifest — update_key is an
ed25519 key from this suite).
