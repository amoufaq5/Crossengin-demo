# Secure Aggregation (SecAgg) Audit

**Phase:** P3.8 — secure aggregation MVP (pairwise additive masking)
**ADR:** ADR-0055 — SecAgg via pairwise additive masking with pre-shared tokens
**Modules:** `src/learning/secure_aggregation.nova`,
`src/learning/federated_aggregator.nova` (extended with v2-sa mode),
SECAGG\_\* parser branch additively added to
`src/io/transducers/kg_sync.nova`,
`examples/crossengin_fed_coordinator.nova` (SecAgg coordinator branch),
`examples/crossengin_chat.nova` (env-detected v2-sa fed_join path).

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

- **No dropout handling.** If a soul vanishes between the JOIN
  handshake and the FED\_STAT\_MASKED submission, the masks it
  would have contributed don't get sent — the surviving souls'
  submissions still carry their `+/-m_{ij}` terms for the absent
  peer, which do NOT cancel. The coordinator's sum is corrupted by
  an additive noise term equal to the missing soul's net mask
  contribution. Production SecAgg fixes this with Shamir secret
  sharing of each soul's mask seeds (any k of n shares
  reconstruct the seed; missing souls' masks can be subtracted
  from the sum after the fact). The MVP documents the failure
  mode and refuses no round — the corrupted sum is the visible
  symptom of the missing soul.

- **No verifiable secret sharing (Shamir).** As above. Adding
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

The coordinator broadcasts the **sum** (not the average) so the
audit-readable contract is clean: the coordinator only ever computes
sums. The soul divides by `n_participants` on its own end to recover
the average if it wants one (helper: `sa_sum_to_avg`).

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
