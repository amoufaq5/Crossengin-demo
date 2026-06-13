# ADR-0084: Synonym alias auto-record + death-gate protection context

- Status: Accepted
- Date: 2026-06-13

## Context

ADR-0082 added two pieces of machinery that this ADR finishes wiring and tidies:

1. **Dormant alias death-gate.** ADR-0082 added an alias-referenced protection
   gate (`_adm_is_alias_referenced` -> `er_aliases_has_canonical`) so the GC
   sweep never reclaims an atom that is still the resolution target of an
   entity-resolution alias. The gate is correct but was DORMANT in the
   autonomous loop: `_ag_ingest` resolves mentions but never records any alias,
   so the alias table the sweep is handed (`a[AG_ALIASES]`) is always empty and
   the gate never fires on a real target. Genuine synonyms (a mention that
   resolves to an existing atom by HDC similarity, with a different surface
   form) were resolved correctly but the resolution was neither cached nor
   recorded — so the synonym re-paid the HDC cost on every occurrence, and the
   resolved canonical was never marked as an alias id-holder.

2. **Growing positional param tail.** ADR-0082 left
   `adm_is_collectable_ep(reg, atom, eas, aliases)` and
   `adm_sweep_ep(reg, kg, mo, eas, aliases)` with a positional list of
   id-holder protection params that grows by one with each new id-holder.

## Decision

**Gap A — synonym alias auto-record (in the resolution layer).**
`er_resolve_or_create` now records `mention -> atom_label(resolved)` in the
alias table WHEN the resolution `via` is `ER_VIA_HDC` (a genuine similarity hit
to an EXISTING atom), the table is present (`aliases != 0`), AND the mention
differs from the resolved atom's canonical label (`str_eq(mention, canon) == 0`
guards against a no-op self-alias). It is NOT recorded for new mints
(`ER_VIA_NEW` — nothing to alias to yet) nor for exact/alias hits (already
canonical / already recorded). The fix lives in the resolution layer so every
caller (including `_ag_ingest`) benefits without change. `er_alias_add` dedups,
so re-recording the same synonym is harmless. This both caches the resolution
(the next occurrence takes the cheap alias path) and makes the resolved
canonical a real alias id-holder, so the ADR-0082 alias death-gate now protects
it in the live loop whenever a synonym is actually seen.

**Gap B — protection context record.** Introduced `adm_prot_new(eas, aliases)`
returning a tagged record `[ADM_PROT_TAG, eas, aliases]` with accessors
`_adm_prot_eas(p)` / `_adm_prot_aliases(p)` that treat `p == 0` as "no
protection" (return 0 for both id-holders). The two gate functions now take a
single `prot` param: `adm_is_collectable_ep(reg, atom, prot)` and
`adm_sweep_ep(reg, kg, mo, prot)`. They unpack the context and pass `eas` /
`aliases` to the unchanged `_adm_is_episodic_member` / `_adm_is_alias_referenced`
helpers. The back-compat delegators `adm_sweep_attributed` / `adm_sweep` pass
`0` (no protection). The autonomous-loop sweep call becomes
`adm_sweep_ep(a[AG_KGREG], a[AG_KG], 0, adm_prot_new(a[AG_EAS], a[AG_ALIASES]))`.

## Consequences

- The alias death-gate is no longer dormant in principle: the moment a genuine
  HDC synonym is resolved, its canonical is recorded and thereafter protected.
- Repeat occurrences of a synonym now hit the O(table) alias path instead of
  re-running the O(atoms x dim) HDC scan.
- Adding a future id-holder protection dimension means extending the `prot`
  record, not threading a new positional arg through every signature and caller.
- `p == 0` keeps every legacy/no-protection caller and test working unchanged.

## Honest gaps

- **The bench autonomous loop still records ZERO aliases.** Verified with a
  throwaway probe: `agent_run(agent_new(12345), 30, 1, 10)` yields
  `alias_table_len == 0` (kg_atoms=3, moments=90, episodic=1). This is EXPECTED
  and correct: the loop observes one fixed sentence ("the agent reached the
  goal in the world") every cycle, whose mentions resolve EXACT (after the
  first cycle mints them) or NEW — never HDC-to-a-differently-labelled atom — so
  there is no genuine synonym to record. The auto-record path is exercised and
  proven by the unit test, not by the bench loop. To see aliases populate in the
  loop, the observation stream would need to contain real surface-form synonyms;
  that is a benchmark/fixture change, out of scope here.

## Implementation Notes

- `src/learning/entity_resolve.nova`: extended `er_resolve_or_create` with the
  HDC-hit alias auto-record block (the only new behavior; the mint path is
  unchanged). No new functions added; reuses existing `er_alias_add`,
  `atom_label`, `str_eq`.
- `src/learning/atom_death_monitor.nova`: ADDED `adm_prot_new`,
  `_adm_prot_eas`, `_adm_prot_aliases` and constants `ADM_PROT_TAG`,
  `ADM_PROT_EAS`, `ADM_PROT_ALIASES`; CHANGED the signatures of
  `adm_is_collectable_ep` and `adm_sweep_ep` to take `prot`; updated the two
  internal `adm_is_collectable_ep` call sites in the sweep and the
  `adm_sweep_attributed` / `adm_sweep` delegators to pass `0`. The
  `_adm_is_episodic_member` / `_adm_is_alias_referenced` helpers are unchanged.
- `src/agent/autonomous_loop.nova`: maintenance-block sweep call updated to
  `adm_prot_new(a[AG_EAS], a[AG_ALIASES])`.
- Tests: `test_atom_death_monitor.nova` updated all `adm_is_collectable_ep` /
  `adm_sweep_ep` calls to the new context form (`adm_prot_new(eas, 0)`,
  `adm_prot_new(0, aliases)`, or `0`); `test_entity_resolve.nova` gained
  `test_synonym_autorecord` (registered in `main()`) asserting the resolve-to-
  existing, alias-recorded, alias-path-on-replay, and no-self-alias properties.
- `make lint-ints` stays clean.
