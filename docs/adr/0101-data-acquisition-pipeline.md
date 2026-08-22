# ADR-0101: Data Acquisition Pipeline

## Status

Accepted (codifies R43+; documents the pipeline that R43 shipped and
every subsequent round has extended)

## Date

2026-08-15

## Context

CrossEngin does not (and MUST not) grow its knowledge by pointing a
crawler at the internet and dumping bytes into a KG. Every atom that
lands in a KG carries a **belief** (α/β pseudo-counts, ADR-0016) + a
**provenance ledger** (source_tier, license, grade, source_ts,
proof_ref — ADR-0087). Both are load-bearing: the reasoning path
weights conflicting atoms by belief × grade × source-authority, and
retract/decay/formal-pin all key on the provenance ledger. Any
ingest path that skips those fields poisons the reasoning layer.

R43 shipped the practical pipeline for bringing outside knowledge
in: importers per format, a review queue with human approval, a
web-fetch scheduler with backpressure, an LLM-extractor bridge, and
chat commands (`/ingest`, `/ingest_review`, `/ingest_approve`,
`/ingest_deny`). R55.1 added ed25519-signed skill install for the
sibling problem (external CODE, not external DATA). This ADR
retroactively documents the pipeline R43 shipped so future work has
a stable design contract to build against.

The rounds that landed pieces of this pipeline before it had an
ADR:

- **R43** — curriculum record schema + validator; ingestion
  pipeline core; review queue; source_registry; six importers
  (.cerec native records, CSV, N-Triples, Wikidata-flavored NT,
  ConceptNet 5, paper metadata, WordNet); ingestion agent;
  web-fetch scheduler; `scripts/llm_extract.sh` bridge.
- **R43 chat wiring** — `/ingest`, `/ingest_review`,
  `/ingest_approve`, `/ingest_deny`.
- **R44** — real domain packs authored through the pipeline
  (`solar_system`, `physics`, `world_history`, `religion`,
  `politics`, `biology`, `folk_astronomy`).
- **R48p7 / R55** — `ingest.review`, `ingest.approve`,
  `ingest.deny` verbs on the JSON-RPC wire.
- **R87 (existing)** — provenance ledger schema.
- **R91 / R92 (existing)** — license enforcement + governed
  promotion.

## Decision

The Data Acquisition Pipeline is a **stage machine** with six
stages, one direction, no back-channel from a later stage to an
earlier one. Every atom that ends up in a KG traveled every stage.

```
   SOURCE      FETCH       EXTRACT      REVIEW       PROMOTE      COMMIT
    |           |            |            |             |            |
    v           v            v            v             v            v
 declared    raw bytes    curriculum   human-in-    ledger-       kg_add_atom
 in a         at rest      records      the-loop     stamped       (belief
 source_       (memory      (validated   queue         atoms         starts
 registry     or            against      (approve/    (source_tier  uniform;
 entry;       disk)         schema)      deny)        + license +   evidence
 typed +                                              grade +       accumulates
 licensed                                              source_ts +   via
                                                       proof_ref)    atom_observe
                                                                     _graded)
```

Every stage's output is a well-typed data structure with an
explicit schema; malformed inputs fail at the stage they enter, not
downstream. The pipeline is EVENTUALLY-CONSISTENT and PAUSABLE at
every hop — a stage can queue for a human, restart cleanly, and
resume without duplicating a record.

### Stage 1: SOURCE — declared, not discovered

A source is registered in `src/ingest/source_registry.nova` before
its data can enter the pipeline. Each source declares:

- **name** — human-readable identifier (`solar_system.cerec`,
  `wikidata:latest-truthy`, `arxiv:cs.AI:2024-01`).
- **kind** — one of the importers R43 shipped:
  `records | csv | nt | wikidata | conceptnet | paper_meta | wordnet`.
  A new source kind is a new importer file; there is no
  "auto-detect" path.
- **default license** — `LICENSE_OPEN | CC_BY_SA | PROPRIETARY |
  OWNER | UNKNOWN` (ADR-0087). Sources of `UNKNOWN` license
  produce **quarantined** atoms — they exist in a KG but the
  clean-data query surface (`atom_is_clean`) refuses to surface
  them, and the reasoning layer treats them as excluded.
- **default grade** — the strongest grade any atom from this
  source may carry. A crawled forum post is capped at
  `TESTIMONIAL`; a peer-reviewed paper starts at
  `EMPIRICAL_STRONG`; a machine-checked proof is
  `FORMAL` (requires a `proof_ref`).
- **source_tier** — ADR-0029 authority tier.

Sources are DATA, not code. New sources register at runtime; no
NOVA source change is required to add a new .cerec file.

### Stage 2: FETCH — raw bytes at rest

`src/ingest/web_scheduler.nova` orchestrates external fetches. It
enforces:

- **Backpressure** — a per-source token bucket (concurrent with
  R56's per-token rate limit shape). Bulk crawls are refused when
  the source's bucket is empty; the caller retries later.
- **Cache-first** — bytes are cached under a content-addressed
  layout so a subsequent fetch of the same URL returns without a
  network round-trip.
- **Timeout + size cap** — every fetch has a wall-clock deadline
  and a byte cap. A fetch that exceeds either is refused and
  logged; the pipeline stops for that source until an operator
  intervenes.
- **Robot exclusion + license-check on origin** — the fetcher
  refuses a source whose `robots.txt` disallows the path OR
  whose robots response indicates a stricter license than the
  source declared.

For LOCAL sources (`.cerec` files on disk, CSV shipped in the
repo), FETCH is a no-op — the bytes are already at rest.

### Stage 3: EXTRACT — curriculum records

Every importer produces a `CurriculumRecord` (see
`src/ingest/curriculum.nova`) with a fixed shape:

```
CurriculumRecord = {
  atoms:        list<AtomSpec>    (label + kind + belief priors)
  implications: list<Implication> (LHS -> RHS + grade)
  observations: list<Observation> (atom + sign + weight)
  provenance:   {tier, license, grade, source_ts, proof_ref}
  source_tag:   "src:<origin>:<name>:<version>"
}
```

The record is a **schema-validated** intermediate — the validator
in `src/ingest/curriculum.nova` refuses malformed records BEFORE
they reach the review stage. Every atom in the record inherits the
record's provenance; per-atom overrides are permitted only to
STRENGTHEN provenance (fresher source_ts, stronger grade proof_ref
attached) — never to weaken it.

**LLM-extracted records** are a special sub-case (R43 LLM bridge).
`scripts/llm_extract.sh` runs an external LLM against unstructured
text (a paper's PDF, a scraped article). Its output is the same
`CurriculumRecord` shape as any other importer, but:

- **Source tag rewritten** — `src:extractor:llm:MODEL:RUN`
  distinguishes the LLM-extracted subset from every other source.
- **Beliefs capped at 800** — no LLM-extracted atom starts at
  Tier-A user-taught confidence (~1000); the ceiling ensures
  contradictory evidence from a peer-reviewed source overrides.
- **FORMAL implications downgraded** — an LLM can propose a
  `formal:P->Q`, but the extractor bridge downgrades it to
  `EMPIRICAL_STRONG` before the record enters review. Only the
  kernel (`src/mind/verify.nova`) may pin FORMAL, and only from a
  proof it can re-check (ADR-0088).
- **Every record enters the review queue** — no direct-to-KG
  path for LLM-extracted content, ever. `include_secrets=0`
  equivalent: the operator approves each record before atoms land.

This is the same "LLM is a preprocessor, not a reasoner" contract
ADR-0104 R48p6 documents for the NL surface. Here it applies to
data ingestion.

### Stage 4: REVIEW — human-in-the-loop queue

`src/ingest/review_queue.nova` holds every incoming record until
an operator (or an ingest-decision automation with the
`ingest:decide` capability) marks it APPROVED or DENIED. The
queue is durable (persists across daemon restart via R55.3's
snapshot round-trip), auditable (`ingest.review` verb returns
every entry's state + source + reason + submitted_at), and
supports partial approvals — a caller can cherry-pick which
records in a batch to approve.

The queue is the pipeline's **hard-gate**: no record moves to
PROMOTE without an explicit approval. This is a policy choice
(deliberately not automatic) — the R43 design decision was that a
system whose knowledge changes without human sign-off cannot be
audited after the fact. Automation of the decision is possible
(a curator with the `ingest:decide` capability could script it)
but the DECISION always leaves a trace.

Refusals of records that pass schema validation but the operator
declines carry a `reason` string. `ingest.deny {id, reason}`
persists it; the record stays in the queue in DENIED state for
audit.

### Stage 5: PROMOTE — ledger-stamped atoms

An approved record enters `src/ingest/pipeline.nova`'s promotion
path. Every atom the record contributes:

- Gets its provenance ledger stamped from the record's provenance
  block (`atom_set_provenance` with a `prov_ledger` tuple —
  `[tier, part, license, grade, source_ts, proof_ref]`).
- Runs through the **corroboration check** (ADR-0092): a claim
  already supported by another source of the same or better tier
  auto-promotes from `EMPIRICAL_WEAK` to `EMPIRICAL_STRONG`.
- Runs through the **conflict check** (ADR-0090): a claim that
  contradicts an existing pinned FORMAL atom is refused; a claim
  that merely differs from an existing empirical one lands in the
  contested-domain queue (ADR-0093 slice 4) — audit reader can
  surface both sides side-by-side without either winning
  automatically.
- Skips `LICENSE_UNKNOWN` license → **quarantined** on entry (ADR-
  0091). Quarantine means the atom exists but is invisible to
  `atom_is_clean` queries and the reasoning path.

Belief is deliberately NOT set from the record — the record's
"prior belief" hint is used to seed alpha/beta pseudo-counts at
uniform (`bel_uniform` = 1.0/1.0) unless the source's declared
grade justifies a stronger seed. The atom accumulates evidence
via `atom_observe_graded` as future records reinforce or
contradict it.

### Stage 6: COMMIT — kg_add_atom

The final stage is a straight `kg_add_atom` (or an update via
`atom_update` for a re-visit of an existing label). Every commit
writes to the decision log (ADR-0043 x ADR-0092 promotion trail)
with the source_tag, the granted grade, and the corroboration/
conflict outcome that made the commit possible. The decision log
is the audit trail — `/why LABEL` in the chat REPL walks it
backward from any atom to the original record that introduced it.

Commits are per-atom; a record with 20 atoms + 5 implications
produces 20 + 5 = 25 decision-log entries, each independently
traceable.

## The 5 ADR-0103 guarantees, preserved

The pipeline runs OUTSIDE the skill runtime, but the atoms it
produces flow INTO skills, so the guarantees still matter:

1. **Refusals short-circuit.** A record that fails schema
   validation refuses at EXTRACT; a record without an approval
   refuses at REVIEW; a quarantined atom refuses at PROMOTE.
   None of these leak through to the skill runtime.
2. **Projection ALWAYS attached.** Personas don't touch the
   pipeline directly (data acquisition is a shared concern), but
   any skill that later USES the ingested atom carries its
   persona through as usual.
3. **Effectors described-not-executed.** The pipeline itself
   dispatches no effectors — it writes to a KG. External fetches
   are governed by the web-scheduler's backpressure, not by the
   effector-gate.
4. **Meta-observer attribution.** Every atom carries its
   source_tag (`src:pack:<name>` for authored packs;
   `src:extractor:llm:<model>:<run>` for LLM records; etc.),
   distinct from `src:skill:*` and `src:pattern:*`. The
   meta-observer stores + surfaces these on every atom the
   reasoner touches.
5. **Persona READ-ONLY.** The pipeline never mutates a persona.

## Non-goals

- **No bulk auto-ingest of internet-scale corpora.** Every source
  is declared; every record is reviewed; every atom is stamped.
  A hundred-million-fact ingest is possible via the SAME
  pipeline (many batches through the review queue), but there is
  no shortcut that skips REVIEW.
- **No unattributed atoms.** Every atom carries a source_tag.
  Fabricated / anonymous / debug-only atoms use
  `src:test:*` prefixes and never enter production KGs.
- **No belief bootstrapping from LLM confidence.** An LLM
  extractor's declared confidence for a claim is metadata for the
  operator's REVIEW decision, not evidence weight. Belief
  accumulates only via corroborating observations in PROMOTE.
- **No implicit license upgrade.** An `UNKNOWN`-licensed source
  cannot promote to `OPEN` on ingest. License changes go through
  the same review path with the operator explicitly acknowledging
  the license change; the audit trail records who upgraded what
  and when.

## Options considered

1. **Straight-through auto-ingest (rejected).** Every prior
   generation of KG systems has tried this — pipe curated JSON
   into a triple store, done. Rejected because the resulting KG
   has no provenance for retract / decay / conflict resolution,
   and the reasoning layer above it becomes unauditable.
2. **Post-hoc labeling (rejected).** Ingest first, review the
   controversial atoms later. Rejected: the moment an atom lands
   in a KG, the reasoning layer starts using it. A "quarantine"
   overlay applied after the fact leaks state during the gap.
3. **Per-tier review policies (deferred).** A Tier-A user-taught
   record maybe SHOULDN'T need review. Rejected for R43 in favor
   of "every record reviews" — the automation surface is designed
   for a later round (a `curator` role with `ingest:decide`
   capability + a policy expression like "auto-approve
   `LICENSE_OPEN, EMPIRICAL_STRONG` from a declared-safe origin";
   R58+).
4. **In-process LLM extraction (rejected, ADR-0014).** Bring the
   LLM inline. Rejected because it violates ADR-0013/0014: no
   LLM in the reasoning path. The `scripts/llm_extract.sh`
   subprocess is explicitly OUT of the reasoning path — the
   subprocess writes a `CurriculumRecord`; the pipeline treats
   that record identically to any other importer's output.
5. **A single "ingest anything" pass (rejected).** Reject the six
   distinct importers in favor of a universal parser. Rejected
   because a universal parser produces vague provenance —
   "extracted from bytes" is not `src:pack:solar_system:v1`. The
   per-source importer gives the operator + audit trail a
   traceable identity for every atom.

## Consequences

- **Positive:** every atom in every KG is traceable to a source
  the operator explicitly declared, extracted through a validated
  importer, reviewed by a human (or a capability-bound
  automation), and stamped with a full provenance ledger. This is
  what `/why LABEL` walks; without this pipeline, that walk would
  bottom out at "we found this somewhere."
- **Positive:** LLM-extracted content coexists with authored
  packs + peer-reviewed papers WITHOUT special reasoning-layer
  treatment. The provenance ledger tells the reasoner which
  atoms to weight higher; the LLM sub-case is one weight class
  among several.
- **Positive:** The pipeline is DAEMON-ready (R48p7 / R55 wire
  verbs), CHAT-ready (R43 slash commands), and SCRIPT-ready
  (`scripts/llm_extract.sh` → `curriculum.nova` validator). One
  shape, three surfaces.
- **Positive:** Session snapshots (R55.3) round-trip the review
  queue with the rest of the daemon state — pending decisions
  survive restart.
- **Neutral:** Adds ~2000 lines under `src/ingest/`
  (`curriculum.nova`, `pipeline.nova`, `review_queue.nova`,
  `source_registry.nova`, `web_scheduler.nova`, `llm_extractor.
  nova`, `importers/*`) — this doc TELLS THE STORY of what R43
  already built, doesn't add code.
- **Negative:** Every ingest goes through review. Bulk imports
  are practical but not fast — an operator (or a
  `curator`-capability automation) processes each batch. The R58+
  auto-approval policies mitigate this for the trusted-source
  case; for now, human oversight is the design choice.
- **Negative:** The importer surface is per-format. A new
  format needs a new importer file. Fine at 7 importers today;
  R60+ could add a generic "structured-record adapter" for
  quick prototypes if the count grows.

## Roadmap after this ADR

- **R58 (`curator` policy expressions)** — a `curator` role
  augmented with policy predicates
  (`license == OPEN && grade >= EMPIRICAL_STRONG && source in
  {declared-safe list}` → auto-approve). Every auto-approval
  still writes a decision-log entry naming the policy that
  approved it, so the "no untraceable atom" invariant holds.
- **R59+ .cerec pattern packs** — extend the .cerec importer
  (R44) to also carry pattern-capsule directives (R53 Pattern
  Capsules can then be authored + shipped as .cerec files,
  reviewed + promoted through the same pipeline).
- **R60+ generic structured-record adapter** — add a
  configuration-driven importer for JSON/YAML sources whose
  schema is well-known (spec files, config dumps). Reduces the
  new-importer-per-format tax for one-off ingests.
- **R61+ per-source rate budgets** — the web scheduler's per-
  source token bucket becomes wire-controllable through a new
  admin verb; today it's constant per source at daemon boot.

## Ship-as-app checklist for ADR-0101

This ADR documents shipped work — the checklist enumerates what
was already in the tree at authoring time:

- [x] `src/ingest/curriculum.nova` — CurriculumRecord + validator
- [x] `src/ingest/pipeline.nova` — PROMOTE stage
- [x] `src/ingest/review_queue.nova` — REVIEW stage
- [x] `src/ingest/source_registry.nova` — SOURCE registration
- [x] `src/ingest/web_scheduler.nova` — FETCH backpressure
- [x] `src/ingest/llm_extractor.nova` — LLM subprocess bridge
- [x] `src/ingest/importers/*.nova` — 7 importers
- [x] `src/agent/ingestion_agent.nova` — orchestrator
- [x] `scripts/llm_extract.sh` — LLM-preprocessor shell helper
- [x] Chat verbs: `/ingest`, `/ingest_review`, `/ingest_approve`,
      `/ingest_deny`
- [x] Wire verbs: `ingest.review`, `ingest.approve`,
      `ingest.deny` (R48p7 / R55)
- [x] Session snapshot round-trips the review queue (R55.3)
- [x] Provenance ledger (ADR-0087) stamped at PROMOTE
- [x] Governed promotion (ADR-0092) run at PROMOTE
- [x] License quarantine (ADR-0091) enforced at PROMOTE

The pipeline is a shipped invariant. What this ADR adds is the
CONTRACT: any future change to any stage must document how it
preserves the six-stage shape, the schema-validation-per-stage
rule, and the "no atom without a source_tag" invariant.

## Role in the Model Substrate

The acquisition pipeline runs in the **mother-daemon-direct** mode
(consumption mode 1) — it is the mother's mouth. Baked children
(mode 3) inherit its output as an immutable KG slice at bake time
and never run the pipeline themselves; per-user selective-load
instances (mode 2), client apps (mode 4), and embedded deployments
(mode 5) receive the pipeline's output indirectly via signed
KG-deltas from the mother's update channel.

Within the reasoning triad this ADR feeds **nodes**: every atom that
downstream signals move, and every atom the cognitive sandbox walks,
enters existence here with a source_tag, a grade, and a provenance
ledger. Because knowledge is data (ADR-0200 Sub-decision 1) instead
of frozen weights, this pipeline is the sole entry point for the
model to gain new knowledge — there is no gradient step, no
fine-tune, no RAG index bypass. That property is what makes the
mother/child factory possible: a delta out of this pipeline is a
delta a child can apply in seconds without any re-training.

**See also:** ADR-0200 (AI-factory frame — this pipeline is the
mother's ingest arm), ADR-0203 (federated update channel — signed
KG-deltas flowing to children reuse this pipeline's provenance),
ADR-0207 (bake manifest — allowlists a slice of this pipeline's
output into a child), ADR-0202 (cognitive sandbox — consumes
pipeline output when learning).
