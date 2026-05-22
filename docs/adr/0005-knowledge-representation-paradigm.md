# ADR-0005: Knowledge representation paradigm

## Status

Accepted

## Context

Crossengin's brain stores knowledge in several modules — long- and short-term Memory, Academic Knowledge, and the contents the Cognitive and Visionary modules manipulate. A foundational question precedes every storage and indexing choice: what is the *form* of the knowledge being stored?

Three broad paradigms have historical precedent:

- **Pure symbolic.** Typed entities, named relations, logical inference. Cyc, ConceptNet, classical expert systems. Brittle at the edges (everything outside the schema is invisible), but transparent and easy to reason about.
- **Pure vector / sub-symbolic.** Continuous embeddings, similarity-based retrieval. The dominant paradigm in modern LLMs. Opaque to inspection; the meaning of a vector is what it co-occurs with, not what it asserts.
- **Hybrid: graph-of-vectors.** Nodes and edges are symbolic and typed; node attributes and edge weights are learned vectors. Queries can traverse the graph (symbolic) or rank by similarity (vector) or both. Pre-dates LLMs in some forms (graph embeddings, knowledge-graph completion) and is the structural backbone of many modern AI systems that need both inspectability and similarity-based recall.

Crossengin's stated thesis is explicitly non-LLM-pilled. The architecture is modular and the modules need to talk to each other in terms that survive inspection ("the Academic module asserts X about hypertension drugs," "the Memory module recalls Y about the user's morning routine") rather than collapse to opaque vectors. Equally, the system needs to do similarity-based recall, cross-modal matching, and soft pattern recognition — capabilities that the vector form provides naturally.

## Decision

We adopt **hybrid graph-of-vectors** as Crossengin's primary knowledge-representation paradigm. Concretely:

- **Nodes are symbolic.** Each node has a type (drawn from a defined typology per module), a stable identifier, named relations, and a slot schema where applicable (frames). The graph is queryable by traversal: "find all `Treatment` nodes connected to `Condition: hypertension` by a `treats` edge."
- **Node attributes and edge weights are vectors.** Each node carries a learned embedding (the `vector` facet of the composite `MemoryItem` record — ADR-0006). Edges may carry weights, confidence scores, and learned representations of the relation itself.
- **Queries pick the facet they need.** Symbolic queries traverse the graph. Similarity queries rank by vector distance. Hybrid queries (e.g., "find drug nodes whose embedding is near this case description and that are connected to the patient's known allergies by an `allergic_to` edge") combine both. The memory substrate in ADR-0006 supports all three.

This paradigm is the structural pre-condition for the composite `MemoryItem` record in ADR-0006, the cross-domain edges in the academic knowledge module in ADR-0008, and the probabilistic cause-effect graph in the Visionary module in ADR-0010.

## Consequences

Positive: every module can store knowledge that is both inspectable (the symbolic facet supports introspection — constitutional value #8 on interpretability) and pattern-matchable (the vector facet supports similarity recall, cross-modal grounding, fuzzy matching). The paradigm matches what `pgvector` + Apache AGE on a single PostgreSQL instance provides natively — no impedance mismatch with the chosen storage in ADR-0006. Cross-module integration becomes possible because every module speaks the same primitives (typed nodes, typed edges, vector attributes).

Negative: graph-of-vectors is more upfront design than pure-vector storage. Schemas (node types, edge types, slot schemas) need to be designed deliberately rather than emerging from training data. Schema evolution requires migration paths (handled in ADR-0007's update policy). Tooling for inspecting graph-of-vectors data is less developed than tooling for either pure form.

Neutral: this is not a novel paradigm. It is the structural form behind knowledge graphs at scale (Google KG, Wikidata with embeddings) and behind several recent neuro-symbolic architectures. Crossengin is not pioneering the paradigm; it is committing to it as the architectural primitive.

## Alternatives considered

**Pure symbolic.** Rejected. Cyc demonstrated that even decades of curation cannot make a pure-symbolic knowledge base cover the long tail of common-sense and domain knowledge. The brittleness shows up at exactly the moments Crossengin needs robustness — novel inputs, fuzzy matches, partial information.

**Pure vector.** Rejected. This is the LLM paradigm Crossengin is explicitly differentiating from. Pure vector storage cannot support the inspectability requirement in constitutional value #8, cannot easily represent typed cross-domain edges (ADR-0008), and cannot express the kind of structured cause-effect relations the Visionary module's probabilistic graph (ADR-0010) requires.

**Spiking neural networks / neuromorphic representations.** A genuinely different paradigm with potential long-term promise. Rejected for v0 on practical grounds: research-grade tooling, immature hardware support, no clear path to running on RunPod cloud GPUs at v0 scale.

**Probabilistic relational models (e.g., Markov logic networks).** Closer to the chosen paradigm in spirit. Considered specifically for the Visionary module (ADR-0010), which adopts a Bayesian-network variant. As a paradigm for the whole system, MLN-style models are heavier than required for Memory and Academic Knowledge use cases.

## References

- ADR-0006 (Memory architecture and storage) for the concrete schema and indexing.
- ADR-0008 (Academic knowledge module) for the composite-unit form of stored academic knowledge.
- ADR-0010 (Visionary layer) for the probabilistic-graphical-model variant used for cause-effect simulation.
- Constitutional value #8 (interpretability) in ADR-0011 — the requirement this paradigm supports.
