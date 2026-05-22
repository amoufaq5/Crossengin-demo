# ADR-0007: Knowledge update policy

## Status

Accepted (user-overridable)

## Context

Both the academic knowledge module and per-user memory grow over time. New papers appear in PubMed, drug labels change, treatment guidelines update, the user has new conversations and forms new memories. The system needs a policy for how stored knowledge is updated. Two broad approaches exist:

- **Deltas.** Each update is a signed, versioned, atomic change to existing knowledge. Add this fact, retract that one, modify this relation. Updates are small and frequent. The current state of knowledge is the sum of all applied deltas.
- **Incremental rebuilds.** Each update is a re-derivation of some portion of the knowledge base from a source of truth (corpus, ingest snapshot). Updates are larger and less frequent. The current state of knowledge is the latest rebuild output.

The two approaches have different failure modes. Deltas can silently corrupt the knowledge base if a delta is wrong and there is no source-of-truth to rebuild from; auditing what the system "knows" requires replaying or summing the delta history. Incremental rebuilds are slower, more wasteful of compute, and force a discrete-update cadence on the system; but they have a clear correctness story — the knowledge base is, by construction, the deterministic output of the pipeline applied to the current sources.

The assistant's recommendation during the design conversation was incremental rebuilds, on correctness-auditability grounds. The user chose deltas as the primary mechanism, on responsiveness grounds (deltas are cheap, frequent, and let the agent absorb new information without waiting for the next batch cycle). The user further requested that the chosen approach include enough safety net to mitigate the silent-corruption failure mode.

## Decision

**Primary mechanism: deltas.** Updates to the academic knowledge module and to per-user memory are encoded as signed, versioned deltas:

- Each delta is a structured operation (`ADD_TRIPLE`, `RETRACT_TRIPLE`, `MODIFY_FRAME_SLOT`, `MERGE_NODES`, `LINK_NODES`, ...) over the graph-of-vectors substrate.
- Each delta carries a signature identifying its producer (preprocessing pipeline run, user-correction event, dream-consolidation, etc.).
- Each delta carries a version number and timestamp.
- Deltas are appended to an immutable delta log per user / per academic-knowledge domain. The current knowledge state is the materialized fold of the log.

**Mitigation 1: quarantine queue.** Deltas do not apply to the live graph immediately. They land in a quarantine queue. A reviewer policy (heuristic for low-stakes deltas, human-in-the-loop for high-stakes deltas in v0; learned classifier in v1) approves or rejects before application. Rejected deltas are logged with reason.

**Mitigation 2: periodic rebuild from sources.** A scheduled job re-derives the academic knowledge module from the source corpus on a fixed cadence (initial cadence: weekly during v0 development, adjustable per domain). The rebuild output is compared against the delta-folded state; divergence above a threshold triggers an alert and a manual review of intervening deltas. This is the safety net for silent corruption — there is always a recent point at which the academic knowledge base was known to match the source corpus.

**Mitigation 3: rollback primitive.** Any delta can be rolled back by appending its inverse to the delta log. The version chain makes the rollback target unambiguous.

**Hybrid policy.** Deltas are the mechanism for *additions* (new facts, new relations, new memories). Incremental rebuilds are the mechanism for *breaking changes* — taxonomy shifts (e.g., a class of drugs gets reclassified), disputed-claim removals where the soundness of related derived knowledge is in question, and any change whose blast radius is hard to reason about as a local delta. The judgment call about which path applies is made in the preprocessing pipeline; high-stakes domain edits default to the rebuild path.

## Consequences

Positive: the agent absorbs new information quickly. Per-user memory updates (the user said something new, did something new) are naturally delta-shaped. The delta log is auditable — any reviewer can see exactly what was applied and when. Rollback is cheap.

Negative: pure deltas without the safety net would risk silent corruption; we are paying for the rebuild job's compute cost (per ADR-0017's RunPod model) to retain that safety. The quarantine queue adds latency between a new fact appearing and the agent acting on it. High-stakes deltas that require human review will queue up if the review process is undermanned.

Neutral: this is a hybrid that leans toward deltas. The hybrid's complexity is real; we accept it as the cost of the user's preference for responsiveness, with the rebuild safety net as the correctness backstop.

## Alternatives considered

**Pure incremental rebuilds** (assistant's recommendation). Slower, less responsive, but auditability and silent-corruption resistance are essentially free properties. The user rejected this on the grounds that an agent that has to wait for the next batch cycle to absorb new information does not feel like a living companion. The user is decision owner; status is `Accepted (user-overridable)`.

**Pure deltas without a rebuild safety net.** The cheapest design. Rejected by the user's own subsequent request that mitigations be included. The risk profile without a rebuild safety net is too high for a system that stores medical knowledge.

**Per-domain choice (deltas for some domains, rebuilds for others).** Implicitly subsumed by the hybrid policy above — additions go through deltas everywhere, breaking changes go through rebuilds everywhere, with the choice made at the source.

**Continual learning at the weight level** (LoRA adapters updated per delta). Considered but unbatched LoRA updates per delta are training-unstable and compute-expensive. ADR-0008 specifies that LoRA fine-tunes are scheduled per re-derivation batch, not per delta — deltas in the academic graph accumulate between LoRA updates and are applied in batches.

## Open questions

- Concrete cadence for the rebuild safety net per domain (weekly is the starting point for medicine v0; this should be tuned at M4 once the rebuild's actual cost is measured).
- Threshold for the "delta-folded vs rebuilt" divergence alert. Initial heuristic: any node addition or retraction present in one and not the other. Tunable post-M4.
- Quarantine reviewer policy for v0: human-in-the-loop for all academic deltas (low volume), heuristic auto-approve for low-stakes per-user memory deltas (high volume). Specifics resolved at M4.

## References

- ADR-0005 (Knowledge representation paradigm) — the graph-of-vectors substrate that deltas operate on.
- ADR-0006 (Memory architecture and storage) — the `MemoryItem` row format that deltas modify.
- ADR-0008 (Academic knowledge module) — how the delta log relates to LoRA fine-tune cycles.
- ADR-0017 (Compute and infrastructure) — the budget for the rebuild safety net.
- ADR-0022 (Evaluation and milestones) — the M4 milestone where the cadence and thresholds are finalized.
