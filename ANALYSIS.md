# CrossEngin -- project analysis

An honest, ground-truth assessment of what CrossEngin is, how to ship it, the
journeys it serves, and where it actually sits relative to the AI landscape.
Everything below is cross-checked against the repo (README "Status (through
R39)", `docs/adr/`, `src/`, and `infra/vercel-proxy/`); promotional language is
deliberately avoided in favour of "what landed" versus "what is a known gap".

---

## 1. Project analysis

### What it is

CrossEngin is a **non-LLM cognitive substrate** written in
[NOVA](https://github.com/amoufaq5/nova) (a self-hosting language whose
`stage2.s == stage3.s` invariant is a load-bearing CI gate). Instead of
orchestrating a pipeline of modules around a transformer, it runs a fabric of
uniform computational units on a tick-driven core (100Hz; ADR-0037) and decodes
responses from concept activation spreading through that fabric. Knowledge is an
**explicit knowledge graph** of typed atoms (ADR-0016) carrying Bayesian beliefs
(ADR-0023), augmented by HDC/VSA hyperdimensional embeddings (ADR-0051) and an
episodic memory (ADR-0022). There is no neural network in the reply path and no
LLM in cognition (ADR-0014).

### Verified achievements

| Capability | Where it lives | Status |
|---|---|---|
| 10-phase agent assembled into one unified process | README R35A note | v1.0, all 10 phases complete (R35A) |
| ~6M-node fabric on a tick-driven core | `src/substrate/` (node pool, synapse graph, gate router, tick driver) | R0..R29 |
| Hand-rolled RFC-grade federation transport | `src/federation/` | R30C..R38D |
| -- DTLS 1.2 + ICE + STUN + TURN client + SRTP wire stack | `dtls12.nova`, `ice.nova`, `stun_rfc8489.nova`, `turn.nova`, `srtp.nova` | landed |
| -- TURN **server**-side state machine (allocations/permissions/channels/tick) | `turn_server.nova` (~890 lines) | R38C |
| -- SCRAM-SHA-256 auth (RFC 7635) coexisting with MD5 path | `src/safety/scram.nova` | R38D |
| Autonomous learning loop: trigger -> fetch -> preprocess -> ingest | `src/learning/` (`self_learning_triggers`, `autonomous_research`, `internet_fetch`, `preprocess`, `learn_pipeline`) | R39 |
| KG + HDC + episodic memory with consolidation / GC | `src/kg/` + `src/learning/atom_birth_monitor.nova` / `atom_death_monitor.nova` | landed |
| Chat self-model + intent dispatch | `examples/crossengin_chat.nova` + `src/chat/helpers.nova` | R39A |
| File-backed chat-state save/load | `src/persistence/chat_state.nova` | R39C |
| Canonical crypto leaves (sha256/md5/sha1/scram), de-duped | `src/safety/` | R33A..R38D |

### Honest gaps

| Gap | Detail |
|---|---|
| HTTPS in the learning fetch path | Deferred to R39B.2; needs client-mode TLS, and DTLS is server-shaped today. `internet_fetch.nova` is HTTP/1.1-over-TCP only. |
| English-only stopwords | `src/learning/preprocess.nova` ships ~110 English defaults; swap hook exists (`preprocess_set_stopwords`) but no other languages bundled. |
| Triple extraction recall | Six high-precision / low-recall patterns by design (`is_a`, `has_property`, `causes`, `part_of`, `defined_as`, `is defined as`), capped at 2 triples/sentence. |
| No atomic snapshot write | `chat_state.nova` does single open + truncate (no tmp + rename), and no multi-process lock; text format is not size-optimized (~10 MB per 100k-atom KG). |
| AGI capability is a programme, not a benchmark | The continuous-learning / theory-of-mind / long-horizon-goals targets are an *architectural* promise (ADRs 0039/0040), not measured against a published AGI benchmark. |
| Onboarding liability | A 924KB `NEXT_SESSION.md` is the per-round detail log; reading it cold is a real barrier. `docs/TOUR.md` exists to relieve this. |

---

## 2. Deployment options

CrossEngin compiles to native Linux ELF binaries (`bin/crossengin`,
`bin/crossengin-chat`). There is no browser/Edge target -- it needs threads,
filesystem, and a 100Hz tick (`docs/adr/r36f-0004-substrate-not-pipeline.md`).
Three deployment shapes follow from that.

### (A) Local / terminal

Build with `make install`, then talk to it directly:

- `bash scripts/chat.sh` -- bash REPL over the one-shot `bin/crossengin`
  (fresh boot each turn; no cross-turn memory).
- `python3 scripts/web.py` -- single-host browser UI binding each cookie to a
  long-lived `bin/crossengin-chat` child (state carries across turns).

Zero external services. This is the floor for development and personal use.

### (B) Vercel-hybrid

Per `infra/vercel-proxy/ARCHITECTURE.md`: Vercel hosts the convenience surface
(domain/TLS/edge) and a single Node-runtime function; a Linux box runs the
actual CrossEngin process.

```
Browser --HTTPS--> Vercel edge/CDN (serves app/page.tsx, runs /api/chat)
        --HTTPS (Bearer token)--> Linux backend host
            backend/server.py listens :8080
            spawns bin/crossengin-chat per session_id
            /data volume for persistence
```

Per-turn: `page.tsx` POSTs `{session_id, input}` to `/api/chat`
(`web/app/api/chat/route.ts`), which forwards verbatim to
`${CROSSENGIN_URL}/chat` with `Authorization: Bearer ${CROSSENGIN_TOKEN}`;
`server.py` validates the bearer (`hmac.compare_digest`), routes to the
per-`session_id` persistent child, and flushes the `agent>` line back. See
`docs/DEPLOY_RUNBOOK.md` for the turnkey steps.

### (C) Pure Docker

`infra/vercel-proxy/backend/docker-compose.yml` builds NOVA + CrossEngin from
source (the Dockerfile clones both repos) and exposes the wrapper on
`http://localhost:8080`. `docker compose up --build` is the one-command path;
mount a `/data` volume for persistence. The entrypoint refuses to start on the
`local-dev-token` default unless `CE_ALLOW_DEV_TOKEN=1`.

### Recommendation

| Use case | Recommended shape | Why |
|---|---|---|
| Hacking on the substrate / NOVA | (A) Local terminal | Fastest loop; no token plumbing. |
| Personal companion with a public URL | (B) Vercel-hybrid | TLS + domain for ~5 EUR/mo (Hetzner + Vercel Hobby). |
| Self-hosted, no third party | (C) Pure Docker behind your own reverse proxy | Vercel-free; you own TLS and the host. |
| Multi-tenant / scale | None yet | Single-user by design; no per-user model or quotas (gap). |

---

## 3. User journey

### End user (chats with the agent)

1. Open the web UI (Vercel URL or `python3 scripts/web.py`) or run
   `bash scripts/chat.sh`.
2. Ask `who are you` -> routes to `selfmodel_identity` (ADR-0038).
3. Ask `what is X` -> renders the highest-belief KG triple as "X is a Y".
4. Ask about an unknown word -> "I don't know X yet" + files a self-learning
   trigger (ADR-0026).
5. Teach it: `/teach aspirin treats fever` to seed a triple directly.

### Operator (deploys + runs it)

1. Pick a shape from Section 2 (typically Vercel-hybrid).
2. Provision a Linux host, build the image (`docker compose up --build`).
3. Generate a token (`openssl rand -hex 32`), set `CROSSENGIN_TOKEN` both ends.
4. Smoke-test `/health` and `/chat` with the bearer (see backend/README.md).
5. Deploy the Vercel half; verify end-to-end and apply the hardening checklist
   in `docs/DEPLOY_RUNBOOK.md`.

### Contributor (round-based / ADR model)

1. Read `docs/CONTRIBUTING.md` (round-based development) and `docs/TOUR.md`.
2. Pick or propose a round; write an ADR under `docs/adr/` for any decision.
3. Implement the NOVA module(s); keep prior rounds byte-identical where the
   round notes promise it.
4. Add unit tests under `tests/unit/` (assertions are the norm -- e.g. the
   chat dispatch test ships 60+).
5. Update the README Status table and `NEXT_SESSION.md` round entry.

---

## 4. CrossEngin vs other AI models

CrossEngin is a **symbolic cognitive substrate**, not a language model. Lining
it up against GPT/Claude/Gemini/Llama is a category comparison, included here
because it is the question everyone asks first.

| Dimension | CrossEngin | LLMs (GPT / Claude / Gemini / Llama) |
|---|---|---|
| Paradigm | Symbolic substrate; tick-driven fabric of uniform units | Transformer; next-token prediction over learned weights |
| Knowledge representation | Explicit KG of typed atoms + HDC/VSA + episodic store | Implicit, distributed in billions of parameters |
| Learning | Continuous / online (autonomous research loop, atom birth/death) | Frozen after training; weights fixed at inference |
| Memory | Explicit episodic memory + persistent KG snapshots | Context window (+ external RAG); no native long-term store |
| Explainability | Traceable -- can name the atom / triple / rule used | Opaque; post-hoc attribution at best |
| Self-model | First-class (`selfmodel_identity/state/goals/activity`, ADR-0038) | Emergent / prompted persona; no introspective state |
| Hallucination | Answers from stored beliefs; says "I don't know X yet" | Fluent fabrication is a known failure mode |
| Compute cost | CPU, ~MB-scale state; runs on a ~5 EUR/mo VPS | GPU/TPU clusters for training; nontrivial inference cost |
| Language fluency | Limited (template surface, English-only stopwords) | State-of-the-art, multilingual |
| Breadth of knowledge | Narrow -- only what was taught / fetched | Vast, web-scale pretraining |
| Determinism | Deterministic given KG state + seed | Stochastic (temperature/sampling) by default |

**Conclusion -- they are complementary, not competitors.** NOVA even ships an
LLM FFI bridge, so an LLM can sit beside the substrate (e.g. as a fluent surface
or a fetch-summarizer) rather than replacing it. CrossEngin's real peer group is
the symbolic / neuro-symbolic cognitive-architecture lineage -- **Cyc, SOAR,
ACT-R, OpenCog AtomSpace, Numenta HTM** -- not GPT. Judged there, its
distinctive bets are the self-hosting NOVA implementation, the hand-rolled
RFC-grade federation stack for multi-node KG sync, and the integrated
continuous-learning loop.
