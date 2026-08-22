# ADR-0105: Sandbox Architecture — capability separation, TLS, signed skill install

**Title note (post-vision-alignment):** This ADR covers the
ACCESS-CONTROL sandbox (capability tokens + ownership overlay). The
COGNITIVE sandbox (the mind, where learning + agent production +
answering happens) is a separate concept covered by ADR-0202.

## Status

Proposed (R54 delivers capability tokens + verb-cap map; TLS + signed
skill install are R54.1 / R54.2, scoped here so the design is one piece)

## Date

2026-08-15

## Context

R49–R51 shipped the JSON-RPC daemon + web shim. Both are loopback-
default and documented as "the socket is the auth boundary." Fine
for a single-user local deployment. NOT fine for anything else:

- Multi-user shared box: any local user can `nc 127.0.0.1 9876`
  and drive skills as if they were the owner
- LAN deployment (via `CE_RPC_BIND_ALLOW_NON_LOOPBACK=1`): anyone
  on the network can dispatch skills that touch files, run
  processes, or spend network budget
- Skill install (`skill.install` verb) currently lets any caller
  register any manifest — a malicious skill running in-process
  is arbitrary code execution
- Ingest verbs (`ingest.approve`, `ingest.deny`) can mint atoms
  no one asked for
- Persona reads (`persona.show`, `persona.project`) leak per-user
  state to whoever holds the socket

ADR-0109 (ship-as-app) called this out as the "R54 sandbox" work.
This ADR is that work.

## Decision

Three layered mechanisms:

1. **Capability tokens** (R54, this ship) — every wire request
   MUST carry a token when the daemon is in enforced mode; the
   token names the caller's holder + a set of granular
   capabilities; verbs check their required capability against
   the token's grant set before dispatch
2. **Transport TLS** (R54.1, documented here) — encrypt the wire.
   Approach: sidecar (stunnel / nginx) in front of the daemon
   for R54, in-process TLS in R55+ once NOVA's TLS integration
   matures beyond the current federation experiments
3. **Signed skill install** (R54.2, documented here) — every
   `skill.install` verb requires a signature over the manifest,
   verified against a trust-anchor list; installs of unsigned or
   untrusted-signed skills refuse cleanly

Each layer is independent. A deployment can run any subset. A
single-user local box runs zero of them (backward compatible with
R49/R50); a shared-box deployment runs capabilities; a LAN
deployment adds TLS; a marketplace deployment adds signed
installs.

### Capability model (v1, R54 ship)

A **Capability** is a namespaced permission string:

```
nl:ask            can call nl.ask + nl.parse_only
kg:read           can call kg.list
capsule:read      can call capsule.list
capsule:install   can call capsule.install
skill:read        can call skill.list
skill:run         can call skill.run
skill:install     can call skill.install (deferred to R54.2)
persona:read      can call persona.show + persona.project
persona:write     can call future persona.set_* verbs
ingest:review     can call ingest.review
ingest:decide     can call ingest.approve + ingest.deny
```

A **Token** is:

```
Token = [
  token_id:   opaque string (128-bit random, hex-encoded)
  holder:     string (user_id / service name; free-form)
  capabilities: list<string>
  issued_at:  int (moment)
  expires_at: int (moment; 0 = never expires)
  revoked:    0/1
]
```

Verbs declare their required capability via a fixed
`verb → required_cap` table (in `src/sandbox/capability.nova`).
`rpc_verbs.rpc_dispatch` consults the table BEFORE dispatching;
requests without the required cap yield
`{ok:false, error:"capability required: <cap>"}`.

**Built-in roles** as convenience bundles:

- `admin`         — every capability
- `reader`        — nl:ask, kg:read, capsule:read, skill:read, persona:read
- `skill_user`    — reader + skill:run
- `curator`       — reader + capsule:install + ingest:*
- `service`       — nl:ask + skill:run (typical "chat frontend" wire client)

Tokens are minted via `capability_token_new(holder, roles, expires_at)`.
Roles expand to their capability set at mint time (a token holds
capabilities, not roles — so revoking a role from a role definition
does not silently downgrade in-flight tokens).

### Enforcement mode

`CE_RPC_REQUIRE_TOKEN=1` — daemon requires every request to include
a `"token"` field naming a live token. Absent / expired / revoked
/ under-capabilised → structured refusal (never 500). Default `0`
(off) keeps R49/R50 wire behavior byte-identical.

### Token issuance

A future `capability.issue` wire verb would let an `admin` token
mint child tokens. For R54 the daemon exposes a simple
**bootstrap admin token** at boot time (path via
`CE_RPC_ADMIN_TOKEN_FILE`) so the operator can seed the first
token from process start. R55+ layers issuance verbs on top.

### Transport TLS (R54.1)

Approach: **stunnel sidecar in front of `crossengin-rpc-daemon`**.
The daemon stays TLS-unaware; stunnel handles the certificate,
the TLS handshake, and forwards decrypted bytes to the daemon on
loopback. This decouples TLS from NOVA and reuses a battle-tested
implementation while the in-process TLS story matures.

Recipe (documented in `docs/SHIP_AS_APP.md`):

```
[crossengin-tls]
accept  = 0.0.0.0:9977
connect = 127.0.0.1:9876
cert    = /etc/crossengin/server.pem
key     = /etc/crossengin/server.key
```

Clients speak TLS to :9977; stunnel forwards to the daemon on
:9876. Combined with `CE_RPC_REQUIRE_TOKEN=1`, this covers the
"LAN deployment" story.

**Deferred to R55+ (in-process TLS):** integrating the
`src/federation/*` TLS layer directly into `crossengin_rpc_daemon`
so the sidecar isn't required. NOVA's TLS is functional (ADR-0074,
ADR-0086) but the socket-integration story wants a round of
smoothing before it's the default.

### Signed skill install (R54.2)

Motivating case: a marketplace of skills where users install by
name. Trust boundary: the manifest + policy id must come from a
verified source.

Shape:

```
SkillPackage = {
  manifest:     SkillManifest
  policy_body:  string (identifies the built-in policy id or an
                        eventual bytecode reference)
  signature:    ed25519 signature over serialized(manifest + policy)
  signer_pk:    ed25519 public key of the author
}
```

`skill.install` verb (R54.2 change):
- If the daemon has a `trust_anchors` list, require `signer_pk` to
  be in the list (direct trust) OR chained under an anchor
- Verify signature; refuse on mismatch
- On success, install the manifest as usual (existing
  `skill_registry_install` path)

Existing built-in skills (echo, research, coding_helper) count as
**pre-anchored**: their manifests are compiled into the daemon
binary; no signature needed. External skill packages get the
signature check.

Deferred: bytecode / policy reference story. R54.2 only signs the
manifest (name, version, deps, effectors, refusal conditions) —
so a signed manifest limits WHAT a skill can do without proving
HOW the code implements it. Real bytecode signing waits on a
NOVA-side policy-loading story.

### The 5 ADR-0103 guarantees, preserved

Sandbox layers ADD enforcement; they never RELAX ADR-0103:

1. Refusals still short-circuit — capability refusals are a
   NEW refusal class (`capability required: <cap>`), served
   BEFORE the skill_run path is entered
2. Projection presence unchanged — if a capability refusal
   fires, no projection is computed (nothing ran)
3. Effectors still described-not-executed — capabilities gate
   dispatch; effector semantics stay identical downstream
4. Meta-observer attribution unchanged — the token's `holder`
   is added as an ADDITIONAL parser-side tag on any observation
   the request creates (`src:token:<holder>`), distinct from
   `src:skill:*` and `src:pattern:*`
5. Persona read-only — capability gate can DENY reads
   (`persona.read` cap absent), never MUTATE

## Options Considered

1. **Capability tokens (CHOSEN).** Namespaced grants + expiring
   opaque bearer tokens. Simple wire integration; audit-friendly.
2. **mTLS client certificates.** More secure but adds cert-issuing
   machinery + per-client PKI. Overkill for the primary case
   (single-user + trusted-collaborators). Layered on top via
   R54.1 stunnel if wanted.
3. **OAuth 2.0.** Standard but heavy. Requires an authorization
   server + JWT signing + token refresh. Rejected: CrossEngin is
   local-first; a full OAuth stack is optimising for a
   deployment shape we haven't chosen.
4. **Unix socket + SO_PEERCRED.** Great for local separation.
   Rejected: cross-platform story is weaker (Windows kernel
   supports AF_UNIX but tooling is uneven), and we already bind
   TCP for the web shim.
5. **Per-verb allowlist by IP.** Coarse. Rejected: doesn't
   distinguish between two users on the same host.

## Consequences

- **Positive:** A shared-box deployment gains real per-user
  separation with minimal ceremony: `CE_RPC_ADMIN_TOKEN_FILE`
  seeds one admin, admin mints per-user tokens, done.
- **Positive:** Enforcement mode is a single env flag; the
  default remains backward-compatible so no existing operator
  workflow breaks.
- **Positive:** Sidecar TLS (R54.1) reuses stunnel/nginx and
  requires zero NOVA-side change.
- **Positive:** Capability grants are the natural place to
  attach RATE LIMITS (R55+): each cap can carry a `qps_max`
  field, decrementing per request.
- **Neutral:** Adds ~500 lines under `src/sandbox/`.
- **Negative:** Bootstrap admin token needs safe seeding. The
  file-based bootstrap (`CE_RPC_ADMIN_TOKEN_FILE`) is
  operator-permissioned; a mis-permissioned file is a leak.
  Documented in `docs/SHIP_AS_APP.md`.
- **Negative:** Tokens are bearer credentials. Anyone who
  intercepts one is that principal. TLS (R54.1) mitigates
  transport; storage is on the operator.
- **Negative:** Signed skill install (R54.2) adds a signing
  toolchain to the author's workflow. For R54 the built-ins
  are pre-anchored; only external skills need the workflow.

## Ship-as-app checklist for R54

- [x] ADR-0105 (this document)
- [x] `src/sandbox/capability.nova` — Capability + Token +
      TokenRegistry + verb→cap map + built-in roles
- [x] rpc_verbs.rpc_dispatch consults the token when
      `CE_RPC_REQUIRE_TOKEN=1`; unenforced when off
- [x] Bootstrap admin token via `CE_RPC_ADMIN_TOKEN_FILE`
- [x] Tests: capability + token + verb-gate + role expansion +
      bootstrap
- [x] All prior tests unchanged (backward compatible when the
      env flag is off)

## Deferred → shipped

- **R54.1 — TLS sidecar recipe** ✅ shipped:
  * `scripts/gen_tls_cert.sh` — one-shot self-signed cert
    generator (ed25519 preferred; RSA fallback; SAN + fingerprint)
  * `infra/tls/stunnel.rpc.conf.example` — reference stunnel conf
    (TLS 1.2+, modern ciphers, foreground/log/pid/setuid)
  * `infra/tls/nginx.rpc.conf.example` — reference nginx `stream`
    conf (raw-TCP forward, TLS termination on :9977)
  * `docs/DEPLOY_TLS.md` — 7-section operator manual:
    when-you-need-this, threat model, cert generation, sidecar
    setup, daemon boot with loopback-only bind, client examples
    (openssl s_client + Python stdlib + fingerprint pinning),
    Let's Encrypt for public deployments, verification steps, R55+
    replacement path

- **R54.2 — Signed skill install** ✅ shipped:
  * `src/sandbox/skill_signature.nova` — SkillPackage type wrapping
    a manifest + ed25519 signature + signer_pk; canonicalizer
    (`crossengin-skill-manifest-v1` versioned + fixed field order
    for reproducibility); sha256 pre-hash before ed25519 (32-byte
    input shape); trust-anchor registry (direct trust list,
    add/remove/trusts, byte-list equality); `skill_pkg_authorize`
    gate composed uniformly with `capability_authorize` (both
    return "" on OK for clean chaining); `skill_pkg_source_tag`
    fingerprint (first-8-bytes hex) for meta_observer audit.
  * `tests/unit/test_skill_signature.nova` (50 checks) covering
    canonicalization determinism, hash stability, sign/verify
    roundtrip, tamper detection (manifest / signature / pubkey
    all swapped), trust-anchor lifecycle, authorize gate
    (off / null pkg / null reg / bad sig / untrusted signer /
    happy path), source-tag shape.
  * The RPC-layer wiring (skill.install verb consulting the
    trust anchors when CE_RPC_REQUIRE_SIGNED_SKILL=1) is a
    follow-up: the primitive lands here; the daemon flag +
    verb integration is a small change on top when a shop
    actually wants marketplace-shaped installs.

## Still deferred

- **R55 — Multi-user daemon** (session slots per token holder,
  per-session DP accounting, snapshot round-trip via wire,
  `capability.issue` verb so admin can mint child tokens
  over the wire instead of via a small in-process program)
- **R56+ — Rate limits per capability**, in-process TLS
  (retires the sidecar recipe), hardware-key-backed admin
  bootstrap

## Role in the Model Substrate

The access-control sandbox this ADR defines gates every consumption
mode that exposes a wire — mother-daemon-direct (mode 1) when the
mother is multi-user, per-user selective-load (mode 2) where every
holder needs its own capability grant, client-app (mode 4) where
the frontend authenticates over the RPC surface, and long-horizon
embedded (mode 5) where a device holds a scoped token to its
owner's mother. Baked-child instances (mode 3) inherit this layer
whole and bind it to the child-appropriate verb subset.

This ADR is NOT part of the reasoning triad. It is a perimeter
around the substrate — capability tokens, transport TLS, signed
skill install — that keeps unauthorized callers out and audit
tags on every request that gets in. The cognitive sandbox where
reasoning actually happens is a separate concept (ADR-0202); the
name "sandbox" is shared but the scopes are disjoint. Keeping the
two straight is what lets the mother/child factory (ADR-0200) ship
children that are safe on customer infra without conflating "the
mind" with "the socket."

**See also:** ADR-0202 (cognitive sandbox — the mind, distinct
from this access-control perimeter), ADR-0207 (bake manifest —
capability grants baked into a child), ADR-0209 (signed child
bundle — extends R54.2's signature pattern to whole bundles),
ADR-0200 (five consumption modes — this perimeter gates each mode
that exposes a wire).
