# ADR-0014: No-LLM cognition principle (LLM-bridge only for STT/TTS modality)

## Status

Proposed

## Date

2026-05-25

## Context
CrossEngin is built on NOVA, which ships an LLM bridge (`runtime/llm.nova` + `runtime/llm_bridge.c`) and LLM-flavored agent modules (`agent/cognitive_llm.nova`, `agent/rag.nova`). Their presence is a standing temptation: at every hard step — comprehension (ADR-0011/012), reasoning (ADR-0031), output (ADR-0013), knowledge retrieval (ADR-0017) — it would be faster for 2 founders to "just call the model." This ADR exists to make that impossible by principle and by enforcement, because the temptation will recur on nearly every other ADR and must have one authoritative ruling to point to.

The principle is foundational to CrossEngin's identity (§2): intelligence must emerge from substrate dynamics (ADR-0001), not from an opaque external model. If an LLM does the cognition, then CrossEngin is a wrapper around an LLM — unauditable (its choices cannot be traced in the decision log, ADR-0043), unlearnable in our Bayesian/Hebbian framework (ADR-0007, ADR-0023), and severed from the soul (ADR-0034). The capability tests in ADR-0049 explicitly include no-LLM-cognition verification; this ADR defines what that test enforces.

The legitimate need that remains is modality. Users may want to speak and listen. Speech-to-text and text-to-speech are signal-format conversions, not cognition. Drawing that line precisely is the whole job of this ADR.

## Decision
We adopt the **NO-LLM-COGNITION principle as a hard, non-negotiable constraint.** The system NEVER uses an LLM for cognition — not for comprehension, knowledge retrieval, reasoning, planning, output generation, or self-modeling. The ONLY permitted use of the NOVA LLM bridge is STT/TTS modality conversion at the system's sensory/motor boundary: raw audio -> token surface forms on the way in, and phoneme/text -> audio on the way out (enhancement #14).

The line is drawn architecturally, not by convention. The LLM bridge is reachable only from two named adapters — `crossengin/io/stt_adapter.nova` and `crossengin/io/tts_adapter.nova` — which sit OUTSIDE the substrate. The STT adapter's only output is a token stream into the reader's lexical-anchor stage (ADR-0012 stage 1); it produces no concepts, no atoms, no interpretation. The TTS adapter's only input is already-generated phonemes from the pure-substrate output path (ADR-0013); it makes no word choices. No substrate node (`core/node.nova`), gate (ADR-0009), or signal path (`core/path.nova`) may carry a reference into the bridge. The LLM-flavored agent modules (`agent/cognitive_llm.nova`, `agent/rag.nova`) are NOT used by CrossEngin.

## Options Considered
1. **Allow LLM as a fallback when the substrate is uncertain.** Pragmatic; would improve early answers. Rejected: the fallback becomes a crutch the substrate never outgrows, every fallback answer is unauditable and unlearnable, and the boundary erodes immediately. Directly violates §2.
2. **Allow LLM for "non-core" tasks (summarization, retrieval) but not final reasoning.** Seemingly narrow. Rejected: summarization and retrieval ARE cognition (they decide what matters); this is the camel's nose. There is no stable line short of modality-only.
3. **Soft principle enforced by code review / convention only.** Cheap. Rejected: with 2 founders under time pressure, convention fails exactly when it matters; the principle is too foundational to leave unenforced. We need an architectural seam plus a test.
4. **Hard principle, modality-only bridge, enforced by isolation + test (CHOSEN).** The bridge is reachable only via two boundary adapters; an automated test verifies no cognition path touches it. Preserves the substrate thesis, auditability, and learnability, while still allowing voice I/O.

## Consequences
- **Positive:** CrossEngin's core thesis is protected and enforceable, not aspirational; all cognition is auditable (ADR-0043) and learnable (ADR-0007, ADR-0023); the system genuinely owns its competence and can report it honestly (ADR-0020, ADR-0038); voice I/O remains available without compromise.
- **Negative:** Forgoes the easy fluency/coverage an LLM would give, especially at cold start — the substrate must earn every capability; comprehension and output (ADR-0011/013) are weaker early; founders must resist a constant pragmatic pull.
- **Future work:** ADR-0049 implements the automated no-LLM-cognition verification test; ADR-0046/047 must ensure deployment configs never wire the bridge into a cognition path; ADR-0028 (internet fetch) must route retrieved text through the reader, not an LLM.

## Implementation Notes
Enforcement seam: confine all imports of `runtime/llm.nova` / `runtime/llm_bridge.c` to `crossengin/io/stt_adapter.nova` and `crossengin/io/tts_adapter.nova`. Provide `stt_to_tokens(audio) -> tokens` (feeds ADR-0012 stage 1) and `tts_from_phonemes(phonemes) -> audio` (consumes ADR-0013 output). Add a build-time/CI guard (`tests/no_llm_cognition.nova`) that statically asserts no module under `crossengin/reader/`, `crossengin/output/`, `mind/`, or `agent/agent.nova` references the bridge symbols, and a runtime trace assertion that no `SIG_*` trace path (`core/signal.nova` trace field) ever visits a bridge node. Explicitly exclude `agent/cognitive_llm.nova` and `agent/rag.nova` from the CrossEngin build manifest in `pkg/pkg.nova`.
DEPENDS ON: NOVA enhancement #14 — STT/TTS modality bridge isolation guaranteeing no cognition path through `runtime/llm.nova` + `runtime/llm_bridge.c`.
