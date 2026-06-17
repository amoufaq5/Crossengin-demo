# ADR-0087: Provenance and licensing ledger (per-atom license + evidence grade)

## Status

Proposed

## Date

2026-06-15

## Context
ADR-0016 gives atoms their layout; ADR-0029 already attaches
`{provenance, source_tier, source_timestamp}` and ADR-0023 carries a Beta belief
per atom. That is enough to answer "how strongly do we believe this, and from a
source of what authority?" — but the truth-seeking thesis (ADR-0086) needs two
more guarantees the current layout cannot make:

1. **Commercial cleanliness (Rule 3).** Every atom must be traceable to a source
   whose license permits commercial use of the *fact* derived from it. CrossEngin
   already learns from the open web (r50 fetches Wikipedia); without a recorded
   license per atom we cannot later prove the knowledge base is free of
   encumbered content, nor strip a source if its terms change. This is a
   business-survival requirement, not a nicety.

2. **Evidence grade distinct from source tier.** ADR-0029's A/B/C tier measures
   *who said it* (authority). It does not capture *what kind of warrant* backs
   the claim: a formally proved theorem, a peer-reviewed empirical finding, a
   single observation, and a contested opinion are epistemically different even
   when asserted by equally authoritative sources. The debate engine (ADR-0089)
   and the formal path (ADR-0088) need to read that warrant directly to weight
   arguments and to decide whether a proof is required.

We must extend the atom's provenance into a small, fixed **ledger record**
without bloating the 1M-node memory budget (ADR-0003) or breaking the closed-form
belief update (ADR-0023). The extension is additive: existing fields keep their
meaning; tier still drives belief evidence weight.

## Decision
Every knowledge atom carries a **provenance ledger record** extending ADR-0016 /
ADR-0029:

```
provenance = [
  source_id,          # interned ref into KG-sources (existing)
  source_tier,        # A / B / C authority (ADR-0029, existing)
  source_timestamp,   # when the source asserted it (existing)
  license,            # NEW: interned license code (see below)
  evidence_grade,     # NEW: warrant class (see below)
  proof_ref           # NEW: ref into KG-proofs, or NULL (ADR-0088)
]
```

**License** is an interned code into a `KG-licenses` table, each entry recording
`{spdx_or_name, commercial_use:bool, attribution_required:bool,
share_alike:bool, url}`. The ingestion pipeline (r50 / ADR-0028) must resolve a
license for every fetched source *before* any atom is minted from it; a source
whose license cannot be resolved or forbids commercial use of derived facts is
ingested only into a quarantined, non-commercial partition that the Enterprise
and Edge editions (ADR-0091) exclude at build time. User-taught atoms (ADR-0027)
carry an `OWNER` license. Facts themselves are not copyrightable, but the
*expression* fetched is; the ledger records the source's license so we can prove
clean derivation and honor attribution/share-alike where required.

**Evidence grade** is a small enum, orthogonal to tier:

- `FORMAL` — backed by a machine-checkable proof; `proof_ref` MUST be non-NULL
  (ADR-0088). Belief is effectively pinned near-certain while the proof verifies.
- `EMPIRICAL_STRONG` — multiple independent, corroborating reputable sources, or
  a primary peer-reviewed result.
- `EMPIRICAL_WEAK` — a single source or low-corroboration extraction.
- `TESTIMONIAL` — asserted by an authority without shown warrant (incl. most user
  teaching).
- `CONTESTED` — evidenced disagreement exists (mirrors ADR-0023's contested
  flag); handled by the steelman policy (ADR-0090).

Evidence grade modulates, but does not replace, the ADR-0023 belief update: the
tier sets the base evidence weight; grade applies a multiplier (`FORMAL`
short-circuits to a pinned high-confidence belief that only a failed proof can
unpin; `EMPIRICAL_WEAK`/`TESTIMONIAL` damp the weight). The decay law of ADR-0023
still applies except to `FORMAL` atoms, whose truth is not time-sensitive.

**Audit.** The ledger is append-only-friendly: belief edits and grade changes are
recorded in the decision log (ADR-0043) with the triggering source, so any
emitted claim can be walked back to its sources and licenses on demand.

## Options Considered
- **Keep tier-only provenance (status quo, rejected).** Cannot prove commercial
  cleanliness and cannot distinguish a proof from an opinion — both fatal to the
  ADR-0086 thesis.
- **Separate license/grade sidecar tables keyed by atom id (rejected).** Avoids
  growing the atom record, but every belief update and every argument
  construction would need a second lookup; at 100Hz over 1M nodes the indirection
  cost is not worth the few bytes saved. Interned codes inline are cheaper.
- **Inline interned ledger record (CHOSEN).** Two interned ints (`license`,
  `evidence_grade`) and one ref (`proof_ref`) added to the existing provenance
  tuple — small, fixed, O(1) to read during argument construction, and resolvable
  to full detail via `KG-licenses` / `KG-proofs`.
- **Free-form license strings per atom (rejected).** Unbounded memory and
  un-auditable; interning into `KG-licenses` gives the same expressiveness with a
  fixed footprint and a single place to update terms.

## Consequences
- **Positive:** The knowledge base becomes provably clean for commercial use
  (Rule 3) and any answer is traceable to sources + licenses; the engine can
  reason about *kind of warrant*, enabling the formal path (ADR-0088) and
  better-calibrated argument weights (ADR-0089); quarantining encumbered sources
  is a build-time partition, so editions stay clean by construction (ADR-0091).
- **Negative:** Ingestion gains a mandatory license-resolution step (a real cost,
  and a blocker when a source's license is ambiguous); three extra fields per
  atom add memory at 1M+ scale (mitigated: two interned ints + one ref);
  evidence-grade assignment needs rules per ingestion path and will mis-grade at
  the margins until tuned.
- **Future work:** Learn evidence grade from corroboration history rather than
  fixed ingestion rules; a license-compatibility checker that refuses to merge
  share-alike-incompatible partitions; periodic re-validation of source licenses.

## Implementation Notes
- Extend the atom provenance tuple in `core/knowledge.nova` / the atom layout
  (ADR-0016); add `KG-licenses` and `KG-proofs` KGs (multi-KG namespacing,
  enhancement #8). Schema spec lives at `docs/design/atom-provenance-schema.md`.
- Ingestion (`src/learning/`, r50 path): add `resolve_license(source)` before
  `lp_ingest`; route unlicensed/non-commercial sources to a quarantine partition
  flagged for exclusion by ADR-0091 edition builds.
- Belief integration: `core/belief.nova` `belief_update` gains a grade multiplier;
  `FORMAL` atoms pin confidence and skip decay (coordinate with ADR-0088 proof
  verification). Tier→weight mapping of ADR-0029 is unchanged.
- Audit: grade/license changes log to ADR-0043; emitted answers can render their
  provenance chain (feeds the explainability requirement of ADR-0089).
- Testing: a fetched source with no resolvable license lands only in quarantine
  and never surfaces in an Enterprise build; a `FORMAL` atom resists decay and is
  unpinned only by a failed proof; an `EMPIRICAL_WEAK` atom moves belief less than
  an `EMPIRICAL_STRONG` one at equal tier.
- DEPENDS ON: NOVA enhancement #8 (multi-KG namespacing for `KG-licenses`/
  `KG-proofs`), #9 (audit log). No new arithmetic enhancement required.

## Implementation status

**Increment 1 (landed): the in-memory ledger schema.** `src/kg/atom_store.nova`
extends the atom `A_PROV` slot from the ADR-0029 `[source_tier, producing_part]`
pair to the full ADR-0087 ledger `[source_tier, producing_part, license,
evidence_grade, source_timestamp, proof_ref]`. The extension is
backward-compatible: indices 0,1 keep their meaning, and accessors are defensive
(`_prov_get`) so a short provenance written by older code — e.g.
`kg_rss_ingest` — still reads, returning safe defaults; `_prov_ensure` upgrades a
short list in place when any new field is set. Added: evidence-grade constants
(`GRADE_FORMAL`/`EMPIRICAL_STRONG`/`EMPIRICAL_WEAK`/`TESTIMONIAL`/`CONTESTED`),
license codes (`LICENSE_UNKNOWN`/`OWNER`/`OPEN`), accessors and setters
(`atom_license`, `atom_evidence_grade`, `atom_proof_ref`, `atom_set_provenance`,
…), the FORMAL-requires-a-proof invariant (`atom_grade_consistent`), and the
clean/quarantine gate (`atom_is_clean`: `LICENSE_UNKNOWN` → not clean).

Verified by `tests/unit/test_atom_store.nova` (now 66 checks, up from 42;
compiled and run via the bootstrap): defaults, full-ledger set/read, grade
naming, the FORMAL/proof invariant, the cleanliness gate, and backward
compatibility with an old 2-element provenance.

**Increment 2 (landed): snapshot persistence.** The ledger now survives a
restart. `snapshot_disk.nova` carries provenance through the full round trip: the
per-atom record gains six trailing fields (`kg_section_build_r`); they serialize
as `kgs.atoms[N].prov.{tier,part,license,grade,ts,proof}` keys, emitted only when
non-default to keep snapshots compact (`kg_section_serialize`); the parser reads
them back into the record and `_ensure_records` pre-allocates the slots; and
`kg_section_apply` restores them onto the rehydrated atom via
`atom_set_provenance`. The change is additive and backward-compatible — an old
snapshot with no `prov.*` keys rehydrates with the atom's `atom_new` defaults
(unresolved license → quarantine on the clean-build gate).

*Verification.* Verified at unit scale (the `atom_store` suite stays green, 66
checks) **and end-to-end**: the full round trip
`kg_section_build_r → snap_to_text → snap_from_text → kg_section_apply` over the
real `snapshot_disk` graph preserves every ledger field, including `proof_ref`
and `evidence_grade`, and the direct build→apply path preserves `tier`/`ts` too.

This end-to-end run required fixing the NOVA compiler. The bootstrap and the
shipped range-based `bin/nova` both mis-handle the ~19k-line snapshot program
(`proof_ref` read back as garbage; `snap_to_text` segfaults — *even on the
baseline `test_snapshot_disk`*), so the verification was done under the
value-tagged compiler (NOVA branch `claude/adoring-wozniak-gdnye9`) after three
tagging fixes landed there: `str_eq` must tag its 0/1 result (`fc5d059`),
`_nova_str_eq` must guard NULL (`b17c783`), and `getenv` must return tagged-0 for
unset vars (`27e17c6`) so CrossEngin's `merkle_signing` NULL guard fires and
`snap_to_text` skips signing instead of crashing. With those, the round trip is
green. Full standing verification under a shipped `bin/nova` waits on that tagged
compiler landing (it is not yet installed; tracked in NOVA `PTR_TAGGING_PLAN.md`).

**Scope still open:** the `KG-licenses` / `KG-proofs` KGs, ingestion-time license
resolution, and the belief grade-multiplier (ADR-0023 integration) remain
follow-on work.
