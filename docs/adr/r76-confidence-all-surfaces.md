# R76: Confidence on every academic surface

## Status

Accepted — R76 round. Extends R74's confidence hedge from multi-hop chains to
the single-relation, synonym, and antonym academic surfaces, so every reasoned
answer carries its certainty.

## Date

2026-06-09

## Context

R74 hedged the forward-chain answer ("tentatively, …" / "i think …") by its
weakest-link confidence, but the other academic surfaces — a single known
relation, a synonym ("X is like Y"), an antonym ("X is the opposite of Y") —
still stated their one-operator conclusion flatly. The certainty was available
(the operator's belief) but only the chain surfaced it.

## Decision

- `_cr_op_confidence(kg, opid)` (`src/agent/cognitive_router.nova`): the
  confidence (milli) of a single operator by atom id (1000 if absent).
- `_cr_academic`'s single-triple, synonym, and antonym branches each prepend
  `_cr_confidence_phrase(_cr_op_confidence(...))` to the reply and append
  `[conf=N]` to the trace — the same hedge vocabulary as the chain.

## Verification

- **Unit** (`test_cognitive_router` 48 → 50): the synonym and antonym surfaces
  now carry `[conf=` in their trace; all existing surface tests still pass — a
  default-belief operator (500) reads "i think X is like Y", whose asserted
  substrings are unchanged.
- Chat builds.

## Consequences / scope

- Every academic answer — chain, relation, synonym, antonym — now communicates
  how sure the agent is, grounded in the operator beliefs that `/good` / `/bad`
  move. A freshly-learned dictionary synonym reads "i think X is like Y"; a
  heavily-reinforced one drops the hedge.
- The gloss ("X means: …") and the knowledge-gap replies stay unqualified — a
  gloss is a definitional lookup, not an inference, so a confidence figure there
  would be misleading.
- The hedge is uniform across surfaces by reusing R74's `_cr_confidence_phrase`
  thresholds; per-surface tuning (e.g. a stricter bar for analogical "is like")
  is a possible refinement.
