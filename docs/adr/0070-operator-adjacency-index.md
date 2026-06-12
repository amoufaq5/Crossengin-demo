# ADR-0070: Operator adjacency index — O(degree) reasoning lookups (P1.5)

## Status

Proposed

## Date

2026-06-12

## Context

`rk_operators_from(rkg, premise_id)` and `rk_operators_to(rkg, conclusion_id)`
(`reasoning_atoms.nova`) were the hot path of all reasoning — the cognitive
router's forward-chain, single-triple, analogy/opposite surfaces, the NL-query
bridge, `rule_inference`, `proof_checker`, `neighborhood`, and the autonomous
loop all call them. Each call **scanned every atom in the KG** testing
`is_operator` + a premise/conclusion match: O(atoms) per lookup, so a single
forward-chain is O(depth × atoms) and a dialogue is O(turns × atoms). The P1
analysis flagged this as the system's main scaling bottleneck — fine at a few
thousand atoms, super-linear into the hundreds of thousands.

## Decision

Add a **generic directed-edge adjacency index** to the KG and have the reasoning
layer drive it, keeping the layers clean:

- **`multi_kg_manager.nova` (generic, no operator semantics).** A new optional KG
  slot `KG_EDGE_IDX` holds `[built, from_lists, to_lists]`, where `from_lists`
  and `to_lists` are list-indexed-by-atom-id → list of edge atom ids (the same
  list-of-lists shape as `KG_KIND_IDX`; dense atom ids give O(1) bucket access,
  no hashing). Generic API: `kg_edge_add(kg, edge_id, from_id, to_id)`,
  `kg_edges_from/to`, `kg_edge_index_built` / `_mark_built`, with a legacy
  auto-grow (`_kg_install_edge_index`) and presence guard (`_kg_has_edge_index`)
  exactly like the existing label/kind/ANN slots. `kg_rebuild_index` resets the
  slot to unbuilt.
- **`reasoning_atoms.nova` (the semantics).** `rop_new` records the edge
  (`premise → conclusion`) after setting its payload. `rk_operators_from/to`
  walk only the relevant bucket and **re-validate** each candidate
  (`kg_atom != 0 && is_operator && endpoint matches`), so the result is
  byte-identical to the old scan — same operators, **same atom-id order**.
  A lazy `_rk_ensure_edges` rebuilds the index from all live operators on first
  use when it is unbuilt.

**Why lazy rebuild.** On snapshot load, operators are restored by a second pass
that re-attaches `op`/`premise`/`conclusion` payloads *directly* (not via
`rop_new`; `snapshot_disk.nova` R51 pass), and `kg_rebuild_index` has already
reset the edge slot to unbuilt. The first post-load `rk_operators_*` call does
one O(atoms) scan to repopulate, then every subsequent lookup is O(degree). The
index is a derived cache — never serialized — mirroring the ANN side-index.

**Why append-only is safe.** `kg_remove_atom` is a soft removal (it drops the
atom from the label/kind/ANN indexes but leaves it in `KG_ATOMS`), so neither
the old scan nor the new index ever hid a "removed" operator — behaviour is
unchanged. A genuinely stale id (e.g. a future hard tombstone) is filtered by
the per-candidate re-validation, so no removal-sync hook is needed.

## Consequences

- Operator lookups are **O(out/in-degree)** instead of O(atoms). Benchmark
  (`tests/benchmark/bench_operator_lookup.nova`, N=2000 atoms / ~2300 edges,
  4000 lookups): linear scan **1330 ms** vs indexed **1 ms** → **~1132×**, with
  **parity** (both paths return the same 4580 hits — equivalence at scale).
- Behaviour is provably identical: `test_reasoning_atoms` adds a rebuild-
  equivalence test (post-reset lazy rebuild, order preserved) and a
  matches-full-scan property test (32 checks total); `test_multi_kg_manager`
  covers the generic edge API + legacy fallback (39 checks).
- Every reasoning consumer stays green (cognitive_router 55, nl_query 55,
  rule_inference 47, rule_explain 54, proof_checker 56, link_prediction 77,
  pagerank 90, graph_clustering 71, neighborhood_activation 45, autonomous_loop
  13, distributed_rules 42) and the snapshot suites (disk/reader/migrate/delta)
  confirm the slot-addition + rebuild path is sound. Full unit suite: 273/273.
  Coverage 241/241; `make lint-ints` clean.

## Honest gaps

- **Only `rk_operators_from/to` are indexed.** `query.nova`'s pattern executor
  (P1.6) and `rule_inference`'s candidate scans still walk all atoms; they are
  separate follow-ups that can reuse this same generic edge index.
- **The ≥1 M-atom ceiling is codegen bug #11, not this index.** Bucket-growth
  and bounds checks compare atom ids against list lengths with raw `<`/`>=`;
  once an id reaches `0x100000` those comparisons miscompile (see ADR-0066).
  This index is precisely what makes million-atom KGs tractable on the time
  axis, so retiring bug #11 (the NOVA tagged-values fix) is the natural next
  ceiling.
- **One-time O(atoms) rebuild after a load** (and on the first lookup of a fresh-
  from-snapshot KG); amortised to O(1) per lookup thereafter.
- Soft-removal semantics are inherited unchanged (a `kg_remove_atom`'d operator
  still resolves via both scan and index); making removal actually hide
  operators is an orthogonal change.

## Implementation Notes

- `src/kg/multi_kg_manager.nova`: `KG_EDGE_IDX` slot + `EI_*` layout,
  `_new_edge_index`, `_kg_has_edge_index`, `_kg_install_edge_index`,
  `kg_edge_index_built`/`_mark_built`, `_ei_bucket_push`/`_get`, `kg_edge_add`,
  `kg_edges_from`/`to`; wired into `_kg_build` and `kg_rebuild_index`.
- `src/parts/reasoning/reasoning_atoms.nova`: `_rk_build_edges`,
  `_rk_ensure_edges`; `rop_new`, `rk_operators_from`, `rk_operators_to` updated.
- Tests: `tests/unit/test_reasoning_atoms.nova`,
  `tests/unit/test_multi_kg_manager.nova`. Benchmark:
  `tests/benchmark/bench_operator_lookup.nova`.
