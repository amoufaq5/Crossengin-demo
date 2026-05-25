# ADR-0030: Confidence thresholds for "learned enough" (test questions, multi-source agreement, user confirmation, all three)

## Status

Proposed

## Date

2026-05-25

## Context
A learning episode (ADR-0026) must terminate. Without an explicit "done" criterion the substrate would either stop as soon as it writes one atom (under-learning, leaving fragile half-knowledge) or keep fetching and asking indefinitely (over-learning, burning the ADR-0028 rate budget and the user's patience). We need concrete, measurable thresholds that declare a target concept "learned enough" to close the episode, mark its atoms as durable, and update the self-model competence estimate (ADR-0020).

The criterion must be auditable and grounded in mechanisms we already have: Bayesian confidence (alpha/beta, ADR-0023), source authority (tiers, ADR-0029), and user teaching/confirmation (ADR-0027). It must avoid an LLM-based "do I understand?" check (NO-LLM-COGNITION, ADR-0014) — the assessment is substrate-internal. It must also be cheap enough that two founders can implement and tune it, and bounded so episodes always halt.

Because different gaps carry different stakes, a single global threshold is wrong: a casual curiosity item and a safety-relevant medical fact should not require the same evidence. The decision must therefore scale the bar with the concept's importance.

## Decision
"Learned enough" is the conjunction of three checks, each with numeric thresholds; an episode closes only when all applicable checks pass (or a hard budget cap forces closure):

1. **Confidence/test-questions.** The episode's target atoms must reach Bayesian confidence with alpha+beta ≥ 12 and posterior mean ≥ 0.75 (`core/belief.nova`, ADR-0023). Additionally the system self-tests: it generates internal `SIG_QUESTION` probes via imagination (ADR-0032) that the new atoms should answer, and ≥ 80% must resolve to an atom above the spreading-activation salience floor (ADR-0012). This catches knowledge that is asserted but not actually reachable/usable.
2. **Multi-source agreement.** At least 2 independent sources of combined weight ≥ 1.0 (per ADR-0029 tiers — e.g., one Tier-A, or two Tier-B) must agree on the core claim, with no unresolved `contested` flag on the target atom. A single Tier-C source never satisfies this.
3. **User confirmation (conditional).** Required only for **high-stakes** concepts: those in safety-relevant domains, those that will drive an auto/notify action (ADR-0041), or those overturning a prior high-confidence atom. For these, an explicit user confirmation via ADR-0027 is mandatory before the atom is marked durable. For ordinary curiosity-driven learning, user confirmation is not required.

The bar **scales by stakes**: low-stakes curiosity items may close on checks 1+2 with the relaxed thresholds above; high-stakes items require all three plus a higher confidence floor (alpha+beta ≥ 20, mean ≥ 0.85). A **hard cap** guarantees termination: an episode is force-closed after 5 fetch attempts (ADR-0028) or 1 unsatisfied teach-request (ADR-0027); force-closed atoms are kept but marked `provisional` (low confidence, excluded from competence credit) and may be revisited by a later trigger.

On success the episode writes durable atoms, raises the ADR-0020 competence estimate for the concept/domain, emits a `SIG_REFLECTION`, and logs closure (ADR-0043).

## Options Considered
- **Single confidence threshold (e.g., alpha+beta ≥ 10).** Simple, one number. Rejected: confidence alone can be high from one biased source, and says nothing about whether the knowledge is actually retrievable or correct; no human check for high-stakes facts.
- **User-confirmation for everything.** Maximally safe. Rejected: unusable for autonomous curiosity learning and violates ADR-0027's question budget; the single user cannot ratify every learned atom.
- **Test-questions + multi-source agreement + conditional user confirmation, stakes-scaled, with a hard cap (CHOSEN).** Triangulates internal usability, external corroboration, and human sign-off where it matters, while guaranteeing termination. More moving parts and thresholds to tune, accepted as the cost of trustworthy autonomous learning.
- **Self-test questions only (no external corroboration).** Tests usability well. Rejected: an internally consistent but wrong belief passes; corroboration (check 2) is what guards correctness.

## Consequences
- **Positive:** Episodes terminate deterministically with knowledge that is corroborated, internally usable, and (for high-stakes items) human-confirmed; competence estimates (ADR-0020) only rise on genuinely consolidated knowledge; thresholds are explicit and auditable.
- **Negative:** Multiple thresholds (12/0.75, 20/0.85, 80%, weight ≥ 1.0) are tuning surface that may need per-domain adjustment; stakes classification adds a dependency on ADR-0041's action classes; the hard cap can leave useful-but-provisional atoms that never get promoted without a re-trigger.
- **Future work:** Learn thresholds from outcomes (did a "learned-enough" atom later get contradicted?); promote `provisional` atoms automatically when corroborating evidence arrives; tie self-test rigor to ADR-0049's capability benchmarks.

## Implementation Notes
- Closure logic in `mind/learning.nova` `episode_check_done(episode_id)` returning `{done, reason, provisional}`; reads confidence from `core/belief.nova` + `runtime/confidence.nova`, source weights/contested flags from ADR-0029, stakes class from ADR-0041.
- Self-test probes generated via `core/imagination.nova` (ADR-0032) as internal `SIG_QUESTION` signals routed through the Reader (ADR-0012); count resolutions above the salience floor.
- High-stakes user confirmation uses ADR-0027's explicit teach/confirm prompt; durable vs `provisional` recorded on the atom (ADR-0016).
- On closure, update ADR-0020 competence, emit `SIG_REFLECTION` (ADR-0008), and write a closure record to the decision log (ADR-0043).
- Test fixtures: low-stakes concept with 2 Tier-B agreeing sources and 85% probe pass (expect close on checks 1+2, competence raised); high-stakes medical concept without user confirmation (expect episode stays open); single Tier-C source (expect check 2 fail); exceed 5 fetches (expect force-close with `provisional` atoms, no competence credit).
- DEPENDS ON: NOVA enhancement #9 — audit log for episode-closure records. Uses existing belief/confidence/imagination primitives; no new outbound capability.
