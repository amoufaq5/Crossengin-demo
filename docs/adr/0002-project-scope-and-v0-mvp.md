# ADR-0002: Project scope and v0 MVP

## Status

Accepted

## Context

Crossengin's long-term vision is an AGI-capable architecture deployed as personal companions for individuals and as derived "company brain" models for enterprises. The full vision spans multimodal perception (text, image, audio, video), four cognitive modules under a Soul layer, per-user persistent memory, per-user soul tuning, and enterprise derivation pipelines. Building all of this at once is not feasible for a small bootstrapped team renting GPU time on demand.

A v0 MVP needs to be small enough to ship, large enough to demonstrate the architecture's distinctive thesis (a structured, non-LLM-pilled, module-composed brain with an outer Soul layer), and concrete enough that progress is measurable rather than aspirational.

## Decision

**v0 in scope:**

- **Perception:** text and image only. Streaming continuous perception. Shared embedding space.
- **Academic knowledge:** medicine as the single domain. Full preprocessing → frame extraction → QA generation → graph linking → LoRA fine-tune pipeline built end-to-end on medicine.
- **Memory:** single-substrate per user on PostgreSQL 16+ with `pgvector` and Apache AGE. Composite `MemoryItem` schema. Working memory as a tagged subset. Per-user row-level encryption.
- **Cognitive module:** BDI-style explicit symbolic goals supplied by the user. Hierarchical planning. Fast heuristic consequence predictor.
- **Visionary module:** probabilistic graphical model for cause-and-effect simulation. Dreaming and simulation unified as directed scenario rollout.
- **Soul:** constitutional layer only for v0 (the 8 starter values in ADR-0011). Developer-tunable and user-configurable layers exist in design but are not implemented in v0.
- **Deployment:** per-user skin-plus-adapter (frozen base + per-user encrypted memory + per-user LoRA + per-user soul tuning). Cloud-only inference on RunPod.

**v0 explicitly out of scope:**

- Audio perception (v1).
- Video perception (v2).
- On-device perception or inference (v1+).
- Multi-domain academic knowledge beyond medicine.
- Developer-tunable and user-configurable soul layers (designed in ADR-0011 but not built).
- A user-facing soul tuning UI.
- Enterprise derivations and the modular swap pipeline (designed in ADR-0016, not built).
- Per-user LoRA training automation. v0 can ship with the LoRA adapter mechanism in place but the user-personalization training loop deferred.

**Success criteria for v0** (concrete; full operational definitions in ADR-0022):

1. **Medicine factual QA:** after LoRA fine-tuning on the medicine corpus, the agent answers novel medical questions about a defined sub-area (e.g., hypertension) drawn from a held-out test set above an accuracy threshold to be set in ADR-0022, and correctly says "I don't know" for out-of-corpus questions at a calibrated refusal rate.
2. **Cross-session memory coherence:** the agent correctly references and builds on prior conversations with the same user across at least three separate sessions.
3. **Constitutional enforcement:** a red-team test suite verifies the agent refuses or correctly handles attempts to violate each of the 8 constitutional values from ADR-0011.

## Consequences

Positive: scope is small enough to deliver with a small team and rented GPU time. The medicine-first choice gives a domain with rich permissively-licensed source material (PubMed, MedlinePlus, drugs.gov, DailyMed — see ADR-0018) and clear factual-evaluation primitives. Cloud-only inference removes a large engineering surface (model packaging for edge, quantization, on-device runtimes) from the v0 critical path.

Negative: the visible v0 deliverable will look domain-narrow to outside observers. The "personal companion for every citizen" vision is not demonstrated at v0 scale. Anyone evaluating the project on breadth rather than architectural soundness will under-rate it.

Neutral: medicine is a high-stakes domain. The constitutional value about honest uncertainty (#6 in ADR-0011) plus calibrated refusal in the QA criterion are how we keep v0 honest about its limits.

## Alternatives considered

**Multi-domain v0 (medicine + law + general science).** Rejected: broader surface to evaluate, no clear test harness, dilutes the pipeline-build effort.

**Text-only v0, defer image to v1.** Considered. The image modality at v0 is justified because the perception architecture (shared embedding space) is materially different with and without a second modality — building it once now avoids re-architecting later.

**Build the soul tuning UI in v0.** Rejected: governance schema and policy enforcement matter more than the UI at v0. UI work proceeds when there is a real population of users whose preferences would inform the design.

## Open questions

- The accuracy threshold for the medicine-domain QA success criterion is set in ADR-0022 and is currently a placeholder pending a baseline measurement on the held-out set.
- The specific medicine sub-area for v0 evaluation (hypertension is the working example) needs final confirmation. The narrower the sub-area, the higher the achievable accuracy ceiling for v0.

## References

- ADR-0011 (Soul: values governance) for the constitutional values referenced.
- ADR-0018 (Data sources for medicine v0) for the source corpus.
- ADR-0022 (Evaluation and milestone plan) for the operational success-criteria definitions.
