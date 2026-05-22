# ADR-0010: Visionary layer — probabilistic simulation and dreams

## Status

Accepted

## Context

The Visionary module is the brain's simulator. It imagines: what could happen, what might go wrong, what the user might need next, what an action's downstream consequences could be. It is distinct from the Cognitive module's fast heuristic consequence predictor (ADR-0009) — the Visionary layer runs longer-horizon, probabilistic scenario rollouts when there is latency budget for them, or in idle time when the agent is not actively responding.

The user has stated that "dreaming" and "simulation" should be the same mechanism. Both are directed scenario rollouts; the distinction is the trigger (user-asked = simulation; idle-spontaneous = dreaming) and the framing (simulation produces an answer to a question; dreaming produces tagged events that the rest of the brain can use opportunistically). Dreams must not silently rewrite ground truth — they are imagined, and downstream consumers need to know they are imagined.

Three design choices structure the Visionary layer:

1. **Representation.** Neural rollout (model continues generating into the future), symbolic plan tree (search over discrete possibilities), or probabilistic graphical model (variables, conditional dependencies, inference)?
2. **Trigger policy.** When does the Visionary layer run?
3. **Containment.** How are imagined outputs distinguished from real ones, and what is allowed to depend on them?

## Decision

**Representation: probabilistic graphical model of causes and effects.** A Bayesian-network-style structure where nodes are typed variables drawn from the academic knowledge graph and the user's memory graph, and directed edges encode conditional dependencies (cause → effect, with conditional probability tables or learned parameters where data supports them).

This representation supports:

- Direct inference queries ("given these observations, what is the probability that this outcome occurs?").
- Counterfactual rollouts ("if the user does X instead of Y, what does the distribution over outcomes look like?").
- Composability with the graph-of-vectors substrate (ADR-0005) — the Bayesian network's nodes are the same kind of typed entities used elsewhere.

**Library choice (v0): permissively-licensed Bayesian-network library.** Candidates: NumPyro (Apache 2.0, JAX-backed), PyMC (Apache 2.0, well-maintained, broad ecosystem), pgmpy (MIT, lighter weight, graph-first). v0 default: **PyMC**, on the grounds of broad ecosystem and Apache 2.0 license. Reassessed at M5 (ADR-0022) once the actual inference workload is profiled.

**Triggers:**

- *Idle time.* When the agent has no active user interaction and no pending cognitive work, the Visionary layer may run rollouts seeded by short-term memory contents and anticipated events.
- *Short-term memory content.* Contents tagged as "open question," "unresolved possibility," or "pending decision" in working memory seed rollouts.
- *Anticipated events.* Future events on the agent's calendar of expected occurrences (e.g., a known user appointment, a predicted external event) seed rollouts for preparation.
- *User-asked simulation.* The cognitive module can request a rollout for a specific question. This shares the same mechanism as idle-spontaneous dreaming; only the trigger and the consumption pattern differ.

**Unification rule: dreams and simulations are the same mechanism.** Both produce events from a directed scenario rollout over the probabilistic graph. The output schema is identical. The trigger metadata distinguishes them in audit logs.

**Output schema for rollout-derived events:**

- Each event is a `MemoryItem` (per ADR-0006) with `type = 'dream'` (or `'simulation'`).
- `meta.imagined = true` is mandatory.
- `meta.prediction_value` — the probability-weighted predicted outcome.
- `meta.cautiousness_value` — a calibrated measure of how cautious the agent should be given the spread of imagined outcomes (high spread or high-magnitude downside → high cautiousness).
- `meta.preparedness_value` — what the agent has learned to do or have ready in case the imagined outcome occurs.

**Containment rules:**

- *Dreams do not modify the academic graph.* The academic knowledge base is updated only by the preprocessing pipeline (ADR-0008), never by dream output. A dream that "discovers" a new fact does not get to assert it.
- *Dreams do not modify the soul.* The Soul layer's values, behavior, and constitutional gate are not mutated by dream content.
- *Imagined-tag propagation.* Every output that traces back to a dream carries `imagined = true` through the consuming pipeline. The cognitive module's action-selection logic checks the imagined-tag before treating a memory item as a basis for action — imagined items are usable for *planning* but not for *asserting* facts to the user.
- *Successful imagined plans become tentative memory.* When a dream-rollout produces a plan that the cognitive module ends up actually executing, the imagined plan is stored as temporary memory with `imagined = true`. When the real execution completes and reflection produces an outcome, the temporary memory is either consolidated into long-term memory (with imagined-tag removed and real-outcome metadata added) or discarded based on the outcome.

## Consequences

Positive: the probabilistic graphical-model representation matches the kind of reasoning Visionary is meant to do — uncertainty-aware, multi-outcome, queryable about likelihoods. The imagined-tag discipline gives the rest of the brain a clean separation between "this happened" and "this might happen," which is the load-bearing safeguard against hallucination. The unified dream/simulation mechanism simplifies the architecture — there is one rollout engine, not two.

Negative: probabilistic-graphical-model inference is computationally non-trivial. Idle-time dreaming consumes compute and energy whose budget needs explicit governance (especially on per-user deployments, per ADR-0015). Building and maintaining the cause-effect graph (which variables, which dependencies, which conditional parameters) is its own engineering effort; v0 covers a narrow slice (medicine + per-user patterns) and grows incrementally.

Neutral: hallucination is the intended mode of the Visionary layer ("what conflicts might arise?" is the question dreaming is meant to ask). The containment rules are what make this safe.

## Alternatives considered

**Neural rollout** (a generative model continues generating sequences into the future). Rejected: opaque, hard to constrain to actually probabilistic outputs (model expresses confidence poorly), incompatible with the graph-of-vectors structural primitive in ADR-0005.

**Symbolic plan tree alone.** Already used by the Cognitive module's fast predictor (ADR-0009). Insufficient for Visionary's job — does not represent uncertainty, does not produce probability-weighted outcomes.

**Separate dream and simulation engines.** Rejected by the user's unification directive; would also duplicate the rollout machinery without architectural benefit.

**Dreams allowed to write to academic graph (i.e., learning from dreams).** Rejected. The risk of corruption is too high. If a dream produces a useful insight, the path is for the cognitive module to act on it, produce an outcome, and the resulting real memory then participates in normal knowledge-update flows (ADR-0007). Dreams never directly assert.

## Open questions

- Concrete schema for the cause-effect graph's variables and dependencies in the medicine domain. Initial v0 scope: a small set of variables around a single sub-domain (matching the v0 evaluation in ADR-0022). Final schema at M5.
- Cadence and compute budget for idle-time dreaming. Per-user deployment context (ADR-0015) bounds this — we cannot run dreams continuously for every user without compute cost concerns. Heuristic for v0: dreaming runs at most N minutes per user per day, capped, with budget enforced at the deployment layer.
- Inference algorithm: exact (where feasible) vs MCMC vs variational. PyMC supports all three; choice depends on the network size and the latency requirements. Decided per workload at M5.

## References

- ADR-0005 (Knowledge representation) — the graph-of-vectors substrate Visionary's variables are drawn from.
- ADR-0006 (Memory architecture) — where imagined-tagged items live.
- ADR-0008 (Academic knowledge) — the source of cause-effect variables relevant to v0's medicine domain.
- ADR-0009 (Cognitive module) — the fast predictor Visionary coexists with.
- ADR-0011 (Soul values governance) — Visionary outputs pass through the constitutional gate before becoming actions.
- ADR-0015 (Deployment topology) — per-user compute budget for dreaming.
- ADR-0019 (Licensing posture) — Apache 2.0 / MIT filter on the Bayesian-network library.
- ADR-0022 (Evaluation and milestones) — M5 Visionary integration milestone.
