# ADR-0004: Multi-KG organization by domain with cross-references

## Status

Proposed

## Date

2026-05-25

## Context
CrossEngin must accumulate durable knowledge across many domains — medicine, law, the user's life, language itself — and reason *across* them (a drug interaction informed by the user's diet; a legal concept anchored to a medical fact). ADR-0002 fixes **atoms** as the persistent knowledge unit and **KG** as their store. The decision here is the *organization* of that knowledge: one monolithic graph for everything, or many domain-scoped graphs linked by cross-references. Because atoms are produced continuously by nodes (ADR-0006) and the system learns new domains over its lifetime (ADR-0026 self-learning), this structure must support *growth of new domains at runtime*, not just a fixed schema.

NOVA provides `core/knowledge.nova` (KG with embeddings) and `core/similarity.nova` (vector similarity). The constraints: a desktop v1 (ADR-0046) where most domains are *cold* most of the time and should not consume hot memory; a 2-founder team that cannot hand-curate domain boundaries; and v2 enterprise (ADR-0047) where a tenant's private domain knowledge must be isolatable from the shared base brain. These forces all push toward *separable, independently-loadable* knowledge stores.

A single global KG is simplest to query (no cross-store joins) but couples everything: it cannot page cold domains out, cannot isolate a tenant's data, grows one giant index whose embedding search degrades as it fills with unrelated atoms, and offers no natural unit for the spawn-on-new-domain behavior the system needs.

## Decision
Knowledge is organized as **multiple domain-scoped KGs, one per domain**, linked by **similarity-weighted cross-KG references**. Each KG (e.g. `kg-medicine`, `kg-law`, `kg-user`, `kg-language` per ADR-0015) is an independently namespaced `core/knowledge.nova` store with its own atom set, embedding index, and Bayesian beliefs (ADR-0016, `core/belief.nova`). Atoms are addressed as `(kg_id, atom_id)`; an atom in one KG references related atoms in others via cross-reference edges weighted by `core/similarity.nova` cosine similarity (#8).

**Spawn-on-new-domain.** The system starts with a small seed set of KGs and *spawns a new KG automatically* when it detects a coherent cluster of atoms that is poorly served by existing domains — operationally, when a run of incoming atoms shows high mutual similarity but low maximum similarity (below a tier threshold) to every existing KG centroid. The new KG is created via `kg_spawn`, seeded with the cluster, and given a centroid for future routing. The detailed heuristic and link-formation policy live in ADR-0017.

**Cross-references: automatic vs earned.** Cheap automatic links form when two atoms exceed a similarity threshold at write time. Stronger *earned* links form when atoms in different KGs *co-activate repeatedly* during reasoning (Hebbian over the synapse layer, ADR-0007) — i.e. cross-domain association is itself learned, consistent with the substrate thesis (ADR-0001). Cross-KG references are what let spreading activation (the reader, ADR-0012) cross domain boundaries.

## Options Considered
**1. Multiple domain KGs + cross-references (CHOSEN).** *Pros:* cold domains page to disk (`runtime/db.nova`), keeping the desktop hot set small (ADR-0046); per-domain embedding indices stay small and fast; clean tenant isolation for v2 (ADR-0047) — a tenant KG layers over the shared base; gives a natural unit for spawn-on-new-domain; cross-domain reasoning is explicit and learnable. *Cons:* cross-KG queries require following reference edges rather than a single index scan; routing an atom to the right KG can be wrong and needs the ADR-0017 heuristic; cross-references add storage and maintenance. Chosen because separability and isolation are decisive for both deployments.

**2. Single monolithic KG (rejected).** All atoms in one `core/knowledge.nova` store. *Pros:* simplest possible model; no routing decision; no cross-store joins; one index to maintain. *Cons:* cannot page cold domains out (fatal on a desktop budget, ADR-0003); a single growing embedding index degrades in precision and latency as unrelated atoms accumulate; no tenant isolation for v2; no natural spawn unit. Rejected — it fails the desktop budget and the enterprise isolation requirement simultaneously.

**3. Fixed hand-defined domain partitions, no runtime spawning (rejected).** Founders pre-declare a fixed set of KGs; nothing new spawns. *Pros:* predictable; no risky auto-spawn heuristic; clean ownership. *Cons:* a personal companion encounters open-ended domains we cannot enumerate in advance; forcing novel knowledge into ill-fitting buckets corrupts per-domain centroids and cross-reference quality; contradicts continuous self-directed learning (ADR-0026). Rejected — incompatible with the open-world companion goal.

## Consequences
- **Positive:** Memory-efficient on a desktop (cold KGs evicted); fast per-domain retrieval; clean v2 tenant isolation (ADR-0047); explicit, learnable cross-domain reasoning; auto-spawn lets the knowledge map grow with the user.
- **Negative:** Cross-KG traversal is costlier than a single-index scan; the spawn heuristic and routing can misclassify (mitigated by ADR-0017 and mutable atoms, ADR-0016); cross-reference edges add storage and a pruning obligation; an atom's "home KG" can become wrong as domains drift.
- **Future work:** ADR-0017 specifies the spawn heuristic, similarity weighting, and automatic-vs-earned link formation; ADR-0018 integrates the concept layer across KGs; ADR-0029 layers source-authority tiers onto atom confidence; v2 isolation realized in ADR-0047.

## Implementation Notes
Extend `core/knowledge.nova` with a namespace/registry layer (`kg_registry`, `kg_spawn`, `kg_get`, `kg_evict`) and cross-reference edges `xref_new(src_kg, src_atom, dst_kg, dst_atom, weight)` weighted by `core/similarity.nova`. Atoms carry global `(kg_id, atom_id)` handles (ADR-0016) and Bayesian alpha/beta via `core/belief.nova`. Cold KGs persist/rehydrate through `runtime/db.nova` per ADR-0048 ordering. Earned links update through the synapse plasticity path (ADR-0007).

DEPENDS ON: NOVA enhancement #8 — multi-KG namespacing + cross-KG reference edges with similarity weights.

Testing: a spawn fixture feeding a synthetic novel-domain atom stream and asserting a new KG is created with a sensible centroid; a cross-reference fixture asserting a `kg-medicine` atom links to a related `kg-user` atom above threshold; an eviction/rehydration round-trip verifying cold-KG persistence.
