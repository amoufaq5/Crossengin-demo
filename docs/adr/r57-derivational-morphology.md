# R57: Derivational morphology (the part-of-speech layer past inflection)

## Status

Accepted — R57 round (the "m" enhancement). Adds derivational morphology to
`word_find_morph` so part-of-speech-changing forms (national → nation,
biological → biology, happiness → happy, quickly → quick) reach the learned base
atom, the layer past R49/R54's inflection.

## Date

2026-06-09

## Context

R49 (regular suffixes) and R54 (irregular lemma table) made *inflected* free text
recall its base — plurals and verb tenses. Both explicitly stopped short of
*derivation*: "national", "biological", "happiness", "quickly" still missed the
learned "nation" / "biology" / "happy" / "quick". Derivation is harder than
inflection because it changes part of speech and usually spelling, and the rules
are noisy — over-stemming ("final" → "fin", "topic" → "top", "only" → "on") is
the classic failure mode a naive stemmer falls into.

## Decision

Add `derive_candidates(form)` (`src/language/word_atoms.nova`, pure): given a
normalized form, return the candidate base strings a common derivational suffix
could have come from, with the usual spelling-change variants —

- `-al` / `-ical` → strip / +e / →-y (national → nation, cultural → culture,
  musical → music, biological → biology);
- `-ly` / `-ily` (quickly → quick, happily → happy);
- `-ness` / `-iness` (darkness → dark, happiness → happy);
- `-ment` (government → govern, movement → move);
- `-ful` / `-iful` (helpful → help, beautiful → beauty);
- `-ous` (dangerous → danger, famous → fame);
- `-ic` → strip / →-y (atomic → atom, historic → history);
- `-ist` → strip / →-y (artist → art, biologist → biology);
- `-ility` → -le (ability → able, visibility → visible);
- `-ity` → strip / +e (complexity → complex, activity → active).

`word_find_morph` tries these **last** — after the exact match, the irregular
table, and the regular inflection rules — so plurals/tenses always win first.

**Two layers of safety against over-stemming:**

1. **Per-suffix minimum-length guards** so short stems are never even proposed:
   "final" (n=5) proposes no `-al` strip, "only" (n=4) no `-ly` strip, "topic" /
   "logic" / "music" no `-ic` strip. This is where over-stemming bites, so the
   bad candidate is never generated in the first place.
2. **Accept-only-if-known** (the R49 invariant): a proposed base is taken ONLY
   if it is itself a known atom, so derivation never invents a concept.

## Verification

- **Unit** (`test_word_atoms` 54 → 83): candidate generation (national → nation,
  biological → biology, ability → able, historic → history; a base word proposes
  nothing; "final" never proposes "fin", "only" never proposes "on"); 16
  end-to-end derivations through `word_find_morph`; and safety — "kindness"
  misses when "kind" isn't learned, and "final"/"only" do **not** over-stem to
  "fin"/"on" **even when those are seeded** (the length guard, not just the
  known-check, blocks them). `lexical_anchor` (27), `cognitive_router` (17),
  `reader` (13) pass.
- **Live**, through the reader: `/teach nation`, then "national" →
  `perceive(m=1,unk=0)` (resolved to nation); nonsense "froobly" →
  `perceive(m=0,unk=1)` ("i don't know 'froobly'"). Chat builds.

## Consequences / scope

- Derived free text now reaches the base concept, and inflection still takes
  precedence (derivation is the last resort). Combined with R49/R54, the common
  inflectional + derivational forms a user types now recall learned knowledge.
- Derivation is **approximate by nature**: "business" → "busy" is etymological,
  not semantic, and "signal" → "sign" relates two distinct concepts. The
  length guards + accept-only-if-known keep over-stemming in check, but they
  can't make derivation meaning-exact — a derived hit is a best-effort link to a
  related concept, not a guarantee of synonymy.
- English suffix heuristics only. The `-tion` / `-sion` / `-ation` family
  (creation → create, decision → decide) is deliberately omitted — its spelling
  changes are too irregular for a safe strip rule — as is derivational chaining
  (nationalism → nation). Those want a real lemma dictionary, future work.
