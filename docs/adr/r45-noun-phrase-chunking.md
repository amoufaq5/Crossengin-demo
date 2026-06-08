# R45: Noun-phrase chunking + block-aware sentence splitting

## Status

Accepted — R45 round. Extends R44's clean triple extraction so compound nouns
survive as single reasoning atoms.

## Date

2026-06-08

## Context

R44 removed function-word noise from learned triples, but the extractor was
still single-word: `"Smoking causes lung cancer"` produced `smoking → lung`
(losing "cancer"), and `"Carbon dioxide is a gas"` produced `dioxide → gas`
(losing "carbon"). Compound nouns — the bulk of real terminology (`lung
cancer`, `carbon dioxide`, `blood pressure`, `side effects`, `green pigment`)
— were being truncated to their first content word.

A second, related defect surfaced while fixing the first: `strip_html` emits a
`\n` per block element (heading / paragraph / list item), but `_pp_collapse_ws`
flattened those newlines to spaces and `split_sentences` only broke on `.!?`.
So a page's heading text merged into the first body sentence
(`"<h1>Fever</h1><p>Fever is a symptom"` → one sentence `"Fever Fever is a
symptom"`), which — once chunking landed — glued across the block boundary into
junk like `fever_fever`.

## Decision

Three changes to `src/learning/preprocess.nova`:

1. **Noun-phrase chunking** (`_pp_subj_phrase` / object run in `_pp_pick_obj`):
   the subject joins the content-word run going backward from the head; the
   object joins the content-word run going forward from the first content word.
   Joined with `_`, bounded to `PP_NP_MAX = 2` (bigrams) so an appositive or a
   long modifier string can't run away. `"Smoking causes lung cancer"` →
   `smoking → causes → lung_cancer`; `"Carbon dioxide is a gas"` →
   `carbon_dioxide → is_a → gas`.
2. **Newline = hard sentence boundary** (`split_sentences`): a `\n` always ends
   a sentence, so block-separated text never merges.
3. **Boundary-preserving whitespace collapse** (`_pp_collapse_ws`): a
   whitespace run that contains a newline collapses to a newline (not a space),
   so the block boundaries from `strip_html` reach `split_sentences`.

## Verification

- `tests/unit/test_preprocess.nova`: 94 → 99 checks. Two prior single-word
  object assertions were updated to the (correct) compounds — `side` →
  `side_effects`, `green` → `green_pigment` — and new cases cover compound
  subject (`carbon_dioxide`) and object (`lung_cancer`). The end-to-end HTML
  test (heading + body) now keeps `fever` as its own atom rather than merging.
- End-to-end on `"<h1>Photosynthesis</h1><p>Photosynthesis is a process.
  Carbon dioxide is a gas. Smoking causes lung cancer. The spectrum is not
  visible.</p>"` →
  `photosynthesis→process`, `carbon_dioxide→gas`, `smoking→lung_cancer`, and
  *no* triple for the negated clause — the heading does not merge.

## Consequences / scope

- Fetched pages now yield compound-noun reasoning atoms, so chains render with
  real terms (`smoking → lung_cancer`) instead of truncated fragments.
- Bounded to bigrams: trigram compounds keep their first two words
  (`acute lung cancer` → `acute_lung`), and a rare appositive can still
  mis-join within two words. Distinguishing modifier-vs-head beyond bigrams
  needs real POS tagging — a later round.
- Compound atoms (`lung_cancer`) are stored and chain internally, but the
  reader still tokenizes user input on spaces, so a query typed as "lung
  cancer" won't anchor the `lung_cancer` atom directly until reader-side
  bigram anchoring lands (follow-up). The learned-graph quality and chain
  rendering improve regardless.
