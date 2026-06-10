# R60: Autodefine unknown words (a dictionary sense without full research)

## Status

Accepted — R60 round (the "p" enhancement). An unknown content word gets a
dictionary definition at idle — a real sense, stored as a gloss and surfaced as
"X means: …" — without needing a full research trigger.

## Date

2026-06-09

## Context

R59 aggregates a dictionary definition during **full research**, but research is
gated (`CE_AUTORESEARCH`) and rate-limited to one topic per turn. Every *other*
unknown word the agent meets is just stub-minted by `_drain_and_teach` — a bare
atom with no content. So most unknown words end up known-but-empty: the agent
stops saying "I don't know X" yet still can't say anything *about* X.

## Decision

Give the idle unknown-word drain a lightweight, per-word dictionary lookup, and a
place to put the result.

- **Word gloss** (`src/language/word_atoms.nova`): `word_set_gloss` /
  `word_gloss` store a word's primary definition on the atom payload.
- **Autodefine** (`_drain_and_teach`): gated by `CE_AUTODEFINE` (opt-in, like
  `CE_AUTORESEARCH`, since it makes outbound requests) and a per-turn budget
  (`CE_AUTODEFINE_BUDGET`, default 2), each drained unknown also gets its
  dictionary definition via the R59 `_dict_learn` — which ingests the definition
  prose — and its primary definition attached as the word's gloss. The unknown
  word becomes known **with a sense**, not a bare stub.
- **Router surface** (`src/agent/cognitive_router.nova`): `_cr_first_gloss` plus
  a gloss fallback in `_cr_academic` and `_cr_unknown` — a known word that has a
  gloss but no reasoning chain answers **"X means: &lt;gloss&gt;"** instead of
  "I don't have a model of X". It reuses the stopword-aware content-word
  selection, and sits *after* the chain/triple checks so a word that later gains
  operators reasons over them in preference to its gloss.

## Verification

- **Unit**: `test_word_atoms` 83 → 87 (gloss set / read / empty / visible via
  `word_find`); `test_cognitive_router` 17 → 21 (the academic and unknown paths
  surface the gloss; a known word *without* a gloss does not produce a "means:"
  reply). `lexical_anchor` (27), `reader` (13), `research_sources` (43), `json`
  (47) pass.
- **Live**: `CE_AUTODEFINE=1`, turn 1 "what is serendipity" → the honest gap
  reply *and*, at idle, `(defined 'serendipity': A combination of events which
  have come together by chance …)`; turn 2 "what is serendipity" → `serendipity
  means: A combination of events …` (trace `academic: dictionary gloss`). Chat
  builds.

## Consequences / scope

- Unknown content words now get a dictionary sense **autonomously and cheaply**,
  separate from full research — opt-in and budgeted. The agent answers
  "X means: …" the next time it's asked, instead of an indefinite gap.
- **Idle-loop (two-turn)**: the gloss is set *after* the turn's reply, so the
  same turn still gaps and the next turn answers (the R50 model, pre-R52). A
  same-turn re-answer for autodefine would mean extending R52 — whose adoption
  gate currently accepts only forward-chain / known-relation traces, not a gloss
  — which is future work.
- The gloss is the **primary** definition; polysemy collapses to the first sense.
  The definition prose is still ingested (the R59 path), so its vocabulary enters
  the KG even though the headword→definition link isn't an explicit operator.
- The budget bounds per-turn fetches; words the dictionary lacks (proper nouns,
  multi-word topics → 404) simply stay stubs, gracefully.
