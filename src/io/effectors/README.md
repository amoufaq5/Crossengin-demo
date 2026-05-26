# Motor effectors

Terminal stage of pure-substrate output: emits text and actions from activated language and motor nodes.

**Governing ADRs:** ADR-0013, ADR-0041..0045, ADR-0043

**Status:** Implemented (Phase 9). `output_generation` produces text from a
communicative intent over the language KG (no LLM, ADR-0013); `effector_gate`
screens every action through the Phase 8 `safety_gate` and writes intent/outcome
decision-log entries (ADR-0043), with the text/SPEAK effector fully implemented.
File/network/message transport is the deferred runtime seam. Each module
compiles and has a passing `tests/unit/` suite.

See [`docs/adr/`](../../docs/adr/) for the decisions that bind this component, and the repository [README](../../README.md) for the substrate overview.
