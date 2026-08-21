# R86: In-process TLS for wire endpoints (scaffolding only)

## Status

Accepted — R86 round. **Scaffolding only.** No cryptographic operation
is performed by any code this ADR introduces; the wire is still
cleartext by default. R86 lays the module skeleton, state machine, and
alert enum that R87..R9X will slot real primitives into without churning
the daemon architecture.

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
| Non-blocking accept + poll loop | R94 (multi-connection TLS) | R86 keeps the serial accept loop; TLS handshakes serialize behind it — acceptable for single-user first cut |

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
- **R93 — handshake state machine wire-up. Next TLS phase.**
  Fill in the `tls_handshake.nova` message parsers/serializers.
  Drive `tls_state.nova` through a real ClientHello/ServerHello
  round trip. Consumes R91 for RNG (via `tls_keyshare_generate`
  and `tls_random_generate`) and R92 for the peer certificate
  (via `tls_cert_verify_chain_and_signature`).
- **R94 — record-layer AEAD wrap/unwrap + application-data path.**
  `wire_connection_wrap` starts returning a REAL wrapped_conn whose
  read/write encrypt/decrypt through the record layer. Feature-flag
  ON only when a `tls_config` is present.
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

- **Wire is still cleartext.** R86 does not change what goes on the
  wire. Operators who need TLS today continue to use the R54.1 sidecar
  recipe.
- The R54.1 sidecar recipe stays supported for the whole R87..R94
  window; R94 is the first round where an in-process TLS deployment
  becomes possible, and even then it is opt-in (feature-flagged via a
  `tls_config` on daemon boot).
- The daemon accept loop is unchanged in behavior. It gains ONE call
  site (`wire_connection_wrap`), which is a pass-through.
- The module tree at `src/net/tls/` is stable — R87..R94 add files
  under `src/net/tls/prims/` and fill in the stubs, they do not
  re-shape the outer layout.
- Future ADRs r87..r9x reference this one for the chosen suite. Any
  cipher/kx/sig change from the choices above requires a new ADR
  because it changes the primitive set every phase depends on.
