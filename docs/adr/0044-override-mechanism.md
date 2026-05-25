# ADR-0044: Override mechanism (belief edit, goal veto, hard stop, kill switch)

## Status

Proposed

## Date

2026-05-25

## Context
An autonomous, continuously-learning substrate will sometimes be wrong: it will hold a mistaken belief, pursue a goal the user disapproves of, get stuck in a runaway loop, or simply need to be stopped now. The user must retain final authority at every level — this is both a trust requirement for the v1 companion (ADR-0046) and a hard requirement for the v2 enterprise pilot (ADR-0047). The decision log (ADR-0043) tells the user *what* happened and *why*; the override mechanism is how they *intervene*. Without graded intervention, the only recourse is to kill the process, which is destructive and discards learned state.

This must be decided now because each override hooks a different core module — `core/belief.nova`, `core/goal.nova`, the action loop, and the runtime — and those interfaces should be designed before the loops are wired (ADR-0036). The 2-founder constraint means overrides must be a thin, well-defined set, not an open-ended admin console.

## Decision
We define four override mechanisms, graded from surgical to total, all surfaced to the user through the same inspection surface as the decision log (ADR-0043) and self-model API (ADR-0038):

1. **Belief edit** — the user corrects a specific atom's confidence. Implemented as a privileged write to the Bayesian belief on that atom in `core/belief.nova` (alpha/beta counts): the override sets or pins alpha/beta (e.g. force a near-certain or near-zero belief), emitted as a `SIG_CORRECTION` so downstream nodes update. Edits are logged (ADR-0043) and may be marked "pinned" so ordinary plasticity (ADR-0023) cannot drift them back.
2. **Goal veto** — the user cancels or forbids a goal/sub-goal in `core/goal.nova`. Vetoing marks the goal node `GOAL_VETOED`, prunes its sub-goal tree, and parks any actions blocked on it (ADR-0041 `PERM_APPROVE` queue). A veto can be one-shot or standing (a standing veto becomes a constraint the goal engine will not regenerate).
3. **Hard stop** — immediately halt all in-flight and queued *actions* (the action loop) while leaving the substrate alive (perception/memory/reasoning keep running). This is the "stop what you're doing" control: it flips a `safety_halt` flag that `safety_gate` checks, draining `NTYPE_ACTOR` outboxes without executing them.
4. **Kill switch** — terminate the process. A clean kill triggers an ordered snapshot (soul -> KGs -> episodic, ADR-0048) so state survives; a panic kill (double-trigger) skips the snapshot for true immediacy. The kill switch is always available and never gated.

These are mediated by `core/safety.nova`, which exposes them as explicit operations and (except panic-kill) records each as an appended decision-log entry.

## Options Considered
1. **Kill switch only (rejected).** Trivial and unmistakably safe, but maximally destructive — every correction means losing the session and all unsaved learning. It also gives no way to fix a *specific* wrong belief without nuking everything. Insufficient alone; retained as the last of four.

2. **Single generic "undo last action" control (considered, rejected as the whole mechanism).** Intuitive and pairs naturally with ADR-0042's `undo_fn`s. But many problems aren't a single action — they're a wrong *belief* or a misguided *goal* that will keep generating bad actions. Undo treats symptoms, not causes. We keep per-action undo (via ADR-0042) but it is not the override mechanism. Rejected as sole solution.

3. **Full read/write admin console over substrate state (rejected for v1).** Maximum control. But exposing arbitrary writes to nodes/synapses/atoms is dangerous, unauditable, and far beyond 2-founder capacity to build safely; arbitrary edits could corrupt the substrate. Rejected; the four targeted overrides cover the real needs.

4. **Four graded overrides — belief edit / goal veto / hard stop / kill switch (CHOSEN).** Each targets a distinct causal level (belief, intention, in-flight action, existence), all auditable, all small and well-scoped. Matches how things actually go wrong. Chosen.

## Consequences
- **Positive:** The user can intervene at the right granularity instead of only at the extremes; belief edits and goal vetoes fix root causes durably; hard stop gives instant safety without data loss; kill switch is an always-available backstop. All overrides are logged, preserving the audit chain (ADR-0043).
- **Negative:** Privileged writes into `core/belief.nova` and `core/goal.nova` bypass normal learning, so a careless user could pin wrong beliefs or over-veto and degrade the system; we mitigate by logging and by letting pins be un-pinned. Hard stop's "substrate alive but actions frozen" state is a new mode that all action-originating code must respect.
- **Future work:** Standing vetoes feed the constitutional layer (ADR-0045) as soft constraints; enterprise (ADR-0047) restricts who may belief-edit vs goal-veto via the loyalty hierarchy; an "explain then offer override" flow built on ADR-0038.

## Implementation Notes
`core/safety.nova` exposes `override_belief_edit(atom_ref, alpha, beta, pin?)`, `override_goal_veto(goal_ref, standing?)`, `override_hard_stop()`, `override_kill(panic?)`. Belief edit calls a privileged setter in `core/belief.nova` and emits `SIG_CORRECTION` (ADR-0008); pinning sets a flag the plasticity path (ADR-0023) honors. Goal veto sets `GOAL_VETOED` on the `core/goal.nova` node and prunes children. Hard stop sets a `safety_halt` flag checked at the top of `safety_gate` (ADR-0041); `NTYPE_ACTOR` `node_drain_outbox` discards instead of dispatching while halted. Kill uses `runtime/syscall.nova`; clean kill invokes the ordered snapshot of ADR-0048 (enhancement #10). All overrides except panic-kill append to the decision log (ADR-0043, enhancement #9). Controls surface via the self-model/inspection UI (ADR-0038) with pure-substrate rendering (ADR-0013) — no LLM. Tests: assert a pinned belief survives subsequent plasticity ticks; assert a standing veto prevents goal regeneration; assert hard stop drains without executing any effector; assert clean kill produces a rehydratable snapshot and panic kill exits immediately.
