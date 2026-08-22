# ADR-0207: RAG and Fine-Tuning Obsolescence

## Status

Proposed. Names the claim explicitly: given the CrossEngin substrate
(KG updates + capsule install + pattern install + persona projection
+ self-model per ADR-0206), the two dominant LLM-augmentation
patterns — retrieval-augmented generation (RAG) and fine-tuning —
are no longer necessary. This ADR is a design statement, not a
migration guide; it locks the framing that guides how CrossEngin
positions against the industry default.

## Date

2026-08-22

## Context

The two escape hatches the industry uses to update or specialize a
frozen-weight LLM are RAG and fine-tuning.

- **RAG** — the model receives per-query context assembled from an
  external similarity index (a vector database of embeddings).
  Update cost is the re-embedding pass over changed documents.
  Reasoning is still weight-implicit; retrieval is by similarity;
  the model can still hallucinate around its retrieved context.
- **Fine-tuning** — the model's weights (or a low-rank adapter) are
  updated on domain data. Update cost is a retraining pass. The
  model's shape is now domain-specialized but every failure mode of
  frozen weights still applies (opacity, hallucination, no audit
  path).

Both patch symptoms. Neither addresses the underlying frame:
knowledge is weight-implicit, reasoning is weight-implicit, deploy
is a hosted API call. ADR-0200 rejects that frame at every level.

The claim of this ADR is that CrossEngin's substrate — where
knowledge is explicit KG data, reasoning is explicit engine
traversal, updates are surgical ingest turns, and "unknown" is a
first-class answer (ADR-0206) — subsumes what both RAG and fine-
tuning give a customer, without any of their costs.

## Decision

CrossEngin ships no RAG index and no fine-tuning loop. The update
lifecycle is:

- `ingest.file` — a new document enters the review queue.
- Reviewer (or auto-approval policy per ADR-0101) elevates the
  candidate atoms to accepted atoms.
- Accepted atoms are live for reasoning immediately; no re-embed
  pass, no re-training pass, no restart.

Retraction is the reverse:

- `retract` (existing NL verb) marks an atom retracted.
- Retracted atoms are excluded from reasoning walks; their
  provenance persists for audit.
- A retract can be reversed by a re-ingest with new authority
  weighting.

There is no separate retrieval index. Retrieval is graph walk over
the KG. Similarity is a first-class edge kind (produced by the HDC
embedding kernel from `src/kg/hdc_embed.nova`) but the walk is
explicit, not implicit; similarity-driven retrieval always names the
edges it traversed and can be audited.

There is no weight re-training loop. Domain specialization is
achieved by baking a domain-scoped child (ADR-0203) or by per-user
selective load (ADR-0205); both operate on data, not weights.

### Comparison table

| Dimension | LLM (frozen) | LLM + RAG | LLM + fine-tune | CrossEngin |
|---|---|---|---|---|
| Knowledge storage | Frozen weights | External store + embeddings | Weights (re-trained) | Explicit KG + capsules |
| Update cost | Retrain (weeks-months) | Re-embed (hours) | Retrain adapter (hours-days) | Ingest one record (seconds) |
| Reasoning | Weight-implicit | Weight-implicit + similarity | Weight-implicit | Explicit engines |
| Inspectability | Opaque | Retrieval visible, reasoning opaque | Opaque | End-to-end |
| Hallucination risk | High | Medium | Medium | Zero (says "unknown") |
| Vendor lock | Provider API | Embed model + LLM | Fine-tune platform | Self-hosted, no external |
| Domain focus | General | General | Fine-tune per domain | Per-child domain-scoped |
| Multi-user | External auth | External auth | Multi-adapter | Native (caps + ownership) |
| Prompt-injection surface | Full user input | Retrieved docs + input | Full user input | Grammar-parsed query only |

### Failure-mode mapping

Each competitor's failure mode maps to a specific CrossEngin
mitigation:

- **Hallucination (LLM, LLM+RAG, LLM+fine-tune).** CrossEngin's
  self-model (ADR-0206) enumerates known-unknowns. When the KG has
  no atom for a topic, the answer is "unknown," not a plausible
  guess. There is no weight-implicit generation to hallucinate
  from.
- **Update lag (LLM: months; LLM+RAG: hours to re-embed; LLM+fine-
  tune: hours to days).** CrossEngin's update is one ingest turn:
  seconds from source to live answer once the review gate passes.
- **Retrieval-context poisoning (LLM+RAG).** RAG systems retrieve
  from a shared index; a poisoned document surfaces on any query
  whose embedding is close. CrossEngin's retrieval is graph walk
  from a specific KG atom; a poisoned atom is scoped to the
  reasoning walks that reach it and is subject to the provenance
  weight (ADR-0029), which downweights atoms from low-authority
  sources.
- **Prompt injection via retrieved content (LLM+RAG).** CrossEngin
  does not concatenate retrieved text into a model prompt. The
  reasoning path is engines, not prompts.
- **Vendor lock (LLM: provider API; LLM+RAG: embed model + LLM;
  LLM+fine-tune: fine-tune platform).** CrossEngin's daemon is
  self-hosted; the only optional external hop is the ADR-0201
  sidecar LLM fallback, and even that is operator-provisioned.
- **Multi-tenant isolation (LLM: external auth service; RAG: shared
  index).** CrossEngin isolates via the ownership overlay
  (ADR-0205) and capability tokens (ADR-0105); every atom access
  passes through the caller-scoped overlay.
- **Domain focus (LLM: general model per query; fine-tune: one
  model per domain).** CrossEngin's per-child bake (ADR-0203)
  ships only the domain slice; per-user selective load (ADR-0205)
  projects a subset without a bake.

### Update lifecycle in operational detail

- **Add a fact.** Operator or an integration calls `ingest.file`
  with the source document; the pipeline extracts atoms and edges
  (OpenIE, entity resolution — see `src/learning/openie.nova`,
  `src/learning/entity_resolve.nova`); the review queue holds them
  pending; `ingest.policy` either auto-approves (if the source is
  high-authority) or the human reviewer approves. Live.
- **Change a fact.** Ingest the new record; the entity-resolution
  step attaches the new atom to the existing entity; belief
  arithmetic updates (`bayesian_updates`) integrates the new
  evidence with the existing atom's belief; if the new record
  contradicts the existing one, both remain and the self-model
  reports a spread (ADR-0206 `self.confidence` returns a spread
  indicator).
- **Remove a fact.** `retract` marks the atom retracted; the
  atom's provenance persists for audit; reasoning walks exclude
  it.
- **Change a whole domain.** Bake a new child (ADR-0203) with the
  updated manifest; push a KG-delta to existing children.

Everything is known or explicitly unknown. There is no black-box
guessing at any step.

## Consequences

### Positive

- No embed-model dependency. CrossEngin's HDC embedding kernel
  handles similarity where similarity is useful, and it is under
  the daemon's control; no third-party embedding model, no
  proprietary embedding format, no re-embed cost on updates.
- No fine-tune platform dependency. Domain specialization is a
  bake, not a training run; no GPU cluster required.
- Zero hallucination by construction. The daemon cannot invent
  facts because there is no weight-implicit generator in the
  answer path. The templater (ADR-0104) constructs answers from
  ProposalResult data; if the ProposalResult has no data, the
  answer says so.
- Auditable end-to-end. Every fact traces to a source atom with
  provenance; every answer traces to the atoms and skill runs that
  produced it.
- Marketing frame. "Not RAG, not fine-tuning, not a chatbot" is a
  crisp positioning statement customers understand.

### Negative

- Framing risk. Customers who ask "how do I do RAG with
  CrossEngin?" are asking the wrong question. Sales and docs must
  explain that they do not; they ingest. Some customers will
  bounce because they wanted a familiar shape.
- Ingest work is real. The customer's data must be structured
  enough for OpenIE + entity resolution to extract atoms. Very
  unstructured data (a scanned handwritten notebook) requires more
  transducer work upfront than dropping into a vector store would.
- The comparison table is a claim, not a proof. Customers will
  benchmark; the benchmark harness (ADR-0208) is how we back the
  table.

### Neutral

- Similarity is still a tool. The HDC embedding kernel produces
  similarity edges when useful; they are walked explicitly by the
  reasoning engines. CrossEngin uses similarity; it does not use
  similarity as its retrieval frame.
- The sidecar LLM (ADR-0201) is a boundary component, not a RAG
  layer. It parses; it does not retrieve; it does not compose.

## Alternatives Considered

1. **Ship a RAG layer as a compatibility shim (rejected).** Would
   satisfy customers who ask for RAG but blur the frame. Every
   piece of the substrate is designed to be better than RAG on the
   axes RAG customers care about; a shim would carry RAG's failure
   modes into a system that avoids them by construction.

2. **Ship a fine-tune-compatible export (rejected).** Same
   framing hazard as above. If a customer's problem is genuinely
   "we already have fine-tuned adapters we want to reuse,"
   CrossEngin is not their tool for the near term.

3. **Ship RAG at the NL surface (rejected).** Would put similarity-
   driven retrieval into the answer path, which is the exact shape
   this ADR rejects.

4. **Silence on RAG / fine-tuning (rejected).** Customers who have
   only seen RAG-shaped tools need the frame stated clearly. This
   ADR is the frame.

## See Also

- ADR-0101 — Data acquisition and review pipeline; the ingest
  lifecycle this ADR relies on.
- ADR-0206 — Beliefs and self-awareness; "knows it does not know."
- ADR-0211 — LLM-free NLP primary path; part of the frame.
- ADR-0200 — Mother/Child factory; the deployment shape.
- ADR-0203 — Bake pipeline; domain specialization without training.
- ADR-0205 — Per-user selective load; per-persona specialization
  without training.
- ADR-0029 — Source authority weighting.
- ADR-0087 — Provenance and licensing ledger.
- `src/learning/openie.nova` — atom / relation extraction.
- `src/learning/entity_resolve.nova` — entity linking.
- `src/kg/hdc_embed.nova` — similarity, when useful.
