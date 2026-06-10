# R62: Deverbal morphology (-tion/-sion via a curated lemma table)

## Status

Accepted — R62 round (the "r" enhancement). Adds the -tion / -sion / -ation
deverbal-noun family to `word_find_morph` via a curated lemma table — the cases
R57 deliberately omitted as too irregular to strip.

## Date

2026-06-09

## Context

R57 added derivational morphology (-al, -ly, -ness, -ment, -ful, -ous, -ic,
-ist, -ity) but explicitly left out the -tion / -sion / -ation family: its stem
changes are too irregular for a safe strip rule. The danger is over-stemming —
"creation" → "create" needs -ion→-e, but the same -ion→-e turns "station" →
"state" (a real, unrelated word that the accept-only-if-known guard can't catch,
since "state" is genuinely a known concept). A rule can't tell deverbal "station"
(none) from "creation" (create). A **table** can.

## Decision

Add `deverbal_lemma(form)` (`src/language/word_atoms.nova`), mirroring R54's
`irregular_lemma`: a curated table mapping ~95 common deverbal nouns to their
base verb/adjective explicitly (creation → create, decision → decide, production
→ produce, admission → admit, information → inform, description → describe,
conclusion → conclude, …), returning "" otherwise. `word_find_morph` consults it
in the derivational tier (after inflection, before the generic R57 strip rules,
since the table is higher precision), accepting the base **only if it is itself a
known atom**.

Two safety properties make this clean where a rule couldn't be:

- **Non-deverbal -tion/-sion words are simply absent** from the table — "station",
  "nation", "condition", "mission" map to nothing, so they're never remapped.
  This is the property a strip rule fundamentally can't have.
- **Accept-only-if-known** (the standing invariant): a listed noun whose base
  isn't learned misses, so the table never invents a concept.

## Verification

- **Unit** (`test_word_atoms` 87 → 108): the raw table (creation → create,
  decision → decide, production → produce, admission → admit, information →
  inform, …; and station/nation/mission → ""), plus end-to-end through
  `word_find_morph` (8 deverbal nouns reach their seeded base) with the
  load-bearing safety case — "station" does **not** reach "state" *even with
  "state" seeded* (the table doesn't list it), and "reduction" misses when
  "reduce" isn't learned. `cognitive_router` (21) and `reader` (13) pass.
- **Integration probes** (au_ingest-created base + full seed + a dict-definition
  ingest + the router): `router_reply(CAT_ACADEMIC, "what is decision", …)`
  surfaces the base's gloss via the deverbal hop ("decision means: …"),
  confirming the table threads through the reader-anchor + router path the chat
  uses.

## Consequences / scope

- Academic free text — dense with -tion/-sion nouns — now reaches the base verb
  it derives from, completing the morphology stack (R49 regular inflection → R54
  irregular inflection → R57 derivation → R62 deverbal).
- A curated table, ~95 high-frequency entries: comprehensive enough for common
  text, not a full nominalization dictionary. Unlisted deverbal nouns simply
  don't map (safe by omission). New entries are one line each.
- The table is the right tool precisely because the transformation is
  many-to-one-irregular (-ation→-ate / -e / strip / -ize; -sion→-de / -se / -d /
  -t) and the noun/verb ambiguity (station vs creation) defeats any single strip
  rule — exactly why R57 deferred it.
