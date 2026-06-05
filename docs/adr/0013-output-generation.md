# ADR-0013: Output generation: pure substrate, no LLM

## Status

Proposed

## Date

2026-05-25

## Context
CrossEngin must produce language: answers, questions back to the user (ADR-0027), descriptions of its own state (ADR-0038). The industry-default way to do this is to hand a context buffer to an LLM and stream tokens back. CrossEngin rejects this. Per §2 and ADR-0014, output is pure-substrate generation: it flows from concept activation patterns down through language nodes to motor effectors, with NO LLM anywhere in the path. This ADR fixes the output mechanism, the mirror image of the reader (ADR-0011/012).

The reason is foundational, not stylistic. If an LLM generates output, then the LLM — not the substrate — is choosing what the system says, which means it is doing the cognition that CrossEngin exists to do in the substrate (ADR-0001). Output would become unauditable (we could not trace a sentence back through the decision log, ADR-0043), unlearnable in our framework, and severed from the soul's identity and values (ADR-0034). The hard question this raises — how do you get fluent language without a language model? — is exactly what this ADR must answer.

Constraints: 2 founders, 8h/day, bootstrapping, 18-30 month v1. We cannot train a generator. Fluency must therefore emerge from the same language atoms (ADR-0015) and substrate dynamics already built for the reader, reused in the production direction.

## Decision
We adopt **pure-substrate output generation**. Generation is the reverse flow of comprehension. A communicative intent — a settled pattern of active concept atoms produced by the reasoning/goal loops — propagates downward: active concepts emit `SIG_EXCITATORY` signals to the language nodes that name them (the same word/phoneme/syntax atoms of ADR-0015 that the reader anchored to), syntax-pattern atoms sequence them via `SIG_BINDING` and ordering constraints, and the resulting ordered language signals drive `NTYPE_ACTOR` motor-effector nodes (ADR-0006) that render text — or hand phonemes to the TTS modality bridge (ADR-0014).

Fluency without a language model comes from three substrate sources: (a) the language KG stores not just words but learned syntax-pattern atoms and collocations, so well-formed sequences are high-weight paths that win the downward spread; (b) the same predictive machinery used in comprehension (ADR-0012 stage 2, ADR-0024) runs forward here, predicting the next language node and pruning ill-formed continuations via `SIG_INHIBITORY`; (c) Hebbian + error-driven plasticity (ADR-0007) strengthens phrasings that the user accepts and weakens awkward ones, so fluency is learned and personalized over time. The soul (ADR-0034) and emotion system (ADR-0035) modulate tone by biasing which language atoms activate.

## Options Considered
1. **LLM generation (or LLM "polish" of substrate drafts).** Maximally fluent. Rejected on principle (ADR-0014, §2): any LLM in the output path IS cognition, is unauditable, and breaks the substrate thesis. Even "polish-only" lets the LLM choose final wording — disqualifying.
2. **Fixed templates / grammar-based surface realization.** Fully controllable, no LLM, cheap to start. Rejected as the primary mechanism: rigid, doesn't learn, can't personalize, and produces stilted output — though template fallbacks may seed the cold-start language KG.
3. **Statistical n-gram surface generator.** Learns phrasing, no LLM. Rejected as standalone: external to the substrate, severed from concept activation and soul, and shallow. Its insight (sequence statistics matter) is absorbed into the syntax-pattern atoms and predictive pruning of the chosen design.
4. **Pure-substrate downward generation (CHOSEN).** Concept activation -> language nodes -> motor effectors, with learned syntax atoms and predictive pruning supplying fluency. Keeps generation in the substrate, auditable, learnable, soul-modulated. Weaker fluency at cold start, but improves with use and honors every principle.

## Consequences
- **Positive:** Output is fully in-substrate, auditable end-to-end, and traceable to the concepts and goals that produced it; fluency is learned and personalized; tone is governed by soul/emotion, not a foreign model; one language KG and one predictive mechanism serve both reading and writing.
- **Negative:** Cold-start output is markedly less fluent than an LLM and may need template scaffolding early; building learned syntax-pattern atoms is substantial work (ADR-0015); long, complex utterances are hard to keep coherent via spreading alone and will need ordering/coherence safeguards analogous to the reader's stage 4.
- **Future work:** ADR-0015 must define syntax-pattern atoms rich enough to carry word order and agreement; ADR-0038 builds the self-description API on this path; ADR-0027's clarifying questions are generated here; ADR-0024 supplies the forward predictive pruning.

## Implementation Notes
Implement in `crossengin/output/generate.nova`: `gen_from_intent(active_concepts)` -> downward spread, `gen_sequence` applying syntax-pattern atoms via `SIG_BINDING`, `gen_emit` driving `NTYPE_ACTOR` nodes from `core/node.nova`. Reuse the language KG accessors (`core/knowledge.nova`) and `SIG_EXCITATORY`/`SIG_INHIBITORY`/`SIG_PREDICTIVE` from `core/signal.nova`. Soul/emotion bias hooks read `core/soul.nova` and `mind/emotion.nova`. Phoneme output for speech is handed to `runtime/llm.nova` + `runtime/llm_bridge.c` strictly as TTS modality (ADR-0014) — never for word choice.
Testing: `tests/output/intent_to_text.nova` asserts a fixed active-concept set yields a well-formed sentence; `tests/output/no_llm_path.nova` asserts (via trace inspection) that no signal in the generation trace ever enters the LLM bridge except the final TTS hand-off.
DEPENDS ON: NOVA enhancement #14 — STT/TTS bridge isolation guaranteeing no cognition path. DEPENDS ON: NOVA enhancement #12 — plasticity kernels for learned fluency. DEPENDS ON: NOVA enhancement #6 — extended signal tags for binding/prediction.
