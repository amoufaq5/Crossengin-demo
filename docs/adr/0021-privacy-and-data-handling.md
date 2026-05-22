# ADR-0021: Privacy and data handling

## Status

Accepted

## Context

Crossengin is intended as a personal companion that lives alongside its user with persistent per-user memory, optional access to camera and microphone (in v1+), and a soul layer that personalizes to the user's preferences. Every one of those capabilities is a privacy concern unless explicit data-handling discipline is in place.

Constitutional value #5 (ADR-0011) commits the agent to preserving user privacy by default. That commitment needs operational backing — concrete storage encryption, consent flows, audit logs, retention policies, data-portability primitives. This ADR is the operational backing.

## Decision

**1. Per-user encryption at rest.**

- Every per-user `MemoryItem` row (per ADR-0006) is encrypted with a key derived from the user's identity.
- The encryption scheme is row-level on the sensitive columns (`raw_refs`, `triples`, `frames`, `narrative`, `vector`, `meta`).
- Key management: per-user keys are derived from a user-specific secret held outside the application database (e.g., in a dedicated key-management service or a per-user envelope encrypted with a master key whose access is audited). The specific KMS choice is finalized at M3 (ADR-0022).
- The model's base weights and academic-knowledge content are not user-specific and are not encrypted with per-user keys.

**2. User data ownership: export and delete primitives.**

- Every user can export their full data: all `MemoryItem` rows, all per-user soul tuning, all per-user LoRA adapter weights, all audit-log entries pertaining to them. Export format: a documented archive (JSON for structured data, binary for model weights) with a stable schema.
- Every user can delete their full data. Delete means: irreversible removal from primary storage, irreversible removal from backups within a documented backup-retention window (specified below), and a tombstone in the audit log recording that the deletion happened.
- Delete includes the per-user LoRA adapter. The base model is unaffected (it does not contain user-specific information that survives the adapter).

**3. Consent for high-stakes data sources.**

- Camera and microphone access (v1+) require explicit per-user opt-in **per session** (not a global once-and-done consent). Each session's audit log records the consent grant.
- Tool calls and actions that touch the outside world (sending messages, contacting third parties, executing transactions — constitutional value #4 territory) require explicit, contemporaneous user consent for each instance, not a blanket prior authorization.
- Use of user data for training (per-user LoRA adapter training) requires the user's informed opt-in. The opt-in describes what data is used, how it changes the agent's behavior, and how the user can revoke and retrain from a clean adapter base.

**4. No third-party sharing without consent.**

- User data is not shared with third parties without explicit, recipient-specific consent.
- Aggregate analytics over user data is opt-in. Default is no aggregate participation.
- Telemetry sent to the project's operational logging is scoped to non-content data (timing, error class) and never includes the user's content or per-user identifiers without explicit user opt-in.

**5. Data minimization and retention.**

- The agent collects only what is needed for the declared interaction. Streaming perception buffers are not persisted unless they produce a `MemoryItem`; ephemeral perception is discarded after processing.
- Default retention: user data persists for as long as the user maintains an active account. The user can truncate (delete older-than-N memory items) at any time through the export/delete primitives above.
- Backup retention: backups containing user data are retained for **30 days** by default after the backup is taken. After 30 days, backup data ages out and is unrecoverable, including for restoring deleted user data. A user-initiated delete is propagated through backups within the 30-day window.
- Provenance logs (which sources informed which derived knowledge) are retained beyond the user-data retention window where they pertain to the academic-knowledge corpus (not user-specific).

**6. Audit log for constitutional and consent decisions.**

- Every constitutional-gate decision (per ADR-0011, ADR-0009) is logged: the candidate action, the constitutional value(s) invoked, the outcome (allow / modify / block).
- Every consent grant or revocation is logged.
- Every developer-tunable layer (Tier 2 in ADR-0011) change is logged with the developer's identity, timestamp, and rationale.
- The audit log is per-user-retrievable for the parts pertaining to the user.
- The audit log is non-modifiable post-write (append-only).
- Audit-log retention: as long as user data is retained. Audit log is included in the user's export bundle.

**7. Encrypted-in-transit.**

- All network traffic between the user and the inference service is TLS-encrypted. Modern cipher suites only.
- Internal traffic between the inference service and the memory substrate uses connection-level encryption.

**8. Camera / microphone permission scoping (forward-looking for v1+).**

- v0 does not use camera or microphone (text + image inputs are uploaded files or pasted content, not live captures).
- For v1+ when live audio is added: per-session consent, visual indicator when capture is active, "stop" primitive always available, no background capture, no capture-while-screen-locked.
- For v2+ when live video is added: same principles, with the additional constraint that any face recognition or person identification across the captured frames requires its own separate explicit consent.

## Consequences

Positive: the agent's privacy posture is operationalized rather than promised. Constitutional value #5 has concrete backing. Users have real ownership of their data (export and delete primitives are not aspirational). Audit logs make constitutional-gate behavior reviewable, which supports trust and supports legitimate research/audit by external reviewers.

Negative: per-user encryption with KMS-managed keys is more infrastructure than v0 strictly needs at small scale. Per-session consent flows for camera/mic add friction that some users will dislike (especially the "no global once-and-done" rule). Delete primitives that propagate through backups within 30 days require backup tooling that respects deletions; this is engineering work, not free.

Neutral: the 30-day backup retention is a balance between operational safety (we can recover from a recent failure) and user-data control (deleted means deleted within a bounded window). The number is tunable.

## Alternatives considered

**Server-side encryption at the disk level only** (no per-user row-level encryption). Simpler, but does not protect against a database-level breach where the attacker has access to the running database. Per-user row-level encryption is the stronger property.

**Once-and-done consent for camera/microphone.** Lower friction, but allows quietly-running background capture that the user has forgotten about. Per-session consent is the more honest posture.

**No backup retention** (delete means immediately gone everywhere). Operationally fragile — a database corruption event could destroy user data with no recovery. The 30-day backup window with delete propagation is the balance.

**Telemetry on by default, opt-out.** Industry default, but at odds with constitutional value #5. Opt-in only is the principled choice.

**Allow aggregate analytics over user data by default.** Same concern; opt-in only.

## Open questions

- Specific KMS choice for per-user key management (HashiCorp Vault, AWS KMS via a permissively-licensed client, in-house). Finalized at M3 (ADR-0022); permissive-license filter from ADR-0019 applies.
- Whether per-user data is geographically scoped (e.g., EU users' data must be stored in EU regions). v0 default: single-region storage; geographic scoping added when there is a user population in regions that legally require it.
- Concrete archive schema for the export bundle. Finalized at M3.

## References

- ADR-0006 (Memory architecture) — the per-user encryption is enforced at the storage layer specified there.
- ADR-0009 (Cognitive module) — the constitutional gate whose decisions this ADR requires logging.
- ADR-0011 (Soul values governance) — constitutional values #4 (consent for irreversible) and #5 (privacy) that this ADR operationalizes.
- ADR-0015 (Deployment topology) — per-user adapter and per-user memory live within this privacy regime.
- ADR-0016 (Enterprise derivation) — enterprise-end-user privacy commitments are the same.
- ADR-0017 (Compute and infrastructure) — backup-tooling implications.
- ADR-0019 (Licensing posture) — KMS choice constrained by permissive license filter.
- ADR-0022 (Evaluation and milestones) — M3 for per-user encryption, export/delete primitives, KMS integration.
