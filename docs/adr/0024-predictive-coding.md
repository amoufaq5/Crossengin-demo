# ADR-0024: Predictive coding between layers (top-down predictions, bottom-up errors)

## Status

Proposed

## Date

2026-05-25

## Context
A substrate that only reacts to input is inert; an AGI-relevant substrate must *anticipate* and learn from the gap between what it expected and what arrived. Predictive coding is the mechanism: higher/abstract parts continuously send top-down predictions to lower/perceptual parts, lower parts compute the residual (prediction error) against actual input, and only the *error* propagates upward to update beliefs and synapse weights. This is the substrate's primary unsupervised learning engine — it is what makes synapse error-driven plasticity (ADR-0007) have an error to be driven by, what surfaces surprises that trigger self-learning (ADR-0026), and what gives replay (ADR-0022) something to correct during idle.

The signal vocabulary already anticipates this: ADR-0008 defines **predictive** and **error** signal types among the 18. The decision here is the *protocol* — how predictions flow down, how error is computed and flows up, how the loop is timed against the 100Hz tick (ADR-0037), and how it couples to belief updates (ADR-0023) and plasticity (ADR-0007) — without an LLM anywhere in the loop (ADR-0014). Constraint: 2 founders on a 100Hz substrate; prediction/error must be a per-tick local computation at nodes, not a global optimization. We must also avoid runaway feedback (predictions reinforcing themselves into hallucination).

## Decision
We implement predictive coding as a **per-tick bidirectional protocol between adjacent parts**, using the `predictive` and `error` signal types from ADR-0008. Each part maintains, at its first nodes (ADR-0010), an incoming **prediction buffer** of top-down `predictive` signals for the next tick. When actual bottom-up input arrives (a moment's signals, ADR-0021, or lower-part activations), each receiving node computes a residual: `error = actual_activation - predicted_activation`, scaled by precision (confidence). The node emits an `error` signal upward **only when** `|error| > theta_err` (default `theta_err = 0.15` on normalized [0,1] activations) — small, well-predicted input is suppressed and does not propagate, which is the efficiency win of predictive coding. Predictions themselves are generated top-down: higher parts emit `predictive` signals derived from currently-active atoms/concepts (ADR-0016/ADR-0018) down through their synapses each tick.

Error signals carry high priority in the gate dispatch (ADR-0009) — surprise should preempt routine processing. Upward error drives three consumers: (a) **synapse plasticity** — error-driven weight update (ADR-0007/enhancement #12), strengthening connections that would have predicted correctly; (b) **belief update** — a persistent prediction failure for an atom contributes contradicting evidence to its Beta belief (ADR-0023); (c) **self-learning** — sustained high error (a running mean above `theta_surprise = 0.3` over a 1-second window) emits a curiosity/`SIG_CORRECTION` signal triggering ADR-0026.

To prevent runaway feedback, predictions are **precision-weighted and bounded**: a prediction's influence is scaled by the source belief's certainty (`belief_strength`, ADR-0023), and prediction signals decay if not refreshed each tick, so a part cannot bootstrap itself into a self-confirming loop. During idle, replay (ADR-0022) runs the same loop offline so the system can learn from re-experienced episodes.

## Options Considered
**1. Per-tick bidirectional predictive/error protocol with thresholded error suppression (CHOSEN).** Aligns with the predictive/error signals already budgeted in ADR-0008, makes learning unsupervised and local (cheap per tick), suppresses well-predicted input for efficiency, and feeds plasticity, beliefs, and curiosity from one mechanism. Cost: tuning thresholds and guarding against feedback. Chosen because it is the canonical, biologically-grounded fit for the substrate thesis (ADR-0001) and unifies three learning consumers.

**2. Pure reactive substrate, no top-down prediction.** Input flows up, responses flow out, no predictions. Rejected: there is no prediction error, so error-driven plasticity (ADR-0007) is starved of signal, the system cannot be *surprised* (no prediction-error trigger for ADR-0026), and it cannot anticipate the user (undermining initiative and theory-of-mind, ADR-0039). Anticipation is a named v1 capability.

**3. Explicit forward-model module that predicts next state globally.** A dedicated module computes a global next-state prediction each tick. Rejected: that is orchestration, not substrate (violates ADR-0001), it is a single bottleneck incompatible with 1M-node parts and the six concurrent loops (ADR-0036), and a global model is far harder to tune than local per-node residuals.

**4. Backpropagation-style end-to-end error.** Train the whole substrate by backprop. Rejected: backprop requires global differentiability and synchronized passes that the asynchronous, sparse, 100Hz substrate (ADR-0003, ADR-0037) is not built for, and it is heavy for a 2-founder team. Local predictive coding gives most of the learning benefit with local, tick-friendly updates and maps directly onto enhancement #12 kernels.

## Consequences
- **Positive:** Unifies unsupervised learning (drives ADR-0007 plasticity), surprise detection (drives ADR-0026 self-learning), and belief revision (ADR-0023) under one local mechanism; error suppression of well-predicted input saves signal throughput (relevant to the 1B-signals/part budget, ADR-0003); gives the system genuine anticipation for theory-of-mind (ADR-0039) and replay-based offline learning (ADR-0022).
- **Negative:** Threshold/window constants (`theta_err=0.15`, `theta_surprise=0.3`, 1s window) need calibration and may vary per part; feedback-stability guarding (precision weighting + prediction decay) adds subtlety and a class of hard-to-debug oscillation bugs; bidirectional signaling roughly doubles inter-part signal traffic on poorly-predicted streams.
- **Future work:** Learned per-part precision; hierarchical predictive coding across more than two adjacent layers; coupling prediction-error magnitude into emotion appraisal (surprise as an emotion, ADR-0035); using accumulated error maps to prioritize what to learn (ADR-0026/ADR-0030).
- **NOVA-enhancement flag:** this is a primary consumer of error-driven plasticity kernels.

## Implementation Notes
- Use ADR-0008 `predictive` and `error` signal types (extended tags over `core/signal.nova`). Prediction buffers and residual computation live at first nodes (ADR-0010); `node_get_state`/`node_set_state` hold `predicted_activation`; residual emitted via `node_emit` as an `error` signal with high `priority` (ADR-0009 gate fast-path).
- Error -> plasticity: feed into ADR-0007 synapse weight update (enhancement #12 kernels over weight arrays). Error -> belief: call `belief_update(..., supports=false, now_tick)` from ADR-0023. Error -> curiosity: emit ADR-0008 curiosity/`SIG_CORRECTION` for ADR-0026 when running-mean error exceeds `theta_surprise`.
- Precision weighting reads `belief_strength` (ADR-0023); prediction decay handled in the per-tick scheduler step (ADR-0037).
- Testing: `fixture_predict_match` (well-predicted input -> error below `theta_err` -> NO upward signal), `fixture_predict_miss` (surprising input -> error signal emitted, target synapse weight moves per ADR-0007, contradicting evidence applied to belief), `fixture_no_runaway` (unrefreshed predictions decay; no self-confirming oscillation over 1000 ticks), `fixture_surprise_trigger` (sustained error -> curiosity signal to ADR-0026).
- Dependencies: ADR-0008 (predictive/error signals), ADR-0007 (plasticity target), ADR-0023 (belief updates + precision), ADR-0010 (first nodes), ADR-0009 (priority routing), ADR-0026 (surprise trigger), ADR-0022 (replay reuses the loop), ADR-0037 (tick timing).
- DEPENDS ON: NOVA enhancement #12 — Hebbian + error-driven plasticity kernels over synapse weight arrays (the error signal's primary sink).
- DEPENDS ON: NOVA enhancement #4 — SIMD/GPU batched signal propagation (top-down prediction fan-out across millions of synapses per tick).
