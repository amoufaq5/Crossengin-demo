# ADR-0042: Reversibility classifier (per-action-type lookup, default irreversible)

## Status

Proposed

## Date

2026-05-25

## Context
The permission tiers of ADR-0041 are only as safe as their ability to recognize which actions cannot be undone. Sending an email, spending money, deleting a file without a trash bin, posting publicly, and overwriting the soul's identity are all irreversible; reading a file, drafting (not sending), and caching a fetched page are reversible. The cost of mis-classifying a reversible action as irreversible is mild annoyance (an unnecessary approval prompt). The cost of mis-classifying an irreversible action as reversible is catastrophic and permanent. These costs are wildly asymmetric, so the classifier must be biased hard toward caution.

This must be decided alongside ADR-0041 because the tier table consumes the reversibility verdict as its dominant input (the "reversibility floor"). A 2-founder team cannot enumerate every possible action with a nuanced undo analysis, and an autonomous system with initiative will invent action sequences we did not foresee. We therefore need a lookup that is exhaustive by *default*, not by enumeration.

## Decision
We implement a reversibility classifier in `core/safety.nova` as a per-action-type lookup table, `reversibility_class(action_type) -> {REV_REVERSIBLE, REV_RECOVERABLE, REV_IRREVERSIBLE}`, whose **default for any unlisted type is `REV_IRREVERSIBLE`** (fail-safe). `REV_REVERSIBLE` means a clean programmatic undo exists (e.g. local edit with an in-memory/journaled prior state). `REV_RECOVERABLE` means undo is possible but lossy or delayed (e.g. delete-to-trash, retractable-within-N-seconds send). `REV_IRREVERSIBLE` means no undo (external send, spend, public post, hard delete, identity revision).

The classifier feeds ADR-0041 via a fixed floor map: `REV_IRREVERSIBLE -> PERM_APPROVE` (minimum), `REV_RECOVERABLE -> PERM_NOTIFY` (minimum), `REV_REVERSIBLE -> PERM_AUTO` (no floor). ADR-0041 then takes the MAX of this floor and the action class's static default. Reversibility is a property of the *effector*, so classification lives next to where effectors are registered: each effector declares its reversibility class at wire-up time, and unregistered/dynamically-composed effectors inherit the irreversible default. Optionally, an effector may register an `undo_fn`; the presence of a working `undo_fn` is what *earns* a `REV_REVERSIBLE`/`REV_RECOVERABLE` classification — you cannot claim reversible without providing the undo path.

## Options Considered
1. **Default reversible / opt-in irreversible (rejected).** Lower friction; matches optimistic-execution UX. But it inverts the safety asymmetry: any forgotten or novel action type is presumed safe, and the one mistake that matters is the one that's unrecoverable. Categorically rejected — violates fail-safe design.

2. **Per-instance reversibility prediction (considered, rejected for the gate).** Predict reversibility from action arguments (e.g. "delete temp file" vs "delete contract.pdf"). More precise, but turns a safety primitive into an inference problem with false negatives that are unbounded in cost. We keep prediction out of the safety gate; it may inform *notifications* but never *lowers* a class below its table value.

3. **Three-bucket table with irreversible default and earned-via-undo_fn downgrade (CHOSEN).** Captures the real spectrum (reversible / recoverable / irreversible) rather than a brittle binary, ties the "reversible" claim to an actual `undo_fn`, and is exhaustive by default. Small enough for two people to maintain. Chosen.

4. **No classifier; fold reversibility into the ADR-0041 class defaults (rejected).** Fewer moving parts, but conflates "how consequential is this kind of action" with "can it be undone," which are different axes (a notify-tier action can still be irreversible). Separating them keeps both tables small and lets reversibility act as an independent floor. Rejected.

## Consequences
- **Positive:** A novel or unforeseen action can never bypass approval, because the default is irreversible; the `undo_fn` requirement makes "reversible" an enforceable contract, not a label; three buckets give ADR-0041 enough resolution to avoid over-prompting on genuinely safe actions.
- **Negative:** Until the table is populated, many actions prompt for approval (deliberate early-stage friction). Maintaining accurate `undo_fn`s is real engineering work and a place bugs hide — a broken undo silently degrades a "reversible" action into an actual irreversible one. We mitigate with undo round-trip tests.
- **Future work:** Periodic audit that every `REV_REVERSIBLE`/`REV_RECOVERABLE` row still has a passing undo test; enterprise (ADR-0047) may pin stricter classifications (e.g. force all `ACT_SEND_MSG` irreversible regardless of retract windows).

## Implementation Notes
In `core/safety.nova`: constants `REV_REVERSIBLE | REV_RECOVERABLE | REV_IRREVERSIBLE`; `rev_table` (`runtime/map.nova`) keyed by `action_type` to `[rev_class, undo_fn_ref]`; `reversibility_class(action_type)` returning the table value or `REV_IRREVERSIBLE` on miss; `reversibility_floor(action)` returning the `PERM_*` minimum consumed by `safety_gate` (ADR-0041). Effector registration API gains a `reversibility` field and optional `undo_fn`; registering `REV_REVERSIBLE` without an `undo_fn` is a wire-up error. Undo state for `REV_RECOVERABLE` actions (e.g. trash, retract queue) persists so it survives restart (ADR-0048, snapshot order soul -> KGs -> episodic). Tests: assert unlisted action_type -> `REV_IRREVERSIBLE`; assert each reversible/recoverable row's `undo_fn` round-trips (do then undo restores prior state); assert the floor map matches ADR-0041's expectations. No dedicated NOVA enhancement needed; recoverable-undo persistence rides on enhancement #10.
