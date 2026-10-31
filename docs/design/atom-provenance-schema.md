# Atom Provenance Schema

> Companion spec to ADR-0087. The ADR holds the decision; this is the field-level
> reference for the knowledge-atom provenance ledger record.

This document specifies the exact shape of a knowledge atom after the ADR-0087
provenance/licensing expansion, the `evidence_grade` enum, and the two supporting
tables (`KG-licenses`, `KG-proofs`). It is descriptive of the record layout; the
*decision* and rationale live in ADR-0087, and the *promotion process* that fills
these fields lives in ADR-0092.

## 1. Full atom shape

After expansion, an atom is three contiguous blocks: the ADR-0016 identity, the
ADR-0023 belief block, and the ADR-0087 provenance ledger.

```
atom = [
  # --- identity (ADR-0016) ---
  atom_id,            # typed atom id (interned)
  concept_ref,        # interned ref to the subject concept
  relation,           # interned relation / operator code
  target_ref,         # interned ref to the object concept (or NULL for unary)

  # --- belief block (ADR-0023) ---
  TAG_BELIEF,         # block tag
  alpha,              # Beta distribution alpha (positive evidence)
  beta,               # Beta distribution beta  (negative evidence)
  last_update_tick,   # tick of last belief edit (drives decay)
  conflict,           # conflict flag (set on hard-conflict freeze)

  # --- provenance ledger (ADR-0087) ---
  source_id,          # interned ref into KG-sources
  source_tier,        # A / B / C authority (ADR-0029)
  source_timestamp,   # when the source asserted it
  license,            # interned ref into KG-licenses        (NEW)
  evidence_grade,     # warrant class enum                   (NEW)
  proof_ref           # interned ref into KG-proofs, or NULL  (NEW)
]
```

### Field reference

| Field | Type | Meaning | Source ADR |
|-------|------|---------|-----------|
| `atom_id` | interned int | Typed unique identity of the atom | ADR-0016 |
| `concept_ref` | interned ref | Subject concept | ADR-0016 |
| `relation` | interned code | Relation / operator linking subject to target | ADR-0016 |
| `target_ref` | interned ref / NULL | Object concept (NULL for unary atoms) | ADR-0016 |
| `TAG_BELIEF` | tag | Marks the start of the belief block | ADR-0023 |
| `alpha` | int ≥ 0 | Beta positive-evidence count | ADR-0023 |
| `beta` | int ≥ 0 | Beta negative-evidence count | ADR-0023 |
| `last_update_tick` | int | Tick of last belief edit; input to decay law | ADR-0023 |
| `conflict` | bool | Hard-conflict / CONTESTED marker | ADR-0023 / ADR-0029 |
| `source_id` | interned ref | Source in KG-sources | ADR-0029 |
| `source_tier` | enum A/B/C | Source authority tier | ADR-0029 |
| `source_timestamp` | int | When the source asserted the fact | ADR-0029 |
| `license` | interned ref | License code into KG-licenses | ADR-0087 |
| `evidence_grade` | enum | Warrant class (see §2) | ADR-0087 |
| `proof_ref` | interned ref / NULL | Proof in KG-proofs, NULL unless FORMAL | ADR-0087 / ADR-0088 |

The expansion is purely additive: identity and belief fields keep their meaning,
and `source_tier` still drives the base belief evidence weight (ADR-0029).

## 2. `evidence_grade` enum

`evidence_grade` is orthogonal to `source_tier`: tier records *who said it*, grade
records *what kind of warrant* backs it.

| Value | Meaning | What warrants it | Belief effect | Assigning gate (ADR-0092) |
|-------|---------|------------------|---------------|---------------------------|
| `FORMAL` | Machine-checkable proof exists | A passing proof in KG-proofs; `proof_ref` MUST be non-NULL | Pinned near-certain; **exempt from ADR-0023 decay**; unpinned only by a failed proof | Proof gate (c) — proof checker (ADR-0088) passes |
| `EMPIRICAL_STRONG` | Well-corroborated empirical fact | Multiple independent sources, or a primary peer-reviewed result, or sufficient source tier | Full evidence weight; normal decay | Corroboration gate (d) — threshold met (ADR-0029) |
| `EMPIRICAL_WEAK` | Low-corroboration empirical fact | A single source or low-corroboration extraction | Evidence weight **damped**; normal decay | Corroboration gate (d) — threshold not met |
| `TESTIMONIAL` | Asserted without shown warrant | Authority assertion with no proof or corroboration; includes most user teaching (ADR-0027) | Evidence weight **damped**; normal decay | Grade gate (b) — default for unwarranted assertions |
| `CONTESTED` | Evidenced disagreement exists | A hard conflict has been recorded against the claim | Routed to steelman policy (ADR-0090); not promoted as trusted | Conflict gate (e) — hard-conflict freeze (ADR-0029) |

`FORMAL` short-circuits the ADR-0023 update to a pinned high-confidence belief; the
grade applies a multiplier on the tier-derived weight for the empirical/testimonial
grades. `CONTESTED` mirrors the ADR-0023 conflict flag and hands off to ADR-0090.

## 3. `KG-licenses` table

`license` interns a row in `KG-licenses`. One row per distinct license; atoms
reference rows, never inline strings.

```
KG-licenses row = {
  spdx_or_name,            # SPDX id or canonical name (e.g. "CC-BY-SA-4.0")
  commercial_use: bool,    # may the derived fact be used commercially?
  attribution_required: bool,
  share_alike: bool,
  url                      # canonical license text
}
```

### Example rows

| spdx_or_name | commercial_use | attribution_required | share_alike | url |
|--------------|----------------|----------------------|-------------|-----|
| `CC-BY-SA-4.0` | true | true | true | creativecommons.org/licenses/by-sa/4.0 |
| `CC0-1.0` / public-domain | true | false | false | creativecommons.org/publicdomain/zero/1.0 |
| `OWNER` (user-taught, ADR-0027) | true | false | false | (internal) |
| `PROPRIETARY` / quarantine | false | n/a | n/a | (per source) |

**Rule:** `commercial_use = false` → the atom is minted only into the **quarantine
partition** and is excluded from Edge and Enterprise edition builds (ADR-0091).
License resolution happens *before* promotion (gate (a), ADR-0092); a source whose
license cannot be resolved is treated as non-commercial and quarantined.

## 4. `KG-proofs` table

`proof_ref` interns a row in `KG-proofs`, populated only for `FORMAL` atoms. Proof
*semantics* are defined by ADR-0088; this table is the storage shape.

```
KG-proofs row = {
  proof_id,                # interned id
  claim_atom,              # ref to the atom this proof backs
  checker_status,          # PASS / FAIL / PENDING (ADR-0088)
  axioms_used,             # refs to the axiom atoms the derivation rests on
  derivation_blob          # opaque serialized derivation for re-checking
}
```

A `FORMAL` grade requires `checker_status = PASS`. If a re-check later returns
`FAIL`, the backing atom's `FORMAL` pin is removed and its belief reverts to the
ADR-0023 update (ADR-0087).

## 5. Lifecycle

License, grade, and `proof_ref` are populated during the ADR-0092 governed
promotion, not at extraction time:

1. **CANDIDATE** — r50 extraction mints the atom into the staging partition with
   identity and belief fields set, `license`/`evidence_grade`/`proof_ref` provisional
   or NULL. Excluded from answers.
2. **VERIFIED / CORROBORATED** — gate (a) resolves and records `license`; gates
   (b)/(c)/(d) assign `evidence_grade` and, for `FORMAL`, set `proof_ref` to a
   passing KG-proofs row; gate (e) sets `conflict`/CONTESTED if a hard conflict
   fires.
3. **PROMOTED** — the atom moves into the live KB with all ledger fields final and
   becomes usable in answers.

During argument construction the debate engine (ADR-0089) reads `evidence_grade`
and `proof_ref` directly: a `FORMAL` atom with a passing `proof_ref` enters
arguments at pinned strength, damped grades contribute proportionally less, and a
`CONTESTED` atom is routed to the steelman policy (ADR-0090) rather than asserted.

## 6. Memory footprint

Consistent with the ADR-0003 1M-node budget, the ledger adds exactly **two interned
ints** (`license`, `evidence_grade`) **+ one ref** (`proof_ref`) per atom — small,
fixed, and O(1) to read during the hot belief-update and argument-construction
paths. Full per-license and per-proof detail lives in `KG-licenses` / `KG-proofs`,
not inline, so the per-atom cost does not grow with license complexity or proof
size.
