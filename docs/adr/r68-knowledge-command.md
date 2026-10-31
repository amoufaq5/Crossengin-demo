# R68: A consolidated /knowledge WORD view

## Status

Accepted — R68 round (the "x" enhancement). One read-only command surfaces
everything the agent knows about a word: gloss, genus, synonyms, antonyms, other
relations, and the sources behind them.

## Date

2026-06-09

## Context

The dictionary path now attaches a lot to a word — a gloss (R60), a genus
operator (R63), synonym edges (R66), antonym edges (R67) — and operators carry
`src:` provenance (R64). But there was no way to *see* it: you'd ask "what is X"
(one chain), `/why` (the last reply's sources), `/find` (similar atoms). The
knowledge was there, scattered across commands.

## Decision

- `dict_rel_tag(label)` (`src/chat/helpers.nova`, pure, unit-tested): classify a
  dictionary-minted operator by its label tag — "genus" / "syn" / "ant" / "" (a
  plain learned relation).
- `_admin_knowledge(lang, kg, arg)` (chat) — `/knowledge WORD` (alias `/know`):
  resolve the word (morphology-aware, showing the base form when it differs),
  print the gloss, then walk the concept's outgoing operators and bucket them by
  `dict_rel_tag` + relation kind into **genus**, **synonyms**, **antonyms**, and
  other **relations** (rendered with `_cr_rel`'s phrase), plus the distinct
  **sources** (`src_label_name`, R64) and the operator count.

## Verification

- **Unit** (`test_chat_helpers` 87 → 92): `dict_rel_tag` over a genus / synonym /
  antonym / plain-relation / seed label.
- **Integration**: after defining a word, `/knowledge WORD` prints its gloss,
  `genus: WORD -> G`, `synonyms: …`, `antonyms: …`, `relations: …`, and
  `sources: dictionary` (and Wikipedia for a researched word). Chat builds.

## Consequences / scope

- The agent's knowledge of a word is now inspectable in one place — useful for
  the user, for debugging the dictionary pipeline, and as the natural surface for
  future per-word facts (confidence, senses, decay).
- Read-only and morphology-aware: `/knowledge cancers` resolves to "cancer" and
  shows its knowledge; a word with no concept atom says so. It reads the live KG,
  so it reflects exactly what `/save` would persist.
- Buckets are by the operator's label tag + kind, so a word taught via `/learn`
  (relations, no dict tags) shows under "relations", and a dictionary word shows
  its genus/synonyms/antonyms — the same view spans both provenance paths.
- It lists outgoing operators from the word's concept; incoming edges (what
  points *at* the word) and the word's sense xrefs are not shown yet — a richer
  `/knowledge` (in/out, senses, per-source confidence) is future work.
