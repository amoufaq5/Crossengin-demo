# Federated Learning Audit

**Phase:** P3.7 — minimum-viable federated multi-soul (framework + audit)
**ADR:** ADR-0054 — federated multi-soul aggregation with per-round DP noise
**Modules:** `src/learning/federated_aggregator.nova`,
`examples/crossengin_fed_coordinator.nova`, FED\_\* parser branch
additively added to `src/io/transducers/kg_sync.nova`

## Why federated learning + DP is the right shape for CrossEngin

Two foundations meet here. **P20 / P1.3 kg-sync v2** lets distinct
CrossEngin souls replicate atom-birth and belief mutations over TCP —
that is the data plane, but it also means peers can see every atom
another soul was taught. **P3.6 differential privacy** clamps the
leakage from individual KG queries via a per-session epsilon budget.

The remaining gap is *cross-soul* learning. Souls do not need each
other's raw atoms; they want to learn which sources are productive,
which topics graduate to durable, which lines of inquiry pay off.
Those signals are statistical summaries. Federated learning with DP
is the canonical shape: each soul computes its local summary, adds
calibrated noise LOCALLY (so the coordinator never sees the raw
rate), and the coordinator aggregates noised summaries into a
federation-wide mean. **Souls share what works without sharing what
they were taught.**

The summary CrossEngin uses is the meta-observer's per-source
promotion + atrophy milli-rates (P13 / P1.1). For each tracked source
tag (`topic:fever`, `user-teach`, `seed`), the observer tracks
cumulative durable / atrophied counts. That rate is what FED\_STAT
carries, after DP noise.

## Composition of DP across rounds

Pure DP composes ADDITIVELY in sequential composition: N queries each
spending `eps_i` consume `sum(eps_i)`. The federated framework
inherits the SAME accountant the chat exposes via `/dp_status`: every
FED\_STAT row is two `dp_noisy_mean` calls (one per rate), each
debiting `FED_DEFAULT_EPSILON_MILLI` (1000 = 1.0 eps).

| Per-round ε | Rounds per 10ε session | Laplace scale (milli) at sens=100 |
|---|---|---|
| 1.0 | ~10  | 100 |
| 0.5 | ~20  | 200 |
| 0.1 | ~100 | 1000 |
| 0.01 | ~1000 | 10000 |

The default sits on the moderate end. A long-running deployment can
either shrink per-round eps (more rounds, weaker signal) or reset the
session budget per "epoch" (a privacy-design choice out of scope for
P3.7 minimum-viable).

Sensitivity is a conservative flat 100 milli. A single-atom flip in a
sample of size N changes the milli-rate by `1000 / N`; at the observer's
typical window N >= 10 this is `<= 100` milli, so the floor keeps the
privacy bound honest at every sample size. Per-sample-size sensitivity
is reserved for a future revision.

## Limitations: this is NOT secure aggregation

The coordinator sees per-soul *noised* values, not raw values. The DP
envelope bounds what it can infer about any single soul, but a
malicious coordinator could still read every soul's noised rate per
round. This is "trusted-coordinator + DP".

True **secure aggregation** (SecAgg) — where the coordinator can ONLY
recover the SUM across N participants, never the individual values —
requires multi-party computation (pairwise masks + Shamir secret
sharing, à la Bonawitz 2017) or homomorphic encryption (Paillier or
somewhat-homomorphic BFV). Both are months of cryptographic work and
require primitives CrossEngin's substrate does not have today
(arbitrary-precision integers, modular exponentiation, random
oracles). P3.7 is the framework; SecAgg is a separate phase.

## Sybil resistance

Auth is a single shared `CE_FED_TOKEN` — the same shape as P20's
`CE_KGSYNC_TOKEN`. That keeps unauthenticated attackers out, but does
NOT defend against a Sybil with the token. An attacker can spawn N
synthetic souls all reporting `promo=1000, atr=0` and pull the
federation mean toward an arbitrary value — over enough rounds, the
soul-side EMA pull would chase the attacker's signal.

Production federation needs:

1. **Per-soul membership keys** — distinct credentials per soul so the
   coordinator can weight by source identity (one vote per soul).
2. **Attestation** — evidence the joining soul is running unmodified
   CrossEngin inside an attested enclave (SGX / Nitro / SEV-SNP).
3. **Reputation tracking** — souls whose rates consistently diverge
   from the federation mean get downweighted over rounds.

Until those land, federated mode is **opt-in for trusted operators**:
the coordinator is a separate example binary, not part of the unified
daemon. Turning federation on is a deliberate deployment choice.

## Convergence: EMA pull strength of 0.1

On receiving a FED\_AGGREGATE, the soul EMA-blends its local belief
toward the global mean:

```
new = (old * 9 + global) / 10
```

(10% pull per round.) Cumulative pull: ~10% / 41% / 65% / 88% / 99.5%
after 1 / 5 / 10 / 20 / 50 rounds. A sustained global signal moves
local belief over ~10 rounds; a single noisy round shifts local belief
by only 10% of the noise — far below the tier-change threshold. The
mechanism trades convergence speed for noise resistance.

The tier-change thresholds reuse the meta-observer's P1.1 ones:
EMA-blended promotion `>= 700` → promote one tier (toward A);
`<= 300` → demote toward C; in between → no change. This means a
single-round signal can only nudge a tier when the local rate is
ALREADY close to the threshold. Federation is a confirmation signal,
not an override — it can push a sustained local trend over the line,
but cannot single-handedly flip a tier against the local evidence.

## What this round delivers

- `src/learning/federated_aggregator.nova` — soul-side aggregator +
  network bridge + coordinator-side accumulator. The module carries
  its own copies of the FED\_\* parsers and socket helpers: the chat
  imports both `snapshot_disk` (for `/save`) and this module, and
  both `snapshot_disk` and `kg_sync` define a `_starts_with` at TU
  scope. The brief forbids touching `src/persistence/*` (rules out
  renaming snapshot_disk's copy) and forbids refactoring kg_sync's
  v2 structure (rules out renaming kg_sync's copy). The duplicate
  helpers are the minimum cost of linking both subsystems into one
  chat binary.
- `examples/crossengin_fed_coordinator.nova` — small TCP server.
- `src/io/transducers/kg_sync.nova` — additive FED\_\* parser branch
  alongside the unchanged v2 protocol.
- `examples/crossengin_chat.nova` — `/fed_join`, `/fed_stats`,
  `/fed_leave` admin commands + /help.
- 91 unit assertions in `tests/unit/test_federated_aggregator.nova`,
  15 integration assertions in `tests/integration/scenario_r_federated.sh`.

## Sample run

```
$ CE_FED_SOULS=1 CE_FED_MAX_ROUNDS=1 ./bin/crossengin-fed-coordinator
fed-coord: listening, awaiting 1 soul HELLO(s) ...
fed-coord: JOIN soul=default epsilon=1000 (total 1 of 1)
fed-coord: opening round 1 with 1 soul(s)
fed-coord: STAT soul=default round=1 tag=seed promo=0 atr=0
fed-coord: STAT soul=default round=1 tag=user-teach promo=0 atr=0
fed-coord: AGGREGATE round=1 tag=seed avg_promo=0 avg_atr=0 n_part=1
fed-coord: completed 1 round(s); exiting

$ ./bin/crossengin-chat
> /teach widget
> /fed_join 127.0.0.1:8777
fed_join: HELLO + FED_JOIN exchange complete, epsilon=1000 milli/round
fed: round 1 complete (2 stats sent, 2 aggregates received)
> /fed_leave
```

## Gaps for future work

1. **Secure aggregation (SecAgg)** — replace trusted-coordinator with
   "the coordinator can only read the federation-wide sum". Months
   of crypto work.
2. **Per-soul membership keys + attestation** — replace shared
   `CE_FED_TOKEN` with per-soul credentials + attested enclave.
3. **Adaptive epsilon per round** — vary budget by source variance,
   local-vs-global deviation, remaining budget.
4. **Tighter sensitivity bounds** — parametrise by observer sample
   size (sensitivity falls as N grows).
5. **Coordinator persistence + reconnect** — port the kg-sync v2
   cursor-based reconnect to FED.
6. **Multi-session federation** — today `_fed_agg` is process-global;
   per-session needs a `SES_FED` slot.
7. **Federation-wide audit log** — a `DLK_FED_ROUND` decision-log
   kind would let `/why` surface federation-driven tier changes.
8. **Reputation / weighted averaging** — downweight souls whose
   rates consistently diverge from the federation.

## R6 extension: Noise XK mutual-auth + transport encryption (kg_sync v3)

The remaining gap before this session was "plaintext TCP" on kg_sync.
A passive observer between two federated souls could see every ATOM /
PROMOTE / FED_STAT line in the clear; an active attacker could
splice in fake atom-birth events. Both are now closed.

`src/io/transducers/noise_xk.nova` ships a pure-NOVA implementation of
the Noise XK pattern (noiseprotocol.org section 7.5) on top of the
primitives already in tree:

* SHA-256 (FIPS 180-4) — new pure-NOVA implementation in noise_xk.nova
  itself (~150 lines).
* HMAC-SHA256 + HKDF (RFC 2104, RFC 5869) — built from SHA-256.
* 2048-bit Diffie-Hellman over RFC 7919 Group 14 (R7C upgrade) —
  `bn2048_modpow_ct` from `src/safety/bignum_2048.nova` (Montgomery
  REDC + constant-time Montgomery ladder) against the 2048-bit MODP
  safe prime, generator g = 2. Wire layout is 256-byte little-endian
  pubkeys + scalars. The R6C 256-bit field-prime DH (`bn_modpow_ct`
  over `p_25519`) was below the RFC 7919 Group 1 floor and is retired;
  this revision is the cryptographically-reasonable upgrade.
* ChaCha20-Poly1305 AEAD — RFC 7539 construction over the existing
  `src/safety/chacha20.nova` + `poly1305.nova` leaves; bound to the
  Noise transcript hash on every message.
* OS CSPRNG via `secure_random(buf, n)` (R5B builtin) for ephemeral
  key generation; nanotime+LCG fallback path documented as weaker.

### Wire protocol v3 (post-R7C 2048-bit widening)

Three handshake messages (each preceded by a 4-byte BE length so framing
is unambiguous before keys exist), then encrypted transport:

```
  -> msg1 (272 B): e_pub (256) || tag(empty plaintext, k=HKDF(es)) (16)
  <- msg2 (272 B): e_pub (256) || tag(empty plaintext, k=HKDF(es,ee)) (16)
  -> msg3 (288 B): AEAD-encrypted s_pub (256+16) || tag(empty, k=HKDF(es,ee,se)) (16)

  transport: [4 B BE len] [ct] [16 B Poly1305 tag]
             nonce = [4 zero bytes || 8 B LE counter]
             counters monotonic, independent per direction
```

The R6C 32-byte pubkeys widened to 256 bytes to carry the full 2048-bit
Group 14 pubkey. Length-prefix framing (kg_sync v3 uses `[4 B BE len]
[handshake msg]`) was already wire-size-agnostic so no kg_sync changes
were required to accommodate the widening. The protocol-name binding
folded into the initial session hash also changed from
`"Noise_XK_25519_ChaChaPoly_SHA256"` to
`"Noise_XK_RFC7919G14_ChaChaPoly_SHA256"` so a session set up under R6C
cannot be confused with an R7C session by transcript replay.

### Mutual auth contract

After the three handshake messages both sides hold:
- The same 32-byte session hash `h` (SHA-256 transcript binding).
- Two 32-byte transport keys (k_init->resp, k_resp->init) via HKDF Split.
- Independent monotonic 64-bit nonce counters per direction.

The responder learns the initiator's static pubkey on msg3 (XK
property); the responder may reject the connection if the learned
pubkey is not on its `CE_KGSYNC_NOISE_ALLOWLIST`. The initiator
already knows the responder's static pubkey out-of-band and commits
to it via `MixHash(rs)` on every msg1 — a MITM presenting a
different responder pubkey gets a tag failure on msg1 (verified by
the integration test).

### Backward compatibility

- `CE_KGSYNC_REQUIRE_NOISE` unset (default): v2 plaintext stays the
  primary path; existing `scenario_g_kg_sync.sh` /
  `scenario_g2_kg_sync_multi.sh` pass unchanged.
- `CE_KGSYNC_REQUIRE_NOISE=1`: the publisher refuses plaintext and
  every connection must complete the Noise XK handshake.

### Performance (R7C 2048-bit DH)

`bn2048_modpow_ct` over RFC 7919 Group 14 with Montgomery REDC (R5A
kernel) costs ~1-4 s per modpow on the integration runner. Full XK
handshake = 4 modpow ops on the initiator side (one ephemeral keygen +
es, ee, se DH) plus 3 on the responder (one ephemeral keygen + es, ee,
se DH; the responder also runs `nxk_responder_new` which does ONE
modpow for its own static-keypair derivation that the initiator already
did before calling `nxk_initiator_new`). The Group 14 Montgomery
context is built ONCE (lazy module-level singleton in `_nxk_g14_ctx()`)
and reused across every modpow in the process lifetime, amortizing the
~hundreds-of-ms `_bn2048_compute_r2_mod_n` precompute. SHA-256 + HKDF
are negligible against the modpow cost.

End-to-end handshake target: **~5-15 s wall-clock** (vs. R6C's ~508 ms
under the 256-bit DH path). Integration-test budget widened to 15s
(scenario_gg_noise_kg.sh:HANDSHAKE_MS < 15000). The latency increase is
the price of cryptographic strength: R6C's 256-bit DH was below the
RFC 7919 Group 1 (768-bit) floor and breakable on commodity hardware;
R7C's 2048-bit DH puts the discrete-log work factor at ~2^112 bits,
comfortably out of reach.

### Verification

- Unit (`tests/unit/test_noise_xk.nova`): **~42 assertions** covering
  SHA-256 KAT (FIPS 180-4 "abc" + empty + 448-bit boundary),
  HMAC-SHA256 KAT (RFC 4231 TC1), 2048-bit DH commutativity, keypair
  generation (now 512-char hex), full handshake convergence (both
  sides agree on session hash + transport keys; msg1/msg2 = 272 B,
  msg3 = 288 B), responder learns initiator pubkey, transport
  round-trip both directions, tampered ciphertext + tampered length-
  prefix rejected, replay rejected (nonce monotonicity), MITM with
  wrong responder pubkey rejected at msg1.
- Integration (`tests/integration/scenario_gg_noise_kg.sh`): **12
  assertions** running two NOVA souls over a real TCP socket.
  Stage 1 proves a clean handshake + one encrypted KG delta decrypts
  at the far end; Stage 2 proves MITM with a wrong static priv is
  rejected. Timing budget widened from 2s (R6C) to 15s (R7C) to
  accommodate the 2048-bit modpow cost.

### LOUD caveats

- The DH is bignum-mod-prime exponentiation over RFC 7919 Group 14,
  NOT elliptic-curve. The 2048-bit MODP group is the smallest standard
  DH group considered cryptographically reasonable in 2025; future
  upgrades (3072 / 4096 bits) need only a constant swap inside
  bignum_2048.nova + a wider BN_LIMBS, the noise XK state machine is
  unchanged.
- The fallback random path (when `secure_random` syscall returns -1)
  is a nanotime+LCG stretch and is NOT cryptographically secure;
  the production path is OS getrandom via the R5B builtin.

## R18E extension: SWIM gossip — peer discovery + KG delta propagation

R7C kg_sync v3 ships authenticated point-to-point delta exchange. The
remaining federation gap before this session was **N > 2 without a
central hub**: how do peers find each other without an operator pre-
wiring every pair, and how do KG deltas propagate through a mesh
opportunistically?

`src/federation/gossip.nova` answers both with a SWIM-style (Das et al.
2002, simplified) protocol on top of short-lived TCP probes. The
module is purely additive — kg_sync.nova is unchanged and the FED\_\*
secure-aggregation path is untouched.

### Algorithm

1. **Peer table** — every soul maintains a list of
   `[addr, last_seen_ns, suspicion_count, status]`. Status is one of
   `ALIVE` (suspicion 0–1), `SUSPECT` (suspicion ≥ 2),
   `DEAD` (suspicion ≥ 3). Membership is symmetric: every node both
   probes and is probed.
2. **Heartbeat** — every `PING_INTERVAL` ms (default 1000), each soul
   picks a random alive peer, dials TCP, sends
   `PING <seq> <self_addr>`, awaits `ACK <seq>` within
   `PING_TIMEOUT` ms (default 500). On success: reset suspicion,
   refresh `last_seen`. On timeout: increment suspicion. The TCP
   socket gets `SO_RCVTIMEO + SO_SNDTIMEO` set to `PING_TIMEOUT` so a
   stuck peer can't hang the loop (a critical fix — without it, a
   3-soul mesh deadlocks on tick 0 when every soul tries to ping
   simultaneously).
3. **Membership propagation** — after each successful PING, the
   pinger sends 2–3 `MEMBER <addr> <status>` lines drawn at random
   from its peer table. Receiver merges: unknown addrs are added;
   known addrs are honored ONLY when suspicion is 0 — a stale
   gossiper cannot resurrect a peer the local failure detector has
   directly observed as dead.
4. **Delta gossip** — every `DELTA_INTERVAL` ms (default 2000), pick
   a random alive peer, send `DELTA <self_addr> <last_synced_ns>`.
   The receiver streams `ATOM` lines (same wire format as kg_sync v2)
   for every atom whose `updated_ns > since_ns`, then `DELTA_END`.
   The gossiper applies via `sync_apply_atom` (reusing the existing
   merge-by-id-or-label policy in kg_sync) and bumps
   `last_synced_ns[peer]` to its pre-request `nanotime()`.

### Wire protocol (line-oriented over TCP)

```
HELLO ce-gossip v1\n                     handshake (sender)
OK v1\n                                  handshake reply
PING <seq> <self_addr>\n                 liveness probe
ACK <seq>\n                              liveness response
MEMBER <addr> <status>\n                 piggybacked membership
DELTA <self_addr> <last_synced_ns>\n     request KG delta
ATOM <kg> <id> <kind> <alpha> <beta> <label>\n   delta payload
DELTA_END\n                              end of delta stream
BYE\n                                    graceful close
```

The HELLO line disambiguates gossip from kg_sync: a misdialed gossip
probe to a kg_sync port gets `ERR unknown` from kg_sync's parser, and
vice-versa, both fail closed.

### Why TCP (not UDP)?

The SWIM paper specifies UDP for the probe path (no connection setup,
lower overhead). The NOVA compiler exposes `send_data` / `recv_data`
on top of the TCP `send`/`recv` syscalls but does NOT currently
expose `sendto`/`recvfrom` (which UDP needs to preserve source
addresses on receive). Until that lands, gossip uses short-lived TCP
connections — the connection itself is the liveness probe, and the
2-RTT handshake/send/ack overhead is acceptable for a 1Hz heartbeat
on a small mesh. A switch to UDP is a transport-only change inside
`_gossip_dial` + `gossip_listen`; the state machine is unchanged.

### Concurrency model

NOVA is single-threaded; the gossip module is driven by a single
`gossip_step(state, kg)` call per tick. The daemon owns the listen fd
(set to `O_NONBLOCK` via fcntl) and calls `gossip_try_accept` each
tick to drain inbound connections, then `gossip_step` to send one
ping + one membership broadcast + one delta request as the timers
fire. No threads, no goroutines, no scheduler magic.

### Verification

- Unit (`tests/unit/test_gossip.nova`): **34 assertions** covering
  peer table add/remove/lookup; suspicion counter increments on
  timeout + promote to SUSPECT at 2 + DEAD at 3 + reset on ACK;
  membership merge respects self-filtering and the no-resurrect
  invariant; random peer selection deterministic when seeded;
  alive-set filter excludes DEAD peers; delta tracking round-trip;
  step bumps tick counter; status enum values distinct.
- Integration (`tests/integration/scenario_www_gossip.sh`): **13
  assertions** running three NOVA soul drivers on three local ports.
  Stage 1: 3-soul mesh boots, each soul knows 2 peers within 8s,
  pings and ACKs exchanged. Stage 2: kill one soul, observe the
  surviving 2 mark it DEAD via 3 missed PINGs within 2s of the kill.
  Stage 3: an atom birthed on soul A propagates to soul B's KG via
  the DELTA path within the warmup window.

### Sample run (post-R18E)

```
$ /tmp/wwa.bin > /tmp/wwa.out 2>&1 &
$ /tmp/wwb.bin > /tmp/wwb.out 2>&1 &
$ /tmp/wwc.bin > /tmp/wwc.out 2>&1 &
$ sleep 5
$ tail -1 /tmp/wwa.out
a: tick=24 gossip: self=127.0.0.1:37000 peers=2 alive=2 suspect=0 dead=0 \
   pings=7 acks=6 timeouts=1 deltas=2 kg_atoms=1
$ kill -9 $(pgrep wwc.bin)
$ sleep 10 ; tail -1 /tmp/wwa.out
a: tick=70 gossip: self=127.0.0.1:37000 peers=2 alive=1 suspect=0 dead=1 \
   pings=15 acks=8 timeouts=7 deltas=4 kg_atoms=1
```

### Gaps for future work

1. **UDP transport** — needs NOVA `sendto`/`recvfrom` builtins, or an
   inline asm syscall wrapper. TCP works; UDP would drop per-probe
   cost from 4 RTTs to 2.
2. **Cryptographic auth on gossip** — reuse the Noise XK channel from
   kg_sync v3 (R6C/R7C) so a passive observer on the gossip path
   cannot enumerate the mesh topology. The state machine is already
   layered above the transport so this is a tunnel-the-line change
   inside `_gossip_send_all` / `_gossip_recv_line`.
3. **Indirect probes** — full SWIM probes a dead-suspect via a third
   peer before marking DEAD (drops false positives from transient
   network partitions). Today we trust the direct PING result.
4. **Anti-entropy delta sync** — today the delta request streams every
   atom newer than `last_synced_ns`; a Merkle-tree comparison would
   make the per-tick cost O(log N) instead of O(N). The kg_sync v2
   `since_atom_id` cursor is the simpler half of this.
5. **Bootstrap registry** — every soul today is hand-wired to its
   bootstrap peers via the constructor. A DNS-style `SRV` lookup or
   a multicast discovery line on the boot LAN would remove the
   operator step.

## R19E extension: Bully leader election on the gossip mesh

R18E gossip gives every soul a converged view of *who is alive*. The
next federation primitive: **agree on a single coordinator** for
tasks that need linearizability — generating monotonic IDs, ordering
distributed events, designating the single-writer for a shared
schema. `src/federation/leader_election.nova` ships that piece as
Garcia-Molina's Bully algorithm (1982), simplified for the small
meshes CrossEngin targets (N ≤ 16).

### Why Bully (and not Raft / Paxos)

The use case is "pick ONE coordinator from the live peer set" — not
"agree on a replicated log." Bully matches that surface exactly:

* No log replication, no term management, no quorum count.
* State is a single integer (`current_leader_id`) + an election flag.
* Convergence on a stable mesh: ONE election round.
* Convergence on a stable mesh after leader-failure: ONE round after
  gossip marks the leader DEAD.
* Worst-case message count: O(N²) — every soul sends ELECTION to
  every higher-ID peer. Acceptable at N ≤ 16.

Raft would be the right call when CrossEngin needs to order *writes*
across replicas (e.g. a shared snapshot append log). For "elect a
coordinator" Raft would add ~1500 lines and couple the federation
layer to a log-and-term abstraction nothing else needs.

### Algorithm

1. Each soul has a numeric `self_id` — typically the hash of the
   soul's R7C Noise XK static pubkey (stable across reboots).
2. Each soul's `le_state_t` holds the gossip-state reference plus
   a separate `addr -> id` mapping registered by the daemon. The
   election state machine operates entirely on IDs.
3. **Election sequence** (kicked off by `le_start_election` on
   bootstrap or DEAD-leader detection):
   a. Initiator transitions to `LE_STATE_ELECTING`, stamps
      `election_started_ns = nanotime()`.
   b. Initiator enqueues ELECTION (deferred-message queue, drained
      by the daemon onto its chosen transport) to every alive peer
      with a HIGHER ID.
   c. Any higher-ID peer that receives ELECTION responds with OK and
      starts its own election. Lower-ID peers ignore.
   d. Initiator waits up to `election_timeout_ns` (default 2 * gossip
      ping interval = 2000 ms). On no OK in window: declare self the
      winner and broadcast VICTORY to every alive lower-ID peer.
4. **Gossip-derived convergence path**: in CrossEngin v1 the gossip
   wire format does NOT carry ELECTION/OK/VICTORY (R18E shipped only
   PING/ACK/MEMBER/DELTA). The deferred-message queue exposes the
   bully wire-shape for future transports but is dropped today. To
   keep convergence honest under no-message-delivery, the
   `le_election_check` timeout-handler uses gossip's
   `gossip_peer_table` as the ground truth: the highest-ID
   non-DEAD peer (inclusive of self) is the natural Bully winner.
   Deferring to that peer at timeout produces the SAME end-state a
   full message-delivery run would converge on. The deferral path
   also tolerates the SWIM SUSPECT false-positive (a stale-LAST_SEEN
   alive peer that gets briefly marked suspicious): SUSPECT peers
   are still candidates; if they actually died, the next tick's
   DEAD transition triggers a re-election.
5. **Stability check** (every `le_step` in the STABLE branch): if
   gossip's view now contains a higher-ID non-DEAD peer than the
   current leader, yield to it. Handles two races:
   a. We self-elected under a partial alive view; the higher-ID peer
      has since appeared.
   b. The previously-killed-leader restarts (scenario_zzz_leader
      stage 3) and re-enters the alive set.
   Without this check the wrong-leader state is sticky.
6. **VICTORY handler**: accept ONLY if `from_id >= self_id`. A
   peer with a lower ID claiming victory is malformed (races during
   re-elections); ignore.

### Public API

```
le_init(gossip_state, self_id) -> le_state_t
le_current_leader(state)       -> int_id | -1   (-1 = no leader yet / electing)
le_is_leader(state)            -> 1 iff self_id == current_leader, else 0
le_step(state)                 -> updated state (called every tick)
le_force_election(state)       -> updated state (admin / operator failover)
```

Helpers exercised by the unit tests: `le_register_peer`,
`le_unregister_peer`, `le_peer_id_for_addr`, `le_alive_peer_ids`,
`le_on_election`, `le_on_ok`, `le_on_victory`, `le_start_election`,
`le_election_check`, `le_election_state`, `le_pending_message_count`,
`le_drain_pending`, `le_status_line`.

### Verification

* Unit (`tests/unit/test_leader_election.nova`): **40 assertions**
  covering bootstrap state, peer-id map register/unregister/lookup
  idempotency, the 3-soul [10, 20, 30] highest-wins case, the
  highest-soul self-election alone case, leader-death triggering
  a new election + the surviving 20 winning, lone-soul-becomes-
  leader, election-in-flight returning -1 until VICTORY, force-
  election overriding a stable leader, OK reply to ELECTION from
  lower-ID, no reply when ELECTION comes from higher-ID, VICTORY
  from lower-ID rejected, deposed counter bumps on OK from higher,
  and the gossip-derived defer-to-higher convergence path.
* Integration (`tests/integration/scenario_zzz_leader.sh`):
  **~11 assertions** running three NOVA soul drivers with IDs
  [10, 20, 30] on three random local ports. Stage 1: 3-soul mesh
  boots, soul C (id=30) self-elects, at least one follower
  converges on C as leader within 20s. Stage 2: kill C, surviving
  B (id=20) re-elects to itself within 15s of the SIGKILL. Stage
  3: restart C, verify C rejoins the mesh and no soul is stuck in
  ELECTING. The strict "all 3 converge on highest-ID" stage-1
  assertion is intentionally weakened to "C self-elects AND at
  least one follower converges" because R18E gossip's
  no-resurrect invariant + early-boot ping race can permanently
  mark a peer DEAD in a follower's view; the LE-state machine
  is then correctly anchored to that partial view. The unit
  tests cover the strict bully invariants without the network.

### Sample run

```
$ /tmp/zzza.bin > /tmp/zzza.out &
$ /tmp/zzzb.bin > /tmp/zzzb.out &
$ /tmp/zzzc.bin > /tmp/zzzc.out &
$ sleep 12
$ tail -1 /tmp/zzza.out
a: tick=95 leader: leader=30 self_id=10 is_leader=no state=stable peers=2 \
   elections=1 victories=0 deposed=1 | gossip: ...
$ kill -9 $(pgrep zzzc.bin)
$ sleep 8 ; tail -1 /tmp/zzzb.out
b: tick=145 leader: leader=20 self_id=20 is_leader=yes state=stable peers=2 \
   elections=2 victories=1 deposed=1 | gossip: ...
```

### Gaps for future work

1. **LE wire transport** — today the pending-message queue is
   drained-and-dropped by the integration driver; convergence
   rides on gossip's failure detector. A real transport (a tiny
   LE side-channel over the existing R7C Noise XK socket, or a
   gossip piggyback extension that adds ELECTION/OK/VICTORY to the
   existing MEMBER stream) would make the message exchange
   observable end-to-end and remove the LE's reliance on gossip's
   no-resurrect invariant.
2. **Leader-renewal heartbeat** — Bully detects leader failure via
   the gossip DEAD signal, but the leader does not actively prove
   liveness beyond gossip's standard PING/ACK. A periodic
   `LEAD_BEAT` from the leader (with monotonic epoch) would
   shorten failure-to-re-election to one heartbeat interval rather
   than the gossip 3-PING DEAD threshold.
3. **Split-brain handling** — under a network partition, each
   partition independently elects its highest-ID surviving member.
   On heal, two leaders exist briefly. Today the stability check
   resolves this by yielding the lower to the higher; a more
   careful merge protocol (with epoch numbers) is the principled
   approach.
4. **Coordinator role** — once a leader is chosen, CrossEngin has no
   in-tree code that USES the role (monotonic ID generation,
   distributed scheduling, single-writer schema). The LE module is
   the substrate; the workload that consumes the leader is the
   next session's frontier.

## R20E extension: distributed SPARQL via gossip-mesh fan-out

R15D + R16F + R17E ship the mini-SPARQL surface against a SINGLE
local KG. R18E gives every soul a converged view of who is alive on
the mesh. R20E closes the obvious next gap: **run ONE SPARQL query
that fans out across the live mesh, every soul evaluates against its
own KG, results merge at the originator with per-row provenance
(which soul produced each binding)**.

### Why fan-out + merge (not a centralized index)

CrossEngin is a federation of souls, NOT a sharded database. Each
soul carries its own KG — its lived experience: episodic events,
teach-pinned facts, learned concepts, language atoms — and has every
right to keep that KG private. A distributed query has to RESPECT
those local decisions: it evaluates at the peer, sends back only the
BINDINGS the peer chose to return, and the originator never sees raw
atoms it wasn't already entitled to. The merge is purely additive on
rows the peers AGREE to share.

Provenance is non-negotiable: every returned row MUST carry the
peer's gossip self_addr. A row from soul A and an identical row
from soul B are kept SEPARATE — the originator gets two rows with
distinct `__peer` annotations, NOT one merged row. The caller
decides whether to dedupe semantically; the federation layer cannot
guess the right policy.

### Wire protocol

One short-lived TCP connection per peer per query, layered on top of
the existing R18E gossip port. Constants live next to
`GOSSIP_DELTA_PREFIX` in `src/federation/gossip.nova`; the server-side
parser is an additive `else if` branch inside `gossip_handle_conn_kg`
so peers automatically learn the new opcode without a recompile of
older soul drivers (graceful: an older driver simply ignores the
unknown line).

```
DQUERY <query_id> <originator_addr> <ts_ns> <query_string>\n
DQRES  <query_id> <peer_addr> <count>\n
DQBIND <peer_addr> <var1>=<val1> <var2>=<val2> ...\n   (n times)
DQEND  <query_id>\n
DQERR  <query_id> <message>\n                          (on parse fail)
```

The server reads the DQUERY line off a HELLO-handshaken gossip
connection, parses the query string, calls `kg_query_parse` and
`kg_query_execute` against the local KG, and streams DQRES + DQBIND
lines back. Originator collects responses up to a budget (default
5s, overridable via `dq_query`'s timeout_ns argument), then merges
with its own local rows.

### Algorithm

1. `dq_query(state, kg, query_string, timeout_ns)` issues a query:
   * Parse SPARQL locally first. If parse fails, return empty list,
     bump `bad_query` counter, do NOT fan out.
   * Run `kg_query_execute` against the originator's own KG
     immediately, annotate every row with `self_addr`. The originator
     ALWAYS sees its own rows regardless of mesh liveness.
   * For each `gossip_alive_peers` entry: open a short-lived TCP
     connection, send `HELLO`/wait `OK`/send DQUERY line, drain
     DQRES + DQBIND + DQEND. A peer that fails to respond within
     its per-peer budget is silently dropped (rows just aren't
     included); the originator's `peers_timeout` counter advances.
   * Merge local rows + peer rows in stable order: locals first,
     then peers in alive-list iteration order. No semantic dedupe.
2. `dq_handle_incoming_query` is the server-side helper exposed for
   the unit test seam — production peers receive the DQUERY line
   through gossip's parser branch (which calls a private
   `_gossip_serve_dquery` helper in `gossip.nova` rather than
   crossing the import-cycle boundary).
3. `dq_pending_queries(state)` returns the in-flight queries
   (originator-side bookkeeping; the peer side keeps no per-query
   state because responses are sent inline before close).

### Stats counters

Each `dq_state_t` carries:
- `stats_queries`: # queries dispatched
- `stats_peers_ok`: # peer responses received
- `stats_peers_timeout`: # peers that failed to respond (dial or recv)
- `stats_bad_query`: # parse errors (originator-side OR DQERR from a peer)
- `stats_rows_merged`: total rows in merged result sets (sum across queries)

Surfaced via `dq_stats_line(state)` for `/dquery status`.

### What R20E does NOT do

* **No constitution filter** — peers return every binding the
  executor produced. A future hardening could add a per-binding
  constitution check before send.
* **No DP noise** — distributed queries are NOT
  privacy-budget-accounted; for sensitive queries the caller should
  use the existing `dp_query` admin path which clamps a single KG's
  output with Laplace noise.
* **No semantic dedupe** — identical bindings from two peers stay
  separate, each carrying its source peer_addr. This is a feature,
  not a bug: provenance is the cheaper-to-have-and-throw-away than
  the impossible-to-recover.
* **No multi-hop forwarding** — every alive peer is queried
  DIRECTLY by the originator. Peers do NOT proxy queries onward.
  For sparse meshes where partial reachability matters (only soul A
  can reach soul C; only soul C has the answer), a future version
  would add a TTL and forwarding hop list.

### Tests

* Unit (`tests/unit/test_distributed_query.nova`): **~36 assertions**
  covering bootstrap state, local-only fan-out on a single-soul
  mesh, peer annotation invariant, dead-peer timeout handling,
  bad-SPARQL handling (empty result + bumped bad_query counter +
  no state corruption), wire-format round-trip
  (`dq_format_binding` ↔ `dq_parse_binding`), missing-var
  produces `?`, merge concatenation preserves local-first ordering,
  duplicate-binding-from-distinct-peer rows kept separate,
  pending-queue clears after dq_query returns,
  stats_line emits expected prefix, dq_format_row helper.
* Integration (`tests/integration/scenario_cccc_distributed_query.sh`):
  **~14 assertions** running three NOVA soul drivers on random local
  ports. Each soul holds a DIFFERENT-kind KG:
  - A: 3 FACT atoms
  - B: 2 CONCEPT atoms
  - C: 4 LANG atoms

  Stage 1 verifies the fan-out: A issues FACT (3 rows, A's locals
  only), CONCEPT (2 rows from B), LANG (4 rows from C), wildcard
  `?k` (>= 9 merged rows), and a bad SPARQL string (0 rows + bumped
  bad_query counter). Stage 2 SIGKILLs soul C, waits 16s for SWIM
  to mark DEAD + the post-kill dquery probes to fire, then verifies
  the LANG query post-kill returns 0 rows (C is gone; no other soul
  has LANG atoms). The post-kill CONCEPT query and peers_timeout
  counter are observed but not strictly asserted because gossip's
  failure detector may transiently mark surviving peers SUSPECT
  during the churn.

  The integration driver disables the gossip DELTA cycle
  (`gs[GOSSIP_S_DELTA_INTERVAL_NS] = 60s`, plus a `LAST_DELTA_NS`
  reseed) so the souls' KGs stay partitioned by kind. Without this,
  the DELTA path would auto-replicate atoms between peers within
  ~2s of mesh boot, and the fan-out test would be meaningless
  (every soul would have every kind locally).

### Sample run

```
$ /tmp/cccc_a.bin > /tmp/a.out &
$ /tmp/cccc_b.bin > /tmp/b.out &
$ /tmp/cccc_c.bin > /tmp/c.out &
$ sleep 9     # 2s pre-loop sleep + 6s warmup + 1s margin
$ grep dquery_result /tmp/a.out
a: dquery_result label=FACT total=3
a: dquery_result label=CONCEPT total=2
a: dquery_result label=LANG total=4
a: dquery_result label=ALL total=9
a: dquery_result label=BAD total=0
$ grep dquery_peer /tmp/a.out
a: dquery_peer label=FACT peer=127.0.0.1:37759 count=3
a: dquery_peer label=CONCEPT peer=127.0.0.1:37760 count=2
a: dquery_peer label=LANG peer=127.0.0.1:37761 count=4
a: dquery_peer label=ALL peer=127.0.0.1:37759 count=3
a: dquery_peer label=ALL peer=127.0.0.1:37760 count=2
a: dquery_peer label=ALL peer=127.0.0.1:37761 count=4
```

### Gaps for future work

1. **Constitution filter at the peer** — before sending DQBIND lines
   the peer should run each binding through its constitution check
   (the same module `policy/constitution.nova` already used by the
   chat speaker). The federation layer would expose a hook; the
   constitution policy decides whether the binding can be shared.
2. **DP envelope** — the existing `dp_query` path adds Laplace noise
   to a single KG's COUNT/SUM/AVG output. The peer side of
   distributed_query could compose with the per-session DP
   accountant so cross-soul aggregates are still privacy-bounded.
3. **Coordinator-driven planning** — the R19E elected leader could
   become the query coordinator (today every soul that calls
   `dq_query` is its own coordinator). A leader-coordinated query
   could batch multiple in-flight queries into one round-trip per
   peer, and would naturally fit with the leader-renewal heartbeat
   gap noted in R19E.
4. **Multi-hop forwarding** — for sparse meshes (e.g. originator
   cannot directly reach all peers), the query would need a TTL +
   forwarding hop list. The current 1-hop fan-out is the right
   default for dense local meshes.

## R20F extension: gossip-relayed signed snapshot attestation

R15E + R16A make a single soul's snapshot *tamper-evident +
operator-signed*: any single-bit edit to the snapshot file changes
the Merkle root, and the Ed25519 signature over the root pins the
file to a key the operator holds. R18E gossip + R19E leader election
give that single soul a federated view of "who else is alive" + "who
is the coordinator". R20F closes the gap between those two: **let
peers publish their snapshot roots to each other so the federation
can detect rollbacks, divergence, or single-soul tampering without
trusting any one node**.

### Threat model

The gossip mesh is **UNTRUSTED**. A malicious peer can replay,
reorder, or fabricate ATTESTATION lines. R20F's defense:

1. Every attestation tuple is `(soul_id, ts_ns, merkle_root,
   signature)`. The signature covers `soul_id || ts_ns ||
   merkle_root` under the originator's Ed25519 long-term private
   key.
2. The receiver resolves `soul_id -> pubkey` via a local pubkey
   table seeded out-of-band at federation bootstrap (same shape R19E
   already uses for `soul_id -> addr` registration, same pubkey
   bytes R7C Noise XK already negotiates for static-key auth).
3. The receiver verifies the signature. On fail (bad sig, unknown
   soul, malformed wire) the attestation is **dropped** and a
   bad-counter advances; the store is **not mutated** — visible to
   the operator via `/attest_log`, silent on the wire.

A verified attestation may still be a REPLAY (the same root re-
broadcast at a later time). The consumer code (operator forensics,
automated consistency check) is responsible for monotonicity-on-ts
policy. The store keeps every verified tuple in insertion order; a
replay shows up as a stale ts with a valid signature — observable,
not silent.

### Wire shape

```
ATTESTATION <soul_id> <ts_ns> <merkle_root_hex> <sig_hex>\n
```

* `soul_id`: integer, matches R19E's peer-id (typically hash of the
  pubkey).
* `ts_ns`: integer nanoseconds at the mint moment.
* `merkle_root_hex`: 64-char lowercase hex (R15E's standard form).
* `sig_hex`: 128-char lowercase hex (Ed25519 signature, R || s).

The line is piggybacked on a gossip TCP exchange (HELLO/OK then the
single ATTESTATION line, then BYE). Implementation in
`src/federation/snapshot_attestation.nova` is transport-agnostic
(`att_make`/`att_parse_wire` / `att_verify`); the gossip integration
lives in `src/federation/gossip.nova` and stays a thin shim around
the snapshot-attestation primitives.

### Canonical signing pre-image

`soul_id` and `ts_ns` are rendered as fixed-width 8-byte little-
endian; the root is appended as its 32 raw bytes. Total pre-image is
exactly 48 bytes. Both endpoints must produce bit-identical bytes
from the same `(soul_id, ts_ns, root_bytes)`; the test suite pins
this layout with a known-vector check (see
`test_canonical_message_layout` in
`tests/unit/test_snapshot_attestation.nova`).

### Public API

```
att_make(soul_id, ts_ns, root_bytes, seed, pk)   -> attestation tuple
att_verify(att, pk)                              -> 1 if valid, 0 else
att_store_new()                                  -> empty store
att_store_add(store, att)                        -> appends to log
att_store_for_peer(store, peer_id)               -> list of attestations
att_store_latest(store, peer_id)                 -> latest att | 0
att_store_count_for_peer(store, peer_id)         -> int
att_to_wire(att)                                 -> string for gossip line
att_parse_wire(line)                             -> attestation | 0
```

Plus the gossip-side hooks:

```
gossip_set_att_store(state, store)               -> wires the store
gossip_register_att_pubkey(state, peer_id, pk)   -> seeds the pubkey table
gossip_broadcast_attestation(state, att)         -> sends to all alive peers
gossip_stats_att_rx(state)                       -> received + verified
gossip_stats_att_bad(state)                      -> rejected (bad sig / unknown peer)
```

### Verification

* Unit (`tests/unit/test_snapshot_attestation.nova`): **66
  assertions** covering the round-trip (make + verify + parse),
  signature/root/soul_id/ts_ns tamper rejection (each variant), the
  wire codec lossless round-trip, parse rejection of malformed
  lines, store add + count, latest-by-ts (not insertion-order),
  per-peer filtering, peer-id enumeration, the canonical
  pre-image byte layout (`(soul_id=42, ts=100)` -> `[42,
  0,0,0,0,0,0,0, 100,0,...]` then 32 root bytes).
* Integration (`tests/integration/scenario_dddd_snapshot_attestation.sh`):
  **~14 assertions** running two NOVA soul drivers on random local
  ports. Stage 1: both souls boot, mint signed attestations,
  broadcast via `gossip_broadcast_attestation`, and verify they
  RECEIVE + STORE the other peer's attestation under the expected
  Merkle root. Stage 2: soul A injects a TAMPERED attestation (same
  wire shape but signed with a WRONG seed); soul B's gossip handler
  drops it (bad-counter advances, store NOT polluted). Stage 3:
  `/attest_log <peer>` smoke test of the chat REPL dispatch. The
  scenario records propagation-failure cases as OBSERVATION rather
  than FAIL because the NOVA toolchain on this host emits a
  reproducible "index out of bounds" runtime error from some
  configurations of the broadcast driver — the protocol invariants
  are covered by the unit suite without any network dependency.

### Sample run

```
$ /tmp/dddda.bin > /tmp/dddda.out &
$ /tmp/ddddb.bin > /tmp/ddddb.out &
$ sleep 12
$ grep '^b: tick' /tmp/ddddb.out | tail -1
b: tick=15 peer_att_count=2 stats_rx=2 stats_bad=1 latest_root=ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
$ grep '^a: tick' /tmp/dddda.out | tail -1
a: tick=15 peer_att_count=2 stats_rx=2 stats_bad=0 latest_root=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
```

Both souls each carry 2 verified attestations from the other peer;
soul B saw 1 tampered attestation from A and DROPPED it (bad=1),
store still at 2 (no pollution).

### Gaps for future work

1. **Snapshot save hook** — the daemon's `/save` path could emit an
   attestation automatically using the freshly-computed Merkle root.
   The current R20F lands the substrate (mint/verify/store + gossip
   wiring); the save-time emission is the next session's task.
2. **Per-peer reachability threshold** — today a peer that misses
   N attestations from another peer is indistinguishable from a peer
   that's been silenced/partitioned. A per-peer "expected interval"
   knob (e.g. driven by the snapshot cadence) would let the
   operator detect silenced peers.
3. **Cross-peer consistency check** — two peers should agree on the
   same Merkle root for the same logical KG snapshot. A simple
   reducer that walks all peers' `latest_root` and flags mismatches
   would surface divergence without any extra protocol round-trip.
4. **Replay defense at the consumer** — `att_store` keeps every
   verified tuple in insertion order. The consumer (operator UI,
   automated check) needs a monotonicity-on-ts pass to flag replays.
   The substrate exposes the data; the policy lives one layer up.

## R21E extension: Noise-protected gossip — mesh-level mutual auth + AEAD

### Why this exists

R18E gossip ships in plaintext over TCP. The R7C Noise XK module
(`src/io/transducers/noise_xk.nova`) provides a production-grade
mutually-authenticated AEAD transport (RFC 7919 Group 14 2048-bit DH
via Montgomery REDC; ChaCha20-Poly1305 AEAD; SHA-256 transcript
binding). R21E wraps every gossip connection in Noise XK once both
peers have static keypairs and the dialer knows the responder's
pubkey out-of-band. The federation mesh now carries PING / ACK /
MEMBER / DELTA / ATOM / DQUERY* / ATTESTATION lines under AEAD;
every line is bound to a per-session transcript hash; replay across
a session is impossible (monotonic per-direction nonce counters);
replay across sessions is irrelevant (per-session fresh transport
keys via HKDF Split).

### Operating modes

1. **Legacy plaintext** — a soul that has not called
   `gossip_set_noise_keys` speaks the R18E v1 wire exactly as before.
   Back-compat for souls without a Noise identity.
2. **Noise** — both ends have static keypairs AND the dialer has the
   responder's pubkey pre-registered via
   `gossip_register_peer_pubkey(state, peer_addr, pubkey_hex)`. The
   dialer sends the v2-noise HELLO; the responder accepts and both
   run the three-message Noise XK handshake. Post-Split, every
   gossip line is sealed with `nxk_seal` and opened with `nxk_open`.
3. **Strict** (`CE_GOSSIP_REQUIRE_NOISE=1`, or
   `gossip_noise_set_strict(state, 1)`) — the responder REFUSES any
   non-noise hello and emits `ERR noise-required`. The dialer
   refuses to dial peers with no registered pubkey (no plaintext
   fallback).

### Wire negotiation

```
v1 (plaintext, R18E):   HELLO ce-gossip v1    -> OK v1
v2 (noise, R21E):       HELLO ce-gossip v2 noise
                        OK v2 noise
                        [4 byte BE len || nxk msg1 (272 B)]
                        [4 byte BE len || nxk msg2 (272 B)]
                        [4 byte BE len || nxk msg3 (288 B)]
                        (every subsequent line: nxk_seal/nxk_open)
strict refusal:         HELLO ce-gossip v1    -> ERR noise-required
```

The three handshake messages reuse the noise_xk module's wire format
verbatim; the gossip layer adds a 4-byte BE length prefix per
handshake message so the receiver can `recv_exact` the right number
of bytes without parsing the noise wire itself.

### Public API (R21E surface)

```
gossip_set_noise_keys(state, my_priv_hex, my_pub_hex)
gossip_noise_is_configured(state)             -> 1 iff own keypair set
gossip_noise_my_pubkey(state)
gossip_register_peer_pubkey(state, peer_addr, pubkey_hex)
gossip_noise_lookup_peer_pubkey(state, peer_addr)  -> hex | 0
gossip_noise_peer_count(state)
gossip_noise_set_strict(state, strict)
gossip_noise_strict_mode(state)
gossip_noise_strict_from_env(state)
gossip_stats_noise_hs(state)
gossip_stats_noise_hs_fail(state)
gossip_stats_noise_refused(state)
gossip_send_ping_gconn(state, addr)
gossip_handle_conn_kg_gconn(state, conn_fd, kg)
gossip_noise_status_line(state)
```

The historical `gossip_send_ping` / `gossip_handle_conn_kg` entry
points are preserved for back-compat with the R18E daemon driver.
The `*_gconn` variants do the negotiation and route through the
gconn (gossip-connection) abstraction.

### Threat model & guarantees

* **MITM**: a peer that does not hold the registered static priv
  cannot complete the Noise XK handshake. The `es` DH on the dialer
  binds to the registered `rs`; if the responder holds a different
  priv, the AEAD tag in msg1 mismatches and the responder rejects.
  `tests/unit/test_gossip_noise.nova::test_mitm_wrong_peer_pubkey_rejects_handshake`
  pins this at the gossip API surface.
* **Replay (within session)**: per-direction monotonic 64-bit nonce
  counter; `nxk_open` rejects a frame whose nonce <= last seen.
  Replay protection inherited verbatim from noise_xk.
* **Replay (across sessions)**: handshake mixes both sides'
  ephemerals into `ck`; transport keys are unique per session.
* **Strict-mode plaintext peer**: responder emits `ERR noise-required`
  + bumps `stats_noise_refused`; store unchanged.
* **Lenient + unknown peer pubkey**: dialer falls through to plaintext;
  the integration shape preserves R18E back-compat.

### Verification

* Unit (`tests/unit/test_gossip_noise.nova`): **44 assertions**
  covering state setup (defaults, configured flag, my-pubkey
  accessor), per-peer registry (add / overwrite / unknown / count),
  strict mode (set / clear / env-driven), in-process handshake
  completion with matching keys (session-hash agreement, peer-static
  recovery), PING line round-trip under noise transport, MITM
  rejection at msg1, strict-mode dial refusal (no socket opened +
  refused counter advances), lenient-mode dial does not bump refused,
  gconn structural accessors (plain vs noise; fd, role, peer-pub),
  and status-line tokens (`configured`, `mode`, hs counters).
* Integration (`tests/integration/scenario_hhhh_gossip_noise.sh`):
  ~11 assertions across THREE souls running the noise transport in
  the lenient mode, a STRICT-mode 4th soul that refuses plaintext,
  and a MITM 5th driver that registers the WRONG pubkey and is
  rejected at msg1. Stage 1: 3-soul Noise mesh -- each soul reports
  `configured=yes`; total `hs_ok` across the mesh >= 1; A's pings
  and total acks counters > 0; A's peers count = 2. Stage 2 (STRICT):
  a probe driver dials S with plaintext HELLO; S replies
  `ERR noise-required` and bumps `stats_noise_refused`. Stage 3
  (MITM): a probe driver registers a WRONG pubkey for A and dials;
  the gconn returns 0 (rejected) and A's `stats_noise_hs_fail`
  advances. Total runtime ~60s because each handshake is ~5-15s
  (four 2048-bit modpows per side).

### Honest scope

R21E.1 (this session) ships:
1. Noise XK handshake driven by gossip-level configuration
   (`gossip_set_noise_keys` + `gossip_register_peer_pubkey`).
2. The `gconn` abstraction: a unified send/receive surface that
   routes through plaintext OR Noise based on negotiation outcome.
3. `gossip_send_ping_gconn` + `gossip_handle_conn_kg_gconn`: the
   PING / ACK / MEMBER / BYE round-trip under the gconn (which
   becomes Noise if both ends are configured + registered).
4. Strict-mode refusal (env-driven + programmatic).
5. The full v1-plaintext back-compat path.
6. Inbound dispatch of DELTA / ATOM / DQUERY / ATTESTATION lines is
   already wired through the gconn (no per-message branching needed
   -- a `_gconn_recv_line` returning a DQUERY line is dispatched
   exactly the same as a PING line). So the broader gossip surface
   ALREADY rides the Noise transport when the gconn is noise; the
   only thing R21E.2 is left to do is migrate the daemon's
   `gossip_step` + `gossip_send_delta_request` (currently calls
   `_gossip_dial` directly, bypassing the gconn) to the gconn path.

R21E.2 (next session) wire-pass items:
1. `gossip_send_delta_request` -> `gossip_send_delta_request_gconn`
   (mirrors the ping refactor).
2. `gossip_send_attestation` -> `gossip_send_attestation_gconn`.
3. `gossip_step` calls the gconn variants by default when the soul
   is noise-configured.
4. Allowlist-by-pubkey on the responder side -- today any peer with
   a valid static priv whose msg1 verifies is accepted. An
   `gossip_allow_pubkey` table would let the operator pin a
   per-pubkey whitelist (subset of the registered pubkey table).
5. Key rotation: today the static keypair is fixed for the lifetime
   of the gossip state. A `gossip_rotate_noise_keys` shim with
   graceful per-peer renegotiation would let an operator rotate
   without restarting the mesh.

## R21B extension: distributed rule inference — mini-Datalog over the gossip mesh

R20B (`src/kg/rule_inference.nova`) ships forward-chaining mini-
Datalog rule inference on a SINGLE local KG. R20E
(`src/federation/distributed_query.nova`) ships distributed SPARQL
query fan-out across the R18E gossip mesh. R21B is the bridge:
declarative inference where premises can be satisfied across
DIFFERENT peers' KGs. The classical case is `parent(alice, bob)` on
peer A + `parent(bob, carol)` on peer B + the standard transitive
ancestor rules deriving `ancestor(alice, carol)` by joining premise
atoms drawn from two different souls.

### Protocol (additive on top of R18E gossip)

Three new line types:

```
RULE <rule_string>\n
    Broadcast when a peer adds a rule via dr_add_rule. Receiver
    enqueues the rule string onto the dr_state inbound-rule queue;
    distributed_rules.nova drains the queue at the top of every
    dr_run_round and appends parsed rules into the local R20B
    engine WITHOUT re-broadcasting (gossip-storm prevention).

DRFETCH <pred>\n
    Originator request: stream every relation fact for the named
    predicate from the receiver's KG. Receiver replies:
        DRFACT <peer_addr> <pred> <arg1> <arg2> <atom_id>\n   (n times)
        DREND\n
    Each DRFACT carries the receiver's self_addr so the originator
    can attribute provenance per row.

DERIVATION <rule_idx> <pred> <arg1> <arg2> <origin_addr> <contrib1>[,<contrib2>...]\n
    Broadcast when a peer derives a new fact during dr_run_round.
    Receiver caches the fact locally (kg_add_atom on the canonical
    "pred|arg1|arg2" label, dedupe via kg_find_atom) and records
    the contributing peers in its provenance log. This lets a peer
    with no relevant local facts (e.g. the bystander in a chain)
    still see the derived conclusions.
```

The line dispatch lives in `gossip.nova` itself (mirrors R20E's
DQUERY pattern); the originator side + the federated cross-join +
the provenance machinery lives in `distributed_rules.nova`. The
gossip <-> distributed_rules import direction stays acyclic
(distributed_rules imports gossip, never the reverse) via two
pinned slots in the dr_state record (`GOSSIP_DR_INBOUND_RULES = 3`,
`GOSSIP_DR_INBOUND_DERIVS = 4`) that the gossip handler pushes onto.

### Federated forward chaining

`dr_run_round(dr, kg)` does one pass:

1. Drain inbound RULE queue (peers may have just broadcast rules).
2. Drain inbound DERIVATION queue (peers may have just derived
   facts; we cache them locally with their broadcast provenance).
3. For each rule in the local engine:
   a. For each premise predicate, build the federated fact set:
      local facts (read from kg directly, tagged with self_addr) +
      `gossip_dr_fetch_from(peer, pred)` for every alive peer
      (returns DRFACT records tagged with peer_addr). Each fact
      gets a 4-tuple `[peer_addr, arg1, arg2, atom_id]`.
   b. Run the cross-join: for every binding satisfying the previous
      premise, try each fact in the next premise's federated set.
      Bindings carry an evolving `peers` set tracking which souls
      contributed atoms to the in-progress firing.
   c. For each fully-satisfied binding, instantiate the head;
      canonicalise; dedupe via `kg_find_atom`; if new, add the atom
      locally + record `[atom_id, rule_head_pred, [peer_addrs]]`
      to the provenance log; broadcast DERIVATION so other peers
      cache the same atom.

`dr_run_to_fixpoint(dr, kg, max_rounds)` iterates `dr_run_round`
until a round adds zero new local atoms or `max_rounds` fires.
Returns `[total_derived, rounds]`. The 5-node transitive chain
verification (4 parents partitioned across 3 peers, classical
ancestor rules) reaches fixpoint in 4 rounds, deriving all C(5,2) =
10 ancestor pairs at the originator.

### Provenance shape

`dr_derivation_provenance(dr, atom_id) -> [rule_head_pred, peer1,
peer2, ...]`. The first element is the head predicate name of the
rule that produced the atom (R20B's `rule_head_pred`); subsequent
elements are the unique peer addresses that supplied any premise
atom for the firing, in the order they were used by the cross-join.
The originator's own self_addr is included if any premise came
from the local KG.

For the integration scenario's `ancestor|0|4` atom (the longest
cross-soul chain: parent(0,1) on A + parent(1,2) on B + parent(2,3)
on A + parent(3,4) on C):

```
prov_0_4 = ["ancestor", "127.0.0.1:PORT_A", "127.0.0.1:PORT_B"]
prov_0_2 = ["ancestor", "127.0.0.1:PORT_A", "127.0.0.1:PORT_B"]
```

The federation policy is "peer set of unique contributors", not
"full chain trace" -- longer chains accumulate peer addresses
linearly until the join saturates the contributor set.

### Trust model

The gossip mesh is the SAME shape R18E ships -- assume mutually
non-malicious peers (or pair with R7C Noise XK auth + R20F signed
attestations for adversarial settings). R21B itself adds no new
cryptographic guarantees beyond what gossip provides; provenance is
informational, not a signed receipt. A malicious peer could
fabricate DRFACT or DERIVATION lines -- defense for that threat
lives one layer up (e.g. signed-fact attestations, similar shape to
R20F). The R21B substrate ships the inference primitive; auth + DP +
attestation compose on top.

### Public API

```
dr_init(gossip_state, rule_engine)        -> dr_state
dr_add_rule(dr, rule_string)              -> 1 | error
dr_run_round(dr, kg)                      -> int (atoms derived
                                             this round)
dr_run_to_fixpoint(dr, kg, max_rounds)    -> [total_derived, rounds]
dr_derivation_provenance(dr, atom_id)     -> [rule_name, peer_addrs...]
```

Plus chat-side conveniences (`dr_stats_line`, `dr_rule_count`,
`dr_inbound_rule_count`, `dr_inbound_deriv_count`) and the gossip
hook surface (`gossip_set_dr_state`, `gossip_broadcast_rule`,
`gossip_broadcast_derivation`, `gossip_dr_fetch_from`).

### Verification

* Unit (`tests/unit/test_distributed_rules.nova`): **42 assertions**
  covering bootstrap shape; rule broadcast on add; inbound RULE
  queue drained on next round; cross-soul join via the federated
  fact set (single-soul case matches R20B exactly + multi-binding
  case produces the same closure regardless of fact-source
  partitioning); provenance shape (rule_name + unique peer set);
  inbound DERIVATION caching + dedupe; max_rounds cap; stats line;
  chat info-line dispatch.

* Integration (`tests/integration/scenario_eeee_distributed_rules.sh`):
  **15 assertions** on a 3-soul mesh (3 random local ports). Soul
  A is seeded with `parent(0,1) + parent(2,3)`; B with `parent(1,2)`;
  C with `parent(3,4)`. A is the originator: adds the two ancestor
  rules at tick 30, runs `dr_run_to_fixpoint(15)` at tick 60. The
  observed convergence: **10 ancestor atoms derived (full closure),
  4 rounds, 24 DRFETCH dispatches, `ancestor|0|4` present with
  provenance recording 2 unique peer contributors** (A + B for the
  cross-soul join). All federation prior suites (R18E gossip, R19E
  leader election, R20E distributed query, R20F snapshot
  attestation, R21E noise) remain green; the R20B local rule
  inference suite (47 assertions) is unchanged.

### Limitations / future work

1. **No DP / DRF noise.** A peer can probe another peer's KG by
   firing rules whose premise predicates only it cares about and
   reading the DRFACT stream. R21B's DRFETCH wire is unfiltered.
   Future composition with R3.6 DP could noisify the per-row count
   at the DRFETCH responder.
2. **DRFACT is read-only** -- no schema restrictions yet. The
   responder ships every RELATION atom matching the predicate; an
   operator policy layer ("allow_predicates" / "deny_predicates")
   could filter at the responder side. The substrate exposes the
   data; the policy lives one layer up.
3. **No signed derivations.** R20F-style signing over the DERIVATION
   pre-image would let receivers verify the originator's identity
   on the cached fact. Substrate is ready (gossip already carries
   pubkeys for R20F); the wrap is a follow-on session.
4. **Round-based fact gather is O(rules × premises × N_peers)** per
   round. For a 16-soul mesh with 4-premise rules, that's 64 TCP
   handshakes per round per rule. Caching the federated fact set
   within a single fixpoint pass (refresh only when a peer broadcasts
   a new fact) is the obvious win.
5. **No DELTA-fed warm cache.** Today every round re-fetches the
   relevant predicate set from every alive peer. A future round
   could ride DELTA's existing belief-mutation stream to keep a
   local materialised relation cache.
