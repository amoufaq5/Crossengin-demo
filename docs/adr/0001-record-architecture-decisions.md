# ADR-0001: Record architecture decisions using ADRs

## Status

Accepted

## Context

Crossengin is a multi-module AI architecture (Memory, Cognitive, Academic Knowledge, Visionary, wrapped by a Soul layer) with a non-trivial number of cross-cutting design choices: representation paradigms, storage backends, governance models, licensing posture, deployment topology. Decisions made early will shape what is and is not buildable later, and the team is small enough that institutional memory cannot live solely in people's heads.

The project is also bootstrapped with a small team and an explicit intent to onboard contributors and, eventually, enterprise integrators. Anyone joining the project later needs to be able to read the rationale for past decisions without re-litigating them, and to understand which decisions were contested at the time so they know where to look for hidden assumptions.

Several existing lightweight processes for capturing this kind of context exist. The most widely adopted in software projects is the Architecture Decision Record (ADR) format introduced by Michael Nygard.

## Decision

We will record every significant architectural decision as an Architecture Decision Record, using the Michael Nygard format. ADRs live in `docs/adr/`, numbered sequentially as `NNNN-kebab-case-title.md`. Each ADR carries a status header (`Proposed`, `Accepted`, `Accepted (user-overridable)`, `Deprecated`, or `Superseded by ADR-NNNN`).

ADRs are immutable once accepted. Changing a decision happens by writing a new ADR that supersedes the old one — the old ADR's status is updated to `Superseded by ADR-NNNN`, and its body is left intact as a historical record.

A blank template lives at `docs/adr/0000-template.md`. An index lives at `docs/adr/README.md`.

For decisions where the user's chosen option diverged from the design assistant's recommendation during the initial design conversation, the status is `Accepted (user-overridable)` and the `Alternatives considered` section records both views with the user identified as decision owner.

## Consequences

Positive: future contributors can read the project's design history in one place. Contested decisions are visibly contested rather than smoothed over, which preserves honest signal for later reviewers. New ADRs cost little to write and are version-controlled.

Negative: ADRs are documentation, and documentation drifts unless maintained. The discipline of writing a new ADR rather than mutating an old one requires consistent reinforcement during code review. Numbering is a soft constraint; gaps will appear when proposals are abandoned.

Neutral: ADRs do not replace inline code comments, design docs, or RFCs. They are specifically for architectural decisions — choices that, if reversed, would require significant rework.

## Alternatives considered

**Free-form design docs in a wiki.** Lower friction to write, but suffers from the discoverability problem (which doc is canonical for a given decision?) and the rot problem (no convention for marking superseded docs).

**RFC-style proposals.** Heavier-weight, useful for decisions that need broad team review before acceptance. We may layer RFCs on top of ADRs later for proposals that need debate before they become accepted decisions, but the baseline record is the ADR.

**No formal record; rely on code, commits, and conversations.** Rejected for the reasons in the Context section — institutional memory in heads does not survive personnel changes or even long gaps in project activity.

## References

- Michael Nygard, "Documenting Architecture Decisions" (2011).
- The blank template at `docs/adr/0000-template.md`.
