# ADR-0088: Cross-KG xref query-time traversal

- Status: Accepted
- Date: 2026-09-26

## Context

The cross-KG-reference machinery accumulated during the memory-lifecycle GC arc
now covers persistence, compaction, snapshotting, and coactivation:

- **ADR-0077** — same-KG xref persistence: xrefs written on the source atom via
  `atom_add_xref`, restored under a snapshot load.
- **ADR-0078** — cross-KG xref persistence: xrefs whose destination is in a
  different KG survive `chat_state` round-trips.
- **ADR-0079** — the in-place `kg_compact` rewrites xref src/dst atom ids so
  compaction cannot dangle any persisted xref.
- **ADR-0085** — `XR_COACT` (the xref coactivation counter) is persisted and
  restored, so a xref that has been corroborated N times over a daemon's
  lifetime keeps that corroboration across a save/load.

What the arc **did not** close: the reader / query layer never actually
consumed those xrefs at query time. `src/reader/neighborhood.nova` did include
a `_walk_xrefs` step, but it walked ONLY the source atom's own xref list, ONE
hop deep, with no coactivation filter -- so a source-side xref would surface
its immediate destination as a neighbor at that xref's raw `xref_weight`, but:

- transitive links (X --xref--> Y --xref--> Z) never surfaced -- Z remained
  invisible to a reader that had loaded X;
- the persisted `XR_COACT` counter, which is what tells the system that a
  candidate cross-KG link has been corroborated MANY times vs a chance
  one-time coactivation, was never consulted at query time;
- a heavily-xref'd atom had no per-call fanout cap, so an atom with hundreds
  of xrefs would drag every one of them into the neighborhood.

Without a query-time consumer, ADRs 0077 / 0078 / 0079 / 0085 were persisting
metadata that the query path could not read. This ADR closes that thread and,
together with ADR-0086 (auto-compact trigger) and ADR-0087 (GC observability),
closes the entire memory-lifecycle GC arc (ADR-0074 through ADR-0088).

## Decision

**Add a public xref-iterator on `cross_kg_references.nova`:**

- `xr_iter_from(atom_id_arg, kg)` -- enumerates every xref where `atom_id_arg`
  (inside `kg`) is the SOURCE side, returning
  `[[dst_kg_label, dst_atom_id, coact_count], ...]` sorted descending by
  `coact_count`. Highest-corroboration first, so a fanout cap keeps the top-N
  strongest edges. Xrefs are stored on the source atom via
  `atom_add_xref(src_atom, x)`, so every entry in `atom_xrefs(a)` has `a` as
  its source by construction -- no filter needed inside the iterator, just an
  order-by-coact sort.

**Extend `src/reader/neighborhood.nova` with the R3 traversal:**

- `_nb_follow_xrefs(atom_id_arg, kg, reg, depth_remaining, out_neighbors, visited)`
  walks xrefs transitively, bounded by depth (recursion depth), fanout (per-call
  cap), and min-coact (per-xref filter). Appends `[handle, coact_count]` entries
  into `out_neighbors`; adds each discovered destination handle into `visited`
  so subsequent recursion (or a re-encounter through a cycle) cannot revisit
  a source-and-destination pair the traversal has already emitted.
- `nb_xref_traversal(reg, source_handle)` -- public entry point. Seeds the
  visited set with the source itself (so a Y --> X loop cannot re-add X), reads
  `MAX_DEPTH` from the module-level config, and dispatches into
  `_nb_follow_xrefs`. Returns `[[handle, coact_count], ...]` in traversal
  order (each level is coact-DESC courtesy of `xr_iter_from`).
- `find_neighbors_full` folds R3 handles into the accumulator AFTER the hop-1
  and hop-2 frontier walks. R3 additions are not treated as hop-2 seeds --
  this keeps R3's own depth semantics independent from `max_hops` (a hop-2
  chase over R3 additions would implicitly double R3's depth). Strength is
  `fp_mul(min(coact_count, 1000), FP_SCALE)`, accumulated by `_nh_add` (which
  clamps at 1000 and de-dupes with the operator / xref-weight / word-sense /
  cofire / slot walks).

**Env-var contract** (lazy-loaded via `_nb_xref_config_load`, cached on
module-level singletons, forcible re-read via `_nb_xref_config_reset` for
tests):

| Var | Default | Meaning |
| --- | --- | --- |
| `CROSSENGIN_READER_XREF_MAX_DEPTH`  | `1` | Transitive walking depth. `0` disables R3 (pre-R3 byte-equivalent). |
| `CROSSENGIN_READER_XREF_MAX_FANOUT` | `8` | Per-call cap on xrefs followed from a single atom (post-coact-filter). |
| `CROSSENGIN_READER_XREF_MIN_COACT`  | `2` | Skip xrefs whose coact_count is below this. |

The env parser is a superset of the ADR-0086 `_ac_env_int`: it accepts a bare
`"0"` (single byte) as a legitimate value (MAX_DEPTH=0 explicitly disables the
walk) while still treating unset / empty / negative / non-numeric-parsing-to-0
inputs as garbage and falling back to the default. This distinguishes an
intentional disable from a fat-finger.

**Coact-descending order** at the iterator layer means the fanout cap is
correctness-preserving: the top-N edges by coactivation count are kept, and
those are the ones whose corroborated history most justifies letting them
influence the neighborhood.

## Consequences

- **The xref-persistence work ships a query-side consumer.** ADRs
  0077 / 0078 / 0079 / 0085 now have a caller at the reader layer;
  `xr_iter_from` is the surface, and `nb_xref_traversal` is the walker. A
  heavily-corroborated cross-KG link now shows up in a reader neighborhood by
  default (MAX_DEPTH=1) rather than being structural metadata a query cannot
  read.
- **Default MAX_DEPTH=1, not 0.** The plan explicitly chose "opt-in for wider
  traversal but not disabled by default so xrefs ARE finally used". Pre-R3
  regressions do not appear because the R3 traversal is guarded by MIN_COACT=2,
  and existing test fixtures build xrefs without ever calling `xref_coactivate`
  -- their coact_count stays 0. The `test_r3_default_preserves_fixture` case
  in `test_neighborhood_activation.nova` asserts this directly: default env
  vs `MAX_DEPTH=0` produce bit-identical output on the `build_med` fixture.
- **Cycle safety by visited set.** The visited set is a small list keyed on
  handle; a repeat handle is skipped and its recursion pruned. So X -> Y -> X
  emits Y once and stops; a diamond X -> Y, X -> Z, Y -> Z emits Y and Z at
  their first-hop coact and does not re-emit Z through Y. Cost is O(depth *
  fanout) per traversal, well below the pre-R3 `_walk_word_senses` scan.
- **Dangling xrefs are a silent skip.** A xref whose `dst_kg_label` does not
  resolve to any KG in the registry (a stale reference to a KG that was
  unloaded, a wire-serialized xref whose destination KG the reader was not
  configured with) is skipped without raising. A hard failure would surface a
  benign-in-practice inconsistency (persisted xrefs long outlive individual
  reader configurations) as a crash. Snapshot loaders and the ADR-0079
  compactor already handle their own consistency; the reader is best-effort.
- **Bounded by design.** Depth * fanout * min_coact give three independent
  levers. MAX_DEPTH tunes reach; MAX_FANOUT tunes per-atom breadth; MIN_COACT
  tunes signal-to-noise. Each is orthogonal, so an operator worried about
  neighborhood blow-up on one axis can raise the constraint on that axis
  without touching the others.
- **Additive to the accumulator.** R3 does not replace `_walk_xrefs`; it
  layers on top. A xref discovered by both surfaces its destination at
  clamp(operator_weight + xref_weight + R3_coact_strength, 1000). Cofire and
  slot side-indices, being independent of xrefs, remain unaffected.
- **No impact on the reader's public API.** `find_neighbors` and
  `find_neighbors_full` keep their existing signatures. Only the internal
  fold in `find_neighbors_full` gained an ADR-0088 branch.

## Alternatives Considered

- **Config: MAX_DEPTH default = 0 (opt-in).** Rejected: this would ship the
  R3 machinery in a state where xrefs are still ignored at query time
  by default -- functionally equivalent to not shipping R3. The plan called
  out "not disabled by default so xrefs ARE finally used". Fixture immunity
  is instead achieved by MIN_COACT=2, which no test fixture explicitly
  clears.
- **Strength derived from xref_weight, not coact_count.** Rejected: the
  `_walk_xrefs` pass already contributes `xref_weight` at hop 1. Using
  coact_count as R3's strength gives R3 a distinct information channel
  (corroboration frequency, not one-shot similarity) and makes the
  additive clamp meaningful (both signals reinforcing a neighbor drives it
  to 1000 faster than either alone).
- **BFS across all KGs, no per-atom fanout cap.** Rejected: an atom with
  hundreds of xrefs (e.g. a hub concept like "person") would drag every
  destination into every neighborhood. The MAX_FANOUT cap plus the
  coact-DESC ordering preserves the strongest edges deterministically.
- **Hop-2 chase over R3-added handles.** Rejected: the existing `find_neighbors`
  `max_hops=2` frontier walks over hop-1 acc entries. If R3 pushed its
  additions BEFORE hop-2, those R3 additions would become hop-2 seeds and
  R3's own recursion would implicitly double in depth. Running R3 AFTER
  hop-2 keeps depth semantics independent.
- **Hard error on dangling xrefs.** Rejected: cross-KG xrefs persist across
  runs; a reader configured with a subset of KGs is a legitimate deployment
  shape. A silent skip is best-effort and matches the ADR-0079 compactor's
  own "silently rewrite what you can, leave the rest" philosophy.
- **Cache the traversal result on the source atom.** Rejected: xref coact
  counts change over the daemon's lifetime (each `xref_coactivate` bump);
  a cache would need an invalidation signal. The current per-atom cost is
  O(atom.xrefs) for `xr_iter_from` plus O(depth * fanout) for the walk,
  both small enough that caching adds complexity without saving cycles.

## Implementation Notes

- `src/kg/cross_kg_references.nova` (+~50 lines): `xr_iter_from` iterator
  and its per-atom coact-DESC sort. Reuses `xref_dst_kg`, `xref_dst_atom`,
  `xref_coact`, and `atom_xrefs` -- no new fields.
- `src/reader/neighborhood.nova` (+~140 lines): module-level env-var config
  block with `_nb_env_int` (a strict env parser that admits literal `"0"`);
  `_nb_xref_config_load`/`_nb_xref_config_reset` for lifecycle; `_nb_visited_contains`,
  `_nb_follow_xrefs`, and `nb_xref_traversal` for the traversal; a single
  new branch in `find_neighbors_full` that folds R3 handles into the acc
  AFTER hop-2 completes.
- `tests/unit/test_reader_xref_traversal.nova`: 18 test functions, ~55 checks
  covering iterator ordering, MIN_COACT filter (default + boundary +
  inclusive-equal), MAX_FANOUT cap (0 edge, top-N ordering), MAX_DEPTH
  (0 disables, 1 stops-at-first-hop, 2 transitive, 2 chain), cycle safety,
  dangling xrefs, null-arg guards, isolated-atom guards, and the
  `find_neighbors_full` integration.
- `tests/unit/test_neighborhood_activation.nova` extended with one regression
  case (`test_r3_default_preserves_fixture`) that asserts default env vs
  MAX_DEPTH=0 produce identical neighborhoods on the pre-R3 fixture.
- `make lint-ints` clean: the only new integer arithmetic is
  `depth_remaining - 1` in the recursion (bounded by MAX_DEPTH, single
  digits) and the coact clamp `if s > 1000 { s = 1000 }` in the fold
  (bounded by clamp). No large-literal multiplies, no new
  comparisons against negative literals.
