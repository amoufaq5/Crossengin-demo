# ADR-0071: Query `kind` fast-path via the existing kind index (P1.6)

## Status

Proposed

## Date

2026-06-12

## Context

`query.nova`'s executor resolves a free-variable-subject triple (`?x <pred>
<obj>`) through `_qry_atoms_matching_triple`, which **scanned every atom** in the
KG and tested it. The most common analytic pattern — `?x kind CONCEPT` (and
`?x kind FACT`, etc.), the first clause of nearly every query and join — was
therefore O(atoms), even though the KG already maintains a kind index
(`KG_KIND_IDX`, served by `kg_atoms_by_kind`). This is the P1.6 companion to the
operator index (ADR-0070): make the query engine reuse the indexes it already
has.

## Decision

In `_qry_atoms_matching_triple`, add a fast-path: a `kind` predicate with a
**fixed** object is served directly from `kg_atoms_by_kind` (the kind-index
bucket) instead of scanning. The bucket yields the same atom-ids in the same
ascending order as the scan, so the result — and every downstream join/filter
that consumes it — is byte-identical, at O(matches) instead of O(atoms).

Deliberately **not** optimised, with reasons:
- **`?x kind ?k` (variable kind)** must bind `?k` to each atom's kind, so it is
  inherently a full pass; left to the scan.
- **`label`** is left to the scan because the label index is one-to-one
  (`kg_find_atom` returns a single atom) while labels are **not** unique in a KG
  — using it would under-return duplicate-label matches. Correctness over speed.

The fast-path mirrors the exact kind resolution the scan used
(`_qry_kind_from_name`, falling back to `rt_str_to_int`), and `kg_atoms_by_kind`
returns `[]` for an out-of-range/unknown kind — identical to the scan finding no
matches.

## Consequences

- `?x kind <K>` query clauses are O(matches). All five query suites stay green
  (`kg_query` 55→62 with an explicit id/order parity test, `kg_query_agg` 67,
  `kg_query_ext` 60, `distributed_query` 36, `self_model_query` 9) — they already
  exercised `kind` patterns and downstream `links` joins, so they prove the
  result is unchanged. Full suite green; coverage 241/241; `make lint-ints`
  clean.
- No new index or data structure — pure reuse of `KG_KIND_IDX`.

## Honest gaps

- **Other predicates still scan.** `label`, `alpha`, `beta`, `created_ns`
  free-subject patterns remain O(atoms). `label` could use the label index only
  after making it many-to-one (or accepting it returns all same-label atoms);
  the numeric-field predicates have no index.
- **The free-subject `links` pattern still scans every atom as a candidate
  source** (it walks each atom's xrefs). A true speedup there needs a reverse-
  xref / incoming-edge index, analogous to ADR-0070's edge index but over
  `atom_xrefs`; that is a separate follow-up.
- The ≥1 M-atom codegen-bug-#11 ceiling (ADR-0066) applies here too.

## Implementation Notes

- `src/kg/query.nova`: `_qry_atoms_matching_triple` gains the `kind` fast-path
  (uses `_kg_has_kind_index` + `kg_atoms_by_kind` from `multi_kg_manager`).
- Test: `tests/unit/test_kg_query.nova` adds `test_execute_kind_fastpath_ids`
  (exact ids in ascending order + unknown-kind-empty parity).
- Companion: ADR-0070 (operator adjacency index, P1.5).
