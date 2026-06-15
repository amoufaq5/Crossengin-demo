# Truth-seeking reasoning engine — design overview

> Companion narrative to ADR-0086. ADRs hold the binding decisions; this document
> explains how the pieces fit and why, for a reader coming to the expanded scope
> cold. Where this doc and an ADR disagree, the ADR wins.

## What changed

CrossEngin began as a non-LLM cognitive substrate (ADR-0001) scoped as a personal
companion (ADR-0046) growing into an enterprise pilot (ADR-0047). The scope has
expanded to a **truth-seeking reasoning engine**: a system whose purpose is to
reach correct, well-warranted conclusions and to *show its work*, beginning with
domains where "correct" is objectively checkable (mathematics, logic, computer
science) and extending outward. The substrate, the no-LLM principle, the Bayesian
beliefs, and the autonomous-learning loop are all retained — the expansion is
additive, not a rewrite.

Five properties define the expanded engine, each anchored to ADRs:

1. **Out-reasons LLMs on checkable questions** — via a structured debate engine
   (ADR-0089), not next-token prediction.
2. **Never fabricates** — every emitted claim is traceable to evidence with a
   stated confidence (ADR-0087 provenance ledger; ADR-0023 beliefs).
3. **Stays current on its own** — autonomous research, gated by governance
   (ADR-0092) on top of the existing loop (r39, r50).
4. **Scales from edge device to cluster** — tiered editions (ADR-0091) over a
   NOVA-everywhere infrastructure stack (NOVA-0006..0008).
5. **Handles contested questions honestly** — steelmans every evidenced position
   rather than asserting one truth (ADR-0090).

## The four foundational decisions (ADR-0086)

| Axis | Decision | Why |
|---|---|---|
| Infrastructure | **NOVA everywhere** — cognition *and* systems infra are NOVA | Rule 1 (no third-party deps); total control and auditability; cost is a multi-year infra build, so scale is earned, not claimed |
| Truth model | **Provenance floor + formal ceiling** | Most knowledge is empirical (graded + sourced + licensed); some is provable (machine-checked). Match the real shape of knowledge |
| Reasoning | **Argumentation + Bayesian adjudication** | Structure for explainability + defeasibility; probability for calibrated confidence; both inside the no-LLM line |
| Deployment & contested truth | **Tiered editions + steelman** | One core, three editions (Edge/Enterprise/Research); contested domains represent all evidenced positions |

## How a reasoning query flows

```
user query
  │
  ├─ simple lookup?  ── yes ─▶ fast path (ADR-0071): highest-belief triple
  │
  └─ reasoning query ─▶ DEBATE ENGINE (ADR-0089)
        1 retrieval     spreading activation + HDC gather candidate atoms/rules
        2 construction  build strict + defeasible arguments (leaves carry the
                        provenance ledger record, ADR-0087)
        3 attack        rebut / undercut / undermine relations between arguments
        4 acceptability Dung grounded (default) / preferred (contested) semantics
        5 adjudication  Beta posterior over surviving conclusions (ADR-0023 +
                        evidence grade, ADR-0087)
              │
              ├─ confident single conclusion ─▶ answer + argument trace + confidence
              ├─ strict/FORMAL only           ─▶ proof-grade answer (ADR-0088)
              └─ contested (multi-extension)   ─▶ steelman all positions (ADR-0090)
```

The argument trace is a first-class output (logged to ADR-0043, renderable to the
user). That faithful "show your work" is the core differentiator from LLM
post-hoc rationalization.

## The knowledge atom, after the expansion

Each knowledge atom keeps its ADR-0016 identity and ADR-0023 Beta belief, and
gains a provenance ledger record (ADR-0087):

```
atom = { ...ADR-0016 fields,
         belief: [alpha, beta, last_update_tick, conflict],          # ADR-0023
         provenance: [ source_id, source_tier, source_timestamp,      # ADR-0029
                        license, evidence_grade, proof_ref ] }        # ADR-0087 (new)
```

`evidence_grade ∈ {FORMAL, EMPIRICAL_STRONG, EMPIRICAL_WEAK, TESTIMONIAL,
CONTESTED}`. `FORMAL` requires a `proof_ref` (ADR-0088) and pins belief.
`license` is interned into `KG-licenses` and gates which edition may use the atom
(ADR-0091). Full field spec: `docs/design/atom-provenance-schema.md`.

## NOVA everywhere — the honest gap

The cognitive design is mature; the infrastructure is not. Today CrossEngin
persists to a text file and NOVA has transport but no storage engine or
consensus. "Massive scale" is therefore gated behind real NOVA systems work:

- **NOVA-0007** — durable storage engine (WAL + crash recovery) replaces the text
  file. *Required for Phase 1.*
- **NOVA-0008** — Raft consensus over the existing federation transport.
  *Required for Phase 5 (distributed scale).*
- **NOVA-0006** — the umbrella defining the infrastructure boundary and roadmap.

The 1M→1B node jump of ADR-0003 becomes a multi-node reality only once these
land. The roadmap (ADR-0086) sequences the work so no phase claims a capability a
later phase is responsible for delivering.

## Roadmap at a glance (ADR-0086)

| Phase | Deliverable | Gate |
|---|---|---|
| 0 | Governance: ADRs + schema + ledger (this set) | docs only |
| 1 | Provenance substrate + NOVA storage engine | ADR-0087, NOVA-0007 |
| 2 | Debate engine on math/logic/CS proving ground | ADR-0089, 0088, 0093 |
| 3 | Domain ontologies + clean ingestion | ADR-0093, 0087 licensing |
| 4 | Autonomous self-update with governance | ADR-0092 |
| 5 | Distributed scale (consensus, sharded KGs) | NOVA-0008, ADR-0003 |
| 6 | Tiered editions | ADR-0091 |
| 7 | Benchmark vs LLMs + domain expansion | ADR-0093 §benchmark |

## Why math / logic / CS first (ADR-0093)

These domains are formally verifiable, so the engine's central claim — better
reasoning than an LLM — can be *measured* objectively rather than asserted, and
they exercise the formal-verification path (ADR-0088) and the strict-argument
degeneracy of the debate engine (ADR-0089). Rollout then proceeds to
physical/engineering (formal + empirical), life/medical (evidence-graded,
regulated), social/economic/political (contested → steelman), and language.
