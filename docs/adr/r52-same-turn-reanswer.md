# R52: Same-turn re-answer after autonomous research

## Status

Accepted — R52 round (the "h" enhancement). Closes the idle-loop latency gap
left by R50: when the agent researches an unknown query on its own initiative,
it now answers that query in the **same turn** instead of the next one.

## Date

2026-06-08

## Context

R50 wired autonomous research: with `CE_AUTORESEARCH=1`, an unknown query files
a curiosity trigger, the trigger is drained at idle, and the topic is fetched +
learned (DNS → TLS 1.3 → preprocess → compound ingest). But the chat generates
the reply *before* the idle drain runs, so the same turn still printed the honest
gap ("i don't have a model of X yet") and only the **next** turn could answer.
The R50 ADR named this explicitly: *"Re-answering within the turn would need a
second reply pass (a later refinement)."* This is that refinement.

The blocker was the percept. The reply's forward-chain seeds from the perceived
concept handles (`_cr_seeds(percept)` in the router), and the percept was
anchored *before* the fetch — when the topic word was still unknown, so it had no
concept handle to chain from. Re-running the router over the stale percept would
just hit the gap branch again.

## Decision

Add a same-turn re-answer pass that runs after the research drain, before the
reply is printed (the print already happens at end-of-turn, after the drain):

- `_drain_and_research` now **returns the topic it researched** (or `""`),
  instead of a 1/0 flag, so the caller knows research happened and on what.
- `_reanswer_after_research` **re-perceives the same query** —
  `loop_perception_step` re-reads the input and re-anchors its tokens against
  the now-grown KGs, so the freshly-learned topic gets a concept handle — then
  **re-runs the router** (`router_reply` with the fresh percept) and adopts the
  new reply.

Three guards keep this an *upgrade only*, never a regression:

1. **Only upgrade a non-reasoned reply.** If the first pass already reasoned
   (a forward-chain / known relation), leave it — research never overrides a
   good answer. (Checked against the original `_last_reason_trace`, still intact
   at entry.)
2. **Only adopt a reasoned re-answer.** The new reply must itself show a
   forward-chain or known relation; a topic that was fetched but yielded no
   chainable operator leaves the honest gap standing rather than swapping one
   gap phrasing for another.
3. **Only when it changed.** The new reply must differ from the first.

On adoption it re-speaks through the governed effector (so the decision log,
`/why`, and `/good` / `/bad` track the *final* answer and its operators) and
refreshes `_last_reply` / `_last_reason_trace` / `_last_reason_ops`.

## Verification

Live, in the chat:

- `CE_AUTORESEARCH=1`, fresh boot, "what is photosynthesis" (unknown) → the
  agent fetches `…/Photosynthesis` (1375 words, 68 operators) and answers **in
  the same turn**: `photosynthesis leads to translocated
  (photosynthesis -> process -> translocated)`, trace `academic: forward-chain
  photosynthesis -> process -> translocated`. Before R52 the same turn said
  "i don't have a model of 'photosynthesis' yet".
- **Default** (autoresearch off): unchanged — honest gap, no research, no
  re-answer (the re-answer block is a structural no-op when `_drain_and_research`
  returns `""`).
- **Gated**: autoresearch on with a known greeting / self-ID query does no
  research and no re-answer (nothing was researched, so the pass never runs).

Cognition unit suites pass (`cognitive_router` 17, `input_classifier` 35,
`lexical_anchor` 27, `word_atoms` 33, `reasoning_atoms` 13); chat builds.

## Consequences / scope

- One-turn UX: the agent closes its own knowledge gap **and** uses what it
  learned in a single exchange. The research-progress lines print first (the
  user sees the fetch happen), then the reasoned answer.
- The `perceive(m=…,unk=…)` line still reflects the **original** perception —
  what the agent understood *when asked* (unk=1 for the then-unknown topic). The
  re-perceive is internal; surfacing the re-perceived counts is a later polish.
- The first (gap) reply was already spoken + logged before the override; the
  re-speak appends the final answer, so the turn leaves two decision-log
  entries — an honest trace of "asked → didn't know → researched → answered".
- Still one fetch per turn (R50's rate limit), and only the **autonomous** path
  re-answers — `/research TOPIC` is an explicit command, not a question, so it
  does not trigger a re-answer. Network-dependent, so not unit-tested, but built
  on the unit-tested router + perception steps.
