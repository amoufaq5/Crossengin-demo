# ADR-0080: Death-gate episodic-member protection (future-proofing id reuse)

## Status

Accepted

## Date

2026-06-13

## Context

ADR-0076 made the collectability gate reference-complete for **xrefs** and
**operator premise/conclusion**. ADR-0079 flagged the last persistent id-holder
the gate did not cover: **episodic cluster members** (`EA_MEMBERS`).

Investigation finding (important, and the honest framing of this change):
reclaiming an episodic member is **benign under today's semantics**. Episodic
clusters consume member ids **only as id-set operations** — signature matching
and `_episodic_overlap` — and **never dereference them into atom objects**. A
reclaimed atom whose id lingers in a cluster is therefore just a stale integer.
The only way it can cause a *wrong* result is if that id is **reused by a
different atom**, and id reuse is **not implemented** (the free-list is
observability-only; `kg_add_atom` always increments `KG_NEXTID`).

So this gate is **future-proofing**: it is dormant-but-correct today and becomes
load-bearing the moment id reuse lands. (The decision to build it now rather
than defer was made explicitly.)

## Decision

Add an opt-in episodic protection layer to the death sweep, without changing any
existing signature:

- `_adm_is_episodic_member(eas, atom)` — 1 if `atom_id(atom)` appears in any
  cluster's member list. Episodic members are **bare ids** (no KG qualifier), so
  this matches by id across the whole store: a deliberately **conservative /
  over-protective** check (it may spare an atom in another KG that shares an id).
  Over-protection errs toward *keeping* atoms, which is safe for a gate.
- `adm_is_collectable_ep(reg, atom, eas)` = `adm_is_collectable` plus the
  episodic check; `eas == 0` makes it identical to the base gate.
- `adm_sweep_ep(reg, kg, mo, eas)` — the sweep core, now eas-aware.
  `adm_sweep_attributed(reg, kg, mo)` and `adm_sweep(reg, kg)` delegate with
  `eas = 0`, so all existing callers and tests are unchanged.

## Consequences

- The capability is in place and tested: `test_atom_death_monitor` (33 checks)
  shows a weak atom that is an episodic member is collectable alone, becomes
  protected once a cluster references it, survives an episodic-aware sweep, and
  that a non-member weak atom is still collected by the same sweep. Back-compat
  suites (`atom_death_attribution`, `meta_observer`) unchanged. Full suite green;
  lint clean.
- **Activation is opt-in.** Protection is active only when a caller passes its
  episodic store to `adm_sweep_ep`. The episodic store (`eas`) lives in the agent
  memory loop, not in the death monitor or meta_observer, so the real sweep call
  site (meta_observer today passes no `eas`) must be updated to thread `eas` to
  turn protection on. That one-line wiring is left to the loop owner; until then
  the gate is dormant (which is correct, since the risk is dormant too).

## Honest gaps

- **Over-protection**: bare-id matching can spare an unrelated same-id atom in a
  different KG. Acceptable (safe direction); a precise gate would need episodic
  members to be KG-qualified `(kg, id)` — a larger change.
- **Cost**: O(clusters × members) per collectability check when `eas` is passed,
  on top of the already-O(atoms) `adm_is_referenced`. Fine for occasional sweeps;
  could be indexed (a member-id set) if sweeps get hot.
- **Dormant until wired** (see Consequences) — and **benign until id reuse**
  exists (see Context). Both are deliberate.
- ≥1 M-atom codegen-bug-#11 ceiling (ADR-0066) unchanged.

## Implementation Notes

- `src/learning/atom_death_monitor.nova`: `import episodic`;
  `_adm_is_episodic_member`, `adm_is_collectable_ep`, `adm_sweep_ep`;
  `adm_sweep_attributed`/`adm_sweep` now delegate to `adm_sweep_ep`.
- Test: `tests/unit/test_atom_death_monitor.nova`
  (`test_episodic_member_protection`).
- Parents: ADR-0076 (operator gate), ADR-0079 (compaction + the flagged gap).
