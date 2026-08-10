# Ship as App — CrossEngin operator manual (R50, ADR-0109)

This document walks a new operator from a fresh checkout to a running
CrossEngin JSON-RPC daemon serving live requests.

CrossEngin ships as a **local daemon + client** pair. The daemon
(`crossengin-rpc-daemon`) binds a TCP socket and serves a
stable JSON-RPC surface (12 core verbs at R48p7, extended
through R59 with capability lifecycle, session snapshots, and
ingest-policy management — see §7 for the current list). Any
client that can speak line-oriented JSON over TCP can drive it
— `curl`, `nc`, a shell script, a native app, a browser
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

### 7.10 Session persistence (R55.3)

For a daemon whose state should survive a restart (personas +
capability tokens + trust anchors + ownership overlay), enable
snapshot persistence:

```bash
mkdir -p ~/.crossengin/snaps
chmod 0700 ~/.crossengin/snaps

CE_RPC_REQUIRE_TOKEN=1 \
CE_RPC_ADMIN_TOKEN_FILE=~/.crossengin/admin.token \
CE_RPC_SNAPSHOT_DIR=~/.crossengin/snaps \
scripts/rpc_daemon.sh
```

Then over the wire (admin token required — both verbs need the
`admin:session` capability):

```bash
# Persist current state to ~/.crossengin/snaps/prod.snap.
CE_RPC_TOKEN=$(cat ~/.crossengin/admin.token) \
scripts/rpc.sh session.save '{"name":"prod"}'
# -> {"ok":true,"result":{"name":"prod","path":".../prod.snap",
#      "bytes":12345,"personas":2,"tokens":3,"anchors":1,
#      "ownership_entries":4,"include_secrets":true}}

# Save without live token secrets (safer for backup pipelines).
scripts/rpc.sh session.save '{"name":"prod-shape","include_secrets":"0"}'

# Restore state (destructive: additive to current registries).
CE_RPC_TOKEN=$(cat ~/.crossengin/admin.token) \
scripts/rpc.sh session.load '{"name":"prod"}'
# When loading a shape-only snapshot, `result.rekeyed` carries
# [{holder, new_token_id}, ...] pairs the operator must redistribute.
```

**What's in a snapshot:**
- `#PERSONA v1` blocks — every registered persona via `persona_export`
- `#OWNERSHIP v1` — every (kind, name, owner) triple
- `#TRUST v1` — every anchor pubkey (hex-encoded)
- `#CAPS v1` — every token as (holder + caps + expiry + revoked) +
  optionally the token_id (`include_secrets=1`, default) OR a `-`
  placeholder (`include_secrets=0`; loader mints a fresh id)

**Path sandbox** — the daemon accepts a bare `name` only. Names
must match `[A-Za-z0-9._-]{1,64}`, cannot start with `.`, and
cannot be `.` or `..`. Slash, backslash, and NUL bytes are
refused before any file operation. The composed path is always
`<CE_RPC_SNAPSHOT_DIR>/<name>.snap`; traversal outside the
configured dir is structurally impossible.

**Security posture:**
- Snapshot files contain live bearer credentials when
  `include_secrets=1` (the default). Chmod the directory 0700 and
  own it as the daemon user. Never copy a full snapshot to an
  untrusted machine.
- Use `include_secrets=0` for backups / migrations you want to
  ship elsewhere. The operator distributes the rekeyed token
  ids returned by `session.load` to their holders.
- The snapshot is a DAEMON-shaped state dump. A running chat
  REPL alongside the daemon has its own separate snapshot
  (`/save PATH` in the chat) that persists cognition-loop state
  the daemon doesn't own.

### 7.11 Per-token rate limits (R56)

Every capability token can carry a `qps_max` field — a wall-clock
1-second fixed-window cap on requests. `qps_max=0` (the default, and
what every R54/R55 token minted before R56 has) means unlimited.

Set at issuance:

```bash
CE_RPC_TOKEN=$(cat ~/.crossengin/admin.token) \
scripts/rpc.sh capability.issue '{
  "holder":   "shop-frontend",
  "roles":    "service",
  "qps_max":  "50"
}'
# -> {"ok":true,"result":{"token_id":"...","holder":"shop-frontend",
#      "caps":["nl:ask","skill:run"], "issued_at":..., "expires_at":0,
#      "qps_max":50}}
```

When the token exceeds the limit within a 1-second window, the
gate refuses:

```json
{"ok":false,"result":null,
 "error":"rate limit exceeded: max 50 req/s for this token"}
```

`capability.list` reports each token's `qps_max`; `session.save` /
`session.load` round-trip it. Legacy snapshot files from R55.3 are
readable — tokens without a `qps_max` field default to 0 on load.

**Where the check fires:** last in the authorize chain — after
enforcement / token liveness / capability match. A cap refusal
still reports the missing cap; a rate refusal fires only when the
call would otherwise have been authorized.

**Per-TOKEN, not per-HOLDER:** two tokens for the same holder each
carry their own bucket. That matches "a service token has its own
budget separate from the operator's ordinary tokens." R57+ can add
per-holder aggregate limits if the operational need shows up.

### 7.12 Per-holder skill.run scoping (R57)

R55.2's ownership overlay handled list visibility (`kg.list`,
`capsule.list`). R57 extends it to EXECUTION for `skill.run` +
symmetric filtering on `skill.list`. Mark a skill owned and only
its holder can invoke it:

```nova
// At daemon boot, in a small NOVA helper:
let ownership = ownership_registry_new()
ownership_set_skill(ownership, "shop_deploy",     "ops-lead")
ownership_set_skill(ownership, "shop_pagerduty",  "on-call")
// Skills NOT in the overlay ("echo", "research") stay public --
// every holder can invoke them (backward compat).
rpc_ctx_set_ownership(ctx, ownership)
```

Then over the wire:

```bash
# ops-lead can invoke their owned skill.
CE_RPC_TOKEN=$OPS_LEAD_TOKEN \
  scripts/rpc.sh skill.run '{"name":"shop_deploy","arg":"canary"}'
# -> {"ok":true,"result":{...ProposalResult...}}

# on-call cannot (owned by ops-lead).
CE_RPC_TOKEN=$ON_CALL_TOKEN \
  scripts/rpc.sh skill.run '{"name":"shop_deploy","arg":"canary"}'
# -> {"ok":false,"error":"skill not accessible to on-call: shop_deploy"}

# Public skills stay callable by everyone.
CE_RPC_TOKEN=$ON_CALL_TOKEN \
  scripts/rpc.sh skill.run '{"name":"echo","arg":"hi"}'
# -> {"ok":true,...}
```

**Refusal ordering matters** — ownership refusal takes precedence
over "skill not installed" so a caller learns nothing about the
existence of a skill they can't access. Their `skill.list` view
also hides those names.

**Gate composition** — the capability gate still fires FIRST.
A reader token (no `skill:run` cap) is refused at the capability
check before the ownership check runs, so debugging output
correctly reports `capability required: skill:run` for the
missing cap and never leaks the fact that a skill is owned.

**What's not gated:** the NL surface (`nl.ask`) still routes
its dispatched skill runs through `skill_run` directly, bypassing
`skill.run`. Ownership scoping applies to explicit wire calls to
`skill.run` only. A future R58+ could thread holder context into
`nl_execute` to also gate the auto-dispatched skill (research /
coding_helper) but that's an executor-layer change.

### 7.12 Curator auto-approval policies (R58)

A running daemon can auto-approve safe ingest records without a
human in the loop, while still keeping every approval attributable
to a named policy in the audit log.

Register policies in-process at daemon boot (a small NOVA helper
that imports `src/ingest/policy.nova`):

```nova
let preg = policy_registry_new()

// Trust: any authored .cerec pack with an OPEN license and <= 500
// atoms auto-approves. First-match-wins so put restrictive
// policies first.
let safe = policy_new("safe-open-packs", POL_ACTION_APPROVE)
policy_add_predicate(safe, POL_OP_SOURCE_PREFIX, "src:pack:")
policy_add_predicate(safe, POL_OP_LICENSE_EQ,    LICENSE_OPEN)
policy_add_predicate(safe, POL_OP_MAX_ATOMS,     500)
policy_registry_register(preg, safe)

rpc_ctx_set_ingest_policy(ctx, preg)
```

Then over the wire (admin token with `ingest:decide` cap; admin
role carries it, so does the R55 `curator` role):

```bash
scripts/rpc.sh ingest.auto_approve
# -> {"ok":true,"result":{"scanned":7,"matched":4,"approved":4,
#      "ingest_failed":0,
#      "entries":[
#        {"id":1,"policy":"safe-open-packs","state":"ingested"},
#        {"id":2,"policy":"","state":"pending"},
#        ...]}}
```

Every approved entry carries `"auto-approved by policy:<name>"` in
its reason field so a subsequent `ingest.review` walk shows exactly
which policy fired.

**Preserves the ADR-0101 invariant** ("no atom without a traceable
decision"): every atom the pipeline commits is attributable to
either a named policy or a human decision. Auto-approval
accelerates the operator; it doesn't remove the audit trail.

Predicate ops (v1): `POL_OP_ANY`, `POL_OP_SOURCE_PREFIX`,
`POL_OP_KG_EQUALS`, `POL_OP_LICENSE_EQ`, `POL_OP_MAX_ATOMS`.
Policies use AND semantics — every predicate must match.

### 7.13 Policy management over the wire (R59)

R59 adds three verbs so an admin/curator can add, list, and
remove policies dynamically instead of only at daemon boot. The
registry stays in-process (still call `rpc_ctx_set_ingest_policy`
at boot to attach an empty or seeded registry); these verbs mutate
it live:

```bash
# List currently registered policies (cap: ingest:review).
scripts/rpc.sh ingest.policy.list
# -> {"ok":true,"result":[
#      {"name":"safe-open-packs","action":"APPROVE","predicates":[
#         {"op":"SOURCE_PREFIX","arg":"src:pack:"},
#         {"op":"LICENSE_EQ","arg":1},
#         {"op":"MAX_ATOMS","arg":500}]}]}

# Register a new policy (cap: ingest:decide).
# Predicates encoded as "OP:arg|OP:arg|..." with pipe as
# separator; first ':' in each token splits op-name from arg
# (so "SOURCE_PREFIX:src:pack:" is well-formed -- the trailing
# colons stay in the arg).
scripts/rpc.sh ingest.policy.add \
  name safe-open-packs \
  action APPROVE \
  predicates "SOURCE_PREFIX:src:pack:|LICENSE_EQ:1|MAX_ATOMS:500"
# -> {"ok":true,"result":{"name":"safe-open-packs","action":"APPROVE",
#      "predicate_count":3,"registry_count":1}}

# Remove every policy with a given name (cap: ingest:decide).
# Duplicates by name are legal; remove drops them all.
scripts/rpc.sh ingest.policy.remove name safe-open-packs
# -> {"ok":true,"result":{"name":"safe-open-packs","removed":1,
#      "registry_count":0}}
```

Op names accepted: `ANY`, `SOURCE_PREFIX`, `KG_EQUALS`,
`LICENSE_EQ`, `MAX_ATOMS`. Action names accepted: `APPROVE`
(deny reserved for R60+). Ops whose arg is an int (`LICENSE_EQ`,
`MAX_ATOMS`) are rejected with a clean refusal when the arg is
missing or unparseable — a bad predicate short-circuits so the
registry is never left with a partial policy. Empty
`predicates` yields a catch-all policy that matches every
entry.

Reader-role tokens can `list` (read-only inspection is
review-capped) but not `add`/`remove` — those need `curator` or
`admin`.

## 12. What comes next (R60+)

- **R60+** — .cerec pattern packs (R53 patterns authored + shipped
  as .cerec files through the R43 pipeline), holder context
  threaded into `nl_execute` so auto-dispatched skills (research /
  coding_helper via `nl.ask`) also honor the ownership overlay,
  in-process TLS (retires the sidecar recipe), generic
  structured-record adapter for one-off JSON/YAML sources
- **R61+** — Per-source rate budgets controllable via admin wire
  verb, hardware-key-backed admin bootstrap, per-holder aggregate
  rate limits

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
