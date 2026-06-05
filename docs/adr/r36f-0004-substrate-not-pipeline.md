# ADR R36F-0004: Cognitive substrate over modular pipeline

## Status
Accepted (R36F) -- restates the core decision originally captured in
`docs/adr/0001-substrate-architecture.md`. This ADR adds the rounds-up
perspective: how the substrate commitment survived 35 rounds of
implementation pressure.

## Context
The single most consequential architectural choice in CrossEngin is
the macro-shape of the system. Two extremes:

  - **Pipeline.** Perceive -> parse -> retrieve -> reason -> plan ->
    act, each stage a typed callable. Trivially unit-testable. Trivial
    to onboard. The shape that most AI projects end up at.
  - **Substrate.** A fabric of uniform computational units (nodes)
    connected by persistent weighted synapses, with ephemeral typed
    signals flowing through gates. Capability emerges from substrate
    dynamics (co-firing, plasticity, spreading activation, prediction)
    rather than from an orchestrator calling modules in sequence.

The NO-LLM-COGNITION principle (existing ADR 0014) forbids using a
language model as cognition; this excludes the usual "wrap an LLM in
orchestration logic" path and forces the architecture itself to carry
the learning and reasoning.

The pipeline shape is easier to build for two founders. The substrate
shape is the shape that the AGI-relevant capabilities -- continuous
learning, initiative, theory-of-mind, long-horizon goals,
self-awareness -- naturally inhabit.

## Decision
**CrossEngin is a substrate, not a pipeline.** Concretely:

  - **Uniform computational units.** Every node has the same shape:
    `(activation, threshold, fan-in synapses, fan-out synapses,
    region tag)`. There are no special "perceiver" or "reasoner"
    node classes at the type level; specialisation is a function of
    region tag + learned synapse structure.
  - **Six concurrent loops** (existing ADR 0036): perception,
    consolidation, drive, action, imagination, meta. All read and
    write the same substrate; none orchestrates the others.
  - **Tick-driven ~100Hz** (existing ADR 0037) layered on event-driven
    coordination. There is no top-level controller that decides "now
    reason, now retrieve."
  - **Algorithmic helpers** (existing ADR 0031, reasoning module)
    survive as substrate-adjacent code that reads and writes the
    substrate but does not orchestrate it. The reasoning module is
    called *from within* substrate dynamics, not above them.

## Consequences
**Positive (validated across 35 rounds).**
  - **Cross-domain emergence works.** Spreading activation across
    cross-KG references (existing ADR 0004) lets a perception event
    in `KG-language` trigger associative recall in `KG-medicine`
    without an orchestrator routing it. The dynamics ARE the
    cross-domain reasoning.
  - **Continuous learning is free.** Plasticity runs as a substrate
    rule, not as a "training mode." The desktop companion is always
    learning; there is no train/eval split.
  - **Initiative has a natural home.** The drive loop reads soul
    state + global activation patterns and emits motor signals
    without being prompted by user input. A pipeline would not have
    a natural place for this.

**Negative (also validated).**
  - **Debuggability is hard.** "Why did this signal fire?" requires
    signal traces + decision log + the audit module (existing ADR
    0043). We accepted this and made observability first-class.
  - **NOVA runtime had to grow.** Rounds R8, R17, R26 each pushed
    NOVA runtime extensions (#1-#5, #12) to support the substrate
    shape. The pipeline path would have run on NOVA's base runtime.
  - **The substrate may fail to produce useful behaviour at all.**
    We mitigate via small substrate islands (the parts in `src/parts/`)
    that can be individually tested + grown rather than gambling on
    a 6M-node monolith from day one.

**Follow-up rounds.**
  - Substrate-adjacent helpers are explicitly allowed (existing ADR
    0031); they read/write the substrate but do not orchestrate.
  - The reasoning track (R6+ in the reasoning module) keeps adding
    helpers without re-introducing pipeline shape.

## Alternatives considered
  - **Pure modular pipeline** (rejected upfront in existing ADR 0001):
    cheapest to build, hostile to the AGI capability thesis.
  - **Hybrid orchestrated substrate** (partially adopted): small
    substrate islands wrapped by a workflow controller. Rejected as
    the macro-architecture because the orchestrator quietly becomes
    the locus of intelligence (collapsing back into pure pipeline).
    Retained as the "helper" pattern: helpers called from within
    substrate dynamics.
  - **LLM-wrapped substrate**: rejected by NO-LLM-COGNITION (existing
    ADR 0014).

## Why this re-ratification at R36F
35 rounds of implementation pressure tend to erode the original macro-
architectural commitment, especially when "just add an orchestrator"
would solve a specific local debugging problem. This R36F ADR exists
to re-pin the commitment and make it cheap for future rounds to
reference: "no, we are not adding a top-level controller; see ADR
R36F-0004."
