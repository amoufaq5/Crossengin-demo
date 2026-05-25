# ADR-0022: Episodic memory (storage, decay, consolidation, replay during idle)

## Status

Proposed

## Date

2026-05-25

## Context
Settled moments (ADR-0021) must be retained as episodes so CrossEngin can recall specific past events ("what did the user ask last Tuesday?"), ground emotional appraisal in history (ADR-0035), and feed the imagination/replay loop (ADR-0032, ADR-0036). A flat, ever-growing log is untenable on a desktop: a multi-day companion accumulating 10^3-10^4 moments/day would bloat storage and slow recall, and most raw episodes have little long-term value. We therefore need a memory that *forgets gracefully* (decay), *distills* recurring structure into durable knowledge (consolidation into atoms, ADR-0016), and *rehearses* during idle to strengthen what matters (replay).

NOVA provides `mind/memory.nova` and `runtime/db.nova`. The decision is the storage tier structure, the decay schedule, the consolidation pipeline (episode -> atoms in domain KGs, ADR-0004/ADR-0017), and how replay is scheduled in the background imagination idle loop without competing with live cognition. Constraints: 2 founders, 8h/day; we cannot build a database engine, so we layer on `runtime/db.nova`. The replay loop must run only when idle (no live perception) so it never steals tick budget from the six live loops (ADR-0036) at 100Hz.

This ADR is explicitly flagged as a NOVA-enhancement consumer: idle-detection and background scheduling hooks are enhancement #13, and replay is the mechanism that links to the ADR-0036 imagination idle loop.

## Decision
We implement episodic memory as a **three-tier decaying store with idle consolidation and replay**, all in `mind/memory.nova` over `runtime/db.nova`. Tiers: **recent** (in-memory ring buffer, last ~24h or 4096 episodes, full fidelity), **archived** (on-disk via `runtime/db.nova`, decayed and gist-compressed), and **consolidated** (no longer episodes at all — distilled into atoms in domain KGs). An episode is `episode_new(moment_ref, salience, last_access, strength)` where `strength` starts at the moment's `salience` (ADR-0021) and `moment_ref` points back to the immutable moment.

**Decay:** each episode's `strength` decays exponentially with retrieval-based reinforcement: `strength *= exp(-dt / tau)` on each consolidation pass, with `tau = 7 days` for ordinary episodes and `tau = 90 days` for emotionally-tagged ones (high arousal/valence per ADR-0008 valence/arousal signals and ADR-0035). Each successful recall resets `last_access` and adds `+0.3` to `strength` (capped at 1.0). When `strength < 0.05`, the episode drops from `recent`/`archived` (but any atoms it already produced persist — memory of the *gist* survives loss of the *episode*).

**Consolidation:** during idle, a pass scans `recent`+`archived` for episodes whose traces (`moment.signal_trace`) repeatedly co-activate the same node clusters; recurring structure is handed to ADR-0025's atom-birth detector to mint or reinforce atoms, and the episode is marked CONSOLIDATED. **Replay:** the imagination idle loop (ADR-0036) samples episodes with probability proportional to `strength * salience`, re-injects their moments as INTERNAL signals (no new external moment), and lets the substrate re-traverse them — strengthening synapses (ADR-0007 Hebbian) and surfacing prediction errors (ADR-0024) for offline learning. Replay is strictly idle-gated via enhancement #13.

## Options Considered
**1. Three-tier decaying store with idle consolidation + replay (CHOSEN).** Bounds memory, distills durable knowledge into atoms, and rehearses high-value episodes for free during idle. Matches the brain-inspired substrate thesis and reuses `runtime/db.nova`. Cost: tuning decay constants and a non-trivial consolidation pass. Chosen because it is the only option that both bounds storage *and* turns experience into reusable knowledge.

**2. Flat append-only episodic log, never forget.** Keep everything forever in `runtime/db.nova`. Rejected: unbounded growth on a desktop, linearly slowing recall, and no distillation — the system would hoard raw episodes instead of learning from them. It also conflates the audit log (ADR-0043, which *is* append-only by design) with cognitive memory, which should forget.

**3. Pure consolidation, no episodic retention (everything becomes atoms immediately).** Convert each settled moment straight into atoms and discard the episode. Rejected: destroys the ability to recall *specific* events with their temporal context ("the conversation we had yesterday"), which is a named v1 capability (self-awareness over time, ADR-0049). Episodic and semantic memory are complementary; we need both.

**4. LRU cache eviction instead of strength-based decay.** Evict least-recently-used episodes. Rejected: LRU ignores emotional salience and recall frequency; a single emotionally pivotal episode accessed once could be evicted before trivial recent chatter. Strength-based decay with reinforcement and emotional `tau` extension models retention far better and ties cleanly to ADR-0035.

## Consequences
- **Positive:** Bounded, self-pruning memory on a desktop; specific-event recall with temporal+emotional context; automatic distillation of experience into durable atoms (ADR-0016/ADR-0025); free offline learning via replay that strengthens synapses (ADR-0007) and exercises predictive coding (ADR-0024). Emotionally significant episodes persist far longer (90d vs 7d tau).
- **Negative:** Decay constants (`tau`, reinforcement `+0.3`, drop threshold `0.05`) are hand-tuned and will need empirical calibration; consolidation and replay add background CPU that must be carefully idle-gated to avoid stealing from live loops; a bug in idle-gating could degrade live responsiveness.
- **Future work:** Learned (rather than fixed) decay schedules; cross-session replay prioritization tied to long-horizon goals (ADR-0040); per-tenant memory isolation for v2 (ADR-0047); sharper consolidation heuristics co-developed with ADR-0025.

## Implementation Notes
- `mind/memory.nova`: `episode_new`, accessors `episode_strength`/`episode_last_access`, `episode_decay(dt)`, `episode_reinforce`, tier-move fns `mem_archive`/`mem_consolidate`/`mem_drop`. Persist `archived`/`consolidated` via `runtime/db.nova`; `recent` is an in-memory ring.
- Replay re-injects via INTERNAL moments (ADR-0021) and `node_emit`; consolidation calls into ADR-0025 atom-birth. Salience/valence/arousal tags come from ADR-0008 and ADR-0035.
- Testing: fixtures `fixture_episode_burst` (decay-curve assertions), `fixture_emotional_episode` (90d tau retention vs 7d ordinary), `fixture_replay_idle` (replay fires only when idle flag set, strengthens expected synapses), `fixture_consolidation` (recurring trace -> atom minted via ADR-0025).
- Dependencies: ADR-0021 (moments), ADR-0016 (atoms), ADR-0025 (atom birth), ADR-0007 (synapse plasticity), ADR-0024 (prediction error during replay), ADR-0032/ADR-0036 (imagination idle loop), ADR-0035 (emotional tagging), ADR-0048 (rehydration order — episodic last).
- DEPENDS ON: NOVA enhancement #13 — idle-detection + background scheduling hooks (imagination/replay). Gates the consolidation and replay passes.
- DEPENDS ON: NOVA enhancement #10 — substrate snapshot + ordered rehydration (episodic restored last, after soul and KGs, per ADR-0048).
