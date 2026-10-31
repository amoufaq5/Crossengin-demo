# R72: Opposite-aware contrast in forward-chain replies

## Status

Accepted — R72 round. When the academic strategy forward-chains an answer about
a concept that has an antonym (R67 `ROP_OPPOSITE`), the reply now contrasts it
("…, as opposed to Y") — reasoning with what the subject is *not*.

## Date

2026-06-09

## Context

R67 gave antonyms a first-class `ROP_OPPOSITE` relation and a standalone surface
("X is the opposite of Y") that fires only when there's no chain. But when the
agent *does* have a forward-chain for X, the opposite was ignored — the answer
never used the antonymy it had learned. Aristotelian definition is by genus
*and* contrast; the chain had the genus path but not the contrast.

## Decision

In `_cr_academic`'s forward-chain branch, look up the subject's opposite with
`_cr_related_of(kg, percept, ROP_OPPOSITE)` and, when present, append a contrast
clause to the reply and a `(vs Y)` note to the trace:

```
happy leads to happiness (happy->happiness), as opposed to sad.
  trace: academic: forward-chain happy->happiness (vs sad)
```

When the subject has no antonym the reply is byte-identical to before (the
clause is empty), so it's purely additive.

## Verification

- **Unit** (`test_cognitive_router` 34 → 38): a concept with a causal chain
  *and* a `ROP_OPPOSITE` edge answers "happy leads to joy … , as opposed to sad"
  with `(vs sad)` in the trace; the same concept with no antonym gets no contrast
  clause.
- **Live**: `/define happy` (mints `ROP_OPPOSITE` antonym edges), then "what is
  happy" → "happy leads to happiness (happy->happiness), as opposed to
  inappropriate." Chat builds.

## Consequences / scope

- The agent's reasoning is now opposite-aware on the main answer path: a chained
  conclusion is framed against its antonym, which is more informative and uses
  the antonymy graph (R66/R67) the dictionary built. The `/good` `/bad` feedback
  still targets the chain's operators (the contrast is a framing clause, not a
  re-weighted edge).
- This is the *display/framing* form of "X holds ⇒ its opposite contrasts". The
  stronger inferential form — actively lowering belief in the opposite when X is
  concluded (a belief update on the antonym atom) — is the natural next step;
  R72 stops at surfacing the contrast, which is safe and reversible.
- The contrast uses the subject's first antonym edge; ranking antonyms (or
  contrasting the chain's *tail* as well as its head) is future polish.
