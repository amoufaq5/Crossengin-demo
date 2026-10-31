# TLS_AUDIT — what real TLS in CrossEngin would take

Status: **TLS 1.3 client with opt-in strict authentication + a pluggable PEM
trust store (R43, R46).** R46 (`src/safety/pem_truststore.nova`) loads RSA trust
anchors from a PEM CA bundle pointed to by `CE_TLS_CA_BUNDLE` (e.g.
`/etc/ssl/certs/ca-certificates.crt`), so anchors are configuration rather than
hard-coded; the built-in gateway pins remain the no-config fallback. See
`docs/adr/r46-pluggable-pem-trust-store.md`.

Status (R43): **TLS 1.3 client with opt-in strict authentication.** R43 adds
RSA cert-chain verification (`src/safety/rsa.nova` PKCS#1 v1.5 + PSS,
`src/safety/x509_verify.nova` chain + SAN + validity) and a pinned gateway-root
anchor: with `CE_TLS_STRICT=1` the client verifies the presented chain to the
pinned sandbox egress-gateway CA + hostname + CertificateVerify before sending
the request, and rejects on any failure (verified live, incl. wrong-host /
wrong-pin rejection). The pins authenticate the gateway -- the actual TLS peer
in this sandbox -- not the true origin; strict is opt-in, lenient is the
portable default. See `docs/adr/r43-tls-certificate-verification.md`.

Status (R42): **TLS 1.3 1-RTT client shipped — without certificate
verification.** `src/io/transducers/tls13_client.nova` completes a real
`TLS_CHACHA20_POLY1305_SHA256` + P-256 handshake and exchanges encrypted HTTP,
validated against the RFC 8448 key-schedule trace and the RFC 8439 AEAD vector
(`tests/unit/test_tls13_keyschedule.nova`) and live against example.com /
en.wikipedia.org. It does NOT yet verify the server's X.509 chain
(confidential but UNAUTHENTICATED — see `docs/adr/r42-tls13-https-client.md`);
X.509/ASN.1/PKI is the next slab. The PSK secure-channel and plain HTTP below
remain.

Status (pre-R42): **PSK secure-channel shipped; full TLS 1.3 deferred (NOVA
enhancement #11).** Plain HTTP/1.1 is in pure NOVA
(`src/io/transducers/http_client.nova`, P1.4 Mode 1). A second hop on the
roadmap also landed: a **PSK-only ChaCha20-Poly1305 secure channel over TCP**
(`src/io/transducers/secure_channel.nova` + `src/safety/chacha20.nova` +
`src/safety/poly1305.nova`, P1.4 extension). The PSK channel gives
confidentiality + integrity without any TLS framing, X.509, or certificate
validation -- it's a wireguard-style "noise envelope" with a pre-shared
key. Real HTTPS (TLS 1.3 with X.509) continues to fall through to the
`curl` shim in `scripts/learn.sh`. This document is the roadmap -- mirrors
`WIN32_AUDIT.md` in the NOVA tree.

## What shipped (PSK secure channel)

* **ChaCha20 stream cipher** (`src/safety/chacha20.nova`): pure NOVA ARX
  primitives (add / rotate / xor over `int_add`, `int_xor`, `int_and`,
  `int_or`, `int_shl`, `int_shr`), 20 rounds per block, 64-byte
  keystream blocks. Verified against RFC 7539 sections 2.1.1
  (quarter-round), 2.3.2 (block function, key=00..1f, nonce=00..09 00 00
  00, counter=1), and 2.4.2 ("Ladies and Gentlemen..." 114-byte
  plaintext encryption); 26 unit-test assertions in
  `tests/unit/test_chacha20.nova` cover those plus the 32-bit rotate
  edge cases, add-wrap wraparound, and the hex codec used to move raw
  bytes through NOVA strings (which can't hold zero bytes).
* **Poly1305 MAC** (`src/safety/poly1305.nova`): 5 x 26-bit limb
  representation of the 130-bit accumulator; per-block
  `(a + n) * r mod (2^130 - 5)` evaluation; clamp + final reduction +
  `s` addition. Verified against RFC 7539 sections 2.5 (clamp), 2.5.2
  (canonical 34-byte "Cryptographic Forum Research Group" tag =
  `a8061dc1305136c6c22b8baf0c0127a9`), and 2.6.2 (key derivation from
  a ChaCha20 block with counter=0). 9 unit-test assertions in
  `tests/unit/test_poly1305.nova`, including verify happy + tamper
  rejection.
* **secure_channel framework**
  (`src/io/transducers/secure_channel.nova`): wraps an existing TCP
  socket in a per-frame envelope. Wire format per frame after handshake
  is `[4-byte BE length] [12-byte nonce] [ciphertext] [16-byte tag]`.
  The 12-byte nonce splits 4 / 8 into a session-id prefix and a
  per-direction monotonic counter. Per-frame Poly1305 one-time key is
  derived from `ChaCha20(session_key, frame_nonce, counter=0)[0..32]`
  per RFC 7539 section 2.6.1. Public API: `sc_open(host, port, psk_hex)
  -> sc_state | 0`, `sc_send(state, buf, len) -> 1|0`, `sc_recv(state)
  -> [buf, len] | 0`, `sc_close(state)`, `sc_psk_validate(psk_hex)`.
  Handshake: client sends 12-byte session nonce -> both derive session
  key -> client sends a 16-byte "CE-SC-HS-OK" magic frame -> server
  echoes the same magic back, verifying the PSK matches and the
  channel is functional. 16 unit-test assertions in
  `tests/unit/test_secure_channel.nova` cover PSK validation,
  session-key determinism, nonce-layout, frame round-trip, and
  single-bit tamper rejection.
* **http_client integration**: opt-in `https_get_psk(url, psk_hex,
  max_bytes)` in `src/io/transducers/http_client.nova` opens the
  channel via `sc_open`, sends the HTTP/1.1 request in one frame,
  reads frames until the peer closes, and re-uses the existing
  `_hc_parse_response` to extract `[status, headers, body, err]`. Note
  this is NOT real HTTPS -- the URL scheme is informational, there is
  no certificate validation, and the receiver's hostname is not
  cryptographically bound to the PSK. It's "HTTP over a PSK-encrypted
  channel" suitable for daemon-to-controlled-upstream traffic.
* **End-to-end integration test**
  (`tests/integration/scenario_v_secure_channel.sh`): spawns a Python
  counterpart (`scripts/secure_channel_echo.py`) that implements the
  same wire framing as a sanity check on the NOVA primitives; the NOVA
  driver connects via `sc_open`, sends `"ping"`, receives `"pong"`
  (the Python server rewrites `ping` -> `pong` so the assertion is
  meaningfully about decryption, not just byte-echo). 6 bash
  assertions: exit code 0, handshake completed, ping sent, decrypted
  reply equals `pong`, reply is 4 bytes, server exited 0.

## SAFETY caveat -- predictable nonce without `getrandom(2)`

NOVA does not expose `getrandom(2)`. The handshake nonce is built from
`nanotime()` and a small process-local counter -- NOT a CSPRNG. For PSK
channels this reduces the failure mode to "an attacker can replay or
predict the nonce, but the PSK is still secret". The catastrophic
failure mode is **nonce reuse with the same PSK across sessions** --
ChaCha20-Poly1305 leaks bits of both plaintexts under any nonce
collision. Production deployments MUST refresh the PSK before reusing
any nonce-derived material. The integration test refreshes the PSK
per run (32 fresh bytes from `/dev/urandom`) so the caveat doesn't
fire in CI. Permanent fix: add a `secure_rand(buf, n)` NOVA builtin
backed by `getrandom(2)`; tracked in the table below.

## Why TLS isn't here yet

TLS 1.3 is not "TCP plus a little extra." The minimum production-real handshake
needs: ECDHE on X25519 (a 256-bit scalar multiply on a Montgomery curve), HKDF
over SHA-256 to derive eight traffic secrets, AEAD record encryption
(AES-128-GCM, per-record nonce by IV XOR explicit counter), and X.509 cert
chain validation against trusted roots (RSA-PSS or ECDSA-P256 signatures,
notBefore/notAfter windows). Every layer wants primitives NOVA does not expose
yet — bignum arithmetic, AES, SHA-256, a secure random source, constant-time
byte compare. Bolting any one in is a multi-week effort; landing all of them
plus the protocol state machine is the 4-6 week call.

## Minimum scope for a real-enough TLS 1.3

* **Cipher: `TLS_AES_128_GCM_SHA256` only.** AES-128 has the smallest software
  footprint and is mandatory-to-implement in RFC 8446 — locking to it removes
  AEAD selection logic.
* **Key exchange: X25519 only.** Reference implementation is a few hundred
  lines of straight-line Montgomery-ladder code over a 256-bit limb vector
  with `add`, `sub`, `mul`, `inv`, constant-time conditional swap. No
  general-purpose bignum.
* **Handshake:** ClientHello (random + X25519 key-share + supported_versions
  0x0304) -> ServerHello (peer X25519 public + chosen cipher) -> derive
  `handshake_traffic_secret` -> decrypt EncryptedExtensions / Certificate /
  CertificateVerify / Finished -> client Finished -> `application_traffic_secret`.
* **Record layer:** 5-byte header + AEAD decrypt into a plaintext stream; the
  recv loop in `http_client.nova` keeps its shape, only the source changes.
* **Cert verification against a hardcoded CA bundle** — bake 5-10 roots at
  build time, no runtime updates. Hard limit, not permanent design.

## Recommended path: PSK-only TLS first

Strongly recommended next step: **TLS 1.3 with external pre-shared keys, no
certificate path at all.** PSK skips X.509 / signatures / CA bundle entirely:
client and server share a 32-byte `psk` out of band, the handshake derives
all secrets from `HKDF-Extract(psk, ...)`. Crypto surface shrinks to
HKDF-SHA256 + AES-128-GCM + X25519 (still wanted for forward secrecy via
`psk_dhe_ke`). Roughly half the code; more than half the bugs avoided.
Immediate production case: CrossEngin daemons talking to a CrossEngin-controlled
upstream (KG sync over TLS, federated learning endpoints). PKI TLS becomes a
strict extension on top — same state machine, same record layer, plus an
ASN.1 parser and a CA store.

## Missing NOVA builtins for crypto

| Need | Today | Required form |
|------|-------|---------------|
| Secure random | only `nanotime()` (predictable!) | `secure_rand(buf, n)` over `getrandom(2)` |
| Constant-time compare | builtin `==` short-circuits | `ct_memcmp(a,b,n)` -> 0/1 with no branch on contents |
| Wide multiply | loop-body multiply codegen bug above 2^20 (gotcha #11) | `mul_wide(a,b)` builtin or a fixed asm shim |
| 64-bit add-with-carry | 64-bit signed, no carry exposed | `addc(lo,hi)` -> `(sum, carry)` |
| AES round | none | AES-NI intrinsic OR ~50-line constant-time table |
| SHA-256 block | none | ~150-line block compressor, can be pure NOVA |

Wall-clock (cert validity windows) is already adequate via `time()` (epoch
seconds). Bignums are X25519-specific and bounded — no general-purpose RSA/DSA.

## Wall-clock estimate to MVP

* **PSK secure channel (ChaCha20-Poly1305 over TCP, no TLS framing):**
  **SHIPPED** in this revision. Pure-NOVA ChaCha20 + Poly1305 primitives,
  per-frame envelope, opt-in `https_get_psk(url, psk_hex, max_bytes)` over the
  existing HTTP client. ~3 KLOC of NOVA + a Python parity helper for
  integration tests. NOT real TLS; treat it as a wireguard-style noise
  envelope over an existing socket.
* **PSK-only TLS 1.3 (real TLS framing on top of the PSK channel):
  ~3 weeks** -- 1 week HKDF-SHA256 (still need a SHA-256 block compressor),
  1 week record layer + state machine + X25519 for `psk_dhe_ke` forward
  secrecy, 1 week interop tests against stock OpenSSL with
  `--tls1_3 --psk_identity`.
* **Full PKI TLS on top: +2 weeks** — mostly ASN.1 parsing and cert-chain edges
  (expired roots, hostname / SAN matching, name constraints).
* Combined honest estimate to production-real HTTPS: **5-6 weeks
  remaining** (was 4-6 weeks; the PSK secure-channel layer above clears the
  symmetric-crypto block).

## Workaround until then

`scripts/learn.sh` continues to handle `https://` via `curl --max-time 15
-A crossengin-learn/0.1`. The new dispatcher
`if_dispatch_transport(url, max_bytes)` in `src/learning/internet_fetch.nova`
routes `http://` to the in-process pure-NOVA client (Mode 1) and returns the
`IF_TRANSPORT_DEFERRED` tag for `https://`, with the error string pointing
back to this file. The caller (typically the chat's `/learn` via
`scripts/learn.sh`) sees no regression — it already falls through to curl for
the deferred branch. The whitelist gate, rate limit, and cache all stay live;
only the byte-fetching transport is gated.

In a sealed environment (no curl, no internet) the agent is fully functional
except `/learn <https-URL>` fails gracefully with the deferred tag and a
one-line operator hint.

## Cross-references

* `src/io/transducers/http_client.nova` — Mode 1 pure-NOVA HTTP client +
  PSK-secure `https_get_psk` opt-in.
* `src/io/transducers/secure_channel.nova` — PSK ChaCha20-Poly1305 envelope
  over TCP; the new layer above TCP.
* `src/safety/chacha20.nova` — pure-NOVA ChaCha20 stream cipher (RFC 7539).
* `src/safety/poly1305.nova` — pure-NOVA Poly1305 MAC (RFC 7539).
* `src/learning/internet_fetch.nova` (`if_dispatch_transport`) — scheme-aware seam.
* `scripts/learn.sh` — curl shim that continues to handle `https://`.
* `scripts/secure_channel_echo.py` — Python counterpart with the same wire
  framing, used by the integration test as a sanity check on the NOVA
  primitives.
* `nova-deps.toml` entry #11 — upstream tracker for full TLS (now narrowed to
  HKDF-SHA256 + record layer + X.509 since the symmetric layer landed).
* `tests/integration/scenario_j_http_client.sh` — plain-HTTP end-to-end loopback.
* `tests/integration/scenario_v_secure_channel.sh` — PSK secure-channel
  end-to-end loopback (NOVA client <-> Python echo, ping -> pong).
* `tests/unit/test_chacha20.nova`, `tests/unit/test_poly1305.nova`,
  `tests/unit/test_secure_channel.nova` — RFC 7539 vector unit tests + the
  framing round-trip.
