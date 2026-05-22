# ADR-0004: Perception layer

## Status

Accepted

## Context

The agent's perception layer is what converts raw sensory input (text, image, later audio and video) into representations that the four brain modules (Memory, Cognitive, Academic, Visionary) can consume. Three design questions sit on top of this:

1. Which modalities are in v0, and which deferred.
2. How modalities relate to one another representationally — separate per-modality embeddings with a fusion step, or a shared cross-modal embedding space.
3. Whether perception is turn-based (the agent waits for an explicit input, processes it, replies) or streaming (the agent continuously perceives and can act spontaneously).

The user has stated the desired endpoint clearly: streaming continuous perception across text, image, audio, and video. The questions for v0 are scope and representational form.

## Decision

**v0 modalities: text and image.** Audio is added in v1; video in v2. The image modality is built in v0 even though it could be deferred, because including it forces the shared-embedding-space design to be exercised on more than one modality from day one. Single-modality v0 would not stress the cross-modal architecture, and retrofitting it later would be more expensive than building it correctly now.

**Cross-modal representation: shared embedding space**, CLIP/SigLIP-style. A single embedding space holds text and image vectors such that semantically related inputs land near each other regardless of modality. This is the path that supports cross-modal retrieval, cross-modal grounding, and unified storage in the memory substrate as a single vector column.

**Streaming continuous perception**, not turn-based polling. The perception layer ingests modality streams continuously; the cognitive module's initiative triggers (ADR-0009) decide when to act on what's perceived.

**Encoder choice for v0: SigLIP.** Apache 2.0 license, which is clean under the strict-permissive posture (ADR-0019). CLIP's MIT license is also permissive in form, but the OpenAI release terms add ambiguity for some commercial users; SigLIP avoids that ambiguity entirely. SigLIP also benchmarks competitively with CLIP on standard zero-shot tasks.

**On-device perception** is the v1+ target. v0 runs perception in the cloud alongside the model. Camera and microphone access at any stage requires explicit per-user opt-in with an audit trail (ADR-0021).

## Consequences

Positive: a single shared embedding space simplifies the memory substrate — one vector column, one similarity index. Cross-modal queries (e.g., "find memories related to this image") work without a fusion layer. SigLIP's Apache license keeps the dependency tree clean. Streaming perception is the architecturally honest design for an always-on agent; building it from v0 avoids a later disruptive refactor from turn-based to streaming.

Negative: streaming perception is more engineering surface than turn-based. Backpressure, buffering, and the contract between perception and the cognitive module's initiative triggers all need explicit design. Cloud-only perception for v0 means user camera/mic feeds, if used, traverse the network — privacy boundaries (ADR-0021) need to be enforced before any audio/video sensors come online in v1.

Neutral: image modality at v0 increases the size of the preprocessing pipeline and the LoRA fine-tune surface but does not change the memory substrate's design.

## Alternatives considered

**Text-only v0, image deferred to v1.** Lower v0 surface area; rejected because the cross-modal architecture must be designed with more than one modality from the start, or it will be incorrectly designed.

**Per-modality encoders with a late-fusion layer** (separate embedding spaces for text and image, fused at the consumer end). Rejected: more complex memory schema, harder cross-modal retrieval, no clear advantage at v0 scale. Late fusion becomes interesting if a specialized modality (e.g., high-resolution medical imaging) outgrows a shared general-purpose encoder; deferred until the need is observable.

**CLIP instead of SigLIP.** Considered. SigLIP wins on the license-clarity criterion; the technical differences are small enough that either would work, but SigLIP is the cleaner default for a project that is going to be license-audited.

**Turn-based perception polling.** Simpler to implement. Rejected as a v0 choice because retrofitting streaming on top of a turn-based foundation is more disruptive than building streaming from the start. The cognitive module's initiative triggers (perception-derived inference, anticipated events) require streaming to function.

## Open questions

- Specific SigLIP variant for v0 (SigLIP, SigLIP 2, language-specific variants). Decision deferred to the M2 perception milestone in ADR-0022; depends on a small benchmark on representative medicine-domain inputs (e.g., medical diagram captions, drug-label images).
- Backpressure policy on streaming perception when the cognitive module is busy. Drop-oldest, drop-newest, summarize-and-collapse — each has different semantics for what the agent "remembers having seen." Needs prototyping at M2.

## References

- ADR-0006 (Memory architecture) for how perception outputs become `MemoryItem` rows.
- ADR-0009 (Cognitive module) for how perception streams feed initiative triggers.
- ADR-0019 (Licensing posture) for the SigLIP-over-CLIP rationale.
- ADR-0021 (Privacy) for camera/mic consent and audit requirements.
- ADR-0022 (Evaluation and milestones) for the perception milestone (M2) where encoder choice is finalized.
