# Ship as App — CrossEngin operator manual (R50, ADR-0109)

This document walks a new operator from a fresh checkout to a running
CrossEngin JSON-RPC daemon serving live requests.

CrossEngin ships as a **local daemon + client** pair. The daemon
(`crossengin-rpc-daemon`) binds a TCP socket and serves 12 stable
verbs. Any client that can speak line-oriented JSON over TCP can
drive it — `curl`, `nc`, a shell script, a native app, a browser
extension. The reference client is `scripts/rpc.sh`.

The design lives in [`ADR-0109 Ship as App`](adr/0109-ship-as-app.md).
The wire is documented in [`ADR-0104 §Component 5`](adr/0104-nl-surface.md).

## 1. Prerequisites

- Linux, macOS, or Windows (via WSL for the launcher scripts;
  the daemon binary itself runs native Windows via
  `make cross-windows`)
- A working NOVA toolchain at `$NOVA_ROOT` (default `~/NOVA`).
  See [`docs/GETTING_STARTED.md`](GETTING_STARTED.md) for the
  NOVA install.
- `bash`, `printf`, `nc` (or Bash 4+ with `/dev/tcp` support) —
  present on every modern Unix. No Python, Node, jq, or Docker
  required.

## 2. Build

From the repo root:

```bash
make install
```

Builds every implemented entry point into `./bin/`:

```
bin/crossengin                 (unified cognitive daemon, existing)
bin/crossengin-chat            (interactive REPL, existing)
bin/crossengin-rpc-daemon      (JSON-RPC daemon, new in R49)
bin/crossengin-selfcheck       (substrate self-check)
bin/crossengin-spine           (companion-spine demo)
bin/crossengin-kg-publisher    (kg_sync publisher, existing)
bin/crossengin-kg-subscriber   (kg_sync subscriber, existing)
bin/crossengin-fed-coordinator (federation coordinator, existing)
```

Cross-compile for Windows:

```bash
make cross-windows
# produces bin/*.exe including bin/crossengin-rpc-daemon.exe
```

## 3. Boot the daemon

```bash
scripts/rpc_daemon.sh
```

Defaults: loopback `127.0.0.1`, port `9876`. Override with env:

```bash
CE_RPC_PORT=19876                     scripts/rpc_daemon.sh
CE_RPC_BIND=192.168.1.10 \
  CE_RPC_BIND_ALLOW_NON_LOOPBACK=1    scripts/rpc_daemon.sh
```

The launcher refuses to bind non-loopback without the explicit
`CE_RPC_BIND_ALLOW_NON_LOOPBACK=1` flag. **Do not flip that flag on a
network you don't fully control** — the RPC wire executes named
skills, so exposing it is roughly equivalent to opening a
shell-command port. TLS on the RPC socket is deferred to R54
(sandbox architecture, ADR-0105); until then, treat non-loopback
as "SSH tunnel only" or wrap in a `stunnel`.

Expected output:

```
=== CrossEngin JSON-RPC daemon ===
binary: ./bin/crossengin-rpc-daemon
endpoint: 127.0.0.1:9876
hit with:  scripts/rpc.sh <verb> '<args-json>'
example:   scripts/rpc.sh nl.ask '{"text":"what is mars","user_id":"owner"}'

=== CrossEngin JSON-RPC (line-oriented; one JSON request per line; 12 verbs; envelope {ok, result, error}; ADR-0104) ===
listening on 127.0.0.1:9876  (max_request=65536 bytes)
```

## 4. Preload the reference skills

In another terminal:

```bash
scripts/preload.sh
```

Installs the reference skills (`echo`, `research`) so `nl.ask` works
on the first request. Output:

```
=== CrossEngin preload (daemon at 127.0.0.1:9876) ===
  install skill: echo                       OK
  install skill: research                   OK

  daemon inventory:
    KGs      : {"ok":true,"result":["world"],"error":""}
    skills   : {"ok":true,"result":[...],"error":""}
    capsules : {"ok":true,"result":[],"error":""}
preload done.
```

## 5. Hit the wire

```bash
# Parse-only debug (LLM-free grammar, deterministic):
scripts/rpc.sh nl.parse_only '{"text":"is earth a planet"}'
```

```json
{"ok":true,"result":{"kind":"is-a","raw_text":"is earth a planet","parser_used":"grammar","args":["earth","planet"]},"error":""}
```

```bash
# Full end-to-end (parse + skill run + templater):
scripts/rpc.sh nl.ask '{"text":"what is mars","user_id":"owner"}'
```

The `result` contains a full ExecutionResult including the templated
English answer with source citations, plus the underlying atoms and
persona projection for auditability.

```bash
# Pretty-print with jq:
CE_RPC_JQ=1 scripts/rpc.sh nl.ask '{"text":"what is mars","user_id":"owner"}'
```

## 6. Verify the ship-as-app promise

The five things that make CrossEngin different from an LLM chatbot,
verifiable via the wire:

| Property | Verify |
|---|---|
| **Auditable parse** | `nl.parse_only` returns the exact StructuredQuery |
| **Source-cited answers** | `nl.ask` result includes `atoms[]` with `[kg, label, belief]` per source |
| **LLM-free reasoning path** | Daemon prints no LLM calls; `parser_used` is `"grammar"` |
| **Persona is advise-only** | `persona.project` returns raw `valence_shift`/`risk_score`, never overrides |
| **Effectors described, not executed** | `nl.ask` result's `proposal.effector_calls[]` names planned actions; nothing dispatches |

## 7. The 12 verbs at a glance

| Verb | Args | Returns |
|---|---|---|
| `nl.ask` | `{text, user_id}` | full ExecutionResult with templated English answer |
| `nl.parse_only` | `{text}` | StructuredQuery only (for debugging what the grammar saw) |
| `kg.list` | `{}` | list of KG label names |
| `capsule.list` | `{}` | list of `{name, version, installed}` |
| `capsule.install` | `{name}` | `{name, code, installed}` |
| `skill.list` | `{}` | list of `{name, version, description, installed}` |
| `skill.run` | `{name, arg}` | ProposalResult (proposal, atoms, effector_calls, projection, trace) |
| `persona.show` | `{user_id}` | full persona record (OCEAN, emotion, risk, counts) |
| `persona.project` | `{user_id, proposal}` | Projection (valence_shift, arousal_shift, risk_score, similar/pref counts) |
| `ingest.review` | `{}` | review-queue entries |
| `ingest.approve` | `{id}` | approve status |
| `ingest.deny` | `{id, reason}` | deny status |

Wire envelope for every response:

```json
{"ok": true, "result": <verb-specific>, "error": ""}
{"ok": false, "result": null, "error": "..."}
```

Requests may carry an optional `"id"` field (number, string, or null)
that the daemon echoes verbatim for client-side correlation.

## 7.5 Web UI (R51, browser-shaped)

For a browser-facing surface, run the shim + open the SPA:

```bash
# Terminal 1: daemon (as in section 3)
scripts/rpc_daemon.sh

# Terminal 2: web shim (Python 3 stdlib, no pip install)
scripts/serve_web.sh
# -> listening on http://127.0.0.1:8080/
```

Then open [http://127.0.0.1:8080/](http://127.0.0.1:8080/) in a browser.

The UI:

- **Ask box** — free-text question, submit runs `nl.ask` end-to-end
- **Parse only** button — runs `nl.parse_only`, shows what the
  grammar understood without invoking a skill (useful for debugging
  phrasing coverage)
- **Answer** — the templated English answer from the templater
- **Sources cited** — every atom the skill leaned on, tagged with
  its KG label + belief mean
- **⚠ Sources disagree** — surfaced automatically when the same
  label appears in 2+ KGs with belief spread ≥ 300 milli (matches
  the templater's disagreement threshold)
- **Persona projection** — the advise-only projection, marked so
  operators know it never overrides
- **Effector calls** — described, not executed (safety guarantee 3)
- **Parse debug** — the underlying `StructuredQuery`
- **Raw JSON-RPC response** — the exact wire envelope, for
  transparency + client debugging
- **Side panels** — live inventory of installed skills + KGs

The shim serves static files from `web/` and routes `POST
/rpc/<verb>` requests to the TCP daemon. Endpoint allowlist matches
the 12 wire verbs; unknown verbs 400 out at the shim (not forwarded).
Path traversal (`../`) is blocked at the resolve step. Loopback
default; non-loopback bind requires `CE_WEB_BIND_ALLOW_NON_LOOPBACK=1`.

Env vars the shim honors:

```
CE_WEB_PORT       (default 8080)          shim's HTTP port
CE_WEB_BIND       (default 127.0.0.1)     shim's bind IP
CE_WEB_BIND_ALLOW_NON_LOOPBACK  "1" to bind LAN (see security posture)
CE_RPC_HOST       (default 127.0.0.1)     TCP daemon host
CE_RPC_PORT       (default 9876)          TCP daemon port
CE_WEB_ROOT       (default <repo>/web)    static-file root
CE_WEB_TIMEOUT_S  (default 30)            per-request daemon timeout
```

`GET /healthz` returns `ok` if the shim is up (does not check the
daemon; use `POST /rpc/kg.list` for a live health probe).

The whole thing is ~350 lines of Python + 250 lines of HTML/CSS/JS.
There is no build step, no bundler, no framework. Distribution is
"clone the repo, run two scripts."

## 7.7 Sandbox / capability tokens (R54, ADR-0105)

For anything beyond single-user local, enable capability enforcement:

```bash
# Generate a fresh 128-bit token id and store it 0600.
head -c 16 /dev/urandom | xxd -p > ~/.crossengin/admin.token
chmod 600 ~/.crossengin/admin.token

CE_RPC_REQUIRE_TOKEN=1 \
CE_RPC_ADMIN_TOKEN_FILE=~/.crossengin/admin.token \
scripts/rpc_daemon.sh
```

The daemon boots with an admin token loaded, refuses any request
that doesn't carry a live token. Clients pass the token via the
request's `"token"` field; `scripts/rpc.sh` reads
`CE_RPC_TOKEN` and injects it:

```bash
export CE_RPC_TOKEN=$(cat ~/.crossengin/admin.token)
scripts/rpc.sh nl.ask '{"text":"what is mars","user_id":"owner"}'
```

Capabilities are namespaced permissions:
`nl:ask`, `kg:read`, `capsule:read`, `capsule:install`, `skill:read`,
`skill:run`, `skill:install`, `persona:read`, `persona:write`,
`ingest:review`, `ingest:decide`. The daemon's verb-to-cap table
lives in `src/sandbox/capability.nova` — every verb declares exactly
one required capability.

Built-in **roles** bundle common capability sets: `admin` (all),
`reader` (read-only), `skill_user` (reader + skill:run), `curator`
(reader + capsule:install + ingest), `service` (nl:ask + skill:run).

**R55 wire verbs** let an admin token mint / revoke / list child
tokens over the wire (no in-process program needed):

```bash
# Mint alice a skill_user token that expires at moment 100000.
CE_RPC_TOKEN=$(cat ~/.crossengin/admin.token) \
scripts/rpc.sh capability.issue \
  '{"holder":"alice","roles":"skill_user","expires_at":"100000"}'
# -> {"ok":true,"result":{"token_id":"...","holder":"alice",
#      "caps":["nl:ask","kg:read","capsule:read","skill:read",
#              "persona:read","skill:run"],
#      "issued_at":..., "expires_at":100000}}

# Alice's client sets that id as its CE_RPC_TOKEN and can now
# call nl.ask + skill.run but not skill.install or capability.*.

# Revoke alice's token immediately.
CE_RPC_TOKEN=$(cat ~/.crossengin/admin.token) \
scripts/rpc.sh capability.revoke '{"token_id":"..."}'

# Audit -- list every live token (holder + caps + expiry only;
# never the token_id itself, since that's a bearer secret).
CE_RPC_TOKEN=$(cat ~/.crossengin/admin.token) \
scripts/rpc.sh capability.list
```

All three verbs require the `admin:sandbox` capability. Only the
`admin` role carries it by default. A `reader` / `skill_user` /
`curator` / `service` token cannot mint new tokens.

Refusal shape for a request without a required cap:

```json
{"ok":false,"result":null,"error":"capability required: skill:run"}
```

The full sandbox / TLS / signed-skill roadmap is in
[ADR-0105](adr/0105-sandbox-architecture.md). **TLS is delivered as
a sidecar recipe** — see the 7-section operator manual in
[`docs/DEPLOY_TLS.md`](DEPLOY_TLS.md): stunnel or nginx in front of
the daemon on loopback, terminate TLS on `:9977`, forward decrypted
bytes to `crossengin-rpc-daemon` on `:9876`. Reference configs live
in `infra/tls/`. **Signed skill install** is R54.2.

## 8. Interactive REPL (existing, still works)

Power users and operators can keep the chat REPL:

```bash
./bin/crossengin-chat
```

The REPL and the daemon are **independent processes** — they do not
share KGs, personas, or skill installs unless you explicitly wire a
shared snapshot (see `/save` / `/load` in the chat REPL). Run either;
run both if you like.

## 9. Docker (recipe, not shipped)

The `Dockerfile` needed for a container image is small: a base with
the NOVA toolchain, `make install`, `EXPOSE 9876`, `CMD
["./bin/crossengin-rpc-daemon"]`. Not shipped as a signed image
because R50's story is source-first; a hobbyist can compose one in
five lines.

## 10. Systemd / launchd / Windows service

Not shipped in R50. The daemon binary is a plain foreground process
that speaks JSON-over-TCP; wrapping it as a system service is
distribution-specific. A minimal systemd unit:

```ini
[Unit]
Description=CrossEngin JSON-RPC daemon
After=network.target

[Service]
Type=simple
ExecStart=/opt/crossengin/bin/crossengin-rpc-daemon
Environment=CE_RPC_PORT=9876
Environment=CE_RPC_BIND=127.0.0.1
Restart=on-failure
User=crossengin

[Install]
WantedBy=multi-user.target
```

Similar shape for launchd or a Windows service.

## 11. Snapshot round-trip

The chat REPL writes / reads durable snapshots (`/save`, `/load`).
The RPC daemon does NOT yet expose these via the wire (deferred to
R51+ under `session.save` / `session.load` verbs). For now, chat and
daemon are separate processes with their own in-memory state.

### 7.8 Signed skill install (R55.1)

For deployments that install user-authored skills over the wire
(marketplace-shape), enable signature enforcement:

```bash
CE_RPC_REQUIRE_TOKEN=1 \
CE_RPC_ADMIN_TOKEN_FILE=~/.crossengin/admin.token \
CE_RPC_REQUIRE_SIGNED_SKILL=1 \
scripts/rpc_daemon.sh
```

Pre-register trust anchors in-process (there is no wire verb for
anchor management yet — R56+). Signed installs supply the full
manifest fields + signer_pk_hex + signature_hex on the wire:

```bash
scripts/rpc.sh skill.install '{
  "name": "shop_debug_helper",
  "version": "1.0.0",
  "description": "extended debug patterns for shop-X",
  "policy_id": "3",
  "tier": "1",
  "effectors": "effector_code_exec,effector_file_ops",
  "capsule_deps": "",
  "refusals": "",
  "signer_pk": "<64 hex chars>",
  "signature": "<128 hex chars>"
}'
```

Refusal modes (all `{ok:false}`):
- `missing arg: signature` / `missing arg: signer_pk` — downgrade defense
- `signer_pk not 64 lowercase hex chars` — malformed key
- `signature not 128 lowercase hex chars` — malformed sig
- `signature does not verify against declared signer_pk` — tampered
- `signer_pk not in trust-anchor list` — untrusted

When enforcement is OFF (default), `skill.install {name: "echo"}`
installs a pre-registered built-in — no signature required. That
covers the single-user local case where the operator implicitly
trusts the daemon binary itself.

### 7.9 Per-user KG + capsule ownership (R55.2)

When a shared daemon holds resources for multiple users, mark them
owned so each holder only sees their own on `kg.list` /
`capsule.list`. The overlay is a side-registry — kg_manager and
capsule_registry stay untouched; ownership marks are additive.

```nova
// At daemon boot (before the accept loop), in a small NOVA helper:
let ownership = ownership_registry_new()
ownership_set_kg(ownership, "alice_notebook", "alice")
ownership_set_kg(ownership, "bob_notebook",   "bob")
ownership_set_capsule(ownership, "alice_private", "alice")
// "world" and other unset KGs stay public (every holder sees them).
rpc_ctx_set_ownership(ctx, ownership)
```

Then over the wire:

```bash
# Alice's token -> sees world + alice_notebook, NOT bob_notebook.
CE_RPC_TOKEN=$ALICE_TOKEN scripts/rpc.sh kg.list
# {"ok":true,"result":["world","alice_notebook"],"error":""}

# Bob's token -> sees world + bob_notebook, NOT alice_notebook.
CE_RPC_TOKEN=$BOB_TOKEN scripts/rpc.sh kg.list
# {"ok":true,"result":["world","bob_notebook"],"error":""}
```

**Rule** (in `src/sandbox/ownership.nova`):
- No overlay wired → nothing filtered (backward compat).
- Resource unset in overlay → visible to everyone (public).
- Resource has an owner → visible only to that exact holder.
  Anonymous callers (no valid token) see ONLY unset/public.

Ownership is a wire-visible filter, not a hard-gate. A capability
gate + skill_run is still what enforces execution boundaries; the
overlay only decides what's LISTED. Wire-transmitted skills
(R55.1) don't consult the overlay yet — a signed install lands as
a shared resource. R56+ can extend ownership to skills if
per-user skill scoping is needed.

## 12. What comes next (R55.3+)

- **R55.3** — Snapshot round-trip via wire: `session.save` /
  `session.load` verbs so a client can persist per-user state
  without dropping into the chat REPL
- **R56+** — Rate limits per capability, in-process TLS,
  hardware-key-backed admin bootstrap
- **R56+** — Rate limits per capability, in-process TLS,
  hardware-key-backed admin bootstrap

## 13. Troubleshooting

- **`bind failed on 127.0.0.1:9876`** — another daemon is running on
  that port. Kill it (`ss -ltnp | grep 9876`) or set `CE_RPC_PORT`
  to another port.
- **`socket() failed`** — the runtime doesn't allow socket creation
  (containers with restrictive seccomp filters can hit this). Run
  outside the container or relax the filter.
- **`no response from 127.0.0.1:9876`** — the daemon crashed or
  never started. Check its stderr; look for a `bind failed` or
  compile-time error.
- **`unknown verb: X`** — you typed the verb wrong. Spell it exactly
  as in section 7 above. `scripts/rpc.sh` prints the list on
  argument-count errors.
- **`no ingest agent in context`** on `ingest.*` — the standalone
  daemon does NOT wire the ingestion pipeline (R49 design). Use the
  chat REPL's `/ingest` for authored packs; the daemon will pick
  them up once R55 wires shared snapshots.

## Appendix: security posture

- **Loopback default.** The daemon binds `127.0.0.1` unless
  overridden. Any non-loopback bind requires an explicit
  `CE_RPC_BIND_ALLOW_NON_LOOPBACK=1` flag.
- **No auth on the wire.** The R49 daemon assumes the socket itself
  is the auth boundary. Anyone who can `nc` your port can dispatch
  named skills. This is correct for local-first / single-user; it
  is NOT correct for a LAN-exposed or public deployment. Sandbox /
  TLS / capability tokens land in R54.
- **No sandboxing on skill execution.** Skills run in the same
  process as the daemon. A malicious skill install is equivalent to
  a code-execution vulnerability. Only install skills you trust or
  wrote yourself until R54.
- **Persona is READ-ONLY through the wire.** `persona.show` reads;
  `persona.project` reads. No wire verb mutates a persona (mutations
  go through the chat REPL's `/persona set ...` commands, which have
  their own audit trail).
