# ADR-0200: CrossEngin as AI Factory (Mother/Child Architecture)

## Status

Proposed (north-star). This ADR names the platform frame that all
0013/0014/0100-series ADRs are components of. It does not supersede or
deprecate any prior ADR; it re-contextualizes them.

## Date

2026-08-21

## Context

### The industry default and why it is wrong for CrossEngin

The default architecture for "AI" in 2026 is a large language model:
knowledge is baked into frozen weights, updates require retraining,
the only modality is natural language, the reasoning path is opaque,
and the only shape available is "chat with a general model." The two
common escape hatches — RAG and fine-tuning — patch symptoms without
touching the underlying frame: knowledge is still weight-implicit,
reasoning is still weight-implicit, and the deploy story is still
"call somebody's hosted API from your machine."

CrossEngin's design has rejected that default from the beginning:

- ADR-0013 (output generation) and ADR-0014 (no LLM in cognition) draw
  a hard line — the reasoning path is LLM-free, top to bottom. Any
  answer traces to explicit atoms, edges, implications, and skill runs
  in the KG.
- ADR-0100 (Moment-Signal Cognition) names the four primitives —
  node, signal, moment, attribution — that reasoning is composed of.
- ADR-0101 (data acquisition), ADR-0103 (skill runtime), ADR-0104
  (NL surface layer), ADR-0105 (sandbox architecture), ADR-0106
  (capsules), ADR-0107 (pattern capsules), and ADR-0108 (style
  capsules) fill in the substrate the reasoning engines walk over.

What was left implicit was the **product frame**. Up to ADR-0109 the
story was "a self-hosted reasoning daemon that can also parse English
questions." That undersells what the pieces actually add up to.

### What the pieces actually add up to

Given a substrate whose knowledge is data (not weights), whose
reasoning is engines (not gradient descent), whose ingest pipeline is
review-gated (not scraped-and-baked), whose skills are signed and
sandboxed (ADR-0105, R54.2), whose ownership overlay is per-user
(R55.x), and whose wire is TLS-guarded at the socket (R86..R94), we
do not have "a self-hosted chatbot." We have the substrate from which
small, focused, domain-configured AI systems are built and maintained
without retraining anything.

That is a **platform** shape, not a product shape. The correct name
for it is a **factory**: the mother model bakes children; children
run on customer infra; the mother updates them over their lifetime
via signed KG-deltas. Enterprises license the factory. They deploy
the children.

### Why enterprises want this shape

Enterprises do not want an LLM. They want an auditable, compliant,
updatable, domain-scoped AI that runs on their own infra and never
ships their data to an external API. Concretely:

- Legal, medical, and finance teams need every answer to trace to a
  citation, and they need "unknown" to be a valid answer rather than
  a hallucinated guess.
- Security, compliance, and audit teams need the reasoning path to be
  inspectable end to end.
- IT and platform teams need the deployment to be a binary they run,
  not a vendor API they page.
- Ops teams need knowledge updates to take seconds, not weeks, and
  never require downtime.

CrossEngin's substrate satisfies each of these by construction. The
missing piece is the packaging layer that turns "one daemon per team"
into "one factory, many domain-scoped deployments." That packaging
layer is what this ADR names.

## Decision

We adopt the **Mother/Child architecture** as CrossEngin's north-star
platform shape.

- **Mother model** — the full CrossEngin daemon: substrate (KGs,
  capsules, ownership overlay, provenance) + reasoning engines
  (graph traversal, MSC signal propagation, skill runtime, pattern
  dispatch) + NL surface + multimodal sandbox + bake/deploy factory.
  The mother is what enterprises license.
- **Child model** — a baked snapshot bundle consisting of a
  domain-filtered KG subset, an allowlisted set of capsules /
  patterns / skills, a chosen persona and policy, and an NL adapter
  configuration. The child runs on a slim child-runtime — the same
  NOVA binary launched with `--child-mode` — with an immutable KG,
  no bake capability, no ingest capability, and no external network
  reach beyond its update channel back to the mother.

Enterprises license the mother. They deploy children. One mother can
bake and update an unbounded number of children.

### Diagram

```
              +--------------------------------------+
              |      MOTHER MODEL (CrossEngin)       |
              |                                      |
              |   [Substrate: KG + capsules + prov]  |
              |   [Reasoning: nodes + signals + ...] |
              |   [Sandbox: multimodal learner]      |
              |   [NL Surface: small-LLM adapter]    |
              |   [Bake & Deploy Factory]            |
              +--------------------+-----------------+
                                   | bakes / signs / updates
       +---------+----------+------+------+----------+--------+
       v         v          v            v          v        v
   [LegalAI][MedRefAI]  [FinanceOpsAI][SecReviewAI][RunbookAI][...]
       |         |            |             |          |
       v         v            v             v          v
    child     child        child         child       child
   runtime   runtime      runtime       runtime     runtime
   (immutable KG, no bake, no ingest, signed update channel to mother)
```

### Sub-decision 1: Knowledge is data, not weights

Every fact CrossEngin knows lives in the KG (atoms, edges,
implications, provenance) or in a capsule (ADR-0106) that names a set
of atoms. Nothing is hidden in an opaque tensor. Consequences:

- Any answer can be traced to the exact atoms and implications that
  produced it.
- Updates are surgical: one ingest turn adds one record; no retraining.
- Domain scoping is a set operation on the KG, not a fine-tune.
- Ownership, licensing, and provenance are first-class fields on
  every atom (ADR-0087).

### Sub-decision 2: Reasoning is plural

The reasoning substrate is not one algorithm. It is a composition of
engines, each suited to a different question shape, dispatched by the
NL surface via a `query_shape` (ADR-0104):

- Graph traversal — direct KG walks for "what is X", "how is X
  related to Y" (ADR-0031, ADR-0100).
- MSC signal propagation — moment/attribution-aware inference over
  atoms and edges (ADR-0100).
- Skill runtime dispatch — the 5-guarantee skill invocation contract
  (ADR-0103) that composes knowledge + persona + safety into a
  proposal.
- Pattern capsule matching — learned patterns invoke skills
  (ADR-0107).
- Multimodal sandbox — the internal learning surface that ingests
  non-text signal (ADR-0105, expanded below).

Different question shapes route to different engines. None of them is
an LLM.

### Sub-decision 3: The NL surface uses a small LLM, strictly at the boundary

ADR-0104 shipped a grammar-first parser with an LLM-preprocessor
fallback. The fallback was described as a shell-invoked adapter that
emits a StructuredQuery, never an answer. This ADR promotes that
fallback to a **first-class small-LLM adapter** (approximately 1B to
3B parameters) that sits STRICTLY at the NL boundary and does two
things only:

- Parse: natural language input becomes a registered `query_shape`.
- Render: a `ProposalResult` becomes natural language output.

The LLM never reasons. The LLM never decides. The LLM does not
retrieve facts. Contract enforcement is mechanical: the parse output
must validate against one of N registered `query_shape` schemas or is
rejected; the render output is constrained to a templated skeleton
whose slots are pre-filled from the ProposalResult, so the LLM has
no room to invent facts. This preserves ADR-0013/0014's invariant
verbatim — the LLM is at the surface, not in the reasoning path.

The size choice matters. A 1-3B parameter adapter fits alongside the
daemon on modest hardware, adds bounded latency, and — because it is
never the source of a fact — its known limits (hallucination,
recency, license concerns) are absorbed by the contract layer.

### Sub-decision 4: The multimodal sandbox is where CrossEngin learns from anything

ADR-0105 sketched the sandbox as a capability-separated execution
surface. This ADR expands its role: the sandbox is the site where
CrossEngin ingests, normalizes, and learns from non-text signal —
text, images, audio, video, structured data, code, sensor streams.

The sandbox does not embed. It extracts entities, relations, and
implications and stamps them into the KG as new atoms and edges,
tagged with sandbox-source provenance. Every sandbox-produced atom
is subject to the same review pipeline (ADR-0101) as human ingest:
provenance recorded, source authority weighted (ADR-0029), belief
tracked (ADR-0023), retractable.

This is how the substrate scales beyond text without dropping
inspectability: what the sandbox learns is written down as data, in
the same shape as everything else.

### Sub-decision 5: The bake mechanism

A `bake_child` operation takes a **bake manifest**:

```
BakeManifest = [
  child_name:        string
  child_version:     semver
  domain_filter:     kg_filter_spec       (namespaces, capsules, tags)
  capsule_allowlist: list<capsule_ref>
  skill_allowlist:   list<skill_ref>
  pattern_allowlist: list<pattern_ref>
  persona_set:       list<persona_ref>
  policy_set:        list<policy_ref>
  nl_adapter:        nl_adapter_config    (model id, size, prompt shape)
  update_key:        pubkey_ref           (mother key that will sign updates)
]
```

The bake produces a **signed child bundle**:

- The KG subset is emitted via the R73-R75 snapshot format (a shape
  already validated for chat-state persistence and cross-KG xref
  fidelity).
- The bundle is wrapped in an outer signature using the Ed25519
  skill-signing pattern established by R54.2, extended to whole
  bundles.
- The manifest, the KG snapshot, the capsule/skill/pattern sets, the
  persona and policy sets, and the NL adapter config are all in one
  verifiable artifact.

### Sub-decision 6: The deploy and update channel

- **Deploy** — the child runtime launches with `--child-mode
  --bundle=path/to/bundle`. It verifies the signature against a
  configured mother-public-key, mounts the KG snapshot as immutable,
  registers the allowlisted skills/capsules/patterns, and binds the
  RPC wire (over TLS, per R86..R94).
- **Update** — the mother produces a signed **KG-delta** (a small
  bundle: atoms added, atoms retracted, edges added, edges removed,
  capsules updated, provenance appended, manifest version bump). The
  child receives the delta via its update channel, verifies the
  signature, and applies it via the same overlay machinery that
  today handles per-user ownership merges (R55.x). No re-baking, no
  re-training, no downtime.

The update channel is client-pulled by default: the child polls or
subscribes; the mother does not initiate connections into customer
infra. A push-mode channel is a future option and is out of scope
here.

### Sub-decision 7: Commercial model

Three tiers, in decreasing operator involvement:

- **Platform license** — the enterprise licenses the mother, runs it
  on their infra, and bakes an unbounded number of children. This is
  the top tier and the primary offer.
- **Managed children** — CrossEngin operates the mother, bakes and
  hosts children per contract, and the enterprise consumes the child
  over the wire. Suits customers who want the shape without running
  the factory themselves.
- **Open reference children** — free, community-baked children
  (security_review, medical_reference, legal_uk, runbook_reference,
  ...) shipped as adoption drivers. These validate the deploy
  format and give operators something to run before they buy.

### Sub-decision 8: What this is NOT

Explicit non-goals, because confusing any of these with the design
collapses the whole thing:

- **Not an LLM wrapper.** The LLM is at the NL surface only. It never
  reasons. Take the LLM out and the substrate still answers questions
  (just not in prose).
- **Not RAG over vector search.** There are no embeddings in the
  reasoning path. Retrieval is graph walk, not similarity.
- **Not a multi-tenant SaaS.** The mother is licensed and self-hosted.
  Multi-tenant is a customer choice inside their own deployment, not
  the vendor's shape.
- **Not a general chatbot.** Children are domain-scoped by
  construction. A general child is a possible artifact, but the
  design is optimized for focus.
- **Not a training platform.** There are no gradients. There is
  ingest, review, and capsule composition.

## Consequences

### Positive

- **Every reasoning step is inspectable.** Any answer traces to KG
  atoms, edges, and skill runs. The only opaque step in the whole
  pipeline is the NL rendering — and rendering is not reasoning.
- **Knowledge updates without retraining.** Ingest one record,
  publish a signed delta, children have it within their next poll.
  Days-to-hours instead of weeks.
- **Domain focus shrinks the footprint.** A child bakes only the KG
  slice, capsules, skills, and patterns its domain needs. Inference
  is faster and cheaper per query than a general model of comparable
  answer quality.
- **Compliance by construction.** Ownership overlay (R55.x),
  capability tokens (R54), TLS on wire (R86..R94), audit log
  (ADR-0043), reversibility classification (ADR-0042), and signed
  skill install (R54.2) already exist. Children inherit all of it.
- **No vendor lock at inference time.** The child runs no external
  API calls to serve an answer. The NL adapter is a local model.
- **Additive migration.** Every step from today's daemon to the
  factory is additive. No breaking changes are required at any
  point.

### Negative

- **Higher up-front investment than an LLM wrapper.** The customer
  must actually ingest and structure their domain knowledge. That is
  the point — the substrate rewards the investment with
  inspectability and updatability — but the ramp is real.
- **Free-form creative tasks are not the sweet spot.** The substrate
  is optimized for grounded question-answering. "Write me a poem" is
  outside the frame.
- **The small-LLM NL surface is still an LLM.** It is subject to
  its own limits (occasional parse errors, sensitivity to phrasing).
  Contract enforcement (rejecting out-of-shape parses and templating
  render slots) narrows those limits but does not eliminate them.
- **The multimodal sandbox is a large future subsystem.** Many
  rounds of work are required to make it a first-class ingest lane
  for images, audio, and video.
- **The factory needs an operator role.** Somebody in the enterprise
  owns cert provisioning, ingest curation, bake operations, and
  update publication. Small teams can absorb this in an existing
  platform-engineering role; the smallest customers will want the
  Managed Children tier instead.

### Neutral / open questions

The following are recognized but not decided here. Each deserves its
own ADR.

- **Which small LLM.** Quantized in-process or a sidecar model
  server. Local weights only, or a signed adapter format. Needs
  ADR-0201.
- **Multimodal sandbox scope.** Perception primitives (edges,
  phonemes, tokens) versus higher-level representations (embeddings
  plus clustering). Where the boundary between "sandbox learns" and
  "human reviews" sits. Needs ADR-0202.
- **Federated update channel.** Whether enterprises can publish
  KG-deltas back to the mother for shared learning. Governance,
  privacy accounting, and provenance-across-organizations questions
  attach here. Needs ADR-0203.
- **Trust anchors for signed child bundles.** Single mother key,
  hierarchical, or web-of-trust. Interacts with hardware-key admin
  bootstrap.
- **Metering.** Per-child telemetry back to the mother. Opt-in,
  opt-out, or contractual. Interacts with the customer's compliance
  posture.

## Roadmap implications

### Complete first

- **R94** — TLS wire-enable. Landing in parallel with this ADR. The
  factory presumes an encrypted wire between mother and children;
  R86..R94 provide it.

### New epic: Mother/Child architecture (R95..R98)

- **R95** — `BakeManifest` shape and `bake_child` command. Domain
  filter spec, capsule/skill/pattern allowlists, persona and policy
  sets, NL adapter config.
- **R96** — `--child-mode` runtime flag. Immutable KG mount, no
  ingest, no bake, no external network beyond update channel,
  wire binds only the child-appropriate verb subset.
- **R97** — Signed child bundle format. Extends R54.2 Ed25519
  skill-signing to whole bundles; wraps the R73-R75 snapshot; adds
  manifest signature.
- **R98** — Update channel. Mother signs KG-delta; child verifies
  and applies via the R55.x overlay machinery; poll and subscribe
  modes; delta rollback on verification failure.

### Follow-on epic: Small-LLM NL surface (R99..R10X)

- Design the adapter contract in full: parse to `query_shape`,
  render from `ProposalResult`, both with hard schema enforcement.
- Ship a reference adapter for one small model, sized so it fits
  next to the daemon on modest hardware.
- Contract enforcement: rejection path for out-of-shape LLM output,
  slot-only templater for renders.
- Latency and memory budgets, with a documented fall-back to
  grammar-only if the adapter is unavailable.

### Follow-on epic: Multimodal sandbox (R120+)

- Image ingest primitives (extraction, entity resolution to KG).
- Audio ingest primitives (transcription boundary, speaker/segment
  attribution).
- Video ingest primitives (frame sampling, temporal chunking).
- Learned-artifact-to-KG bridge with provenance stamped per source.
- Human-review flow for sandbox outputs, parallel to text ingest
  review (ADR-0101).

### Cross-cutting work that lands independently

- Admin bulk operations on capsules and skills.
- Per-session hooks in the wire.
- Ownership audit log surfacing.
- Per-source rate budgets.
- Hardware-key admin bootstrap.
- DTLS-12 red-fix.
- `bignum_256` and `field25519` refactor.

## Migration path from today's daemon to the AI Factory

- **Today.** Single-daemon deployment, one KG per host, per-user
  ownership overlay, TLS wire. Enterprises can use it as-is for
  internal tools; ADR-0109 documents the shape.
- **After R95..R98.** The same daemon can now emit signed child
  bundles and update them. Operators bake children per domain and
  deploy them to team-scoped hosts. No breaking change to the R49
  wire; child-mode is a launch flag on the same binary.
- **After R99..R10X.** Children become user-facing: the small-LLM NL
  adapter parses English in and renders English out, still routing
  every fact through the reasoning substrate. Grammar-first path
  remains as the deterministic fallback.
- **After R120+.** Children learn from multimodal input on-site.
  Sandbox outputs stamp into the KG; the update channel back to the
  mother is optional and consent-gated per Sub-decision 7 and
  ADR-0203.

Each epic is additive. Each is a strict superset of the daemon that
preceded it. Nothing in this roadmap requires a breaking change to
the ADR-0104 wire, the ADR-0103 skill contract, or the ADR-0013/0014
no-LLM-in-reasoning invariant.

## Cross-references

- ADR-0013 / ADR-0014 — No LLM in reasoning path. Invariant.
- ADR-0100 — Moment-Signal Cognition primitives.
- ADR-0101 — Data acquisition and review pipeline.
- ADR-0102 — Persona.
- ADR-0103 — Skill runtime and the 5 guarantees.
- ADR-0104 — NL surface layer (this ADR extends the LLM-fallback
  role to a first-class small-LLM adapter, boundary only).
- ADR-0105 — Sandbox architecture (this ADR extends its role to
  multimodal learning ingest).
- ADR-0106 — Capsules.
- ADR-0107 — Pattern capsules.
- ADR-0108 — Style capsules.
- ADR-0109 — Ship-as-app (the current single-daemon shape the
  factory builds on).
- R54.2 — Ed25519 skill signing (extended by R97 to whole bundles).
- R55.x — Per-user KG ownership overlay (reused by R98 for
  KG-delta application).
- R73..R75 — Snapshot format (reused by R97 as the child KG payload).
- R86..R94 — TLS on the wire (presumed by the mother-to-child
  update channel).
