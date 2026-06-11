# ADR-0061: OpenIE depth — negation, coordination, coreference (NL_AND_COVERAGE N3)

## Status

Proposed

## Date

2026-06-11

## Context

`openie.nova` discovered a single (subject, predicate, object) skeleton per
sentence with prepositional n-ary tails, but three common constructions were
lost: **negation** was silently dropped (a precision guard returned 0),
**coordinated objects** ("X has A and B") kept only A, and a **pronoun subject**
("It is hot") anchored to nothing. N3 deepens the extractor on all three while
keeping precision (garbage triples still poison the KG).

## Decision

`oie_fact` gains two fields — `polarity` (+1/-1) and `coords` (a list of extra
coordinated objects) — with new accessors `oie_polarity`, `oie_coords`,
`oie_is_negated`. The first four fields (subject/predicate/object/args) keep
their indices, so every existing caller (`openie_triples`, `learn_pipeline`,
`autonomous_loop`) is untouched.

- **Negation → polarity, not a drop.** A `not`/`no`/`never` between the verb/aux
  and the object sets `polarity = -1` and the extraction *continues*: "The sky is
  not blue" now yields `(sky, is_a, blue, polarity=-1)` instead of nothing. The
  aux hand-off steps across the negation, so "Mosses do not require sunlight" →
  `(mosses, require, sunlight, -1)`. **KG safety is preserved**: `openie_triples`
  emits *no* positive triple for a negated fact, so the ingest path can never
  assert the opposite of the text — the polarity is carried on the fact for a
  consumer that wants to record the negation explicitly.
- **Coordination split.** After the primary object, a run of `and`/`or`
  conjuncts is collected into `coords`; `openie_triples` emits one `(S, R, O)`
  per coordinated object. "The cell contains a nucleus and mitochondria" → two
  triples.
- **Pronoun coreference.** `openie_extract_ctx(sentence, prev_subject)` adopts a
  leading subject pronoun (it/they/he/she/…) as the previous sentence's subject;
  `openie_run` threads the last subject across sentences. "The Sun is a star. It
  is hot." → both facts have subject `sun`. (`openie_extract` is now a thin
  wrapper passing no antecedent, so the standalone single-sentence API is
  unchanged.)

## Consequences

- `test_openie` grows from 31 to 64 checks: the former `test_negation_rejected`
  (asserted 0) becomes `test_negation_polarity` (asserts the carried fact +
  negative polarity + zero positive triples), plus new coordination,
  three-way-coordination, coreference, and positive-default suites.
- Reverse-dependency tests stay green (`test_learn_pipeline` 21,
  `test_pdf_text` 18, `test_autonomous_loop` 13): they consume only
  `openie_triples`, whose contract for positive facts is unchanged.

## Honest gaps

- **Comma coordination merges.** The tokenizer drops punctuation, so "A, B and C"
  splits only at the explicit `and` (A_B becomes one NP, then C). Only `and`/`or`
  conjuncts are split; serial commas are a follow-up.
- **Pronoun resolution is shallow.** Only a *leading* subject pronoun resolves,
  and always to the immediately-previous sentence's subject (no gender/number
  agreement, no object-position anaphora, no salience ranking). Matches the
  bounded R75 anaphora style.
- **Negation scope is local.** Only a negation adjacent to the verb/aux or at the
  object head is caught; "not only X but Y" and constituent negation deeper in
  the object NP are out of scope.
- **Verb recall unchanged.** A verb the heuristic doesn't know ("eat") is still
  not discovered as a predicate; N3 didn't widen the verb lexicon.

## Implementation Notes

- Modified: `src/learning/openie.nova` (fact shape + `openie_extract_ctx` +
  `openie_triples`), `tests/unit/test_openie.nova`. No new module.
- Next on `NL_AND_COVERAGE.md`: N4 — NL generation quality.
