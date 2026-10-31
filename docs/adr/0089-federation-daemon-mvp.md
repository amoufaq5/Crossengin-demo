# ADR-0089: MVP federation daemon (gossip + kg_sync + distributed_query)

- Status: Accepted
- Date: 2026-09-28

## Context

`src/federation/` accumulated 23 unit-tested NOVA modules over the R18E through
R28E rounds -- a full mesh substrate: SWIM-style gossip (R18E), kg_sync deltas
v3 (R6C/R7C), distributed SPARQL query fan-out (R20E), mini-Datalog
distributed rules (R21B), Bully leader-election (R19E), signed snapshot
attestation + replication (R20F/R23C), DTLS 1.2 with R29B2 stubs, ICE/STUN/TURN
(RFC 5245/8489), WebRTC signaling with a documented data-plane stub, NAT
traversal (STUN external-addr discovery + gossip-piggyback advertisement),
gossip relays with a Noise-XK secure variant, and a Raft state machine. Every
one has a unit-test file under `tests/unit/` and, for the network paths, a
matching `tests/integration/scenario_*.sh` shell driver.

**None of it was wired into a runnable daemon.** The chat REPL grew a stub
handler for each federation feature (`/gossip`, `/gossip_add_peer`,
`/gossip_noise`, `/leader`, `/attest_log`, `/nat`, `/snap_replicas`, `/relay`,
`/relay_secure`, `/webrtc`, `/drule_add`, `/drule_run`) that printed a link to
the integration scenario and returned; the message operators saw was
consistently `"this REPL has no gossip daemon"`. The federation modules ran
only inside the integration scenarios' standalone driver binaries under
`tests/integration/_scenario_www_drivers/`.

Two things were missing:

1. **A unified federation-daemon entry point.** The scenarios each build their
   own tiny driver; there is no `nova run examples/crossengin_fed_daemon.nova`
   equivalent to `nova run examples/crossengin_daemon.nova`. An operator
   spinning up a mesh peer has no runnable binary; they can only compose the
   primitives themselves from scratch.
2. **Chat-REPL live wiring.** Even in a session where the operator wants to
   inspect a running peer's peer table or shoot a SPARQL query across the mesh,
   the REPL cannot reach a live gossip state because it never allocated one.

Phase M ships this in three rounds; R1 (this ADR) delivers the MVP.

## Decision

**A new binary at `examples/crossengin_fed_daemon.nova`** that composes the R1
subset of federation primitives -- gossip + kg_sync + distributed_query -- into
one event-driven daemon. Mirrors the shape of `examples/crossengin_daemon.nova`
(env-config -> component alloc -> Session registration -> tick loop) so a
reader who understands the cognition daemon can navigate the mesh daemon by
homology.

**R1 scope is deliberately narrow:**

- **Gossip** provides peer discovery + membership + delta gossip over plain
  TCP. The DTLS 1.2 transport at `src/federation/dtls12.nova` carries R29B2
  stubs (cert-verify at `:137`, SRTP EKM at `:140`) that block wire-encryption
  today; when those unstub, gossip's transport swap is a two-line change and
  R1's daemon inherits it without further work.
- **kg_sync** is instantiated (`kgd_state_new`) and held on the Session for
  R2/R3 to consume; gossip's own `DELTA` branch works off the raw KG for the
  R1 exchange.
- **distributed_query** is wired against the gossip state so the R1 chat REPL
  can fan out a SPARQL query across the mesh.

**Chat REPL live wiring** replaces the stubs at `examples/crossengin_chat.nova:5461-5462`
with four real handlers:

| Slash command | Behavior |
| --- | --- |
| `/gossip_start [addr]`      | Lazy-init a module-level gossip state; bind TCP listener on `addr` (default `127.0.0.1:8790`); print bound fd. Repeated calls print "already running". |
| `/gossip_peer add <addr>`   | `gossip_add_peer` and report new peer count. |
| `/gossip_peers`             | Iterate the peer table; one line per row (`<addr> <status> last_seen=<ns>`). |
| `/gossip_dq <query-text>`   | `dq_query` across the mesh; render each returned binding via `dq_format_binding`. |

The R2/R3 stubs (`/leader`, `/attest_log`, `/nat`, `/drule_add`, ...) stay in
place until their respective rounds land; only the R1 four are lifted.

**Env-var contract** (all optional):

| Var | Default | Meaning |
| --- | --- | --- |
| `CE_FED_LISTEN_ADDR` | `"127.0.0.1:8790"` | Address the daemon binds its TCP listener to (`HOST:PORT`). |
| `CE_FED_PEERS`       | `""` -- falls back to `CE_GOSSIP_PEERS` | Comma-separated bootstrap peer list. |
| `CE_FED_SOUL_ID`     | `"soul:<listen_addr>"` | Stable node identity; used in banners and reserved for R2 leader-election IDs. |
| `CE_FED_TICK_MS`     | `250` (clamped to `[50, 10000]`) | Milliseconds between gossip_step / accept / input-poll ticks. |
| `CE_FED_MAXSTEP`     | `0` (unbounded) | Test-only step cap so integration scripts can bound the loop. |

Env-var parsing follows the canonical guard used across the tree: a `getenv`
that returns 0 or an empty string falls back to the documented default;
integer env vars additionally guard `rt_str_to_int == 0` (its garbage return)
and negative values.

**Component-alloc order** (fixed; the tests cover it):

1. `kg_registry_new()` -- registry for this node's shared KGs.
2. `mo_new()` -- meta-observer; R1 does not attribute mesh-received atoms
   but the seam is present so R2's rule engine can wire it without changing
   the boot.
3. `reasoning_kg_init(kgreg)` -- one reasoning-shaped KG registered as
   `"reasoning"` so kg_sync's `DELTA` branch can find it.
4. `gossip_init(listen_addr, peer_list)` -- gossip state.
5. `gossip_listen(listen_addr)` -- bind TCP listener; returns fd, or -1 on
   bind failure (daemon logs a WARN and continues in client-only mode).
6. `kgd_state_new()` -- kg-sync delta state.
7. `dq_init(gs)` -- distributed-query state.

**Session tie-in.** The daemon allocates a `Session` handle
(`session_make(soul_id, ..., kgreg, fed_kg, 0, ..., mo, 0)`) and registers it
under a fresh `SessionRegistry`. Cognitive slots (soul, lang, ikg, refl_kg,
ctx, log, engine, hs) stay 0 -- this binary carries the mesh half of the
Session shape. Even in R1 that seam is useful: R3 wires snapshot attestation
into the Session (`att_store_new(sess, ...)`) and the chat's `/save` path
already speaks the Session contract, so the wire-up is a diff, not a
rearchitecture.

**Tick loop.** Each tick advances `gossip_step` (which runs the R18E SWIM
PING/DELTA clock against `fed_kg`), drains any pending accept via
`gossip_try_accept` and hands the conn to `gossip_handle_conn_kg`, then polls
`/tmp/crossengin_fed_input` for a scripted command:

- `EXIT` -- clean shutdown.
- `PEER <addr>` -- register a bootstrap peer at runtime.
- `PING` -- force an extra `gossip_step` regardless of the clock.
- anything else -- logged and ignored.

The polling shape mirrors `examples/crossengin_daemon.nova:470-480` so scripted
integration tests (Phase M R1 does not add any today) can drive the mesh peer
the same way they drive the cognition daemon.

## Consequences

- **Federation primitives are now composable from one process.** Anyone
  wanting a mesh peer runs `nova run examples/crossengin_fed_daemon.nova`
  (or `make install && ./bin/crossengin-fed-daemon`) and gets a bound
  listener plus a peer table plus a distributed-query surface. The
  scenarios' driver binaries under `tests/integration/_scenario_www_drivers/`
  remain the source of truth for the wire protocol tests; the daemon is
  the composed happy path.
- **The chat REPL grows a live mesh view.** An operator running the chat
  can now `/gossip_start`, `/gossip_peer add <addr>`, `/gossip_peers`, and
  `/gossip_dq <query>` without leaving the REPL. This closes the four
  most-asked-about stub commands out of the twelve federation stubs; the
  other eight land in R2 / R3.
- **The `crossengin_daemon` cognition binary is untouched.** The two
  daemons serve two different concerns and have two different tick loops.
  A production deployment typically runs both, side by side; they
  communicate via the on-disk snapshot directory the chat's `/save`
  already writes to. R3 wires the snapshot side into gossip attestation
  broadcast; until then the two daemons are strictly independent.
- **Plain TCP now, DTLS 1.2 later.** R1 does not attempt to encrypt the
  wire because the DTLS 1.2 module has two R29B2 stubs
  (`dtls12.nova:137, 140`) that block a real handshake. Gossip's Noise-XK
  overlay (`CE_GOSSIP_REQUIRE_NOISE`) is available as a stopgap for
  operators who need integrity + confidentiality on an untrusted
  network; enabling it is out of scope for the R1 boot script but is
  a two-env-var flip (`CE_GOSSIP_NOISE_STATIC_PRIV=<hex>` +
  `CE_GOSSIP_REQUIRE_NOISE=1`) that the existing gossip_noise scenario
  documents.
- **R2 and R3 build on this Session shape without reshaping the boot.**
  R2 adds `le_init(gs, soul_id)` and `dr_init(gs, kgreg)` after `dq_init`;
  the tick body runs `le_step` and `dr_step` alongside `gossip_step`, and
  the four R1 slash commands grow siblings (`/leader status`, `/leader
  elect`, `/drule_add`, `/drule_run`, `/drule_fixpoint`). R3 wires
  `att_store_new` + `sr_init` onto the Session and adds the attestation
  broadcast + snapshot-fetch commands (`/attest_log`, `/attest_verify`,
  `/snap_fetch`, `/snap_serve on|off`). Neither round revisits the R1
  env-var contract; they extend it (`CE_FED_LEADER_ELECTION_ENABLED`,
  `CE_FED_ATTEST_KEY_DIR`, etc.).
- **Env-var namespace stays clean.** `CE_FED_*` is the mesh daemon's
  private prefix (`CE_FED_LISTEN_ADDR`, `CE_FED_PEERS`, ...). The legacy
  `CE_GOSSIP_*` remains a live fallback for `CE_FED_PEERS` so operators
  who already have a gossip bootstrap block do not have to touch it.
  `CE_SESSION_ID`, `CE_SNAP_PATH`, `CE_DLOG_PATH` (the cognition
  daemon's env vars) are not consulted by the fed daemon -- their
  namespace stays cognition-only until R3 needs the snap directory.
- **Bounded loop is opt-in.** `CE_FED_MAXSTEP` is unset by default so
  the fed daemon runs until `EXIT` or EOF. Setting it to a positive
  integer is a test-only affordance; the shape mirrors `CE_MAXSTEP` on
  the cognition daemon.
- **`make cross-windows` grows a new target.** The fed daemon builds
  under mingw-w64 the same way the cognition daemon does. Its Windows
  binary name is `crossengin-fed-daemon.exe`, keeping the naming
  convention consistent with the other examples.

## Alternatives Considered

- **Fold the mesh into `crossengin_daemon`.** Rejected: cognition and
  mesh have different lifecycles and different failure modes. A peer that
  cannot bind its listen port should not stop the cognition loop from
  running; a soul that is mid-reasoning should not stall waiting for a
  gossip DELTA reply. Two binaries let each shape its own tick loop and
  env-var namespace. A production deployment can still run both
  side-by-side; the seam is the on-disk snapshot directory that R3
  couples via attestation broadcast.
- **Ship without kg_sync in R1.** Rejected: `kgd_state_new` is one line
  and holding it on the Session establishes the seam R2 (rule engine
  broadcasting derivations over gossip) needs. Deferring the alloc
  would force R2 to grow both the primitive AND its wiring.
- **Wire DTLS 1.2 now.** Rejected: `dtls12.nova:137` (cert verification)
  and `:140` (SRTP EKM) both carry `_R29B2_STUB` markers -- neither is
  functional. Wiring gossip through a stub layer would produce a daemon
  whose wire tests pass in isolation but fall over on the first real
  handshake. Plain TCP with the Noise-XK opt-in is the honest surface
  today.
- **Wire leader_election + distributed_rules in R1.** Rejected: those
  compose against gossip the same way distributed_query does, so
  wiring them is a mechanical follow-up, but the four R1 slash commands
  (`/gossip_start`, `/gossip_peer add`, `/gossip_peers`, `/gossip_dq`)
  already give operators enough surface to inspect a live mesh and
  fan out a query. R2 (ADR-0090) adds coordination and inference on
  top of a working peer table, which is easier to reason about than a
  ten-command boot.
- **Skip the Session seam.** Rejected: the Session shape is what the
  chat's `/save` speaks and what R3's attestation store attaches to.
  Skipping it in R1 would force R3 to retrofit; adding the seam now
  (with cognitive slots at 0) costs nothing and lets R3 focus on the
  attestation broadcast itself.
- **Skip the `/tmp/crossengin_fed_input` polling.** Rejected: the
  cognition daemon uses `/tmp/crossengin_input` for scripted-episode
  drivers; keeping the shape symmetric across the two daemons is
  cheap and consistent, and R3's snapshot-replication scenario will
  need an EXIT command anyway.
- **Reuse `CE_GOSSIP_SELF` as the R1 listen addr.** Rejected: the two
  daemons have different default ports (`crossengin_daemon` has no
  gossip listener today; the gossip module's built-in default is
  `127.0.0.1:8770`, occupied by the pre-existing kg-sync port
  neighborhood). `CE_FED_LISTEN_ADDR` with default `:8790` gives the
  fed daemon a clean port that does not clash with a locally-running
  kg-publisher / kg-subscriber pair.

## Implementation Notes

- `examples/crossengin_fed_daemon.nova` (~360 lines): env-config
  helpers (`_fed_env_str`, `_fed_env_int`, `_fed_peers_from_env`,
  `_fed_soul_id_from_env`, `_fed_tick_ms_from_env`), the boot banner,
  component alloc, Session registration, the input-drain + tick loop,
  and the shutdown summary. Imports are limited to what R1 actually
  uses: `src/kg/*`, `src/parts/reasoning/reasoning_atoms.nova`,
  `src/parts/meta/meta_observer.nova`, `src/federation/gossip.nova`,
  `src/federation/kg_sync.nova`, `src/federation/distributed_query.nova`,
  `src/session/session.nova`. R2 will import
  `src/federation/leader_election.nova` +
  `src/federation/distributed_rules.nova`; R3 will import
  `src/federation/snapshot_attestation.nova` +
  `src/federation/snapshot_replication.nova`.
- `src/chat/fed_slash.nova` (~180 lines): pure helper surface for the
  four chat slash commands -- argument parsers (`chat_fed_parse_peer_command`,
  `chat_fed_pick_listen_addr`, `chat_fed_pick_query_text`), output
  formatters (`chat_fed_gossip_started_line`, `chat_fed_peer_added_line`,
  `chat_fed_peers_render`, `chat_fed_dq_result_header`, ...) and status
  label helpers (`chat_fed_status_label` mapping GOSSIP_STATUS_* enum
  to symbolic name). Kept pure so the tests can validate the exact
  wire shape without spinning up a gossip listener.
- `examples/crossengin_chat.nova`:
  - imports `src/federation/gossip.nova`,
    `src/federation/distributed_query.nova`, and `src/chat/fed_slash.nova`;
  - grows module-level lazy-init state `_chat_fed_gs`, `_chat_fed_dq`,
    `_chat_fed_listen_addr` alongside the existing `_fed_agg`;
  - grows four real slash-command dispatches (`/gossip_start`,
    `/gossip_peer`, `/gossip_peers`, `/gossip_dq`), which replace the two
    stub println's at the old `:5461-5462` (the `/gossip` and
    `/gossip_add_peer` stubs go away; `/gossip_noise` and the R2/R3
    stubs stay for their respective rounds);
  - grows a `/help` section describing the four new commands.
- `tests/unit/test_fed_daemon_boot.nova` (~30 checks): the pure
  env-parser surface (`_t_env_str_resolve`, `_t_env_int_resolve`,
  `_t_peers_resolve`, `_t_soul_id_resolve`, `_t_tick_ms_resolve`) and
  the daemon's component-alloc contract (`gossip_init` shape,
  `kgd_state_new` non-null, `dq_init` wires gossip). Uses the
  `test_session_paths.nova` idiom: NOVA has no `setenv`, so the pure
  resolvers take the raw env value as an argument.
- `tests/unit/test_chat_fed_slash_commands.nova` (~30 checks):
  argument parsers for all four slash commands, output-line formatters,
  peer-table renderer, status-label mapping, and an end-to-end check
  that runs `dq_query` on a two-fact fixture and asserts the
  `chat_fed_dq_result_header` line formats the row count correctly.
- `Makefile`: `FED_DAEMON := examples/crossengin_fed_daemon.nova`,
  added to `CROSS_WIN_PAIRS` as `crossengin-fed-daemon`, and to the
  `install` target so `bin/crossengin-fed-daemon` builds alongside
  the cognition daemon. The `check-nova` toolchain guard already
  covers it via `SRC_MODULES` -- no separate target needed.
- `docs/CHAT_USAGE.md`: the four R1 slash commands are documented
  under a new "Federation" subsection of the admin commands table.
- `ENHANCEMENTS_ROADMAP.md`: Phase M R1 SHIPPED note under a new
  "Phase M -- Federation Daemon" heading, with R2 / R3 sketched as
  the two remaining rounds.
- `make lint-ints` clean: no new large-literal arithmetic in the fed
  daemon or the chat helpers. All integer ops in the daemon are
  small (tick counter, step counter, peer count) and all comparisons
  are against single-digit or hundreds-scale constants
  (CE_FED_MIN_TICK_MS=50, CE_FED_MAX_TICK_MS=10000, CE_FED_DEFAULT_TICK_MS=250).

## R2 / R3 preview

- **R2 -- coordination + inference (ADR-0090).** `le_init(gs, soul_id)` +
  `dr_init(gs, kgreg)` allocated after `dq_init`; `le_step` +
  `dr_run_round` scheduled in the tick body; chat REPL grows
  `/leader status`, `/leader elect`, `/drule_add <rule>`, `/drule_run`,
  `/drule_fixpoint`. Env-var contract adds
  `CE_FED_LEADER_ELECTION_ENABLED` (default 1) and
  `CE_FED_DRULE_MAX_ROUNDS` (default 32).
- **R3 -- durability (ADR-0091).** `att_store_new` + `sr_init` wired onto
  the Session; the chat's `/save` broadcasts an ATTESTATION over
  gossip; chat REPL grows `/attest_log`, `/attest_verify <soul>`,
  `/snap_fetch <root>`, `/snap_serve on|off`. Env-var contract adds
  `CE_FED_ATTEST_KEY_DIR` (default `~/.crossengin/fed_keys/`).
  Closes the federation-daemon arc for what can be built without
  unstubbing DTLS 1.2.
