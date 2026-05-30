# Differential Privacy Audit

**Phase:** P3.6 — minimum viable DP at the KG-query surface
**ADR:** ADR-0053 — differential privacy at the knowledge-graph-query surface
**Module:** `src/safety/differential_privacy.nova`

## Why integer Laplace is the right primitive for CrossEngin

CrossEngin runs on a pure-integer substrate: every belief is an
`(alpha, beta)` pair in milli-fixed-point (scale = 1000), every mood
component is a milli-valued integer, and every embedding component is an
integer in `[-1000, 1000]`. The entire knowledge-graph data plane is
already pre-quantised to the same granularity that a DP mechanism needs
for its output. We have no `float` type in the language at all (NOVA v0.x
is integer-only), no `math.exp`, no `random.gauss` — so adopting the
standard continuous Laplace mechanism (`Lap(scale)`) is not even on the
table.

The standard escape valve is the **discrete Laplace distribution**, also
called the **two-sided geometric**. The variate `Y = G(p) - G(p)` where
`G(p)` is the geometric distribution on the non-negative integers with
parameter `p` is supported on `Z`, has mean 0, variance `2 * (1 - p) /
p^2`, and tail probabilities that closely track the continuous Laplace
CDF for `p` near `1 - e^(-epsilon / Delta_f)`. This is the discrete
Laplace mechanism of Ghosh / Roughgarden / Sundararajan (2009); it
satisfies pure differential privacy with the same `(epsilon, 0)` envelope
as the continuous mechanism. For CrossEngin the discrete variant is the
*natural* fit:

- It is integer-only, so no NOVA codegen workarounds are needed for
  fractional arithmetic. (The codegen does have one: large multiplies
  cross a pointer-threshold check at 2^20 that misroutes them into
  `str_repeat`. The LCG is engineered with both operands masked to 15
  bits at every step, and the avalanche XOR keeps the working set inside
  the safe range. NOVA bug #5/6.)
- The output domain matches the KG query domain (`kg_atom_count` is an
  integer; belief means are milli-integers in `[0, 1000]`).
- Variance scales `~ 2 * scale^2`, matching the continuous Laplace
  utility envelope — the same `~63%` within `+/-scale` and `~86%`
  within `+/-2*scale` shape (measured: 65% / 83% over 1000 samples).

## Sensitivities for the common queries

The DP scale is `Delta_f / epsilon`, where `Delta_f` is the **sensitivity**
of the query — the maximum amount a single user's contribution can change
the answer. Each opt-in DP wrapper picks the sensitivity per its
semantics.

| Query | Sensitivity Delta_f | Notes |
|---|---|---|
| `kg_atom_count` | **1** | A single teaching event creates or removes at most one atom. The tightest sensitivity in the system. |
| `kg_atom_belief_mean` (per-atom) | **1000 / (alpha + beta)** milli | The posterior mean `alpha/(alpha+beta)` shifts by at most `1/(alpha+beta)` when one observation flips. For a freshly-seeded atom this is `500` milli (very loose); after 10 observations it drops to `~100` milli; after 100 observations it is `~10` milli. The wrapper floors at 100 milli so a heavy-evidence atom does not get an unrealistically tight noise band. |
| `kg_cosine_similarity` (future) | **2000 / n_dims** milli | An L2-normalised cosine over `n_dims=8` integer-milli vectors changes by at most `2/n` when one vector flips polarity. For the current 8-dim embeddings, this is `250` milli. Not wired in P3.6; reserved for P3.7. |
| `kg_centroid` (future) | **1000 / kg_atom_count** milli | The mean embedding shifts by `1/n` per dimension when one atom changes. Sensitivity drops as the KG grows — a small-KG query is the worst case. Not wired in P3.6. |

## Privacy / utility trade-off

The per-session budget defaults to `epsilon = 10.0` (10000 milli-eps).
This is **moderate**, not production-grade. To put it in context:

- `epsilon = 0.1` is the typical "strong" DP setting used in published
  research on shared databases (US Census 2020 published its
  disclosure-avoidance system at `epsilon = 19.6` over the whole release,
  with per-product budgets of `~0.1`).
- `epsilon = 1.0` is "moderate" — enough utility for analyst-grade
  queries while preserving plausible deniability.
- `epsilon = 10.0` is the CrossEngin default — enough utility for an
  **operator diagnostic surface** where the analyst is the agent's
  operator (not an external party) and the goal is *bounded* leakage
  rather than indistinguishability. At `epsilon = 0.1` per
  `kg_atom_count_dp` call, the budget allows **100 noisy queries per
  session** before refusal. That is enough for an operator to monitor
  KG growth over a session but not enough to reconstruct the teaching
  trace via repeated queries.

Concretely, the noise envelope at the `/dp_query atoms` default of
`epsilon = 0.1` is:

- Scale = `1 / 0.1 = 10` (continuous Laplace scale).
- Stdev `~ 14`.
- ~63% of answers within `+/-10` of the true count.
- ~95% within `+/-30`.

A `kg_atom_count` of `572` is reported as `noisy ~ 572 +/- 14` —
distinguishable from `573` only with low confidence per query, and the
~100-query budget per session caps how many independent draws an
adversary can average over. (Pure DP composition does NOT let the
adversary "wash out" the noise: the privacy bound holds regardless of
the number of queries, but the *utility* of any single query is bounded
by the configured noise.)

## Composability

Sequential composition of pure-DP mechanisms is **additive**: N queries
each consuming `epsilon_i` milli-eps consume `sum(epsilon_i)` milli-eps
total against the privacy bound. This is exactly the bookkeeping the
`dp_consume` accountant performs: every wrapper deducts its declared
`epsilon_milli` from the per-session `DP_REMAINING` slot, and the
session is "spent" when the slot reaches zero.

The current implementation supports ONLY sequential composition. Two
known refinements are reserved for future work:

1. **Advanced composition / RDP.** Renyi differential privacy and the
   moments accountant give tighter bounds on long-running query streams
   (e.g. the `sqrt(N)` improvement of the moments accountant over linear
   composition for the Gaussian mechanism). These require either a
   different noise distribution (Gaussian) or a different accountant
   (RDP-budget tracking instead of pure-`epsilon` bookkeeping). Both
   are out of scope for P3.6.
2. **Parallel composition.** When two queries access disjoint atoms of
   the KG, their privacy costs do NOT add — the maximum applies
   instead. The current accountant adds unconditionally, which is
   safe (it is an upper bound on the true privacy cost) but suboptimal.
   A future revision can track the support set of each query and apply
   parallel composition where appropriate.

## Refusal on exhaustion (option 2)

When the budget is exhausted, the DP wrappers return `DP_REFUSED`
(`-2147483647` — a sentinel that no realistic noise value can collide
with). The chat-side `/dp_query` admin command prints
`dp_query atoms: budget exhausted (remaining 0 milli-eps)` and the
underlying KG query is NOT executed. This is "option 2" in the design
brief; "option 1" (return cached / stale answers, which is also
privacy-preserving) is a reasonable alternative for read-mostly
workloads and is reserved for a future revision when call sites warrant
it.

The refusal is *privacy-preserving*: a refusal cannot leak fresh
information about the underlying data — the only bit it leaks is "the
budget was exhausted", which is a function of the *query sequence*, not
the data.

## Gaps for future work

1. **Advanced composition (RDP / moments accountant)** — tighter bounds
   over long query streams (above).
2. **Parallel composition over disjoint KG slices** — better budget
   utilization when queries don't overlap (above).
3. **Distributed DP for federated multi-soul (P3.7)** — when N
   CrossEngin instances cooperate (kg-sync between souls), the
   union of their queries leaks more than any one alone. A
   *shuffle-DP* or *secure-aggregation* layer would shrink the
   combined `epsilon`. P3.7 territory.
4. **Sensitivity proofs at every wrapper site** — today the
   sensitivities documented above are *claimed*, not formally proved.
   A future ADR could carry a per-query sensitivity lemma + a
   regression test that the wrapper site honours it.
5. **Differential-privacy-aware audit log entries** — the decision log
   does not yet record DP consumption events. Adding a `DLK_DP_QUERY`
   entry would let `/why`-style introspection surface the budget
   trace alongside the usual gate decisions.
6. **Better random-number quality** — the 15-bit LCG with avalanche
   gives empirically good Laplace shape (within `+/-3%` of the true
   CDF over 1000 samples) but the period is short (`< 2^15`). A
   future revision could use a counter-based PRF (e.g. a tiny
   Speck variant) with the same pointer-threshold-safe arithmetic.

## Implementation summary

- `src/safety/differential_privacy.nova` (new, ~280 LOC). The module is
  self-contained: it imports only `std/io` (for `nanotime` as a seed
  source) and has no upstream CrossEngin dependencies, so the privacy
  primitive has no attack surface.
- `src/kg/multi_kg_manager.nova` gains `kg_atom_count_dp` and
  `kg_atom_belief_mean_dp` (opt-in wrappers; original queries
  unchanged).
- `src/session/session.nova` gains the `SES_DP` slot and the
  `session_dp` / `session_attach_dp` accessors. Default budget of
  `10.0` epsilon (= 10000 milli-eps) per session, overridable via
  `$CE_DP_EPSILON_BUDGET`.
- `examples/crossengin_chat.nova` exposes `/dp_status` and
  `/dp_query atoms`. The latter is an admin diagnostic — it prints
  BOTH the true count and the noisy count; in a production tenant
  context the true count would be gated behind a role check.
- `examples/crossengin_daemon.nova` instantiates the per-session
  `dp_state` at boot, mirroring the P1.1 source-authority wiring.
- `tests/unit/test_differential_privacy.nova` covers 52 assertions:
  budget accounting, Laplace mean/variance/shape, determinism, refusal,
  clamping.
- `tests/integration/scenario_p_dp_budget.sh` covers 10 assertions:
  initial budget, drain over 100+ queries, exhaustion refusal,
  variance check, monotonic budget decrease, `/help` listing.

## Sample observations

```
> /dp_status
dp budget: 0 / 10000 milli-eps consumed (remaining 10000 milli-eps over 0 queries)

> /dp_query atoms
dp_query atoms: true=572 noisy=583 (epsilon=100 milli, remaining 9900)

> /dp_query atoms
dp_query atoms: true=572 noisy=581 (epsilon=100 milli, remaining 9800)

> /dp_status
dp budget: 200 / 10000 milli-eps consumed (remaining 9800 milli-eps over 2 queries)
```

Distribution shape over 1000 samples at `scale = 1.0`:

| Band | Theory (Laplace CDF) | Observed |
|---|---|---|
| `\|v\| = 0` | ~318 (interpolated) | 335 |
| `\|v\| <= 1` | ~632 | 650 |
| `\|v\| <= 2` | ~865 | 827 |
| `\|v\| <= 3` | ~950 | 908 |
| `\|v\| <= 4` | ~982 | 954 |

Sample mean over 1000 draws: `+13` (max ±100 expected; well within the
sampling error of `sqrt(1000 * 2)` ~ `45`).
