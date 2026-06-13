# ADR-0082: Alias-referenced death-gate protection and feeding observation ids into consolidation

- Status: Accepted
- Date: 2026-06-13

## Context

ADR-0081 wired the memory-lifecycle machinery (episodic consolidation +
episodic-aware GC sweep) into the live autonomous loop and, in doing so, left two
honest gaps:

1. **The death gate does not know about the entity-resolution alias table.**
   `AG_ALIASES` is an id-holder: an alias entry resolves a surface mention to a
   concrete atom. ADR-0080 already taught the gate to spare episodic cluster
   members; the alias table got the same treatment as episodic membership did NOT
   exist yet. A cold aliased atom could be reclaimed while an alias still pointed
   at it -- the same dangling-reference hazard the episodic gate (ADR-0080) and
   the operator/xref gates (ADR-0076/0017) guard against.

2. **The agent's episodic store stays EMPTY in the live loop.** The maintenance
   block ran `episodic_consolidate` over `AG_STREAM`, but `AG_STREAM` holds only
   tool-result moments whose traces are empty -- they never group into a recurring
   cluster. Episodic protection was therefore wired-but-dormant: the gate could
   protect cluster members, but no clusters were ever minted.

## Decision

**1. Alias-referenced protection, threaded into the gate like episodic.**

- `entity_resolve.nova` gains a pure predicate `er_aliases_has_canonical(aliases,
  label)` that scans the `[alias_label, canonical_label]` table and returns 1 iff
  any entry's canonical label `str_eq`s `label`. The alias model stores LABELS,
  not ids: a mention resolves via `kg_find_atom(canonical)`, so the atom whose
  label equals an entry's canonical is that alias's resolution target. The
  predicate therefore matches by label (string), which is what the production
  alias table actually holds. entity_resolve does NOT import atom_death_monitor,
  so there is no import cycle.
- `atom_death_monitor.nova` imports `entity_resolve.nova` and adds
  `_adm_is_alias_referenced(aliases, atom)` (returns 1 when `aliases != 0` and
  `er_aliases_has_canonical(aliases, atom_label(atom)) == 1`), mirroring
  `_adm_is_episodic_member`.
- The protection gate is EXTENDED rather than forked: `adm_is_collectable_ep`
  and `adm_sweep_ep` each take a new trailing `aliases` param (convention: `0`
  disables the alias check, exactly like `eas`). The internal delegators
  `adm_sweep_attributed`/`adm_sweep` pass `0, 0`.
- The autonomous loop's ADR-0081 maintenance block now passes `a[AG_ALIASES]` as
  the new last arg to `adm_sweep_ep`.

**2. Feeding observation ids into consolidation so clusters actually mint.**

- A dedicated observation moment stream `AG_OBS_STREAM` (slot 18) is added to the
  agent and instantiated in `agent_new` (mirroring `AG_STREAM`). It is kept
  SEPARATE from `AG_STREAM` precisely so the tool-moment metric
  (`agent_metric_moments == 90`, 30 cycles x 3 tool steps) is not inflated.
- `_ag_ingest` now collects the cycle's resolved observation atom ids into an
  id-set and records them as the trace of one moment pushed into `AG_OBS_STREAM`.
  Because the cycle observes the SAME sentence every tick and entity resolution
  dedups to the SAME atoms (the P1+P3 property), the moment's trace signature
  recurs. The maintenance block's `episodic_consolidate(a[AG_EAS],
  a[AG_OBS_STREAM], 0, 0)` then mints a cluster once recurrence reaches
  `EPISODIC_MIN_RECUR`.
- The observation sentence was changed from "the agent reached the goal" (2
  distinct atoms -- below `EPISODIC_MIN_CLUSTER_SIZE = 3`, so the tally skipped
  it) to "the agent reached the goal in the world" (3 distinct atoms: agent,
  goal, world), which clears the cluster-size threshold while keeping the KG at 3
  atoms (well within the `<= 5` no-fragmentation bound).

## Consequences

- The GC sweep now respects two id-holders (episodic clusters AND the alias
  table) in addition to xrefs and operator premises/conclusions. A cold atom an
  alias still resolves to survives the sweep.
- The agent's episodic store is no longer dormant: a live 30-cycle run mints
  exactly one episodic cluster (verified by probe -- see Implementation Notes),
  proving the consolidation feed is real end-to-end.
- `test_autonomous_loop`'s ADR-0081 "agent owns an episodic store" check is
  strengthened to also assert `episodic_atoms_count(agent_eas(a)) >= 1`; the
  moments==90 and kg<=5 assertions remain intact.

## Honest gaps

- **Growing parameter list.** The gate now carries `eas` AND `aliases` as
  separate positional params (`adm_is_collectable_ep(reg, atom, eas, aliases)`,
  `adm_sweep_ep(reg, kg, mo, eas, aliases)`). Each new id-holder adds another
  bare param. A future refactor could bundle the id-holders into a single
  "protection context" record; this ADR deliberately did NOT do that, to keep the
  change a minimal mirror of the ADR-0080 shape and avoid touching every caller.
- **Label-based, so KG-ambiguous.** The gate matches by canonical LABEL with no
  KG qualifier, so an alias canonical that equals a same-label atom in a different
  KG would spare that atom too. This errs toward keeping atoms (safe for a
  protection gate) and is acceptable, exactly as documented for the episodic gate.
- **Dormant in the live autonomous loop (but correct).** `_ag_ingest` reads the
  alias table during resolution but never calls `er_alias_add`, so `AG_ALIASES`
  is empty in the live loop and the alias gate fires for nothing there -- the
  ADR-0081 fragmentation it backstops is already prevented by reinforce-on-
  observation. The gate is genuinely effective for any system that DOES curate
  aliases (verified by probe: an atom whose label is a canonical target is
  protected; a non-target is collectable; `aliases = 0` disables). Auto-recording
  HDC-resolution hits as aliases (which would activate the gate in the loop) is
  left as follow-up.

## Implementation Notes

Functions/slots ADDED in this change:

- `entity_resolve.nova`: `er_aliases_has_canonical(aliases, label)` (new pure
  label-scan predicate).
- `atom_death_monitor.nova`: `import "./entity_resolve.nova"`;
  `_adm_is_alias_referenced(aliases, atom)` (new). `adm_is_collectable_ep` and
  `adm_sweep_ep` gained an `aliases` param; the internal call sites and the two
  delegators (`adm_sweep_attributed`, `adm_sweep`) were updated to pass it.
- `autonomous_loop.nova`: new slot `AG_OBS_STREAM = 18` instantiated in
  `agent_new`; `_ag_ingest` records the resolved observation id-set as a moment
  into it; new helper `_ag_obs_add(ids, id)` (dedup append); the maintenance
  block consolidates `AG_OBS_STREAM` and passes `a[AG_ALIASES]` to the sweep; the
  observation sentence was changed to a 3-entity phrasing.

Tests: `test_alias_reference_protection` added to `test_atom_death_monitor.nova`
(builds a real alias entry via `er_alias_add(aliases, "synonym", atom_label(m))`);
the ADR-0080 calls in that file were updated to the new 4/5-arg signatures; the
ADR-0081 assertion in `test_autonomous_loop.nova` was strengthened.

Probe (throwaway) output, `agent_new(12345)` + `agent_run(a, 30, 1, 10)`:

```
episodic_atoms_count=1
kg_atoms=3
moments=90
edits=3
audit_ok=1
eval_steps=6  optimal=6
```
