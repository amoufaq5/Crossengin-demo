# ADR-0017: Compute and infrastructure — RunPod

## Status

Accepted

## Context

Crossengin needs GPU compute for two distinct workloads: training (preprocessing pipelines, LoRA fine-tunes, evaluation runs) and inference (serving the model to users). The team is small and the project is un-funded by design — the user has stated an explicit intent to reach a clearer use-of-money milestone before raising. This rules out fixed-cost GPU clusters and managed-AI-platform commitments.

On-demand GPU rental is the natural fit. RunPod is the user's chosen provider for v0 — it offers community-cloud GPU instances at lower-than-major-cloud rates, supports the container workflow the team prefers, and has the GPU models the project needs (A100 80GB for training-grade work, RTX 4090 24GB for cheaper iteration).

## Decision

**Compute platform: RunPod, on-demand GPU rental.**

**Training compute targets:**

- *Full-corpus LoRA fine-tunes and longer training runs:* RunPod **A100 80GB community-cloud** instance. Approximate rate at the time of decision: $1.50–$2.00 per hour. Used for batched re-derivation cycles (per ADR-0007 and ADR-0008) and the major training milestones in ADR-0022.
- *Iteration and LoRA-only experiments:* RunPod **RTX 4090 24GB** instance. Significantly cheaper per hour. Used for short development cycles where the larger memory footprint of an A100 is not needed (small LoRA experiments, evaluation runs, preprocessing-pipeline shakedowns).

Training runs are **batched jobs, not always-on**. The container is spun up, the job runs, the artifact is exported to durable storage (model weights, evaluation outputs, training logs), the container is spun down. No continuous training infrastructure.

**Inference compute target for v0: cloud.** RunPod-hosted inference behind a small inference service. Edge / on-device inference is deferred to v1+ (per ADR-0004 and ADR-0015).

**Container approach.** Every workload is a Docker image with the Python + PyTorch + Rust toolchain pinned. Image build is reproducible (lockfile-pinned `uv` dependencies, pinned base image, pinned CUDA version). Images are versioned. The base Docker image is shared across training and inference containers to minimize divergence between them.

**Data-mount strategy.** RunPod containers are ephemeral. Persistent data (model artifacts, training datasets, evaluation outputs, the PostgreSQL+pgvector+AGE substrate for development) lives in durable storage outside the container — a RunPod network volume or an external object store. Containers mount what they need at startup and write artifacts back at completion. PostgreSQL itself runs in a persistent container with its data on a durable network volume; backups are taken before each significant migration or change.

**Cost-tracking discipline.** Every training run logs its (hours × $/hr) cost to a running ledger. The ledger is reviewed at every milestone closeout (per ADR-0022). The discipline is part of the un-funded-by-design constraint: the team needs to know what each milestone has cost in compute, to be able to talk about cost discipline credibly when fundraising.

**Failover and reliability.** No multi-region failover in v0; the personal-companion-for-every-citizen scale that would justify it is a v1+ concern. v0 ships with the assumption that occasional RunPod-side outages are acceptable degraded-service modes. The inference service is structured so that user requests during an outage return a clean "I'm unavailable right now" rather than failing silently.

## Consequences

Positive: pay-only-for-what-you-use is the right cost model for an un-funded bootstrap. RunPod's pricing is among the cheapest per-GPU-hour available for the GPU classes the project needs. Containerized workloads are portable — if RunPod becomes the wrong provider later, the workloads move with relatively low friction. Batched-training discipline keeps the compute bill predictable.

Negative: on-demand cold starts add latency to training jobs (a few minutes per spin-up). RunPod community cloud has occasional capacity issues for popular GPU classes; jobs may queue or need to fall back to a secondary GPU class. No multi-region failover means a RunPod outage is a service outage. Inference at v0 is cloud-only, which means user-side latency is bounded by network round-trips.

Neutral: the cost-tracking ledger is overhead, but it is the kind of overhead that pays for itself the moment any cost-related question is asked.

## Alternatives considered

**Major cloud providers** (AWS, GCP, Azure). Better SLA, broader service ecosystem (managed PostgreSQL, managed queues, etc.), but per-GPU-hour pricing 2-4× RunPod community cloud rates. Rejected for v0 on cost. Revisit when the funding picture changes.

**Dedicated owned GPU hardware.** Lowest marginal cost per hour but high capex. Rejected on the un-funded-by-design constraint and on the team's preference to avoid hardware ownership at this stage.

**Other on-demand GPU rental providers** (Lambda, Vast.ai, others). Considered. RunPod is the user's chosen default; alternatives stay on the bench as backup providers if RunPod has sustained capacity issues. No second-provider integration in v0 — single-provider operational simplicity wins until it doesn't.

**Always-on training infrastructure.** Rejected on cost and on the architectural fit — training is naturally batched per ADR-0007's update cadence.

**Edge inference at v0.** Rejected per ADR-0004 and ADR-0015 — adds substantial engineering (model packaging, quantization, on-device runtime) without delivering a v0-distinguishing capability.

## Open questions

- Whether the inference service is colocated with the PostgreSQL substrate on the same RunPod instance (lower latency, smaller blast radius for outages) or split (better resource isolation, more network hops). Resolved at M1 (infrastructure milestone) per ADR-0022.
- Backup cadence and retention for the development PostgreSQL substrate. Initial heuristic: daily snapshot, 30-day retention. Finalized at M1.
- Cost-tracking ledger format and storage. Simple v0 default: a CSV file in durable storage, one row per run. Sufficient for v0; revisitable at v1.

## References

- ADR-0002 (Project scope) — un-funded by design, v0 scope.
- ADR-0006 (Memory architecture) — the PostgreSQL substrate that runs on the RunPod infrastructure.
- ADR-0007 (Knowledge update policy) — the rebuild safety net's compute budget lives here.
- ADR-0008 (Academic knowledge module) — LoRA fine-tune cadence and cost.
- ADR-0015 (Deployment topology) — per-user adapter compute, bounded by this ADR's budgets.
- ADR-0019 (Licensing posture) — every dependency in the container is permissively licensed.
- ADR-0022 (Evaluation and milestones) — M1 infrastructure milestone definition-of-done.
