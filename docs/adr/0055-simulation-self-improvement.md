# ADR-0055: Simulation environment + self-improvement (P5)

## Status

Proposed

## Date

2026-06-11

## Context

The agent had nowhere to practice and no way to get better on its own. There
was no sandbox world to act/plan in before acting for real, and no loop that
turns logged experience into improved behaviour — let alone a *safe* one. P5
closes the autonomy loop: a tickable world plus a bounded self-improvement
mechanism that learns only from the agent's own experience and routes any
self-change through the existing safety scaffolding.

## Decision

**Simulation (`src/sim/world_model.nova`).** A deterministic, tickable grid
micro-world. A cell is the state (a "moment", `world_state_id`); an action
(up/down/left/right) is an effector call; reaching the goal pays a reward, every
other step a small penalty (so shorter paths score higher). `world_step` advances
the real world; `world_peek` predicts `[reward, done, next_state]` WITHOUT acting
— the forward-simulation seam (imagine before committing). The same contract
extends to text/API/tool sandboxes later.

**Self-improvement (`src/parts/meta/self_improve.nova`).** The agent acts in the
world, logs each `(state, action, reward, next-state)` transition, and updates a
value estimate from it with a gradient-free temporal-difference backup (the world
is deterministic, so a full backup is value iteration). Exploration is seeded
epsilon-greedy with decay, so a run is reproducible and the goal is reliably
discovered; thereafter the greedy policy converges to the optimal path. The only
learning signal is the world's own reward — no human teaching.

**Bounded self-edit.** Reflection may PROPOSE a self-change (e.g. committing a
learned best-action as a rule). Every proposal is an `ACT_SELF_MODIFY` routed
through `constitutional_filter.safety_gate` (a constitutionally vetoed edit never
runs; APPROVE-tier edits require approval) and recorded in the hash-chained
`decision_log` (intent + outcome). So every self-change is gated, audited, and
tamper-evident — no unbounded self-rewrite.

## Options Considered

- **Grid micro-world (CHOSEN)** — the canonical, legible sandbox; states/actions/
  rewards map cleanly onto moments/effectors/appraisal. Text/bandit worlds fit the
  same `[reward, done, next_state]` contract and come later.
- **Full-update TD / value iteration (CHOSEN)** over a partial learning rate: with
  integer milli values a small `alpha * delta` rounds to zero, and the world is
  deterministic, so a full backup is correct and convergent.
- **Seeded epsilon-greedy exploration (CHOSEN)** over greedy-with-optimistic-init:
  the latter did not reliably reach the goal within the step budget (it could
  cycle deterministically); seeded epsilon-greedy guarantees discovery and stays
  reproducible.
- **Greedy before/after as the honest metric (CHOSEN)** over the in-training
  return (which is noisy because exploration is still on). We report the greedy
  policy's return before any learning vs after.
- **Reuse `constitutional_filter` + `decision_log` (CHOSEN)** — the roadmap says
  "use the scaffolding". The log is integer-only and hash-chained, so the edit
  *text* is vetted at the gate while the record carries the edit *id*.

## Consequences

- **Positive.** Acceptance met (measured): on a 5x5 grid the agent's greedy
  return rose from -200 (untrained, never reaches the goal) to 93 — the OPTIMAL
  8-step path — learning only from its own logged transitions; +293 improvement,
  converged by ~session 20. Self-edits are correctly bounded: a benign approved
  edit executes, an unapproved one suspends, a constitutionally forbidden one is
  vetoed, and all six log entries verify on the hash chain. The autonomy loop is
  closed and safe.
- **Negative / costs.** The world is a toy and the learner is tabular; the loop
  is demonstrated standalone, not yet driving the live agent.

## Honest gaps

- **Toy world, tabular learner.** The value table is one row per grid cell; large
  or continuous state spaces need function approximation. The HDC layer (P1) is
  the natural source of state features — a P1↔P5 tie left for future work.
- **TD, not the substrate's plasticity.** Learning here is Q-learning, not the P2
  three-factor / eligibility rule. A faithful integration would drive the value
  update via `XSIG_REWARD` → three-factor plasticity (the reward is already the
  world's, exactly what appraisal would feed); wiring that is the next step.
- **forward_sim is the `world_peek` seam, not the engine.** Predict-before-act is
  available, but the `imagination/forward_sim` pattern engine is not yet driving
  multi-step planning over the world.
- **Self-edit is gated + logged, not yet applied.** The proposal is vetted and
  audited, but actually minting the proposed rule atom into a live KG (and an
  automated undo) is represented by the audit record, not executed — reversibility
  is "the log records it", not a programmatic rollback yet.
- **Not in the live loop / not persisted.** Like P2/P4, the mechanism is not wired
  into `tick_driver`, and the learned value table is not snapshotted, so
  "across sessions" is demonstrated within a run rather than across process
  restarts (the persistence hook, ADR-0048, is the wiring point).

## Implementation Notes

- Integer-only throughout; exploration uses a seeded LCG via the overflow-safe
  `int_*` builtins. **NOVA gotcha:** a single-line multi-`let`
  (`let A=0 B=1 ...`) mis-parses the field indices — constants must be one per
  line (this caused an initial out-of-bounds before the fix).
- The decision-log entry is integer-only and hash-chained (`dl_hash_entry` does
  integer math on each field), so `si_self_edit` passes the edit *id* (int) as the
  logged goal and the edit *text* only to `const_veto_for`; this keeps `dl_verify`
  green.
- **Tests.** `test_world_model` (29: build/reset/step/wall/goal/peek-purity),
  `test_self_improve` (20: value table, TD backup, the across-sessions
  improvement acceptance, the bounded self-edit accept/suspend/veto + audit-chain
  verification), and `tests/benchmark/bench_self_improve.nova` (the optimal-path
  acceptance metric). Both modules are new and imported by nothing else; the
  existing suite (incl. `synapse_graph`, `decision_log`, `constitutional_filter`)
  stays green.
- **Next (P5 onward).** Drive the value update from the three-factor reward loop;
  use HDC state features; run `world_peek` through `forward_sim`; mint accepted
  self-edits as real rule atoms with rollback; persist the value table across
  sessions and drive the loop from `tick_driver`.
```
P1 HDC embeddings ─► P2 predictive coding + 3-factor ─► P3 ingestion/OpenIE
                                                              │
                        P5 sim + self-improve ◄── P4 agentic tooling
```
