# ADR-0077: Persist same-KG general xrefs across a snapshot

## Status

Accepted — the snapshot round-trip now carries SAME-KG general xrefs
(`XREF_CAUSAL` / `XREF_SIMILAR` / `XREF_ANALOGICAL` / `XREF_PARTOF`), the kind
`atom_add_xref` installs, resolved BY LABEL and re-attached idempotently. This
sits alongside R51 (operators by-label) and R65 (gloss) as another atom-payload
field that survives `/save` + restart + `/load`.

## Date

2026-06-12

## Context

The KGS snapshot path serialized per atom only `[kg, id, kind, label, alpha,
beta, op/premise/conclusion, gloss]` (`kg_section_build` in
`src/persistence/snapshot_disk.nova`). General cross-KG references created via
`atom_add_xref` — the ADR-0017 relational edges (causal, similar, analogical,
part-of) — were **never serialized**. They did not survive a save → load.

The only xrefs that came back were **word-sense** xrefs, and only because
`kg_section_apply` re-derives them from scratch in a dedicated pass
(`_restore_word_senses`, walking sibling KGs for a same-labeled concept). Every
other xref was a silent, latent data-loss on every `/save`: the atoms returned,
but the graph edges between them were gone.

Atom ids are **not stable across a load** (a fresh registry re-mints ids from
0) — that is exactly why R51 serializes operator premise/conclusion BY LABEL and
re-resolves them in a second pass. An xref stores its destination as an atom id
(`xref_dst_atom`), so it has the same instability and needs the same treatment.

## Decision

Serialize and restore **SAME-KG** general xrefs by LABEL, mirroring the R51
operator pattern exactly. CROSS-KG xrefs (where `xref_dst_kg(x)` differs from the
owning atom's KG) are OUT OF SCOPE for this change and are skipped at serialize
time (a follow-up).

- **Build** (`kg_section_build`): after the gloss field `[9]`, append record
  field `[10]` = a list of same-KG xref tuples. For each `x` in `atom_xrefs(a)`
  where `str_eq(xref_dst_kg(x), kg_label(kg)) == 1`, resolve `d = kg_atom(kg,
  xref_dst_atom(x))`; if `d != 0`, push `[atom_label(d), xref_kind(x),
  xref_weight(x), xref_earned(x)]`. Cross-KG and dst==0 are skipped.
- **Wire format** (`kg_section_serialize`): emit nothing when the list is empty
  (keeps snapshots compact and back-compatible). Otherwise emit
  `…[N].xref.count <int>` and per entry `j`: `…[N].xref[j].dst` (str label),
  `.kind` (int), `.weight` (int), `.earned` (int).
- **Parser** (the `kgs.atoms[N].*` dispatch + `_ensure_records` /
  `_ensure_xref_tuples`): `xref.count` is a no-op (tuples are grown on demand);
  each `xref[j].<field>` lands into record field `[10]` as the same
  list-of-tuples shape. Absent keys → empty list (old snapshots).
- **Restore** (a third pass in `kg_section_apply`, after the rebuild + the R51
  operator pass): for each record with xrefs, locate the src atom by label in
  its KG, resolve each xref's dst via `kg_find_atom(that_kg, dst_label)`, and if
  both exist `atom_add_xref(src, xref_new(src, dst, kind, weight, earned))`.

**Idempotence** is enforced by a de-dup guard `_has_xref_kind_to(src, dst_kg,
dst_atom, kind)` — the add is skipped when `src` already carries an xref to the
same `(dst_kg, dst_atom_id, kind)` tuple. This mirrors the word-sense
`_has_sense_to` de-dup, extended with `kind` so a CAUSAL and a SIMILAR edge to
the same dst are distinct (both survive) while a re-applied snapshot is a no-op.
Applying the same snapshot twice does not grow the xref count.

## Consequences

- **Round-trip fidelity for same-KG xrefs.** A relational edge an atom carries
  (causal/similar/etc. within its own KG) reasons the same after a restart, not
  just within the session.
- **Unblocks a future safe snapshot-based `kg_compact`.** The round-trip becomes
  *reference-complete* for same-KG graphs: a compaction pass that goes through
  the snapshot serialize/restore no longer drops the edge structure of a
  same-KG graph, so a snapshot can be treated as a faithful copy of it.
- Back-compatible: a pre-ADR-0077 snapshot has no `.xref.*` lines, so every
  record parses with an empty `[10]` and the restore pass is a no-op. Old
  snapshots load unchanged.
- Cost: a handful of extra lines per atom that actually has same-KG xrefs; zero
  bytes for atoms without them.

## Honest gaps

- **CROSS-KG xrefs still drop.** An xref whose `dst_kg` differs from the owning
  atom's KG is skipped at serialize time. Restoring those needs the destination
  KG to exist and be label-resolvable at apply time across the registry — a
  follow-up.
- **chat_state ATOM-record format still drops xrefs.** That is a separate path
  (`src/persistence/chat_state.nova`) with its own record shape, untouched here
  — a separate follow-up.
- **Duplicate-label limitation (shared with the operator path).** Dst resolution
  is by label, so if a KG holds two atoms with the same label the restore
  resolves to whichever `kg_find_atom` returns. This is the same constraint R51
  already lives with for premise/conclusion.

## Implementation Notes

- All changes are confined to `src/persistence/snapshot_disk.nova` (the
  `SEC_KGS` path) plus the test. The record-shape constants stay the same; field
  `[10]` is purely additive and is padded by `_ensure_records`.
- The restore pass runs AFTER `kg_rebuild_index` and the R51 operator pass, so
  every atom exists and every per-KG index is current before any label lookup.
- The de-dup helper `_has_xref_kind_to` lives next to `_has_sense_to`; the two
  differ only in the `kind` discriminator.

## Verification

- **Unit** (`test_snapshot_disk_full` 94 → 113 checks): `test_kg_section_xref_round_trip`
  builds a 3-atom KG with a SAME-KG `XREF_CAUSAL` and `XREF_SIMILAR`, round-trips
  via `snap_to_text(snap_from_text(...))` + `kg_section_apply`, and asserts the
  restored src has both xrefs, each dst re-resolves BY LABEL to the freshly-minted
  atom id, and kind/weight/earned survive; applying twice keeps the count stable.
  `test_kg_section_xref_back_compat_no_xrefs` confirms an atom with no xrefs
  round-trips with an empty xref list (no crash).
- **Acceptance suites all green**: `test_snapshot_disk` (31), `test_snapshot_disk_full`
  (113), `test_snapshot_delta` (84), `test_snapshot_migrate` (37),
  `test_snapshot_reader` (25), `test_chat_state_persistence` (88),
  `test_schema_migration` (78), `test_merkle` (60).
