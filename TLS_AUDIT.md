# TLS_AUDIT — what real TLS in CrossEngin would take

Status: **deferred runtime seam (NOVA enhancement #11).** Plain HTTP/1.1 is now
landed in pure NOVA (`src/io/transducers/http_client.nova`, P1.4 Mode 1). HTTPS
itself continues to fall through to the `curl` shim in `scripts/learn.sh`. This
document is the roadmap — mirrors `WIN32_AUDIT.md` in the NOVA tree.

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

* **PSK-only TLS, no PKI: ~4 weeks** — 1 week crypto primitives (HKDF, AES-GCM,
  X25519, secure_rand), 1 week record layer + state machine, 1 week to wire
  into `http_client.nova`'s recv loop, 1 week interop tests against stock
  OpenSSL.
* **Full PKI TLS on top: +2 weeks** — mostly ASN.1 parsing and cert-chain edges
  (expired roots, hostname / SAN matching, name constraints).
* Combined honest estimate: **4-6 weeks** to a production-real HTTPS path.

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

* `src/io/transducers/http_client.nova` — Mode 1 pure-NOVA HTTP client.
* `src/learning/internet_fetch.nova` (`if_dispatch_transport`) — scheme-aware seam.
* `scripts/learn.sh` — curl shim that continues to handle `https://`.
* `nova-deps.toml` entry #11 — upstream tracker for full TLS.
* `tests/integration/scenario_j_http_client.sh` — end-to-end loopback proof.
