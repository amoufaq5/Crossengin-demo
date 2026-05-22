# Architecture Decision Records

This directory contains the Architecture Decision Records (ADRs) for the Crossengin project, capturing the design decisions made for v0 and beyond.

ADRs use the Michael Nygard format. A blank template lives at [`0000-template.md`](./0000-template.md). The process for adding, accepting, and superseding ADRs is defined in [ADR-0001](./0001-record-architecture-decisions.md).

## Status legend

- **Accepted** — decision is in force.
- **Accepted (user-overridable)** — decision was contested during the design conversation; the user is decision owner and may revisit.
- **Proposed** — decision drafted but awaiting user ratification.
- **Deprecated** — no longer in force; not superseded by a specific successor.
- **Superseded by ADR-NNNN** — replaced by a specific successor ADR.

## Index

| ADR | Title | Status | Summary |
|-----|-------|--------|---------|
| [0001](./0001-record-architecture-decisions.md) | Record architecture decisions using ADRs | Accepted | Use Michael Nygard ADR format; one decision per file; immutable once accepted. |
| [0002](./0002-project-scope-and-v0-mvp.md) | Project scope and v0 MVP | Accepted | v0 = text+image perception, medicine domain, single-substrate memory, BDI cognitive, probabilistic Visionary, constitutional Soul, cloud-only inference. |
| [0003](./0003-implementation-language-and-stack.md) | Implementation language and primary stack | Accepted (user-overridable) | Python 3.11+ with PyTorch and Rust (PyO3) for hot paths. NOVA explicitly not the implementation language. |
| [0004](./0004-perception-layer.md) | Perception layer | Accepted | v0 text+image, shared SigLIP embedding space, streaming continuous perception, cloud-side. |
| [0005](./0005-knowledge-representation-paradigm.md) | Knowledge representation paradigm | Accepted | Hybrid graph-of-vectors: symbolic typed nodes, vector attributes. |
| [0006](./0006-memory-architecture-and-storage.md) | Memory architecture and storage backend | Accepted | One substrate per user on PostgreSQL 16 + pgvector + Apache AGE. Composite `MemoryItem` schema. |
| [0007](./0007-knowledge-update-policy.md) | Knowledge update policy | Accepted (user-overridable) | Deltas primary; quarantine + signed versioning + periodic rebuild safety net; rebuilds for breaking changes. |
| [0008](./0008-academic-knowledge-module.md) | Academic knowledge module | Accepted | Composite unit (chunk + QA + frame); baked into weights via LoRA; cross-domain edges; v0 domain = medicine. |
| [0009](./0009-cognitive-module-goals-and-action.md) | Cognitive module — goals, planning, action | Accepted | BDI symbolic goals; four initiative triggers; hierarchical planning; fast heuristic consequence predictor; broad action vocabulary; constitutional gate. |
| [0010](./0010-visionary-layer-probabilistic-simulation.md) | Visionary layer — probabilistic simulation and dreams | Accepted | Bayesian-network cause-effect graph (PyMC). Dreams and simulations unified. Imagined-tag containment. |
| [0011](./0011-soul-values-governance.md) | Soul — values governance (three-tier) | Accepted (user-overridable) | Constitutional / developer-tunable / user-configurable; 8 starter constitutional values; v0 enforces constitutional only. |
| [0012](./0012-soul-emotion-taxonomy.md) | Soul — emotion taxonomy | Proposed | OCC 22-type backbone with Plutchik supplement and Russell circumplex projection; v0 implements a subset. Awaiting user ratification. |
| [0013](./0013-soul-consciousness-model.md) | Soul — consciousness model | Accepted | Self-model + narrative thread; engineering definition only; hard problem out of scope. |
| [0014](./0014-soul-behavior-and-personality.md) | Soul — behavior and personality | Accepted | Hand-authored per-deployment personality config (YAML/Pydantic), within developer-authorized bounds; no v0 learning loop. |
| [0015](./0015-deployment-topology-skin-plus-adapter.md) | Deployment topology — per-user skin-plus-adapter | Accepted (user-overridable) | Shared base + per-user encrypted memory + per-user LoRA + per-user soul tuning. Cloud-only v0. |
| [0016](./0016-enterprise-derivation.md) | Enterprise derivation | Accepted | Base + swapped academic content + per-enterprise LoRA. Constitutional layer non-negotiable. v1+ implementation. |
| [0017](./0017-compute-and-infrastructure-runpod.md) | Compute and infrastructure — RunPod | Accepted | RunPod on-demand; A100 80GB for major runs, RTX 4090 for iteration; containerized; cost ledger; cloud inference. |
| [0018](./0018-data-sources-medicine-v0.md) | Data sources for medicine v0 | Accepted | PubMed open subset, MedlinePlus, OpenStax (bio/chem), DailyMed, drugs.gov; provenance metadata mandatory; commercial/NC sources excluded. |
| [0019](./0019-licensing-posture.md) | Licensing posture | Accepted | Strict permissive: Apache 2.0 / MIT / BSD / PostgreSQL / CC-BY only; no GPL family, no NC variants, no Llama license tier. |
| [0020](./0020-nova-evaluation.md) | NOVA evaluation — design inspiration, not implementation language | Accepted | Three structural gaps (GPU kernels, ML bindings, Python interop) preclude NOVA as v0 implementation. NOVA continues as DSL inspiration. Revisit at 12–18 months. |
| [0021](./0021-privacy-and-data-handling.md) | Privacy and data handling | Accepted | Per-user encryption; export/delete primitives; per-session consent for sensors and outside-world actions; opt-in telemetry; audit log. |
| [0022](./0022-evaluation-and-milestone-plan.md) | Evaluation criteria and v0 milestone work plan | Accepted | Three v0 success criteria (medicine QA with calibrated refusal; cross-session memory coherence; constitutional enforcement); six milestones (M1–M6) with definitions-of-done. |

## Contested decisions

Four ADRs are marked **Accepted (user-overridable)**, meaning the user's chosen option differed from the assistant's recommendation during the design conversation. The user is decision owner; both views are recorded in each ADR's "Alternatives considered" section.

- ADR-0003 — implementation stack (user accepted assistant's recommendation; status reflects active negotiation).
- ADR-0007 — knowledge update policy (user chose deltas; assistant recommended incremental).
- ADR-0011 — soul values governance (assistant introduced the three-tier model in response to the user's initial framing; user accepted).
- ADR-0015 — deployment topology (assistant's reading of the user's "per-user skin" phrasing; user invited to confirm).

## Proposed decisions

One ADR is **Proposed** and awaits user ratification before becoming Accepted:

- ADR-0012 — soul emotion taxonomy (OCC backbone + Plutchik supplement + Russell projection).
