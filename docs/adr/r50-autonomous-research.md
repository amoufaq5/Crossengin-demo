# R50: Autonomous research (self-initiated /learn on unknowns)

## Status

Accepted — R50 round. Wires the self-learning-trigger queue (ADR-0026) to the
live fetch pipeline (R41–R49) so the agent learns from the internet on its own
initiative when it hits something it doesn't know.

## Date

2026-06-08

## Context

The pieces existed but were never connected at the chat:

- The chat already files an `SLT_UNKNOWN_QUERY` trigger for every unknown term
  (`_submit_curiosity`), and drains the queue at idle (`_drain_and_teach`) —
  but the drain only minted a bare stub atom for the word, never *researched*
  it.
- `src/learning/autonomous_research.nova` (R39D) had a FETCHING → PREPROCESSING
  → INGESTING orchestrator for exactly this, but it predated the live transport
  (R41) and the `learn_pipeline`: its FETCHING used the old `if_dispatch_transport`
  (no DNS, no TLS) and its INGESTING stored opaque evidence rather than the
  triples/operators `lp_ingest` now creates. So it could not actually fetch.

R41–R49 then built a working pipeline (DNS-over-UDP → TLS 1.3 → preprocess →
compound ingest). R50 connects the existing trigger queue to it.

## Decision

Add an idle-loop research drain to the chat, using the **modern**
`learn_from_url`:

- `_drain_and_research` (runs before `_drain_and_teach`): when
  `CE_AUTORESEARCH=1`, dequeue ONE unknown topic from the trigger arbiter,
  derive a Wikipedia URL, and run it through `learn_from_url` (DNS + TLS 1.3 +
  preprocess + `lp_ingest`). The rest of the queue still falls through to stub
  minting. One fetch per turn; each topic researched at most once.
- `_ar_wiki_url(topic)` → `https://en.wikipedia.org/wiki/<Capitalized>` (https so
  the in-engine TLS client serves it; capitalized so the canonical title is hit
  directly instead of a lowercase redirect the no-redirect client wouldn't
  follow).
- `/research TOPIC` — an explicit trigger of the same path, no env flag needed
  (handy for demo/control).

Opt-in by design: autonomous outbound requests are gated on `CE_AUTORESEARCH`,
and `/research` is always explicit. The older `autonomous_research.nova`
orchestrator is left intact (its unit test + federation references), but is
superseded by this `learn_from_url`-based path.

## Verification

Live, in the chat:

- `/research photosynthesis` → fetches `…/Photosynthesis`, learns **1375 words,
  68 operators, 1334 new atoms**; "what is photosynthesis" then reasons:
  `photosynthesis -> process -> translocated`.
- `CE_AUTORESEARCH=1`, "what is mitochondria" (unknown) → the agent fetches
  `…/Mitochondria` **on its own** (1931 words, 129 operators), and the next turn
  reasons `mitochondria -> double_membrane` — over a learned **compound**
  (R45) anchored from free text (R48).

Chat regression scenarios pass with `CE_AUTORESEARCH` unset (default behaviour
unchanged); chat rebuilds.

## Consequences / scope

- The agent now closes its own knowledge gaps from the web: unknown query →
  autonomous fetch → learn → reason on the follow-up. The full session arc
  (per-category cognition → live authenticated learning → clean compound
  knowledge → free-text recall → self-initiated research) is connected.
- Idle-loop model: the gap reply is generated before the fetch, so the same
  turn still says "I don't have a model yet" and the *next* turn answers — the
  research happens "at idle", as designed. Re-answering within the turn would
  need a second reply pass (a later refinement).
- Topic → URL is a Wikipedia heuristic on the single unknown term; multi-word
  topics file their words individually. A real search/disambiguation step and
  source diversity beyond Wikipedia are future work. Rate-limited to one fetch
  per turn; not unit-tested (network-dependent) but built on the tested
  `learn_pipeline`.
