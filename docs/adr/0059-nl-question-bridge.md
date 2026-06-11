# ADR-0059: NL question → structured KG answer (NL_AND_COVERAGE N1)

## Status

Proposed

## Date

2026-06-11

## Context

The reasoning KG already stores everything the agent knows as operator atoms
(premise `-RELATION->` conclusion, each carrying a Bayesian belief;
`src/parts/reasoning/reasoning_atoms.nova`). The cognitive router can *forward-
chain* over those edges, but there was no first-class path from an English
*question* to a targeted lookup and back to a confidence-qualified answer — the
keystone the NL track is built around. N1 adds that bridge.

## Decision

A new pure module `src/language/nl_query.nova`, three shallow heuristic steps —
no parser, no LLM, gradient-free and auditable, the project's no-LLM-cognition
invariant intact:

1. **Classify** the question form — `nlq_classify`: yes/no (leading
   is/are/does/can/…), or wh- (what / who / where / when / why / how /
   how-many). The "how many"/"how much" bigram is split out from bare "how".
2. **Extract** the focus entity (and, for yes/no, subject + object) plus a
   relation kind, by scanning tokens against small curated word sets — the same
   shallow style as `openie.nova`. Relation keywords (cause(s)/lead(s),
   means/implies, like/similar, opposite) map onto the four operator kinds;
   determiners, question words, copulas, prepositions and light filler verbs
   ("happen", "occur", "work") are skipped from the focus noun-phrase.
3. **Look up + render** — resolve the focus with `er_resolve` (exact + alias,
   ADR-0053), then walk the operators leaving (or, for "why"/"what causes X",
   *entering*) the resolved atom:
   - `nlq_answer_what` — the strongest relation leaving the focus, preferring an
     is_a edge for a bare "what is X".
   - `nlq_answer_why` — the strongest causal edge whose conclusion is the focus.
   - `nlq_answer_yesno` — a yes/no backed by the matching edge; a direct OPPOSITE
     edge answers "no" for an is_a question but "yes" for an "is X the opposite
     of Y" question; the *absence* of an edge is an honest "i don't have that"
     rather than a guessed "no".
   - `nlq_answer_howmany` — the count of distinct conclusions under the relation.

   Every found answer is hedged by the backing operator's belief using the **R74
   weakest-link tiers** (`nlq_phrase`: ≥700 plain, 400–699 "i think", <400
   "tentatively,") so the agent's voice is consistent with the router, carries
   the operator id (so `/good`//`/bad` can re-weight the exact edge it leaned on),
   and is tagged with the source the edge came from (`nlq_source_tag`).

## Consequences

- "what is X" / "what causes X" / "is X a Y" / "is X the opposite of Y" / "how
  many things does X cause" are all answered from a seeded KG with provenance and
  a confidence hedge, unit-tested end to end (`test_nl_query`, 55 checks).
- The bridge returns a structured record (`[found, form, text, conf, op_ids,
  source]`), so the chat path can adopt it incrementally without changing the
  router's existing surfaces.
- No production module was modified; the new module is additive and behind no
  flag because it is read-only over the KG.

## Honest gaps

- **Single-edge answers.** Each answer rests on one operator (the strongest
  match); multi-hop "what is X" that needs a chain still belongs to the router's
  forward-chain. Composing the two is follow-up.
- **where/when are answered like what.** The KG stores spatial/temporal facts as
  OpenIE n-ary arguments (`discovered_in`, …) folded into composite-predicate
  operators, not as a distinct relation kind, so "where/when" currently surface
  the strongest relation rather than a dedicated place/time slot. A
  role-addressed lookup is N3/N4 territory.
- **HDC resolution is inert here.** `_nlq_resolve` passes an empty mention vector
  to `er_resolve`, so only exact + alias resolution fires; wiring the
  neighbourhood-vector path would let "the vehicle" resolve to "car" in HDC mode.
- **Not yet wired into the live chat router.** This ADR lands the bridge + tests;
  adopting it as a CAT_FACTUAL/CAT_ACADEMIC pre-pass in
  `cognitive_router.router_reply` is a deliberate, separately-tested follow-up so
  the existing routing suite is not perturbed.

## Implementation Notes

- New files only: `src/language/nl_query.nova`, `tests/unit/test_nl_query.nova`.
- Imports `reasoning_atoms.nova` (operators + KG API) and `entity_resolve.nova`
  (resolution); the diamond on `multi_kg_manager` dedupes cleanly.
- Next on `NL_AND_COVERAGE.md`: N2 — number-words & units → value.
