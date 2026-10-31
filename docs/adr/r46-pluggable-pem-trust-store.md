# R46: Pluggable PEM trust store (anchors not hard-coded)

## Status

Accepted — R46 round. Generalises the R43 strict-TLS pin from two baked-in
gateway moduli to a trust store loaded from a PEM CA bundle.

## Date

2026-06-08

## Context

R43 made HTTPS authenticated by pinning the sandbox egress-gateway root CAs as
hard-coded hex moduli in `tls13_client.nova`. That works in this sandbox but is
not portable: a different environment has different CAs, and editing source to
re-pin is the wrong interface. The standard answer is a trust store — a PEM CA
bundle the operator points the client at.

## Decision

### `src/safety/pem_truststore.nova` (new)

`truststore_load(text)` / `truststore_load_file(path)` parse a PEM bundle
(concatenated `-----BEGIN CERTIFICATE-----` base64 blocks) into a list of RSA
anchors `[N_bn, e_int]`:
- find each BEGIN/END block, strip the base64 (one O(n) buffer pass), decode
  with the existing `scram_base64_decode`, and `cert_parse` the DER;
- keep the RSA public key; **skip** non-RSA roots (ECDSA) and any cert
  `cert_parse` rejects.

To support that skip cleanly, `cert_parse` now checks the SPKI algorithm OID
and returns not-ok for non-`rsaEncryption` keys (so an EC SPKI is never
mis-read as a garbage RSA modulus).

### Verifier takes a list of anchors

`cert_chain_verify(der_list, host, anchors, now)` now takes a *list* of `[N, e]`
anchors instead of a single pin: it verifies the chain signatures once, then
requires the top cert's key to equal **some** anchor. (A single pin is just a
one-entry list.)

### Wiring (`tls13_client.nova`)

`_tls_anchors()` (cached) reads `CE_TLS_CA_BUNDLE`; if set, the RSA roots in
that file become the trust store. If unset/empty, it falls back to the built-in
gateway pins, so the sandbox still authenticates out of the box. Strict mode
(`CE_TLS_STRICT=1`) is unchanged otherwise.

## Verification

- Unit: `pem_truststore` (5 — loads an RSA anchor whose key matches the cert
  modulus, **skips** an ECDSA cert in the same bundle, handles empty/garbage);
  `x509_verify` (8) updated to the anchor-list signature; `rsa` (5) unchanged.
- **Live**, strict mode, anchors loaded from a file (not the hard-coded pins):
  - `CE_TLS_CA_BUNDLE=<gateway-roots.pem>` → `chain→anchor + hostname +
    certverify OK`, HTTP 200.
  - `CE_TLS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt` (the full 150-cert
    system store) → ok, ~4 s including load (cached thereafter).
  - a bundle **without** the gateway root → `cert-verify-failed: root-not-pinned`
    (correctly rejected — the store genuinely gates).
- `learn_pipeline` compiles; chat regression scenarios pass.

## Consequences / scope

- TLS anchors are now configuration, not source: point `CE_TLS_CA_BUNDLE` at any
  PEM bundle (including the OS store) and the client trusts those CAs. The
  built-in gateway pins remain only as the no-config fallback.
- RSA-2048 anchors only: ECDSA roots are skipped, and RSA moduli wider than
  2048 bits don't fit `bignum_2048` and are skipped — so a chain rooted at an
  RSA-4096 or ECDSA CA won't validate yet. Widening needs `bignum_4096` /
  ECDSA-anchor support (a later round). For the gateway (RSA-2048) and most
  RSA-2048 roots this is sufficient.
- Trust is by public-key equality with an anchor (self-signed-root model); full
  path policy (name constraints, EKU, revocation) is still out of scope.
