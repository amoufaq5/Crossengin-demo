# ADR-0095: Embodiment — sensorimotor architecture and robotics control

## Status

Proposed

## Date

2026-06-15

## Context
The Edge edition (ADR-0091) explicitly names robots and vehicles as targets, and
the output path already routes cognition to motor effectors: ADR-0013 generates
output as concept activation flowing to motor effectors, and the enhancement
roadmap's P4 adds effectors under `src/io/effectors/`. But driving a real robot —
let alone a humanoid — needs far more than an output path. It needs a closed
**sensorimotor loop** (perception in, action out, continuously), and it needs that
loop to be **real-time and safe** in a way deliberative cognition is not. This ADR
exists to set the embodiment boundary and its hard constraints *before* any
robotics work begins, because those constraints (hard real-time, physical safety)
propagate back into the runtime and into the constitution.

Two facts shape the decision. First, NOVA is unusually well-suited to physical
control: it compiles to native code via raw syscalls with **no garbage collector**
and a deterministic arena model, so there are no GC pauses to jitter a control
loop — a genuine advantage over GC'd languages for robotics. Second, the
cognitive substrate ticks at ~100Hz (ADR-0037), which is appropriate for
deliberation but **too slow and too jittery** for balance, force control, and
collision reflexes, which need kHz-scale, bounded-latency loops. Cognition and
control therefore cannot be the same loop. Rule 1 (NOVA everywhere) also means we
cannot adopt a robotics middleware (e.g. ROS) — the control stack and device I/O
must be native NOVA, which is a large undertaking we must be honest about.

## Decision
We adopt a **two-tier embodiment architecture** with a symmetric sensor/motor
boundary, and we make physical safety an embodied, non-overridable layer:

- **Sensor boundary (in).** Add `src/io/sensors/` symmetric to the effector
  boundary: sensors (vision, audio, proprioception, force/IMU) are converted to
  **moments** and injected as signals into the perception part of the substrate
  (ADR-0001), reusing the existing moment/perception path and existing vision/audio
  pipelines. Sensing is a signal-format conversion at the boundary; it produces
  signals, not interpretation (the same discipline ADR-0014 applies to STT).

- **Motor boundary (out).** ADR-0013 concept-activation output drives motor
  effectors under `src/io/effectors/` (P4).

- **Tier 1 — reflex/control loop (hard real-time).** A bounded, deterministic
  control loop running far faster than cognition (kHz-scale), responsible for
  balance, joint/force control, and **safety interlocks** (collision limits,
  force ceilings, emergency stop). It is isolated from cognition's scheduler and
  **cannot be starved** by deliberation — analogous to spinal reflexes versus
  cortical planning. This is what NOVA's no-GC determinism makes feasible.

- **Tier 2 — deliberative cognition (~100Hz).** The substrate (ADR-0001), debate
  engine (ADR-0089), and imagination/simulation (ADR-0032) set goals and issue
  *intentions* (target poses, trajectories, behaviors) to Tier 1; they never
  command actuators directly at the sample rate.

- **Embodied constitution.** Physical-safety rules are enforced in **two places**:
  as constitutional inhibitory signals in cognition (ADR-0045) *and* as hard
  interlocks in the Tier-1 loop that fire regardless of what cognition requests.
  Neither cognition nor the autonomous self-update loop (ADR-0092) may weaken or
  remove the Tier-1 interlocks — embodiment makes the non-revisable constitution
  (ADR-0045) literally a physical-safety guarantee, not just a behavioral one.

Simulation comes first: per the enhancement roadmap P5 (`src/sim/world_model.nova`)
and imagination's forward/scenario modes (ADR-0032), behaviors are validated in a
world-model simulation before touching hardware, addressing the sim-to-real gap as
an explicit stage rather than an afterthought.

## Options Considered
- **Adopt robotics middleware (ROS or similar) (rejected).** Mature ecosystem and
  drivers. Rejected on two grounds: it violates Rule 1 (a large third-party
  dependency), and mainstream ROS is not itself hard-real-time — it would not even
  give us the guarantee we most need. We build control + device I/O natively.
- **Single-tier control: cognition drives motors directly at 100Hz (rejected).**
  Simplest wiring. Rejected because 100Hz is too slow for balance/force control and
  cognitive jitter would be physically dangerous — a deliberation spike must never
  delay a collision reflex. Safety demands separation.
- **Teleoperation only, no autonomous control (rejected).** Safe and simple, but
  abandons the autonomy that is the whole point; useful only as an early bring-up
  mode, not the architecture.
- **Two-tier reflex + deliberative with embodied non-overridable safety interlocks
  (CHOSEN).** Matches the biological split, exploits NOVA's deterministic runtime
  for Tier 1, keeps cognition in charge of *what* without endangering *how*, and
  makes physical safety a hard floor. Most work, but the only safe autonomous
  option.

## Consequences
- **Positive:** NOVA's no-GC determinism is a real, defensible fit for Tier 1; the
  sensor boundary completes the loop the architecture only half-had (output
  existed, structured input did not); safety interlocks independent of cognition
  give a hard physical-safety floor; simulation-first reduces sim-to-real risk;
  realizes the Edge edition's (ADR-0091) robot target concretely.
- **Negative:** This is a multi-year, hardware-dependent program and the honest
  largest single undertaking in the roadmap — hard real-time on bare NOVA with no
  robotics ecosystem means building drivers, control, and sensor fusion from
  scratch; it is gated behind Edge distillation (ADR-0091), which is itself
  unsolved; safety-critical robotics invites certification and liability concerns
  far beyond software; a new NOVA runtime capability (a hard-real-time bounded
  control loop, stronger than the 100Hz tick of enhancement #5) is required and
  does not yet exist.
- **Future work:** Specify the hard-real-time scheduling enhancement upstream in
  NOVA (a sibling to #5); sensor-fusion and proprioceptive state estimation; tie
  the world-model simulation (P5) to imagination (ADR-0032) so the robot can plan
  by simulating; choose an initial hardware platform; a safety-certification path.

## Implementation Notes
- New `src/io/sensors/` (moment conversion into the perception part, ADR-0001),
  paired with `src/io/effectors/` (P4) for output (ADR-0013).
- A Tier-1 control module distinct from the cognitive scheduler (`runtime/
  scheduler.nova`, ADR-0037): bounded, deterministic, kHz-scale, with the safety
  interlocks as its highest-priority, non-preemptible path. Tier 2 issues
  intentions to Tier 1 over a bounded channel; back-pressure never blocks Tier 1.
- Embodied safety: physical-safety constitutional rules in
  `src/safety/constitutional_filter.nova` (ADR-0045) *and* as Tier-1 interlocks;
  assert (ADR-0092) that no self-update path can disable an interlock.
- Validate in simulation (P5 `src/sim/world_model.nova`) before hardware; route
  planned behaviors through imagination scenario mode (ADR-0032) first.
- Testing: a Tier-1 latency/jitter fixture (interlock fires within a bounded
  deadline regardless of cognitive load); a starvation test (a cognition spike
  never delays the reflex loop); a safety-interlock test (a motor intention that
  would exceed force/collision limits is overridden by Tier 1 and logged,
  ADR-0043); a self-update-cannot-disable-interlock test (ADR-0092); sim-to-real
  validation gating before any hardware actuation.
- DEPENDS ON: a NEW NOVA enhancement — hard-real-time bounded control scheduling
  (sibling to enhancement #5's 100Hz tick, but with deterministic latency
  guarantees); P4 effectors; a new sensor-ingestion path; NOVA enhancement #4
  (batched propagation) for sensor-volume perception. Builds on ADR-0001,
  ADR-0013, ADR-0032, ADR-0037, ADR-0045, ADR-0091, ADR-0092.
