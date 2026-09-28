# ADR-0090: Federation coordination + inference (leader election + distributed rules)

- Status: Accepted
- Date: 2026-09-28

## Context

Phase M R1 (ADR-0089) landed `examples/crossengin_fed_daemon.nova`, a single
event-driven binary that composes gossip (R18E), kg_sync deltas (R6C/R7C v3),
and distributed SPARQL query fan-out (R20E) into a runnable mesh peer. The
chat REPL grew four live handlers (`/gossip_start`, `/gossip_peer add`,
`/gossip_peers`, `/gossip_dq`) that operate on a module-level singleton gossip
state so operators can inspect a live mesh without spawning a second process.

Two federation primitives were unit-tested but not wired into the R1 daemon:

- **`src/federation/leader_election.nova`** (R19E) -- Bully leader-election
  over the gossip peer table. Ships `le_init`, `le_start_election`,
  `le_step`, `le_current_leader`, `le_status_line`, plus the peer-id map
  (`le_register_peer`, `le_unregister_peer`), the inbound message handlers
  (`le_on_election`, `le_on_ok`, `le_on_victory`), and stat accessors.
- **`src/federation/distributed_rules.nova`** (R21B) -- mini-Datalog rules
  broadcast + evaluated across the mesh. Ships `dr_init`, `dr_add_rule`,
  `dr_run_round`, `dr_run_to_fixpoint`, plus the R28A/R30A/R31A async +
  pipelined-fetch machinery layered on top.

The corresponding chat REPL stubs (`/leader`, `/drule_add`, `/drule_run`)
still printed the pre-Phase-M "REPL has no gossip daemon (see
tests/integration/scenario_*.sh)" line. `/drule_fixpoint` had no dispatch
at all.

This ADR is R2. It wires those two primitives into the R1 fed daemon and
lifts the three (four counting `/drule_fixpoint`) chat REPL stubs. R3
(ADR-0091) then adds snapshot attestation + replication on top of the R2
Session shape.

## Decision

**Extend the R1 fed daemon** (`examples/crossengin_fed_daemon.nova`) to
allocate leader-election + distributed-rules state at boot and to advance
`le_step` on each tick of the main loop. The R1 alloc block already ended at
`dq_init(gs)`; R2 appends two more allocations under two new
opt-out env flags:

| Env var | Default | Effect on 0 |
| --- | --- | --- |
| `CE_FED_LEADER_ELECTION_ENABLED` | `1` | `le_init` skipped; `/leader` handler prints "no state"; tick loop skips `le_step`. |
| `CE_FED_DR_ENABLED`              | `1` | `dr_init` skipped; `/drule_*` handlers print "no state"; gossip inbound RULE / DERIVATION lines are ignored (matches the pre-R2 default). |

Only the literal string `"0"` disables; any other value (including empty)
falls back to the default-on path. This matches the R1 env-var idiom
(explicit override wins; unset uses documented default) and keeps the
enable-flag namespace uncluttered.

**Boot alloc order** (extends ADR-0089 sec "Component alloc"):

1. `kg_registry_new()`
2. `mo_new()`
3. `reasoning_kg_init(kgreg)`
4. `gossip_init(listen_addr, peer_list)`
5. `gossip_listen(listen_addr)`
6. `kgd_state_new()`
7. `dq_init(gs)`
8. **NEW (R2):** if `CE_FED_LEADER_ELECTION_ENABLED` != "0": `le = le_init(gs, _fed_soul_id_to_int(soul_id))`
9. **NEW (R2):** if `CE_FED_DR_ENABLED` != "0": `dr_engine = rule_engine_new(); dr = dr_init(gs, dr_engine)`

`le_init` takes an INT `self_id` (per R19E's Bully-algorithm contract: the
highest-ID alive peer wins). The daemon derives it from the `soul_id`
string via a small djb2-style mixer masked to 24 bits (`_fed_soul_id_to_int`).
The mask keeps the integer well under Bug-#11's large-literal codegen ceiling
so downstream `int_to_str` / comparisons never risk drift. The chat REPL
mirrors the SAME mixer (`_chat_soul_id_to_int`) so a mixed-mode operator
running the chat and the daemon against the same `soul_id` gets consistent
peer IDs.

`dr_init` takes a fresh `rule_engine_new()`. `dr_init` internally calls
`gossip_set_dr_state(gs, dr)`, so inbound RULE / DERIVATION lines route to
the freshly-allocated dr without any manual callback wiring.

**Tick loop extension**. `le_step` is a cheap check (two list walks over
the alive-peer set + timeout comparison; no I/O), so it runs on every tick
alongside `gossip_step`. Distributed rules do NOT tick continuously -- rule
evaluation is expensive (federated fact-fetch over gossip) and drift-free
between rounds, so we run `dr_run_round` / `dr_run_to_fixpoint` on explicit
operator invocation (chat REPL, or an integration script that writes
`RULE_RUN` / `RULE_FIXPOINT` to `/tmp/crossengin_fed_input`; the input-seam
extension for R2 is one branch each in the daemon's command drain). The
non-continuous shape matches how R21B's tests exercise it (unit tests call
`dr_run_round` directly; no scheduled tick).

**Chat REPL wiring** (`examples/crossengin_chat.nova`) replaces the three
stubs at the R1 baseline (`/leader`, `/drule_add`, `/drule_run`) with real
handlers and adds a fourth (`/drule_fixpoint`). All four require
`/gossip_start` first -- the module-level lazy-init state
`_chat_fed_le` / `_chat_fed_dr` / `_chat_fed_dr_engine` is allocated
alongside the R1 `_chat_fed_gs` / `_chat_fed_dq` singletons inside
`_admin_gossip_start`, so one gossip_start boots the R1+R2 mesh surface.

| Slash command | Behavior |
| --- | --- |
| `/leader`, `/leader status` | Print `le_status_line(_chat_fed_le)` -- current leader id, self_id, phase, peer count, election / victory / deposed counters. |
| `/leader elect`             | Call `le_start_election(_chat_fed_le)`; print the "election started" line via `chat_fed_le_elect_result_line`. |
| `/drule_add <rule>`         | Parse; call `dr_add_rule(_chat_fed_dr, rule)`; report ok / refusal (the R20B parser's error tuple's reason is folded into the line). |
| `/drule_run`                | Call `dr_run_round(_chat_fed_dr, kg)`; print the round's derived count. |
| `/drule_fixpoint`           | Call `dr_run_to_fixpoint(_chat_fed_dr, kg, 0)`; print `[total, rounds]`. `max_rounds=0` falls back to `DR_DEFAULT_MAX_ROUNDS=50`. |

Argument parsing + line formatting stay in `src/chat/fed_slash.nova`
(five new helpers: `chat_fed_le_parse_arg`, `chat_fed_le_status_line`,
`chat_fed_le_elect_result_line`, `chat_fed_drule_add_parse`,
`chat_fed_drule_add_result_line`, plus `_no_state_line` / `_usage_line`
mirrors of the R1 shapes) so the unit tests can validate the wire shape
without spinning up a live gossip listener.

## Consequences

- **Coordination + inference are now composable from one process.** An
  operator running `nova run examples/crossengin_fed_daemon.nova` gets a
  running Bully leader-election loop and a distributed-rules engine wired
  against the gossip peer table -- no separate driver binary. The R1
  daemon's `--tick-ms=250` pacing runs `le_step` at the same rate,
  which is well inside R19E's `LE_DEFAULT_TIMEOUT_MS=2000` election
  window so a single-node bring-up self-elects within one timeout after
  the first tick and a two-node scenario converges within two.
- **The chat REPL grows a live coordination + inference view.** The four
  new commands (`/leader`, `/leader elect`, `/drule_add`, `/drule_run`,
  `/drule_fixpoint`) close five of the pre-Phase-M stubs (`/leader`,
  `/drule_add`, `/drule_run`, plus the previously undispatched
  `/drule_fixpoint` and the `elect` sub-command). Combined with R1, the
  chat REPL now covers 9 of the 12 federation stubs; the remaining 3
  (`/attest_log`, `/snap_replicas`, `/snap_fetch`) land in R3.
- **Bully corner cases are handled inside R19E, not in the wiring.**
  Split-brain during a network partition is what Bully was designed to
  live with: each partition self-elects the highest-ID within its
  alive-peer view, and on re-merge R19E's `le_step` stability check
  yields to the globally-highest ID. The "deferred outbound message"
  queue (`le_drain_pending`) is R19E's transport-agnostic seam --
  today the daemon's `le_step` runs alongside gossip's own tick, and
  the queue drains through R19E's `_le_highest_non_dead_or_self`
  shortcut when the gossip alive view already exposes the higher-ID
  peer (the CrossEngin default path). A future round wiring dedicated
  ELECTION / OK / VICTORY frames onto the gossip channel would drain
  the queue verbatim; R2's shortcut path produces the SAME end state
  Bully would converge on with full message delivery.
- **`dr_run_to_fixpoint` boundedness is honored.** R2 chat REPL passes
  `max_rounds=0` so R21B's `DR_DEFAULT_MAX_ROUNDS=50` cap applies.
  R21B's `dr_run_round` also deduplicates DERIVATION broadcasts (an
  atom that already exists in the KG is not re-added, and the cache
  path in `_dr_drain_inbound_derivs` records a hit without a
  re-broadcast). Combined, the fixpoint's termination is guaranteed
  even against a pathological rule set that would otherwise loop.
- **Env-var namespace stays clean.** `CE_FED_LEADER_ELECTION_ENABLED`
  and `CE_FED_DR_ENABLED` share the `CE_FED_*` prefix R1 established.
  Both default to on, so operators who set nothing get the full
  Phase-M-R2 surface; opt-out is one env var per feature. The plan
  file's mention of `CE_FED_DRULE_MAX_ROUNDS` is intentionally NOT
  implemented in R2 -- R21B's own `DR_DEFAULT_MAX_ROUNDS=50` is the
  right default, and a future round adding it would revisit the
  boundedness contract; today the chat REPL prints the cap in the
  `/drule_fixpoint` line so operators know what termination window
  they're inside.
- **No new tick-loop primitive per federation feature.** `le_step` is
  the ONLY new call in the tick body. `dr` is driven by the input
  seam / chat REPL, matching how R21B's own tests exercise it. This
  keeps the daemon's tick cheap (still a couple of list walks + one
  optional socket accept) and preserves the R1 CE_FED_TICK_MS=250
  default without regression.
- **R3 builds on this Session shape without reshaping the boot.** R3
  will allocate `att_store_new` + `sr_init` on the Session
  (which R1 already registers) after `dr_init`. Neither R2 slot on
  the Session changes shape, so R3 is an append.

## Alternatives Considered

- **Wire distributed_rules as a per-tick step.** Rejected: `dr_run_round`
  fans out DRFETCH RPCs to every alive peer; even at 250ms tick pacing
  and N=8 peers, that is 32 RPCs / second for zero operator benefit --
  rule derivations are drift-free between explicit invocations. The
  R21B tests all exercise the primitive via explicit `dr_run_round`
  calls, matching what the chat REPL now does. If R3 or a later round
  finds a use case for a continuous derivation loop, adding a
  `dr_step(dr, kg)` scheduled call is a one-line diff.
- **Use Raft instead of Bully for leader election.** Rejected: Raft
  replicates a LOG; leader-election is a small ordinance under Raft.
  For the CrossEngin case ("pick ONE coordinator from the alive-peer
  set") Bully is the cheaper primitive -- state is a single integer
  + an election flag, convergence on a stable mesh is one round,
  worst-case message count is O(N^2) which is fine at N <= 20. Raft
  (`raft_*.nova` in the tree) will be wired later for the shared
  snapshot-append case; R2 keeps the surfaces distinct.
- **Ship a new inference primitive.** Rejected: `distributed_rules`
  already exists, is unit-tested, has the R28A async fetch + R30A
  pipeline + R31A parallel-connect refinements from later rounds,
  and interoperates with the R20B `rule_inference` engine unmodified.
  Any new primitive would either duplicate that work or diverge from
  it in ways integration scripts already exercise.
- **Move the R2 chat state to a new module.** Rejected: the R1 chat
  federation state (`_chat_fed_gs`, `_chat_fed_dq`, `_chat_fed_listen_addr`)
  is already a module-level singleton block in
  `examples/crossengin_chat.nova`. Adding `_chat_fed_le`, `_chat_fed_dr`,
  `_chat_fed_dr_engine` next to them is one paragraph and keeps the
  R1 + R2 lifecycle in one place. `src/chat/fed_slash.nova` grows the
  formatters; the chat file grows the module-state + dispatch, same
  shape as R1.
- **Drop `_fed_soul_id_to_int` and require operators to set `CE_FED_SOUL_ID`
  as an integer.** Rejected: soul IDs are strings across the rest of
  the tree (`soul:127.0.0.1:8790` per R1's default). Forcing an integer
  form for R2 would break the R1 env-var contract and confuse operators
  who expect the same `soul_id` in every log line. The mixer is 8 lines
  and produces a stable value across runs; masking to 24 bits keeps it
  well inside Bug-#11's ceiling and makes the `int_to_str` on the
  shutdown-summary line readable.

## Implementation Notes

- **`examples/crossengin_fed_daemon.nova`** (R1: 360 lines -> R2:
  ~440 lines): adds `_fed_bool_from_env_value`,
  `_fed_le_enabled_from_env`, `_fed_dr_enabled_from_env`,
  `_fed_soul_id_to_int` (djb2 masked to 24 bits); imports
  `src/federation/leader_election.nova`,
  `src/federation/distributed_rules.nova`, `src/kg/rule_inference.nova`;
  extends the alloc block with `le = le_init(gs, self_id_int)` and
  `dr = dr_init(gs, rule_engine_new())` under the two enable flags;
  the tick body adds `if le != 0 { le_step(le) }`; the shutdown
  summary appends `le_self_id`, `le_leader`, `le_elections`,
  `le_victories`, `le_deposed` when le is allocated (and `le_disabled=1`
  when it isn't), and `dr_rules`, `dr_derived`, `dr_rounds`,
  `dr_rules_tx`, `dr_derivs_tx` symmetrically for dr.
- **`src/chat/fed_slash.nova`** (R1: 188 lines -> R2: ~290 lines):
  imports `../federation/leader_election.nova` +
  `../federation/distributed_rules.nova`; adds LE helpers
  (`chat_fed_le_no_state_line`, `chat_fed_le_parse_arg`,
  `chat_fed_le_usage_line`, `chat_fed_le_status_line`,
  `chat_fed_le_elect_result_line`) and DR helpers
  (`chat_fed_drule_no_state_line`, `chat_fed_drule_add_usage_line`,
  `chat_fed_drule_add_parse`, `chat_fed_drule_add_result_line`,
  `chat_fed_drule_run_line`, `chat_fed_drule_fixpoint_line`).
  Same "pure helper surface + caller wires the state" pattern as R1.
- **`examples/crossengin_chat.nova`**: imports `leader_election.nova`
  + `distributed_rules.nova`; grows module-level `_chat_fed_le`,
  `_chat_fed_dr`, `_chat_fed_dr_engine` alongside R1's `_chat_fed_gs`,
  `_chat_fed_dq`, `_chat_fed_listen_addr`; extends `_admin_gossip_start`
  to allocate the three R2 singletons alongside `dq_init`; adds
  `_admin_leader(arg)`, `_admin_drule_add(arg)`, `_admin_drule_run(kg)`,
  `_admin_drule_fixpoint(kg)`; replaces the R21B `/drule_add`,
  `/drule_run` stubs and the R19E `/leader` stub with real dispatches;
  adds `/drule_fixpoint` dispatch (was not present in R1); updates
  the `/help` block with the five new commands (`/leader`, `/leader elect`
  are one line; `/drule_add`, `/drule_run`, `/drule_fixpoint` are
  three lines).
- **`tests/unit/test_fed_daemon_leader.nova`** (~30 checks): bootstrap
  state (le_init sets leader=-1, phase=STABLE, self_id from mixer);
  peer registration round-trip; `le_start_election` transitions to
  ELECTING; ELECTION / OK / VICTORY message handler flows;
  higher-ID VICTORY updates local leader; env-disabled resolver
  returns 0 (no allocation). Uses the pure-resolver twin idiom from
  `test_session_paths.nova` -- NOVA has no `setenv`, so
  `_t_le_enabled_resolve` takes the raw env string as an argument.
- **`tests/unit/test_fed_daemon_rules.nova`** (~30 checks):
  bootstrap (dr_init records gossip + engine, gossip_dr_state wired,
  counters at zero); `dr_add_rule` accepts a valid rule and bumps
  rule_count + stats_rules_tx; `dr_add_rule` refuses a malformed rule
  (returns error tuple); `dr_run_round` derives from a two-fact
  parent-chain fixture; `dr_run_to_fixpoint` terminates within
  DR_DEFAULT_MAX_ROUNDS and returns [total, rounds]; env-disabled
  resolver skips allocation.
- **`docs/CHAT_USAGE.md`**: the "Federation / DP" section grows a
  "R2 -- coordination + inference (ADR-0090)" subsection describing
  the five new commands; the R1 subsection's forward-reference note
  ("R2 will wire /leader ...") is updated to say "R2 is now live".
- **`ENHANCEMENTS_ROADMAP.md`**: the Phase M R2 entry moves from
  "pending" to "SHIPPED" with an ADR-0090 link.
- **`make lint-ints` clean**: the only new integer arithmetic in R2
  is the djb2 mixer's `h * 33 + byte`, kept safe by the 24-bit mask
  applied every step (5381 * 33 fits in 20 bits; every subsequent
  step is bounded by the mask). No large-literal comparisons; the
  `_FED_LE_ID_MASK = 16777215` constant is well under Bug-#11's
  problematic threshold.

## R3 preview

- `att_store_new(soul_id, signer_keys)` allocated on the Session
  after the R2 slot (uses `merkle_signing_keypair_load(base_path)`
  for the signer identity, env `CE_FED_ATTEST_KEY_DIR` for the
  key dir).
- `sr_init(gs, local_snap_dir)` allocated after att_store, wired
  against the same gossip state.
- Gossip inbound `ATTESTATION` callback invokes
  `sr_observe_attestation(sr, attestation)` -- routes through the
  same passive-drain pattern R2 uses for `dr_state`.
- Chat REPL grows `/attest_log`, `/attest_verify <soul>`,
  `/snap_fetch <root>`, `/snap_serve on|off`.
- Closes the federation-daemon arc for what can be built without
  unstubbing DTLS 1.2 (`src/federation/dtls12.nova:137, 140`).
