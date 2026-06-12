# ADR-0072: KG memory lifecycle — design for eviction / reclamation / paging (P1.7)

## Status

Proposed (design only — no implementation in this pass; see "Why design-first").

## Date

2026-06-12

## Context

The KG grows monotonically in RAM. `kg_add_atom` always allocates a fresh id
(`KG_NEXTID++`) and `KG_ATOMS` only ever appends; `kg_remove_atom` is a **soft**
removal (it unlinks from the label/kind/ANN indexes but leaves the atom object
in `KG_ATOMS`). So nothing reclaims memory, and a long-lived agent's footprint
rises without bound.

A **policy** layer already exists — `atom_death_monitor.nova`: activation decay
(`adm_decay`), a belief-evidence floor (`DEATH_BELIEF`), protection flags,
tombstone/dead marks, and sweeps (`adm_sweep`, `adm_sweep_attributed`) that
decide *which* atoms are collectable. What is missing is the **mechanism**: the
sweeps mark atoms but cannot return their memory, because the store has no
reclamation path and no cold tier. This ADR designs that mechanism.

## Why design-first (not implemented here)

The obvious fix — a free-list so `kg_add_atom` reuses tombstoned slots — would
**reuse atom ids**, and several subsystems treat an atom id as a stable, unique
handle for the atom's lifetime:

- **The P1.5 edge index (ADR-0070)** keys `from_lists`/`to_lists` by atom id and
  is append-only; a reused id would inherit the *previous* occupant's edges.
- Snapshot delta replication serializes premise/conclusion **by label** precisely
  because ids are not stable across load — but within a run they are assumed
  stable (handles, xrefs, episodic records, link-prediction neighbour lists).

Reusing ids without invalidating every derived index is a correctness hazard.
Getting this wrong silently corrupts reasoning, so it must be designed before
it is built — hence this ADR.

## Decision (proposed phased design)

**Phase A — generational ids + true reclamation (bounds growth under churn).**
Replace bare ids with `(slot, generation)` or keep integer ids but add a
free-list of reclaimed slots whose **generation counter** is bumped on reuse.
`kg_remove_atom` becomes a hard tombstone: `atoms[id] = 0`, push `id` to the
free-list, and **invalidate derived indexes for that id** (the edge index entry,
ANN bucket — label/kind already handled). `kg_add_atom` pops a free slot when
available. Consumers that cache an id revalidate via a generation check
(`handle_is_live`). The edge index gains a per-id generation tag so a stale edge
referencing a recycled slot is dropped on lookup (it already re-validates
`is_operator`; add a generation match).

**Phase B — wire the death sweep to reclamation.** `adm_sweep` already selects
collectable atoms; have it call the Phase-A hard `kg_remove_atom`. Add a
configurable cap (`KG_MAX_ATOMS`) that triggers a sweep when exceeded, evicting
the lowest activation×belief atoms first (protected/recently-referenced atoms
exempt). This turns the existing decay policy into an actual LRU-ish bound.

**Phase C — cold tier / on-disk paging.** For atoms below the activity threshold
but still worth retaining (not collectable), page them to the snapshot store
keyed by label, leaving an in-RAM stub; fault them back in on access. Reuse the
existing snapshot serialization (atoms already round-trip there) and the
label-based restore path. This is what lets the working set exceed RAM.

## Consequences (intended)

- Memory bounded under churn (Phase A), under growth (Phase B), and beyond RAM
  (Phase C) — closing the P1.7 scaling gap.
- The death policy that already exists becomes load-bearing instead of advisory.

## Honest gaps / risks

- **Id-reuse correctness is the whole risk.** Every id-keyed cache must adopt the
  generation check or be rebuilt on reclamation; missing one corrupts results
  silently. Phase A must ship with an audit of id-as-handle assumptions
  (edge index, xrefs, episodic, link-prediction, handles, snapshot delta).
- **Edge index interaction (ADR-0070):** the index must learn generations, or be
  rebuilt after any sweep. Simplest safe first cut: after a sweep, mark the edge
  index unbuilt so it lazily rebuilds (already supported) — at the cost of one
  O(atoms) rebuild per sweep.
- **Codegen bug #11** still caps id magnitudes at 0x100000 until the NOVA
  tagged-values fix (ADR-0066); generational ids that pack slot+gen into one int
  would hit it sooner, so a struct pair is preferable.
- Phase C changes durability/latency semantics (a read can fault from disk) and
  needs its own ADR + benchmarks before implementation.

## Recommended first increment

Phase A's **edge-index-rebuild-on-sweep** variant (mark unbuilt after a sweep)
plus a hard `kg_remove_atom` + free-list, **without** id reuse initially (freed
slots stay 0; the free-list is observability only) — this proves the
reclamation plumbing and the index-invalidation hook with zero id-reuse risk,
and is independently testable. Id reuse (the real memory win) lands once the
handle-audit is done.
