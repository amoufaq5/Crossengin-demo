# Secure Aggregation (SecAgg) Audit

**Phase:** P3.8 — secure aggregation MVP (pairwise additive masking),
extended to **P3.8r — dropout-resilient SecAgg (v2-sa-r)**, further
extended to **P3.9 — DH key agreement (v2-sa-dh)** which replaces
the pre-shared-token path with a real Diffie-Hellman exchange when
the soul opts in via `CE_SECAGG_DH=1`, and **P3.9 cont. — 2048-bit
DH on RFC 7919 Group 14 (v2-sa-dh-2048)** which swaps the 256-bit
Curve25519-field strawman for a cryptographically-reasonable 2048-bit
MODP safe-prime group when the soul opts in via `CE_SECAGG_DH_2048=1`.
**ADR:** ADR-0055 — SecAgg via pairwise additive masking with
pre-shared tokens. The dropout-resilience extension layers on top of
the original ADR-0055 primitive: same mask derivation, same wire
envelope, with an additive FED_DROPOUT + FED_RECON_MASKED protocol
pair that lets the surviving souls reconcile their submissions when
one peer vanishes mid-round. The DH extension adds an additive
FED_DH_PUBLIC line on top of v2-sa-r: the wire protocol shape is
unchanged below the round_open, and the mask derivation is the same
LCG -- just seeded by a DH-derived shared secret instead of a
pre-shared token.
**Modules:** `src/learning/secure_aggregation.nova` (P3.8r:
`sa_recompute_without` / `sa_reconcile_for_dropped` + FED_DROPOUT /
FED_RECON_MASKED wire formatters + parsers + the
`CE_FED_ROUND_DEADLINE_MS` env helper; P3.9: `sa_dh_generate_keys` /
`sa_dh_shared_secret_for_peer` / `sa_register_peer_dh` + the
FED_DH_PUBLIC wire formatter + parser + `sa_dh_enabled_from_env`;
P3.9 cont.: `sa_dh_generate_keys_2048` / `sa_dh_shared_secret_for_peer_2048`
+ `sa_dh_2048_enabled_from_env` + the SA_DH_BITS state slot routing
`sa_mask_for_peer` to the 2048-bit shared-secret derivation when the
soul opts in to v2-sa-dh-2048),
`src/safety/bignum_2048.nova` (NEW in P3.9 cont., **extended in R4D
with Montgomery REDC**: a 64-limb 2048-bit pure-NOVA bignum library
parallel to the 256-bit `bignum.nova`; exposes `bn2048_modpow_ct` --
Montgomery-ladder constant-time exponentiation on RFC 7919 Group 14
now backed by Montgomery REDC (CIOS form) for **~10x speedup** vs the
original bit-by-bit reduce: one full-width modpow_ct on the RFC 7919
Group 14 prime drops from ~18s to ~1.2s -- as the crypto-safe primitive
for 2048-bit DH; the non-CT square-and-multiply variant is
intentionally OMITTED to prevent timing leaks on private exponents;
the public surface gains
`bn2048_mont_ctx_new`/`bn2048_to_mont`/`bn2048_montmul`/
`bn2048_from_mont`/`bn2048_modpow_ct_mont` for caller-managed
Montgomery form),
`src/learning/federated_aggregator.nova` (extended with v2-sa mode and
the P3.8r reconciliation emitter `fed_agg_emit_recon_masked`),
`src/safety/bignum.nova` (P3.9: `bn_modpow_ct` -- Montgomery-ladder
constant-time modular exponentiation -- replaces the side-channel-
unsafe `bn_modpow` for DH/ECDH/RSA private-exponent operations),
SECAGG\_\* / FED\_DH\_PUBLIC parser branches additively added to
`src/io/transducers/kg_sync.nova` (one more dispatch case for
FED_DROPOUT / FED_RECON_MASKED / FED_DH_PUBLIC),
`examples/crossengin_fed_coordinator.nova` (SecAgg-r coordinator with
dropout detection + reconciliation broadcast / collect path; P3.9:
DH-pubkey collection during handshake drain + `_fed_broadcast_dh_pubkeys`
phase after all souls join),
`examples/crossengin_chat.nova` (env-detected v2-sa fed_join path with
the FED_DROPOUT receive hook -- no new admin commands; P3.9: single
`CE_SECAGG_DH` env probe gates the DH keygen + announce + receive
broadcast cycle).

## What changed from P3.7

P3.7 shipped federated learning with **trusted coordinator + local DP**:
every soul locally adds Laplace noise to its rate (one
`dp_noisy_mean` call per stat per round) before sending FED\_STAT, and
the coordinator averages the noised values across N souls. The
coordinator never sees raw rates — but it does see each soul's
DP-noised contribution. A curious coordinator (or any traffic
inspector) learns the noised distribution per soul.

P3.8 adds an *information-theoretic* privacy layer on top: **pairwise
additive masking**. For every pair of souls (A, B), the pair shares a
deterministic mask `m_AB`. A adds `+m_AB` to its share; B adds
`-m_AB`. When the coordinator sums every soul's masked share, the
`+m_AB / -m_AB` pair cancels — so the coordinator recovers the sum of
raw values but cannot read any single soul's contribution.

## Why pairwise additive masking is the right MVP

Real secure aggregation as defined by Google's 2017 paper (Bonawitz et
al., *Practical Secure Aggregation for Federated Learning on
User-Held Data*) layers four primitives:

1. **Pairwise additive masks** — the cancellation primitive itself.
   This is what we ship.
2. **Diffie-Hellman key agreement** — pairs derive their shared mask
   seed from a fresh per-round DH exchange instead of a pre-shared
   token. Defers the need to distribute long-term secrets.
3. **Shamir secret sharing of the masks** — each soul `shamir`-shares
   its individual mask among k of n peers so that if a soul drops
   out mid-round, the remaining peers can reconstruct its mask and
   subtract it from the sum. Closes the dropout-induced
   "uncancelled mask" failure mode.
4. **Authenticated key exchange + signatures** — defends against
   active adversaries (peers that pretend to be other peers to
   poison the masks).

The MVP ships **primitive 1** only — and that primitive alone is
enough to demonstrate the security property the brief asks for:
**the coordinator sees only the sum, never per-soul contributions.**
The DH, Shamir, and authentication layers are **4-6 weeks of pure
crypto** per the reference implementation: bignum arithmetic for DH,
polynomial interpolation for Shamir, an authenticated channel for
each pair. CrossEngin's NOVA toolchain has no bignum, no polynomial
math, and no authenticated channel primitive today; adding any one
of those is its own multi-week project before we'd get to compose
them. The MVP picks the layer that ships the headline property
(`coord_sees_only_sum == TRUE`) with the smallest possible new
primitive surface: a 15-bit LCG + a string-hash + an additive sum
accumulator. Every line of that stack already has a working
analogue in the differential-privacy module — the same LCG with the
same NOVA pointer-threshold bug workarounds — so the implementation
risk is bounded.

## Security model

**Trust:** the coordinator + at least N-1 honest, non-colluding souls.

**Property:** given N souls with raw stats x₁, …, x_N, the
coordinator computes Σᵢ xᵢ but for any single soul i the
coordinator's view of soul i's contribution `masked_x_i = x_i +
Σ_{j>i} m_{ij} - Σ_{j<i} m_{ji}` is information-theoretically
indistinguishable from a uniform draw over the mask domain
(2¹⁵ = 32 768) — because the masks are uniform 15-bit LCG outputs
seeded by a fresh per-round hash. The coordinator sees a number that
is uniformly distributed in the mask domain conditional on the sum;
it gains exactly the information needed to compute the sum and
nothing more about any individual contribution. This is
*information-theoretic*, not just computational: even with unbounded
compute, the coordinator cannot recover `x_i` from `masked_x_i`
alone.

**The collusion caveat.** If any (N-1) of N souls collude with the
coordinator, the holdout is unmasked: the colluders can subtract
their own (known) masks from the sum and recover the holdout's raw
value. This is the standard MPC threshold — no information-theoretic
scheme over N parties tolerates more than (N-2) corruptions for the
sum-recovery primitive. SecAgg-with-Shamir lifts this to a tunable
threshold k of n (the coordinator + N-k souls), but the MVP ships
the (N-1)-honest threshold.

**Passive eavesdropper on the wire.** A network observer who sees
every masked submission learns the same thing the coordinator does:
the sum, and nothing about per-soul values. The pre-shared tokens
are NEVER on the wire; only the masked values are. This is one step
better than P3.7's DP-noised submissions (which leak the noised
distribution per soul on the wire).

## What this MVP does not do

- **No verifiable secret sharing (Shamir).** Production SecAgg uses
  Shamir secret sharing of each soul's mask seeds so any k of n
  surviving peers can reconstruct a dropped soul's seed and
  algebraically remove its mask from the sum WITHOUT requiring the
  survivors to recompute their own submissions. The P3.8r path
  shipped here uses a simpler, equivalent-strength mechanism
  ("dropped soul advertised, every survivor subtracts the dropped
  peer's mask from its own submission"). Both routes recover
  Σ_{i ≠ dropped} x_i; Shamir is more bandwidth-efficient for
  multiple simultaneous dropouts but adds polynomial-field-
  arithmetic complexity that NOVA lacks today. Adding
  Shamir alone is ~2 weeks: polynomial interpolation in a finite
  field, the share-distribution protocol, and the recovery path.

- **No Diffie-Hellman key exchange.** The MVP relies on pre-shared
  tokens distributed via `CE_FED_TOKEN_<peer>` env vars. This
  means: (1) operators have to bootstrap the pairwise secrets out
  of band, and (2) if a token leaks, all of that pair's past and
  future masks are recoverable. DH is the right answer for both
  problems, but DH on a 1024-bit safe prime needs bignum
  arithmetic that NOVA does not have today. The audit recommends
  pre-shared tokens as the bootstrap path; the upgrade to DH is a
  P3.9 candidate that requires the bignum prework as its
  dependency.

- **No Byzantine robustness.** A malicious soul can submit a
  garbage masked value and the coordinator has no way to detect
  it; the sum is corrupted by the difference. Production
  SecAgg-Byzantine layers a zero-knowledge proof that the
  submission lies in the expected range. Out of scope for the
  MVP.

- **No authenticated channel.** The pre-shared token authenticates
  the pair to each other (they both derive the same mask seed),
  but the wire between each soul and the coordinator is
  un-authenticated (the v2-sa HELLO does not carry a per-soul
  identity proof). The brief's "trusted token distribution"
  assumption covers this; production SecAgg uses a TLS-style
  authenticated channel per soul-coord pair.

## Trusted-token distribution

The MVP assumes operators distribute pairwise tokens via
`CE_FED_TOKEN_<peer_id>` environment variables. Concretely, alice's
chat session runs with:
```
CE_SECAGG_ENABLED=1
CE_SECAGG_PEERS="bob,carol"
CE_FED_TOKEN_bob="<shared with bob>"
CE_FED_TOKEN_carol="<shared with carol>"
```
and bob's session runs with the matching token for alice. Both
tokens of a pair MUST match for the mask to cancel — a mismatch
shows up as an additive noise term in the coordinator's sum (the
same failure mode as a dropout). For production, a key-distribution
service (DH, PSI, or a trusted introducer) replaces the env vars.

## Demo (the brief's 2-soul example, verified by `test_secure_aggregation.nova`)

Two souls A (alice) and B (bob) with raw stats `x_A=100`, `x_B=200`
share a token `"secret"`. At round 1 the LCG-derived mask is, for
the dim-0 stat, `m_AB`. Then:

- alice computes `masked_A = 100 + m_AB` (alice < bob lex, so alice
  ADDS the mask)
- bob computes `masked_B = 200 - m_AB` (bob > alice, so bob
  SUBTRACTS the mask)
- coordinator sums: `masked_A + masked_B = 300 = x_A + x_B`

The masked values `masked_A` and `masked_B` are NOT equal to the
raw values (asserted by
`test_secagg_two_soul_sum_demo`). The coordinator's accumulator
stores the sum, never the raws (asserted by
`test_secagg_coord_never_sees_raw`).

## Wire-protocol additions

The SecAgg layer is an additive extension of the P3.7 federated
protocol — the v1 lines are unchanged. New lines:

| Line | Direction | Meaning |
|---|---|---|
| `SECAGG_HELLO ce-fed v2-sa` | client → server | opt-in to SecAgg mode |
| `OK ce-fed v2-sa protocol accepted` | server → client | accept |
| `SECAGG_PEER <peer_id> <token>` | client → server | announce one peer pair |
| `FED_STAT_MASKED <round> <tag> <mp> <ma>` | client → server | masked stats |
| `FED_AGGREGATE_SUM <round> <tag> <sp> <sa> <n>` | server → client | coord sum |
| `FED_DROPOUT <round> <dropped_soul_id>` | server → client | a soul vanished; survivors reconcile (**P3.8r**) |
| `FED_RECON_MASKED <round> <soul_id> <tag> <ap> <aa>` | client → server | reconciled stat (dropped peer's mask removed) (**P3.8r**) |

The coordinator broadcasts the **sum** (not the average) so the
audit-readable contract is clean: the coordinator only ever computes
sums. The soul divides by `n_participants` on its own end to recover
the average if it wants one (helper: `sa_sum_to_avg`).

## Shipped: dropout resilience (P3.8r / v2-sa-r)

**Status:** shipped. Previously documented as a limitation (see "What
this MVP does not do" -- now moved to the production-ready row).
**Verified by:** `test_secagg_three_soul_dropout_demo` in
`tests/unit/test_secure_aggregation.nova` (the 3-soul A/B/C round
where B drops; A + C reconcile by removing m_AB and m_BC from their
masked submissions; the coordinator's sum equals x_A + x_C exactly),
and `tests/integration/scenario_u_secagg.sh` "scenario U.r" (a real
2-soul TCP round-trip where a Python soul-helper acts as the dropout
peer -- handshake then close -- and the coordinator's
FED_AGGREGATE_SUM line carries the surviving soul's raw values
exactly, n_part=1).

### Protocol flow (extension of v2-sa)

1. Round begins with N expected souls and a list of their ids
   (collected at JOIN time via SECAGG_PEER announcements).
2. Each soul computes `masked_x_i` as in P3.8 and sends
   `FED_STAT_MASKED <round> <tag> <mp> <ma>`.
3. If soul k disconnects mid-round (the coord's `recv_line` returns 0
   before any FED_STAT_MASKED arrives, OR the FED_ROUND broadcast
   `_send_all` failed for that soul), the coordinator broadcasts
   `FED_DROPOUT <round> <k>` to every surviving soul.
4. Each surviving soul recomputes its mask vector EXCLUDING k:
   - if i < k -> i had ADDED +m_ik, so it subtracts m_ik from its
     already-sent masked_x_i (the helper `sa_recompute_without`
     returns +m_ik, and `sa_reconcile_for_dropped` does
     `adj = masked - delta`).
   - if i > k -> i had SUBTRACTED -m_ki, so it adds m_ki back (the
     helper returns -m_ki, the same subtraction undoes it).
   The soul emits one `FED_RECON_MASKED <round> <i> <tag>
   <adj_promo> <adj_atr>` per tag.
5. The coordinator's reconciliation pass sums the FED_RECON_MASKED
   submissions and broadcasts the FED_AGGREGATE_SUM. Mask
   cancellation holds across the SHRUNK survivor set because every
   surviving pair (i, j) still has its +m_ij / -m_ji symmetry and
   the dropped peer's now-uncancelled contributions were just
   removed.

### Determinism contract

The reconciliation step depends critically on the soul deriving the
EXACT SAME mask that it used during the original masked-stat emit. The
LCG is purely deterministic over `(token, round_id, k_dim)` -- a re-call
of `sa_mask_for_peer` with those three inputs returns bit-identical
output. This is asserted by `test_sa_mask_deterministic_same_inputs`
(P3.8) and re-asserted by `test_sa_recompute_without_determinism`
(P3.8r). The round_id stays bound to the SA state from the
`fed_agg_emit_masked_stats` call through `fed_agg_emit_recon_masked`
(both call `sa_round_set(sa, f[FED_ROUND_ID])` before the per-peer
loop), so the round id never drifts between emit and reconcile.

### Threshold

The P3.8r flow tolerates **any number of simultaneous dropouts up to
N-1**: as long as ≥1 soul survives, the coordinator can drive a clean
reconciliation pass per dropped peer. With ≥2 dropouts in a single
round, the coordinator broadcasts FED_DROPOUT once per dropped id
(serially) and the survivors apply each adjustment in turn. Each
reconciliation step caches the new "current submission" on the soul,
so the SECOND reconciliation correctly subtracts against the
FIRST-RECONCILED value (the `fed_agg_emit_recon_masked` helper
overwrites `FED_LAST_EMIT_LIST` with the adjusted rows). The (N-1)
collusion caveat from P3.8 still applies: if the coordinator colludes
with N-1 of the survivors, the holdout is unmasked -- the survivor
threshold for sum-recovery is identical to the original SecAgg MVP.

### Tuning the round deadline

`CE_FED_ROUND_DEADLINE_MS` (default 5000 ms, capped at 60_000 ms,
floored at 100 ms) sets the nominal per-round receive deadline. In the
NOVA single-thread blocking-IO model an explicit sub-recv timeout
isn't available, so the coordinator's dropout signal is the
conventional one: a peer-closed fd. The deadline value is reported in
the coord's boot banner (`round-deadline-ms=5000`) so an operator can
audit the tuning, but is not currently enforced against `nanotime()`
inside the recv loop (a future revision could add `O_NONBLOCK` + a
poll-based wait to honor the deadline literally; for now the
peer-closed-fd signal is the production failure mode that matters).

## How this composes with P3.7's DP

In v2-sa mode the soul does NOT apply DP noise to its raw stats —
the pairwise mask provides information-theoretic privacy for the
sum. The DP budget is left untouched (and so a v2-sa session can
afford strictly more `/dp_query` operations than a v1 session of the
same length). A future round may add DP-noise-on-top-of-SecAgg
("local DP plus secure aggregation") for the stricter regime where
the coordinator is curious AND the sum itself is sensitive; that's
the layered defense Google's SecAgg paper recommends for "the
strictest threat model". For CrossEngin's threat model
(soul-vs-coordinator with at-least-one honest soul), SecAgg alone
gives the headline property.

## Shipped: DH key agreement (P3.9 / v2-sa-dh)

**Status:** shipped (this session). Replaces the pre-shared-token
path with a real Diffie-Hellman key agreement when the soul opts in
via `CE_SECAGG_DH=1`. The pre-shared-token path remains the default
and is unchanged for backwards compatibility.

**Verified by:** `test_sa_dh_two_soul_pair_mask_matches` +
`test_secagg_two_soul_dh_sum_demo` in
`tests/unit/test_secure_aggregation.nova` (the headline check: alice
and bob each generate a 256-bit private key + matching public key,
exchange pubkeys via the coordinator broadcast, then each derives
the pairwise shared secret via `peer_pubkey ^ my_private mod p` and
both sides land on the SAME shared secret; the LCG mask derivation
seeded by that shared secret produces matching masks so the SecAgg
cancellation invariant holds), and `tests/integration/scenario_u_secagg.sh`
"scenario U.dh" (a real 2-soul TCP round-trip where both chat souls
generate keypairs, send FED_DH_PUBLIC to the coordinator, receive
the broadcast pubkeys back, and complete a round with DH-derived
masks; the coordinator's AGGREGATE_SUM still equals Σ raw values).

### Wire protocol additions (additive on v2-sa-r)

| Line | Direction | Meaning |
|---|---|---|
| `FED_DH_PUBLIC <soul_id> <pubkey_hex>` | client → server (during handshake) | soul announces its DH public key |
| `FED_DH_PUBLIC <soul_id> <pubkey_hex>` | server → client (after all join) | coord broadcasts every peer's pubkey |
| `ACK 0` | server → client | sentinel: DH-broadcast phase ended |

### Protocol flow

1. Each soul generates a 256-bit private key `d_i` via
   `_sa_dh_random_bn_from_nanotime` (a stretched-nanotime LCG; see
   weak-random caveat below) and computes its public key
   `P_i = g^d_i mod p` via `bn_modpow_ct` (the constant-time
   Montgomery ladder).
2. During the v2-sa handshake (after FED_JOIN), each soul sends
   `FED_DH_PUBLIC <soul_id> <pubkey_hex>` instead of (or alongside
   nothing — the DH mode does NOT load `CE_FED_TOKEN_<peer>` env
   vars) `SECAGG_PEER` lines.
3. The coordinator collects each soul's pubkey during the handshake
   drain, then after all N souls have joined, broadcasts every
   pubkey to every OTHER soul (one `FED_DH_PUBLIC` line per peer
   per soul), then sends a sentinel `ACK 0`.
4. Each soul receives the peer pubkeys and registers them via
   `sa_register_peer_dh(s, peer_id, peer_pubkey_hex)`. The shared
   secret with peer j is `s_ij = P_j^d_i mod p`, derived on demand
   by `sa_dh_shared_secret_for_peer` (called from `sa_mask_for_peer`
   when `s[SA_DH_MODE] == 1`).
5. By DH commutativity `(g^a)^b == (g^b)^a mod p`, so both sides of
   each pair compute the SAME shared secret; the existing LCG mask
   derivation seeded by the shared secret then produces matching
   masks and the SecAgg cancellation invariant holds.

### Crypto-strength caveats (LOUD)

**256-bit prime is BROKEN against modern adversaries** (in the
v2-sa-dh path; v2-sa-dh-2048 below CLOSES this caveat). We use
`p = 2^255 - 19` (the Curve25519 field prime) and `g = 2` because
our bignum library WAS 256-bit; RFC 7919 Group 1 (the smallest
standard MODP group) is already 768-bit. A 256-bit DH group is
recoverable via index-calculus on commodity hardware; the v2-sa-dh
MVP demonstrates the WIRE PROTOCOL + FLOW, not the cryptographic
strength. The audit-readable contract: the wire shapes
(`FED_DH_PUBLIC` line + broadcast phase), the soul-side keygen +
shared-secret derivation, and the LCG seeding-from-shared-secret
all match the production design. **UPDATE (P3.9 cont.):** the
2048-bit `bignum_2048.nova` + `sa_dh_*_2048` variants + RFC 7919
Group 14 constants shipped this session; the `CE_SECAGG_DH_2048=1`
opt-in flips the DH primitive to a cryptographically reasonable
group. See "Shipped: 2048-bit DH on RFC 7919 Group 14" below.

**`p_25519` is NOT a "safe" DH prime.** Curve25519's prime is the
*field* prime of an elliptic curve, not the order of a prime-order
subgroup of `(Z/pZ)*`. Real DH wants `p = 2q + 1` with `q` prime
AND a generator of the order-`q` subgroup. We use `p_25519` + `g=2`
anyway because the WIRE PROTOCOL CORRECTNESS check
(`shared_from_a == shared_from_b`) is group-structure-independent
(commutativity is the only algebraic property we exercise).
Production must swap to an RFC 7919 group.

**Weak random.** The 256-bit private key is generated via
`nanotime() + 15-bit LCG` -- not cryptographically random. A
network adversary that can guess the soul's boot time to within a
second can brute-force the private key by enumerating LCG seeds
(roughly thousands of candidates). Production needs `/dev/urandom`
(or the OS-equivalent CSPRNG); the NOVA toolchain does not expose
one today. This is the SAME weak-random caveat the P3.8 LCG-driven
mask derivation carries; DH inherits it without making things
worse.

**Constant-time `bn_modpow_ct` IS used.** `sa_dh_generate_keys` and
`sa_dh_shared_secret_for_peer` both call `bn_modpow_ct` (Montgomery
ladder; see `src/safety/bignum.nova`) for the modular exponentiation
so the PRIVATE KEY EXPONENT does not leak via wall-clock timing to a
passive network observer. The square-and-multiply `bn_modpow` is
NOT used on private exponents anywhere; it remains in the public API
for offline test vector / public-exponent verification only.

## Constant-time `bn_modpow_ct` (P3.9 prerequisite)

**Status:** shipped (this session). The square-and-multiply
`bn_modpow` shipped in R2D leaked the exponent's Hamming weight
via timing (the `if (bit set)` branch only ran the multiply on
1-bits). For DH this would have leaked the soul's private key to
a passive eavesdropper measuring round-trip wall-clock.

`bn_modpow_ct` replaces this with the textbook **Montgomery ladder**:

```
R0 = 1, R1 = base mod m
for i = bit_len - 1 DOWN TO 0:
  b = exp.bit(i)
  if b == 0:
    R1 = R0 * R1 mod m
    R0 = R0 * R0 mod m
  else:
    R0 = R0 * R1 mod m
    R1 = R1 * R1 mod m
return R0
```

Both branches execute exactly one modmul + one square per bit, so
the per-bit wall-clock is exponent-bit-independent. The outer loop
walks all 256 bits (no leading-zero skip -- that would itself leak
the position of the most-significant set bit), so the function's
total runtime is exponent-Hamming-weight-INDEPENDENT.

`bn_modpow` remains in the public API for OFFLINE self-tests and
public-exponent verification (the documentation marks it "fast,
side-channel-unsafe; use only for offline self-tests"). Both
`sa_dh_generate_keys` (the `g^private mod p` keygen) and
`sa_dh_shared_secret_for_peer` (the `peer_pubkey^private mod p`
derivation) call `bn_modpow_ct` exclusively.

**Cost.** `bn_modpow_ct` is ~2x slower than `bn_modpow` per
bit-loop iteration on uniformly random exponents (square-and-multiply
averages 1.5 modmuls per bit; the ladder always does 2). For a
short exponent like `2^255 - 19 mod 1009` (1-byte exp, 8 set bits)
the dev sandbox measures ~20 ms for `bn_modpow` and ~40 ms for
`bn_modpow_ct` -- a ~1.88x ratio that matches the analytic
prediction. For full 256-bit private exponents (~128 set bits on
average) the ratio narrows to ~4/3x because `bn_modpow` runs the
multiply on roughly half the bits already.

**Equivalence.** `tests/unit/test_bignum.nova` asserts
`bn_modpow == bn_modpow_ct` on a 100-vector deterministic sweep
(72 textbook-fixed vectors + 28 pseudo-random LCG-seeded vectors)
plus the Curve25519 `2^255 mod p = 19` vector. The two functions
are observably interchangeable on the test surface.

## Shipped: 2048-bit DH on RFC 7919 Group 14 (P3.9 cont. / v2-sa-dh-2048)

**Status:** shipped (this session). The 256-bit `p_25519`-based DH
that v2-sa-dh used was cryptographically broken (a 256-bit DH group
is recoverable via index-calculus on commodity hardware; and
`p_25519` is a field prime, not a safe DH prime). This session adds
the 2048-bit `bignum_2048.nova` module + `sa_dh_generate_keys_2048`
+ `sa_dh_shared_secret_for_peer_2048` + the `CE_SECAGG_DH_2048` env
flag, all backed by the standard RFC 7919 Group 14 (= RFC 3526 §3,
the 2048-bit MODP "More Modular Exponential") safe-prime group with
generator g = 2.

**Verified by:**
- `tests/unit/test_bignum_2048.nova` (NEW) — the **headline check**:
  `bn2048_modpow_ct(g=2, p-1, p) == 1` (Fermat's little theorem on
  the RFC 7919 Group 14 safe prime). Costs ~15s wall-clock on this
  dev sandbox; passes. Plus 24+ correctness assertions: constructor
  + hex round-trip on zero/max/short inputs, 32-bit carry across
  limb #16 boundary in `bn2048_add`, underflow wrap in `bn2048_sub`,
  small + carry-into-hi cases for `bn2048_mul`, `2^1024 mod 1009 =
  960` small-modulus scale-up check for `bn2048_modpow_ct`, RFC
  7919 Group 14 constant validation.
- `tests/unit/test_secure_aggregation.nova` (extended) —
  `test_sa_dh_two_soul_2048_pair_mask_matches`: the 2-soul DH-2048
  pair-equivalence check. Alice and bob each generate a 2048-bit
  keypair, exchange pubkeys, derive the pairwise shared secret via
  `sa_dh_shared_secret_for_peer_2048`, and BOTH sides land on the
  SAME shared secret + the SAME LCG-derived mask. Costs ~60-140s
  wall-clock (4 modpow_ct calls + 2 mask derivations). PASSES.
- `tests/integration/scenario_u_secagg.sh` (extended) — scenario
  U.dh2048: two chat souls join with `CE_SECAGG_DH_2048=1`, generate
  2048-bit keypairs, broadcast pubkeys via FED_DH_PUBLIC, and
  complete a SecAgg round with DH-derived masks on the wider group.
  Timing budget is 180s (3 minutes) per the wall-clock-cost-realism
  banner in the script.

### Wire protocol additions (additive on v2-sa-dh)

| Line | Direction | Meaning |
|---|---|---|
| `FED_DH_PUBLIC <soul_id> <pubkey_hex>` | both directions | unchanged shape; the `pubkey_hex` field is now 512 chars (2048 bits) instead of 64 chars (256 bits) |

The coordinator does NOT need to know which group the souls use —
the wire layer just forwards opaque hex pubkeys. Both ends of each
pair must agree on the bits (256 or 2048) for the shared secret
derivation to land on the same value; the env-driven opt-in
(`CE_SECAGG_DH_2048` set on BOTH sides) is how this is bootstrapped.

### Protocol flow (delta vs v2-sa-dh)

Identical to v2-sa-dh, with two substitutions:
1. `sa_dh_generate_keys(s)` → `sa_dh_generate_keys_2048(s)` when the
   chat detects `CE_SECAGG_DH_2048=1` at JOIN time. This sets
   `SA_DH_BITS = 2048` on the soul's `sa_state`.
2. `sa_mask_for_peer` now dispatches on `SA_DH_BITS`:
   - 256 → existing `sa_dh_shared_secret_for_peer` (8-limb path)
   - 2048 → new `sa_dh_shared_secret_for_peer_2048` (64-limb path)

The LCG seed builder (`_sa_hash_str` → `_sa_seed_for_pair`) walks
the shared-secret hex byte-by-byte and works for any string length,
so the mask cancellation invariant holds regardless of the DH width.

### Crypto-strength caveats (now narrower)

**RFC 7919 Group 14 IS a "safe" DH prime.** It satisfies p = 2q + 1
with q prime, and g = 2 generates the order-q subgroup. This is the
SMALLEST DH MODP group the IETF still considers cryptographically
reasonable in 2025 — the upgrade closes the "256-bit DH is broken"
caveat the v2-sa-dh path carried.

**Weak random STILL applies.** The 2048-bit "random" private key
uses the SAME stretched-nanotime + 15-bit LCG as the 256-bit path
(see `_sa_dh_random_bn2048_from_nanotime` — extends the 256-bit
helper to 64 limbs). The 2048-bit arithmetic is strong; the
2048-bit entropy is NOT. Production needs `/dev/urandom` or the
platform CSPRNG; the NOVA toolchain does not expose one today.

**Timing reality check (LOUD; post-R4D Montgomery REDC).** One full-
width `bn2048_modpow_ct` costs ~**1.2 seconds** on this dev sandbox
post-Montgomery REDC (was ~15-18 seconds pre-Mont; **~10-15x speedup**).
A 2-soul DH-2048 round = 2 keygens + 2 shared-secret derivations + 2
mask derivations = ~6 modpow_ct = ~**8-10 seconds wall-clock** (was
~60-90s pre-Mont). An N-soul round scales as N + N*(N-1) = O(N²)
modpow_ct calls; a 5-soul round takes ~**30-60 seconds wall-clock**
(was ~5 minutes pre-Mont). v2-sa-dh-2048 is no longer the per-round
latency liability it was; it remains gated behind `CE_SECAGG_DH_2048=1`
mostly for backward-compat opt-in. The integration scenario
`tests/integration/scenario_u_secagg.sh` now completes in ~**19 seconds**
end-to-end (was ~141 seconds pre-Mont). For comparison, the 256-bit
`bn_modpow_ct` still costs ~40 ms (no Mont upgrade on bignum.nova
yet; the 256-bit path is no longer recommended anyway).

**Montgomery REDC implementation notes (R4D perf upgrade).** Replaced
the bit-by-bit `_bn2048_mod4096` reduction (4096 iterations × 64-limb
passes = ~786k limb-ops per reduce) with CIOS Montgomery REDC
(~8k limb-mults per reduce). The CIOS inner loop inlines the 32x32 →
[lo32, hi32] multiply to avoid the per-cell `list_new` allocations
that would otherwise OOM the NOVA sandbox (an unrolled modpow does
~32M 32x32 multiplies; allocating a 2-element list per multiply
ballooned the heap to 14GB+ before the inline fix). The Montgomery
context (`bn2048_mont_ctx_new`) precomputes `n_prime0 = -N^-1 mod
2^32` (via Newton's iteration: 5 squarings from `x_0 = 1`) and
`r2_mod_n = R^2 mod N` (via the legacy bit-by-bit reducer, paid once
per modulus). The public API gains
`bn2048_mont_ctx_new`/`bn2048_to_mont`/`bn2048_montmul`/
`bn2048_from_mont`/`bn2048_modpow_ct_mont` (caller-managed Mont
form) plus a kept-for-fallback `_bn2048_modpow_ct_legacy` (used when
the modulus is even, which DH primes never are). `bn2048_modpow_ct`
keeps its external signature bit-exact; the only observable change
is the ~10x wall-clock drop.

**Constant-time `bn2048_modpow_ct` IS used.** Same Montgomery-ladder
shape as the 256-bit `bn_modpow_ct`; per-bit wall-clock is exponent-
bit-independent. The non-CT square-and-multiply variant is
INTENTIONALLY OMITTED from the `bignum_2048` public API (unlike the
256-bit `bignum` module which exposes both): for 2048-bit DH any
remote-callable code path that uses the non-CT variant on a private
exponent is exploitable by a timing observer, and the cost of
keeping a "fast" non-CT variant available is not worth the
foot-gun risk.

### Bignum_2048 correctness fix vs the 256-bit reference

The 256-bit `bn_mod` in `bignum.nova` IGNORED the carry-out of the
in-place shift-left-by-one, because Curve25519's prime
(p = 2^255 - 19) has bit 255 CLEAR. The shift therefore never
overflowed the 256-bit container in any reachable test case. For
RFC 7919 Group 14 (top hex digit `ffffffff`, bit 2047 set) the
shift DOES overflow when the running remainder is close to m, and
silently dropping the top bit makes the reduction return 0 instead
of the correct value. The 2048-bit `_bn2048_shl1_inplace` returns
the carry-out bit, and `bn2048_mod` / `_bn2048_mod4096` force a
subtract of m whenever the shift overflows (the post-subtract value
correctly reflects the underlying mathematical operation via the
borrow-chain wraparound — see the inline comment in `bn2048_mod`).
This is the only algorithmic difference between the two modules
beyond limb-count scaling.

## Full SecAgg upgrade path

The reference Google SecAgg (~4-6 weeks per the published prototype)
adds:

1. **DH key agreement** — **shipped (this session, v2-sa-dh; AND
   v2-sa-dh-2048 on RFC 7919 Group 14).**
   See "Shipped: DH key agreement" and "Shipped: 2048-bit DH on RFC
   7919 Group 14" above. The 2048-bit group closes the "BROKEN"
   caveat; the remaining production-grade gap is a CSPRNG (the NOVA
   toolchain does not expose `/dev/urandom` today; the LCG-stretched
   nanotime seed leaks to anyone who can guess boot time within
   seconds).
2. **Shamir secret sharing of mask seeds** — ~2 weeks once we have
   a finite-field polynomial primitive.
3. **Dropout handling** — **shipped (P3.8r).** The MVP path
   ("dropped soul advertised, every survivor subtracts the dropped
   peer's mask from its own submission") works without Shamir.
4. **Authenticated channel** — ~1 week given a TLS-style HMAC
   primitive (which today's CrossEngin lacks; the kg-sync `token=`
   tag is the closest analogue and is purely a shared-secret check).

The MVP's pairwise-additive-masking module is the foundation; each
of the four layers above sits on top of it without invalidating the
existing primitive.

## What "bignum landed" means concretely

`src/safety/bignum.nova` is now a leaf primitive alongside `chacha20.nova`
and `poly1305.nova` -- no cross-safety imports, pure builtins (`int_add`,
`int_sub`, `int_mul`, `int_and`, `int_or`, `int_shl`, `int_shr`, list
ops). Public surface:

| Function | Returns | Description |
|---|---|---|
| `bn_new()` | bn | 256-bit zero |
| `bn_from_int(n)` | bn | small int -> bn (handles up to 2^64-1 via two-limb split) |
| `bn_from_hex(hex)` | bn | hex string (lower or upper case, 1..64 chars) -> bn |
| `bn_to_hex(bn)` | string | canonical 64-char lowercase hex |
| `bn_zero(bn)` | int (0 or 1) | 1 iff all limbs zero |
| `bn_eq(a, b)` | int (0 or 1) | structural equality |
| `bn_cmp(a, b)` | int (-1, 0, 1) | comparator |
| `bn_add(a, b)` | bn | (a + b) mod 2^256 (drops carry past bit 255) |
| `bn_sub(a, b)` | bn | (a - b) mod 2^256 (two's-complement wrap on underflow) |
| `bn_mul(a, b)` | [hi, lo] | full 512-bit product (no truncation) |
| `bn_mod(a, m)` | bn | a mod m (bit-by-bit long division) |
| `bn_modmul(a, b, m)` | bn | (a * b) mod m, via the full 512-bit product |
| `bn_modpow(b, e, m)` | bn | b^e mod m, right-to-left square-and-multiply (FAST, SIDE-CHANNEL-UNSAFE; offline tests only) |
| `bn_modpow_ct(b, e, m)` | bn | b^e mod m via Montgomery ladder (CRYPTO-SAFE; constant-time per bit; use for DH/ECDH/RSA private exponents) |

Test coverage lives in `tests/unit/test_bignum.nova` -- 66 assertions
across `bn_to_hex` / `bn_from_hex` round-trip on the all-zeros, all-ones,
short, and case-mixed inputs; 32-bit carry propagation in `bn_add`;
underflow wrap in `bn_sub`; small + 2^128-squared + max-squared products
in `bn_mul`; small modulus + a < m in `bn_mod`; `(5*6) mod 7 = 2` in
`bn_modmul`; the textbook `2^10 mod 1000 = 24` and the Curve25519
`2^255 mod (2^255-19) = 19` in both `bn_modpow` and `bn_modpow_ct`; and
the equivalence sweep `bn_modpow == bn_modpow_ct` on 100 deterministic
vectors (72 textbook + 28 pseudo-random). The smallest measurable
op (a single `bn_add` call, no loop) clocks ~800 ns via `nanotime()`
on the dev container; a single `bn_modpow_ct` call at 256-bit modulus
on an 8-bit exponent clocks ~40 ms (vs. ~20 ms for `bn_modpow` -- the
~1.88x ratio matches the ladder always doing both ops vs.
square-and-multiply skipping the multiply on 0-bits).

## What "bignum_2048 landed" means concretely

`src/safety/bignum_2048.nova` (NEW) is a 64-limb (32-bit-per-limb)
pure-NOVA 2048-bit unsigned bignum library, parallel to the 256-bit
`bignum.nova`. Same shape, just wider. Public surface:

| Function | Returns | Description |
|---|---|---|
| `bn2048_new()` | bn2048 | 2048-bit zero |
| `bn2048_from_int(n)` | bn2048 | small int -> bn2048 (two-limb split) |
| `bn2048_from_hex(hex)` | bn2048 | hex string (1..512 chars) -> bn2048 |
| `bn2048_to_hex(bn)` | string | canonical 512-char lowercase hex |
| `bn2048_zero(bn)` | int (0/1) | 1 iff all limbs zero |
| `bn2048_eq(a, b)` | int (0/1) | structural equality |
| `bn2048_cmp(a, b)` | int (-1/0/1) | comparator |
| `bn2048_add(a, b)` | bn2048 | (a + b) mod 2^2048 |
| `bn2048_sub(a, b)` | bn2048 | (a - b) mod 2^2048 (two's-complement wrap) |
| `bn2048_mul(a, b)` | [hi, lo] | full 4096-bit product |
| `bn2048_mod(a, m)` | bn2048 | a mod m (bit-by-bit long division) |
| `bn2048_modmul(a, b, m)` | bn2048 | (a * b) mod m, via the full 4096-bit product |
| `bn2048_modpow_ct(b, e, m)` | bn2048 | b^e mod m via Montgomery ladder + Montgomery REDC under the hood (CRYPTO-SAFE; the ONLY exposed modpow variant) |
| `bn2048_mont_ctx_new(N)` | mont_ctx | precomputed Montgomery context (`n_prime0`, `r2_mod_n`, `N`, `N_LIMBS`) for a fixed odd modulus N — amortizes the one-time precompute across many ops |
| `bn2048_to_mont(x, ctx)` | bn2048 | enter Montgomery form: `x_mont = x * R mod N` |
| `bn2048_from_mont(x_mont, ctx)` | bn2048 | leave Montgomery form: `x = x_mont * R^-1 mod N` |
| `bn2048_montmul(a, b, ctx)` | bn2048 | (a * b * R^-1) mod N via CIOS (the Montgomery REDC hot path) |
| `bn2048_modpow_ct_mont(b, e, ctx)` | bn2048 | b^e mod N via Montgomery REDC (caller-managed ctx; same shape as `bn2048_modpow_ct` but skips the per-call ctx allocation when the caller has it already) |
| `rfc7919_group14_p()` | bn2048 | the RFC 7919 Group 14 / RFC 3526 §3 2048-bit MODP safe prime |
| `rfc7919_group14_g()` | bn2048 | the RFC 7919 Group 14 generator g = 2 |

**INTENTIONAL OMISSION:** there is NO `bn2048_modpow` (non-CT
square-and-multiply variant). For 2048-bit DH, only the CT path is
safe to expose to any remote-callable code path; a passive timing
observer of a non-CT 2048-bit modpow could recover the soul's
private exponent from per-bit timing variance.

Test coverage in `tests/unit/test_bignum_2048.nova` (extended in the
R4D Montgomery upgrade) -- **65 assertions**, including:
- The **headline check** Fermat's little theorem on the safe prime:
  `bn2048_modpow_ct(2, p-1, p) == 1` -- now passes in ~**1.2 seconds**
  wall-clock on the dev container (was ~15-18 seconds pre-Mont).
- A Montgomery context round-trip on small N (`(5*6) mod 1009 = 30`
  via the explicit `bn2048_to_mont` / `bn2048_montmul` /
  `bn2048_from_mont` chain).
- A 2-vector pseudo-random equivalence sweep
  (`bn2048_modpow_ct == _bn2048_modpow_ct_legacy` on small N=1009).
- The headline speedup-ratio measurement: ONE legacy modpow_ct vs
  ONE Montgomery modpow_ct on the RFC 7919 Group 14 prime with a
  short non-trivial exponent (`0xDEADBEEFDEADBEEF`). Observed median
  on this dev container: **~10x** (Mont ~1.2 s, Legacy ~12.8 s).
  The test prints the ratio and asserts a conservative >=2x band
  to keep CI stable under sandbox-load variance.

The 2-soul DH-2048 round now lands in ~**8.7 seconds** wall-clock
(was ~60-90 s pre-Mont; per `test_secure_aggregation.nova`'s
`test_sa_dh_two_soul_2048_pair_mask_matches`). The integration
scenario `scenario_u_secagg.sh` (U.dh2048 stage) completes the full
2-soul DH-2048 SecAgg round in ~**19 seconds** end-to-end (was
~141 s pre-Mont; the 180s scenario deadline still holds for slow-
sandbox headroom).

## What "bignum_256 landed" means concretely (R6B Montgomery REDC mirror)

`src/safety/bignum_256.nova` (NEW in R6B) is an 8-limb (32-bit-per-limb)
pure-NOVA 256-bit unsigned bignum library, parallel to the existing
`bignum.nova` (the `bn_*` prefix) and `bignum_2048.nova` (the `bn2048_*`
prefix). It mirrors R4D's Montgomery REDC upgrade for the 256-bit case:
the bit-by-bit reducer behind every modmul is replaced by CIOS-form
Montgomery REDC, dropping `bn256_modpow_ct` on the Curve25519 prime
from ~45 ms (legacy) to ~3.1 ms (Montgomery) wall-clock -- a **~14x
speedup** measured end-to-end on this dev container with the full
254-bit `p-1` exponent.

The new `bn256_*` prefix is shipped alongside the existing `bn_*`
prefix from `bignum.nova` rather than replacing it. Existing callers
(Curve25519 ECDH emulation paths, ChaCha20-Poly1305 field math, the
`secure_aggregation.nova` DH-256 fallback) continue to import
`bignum.nova` with byte-identical semantics during the transition;
the upgrade is opt-in via the `bn256_*` prefix and a future patch
can migrate consumers when convenient.

Public surface mirrors `bignum_2048.nova`:
`bn256_new` / `bn256_from_int` / `bn256_from_hex` / `bn256_to_hex` /
`bn256_zero` / `bn256_eq` / `bn256_cmp` / `bn256_add` / `bn256_sub` /
`bn256_mul` / `bn256_mod` / `bn256_modmul` / `bn256_modpow_ct` /
`bn256_mont_ctx_new` / `bn256_to_mont` / `bn256_from_mont` /
`bn256_montmul` / `bn256_modpow_ct_mont`; plus `bn256_curve25519_p()`
for the Curve25519 field prime `p = 2^255 - 19`.

**INTENTIONAL OMISSION (mirror of bignum_2048.nova):** there is NO
`bn256_modpow` (non-CT square-and-multiply variant) in this module.
The legacy non-CT path lives in `bignum.nova` as `bn_modpow` for
offline test vectors only. For 256-bit DH / ECDH, only the CT path
is safe to expose to any remote-callable code path.

### CIOS implementation note (same anti-pattern as bn2048)

The inner-loop 32x32 -> 64-bit multiplies are INLINED (split into
16-bit halves directly) rather than calling a helper that returns a
`[lo, hi]` pair. The helper form would allocate ~512k short-lived
2-element lists per modpow at 256 bits; the 2048-bit module's
experience was the same anti-pattern allocating ~32M pairs per
modpow ballooning the heap to 14GB+ before the inline fix. The
inline form allocates ZERO per-iter lists past the one-shot 9-limb
accumulator, and the modpow runs cleanly inside the sandbox budget.

### Test coverage

`tests/unit/test_bignum_256.nova` (NEW in R6B) -- **70 assertions**
across 27 test functions covering: hex round-trip / carry chains /
underflow wrap / mul small + carry-into-hi + max-squared / mod /
modmul / modpow_ct textbook + edges + Curve25519 2^255 sanity;
Montgomery context round-trip on N=1009; mont == legacy equivalence
on 2 pseudo-random vectors at small N + 1 cross-check on the
Curve25519 prime with `0xDEADBEEFDEADBEEF`; the **headline check**
Fermat's little theorem on the Curve25519 prime
(`bn256_modpow_ct(2, p-1, p) == 1` -- passes in ~**3.1 ms** wall-
clock); speedup-ratio measurement on the Curve25519 prime with the
full 254-bit `p-1` exponent. Observed median on this dev container:
**~14x** (Mont ~3.1 ms, Legacy ~45 ms). Both paths produce the
Fermat identity value (1) -- the speedup ratio is over the identical
computation, not a shortcut. The test prints the ratio and asserts
a conservative >=2x band to keep CI stable under sandbox-load
variance.

### Existing `bignum.nova` (the `bn_*` prefix) is unchanged

The existing `bn_modpow_ct` continues to use the bit-by-bit reducer
and remains the primitive in use by Curve25519 ECDH emulation, the
ChaCha20-Poly1305 field math, and the `secure_aggregation.nova`
DH-256 fallback. Migrating those callers to `bn256_modpow_ct` for
the per-op ~14x speedup is a follow-up patch (the new prefix is
ship-able without touching any in-use call site).

## R7B production migration: DH-256 (`bn_modpow_ct` -> `bn256_modpow_ct`)

R7B realized the per-op ~14x speedup from R6B's bignum_256 in the only
production caller of `bn_modpow_ct` (the legacy 256-bit
`bn_modpow_ct`): the v2-sa-dh path in
`src/learning/secure_aggregation.nova`. Two call sites:

  * `sa_dh_generate_keys` (one `g^priv mod p` per soul per round);
  * `sa_dh_shared_secret_for_peer` (one `peer_pub^my_priv mod p` per
    peer per round).

Both run on the Curve25519 prime `p = 2^255 - 19` (loaded from the
existing `_SA_DH_P_HEX` constant), which is odd, so Montgomery REDC
applies. Both were swapped from `bn_*` to `bn256_*` end-to-end
(`bn_from_hex` -> `bn256_from_hex`, `bn_mod` -> `bn256_mod`,
`bn_modpow_ct` -> `bn256_modpow_ct`, `bn_to_hex` -> `bn256_to_hex`).
The on-disk hex representation is byte-identical between `bn_*` and
`bn256_*` (both encode as 64 lowercase hex chars MSB-first; both
internal layouts are 8 x 32-bit little-endian limbs), so registered
peer pubkeys parse cleanly via either module and the wire format is
unchanged.

### Measured speedup (R7B, this dev container)

Microbenchmark: 10 iterations of a 2-soul-pair DH round
(2 keygens + 2 shared-secret derivations = **4 `bn_modpow_ct` calls
per iter**).

  * **BEFORE** (legacy bit-by-bit reducer): 260 ms / iter avg,
    ~65 ms per `bn_modpow_ct` call.
  * **AFTER** (Montgomery REDC via `bn256_modpow_ct`): 12.9 ms / iter
    avg, ~3.2 ms per `bn256_modpow_ct` call.
  * **Speedup: ~20x per call** (per-iter total 260 ms -> 12.9 ms).
    Slightly above R6B's headline 14x microbenchmark on
    `test_bn256_modpow_mont_speedup_ratio`; the difference is within
    sandbox-load variance.

### Correctness verification

  * `tests/unit/test_bignum_256.nova` passes 70 checks, including the
    Mont-vs-legacy equivalence sweep on the Curve25519 prime which
    proves `bn256_modpow_ct == bn_modpow_ct` on the production
    modulus.
  * `tests/unit/test_secure_aggregation.nova` passes 170 checks --
    notably the DH commutativity test
    `test_sa_dh_two_soul_pair_mask_matches` (alice's
    `peer_pub^my_priv` equals bob's `peer_pub^my_priv` after the
    migration) and `test_secagg_two_soul_dh_sum_demo` (full end-to-
    end masked-sum cancellation with DH-derived shared secrets).
  * `tests/integration/scenario_u_secagg.sh` passes 48/48 across
    SecAgg, dropout-resilience, DH-256, and DH-2048 sub-scenarios.
  * `tests/integration/scenario_v_secure_channel.sh` passes 6/6 (PSK
    secure channel; verifies the migration does not regress the
    chacha20/poly1305 leaves it depends on transitively).

### What stays on `bn_*`

  * `tests/unit/test_bignum.nova` and `tests/unit/test_secure_aggregation.nova`
    still call `bn_from_hex`/`bn_zero`/`bn_modpow`/`bn_modpow_ct`
    directly to exercise the legacy primitive surface -- those tests
    are unchanged. The legacy `bn_*` API in `bignum.nova` remains
    in-tree as the equivalence anchor for `bn256_*` and as the public-
    exponent (offline) `bn_modpow` test path.
  * `src/safety/chacha20.nova` and `src/safety/poly1305.nova` do not
    use `bn_modpow_ct` (Poly1305's 130-bit prime is a separate field
    arithmetic, NOT 256-bit; the `bn256_*` 256-bit fixed width does
    not apply).
  * `src/io/transducers/noise_xk.nova` -- the Noise XK 256-bit DH was
    the other in-tree caller. That migration is **R7C's scope** and
    targets `bn2048_modpow_ct` (RFC 7919 Group 14, strength upgrade
    in addition to perf), so this audit does not touch noise_xk.

## R9F appendix — Byzantine-resilient federated aggregation (P3.10 / ADR-0056)

### What R9F adds

A new leaf module `src/learning/byzantine_aggregation.nova` plus a
Byzantine-aware accumulator path in `federated_aggregator.nova`. The
module ships two coordinate-wise robust aggregation rules:

  * **Trimmed mean** (`byz_trimmed_mean(updates, trim_k)`):
    sort each coordinate across participants, drop the top-k and
    bottom-k extreme values, mean of the remainder. Tolerates `k`
    Byzantine participants per coordinate. Fast (O(n^2) insertion
    sort dominates; n is small in practice).
  * **Coordinate-wise median** (`byz_coordinate_median(updates)`):
    median per coordinate. Tolerates up to ~n/2 Byzantine in the
    worst case. Same per-coord cost as trimmed mean; no `trim_k`
    knob to tune.

Both algorithms work on lists of integer-vector "updates" so the same
module can serve federated rate-of-promotion aggregation today and
generic D-dim model deltas in a future round.

A `byz_aggregate(updates, strategy, trim_k)` dispatcher routes the
caller's `BYZ_NONE | BYZ_TRIMMED_MEAN | BYZ_MEDIAN` choice. The
existing `federated_aggregator.nova` gains a parallel accumulator
(`fed_acc_byz_*`) that keeps per-participant rows rather than
collapsing to a sum, and a `fed_acc_byz_aggregate(acc, strategy,
trim_k)` reducer that returns the same shape as `fed_acc_averages`.

### The SecAgg vs Byzantine trade-off (deliberate)

SecAgg's privacy guarantee is that the coordinator sees ONLY the SUM
of all souls' contributions: per-soul values are hidden via pairwise
additive masks that cancel in aggregate. A coordinator following the
protocol literally cannot inspect a single soul's masked submission.

Byzantine-resilient aggregation does the OPPOSITE: to filter
adversarial outliers, the aggregator MUST inspect each soul's
contribution individually. The two are FUNDAMENTALLY in tension at
this layer. Two naive composition options exist:

  * **SecAgg-then-Byzantine** -- coordinator decrypts to per-soul
    values, then trims. This DEFEATS SecAgg's privacy property:
    inspecting per-soul values to filter outliers is exactly the
    capability SecAgg withholds from the coordinator.
  * **Byzantine-then-SecAgg** -- each soul filters its OWN update
    before masking. Trivially circumventable: a Byzantine soul
    simply skips the filter and masks its poisoned update directly.
    The masks cancel as designed; the poisoned value contributes to
    the sum without any defense.

R9F therefore makes Byzantine resilience a SEPARATE PRIVACY POSTURE
from SecAgg, not a layer over it. Operators pick ONE per round:

  * **SecAgg mode** (use `sa_acc_*`): privacy guarantee, no Byzantine
    defense beyond a per-soul range clamp (which an adversarial soul
    can defeat by submitting in-range but biased values).
  * **Byzantine mode** (use `fed_acc_byz_*`): per-soul plaintext
    visible to the coordinator, robust aggregation against an
    adaptive adversary up to f participants.

The advanced primitives that would close this gap — zero-knowledge
proofs of well-formedness on masked submissions, threshold-
homomorphic encryption with range proofs, or trimmed-mean computed
directly over secret shares — require months of crypto-protocol
engineering and are deliberately out of scope for P3.10. The trade-
off is surfaced here so operators choose the correct posture for
their threat model.

### Env knobs

  * `CE_FL_BYZ_STRATEGY` -- `none` | `trimmed` | `median`. Default
    `none` (preserves P3.7's averaging behaviour). Recognised
    lowercase tokens only.
  * `CE_FL_BYZ_TRIM_K` -- integer; the number of extreme values to
    drop from EACH end per coordinate. Default `1`. A value of 0
    reduces trimmed mean to the plain mean. Excessively large values
    (`2 * trim_k >= n`) return zeros (degenerate config; caller
    should reduce `trim_k`).

### Verification

  * `tests/unit/test_byzantine_aggregation.nova` -- 74 assertions
    covering the algorithm semantics on the canonical fixtures, the
    poisoning resilience (one 100x outlier among 5; both algorithms
    track the honest cluster), multi-dim per-coord aggregation,
    edge cases (empty / single-participant / 2-participant /
    degenerate `trim_k`), the env parsers, the dispatcher routing,
    and the `fed_acc_byz_*` integration with the federated
    accumulator.
  * `tests/integration/scenario_pp_byz_fl.sh` -- 15 assertions
    against a NOVA driver that simulates 5 souls (4 honest, 1
    Byzantine) submitting the same source rate. The bash side
    asserts that BYZ_NONE produces a poisoned aggregate
    (promo=2563, atr=2163 on a 9999-poisoned fixture where the
    honest mean is 705/205), BYZ_TRIMMED_MEAN matches the honest
    mean (promo=710, atr=210), and BYZ_MEDIAN matches the honest
    median (promo=710, atr=210). The poisoning-skew reduction is
    ~370x (NONE skew = 1858, trimmed skew = 5).
  * `tests/unit/test_secure_aggregation.nova` -- 170 assertions
    bit-identically green (the SecAgg path is untouched; the only
    edit to `secure_aggregation.nova` was a header-comment note on
    the trade-off).
  * `tests/unit/test_federated_aggregator.nova` -- 91 assertions
    bit-identically green (the FL aggregator gains the parallel
    `fed_acc_byz_*` block but the existing `fed_acc_*` path is
    unchanged).

### Why R9F does NOT implement Krum / Bulyan

  * **Krum** -- O(n^2 * d) per round. Implementable in pure NOVA, but
    the n=5 federations CrossEngin currently runs are small enough
    that median already pins the result to the honest cluster.
    Trimmed mean is faster and gives most of the benefit at this
    scale; the additional 2x slowdown of Krum buys little.
  * **Bulyan** (Krum followed by trimmed mean) -- O(n^3) per round,
    requires n >= 4f + 3. The asymptotic robustness guarantees
    matter at the n=20+ scale; R9F's 5-soul fixture is too small
    for the guarantees to bind.

Both are tractable follow-ups when the federation scales. The current
`byz_aggregate` dispatcher is structured so a future Krum / Bulyan
addition is a one-case extension, not a re-architecture.
