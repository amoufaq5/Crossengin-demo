# ADR-0018: Concept layer evolution (hierarchy, schemas, multi-vector embeddings, integration with multi-KG)

## Status

Proposed

## Date

2026-05-25

## Context
NOVA ships a concept layer (`core/concept.nova`) with multi-vector embeddings. CrossEngin needs more than the base: a concept must sit at the top of an abstraction hierarchy over the per-domain atoms of ADR-0016, carry a *schema* (typed slots) so it can structure knowledge rather than just cluster it, hold *multiple* embedding vectors capturing different facets of meaning, and span the multiple KGs introduced in ADR-0017. Concepts are what the reader activates during comprehension (ADR-0012), what output generation flows down from (ADR-0013), what theory-of-mind models the user with (ADR-0039), and what reasoning operates over (ADR-0031). The base layer is a clustering primitive; we must evolve it into a structured, cross-domain abstraction layer.

This decision is needed now because ADR-0017's cross-KG references are the raw material from which cross-domain concepts are assembled, and the self-model (ADR-0020) and theory-of-mind (ADR-0039) both depend on concepts having rich, schema-typed properties. Deferring it would force ad-hoc concept handling into each consumer.

Constraints: 2 founders, 8h/day, bootstrap. We extend `core/concept.nova` rather than rewrite it, reuse `core/similarity.nova` for facet matching, and keep concept vectors out of the atom (ADR-0016 stores only an `embed_ref`) so atoms stay small.

## Decision
**Hierarchy.** A concept is `[TAG_CONCEPT, id, parents, children, schema, vectors, members, kg_span, salience]`. `parents`/`children` form a DAG (multiple inheritance allowed: "antibiotic" is-a "drug" and is-a "chemical-compound"). Member atoms attach at the most specific concept; activation and property inheritance flow up `parents`. Promotion is automatic: when a set of atoms across one or more KGs shares schema slots and clusters tightly (mean pairwise `similarity_cosine` > `CONCEPT_PROMOTE = 0.7`), `concept_promote(members)` creates or attaches a concept node above them.

**Schemas.** Each concept carries a `schema`: a map of typed slots (e.g. drug → {mechanism, dose_range, contraindications, evidence_tier}). Slots are filled by member atoms and inherited by children; an unfilled slot on a frequently activated concept is a concrete *imagination gap* that triggers self-directed learning (ADR-0026). Schemas are themselves learned and mutable — a slot is added when ≥`SCHEMA_K = 3` members independently exhibit a shared property dimension.

**Multi-vector embeddings.** Each concept holds `vectors` = a small map of named facets: `VEC_LEXICAL` (surface/word form, ties to language atoms ADR-0015), `VEC_SEMANTIC` (meaning), `VEC_RELATIONAL` (its role in the xref graph), and optionally `VEC_AFFECTIVE` (valence/arousal association from ADR-0035). The reader and similarity queries select the facet relevant to the task, so lexical lookup and semantic reasoning use different vectors of the same concept. This is the evolution of `core/concept.nova`'s existing multi-vector support into named, task-selected facets.

**Multi-KG integration.** `kg_span` lists the KGs whose atoms are members. A concept is *cross-domain* iff `len(kg_span) > 1`; such concepts are assembled from earned cross-KG references (ADR-0017) and are exactly where analogical reasoning (ADR-0031) lives. Concepts do not belong to a KG — they sit above the KG layer and index into it, preserving ADR-0017's structural boundaries while still allowing cross-domain abstraction.

## Options Considered
**Flat concepts (clusters only, no hierarchy or schema).** The base `core/concept.nova` behavior. Rejected: without a hierarchy, property inheritance and abstraction are impossible, and without schemas the system cannot represent "what it doesn't know yet" about a concept — which ADR-0026 needs to drive curiosity. Insufficient for theory of mind (ADR-0039).

**Single embedding per concept.** Simpler and smaller. Rejected: lexical similarity and semantic similarity genuinely diverge (homonyms, synonyms), and the reader needs to match on different facets at different stages (ADR-0012). Multi-vector is already in the base layer; we leverage and name the facets rather than collapse them.

**Concepts owned by a single KG.** Put each concept inside one KG. Rejected: it would forbid cross-domain concepts, the very thing ADR-0017's earned cross-refs make possible, and would re-introduce the monolith problem at the concept level. Concepts indexing across KGs via `kg_span` is the right structure.

**Rigid predefined schemas per domain.** Hand-author schemas. Rejected: contradicts continuous learning and exceeds founder capacity; learned, mutable schemas (slots added after `SCHEMA_K` confirmations) scale with experience.

## Consequences
- **Positive:** Structured, inheritable, cross-domain abstraction over atoms; schemas make knowledge gaps explicit and machine-actionable (feeding ADR-0026); facet vectors give the reader and reasoner the right similarity signal per task; cross-domain concepts unlock analogy (ADR-0031) and rich user models (ADR-0039).
- **Negative:** A DAG with multiple inheritance complicates activation/inheritance traversal and demands cycle prevention. Maintaining multiple vectors per concept costs memory and recompute. Promotion/schema thresholds need calibration (ADR-0049).
- **Future work:** Concept death/merge mirroring atom GC (ADR-0025). Affective facet integration with the emotion system (ADR-0035). The self-model (ADR-0020) reads concept schemas to know which competences are grounded; ADR-0039 specializes a user concept with theory-of-mind slots.

## Implementation Notes
Extend `core/concept.nova`: `concept_new(schema)`, `concept_promote(members)`, `concept_link(parent, child)`, accessors `concept_parents`, `concept_schema`, `concept_vector(name)`, `concept_kg_span`, mutators `concept_fill_slot`, `concept_add_slot`. Tag constants `TAG_CONCEPT`, `VEC_LEXICAL|SEMANTIC|RELATIONAL|AFFECTIVE`. Facet matching delegates to `core/similarity.nova`. Concepts reference member atoms by `(kg_id, atom_id)` (ADR-0016) and are assembled from xrefs (ADR-0017). Persist concepts after KGs in the rehydration order (ADR-0048). Test fixtures: promoting a tight cross-KG atom cluster yields a concept with `len(kg_span)==2`; an unfilled high-salience slot raises an imagination-gap signal consumable by ADR-0026; lexical vs semantic facet queries return different nearest neighbors for a homonym. DEPENDS ON: NOVA enhancement #8 (multi-KG/cross-refs the concepts index over). No LLM is used to form or label concepts (ADR-0014); concept labels come from associated language atoms (ADR-0015).
