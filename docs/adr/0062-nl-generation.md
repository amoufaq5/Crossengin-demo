# ADR-0062: NL generation quality (NL_AND_COVERAGE N4)

## Status

Proposed

## Date

2026-06-11

## Context

The agent stores facts as (subject, relation, object) operator atoms and reasons
in chains over them, but it *spoke* them as terse fragments with underscored
labels, no articles, and no subject-verb agreement ("rain->flood",
"the_sun is_a star"). N4 adds a generation layer that renders the same facts and
chains as fluent English.

## Decision

A new pure module `src/language/nl_generate.nova` (depends only on the `ROP_*`
relation-kind constants), shallow + deterministic per the no-LLM invariant:

- **Word helpers** — `nlg_phrase` (underscore→space), `nlg_cap` (first-letter
  capitalisation via `chr`), `nlg_indef_article` (a/an by leading vowel),
  `nlg_is_plural` (single trailing 's', excluding ss/us/is), `nlg_pluralize`
  (-y→-ies, sibilant→-es, else -s).
- **Single-fact clauses** — `nlg_clause(subject, kind, object)` renders each
  relation kind with article + number agreement: is_a → "rain is a liquid" /
  "dog is an animal" / "dogs are animals" (plural subject pluralises the object);
  causal → "rain leads to flood" / "clouds lead to rain"; analogy → "is like";
  opposite → "is the opposite of". `nlg_fact_sentence` capitalises + terminates.
- **Coordination** — `nlg_object_list` is an Oxford-comma list ("water,
  sunlight, and soil"); `nlg_clause_multi` renders a coordinated object
  ("rain leads to flooding and erosion"), the natural surface for N3's `coords`.
- **Chains** — `nlg_chain` / `nlg_chain_sentence` render a forward chain
  ("Morning leads to breakfast, which leads to energy.").

**Tie-in to the chat reply path.** The N1 NL-question bridge (`nl_query.nova`)
now builds its answer text with `nlg_clause` instead of a bare `subj phrase obj`
fragment, so every answer the bridge returns is article- and agreement-correct
and de-underscored. Because the generator's spellings match the cognitive
router's existing relation phrasing, the bridge's expected outputs were already
the fluent forms — the swap kept `test_nl_query` green unchanged.

## Consequences

- `test_nl_generate` (35 checks) covers the helpers, every relation kind,
  pluralisation/agreement, sentence capitalisation, Oxford lists, and chains.
- `nl_query` is wired through the generator (its 55 checks still pass), giving the
  NL Q&A path fluent output as the first concrete consumer.

## Honest gaps

- **Article heuristic is spelling-based**, not phonetic: "an hour" / "a unicorn"
  / "an x-ray" are mis-articled. A small exception list would fix the common
  cases.
- **Pluralisation is naive** (no irregulars: "mouse"→"mouses", "person"→
  "persons"); good enough for agreement display, not for a lexicon.
- **The legacy cognitive router still uses its own `_cr_render_chain`/
  `_cr_single_triple` fragments.** Routing those through `nl_generate` would touch
  the large router suite's asserted strings, so it is a deliberate follow-up; N4
  ties into the newer, self-contained NL bridge instead, where the swap is
  provably safe.
- **No tense/aspect or determiner choice for the subject** (always bare/"the"-
  free): "the sun" only because the label carried it.

## Implementation Notes

- New files: `src/language/nl_generate.nova`, `tests/unit/test_nl_generate.nova`.
- Modified: `src/language/nl_query.nova` (renders answers via `nlg_clause`).
- This completes the NL_AND_COVERAGE N-track (N1–N4) and the C-track (C1 done
  pre-session, C2 this session).
