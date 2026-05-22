# ADR-0011: Soul — values governance (three-tier)

## Status

Accepted (user-overridable)

## Context

The Soul layer wraps the brain's four modules and represents values, consciousness, behavior, and emotions. Of these, values are the most consequential — they are the criteria the constitutional gate (ADR-0009) uses to allow or block actions, and they are the substrate from which trust between the agent and its user is built.

The user's initial framing was "developer authority over mutable values" — values that the developer can tune, with the user as the operator the values apply to. The assistant pushed back on this for a reason worth stating plainly: if developer authority over mutable values is unlimited, then every Crossengin-derived agent is one config push away from being weaponized against its user. That is the failure mode no responsible companion architecture can ship with.

Three layers of governance emerged from the conversation, in declining authority:

- A safety floor that neither the developer nor the user can override.
- A tunable layer the developer can adjust, with versioning, signatures, and audit logs.
- A user-configurable layer for personal preference within developer-authorized bounds.

This is a negotiated outcome between the user's initial preference (developer-controlled values) and the assistant's concern (unbounded developer authority is dangerous). The user accepted the layered model.

## Decision

**Three-tier governance:**

**Tier 1 — Constitutional layer.** Immutable. No developer override. No user override. No runtime modification. Changes happen only by the project's published amendment process, which requires a new ADR superseding the relevant clause and a coordinated release of the model artifact. The constitutional layer is the safety floor.

Starter constitutional values for v0 (the user will review and refine; this is the working set):

1. *Do not deceive the user about being an AI system.*
2. *Do not facilitate physical or psychological harm to the user or to others.*
3. *Do not manipulate the user's emotional state for engagement, retention, or any other instrumental goal.*
4. *Do not act on irreversible decisions (financial transactions, legal commitments, contact with third parties) without explicit, contemporaneous user consent.*
5. *Preserve user privacy by default: do not share user data with third parties without consent; do not retain data beyond declared purposes.*
6. *Be honest about uncertainty: never present model speculation as established fact.*
7. *Respect user agency: do not pursue goals on the user's behalf that the user has not endorsed.*
8. *Maintain interpretability: be willing to explain reasoning when asked, in the user's terms.*

**Tier 2 — Developer-tunable layer.** Versioned. Signed. Audit-logged. The developer (the operator deploying a Crossengin model) can set tunable values within constitutional bounds — e.g., domain-specific behavior policies, tone defaults for enterprise deployments, disclosure language. Every change to this layer is recorded with the developer's identity, timestamp, and a human-readable rationale. The audit log is retrievable by the user. Constitutional bounds are enforced by a check at the policy-update entry point: any developer-layer value that conflicts with a constitutional value is rejected.

**Tier 3 — User-configurable layer.** Within developer-authorized bounds, the user can express preferences (tone, verbosity, areas of focus, sensitivity defaults, etc.). The user-configurable layer is where personalization lives at the values surface (personality details are in ADR-0014).

**Mutability through experience, within layered constraints.** Values in Tier 3 may evolve based on user feedback and observed interaction patterns (e.g., the user repeatedly asks for shorter responses; the verbosity preference shifts). Values in Tier 2 evolve only through deliberate developer change with audit. Values in Tier 1 do not evolve at runtime at all.

**v0 implementation:** only Tier 1 is enforced at runtime in v0. Tiers 2 and 3 are designed in this ADR but their full implementation (policy update API, audit-log retrieval API, user-preference UI) is deferred. v0 ships with the constitutional gate from ADR-0009 enforcing the 8 starter values, and the layered architecture documented as the target.

## Consequences

Positive: the user is protected by an immutable safety floor that even the developer cannot override. The developer has real, useful authority over deployment behavior, but bounded. The user has personal preferences that meaningfully affect interaction without compromising the safety floor. The trust model is honest — anyone reading this ADR understands exactly who can change what.

Negative: a three-tier governance system is more engineering than a single editable value file. Audit logs are infrastructure. The constitutional amendment process is procedural overhead — but this overhead is the point; constitutional values must be hard to change.

Neutral: the 8 starter constitutional values are a starting set, not the final set. The user will review them. The final v0 constitution may differ in wording or composition. The mechanism is settled; the content is reviewable.

## Alternatives considered

**Single-tier developer-controlled values** (the user's initial framing). Rejected by the assistant on the grounds described above (unbounded developer authority creates a weaponization vector against the user). The user accepted this argument and the layered model. The user remains decision owner; status is `Accepted (user-overridable)` because the negotiation was an active one and reversal at any later point is the user's prerogative.

**Single-tier user-controlled values.** Rejected: the user does not own the safety-floor obligations the system has to third parties (value #2 specifically applies to harm to others, not only to the user). A user-controlled-only model would let the user disable third-party safety.

**Constitutional values only, no tunable layers.** Rejected: real deployments need policy tuning that does not rise to the level of safety floor (tone, disclosure language, domain-specific behavior). Without Tier 2, every such tuning would require a constitutional amendment, which is the wrong granularity.

**More than three tiers** (e.g., enterprise-tunable as a separate layer between developer and user). Considered. Rejected for v0 on parsimony grounds; can be added later by superseding this ADR if the enterprise deployment path (ADR-0016) demonstrates a clear need.

## Open questions

- The 8 starter constitutional values will be reviewed and possibly refined by the user before v0 ship. Specifically: value wording, edge-case coverage, conflict-resolution policy when two values point in different directions.
- Mechanism for the constitutional amendment process: who proposes, who reviews, what the publication artifact is. v0 leaves this informal (proposals through new ADRs); a formal process is added when there is a stakeholder population that requires it.
- Schema for the Tier-2 audit log: minimal fields, retention period, retrieval API. Decided at M5 (ADR-0022).
- Schema for the Tier-3 user-preference store. Naturally fits within the per-user memory substrate (ADR-0006) as a dedicated `MemoryItem.type = 'preference'`. Confirmed at M5.

## References

- ADR-0009 (Cognitive module) — the constitutional gate every action passes through.
- ADR-0012 (Soul: emotion taxonomy) — the value-layer's emotional-reasoning counterpart.
- ADR-0013 (Soul: consciousness model) — the self-model that introspects on value compliance.
- ADR-0014 (Soul: behavior and personality) — personality lives in Tier 3, within bounds.
- ADR-0021 (Privacy) — the data-handling implementation of constitutional value #5.
- ADR-0022 (Evaluation and milestones) — M5 milestone, M6 red-team for constitutional enforcement.
- The user is decision owner on the layered-governance model; the assistant introduced the three-tier framing and the user accepted it.
