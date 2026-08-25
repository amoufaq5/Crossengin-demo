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

**R60 update:** `nl.ask` now honors the ownership overlay too.
When an overlay is wired, an `nl.ask` that would auto-dispatch a
skill (research / relate / contradict / is_a) runs the same
ownership check `skill.run` runs. Refusal shape is bit-identical
(`"skill not accessible to <holder>: research"`), stamped into
the ExecutionResult's `refusal_reason` slot; the JSON envelope
still returns `ok:true` because the verb executed successfully
even though the executor refused to dispatch. Admin-delegated
kinds (`list capsules`, `list skills`, `retract …`) never touch
the gate — they were never skill dispatches to begin with. The
old executor-only path (chat REPL, unit tests, any caller of
`nl_execute` with the 8-arg signature) is unchanged; a new
`nl_execute_scoped(...)` variant accepts the overlay + holder
and is what `nl.ask` calls under the hood.

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

### 7.14 Pattern packs authored as .cerec files (R61)

R53 Pattern Capsules were built-in only — the two shipped
capsules (`debug_common`, `research_hygiene`) compiled into the
daemon. R61 adds a `.cerec`-shaped **pattern pack** file
format so operators can ship additional pattern capsules as
authored data:

```
# data/patterns/security_review.cerec
CAPSULE security_review
VERSION 1.0.0
DESCRIPTION OWASP + CWE derived review patterns for coding_helper
LICENSE CC-BY-4.0

PATTERN 900
TRIGGER sql injection
GUIDANCE Prefer parameterized queries; never interpolate user input into SQL.

PATTERN 850
TRIGGER hardcoded secret
GUIDANCE Extract to environment or a secrets manager; check git history for prior commits.
```

Load at daemon boot via a small NOVA helper:

```nova
import "src/ingest/pattern_pack.nova"

pattern_pack_load("data/patterns/security_review.cerec")
// -> patterns register into the process-wide pattern registry;
//    coding_helper's next `pattern_registry_match_all(...)` call
//    now sees them alongside the built-ins.
```

**Why not through the R43 review queue?** Pattern packs are
ADVICE, not truth-claims. They never write atoms into a KG, so
the ADR-0101 "no atom without a traceable decision" invariant
simply doesn't apply. Trust flows through the pack's manifest
(capsule name + version + auto-generated `src:pattern:<name>:v<ver>`
tag) and the operator's decision to call `pattern_pack_load`.
The R58 auto-approval policies + R59 wire management only cover
KG-bound records — pattern packs live on the parallel advice
track.

**Directive grammar** — `CAPSULE`, `VERSION` (semver required),
`DESCRIPTION` (metadata; parsed for forward-compat but not stored
today), `LICENSE` (same), `SOURCE_TAG` (optional override for
the auto tag), then a sequence of `PATTERN <0..1000>` blocks
each followed by `TRIGGER <tok1> <tok2> ...` and `GUIDANCE
<text>`. A new `PATTERN` closes the previous one; a new
`CAPSULE` closes the previous capsule. Blank lines don't close
anything (matches the .cerec convention). Comments (`# ...`) are
line-scoped.

**Lenient parser** — a PATTERN missing TRIGGER or GUIDANCE, a
confidence outside 0..1000, or an unknown directive records an
error at that line and skips the fragment; other patterns in
the same file still register. Ships a validated sample pack at
`data/patterns/security_review.cerec` (25 OWASP/CWE-derived
patterns across injection, XSS, auth, deserialization, crypto,
and side-channel families).

**Idempotent by name** — loading the same file twice or two
files that define the same `CAPSULE` name is safe: the second
load REPLACES the first in the registry (last-write-wins,
matches R53 `pattern_registry_register` semantics). Useful for
hot-reloading a pack during development without restarting the
daemon.

### 7.15 Pattern packs over the wire (R62)

R61 shipped `pattern_pack_load` for boot-time file loading;
R62 puts it on the JSON-RPC surface so an admin can install
packs dynamically the same way `capability.issue` /
`ingest.policy.add` land.

```bash
# List every pattern capsule currently registered
# (cap: capsule:read -- reader role can do this).
scripts/rpc.sh pattern.list
# -> {"ok":true,"result":[
#      {"name":"debug_common","version":"1.0.0",
#       "pattern_count":12,"source_tag":"src:pattern:debug_common:v1"},
#      {"name":"research_hygiene","version":"1.0.0",
#       "pattern_count":5,"source_tag":"src:pattern:research_hygiene:v1"},
#      {"name":"security_review","version":"1.0.0",
#       "pattern_count":25,"source_tag":"src:pattern:security_review:v1.0.0"}]}

# Install a pack body inline (cap: capsule:install -- admin or
# curator). The `body` arg is the RAW .cerec-shaped pack text;
# JSON-escape newlines + quotes at the client. scripts/rpc.sh
# handles that for you:
scripts/rpc.sh pattern.install body "$(cat pack.cerec)"
# -> {"ok":true,"result":{
#      "registered":1,
#      "names":["my_local_pack"],
#      "error_count":0,
#      "errors":[],
#      "registry_count":4}}
```

Parse errors are surfaced per-line + per-message but never
abort the install — every WELL-FORMED capsule in the body still
registers. A pack with zero parseable capsules returns
`registered:0` alongside the error list so an operator can
diagnose without a second call.

**Same trust boundary as R61 file loading** — patterns are
advice; no review queue; last-write-wins by capsule name.
Re-installing `security_review v1.0.1` over `v1.0.0` REPLACES
the older entry in place, and every downstream skill's next
`pattern_registry_match_all(...)` call sees the new patterns
immediately.

### 7.16 Holder-scoped pattern overlay (R63)

The R61/R62 pattern registry is process-wide by design (matches
R53). R63 adds an OPTIONAL scope layer on top of that global
registry via the same R55.2 ownership overlay every other
resource kind already uses:

```
OWN_KIND_KG       (R55.2)  — kg.list filters by holder
OWN_KIND_CAPSULE  (R55.2)  — capsule.list filters by holder
OWN_KIND_SKILL    (R57)    — skill.run refuses non-owner
OWN_KIND_PATTERN  (R63)    — pattern.list filters + install auto-assigns
```

When an ownership overlay is wired into the RpcContext:

- **`pattern.list`** filters output by holder visibility.
  A caller sees a pack iff either (a) no owner is set for
  that pack, or (b) the pack's owner matches the presented
  holder. Anonymous callers see only unset (public) packs.
- **`pattern.install`** auto-assigns the presented holder as
  the owner of every capsule in the body. The response now
  echoes an `owners: [...]` list alongside `names: [...]` so
  operators see exactly what ownership was written.
- Anonymous installs (no valid token) leave capsules public
  even when an overlay is wired — there's no plausible holder
  to stamp, and refusing outright would be surprising for
  bootstrap flows.
- Snapshot save/load automatically round-trips pattern
  ownership entries because R55.3's `#OWNERSHIP v1` section
  walks generic `ownership_entries` and the R63 loader
  accepts `pattern` as a known kind.

Skills that consult patterns can opt in to the same gate via
the new `pattern_registry_match_scoped(tokens, filter_names,
overlay, holder)` API — a drop-in replacement for
`pattern_registry_match_all` that honors the overlay.

**R64 update:** the `coding_helper` reference skill now uses
this scoped API automatically when the daemon has an overlay
wired. Threading is:
`skill.run` verb → `skill_run_scoped(sup, perc, overlay,
holder)` → `skill_dispatch_policy_scoped` →
`coding_helper_policy_scoped` → `pattern_registry_match_scoped`.
A caller who can't see `debug_common` under the overlay gets
zero matches (proposal falls back to the "add more concrete
symptoms" hint, confidence collapses to 0) — no owned advice
leaks across holders. `research` is scope-agnostic (walks KGs,
not patterns) so its dispatch stays unchanged; the scoped path
transparently forwards it to the unscoped policy.

Backward compat: without an overlay wired, R63 + R64 behavior
is byte-identical to R62. The overlay is DATA — no default is
constructed; operators opt in by calling
`rpc_ctx_set_ownership(...)` at daemon boot.

### 7.17 JSON structured-record importer (R65)

R43 shipped importers for `.cerec`, CSV, N-Triples, Wikidata,
ConceptNet, paper metadata, WordNet, and LLM-emitted `.cerec`.
R65 adds a **JSON** adapter for one-off structured sources
(scraper output, admin dumps, LLM-emitted JSON structures) so
an operator doesn't have to hand-author `.cerec` syntax to
ingest a small dataset.

Wire format: a JSON array of record objects. Each object
carries `kg` + `source` plus optional `capsule` metadata and
`atoms` / `implications` / `observations` / `citations` arrays
that mirror the `.cerec` record shape 1:1:

```json
[
  {
    "kg": "climate",
    "source": "src:json:sample:climate:v1",
    "capsule": {
      "name": "climate_sample",
      "version": "1.0.0",
      "description": "small illustrative climate reference",
      "license": "CC-BY-4.0"
    },
    "atoms": [
      {"label": "co2",                 "kind": "concept", "belief": 950},
      {"label": "atmospheric_warming", "kind": "fact",    "belief": 900}
    ],
    "implications": [
      {"ante": "co2", "conseq": "atmospheric_warming", "strength": "EMPIRICAL"}
    ]
  }
]
```

Ingest via the standard `/ingest json <path>` chat command
(or the `ingest.*` wire verbs when they land). The importer
produces curriculum records identical in shape to `.cerec`
output, so:

- **R43 pipeline** applies them unchanged (auto-register capsules,
  seed atoms, wire implications, credit citations).
- **R58 auto-approval policies** treat them as first-class
  entries — a JSON-imported record with `src:json:...` prefix
  can be approved by a `SOURCE_PREFIX:src:json:` policy.
- **R55.3 session snapshots** persist any resulting KG state.

`kind` accepts either the string name (`fact`, `relation`,
`concept`, `skill`, `lang`, `rule`) or the raw integer
constant. `strength` accepts `FORMAL` | `EMPIRICAL`. `sign` is
+1 or -1. Beliefs / weights are integer milli-scaled (0..1000).
`kg` and `source` default to the values supplied to
`jsonr_parse(path, kg_hint, source_tag)` when omitted from a
record; per-record values win when both are present.

**Lenient parser** — a malformed field records an error at the
offending record's array index and skips just that fragment;
other well-formed records still land. A top-level JSON syntax
error returns the parse error with an empty records list so
the operator can fix + retry without partial ingestion.

Shipped: `data/packs/samples/climate_facts.json` — 10 atoms +
7 implications + 3 observations + 2 citations across a small
climate-science reference; parses clean and demonstrates every
directive.

**YAML now lands in R85** — see §7.35. R65's original "defer
YAML to a later round" call turned into a strict-subset
adapter under `src/ingest/importers/yaml_records.nova` that
rejects anchors, tags, flow-style, and block scalars up-front
rather than parsing them permissively. Operators who need
the rejected features still pre-convert with `yq -p yaml -o
json` and pipe into the JSON importer.

### 7.18 ingest.file wire verb (R66)

R43 shipped `/ingest <format> <path>` for the chat REPL and
the ingest agent behind it. R66 puts the same capability on
the JSON-RPC surface so a remote client can push records
inline (no file on disk):

```bash
# .cerec body inline (cap: ingest:decide -- curator or admin).
scripts/rpc.sh ingest.file \
  format cerec \
  body "KG solar_system
SRC src:cerec:sample:v1
ATOM mercury 1 900
ATOM hot 3 800
IMP mercury hot EMPIRICAL"
# -> {"ok":true,"result":{
#      "format":"cerec",
#      "records_parsed":1,
#      "records_ingested":1,
#      "records_queued":0,
#      "records_dropped":0,
#      "atoms_added":2,
#      "error_count":0,
#      "errors":[],
#      "force_queue":false}}

# JSON body with kg/source defaults.
scripts/rpc.sh ingest.file \
  format json \
  kg climate \
  source src:cerec:climate:v1 \
  body '[{"atoms":[{"label":"co2","kind":"concept","belief":950}]}]'
# -> {"ok":true,"result":{"format":"json","records_parsed":1,
#      "records_ingested":1,...}}

# Force human review even for a trusted source.
scripts/rpc.sh ingest.file \
  format cerec \
  body "KG k
SRC src:cerec:review-me
ATOM x 1 500" \
  force_queue 1
# -> ingested:0, queued:1
```

Formats supported as of R85: **cerec**, **json**, **yaml**,
**csv**, **ntriples**, **wikidata**, **conceptnet**,
**papermeta**, **wordnet** — every importer whose module ships
a `_parse_text` variant. Each takes the same envelope
(`format` + `body`) plus format-specific args:

| format     | requires `kg` | requires `source` | extra              |
|------------|---------------|-------------------|--------------------|
| cerec      | no (in body)  | no (in body)      | —                  |
| json       | no (default)  | no (default)      | `kg`/`source` default when a record omits them |
| yaml       | no (default)  | no (default)      | R85 subset only (see §7.35); `kg`/`source` default when a record omits them |
| csv        | **yes**       | **yes**           | —                  |
| ntriples   | **yes**       | **yes**           | —                  |
| wikidata   | **yes**       | **yes**           | R68 adds `labels_body` (TSV) + `formal_preds` (CSV) |
| conceptnet | **yes**       | **yes**           | optional `keep_lang="1"` for multilingual |
| papermeta  | **yes**       | no                | source computed per-DOI |
| wordnet    | **yes**       | **yes**           | —                  |

**Trust boundary preserved** — the same `_ing_is_trusted`
check that gates `/ingest` from a file-path applies here:
records with a trusted source-tag prefix (`src:pack:`,
`src:cerec:`, `src:user:`, `src:cap:`) go direct to the
pipeline; everything else lands in the review queue. R58
auto-approval policies then decide on queued entries the same
way they do for file-loaded ingests.

**`force_queue: "1"`** short-circuits trust and queues every
record — useful when an operator wants human review of every
record even from a trusted origin (e.g., debugging a suspect
source, or building a curator audit trail).

**Parse errors surface per-line + per-message** but never
abort the ingest — every well-formed record still lands. A
body with zero parseable records returns `records_parsed:0` +
the error list so an operator can diagnose without a second
call.

### 7.19 Wikidata multi-body ingest (R68)

R67 wired wikidata over `ingest.file` but with an empty labels
table + default `FORMAL` predicate set, so imported atoms
surfaced as raw `Q76` / `Q5` IDs. R68 adds two optional args
so a caller can ship the labels table + additional FORMAL
predicates alongside the triples in one JSON-RPC call:

- **`labels_body`** — TSV `Qid<TAB>label\n...`. Comment lines
  starting with `#` and blank lines are dropped. Parsed via
  `wd_labels_parse_text`; the resulting table replaces the
  empty default so atoms surface with human-readable labels.
- **`formal_preds`** — comma-separated `Pxx` predicate IDs.
  Each is added on top of the R67 default set (`P31`, `P279`,
  `P361`, `P527`, `P171`, `P105`, `P17`) via
  `wd_promote_predicate` which dedupes internally. Adding a
  predicate already in the default set is a no-op.

Example:

```bash
scripts/rpc.sh ingest.file \
  format wikidata \
  kg wd \
  source src:cerec:wd \
  body "$(cat triples.nt)" \
  labels_body "$(printf 'Q76\tobama\nQ5\thuman\nQ729\tanimal\n')" \
  formal_preds "P625,P569"
# -> {"ok":true,"result":{
#      "format":"wikidata",
#      "records_parsed":1,
#      "records_ingested":1,
#      "labels_loaded":3,
#      "extra_formal_preds":2,
#      ...}}
```

Response echoes `labels_loaded` (row count from
`labels_body`) and `extra_formal_preds` (net-new predicate
count, excluding defaults). Both fields stay `0` for
non-wikidata formats OR when the args aren't supplied — a
caller can key on them without format-branch code.

Non-wikidata formats **silently ignore** `labels_body` +
`formal_preds` so a common config shipped to multiple ingests
doesn't need per-format arg-stripping.

### 7.20 Ownership auto-assignment on install verbs (R70)

R63 shipped auto-assignment for `pattern.install` — when an
overlay is wired and a holder is presented, the installed
capsule gets stamped as owned by that holder so `pattern.list`
correctly filters. R70 finishes the story by applying the
same shape to `capsule.install` and `skill.install`.

Rules (identical across all three install verbs now):

| condition | outcome |
|---|---|
| no overlay wired | `owner=""` (no stamp) |
| overlay wired, anonymous caller | `owner=""` (no plausible stamp target) |
| overlay wired, resource unowned | stamp holder → `owner=<holder>` |
| overlay wired, resource owned by holder | no-op (idempotent re-install) |
| overlay wired, resource owned by someone else | **refused**: `"<kind> '<name>' already owned by <other>"` |

The cross-holder refusal fires BEFORE any state mutation —
a bob attempting `capsule.install public_pack` after alice
already installed it gets a clean refusal, the capreg's
install-state doesn't flip, and the overlay is unchanged.

Response envelope now carries `owner`:

```bash
scripts/rpc.sh capsule.install name public_pack
# -> {"ok":true,"result":{
#      "name":"public_pack",
#      "code":0,
#      "installed":true,
#      "owner":"alice"}}     # <-- new in R70

scripts/rpc.sh skill.install name research
# -> {"ok":true,"result":{
#      "name":"research",
#      "installed":true,
#      "pre_anchored":true,
#      "code":0,
#      "owner":"alice"}}     # <-- new in R70
```

Combined with R55.2's `kg.list` + `capsule.list` filtering
and R63's `pattern.list` filtering, this means every RESOURCE
kind now flows through a consistent lifecycle: an admin
install stamps ownership; only the owner can re-install or
touch the resource under the overlay; every list surface
filters correctly.

### 7.21 Ownership auto-assignment on ingest.file (R71)

R70 closed auto-assignment for the three install verbs
(pattern.install / capsule.install / skill.install). R71
completes the ownership lifecycle by wiring the same shape
into `ingest.file`. Now every RESOURCE ENTRY POINT stamps
ownership consistently:

| entry point | stamps |
|---|---|
| pattern.install (R63) | pattern capsule |
| capsule.install (R70) | capsule |
| skill.install (R70)   | skill |
| **ingest.file (R71)** | **target KG + capsule metadata (if any)** |

`ingest.file` runs a per-record pre-pass BEFORE the R66 apply
step:

1. **Check phase** (no writes): look up existing owner for the
   record's target `kg` AND (if the record ships capsule
   metadata) its capsule name.
2. **Refuse phase**: if either resource is already owned by
   someone other than the presented holder, record a
   per-record refusal error (`"ownership refused: <kind>
   '<name>' already owned by <other>"`) and drop the record.
3. **Apply phase**: if the check phase passed, stamp the
   presented holder on any currently-unowned resource. The
   split ensures a capsule refusal never leaves the KG
   half-stamped.

Response echoes three new counters:

| field | meaning |
|---|---|
| `kgs_stamped`                    | net-new KG stamps (dedupes within batch) |
| `capsules_stamped`               | net-new capsule stamps (dedupes) |
| `records_refused_by_ownership`   | records dropped due to owner-mismatch |

Backward compat: `kgs_stamped` and `capsules_stamped` stay at
`0` when no overlay is wired OR when the caller is anonymous
— existing R66-R68 wire tests are byte-identical.

Example:

```bash
# Alice ingests a JSON record with capsule metadata under a
# wired overlay -- gets both her KG and her capsule stamped.
scripts/rpc.sh ingest.file \
  format json \
  body '[{"kg":"solar_system","source":"src:cerec:x",
          "capsule":{"name":"solar_pack_r71","version":"1.0.0"},
          "atoms":[{"label":"venus","kind":"fact","belief":900}]}]'
# -> {"ok":true,"result":{
#      "records_parsed":1,
#      "records_ingested":1,
#      "kgs_stamped":1,
#      "capsules_stamped":1,
#      "records_refused_by_ownership":0,
#      ...}}

# Bob tries the same body -> owner-mismatch on both resources;
# per-record refusal error, nothing ingested.
# -> {"ok":true,"result":{
#      "records_parsed":1,
#      "records_ingested":0,
#      "records_refused_by_ownership":1,
#      "errors":[{"line":0,"message":"ownership refused: kg
#                 'solar_system' already owned by alice"}],
#      ...}}
```

**Batch semantics** — a mixed batch is atomic per-record but
lenient overall: a bob-ingest with one record targeting an
alice-owned KG + another targeting a fresh KG refuses record
1 (per-record error) and stamps + ingests record 2. Matches
the R66 lenient pattern used for every other error class.

**Full lifecycle now consistent** — combined with R55.2's
`kg.list` / `capsule.list` filters, R57's `skill.run` gate,
R60's `nl.ask` gate, R63's pattern gates, R64's
`coding_helper` gate, and R70's install-verb stamps, an
operator can wire a single ownership overlay and every
resource kind an alice creates via any entry point is
invisible to bob and refuses cross-holder writes uniformly.

### 7.22 Ownership audit + transfer over the wire (R72)

R55.2/R63/R70/R71 all stamp ownership on their respective
entry points. R72 exposes two admin verbs so operators can
audit + hand off the overlay from the wire instead of
dropping into NOVA helper code.

```bash
# Enumerate every ownership entry (cap: admin:sandbox).
scripts/rpc.sh ownership.list
# -> {"ok":true,"result":[
#      {"kind":"kg","name":"alice_notebook","owner":"alice"},
#      {"kind":"capsule","name":"security_pack","owner":"alice"},
#      {"kind":"skill","name":"research","owner":"alice"},
#      {"kind":"pattern","name":"my_debug_pack","owner":"bob"}]}

# Filter by kind and/or holder (both optional; compose with AND).
scripts/rpc.sh ownership.list kind kg holder alice
# -> only KGs owned by alice

# Hand off ownership from alice to bob (cap: admin:sandbox).
scripts/rpc.sh ownership.transfer \
  kind kg name alice_notebook new_owner bob
# -> {"ok":true,"result":{
#      "kind":"kg","name":"alice_notebook",
#      "old_owner":"alice","new_owner":"bob",
#      "cleared":false}}

# Make a resource public again (empty new_owner clears the entry).
scripts/rpc.sh ownership.transfer \
  kind capsule name shared_pack new_owner ""
# -> {"ok":true,"result":{...,"cleared":true}}
```

**Refusal rules for `ownership.transfer`**:

- Missing any of `kind`, `name`, `new_owner` → refuse (empty
  `new_owner` string is OK — that's the "make public" case)
- `kind` outside {kg, capsule, skill, pattern} → refuse
- Empty `name` → refuse
- Target resource has no existing owner AND `new_owner`
  non-empty → refuse (`"cannot transfer: <kind> '<name>' has
  no existing owner (use an install verb to establish)"`).
  Transfer means HAND-OFF; use an install verb to establish
  fresh ownership.

Both verbs require **admin:sandbox** — the same cap the R55
capability lifecycle verbs use. Curators (`ingest:decide`)
can create ownership via install/ingest verbs but can't
audit or transfer it.

### 7.23 Policy registry round-trip via session snapshots (R73)

R55.3 shipped `session.save`/`session.load` covering personas,
capability tokens, trust anchors, and ownership overlay. R58's
policy registry was boot-time-only — a `session.load` would
restore every other piece of daemon state but leave auto-
approval policies to be re-registered by hand. R73 closes the
gap.

Snapshot format gets one new section:

```
#POLICY v1
POLICY safe_open_packs APPROVE
PRED SOURCE_PREFIX src:pack:
PRED LICENSE_EQ 2
PRED MAX_ATOMS 500
POLICY catch_all APPROVE
PRED ANY 0
```

Each policy emits a `POLICY <name> <action>` line, then a
`PRED <op> <arg>` for every predicate. Predicate encoding
mirrors R58: `SOURCE_PREFIX` and `KG_EQUALS` take a string
arg (everything after the space, so colons in values round-
trip); `LICENSE_EQ` and `MAX_ATOMS` take an integer arg;
`ANY`'s arg is written as `0` and ignored on load.

Wire responses now carry a `policies` count:

```bash
scripts/rpc.sh session.save name my_daemon
# -> {"ok":true,"result":{
#      ...
#      "personas":3,"tokens":7,"anchors":2,
#      "ownership_entries":12,"policies":4,
#      ...}}

scripts/rpc.sh session.load name my_daemon
# -> {"ok":true,"result":{
#      ...
#      "policies":4,       # <-- R73: repopulated ingest.policy registry
#      ...}}
```

New signatures (existing callers unchanged):

```
session_snapshot_serialize_ex(persona_reg, cap_reg, trust_reg,
                              overlay, policy_reg, include_secrets, now)
session_snapshot_apply_ex(text, persona_reg, cap_reg, trust_reg,
                          overlay, policy_reg, now)
```

The 6-arg `session_snapshot_serialize` / 6-arg
`session_snapshot_apply` still work — they delegate with
`policy_reg=0` so a `#POLICY v1` section is neither written
nor read. Every R55.3-R72 test remained byte-identical.

**Lenient parser** — a malformed `PRED` line, an unknown op
name, an unknown action, or a `PRED` before any `POLICY`
opener is dropped without aborting the parse; the rest of
the section still loads.

### 7.24 Pattern registry round-trip via session snapshots (R74)

R73 put the R58 policy registry into session snapshots. R74
does the same for the R53/R61/R62 pattern registry so R62-
installed authored packs survive a daemon restart.

Snapshot format gets one more section — mirrors R61's .cerec
pattern-pack authoring shape so an operator can eyeball or
hand-edit:

```
#PATTERN v1
CAPSULE security_review 1.0.0
PATTERN 900 src:pattern:security_review:v1.0.0
TRIGGER sql injection
GUIDANCE Prefer parameterized queries; never interpolate user input into SQL.
PATTERN 850 src:pattern:security_review:v1.0.0
TRIGGER hardcoded secret
GUIDANCE Extract to environment or secrets manager; check git history.
CAPSULE debug_common 1.0.0
PATTERN 800 src:pattern:debug_common:v1
...
```

The pattern registry is a process-wide singleton (no reg
param) so the `#PATTERN v1` section is emitted
**unconditionally** in every R74+ snapshot — the lazy-init
built-ins always populate the section with at least
`debug_common` + `research_hygiene`.

Wire responses now carry a `patterns` count:

```bash
scripts/rpc.sh session.save name my_daemon
# -> {"ok":true,"result":{
#      ...
#      "policies":4,
#      "patterns":3,       # <-- R74: 2 built-ins + 1 authored pack
#      ...}}

scripts/rpc.sh session.load name my_daemon
# -> {"ok":true,"result":{
#      ...
#      "patterns":3,
#      ...}}
```

**Last-write-wins on capsule name** (matches R53 semantics).
Re-loading a snapshot that contains `debug_common v1.0.0`
into a daemon whose lazy-init already registered
`debug_common v1.0.0` is a no-op. An operator who edits a
snapshot to bump a built-in's guidance (or version) and
reloads gets their edit honored — the tweaked capsule
overwrites the compiled built-in.

**Lenient parser** — non-numeric `PATTERN <conf>` (typo
guard: `str_to_int` returns 0 for garbage, so we explicitly
reject non-digit chars in the conf slot), missing `TRIGGER`,
missing `GUIDANCE`, or malformed `CAPSULE` all drop the
fragment; other patterns in the same capsule still register.

**Ownership + patterns compose**: an R63-stamped
`ownership_pattern` entry survives R74 round-trip through
the `#OWNERSHIP v1` section already; the pattern registry
survives through `#PATTERN v1`. After
save/restart/load, a bob who couldn't see alice's authored
pack before still can't — the ownership overlay stops him
in `pattern.list` + `coding_helper` (R63/R64) exactly as
before the restart.

### 7.25 Skill registry round-trip via session snapshots (R75)

R73 (policy registry) and R74 (pattern registry) closed the
persistence gap for those two boot-time-only registries. R75
finishes the arc with the R55.1 skill registry — skills
registered via `skill.install` (both pre-anchored + signed
variants) now survive daemon restart.

Snapshot format gets a `#SKILL v1` section that captures
manifest identity + install marker:

```
#SKILL v1
SKILL research 1.0.0 2 1 1
DESC walk KGs for topic-token label matches
EFFECTOR effector_read_kg
EFFECTOR effector_search
DEP solar_system:1.0.0
REFUSAL 1:400
SKILL coding_helper 1.0.0 3 1 0
DESC pattern-match debug problems
EFFECTOR effector_pattern_match
```

The `SKILL <name> <ver> <policy_id> <tier> <installed>` line
carries the identity + install-flag; `DESC` / `EFFECTOR` /
`DEP` / `REFUSAL` capture the rest. Supervisors are NOT
serialized (they hold live refs to kg/capsule/mo/persona
registries the snapshot doesn't own) — the load side ships
the installed-flag names back to the wire caller so the
daemon can rebuild supervisors from its live context.

Wire responses carry `skills` + `skills_installed_names`:

```bash
scripts/rpc.sh session.save name my_daemon
# -> {"ok":true,"result":{
#      ...
#      "patterns":3, "skills":3,
#      ...}}

scripts/rpc.sh session.load name my_daemon
# -> {"ok":true,"result":{
#      ...
#      "patterns":3,
#      "skills":3,
#      "skills_installed_names":["research","coding_helper"],
#      ...}}
```

`skills_installed_names` is the list of manifests marked
INSTALLED in the snapshot. A wire caller iterates it and
calls `skill_registry_install` per name with a fresh
supervisor built from the ctx's live registries — this
re-hydrates the install state that the manifest+register
step alone can't restore.

**Last-write-wins on name** (matches R73/R74 semantics).
Reloading a snapshot that contains `research` over the
compile-time built-in is a no-op when the content matches;
an operator's hand-edit gets honored.

**Lenient parser** — bad `SKILL` line (fewer than 5 tokens)
drops that skill; orphan `EFFECTOR`/`DEP`/`REFUSAL` (before
any `SKILL` opener) is dropped; unknown directives inside a
skill are skipped without aborting the parse.

**New signature** (backward-compat wrappers preserved):

```
session_snapshot_serialize_ex(persona_reg, cap_reg, trust_reg,
                              overlay, policy_reg, skill_reg,
                              include_secrets, now)
session_snapshot_apply_ex(text, persona_reg, cap_reg, trust_reg,
                          overlay, policy_reg, skill_reg, now)
```

The 6-arg `session_snapshot_serialize` and
`session_snapshot_apply` still work — they delegate with
`policy_reg=0` and `skill_reg=0` so no `#POLICY v1` /
`#SKILL v1` section is written or read on the legacy path.

**Persistence arc complete**: every registry the daemon
owns now round-trips through `session.save` / `session.load`
— personas (R55.3), capability tokens (R55.3), trust anchors
(R55.3), ownership overlay (R55.3), policies (R73), patterns
(R74), skills (R75). An operator can `session.save`, restart
the daemon, `session.load`, and every piece of state comes
back consistent.

### 7.26 session.list wire verb (R76)

R73-R75 completed the persistence arc but an operator still had
no wire way to enumerate existing snapshots — knowing what
names were available meant shelling out to `ls`. R76 closes
that gap with a `session.list` verb.

```bash
scripts/rpc.sh session.list
# -> {"ok":true,"result":[
#      {"name":"nightly-2026-08-12","path":"/var/lib/cxe/nightly-2026-08-12.snap",
#       "bytes":48231,"saved_at":11440820},
#      {"name":"before-migration","path":"/var/lib/cxe/before-migration.snap",
#       "bytes":48944,"saved_at":11441105}]}
```

Cap: `admin:session` (same as `session.save` + `session.load`).

**Directory index implementation.** NOVA exposes
`sys_open`/`read`/`write`/`fstat`/`unlink` but has no
`readdir`/`getdents`. Rather than parse raw dirent bytes,
R76 keeps a small text index at `<snapshot_dir>/index.txt`:

```
<name>\t<bytes>\t<saved_at>
<name>\t<bytes>\t<saved_at>
...
```

`session.save` upserts the entry (last-write-wins on name)
after successfully writing the `.snap` payload atomically.
`session.list` reads the index, splits by newline, and
returns the entries in insertion order (matches save order).
The tradeoffs:

- **Cross-daemon integrity**: only the daemon writes the
  index. If an operator deletes a `.snap` file with `rm`
  outside the daemon, `session.list` still shows the entry
  (subsequent `session.load` returns "read failed"). Manual
  ops should either use the daemon or maintain the index by
  hand.
- **Missing index = empty list** (not an error) — that's
  the natural "fresh install, no snapshots yet" case.
- **Malformed index lines** dropped silently by the parser;
  a corrupt index yields an empty list + `ok:true`. The
  index rebuilds itself on the next `session.save`.

The index file is a separate concern from any single `.snap`
payload — the `.snap` files themselves remain the source of
truth for state, the index is metadata for enumeration.

### 7.27 session.delete wire verb (R77)

R76 gave operators a way to enumerate snapshots. R77 lets them
prune stale ones without shell access:

```bash
scripts/rpc.sh session.delete name old-backup
# -> {"ok":true,"result":{
#      "name":"old-backup",
#      "path":"/var/lib/cxe/old-backup.snap",
#      "deleted":true,
#      "index_removed":true}}
```

Cap: `admin:session` (same as save/load/list).

**Idempotent** — a name whose `.snap` is already gone (or was
never registered) returns `ok:true` with
`deleted:false`/`index_removed:false`. This matches the
operator intuition of `rm -f <name>.snap` — the goal is "make
sure this is gone", not "assert the file exists".

**Response semantics**:

| field | meaning |
|---|---|
| `deleted`       | `sys_unlink` succeeded on the `.snap` file |
| `index_removed` | the R76 index had an entry for this name and it was rewritten without it |

Both booleans reflect independent successes, so an operator
can detect "index was stale, file was already gone" vs
"first-ever delete of an existing snapshot".

**Refusals** — mirror `session.save`/`session.load`:

- No snapshot dir configured
- Missing `name` arg
- `name` fails the shared `_rpc_snap_name_check` (traversal,
  disallowed chars, empty, `.`/`..`)
- Reader-role token refused by cap gate (`admin:session`)

**Not atomic across processes** — two concurrent
`session.delete` calls against the same name race; the daemon
is single-threaded per-connection and admin ops are
low-frequency, so this is fine.

### 7.28 admin.rotate_token wire verb (R78)

R55 shipped `capability.issue`/`revoke`/`list`. R78 adds
one more: **`admin.rotate_token`** — mint a fresh bearer
ID for a live token while preserving everything else
(holder, caps, expiry, revocation state, rate-limit
window).

The use case: a token ID appears in a log, a paste, or a
compromised client image. The operator wants to keep the
token's IDENTITY (alice's admin token stays alice's admin
token) but wants a new bearer secret.

```bash
scripts/rpc.sh admin.rotate_token token_id "tk-carol-old-id"
# -> {"ok":true,"result":{
#      "old_token_id":"tk-carol-old-id",
#      "new_token_id":"1f8a3e0b9c7d4562...", (32 hex chars)
#      "holder":"carol"}}
```

Cap: `admin:sandbox` (same as R55 capability verbs).

**In-place rotation** — the token record's `TOK_ID` slot is
mutated. Every other slot stays pointer-identical: caps
list, holder, issued_at, expires_at, revoked flag, qps_max,
current-window state (R56). A subsequent
`capability_registry_lookup(reg, new_id)` returns THE SAME
token record; the old_id is now unknown.

**Refusals**:

- No capability registry wired
- Missing `token_id` arg
- Unknown `token_id` (already rotated or typo)
- Reader-role refused by cap gate (`admin:sandbox`)

**Response transport**: both the old and new IDs are bearer
secrets. The wire response echoes them in cleartext because
the operator NEEDS to know the new one to redistribute.
Ship this call only over a secure channel (loopback socket
or the R54.1 TLS sidecar) — the verb itself doesn't add
extra confidentiality.

### 7.29 admin.set_qps wire verb (R79)

R56 shipped per-token rate limits. Setting `qps_max` was
only possible at `capability.issue` time -- changing a live
token's ceiling meant revoke + re-issue, which churns the
bearer id. R79 adds `admin.set_qps` so a rate-limit ceiling
can be dialed up or down in place.

```bash
scripts/rpc.sh admin.set_qps token_id "tk-gina" qps_max 100
# -> {"ok":true,"result":{
#      "token_id":"tk-gina","holder":"gina",
#      "old_qps_max":0,"new_qps_max":100}}

# Zero means "unlimited" (matches R56 semantics; a change back
# to 0 removes the ceiling).
scripts/rpc.sh admin.set_qps token_id "tk-gina" qps_max 0
```

Cap: `admin:sandbox` (same as R55 / R78).

**In-place mutation + window reset**: R56's underlying
`token_set_qps_max` updates the `TOK_QPS_MAX` slot AND
resets `TOK_WINDOW_START_NANOS` + `TOK_WINDOW_COUNT` to 0.
The new ceiling takes effect on the very next request
without carrying credit or debt from the old ceiling. Every
other slot (id, holder, caps, expiry, revocation flag)
stays pointer-identical.

**Refusals**:

- No capability registry wired
- Missing `token_id` / `qps_max` args
- `qps_max` is negative (`str_to_int` returns 0 for garbage;
  accepting "0" as intentional "unlimited" and rejecting only
  negatives keeps the ambiguity on the safer side)
- Unknown `token_id`
- Reader-role refused by cap gate

### 7.30 capability.list echoes live rate-limit window state (R80)

R56 shipped per-token rate limits; R79 made them mutable at
runtime. But `capability.list` gave operators no way to see
whether the ceilings mattered — a token with `qps_max=1000`
but only 2 req/s of real traffic doesn't need to be rate-
limited, and there was no wire signal to notice.

R80 adds two fields to every entry in the `capability.list`
response:

| field | meaning |
|---|---|
| `window_count`       | requests observed in the CURRENT 1-second window. Meaningful only when `qps_max > 0`. |
| `window_start_nanos` | `nanotime` when the current window opened (`0` if the token hasn't been used yet, or `qps_max=0`). |

Combined with `qps_max` (already in the response since R56),
an operator can tell at a glance:

- **Ceiling not binding** — `window_count << qps_max`
  consistently → dial `qps_max` down via R79 `admin.set_qps`
- **Running hot** — `window_count` frequently near `qps_max`
  → dial `qps_max` up
- **Dormant** — `window_start_nanos == 0` → token isn't
  seeing traffic; candidate for `capability.revoke`

The response envelope is a pure addition — every prior R55
field stays byte-identical for backward-compat.

```bash
scripts/rpc.sh capability.list
# -> {"ok":true,"result":[
#      {"holder":"alice","caps":["nl:ask","kg:read",...],
#       "issued_at":11440820,"expires_at":0,"revoked":false,
#       "qps_max":100,"window_count":47,
#       "window_start_nanos":1755060742394817293},
#      {"holder":"bob-svc","caps":["nl:ask","skill:run"],
#       "issued_at":11440900,"expires_at":0,"revoked":false,
#       "qps_max":10,"window_count":0,
#       "window_start_nanos":0}]}
```

`token_id` still omitted from the response — bearer secret.
An audit surface for "which tokens exist for holder X" via
a hashed id remains R81+ scope.

### 7.31 admin.set_expires wire verb (R81)

Third live-token knob alongside R78 `admin.rotate_token`
(change bearer id) and R79 `admin.set_qps` (change rate
ceiling). R81 lets an operator extend or shorten a token's
expiry without minting a new token — useful for time-limited
delegations, emergency expiration, or extending a long-running
service token past its original cutoff.

```bash
# Extend from expires_at=0 (never) to a specific moment
scripts/rpc.sh admin.set_expires token_id "tk-service-01" expires_at 5000000
# -> {"ok":true,"result":{
#      "token_id":"tk-service-01","holder":"service-01",
#      "old_expires_at":0,"new_expires_at":5000000}}

# Remove the ceiling (make it never-expires)
scripts/rpc.sh admin.set_expires token_id "tk-service-01" expires_at 0

# Emergency: expire immediately (any expires_at < current `now`
# makes the token non-live on the next authorize check without
# needing capability.revoke)
scripts/rpc.sh admin.set_expires token_id "tk-suspected-leak" expires_at 1
```

Cap: `admin:sandbox`. Refusals mirror R78/R79: no cap
registry, missing args, negative `expires_at`, unknown
`token_id`, reader-role refused by cap gate.

**Semantics**:

| `expires_at` value | effect |
|---|---|
| `0`                    | token never expires (R54 default) |
| `> now`                | token live until that moment |
| `< now` (or `== now`)  | token immediately non-live on next authorize |

Revoked state is **independent** of expiry. A revoked token
stays refused regardless of a fresh expiry (revoked check
runs first in `token_is_live`). To "un-revoke" without
recycling the token, use R78 `admin.rotate_token` — rotate
preserves everything else, and mis-revocation is a rare
operator error.

**Live-token-knob trio complete** (R78 + R79 + R81):

| verb | changes | preserves |
|---|---|---|
| `admin.rotate_token` | `token_id`                | holder, caps, expiry, revoked, qps, window |
| `admin.set_qps`      | `qps_max` (+ resets window) | token_id, holder, caps, expiry, revoked |
| `admin.set_expires`  | `expires_at`              | token_id, holder, caps, revoked, qps, window |

An operator can now tune any dimension of a live token
individually. `capability.revoke` remains the one-way kill
switch.

### 7.32 admin.grant_cap + admin.remove_cap wire verbs (R82)

R78/R79/R81 made token id, rate ceiling, and expiry mutable
in place. R82 closes the arc by adding cap-set mutation.
An operator can now tune EVERY dimension of a live token
without recycling.

```bash
# Grant a cap (idempotent -- granted=false if already present).
scripts/rpc.sh admin.grant_cap token_id "tk-tara" cap "skill:run"
# -> {"ok":true,"result":{
#      "token_id":"tk-tara","holder":"tara","cap":"skill:run",
#      "granted":true,
#      "caps":["nl:ask","kg:read","capsule:read","skill:read",
#              "persona:read","skill:run"]}}

# Remove a cap (idempotent -- removed=false if absent).
scripts/rpc.sh admin.remove_cap token_id "tk-uma" cap "nl:ask"
# -> {"ok":true,"result":{
#      "token_id":"tk-uma","holder":"uma","cap":"nl:ask",
#      "removed":true,
#      "caps":["kg:read","capsule:read","skill:read","persona:read"]}}
```

Both verbs: cap `admin:sandbox`.

**grant_cap validates against the 13 well-known caps**
(nl:ask, kg:read, capsule:read/install, skill:read/run/install,
persona:read/write, ingest:review/decide, admin:sandbox/session).
Typos like `"cap":"skil:run"` refuse with `"unknown cap: ..."`.
Otherwise a typo'd cap would sit in the token's list where
no verb's required-cap lookup would ever match it.

**remove_cap does NOT validate** — an operator might be
cleaning up a legacy token with a stale cap from an older
schema; refusing on "unknown cap" here would prevent that
cleanup. `remove` should always succeed at removing whatever's
there.

**Live-token-knob quartet complete** (R78 + R79 + R81 + R82):

| verb | changes | preserves |
|---|---|---|
| `admin.rotate_token` (R78) | `token_id`   | holder, caps, expiry, revoked, qps, window |
| `admin.set_qps` (R79)      | `qps_max` (+ resets window) | id, holder, caps, expiry, revoked |
| `admin.set_expires` (R81)  | `expires_at` | id, holder, caps, revoked, qps, window |
| `admin.grant_cap` (R82)    | `caps` (add) | id, holder, expiry, revoked, qps, window |
| `admin.remove_cap` (R82)   | `caps` (rm)  | id, holder, expiry, revoked, qps, window |

Only `holder` is truly immutable (an admin who needs to
change a token's holder mints a new one via
`capability.issue`). `capability.revoke` remains the one-way
kill switch; a mis-revoke can be recovered via
`admin.rotate_token` which resets the revoked flag as a
side effect of preserving nothing about revocation (well —
actually it doesn't touch the revoked slot; a rotated token
stays revoked. The right recovery is a fresh
`capability.issue`. Rare enough.)

### 7.33 admin.set_revoked wire verb (R83)

`capability.revoke` (R55) is a one-way kill switch — great
for "I know this token is compromised" but wrong for the
mis-revoke case where an operator accidentally revoked a
live token and needs to restore it. Before R83 the only
recovery was a fresh `capability.issue`, which mints a new
token id and breaks audit continuity.

R83 adds `admin.set_revoked` — the audit-pure reversible
alternative. The token's identity (id, caps, holder,
expiry, rate limit, window state) all stay intact; only
the `revoked` flag flips.

```bash
# Un-revoke a mis-revoked token.
scripts/rpc.sh admin.set_revoked token_id "tk-wanda" revoked 0
# -> {"ok":true,"result":{
#      "token_id":"tk-wanda","holder":"wanda",
#      "old_revoked":true,"new_revoked":false}}

# Revoke via the admin knob (equivalent to capability.revoke
# but with the mutable audit shape -- useful when a workflow
# needs symmetric revoke+un-revoke).
scripts/rpc.sh admin.set_revoked token_id "tk-xander" revoked 1
```

Cap: `admin:sandbox`.

**Refusals**: no cap registry, missing args, `revoked` not
exactly `"0"` or `"1"` (rejects `"2"`, `"-1"`, `"true"`,
non-numeric — `str_to_int` returns 0 for garbage so we
require the literal `"0"`/`"1"` string), unknown token_id,
reader-role refused by cap gate.

**Idempotent**: setting the same value returns
`old_revoked == new_revoked` and the token stays as-is.

**Note**: this doesn't retroactively help a request that
already hit `capability_authorize` and got `"capability
required: token revoked"` — that request stays refused.
Only SUBSEQUENT requests benefit from the state change.

**Live-token-knob quintet complete** (R78 + R79 + R81 + R82 + R83):
every dimension of a token is mutable at runtime except
`holder`. The only truly one-way surface left is
`capability.issue` itself (minting new tokens) and there's
no reason to want that reversed — an admin who wants to
"un-mint" a token uses `capability.revoke` (or
`admin.set_revoked` if they might change their mind later).

| verb | changes | preserves |
|---|---|---|
| `admin.rotate_token` (R78) | `token_id` | everything else |
| `admin.set_qps` (R79)      | `qps_max` + resets window | id, holder, caps, expiry, revoked |
| `admin.set_expires` (R81)  | `expires_at` | id, holder, caps, revoked, qps, window |
| `admin.grant_cap` (R82)    | `caps` (add) | id, holder, expiry, revoked, qps, window |
| `admin.remove_cap` (R82)   | `caps` (rm)  | id, holder, expiry, revoked, qps, window |
| `admin.set_revoked` (R83)  | `revoked`    | id, holder, caps, expiry, qps, window |

### 7.34 admin.set_holder wire verb (R84)

R84 closes the live-token-knob loop. Before R84 the ONLY way to
change a token's holder was to `capability.revoke` it and mint a
fresh one via `capability.issue` — which broke audit continuity
(the token id changed, so every downstream log entry keyed on
that id became orphaned) and required the new owner to redeploy
whatever pinned the old bearer string. `admin.set_holder`
reassigns the token's ownership pointer IN PLACE. The id, caps,
expiry, revoked flag, rate ceiling, and mid-window count all
stay put; only the `holder` slot moves.

The intended use case is an **ops handoff** — team A's service
account rolls to team B without disturbing anything else:

```bash
# Team A -> team B, keeping tk-svc-42's audit identity.
scripts/rpc.sh admin.set_holder token_id "tk-svc-42" holder "team_b"
# -> {"ok":true,"result":{
#      "token_id":"tk-svc-42",
#      "old_holder":"team_a","new_holder":"team_b"}}
```

Cap: `admin:sandbox`.

**Refusals**: no cap registry, missing args, empty `holder`
(a token with no owner would silently anonymize ownership
checks — refuse pre-mutation), unknown `token_id`,
reader-role refused by cap gate.

**Idempotent**: reassigning to the current holder returns
`old_holder == new_holder` and the token is untouched.

**Rate-limit window NOT reset**: the new holder inherits the
old holder's mid-window count. This is intentional — a
malicious operator cannot burn a rate ceiling and then hand
off to reset the budget. If a genuine reset is wanted, follow
up with `admin.set_qps` which does reset the window as a side
effect.

**Live-token-knob sextet complete** (R78 + R79 + R81 + R82 + R83 + R84):
every dimension of a capability token — including `holder` —
is now mutable at runtime without minting a new token. The
only truly one-way surface left is `capability.issue` itself
and there is no reason to want that reversed.

| verb | changes | preserves |
|---|---|---|
| `admin.rotate_token` (R78) | `token_id`   | everything else |
| `admin.set_qps` (R79)      | `qps_max` + resets window | id, holder, caps, expiry, revoked |
| `admin.set_expires` (R81)  | `expires_at` | id, holder, caps, revoked, qps, window |
| `admin.grant_cap` (R82)    | `caps` (add) | id, holder, expiry, revoked, qps, window |
| `admin.remove_cap` (R82)   | `caps` (rm)  | id, holder, expiry, revoked, qps, window |
| `admin.set_revoked` (R83)  | `revoked`    | id, holder, caps, expiry, qps, window |
| `admin.set_holder` (R84)   | `holder`     | id, caps, expiry, revoked, qps, window |

### 7.35 YAML ingest adapter (R85)

R65 shipped a JSON structured-record adapter (§7.17) and R66/R67
put every importer on the `ingest.file` wire (§7.18). R85
completes the "config-shaped pack" side of that story with a
YAML adapter — a hand-rolled YAML 1.2 SUBSET parser under
`src/ingest/importers/yaml_records.nova` that produces exactly
the same curriculum records the JSON adapter produces. This
matters because operator-authored records packs are the
common case, and YAML's indentation + comments read cleaner
by hand than JSON's `{}`/`""` scaffolding.

The parser is a **strict subset** by design. A partial YAML
parser that silently drops anchors would be a worse operator
experience than "the doc uses `&anchor`, refuse it clearly and
tell the operator to pre-convert with `yq -p yaml -o json`".

**Subset supported:**

- Top-level list of records (`- kg: ...`)
- Top-level `records:` key holding such a list
- Bare-string, single-quoted, and double-quoted scalars
  (`\n \t \r \" \\ \/` escapes)
- Integer scalars (optional leading `-`)
- Boolean scalars (`true` / `false`)
- Null (`null`, `~`, or an empty value after `key:`)
- One-level nested mappings inside a record (e.g. `capsule:`)
- Nested lists of mappings (`atoms:`, `implications:`, ...)
- Comments starting with `#` (bare column-0 or space-preceded)
- Indentation: **strictly 2 spaces per level** — any tab
  anywhere on a line refuses the parse; odd-column indent
  refuses the parse

**Explicitly rejected** (per-parse error, nothing lands):

- Anchors (`&anchor`) and aliases (`*anchor`)
- Multi-document streams (`---` after any content); a leading
  `---` on the very first line is tolerated as an optional
  first-doc header
- Flow-style sequences (`[a, b]`) and mappings (`{k: v}`)
- Block scalars (`|` and `>`)
- Tags (`!!str`, `!custom`)
- Merge keys (`<<:`)

**Wire integration** — the `ingest.file` verb (§7.18) dispatches
`format: yaml` to `yamlr_parse_text(body, kg_hint, source_tag)`.
`kg` + `source` args default in for records that omit them, per-
record values override, all of the R71 KG + capsule ownership
auto-assignment (§7.21) applies unchanged — the yaml body is
just another `records[]` source once the parser is done. Same
trust/queue split, same `force_queue` bypass, same
`records_refused_by_ownership` echo.

**source_registry** — `reg_source_install_defaults` now
registers `yaml` → `src:yaml:` (FMT_YAML = 10); the format
count is 10.

Example:

```bash
scripts/rpc.sh ingest.file \
  format yaml \
  body "$(cat data/packs/samples/climate_facts.yaml)"
# -> {"ok":true,"result":{
#      "format":"yaml",
#      "records_parsed":1,
#      "records_queued":1,     # src:yaml: is not in the default
#                              # trusted prefix list -> review queue
#      "atoms_added":0,
#      ...}}
```

Shipped: `data/packs/samples/climate_facts.yaml` — the same 10
atoms + 7 implications + 3 observations + 2 citations as the
R65 JSON sample, so operators can diff the two side-by-side.

### 7.36 In-process TLS scaffolding (R86)

**Honest status: wire is still cleartext.** R86 lays the module
skeleton, connection-state enum, alert enum, and wire-integration
seam for an in-process TLS 1.3 implementation. No cryptographic
operation runs. Operators who need TLS today keep using the R54.1
sidecar recipe.

Why an in-process implementation matters: the R54.1 stunnel sidecar
terminates TLS in a separate process and hops to the daemon over
loopback in cleartext. On a shared-tenancy box (the daemon co-tenants
with other users), any co-tenant that can read `lo` sees the
capability tokens and every wire payload. A daemon that speaks TLS
directly closes that gap and drops one process from the supervision
tree.

R86 ships:

- `src/net/tls/tls_alerts.nova` — **fully implemented**: the RFC 8446
  §6 alert enum (all 27 codes), a `tls_alert` struct, byte-buffer
  serialize / parse (the wire form is 2 bytes and one of them may be
  NUL, so it uses `[buf, len]` pairs the way
  `src/safety/chacha20.nova` does, not NOVA strings).
- `src/net/tls/tls_state.nova` — connection-state enum (INIT ->
  HANDSHAKE_HELLO_SENT | HANDSHAKE_HELLO_RECEIVED -> FINISHED ->
  APPLICATION -> CLOSING -> CLOSED) with a full legal-transition
  table and a `tls_state_ctx` holder. No crypto; the state machine
  is testable now.
- `src/net/tls/tls_config.nova` — server-side material holder (cert
  DER, key DER, cipher preference, session-cache size). Empty by
  default; nothing today constructs one with real material.
- `src/net/tls/tls_record.nova` — record-layer header (5-byte parse /
  serialize, fully implemented; the header can carry NUL bytes so it
  uses `[buf, len]` too). Body wrap/unwrap are `TLS_NOT_IMPLEMENTED`
  stubs (R94 fills in).
- `src/net/tls/tls_handshake.nova` — handshake type enum + a
  message struct stub. All per-type parsers/serializers return
  `TLS_NOT_IMPLEMENTED` (R93 fills in).
- `src/net/tls/tls_wire_hook.nova` — the one seam the daemon calls:
  `wire_connection_wrap(fd, tls_config)`. When `tls_config == 0`
  (always, today) it returns the raw fd unchanged. The daemon's
  accept loop now routes through it so R94 flips the semantics
  without a second daemon change.

**Chosen algorithm suite** (justified in the ADR):

- Cipher: `TLS_CHACHA20_POLY1305_SHA256` — a single integer-only
  suite avoids the constant-time AES S-box problem in a language
  without SIMD or CLMUL.
- Key exchange: `x25519` — a single 255-bit prime field, no NIST
  point-format serialization.
- Signature: `ed25519` — deterministic (no CSPRNG dependency at the
  signing side), same field as the KX.
- KDF: `HKDF-SHA-256`.
- Cert: DER-encoded X.509 subset (Subject / SubjectPublicKeyInfo /
  Validity / SignatureAlgorithm / Signature); chain length <= 2 in
  the first cut.

**Phased build-out roadmap** (see ADR
`docs/adr/r86-in-process-tls-scaffolding.md` for the full inventory):

| Phase | What lands |
|---|---|
| R87 | Random-source seam; wire-integer serializers |
| R88 | ChaCha20 block function + Poly1305 MAC (RFC 7539 vectors) |
| R89 | x25519 field arithmetic + Montgomery ladder (RFC 7748) |
| R90 | HKDF-SHA-256 + TLS 1.3 key schedule |
| R91 | X.509 DER subset parser |
| R92 | ed25519 verify |
| R93 | Handshake state-machine wire-up |
| R94 | **First round where in-process TLS is usable** — AEAD wrap/unwrap; `wire_connection_wrap` starts returning a real wrapped_conn |
| R95 | Trust-anchor registry + cert chain validation |
| R96 | Session-ticket resumption |
| R97 | Alert delivery on live connections; close_notify |
| R98..R9X | Hardening / audits / fuzz |

**Missing runtime capabilities** (documented in the ADR; blocking
each phase from starting): a CSPRNG source (blocks R87 first-cut) and
non-blocking accept + poll (blocks multi-connection TLS at R94+).
NOVA runtime is off-limits per the standing constraint; the CrossEngin
side implements every field-arithmetic and DER primitive as a source
file, so no runtime change is required for the non-random / non-poll
parts of the roadmap.

### 7.37 ChaCha20-Poly1305 AEAD (R87)

**Honest status: wire is still cleartext.** R87 lands the first real
crypto brick under R86's TLS scaffold — a pure-NOVA
ChaCha20-Poly1305 AEAD (RFC 8439 §2.8) — and wires it into the TLS
1.3 record-layer body per RFC 8446 §5.2 + §5.3. The wire hook
(`wire_connection_wrap`) is still a pass-through: the handshake state
machine has to land (R92) and be flipped on (R93) before a live
connection encrypts anything. Operators who need TLS today keep
using the R54.1 sidecar recipe.

What shipped in R87:

- `src/safety/poly1305.nova` — the Poly1305 one-time authenticator
  (RFC 8439 §2.5), already in tree from earlier work; R87 extended
  the test coverage to 56 checks including all RFC §2.5.2 + Appendix
  A.3 test vectors plus clamp bit-boundary verification, exact and
  partial block boundaries, and constant-time compare unit tests.
- `src/safety/chacha20_poly1305.nova` — **NEW.** The AEAD
  construction that combines the existing ChaCha20 stream cipher
  (`src/safety/chacha20.nova`) with Poly1305:
  - `caead_seal_buf(key32, nonce12, aad, aad_len, pt, pt_len)`
    → `[ct_buf, ct_len, tag_buf]`. Derives the one-time Poly1305
    key from ChaCha20 counter=0 per RFC 8439 §2.6.2, encrypts the
    plaintext at counter=1, tags `pad16(aad) || pad16(ct) ||
    le64(|aad|) || le64(|ct|)`.
  - `caead_open_buf(key32, nonce12, aad, aad_len, ct, ct_len, tag)`
    → `[pt_buf, pt_len, ok]`. Recomputes the tag, compares in
    constant time; on mismatch returns `ok = 0` and a NUL buffer
    (never releases plaintext).
  - `caead_ct_eq_buf(a, b, n)` — constant-time byte-buffer equality.
    Exposed for reuse.
- `src/net/tls/tls_record.nova` — **extended.** The R86 header
  parse/serialize path stays; R87 adds:
  - `tls_record_seal_buf(key32, iv12, seq_num, inner_type, pt, pt_len)`
    → `[rec_buf, rec_len]`. Builds a TLS 1.3 TLSCiphertext record:
    5-byte header || ciphertext || 16-byte tag. Inner content type
    rides as the trailing byte of the plaintext (RFC 8446 §5.2
    TLSInnerPlaintext.type). The record header IS the AAD.
  - `tls_record_open_buf(key32, iv12, seq_num, rec_buf, rec_len)`
    → `[pt_buf, pt_len, inner_type, ok]`. Parses the header,
    reconstructs the per-record nonce, verifies the tag in constant
    time, strips the inner-type byte. On any failure (short buffer,
    header disagreement, tag reject) returns a NUL plaintext + ok=0.
  - `tls_record_build_nonce(iv12, seq_num)` — per-record nonce =
    seq_num (right-aligned big-endian in 12 bytes) XOR iv (RFC 8446
    §5.3).
  - `tls_record_seq_new / _get / _next / _reset` — per-direction
    64-bit sequence-number counter. Resets on key change, refuses to
    advance if it ever goes negative (nonce-reuse guard).

Test vectors verified:

| Test vector | Where | Status |
|---|---|---|
| Poly1305 §2.5 clamp bit-mask | test_poly1305 | ✅ |
| Poly1305 §2.5.2 canonical MAC | test_poly1305 | ✅ |
| Poly1305 Appendix A.3 #1 (zero key + zero msg → zero tag) | test_poly1305 | ✅ |
| ChaCha20-Poly1305 §2.8.2 "Sunscreen" (seal + open) | test_chacha20_poly1305 | ✅ |
| ChaCha20-Poly1305 Appendix A.5 (265-byte plaintext + long AAD) | test_chacha20_poly1305 | ✅ |

Test totals (R87 delta): poly1305 grew from 9 → 56 checks;
chacha20_poly1305 landed at 55 checks; tls_record_aead landed at 53
checks. Regression sweep across R86 tests (`test_chacha20`,
`test_tls_alerts`, `test_tls_state`, `test_tls_scaffold`) +
`test_capability_wire` + `test_nl_rpc_verbs` all green.

**Nonce-reuse hazard.** ChaCha20-Poly1305 is catastrophically broken
by nonce reuse under the same key: two records with the same
(key, nonce) leak the XOR of both plaintexts AND enable Poly1305
key recovery. The TLS 1.3 per-record nonce discipline (seq XOR iv,
seq monotonically increasing, resets only on key change) guarantees
uniqueness. Do not reuse the `caead_*` primitives in any protocol
without a comparable discipline; the module docstring says the same.

### 7.38 HKDF-SHA-256 + TLS 1.3 key-schedule wrappers (R88)

**Honest status: key-schedule primitives are ready; the handshake is
still stubbed and the wire is still cleartext.** R88 lands the KDF
brick R92 (handshake wire-up) and R93 (wire-hook flip) both need
before an in-process TLS deployment can encrypt bytes. The
`wire_connection_wrap` hook remains a pass-through.

What shipped in R88:

- `src/safety/hkdf_sha256.nova` — **NEW.** Generic HKDF-SHA-256 per
  RFC 5869:
  - `hkdf_extract(salt, salt_len, ikm, ikm_len) -> 32-byte PRK`.
    When `salt_len == 0` the RFC 5869 §2.2 zero-salt substitution
    (32 zero bytes) is materialized internally, so callers can
    pass `(0, 0)` for "no salt".
  - `hkdf_expand(prk, prk_len, info, info_len, out_len) ->
    [okm_buf, okm_len]`. Implements the T(i) chain from §2.3 with
    the RFC's 255-HashLen (== 8160-byte) ceiling. Requests >8160
    bytes and negative lengths return `okm_len = 0` (refusal).
  - `hkdf_sha256(salt, salt_len, ikm, ikm_len, info, info_len, out_len)
    -> [okm_buf, okm_len]`. Extract-then-Expand convenience.
- `src/net/tls/tls_kdf.nova` — **NEW.** TLS 1.3 key-schedule
  wrappers per RFC 8446 §7.1 + §7.3:
  - `tls_kdf_hkdf_label_bytes(length, label, label_len, ctx, ctx_len)
    -> [buf, len]`. Serializes the `HkdfLabel` struct verbatim
    (big-endian uint16 length, 1-byte-prefixed label with the
    "tls13 " prefix, 1-byte-prefixed context).
  - `tls_kdf_hkdf_expand_label(secret, sec_len, label, label_len,
    context, ctx_len, length) -> [okm_buf, okm_len]`. Validates
    label / context / length against the RFC 8446 bounds, then
    hands off to `hkdf_expand`.
  - `tls_kdf_derive_secret(secret, sec_len, label, label_len,
    messages, msg_len) -> [okm_buf, okm_len]`. Composes
    `Transcript-Hash(messages) = SHA-256(messages)` into the
    context field per RFC 8446 §7.1.
  - `tls_kdf_derive_key_iv(secret, sec_len) -> [key32, iv12]`. The
    per-direction record-layer entry point (labels `"key"` /
    `"iv"`, empty context, 32-byte key and 12-byte IV sized for
    ChaCha20-Poly1305). This is what R92's handshake state
    machine will feed into `tls_record_seal_buf` /
    `tls_record_open_buf` once traffic secrets exist.
- **Prerequisites already in tree:** SHA-256 and HMAC-SHA-256 were
  shipped by R33A as `src/safety/sha256.nova` (streaming +
  one-shot + RFC 2104 HMAC). R88 does not re-implement either; it
  just imports.

Test vectors verified:

| Test vector | Where | Status |
|---|---|---|
| RFC 5869 Appendix A.1 (basic SHA-256) — PRK, OKM, combined | test_hkdf_sha256 | ✅ |
| RFC 5869 Appendix A.2 (80/80/80 byte inputs, 82-byte OKM) | test_hkdf_sha256 | ✅ |
| RFC 5869 Appendix A.3 (empty salt + empty info) | test_hkdf_sha256 | ✅ |
| Extract equivalence to HMAC(salt, ikm) + zero-salt substitution | test_hkdf_sha256 | ✅ |
| Boundary out_len ∈ {0, 32, 33, 8160}; refusal at 8161 and negative | test_hkdf_sha256 | ✅ |
| RFC 8448 §3 `early_secret` (HKDF-Extract(0^32, 0^32)) | test_tls_kdf | ✅ |
| RFC 8448 §3 `derived_from_early` via expand_label + derive_secret | test_tls_kdf | ✅ |
| HkdfLabel byte-serialization ("derived", "key", "iv" labels; big-endian length) | test_tls_kdf | ✅ |
| `derive_key_iv` matches manual expand_label with "key"/"iv" labels | test_tls_kdf | ✅ |
| RFC 8446 label bounds: refuse empty label, oversize label, oversize context, length > 65535 | test_tls_kdf | ✅ |

Test totals (R88 delta): hkdf_sha256 landed at 29 checks; tls_kdf
landed at 27 checks. Regression sweep across R86 + R87 suites
(`test_sha256`, `test_chacha20`, `test_chacha20_poly1305`,
`test_poly1305`, `test_tls_alerts`, `test_tls_state`,
`test_tls_scaffold`, `test_tls_record_aead`) + `test_capability_wire`
+ `test_nl_rpc_verbs` all green.

What R89 unlocks next: with HKDF in place, the remaining crypto
prerequisites for the handshake are x25519 (ECDH for the ephemeral
key), an X.509 subset parser, and ed25519 verification. R89 picks
up x25519; the field arithmetic is pure integer with no runtime
primitive missing.

### 7.39 x25519 ECDH (R89)

**Honest status: ECDH primitive is ready and byte-exact against RFC 7748;
the handshake is still stubbed, the wire is still cleartext, and the
RNG source needed to sample the ephemeral scalar is not yet wired.**
R89 lands the key-exchange half of the TLS 1.3 handshake without
touching the state machine or the wire hook -- both of those stay
where R86 left them.

What shipped in R89:

- `src/safety/field25519.nova` — **NEW.** GF(2^255 - 19) field
  arithmetic in the classic Bernstein 10-limb 26/25-bit layout
  (a.k.a. curve25519-donna / ref10). Constant-time throughout
  (data-independent branches, XOR-mask conditional swap, fixed
  addition-chain modular inverse). Exposes `fe_zero`, `fe_one`,
  `fe_copy`, `fe_add`, `fe_sub`, `fe_neg`, `fe_mul`, `fe_sq`,
  `fe_mul121666`, `fe_invert`, `fe_frombytes`, `fe_tobytes`,
  `fe_cswap`. Every intermediate product stays well inside NOVA's
  63-bit signed-positive integer range (worst-case fe_mul sum
  ~2^61, empirically fuzzed against `bignum_256`'s modmul over
  the same prime).
- `src/safety/x25519.nova` — **NEW.** X-only Curve25519 Montgomery
  ladder per RFC 7748 §5. Exposes:
  - `x25519_clamp_scalar(out, in)` — RFC 7748 clamp (bottom 3 bits
    clear, top bit clear, bit 254 set).
  - `x25519_scalarmult(out, scalar, u)` — raw scalar-mult (clamps
    the scalar, decodes u with high-bit mask, runs the ladder,
    inverts z_2 and encodes canonical bytes).
  - `x25519(out, scalar, u)` — scalar-mult with the RFC 7748 §6.1
    all-zero-shared-secret rejection: on a low-order u (u=0 or u=1)
    returns ok=0 and zeros out.
  - `x25519_base(out, scalar)` — public-key generation (u = 9).
- `src/net/tls/tls_keyshare.nova` — **NEW.** TLS-facing thin wrapper:
  - `tls_keyshare_x25519_public(pub, scalar)`.
  - `tls_keyshare_x25519_shared(shared, scalar, peer_pk)` — with
    the all-zero rejection propagated.
  - `tls_keyshare_derive_handshake_secret(shared, len, early, len)`
    — folds the shared secret into the RFC 8446 §7.1 key schedule
    at the `Derive-Secret(early, "derived", "") -> HKDF-Extract`
    transition, giving R92's handshake state machine the exact PRK
    it will feed into subsequent `Derive-Secret` calls.
  Length constants: `TLS_X25519_SCALAR_LEN = TLS_X25519_PUBLIC_LEN
  = TLS_X25519_SHARED_LEN = 32`.

Test vectors verified (byte-exact, all in `test_x25519` and
`test_tls_keyshare`):

| Test vector | Where | Status |
|---|---|---|
| RFC 7748 §5.2 scalar-mult test 1 (scalar=a546…, u=e6db…) | test_x25519 | ✅ |
| RFC 7748 §5.2 scalar-mult test 2 (scalar=4b66…, u=e521…) | test_x25519 | ✅ |
| RFC 7748 §5.2 iterated test after 1 iteration | test_x25519 | ✅ |
| RFC 7748 §5.2 iterated test after 1000 iterations | test_x25519 | ✅ |
| RFC 7748 §6.1 Alice public key from Alice sk | test_x25519, test_tls_keyshare | ✅ |
| RFC 7748 §6.1 Bob public key from Bob sk | test_x25519, test_tls_keyshare | ✅ |
| RFC 7748 §6.1 shared secret (Alice·Bob, both directions) | test_x25519, test_tls_keyshare | ✅ |
| RFC 7748 §6.1 low-order u=0 rejection (ok=0, zeroed out) | test_x25519, test_tls_keyshare | ✅ |
| Low-order u=1 rejection | test_x25519 | ✅ |
| RFC 7748 scalar-clamp idempotence and unclamped==clamped equivalence | test_x25519 | ✅ |
| CT-ladder determinism (two runs on identical input match bytewise) | test_x25519 | ✅ |
| GF(p25519) field-arithmetic identities (comm, assoc, distrib, inv) | test_field25519 | ✅ |
| fe_frombytes/fe_tobytes canonical roundtrip (0, 1, p-1, p→0, arbitrary) | test_field25519 | ✅ |
| fe_frombytes high-bit mask (0x80/0xFF top byte decodes same as masked) | test_field25519 | ✅ |
| fe_cswap(a, b, 0) no-op / fe_cswap(a, b, 1) swaps / double-swap restores | test_field25519 | ✅ |
| fe_sq(a) == fe_mul(a, a) byte-identical across seed set | test_field25519 | ✅ |
| fe_mul121666(a) == fe_mul(a, 121666_fe) | test_field25519 | ✅ |
| The RFC 7748 §5.2 1,000,000-iteration case is deliberately SKIPPED (optional; exceeds 60s test cap). | test_x25519 (noted) | -- |

NOVA-arithmetic decisions (why 10x(26/25) not 5x51):

- **Limb layout: 10 limbs alternating 26-bit and 25-bit windows
  (radix 2^25.5), the "curve25519-donna" / ref10 layout.** Chosen
  over 5x51 specifically to keep every fe_mul intermediate safely
  under NOVA's 63-bit signed-positive integer range. Worst-case
  fe_mul term: `2 * canonical_limb * (19 * canonical_limb) < 2^27
  * 2^30.25 = 2^57.3`; ten-term sum `~2^60.6`. 5x51 would push
  intermediates to ~2^108, requiring a split into hi/lo halves
  that NOVA's 63-bit arithmetic can't express in one word. The
  Bernstein 10-limb bound is well-studied and matches the classic
  reference implementations.
- **Reduction strategy: two sequential carry cascades (each
  h[0]->h[1]->...->h[9] with the 19*carry9 wrap folded back into
  h[0]).** Every fe_ operation ends canonical (h[even] in
  [0, 2^26), h[odd] in [0, 2^25)); the second cascade absorbs the
  wrap-induced growth in h[0]->h[1]->h[2].
- **Constant-time freeze in fe_tobytes: add 19 to a canonical h,
  sequentially cascade UP TO h[9] without applying the wrap, and
  inspect bit 25 of t[9] as the "h >= p" flag.** Then multiply-
  select between h and (t with top bit cleared) -- branch-free.
- **fe_sub folds through +4p limbs** ([2^28 - 76, 2^27 - 4,
  2^28 - 4, ..., 2^27 - 4]) so no intermediate goes negative
  (NOVA has no signed-integer wrap; a negative value would
  silently be interpreted as a very large positive).

RNG dependency (still open, not fixed in R89):
The keyshare functions take a caller-supplied 32-byte scalar. That
scalar MUST come from a CSPRNG for the shared secret to be secret.
The NOVA runtime does not yet expose `sys_getrandom`; R89 does not
add a random source. R92's handshake wire-up will need to close
this (either via a NOVA runtime addition or a stub-scalar-with-
audit-warning path). This is called out again in §12.

Test totals (R89 delta): field25519 landed at 37 checks;
x25519 at 15 checks; tls_keyshare at 14 checks. Regression sweep
across R86 + R87 + R88 suites (`test_hkdf_sha256`, `test_tls_kdf`,
`test_tls_record_aead`, `test_chacha20_poly1305`, `test_poly1305`,
`test_sha256`, `test_tls_alerts`, `test_tls_state`, `test_tls_scaffold`,
`test_capability_wire`, `test_nl_rpc_verbs`) all green.

What R90 unlocks next: ed25519 verify (RFC 8032). With ECDH landed
and ed25519 verify landed, the last crypto primitive gap before the
handshake state machine can be wired is X.509 parsing; R91 picks
that up.

### 7.40 Ed25519 verify + TLS cert-auth seam (R90)

**Honest status: verify-only Ed25519 is audited + widened; the TLS
cert-auth seam (`tls_cert_verify_input_build`, `tls_cert_verify`,
`tls_cert_verify_ed25519`) is callable and byte-exact against
RFC 8446 §4.4.3 for both server and client roles; handshake still
stubbed, X.509 not yet parsed (raw pubkey passed in), CSPRNG still
missing, wire still cleartext.** R90 is the LAST TLS primitive
round — every RFC-standardized primitive TLS 1.3 needs
(ChaCha20-Poly1305 AEAD, HKDF-SHA-256, x25519 ECDH, Ed25519 verify,
SHA-512) is now in tree. Remaining TLS work is orchestration
(handshake state machine, CSPRNG, X.509 parsing) plus the
wire-hook flip.

Audit finding on the pre-existing `src/safety/ed25519.nova` (shipped
in R54.2 for signed-skill install): the module already implements
RFC 8032 correctly — SHA-512 built inline (128-byte block, 80
rounds, 64-bit-as-`[lo32, hi32]` limb pairs so NOVA's arithmetic
sign-extension can't corrupt the round-function shifts); the verify
path decodes A and R via the standard sqrt-of-ratio trick and
rejects any y >= p (non-canonical encoding, RFC 8032 §5.1.3);
rejects any s >= L (RFC 8032 §5.1.7); uses a Montgomery-ladder
scalar-mult for bit-independent outer control flow. The verify
equation checked is `sB == R + kA` (strict, not the cofactor-8
batched form) — both are RFC 8032-compliant; strict verification
is the stricter of the two.

What shipped in R90:

- `src/safety/ed25519.nova` — **UNCHANGED.** Verify path audited
  against RFC 8032 §5.1.7 (verify algorithm) and §5.1.3 (point
  decoding). No changes to the primitive itself.
- `tests/unit/test_ed25519.nova` — **EXTENDED.** 45 -> 61 passing
  checks (+16 R90-added):
  - RFC 8032 TEST 2 and TEST 3 bit-flip coverage on message.
  - RFC 8032 TEST 3 bit-flip on R and pubkey.
  - `s == L` exactly rejected (spliced signature with s bytes = L
    in little-endian).
  - `s == L + 1` rejected.
  - Non-canonical A (all-0xFF pubkey → y = 2^255 - 1 > p) rejected.
  - Non-canonical R (all-0xFF R → y = 2^255 - 1 > p) rejected.
  - All-zero pubkey + arbitrary sig rejected.
  - Verify determinism: repeated calls on the same triple return
    the same 0/1 value (both accept and reject paths).
  - (Pre-existing sandbox quirk: the `ed25519_sign latency > 0`
    assertion has `nanotime()` returning 0 on this sandbox and
    fails; unchanged from R89. Not blocking any correctness
    coverage.)
- `src/net/tls/tls_cert.nova` — **NEW.** TLS 1.3 CertificateVerify
  seam (RFC 8446 §4.4.3):
  - `tls_cert_verify_input_build(transcript_hash, transcript_hash_len,
    is_server)` — assembles the 130-byte signed content: 64 octets
    of 0x20, the 33-byte context string ("TLS 1.3, server
    CertificateVerify" or "TLS 1.3, client CertificateVerify"),
    one 0x00 separator, then the transcript hash. Deterministic;
    no crypto.
  - `tls_cert_verify(cert_pubkey, signed_data, signed_data_len,
    signature)` — thin adapter over `ed25519_verify` with a
    signed_data_len parameter for the R93 handshake plumbing.
  - `tls_cert_verify_ed25519(cert_pubkey, transcript_hash,
    transcript_hash_len, is_server, signature)` — one-call
    convenience combining build + verify.
  - Length constants: `TLS_CERT_PAD_LEN = 64`,
    `TLS_CERT_CONTEXT_LEN = 33`, `TLS_CERT_SEP_LEN = 1`,
    `TLS_CERT_PUBKEY_LEN = 32`, `TLS_CERT_SIGNATURE_LEN = 64`.
  - Role sentinels: `TLS_CERT_ROLE_SERVER`, `TLS_CERT_ROLE_CLIENT`.
- `tests/unit/test_tls_cert.nova` — **NEW.** 41 checks:
  byte-layout coverage of the build output (0x20 padding, both
  context strings verbatim, separator, transcript verbatim,
  server-vs-client differ in the 6-byte role word only, partial
  transcript_hash_len only consumes the leading N bytes), full
  sign+verify round-trip using an RFC 8032 TEST 1 keypair over
  the built input, tamper detection (bit-flipped sig, bit-flipped
  pubkey, bit-flipped transcript, role mismatch), and shape
  rejection (wrong pubkey length, wrong signature length, negative
  or oversized signed_data_len).

X.509 note: R90 does NOT parse X.509. The cert-pubkey is passed
into the verify seam as raw 32 bytes with a docstring flagging
this. The X.509 subset parser is the next TLS phase (R92 candidate
in the current roadmap; see §12).

Signing note: R90 is verify-only on the TLS path. `ed25519_sign`
continues to work for the R54.2 signed-skill-install flow (which
signs a SHA-256 digest with a stored 32-byte seed); the TLS server-
signing wrapper is deferred until the handshake state machine
exists to consume it (there is no plumbing to test it against
until then).

Test totals (R90 delta): test_ed25519 landed at 61 checks
(+16); test_tls_cert at 41 checks (all new). Regression sweep
across all R86..R89 TLS suites (`test_field25519`, `test_x25519`,
`test_tls_keyshare`, `test_hkdf_sha256`, `test_tls_kdf`,
`test_tls_record_aead`, `test_chacha20_poly1305`, `test_poly1305`,
`test_sha256`, `test_tls_alerts`, `test_tls_state`,
`test_tls_scaffold`, `test_tls13_keyschedule`) and the higher-level
suites (`test_capability_wire`, `test_nl_rpc_verbs`) all green.
The `test_dtls12` failure (72/450 checks red) is pre-existing —
same red counts on `git stash` of the R90 patch — unrelated to
this round.

What R90 unlocks next: with every TLS crypto primitive now in
tree, the remaining TLS work is pure orchestration. R91 candidate
is a CSPRNG source (R92's handshake wire-up must have this; better
to land the primitive first). R92 candidate is the X.509 subset
parser. R93 candidate is the handshake state machine. R94
candidate is the wire-hook flip.

### 7.41 CSPRNG source + RNG interface (R91)

**Honest status: RNG interface + three pluggable backends ship;
`tls_keyshare_generate` and `tls_random_generate` are RNG-driven
wire entry points on the R89 keyshare module. Callers no longer
have to supply a scalar. But — OS-entropy backend is UNAVAILABLE
in this project's sandbox container (NOVA's `secure_random` builtin
wraps the Linux `getrandom` syscall, and the container's seccomp
filter blocks it: `secure_random` returns -1). The interface still
ships; on this container it must be driven via the deterministic
test backend (TEST-ONLY) or the caller-supplied callback backend
that a launcher/sidecar wires up. Handshake orchestration remains
stubbed; wire is still cleartext.**

**Probe finding (this container, R91):**

- `secure_random(buf, 32)` → returns `-1` (getrandom blocked by
  seccomp).
- `nanotime()` → the ARM64 stub-clock in this container is broken
  in a way that segfaults the process on a bare call, so it is
  NOT a viable fallback entropy source anywhere (and would be a
  cryptographic-quality liability even if it worked).
- No `/dev/urandom` sys_open probe was attempted: R73/R74/R75
  showed that `sys_open` in this container aborts on some paths,
  and `secure_random` returning `-1` already gives us the
  authoritative "OS entropy is not reachable" signal. In a
  production deployment where `getrandom` is not filtered out,
  `rng_os_new` will succeed and the OS backend serves normally.

Because Backend A cannot be exercised here, we do NOT hard-fail
the test suite over its absence. `test_rng` logs
`SKIP: OS entropy source not available in this container ...` and
still passes 48 checks against Backends B and C plus the interface
sanity coverage. In an environment where `getrandom` is available,
`test_rng` upgrades that skip to an actively-exercised path
without any test-code change.

**Interface (src/safety/rng.nova):**

```
rng_read(rng_ctx, out_buf, out_len)               -> ok  (1|0)
rng_kind(rng_ctx)                                 -> int  (RNG_KIND_*)
rng_os_new(ctx_out)                               -> ok  (1|0)
rng_test_new(ctx_out, seed_buf, seed_len)         -> ok  (1|0)
rng_callback_new(ctx_out, cb_fn)                  -> ok  (1|0)
```

`rng_ctx` is an opaque NOVA list produced by a backend constructor.
Callers do not know or care which backend is behind it. `rng_read`
returns 1 iff `out_buf` was fully populated with `out_len` bytes;
0 on any failure (RNG dry, bad-shape ctx, negative or oversized
`out_len`, unknown-kind sentinel). A zero-length read is a
no-op returning 1.

**Backends shipped:**

- **A — OS entropy via `secure_random`.** Wraps NOVA's `secure_random`
  builtin (which itself wraps the Linux `getrandom` syscall) and
  folds the raw bytes through a lightweight SHA-256 extractor
  (read 64 bytes → SHA-256 → 32-byte pool, serve pool). Not a full
  HKDF-based DRBG — that upgrade is a candidate for a later round
  if the OS source proves unreliable across target environments.
  `rng_os_new` probes the source at construction and returns 0 if
  it is unavailable (as in this container). Use in production
  where `getrandom` is reachable.
- **B — TEST-ONLY deterministic RNG.** ChaCha20-CTR keystream
  keyed by SHA-256(seed), block-counter monotonic. Byte-identical
  output from a given seed. Rejected empty seed. **Never for real
  handshakes.** Present so downstream tests (x25519 keyshare,
  handshake orchestration once it lands) can be reproducible.
  An exported constant `RNG_TEST_BACKEND_WARNING` carries the
  explicit warning string; `test_rng` pins its shape so a future
  refactor cannot quietly soften it.
- **C — Caller-supplied callback.** Wraps a function reference
  `fn cb_fn(out_buf, out_len) -> ok` so integrators can plug in
  any entropy source without the RNG interface knowing. **This is
  the recommended production integration when Backend A is
  unavailable in the target environment** — a launcher / sidecar
  that reads from `/dev/urandom` on the operator's behalf and
  supplies bytes through the callback closes the R91 gap without
  any NOVA-runtime change.

**Wire integration (src/net/tls/tls_keyshare.nova):**

- `tls_keyshare_generate(rng_ctx, priv_out, pub_out) -> ok` —
  pulls 32 bytes into `priv_out` from `rng_ctx`, computes
  `pub_out = x25519_base(priv_out)`, returns 1 on success. Zero
  on RNG failure, `x25519_base` failure, or an all-zero pubkey
  (defensive check — a real RNG never hits this in practice).
- `tls_random_generate(rng_ctx, out_buf, out_len) -> ok` —
  generic random-bytes helper for ClientHello.random,
  ServerHello.random, session-ticket nonces, etc. Length capped
  at `TLS_RANDOM_MAX = 1024` so a caller confused about a signed
  length can't request a huge fill.
- The pre-existing caller-supplied-scalar path
  (`tls_keyshare_x25519_public` / `_shared`) is kept for the
  RFC 7748 §6.1 test vector and for tests that need a known
  scalar.

**Tests (R91 delta):** `test_rng` at 48 checks
(interface-independent shape + Backend B determinism at four
lengths + Backend C invocation/propagation + Backend A probe with
SKIP semantics). `test_tls_keyshare_rng` at 27 checks (reproducible
keyshare from a seeded RNG, DH round-trip end-to-end through the
wire entry point, `tls_random_generate` length bounds and
determinism, RNG-failure propagation via a rigged callback). All
green.

**Regression sweep (R91):** `test_tls_keyshare`, `test_tls_kdf`,
`test_tls_record_aead`, `test_chacha20`, `test_chacha20_poly1305`,
`test_poly1305`, `test_sha256`, `test_x25519`, `test_field25519`,
`test_hkdf_sha256`, `test_tls_alerts`, `test_tls_state`,
`test_tls_scaffold`, `test_tls_cert`, `test_capability_wire`,
`test_nl_rpc_verbs` all green. `test_ed25519` has the one
pre-existing `ed25519_sign latency positive` red carried since
R89/R90 (nanotime broken container-side; R91 confirms nanotime is
not merely returning 0 in this sandbox — it segfaults the process
on a bare call, matching R90's "sandbox-quirk" note). Not
attributable to R91.

What R91 unlocks next: R92 candidate is the X.509 DER subset
parser (leaf-only, six required fields). R93 candidate is the
handshake state-machine wire-up (consumes R91's RNG interface for
ClientHello.random / ServerHello.random / ephemeral x25519 scalar
via `tls_keyshare_generate`, and R92's parsed cert for the peer
pubkey). R94 candidate is the wire-hook flip
(`wire_connection_wrap` starts returning a real wrapped_conn under
a `tls_config`). Handshake orchestration is the last big lift
before an in-process TLS deployment is possible.

### 7.42 X.509 subset parser + chain verify (R92)

**Honest status: cert parsing + chain-verify + TLS
CertificateVerify end-to-end works in tests. Handshake state
machine still stubbed; wire still cleartext; RNG still
sidecar-dependent in this sandbox.** R92 shipped the piece the
R86 ADR flagged as "the last big cryptographic-plumbing bill"
before handshake orchestration -- turning a raw 32-byte Ed25519
pubkey (the R90 seam) into a real X.509 leaf + root pair the
caller can hand in and get back a boolean "trust this pubkey?".

**What the R92 profile supports:**

- Ed25519 signature algorithm only (RFC 8410 OID `1.3.101.112`,
  DER `06 03 2B 65 70`) -- both the outer signatureAlgorithm and
  the SPKI algorithm are validated as Ed25519 and byte-equal to
  each other (RFC 5280 §4.1.1.2).
- Chain length capped at 2 (leaf + root). Root is passed in
  explicitly by the caller -- there is no trust-anchor store
  yet (R95+ territory). Root MUST be self-signed; leaf MUST NOT
  be byte-identical to the root.
- Distinguished Name reduced to CN (OID `2.5.4.3`). UTF8String
  and PrintableString value encodings both accepted. Full DN
  comparison is out of scope for R92; issuer/subject linkage
  uses byte-equal CN comparison.
- UTCTime (`YYMMDDHHMMSSZ`, 13 bytes) and GeneralizedTime
  (`YYYYMMDDHHMMSSZ`, 15 bytes) parsed to a unix timestamp via
  Howard Hinnant's public-domain `days_from_civil`. YY < 50
  maps to 20YY per RFC 5280 §4.1.2.5.1.
- Non-critical extensions are tolerated (stepped over).
  Critical extensions the parser does not understand are
  refused -- and R92 understands zero extensions, so any
  critical extension in the cert fails the parse.

**What the R92 profile refuses (unambiguous):**

- Any signature algorithm other than Ed25519 (RSA / ECDSA /
  Ed448 etc.).
- Chain length > 2. Root that is not self-signed. Self-signed
  leaf (leaf byte-equal to root).
- UTCTime / GeneralizedTime without a trailing `Z` (offset
  timezones would require arithmetic the R92 helper does not
  carry, and TLS 1.3 servers ship Z-suffix certs in practice).
- Any critical extension.
- BIT STRING with a nonzero unused-bits count in the SPKI or
  signature slot (both are byte-aligned).
- Long-form length encodings > 4 bytes (0x85+). Indefinite
  length (0x80 solo -- BER, not DER).
- Long-form tag identifiers (low 5 bits == 0x1F).
- Anything other than a 32-byte SPKI pubkey / 64-byte signature.

**Why algorithm rigidity, not agility:** the R86 ADR chose one
TLS suite (`TLS_CHACHA20_POLY1305_SHA256`) with x25519 and
Ed25519 uniformly. The daemon has no reason to accept a cert
signed with a different scheme -- there is no interop matrix to
cover, no legacy suite to negotiate down to. Refusing everything
else here means the R93 handshake code path never has to
double-check `sig_alg == Ed25519` on its own; a cert that passed
`x509_parse` is Ed25519 by construction.

**Module layout:**

- `src/net/tls/der.nova` -- minimal ASN.1 DER TLV walker
  (`der_read_tlv`, `der_expect_tag`, `der_oid_equal`,
  `der_bitstring_content`, `der_bytes_equal`, tag constants).
  Deliberately kept generic: byte-list buffers with
  offset/length pairs, out-parameters via single-element lists,
  no cert-specific state.
- `src/net/tls/x509.nova` -- cert parser + chain verifier
  (`x509_parse`, `x509_verify_self_signed`,
  `x509_verify_signed_by`, `x509_check_validity`,
  `x509_check_issuer`, `x509_chain_verify`,
  `x509_parse_utctime`, `x509_parse_generalizedtime`). Parsed
  cert is a fixed-index NOVA list holding offsets into the
  original cert buffer -- no allocation for the parse result
  beyond the struct itself.
- `src/net/tls/tls_cert.nova` -- new
  `tls_cert_verify_chain_and_signature(leaf_buf, leaf_len,
  root_buf, root_len, now_unix, transcript_hash,
  transcript_hash_len, is_server, tls_signature)` end-to-end
  wrapper: chain-verify + assemble the RFC 8446 §4.4.3
  signed-content blob + verify the TLS CertificateVerify
  signature under the leaf's SPKI pubkey, all in one call.
  R90's raw-pubkey APIs stay (still called by tests and by the
  low-level wrappers).

**Note on `src/safety/x509.nova`:** that pre-existing 903-line
module is the DTLS 1.2 ECDSA-P-256 parser (R32C). It is
intentionally NOT reused by the R92 TLS 1.3 path -- different
suite, different algorithm rigidity, and folding the two would
force the TLS 1.3 path to accept algorithm choices the R86 ADR
already rejected. Keeping them separate lets each remain
small and single-purpose.

**Fixture strategy (test cert building):**

- `tests/unit/fixtures/x509_test_certs.nova` --
  `x509_build_test_cert(subject_cn, issuer_cn, serial, nb_utc,
  na_utc, spki_pk_32, signer_seed_32, signer_pk_32)` assembles
  a proper DER-encoded cert programmatically and signs the TBS
  with `ed25519_sign`. Round-trip tests then feed the result
  straight into `x509_parse` / `x509_chain_verify`. Preferred
  over hex-literal fixtures: the DER assembly is auditable in
  NOVA, the signature always corresponds to the current TBS
  bytes (no stale-hex risk), and negative-case variants
  (`x509_build_test_cert_bad_alg`, `x509_build_test_cert_with_ext`
  with critical/non-critical flag, `x509_build_test_cert_non_z_time`)
  reuse the same encoder. Root key = RFC 8032 §7.1 TEST 1;
  leaf key = TEST 2.

**Tests (R92 delta):**

- `test_der` -- 73 checks. Short-form and long-form (0x81/0x82)
  length parsing; indefinite-length / >4-length-bytes / truncated /
  long-form-tag rejection; nested SEQUENCE walk; BIT STRING
  zero and nonzero unused-bits; OID equality (match, prefix
  mismatch, length mismatch, out-of-range); [0] EXPLICIT wrap;
  `der_bytes_equal` cases.
- `test_x509_r92` -- 60 checks. UTCTime YY=49 → 2049 and YY=50
  → 1950; GeneralizedTime 1970-01-01 → unix 0 and
  2020-02-29 12:00 (leap year); non-Z suffix rejection;
  round-trip on a built root/leaf pair with every field
  cross-checked; self-signature verify; leaf-by-root verify;
  validity window with inclusive-boundary edge cases;
  CN-based issuer check; happy-path `x509_chain_verify`; five
  tamper cases (sig bit, TBS bit, wrong root, expired, self-
  signed leaf); four format rejections (non-Ed25519 alg,
  critical extension, non-critical extension tolerated,
  non-Z time in cert); trailing-byte rejection; empty-buf
  rejection.
- `test_tls_cert_chain` -- 14 checks. End-to-end
  `tls_cert_verify_chain_and_signature` happy path for both
  server-role and client-role CertificateVerify; wrong-root
  fail; expired-cert fail; tampered CertVerify signature fail;
  swapped-role fail (both directions); 63/65-byte sig
  rejection; negative and oversized transcript_hash_len
  rejection; tampered transcript fail; tampered leaf-TBS fail;
  byte-equal leaf/root refusal.

All 147 new R92 checks green.

**Regression sweep (R92):** `test_tls_cert` (41),
`test_tls_kdf` (27), `test_tls_keyshare` (14),
`test_tls_keyshare_rng` (27), `test_tls_alerts` (161),
`test_tls_state` (68), `test_tls_scaffold` (70),
`test_tls_record_aead` (53), `test_tls13_keyschedule` (28),
`test_capability_wire` (245), `test_nl_rpc_verbs` (74) all
green. `test_ed25519` retains the one pre-existing
`ed25519_sign latency positive` red carried since R89/R90
(nanotime segfaults in this sandbox); not attributable to
R92. Pre-existing `test_dtls12` reds untouched -- unrelated
to the R87..R92 TLS 1.3 build-out.

What R92 unlocks next: R93 candidate is the handshake
state-machine wire-up (ClientHello → ServerHello →
EncryptedExtensions → Certificate → CertificateVerify →
Finished orchestration), consuming R91's RNG for the two
`.random` fields and the ephemeral x25519 scalar and R92's
parsed cert for the peer's Ed25519 pubkey. R94 candidate is
the wire-hook flip (`wire_connection_wrap` starts returning a
real wrapped_conn under a `tls_config`; ships alongside a
sidecar recipe for supplying entropy through Backend C in
seccomp-filtered containers).

### 7.43 TLS 1.3 handshake state machine (R93)

**Honest status: full in-process TLS 1.3 handshake runs end-to-end
in tests; a server session and a client session (both instantiated
in the same process, exchanging bytes through caller-owned queues)
converge on byte-identical `client_application_traffic_secret_0`
and `server_application_traffic_secret_0` and then round-trip
encrypted application data in both directions. Wire is STILL
cleartext — `wire_connection_wrap` is untouched; R94 flips it.**

**What the state machine does end-to-end (RFC 8446 §4):**

1. Client emits `ClientHello` cleartext with the pinned suite
   (`TLS_CHACHA20_POLY1305_SHA256` / x25519 / ed25519), a
   32-byte `random`, a 32-byte x25519 keyshare, and the
   supported_versions / supported_groups / signature_algorithms
   extensions.
2. Server parses `ClientHello`, absorbs it into the SHA-256
   transcript, emits `ServerHello` cleartext with its own keyshare,
   computes the x25519 shared secret, and derives the RFC 8446 §7.1
   `early_secret` → `handshake_secret` → `(client|server)_hs_traffic`
   secrets.
3. Server sends `EncryptedExtensions` (empty) || `Certificate`
   (single leaf) || `CertificateVerify` (ed25519 sig over the
   RFC 8446 §4.4.3 signed content assembled from the transcript
   through `Certificate`) || server `Finished` (HMAC-SHA-256 with
   `HKDF-Expand-Label(server_hs_traffic, "finished", "", 32)`
   over the transcript through `CertificateVerify`) as one AEAD
   record sealed under `server_hs_traffic`.
4. Client decrypts the flight, absorbs each message in turn, chain-
   verifies the leaf against the caller-supplied root (`x509_chain_verify`
   from R92), verifies the `CertificateVerify` signature under the
   leaf's SPKI pubkey, and verifies the server `Finished` HMAC.
5. Both sides derive `master_secret` and
   `(client|server)_application_traffic_secret_0` from the transcript
   through server `Finished` (identical inputs → identical outputs).
6. Client sends its `Finished` (HMAC over transcript-through-server-
   `Finished` with `finished_key(client_hs_traffic)`) as an AEAD
   record sealed under `client_hs_traffic`, then switches TX to
   `client_ap_traffic` and RX to `server_ap_traffic`.
7. Server verifies the client `Finished` HMAC, then switches keys
   the same way. Both endpoints are now in `APPLICATION`.

**Explicit simplifications (R93 does NOT cover):**

- No 0-RTT / no early data.
- No PSK / no session resumption.
- No HelloRetryRequest (client always offers x25519; a server that
  gets a ClientHello without x25519 sends a fatal `handshake_failure`
  alert — R93 has no HRR path).
- No client certificate authentication.
- No key update after handshake.
- No post-handshake authentication.
- One record per handshake message on the send path, EXCEPT the
  server's encrypted flight (EE || Cert || CertVerify || Finished),
  which is a single AEAD record. The parser tolerates cross-record
  fragmentation on receive as required by RFC 8446 §5.1.

**In-memory test harness (crown-jewel pattern):**

- Two sessions instantiated in the same process:
  `session_new_client(client, root_der, rng_ctx, now_unix)` and
  `session_new_server(server, cert_der, cert_priv, cert_pub, rng_ctx, now_unix)`.
- Distinct-seed deterministic RNGs (R91 Backend B) drive each side's
  ephemeral x25519 scalar and `.random` fields so the whole test is
  reproducible byte-for-byte.
- Pump loop: alternately `session_drain_send` each side's outbound
  and `session_recv` on the other; state machines advance eagerly
  after each `recv`. Loop until both `session_handshake_done`.
- Root and leaf certs assembled programmatically via R92's
  `x509_build_test_cert` (RFC 8032 TEST 1 root, TEST 2 leaf).

**Module layout (R93 delta):**

- `src/net/tls/tls_handshake.nova` — replaces the R86 `TLS_NOT_IMPLEMENTED`
  stubs with real parse / serialize per message type
  (`hs_client_hello_*`, `hs_server_hello_*`, `hs_encrypted_extensions_*`,
  `hs_certificate_*`, `hs_certificate_verify_*`, `hs_finished_*`) plus
  the shared `hs_wrap_header` / `hs_parse_header` helpers. R86 wrappers
  (`tls_handshake_parse_*`) retained as thin adapters onto the new
  concrete routines so any straggling caller compiles.
- `src/net/tls/tls_transcript.nova` — NEW. SHA-256 transcript hash
  rolling with a snapshot-`get` (deep-copy the streaming state so
  `sha256_final` on the snapshot yields the interim digest without
  disturbing the live stream). Used by every derivation step and by
  the CertificateVerify / Finished input construction.
- `src/net/tls/tls_session.nova` — NEW. Connection state machine +
  key schedule invocations + per-direction record keys (with
  epoch-resetting sequence counters) + inbound / outbound byte
  queues + public API (`session_new_client` / `session_new_server` /
  `session_start_client` / `session_recv` / `session_want_send` /
  `session_drain_send` / `session_encrypt_app` / `session_decrypt_app` /
  `session_close` / `session_finalize_close` / `session_handshake_done` /
  accessors for each derived secret).

**Tests (R93 delta, 120 new checks):**

- `test_tls_handshake_msgs` — 54 checks. Round-trips for every
  message type (ClientHello without / with SNI, ServerHello,
  EncryptedExtensions, Certificate, CertificateVerify, Finished);
  hand-encoded byte-level layout of ClientHello; reject wrong
  `legacy_version`, wrong cipher (non-0x1303), missing key_share,
  wrong sigalg on CertificateVerify, wrong Finished length;
  extension-length-overflow rejection; unknown-extension tolerance
  (RFC 8446 §4.2 "MUST ignore" semantic); header-parse bounds.
- `test_tls_transcript` — 16 checks. Empty transcript equals
  `SHA-256("")`; single / two / ten-piece absorbs all equal the
  concatenated one-shot; snapshot doesn't disturb the live state;
  boundary at 63 / 64 bytes (SHA-256 block edge); `absorb` vs
  `absorb_buf` parity; `get_into` equals `get`; init variant
  matches new variant.
- `test_tls_session` — 35 checks. **Crown jewel:** both peers
  finish the handshake and derive byte-identical
  `client_hs_traffic`, `server_hs_traffic`, `client_ap_traffic`,
  `server_ap_traffic`. Application-data round-trip in both
  directions. Multiple app records with correct sequence-counter
  progression. `close_notify` transitions both sides to CLOSING;
  `session_finalize_close` transitions both to CLOSED.
- `test_tls_session_tamper` — 15 checks. Client rejects wrong
  root (`bad_certificate`), expired leaf (`certificate_expired`),
  bogus CertVerify signature (`decrypt_error`), tampered server
  Finished (`bad_record_mac` or `decrypt_error`). Server rejects
  wrong cipher (`handshake_failure`), wrong group (`handshake_failure`),
  tampered client Finished (`bad_record_mac` or `decrypt_error`).

**Regression sweep (R93):** all TLS suites green —
`test_tls_alerts` (161), `test_tls_scaffold` (66), `test_tls_state` (68),
`test_tls_kdf` (27), `test_tls_keyshare` (14), `test_tls_keyshare_rng` (27),
`test_tls_cert` (41), `test_tls_cert_chain` (14),
`test_tls_record_aead` (53), `test_tls13_keyschedule` (28),
`test_tls_handshake_msgs` (54), `test_tls_transcript` (16),
`test_tls_session` (35), `test_tls_session_tamper` (15). Wire
regressions `test_capability_wire` (245), `test_nl_rpc_verbs` (74)
green. Pre-existing `test_dtls12` reds and the `ed25519_sign latency`
red on `test_ed25519` are unchanged (they precede R93 and are
tracked in §12).

**What's still missing for wire deployment:**

- **R94 flip of `wire_connection_wrap`.** R93 wires the state
  machine into a callable API, but the daemon accept loop still
  hands raw fds through the pass-through hook. R94 replaces the
  passthrough with a real wrapped_conn whose read/write path
  drives `session_recv` / `session_drain_send` under a
  `tls_config`.
- **Entropy sidecar for this container.** The OS RNG backend from
  R91 remains unavailable in this project's seccomp-filtered
  sandbox. R94 needs to ship a launcher / sidecar recipe that
  supplies bytes through the R91 callback backend (Backend C) so
  a live handshake has real entropy for its ephemeral scalar and
  `.random` fields.
- **Cert provisioning story.** R93 tests programmatically-built
  Ed25519 certs (RFC 8032 TEST 1 / TEST 2 keys); a real deployment
  needs a supported path for operators to bring their own leaf
  cert + private key (and a root cert operators trust). R94 ties
  this into the `tls_config` on daemon boot.

### 7.44 TLS wire-enable (R94) — TLS 1.3 on the wire

**Honest status: the TLS build-out is COMPLETE.** R86 scaffolded the
seam; R87..R92 landed the primitives; R93 landed the handshake state
machine as an in-memory test; R94 flips `wire_connection_wrap` from
pass-through to a real TLS-wrapped-fd type and wires the daemon's
accept loop to it. Opt-in via `CROSSENGIN_TLS=1`; deployments that
don't set it boot byte-identically to pre-R94 (the null-`tls_config`
branch is a no-op RAW wrapper).

**Opt-in switch:**

- `CROSSENGIN_TLS=1` — turn TLS on. Any other value (unset / "0")
  leaves the wire in cleartext, backwards-compatible with every
  pre-R94 launcher.

**Cert material (three env vars, all base64-encoded DER):**

- `CROSSENGIN_TLS_LEAF_DER`  — `base64(leaf.der)`, the server
  certificate the daemon presents on the wire.
- `CROSSENGIN_TLS_LEAF_PRIV` — `base64(leaf-priv-seed)`, the 32-byte
  Ed25519 seed that signs `CertificateVerify`. R94 does NOT parse
  PKCS#8 wrappers; the sidecar / launcher extracts the raw seed
  before exporting.
- `CROSSENGIN_TLS_ROOT_DER`  — `base64(root.der)`, the trust anchor
  the daemon carries alongside its leaf. R94 uses this internally
  for shape validation; a future client-cert-auth round (see the R86
  ADR post-scriptum) will use it to gate incoming client certs.

If `CROSSENGIN_TLS=1` is set but any of the three env vars is missing
or malformed, the daemon refuses to boot with a diagnostic pointing at
this section. Silent fallback to cleartext is deliberately NOT the
default — a mis-configured launcher must not quietly downgrade the
confidentiality guarantee.

**RNG modes (`CROSSENGIN_RNG_MODE`):**

- `os`       — Backend A. Uses NOVA's `secure_random` builtin,
               which wraps the Linux `getrandom` syscall. Fails
               in seccomp-restricted containers.
- `test`     — Backend B. Deterministic ChaCha20-CTR keyed by
               `SHA-256(seed)` where `seed = CROSSENGIN_RNG_SEED`
               env var. **NOT PRODUCTION SAFE** — every "random"
               byte is reproducible to anyone who knows the seed.
               Present for smoke tests / bring-up.
- `callback` — Backend C. Reads 32-byte entropy chunks on demand
               from a named FIFO at `CROSSENGIN_RNG_FIFO`. The
               operator's sidecar keeps the FIFO supplied with
               real entropy from a source NOVA cannot reach
               directly (a hardware RNG, a chain of `getrandom`
               calls in a permissive process, etc.).

**Sandbox note (this container):** This project's sandbox runs
inside a seccomp-restricted container that BLOCKS `getrandom`;
`secure_random` returns -1 and `CROSSENGIN_RNG_MODE=os` fails. In
this container the daemon MUST use `CROSSENGIN_RNG_MODE=callback`
with a FIFO fed by an external process. In unrestricted deployments
(bare metal, permissive containers, standard cloud VMs)
`CROSSENGIN_RNG_MODE=os` works out of the box.

**Sidecar recipe (operator writes this; R94 does NOT ship it):**

R94 ships the CONTRACT, not the sidecar. The sidecar is a launcher
script the operator supplies; below is an illustrative shell recipe
for the shape it takes.

```
# Operator's launcher -- NOT shipped, illustrative only.
# The sidecar wraps the daemon so cert material + entropy reach it
# through env vars / a FIFO the daemon reads.
#
# export CROSSENGIN_TLS=1
# export CROSSENGIN_TLS_LEAF_DER="$(base64 -w0 leaf.der)"
# export CROSSENGIN_TLS_LEAF_PRIV="$(base64 -w0 leaf.priv)"   # 32-byte seed
# export CROSSENGIN_TLS_ROOT_DER="$(base64 -w0 root.der)"
#
# # In a permissive environment:
# export CROSSENGIN_RNG_MODE=os
#
# # In a seccomp-restricted environment (this project's sandbox):
# mkfifo /run/crossengin/rng.fifo
# ( while :; do dd if=/dev/urandom bs=32 count=1; done ) \
#     > /run/crossengin/rng.fifo &
# export CROSSENGIN_RNG_MODE=callback
# export CROSSENGIN_RNG_FIFO=/run/crossengin/rng.fifo
#
# export CE_RPC_PORT=9876
# exec /path/to/crossengin_rpc_daemon
```

**Cert provisioning is out of scope for R94.** Recommended path:
the operator uses their existing internal PKI to mint Ed25519 leaf
+ root pairs (RFC 8410 §7 format), or generates them via any
Ed25519-capable tool (openssl 3.0+, `step-cli`, etc.). The sidecar
extracts the raw seed from the PKCS#8 wrapper before base64-
encoding it — R94 does NOT include a PKCS#8 parser.

**Explicit list of supported / unsupported (R94 profile):**

Supported:
- TLS 1.3 only (RFC 8446). No TLS 1.2 fallback path.
- Cipher suite: `TLS_CHACHA20_POLY1305_SHA256` (0x1303) ONLY.
- Key exchange: `x25519` ONLY.
- Signature algorithm: `Ed25519` ONLY.
- Cert chain length ≤ 2 (leaf + root).
- Self-signed root only (root == trust anchor, no intermediate CAs).
- Full handshake per accepted connection.

Unsupported / refused / out of scope for R94:
- Session resumption (0-RTT / PSK / ticket cache).
- HelloRetryRequest (a ClientHello that doesn't already offer
  x25519 gets a fatal `handshake_failure`).
- Client-certificate authentication.
- Post-handshake key update.
- Post-handshake authentication.
- SNI-based multi-cert selection.
- OCSP / CRL revocation checks.
- Longer cert chains.

**TLS build-out is now complete.** The phase history (R86..R94) lives
in `docs/adr/r86-in-process-tls-scaffolding.md`; the post-scriptum
there enumerates hardening candidates (see also §12 below).

**Tests (R94 delta, 106 new checks):**

- `test_base64` (35 checks) — RFC 4648 §10 vectors plus shape-
  rejection cases.
- `test_tls_config` (22 checks) — new server / client constructors
  with valid + malformed material.
- `test_tls_wire_hook` (40 checks) — crown-jewel handshake pump
  under mock transport; app-data round-trip in both directions;
  close_notify propagation; null-config back-compat.
- `test_daemon_tls_bootstrap` (9 checks) — end-to-end env-var pipe
  (encode → decode → tls_config_new_server) plus a garbled-
  base64 refusal spot-check.

**Regression sweep (R94):** every existing TLS suite green —
`test_tls_scaffold` (70), `test_tls_alerts` (161), `test_tls_state`
(68), `test_tls_kdf` (27), `test_tls_keyshare` (14),
`test_tls_keyshare_rng` (27), `test_tls_record_aead` (53),
`test_tls_transcript` (16), `test_tls13_keyschedule` (28),
`test_tls_cert` (41), `test_tls_cert_chain` (14),
`test_tls_handshake_msgs` (54), `test_tls_session` (35),
`test_tls_session_tamper` (15), `test_x509` (54), `test_x509_r92`
(60), `test_x509_verify` (14), `test_capability_wire` (245),
`test_nl_rpc_verbs` (74). Pre-existing DTLS-12 reds and the
Ed25519 latency red are untouched (they predate R87).

### 7.45 Small-LLM NL adapter wired as fallback (R95 — Phase B)

Phase A codified the AI-Factory vision in 22 ADRs. R95 (Phase B) is
the first user-visible code round on top of that vision: the LLM
parser that shipped in R48p6 but was never called is now wired as
a FALLBACK on `nl.ask` when the grammar returns `NLK_UNPARSED`.
ADR-0211 keeps LLM-free NLP as the primary target; the sidecar is
the escape hatch when grammar coverage misses. Every fallback fires
under a per-holder counter so the operator can drive the LLM
dependence toward zero over time (Phase C's grammar expansion + HDC
classifier + `nl.metrics` wire verb will feed on these numbers).

**What shipped:**

- `src/nl/nl_llm_sidecar.nova` — module that fork+exec's
  `scripts/nl_parse_llm.sh` (the RFC-locked script from ADR-0201),
  drains stdout, hands the wire bytes to `llm_parse_wire_verbose`.
  Follows the fork+exec pattern proven in `whisper_backend.nova`
  since NOVA has no `run_shell` primitive
  (`docs/NOVA_RUNTIME_GAPS.md` P-1). Env-driven; cached at first
  probe.
- `src/nl/nl_metrics.nova` — per-holder counter registry with
  slots `total / unparsed / llm_fallback_attempts /
  successes / failures`. Public API `nl_metrics_new()` +
  `nl_metrics_inc_*(reg, holder)` + `nl_metrics_snapshot(reg)`.
  Anonymous holders (`""`) are a first-class bucket. Reads never
  allocate rows (no side effect in getters).
- `nl_llm_try_fallback(q, raw_text, metrics, holder)` — the shared
  helper both seams call. No-op on non-UNPARSED. On UNPARSED with
  the sidecar unavailable it returns the original query and touches
  NO counters (we didn't try). On UNPARSED with the sidecar
  available it inc's attempt, invokes the sidecar, parses the wire,
  and on success replaces `q` (inc'ing success) or on malformed
  wire returns the original (inc'ing failure).

**The two seams:**

1. **Wire — `_rpc_verb_nl_ask` (`src/nl/rpc_verbs.nova`)** — a new
   `RCTX_NL_METRICS` slot on `rpc_ctx` (accessor
   `rpc_ctx_nl_metrics(ctx)`, mutator `rpc_ctx_set_nl_metrics(ctx,
   reg)`). The verb inc's total on every call, inc's unparsed when
   grammar whiffs, then calls `nl_llm_try_fallback(q, text,
   metrics, holder)` before dispatching to `nl_execute_scoped`.
   `crossengin_rpc_daemon.nova` allocates a fresh `nl_metrics`
   registry at boot so this daemon always feeds the counters —
   removes the "did the operator remember to wire the registry?"
   trap. Absent the wiring (custom daemons pre-R95) the seam
   silently no-ops.
2. **Chat — `_try_nl` (`examples/crossengin_chat.nova`)** — the
   line-2076 `if k == NLK_UNPARSED { return 0 }` is replaced with
   a `nl_llm_try_fallback` call; still-UNPARSED after the sidecar
   returns 0 (preserves the "genuinely no NL match" fall-through
   to legacy cognition). A module-level lazy-init singleton
   `_nl_metrics_singleton` keeps process-scoped counters for the
   chat session, mirroring the pattern used by `_skill_registry`
   and `_ingest_agent`.

**Env-var contract (documented in ADR-0201, implemented at R95):**

| Env var | Purpose | Default |
|---|---|---|
| `CROSSENGIN_NL_LLM_ENABLED` | Master gate. Value must be `"1"` to arm the sidecar path. | off |
| `CROSSENGIN_NL_LLM_MODEL` | Passed to `--model`. | `local-small` |
| `CROSSENGIN_NL_LLM_BACKEND` | Passed to `--backend` (`ollama` / `llama-cpp` / `openai` / `dry-run`). | `ollama` |
| `CROSSENGIN_NL_LLM_SCRIPT` | Override the resolved script path (out-of-tree installs). | `scripts/nl_parse_llm.sh` |
| `CROSSENGIN_NL_LLM_TESTMODE` | Bypass shell-out entirely; short-circuit to the fixture. | off |
| `CROSSENGIN_NL_LLM_TEST_WIRE` | Wire-format bytes returned in test-mode. E.g. `"KIND research\nARG cats\n"`. | `""` |

Env is read ONCE at first `nl_llm_sidecar_available()` and cached.
Restart to pick up changes — documented so operators don't chase
"why isn't my new `MODEL` taking effect?" ghosts.

**Test-mode pattern.** NOVA has no `setenv` (see
`docs/NOVA_RUNTIME_GAPS.md`), so unit tests can't mutate env vars
between scenarios to exercise different configurations. The
sidecar module exposes three test-only injectors —
`nl_llm_sidecar_test_force_off()`,
`nl_llm_sidecar_test_force_live(script_path)`,
`nl_llm_sidecar_test_force_testmode(wire)` — that let a test bypass
the env-read step and inject the cache state directly. Every unit
test calls `nl_llm_sidecar_reset_cache()` first so scenarios don't
latch to the first observation.

**Metric slots per holder:**

- `total` — every `nl.ask` (or `_try_nl` call).
- `unparsed` — grammar returned `NLK_UNPARSED`.
- `llm_fallback_attempts` — sidecar was invoked. Always equal to
  `successes + failures`. Sidecar-unavailable does NOT count.
- `llm_fallback_successes` — sidecar returned + wire parsed +
  produced a valid `StructuredQuery`.
- `llm_fallback_failures` — attempt fired but wire was malformed /
  empty / kind-less.

**Sidecar-unavailability semantics.** When
`nl_llm_sidecar_available() == 0` the helper returns the original
UNPARSED query untouched and does not inc any counter. The
executor's refusal branch then fires with the updated message
`"grammar could not parse this input; LLM sidecar was unavailable
or also refused"` (was `"...LLM fallback not linked yet (R48p6)"`;
same behavior, clearer text). This is deliberate: the metric
measures "we tried the LLM"; treating an unwired sidecar as an
attempt would misrepresent the fallback rate.

**New tests (163 checks total):**

- `test_nl_llm_sidecar` (53) — availability contract, test-mode
  short-circuit, wire handoff to `llm_parse_wire_verbose`, malformed
  wire refusal, the shared helper's contract with the metrics
  registry, null-query defense, 0-registry no-op safety.
- `test_nl_metrics` (51) — fresh-registry all-zero, single- and
  multi-holder increments, anonymous bucket, snapshot idempotence,
  order independence, 0-registry no-op mutators + readers.
- `test_nl_rpc_llm_fallback` (33) — end-to-end through
  `rpc_dispatch("nl.ask", ...)`: grammar-parseable fast path
  (attempts=0), sidecar off (unparsed=1, attempts=0), sidecar
  success (attempts=1, successes=1, parser_used flips to `"llm"`),
  sidecar malformed (attempts=1, failures=1), ctx accessor
  round-trip, 0-metrics ctx compatibility.
- `test_nl_chat_llm_fallback` (26) — analogous coverage for the
  chat seam via the shared helper (chat's `_try_nl` calls `print()`
  directly and pulls in a large substrate slice, making black-box
  import impractical; the plan explicitly allows testing the
  helper directly for this surface).

**Regression sweep (all green):** `test_nl_grammar_parser` (103),
`test_nl_query_shape` (86), `test_nl_executor` (76),
`test_nl_templater` (60), `test_nl_llm_parser` (66),
`test_nl_rpc_server` (37), `test_nl_chat_wire` (29),
`test_capability_wire` (245), `test_nl_rpc_verbs` (74). Executor's
message-text assertion still matches (the new message contains the
`"LLM"` substring the test scans for).

**Live-sidecar smoke.** Deferred to a permissive host. This
project's sandbox container blocks / observes fork+exec in ways
that make a live smoke unreliable inside the test harness; the
test-mode short-circuit exercises the same handoff logic (parse
+ metrics + fallback semantics) without touching the process
table, and is the primary confidence gate for R95. Operators
running the daemon on a normal host validate the live path with:

```
CROSSENGIN_NL_LLM_ENABLED=1 \
CROSSENGIN_NL_LLM_BACKEND=dry-run \
CE_NL_LLM_DRY_KIND=research \
CE_NL_LLM_DRY_ARGS=weather \
  bin/crossengin-rpc-daemon
```

and issuing `nl.ask` with a text the grammar rejects; the sidecar
returns the fixture, `llm_parse_wire` promotes it to a research
query, and the daemon dispatches the research skill.

**References**: ADR-0201 (small-LLM sidecar contract), ADR-0211
(LLM-free NLP as primary path; fallback rate drives investment),
plan file `gentle-toasting-zephyr.md`.

### 7.46 nl.metrics wire verb (R96 — Phase C part 1)

R95 stood up the per-holder counter registry but left it invisible
on the wire: an operator could see the LLM sidecar fire but not
snapshot the fallback rate. R96 closes that gap with a single
read-only verb, `nl.metrics`, that exposes the R95 counters as
JSON. This is Phase C part 1: ADR-0211 mandates the fallback-rate
metric as the primary driver of Phase C's grammar / classifier
investment, and you cannot drive down a rate you cannot see.

**Verb summary:**

- **Verb name:** `nl.metrics`
- **Cap required:** `nl:metrics:read` (new; bundled with the READER
  role, not admin — this is observability, not a mutation).
- **Args (all optional):**
  - `holder` — when present, return just that holder's row.
    The empty string `""` is a valid query: the anonymous bucket
    (calls made with no capability token presented).
- **Response shape (no `holder` arg):**

  ```
  {
    "holders": {
      "alice": {"total": 42, "unparsed": 5, "llm_attempts": 5,
                 "llm_successes": 4, "llm_failures": 1,
                 "fallback_rate": 119},
      "bob":   {"total": 17, "unparsed": 0, "llm_attempts": 0,
                 "llm_successes": 0, "llm_failures": 0,
                 "fallback_rate": 0},
      "_total_all_holders": {
        "total": 59, "unparsed": 5, "llm_attempts": 5,
        "llm_successes": 4, "llm_failures": 1,
        "fallback_rate": 847
      }
    }
  }
  ```

- **Response shape (with `holder` arg):** just the inner
  `{total, unparsed, llm_attempts, llm_successes, llm_failures,
  fallback_rate}` row, no wrapping `holders` map.

**`fallback_rate` encoding — integer basis points.** NOVA has no
float type (`docs/NOVA_RUNTIME_GAPS.md`). The rate is emitted as
BASIS POINTS: `llm_attempts * 10000 / total`, integer division,
with `total == 0` mapped to 0. Four significant digits — enough
for a dashboard tile. 8.47% renders as `847`; 1.19% as `119`;
100% as `10000`; "no traffic yet" as `0` (distinguishable from
"traffic without fallback" via `total > 0` on the same row).
Clients can render as a percentage by dividing by 100.

**Snapshot semantics.** The verb NEVER mutates the registry.
Successive calls without any intervening `nl.ask` return
identical rows. An unseen holder's per-holder query returns an
all-zero row and does NOT allocate a registry row (no
side-effect-in-getter).

**No metrics registry wired** (custom daemons that skipped
`rpc_ctx_set_nl_metrics`): the verb returns an empty holders
map with a zero `_total_all_holders` row rather than refusing.
Callers distinguishing "not wired" from "no traffic yet" can
inspect the shape: a wired-but-empty registry returns
`{"holders": {"_total_all_holders": {...zeros...}}}`; a call
against a non-wired context returns the same shape (the R95
inc helpers no-op on registry==0 so the two cases converge by
design). The reference daemon (`crossengin_rpc_daemon.nova`)
wires a fresh registry at boot, so this branch only surfaces
when an operator disabled the wiring deliberately.

**Example (loopback, no sandbox):**

```
scripts/rpc.sh nl.metrics
# -> {"ok":true,"result":{"holders":{
#      "_total_all_holders":{"total":0,"unparsed":0,
#        "llm_attempts":0,"llm_successes":0,"llm_failures":0,
#        "fallback_rate":0}}}, "error":""}

scripts/rpc.sh nl.ask text='floof glorpity'  user_id=owner
scripts/rpc.sh nl.metrics holder=''
# -> {"ok":true,"result":{"total":1,"unparsed":1,
#      "llm_attempts":0,"llm_successes":0,"llm_failures":0,
#      "fallback_rate":0}, "error":""}
```

**Example (sandbox-enforced dashboard reader):**

```
# admin mints a reader token for the dashboard cron job:
scripts/rpc.sh capability.issue holder=dashboard roles=reader
# -> ...token_id=abcd...

TOK=abcd... curl (or scripts/rpc.sh) nl.metrics
# Reader role carries nl:metrics:read; call is authorized.
```

**Cap gate.** `nl.metrics` requires `nl:metrics:read`. The reader,
skill_user, curator, and admin roles all carry it; the service
role does not (call-serve accounts don't need dashboard reads).
Under enforcement:

- reader token -> allowed
- admin token -> allowed
- token missing the cap -> `"capability required: nl:metrics:read"`
- unknown token -> `"capability required: unknown token"`
- anonymous (no token) -> `"capability required: request missing 'token' field"`

**Tests (78 new checks in `test_nl_rpc_metrics_verb`):**
verb registered + cap declared, reader/admin carry the cap +
service does not, fresh-registry empty snapshot, unwired-context
still returns ok, three-`nl.ask` shape check (2 parsable + 1
unparsable-sidecar-off), test-mode success shape, test-mode
failure shape, holder-arg single-row filter (with no-side-effect
verification on unseen holders), aggregate math across two
holders, basis-points math edge cases (0/0, 1/10, 3/17, 5/5),
cap gate positive + three refusal branches, malformed / edge args.

**References**: ADR-0201 (small-LLM sidecar contract), ADR-0211
(LLM-free NLP as primary path; fallback rate drives investment).

### 7.47 Grammar expansion 12 -> N patterns (R97 — Phase C part 2)

Phase C part 1 (R96) landed the `nl.metrics` verb, but a metric only
matters if you have a knob to turn. R97 turns the first knob: it
extends the deterministic LLM-free grammar parser
(`src/nl/grammar_parser.nova`) from its R48p2 core of ~12 canonical
patterns to **~85 natural phrasings**, without introducing any new
`StructuredQuery` kinds. Every added pattern maps to one of the same
11 `NLK_*` kinds the executor already knows how to dispatch. This is
the FIRST metric-driven grammar expansion — the direct effect on
`_total_all_holders`'s `fallback_rate` (basis points, see §7.46) is
the tuning signal for future work.

**What "12 -> N" means concretely.** Existing behavior on every R48p2
test input is preserved byte-for-byte (regression suite: 103 checks
still green). R97 layers new matchers around it so the parser now
also recognizes the polite / synonymous / suffix / infix / declarative
forms real users type. `sq_unparsed` (which sends the query out to
the small-LLM sidecar) fires on strictly fewer inputs than before.

**Per-category coverage added** (all map to existing `NLK_*` kinds;
counts refer to distinct new phrasings, not test cases):

- **NLK_RESEARCH (+24)** — `explain X` / `describe X` / `define X` /
  `what does X mean` / `what is the meaning of X` /
  `give me info on|about X` / `information on|about X` /
  `what can you say about X` / `elaborate on X` / `expand on X` /
  `overview of X` / `summary of X` / `background on X` /
  `history of X` / `origin of X` / `facts about X` /
  `key points about X` / `details on|about X` /
  `how does X work` / `why is X important` /
  suffix forms `X definition` / `X meaning` / `X explained` /
  `know about X` (picks up after `i want to` preamble strip).
- **NLK_RELATE (+11)** — `how does X relate to Y` /
  `what is the relationship between X and Y` /
  `connection between X and Y` / `link between X and Y` /
  `association between X and Y` / `similarities between X and Y` /
  `difference[s] between X and Y` / `how are X and Y related` /
  `compare X and Y` / `comparison of X and Y` /
  `X vs Y` / `X versus Y` (infix).
- **NLK_CONTRADICT_SCAN (+6)** — 1-topic scan forms mapped by
  putting the topic in both slots: `contradictions in X` /
  `inconsistencies in X` / `conflicts about X` /
  `disagreements about X` / `find contradictions in X` /
  `scan for contradictions about X` / `where does X conflict`.
- **NLK_IS_A (+7)** — `is X a kind of Y` / `is X a type of Y`
  (strip leading `kind of` / `type of` from Y) /
  `is X kind of Y` / `is X type of Y` (article-less) /
  `does X count as [a] Y` / `is X considered [a] Y` /
  declarative `X is a[n] Y`.
- **NLK_RETRACT (+6)** — `forget X` / `forget about X` /
  `remove X` / `delete X` / `unlearn X` / `withdraw X` /
  `retract fact X`.
- **NLK_CAPSULE_INSTALL (+5)** — `add capsule X` / `load capsule X` /
  `import capsule X` / `enable capsule X` / `install pack X`
  (`pack` is a `capsule` synonym).
- **NLK_SKILL_INSTALL (+4)** — `add skill X` / `load skill X` /
  `enable skill X` / `activate skill X`.
- **NLK_CAPSULE_LIST (+7)** — `show capsules` / `show all capsules` /
  `list all capsules` / `what capsules are installed` /
  `which capsules do i have` / `installed capsules` /
  `available capsules`.
- **NLK_SKILL_LIST (+7)** — same shapes as CAPSULE_LIST with
  `skills`: `show skills` / `show all skills` / `list all skills` /
  `what skills are available` / `which skills do i have` /
  `installed skills` / `available skills`.
- **NLK_SKILL_RUN (+6)** — `execute X on Y` / `use [skill] X on Y` /
  `invoke X on Y` / `apply X to Y` / `run X with Y`.
- **NLK_NONE (+6)** — filler / greeting-only utterances now return
  NONE (a greeting isn't a query): `hi` / `hey` / `hello` / `um` /
  `uh` / `hmm`, including multi-token combinations like `hi there`.
  Pure-punctuation inputs (`?`, `!`, `.`, `...`) already returned
  NONE via the empty-token path.

**Preamble stripping.** Before pattern matching, common polite /
filler leading tokens are removed in a fixed-point loop so
`please tell me about X` and `could you please tell me about X` both
parse identically to `tell me about X`. Leading strips: `please`,
`hey`, `hi`, `hello`, `um`, `uh`, `hmm`, `hi there`, `hello there`,
`hey there`, `can|could|would|will you`, `may i ask`, `i want to`,
`i would like to`, `i d like to` (post-apostrophe-stripping tokens
for `i'd like to`). Trailing strips: `please`, `thanks`, `thank you`.
`not` is NEVER stripped — that would change meaning. This preamble
layer multiplies coverage: every base pattern gets its polite
variants for free.

**Priority discipline.** Longer / more-specific patterns run first;
looser ones (single-word verb prefixes, suffix forms, declarative
`X is a Y`, and the terminal `why X` catch-all) run last. Regression
guards ensure `install capsule X` still routes to CAPSULE_INSTALL
(not RESEARCH about "capsule X"), `add capsule X` beats RESEARCH,
`forget X` beats RESEARCH, and 2-token bare list forms
(`installed capsules`) beat the late-firing declarative IS_A.

**Tests (409 new checks in `test_nl_grammar_parser`, 103 -> 512
total).** Every new phrasing has at least one direct assertion of
(kind, args); the `test_r97_every_new_pattern_validates` sweep
additionally re-checks that every added phrasing produces an
`sq_validate == SQ_OK` structured query, so no pattern silently
constructs an ill-formed SQ. Preamble tests cover single strips,
nested strips (`could you please tell me about X`), 4-token
whole-phrase strips (`i would like to know about X`), the
apostrophe-tokenized `i'd like to` form, and trailing strips
(`please`, `thanks`, `thank you`). Filler-only inputs (`hi`,
`hello`, `hmm`, `um uh hmm`, `hi there hello`) are asserted to
return `NLK_NONE`, not `NLK_UNPARSED` — a greeting should not fire
the LLM sidecar.

**Effect on the R96 metric.** `nl.metrics` snapshots
`fallback_rate = llm_attempts * 10000 / total` in basis points
(§7.46). Before R97, every one of the newly-recognized phrasings
produced an `NLK_UNPARSED` and either fired the sidecar (raising
`llm_attempts`) or refused (still counted as `unparsed`). After
R97, the same inputs return an `sq_*` from the grammar path,
skipping both counters and thus lowering `fallback_rate` for any
holder whose traffic contains these forms. No absolute-baseline
number is quoted here — the metric is per-holder and per-workload,
so operators observe their own reduction against their own baseline
via `scripts/rpc.sh nl.metrics` before/after upgrading. The point
of R97 is that a reduction is now **possible without touching the
sidecar** — the ADR-0211 objective (LLM-free NLP as the primary
path) advances by a full step.

**Not touched.** The `StructuredQuery` shape (`query_shape.nova`),
executor kind dispatch (`executor.nova`), templater, RPC verbs,
LLM parser, and R96 metrics wire are all unchanged. This is a pure
front-end recognizer expansion. The next Phase C candidate (R98)
adds a hyperdimensional-computing prototype-vector intent classifier
that handles freeform inputs the grammar STILL misses (before the
sidecar), and is also measurable via `nl.metrics`.

**References**: ADR-0104 (NL Surface Layer), ADR-0211 (LLM-free NLP
as primary path; fallback rate as tuning signal), §7.46 (the metric
that R97 moves).

### 7.48 HDC prototype-vector intent classifier (R98 — Phase C part 3)

R97 pushed the grammar rung from ~12 to ~85 patterns. R98 fills the
middle rung of the ADR-0211 three-rung pipeline so freeform
utterances that STILL slip past the grammar have a symbolic, offline
path to try BEFORE the sidecar LLM. The pipeline order is now:

    grammar_parse                   -- src/nl/grammar_parser.nova   (R48p2, R97)
    -> nl_ic_try_classify            -- src/nl/nl_intent_classifier.nova (R98)
    -> nl_llm_try_fallback           -- src/nl/nl_llm_sidecar.nova   (R95)

Both call sites (`_rpc_verb_nl_ask` in `src/nl/rpc_verbs.nova` and
`_try_nl` in `examples/crossengin_chat.nova`) funnel through the new
shared helper `nl_pipeline_try_fallback_rungs` in
`src/nl/nl_pipeline.nova`, so the ordering + metric-touch contract
lives in ONE place. A future rung (e.g. KG-driven paraphrase) only
edits that helper.

**Algorithm.** For each SQ kind, hand-authored training utterances
are tokenized + preamble-stripped, and each token is looked up in
the R-P1 HDC layer's deterministic symbol table
(`hdc_symbol(label)`, 10 000-dim bipolar hypervector). Utterance
vectors are HDC-bundled (element-wise sum + majority-clip), and
utterance vectors are bundled again into a per-kind PROTOTYPE
vector. Classification:

1. Tokenize + preamble-strip the raw utterance.
2. Bundle its token-vectors into an utterance vector.
3. Compute cosine similarity against every prototype
   (`hdc_cosine`, milli-scale, converted to basis points).
4. Pick the winner; hit iff `sim_bp >= threshold` (default 3500).
5. Slot-fill from the utterance tokens (kind-specific: strip
   signal words, split on connectors); validate via `sq_validate`;
   fall through to unparsed if either step fails.

**Deterministic + offline.** `hdc_symbol` is a pure function of the
label (FNV-1a seed + bounded LCG), memoised under the 8192-entry
HDC cache. Same corpus + same input → bit-identical prototype +
similarity every time, across processes and snapshots. No network,
no floats.

**Training corpus.** Ships at `data/nl_intent/prototypes.txt` for
operator inspection, and is ALSO embedded in the classifier module
(`_nlic_corpus_blocks` in `src/nl/nl_intent_classifier.nova`) so
daemon boot needs no file I/O — the sandbox container's `sys_open`
on `/tmp` aborts (see `docs/NOVA_RUNTIME_GAPS.md`), and reading a
data file at every start would inherit the same risk. Keep the two
in sync when adding utterances (a later round can unify them). The
starter corpus authors 10-20 utterances per kind (skipping NONE /
UNPARSED) across biology / physics / history / ops / meta topics so
no prototype vector is locked to one domain lexicon.

**Threshold** (`CROSSENGIN_NL_IC_THRESHOLD_BP`, default 3500).
Integer basis points; 0-10000 (10000 = 100% cosine similarity).
Chosen empirically against the shipped 10-kind corpus: on-topic
paraphrases score 4000-5900 bp; two-word non-sense inputs land
around 3000-3200 bp; clearly-off inputs (unknown vocabulary
throughout) land below 500 bp. 3500 clears the noise floor with
room to spare while still catching on-topic paraphrases. Lower
values raise hit rate (and mis-classification risk); higher values
push more traffic to the sidecar. The chosen threshold is emitted
at module init via a `println` for operator visibility.

**Slot fill.** The classifier recognizes intent, not full
structure. For simple single-arg kinds (RESEARCH / RETRACT /
CAPSULE_INSTALL / SKILL_INSTALL) the recovered slot is the
utterance minus a kind-specific "signal words" list — the tokens
that identify the intent (e.g. `explain` / `describe` / `about`
for RESEARCH) get stripped and the remainder is the topic. For
two-arg kinds (RELATE / IS_A / SKILL_RUN) the utterance is split
on a known connector (`and` / `to` / `vs` / `versus` / `with`
for RELATE; `a` / `an` for IS_A; `on` / `with` / `using` for
SKILL_RUN). If the split cannot yield two non-empty slots the
classification is DROPPED — a slot-fill failure returns
`sq_unparsed` rather than a malformed SQ, so the executor's
invariants stay intact. CONTRADICT_SCAN copies its topic into both
argument slots (grammar's existing 1-topic → 2-slot convention).
Every constructed SQ is passed through `sq_validate`; an
SQ_ERR_ARITY / SQ_ERR_EMPTY_ARG also aborts to unparsed.

**Metrics** (extends `src/nl/nl_metrics.nova`; the R96 wire verb
picks up the new fields automatically):

- `classifier_attempts` — inc'd every time the classifier is
  invoked (i.e. grammar returned UNPARSED and the classifier ran).
- `classifier_hits` — inc'd when the classifier returned a valid
  SQ (kind other than UNPARSED, `sq_validate == SQ_OK`).
- `classifier_misses` — inc'd otherwise. Invariant:
  `classifier_attempts == classifier_hits + classifier_misses`.
- `classifier_hit_rate` — derived field in the `nl.metrics`
  response, in basis points:
  `classifier_hits * 10000 / classifier_attempts`;
  0 when `classifier_attempts == 0`. Independent of the R96
  `fallback_rate` — a classifier hit BYPASSES the sidecar
  entirely, so `llm_attempts` stays at 0 for those calls.

**Response schema.** `nl.metrics` responses (both per-holder and
`_total_all_holders` aggregate) gain four fields beyond the R96
payload: `classifier_attempts`, `classifier_hits`,
`classifier_misses`, `classifier_hit_rate`. Existing consumers
ignoring the new fields see the R96 payload unchanged.

**Effect on the R96 metric.** Every classifier HIT is an utterance
that would otherwise have been counted against `llm_attempts`. So
`fallback_rate` (in bp, the ADR-0211 target) drops by the exact
count of hits per holder, no sidecar-side change required. The
new `classifier_hit_rate` sits alongside `fallback_rate` on the
dashboard: fallback shrinking while classifier hit-rate rises is
Phase C progressing; both stagnant means the next rung of expansion
(more training utterances, or a new prototype) is due.

**Tests.** `tests/unit/test_nl_intent_classifier.nova` (71 checks)
covers init idempotence, prototype count, self-similarity on
training utterances, paraphrase classification, threshold default,
off-topic misses, all seven slot-fill kinds, validator
fall-through, per-holder metric increments, and prototype
determinism (same corpus → identical similarity). Extended
`test_nl_metrics` (74 checks total; +23) exercises the new IC
counter mutators + reads + snapshot slots. Extended
`test_nl_rpc_metrics_verb` (89 checks total; +8) asserts the new
response fields on both the aggregate branch and the per-holder
branch. Extended `test_nl_rpc_llm_fallback` (43 checks total;
+15) asserts the classifier-hit-skips-sidecar invariant, the
classifier-miss-falls-to-sidecar path, and the
grammar-hit-touches-neither-rung fast path.

**Not touched.** SQ shape (`query_shape.nova`), executor kind
dispatch, templater, LLM parser, and the grammar parser are all
unchanged. No new SQ kinds introduced — the classifier only routes
utterances into the same 11 kinds the executor already dispatches.
The three rungs stay independent: a future round can swap any rung
without touching the others.

**References**: ADR-0104 (NL Surface Layer), ADR-0051
(HDC / VSA embeddings — the substrate this reuses), ADR-0211
(LLM-free NLP as primary path; fallback rate as tuning signal),
§7.45 (sidecar), §7.46 (metrics wire verb + basis-points math),
§7.47 (R97 grammar expansion — the neighbouring rung).

### 7.49 bake_child factory (R99 — Phase D part 1)

R99 delivers the first slice of the mother/child bake factory promised
in ADR-0203 + ADR-0204. A mother daemon reads a `BakeManifest`, walks
its live registries under the manifest's allowlists + KG-atom filter,
and emits a signed line-oriented bundle a child runtime will consume.
R100 (`--child-mode`) and R101 (signed KG-delta channel) are the
next Phase D rounds; R99 stops at the produce-and-sign step.

**Wire verb:** `admin.bake_child` (cap `admin:bake`, admin role only).

    args:
      manifest_text  (inline text)  -- OR --
      manifest_path  (readable file path)
      output_path    (optional; defaults to
                      $CROSSENGIN_BAKE_DIR/<name>-<version>.bundle)

    response (on ok=true):
      { name, version, domain,
        bundle_path, bundle_bytes_len, signature_bytes_len,
        personas, capsules, skills, patterns, policies,
        kg_atoms, ownership_entries }

Refusals: signer keys missing, malformed manifest, unreadable
manifest_path, no bake dir configured (when output_path absent),
write failure.

**Manifest format** (`src/factory/bake_manifest.nova`):

    BAKE-MANIFEST v1
    NAME solar-child
    VERSION 0.1.0
    DOMAIN astronomy
    ALLOW_CAPSULE solar_system                # repeatable
    ALLOW_SKILL research                      # repeatable
    ALLOW_PATTERN debug_common                # repeatable
    PERSONA_USER alice                        # repeatable
    ALLOW_POLICY auto_wikidata                # repeatable
    ALLOW_KG_CAPSULE solar_system             # KG-atom filter (repeatable)
    ALLOW_SOURCE_PREFIX solar_                # KG-atom filter (repeatable)
    ALLOW_LICENSE OPEN                        # KG-atom filter (repeatable)
    STYLE plain                               # optional single style pin
    # comment lines start with '#'; blank lines ignored

Comment + blank lines are ignored; duplicate `ALLOW_*` directives
aggregate; unknown directives are refused with a naming error.
`NAME`, `VERSION`, `DOMAIN` are required (empty allowlists are
legal — the bundle carries empty-of-that-kind sections). The literal
`*` in any ALLOW list acts as a wildcard for that predicate.

**KG-atom filter** (`src/factory/kg_filter.nova`). An atom is
selected iff ANY of:

  1. It belongs to a capsule named in `ALLOW_KG_CAPSULE`.
  2. Its KG label starts with any prefix in `ALLOW_SOURCE_PREFIX`.
  3. Its `atom_license` (int) matches any license name in
     `ALLOW_LICENSE` (`UNKNOWN` / `OWNER` / `OPEN` / `CC_BY_SA` /
     `PROPRIETARY`, mapping to the R32 license constants).

Empty allowlists = no atoms pass. Cross-KG capsule membership can
be over-broad due to the base capsule module's per-id (not per-kg)
membership store; users should scope their `ALLOW_KG_CAPSULE`
entries to capsules that actually cover atoms they want in the
child. A future round tightens this by threading kg-label through
capsule membership.

**Bundle format** (line-oriented ASCII + hex-encoded signature
footer). Sections emitted in order:

    #CROSSENGIN-CHILD-BUNDLE v1
    #name <name>
    #version <ver>
    #domain <domain>
    #baked-at <now>
    #mother-fingerprint <sha256-of-signer-pk-hex>

    #PERSONA v1        ... personas from PERSONA_USER intersect ...
    #OWNERSHIP v1      ... entries whose (kind, name) is in the
                            corresponding ALLOW_* list ...
    #POLICY v1         ... policies from ALLOW_POLICY intersect ...
    #PATTERN v1        ... pattern capsules from ALLOW_PATTERN ...
    #SKILL v1          ... skills from ALLOW_SKILL intersect ...
    #CAPSULE v1        ... capsules from ALLOW_CAPSULE, with
                            atom-ref labels (not raw atom-ids) so
                            the child can rehydrate against its
                            own KG section ...
    #KG v1             ... ATOM + XREF lines for atoms selected by
                            the R99 filter ...

    #SIGNATURE <hex-128>
    #SIGNER-PK  <hex-64>

Note: NO `#CAPS v1` (bearer tokens stay with the mother) and NO
`#TRUST v1` (trust anchors stay with the mother). The child boots
without secrets it wasn't explicitly provisioned with.

**Signature** (`src/persistence/bundle_signing.nova`). Signs SHA-256
of the bundle bytes UP TO but NOT INCLUDING the `#SIGNATURE` line;
Ed25519 via the existing R16A `merkle_sign` primitive. The child
recomputes the same digest over the same prefix on verify.

**Signer keys** come from ENV (secure_random is seccomp-blocked in
this container; keys MUST be provisioned externally):

    CROSSENGIN_MOTHER_SIGNER_SEED_B64   -- base64(32-byte Ed25519 seed)
    CROSSENGIN_MOTHER_SIGNER_PK_B64     -- base64(32-byte Ed25519 pub key)
    CROSSENGIN_BAKE_DIR                 -- absolute path; where the
                                            bundle file lands

The sidecar (see §7.44 recipe) generates the keypair, exports both
env vars to the mother daemon's environment, and holds the private
seed for the lifetime of the mother. A child that trusts a mother
carries the mother's PK as its anchor (R100 wires this).

**Files** (R99):

  * `src/factory/bake_manifest.nova`   -- parser + validator + serializer
  * `src/factory/kg_filter.nova`       -- atom predicate + selection walker
  * `src/factory/bake.nova`            -- pipeline + bundle format + verify
  * `src/persistence/bundle_signing.nova`
                                        -- Ed25519 sign / verify + env loader
  * `src/sandbox/session_snapshot.nova` -- 5 `_scoped` section serializers
  * `src/persistence/snapshot_disk.nova`
                                        -- `kg_section_build_scoped`
  * `src/sandbox/capability.nova`      -- `CAP_ADMIN_BAKE` constant +
                                            verb-required + admin role
  * `src/nl/rpc_verbs.nova`            -- `_rpc_verb_admin_bake_child`
                                            handler + dispatch + name

**Tests** (all green): `test_bake_manifest` (81 checks),
`test_kg_filter` (22 checks), `test_bundle_signing` (25 checks),
`test_bake` (53 checks), `test_admin_bake_child_verb` (20 checks).
Verb count 37 → 38 in `test_nl_rpc_verbs`.

**Backwards compat:** `session.save` / `session.load` unchanged.
Existing whole-daemon serializers preserved; scoped variants sit
beside them and are invoked ONLY by `bake_child`.

**References:** ADR-0203 (BakeManifest), ADR-0204 (Signed bundle),
ADR-0104 (NL Surface Layer), ADR-0105 (Sandbox Architecture), R16A
Merkle signing.

### 7.50 `--child-mode` runtime flag (R100 — Phase D part 2)

R99 shipped `admin.bake_child`, which produces a signed child bundle
from a filtered snapshot of a mother daemon's registries. R100
delivers the **other** half of the mother/child arc: the slim runtime
that LOADS one of those bundles at boot and serves it read-mostly.

**Boot contract (env vars, all optional):**

```
CROSSENGIN_CHILD_MODE=1
    Turn child mode on. Any other value (unset / "0" / other) leaves
    the daemon in mother mode, byte-identical to pre-R100 boot.

CROSSENGIN_CHILD_BUNDLE_PATH=<abs-path>
    Absolute path to a signed bundle produced by admin.bake_child.
    Required when CROSSENGIN_CHILD_MODE=1.

CROSSENGIN_MOTHER_ANCHOR_PK_B64=<base64(32-byte-pk)>
    The mother's Ed25519 public key. Trust anchor for verifying the
    bundle signature. Required when CROSSENGIN_CHILD_MODE=1.
    Distinct from CROSSENGIN_MOTHER_SIGNER_PK_B64 (which the mother's
    baker side uses): the child never signs, only verifies, so it
    carries just the anchor -- never the signer seed.
```

**Boot sequence:**

```
1. main()
2. call child_mode_bootstrap_from_env():
     - env unset -> ok=0, err="" -> proceed as mother-mode daemon.
     - env=1 but bundle missing / anchor missing / bundle unreadable
       / bad base64 / wrong-length pk / signature mismatch
                 -> ok=0, err="<reason>" -> daemon PRINTS the reason
                    and REFUSES TO START (a silent fallback would
                    demote trust without the operator noticing).
     - happy path -> ok=1, payload = [bits, bundle_text].
3. apply the bundle via
     session_snapshot_apply_ex(bundle_text, persona_reg, cap_reg,
                                trust_reg, overlay, policy_reg,
                                skill_reg, now)
   (bundle carries #PERSONA + #OWNERSHIP + #POLICY + #PATTERN +
   #SKILL + #KG sections; NO #CAPS / #TRUST -- bearer tokens are
   per-mother secrets, provisioned out of band).
4. call rpc_ctx_set_child_mode_bits(ctx, CHILD_MODE_ACTIVE) so every
   subsequent request runs through the disable-table gate below.
```

**Verb disable table (refused when the CHILD_MODE_ACTIVE bit is
set on a ctx):**

```
ingest.file              admin.rotate_token   capability.issue
ingest.policy.add        admin.set_qps        capability.revoke
ingest.policy.list       admin.set_expires    ownership.transfer
ingest.policy.remove     admin.grant_cap
capsule.install          admin.remove_cap
skill.install            admin.set_revoked
pattern.install          admin.set_holder
session.save             admin.bake_child
```

**Verbs still enabled in child mode:**

```
nl.ask     nl.metrics       kg.list          capsule.list
skill.list skill.run        pattern.list     capability.list
session.load session.list   ownership.list
persona.show  persona.project   nl.parse_only
```

**Refusal message shape:** `verb disabled in child-mode runtime:
<verb>` -- fixed, grep-able, distinct from the `capability
required: ...` shape the sandbox layer emits.

**KG immutability:** enforced at the WIRE, not deep in `kg_insert`.
Every atom-mutating surface a child daemon exposes runs through one
of the disable-table verbs (ingest.file for pipeline ingest;
capsule.install / skill.install / pattern.install for registry
additions; admin.* for token / cap / holder mutation). An internal
reasoning path that mutated KG mid-`nl.ask` would still see mutable
atoms -- that is a hypothetical latent bug in `nl_execute_scoped`,
NOT an R100 gap; belt not suspenders. If R101 or later grows an
`nl.ask` path that mutates, the correct fix is to make that path
consult the ctx bit; deep-gating every atom-store call would be
suspenders without a belt-side threat.

**Gate ordering:** `rpc_dispatch` calls `capability_authorize_ex`
which folds the child-mode check IN FRONT OF the pre-R100 cap check.
When both would refuse, the child-mode message wins so an operator
sees the actual reason (the caller's token may legitimately hold the
required cap; child mode is what's forbidding it). Enabled verbs
fall through to the pre-R100 cap path unchanged.

**Child bundle provisioning recipe** (illustrative shell):

```
# On the mother host:
#   sidecar sets CROSSENGIN_MOTHER_SIGNER_SEED_B64 + _PK_B64.
#   Operator calls admin.bake_child with a manifest naming the
#   capsules / skills / patterns / personas / policies / KG atoms
#   that the child should be allowed to see.
$ echo '{"verb":"admin.bake_child","token":"<admin>",
         "args":{"manifest_path":"child-astro.manifest"}}' \
  | nc -q1 127.0.0.1 9876
# -> {"ok":true,"result":{"bundle_path":"/var/lib/crossengin/bake/
#     astro-child-0.1.0.bundle", ...}}

# Ship both the bundle AND the mother's public key (NOT the seed)
# out of band to the child host:
$ scp /var/lib/crossengin/bake/astro-child-0.1.0.bundle \
      child.host:/var/lib/crossengin/child/
$ echo "$CROSSENGIN_MOTHER_SIGNER_PK_B64" \
      | ssh child.host 'cat > /var/lib/crossengin/child/anchor.pk.b64'

# On the child host, boot the daemon in child mode:
$ export CROSSENGIN_CHILD_MODE=1
$ export CROSSENGIN_CHILD_BUNDLE_PATH=/var/lib/crossengin/child/astro-child-0.1.0.bundle
$ export CROSSENGIN_MOTHER_ANCHOR_PK_B64="$(cat /var/lib/crossengin/child/anchor.pk.b64)"
$ export CE_RPC_PORT=9877
$ ./bin/crossengin-rpc-daemon
=== CrossEngin JSON-RPC daemon ===
listening on 127.0.0.1:9877  (max_request=65536 bytes)
child-mode: ON -- bundle loaded from /var/lib/crossengin/child/astro-child-0.1.0.bundle
           bundle signature verified under anchor pk;
           KG immutable + ingest/bake/admin verbs refused.

# Verify from a client -- read verbs work:
$ echo '{"verb":"kg.list"}' | nc -q1 127.0.0.1 9877
{"ok":true,"result":["world"], ...}
# ingest is refused:
$ echo '{"verb":"ingest.file","args":{}}' | nc -q1 127.0.0.1 9877
{"ok":false,"error":"verb disabled in child-mode runtime: ingest.file"}
```

**Files** (R100):

  * `src/factory/child_mode.nova`      -- bootstrap + disable table +
                                          bit constants (~280 lines)
  * `src/nl/rpc_verbs.nova`            -- `RCTX_CHILD_MODE_BITS`
                                          slot + `rpc_ctx_is_child_mode`
                                          + dispatch calls
                                          `capability_authorize_ex`
  * `src/sandbox/capability.nova`      -- `capability_authorize_ex`
                                          (child-mode gate composed
                                          with pre-R100 cap check)
  * `examples/crossengin_rpc_daemon.nova`
                                        -- boot-time bootstrap +
                                           `session_snapshot_apply_ex`
                                           + set-bits call; refuses to
                                           start on bootstrap failure

**Tests** (all green): `test_child_mode` (59 checks -- bit constants,
env-off no-op, disable table, refusal shape, verify tamper/wrong-pk
paths); `test_child_mode_wire` (46 checks -- ctx slot round-trip,
higher-bit semantics, every disabled verb refused at wire, every
enabled verb NOT child-refused, `capability_authorize_ex` ordering,
verb count still 38); `test_capability_wire` gains 4 R100 ordering
checks (253 total). Regression sweep clean on `test_capability_wire`,
`test_nl_rpc_verbs`, `test_nl_rpc_server`, `test_session_snapshot`,
`test_ownership`, `test_bake_manifest`, `test_bake`,
`test_admin_bake_child_verb`, `test_bundle_signing`, `test_kg_filter`,
`test_capability`.

**Backwards compat:** With `CROSSENGIN_CHILD_MODE` unset, the daemon
boots byte-identically to R99. `capability_authorize` is unchanged;
`capability_authorize_ex` wraps it and reduces to the same function
when `child_mode_bits=0`.

**Verb count unchanged at 38** — R100 adds no new verbs; the wire's
surface area shrinks (disable table) rather than expanding.

**References:** ADR-0203 (BakeManifest), ADR-0204 (Signed bundle),
ADR-0104 (NL Surface Layer), ADR-0105 (Sandbox Architecture), §7.49
(R99 bake pipeline).

### 7.51 Per-user selective load (R101 — Phase E)

ADR-0205 (Mode 2) says one mother should be able to serve many
effective views: the same daemon, but each user sees only the parts
they opted in to. R101 wires that as a soft-filter layer on TOP of the
R55.2 ownership overlay — ownership stays the hard boundary (operator
authority; admin-only mutation), preferences become the user's own
opt-in list within what ownership already allows.

**Composed visibility:**

```
composed_visible(H, kind, name) =
    ownership_visible(overlay, kind, name, H)
AND preference_visible(pref_reg, H, kind, name)
```

* ownership decides whether H is ALLOWED to see this at all.
* preference decides whether H CURRENTLY wants to see it.

Default is opt-in: absence of a preference row means visible (fall
through to ownership). Only an explicit `enabled=0` entry (or a
matching wildcard) hides an item; ownership-blocks always win.

**Three wire verbs (verb count 38 -> 41):**

| Verb                     | Cap                     | Purpose                                                       |
|--------------------------|-------------------------|---------------------------------------------------------------|
| `user.preference.set`    | `nl:preference:write`   | Set a per-user (kind, name) -> enabled bit; `holder` optional |
| `user.preference.list`   | `nl:preference:read`    | Enumerate the caller's preferences (or another's, with admin) |
| `user.preference.clear`  | `nl:preference:write`   | Clear one entry or all entries for the caller                 |

Three new caps:

- `nl:preference:read`  — bundled with the READER role.
- `nl:preference:write` — bundled with the READER role.
- `admin:preference`    — admin-only; required to pass a `holder` arg
  targeting another user's preferences.

**Kinds** match the R55.2 ownership vocabulary: `capsule`, `skill`,
`pattern`, `kg`.

**Wildcards.** A name of literal `"*"` applies the entry to EVERY
name of that kind for that holder. Only kind-wide disable makes
practical sense; a matching per-name enable STILL WINS the visibility
check.

**Example — user hides all pattern packs from themselves:**

```bash
# Alice decides she wants a quieter menu.
CE_RPC_TOKEN=$(cat ~/tok-alice) scripts/rpc.sh \
    user.preference.set kind=pattern name='*' enabled=0

# pattern.list now returns [] for alice (her wildcard),
# still returns everything for bob (his registry is empty).
scripts/rpc.sh user.preference.list
# {"holder":"alice","preferences":[{"kind":"pattern","name":"*","enabled":0}],"count":1}

# Alice changes her mind about one specific pack:
scripts/rpc.sh user.preference.set \
    kind=pattern name=debug_common enabled=1
# debug_common now visible again, everything else still hidden.

# Reset everything:
scripts/rpc.sh user.preference.clear all=1
```

**Wired into list verbs:** `kg.list`, `capsule.list`, `skill.list`,
`pattern.list` all now consult `visibility_visible(overlay, pref_reg,
kind, name, holder)` in place of the old `ownership_*_visible`
helpers. Absent a preference registry (default before daemon boot
wires one), the composed check collapses to pure ownership — every
pre-R101 caller sees byte-identical behavior.

**Dispatch gating:** the R57/R60 skill dispatch check
(`skill.run` + `nl_execute_scoped_ex`'s "research" gate) also
consults the composed helper — a user who wildcard-hides skills from
their menu also cannot dispatch them until they clear the preference.

**Snapshot round-trip:** `session.save`/`session.load` carry a new
`#PREFERENCE v1` section:

```
#PREFERENCE v1
PREF alice skill research 0
PREF alice pattern * 0
PREF bob capsule solar_system 0
```

Section is omitted when no preference registry is wired OR the
registry is empty; lenient parser drops malformed rows.
`session_snapshot_serialize_ex` gains a `preference_reg` parameter
between `skill_reg` and `include_secrets`; `session_snapshot_apply_ex`
takes the mirror slot before `now`. Bake bundles (R99) always pass
`0` for that slot — per-user state is mother-side, not baked.

**Interaction with child-mode (R100):** a child-mode daemon still
serves `user.preference.*` since preferences are per-user soft
choice, not a factory operator boundary. A child's bundle allowlist
becomes the outer envelope; user preferences carve the personal
subset.

**References:** ADR-0205 (Per-User Selective Load; Mode 2),
ADR-0105 (Sandbox Architecture; the R55.2 overlay this composes with),
`src/preference/user_preference.nova`, §7.9 (R55.2 ownership overlay
this composes with), §7.10 (R55.3 snapshot round-trip this extends).

## 12. What comes next (R90+)

**TLS build-out (R86..R94) is COMPLETE.** Primitives, handshake,
wire wiring, sidecar recipe — all in tree; opt-in via
`CROSSENGIN_TLS=1`; see §7.36..§7.44. Front-of-queue is now non-TLS
candidates (see the list further down this section). Any post-R94
TLS work is now pure hardening / feature-add layered on top of the
existing tree (session resumption, client-cert auth, HRR, cert
rotation, OCSP/CRL, SNI multi-cert, ACME sidecar, concurrent TLS —
the R86 ADR's post-scriptum enumerates these).

**TLS build-out (historical roadmap, all ✅; see §7.36..§7.44):**

- **R87** — ✅ Poly1305 + ChaCha20-Poly1305 AEAD (see §7.37;
  RFC 8439 §2.5, §2.8; all vectors green). TLS 1.3 record-layer
  seal/open runs today; handshake still stubbed.
- **R88** — ✅ HKDF-SHA-256 + TLS 1.3 key-schedule wrappers (see §7.38;
  RFC 5869 + RFC 8446 §7.1, §7.3; all RFC vectors green).
  Traffic-secret → (key, iv) derivation ready; handshake still
  stubbed.
- **R89** — ✅ x25519 ECDH (see §7.39; RFC 7748 §5.2 + §6.1; all
  vectors green). Key-share primitive + TLS keyshare glue landed;
  handshake still stubbed, wire still cleartext, RNG source still
  missing (see gap below).
- **R90** — ✅ Ed25519 verify + TLS 1.3 CertificateVerify seam (see
  §7.40; RFC 8032 + RFC 8446 §4.4.3; all vectors green + 41
  cert-seam checks). Audit + widen on the pre-existing
  `ed25519.nova` (R54.2), new `tls_cert.nova` for the RFC 8446
  §4.4.3 signed-content assembly + verify. **Every TLS crypto
  primitive is now in tree.** Remaining TLS work is orchestration.
- **R91** — ✅ CSPRNG source + pluggable RNG interface (see §7.41;
  three backends: OS via `secure_random`, TEST-ONLY deterministic
  ChaCha20-CTR, caller-supplied callback). `tls_keyshare_generate`
  and `tls_random_generate` on the R89 keyshare module now
  RNG-driven. **Caveat**: OS backend is UNAVAILABLE in this
  project's sandbox container (seccomp blocks `getrandom`); use
  Backend C (callback) in that case, wired by a launcher/sidecar.
- **R92** — ✅ X.509 subset parser + cert-chain verify (see §7.42;
  RFC 5280 + RFC 8410, Ed25519-only, chain-len-2, CN-only DN,
  UTCTime + GeneralizedTime with Z suffix). New
  `src/net/tls/der.nova` (73 checks) + `src/net/tls/x509.nova`
  (60 checks) + `tls_cert_verify_chain_and_signature` end-to-end
  wrapper on `tls_cert.nova` (14 checks). Test-cert fixture built
  programmatically via `x509_build_test_cert` (RFC 8032 TEST 1
  root, TEST 2 leaf) — DER assembler colocated at
  `tests/unit/fixtures/x509_test_certs.nova`, signed at test time
  by the in-tree `ed25519_sign`. The R90 seam
  (`tls_cert_verify_ed25519` with a raw 32-byte pubkey) stays for
  the low-level path and its tests; the R92 wrapper adds
  cert-chain gating on top.
- **R93** — ✅ Handshake state-machine wire-up (see §7.43;
  RFC 8446 §4; 120 new checks). In-memory only: two sessions in
  one process exchange bytes through caller-owned queues and
  converge on byte-identical application traffic secrets, then
  round-trip encrypted app data both ways. Consumes R87 (AEAD),
  R88 (KDF), R89 (ECDH), R90 (CertificateVerify), R91 (RNG),
  R92 (cert chain). Explicit simplifications: no 0-RTT, PSK,
  HRR, client cert, key update, post-handshake auth.
- **R94** — ✅ Wire-hook flip + sidecar recipe (see §7.44). Opt-in
  via `CROSSENGIN_TLS=1`; three base64 env vars carry cert material
  (`CROSSENGIN_TLS_LEAF_DER` / `CROSSENGIN_TLS_LEAF_PRIV` /
  `CROSSENGIN_TLS_ROOT_DER`); RNG mode picked via
  `CROSSENGIN_RNG_MODE` (`os` / `test` / `callback`); tiny in-tree
  `src/net/tls/base64.nova` decoder unwraps the env vars into byte
  lists. New `tls_config_new_server` / `tls_config_new_client`
  constructors + role tag. `test_tls_wire_hook` (40),
  `test_tls_config` (22), `test_base64` (35),
  `test_daemon_tls_bootstrap` (9) — 106 new checks. Regression
  green. **TLS build-out is now COMPLETE.**

**Runtime gap (R91 partially addressed):**

- **CSPRNG source.** The RNG interface (R91) unblocks callers by
  giving them a pluggable seam. The OS backend uses NOVA's
  `secure_random` builtin (wraps `getrandom` on Linux). When the
  target environment permits `getrandom`, this backend serves
  entropy end-to-end with no additional work. When it does not
  (seccomp-filtered containers, this project's sandbox included),
  operators wire Backend C (callback) to a sidecar or launcher
  that supplies bytes from a source NOVA cannot reach directly.
  A full HKDF-based DRBG is a candidate for a later round if the
  OS source proves unreliable across target environments.

**TLS COMPLETE (R86..R94) milestone:** primitives, handshake, wire
wiring, sidecar contract — all in tree. Any further TLS work
(session resumption / client-cert auth / HRR / OCSP / SNI /
concurrent handshakes / ACME sidecar) is optional hardening layered
on top; see the R86 ADR's post-scriptum for the full list.

**AI-Factory epic (Phase A + B ✅; Phase C ✅).** Phase A shipped
the vision (ADR-0200..0211 + 5 top-level docs). Phase B (R95) wired
the small-LLM sidecar as the freeform-NL fallback and stood up the
per-holder metrics registry (see §7.45). **Phase C part 1 (R96)**
landed the `nl.metrics` wire verb (see §7.46) so operators can
snapshot the per-holder fallback rate live in basis points — the
ADR-0211 metric that drives the rest of Phase C is now visible.
**Phase C part 2 (R97)** expanded the LLM-free grammar parser from
~12 canonical patterns to ~85 natural phrasings across the same 11
SQ kinds (see §7.47) — the first metric-driven grammar expansion.
**Phase C part 3 (R98)** shipped the HDC prototype-vector intent
classifier as the middle rung of the ADR-0211 pipeline (see §7.48).
Grammar-miss utterances now try a symbolic, offline HDC classifier
(10 kinds, ~130 training utterances, threshold-tuned at 3500 bp)
BEFORE the LLM sidecar; a hit skips the sidecar entirely, dropping
`fallback_rate` by the exact count of hits per holder. The
`nl.metrics` response gains four fields
(`classifier_attempts` / `classifier_hits` / `classifier_misses` /
`classifier_hit_rate`) so both rungs are dashboardable side by
side.

**Phase D roadmap (bake-factory epic; R99 + R100 shipped):**
- **R99 ✅** — `bake_child` + BakeManifest + filtered snapshot +
  signed bundle (see §7.49). Mother produces the artifact; child
  can verify but does not yet CONSUME it.
- **R100 ✅** — `--child-mode` runtime flag + bitmask (see §7.50).
  Boot loads a signed bundle via `session_snapshot_apply_ex`,
  verifies signature under `CROSSENGIN_MOTHER_ANCHOR_PK_B64`, marks
  the KG immutable, disables ingest/bake/admin/install verbs.
  Bundles produced by R99 are now actually loaded and served.
- **R102** — Signed KG-delta update channel (remaining Phase D
  round; was originally R101). Mother emits an incremental delta
  bundle between two moments (`admin.emit_delta`); child verifies +
  applies (`update.apply`) under the anchor from R100. Deltas chain
  via `parent-bundle-fingerprint`.

**Phase E ✅ (R101).** Per-user selective load — the third
consumption mode from ADR-0200. Same mother, per-user overlay that
projects only opted-in items via the new `user.preference.*` verb
family. Composes on top of R55.2 ownership; snapshot round-trips a
new `#PREFERENCE v1` section. Verb count 38 -> 41. See §7.51.

**Front-of-queue after Phase C ✅ / Phase D parts 1 + 2 ✅ /
Phase E ✅:**
- **R102** — signed KG-delta update channel (remaining Phase D
  round). Mother emits an incremental delta bundle; child verifies +
  applies. Deltas chain via `parent-bundle-fingerprint`.
- **KG-driven paraphrase (candidate)** — consult the live KG for
  atom aliases at classify time so a training utterance that says
  "photosynthesis" also matches queries about "photosynthetic
  process" without adding a new corpus line. Slots in as a fourth
  pipeline rung; measurable via the same `nl.metrics` verb.
- **Fallback-rate driven grammar backfill loop (candidate)** — an
  operator tool that reads `nl.metrics` snapshots, harvests the
  top-N high-frequency unparsed inputs from a holder's traffic, and
  suggests new grammar patterns to hand-add.

Each Phase C improvement is directly measurable via the R96 verb;
the fallback-rate basis-points number is the single scalar tuning
target, and R97 + R98 are the first two knobs turned against it.

**Front-of-queue (non-TLS, post-Phase-B; the top three are the
immediate targets):**

1. **Phase C — LLM-free NLP expansion** (see above).
2. **Admin bulk-ops** (multi-token grants / revokes in one wire call).
3. **Per-session pre/post hooks** so a daemon operator can attach an
   audit-log writer without editing `rpc_server.nova`.
4. **Ownership audit log** — a per-holder append-only log of
   `ownership.transfer` and `admin.set_holder` events.
- Per-source rate budgets controllable via admin wire verb (aggregate
  ceilings across many tokens from one origin).
- Per-holder aggregate rate limits (an owner's tokens share a
  combined ceiling).
- Hardware-key-backed admin bootstrap (yubikey attestation on
  `capability.issue` for the first admin token).
- DTLS-12 red-fix (72/450 checks red since R86; unrelated to the
  R87..R94 TLS 1.3 build-out but the tally deserves a pass).
- Consolidation refactor: `bignum_256` / `field25519` overlap —
  both carry 256-bit modular arithmetic paths.

**R95+ epic candidate: Mother/Child architecture.** A concurrent
ADR-0200 draft (parallel R94 work) may land the design for a
process-tree-style deployment where a supervisor "mother" spawns
per-tenant "child" daemons. If that ADR lands under
`docs/adr/adr-0200-*.md`, it becomes the R95+ epic (post-TLS
front-of-queue), and the eight items above deprioritize behind it.
Cross-reference it from here when it exists; ordering is a design
call at R95 kickoff.

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
