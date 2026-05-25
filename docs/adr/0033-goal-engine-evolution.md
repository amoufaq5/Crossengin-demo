# ADR-0033: Goal engine evolution (existing 4 drives + long-horizon persistence + sub-goal trees + cross-session continuity)

## Status

Proposed

## Date

2026-05-25

## Context
`core/goal.nova` provides a goal engine with 4 base drives (the motivational substrate that produces SIG_GOAL_DRIVE signals, ADR-0008). For a desktop companion that exhibits initiative and pursues multi-day/multi-week objectives, four reactive drives are not enough. The system needs to (a) decompose abstract goals into actionable sub-goals, (b) keep goals alive across process restarts and long stretches of user inattention, and (c) resume coherently in the next session — "yesterday you asked me to learn X; I made progress on the sub-task Y." Without this, CrossEngin is reactive, not self-directed, and fails the long-horizon-goals and initiative capability tests (ADR-0049).

The constraints are real: a single-user desktop app (ADR-0046) is frequently closed and reopened; the user gives intermittent attention. So goal state must survive snapshots (ADR-0048) and rehydrate in the correct order. With 2 founders bootstrapping over 18-30 months, we extend the existing 4-drive engine rather than replace it, and we lean on already-decided persistence machinery rather than inventing a parallel store.

This decision is needed now because goals are the spine of agency: self-learning triggers (ADR-0026) create goals, imagination (ADR-0032) evaluates them via scenarios, the action loop executes them, and emotion (ADR-0035) appraises moments *against* them. The goal data model (tree shape, persistence fields) must be settled before these integrate. ADR-0040 covers the persistence mechanics specifically; this ADR defines the engine evolution that produces the goals to persist.

## Decision
We evolve `core/goal.nova` along three axes while preserving the 4 drives. (1) **Keep the 4 drives as the motivational root.** Drives remain the source of intrinsic motivation, emitting SIG_GOAL_DRIVE (and interacting with SIG_CURIOSITY, ADR-0008) that bias which goals are spawned and prioritized. (2) **Sub-goal trees.** A goal becomes a node in a tree (`goal_new` with parent/children fields, plus `status` ∈ {active, blocked, satisfied, abandoned}, `priority`, `deadline`, `progress`, and a `provenance` link to the moment/drive that spawned it). Decomposition is performed by reasoning means-ends strategy `reason_means_ends` (ADR-0031) and validated by scenario imagination (ADR-0032). A parent's progress is a rollup of its children; satisfaction propagates upward; blocking propagates a SIG_GOAL_DRIVE re-prioritization. (3) **Long-horizon persistence + cross-session continuity.** Goal trees are part of the snapshot set (ADR-0048) and rehydrate after soul, before episodic — so on restart the engine reconstitutes active trees, re-anchors them to episodic context, and the perception/goals loops resume the highest-priority unblocked leaf. A `last_touched` timestamp and decay let stale goals lose priority gracefully without being deleted, supporting multi-week objectives under intermittent attention (the detailed mechanics are ADR-0040).

## Options Considered
- **Flat goal list, no hierarchy (rejected).** Keep goals as a priority queue over the 4 drives. Simplest extension. Rejected because real objectives ("help me prepare for the board exam over 6 weeks") are inherently decomposable; without trees the system cannot track partial progress, resume mid-task, or explain structure to the user — failing long-horizon and self-awareness tests.
- **External planner / task framework (rejected).** Adopt a classical HTN/STRIPS planner bolted onto the engine. Powerful decomposition. Rejected: it reintroduces an orchestration layer outside the substrate (against ADR-0001), duplicates means-ends reasoning we already get from ADR-0031, and is heavy for 2 founders to build and maintain.
- **Goals as ordinary atoms in a KG, no dedicated engine (rejected).** Represent goals like any knowledge atom. Elegant and uniform. Rejected because goals need active scheduling, deadline/priority dynamics, and drive-coupling that the passive KG/atom lifecycle doesn't provide; we'd end up rebuilding the engine inside the KG.
- **Evolve the 4-drive engine with sub-goal trees + persistence (CHOSEN).** Preserves the working motivational core, adds exactly the structure (trees) and durability (snapshots) needed, and reuses ADR-0031 reasoning and ADR-0048 persistence. Best fit for the constraints.

## Consequences
- **Positive:** Genuine long-horizon agency — multi-day/week goals survive restarts and intermittent attention; partial progress is visible and explainable (feeds ADR-0038 self-model API); decomposition reuses existing reasoning. Drives keep behavior intrinsically motivated rather than purely task-driven.
- **Negative:** Tree state is now critical persisted state — a corrupt or mis-ordered rehydration (ADR-0048) can resurrect stale or contradictory goals; needs validation on load. Priority/decay tuning is delicate: too aggressive and long goals die, too slow and the queue clogs. Cross-session re-anchoring depends on episodic memory being healthy (ADR-0022).
- **Future work:** Conflict resolution between competing sub-goals and between drives; goal vetoes from the override layer (ADR-0044) must prune trees safely. Enterprise v2 (ADR-0047) needs per-tenant goal isolation. Tighter loop with theory-of-mind (ADR-0039) so user-state changes re-prioritize trees.

## Implementation Notes
- Files: extend `core/goal.nova` with tree fields on `goal_new` (parent, children, status, priority, deadline, progress, provenance, last_touched) and accessors/mutators; rollup and propagation helpers (`goal_rollup_progress`, `goal_propagate_block`).
- Decomposition calls `reason_means_ends` (ADR-0031); validation calls `imagine_scenarios` (ADR-0032). Drives emit SIG_GOAL_DRIVE (ADR-0008).
- Persistence: include goal trees in the snapshot set; rehydrate order soul -> KGs -> episodic with goals re-anchored to episodic on load (detailed in ADR-0040, format in ADR-0048).
- Testing: decomposition fixtures (abstract goal -> expected sub-tree); restart test asserting active trees rehydrate and the correct leaf resumes; decay test over simulated multi-day gaps; veto/prune test against ADR-0044.
- `DEPENDS ON: NOVA enhancement #10` — substrate snapshot + ordered rehydration (soul -> KGs -> episodic) so goal trees survive restarts. `DEPENDS ON: NOVA enhancement #6` — extended signal tags for SIG_GOAL_DRIVE prioritization.
