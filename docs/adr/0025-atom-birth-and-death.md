# ADR-0025: Atom birth and death (co-activation pattern -> new atom; decay-based GC)

## Status

Proposed

## Date

2026-05-25

## Context
Atoms are CrossEngin's durable knowledge units (ADR-0016), and ADR-0006 establishes that nodes produce atoms **only for novel patterns** and may read atoms they did not create. Two lifecycle questions follow and must be answered concretely: *birth* — under exactly what conditions does a recurring co-activation of nodes crystallize into a new persistent atom (rather than minting noise atoms for every fleeting pattern)? — and *death* — how are atoms that stop earning their keep garbage-collected so the KGs (ADR-0004/ADR-0017) don't accumulate dead weight over months of continuous learning on a desktop? Without disciplined birth, the KGs bloat with spurious atoms and the 1M-node parts (ADR-0003) thrash; without principled death, stale knowledge lingers and storage grows unbounded.

This decision sits at the seam between the substrate (nodes/synapses, ADR-0006/ADR-0007) and knowledge (atoms/KGs, ADR-0016/ADR-0017), and it is the concrete mechanism behind consolidation (ADR-0022) and is fed by predictive-coding novelty (ADR-0024). Constraint: 2 founders, 100Hz substrate — birth detection must be a cheap, incremental co-activation counter, and death must be a periodic background sweep (idle-gated, enhancement #13), not a stop-the-world GC. We need concrete thresholds the team can implement and tune.

## Decision
We define atom **birth** by a **co-activation-frequency + novelty + stability** gate, and atom **death** by **decay-based reference-counted garbage collection**.

**Birth.** Each node tracks short-lived candidate co-activation patterns: when a set of nodes fires together within a 50ms (5-tick) window, an incremental counter for that pattern signature is bumped (signatures hashed from the participating node ids, kept in a small per-part LRU candidate table, capacity ~10k). A new atom is born only when ALL hold: (1) **frequency** — the pattern recurs `>= 5` times; (2) **novelty** — no existing atom already matches it within cosine similarity `0.9` (checked via `core/similarity.nova` over the pattern's embedding), satisfying ADR-0006's "novel patterns only"; (3) **stability** — the pattern persists across `>= 3` distinct moments/episodes (ADR-0021/ADR-0022), not a single burst. On firing, `atom_new(pattern_embedding, kg_id)` is created in the appropriate domain KG (ADR-0017, spawning a new KG if the domain is new), with an initial Beta belief (ADR-0023) seeded `alpha=1+evidence_weight, beta=1`. Predictive-coding surprise (ADR-0024) lowers the frequency threshold to `3` for high-error patterns — the system preferentially crystallizes things that violated expectations.

**Death.** Each atom carries `last_access_tick` and an `activation_strength` that decays exponentially (`tau_atom = 30 days`) and is reinforced `+0.2` on each read/co-activation. A periodic idle GC sweep (default every 6h of idle, enhancement #13) collects an atom when ALL hold: (1) `activation_strength < 0.02`; (2) not referenced by any cross-KG edge (ADR-0017) and not cited by a CONSOLIDATED episode's surviving knowledge; (3) `belief_strength < 4` (we never GC a well-evidenced atom, however cold — foundational facts persist). Collected atoms are first **tombstoned** for one sweep cycle (soft-deleted, recoverable) before hard removal, so an atom reactivated just after marking is rescued. Protected classes — constitutional/value atoms (ADR-0045), self-model atoms (ADR-0020), and atoms tagged classical/stable (ADR-0029) — are exempt from death entirely.

## Options Considered
**1. Frequency+novelty+stability birth gate with decay-based reference-counted GC (CHOSEN).** Implements ADR-0006's "atoms only on novel patterns" precisely, prevents both noise-atom bloat and unbounded growth, and ties cleanly to similarity (ADR-0017), beliefs (ADR-0023), predictive surprise (ADR-0024), and idle scheduling (#13). Tombstoning makes death safe. Cost: candidate tables, several thresholds, and a background sweep. Chosen as the only option meeting both the novelty mandate and the bounded-storage constraint.

**2. Birth an atom on every distinct co-activation (no gate).** Maximally sensitive. Rejected: explodes the KGs with transient, noise, and near-duplicate atoms, violating ADR-0006 and thrashing the 1M-node parts and `core/similarity.nova` lookups (ADR-0003); confidence and routing degrade because real atoms are buried in spurious ones.

**3. Never delete atoms (birth only, immortal atoms).** Simple, no GC. Rejected: unbounded KG growth over months of continuous desktop learning, stale/obsolete knowledge competing with current knowledge (worsening conflicts, ADR-0023/ADR-0029), and ever-slowing spreading activation in the reader (ADR-0012). Belief *decay* (ADR-0023) softens stale confidence but does not reclaim storage; we need actual death.

**4. Fixed-size atom pool with LRU eviction.** Cap atoms per KG, evict least-recently-used. Rejected: a hard cap is arbitrary across heterogeneous domains, and pure LRU would evict cold-but-foundational atoms (a rarely-recalled but high-evidence fact) — exactly what the `belief_strength`/protected-class guards prevent. Decay+reference-count GC retains by *importance*, not just recency, mirroring the episodic decision in ADR-0022.

## Consequences
- **Positive:** Disciplined, novelty-gated atom creation that honors ADR-0006 and prevents KG bloat; bounded long-term storage via safe (tombstoned) decay-based GC; preferential crystallization of surprising patterns (via ADR-0024 coupling) so the system learns what defied expectation; protected classes guarantee constitution, self-model, and classical facts are never collected.
- **Negative:** Many tuned constants (freq 5/3, cosine 0.9, stability 3 moments, `tau_atom=30d`, GC strength 0.02, belief 4, 6h sweep) requiring empirical calibration; candidate co-activation tables add per-part memory; a GC bug risks deleting live knowledge, mitigated by tombstoning and protected classes but still a correctness-sensitive subsystem.
- **Future work:** Learned (per-domain) birth/death thresholds; merging near-duplicate atoms discovered post-birth (similarity-driven consolidation with ADR-0018); coordinating GC with snapshotting (ADR-0048) so tombstones are handled correctly across restarts; v2 per-tenant atom-lifecycle isolation (ADR-0047).

## Implementation Notes
- Birth detection: per-part candidate table (LRU ~10k) keyed by hashed node-id signatures, bumped on 5-tick co-activation windows; on gate-pass call `atom_new` in `core/knowledge.nova` (KG chosen/spawned per ADR-0017), seed belief via `core/belief.nova` (ADR-0023). Novelty check uses `core/similarity.nova` cosine `>= 0.9`. Surprise coupling reads ADR-0024 error magnitude to lower the frequency gate.
- Death: atoms gain `last_access_tick` + `activation_strength` (accessors/mutators `atom_touch`, `atom_decay`) in `core/knowledge.nova`; idle GC sweep scheduled via enhancement #13, tombstone flag before hard delete; reference check walks cross-KG edges (ADR-0017); protected-class tags from ADR-0045/ADR-0020/ADR-0029.
- Consolidation (ADR-0022) is the main birth caller during idle; live novel-pattern birth happens on the perception/reasoning path (ADR-0006).
- Testing: `fixture_atom_birth` (pattern recurring 5x across 3 moments -> exactly one atom; a near-duplicate at cosine 0.92 -> NO new atom), `fixture_surprise_birth` (high ADR-0024 error -> birth at frequency 3), `fixture_atom_death` (cold atom strength<0.02, no refs, belief<4 -> tombstoned then collected; reactivation during tombstone -> rescued), `fixture_protected` (constitutional/self-model/classical atoms never collected even when cold).
- Dependencies: ADR-0006 (atoms only on novel patterns), ADR-0016 (atom design), ADR-0017 (KG spawn + cross-KG refs + similarity), ADR-0023 (seed/guard belief), ADR-0024 (surprise lowers birth threshold), ADR-0022 (consolidation drives birth, GC during idle), ADR-0020/ADR-0029/ADR-0045 (protected classes), ADR-0048 (GC/tombstone vs snapshot).
- DEPENDS ON: NOVA enhancement #13 — idle-detection + background scheduling hooks (the GC sweep).
- DEPENDS ON: NOVA enhancement #2 — sparse synapse adjacency with O(1) growth/pruning (co-activation patterns ride on synapse structure; atom death parallels synapse pruning).
- DEPENDS ON: NOVA enhancement #8 — multi-KG namespacing + cross-KG reference edges (birth targets a KG; death respects cross-KG reference counts).
