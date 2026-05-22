# ADR-0008: Academic knowledge module: structure and learning

## Status

Accepted

## Context

The Academic Knowledge module holds Crossengin's domain knowledge — the textbook-grade, reference-grade information about the world that the agent draws on for reasoning. It is distinct from per-user Memory (episodic, personal) and from the Cognitive module's goal-and-plan state (task-current, transient). Three questions sit at the top of its design:

1. **What is the atomic unit of stored academic knowledge?** A raw text chunk, a QA pair, a structured frame, or something composite?
2. **How is the knowledge made available to the model at inference time?** Runtime retrieval (RAG) or baked into the model's weights (fine-tuning)?
3. **How do domains relate to each other?** Sealed silos, or explicit cross-domain links?

The user has stated preferences on all three. The composite atomic unit is preferred (text chunk + QA pairs + frame together). Storage is via baked-in fine-tuning, not RAG. Cross-domain relations are explicit edges. v0 targets a single domain — medicine — and the full pipeline is built end-to-end on medicine before any second domain is added.

## Decision

**Atomic unit: composite knowledge record.** Each unit contains:

- A *textbook-style chunk* — a paragraph-to-page-length piece of source-grade prose, with its source citation and license recorded in provenance metadata.
- A *set of QA pairs* — questions and answers derived from the chunk by the preprocessing pipeline (the question-generation step at preprocessing time, not at inference time).
- A *frame* — a typed slot-and-filler structure where applicable to the chunk's content (e.g., for a drug entry, slots like `mechanism_of_action`, `indications`, `contraindications`, `typical_dosage`, `interactions`).

These three views are stored together as a single composite record. The record is also added to the graph-of-vectors substrate (ADR-0005, ADR-0006) as a node, with its vector embedding (from the shared SigLIP-derived embedding space, ADR-0004) and its symbolic relations (frame slots as outgoing edges, citations as incoming edges from source nodes).

**Storage strategy: baked into model parameters via LoRA fine-tuning.** Academic knowledge is encoded into the model's weights through scheduled fine-tunes rather than retrieved at runtime. The graph form serves preprocessing, pipeline ingestion, evaluation, and developer inspection — but at inference time the model consults its internal weights, not a runtime retrieval store. LoRA is the update mechanism, applied on a re-derivation batch cadence (per ADR-0007: deltas accumulate between LoRA updates, then a batched fine-tune folds them in).

**Cross-domain relations: explicit edges in the academic graph.** Domains are not silos. When a medicine knowledge unit references a pharmacology unit, the graph carries an explicit typed edge (e.g., `treats(aspirin_node, headache_node)`, where `aspirin_node` lives in the pharmacology slice and `headache_node` lives in the medicine slice). This is the graph-of-vectors structure that lets queries cross domain boundaries naturally.

**v0 domain: medicine only.** The full pipeline — source ingest → preprocessing → frame extraction → QA generation → graph linking → cross-domain edge addition → LoRA fine-tune → evaluation — is built end-to-end on medicine before any second domain is added. Building it on one domain first means every pipeline stage is exercised and stabilized before generalization, rather than discovering pipeline bugs during domain expansion.

## Consequences

Positive: the composite unit means every form of query (similarity, factual QA lookup, structured slot access) hits the same record. Pre-derived QA pairs at preprocessing time become high-quality fine-tune training data, which is the path to baking knowledge into weights cleanly. Explicit cross-domain edges are the substrate for the cognitive module's reasoning across domain boundaries (a medicine reasoner naturally walks into pharmacology when relevant). The medicine-first focus gives v0 a rich, permissively-licensed source corpus (per ADR-0018) and a clear factual-evaluation harness (per ADR-0022).

Negative: baking knowledge into weights makes updates expensive — every LoRA cycle is a fine-tune run on rented GPU time. The agent cannot absorb a new fact "the moment it appears" the way a RAG-based system can; new facts wait for the next LoRA cycle (with per-user memory deltas as the short-term mechanism in the meantime, per ADR-0006). The composite-unit preprocessing pipeline is more engineering than a raw-chunk approach.

Neutral: the pipeline is the largest single engineering deliverable in v0 (milestone M4 in ADR-0022). Building it on medicine first is a discipline, not a limitation — the medicine-only constraint exists to focus engineering, not to bound the architecture.

## Alternatives considered

**Raw text chunks only (no frames, no derived QA).** Less preprocessing work. Rejected: loses the inspectability of frames (a slot-filled `Drug` record is queryable in ways a raw paragraph is not) and loses the high-quality QA training signal that pre-derived QA pairs provide for fine-tuning.

**RAG instead of fine-tuning.** Runtime retrieval over the academic store at inference time. Simpler ingest path. Rejected by the user in favor of baked-in weights, on the grounds that an architecture whose knowledge lives in weights is materially different from an architecture that retrieves text at inference — the former is closer to the "structured brain" thesis. The cost is fine-tune compute. The hybrid would be possible (bake the stable core, RAG the long tail) and may be revisited in v1.

**Domain silos with no cross-domain edges.** Simpler graph. Rejected: real-world reasoning crosses domain boundaries constantly, and a sealed-silo design would force the cognitive module to fall back on string matching across domain text rather than typed edges across domain entities.

**Build the pipeline on multiple domains in parallel.** Faster perceived progress. Rejected: pipeline bugs found during multi-domain ingest are harder to triage than the same bugs found during single-domain ingest. Medicine-first is the focused-engineering path.

## Open questions

- Specific frame schemas for medicine v0. Initial sketch: `Drug`, `Condition`, `Treatment`, `DiagnosticTest`, `Symptom`, `Anatomy`. The complete v0 schema is finalized at M4 alongside source ingest (per ADR-0022 and ADR-0018).
- QA-generation policy: which model generates the QA pairs from chunks at preprocessing time, and what permissive-license constraints apply to it (ADR-0019). Decision needed at M4.
- LoRA fine-tune cadence — initial heuristic is per re-derivation batch (per ADR-0007), exact frequency tuned by per-batch evaluation results at M4.

## References

- ADR-0004 (Perception layer) — the shared embedding space producing the `vector` facet.
- ADR-0005 (Knowledge representation) — the graph-of-vectors form.
- ADR-0006 (Memory architecture) — the storage substrate.
- ADR-0007 (Knowledge update policy) — the delta-and-rebuild discipline academic knowledge inherits.
- ADR-0017 (Compute) — the LoRA fine-tune budget.
- ADR-0018 (Data sources) — the permissive medicine source corpus.
- ADR-0019 (Licensing posture) — constraints on QA-generation models and tooling.
- ADR-0022 (Evaluation and milestones) — M4 milestone definition-of-done.
