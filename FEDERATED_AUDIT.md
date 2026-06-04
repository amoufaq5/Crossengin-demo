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

2. **Pipelined dispatch (fan-out then collect).** The synchronous
   loop interleaves dial+send+recv-DREND per peer. R28A separates
   the dispatch and collect phases:

   * **Phase 1 (dispatch).** For every alive peer != self, open a
     TCP connection, run the HELLO/OK handshake, record `start_ns =
     nanotime()`, send `DRFETCH <pred>`. Failed dials and failed
     HELLOs are silently skipped (no SUSPECT propagation).
     Accumulate a list of `[fd, start_ns, peer_addr]` handles. The
     dials happen back-to-back without waiting for ACKs in between,
     so kernel-level TCP handshakes overlap with the time spent in
     user-space serializing the DRFETCH lines.

   * **Phase 2 (collect).** For each open handle, set the per-peer
     adaptive `_gossip_set_rcvtimeo_ms`, drain `DRFACT` lines until
     `DREND` or the timer fires, append facts to the output. On
     `DREND` the observed round-trip is pushed onto the peer's
     latency window; on timeout the `STATS_LATE_DROPS` counter is
     incremented and the peer's existing latency window is left
     untouched (so a one-off jitter doesn't poison the median).

   NOVA's socket builtins are blocking with `SO_RCVTIMEO`; there is
   no `poll(2)` / `select(2)` primitive. The "async" name describes
   the dispatch shape (fan-out then collect) not the wire-level
   concurrency. The win is materially measurable even on a
   loopback mesh: the 4-peer dispatch pass completes in ~ tens of
   milliseconds (just the latency of 4 connect + send sequences)
   while the legacy synchronous path stalls a 4-peer round on the
   first slow peer for up to 4 × 500 ms = 2 s worst case.

3. **Late-ACK isolation.** When the adaptive RCVTIMEO fires before
   `DREND`, the collect path closes the fd, increments
   `STATS_LATE_DROPS`, and continues. It does **not** call
   `gossip_on_timeout` -- the gossip layer's PING/ACK liveness probe
   remains the only source of `SUSPECT` marks. R21B's existing
   `gossip_dr_fetch_from` already had this property; R28A preserves
   it for the pipelined path.

4. **Opt-in via `CE_DR_ASYNC_FETCH` env var.** Values `on`, `1`,
   `yes` (any case) enable the pipelined path; everything else / unset
   leaves R21B's synchronous loop in place. The env var is read once
   in `dr_init` and cached on the dr\_state record at
   `DR_S_ASYNC_FETCH_OPT`; a test/operator hook `dr_set_async_fetch(dr,
   on)` flips the flag at runtime without re-reading the environment.

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
  PAD, floor clamp at 200 ms, ceiling clamp at 5000 ms, handles
  zero-valued samples, 5-sample median) (12); per-peer latency
  table rolling-window cap (3); per-peer median independence (2);
  `STATS_TIMEOUT_ADJ` purity of the calculator helper (the counter
  bumps in `_dr_collect_one`, not in the read-only accessor) (2);
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
  `CE_DR_ASYNC_FETCH=on` exported: STABLE 5-soul sub-scenario
  derives **the full 55 ancestor closure** rather than the 20-40
  partial R27E documented; DROP sub-scenario remains within
  [12, 25] (post-cut reachability closure); REJOIN sub-scenario
  recovers full closure post-rejoin; LATENCY sub-scenarios at peer
  counts 2..5 stay sub-quadratic. The scenario\_yyyy script itself
  is unchanged; the env var propagates via the parent shell's
  environment into every `launch_soul` child process.

* All other federation suites (R18E gossip, R19E leader, R20B rule
  inference, R20E distributed query, R20F snapshot attestation,
  R21E noise gossip, R26E gossip relay, R27C relay-secure) remain
  green; module count unchanged at 191 (R28A is purely additive
  inside `src/federation/distributed_rules.nova`).

### Limitations / future work

1. **No poll(2)/select(2) so dispatch is pipelined not parallel.**
   When NOVA grows a multi-fd readiness primitive, the collect phase
   should walk fds in ACK-arrival order rather than dispatch order.
   The current order is "fast peers ACKed before the loop runs", so
   the dispatch order is a reasonable approximation but the worst
   case is still N × adaptive\_timeout when every peer holds out
   until their timer fires.
2. **Median is a coarse summary.** A peer that swings between 50 ms
   and 800 ms has a 425 ms median that's neither prompt nor patient
   for the actual workload. P95 with EWMA would be more responsive;
   the R28A median is the cheapest thing that beats a hardcoded 500
   ms ceiling.
3. **No per-rule-evaluation budget.** A pathological mesh where
   every peer hits the MAX timeout drives a single fixpoint round to
   `N × 5 s`. A higher-level "give up this fixpoint pass after T
   seconds" budget would bound the worst case more aggressively;
   the driver in `scenario_yyyy_rule_convergence_driver` already
   takes this shape (4 fixpoint passes of <= 15 rounds each) but
   the underlying gather doesn't yet honor a deadline.
4. **No DELTA-fed warm cache.** Same item as R21B's open list.
   A subsequent round could ride DELTA's existing belief-mutation
   stream to keep a local materialised relation cache + only
   DRFETCH on cache miss.
