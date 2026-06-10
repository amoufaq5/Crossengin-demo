# R73: Opposite-aware belief update (X asserted ⇒ its opposite less likely)

## Status

Accepted — R73 round. R72 surfaced an antonym as a *contrast* in the reply; R73
makes it a real inference: corroborating a fact about X lowers the belief in X's
antonym Y.

## Date

2026-06-09

## Context

R67 gave antonyms a `ROP_OPPOSITE` relation; R72 used it to frame a forward-chain
answer ("…, as opposed to Y"). But that was display-only — the agent's beliefs
didn't change. The genuine inference "X holds ⇒ its opposite is less likely" was
explicitly deferred in R72.

## Decision

- `_cr_weaken_opposite(kg, percept)` (`src/agent/cognitive_router.nova`): find
  the subject's antonym via `_cr_related_of(…, ROP_OPPOSITE)`, resolve the
  opposite *concept* atom (the operator's conclusion), and apply one **negative
  observation** (`atom_observe(Y, -1)`) so Y's Bayesian belief mean drops.
  Returns the weakened label (or "").
- `_cr_factual`, on the **corroborated** branch only (the assertion lines up with
  a known causal/implicative relation about X), calls it and appends a note:
  `… ('dark', its opposite, now a bit less likely)`. Restricting it to the
  corroborated path keeps the update conservative — only an *affirmed* X
  down-weights its opposite, not every passing mention.

## Verification

- **Unit** (`test_cognitive_router` 38 → 42): asserting a corroborated fact about
  "light" (which has a `ROP_OPPOSITE` edge to "dark") lowers `atom_confidence`
  of the "dark" atom and notes it as "less likely"; a concept with no antonym is
  untouched (no note, no belief change). Chat builds.

## Consequences / scope

- The antonymy graph (R66/R67) now feeds back into beliefs: repeatedly affirming
  one pole of an opposition gently suppresses the other, which is the expected
  direction for mutually-exclusive concepts. The magnitude is one observation per
  corroborated assertion — mild, and the ADR-0025 GC handles a pole that decays
  to near-zero.
- It fires only in the **factual** strategy's corroborated branch (an assertion
  affirmed by existing knowledge), not on academic *queries* — asking "what is X"
  does not assert X, so it must not suppress X's opposite.
- The update is one-directional (X's mention weakens Y, not vice-versa in the
  same turn) and unconditional within that branch; a symmetric, evidence-weighted
  update (down-weight proportional to X's own corroboration strength) is the
  natural refinement.
