# CrossEngin — system architecture (current, post-expansion)

> **Status:** the single current source of truth for the system shape after the
> truth-seeking expansion (ADR-0086…0096). The large top-level `ARCHITECTURE.md`
> predates the expansion and remains accurate for the substrate internals it
> covers; where the two differ on scope, this document and the ADRs win. Each
> claim here is anchored to an ADR — read the ADR for the binding decision and the
> reasoning; this document is the map.

## 1. One-paragraph thesis

CrossEngin is a non-LLM cognitive substrate (ADR-0001) that has grown into a
**truth-seeking reasoning engine** (ADR-0086): it reaches well-warranted
conclusions and *shows its work*, beginning in domains where correctness is
objectively checkable (math/logic/CS, ADR-0093). It never fabricates — every
claim is traceable to graded, licensed evidence with a confidence (ADR-0087,
ADR-0023). It reasons by structured argument adjudicated by probability
(ADR-0089), proves what can be proved (ADR-0088), simulates to plan (ADR-0032),
researches its own gaps under governance (ADR-0092), and ships from embedded
device to cluster (ADR-0091) on a zero-dependency NOVA stack (NOVA-0006…0008).

## 2. The layered stack

```
┌──────────────────────────────────────────────────────────────────┐
│  EDITIONS (ADR-0091) — one core, selected by a build manifest       │
│     Edge        │      Enterprise/Cloud      │      Research         │
├──────────────────────────────────────────────────────────────────┤
│  I/O & EMBODIMENT (ADR-0095, 0013, 0014)                            │
│   sensors→moments │ motor effectors │ STT/TTS bridge (isolated)     │
│   Tier-1 hard-real-time reflex/safety loop  ◀── intentions ──┐      │
├──────────────────────────────────────────────────────────────┼─────┤
│  REASONING (ADR-0089, 0088, 0032)                              │     │
│   debate engine: retrieval→construct→attack→acceptability→     │     │
│   Bayesian adjudication │ formal proof path │ imagination/sim   │     │
├────────────────────────────────────────────────────────────────────┤
│  KNOWLEDGE (ADR-0016, 0023, 0029, 0051, 0087)                       │
│   typed-atom KGs (multi-KG per domain) + HDC/VSA + episodic;         │
│   atom = belief[α,β,conflict] + provenance[src,tier,license,         │
│   evidence_grade,proof_ref]                                          │
├────────────────────────────────────────────────────────────────────┤
│  SUBSTRATE CORE (ADR-0001, 0036, 0037)                              │
│   uniform nodes ─ weighted synapses ─ typed signals ─ gates;         │
│   parts; 6 concurrent loops + idle imagination loop @ ~100Hz         │
├────────────────────────────────────────────────────────────────────┤
│  GOVERNANCE & SAFETY (cross-cutting: 0045,0041,0092,0094,0096,0043) │
│   constitution │ permission tiers │ governed self-update │ threat    │
│   model │ ML policy │ append-only decision log (audits all above)    │
╞════════════════════════════════════════════════════════════════════╡
│  NOVA INFRASTRUCTURE (NOVA-0006/0007/0008)                          │
│   serving/observability → consensus (Raft) → storage (WAL+recovery)  │
│   → transport (DTLS/ICE/STUN/TURN/TLS — already built)               │
├────────────────────────────────────────────────────────────────────┤
│  NOVA CORE — self-hosting compiler · arena alloc (no GC) · syscalls  │
└──────────────────────────────────────────────────────────────────┘
```

The boundary at the double line (`═`) is the NOVA/CrossEngin split (NOVA-0006):
reusable systems infrastructure is NOVA's; cognition is CrossEngin's.

## 3. Substrate core (ADR-0001)

Intelligence is an emergent property of a fabric, not the output of an
orchestrator. Uniform **nodes** are joined by weighted **synapses**, along which
typed **signals** flow, **gated** and routed into **parts** (perception,
KG-domains, reasoning, episodic, soul, imagination, action, meta). There is no
top-level controller; capability comes from co-firing, plasticity, and spreading
activation. Six concurrent loops plus a background imagination loop run
continuously, tick-driven at ~100Hz (ADR-0037). Scale is two-axis (ADR-0003):
fixed pre-allocated node arenas (1M/part v1 → 1B target) and a sparse, elastic
CSR synapse store that is the primary growth mechanism.

## 4. Knowledge layer

Knowledge is an **explicit graph of typed atoms** (ADR-0016) — not weights —
augmented by HDC/VSA embeddings (ADR-0051) and episodic memory. After the
expansion each atom carries:

```
atom = { ...identity (ADR-0016),
         belief:     [alpha, beta, last_update_tick, conflict],        # ADR-0023
         provenance: [source_id, source_tier, source_timestamp,        # ADR-0029
                      license, evidence_grade, proof_ref] }            # ADR-0087
```

`evidence_grade ∈ {FORMAL, EMPIRICAL_STRONG, EMPIRICAL_WEAK, TESTIMONIAL,
CONTESTED}`; `FORMAL` requires a `proof_ref` (ADR-0088) and pins belief; `license`
is interned and gates which edition may use the atom. Source authority (tier
A/B/C) and recency policy resolve conflicts (ADR-0029); genuine disagreement
becomes a first-class CONTESTED state (ADR-0023), never a silent average. Field
spec: `docs/design/atom-provenance-schema.md`.

## 5. Reasoning layer

A reasoning query runs the **debate engine** (ADR-0089):

```
query → retrieval (HDC/KG spreading activation gather candidate claims+rules)
      → construction (strict rules from FORMAL atoms + defeasible rules → arguments)
      → attack (rebut / undercut / undermine between arguments)
      → acceptability (Dung grounded default; preferred for contested subgraphs)
      → adjudication (Beta posterior over surviving conclusions; ADR-0023+0087)
      → answer + argument trace + confidence
```

- **Strict/FORMAL-only arguments degenerate into proofs**, checked by a tiny native
  NOVA proof-checker kernel (ADR-0088); they cannot be defeated by defeasible
  attacks.
- **Contested results** (multiple surviving positions, or CONTESTED atoms, or a
  contested domain) route to the **steelman policy** (ADR-0090): represent every
  evidenced position at its strongest with provenance, distinguishing empirical
  defeat from genuine value disagreement.
- **Simulation** (imagination, ADR-0032) supplies forward/counterfactual/scenario
  rollouts for prediction and planning, and dream-mode recombination for novel
  pattern discovery.
- The **argument trace is a first-class output**, logged to the decision log
  (ADR-0043) — the faithful "show your work" that separates this from LLM
  rationalization.

**How it solves a never-seen problem:** by composition, not recall — *derive*
(argument), *transfer* (cross-domain activation), *imagine* (simulate),
*research* (learn the gap, ADR-0092), *prove* (ADR-0088). This is an
architectural programme, first *measured* on the verifiable proving ground
(ADR-0093), not yet a benchmarked result.

## 6. Learning / ML policy (ADR-0096)

The engine **learns continuously**, but uses only learning that is **online,
local, explainable, and substrate-compatible**: Bayesian belief updating
(ADR-0023), Hebbian + error-driven plasticity (#12), predictive coding /
three-factor learning, the backprop-free Forward-Forward representation learner,
and HDC/VSA (ADR-0051). **Forbidden:** any LLM/frozen pre-trained model in
cognition (ADR-0014), and end-to-end global backprop as the cognition mechanism.
The test: would the technique make a capability unauditable, unlearnable-online,
or dependent on a frozen artifact? If yes, it is out.

## 7. Governance & safety (cross-cutting)

- **Constitution** (ADR-0045): hard, non-revisable inhibitory rules the agent
  cannot self-edit — and, on robots, an embodied physical-safety floor (ADR-0095).
- **Permission tiers** (ADR-0041) and **override + reversibility** (ADR-0044, 0025).
- **Governed self-update** (ADR-0092): CANDIDATE → VERIFIED → PROMOTED through
  license/grade/proof/corroboration/conflict/debate gates; promotion is an argument
  that must survive, not a blind insert.
- **Threat model** (ADR-0094): ten attack surfaces with a control each, unified by
  provenance-backed reversibility; a security-review gate per roadmap phase.
- **Decision log** (ADR-0043): append-only audit under everything above.

## 8. Deployment / editions (ADR-0091, 0047, 0046)

One binary, three editions by manifest + topology — not three codebases.

| | Edge | Enterprise / Cloud | Research |
|---|---|---|---|
| Target | robot, phone, vehicle, OS-embedded | multi-tenant ERP/cloud | team + partners |
| Topology | single process, offline | one-tenant-per-process supervisor → Raft cluster | single full-introspection process |
| Knowledge | distilled, clean-KB only (quarantine excluded) | base-brain snapshot + per-tenant overlay | full, no distillation |
| Autonomous research | gated/off | on, governed | on, exposed |
| Scale | none | NOVA-0007 storage + NOVA-0008 consensus, sharded KGs | none |
| Introspection | hidden | audit only | argument graph + decision log + LLM-benchmark harness |

The edition manifest is a **security-relevant artifact** (ADR-0094): an Edge build
provably contains no quarantined atoms and no fetch path.

## 9. NOVA infrastructure dependency (NOVA-0006/0007/0008)

"NOVA everywhere" (Rule 1) makes NOVA responsible for systems infrastructure:
durable storage with WAL + crash recovery (NOVA-0007, replaces today's text-file
persistence), Raft consensus over the existing federation transport (NOVA-0008),
and a serving/observability layer. Build order: transport (done) → storage →
consensus → serving. **Massive scale is gated behind this work** and is not
claimed before it lands (the 1M→1B node jump of ADR-0003 becomes a multi-node
reality only at roadmap Phase 5).

## 10. Roadmap pointer

Seven phases (ADR-0086): 0 governance (this doc set) · 1 provenance substrate +
NOVA storage · 2 debate engine on the verifiable proving ground · 3 domain
ontologies + clean ingestion · 4 autonomous self-update governance · 5 distributed
scale · 6 tiered editions · 7 benchmark vs LLMs + expansion.

## 11. Honest current state

Design is mature; most of the expansion is **not built yet** (Phase 0 is
docs-only). The substrate, KGs, Bayesian beliefs, federation transport, and a
working autonomous-research loop exist (ANALYSIS.md). Not yet built: the
provenance ledger fields, the debate/formal engines, the NOVA storage engine and
consensus, the tiered-edition tooling, embodiment, and the security controls of
ADR-0094. Persistence today is a text file. Treat sections 4–9 as the *target*
architecture the ADRs commit to, sequenced by the roadmap.
