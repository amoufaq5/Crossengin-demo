# ADR-0021: Moments (timestamped perception, lifecycle, episodic integration)

## Status

Proposed

## Date

2026-05-25

## Context
Every external input to CrossEngin — a user utterance, a sensor reading, a clock event, an internet-fetch result (ADR-0028) — must enter the substrate through a single, uniform, timestamped record. Without one canonical entry point, perception, episodic memory, and emotion would each invent their own input representation and the system would lose the ability to say *when* something happened, *what state it was in* at the time, and *which downstream activity that input caused*. The substrate thesis (ADR-0001) demands that input become signals flowing through nodes; the question is what durable object anchors that flow to wall-clock time and to the episodic record.

NOVA already provides `core/moment.nova` — a timestamped perception record (singular file, per §3). We are deciding the moment's full lifecycle: how raw input is wrapped into a moment, how a moment is fanned out into signals at the perception part's first nodes (ADR-0010), how the moment is correlated with the resulting cognition, and how it is finally handed to episodic memory (ADR-0022). The constraint is a 2-founder team on a 100Hz tick: moment creation must be cheap (allocation-free on the hot path) and must not stall the perception loop (ADR-0036). A desktop v1 single user generates perhaps 10^3-10^4 moments/day, so storage volume is modest but the *correlation* machinery (linking a moment to the trace of signals it spawned) must be designed once and reused for v2.

The moment is also the unit the No-LLM-Cognition principle (ADR-0014) protects: when STT converts audio to text via the modality bridge, the *text* enters as a moment payload — the bridge never reasons, it only fills a moment's `raw` field.

## Decision
We adopt the moment as the immutable timestamped envelope for all external perception, with a four-phase lifecycle: **capture -> fan-out -> correlation -> consolidation handoff**. Extend `core/moment.nova` with a richer layout `[TAG_MOMENT, id, timestamp, modality, raw, salience, origin_part, signal_trace, soul_state_ref, status]` and a constructor `moment_new(modality, raw, salience)`. `timestamp` is the 100Hz tick index plus monotonic ns (from `runtime/scheduler.nova`); `modality` is an enum (TEXT, AUDIO_STT, SENSOR, CLOCK, FETCH, INTERNAL). The moment is created at the gate boundary (ADR-0009) before any node sees it, so the entry point is uniform regardless of source.

On **capture**, the moment is stamped and a snapshot reference to current soul state (ADR-0034 — fast-changing state vector) is copied into `soul_state_ref` so the episode later records "what mood/goal-context surrounded this perception." On **fan-out**, the gate emits `SIG_EVENT` (or `SIG_QUESTION`/`SIG_ORDER` per `core/signal.nova`) signals carrying `moment=id` in the signal's `moment` field (already in the `core/signal.nova` layout) to the perception part's first nodes. As those signals propagate, each visited node appends to the signal's `trace`; a lightweight **correlation collector** in the memory loop accumulates the union of traces keyed by `moment.id` into `signal_trace`. After a bounded settle window (default 200ms / 20 ticks, or earlier on quiescence), the moment's `status` flips PERCEIVED -> SETTLED and it is handed to episodic memory (ADR-0022) for storage and eventual consolidation. Moments are append-only and never mutated after SETTLED; corrections arrive as *new* moments (modality INTERNAL, `SIG_CORRECTION`), preserving an honest history for the decision log (ADR-0043).

## Options Considered
**1. Moment as immutable timestamped envelope with trace correlation (CHOSEN).** Gives a single uniform entry point, a wall-clock anchor, and a causal bridge from input to the cognition it triggered (via `signal_trace`). Reuses `core/moment.nova` and the existing `trace` field on signals. Cost: the correlation collector adds a per-moment accumulation pass. Accepted because the trace is exactly what episodic recall, emotion appraisal (ADR-0035), and the decision log all need, so the cost is amortized across three consumers.

**2. No moment object — input becomes signals directly.** Simpler: the gate just emits signals and skips the envelope. Rejected because signals are ephemeral (§2) and carry no durable timestamp or soul-state snapshot; episodic memory would have nothing concrete to store, and we would lose the ability to reconstruct *when* and *in what state* perception occurred. The substrate would be amnesic about its own inputs.

**3. Moment as a mutable record updated throughout cognition.** Let downstream parts write conclusions back into the moment. Rejected: mutation destroys the honest "what was actually perceived vs. what was inferred" boundary that the safety/audit layer (ADR-0009/ADR-0043) depends on, and it creates write-contention on a hot object across the six concurrent loops (ADR-0036). We instead keep moments immutable and let inference live in atoms (ADR-0016).

**4. Per-modality record types (TextMoment, SensorMoment, ...).** Type-specialized envelopes. Rejected for the same reason nodes are uniform (ADR-0006): specialization belongs in learned state and in the `modality` enum, not in proliferating types that the gate, episodic store, and consolidation would each have to branch on.

## Consequences
- **Positive:** A single uniform, timestamped entry point for all input; honest immutable perception history; a built-in causal link (moment -> signal trace -> atoms) that powers episodic recall (ADR-0022), emotion appraisal of moments against goals (ADR-0035), and full per-action traces in the decision log (ADR-0043). STT/TTS isolation (ADR-0014) is structurally clean: the bridge only fills `raw`.
- **Negative:** The correlation collector adds bookkeeping on every perception and a bounded settle latency (200ms) before episodic handoff; tuning the settle window per modality is future tuning work. Immutability means corrections cost an extra moment rather than an in-place edit.
- **Future work:** Adaptive settle windows driven by quiescence detection; moment compaction for high-frequency sensor modalities in v2; richer `soul_state_ref` snapshots once the soul wrapper (ADR-0034) stabilizes.

## Implementation Notes
- Extend `core/moment.nova`: constructor `moment_new`, accessors `moment_timestamp`, `moment_trace`, mutator `moment_set_status` (PERCEIVED/SETTLED/CONSOLIDATED), tag constant `TAG_MOMENT`, modality enum constants.
- Capture happens at the gate (ADR-0009) using `channel_new`-derived gate routing; fan-out emits via `node_emit` to ADR-0010 first nodes; the signal carries `moment` per the `core/signal.nova` layout. Correlation collector lives in the memory loop (ADR-0036) and reads signal `trace` lists.
- Handoff target is `mind/memory.nova` (ADR-0022); soul-state snapshot reads from `core/soul.nova` (ADR-0034).
- Testing: fixtures `fixture_moment_text`, `fixture_moment_stt`, `fixture_moment_clock`; assert (a) timestamp monotonicity across a 100Hz tick burst, (b) `signal_trace` captures the exact node set a known input reaches, (c) immutability — post-SETTLED writes rejected, (d) bridge fills only `raw`.
- Dependencies: ADR-0008 (signal types), ADR-0009 (gates), ADR-0010 (first nodes), ADR-0022 (episodic store), ADR-0034 (soul state), ADR-0043 (decision log).
- DEPENDS ON: NOVA enhancement #5 — 100Hz deterministic tick scheduler (for `timestamp` tick index and the settle window).
- DEPENDS ON: NOVA enhancement #6 — extended signal tag space (so `SIG_EVENT`/`SIG_CORRECTION` and CrossEngin's 18 types carry `moment` ids with fast dispatch).
