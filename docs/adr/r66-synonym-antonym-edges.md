# R66: Synonym / antonym edges widen the reasoning graph

## Status

Accepted — R66 round (the "v" enhancement). When a word is defined from the
dictionary, also link it to the **synonyms** and **antonyms** the API returns,
adding analogical edges to the reasoning graph beyond R63's single genus.

## Date

2026-06-09

## Context

dictionaryapi.dev returns, per meaning, not just `definitions` but `synonyms`
and `antonyms`. R59 / R63 used only the definitions (ingest + genus). So a
defined word got one implicative genus edge and nothing else — the synonym graph
the API hands us for free was discarded.

## Decision

- `dict_synonyms(body)` / `dict_antonyms(body)`
  (`src/learning/research_sources.nova`, pure): the distinct, lowercased strings
  from `meanings[].synonyms` / `meanings[].antonyms` (deduped across meanings).
- `_dict_learn` (chat): after the genus, link the headword to each related term
  with a `ROP_ANALOGY` operator — single-token terms only (clean concepts),
  capped at 5 per relation, self-links skipped, concept atoms minted as needed.
  The operator label carries the tag: `src:dict:WORD:syn->TERM` /
  `…:ant->TERM`, so synonyms and antonyms are distinguishable downstream.
- Router (`cognitive_router.nova`): `_cr_analogy_of` surfaces the first SYNONYM
  analogy edge as **"X is like Y"** (skipping `:ant->` edges), and
  `_cr_single_triple` now skips analogy ops so it can't render a bare (or
  antonym) "is like". So a word with a synonym graph but no causal/implicative
  chain reasons "X is like Y" — the synonym graph made usable — while antonyms
  stay in the graph (for `/find`, neighborhoods, a future opposite-aware path)
  without being mis-surfaced as similarity.

## Verification

- **Unit**: `test_research_sources` 52 → 61 (`dict_synonyms` / `dict_antonyms`
  dedupe across meanings, and 404 / no-key / garbage → empty).
  `test_cognitive_router` 21 → 25 (a synonym edge surfaces "decision is like
  choice" with trace `analogy (synonym)` and records the op; the antonym edge
  is **not** surfaced). `reader` / `lexical_anchor` pass.
- **Integration**: defining a word prints `(synonyms: WORD ~ a, b)` /
  `(antonyms: …)` and adds the operators; the synonym count flows into the
  reported ops. Chat builds.

## Consequences / scope

- The dictionary now contributes a small **graph** per word (genus + synonyms +
  antonyms), not a single edge — richer analogical structure for reasoning,
  neighborhoods, and `/why`. A word with no chain but a synonym reasons "X is
  like Y" instead of falling straight to the gloss.
- Synonyms are linked with `ROP_ANALOGY` ("is like"), which is semantically
  right; **antonyms** are also `ROP_ANALOGY` but tagged `:ant->` and excluded
  from the "is like" surface — a pragmatic placement, since there is no
  `ROP_OPPOSITE`. A dedicated opposite relation (and an "X is the opposite of Y"
  surface) is the natural follow-up.
- Single-token terms only and capped at 5 per relation: multi-word synonyms
  ("good luck") are skipped to keep concepts clean, and the cap bounds graph
  growth per word. The edges persist across a restart via R51 (operator
  round-trip), like the genus.
