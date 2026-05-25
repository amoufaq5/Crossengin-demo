# ADR-0001: Substrate architecture vs modular workflow

## Status

Proposed

## Date

2026-05-25

## Context
CrossEngin targets AGI-relevant capabilities — continuous learning, self-directed skill acquisition, theory of mind, initiative, counterfactual reasoning, long-horizon goals, and self-awareness of identity and state over time. The single most consequential architectural choice is the macro-shape of the system: is intelligence produced by a *pipeline of cognitive modules* (perceive -> parse -> retrieve -> reason -> plan -> act, each a callable component), or by the *dynamics of a computational fabric* in which many uniform units exchange typed messages and capability emerges from learned connection structure? Every later ADR inherits this choice; it cannot be deferred.

The constraints are real and shape the answer. We are 2 founders at 8h/day each, bootstrapping with no outside funding, on an 18-30 month v1 timeline. v1 ships as a personal desktop companion (single user, single device); v2 is a single-tenant enterprise pilot. We are not building on an LLM — the NO-LLM-COGNITION principle (ADR-0014) forbids using any language model as cognition. That removes the usual shortcut of wrapping orchestration logic around a frozen model, and forces the architecture itself to carry the learning and reasoning.

A modular workflow is far easier to build, test, and debug with a small team: each module has a signature, a unit test, and a clear owner. But a fixed pipeline bakes in a fixed processing order and a fixed division of labor. The capabilities we want are precisely the ones that resist being decomposed into a static call graph — initiative and continuous learning are *cross-cutting* and *always-on*, not stages you visit once per request.

## Decision
CrossEngin is a **substrate**, not a modular workflow. The system is a fabric of uniform computational units — **nodes** — connected by persistent weighted **synapses**, along which ephemeral typed **signals** flow, **gated** and routed to specialized regions. Nodes are organized into **parts** (perception, KG-medicine, KG-[domain], episodic, soul, reasoning, imagination, action, meta), each holding 1M nodes in v1. Intelligence is an emergent property of substrate dynamics — co-firing, plasticity, spreading activation, prediction and error correction — rather than the output of an orchestrator calling modules in sequence.

Concretely: there is no top-level controller that decides "now reason, now retrieve." Instead, perception produces **moments**, gates route the resulting signals to parts, activation spreads across synapses, atoms are read and written in domain KGs, and output emerges from concept-activation patterns flowing down to motor effectors (ADR-0013). Six genuinely concurrent loops (ADR-0036) and a background imagination loop run continuously over the same substrate, tick-driven at ~100Hz (ADR-0037) and layered on event-driven coordination. "Modules" survive only as *substrate-adjacent helpers* for genuinely algorithmic work (e.g. multi-step reasoning strategies in `mind/reasoning.nova`, ADR-0031) — they read and write the substrate, they do not orchestrate it.

## Options Considered
**1. Pure modular workflow (rejected).** A classic cognitive pipeline of typed components with explicit control flow. *Pros:* cheapest to build for 2 people; trivially unit-testable; deterministic and debuggable; maps cleanly onto NOVA's existing `mind/` modules. *Cons:* the request-response, fixed-order shape is hostile to always-on initiative, continuous background learning, and emergent cross-domain association. New capabilities require new modules and new wiring rather than new learned structure. Self-awareness of state-over-time has nowhere natural to live. Rejected because it optimizes for our short-term ease at the direct expense of the long-term capability thesis.

**2. Pure substrate (CHOSEN).** Uniform nodes + synapses + signals + gates + multi-KG; emergence from dynamics. *Pros:* directly fits the AGI goals — learning *is* plasticity, initiative *is* a continuously-running loop, cross-domain reasoning *is* spreading activation across cross-KG references (ADR-0004). One mechanism (the substrate) generalizes instead of N bespoke modules. *Cons:* much harder to debug ("why did this signal fire?"), demands heavy NOVA runtime enhancements (#1-#5, #12) that do not yet exist, and risks the substrate failing to produce useful behavior at all. We accept these by mandating the decision log (ADR-0043) and signal traces as first-class observability.

**3. Hybrid orchestrated substrate (considered, partially adopted).** Small substrate islands wrapped and sequenced by a workflow controller. *Pros:* a pragmatic middle path; keeps an escape hatch to imperative code. *Cons:* the orchestrator re-imposes fixed processing order and becomes the true locus of intelligence, demoting the substrate to a subroutine — quietly collapsing back into option 1. We rejected it *as the macro-architecture* but retained its useful kernel: algorithmic helpers (ADR-0031) may be called *from within* substrate dynamics without ever sitting above them.

## Consequences
- **Positive:** A single uniform mechanism underlies all cognition, so capabilities compound rather than being re-implemented per feature; continuous learning, initiative, and cross-domain association become structural rather than bolted-on; the design is honestly aligned with the AGI thesis and the NO-LLM principle (ADR-0014).
- **Negative:** Debuggability drops sharply versus a pipeline — we trade step-through clarity for emergent behavior; we take on substantial NOVA runtime risk (enhancements #1-#5, #12); there is genuine uncertainty that emergence yields useful behavior on the v1 timeline, and a 2-founder team has thin margin for that risk.
- **Future work:** Defines the seven primitives (ADR-0002), the scaling plan (ADR-0003), multi-KG organization (ADR-0004), and the NOVA enhancement program (ADR-0005). Forces investment in observability (ADR-0043) and a careful build sequence (ADR-0050) that proves substrate viability early.

## Implementation Notes
The substrate is assembled in `core/system.nova` from the seven primitives of ADR-0002, built on NOVA's existing `core/node.nova`, `core/channel.nova`, `core/signal.nova`, `core/moment.nova`, and `core/knowledge.nova`. Parts are node collections allocated up-front; signal paths use `core/path.nova`. The concurrent loops (ADR-0036) communicate over `runtime/chan.nova`; ticking is driven by `runtime/scheduler.nova` (ADR-0037). Observability is non-negotiable: every signal carries a `trace` (visited-node list) per `core/signal.nova`, and decisions append to the log of ADR-0043.

DEPENDS ON: NOVA enhancement #1 — pre-allocated fixed-capacity node arenas (1M+ nodes/part).
DEPENDS ON: NOVA enhancement #3 — true concurrent execution units for the 6 loops (current scheduling is cooperative).
DEPENDS ON: NOVA enhancement #5 — 100Hz deterministic tick scheduler fused with event-driven coordination.

Testing strategy: a "substrate-liveness" fixture that boots one part, injects a `SIG_EVENT`, and asserts measurable spreading activation and a written atom — the earliest go/no-go gate in the build sequence (ADR-0050), validated under the capability tests of ADR-0049.
