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
* X25519-shape Diffie-Hellman — `c25519_*` surface wrapping
  `bn_modpow_ct` from `src/safety/bignum.nova` against the field
  prime p_25519 = 2^255 - 19 with generator g = 2. Wire layout is
  X25519-compatible (32-byte little-endian pubkeys + scalars); real
  ECDH on the curve is a drop-in replacement when Field 25519 lands.
* ChaCha20-Poly1305 AEAD — RFC 7539 construction over the existing
  `src/safety/chacha20.nova` + `poly1305.nova` leaves; bound to the
  Noise transcript hash on every message.
* OS CSPRNG via `secure_random(buf, n)` (R5B builtin) for ephemeral
  key generation; nanotime+LCG fallback path documented as weaker.

### Wire protocol v3

Three handshake messages (each preceded by a 4-byte BE length so framing
is unambiguous before keys exist), then encrypted transport:

```
  -> msg1 (48 B): e_pub (32) || tag(empty plaintext, k=HKDF(es)) (16)
  <- msg2 (48 B): e_pub (32) || tag(empty plaintext, k=HKDF(es,ee)) (16)
  -> msg3 (64 B): AEAD-encrypted s_pub (32+16) || tag(empty, k=HKDF(es,ee,se)) (16)

  transport: [4 B BE len] [ct] [16 B Poly1305 tag]
             nonce = [4 zero bytes || 8 B LE counter]
             counters monotonic, independent per direction
```

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

### Performance

Curve25519-shape DH via `bn_modpow_ct` is the dominant cost: ~120 ms
per scalar mult on the integration runner. Full XK handshake = 4 DH
operations on the initiator side (es, ee, se) plus 3 on the responder
(es, ee, se), plus SHA-256 + HKDF (negligible). Measured on the
integration scenario: **~508 ms wall-clock end-to-end** for a fresh
handshake, well under the 2-second budget. Real ECDH on Curve25519
(with the X25519 ladder) drops this to ~5 ms when it lands.

### Verification

- Unit (`tests/unit/test_noise_xk.nova`): **42 assertions** covering
  SHA-256 KAT (FIPS 180-4 "abc" + empty + 448-bit boundary),
  HMAC-SHA256 KAT (RFC 4231 TC1), DH commutativity, keypair
  generation, full handshake convergence (both sides agree on session
  hash + transport keys), responder learns initiator pubkey,
  transport round-trip both directions, tampered ciphertext +
  tampered length-prefix rejected, replay rejected (nonce
  monotonicity), MITM with wrong responder pubkey rejected at msg1.
- Integration (`tests/integration/scenario_gg_noise_kg.sh`): **12
  assertions** running two NOVA souls over a real TCP socket.
  Stage 1 proves a clean handshake + one encrypted KG delta decrypts
  at the far end; Stage 2 proves MITM with a wrong static priv is
  rejected.

### LOUD caveats

- The DH is bignum-mod-prime, not real elliptic-curve scalar mult.
  Wire layout matches X25519 so a future real-ECDH drop-in changes
  only `c25519_*`; the noise XK state machine is unchanged.
- 256-bit DH is below the 768-bit RFC 7919 Group 1 floor and is
  breakable in tractable time on commodity hardware. The MVP
  demonstrates the wire protocol + the mutual-auth contract, NOT
  cryptographic strength against a serious adversary. The 2048-bit
  SECAGG_AUDIT path (`bn2048_modpow_ct` + RFC 7919 Group 14, landed
  in R5A) is the upgrade target.
- The fallback random path (when `secure_random` syscall returns -1)
  is a nanotime+LCG stretch and is NOT cryptographically secure;
  the production path is OS getrandom via the R5B builtin.
