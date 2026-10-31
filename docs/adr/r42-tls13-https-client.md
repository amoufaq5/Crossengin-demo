# R42: In-engine TLS 1.3 client (HTTPS for /learn)

## Status

Accepted — R42 round. Advances TLS_AUDIT.md from "PSK channel shipped, real
TLS deferred" to "TLS 1.3 1-RTT client shipped (no cert verification)".
Completes the HTTPS half of R41's live `/learn`.

## Date

2026-06-08

## Context

R41 wired live `http://` learning, but `https://` fell through to a deferred
stub — and that is most of the useful web (every large site forces HTTPS).
The blocker named in TLS_AUDIT.md was "no verified TLS/socket stack". But the
hard part — the cryptography — was already in the tree and RFC-tested:
`sha256`, `hmac_sha256`, `hkdf_*`, `chacha20`, `poly1305`, and `p256` ECDHE.
What was missing was the *assembly*: the TLS 1.3 key schedule, the record
AEAD, and the handshake state machine.

## Decision

Implement a minimal TLS 1.3 client (`src/io/transducers/tls13_client.nova`):

- **Cipher** `TLS_CHACHA20_POLY1305_SHA256` (0x1303) — no AES needed; ChaCha20
  + Poly1305 are already present and RFC 8439-tested.
- **Group** `secp256r1` (P-256) key share, via the existing `p256` ECDHE.
- **1-RTT**, no PSK / 0-RTT / client-cert.

The build was **test-first against published vectors**, because TLS fails
silently — a single wrong byte yields an opaque handshake abort:

1. **Key schedule** (HKDF-Expand-Label, Derive-Secret, the early→handshake→
   master ladder) pinned to the **RFC 8448** reference trace. RFC 8448 uses
   AES-128-GCM, but the secret ladder is SHA-256 and cipher-independent, so
   every secret matches exactly and the key is checked at the RFC's 16-byte
   length. (18 assertions.)
2. **Record AEAD** (ChaCha20-Poly1305 with AAD + the TLS per-record nonce)
   pinned to the **RFC 8439 §2.8.2** AEAD vector, including tamper rejection.
   (10 assertions.)

Only then the protocol layer: record I/O, ClientHello (SNI, supported_versions,
supported_groups, signature_algorithms, key_share), ServerHello parse, the
encrypted-flight decryption (EncryptedExtensions / Certificate /
CertificateVerify / Finished) with running transcript hash, the client
Finished, and the encrypted HTTP exchange (with chunked-transfer decoding).

### Wiring

`learn_pipeline.learn_from_url` routes `https://` through `tls_get` (resolving
the host with R41's DNS-over-UDP and reusing the same preprocess + ingest), so
the chat's `/learn https://…` works with no further change.

## Scope / honesty (read this)

- **No certificate verification.** The client completes the handshake and
  exchanges encrypted data but does **not** validate the server's X.509 chain
  (no ASN.1/PKI/CA bundle yet). The channel is therefore **confidential but
  UNAUTHENTICATED** — fine for fetching public knowledge for `/learn`, NOT for
  anything trusting the peer's identity. `tls_get` and the ADR say so plainly;
  X.509 is the next TLS_AUDIT.md slab.
- One cipher suite + one group. Servers that don't offer
  `TLS_CHACHA20_POLY1305_SHA256` over P-256 won't connect (most large CDNs do).
- `recv_data` has no timeout builtin — a stalled peer blocks. Acceptable for
  the opt-in `/learn` path.
- Triple-extraction quality on fetched prose is still the preprocessor's
  (R41) limitation, not TLS's.

## Verification

- Unit: `tls13_keyschedule` (28 assertions: RFC 8448 ladder + RFC 8439 AEAD +
  record nonce). Modules compile standalone (the `make build` gate).
- **Live**, in-engine, no shell/curl:
  - `https://example.com/` → HTTP 200, real HTML decrypted.
  - `https://en.wikipedia.org/wiki/Photosynthesis` → HTTP 200, **1375 content
    words + 93 reasoning operators** ingested from the decrypted page.
  - In the chat: a concept unknown before `/learn https://…` becomes
    reasoned-over after — the learning loop now closes over HTTPS.
- A latent bug surfaced and was fixed along the way: NOVA's plain `random()`
  faults on the second call without `random_seed()`, so TLS randomness uses
  `secure_random` (as `p256` does); and byte→string must use `substr` over the
  buffer (one O(n) copy), never per-char concatenation (O(n²), which timed out
  on a 256 KB page).

## Consequences

- `/learn` reaches the HTTPS web, fully in-engine: DNS-over-UDP + TLS 1.3 +
  HTTP/1.1, all in NOVA, no external shim.
- The crypto core is reusable for any future TLS need (kg-sync, federation
  transport) once certificate verification lands.
- Next (R43): X.509/ASN.1 + signature verification to authenticate the peer;
  optionally AES-128-GCM and X25519 for broader server compatibility.
