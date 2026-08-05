# ADR-0104: NL Surface Layer — grammar-first + LLM-preprocessor fallback

## Status

Proposed

## Date

2026-08-15

## Context

Everything CrossEngin does today happens through slash-commands
(`/assert`, `/ingest`, `/skill run research ...`, `/persona
project ...`). That's fine for the operator + author roles but hard
to sell as "an AI you can talk to." The user's R45 R50 goal was
explicit: ship this as an app where people ask questions in English
and get answers with sources.

What we have that lets that happen:

- **Skill runtime (ADR-0103, R47 complete)** — `skill_run` is the
  canonical way to compose knowledge + persona + safety into a
  proposal for a user problem. Every NL question, at its deepest
  layer, invokes a skill.
- **Persona (ADR-0102)** — provides the projection that turns "here
  are the facts" into "here's what you should think about it given
  your history." Also carries the preferred style reference.
- **Capsules (ADR-0106)** — the knowledge pool a skill walks.
- **The 5 hard guarantees from ADR-0103** — refusals short-circuit,
  projections always attach, effectors described-not-executed,
  attribution, persona read-only. Any NL surface MUST preserve
  these; it cannot go around them.

What's missing:

1. **A parser** that turns "what do you know about the sun?" into a
   structured invocation like `{skill:research, topic:"the sun"}`.
2. **A query executor** that maps structured invocations onto skill
   supervisors + runs them.
3. **A templater** that turns the structured `ProposalResult` back
   into readable English (or JSON for a machine client).
4. **A stable client-facing protocol** (JSON-RPC) so web/mobile
   frontends can talk to the daemon.

The user's R45 answer to the NL question was "both" — grammar-based
primary parser (LLM-free, deterministic, auditable) + LLM-preprocessor
fallback for anything the grammar doesn't recognize (under the
existing ADR-0013/0014 stance where the LLM emits STRUCTURED QUERIES,
never answers).

This ADR names the four components and their contracts.

## Decision

We introduce a four-piece **NL Surface Layer**:

1. **Grammar parser** (`src/nl/grammar_parser.nova`) — a small,
   LLM-free deterministic parser that recognizes ~15 canonical
   question shapes and translates them into structured queries.
   Handles ~80% of well-formed questions on the domains we ship.
2. **LLM-preprocessor parser** (`src/nl/llm_parser.nova` +
   `scripts/nl_parse_llm.sh`) — invoked only when the grammar
   returns UNPARSED. Prompt-constrained to emit a StructuredQuery
   record (never a natural-language answer). Under ADR-0013/0014:
   LLM in the parse path, NEVER in the answer path.
3. **Query executor** (`src/nl/executor.nova`) — dispatches a
   StructuredQuery to the appropriate skill supervisor via
   `skill_run`. Preserves all 5 ADR-0103 guarantees. Returns the
   raw ProposalResult.
4. **Templater** (`src/nl/templater.nova`) — LLM-FREE deterministic
   renderer that turns a ProposalResult + persona.style_capsule_ref
   into English. Style capsule (ADR-0108) configures phrasing;
   default style ships in-line.
5. **JSON-RPC daemon surface** (`src/nl/rpc_verbs.nova`) — 12
   verbs that map onto the NL layer + admin commands, so any
   web/mobile client speaks the same wire protocol as the chat.

### Component 1: Grammar parser

Small handwritten recognizer over ~15 canonical patterns. All
patterns emit a `StructuredQuery` record; unrecognized input yields
`GRAMMAR_UNPARSED` and control passes to the LLM fallback.

Recognized shapes (v1):

| Pattern | Emits |
|---|---|
| `what is X` / `what are X` | `{kind: RESEARCH, topic: X}` |
| `what do you know about X` | `{kind: RESEARCH, topic: X}` |
| `tell me about X` | `{kind: RESEARCH, topic: X}` |
| `does X relate to Y` | `{kind: RELATE, a: X, b: Y}` |
| `does X contradict Y` | `{kind: CONTRADICT_SCAN, a: X, b: Y}` |
| `is X a Y` | `{kind: IS_A, x: X, y: Y}` |
| `who is X` | `{kind: RESEARCH, topic: X, kind_filter: ATOM_CONCEPT}` |
| `when did X happen` / `when was X` | `{kind: RESEARCH, topic: X, kind_filter: ATOM_FACT}` |
| `where is X` | `{kind: RESEARCH, topic: X}` |
| `why X` | `{kind: RESEARCH, topic: X}` (heuristic; upgraded when a proof-search skill lands) |
| `retract X` | `{kind: RETRACT, label: X}` |
| `install capsule X` | `{kind: CAPSULE_INSTALL, name: X}` |
| `install skill X` | `{kind: SKILL_INSTALL, name: X}` |
| `list capsules` / `list skills` | `{kind: CAPSULE_LIST}` / `{kind: SKILL_LIST}` |
| `run skill X on Y` | `{kind: SKILL_RUN, skill: X, arg: Y}` |

Parser is deterministic byte-walking: tokenize (per the same
`persona_project` tokenizer already used), pattern-match against
the first N tokens, emit the query. Failure is graceful — return
`GRAMMAR_UNPARSED` with the tokenized input so the LLM fallback can
work from the same tokens.

### Component 2: LLM-preprocessor parser

Invoked only when grammar returns `GRAMMAR_UNPARSED`. The LLM
receives the raw user text + the schema of `StructuredQuery`
records + a strict "emit ONE record; no prose; no answer content"
prompt. Same safety wall as `scripts/llm_extract.sh`
(ADR-0013/0014):

- Source tag on any observation the query later creates:
  `src:parser:llm:MODEL:RUN`
- Output validated against StructuredQuery schema; malformed →
  refused, not answered
- LLM output NEVER leaves this layer — the executor consumes the
  StructuredQuery and produces its own answer via the skill
  runtime + templater. LLM cannot write the response the user sees.

Prompt template lives inline in `scripts/nl_parse_llm.sh` (mirrors
the extract helper's four-backend design: ollama / llama-cpp /
openai-compatible / dry-run).

### Component 3: Query executor

```
nl_execute(query, kg_registry, capsule_registry, persona_registry,
           skill_registry, mo, user_id, now) -> ExecutionResult

ExecutionResult = [
  ok:                 0/1
  proposal_result:    ProposalResult (from skill_run)
  parser_used:        "grammar" | "llm" | "none"
  query:              StructuredQuery
  templated_answer:   string (English -- filled by templater)
  refusal_reason:     string
]
```

Dispatch table:
- `RESEARCH` → skill_run on installed `research` skill (auto-install
  if uninstalled + not gated by refusal conditions)
- `RELATE` / `CONTRADICT_SCAN` → skill_run on `research` with a
  compound topic; templater surfaces the cross-KG conflict portion
- `RETRACT` / `CAPSULE_*` / `SKILL_*` → forward to the same admin
  functions the slash-commands invoke (`_admin_retract`,
  `_admin_capsule_install`, etc.); templater wraps in English

Every skill invocation goes through `skill_run` — all 5 hard
guarantees preserved. Persona is looked up by `user_id` from the
persona_registry and passed through. No shortcuts.

### Component 4: Templater

LLM-FREE deterministic renderer. Given:
- `ProposalResult` (structured)
- Optional `style_capsule` reference (from persona)
- Optional language hint

Produces a plain-English string. Ships with an in-line default
style (concise, cite-sources, hedge-uncertain) that renders every
ProposalResult in a consistent, readable shape:

```
<one-line direct answer>

Sources:
  - src:pack:solar_system:v1 says X believes 950 milli
  - src:pack:folk_astronomy:v1 says X believes 200 milli

⚠ These sources DISAGREE on X (belief spread 750 milli).
  Persona projection: predicted valence +425, risk score 500.
```

Style capsules (ADR-0108) override the default with author-supplied
templates for formal/casual/academic/technical registers.

Templater IS deterministic. Given the same ProposalResult + style,
it always produces the same string. This is a design commitment,
NOT a limitation — it's what makes the layer auditable and
LLM-free.

### Component 5: JSON-RPC daemon surface

Stable wire protocol for external clients (web app, mobile,
CLI over TCP, IDE plugin). All verbs return `{ok, result, error}`.

| Verb | Args | Returns |
|---|---|---|
| `nl.ask` | `{text, user_id}` | `ExecutionResult` |
| `nl.parse_only` | `{text}` | `StructuredQuery` (for debugging) |
| `kg.list` | `{}` | list of KG names |
| `capsule.list` | `{}` | list of capsules + install state |
| `capsule.install` | `{name}` | install status |
| `skill.list` | `{}` | list of skills + install state |
| `skill.run` | `{name, arg}` | ProposalResult |
| `persona.show` | `{user_id}` | persona record |
| `persona.project` | `{user_id, proposal}` | Projection |
| `ingest.review` | `{}` | queue entries |
| `ingest.approve` | `{id}` | status |
| `ingest.deny` | `{id, reason}` | status |

Wire format: JSON. Server: lives in `src/nl/rpc_server.nova` +
`crossengin_daemon.nova` binds a socket. Client libraries can be
written in any language.

### The 5 ADR-0103 guarantees, preserved end-to-end

| Guarantee | Where enforced in NL surface |
|---|---|
| 1. Refusals short-circuit BEFORE policy | executor calls `skill_run` unchanged |
| 2. Projection ALWAYS attached | executor never strips it |
| 3. Effectors DESCRIBED not executed | executor + templater surface `effector_calls` in the answer but don't dispatch |
| 4. Meta-observer attribution | `skill_run` handles this; NL layer adds `src:parser:{grammar|llm:...}` tags for any observation the query records |
| 5. Persona READ-ONLY | executor passes persona by ref; templater only reads style_capsule |

The NL layer adds ZERO new enforcement authority. Every safety
check that gates a slash-command also gates its NL equivalent.

## Options Considered

1. **Grammar + LLM hybrid (CHOSEN, per user R45).** Grammar first
   (deterministic, cheap, auditable). LLM only when grammar can't
   parse. Best of both: predictable primary path + graceful
   fallback for arbitrary phrasing.
2. **Grammar only.** Fully LLM-free but rejects any question
   outside the ~15 recognized patterns. Rejected as too narrow to
   feel like Claude/ChatGPT.
3. **LLM only for parsing.** Simpler code. Rejected: every
   question — even trivial ones — needs an LLM round-trip. Cost,
   latency, and vendor lock-in for basic queries.
4. **LLM for both parse AND answer.** Would work. Rejected: the
   whole ADR-0014 stance is "no LLM in the answer path" — this
   would violate the design commitment MSC is built on.
5. **Structured-only interface (no NL, ship as a REST API).**
   Cheapest. Rejected in R45: goal is app-shaped user experience,
   not a developer-only API surface.

## Consequences

- **Positive:** Users get "ask a question in English → answer with
  sources + persona projection + audit trail." The ship-as-app
  path (R50) opens up.
- **Positive:** Auditable primary path. `nl.parse_only` returns
  the StructuredQuery a text parsed to, so users can inspect
  WHAT the system understood — separate from HOW it answered.
- **Positive:** LLM cost bounded to the fallback path. Common
  queries (grammar-covered) never touch an LLM. Cost scales with
  arbitrary phrasing, not with query volume.
- **Positive:** Every skill remains driveable via `/skill run` too
  — the NL layer is ADDITIVE, not replacement. Power users keep
  the slash-command interface.
- **Neutral:** Adds ~5 modules under `src/nl/`. Estimated ~2000
  lines total across parser + executor + templater + rpc.
- **Negative:** Grammar coverage is the primary UX ceiling for a
  while. Real usage will surface question shapes we didn't
  anticipate; extending the grammar is one-file-per-pattern.
- **Negative:** Templater's deterministic phrasing will feel
  stilted next to LLM prose. Style capsules (ADR-0108) mitigate
  but don't eliminate. This is the accepted tradeoff for
  auditability.
- **Future work:** Multi-turn context (follow-up questions
  referencing prior answers) is deferred to a follow-on ADR.
  v1 treats each `nl.ask` as an independent query with the
  persona as the only carry-over.

## Implementation Notes

**Modules to add:**

```
src/nl/query_shape.nova        StructuredQuery shape (kind + typed args)
                                + kind constants (RESEARCH, RELATE,
                                CONTRADICT_SCAN, IS_A, RETRACT,
                                CAPSULE_INSTALL, SKILL_INSTALL,
                                CAPSULE_LIST, SKILL_LIST, SKILL_RUN)
                                + accessors + validator.

src/nl/grammar_parser.nova     Deterministic recognizer for ~15
                                canonical question shapes. Returns
                                StructuredQuery or GRAMMAR_UNPARSED.

src/nl/llm_parser.nova         Loads an LLM-emitted StructuredQuery
                                (from stdin or a file written by
                                scripts/nl_parse_llm.sh), validates
                                the shape, tags source
                                src:parser:llm:MODEL:RUN.

src/nl/executor.nova           Dispatches StructuredQuery to skill
                                supervisor / admin function. Returns
                                ExecutionResult. Preserves ADR-0103
                                guarantees.

src/nl/templater.nova          Deterministic ProposalResult -> English.
                                Ships with an in-line default style;
                                consults persona.style_capsule_ref if
                                set (ADR-0108).

src/nl/rpc_verbs.nova          12 JSON-RPC verbs. Serializes
                                ProposalResult / ExecutionResult /
                                StructuredQuery as JSON.

scripts/nl_parse_llm.sh        Same 4-backend pattern as
                                scripts/llm_extract.sh (ollama,
                                llama-cpp, openai, dry-run). Writes
                                a StructuredQuery-shaped JSON that
                                llm_parser.nova consumes.
```

**Files to extend:**

```
examples/crossengin_chat.nova  Route free-text (no leading '/')
                                through nl_execute; print
                                templated_answer.

examples/crossengin_daemon.nova
                                Bind an RPC socket + dispatch to
                                nl/rpc_verbs.
```

**Rollout sequence (R48):**

1. This ADR (0104). Done.
2. `src/nl/query_shape.nova` + tests. Base shape everything else
   references.
3. `src/nl/grammar_parser.nova` + tests. The ~15 patterns.
4. `src/nl/executor.nova` + tests. Dispatch table.
5. `src/nl/templater.nova` + tests. Default style ships in-line.
6. Chat wiring: free text routes through NL executor + templater.
7. `src/nl/llm_parser.nova` + `scripts/nl_parse_llm.sh`. LLM fallback.
8. `src/nl/rpc_verbs.nova`. JSON verbs + daemon binding.
9. Ship as app (R50) — this is where the frontend + installer live.

**Test plan (per ADR-0102 format):**

For each canonical grammar pattern:
- `test_grammar_<pattern>` — well-formed input → correct StructuredQuery
- `test_grammar_<pattern>_variant` — spacing / capitalization variants
- `test_grammar_<pattern>_negative` — near-miss doesn't match (returns UNPARSED)

For the executor:
- `test_executor_research_dispatches_to_skill`
- `test_executor_refusal_short_circuits_before_skill_call`
- `test_executor_persona_projection_attached`
- `test_executor_effectors_described_not_executed`
- `test_executor_attribution_flows_to_meta_observer`
- `test_executor_persona_readonly`

For the templater:
- `test_templater_deterministic` — same input → same string, always
- `test_templater_sources_listed` — each src:* tag surfaces
- `test_templater_disagreement_surfaced` — cross-KG conflicts
  formatted as first-class output
- `test_templater_persona_projection_line`
- `test_templater_effector_calls_listed`

For LLM fallback:
- `test_llm_parse_valid_query_accepted`
- `test_llm_parse_malformed_refused`
- `test_llm_parse_attribution_tag_present`

For RPC verbs:
- End-to-end: `nl.ask` returns full ExecutionResult with English
  templated answer + StructuredQuery + persona projection.

**Reference test scenario (the vision moment via NL):**

```
> what do you know about the sun?

[grammar] parsed as RESEARCH topic="the sun"
[executor] dispatched to skill 'research' (auto-installed)
[templater]

Based on 12 atoms across 7 KGs, here's what I know about "the sun":

The sun is a star (astronomy pack, belief 1000/1000). It is a G-type
star (astronomy pack, belief 900/1000). It engages in hydrogen
fusion (physics pack, belief 900/1000).

⚠ Sources DISAGREE on 'sun':
  - src:pack:solar_system:v1 believes 1000 milli
  - src:pack:folk_astronomy:v1 believes 200 milli
    (spread 800 milli, threshold 300)

Persona projection (advisory):
  predicted valence shift: 0 (no relevant history)
  risk score:              500 (neutral)
  matching preferences:    0
```

Same content today via `/skill run research the sun` — that's the
point: the NL layer is a wrapper, not a rewrite.

DEPENDS ON: ADR-0103 (Skill Runtime — the executor invokes
`skill_run`), ADR-0102 (Persona — projection attached),
ADR-0013 + ADR-0014 (LLM never in answer path — enforced by
having the LLM only emit StructuredQuery, never templated text),
ADR-0028 (source_whitelist — applies to the LLM parser's outbound
call).
FEEDS INTO: ADR-0108 (Style Capsules — configure the templater),
ADR-0111ish (multi-turn context — deferred), R50 ship-as-app
(the frontend consumes the JSON-RPC verbs).
