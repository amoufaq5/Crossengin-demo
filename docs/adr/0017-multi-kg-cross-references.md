# ADR-0017: Multi-KG with cross-references (spawn-on-new-domain, similarity-weighted cross-refs, automatic and earned link formation)

## Status

Proposed

## Date

2026-05-25

## Context
ADR-0004 made the organizational decision that CrossEngin stores knowledge in many domain-specific KGs (KG-medicine, KG-biology, …) rather than one monolith, with cross-references linking related concepts across domains. This ADR specifies the *mechanism*: when a new KG is spawned, how cross-KG reference edges are created and weighted, and the difference between automatically formed links and links that must be earned. ADR-0016 already gave every atom a `kg_id` and an `xrefs` list; here we define what populates and weights those xrefs and what triggers a new `kg_id` to exist at all.

This must be decided now because the reader's spreading-activation stage (ADR-0012) traverses cross-KG references, the concept layer (ADR-0018) builds cross-domain concepts on top of them, and self-directed learning (ADR-0026) frequently encounters material in a domain the system has never separated before. Without a spawn heuristic the system either dumps everything into one KG (defeating domain-local activation and v2 tenant isolation, ADR-0047) or fragments into thousands of tiny KGs.

Constraints: 2 founders, 8h/day, bootstrap. We cannot hand-curate a domain taxonomy. Spawning and linking must be automatic, driven by substrate signals and vector similarity, and cheap enough to run online. We build directly on `core/knowledge.nova` for the stores and `core/similarity.nova` for the cosine weighting of cross-references.

## Decision
**Spawn-on-new-domain heuristic.** A new KG is spawned when a cluster of recently created atoms is persistently *dissimilar* from every existing KG centroid yet *self-coherent*. Concretely: each KG maintains a running centroid embedding. When a window of N=200 newly produced atoms (over a moment window) has mean max-similarity to all existing KG centroids below `SPAWN_DISSIM = 0.35` (via `core/similarity.nova`), AND the cluster's internal mean pairwise similarity exceeds `SPAWN_COHERE = 0.55`, the meta part calls `kg_spawn(label)`, allocates the new KG namespace, and migrates the cluster's atoms into it (their `id` stays, `kg_id` changes, xrefs are preserved). This prevents both premature splitting (incoherent noise) and a runaway monolith.

**Similarity-weighted cross-references.** A cross-KG reference is an edge `[XREF, src_atom, dst_kg, dst_atom, weight, kind, earned]`. `weight` is the cosine similarity of the two atoms' embeddings (`similarity_cosine` over `embed_ref`, ADR-0018), recomputed lazily and decayed if not reinforced. `kind` is `XREF_SIMILAR`, `XREF_CAUSAL`, `XREF_ANALOGICAL`, or `XREF_PARTOF`. The reader's spreading activation (ADR-0012) propagates activation across an xref scaled by `weight`, so strong cross-domain links carry more signal.

**Automatic vs earned links.** *Automatic* links (`earned=false`) form when two atoms exceed `XREF_AUTO = 0.82` similarity at creation/update time — cheap, embedding-only, and revocable if similarity later decays. *Earned* links (`earned=true`) form only after repeated co-activation in successful reasoning or confirmed predictions: an `XREF_CAUSAL` or `XREF_ANALOGICAL` edge is promoted to earned once it has been co-activated and not contradicted across `EARN_K = 5` distinct moments, at which point its `weight` is floored at 0.5 and it resists similarity decay. Earned links are how the system encodes hard-won cross-domain insight that raw embedding proximity would never capture (e.g., a medicine→economics analogy).

## Options Considered
**Single monolithic KG with a domain tag (no spawning).** Simplest. Rejected (consistent with ADR-0004): domain-local spreading activation degrades when every atom is in one graph, cross-tenant isolation for v2 (ADR-0047) becomes a query-time filter rather than a structural boundary, and the centroid signal that drives curiosity-based learning (ADR-0026) disappears.

**Manual/predeclared domain taxonomy.** An engineer defines the KGs up front. Rejected: 2 founders cannot anticipate the domains a continuously learning companion will enter, and a fixed taxonomy contradicts the self-directed-learning thesis. The spawn heuristic lets domains emerge from the data.

**Pure embedding-similarity links only (no earned tier).** All cross-refs are cosine-weighted and nothing is "earned." Rejected: embedding proximity captures surface similarity but misses causal/analogical structure discovered through reasoning; without an earned tier those edges would decay away between uses. We keep automatic links for breadth and earned links for durable insight.

**Spawn purely on atom count per topic.** Split a KG when it exceeds a size threshold. Rejected: size is not domain-ness; it would split coherent large domains and merge unrelated small ones. Similarity-coherence is the right signal.

## Consequences
- **Positive:** Domains emerge automatically and stay coherent; cross-domain reasoning is supported by weighted edges that the reader can traverse; the automatic/earned distinction lets cheap links scale while durable insight is protected from decay. Structural KG boundaries give v2 tenant isolation (ADR-0047) for free.
- **Negative:** Spawn/merge thresholds (`SPAWN_DISSIM`, `SPAWN_COHERE`, `XREF_AUTO`, `EARN_K`) are tuning parameters that need empirical calibration during the multi-day test (ADR-0049). Migrating a cluster into a new KG is a non-trivial transactional operation that must be crash-safe (ADR-0048). Lazy xref-weight recomputation adds bookkeeping.
- **Future work:** A KG-merge operation (inverse of spawn) for domains that converge. ADR-0018 consumes xrefs to build cross-domain concept nodes. ADR-0029 source-authority tiers feed xref provenance. ADR-0025's decay GC must also prune dead xrefs.

## Implementation Notes
Extend `core/knowledge.nova` with a `kg_registry` (map of `kg_id -> {centroid, atom_index}`) and constructors `kg_spawn(label)`, `kg_centroid(kg_id)`, plus xref ops `xref_new(src, dst_kg, dst_atom, kind)`, `xref_weight(x)` (delegates to `core/similarity.nova` `similarity_cosine`), `xref_promote_earned(x)`. Tag constants `TAG_XREF`, `XREF_SIMILAR|CAUSAL|ANALOGICAL|PARTOF`. The spawn evaluator runs in the meta part on a slow cadence (not every 100Hz tick — ADR-0037 event-driven layer). Test fixtures: feeding a coherent off-domain atom cluster triggers exactly one `kg_spawn`; an automatic xref above 0.82 forms and later drops below threshold and is pruned; a co-activated causal xref reaches earned status after 5 moments and survives a similarity-decay pass. DEPENDS ON: NOVA enhancement #8 — multi-KG namespacing + cross-KG reference edges with similarity weights. This is the mechanism realizing ADR-0004's organizational decision; cross-reference ADR-0016 (atom `xrefs`/`kg_id`), ADR-0012 (spreading activation), ADR-0018 (concepts over xrefs). No LLM participates in spawning or linking (ADR-0014).
