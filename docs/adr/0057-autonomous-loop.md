# ADR-0057: The always-on autonomous loop (capstone)

## Status

Proposed

## Date

2026-06-11

## Context

ADRs 0051–0055 shipped the five roadmap phases and ADR-0056 wired the tractable
follow-ups, but those mechanisms were still opt-in or standalone. ADR-0056 named
the remaining frontier: "a single always-on autonomous loop … perception →
three-factor learning → goal-driven tool use → self-improvement every tick."
This ADR builds it — one cycle that runs all five phases together, so the
substrate is an agent, not a toolbox.

## Decision

`src/agent/autonomous_loop.nova`: `agent_new(seed)` assembles the whole stack
into one state object (a task world + value table, a synapse graph, a tool
registry + goal plan, a soul + decision log, a moment stream, an ingestion KG +
alias table, a skills KG, a seeded RNG). `agent_cycle(a, approved, now)` runs one
unified turn, and `agent_run(a, cycles, approved, reflect_every)` loops it and
reports metrics. Each cycle:

1. **Act + learn the task (P5).** A world episode under decaying-exploration;
   the value table updates from the world's reward (gradient-free TD). The
   episode return is the cycle's reward signal — the only teacher.
2. **Substrate plasticity (P2).** That reward neuromodulates a "task-value"
   three-factor synapse (eligibility from the cycle's co-firing × a broadcast
   neuromodulator from `pc_neuromod_scalar`), so the synapse strengthens as the
   agent succeeds.
3. **Act through tools (P4).** A goal-driven plan (search → compute → write)
   runs via `plan_execute_moments`: tools selected by competence, every call
   gated by the permission/reversibility layer, each result emitted as a moment.
4. **Ingest with entity resolution (P1 + P3).** The cycle's observation is
   OpenIE-extracted and each mention resolved to a canonical atom by HDC
   similarity before insertion, so repeated observations do not fragment the KG.
5. **Bounded self-improvement (P5 + safety).** Every `reflect_every` cycles the
   agent proposes a self-edit (adopt its learned policy as a rule), routed
   through the constitutional gate and the hash-chained decision log; it mints a
   rule atom only if accepted.

Everything is deterministic given the seed, so the agent's progress is
reproducible and measurable.

## Consequences

- **Measured (30-cycle run, `test_autonomous_loop`):** task return rose −100 →
  95 and the learned greedy policy reaches the **optimal** 6-step path (P5); the
  task-value synapse strengthened 0 → 65 under reward (P2); 90 moments emitted
  across the run (P4); ingestion held the KG at a stable handful of atoms despite
  30 repeated observations (P1 + P3); 3 self-edits were gated, approved, minted,
  and the audit chain verifies (safety). With approval withheld, **0** self-edits
  are accepted — the agent still learns its task but cannot change itself without
  sanction (the gate bounds the loop).
- All five phases now demonstrably run, compose, and stay safe inside one loop.
- Additive: `autonomous_loop.nova` is a new file imported by nothing else, so the
  entire existing suite is unaffected; the combined import set links with no
  symbol clashes.

## Honest gaps

- **Demonstration agent on a toy world.** The loop is real and unified, but the
  task is a 4×4 grid and the learner is tabular; scaling needs the HDC state
  features (seam present) feeding function approximation.
- **Two tracks, not yet one.** The world episode (the task) and the tool plan
  (the effector demonstration) run in the same cycle but are parallel — the tools
  are not yet the agent's task *actions*. Unifying them (tool calls ARE the moves)
  is the next refinement.
- **Its own loop, not the tick scheduler.** `agent_cycle` is a cycle, not yet a
  stage inside `tick_driver`'s per-tick scheduler; merging them (so the substrate
  tick and the agent cycle are one clock) remains.
- **No cross-restart persistence.** Agent state (value table, competence, KG,
  decision log) isn't snapshotted through ADR-0048 yet, so "always-on" is
  within-process. The reward is the world's, not yet appraisal over rich percepts;
  the live MCP transport is still simulated.

## Implementation Notes

- Imports the full stack (`self_improve`, `synapse_graph`,
  `predictive_coding_runtime`, `appraisal`, `tool_use`, `openie`,
  `entity_resolve`, `soul/state`); verified to compile and link with no symbol
  collisions. The three-factor pass is inlined from `synapse_graph` primitives
  (no `tick_driver` dependency). Deterministic given the RNG seed.
- HDC embed mode is enabled in `agent_new` (so ingestion resolves synonyms); the
  caller resets it afterward.
- **Tests.** `tests/unit/test_autonomous_loop.nova` (13 checks): the unified
  learn-and-stay-safe run, and the bounded-without-approval run. New file,
  imported by nothing, so all prior suites are untouched.
- **Next.** Make tool calls the task actions; fold `agent_cycle` into
  `tick_driver`; snapshot agent state for true cross-restart continuity; live MCP.
```
P1 HDC ─► P2 3-factor ─► P3 ingestion ─► P4 tooling ─► P5 self-improve
                                    └────────► ADR-0057 one autonomous loop ◄────────┘
```
