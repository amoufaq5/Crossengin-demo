# r76 — Knowledge-base bulk import (NL_AND_COVERAGE C1)

## Status
Accepted (WordNet track landed; ConceptNet + Wikidata tracks pending).

## Context
CrossEngin's cross-domain breadth is capped by two things: a tiny fetch
whitelist (~4 default domains) and a high-precision / low-recall text triple
extractor (6 patterns, 2 triples/sentence). Scraping breadth one triple at a
time loses the race to the knowledge-acquisition bottleneck.
`NL_AND_COVERAGE.md` Section C1 names the fix: **import breadth that already
exists in curated, structured form** (WordNet, ConceptNet, Wikidata, …), then
grow it autonomously. This ADR records the import architecture and the first
(WordNet) track.

## Decision
Two new modules under `src/data/`:

- **`kb_import_core.nova`** — shared importer substrate: a delimiter splitter,
  LF line splitter, dedup-by-label concept interning (`kbi_concept`), curated-KB
  provenance tagging (`provenance="kb"`, `kb_source="<name>"`, ADR-0029) +
  belief seeding (Beta(3,1): above fetched evidence, below user-taught), and an
  import-stats record so callers get a truthful count of what landed.

- **`import_wordnet.nova`** — WordNet importer over a NORMALIZED feed:
  - `S|id|primary|gloss` → CONCEPT atom keyed `wn:<id>` (label is the synset id,
    not the word, so polysemy stays distinct and edges resolve by stable key);
  - `W|id|word` → intern word + weighted sense to the concept (synonymy emerges
    from many words → one concept);
  - `H|id|hyper_id` → `ROP_IMPLY` operator (hyponym IS-A hypernym);
  - `A|id|anto_id` → `ROP_OPPOSITE` operator (antonymy).
  Two passes (concepts/words, then edges). Idempotent: re-import refreshes
  belief and reuses operators by deterministic label, never duplicating.

Mapping rationale: there is no native IS-A operator kind; the 5 kinds are
CAUSAL / IMPLY / ANALOGY / EVIDENCE / OPPOSITE. Hypernymy ("a car is a vehicle")
maps to `ROP_IMPLY` (membership implication); antonymy maps to the existing
`ROP_OPPOSITE` (R67). Synonymy needs no operator — it is the existing
word→concept sense binding (`first_atoms._bind` pattern) with multiple words on
one concept.

## Transport boundary (honest scope)
The NOVA module parses a **normalized feed**, not a raw WordNet dump. An
ops-layer converter turns `data.noun` / `index.noun` / Prolog files into the
normalized line format. This mirrors `internet_fetch` (the module gates +
ingests; the transport supplies bytes) and keeps the NOVA side pure and
unit-testable.

## Consequences
- Fixes the synonym + word-sense gap the text extractor cannot, with provenance
  and trust weighting intact.
- Establishes the import pattern (`kb_import_core`) that the ConceptNet and
  Wikidata tracks reuse — they add a record dialect, not new infrastructure.
- Coverage compounds: imported concepts feed `rule_inference`,
  `link_prediction`, and `cross_kg_references` (NL_AND_COVERAGE C3).

## Honest gaps / future work
- The raw-dump → normalized-feed converter script is NOT in this change (ops
  layer). The feed format is the contract.
- Entity resolution across KBs (NL_AND_COVERAGE C-entity-link) is future: today
  dedup is by exact label within one KG; cross-KB "car"≡"automobile" linking
  waits on the HDC embedding keystone (ENHANCEMENTS P1 / LAYER L0-1).
- Belief prior Beta(3,1) is a single flat tier; per-source authority tiers
  (ADR-0029) can refine it.
- No streaming/batched ingest yet — a multi-million-line feed loads in one pass;
  a chunked path is future work.

## Verification
`tests/unit/test_import_wordnet.nova` (8 tests: concept creation, synonymy,
polysemy, hypernym/antonym operators, provenance, edge count, idempotency).
NOTE: authored against the real `atom_store` / `multi_kg_manager` /
`reasoning_atoms` / `word_atoms` APIs but NOT yet compiled in this environment
(no NOVA toolchain present) — `make build && make test` is the acceptance gate
and must run in a toolchain session.
