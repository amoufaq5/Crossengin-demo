# ADR-0019: Licensing posture

## Status

Accepted

## Context

Crossengin's intended deployment includes commercial enterprise derivatives (ADR-0016) and research use by external collaborators. The project must remain commercial-clearable and research-friendly across its entire dependency tree — every Python package, every Rust crate, every database extension, every dataset, every model checkpoint used as a starting point or training input.

This is not a posture that can be adopted retroactively. A single GPL-family dependency adopted in v0 propagates licensing obligations through the rest of the stack and is genuinely hard to extract once it's wired into core paths. A single CC-BY-NC dataset baked into model weights forecloses every commercial deployment. License discipline has to be a from-day-one decision, enforced at the dependency-add boundary.

## Decision

**Green-list licenses** (acceptable everywhere in Crossengin's dependency tree, including for the model itself, the dependencies it links against, and the data it trains on):

- **Apache License 2.0** — preferred for Crossengin's own code.
- **MIT License**
- **BSD-2-Clause, BSD-3-Clause**
- **PostgreSQL License** (BSD-style; applies to PostgreSQL itself and to `pgvector`)
- **ISC License**
- **Unlicense / public domain dedications (CC0)**
- **For data: CC-BY 4.0 and earlier CC-BY versions** (attribution required; commercial use permitted)
- **For data: public domain** (US government works, etc.)

**Case-by-case (review before adoption)**:

- **MPL 2.0 (Mozilla Public License)** — file-level copyleft, usually compatible with Crossengin's posture for library use but requires that modifications to MPL'd files remain MPL. Adoptable if the dependency is used as a library; adopt only if no Apache/MIT alternative exists.
- **LGPL (Lesser GPL)** — dynamic linking is generally acceptable; static linking propagates GPL terms. Adopt only via dynamic linking, and only when no permissive alternative exists.
- **CC-BY-SA (ShareAlike)** for data — the "viral derivative" question for trained model weights is unsettled (see ADR-0018). Default: exclude pending the user's per-source decision.

**Red-list licenses** (excluded from Crossengin's dependency tree):

- **GPL family** (GPLv2, GPLv3, AGPL) for code that Crossengin links against or that becomes part of Crossengin's distributed artifacts.
- **Server Side Public License (SSPL)** and similar source-available-but-not-OSI-approved licenses.
- **All NonCommercial (NC) variants** of Creative Commons licenses for data (CC-BY-NC, CC-BY-NC-SA, CC-BY-NC-ND).
- **All NoDerivatives (ND) variants** of Creative Commons licenses for data.
- **Llama license tier** for the base model itself. Llama-licensed model weights carry use restrictions (acceptable-use policy, scale-based commercial gate) that fail the commercial-clearable test. Research-only baselines built on permissively-licensed alternatives are preferred even when Llama-based baselines would be technically expedient.
- **Any model whose license restricts commercial deployment, scale of deployment, or specific use cases** beyond what the constitutional layer (ADR-0011) already enforces.
- **Any dataset whose terms forbid model training**, regardless of whether the data is technically accessible.

**License-gate workflow.** Every proposed new Python package, Rust crate, model checkpoint, or dataset is license-checked at the proposing pull request:

1. The PR description states the dependency's name, version, and license.
2. CI runs a license-detector against the dependency's metadata; the result is included in the PR.
3. Reviewer confirms the license against this ADR's green/red lists. Case-by-case licenses get explicit reviewer rationale.
4. PR merges only after license sign-off.

The license-detection tooling is itself permissively licensed (e.g., `pip-licenses`, `cargo-deny` — both MIT/Apache).

**Crossengin's own code is Apache 2.0.** This is the project's outbound license for the implementation. Apache 2.0 is preferred over MIT because the explicit patent grant is meaningful for an AI project where contributors may hold patents in the area.

**Data provenance discipline.** Per ADR-0018, every record in the academic knowledge module carries `source`, `license`, `license_url`, and `retrieved_at` metadata. Records with missing license metadata are quarantined, not ingested.

## Consequences

Positive: a Crossengin-derived model can be deployed commercially without legal-license surprises. Enterprise pathway (ADR-0016) is unblocked at the dependency-licensing level. Research collaborators can use the project without license-fear. The license-gate workflow keeps the discipline mechanical rather than dependent on memory.

Negative: some technically superior dependencies are excluded by license. The Llama base-model exclusion in particular removes a popular research baseline; permissively-licensed alternatives may be smaller or less well-tuned. CC-BY-SA exclusion (pending review) removes a meaningful slice of Wikipedia and Wikidata content from the medicine corpus. License-checking is per-PR overhead.

Neutral: the case-by-case category (MPL, LGPL, CC-BY-SA) acknowledges that real engineering occasionally requires nuance. The discipline is to make those calls deliberately, not by default.

## Alternatives considered

**MIT-only outbound** for Crossengin's code. Considered. Apache 2.0's explicit patent grant tips the balance to Apache in the AI domain.

**Permissive-with-NC-data-allowed** (allow CC-BY-NC datasets, with a non-commercial fork of trained weights). Rejected — diverging commercial and non-commercial weight trees is a maintenance and shipping nightmare.

**Permissive-with-Llama-allowed-for-research** (allow Llama-derived baselines under Llama's research terms, with the understanding that commercial deployments use a different base). Considered and rejected. Any Llama-derived artifact in the development tree creates the same fork-and-distinguish problem.

**No explicit license posture** (decide per dependency without a written rule). Rejected — leads inexorably to a GPL-tainted or NC-tainted artifact appearing at the worst possible moment, and the discipline of cleaning it up retroactively is much worse than the discipline of avoiding it upfront.

**SPDX-license-list as the green list** (allow anything OSI-approved). Considered. Too permissive — many OSI-approved licenses (GPLv3, AGPL) are red-list for Crossengin's commercial-clearable requirement.

## Open questions

- Final decision on Wikipedia/Wikidata under CC-BY-SA (deferred to the user; tracked in ADR-0018).
- Specific license-detection tooling integration in CI. Initial pick: `pip-licenses` for Python, `cargo-deny` for Rust. Wired into CI at M1 (per ADR-0022).
- Process for handling transitively-introduced dependencies that fail the license filter (a green-list package depending on a red-list package). v0 default: the transitive dependency blocks the green-list package's adoption. Finalized at M1.

## References

- ADR-0003 (Implementation stack) — Python, PyTorch, Rust — all permissively licensed.
- ADR-0006 (Memory architecture) — PostgreSQL, pgvector, Apache AGE all in the green list.
- ADR-0008 (Academic knowledge) — license discipline applies to source corpus.
- ADR-0016 (Enterprise derivation) — commercial path that this posture enables.
- ADR-0018 (Data sources) — specific medicine-corpus license decisions.
- ADR-0022 (Evaluation and milestones) — M1 for the license-gate CI integration.
