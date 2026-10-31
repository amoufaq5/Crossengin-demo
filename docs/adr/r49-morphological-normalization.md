# R49: Morphological normalization (inflected free text hits learned atoms)

## Status

Accepted — R49 round. Improves lexical recall: a user typing an inflected form
("cancers", "studies", "running") matches the learned base atom.

## Date

2026-06-08

## Context

The lexicon stores base forms (the learner mints `cancer`, `study`, `run`), but
the reader matched tokens exactly: free-text "cancers" failed `word_find` and
was treated as an unknown word, even though `cancer` was known. Compounds (R45)
inherited the problem — "lung cancers" missed `lung_cancer`. So plurals and
verb inflections in queries needlessly missed learned knowledge.

## Decision

Add `word_find_morph(lang, form)` (`src/language/word_atoms.nova`): exact match
first, then a small set of conservative English suffix rules —

- plural `-ies → -y` (studies → study), `-es` (boxes → box), `-s` (cancers →
  cancer, but never `-ss`: "less", "boss");
- verb `-ing` (walking → walk, with consonant-undouble running → run and
  add-`e` making → make) and `-ed` (walked → walk, used → use, undouble
  stopped → stop).

**The load-bearing safety property: a stripped variant is accepted ONLY if it
is itself a known atom.** The function never invents a concept — it just finds
an existing one through a plausible inflection. So "bus" → "bu" (not an atom) →
no match, original kept; there are no spurious merges.

`reader_anchor` (single tokens and the R48 bigram) and the router's
`_cr_first_content_unknown` both use `word_find_morph`, so inflected free text
anchors and reasons over the base concept and isn't flagged as a knowledge gap.

## Verification

- `test_word_atoms` 24 → 33: every rule matches its base (cancers→cancer,
  studies→study, boxes→box, running→run, walking→walk, making→make,
  walked→walk, used→use) and the safety cases miss (bus, gas, "less" `-ss`,
  unknown).
- End-to-end through the reader: "cancers" → `cancer`; "lung cancers" →
  `lung_cancer` (compound + plural together); "studies" → `study`; "running
  fast" → `run` + `fast` unknown.
- `test_lexical_anchor` (27), `test_cognitive_router` (17), `test_reader` (13)
  pass; chat regression scenarios pass; chat rebuilds.

## Consequences / scope

- Inflected queries now reach learned atoms, and the display token is preserved
  ("cancers") while resolving to the canonical concept ("cancer").
- Rule-based and English-only — no irregulars (mice → mouse, ran → run, leaves →
  leaf), no derivational morphology (national → nation). Those need a lemma
  dictionary / Porter-class stemmer, a later refinement. The common regular
  inflections that dominate real text are covered, safely (accept-only-if-known
  rules out the classic over-stemming failures).
