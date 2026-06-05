# Modality transducers

Speech-to-text and text-to-speech ONLY, via the NOVA LLM bridge (runtime/llm.nova). There is deliberately no cognition path through this component.

**Governing ADRs:** ADR-0014

**Status:** Implemented (Phase 9), text path. `input_transducer` normalizes text/
file input into a reader-ready percept (trim/lowercase/whitespace-collapse), with
no cognition path. Audio (STT) and TTS remain the deferred NOVA modality-bridge
seam — DEPENDS ON NOVA enhancement #14 (bridge isolation guaranteeing no
cognition path); the transducer reports audio as not-ready rather than
fabricating a transcription. The module compiles and has a passing `tests/unit/`
suite.

See [`docs/adr/`](../../docs/adr/) for the decisions that bind this component, and the repository [README](../../README.md) for the substrate overview.
