# ADR-0103: Skill Runtime — the composition point where knowledge serves users

## Status

Proposed

## Date

2026-08-15

## Context

Every layer built so far has been **substrate** — nodes and beliefs
(ADR-0100), capsules of knowledge (ADR-0106), persona of the user
(ADR-0102), safety gates (ADR-0028/0092), effectors (`src/io/effectors/`).
None of it, by itself, *does* anything for a user. A user asks "help me
debug this code" and today the answer is "type `/consistency` and hope
some atom shows up." The composition point is missing: the thing that
walks knowledge for a purpose, applies user context, gates through
safety, and returns a proposal the user can act on.

That composition point is a **Skill**. The user's R45 spec was
unambiguous:

> "Skills should be able to use knowledge taught to solve user's
> problems, for example it should use the coding knowledge to debug
> or do software tasks for users."

This ADR turns that sentence into a runtime.

What's already built that this composes over:

- **Capsules (ADR-0106)** — named shareable bundles of atoms. A skill
  declares required capsules as manifest fields. Supervisor refuses to
  start if any are absent.
- **Persona (ADR-0102)** — per-user identity + emotion + risk +
  history + preferences. Every skill invocation accepts a persona
  reference; every proposal it emits gets `persona_project()` called
  on it before returning to the user.
- **Effectors (`src/io/effectors/`)** — the layer that actually acts
  (file ops, HTTP requests, MCP calls, code execution). Skills
  declare effectors they need; supervisor passes them through the
  existing `effector_gate` + `capability_gate` + `reversibility_
  classifier` chain.
- **Meta-observer (ADR-0050)** — per-source atrophy. Every skill
  proposal carries source tag `src:skill:<name>:v<version>:<run_id>`
  so atrophy accumulates per skill + version.
- **Kernel (ADR-0088)** — for any FORMAL derivation a skill's policy
  wants to construct, the kernel gates it. Skills cannot mint pinned
  FORMAL atoms directly.

What's NOT yet built (and this ADR does NOT rebuild):

- A DSL for authoring skill manifests in a text file. v1 skills are
  authored in NOVA (their policy function IS a `fn`). A follow-on
  ADR can add a text-manifest parser.
- Autonomous skill scheduling. v1 skills fire on explicit user
  invocation (`/skill run NAME ARG...`). A future ADR-0111ish can
  add background-firing conditions.
- Skill marketplace / cross-host federation. v1 is local. Follows
  the same later-marketplace path as capsules.

## Decision

We introduce a **Skill Runtime** with four primitives — Manifest,
Policy, Supervisor, Registry — that compose Capsules + Persona +
Effectors + Gates into a runnable unit answering user problems.

### The four primitives

**1. SkillManifest** — the declarative shape of what a skill IS.

```
SkillManifest = [
  name:                string,           primary key
  version:             string,           semver
  description:         string,           one-liner
  required_capsules:   list<[name, min_version]>,
                                         supervisor refuses to start
                                         if any missing OR not installed
  capability_tier:     int,              TIER_USER / TIER_ELEVATED / TIER_ROOT
  effectors:           list<string>,     names of effectors this skill uses;
                                         supervisor gates each via
                                         effector_gate.
  refusal_conditions:  list<Condition>,  supervisor evaluates BEFORE the
                                         policy runs; any hit -> refuse
                                         with a named reason returned to
                                         the user (no policy call, no
                                         proposal emitted).
  policy_id:           int,              dispatch tag for the policy fn
                                         (NOVA doesn't uniformly expose
                                         function references; the runtime
                                         switches on this tag).
  attribution_prefix:  string,           default: "src:skill:<name>:v<ver>"
  license:             string
]

Condition = [kind, arg]      # e.g. [COND_MIN_CONFIDENCE, 700]
                             #      [COND_KG_EMPTY, "medicine"]
                             #      [COND_CAPSULE_UNINSTALLED, "biology"]
```

**2. Policy** — a NOVA function `(perception, kgs, capsules, persona,
supervisor_state) -> Proposal`. v1 policies are compiled into the
runtime and dispatched by `policy_id`. A skill's policy IS its
behaviour; everything else is declarative wrapping around it.

**3. Supervisor** — the lifecycle owner. One supervisor instance per
started skill. Wraps a Skill for its lifetime; snapshots + retires
cleanly.

```
Supervisor = [
  manifest:            SkillManifest,
  kg_registry_ref:     kg_registry,
  capsule_registry:    CapsuleRegistry,
  persona:             Persona,          (may be 0)
  effector_gate:       effector_gate handle,
  live_state:          list,             opaque per-skill state
  tick_count:          int,
  started_at:          moment,
  status:              int               SKILL_STARTING | RUNNING | REFUSED |
                                         RETIRED | ERROR
]
```

**4. Registry** — per-session skill registry, mirroring
`CapsuleRegistry` / `PersonaRegistry` shape.

### The invocation contract

```
skill_run(supervisor, perception) -> ProposalResult
```

Where:

```
ProposalResult = [
  ok:                    0 or 1,
  proposal:              string (or structured; for v1 a description),
  proposal_atoms:        list<atom_ref>,        atoms the proposal touches
  persona_projection:    Projection (from persona_project),
                                                (0 if no persona attached)
  effector_calls:        list<EffectorCall>,    what supervisor would run
                                                if user approves
  refusal_reason:        string                 non-empty iff ok=0
]
```

The runtime GUARANTEES:

1. **Refusal conditions are checked BEFORE the policy runs.** Any hit
   returns a `ProposalResult{ok=0, refusal_reason=...}` without
   invoking the policy. Consequence: a broken persona / missing
   capsule cannot make the policy return a garbage answer.
2. **Persona projection is ALWAYS attached** (when a persona is
   supplied), even for refused proposals — so the user can see
   "this would have been refused AND your persona projected -300
   valence anyway; probably good."
3. **Effector calls are DESCRIBED, not executed.** The
   `ProposalResult` lists what the supervisor WOULD run if the user
   approves. Approval is external (user, or a future higher-level
   skill supervisor).
4. **Every atom the skill touched flows into the meta-observer under
   the attribution prefix.** So per-skill atrophy is queryable:
   "which skills' proposals produce beliefs that die?"
5. **The persona is never modified by the runtime.** Skills READ
   persona; only user-authored `/persona ...` or explicit
   `persona_add_decision()` on approval mutates it.

### The safety perimeter (advise vs. enforce, clarified)

| Layer | Who enforces | What it does |
|---|---|---|
| Refusal conditions | supervisor | short-circuits BEFORE policy runs |
| Persona projection | supervisor | ADVISES the user (never blocks) |
| Capability tier | capability_gate | blocks below-tier calls |
| Constitutional filter | constitutional_filter | hard content blocks |
| Reversibility class | reversibility_classifier | flags irreversible → needs override |
| Effector gate | effector_gate | per-effector permission check |
| Override mechanism | override_mechanism | user's explicit elevation |

Refusal conditions are the FIRST filter (cheap check, no policy
cost). Persona projection is INFORMATIONAL (advise-only per
ADR-0102). The remaining layers are ENFORCEMENT (they can block).
Skills add zero new enforcement authority; they compose over the
existing gates.

### Reference skills to ship

**v1 skills (shippable with what exists today):**

- **`echo_skill`** (trivial reference). Takes a user query; walks
  the requested KG for atom labels matching the query tokens;
  returns a proposal listing atoms + beliefs + sources. No
  effectors. Serves as the runtime's smoke test.

- **`research_skill`**. Given `(topic, kgs)`, walks named KGs
  collecting atoms whose label overlaps the topic tokens (per the
  same tokenizer `persona_project.nova` uses). Aggregates beliefs.
  Reports contradictions surfaced by `mkgc_scan_conflicts`
  crossing the named KGs. Persona projection applied to the
  "answer this question" proposal. Effectors: none.

**v2 skill (needs a coding capsule to be genuinely useful):**

- **`coding_helper`** (the vision's example). Requires
  `coding:1.0.0` capsule + `debug_pattern:1.0.0` pattern capsule
  (ADR-0107). Given a user's problem description:
  1. Walks the coding capsule for language + concept atoms
     matching the problem tokens.
  2. Walks the debug pattern capsule for methodology atoms
     (reproduce → isolate → hypothesize → test → verify per
     ADR-0107 sketch).
  3. Composes a step-by-step proposal.
  4. Runs the proposal through `persona_project` for advice.
  5. If the user approves execution, dispatches
     `effector_code_exec` for each concrete step.
  Effectors: `effector_code_exec`, `effector_file_ops` (both
  already in `src/io/effectors/`).

  The `coding_helper` SHAPE ships in the runtime (manifest +
  policy_id + policy fn stub); the actual policy body will fill
  in once the coding + debug_pattern capsules exist.

### Chat commands (new)

```
/skill list                        registered skills, install state, deps
/skill info NAME                   full manifest detail
/skill install NAME                start supervisor (refuses if deps missing)
/skill uninstall NAME              stop supervisor
/skill run NAME ARG...             invoke policy; print ProposalResult
/skill history NAME                proposals this skill has emitted
```

## Options Considered

1. **Full runtime as designed above (CHOSEN).**
2. **Skills as free functions users call directly, no runtime.**
   Cheap. Rejected: no manifest, no dep declaration, no persona
   injection, no refusal-condition enforcement, no per-skill
   atrophy attribution. Every skill would re-invent all of this.
3. **Skills as capsules (unify).** Attractive symmetry — a skill
   is "just" a shareable bundle of policy atoms. Rejected: a skill
   has ACTIVE behaviour (a callable policy fn) that capsules
   deliberately don't; and skills declare capsules as dependencies,
   not the other way around.
4. **Skills as autonomous agents (background-firing).** v1 was
   originally sketched this way. Descoped in R45 to avoid the
   scheduling + interruption + resource-accounting complexity;
   v1 fires on user invocation only. Follow-on ADR can add
   background firing.
5. **Text-manifest DSL for authoring.** Would let non-NOVA users
   author skills. Rejected for v1 because the policy fn itself
   would still need NOVA; the manifest could parse but authoring
   would still be gated on NOVA fluency. Text-manifest revisit
   after a policy DSL exists.

## Consequences

- **Positive:** The composition point the vision asked for. Users
  can install a coding_helper, ask it to debug, and get a proposal
  that walks a real methodology capsule + honors their persona's
  risk profile + is refusable on low-confidence + logs to the audit
  trail — every layer already built serving one coherent purpose.
- **Positive:** Skill authors write ONE `fn` (the policy) and one
  manifest struct. All the rest — dep resolution, persona
  injection, refusal enforcement, effector gating, attribution — is
  runtime.
- **Positive:** Meta-observer per-skill atrophy becomes queryable:
  which skills produce beliefs that decay? Which skills' proposals
  the user consistently rejects?
- **Neutral:** Adds a SkillRegistry to the per-session state (18th
  Session slot, after CapsuleRegistry and PersonaRegistry from R45p3
  and R46p3.1 respectively). Snapshot round-trip via the same
  presence-flag pattern.
- **Negative:** Policy dispatch via integer tag (rather than
  first-class function refs) means a new skill requires a new tag
  constant + a case in the dispatcher. Not blocking, but adds a
  small central point of edit. Reversible when NOVA gains reliable
  function-reference support.
- **Future work:** ADR-0107 (Pattern Capsules) + ADR-0108 (Style
  Capsules) — both feed into skills; pattern capsules drive skill
  policies as state machines, style capsules configure how the
  NL renderer presents the proposal.

## Implementation Notes

**Modules to add:**

```
src/skills/skill_manifest.nova
    Manifest shape + constructors + accessors. Condition kinds:
    COND_MIN_CONFIDENCE, COND_KG_EMPTY, COND_CAPSULE_UNINSTALLED,
    COND_PERSONA_MISSING (extensible list).

src/skills/skill_registry.nova
    Per-session registry (register / lookup / install / uninstall /
    remove / list). Install resolves required_capsules against a
    CapsuleRegistry -- refuses if any is missing or uninstalled.

src/skills/skill_supervisor.nova
    Supervisor shape + lifecycle (start / retire) + runner
    (skill_run). runner enforces refusal conditions, dispatches
    policy by tag, attaches persona projection, packages the
    ProposalResult, attributes atoms via meta-observer.

src/skills/skill_dispatch.nova
    The policy dispatch switch. One `case` per registered skill_id
    tag. Grows with the reference skills below.

src/skills/skills/echo_skill.nova         (reference skill 1)
src/skills/skills/research_skill.nova     (reference skill 2)
src/skills/skills/coding_helper.nova      (reference skill 3, stub;
                                            filled in once coding
                                            + debug_pattern capsules
                                            exist)
```

**Files to extend (deferred if too much for one commit):**

```
src/session/session.nova
    18th SES_SKILL_REGISTRY slot. Same snapshot round-trip pattern.
    (This is R47p3 -- joint work with the capsule + persona slot
    additions.)

examples/crossengin_chat.nova
    /skill list | info NAME | install NAME | uninstall NAME |
    run NAME ARG... | history NAME
    Lazy-init _skill_registry mirroring _ingest_agent / _capsule /
    _persona_registry.
```

**Snapshot format:** SkillRegistry serializes as
`[skill_count, skill_1, skill_2, ...]` where each skill is
`[name, version, capabilty_tier, is_installed, tick_count,
started_at, live_state_blob]`. Manifests are code-defined, not
serialized (they're compiled in with their policy). Live state IS
serialized so mid-session skills can restore.

**Test plan (per ADR-0102's format):**

- `test_manifest_new_and_accessors` — shape validation
- `test_manifest_add_condition` — refusal condition wiring
- `test_registry_one_per_name` — dup rejected
- `test_supervisor_install_missing_capsule_refuses` — dep gate
- `test_supervisor_run_no_persona` — projection = 0, still runs
- `test_supervisor_run_with_persona` — projection attached
- `test_refusal_condition_short_circuits_policy` — policy NOT called
- `test_supervisor_attribution_flows_to_meta_observer` — per-skill tag
- `test_echo_skill_end_to_end` — reference smoke test
- `test_research_skill_topic_overlap` — token-based topic match
- `test_research_skill_contradiction_surfaced` — cross-KG scan
- `test_supervisor_retire_leaves_atoms_intact` — atoms outlive
  supervisor
- `test_skill_run_never_executes_effectors_directly` — always
  described, never dispatched (approval external)

**Reference skill priority for first commit:** `echo_skill` +
`research_skill` are shippable TODAY on the existing KG + capsule
substrate. Both prove the runtime end-to-end. `coding_helper`
manifest ships (so the tag + slot exist) with a placeholder policy
that returns an "insufficient content" refusal until the coding
capsule + debug pattern capsule land.

**Rollout sequence:**

1. This ADR (0103) — done.
2. `src/skills/skill_manifest.nova` + `skill_registry.nova` +
   tests. (R47p1)
3. `src/skills/skill_supervisor.nova` + `skill_dispatch.nova` +
   `echo_skill` reference + tests. (R47p2)
4. `research_skill` reference + tests. (R47p3)
5. `/skill ...` chat commands. (R47p4)
6. `coding_helper` shape + placeholder policy. (R47p5, ships
   ready to activate once coding + debug_pattern capsules exist)
7. When ADR-0107 + coding.cerec + debug_pattern.cerec land: fill in
   `coding_helper`'s real policy body.

DEPENDS ON: ADR-0100 (MSC), ADR-0106 (Capsules), ADR-0102 (Persona),
ADR-0088 (kernel discipline), ADR-0050 (meta-observer).
FEEDS INTO: ADR-0107 (Pattern Capsules — drive skill policies as
state machines), ADR-0108 (Style Capsules — render skill proposals),
ADR-0104 (NL surface — natural-language entry point to `/skill run`).
