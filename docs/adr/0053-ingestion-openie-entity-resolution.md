# ADR-0053: Ingestion — formats, OpenIE, entity resolution (P3)

## Status

Proposed

## Date

2026-06-11

## Context

`preprocess.nova` is the only path text takes into the KG, and it is narrow:
English-only, ~6 fixed binary relations, at most two triples per sentence, and
it reads nothing but HTML/plain text — no PDF, no CSV, no tables. So the system
cannot ingest a paper or a dataset, and because new mentions are matched only by
exact label, "car" and "automobile" become two atoms and the "one atom answers
many phrasings" property breaks. P3 of the roadmap widens ingestion (formats +
OpenIE) and adds the entity resolution that keeps the KG from fragmenting — the
first real consumer of the P1 HDC layer.

## Decision

Four new modules, each self-contained and individually tested.

**`src/data/table.nova` — tabular decoder.** Parses CSV (with quoted fields and
`""` escapes) and Markdown-pipe tables into a small tagged model (mirroring
`json.nova`), then projects each row into one `ATOM_FACT` with the full row in
its payload (header → cell). To make imported data flow into the existing
analytical-query path, an optional projection maps a numeric *measure* column
into `belief.alpha` and a categorical *group* column into `belief.beta` (each
value gets a small integer code via a returned dictionary), so rows aggregate
with `SELECT ?g (SUM(?a alpha) AS ?t) WHERE { ?a beta ?g } GROUP BY ?g`.

**`src/data/pdf_text.nova` — PDF text extraction.** Scans `BT … ET` text objects
and collects the literal strings shown by `Tj`/`TJ`, decoding PDF backslash and
octal escapes and honoring balanced nested parentheses. Strings outside a text
object (metadata) are ignored. Scope is uncompressed content streams ("start
with text streams"); `pdf_has_flate` flags when streams are FlateDecoded.

**`src/learning/openie.nova` — Open Information Extraction.** A shallow,
heuristic SVO extractor that *discovers* the predicate — it keeps the verb
itself as the relation instead of mapping to the fixed six — and captures
trailing prepositional phrases as n-ary arguments (role → value), which is where
who-did-what-where-when (event structure) lives. Copulas normalise to `is_a`;
negated clauses are rejected (precision over recall). `openie_triples` flattens
facts into `[S,R,O]` (core triple + one `(S, pred_role, value)` per argument)
to feed the existing ingest path.

**`src/learning/entity_resolve.nova` — entity resolution (the critical piece).**
Resolves a mention to a canonical atom in order: EXACT label → ALIAS table → HDC
neighbourhood similarity (`hdc_cosine` ≥ threshold) → NEW. The HDC step is what
unifies spelling-unrelated synonyms: two atoms described by the same neighbours
have near-identical hypervectors (ADR-0051), so "automobile" with a vehicle
neighbourhood resolves to the existing "car" atom. `er_resolve_or_create` mints a
fresh atom (seeded with the mention's hypervector) only when nothing matches.

## Options Considered

- **Shallow heuristic OpenIE (CHOSEN).** A verb-anchored SVO + prepositional-tail
  parser is gradient-free, dependency-light, and good enough to beat the
  fixed-6 extractor on triples/sentence. A full dependency parser was rejected as
  far too heavy for the substrate and unnecessary for the acceptance bar.
- **HDC-similarity entity resolution (CHOSEN)** over exact-only (the status quo
  that fragments) and string-edit distance (rejected: that matches spelling, the
  exact thing HDC was built to get past — "car"/"automobile" are edit-distance
  far but meaning-near).
- **Belief-field projection for GROUP BY (CHOSEN, scoped)** over extending
  `query.nova` to group/aggregate arbitrary payload fields (deferred — a larger
  query-engine change). The projection is explicit, optional, and the full row is
  always preserved in the payload.
- **Uncompressed PDF text streams (CHOSEN)** over a full PDF stack (FlateDecode,
  CID fonts, layout reflow). The roadmap says "start with text streams"; the
  existing `deflate_decode.nova` is the wiring point for compressed streams next.

## Consequences

- **Positive.** All three P3 acceptance criteria pass (measured): a PDF's text
  object ingests to provenanced triples with discovered predicates
  (`photosynthesis is_a process`, `plants absorb carbon_dioxide`,
  `plants absorb_from air`); "car" and "automobile" resolve to ONE atom via HDC
  (and an unrelated mention does not falsely merge); a CSV aggregates correctly
  through `query.nova` GROUP BY (west=400, east=250). The KG gains real format
  reach (CSV, Markdown, PDF text) and meaning-aware deduplication.
- **Negative / costs.** OpenIE is heuristic (false positives/negatives on hard
  syntax); the GROUP BY projection repurposes belief fields for tabular data; PDF
  coverage is partial. None of it is wired into the live ingest pipeline yet.

## Honest gaps

- **Not yet wired into `learn_pipeline`.** These are mechanisms with their own
  tests. Making them live means `learn_pipeline` calling `openie_triples` instead
  of (or alongside) the 6-pattern `preprocess`, and `_lp_ensure_concept` calling
  `er_resolve_or_create` — which needs the mention's *neighbourhood* hypervector
  plumbed through (HDC resolution is only as good as the context it is given) and
  an alias table carried on the registry. Deferred to keep the green gate safe,
  exactly as P2's mechanisms are not yet in the tick loop.
- **OpenIE is a shallow parser.** Verb detection is suffix heuristics (`-ed`,
  `-ing`, `-s`) + a small lexicon + copula/aux handling; no POS tagger or
  dependency parse. Fronted prepositional phrases ("In 1905, Einstein…"),
  passives, coordinated clauses, relative clauses, and coreference are not
  handled, and it is English-only. One fact per sentence.
- **PDF is uncompressed-only.** FlateDecoded streams (most real papers), CID/
  Type0 fonts, ToUnicode CMaps, and reading-order/layout are out of scope;
  `pdf_has_flate` only flags the need. `deflate_decode.nova` is the next hook.
- **GROUP BY projection is a deliberate hack.** Mapping measure→alpha and group→
  beta reuses belief slots as data columns for analytical CSV KGs; the clean fix
  is teaching `query.nova` to group/aggregate payload fields.
- **Entity resolution needs HDC mode.** The similarity path is inert unless
  `ATOM_EMBED_MODE = HDC` and candidate atoms carry neighbourhood encodings; in
  LEGACY mode it is exact + alias only. The acceptance threshold is a fixed
  constant (600 milli), not adaptive.
- **Scraping / multimodal / quality gates deferred.** The roadmap's
  politeness-aware crawler, structured connectors (arXiv/PubMed/Wikidata),
  OCR/STT→triple routing, and explicit source-authority + contradiction gating
  at ingest are follow-ups; the base modules (`internet_fetch`, `kg_rss_ingest`,
  `image_ocr`, `source_authority`) already exist to wire against.

## Implementation Notes

- The decoders mirror `json.nova`'s tagged-model + accessor shape; OpenIE reuses
  `preprocess`'s sentence splitter, stopword set, and NP bound. Strings are built
  with `chr` / `substr`; the integer-only style is preserved.
- **Tests.** `test_entity_resolve` (19: exact/alias/HDC/precedence + the
  car↔automobile acceptance + no-false-merge), `test_table` (24: CSV quoting,
  Markdown, int detection, the GROUP BY acceptance, payload fidelity),
  `test_openie` (33: discovered predicate, article drop, intransitive n-ary,
  copula→is_a, multi-arg event, negation rejection, no-verb guard, triple
  flattening), `test_pdf_text` (10: fragments, escapes, octal, nested parens,
  BT/ET scoping, flate detection, PDF→triples). All four modules are new and
  imported by nothing else, so the existing suite is unaffected.
- **Next (P3 → P4).** Wire `openie_triples` + `er_resolve_or_create` into
  `learn_pipeline`; inflate FlateDecoded PDFs via `deflate_decode`; then P4
  (agentic tooling) can act on the richer, deduplicated KG.
```
P1 HDC embeddings ──► P2 predictive coding + 3-factor ──► P3 ingestion/OpenIE
                                                                │
                          P5 sim + self-improve ◄── P4 agentic tooling
```
