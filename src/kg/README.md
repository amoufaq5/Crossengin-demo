# Multi knowledge-graph store

One knowledge graph per domain, auto-spawned on new-domain detection. Holds mutable atoms with Bayesian confidence and similarity-weighted cross-KG references.

**Governing ADRs:** ADR-0016, ADR-0017, ADR-0018

**Status:** Pending. Builds on core/knowledge.nova, core/similarity.nova, core/belief.nova; DEPENDS ON NOVA enhancement #8.

See [`docs/adr/`](../docs/adr/) for the decisions that bind this component, and the repository [README](../README.md) for the substrate overview.
