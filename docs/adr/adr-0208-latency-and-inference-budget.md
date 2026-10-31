# ADR-0208: Latency and Inference Budget (Parity with LLMs)

## Status

Proposed. Establishes per-query-kind latency budgets that keep the
daemon competitive with representative LLM chat latency, and locks a
regression harness that fails any round shipping a slowdown beyond
budget. ADR-0200 makes latency parity with LLMs a hard requirement;
this ADR is how the requirement is enforced.

## Date

2026-08-22

## Context

Nobody uses a slow model. If a CrossEngin child takes three seconds
to answer "what is X" while an LLM chat replies in 400 milliseconds
with a plausible (if occasionally wrong) answer, the user picks the
LLM regardless of what the audit trail or the confidence report
looks like. Vision requires parity; parity requires a discipline.

The daemon's design is amenable to fast paths:

- KG lookups are indexed. `src/kg/index/*` provides adjacency and
  label indexes; a `research` walk over a single topic is bounded
  by the topic atom's out-degree.
- HDC embeddings are cached. `src/kg/hdc_embed.nova` maintains a
  vector cache; a warm cache turns similarity into a table lookup.
- Skill dispatch is a switch. `src/skills/skill_dispatch.nova` uses
  integer dispatch keyed by skill id; no reflection, no map lookup
  per invocation.
- Templater is deterministic and stateless (ADR-0104); its runtime
  is a function of the ProposalResult size.

What is missing is the discipline. Without an explicit budget and a
harness that enforces it, latency drifts on any round that does not
watch it.

## Decision

### Per-query-kind latency budgets (initial)

These are the shipping targets on a modest reference host (single-
CPU, warm caches, one active connection):

| Query kind | Budget (p50) | Budget (p99) |
|---|---|---|
| `is_a` (single-atom traversal) | 100 ms | 250 ms |
| `research` (one topic) | 200 ms | 500 ms |
| `relate` (two topics) | 300 ms | 700 ms |
| `contradict_scan` | 500 ms | 1200 ms |
| `skill_run` (echo) | 50 ms | 150 ms |
| `skill_run` (research) | 300 ms | 800 ms |
| `capsule.list` / `skill.list` | 50 ms | 150 ms |
| `nl.parse` (grammar path) | 20 ms | 60 ms |
| `nl.parse` (grammar unparsed) | 30 ms | 100 ms |

These are initial numbers. The benchmark harness (below) will refine
them; the shape of the budget table stays.

### Fast-path constraints

To hit the budgets, the fast paths obey these rules:

- Indexed KG lookup. No scan-and-filter over the atom table for
  any hot verb. The R70 adjacency index and label index are
  mandatory for any traversal on the hot path.
- Warm HDC embedding cache. Cache size defaults are sized so that
  the working set of a representative domain fits; misses are a
  cold-start tax, not a steady-state tax.
- Integer-switch skill dispatch. No string lookup at invocation
  time. `skill_dispatch` reserves integer ids at install.
- Single-record templater. The default style templater walks the
  ProposalResult in one pass; recursion is bounded by the
  ProposalResult's depth (small by construction).
- No sync I/O on the hot path. Ingest, review, and audit-log flush
  are async; the hot path never blocks on disk.

### Out of scope

- **Sidecar LLM parse latency (ADR-0201).** The sidecar's latency
  is a function of the operator's model choice and is not the
  daemon's responsibility. The `nl.parse (grammar unparsed)` row
  in the table above does NOT include sidecar wall-clock; if the
  sidecar is invoked, the total wall-clock is
  `daemon_time + sidecar_time` and is reported as such.
- **Cold-start latency.** First query after boot pays the index-
  build and cache-warm costs. The budget table is a steady-state
  target.
- **Multimodal ingest latency.** ADR-0202 perceptual atom
  extraction is a review-queue path, not a hot path. Its latency
  is budgeted separately once the multimodal epic (ADR-0200 R120+)
  lands.

### Benchmark harness

A wall-clock harness lives at `bench/latency_v1/`. Its shape:

- **Real corpus.** A representative KG with approximately 10^5
  atoms, 10^6 edges, drawn from a mix of encyclopedia-scale (broad,
  low-depth) and technical-scale (narrow, high-depth) domains.
- **Real queries.** A hand-curated list of ~200 queries per kind,
  drawn from realistic user phrasings.
- **Wall-clock.** No microbenchmark stubbing; queries hit the
  running daemon over the wire, timed at the client side.
- **Per-kind report.** Output is a per-kind p50 / p95 / p99 table
  plus a per-verb call-chain breakdown so a regression is
  localizable.
- **Baseline artifact.** Each round's harness output is committed
  to `bench/latency_v1/baselines/` so subsequent rounds can diff
  against the prior baseline.

### Regression gate

The CI harness runs the benchmark per PR against the committed
baseline. A PR that:

- Regresses any p99 by more than 10 percent beyond budget, OR
- Introduces a new query kind without a budget row,

fails the check. The PR author can either fix the regression or
propose a budget bump with justification in the PR description
(reviewers can accept the bump if the change is worth it).

The harness is not the ADR; the ADR is the discipline. Rounds that
land the harness itself and successive tuning rounds are Phase B
work.

### Implementation status

- **R106 (Phase H) — harness IMPLEMENTED.** The harness described
  above ships in tree as `tests/benchmark/bench_nl_verbs.nova` +
  `tests/benchmark/kg_synthetic_loader.nova` +
  `scripts/bench_nl_verbs.sh`, wrapped by three Makefile targets
  (`bench-nl`, `bench-nl-compare`, `bench-nl-baseline`). The
  `crossengin-bench-v1` JSON payload emitted matches
  `scripts/bench.sh`; `--compare` exits 2 on any phase whose
  `median_ns` regresses past 1.5× baseline.
- **Baseline PENDING permissive-host capture.** The shipped
  `bench/latency_v1/baseline.json` is an empty stub; the container
  this repo currently ships in has broken `nanotime()` (see
  `docs/NOVA_RUNTIME_GAPS.md` R-2), so measurements from here would
  all be zeros. The harness gracefully skips on a broken-clock host
  (prints `SKIP: nanotime not functional …` and exits 0). Capture
  the real numbers on a permissive host via
  `make bench-nl-baseline` and commit the resulting JSON.
- **CI hookup PENDING.** No CI workflow file lives in the tree
  yet (`docs/SHIP_AS_APP.md` §12 notes CI is Makefile-driven); the
  exit-2 semantics are ready for a workflow when one lands.

## Consequences

### Positive

- Real performance discipline. Rounds are held to explicit budgets;
  latency does not silently drift.
- Commitment to parity is documented, not implicit. Customers
  evaluating CrossEngin against an LLM chat see a specific budget
  table; benchmark reports show pass or fail.
- Competitive framing. "Slower than LLMs" was the industry-default
  assumption for a KG-based system; this ADR is the artifact that
  says otherwise.
- Design vetoes. A round that proposes a fancy new inference path
  that misses budget gets vetoed on latency grounds — a cheap
  design gate.

### Negative

- Budget tuning is real work. Initial numbers are guesses; the
  first few rounds of the harness will surface either headroom
  (budgets too loose, tighten them) or misses (budgets too tight,
  fix the fast path or bump the budget with justification).
- Some designs get vetoed. A neat idea that adds 500 ms to
  `research` fails the check; the design is either revised, gated
  behind a slow-path toggle, or does not ship.
- Harness maintenance. The reference corpus and query set need to
  evolve as the daemon's capabilities grow; a stale harness is
  worse than none.

### Neutral

- Budgets are per-kind, not per-verb. Some verbs (`skill.run`) span
  multiple kinds; the budget applies to the invoked kind, not the
  verb name.
- p50 and p99 are both budgeted. p50 is what feels fast; p99 is
  what avoids tail-latency complaints. Both matter.

## Alternatives Considered

1. **No explicit budget, best-effort (rejected).** ADR-0200's
   parity requirement becomes a soft claim without a gate; latency
   drifts.

2. **Micro-benchmarks per module (partial, insufficient).** Useful
   for pinpointing regressions but does not answer "does the
   daemon meet the user-facing budget." The wall-clock harness is
   the load-bearing measurement; module benchmarks are the
   localization tool.

3. **Budget by verb rather than by kind (rejected).** Verbs vary
   too widely (`skill.run` covers everything from echo to
   research). Kind-level budgets are the tighter contract.

4. **Include sidecar LLM latency in the budget (rejected).** The
   sidecar's latency is not the daemon's to control. Reporting the
   two components separately is more honest.

5. **Budget by hardware profile (partial, not-yet).** A modest-host
   budget is what ships now; a per-tier table (laptop / server /
   HPC) is a candidate for a follow-on ADR when the deployment
   inventory demands it.

## See Also

- ADR-0200 — Mother/Child factory; the parity requirement.
- ADR-0207 — RAG obsolescence; the "no waiting on retrieval"
  fast-path argument.
- ADR-0211 — LLM-free NLP primary path; ensures the fast path does
  not touch the network.
- ADR-0201 — Sidecar LLM adapter; the fallback whose latency is
  reported separately.
- ADR-0100 — MSC signal propagation timing.
- `bench/latency_v1/` — the harness (Phase B).
- `src/kg/index/*` — the indexes that hot verbs rely on.
- `src/kg/hdc_embed.nova` — the HDC cache.
- `src/skills/skill_dispatch.nova` — integer-switch dispatch.
