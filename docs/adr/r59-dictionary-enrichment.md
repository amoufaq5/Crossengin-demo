# R59: Always-aggregate dictionary definitions in research

## Status

Accepted — R59 round (the "o" enhancement). Makes the dictionary a first-class
source aggregated **alongside** the encyclopedia on every research, instead of a
deep fallback that almost never fired.

## Date

2026-06-09

## Context

R53/R55 swept multiple sources but **stopped at the first strong one** — and
since the OpenSearch-resolved Wikipedia article almost always wins, the
Wiktionary / dictionary candidates were deep fallbacks that essentially never
ran (R55 said as much). R58 added `/define` (the structured dictionary API + the
JSON parser), but as a separate command. So a topic's dictionary *definition*
never enriched its research result — the agent learned the encyclopedia article
and nothing from the dictionary.

## Decision

Add an **always-on dictionary enrichment** step to `_research_topic`. After the
encyclopedia sweep — regardless of whether it was strong — fetch the structured
dictionary API (R58 `dict_api_url` / `dict_definitions`) for the topic and ingest
its definitions as knowledge (`src:dict:TOPIC`), aggregated alongside the
article.

- The `/define` dictionary-learning is refactored into a shared
  `_dict_learn(lang, kg, word, now) -> [num_defs, words, ops, defs]`, used by
  both `/define` and the enrichment, so there's one fetch+parse+ingest path.
- `dict_learn_text(defs)` (pure, in `research_sources.nova`) joins the
  definition strings into sentence-terminated prose for the preprocess+ingest
  path — unit-tested.
- Research **succeeds** when the encyclopedia *or* the dictionary learned
  something, so a word the encyclopedia missed but the dictionary has still
  counts.
- ON by default (that's the point — *always* aggregate); `CE_RESEARCH_NO_DICT=1`
  opts out to save the extra fetch.

## Verification

- **Unit** (`test_research_sources` 41 → 43): `dict_learn_text` joins definitions
  into `"a happy accident. good luck. "` and maps an empty list to `""`.
  `json` (47), `learn_pipeline` (10), `preprocess` (99) pass.
- **Live**: `/research photosynthesis` learns the **encyclopedia article** (68
  operators via `en.wikipedia/search`) **and** prints `(+ dictionary: 1
  definition(s), 7 word(s), 0 operator(s))` — both sources in one step.
  `CE_RESEARCH_NO_DICT=1` suppresses the dictionary line. `/define ephemeral`
  still prints its definitions (shared helper). Chat builds.

## Consequences / scope

- Research now cross-sources every topic: encyclopedia prose **plus** a
  dictionary definition from genuinely independent providers, in a single step.
  The autonomous path (`_drain_and_research`) enriches too, since it goes through
  the same `_research_topic`.
- Cost: one extra small dictionary fetch per research (the API is tiny and fast);
  `CE_RESEARCH_NO_DICT=1` removes it. A topic the dictionary doesn't list (proper
  nouns, multi-word topics) returns a 404 → empty definitions → adds nothing,
  gracefully.
- A definition is short prose ingested through the same preprocess + ingest as
  the article (idempotent by label), so it grounds the word's core sense and
  vocabulary; it adds few operators — the encyclopedia stays the operator-rich
  source. The dictionary's value is the definition + cross-validation, not chain
  depth.
- Wiktionary remains in the candidate sweep as an HTML fallback (dormant in
  practice now that the structured dictionary API is the active independent
  source); consolidating the two is possible future cleanup.
