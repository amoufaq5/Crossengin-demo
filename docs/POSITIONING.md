# CrossEngin Positioning

A short brief for three audiences and the deals they need to see.
For the architecture, see [ARCHITECTURE.md](ARCHITECTURE.md). For
the north-star, see [VISION.md](VISION.md) and
[ADR-0200](adr/adr-0200-crossengin-as-ai-factory.md).

## The pitch

CrossEngin is the biggest brain of all AI — the mother that
deploys, updates, and personalizes smaller configured models on
demand. Frozen weights are replaced by a live, updatable Knowledge
Graph. Reasoning is inspectable end-to-end, over explicit atoms,
edges, implications, and skill runs. There is no LLM in the
reasoning path; the LLM sidecar is a fallback whose invocations are
a measurable failure to close. What you buy is the substrate, not a
prompt.

## Three audiences

### Enterprise ops leaders

Sovereignty is the anchor. The mother runs on the customer's own
infrastructure, over TLS 1.3 (R86-R94, wire-enabled at f060bcc);
no query ever hits an external API to be answered. Compliance is
native — the audit log (ADR-0043), capability tokens as a
six-dimension mutable sextet (ADR-0203), and the per-user ownership
overlay (R55.x) are already built into the substrate rather than
bolted on. Per-user personalization comes from selective load
(mode 2) — one mother, many users, isolated sessions. There is no
vendor lock at inference time: the reasoning path calls nothing
outside the daemon.

### Individual power users

Deterministic answers with a citation, or an honest "unknown."
The personal KG stays personal — atoms carry ownership; reads that
would cross a boundary without a merge capability return empty
instead of leaking. The primary NL surface is LLM-free (ADR-0211),
so the product works offline; the sidecar LLM, if configured, is
local. The substrate extends via signed capsules (ADR-0106,
ADR-0107, ADR-0108) — the user picks up new competencies without
re-training anything.

### Robotics / IoT / OS engineers (long-horizon)

Deterministic reasoning fits embedded budgets in a way an LLM
never will — the token stream, the retrieval hop, and the sampler
are all absent from the reasoning path. KG updates arrive as
signed deltas over the update channel (ADR-0203), which means new
knowledge does not require an OTA re-flash. Per-device persona
lets one bake serve many device classes; offline-first is the
default because the primary NL path does not require a network at
all. Mode 5 (embedded) in [VISION.md](VISION.md).

## Competitive framing

Backed by ADR-0207.

| vs | Where CrossEngin wins |
|---|---|
| LLM SaaS (hosted) | Data never leaves customer infra; deterministic reasoning; audit-log native; no per-token vendor bill |
| Self-hosted LLM | Explicit KG updates in seconds instead of days of tuning; end-to-end inspectable reasoning; hallucination floor is "unknown" |
| LLM + RAG | Retrieval is a graph walk against explicit atoms, not similarity over opaque embeddings; reasoning is not a prompt, so prompt injection has no target |
| LLM + fine-tune | No gradients, no retraining cycle; new knowledge is a signed KG-delta that lands atomically |

Latency parity with hosted LLMs is a hard requirement (ADR-0208);
sovereignty and inspectability do not cost a five-second turnaround.

## Where it fits (uses)

- Chat over a governed KG (per-team, per-persona).
- Coding assistant against an internal codebase KG.
- Internet search grounded in the customer's own ingest pipeline.
- Compliance Q&A with citation-first answers.
- Medical reference — protocol adherence and drug-interaction
  lookup against curated capsules.
- Security review — the `security_review.cerec` reference skill
  already ships and is the working demonstration.
- Curriculum design against a subject-matter KG.
- Legal research with citation and traceback per paragraph.
- Runbook engine — symptom-to-remediation walks with deterministic
  traceback for every recommended step.

## Where it is NOT the right tool

- Free-form creative generation. The substrate is optimized for
  grounded question-answering; write-me-a-poem is outside the
  frame.
- Tasks where a confident guess beats an honest "unknown."
  CrossEngin will not guess.
- Multi-tenant SaaS in the vendor's shape. The mother is licensed
  and self-hosted; multi-tenancy is a customer choice inside their
  own deployment, not the product's shape.

## What you buy / license

Three tiers, in decreasing operator involvement:

- **Platform license.** The enterprise licenses the mother, runs
  it on their infra, and bakes an unbounded number of children.
  Top tier and the primary offer.
- **Managed children.** CrossEngin operates the mother, bakes and
  hosts children per contract, and the enterprise consumes the
  child over the wire. For customers who want the shape without
  running the factory themselves.
- **Open reference children.** Free, community-baked children as
  adoption drivers. `security_review` is the first; others follow.

## Where to go next

- [VISION.md](VISION.md) — the model-first refined vision and the
  five deployment modes.
- [ARCHITECTURE.md](ARCHITECTURE.md) — one-page architectural map
  across substrate layers, bake pipeline, and update channel.
- [ADR-0200](adr/adr-0200-crossengin-as-ai-factory.md) — north-star
  ADR for the AI Factory and the five consumption modes.
- [SHIP_AS_APP.md](SHIP_AS_APP.md) — the current mother-daemon
  deployment shape.
