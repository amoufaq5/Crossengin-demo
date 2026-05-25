# ADR-0009: Gate design (learned routing, signal-content-based, broadcast support)

## Status

Proposed

## Date

2026-05-25

## Context
A signal (ADR-0008) leaving a node must reach the right destination part(s) — a sensory signal to perception's first nodes (ADR-0010), an error signal up the predictive-coding stack (ADR-0024), a constitutional signal everywhere with veto priority (ADR-0045). With nine parts, 1M nodes each, and 1B signals/part, hard-wiring every routing path is impossible and would freeze the substrate's organization. ADR-0002 specifies gates as learned routing checkpoints that "decide which parts receive which signals based on signal content," start with basic rules, develop sophistication, and can broadcast to multiple parts at once. We must now design that mechanism concretely.

NOVA's `core/channel.nova` gives the raw material: layout `[TAG, name, source, destinations, chan_type, filter_min_salience, message_count]` and four channel types. Two are directly relevant: `CHAN_FILTERED` (route by a salience/content filter) and `CHAN_BROADCAST` (one-to-many), plus `CHAN_WEIGHTED`. A gate is essentially a `CHAN_FILTERED`/`CHAN_BROADCAST` channel whose filter is LEARNED rather than static. But `core/channel.nova` filters are fixed thresholds; CrossEngin needs the routing decision to adapt with experience while remaining cheap enough for the 100Hz loop and inspectable enough for the safety layer (ADR-0043).

The bootstrapping constraint shapes this heavily. We cannot ship a system that learns all routing from scratch — it would behave randomly for months. We need sensible seed rules (sensory→perception, goal-drive→reasoning, constitutional→broadcast) that work on day one, with learning layered on top to refine and add routes. And every routing decision involving an action-class signal must be loggable for ADR-0043.

## Decision
A gate is a learned, content-based router built atop `core/channel.nova`, placed between a source (a node's outbox or an inter-part synapse block) and one-or-more destination parts. Each gate holds a small routing TABLE keyed primarily on signal type (the 18 `XSIG_*` constants, ADR-0008) and secondarily on lightweight signal content: the signal's `priority`, salient `metadata` keys, and a coarse activation/topic vector. The table entry yields a set of destination parts each with a routing WEIGHT; destinations whose weight exceeds the gate's admit threshold receive the signal. When two or more destinations qualify, the gate uses a `CHAN_BROADCAST` fan-out; when one qualifies, a `CHAN_DIRECT`/`CHAN_FILTERED` delivery.

Routing weights are SEEDED with hand-written rules and then LEARNED. Seed rules encode obvious priors: `XSIG_SENSORY`→perception first nodes; `XSIG_GOAL`→reasoning+action; `XSIG_RECALL`→episodic; `XSIG_CONST`→broadcast to all parts at top priority. Learning is reinforcement-style and reuses the plasticity machinery of ADR-0007: when a routed signal contributes to a rewarded outcome (an `XSIG_REWARD`, ADR-0008) or reduces downstream prediction error (`XSIG_ERROR`, ADR-0024), the route weight to that destination is strengthened; consistently useless routes decay and are pruned, exactly mirroring synapse growth/pruning. Thus gates "develop sophistication" without a separate learning subsystem.

Constitutional routing is privileged and NOT learnable: `XSIG_CONST` signals always broadcast at priority 9 and the gate cannot down-weight or prune that route (enforced, ADR-0045). This is the one hard exception to learned routing.

## Options Considered
**Static rule-based routing (fixed `CHAN_FILTERED` filters).** Hand-write all routes once; no learning. Simplest and most predictable, and it ships fastest for two founders. Rejected as the sole mechanism: it freezes the substrate's organization, contradicting ADR-0002's "develops sophistication," and cannot discover that, say, a particular medical pattern should also reach the imagination part. We keep its strength by using it as the SEED layer beneath learning.

**Full broadcast everywhere (no gating).** Every signal goes to every part; let nodes ignore irrelevant input. Trivially simple. Rejected on cost: broadcasting 1B signals/part to nine parts is ~9B deliveries/tick — far beyond the desktop and the SIMD budget (enhancement #4) — and it removes the attentional focusing that `XSIG_ATTEND` (ADR-0008) is meant to provide. Broadcast is retained only where semantically required (constitutional, some attentive signals).

**A learned neural classifier per gate (a small network deciding routes).** Maximally adaptive content-based routing. Rejected for v1: it adds a second, opaque learning system distinct from synapse plasticity, doubling the machinery the team must build and tune, and an opaque router conflicts with the inspectability the decision log (ADR-0043) and override mechanism (ADR-0044) require. A weighted table learned by the SAME reinforcement rule as synapses is adaptive enough and stays auditable.

**Chosen:** seeded-then-learned weighted routing tables on `core/channel.nova`, reusing ADR-0007 plasticity, with a privileged non-learnable constitutional path. It works on day one, improves with experience, costs little in the hot loop, and remains inspectable.

## Consequences
- **Positive:** Day-one sensible behavior from seed rules with no cold-start; routing improves automatically using machinery already built for ADR-0007 (no new learner). Content-based admission plus selective broadcast keeps signal volume tractable and supports attention. Constitutional broadcast is structurally guaranteed (ADR-0045). Tables are human-readable, satisfying ADR-0043/ADR-0044 inspection.
- **Negative:** A learned routing layer adds a tuning surface (admit threshold, route learning rate, decay) and a failure mode where mis-learned routes misdeliver signals — needs a gate-trace tool in the harness. Sharing the reinforcement signal with synapse plasticity couples two systems; a reward-attribution bug affects both. Per-gate tables consume memory that must be budgeted within the desktop limit.
- **Future work:** Gates feed first nodes (ADR-0010) and are the routing backbone for predictive/error flow (ADR-0024), goal-driven biasing (ADR-0033), recall cues (ADR-0022/ADR-0012), and constitutional veto (ADR-0045). Gate routes are part of the substrate snapshot (ADR-0048). v2 multi-tenant (ADR-0047) keeps the constitutional path non-negotiable across tenants.

## Implementation Notes
New module `core/gate.nova` exposing `gate_new(name, source, seed_rules)`, `gate_route(gate, signal)` (returns destination set; emits via `core/channel.nova` `CHAN_BROADCAST` or `CHAN_DIRECT`), `gate_reinforce(gate, dest, delta)` (route-weight update reusing the ADR-0007 kernel), and `gate_prune(gate)`. Represent each gate's table as a map from `XSIG_*` type to a small weighted destination list; store the coarse content vector with `core/similarity.nova` for content matching. Seed rules are a static table loaded at startup. Mark the `XSIG_CONST` route immutable.

`DEPENDS ON: NOVA enhancement #7 — learned, content-based gate routing tables atop core/channel.nova (filtered/weighted channels).` Reinforcement reuses `DEPENDS ON: NOVA enhancement #12 — Hebbian + error-driven plasticity kernels` (same update applied to route weights). Broadcast fan-out across millions of signals uses `DEPENDS ON: NOVA enhancement #4 — SIMD/GPU batched signal propagation`.

Testing: `fixture_gate_seed` asserts seed rules deliver `XSIG_SENSORY`→perception and `XSIG_CONST`→all parts on tick 0 with no learning; `fixture_gate_learn` rewards a route and asserts its weight rises and an unrewarded route decays/prunes; `fixture_gate_const_immutable` attempts to down-weight the constitutional route and asserts it cannot change (gate to ADR-0045). Honors NO-LLM-COGNITION: routing is pure substrate. Depends on ADR-0008 (signal types/priority) and ADR-0007 (plasticity kernel); feeds ADR-0010, ADR-0024, ADR-0043, ADR-0045.
