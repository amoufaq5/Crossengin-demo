# 0079: In-place KG compaction

## Status

Accepted — capstone of the memory-lifecycle work (ADRs 0072 handle audit,
0074 hard reclamation, 0075/0076 death gating + handle inventory).

## Date

2026-06-12

## Context

`kg_reclaim_atom` (ADR-0074) is the hard reclamation path: it nulls an atom's
slot in `KG_ATOMS` (sets it to `0`), unindexes it, and records the freed id on
the freelist. That leaves `0` holes in `KG_ATOMS`. Ids are not reused, so under
churn the list — and every linear scan over it (`kg_centroid`, `kg_atoms_by_kind`
fallback, the reasoning edge-index rebuild, snapshot serialization, …) — grows
without bound even while the live atom count stays flat. We need a compactor that
removes the holes and renumbers the live atoms to dense ids.

The naive approach — serialize each live atom, drop it, and rebuild from the
snapshot wire format — is NOT state-complete. The snapshot round-trip drops
non-word (HDC / custom) embeddings and roughly 25 payload keys: it re-derives a
lexical embedding and only re-attaches the payload fields the wire format knows
about. Round-tripping through it would silently lose atom state. So the only
faithful compactor is an IN-PLACE one that MOVES the live atom objects (never
serializes them): embeddings, beliefs, provenance, version, and every payload
key survive by construction.

Renumbering means every persistent id-holder must be remapped. The ADR-0076
handle audit enumerates them: the references to live-atom ids are
(1) cross-KG xref endpoints (`XR_SRC_ATOM` / `XR_DST_ATOM`, cross_kg_references),
(2) reasoning operator `premise`/`conclusion` payloads (same-KG atom ids,
reasoning_atoms), and (3) episodic cluster members (`EA_MEMBERS`, episodic) —
which live in a SEPARATE `eas` store, not in the registry.

## Decision

Add `fn kg_compact(reg, kg)` to `src/kg/multi_kg_manager.nova`. It:

1. Walks `kg[KG_ATOMS]` and builds `old_to_new`: each live atom at slot `i` is
   assigned the next dense id (`0,1,2,…`) in old-id order (so relative order is
   preserved); a hole gets `0-1`. The map is padded to `len(atoms)`.
2. Builds the new dense `KG_ATOMS` by MOVING the live atom objects: for each live
   atom it rewrites `A_ID` via `list_set(a, A_ID, new_id)` and appends the SAME
   object. `KG_NEXTID` is set to the live count.
3. Remaps operator payloads in this KG: for each atom with a `"premise"` payload,
   remaps `"premise"` and `"conclusion"` through `old_to_new` (same-KG ids).
4. Remaps xrefs registry-wide (`reg[KREG_KGS]`): for every xref on every atom in
   every KG, if `xref_src_kg == kg_label(kg)` it remaps `XR_SRC_ATOM`, and if
   `xref_dst_kg == kg_label(kg)` it remaps `XR_DST_ATOM`. This covers same-KG
   xrefs and cross-KG xrefs whose destination is in the compacted KG. (Only the
   compacted KG's atoms own xrefs whose src_kg is this label, but checking all is
   safe and cheap.)
5. Calls `kg_rebuild_index(kg)` — rebuilds the label/kind indexes, resets the
   edge index unbuilt (the reasoning layer lazily rebuilds it from the remapped
   operators on first lookup), rebuilds the ANN if attached, and clears the
   freelist (its old ids are now meaningless).
6. Returns `old_to_new`.

A defensive helper `_remap_id(old_to_new, id)` returns the new id, or leaves the
id unchanged when out of range or when it maps to a dropped hole (`0-1`) — a
referent that was a hole shouldn't happen (reclaimed atoms are unreferenced) but
failing safe beats corrupting. `kg_live_atom_count(kg)` exposes the non-0 slot
count.

Episodic cluster members live in the separate `eas` store, so the compactor
cannot reach them. `fn episodic_remap_members(eas, old_to_new)` is added to
`src/kg/episodic.nova`: for each episodic atom it rebuilds `EA_MEMBERS` by
mapping each member through `old_to_new`, dropping members that map to `0-1`.
The caller passes the map `kg_compact` returns.

## Consequences

- `KG_ATOMS` length (and the cost of every scan over it) is bounded by the live
  atom count under churn, instead of growing monotonically with reclamations,
  while FULL atom state is preserved (move, not serialize).
- Dense ids restore O(1)-by-slot addressing without holes for newly compacted
  KGs.
- The edge index is rebuilt (reset unbuilt + lazy rebuild) so a reclaimed
  operator's edges and stale premise/conclusion ids never leak into lookups.

## Honest gaps

- NOVA's allocator is a bump allocator and does not free RAM, so this bounds the
  LIST LENGTH (and scan cost), not RSS. The moved atom objects are the same
  allocations; the old hole-ridden `KG_ATOMS` backing list is garbage but not
  reclaimed by the runtime.
- Episodic remapping is CALLER-DRIVEN: `kg_compact` returns the map, and the
  caller must invoke `episodic_remap_members(eas, map)` because the `eas` store
  is separate from the registry and the compactor has no handle to it.
- The death gate (ADR-0075/0076) does not yet protect episodic-referenced atoms
  from reclamation, so an atom named by a cluster can be reclaimed and then
  dropped from the cluster by the remap. This is a follow-up: the gate should
  consult the episodic store before reclaiming.
- CONTRACT: any NEW persistent holder of an atom id MUST be remapped through the
  compactor (registry-wide xrefs + operators are handled here; episodic via the
  helper). A new id-holder added without wiring into the compactor will silently
  dangle after a compaction. Documented here so future work audits against it.
- NOVA codegen bug #11 (large-magnitude multiply miscompile) still caps practical
  KG size at ~1M atoms; compaction does not change that ceiling.

## Implementation Notes

- `kg_compact` / `_remap_id` / `kg_live_atom_count` live in
  `src/kg/multi_kg_manager.nova`; `episodic_remap_members` in
  `src/kg/episodic.nova`.
- The move rewrites `A_ID` directly (`list_set(a, A_ID, new_id)`); an atom is a
  list and its id is mutable, so identity-by-object is preserved while the id
  field is updated.
- Step 4 iterates `reg[KREG_KGS]` and skips `0` (already-reclaimed) slots, so it
  is safe to run after other KGs have their own holes.
- Tests: `test_kg_compact` (holes removed; dense ids; payload + embedding
  survive the move; operator premise/conclusion remapped and reachable via the
  rebuilt edge index; same-KG xref dst remapped; cross-KG xref dst remapped; the
  returned map maps survivors and holes correctly) and `test_episodic_remap_members`
  in `tests/unit/test_multi_kg_manager.nova`.
