# ADR-0091: Federation durability (snapshot attestation + replication)

- Status: Accepted
- Date: 2026-09-28

## Context

Phase M R1 (ADR-0089) landed `examples/crossengin_fed_daemon.nova`, a single
event-driven binary that composes gossip (R18E), kg_sync deltas (R6C/R7C v3),
and distributed SPARQL query fan-out (R20E) into a runnable mesh peer. Phase
M R2 (ADR-0090) added leader-election (R19E, Bully over gossip) and
distributed-rules (R21B, mini-Datalog broadcast + evaluate) under two opt-out
env flags, plus five live chat REPL handlers (`/leader status|elect`,
`/drule_add`, `/drule_run`, `/drule_fixpoint`).

Two federation primitives were still unit-tested but not wired into the
daemon or the chat REPL:

- **`src/federation/snapshot_attestation.nova`** (R20F) -- gossip-relayed,
  Ed25519-signed `(soul_id, ts_ns, merkle_root, signature)` tuples. Wire
  form: `ATTESTATION <id> <ts> <root_hex> <sig_hex>`. Ships `att_store_new`,
  `att_make`, `att_verify`, `att_to_wire`, `att_parse_wire`, the per-peer
  store accessors (`att_store_for_peer`, `att_store_latest`,
  `att_store_count_for_peer`, `att_store_peer_ids`), and the
  `_gossip_serve_attestation` dispatch in `src/federation/gossip.nova`
  behind `gossip_set_att_store` + `gossip_register_att_pubkey`.
- **`src/federation/snapshot_replication.nova`** (R23C) -- best-effort
  federated snapshot bytes via three new gossip lines (`SNAP_FETCH`,
  `SNAP_DATA`, `SNAP_END`). Ships `sr_init`, `sr_observe_attestation`,
  `sr_observe_snap_response`, `sr_register_local`, and the
  `_gossip_serve_snap_fetch` / `gossip_send_snap_fetch` /
  `gossip_drive_snap_fetches` client-server plumbing behind
  `gossip_set_sr_state`.

The chat REPL stubs at `/attest_log`, `/attest_verify <soul>`,
`/snap_fetch <root>`, `/snap_serve on|off` still printed the pre-Phase-M
"REPL has no gossip daemon (see tests/integration/scenario_*.sh)" line.

This ADR is R3. It wires those two primitives into the R2 fed daemon and
lifts the four chat REPL stubs. Together with R1's query fan-out and R2's
coordination + inference, R3 completes the durability picture: R1 gave
nodes SHARED QUERIES, R2 gave nodes SHARED DERIVATIONS, R3 lets nodes share
SIGNED SNAPSHOTS. This closes the federation-daemon arc for what can be
built without unstubbing DTLS 1.2 (`src/federation/dtls12.nova:137, 140`).

## Decision

**Extend the R2 fed daemon** to allocate the attestation store + replication
state at boot under three new env flags:

| Env var | Default | Effect |
| --- | --- | --- |
| `CE_FED_ATTEST_ENABLED` | `1` | `0` skips `att_store_new` + the Ed25519 keypair load; `/attest_log` and `/attest_verify` print "no state". Any other value keeps attestation on. |
| `CE_FED_ATTEST_KEY_DIR` | `$HOME/.crossengin/fed_keys` | Directory holding this node's `signer.priv` + `signer.pub` (32 bytes each). The daemon passes `<dir>/signer` as the base path to `merkle_signing_keypair_load`, which appends `.priv` / `.pub`. Fallback when HOME unset: `./crossengin_fed_keys/signer`. **Missing key files do NOT crash the daemon**: a WARN log is printed, attestation is disabled for that run, and the mesh peer runs on. |
| `CE_FED_SNAP_REPLICATION_ENABLED` | `1` | `0` skips `sr_init`; `/snap_fetch` prints "no state"; gossip's SNAP_FETCH inbound handler answers with a bare `SNAP_END` (peer sees a miss). |
| `CE_FED_SNAP_SERVE` | `0` (**opt-in**) | `1` calls `sr_set_serving(sr, 1)` at boot so the daemon answers peers' SNAP_FETCH requests with replica bytes; default `0` returns 0 from `sr_serve_snap_request` so peers see SNAP_END. The chat REPL surfaces the same toggle via `/snap_serve on|off`. |
| `CE_SNAP_PATH` | (reused) | Local snapshot directory for `sr_init(gs, local_snap_dir)`. When unset the daemon falls back to `$HOME/.crossengin/snap`; final container fallback is `./crossengin_snap`. `sys_open` on `/tmp` aborts inside the container (per Phase L findings), so `/tmp` is never a fallback. |

Only the literal string `"0"` disables the default-on flags; any other value
(including empty) falls back to the default-on path. `CE_FED_SNAP_SERVE`
inverts this: only `"1"` (or any non-empty non-`"0"` string) enables serving,
matching the ADR's "verify-before-serve" trust posture.

### Ed25519 signer identity

One keypair per node, loaded from `CE_FED_ATTEST_KEY_DIR` at boot. The key
file format is exactly what `merkle_signing_keypair_load(base_path)`
produces via `examples/snap_keygen.nova` at `src/persistence/merkle_signing.nova:412`:

```
<base>.priv   32 bytes, mode 0600
<base>.pub    32 bytes, mode 0644
```

`base_path` is `<CE_FED_ATTEST_KEY_DIR>/signer`. The daemon then registers
its own pubkey under its own peer_id via `gossip_register_att_pubkey(gs,
self_id, pair[1])` so a same-node round-trip verifies the local signer;
peer pubkeys are registered out-of-band by the operator (same shape R7C
Noise XK static-auth already uses). Reading the priv seed at every save
is intentional (matches the R16A `merkle_signing_sign_root_via_env`
comment) -- the substrate does not hold the key in memory between saves,
reducing the blast radius of a memory disclosure between writes.

### Attestation broadcast: piggyback on gossip

The R20F module ships a `gossip_broadcast_attestation(state, att)` that
dials every alive peer, sends `HELLO / ATTESTATION <wire> / BYE`, and
returns the count of successful deliveries. R3 does NOT auto-broadcast on
every snapshot save (that would require an intrusive edit to
`persistence/snapshot_disk.nova`; deferred). Instead, R3 gives operators
and downstream integrations the surface to broadcast when they choose:
either an explicit chat REPL invocation later, or the fed-daemon's
scripted-command drain at `/tmp/crossengin_fed_input`. The `att_store`
is populated by RECEIVING attestations over gossip -- the inbound side
that R3 wires here is the useful half for federation-wide durability
(every node builds a global picture of who sealed which root when).

### Replication opt-in: `/snap_serve on`

`sr_set_serving(sr, on)` (new in R3) toggles a `SR_S_SERVING` slot in the
sr_state. When off (default), `sr_serve_snap_request` short-circuits to
`0` regardless of what the local replica table holds; the gossip serve
handler (`_gossip_serve_snap_fetch`) then answers each inbound SNAP_FETCH
with a bare `SNAP_END`, indistinguishable from a real miss on the wire.
This is deliberate: a node can observe attestations, populate its known-
roots table, and even register its own replicas locally via
`sr_register_local` -- all without shipping anything to the mesh -- until
the operator explicitly reviews and turns serving on. The fed daemon
also exposes `CE_FED_SNAP_SERVE=1` for hands-off deployments where the
policy decision is baked into the environment.

The client side (fetching FROM peers) is NOT gated: any node with
`CE_FED_SNAP_REPLICATION_ENABLED=1` can call `/snap_fetch <root>` to try
to pull a replica in. Verification then goes through
`sr_observe_snap_response`, which enforces the `meta.merkle_root` line
equivalence against the signed attestation's root. A tampered stream
lands in `sr_stats_verify_fail` and is dropped without touching the
replica table.

### Boot alloc order (extends ADR-0089 sec "Component alloc")

1. `kg_registry_new()`
2. `mo_new()`
3. `reasoning_kg_init(kgreg)`
4. `gossip_init(listen_addr, peer_list)`
5. `gossip_listen(listen_addr)`
6. `kgd_state_new()`
7. `dq_init(gs)`
8. (R2) `le_init(gs, _fed_soul_id_to_int(soul_id))` if `CE_FED_LEADER_ELECTION_ENABLED != "0"`
9. (R2) `dr_engine = rule_engine_new(); dr = dr_init(gs, dr_engine)` if `CE_FED_DR_ENABLED != "0"`
10. **NEW (R3):** if `CE_FED_ATTEST_ENABLED != "0"`:
    - `pair = merkle_signing_keypair_load(<CE_FED_ATTEST_KEY_DIR>/signer)`
    - on load failure -> WARN + skip; on success ->
      - `att = att_store_new()`
      - `gossip_set_att_store(gs, att)`
      - `gossip_register_att_pubkey(gs, self_id_int, pair[1])`
11. **NEW (R3):** if `CE_FED_SNAP_REPLICATION_ENABLED != "0"`:
    - resolve `local_snap_dir` from `CE_SNAP_PATH` / `$HOME/.crossengin/snap` / `./crossengin_snap`
    - `sr = sr_init(gs, local_snap_dir)`
    - `gossip_set_sr_state(gs, sr)`
    - if `CE_FED_SNAP_SERVE == "1"`: `sr_set_serving(sr, 1)`

### Tick loop

No new per-tick work. Gossip's parser branches (in
`gossip_handle_conn` and `gossip_handle_conn_kg`) already dispatch
inbound ATTESTATION, SNAP_FETCH, SNAP_DATA, and SNAP_END lines through
`_gossip_serve_attestation` / `_gossip_serve_snap_fetch` /
`_gossip_serve_snap_data` / `_gossip_serve_snap_end` (see
`src/federation/gossip.nova:1220-1450` and `:2740-2870`). Wiring is
purely at boot; the R2 tick body is unchanged.

### Chat REPL wiring

`examples/crossengin_chat.nova` gains two module-level lazy-init
singletons: `_chat_fed_att` (holds `att_store_new()`) and `_chat_fed_sr`
(holds `sr_init(gs, "")`). Both are allocated inside
`_admin_gossip_start` alongside R1's `_chat_fed_gs` / `_chat_fed_dq` and
R2's `_chat_fed_le` / `_chat_fed_dr`, so a single `/gossip_start` boots
the full R1+R2+R3 mesh surface.

| Slash command | Behavior |
| --- | --- |
| `/attest_log` | Dump up to 20 most-recent verified attestations across all peers. Header + one line per entry (`peer=<id> ts=<ns> root=<hex> sig=<hex16>...`). Requires `/gossip_start`. |
| `/attest_verify <soul_id>` | Look up the peer's most-recent attestation via `att_store_latest`, resolve its pubkey via `gossip_lookup_att_pubkey`, and re-verify. Prints `attest_verify: peer=<n> ok` or `... FAILED (<reason>)` with one of: no attestation for peer, no pubkey registered, signature mismatch. |
| `/snap_fetch <root_hex>` | Validate the 64-char lowercase-hex root; walk `gossip_alive_peers`; dial each with `gossip_send_snap_fetch`; stop on first success. Empty alive set or unknown root prints a refusal. |
| `/snap_serve on|off` | Toggle `sr_set_serving`. Off means peers' SNAP_FETCH requests get bare SNAP_END back (miss); on means the sr_state's local replica table is served. |

Argument parsing and output formatting live in `src/chat/fed_slash.nova`
so the tests can validate the exact wire shape without spinning up a
live gossip listener. Five new helpers land there: `_attest_log_format`,
`_attest_verify_result_line`, `chat_fed_att_verify_parse_arg`,
`_snap_fetch_result_line`, `_snap_serve_toggle_result_line`, plus the
"no state" and "usage" lines.

## Consequences

**Positive**:

- The federation daemon can now produce, receive, verify, and serve
  signed snapshot attestations. Combined with R23C's replica table +
  verify-before-store contract, this gives the mesh **cryptographically
  provable durability**: any peer can retrieve any signed root's bytes
  from any peer that has cached them, and reject anything the signature
  does not cover.
- Chat REPL parity: all four R20F/R23C stubs replaced by real handlers.
  Operators can inspect a live mesh's attestation state without
  spawning a second process, the recommended production entry point
  remains `examples/crossengin_fed_daemon.nova`.
- Opt-in serving means a node can safely join a mesh, observe roots,
  and even build its own attestation history before deciding to ship
  replica bytes. No default surprise-data-transfer footgun.
- Env-flag resolvers mirror R1/R2 shape (default-on flags: only `"0"`
  disables; `CE_FED_SNAP_SERVE` inverts this: default-off, `"1"`
  enables) so operators do not have to learn a new idiom for R3.
- Ed25519 keypair loading reuses R16A's `merkle_signing_keypair_load`
  entry point -- no new crypto surface, no new file-format footprint.
  A missing key file is a WARN, not a crash: the daemon keeps running
  as a mesh peer without attestation.

**Negative**:

- The daemon does NOT auto-broadcast an attestation on every snapshot
  save. That requires an intrusive edit to `persistence/snapshot_disk.nova`
  to notify the mesh -- deferred because R3's boundary is "wire in what
  is already unit-tested". Follow-up: hook `gossip_broadcast_attestation`
  into the save path via a callback slot on the Session shape.
- The chat REPL does NOT load an Ed25519 signer keypair. `att_make`
  needs `(seed, pk)` and the chat process does not know where the
  operator keeps them. The chat is a viewer for the OBSERVED-from-peers
  side of the store; the fed daemon is the signing side. This is a
  deliberate separation of concerns (the fed daemon is a long-running
  process with well-defined key state; the chat is an operator surface).
- `sr_serve_snap_request` now gates on the new `SR_S_SERVING` slot.
  Existing unit + integration tests that asserted "on hit, bytes are
  returned" needed a `sr_set_serving(sr, 1)` prelude added. This is
  additive; no removed callers.

**Deferred (still blocked on stubs)**:

- **DTLS 1.2 unstub** -- `src/federation/dtls12.nova:137, 140` R29B2
  cert-verify + SRTP EKM stubs. Once landed, swap gossip's TCP for
  DTLS and the mesh gets encrypted attestation transport.
- **NAT hole-punch** -- R23E.2 pending NOVA `sendto`/`recvfrom`
  primitives (`src/federation/nat_traversal.nova:874, 1162`).
- **WebRTC data plane** -- `webrtc.nova` signaling half only; data
  plane returns `RTC_ERR_NEEDS_DTLS` until DTLS is unstubbed.
- **Raft wire integration** -- `raft_*.nova` currently in-memory
  harness only; no wire integration.
- **Auto-broadcast on snapshot save** -- see "Negative" above.

**This closes the federation-daemon arc for the plain-TCP era.** Every
one of the 23 modules under `src/federation/` that CAN be wired without
unstubbing DTLS 1.2 now IS wired into either the fed daemon
(`examples/crossengin_fed_daemon.nova`) or the chat REPL
(`examples/crossengin_chat.nova`), with parity between the two so an
operator can either drive the mesh from a script or inspect it live.

## Alternatives Considered

**Auto-broadcast in `snapshot_disk.nova`.** Rejected for R3: the save
path currently has no gossip dependency, and adding one would either
(a) require a callback-slot edit to the snapshot writer, or (b) invert
the persistence-does-not-depend-on-federation import order that keeps
the two subsystems buildable in isolation. Deferred as a follow-up ADR
once the shape of the callback is clearer.

**Default-on `sr_set_serving`.** Rejected: a fresh node joining the
mesh should not automatically ship its snapshots to whoever asks. The
plan explicitly calls out "opt-in per plan: don't send bytes to peers
unless explicitly enabled". The default-off contract also matches the
"verify-before-use" trust posture the ADR takes for the client side
(receiver verifies signed root before storing).

**Chat REPL loads a signer keypair too.** Rejected: the fed daemon is
the production entry point for the signing side; the chat is a viewer.
Loading a keypair inside the chat process would double the key-material
lifecycle surface with no clear benefit (an operator wanting to sign
an attestation from the chat can invoke the fed daemon's scripted-
command drain instead). See "Negative" above.

**Separate `SR_S_SERVING` slot vs. rebuilding a new `sr_state`.**
Adding a slot at index 7 (after the six R23C slots) is additive: all
existing callers keep their slot layout; no breaking change to sr's
public API surface. Rebuilding from scratch would have required
touching every `sr_*` accessor + every downstream test.

## Implementation Notes

**API surprises found during implementation** (all resolved additively,
per Phase L convention "grep before assuming API shape"):

1. `att_store_new()` takes NO args. The plan sketch suggested
   `att_store_new(soul_id, signer_privkey, signer_pubkey)`; the actual
   R20F code splits identity per-tuple (soul_id is passed to
   `att_make(soul_id, ts_ns, root_bytes, seed_bytes, pk_bytes)`). The
   daemon's alloc block calls the constructor with zero args and
   registers the signer pubkey via `gossip_register_att_pubkey`.
2. `att_verify(att, pk_bytes)` takes TWO args, not three. Public-key
   lookup happens via `gossip_lookup_att_pubkey(state, peer_id)`, not
   as an argument.
3. `sr_set_serving(sr, on)` **did not exist** in the R23C code. R3
   introduces it as a new `SR_S_SERVING = 7` slot, guarded in
   `sr_serve_snap_request`. Existing tests + the R23C integration
   scenario updated to add `sr_set_serving(sr, 1)` where they
   previously assumed serve-on-hit.
4. `att_store_recent(store, max_n)` also new: enumerates the tail N
   entries across all peers, newest-last as walked. `/attest_log`
   consumes it; the older `att_recent_lines_for_peer` remains for the
   per-peer detail path.
5. `merkle_signing_keypair_load(base_path)` DOES exist under that
   name (`src/persistence/merkle_signing.nova:412`) and returns
   `[seed_bytes, pk_bytes] | 0` (0 on missing / short-length file).
   The daemon treats `0` as "attestation disabled" and warn-logs.

**NOVA quirks honored** (mirrors Phase K/L notes):

- `str_eq_bytes` used for all short-literal compares (`"0"`, `"on"`,
  `"off"`, `"status"`).
- `rt_str_to_int` used for env-int parsing; guarded by the `<= 0
  -> fallback` idiom in the resolvers.
- No `setenv`: env resolvers are pure functions taking the raw env
  value; the daemon has a one-line getenv wrapper.
- Module-level singletons (`_chat_fed_att`, `_chat_fed_sr`) lazy-init
  in `_admin_gossip_start`.
- `sys_open` on `/tmp` aborts under the container, so the daemon's
  local snap dir never falls back to `/tmp`; the last-resort default
  is `./crossengin_snap` (relative to the daemon's cwd).
- Numeric constants (`SR_S_SERVING = 7`, `16777215` mask,
  `1700000000000000000` test-vector ts) stay well under Bug-#11's
  large-literal codegen ceiling; `make lint-ints` clean on the
  modified files.

**Test coverage**:

- `tests/unit/test_fed_daemon_attest.nova` -- ~40 checks. Env
  resolvers (default, `"0"` disables, key-dir precedence), att
  bootstrap, verify with matching / wrong / null key, store
  accumulation, gossip wiring round-trip, `att_store_recent`
  clamping, chat REPL formatters, arg parser.
- `tests/unit/test_fed_daemon_replication.nova` -- ~40 checks. Env
  resolvers (default-on for enable, default-OFF for serve, CE_SNAP_PATH
  precedence), sr bootstrap, serving toggle, gossip wiring round-trip,
  serve gating, `/snap_fetch` root-hex validator, result-line
  formatters for the four dispatch branches, env-disabled path.

Neither test spins up a live gossip listener; the live-wire round trip
is covered by the existing R20F / R23C integration scenarios
(`tests/integration/scenario_dddd_snapshot_attestation.sh`,
`tests/integration/scenario_mmmm_snap_replication.sh`).
