# R54: Irregular morphology (a lemma table lifts R49's regular-only limit)

## Status

Accepted — R54 round (the "j" enhancement). Adds an irregular lemma table to
`word_find_morph` so common irregular inflections (mice → mouse, ran → run,
leaves → leaf) reach the learned base atom, alongside R49's regular suffix rules.

## Date

2026-06-09

## Context

R49 made lexical recall inflection-tolerant with conservative regular English
suffix rules (plural -ies/-es/-s, verb -ing/-ed), each accepted only if the
stripped form is itself a known atom. Its stated limit: *"no irregulars
(mice → mouse, ran → run, leaves → leaf)…those need a lemma dictionary /
Porter-class stemmer."* So a user typing "mice", "ran", or "feet" missed the
learned "mouse" / "run" / "foot" — and worse, the regular rules actively
mislemmatize some irregulars: "leaves" ends in "-es", so the regular strip
reaches "leave" (a different concept) rather than "leaf".

## Decision

Add `irregular_lemma(form)` in `src/language/word_atoms.nova`: a curated table
mapping a known irregular inflection to its base form, returning "" when the
form isn't a listed irregular. It covers the common English irregular plurals
(mice, children, feet, geese, people, leaves, wives, …), the Latin/Greek
scientific plurals frequent in academic text (bacteria → bacterium, phenomena →
phenomenon, analyses → analysis, criteria → criterion, data → datum, nuclei,
fungi, indices, matrices, …), and the common irregular verbs in both past tense
and past participle (ran → run, ate/eaten → eat, took/taken → take, wrote/written
→ write, understood → understand, …). It is a small curated table, not a full
lemma dictionary.

`word_find_morph` consults it **right after the exact match and before the
regular suffix rules**, so:

- an irregular reaches its true base ("leaves" → **leaf**, beating the regular
  "-es" strip to "leave"); and
- the load-bearing **safety property is preserved**: the lemma is accepted ONLY
  if it is itself a known atom, so a listed mapping never invents a concept — it
  only reaches an existing one. "geese" with no learned "goose" stays unknown.

Exact match still wins over the table, so a form that is *itself* a learned atom
("saw" the tool, "left" the direction, "data" used as the base) resolves to
itself, not to a lemma.

## Verification

- **Unit** (`test_word_atoms` 33 → 54 checks): the raw table
  (`test_irregular_lemma_table`: mice→mouse, ran→run, leaves→leaf, children→child,
  bacteria→bacterium, analyses→analysis, understood→understand; non-irregulars
  and regular plurals → ""), and end-to-end through `word_find_morph`
  (`test_irregular_morph`): irregular plurals + verbs reach the learned base
  (including leaves→leaf beating the -es strip, and taken→take), while the safety
  cases miss (men with no "man", ate with no "eat"). Consumers pass:
  `lexical_anchor` (27), `cognitive_router` (17), `reader` (13).
- **Live**, through the reader: `/teach mouse`, then "mice" →
  `perceive(m=1,unk=0)` (resolved to mouse), whereas "geese" →
  `perceive(m=0,unk=1)` ("i don't know 'geese' yet" — goose not taught, so the
  accept-only-if-known guard holds). The unk-count contrast is the table + guard
  working through the anchor path.
- Chat builds.

## Consequences / scope

- Irregular plurals and verbs now reach learned concepts, and "leaves" no longer
  mis-lemmatizes to "leave". Inflected academic text (bacteria, phenomena,
  analyses) anchors to its base, which matters for the agent's research domain.
- Still a curated table, English-only: rare irregulars and derivational
  morphology (national → nation, biology → biological) aren't covered, and a
  genuinely open-ended lemmatizer would need a dictionary / Porter-class stemmer
  — deferred, as R49 noted. The table is the high-frequency 80% done safely.
- No false merges by construction: every path (exact → irregular table →
  regular rules) only ever returns an atom that already exists, and exact match
  shadows the table, so polysemous surface forms that are themselves concepts
  ("saw", "left", "rose") keep their own identity.
