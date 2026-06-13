# ADR-0076: Phase C — reference-complete death gate; id-reuse handle audit

## Status

Accepted (Phase C, part 1: closes a correctness hazard + records the audit;
actual list-shrink / id-reuse is deferred with a recommended path).

## Date

2026-06-12

## Context

Phase B (ADR-0075) made the death sweep *actually* reclaim atoms. Phase C's goal
is to turn that into bounded memory / scan cost (the holes are not yet
compacted, and ids are not reused). Doing that safely requires knowing **every**
place a long-lived structure stores an atom id, because reusing/renumbering an
id silently corrupts any stale reference. This ADR records that audit and fixes
the one correctness hazard the audit exposed.

## Handle audit (what persistently holds an atom id)

**Persistent, in-KG references:**
- **xrefs** (`cross_kg_references`): `(dst_kg, dst_atom_id)`. Already protected —
  `adm_is_referenced` walks every atom's xrefs.
- **operator premise / conclusion** (`reasoning_atoms`, stored in atom
  *payloads* by `rop_new`): **NOT** protected — `adm_is_referenced` only walks
  xrefs. *This is a live hazard:* after Phase B, the sweep could reclaim a
  premise/conclusion fact out from under a live operator, dangling the edge.
- **episodic cluster members** (`episodic`, atom-id lists in episodic atoms):
  **NOT** protected.

**Transient, per-call (safe — a sweep never runs mid-call):** the id lists built
by `nl_query`, `proof_checker`, `cognitive_router`, `reasoning_module`,
`distributed_rules`, and the PageRank/Louvain/clustering working sets.

**Already-safe machinery:** a compaction subsystem exists
(`snapshot_compaction.nova`), and the snapshot restore path re-resolves operator
premise/conclusion **by label**, not by id (the R51 pass) — so a serialize→
restore round-trip is inherently id-agnostic for operators.

## Decision

**This increment — close the correctness hazard.** Extend `adm_is_collectable`
with `_adm_is_operator_referenced`: an atom named as a live operator's premise or
conclusion (anywhere in its KG) is never collectable, mirroring the xref gate.
This keeps the reasoning graph intact under eviction — a learned causal edge can
no longer lose its premise to the sweep.

**Deferred — the actual list-shrink / RAM reclaim.** Recommended path is a
`kg_compact` built on the **existing snapshot serialize→restore** machinery
rather than hand-rolled incremental id reuse, because:
- The snapshot path already re-resolves the hard references (operators) by label
  and, post-Phase-B, drops freed (0) slots on serialize — so it compacts safely
  by construction, reusing heavily-tested code.
- Incremental id reuse would additionally require protecting **episodic members**
  and a **generation-tag** scheme so any *missed* holder fails safe instead of
  silently corrupting — high risk for a payoff that is bounded anyway: NOVA's
  bump allocator never frees, so reclamation only bounds the `KG_ATOMS` list
  length under churn, not process RSS.

## Consequences

- Reasoning-graph integrity is preserved under eviction. `test_atom_death_monitor`
  27 checks (a weak premise *and* conclusion are collectable alone, become
  protected once an operator references them, and survive two sweeps).
- Full suite 273/273; coverage 241/241; `make lint-ints` clean.

## Honest gaps

- **No list-shrink / RAM reclaim yet** — deferred to the snapshot-compaction
  path above (which still needs episodic + cross-KG-xref id-stability verified
  across a round-trip before being exposed as `kg_compact`).
- `_adm_is_operator_referenced` is O(atoms) per check, so the sweep is O(atoms²)
  — the same class as the existing `adm_is_referenced`. A future pass can serve
  both from the P1.5 edge index / a reverse-xref index.
- **Episodic-member protection is still required before *any* id reuse** and is
  not done here.
- ≥1 M-atom codegen-bug-#11 ceiling (ADR-0066) unchanged.

## Implementation Notes

- `src/learning/atom_death_monitor.nova`: `_adm_is_operator_referenced`; wired
  into `adm_is_collectable`.
- Test: `tests/unit/test_atom_death_monitor.nova`
  (`test_operator_reference_protection`).
- Parents: ADR-0072 (design), ADR-0074 (mechanism), ADR-0075 (sweep wiring),
  ADR-0070 (edge index).
