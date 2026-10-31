# CrossEngin Vision

## Update — Vision refined (post-ADR-0200 / session_01MfeBvRAv9TTWQXbd9aEUkF)

Five clarifications land on top of the original mother/child framing
below. Read these first; the rest of the document is preserved as it
shipped in `ca4df08` and remains accurate underneath.

**Model, not factory only.** CrossEngin IS the model. Frozen weights
are replaced by a live, updatable Knowledge Graph and a triad of
reasoning engines. The AI Factory (bake children, deploy children,
update children) is ONE of five consumption modes, not the total
picture. Any framing that reduces CrossEngin to "the factory that
makes children" understates what the substrate itself is.

**Five deployment modes.** The substrate is consumed in five shapes:
(1) **mother-daemon-direct** — an operator or small team drives the
mother itself; (2) **per-user selective-load** — one mother, many
users, each loading a persona-scoped, capability-scoped subset into
an isolated session; (3) **baked-child** — the mother emits a
signed, immutable, domain-filtered child bundle deployed on customer
infra (the mode ADR-0200 elaborates); (4) **client-app** — a
desktop, web, or mobile frontend consumes the mother or a child
over the RPC wire; (5) **embedded** — a device (robot, OS layer,
IoT endpoint) holds a scoped child locally and reaches back to its
owner's mother for signed updates.

**RAG and fine-tuning are obsolete under this frame.** Knowledge
lives as data (KG atoms, edges, implications, capsules), not as
weights, so there is nothing to fine-tune. Retrieval is a graph
walk against explicit atoms, not a similarity search against
opaque embeddings, so RAG's retrieval-then-hope-the-LLM-uses-it
pipeline collapses into deterministic reasoning. Both patch a
frozen-weights substrate CrossEngin does not have.

**Beliefs and self-awareness are first-class cognitive state.**
Confidence, provenance, source authority, and the model's own
uncertainty about a given atom are stored on the atom, not implied
by softmax over a token distribution. The cognitive sandbox
(ADR-0202) reasons over that state deterministically; the model
can and does emit "unknown" as a first-class answer with the
sources it consulted. Belief lifecycle and self-model semantics are
elaborated by ADR-0206.

**LLM-free NLP is the primary path.** The natural-language surface
is grammar + HDC + templater end-to-end; there is no LLM in the
reasoning path and, past Phase C, the primary NL surface itself no
longer requires one. The sidecar LLM is a fallback, invoked only
when the primary path rejects an input, and every invocation is a
tracked failure event. The **fallback-rate metric drives toward
zero**; a rising number is a bug against the grammar and the
templater, not a normal operating state. Full contract in
ADR-0211; sidecar boundary role in ADR-0201.

**Latency parity with LLMs is a hard requirement.** CrossEngin's
answers arrive in the same wall-clock envelope users expect from
hosted LLM APIs. Inspectability, updatability, and deterministic
"unknown" cannot cost a five-second turnaround. The performance
harness that enforces this — budgets per verb, per query shape,
per deployment mode — is ADR-0208.

Consistent with the original elevator pitch that follows: CrossEngin
is not an LLM. It is the substrate that builds them.

## Elevator pitch

CrossEngin is not an LLM. It is the substrate that builds them — a
knowledge-graph-native reasoning platform whose "mother model" bakes,
signs, and updates small, domain-configured "child models" that
enterprises deploy on their own infra.

## What CrossEngin is

CrossEngin is a self-hosted reasoning platform. Its knowledge lives in
an explicit knowledge graph and in versioned capsules of related
atoms; its reasoning is done by explicit engines (graph traversal,
signal propagation, skill runs, pattern dispatch); its natural-language
surface uses a small local LLM only to parse questions in and render
answers out, never to reason. The full daemon is the **mother model**.
The mother bakes signed **child models** — domain-scoped snapshots
consisting of a KG subset, allowlisted capsules and skills, a persona
and policy set, and an NL adapter configuration. Enterprises license
the mother and deploy the children.

For the full architectural decision, see
[ADR-0200](adr/adr-0200-crossengin-as-ai-factory.md).

## How it is different from LLMs and RAG

| Dimension | LLM | RAG | CrossEngin |
|---|---|---|---|
| Knowledge storage | Frozen weights | External store + embeddings | Explicit KG + capsules |
| Update cost | Retrain (weeks) | Re-embed (hours) | Ingest one record (seconds) |
| Reasoning | Weight-implicit | Weight-implicit + similarity | Explicit engines |
| Inspectability | Opaque | Retrieval-visible, reasoning-opaque | End-to-end inspectable |
| Hallucination risk | High | Medium | Zero (says "unknown" instead) |
| Vendor lock | Provider API | Embedding model + LLM | Self-hosted, no external deps |
| Domain focus | General | General | Per-child domain-scoped |
| Multi-user | External auth | External auth | Native (cap tokens + ownership) |

Two rows deserve emphasis:

- **Hallucination risk.** CrossEngin's reasoning path is LLM-free
  (ADR-0013, ADR-0014). If the KG does not support an answer, the
  answer is "unknown" with the sources it did consult — never a
  confident guess. The NL adapter renders that answer; it cannot
  invent a fact the substrate did not produce.
- **Update cost.** A signed KG-delta from the mother propagates to
  child deployments through the same overlay machinery that today
  handles per-user ownership merges. No re-baking. No downtime.

### Competitor framing (ADR-0207)

The tighter head-to-head against every LLM-adjacent shape:

| Dimension | LLM (frozen) | LLM + RAG | LLM + fine-tune | CrossEngin |
|---|---|---|---|---|
| Knowledge storage | Frozen weights | Weights + vector index | Weights + adapter | Explicit KG + capsules |
| Update cost | Retrain (weeks) | Re-embed (hours) | Re-tune (days) | Ingest one record (seconds) |
| Reasoning inspectability | Opaque | Retrieval visible, reasoning opaque | Opaque | End-to-end inspectable |
| Hallucination risk | High | Medium | High (novel-domain) | Zero (returns "unknown") |
| Vendor lock | Provider API | Embed model + LLM | Base model + tuner | Self-hosted, no external deps |
| Prompt-injection surface | Whole prompt | Prompt + retrieved docs | Whole prompt | NL parser only; reasoning is unreachable |

The last row is the one competitors cannot close by iteration:
CrossEngin's reasoning path is not a prompt, so the standard prompt-
injection playbook has no target. The NL surface can be attacked; the
substrate cannot.

## The mother/child model

- **Mother** — the full CrossEngin daemon plus the bake/deploy
  factory. Runs on operator infra. Ingests knowledge, curates
  capsules, and emits signed child bundles.
- **Child** — a slim runtime (same binary, launched with
  `--child-mode`) loading a signed bundle: a domain-scoped KG
  snapshot, an allowlisted set of capsules and skills and patterns, a
  persona and policy set, and an NL adapter configuration. Immutable
  KG. No bake capability. No ingest. TLS on the wire.
- **Update channel** — the mother signs KG-deltas. Children pull
  them, verify the signature, and apply the delta atomically. No
  retraining is ever performed.

ADR-0200 has the full architecture, the bake manifest shape, the
signature model, and the roadmap.

## Who it is for

- Enterprises building compliant AI for legal, medical, finance,
  security, or ops use cases, where every answer must trace to a
  citation and every reasoning step must be inspectable.
- Teams whose data cannot leave their infrastructure, and who
  therefore cannot use hosted LLM APIs.
- Operators who need updates to take seconds rather than weeks and
  who cannot accept downtime for a retraining cycle.
- Platform teams standardizing on one AI substrate across many
  domain-scoped deployments — one factory, many children.

## What it is not for

- Free-form creative writing. The substrate is optimized for
  grounded question-answering.
- General open-domain chat. Children are domain-scoped by
  construction; a general child is possible but is not the design
  target.
- Any task where a confident guess is preferred to "unknown."
  CrossEngin will not guess.

## Concrete use-case snapshots

- **Legal AI.** Policy and statute Q&A with citations. Deterministic
  traceback to the source paragraph. "Unknown" instead of a
  hallucinated statute.
- **Medical reference.** Drug-interaction lookup and protocol
  adherence checks against a curated capsule set. Provenance and
  authority weighting per source (ADR-0029).
- **Security review.** Pattern-matched code audit against
  OWASP+CWE. The `security_review.cerec` reference skill already
  ships and is a working demonstration of the child-shape at demo
  scale.
- **Finance ops.** Internal procedure queries with audit-log-native
  answers (ADR-0043), scoped to the customer's own KG.
- **Runbook engine.** Symptom to remediation walks with
  deterministic traceback for every step of the recommended plan.

## How you deploy

Three steps, three tiers:

1. **License the mother.** The full CrossEngin daemon plus the
   bake/deploy factory. Runs on your infra.
2. **Bake children per domain.** One bake manifest per use case:
   what KG slice, which capsules and skills, which persona and
   policy, which NL adapter. Sign, distribute.
3. **Deploy children per team.** Slim runtime, immutable KG, TLS on
   the wire. Team consumes over the R49 JSON-RPC wire.

The concrete boot, preload, and wire steps for the mother are in
[SHIP_AS_APP.md](SHIP_AS_APP.md). Child-mode deploy is future work
(R95..R98); see ADR-0200 for the plan.

Two lighter tiers exist alongside the full license:

- **Managed children** — CrossEngin operates the mother, bakes and
  hosts children per contract, and the enterprise consumes them over
  the wire.
- **Open reference children** — free, community-baked children as
  adoption drivers. `security_review` is the first.

## Roadmap at a glance

The vision refinement re-cuts the roadmap along phases, with the
old R-ranges still valid as their underlying epics. Each phase is
additive; no breaking change to the R49 wire, the ADR-0103 skill
contract, or the ADR-0013/0014 no-LLM-in-reasoning invariant is
ever required.

- **TLS on the wire — complete (R86-R94, wire-enable at f060bcc).**
  In-process TLS 1.3, no sidecar, cert-signed capability boundary.
- **Phase A — ADR alignment (this round).** The new ADRs 0200 and
  0201-0211 land, plus VISION / ARCHITECTURE / POSITIONING top-line
  docs. Doc-only.
- **Phase B — Sidecar LLM wire (ADR-0201).** First-class adapter
  contract, boundary-only, contract-enforced parse and render.
- **Phase C — LLM-free NLP expansion (ADR-0211).** Grammar + HDC +
  templater end-to-end; fallback-rate metric drives toward zero.
- **Phase D — Bake factory (ADR-0204, R95-R97).** BakeManifest,
  filtered snapshot, Ed25519 whole-bundle signing.
- **Phase E — Selective load (mode 2).** Per-user session-scoped
  subsets over one mother, capability-sextet gated.
- **Phase F — Cognitive layer (ADR-0206).** Beliefs, self-model,
  sandbox thought-experiment primitives promoted to first class.
- **Phase G — Multimodal (ADR-0205, R120+).** Image, audio, video,
  and structured-signal transducers into the sandbox and KG.
- **Phase H — Performance harness (ADR-0208).** Latency-parity
  budgets per verb, per query shape, per deployment mode.
- **Phase I — Form factors (ADR-0209, ADR-0210).** Client-app
  (desktop / web / mobile) and embedded (robot / OS / IoT) shapes.
- **Phase J — Agents.** Multi-child orchestration and long-running
  agent lifecycles built on the substrate the earlier phases
  hardened.

## Where to read more

- **[ADR-0013](adr/0013-output-generation.md) /
  [ADR-0014](adr/0014-no-llm-cognition.md)** — the invariant: no LLM
  in the reasoning path.
- **[ADR-0100](adr/0100-moment-signal-cognition.md)** — Moment-Signal
  Cognition. The four reasoning primitives.
- **[ADR-0103](adr/0103-skill-runtime.md)** — the skill runtime and
  its five guarantees.
- **[ADR-0104](adr/0104-nl-surface.md)** — the NL surface layer;
  grammar-first with LLM-adapter fallback (extended by ADR-0200 to a
  first-class boundary adapter).
- **[ADR-0105](adr/0105-sandbox-architecture.md)** — the sandbox;
  the site of multimodal ingest under ADR-0200's expansion.
- **[ADR-0106](adr/0106-capsules.md)** — capsules; the sharable
  unit of domain knowledge.
- **[ADR-0200](adr/adr-0200-crossengin-as-ai-factory.md)** — this
  vision, in full architectural form; north-star for the five
  consumption modes.
- **ADR-0201** — sidecar LLM adapter (NL boundary role).
- **ADR-0202** — cognitive sandbox (third leg of the reasoning
  triad).
- **ADR-0203** — deploy, capability tokens, TLS wire, update
  channel.
- **ADR-0204** — bake manifest and signed child bundle format.
- **ADR-0205** — multimodal transducers and sandbox ingest.
- **ADR-0206** — beliefs, self-awareness, and safety governance.
- **ADR-0207** — competitive framing versus LLM, LLM+RAG, and
  LLM+fine-tune.
- **ADR-0208** — latency parity with LLMs (performance harness).
- **ADR-0209** — client-app deployment mode.
- **ADR-0210** — embedded deployment mode.
- **ADR-0211** — LLM-free primary NLP path (grammar + HDC +
  templater).
- **[ARCHITECTURE.md](ARCHITECTURE.md)** — one-page architectural
  map across the substrate layers, five deployment modes, and
  bake/update pipelines.
- **[POSITIONING.md](POSITIONING.md)** — commercial and audience
  framing for the three buyer profiles.
- **[SHIP_AS_APP.md](SHIP_AS_APP.md)** — the current mother-daemon
  deployment.
