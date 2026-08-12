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

**YAML deferred to R67+** — YAML's indentation semantics,
anchors, tags, and flow-style ambiguity are a much larger
surface than JSON's clean grammar; a subset would be
misleading. Operators today can pre-convert YAML with `yq -o
json` at the shell and pipe into the JSON importer.

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

Formats supported at R67: **cerec**, **json**, **csv**,
**ntriples**, **wikidata**, **conceptnet**, **papermeta**,
**wordnet** — every importer whose module ships a
`_parse_text` variant. Each takes the same envelope
(`format` + `body`) plus format-specific args:

| format     | requires `kg` | requires `source` | extra              |
|------------|---------------|-------------------|--------------------|
| cerec      | no (in body)  | no (in body)      | —                  |
| json       | no (default)  | no (default)      | `kg`/`source` default when a record omits them |
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

## 12. What comes next (R73+)

- **R73+** — In-process TLS (retires the sidecar recipe), YAML
  input adapter (or make `jsonr_parse` accept a
  yaml-to-json shim), snapshot round-trip for ingest.policy
  registry (currently a boot-time-only registry; a snapshot
  restore doesn't repopulate it)
- **R74+** — Per-source rate budgets controllable via admin wire
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
