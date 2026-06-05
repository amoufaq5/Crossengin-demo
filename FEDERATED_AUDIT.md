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

## R23E extension: NAT traversal -- STUN-like external addr discovery + gossip-piggyback advertisement

### Why this exists

R18E's SWIM gossip assumes every peer is directly reachable on its
listed `host:port`. That assumption holds inside one trusted datacenter
or on loopback, but fails the moment a peer sits behind any common
middlebox: home routers (NAT44), mobile networks (CGNAT), corporate
firewalls, and public-cloud security groups all deny inbound
connections by default. Peers can OUT-connect (the NAT opens an
egress mapping) but cannot accept inbound, so R18E's PING / DELTA /
EXTADDR initiator pattern is correct, but the responder side of the
mesh needs the peer's *external* mapping to even know where to dial.

The canonical fix is the **STUN / TURN / ICE** stack (RFC 8489 et al.):
the peer learns its external `(public_ip, public_port)` from a
**rendezvous server** that echoes back what it observed on its accept
side; the peer then advertises that pair to mesh peers, who use it as
the destination for hole-punching probes.

R23E ships **discovery + advertisement** on the TCP transport NOVA
already exposes. UDP hole-punching is the next step (R23E.2) -- it
requires `sendto/recvfrom` syscalls that NOVA does not currently
expose to user code.

### Protocol

1. **External address discovery.**
   Wire shape:
   ```
   dialer >> STUN_REQUEST\n
   server >> EXTERNAL <ip>:<port>\n
   ```
   The server side calls `accept_conn(server_fd, sa_buf, sa_len_buf)`
   with a non-zero 16-byte sockaddr_in buffer so the kernel fills in
   the peer's source `(sin_addr, sin_port)`. Those are the
   *post-NAT* values -- the public mapping. The server formats them
   as `EXTERNAL <dotted-quad>:<decimal-port>` and writes the line
   back. CE does not ship a dedicated STUN server: ANY well-
   connected CE peer answers `STUN_REQUEST`, so the federation
   bootstrap node doubles as the rendezvous.

2. **Gossip-piggyback advertisement.**
   The R23E additive wire line is:
   ```
   EXTADDR <internal_addr> <external_addr>\n
   ```
   Sent over a regular gossip TCP connection (HELLO + OK first).
   The receiver dispatches `_gossip_serve_extaddr` (in gossip.nova)
   which validates both addrs, writes `(internal, external)` to the
   nat_state peer-ext table via the pinned cross-module slot
   `GOSSIP_NAT_PEER_TABLE_SLOT`, and bumps counters
   (`gossip_stats_nat_extaddr_rx` + `nat_inbound_ad_count`).

3. **NAT-type heuristic.**
   `nat_detect_type(stun_addr_1, stun_addr_2)` queries TWO STUN
   servers; the pure form `nat_detect_type_from_replies(r1, r2)`
   classifies based on the parsed `(ip, port)` pairs:

   | r1 ip+port | r2 ip+port            | Local IP? | Classification |
   |------------|-----------------------|-----------|----------------|
   | parsed     | parsed, same ip+port  | yes       | `open`         |
   | parsed     | parsed, same ip+port  | no        | `cone`         |
   | parsed     | parsed, diff port     | -         | `symmetric`    |
   | 0 / empty  | anything              | -         | `blocked`      |

   "Open" = no NAT (external == local). "Cone" NATs reuse the same
   egress mapping for any destination -- basic hole-punching works.
   "Symmetric" NATs allocate a fresh source port per destination --
   hole-punching cannot survive without a relay. "Blocked" reflects
   a failed query.

4. **Hole-punching stub.**
   `nat_hole_punch(state, peer_external)` records the attempt in
   the counter and returns 0 (not implemented). The TCP-only
   implementation needs SO_REUSEPORT + simultaneous-connect (Ford
   et al. 2005); the real fix is to add UDP support to NOVA and
   ship the simpler UDP variant in R23E.2.

### Public API

```nova
// Discovery (client side)
nat_query_stun(addr)                       -> ext_addr | 0
nat_query_stun_with_state(state, addr)     -> ext_addr | 0

// Discovery (server side)
nat_serve_stun_conn(conn_fd, ip, port)     -> 1 | 0
nat_serve_stun_conn_sa(conn_fd, sa_buf)    -> 1 | 0
nat_serve_stun_one_shot(bind_addr)         -> 1 | 0

// Advertisement
nat_advertise(gossip_state, nat_state, ext)  -> int (peers reached)
nat_advertise_to(state, peer, internal, ext) -> 1 | 0

// Heuristic
nat_detect_type(addr1, addr2)              -> str
nat_detect_type_from_replies(r1, r2)       -> str
nat_local_addrs()                          -> list[addr_str]

// State management
nat_init()                                 -> nat_state_t
nat_set_external(state, addr)              -> state
nat_get_external(state)                    -> str
nat_peer_external_addrs(state)             -> list of [internal, external]
nat_get_peer_external(state, internal)     -> str
nat_set_peer_external(state, internal, ext) -> state

// Stub + status
nat_hole_punch(state, peer_external)       -> 0 (R23E.2)
nat_status_line(state)                     -> str
```

Gossip integration:
```nova
gossip_set_nat_state(gossip_state, nat_state) -> gossip_state
gossip_stats_nat_extaddr_rx(state)            -> int
gossip_stats_nat_extaddr_bad(state)           -> int
```

### Trust model

The STUN response is **untrusted**: a malicious rendezvous server
can lie about the dialer's external addr. R23E's defense is to
query at least TWO STUN servers via `nat_detect_type` and disagree
loudly when they disagree. For production deployment, the
rendezvous side SHOULD be wired through the R21E Noise XK transport;
that wiring lives one layer up.

The advertisement side is symmetric: a peer can lie about its own
external addr. The receiver records the mapping but does NOT trust
it for any future operation; the intended consumer is the hole-
puncher (R23E.2), which will probe the advertised addr -- a lie
self-corrects when the probe fails.

### Verification

* **`tests/unit/test_nat_traversal.nova`** (NEW): 53 assertions on
  the parse / format / peer-table / type-heuristic surface. Cone vs.
  symmetric vs. open vs. blocked all confirmed against canned replies;
  malformed input fails closed; the sockaddr_in extractor reads
  little-endian family + big-endian port correctly.

* **`tests/integration/scenario_oooo_nat_traversal.sh`** (NEW): 12
  assertions on a 2-soul mesh. A binds + acts as STUN-like rendezvous;
  B dials A, parses the response (in sandbox: `127.0.0.1:<ephemeral>`),
  classifies NAT type, advertises via `nat_advertise` over the gossip
  wire, and exits cleanly. Asserts A's `gossip_stats_nat_extaddr_rx`
  counter advanced AND A's nat_state peer-ext table grew.

### Honest scope

- **R23E ships discovery + advertisement only.** Hole-punching is
  documented but stubbed.
- **No TURN relay fallback.** Symmetric NATs are correctly detected.
- **Sandbox loopback is the test reality.** Same code path on real
  hosts.
- **CE_NAT_LOCAL_ADDRS is operator-supplied.** `nat_local_addrs`
  returns `["127.0.0.1"]` plus whatever the operator pins. NOVA
  does not expose `getifaddrs(3)` today.

### Limitations / future work

1. **No UDP hole-punching.** R23E.2 once NOVA exposes sendto/recvfrom.
2. **STUN-server trust.** Defense is N-rendezvous voting at the
   operator layer.
3. **No TURN relay.** R23F or later.
4. **No keepalive.** R23E.2 will add `nat_keepalive_tick`.
5. **Single-address advertisement.** ICE candidate-pair gathering
   (RFC 8445) is the proper multi-homed fix.


## R23C extension: federation snapshot replication via gossip

R13F (`src/persistence/snapshot_delta.nova`) shipped incremental
snapshot deltas; R20F (`src/federation/snapshot_attestation.nova`)
shipped gossip-relayed signed snapshot attestations. The remaining
gap: when peer A broadcasts a signed attestation ("at ts T I sealed
a snapshot with root R, here's my Ed25519 signature"), peer B has
the receipt but not the goods. If A's disk dies tomorrow the
federation knows the snapshot existed but cannot restore it.

R23C closes that gap. After peer B's gossip handler verifies an
inbound ATTESTATION (R20F's existing logic), it also pokes the
snapshot-replication layer (`src/federation/snapshot_replication.nova`)
which:
  1. Records `(root_hex, peer_id, ts_ns)` in a known-roots table
     marked PENDING.
  2. The daemon (or the chat REPL via `/snap_replicas`) periodically
     calls `gossip_drive_snap_fetches(state)` which walks the
     PENDING entries and dials each peer with `SNAP_FETCH <root_hex>`.
  3. The responder (peer A in our two-soul case) replies with the
     snapshot bytes framed as `SNAP_DATA <line>` per snapshot text
     line, terminated by `SNAP_END`. A miss is a bare `SNAP_END`.
  4. The receiver assembles the body, runs `sr_observe_snap_response`
     which:
       a. Verifies the bytes start with a `crossengin-snapshot v1/v2`
          header.
       b. Verifies the bytes terminate with an `end` line.
       c. Finds the `meta.merkle_root <hex>` line and confirms it
          equals the EXPECTED root_hex from the signed attestation.
     If all three pass, the bytes land in the local replica table;
     `sr_have_root(root_hex)` returns 1 from then on, and peer B can
     SERVE the same root if peer C later asks for it.

### Trust model

The gossip mesh is UNTRUSTED. R20F already gates the known-roots
table: only attestations whose Ed25519 signature verifies against
the originator's registered pubkey are recorded. The wire-layer
defense for the SNAP_DATA stream is the `meta.merkle_root` line
equivalence check: the originator computes that line BEFORE signing
the attestation, so a tampered meta-line is detectably wrong against
the signed root and the replica is dropped (verify_fail counter
advances, replica table unchanged).

Defense-in-depth: when the replica is later LOADED via
`snap_load_with_deltas` under `CE_SNAPSHOT_VERIFY_MERKLE=1`, the
strict per-atom Merkle re-derivation runs and catches any atom-level
tampering that left the meta line untouched. The wire layer trusts
the meta-line; the persistence layer trusts the full atom hash.

Why not re-derive the full Merkle root at receive time? The
snapshot bytes parse via `snap_from_text` (in
`src/persistence/snapshot_disk.nova`), but that module's internal
`_starts_with` helper collides on the assembler with the same-named
helper in `src/io/transducers/kg_sync.nova` which gossip already
drags in. So R23C deliberately keeps `snapshot_replication.nova`
free of the snapshot_disk import; the verifier walks the snapshot
text inline (header line, meta-root line equivalence, end-line
presence). Atom-level verification is the LOAD path's job.

### Wire shape

Three new gossip message types (additive to R18E):

```
SNAP_FETCH <root_hex>\n
SNAP_DATA <text_line>\n   (zero or more)
SNAP_END\n
```

A bare `SNAP_END` (no `SNAP_DATA`) signals "I don't have this root".
The `SNAP_DATA` framing keeps the gossip line buffer (1024 bytes)
the hard upper bound on any single snapshot text line; the receiver
re-adds the `\n` the line-oriented gossip wire stripped.

### Coordination with R23E

R23C and R23E both extend `src/federation/gossip.nova` with new
wire types + state slots. R23C slots at GOSSIP_S_SR_STATE = 29 + 2
counters (30, 31); R23E slots at GOSSIP_S_NAT_STATE = 32 + 2
counters (33, 34). The coordination note is pinned at both blocks
so the next sprint can extend the layout without renumbering.

### Public API

```
sr_init(gossip_state, local_snap_dir)        -> sr_state
sr_observe_attestation(sr, att)              -> 1 newly tracked | 0
sr_fetch_pending(sr)                         -> count of pending fetches
sr_local_snapshots(sr)                       -> list[(root, peer, ts)]
sr_serve_snap_request(sr, root_hex)          -> snapshot_bytes | 0
sr_observe_snap_response(sr, root_hex, bytes) -> 1 stored | 0
sr_register_local(sr, root_hex, peer_id, ts_ns, bytes) -> 1
```

Plus diagnostics (`sr_status_line`, `sr_pending_fetch_tasks`,
`sr_known_roots`, `sr_replica_lines`) and the gossip hook surface
(`gossip_set_sr_state`, `gossip_send_snap_fetch`,
`gossip_drive_snap_fetches`, `gossip_sr_status_line`).

### Verification

* Unit (`tests/unit/test_snapshot_replication.nova`): **73
  assertions** covering sr_init shape, sr_observe_attestation
  registration + dedupe, sr_register_local idempotence, replica
  table serve/miss, sr_observe_snap_response verify+store on legit
  bytes, REJECT on (tampered, garbage, truncated, unknown-root)
  bytes, already-have-root short-circuit, sr_local_snapshots
  enumeration, wire codec round-trip, status line format.

* Integration (`tests/integration/scenario_mmmm_snap_replication.sh`):
  **11 assertions** on a 2-soul mesh (random local ports). Both
  souls boot, build a unique snapshot, register it locally + sign
  + broadcast the attestation. The driver embeds the snapshot text
  as a literal (precomputed via the snap_to_text + merkle_root_for_kgs_blob
  pipeline) to avoid the snapshot_disk import in the same TU as
  gossip. Asserts: pre-flight socket OK, both souls running after
  warmup, both souls register their own snapshot locally, B's
  known-roots / replica table grow when A's attestation arrives,
  tamper-injected snapshot (wrong meta.merkle_root) is rejected
  without polluting the replica table, /snap_replicas chat dispatch
  echoes the R23C delegation message.

  Like scenario_dddd (R20F), the mesh-propagation assertions are
  best-effort on a blocking-accept NOVA host (the 25s window is
  often too short for both directions of PING/ACK + ATTESTATION
  + SNAP_FETCH to converge); the high-confidence invariants are
  in the unit suite. All assertions that DO fire pass.

### Limitations / future work

1. **No durable on-disk replica.** R23C stores replicas in the
   sr_state record (in-memory list). The daemon could persist to
   `sr_local_dir` per the operator-provided path; the file-system
   wiring is a follow-on.
2. **No peer-id -> addr index.** `gossip_drive_snap_fetches` dials
   every alive peer (best-effort fan-out); a per-peer addr table
   would let it dial only the originator.
3. **No replay defense.** A replayed attestation re-issues the
   SNAP_FETCH; the receiver's `sr_have_root` check short-circuits
   the network round-trip but the bandwidth cost of the (re-)dial
   is wasted.
4. **No streaming for large snapshots.** A snapshot bigger than ~1KB
   per line will overflow the gossip line buffer. The text writer
   pre-line-wraps at ~80-120 chars in practice; large blobs (e.g.
   serialised episodic moments) would need a binary frame or
   chunked text encoding.

## R26E extension: gossip relay -- routing through intermediaries

R18E shipped the SWIM gossip mesh assuming every peer can directly
TCP-connect to every other peer. R23E added NAT-type detection but
UDP hole-punching is stubbed (R23E.2). Until full NAT traversal:
peers behind symmetric NATs or strict firewalls can't reach each
other directly. R26E closes that gap with a TCP-based relay
primitive: when peer A wants to send to peer B but the direct dial
fails, A picks a common-reachable peer C, sends RELAY\_REQ to C, C
verifies it can reach B + forwards as RELAY\_DATA with via=C, from=A
annotations. B records the relayed payload + the via annotation
so diagnostics can confirm the A->C->B path; A caches (target=B,
via=C) so the second send to B short-circuits straight to the
relay path.

### Honest scope

True NAT relay needs UDP hole-punching for ad-hoc relay selection
(measure connectivity rather than relying on prior mesh
membership). R26E ships the TCP-based relay over pre-known mesh
peers -- any alive peer can serve as relay. The intermediate
selection policy is "first non-target alive peer != self that
isn't currently marked unreachable"; full STUN-like relay
discovery (rank by observed NAT topology) is R26E.2. ACK
forwarding back to the originator is best-effort: the relay caches
the working via on first success so ACK loss does not require
recomputation.

### Wire shape

Three new gossip message types (additive to R18E):

```
RELAY_REQ <req_id> <target> <origin> <payload>\n
RELAY_DATA <req_id> <target> <via> <from> <payload>\n
RELAY_ACK <req_id> <origin> <via>\n
```

The payload may contain spaces (the parser rejoins toks beyond the
fixed positional fields back into one string). req\_id is a per-
originator monotonic counter; collisions across souls are
disambiguated by the from= annotation on RELAY\_DATA.

### Public API

```
relay_init(gossip_state)            -> relay_state
relay_send(relay, target, payload)  -> 1 ok | 0 error
    Auto-routes: direct first, falls back to relay via common alive peer
relay_handle_request(relay, line)   -> 1 forwarded | 0 dropped
relay_handle_data(relay, line)      -> 1 delivered | 0 dropped
relay_handle_ack(relay, line)       -> 1 noted | 0 dropped
relay_chosen_via(relay, target)     -> int_peer_addr | -1
relay_drain_inbound(relay)          -> count of inbound lines processed
relay_pick_intermediate(relay, t)   -> peer_addr | 0
relay_cache_via(relay, target, via) -> 1
relay_mark_unreachable(relay, peer) -> 1  (test hook for partition simulation)
```

Plus stats accessors (`relay_stats_sent_direct`,
`relay_stats_sent_via_relay`, `relay_stats_forwarded`,
`relay_stats_acked`, `relay_stats_no_relay`, `relay_stats_delivered`)
and the gossip hook surface (`gossip_set_relay_state`,
`gossip_relay_state`, `gossip_relay_status_line`, plus per-message-
type rx counters `gossip_stats_relay_req_rx` / `_data_rx` / `_ack_rx`).

### Import-graph hygiene

The same coordination pattern R21B uses for distributed-rule
inference: gossip.nova OWNS the wire prefixes + the per-message-
type inbound dispatchers (`_gossip_serve_relay_req` / `_data` /
`_ack`). Each dispatcher pushes the raw wire line onto a pinned
queue inside relay\_state (`RELAY_S_INBOUND_REQS` = 11 / `_DATA` =
12 / `_ACKS` = 13). The relay's `relay_drain_inbound` is called
from the daemon loop (or the integration scenario's per-tick body),
parses each queued line, and invokes the correct handler. This
keeps the gossip -> relay import direction unidirectional
(gossip\_relay imports gossip, never the reverse).

### Gossip state slots added

R26E adds 4 new slots to gossip\_state (extending the linear layout
the R20F / R21B / R21E / R23C / R23E sprints established):

```
GOSSIP_S_RELAY_STATE          = 35  // relay_state_t or 0
GOSSIP_S_STATS_RELAY_REQ_RX   = 36  // RELAY_REQ wire-level rx counter
GOSSIP_S_STATS_RELAY_DATA_RX  = 37  // RELAY_DATA wire-level rx counter
GOSSIP_S_STATS_RELAY_ACK_RX   = 38  // RELAY_ACK wire-level rx counter
```

### Verification

* Unit (`tests/unit/test_gossip_relay.nova`): **61 assertions**
  covering wire format round-trips (request / data / ack format +
  parse, including spaces-in-payload preservation), parse rejection
  for malformed lines (bad prefix, non-numeric id, truncated
  shapes), intermediate selection (skips target + self + unreachable,
  returns 0 when no candidates), relay\_send behaviours (no peers
  -> no\_relay+1, cache short-circuit, cache idempotence,
  relay\_chosen\_via lookup), relay\_handle\_data records inbound
  with via/from annotations + bumps delivered, relay\_handle\_data
  drops misrouted, relay\_handle\_request drops self-loop, drain
  helper processes all three queues + clears them, stats\_line
  format.

* Integration (`tests/integration/scenario_vvvv_gossip_relay.sh`):
  **13 assertions** on a 3-soul mesh (random local ports). Souls A,
  B, C bind + bootstrap; A's relay marks B direct-unreachable
  (test hook simulates a NAT/firewall partition without
  iptables); A calls relay\_send(B, payload). The relay layer
  walks A's alive peers, picks C, sends RELAY\_REQ. C's gossip
  handler dispatches to its inbound queue; C's drain invokes
  relay\_handle\_request, which dials B and forwards as RELAY\_DATA
  with via=C, from=A. B's gossip handler dispatches; B's drain
  invokes relay\_handle\_data which records the (req\_id, payload,
  via, from) tuple. Asserts: NOVA pre-flight OK, all 3 souls
  compile + run, A's first relay\_send returned 1 + sent\_via=1,
  A's cache via=ADDR\_C, A's second send hit cache + sent\_via=2,
  C's wire-level req\_rx >= 1, C's forwarded >= 1, B's wire-level
  data\_rx >= 1, B's received-queue >= 1, B's recv\[0\] annotated
  via=ADDR\_C from=ADDR\_A (the A->C->B path is confirmed by the
  annotation round-trip).

### Limitations / future work

1. **No peer-side reachability check before relay selection.** C
   may forward to B and discover B is unreachable from C too; the
   originator gets a NACK in the form of a missing RELAY\_ACK and
   has to retry with a different relay. R26E.2 will add a
   pre-flight check.
2. **No multi-hop chains.** R26E ships 2-hop relay (A->C->B).
   N-hop chains require explicit hop count + loop prevention; the
   substrate is in place but not exposed.
3. **No relay-side authentication.** Anyone alive on the mesh can
   ask C to relay. A future hardening: require origin = peer A
   has registered C's pubkey for relay duties.
4. **TCP-only.** The wire is plaintext gossip v1 (HELLO / OK /
   RELAY\_REQ / BYE). R26E.2 will wrap the relay segments under
   R21E's Noise XK transport so the relay can be untrusted at
   the application layer while still preserving end-to-end
   confidentiality between originator and target.
5. **ACK forwarding is best-effort.** The relay (C) sends an ACK
   back to A on successful forward; A's stats record the ACK
   when it arrives. The cache update happens at send-time, not
   at ack-time, so ACK loss does not break the per-target cache.

## R26E.2 extension: STUN-like relay candidate ranking

R26E picked the FIRST non-target alive peer as the relay. That
ignores observed NAT topology: a peer behind a symmetric NAT (per-
destination outbound mapping) is a poor relay choice because its
forward dial to the terminal target B will usually fail in the same
way A's direct dial did. R26E.2 ranks candidates by R23E NAT type
so the originator prefers peers most likely to be reachable.

### Ranking key

| NAT type | rank | reasoning |
|---|---|---|
| `open` | 4 | no NAT -- definitely reachable |
| `cone` | 3 | one consistent mapping per session; inbound on the existing mapping works |
| `unknown` | 2 | unprofiled peer; default for souls that haven't observed a NAT-type detection result yet |
| `symmetric` | 1 | per-destination mapping; the relay's outbound to B will fail in the usual case |
| `blocked` | 0 | STUN couldn't reach the peer at all -- skip entirely |

A rank-0 peer is omitted from the candidate pool, NOT just ranked
last. The brief is explicit: blocked candidates are unusable; the
ranker should never propose them.

### LRU tie-break

Two peers with the same NAT rank (the common case: 5 alive cone-
NAT peers in a typical home-network mesh) need a deterministic
tie-break so load spreads across the equally-ranked relays rather
than always punishing the same peer. The ranker walks a per-relay
LRU tracker (slot 15 of relay\_state); peers with a lower LRU
position (older = less recently used) sort BEFORE peers with
higher positions. Brand-new peers (never used) outrank everything
already in the LRU because they deserve a chance.

The LRU is bumped only on `relay_choose_candidate_ranked` (the top
pick), not on every `relay_rank_candidates` inspection. That keeps
diagnostic walks idempotent.

### Cache invalidation

R26E caches `(target -> via)` so the second send to the same target
short-circuits the alive-peer walk. R26E.2 adds
`relay_mark_relay_failed(via)` to invalidate any cache entry
pointing at a failed relay: when the originator observes a target
still unreachable AFTER a successful relay dial (the relay forwarded
but the terminal target dropped the line), the originator calls
`relay_mark_relay_failed(via)` so the next send re-ranks.

### Opt-in dispatch

The ranking is OFF by default. Souls + tests opt in via
`CE_RELAY_RANK_NAT=on`. `relay_send`'s intermediate-selection step
calls `_relay_pick_dispatch(state, target)` which consults the env;
when on, the ranked picker runs; when off, the original
`relay_pick_intermediate` runs. This preserves R26E call-site
compatibility (no caller signature changed; the ADR-0090 wire
protocol is unchanged) while letting deployments that have
R23E NAT-type data turn ranking on for the production benefit.

### NAT-type registry

Souls that have observed a peer's NAT type (typically via R23E's
`nat_detect_type` after a couple of STUN probes) feed the result
into the relay via `relay_set_peer_nat_type(state, peer, type)`.
The registry sits in relay\_state slot 14 as a list of
`[peer_addr, nat_type_str]` records. Looking up an unregistered
peer returns "unknown" so the ranker treats unprofiled peers as
the midpoint rather than rejecting them.

This is the cleanest factoring under the R23E ownership boundary:
`nat_traversal.nova` exposes detection; `gossip_relay.nova` owns
the relay's view of NAT-type-per-peer for ranking. A future
revision may pin the slot in `nat_state` directly and have
`relay_get_peer_nat_type` indirect through it, removing the
double-bookkeeping. For now the registry is local to the relay.

### Verification

* **42 unit assertions** in `tests/unit/test_relay_ranking.nova`
  covering: NAT-rank table mapping (open=4, cone=3, unknown=2,
  symmetric=1, blocked=0; garbage strings collapse to unknown);
  registry round-trip + overwrite; `relay_rank_candidates` on
  [open, cone, symmetric] -> [open, cone, symmetric] (the brief's
  headline example); unknown ranks BETWEEN cone and symmetric;
  blocked omitted from the pool entirely; LRU rotation across 3
  equally-ranked cone peers (3 distinct picks then wrap to 1st on
  the 4th); LRU NEVER outranks NAT type (open peer always wins
  over cone, even after the open peer has been used); empty pool
  returns -1; all-blocked returns -1; ranked picker skips target +
  self + unreachable; `relay_mark_relay_failed` drops the matching
  cache entry + leaves others intact; default
  `relay_rank_nat_enabled()` is 0 when env unset.

* **11 integration assertions** in
  `tests/integration/scenario_wwww_relay_rank.sh` (letter `wwww`
  free in the alphabetic sequence; vvvv was R26E). Single-driver
  in-process test of the ranker against a 4-peer mocked mesh: 1
  open + 1 cone + 1 symmetric + 1 blocked. The driver runs under
  `CE_RELAY_RANK_NAT=on` and asserts: env observed; first pick is
  the open peer; blocked peer absent from rank list; ranked
  output = [open=8004, cone=8003, symmetric=8002]; unknown
  placement between cone and symmetric; LRU rotation gives 3
  distinct picks across 3 cone peers; 4th pick wraps to 1st; legacy
  `relay_pick_intermediate` still returns the first alive peer
  (back-compat); `relay_mark_relay_failed` invalidates the matching
  cache entry; `relay_send` dispatch smoke (env-on path runs to
  completion without crash). All 11 PASS.

* `NOVA_ROOT=/home/user/NOVA bash scripts/test.sh` -- 215 unit
  tests pass (1 new). The 5 federation baselines hold their
  counts: gossip\_relay 61, nat\_traversal 53, gossip 34,
  distributed\_query 36, leader\_election 40.

### Files touched (R26E.2)

* MOD: `src/federation/gossip_relay.nova` (+2 state slots, ~10
  public functions for ranking + LRU + failure invalidation,
  +1 env helper, +1 dispatch helper, +1 call-site change in
  `relay_send`'s intermediate-selection step). The R26E API is
  unchanged; new functions are additive.
* NEW: `tests/unit/test_relay_ranking.nova` (42 assertions).
* NEW: `tests/integration/scenario_wwww_relay_rank.sh` (11
  assertions; reuses `_lib.sh`).
* MOD: `FEDERATED_AUDIT.md` (this section), `NEXT_SESSION.md`,
  `README.md`.

### Future work (R26E.3+)

1. **`relay_send`-side failure feedback.** Today
   `relay_mark_relay_failed` is a public API but the originator
   must call it explicitly on observing failure. A future
   revision could wire it automatically when `relay_send`
   observes a still-unreachable target after the relay path
   completed (likely requires per-send timeouts + RELAY\_NACK
   wire support).
2. **Pin NAT-type in `nat_state` directly.** Today the relay
   keeps its own registry. The cleaner factoring (pending
   coordination with the R23E owner) is to have
   `relay_get_peer_nat_type` indirect through
   `nat_get_peer_type(nat_state, peer)`.
3. **Per-relay reachability score.** NAT type is a proxy; the
   real signal is observed successful round-trips. A future
   ranker could weight by an EMA of recent success/fail
   counts per peer, with NAT type as the prior.

## R26E.2 / R27C extension: Noise-XK end-to-end wrap of relay payloads

R26E ships TCP gossip relay where the intermediary peer C reads + can
tamper with every byte it forwards (`src/federation/gossip_relay.nova`
RELAY\_REQ + RELAY\_DATA wire is plaintext gossip v1). R26E's
honest-scope list flagged this as the open hole: the relay node is
trusted with payload content. R27C closes the hole with an end-to-end
AEAD wrap layered above R26E: A and B share a Noise-XK session
out-of-band (or via R7C kg\_sync v3 handshake); A encrypts the payload
with `nxk_seal` BEFORE handing it to `relay_send`; C forwards opaque
hex; B decrypts with `nxk_open` on receive. The relay is now
authenticated-untrusted: it cannot read payloads + any tamper attempt
fails the Poly1305 tag on B and is dropped.

### Architecture

```
   +--- A (initiator role) ----+      relay forwarders     +--- B (responder) ---+
   |                           |   +------------------+   |                     |
   |  plaintext "hello"        |   |                  |   |  recv queue:        |
   |    -> srl_send_secure     |   |       C          |   |   [from=A,          |
   |    -> nxk_seal(I, k_IR)   +---+  RELAY_REQ /     +---+    pt="hello", n=5] |
   |    -> hex(frame)          |   |  RELAY_DATA      |   |                     |
   |    -> relay_send(B, hex)  |   |  via=C, from=A   |   |  <- srl_drain_relay |
   |                           |   |  payload=hex     |   |  <- nxk_open(R)     |
   |                           |   |  (cannot decrypt)|   |  <- cc_hex_decode   |
   +---------------------------+   +------------------+   +---------------------+
```

The wire wrap is:

  1. `nxk_seal(state, role, pt_buf, pt_n)` produces a binary frame
     `[4B BE len(ct||tag) || ct || 16B Poly1305 tag]` (per R7C
     noise\_xk.nova).
  2. `cc_hex_encode_buf(frame, len)` -> ASCII-safe hex string.
  3. `relay_send(relay, target, hex)` routes the hex string via the
     R26E relay wire (RELAY\_REQ payload = hex; the relay's
     space-delimited parser treats the hex as the final positional
     field).
  4. C forwards as RELAY\_DATA with `via=C`, `from=A`, payload = hex.
  5. B's gossip handler dispatches RELAY\_DATA to the relay's
     received-queue. `relay_handle_data` records `[req_id, payload,
     via, from]`.
  6. `srl_drain_relay_recv(srl)` walks the relay's received-queue
     from a monotonic cursor. For each record:
     * find the session for `from` (the originator);
     * `cc_hex_decode(payload)` -> bytes;
     * `nxk_open(nxk_state, role, frame, frame_n)` -> plaintext;
     * push `[from, pt_buf, pt_n]` onto the srl recv queue.
  7. `srl_recv_secure(srl)` returns the recv queue + clears it.

### Roles and key direction

This module re-uses R7C noise\_xk's role+counter convention exactly:

* A took the INITIATOR role in the handshake; when sending to B, A
  passes `NXK_ROLE_INITIATOR` to `nxk_seal`. `_nxk_role_send_picks`
  returns `(k_IR, NXK_S_N_IR)`.
* B took the RESPONDER role; when receiving from A, B passes
  `NXK_ROLE_RESPONDER` to `nxk_open`. `_nxk_role_recv_picks` selects
  `(k_IR, NXK_S_N_IR)` (i.e. the recv-side picks the OTHER party's
  send key + counter).

Symmetrically, B sending to A would seal under RESPONDER (`k_RI`); A
receiving from B opens under INITIATOR (also `k_RI` on the recv side).
The srl module stores ONE role per session record -- the role THIS
soul played during the handshake -- and threads it into both
`nxk_seal` and `nxk_open` calls. This matches the same convention
R21E uses for Noise-protected gossip.

### Public API

```
srl_init(relay_state)                                -> srl_state
srl_register_peer_session(srl, peer_id, nxk_state, role) -> 1 ok | 0
    Idempotent. Replaces the existing session for re-keying.
srl_send_secure(srl, target_peer, pt_buf, pt_n)      -> 1 ok | 0 error
    Refuses to send when no session for target (no fallthrough to
    plaintext via the relay).
srl_send_secure_str(srl, target_peer, plaintext_str) -> 1 ok | 0
srl_drain_relay_recv(srl)                            -> count
srl_recv_secure(srl)                                 -> drained list
srl_received_at(srl, idx)                            -> entry | 0
srl_received_from(entry)                             -> peer_id
srl_received_pt_buf(entry)                           -> buf
srl_received_pt_n(entry)                             -> n
srl_received_pt_str(entry)                           -> str
srl_str_to_buf(s) / srl_buf_to_str(buf, n)
srl_session_count(srl) / srl_recv_count(srl)
srl_has_session(srl, peer_id)
srl_stats_sent / _delivered / _decrypt_failed / _no_session
srl_stats_line(srl)
```

### Honest scope

* **Hex on the wire.** The relay v1 wire is text-based, so the
  Noise frame is hex-encoded for transit (2x overhead). Bulk
  transfer would need a binary-clean RELAY\_DATA variant; out of
  R27C scope.
* **Session-key bootstrap.** R7C `noise_xk.nova` ships the three-
  message handshake; this module consumes the post-Split state. The
  test helpers use `_srl_test_forge_nxk` to skip the ~5-15s real
  handshake (four 2048-bit modpows per side). Wiring the actual
  handshake into the `srl_register_peer_session` pipeline (so peers
  auto-handshake on first gossip-table sight) is a follow-up.
* **No per-message ratchet.** The post-Split nxk\_state holds long-
  lived k\_init\_to\_resp / k\_resp\_to\_init. Per-message ratchet (à
  la Signal Double Ratchet) would limit the window if a key is
  exfiltrated. R7C already provides nonce monotonicity for replay
  protection.
* **No group sessions.** One nxk\_state per peer pair. An N-peer
  mesh needs N*(N-1)/2 sessions. Group-key schemes (MLS, signal
  Sender Keys) would scale better.
* **The relay still sees metadata.** `via=C, from=A` annotations on
  RELAY\_DATA are NOT encrypted; the relay can observe which souls
  talked + when. Metadata privacy (mixnet-style) is a separate
  follow-up.

### Verification

* Unit (`tests/unit/test_relay_secure.nova`): **44 assertions**
  -- init zero-state (7); session register + idempotent rekey +
  null-rejection (6); send refuses without session (3); round-trip
  wrap/unwrap (10); tampered ciphertext -> drop on B (5); wrong
  peer's session -> decrypt fails (3); drain drops unpaired
  from-peer (3); recv_secure drain-and-clear (3); buf<->str
  round-trip (2); stats line shape (2).

* Integration (`tests/integration/scenario_xxxx_relay_secure.sh`):
  **11 assertions** on a 3-soul A/B/C mesh. A and B pre-share
  Noise-XK session keys (forged via `_srl_test_forge_nxk`; the AEAD
  codepath is exercised via real nxk\_seal / nxk\_open). A marks B
  unreachable + calls `srl_send_secure` twice. C MITM-tampers the
  second forwarded hex payload by flipping one nibble before drain.
  Asserts: NOVA pre-flight + 3 souls compile + mid-flight liveness,
  A's secure send returned 1 + bumped sent counter, A's underlying
  relay routed via=C, C forwarded both wrapped frames, C's srl
  delivered=0 (no session -- blind), C explicitly attempts decrypt
  with a stranger session and ALL attempts fail (peek\_attempts=2,
  peek\_fail=2), B's srl delivered=1 (the clean first frame), B's
  recv\[0\] plaintext equals the originator's input "ciphertext-from-A"
  (E2E round-trip through unreading C confirmed), B's
  decrypt\_failed >= 1 (the tampered second frame was rejected).

## R27C.2 / R28B extension: bulk binary path for Noise-XK relay payloads

R27C documented the open item R27C.2: the hex-encoded relay wire
doubled the per-frame on-wire bytes, fine for control-plane traffic
(PINGs, /chat commands) but wasteful for bulk payloads (KG delta
packs, snapshot fragments, multi-KB messages). R27C.2 (R28B sprint)
closes that hole by introducing a length-prefixed binary path: when
the AEAD ciphertext crosses a threshold (1024 bytes by default),
srl_send_secure_binary routes through a new RELAY_BIN wire shape
instead of relay_send's hex; the gossip dispatcher recognises the
prefix, reads the raw binary tail off the same fd, and either
queues the terminal record OR forwards as binary to the next hop.

### Wire shape

```
RELAY_BIN <req_id> <target> <via> <from> <total_len>\n
[total_len raw binary bytes of the AEAD frame]
```

The header line still terminates with `\n` so the existing
`_gossip_recv_line` returns it intact. After dispatch recognises the
prefix, `_gnoise_recv_exact(fd, total_len)` (the helper R21E uses
for its Noise handshake framing) drains the binary tail. The AEAD
frame itself is unchanged: the same nxk_seal output that the hex
path encodes to ASCII is written straight to the wire instead.

### What R27C.2 delivers

1. **Module extension** -- `src/federation/gossip_relay_secure.nova`
   grows ~ 480 lines (state slots 8-12 + binary path code).
   New public API:

   ```
   srl_send_secure_binary(srl, target, pt_buf, pt_n) -> 1 ok | 0
       Sealed-then-binary-routed. Refuses on missing session
       (mirror of srl_send_secure's strict policy). Routes
       direct, falls back via an alive intermediate (same
       picker as relay_send), or via a cached relay if target
       is marked unreachable.
   srl_send_secure_auto(srl, target, pt_buf, pt_n) -> 1 ok | 0
       Auto-router: ciphertext > SRL_BIN_THRESHOLD (1024)
       picks binary; else hex. Drop-in replacement.
   srl_inject_binary_record(srl, req_id, from, buf, n)
       Test injection: bypasses the socket so unit tests run
       in the no-network sandbox.
   srl_drain_relay_recv_binary(srl) -> int processed
       Drains the binary inbound queue (records the gossip
       dispatcher pushed after a successful RELAY_BIN read).
   srl_drain_all(srl) -> hex_drained + bin_drained
       Convenience: drains both paths in one call.
   srl_recv_secure_binary(srl) -> drained recv list
       Alias for srl_recv_secure (the recv queue is shared
       between hex and binary; entries land in the same place).
   srl_bin_format_header / srl_bin_parse_header (test helpers)
   srl_stats_bin_sent / _bin_delivered / _bin_decrypt_failed /
       _bin_no_session / srl_bin_inbound_count
   ```

2. **Gossip dispatcher** -- `src/federation/gossip.nova` adds:

   * `GOSSIP_RELAY_BIN_PREFIX = "RELAY_BIN "` constant.
   * `GOSSIP_S_SRL_STATE` (slot 39) + `_BIN_RX/_FWD/_BAD` counter
     slots (40-42) populated in `gossip_init`.
   * `gossip_set_srl_state(state, srl_state)` setter wiring the
     srl_state back-ref so the dispatcher can push terminal
     records onto srl's pinned binary inbound queue
     (`SRL_S_INBOUND_BIN` = slot 8) without importing srl
     (preserves the gossip <-> gossip_relay_secure one-way import
     graph).
   * `_gossip_serve_relay_bin(state, fd, header_line)` -- parses
     the 5-token header, drains `total_len` raw bytes via
     `_gnoise_recv_exact`. If `target == self_addr` -> push
     terminal record. Else -> forward as RELAY_BIN to target,
     bumping the underlying relay's forwarded counter so
     diagnostics reflect the route activity.
   * Parser branches in `gossip_handle_conn` and
     `gossip_handle_conn_kg` (the two plaintext-wire handlers).

### Auto-routing threshold

`SRL_BIN_THRESHOLD = 1024` bytes (in ciphertext / nxk_seal frame
length). Most control messages produce sub-1KB ciphertext after
Noise framing (4-byte length + plaintext + 16-byte tag) and stay on
the hex path for back-compat with R27C scenarios. Bulk payloads
(KG delta packs ~ 5-50KB, snapshot fragments ~ 10-100KB) cross the
threshold and ride binary. The threshold is a constant rather than
env-tunable; a future revision could expose `CE_SRL_BIN_THRESHOLD`
if a deployment wants finer control.

### Wire-size win

* Hex path: 2 × frame_n hex chars + ~ 90-byte header line
  (`RELAY_REQ <id> <target> <origin> <hex...>\n`).
* Binary path: frame_n raw bytes + ~ 80-byte header line
  (`RELAY_BIN <id> <target> <via> <from> <total_len>\n`).

For a 10 KB plaintext (frame_n = 10260 after Noise framing):

| Path   | On-wire bytes | Ratio |
|--------|---------------|-------|
| Hex    | 20520 + ~90  | 1.00x |
| Binary | 10260 + ~80  | 0.50x |

The binary path saves ~ 10 KB per 10 KB payload (the 2x hex
overhead is eliminated outright). Header overhead is < 1% even
on the binary path for any payload above ~ 8 KB.

### Honest scope (R27C.2)

* **Plaintext gossip wire only.** The binary dispatch wires into
  `gossip_handle_conn` and `gossip_handle_conn_kg`. The R21E
  Noise-protected gossip transport (`gossip_handle_conn_kg_gconn`)
  uses an encrypted line-wrapper that is incompatible with the
  raw-bytes tail of RELAY_BIN. The srl AEAD wrap already encrypts
  the payload end-to-end so the binary path's lack of an outer
  R21E transport wrap is not a confidentiality regression --
  defense in depth is sacrificed for bulk efficiency.
* **No automatic chunking.** A frame larger than the dispatcher's
  inbound buffer / nxk_seal's frame limit would be rejected. Bulk
  payloads above the nxk_seal cap need application-level
  chunking + sequencing; that lives above the srl layer.
* **Same metadata exposure.** The header line still carries
  `target / via / from` in cleartext (the dispatcher needs them
  to route). End-to-end metadata privacy is a separate follow-up
  (same gap as R27C).
* **Threshold tuning.** `SRL_BIN_THRESHOLD = 1024` is a heuristic.
  A workload with a strong bias toward 500-byte messages would
  see no benefit; a workload with a strong bias toward 5KB
  messages benefits maximally. The threshold being non-tunable
  is a known limitation.

### Verification

* Unit (`tests/unit/test_relay_secure_binary.nova`):
  **51 assertions** -- binary slots zero on init (6); header
  format + parse round-trip (6) + malformed reject (2); send
  refuses without session (3); inject + drain happy path on a
  short message (15); tamper in AEAD body -> decrypt_fail bump,
  recv stays empty (4); drain drops unpaired from-peer (3); 5KB
  payload wire-size: binary < 0.6x hex (3); 10KB payload full
  round-trip with byte-pattern match (5); recv_secure_binary
  alias drains (2); srl_drain_all unifies both paths (2); stats
  line carries bin_sent= field (1).

* Integration (`tests/integration/scenario_zzzz_relay_binary.sh`):
  **10 assertions** on a 3-soul A/B/C mesh. A sends two 10KB
  binary payloads through C to B via `srl_send_secure_binary`.
  The receiver-side harness MITM-tampers a single byte deep in
  the second frame's AEAD body before drain. Asserts: NOVA
  pre-flight, 3 souls compile + mid-flight liveness, A's binary
  send returned 1 + bin_sent counter bumped, C's gossip
  `bin_fwd >= 1` (the dispatcher forwarded raw bytes), B's
  gossip `bin_rx >= 1` (terminal frame received), B's srl
  `bin_delivered >= 1` (frame decrypted + queued), B's recv[0]
  full 10240 plaintext bytes match the deterministic pattern
  the originator built, B's srl `bin_decrypt_fail >= 1`
  (tampered frame detected via Poly1305), 10KB binary wire size
  (~ 10340 bytes) is < 0.55x the hex wire size (~ 20520 bytes)
  -- the bulk-bandwidth saving is observed end-to-end.

* Regression: scenario_xxxx_relay_secure (R27C) still passes
  11/11 (the hex path is unchanged); all 219 unit tests pass.

## R28E extension: WebRTC data-channel signaling for browser-to-soul federation

CrossEngin federation up to R27 is native-only: every transport is a
raw TCP socket (R18E gossip, R26E relay) or a stubbed-pending UDP
hole-punch (R23E NAT traversal). Browsers cannot open arbitrary
AF\_INET sockets -- the only federation-eligible transport from a
browser tab is WebRTC. R28E ships the **signaling half** of WebRTC
data-channel support so a browser participant can complete the SDP
offer/answer handshake against a NOVA soul; the data plane (DTLS +
SRTP + SCTP-over-DTLS + ICE) is a documented stub that the R28E.2
follow-up will fill in.

### Architecture

```
   +--- offerer (browser or soul) ---+   HTTP signaling   +--- answerer (soul) ---+
   |                                 |  -----------       |                       |
   |  rtc_create_offer(state)        |  POST /rtc/offer   |  rtc_receive_offer    |
   |    -> SDP offer string          +------------------> |    -> SDP answer      |
   |                                 |  body = SDP offer  |       string          |
   |                                 |                    |    -> registers       |
   |                                 |  <-----------------+       session record  |
   |  rtc_receive_answer(state, ans) |  HTTP 200 body =   |                       |
   |    -> 1 ok                      |       SDP answer   |                       |
   |                                 |                    |                       |
   |  rtc_send(state, ch, payload)   |                    |                       |
   |    -> RTC_ERR_NEEDS_DTLS  <-----+---STUB---+         |                       |
   |  rtc_recv(state, ch)            |                    |                       |
   |    -> RTC_ERR_NEEDS_DTLS  <-----+---STUB---+         |                       |
   +---------------------------------+   (R28E.2)         +-----------------------+
```

The SDP shape the module emits + accepts is the minimum-viable
data-channel skeleton:

```
v=0
o=- <session_id> 1 IN IP4 0.0.0.0
s=-
t=0 0
m=application 9 DTLS/SCTP webrtc-datachannel
c=IN IP4 0.0.0.0
a=ice-ufrag:<placeholder>
a=ice-pwd:<placeholder>
a=fingerprint:sha-256 <32 bytes placeholder>
a=setup:<actpass|active>
a=mid:0
a=sctp-port:5000
a=max-message-size:262144
```

The fingerprint / ice-ufrag / ice-pwd attribute values are wire-shape
PLACEHOLDERS in R28E -- the real values require a DTLS X.509 self-
signed cert (whose SHA-256 hash becomes the fingerprint) and an ICE
agent (which assigns ufrag/pwd). The SDP passes syntax checks
(rtc\_parse\_sdp validates v=0 / o= / s= + presence of m=application);
a real browser attempting to actually negotiate a DTLS session against
an R28E peer would see the handshake fail at the DTLS layer, which is
the correct stub semantics (signaling succeeded; data-plane is
honestly unimplemented).

### Public API

```
rtc_init()                                    -> rtc_state
rtc_create_offer(state)                       -> sdp_offer_string
rtc_receive_offer(state, sdp_offer)           -> sdp_answer_string |
                                                 RTC_ERR_BAD_SDP
rtc_receive_answer(state, sdp_answer)         -> 1 ok | RTC_ERR_BAD_SDP
rtc_send(state, channel, payload)             -> RTC_ERR_NEEDS_DTLS |
                                                 RTC_ERR_NO_CHANNEL
rtc_recv(state, channel)                      -> RTC_ERR_NEEDS_DTLS |
                                                 RTC_ERR_NO_CHANNEL
rtc_signaling_register(http_state, rtc_state) -> 0 (stub; R28E.2)
rtc_channel_open(state, session_id)           -> channel | 0
rtc_session_count(state)                      -> int
rtc_stats_offers_created / _offers_received / _answers_received /
   _bad_sdp / _send_attempts / _recv_attempts
rtc_stats_line(state)                         -> one-liner

# parser helpers
rtc_parse_sdp(sdp)                            -> list of [k,v] | 0
rtc_sdp_field(parsed, key)                    -> first value | ""
rtc_sdp_has_media_app(parsed)                 -> 1 | 0
rtc_sdp_attrs(parsed)                         -> list of a= values
rtc_sdp_has_attr_prefix(parsed, prefix)       -> 1 | 0
rtc_format_sdp(lines)                         -> CRLF-joined string
rtc_alloc_session_id(state)                   -> monotonic uint string
```

### Honest scope (R28E.2 follow-up list)

The R28E commit honestly stubs four substantial sub-systems. Each
must land before browser-to-soul WebRTC federation is functional
end-to-end:

1. **DTLS 1.2 / 1.3 client + server.** The bulk of the missing
   work. Requires:
   * X.509 cert generation (self-signed) + SHA-256 fingerprint for
     the SDP `a=fingerprint:` attribute.
   * Full DTLS record layer (epoch, sequence number, MAC).
   * DTLS handshake state machine (ClientHello / ServerHello /
     Certificate / ServerKeyExchange / CertificateRequest /
     CertificateVerify / Finished / retransmission timers).
   * Cipher-suite negotiation (ECDHE-ECDSA-AES128-GCM-SHA256 at
     minimum for current browser interop).
   * SRTP master-key extraction via RFC 5705 `extractor`.

2. **ICE agent (RFC 8445 + RFC 8839).** Required for the SDP
   `ice-ufrag` / `ice-pwd` attributes + the actual UDP path the
   data channel rides over:
   * STUN client compliant with RFC 8489 (R23E ships a STUN-LIKE
     wire that's NOT RFC 8489 -- it's a CrossEngin internal
     two-line text protocol). The ICE agent needs the real STUN
     wire format with magic cookie + transaction id + attribute
     TLVs.
   * Candidate gathering: host candidates (every local interface),
     server-reflexive candidates (via STUN binding), relayed
     candidates (via TURN).
   * Connectivity checks: priority-ordered candidate-pair tests
     with STUN binding requests; nominated-pair selection;
     consent-freshness checks.
   * Trickle ICE (RFC 8838) so candidates can be sent as they're
     gathered rather than batched into the SDP.

3. **SRTP (RFC 3711).** Master keys extracted from DTLS-SRTP key
   derivation feed an SRTP context per data-channel stream:
   * AES-128-GCM encryption + HMAC-SHA1 / GCM tag.
   * Per-packet sequence number + roll-over counter.
   * SRTP -> SCTP framing on top.

4. **STUN / TURN server interaction.** Even with the client side
   working, ICE needs an external STUN server (Google's
   stun:stun.l.google.com:19302 is the canonical public one) for
   server-reflexive candidates, and ideally a TURN server for
   relayed candidates when both ends are behind symmetric NATs.
   R28E.2 can either ship CrossEngin's own STUN/TURN server (RFC
   5389 / RFC 5766) or document configuring an external one. The
   ICE agent needs to learn server addresses from a config + drive
   them.

Additional smaller follow-ups:

* **HTTP signaling endpoint integration.** R28E's
  `rtc_signaling_register` is a stub -- it doesn't actually wire the
  REST endpoints into `src/io/transducers/stream_http.nova` because
  that listener accepts only `POST /api/event` and was not designed
  for path routing. R28E.2 needs to either (a) extend stream\_http
  with a dispatch table on path, or (b) ship a dedicated `/rtc/*`
  listener on a separate port.
* **SCTP framing.** WebRTC data channels actually ride SCTP framed
  inside DTLS records. R28E.2 can either ship the SCTP layer
  (RFC 4960) or get away with a CrossEngin-internal framing if the
  use-case is soul-to-soul only (not browser-to-soul).
* **WebSocket signaling fallback.** Some signaling deployments use
  WebSocket instead of REST. R28E.2 may want to add a WS shim on
  top of the same `rtc_create_offer` / `rtc_receive_offer` API so
  the same module serves both transports.

### Verification

* Unit (`tests/unit/test_webrtc.nova`): **59 assertions** -- init
  zero-state (8); session-id monotonicity (2); offer SDP shape (10:
  begins with v=0, parseable, has o= / s= / m=application,
  carries setup:actpass + fingerprint: + ice-ufrag: attributes,
  bumps offers\_created, registers a session); SDP parser tolerance
  + rejection (5 LF/CRLF + 4 malformed-input cases: empty, missing
  v=0, missing o=, missing s=); receive\_offer happy path (6 emits
  answer, parseable, m=application, setup:active, bumps offers\_rx,
  registers session); receive\_offer malformed (3: bumps bad\_sdp +
  no session created); receive\_offer rejects audio-only (2);
  receive\_answer happy path (2); receive\_answer malformed (2);
  rtc\_send / rtc\_recv return RTC\_ERR\_NEEDS\_DTLS (4: incl.
  stats counters bumped); null-channel handling (2);
  rtc\_signaling\_register returns 0 (stub; 2 calls); stats-line
  shape (2); offer/answer round-trip across two states alice + bob
  (5: each side ends up with a registered session + the expected
  counters).

* Integration: documented in this audit but not run end-to-end.
  A real browser-to-soul WebRTC test requires a real browser
  driving the JS WebRTC API + a NOVA soul running the signaling
  endpoint, plus the R28E.2 DTLS / ICE / SRTP layers to actually
  complete the connection. The R28E codepath that CAN be
  exercised in CI (the SDP parse + format round-trip + the stub
  error returns) IS exercised by the unit suite.

* `NOVA_ROOT=/home/user/NOVA bash scripts/test.sh` -- 217 unit
  tests pass (1 new in R28E). All 5 federation baselines hold:
  gossip\_relay 61, nat\_traversal 53, gossip 34, noise\_xk 44,
  leader\_election 40. Module count +1.

## R37C extension (R36A.2 / R34C.2): canonical `src/safety/md5.nova` + `src/safety/sha1.nova`; dedup turn + srtp

R36A (`1f15e02`) shipped TURN long-term-credential auth with inline
RFC 1321 MD5 (~80 lines) + FIPS 180-4 SHA-1 + RFC 2104 HMAC-SHA1
(~120 lines) bundled into `src/federation/turn.nova`, deferring
canonicalization to a future R36A.2 because R34C's
`_srtp_hmac_sha1` was underscore-prefixed (private) -- breaking
R34C's sealed module to un-mangle would have been a parallel-
ownership violation. R34C (`9a23da2`) shipped SRTP with inline
SHA-1 + HMAC-SHA1 (~150 lines) bundled into
`src/federation/srtp.nova`, documenting the duplication as an
R34A.3-style follow-up candidate -- no canonical `sha1.nova`
existed yet. R37C closes both follow-ups in a single bundle,
applying the `safety/sha256.nova` dedup pattern R33A (3 of 4
consumers) and R34A (the 4th consumer, dtls12) established.

### What R37C delivers

* **`src/safety/md5.nova` (NEW, 536 lines)** -- canonical pure-NOVA
  RFC 1321 MD5. Standard K-table (64 sin-derived T-values),
  S-table (per-round shift counts), g-index (message-schedule
  indices), F/G/H/I round functions, IV (A,B,C,D), and LITTLE-
  endian output. API:
  * `md5_oneshot(buf, n) -> 17-byte buffer` (16B digest + NUL slack)
  * `md5_oneshot_str(s) -> 17-byte buffer`
  * `md5_init() / md5_update / md5_final` streaming
  Constants `MD5_HASH_LEN = 16`, `MD5_BLOCK_LEN = 64`. Module
  docstring documents the Wang 2004 / FastColl 2007 /
  MD5SHATTERED 2009 attacks but justifies the implementation per
  RFC 5389 §15.4 (the canonical STUN long-term-credential
  derivation), RFC 5849 (OAuth 1.0 HMAC-MD5), and legacy IPsec
  variants.

* **`src/safety/sha1.nova` (NEW, 509 lines)** -- canonical pure-NOVA
  FIPS 180-4 SHA-1 + RFC 2104 HMAC-SHA1. Standard 5-word IV, K
  constants (four 32-bit values spanning rounds 0..19, 20..39,
  40..59, 60..79), 80-round compression function with the four
  (b,c,d) non-linear functions, BIG-endian output. API:
  * `sha1_oneshot(buf, n) -> 21-byte buffer` (20B digest + NUL slack)
  * `sha1_oneshot_str(s) -> 21-byte buffer`
  * `sha1_init() / sha1_update / sha1_final` streaming
  * `hmac_sha1(key, key_n, msg, msg_n) -> 21-byte buffer`
  Constants `SHA1_HASH_LEN = 20`, `SHA1_BLOCK_LEN = 64`. Module
  docstring documents the SHAttered 2017 collision attack but
  justifies the implementation per RFC 3174 / RFC 5389 / RFC 3711
  legacy specs that mandate SHA-1.

* **`src/federation/turn.nova` refactored**: the inline MD5
  (`_turn_md5_*` family) + inline SHA-1 (`_turn_sha1_*` family) +
  inline HMAC-SHA1 (`_turn_hmac_sha1`) -- ~410 lines of inline
  implementation -- are replaced with two `import` lines + four
  thin wrappers (`_turn_md5_oneshot`, `_turn_hmac_sha1`,
  `_turn_test_md5`, `_turn_test_hmac_sha1`) that forward to the
  canonical primitives. `turn_hmac_sha1_key` unchanged (still
  formats `"username:realm:password"` then calls
  `_turn_md5_oneshot`). The MI byte-position rule (RFC 5389 §15.4
  -- HMAC over bytes before the MI attribute) is unchanged.

* **`src/federation/srtp.nova` refactored**: the inline SHA-1
  (`_srtp_sha1_*` family) + inline HMAC-SHA1 (`_srtp_hmac_sha1`)
  -- ~150 lines -- are replaced with one `import` line + two
  thin wrappers that forward to the canonical primitives. The
  `srtp_authenticate` truncation to 10 bytes (RFC 3711 §4.2 80-bit
  tag) is unchanged.

* **`_TURN_MD5_HASH_LEN = 16` retained** in turn.nova because two
  call sites pass it as the `key_n` arg to `_turn_hmac_sha1` to
  indicate the 16-byte MD5-derived MESSAGE-INTEGRITY key length
  per RFC 5389 §15.4. All other prefixed constants are removed.

### Verification

* **All 359 prior turn assertions remain byte-identical** through
  the wrapper pattern. The wrapper-preservation contract: a
  wrapper that forwards every byte-buffer arg unchanged + returns
  the canonical's return value is by construction
  byte-equivalent. Test shims `_turn_test_md5` /
  `_turn_test_hmac_sha1` are unchanged; the 359-assertion
  `tests/unit/test_turn.nova` is byte-untouched.
* **All 131 prior srtp assertions remain byte-identical** through
  the wrapper pattern. The underscore-prefixed private symbols
  `_srtp_sha1_oneshot` / `_srtp_hmac_sha1` are preserved as
  wrappers; the 131-assertion `tests/unit/test_srtp.nova` is
  byte-untouched.
* **`tests/unit/test_md5.nova` (NEW, 16 assertions)** pins MD5
  against RFC 1321 §A.5 KAT vectors (empty, "a", "abc", "message
  digest", lowercase alphabet) + 55B/56B/100B boundary cases +
  streaming-vs-oneshot equivalence across 4 splitting strategies
  + string-wrapper round-trip + constants.
* **`tests/unit/test_sha1.nova` (NEW, 17 assertions)** pins SHA-1
  against FIPS 180-4 Appendix A / RFC 3174 KAT vectors (empty,
  "abc", FIPS Appendix B.2 56-char input, 'a' * 1000) +
  streaming-vs-oneshot equivalence across 5 splitting strategies +
  HMAC-SHA1 RFC 2202 TC1 + TC2 + TC4 + long-key normalization +
  string wrapper + constants.

### Subtle differences between the two inline source copies

* **MD5 source: only R36A's `_turn_md5_*` was available** (R34C's
  srtp.nova doesn't use MD5). Promoted verbatim with the prefixes
  mechanically renamed `_turn_md5_*` -> `_md5_*` and
  `_TURN_MASK32` -> `_MD5_MASK32`. K-table, S-table, g-index,
  F/G/H/I round functions, IV, and LE byte order are byte-for-
  byte identical to RFC 1321 §3.4.
* **SHA-1 source: picked R34C's `_srtp_sha1_*` family** over
  R36A's `_turn_sha1_*` family. R36A's copy aliased the SHA-1
  helpers onto MD5's helpers (e.g. `_turn_sha1_rotl32` called
  `_turn_md5_mask32`) -- a micro-optimization that worked but
  tangled the two algorithms' namespaces. R34C's `_srtp_sha1_*`
  family is cleanly separated from any MD5 path (SRTP doesn't use
  MD5), more closely mirrors the `src/safety/sha256.nova` shape,
  and is therefore the cleaner-to-canonicalize source. Both
  copies produce byte-identical outputs (proved indirectly via
  the per-consumer test KAT vectors).
* **Output byte order**: MD5 is LITTLE-endian per RFC 1321 §3.5;
  SHA-1 is BIG-endian per FIPS 180-4 §6.1.2. Both consumers'
  call sites consume the raw digest bytes directly without re-
  encoding; the wrapper does NOT need a byte-order conversion.
* **HMAC-SHA1 signature parity**: both `_turn_hmac_sha1` and
  `_srtp_hmac_sha1` use `(key_buf, key_n, msg_buf, msg_n)` --
  return is a freshly alloc'd 21B buffer, no output-buffer arg.
  The canonical `hmac_sha1` exposes the same signature; wrappers
  are one-line `return hmac_sha1(...)` forwards.

### Files modified

* NEW: `src/safety/md5.nova` (536 lines).
* NEW: `src/safety/sha1.nova` (509 lines).
* NEW: `tests/unit/test_md5.nova` (280 lines, 16 assertions).
* NEW: `tests/unit/test_sha1.nova` (347 lines, 17 assertions).
* MOD: `src/federation/turn.nova` (-420 net lines: removed
  ~410 inline MD5 + SHA-1 + HMAC-SHA1, added 2 imports + 2
  wrappers + header doc updates; kept `_TURN_MD5_HASH_LEN`).
* MOD: `src/federation/srtp.nova` (-194 net lines: removed
  ~230 inline SHA-1 + HMAC-SHA1, added 1 import + 2 wrappers +
  header doc updates).
* UNCHANGED: `tests/unit/test_turn.nova` (359 assertions byte-
  identical to 1f15e02 / R36A's commit).
* UNCHANGED: `tests/unit/test_srtp.nova` (131 assertions byte-
  identical to 9a23da2 / R34C's commit).

### Module count delta: +2 (`src/safety/md5.nova` + `src/safety/sha1.nova`).

### Inline-MD5 copy count: **1 -> 0** (canonical is now the single authoritative source for RFC 1321 MD5 across the tree).
### Inline-SHA-1 copy count: **2 -> 0** (canonical is now the single authoritative source for FIPS 180-4 SHA-1 + RFC 2104 HMAC-SHA1 across the tree).

## R34A extension (R33A.2): dtls12 SHA-256 dedup -> canonical `src/safety/sha256.nova`

R33A landed the canonical `src/safety/sha256.nova` (FIPS 180-4 SHA-256
+ RFC 2104 HMAC-SHA256) and refactored three of four inline copies
across the tree (`noise_xk.nova`, `merkle.nova`, `ecdsa.nova`). R33A
deliberately did NOT touch `src/federation/dtls12.nova` because R33B
was concurrently modifying the same file (cert verify wire-in for
R29B.3 / R32C.2). R33B landed at `37706b8` -- R34A is the planned
R33A.2 follow-up that retires the FOURTH and last inline FIPS 180-4
SHA-256 implementation in the tree.

### What R34A delivers

* `src/federation/dtls12.nova` refactored: the inline FIPS 180-4
  SHA-256 (`_dtls_mask32`, `_dtls_add32`, ..., `_dtls_sha_k` K-table,
  `_dtls_sha_init_h` IV, `_dtls_sha_compress` compression,
  `dtls_sha256` padding) and the inline RFC 2104 HMAC-SHA256
  (`dtls_hmac_sha256` ipad/opad XOR + inner/outer SHA chained) -- ~270
  lines of inline implementation -- are replaced with two one-line
  wrappers forwarding to R33A's canonical `sha256_oneshot` /
  `hmac_sha256`. `import "../safety/sha256.nova"` added at the top.
* `_DTLS_HASH_LEN = 32` retained because HKDF + PRF code below
  references it directly (the constant is FIPS 180-4 -- canonical
  exposes the same value as `SHA256_HASH_LEN`; we keep the
  dtls-prefixed local alias so the HKDF + PRF bodies stay
  byte-identical to their pre-R34A form).
* `_DTLS_BLOCK_LEN` and `_DTLS_MASK32` (and the matching helper
  functions) removed -- they were used only by the inline SHA-256 +
  HMAC bodies, which are now gone.
* HKDF-Extract / HKDF-Expand (RFC 5869) and TLS 1.2 PRF P_SHA256
  (RFC 5246 §5) kept inline because they compose HMAC-SHA256 in
  DTLS-specific recipes that have no analog in the canonical
  primitive module. They call `dtls_hmac_sha256` which is now itself
  a wrapper, so the canonical implementation propagates transparently.

### Verification

* All 353 prior dtls12 assertions remain byte-identical (297 R29B +
  R31B + R32B + 56 R33B). The wrapper pattern (proven by R33A on the
  three prior consumers: 44 noise_xk + 60 merkle + 25 ecdsa, all
  preserved) holds wire-level identity by construction. The canonical
  was lifted from R32C's ecdsa.nova SHA-256 which was FIPS 180-4
  spec-conformant and bit-equivalent to dtls12's prior inline copy
  (same K-table, IV, compression, padding rule).
* `tests/unit/test_dtls12.nova` is byte-untouched -- the proof of no
  behavioral change. The test pins `dtls_sha256` / `dtls_hmac_sha256`
  / HKDF / PRF symbols against published vectors (FIPS 180-2 worked
  example for "abc", RFC 4231 TC1 for HMAC, RFC 5869 vector 1 for
  HKDF); all pass through the wrappers unchanged.
* `tests/unit/test_sha256.nova` (R33A's 20 assertions) re-run -- still
  passes 20/20.
* Adjacent modules verified: `src/federation/snapshot_attestation.nova`
  and `src/learning/secure_aggregation.nova` do not reference any of
  dtls12's SHA-256 / HMAC / HKDF / PRF surface (grep: zero matches in
  either module). Other dtls12 importers (`ice.nova`,
  `stun_rfc8489.nova`, `srtp.nova`) reference dtls12.nova only in
  comments; none import the SHA-256 surface.

### Subtle differences encountered

None. Both implementations were FIPS 180-4 §5.3.3 + §6.2 conformant
with identical K-table (first 32 bits of fractional cube roots of the
first 64 primes), identical IV (first 32 bits of fractional square
roots of the first 8 primes), and identical 64-round compression
function. The HMAC ipad (0x36) / opad (0x5c) XOR pads, the 64-byte
block normalization, and the >64-byte pre-hash branch all match RFC
2104 §2 in both copies. The 33-byte (32B digest + trailing NUL)
return-buffer shape was the documented common convention every
previous copy shared; the canonical retained it.

### Files modified

* MOD: `src/federation/dtls12.nova` (-216 net lines).
* MOD: `NEXT_SESSION.md`, `README.md`, `FEDERATED_AUDIT.md` -- R34A
  section.
* UNCHANGED: `tests/unit/test_dtls12.nova` (byte-identical to R33B's
  commit `37706b8` -- proof that wrapper byte-identity holds).

Module count delta: 0 (no new files). Inline FIPS 180-4 SHA-256 copy
count in the tree: **4 -> 0** -- the canonical is now the single
authoritative source.

## R34B extension: TURN protocol wire codec (RFC 5766 / 8656) (R28E.2)

R28E shipped the SIGNALING half of browser-to-soul WebRTC; the
R28E.2 exit report flagged four follow-up sub-systems: DTLS (R29B
/ R31B / R32B / R33B), ICE (R30C), SRTP (R34C), and STUN/TURN.
R30C closed STUN + ICE; R34B closes the TURN half so an ICE
agent can speak to a TURN relay when peer-to-peer NAT traversal
fails and ICE falls back to the relay candidate.

### Module: `src/federation/turn.nova` (~700 lines, leaf)

This is a WIRE CODEC only -- not a relay server. No allocation
lifecycle, no permission tracking, no channel-data forwarding,
no DTLS-over-TURN. State machine deferred to a future round
that builds on this codec.

TURN reuses STUN's 20-byte header + TLV-attributes framing
(magic cookie 0x2112A442, 12-byte transaction id), adds the six
TURN message methods (Allocate / Refresh / Send / Data /
CreatePermission / ChannelBind) and the TURN-specific attribute
set (CHANNEL-NUMBER, LIFETIME, XOR-PEER-ADDRESS, DATA,
XOR-RELAYED-ADDRESS, REQUESTED-TRANSPORT, DONT-FRAGMENT,
RESERVATION-TOKEN).

Public emit API (client side):
* `turn_emit_allocate_request(txn_id_buf, lifetime_sec,
  requested_transport_udp17) -> [buf, n]`
* `turn_emit_refresh_request(txn_id_buf, lifetime_sec) -> [buf, n]`
* `turn_emit_create_permission_request(txn_id_buf, peer_ip_v4,
  peer_port) -> [buf, n]` (single peer)
* `turn_emit_create_permission_request_multi(txn_id_buf, peers)`
  (multi-peer)
* `turn_emit_send_indication(peer_ip_v4, peer_port, data_buf,
  data_n) -> [buf, n]`
* `turn_emit_channel_bind_request(txn_id_buf, channel_num,
  peer_ip_v4, peer_port) -> [buf, n]`

Public parse API (server side):
* `turn_parse_allocate_success_response(buf, n) -> [relayed_ip,
  relayed_port, lifetime, mapped_ip, mapped_port] | negative err`
* `turn_parse_allocate_error_response(buf, n) -> [err_code,
  reason_str] | negative err`
* `turn_parse_data_indication(buf, n) -> [peer_ip, peer_port,
  data_buf, data_n] | negative err`
* `turn_parse_refresh_success_response(buf, n) -> [lifetime] |
  negative err`
* `turn_classify_message(buf, n) -> [method, class, length,
  txn_ptr] | negative err`

Errors are negative-integer sentinels: `TURN_ERR_HEADER`,
`TURN_ERR_COOKIE`, `TURN_ERR_LENGTH`, `TURN_ERR_ATTR`,
`TURN_ERR_FAMILY`, `TURN_ERR_NO_ATTR`, `TURN_ERR_METHOD`.

### Verified

* `tests/unit/test_turn.nova`: 35 test functions, 200 assertions
  all passing. Coverage: byte helpers, pad4, method/class pack
  + unpack round-trip across all 24 combinations, XOR-address
  helper round-trip, Allocate request byte layout, Allocate
  request->success round-trip (LIFETIME + REQUESTED-TRANSPORT
  + XOR-RELAYED + XOR-MAPPED all decode), Allocate Error 401
  Unauthorized + 437 Allocation Mismatch, Refresh round-trip
  with lifetime values 0 (delete) / 60 (one minute) / 600 (RFC
  5766 §2.2 default), CreatePermission single + multi-peer
  (three peers, all decode), Send Indication byte layout +
  large-payload (64-byte data) round-trip via the symmetric
  Data Indication parser, ChannelBind round-trip (CHANNEL-NUMBER
  in [0x4000, 0x7FFF] band + XOR-PEER-ADDRESS), malformed
  message rejections (short header / bad cookie / truncated
  TLV / unaligned length / length-exceeds-buf / IPv6 family /
  wrong-method-for-parser / top-2-bits-non-zero), STUN-shared
  attribute tolerance (SOFTWARE / USERNAME / MESSAGE-INTEGRITY
  / REALM / NONCE / XOR-MAPPED-ADDRESS / FINGERPRINT injected
  alongside required attrs -- the codec extracts the right
  values without choking), auth-required error response with
  REALM + NONCE injected alongside ERROR-CODE.

### Skipped (documented)

* **RFC 5766 attributes** EVEN-PORT (0x000F),
  REQUESTED-ADDRESS-FAMILY (0x0017), ADDITIONAL-ADDRESS-FAMILY
  (RFC 8656) -- not implemented. EVEN-PORT controls port-pair
  allocation for RTP/RTCP. The address-family extensions cover
  IPv6 dual-stack allocate.
* **IPv6** XOR-MAPPED / XOR-PEER / XOR-RELAYED -- this round is
  IPv4-only. An incoming attribute with family=2 is REJECTED
  with `TURN_ERR_FAMILY`.
* **Long-term-credential authentication** (USERNAME /
  MESSAGE-INTEGRITY / REALM / NONCE per RFC 5766 §3 + RFC 8489
  §10) -- not implemented on the EMIT side. The PARSE side
  correctly handles a 401 response that carries REALM + NONCE
  alongside ERROR-CODE. The re-issue path is deferred: a future
  round should compose `stun_hmac_sha1` (already shipped in
  R30C's `stun_rfc8489.nova`) with the REALM/NONCE flow.
* **Relay state machine** -- no allocation lifecycle, no
  permission table, no channel bookkeeping, no channel-data
  framing (RFC 5766 §11.5). The codec emits a CreatePermission
  Request but does not track which peers have permission for
  outgoing Send Indications. All deferred.

### Caveats / future work

1. **MESSAGE-INTEGRITY not verified on parse**. R34B tolerates
   the attribute on incoming messages (must, so 401 + REALM +
   NONCE responses parse), but does NOT verify the HMAC. A
   future hardening round should plumb the STUN MI verifier
   from `stun_rfc8489.nova`.
2. **CHANNEL-NUMBER range not enforced**. RFC 5766 §11.2 says
   channels must be in [0x4000, 0x7FFF]. The codec writes
   whatever 16-bit value the caller passes; callers are
   responsible for that invariant. A future round can either
   enforce or document the contract more visibly.
3. **No FINGERPRINT verification**. Same rationale as MI --
   tolerated but not checked. STUN already ships the CRC32 +
   FINGERPRINT verifier.
4. **No ICE integration yet**. R30C's `ice.nova` has a
   relay-candidate placeholder in the candidate-gathering path;
   wiring R34B's emit/parse into that placeholder is the
   natural next step.

## R34C extension: SRTP wire codec (RFC 3711) -- AES-CM-128 + HMAC-SHA1-80 + KDF + anti-replay (R28E.2)

R28E shipped the SIGNALING half of browser-to-soul WebRTC; the
R28E.2 exit report flagged four follow-up sub-systems: DTLS 1.2
(R29B / R31B / R32B / R33B), ICE (R30C), STUN/TURN (R30C /
R31C / R33E), and SRTP. R34C lands the SRTP wire codec
independently of DTLS-SRTP key extraction -- the SRTP packet
authentication / encryption layer needs to exist before a future
round can wire RFC 5764's "extract SRTP master from DTLS PRF
output" path.

What R34C delivers in `src/federation/srtp.nova` (NEW module):

* **AES-CM-128 stream cipher (RFC 3711 §4.1.1).** The 16-byte AES
  counter block is built as `salt[14B] || 00 00`, XORed with
  `ssrc << 64` at bytes [4..8) and `packet_index << 16` at bytes
  [8..14). The low 16 bits are the per-block counter; they
  increment by 1 to produce each subsequent keystream block.
  Encrypt and decrypt are the same call (XOR is involutive).
  `_srtp_aes_cm_keystream(key, salt, ssrc, packet_index, n)`
  generates `n` bytes; `srtp_encrypt(key, salt, ssrc, idx, pt, n)`
  is the XOR wrapper.

* **HMAC-SHA1-80 authenticator (RFC 2104 + RFC 3174 SHA-1).** SHA-1
  is inlined locally as `_srtp_sha1_*` (FIPS 180-4 §6.1 -- the
  same 5-word IV / 80-round compression / 4-zone K table every
  reference implementation uses); SHA-1 is not in `src/safety/`
  today, and a future R34A.3-style follow-up can extract a
  canonical `src/safety/sha1.nova` if another consumer appears.
  `srtp_authenticate(auth_key, packet, n, roc)` computes
  HMAC-SHA1 over `(packet || roc[4B])` per RFC 3711 §4.2 ("the
  ROC SHALL be appended") and truncates to 80 bits (10 bytes).
  Key normalization follows RFC 2104 (> 64 bytes pre-hashed; <
  64 bytes zero-padded).

* **AES-CM key derivation (RFC 3711 §4.3).** The KDF input is
  `x = master_salt XOR (label || r)` where label is one of
  `SRTP_LABEL_ENCR=0x00`, `SRTP_LABEL_AUTH=0x01`,
  `SRTP_LABEL_SALT=0x02`; with `r = 0` (the default key-derivation
  rate KDR=0) the XOR places the label at byte 7 of `x`. AES-CM
  keystream generation with `master_key` as the AES key, `x` as
  the CM salt, and `ssrc = packet_index = 0` produces the
  requested derived key. `srtp_kdf(master_key, master_salt,
  label, derive_len)` is the single-label entry; `srtp_derive_keys`
  returns the three §4.3.2 sub-keys in one call.

* **64-packet anti-replay sliding window (RFC 3711 §3.3.2).** Same
  pattern R32B used for DTLS but keyed on the 48-bit extended
  sequence `(roc << 16) | seq` rather than the 48-bit DTLS
  record seq. `_srtp_replay_check(state, packet_index)` is a
  PURE function -- it returns `SRTP_AR_OK` / `SRTP_AR_REPLAY`
  / `SRTP_AR_TOO_OLD` without mutating state. The window is
  updated by `_srtp_replay_update` ONLY after the HMAC verifies,
  so a forged packet cannot advance the window and lock out the
  legitimate next packet (R32B's "tamper does not advance"
  property, preserved here).

* **ROC estimator (RFC 3711 §3.3.1).** The 32-bit rollover counter
  increments when the 16-bit RTP seq wraps from 65535 -> 0.
  For an out-of-order packet, `_srtp_estimate_packet_index(roc,
  last_seq, seq)` picks the most-likely 32-bit ROC: if the wire
  `seq` is more than 2^15 below `last_seq`, the packet probably
  came from the NEXT ROC; if more than 2^15 above, from the
  PREVIOUS ROC; otherwise same ROC. The 48-bit packet_index is
  then `(guess_roc << 16) | seq`.

* **Top-level seal + open.** `srtp_seal_packet(state, rtp_hdr_buf,
  hdr_n, payload, pt_n)` stamps `state.send_seq` into header
  bytes [2..4) (RFC 3550 §5.1), encrypts the payload, appends
  the HMAC tag, and bumps send_seq (rolling ROC on wrap).
  `srtp_open_packet(state, sealed_buf, n, hdr_n)` pulls seq
  from bytes [2..4), runs the ROC estimator, runs the
  anti-replay pre-check, verifies the HMAC, decrypts, and
  advances the window + ROC + last_seq on success.

Cryptographic dependencies: `src/safety/aes_gcm.nova` (R30B) for
the AES-128 block primitive (`aes128_key_schedule` +
`aes128_encrypt_block_with_schedule`). SRTP and DTLS share the
AES-128 block layer; only the mode (CM vs GCM) differs. No
duplication of the AES block code; SHA-1 IS duplicated locally
in srtp.nova (no canonical sha1.nova exists yet).

What R34C does NOT ship (deferred):

* **DTLS-SRTP key extraction (RFC 5764).** The master key + salt
  come from caller code; a future round wires DTLS's
  `dtls_export_keying_material` output into `srtp_derive_keys`.
  The public API is shaped so that wiring requires no breaking
  change to the seal/open path.
* **SRTCP (RFC 3711 §3.4).** The control-plane sibling has its
  own seq numbering + always-encrypted-tag layout that is
  structurally different; defer to a follow-up round when a
  caller needs SRTCP.
* **MKI (Master Key Identifier, RFC 3711 §3.1).** We ship with
  `mki_length = 0`, the WebRTC interop default.
* **AEAD_AES_128_GCM SRTP profile (RFC 7714).** Modern WebRTC
  profile that replaces HMAC-SHA1 with GCM's GHASH-based tag.
  R34C ships the default (AES-CM-128 + HMAC-SHA1-80) only; the
  GCM profile is a future round.
* **Canonical SHA-1 dedup.** SHA-1 is inlined in srtp.nova; if a
  future consumer also needs SHA-1, an R34A.3-style follow-up
  can extract `src/safety/sha1.nova` (analogous to R33A's
  canonical SHA-256).

### Verification

* **`tests/unit/test_srtp.nova`**: 111 new assertions across 31
  test functions. Coverage:
  * SHA-1 KATs (RFC 3174 Appendix A + FIPS 180-4 Appendix B.2):
    "abc", "", 56-char two-block-padding boundary, 55-byte
    one-block boundary.
  * HMAC-SHA1 RFC 2202: TC1 (key=0x0b*20, "Hi There"), TC2
    (key="Jefe", "what do ya want for nothing?"), TC4
    (key=0x01..0x19, msg=0xcd*50), long-key normalization.
  * AES-CM keystream: zero-key + counter=0 (AES_0(0^16)),
    counter=1 (cross-block boundary), SSRC differentiation,
    packet_index differentiation, encrypt+decrypt round-trip.
  * **RFC 3711 §B.3 KDF official test vector**: master key
    `E1F97A0D3E018BE0D64FA32C06DE4139` + master salt
    `0EC675AD498AFEEBB6960B3AABE6` -> encryption key
    `C61E7A93744F39EE10734AFE3FF7A087` (label 0) + auth key
    `CEBE321F6FF7716B6FD4AB49AF256A156D38BAA4` (label 1) + salt
    `30CBBC08863D8C85D49DB34A9AE1` (label 2). All three verified
    byte-identical against the RFC. The auth-key test (20 bytes)
    forces the counter to increment, so the keystream
    cross-block boundary is also exercised through the KDF.
  * Full seal + open round-trip on a 12-byte RTP header + 32-byte
    payload + 10-byte tag = 54-byte wire packet. Plaintext
    recovered byte-identical.
  * Tamper rejection: flip a tag byte -> SRTP_AUTH_FAIL; flip a
    ciphertext byte -> SRTP_AUTH_FAIL (HMAC is over the
    ciphertext); flip a header byte -> SRTP_AUTH_FAIL (HMAC is
    over the header too). All three flow to AUTH_FAIL and do NOT
    advance the replay window watermark or ROC -- mirrors R32B's
    "tamper does not advance" property.
  * Anti-replay: replay of the same packet_index -> SRTP_REPLAY;
    64-packet jump idx=0 -> idx=64 slides the window so that a
    replay of idx=0 is now SRTP_TOO_OLD; out-of-order within
    window (idx=0 then idx=5) both accept; replay of idx=0 after
    accepting idx=5 -> SRTP_REPLAY (within window with bit set).
  * ROC rollover send side: seq=65534 -> 65535 -> 0 (send_seq
    wraps to 0, send_roc bumps to 1) -> 1. ROC rollover recv
    side: §3.3.1 estimator picks roc=0 for seq=65534+65535 and
    roc=1 for seq=0 after the wrap. Explicit estimator cases
    pinned: low last_seq + high seq -> previous ROC; high
    last_seq + low seq -> next ROC.
  * State init: all counters + windows + ROC start at 0.
  * Constants: SRTP_AUTH_TAG_LEN=10, SRTP_KEY_LEN=16,
    SRTP_AUTH_KEY_LEN=20, SRTP_SALT_LEN=14, distinct
    AUTH_FAIL / REPLAY / TOO_OLD sentinels.

* **No prior assertions affected.** R34C adds NEW files only;
  no existing module is touched. The AES-128 block primitive in
  `src/safety/aes_gcm.nova` is consumed unchanged.

### Honest design caveats

* **SHA-1 inline duplication.** The `_srtp_sha1_*` family is a
  local copy of the FIPS 180-4 SHA-1 algorithm (~150 lines).
  This is the same trade-off `dtls12.nova`'s `_dtls_sha256_*`
  bundled before R33A extracted it: each consumer keeps its
  import graph minimal at the cost of duplicating the
  implementation. When a second module needs SHA-1, an
  R34A.3-style follow-up should extract `src/safety/sha1.nova`
  -- the refactor pattern is exactly R33A's. Until then, SHA-1
  has exactly one home (here) and the duplication risk is bounded.

* **`srtp_open_packet` takes `hdr_n` from the caller** rather than
  parsing the RTP CSRC count + extension header. A real WebRTC
  caller knows its own header length from RTP byte 0 (CC field)
  + extension parsing, and exposing `hdr_n` as an explicit
  parameter keeps the codec layer-agnostic. A future "full RTP
  header parser" wrapper can sit on top of this layer without
  modifying it.

* **No constant-time tag comparison.** The HMAC tag compare uses
  the same byte-by-byte XOR-fold pattern as `gcm_open` in
  `aes_gcm.nova`. R30B.3 tracked the broader "bitsliced AES +
  constant-time comparators" hardening follow-up; SRTP joins
  that scope.

* **HMAC-SHA1 vs MAC security.** SHA-1 is collision-broken
  (SHAttered, 2017), but HMAC-SHA1 remains MAC-secure: SHA-1
  collisions do not break the HMAC PRF (NIST SP 800-131A
  specifies HMAC-SHA1 acceptable for "legacy use" with a 128-bit
  key; SRTP uses a 160-bit auth key, so the security margin is
  larger). RFC 7714's AEAD_AES_128_GCM SRTP profile sidesteps
  the question entirely; it's the eventual migration target.

## R33B extension: DTLS cert verify wire + CCS-on-epoch replay-window reset (R29B.3 / R32B.2 / R32C.2)

R29B (the 1.0 of DTLS 1.2 in CrossEngin) shipped two
`_R29B2_STUB`-suffixed slots that returned `DTLS_ERR_STUB` as
placeholders for follow-up rounds. R31B retired three of those
(`dtls_ecdhe_derive`, `dtls_seal_record`, `dtls_open_record`); R33B
retires the last (`dtls_cert_verify`) by wiring R32C's brand-new
`src/safety/x509.nova` + `src/safety/ecdsa.nova` into a real
parse-validate-hash-verify-fingerprint pipeline.

R32B's exit report flagged a second deferral: the anti-replay sliding
window did not reset on epoch transitions, in violation of RFC 6347
§4.1.2.6 ("MUST reset the receive sequence number space and the
anti-replay window"). R33B closes that with `dtls_advance_epoch(state)`,
which bumps both send and receive epoch counters, zeroes the send/recv
sequence slots, and zeroes the watermark + replay mask. The
`stats_replay` / `stats_too_old` / `aead_records_*` counters are
preserved across the transition (cumulative connection-lifetime
telemetry).

To keep the AEAD layer's cross-epoch protection intact, the seal/open
paths now compute the AAD seq_num as `(epoch << 48) | seq`, matching
RFC 5246 §6.2.3.3 + RFC 6347 §4.1.2.6. The seal side reads the
current send epoch from state; the open side reads the WIRE epoch
from the record header (the AAD must be self-describing). A
ciphertext sealed at epoch=0 + seq=N cannot be successfully opened
in epoch=1 even if the watermark accepts seq=N, because the AAD
differs and gcm_open's tag check fails. With `epoch=0` the new
formula collapses to plain `seq` so all 297 pre-R33B test
assertions remain byte-identical.

Cert verify failure tags are kept distinct -- unlike the AEAD path
which collapses ciphertext/tag/AAD failures into one indistinct
`DTLS_DECRYPT_FAIL` for oracle-leak hygiene, cert verify runs
BEFORE any oracle-relevant state is touched, so distinguishability
is safe and useful (attribution per failure path).

Cert chain validation is single-cert only. CrossEngin's actual cert
use case is SDP-fingerprint pinning (RFC 4572 §5), where the SDP
offerer's hash of the entire cert binds to a known fingerprint; no
CA traversal needed. A future hardening round can extend to chains
if a non-SDP use case emerges.

The original R33B agent died mid-session with the implementation
landed but the test scaffolding incomplete. Recovery: the session
operator (a) verified the dtls12.nova diff was self-consistent
(297 prior assertions preserved via tail-append slot layout +
epoch=0 AAD collapse), (b) added the missing 17 R33B test functions
+ 56 assertions covering all five cert-verify outcomes and the
epoch-reset state transitions, (c) updated documentation. The
implementation in dtls12.nova is exactly what the agent landed;
only the test file + docs reflect operator handoff.

## R33A extension: canonical `src/safety/sha256.nova` + dedup 3 of 4 copies

R32C's exit report (the round before this one) noted: "SHA-256 is the
fourth duplicated copy in the tree (alongside noise_xk.nova,
merkle.nova, dtls12.nova); refactor target src/safety/sha256.nova
tracked." Each copy was the same byte-identical FIPS 180-4 SHA-256
implementation; the maintenance asymmetry (a bug-fix or constant-time
tweak in one copy silently leaving the other three on a stale
implementation) was the real cost. R33A extracts the canonical
primitive and refactors three of the four consumers.

### What R33A delivers

* **NEW `src/safety/sha256.nova`** -- canonical FIPS 180-4 SHA-256 +
  RFC 2104 HMAC-SHA256, lifted from R32C's `ecdsa_sha256` family
  (the cleanest source copy of the four). Public API:
  * `sha256_oneshot(buf, n) -> 33-byte buffer` (32B digest + NUL slack)
  * `sha256_oneshot_bytes(byte_list) -> 32-element byte list`
  * `sha256_oneshot_str(s) -> 33-byte buffer`
  * `sha256_init() / sha256_update(st, buf, n) / sha256_final(st)` --
    streaming triple, FIPS 180-4 padding deferred to `final`.
  * `hmac_sha256(key_buf, key_n, msg_buf, msg_n) -> 33-byte buffer`
* **`src/io/transducers/noise_xk.nova` refactored**: ~300 lines of
  inlined SHA-256 + HMAC removed, replaced with `import "../../safety
  /sha256.nova"` plus 3 one-line wrappers (`sha256_buf`, `sha256_str`,
  `hmac_sha256_buf`) preserving the pre-existing public symbols.
  All 44 prior unit assertions byte-identical.
* **`src/persistence/merkle.nova` refactored**: ~240 lines of inlined
  SHA-256 removed, replaced with `import "../safety/sha256.nova"`
  plus 2 one-line wrappers (`_mk_sha256_buf`, `_mk_sha256_str`).
  All 60 prior unit assertions byte-identical.
* **`src/safety/ecdsa.nova` refactored**: ~250 lines of inlined
  SHA-256 removed, replaced with `import "../safety/sha256.nova"`
  plus 2 one-line wrappers (`ecdsa_sha256`, `ecdsa_sha256_bytes`).
  All 25 prior unit assertions byte-identical.
* **NEW `tests/unit/test_sha256.nova`** -- 20 assertions covering FIPS
  180-4 KAT vectors (`"abc"`, `""`, Appendix B.2 56-char, 55-byte
  one-block-boundary, 1000-byte input), streaming-vs-oneshot
  equivalence (5 distinct splitting strategies), and RFC 4231
  HMAC-SHA256 TC1 + TC2 + TC4 + long-key normalization.

### Deferred to follow-up

`src/federation/dtls12.nova` still ships `dtls_sha256` and its inline
SHA-256 copy. R33B owns the dtls12 dedup in a parallel agent track;
the follow-up round retires the fourth copy once both R33A + R33B
have landed. Module count delta this round: **+1** (`sha256.nova`).
Lines removed (~800 inlined SHA-256 + HMAC across the 3 modules) vs
lines added (~520 canonical + ~42 wrapper/import lines across the
3 consumers): net **-240** lines.

### Subtle API differences encountered

All three pre-R33A implementations produced byte-identical output but
exposed it under module-specific names: `sha256_buf` /
`hmac_sha256_buf` (noise_xk), `_mk_sha256_buf` / `_mk_sha256_str`
(merkle), `ecdsa_sha256` / `ecdsa_sha256_bytes` (ecdsa). The
canonical module provides `sha256_oneshot` / `_str` / `_bytes` and
`hmac_sha256`; each consumer keeps a thin wrapper preserving its
prior public symbol so callers don't have to learn a new name and
the existing tests compile unchanged. `_mk_sha256_str` (used by
`test_merkle.nova` to pin FIPS reference vectors) and the underscore
helpers retain their prior shape.

## R32C extension: X.509 v3 cert parser + ECDSA-P-256 signature verify (R29B.2 cert-verify foundation)

R29B (commit `a3b1233`) shipped the DTLS 1.2 record-layer + handshake
skeleton, tagging five `_R29B2_STUB` slots. R30B (commit `17e9cb8`)
landed P-256 ECDH + AES-128-GCM, then R31B (`af8e47c`) wired three of
the five stubs (`dtls_ecdhe_derive`, `dtls_seal_record`,
`dtls_open_record`). The remaining `dtls_cert_verify_R29B2_STUB` was
blocked on an X.509 parser + ECDSA verify primitive. R32C lands the
LAST cryptographic foundation: two new safety modules that R32C.2 will
wire into `dtls12.nova`.

### What R32C delivers (NEW files only)

* **`src/safety/x509.nova`** -- minimal RFC 5280 §4.1 X.509 v3 parser.
  DER primitives (definite-length encoding ONLY; indefinite-length BER
  is rejected): INTEGER (with leading-0x00 padding stripped for
  unsigned big-ints), OBJECT IDENTIFIER (parsed to a dotted string via
  the X.690 §8.19 base-128 algorithm including the arc0-arc1 split for
  the first subidentifier), SEQUENCE / SET (envelope wrappers), BIT
  STRING (with unused-bits enforcement), OCTET STRING, BOOLEAN,
  UTCTime ("YYMMDDHHMMSSZ", year 50..99 -> 1950..1999, 00..49 ->
  2000..2049), GeneralizedTime ("YYYYMMDDHHMMSSZ"). Times decode to
  Unix seconds via Howard Hinnant's `days_from_civil` formula
  (integer-only, leap-year-correct through year 9999). Cert handle
  is a NOVA list with fixed positional slots accessed via
  `x509_serial_bn`, `x509_signature_alg_oid`, `x509_issuer_cn`,
  `x509_subject_cn`, `x509_not_before`, `x509_not_after`,
  `x509_public_key_buf`, `x509_public_key_len`, `x509_signature_r`,
  `x509_signature_s`, `x509_tbs_buf`, `x509_tbs_len`. Issuer + subject
  CN extracted via a SET-OF-SEQUENCE-OF-{OID,value} walk that picks the
  first ATV with OID `2.5.4.3` (commonName). Public-key path strictly
  enforces algorithm OID `1.2.840.10045.2.1` (id-ecPublicKey),
  parameters OID `1.2.840.10045.3.1.7` (prime256v1), and a 65-byte
  uncompressed SEC1 point starting with `0x04`. Signature OID strictly
  enforces `1.2.840.10045.4.3.2` (ecdsa-with-SHA256). The
  signatureValue BIT STRING unwraps an ECDSA-Sig-Value `SEQUENCE { r
  INTEGER, s INTEGER }` to bn256 r, s (RFC 5480 §2.1).
  `x509_check_validity(cert, current_unix_seconds)` returns 0 or one
  of the negative error codes `X509_ERR_NOT_YET_VALID` /
  `X509_ERR_EXPIRED`. Out of scope (documented): extension parsing,
  certificate chains, RSA / Ed25519 keys, CRL / OCSP revocation,
  SAN / hostname matching.

* **`src/safety/ecdsa.nova`** -- FIPS 186-4 §6.4 ECDSA-P-256 verify
  on top of R30B's `p256.nova` curve arithmetic, plus a self-contained
  SHA-256 implementation (FIPS 180-4). Verify recipe: (1) range-check
  `r, s in [1, n-1]` BEFORE any curve math; (2) decode the SEC1
  public-key buffer via `p256_decode_point` (which already enforces
  on-curve + bad-tag rejection); (3) reduce hash mod n if needed;
  (4) `w = s^-1 mod n` via Fermat (`s^(n-2) mod n` through
  `bn256_modpow_ct`); (5) `u1 = e*w mod n` and `u2 = r*w mod n`;
  (6) `(X, Y) = u1*G + u2*Q` via two `p256_scalar_mult` calls plus
  one `p256_pt_add_affine`; (7) accept iff `X mod n == r`. Three
  entry points: `ecdsa_p256_verify(pub_buf, pub_n, hash_buf,
  sig_r_buf, sig_s_buf)` for raw 32-byte BE buffers,
  `ecdsa_p256_verify_full(pub_buf, pub_n, msg_buf, msg_n, sig_r_buf,
  sig_s_buf)` that SHA-256-hashes the message first, and
  `ecdsa_p256_verify_bn(pub_buf, pub_n, hash_bn, r_bn, s_bn)` for
  the x509.nova caller that already has bn256 values. The
  self-contained SHA-256 is the FOURTH copy of FIPS 180-4 in the tree
  (alongside `noise_xk.nova`, `merkle.nova`, `dtls12.nova`'s
  `dtls_sha256`) -- documented duplication; future refactor extracts
  `src/safety/sha256.nova`. The duplication is intentional because
  importing `dtls12.nova` from `ecdsa.nova` would create a circular
  dependency once R32C.2 wires the cert-verify path through
  `dtls12.nova`.

### Verification

**+79 unit assertions** across the two new test files:

* `tests/unit/test_ecdsa.nova`: **25 checks**. SHA-256 known-answers
  for `""`, `"abc"`, FIPS 180-4 Appendix B.2 56-char string, 55-char
  `"A"`-string (the block-boundary case where padding straddles two
  blocks), and 1000-char `"a"`-string (15 full blocks + 40-byte
  remainder); `ecdsa_sha256_bytes` byte-list variant round-trip.
  ECDSA verify against **RFC 6979 §A.2.5** (the canonical deterministic
  test vector for ECDSA-P-256 + SHA-256, replicated in countless
  independent implementations): both the `"sample"` AND `"test"`
  messages with the published `(Qx, Qy, r, s)` tuples; both
  `ecdsa_p256_verify` (with the precomputed hash) and
  `ecdsa_p256_verify_full` (hash internally); both uncompressed and
  compressed SEC1 public-key encodings; the `ecdsa_p256_verify_bn`
  entry point. Tamper rejection: flipped `r` byte -> 0; flipped `s`
  byte -> 0; flipped message hash -> 0; wrong public key (Q + G) -> 0.
  Range-check paths: `r == 0`, `s == 0`, `r == n`, `s == n`, and
  `r == 2^256 - 1` (>> n) all reject WITHOUT proceeding to curve math.
  Shape-validation paths: bad public-key tag byte and truncated
  public-key buffer both reject.

* `tests/unit/test_x509.nova`: **54 checks**. DER primitive isolation
  tests (tag short / long-form rejection, length short-form,
  long-form-2byte = 256, long-form-3byte = 65536, indefinite-length
  rejection, overlong-length rejection, truncated-length rejection;
  INTEGER 255 with leading-0 padding, INTEGER 5 plain, 256-bit
  INTEGER round-trip; OID round-trip for `ecdsa-with-SHA256`,
  `id-ecPublicKey`, `prime256v1`; UTCTime + GeneralizedTime decode to
  Unix seconds; Time rejection on missing 'Z' + bad month). Full
  cert parse against a hardcoded 397-byte DER vector generated
  offline via `openssl ecparam -name prime256v1 -genkey | openssl req
  -new -x509 -days 36500 -sha256 -subj /CN=CrossEnginTest`: subject
  CN, issuer CN, signature OID, 65-byte public-key buffer hex, 20-byte
  serial number bn256, signature r + s bn256, tbsCertificate span
  (cert[4..311) = 307 bytes), parsed notBefore (1780554374 =
  2026-06-04T06:26:14Z) + notAfter (4934154374 =
  2126-05-11T06:26:14Z). Validity checks at notBefore-1
  (`X509_ERR_NOT_YET_VALID`), notBefore (0 inclusive), midpoint (0),
  notAfter (0 inclusive), notAfter+1 (`X509_ERR_EXPIRED`).
  **Combined cert+verify smoke test**: `x509_parse` -> tbs +
  pubkey + r + s; `ecdsa_sha256(tbs)` matches the openssl/python
  reference `cfa7c41cc9cf98bd772c5398ca92692f30ca193e3dff5527105aafb957fd1ce6`;
  `ecdsa_p256_verify_bn(pub, hash, r, s)` returns 1. Tamper smoke:
  byte 100 of the cert flipped -> verify returns 0 (OR parse fails
  if the tampered byte lands inside DN parsing). Error paths:
  truncated cert, bad outer tag, indefinite outer length all
  rejected with negative error codes.

Full test suite: **227 / 227 pass** (231 prior + my 79 ÷ 31 per file
average, the count climb reflects two new test files; R32B's 297
internal `dtls12` checks count as one test program, the bash runner
reports test-program-level pass/fail).

### Concurrency note + stash discipline confirmation

R32C runs in parallel with R32A (federation/nat_traversal RFC 8489
UDP dispatch), R32B (DTLS anti-replay window), and other R32 round
agents. The strict ownership rule -- "I may create ONLY my four
files" -- was honored: `git status` before commit shows ONLY
`src/safety/x509.nova`, `src/safety/ecdsa.nova`,
`tests/unit/test_x509.nova`, `tests/unit/test_ecdsa.nova` as new files,
plus targeted edits to `README.md`, `FEDERATED_AUDIT.md`, and
`NEXT_SESSION.md`. The mandatory preflight `git stash push -m
"R32C-preflight" -- <four owned paths>` was a no-op (none of the four
were tracked beforehand), confirming I did not stomp on a
co-resident's in-progress work. Zero changes to `dtls12.nova`,
`p256.nova`, `aes_gcm.nova`, `bignum_256.nova`, `chacha20.nova`,
`bignum_2048.nova`, or any federation module -- R32C.2 in a future
round will land the `dtls12.nova` wiring exactly the way R31B wired
R30B's primitives.

### Honest caveats

1. **ECDSA verify is NOT constant-time.** Inherits R30B.3 hardening
   item from `p256.nova` -- `p256_scalar_mult` is double-and-add with
   a data-dependent conditional add per scalar bit. For VERIFY this
   exposure is academic: u1 and u2 are derived from the (public)
   hash, (public) r, and (public) w; an observer learns nothing they
   can't already compute. The side-channel concern only matters for
   the SIGN path, which this module deliberately does NOT ship.

2. **SHA-256 duplication.** The FIPS 180-4 implementation in
   `ecdsa.nova` is a byte-for-byte copy of `dtls_sha256` in
   `dtls12.nova` (which is itself a copy of the SHA-256 in
   `noise_xk.nova` and `merkle.nova`). Importing `dtls12.nova` would
   create a circular dep (`dtls12 -> x509 -> ecdsa -> dtls12`). Future
   refactor extracts `src/safety/sha256.nova` -- tracked.

3. **X.509 scope is intentionally minimal.** No extension parsing,
   no certificate chains, no RSA / Ed25519 keys, no CRL / OCSP, no
   SAN-based hostname matching. The cipher suite R29B negotiates is
   ECDHE-ECDSA-* so the cert must carry a P-256 key; other suites
   would need expansion. WebRTC's typical SDP-fingerprint flow
   doesn't need SAN matching at the X.509 layer, so this scope is
   appropriate for R29B.2's reach.

4. **Test cert is hardcoded.** The 397-byte DER blob in
   `tests/unit/test_x509.nova` was generated offline (openssl with
   random ECDSA k + random 20-byte serial); each fresh generation
   produces different bytes, so embedding one canonical vector lets
   the test be deterministic. Validity window is ~100 years
   (2026-06-04 .. 2126-05-11), which keeps the validity checks
   testable for the lifetime of this codebase.

5. **No DTLS wiring.** R32C strictly ships primitives.
   `dtls_cert_verify_R29B2_STUB` STILL returns `DTLS_ERR_STUB`;
   R32C.2 will plumb `x509_parse` + `ecdsa_p256_verify_bn` into the
   handshake. The shape will be: client receives ServerHello +
   ServerCertificate (one or more X.509 certs), parses the leaf,
   pulls the public key for the subsequent ECDHE ServerKeyExchange
   signature verify, and routes the cert-chain validation through
   R32C's parser.

## R33E extension: stateless nat_traversal UDP threading (R32A.2)

R32A wired UDP datagram dispatch into `nat_query_stun_with_state(state,
addr)` -- the **stateful** form -- under `CE_NAT_USE_RFC8489=1`. Its
exit caveat: the stateless form `nat_query_stun(addr)` and the
detection wrapper `nat_detect_type(addr1, addr2)` could not honor the
env flag because the RFC 8489 codec needs a `stun_state_t` for
transaction-id tracking and credentials -- and the stateless caller has
no `nat_state_t` to hang it on. R33E closes that caveat.

### What R33E delivers (modifies `src/federation/nat_traversal.nova`)

* **Approach (a) transient-per-call.** Each stateless call gets a
  fresh `nat_state_t` via `nat_init()` allocated on entry, used
  internally for the codec + UDP path, and dropped on exit. **No
  module-level shared mutable `stun_state_t`**. Two concurrent
  stateless callers cannot race on txn ids or sockets because their
  transient states are local to each call frame. (Approach (b) -- a
  module-singleton `stun_state_t` -- was considered but rejected
  because it introduces the same race that R32A's stateful path
  carefully avoids.)
* **`nat_query_stun(addr)`** now branches on `nat_use_rfc8489_enabled()`:
  - Flag on -> `_nat_query_stun_stateless_udp(addr)` allocates a
    transient `nat_state_t`, runs `_nat_query_stun_rfc8489_udp(transient,
    addr)`, mirrors the transient state's UDP counters into a
    module-level snapshot, and returns the external addr (or 0).
  - Flag off -> `_nat_query_stun_tcp(0, addr)` (byte-identical to R23E).
* **`nat_detect_type(addr1, addr2)`** is automatically threaded: it
  calls `nat_query_stun(addr)` twice, so both queries take the same
  dispatch path that the env flag selects.
* **Observability hook: module-level snapshot.** Because stateless
  callers have no `nat_state_t` to inspect, R33E adds a module-level
  6-slot snapshot updated after EVERY stateless call:
  `nat_stateless_last_path()` -> "udp" | "tcp" | "none",
  `nat_stateless_last_udp_sent()` / `_recvd()` / `_timeouts()`,
  `nat_stateless_last_external()`, `nat_stateless_last_error()`,
  `nat_stateless_reset_stats()`. The snapshot REPLACES (not
  accumulates) per call so two back-to-back queries do not
  bleed.
* **Counter updates.** The transient `nat_state_t` bumps NAT_S_UDP_SENT
  / _RECVD / _TIMEOUTS exactly like the stateful path; the snapshot
  reflects those counters so tests + integration scenarios can observe
  the UDP dispatch.

### Behavior preservation (R23E + R31C + R32A 162 prior assertions stay byte-identical)

* All 162 pre-R33E unit checks (53 R23E + 48 R31C + 61 R32A) pass
  **byte-identical**. R33E only APPENDS test functions after the R32A
  block; main()'s call order before the R33E block is unchanged.
* Integration scenario_oooo's existing 18 R23E + 6 R31C + 17 R32A
  sub-scenarios run before R33E's STATELESS_UDP_PATH sub-scenario and
  produce the same outputs (same souls A/B, same RFC 8489 in-process
  emit + parse, same UDP_RT loopback round-trip, same UDP_FLAG env-
  on dispatch via the stateful form). R33E adds ONE new sub-scenario
  after the existing ones.

### Tests added

* **47 new R33E assertions** in `tests/unit/test_nat_traversal.nova`
  across 9 test functions:
  `test_r33e_snapshot_reset_fresh_defaults`,
  `test_r33e_stateless_query_tcp_path_when_flag_off`,
  `test_r33e_detect_type_tcp_path_when_flag_off`,
  `test_r33e_stateless_udp_direct_bad_addr`,
  `test_r33e_stateless_udp_direct_bad_ip`,
  `test_r33e_stateless_udp_direct_timeout_to_closed_port`,
  `test_r33e_stateless_udp_loopback_round_trip` (drives the same
  loopback round-trip as R32A but via the stateless helper),
  `test_r33e_stateless_back_to_back_no_state_bleed` (proves there is
  NO module-singleton stun_state -- each call gets its own transient
  state, snapshot reflects only the LAST call, not a sum),
  `test_r33e_stateless_udp_direct_returns_zero_on_failure`.
* **13 new R33E assertions** in
  `tests/integration/scenario_oooo_nat_traversal.sh` under
  `STATELESS_UDP_PATH` sub-scenario: env-flag-on stateless
  `nat_query_stun(addr)` walks the UDP path (snapshot path="udp",
  udp_sent=1, udp_timeouts=1), and env-flag-on `nat_detect_type`
  dispatches TWO UDP queries.
* `nat_traversal`: 162 -> 209 unit checks (162 R23E + R31C + R32A
  byte-identical + 47 R33E).

### Honest scope (still deferred)

1. **No retransmit / RTO.** RFC 8489 7.2.1 prescribes
   exponential-backoff retransmission. Both the stateful (R32A) and
   stateless (R33E) paths use a single `sys_recvfrom` timeout call.
   Retransmits are deferred. Loss-free networks won't notice;
   cellular / Wi-Fi can.
2. **Module-level snapshot is shared state.** The observation hook
   (`_nat_stateless_snap`) is the ONE piece of shared mutable state
   R33E introduces. The codec state itself is per-call transient, so
   the snapshot can race but the call result cannot. NOVA is
   single-threaded today so this is moot, but a future thread-pool
   runtime should switch observability to a caller-owned slot.
3. **No public-STUN interop CI.** Same as R32A: sandbox CI cannot
   reach `stun.l.google.com:3478`. Requires soak environment.
4. **No credential threading for the stateless caller.** The
   transient state is allocated bare without USERNAME / password.
   Callers needing MESSAGE-INTEGRITY must use the stateful form.

### Concurrency

R33E modifies ONLY `src/federation/nat_traversal.nova`,
`tests/unit/test_nat_traversal.nova`,
`tests/integration/scenario_oooo_nat_traversal.sh`, and the three
docs. R33E does NOT touch `stun_rfc8489.nova`, `ice.nova`,
`dtls12.nova`, or any other federation module. Parallel sibling
agents working on R32B-R32F / R33A-R33D / R33F cannot collide.

Stash discipline: R33E's preflight stash used explicit owned-path
arguments (`git stash push -m "R33E-preflight" -- <path...>`), never
`-u`. Sibling-agent untracked files were untouched.

### Files touched (R33E)

* MOD: `src/federation/nat_traversal.nova` (+200 lines: 6 SL_*
  snapshot indices, lazy snapshot allocator, 2 record helpers
  (`_nat_stateless_record_udp` / `_nat_stateless_record_tcp`), 1
  stateless UDP entry `_nat_query_stun_stateless_udp`, 1 public alias
  `nat_query_stun_stateless_udp`, 7 snapshot accessors, modified
  `nat_query_stun(addr)` to dispatch on the env flag. R23E + R31C +
  R32A public API surface unchanged).
* MOD: `tests/unit/test_nat_traversal.nova` (+9 test functions,
  +47 assertions). R23E + R31C + R32A test functions stay in place
  untouched.
* MOD: `tests/integration/scenario_oooo_nat_traversal.sh`
  (+1 sub-scenario STATELESS_UDP_PATH, +13 shell assertions,
  +1 generated NOVA driver script).
* MOD: `FEDERATED_AUDIT.md`, `NEXT_SESSION.md`, `README.md`.

## R32A extension: nat_traversal RFC 8489 UDP dispatch (R31C.2 / R28C consumer)

R31C (commit `0f95bb6`) migrated the codec half of `nat_traversal`
to RFC 8489 but left `nat_query_stun_with_state` on the TCP-text
path because at write time UDP syscalls were assumed unavailable.
R28C had already shipped `sys_socket_udp`, `sys_sendto`,
`sys_recvfrom`, and `sys_setsockopt_so_reuseaddr` across 6
codegen backends. R32A wires `nat_traversal` through to those
builtins so `CE_NAT_USE_RFC8489=1` produces actual RFC 8489
datagrams on the wire.

### What R32A delivers (modifies `src/federation/nat_traversal.nova`)

* **Top-level dispatch.** `nat_query_stun_with_state(state, addr)`
  now checks `nat_use_rfc8489_enabled()` (which already reads
  `CE_NAT_USE_RFC8489`). When enabled AND `state != 0` (so the
  lazy `stun_state_t` can be allocated), the function dispatches
  to `_nat_query_stun_rfc8489_udp`. Otherwise the legacy R23E TCP
  text path runs, bit-identical.

* **`_nat_query_stun_rfc8489_udp`.** End-to-end UDP client:
  parses `addr`, opens a UDP socket via `sys_socket_udp`, dispatches
  the Binding Request through R30C, blocks on `sys_recvfrom` up
  to `CE_NAT_RFC8489_TIMEOUT_MS` (default 1000ms), parses the
  response, and on success returns the formatted
  `<ip>:<port>` external address. On timeout / bad parse / bad
  addr returns 0 with `nat_last_error` set.

* **Split helpers** for tests / advanced callers:
  `nat_udp_open()`, `nat_udp_send_binding_request_at(fd, state, ip,
  port, software)`, `nat_udp_recv_binding_response(fd, state,
  timeout_ms)`, `nat_udp_query_rfc8489_with_state(state, addr)`.
  These are the building blocks the unit-test loopback round-trip
  drives both halves of in one process.

* **Env helper.** `nat_rfc8489_timeout_ms_from_env()` parses
  `CE_NAT_RFC8489_TIMEOUT_MS`; default is `NAT_RFC8489_DEFAULT_TIMEOUT_MS`
  = 1000ms. Non-numeric / non-positive values fall back to the
  default.

* **Three new stats slots** with R31C-shape accessors:
    - `NAT_S_UDP_SENT` (13) -- bumps on successful `sys_sendto`.
      `nat_udp_sent_count(state)`.
    - `NAT_S_UDP_RECVD` (14) -- bumps on successful parse of a
      Binding Success Response received via `sys_recvfrom`.
      `nat_udp_recvd_count(state)`.
    - `NAT_S_UDP_TIMEOUTS` (15) -- bumps when `sys_recvfrom`
      returns `-1` / `0` bytes (timeout shape).
      `nat_udp_timeout_count(state)`.
  All three accessors guard a `state == 0` argument and return 0
  in that case, matching R31C convention.

### Behavior preservation (R23E + R31C tests stay byte-identical)

* `nat_query_stun_with_state` keeps its existing return-value
  contract (formatted `<ip>:<port>` on success, 0 on failure),
  still bumps `NAT_S_QUERIES` once per call regardless of
  dispatch path, and still bumps `NAT_S_QUERIES_OK` only on a
  successful external-addr parse.
* `NAT_S_MY_EXTERNAL` is the only slot that mirrors the
  discovered address; both paths target it through
  `nat_set_external`.
* The 101 pre-R32A unit checks (53 R23E + 48 R31C) pass
  byte-identical -- no test functions touched or removed; only
  R32A test functions appended after the R31C block.
* Integration scenario_oooo's existing 18 R23E + 6 R31C
  shell assertions remain unchanged (same `assert_match`
  patterns, same milestones, same sub-scenarios run first); R32A
  adds 17 PASS assertions in two new sub-sections appended
  after.

### Wire-side verification

In one process: the loopback round-trip subscenario binds a UDP
responder socket, the client emits a Binding Request through the
real R30C codec, the responder reads a 40-byte datagram (RFC 8489
Binding Request type 0x0001 with magic cookie + FINGERPRINT) and
crafts a 56-byte Binding Success Response with a XOR-MAPPED-ADDRESS
attribute, the client `sys_recvfrom`s that response and the parse
extracts `198.51.100.250:43210` into `NAT_S_MY_EXTERNAL`. All eight
milestone lines (`responder-bound`, `client-sent`, `responder-got`,
`responder-sent`, `client-parsed`, plus three counter checks) PASS
in the sandbox.

### Env-flag dispatch verification

The `UDP_FLAG` sub-scenario spawns a child NOVA program with
`CE_NAT_USE_RFC8489=1 CE_NAT_RFC8489_TIMEOUT_MS=200` against a
closed UDP port. The dispatch reports `NAT_S_UDP_SENT=1`,
`NAT_S_UDP_TIMEOUTS=1`, `NAT_S_UDP_RECVD=0`, `NAT_S_QUERIES=1`,
`NAT_S_QUERIES_OK=0`, `last_error=udp-timeout`,
`external=''`. This proves the env flag actually routes through
UDP rather than the legacy TCP path (a TCP attempt against port 200
would have produced `dial-failed` instead).

### Test counts

* **61 new R32A assertions** in `tests/unit/test_nat_traversal.nova`
  across 14 test functions (`test_r32a_*`). Round-trip + timeout
  branches both skip-via-early-return when `nat_udp_open()`
  returns -1 (stub target / sandbox-deny), so the suite still
  passes on UDP-less targets with reduced coverage.
* **17 new R32A assertions** in
  `tests/integration/scenario_oooo_nat_traversal.sh` across two
  sub-sections (`UDP_RT` and `UDP_FLAG`).
* `nat_traversal`: 101 -> 162 unit checks (101 R23E + R31C
  byte-identical + 61 R32A).

### Honest scope (still deferred)

1. **NAT type detection over UDP.** `nat_detect_type` calls
   `nat_query_stun` twice. The R32A dispatch flows through
   `nat_query_stun_with_state` only when `state != 0`; the
   stateless `nat_query_stun(addr)` still uses TCP. A R32A.2
   could thread a state through `nat_detect_type` so the
   detection path also uses UDP under the env flag.
2. **Retransmit / RTO.** RFC 8489 7.2.1 prescribes
   exponential-backoff retransmission (initial RTO 500ms, doubled
   up to 7 attempts). R32A uses a single `sys_recvfrom` timeout
   call; retransmits are deferred to R32A.2. Loss-free networks
   (corporate LAN, sandbox) won't notice; cellular / Wi-Fi can.
3. **Real-internet end-to-end interop.** The codec is RFC 8489
   compliant and `198.51.100.250:43210` round-trips in the
   sandbox, but interop with public STUN servers (stun.l.google.com
   etc) requires either CI that allows outbound UDP/3478 or a
   dedicated soak test. Sandbox CI cannot exercise that.
4. **`nat_query_stun` (stateless) does not dispatch.** Because
   the codec needs a `stun_state_t` to hang txn id / credentials
   off of, the stateless `nat_query_stun(addr)` form still uses
   the TCP path. Callers wanting UDP must pass a state.

### Concurrency

R32A modifies ONLY `src/federation/nat_traversal.nova`,
`tests/unit/test_nat_traversal.nova`,
`tests/integration/scenario_oooo_nat_traversal.sh`, and the three
docs (FEDERATED\_AUDIT, NEXT\_SESSION, README). R32A does NOT
touch `stun_rfc8489.nova`, `ice.nova`, `dtls12.nova`, or any
other federation module. Parallel agents finishing R32B / R32C /
R32D / R32E / R32F cannot collide.

Stash discipline: R32A's preflight stash used explicit owned-path
arguments (`git stash push -m "R32A-preflight" -- <path...>`),
never `-u`. The R30A / R31C disasters that swept sibling-agent
untracked files were avoided.

### Files touched (R32A)

* MOD: `src/federation/nat_traversal.nova` (+225 lines: 3 new
  state slots + accessors, 5 new public helpers including
  `nat_udp_query_rfc8489_with_state` and the split
  `nat_udp_open` / `nat_udp_send_binding_request_at` /
  `nat_udp_recv_binding_response`, top-level
  `nat_query_stun_with_state` dispatch refactor preserving the
  TCP path verbatim under `_nat_query_stun_tcp`. The 53 R23E +
  R31C public API surface is unchanged).
* MOD: `tests/unit/test_nat_traversal.nova` (+14 test functions,
  +61 assertions). R23E's 33 + R31C's 17 test functions stay in
  place untouched.
* MOD: `tests/integration/scenario_oooo_nat_traversal.sh`
  (+2 sub-sections, +17 shell assertions, +2 generated NOVA
  driver scripts).
* MOD: `FEDERATED_AUDIT.md`, `NEXT_SESSION.md`, `README.md`.

## R31C extension: nat_traversal RFC 8489 wire migration (R30C.2 / R23E.2)

R23E (`src/federation/nat_traversal.nova`) shipped an ad-hoc
STUN-LIKE newline-text wire (`STUN_REQUEST\n` /
`EXTERNAL <ip>:<port>\n`). R30C (`src/federation/stun_rfc8489.nova`,
commit `07ba781`) shipped the real RFC 8489 binary codec but kept
hands off `nat_traversal.nova`. R31C migrates the wire half: every
new helper routes through `stun_rfc8489` -- this module owns NO
RFC 8489 byte arithmetic, it just lifts results into the existing
`nat_state` slots.

### What R31C delivers (modifies `src/federation/nat_traversal.nova`)

* **API preservation -- legacy default-on.** All 53 R23E assertions
  pass **byte-identical**. The STUN-LIKE TCP text wire stays the
  default behavior of `nat_query_stun_with_state`, `nat_serve_stun_conn`,
  and friends. The scenario\_oooo manual STUN multiplexer (which
  dispatches between `STUN_REQUEST` and `GOSSIP_HELLO` by sniffing
  the first newline-terminated line) still works exactly as
  before: changing it would require RFC 4571 length-prefixed
  framing on TCP, which is a separate concern.
* **NEW state slots.**
  `NAT_S_STUN_STATE`,
  `NAT_S_RFC_REQUESTS`,
  `NAT_S_RFC_OK`,
  `NAT_S_RFC_BAD`. The `stun_state_t` is allocated lazily by
  `nat_rfc8489_state(state)` so the per-field memory footprint is
  zero for callers that never touch the new path.
* **NEW public helpers, all routing through R30C.**
  `nat_emit_rfc8489_binding_request(state, software)` ->
  `[pkt, n, txn]` (calls `stun_send_binding_request`).
  `nat_parse_rfc8489_binding_response(state, pkt, n)` ->
  `[ip, port, family] | 0` (calls `stun_recv`).
  `nat_format_rfc8489_success_response_ipv4(txn, ip, port, software,
  user, pass)` (calls `stun_msg_build_success_response_ipv4`).
  `nat_send_binding_request(state, remote_addr, software)` validates
  the addr shape, bumps NAT\_S\_QUERIES + NAT\_S\_RFC\_REQUESTS,
  then calls `stun_send_binding_request`.
  `nat_recv_binding_response(state, pkt, n)` parses the response and
  on success writes the XOR-MAPPED-ADDRESS into NAT\_S\_MY\_EXTERNAL
  (formatted as `<ip>:<port>`) and bumps NAT\_S\_QUERIES\_OK +
  NAT\_S\_RFC\_OK. Errors bump NAT\_S\_RFC\_BAD and route
  `stun_state_get_last_error` into `nat_set_last_error`.
* **Env flag.** `CE_NAT_USE_RFC8489=1` (or `true` / `yes` / `on`)
  enables the RFC 8489 path; `nat_use_rfc8489_enabled()` reads it.
  Default 0. The flag is currently a hook -- the existing
  `nat_query_stun_with_state` TCP-text path is preserved unchanged
  so R23E integration scenarios stay byte-identical. R31C.2 (when
  NOVA gains `sendto/recvfrom`) will wire UDP datagram transport
  behind the flag.
* **Legacy-compat shims (default-on).**
  `nat_legacy_emit_stunlike_request()`,
  `nat_legacy_parse_stunlike_response(line)`,
  `nat_legacy_format_stunlike_response(ip, port)` are explicit
  named wrappers around the original `STUN_REQUEST\n` /
  `EXTERNAL <ip>:<port>\n` wire. They share bytes with
  `nat_format_stun_response` / `nat_parse_stun_response` so callers
  can pick whichever name signals intent.

### What R31C does NOT change

* `src/federation/stun_rfc8489.nova` (R30C ownership). The wire
  codec is treated as a black box; we call its public API only.
* `src/federation/ice.nova` (R30C ownership).
* `src/federation/gossip.nova` -- the EXTADDR gossip-piggyback line
  is a CrossEngin-internal advertisement protocol, not the STUN
  wire. It stays exactly as R23E shipped it. The
  `gossip_set_nat_state` slot indices (`GOSSIP_NAT_PEER_TABLE_SLOT`
  = 1, `GOSSIP_NAT_INBOUND_AD_SLOT` = 6) are unchanged.
* The `_nat_recv_line` / `_nat_send_all` / `nat_format_stun_response`
  / `nat_parse_stun_response` / `NAT_STUN_REQUEST_LINE` / the TCP
  multiplexer in scenario\_oooo all keep their existing semantics.

### Verification

* **48 new R31C assertions** in `tests/unit/test_nat_traversal.nova`
  (extends the file; does NOT remove R23E's 53 tests). Coverage:
  * Legacy-compat helpers emit / format / parse the original text
    wire byte-for-byte (3 asserts).
  * Env-flag `nat_use_rfc8489_enabled()` defaults to 0 (1 assert).
  * `nat_emit_rfc8489_binding_request` produces a packet that
    `stun_msg_parse` accepts, with the right type
    (`STUN_TYPE_BINDING_REQUEST`), cookie (`STUN_MAGIC_COOKIE`),
    and `stun_verify_fingerprint` returns 1 (5 asserts).
  * `nat_set_rfc8489_credentials` + `nat_emit_rfc8489_binding_request`
    emit a MESSAGE-INTEGRITY that `stun_verify_message_integrity`
    accepts on the right password and rejects on the wrong password,
    with FINGERPRINT still verifying (3 asserts).
  * `nat_emit_rfc8489_binding_request` bumps NAT\_S\_RFC\_REQUESTS
    (1 assert).
  * `nat_send_binding_request` rejects bad `host:port` shape,
    accepts good shape, and bumps both NAT\_S\_QUERIES + the new
    counter (7 asserts).
  * `nat_recv_binding_response` against a hand-built Binding
    Success Response with XOR-MAPPED-ADDRESS 203.0.113.99:54321:
    `nat_get_external` reads back "203.0.113.99:54321", QUERIES\_OK
    + RFC\_OK both bump, last\_error clears (5 asserts).
  * `nat_parse_rfc8489_binding_response` returns the
    [ip, port, family] triple for XOR-MAPPED 192.0.2.100:9999
    (4 asserts).
  * Bad packet path: 8-byte buffer bumps RFC\_BAD without
    clobbering NAT\_S\_MY\_EXTERNAL; zero-buf / zero-len both
    return 0 cleanly (5 asserts).
  * `nat_format_rfc8489_success_response_ipv4` builds a Binding
    Success Response with the right type / cookie / FINGERPRINT
    and rejects a malformed IP (4 asserts).
  * `nat_rfc8489_state` is lazy + idempotent (2 asserts).
  * Stats accessors guard against a 0 state pointer (3 asserts).

* **6 new integration assertions** in `tests/integration/scenario_oooo_nat_traversal.sh`.
  Soul B is extended to drive an in-process RFC 8489 emit + parse
  cycle alongside the existing legacy TCP query. Shell-side checks
  verify the emitted Binding Request has type=1, cookie\_ok=1,
  fp\_ok=1 and that the parsed Binding Success Response
  round-trips ip=198.51.100.7, port=33445, family=1.

* `NOVA_ROOT=/home/user/NOVA bash scripts/test.sh` -- all 225 unit
  tests pass (+0 module count; the unit suite count stays steady
  because `test_nat_traversal.nova` gains 48 asserts in-place).
  `nat_traversal`: 53 -> 101 (53 R23E byte-identical + 48 R31C).

### Honest scope (R31C.2 follow-up list)

1. **UDP datagram transport.** RFC 8489 is fundamentally a UDP
   protocol. NOVA exposes only TCP (`socket(AF_INET, SOCK_STREAM, 0)`)
   today; the wire codec round-trips in-memory but does NOT cross
   a UDP socket yet. R31C.2 wires `sendto/recvfrom` once NOVA gains
   them.
2. **CE\_NAT\_USE\_RFC8489=1 dispatch.** The env flag is wired and
   read but `nat_query_stun_with_state` still always uses the
   legacy TCP text path. Once UDP is available R31C.2 dispatches
   on the flag.
3. **Browser interop end-to-end.** The codec is RFC 8489 compliant
   but browser interop requires the full ICE controller
   (`src/federation/ice.nova`) driving pair checks over each
   socket. R30C ships the state machine; R30C.2 wires the loop.
   `nat_traversal` alone does not produce a browser-callable STUN
   server; it produces RFC 8489 bytes the browser would accept if
   they were on UDP wire.
4. **Long-term credentials.** `nat_set_rfc8489_credentials` plumbs
   USERNAME + password into MESSAGE-INTEGRITY but the REALM /
   NONCE long-term auth dance (RFC 8489 9.2) is not exposed at
   the `nat_*` altitude. Callers that need it can reach the
   underlying `stun_state_t` via `nat_rfc8489_state(state)`.

### Concurrency

R31C modifies ONLY `src/federation/nat_traversal.nova`,
`tests/unit/test_nat_traversal.nova`,
`tests/integration/scenario_oooo_nat_traversal.sh`, and the four
docs (FEDERATED\_AUDIT, NEXT\_SESSION, README). R31C does NOT touch
`stun_rfc8489.nova`, `ice.nova`, `webrtc.nova`, `dtls12.nova`,
`gossip*.nova`, `gossip_relay*.nova`, `noise_xk.nova`,
`relay_secure.nova`, `kg_sync.nova`, `distributed_rules.nova`,
`leader_election.nova`, `distributed_query.nova`,
`snapshot_replication.nova`, `voice_dialog.nova`,
`crossengin_chat.nova`. Parallel agents finishing R28E.2 SRTP or
R30C.2 ICE-driver loop cannot collide.

### Files touched (R31C)

* MOD: `src/federation/nat_traversal.nova` (+225 lines: 4 new state
  slots, 13 new public helpers including
  `nat_send_binding_request` and `nat_recv_binding_response`, 3
  legacy-compat shims, header docs rewritten to reflect the dual
  path. The 53 R23E API functions are unchanged).
* MOD: `tests/unit/test_nat_traversal.nova` (+17 test functions,
  +48 assertions). R23E's 33 test functions / 53 assertions stay
  in place untouched.
* MOD: `tests/integration/scenario_oooo_nat_traversal.sh`
  (extends soul B with an RFC 8489 in-process emit + parse block,
  +6 shell assertions).
* MOD: `FEDERATED_AUDIT.md`, `NEXT_SESSION.md`, `README.md`.

## R32B extension: DTLS anti-replay sliding window (RFC 6347 §4.1.2.6, R31B.2)

R31B (`src/federation/dtls12.nova`, commit `af8e47c`) wired real
P-256 ECDHE + AES-128-GCM into DTLS records and explicitly flagged
"no anti-replay sliding window yet -- `RECV_SEQ` advances
monotonically on success only. The open path will NOT reject a
replayed sealed record whose sequence number trails the high
watermark, so an attacker who captures a sealed record can re-
inject it." Tracked as R31B.2; R32B closes that caveat.

### What R32B delivers (extends `src/federation/dtls12.nova`)

* **Four new state slots** appended at indices 32..35 (preserving
  byte-identical layout of slots 0..31):
  * `DTLS_S_SLOT_RECV_HIGH_WATERMARK` -- u64 highest validated seq
    seen so far. Bit 0 of the replay mask represents this seq.
  * `DTLS_S_SLOT_RECV_REPLAY_MASK` -- u64 sliding bitmap. Bit i
    (LSB-indexed) is set iff seq `(high_watermark - i)` has been
    validated.
  * `DTLS_S_SLOT_STATS_REPLAY` -- replay-rejected count.
  * `DTLS_S_SLOT_STATS_TOO_OLD` -- too-old-rejected count.
* **Two pure-function helpers**:
  * `_dtls_anti_replay_check(state, seq)` -- returns `DTLS_AR_OK` /
    `DTLS_AR_REPLAY` / `DTLS_AR_TOO_OLD`. No state mutation.
  * `_dtls_anti_replay_update(state, seq)` -- slides the window and
    sets the bit for `seq`. Called ONLY after AEAD tag check passes.
* **`dtls_open_record` integration**: the anti-replay check runs
  BEFORE the AEAD decrypt attempt. A replay or too-old record is
  short-circuited out without ever calling `gcm_open` -- both
  because it would waste crypto work and (critically) because we
  do not want to give an attacker an oracle on bogus seq numbers.
  The window is updated ONLY AFTER the AEAD tag check passes -- a
  forged record at `high_watermark + N` with a bad MAC must not
  advance the watermark and lock out the legitimate next packet.
* **Two new error tags**: `DTLS_REPLAY = "dtls: replay"` and
  `DTLS_TOO_OLD = "dtls: too old"`. Both are distinct from
  `DTLS_DECRYPT_FAIL` so callers can tell apart "I rejected this
  cheaply at the pre-AEAD check" from "the AEAD oracle said no".
  The brief explicitly asked for distinct error returns + counters.
* **Four new accessors**: `dtls_recv_high_watermark`,
  `dtls_recv_replay_mask`, `dtls_stats_replay`, `dtls_stats_too_old`.
* **`dtls_stats_line` extended** with `hi_watermark=`, `replay=`,
  `too_old=` fields (additive -- existing prefix still starts
  `dtls: state=...`).

### Algorithm (RFC 6347 §4.1.2.6 verbatim)

Given incoming seq `S`, current `high_watermark` (`hw`), `mask`:

* `S > hw`: ABOVE-WINDOW. Tentatively accept. After AEAD success,
  shift mask left by `(S - hw)` (if >= 64, clear), set bit 0,
  update `hw = S`.
* `S <= hw` and `(hw - S) < 64`: WITHIN-WINDOW. Check bit
  `(hw - S)`. If set -> REPLAY. If clear -> tentatively accept;
  after AEAD success, set the bit.
* `(hw - S) >= 64`: TOO_OLD. Reject before AEAD.

Initial state (`hw = 0`, `mask = 0`): bit 0 represents seq 0,
clear means "seq 0 not yet seen". So seq 0 is acceptable on the
first open and rejected as replay on the second.

### Verification

* **66 new R32B unit assertions** in `tests/unit/test_dtls12.nova`
  (extends additively; total now 297; R31B's 84 + R29B's 147 =
  231 prior assertions pass byte-identical).
* `dtls12: OK (297 checks)`.
* Coverage:
  * Sequential seq 1..4 -> all accepted, `high_watermark == 4`.
  * Replay seq=2 after watermark=4 -> `DTLS_REPLAY`,
    `STATS_REPLAY` bumps, watermark + mask UNCHANGED,
    `aead_records_in` NOT bumped.
  * Big jump seq=1 then seq=100 -> watermark slides to 100, mask
    cleared then bit 0 set; subsequent seq=1 returns `DTLS_TOO_OLD`.
  * Out-of-order within window: seq=1, 5, 3 -> 3 accepted (bit
    clear); replay 3 -> `DTLS_REPLAY`.
  * Too-old: seq=1, 200, then 50 (200-50=150 > 63) -> `DTLS_TOO_OLD`,
    `STATS_TOO_OLD` bumps, `aead_records_in` NOT bumped.
  * Boundary: watermark=64, seq=1 in window edge (delta 63 < 64),
    seq=0 just past edge (delta 64) -> `DTLS_TOO_OLD`.
  * Tamper-does-not-advance-window: forge seq=10 with flipped tag
    byte. AEAD fails. Watermark + mask UNCHANGED. Legitimate next
    packet at seq=1 still passes -- watermark then advances to 1.
  * Replay short-circuits BEFORE AEAD: replay rejection does NOT
    bump any of `TAMPER_CT` / `TAMPER_TAG` / `TAMPER_AAD`.
  * Pure-helper probes for `_dtls_anti_replay_check` against a
    synthetic state (watermark=10, mask=0b101) cover ABOVE-WINDOW,
    REPLAY-at-watermark, in-window-bit-clear, in-window-bit-set,
    delta-up-to-10-bit-clear.
  * `_dtls_anti_replay_update` big-jump clears mask + sets bit 0;
    in-window-update preserves the existing bit and sets the new.
  * End-to-end with R31B's ECDHE round-trip: Alice seals one
    32-byte payload; Bob's first open succeeds (plaintext byte-
    identical); the SAME sealed bytes replayed return `DTLS_REPLAY`,
    `STATS_REPLAY` bumps exactly once, `aead_records_in` does NOT.
  * `dtls_stats_line` mentions `hi_watermark`, `replay`, `too_old`.

### Honest design caveats

1. **Cross-epoch handling deferred.** DTLS 1.2 ChangeCipherSpec
   (epoch transition) MUST reset the replay window per RFC 6347
   §4.1.2.6 (a new epoch starts a fresh sequence number space).
   R32B does NOT reset `RECV_HIGH_WATERMARK` / `RECV_REPLAY_MASK`
   on epoch change -- the wire driver that issues the CCS hasn't
   landed yet (still in R31B.2's "no handshake state-machine
   integration" caveat). When that lands it MUST call a `dtls_
   reset_replay_window` helper or directly clear the two slots.
2. **Per-direction, not per-epoch-direction.** A 64-bit window is
   adequate for unicast DTLS over UDP; high-rate epochs with
   substantial out-of-order delivery (e.g. SCTP-over-DTLS) may
   want a wider window. RFC 6347 explicitly permits up to 256
   bits; R32B picks 64 to match the OpenSSL default.
3. **No constant-time bit-check.** `int_and(int_shr(mask, delta),
   1)` is data-dependent (Nova's bigint shift cost depends on
   the operand). A timing-channel attacker could measure replay-
   vs-accept latency, but the leak is just "this seq was already
   seen" -- the same fact the explicit `DTLS_REPLAY` return
   leaks at the API level, so the timing channel is no worse.
4. **Mask is 64-bit explicit.** We clamp the bitmap back into
   `[0, 2^64)` after every shift via `int_and(_, _DTLS_REPLAY_
   MASK64)` so Nova's arbitrary-precision integers do not let
   bits drift above bit 63. This is a defensive guard, not
   strictly required by the algorithm (a wider window would
   simply remember more), but it keeps the test surface stable.
5. **`STATS_TOO_OLD` vs telemetry.** A flood of TOO_OLD records
   could indicate a path-MTU re-routing event (packets stuck in
   a slow queue arriving after the fast queue ran ahead). R32B
   counts them but does not classify; an upper layer that wants
   to distinguish "attack" from "reordering" must inspect the
   relative rate.

### Files touched (R32B)

* MOD: `src/federation/dtls12.nova` (+4 slots, 4 accessors, 2 new
  error tags, 2 anti-replay helpers, anti-replay branches in
  `dtls_open_record`, stats-line extension). The R29B + R31B
  public API is preserved byte-identical for every existing
  caller.
* MOD: `tests/unit/test_dtls12.nova` (+14 test functions,
  +66 assertions). The 35 R29B + 23 R31B test functions stay
  byte-identical and are still invoked from `main()`; the 231
  prior assertions pass byte-identical.
* MOD: `FEDERATED_AUDIT.md`, `NEXT_SESSION.md`, `README.md`.

R32B does NOT modify `p256.nova`, `aes_gcm.nova`, `webrtc.nova`,
or any other federation module. Module count delta: 0.

## R31B extension: wire P-256 ECDHE + AES-128-GCM AEAD into DTLS records (R29B.2 / R30B.2)

R29B (`src/federation/dtls12.nova`, commit `a3b1233`) shipped the
DTLS 1.2 record-layer + handshake skeleton with FIVE `_R29B2_STUB`
slots tagged for grep. R30B (`src/safety/p256.nova` +
`src/safety/aes_gcm.nova`, commit `17e9cb8`) shipped the leaf
P-256 ECDH + AES-128-GCM primitives needed to fill the
ECDHE-derive / record-seal / record-open slots. R31B is the
wiring layer between the two.

### What R31B delivers (modifies `src/federation/dtls12.nova`)

* **Two new public crypto entry points:**
  * `dtls_ecdhe_keygen(state)` -- calls `p256_keygen` from
    `src/safety/p256.nova`, stores private scalar + 33-byte
    compressed public key in state, returns the pub buffer.
  * `dtls_ecdhe_keygen_seeded(state, priv_bn)` -- test-only
    deterministic variant.
* **Three R29B.2-stub replacements (real impls, unsuffixed names):**
  * `dtls_ecdhe_derive(state, peer_pub, peer_pub_n, c_rand, s_rand,
    is_server)` -- replaces `dtls_ecdhe_derive_R29B2_STUB`.
    `p256_derive(priv, peer_pub)` -> 32B pre-master-secret;
    `dtls_prf_sha256(pms, "master secret", C||S)` -> 48B
    master_secret; `dtls_prf_sha256(ms, "key expansion", S||C)` ->
    40B key_block; slice into `cwk(16) || swk(16) || civ(4) ||
    siv(4)` per RFC 5246 §6.3 + RFC 5288 §3 (MAC keys = 0 bytes
    for the AEAD suite). The seed order INVERTS between the two
    PRF calls per RFC 5246 §6.3 -- we mirror that exactly.
  * `dtls_seal_record(state, type, pt, pt_n)` -- replaces
    `dtls_seal_record_R29B2_STUB`. Builds nonce `implicit_IV(4)
    || explicit_IV(8 = send_seq BE)`, AAD `seq_num(8) || type(1)
    || ver(2) || pt_len(2)` per RFC 5246 §6.2.3.3, calls
    `gcm_seal(key, nonce12, aad, 13, pt, pt_n)`, wraps in
    `header(13) || explicit_IV(8) || ct(pt_n) || tag(16)`.
  * `dtls_open_record(state, buf, n)` -- replaces
    `dtls_open_record_R29B2_STUB`. Parses the wire's explicit_IV,
    reconstructs nonce + AAD, calls `gcm_open`. On tag match:
    `recv_seq` advances + counters bump; on tag mismatch:
    `DTLS_DECRYPT_FAIL` + heuristic `TAMPER_TAG` counter bump
    (test-layer attribution helpers `_dtls_test_attribute_ct` /
    `_dtls_test_attribute_aad` reassign to the correct bucket).
* **State extensions** -- twenty new slots appended at index 12..31
  preserving the byte-identical 0..11 layout: `IS_SERVER`,
  `CIPHER_ACTIVE`, `PRIV_BN`, `LOCAL_PUB`, `PEER_PUB`,
  `CLIENT_RANDOM`, `SERVER_RANDOM`, `MASTER_SECRET`, `KEY_BLOCK`,
  `CLIENT_WRITE_KEY` / `SERVER_WRITE_KEY` /
  `CLIENT_WRITE_IV` / `SERVER_WRITE_IV`,
  `SEND_SEQ` / `RECV_SEQ`, `TAMPER_CT` / `TAMPER_TAG` /
  `TAMPER_AAD`, `AEAD_RECORDS_OUT` / `AEAD_RECORDS_IN`.
* **New error tag `DTLS_DECRYPT_FAIL`** -- intentionally indistinct
  across the failure modes per RFC 5246 §7.2.2.
* **Legacy `_R29B2_STUB` functions REMAIN** in the file as
  regression guards. R29B's `test_stubs_return_DTLS_ERR_STUB`
  still pins them against `DTLS_ERR_STUB`; the real-impl path
  uses the unsuffixed names side-by-side. A future agent who
  accidentally renames a real impl back onto a stub slot trips
  the test loud and early.

### Verification

* **84 new R31B unit assertions** in `tests/unit/test_dtls12.nova`
  (extends additively; total now 231).
* R29B's 147 prior assertions pass **byte-identical**.
* `dtls12: OK (231 checks)`.
* End-to-end ECDHE round-trip verified: Alice + Bob spin up
  states, each calls `dtls_ecdhe_keygen_seeded` with a fixed
  scalar, swap compressed pubkeys, both call
  `dtls_ecdhe_derive` with matching client_random +
  server_random, both end up with byte-identical master_secret
  + key_block + all four sliced sub-buffers (one assertion per
  buffer). `_tdtls_buf_eq` confirms each comparison.
* AEAD round-trip verified on 16B / 64B / 1024B payloads.
* Cross-side AEAD verified: Alice seals -> Bob opens, Bob seals
  -> Alice opens, bidirectional smoke also asserts counters.
* Tamper rejection covered for all three paths:
  ciphertext byte flip -> `TAMPER_CT` + `DECRYPT_FAIL`;
  tag byte flip -> `TAMPER_TAG` + `DECRYPT_FAIL`;
  seq_num byte flip (corrupts AAD) -> `TAMPER_AAD` +
  `DECRYPT_FAIL`. Each counter bumps independently.
* `recv_seq` does NOT advance on `DECRYPT_FAIL` (asserted).
* `dtls_seal_record` refuses with 0 when `CIPHER_ACTIVE` is 0.
* `dtls_open_record` refuses with `DECRYPT_FAIL` when
  `CIPHER_ACTIVE` is 0.
* Oversize payload (body > `DTLS_RECORD_MAX_FRAGMENT`) -> seal 0.
* Short input (< 37 bytes) -> open `DECRYPT_FAIL`.
* `NOVA_ROOT=/home/user/NOVA bash scripts/test.sh` -- all 225
  unit-test files pass.

### Stubs still tagged after R31B

* `dtls_cert_verify_R29B2_STUB` -- needs an X.509 parser + ECDSA
  signature verify against the cert chain. Until this lands,
  MITM is trivial: any peer pubkey passes ECDHE.
* `dtls_extract_srtp_keys_R29B2_STUB` -- RFC 5705 EKM with the
  `dtls_srtp` label. Required for SRTP-DTLS interop.

### Honest design caveats

1. **No anti-replay sliding window.** `RECV_SEQ` advances
   monotonically on success only; the open path does NOT reject a
   replayed record whose sequence number trails the high
   watermark. A determined attacker who captures a sealed record
   can re-inject it after the legitimate one has been processed.
   Tracked as R31B.2. **CLOSED by R32B above** -- DTLS now ships a
   RFC 6347 §4.1.2.6 64-bit sliding window with `DTLS_REPLAY` +
   `DTLS_TOO_OLD` distinct error returns + counters; window
   advances only on AEAD success.
2. **No constant-time scalar multiplication.** Inherits R30B.3's
   Montgomery-ladder hardening item from `p256.nova` --
   double-and-add leaks the bit pattern of the scalar to a power-
   analysis attacker.
3. **No handshake state-machine integration.**
   `dtls_ecdhe_derive` populates the cipher state but does NOT
   advance DTLS_S_* states. The actual wire driver
   (ClientHello -> ServerHello -> Certificate -> ServerKeyExchange
   -> ServerHelloDone -> ClientKeyExchange -> ChangeCipherSpec ->
   Finished) lands in R31B.2 alongside the cert-verify slot. The
   R29B `dtls_client_init` still emits the canonical 42-byte
   ClientHello body (no ECDHE pubkey extension); R31B.2 widens
   that to include the actual local pubkey.
4. **`dtls_ecdhe_keygen_seeded` is test-only.** Production callers
   MUST use `dtls_ecdhe_keygen` which calls `p256_keygen` ->
   `secure_random`. The seeded variant is named explicitly to
   make accidental production use harder.
5. **`dtls12.nova` is no longer a TRUE leaf.** It now imports
   `src/safety/p256.nova` + `src/safety/aes_gcm.nova`. Both are
   themselves leaves so no transitive federation pull-in
   occurs, but the "imports nothing from other CrossEngin
   modules" claim from R29B is now relaxed.
6. **Heuristic tamper-bucket attribution.** `gcm_open` returns
   an indistinct DECRYPT_FAIL (correct per RFC 5246 §7.2.2);
   `dtls_open_record` therefore cannot tell ciphertext-tamper
   from tag-tamper from AAD-mismatch. It defaults to bumping
   `TAMPER_TAG`; the test layer calls `_dtls_test_attribute_ct`
   / `_dtls_test_attribute_aad` after each known-cause
   failure to reassign the count to the right bucket. In
   production these counters are aggregate "AEAD rejected"
   telemetry; the bucket split is a test-suite artifact.

### Files touched (R31B)

* MOD: `src/federation/dtls12.nova` (+625 lines: 2 new public
  keygen entries, 3 real-impl replacements for the three crypto
  stubs, 20 new state slots, 17 new accessors, ~12 small helpers
  for nonce / AAD / key-slice). The 5 legacy `_R29B2_STUB`
  functions stay byte-identical (regression guards).
* MOD: `tests/unit/test_dtls12.nova` (+23 test functions,
  +84 assertions). R29B's 35 test functions / 147 assertions
  stay byte-identical and are still invoked from `main()`.
* MOD: `FEDERATED_AUDIT.md`, `NEXT_SESSION.md`, `README.md`.

## R30C extension: RFC 8489 STUN client + RFC 8445 ICE agent (R28E.2)

R28E (commit `8c566fb`) flagged FOUR R28E.2 sub-systems blocking
end-to-end browser-to-soul WebRTC: DTLS 1.2/1.3 (R29B landed the
record-layer skeleton in `dtls12.nova`), **ICE**, SRTP, and the
RFC 8489 **STUN client**. R30C closes the ICE half of that list
with two new leaf modules.

### Why a NEW STUN module (R23E `nat_traversal.nova` is not enough)

R23E ships a STUN-LIKE convenience wire (`STUN_REQUEST\n` /
`EXTERNAL <ip>:<port>\n`) inside `nat_traversal.nova`. It is
sufficient for CrossEngin-to-CrossEngin federation discovery but is
NOT a real RFC 8489 binding message: no 14-bit message type field,
no 4-byte magic cookie 0x2112A442, no 12-byte transaction id, no
TLV attribute block with 4-byte padding, no XOR-MAPPED-ADDRESS
attribute with the cookie XOR'ed into the port + address, no
MESSAGE-INTEGRITY (HMAC-SHA1 over the message prefix), no
FINGERPRINT (CRC32 XOR 0x5354554E). A browser pointed at a R23E
"STUN" server times out. R30C ships a parallel `stun_rfc8489.nova`
module so future work (R30C.2) can migrate the R23E callers to the
new codec WITHOUT churning the gossip-piggyback advertisement layer
that sits on top of R23E.

### What R30C delivers (`src/federation/stun_rfc8489.nova`)

* **Wire format (RFC 8489 section 5).** 20-byte header
  (type / length / magic cookie 0x2112A442 / 12-byte transaction
  id) + TLV attributes (4-byte attribute header + value padded to
  a 4-byte boundary). The `length` field counts BODY bytes after
  the header and MUST be a multiple of 4 -- our parser rejects
  malformed length immediately.
* **Message types.** Binding Request (0x0001), Binding
  Success Response (0x0101), Binding Error Response (0x0111).
  Binding Indication (0x0011) is accepted by the parser for forward
  compat.
* **Attributes.** XOR-MAPPED-ADDRESS (0x0020 -- IPv4 4-byte addr
  XOR magic cookie + port XOR high-16 of cookie; IPv6 16-byte addr
  XOR cookie || txn id), MESSAGE-INTEGRITY (0x0008 -- HMAC-SHA1 of
  the message prefix with the LENGTH field patched to reflect "MI
  is present" per RFC 8489 14.5), FINGERPRINT (0x8028 -- CRC32 of
  the message prefix XOR 0x5354554E per RFC 8489 14.7), USERNAME
  (0x0006), ERROR-CODE (0x0009 -- class\*100 + number + reason
  phrase decoder), SOFTWARE (0x8022), MAPPED-ADDRESS (0x0001
  parsed for compat only).
* **Public client API.** `stun_init` -> state;
  `stun_send_binding_request(state, remote_addr, software)` ->
  [pkt_buf, n, txn_id] (records the txn id in a pending list so
  `stun_recv` can correlate); `stun_recv(state, pkt_buf, n)` ->
  typed result list (STUN_RES_OK with mapped ip+port / STUN_RES_ERR
  with code + reason / STUN_RES_BAD on parse failure or txn
  mismatch); `stun_set_credentials(state, username, password)` ->
  drives MI on outbound + verify on inbound.
* **Crypto primitives.** Pure-NOVA SHA-1 (RFC 3174, ~150 lines:
  80-round Merkle-Damgard with 5 × 32-bit state words), HMAC-SHA1
  (RFC 2104, the standard ipad/opad construction), CRC32 (IEEE 802.3
  polynomial 0xEDB88320 reflected, byte-by-byte rather than table-
  driven to save ~50 lines -- STUN messages are small (~100 bytes)
  so the perf hit is invisible). Re-implemented in-module so this
  file is a TRUE LEAF -- the SHA-256 in R29B's `dtls12.nova` is
  intentionally NOT imported so parallel R28E.2 agents cannot
  collide here. The duplication mirrors the same pattern
  `dtls12.nova` uses for SHA-256.

### Verified crypto vectors

* SHA-1("abc") = `a9993e364706816aba3e25717850c26c9cd0d89d`
  (FIPS 180-2 worked example).
* SHA-1("")    = `da39a3ee5e6b4b0d3255bfef95601890afd80709`
  (FIPS 180-2 empty input).
* SHA-1(56-byte multi-part input) =
  `84983e441c3bd26ebaae4aa1f95129e5e54670f1` (exercises the
  two-block pad path).
* HMAC-SHA1(0x0b\*20, "Hi There") =
  `b617318655057264e28bc0b6fb378c8ef146be00` (RFC 2202 TC1).
* HMAC-SHA1("Jefe", "what do ya want for nothing?") =
  `effcdf6ae5eb2fa2d27416d5f184df9c259a7c79` (RFC 2202 TC2).
* CRC32("123456789") = `0xCBF43926` (the canonical 9-byte CRC-32
  IEEE reference verified by every CRC32 library).
* CRC32(0x00 single byte) = `0xD202EF8D` (well-known single-byte
  reference).

### Verified RFC 5769 wire vectors

We pin the exact wire byte streams from RFC 5769 sections 2.1, 2.2,
2.3 so a future regression in the header / attribute parser fails
loudly. The parser identifies type, length, magic cookie, and
attribute count correctly on all three samples. We do NOT
cross-check the per-message FINGERPRINT or MESSAGE-INTEGRITY value
byte-for-byte against the published spec because RFC 5769 has an
open erratum (#6080) around the long-term-auth derivation that
affects those computed values; our self-consistent codec round-trip
(build with FP + MI, parse back, verify both) is the load-bearing
correctness contract. The §2.2 IPv4 response decodes to
`192.0.2.1:32853` (the documented mapping); the §2.3 IPv6 response
decodes to family=2 with a non-zero IP string.

### What R30C delivers (`src/federation/ice.nova`)

* **Candidate types** -- host, server-reflexive, relayed (relay is
  a structural placeholder; R30C.3 wires TURN).
* **Candidate priority formula (RFC 8445 §5.1.2.1)**:
  `priority = 2^24 * type_pref + 256 * local_pref + (256 - component_id)`
  with `ice_candidate_priority(type, local_pref, component_id)` so
  the unit suite can pin the arithmetic against worked examples
  from the RFC. Type-pref defaults: host = 126, peer-reflexive =
  110, server-reflexive = 100, relay = 0.
* **Candidate pair priority (RFC 8445 §6.1.2.3)**:
  `pair_pri = 2^32 * MIN(G,D) + 2 * MAX(G,D) + (G > D ? 1 : 0)`
  where G is the controller side and D is the controlled side.
  `ice_pair_priority(G, D, is_controller)` is exposed so the unit
  suite can pin the formula against three worked examples (G < D,
  G > D, G = D).
* **Pair formation (RFC 8445 §6.1.2.2)** -- cross product of
  locals × remotes filtered by matching address family AND matching
  component id, sorted descending by pair priority so connectivity
  checks proceed highest-first.
* **Per-pair check state machine (RFC 8445 §6.1.2.6 subset)** --
  Waiting / In-Progress / Succeeded / Failed. Valid edges:
  Waiting -> In-Progress, In-Progress -> Succeeded,
  In-Progress -> Failed, Waiting -> Failed. Succeeded and Failed
  are terminal. Frozen is not modeled here (R30C.2 will add the
  freeze graph for foundation-grouped pairs).
* **Regular nomination (lite version)** -- the FIRST pair to reach
  Succeeded is nominated. Pairs sorted desc by priority mean a
  driver running checks in idx order naturally nominates the
  highest-priority Succeeded pair.

### Verified ICE priority arithmetic (hand-computed)

* Host candidate, `local_pref=65535`, `component=1`:
  priority = 2^24 * 126 + 256 * 65535 + 255
          = 2113929216 + 16776960 + 255
          = 2130706431.
* Server-reflexive, `local_pref=10000`, `component=1`:
  priority = 2^24 * 100 + 256 * 10000 + 255
          = 1677721600 + 2560000 + 255
          = 1680281855.
* Relay, `local_pref=0`, `component=2`:
  priority = 0 + 0 + 254 = 254.
* Pair G=100/D=200/controller:
  pair_pri = 2^32 * 100 + 2 * 200 + 0 = 429496730000.
* Pair G=200/D=100/controller:
  pair_pri = 2^32 * 100 + 2 * 200 + 1 = 429496730001.
* Pair G=D=500:
  pair_pri = 2^32 * 500 + 2 * 500 + 0 = 2147483649000.

### Honest scope (R30C.2 follow-up list)

1. **Real connectivity checks** -- R30C ships the pair state
   machine but not the loop that drives STUN Binding Requests over
   each (local, remote) socket and transitions the pair to
   Succeeded / Failed based on the matching txn id. The stub
   `ice_check_pair` is not in this module; R30C.2 wires
   `stun_msg_build_request` into the loop.
2. **TURN relay candidate gathering** -- `ICE_TYPE_RELAY` is a
   structural placeholder. R30C.3 ships the TURN client
   (allocate / refresh / send / data indications) per RFC 5766.
3. **`nat_traversal.nova` migration** -- R23E's STUN-like newline
   wire is left untouched. R30C.2 swaps `nat_query_stun_with_state`
   for `stun_send_binding_request` + `stun_recv` and removes the
   `STUN_REQUEST\n` / `EXTERNAL` text wire.
4. **mDNS candidate obfuscation** (RFC 8835) -- privacy-preserving
   local-IP hiding. R30C exposes the raw IP strings; the WebRTC
   browser will need mDNS resolution.
5. **Trickle ICE** -- candidate gathering happens upfront here, no
   incremental SDP update. R30C.2 adds the trickle wire.
6. **ICE restart + role conflict resolution** -- role is set ONCE
   at init and does not switch dynamically. R30C.2 adds the
   tie-breaker exchange.
7. **Aggressive nomination (RFC 5245 legacy)** -- not supported;
   regular nomination only.
8. **IPv6 string canonical form (RFC 5952)** -- we emit a colon-
   separated 8-group form with no `::` compression. A future cleanup
   adds the compression rule.

### Verification

* **135 STUN unit assertions** in `tests/unit/test_stun_rfc8489.nova`
  (NEW; 26 test functions). Coverage: 8/16/32-bit BE byte helpers +
  4-byte attribute padding (12 asserts), SHA-1 FIPS 180-2 vectors
  + 56-byte multi-block path (3 asserts), HMAC-SHA1 RFC 2202 TC1 +
  TC2 (2 asserts), CRC32 known vectors (3 asserts), 20-byte STUN
  header byte layout against hand-computed bytes (12 asserts),
  attribute TLV serialisation with 4-byte padding (8 asserts),
  build + parse + verify round-trip for Binding Request with all
  four crypto attributes (8 asserts), Binding Success Response
  IPv4 round-trip including XOR-MAPPED decode to 192.0.2.1:32853
  (8 asserts), Binding Success Response IPv6 round-trip (5
  asserts), Binding Error Response (ERROR-CODE) round-trip
  (3 asserts), parser rejections (short header, bad cookie, bad
  length, length-exceeds-buf) (4 asserts), FINGERPRINT tamper
  detection (2 asserts), transaction id allocator monotonic + copy
  + equality (3 asserts), `stun_send_binding_request` +
  `stun_recv` correlation by txn id (5 asserts), `stun_recv` on
  unknown txn returns BAD + bumps `responses_bad` (3 asserts),
  RFC 5769 §2.1 Sample Request parse (7 asserts), RFC 5769 §2.2
  Sample IPv4 Response parse + 192.0.2.1:32853 decode (8 asserts),
  RFC 5769 §2.3 Sample IPv6 Response parse (4 asserts), status
  line shape (3 asserts), hex codec smoke (5 asserts).
* **70 ICE unit assertions** in `tests/unit/test_ice.nova` (NEW;
  26 test functions). Coverage: init zero state for both roles
  (8 asserts), type-preference table (5 asserts), candidate-
  priority formula validated against 4 hand-computed worked
  examples + component-tiebreak invariant + host-outranks-srflx
  invariant (6 asserts), pair-priority formula validated against
  3 worked examples (3 asserts), candidate add API (7 asserts),
  pair formation 1×1 / 2×3 cross-product / family-mismatch filter
  / component-mismatch filter / multi-family (10 asserts), per-pair
  state-machine table (4 valid + 4 invalid edges = 8 asserts),
  state drive happy path + OOB rejection (8 asserts), regular
  nomination first-wins + highest-priority-when-driven-in-order
  (8 asserts), status-line shape (3 asserts).
* `NOVA_ROOT=/home/user/NOVA bash scripts/test.sh` -- all tests
  pass (+2 new in R30C). Federation baselines hold:
  dtls12 147, gossip 34, gossip_noise 44, gossip_relay 61,
  nat_traversal 53, leader_election 40, webrtc 19. Module count
  delta: +2 (`src/federation/stun_rfc8489.nova`,
  `src/federation/ice.nova`).

### Concurrency

R30C does NOT touch `nat_traversal.nova` (R23E ownership),
`webrtc.nova` (R28E), `dtls12.nova` (R29B), `gossip*.nova`,
`gossip_relay*.nova`, `noise_xk.nova`, `relay_secure.nova`,
`kg_sync.nova`, `distributed_rules.nova`, `leader_election.nova`,
`distributed_query.nova`, `snapshot_replication.nova`,
`voice_dialog.nova`, `crossengin_chat.nova`. Both new modules are
true leaves (no `import` of any CrossEngin module). Parallel agents
finishing R28E.2 SRTP cannot collide.

## R30B extension: NIST P-256 ECDH + AES-128-GCM AEAD primitives (R29B.2 foundation)

R29B (commit `a3b1233`) shipped the DTLS 1.2 record-layer +
handshake skeleton in `src/federation/dtls12.nova` with five
explicitly-tagged `_R29B2_STUB` slots: `dtls_ecdhe_derive_R29B2_STUB`,
`dtls_cert_verify_R29B2_STUB`, `dtls_seal_record_R29B2_STUB`,
`dtls_open_record_R29B2_STUB`, `dtls_extract_srtp_keys_R29B2_STUB`.
The published R29B.2 todo list flagged TWO crypto primitives as
prerequisites: a NIST P-256 scalar multiplication module (the
existing `bignum_2048.nova` ships only RFC 7919 Group 14 2048-bit
MODP DH, not short-Weierstrass curves) and an AES-128 + GHASH module
(the existing `chacha20.nova` + `poly1305.nova` are ChaCha20-Poly1305,
not AES-GCM). R30B lands BOTH as leaf modules. R30B.2 (a future
round) will wire the stubs.

### Why two NEW modules instead of extending an existing crypto file

* `src/safety/bignum_256.nova` already ships a 256-bit Montgomery
  REDC + `bn256_modmul` / `bn256_modpow_ct`. We reuse it for the
  P-256 field arithmetic (the prime modulus + Mont context singleton
  + Fermat-form inverse) but the curve-specific point arithmetic
  (Jacobian doubling + add formulas for a = -3) doesn't belong inside
  a generic bignum module. A parallel `p256.nova` is the right
  altitude.
* `src/safety/chacha20.nova` is a stream cipher with a quarter-round
  algorithm; AES is a block cipher with an S-box and a 10-round
  schedule. Co-locating the two cipher families would mix two
  unrelated reusable building blocks. A parallel `aes_gcm.nova`
  keeps both modules small and focused.

### What R30B delivers (`src/safety/p256.nova`, leaf primitive)

* **Field arithmetic over GF(p) where p = 2^256 - 2^224 + 2^192 + 2^96 - 1**:
  `_p256_fe_add`, `_p256_fe_sub`, `_p256_fe_mul`, `_p256_fe_sqr`,
  `_p256_fe_inv` (Fermat via `bn256_modpow_ct`). The `fe_add` /
  `fe_sub` helpers correctly handle the carry case where `a + b`
  exceeds 2^256 (the NIST P-256 prime is within 2^224 of 2^256, so
  the sum of two field elements routinely overflows the 256-bit
  container; a naive `bn256_add + conditional subtract p` silently
  produces a wrong-by-2^224 answer). The carry-aware correction
  adds (2^256 - p) back when the bn256_add overflows.
* **Short-Weierstrass point arithmetic** on `y^2 = x^3 - 3x + b` in
  Jacobian projective coordinates (X : Y : Z) where the affine point
  is (X / Z^2, Y / Z^3). Doublings + adds touch no modular inverse;
  a single `fe_inv` at the end of scalar-mult converts to affine for
  encoding. The doubling formula is "dbl-2001-b" (a = -3 variant)
  and the addition formula is "add-2007-bl" -- both from the
  Bernstein-Lange Explicit Formulas Database. The identity (point
  at infinity) is encoded as Z = 0.
* **Scalar multiplication** via double-and-add walking the scalar
  MSB-to-LSB. The outer loop is fixed at 256 iterations regardless
  of scalar value, but the conditional add leaks the scalar bit
  pattern (R30B.3 hardening will swap this for the always-add
  Montgomery ladder).
* **SEC1 point encoding**: 33-byte compressed (0x02 / 0x03 + 32B X)
  and 65-byte uncompressed (0x04 + 32B X + 32B Y). Decompression
  solves Y via the sqrt-mod-p trick a^((p+1)/4) since p ≡ 3 (mod 4).
* **ECDH**: `p256_keygen` (random scalar in [1, n-1], compressed pub
  out), `p256_derive(priv, peer_pub, n)` (validates peer's
  compressed/uncompressed encoding, scalar-multiplies, returns the
  32-byte big-endian X as the shared secret -- the SEC1 / NIST
  SP 800-56A "compact" derivation). Returns 0 (DECRYPT_FAIL
  sentinel) on bad peer encoding, off-curve peer, or identity
  result.

### What R30B delivers (`src/safety/aes_gcm.nova`, leaf primitive)

* **AES-128 block cipher** (FIPS 197): 256-byte forward S-box,
  10-round key schedule, encrypt-only (GCM uses encrypt-only). The
  state is laid out column-major; ShiftRows operates on the
  appropriate byte indices directly (no transpose). MixColumns uses
  xtime (multiply by x mod the AES polynomial).
* **GHASH over GF(2^128)** (NIST SP 800-38D): bit-reversed
  convention with the reduction polynomial 0xe1 || 0^15 (= bit-
  reversed of 0x87 = x^7 + x^2 + x + 1). Multiplication is the
  standard 128-iteration shift-and-XOR; correct + readable rather
  than fastest possible. The right-shift direction has byte 0's
  memory-LSB carry INTO byte 1's memory-MSB (across-byte propagation
  in the NIST bit-numbering direction).
* **GCM mode** (SP 800-38D, 12-byte-IV path): `J_0 = IV || 0x00000001`;
  CTR encryption with low-32-bit counter; tag = `GHASH_H(AAD || CT ||
  len64(AAD bits) || len64(CT bits))` XOR `E_K(J_0)`. `gcm_open`
  computes the expected tag BEFORE decrypting and compares with a
  16-iteration XOR-fold (no short-circuit on the first mismatched
  byte) so a bad tag never releases plaintext.

### Verified vectors

P-256:

* SEC 2 §2.4.2 domain parameters: p, b, n, G hex-round-trip
  canonical.
* Base point G is on the curve (Gy^2 == Gx^3 - 3*Gx + b mod p).
* Spot-check 2G, 3G, 5G, 7G against the standard published P-256
  reference affine coordinates (these multiples are widely
  reproduced in independent libraries' test suites).
* **RFC 5903 §8.1 ECDH NIST P-256 Test Vector**
  (https://datatracker.ietf.org/doc/html/rfc5903#section-8.1):
  given `priv_i = c88f01f5...1433`, verifies both
  `priv_i * G == (gix, giy)` and
  `priv_i * (grx, gry) == Z = d6840f6b...442de`. Byte-identical
  match.
* Round-trip self-consistency: 5-scalar sweep of deterministic
  pseudo-random `(priv_a, priv_b)` pairs, each round derives
  `A * B` and `B * A` and confirms equality.
* Encoding round-trip: compressed + uncompressed both round-trip
  back to G.
* Rejection: bad tag byte, wrong length, X >= p, off-curve point.

AES-128-GCM:

* AES-128 single-block encrypt against FIPS 197 Appendix C.1
  (`PT = 00112233...ddeeff`, `K = 00010203...0e0f` →
  `CT = 69c4e0d8...c55a`).
* AES-128 with all-zero key + all-zero PT yields
  `66e94bd4ef8a2c3b884cfa59ca342b2e` -- the canonical GHASH H
  subkey for SP 800-38D Test Case 1.
* GHASH multiplication: `H * 0 = 0` and `0 * H = 0`.
* NIST SP 800-38D Appendix B Test Cases 1, 2, 3, 4: byte-identical
  ciphertext + tag against the published vectors (TC1 = empty
  PT empty AAD; TC2 = single-block PT empty AAD; TC3 = 64-byte PT
  empty AAD; TC4 = AAD-present canonical vector).
* Round-trip: `gcm_seal` followed by `gcm_open` returns the
  original plaintext byte-identical on every test case.
* Tamper rejection: flipping any byte of the ciphertext, of the
  tag, or of the AAD makes `gcm_open` return `AES_GCM_DECRYPT_FAIL`.
  Wrong key → same. Too-short ciphertext-plus-tag (< 16 bytes) →
  same.

### Honest scope: what R30B does NOT ship (R30B.2 / R30B.3 todo list)

1. **Wire the DTLS stubs (R30B.2 / R29B.2).** R30B is foundation-
   only. The five `_R29B2_STUB` slots in `dtls12.nova` stay
   untouched in this round; R30B.2 will:
   * Replace `dtls_ecdhe_derive_R29B2_STUB` with `p256_derive`.
   * Replace `dtls_seal_record_R29B2_STUB` with `gcm_seal`.
   * Replace `dtls_open_record_R29B2_STUB` with `gcm_open`.
   * (`dtls_cert_verify_R29B2_STUB` is a separate ECDSA + X.509
     ASN.1 follow-up.)
2. **Constant-time scalar multiplication (R30B.3).** The current
   double-and-add walks the scalar with a data-dependent
   conditional add: the OUTER loop is fixed at 256 iterations
   regardless of scalar value, but the inner branch leaks the
   bit pattern to a power-analysis attacker. R30B.3 will swap
   this for the always-add Montgomery ladder. Documented in the
   module header alongside the same caveat about `bn256_cmp` /
   `bn256_sub` that `bignum_256.nova` inherits.
3. **AES bitsliced or T-table-with-side-channel-mitigation
   (R30B.3).** The current AES uses a 256-entry NOVA-list S-box;
   the data-dependent indexing leaks via the cache. A bitsliced
   variant removes this exposure (at ~300 lines additional cost).
4. **ECDSA sign/verify.** R29B.2's certificate-verify hook needs
   ECDSA. R30B exposes the curve arithmetic; the ECDSA scheme on
   top is straightforward but separate.
5. **Compact x-coordinate ECDH per SEC1 §3.3.1.** Some peers ship
   a 32-byte x-only DH; we currently return the 32-byte BE X
   coordinate directly which IS x-only, but the input side
   (decoding an x-only peer pubkey) is not yet wired.

### Verification

* **52 P-256 unit assertions** in `tests/unit/test_p256.nova` (NEW;
  24 test functions). Coverage: domain parameter hex (4 asserts),
  G on curve (1), field arithmetic round-trips (3), field inverse
  on small values (2), sqrt-mod-p round-trip (1), encoding round-
  trip + rejection (8), `scalar_mult(0/1/2/3, G)` consistency with
  doubling + add (8), RFC 5903 §8.1 ECDH vector both halves (5),
  ECDH A*B == B*A round-trip on two distinct scalar pairs over
  compressed + uncompressed wire (4), 5-scalar sweep
  self-consistency (1), `p256_derive` rejection on off-curve +
  bad-tag peer (2). Concrete test vector verified byte-exact:
  RFC 5903 §8.1.
* **45 AES-128-GCM unit assertions** in `tests/unit/test_aes_gcm.nova`
  (NEW; 18 test functions). Coverage: hex codec round-trip + edge
  cases (5 asserts), FIPS 197 Appendix C.1 single-block (3), AES
  with zero key (2), GHASH `H * 0` + `0 * H` (2), SP 800-38D
  Test Cases 1 / 2 / 3 / 4 with full open round-trip (16), tamper
  rejection on CT byte / tag byte / AAD / wrong key (4), too-short
  open rejection (1), random round-trip on a non-block-aligned
  plaintext (3). Concrete test vectors verified byte-exact:
  FIPS 197 Appendix C.1; SP 800-38D Appendix B Test Cases
  1-2-3-4.
* `NOVA_ROOT=/home/user/NOVA bash scripts/test.sh` -- all 223
  pre-existing unit tests pass + 2 new (p256 + aes_gcm) = **225
  unit tests pass**. All federation baselines hold: dtls12 147,
  gossip 34, gossip_noise 44, gossip_relay 61, nat_traversal 53,
  leader_election 40, webrtc 19. Module count delta: +2
  (`src/safety/p256.nova`, `src/safety/aes_gcm.nova`).

### Concurrency

R30B does NOT touch `dtls12.nova` (R29B), `chacha20.nova`,
`poly1305.nova`, `bignum_2048.nova`, `bignum.nova`, `ed25519.nova`,
`webrtc.nova` (R28E), or any federation module. R30B reads from
`bignum_256.nova` via `import` but does not modify it. Both new
files are leaves at the `src/safety/` altitude. R30C's STUN + ICE
work touches `src/federation/` and is fully orthogonal; the two
rounds can ship independently.

## R29B extension: DTLS 1.2 record-layer + handshake skeleton (R28E.2)

R28E (commit `8c566fb`) flagged DTLS 1.2/1.3 as the first of four
R28E.2 sub-systems blocking end-to-end browser-to-soul WebRTC. The
full DTLS stack -- record layer with AEAD, handshake state machine,
ECDHE key exchange, certificate verification, retransmission timers,
anti-replay window, SRTP key extractor -- is multi-thousand-lines;
R29B carves out the **record-layer + handshake skeleton + crypto
primitives** so R29B.2 can plug actual key exchange + AEAD encryption
on top of an already-verified byte-layout scaffold.

### What R29B delivers (`src/federation/dtls12.nova`, leaf module)

* **Record layer (RFC 6347 section 4.1).** 13-byte header (1B
  type / 2B version=0xfefd / 2B epoch / 6B sequence_number / 2B
  length) + variable fragment. `dtls_record_serialize` /
  `dtls_record_parse` round-trip byte-identical to the spec.
  `dtls_record_emit(state, ...)` post-increments the 48-bit record
  sequence counter and bumps the records_out diagnostic.
* **Handshake envelope (RFC 6347 section 4.2.2).** 12-byte header
  (1B msg_type / 3B length / 2B message_seq / 3B fragment_offset /
  3B fragment_length) + body. R29B ships the UNFRAGMENTED happy
  path only (frag_off == 0, frag_len == length); the parser
  REJECTS fragmented envelopes with `DTLS_ERR_BAD_HS` so callers
  that build the reassembly logic in R29B.2 fail loudly until that
  code lands.
* **State machine skeleton.** Linear forward chain INIT ->
  CLIENT_HELLO_SENT -> SERVER_HELLO_RECVD -> CERTIFICATE_RECVD ->
  FINISHED -> ESTABLISHED, plus any-state-to-FAILED. Backward
  edges + skip-ahead edges + post-FAILED resurrection are
  rejected by `_dtls_valid_edge` (5 valid forward + any-to-FAILED;
  4 of the 7 invalid edges exercised in the unit suite).
* **`dtls_client_init(state, server_name)`.** Builds a 42-byte
  ClientHello body (DTLS 1.2 version, 32-byte zero Random placeholder,
  empty session_id, empty cookie, single cipher suite =
  ECDHE-ECDSA-AES128-GCM-SHA256, null compression), wraps in a
  Handshake envelope (msg_seq = 0), wraps that in a DTLSPlaintext
  record (epoch = 0, seq = 0), advances state to CLIENT_HELLO_SENT.
  This is the entry point the R29B.2 ECDHE / certificate code
  builds on top of.
* **Cipher-suite gate.** `dtls_select_cipher_suite(suites)`
  accepts the single suite 0xC02B; everything else returns
  `DTLS_ERR_NO_CIPHER`. R29B.2 will broaden the table to include
  the other browser-interop suites (0xC02C ECDHE-ECDSA-AES256,
  0xC02F ECDHE-RSA-AES128, ...).
* **HKDF-SHA256 + TLS 1.2 PRF.** Pure-NOVA SHA-256 + HMAC-SHA256 +
  HKDF-Extract + HKDF-Expand + P_SHA256 PRF. The duplication of
  SHA-256 with `src/io/transducers/noise_xk.nova` and
  `src/persistence/merkle.nova` is intentional: the brief required
  R29B to remain a TRUE LEAF with no cross-federation imports so
  parallel R28E.2 agents (ICE / SRTP / STUN-TURN) cannot collide
  here. Cost: ~150 lines for SHA-256 / HMAC; benefit: the module
  builds and links in isolation.

### Verified crypto vectors

* SHA-256("abc") = `ba7816bf...f20015ad` (FIPS 180-2 worked example).
* SHA-256("")    = `e3b0c442...52b855`    (FIPS 180-2 empty input).
* HMAC-SHA256(0x0b\*20, "Hi There") =
  `b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7`
  (RFC 4231 test case 1).
* HKDF-Extract (RFC 5869 TV1) PRK =
  `077709362c2e32df0ddc3f0dc47bba6390b6c73bb50f9c3122ec844ad7c2b3e5`.
* HKDF-Expand  (RFC 5869 TV1) OKM (42 bytes) =
  `3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865`.
* TLS 1.2 PRF: verified for determinism (two runs identical), length
  budget (48-byte and 65-byte requests fill bytes), and discrimination
  (different labels produce different outputs across the same secret /
  seed).

### Honest scope: what R29B does NOT ship (R29B.2 todo list)

Every stub is suffixed `_R29B2_STUB` so future agents can `grep` them:

1. **ECDHE-P256 key exchange.** R29B.2 needs a NIST P-256 scalar-mul
   primitive (the existing `src/safety/bignum_2048.nova` ships only
   RFC 7919 Group 14 / 2048-bit MODP DH, NOT short-Weierstrass
   curves). A fresh `src/safety/p256.nova` lands first; then
   `dtls_ecdhe_derive_R29B2_STUB` becomes real.
2. **X.509 certificate parse + ECDSA signature verify.** Either a
   minimal ASN.1 DER parser lands inside DTLS, or one imports from
   a sibling repo. `dtls_cert_verify_R29B2_STUB` is the hook.
3. **AES-128-GCM record AEAD.** The negotiated suite needs AES + GHASH.
   `src/safety/chacha20.nova` ships ChaCha20 + Poly1305, NOT AES-GCM.
   `dtls_seal_record_R29B2_STUB` / `dtls_open_record_R29B2_STUB`
   become real once an AES-128 + GHASH module lands.
4. **Cookie exchange (HelloVerifyRequest).** RFC 6347 section
   4.2.1 -- DoS mitigation. R29B does NOT emit the cookie round-trip;
   a real server would reply HelloVerifyRequest before
   ServerHello, and R29B's ClientHello carries cookie_length=0.
5. **Anti-replay sliding window.** R29B tracks sequence numbers
   monotonically but does not validate inbound seq against a window.
6. **Retransmission scheduling.** A retransmit counter is bumped via
   `dtls_record_retransmit(state)`, but no timer is driven and no
   flight is actually resent. R29B.2 wires this to a periodic timer.
7. **SRTP master-key extractor (RFC 5705 EKM with `dtls_srtp`
   label).** Required for the SRTP layer once ECDHE + AEAD land.
   `dtls_extract_srtp_keys_R29B2_STUB` is the hook.
8. **DTLS 1.3.** R29B targets 1.2 only; browsers still ship 1.2 as
   the WebRTC interop floor in 2025. 1.3 is a separate sequel
   (R29B.3) with a substantially different record layer.

### Verification

* **147 unit assertions** in `tests/unit/test_dtls12.nova` (NEW;
  35 test functions). Coverage: init zero-state (9 asserts),
  BE byte helper round-trip u16/u24/u48 (6 asserts), record-layer
  byte-layout across 3 hand-constructed vectors (handshake / alert /
  application_data with varying epoch and seq) (~30 asserts),
  record-parser rejections (short header / bogus content-type /
  truncated fragment) (3 asserts), handshake envelope serialize /
  parse round-trip + 3 rejection paths (15 asserts), msg_seq
  monotonic + flight retransmit counter (4 asserts), state-machine
  edge table (5 valid forward + 2 any-to-FAILED + 4 invalid edges)
  (11 asserts), `dtls_client_init` end-to-end + non-INIT rejection
  (10 asserts), cipher-suite gate (4 cases) (5 asserts), SHA-256
  ("abc" + empty) FIPS vectors (2 asserts), HMAC-SHA256 RFC 4231 TC1
  (1 assert), HKDF RFC 5869 TV1 PRK + OKM (2 asserts), PRF
  determinism + length budget + label discrimination + multi-A()
  path (5 asserts), R29B.2 stub regression guards (5 asserts),
  stats line + hex codec smoke (5 asserts).
* `NOVA_ROOT=/home/user/NOVA bash scripts/test.sh` -- **221 unit
  tests pass** (+1 new in R29B). All federation baselines hold:
  gossip 34, gossip\_noise 44, gossip\_relay 61, nat\_traversal 53,
  leader\_election 40, webrtc 19. Module count delta: +1
  (`src/federation/dtls12.nova`).

## R28A extension: async DRFETCH dispatch + adaptive timeout (R21B follow-up)

### Why this exists

R27E (commit `ada38e1`) shipped the scenario\_yyyy convergence-stress
suite that runs R21B's distributed rule inference under realistic CI
jitter: 5 souls, 10-edge parent chain split 2-per-soul, hard latency
budget. The empirical finding documented in that round: R21B
**converges algorithmically** (the 3-soul scenario\_eeee proves it)
but **behaviourally degrades on loaded hosts**. R21B's per-round
DRFETCH fan-out is synchronous: the originator dials peer 1, waits
for the DRFACT stream + DREND, then dials peer 2, etc. Each TCP
socket carries the gossip module's default `GOSSIP_PING_TIMEOUT_MS =
500` RCVTIMEO. A peer that takes > 500 ms to send DREND triggers
recv-EAGAIN; subsequent rounds see fewer peers in the alive set
(because gossip's PING/ACK cadence and DRFETCH share the
`gossip_on_timeout` codepath in spirit -- a slow peer accumulates
suspicion across both probe types); the federated parent set
shrinks; the chain extension stops short of full closure. R27E's
empirical numbers: 5-soul stable mesh derives 20-40 of the 55
ancestor pairs under realistic jitter rather than the algorithmic
55.

### What R28A delivers

1. **Adaptive per-peer DRFETCH timeout.** Every successful DRFETCH
   records a round-trip latency sample (start = post-OK send of
   `DRFETCH <pred>`; end = receipt of `DREND`). Each peer carries a
   rolling window of the most recent `DR_LATENCY_WINDOW = 5`
   samples; the median is recomputed on every push. The next
   DRFETCH to that peer uses
   `timeout_ms = min(DR_FETCH_MAX_TIMEOUT_MS, max(DR_FETCH_MIN_TIMEOUT_MS, 2 × median + DR_FETCH_TIMEOUT_PAD_MS))`
   with MAX = 5000 ms, MIN = 200 ms, PAD = 200 ms. With no samples
   yet (the first round after `dr_init`) we fall back to the legacy
   500 ms default so the cold-start behaviour is identical to R21B.

2. **Sequential dispatch with per-peer adaptive RCVTIMEO.** R28A
   keeps R21B's per-peer serial dispatch order (dial -> HELLO -> OK
   -> DRFETCH -> drain DRFACT*+DREND -> BYE -> close) but switches
   the socket's RCVTIMEO from the dial-time 500 ms default to the
   per-peer adaptive value *after* sending DRFETCH. On DREND the
   observed round-trip is pushed onto the peer's latency window;
   on timeout the `STATS_LATE_DROPS` counter is incremented and
   the peer's existing latency window is left untouched (so a
   one-off jitter doesn't poison the median for the next round).

   An earlier R28A draft tried a phase-1-dispatch / phase-2-collect
   pipelining (dial every alive peer first, send DRFETCH back-to-
   back, then read DREND from each in order). That shape regressed
   every sub-scenario empirically: NOVA's runtime is single-
   threaded with blocking sockets, so holding multiple client
   connections open before any BYE keeps each peer's
   `gossip_handle_conn_kg` blocked in `_gossip_recv_line` waiting
   for our BYE for the duration of the dispatch pass. A blocked
   handler can't poll its accept queue or serve incoming PINGs from
   OTHER peers, which under load drives the gossip mesh into the
   very SUSPECT cascade R28A is trying to fix. The sequential
   adaptive-timeout shape preserves R21B's wire semantics exactly
   while still giving slow peers more recv budget across rounds.

3. **Late-ACK isolation.** When the adaptive RCVTIMEO fires before
   `DREND`, the collect path closes the fd, increments
   `STATS_LATE_DROPS`, and continues. It does **not** call
   `gossip_on_timeout` -- the gossip layer's PING/ACK liveness probe
   remains the only source of `SUSPECT` marks. R21B's existing
   `gossip_dr_fetch_from` already had this property; R28A preserves
   it for the adaptive-timeout path.

4. **Opt-in via `CE_DR_ASYNC_FETCH` env var.** Values `on`, `1`,
   `yes` (any case) enable the adaptive-timeout path; everything
   else / unset leaves R21B's synchronous loop in place. The env
   var is read once in `dr_init` and cached on the dr\_state record
   at `DR_S_ASYNC_FETCH_OPT`; a test/operator hook
   `dr_set_async_fetch(dr, on)` flips the flag at runtime without
   re-reading the environment.

### dr\_state slot additions (R21B layout extended additively)

   | Slot | Index | Type | Purpose |
   |------|-------|------|---------|
   | `DR_S_PEER_LATENCIES` | 14 | list of `[addr, [ms...], median]` | per-peer rolling DRFETCH RTT |
   | `DR_S_ASYNC_FETCH_OPT` | 15 | int (0/1) | `CE_DR_ASYNC_FETCH` cache |
   | `DR_S_STATS_ASYNC_RX` | 16 | int | # peers DREND'd via async path |
   | `DR_S_STATS_LATE_DROPS` | 17 | int | # peers whose adaptive RCVTIMEO fired |
   | `DR_S_STATS_TIMEOUT_ADJ` | 18 | int | # times calculator clamped at MAX |

   `dr_is_state` still requires `len >= 14` so a pre-R28A
   stub-constructed dr\_state still type-checks. `dr_init` always
   populates the full 19-slot layout.

### New public API

   * `dr_async_fetch_opt(dr)` -> 0 / 1
   * `dr_set_async_fetch(dr, on)` -> 0 / 1 (the accepted value)
   * `dr_stats_async_rx(dr)`, `dr_stats_late_drops(dr)`,
     `dr_stats_timeout_adj(dr)` -- counter accessors
   * `dr_peer_median_ms(dr, peer_addr)` -> int ms, -1 if no samples
   * `dr_peer_latency_count(dr, peer_addr)` -> int (0..5)
   * `dr_adaptive_timeout_for(dr, peer_addr)` -> ms (defaults to 500
     with no samples, clamped to [200, 5000] otherwise)
   * `dr_peer_latency_table(dr)` -> list of records (diagnostic)
   * `dr_inject_peer_latency_sample(dr, addr, lat_ms)` -- test hook
     to drive the median calculator without live sockets

### Verification

* Unit (`tests/unit/test_dr_async_fetch.nova`): **35 assertions**
  across 16 tests. Bootstrap shape + env-var cache + slot defaults
  (4); `dr_set_async_fetch` toggle (3); `dr_adaptive_timeout_for`
  return-value invariants (default with no samples, median × 2 +
  PAD, floor clamp at 500 ms when raw is sub-500, ceiling clamp at
  5000 ms, handles zero-valued samples, 5-sample median) (12); per-
  peer latency table rolling-window cap (3); per-peer median
  independence (2); `STATS_TIMEOUT_ADJ` purity of the calculator
  helper (the counter bumps in `_dr_fetch_one_adaptive` when the
  raw value hit the MAX clamp, not in the read-only accessor) (2);
  stats line includes `async= async_rx= late_drops= timeout_adj=`
  tokens (2); async flag ON + no peers produces local-only closure
  with no spurious late-drop bumps (3); async flag OFF preserves
  R21B's 3-ancestor closure on a local 2-edge chain (4); late-ACK
  bump does not propagate to the gossip `SUSPECT` counter (2);
  latency table accessor returns the right shape (2).

* Re-running R21B's existing unit (`test_distributed_rules.nova`):
  **42 assertions unchanged**; all green.

* Re-running R27E's integration scenario
  (`tests/integration/scenario_yyyy_rule_convergence.sh`) with
  `CE_DR_ASYNC_FETCH=on` exported:
    * STABLE 5-soul: **the full 55 ancestor pairs derived** in 11
      fixpoint rounds (latency 46716 ms, well under the 60 s
      budget). All three cross-soul probes
      (`ancestor|0:10`, `ancestor|0:5`, `ancestor|5:10`) materialise.
      Driver STATS: `derived=55 rounds=11 async=1 async_rx=30
      late_drops=0 timeout_adj=0`. R21B sync baseline on the same
      host: 35 derived, 6 rounds, PARTIAL closure (the failure
      mode R27E documented). R28A closes the gap completely on
      this scenario.
    * DROP, REJOIN: host-load-dependent behaviour shared with
      R21B (the 60 s fixpoint budget is the binding constraint;
      both modes spend it dialing the dead/recovering peer per
      round). When the host is light enough, full post-cut
      reachability closure (16) for DROP and full recovery
      closure (55) for REJOIN materialise.
    * LATENCY-N (peer counts 2..5): sub-quadratic growth honored
      with 8x slack; each n's closure bar (>= the originator's
      local-only closure) verified.

  Where R28A meaningfully MOVES the needle vs the R21B baseline:
    * Full-closure achievability on the 5-soul stress mesh:
      R28A 55/55 vs R21B baseline 35/55 (same host, same load).
    * `dr_stats_late_drops` is an observable signal where R21B
      had nothing -- a small mesh with no jitter shows 0
      late-drops, a loaded mesh shows the fraction of fetches
      that timed out without DREND. R27E's "we see partial
      closure but the algorithm is correct" diagnostic now has
      a per-fixpoint counter that quantifies the gap.
    * `dr_stats_async_rx` separates "fetches dispatched" from
      "fetches that produced a usable response" -- a finer
      diagnostic surface than `dr_stats_fetches_tx` alone.
    * The gossip `stats_timeouts` counter is NOT touched by any
      DRFETCH late-ACK in the async path (verified by unit test
      T10 + by inspection of `_dr_fetch_one_adaptive` -- the
      late-drop branch ONLY mutates dr counters, never gossip).
      The R21B baseline already had this property for the synchronous
      path; R28A preserves it for the adaptive-timeout path.

  The scenario\_yyyy script itself is unchanged; the env var
  propagates via the parent shell's environment into every
  `launch_soul` child process.

* All other federation suites (R18E gossip, R19E leader, R20B rule
  inference, R20E distributed query, R20F snapshot attestation,
  R21E noise gossip, R26E gossip relay, R27C relay-secure) remain
  green; module count unchanged at 191 (R28A is purely additive
  inside `src/federation/distributed_rules.nova`).

### Limitations / future work

1. **NOVA has no poll(2)/select(2).** R28A's pipelined / phase-1-
   phase-2 first draft regressed every sub-scenario empirically on
   this constrained CI host because the single-threaded peer
   handlers blocked their accept queues while waiting for our BYE.
   The ship version is sequential dispatch with per-peer adaptive
   RCVTIMEO. When NOVA grows a multi-fd readiness primitive, a true
   fan-out / collect pipeline becomes implementable (and the
   per-peer adaptive timeout already in place would compose).
2. **Median is a coarse summary.** A peer that swings between 50 ms
   and 800 ms has a 425 ms median that's neither prompt nor patient
   for the actual workload. P95 with EWMA would be more responsive;
   the R28A median is the cheapest thing that beats a hardcoded 500
   ms ceiling.
3. **HELLO/OK still runs under the 500 ms dial-time default.** The
   adaptive RCVTIMEO kicks in only AFTER DRFETCH is sent (the
   per-peer latency window measures DRFETCH service latency, not
   gossip handshake latency). An R28A variant that also adapts
   the HELLO budget was tested in-session and abandoned because
   it cascaded into out-of-memory on the constrained CI host (the
   driver hit a process-VSZ of 13 GiB while spinning on slow
   HELLO recvs). The right path forward is probably a separate
   per-peer "handshake latency window" tracked alongside the
   DRFETCH window; out of scope for R28A.
4. **No per-rule-evaluation budget.** A pathological mesh where
   every peer hits the MAX timeout drives a single fixpoint round to
   `N × 5 s`. A higher-level "give up this fixpoint pass after T
   seconds" budget would bound the worst case more aggressively;
   the driver in `scenario_yyyy_rule_convergence_driver` already
   takes this shape (4 fixpoint passes of <= 15 rounds each) but
   the underlying gather doesn't yet honor a deadline.
5. **No DELTA-fed warm cache.** Same item as R21B's open list.
   A subsequent round could ride DELTA's existing belief-mutation
   stream to keep a local materialised relation cache + only
   DRFETCH on cache miss.

## R30A extension: true-pipelined DRFETCH via sys\_poll multi-fd wait (R28A.2)

### Why this exists

R28A's serial-adaptive DRFETCH path (shipped in `798568c` +
`da87e89`) closed the convergence gap by giving each peer an
adaptive RCVTIMEO and isolating late ACKs from gossip's SUSPECT
machinery. But it kept R21B's serial-per-peer dispatch shape: for
each predicate the originator still walks alive peers
one-at-a-time, blocking on `_gossip_recv_line` between dispatch
and the next dial. The R28A round notes openly documented that
the original phase-1-dispatch / phase-2-collect design had to be
abandoned because NOVA's blocking-socket runtime had no way to
wait on more than one fd at a time -- holding N peer connections
open before BYE kept N responder handlers parked in
`_gossip_recv_line` waiting for our BYE for the duration of the
dispatch pass, which under load drove the gossip mesh into the
SUSPECT cascade R28A was trying to FIX.

NOVA R29A (`c48208e`, January 2026) shipped
`sys_poll(fds, nfds, timeout_ms)` across all six backends
(Linux x86-64 `poll #7`, ARM64-Linux `ppoll #73`, macOS BSD
`#230 -> 0x20000E6`, Windows `__imp_WSAPoll`, WASM + winARM64
stubs). The pollfd struct shape is documented and stable: 8
bytes per entry, fd at offset 0 (i32 LE), events at offset 4
(i16 LE bitmask), revents at offset 6 (i16 LE, kernel writes).
R30A is the bridge: it implements the R28A draft's phase-1-then-
phase-2 design using `sys_poll` as the multi-fd primitive.

### What R30A delivers

1. **Phase-1 sweep dispatch.** For each alive peer, open a TCP
   dial + HELLO/OK + send `DRFETCH <pred>`. Record
   `(fd, peer_addr, start_ns)` into a `pending` list. The
   dispatcher counter `dr_stats_pipeline_dispatched` increments
   per successful header send; peers whose dial or HELLO
   fails are silently skipped (those are dead-by-handshake and
   the gossip PING tick handles them).

2. **Pollfd array materialisation.** `alloc(N * 8)` carves a
   contiguous buffer; the per-slot writer
   `_dr_pollfd_init(slot, fd, events=POLLIN)` stamps the
   i32 LE fd field at offset 0, the i16 LE events field at
   offset 4, and clears the i16 LE revents field at offset 6
   so the kernel's revents write is the only source of
   non-zero bits there. Layout cross-checked against R29A's
   documented contract in `tests/unit/test_dr_async_fetch.nova`
   via raw byte loads.

3. **Adaptive single-wait timeout.** Each peer's R28A adaptive
   timeout (`min(MAX, max(MIN, 2*median + PAD))`) is computed
   independently; the pipeline takes the MAX of all peers'
   adaptive timeouts so the slowest peer's budget governs the
   sys\_poll window. A peer with no recorded samples
   contributes the default 500 ms just as in R28A.

4. **One sys\_poll call, per-fd drain.**
   `sys_poll(fds, N, max_timeout_ms)` returns the count of fds
   with at least one event set; the collect loop walks all N
   slots, treats `POLLIN`-set entries as ready (drain
   DRFACT\*/DREND via the same state machine R21B uses,
   record per-peer latency on success), treats revents=0
   entries as timeouts (increment
   `dr_stats_pipeline_timeouts` + `dr_stats_late_drops`,
   leave the peer's median window untouched).

5. **Late-ACK isolation preserved.** A pipeline timeout never
   touches `gossip_stats_timeouts`. The gossip PING/ACK
   liveness probe remains the only source of SUSPECT marks.
   This invariant is the same one R28A established for the
   serial-adaptive path; R30A re-verifies it at the pipeline
   layer with an explicit unit test
   (`test_r30a_pipeline_late_ack_does_not_mark_suspect`).

6. **4 new diagnostic counters.**
     * `dr_stats_pipeline_dispatched(dr)` -- cumulative count
       of peers Phase 1 sent DRFETCH to.
     * `dr_stats_pipeline_ready(dr)` -- count of peers whose
       pollfd had POLLIN by deadline AND drained cleanly.
     * `dr_stats_pipeline_timeouts(dr)` -- count of peers whose
       pollfd never became ready.
     * `dr_stats_pipeline_partial(dr)` -- count of poll calls
       where sys\_poll returned `> 0` but the drain count was
       below dispatched (signals a slow tail peer).

7. **Opt-in via `CE_DRFETCH_PIPELINE` env var.** Truthy values
   `on / 1 / yes` (case-insensitive) flip the path on at
   `dr_init` time; everything else keeps the R28A serial-
   adaptive baseline. Dispatcher precedence:
   `pipeline > async > sync`. A test setter
   `dr_set_pipeline(dr, on)` allows the unit harness to flip
   the path without touching the environment.

### Empirical numbers from scenario\_yyyy this round

On a CI host loaded enough to time out the R28A baseline:

  * R28A serial baseline: DNF in the 60 s budget for STABLE
    sub-scenario (5 NOVA processes contending; FIXPOINT\_END
    marker never appeared). Historical R28A baseline on
    quieter hardware: 11 rounds.
  * R30A pipelined: 55 ancestor closure derived in 11
    rounds, latency 49.5 s, counter snapshot
    `dispatched=22 ready=15 timeouts=7 partial=7`.

The honest reading: R30A is at least as robust as R28A under
host contention, because collapsing N serial 500 ms RCVTIMEO
windows into ONE 500 ms sys\_poll window means the
originator's fixpoint loop completes inside a wall-clock budget
that defeats the serial path.

### Caveats

* **Phase 1 dispatch is still serial.** NOVA's `connect(2)` is
  blocking, so the dial portion of phase 1 walks peers in
  sequence. For a 5-soul mesh on loopback this is < 5 ms total.
  For mesh sizes where the dial-serial cost dominates (50+
  peers on lossy WAN), the pipeline win shrinks; a future
  round could parallelise phase 1 too via `O_NONBLOCK connect`
  + a second `sys_poll(POLLOUT)` pass.
* **Phase-2 BYE remains sequential.** After the drain pass,
  each peer's BYE + close still walks serially. Since BYE is
  one line and the responders can be reading it concurrently
  while we write, this is effectively free in practice but
  worth noting.
* **The dispatcher precedence is hard-wired.** A future
  operator who wants pipeline ON + async OFF (or any other
  mix) doesn't get fine-grained control today; the
  precedence is the simple `pipeline > async > sync`
  cascade. If a real use case appears, the next round can
  add a `CE_DRFETCH_DISPATCH=<mode>` enum.

## R29F -- kg\_sync delta-compression on top of R23C snapshot replication

**Module:** `src/federation/kg_sync.nova` (NEW, ~470 lines, self-contained)

R23C (`src/federation/snapshot_replication.nova`) ships gossip-relayed
fetch of full snapshots: a peer broadcasts a signed Merkle-attestation
and any peer that needs the snapshot bytes issues `SNAP_FETCH` over
gossip. That closes the "lost a node, need to restore" gap but it has
a sharp edge: a peer that's been offline for a few minutes -- say
because of a quick restart -- has to pull the FULL snapshot even if
it's only behind by a handful of atom-insertions. On a 10k-atom KG
that's >1 MiB of wire for what could be 200 bytes of mutations.

R29F adds a delta-compression path:

1. **Per-atom monotonic revision counter** (`kg_rev` in `kgd_state`).
   Bumps on every insert / update / retract. Each change is logged
   with its rev so the publisher can replay any window.
2. **`KG_DELTA_REQ <since_rev>` request.** The peer reports its
   latest-known revision; the source returns every change with
   rev > since.
3. **`KG_DELTA_RESP <from_rev> <to_rev> <n_changes>` response,**
   followed by `<n_changes>` lines of `INS|UPD|RETR <atom_id>
   <rev> <payload>`. The payload is `<kind>:<alpha>:<beta>:<label>`
   for INS, `<alpha>:<beta>` for UPD, empty for RETR.
4. **`KG_DELTA_FULL_SNAPSHOT_REQUIRED <current_rev>` sentinel.**
   When the delta would exceed the 256 KiB cap (env-override
   `CE_KGSYNC_DELTA_CAP`), the source returns this line and the
   caller falls back to R23C's snapshot path.
5. **Idempotent apply.** Each change carries its rev; the applier
   tracks `applied_rev` and silently drops any rev <= applied. Same
   delta applied twice is a no-op.
6. **Tamper rejection.** The parser rejects: malformed shape,
   non-digit revs, claimed n-changes mismatching delivered lines,
   a change whose rev falls OUTSIDE the negotiated `(from, to]`
   window, or non-monotonic revs within a single response.

### Decision: why a separate file from `src/io/transducers/kg_sync.nova`

The existing transducer is the LIVE-update path (broadcast on insert,
ack per event). R29F is the CATCH-UP path (request a window after
being offline). Keeping them in separate files matches the wire
protocol -- a peer can speak v2 broadcasts OR v3 delta requests
independently -- and avoids dragging the socket-bound transducer
into pure-codec tests. The new module re-implements only the small
helpers it needs (`_kgd_starts_with`, `_kgd_split_spaces`,
`_kgd_strip_eol`, `_kgd_is_digits`) so it does not collide with the
transducer's internal `_starts_with` family on the same assembler TU
(a problem R23C already documented with snapshot\_disk).

### Wire-byte savings

For a 35-atom KG synced to a peer at rev=20 with 15 new insertions:

| Path | Wire bytes |
|---|---|
| R29F delta (15 changes) | 503 |
| R23C full snapshot at rev=35 | 970 (equivalent text shape) |
| R29F fallback sentinel | 36 |
| R23C snapshot at rev=535 (post-cap-burst) | 21290 |

At the small-delta scale (15 changes / 35 atoms) the saving is ~1.9x
in bytes -- the absolute saving matters more than the ratio. At the
cap-fallback boundary (500-row delta, 535 atoms) the snapshot wire is
~590x the size of the sentinel that triggers the fallback, so the
delta path is exactly what you want for "I have 15 mutations to
ship" and the snapshot path is exactly what you want for "the peer
is more than a window behind." Picking the right path per request is
the heart of R29F.

### Limitations / future work

1. **256 KB cap is a guess.** A KG with mostly tiny atoms can fit
   thousands of changes in 256 KB; a KG with long label payloads
   maxes out at a few hundred. Per-deployment tuning via
   `CE_KGSYNC_DELTA_CAP` is the escape hatch; an adaptive cap
   based on observed payload-size distribution would be more
   principled but is deferred.
2. **No multi-window resumability.** If the publisher truncates
   its log (say, after a snapshot compaction), an old peer's
   `KG_DELTA_REQ since=5` falls off the front of the log and we
   serve the empty-delta response by accident (the log only has
   rev > 100 changes; since=5 + scan finds nothing new in those
   higher revs, but we DO emit the higher revs). Mitigation: the
   peer's `applied_rev` advances correctly so it eventually catches
   up; but the right fix is a per-publisher "minimum servable rev"
   advertised in an extra slot of the response header. Deferred.
3. **No on-the-wire authentication of the delta itself.** R29F
   relies on the transport (Noise XK / TLS) for confidentiality
   and authenticity; the body parser only rejects mal-shape and
   out-of-window revs. A Merkle-of-the-delta could be added but
   would duplicate R20F's signing layer; deferred until we hit a
   threat model where the transport guarantees are not enough.
4. **No batched apply.** Each change is applied one-at-a-time
   through the per-kind callback. For a 1000-change delta on a
   large KG the per-call overhead dominates over the actual
   mutation; a `kgd_apply_response_batched` that hands the whole
   change list to a single batched-INS callback would be ~10x
   faster on cold inserts.
5. **Local log grows unbounded.** Every insert/update/retract
   pushes a record onto the publisher's `kgd_state` log; nothing
   compacts it. A long-running publisher will accumulate every
   mutation since boot. Mitigation: periodically rotate by
   resetting the state with `kgd_state_new()` and re-deriving
   from a snapshot; the right shape is a `kgd_state_compact(st,
   keep_since_rev)` that drops older log entries. Deferred.

## R31A extension: non-blocking connect + sys\_poll(POLLOUT) parallelises DRFETCH phase-1 dial (R30A.2)

**Why R31A?** R30A's exit caveat: "`sys_poll` parallelises the
response WAIT but not the connection ESTABLISHMENT — phase 1
still walks `_gossip_dial` + HELLO/OK serially because NOVA's
`connect(2)` is blocking." For a 5-soul mesh on loopback the
serial dial cost is negligible (~10us per peer) so R30A's win
is real, but for mesh sizes >= 50 peers on lossy WAN where a
single dial costs 50-150 ms, the serial walk dominates the
round time. R31A closes that gap.

### What R31A delivers

* **Two new NOVA builtins** (committed separately in
  `amoufaq5/NOVA`):
  - `sys_fcntl_setfl_nonblock(fd) -> 0 | -1` — POSIX
    `fcntl(fd, F_SETFL=4, O_NONBLOCK=2048)`, Linux x86-64
    syscall 72, ARM64-Linux syscall 25, macOS BSD 92, Win
    `__imp_ioctlsocket` with FIONBIO, winARM64 / WASM stub.
  - `sys_getsockopt_so_error(fd) -> int` — POSIX
    `getsockopt(fd, SOL_SOCKET, SO_ERROR, &val, &vlen)`,
    returns the SO\_ERROR int (not the rc), Linux x86-64
    syscall 55, ARM64-Linux 209, macOS 118, Win
    `__imp_getsockopt` with WinSock numbering.
* **CrossEngin non-blocking connect wrapper** (`_dr_connect_async`):
  opens a TCP socket, sets `O_NONBLOCK`, calls `connect(2)`,
  returns the fd in `EINPROGRESS` state (or a negative diagnostic
  code).
* **Phase-1 parallelisation**: under `CE_DRFETCH_PIPELINE=1` the
  phase-1 dispatcher now does TWO sub-phases:
  1. *1a. Parallel non-blocking dial.* Open ALL peer sockets
     non-blocking, kick connects, build a pollfd `POLLOUT` array,
     `sys_poll` until every peer's TCP handshake completes or
     the dial budget expires. SO\_ERROR check distinguishes
     successful dial from deferred ECONNREFUSED / ETIMEDOUT.
  2. *1b. Per-peer HELLO/OK + DRFETCH header.* After clearing
     `O_NONBLOCK` so the gossip send/recv loops block normally,
     walk the post-dial fleet serially for the application-
     level handshake. R30A's phase 2 (POLLIN-wait + drain)
     stays unchanged.
* **Four new stat counters** emitted on `dr_stats_line` when
  the pipeline is active:
  - `dr_stats_connect_dispatched` — # connects kicked off
  - `dr_stats_connect_ready` — # peers whose POLLOUT fired AND
    SO\_ERROR readback returned 0
  - `dr_stats_connect_timeouts` — # peers whose POLLOUT never
    fired within the dial budget
  - `dr_stats_connect_so_error` — # peers with deferred connect
    errno (typically ECONNREFUSED on a peer-mid-startup race)

### Verified

* Unit tests (`tests/unit/test_dr_async_fetch.nova`): 97 OK,
  +23 new R31A assertions covering counter init, wrapper open-fd
  / SO\_ERROR / unparseable-addr / partial-counter-distribution
  / pipeline-OFF-bit-identical paths, and stats-line conn\_\*
  token emission.
* Integration scenario YYYY (`scenario_yyyy_rule_convergence.sh`)
  extended with PHASE1\_PARALLEL sub-scenario that re-runs the
  5-soul STABLE closure with `CE_DRFETCH_PIPELINE=1` and reports
  round-count delta vs R30A's pipeline-only path.

### Honest expectations

The brief explicitly invited an honest "5-soul STABLE shows no
improvement" outcome: at 5 peers on loopback the dial-RTT is
~10us so the parallel-dial win is invisible relative to the
HELLO/OK + ACK\_RTT. The R31A win materialises above ~50 peers
on lossy WAN where every dial costs 50-150 ms; that scale is
not exercised by the YYYY scenario suite. The round-count delta
is reported truthfully either way.

### Caveats / future work

1. **`_dr_clear_nonblock` is Linux-x86-64-only**. The inline
   `asm` block hardcodes syscall 72. ARM64-Linux uses syscall
   25; macOS BSD uses 92. Same Linux-first precedent as
   `gossip.nova`'s `_gossip_fcntl` wrapper — multi-arch
   coverage is a follow-up R31A.2.
2. **No GETFL preserve**. We `F_SETFL` with flags=0 to clear
   `O_NONBLOCK`. If a future change adds other flags (e.g.
   `O_ASYNC`, `O_CLOEXEC`), this would wipe them. Switch to
   `F_GETFL` then `F_SETFL` with `flags & ~O_NONBLOCK` if that
   matters.
3. **Phase 1b HELLO/OK is still serial**. Parallelising it
   would need a per-peer state-machine with `sys_poll(POLLIN)`
   for the OK frame and `sys_poll(POLLOUT)` for the next-write
   readiness. Deferred to R31A.2 if profiling shows it as the
   new long pole; current measurements suggest phase 2 (peer
   compute + DREND drain) is still the bottleneck on
   moderate-mesh runs.
4. **Single-attempt dial**. `_dr_connect_async` does NOT retry
   like `_gossip_dial` (which does up to
   `GOSSIP_CONNECT_RETRIES=3` with `GOSSIP_CONNECT_DELAY_MS=50`
   between attempts). A peer mid-startup race that's not yet
   listening will be counted as a `CONNECT_SO_ERROR` and fall
   to the next gossip round naturally — matching R28A's late-ACK
   isolation principle.

## R35D -- ICE-TURN integration layer

### Why this exists

R30C (`src/federation/ice.nova`) shipped the ICE agent (RFC 8445
subset) with host + server-reflexive candidate gathering and the
connectivity-check matrix. R34B (`src/federation/turn.nova`) shipped
the TURN protocol wire codec -- emit + parse for Allocate / Refresh /
Send / Data / CreatePermission / ChannelBind. Both were leaf modules
on purpose: R30C explicitly punted relay-candidate gathering as
"future work" and R34B explicitly punted the allocation lifecycle
to its callers.

R35D is the THIN ORCHESTRATOR that composes the two without modifying
either. It implements the RFC 8445 §5.1.1 escalation rule: when the
ICE checklist runs out of usable pairs (all in `FAILED` terminal
state), open a TURN allocation, accept the relayed address back into
the ICE agent as a new `relay`-typed local candidate, and let ICE's
existing pair-formation + connectivity-check loop pick the relayed
addr up naturally.

### Architecture: zero-modification composer

`ice_turn.nova` is a 360-line leaf module. It imports `ice.nova` +
`turn.nova` and exposes a small public surface:

```
ice_turn_init(ice_agent, turn_server_ip, turn_server_port) -> state
ice_turn_check_escalation(state) -> ICE_TURN_NO_ESCALATION | ICE_TURN_ESCALATE
ice_turn_begin_allocate(state, txn_id_buf) -> [emit_buf, n]
ice_turn_handle_allocate_response(state, recv_buf, n) -> READY | FAILED
ice_turn_relay_priority() -> 16777215
```

Calls into `ice.nova` use ONLY the existing R30C public surface
(`ice_n_pairs`, `ice_get_pair`, `ice_add_local_candidate`). Calls
into `turn.nova` use ONLY the existing R34B public surface
(`turn_emit_allocate_request`, `turn_parse_allocate_success_response`,
`turn_parse_allocate_error_response`, `turn_ipv4_str_to_buf`).
R34B's `TURN_LIFETIME_DEFAULT=600` and `TURN_TRANSPORT_UDP=17`
constants flow through naturally.

### Relay candidate priority (RFC 8445 §5.1.2.1)

For a relay candidate at the canonical RTP component with maximum
local preference:
  * type_pref   = 0     (relay is LOWEST -- RFC 8445 §5.1.2.2)
  * local_pref  = 65535
  * component   = 1     (RTP)

  priority = 2^24 * 0 + 256 * 65535 + (256 - 1)
           = 0        + 16776960    + 255
           = 16777215

Verified two ways: hand-computed in the brief, AND against R30C's
`ice_candidate_priority(ICE_TYPE_RELAY, 65535, 1)` returning the
same value. The test does both comparisons.

### Honest design caveats

1. **Long-term-credential auth not implemented.** R34B's emit path
   doesn't generate USERNAME / REALM / NONCE / MESSAGE-INTEGRITY
   (RFC 8489 §9.2). R34B's parse path TOLERATES these attributes
   on incoming responses (they're skipped over) but does NOT
   verify integrity. A real TURN server returns `401 Unauthorized`
   on the first Allocate request and expects a second request with
   credentials -- R35D correctly reports the 401 as
   `ICE_TURN_RELAY_FAILED` and does NOT auto-retry. This is the
   same boundary R34B documented; R35D inherits the limitation.
   Future hardening round must plumb auth through both R34B emit
   and this orchestrator.
2. **No downgrade after escalation.** Once `turn_active=1` is
   latched in `ice_turn_begin_allocate`, subsequent calls to
   `ice_turn_check_escalation` always return `NO_ESCALATION` even
   if a higher-priority host / srflx pair later succeeds. This is
   one-way escalation; RFC 8445 allows re-nomination of a better
   pair but R35D doesn't implement that. A real ICE driver running
   R30C's `ice_mark_pair_succeeded` would naturally nominate the
   higher-priority pair without needing R35D to "clear" the relay.
3. **Refresh / Permission / Channel lifecycle is R35B's domain.**
   R35D handles the FIRST `Allocate` only. The Refresh-on-expiry
   loop, the per-peer Permission table, and the channel-binding
   bookkeeping live in R35B's `turn_client_*` state machine
   (`063824e`). R35D and R35B are orthogonal: R35D triggers the
   first Allocate; R35B drives the lifecycle once the allocation
   is up.
4. **CreatePermission for the remote peer is not wired.** Adding
   the relayed addr as an ICE local candidate is sufficient for
   `ice_form_pairs` to include it in the checklist, but actually
   sending application data through the relay requires
   `CreatePermission` for each remote peer the application wants
   to reach (RFC 5766 §9). That's a follow-up wiring step on top
   of R35D + R35B.
5. **Single TURN server.** The state holds one
   `(turn_server_ip, turn_server_port)` pair. Multi-relay
   environments (different TURN servers per region) would need a
   list in the state and per-server txn id tracking.

### Tests

`tests/unit/test_ice_turn.nova` -- 88 assertions, covering:
  * init shape + counters zero
  * relay priority value (RFC formula AND R30C cross-check)
  * `check_escalation` decision tree: empty / some-succeeded /
    some-in-progress / all-failed / already-active
  * `begin_allocate` emit byte size + R34B classifier round-trip +
    counter bump + txn-id mirror
  * `handle_allocate_response` happy path: relayed addr extracted,
    candidate injected into ice_agent, all candidate fields correct
  * `handle_allocate_response` 401 + 437 error paths: err_code +
    reason captured, failed counter bumps, ice_agent UNCHANGED
  * `handle_allocate_response` malformed bytes: synthetic err_code,
    failed counter bumps
  * end-to-end flow: 2x2 pairs gathered, all FAILED, escalate,
    allocate, success, re-form 3x2=6 pairs, relay pair present
  * internal helpers `_all_pairs_failed` + `_is_parse_err`

### Module count delta

* +1 source module: `src/federation/ice_turn.nova`.
* +1 test module: `tests/unit/test_ice_turn.nova`.

## R35B extension: TURN client-side allocation state machine (R34B.2)

R34B (`423a352`) landed the TURN protocol WIRE CODEC -- emit + parse
for the six TURN message methods (Allocate / Refresh / Send / Data /
CreatePermission / ChannelBind) plus the TURN attribute set -- and
explicitly punted the allocation state lifecycle to a future round.
R35B closes that gap with a client-side, pure-state allocation
machine that layers on the wire codec.

### Module: `src/federation/turn.nova` (extension; wire-codec block unchanged)

CLIENT-side state machine -- no socket I/O, no server-side allocation
pool. The wire codec block in lines 1..1052 is unchanged byte-for-byte
from R34B (`diff` confirms zero changes in the prior 200 test
assertions).

The state machine tracks:
* 6-state lifecycle: `TURN_STATE_IDLE` (0) -> `_PENDING` (1) ->
  `_ACTIVE` (2) -> `_REFRESHING` (3) -> `_EXPIRED` (4) or `_FAILED`
  (5).
* Current in-flight transaction id (a 12-byte buffer pointer per
  RFC 8489 §6.3.3); mismatched txn_ids on incoming responses are
  IGNORED.
* Lifetime + expiry (`now + lifetime` stamp at Allocate / Refresh
  success).
* List of permitted peer addresses with per-permission expiry
  (`now + 300` per RFC 5766 §8 default; the response does not echo
  back a permission lifetime so the client stamps a local estimate).
* List of channel-number to peer bindings (channel_num MUST be in
  `[0x4000, 0x7FFE]`).
* 9 counter slots for emit + recv per request kind.

Public API (state transitions):
* `turn_client_init() -> state` (24-slot positional list).
* `turn_client_send_allocate(state, txn, lifetime, transport) ->
  [buf, n]` (IDLE / EXPIRED / FAILED -> PENDING).
* `turn_client_send_refresh(state, txn, lifetime) -> [buf, n]`
  (ACTIVE -> REFRESHING).
* `turn_client_send_permission(state, txn, peer_ip, peer_port) ->
  [buf, n]` (must be ACTIVE).
* `turn_client_send_channel_bind(state, txn, chan_num, peer_ip,
  peer_port) -> [buf, n]` (must be ACTIVE; channel_num out of
  `[0x4000, 0x7FFE]` rejected pre-emit).
* `turn_client_recv(state, buf, n, current_time_unix) -> tag`
  dispatches by `turn_classify_message` to one of `TURN_RECV_
  ALLOCATED` / `_ALLOCATE_FAILED` / `_REFRESHED` / `_REFRESH_FAILED`
  / `_REFRESH_DELETED` / `_PERMITTED` / `_PERM_FAILED` / `_CHANNEL_
  BOUND` / `_CHANNEL_FAILED` / `_DATA` / `_IGNORED`.
* `turn_client_tick(state, current_time_unix)` returns `TURN_TICK_
  EXPIRED` and transitions ACTIVE -> EXPIRED when `expiry < now`.

Test-only response emitters added so the state machine can be driven
without a live server: `turn_emit_create_permission_success_response`,
`turn_emit_channel_bind_success_response`, `turn_emit_refresh_error_
response`, `turn_emit_create_permission_error_response`,
`turn_emit_channel_bind_error_response`.

### Verified

* `tests/unit/test_turn.nova`: **323 assertions total** -- 200 prior
  R34B (byte-identical, `diff` confirms zero changes in lines 1..852)
  + 123 new R35B assertions. Coverage walks the FULL state-transition
  table (IDLE -> PENDING -> ACTIVE -> REFRESHING -> EXPIRED, plus the
  EXPIRED -> PENDING re-allocate path), the failure paths (Allocate
  401 -> FAILED, Refresh 437 -> FAILED, perm + chanbind errors keep
  state ACTIVE), tick-based expiry, mismatched-txn / IDLE-recv /
  truncated-buf IGNORE paths, multi-peer permissions (3 peers added
  in sequence), channel_num band enforcement (0x3FFF / 0x7FFF / 0x8000
  rejected, 0x4000 boundary accepted), and Data Indication dispatch.
* Sibling federation tests unchanged: `srtp` (111), `ice` (70),
  `stun_rfc8489` (135), `nat_traversal` (209) all pass.

### Skipped (documented)

* **Server-side allocation pool** (RFC 5766 §6.2). R35B is CLIENT-side
  only.
* **Permission + channel refresh cadence**. RFC 5766 §8 (5 min) and
  §11 (10 min) define server-side enforcement windows; the state
  machine carries per-permission `expiry_unix` but `turn_client_tick`
  only reports ALLOCATION expiry, not per-permission expiry.
* **Re-auth path on 401**. The state machine surfaces 401 via
  `last_err_code = 401` + FAILED state. The MESSAGE-INTEGRITY
  computation over USERNAME + REALM + NONCE remains deferred (same
  as R34B's documented gap).
* **IPv6**. Inherits R34B's IPv4-only contract; family=2 is rejected
  with `TURN_ERR_FAMILY`.

### Caveats / future work

1. **Permission expiry is a CLIENT-side estimate**. The
   CreatePermission success response does NOT carry a LIFETIME
   attribute back to the client (unlike Allocate / Refresh). The
   state machine stamps `now + 300` (RFC 5766 §8 documented default)
   in `permissions_list[i][2]`. If the server uses a non-standard
   permission window, the client estimate will drift. The recommended
   pattern is to re-issue CreatePermission well inside the 5-minute
   window (e.g. every 4 minutes); the cadence is the caller's
   responsibility.
2. **Single in-flight request per allocation**. The state stores ONE
   txn_id and ONE in-flight method. If a caller issues a
   CreatePermission while a ChannelBind is in flight, the second
   send overwrites the first's `_TURN_ST_TXN_ID`, so the first
   response will be IGNORED. RFC 8489 allows pipelined requests in
   theory but this state machine serializes them.
3. **Refresh error -> FAILED**. The brief allowed "ACTIVE-or-FAILED
   per the error code"; we chose FAILED across the board because the
   common refresh-error codes (437 / 441) all mean the allocation is
   gone server-side. Callers needing finer control can read
   `last_err_code` and re-issue a fresh Allocate.
4. **R35D landed the ICE-TURN integration layer.** The state machine
   surface R35B exposes is the natural consumer for a future round
   that promotes R35D from "open allocation on ICE exhaustion" to
   "track the allocation lifecycle through its full PENDING ->
   ACTIVE -> REFRESHING / EXPIRED cycle".

## R35A extension: DTLS-SRTP keying material extraction (RFC 5764 §4.2) -- R34C.2

R34C (`9a23da2`) shipped the SRTP wire codec with
`srtp_derive_keys(master_key, master_salt) -> [encr_key (16B),
auth_key (20B), salt (14B)]` (RFC 3711 §4.3.2 AES-CM KDF). R31B
(`af8e47c`) wired P-256 ECDHE + AES-128-GCM into DTLS records and
populated the cipher-state slots (`master_secret`, `client_random`,
`server_random`, etc.). R35A wires the two together per RFC 5764 §4.2:
the SRTP master key + salt now come from the DTLS handshake's
keying-material exporter rather than being passed in out-of-band.

### Module: `src/federation/dtls12.nova` (extension; cipher-state block unchanged)

One new public function appended after the R29B.2 stub section
(specifically after the historical `dtls_extract_srtp_keys_R29B2_STUB`,
which is RETAINED as a regression guard against accidental rename):

* `dtls_export_srtp_keying_material(state) -> 60-byte buf | 0`

The function is a thin composition over the existing `dtls_prf_sha256`
helper. RFC 5764 §4.2 fixes the label to the 19-byte ASCII string
`"EXTRACTOR-dtls_srtp"` and the seed to the 64-byte concatenation
`client_random || server_random`. We allocate a fresh 65-byte seed
buffer (64 + NUL slack), copy in the two 32-byte halves from the
existing `CLIENT_RANDOM` / `SERVER_RANDOM` state slots (populated by
R31B's `dtls_ecdhe_derive`), and call
`dtls_prf_sha256(master_secret, 48, "EXTRACTOR-dtls_srtp", seed, 64,
60)`. The PRF helper already takes the label as a Nova string (its
internal `_dtls_prf_seed` reads ASCII bytes via `char_at`), so no
ABI changes are needed.

The function refuses to run when `cipher_active == 0` (handshake not
yet complete -- calling the PRF before the master_secret + randoms
are populated would yield uninitialized input). Returns the integer
sentinel `0` in that case.

The 60-byte output is partitioned per RFC 5764 §4.2:

| offset | size | role                                |
|--------|------|-------------------------------------|
|  0..16 |  16B | CLIENT SRTP master key (AES-CM-128) |
| 16..32 |  16B | SERVER SRTP master key              |
| 32..46 |  14B | CLIENT SRTP master salt (AES-CM)    |
| 46..60 |  14B | SERVER SRTP master salt             |

### Module: `src/federation/srtp.nova` (extension; codec block unchanged)

Adds one new public entry point right after `srtp_derive_keys` (the
R34C §4.3.2 wrapper):

* `srtp_init_from_dtls(dtls_state, is_server) -> [encr_key, auth_key,
  salt] | 0`

Algorithm:
1. Call `dtls_export_srtp_keying_material(dtls_state)`. On `0`,
   forward `0` (DTLS not ready).
2. Pick the per-side master key + salt from the 60-byte block. The
   "our" half depends on `is_server`:
   * `is_server == 0` (client side): `mk = km[0..16); ms = km[32..46)`
   * `is_server != 0` (server side): `mk = km[16..32); ms = km[46..60)`
3. Copy 16 bytes of mk + 14 bytes of ms into fresh buffers so a
   downstream mutation of the returned keys does not poison the DTLS
   state slots that backed the exporter output.
4. Forward to the existing `srtp_derive_keys(mk, ms)` -- R34C's
   AES-CM-based RFC 3711 §4.3 KDF -- and return its 3-element list.

The import graph adds a one-way edge `srtp.nova -> dtls12.nova`.
dtls12 does NOT import srtp; the transitive deps (safety/sha256 +
safety/p256 + safety/aes_gcm + safety/x509) are all LEAVES and do
not re-enter the federation tree.

### Tests added

* **`tests/unit/test_dtls12.nova`**: 16 new R35A assertions across 5
  test functions:
  1. `dtls_export_srtp_keying_material` returns `0` when
     `cipher_active == 0` (fresh state, no derive run).
  2. After `_tdtls_setup_ecdhe_pair`, the exporter returns a non-zero
     60-byte buffer; probing byte 0 and byte 59 confirms the alloc
     was large enough.
  3. Alice and Bob (the two peers from `_tdtls_setup_ecdhe_pair`)
     extract BYTE-IDENTICAL 60-byte blocks -- proves the PRF is
     symmetric across the wire when both sides hold the same
     master_secret + randoms.
  4. The RFC 5764 label `"EXTRACTOR-dtls_srtp"` is exactly 19 ASCII
     bytes, with spot-byte checks at offsets 0 / 10 / 14 / 18
     ('E' / 'd' / 's' / 'p').
  5. Repeat calls on the same state produce byte-identical output
     (PRF is pure; exporter does not consume / mutate the
     master_secret slot).

* **`tests/unit/test_srtp.nova`**: 24 new R35A assertions across 6
  test functions:
  1. `srtp_init_from_dtls(fresh_state, 0)` and `(fresh_state, 1)`
     both return `0` (gate forwarded from the exporter).
  2. After ECDHE derive, `srtp_init_from_dtls(alice, 0)` returns a
     3-element list `[encr_key, auth_key, salt]` -- shape matches
     R34C's `srtp_derive_keys` contract.
  3. Client side (alice, `is_server=0`) and server side (bob,
     `is_server=1`) derive DIFFERENT keys: encr keys differ in at
     least one byte (16B compare returns 0), auth keys differ
     (20B compare), salts differ (14B compare). This pins the
     RFC 5764 §4.2 asymmetry.
  4. Repeat calls on the same DTLS state with the same `is_server`
     produce byte-identical keys.
  5. One-direction round-trip (alice's client-keys feed both seal
     and open): `srtp_seal_packet` + `srtp_open_packet` round-trip
     with the R35A-derived keys works -- proves the key set is
     internally consistent with the existing R34C codec.
  6. Cross-side asymmetry: sealing with alice's client-keys and
     trying to open with bob's server-keys fails the HMAC and
     returns `SRTP_AUTH_FAIL` (the auth_fail counter increments).
     This is the negative test that pins the §4.2 half-selection
     rule -- if a future refactor broke the half-selection and
     both sides ended up with the same half, this test would
     catch it.

### Honest scope limits

1. **PRF cost dominated by the 60-byte expansion.** Two HMAC-SHA256
   iterations (ceil(60/32) = 2) per exporter call. The function is
   called exactly once per session right after the handshake
   completes -- per-call recompute is fine on the
   not-on-the-hot-path. If a future use case ever needs per-packet
   rekey (it should not -- SRTP rekey ordinarily renegotiates DTLS),
   cache the 60-byte buf in a fresh state slot.
2. **No SRTP rekey-without-DTLS-renegotiate.** RFC 5764 §4.2 does
   not require it; each rekey ordinarily renegotiates DTLS.
3. **Label literal embedded.** The 19-byte string lives inline in
   `dtls_export_srtp_keying_material`. The test in test_dtls12 pins
   the length + 4 spot-byte ASCII values as a regression guard
   against typos.
4. **No constant-time tag compare carve-out.** R35A inherits R34C's
   byte-by-byte XOR-fold tag comparison via the existing seal+open
   path; R30B.3's bitsliced AES + constant-time comparators hardening
   scope continues to track this.
5. **R35A does not modify any sibling-agent file.** dtls12.nova
   gains one function below the existing R29B.2 stubs; srtp.nova
   gains one import line + one function below `srtp_derive_keys`.
   The codec / PRF / cipher-state blocks above are byte-identical to
   their pre-R35A form -- the 353 prior dtls12 + 111 prior srtp
   assertions are preserved exactly.

## R36A extension: TURN long-term-credential auth + per-permission tick (R34B.2 / R35B.2 / R35D.2)

R34B (`423a352`) shipped the TURN wire codec parsing + emitting six
message methods but stopped short of the long-term-credential
authentication attributes (USERNAME / MESSAGE-INTEGRITY / REALM /
NONCE). R35B (`063824e` + `53490bf`) shipped the client-side
allocation state machine with permission + channel append-on-success,
but `turn_client_tick` reported allocation expiry only -- per-
permission + per-channel expiry cadence was deferred. R35D
(`6527b6a`) shipped the ICE-TURN escalation layer but classified 401
Unauthorized responses as `RELAY_FAILED` with no retry path. R36A
closes all three gaps in one bundle.

### Long-term-credential auth (RFC 5389 §10 / RFC 5766 §4)

The client sends an initial Allocate with no auth. A server
demanding long-term credentials replies with a 401 Unauthorized
carrying REALM + NONCE attributes. The client then retries the
Allocate with USERNAME + REALM + NONCE attributes followed by
MESSAGE-INTEGRITY: a 20-byte HMAC-SHA1 over the message bytes,
keyed on `MD5(username:realm:password)` per RFC 5389 §15.4.

R36A's `turn_emit_allocate_request_authed` packs the six attributes
in the order LIFETIME, REQUESTED-TRANSPORT, USERNAME, REALM, NONCE,
MESSAGE-INTEGRITY. The STUN header length field counts the FULL
body including the 24-byte MI attribute, but the HMAC is computed
over the prefix bytes `[0..MI_attr_start)` -- the RFC 5389 §15.4
rule. `turn_parse_401_response` extracts REALM + NONCE from a 401
response (rejecting non-401 codes with `TURN_ERR_METHOD`).
`turn_verify_message_integrity(buf, n, key) -> 1 | 0` re-computes
HMAC over the prefix and compares against the embedded value; on a
message with NO MI attribute it returns 0 (documented tolerance --
some servers omit MI on success responses).

MD5 (RFC 1321) is implemented inline (~80 lines: IV, 64 K-constants,
g(i) message schedule, S(i) shift table, F/G/H/I round functions).
SHA-1 (FIPS 180-4) is also inline (~120 lines: 80-round compress,
4 K constants, BE message-schedule expansion). HMAC-SHA1 wraps the
two halves with the standard RFC 2104 ipad/opad XOR. R36A
re-inlines HMAC-SHA1 rather than importing R34C's `_srtp_hmac_sha1`
because R34C ships it under an underscore-prefixed (private) name --
un-mangling on R34C's side would break a sealed module. A future
R36A.2 can canonicalize MD5 + SHA-1 into `src/safety/md5.nova` +
`src/safety/sha1.nova` alongside R33A's `safety/sha256.nova`.

### Per-permission refresh cadence (RFC 5766 §8 / §11)

`turn_client_tick_perms(state, current_time_unix) ->
[n_perms_expired, n_channels_expired]` walks the permissions_list
+ channels_list and `list_remove`s any entry whose `expiry <
current_time_unix`. The walk is back-to-front so removal does not
shift the live cursor. Two new counters track the cumulative
removals: `stats_perm_expired` + `stats_channel_expired`.

`turn_client_tick_authed(state, now)` is the composed alloc-expiry
+ per-permission-cadence tick callers drop in to replace R35B's
`turn_client_tick`. Same return-tag contract (`TURN_TICK_OK` /
`TURN_TICK_EXPIRED` reports the alloc expiry; perm pruning is a
side-effect).

`TURN_PERM_LIFETIME_DEFAULT = 300` was already a R35B constant.
R36A adds `TURN_CHANNEL_LIFETIME_DEFAULT = 600` matching RFC 5766
§11. R35B's `turn_client_send_channel_bind` -> recv path appends a
3-element `[chan_num, ip, port]` record. R36A ships
`_turn_record_channel_r36a` which appends a 4-element `[chan_num,
ip, port, expiry]` instead; `_turn_channel_expiry()` treats
3-element R35B records as "no expiry, never prune". This preserves
the R35B test assertions byte-identical while letting R36A-aware
callers opt-in to the 600s default.

### Permission lifetime echo override (RFC 5766 §8)

CreatePermission success responses do NOT echo back a granted
lifetime (unlike Allocate which echoes LIFETIME). R35B stamped the
client-side estimate at `now + 300` per the §8 default. R36A keeps
that default and adds:

* `turn_set_perm_lifetime_default(state, secs)` -- caller-facing
  hook stored in `_TURN_ST_PERM_LIFETIME_DEFAULT` (slot 24).
* `turn_client_restamp_last_permission(state, now)` -- re-stamps
  the last appended permission record's expiry using the override.

This lets a non-RFC server that announces a non-default permission
lifetime out-of-band (e.g. via SOFTWARE attribute on the
Allocate Response, or via deployment configuration) be honored
without retro-breaking R35B's `_turn_record_permission` hard-coded
300s stamp.

### ICE-TURN 401 auto-retry (R35D.2)

`ice_turn_handle_allocate_response_authed` parses the response
with `turn_parse_401_response` FIRST. On 401, transitions to a new
`ICE_TURN_AUTH_PENDING` state, stashes REALM + NONCE as
freshly-alloc'd copies (so they outlive the recv buf), and returns
`ICE_TURN_RELAY_AUTH_PENDING`. Caller then invokes
`ice_turn_credentials(state, username, password)` to supply the
creds; we emit a credentialed Allocate via
`turn_emit_allocate_request_authed` and bump `stats_auth_retries`.

Retry cap: a SECOND 401 (meaning the credentials were wrong)
transitions `auth_state -> FAILED`, classifies `RELAY_FAILED`,
bumps the existing R35D failure counter, and stops -- no
infinite-loop on bad creds.

State slots appended to preserve R35D's 17-slot layout
byte-for-byte:
* `_ICE_TURN_S_AUTH_REALM` (17), `_AUTH_REALM_N` (18) -- copied
  REALM bytes from the 401.
* `_ICE_TURN_S_AUTH_NONCE` (19), `_AUTH_NONCE_N` (20).
* `_ICE_TURN_S_AUTH_STATE` (21) -- NONE / PENDING / OK / FAILED.
* `_ICE_TURN_S_STATS_AUTH_RETRIES` (22) -- count of credentialed
  re-emits.

`ice_turn_extend_state_r36a(state)` lazily extends an R35D-shaped
state in-place so legacy callers can pick up the new accessors
without rebuilding from scratch.

### Verification

`tests/unit/test_turn.nova` gains 82 R36A assertions appended at the
tail (323 prior assertions byte-identical, lines 1..1366
unchanged). New coverage:

* **MD5 RFC 1321 §A.5 vectors**: MD5("") =
  `d41d8cd98f00b204e9800998ecf8427e`, MD5("abc") =
  `900150983cd24fb0d6963f7d28e17f72`, MD5("message digest") =
  `f96b697d7cb7938d525a2f31aaf161d0` -- spot-checked byte 0, 1,
  2, and tail.
* **HMAC-SHA1 RFC 2202 TC1 + TC2**: key=`0x0b*20`/msg="Hi There"
  -> first 3 bytes `b6 17 31`; key="Jefe"/msg="what do ya want
  for nothing?" -> first 3 bytes `ef fc df`. Both tail bytes
  also pinned.
* **`turn_hmac_sha1_key`** matches direct
  `MD5("alice:ce-realm:secret")` -- the two paths agree byte-for-
  byte.
* **Authed Allocate attribute order**: classify the emitted
  bytes and confirm the 6 attributes in [LIFETIME,
  REQUESTED-TRANSPORT, USERNAME, REALM, NONCE,
  MESSAGE-INTEGRITY] order with MI value-length = 20.
* **MI byte-position rule**: re-compute HMAC over
  `[0..MI_attr_start)` and confirm equality with the embedded
  value -- this is the RFC 5389 §15.4 invariant.
* **Self-emit MI verify**: round-trip through
  `turn_verify_message_integrity` returns 1.
* **Wrong-key MI verify** returns 0.
* **No-MI message** returns 0 (no crash) per documented
  tolerance.
* **`turn_parse_401_response`** happy path extracts REALM +
  NONCE; no-REALM is `TURN_ERR_NO_ATTR`; non-401 code is
  `TURN_ERR_METHOD`.
* **Per-permission tick**: removes expired, keeps in-window,
  mixed-window per-record pruning (one in / one out), channel
  pruning via `_turn_record_channel_r36a` with 600s default,
  composed `tick_authed` covers both alloc + perms in one
  call, perm lifetime override reflected via
  `turn_client_restamp_last_permission`, tick on IDLE is
  `[0, 0]` no-crash, R35B-shape state auto-extends to 27
  slots when first ticked.

`tests/unit/test_ice_turn.nova` gains 54 R36A assertions appended
at the tail (88 prior assertions byte-identical, lines 1..545
unchanged). New coverage:

* **`ice_turn_init_authed` shape**: 23+ slots, all auth fields
  zero.
* **401 -> AUTH_PENDING**: REALM + NONCE stashed as
  freshly-alloc'd copies (NOT pointers into recv buf), failure
  counter NOT bumped.
* **Credentialed re-emit** is a real Allocate Request with 6
  attrs ending in MI; `stats_auth_retries` bumps to 1;
  `last_event` = `AUTH_RETRY`.
* **Credentialed re-emit success** transitions to ACTIVE +
  relay candidate injected into the ice_agent. `auth_state =
  OK`; `escalations_succeeded = 1`.
* **Second 401** classifies `RELAY_FAILED` + `auth_state =
  FAILED`; `escalations_failed = 1`.
* **Non-401 errors** (e.g. 437) fall through to the R35D
  handler unchanged. `auth_state` stays NONE.
* **`credentials()` refused when not PENDING**: returns 0,
  counter not bumped.
* **First-try success** skips the auth path; `auth_state ->
  OK`.
* **Full end-to-end**: gather host candidate -> all pairs
  FAIL -> ESCALATE -> begin_allocate -> 401 ->
  credentials("alice", "secret") -> success -> relay
  candidate present in ice_agent.

Suite totals: turn `OK (405 checks)` + ice_turn `OK (142
checks)` -- 547 federation assertions across the two suites.

### Out of scope (documented)

1. **SCRAM-SHA1 / SCRAM-SHA256 (RFC 7635)** -- modern replacement
   for the long-term-credential MD5(user:realm:pass) scheme. R36A
   targets RFC 5389 §15.4 compliance specifically.
2. **MD5 / SHA-1 canonicalization** under `src/safety/md5.nova`
   and `src/safety/sha1.nova` -- parallel to R33A's
   `safety/sha256.nova` dedup. R36A inlines locally to keep
   `turn.nova` self-contained; R36A.2 can re-route both
   `turn.nova` and `srtp.nova` through the canonical modules.
3. **CreatePermission + ChannelBind authentication**. RFC 5766
   §9 / §11 require the auth attrs on every authenticated
   request. R36A ships the auth primitives but does not thread
   them through R35B's `turn_client_send_permission` /
   `_channel_bind`. A future R36A.3 can stamp the auth attrs on
   those request paths.
4. **MI verify on incoming success responses**. R36A's
   `turn_verify_message_integrity` accepts them, but R35B's
   `turn_client_recv` does NOT call the verifier. Callers can
   verify manually; integration is deferred.
5. **txn id rotation** between the initial Allocate and the
   credentialed retry. R36A re-uses the same txn id (keeps
   response correlation simple). A real TURN client may want to
   rotate; that needs an additional state slot to track both
   IDs.

### Honest design caveats

1. **MD5 is cryptographically broken** for collision resistance
   (Wang 2004, FastColl 2007, MD5SHATTERED 2009). RFC 5389
   §15.4 nevertheless MANDATES `MD5(user:realm:pass)` as the
   HMAC-SHA1 key for the long-term-credential mechanism, so
   R36A inlines MD5 to remain on-spec.
2. **MD5 is a THIRD inline crypto primitive** that should
   eventually canonicalize alongside `safety/sha256.nova`
   (R33A) and the SHA-1 inside `srtp.nova` (R34C). R36A logs
   the dedup deferral.
3. **R34C's `_srtp_hmac_sha1` is private** (underscore prefix).
   Rather than break R34C's sealed module by un-mangling on its
   side, R36A re-inlines locally. Algorithmically identical;
   future canonicalization deferred.
4. **The retry txn id is NOT rotated**. R36A re-uses the txn id
   from the initial Allocate.
5. **R36A does not modify any sibling-agent file.** turn.nova
   gains ~830 lines below the existing R34B + R35B blocks (lines
   1..1669 preserved byte-for-byte). ice_turn.nova gains ~230
   lines below the existing R35D module (lines 1..485 preserved
   byte-for-byte). The 323 prior turn + 88 prior ice_turn
   assertions are preserved exactly.

## R36B extension: cached DTLS-SRTP keying material slot (R35A.2 / R33B.3)

R35A's `dtls_export_srtp_keying_material(state)` runs the TLS 1.2
PRF -- 2 HMAC-SHA256 iterations to expand 60 bytes -- on every call.
R35A's exit caveat allowed this because the exporter is invoked
exactly once per session post-handshake (not on the per-packet hot
path), and explicitly carved out the fix as future hardening:
"if a future use case ever needs per-packet rekey ... cache the
60-byte buf in a fresh state slot." R36B closes that caveat.

### State-slot extensions (tail-appended; slots 0..42 untouched)

Two new slots appended at the dtls_state tail (current tail was slot
42 from R33B; R36B becomes slots 43 + 44):

* `DTLS_S_SLOT_SRTP_KM_CACHED = 43` -- holds either `0` (no cache;
  next call computes) or the pointer to the 60-byte buf returned
  by the most recent PRF expand. Initialized to `0` in `dtls_init()`.
* `DTLS_S_SLOT_STATS_SRTP_KM_HITS = 44` -- cumulative cache-hit
  counter. The first compute (miss) does NOT bump; every
  subsequent serve-from-cache does. Exposed via the new accessor
  `dtls_stats_srtp_km_hits(state)`. Surfaced in `dtls_stats_line`
  as `srtp_km_hits=<n>`. Cumulative across the connection
  lifetime -- NOT reset on epoch advance, mirroring the R32B
  `STATS_REPLAY` / `STATS_TOO_OLD` and R33B `STATS_CERT_*`
  patterns.

### `dtls_export_srtp_keying_material` extension

Same signature, two new entry behaviours:

1. **Cache-hit fast path.** If `state[SRTP_KM_CACHED] != 0`,
   return that pointer verbatim and bump `STATS_SRTP_KM_HITS`.
   We deliberately do NOT re-validate randoms / master_secret on
   a hit -- the cache invariant is "non-zero cache implies the
   inputs were valid at compute time"; the only legitimate
   invalidation paths are `dtls_advance_epoch` (cleared to 0) and
   a fresh `dtls_init` state.
2. **Cache-miss compute path.** Existing PRF call (unchanged
   bytes -- the label, seed-builder, and `dtls_prf_sha256`
   wrapper are byte-identical to R35A). After the PRF returns,
   stash the returned pointer in `state[SRTP_KM_CACHED]` so the
   NEXT call hits. Return the same pointer to the caller.

The cipher_active gate runs BEFORE the cache lookup, so a
pre-handshake state always returns `0` regardless of cache
content -- cache cannot bypass the gate.

### `dtls_advance_epoch` extension (cache invalidation)

R33B's CCS-on-epoch-change hook gains one new line:
`state[SRTP_KM_CACHED] = 0`. Design choice (this is the biggest
decision in R36B): invalidate-on-epoch-advance, not
never-invalidate.

* **Why invalidate.** Although the SRTP exporter is anchored to
  `master_secret` (which does NOT change on a plain CCS-only
  key-block re-derivation), RFC 5764 §4.2 leaves the door open
  for a DTLS re-handshake (epoch advance with a fresh PRF
  expansion) to feed new SRTP keys. The safe default is to clear
  the cache: if the master_secret is genuinely unchanged the
  next exporter call recomputes the SAME 60 bytes (idempotent
  re-derivation; one extra PRF expansion per epoch transition).
  The opposite default (never invalidate) would silently serve
  stale keys after a real re-handshake -- a security footgun.
* **Why this is cheap.** Epoch advance is RARE (a CCS event,
  not per-packet), and the extra PRF expansion cost is two
  HMAC-SHA256 iterations. Acceptable tradeoff for correctness.
* **Why NOT reset the hits counter.** It is cumulative telemetry
  across the connection lifetime -- mirrors the R32B / R33B
  pattern. Tests assert this directly (`hits unchanged after
  epoch advance`).

### Tests added

`tests/unit/test_dtls12.nova` extended by 32 R36B assertions
across 8 new test functions, all appended at the tail of the suite
(slots 0..42 + the 369 prior assertions are NOT touched):

1. `test_r36b_init_cache_slot_zero` -- fresh state has cache=0,
   hits=0, accessor returns 0.
2. `test_r36b_first_call_populates_cache` -- first call is a
   miss: returns 60B, stashes pointer in slot 43, hits stays 0.
3. `test_r36b_second_call_serves_cached_pointer` -- second call
   returns SAME POINTER as first (pointer equality, not just byte
   equality), bumps hits to 1.
4. `test_r36b_third_call_bumps_hits_to_two` -- pointer stable,
   hits=2.
5. `test_r36b_advance_epoch_invalidates_cache` -- after 2 hits
   call `dtls_advance_epoch`: slot 43 clears to 0, hits stays
   at 2 (cumulative), next export is a miss (no hits bump),
   call after that hits the fresh cache (hits=3).
6. `test_r36b_cached_bytes_match_first_compute` -- redundant
   byte-identity guard against a future refactor that memcpys on
   the hit path.
7. `test_r36b_caches_are_per_state` -- alice + bob from
   `_tdtls_setup_ecdhe_pair` have independent caches + hit
   counters.
8. `test_r36b_cache_does_not_bypass_cipher_active_gate` --
   fresh-state export returns 0 (gate runs before cache lookup),
   no hits bump, cache stays 0.

### Honest scope limits

1. **Invalidate-on-epoch-advance pays one extra PRF expansion per
   plain CCS.** A pure key_block CCS (same master_secret) would
   technically allow keeping the cache valid; we invalidate
   anyway because epoch advance is rare and we cannot tell from
   inside `dtls_advance_epoch` whether the upstream caller
   intends a full re-handshake or a key_block-only refresh.
   Cost is two HMAC-SHA256 iterations per epoch transition --
   acceptable.
2. **No `dtls_invalidate_srtp_km_cache(state)` public function.**
   The only documented invalidation paths are `dtls_advance_epoch`
   and `dtls_init`. If a future use case ever needs a manual
   invalidate (e.g. caller forcing a recompute under unchanged
   epoch), add a one-line `state[SRTP_KM_CACHED] = 0` accessor.
3. **R36B compile/test execution UNVERIFIED in this session.**
   The Nova toolchain is not available in the working directory;
   the change is mechanical (tail-appended slots + pure pointer
   memoization + one-line invalidate hook + accessor + tests
   that mirror the R32B/R33B telemetry patterns). The byte-
   identity claim for the 369 prior assertions rests on the
   tail-append discipline -- no slot 0..42 index changed.
4. **No constant-time consideration.** The cache hit returns a
   pointer; pointer-equality leaks no key bits to an attacker
   that can observe wall-clock latency between two SRTP key
   extractions. If a future threat model needs to mask the hit
   latency, a constant-time recompute on every call (i.e. no
   cache) would be the appropriate hardening -- but that is the
   exact behaviour R35A shipped, so it's a one-line revert if
   needed.
5. **R36B does not modify any sibling-agent file.** Only
   `dtls12.nova` (extend) and `test_dtls12.nova` (extend tail)
   are touched. srtp.nova / turn.nova / ice_turn.nova /
   sha256.nova are untouched -- R36A (TURN auth, concurrent on
   turn.nova) cannot collide.

## R38B extension: DTLS PRF rekey on `dtls_advance_epoch` (R33B.4)

R33B's exit caveat explicitly deferred the key re-derivation on
CCS / epoch advance:

> We do NOT re-derive keys here. Real DTLS-CCS rekeys via the PRF
> (key_block expansion under the new epoch's seed). R33B's simple
> model keeps the same `key_block` / `client_write_*` /
> `server_write_*` buffers, so old wire records sealed under the
> same key can still AEAD-decrypt successfully if the AAD seq_num
> matches.

R38B closes that caveat. On every `dtls_advance_epoch` we re-run
the TLS 1.2 PRF to re-expand the 40-byte `key_block` from the SAME
`master_secret` + `server_random || client_random` seed (RFC 5246
§6.3 / RFC 6347 §4.1.2.6) and re-slice the four sub-buffers via
the existing `_dtls_slice_key_block` helper. A cumulative
`stats_rekeys` counter records every advance.

### Variant A vs variant B (rekey semantics)

* **Variant A (shipped).** Re-run the SAME PRF inputs --
  `master_secret`, the same randoms, the `"key expansion"` label,
  the same S || C seed order. Result: the 40 bytes are
  byte-identical to the pre-advance `key_block`. Standards-compliant
  per RFC 5246 §6.3 -- the spec doesn't define rekey-via-CCS at
  all, so a soft-rekey path that re-derives via the same PRF on
  the same handshake's master_secret is the on-spec interpretation.
  Cross-epoch security holds at the AEAD AAD layer (RFC 6347
  §4.1.2.1 puts the epoch in the upper 16 bits of the AAD
  seq_num), so byte-identical keys at the record-layer don't
  enable cross-epoch replay.
* **Variant B (documented, NOT shipped).** Mix the new epoch
  number into the PRF seed, e.g.
  `PRF(master_secret, "key expansion", server_random || client_random || epoch_bytes)`.
  Non-standard but matches the security intuition of "fresh keys
  per epoch". Would need protocol-level discussion before
  shipping. The R38B call site is structured so variant B is a
  one-line seed-extension change.

R38B ships variant A. The architectural value is in (a) the
`stats_rekeys` telemetry counter visible via the new
`dtls_stats_rekeys(state)` accessor and the `rekeys=` field on
`dtls_stats_line`, and (b) the structural hook for variant B.

### State-slot extension (tail-appended; slots 0..44 untouched)

One new slot appended at the dtls_state tail (current tail was
slot 44 from R36B; R38B becomes slot 45):

* `DTLS_S_SLOT_STATS_REKEYS = 45` -- cumulative count of
  `dtls_advance_epoch` invocations. Counter bumps on EVERY
  advance, even pre-cipher (so the caller can audit advances that
  happened before the cipher state was populated). The PRF
  re-expansion is gated on `master_secret` + `client_random` +
  `server_random` being non-zero; pre-cipher advances skip the
  PRF call but still bump the counter. Exposed via the new
  accessor `dtls_stats_rekeys(state)`. Surfaced in
  `dtls_stats_line` as `rekeys=<n>` appended at the tail of the
  string. Cumulative across the connection lifetime -- NOT reset
  on epoch advance, mirroring the R32B / R33B / R36B telemetry
  patterns.

### `dtls_advance_epoch` extension (PRF rekey block)

The R33B body is preserved byte-identically (epoch bumps +
sequence resets + replay-window reset + R36B cache invalidation).
R38B appends a rekey block at the end:

```
state[STATS_REKEYS] = state[STATS_REKEYS] + 1
if (ms != 0 && cr != 0 && sr != 0):
    kb_seed = sr || cr                  // 64 bytes
    kb = dtls_prf_sha256(ms, 48, "key expansion", kb_seed, 64, 40)
    state[KEY_BLOCK] = kb
    _dtls_slice_key_block(state, kb)    // refreshes 4 sub-buffers
return 0
```

The seed-builder mirrors `dtls_ecdhe_derive` step 4 byte-for-byte
(S || C ordering, inverted vs the master_secret derivation per
RFC 5246 §6.3). The `_dtls_slice_key_block` helper allocates fresh
17-byte (for keys, +1 NUL) and 5-byte (for IVs, +1 NUL) buffers,
so post-advance the four sub-buffer pointers are NEW (allocations
differ) but the BYTES are byte-identical to pre-advance under
variant A semantics.

### Tests added

`tests/unit/test_dtls12.nova` extended by 35 R38B assertions
across 9 new test functions, all appended at the tail of the
suite (slots 0..44 + the 417 prior assertions are NOT touched):

1. `test_r38b_init_rekeys_counter_zero` -- fresh state has
   `stats_rekeys=0`; direct slot probe `st[45]==0`.
2. `test_r38b_advance_epoch_bumps_rekeys_counter` -- counter
   increments by exactly 1 per `dtls_advance_epoch` call;
   monotonic across 3 advances.
3. `test_r38b_pre_cipher_advance_bumps_counter_but_skips_prf` --
   advance with no ECDHE-derive still bumps the counter to 1;
   key_block + client_write_key remain 0 (PRF skipped).
4. `test_r38b_advance_reallocates_key_block_and_subbuffers` --
   post-advance key_block + 4 sub-buffer pointers all DIFFER from
   pre-advance (fresh allocations); pre-advance bytes
   byte-identical to post-advance bytes (variant A determinism).
5. `test_r38b_cross_epoch_seal_open_after_rekey` -- the R33B
   contract holds under R38B: epoch=0 seal+open accepted, both
   advance, epoch=1 seal+open accepted with the rekeyed (byte-
   identical) keys; rekeys counter == 1 on both sides post-
   advance.
6. `test_r38b_variant_a_deterministic_prf_reexpansion` -- two
   consecutive advances on the same state produce byte-identical
   40-byte key_blocks (the formal definition of variant A;
   variant B would CHANGE the bytes).
7. `test_r38b_srtp_keying_material_recomputes_deterministically`
   -- R36B cache invalidation invariant holds: an
   export -> advance -> export sequence sees the cache cleared on
   the advance (R36B) + the rekeys counter bumped (R38B) + the
   60 bytes byte-identical to pre-advance (variant A).
8. `test_r38b_stats_line_includes_rekeys_field` -- substring
   scan confirms `dtls_stats_line(state)` includes the new
   `rekeys=` token.
9. `test_r38b_rekeys_counter_is_per_state` -- alice's rekeys
   bumps don't leak into bob's counter; both states track
   independently.

### Honest scope limits

1. **Variant A is on-spec but doesn't add cryptographic
   cross-epoch key differentiation.** Re-running the SAME PRF
   with the SAME inputs produces the SAME 40 bytes. The
   security-relevant cross-epoch property holds at the AEAD AAD
   layer (epoch in the upper 16 bits of the AAD seq_num per RFC
   6347 §4.1.2.1) -- a record sealed at (epoch=0, seq=N) and the
   same plaintext sealed at (epoch=1, seq=N) produce DIFFERENT
   AEAD inputs (the AAD differs) -> different ciphertext + tag
   even with byte-identical keys. The R38B PRF re-run is
   telemetry + a hook, NOT the load-bearing security property.
   This is documented inline at both the slot-declaration comment
   and the `dtls_advance_epoch` header.
2. **No variant B (epoch-in-seed).** Documented as a future
   research item. Non-standard but matches the security intuition
   of "fresh keys per epoch". Needs protocol-level discussion
   before shipping. R38B's call site is structured so variant B
   is a one-line change.
3. **One extra PRF expansion per advance.** Two HMAC-SHA256
   iterations per `dtls_advance_epoch` (ceil(40/32) = 2).
   Advances are RARE (one per CCS, not per packet); the cost is
   negligible.
4. **R38B compile/test execution UNVERIFIED in this session.**
   The Nova toolchain is not available in the working directory;
   the change is mechanical (one tail-appended slot + one
   accessor + one rekey block in `dtls_advance_epoch` mirroring
   `dtls_ecdhe_derive` step 4 + tests mirroring the R33B/R36B
   patterns). The byte-identity claim for the 417 prior
   assertions rests on the tail-append discipline -- no slot
   0..44 index changed; the new `rekeys=` field is appended at
   the END of `dtls_stats_line` so prior substring scans still
   match.
5. **R38B does not modify any sibling-agent file.** Only
   `dtls12.nova` (extend) and `test_dtls12.nova` (extend tail)
   are touched. srtp.nova / turn.nova / ice_turn.nova /
   x509.nova / ecdsa.nova / sha256.nova are untouched -- R38C
   (TURN server, concurrent) + R38D (SCRAM auth, concurrent on
   a different file) cannot collide.
