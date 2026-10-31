# ADR-0210: Agent Production (Skills + Patterns + Composed Agents)

## Status

**Tier 1 shipped (R47 -- ADR-0103); tier 2 shipped R109 -- Phase J;
tier 3 (signed AgentPackage over the wire) deferred to a follow-up
round.**

Tier-2 delivery: `src/agents/agent_manifest.nova`,
`src/agents/agent_registry.nova`, `src/agents/agent_run.nova`, four
wire verbs (`agent.compose`, `agent.list`, `agent.run`,
`agent.retire`), `OWN_KIND_AGENT` overlay kind, `PREF_KIND_AGENT`
preference kind, `#AGENT v1` snapshot section, `ALLOW_AGENT`
BakeManifest directive, per-skill CAP_SKILL_RUN escalation-prevention
gate, and style-pin persona clone. See docs/SHIP_AS_APP.md §7.58.

Tier 3 (`agent.install <signed-package>`) is planned as R112 --
reuses `bundle_pkg_sign` from R99 to sign a composed AgentManifest for
distribution, verifies against `trust_anchor_registry` at install.

Names three tiers of agent production and how the daemon composes
them: in-tree reference skills (tier 1), runtime-composed pattern-
driven agents (tier 2), and user-authored agents delivered as signed
capsules (tier 3). Adds four wire verbs (`agent.compose`,
`agent.list`, `agent.run`, `agent.retire`), all of which route through
existing primitives — the R47 skill supervisor, the ADR-0107 pattern
registry, the R54.2 signed-install path (deferred to tier 3), the
meta-observer attribution stamp, and the review-gated ingest for any
atoms the agent produces.

## Date

2026-08-22

## Context

"Agent" is an overloaded word. In LLM-shaped systems, it typically
means a loop of tool calls driven by a prompt-driven planner. In
CrossEngin, an agent is a composed entity that:

- Accepts a query or a task specification.
- Executes inside the cognitive sandbox (ADR-0202).
- Composes a subset of skills, patterns, and KG walks to produce a
  proposal.
- Stamps every step it takes with meta-observer attribution.
- Emits atoms and edges through the review-gated ingest queue.

The primitives already ship. What is missing is the composition
layer: a way to say "for this class of query, compose these skills
under this pattern and this persona; run the composition; return
the ProposalResult." Users should be able to author agents outside
the daemon and install them with the same signing discipline that
gates skills.

## Decision

### Three tiers

**Tier 1 — In-tree reference skills.** The `echo`, `research`, and
`coding_helper` skills (ADR-0103) are the ground floor. Every agent
composes one or more of these; the skills themselves are the
canonical building blocks. Shipped via `src/skills/` and installed
by default.

**Tier 2 — Pattern-driven agents.** Composed at runtime from
`capsule + pattern + skill` triples. The pattern registry
(`src/capsules/pattern_capsule.nova`) already carries the shape:
"when the incoming query matches this pattern, invoke this skill
against this capsule, projected through this persona." Runtime
picks based on the parsed query kind plus the installed pattern
allowlist plus the caller's overlay. This tier requires no new
authorship; every installed pattern is already a compositional
agent.

**Tier 3 — User-authored agents.** Signed capsule packages
authored outside the daemon and installed via `agent.install` (a
new verb that layers on the R54.2 skill-signing pattern extended
per ADR-0203 to whole bundles). An authored agent is a manifest
that names:

- A composition graph (which skills, in which order, sharing which
  atoms).
- A signature over the manifest and its referenced artifacts.
- An intended trigger (an NL pattern, an explicit invocation, a
  scheduled event).

The manifest is a superset of the pattern capsule shape; a
pattern capsule is the simplest possible authored agent.

### Wire verbs

Four new verbs:

- `agent.compose{name, manifest}` — accepts an agent manifest
  (signed for tier 3; unsigned for tier 2 patterns installed in
  place); registers the composition; returns the registered
  agent id.
- `agent.list{}` — returns the registered agents plus their tier,
  their trigger, and their installed-vs-available status per the
  caller's overlay.
- `agent.run{name, input}` — invokes the agent by name; returns
  the ProposalResult produced by the composition. Every step is
  meta-observer stamped.
- `agent.retire{name}` — removes an agent registration.
  Retracting a tier-3 agent unregisters it but leaves its
  emitted atoms in the KG (they persist under their own
  provenance; audit-only).

### Composition graph shape

Tier-3 agent manifests carry:

```
AgentManifest = [
  name:                 string
  version:              semver
  trigger:              trigger_ref            // NL pattern, explicit, scheduled
  composition:          list<step>
  input_schema:         schema_ref
  output_schema:        schema_ref
  signature:            bytes                  // ed25519 over the above
  signing_certificate:  bytes                  // R55.1 trust-anchor evidence
]

step = [
  kind:          SKILL_RUN | PATTERN_MATCH | KG_WALK | ATOM_EMIT
  skill_ref:     name                          // for SKILL_RUN
  pattern_ref:   name                          // for PATTERN_MATCH
  walk_spec:     walk_ref                      // for KG_WALK
  emit_target:   kg_ref                        // for ATOM_EMIT
  input_slots:   dict<slot_name, source_ref>
  output_slots:  dict<slot_name, sink_ref>
]
```

The composition graph is a directed acyclic graph over steps.
Cycles are refused at registration. Slot wiring is checked against
the referenced skills' input / output shapes.

### Attribution

`meta_observer.nova` (existing) stamps every skill invocation with
`{invoker: agent:NAME:VERSION, step: N, parent_query: id}`. This
propagates through every ProposalResult and every emitted atom's
provenance. An agent that emits an atom leaves a full audit trail:
"agent LegalCiteChecker v1.2, step 4, from query Q, from user U."

### Ingest gate for agent-produced atoms

Every atom an agent emits (via a `ATOM_EMIT` step or as a side
effect of a skill invocation) goes through `rq_submit` and is
gated by `ingest.policy`. Agents cannot mint atoms into a
production KG unattended; the review queue is the same gate that
covers text ingest and multimodal ingest. Auto-approval for
agent-emitted atoms is configurable per agent per source-authority
weight (per ADR-0029).

### Signing and trust

Tier-3 agent manifests are signed using the R54.2 Ed25519 pattern
extended per ADR-0203 to whole bundles: the signing certificate
proves the author is a trusted issuer under the operator's trust
anchor list (R55.1). An unsigned or untrusted-signed agent refuses
to install.

## Consequences

### Positive

- Three-tier progression is natural. Skills are for the ground
  floor; patterns are for compositional agents that need no
  authorship; signed manifests are for third-party agents. The
  layers do not conflict.
- Every agent invocation is attributed. Auditor can trace any
  atom or answer to the specific agent, version, and step that
  produced it.
- Signing reuses R54.2. No new crypto primitive.
- Review gate for atom emission is the same one that gates ingest.
  A rogue agent cannot poison the KG unattended.
- Runtime composition uses the existing pattern registry. Tier 2
  ships the moment the four verbs land.

### Negative

- Composition-graph validation is real work. Slot type checking,
  cycle detection, unbounded-recursion refusal — each has a
  correctness bug pool.
- Signed-install ecosystem is a chicken-and-egg. Third-party agent
  authors need trust-anchor issuance from the operator; operators
  need agents to justify the trust-anchor tooling. First-party
  agents (Anthropic-issued reference agents, or CrossEngin project
  reference agents) will bootstrap.
- Retirement leaves emitted atoms behind (by design). Operators
  must understand that retiring an agent does not roll back its
  history; that is a `retract` operation on the specific atoms.

### Neutral

- The verb family is small (four verbs). The bulk of the surface
  is manifest schema and composition semantics.
- Tier-1 skills continue to be installed via `skill.install`;
  agent verbs do not replace that path.

## Alternatives Considered

1. **One-tier only, agents are just signed skills (rejected).**
   Would collapse the composition story into skill-authorship.
   Agents that compose multiple skills are common enough that the
   composition graph deserves its own shape.

2. **Composition graph in NOVA source rather than manifest
   (rejected).** Would require every agent to be a NOVA module;
   third-party authorship without daemon rebuild would be
   impossible.

3. **Agents as LLM-driven prompt loops (rejected).** Would put an
   LLM in the reasoning path, violating ADR-0013 / ADR-0014.

4. **No signing on agents, only on the skills they compose
   (rejected).** An unsigned agent that composes signed skills can
   still be malicious in its composition (bad step ordering, bad
   slot wiring). The agent manifest itself must be signed.

5. **Agents can bypass the ingest gate for their own atoms
   (rejected).** Would let a malicious agent poison the KG. The
   gate is the safety layer.

## See Also

- ADR-0103 — Skill runtime and the five guarantees (tier 1).
- ADR-0107 — Pattern capsules (tier 2).
- ADR-0202 — Cognitive sandbox; agent execution environment.
- ADR-0203 — Bake pipeline; agent manifests can bake into a child.
- ADR-0206 — Beliefs and self-awareness; agents can consult
  `self.confidence` / `self.gaps`.
- R54.2 — Ed25519 skill signing (extended for agent manifests).
- R101 — Auto-approval policy (`ingest.policy`).
- `src/skills/skill_supervisor.nova` — the invocation harness.
- `src/skills/skill_dispatch.nova` — integer-switch dispatch.
- `src/capsules/pattern_capsule.nova` — the pattern shape.
- `src/parts/meta/meta_observer.nova` — attribution.
- `src/sandbox/skill_signature.nova` — signing infrastructure.
