# ADR-0009: Cognitive module — goals, planning, action

## Status

Accepted

## Context

The Cognitive module is the brain's executive: it represents what the agent is trying to do, decides when to act, plans how to act, and emits actions. Its inputs are perception streams (ADR-0004), memory state (ADR-0006), academic knowledge (ADR-0008), Visionary-module simulation outputs (ADR-0010), and Soul-layer constraints (ADR-0011). Its outputs are actions in the world.

Four design questions sit at the top:

1. **Goal representation.** Implicit (inferred from utterances) or explicit symbolic goals?
2. **Initiative.** When does the agent act spontaneously, vs only on user prompt?
3. **Planning.** Flat plan, hierarchical plan, or reactive (no plan)?
4. **Action vocabulary.** Text replies only, or also tool calls, code execution, UI manipulation?

The user has specified all four. Goals are explicit symbolic, BDI-style, supplied by the user. Initiative triggers are enumerated. Planning is hierarchical. Action vocabulary is broad — text replies, structured tool/API calls, code execution, UI manipulation.

## Decision

**Goal representation: BDI-style explicit symbolic goals supplied by the user.** The cognitive module tracks three sets explicitly:

- **Beliefs** — propositions the agent currently holds about the world, sourced from memory, academic knowledge, and perception. Beliefs carry confidence values.
- **Desires** — goals the user has articulated to the agent. Each desire has an identifier, a textual statement, optional success criteria, and a priority.
- **Intentions** — the subset of desires the agent has committed to act on now (or in the near term), with associated plans.

Goals are explicit because the user has articulated them. The agent does not infer arbitrary new goals; it tracks user-articulated goals and the sub-goals that decompose from them during planning.

**Initiative triggers (enumerated).** The agent acts spontaneously — without an immediate user prompt — when one of the following triggers fires:

1. **User interaction.** The user has said or done something the agent is meant to respond to.
2. **User-behavior cue indicating need for help.** A pattern in the user's observed behavior matches a known help-needed pattern (e.g., the user has been stuck on the same task for an unusual length of time).
3. **Perception-derived inference.** Something perceived produces an inference whose action-relevance threshold is crossed (e.g., a visible safety hazard, a relevant deadline approaching).
4. **Anticipated event.** A predicted future event passes its action threshold (e.g., a scheduled commitment requires preparation now).

These four are the complete v0 set. Adding a new trigger requires a new ADR.

**Planning: hierarchical.** Plans are tree-structured: a top-level plan toward a desire decomposes into sub-plans, which decompose into action sequences. The planner picks a plan, expands it lazily (only the next-step children are concretized, not the full tree), and re-plans when a step fails or a precondition changes. The fast heuristic consequence predictor (below) evaluates candidate sub-plans before commitment.

**Fast heuristic consequence predictor lives in the cognitive module.** It is deliberately distinct from the slower probabilistic simulator that lives in the Visionary layer (ADR-0010). The cognitive predictor is for moment-to-moment planning ("will this next step satisfy the precondition for the step after?"); the Visionary simulator is for scenario rollout over longer horizons. The split lets fast planning stay fast without losing the option of richer simulation when latency budget allows.

**Action vocabulary (v0):**

- *Text replies.* The agent's verbal output to the user.
- *Structured tool/API calls.* Calls to defined external tools with typed arguments and typed returns. v0 includes whatever tools the medicine-domain use cases require; the tool registry is itself a versioned, audited artifact.
- *Code execution.* Sandbox-bounded code execution as an action type (e.g., running a calculation, formatting a structured output).
- *UI manipulation.* The agent can act on the user-facing UI surface where authorized.

**Constitutional safety gate.** Every action — regardless of type — passes through the Soul layer's constitutional gate (ADR-0011) before emission. A candidate action that violates a constitutional value is blocked at this gate, with the reason logged. The constitutional gate is the last step in the action pipeline; no path emits actions around it.

## Consequences

Positive: explicit symbolic goals are inspectable — at any moment a reviewer can ask "what does the agent currently believe, want, and intend?" and get a structured answer. The constitutional gate is a single, auditable enforcement point for the safety-floor values. Hierarchical planning matches how humans articulate goals in conversation (high-level intent → sub-tasks). The four-trigger initiative set is small enough to red-team thoroughly (per the constitutional-enforcement criterion in ADR-0022).

Negative: BDI-style goal tracking is more state than a stateless prompt-response loop. Belief updates have to be transactional across modules (memory, perception, academic). Hierarchical planning needs an actual planner — not free; v0 uses a simple HTN-style planner and revisits at v1 if its limitations bite. The constitutional gate adds latency to every action emission (acceptable; safety first).

Neutral: code execution and UI manipulation as first-class action types means action sandboxing and UI permission models are part of v0's surface — handled in ADR-0021 (privacy and data handling) and at the application layer.

## Alternatives considered

**Implicit goals inferred from utterances** (LLM-style). Simpler. Rejected: incompatible with the "explicit symbolic goals" thesis and with the inspectability requirement from constitutional value #8. An agent whose goals are vibes is not an agent whose goals are auditable.

**Reactive (no planning, just stimulus-response).** Considered. Rejected: cannot support the perception-derived inference and anticipated-event initiative triggers, which inherently require lookahead.

**Flat planning.** Considered. Rejected: real goals decompose into sub-goals; flat planning either flattens prematurely or stalls on coarse-grained next steps.

**Text-only action vocabulary** (no tool calls, no code, no UI manipulation). Rejected: too narrow for the personal-companion use case. The agent has to be able to *do things*, not only *say things*.

**Single consequence predictor shared with the Visionary layer.** Rejected: planning-cycle latency and scenario-rollout-horizon are different problems with different tractable solutions. Sharing a single solver makes one of the two slow.

## Open questions

- HTN planner choice for v0 (build minimal in-house planner, or adopt a permissively-licensed off-the-shelf planner). Decision at M5 (ADR-0022).
- Concrete tool-registry schema and how new tools are versioned, signed, and audited. Tool-registry security is a v0 concern; the schema is finalized at M5.
- Sandbox model for code execution. Initial assumption: subprocess with seccomp filters in a container, no network by default. Final decision at M5.

## References

- ADR-0004 (Perception) — initiative trigger source.
- ADR-0005 (Knowledge representation) — beliefs and desires as graph-of-vectors nodes.
- ADR-0006 (Memory) — where beliefs and intentions persist.
- ADR-0010 (Visionary) — the slow simulator the cognitive predictor coexists with.
- ADR-0011 (Soul: values governance) — the constitutional gate every action passes through.
- ADR-0021 (Privacy) — action-sandboxing and consent for tool calls touching the outside world.
- ADR-0022 (Evaluation and milestones) — M5 cognitive integration milestone.
