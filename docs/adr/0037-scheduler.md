# ADR-0037: Scheduler (hybrid: 100Hz substrate tick layered on event-driven coord)

## Status

Proposed

## Date

2026-05-25

## Context
The substrate is a physical system in software: ~1M nodes per part (ADR-0003), each with ~1000 sparse synapses (ADR-0007), with signals (ADR-0008) propagating and weights updating via Hebbian + error-driven plasticity (ADR-0012). Such dynamics need a regular clock — a tick — so that signal propagation, weight integration, decay (ADR-0023, ADR-0025), and predictive-coding error settling (ADR-0024) advance in consistent, batchable steps. Without a fixed tick, plasticity updates interleave nondeterministically across the seven concurrent loops (ADR-0036) and the system becomes impossible to reason about or reproduce.

But a pure fixed-rate tick is wasteful and unresponsive at the coordination level. Most wall-clock time on a desktop companion (ADR-0046) is idle waiting for user input; spinning every part at full rate burns battery and CPU for nothing, and high-level events (a user utterance arrives, a goal fires, a fetch completes — ADR-0028) are inherently asynchronous and should be handled when they occur, not polled. We therefore must decide how the low-level substrate clock and the high-level coordination relate.

NOVA provides `runtime/scheduler.nova` but not a deterministic fixed-rate tick fused with event-driven dispatch; that is enhancement #5. Constraints: one desktop machine, 2 founders, NOVA runtime (ADR-0005), and the concurrency model from ADR-0036 that this scheduler must drive.

## Decision
We adopt a **hybrid scheduler**: a deterministic ~100Hz (10ms period) substrate tick layered beneath an event-driven coordination layer, both in `runtime/scheduler.nova`, realizing enhancement #5. The tick is the substrate's heartbeat; events are how the seven loops (ADR-0036) coordinate.

Each 10ms tick performs one bounded round of substrate dynamics: drain node outboxes into synapse channels, propagate signals one hop (SIMD-batched per enhancement #4), integrate Hebbian + error-driven weight deltas (enhancement #12) **committed only at the tick boundary**, apply decay, and settle one predictive-coding pass (ADR-0024). Because all weight mutations commit at tick edges, the concurrent loops never see half-updated synapse arrays — this is how ADR-0036 stays race-free despite true concurrency. Tick rate is adaptive: 100Hz under active cognition, throttled toward ~10Hz (or fully quiesced with the substrate snapshot stable) when idle, at which point the imagination loop's idle hooks (enhancement #13) take over spare capacity.

The event layer sits on top: arriving moments (ADR-0021), goal activations (ADR-0033), emotion broadcasts (ADR-0035), fetch completions (ADR-0028), and inter-loop channel messages are events that wake the relevant loop immediately rather than waiting for a poll. An event may raise the tick rate (e.g. user utterance → 100Hz) and enqueues signals that the next tick propagates. Thus events decide *when* and *how fast* the substrate ticks; the tick decides *how* dynamics advance deterministically within each step.

## Options Considered
**Pure fixed-rate tick (everything polled at 100Hz).** Maximally deterministic and simple to reason about; trivially reproducible for testing. Rejected because it wastes CPU/battery during the long idle stretches of a single-user companion and adds up to 10ms latency to every high-level event that could be handled instantly. It also gives no natural place for idle-only imagination.

**Pure event-driven (no fixed tick).** Maximally responsive and efficient — work only happens on events. Rejected because substrate dynamics genuinely need a regular clock: Hebbian integration, decay, and predictive settling are rate-dependent processes, and without tick boundaries the concurrent loops (ADR-0036) would commit weight updates at arbitrary interleavings, reintroducing races and destroying reproducibility. Plasticity math (enhancement #12) assumes discrete steps.

**Hybrid: fixed tick beneath event-driven coordination (CHOSEN).** Keeps deterministic, batchable substrate steps for plasticity and SIMD propagation while letting coordination be responsive and cheap. The adaptive tick rate recovers the efficiency of the event-driven option during idle and the responsiveness for live interaction, while tick boundaries recover the determinism of the fixed-rate option. Matches enhancement #5 precisely. Slightly more complex than either pure model — the accepted cost.

## Consequences
- **Positive:** Race-free concurrency for ADR-0036 via tick-boundary weight commits; deterministic, reproducible substrate dynamics for testing (ADR-0049); responsive UX from the event layer; energy savings and a clean idle window for imagination (ADR-0032) via adaptive throttling and enhancement #13. SIMD batching (enhancement #4) has a natural per-tick granularity.
- **Negative:** Two coordination paradigms in one scheduler raise conceptual and debugging complexity; the adaptive rate logic (when to throttle, how fast to ramp) is a tuning surface that can misbehave (e.g. oscillating rates). Hard dependency on enhancement #5. A 10ms tick bounds worst-case substrate-event latency.
- **Future work:** Multi-rate ticking (fast parts vs. slow parts at different sub-rates); per-tick budget accounting feeding the decision log (ADR-0043); scaling the tick to 1B-node parts (ADR-0003) likely needs GPU-side propagation (enhancement #4) within the 10ms window.

## Implementation Notes
In `runtime/scheduler.nova` add `tick_run(substrate, dt_ms)` invoked from a monotonic 10ms timer, plus `event_post(kind, payload)` / `event_drain()` for the coordination layer; expose `tick_set_rate(hz)` for adaptive throttling and `TICK_RATE_ACTIVE`/`TICK_RATE_IDLE` constants. Tick phases as ordered functions: `phase_drain`, `phase_propagate` (calls `runtime/simd.nova` batch op), `phase_plasticity` (enhancement #12 kernels, commit at boundary), `phase_decay`, `phase_predict` (ADR-0024). Idle detection reuses enhancement #13 hooks to gate the imagination loop (ADR-0036) and lower the rate. The seven loops (ADR-0036) subscribe to events; the tick is owned by the scheduler, not by any loop. Testing: a deterministic-replay fixture feeding a fixed signal sequence and asserting identical weight arrays across runs; a latency test asserting an injected utterance event raises rate and is serviced within one tick; an idle test asserting rate throttles and imagination activates after N idle ticks. `DEPENDS ON: NOVA enhancement #5 — 100Hz deterministic tick scheduler fused with event-driven coordination.` Also leans on #4 (batched propagation), #12 (plasticity kernels), #13 (idle hooks). Built before the loops (ADR-0036) in the milestone plan (ADR-0050).
