# ADR-0016: Enterprise derivation

## Status

Accepted

## Context

Crossengin's deployment thesis is two-pronged: the personal-companion mode for individuals (per-user skin-plus-adapter, ADR-0015) and a "company brain" mode for enterprises. The enterprise mode reuses the base architecture but specializes it to the enterprise's domain and data.

The user has specified the enterprise derivation mechanism: modular swap of the academic-knowledge content for the enterprise's domain, plus fine-tuning of the resulting model on enterprise-specific data. The intent is that an enterprise gets a Crossengin-derived model that knows their domain deeply and operates on their data with their governance bounds, rather than a generic model lightly customized.

Enterprise deployment is **not in v0 scope** (per ADR-0002). v0 builds the architecture; the enterprise derivation pipeline is built on top of that architecture at v1+. This ADR documents the design so that v0 implementation decisions do not foreclose the v1+ enterprise path.

## Decision

**Enterprise model artifact = (base model) + (swapped academic-knowledge content) + (per-enterprise LoRA adapter).**

The three components:

1. **Base model.** Same as in personal-companion deployments. Identical weights, identical architecture, identical Soul-layer constitutional bounds. The constitutional layer (Tier 1, ADR-0011) is non-negotiable; it applies in enterprise variants exactly as it applies in personal-companion variants.

2. **Swapped academic-knowledge content.** The composite academic-knowledge records (ADR-0008) for the enterprise's domain replace the generic-domain content. The graph-of-vectors substrate is the same; only the loaded content differs. Cross-domain edges from the enterprise domain into adjacent permissive-source domains (e.g., a legal-tech enterprise that needs to reach into general computing knowledge) are preserved.

3. **Per-enterprise LoRA adapter.** A fine-tuned adapter trained on the enterprise's data. Similar mechanism to the per-user LoRA in ADR-0015, but at the enterprise granularity rather than the individual granularity.

**Enterprise governance:**

- The **constitutional layer (Tier 1) is the same** as in personal-companion deployments. The enterprise cannot override it. This is the contract the architecture makes with the end users the enterprise's deployed model serves — values like "do not deceive about being an AI system" and "do not facilitate harm" do not change because a paying enterprise has bought the deployment.
- The **developer-tunable layer (Tier 2)** is configured by the enterprise within constitutional bounds. The enterprise's Tier 2 includes its domain-specific behavior policies, required disclosures, and tonality defaults.
- The **user-configurable layer (Tier 3)** is available to end users of the enterprise's deployment within whatever bounds the enterprise (as Tier-2 developer) authorizes.

**Per-employee skins (optional feature, off by default).** By default, an enterprise deployment serves all its end users from the same enterprise-LoRA-adapted base, with per-user state in Tier 3 only (preferences, no per-user adapter). The enterprise can opt into per-employee skins — adding per-employee LoRA adapters and per-employee encrypted memory — as a feature. The architecture supports it; it is not the default.

**Enterprise data handling.**

- All ADR-0021 privacy commitments apply to enterprise-end-user data exactly as they apply to personal-companion users.
- Enterprise data used for the per-enterprise LoRA training is the enterprise's responsibility under the enterprise's data agreements; Crossengin's pipeline encodes the same provenance metadata requirements as for the public academic-knowledge sources (ADR-0018) but does not enforce the same license filter (enterprises train on their own data under their own terms).
- Audit logs and amendment-process trails (ADR-0011) are available to the enterprise.

## Consequences

Positive: the enterprise path reuses every component of the architecture — base model, memory substrate, cognitive module, Visionary, Soul. The only enterprise-specific artifacts are the swapped academic content and the per-enterprise LoRA. This means v0 work directly supports enterprise readiness without enterprise-specific engineering. The constitutional bound preservation means Crossengin's safety floor is the same regardless of who is paying — enterprises do not get to weaken it.

Negative: "swap academic-knowledge content" is a clean phrase but a non-trivial operation in practice. The ingest pipeline (ADR-0008) has to work for arbitrary enterprise domains, which means the source-preprocessing tooling needs to be flexible. The enterprise's data licensing (their own data, under their own terms) opens questions the strict-permissive posture (ADR-0019) does not directly answer — those questions are punted to the enterprise's data agreement with Crossengin.

Neutral: enterprises that want to fully control their model's value structure beyond Tier-2 bounds are not Crossengin's customers. The constitutional layer is the architecture's commitment; an enterprise that wants to violate it has to find a different vendor.

## Alternatives considered

**Per-enterprise full fine-tune from scratch** (no base model sharing). Maximally specialized; rejected on cost and on the loss of the shared-base benefits (one safety floor, one update mechanism, one inspection surface).

**Per-enterprise instance with their own deployment of the entire architecture** (separate base model, separate everything). Considered. Some enterprises (regulated industries) may require this for compliance reasons. Architecture supports it (the whole stack is open-source under the strict-permissive posture, and the enterprise can self-host) but the Crossengin offering by default is the shared-base-plus-adapter variant.

**No constitutional bound preservation** (enterprise can override Tier 1). Rejected as antithetical to the project's safety thesis. The constitutional layer is non-negotiable.

**Per-employee skins by default** (rather than opt-in). Rejected on cost — the enterprise pays in compute for every adapter, and for many enterprise use cases (call-center support, internal knowledge base, etc.) per-employee personalization adds little value over per-enterprise specialization.

## Open questions

- Specifics of the enterprise data agreement template — what Crossengin commits to, what the enterprise commits to, what happens to enterprise data on contract termination. Out of scope for v0; needs an enterprise-specific ADR set when the v1+ enterprise path opens.
- Audit-log granularity for enterprise deployments. v0 default: same as personal-companion. Enterprise-specific requirements (e.g., regulatory audit) are addressed when concrete enterprises engage.
- Whether per-enterprise variants share the base model's update cadence or can pin to a base version. Initial design: enterprises can pin, with security-fix exceptions. Finalized when v1+ enterprise pipeline is built.

## References

- ADR-0002 (Project scope and v0 MVP) — enterprise derivation explicitly out of v0 scope.
- ADR-0008 (Academic knowledge module) — the swap mechanism's source-side machinery.
- ADR-0011 (Soul values governance) — the three-tier governance enterprise deployments inherit.
- ADR-0015 (Deployment topology) — the personal-companion variant of skin-plus-adapter that enterprise variants generalize from.
- ADR-0018 (Data sources) — license discipline that applies to public academic sources; enterprise data is on enterprise terms.
- ADR-0019 (Licensing posture) — Crossengin's project license is permissive; enterprises can self-host if they need to.
- ADR-0021 (Privacy) — applies to enterprise-end-user data identically.
