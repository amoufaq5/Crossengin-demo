# R75: Anaphora resolution (a pronoun follows the last topic)

## Status

Accepted — R75 round. A follow-up pronoun ("it", "they", …) resolves to the
conversation's last subject, so multi-turn dialogue flows: "what is
photosynthesis" then "what is it" reasons about photosynthesis.

## Date

2026-06-09

## Context

Every turn was treated in isolation. A natural follow-up — "what does it
produce", "tell me about it" — was meaningless to the agent: "it" anchored to
nothing, so the pronoun was either an unknown word or dropped. The conversation
couldn't carry a subject across turns.

## Decision

- `resolve_anaphora(text, last_topic)` (`src/chat/helpers.nova`, pure,
  unit-tested): replace each anaphoric token (`it` / `its` / `they` / `them` /
  `their`, trailing `?.,!` preserved) with `last_topic`; other tokens are kept
  verbatim (including case). Returns the text unchanged when there's no anaphor
  or no remembered topic.
- The chat keeps a process-wide `_last_topic`, set at the end of each agent turn
  to the input's first content word (`_cr_topic_word` of the *resolved* input).
  Before an agent message is processed (admin commands are exempt), the chat
  rewrites it through `resolve_anaphora` and prints the substitution
  (`"what is it" -> "what is photosynthesis"`).

## Verification

- **Unit** (`test_chat_helpers` 94 → 100): "what does it produce" →
  "what does photosynthesis produce"; "what is it?" keeps the "?"; "they"
  resolves; non-pronoun tokens keep their case; empty topic / no pronoun →
  unchanged.
- **Live**: `/learn` a `photosynthesis→energy` edge, "what is photosynthesis"
  (reasons, sets the topic), then **"what is it"** →
  `("what is it" -> "what is photosynthesis")` and the agent re-reasons
  "photosynthesis leads to tired …". Chat builds.

## Consequences / scope

- The agent now holds a conversational subject across turns — the first piece of
  real dialogue continuity. Combined with the reasoning surfaces, a user can
  introduce a topic and then probe it with pronouns.
- The topic is the *first content word* of the last query, and any anaphoric
  pronoun maps to it. This is a single-antecedent heuristic: it doesn't track
  multiple referents, gender/number agreement, or distinguish an expletive "it"
  ("it is raining") from a referential one — rare in a knowledge dialogue, and
  noted here as the boundary. Demonstratives ("this"/"that") are deliberately
  excluded (too entangled with relatives).
- Resolution happens before perception, so the rewritten query flows through the
  normal classify→route path; if that path mis-handles the rewritten phrasing
  (e.g. routes "tell me about photosynthesis" to the social strategy), that's a
  separate classifier concern, not an anaphora one.
