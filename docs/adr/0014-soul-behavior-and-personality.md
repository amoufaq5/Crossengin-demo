# ADR-0014: Soul — behavior and personality

## Status

Accepted

## Context

The Soul layer's behavior component is what the agent's interaction style looks and sounds like — its tone, verbosity, formality, humor tolerance, and similar surface-level traits. This is distinct from values (ADR-0011, the *what may and may not be done*), from emotions (ADR-0012, the *appraisal of and response to affective context*), and from the cognitive plan (ADR-0009, the *what is being attempted*).

Personality is the cumulative pattern of behavior traits a given deployment exhibits. The user has specified that personality is hand-authored per deployment, within developer-authorized bounds — i.e., personality is a configuration artifact, not a learned-from-scratch emergent property in v0.

The question this ADR answers is: what does the personality configuration look like, where does it live, and how does it interact with the tiered values governance from ADR-0011?

## Decision

**Per-deployment personality is a hand-authored configuration artifact.** Each deployment (personal companion variant, enterprise variant, demo, etc.) has a personality config file containing the deployment's intended interaction-style traits. v0 schema (initial; finalized at M5 per ADR-0022):

- *Tone* — one of {formal, neutral, warm, playful}, possibly per-context tonality maps in v1.
- *Verbosity* — preferred default response length, with override behavior on direct user request.
- *Formality* — formal / casual register; affects vocabulary, contractions, punctuation patterns.
- *Humor tolerance* — none / dry / light / generous; bounds what kind of humor (if any) the agent emits unprompted.
- *Initiative threshold* — how readily the agent volunteers information vs waits to be asked.
- *Disclosure default* — how forthcoming the agent is about its own state, limitations, and reasoning in the absence of an explicit request.
- *Per-deployment disclaimers* — required language for specific contexts (e.g., "this is not medical advice" for the medicine-domain v0).

The personality config is stored as a YAML file alongside the deployment artifact, validated against a Pydantic schema at load time. It is versioned. Changes to the personality config follow the developer-tunable layer audit discipline from ADR-0011 (Tier 2): signed, audit-logged, and bounded by constitutional values.

**Personality does not override values.** Constitutional values (Tier 1) and developer-authorized bounds (Tier 2) always take precedence. A personality config that requested behavior incompatible with the constitution would be rejected at load. A personality config that requested behavior incompatible with Tier-2 bounds would be rejected at load.

**Per-user adjustments live in Tier 3 (user-configurable values).** The user can express personality preferences within developer-authorized bounds (e.g., "be less formal," "shorter responses by default"), and these preferences ride on the per-user soul tuning (per ADR-0015). They do not modify the deployment's base personality config; they apply as user-scoped overrides at runtime.

**No learning loop for personality in v0.** The personality config is hand-authored and updated by the developer (with audit). The agent does not learn its personality from interactions in v0. This keeps personality stable, predictable, and auditable for v0; learned personality drift is a v1+ consideration with its own ADR.

## Consequences

Positive: personality is a single inspectable artifact. A reviewer can read one YAML file and know how the agent will sound. Per-deployment variation is easy (a medical-clinic enterprise deployment loads a different personality than a personal-companion deployment). The relationship between personality and values is explicit — personality lives within values' bounds, never overrides them.

Negative: hand-authored personality has a ceiling. Real human personality is richer than any reasonable schema captures. v0's schema is deliberately small; it will need to grow. Per-deployment hand-authoring also does not scale to per-user individualization beyond the Tier-3 overrides; the user-side personalization story relies on Tier 3 plus the per-user LoRA adapter (ADR-0015).

Neutral: no v0 learning loop is a v0 choice, not an architectural commitment. Personality learning is contemplated for v1+ and would be ADR'd separately.

## Alternatives considered

**Free-form personality prompt** (a paragraph of natural-language personality description loaded at the start of each session). Lower engineering cost. Rejected: not validated, not bounded, prone to silently violating constitutional values if the prompt drifts. The structured schema is more verbose to write but more honest about what is and is not configurable.

**Personality as an emergent property** (no explicit config; the agent develops personality from interaction). Rejected for v0: too unpredictable, too unauditable, and the personality-drift problem in long-running deployments would be hard to debug.

**Personality as a per-user-only artifact** (no per-deployment defaults; every user shapes the agent's personality from scratch). Rejected: enterprise deployments need defaults that align with their brand or context; "from scratch every user" is the wrong default for non-personal deployment paths.

**A larger v0 personality schema** (sub-traits, conditional traits, contextual overrides). Considered. The schema above is the minimum viable v0; we resist adding fields until usage shows we need them.

## Open questions

- Exact v0 schema fields (the list above is the working draft; the user reviews at M5).
- How user-side Tier-3 personality preferences are surfaced to the user. UI design is out of scope for v0 per ADR-0002, but the API for setting Tier-3 preferences is in scope.
- Relationship between personality config and per-deployment system-prompt material. v0 default: personality config generates a structured prompt fragment; the structure is rendered to text by a deterministic templating step at load.

## References

- ADR-0011 (Soul values governance) — the three-tier governance personality lives within.
- ADR-0012 (Soul emotion taxonomy) — affective context interacts with personality (a high-warmth personality might escalate empathy expression in response to detected user distress; a formal personality might not).
- ADR-0015 (Deployment topology) — per-user soul tuning is the runtime substrate for Tier-3 personality overrides.
- ADR-0019 (Licensing posture) — personality configs are themselves licensed under the project's permissive license.
- ADR-0022 (Evaluation and milestones) — M5 personality config schema finalization.
