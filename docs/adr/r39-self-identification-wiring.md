# R39: Self-identification wiring (chat -> self_model_query bridge)

## Status

Accepted -- R39 round wiring of the pre-existing `self_model_query` API
into the chat intent dispatcher.

## Date

2026-06-06

## Context

The substrate's existing ADRs already specify a complete self-awareness
surface:

- **ADR-0034** (soul wrapper) hosts identity, OCEAN, values,
  constitution, identity themes, and loyalty hierarchy under
  timescale-aware write APIs. The shipping `src/core/soul.nova`
  exposes `soul_name`, `soul_purpose`, `soul_mood_valence`,
  `soul_mood_arousal`, and the structured state map.
- **ADR-0038** (self-model query API) specifies typed
  introspection queries -- `SELFQ_IDENTITY`, `SELFQ_STATE`,
  `SELFQ_GOALS`, `SELFQ_COMPETENCE`, `SELFQ_ACTIVITY` -- and
  delegates each to a renderer that aggregates over soul,
  emotion, goals, competence, and live loops. The shipping
  `src/parts/meta/self_model_query.nova` exposes `smq_answer`
  and the five subtype dispatchers.

What was missing through R38: **the chat surface had no way to
turn a user utterance like "who are you?" or "what can you do?"
into a `SELFQ_*` call.** A literal natural-language input would
go through the perceive stage, hit the language KG, and either
fall back to the seeded reply or trigger an unknown-query
learning episode. The agent has the answer to "who are you?" in
its soul block; it just was not asked.

R39A is the round that asks.

## Decision

R39A adds an **intent dispatcher** to the chat's per-turn processing.
After perceive and before KG-match the dispatcher classifies the
incoming utterance into one of three intent types in priority
order:

1. `INTENT_SELF_ID` -- the utterance is asking the agent about
   itself. Dispatched to `smq_answer(SELFQ_*)` and rendered via
   the existing output substrate.
2. `INTENT_KG_QUERY` -- the utterance maps to existing atoms in
   the KG with sufficient salience. Dispatched to the standard
   KG-match reply path.
3. `INTENT_UNKNOWN` -- the utterance contains at least one
   unknown word that did not match a seeded vocabulary atom.
   Dispatched to `slt_signal_unknown_query` (per the R39
   autonomous-learning ADR).

A single utterance can match more than one intent (e.g. "what
are you trying to do today?" -- self-ID for `SELFQ_GOALS` AND
contains the unknown lemma "today"). Priority is **self-ID
first**, then KG-match, then unknown-query. The unknown-query
side-effect (queueing an `SLT_UNKNOWN_QUERY` signal) still
fires regardless of which intent ended up handling the reply --
the system can answer the self-ID question now AND research the
unfamiliar lemma in the idle loop.

## Pattern -> SELFQ mapping

R39A ships a small regex map. The patterns are intentionally
literal (we are not building an ML-based intent classifier in
this round); they live alongside `src/chat/helpers.nova` and
are easy to extend.

| Pattern (case-insensitive regex)                  | SELFQ subtype      | smq function called      |
|---------------------------------------------------|--------------------|--------------------------|
| `^who are you\??$`                                | `SELFQ_IDENTITY`   | `smq_what_are_you`       |
| `^what are you\??$`                               | `SELFQ_IDENTITY`   | `smq_what_are_you`       |
| `^what.{0,8}your.{0,8}name\??$`                   | `SELFQ_IDENTITY`   | `smq_what_are_you`       |
| `^what (do you|can you) (know|do)\??$`            | `SELFQ_COMPETENCE` | `smq_capabilities`       |
| `^what.{0,12}capabilit`                           | `SELFQ_COMPETENCE` | `smq_capabilities`       |
| `^what (are )?your goals\??$`                     | `SELFQ_GOALS`      | `smq_goals`              |
| `^what are you (trying to do|working on)\??$`     | `SELFQ_GOALS`      | `smq_goals`              |
| `^how (are )?(you|do you feel)\??$`               | `SELFQ_STATE`      | `smq_state`              |
| `^what.{0,8}(mood|feeling).{0,8}$`                | `SELFQ_STATE`      | `smq_state`              |
| `^what are you doing( right now)?\??$`            | `SELFQ_ACTIVITY`   | `smq_activity`           |

The map is consulted in source order; the first matching pattern
wins. Patterns are anchored (`^...\??$`) so a longer sentence
that happens to include "who are you" inside a longer
construction does not accidentally route through self-ID. This
is honest and conservative; we miss "could you tell me who you
are?" today.

The rendered answer flows through the existing output substrate
(ADR-0013) -- concept atoms activate, language nodes select
lemmata, output assembly composes a sentence. **No LLM** in any
part of this path; the renderer is the same pure-substrate
path the rest of the chat uses for KG-match replies.

## Priority: self-ID over KG-match

The dispatcher checks self-ID **first**. The rationale:

- A user typing "who are you?" expects the agent to answer about
  itself, not to dump KG atoms that contain the word "you".
- A self-ID question is also frequently a TRUST-CALIBRATION
  question -- the user is gauging the agent before deciding how
  much to rely on it. ADR-0046 names this as the headline desktop-
  companion need.
- The set of self-ID patterns is small and anchored, so the
  precedence rule does not capture utterances the user did not
  intend as self-ID.

For utterances that match no self-ID pattern, the dispatcher
proceeds to KG-match, then unknown-query, exactly as before.
A self-ID match suppresses the KG-match reply for the same turn;
the unknown-query side-effect still queues if there were unknown
lemmata in the utterance.

## Honest gaps

- **Regex misses niche phrasings.** "Could you remind me who
  you are again?", "Tell me about yourself", "Are you Claude?",
  "What model are you?" -- none of these match the v1 pattern
  set. The system would fall back to KG-match (and likely fail
  to surface a useful answer). The dispatcher is easy to extend
  -- adding an `^are you` row points at `SELFQ_IDENTITY` -- but
  every pattern added is a judgment call about generality vs
  false-positive risk.
- **No ML-based intent classifier.** A learned intent gate is
  the natural next step and is consistent with the substrate
  evolution path (a future round could train a gate over the
  routing decision). It is deferred for now. R39 ships a hand-
  curated regex map because the substrate has no training-time
  reward signal for routing yet (cf. ADR-0026's deferred learned
  trigger policy for the same reason).
- **`SELFQ_COMPETENCE` quality depends on ADR-0020 maturity.**
  The renderer reads competence atoms; if the self-model store
  is sparse the answer is sparse. R39 does not change that. The
  shipping fallback is a terse "I know about: <top-N concept
  labels by belief>".
- **Mood-narration depends on ADR-0035 maturity.** Today the
  `SELFQ_STATE` renderer reads valence + arousal as raw integers
  and emits a small phrase ("valence X, arousal Y" or a coarse
  qualitative mapping). The richer mood narrative is a future
  ADR-0035 follow-up.
- **No theory-of-mind injection (ADR-0039).** The dispatcher
  does NOT route through the user-model before answering. A
  future round may add a "tailor the answer to what this user
  already knows" pass; today the answer is the same regardless
  of who asks.

## Consequences

- **Positive.** A user can type "who are you?" and get a real
  answer rendered from the live soul. The companion trust /
  calibration surface is live; ADR-0049's self-awareness
  capability test can be exercised end-to-end. The dispatcher
  is a small, well-scoped change that does not touch the
  substrate's correctness.
- **Negative.** A literal regex map is brittle. We will
  systematically miss phrasings the patterns do not cover. The
  failure mode is "agent falls back to KG-match" which is the
  pre-R39 behaviour; that is acceptable but visible.
- **Future work.** A learned intent classifier (deferred per
  ADR-0026 trigger-policy precedent); a richer pattern set
  driven by usage telemetry; theory-of-mind tailoring per
  ADR-0039.

## How this relates to the existing ADRs

- ADR-0034 specifies the **soul block** the renderer reads.
  R39A does not modify soul; it just hands the right `SELFQ_*`
  tag to `smq_answer`.
- ADR-0038 specifies the **self-model query API** itself. R39A
  does not modify it; it just becomes the first real caller
  inside the live chat surface.
- ADR-0013 specifies the **output substrate** the rendered
  answer flows through. R39A does not modify it.
- ADR-0014 specifies **no LLM in cognition**. R39A preserves
  this -- pattern matching is pure substrate text; the answer
  rendering is pure substrate concept activation.

## Implementation notes

- New code lives in the chat dispatcher inside
  `examples/crossengin_chat.nova` plus a small `intent_*`
  helper extracted to `src/chat/helpers.nova` for unit-test
  reach. The regex map is a `let` binding so adding a row is a
  one-line change.
- Tests: per-pattern fixture asserting each row routes to the
  expected `SELFQ_*` subtype; an end-to-end fixture asserting
  "who are you?" produces a response containing the soul's
  configured name; a regression fixture asserting a sentence
  with "you" inside other words ("did you eat?") does NOT
  trigger self-ID.

## Deferred

- ML-based intent classifier.
- "are you GPT/Claude/<model>?" -- the answer is "no, I'm a
  CrossEngin substrate" but the pattern is not yet in the map;
  a one-line addition.
- Multi-turn self-ID (the user asks "and how about your goals?"
  after "who are you?" and the system should keep the SELFQ
  context); requires a small per-session dispatcher state.
