# ADR R36F-0006: Canonical crypto primitives under `safety/`

## Status
Accepted (R36F) -- crystallises the pattern established at R33A
(`safety/sha256.nova` dedup refactor) and applied at R34A (federation
SHA-256 consolidation) and across R31-R35.

## Context
By the end of R32, CrossEngin had at least four separate inline
implementations of SHA-256:

  - `src/federation/dtls12.nova` had one for transcript hashing.
  - `src/safety/noise_xk.nova` had one for HKDF.
  - `src/safety/merkle.nova` had one for tree-hashing.
  - `src/safety/ecdsa.nova` had one for `H(message)` before signing.

Each was independently written, similar but not identical. A bug fix
to one (e.g. constant-time padding handling) had to be replicated to
the other three. R29B caught one such asymmetry: `merkle.nova` rejected
zero-length input correctly; `noise_xk.nova` accepted it and produced
the wrong digest.

The pattern generalises beyond SHA-256: HMAC, P-256 ECDSA, AES-GCM,
X.509 parsing all face the same risk. As the federation stack landed
(R30C / R31B / R32B / R33B / R34B / R34C / R35A / R35B / R35D), the
risk multiplied: each new wire module wanted its own crypto helpers,
and "just copy from the other module" became the path of least
resistance.

## Decision
**Crypto primitives are centralised under `src/safety/`.** Each primitive
gets one and only one canonical NOVA module:

  - `safety/sha256.nova` -- the canonical SHA-256 (R33A consolidation).
  - `safety/hmac_sha256.nova` -- HMAC keyed on top of `sha256.nova`.
  - `safety/p256.nova` -- canonical P-256 point math + ECDSA.
  - `safety/aes_gcm.nova` -- canonical AES-GCM.
  - `safety/aes_cm.nova` (R34C) -- AES-CM-128 for SRTP.
  - `safety/x509.nova` -- canonical X.509 parser.
  - `safety/p384.nova`, `safety/ed25519.nova`, etc. -- additional
    primitives ship as separate canonical modules when needed.

**Consuming modules import the canonical leaves and do not maintain
their own copies.** Specifically:

  - `src/federation/dtls12.nova` imports `safety/sha256.nova` for
    transcript hashing (R34A dedup).
  - `src/federation/srtp.nova` imports `safety/aes_cm.nova` (R34C) and
    `safety/hmac_sha1.nova` (R34C).
  - `src/safety/noise_xk.nova`, `safety/merkle.nova`,
    `safety/ecdsa.nova` import `safety/sha256.nova` (R33A).

The canonical leaves expose a small public API (typically:
`<algo>_init(state)`, `<algo>_update(state, bytes)`,
`<algo>_finalize(state) -> digest`). Consumers do not poke into
internal slots.

## Consequences
**Positive.**
  - **Bug-fix symmetry.** A constant-time padding bug fix to
    `safety/sha256.nova` lands once and is consumed by all five
    callers transparently.
  - **Audit cost is bounded.** Per-algorithm audit happens once per
    canonical leaf, not once per (algorithm, caller) pair.
  - **NOVA import graph stays acyclic and leaf-shaped under safety/.**
    `safety/sha256.nova` imports nothing (just syscalls); every other
    safety/ leaf imports `sha256.nova` only forward.
  - **R34A dedup pattern is repeatable.** When a future round needs
    SHA-512 in two places, the pattern says "ship one canonical
    `safety/sha512.nova`, point both consumers at it" without
    rediscussion.

**Negative.**
  - **Consumer modules pay a one-time refactor cost.** R33A spent a
    full round consolidating four inline SHA-256 copies into the
    canonical leaf. R34A repeated for the federation surface. We
    accepted this upfront cost in exchange for asymptotic maintenance
    saving.
  - **API drift risk.** If `safety/sha256.nova` ever wants to change
    its public surface, all consumers must update. We mitigate by
    making the public surface small (3 functions) and stable.

**Follow-up rounds.**
  - R37+: when a new federation crypto primitive is needed, the round
    plan must specify "land canonical leaf first, then consumer" in
    that order, not the reverse.
  - The pattern extends to non-crypto utilities (base64, base32, hex)
    -- these already live as canonical leaves under
    `src/safety/encoding/` and follow the same discipline.

## Alternatives considered
  - **Per-module inline copies (status quo before R33A).** Rejected:
    bug-fix asymmetry was already biting at R29B.
  - **Vendored OpenSSL bindings.** Rejected: per ADR R36F-0001, we
    don't ship libc-linked binaries, and OpenSSL's API surface is
    much larger than the small public surface we actually need.
  - **NOVA standard library extension.** Considered; rejected for v1
    because the NOVA stdlib is intentionally small (NOVA ADR
    R36F-0001 covers this). CrossEngin's `src/safety/` is the
    application-side canonical home.

## R33A as a worked example
The R33A round did this in three commits:
  1. Land `safety/sha256.nova` as the canonical leaf, with tests.
  2. Refactor `noise_xk.nova` / `merkle.nova` / `ecdsa.nova` to import
     the canonical leaf. All prior tests still pass.
  3. Delete the inline SHA-256 copies. Net -300 lines.

R34A repeated the pattern for `dtls12.nova`'s SHA-256. Same shape:
land, refactor, delete. The pattern is the load-bearing piece, not
SHA-256 specifically.
