# ADR-0086: Auto-compact trigger via autonomous_loop freelist watch

- Status: Accepted
- Date: 2026-09-26

## Context

The memory-lifecycle GC arc (ADR-0072..0085) landed the full machinery for
reclaiming atoms: `kg_reclaim_atom` (ADR-0074) frees an atom slot and records
it on the per-KG freelist, `adm_sweep_ep` (ADR-0075, extended in ADR-0080..0082)
drives the two-phase tombstone-then-reclaim over collectable atoms, and
`kg_compact` (ADR-0079) hole-removes the freelist in-place with a full
registry-wide operator/xref remap.

Nothing yet **invokes** `kg_compact` in the live loop. `kg_reclaim_atom` leaves
zero-holes in `KG_ATOMS`; every subsequent scan over `kg_atoms(kg)` walks those
holes. Under any sustained reclaim churn the freelist grows without bound over
the daemon's lifetime, bounded only by process restart -- there is no admin
command wired up either. Long-running deployments therefore accumulate zero-
holes indefinitely, wasting scan cycles proportional to (reclaims_so_far /
atoms_alive) on every walk.

This ADR wires a **cheap, rate-limited watcher** into the autonomous loop's
tick body that samples the per-KG freelist-to-live ratio and invokes
`kg_compact` when the ratio grows past a threshold, subject to a per-KG
cooldown so back-to-back threshold-crossings can never thrash-compact the
same KG.

## Decision

**Helpers (in `src/kg/multi_kg_manager.nova`, colocated with the KG record
layout constants they read):**

- `kg_freelist_size(kg) -> int` -- length of the reclaimed-slot freelist. An
  ADR-0086-named alias for the existing `kg_freelist_count`; the two are
  intentionally kept as separate names so the trigger call sites read as
  "watch the freelist size", while the observability path can stay on the
  older ADR-0074 naming.
- `kg_atoms_alive(kg) -> int` -- count of non-null slots in `KG_ATOMS`
  (delegates to the existing `kg_live_atom_count`, again spelled per ADR-0086
  so the trigger code reads clean).
- `kg_freelist_ratio_permille(kg) -> int` -- `(freelist_size * 1000) /
  atoms_alive`, with an `atoms_alive == 0` guard that returns 0 so a fully-
  reclaimed KG or a fresh empty one does not divide by zero.

Both `kg_freelist_count` and `kg_live_atom_count` already existed (from
ADR-0074 / ADR-0079); the two aliases are one-line delegates. The ratio helper
is the only genuinely new computation.

**Auto-compact trigger (in `src/agent/autonomous_loop.nova`):**

- New agent slot `AG_LAST_COMPACT` (index 19): a `[kg_label, last_tick]` list,
  one entry per KG that has been compacted at least once during the agent's
  lifetime. Linear-scan lookup on the small (4-6 KGs at boot) registry.
- Helpers `_ag_last_compact_get(ag, kg_label) -> int` and
  `_ag_last_compact_set(ag, kg_label, tick)`. `get` returns 0 for an unknown
  label (which `_ag_maybe_autocompact` treats as "never compacted -- fire").
- Helper `_ag_maybe_autocompact(ag, reg, now_tick)`:
  1. Lazy-loads the env-var config on first invocation into module-level
     singletons (`_ac_cfg_*`); subsequent calls skip the reload.
  2. Bails out immediately when the loaded config is `enabled == 0`.
  3. Every `CHECK_EVERY_TICKS`, iterates `kg_get(reg, 0..kg_count-1)`.
  4. For each live KG: samples `kg_freelist_ratio_permille(kg)`; skips when
     under `THRESHOLD_PERMILLE`; skips when `now_tick - last_compact_tick <
     MIN_INTERVAL_TICKS`.
  5. Otherwise calls the registry-wide `kg_compact(reg, kg)` (per ADR-0079,
     which remaps operators and xrefs across the whole registry), and
     records the new `last_compact_tick` on `AG_LAST_COMPACT`.
- Wired into `agent_cycle` right after the ADR-0081 GC block:
  `_ag_maybe_autocompact(a, a[AG_KGREG], now)`.

**Env-var contract** (read once at first invocation, cached on module-level
singletons):

| Var | Default | Meaning |
| --- | --- | --- |
| `CROSSENGIN_AUTOCOMPACT_ENABLED`             | `1`   | `"0"` disables the watcher; anything else (or unset) enables. |
| `CROSSENGIN_AUTOCOMPACT_THRESHOLD_PERMILLE`  | `200` | Fire when `freelist/alive >= threshold/1000` (default 20%). |
| `CROSSENGIN_AUTOCOMPACT_MIN_INTERVAL_TICKS`  | `1000`| Per-KG cooldown between compactions. |
| `CROSSENGIN_AUTOCOMPACT_CHECK_EVERY_TICKS`   | `64`  | Sample cadence: only checked on `now_tick % every == 0`. |

The env-var read follows the canonical guard used elsewhere in the codebase
(`_co_env_int` in `snapshot_compaction.nova`): unset (`env == 0`) OR empty
(`len(env) == 0`) falls back to the default; `str_to_int` returning `<= 0`
also falls back so a garbage value cannot silently disable the watcher.

The `_ac_config_reset()` test-hook forces a re-read on the next call; it is
called by every test that toggles the config so state cannot leak across
tests via the module-level cache.

## Consequences

- **Freelist no longer grows unbounded.** A daemon under sustained reclaim
  churn now compacts the affected KG in bounded time -- at most once per
  `MIN_INTERVAL_TICKS`, with the first compaction firing on the first
  check-every tick after the ratio crosses threshold.
- **Zero cost when the freelist is small.** The ratio check is O(atoms) but
  only sampled every `CHECK_EVERY_TICKS` ticks, and `kg_compact` runs only
  when the ratio is above threshold. On a fresh KG with no reclaims the
  watcher does O(kg_count) work every 64 ticks and calls nothing.
- **Wiring gate closed for ADR-0079.** The in-place compactor was previously
  reachable only through tests and (eventually) an unwritten admin command.
  This ADR is the primary production caller; the /compact admin surface (if
  it lands later) is now purely operator-driven, not the only lifeline.
- **Rate-limited per-KG.** A pathological ingest that alternates rapid
  reclaims and re-inserts on the SAME KG cannot cause back-to-back
  compactions: the second is suppressed by `MIN_INTERVAL_TICKS` until at
  least 1000 ticks have elapsed since the previous one on that KG. The
  cooldown is per-KG so an unrelated KG that separately crosses threshold
  compacts on its own schedule.
- **No observability yet.** The watcher does not increment any counters or
  emit a moment; that is ADR-0087 (GC observability, Phase L R2). An
  operator today sees the effect only indirectly through `kg_freelist_size`
  reads.
- **Bench loop still doesn't trigger a compaction.** `agent_run(a, 30, ...)`
  in the autonomous-loop tests ticks `now` from 1 to 30, never crossing the
  first check-every boundary (64). This is intentional: R1 must not perturb
  the ADR-0081/0082 test expectations. The trigger is exercised by
  `tests/unit/test_autocompact_trigger.nova` directly with hand-driven ticks.

## Alternatives Considered

- **Trigger on every reclaim.** Rejected: `kg_compact` is O(atoms + ops +
  xrefs) so firing it on every reclaim is quadratic in the reclaim volume.
  A sampled watcher amortizes the cost.
- **Global threshold across all KGs.** Rejected: a single fat KG would starve
  others' compactions or force premature ones. Per-KG threshold + per-KG
  cooldown gives each KG its own schedule.
- **Compact-on-save only.** ADR-0075's snapshot path already has a
  `CE_AUTO_COMPACT_ON_SAVE` env var that runs the SNAPSHOT compactor
  (a different subsystem -- `snap_compact`, not `kg_compact`) before writing
  the on-disk image. That path shrinks the persisted snapshot but leaves the
  live in-memory freelist untouched. This ADR fills the live-memory gap;
  the two mechanisms compose (a save-time snapshot compaction PLUS a
  run-time in-memory compaction).
- **Wall-clock cadence.** Rejected: the autonomous loop is tick-driven and
  reproducible; a wall-clock cadence would make the compaction schedule
  non-deterministic and hard to test.

## Implementation Notes

- `src/kg/multi_kg_manager.nova`: three new one/three-line helpers next to
  `kg_freelist_count`. No changes to the freelist mechanism itself.
- `src/agent/autonomous_loop.nova`: new `AG_LAST_COMPACT = 19` slot pushed
  in `agent_new`; four config accessors + one env-parse helper + the two
  last-compact map accessors + the watcher itself. Wired into `agent_cycle`
  after the ADR-0081 maintenance block, before the cycle counter bump.
- `tests/unit/test_autocompact_trigger.nova`: 12 test functions, 40 checks.
  Each mutates `_ac_cfg_*` only via `_ac_config_reset()` or a scoped direct
  poke followed by a reset, so tests don't cross-contaminate.
- `make lint-ints` stays clean: the only new integer arithmetic is
  `fl * 1000 / alive` in the ratio helper, with `fl` and `alive` both
  bounded by `len(KG_ATOMS)` well below the codegen threshold.
