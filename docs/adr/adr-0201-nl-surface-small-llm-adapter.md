# ADR-0201: Sidecar Small-LLM NL Adapter (Fallback)

## Status

Proposed. Fixes the long-term shape of the small-LLM natural-language
adapter that ADR-0104 sketched as a fallback and ADR-0200 promoted to
a first-class boundary component. Establishes the sidecar subprocess
pattern (already scaffolded by R48p6 as `scripts/nl_parse_llm.sh`),
the fixed four-line wire format, the contract-enforced parser
(`src/nl/llm_parser.nova`), and the exact wire-up site inside
`_rpc_verb_nl_ask` (`src/nl/rpc_verbs.nova:510`) where the fallback
is invoked when the deterministic grammar returns `UNPARSED`. This
ADR does not itself land the wire-up; that is Phase B work. Its role
is to lock the pattern so Phase B is a mechanical stitch rather than
a design pass.

## Date

2026-08-22

## Context

The NL surface layer as specified by ADR-0104 has two parse routes:

1. A deterministic grammar parser (`src/nl/grammar_parser.nova`,
   ~15 canonical shapes at ship, expandable to 50-100 per ADR-0211).
2. An LLM-preprocessor fallback, invoked when the grammar returns
   `GRAMMAR_UNPARSED`.

R48p6 landed the second route's daemon-side plumbing:
`src/nl/llm_parser.nova` (which parses a `KIND / ARG ...` wire
format), and `scripts/nl_parse_llm.sh` (the sidecar shell script that
mirrors the four-backend pattern from `scripts/llm_extract.sh`:
ollama, llama.cpp, openai-compatible, dry-run). What R48p6 did NOT
land is the actual invocation site: `_rpc_verb_nl_ask` still hard-
refuses any `UNPARSED` input with the string
`"LLM fallback not linked yet"`. The parser exists; the executor
does not call it.

The vision in ADR-0200 requires the daemon to accept freeform
English. The deterministic grammar covers the well-formed common
case, but the long tail of natural phrasing cannot be closed by
grammar alone in the near term. A sidecar model, invoked only when
the deterministic layer fails, gives us the tail without dragging an
LLM into the reasoning path. ADR-0200 states this explicitly:
"the LLM is at the NL surface only. It never reasons. It never
decides. It does not retrieve facts."

There is a competing shape worth naming so it can be rejected: an
in-process quantized LLM (a NOVA-side inference runtime, weights
loaded at daemon boot, no subprocess). That shape trades operator
choice for latency. It is rejected as a near-term option for three
reasons:

- NOVA does not have a matmul-friendly runtime; adding one is many
  quarters of runtime work, and the standing constraint prohibits
  editing `/home/user/NOVA/src/runtime/*`.
- Vendor lock: baking a specific model into the daemon forces every
  operator onto that model, that quantization, and that license.
- Enterprise procurement: legal, medical, and finance customers must
  approve the model runner independently of the daemon; a sidecar
  boundary is exactly the abstraction their procurement process
  already knows how to review.

The primary NL surface remains LLM-free per ADR-0211. This ADR is
about the fallback shape only.

## Decision

### The sidecar is a subprocess, invoked per query

The daemon shells out to an external model runner. The runner is
provisioned by the operator; the daemon does not embed weights, does
not link against a model library, does not maintain a persistent
inference session. Each `UNPARSED` query spawns the sidecar with the
user's text on stdin (plus a schema summary as prompt context) and
reads its stdout to completion.

The sidecar script `scripts/nl_parse_llm.sh` already ships the
four-backend fan-out established by `scripts/llm_extract.sh`:

- `ollama` — talks to a locally running ollama daemon
- `llama-cpp` — invokes the llama.cpp CLI binary
- `openai` — hits any OpenAI-compatible HTTP endpoint (self-hosted
  vLLM, a bring-your-own-key hosted endpoint, a corporate proxy)
- `dry-run` — emits a fixed response, for tests and CI

Selection is by env var (`CROSSENGIN_NL_LLM_BACKEND`). No backend is
required at build time. If the env var is unset or the chosen backend
fails to launch, the fallback declines and the RPC call refuses at
the daemon boundary (rather than silently degrading).

### The wire format is fixed and minimal

The sidecar returns exactly four lines on stdout:

```
KIND <one of the 12 enum values>
ARG1 <value or empty>
ARG2 <value or empty>
ARG3 <value or empty>
```

`KIND` is drawn from the frozen set of 12 recognized query kinds:
`RESEARCH`, `RELATE`, `CONTRADICT_SCAN`, `IS_A`, `RETRACT`,
`CAPSULE_INSTALL`, `SKILL_INSTALL`, `CAPSULE_LIST`, `SKILL_LIST`,
`SKILL_RUN`, `PERSONA_PROJECT`, `UNKNOWN`. Any other `KIND` value is
rejected as malformed. Any missing line, extra line, or wrong header
is rejected as malformed. The parser does not attempt best-effort
recovery.

`llm_parse_wire` in `src/nl/llm_parser.nova` performs this validation
before any StructuredQuery is constructed. The output of the
validator is either a fully typed StructuredQuery record or a
refusal, tagged `src:parser:llm:MODEL:RUN` for meta-observer
attribution.

### The LLM cannot extend the query_shape enum

Contract enforcement is the load-bearing property. The 12 KIND values
are hard-coded in `src/nl/query_shape.nova`. The parser has no
extension point that lets the LLM invent a new query shape at
runtime. If the sidecar wants to route a query in a new way it must
first ship as a grammar pattern or an HDC prototype vector in the
deterministic layer (ADR-0211). This preserves the ADR-0200
invariant: the LLM is at the boundary, not inside the reasoning
path, and it cannot bypass the reasoning invariants by inventing new
kinds of question the executor does not know how to handle safely.

### Wire-up site

The stitch happens between `grammar_parse` and `nl_execute_scoped`
inside `_rpc_verb_nl_ask` at `src/nl/rpc_verbs.nova:510`. The current
shape refuses when `kind == UNPARSED`. The Phase B change replaces
that refusal with:

- invoke `scripts/nl_parse_llm.sh` with the user's text
- pass stdout through `llm_parse_wire`
- on success, feed the resulting StructuredQuery to
  `nl_execute_scoped` exactly as if the grammar had parsed it
- on failure or if the sidecar is unavailable, refuse cleanly with a
  human-readable reason

The `nl_execute_scoped` signature does not change. The R60 overlay-
scoped path (holder-checked skill visibility, ownership gate) applies
uniformly whether the parse came from grammar or from the sidecar.
The five ADR-0103 guarantees are preserved by dispatching through
the same executor with the same skill_run path.

### Fallback-rate metric

Every invocation of the sidecar is counted per-holder against a
cap-token qps budget (`qps_max` on the R54 capability token). The
count is reported through the meta-observer as
`nl.llm_fallback.count` and via a wire verb `nl.metrics` (Phase C).
The purpose is not billing; the purpose is to give the deterministic
layer team a metric that says "here is how much natural language
your grammar / HDC classifier is not yet covering." The metric
drives investment in ADR-0211 work: each new grammar pattern moves
some real query volume off the sidecar and onto the fast path.

The design goal is that this rate trends toward zero over time. It
never reaches zero (the long tail is genuinely long), but a healthy
deployment sees it under 5 percent of queries and dropping.

### Test mode

An env var `CROSSENGIN_NL_LLM_TESTMODE=1` swaps the sidecar
invocation for a deterministic mock. Tests set the mock's return
value per-case; the daemon path is unchanged. The `dry-run` backend
in `scripts/nl_parse_llm.sh` is the same shape and can be used
outside NOVA test harnesses.

## Consequences

### Positive

- No in-process LLM inference. The daemon runs without linking a
  model runtime; the runtime-off-limits constraint is satisfied
  without contortion.
- Operator chooses the model. Enterprise procurement approves the
  runner once and swaps it as their policy evolves; the daemon is
  agnostic.
- Contract-enforced parse output. The LLM cannot introduce a new
  query kind that bypasses the executor's dispatch table, cannot
  extend the reasoning surface, cannot smuggle answer text into the
  parse phase.
- Latency floor is the deterministic grammar. Common queries never
  invoke the sidecar. The sidecar's cost is paid only by phrasings
  the grammar has not yet learned.
- Metric-driven investment. The fallback rate makes the ADR-0211
  work measurable: each pattern shipped translates to a measurable
  drop in tail cost.

### Negative

- Per-query subprocess cost. Spawning a shell script per fallback
  query has a real overhead (tens of milliseconds on typical
  hardware, before the model runs). This is acceptable because the
  fast path is deterministic and the fallback is by construction the
  tail; but sustained sidecar traffic will feel slow.
- Operator burden. The operator must provision a model runner
  (ollama, llama.cpp, an OpenAI-compatible endpoint). A daemon
  without a runner refuses on any query the grammar cannot parse.
  Documentation must cover the four backend recipes.
- No graceful degradation to a lesser sidecar. If the runner is
  down, the fallback refuses. Callers see a refusal, not a stale or
  approximate answer. This is the intended behavior — a wrong answer
  is worse than no answer under the ADR-0200 vision — but it must be
  documented so operators are not surprised.

### Neutral

- Model-choice is an operator concern, not a code concern. Which
  model is best for the parse task is out of scope here and will
  vary with locale, domain, and latency budget.
- Prompt template lives in the shell script, not in NOVA. Updating
  the prompt is a script edit, not a daemon rebuild.

## Alternatives Considered

1. **In-process quantized LLM (rejected).** Would need a NOVA-side
   matmul runtime the language does not have; would force a model
   choice on every operator; would drag inference into the same
   process as reasoning. Rejected on runtime, procurement, and
   architectural grounds.

2. **Sidecar returning JSON instead of the four-line format
   (rejected for the near term).** JSON is more expressive but
   invites unbounded extension. A fixed four-line format keeps
   parse validation trivial and gives the LLM no room to invent
   fields the executor does not know how to consume. JSON can be
   revisited when the query kinds grow past what four lines
   comfortably express.

3. **LLM as a persistent inference session over a socket
   (deferred).** Would amortize the per-query subprocess cost. Worth
   it once the fallback rate is high enough to justify a supervised
   sidecar; premature while the goal is to drive fallback traffic
   toward zero.

4. **No fallback at all — grammar refuses everything it cannot parse
   (rejected).** ADR-0211 is aspirationally where we end up, but
   only after the grammar and HDC classifier cover the vast bulk of
   real queries. A daemon that refuses arbitrary English on day one
   is a much smaller product than the vision requires.

5. **Multiple sidecars in parallel, vote on the parse (rejected).**
   Adds complexity without a clear win. If one runner produces a
   valid contract-conforming parse and another does not, the
   validator already refuses the bad one; if both produce valid
   parses but disagree on kind or args, we cannot pick a winner
   without a tie-breaker that is itself either arbitrary or another
   layer of policy. Not worth the design surface.

## See Also

- ADR-0104 — NL surface layer; the parent design this ADR realizes.
- ADR-0200 — Mother/Child factory; the north-star that specifies
  the small-LLM's role as boundary-only.
- ADR-0211 — LLM-free NLP as primary path; this ADR is the fallback
  side of that pair.
- ADR-0103 — Skill runtime; the five guarantees the executor
  preserves regardless of parse route.
- R48p6 — the round that landed the sidecar script and parser
  module; the Phase B stitch consumes this work directly.
- `src/nl/llm_parser.nova` — parser implementation and
  `llm_parse_wire` entry point.
- `src/nl/rpc_verbs.nova` — verb dispatch; wire-up site at line 510.
- `scripts/nl_parse_llm.sh` — sidecar script with the four backends.
