# R69: /define sets the gloss (consistent dictionary learning)

## Status

Accepted — R69 round (the "y" enhancement). Moves the gloss-setting into
`_dict_learn`, so `/define`, autodefine, and research enrichment all attach the
word's gloss — closing the gap R68 surfaced (`/define WORD` then `/knowledge
WORD` showed no gloss).

## Date

2026-06-09

## Context

R60 stored a word's primary definition as the `"gloss"` payload — but only on the
autodefine path (`_autodefine_word` set it after calling `_dict_learn`).
`/define` and the R59 research enrichment called `_dict_learn` directly, so they
learned the definition and minted the genus/synonym/antonym operators but never
set the gloss. R68's `/knowledge` made this visible: after `/define happy`, the
view had a genus and synonyms but no gloss line.

## Decision

Set the gloss inside `_dict_learn`, where every caller funnels through:

```
word_set_gloss(word_intern(lang, nword, now), defs[0][1])
```

`word_intern` ensures the word atom exists (the `/define` path may not have one,
since it doesn't `au_ingest` first), then the primary definition becomes the
gloss. `_autodefine_word` no longer sets it (the duplicate is removed); it just
reports.

## Verification

- **Unit** (`test_word_atoms` 108 → 110): the `/define` scenario — a word absent
  from the lexicon, `word_intern` creates it, `word_set_gloss` sets the gloss,
  and `word_gloss(word_find(...))` returns it.
- **Integration**: `/define WORD` then `/knowledge WORD` now shows the gloss line
  alongside the genus / synonyms / antonyms; autodefine and research enrichment
  set it the same way. Chat builds.

## Consequences / scope

- All three dictionary paths now attach the gloss uniformly, so `/knowledge`
  (R68) is complete after any of them, and the router's "X means: …" fallback
  (R60) works for a manually `/define`d word too — not just autodefined ones.
- Research enrichment (R59) now sets a researched topic's gloss to its dictionary
  definition. That's the intended sense for a common word; for a proper-noun
  topic with no dictionary entry, `_dict_learn` returns early (no gloss), so
  nothing changes there.
- The gloss is the primary sense (first definition); re-defining a word
  overwrites it with the latest fetch — idempotent and current, matching the
  rest of the dictionary learning.
