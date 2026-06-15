# ADR-0093: Domain rollout strategy — math/logic/CS first

## Status

Proposed

## Date

2026-06-15

## Context
ADR-0086 frames CrossEngin as a truth-seeking engine that must eventually cover
the breadth of human knowledge — a dozen-plus broad domains, from mathematics to
medicine to politics. It does not say in what *order* to build them, and order is
not a detail: it determines what the engine can credibly claim early, how much
licensing risk it takes on, and whether the hard machinery (formal verification,
defeasible debate) gets stress-tested on clean ground before it meets the messy
ground. A small, bootstrapped team cannot open all domains at once; each domain is
a large curation effort, and opening one badly poisons the substrate's confidence.
We need a sequencing decision and a gate that says when a domain is *ready*.

The forces pull together rather than apart. The ADR-0086 thesis — that CrossEngin
*out-reasons* LLMs — is only credible if it is *measured*, not asserted, and you
can only measure correctness where correctness is objectively checkable.
Mathematics, logic, and computer science are exactly that domain: theorems, proofs,
type judgments, and algorithm-correctness facts are right or wrong independent of
opinion, so they let the proving ground (ADR-0086 Phase 2) actually settle the
claim. They are also the domain that most directly exercises the formal path
(ADR-0088) and strict arguments (ADR-0089) — building them first means the
proof checker and the strict-vs-defeasible split get hardened on the cleanest
possible inputs before any empirical or contested knowledge arrives. And they are
the cleanest on Rule 3: most foundational math/CS knowledge is open, or is
fact-not-expression and so not copyrightable, making the first ingestion pipeline
the least licensing-fraught one we will ever build.

The alternative orderings all front-load risk. Going after the highest-commercial-
value domains first (medical, finance) means starting where correctness is
*hardest* to prove objectively, where regulation is heaviest, and where claims are
most contested — precisely the conditions under which an unproven engine should not
lead. So the question this ADR settles is: which slice first, what is the recommended
sequence after it, and what must be true before any domain is allowed to "open".

## Decision
We adopt a **formally-verifiable-first** rollout. The first domain slice is
**mathematics + logic + computer science**, and every domain — first or later —
must pass a fixed onboarding checklist before it opens. Domains open **one slice
at a time, never all at once**; the full dozen-plus is an explicit multi-year
program, not a launch.

**Per-domain onboarding checklist (a domain cannot "open" until all pass):**

```
[ ] ONTOLOGY    : the concept/relation types the domain's KG needs, defined and
                  namespaced as its own multi-KG (ADR-0029, NOVA enh #8)
[ ] INGESTION   : a curated fetch->preprocess->ingest pipeline (r50) with
                  per-atom license resolution recorded in the ledger (ADR-0087)
[ ] GRADING     : an evidence-grade policy for the domain — what counts as FORMAL
                  (verifiable via ADR-0088) vs EMPIRICAL_STRONG/WEAK here
[ ] BENCHMARK   : a curated benchmark set for the proving-ground measurement
                  against LLMs (ADR-0086 Phase 7)
[ ] LICENSING   : the slice confirmed commercially clean (Rule 3) before ingest
```

**Recommended rollout sequence:**

```
(1) mathematics / logic / computer science      [FORMAL]
      cleanest licensing; objectively checkable; exercises ADR-0088/0089.
(2) physical sciences & engineering              [FORMAL + EMPIRICAL]
      formal models meet measured reality; introduces empirical grading.
(3) life sciences & medical                      [EVIDENCE-GRADED, REGULATED]
      heavy safety/regulatory weight; conservative grading; no early claims here.
(4) social / economic / political                [CONTESTED -> ADR-0090]
      genuine disagreement; route to steelman policy, not a single answer.
(5) languages / linguistics                       [DESCRIPTIVE]
```

**Why first means first.** Slice (1) is the one place where ADR-0089 arguments
are checkable end-to-end (a proof is a proof), so it is where the ADR-0086 claim
is *won or lost* as a measurement. It also breaks in the verification machinery on
inputs that are supposed to be clean, so that by the time we reach the empirical
(2), regulated (3), and contested (4) domains, the strict/defeasible split and the
proof checker are already trustworthy. Contested domains are sequenced last on
purpose and hand off to the steelman policy (ADR-0090) rather than the proof path.

**Tie to ADR-0086 phases.** This rollout *is* the Phase 3 domain work; slice (1)
doubles as the Phase 2 proving ground; the per-domain benchmark sets feed the
Phase 7 LLM comparison. The checklist is the gate between phases for each domain.

## Options Considered
- **Highest-commercial-value first, e.g. medical / finance (rejected).**
  Tempting for revenue and for the tiered editions (ADR-0091). Rejected: these are
  the domains where correctness is *hardest* to prove objectively, so we could not
  substantiate the ADR-0086 out-reasons-LLMs claim early; they are heavily
  regulated (safety weight, ADR-0090 contestation), and their licensing is the
  least clean (Rule 3 risk). Leading with them means leading from our weakest
  evidentiary footing.
- **Breadth-first, shallow across all domains at once (rejected).** Maximizes
  apparent coverage. Rejected: it dilutes the proving ground — a thin layer
  everywhere means nothing is deep enough to *measurably* beat an LLM, it
  overwhelms a small team's curation capacity, and it forces the formal machinery
  to debut on mixed-quality inputs rather than clean ones. Coverage without depth
  proves nothing.
- **Formally-verifiable-first (CHOSEN).** Open the objectively-checkable domain
  first, then expand outward through increasingly empirical and contested
  knowledge. Slower to broad coverage, but it is the only order that lets the
  central claim be *measured* early, keeps the first licensing surface clean, and
  hardens ADR-0088/0089 before they meet messy knowledge.

## Consequences
- **Positive:** The ADR-0086 out-reasons-LLMs thesis can be objectively measured
  from the first slice rather than asserted; the cleanest licensing surface (Rule
  3) comes first; the proof checker (ADR-0088) and strict-argument path (ADR-0089)
  are stress-tested on clean inputs before empirical/contested domains arrive; the
  checklist gate makes "is this domain ready" an explicit, auditable decision
  instead of a judgment call; contested knowledge is deliberately deferred to
  where ADR-0090 can handle it.
- **Negative:** Broad commercial coverage arrives *late* — the highest-value
  domains (medical/finance) are sequenced behind math/CS, which is a real
  go-to-market cost the tiered editions (ADR-0091) must account for; each domain
  is a multi-month curation effort and the program spans years; the checklist can
  become a bottleneck if "open" criteria are set too strictly; sequencing is a
  recommendation, and external pressure to jump ahead to a lucrative domain before
  its checklist passes is a standing risk to discipline.
- **Future work:** Refine the checklist thresholds per domain as we learn what
  "ready" really requires; tooling to track checklist state per domain; revisit
  the sequence after slice (1) data on how well formal hardening transfers; let
  ADR-0092 autonomous self-update propose (but not unilaterally open) new slices.

## Implementation Notes
- The onboarding checklist (ontology / ingestion / grading / benchmark /
  licensing) is the binding gate; a domain's KG cannot accept ingested atoms
  until its checklist passes. Each domain is its own namespaced KG (NOVA
  enhancement #8), consistent with ADR-0029's multi-KG model.
- Ingestion reuses the r50 autonomous-research pipeline (fetch -> preprocess ->
  ingest) with per-atom license resolution written to the provenance ledger
  (ADR-0087); the grading policy decides which atoms are eligible for the
  ADR-0088 `FORMAL` path versus empirical grades.
- Slice (1) math/logic/CS atoms route to ADR-0088 verification for `FORMAL`
  grading and to ADR-0089 as strict premises; benchmark sets feed the ADR-0086
  Phase 7 LLM comparison harness.
- Testing: a math theorem query answered with a proof-grade argument plus a
  rendered argument trace (ADR-0089) backed by a verified proof (ADR-0088); a CS
  algorithm-correctness query answered from formal premises; a gating test
  asserting a domain whose checklist is incomplete *cannot* open (no atoms
  ingested into its KG) until ontology/ingestion/grading/benchmark/licensing all
  pass; a contested-domain query (when slice 4 opens) routed to ADR-0090 rather
  than collapsed to one answer.
- DEPENDS ON: ADR-0088 (formal verification path for slice 1 grading), ADR-0089
  (strict/defeasible debate consuming the slice); ADR-0087 (per-atom licensing &
  grade), ADR-0029 + NOVA enhancement #8 (per-domain KG namespacing), r50
  (ingestion pipeline).
