# ADR-0075: Wire the death sweep to reclamation — Phase B (working eviction)

## Status

Accepted (Phase B of ADR-0072; builds on the ADR-0074 mechanism).

## Date

2026-06-12

## Context

ADR-0074 delivered `kg_reclaim_atom` (hard removal: null the slot, unindex,
free-list, reset the edge index) but did **not** wire it into the death sweep,
because reclamation puts `0` HOLES into `KG_ATOMS` for the first time and every
raw `kg_atoms()` scanner had to be confirmed hole-tolerant first. This ADR does
that audit and flips eviction on.

## Decision

1. **Wire `adm_sweep` to reclaim.** At the tombstone→dead transition,
   `adm_sweep_attributed` now calls `kg_reclaim_atom(kg, atom_id(a))` after
   marking the atom `dead` and recording the observer attribution. The dormant
   death policy (decay + belief floor + reference gate) is now load-bearing: a
   collectable atom is actually removed from the KG, not just flagged. The
   `dead` payload is still set on the (still-referenced) atom object, so an
   observer holding the handle reads it unchanged — only the KG slot is freed.

2. **Audited all ~30 raw `kg_atoms()` scanners for an `a != 0` guard.** 23 were
   already guarded (directly, or via a helper that returns 0 for a 0 atom —
   `is_operator`, `is_word_atom`, `is_pattern`). Guards were added to 9 sites
   across 7 files; each was independently re-read to confirm correctness (the
   sub-agent's self-report mislabeled three of them, so every "already guarded"
   site was verified by hand, not trusted).

3. **`adm`'s own scans** (`adm_is_referenced`, the sweep loop) now skip 0 slots.

Notable: `snapshot_disk.kg_section_build` now skips freed slots, so a reclaimed
atom is no longer serialized into a snapshot (and `atom_id(0)` can't crash the
save of a holed KG).

## Consequences

- **Eviction is real.** A sweep over a KG with collectable atoms shrinks the
  live set and frees the slots; the free-list records them. Verified:
  `test_atom_death_monitor` (21 checks) now asserts the slot is nulled
  (`kg_atom == 0`), the free-list grew, and a *third* sweep over the holed KG
  does not crash and is a no-op.
- The whole scanner surface tolerates holes (independently audited), so a swept
  KG can be safely PageRanked, clustered, queried, gossiped, serialized, etc.
- Full suite 273/273; coverage 241/241; `make lint-ints` clean.

## Honest gaps

- **Ids are still not reused and RAM is not physically returned.** Under NOVA's
  bump allocator, nulling a slot drops the reference but does not shrink memory,
  and `KG_ATOMS` keeps its length (holes are not compacted) — so a heavily
  churned KG's *slot count* (and therefore raw-scan cost) keeps growing even as
  the *live* count falls. Slot recycling (id reuse, gated on the handle audit)
  and/or a compaction pass are **Phase C**; this ADR delivers correct logical
  eviction, not the memory/scan-cost reduction.
- The edge index is fully reset on each reclaim (one lazy O(atoms) rebuild on
  the next operator lookup). Fine for occasional sweeps; a batched
  reclaim-then-rebuild-once is a future optimisation if sweeps get hot.
- ≥1 M-atom codegen-bug-#11 ceiling (ADR-0066) unchanged.

## Implementation Notes

- `src/learning/atom_death_monitor.nova`: `a != 0` guards in `adm_is_referenced`
  + the sweep loop; `kg_reclaim_atom` call at the dead transition.
- `a != 0` guards added: `src/kg/semantic_search.nova`,
  `src/kg/competence_tracker.nova`, `src/parts/meta/reflection_loop.nova` (×2),
  `src/parts/meta/meta_observer.nova`, `src/parts/meta/theory_of_mind.nova`,
  `src/learning/atom_birth_monitor.nova`, `src/persistence/schema_migration.nova`
  (×2), `src/persistence/snapshot_disk.nova`.
- Test: `tests/unit/test_atom_death_monitor.nova` (reclaim + holed-KG sweep).
- Parents: ADR-0072 (design), ADR-0074 (mechanism), ADR-0070 (edge index).
