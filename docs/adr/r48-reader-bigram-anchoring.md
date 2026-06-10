# R48: Reader-side bigram anchoring (free-text compounds)

## Status

Accepted — R48 round. Closes the loop opened by R45: compound atoms the learner
creates are now matched when a user types the compound as free text.

## Date

2026-06-08

## Context

R45 taught the extractor to mint compound-noun atoms (`lung cancer` →
`lung_cancer`, `carbon dioxide` → `carbon_dioxide`), so fetched pages produce
clean compound reasoning edges. But the reader still tokenized input on spaces:
a user typing "lung cancer" produced tokens `[lung, cancer]`, neither of which
matched the learned `lung_cancer` concept. So compounds chained internally in
the KG but were unreachable from conversation — the learner and the reader
disagreed on word boundaries.

## Decision

Two small, symmetric changes:

1. **`reader_anchor`** (`src/reader/lexical_anchor.nova`): before anchoring
   token *i* as a single word, try the bigram `tok[i] + "_" + tok[i+1]`; if that
   is a known word atom, anchor the **compound** and consume both tokens. Falls
   back to single-token anchoring when no learned bigram exists. So free-text
   "lung cancer" anchors `lung_cancer`, and the compound concept enters the
   percept and forward-chains like any other.
2. **`_cr_first_content_unknown`** (`src/agent/cognitive_router.nova`): the
   academic strategy's gap check now skips a token pair that forms a known
   bigram, so "what is lung cancer" reasons over `lung_cancer` instead of
   flagging "lung" as an unknown word.

Bounded to bigrams, matching R45's `PP_NP_MAX = 2`.

## Verification

- `test_lexical_anchor` 18 → 27: "lung cancer" → one `lung_cancer` anchor;
  "smoking causes lung cancer" → 3 anchors (the compound merged, not 4); "lung
  disease" (no learned bigram) → 2 single anchors (fallback intact).
- `test_cognitive_router` 15 → 17: a known compound is not a content gap; an
  unlearned compound still flags its first word.
- End-to-end (learner mints `carbon_dioxide` + a `carbon_dioxide→warming`
  operator): free-text "carbon dioxide" anchors `carbon_dioxide`; the router's
  content-unknown check returns empty for "what is carbon dioxide" (recognized)
  and "carbon" for the unlearned "carbon monoxide".
- Chat regression scenarios pass; chat rebuilds.

## Consequences / scope

- Compound concepts learned from the web are now first-class in conversation:
  the reader anchors them, the router reasons over them, and the academic chain
  renders them as units.
- Bigrams only (longer compounds keep their first two words, per R45). The match
  is exact on the learned join — there's no fuzzy/partial compound matching, and
  no morphological normalization (`cancers` won't hit `lung_cancer`). Those are
  later refinements; the learner/reader boundary disagreement that made
  compounds unreachable is resolved.
