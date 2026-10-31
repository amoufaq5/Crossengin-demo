# R67: A first-class ROP_OPPOSITE relation for antonyms

## Status

Accepted — R67 round (the "w" enhancement). Antonyms get their own reasoning
relation, `ROP_OPPOSITE`, and a surface — "X is the opposite of Y" — instead of
R66's pragmatic ROP_ANALOGY-tagged-`:ant` placement.

## Date

2026-06-09

## Context

R66 linked dictionary antonyms with `ROP_ANALOGY` (the "is like" kind) tagged
`:ant->` in the label, because there was no opposite relation. The router then
had to *skip* those tagged edges so it wouldn't say "happy is like sad". The
antonym was in the graph but semantically mislabelled (an analogy of opposites)
and never surfaced.

## Decision

- **`ROP_OPPOSITE = 5`** (`src/parts/reasoning/reasoning_atoms.nova`), with
  `rop_kind_name` → "oppositional". It is a non-chaining kind (like analogy), so
  the forward-chain never walks through an opposite.
- **`_dict_link_related`** now takes the operator `kind`: synonyms link with
  `ROP_ANALOGY`, antonyms with `ROP_OPPOSITE` (still labelled `…:ant->TERM` for
  provenance).
- **Router**: `_cr_rel(ROP_OPPOSITE)` → "is the opposite of"; `_cr_related_of(kg,
  percept, kind)` generalises the R66 finder over a kind; `_cr_single_triple`
  skips both analogy and opposite ops (their dedicated surfaces handle them).
  `_cr_academic` / `_cr_unknown` prefer a **synonym** ("X is like Y") and
  otherwise surface an **antonym** ("X is the opposite of Y"), each with its own
  trace (`analogy (synonym)` / `opposite (antonym)`), before the gloss.

## Verification

- **Unit** (`test_cognitive_router` 25 → 29): with both a synonym and an antonym
  edge, the synonym is preferred ("decision is like choice", the antonym not
  surfaced); with only an antonym edge, "happy is the opposite of sad" (trace
  `opposite (antonym)`, op recorded); `rop_kind_name(ROP_OPPOSITE)` ==
  "oppositional". `reasoning_atoms`, `reader`, `research_sources` pass, and
  `snapshot_disk_full` (89) confirms the new kind round-trips through R51's
  operator serialization (op kind is just an int).
- **Integration**: defining a word mints `ROP_OPPOSITE` antonym edges; a word
  with an antonym but no synonym/chain answers "X is the opposite of Y". Chat
  builds.

## Consequences / scope

- Antonyms are now first-class: correct relation kind, a human surface, and a
  distinct trace `/why` can cite. The synonym-preferred ordering keeps "what is
  X" informative (similarity over opposition) while still making opposition
  reachable.
- `ROP_OPPOSITE` persists across a restart for free (R51 serializes any operator
  by its `op`/`premise`/`conclusion` payload; the kind is just `5`), and the
  edges survive `/save` + `/load` like the genus and synonyms.
- The relation is undirected in meaning (opposite is symmetric) but stored as a
  single directed edge headword → antonym; the reverse is implied. A symmetric
  store (both directions) and opposite-aware inference (X true ⇒ its opposite
  less likely) are future work.
