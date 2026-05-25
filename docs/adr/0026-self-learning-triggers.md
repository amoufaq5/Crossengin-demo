# ADR-0026: Self-learning triggers (unknown query, curiosity drive, imagination gap, prediction error, user request, all combined)

## Status

Proposed

## Date

2026-05-25

## Context
CrossEngin's headline capability is continuous, self-directed learning: the substrate must notice its own ignorance and act to close gaps without being told to. Today the substrate only learns passively (Hebbian co-firing per ADR-0007, atom birth per ADR-0025). That is insufficient for a desktop companion that should improve between conversations. We need an explicit, auditable answer to the question "what events should cause the system to start a learning episode?"

The hard constraint is that learning is expensive and partly external (internet fetch per ADR-0028, asking the user per ADR-0027), so triggers cannot fire indiscriminately. With 2 founders at 8h/day and a v1 desktop budget, we cannot afford a runaway curiosity loop that hammers the network or pesters the single user. We also must respect the NO-LLM-COGNITION principle: trigger detection is pure substrate signalling, not a prompted classifier.

A complication is that learning impulses arise from several independent substrate sources at once. A single user utterance can simultaneously be an unknown query, provoke a prediction error, and excite the curiosity drive. We therefore need not only a set of triggers but an arbitration policy that fuses concurrent impulses into at most one learning episode with a coherent target.

## Decision
We define five named self-learning triggers, each emitted as a substrate signal extending the taxonomy of ADR-0008, all converging on a meta-part "learning arbiter" (a set of `NTYPE_REASONER` nodes in the meta part):

1. **Unknown query** — the Reader's fetch/route/learn stage (ADR-0012, stage 5) finds no atom above the lexical/spreading-activation salience floor for an incoming `SIG_QUESTION`. It emits a `curiosity` signal tagged `gap=lexical`.
2. **Curiosity drive** — `core/goal.nova`'s curiosity drive (one of its 4 drives) crosses an activation threshold (drive level > 0.6) during idle, emitting a `goal-drive` + `curiosity` pair targeting the lowest-competence domain reported by ADR-0020.
3. **Imagination gap** — `core/imagination.nova`, during the idle imagination loop (ADR-0032), runs a forward/counterfactual rollout that terminates in an under-specified atom (confidence alpha+beta < 8 per ADR-0023); it emits `curiosity` tagged `gap=model`.
4. **Prediction error** — predictive coding (ADR-0024) produces a bottom-up `error` signal whose magnitude exceeds a persistent-surprise threshold (running error > 0.4 sustained over 5 ticks); this marks a systematic model deficiency, not noise.
5. **User request** — an explicit `SIG_ORDER`/`SIG_REQUEST` like "learn about X" or "look this up" maps directly to a learning episode at top priority.

The **arbitration policy**: the arbiter buffers all learning signals within a 200ms window (≈20 ticks at 100Hz), deduplicates by target concept (via `core/concept.nova` IDs), and scores each candidate episode by `priority = source_weight × competence_gap × goal_alignment`. Source weights are fixed: user request 1.0, prediction error 0.7, unknown query 0.6, imagination gap 0.4, curiosity drive 0.3. The highest-scoring candidate becomes the active learning episode; others are queued (max depth 8, decay-evicted). At most one external-fetch episode runs concurrently to respect ADR-0028 rate limits. User-request episodes always pre-empt autonomous ones.

## Options Considered
- **Single trigger (unknown-query only).** Simplest; the system learns only when it visibly fails to answer. Rejected: it makes the system purely reactive, never curious or self-correcting, killing the initiative and continuous-learning capabilities (ADR-0049's capability tests) that justify the whole project.
- **Five independent triggers with no arbiter (each fires its own episode).** Easy to implement per-trigger. Rejected: concurrent impulses cause duplicate fetches for the same concept, network/rate-limit thrashing (ADR-0028), and conflicting writes to the same atom; with one user and one device this is wasteful and confusing.
- **Five triggers + windowed scoring arbiter (CHOSEN).** Captures all impulse sources but fuses them into a coherent, prioritized queue with a single external episode at a time. More code than the naive approach but bounded and auditable.
- **Learned trigger policy (a trained gate decides when to learn).** Most adaptive long-term. Deferred: needs a reward signal and training data we won't have at v1, and risks opacity. We keep weights fixed and revisit as future work.

## Consequences
- **Positive:** The system becomes proactively self-improving from five complementary sources; arbitration prevents redundant or runaway learning; every episode has a traceable trigger source recorded for the decision log (ADR-0043).
- **Negative:** Fixed source weights are a tuning liability and may need hand-adjustment per user. The 200ms fusion window adds latency before a learning episode starts. A persistent high curiosity drive could still starve the queue of user-relevant learning if weights are mis-set.
- **Future work:** Replace fixed source weights with a learned policy once an intrinsic-reward signal exists; feed episode outcomes back into ADR-0020 competence estimates; let ADR-0035 emotion (e.g., frustration from repeated prediction error) modulate trigger thresholds.

## Implementation Notes
- New module `mind/learning.nova` exposing `trigger_new(source_tag, target_concept, gap_score)`, `arbiter_step(tick)`, and state map keys `{source, target, priority, status}`. Trigger signals reuse the `curiosity`, `goal-drive`, `error`, and `goal-drive` tags defined in ADR-0008.
- Arbiter nodes live in the meta part (`NTYPE_REASONER`); they subscribe via a `CHAN_FILTERED` channel (`core/channel.nova`) keyed on the learning-signal tags.
- Reads competence from ADR-0020's self-model and confidence from `core/belief.nova` (alpha/beta) and `runtime/confidence.nova`.
- Test fixtures: inject a `SIG_QUESTION` with no matching atom (expect unknown-query episode); replay a sustained `error` signal (expect prediction-error episode preempting a queued curiosity episode); fire user "learn X" mid-curiosity (expect preemption). Assert at most one active external episode.
- DEPENDS ON: NOVA enhancement #6 — extended signal tag space for the trigger signals; #5 — 100Hz tick scheduler for the 200ms fusion window; #13 — idle-detection hooks so curiosity/imagination triggers only fire when idle.
