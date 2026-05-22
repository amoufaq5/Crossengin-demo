# ADR-0015: Deployment topology — per-user skin-plus-adapter

## Status

Accepted (user-overridable)

## Context

Crossengin's intended deployment story includes a personal-companion mode in which every user has "their own" Crossengin — an agent that lives alongside them, remembers them, develops a personalized soul, and operates with their values within the project's constitutional bounds. The phrase the user used during the design conversation is "per-user skin."

The phrase is ambiguous. "Skin" could mean:

- **Pure skin.** A frozen shared base model with user-specific configuration applied at session start (system prompt, preferences, context window contents). All persistence between sessions lives in external memory; the model weights are identical for every user.
- **Skin-plus-adapter.** A frozen shared base model plus per-user durable personalization that survives session boundaries — per-user encrypted memory (which the user has explicitly required, ADR-0006 and ADR-0021), and per-user fine-tuning weights (a LoRA adapter) that adjusts the base model's behavior in user-specific ways, and per-user soul tuning (Tier 3 user-configurable values from ADR-0011, plus per-user personality overrides from ADR-0014).

The user has explicitly required per-user encrypted memory and Tier-3 user-configurable values. Those alone exceed what "pure skin" can support — encrypted per-user memory is not a session-context artifact, it is durable per-user storage. The user's brief responses to clarification on this point pointed toward the skin-plus-adapter interpretation, but did not name it explicitly.

The assistant's reading is that skin-plus-adapter matches the user's expressed needs. This ADR documents that interpretation and lays out the alternatives; the user remains the decision owner and is invited to confirm or correct.

## Decision

**Per-user deployment topology: skin-plus-adapter.**

- **One shared base model.** A single set of base weights, identical across all users in a given deployment. Updated by the developer on a release cadence (Tier-2 developer-tunable layer per ADR-0011); not user-specific.
- **Per-user encrypted memory store.** Per ADR-0006: each user has their own row-level-encrypted slice of the PostgreSQL+pgvector+AGE substrate, holding their `MemoryItem` rows.
- **Per-user LoRA adapter.** A small set of low-rank fine-tune weights specific to the user, applied to the base model at session start. The adapter is trained on user-specific interactions on a cadence (initial: per-week or per-N-interactions; tuned at M5). v0 ships with the adapter mechanism in place but the automated training loop is deferred (per ADR-0002, this is in scope to *support* but not to *automate*).
- **Per-user soul tuning.** Tier-3 user-configurable values (ADR-0011) and per-user personality overrides (ADR-0014), stored alongside the user's memory slice, applied at session load.

**Session load is:** fetch the user's encrypted memory, attach their LoRA adapter to the base model, apply their Tier-3 soul configuration. Detach at session end (or on inactivity timeout). The base model is shared infrastructure; the user's skin-plus-adapter is the personalization layer.

**Inference is cloud-only in v0** (per ADR-0017's RunPod constraint). Edge / on-device inference is a v1+ deferred decision.

## Consequences

Positive: per-user personalization is real and durable — the agent remembers the user across sessions, learns user-specific patterns via the adapter, respects user-specific values within constitutional bounds. The shared base model means the developer's update cadence affects all users (one fine-tune cycle improves everyone), which is operationally cheap. Per-user memory encryption (ADR-0021) is enforced at the storage layer. Adapter weights are small enough to ship and load per session without unreasonable cost.

Negative: per-user LoRA training has a compute cost that scales with the user population. Even at v0 scale (small population), this is a non-trivial budget line on RunPod (ADR-0017). Per-user adapter loading at session start adds latency (mitigated by pre-warming for active users). Adapter drift over a user's lifetime needs governance — an adapter that has been training for a year on noisy interaction signal can drift toward unhelpful patterns; the rebuild discipline (ADR-0007) and constitutional gate (ADR-0011) are the mitigations.

Neutral: enterprise deployments (ADR-0016) do not use per-user skin-plus-adapter by default — they use a per-enterprise variant of skin-plus-adapter where the "user" granularity is the enterprise, not the individual employee. Per-employee skins are a feature an enterprise can opt into; not the default.

## Alternatives considered

**Pure skin** (frozen base + session-time configuration only, no per-user adapter). Lower compute cost. Rejected because it cannot deliver the durability of personalization the user has required — per-user memory and Tier-3 soul are durable, and pure-skin would leave the model's weights unable to specialize to any user.

**Per-user full fine-tune** (every user gets their own complete copy of all model weights). Rejected: storage cost and training cost are prohibitive even at small user scale. LoRA adapters give most of the personalization benefit at a fraction of the cost.

**Per-citizen instance** (one model per user, deployed standalone). The most personalized possible topology. Rejected for v0 on compute cost — running a separate model instance for every user on RunPod is operationally untenable for a small-team bootstrapped project. Becomes plausible if edge inference (v1+) matures to the point where each user's instance runs on their own device.

**Pure server-side stateless** (no per-user state at all). Rejected as an architectural antithesis to the personal-companion thesis. Trivially fails the cross-session memory coherence success criterion in ADR-0022.

## Open questions

- Cadence and trigger for per-user LoRA training: per-week, per-N-interactions, on-demand, only at user request? v0 default: deferred (the mechanism ships, the automation does not). Finalized in v1.
- Adapter-drift detection and reset policy. v0 default: developer can review per-user adapters and reset to base if drift is detected; user can request reset. Automated drift detection is v1+.
- Adapter loading latency budget per session. Initial target: under 2 seconds for cached users, under 10 seconds for cold users. Measured and tuned at M5.

This ADR's status is **Accepted (user-overridable)** because the "skin-plus-adapter" interpretation of the user's brief "per-user skin" phrasing was the assistant's reading; the user is invited to confirm, refine, or correct. The user is decision owner on the topology.

## References

- ADR-0006 (Memory architecture) — per-user encrypted memory store.
- ADR-0011 (Soul values governance) — Tier-3 user-configurable values.
- ADR-0014 (Soul behavior and personality) — per-user personality overrides.
- ADR-0016 (Enterprise derivation) — the enterprise variant of this topology.
- ADR-0017 (Compute and infrastructure) — RunPod cloud-only constraint.
- ADR-0021 (Privacy) — per-user encryption is enforced at the storage layer.
- ADR-0022 (Evaluation and milestones) — M5 for adapter mechanism integration; cross-session memory coherence success criterion.
