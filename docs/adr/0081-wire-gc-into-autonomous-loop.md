# ADR-0081: Wire the memory-lifecycle GC into the live autonomous loop

## Status

Accepted

## Date

2026-06-13

## Context

ADRs 0072–0080 built the memory-lifecycle machinery: reclamation
(`kg_reclaim_atom`), the two-phase death sweep (`adm_sweep`), a
reference-complete collectability gate (xrefs + operators + episodic), in-place
compaction (`kg_compact`), and episodic-member protection (`adm_sweep_ep`). All
of it was unit-tested but **invoked nowhere in production** — `adm_sweep*` had no
runtime call site, no production code instantiated an episodic store, and the
agent struct had no `eas` slot. The eviction mechanism had never actually run.

This ADR turns it on in the autonomous loop (`autonomous_loop.nova`), the
agent's tick.

## Decision

- The agent owns an episodic store: new slot `AG_EAS`, instantiated with
  `episodic_atoms_new()` in `agent_new`. Accessor `agent_eas(a)`.
- In `agent_cycle`, every `AG_GC_EVERY` (= 8) cycles run a maintenance block:
  `episodic_consolidate(AG_EAS, AG_STREAM, ...)` then
  `adm_sweep_ep(AG_KGREG, AG_KG, 0, AG_EAS)`. Passing `AG_EAS` activates the
  ADR-0080 episodic protection; the two-phase death means a weak atom is only
  reclaimed after staying collectable across two maintenance passes.
- **Observation now reinforces.** `_ag_ingest` calls `adm_reinforce` on each
  resolved/created atom. This was forced by a real bug the live sweep surfaced
  (see below) and is the correct memory semantic regardless: an entity the agent
  keeps observing stays hot.

## The bug live GC surfaced (and the fix)

Enabling the sweep over the experience KG immediately broke
`test_autonomous_loop` ("repeated observations did NOT fragment the KG"). Root
cause: the **entity-resolution alias table (`AG_ALIASES`) is an id-holder the
death gate does not know about.** Re-observed entities were never reinforced, so
their atoms decayed, the sweep reclaimed them, and the next ingest — finding the
alias still pointing at a now-reclaimed id — re-minted them as fresh atoms. The
KG fragmented (atom count climbed) instead of dedup'ing.

Fixed at the semantic root: reinforcing on observation keeps actively-used atoms
above the death threshold, so they are never collectable, so the alias never
dangles. After the fix the experience KG holds a stable **2 atoms** across a
30-cycle run with GC sweeping at cycles 0/8/16/24.

## Consequences

- The full ADR-0072–0080 machinery now executes at runtime for the first time.
  `test_autonomous_loop` (13 checks) and `test_autonomous_research` (58) pass;
  full suite green; lint clean.
- Behavior change: weak, unreinforced, unreferenced atoms are now evicted live.
  The reinforce-on-observation rule keeps everything the agent actually uses.

## Honest gaps

- **Episodic protection is wired but dormant in this loop.** Consolidation over
  the bench's tool-moment stream does not hit the recurrence threshold, so the
  episodic store stays empty (0 clusters) — there is nothing to protect here.
  The wiring and the protection *logic* are correct (the latter unit-tested in
  ADR-0080); minting clusters requires recurring moment sets the bench doesn't
  produce. Feeding ingested-observation ids into the consolidation stream would
  make it mint, but that changes loop semantics and is deferred.
- **The alias table is still not in the death gate.** The reinforce fix removes
  the *practical* fragmentation, but `adm_is_referenced` still does not treat an
  alias-referenced atom as referenced. If an aliased entity ever goes genuinely
  cold (un-observed long enough to fall below threshold) it can still be
  reclaimed while the alias lingers. A complete fix threads `AG_ALIASES` into
  the gate (analogous to the operator/episodic checks) — deferred as a known gap.
- Only `AG_KG` is swept (not `AG_SKILLS` or other KGs); cadence is a fixed 8.
- ≥1 M-atom codegen-bug-#11 ceiling unchanged.

## Implementation Notes

- `src/agent/autonomous_loop.nova`: imports (`atom_death_monitor`, `episodic`);
  `AG_EAS`/`AG_GC_EVERY`; store in `agent_new`; `agent_eas`; reinforce in
  `_ag_ingest`; maintenance block in `agent_cycle`.
- Test: `tests/unit/test_autonomous_loop.nova` (store-wired + non-fragmentation).
- Parents: ADR-0075 (sweep), ADR-0080 (episodic protection).
