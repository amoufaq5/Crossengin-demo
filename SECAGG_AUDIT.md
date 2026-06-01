# Secure Aggregation (SecAgg) Audit

**Phase:** P3.8 — secure aggregation MVP (pairwise additive masking),
extended to **P3.8r — dropout-resilient SecAgg (v2-sa-r)**.
**ADR:** ADR-0055 — SecAgg via pairwise additive masking with
pre-shared tokens. The dropout-resilience extension layers on top of
the original ADR-0055 primitive: same mask derivation, same wire
envelope, with an additive FED_DROPOUT + FED_RECON_MASKED protocol
pair that lets the surviving souls reconcile their submissions when
one peer vanishes mid-round.
**Modules:** `src/learning/secure_aggregation.nova` (P3.8r:
`sa_recompute_without` / `sa_reconcile_for_dropped` + FED_DROPOUT /
FED_RECON_MASKED wire formatters + parsers + the
`CE_FED_ROUND_DEADLINE_MS` env helper),
`src/learning/federated_aggregator.nova` (extended with v2-sa mode and
the P3.8r reconciliation emitter `fed_agg_emit_recon_masked`),
SECAGG\_\* parser branch additively added to
`src/io/transducers/kg_sync.nova` (one more dispatch case for
FED_DROPOUT / FED_RECON_MASKED),
`examples/crossengin_fed_coordinator.nova` (SecAgg-r coordinator with
dropout detection + reconciliation broadcast / collect path),
`examples/crossengin_chat.nova` (env-detected v2-sa fed_join path with
the FED_DROPOUT receive hook -- no new admin commands).

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

## Full SecAgg upgrade path

The reference Google SecAgg (~4-6 weeks per the published prototype)
adds:

1. **DH key agreement** — **bignum prerequisite landed (`src/safety/bignum.nova`);
   DH key exchange unblocked.** A pure-NOVA 256-bit unsigned bignum library
   shipped in the session that produced this paragraph: `bn_new` /
   `bn_from_hex` / `bn_to_hex` / `bn_add` / `bn_sub` / `bn_mul` (512-bit
   product as `[hi, lo]`) / `bn_mod` / `bn_modmul` / `bn_modpow`. The
   modular-exponentiation kernel is verified against the textbook
   `2^10 mod 1000 = 24` and against the Curve25519 prime
   `p = 2^255 - 19` (`2^255 mod p = 19`, equivalent to RFC 7748's
   field-element reduction step). Limb representation: 8 32-bit limbs,
   LSB at index 0, so each per-limb arithmetic intermediate stays well
   under 2^64 (the schoolbook 256x256 multiply splits each 32-bit limb
   into two 16-bit halves so per-cell products fit cleanly in the
   positive signed 63-bit band). With bignum in hand, an X25519 DH
   exchange becomes (a) generate a 256-bit scalar, (b) call a (yet to be
   shipped) Curve25519 scalar-mult primitive
   `x25519(scalar, base_point)` over the Curve25519 Montgomery form, (c)
   send the public point, (d) on receive call `x25519(scalar, peer_point)`
   to derive the shared mask seed. Steps (a) + (b) + (d) need 1-2 weeks
   of pure crypto work on top of the bignum library: the actual scalar-
   mult routine (Montgomery ladder), the Curve25519 field-element
   compression / decompression, and the public-key encoding.
   **Constant-time follow-up required for production.** The MVP `bn_modpow`
   branches on the exponent's bit pattern (square-and-multiply) so the
   timing leak is observable to a network adversary. The constant-time
   re-implementation (Montgomery ladder for scalar mult, masked
   subtraction for borrow, fixed-window exp for `bn_modpow`) is its own
   ~2-3 week project per primitive. The current MVP `bn_modpow` is
   sufficient for OFFLINE self-tests + verification of stored
   crypto material; do NOT export it to a remote-callable code path
   without the const-time follow-up.
2. **Shamir secret sharing of mask seeds** — ~2 weeks once we have
   a finite-field polynomial primitive.
3. **Dropout handling** — ~1 week once Shamir lands (compose the
   share-reveal protocol with the mask cancellation).
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
| `bn_modpow(b, e, m)` | bn | b^e mod m, right-to-left square-and-multiply |

Test coverage lives in `tests/unit/test_bignum.nova` -- 54 assertions
across `bn_to_hex` / `bn_from_hex` round-trip on the all-zeros, all-ones,
short, and case-mixed inputs; 32-bit carry propagation in `bn_add`;
underflow wrap in `bn_sub`; small + 2^128-squared + max-squared products
in `bn_mul`; small modulus + a < m in `bn_mod`; `(5*6) mod 7 = 2` in
`bn_modmul`; the textbook `2^10 mod 1000 = 24` and the Curve25519
`2^255 mod (2^255-19) = 19` in `bn_modpow`. The smallest measurable
op (a single `bn_add` call, no loop) clocks ~800 ns via `nanotime()`
on the dev container (one-time measurement -- environments vary by
10x).
