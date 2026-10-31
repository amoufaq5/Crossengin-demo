# R55: Real search/disambiguation + a genuinely independent source

## Status

Accepted — R55 round (the "k" enhancement). Adds a real search step (Wikipedia's
OpenSearch API) that resolves a topic to its canonical article instead of
guessing the title, and a genuinely independent source (the Wiktionary
dictionary) to the research sweep.

## Date

2026-06-09

## Context

R53 made research multi-source, but every candidate was a Wikipedia-family title
**guess** (capitalize, upper-case acronym, Simple-English). A guess fails on:

- **typos** ("phtosynthesis" → a 404 at the guessed title);
- **casing / plural-singular** mismatches ("mitochondria" → the article is
  "Mitochondrion"; "dna" → "DNA");
- **disambiguation** (the guessed title is a stub list).

And the only "independent" source, Simple-English Wikipedia, is still Wikimedia.

## Decision

Three changes:

1. **Raw fetch primitive.** Extract `lp_fetch(url, now)` from `learn_from_url`
   (DNS + fetch gate + TLS 1.3 / HTTP), returning `[status, http_code, body,
   message]` — the raw body, with NO preprocess/ingest. `learn_from_url` now
   builds on it. This lets the agent read a response (a search result) without
   learning it as facts.

2. **Real search / disambiguation** (`src/learning/research_sources.nova`,
   pure): `research_search_url(topic)` builds the Wikipedia OpenSearch API URL
   (`action=opensearch&limit=1&namespace=0`); `research_first_url(body)` parses
   the canonical article URL out of the JSON `[query,[titles],[descs],[urls]]`
   with a plain string scan (no JSON parser). The chat's
   `_research_search_resolve` fetches it raw and parses it, and `_research_topic`
   **leads the candidate sweep with the resolved URL** (`en.wikipedia/search`).
   Wikipedia's own resolver corrects typos, casing, acronyms, and plural/singular
   and disambiguates server-side.

3. **A genuinely independent source.** Add Wiktionary (`en.wiktionary.org`) to
   `research_candidates` — a **dictionary** (definitions / etymology), not an
   encyclopedia, so a different content type and a real second opinion. Verified
   reachable through the gateway (http 200, ~493 words). It's the deep fallback
   for terms OpenSearch can't match. (Britannica was probed and returns 403 to
   the in-engine client — bot detection — so it's excluded.)

## Verification

- **Unit** (`test_research_sources` 22 → 33): the OpenSearch URL + `%20` query
  encoding, the JSON parse (canonical, typo-corrected, acronym, empty-result,
  and garbage → ""), and the Wiktionary candidate's presence.
  `test_learn_pipeline` still passes (10 — the refactor is behavior-preserving);
  `preprocess` (99) and `cognitive_router` (17) pass.
- **Live**:
  - `/research photosynthesis` → `search resolved … -> …/Photosynthesis`, one
    strong fetch (68 operators).
  - `/research phtosynthesis` (**typo**) → search **corrects** it to
    `…/Photosynthesis` and learns the real article — where a title guess would
    404.
  - `CE_AUTORESEARCH=1`, "what is mitochondria" → search resolves the **plural**
    to the singular article `…/Mitochondrion` (129 operators) and the **same
    turn** (R52) answers `mitochondria -> double_membrane`.
- Chat builds.

## Consequences / scope

- Research resolves the canonical article via a real search rather than guessing
  the title: typos, casing, acronyms, and plural/singular are handled by
  Wikipedia's resolver. Cost is one small search fetch + one article fetch in the
  common case (the search JSON is tiny).
- **OpenSearch is aggressive** — it fuzzy-matches almost any token (even nonsense:
  "zqxk" → some tangential article) to *something*, so the search result usually
  wins and Wiktionary fires only when OpenSearch returns nothing. A consequence:
  a typo'd or nonsense token may now learn a tangential article instead of
  failing — bounded, idempotent by label, and the autonomous trigger fires on
  real words, so this is rare in practice.
- `lp_fetch` is now a reusable raw-fetch primitive (DNS + gate + TLS), useful for
  future non-learning fetches (search, sitemaps, robots.txt).
- Independent-source diversity beyond Wikimedia is still limited to Wiktionary:
  Britannica 403s the in-engine client, and JSON-API dictionary sources would
  need a real JSON parser — future work.
