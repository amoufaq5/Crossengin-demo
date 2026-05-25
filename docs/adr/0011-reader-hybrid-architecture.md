# ADR-0011: Reader: Option 5 hybrid (substrate + predictive components)

## Status

Proposed

## Date

2026-05-25

## Context
Every external input to CrossEngin — typed text, a transcribed utterance, a document the user pastes — must be turned into substrate activity: a pattern of firing across the perception and KG parts that the six loops (ADR-0036) can reason over. The component that does this is the READER. It must decide which concepts a piece of language refers to, bias that interpretation by current context and soul state, pull the relevant atoms out of the right KGs (ADR-0004, ADR-0017), and learn from the interaction. This decision fixes WHAT KIND of thing the reader is, because it shapes the entire input path and every downstream ADR in this group.

The temptation is to reach for a parser or an LLM. Both are rejected on principle: per §2 and the NO-LLM-COGNITION rule formalized in ADR-0014, the reader is NOT a parser and NOT an LLM. A classical parser imposes a fixed grammar and produces brittle symbolic trees that cannot degrade gracefully or learn; an LLM would smuggle opaque cognition into the input path, defeating CrossEngin's entire thesis that intelligence emerges from substrate dynamics (ADR-0001). At the same time, a purely associative spreading-activation reader with no predictive machinery is too slow and too ambiguous to resolve real language in real time at our 100Hz tick budget (ADR-0037).

The forces are sharp. We are 2 founders at 8h/day, bootstrapping, with an 18-30 month v1 horizon. We cannot build and train a language model, nor maintain a large hand-written grammar. We need something that is cheap to start, learns continuously, runs inside the substrate, and produces signal activity rather than parse trees.

## Decision
We adopt **Option 5: a hybrid reader combining substrate spreading-activation with lightweight predictive components.** The reader is implemented as a coordinated five-stage pipeline (detailed in ADR-0012): lexical anchor, context bias, spreading activation, coherence check, and fetch/route/learn. Its substrate half does the conceptual work — token surface forms anchor to language atoms (ADR-0015), activation spreads across cross-KG references, and `NTYPE_KNOWER` nodes settle on an interpretation. Its predictive half is a thin layer of `SIG_PREDICTIVE` signals (ADR-0008) that pre-bias likely next concepts and likely senses from context, sharpening and accelerating the substrate settle so it converges within the tick budget.

Concretely, the reader is not a separate module that "calls" the substrate; it is a configuration of nodes, gates, and signals. Stage outputs are `SIG_EVENT` and `SIG_REQUEST` signals routed by learned gates (ADR-0009) to the appropriate KG parts. The predictive component is itself learned (Hebbian + error-driven, ADR-0007): when a prediction mismatches the eventual settle, the `SIG_ERROR` drives weight updates, so the reader gets faster and more accurate with experience rather than being frozen at design time. This is predictive coding (ADR-0024) applied to comprehension.

## Options Considered
1. **Pure symbolic parser (grammar + lexicon).** Deterministic, debuggable, fast. Rejected: brittle on noisy/novel input, requires hand-maintained grammar we have no capacity to build or grow, produces parse trees rather than substrate activity, and cannot learn continuously — it contradicts ADR-0001's emergence thesis.
2. **Pure statistical / n-gram model.** Cheap, robust to noise, learns from data. Rejected: shallow — captures surface co-occurrence, not concept reference or cross-domain meaning; needs a training corpus we do not have; still external to the substrate.
3. **LLM-based reader.** Most capable at raw comprehension. Rejected outright on principle (ADR-0014, §2): an LLM in the input path IS cognition; it is opaque, unauditable against the decision log (ADR-0043), and dissolves the substrate thesis. The LLM bridge is confined to STT/TTS modality only (enhancement #14).
4. **Pure-substrate spreading-activation only (no predictive layer).** Fully in-substrate, learns, no external model. Rejected as insufficient ALONE: without top-down bias, activation is ambiguous and slow to settle, blowing the 100Hz budget on long or polysemous input. It is, however, the core of the chosen option.
5. **Substrate + predictive hybrid (CHOSEN).** Keeps spreading activation as the meaning engine but adds learned predictive bias to disambiguate and accelerate. Captures the strengths of option 4 while fixing its latency/ambiguity weakness, stays fully inside the substrate, honors NO-LLM-COGNITION, and learns continuously.

## Consequences
- **Positive:** Input comprehension lives entirely in the substrate and improves with use; no training corpus or grammar to maintain; graceful degradation on novel/noisy input; full auditability (every stage emits traced signals); predictive bias keeps comprehension inside the tick budget; uniform mechanism reused for the self-model API (ADR-0038).
- **Negative:** Emergent behavior is harder to debug than a parse tree; early reader (cold substrate) will be weak until language atoms and synapses accumulate; tuning the balance between bottom-up activation and top-down prediction is delicate and ongoing; two interacting learning signals (Hebbian + error) can oscillate if gains are mis-set.
- **Future work:** ADR-0012 specifies the five stages; ADR-0015 supplies the language atoms it anchors to; ADR-0024 generalizes the predictive coding; the fetch/learn stage feeds self-learning triggers (ADR-0026) and internet fetching (ADR-0028).

## Implementation Notes
Place the reader in `crossengin/reader/reader.nova` as a substrate configuration, not a monolithic function: constructors `reader_new(parts_ref)`, stage drivers `reader_anchor`, `reader_bias`, `reader_spread`, `reader_cohere`, `reader_route` (each defined fully in ADR-0012). Anchoring queries the language KG via `core/knowledge.nova` accessors; spreading uses `core/similarity.nova` for cross-KG reference weights. Predictive bias is carried by `SIG_PREDICTIVE` signals on `core/signal.nova`'s extended tag space; mismatch raises `SIG_ERROR`. Reuse learned gates from ADR-0009 for routing settled interpretations.
Testing: fixture `tests/reader_settle.nova` feeds canned token streams to a pre-seeded language KG and asserts the settled atom set and tick count; a polysemy fixture asserts context bias flips the chosen sense.
DEPENDS ON: NOVA enhancement #6 — extended signal tag space for `SIG_PREDICTIVE`/`SIG_ERROR`. DEPENDS ON: NOVA enhancement #8 — multi-KG cross-reference edges for spreading activation. DEPENDS ON: NOVA enhancement #12 — Hebbian + error-driven plasticity kernels so the predictive layer learns.
