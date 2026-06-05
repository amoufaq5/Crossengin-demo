# ADR-0032: Imagination subsystem evolution (current 10 patterns -> learn new patterns from experience; forward/counterfactual/dream/scenarios)

## Status

Proposed

## Date

2026-05-25

## Context
`core/imagination.nova` ships with a fixed set of ~10 seed imagination patterns (e.g. simple forward projection, basic "what-if" substitution). For AGI-relevant capability — counterfactual reasoning, initiative, long-horizon planning — a fixed catalogue is a ceiling: the system can only imagine in ways its founders pre-scripted. CrossEngin must instead *learn new imagination patterns from its own experience*, so that the ways it simulates futures and alternatives grow with what it knows. This is also where initiative and creativity originate: imagination running in the idle loop (ADR-0036) proposes goals and surfaces knowledge gaps.

Constraints shape this heavily. We have 2 founders at 8h/day and a desktop deployment (ADR-0046) where imagination runs in background during idle (enhancement #13), so it must be interruptible and resource-bounded — it cannot starve the six live loops. It must obey NO-LLM-COGNITION (ADR-0014): imagined content is substrate activation over concept and KG atoms, never LLM-generated text. And it must reuse, not reinvent, the replay machinery of episodic memory (ADR-0022), since both consolidate and recombine past moments.

The decision is needed now because imagination is a shared dependency: replay (ADR-0022), self-learning's "imagination gap" trigger (ADR-0026), goal proposal (ADR-0033), and emotion's appraisal of imagined outcomes (ADR-0035) all hook into it. Its pattern representation and its four operating modes must be fixed before those consumers are built.

## Decision
We evolve `core/imagination.nova` from **10 fixed seed patterns into a learned, extensible pattern library**, and define **four operating modes** over it. An imagination *pattern* becomes a first-class atom (`atom_new`, ADR-0016) in an imagination KG: a reusable transformation template — "given a situation atom-cluster, produce a successor cluster by applying transform T." The 10 seeds are bootstrap entries; new patterns are *abstracted from experience* by detecting, in episodic replay (ADR-0022), recurring (situation -> outcome) deltas, generalizing them via the concept layer (ADR-0018), and minting a new pattern atom with Bayesian confidence (alpha/beta, `core/belief.nova`) that rises as the pattern's predictions verify against reality (ADR-0024 prediction error).

The four modes are: (1) **Forward simulation** — roll the substrate forward from the current moment using high-confidence patterns to predict near-future states (feeds planning in ADR-0033, predictions in ADR-0024). (2) **Counterfactual** — clamp one or more atoms to alternative values and re-simulate, comparing to the factual trace to attribute causation (consumes SIG_CAUSAL operators from ADR-0031). (3) **Dream** — low-constraint recombination of episodic fragments during deep idle, used for consolidation and novel-pattern discovery (the primary source of new pattern atoms). (4) **Scenarios** — multi-step, branching forward sims with explicit decision points, used for long-horizon goal evaluation. All four run as bounded substrate propagation over `NTYPE_REASONER`/`NTYPE_REMEMBERER` nodes, scheduled in the imagination idle loop.

## Options Considered
- **Keep the 10 fixed patterns, hand-add more (rejected).** Zero new machinery; founders extend the catalogue as needs arise. Rejected because it makes imagination's reach a function of founder time, not system experience — directly capping the continuous-learning and initiative capabilities (ADR-0049's capability tests). It also can't adapt per-domain after deployment.
- **Single generic "simulate" routine, no explicit patterns (rejected).** One forward-rollout function parameterized at call sites. Simpler representation. Rejected because counterfactual, dream, and scenario modes have genuinely different constraint and scheduling profiles; collapsing them loses the ability to learn *mode-specific* patterns and to budget dream-time separately from forward sims.
- **LLM-driven scenario generation (rejected outright).** Prompt the bridge for "what could happen next." Rejected per ADR-0014; imagination must be substrate activation with provenance, not generated prose.
- **Learned pattern atoms + four explicit modes (CHOSEN).** Patterns grow from experience via replay and concept abstraction; modes give principled scheduling and constraint differences. Most complex option, but the only one delivering experience-driven growth plus the distinct cognitive uses CrossEngin needs.

## Consequences
- **Positive:** Imagination reach grows with experience, not founder labor; counterfactual reasoning becomes a first-class, testable capability; dream-mode doubles as memory consolidation, sharing cost with ADR-0022. Pattern confidence is Bayesian and self-correcting via prediction error (ADR-0024). Mode separation lets us budget idle time precisely.
- **Negative:** Learned patterns can be spurious; we need a death/GC path (ADR-0025) for low-confidence patterns to prevent library bloat and "superstitious" simulation. Dream recombination is the hardest to test (no ground truth) and risks consuming idle cycles; needs hard caps. Four modes increase surface area for the idle scheduler.
- **Future work:** Counterfactual mode underpins the override "what-if" explanations (ADR-0044) and richer theory-of-mind simulation of the user (ADR-0039). Scenario mode feeds sub-goal tree expansion (ADR-0033). Long-term, pattern abstraction could itself become a learned meta-pattern.

## Implementation Notes
- Files: extend `core/imagination.nova` with `imagine_forward`, `imagine_counterfactual`, `imagine_dream`, `imagine_scenarios`, plus `pattern_new`/accessors stored in an imagination KG (`core/knowledge.nova`, ADR-0017). Confidence via `core/belief.nova`.
- Pattern abstraction hooks into replay in `mind/memory.nova` (ADR-0022): detect recurring deltas, generalize through `core/concept.nova` (ADR-0018), mint pattern atoms.
- Scheduling: register modes with the imagination idle loop (ADR-0036) under idle-detection hooks; counterfactual/forward consume ADR-0031 operators and emit ADR-0024 predictions.
- Testing: forward-sim accuracy vs held-out episodic continuations; counterfactual causal-attribution fixtures with known interventions; assert dream-mode is interruptible and bounded; NO-LLM guard (ADR-0014).
- `DEPENDS ON: NOVA enhancement #13` — idle-detection + background scheduling hooks for replay/imagination. `DEPENDS ON: NOVA enhancement #4` — SIMD/GPU batched propagation for branching scenario sims. `DEPENDS ON: NOVA enhancement #8` — multi-KG namespacing for the imagination KG and cross-refs to source episodes.
