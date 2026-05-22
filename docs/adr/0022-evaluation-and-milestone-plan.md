# ADR-0022: Evaluation criteria and v0 milestone work plan

## Status

Accepted

## Context

A v0 ship needs a definition. Without one, "v0" drifts indefinitely as new features feel necessary. This ADR closes that loophole by specifying three concrete success criteria for v0 and a six-milestone work plan with explicit definition-of-done for each milestone.

The success criteria correspond to the three load-bearing claims Crossengin's v0 makes: that the academic-knowledge pipeline produces an agent that knows medicine and knows what it doesn't know; that the memory substrate supports coherence across sessions; that the constitutional governance is real, not aspirational.

## Decision

### v0 success criteria

**Success criterion 1 — Medicine-domain factual QA with calibrated refusal.**

- The agent, after LoRA fine-tuning on the v0 medicine corpus (per ADR-0008 and ADR-0018), answers a held-out set of medicine questions about the v0 sub-area (hypertension is the working target) at an accuracy threshold to be set by baseline measurement at M4.
- The agent correctly refuses ("I don't know" with appropriate language) on out-of-corpus questions at a calibrated refusal rate. Calibration means: the agent's expressed confidence on its answers correlates with the actual accuracy of those answers; refusal happens at confidence below a threshold.
- The accuracy threshold is set by measuring the baseline (untuned base model) and the LoRA-tuned model on the held-out set. The pass threshold is set during M4 as "materially above baseline, in absolute terms at a level that supports the v0 ship narrative."
- This criterion is operationally testable. A pass/fail signal can be generated at any point during development.

**Success criterion 2 — Cross-session memory coherence.**

- Across a defined sequence of at least three separate sessions with the same simulated user, the agent correctly references and builds on prior conversations.
- Concretely: a test harness simulates user sessions with known content (the user mentions a specific medication they take, a specific concern, a specific preference). In later sessions, the agent's responses correctly incorporate those prior details without the user re-stating them.
- The test harness is automated and runs as part of the v0 evaluation suite.

**Success criterion 3 — Constitutional value enforcement.**

- A red-team test suite (M6) verifies, for each of the 8 starter constitutional values (ADR-0011), that the agent refuses or correctly handles attempts to violate the value.
- Each value has at least three test cases: an unambiguous violation attempt, an ambiguous boundary case, and a benign case that superficially resembles a violation.
- A pass means: unambiguous violations are blocked or correctly handled, ambiguous cases are flagged or handled with appropriate caution, and benign cases are not over-blocked.

### Milestone work plan

**M1 — Infrastructure.**

Definition-of-done:
- RunPod container workflow established with a pinned Python + PyTorch + Rust base image (ADR-0017).
- PostgreSQL 16 + `pgvector` + Apache AGE deployed on a persistent network volume, accessible from training and inference containers (ADR-0006).
- License-detection CI integration wired in (ADR-0019).
- Cost-tracking ledger initialized (ADR-0017).
- Backup tooling for the PostgreSQL substrate running on the documented cadence.

**M2 — Perception.**

Definition-of-done:
- SigLIP encoder integrated and producing embeddings into the documented `vector` column dimensionality (ADR-0004, ADR-0006).
- Text and image inputs flow through a streaming perception pipeline.
- Backpressure policy decided and implemented.
- Perception outputs land as `MemoryItem` rows with correct `vector` and provenance metadata.

**M3 — Memory substrate.**

Definition-of-done:
- `MemoryItem` schema implemented end-to-end (ADR-0006).
- Per-user row-level encryption working, KMS choice finalized (ADR-0021).
- Working-memory tagging and read path implemented.
- User-data export and delete primitives functional and tested.
- Audit-log infrastructure operational (ADR-0011, ADR-0021).

**M4 — Academic knowledge for medicine.**

Definition-of-done:
- Source ingest pipeline functional for the v0 medicine corpus (ADR-0018) with full provenance metadata.
- Frame schemas for medicine v0 finalized (ADR-0008).
- QA-generation pipeline functional.
- Cross-domain edges between medicine and adjacent domains (chemistry, biology, pharmacology) created where applicable.
- First LoRA fine-tune cycle completed.
- Baseline (untuned) and post-tune evaluations on the held-out QA set complete; success criterion 1's accuracy threshold set.
- Rebuild safety net (ADR-0007) tested at least once on the full corpus.

**M5 — Cognitive + Visionary + Soul integration.**

Definition-of-done:
- BDI-style goal tracking implemented (ADR-0009).
- Hierarchical planner functional for the v0 use-case scope.
- Action vocabulary (text, tool calls, code execution, UI manipulation) plumbed end-to-end with sandbox.
- Visionary's probabilistic-graphical-model integration with PyMC operational; idle-time dream rollouts producing `imagined=true` events; containment rules verified.
- Self-model and narrative thread (ADR-0013) implemented and exposing the introspection API.
- Constitutional gate (ADR-0011) operational; every action passes through it; gate decisions logged.
- v0 OCC emotion subset (ADR-0012) recognized and influencing action selection.
- Per-deployment personality config schema finalized and loaded (ADR-0014).
- Per-user LoRA adapter mechanism integrated (training loop automation deferred per ADR-0015, but the adapter-attach mechanism is functional).

**M6 — Evaluation and red-team.**

Definition-of-done:
- Cross-session memory coherence test harness operational (success criterion 2 testable).
- Constitutional red-team test suite written and run (success criterion 3 testable).
- Medicine-domain QA evaluation re-run on the final v0 model (success criterion 1 testable).
- All three success criteria pass at the thresholds set in their respective sections.
- Final evaluation report compiled.

### Cadence

The milestones are sequential: each depends on the prior. Some preparation can run in parallel (e.g., source-corpus collection at M4 can begin during M1 and M2 since it does not depend on infrastructure being live), but the definition-of-done gates are sequential.

No fixed calendar dates are committed in this ADR. The user has stated that the team is bootstrapped and renting compute on-demand; calendar commitments without funding are speculative. The milestone structure and definitions-of-done are the contract; the calendar is determined by available engineering capacity and adjusted as actual progress accumulates.

## Consequences

Positive: "v0" has a definition. Three pass/fail criteria; six milestones with definition-of-done. Anyone reviewing the project can ask "are we done with M4?" and get a real answer. The success criteria are honest — they include a refusal-calibration component and a red-team component, not just an accuracy number.

Negative: pass/fail gates can be sandbagged (set the threshold low enough and any model passes). The accuracy-threshold-set-at-M4 approach acknowledges this — we set the threshold against a baseline so "materially above baseline" is a real test, not a vacuous one. Red-team test suites have coverage limits; a passing red-team is necessary but not sufficient for full safety.

Neutral: the milestone structure assumes the architecture decisions in the prior ADRs hold. If a major architectural pivot happens mid-project, the milestone definitions need re-issuing.

## Open questions

- Specific medicine sub-area for the v0 evaluation (hypertension is the working target; alternative narrower sub-areas could include a single drug class or a single condition cluster). Finalized at M4.
- Concrete accuracy threshold for success criterion 1. Set at M4 against baseline.
- Calibration scoring methodology — Brier score, ECE (expected calibration error), or both. Finalized at M4.
- Exact test-case count and structure for the red-team suite. v0 default: at least three per constitutional value (24 minimum). May expand during M6.

## References

- ADR-0002 (Project scope and v0 MVP) — the scope this evaluation plan operationalizes.
- ADR-0006 (Memory architecture) — M3.
- ADR-0008 (Academic knowledge) — M4.
- ADR-0009 (Cognitive module), ADR-0010 (Visionary), ADR-0011 (Soul values), ADR-0012 (Emotions), ADR-0013 (Consciousness), ADR-0014 (Personality), ADR-0015 (Deployment) — M5.
- ADR-0017 (Compute) — M1 and the cost-tracking discipline.
- ADR-0018 (Data sources) — M4 corpus and license provenance.
- ADR-0019 (Licensing) — M1 license-gate integration.
- ADR-0021 (Privacy) — M3 encryption, export/delete, audit log.
