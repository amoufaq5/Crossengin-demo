# ADR-0012: Soul — emotion taxonomy

## Status

Proposed

## Context

The Soul layer's emotion component represents the agent's interpretation of an interaction and its perception of the user's affective state (inferred from the user's words and behavior), and manifests in the agent's own behavior, tonality, and action selection. The user has specified a large list of emotions with sub-emotions and connections between them — i.e., a structured taxonomy rather than a flat label set. The specific taxonomy is open and this ADR is the place to choose one.

Four mature taxonomies have prior art in affective computing:

- **Plutchik's wheel** (1980). 8 primary emotions (joy, trust, fear, surprise, sadness, disgust, anger, anticipation) arranged in opposing pairs, with three intensity gradients each (e.g., serenity → joy → ecstasy). Dyads (combinations of adjacent primaries) define complex emotions (joy + trust = love, fear + surprise = awe). Pros: small, intuitive, opposing-pair structure aids relational reasoning. Cons: relatively coarse; cultural specificity baked into label choices.
- **OCC** (Ortony, Clore, Collins, 1988). 22 emotion types organized by appraisal: emotions are reactions to events (with respect to goals), to agents (with respect to standards), and to objects (with respect to attitudes). Pros: explicitly computational — each emotion type is a triggered response to a specific appraisal pattern, which maps cleanly onto a software event model. Cons: more classes to instrument; some categories require inference about social and moral norms.
- **Russell's circumplex** (1980). Continuous 2D space of valence (pleasant/unpleasant) and arousal (low/high). Pros: no commitment to discrete classes; smooth interpolation; well-validated in psychology research. Cons: loses categorical structure useful for explanation; harder to express "the user is feeling anxious" vs "the user is at valence -0.3, arousal +0.6."
- **Ekman's six basics** (1972, 1992). Anger, disgust, fear, happiness, sadness, surprise. Pros: smallest taxonomy with strong cross-cultural empirical support; widely used in facial-expression and voice-affect research. Cons: too coarse for the user's stated need for sub-emotions and connections; does not support the relational structure the user wants.

The user's stated requirement is "a large list with sub-emotions and connections." That requirement disqualifies Ekman's six basics as the sole taxonomy (too small) and rules out Russell's circumplex as a sole representation (continuous, no discrete sub-emotions). It points toward Plutchik (structured, small primary set with explicit dyads and intensity gradient) or OCC (large set, hierarchical by appraisal triggers).

## Decision (proposed)

**v0 emotion taxonomy: OCC's 22 emotion types as the categorical backbone, layered with Plutchik-style primary/secondary relations for the small subset of emotions where Plutchik's dyads are computationally useful.**

Rationale:

1. **OCC is appraisal-based.** Each OCC type is defined by what triggers it — a specific appraisal of an event, agent, or object. This maps directly onto the Cognitive module's event model and the constitutional-gate's reasoning. "The user is feeling `pride`" (OCC: approving an agent's praiseworthy action, where the agent is the user themselves) has a software-event meaning the agent can reason about; "the user is feeling `joy`" (Plutchik primary) has only a label.
2. **OCC's hierarchy fits "sub-emotions and connections."** The 22 types group into 6 super-categories: well-being (joy, distress), prospect-based (hope, fear, satisfaction, fears-confirmed, relief, disappointment), fortune-of-others (happy-for, gloating, pity, resentment), attribution (pride, shame, admiration, reproach), attraction (love, hate), and well-being / attribution compounds (gratification, gratitude, remorse, anger). This is the "list with sub-emotions and connections" the user described.
3. **Plutchik's dyad logic stays useful for the small set of emotions where it adds something** (e.g., the agent recognizing a user's `awe` as `fear + surprise`-like rather than as one of OCC's appraisal types). Plutchik supplements, does not replace.
4. **Russell's circumplex is also kept as a continuous projection** — the OCC type is the categorical label, but the underlying valence/arousal scores are computed and stored alongside, useful for the agent's tonality and action-selection reasoning where continuous gradation matters more than categorical class.

**v0 implementation scope:** The agent recognizes and reasons about a defined subset of the 22 OCC types in v0 — exact subset finalized at M5 (ADR-0022). Likely starting subset: the well-being pair (joy, distress), prospect-based pair (hope, fear), and the attribution quartet (pride, shame, admiration, reproach), since these are the types most relevant to a personal-companion context and the easiest to attest with limited training data. The remaining 14 OCC types are deferred but the taxonomy is in place to receive them.

**Status: Proposed**, not Accepted. The user has explicitly delegated the research-and-recommend step to this ADR; the user reviews and ratifies before status changes to Accepted.

## Consequences

Positive: OCC's appraisal-based structure gives the cognitive module a clean computational handle on emotion — every emotion has a triggering pattern that the cognitive module can detect. The hierarchical structure satisfies the user's "sub-emotions and connections" requirement. Russell's valence/arousal projection provides continuous gradation where useful. The v0 subset is small enough to instrument and evaluate.

Negative: OCC has more classes than Ekman or Plutchik, which means more training data needed to recognize each. Some OCC types require social-norm inference (e.g., `reproach` requires a sense of what counts as a blameworthy action) that is heavier than v0 needs for the medicine-domain personal companion. The hybrid (OCC + Plutchik supplement + Russell projection) is more complexity than a single-taxonomy commitment.

Neutral: this is a starting taxonomy. Cross-cultural emotion taxonomies and culture-specific calibrations are out of scope for v0 but contemplated for v1.

## Alternatives considered

**Plutchik only.** Cleaner, smaller, intuitive opposing-pair structure. Rejected because OCC's appraisal grounding maps better onto the Cognitive module's event model. Plutchik may serve as v0's working primary set if implementation cost makes the OCC subset too heavy — revisitable.

**OCC only, no Plutchik supplement, no Russell projection.** Simpler. The Plutchik supplement and Russell projection add real value in specific cases (dyad-like complex emotions; continuous gradation in tonality). Keeping them is cheap. Removing them is a future cleanup decision if usage doesn't materialize.

**Ekman's six basics.** Rejected: too coarse for the user's stated requirement.

**Russell's circumplex only.** Rejected: loses categorical structure useful for explanation and for emotion-conditioned action selection.

**Custom taxonomy** (build a Crossengin-specific taxonomy from scratch). Rejected for v0: no empirical grounding, no prior art to borrow from, large cost for unclear benefit. The room to deviate from established taxonomies is a v1 conversation once we have observed where the chosen taxonomy is insufficient.

## Open questions

- Final subset of OCC types implemented in v0. Initial proposal: well-being pair, prospect-based pair, attribution quartet (8 types). User ratification needed.
- Whether the emotion taxonomy is the same for "agent's inferred reading of user's affective state" and for "agent's own represented emotional state." Initial assumption: same taxonomy, different instances. To be confirmed by the user.
- Concrete mapping from OCC types to action-selection effects (e.g., when the agent infers user `distress`, how does that change action-selection?). Designed at M5 (ADR-0022).
- Cross-cultural calibration is out of scope for v0; needs an ADR in v1.

## References

- Plutchik, R. (1980). *Emotion: A Psychoevolutionary Synthesis.*
- Ortony, A., Clore, G. L., & Collins, A. (1988). *The Cognitive Structure of Emotions.*
- Russell, J. A. (1980). *A Circumplex Model of Affect.*
- Ekman, P. (1992). *An Argument for Basic Emotions.*
- ADR-0009 (Cognitive module) — event model that OCC appraisal types map onto.
- ADR-0011 (Soul values governance) — value layer that emotion-conditioned actions still pass through.
- ADR-0013 (Soul consciousness model) — self-model that tracks the agent's own emotional state.
- ADR-0014 (Soul behavior and personality) — tonality and personality affected by emotion state.
- ADR-0022 (Evaluation and milestones) — M5 for the implementation of the v0 OCC subset.
