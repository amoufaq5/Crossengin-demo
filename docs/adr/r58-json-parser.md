# R58: A real JSON parser (cleaner OpenSearch + a dictionary-API source)

## Status

Accepted — R58 round (the "n" enhancement). Adds a recursive-descent JSON parser
and uses it to harden the OpenSearch resolve and to unlock a structured
dictionary-API source (`/define`).

## Date

2026-06-09

## Context

R55 parsed the OpenSearch response by scanning for the first `https://` — fragile
(a URL inside a *description* or a `sourceUrl` could be picked instead of the
article) and unable to navigate structured data at all. Richer JSON sources need
real structure: the free dictionary API (`api.dictionaryapi.dev`, verified
reachable, http 200) returns
`[ {.."meanings":[ {"partOfSpeech":..,"definitions":[ {"definition":..} ]} ]} ]`,
which a string scan can't walk.

## Decision

Add `src/data/json.nova`, a single-pass recursive-descent JSON parser:

- Tagged values `[tag, payload]` for null / bool / number / string / array /
  object / **err**. A mutable cursor `[pos]` is threaded through the parsers;
  arrays and objects recurse mutually. Malformed input yields `JV_ERR` (which
  propagates through array/object parsing) rather than crashing or looping —
  every step advances the cursor or stops.
- Strings take a fast O(n) `substr` of the whole span in the no-escape common
  case, and fall to a char-by-char decoder only when a backslash is present
  (handling `\" \\ \/ \b \f \n \r \t` and `\uXXXX` → UTF-8 BMP); raw UTF-8 bytes
  pass through untouched.
- Accessors: `json_type` / `json_str` / `json_num` / `json_bool`,
  `json_arr_get` / `json_arr_len`, `json_get` / `json_has` — all total (a
  wrong-type access returns `JV_ERR` / a default, never crashes).

Then put it to work:

- `research_first_url` now parses the OpenSearch JSON and reads the URL array
  (index 3, element 0), so a `https://` spoofed in a description is ignored.
- `dict_api_url` + `dict_definitions` (pure) navigate the dictionary-API shape to
  `[partOfSpeech, definition]` pairs.
- The chat's **`/define WORD`** `lp_fetch`es the dictionary JSON, parses it,
  prints the definitions, and **ingests the definition prose as knowledge**
  (`src:dict:WORD`) — the parser unlocking a typed API where `/learn`
  HTML-scrapes prose.

## Verification

- **Unit** (`test_json`, 47): primitives; escapes incl. `\uXXXX` → UTF-8;
  arrays, objects, and deep nesting matching the dictionary shape; the OpenSearch
  shape; and errors (garbage, unterminated string/array, missing colon, empty)
  plus safe wrong-type access. `test_research_sources` 33 → 41:
  `research_first_url` now ignores a description-spoofed URL, and
  `dict_definitions` extracts pairs and returns empty for a 404 object / garbage.
  `learn_pipeline` (10), `preprocess` (99), `cognitive_router` (17), `word_atoms`
  (83) pass.
- **Live**: `/define serendipity` → two noun definitions printed and 19 words
  learned; `/research dna` → the JSON-parsed OpenSearch resolves the acronym to
  `…/DNA` (103 operators). Chat builds.

## Consequences / scope

- The agent can now read typed JSON APIs without HTML scraping — the dictionary
  today, and search / weather / knowledge-graph APIs later — and the OpenSearch
  resolve is hardened against a spoofed URL.
- **Numbers** are stored truncated to int (raw token kept alongside). NOVA has no
  native float, so fractional JSON numbers lose their fraction — fine for
  navigation / counts, a limit for numeric-heavy APIs.
- `\uXXXX` **surrogate pairs** (astral-plane / emoji) emit `?`; the BMP is
  covered. Deeply nested JSON recurses without a depth cap — the sources here are
  shallow, but a pathological document could deep-recurse (future hardening).
- `/define` ingests definitions through the same preprocess + ingest path as
  `/learn`, so they become first-class knowledge attributed to `src:dict:WORD`.
