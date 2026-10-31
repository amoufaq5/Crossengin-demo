# R56: Surface re-perceived counts on the same-turn answer

## Status

Accepted — R56 round (the "l" enhancement). Makes the `perceive(m,unk)` line
report what the agent understood AFTER a same-turn research re-answer (R52), not
just its pre-research perception.

## Date

2026-06-09

## Context

R52 added the same-turn re-answer: when autonomous research fills a knowledge gap
mid-turn, the agent re-perceives the query and answers it in the same turn. But
the `perceive(m=…,unk=…)` line still printed the **original** perception counts —
captured before the fetch — so the agent could reason
`photosynthesis -> process -> translocated` while the same line claimed
`unk=1` (photosynthesis still unknown). The telemetry contradicted the answer.

## Decision

Carry the re-perceived counts out of the re-answer pass and prefer them when
present:

- `_reanswer_after_research` already calls `loop_perception_step` to re-anchor
  against the grown KGs; capture its return (matched) and `ctx_unknown` (unknown)
  and, **on adoption**, stash them in process-wide `_reperceive_m` /
  `_reperceive_unk`. They're reset to `-1` at the top of each turn, so they're
  set only when a re-answer actually happened.
- The perceive line (both the human and the JSON-log path) uses the re-perceived
  counts when `_reperceive_m >= 0`, and keeps the original counts alongside:
  - human: `perceive(m=3,unk=0)  [re-perceived after research; initially
    m=2,unk=1]` — the legacy `perceive(m=N,unk=N)` prefix is preserved verbatim,
    so existing tooling/regex still matches;
  - JSON: `m`/`unk` carry the post-research counts, with `m_initial`/`unk_initial`
    added for the pre-research ones.

When no re-answer happens (the overwhelming majority of turns), both paths emit
exactly the legacy line — a pure no-op.

## Verification

- **Live**, `CE_AUTORESEARCH=1`, "what is photosynthesis": the agent researches,
  then prints `perceive(m=3,unk=0)  [re-perceived after research; initially
  m=2,unk=1]` and reasons `photosynthesis -> process -> translocated` — the
  counts now agree with the answer.
- **No-op preserved**: default mode (no research) prints the plain
  `perceive(m=2,unk=1)`. The JSON-log scenario's two assertions both hold — the
  `fever` turn's human line matches `perceive\(m=N,unk=N\)`, and its JSON line
  carries the required `{ts,level,session,event,msg,m,unk}` keys.
- **JSON validity on a research turn**: the perceive object parses and carries
  `m=3,unk=0,m_initial=2,unk_initial=1`; the scenario's required key set is a
  subset, so the extra fields are tolerated.
- Chat builds.

## Consequences / scope

- The perceive telemetry is now consistent with the reply on a same-turn
  research answer, and it documents the gap the research closed (initially
  `unk=1` → `unk=0`), making the self-learning loop legible.
- The change is confined to the re-answer path; turns without a re-answer are
  byte-identical to before, so no scenario / tooling that parses the legacy line
  regresses.
- Only the autonomous same-turn path sets the counts (`/research TOPIC` is an
  explicit command that doesn't re-answer a question). The displayed counts are
  the re-perception of the *original* query against the post-research KGs — a
  faithful "what I understand now"; richer per-token diffs are future polish.
