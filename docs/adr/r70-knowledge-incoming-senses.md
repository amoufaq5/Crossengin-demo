# R70: /knowledge shows incoming edges + senses

## Status

Accepted — R70 round. Extends `/knowledge WORD` (R68) with two more facets: the
**incoming** reasoning edges (what points at the concept) and the word atom's
**senses** (its cross-KG references to concept atoms).

## Date

2026-06-09

## Context

R68's `/knowledge` listed only the concept's *outgoing* operators (genus,
synonyms, antonyms, relations) and aggregated sources. But a concept is also a
*target* — other concepts imply or cause it — and a word has *senses* (the
cross-KG bindings the reader resolves). Neither was visible, so the view showed
half the local graph around a word.

## Decision

- `_know_sense_label(kg_label, concept_label)` (`src/chat/helpers.nova`, pure,
  unit-tested): render one sense as `kglabel/conceptlabel`.
- `_admin_knowledge` now also:
  - **Incoming edges** — `rk_operators_to(kg, concept_id)`; the "from" side is
    each operator's premise (`rop_premise`), rendered as `implied by: A, B`
    (distinct), and those operators' sources fold into the sources line too.
  - **Senses** — `word_senses(wa)` (the word atom's xrefs); each is resolved by
    its destination KG **label** (`xref_dst_kg` stores the KG label, so the
    lookup is `kg_find(kgreg, label)`, not the id-based `kg_get`) and atom, into
    `senses: reasoning/infection, …`.
  The footer now reads `(N out, M in)`. The command takes `kgreg` (threaded from
  the dispatch) to resolve sense destinations.

## Verification

- **Unit** (`test_chat_helpers` 92 → 94): `_know_sense_label` formatting.
- **Integration**: `/learn` a `virus|causal|infection` triple, then `/knowledge
  infection` shows `implied by: virus, fever` (the learned edge + a seed edge),
  `senses: reasoning/infection`, and `(2 out, 3 in)`; `/knowledge virus` shows
  `(2 out, 0 in)`. Chat builds; `test_chat_helpers` passes.

## Consequences / scope

- `/knowledge` now shows the full local neighbourhood of a word — out-edges,
  in-edges, and the lexical→concept senses — in one read-only view, which is the
  natural place to inspect what `/save` persists and to debug the learning
  pipeline.
- A sense's destination KG is found by label (the atom's stored KG identity is
  its label, not a numeric id); a dangling sense (GC'd destination) is skipped
  rather than shown blank.
- Still only the *direct* neighbourhood (one hop out, one hop in) and the word's
  own senses; multi-hop context, per-edge confidence, and incoming-edge sources
  broken out separately are future refinements.
