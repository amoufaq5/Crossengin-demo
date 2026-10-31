# ADR-0211: LLM-Free NLP as Primary Path

## Status

Proposed. Locks the intended long-term shape of the NL surface: the
primary path is LLM-free (grammar parser + HDC classifier +
deterministic templater), and the sidecar LLM (ADR-0201) is a
bounded fallback whose invocation rate is the metric the
deterministic layer is measured against. Every primitive on the
primary path already ships or is roadmapped to compose existing
primitives.

## Date

2026-08-22

## Context

ADR-0104 shipped the NL surface with a grammar-first parser (~15
canonical shapes) and an LLM-preprocessor fallback. ADR-0200
promotes the sidecar to a first-class boundary component; ADR-0201
locks the sidecar's shape as fallback. This ADR is the other side
of that pair: the primary path is deterministic, LLM-free, and is
the trunk of the design — not a shrinking legacy layer that the
sidecar eventually replaces.

The reason matters. ADR-0013 / ADR-0014 are the invariant: no LLM in
the reasoning path, ever. That invariant is only credible if the
common case also does not invoke an LLM. If every English question
routes through the sidecar and only reasoning is LLM-free, the
sidecar is de facto the reasoning entry point; a compromised sidecar
becomes a compromised model. The primary path being LLM-free is
what keeps the sidecar's role bounded.

The other reason is latency (ADR-0208). A daemon that shells out to
an LLM for every query cannot meet the parity budget; the fast path
must be a byte walk.

### What is already in tree

- `src/nl/grammar_parser.nova` — ~15 canonical patterns; extensible.
- `src/nl/templater.nova` — deterministic ProposalResult → English
  renderer; documented as LLM-free ("same input → same output,
  forever").
- `src/kg/hdc_embed.nova` — 10000-dim hyperdimensional vectors with
  cache.
- `src/kg/semantic_search.nova` — vector-similarity search over
  the KG.
- `src/learning/openie.nova` — open-domain relation extraction.
- `src/learning/entity_resolve.nova` — entity linking against the
  KG.
- WordNet + ConceptNet importers under `src/kg/imports/`.

None of these invoke an LLM.

## Decision

### The primary NL surface uses no LLM

Concretely, the fast-path pipeline is:

1. Tokenize (the shared tokenizer already used by `persona_
   project`).
2. Grammar parse (`src/nl/grammar_parser.nova`). On match, emit a
   StructuredQuery and route to the executor. Done.
3. On grammar unparsed: HDC prototype-vector intent classifier.
   Build one hyperdimensional prototype per query kind from a
   hand-authored corpus of exemplar phrasings; classify by cosine
   similarity against the input's HDC representation; if the top
   match exceeds a confidence threshold, emit the StructuredQuery
   for that kind and route to the executor. Deterministic, sub-
   millisecond.
4. On classifier below-threshold: KG-driven paraphrase. Query-
   rewrite the input via synonym / hypernym chains from the KG
   (WordNet + ConceptNet already imported); retry step 2 and step
   3 against each paraphrase.
5. On all above failing: hand-authored CFG chart parser (CKY over
   an author-maintained grammar of English question forms). This
   is the highest-effort deterministic layer; it lands in a later
   round.
6. Only after all deterministic layers fail: sidecar LLM fallback
   (ADR-0201).

The templater is unchanged from ADR-0104: deterministic, style-
capsule-configured, LLM-free. Same input → same string, always.

### Roadmap for LLM-free expansion

The deterministic layer is not static; it grows toward the observed
question distribution.

- **Grammar expansion.** Grow from ~15 patterns at ship to 50-100
  patterns as usage surfaces new phrasings. Each pattern is a
  small change to `grammar_parser.nova` with a corresponding test.
- **HDC prototype classifier.** Build one HDC prototype vector per
  query kind from a curated exemplar corpus (approximately 50
  phrasings per kind at launch). Classification is a cosine-
  similarity comparison against all prototypes; sub-millisecond.
  New query kinds add new prototypes; existing prototypes refine
  as the exemplar corpus grows.
- **KG-driven paraphrase.** Given a KG rich in synonym / hypernym
  edges (WordNet + ConceptNet already provide the seed), a query
  rewriter can produce equivalent phrasings and retry the grammar
  and classifier. Handles the "same idea, different words"
  variance without an LLM.
- **CKY / chart parser.** A hand-authored context-free grammar
  over English question forms parsed by a standard CKY chart
  algorithm. High-effort in authorship but arbitrary structure
  once done. Land in a later round after the first three layers
  are shipping.

Each expansion is a measurable ROI: the fallback-rate metric
(ADR-0201) shows the delta directly.

### Fallback-rate metric

Every `nl.ask` records whether the deterministic path resolved the
query or the sidecar was invoked. Aggregate:

```
fallback_rate = (queries_routed_to_sidecar) / (total_nl_ask)
```

Tracked per-caller (for cap-token accounting) and daemon-wide (for
the ADR-0211 trend). Reported via `nl.metrics`.

The design goal is monotonic decrease. Each round that lands a new
pattern, a new prototype, a paraphrase rule, or a CFG production
moves some traffic off the sidecar. A round that ships a regression
in the deterministic layer surfaces as a fallback-rate increase and
is treated the same as a latency regression under ADR-0208.

### Templater discipline

The templater is not an LLM and cannot become one under this ADR.
Style capsules (ADR-0108) parameterize phrasing; they do not
introduce inference. A future style capsule that wraps an LLM is
explicitly out of scope and would require a separate ADR that
first argues why the templater's deterministic invariant should be
relaxed.

## Consequences

### Positive

- Daemon runs with no LLM dependency by default. The sidecar is
  optional; a customer who cannot or will not deploy a model
  runner gets a daemon that answers what its grammar and HDC
  classifier can parse, and refuses the rest cleanly.
- Latency is deterministic on the fast path. No network hop, no
  subprocess, no model inference — byte walks and vector math.
  ADR-0208 budgets are achievable.
- Audit trail is clean. Deterministic parses are inspectable
  (`nl.parse_only`); the reasoning path only sees a structured
  query, never a natural-language string interpreted by a model.
- IP-free NLP path. The grammar, templater, HDC classifier, and
  CFG are all in-tree code with no third-party model dependency;
  no license entanglement, no vendor lock, no data leakage.
- Fallback rate is a measurable ROI signal. Every ADR-0211 layer
  round produces a number.

### Negative

- Grammar / classifier development is real ongoing work. Each new
  pattern, each new prototype exemplar, each new paraphrase rule
  is a small round.
- The long tail of natural language is long. Even a mature
  deterministic layer will not cover 100 percent of phrasings;
  the sidecar's residual role never reaches zero.
- CFG authorship is high-effort. The CKY chart parser lands late
  and its grammar is a living artifact operators may need to
  extend for their domain.
- The classifier's exemplar corpus is a labeling burden. Getting
  50 good phrasings per kind at launch, and growing them as new
  kinds land, is real work.

### Neutral

- Determinism is a strong property but stilted phrasing is the
  cost. Style capsules mitigate; users who want LLM-fluent prose
  can request it from a downstream client (the mode-4 SPA can
  post-process for display), but the daemon's rendered answer is
  what the audit sees.
- The sidecar (ADR-0201) remains supported; this ADR is not a
  deprecation.

## Alternatives Considered

1. **LLM as primary, grammar as fallback (rejected).** Would put
   the sidecar in the common path; ADR-0013 / ADR-0014 stops
   being credible; ADR-0208 latency budget cannot be hit.

2. **Grammar-only, no HDC classifier or paraphrase or CFG
   (rejected).** Would ship the ADR-0104 shape unchanged and
   leave the fallback rate high for the foreseeable future. The
   deterministic-layer roadmap is what drives fallback toward
   zero.

3. **LLM for templater (rejected).** Rendering is not reasoning
   but it is user-visible; an LLM-rendered answer is opaque about
   whether it is faithful to the ProposalResult. Determinism is
   the audit-visible property.

4. **CKY / CFG only, no grammar or HDC or paraphrase (rejected
   for pragmatism).** CKY is the most general deterministic
   parser but the most expensive to author. The three simpler
   layers cover the bulk of realistic traffic; CKY is the long-
   tail deterministic layer, not the first thing to build.

5. **Fine-tune a small model for the parse task (rejected).**
   Would improve fallback quality but reintroduces the fine-tune
   dependency ADR-0207 rejects. The sidecar is operator-provisioned
   and unmodified.

## See Also

- ADR-0104 — NL surface layer (the parent ADR).
- ADR-0201 — Sidecar LLM adapter (the fallback side of the pair).
- ADR-0207 — RAG and fine-tuning obsolescence (kindred stance).
- ADR-0208 — Latency budget (why the primary path must be
  deterministic).
- ADR-0013 / ADR-0014 — No LLM in reasoning path (the invariant
  this ADR keeps credible).
- ADR-0108 — Style capsules (templater configuration).
- `src/nl/grammar_parser.nova` — the 15-pattern shipped baseline.
- `src/nl/templater.nova` — deterministic renderer.
- `src/kg/hdc_embed.nova` — the vector space for the classifier.
- `src/kg/semantic_search.nova` — vector similarity used at parse
  and elsewhere.
- `src/learning/openie.nova` — relation extraction.
- `src/learning/entity_resolve.nova` — entity linking.
- WordNet + ConceptNet importers under `src/kg/imports/`.
