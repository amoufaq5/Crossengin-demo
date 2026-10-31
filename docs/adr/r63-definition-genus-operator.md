# R63: Link a defined word to its definition's genus (so it reasons)

## Status

Accepted — R63 round (the "s" enhancement). When a word is defined from the
dictionary, link it to its definition's **genus** with a reasoning operator, so a
defined word forward-chains (reasons) instead of only displaying its gloss.

## Date

2026-06-09

## Context

R60 autodefine learns a word's dictionary definition and stores the primary
definition as a gloss; the router answers "X means: …". But the headword was
never *linked* to the concepts in its definition — so "what is X" could recite
the gloss yet not reason about X. The encyclopedia path mints operators; the
dictionary path stopped at the prose.

## Decision

Extract the **genus** (the head of the definition's leading noun phrase — the
Aristotelian "kind") and add an implicative operator `headword -> genus`.

- `dict_genus(definition)` (`src/learning/research_sources.nova`, pure): skip
  leading articles / "to", collect content words until the first preposition /
  conjunction / clause-ending punctuation, and return the **last** one (the NP
  head): "a small rodent" → rodent, "a combination of events" → combination, "to
  bring into existence" → bring. The "act/process **of** X" frame skips the frame
  noun to X ("the act of choosing" → choosing).
- `_dict_learn` (chat): after ingesting the definition prose, take the genus of
  the primary definition, ensure the headword concept exists, and add
  `rop_new(ROP_IMPLY, headword, genus)` — but only when the **genus is itself a
  known concept** (it is, since the definition was just ingested) and differs
  from the headword. This runs for `/define`, autodefine (R60), and the research
  dictionary enrichment (R59) alike, since they share `_dict_learn`.

Because the academic strategy forward-chains over `ROP_IMPLY` edges, "what is X"
now follows `X -> genus -> …` — a chain the router prefers over the gloss
(the chain check precedes the gloss check), so a defined word reasons.

## Verification

- **Unit** (`test_research_sources` 43 → 52): `dict_genus` on the common shapes —
  NP head, adjective-then-head, verb definition, the-article, the act/process-of
  frame, conjunction and trailing-punctuation boundaries, and empty.
- **Integration**: a defined word gains a `headword -> genus` `ROP_IMPLY`
  operator; "what is X" forward-chains `X -> genus` (trace `academic:
  forward-chain`) rather than the gloss, and with R61 it answers in the same turn.
- Chat builds.

## Consequences / scope

- A defined word is no longer a dead-end gloss: it carries a reasoning edge to
  its genus, so it composes into chains (and, when the genus has further edges,
  longer ones). The dictionary path now contributes operators like the
  encyclopedia path does.
- Genus extraction is heuristic (no POS tagger): the NP-head rule handles
  "adjective + noun" and the "act/process of X" frame, but a leading
  "adjective, …" with a comma stops early ("a small, furry rodent" → small), and
  a definition with no clear head yields no link. These are accept-or-skip, never
  wrong-merge: the operator is only added when the genus is a known concept.
- One genus link per word (the primary sense). Multi-genus defs, synonym/antonym
  edges (the dict API also returns these), and a real parser are future work.
- The link is `ROP_IMPLY` ("X is-a genus"); it is attributed `src:dict:WORD:genus`
  so `/good` `/bad` can re-weight it and a future meta-loop can score the
  dictionary genus path.
