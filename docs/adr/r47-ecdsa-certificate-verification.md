# R47: ECDSA certificate verification (key-type-agnostic strict TLS)

## Status

Accepted — R47 round. Extends the strict-TLS verifier (R43/R46) to ECDSA-P256
leaves, chains, and trust anchors, so it authenticates non-RSA servers.

## Date

2026-06-08

## Context

R43–R46 built strict HTTPS authentication but RSA-only: `cert_parse` rejected
EC keys, `cert_chain_verify` used PKCS#1 for every link, the `CertificateVerify`
path handled only `rsa_pss_rsae_sha256`, and the trust store loaded only RSA
anchors. Most of the public web that isn't RSA uses ECDSA-P256 leaves
(`ecdsa-with-SHA256` signatures, `ecdsa_secp256r1_sha256` CertVerify). The
`ecdsa_p256_verify` primitive already shipped and is RFC-tested (25 checks); the
gap was the X.509 + TLS plumbing.

## Decision

Make the whole verification path key-type-agnostic:

- **`cert_parse`** reads the SPKI algorithm OID and the signatureAlgorithm OID,
  tagging each cert with `key_type` (RSA / EC) and `sig_type` (RSA-PKCS#1 /
  ECDSA), and extracts either the RSA modulus+exponent or the 65-byte P-256
  point. Unknown key algorithms return not-ok.
- **`cert_verify_under(child, parent)`** dispatches on the child's `sig_type`:
  RSA-PKCS#1-SHA256 under an RSA parent, or ECDSA-P256-SHA256 (DER `r,s` parsed
  to 32-byte buffers) under an EC parent. `cert_chain_verify` uses it for every
  link, so mixed and all-ECDSA chains validate.
- **Trust anchors are typed** `[key_type, A, B]` (RSA `[KEY_RSA, N, e]`, EC
  `[KEY_EC, point, point_n]`); `cert_anchor_match` compares by modulus or by
  point bytes. The PEM trust store now loads RSA **and** EC roots.
- **`CertificateVerify`** dispatches `0x0804` (RSA-PSS, RSA leaf) and `0x0403`
  (ECDSA-P256, EC leaf) using the leaf's key.

## Verification

- Unit: `x509_verify` 8 → 14 — a synthetic openssl **ECDSA-P256 chain** (EC root
  → EC leaf, SAN, `ecdsa-with-SHA256`) parses as EC, its ECDSA chain signature
  verifies under the root's EC key, and wrong-host / wrong-anchor are rejected.
  `pem_truststore` (5) now asserts both an RSA and an EC anchor load from a
  mixed bundle. `ecdsa` (25) and `rsa` (5) unchanged.
- **Live RSA path unchanged**: strict `/learn https://example.com/` still
  verifies the RSA gateway chain (`chain→pinned root + hostname + certverify
  OK`, HTTP 200) — the refactor didn't regress it. Chat scenarios pass; chat
  rebuilds.

## Scope / honesty

- **Cannot be demonstrated live here.** This sandbox MITMs all outbound TLS with
  RSA gateway certs (see ADR-0R43), so an ECDSA `CertificateVerify` never occurs
  against the gateway. The ECDSA path is validated offline (synthetic EC chain +
  the RFC-tested `ecdsa_p256_verify`); it would engage against a real ECDSA
  server in a non-proxied deployment.
- P-256 only (the curve `ecdsa.nova`/`p256.nova` implement). P-384/P-521 and
  EdDSA leaves are not handled; RSA stays 2048-bit (bignum_2048). No
  name-constraints / EKU / revocation.
