# ADR-0006: Memory architecture and storage backend

## Status

Accepted

## Context

The memory module is the substrate on which everything else in Crossengin operates: perception writes to it, Cognitive reads and updates it, Academic Knowledge contributes structured chunks to it, Visionary stores imagined-scenario rollouts in it, and Soul reads from it for context-aware behavior. Memory needs to support: vector similarity queries, graph traversal, full-text search over narratives, per-user encryption, and a clean separation between working (short-term) and long-term memory.

A common architectural pattern is to use multiple specialized stores — a vector database (Qdrant, Weaviate, Pinecone) for similarity, a graph database (Neo4j, JanusGraph) for traversal, a relational store for structured metadata, a search engine for full-text. This pattern scales well but multiplies operational complexity, fragments transactions, and requires writing application-level joins across stores.

The alternative is a single substrate that exposes multiple query modalities. PostgreSQL with `pgvector` (vector indexes via HNSW or IVFFlat) and Apache AGE (Cypher-style graph queries) provides exactly this: one database, one transaction boundary, one operational story.

The user has delegated this architectural choice to the assistant, with the directive that the result must support per-user encryption, fit a small team's operational budget, and not lock the project into a vendor.

## Decision

**One substrate per user: PostgreSQL 16+ with `pgvector` and Apache AGE.** Both extensions are permissively licensed (`pgvector` under PostgreSQL license, Apache AGE under Apache 2.0). PostgreSQL deploys anywhere — RunPod containers, self-hosted, managed cloud — without vendor lock-in. One database to learn, monitor, and back up.

**Composite `MemoryItem` record.** Every memory item is a single row exposing multiple facets:

```
MemoryItem
├── core_id         UUID, primary key
├── user_id         UUID, foreign key, row-level encryption key derives from this
├── timestamp       TIMESTAMPTZ
├── type            ENUM (perception, interaction, inference, academic, dream, ...)
├── raw_refs        JSONB, references to raw source artifacts (file paths, URLs)
├── triples         JSONB, list of (subject, predicate, object) symbolic triples
├── frames          JSONB, list of {schema_name, slot_assignments} for slot-and-filler representations
├── narrative       TEXT, human-readable summary; indexed by PostgreSQL full-text search
├── vector          VECTOR(d), embedding from the shared perception space (ADR-0004); indexed by pgvector HNSW
├── links           JSONB, list of {target_core_id, relation_type, weight}; mirrored into Apache AGE for graph queries
├── meta            JSONB, provenance, source license, confidence, imagined flag, working flag, ...
```

Each row is self-contained. Queries pick the facet they need: vector queries scan the HNSW index on `vector`; graph queries run Cypher through Apache AGE over `links`; symbolic queries filter on `type` and `triples`; full-text queries hit `narrative`.

**Working memory** is the subset of `MemoryItem` rows where `meta->>'working' = 'true'`. Optionally fronted by an in-memory cache (Redis or an in-process LRU) for hot reads. Working-set tagging is updated by the cognitive module's attention policy; long-term memory is the unfiltered table.

**Per-user encryption.** Row-level encryption with per-user keys. Sensitive columns (`raw_refs`, `triples`, `frames`, `narrative`, `meta`) are encrypted at write with a key derived from the user's identity. The `vector` column is also encrypted at rest where feasible; trade-offs against `pgvector` index performance are evaluated at the M3 milestone (ADR-0022).

**Migration escape hatch.** If `pgvector` HNSW performance becomes a bottleneck at user scale beyond v0, vectors can be externalized to Qdrant (Apache 2.0) without rewriting the application's symbolic and graph code, by storing only `core_id` in Qdrant and joining back to the PostgreSQL row. The composite-row design accommodates this without schema disruption.

## Consequences

Positive: one database, one backup story, one transaction boundary. Per-user encryption is straightforward at the row level. Cross-facet queries (vector similarity *and* graph traversal *and* metadata filter) execute in a single SQL statement. All chosen extensions are permissively licensed. Operationally cheap for a small team — RunPod can run PostgreSQL in a container alongside the model, or it can run as a managed service later.

Negative: `pgvector` is less performant at very large scale than purpose-built vector databases. Apache AGE is younger than Neo4j and has a smaller community; query semantics for some advanced Cypher features may need workarounds. Per-user row-level encryption adds CPU cost on every read and complicates query planning when encrypted columns participate in WHERE clauses.

Neutral: the migration path to Qdrant or similar is real but not free; we expect it not to be needed at v0 scale and we re-evaluate at v1.

## Alternatives considered

**Specialized polyglot storage** (Qdrant for vectors + Neo4j for graph + PostgreSQL for relational + Elasticsearch for full-text). More performant at very large scale but multiplies operational surface. Rejected for v0; revisit if scale demands it.

**SQLite + sqlite-vss.** Simpler still, but SQLite's concurrency model (single writer) is wrong for a multi-user companion service even at v0 scale.

**A graph-native store with vector add-ons** (Neo4j with vector indexes, JanusGraph). Graph-first rather than relational-first. Rejected on licensing grounds (Neo4j Community is GPLv3, fails the strict-permissive posture in ADR-0019) and on the polyglot-cost grounds above for the others.

**No structured memory; pure vector retrieval over chat history (LLM-style).** Rejected as the architectural antithesis of Crossengin's thesis (ADR-0005).

## Open questions

- Exact vector dimensionality `d` is set at the M2 milestone (ADR-0022) once the SigLIP variant is chosen in ADR-0004.
- Whether the in-memory cache in front of working memory is needed at v0 scale, or only at v1+. Defer until profiling at M3.
- Concrete encryption scheme for per-user row-level encryption: pgcrypto column-level encryption with key derivation, application-layer encryption with envelope keys, or transparent data encryption at the storage layer. To be resolved at M3 alongside the privacy ADR (ADR-0021).

## References

- ADR-0004 (Perception layer) for the source of the `vector` column.
- ADR-0005 (Knowledge representation paradigm) for the graph-of-vectors form this schema implements.
- ADR-0007 (Knowledge update policy) for how `MemoryItem` rows evolve over time.
- ADR-0019 (Licensing posture) for the license filter on extensions and migration targets.
- ADR-0021 (Privacy and data handling) for the per-user encryption requirements this schema implements.
- ADR-0022 (Evaluation and milestones) for the M3 memory-substrate milestone definition-of-done.
