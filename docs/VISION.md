# CrossEngin Vision

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

- **R86..R94 — TLS on the wire.** Landing now. In-process TLS,
  no sidecar, cert-signed capability boundary.
- **R95..R98 — Mother/child architecture.** Bake manifest,
  `--child-mode` runtime, signed child bundle, signed KG-delta
  update channel.
- **R99..R10X — Small-LLM NL surface.** Adapter contract, reference
  small-LLM adapter, contract-enforced parse and render.
- **R120+ — Multimodal sandbox.** Image, audio, and video ingest
  lanes that stamp learned artifacts back into the KG under review.

Every step is additive. No breaking change to the R49 wire, the
ADR-0103 skill contract, or the ADR-0013/0014 no-LLM-in-reasoning
invariant is required at any step.

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
  vision, in full architectural form.
- **[SHIP_AS_APP.md](SHIP_AS_APP.md)** — the current mother-daemon
  deployment.
