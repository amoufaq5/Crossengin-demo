# ADR-0094: Security architecture and threat model for the truth-seeking engine

## Status

Proposed

## Date

2026-06-15

## Context
CrossEngin already carries real security machinery, but it was scoped to the v1
desktop companion (ADR-0046) and the v2 single-tenant pilot (ADR-0047): a crypto
suite in `src/safety/` (AES-GCM, ChaCha20-Poly1305, Ed25519, ECDSA/P-256, RSA,
SHA family, X.509 verification, PEM truststore), a constitutional filter
(ADR-0045), permission tiers (ADR-0041), an override mechanism with a
reversibility classifier (ADR-0044), differential privacy and secure aggregation
for federation, per-tenant process isolation (ADR-0047), and an RFC-grade
transport (DTLS/TLS/SCRAM). Those are primitives and per-feature controls — they
are **not** a consolidated threat model for the expanded system.

The truth-seeking expansion (ADR-0086) widens the attack surface in ways the
existing controls do not fully cover. A knowledge base that **updates itself from
the open web** (ADR-0092, r50) invites data poisoning. A **structured reasoning
engine** (ADR-0089) is an attackable artifact. A **durable storage engine**
(NOVA-0007) and **distributed consensus** (NOVA-0008) add at-rest and cluster
attack surfaces that do not exist on a single text file. **Tiered editions**
(ADR-0091) ship onto hardware we do not control (Edge), where the build manifest
becomes a security-relevant artifact. And Rule 1 (NOVA everywhere) means we own
the security of the *entire* stack with no externally hardened libraries to lean
on — the burden and the control are both total. This ADR exists to name the
threats once, authoritatively, and to assign each a control, so later phases
inherit a model instead of re-deciding security ad hoc.

## Decision
We adopt a **consolidated threat model with a control per surface**, defense-in-
depth, and **provenance-backed reversibility** as the unifying principle: because
every atom is sourced, graded, and licensed (ADR-0087) and every belief change is
logged (ADR-0043), a successful attack on the knowledge base is *traceable and
reversible* (ADR-0025 death, ADR-0044 override) rather than silent and permanent.
The surfaces and their controls:

1. **Knowledge poisoning (highest novel risk).** Adversarial or low-quality
   sources feeding false facts through the autonomous loop. *Controls:* the
   governed promotion gates of ADR-0092 (license, corroboration, conflict-freeze,
   debate adjudication) sit between CANDIDATE and PROMOTED; source tiering
   (ADR-0029) weights evidence; the provenance ledger (ADR-0087) makes every
   promoted atom traceable to its sources and reversible; CONTESTED flagging
   (ADR-0023) refuses silent overwrite of high-confidence/user-taught atoms.
   *Residual risk (accepted):* coordinated multi-source poisoning can still move a
   belief; mitigated — not eliminated — by source diversity requirements,
   track-record-based tiering (ADR-0029 future work), and anomaly detection on
   abnormal belief-shift velocity. We treat this as the engine's defining
   security problem and never claim it solved.

2. **Reasoning/argument manipulation.** Inputs crafted to produce a misleading
   argument graph or to exploit acceptability semantics. *Controls:* bounded
   argument-graph size (ADR-0089); `FORMAL`/strict arguments (ADR-0088) cannot be
   defeated by defeasible attacks, anchoring conclusions in checkable proof where
   the domain allows; the full argument trace is audited (ADR-0043), so a
   manipulated conclusion is inspectable after the fact.

3. **Storage at rest and integrity (NOVA-0007).** *Controls:* encryption at rest
   for sensitive partitions; checksums (already specified in NOVA-0007 for
   corruption) extended to tamper detection; WAL and snapshot integrity
   (signed/authenticated checkpoints) so an offline edit to the store is
   detectable on recovery.

4. **Distributed/consensus surface (NOVA-0008).** Raft is crash-fault-tolerant,
   **not Byzantine-fault-tolerant** — a *compromised* node is a real, accepted
   limitation for now. *Controls:* mutual node authentication reusing the existing
   federation crypto (DTLS/SCRAM/Ed25519/X.509); per-tenant isolation (ADR-0047)
   preserved across the cluster, not just within a process; split-brain resolved
   by Raft safety (no two leaders commit conflicting entries).

5. **Edition manifest tampering (ADR-0091).** The manifest decides which KG
   partitions load (clean vs. quarantine) and whether outbound research runs — so
   repackaging an Edge build could smuggle in quarantined atoms or enable
   research on a customer device. *Controls:* the manifest is signed and verified
   at build and load time; an Edge build provably excludes the ADR-0087 quarantine
   partition (the existing ADR-0091 test) and provably has no fetch path.

6. **Multi-tenant isolation (ADR-0047).** *Controls:* the OS process boundary
   remains the isolation primitive; NOVA-0007/0008 must not create a shared-store
   or shared-log path that crosses tenants — isolation is asserted at the storage
   and consensus layers, not only in the substrate.

7. **Constitution & self-update integrity (ADR-0045, ADR-0092).** The agent must
   not autonomously edit its constitution, soul, or its own safety gates.
   *Controls:* constitutional rules are hard, non-revisable inhibitory signals
   (ADR-0045); ADR-0092 explicitly refuses and logs any self-update touching them.

8. **Privacy.** *Controls:* differential privacy and secure aggregation (existing)
   for any federated learning; data minimization; PII/secret handling during
   ingestion (don't mint atoms from credentials/PII); license screening (ADR-0087)
   doubles as a content-provenance gate.

9. **Supply chain / trust root.** Rule 1 (no third-party deps) sharply reduces
   supply-chain exposure, but the assembly bootstrap seed and the self-hosting
   toolchain become the trust root. *Controls:* the `stage2.s == stage3.s`
   self-hosting invariant (NOVA ADR-0002) is reused as a build-integrity check;
   reproducible builds; the proof-checker kernel (ADR-0088) is kept tiny and
   auditable precisely so it can be trusted.

10. **Sensory boundary.** The STT/TTS bridge (ADR-0014, enhancement #14) is also a
    security boundary: untrusted audio/text enters there. *Controls:* the bridge
    isolation already mandated by ADR-0014 (no cognition path through it) is a
    security control, not only a purity control.

## Options Considered
- **Per-feature security, no unifying model (rejected).** Cheapest near-term, but
  leaves gaps at the seams (e.g. nobody owns cross-layer tenant isolation) and
  makes "is it secure?" unanswerable. The expansion's new surfaces demand a model.
- **Treat the existing crypto suite as "security" (rejected).** Primitives are
  necessary, not sufficient; ciphers do not address poisoning, manifest
  tampering, or consensus trust. Conflating the two is the trap this ADR avoids.
- **Adopt an external security framework / hardened libraries (rejected).**
  Violates Rule 1 and surrenders the auditable zero-dependency posture; we instead
  build controls natively on the existing crypto leaves.
- **Consolidated threat model + per-surface controls + provenance-backed
  reversibility + a phase-gating security review (CHOSEN).** Most work, but the
  only option that is coherent, auditable, and honest about residual risk; it also
  turns the worst case (poisoning) from a silent corruption into a traceable,
  reversible event.

## Consequences
- **Positive:** One coherent, auditable model; defense-in-depth across cognition,
  storage, consensus, and deployment; provenance + audit make knowledge attacks
  *recoverable*; reusing the self-hosting invariant gives a cheap build-integrity
  check; Rule 1 shrinks supply-chain exposure.
- **Negative:** Data poisoning is never fully solved and we say so; owning the
  whole stack's security with no hardened external libraries is a heavy load for a
  small team; Raft is not Byzantine-tolerant, so a compromised cluster node is an
  accepted risk pending future work; every ADR-0086 phase now carries a security-
  review gate, which is real overhead.
- **Future work:** Byzantine-fault-tolerant consensus once the cluster grows
  beyond trusted operators; formal verification of the proof-checker kernel
  (ADR-0088) and of tenant isolation; structured red-teaming of the autonomous
  loop (a poisoning corpus); a coordinated-disclosure / bug-bounty process once
  any edition ships publicly.

## Implementation Notes
- Maintain a living `docs/design/threat-model.md` enumerating surfaces, controls,
  residual risks, and owners; add a **security-review gate** to each ADR-0086
  phase (no phase ships without its surfaces reviewed against this ADR).
- Map controls to existing modules: poisoning → ADR-0092 promotion state machine +
  ADR-0029 tiers; at-rest → NOVA-0007 (encryption + checksums + signed
  checkpoints); node auth → `src/safety/` X.509/Ed25519/SCRAM over the federation
  transport; manifest → ADR-0091 build tooling (sign + verify); constitution →
  `src/safety/constitutional_filter.nova` + ADR-0045; privacy →
  `src/safety/differential_privacy.nova` + secure aggregation.
- Testing: a poisoning red-team fixture (a coordinated false-claim source set must
  be caught or flagged CONTESTED, never silently promoted); a manifest-tamper test
  (an Edge build with the quarantine partition re-added fails verification); an
  at-rest tamper test (an offline store edit is detected on NOVA-0007 recovery); a
  cross-tenant isolation test extended to the storage/consensus layers (ADR-0047);
  a self-update-refusal test for constitution edits (ADR-0092).
- DEPENDS ON: the existing `src/safety/` crypto leaves; NOVA-0007 (at-rest
  encryption + integrity), NOVA-0008 (node authentication + isolation); NOVA
  enhancement #9 (crash-safe audit log). No new cipher primitive required.
