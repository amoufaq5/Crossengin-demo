# R40: Per-category cognition (classify → route → strategy)

## Status

Accepted — R40 round. Introduces ADR-0055 (input classification and
per-category routing). Builds directly on the R39A intent dispatcher
(`r39-self-identification-wiring.md`), the ADR-0031 reasoning strategies,
and the ADR-0007 plasticity model.

## Date

2026-06-08

## Context

Through R39 every user utterance ran the **same** cognitive path: perceive →
forward-chain → emit an `ACK` ("okay") or a `SEE TOPIC` word. The dispatcher
added self-identification and a single learned-triple reply on top, but the
*default* was still one undifferentiated pipeline. The observable
consequences (all reproduced by building and running
`examples/crossengin_chat.nova`):

- **"it is all okay."** A greeting, a maths question, a moral debate, and a
  confession all fell through to the cognition fallback, whose default intent
  is literally `_intent1("ACK", "okay")`. The fallback only produced something
  else when a *new* forward-chain conclusion happened to surface — which only
  occurs for the ~50 seeded health/daily-life concepts. Real-world input
  (`sky`, `democracy`, `money`, `2 + 2`) produced "okay".
- **"no signs of reasoning."** The reasoning engine *was* wired
  (`loop_reasoning_step` → `reason_forward_chain`) and *did* fire for seeded
  concepts, but it was invisible (no trace) and starved (no operators for
  real input), so it looked absent.
- **"atoms are not structured properly."** The unknown-word reply named the
  *first* token not in the language KG — so it picked stopwords ("I don't know
  **the** yet") and bare numbers ("I don't know **2** yet"). There was no
  arithmetic, no numeric atoms, no part-of-speech awareness.
- **"feedback is very dumb."** The only feedback loop was source-authority
  tier promotion (`/meta-feedback`). Nothing let the user say "that's wrong"
  and have the agent revise the *belief* that produced a reply.
- **"different approaches for different input."** Nothing classified input,
  so academic / personal / social / debatable / financial questions could not
  be treated differently even in principle.

The root cause behind all five is the same: **the substrate had no notion of
what *kind* of utterance it was handling.** R40 gives it one.

## Decision

Add a three-stage front end — **classify → route → strategy** — ahead of the
existing cognition fallback, leaving veto and self-identification untouched.

### 1. Classify (`src/perception/input_classifier.nova`, pure)

`classify_input(text) → [category, confidence_milli, signals]`. Cheap
lexical + shape signals score every category; the highest score wins, with a
fixed priority order breaking ties. The module is **pure (builtins only, no
KG)** so it is exhaustively unit-tested and can never regress cognition.

The five requested categories, plus four operational categories proposed in
this round (the question "your 5 + let me propose more" was answered "propose
more"):

| Category | Why it earns its own strategy |
|---|---|
| **academic** | definitional / explanatory — wants a *reasoned* answer |
| **personal** | the speaker's own state — wants empathy, not a causal claim |
| **social** | smalltalk — wants warmth, and must **not** write KG facts |
| **debatable** | opinion / normative — must present *both* sides, never assert |
| **financial** | money-laden — wants computation + an explicit not-advice caveat |
| **arithmetic** *(new)* | a computable expression — wants the actual number, not an atom lookup |
| **procedural** *(new)* | how-to — wants a step sequence, distinct from academic "why" |
| **greeting** *(new)* | hello / thanks / bye — a social subtype with zero KG side-effects |
| **factual** *(new)* | a *declarative assertion* the user is teaching — distinct from a question |
| **unknown** *(fallback)* | nothing matched — degrade gracefully, name the gap |

Rationale for the four additions: each is a real utterance shape that would
otherwise be mis-served by one of the five. Arithmetic and procedural are not
academic (they want computation / steps, not a definition); greeting is a
social subtype whose defining property is that it must leave the KG untouched;
factual is the *inverse* of a question (the user is the teacher) and is what a
learning loop should consume. `unknown` is the graceful floor that replaces
"okay".

### 2 + 3. Route → strategy (`src/agent/cognitive_router.nova`)

`router_reply(category, raw_msg, kg, lang, percept, now) → [reply, trace, ops]`.
Each category runs a **different** combination of *atom extraction*,
*reasoning pattern*, *learning policy*, and *response shape*:

| Category | Atoms it reads | Reasoning pattern | Learning policy | Response shape |
|---|---|---|---|---|
| academic | percept concepts | **forward-chain**; else single learned triple | durable triples (via /learn, /correct) | "X leads to Y (a→b→c)"; else names the gap |
| factual | percept concepts | corroborate against known triples | **queue the assertion to learn** | "noted — …"; echoes a corroborating triple |
| procedural | percept concepts | forward-chain as a **step sequence** | learn ordered steps | "here's a sequence I've learned: …"; else admits no procedure |
| debatable | the two options | **abductive** balance; trace only if topic fully known | belief held with **wide uncertainty**, never asserted | "both A and B have a case … I won't assert one as the truth" |
| personal | affect words | named-feeling extraction (no chaining) | **episodic**, never a global fact | empathic acknowledgement |
| social | — | none | **no KG write** | warm smalltalk |
| greeting | — | none | **no KG write** | courtesy |
| financial | percept concepts | arithmetic if numeric; else forward-chain | quantities, never eternal facts | the figure + a not-advice caveat |
| arithmetic | numeric/op tokens | **fixed-point evaluation** (`src/language/arithmetic.nova`) | — | "= 4" |
| unknown | content tokens | forward-chain if everything is known | — | names the first **content** unknown word |

Two design rules fall out of the table and matter a lot in practice:

- **Atom hygiene (fixes "atoms not structured").** Unknown-word selection now
  skips a stopword set *and* numeric tokens, so it names the first **content**
  word ("I don't know **sky**", not "the"). Numbers route to the arithmetic
  evaluator instead of becoming junk atoms.
- **Honesty over confabulation.** academic / procedural / financial name the
  knowledge gap when the subject contains an unknown word, rather than
  reaching for an incidental forward-chain over the function words that
  happened to anchor. "why is the sky blue" returns "I don't have a model of
  'sky' yet" — not a non-sequitur chain.

### Reasoning made visible

`router_reply` returns a `trace` string ("academic: forward-chain
fever→infection→symptom") that the chat prints under the agent line, and
records in the JSON log as a `category` + `reasoning` field. The reasoning
that was always running is now legible at the surface.

### Feedback that revises belief (fixes "feedback is dumb")

The `ops` element of the triple is the CSV of reasoning-operator atom ids the
reply leaned on. The chat stashes it, and:

- `/good` → `rop_observe(op, +1)` on each — reinforce the inference
- `/bad`  → `rop_observe(op, −1)` — weaken it
- `/correct S R O` → learn the right operator *and* weaken the wrong one

This drives ADR-0007 plasticity **from the conversation**, closing the loop
the source-authority meta-observer never addressed.

## Where `/learn` and federation sit (the other two reports)

- **`/learn` has no internet sequence** is correct *and by design*: the fetch
  is delegated to `scripts/learn.sh`, and triple ingestion only creates an
  operator when both endpoints already exist as atoms. The classifier closes
  half the gap — `factual` now *recognises* teachable assertions and routes
  them toward learning — but autonomous fetch remains gated on the
  network-policy + the R39D orchestrator. Documented here so the boundary is
  explicit, not silently broken.
- **"federated files won't compile"** did not reproduce: the federated unit
  suites pass (federated-aggregator 91, secure-aggregation 170, byzantine 74,
  gossip 34, distributed-rules 42 checks). The files are very large
  (`turn.nova` 117 KB, `gossip.nova` 127 KB), so the self-hosted compiler is
  slow enough that a whole-tree `make build`/`make test` can appear to hang —
  a throughput issue, not a correctness one.

## Consequences

- The chat no longer defaults to "okay"; every category has a distinct,
  honest reply, and the reasoning behind it is visible.
- New, fully unit-tested, dependency-light modules: `input_classifier`
  (35 checks), `arithmetic` (16), `cognitive_router` (15). All existing
  chat-driven integration scenarios continue to pass.
- The classifier is deliberately heuristic. The migration path to a **learned**
  classifier — category atoms whose senses the reader strengthens whenever a
  routed reply is accepted (`/good`) — slots in behind the same
  `classify_input` contract without touching the router. That is the natural
  R41 follow-up.
