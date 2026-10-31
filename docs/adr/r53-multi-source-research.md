# R53: Multi-source, disambiguation-aware research

## Status

Accepted — R53 round (the "i" enhancement). Replaces R50's single-guess research
URL with an ordered sweep over multiple source candidates, so the agent isn't
pinned to one Wikipedia-title guess on one host.

## Date

2026-06-09

## Context

R50's `_ar_wiki_url` made exactly one guess: the English-Wikipedia article at the
topic's capitalized title. Two failure modes ended the search with nothing
reasoned:

- **Acronyms.** A short lowercase token ("dna", "rna") capitalizes to "Dna" /
  "Rna". Wikipedia resolves the *first* letter case-insensitively (so "Dna"
  happens to reach "DNA"), but multi-letter initialisms and true title
  mismatches don't, and the in-engine TLS client follows no redirects.
- **Disambiguation stubs.** When the capitalized title is a disambiguation page
  (a list of links, almost no prose), the ingest learns words but ~zero
  reasoning operators — so the agent "researched" the topic yet still can't
  reason about it, and there was no fallback to a better page.

A single guess that lands on a stub, an acronym redirect, or a 404 was the end
of the road.

## Decision

Split the URL logic into a pure, unit-tested module and make the fetch loop
sweep multiple sources.

- **`src/learning/research_sources.nova`** (pure, no IO): `research_candidates(topic)`
  returns an ORDERED list of `[source_label, url]`:
  1. `en.wikipedia` — the canonical capitalized title;
  2. `en.wikipedia/acronym` — the UPPER-case title, but only for short (<= 5
     char) tokens and only when it differs from the capitalized form (so "dna"
     also offers ".../DNA", but "photosynthesis" gets no spurious all-caps URL);
  3. `simple.wikipedia` — Simple-English Wikipedia on a **different host**, whose
     articles are shorter and far less likely to be disambiguation pages.
  Plus `research_cap_first`, `research_wiki_path` (spaces → underscores so a
  multi-word topic still forms a valid title), and `research_is_strong(ops,
  min_ops)` so the strength threshold is one knob.
- **`_research_topic`** now sweeps the candidates: fetch each in order, **stop at
  the first "strong" result** (>= `_research_min_ops`, default 3, overridable via
  `CE_RESEARCH_MIN_OPS`), otherwise fall through to the next SOURCE and keep the
  best. Because every `learn_from_url` ingest is idempotent by label, the sources
  we do fetch reinforce + extend knowledge rather than duplicating it.

**Cost is paid only on weak pages.** A real article on the first source is still
ONE fetch — the sweep continues only past a weak/failed candidate. So real topics
incur no extra latency; only stubs/misses fetch more.

## Verification

- **Unit** (`test_research_sources`, 22 checks): canonical-first ordering, the
  acronym UPPER variant present for short tokens and absent for long ones,
  the simple-wikipedia fallback always present, spaces → underscores for
  multi-word titles, every URL https, empty topic → no candidates, and the
  strength threshold boundaries (>=, <, inclusive).
- **Live**:
  - `/research photosynthesis` → `en.wikipedia` strong (68 operators) → **stops
    at one fetch** (acronym + simple-wiki never tried).
  - `/research zqxk` (nonsense) → sweeps all three: `en.wikipedia` (1 op, weak)
    → `en.wikipedia/acronym` (ZQXK) → `simple.wikipedia` (**different host,
    reachable through the gateway**), all weak → keeps the best and reports it.
    This exercises the full fall-through and confirms a second host is live.
  - Autonomous + same-turn (R50 + R52): `CE_AUTORESEARCH=1`, "what is
    photosynthesis" → multi-source research then answers **in the same turn**
    (`photosynthesis -> process -> translocated`).
- research_sources unit + chat build; cognition suites unaffected (the change is
  isolated to the research path).

## Consequences / scope

- Research is no longer pinned to one title guess on one host: a disambiguation
  stub, an acronym, or a missing article falls through to the next source, and a
  genuinely different host (Simple-English Wikipedia, verified reachable) gives a
  second opinion.
- Wikipedia resolves first-letter case server-side (Dna → DNA as a 200), so the
  acronym variant mostly earns its keep on multi-letter initialisms and true
  404s. It's cheap (tried only when the canonical guess was weak) and defensive.
- **Tradeoff**: a nonsense/missing topic now ingests the not-found page from up
  to 3 sources (~150 words each) before reporting failure — bounded junk,
  idempotent by label, and only on topics that have no real article. Real topics
  are unaffected (one fetch).
- Source diversity is still Wikipedia-family (en + simple). Genuinely independent
  sources (other encyclopedias, dictionaries) and a real search / disambiguation
  API are future work. R50's one-topic-per-turn rate limit still holds; the
  per-topic sweep is bounded at 3 candidates.
