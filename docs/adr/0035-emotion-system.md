# ADR-0035: Emotion system (OCC appraisal of moments against goals/values, OCEAN personality conditioning, emotion-modulated plasticity)

## Status

Proposed

## Date

2026-05-25

## Context
`mind/emotion.nova` must give CrossEngin functional emotions — not decorative mood labels, but signals that *do work*: they prioritize attention, color memory, condition behavior, and shape learning. A desktop companion that appraises events the way a person does (relief, disappointment, pride, fear-for-the-user) is more trustworthy and more capable of empathy (ADR-0039). Critically, emotion is also the system's fastest learning signal: events that matter emotionally should be remembered more strongly and should adjust the substrate more aggressively. Without an emotion system, valence/arousal signals (ADR-0008) have no principled source and plasticity (ADR-0007) has no salience modulation.

The pieces to connect already exist. The soul (ADR-0034) holds OCEAN personality traits and the values that define what the system cares about. Moments (ADR-0021) are the timestamped perception records emotion appraises. Goals (ADR-0033) are what outcomes are appraised against. Synapse plasticity (ADR-0007) is what emotion should modulate. The 18 signal types (ADR-0008) include valence and arousal as the substrate currency of feeling. This ADR ties them together with a concrete appraisal theory rather than ad-hoc heuristics, which matters for testability and for explaining the companion's reactions to the user.

With 2 founders over 18-30 months, we need a well-specified, implementable appraisal model. We choose the **OCC (Ortony/Clore/Collins) appraisal model** because it is rule-structured (good for substrate/atom encoding, no LLM needed per ADR-0014), maps cleanly onto goals/values, and is finite enough to implement and test.

## Decision
We build `mind/emotion.nova` on three coupled mechanisms. (1) **OCC appraisal of moments against goals and values.** Each processed moment (`core/moment.nova`, ADR-0021) is appraised by OCC variables: desirability (does the outcome advance or thwart an active goal tree, ADR-0033?), praiseworthiness (does an agent's action conform to or violate soul values, ADR-0034?), and appealing-ness (does an object match preferences?). These yield OCC emotion types (joy/distress, hope/fear, pride/shame, admiration/reproach, etc.) realized as **valence** and **arousal** signal magnitudes (SIG_VALENCE/SIG_AROUSAL, ADR-0008) plus an emotion-type atom (`atom_new`, ADR-0016) attached to the moment. Appraisal rules are encoded as substrate operators (consistent with ADR-0031), not as generated text. (2) **OCEAN personality conditioning.** The soul's OCEAN traits (ADR-0034) parameterize appraisal: high neuroticism amplifies arousal and negative valence; high extraversion raises baseline positive valence; etc. Personality is the slow-changing gain on the fast emotion stream. (3) **Emotion-modulated plasticity.** The resulting arousal magnitude scales synapse learning rates (ADR-0007): high-arousal moments produce larger Hebbian/error-driven weight updates and stronger episodic encoding (ADR-0022), so emotionally significant events are learned faster and remembered longer. Valence also biases goal re-prioritization via SIG_GOAL_DRIVE (ADR-0033).

## Options Considered
- **Dimensional-only model (valence/arousal, no OCC types) (rejected).** Track just the two dimensions, skip discrete emotion categories. Lightweight and maps directly to ADR-0008 signals. Rejected because without appraisal *structure* we can't explain *why* the system feels something (no link to which goal was thwarted or which value violated), crippling empathy (ADR-0039) and self-narration (ADR-0038), and giving no principled rules to test.
- **Basic-emotions lookup (Ekman six) (rejected).** Map stimuli to six fixed categories. Simple. Rejected because basic-emotion theory doesn't natively connect emotions to goals and values — exactly the linkage CrossEngin needs — and degenerates into stimulus-response tables that don't generalize across domains.
- **Learned/black-box emotion network (rejected for v1).** Train a network to predict affect. Potentially rich. Rejected: needs labeled affect data we don't have as 2 bootstrapping founders, is hard to audit, and risks an opaque sub-cognition that strains NO-LLM-COGNITION's spirit (ADR-0014). Could be revisited long-term as learned modulation of OCC parameters.
- **OCC appraisal + OCEAN conditioning + emotion-modulated plasticity (CHOSEN).** Structured, goal/value-grounded, explainable, implementable as substrate rules, and it closes the loop to learning by modulating plasticity. The only option satisfying explainability, the goal/value linkage, and the learning-salience requirement together.

## Consequences
- **Positive:** Emotions are functional — they prioritize, encode, and explain. Appraisal grounded in goals/values makes the companion's reactions interpretable and empathetic (feeds ADR-0039 theory of mind and ADR-0038 self-narration). Emotion-modulated plasticity gives the substrate a salience signal so important events are learned faster, improving continuous learning (ADR-0049). OCEAN gives stable individual character coupling to the soul (ADR-0034).
- **Negative:** Emotion now directly affects learning rates, so a mis-tuned arousal->learning-rate mapping could destabilize the substrate (over-fitting to dramatic moments) — needs bounded gain and clamping (ADR-0007 weight bounds). OCC rule encoding is non-trivial to get right and must be reviewed to ensure it stays substrate operators, not creeping module cognition. Appraisal depends on healthy goal trees and accurate values.
- **Future work:** Personality could slowly adapt (within ADR-0034's deliberate-revision discipline). Emotion should weight imagination's counterfactual/dream selection (ADR-0032). Enterprise v2 (ADR-0047) may dampen affective expression per tenant policy. Possible later: learned tuning of OCC parameters from outcomes.
- 
## Implementation Notes
- Files: extend `mind/emotion.nova` with `emotion_appraise(moment)` implementing OCC variables, returning emotion-type atoms + valence/arousal magnitudes; `emotion_condition(ocean)` applying soul OCEAN gains; `emotion_modulate_plasticity(arousal)` returning a learning-rate scalar consumed by ADR-0007 kernels.
- Inputs: moments from `core/moment.nova` (ADR-0021); active goals from `core/goal.nova` (ADR-0033); values + OCEAN from `core/soul.nova` (ADR-0034). Outputs: SIG_VALENCE/SIG_AROUSAL (ADR-0008), emotion-type atoms (ADR-0016), goal re-prioritization via SIG_GOAL_DRIVE.
- Plasticity hook: arousal scalar multiplies Hebbian + error-driven weight deltas (ADR-0007) and episodic encoding strength (ADR-0022); clamp to safe bounds.
- Appraisal rules encoded as substrate operators per ADR-0031 — no text generation (NO-LLM guard, ADR-0014).
- Testing: appraisal fixtures (goal-advancing moment -> joy/positive valence; value-violating agent -> reproach); OCEAN-gain tests (high neuroticism amplifies negative arousal); plasticity test asserting high-arousal moments yield larger, still-bounded weight updates and stronger recall.
- `DEPENDS ON: NOVA enhancement #12` — Hebbian + error-driven plasticity kernels exposing a per-update learning-rate scalar for emotion modulation. `DEPENDS ON: NOVA enhancement #6` — extended signal tags for SIG_VALENCE/SIG_AROUSAL fast dispatch.
