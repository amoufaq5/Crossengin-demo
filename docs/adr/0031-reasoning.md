# ADR-0031: Reasoning (hybrid: substrate atoms for inferential operators + module functions for complex multi-step strategies)

## Status

Proposed

## Date

2026-05-25

## Context
CrossEngin must reason — chain causes, draw implications, transfer structure by analogy, weigh evidence — without ever invoking an LLM as cognition (ADR-0014). The substrate thesis (ADR-0001) says intelligence emerges from node/synapse/signal dynamics, not from orchestrated modules. Yet pure substrate spreading activation alone is poor at deliberate, auditable multi-step inference (e.g. a five-step differential diagnosis, or a proof-like chain the user can inspect). We need both the fast, parallel, learned reasoning of the fabric and the structured, replayable strategies a desktop companion can explain.

The relevant signal vocabulary already exists: ADR-0008 defines causal, implicative, analogical, and evidential signal types among the 18. These are the inferential currency of the substrate. The question this ADR settles is WHERE inference lives: in the fabric (as atoms and signal dynamics), in `mind/reasoning.nova` (as explicit strategy functions), or both. With 2 founders at 8h/day bootstrapping toward an 18-30 month v1, we cannot afford a fully emergent reasoner that we cannot debug, nor a purely symbolic engine that contradicts the substrate architecture and cannot learn.

The decision must be made now because reasoning sits on the critical path: self-learning triggers (ADR-0026), predictive coding (ADR-0024), goal decomposition (ADR-0033), and emotion appraisal (ADR-0035) all consume reasoning outputs. Their interfaces depend on whether reasoning emits atoms, function returns, or both.

## Decision
We adopt a **hybrid reasoning architecture**. (1) *Inferential operators live as substrate atoms.* A causal link, an implication, an analogical mapping, and an evidential weight are each represented as atoms (`atom_new`, ADR-0016) stored in a dedicated reasoning KG, carrying Bayesian confidence (alpha/beta, `core/belief.nova`). Reasoner nodes (`NTYPE_REASONER`) fire SIG_CAUSAL/SIG_IMPLICATIVE/SIG_ANALOGICAL/SIG_EVIDENTIAL signals along synapses; co-firing strengthens the operator weight (ADR-0007). This is fast, parallel, learned, and integral to the fabric — single-step inference is just signal propagation. (2) *Complex multi-step strategies are explicit functions in `mind/reasoning.nova`.* Named strategies — `reason_forward_chain`, `reason_abductive`, `reason_analogical_transfer`, `reason_evidential_combine`, `reason_means_ends` — orchestrate the substrate: they seed the relevant first nodes, run bounded propagation, harvest activated operator atoms, and assemble a trace. Crucially these functions do NOT compute the inference themselves; they *sequence and gate* substrate operations and record each step into the signal `trace` field (`core/signal.nova`) so the decision log (ADR-0043) can replay it.

The boundary rule is: **single inferential steps are substrate; the deliberate selection and chaining of steps is a module function.** A strategy function never hard-codes domain facts — those always come from atoms. This keeps NO-LLM-COGNITION intact: every conclusion is a substrate-derived atom with provenance, never generated text.

## Options Considered
- **Pure emergent substrate reasoning (rejected).** Let multi-step inference arise solely from recurrent spreading activation and learned gates (ADR-0009). Most faithful to ADR-0001 and requires no strategy code. Rejected for v1: deliberate chains (diagnosis, planning) would be non-deterministic and nearly impossible to debug or explain to a single desktop user, and would take far longer than 18-30 months to train to reliability with 2 founders. We keep it as a long-term direction (see Future work).
- **Pure symbolic inference engine (rejected).** A classical forward/backward chainer with a rule base in `mind/reasoning.nova`. Auditable and quick to stand up. Rejected because it divorces reasoning from the learning fabric: rules wouldn't strengthen via Hebbian/error-driven plasticity, couldn't carry alpha/beta confidence naturally, and would duplicate the KG. It also drifts toward an orchestration architecture ADR-0001 explicitly refused.
- **LLM-assisted reasoning (rejected outright).** Use the NOVA LLM bridge to propose inference steps. Fastest to demo. Rejected as a direct violation of ADR-0014/NO-LLM-COGNITION; the bridge is STT/TTS-only (enhancement #14).
- **Hybrid: operators-as-atoms + strategies-as-functions (CHOSEN).** Captures the substrate's learned, parallel single-step inference while giving us auditable, bounded, explainable multi-step strategies. Higher interface complexity than the pure options, but the only one satisfying both the emergence thesis and desktop-companion explainability.

## Consequences
- **Positive:** Single-step inference is learned and fast (signal propagation); multi-step reasoning is bounded, deterministic-enough, and fully traceable for ADR-0043. Confidence flows end-to-end via alpha/beta. Strategies are unit-testable in isolation. New operators can emerge as atoms without code changes (ADR-0025 atom birth applies to operator atoms).
- **Negative:** Two loci of reasoning create a coordination surface — strategy functions must stay "thin" or they will accrete hidden cognition and erode the substrate principle. Requires discipline and review to prevent domain facts leaking into `mind/reasoning.nova`. Bounded propagation needs tuned step/iteration caps to avoid runaway activation at 100Hz.
- **Future work:** As the fabric matures (post-v1), migrate strategy selection itself into learned gates so chaining becomes emergent, shrinking `mind/reasoning.nova` toward a thin harness. Feeds counterfactual reasoning in ADR-0032 and goal sub-tree expansion in ADR-0033.

## Implementation Notes
- Files: extend `mind/reasoning.nova` with the named strategy functions; add a reasoning KG via `core/knowledge.nova` (namespaced per ADR-0017). Operator atoms use `atom_new` + accessors (ADR-0016); confidence via `core/belief.nova` alpha/beta.
- Signals: reuse SIG_CAUSAL, SIG_IMPLICATIVE, SIG_ANALOGICAL, SIG_EVIDENTIAL from the 18-type space (ADR-0008); record each step in the `trace` list of `core/signal.nova`.
- Strategy functions seed `NTYPE_REASONER` first nodes (ADR-0010), run bounded ticks, harvest activated operator atoms, return a trace structure consumed by ADR-0024 (errors), ADR-0026 (triggers), ADR-0033 (goal decomposition).
- Testing: fixtures with known causal/implicative chains; assert the harvested atom chain and that confidence composes correctly; assert no text generation occurs (NO-LLM guard, ADR-0014).
- `DEPENDS ON: NOVA enhancement #12` — Hebbian + error-driven plasticity kernels to strengthen operator-atom synapses. `DEPENDS ON: NOVA enhancement #6` — extended 18-type signal tag space with fast dispatch. `DEPENDS ON: NOVA enhancement #4` — SIMD/GPU batched propagation so bounded multi-step chains stay within tick budget.
