# ADR-0109: Ship as App — packaging, distribution, and the daemon story

## Status

Proposed (R50)

## Date

2026-08-15

## Context

R44 through R49 built the technical stack:

- R44 (packs) — .cerec importer + real domain packs (solar_system,
  physics, world_history, religion, politics, biology,
  folk_astronomy)
- R45 (Capsules, ADR-0106) — shareable, versioned bundles of atoms
- R46 (Persona, ADR-0102) — per-user, advise-only projection
- R47 (Skill Runtime, ADR-0103) — the 5-guarantee invocation
  contract every reasoning path funnels through
- R48 (NL Surface, ADR-0104) — grammar-first + LLM-preprocessor
  parser + deterministic templater
- R49 (JSON-RPC daemon) — `crossengin-rpc-daemon` binds a TCP
  socket and serves the 12 verbs any client can speak

That's a runnable engine. It is NOT yet an app. The gap between
"working `bin/crossengin*` binaries in a source checkout" and
"someone downloads a thing and uses it" is what R50 closes.

The user's vision from R45 was explicit: **ship this as
something that behaves like Claude / ChatGPT to a non-technical
user, but with CrossEngin's actual differentiators (auditable
reasoning, source-cited answers, per-user persona projection,
LLM-free reasoning path)**. Not "publish a Python package." Not
"a REST API for developers." An **app**.

## Decision

Package CrossEngin as a **single-host self-contained deployment**
with a **daemon-plus-client** shape. The daemon is
`crossengin-rpc-daemon` (R49). Clients are anything that can speak
line-oriented JSON over TCP: a shell script (`scripts/rpc.sh`),
`curl`, an eventual web UI, an eventual mobile app, an IDE
extension. Text UI (`crossengin-chat`) remains for power users
and operators; it is not the primary user surface.

R50 delivers the **operator scaffold**: what someone runs to get
from a fresh checkout to a running daemon serving live traffic.
R51+ (future) delivers user surfaces (web app, mobile).

### Deliverables in scope for R50

1. **`ADR-0109` (this document)** — decision + roadmap
2. **`Makefile install` extension** — `bin/crossengin-rpc-daemon`
   built alongside the existing set
3. **`Makefile cross-windows`** — Windows cross-compile pairs
   include the RPC daemon
4. **`scripts/rpc_daemon.sh`** — launcher with sensible defaults
   (port, bind IP, log level) + safe-mode preflight
5. **`scripts/rpc.sh`** — one-shot client:
   `./scripts/rpc.sh nl.ask '{"text":"what is mars"}'`
6. **`scripts/preload.sh`** — pack + skill preload:
   drives `capsule.install` + `skill.install` for the built-in
   packs and reference skills so a fresh daemon isn't empty
7. **`docs/SHIP_AS_APP.md`** — operator manual: install → boot
   daemon → preload → hit with client → verify → next steps

### Deliverables added in R51

- **Web UI shipped** (`web/index.html` + `web/app.js` +
  `web/styles.css`) + Python 3 HTTP shim
  (`scripts/rpc_web_shim.py`) that forwards `POST /rpc/<verb>` to
  the TCP daemon. Launcher: `scripts/serve_web.sh`. Renders
  templated answers with source chips + disagreement callouts +
  persona projection + effector-calls (described, not executed) +
  parse-debug panel. Loopback default, path-traversal blocked,
  wire-verb allowlist at the shim. Stdlib-only Python; no npm,
  no bundler.

### Deliverables deferred to R52+

- WebSocket streaming (current R51 shim is request/response only;
  a streaming variant would let long-running skill runs push
  progress)
- Mobile app (native shell wrapping a WebView + the same wire)
- Distributable installers (deb / rpm / brew / MSI); the current
  cross-windows `.exe` build is a foundation but not a signed
  installer
- Multi-user daemon (session slots, per-user isolation, DP
  accounting on wire calls). The R49 daemon serves ONE process's
  RpcContext -- a family / small-team deployment picks up here
- Snapshot/restore integration (a wire verb `session.save` /
  `session.load`; the chat REPL has this today, the daemon does
  not)
- Systemd unit / launchd plist / Windows service wrapper
- TLS on the RPC socket (deferred to the sandbox ADR-0105 work
  which will layer capability separation on top)

### Non-goals for R50

- **We do NOT ship a hosted service.** The whole point is
  local-first: your persona, your knowledge, your skills stay on
  your machine. A hosted-CrossEngin story would need distinct
  privacy commitments and is out of scope.
- **We do NOT ship a package repository.** Anyone can clone the
  repo and `make install`. Distribution to arbitrary users
  through a package manager is future work.
- **We do NOT wire an LLM by default.** The
  `scripts/nl_parse_llm.sh` LLM-preprocessor is available for
  power users who want the fallback parser, but the daemon runs
  100% LLM-free out of the box.

### Deployment shapes R50 supports

| Shape | Who | Command |
|---|---|---|
| Text REPL (existing) | Operators, authors, debuggers | `./bin/crossengin-chat` |
| Local daemon (new) | Power users, script-driven workflows | `./scripts/rpc_daemon.sh` |
| Docker (recipe in docs) | Small deployments, home lab | `docker build && docker run` |
| Windows binary | Non-technical users on Windows | `make cross-windows`; run `bin/crossengin-rpc-daemon.exe` |

### Wire compatibility promise

The 12 verbs documented in ADR-0104 §Component 5 are STABLE. A
client written today against R49's daemon will work against every
future R50+ daemon. Adding verbs is additive; renaming or
changing arg shapes requires a version bump and a deprecation
window (min 2 release cycles).

The wire envelope `{ok, result, error}` is fixed. Correlation ids
are optional (echoed if present). Line-oriented framing (one JSON
per line) is the default; a future WebSocket bridge preserves the
same envelope.

### The 5 ADR-0103 guarantees, preserved end-to-end

The daemon inherits these unchanged — every verb funnels through
the same `skill_run` / `nl_execute` / templater stack the chat REPL
uses:

| Guarantee | Where enforced |
|---|---|
| 1. Refusals short-circuit BEFORE policy | `skill_run` inside verb impls |
| 2. Projection ALWAYS attached | executor never strips; encoder surfaces it |
| 3. Effectors DESCRIBED not executed | templater / rpc_verbs encoder |
| 4. Meta-observer attribution | `skill_run` handles; parser tag added by rpc_verbs |
| 5. Persona READ-ONLY | passed by ref; encoder only reads |

## Options Considered

1. **Daemon-plus-client, TCP + JSON line protocol (CHOSEN).**
   Language-agnostic, works with `curl`, `nc`, `jq`, native
   sockets. Same wire from CLI, web, mobile. Trivial to log +
   audit + tee for testing.
2. **HTTP/REST.** More client-friendly. Rejected for R50: adds
   headers/auth/verb-mapping complexity for what is a single-user
   local daemon. R51 can layer HTTP on top (same envelope, one
   endpoint per verb) if a web client benefits.
3. **Unix socket only.** More secure by default. Rejected: cross-
   platform story is worse (Windows has AF_UNIX in recent
   builds but the tooling story is uneven). TCP-on-loopback is
   the pragmatic default; a `CE_RPC_UNIX_SOCKET` env var can
   layer AF_UNIX later.
4. **gRPC.** Well-typed. Rejected: adds protobuf toolchain to the
   user's install path. NOVA-side gRPC would be a large build.
5. **Single-binary chat that IS the daemon.** Simpler
   deployment. Rejected: the chat REPL's cognition loop runs
   per-turn work (auto-research, teach queue) that would delay
   RPC requests. Separate binaries let each be tuned.

## Consequences

- **Positive:** Anyone with a NOVA toolchain can `make install`
  and get a runnable daemon in minutes. No Python, no Node, no
  container runtime required.
- **Positive:** The wire is stable enough to write a client
  against today. A hobbyist can ship a browser extension /
  Alfred workflow / Raycast plugin using the R49 wire without
  waiting for R51.
- **Positive:** The chat REPL is unchanged. Existing operators
  keep their workflow.
- **Positive:** The Windows cross-compile story means a
  non-technical user on Windows can get a working `.exe` from a
  Linux CI, no MSVC install required.
- **Neutral:** Ship-as-app is a story about scaffolding, not new
  cognition. R50 adds ~500 lines of shell + docs and touches the
  Makefile; no NOVA source changes beyond the R49 daemon (already
  committed).
- **Negative:** Serial accept loop in R49's daemon means one
  request at a time. Fine for a single user; a family deployment
  will want concurrency (R51+).
- **Negative:** No TLS on the socket. Loopback default is safe
  for local use; a LAN deployment MUST NOT flip `CE_RPC_BIND` to
  `0.0.0.0` without adding TLS. The daemon prints a warning at
  boot when bind is non-loopback.
- **Negative:** Preload script is bash. Windows users need WSL
  or a `preload.ps1` (deferred). The daemon itself is native
  Windows; only the boot scaffold is Unix-first.

## Roadmap after R51

- **R52** — Style Capsules (ADR-0108 implementation): personas
  can pick a rendering style; templater consults the capsule
- **R53** — Pattern Capsules (ADR-0107 implementation): skills
  can compose learned patterns via named capsules
- **R54** — Sandbox architecture (ADR-0105): capability
  separation for the daemon; TLS on RPC; user-signed skill install
- **R55** — Multi-user daemon: session slots per user, DP
  accounting per session, snapshot round-trip via wire

## Ship-as-app checklist for R50

A release ships when:

- [x] `make install` builds `bin/crossengin-rpc-daemon`
- [x] `make cross-windows` builds `bin/crossengin-rpc-daemon.exe`
- [x] `scripts/rpc_daemon.sh` boots the daemon with defaults
- [x] `scripts/rpc.sh` hits a running daemon with a verb
- [x] `scripts/preload.sh` installs the reference skills
- [x] `docs/SHIP_AS_APP.md` walks a new operator through the
      install → run → verify path
- [x] The RPC wire behaves per ADR-0104 §Component 5

Nothing here is speculative — every deliverable is a small,
verifiable change on top of R49.
