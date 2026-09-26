# ADR-0087: GC observability (metrics registry + /gc-stats chat command)

- Status: Accepted
- Date: 2026-09-26

## Context

The memory-lifecycle GC arc (ADR-0072..0086) landed the full machinery for
reclaiming atoms and compacting KGs:

- `kg_reclaim_atom` (ADR-0074) hard-frees an atom slot and records the id on
  the per-KG freelist.
- `adm_sweep_ep` (ADR-0075, extended in ADR-0080..0082, ADR-0084) runs the
  two-phase tombstone-then-reclaim sweep with an episodic-and-alias-aware
  protection context.
- `kg_compact` (ADR-0079) hole-removes the freelist in-place with a full
  registry-wide operator/xref remap.
- `_ag_maybe_autocompact` (ADR-0086) is the primary production caller of
  `kg_compact`, wired into the autonomous loop's tick body.

All of that runs **silently**. An operator has no way to see:

- how many atoms this daemon has reclaimed over its lifetime;
- whether the operator-premise / operator-conclusion / episodic-member /
  alias protection gates ever actually protected anything (or whether they
  are latent-safe machinery whose refusal branch is cold);
- how many compaction runs the ADR-0086 watcher fired, and how many atoms
  each collapsed;
- the current per-KG freelist size and ratio.

ADR-0086 explicitly deferred observability to this round ("No observability
yet. The watcher does not increment any counters or emit a moment; that is
ADR-0087."). This ADR closes that thread.

## Decision

**A per-agent GC-metrics registry** at `src/kg/gc_metrics.nova`. The registry
is a list-of-slots (see the file header) with a `GCM_KG_LABELS` list and
one parallel counter list per counter type. `gcm_ensure_kg` auto-adds a KG
label (extending every counter list with a fresh 0) so counters and labels
stay in lockstep. Lookup is O(n) linear scan over the label list; the KG
registry is small (single-digit KGs at boot, dozens with learning) so O(n)
is fine and avoids NOVA's 16-key builtin-map cap.

**Counter surface** (per KG, aggregated across agent lifetime):

| Metric | Kind | Bump site |
| --- | --- | --- |
| `reclaimed_total` | counter (+1) | every successful `kg_reclaim_atom_metric` and every sweep-driven reclaim inside `_adm_sweep_ep_metric` |
| `swept_total` | counter (+n) | `adm_sweep_attributed_metric`: number of atoms removed on that call |
| `swept_episodic_total` | counter (+n) | `adm_sweep_ep_metric`: number of atoms removed on that call |
| `protected_operator_premise` | counter (+1) | `_adm_collectable_metric` refused because a live operator names the atom as its `premise` |
| `protected_operator_conclusion` | counter (+1) | same, but the atom is a `conclusion` |
| `protected_episodic_member` | counter (+1) | same, but the atom is a member of an episodic cluster (ADR-0080) |
| `protected_alias` | counter (+1) | same, but the atom is an alias resolution target (ADR-0082) |
| `compact_runs_total` | counter (+1) | every `kg_compact_metric` call (via `gcm_record_compact`) |
| `compact_atoms_removed_total` | counter (+n) | per-run `pre_count - post_count` (holes collapsed) |
| `compact_last_tick` | overwrite | last-run tick the compactor was invoked at |
| `freelist_size_sampled` | overwrite | current freelist length, re-sampled every autonomous-loop check tick |
| `freelist_ratio_permille_sampled` | overwrite | current `freelist * 1000 / alive`, re-sampled every check tick |

**Wire-up (additive, backwards-compatible)**. NOVA has no default arguments,
so each modified function gets a sibling `_metric` variant that adds
`metrics_reg` (and, where relevant, an explicit `kg_label`) at the tail:

- `src/kg/multi_kg_manager.nova`:
  - `kg_reclaim_atom_metric(kg, atom_id, metrics_reg, kg_label_arg)` -- calls
    `kg_reclaim_atom`; when it returns 1 (an atom was reclaimed), increments
    `reclaimed_total`.
  - `kg_compact_metric(reg, kg, metrics_reg, kg_label_arg, at_tick)` --
    measures `pre_count - post_count`, calls `gcm_record_compact` +
    `gcm_sample_freelist` to record the run and post-compact steady state.
- `src/learning/atom_death_monitor.nova`:
  - `_adm_operator_reason(reg, atom)` -- returns 1 (premise), 2 (conclusion),
    or 0 (neither). Mirrors `_adm_is_operator_referenced` but reports the
    role so the metrics can attribute the protection.
  - `_adm_collectable_metric(reg, atom, prot, mreg, kg_label)` -- inlines the
    `adm_is_collectable_ep` gate chain and records the specific protection
    that first refused collection on `mreg`.
  - `_adm_sweep_ep_metric(reg, kg, mo, prot, mreg, kg_label)` -- the sweep
    core with metric attribution. `adm_sweep_ep` now delegates here with
    `mreg=0` (byte-equivalent).
  - `adm_sweep_ep_metric(reg, kg, mo, prot, metrics_reg, kg_label)` --
    episodic-aware public entry point. Bumps `swept_episodic_total` by the
    removed count.
  - `adm_sweep_attributed_metric(reg, kg, mo, metrics_reg, kg_label)` --
    non-episodic public entry point. Bumps `swept_total` by the removed
    count.
- `src/agent/autonomous_loop.nova`:
  - New agent slot `AG_GC_METRICS = 20`. `agent_new` allocates a fresh
    registry via `gc_metrics_new()`, pushes it into the slot, AND installs
    it as the module-level default (`gc_metrics_set_default`) so the chat
    REPL's `/gc-stats` handler (which has no `agent` in scope) reads the
    same registry.
  - Public accessor `agent_gc_metrics(a)`.
  - The ADR-0086 auto-compact call site is upgraded to `kg_compact_metric`
    with the agent's registry; the watcher also samples the freelist
    unconditionally on every check tick (independent of whether a
    compaction fires) so `/gc-stats` reflects the current state.
  - The ADR-0081 GC block (`adm_sweep_ep`) is upgraded to
    `adm_sweep_ep_metric` with the agent's registry + KG label.
- `examples/crossengin_chat.nova`:
  - New `/gc-stats [kg=<label>]` slash-command handler. Reads
    `gc_metrics_default()`, snapshots it via `gcm_snapshot(reg)`, filters by
    the optional `kg=<label>` argument, and prints one block per KG:
    ```
    KG <label>:
      reclaimed=N  swept=N  swept_episodic=N
      protected_operator_premise=N  ...conclusion=N  episodic_member=N  alias=N
      compact_runs=N  atoms_removed=N  last_tick=N
      freelist_size=N  freelist_ratio_permille=N
    ```
  - Empty registry (no autonomous loop has been run yet in-process) prints
    `no GC activity yet`.
  - Filter miss (no such KG label in the registry) prints
    `no GC activity yet for KG '<label>'`.

## Consequences

- **Observable GC.** An operator can now read live counters via `/gc-stats`
  without instrumenting the daemon. This is the primary handle for tuning
  the ADR-0086 threshold + interval defaults: too many compact runs means
  the threshold is too aggressive; a growing `freelist_size` with no runs
  means it is too lax.
- **Attribution is honest.** The metric-attributed collectability gate
  (`_adm_collectable_metric`) records the FIRST protection that refused
  collection -- not every one that would have. Base-gate refusals (hard-
  protected, still-active, well-evidenced, xref-referenced) are NOT
  attributed to any `protected_*` counter, because they are ordinary "atom
  is alive" cases rather than specialized protection gates.
- **Additive wire-up.** Every existing caller of `kg_reclaim_atom`,
  `kg_compact`, `adm_sweep_ep`, and `adm_sweep_attributed` continues to
  work unchanged. Their outputs and side effects are byte-equivalent to
  pre-R2. Only sites that opt in (the autonomous loop, tests) route
  through the `_metric` variants.
- **Zero overhead when metrics are off.** The `metrics_reg == 0` sentinel
  short-circuits every counter increment; a bare-metal caller (a test, a
  legacy loop) pays no cost.
- **Overwrite vs accumulate.** Compact runs and atoms-removed accumulate;
  `compact_last_tick`, `freelist_size_sampled`, and
  `freelist_ratio_permille_sampled` overwrite. `/gc-stats` therefore
  reports lifetime totals for the first two and a point-in-time snapshot
  for the latter three -- the natural semantics for each metric.
- **Shared default = shared readback.** The autonomous loop installs its
  per-agent registry as the module-level `_gcm_default`. If multiple agents
  ever share one process (unusual today; possible in future federation
  work), the LAST-constructed agent wins the default slot -- but each
  agent still owns its own registry, accessible via `agent_gc_metrics(a)`.
- **No wire into the reader / query path.** ADR-0088 (R3) will extend the
  reader to consume xrefs at query time. GC metrics are DAEMON-side; they
  do not appear in the reader's neighborhood or in a query result.

## Alternatives Considered

- **Per-atom histogram.** Rejected: per-atom counters would grow with
  storage rather than with the KG count; the observability question is
  "how often did the GC run", not "which atom got protected most".
- **Emit moments.** Rejected: moments are the perception seam
  (world-events, tool results). GC events are internal accounting, not
  perception; a moment would confuse the router.
- **Shared global registry, no per-agent slot.** Rejected: keeps the plumbing
  test-friendly. Per-agent + a module-level default (installed by
  `agent_new`) gives both: tests thread their own registry through the
  API; the chat REPL reads the same registry back through the default.
- **Log-file emit.** Rejected: log files are not queryable. A counter
  registry is O(1) read; a log is O(events) grep.
- **Attribute EVERY protection gate that refused, not just the first.**
  Rejected: adds noise. The first-refusal gate is the reason the atom
  survived; recording later gates that would have also refused would
  over-count the protection rate.

## Implementation Notes

- `src/kg/gc_metrics.nova` (~280 lines): the registry factory, per-slot
  increment / read helpers, the module-level default + reset test hook,
  and the snapshot builder. All O(1) per bump given the small label list.
- `src/kg/multi_kg_manager.nova`: two thin wrappers (`kg_reclaim_atom_metric`,
  `kg_compact_metric`); no changes to the existing `kg_reclaim_atom` or
  `kg_compact` semantics.
- `src/learning/atom_death_monitor.nova`: refactor to route both existing
  sweeps through the new `_adm_sweep_ep_metric` core with `mreg=0`; adds
  the `_adm_operator_reason` role classifier and `_adm_collectable_metric`
  attributed gate.
- `src/agent/autonomous_loop.nova`: new `AG_GC_METRICS = 20` slot;
  `agent_new` allocates + installs; `agent_gc_metrics` accessor;
  `_ag_maybe_autocompact` and the ADR-0081 sweep upgraded to their
  `_metric` variants.
- `examples/crossengin_chat.nova`: new `/gc-stats` handler; help text row;
  dispatch entry alongside `/compact`.
- `tests/unit/test_gc_metrics.nova`: 11 test functions, ~83 checks --
  every counter, per-KG isolation, snapshot shape, 0-registry no-op,
  default-registry lifecycle.
- Existing suites extended with a one-shot metric-integration check each
  so a regression in the wire-up (rather than the registry itself) is
  caught at the sweep / compact / autonomous-loop layers.
- `make lint-ints` clean: no new large-literal arithmetic, no new
  comparisons against a negative literal. The only arithmetic in the new
  code is `pre_count - post_count` and `list_set(reg[slot], idx, cur + delta)`,
  both bounded by `len(kg_atoms(kg))` -- well below the codegen threshold.
