# R43: Strict TLS authentication — RSA cert-chain verification + pinned anchor

## Status

Accepted — R43 round. Adds certificate verification to the R42 TLS 1.3 client,
making HTTPS *authenticated* (opt-in strict mode), not merely encrypted.

## Date

2026-06-08

## Context

R42 shipped a working TLS 1.3 client but with **no certificate verification**
(confidential, unauthenticated). Closing that gap surfaced a material fact
about the environment:

- **This sandbox terminates all outbound TLS at an Anthropic egress gateway.**
  example.com and en.wikipedia.org both present certificates issued by
  `O=Anthropic, CN=…Egress Gateway SDS Issuing CA`, chaining to a
  `…Egress Gateway CA` root that is installed in the system trust store. The
  real public certificates are never seen from inside. This is normal
  network-policy enforcement — but it means a TLS client in the sandbox can
  only ever authenticate **the gateway**, never the true origin.
- The gateway certs are **RSA-2048** (`sha256WithRSAEncryption`); the existing
  `x509.nova` parses ECDSA only, and no RSA signature verification existed.

Per the chosen direction ("pin the gateway CA for live strict auth"), R43
builds the RSA + X.509 machinery and pins the gateway root so strict
verification works **live in this sandbox**, authenticating the actual TLS
peer.

## Decision

### RSA verification (`src/safety/rsa.nova`, new)

PKCS#1 v1.5 and PSS (MGF1) SHA-256 verification over the existing
`bignum_2048` modexp (`s^e mod N`). Validated offline against openssl-generated
signatures (`tests/unit/test_rsa.nova`): PKCS#1 v1.5 (used for cert chain
signatures) and PSS (used for the TLS 1.3 CertificateVerify with an RSA leaf),
plus tamper / wrong-hash rejection.

### RSA cert parsing + chain verification (`src/safety/x509_verify.nova`, new)

A minimal DER walker that extracts what a chain check needs and `x509.nova`
does not: the RSA public key (modulus + exponent), the Subject Alternative
Names, the validity window, and the exact tbsCertificate byte range + the
signature. `cert_chain_verify`:

1. verifies each cert's PKCS#1 v1.5 signature under the next cert's key,
2. requires the top cert's key to equal a **pinned anchor**,
3. matches the leaf SAN against the host (exact or `*.suffix` wildcard),
4. checks the leaf validity window.

Tested (`tests/unit/test_x509_verify.nova`) against a synthetic openssl chain
(stable, 100-year validity) — parse, chain, wildcard, wrong-host, wrong-pin.

### Wiring (`tls13_client.nova`)

Strict mode (`CE_TLS_STRICT=1`, default off) captures the Certificate +
CertificateVerify during the handshake and, before sending the request:
- verifies the chain to a pinned gateway root (production + staging anchors
  embedded), and
- verifies the CertificateVerify RSA-PSS signature with the leaf key over the
  transcript-through-Certificate.
Any failure aborts the fetch with `cert-verify-failed`. `learn_pipeline` /
`/learn https://` honour it automatically.

## Verification

- Unit: rsa (5), x509_verify (8), tls13_keyschedule (28) — all green.
- **Live, against the real egress-gateway chain (leaf ← SDS Issuing CA ←
  pinned root):**
  - strict `/learn https://example.com/` → "STRICT: chain→pinned root +
    hostname + certverify OK", HTTP 200.
  - the same chain with a wrong hostname → `hostname-mismatch` (rejected); with
    a non-gateway pin → `root-not-pinned` (rejected).

## Scope / honesty (read this)

- **The pinned anchors are the sandbox egress-gateway CAs.** Strict mode
  therefore authenticates **the gateway**, which is the actual TLS peer here —
  it does NOT (and cannot, from inside the sandbox) authenticate the true
  origin server, because the gateway re-originates the connection. In a
  non-proxied deployment these pins won't match and strict mode would reject;
  that environment would supply its own trust anchors. This is why strict is
  **opt-in**, lenient is the portable default.
- RSA only on the verification path (the gateway certs are RSA); ECDSA leaves
  (`ecdsa.nova` exists) are not wired into the strict CertVerify yet. No CRL /
  OCSP revocation, no name-constraints / EKU policy checks — chain signature +
  pin + hostname + validity + proof-of-possession only.
- The `bignum_2048` modexp is constant-time and not fast; ~4 RSA verifies per
  strict handshake add latency to `/learn`, acceptable for an opt-in path.

## Consequences

- HTTPS `/learn` can now be **authenticated** in this sandbox, end to end, in
  NOVA: DNS-over-UDP + TLS 1.3 + RSA X.509 chain validation + pinning.
- The RSA + X.509 verifiers are reusable (federation transport, snapshot
  attestation) wherever RSA PKI appears.
- Follow-ups: ECDSA CertVerify wiring for non-RSA leaves; a pluggable trust
  store (PEM bundle) so anchors aren't hard-coded; name-constraints / revocation.

## Update (PR 4b, audit F-17 follow-up)

RSA verification now runs on `src/safety/bignum_rsa.nova`, a width-generic
(64/96/128-limb) Montgomery implementation with a variable-time public
exponent modpow (16 squarings + 1 multiply for e = 65537). Every input to a
signature verify is public, so constant time is not needed there; the
constant-time `bignum_2048` ladder stays for the DH users. Effects:

- RSA-2048/3072/4096 keys; certificate signatures sha256/384/512WithRSA;
  TLS 1.3 CertificateVerify rsa_pss_rsae_sha256/384/512 (new
  `src/safety/sha512.nova` for SHA-384/512).
- A verify takes milliseconds instead of seconds.
- 86 of the 122 roots in `/etc/ssl/certs/ca-certificates.crt` load (all RSA
  roots and the P-256 ones); P-384 / P-521 are PR 4c.
- Anchor matching compares widths and the exponent (`bnr_eq`), so keys of
  different sizes can never match on their low limbs (the F-17 failure mode).
- Not supported: RSASSA-PSS *certificate* signatures (none in the system
  bundle) and SHA-1 signatures.

## Update (PR 4c)

P-384 (`src/safety/p384.nova`) on the same width-generic Montgomery code
(12 limbs; Jacobian a = -3 formulas; Shamir's trick for u1*G + u2*Q;
Fermat inversion; variable time -- public inputs only). Certificates may use
ecdsa-with-SHA256/384/512 with a P-256 or P-384 key (a longer digest is
truncated to the curve order's size, FIPS 186-4 6.4); the namedCurve OID
must match the point length. TLS 1.3 CertificateVerify accepts
ecdsa_secp384r1_sha384 (0x0503), and 0x0403 / 0x0503 are bound to their
curve. The system bundle now loads 121 of 122 roots (all but P-521), and 118
of them verify their own signature under this code (the other 3 are
SHA-1-signed).
