# ADR-0029: Source authority weighting and conflict resolution (Tier A/B/C sources, newest-wins for guidelines, oldest-wins for classical, flag hard conflicts)

## Status

Proposed

## Date

2026-05-25

## Context
Once CrossEngin fetches knowledge from multiple whitelisted sources (ADR-0028) and also receives user teaching (ADR-0027), it will encounter sources that disagree. A medical guideline updated in 2025 may contradict a 2019 textbook; two reference sites may state different figures; the user may assert something that conflicts with an external source. The substrate must decide which claim becomes the high-confidence atom, how to set Bayesian counts (ADR-0023), and when a disagreement is too important to resolve silently. Without a principled scheme, atom confidence would be set by whichever source happened to be fetched last.

This decision feeds directly into belief tracking (ADR-0023): source authority determines how strongly a piece of evidence moves an atom's alpha/beta. It must also respect provenance set upstream (user-taught vs fetched) and remain auditable (ADR-0043). Crucially, "newest is best" is not universally true: for fast-moving normative knowledge (clinical guidelines, standards, prices) recency matters, but for stable classical knowledge (mathematics, anatomy, settled history) an older authoritative source is often more reliable than a recent low-quality restatement. The scheme must encode both regimes.

## Decision
We assign every source a **tier** and store it on each atom's provenance. Three tiers with fixed evidence weights applied when updating Bayesian counts (ADR-0023):

- **Tier A (authoritative):** the user (loyalty apex, ADR-0034), official standards/guideline bodies, primary references. Weight 1.0 — a Tier-A claim contributes a full evidence increment (e.g., +3 to the supported side's alpha).
- **Tier B (reputable secondary):** established encyclopedias, well-known reference sites. Weight 0.5.
- **Tier C (weak/unverified):** everything else on the whitelist not elevated, or low-confidence extractions. Weight 0.2.

**Conflict resolution** between atoms making contradictory claims about the same concept:
1. **Tier dominates.** Higher-tier wins; user-taught (Tier A) outranks any fetched claim, consistent with ADR-0027.
2. **Within the same tier, apply a domain recency policy** stored per-domain in `KG-sources`:
   - **newest-wins** for domains flagged `normative` (guidelines, standards, prices, current events): the claim with the more recent source timestamp wins and gets the alpha increment; the older claim's counts decay.
   - **oldest-wins** for domains flagged `classical` (mathematics, anatomy, settled physics/history): the older authoritative source is preferred, resisting churn from recent restatements.
   - default `neutral` domains: combine both claims as competing evidence (each updates its side of alpha/beta), letting confidence settle empirically.
3. **Hard-conflict flag.** If two **Tier-A** sources disagree, OR a fetched claim contradicts a user-taught atom, OR a high-confidence atom (alpha+beta ≥ 20, mean > 0.8) would be overturned, the system does NOT silently overwrite. It marks the atom `contested`, freezes its confidence, raises a `SIG_REFLECTION`, and surfaces the conflict to the user (via ADR-0027's explicit mode) for adjudication, logging the event (ADR-0043).

## Options Considered
- **Newest-wins everywhere.** Simple and good for guidelines. Rejected: corrupts stable classical knowledge whenever a recent low-quality source restates it incorrectly; ignores source authority entirely.
- **Source-tier-only (ignore time).** Clear precedence. Rejected: cannot distinguish a current guideline from a superseded one within the same tier; normative domains demand recency.
- **Tier + per-domain recency policy + hard-conflict flagging (CHOSEN).** Captures authority, the newest-vs-oldest split, and human adjudication for the dangerous cases. More configuration (domain flags) but matches reality and keeps the user in the loop on high-stakes disagreements.
- **Always defer every conflict to the user.** Safest for correctness. Rejected: floods the single user with trivial disagreements, violating the attention budget of ADR-0027; reserve human adjudication for hard conflicts only.

## Consequences
- **Positive:** Atom confidence reflects genuine source authority and the correct temporal regime per domain; dangerous disagreements get human adjudication instead of silent overwrite; user knowledge is appropriately privileged; fully auditable.
- **Negative:** Requires maintaining per-source tiers and per-domain recency flags (founder curation); mis-flagging a domain (normative vs classical) produces systematically wrong resolutions; the `contested` freeze can leave an atom stuck until the user responds.
- **Future work:** Learn source tiers from track record (how often a source is later contradicted) rather than fixing them; auto-classify domains as normative/classical; let ADR-0039 model which conflicts a given user cares to adjudicate.

## Implementation Notes
- Source tiers and domain recency flags stored as atoms in `KG-sources`; each knowledge atom carries `{provenance, source_tier, source_timestamp}` (extends ADR-0016 atom layout).
- Conflict resolution implemented in `mind/learning.nova` `resolve_conflict(atom_a, atom_b)`, calling `core/belief.nova` to apply weighted alpha/beta increments (Tier A=+3, B=+1.5, C=+0.6 to the winning side; decay the loser) and `core/similarity.nova` to confirm two atoms truly address the same concept before declaring a conflict.
- Hard-conflict path emits `SIG_REFLECTION` (ADR-0008) and invokes ADR-0027 explicit teach-prompt for adjudication; logs via ADR-0043.
- Integrates with ADR-0028 (tier tagging at fetch time) and ADR-0023 (belief updates).
- Test fixtures: same-tier `normative` conflict with differing timestamps (expect newest-wins, loser decayed); same-tier `classical` conflict (expect oldest-wins); fetched claim vs user-taught atom (expect user wins, fetched logged); two Tier-A disagreeing (expect `contested` freeze + user flag, no overwrite).
- DEPENDS ON: NOVA enhancement #8 — multi-KG namespacing for `KG-sources` and cross-KG references; #9 — audit log for contested-conflict events.
