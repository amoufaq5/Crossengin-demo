# R64: Cite knowledge sources in /why

## Status

Accepted — R64 round (the "t" enhancement). `/why` now lists the distinct
knowledge sources behind the last answer's reasoning ("sources: Wikipedia,
dictionary").

## Date

2026-06-09

## Context

Every operator the agent learns is attributed at mint time with a `src:` prefix
on its label — `src:url:en.wikipedia.org:…`, `src:dict:WORD:…`,
`src:topic:TAG:…` — and a reply records the operator ids it leaned on
(`_last_reason_ops`, used by `/good` `/bad`). But `/why` explained *the decision*
(tier, outcome, trace size) without ever saying **where the knowledge came
from**. The provenance was in the labels, unsurfaced.

## Decision

- `src_label_name(label)` (`src/chat/helpers.nova`, pure, unit-tested): map an
  operator label to a human source — `src:url:` hosts to "Wikipedia" / "Simple
  Wikipedia" / "Wiktionary" / "dictionary" (else the bare host), `src:dict:` to
  "dictionary", `src:topic:` to "a learned topic", and a bare seed/unlabeled
  operator to "prior knowledge".
- `_why_sources(kg, ops_csv)` (chat): walk the last reply's operator ids, look up
  each operator's label, map it to a source, and join the **distinct** names.
- `_admin_why` prints a `sources :` line when the reply leaned on learned
  operators.

## Verification

- **Unit** (`test_chat_helpers` 79 → 87): `src_label_name` over a Wikipedia URL,
  Simple Wikipedia, Wiktionary, a dictionary ingest, the dictionary genus
  (R63), a learned topic, a bare seed label ("prior knowledge"), and an
  unknown host (kept verbatim).
- **Integration**: after an answer that forward-chains over learned operators,
  `/why` prints e.g. `sources : a learned topic, prior knowledge`; after a
  research-backed answer, `Wikipedia`; after an autodefine genus chain,
  `dictionary`.
- Chat builds.

## Consequences / scope

- The agent can now say *where* an answer came from, not just *that* it reasoned
  — the provenance that was always in the operator labels is finally legible, and
  cross-sourced answers (R59: encyclopedia + dictionary) show both.
- Sources are aggregated from exactly the operators the reply used, so they track
  the actual reasoning path (not the whole KG). A reply that leaned on no learned
  operators (a pure gloss, a social reply) shows no sources line.
- Names are coarse ("Wikipedia", "dictionary") rather than the specific article /
  page — the label keeps the full `src:…:S-rel->O` detail, so a future `/why-deep`
  or meta-loop can surface the exact triple and page. Per-source confidence /
  corroboration scoring (ADR-0029 `source_authority`) is the natural next layer.
