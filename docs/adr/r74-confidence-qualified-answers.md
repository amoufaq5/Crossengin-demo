# R74: Confidence-qualified answers

## Status

Accepted — R74 round. The academic forward-chain answer is now hedged by its
weakest-link confidence — "tentatively, …" / "i think …" / (confident, no hedge)
— so the agent's certainty is visible in the reply.

## Date

2026-06-09

## Context

The agent stated every forward-chain conclusion with the same flat certainty,
whether the chain rested on a freshly-minted edge or a heavily-corroborated one.
One of the original complaints was that the feedback was "dumb / not related to
what is designed": the reasoning had real Bayesian confidence per operator
(ADR-0023), but the reply never reflected it.

## Decision

- `_cr_chain_confidence(kg, ops)` (`src/agent/cognitive_router.nova`): the chain's
  confidence is its **weakest link** — the minimum operator belief along it
  (milli); an empty chain is fully confident (1000).
- `_cr_confidence_phrase(conf)`: a leading hedge — `>= 700` none (confident),
  `400–699` "i think ", `< 400` "tentatively, ".
- `_cr_academic`'s forward-chain branch prepends the phrase to the reply and
  appends `[conf=N]` to the trace.

## Verification

- **Unit** (`test_cognitive_router` 42 → 48): `_cr_confidence_phrase` at each
  tier; and a one-edge chain whose operator is weakened (`rop_observe(-1)` →
  belief ~333) answers "tentatively, rain leads to flood …", still reaches the
  conclusion, and records `[conf=` in the trace. The existing chain tests
  (default belief 500) keep passing — they now read "i think …", which still
  contains the asserted substrings.
- **Live**: a freshly `/learn`ed `photosynthesis|causal|energy` edge (belief 500)
  → "i think photosynthesis leads to tired (…)" with trace `… [conf=500]`. Chat
  builds.

## Consequences / scope

- The reply now communicates how sure the agent is, grounded in the operators'
  actual beliefs — a strongly-corroborated chain is stated plainly, a tentative
  one is flagged. Combined with `/good` / `/bad` (which move those beliefs), the
  hedge visibly tightens or loosens as the agent learns.
- Weakest-link is a conservative aggregate (one shaky edge hedges the whole
  chain); a probabilistic product across the chain, or surfacing the specific
  weak edge, are natural refinements.
- The qualifier is on the academic forward-chain only; the single-triple /
  analogy / opposite / gloss surfaces still state plainly. Extending the hedge to
  those (and to the factual "lines up" reply) is straightforward follow-up.
