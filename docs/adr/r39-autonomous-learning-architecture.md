# R39: Autonomous learning architecture (trigger -> research -> preprocess -> ingest)

## Status

Accepted -- R39 round wiring of pre-existing ADR primitives into an end-to-end
self-directed learning path.

## Date

2026-06-06

## Context

CrossEngin's headline capability is continuous, self-directed learning. The
substrate ADRs already specify each piece in isolation:

- **ADR-0026** (self-learning triggers) names five impulse sources --
  `SLT_USER_REQUEST`, `SLT_PREDICTION_ERROR`, `SLT_UNKNOWN_QUERY`,
  `SLT_IMAGINATION_GAP`, `SLT_CURIOSITY` -- and arbitrates them into a
  single learning episode.
- **ADR-0028** (internet fetching) specifies a whitelisted,
  rate-limited, validated, audited, cached fetch path. NOVA enhancement
  #11 supplies the outbound HTTP. The shipping `src/learning/internet_fetch.nova`
  exposes `if_permit` -> `if_transport_get` -> `if_ingest` with the
  `FETCH_*` and `IF_TRANSPORT_*` tags.
- **ADR-0029** (source authority weighting) assigns Tier A/B/C to
  every source and gates conflict resolution and Bayesian increments
  on the tier plus a per-domain recency policy.

Through R38 these pieces are **separately implemented and unit-tested,
but not wired together end-to-end inside the live chat agent**. A user
typing a word the agent does not know goes through the perceive stage
and surfaces as an unknown atom, but no actual learning episode is
queued, no fetch goes out, and no new knowledge is ingested. This was
acceptable while the safety-critical pieces (whitelist, rate limit,
validate, audit) were being landed; it is no longer acceptable now
that the substrate is otherwise complete.

R39 wires them.

## Decision

R39 lands four code modules (R39A/B/C/D/F) that together compose the
autonomous learning loop, with R39E (this ADR plus its siblings) as
the documentation surface. The four pieces and how they connect:

```
   chat input
       |
       v
   R39A perceive stage  ----------  unk(word) > 0  ----+
       |                                               |
       |                                               v
       |                                  slt_signal_unknown_query
       |                                  (SLT_UNKNOWN_QUERY, weight 600/1000)
       |                                               |
       v                                               v
   intent dispatcher                          mind/learning arbiter
   (self-ID? KG-match?)                       (200ms fusion, score, queue)
       |                                               |
       v                                               v
   immediate reply                          R39D idle-loop episode drain
                                                       |
                                                       v
                                            R39B if_transport_get(url)
                                                       |
                                          +------------+---------------+
                                          |                            |
                                  IF_TRANSPORT_HTTP_OK         IF_TRANSPORT_DEFERRED
                                  (plain HTTP)                 (https - R39B.2)
                                          |
                                          v
                                  R39F preprocess
                                  (strip HTML/markup,
                                   lowercase, stopwords,
                                   sliding-window triple
                                   extractor)
                                          |
                                          v
                                  if_ingest(words, triples)
                                          |
                                          v
                                  KG manager
                                  (atom_birth at provenance=fetched,
                                   tier per ADR-0029,
                                   belief_init per ADR-0023)
```

The end-to-end story per piece:

1. **Trigger (R39A inside the chat dispatcher).** During perceive,
   the chat counts unknown-word atoms (atoms whose label was novel
   in this turn). When `unk > 0`, the dispatcher calls into
   `slt_signal_unknown_query` from
   `src/learning/self_learning_triggers.nova`, which enqueues an
   `SLT_UNKNOWN_QUERY` signal tagged with the offending lemma as
   the target concept. The signal carries `SLT_SCALE`-normalised
   source weight 600 (= 0.6 per ADR-0026); the queue cap is
   `SLT_QUEUE_MAX = 8`.

2. **Research (R39D idle-loop drain).** During the
   `agent/agent.nova` idle hook (ADR-0036 / ADR-0037 -- the
   "what runs when the user isn't talking" path), R39D's
   orchestrator polls the learning arbiter for the
   highest-scoring episode (priority =
   `source_weight * competence_gap * goal_alignment` per
   ADR-0026). For an `SLT_UNKNOWN_QUERY` episode it looks the
   target concept up in `KG-sources` (ADR-0028) to derive a URL,
   then calls `if_permit(f, url, now)` to gate the request through
   whitelist + token-bucket + per-domain spacing.

3. **HTTP transport (R39B).** On `FETCH_OK`, R39D calls
   `if_transport_get(url, max_bytes)`. R39B is the round that
   makes this function actually reach the network: it composes
   `src/io/transducers/http_client.nova`'s `http_get` (already
   shipped as the HTTP/1.1 client primitive) with the whitelist
   gate, the `IF_TRANSPORT_*` result tag map, and the audit log
   write. **Plain HTTP only** -- the `https` scheme returns
   `IF_TRANSPORT_DEFERRED` with the message
   `"https deferred to scripts/learn.sh -- see TLS_AUDIT.md"`.
   HTTPS will land in R39B.2 once the DTLS-derived TLS path lifts
   into the http_client seam (see TLS_AUDIT.md). For HTTPS today
   the existing manual `scripts/learn.sh <url>` path stays
   primary; `/learn` then consumes the cache file. This is
   documented honestly in `docs/CHAT_USAGE.md`.

4. **Preprocess (R39F).** Whatever bytes come back are stripped
   of HTML / markup, lowercased, broken into alphabetic tokens,
   filtered through the English stopword list (an inline ~150-word
   set; multi-language is deferred), and passed through the same
   5-word sliding-window triple extractor `scripts/learn.sh` uses.
   The output is two lists -- `words[]` (candidate vocabulary
   atoms, kind=lang) and `triples[]` (subject-predicate-object
   structural atoms, kind=relation). Preprocessing is
   pure-substrate text; no LLM is involved.

5. **Ingest.** R39D calls `if_ingest(f, url, payload)` which
   writes the audit entry, populates the URL-keyed cache (TTL per
   ADR-0028), tags each new atom with `provenance=fetched`, looks
   up the source's authority tier from `KG-sources`, and applies
   the Bayesian alpha/beta increment per ADR-0029 (Tier A = +3,
   Tier B = +1.5, Tier C = +0.6 to the winning side; loser
   decayed). The atom-birth monitor (ADR-0025) tracks the new
   atoms for promotion / atrophy review.

The arbiter respects ADR-0028's single-in-flight cap, so a
second `SLT_UNKNOWN_QUERY` queued while the first episode is
fetching just waits its turn.

## Performance budget

Per unknown word at perceive time:

- Queue append: O(1), microseconds (in-memory list append).
- Deferred network fetch (R39D drain): 2-10 seconds (per-domain
  spacing 2s + TCP + body recv) for a typical 50-100KB
  Wikipedia-style page.
- Preprocess: ~5-15ms for a 100KB body on the substrate.
- Ingest: ~50ms for 30 atoms + 5 triples (atom_store insert +
  belief update + xref scan).

The cost the user feels at chat time is the perceive cost only
(microseconds); the actual research happens later in the idle
loop and the answer to the original unknown query comes from
the now-populated KG on the **next** turn or the next time the
agent surfaces the topic itself.

## Failure modes (named and tested)

| Failure                         | Surface                          | Effect                                                         |
|---------------------------------|----------------------------------|----------------------------------------------------------------|
| Whitelist denies host           | `FETCH_DENIED_HOST` from `if_permit` | Episode dropped; audit entry; no socket opened.            |
| Rate limit hit (30/hr or 2s/dom)| `FETCH_RATE_LIMITED` from `if_permit`| Episode requeued at end; arbiter picks the next candidate. |
| TCP / DNS / connect failure     | `IF_TRANSPORT_HTTP_ERR` + `HTTP_ERR_*` | Episode marked failed; audit entry with the error message. |
| Body too large (> `IF_MAX_BODY`)| `HTTP_ERR_TOO_LARGE` / `FETCH_INVALID` | Body truncated to cap; what we got is preprocessed; flag.  |
| Parse / preprocess error        | `FETCH_INVALID`                  | Episode marked failed; partial atoms not committed.          |
| HTTPS scheme                    | `IF_TRANSPORT_DEFERRED`          | Episode marked deferred; user is told to use `scripts/learn.sh`. |
| Wrong content-type              | `FETCH_INVALID`                  | Episode marked invalid; audit entry; no atoms.               |

Every failure path is audited via the decision log (ADR-0043) so a
later `/why` or `/history` walks the operator through what was
attempted and why it stopped.

## Configuration knobs

These are the rate-limit and size caps the round ships with. They
live in `src/learning/internet_fetch.nova` as `let IF_*` constants
unless noted.

| Knob                        | Value      | Notes                                        |
|-----------------------------|------------|----------------------------------------------|
| `IF_MAX_PER_HOUR`           | 30         | Global token bucket per ADR-0028.            |
| `IF_DOMAIN_SPACING`         | 2 seconds  | Per-domain courtesy spacing.                 |
| `IF_MAX_BODY`               | 2 MB       | Response cap; truncated above.               |
| `IF_INFLT_CAP`              | 1          | At most one fetch in flight.                 |
| `SLT_QUEUE_MAX`             | 8          | Learning-episode queue depth (ADR-0026).     |
| `SLT_FUSION_WINDOW_TICKS`   | 20         | 200ms at 100Hz fusion window.                |
| R39F stopword set           | ~150 words | English; multi-language deferred.            |

## Security posture

The chain enforces the substrate's invariants:

- **No LLM in the cognition path (ADR-0014).** Bytes from the
  network are inert evidence. They are preprocessed by pure
  substrate text manipulation (lowercase, tokenize, stopword
  filter, slide a 5-word window). They are NEVER passed to a
  language model for "smart" extraction. The atoms they become
  are subject to ADR-0029 tier weighting like any other source.
- **Whitelist is the only network gate (ADR-0028).** No code path
  exists that can fetch a non-whitelisted URL. The whitelist
  lives as atoms in `KG-sources`; adding an entry is an approve-
  tier action (ADR-0041) which requires the user.
- **Audit per ADR-0043.** Every fetch -- success, denied,
  rate-limited, invalid -- writes an append-only record with the
  URL, status, byte count, body hash, and triggering episode ID.
  `/history` and `/why` surface these.
- **Source authority pinning per ADR-0029.** A `KG-sources` atom
  cannot be retroactively reassigned to a higher tier without an
  approve-tier action. A fetched claim can never overwrite a
  user-taught (Tier A) claim silently; the system marks the atom
  `contested` and surfaces it for adjudication.

## Honest gaps

- **HTTPS deferred to R39B.2.** The shipping path is plain HTTP
  only. The `if_transport_get` function returns
  `IF_TRANSPORT_DEFERRED` for any `https://` URL with the message
  `"https deferred to scripts/learn.sh -- see TLS_AUDIT.md"`.
  Users wanting Wikipedia today should run
  `scripts/learn.sh <topic|url>` first, then `/learn <ARG>` in
  the chat -- that pipeline does its own HTTPS via the system
  curl. The autonomous loop will fetch HTTP whitelist entries in
  R39 and graduate to HTTPS once the TLS-in-http_client work in
  R39B.2 lands.
- **Multi-language stopwords deferred.** The R39F preprocessor
  ships an English stopword set only. Non-English text will be
  ingested with more noise (function words become atoms) until
  R39F.2 adds per-language tables. The triple extractor is
  English-grammar-shaped (subject-verb-object windowing); it
  will fire spurious triples on languages with different word
  order.
- **Whitelist seed is small.** v1 ships ~15-30 vetted domains.
  Adding entries is an approve-tier action -- the user has to
  okay each addition. Founder curation is ongoing work.
- **Single-active episode is a real cap.** During an active
  fetch, queued unknown-query episodes wait. With the 2s/domain
  spacing and 30/hr global cap, a burst of unknown words from one
  long user turn can take minutes to fully process.
- **No competence-gap reweighting yet.** The arbiter scores
  candidates as `source_weight * competence_gap * goal_alignment`,
  but R39 leaves `competence_gap` as a constant 1.0 and
  `goal_alignment` as a constant 1.0. Both feed in from
  ADR-0020 and ADR-0033 in a future round.

## Consequences

- **Positive.** An unknown word during chat costs ~0ms at perceive
  time and deferred ~2-10s + ~50ms for the actual research +
  ingest. The agent grows its KG without the user manually
  running `scripts/learn.sh`. Every fetch is whitelisted,
  audited, tier-tagged, and reversible (the cache TTL plus the
  atrophy monitor will retire stale atoms). No LLM in the
  cognition path.
- **Negative.** The 30/hr global cap is genuinely tight for a
  curious system; the founders may need to raise it once the
  whitelist is broader. Per-domain spacing of 2s makes any
  bursty crawl slow on purpose -- that is by design (politeness
  to upstream + audit clarity) but it shows up as "why is my
  agent still chewing on that paragraph from 20 seconds ago?"
- **Future work.** R39B.2 lifts HTTPS. R39F.2 adds multi-language
  stopwords. A future R40+ round may add competence-gap
  reweighting (close ADR-0020's loop into the arbiter) and a
  per-domain trust score that feeds back into ADR-0029 tiers.

## How this relates to the existing ADRs

- ADR-0026 specifies the **trigger taxonomy** and the arbiter's
  scoring rule. R39A's `slt_signal_unknown_query` call is the
  only new entry point R39 needs from the existing primitive.
- ADR-0028 specifies the **fetch gate** (whitelist + rate limit
  + validate + audit + cache). R39B is the round that wires the
  in-process HTTP transport; the gate and cache are pre-existing.
- ADR-0029 specifies **tier weighting + conflict resolution**.
  R39 does not change the rules; it just ensures the ingest path
  populates the tier field correctly from `KG-sources`.
- ADR-0036 + ADR-0037 specify the **idle loop**. R39D layers an
  episode-drain hook on the existing idle scheduler; it is one
  more callback the scheduler invokes when the active loops are
  quiet.
- ADR-0043 specifies the **decision log**. R39 does not change
  its format; every step in the chain writes the existing
  `act_*` action types (fetch, ingest, deny, error).
- ADR-0014 specifies **no LLM in cognition**. R39 preserves this
  -- the byte stream from the network never reaches a language
  model.

## Implementation notes

- Modules touched (by sibling agents in this round):
  - R39A: `examples/crossengin_chat.nova` dispatcher; calls
    `slt_signal_unknown_query` on perceive unk>0.
  - R39B: `src/learning/internet_fetch.nova` extension; HTTP
    plumbing via `src/io/transducers/http_client.nova`.
  - R39D: `src/parts/meta/idle_loop_orchestrator.nova` (new);
    drains the learning queue on idle ticks.
  - R39F: `src/learning/text_preprocess.nova` (new); strip /
    tokenize / stopword / triple-extract.
- Tests: per-piece unit tests plus a single
  `tests/integration/test_r39_autonomous_loop.sh` end-to-end
  that injects an unknown word, idles N ticks, and asserts a
  new atom appears in `KG-reasoning` with `provenance=fetched`.

## Deferred to R39B.2

- HTTPS via the http_client TLS path.
- Body decompression (`Content-Encoding: gzip` is currently
  refused with `FETCH_INVALID`).
- Redirect following past 3 hops (current cap).

## Deferred to R39F.2

- Per-language stopword tables.
- Better triple extractor for non-SVO languages.
- HTML structural extraction (headings -> concept hierarchy);
  today we treat HTML as a flat text stream after tag-stripping.
