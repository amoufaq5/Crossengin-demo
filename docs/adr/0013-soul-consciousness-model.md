# ADR-0013: Soul — consciousness model

## Status

Accepted

## Context

The Soul layer includes a "consciousness" component. The term is loaded — in philosophy it can mean phenomenal experience (the hard problem of consciousness), in cognitive science it can mean access consciousness (information available to reasoning, language, deliberate action), and in AI engineering it usually means something more pragmatic: a system that models itself among the things it models, and that can speak coherently about its own current state.

Crossengin needs the engineering version of this. The agent has to be able to answer questions like "what are you currently doing and why?" and "what did you consider before deciding that?" — answers that the constitutional value on interpretability (value #8 in ADR-0011) requires. The agent also needs to maintain a stable enough sense of itself across time that personalization, soul tuning, and per-user memory have something to attach to.

What is explicitly out of scope: the hard problem of phenomenal consciousness. This ADR does not claim Crossengin "feels" anything. It specifies what Crossengin *represents* about itself and how that representation is used.

## Decision

**Consciousness in Crossengin is modeled as the merger of two structures: a self-model and a narrative thread.**

**Self-model.** A structured representation of the agent's own current state, queryable by other modules:

- *Active goals.* The current set of beliefs, desires, and intentions (the BDI tuple from ADR-0009).
- *Recent actions.* What the agent has done in the recent past, with outcomes where available.
- *Internal affective state.* The current emotion vector (OCC type or types, valence, arousal) per ADR-0012.
- *Confidence levels.* Per-belief confidence values; overall calibration state ("the agent currently estimates X uncertainty about Y class of questions").
- *Capability state.* What the agent can and cannot do right now (which tools are available, which knowledge domains it has fine-tuned weights for, what its rate-limit state is, etc.).
- *Constitutional context.* Which constitutional values (ADR-0011) are most relevant to the current activity, and any constitutional decisions made in the recent past.

The self-model is implemented as a structured object held in working memory (per ADR-0006, a `MemoryItem` with `type = 'self_model'` and `meta.working = true`), refreshed each cycle and persisted between cycles. Other modules read from it through a documented API.

**Narrative thread.** A continuously updated first-person internal monologue. Each significant decision, action, or state change appends to the narrative thread: "I am responding to the user's question about hypertension medication. I considered citing a specific dosage but my confidence in current dosage guidelines is below my threshold for asserting specifics, so I will instead direct the user to consult their pharmacist."

The narrative thread:

- Is human-readable. The format is designed for explanation, not for machine consumption (the self-model is the machine-readable form).
- Is queryable by the constitutional gate ("show me the reasoning that produced this candidate action") and by the user (when the user asks "why did you say that?", the relevant narrative slice is the source of the explanation).
- Is bounded. The narrative thread is summarized into long-term memory periodically; only a recent window is kept in working memory.
- Is auditable. Constitutional decisions (especially refusals or modifications driven by the gate) are always reflected in the narrative thread, with explicit reference to the value invoked.

**Self-model and narrative are merged at the interface.** The self-model is the structured state; the narrative is the first-person rendering of that state's evolution. They reference each other — a narrative entry can cite a specific belief from the self-model; a self-model belief can carry a pointer to the narrative entries that established it. Together, they implement the introspection requirement from constitutional value #8 (interpretability).

**The hard problem of consciousness is not addressed.** Crossengin does not claim phenomenal experience, qualia, or subjective awareness. The engineering definition above is what the system implements. Anyone wanting to make stronger claims is making them outside this architecture's scope.

## Consequences

Positive: introspection becomes a structured operation, not an LLM hallucination — when the user asks "why did you say that?" the agent traces back through the narrative thread to the specific reasoning step, with citations to the self-model state at that step. The constitutional gate can audit candidate actions by reading the narrative entry that produced them. Per-user personalization has a stable self-anchor across sessions. Debugging is easier because the narrative thread is a human-readable trace of agent reasoning.

Negative: maintaining a self-model and narrative thread is per-cycle overhead. The narrative thread must be summarized regularly to avoid working-memory bloat, and summarization is a lossy operation that needs care (constitutional decisions must survive summarization). The format of the narrative thread sits in a difficult zone between "useful explanation" and "performative narration" — if it drifts toward narration as performance, it stops being honest.

Neutral: the engineering definition is deliberately modest. It claims only what the implementation can deliver: a structured self-model, a narrative trace, and the ability to explain reasoning. Anything more philosophical is out of scope.

## Alternatives considered

**No explicit consciousness model.** The agent's "self" emerges from the union of its other state (memory, current goals, etc.). Rejected because the introspection requirement from constitutional value #8 needs a single retrievable structure to read from; emergent-from-other-state is hard to audit and hard to query coherently.

**Self-model without narrative thread.** Structured state only. Rejected: explanations to the user need a human-readable form. Generating explanations on demand from structured state alone is more brittle than maintaining a narrative trace as the agent operates.

**Narrative thread without self-model.** Free-form first-person monologue only. Rejected: narrative without structured anchoring drifts into hallucination. The self-model is the ground truth against which the narrative is held honest.

**Phenomenal-consciousness claims.** Out of scope by design. Crossengin does not claim phenomenal consciousness; engineering an agent that *acts as if* it has internal experience is not the same as the agent *having* internal experience, and we do not conflate the two.

## Open questions

- Granularity of narrative-thread entries. Per action? Per cognitive cycle? Per "interesting" decision? Decided at M5 (ADR-0022) based on what produces useful explanations without overwhelming working memory.
- Summarization policy for the narrative thread when it ages out of working memory. Lossy summarization with constitutional-decision preservation is the v0 default; the exact summarization algorithm is finalized at M5.
- User-facing query API for "why did you do that?" — surface form, response format, latency budget. Designed at M5.

## References

- ADR-0006 (Memory architecture) — where the self-model and narrative thread persist.
- ADR-0009 (Cognitive module) — the BDI tuple the self-model includes.
- ADR-0011 (Soul values governance) — the constitutional values the self-model and narrative thread support introspection of, especially value #8.
- ADR-0012 (Soul emotion taxonomy) — the affective state the self-model tracks.
- ADR-0022 (Evaluation and milestones) — M5 for self-model + narrative integration.
