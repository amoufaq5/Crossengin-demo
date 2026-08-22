# CrossEngin Architecture

A one-page architectural map of the CrossEngin substrate. For the
product frame and the north-star language, see
[ADR-0200](adr/adr-0200-crossengin-as-ai-factory.md) and
[VISION.md](VISION.md). For the commercial framing, see
[POSITIONING.md](POSITIONING.md).

## Overview

CrossEngin is an AI **model** — not an LLM wrapper, not a chatbot
frontend, not a RAG pipeline. Its knowledge lives in an explicit,
updatable Knowledge Graph rather than in frozen weights; its
reasoning is done by a **triad** of engines (graph nodes, MSC signal
propagation, and a cognitive sandbox); its natural-language surface
is **LLM-free primary** (grammar + HDC + templater) with a sidecar
LLM as a fallback whose invocation rate is a tracked failure signal.
The substrate is consumed in five deployment modes:
(1) mother-daemon-direct, (2) per-user selective-load, (3) baked
child, (4) client-app (desktop / web / mobile), (5) embedded
(robot / OS / IoT). RAG and fine-tuning are both obsolete under this
frame.

## Substrate layers

```
+----------------------------------------------------------+
|  Wire     JSON-RPC verbs / TLS 1.3 / capability tokens   |
+----------------------------------------------------------+
|  Factory  bake / sign / deploy / signed KG-delta update  |
+----------------------------------------------------------+
|  NL       grammar + HDC + templater  ||  sidecar LLM     |
|  Surface  (primary path)             ||  (fallback)      |
+----------------------------------------------------------+
|  Reasoning triad                                         |
|    graph nodes  |  MSC signals  |  cognitive sandbox     |
+----------------------------------------------------------+
|  Knowledge                                               |
|    KG atoms + edges + implications + provenance          |
|    capsules (knowledge / pattern / style)                |
|    ownership overlay (per-user)                          |
+----------------------------------------------------------+
```

- **Knowledge.** All facts live in the KG or in versioned capsules
  that name atom sets (ADR-0106 / ADR-0107 / ADR-0108). Every atom
  carries provenance and belongs to an ownership overlay (R55.x).
- **Reasoning triad.** Graph traversal answers structural questions;
  MSC signal propagation (ADR-0100) answers moment/attribution-aware
  questions; the cognitive sandbox (ADR-0202) runs deterministic
  side-effect-free thought experiments over both.
- **NL surface.** ADR-0104 grammar-first path is the primary
  surface, extended by ADR-0211 to include HDC and template rendering
  so it stands alone. The sidecar LLM (ADR-0201) is invoked only
  when the primary path rejects an input; every invocation is a
  logged failure event.
- **Factory.** Bake / sign / deploy / update-channel pipeline that
  emits domain-scoped child bundles from the mother substrate
  (ADR-0200, elaborated by ADR-0203 and ADR-0204).
- **Wire.** JSON-RPC verb set (R49) over TLS 1.3 (R86-R94, wire-
  enabled at commit f060bcc); every call carries a six-dimension
  capability token (R54) that scopes read, write, ingest, bake,
  update, and admin independently.

## Five deployment modes

| # | Mode | Form factor | Protocol | Auth | Update path | Status | Anchor |
|---|------|-------------|----------|------|-------------|--------|--------|
| 1 | Mother-daemon-direct | Full daemon on operator host | Local RPC / TLS | Admin cap token | In-place ingest | shipped | ADR-0109 |
| 2 | Per-user selective-load | Session-scoped subset of mother | JSON-RPC / TLS | Per-user cap sextet | Session refresh | shipped (session) / planned (selective load) | ADR-0202 |
| 3 | Baked child | Signed bundle + slim runtime | JSON-RPC / TLS | Mother-signed bundle key | Signed KG-delta pull | planned (R95-R98) | ADR-0203 |
| 4 | Client-app (desktop / web / mobile) | Frontend on user device | JSON-RPC / TLS | Per-user cap sextet | Server-side (mother or child) | planned | ADR-0209 |
| 5 | Embedded (robot / OS / IoT) | Scoped child on device | JSON-RPC / TLS | Device cap sextet | Signed KG-delta pull | long-horizon | ADR-0210 |

TLS wire-enable (mode 3, mode 4, mode 5) landed at **f060bcc**
(R94). All modes share the substrate; the shape of the packaging
and the wire posture differ.

## On-wire boundaries

- **Transport.** TLS 1.3 only (RFC 8446), landed at R86-R94; the
  wire-enable commit is f060bcc. No plaintext socket ships.
- **Authorization.** Capability tokens are a six-dimension mutable
  sextet — read, write, ingest, bake, update, admin — issued by the
  mother (ADR-0203). Each verb declares the sextet it requires.
- **Rate limits.** Per-source and per-cap-token budgets bound both
  ingest and query volume; overages are backpressured, not silently
  dropped.
- **Ownership overlay.** Every atom is stamped with its owning
  identity (R55.x). Reads that would cross an ownership boundary
  without a merge capability return empty rather than leaking.

## Bake pipeline

```
manifest -> filtered snapshot -> sign -> bundle -> child-mode load
```

The `BakeManifest` (domain filter, capsule/skill/pattern allowlists,
persona/policy sets, NL adapter config, update key) is fed to the
`bake_child` command. It emits an R73-R75 KG snapshot filtered to
the manifest's namespaces, wraps the manifest / snapshot / capsule
sets / policy sets / NL config in a single Ed25519-signed bundle
(extending the R54.2 skill-signing pattern to whole bundles), and
hands the bundle to a child runtime launched with `--child-mode`.
See ADR-0203 (deploy) and ADR-0204 (bake manifest shape).

## Update channel

```
mother emits signed KG-delta -> child verifies -> child applies
```

The mother produces a small delta bundle (atoms added, atoms
retracted, edges added, edges removed, capsules updated, provenance
appended, manifest version bump), Ed25519-signs it with the
manifest's `update_key`, and publishes it to the update channel.
The child pulls (poll or subscribe), verifies the signature against
its configured mother public key, and applies the delta via the
R55.x ownership-overlay machinery. No re-baking, no re-training, no
downtime. See ADR-0203.

## Component status map

| Component | Status | Anchor commit / round | ADR |
|-----------|--------|------------------------|-----|
| Knowledge graph (atoms, edges, implications) | shipped | early rounds | ADR-0100 |
| Capsules (knowledge) | shipped | R37-R42 | ADR-0106 |
| Pattern capsules | shipped | R43 | ADR-0107 |
| Style capsules | shipped | R44 | ADR-0108 |
| Persona | shipped | R28 | ADR-0102 |
| Skill runtime (5 guarantees) | shipped | R38 | ADR-0103 |
| NL grammar-first parser | shipped | R48 | ADR-0104 |
| NL templater (primary render) | planned | Phase C | ADR-0211 |
| NL sidecar LLM adapter | planned | Phase B | ADR-0201 |
| Ownership overlay | shipped | R55.x | ADR-0203 |
| Capability tokens (six-dim sextet) | shipped | R54 | ADR-0203 |
| Session snapshots (chat state) | shipped | R73-R75 | ADR-0204 |
| TLS 1.3 wire | shipped | R86-R94 (f060bcc) | ADR-0203 |
| Multimodal transducers (sandbox ingest) | planned | Phase G | ADR-0205 |
| Learning framework (belief + self-awareness) | planned | Phase F | ADR-0206 |
| Safety governance (policy sets, review) | shipped (policy) / planned (governance ADR) | R47 | ADR-0206 |

Rounds and commit hashes cited above are the load-bearing anchors;
where a range is given the wire-enable commit is called out
explicitly.

## Cross-references

- [ADR-0200](adr/adr-0200-crossengin-as-ai-factory.md) — north-star
  frame and the five consumption modes.
- ADR-0201 — sidecar LLM adapter (NL boundary role).
- ADR-0202 — cognitive sandbox (the third leg of the reasoning
  triad).
- ADR-0203 — deploy, cap tokens, TLS wire, and update channel.
- ADR-0204 — bake manifest and signed bundle format.
- ADR-0205 — multimodal transducers and sandbox ingest.
- ADR-0206 — beliefs, self-awareness, and safety governance.
- ADR-0207 — competitive framing (LLM / LLM+RAG / LLM+fine-tune
  vs CrossEngin).
- ADR-0208 — latency parity with LLMs (hard requirement).
- ADR-0209 — client-app deployment mode (desktop / web / mobile).
- ADR-0210 — embedded deployment mode (robot / OS / IoT).
- ADR-0211 — LLM-free primary NLP path (grammar + HDC + templater).
