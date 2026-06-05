# ADR-0019: Procedural memory and KG-skills (skills as procedural rules + skills KG)

## Status

Proposed

## Date

2026-05-25

## Context
So far the knowledge representation (ADR-0016 atoms, ADR-0017 multi-KG, ADR-0018 concepts) is *declarative* — it captures what is true. CrossEngin also needs *procedural* memory: how to do things. A companion that can acquire skills (one of the eight capability tests, ADR-0049) must represent "to convert a recipe to metric, do X then Y then Z", "to summarize a document, …", "to greet this user, …" as executable knowledge that can be invoked, sequenced, evaluated for success, and improved. This is distinct from reasoning strategies (ADR-0031, which are module-level multi-step procedures); skills are learned, fine-grained, substrate-resident procedures the system accumulates over its lifetime.

The decision is needed now because self-directed learning (ADR-0026) and the ask-user-to-teach mechanism (ADR-0027) frequently produce procedures, not facts, and the self-model (ADR-0020) tracks competence largely in terms of which skills exist and how reliable they are. Without a procedural representation, taught procedures would be flattened into inert facts and could never execute.

Constraints: 2 founders, 8h/day, bootstrap, no LLM in cognition (ADR-0014) — so skills cannot be LLM-generated code; they must be substrate structures. We reuse the atom (ADR-0016, `ATOM_RULE`/`ATOM_SKILL` kinds), the multi-KG layer (ADR-0017), and `core/belief.nova` so a skill's reliability is tracked exactly like an atom's confidence.

## Decision
**Skills as procedural rules in a dedicated skills KG.** We spawn a standing `KG-skills` namespace (via ADR-0017's `kg_spawn`, but seeded at startup since it is always needed). A *skill* is an atom of kind `ATOM_SKILL` whose payload is `{trigger, steps, preconditions, effects, reliability}`. `trigger` is a concept/condition pattern (ADR-0018) that activates the skill; `steps` is an ordered list of *procedural rules* (`ATOM_RULE` atoms), each `{condition -> action_signal}` where `action_signal` is one of the 18 signal types (ADR-0008) emitted toward the action part. `preconditions` and `effects` are concept-slot assertions used for planning and for verifying success. `reliability` is a `core/belief.nova` (alpha/beta) updated on every execution outcome.

**Invocation.** Skills are not called by name from outside; they are *activated* by the substrate. When the reader/reasoning loop activates a concept matching a skill's `trigger` and the `preconditions` hold, the skill emits its `steps` as ordered `SIG_COMMAND`/`SIG_ORDER` signals (ADR-0008) through gates (ADR-0009) to the action part. A goal (ADR-0033) can also recruit a skill whose `effects` satisfy a sub-goal. On completion, observed `effects` are compared to predicted `effects`; a match calls `skill_observe(s, +1)` (alpha), a mismatch `skill_observe(s, -1)` (beta), feeding predictive coding (ADR-0024).

**Learning and refinement.** Skills are born three ways: (1) taught explicitly by the user (ADR-0027) — the taught steps are parsed by the reader into `ATOM_RULE` atoms; (2) extracted from episodic replay (ADR-0022) when a successful action sequence recurs; (3) composed from existing skills when a sub-goal tree (ADR-0033) repeatedly chains them. A skill whose `reliability` posterior mean falls below `SKILL_RETIRE = 0.4` over `RETIRE_N = 8` executions is flagged for relearning rather than silently deleted, and its decay follows the same GC path as other atoms (ADR-0025).

## Options Considered
**Skills as compiled NOVA functions / generated code.** Maximum performance. Rejected: it would require either hand-authoring every skill (infeasible for 2 founders and contrary to continuous learning) or generating code at runtime, which would invite an LLM into the cognition path (violating ADR-0014) and bypass the substrate. Skills must be learnable substrate data.

**Fold procedures into declarative atoms (no separate procedural kind).** Store "steps" as ordinary fact atoms. Rejected: declarative atoms have no execution semantics, no precondition/effect contract, and no per-execution reliability; the system could describe a procedure but not run it. The `ATOM_SKILL`/`ATOM_RULE` kinds give us executable structure while reusing the atom machinery.

**One skill library shared across all domains (no KG-skills namespace).** Rejected: skills are domain-organized like everything else (ADR-0004/ADR-0017); a contraindication-checking skill belongs near KG-medicine via cross-refs, and v2 tenant isolation (ADR-0047) requires tenant-specific skills to live in a separable namespace. A dedicated `KG-skills` with cross-refs to domain KGs fits the existing model.

**Reuse the reasoning module (ADR-0031) for all procedures.** Rejected: ADR-0031 covers complex multi-step *strategies* implemented as module functions; lifetime-accumulated fine-grained skills are too numerous and too learned to be module code. The two are complementary — strategies can recruit skills.

## Consequences
- **Positive:** The system represents and executes learned procedures purely in the substrate, with per-skill Bayesian reliability driving honest self-assessment (ADR-0020) and predictive-coding updates (ADR-0024). Skills compose into sub-goal plans (ADR-0033) and can be taught (ADR-0027) or mined from experience (ADR-0022). No LLM is needed to act.
- **Negative:** Executing a skill as a stream of signals through gates is harder to debug than a function call; failures may be partial (some steps fire, some don't). Success verification depends on accurate `effects` schemas (ADR-0018). Composition can create deep skill chains needing depth limits.
- **Future work:** A skill-debugger/trace view tied to the decision log (ADR-0043). Skill generalization (lifting concrete steps to schema-typed ones). ADR-0020 consumes `KG-skills` reliability to report competence; ADR-0026 triggers acquisition of missing skills.

## Implementation Notes
Build `KG-skills` on `core/knowledge.nova`; skills and rules are `atom_new(..., ATOM_SKILL|ATOM_RULE, ...)` (ADR-0016). Add `skill_new(trigger, steps, pre, eff)`, `skill_activate(s, ctx)` (emits ordered `SIG_COMMAND` via `core/channel.nova` weighted channels and ADR-0009 gates), `skill_observe(s, outcome)` (updates `core/belief.nova`), `skill_compose(s1, s2)`. Reliability read via `runtime/confidence.nova`. Triggers/preconditions/effects reference concepts (ADR-0018). Episodic mining hooks into `mind/memory.nova` replay (ADR-0022, NOVA enhancement #13 idle scheduling). Test fixtures: a taught 3-step procedure becomes a `KG-skills` skill that activates on its trigger and emits 3 ordered command signals; a deliberately failing skill drives `reliability` posterior below `SKILL_RETIRE` after 8 runs and is flagged for relearning; a sub-goal recruits a skill by matching `effects`. DEPENDS ON: NOVA enhancement #8 (skills KG + cross-refs to domain KGs). Skills are substrate data and signals only — no LLM in skill creation or execution (ADR-0014).
