# ADR-0096: Machine-learning policy (online local learning yes, LLM/frozen-model cognition no)

## Status

Proposed

## Date

2026-06-15

## Context
ADR-0014 forbids LLM cognition, and it is frequently over-read — by the team under
time pressure and by outside readers — as "CrossEngin uses no machine learning at
all." That is false, and the falsehood is dangerous in both directions: it invites
people to either (a) bolt on a frozen deep model "because we said no ML anyway, so
what's one more exception," or (b) reject principled statistical learning the
system genuinely depends on. The system in fact learns continuously and uses a
specific family of learning algorithms: per-atom **Bayesian** belief updating
(ADR-0023), **Hebbian + error-driven synaptic plasticity** (enhancement #12),
**predictive coding + three-factor learning** (enhancement roadmap P2), a
backprop-free **Forward-Forward representation learner**
(`src/learning/forward_forward.nova`, P2), and **HDC/VSA hyperdimensional
embeddings** (ADR-0051). The substrate itself is a network of nodes and plastic
synapses — so "no neural networks" was never the actual principle.

The expansion (ADR-0086) raises the stakes. The debate engine (ADR-0089), the
formal path (ADR-0088), and governed self-update (ADR-0092) all touch learning,
and "could we just train a model for this step?" will recur on each. ADR-0014
answers it for LLMs specifically; this ADR generalizes the ruling to *all* of ML
by stating the criteria that separate the learning we permit from the learning we
forbid, so the question has one authoritative answer instead of being re-litigated
per feature.

## Decision
We permit a **bounded family of learning algorithms defined by three properties**,
and forbid everything outside it. A learning technique is permitted only if it is:

1. **Online and local** — it learns continuously from experience via local update
   rules, rather than by offline batch optimization that bakes knowledge into a
   frozen artifact. The substrate gets smarter by rewiring and reweighting as it
   runs (ADR-0003 synapse-first growth), not by a separate training phase that
   produces a fixed model.
2. **Explainable and traceable** — its updates produce named, inspectable state
   (atoms, synapses, Beta beliefs, HDC vectors) that the decision log (ADR-0043)
   can audit, so any learned change can be explained and reversed (ADR-0044,
   ADR-0025).
3. **Substrate-compatible** — it runs within substrate dynamics on the tick budget
   (ADR-0037, ADR-0003) as cheap, bounded computation, not as an external
   black-box inference call.

**Permitted (the current family):** Bayesian belief updating (ADR-0023); Hebbian
and error-driven plasticity (#12); predictive coding / three-factor learning (P2);
the Forward-Forward representation learner (P2) — chosen precisely *because* it
learns representations **without global backpropagation**; HDC/VSA embedding and
similarity (ADR-0051). New techniques are admitted only by passing the three
criteria above.

**Forbidden:** any **LLM or large pre-trained model in the cognition path**
(reaffirms ADR-0014); any **offline-trained frozen deep model substituted for a
cognitive capability** (it is opaque, cannot learn online, and breaks the audit
trail); **end-to-end global backpropagation as the cognition mechanism** (the
substrate learns locally, not by a global gradient over a monolithic network).

**The deciding test:** *would using technique X make a capability unauditable, or
unlearnable online, or dependent on a frozen external artifact?* If yes, it is
forbidden, no matter how powerful. Backprop is not banned as arithmetic in some
isolated, clearly non-cognitive offline tool, but it is never the mechanism of
cognition and any such use must not breach the ADR-0014 boundary or the audit
requirement.

## Options Considered
- **"No ML at all — pure symbolic" (rejected).** Clean slogan, but false to what is
  built and self-defeating: Bayesian beliefs and synaptic plasticity *are* learning,
  and forbidding them would kill the continuous-learning thesis that distinguishes
  CrossEngin from a frozen model. It also misframes the substrate, which is itself a
  learning network.
- **"Anything goes if it helps, including deep nets/LLMs" (rejected).** Collapses
  straight into an ADR-0014 violation: opaque, unauditable, unlearnable-online
  cognition. This is the exact failure the whole project exists to avoid.
- **"Allow offline-trained neural nets but not LLMs" (rejected).** A frozen
  offline-trained net is still opaque and cannot learn online; the LLM ban is a
  special case of a broader problem (frozen black-box cognition), so drawing the
  line at "LLM" specifically leaves the hole open.
- **Permitted family by explicit online/explainable/substrate criteria (CHOSEN).**
  Names what we use, gives a reusable test for new techniques, and protects the
  three things that must hold together — continuous learning, explainability, and
  the no-LLM principle. Cost: the line needs judgment at the margin.

## Consequences
- **Positive:** Ends the "no ML" ambiguity with a precise, defensible ruling;
  protects continuous learning, explainability, and the no-LLM boundary
  simultaneously; gives a single criterion for evaluating any future learning
  technique; legitimizes the local-learning algorithms the roadmap already commits
  to (P1/P2) without opening the door to frozen models.
- **Negative:** "Online and local enough" is a judgment call at the margin (e.g.
  some representation learners blur the line), so borderline techniques need a
  recorded acceptance note; we deliberately forgo the raw capability of large
  pre-trained models, paying in cold-start coverage exactly as ADR-0014 already
  accepted.
- **Future work:** A per-technique acceptance ledger (technique → which criteria it
  meets → decision); revisit only if a *provably* auditable, online use of a larger
  model is demonstrated — the bar is the three criteria, not novelty.

## Implementation Notes
- This ADR is enforced alongside the ADR-0014 no-LLM-cognition CI guard (#14): the
  static check that the only path into `runtime/llm.nova` is STT/TTS, plus a review
  checklist for any new learning module — *online? explainable/audited?
  tick-budget? not a frozen external artifact?*
- Permitted techniques map to existing/planned modules: `core/belief.nova`
  (Bayesian, ADR-0023); `src/substrate/synapse_graph.nova` plasticity (#12);
  `src/parts/reasoning/predictive_coding.nova` (P2); `src/learning/forward_forward.nova`
  (P2); `src/kg/hdc_embed.nova` (ADR-0051, P1).
- Testing: the existing no-LLM-cognition verification (ADR-0014) remains the hard
  gate; add an assertion that learning updates emit inspectable state to the
  decision log (ADR-0043), demonstrating the explainability criterion.
- DEPENDS ON: no new NOVA enhancement; references #12 (plasticity kernels), #4
  (batched propagation for the learners), and the #14 bridge isolation that backs
  the LLM prohibition.
