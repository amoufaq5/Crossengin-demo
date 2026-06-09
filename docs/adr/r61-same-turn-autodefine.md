# R61: Same-turn autodefine (a defined word answers in one turn)

## Status

Accepted — R61 round (the "q" enhancement). Extends R52's same-turn re-answer to
adopt a dictionary gloss, so a word autodefined at idle (R60) is answered in the
**same turn** instead of the next one.

## Date

2026-06-09

## Context

R60 autodefines an unknown word at idle (`CE_AUTODEFINE`) and stores its
definition as a gloss, so the next turn answers "X means: …". But that was a
two-turn loop: the gloss is set *after* the turn's reply, and R52's same-turn
re-answer only fired for **research** (`_drain_and_research`) and only adopted a
**reasoned** trace (forward-chain / known relation) — a gloss reply
(`academic: dictionary gloss`) was neither triggered nor accepted. So a defined
word still made the user ask twice.

## Decision

Generalize the same-turn re-answer from "after research" to "after idle
learning", covering both research operators and autodefine glosses:

- `_trace_is_answer(trace)` = reasoned **or** dictionary gloss. The re-answer's
  two gates now use it: only upgrade a reply that isn't *already* an answer, and
  only adopt a new reply that *is* an answer (a chain or a gloss).
- `_reanswer_after_research` is renamed `_reanswer_after_learning` (its body is
  otherwise unchanged — re-perceive, re-route, adopt-if-better, re-speak through
  the governed effector, refresh `_last_*` and the R56 re-perceived counts).
- The turn now runs **both** idle drains first — `_drain_and_research` then
  `_drain_and_teach` — and then a single re-answer, gated on research **or**
  autodefine (`_autodefined_turn`, set by `_drain_and_teach` when it defines a
  word, reset each turn). Running after both drains means the one re-answer sees
  whichever result landed.

## Verification

- **Live**: `CE_AUTODEFINE=1`, "what is serendipity" (one turn) →
  `(defined 'serendipity': A combination of events …)` at idle **and**, the same
  turn, `agent> serendipity means: A combination of events …` with
  `reasoning: academic: dictionary gloss` and `perceive(m=3,unk=0)
  [re-perceived after learning; initially m=2,unk=1]`. Before R61 this took two
  turns.
- **R52 preserved**: `CE_AUTORESEARCH=1`, "what is photosynthesis" still answers
  the same turn with a forward-chain (`photosynthesis -> process ->
  translocated`) — the reorder (teach drain before the re-answer) doesn't disturb
  the research path, since the research topic was already dequeued.
- **Default unchanged**: with no flags, "what is serendipity" prints the plain
  gap and the plain `perceive(m=2,unk=1)` line (no re-answer, byte-identical).
- Chat builds; the rename leaves no stale references.

## Consequences / scope

- The autodefine loop now closes in a single exchange, matching research: the
  agent meets an unknown word, defines it at idle, and answers "X means: …" right
  away. The R56 re-perceived counts and `/why` / `/good` / `/bad` all track the
  adopted gloss reply (its ops are empty, correctly — a gloss isn't an operator).
- Research still takes precedence: when both flags are on and research fired, the
  research re-answer runs and the autodefine branch is skipped (research is the
  richer answer).
- A gloss is adopted only when it's a *real* upgrade over a gap and differs from
  the first reply, so an unrelated word defined elsewhere in the turn never
  hijacks the answer to the current query.
- The two drains now both run before the re-answer every turn (previously the
  research re-answer sat between them); behaviour is unchanged for turns that
  learn nothing, since the re-answer is gated on a drain having produced
  something.
