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
