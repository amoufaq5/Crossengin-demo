# ADR-0206: Beliefs and Self-Awareness (First-Class Cognitive State)

## Status

Proposed. Promotes belief and self-awareness from scattered atom-
level state (`atom_belief`, `belief_decay`, `bayesian_updates`) to a
model-wide SELF-MODEL that the daemon can articulate: an aggregated
confidence surface, a known-unknowns register, a meta-observer as
introspective loop, and a volitional override layer gated by human
authority. Adds three wire verbs: `self.confidence`, `self.gaps`,
`self.override`. Every primitive already ships under
`src/parts/meta/`, `src/safety/`, and `src/learning/`; this ADR
composes them into a coherent self-model.

## Date

2026-08-22

## Context

Beliefs live at the atom level today. Each atom carries a
`belief_confidence` value updated by `bayesian_updates`, decayed by
`belief_decay`, born and retired by `atom_birth_monitor` and
`atom_death_monitor`. The reasoning engines read these per-atom
values when answering. What the daemon does not do is aggregate
them: it does not have a self-report of "how confident am I about
topic X overall," it does not have a register of "here are the
things I know I do not know," it does not have an introspective loop
that observes its own state as it reasons.

Introspection is not a nice-to-have. The ADR-0200 vision includes:

- Legal / medical / finance customers whose regulator requires the
  model to say "unknown" rather than confabulate.
- Enterprise customers who need to audit not just what an answer
  was but what the model believed about the underlying facts, and
  what it did not believe strongly enough to assert.
- Users who want to trust the system's answers, which requires the
  system to be honest about uncertainty.

The claim in ADR-0207 that CrossEngin obsoletes RAG rests on the
same primitive: "everything is known or explicitly unknown, no
black-box guessing." That claim is only true if the model can
enumerate its unknowns.

The primitives to compose already exist:

- `src/parts/meta/meta_observer.nova` — the introspective observer
  attached to every skill invocation and every ingest turn.
- `src/safety/override_mechanism.nova` — the volitional override
  layer with four tiers: belief-edit (change a specific belief),
  goal-veto (suppress a goal), hard-stop (pause reasoning),
  kill-switch (terminate the daemon).
- `src/safety/constitutional_filter.nova` — the rules that gate
  what a self-override can express.
- `src/safety/differential_privacy.nova` — the noise layer that
  guards self-report against membership-inference on training-data
  provenance.
- `src/learning/belief_decay.nova` — time-based belief attenuation.
- `src/learning/bayesian_updates.nova` — new-evidence integration.
- `src/learning/atom_birth_monitor.nova` and
  `src/learning/atom_death_monitor.nova` — atom lifecycle events
  the self-model consumes to populate its known-unknowns register.

## Decision

### The self-model, in three surfaces

The daemon exposes three views of its own cognitive state:

1. **Aggregated confidence surface.** For any topic (a KG atom, a
   capsule, a query kind), the daemon reports an aggregate belief
   value derived from the underlying atoms plus a spread indicator
   (how much internal disagreement there is). Answer: "on topic X,
   I believe with weight 750 out of 1000; internal spread is low."

2. **Known-unknowns register.** A living list of gaps: topics the
   daemon has been asked about but cannot answer with confidence,
   plus topics whose atoms have died (retracted / decayed below
   threshold / gated out by review). Answer: "here are 47 topics I
   have been asked about in the last 30 days that I do not have
   strong evidence for."

3. **Meta-observer introspective loop.** The meta-observer becomes
   the runtime surface that emits self-model updates during
   reasoning. Every skill invocation, every atom access, every
   belief update goes past the meta-observer; the meta-observer
   aggregates them into the two views above.

### Wire verbs

Three new verbs:

- `self.confidence{topic}` — returns
  `{aggregate: milli, spread: milli, contributing_atoms: n,
    provenance_summary: [...]}`.
  The topic can be a KG atom label, a capsule name, or a `query_
  shape`. The returned aggregate is the meta-observer's rolling
  average of the underlying atoms' belief weights, weighted by
  provenance authority per ADR-0029.
- `self.gaps{filter?}` — returns
  `[{topic, last_asked, gap_kind, suggested_ingest}, ...]`.
  `gap_kind` is one of `NO_ATOMS`, `LOW_BELIEF`, `RECENTLY_DIED`,
  `HIGH_SPREAD_DISAGREEMENT`. `suggested_ingest` names a source or
  capsule that would fill the gap.
- `self.override{directive, justification, operator_id}` — accepts
  a volitional directive that the daemon applies via
  `override_mechanism`. Directive is one of the four tiers
  (belief-edit, goal-veto, hard-stop, kill-switch); every override
  is stamped in the audit log with `operator_id` and
  `justification`.

### Introspective loop shape

The meta-observer already observes every skill invocation. This ADR
adds two subscriptions:

- Atom belief transitions (`bayesian_updates` emits an event when a
  belief crosses a threshold band).
- Atom birth / death (`atom_birth_monitor` and
  `atom_death_monitor` emit lifecycle events).

The meta-observer aggregates these into per-topic rolling summaries
kept in a bounded in-memory table (LRU by last-access). The self-
model surfaces read from this table; when a caller asks about a
topic not in the table, the meta-observer computes on-demand from
the underlying atoms and caches the result.

### Volitional layer gating

The override layer is not autonomous. Every `self.override` call
requires an operator (`admin` tier capability) and a `justification`
free-text field that lands in the audit log. The daemon does not
override itself; a human always does. This is the constitutional
constraint: the daemon has a volitional capacity, but the trigger is
external.

Constitutional filter (`constitutional_filter.nova`) gates what
directives are legal:

- Belief-edit: allowed for any atom the operator has capability
  over.
- Goal-veto: allowed for any goal the operator has capability over.
- Hard-stop: allowed always (a fast circuit-breaker).
- Kill-switch: allowed always; requires a second operator's
  confirmation on the same call (two-party).

### Privacy-aware self-report

`self.confidence` and `self.gaps` can leak training-provenance if
returned verbatim (which sources contributed how many atoms). The
returned `provenance_summary` is passed through
`differential_privacy.nova` (Laplace mechanism, epsilon per-topic
budget) so that repeat queries on the same topic do not accumulate
into a full inversion. Operators can raise or lower the epsilon
budget per role.

## Consequences

### Positive

- Transparent cognitive state. Users and operators can inspect what
  the model believes and what it does not; auditors can walk from
  an answer to the belief surface that produced it.
- Enables the ADR-0207 obsolescence claim. A model that can say
  "unknown" credibly does not hallucinate; the self-model is the
  primitive that makes "unknown" a first-class answer.
- Grounded volition. The model has a volitional capacity but the
  trigger is human; the two-party kill-switch and audit-logged
  belief-edit prevent unattended override.
- Composes existing primitives. No new inference algorithm.

### Negative

- Surfacing "what the model doesn't know" is UX-sensitive. A user
  who asks a routine question and gets "here are 47 gaps around
  your topic" is annoyed; the client (mode 4) has to filter and
  frame gap-reports carefully.
- The meta-observer's aggregation table is a new hot spot. Bounded
  LRU keeps it small but sustained high-query workloads may still
  push against the bound.
- Differential-privacy budget management is real work. Operators
  who do not tune epsilon will either leak provenance or over-noise
  their self-reports.
- Override audit is only as strong as the operator_id it accepts.
  Weak operator authentication undermines the volitional layer's
  guarantees.

### Neutral

- The three verbs are additive; existing verbs are unchanged.
- Cached self-model state is derived; on a restart it repopulates
  on-demand and eventually reaches the same distribution.

## Alternatives Considered

1. **Keep beliefs atom-only, no aggregate (rejected).** Would leave
   the ADR-0207 obsolescence claim unsupported. "The model knows
   what it does not know" requires the enumeration primitive.

2. **Self-model computed on-demand per query, no cached aggregation
   (rejected for latency).** ADR-0208 latency budget cannot afford
   a full underlying-atom walk on every `self.confidence` call.
   Bounded LRU cache is the compromise.

3. **Volitional layer as autonomous, model overrides itself
   (rejected on safety grounds).** A model that overrides its own
   beliefs unattended is exactly the shape ADR-0044 (override
   mechanism) exists to prevent.

4. **No differential privacy on self-report (rejected on
   compliance).** Verbatim provenance returns invert to full
   training-data disclosure over repeat queries; regulated
   customers cannot ship the daemon that way.

5. **Include LLM-generated "explanations" in `self.confidence`
   output (rejected).** Would put an LLM in the self-report path,
   which is the reasoning path by definition. Ships only the
   structured aggregate; the client (mode 4) can render.

## See Also

- ADR-0100 — Moment-Signal Cognition; MSC signals feed the self-
  model's aggregation.
- ADR-0202 — Cognitive sandbox; the environment in which beliefs
  update.
- ADR-0207 — RAG and fine-tuning obsolescence; that claim depends
  on this ADR's primitive.
- ADR-0044 — Override mechanism (existing).
- ADR-0038 — Self-model query API (existing precedent for the
  shape of these verbs).
- `src/parts/meta/meta_observer.nova` — the introspective loop.
- `src/safety/override_mechanism.nova` — the four volitional tiers.
- `src/safety/constitutional_filter.nova` — override gating.
- `src/safety/differential_privacy.nova` — self-report noise.
- `src/learning/belief_decay.nova` — belief attenuation.
- `src/learning/bayesian_updates.nova` — evidence integration.
- `src/learning/atom_birth_monitor.nova` /
  `src/learning/atom_death_monitor.nova` — lifecycle events.
