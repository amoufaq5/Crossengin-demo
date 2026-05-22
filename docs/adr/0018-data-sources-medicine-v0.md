# ADR-0018: Data sources for medicine v0

## Status

Accepted

## Context

The v0 academic knowledge module is built on medicine (ADR-0002, ADR-0008). Medicine has rich source material, but the source material's licensing varies — some sources are public domain, some are CC-BY (compatible with the strict-permissive posture in ADR-0019), some are CC-BY-NC (non-commercial only — incompatible), and some are paywalled with terms that explicitly forbid model training (incompatible).

The strict-permissive posture requires that every source the academic knowledge pipeline ingests is verified commercial-clearable and research-friendly. This ADR enumerates the v0 candidate sources, their licenses, and how the preprocessing pipeline handles per-record provenance.

## Decision

**Accepted source corpus for v0 medicine domain:**

| Source | License / status | Notes |
|--------|------------------|-------|
| **PubMed open-access subset** | Public domain (US government works) for NIH/NLM-authored content; varying open licenses for author-deposited content | Per-record license metadata required; the ingest pipeline filters to verifiably open-licensed records only |
| **MedlinePlus** | Public domain (US government, NIH/NLM) | Consumer-facing medical information; clean ingest |
| **OpenStax** (biology, anatomy and physiology, chemistry textbooks) | CC-BY 4.0 | Textbook-grade foundational material for the biology and chemistry adjacent to medicine |
| **DailyMed** (FDA structured product labels) | Public domain (US government) | Drug labels with structured fields that map well onto the `Drug` frame schema (ADR-0008) |
| **drugs.gov / drugs@FDA** | Public domain (US government) | FDA-approved drug information |
| **NIH Open Educational Resources** | Mostly public domain or CC-BY | Cross-check per-resource license at ingest |
| **Wikipedia / Wikidata** (medicine-related articles) | CC-BY-SA 4.0 | **Flagged for review.** SA (ShareAlike) is a viral term — derivative works must be re-licensed under CC-BY-SA. Whether weight-baking constitutes a "derivative work" under SA is legally unsettled and the user should make a deliberate call before including. Default for v0 ingest: **excluded** pending the user's decision; the architecture supports its inclusion if the legal posture is clarified |

**Sources flagged but requiring review:**

| Source | Status | Reason |
|--------|--------|--------|
| **WHO publications** | Typically CC-BY-NC-SA | NC (NonCommercial) excludes commercial use; Crossengin's enterprise pathway is commercial. **Excluded** under strict-permissive posture |
| **Wikipedia / Wikidata** | CC-BY-SA 4.0 | See note above |

**Explicitly excluded sources:**

- **UpToDate.** Commercial subscription product; terms explicitly restrict training-use.
- **BMJ, NEJM, The Lancet, and other commercial medical journals.** Subscription content with training-use restrictions.
- **Cochrane Library full reviews.** Subscription content; some abstracts are open but the full reviews are not.
- **Any source whose terms forbid model training, regardless of access cost.**

**Per-record provenance metadata is mandatory.** Every `MemoryItem` representing an academic-knowledge composite record (per ADR-0008) carries in `meta`:

- `source` — canonical source identifier (e.g., `pubmed:PMID12345678`, `dailymed:setid-abc`, `openstax:biology-2e:ch3`).
- `license` — short license tag (e.g., `public-domain-us-gov`, `cc-by-4.0`, `cc-by-sa-4.0`).
- `license_url` — link to the canonical license text.
- `retrieved_at` — timestamp of ingest.
- `pipeline_version` — version of the preprocessing pipeline that produced the record (so we can re-derive if needed, per ADR-0007's rebuild safety net).

The ingest pipeline rejects any source record without complete provenance metadata. Records whose license cannot be determined from the source's metadata are quarantined for manual review rather than ingested.

## Consequences

Positive: every record in the academic knowledge module has a known, verified license. The strict-permissive posture survives the v0 medicine corpus build. Provenance metadata supports both the rebuild safety net (ADR-0007 — re-derive from sources when needed) and downstream auditing (anyone asking "where did the agent learn this?" gets a real answer).

Negative: the accepted corpus is narrower than what is technically available in medicine — paywalled clinical references like UpToDate are widely considered gold-standard and their exclusion lowers the agent's knowledge ceiling in some specialty areas. The CC-BY-SA question on Wikipedia is unsettled and excluding it pre-resolution removes a substantial chunk of general-medicine content from v0.

Neutral: the v0 success criterion (ADR-0022) is measurable against the accepted corpus, not against a theoretical full-medical-knowledge corpus. The narrower the source set, the easier it is to define what the agent should and should not know.

## Alternatives considered

**Include CC-BY-NC sources (with a separate non-commercial fork).** Considered. Rejected: a fork that diverges between commercial and non-commercial trained weights doubles maintenance burden and creates a foot-gun for future enterprise deployments. Cleaner to exclude NC sources entirely.

**Include Wikipedia by default.** Considered. The CC-BY-SA "viral derivative" question is real enough to require the user's deliberate call. Defaulting to exclusion is the conservative choice; the user is invited to revisit.

**Include paywalled commercial sources via license negotiation.** Out of scope for v0 (un-funded by design per ADR-0017; license negotiation requires legal counsel and budget). Revisitable when the funding picture changes.

**Include arbitrary scraped web medical content.** Rejected: most has no clean license, and the strict-permissive posture forbids it.

## Open questions

- The user's decision on Wikipedia / Wikidata inclusion under CC-BY-SA. The conservative default is to exclude; the user can review and override.
- Whether OpenStax chemistry and biology should be ingested in full or selectively. v0 default: selective — only chapters relevant to the chosen v0 sub-area of medicine (e.g., hypertension-relevant cardiovascular physiology). Finalized at M4.
- License-classifier policy for PubMed records whose deposit metadata is incomplete. v0 default: quarantine for manual review. M4 may add a license-classifier model if manual review volume is unmanageable.
- Cadence for re-ingesting source updates (new PubMed records, new DailyMed labels). Initial cadence: monthly per source. Finalized at M4.

## References

- ADR-0002 (Project scope) — medicine as the v0 academic domain.
- ADR-0007 (Knowledge update policy) — the rebuild safety net depends on provenance metadata defined here.
- ADR-0008 (Academic knowledge module) — the composite-record form into which sources are preprocessed.
- ADR-0019 (Licensing posture) — the green-list / red-list filter this ADR enforces for medicine sources.
- ADR-0021 (Privacy) — user data, separate from source data, has its own provenance discipline.
- ADR-0022 (Evaluation and milestones) — M4 medicine source ingest milestone.
