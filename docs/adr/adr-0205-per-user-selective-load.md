# ADR-0205: Per-User Selective Load

## Status

Proposed. Names the third consumption mode — same mother, per-user
overlay that projects only opted-in capsules, skills, patterns, and
personas — as a first-class deliverable alongside mother-daemon-
direct (mode 1) and baked-child (mode 3). Adds the `user.preference`
verb family, composes the existing ownership overlay
(`src/sandbox/ownership.nova`) and persona registry, and draws a
clean line between USER OPT-IN (soft, runtime-mutable) and OPERATOR
ASSIGNMENT (hard, from R70 auto-assignment). No re-baking, no
per-user process.

## Date

2026-08-22

## Context

ADR-0200 enumerates five consumption modes. Modes 1 (mother-daemon-
direct) and 3 (baked-child) are the operator-driven shapes: the
enterprise picks what a user gets. Mode 5 (embedded) is long-horizon.
Modes 2 and 4 are user-facing. Mode 4 is the client app front-end
(desktop / web / mobile) — a shell around the wire.

Mode 2 is different. It says: one deployment, many effective models,
without re-baking. The same mother serves every user, but each user
sees only the parts they opted in to. A legal analyst who opts in to
the case-law capsule and the citation-checker skill sees a legal-
tools view of the mother; a finance analyst who opts in to the
regulatory-comment capsule and the periodicity-summarizer skill sees
a finance-tools view; both are talking to the same daemon.

The primitives that make this possible already exist:

- `src/sandbox/ownership.nova` — the per-user overlay that gates
  visibility of capsules, skills, patterns, personas.
- Persona registry — projections attach per user (ADR-0102).
- R70 operator-assignment — the mother's operator can hard-assign a
  user to a set of ownership rows (a "role" pattern).

What is missing is a soft-assignment layer where the user themselves
opts in to items on top of what the operator assigned. Today the
overlay is populated only by the operator's assignments; a user
cannot self-project onto an item the operator did not authorize
first.

The distinction matters. An operator hard-assigns a user to the
`legal_case_law` capsule because compliance says so; that assignment
must not be user-removable. A user soft-selects the `citation_
checker` skill because they find it helpful; that selection must be
user-removable (and re-selectable) without an operator round-trip.
Both signals live in the overlay; only the source and the removal
policy differ.

## Decision

### The `user.preference` verb family

Three new wire verbs, all callable with a `user_preference` capability
token:

- `user.preference.set{name, kind}` — opts the caller into a
  capsule, skill, pattern, or persona by name. Adds an overlay row
  tagged `source: user_soft`.
- `user.preference.list{}` — returns the caller's overlay
  membership, tagged by source (`operator_hard` versus
  `user_soft`).
- `user.preference.clear{name, kind}` — removes a `user_soft`
  overlay row. Refuses to remove a row tagged `operator_hard`.

The verbs are per-caller. `caller_holder` is derived from the
capability token in the standard way; the verbs operate on the
caller's overlay, never someone else's.

### Soft versus hard sources

Every overlay row now carries a `source` field:

- `operator_hard` — populated by R70 operator assignment. Only
  operator (`admin` tier) can add or remove.
- `user_soft` — populated by `user.preference.set`. Caller can
  self-remove via `user.preference.clear`.

An overlay row can only be one source; the operator setting a row a
user had soft-selected replaces the source with `operator_hard` (and
locks it against user removal). The user setting a row the operator
had hard-assigned is a no-op (the row is already there and stronger).

### Overlay evaluation

The ownership visibility check remains
`ownership_visible(reg, kind, name, holder)`. Its return value is
still binary (visible or not visible). The `source` field only
governs mutation policy, not visibility; a row is visible if it
exists, regardless of source.

### No re-baking

The critical property of this mode: adding or removing a user's
preference does not require a bake, a snapshot, or a daemon restart.
The overlay is a live mutation on the mother's process state,
persisted via the existing overlay snapshot path (R55.x).

### Preference UX

Preference management is a client-app concern (mode 4). The client
lists available capsules / skills / patterns / personas via the
existing `capsule.list` / `skill.list` / `pattern.list` verbs
(which the daemon can enrich with an `available_but_not_installed`
flag when the caller is in this mode), and calls
`user.preference.set` / `.clear` in response to user action.

### Interaction with child-mode

A baked child (ADR-0204) inherits the `--child-mode` posture, which
disables `capsule.install` / `skill.install` / `pattern.install` but
does NOT disable `user.preference.*`. Users on a deployed child can
still self-select from the bundle's allowlist. The child's allowlist
becomes the outer envelope; user preferences pick a subset within.

## Consequences

### Positive

- Users tailor their experience without operator involvement. The
  operator ships the outer envelope (what is allowed); the user
  picks from it. Reduces operator ticket load.
- One deployment serves many personas. An enterprise licenses one
  mother; every user gets a personalized effective view without a
  per-user bake.
- Composes existing machinery. The overlay is R55.x; the persona
  substrate is ADR-0102; the wire is the daemon's normal wire. The
  only new code is the three verbs and the `source` field.
- Auditable. The overlay row source distinguishes user choice from
  operator assignment; a compliance audit can enumerate both.
- Reversible. Users can experiment (turn on, turn off) without a
  round-trip.

### Negative

- Users can hide themselves from operator visibility. A user
  soft-selecting a preference for a skill the operator would rather
  they not use is a real UX and policy question. Mitigation: the
  operator sets `operator_hard` denials that the user cannot
  override; or the operator disables `user.preference` capability
  entirely for a role.
- Requires a preference-management UX in the client. Not a huge
  build but non-zero.
- Preference persistence lives on the mother. A user with an
  intermittent connection to the mother sees stale preferences
  until they reconnect and re-fetch.

### Neutral

- The `source` field is a small additive schema change on the
  overlay. Backfill: old rows without a source are treated as
  `operator_hard` (the safe default).
- Operator can revoke a soft preference at any time (by adding an
  operator-hard denial). User self-service does not undermine
  operator authority; it just reduces the routine load on it.

## Alternatives Considered

1. **Bake per user (rejected).** Would give per-user isolation but
   at bake cost. Enterprises with thousands of users cannot bake
   thousands of children per week.

2. **Client-side preference (rejected).** Store preferences in the
   client app; the daemon serves everyone the full view. Would
   push access-control into the client, which is untrustworthy.

3. **User preferences are just capability tokens with narrower
   grants (partial, not sufficient).** Capability tokens govern
   verb access; the overlay governs item visibility. Both layers
   are needed; user preferences are the item-visibility layer.

4. **Merge soft and hard into one source (rejected).** Would let
   users clear operator assignments, which defeats the point.

5. **Ship without this mode; let operators bake per-persona
   children (rejected).** Would work but is the exact tax this mode
   removes. Multi-persona bakes are perfectly reasonable for
   distinct populations; per-user is where per-user selective load
   wins.

## See Also

- ADR-0200 — Five consumption modes; this is mode 2.
- ADR-0102 — Persona substrate; the projection layer this mode
  operates on.
- ADR-0203 — Bake pipeline; contrast with the hard-bake mode 3.
- ADR-0204 — Slim runtime; children still support this mode within
  their allowlist.
- ADR-0209 — Deployment form factors; enumerates all five modes.
- R70 — Operator auto-assignment (the hard source).
- R55.x — Ownership overlay and its persistence.
- `src/sandbox/ownership.nova` — `ownership_visible` and the row
  schema.
