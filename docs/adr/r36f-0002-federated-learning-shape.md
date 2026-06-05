# ADR R36F-0002: Federated learning shape -- DP composition, EMA pull, Sybil model

## Status
Accepted (R36F) -- learning loop shape coalesced over R8 (initial
learning loop), R19 (DP audit), R23 (EMA), R26 (snapshot replication),
R30-R35 (federation transport).

## Context
CrossEngin v1 is a desktop companion (single user, single device). The
v2 horizon is a single-tenant enterprise pilot, where multiple
CrossEngin instances learn from each other without ever shipping raw
moments off-device. The federation surface therefore has to answer
three orthogonal questions:

  1. **Privacy budget.** Each shared update reveals some signal about
     the contributing instance's moments. How do we account for it?
  2. **Aggregation shape.** Do we sum, average, or pull-toward when
     fusing peer updates into the local node weights?
  3. **Adversarial model.** What level of trust do we assume between
     peers? Is the threat a curious researcher, a single malicious
     peer, or a coordinated Sybil swarm?

These are intertwined: stronger privacy budgets cap how much each peer
can contribute, which constrains aggregation shape, which interacts
with the Sybil model.

## Decision
**1. Differential-privacy composition with explicit epsilon budget.**
Each peer-to-peer update is noised via Gaussian DP at the source. The
per-update epsilon is configured per node-class (perception synapses
get a tighter budget than KG-medicine, etc.). Total budget is composed
across updates using the basic sequential composition theorem (NOT
RDP / advanced composition); the per-instance daily epsilon ceiling is
exposed in `DP_AUDIT.md` and surfaced via the audit log.

**2. No secure aggregation in v1.** We accept that peers can see each
other's noised updates. Secure aggregation (cryptographic sum-without-
seeing-individuals, e.g. Bonawitz et al. 2017) would require a
coordinator and a key-agreement quorum. That coordinator does not exist
in our gossip-based federation (R30-R35). v2 may add it.

**3. EMA pull-strength = 0.1 (10% per round).** Local node weights are
updated as `w_local := 0.9 * w_local + 0.1 * w_aggregated_peers`. The
0.1 value was chosen so that a single noisy round cannot dominate local
state; ~22 rounds are needed to halve the influence of any pre-existing
local belief. TODO: pin the exact round where 0.1 was decided -- search
turns up R23-era discussion but the literal commit is not unambiguous.

**4. Sybil resistance assumes "few-shot" attackers.** A peer adversary
controlling K identities can pull local weights toward their preferred
direction at speed roughly `K / (K + N_honest)`. We assume `N_honest >
10 * K` in v1 and document this as an explicit limit. v2's enterprise
pilot ships with peer-identity proofs (signed attestations) that raise
the Sybil cost.

## Consequences
**Positive.**
  - DP epsilon is auditable per instance per day via the audit log
    (R21, R29 audit modules) and can be tuned per node-class without
    refactoring the learning loop.
  - The 0.1 EMA pull means single-round corruption is bounded: a
    Sybil burst lasting 1 round shifts local weights by <= 10% and
    decays exponentially as honest peers re-vote.
  - No-secure-aggregation simplification eliminates a coordinator
    requirement, keeping the federation gossip-shaped and decentralised.

**Negative.**
  - Honest peers must add Gaussian DP noise, which hurts learning
    efficiency. v1 trades off learning speed against privacy.
  - The Sybil assumption is fragile in open federations. v1 is
    explicitly NOT an open federation; v2 must layer attestations.
  - Sequential composition is more conservative than RDP; a future
    optimisation can recover budget by switching to RDP without
    changing the wire protocol.

**Follow-up rounds.**
  - R37+: pin the literal EMA round in `FEDERATED_AUDIT.md`.
  - v2: secure aggregation prototype; peer-identity attestations.
  - v2: switch DP composition to RDP for tighter budgets.

## Alternatives considered
  - **Federated SGD without DP.** Rejected: leaks per-moment signal,
    violates the desktop-companion privacy promise.
  - **Centralised training with raw-data shipping.** Rejected outright:
    raw moments never leave the device.
  - **Secure aggregation in v1.** Rejected: needs a quorum coordinator
    that conflicts with our gossip federation shape.
  - **EMA pull = 0.5.** Rejected: a single noisy round can dominate
    local belief; recovery would take too long.
  - **EMA pull = 0.01.** Rejected: too sluggish; the desktop companion
    would take 100+ rounds to incorporate a useful peer signal.
