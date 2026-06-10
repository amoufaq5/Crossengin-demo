# R44: Cleaner triple extraction (content-word reasoning edges)

## Status

Accepted — R44 round. Improves `src/learning/preprocess.nova` so the reasoning
operators learned from fetched pages (R41–R43) are meaningful rather than
function-word noise.

## Date

2026-06-08

## Context

R41–R43 made `/learn` fetch real pages (HTTP, then authenticated HTTPS) and
ingest their `S–R–O` triples as reasoning operators. But the triple extractor
produced noisy edges: fetching the Wikipedia *Photosynthesis* article yielded
93 operators including junk like `spectrum -is_a-> not`, `domain -is_a-> for`,
and `it -is_a-> organism`. When the academic strategy forward-chained over
these, replies read as non-sequiturs (`"chlorophyll … spectrum->not"`).

Root cause: `_pp_ok_triple_arg` accepted any token 2–32 chars that wasn't an
article. So a subject/object could be a pronoun (`it`, `they`), a preposition
(`for`, `by`), or a negation (`not`, `no`) — all of which the surrounding
prose makes grammatically adjacent to the relation keywords (`is`, `has`,
`causes`). A rich ~100-word stopword list already existed
(`preprocess_is_stopword`) but the triple path never used it.

## Decision

Three targeted changes to the extractor, no API change:

1. **Content-word arguments.** `_pp_ok_triple_arg` now rejects any stopword, so
   a triple subject/object must be a content word. This removes the entire
   `X -is_a-> {for,by,not,this,it,…}` class.
2. **Negation drops the triple.** `_pp_pick_obj` returns "" when the relation is
   negated (`is not …`, `has no …`) instead of asserting the opposite of the
   text.
3. **Skip to the content object.** `_pp_pick_obj` skips leading function words
   (articles, determiners, prepositions) up to a small bound to reach the first
   content word, so `is a green pigment` → `green` rather than the article, and
   `is for use` → `use` rather than the preposition.

## Verification

- `tests/unit/test_preprocess.nova`: 88 → 94 checks (the original triple cases
  still pass; new cases cover negation-drops, stopword-subject-drops, and
  content-object selection).
- Direct demonstration on realistic prose:
  - `"The spectrum is not visible…"` → *(no triple)* (was `spectrum->not`)
  - `"It is the most abundant organism"` → *(no triple)* (was `it->organism`)
  - `"This domain is for use…"` → `domain -is_a-> use` (was `domain->for`)
  - `"Chlorophyll is a green pigment…"` → `chlorophyll -is_a-> green`
  - `"Water is part of the cell"` → `water -part_of-> cell`

## Consequences / scope

- Fetched pages now yield clean, content-bearing reasoning edges, so the
  academic strategy chains over them sensibly instead of surfacing junk.
- Still single-word, surface-pattern extraction: compound nouns collapse to
  their first content word (`"lung cancer"` → `lung`), and a past participle
  after a copula can slip through (`"is produced"` → `produced`). Eliminating
  those needs noun-phrase chunking / light POS tagging — a future round. The
  function-word *noise*, which was the visible problem, is gone.
