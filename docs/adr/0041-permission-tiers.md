# ADR-0041: Permission tiers (auto / notify / approve based on action class)

## Status

Proposed

## Date

2026-05-25

## Context
CrossEngin acts in the world. The action loop (ADR-0036) drives `NTYPE_ACTOR` nodes that emit `SIG_COMMAND` and `SIG_ORDER` signals down to motor effectors and external bridges: filesystem writes, whitelisted outbound HTTP fetches (ADR-0028), calendar/email integrations, and shell-like tool calls. An autonomous substrate with initiative and long-horizon goals (ADR-0033, ADR-0040) will originate actions the user never explicitly requested. Some are harmless (re-reading a cached page); some are consequential (sending a message, deleting a file). We cannot treat them identically, and we cannot ask the user to confirm everything — that destroys the companion experience.

This decision must be made now because the action loop is being built and `core/safety.nova` must wrap every effector call before any external integration ships in v1. The constraint is a 2-founder team that cannot maintain a hand-curated approval rule for thousands of action instances, and cannot afford a learned/probabilistic gate whose mistakes are unauditable. We need a small, deterministic, inspectable policy that defaults safe and degrades gracefully.

For v1 (single-user desktop, ADR-0046) the user IS the authority. For v2 (enterprise pilot, ADR-0047) the same tiering must hold but the authority resolves through the soul loyalty hierarchy (ADR-0045). The mechanism must therefore be policy-data-driven, not hardcoded per deployment.

## Decision
We adopt three permission tiers — `PERM_AUTO`, `PERM_NOTIFY`, `PERM_APPROVE` — assigned per **action class**, not per action instance. Every outward action is tagged with an `action_class` symbol (e.g. `ACT_READ_LOCAL`, `ACT_WRITE_LOCAL`, `ACT_NET_FETCH`, `ACT_SEND_MSG`, `ACT_DELETE`, `ACT_SPEND`, `ACT_SELF_MODIFY`). A single classification table in `core/safety.nova` maps `action_class -> tier`. The gate function `safety_gate(action)` looks up the tier and: `PERM_AUTO` executes immediately; `PERM_NOTIFY` executes immediately but emits a `SIG_REFLECTION` to the user-facing notification channel and writes a decision-log entry (ADR-0043); `PERM_APPROVE` suspends the action, surfaces an approval request, and blocks the originating action sub-goal until the user responds (approve/deny/always-allow).

The tier for a class is computed, not arbitrary: it is the MAX (most restrictive) of (a) the static class default and (b) the reversibility floor from the reversibility classifier (ADR-0042). Irreversible classes are forced to at least `PERM_APPROVE` regardless of their static default. This makes the reversibility classifier the dominant safety input and keeps the table itself small (~20 classes for v1). An optional per-class **rate/scope refinement** (e.g. `ACT_NET_FETCH` is `PERM_AUTO` under the whitelist+rate-limit of ADR-0028, else `PERM_APPROVE`) is expressed as a guard predicate attached to the class row, evaluated at gate time.

## Options Considered
1. **Per-action-instance learned permission gate (rejected).** Treat permission as another learned routing decision (like ADR-0009 gates), training on user approve/deny feedback. Powerful and adaptive, but its decisions are non-deterministic and hard to audit; a single mis-generalization could auto-execute an irreversible action. For a safety boundary we require deterministic, inspectable behavior. Rejected for v1; revisitable as a *suggestion* layer that proposes table edits, never as the gate itself.

2. **Binary allow/deny with a global confirmation toggle (rejected).** Simplest to build. But it forces a false choice: either nag on everything or trust everything. It cannot express "do it but tell me," which is the most useful default for a companion. Rejected as too coarse.

3. **Capability tokens per integration (considered, partially adopted).** Grant the agent explicit capability tokens (filesystem-write, network, send) that the user mints. Strong isolation, but tokens gate *whether* an integration exists, not *when* a given use needs oversight — orthogonal to tiers. We keep capability scoping at the integration boundary (which effectors are wired at all) and layer the three tiers on top for runtime oversight.

4. **Three-tier class table with reversibility floor (CHOSEN).** Deterministic, tiny, inspectable, and policy-data-driven so v1 and v2 share code. Captures the auto/notify/approve spectrum the companion UX needs and binds the hardest cases to ADR-0042. Chosen.

## Consequences
- **Positive:** Deterministic, auditable safety boundary on every action; the common case (`PERM_NOTIFY`) preserves autonomy without silence; irreversible actions can never silently auto-execute because of the reversibility floor; one table serves desktop and enterprise.
- **Negative:** New action types must be classified before they ship, or they fall through to the default (we make the default `PERM_APPROVE` — fail safe), which can feel over-cautious until the table is tuned. Guard predicates add a little per-action cost on the action loop's hot path.
- **Future work:** A learned suggestion layer that proposes table refinements from approve/deny history (ADR-0023 belief tracking over per-class outcomes); enterprise admin-locked rows for v2 (ADR-0047); a UI for users to inspect and edit their tier table, tied to the override mechanism (ADR-0044).

## Implementation Notes
Add to `core/safety.nova`: tier constants `PERM_AUTO | PERM_NOTIFY | PERM_APPROVE`; `perm_table` as a `runtime/map.nova` keyed by `action_class` to a row `[default_tier, guard_fn, reversibility_ref]`; `safety_gate(action) -> decision` that computes `max_tier(default, reversibility_floor(action))` then dispatches. Actions are NOVA tag-prefixed values carrying `action_class` in their metadata, mirroring the `core/signal.nova` metadata-map idiom. `PERM_APPROVE` suspension uses the action loop's coroutine yield (`runtime/coroutine.nova`); the blocked sub-goal parks in `core/goal.nova` until resolved. Notifications and approval prompts are emitted as `SIG_REFLECTION` / `SIG_REQUEST` (ADR-0008) so output renders through pure-substrate generation (ADR-0013) — NO LLM. Every gate decision writes to the decision log (ADR-0043). The reversibility floor is the lookup defined in ADR-0042. Tests: a fixture table covering all ~20 classes; assert irreversible classes always resolve `>= PERM_APPROVE`; assert unknown class defaults to `PERM_APPROVE`; assert guard-predicate downgrade only ever *raises* the tier. No new NOVA enhancement strictly required; logging path uses NOVA enhancement #9.
