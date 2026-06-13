# ADR-0074: Atom reclamation mechanism — Phase A of the memory lifecycle

## Status

Accepted (implements the first, zero-id-reuse increment of ADR-0072).

## Date

2026-06-12

## Context

ADR-0072 designed the KG memory lifecycle and identified the gap: the death
**policy** exists (`atom_death_monitor.nova` decays, gates, and on the second
sweep marks an atom `dead`) but no **mechanism** reclaims it. Two specific
shortfalls:

- `adm_sweep` only sets a `dead` *payload flag* — the atom keeps its `KG_ATOMS`
  slot and stays in every index, so scans (and reasoning) still see it.
- `kg_remove_atom` is **soft**: it unlinks an atom from the label/kind/ANN
  indexes but leaves the object in `KG_ATOMS`.

This ADR delivers the reclamation mechanism and its index-invalidation hook,
deliberately scoped to the "zero-id-reuse, independently testable" first
increment recommended in ADR-0072.

## Decision

Add `kg_reclaim_atom(kg, id)` (the **hard** removal path) plus a per-KG
free-list (`KG_FREELIST` slot):

1. Unindex via the existing `kg_remove_atom` (label/kind/ANN).
2. Null the slot (`KG_ATOMS[id] = 0`).
3. Record the freed id on the free-list (`kg_freelist_count` for observability).
4. **Invalidate the edge index** — reset `KG_EDGE_IDX` to a fresh empty+unbuilt
   index (the same full reset `kg_rebuild_index` performs), so the next
   `rk_operators_*` lookup lazily rebuilds from live atoms only.

**Edge-index interaction (ADR-0070) — the subtle part.** Merely flipping the
edge index's `built` flag is wrong: the `from`/`to` buckets still hold the old
entries, and the lazy rebuild would *append* to them, double-counting survivors.
A test (`test_reclaim_invalidates_edges`) caught exactly this; the fix is the
full reset, mirroring the snapshot-load path.

**Not done (by design):**
- **Ids are not reused.** `kg_add_atom` still increments `KG_NEXTID`; the
  free-list is bookkeeping only. Id reuse needs the handle audit (ADR-0072).
- **Not wired into `adm_sweep`** (see Wiring gate).

## Consequences

- A correct, tested reclamation primitive with the edge-index-invalidation hook
  that the ADR-0070 × lifecycle interaction hinges on. `test_multi_kg_manager`
  50 checks (reclaim removes from kind/label indexes + slot + free-list,
  idempotent, out-of-range safe); `test_reasoning_atoms` 38 (reclaiming an
  operator drops it from `rk_operators_from` after the rebuild).
- **Purely additive** to `multi_kg_manager` (new slot + functions, two extra
  pushes in `_kg_build`/`kg_rebuild_index` with the usual legacy auto-grow), so
  existing behaviour is unchanged: full suite 273/273, coverage 241/241,
  `make lint-ints` clean.

## Wiring gate (what must happen before Phase B)

Wiring `kg_reclaim_atom` into `adm_sweep`'s dead-transition would, for the first
time, put `0` holes into `KG_ATOMS`. A scan audit found **~30 modules** that
iterate `kg_atoms()`; each loop body must guard `if a != 0` before that wiring is
safe. The heuristic flagged low-guard scanners to check first:
`agent/autonomous_loop.nova`, `kg/ann_index.nova`, `kg/competence_tracker.nova`,
`learning/atom_death_monitor.nova` (its own sweep loop needs the guard too).
`reasoning_atoms` and `query` already re-validate (`is_operator`/`a != 0`).

## Honest gaps

- **No physical memory reclaimed yet.** Under NOVA's bump allocator, nulling a
  slot drops the reference but does not return memory; the win arrives with id
  reuse (slot recycling) or a compacting pass — both gated on the handle audit.
  This ADR delivers the *contract and plumbing*, not the RAM saving.
- The death sweep still only marks `dead`; turning that into a reclaim call is
  Phase B, blocked on the scanner audit above.
- ≥1 M-atom codegen-bug-#11 ceiling (ADR-0066) is unchanged.

## Implementation Notes

- `src/kg/multi_kg_manager.nova`: `KG_FREELIST` slot, `_kg_has_freelist`,
  `_kg_freelist_push`, `kg_freelist_count`, `kg_reclaim_atom`; wired into
  `_kg_build` and `kg_rebuild_index`.
- Tests: `tests/unit/test_multi_kg_manager.nova` (`test_reclaim_atom`),
  `tests/unit/test_reasoning_atoms.nova` (`test_reclaim_invalidates_edges`).
- Design parent: ADR-0072. Edge index: ADR-0070.
