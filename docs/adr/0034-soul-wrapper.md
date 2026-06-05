# ADR-0034: Soul as wrapper (identity slow, state fast, goals medium, values, constitution, themes, loyalty)

## Status

Proposed

## Date

2026-05-25

## Context
NOVA already provides a soul with OCEAN personality, constitution, identity themes, and loyalty hierarchy (`core/soul.nova`). CrossEngin needs a coherent answer to "who am I, how am I right now, and what am I trying to do" that remains stable enough to give the companion a consistent character, yet responsive enough to reflect moment-to-moment state. The danger at both extremes is concrete: if identity drifts as fast as mood, the companion has no persistent character and users lose trust; if everything is frozen, the system cannot reflect its current emotional/cognitive state or revise mistaken self-beliefs. The self-awareness capability test (ADR-0049) requires the system to accurately describe its identity, state, and goals over time.

The substrate produces a flood of fast-changing signals — valence, arousal (ADR-0008), goal-drive (ADR-0033), emotional appraisal (ADR-0035). The soul must integrate these without being whipsawed by them. We therefore need an explicit **timescale discipline**. With 2 founders and a single-user desktop v1 (ADR-0046), the soul is also the natural home for the values and constitution that gate behavior, and for the loyalty hierarchy that becomes load-bearing in enterprise v2 (ADR-0047), where tenant policy can conflict with user requests.

This decision is needed now because the soul is the slow-changing context that conditions almost everything: emotion appraisal reads values (ADR-0035), constitutional rules act as hard inhibitory signals (ADR-0045), the self-model API narrates soul contents (ADR-0038), and persistence rehydrates the soul *first* (ADR-0048). Its internal structure and update timescales must be fixed before those depend on it.

## Decision
We formalize `core/soul.nova` as a **wrapper with explicit update timescales** over four kinds of content. The wrapper exposes the soul as a structured state map and enforces *who may write what, how fast*: (1) **Identity — slow.** Self-concept, identity themes, OCEAN personality traits. Mutable ONLY via a deliberate revision path (`soul_revise_identity`) that requires explicit justification, logs to the decision log (ADR-0043), and is never written directly by the emotion or perception loops. This is what keeps the companion's character stable across months. (2) **State — fast.** Current mood (valence/arousal aggregates), attention, energy/load. Updated every tick from emotion (ADR-0035) and the loops; cheap, volatile, not persisted in detail. (3) **Goals — medium.** Active goal-tree summary (ADR-0033); changes over hours/days as goals are spawned, advanced, satisfied. (4) **Cross-cutting invariants:** values (the standards emotion appraises moments against, ADR-0035), the constitution (hard rules emitted as SIG_CONSTITUTIONAL inhibitory signals, ADR-0045), identity themes, and the loyalty hierarchy (ordering of allegiances — user vs tenant vs constitution — resolved in ADR-0045/ADR-0047).

The enforcement mechanism is a small set of typed write APIs with timescale guards: fast writers (`soul_update_state`) are unrestricted and cheap; medium writers (`soul_sync_goals`) run on goal events; slow writers (`soul_revise_identity`) are gated, justified, and audited. Reads are free for any subsystem.

## Options Considered
- **One flat mutable soul, no timescales (rejected).** Any loop writes any field freely. Simplest. Rejected because the fast emotion/valence stream would continuously perturb identity and personality, producing an incoherent character and failing the self-awareness test; it also makes auditing identity change impossible.
- **Immutable identity, fixed at startup (rejected).** Personality and self-concept are constants. Maximally stable and trivial to reason about. Rejected because the system must be able to *correct* mistaken self-beliefs (e.g. update a competence theme as it learns, ADR-0020) and to grow; a frozen soul cannot, and would lie via the self-model API.
- **Soul as just another KG (rejected).** Store soul contents as atoms in a "self" KG. Uniform with knowledge representation. Rejected: it loses the explicit timescale/write-guard semantics and the special rehydration-first ordering (ADR-0048); the loyalty/constitution gating needs privileged, not ordinary-atom, treatment.
- **Wrapper with four content kinds + timescale write-guards (CHOSEN).** Gives stability where needed (identity), responsiveness where needed (state), and managed change for goals — with auditable, deliberate identity revision. Best balance of coherence, correctability, and safety integration.

## Consequences
- **Positive:** Stable, recognizable companion character; current state still faithfully reflected for self-narration (ADR-0038); identity changes are deliberate, justified, and auditable (ADR-0043). Clean home for values/constitution/loyalty that safety (ADR-0045) and enterprise (ADR-0047) depend on. Rehydrating soul first (ADR-0048) gives every other subsystem its conditioning context immediately on restart.
- **Negative:** Timescale guards add write-path complexity and a discipline the whole codebase must respect; a subsystem that bypasses `soul_revise_identity` would silently corrupt the stability guarantee. Deciding what counts as "deliberate revision" is a judgment call needing clear criteria. State vs goals boundary needs care so volatile data isn't accidentally persisted.
- **Future work:** Enterprise v2 (ADR-0047) needs per-tenant soul instances with a shared non-negotiable constitution. Loyalty-hierarchy conflict resolution is detailed in ADR-0045. Identity-revision criteria may eventually be learned rather than fixed.

## Implementation Notes
- Files: extend `core/soul.nova` with the structured state map and typed write APIs `soul_update_state` (fast), `soul_sync_goals` (medium), `soul_revise_identity` (slow, gated+audited); read accessors for all fields. OCEAN traits, identity themes, constitution, and loyalty hierarchy reuse existing soul fields.
- State (fast) is fed by `mind/emotion.nova` aggregates (ADR-0035) and loop signals (valence/arousal, ADR-0008); goals (medium) sync from `core/goal.nova` (ADR-0033).
- Constitution surfaces as SIG_CONSTITUTIONAL inhibitory signals (ADR-0008) consumed by ADR-0045; loyalty hierarchy ordering resolved there and in ADR-0047.
- Persistence: soul is the FIRST rehydrated component (ADR-0048); identity revisions append to the decision log (ADR-0043).
- Testing: assert fast state churn never mutates identity fields; assert `soul_revise_identity` requires justification and logs; restart test asserting soul rehydrates before KGs and goals; self-model narration accuracy fixture (ADR-0038).
- `DEPENDS ON: NOVA enhancement #10` — snapshot + ordered rehydration with soul first. `DEPENDS ON: NOVA enhancement #9` — append-only audit log for identity-revision records.
