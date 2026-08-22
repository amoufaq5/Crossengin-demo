# ADR-0102: Persona — full, per-user, advise-only

## Status

Proposed

## Date

2026-08-15

## Context

ADR-0100 named the cognitive architecture (Moment-Signal Cognition).
ADR-0106 introduced Capsules — shareable, named bundles of atoms.
Neither speaks to the SUBJECTIVE side of an intelligent agent: whose
values does the agent reason on behalf of, how does the agent's
emotion state track outcomes over time, how does the agent weigh a
proposed action against the user's risk tolerance and past decisions?

CrossEngin has partial machinery today:

- `Session.soul` (via `src/parts/soul/identity.nova`) — OCEAN traits
  + identity/purpose. Static per session.
- `src/agent/loop_emotion.nova` — a mood loop with valence + arousal.
  Runs but does not couple to decisions.
- `src/parts/meta/meta_observer.nova` — per-source atrophy tracking.
  Cross-cuts sources but not decisions.
- `src/safety/reversibility_classifier.nova` — flags irreversible
  actions. Hard gate, unrelated to persona.
- `src/safety/constitutional_filter.nova` — hard content blocks.
  Also unrelated to persona.

None of these compose into "the agent's model of its user." An
agent that knows *what* to do (skill runtime, ADR-0103) still
doesn't know *for whom* or *how they'd feel about it*. Without a
persona layer, Skills would have no principled way to say "this
proposal has predicted valence -300 for you based on 4 similar past
decisions where outcomes were negative." That prediction — surfaced
to the user, not enforced — is the piece the vision asks for.

The user's R45 architectural choices for this ADR were unambiguous:

1. **Full persona**, not a minimal (emotion+risk) subset.
2. **One per user**, not per-agent-user pair.
3. **Advise-only** — never veto a decision. Constitutional filter
   and reversibility classifier remain the hard gates.

This ADR turns those three commitments into a shape + a contract +
an implementation plan.

## Decision

We introduce **Persona** as a first-class per-user primitive with
full slot coverage: identity, OCEAN traits, current emotion state,
risk profile, decision history, learned preferences, self-reflection
log. One Persona per user. Persona projects onto proposed actions
(predicted valence shift + risk score + similar-past-decision
references) but NEVER blocks them — advisory input to the operator,
who retains final authority.

### The Persona shape

```
Persona = [
  user_id:           string,           primary key
  identity:          list,             [name, purpose, stated_values[]]
  ocean:             list,             [openness, conscientiousness, extraversion,
                                        agreeableness, neuroticism] (0..1000 milli)
  emotion:           list,             [valence, arousal, dominant_focus,
                                        last_update_moment]
  risk:              list,             [risk_tolerance, loss_aversion, uncertainty_appetite]
  history:           list<DecisionRec>, immutable append-only decision log
  preferences:       list<PrefRec>,     source-attributed accumulated preferences
  reflection:        list<ReflectionRec>, moment-tagged introspective observations
  style_capsule_ref: string,           name of preferred style capsule (ADR-0108)
  created_at:        moment
  updated_at:        moment
]

DecisionRec   = [moment, proposal_desc, chosen_option, predicted_valence,
                 actual_outcome_or_0, satisfaction_or_0, source_tag]
PrefRec       = [label, weight (-1000..+1000 milli), source_tag, moment_first,
                 moment_last, observation_count]
ReflectionRec = [moment, observation_text, source_tag]
```

Rationale for each slot:

- **`identity`** carries the same three fields the existing `soul`
  module has, so a Persona can be constructed from a Session's soul
  or migrated from it. NOT a duplicate; the Session slot for
  Persona will replace the soul once migration is complete.
- **`ocean`** encodes the Big Five in the same 0..1000 milli scale
  the belief system uses. Zero external ML dependency.
- **`emotion`** is deliberately small — valence + arousal is enough
  to project outcomes; a richer categorical emotion model can
  layer later without changing the shape (add a slot; existing
  callers unaffected).
- **`risk`** carries three dimensions because "risk tolerance"
  alone doesn't cover loss aversion (a user can accept high
  volatility but hate losses) or uncertainty appetite (unrelated to
  volatility — some users tolerate known risks fine but reject
  unknown-unknowns).
- **`history`** is APPEND-ONLY. Retracted decisions stay in the log
  (with retraction_marker), matching ADR-0088's audit posture.
- **`preferences`** are source-attributed just like atoms. A
  preference for "quiet workspaces" comes with the source tag of
  the observation that established it, so meta-observer can atrophy
  a preference source if the user later contradicts it enough.
- **`reflection`** is the agent's own observations about its user:
  "user historically prefers concise answers over exhaustive ones."
  Same shape as an atom-observation, but scoped to persona and
  never enters a KG. Retractable.
- **`style_capsule_ref`** is a forward hook for ADR-0108. Persona
  picks the preferred style; the NL templater consults it.

### The advise-only contract

The persona exposes ONE projection function:

```
persona_project(p, proposal) -> {
  predicted_valence_shift:   int (-1000..+1000 milli),
  predicted_arousal_shift:   int,
  risk_score:                int (0..1000 milli),
  similar_past_decisions:    list<DecisionRec>,
  matching_preferences:      list<PrefRec>,
  reasoning_trace:           list<string>   // human-readable
}
```

The projection is INFORMATIONAL. Callers (skills, the chat REPL,
future JSON-RPC clients) display the projection to the user
alongside the proposal and let the user decide. The persona itself
CANNOT block, cancel, or modify a proposal. Enforcement stays with
the existing hard-gate layer:

- `constitutional_filter` — content blocks
- `reversibility_classifier` — irreversible actions
- `capability_gate` + `permission_tiers` — authorization
- `override_mechanism` — explicit elevation

The persona INFORMS operator judgment; the hard gates ENFORCE
safety. Distinct concerns, distinct code paths.

### Observation → update loop

The persona LEARNS from outcomes without a training step:

- **Every completed decision** adds a DecisionRec to `history`.
- **Every stated preference** (from the user via `/persona
  prefer LABEL WEIGHT SRC` or inferred from N corrective
  interactions) adds/updates a PrefRec in `preferences`.
- **Every projection outcome** where `actual_outcome_or_0` gets
  filled in later becomes evidence — the projection's error
  updates the calibration of future projections. This is a small
  Bayesian shift over the projection weights, using the same
  primitive as `bel_observe` on atoms.
- **Every self-reflection** (either LLM-generated summary of a
  session under the ADR-0013 preprocessor stance, OR
  operator-written) appends a ReflectionRec.

Nothing about this loop needs training a model. Each observation is
one shift, source-tagged, retractable.

### One-per-user semantics

- One `Persona` per `user_id` string. The registry keyed on user_id
  ensures uniqueness.
- Cross-session: the SAME user across sessions gets the same
  Persona (subject to snapshot load path). A user's persona is
  their portable digital second-self.
- Multi-user host: a host can hold many personas (one per user);
  each Session references one persona by user_id. Cross-persona
  bleed is forbidden by the same isolation as cross-session
  cognitive state (ADR-0051).
- Import / export: `persona_export(p) -> serialized` +
  `persona_import(serialized) -> p` lets users migrate their
  persona between devices / instances. Format is the same
  self-describing wire pattern as snapshots (see ADR-0043).

### Explicit non-goals for v1

- **Not a full theory-of-mind.** The persona models the USER, not
  other agents. Modeling other agents (the classic ToM task) is a
  separate future ADR.
- **Not multi-persona per user.** Some future work may want
  "professional-me" vs. "personal-me" contexts. v1 says one
  persona per user; roles are a follow-up.
- **Not autonomous decision-making.** Persona projects, skills
  propose, humans decide. Even the safest projection never trips
  an effector directly.
- **Not integrated with the emotion loop yet.** `loop_emotion.nova`
  runs independently. This ADR names the interface; the wiring is
  in the implementation phase.

## Options Considered

1. **Full persona, one per user, advise-only (CHOSEN, per user's
   R45 answer to Question 4).**
2. **Minimal persona (emotion+risk only).** Faster to ship, but
   fails to represent the user in the way the vision asks — no
   history, no preferences, no reflection. Rejected in R45.
3. **One persona per (agent, user) pair.** Each skill gets its own
   view of the user. Cleaner data isolation but breaks the
   "portable digital twin" story — moving from the coding-helper
   skill to the medical-advisor skill loses everything the user
   ever told the coding one. Rejected in R45.
4. **Persona with veto authority.** Persona could block proposals
   below a risk threshold. Rejected in R45: safety enforcement
   should live with the existing hard-gate layer (constitutional
   filter, reversibility classifier), not with a subjective
   persona. Persona ADVISES, hard gates ENFORCE, humans DECIDE.
5. **Persona as a Capsule.** Attractive symmetry — a Persona is
   "just" a shareable bundle of preferences + reflections. Rejected
   because Persona has state (current emotion, current risk
   posture, updated_at) that Capsules don't; and one-per-user
   uniqueness is easier to enforce with a dedicated registry.

## Consequences

- **Positive:** Skills (ADR-0103) get a single injection point for
  "who is this user, what do they want, what have they told us
  before" — `skill_run(skill, perception, persona)`. Without a
  persona layer skills would each need to build this from scratch.
- **Positive:** The vision's "represents its owner" promise becomes
  concrete: the persona is portable, exportable, and every belief
  it holds about the user is source-attributed and retractable.
- **Positive:** Zero coupling to LLMs. All persona state is Bayesian
  belief + append-only logs + inspectable lists. Reads and writes
  from NOVA code with no external calls.
- **Neutral:** Adds another Session slot (17th, per R45p2's plan to
  add the CapsuleRegistry as the 16th). Snapshot format grows via
  the presence-flag pattern.
- **Negative:** Persona has more state than Session's current
  `soul` slot — migrating existing soul-only Sessions is a small
  chore (auto-migrate: `persona_from_soul(sl, user_id)` builds a
  fresh persona seeded with the soul's identity + OCEAN).
- **Negative:** Persona projection accuracy is bootstrap-cold. A
  new user gets uncalibrated advisory output until enough
  decisions land in `history`. Documentation must be honest about
  this.
- **Future work:** ADR-0103 (Skill Runtime) will declare the
  persona injection contract. ADR-0104 (NL surface) will consult
  the persona's style_capsule_ref when rendering. ADR-0108 (Style
  Capsules) will define what the templater does with the reference.

## Implementation Notes

**Modules to add:**

```
src/persona/persona.nova
    Persona shape, constructors, accessors, mutators (update
    emotion, add DecisionRec, add PrefRec, add ReflectionRec).

src/persona/persona_registry.nova
    Per-host registry keyed on user_id. One-per-user invariant.
    Register / lookup / list / remove.

src/persona/persona_project.nova
    The projection function. Walks history for similar
    proposals (by proposal-atom-label overlap), aggregates
    valence shifts, aggregates risk-score, returns the
    projection record.

src/persona/persona_export.nova
    Serialize / deserialize per the snapshot wire-format
    convention (ADR-0043 audit-log style; presence flag +
    length-prefixed sub-lists for forward-compat).
```

**Files to extend:**

```
src/session/session.nova
    Add SES_PERSONA slot (17th; 16th is CapsuleRegistry from
    R45p2). Add session_persona accessor.

examples/crossengin_chat.nova
    /persona                          -- summary of current user's persona
    /persona show                     -- full detail
    /persona set NAME PURPOSE         -- set identity (bootstrap)
    /persona ocean O C E A N          -- set trait vector (0..1000 each)
    /persona prefer LABEL WEIGHT SRC  -- add a preference
    /persona feel VALENCE AROUSAL     -- log current emotion
    /persona reflect TEXT             -- append a reflection
    /persona project PROPOSAL_LABEL   -- show advisory projection
    /persona export PATH              -- write persona to disk
    /persona import PATH              -- load persona from disk
```

**Snapshot round-trip:** persona serializes as
`[persona_present_flag, user_id, identity, ocean, emotion, risk,
history_count, history..., prefs_count, prefs..., refl_count,
refl..., style_capsule_ref, created_at, updated_at]`. Snapshots
without a persona flag restore cleanly (persona = 0).

**Test plan:**

- `test_persona_new_shape` — 10 slots, defaults sensible.
- `test_persona_identity_accessors` — get/set name/purpose/values.
- `test_persona_ocean_bounds` — 0..1000 milli enforcement.
- `test_persona_emotion_update` — updating bumps updated_at.
- `test_persona_add_decision` — history append-only; retract
  markers preserved.
- `test_persona_add_pref` — preferences source-tagged; duplicates
  update weight not append.
- `test_persona_reflection_append` — reflection append-only.
- `test_persona_registry_one_per_user` — duplicate user_id
  rejected.
- `test_persona_project_no_history` — cold-start projection
  returns zero shifts + empty similar list.
- `test_persona_project_with_history` — projection walks history
  and aggregates.
- `test_persona_project_never_blocks` — projection always returns
  a result, never a rejection.
- `test_persona_export_import_roundtrip` — bytes match.
- `test_persona_from_soul` — migration builds a valid persona.

**Deliberate reservation:** the persona's `project` function
returns a numeric valence_shift + risk_score, but v1 does NOT
attempt to combine these into a single "recommendation score." The
whole point of advise-only is to surface the FACTORS to the user,
not to hide them behind a synthesized number. If a caller (skill)
wants a scalar score, it composes valence + risk on its own with a
weighting derived from the user's stated preferences.

DEPENDS ON: ADR-0100 (Moment-Signal Cognition), ADR-0051 (Session),
ADR-0043 (audit log — persona history is a specialized audit log),
ADR-0088 (kernel + no-retract-erasure discipline extends to
persona history).
FEEDS INTO: ADR-0103 (Skill Runtime — declares persona injection
contract), ADR-0104 (NL surface — consults style_capsule_ref),
ADR-0108 (Style Capsules — defines what the templater does with
the reference).

## Role in the Model Substrate

Persona is the primitive that makes **per-user selective-load**
(consumption mode 2) meaningful and that gives every other
consumption mode a per-user identity to project against. The mother
holds one persona per user; a selective-load instance carries its
user's persona as portable digital-second-self; a baked child (mode
3) ships with a persona-set allowlist; a client app (mode 4) reads
and writes the persona over the RPC surface; an embedded deployment
(mode 5) holds a single owner's persona locally.

Within the reasoning triad, Persona is state that composes into the
**cognitive sandbox** — not a KG node and not a belief signal, but
per-user context the sandbox consults when a skill proposes, when
the NL templater phrases, and when advice-only projections run. The
persona layer is what lets the LLM-free primary NLP path (ADR-0104)
produce user-shaped answers without a sidecar LLM having to be
prompted with user history: history and preferences live here, in
inspectable Bayesian state, and the deterministic templater reads
them directly.

**See also:** ADR-0200 (five consumption modes — persona is
per-user across all of them), ADR-0204 (persona projection contract
inside the cognitive sandbox), ADR-0208 (persona-set allowlist in
bake manifests), ADR-0211 (LLM-free NLP primary path that consults
persona style + preferences deterministically).
