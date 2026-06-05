# ADR-0016: Atom design (mutable, KG-stored, cross-KG referenced, Bayesian confidence)

## Status

Proposed

## Date

2026-05-25

## Context
The atom is the persistent unit of knowledge in CrossEngin. As defined in ADR-0002, nodes produce atoms only for novel patterns, atoms live in domain-specific KGs, and nodes can read atoms they did not create. Before we can build the multi-KG layer (ADR-0017), the concept layer (ADR-0018), procedural memory (ADR-0019), or belief refinement (ADR-0023), we need one canonical atom representation that every part of the substrate agrees on. Getting this layout wrong is expensive: atoms are the most numerous persistent objects (millions per KG), are read on nearly every reasoning step, and must be serialized in the persistence snapshot (ADR-0048).

The hard requirement is that an atom must be (1) mutable — updated as new evidence arrives rather than re-created, so that identity is stable across learning; (2) confidence-bearing — every atom carries a Bayesian belief so the system can reason about how much it trusts a fact and decay it over time; (3) cross-KG referable — an atom in KG-medicine can point at an atom in KG-biology without copying it, which is how cross-domain concepts are built; and (4) cheap to read foreign — a reasoner node in another part must be able to dereference and evaluate an atom it never produced.

Constraints: 2 founders at 8h/day on a bootstrap budget mean we cannot afford a bespoke object database; we reuse `core/knowledge.nova` for storage and `core/belief.nova` for confidence rather than inventing parallel machinery. NOVA values are tag-prefixed lists/maps, so the atom must read as a normal NOVA structure with a constructor and accessors, and must serialize through `runtime/json.nova` / `runtime/db.nova` for snapshots.

## Decision
We define the atom as a tag-prefixed NOVA structure with the layout `[TAG_ATOM, id, kg_id, kind, label, payload, belief, embed_ref, xrefs, provenance, created_moment, updated_moment, version]`. `id` is a KG-local stable identifier; `kg_id` names the owning KG (ADR-0017); `kind` is one of `ATOM_FACT`, `ATOM_RELATION`, `ATOM_CONCEPT`, `ATOM_SKILL`, `ATOM_LANG` (the language atoms of ADR-0015) and `ATOM_RULE` (procedural, ADR-0019); `payload` is a kind-specific map; `belief` is a `core/belief.nova` (alpha/beta) handle; `embed_ref` references the multi-vector embedding held by the concept layer (ADR-0018); `xrefs` is a list of cross-KG reference edges (ADR-0017); `provenance` records source tier (ADR-0029) and producing node/part; `version` increments on every mutation.

Confidence is Bayesian, not a scalar. We do NOT store a float "confidence". We store alpha/beta counts via `belief_new(alpha0, beta0)` and expose `atom_confidence(a)` which returns the posterior mean `alpha / (alpha + beta)` through `runtime/confidence.nova`. Supporting evidence calls `atom_observe(a, +1)` (increment alpha); contradicting evidence calls `atom_observe(a, -1)` (increment beta). This gives us both an expectation and a variance, so the system distinguishes "0.7 from 3 observations" from "0.7 from 300 observations" — essential for the self-learning thresholds in ADR-0030 and conflict handling in ADR-0023.

Mutation is in-place by identity. `atom_update(a, payload_delta)` merges new payload fields, bumps `version`, sets `updated_moment`, and leaves `id`/`kg_id` fixed so all inbound synapses and xrefs remain valid. Atoms are never silently replaced; superseding facts are recorded as evidence against the old belief, which is how decay-based death (ADR-0025) eventually garbage-collects an atom whose posterior mean falls below the GC threshold.

## Options Considered
**Immutable atoms with versioned append (event-sourced).** Every change writes a new atom and supersedes the old one. Rejected as the default: it breaks reference stability (every xref and synapse would need rewriting on each update), multiplies storage for the millions of atoms per KG, and makes "the current belief about X" a query rather than a field. We keep an append-only *audit* trail at the decision-log level (ADR-0043) but not at the atom level.

**Scalar confidence float instead of alpha/beta.** Simpler and smaller. Rejected because a single float cannot express evidence volume or support principled decay and conflict resolution; ADR-0023, ADR-0029 and ADR-0030 all require the count-based posterior. Reusing `core/belief.nova` costs us nothing extra since it already exists.

**Atoms as opaque blobs keyed in one global KG.** Store all knowledge in a single `core/knowledge.nova` instance with a domain field. Rejected in favor of multi-KG (ADR-0004 organizational decision, ADR-0017 mechanism): a global store defeats domain-local spreading activation in the reader (ADR-0012) and makes cross-tenant isolation in v2 (ADR-0047) far harder. The `kg_id` field on every atom is what makes namespacing cheap.

**Embedding stored inline on the atom.** Rejected: multi-vector embeddings (ADR-0018) are large and shared across the concept hierarchy; we store an `embed_ref` and let the concept layer own the vectors, keeping the atom small enough to keep millions resident.

## Consequences
- **Positive:** One uniform, small, serializable knowledge unit usable by every part. Stable identity under mutation keeps synapses and cross-KG references valid for the life of the atom. Bayesian confidence is first-class, enabling principled learning-enough decisions (ADR-0030), conflict handling (ADR-0023), and decay-based GC (ADR-0025). Reuse of `core/belief.nova` and `core/knowledge.nova` minimizes founder effort.
- **Negative:** In-place mutation means we must be disciplined about the audit trail living elsewhere (ADR-0043) to retain history. The `version` field and `updated_moment` add bookkeeping on every write. Cross-KG dereference cost is paid on read; hot atoms may need a small resident cache.
- **Future work:** ADR-0017 defines how `xrefs` are formed and weighted; ADR-0018 defines `embed_ref` and concept promotion of atoms; ADR-0023 refines decay and conflict on `belief`; ADR-0025 sets the birth/death thresholds that act on `belief` posterior mean and `updated_moment`.

## Implementation Notes
Add an `atom` module layered on `core/knowledge.nova`: `atom_new(kg_id, kind, label, payload)` (initializes `belief_new(1,1)` as a uniform prior, sets `created_moment` from `core/moment.nova`, `version=0`); accessors `atom_id`, `atom_kg`, `atom_kind`, `atom_payload`, `atom_belief`, `atom_xrefs`, `atom_confidence`; mutators `atom_update`, `atom_observe`, `atom_add_xref`. Tag constants `TAG_ATOM`, `ATOM_FACT|RELATION|CONCEPT|SKILL|LANG|RULE` live next to the existing `core/knowledge.nova` tags. Serialize via `runtime/json.nova` and persist through `runtime/db.nova` for the snapshot (ADR-0048). Test fixtures: an atom round-trips through update/observe with stable `id`; `atom_confidence` matches the alpha/beta posterior mean from `runtime/confidence.nova`; a foreign part reads and evaluates an atom it did not create. DEPENDS ON: NOVA enhancement #8 — multi-KG namespacing + cross-KG reference edges (the `kg_id`/`xrefs` fields rely on it). No LLM is involved in atom creation, mutation, or evaluation (ADR-0014).
