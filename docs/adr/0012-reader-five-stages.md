# ADR-0012: Reader five stages (lexical anchor, context bias, spreading activation, coherence check, fetch/route/learn)

## Status

Proposed

## Date

2026-05-25

## Context
ADR-0011 chose the Option 5 hybrid reader but deliberately deferred its internal structure. This ADR specifies that structure: the five concrete stages through which incoming language becomes settled substrate activity and routed signals. We need this specified now because the reader sits on the critical path of every interaction; its stage boundaries determine where gates route (ADR-0009), where signals are typed (ADR-0008), where learning hooks attach (ADR-0007, ADR-0024), and where the system decides it does not know something and must learn (ADR-0026, ADR-0028).

The constraint is the 100Hz substrate tick (ADR-0037) layered on event-driven coordination: a normal utterance must settle within a small number of ticks, while genuinely novel input may legitimately spill into a slower fetch/learn path. The stages must therefore be a graded pipeline — fast common case, explicit slow case — not a fixed-cost monolith. As always: 2 founders, 8h/day, bootstrapping; the design must be implementable incrementally and testable stage by stage.

## Decision
The reader runs **five ordered stages**, each emitting typed signals that the next consumes; stages overlap across ticks rather than blocking.

1. **Lexical anchor.** Incoming surface tokens (from text, or from the STT modality bridge — ADR-0014) are matched to word/phoneme atoms in the language KG (ADR-0015). Each match fires the anchoring `NTYPE_PERCEIVER` first nodes (ADR-0010) of the perception part, emitting `SIG_SENSORY` signals tagged with the matched atom ids. Unmatched tokens emit a low-confidence anchor plus a `SIG_CURIOSITY` marker for stage 5.
2. **Context bias.** Before activation spreads freely, current context — the active concepts from the last few moments (ADR-0021), soul state (ADR-0034), and the running goal set — injects `SIG_PREDICTIVE` signals that pre-weight likely senses and likely next concepts. This is the predictive half of the Option 5 hybrid; it disambiguates polysemy and primes the spread so it converges quickly.
3. **Spreading activation.** Anchored, biased activation propagates across synapses and cross-KG reference edges (ADR-0017) via `SIG_EXCITATORY`/`SIG_INHIBITORY` signals (ADR-0008). `NTYPE_KNOWER` nodes accumulate activation; inhibition suppresses competing interpretations. The substrate settles toward the most coherent concept set — this is where meaning is actually constructed, not parsed.
4. **Coherence check.** The settled pattern is evaluated for internal consistency: do the co-active atoms mutually reference and predict one another, or is activation diffuse/contradictory? A `SIG_BINDING` pass groups mutually-supporting atoms; residual `SIG_ERROR` signals measure mismatch between top-down predictions (stage 2) and the bottom-up settle (stage 3). High coherence -> accept; low coherence -> escalate to stage 5.
5. **Fetch / route / learn.** On a coherent, known interpretation, the reader routes `SIG_EVENT`/`SIG_REQUEST` signals through learned gates (ADR-0009) to the relevant KG and reasoning parts. On low coherence or unmatched anchors, it triggers learning: ask-the-user (ADR-0027), or whitelisted internet fetch (ADR-0028), gated by "learned enough" thresholds (ADR-0030). Either way, Hebbian + error-driven plasticity (ADR-0007) updates anchor strengths, bias weights, and cross-KG references so the next encounter is faster — closing the predictive-coding loop (ADR-0024).

## Options Considered
1. **Single-pass associative settle (no explicit stages).** Simpler to write. Rejected: no clean place to inject prediction, measure coherence, or trigger learning; un-debuggable; cannot separate fast/slow paths.
2. **Strict blocking pipeline (each stage fully completes before the next).** Easy to reason about. Rejected: violates the 100Hz budget — blocking on spreading activation for long input stalls every other loop. Chosen design overlaps stages across ticks instead.
3. **Three stages (anchor, activate, route) without separate bias/coherence.** Leaner. Rejected: folding bias into activation loses the predictive sharpening that makes ADR-0011's hybrid work, and folding coherence into routing removes the explicit "I don't understand" signal that drives self-learning (ADR-0026). The five-stage split (CHOSEN) makes prediction and coherence first-class.

## Consequences
- **Positive:** Clear stage boundaries give precise hooks for gating, typing, learning, and auditing; fast common case stays within the tick budget while novel input flows to an explicit learn path; coherence check yields a principled "unknown" trigger; each stage is independently testable.
- **Negative:** Five interacting stages with overlap across ticks are more complex to schedule and debug than a single settle; coherence thresholds and bias gains require empirical tuning; mis-tuned bias can over-commit to a wrong sense before stage 4 catches it.
- **Future work:** Stage 5 is the integration point for ADR-0026/027/028/030; stage 2's predictive signals generalize into ADR-0024 predictive coding; stage 1 depends on the language-atom schema in ADR-0015.

## Implementation Notes
Implement each stage as a driver function in `crossengin/reader/reader.nova`: `reader_anchor`, `reader_bias`, `reader_spread`, `reader_cohere`, `reader_route`, sharing a `reader_state` map keyed `{active_anchors, bias_vec, settle, coherence, route_targets}`. Anchoring/spreading read the language KG and other KGs via `core/knowledge.nova` + `core/similarity.nova`. Signals use the extended `core/signal.nova` tag space; routing reuses ADR-0009 gates over `core/channel.nova` `CHAN_FILTERED`/`CHAN_WEIGHTED`. Coherence binding uses `SIG_BINDING`; learning hooks call into the ADR-0007 plasticity kernels.
Testing: per-stage fixtures under `tests/reader/` — `anchor_unknown.nova` (asserts `SIG_CURIOSITY` on OOV token), `bias_polysemy.nova` (asserts sense flip), `cohere_escalate.nova` (asserts low coherence triggers stage-5 learn path).
DEPENDS ON: NOVA enhancement #6 — extended signal tags. DEPENDS ON: NOVA enhancement #7 — learned content-based gate routing for stage 5. DEPENDS ON: NOVA enhancement #5 — 100Hz tick fused with event-driven coordination so stages can overlap across ticks.
