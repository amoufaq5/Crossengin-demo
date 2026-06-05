# ADR-0036: Six concurrent loops + imagination idle loop (true concurrency, fiber or process, communication channels)

## Status

Proposed

## Date

2026-05-25

## Context
The substrate model (ADR-0001) rejects orchestration: intelligence emerges from the dynamics of nodes, synapses, and signals running continuously, not from a top-level controller calling cognitive modules in sequence. For that emergence to be real, the agent's driving loops — perception, memory, reasoning, emotion, action, goals — must execute genuinely concurrently. If they are merely polled round-robin on one thread, the substrate is a disguised workflow: perception cannot keep ingesting moments (ADR-0021) while reasoning chews on a hard inference, emotion cannot appraise (ADR-0035) in parallel with action emission, and the "always-on companion" feel collapses into turn-taking latency.

NOVA today ships `agent/agent.nova` (the cognitive agent referenced throughout §3) plus `runtime/coroutine.nova` and `runtime/taskpool.nova`, but its scheduling is cooperative — coroutines yield voluntarily on a single executor. A blocking or long-running reasoning step would stall every other loop. We must decide the concurrency model for the six loops and for a seventh, the background imagination loop (ADR-0032) that should run only when the system is idle, replaying episodes (ADR-0022) and exploring counterfactuals without competing with live cognition.

Constraints: 2 founders at 8h/day, bootstrapping, NOVA as the implementation language (ADR-0005). v1 is a single-user desktop app (ADR-0046), so we have one machine's cores — not a cluster — and must keep the model debuggable by two people. Whatever we choose must communicate through typed channels so loops stay decoupled, and must survive the persistence/restart model (ADR-0048, ADR-0040).

## Decision
We implement the six loops plus the imagination idle loop as **seven true concurrent execution units** — fibers (green threads multiplexed over an OS thread pool) on v1, with the option to promote any unit to an OS process later. They communicate exclusively over typed message channels built on `runtime/chan.nova`, never via shared mutable memory. This requires NOVA enhancement #3 (true concurrent execution units with typed channels), since today's `runtime/coroutine.nova` is cooperative-only.

Each loop is a long-lived unit owning a clear slice of the substrate: perception drives `NTYPE_PERCEIVER` first nodes (ADR-0010) and emits moments; memory owns episodic store reads/writes (`mind/memory.nova`); reasoning runs the hybrid engine (ADR-0031, `mind/reasoning.nova`); emotion runs OCC appraisal (`mind/emotion.nova`); action owns `NTYPE_ACTOR` effectors and pure-substrate output (ADR-0013); goals runs the drive/goal engine (`core/goal.nova`, ADR-0033). Loops exchange `core/signal.nova` values (the 18-type taxonomy, ADR-0008) over channels: e.g. perception → memory and perception → reasoning carry `SIG_EVENT`/sensory; reasoning → goals carries `SIG_QUESTION`/goal-drive; emotion broadcasts valence/arousal signals that modulate plasticity (ADR-0007) in every other loop. The imagination loop is gated OFF during activity and ON during idle via enhancement #13's idle-detection hooks; it reads episodic + concept atoms and writes only to imagination scratch, never to live action.

The 100Hz substrate tick that advances node/synapse dynamics (ADR-0037) is NOT one of these loops; it is the scheduler layer beneath them. Loops are event-driven coordination on top of that tick.

## Options Considered
**Single-threaded cooperative coroutines (NOVA as-is, `runtime/coroutine.nova`).** Cheapest: no new runtime work, fully deterministic, trivially debuggable. Rejected as the primary model because a single long reasoning or fetch step (ADR-0028) blocks perception and emotion, destroying the concurrency the substrate thesis (ADR-0001) requires. We keep cooperative coroutines *inside* a loop for sub-tasks, but not across loops.

**One OS process per loop with IPC.** Maximum isolation and crash containment; a wedged reasoning process can be killed and restarted without taking down perception — attractive for the enterprise one-tenant-per-process model (ADR-0047). Rejected for v1: IPC serialization of millions of signals/tick is far too costly, shared substrate access (synapse arrays, KGs) across process boundaries needs heavyweight shared memory, and two founders cannot afford that plumbing on the desktop timeline. Retained as a v2 escalation path — the channel abstraction makes process promotion feasible later.

**Fibers/green threads over a thread pool with typed channels (CHOSEN).** Pre-emptible enough that no loop starves the others, cheap context switches so seven units cost little, shared address space so loops touch the same substrate without serialization, and `runtime/chan.nova` gives the typed decoupling we want. Matches enhancement #3 exactly. Rejected alternatives' best traits (determinism, isolation) are partially recovered via deterministic tick boundaries (ADR-0037) and the option to promote a loop to a process.

## Consequences
- **Positive:** Genuine concurrency — perception ingests while reasoning thinks while emotion appraises; the companion feels continuously alive. Channel-only communication keeps loops decoupled and individually testable. Imagination uses spare cycles for free (ADR-0032). Sets the structural basis for self-awareness (ADR-0038) since the agent can observe its own running loops.
- **Negative:** Concurrency bugs (races on shared synapse weights, channel deadlocks) are far harder to reproduce than in a cooperative model; we must impose tick-boundary discipline (ADR-0037) so weight mutations are batched, not interleaved arbitrarily. Hard dependency on un-landed enhancement #3. Debuggability cost is the price ADR-0001 already accepted for substrate dynamics.
- **Future work:** Per-loop promotion to OS processes for v2 isolation (ADR-0047); back-pressure policy when a downstream channel fills; integration with the decision log (ADR-0043) so cross-loop signal traces are auditable.

## Implementation Notes
Loops live in `agent/agent.nova` as seven unit spawns; define `loop_spawn(kind, in_chans, out_chans)` and a `LOOP_*` tag constant per kind (`LOOP_PERCEPTION`, `LOOP_MEMORY`, `LOOP_REASONING`, `LOOP_EMOTION`, `LOOP_ACTION`, `LOOP_GOALS`, `LOOP_IMAGINATION`). Channels are `channel_new(name, source, destinations, CHAN_DIRECT|CHAN_BROADCAST, filter_min_salience, 0)` from `core/channel.nova`; emotion's valence/arousal uses `CHAN_BROADCAST`. Carry `core/signal.nova` values; respect priority/trace fields for ADR-0043 auditing. Imagination's on/off uses enhancement #13 idle hooks from `runtime/scheduler.nova`. Testing: a fixture that floods the perception channel while stalling a fake reasoning step and asserts perception throughput and emotion appraisal continue (no head-of-line blocking); a deadlock detector test on full channels; a determinism test asserting weight mutations only commit at tick boundaries. `DEPENDS ON: NOVA enhancement #3 — true concurrent execution units (fibers/green threads or processes) with typed channels for the 6 loops.` Also depends on enhancement #13 (idle scheduling) for the imagination loop. Sequenced after the scheduler (ADR-0037) and the agent skeleton in the build plan (ADR-0050).
