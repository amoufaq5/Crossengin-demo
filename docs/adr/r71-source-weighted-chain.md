# R71: Source-weighted forward chaining

## Status

Accepted — R71 round. The academic forward-chain now weights each edge's
confidence by the authority of the source it was learned from, so reasoning
prefers Wikipedia / a learned topic / the curated seed over a lower-authority
dictionary edge when confidences are close.

## Date

2026-06-09

## Context

`_cr_chain` greedily follows the highest-*confidence* chaining operator. But
confidence (the operator's Bayesian belief) says nothing about *where* the edge
came from — a freshly-minted dictionary genus edge and a corroborated Wikipedia
causal edge start at the same default belief. The operator labels already carry
the provenance (`src:url:…`, `src:dict:…`, `src:topic:…`, or a bare seed label),
but the chain ignored it.

## Decision

- `_cr_src_weight(label)` (`src/agent/cognitive_router.nova`, pure): a milli
  authority factor from the label's provenance prefix — Wikipedia 1000,
  `src:url:` 950, a learned topic 920, Wiktionary 900, dictionary 850, other
  `src:` 850, and **seed / curated (no `src:`) 1000** (fully trusted).
- `_cr_chain` selects the edge with the highest `confidence * _cr_src_weight /
  1000` rather than raw confidence. Because seed edges weight 1000, single-edge
  and all-seed chains are unchanged; the weighting only breaks ties / reorders
  when a node has competing edges from different sources.

## Verification

- **Unit** (`test_cognitive_router` 29 → 34): `_cr_src_weight` over wikipedia /
  dictionary / seed labels; and a node with two equal-confidence CAUSAL edges —
  a dictionary edge listed first, a Wikipedia edge second — chains to the
  **Wikipedia** target ("trusted"), not the low-authority one ("cheap"), which a
  confidence-only pick would have taken. The existing
  `morning->breakfast->energy->work` seed chain is unaffected (all weight 1000).
  `reader` passes; chat builds.

## Consequences / scope

- When the agent has learned the same kind of edge from multiple sources, its
  forward-chain now leans on the more authoritative one — the dictionary's
  best-effort genus loses to a corroborated encyclopedia causal edge of equal
  confidence. Confidence still dominates within a source tier (a strongly-held
  dictionary edge beats a weakly-held Wikipedia one).
- The weights are a small static authority table in the router, not the full
  ADR-0029 `source_authority` tier machinery (which is URL/host-oriented and
  needs a registered `sa` instance). Wiring the dynamic, track-record-based
  tiers (so a source's authority *adapts* to its corroboration history) is the
  next step.
- Only the chain-selection (`_cr_chain`) is weighted; the single-triple / analogy
  / opposite surfaces still use raw confidence. Extending the weighting to those
  is straightforward follow-up.
