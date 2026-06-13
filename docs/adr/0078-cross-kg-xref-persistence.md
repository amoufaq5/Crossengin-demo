# ADR-0078: Persist cross-KG general xrefs across a snapshot

## Status

Accepted — the snapshot round-trip now carries CROSS-KG general xrefs in
addition to the SAME-KG xrefs ADR-0077 landed. An xref whose destination lives
in a different KG is serialized BY LABEL (both the dst KG label and the dst atom
label) and re-resolved through the registry on apply, idempotently. SEC_KGS is
now reference-complete for both same- and cross-KG xrefs.

## Date

2026-06-12

## Context

ADR-0077 persisted SAME-KG general xrefs (`XREF_CAUSAL` / `XREF_SIMILAR` /
`XREF_ANALOGICAL` / `XREF_PARTOF`) by serializing the destination BY LABEL and
re-resolving it on apply (atom ids are not stable across a load). It explicitly
left CROSS-KG xrefs out of scope and skipped them at serialize time: resolving a
cross-KG dst atom's LABEL requires the destination KG, and `kg_section_build(kg)`
only has the one KG — not the registry. So an edge from `reasoning:logic` to
`language:grammar` was silently dropped on every `/save`.

The fix is the same one R51 (operators) and ADR-0077 (same-KG xrefs) already
use — serialize the dst BY LABEL — but the builder needs the registry to find
the dst KG and resolve the dst atom's label inside it.

## Decision

Make the xref build registry-aware and carry the dst KG label end to end.

- **Reg-aware builder.** Add `kg_section_build_r(kg, reg)` holding the full body;
  `kg_section_build(kg)` becomes `return kg_section_build_r(kg, 0)` so the ~12
  existing callers are unchanged and keep SAME-KG-only behavior (a reg-less
  builder still cannot resolve a cross-KG dst, so it skips those, exactly as
  ADR-0077 did). In the xref loop:
  - SAME-KG (`str_eq(xref_dst_kg(x), kg_label(kg)) == 1`): resolve
    `d = kg_atom(kg, xref_dst_atom(x))` as before; push if `d != 0`.
  - CROSS-KG: only when `reg != 0` — `dkg = kg_find(reg, xref_dst_kg(x))`; if
    found, `d = kg_atom(dkg, xref_dst_atom(x))`; push if `d != 0`. When
    `reg == 0` or the dst KG/atom is not found, SKIP.
- **Tuple shape.** Each field `[10]` xref tuple grows from the ADR-0077 4-field
  `[dst_label, kind, weight, earned]` to the 5-field
  `[dst_kg_label, dst_label, kind, weight, earned]` for ALL xrefs. A SAME-KG
  edge stores its own kg label as `dst_kg_label`.
- **Wire format.** Add a per-entry `…[N].xref[j].dstkg` key (the dst KG label)
  alongside the existing `.dst` / `.kind` / `.weight` / `.earned`. Emitted only
  when the atom has xrefs, so atoms without xrefs cost zero bytes (unchanged
  compactness).
- **Parser.** `_ensure_xref_tuples` pads to the 5-field shape with
  `dst_kg_label` defaulting to `""`; the dispatch parses `.dstkg` into tuple
  slot `[0]`. BACK-COMPAT: a tuple with `.dst` but no `.dstkg` (an old 4-field
  ADR-0077 snapshot, or any earlier form) leaves `dst_kg_label == ""`, and the
  restore pass defaults it to the record's own kg field `r[0]` — preserving
  SAME-KG semantics. (No persisted snapshots exist in the wild, but the parser
  stays tolerant.)
- **Restore (third pass).** For each xref tuple, take `dst_kg_label` (defaulting
  empty to `r[0]`), resolve the dst KG via `kg_spawn(kg_reg, dst_kg_label)`
  (idempotent — returns the existing KG), find the dst atom by label with
  `kg_find_atom`, and re-attach `atom_add_xref(src, xref_new(src, dst, kind,
  weight, earned))`. The pass iterates all records AFTER every KG's atoms exist
  and indexes are rebuilt, so a cross-KG dst in a sibling KG resolves. The
  existing `_has_xref_kind_to(src, dst_kg, dst_atom_id, kind)` de-dup already
  keys on dst_kg, so cross-KG idempotence works unchanged.

## Consequences

- **Round-trip fidelity for cross-KG xrefs.** A relational edge that crosses
  domain KGs (e.g. a reasoning concept linked to a language word) reasons the
  same after a restart, not just within the session.
- **SEC_KGS is now reference-complete for BOTH same- and cross-KG xrefs.** A
  snapshot-based `kg_compact` that goes through serialize/restore would no
  longer drop any general xref — same-KG (ADR-0077) or cross-KG (this ADR) — so
  a snapshot can be treated as a faithful copy of the full edge structure.
- Back-compatible: reg-less callers (`kg_section_build(kg)`) keep ADR-0077
  behavior, and an old 4-field / no-`.dstkg` tuple defaults its dst KG to the
  record's own kg, so existing same-KG snapshots load unchanged.
- Cost: one extra `.dstkg` line per xref-bearing atom entry; zero bytes for
  atoms without xrefs.

## Honest gaps

- **chat_state ATOM-record format still drops xrefs.** That is a separate path
  (`src/persistence/chat_state.nova`) with its own record shape, untouched here
  — a separate follow-up.
- **Duplicate-label limitation (shared with the operator path / R51).** Dst
  resolution is by label, so if a KG holds two atoms with the same label the
  restore resolves to whichever `kg_find_atom` returns. Same constraint R51
  already lives with for premise/conclusion and ADR-0077 for same-KG xrefs.
- **Reg-less callers still skip cross-KG.** Any caller of `kg_section_build(kg)`
  (reg=0) serializes only same-KG xrefs; cross-KG persistence requires routing
  a live registry through `kg_section_build_r`.

## Implementation Notes

- All code changes are confined to `src/persistence/snapshot_disk.nova` (the
  SEC_KGS path) plus the test. The only structural change is field `[10]`'s
  tuple growing by one leading element (`dst_kg_label`); `_ensure_xref_tuples`
  and `_ensure_records` produce the new shape.
- `kg_section_build_r` is the new body; `kg_section_build` delegates with reg=0.
  All existing callers stay on the old signature.
- The restore pass uses `kg_spawn(kg_reg, dst_kg_label)` to obtain the dst KG;
  it is idempotent and the label already round-tripped during the rebuild, so
  this does not orthogonally create KGs.
- The de-dup helper `_has_xref_kind_to` was already keyed on `(dst_kg,
  dst_atom_id, kind)` (ADR-0077), so cross-KG idempotence required no change.

## Verification

- **Unit** (`test_snapshot_disk_full` 113 → 125 checks):
  `test_kg_section_xref_cross_kg_round_trip` builds a registry with two KGs
  ("reasoning" + "language"), adds an atom in each, links
  `reasoning:logic --SIMILAR--> language:grammar` (cross-KG), builds both KGs'
  records with `kg_section_build_r(kg, reg)` into one SEC_KGS blob (concatenated
  record lists, mirroring `test_kg_section_apply_restores_lang_word`), round-trips
  via `snap_to_text(snap_from_text(...))`, applies to a fresh registry with both
  labels, and asserts the cross-KG xref is restored on the reasoning src atom
  with `xref_dst_kg == "language"`, `xref_dst_atom == atom_id(grammar2)`
  (re-resolved by label), and kind/weight/earned survived; a second apply does
  not duplicate. The existing `test_kg_section_xref_round_trip` (same-KG) still
  passes unchanged, exercising the new 5-field tuple via the own-kg path.
- **Acceptance suites all green**: `test_snapshot_disk` (31),
  `test_snapshot_disk_full` (125), `test_snapshot_delta` (84),
  `test_snapshot_migrate` (37), `test_snapshot_reader` (25),
  `test_chat_state_persistence` (88), `test_schema_migration` (78),
  `test_merkle` (60).
