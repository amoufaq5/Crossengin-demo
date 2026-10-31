# CrossEngin -- 5-minute tour

New to the repo and staring at the 924KB `NEXT_SESSION.md`? Start here. This
is the short path: what CrossEngin is, how to run it, how to talk to it, and
where the code lives.

## What is CrossEngin?

CrossEngin is a **non-LLM cognitive substrate**, written in
[NOVA](https://github.com/amoufaq5/nova). Rather than orchestrating a pipeline
of modules around a transformer, it runs a fabric of uniform computational
units -- roughly 6M nodes on a tick-driven core (100Hz) -- and decodes
responses from concept activation spreading through that fabric. Knowledge is
an **explicit knowledge graph** of typed atoms (ADR-0016) with Bayesian beliefs
(ADR-0023), augmented by HDC/VSA hyperdimensional embeddings (ADR-0051) and
episodic memory (ADR-0022). There is no neural network in the reply path and
no LLM in cognition (ADR-0014). The project targets AGI-relevant capabilities
-- continuous learning, self-directed skill acquisition, theory of mind,
long-horizon goals, self-awareness of identity and state -- as an
*architectural* programme, not a benchmarked claim.

## Run it in a terminal

Build the binaries, then start a chat REPL:

```sh
make install                 # compiles every module into ./bin/
bash scripts/chat.sh         # terminal REPL (drives ./bin/crossengin)
```

For a browser UI with per-cookie state across turns:

```sh
python3 scripts/web.py       # http://localhost:8765/
```

Terminal mode (`scripts/chat.sh`) boots a fresh agent every turn (no
cross-turn memory by default); web mode (`scripts/web.py`) binds each cookie to
a long-lived `bin/crossengin-chat` child so state carries across requests. See
`docs/GETTING_STARTED.md` for the full install (Linux / WSL2 / macOS).

## Talk to it

A few example turns (post-R39):

```text
> who are you?
agent> I am <soul_name>. My purpose is <soul_purpose>.   # -> selfmodel_identity (ADR-0038)

> what is aspirin?
agent> aspirin is a drug                                 # -> highest-belief KG triple

> tell me about quasars
agent> okay                                              # unknown word -> "I don't know X yet"
                                                         #    + files a curiosity / self-learning
                                                         #    trigger (ADR-0026)
```

Self-identification questions ("who are you", "what are your goals", "how are
you", "what can you do") route to the real self-model API. Concept queries
("what is X", "tell me about X") render the highest-belief KG triple as
"X is a Y" / "X causes Y" / "X has Y". Unknown words reply that the agent
doesn't know X yet and queue an autonomous learning episode. The highest-yield
interactive action is `/teach` -- e.g. `/teach aspirin treats fever`.

## Where things live

| Path | What it is |
|---|---|
| `src/substrate/` | The tick-driven fabric: node pool, synapse graph, gate router, signal dispatch, resonance engine, tick driver. |
| `src/kg/` | Knowledge graph: atom store, concept layer, HDC/VSA embeddings, episodic store, cross-KG references, clustering, link prediction. |
| `src/federation/` | Hand-rolled RFC federation stack: DTLS 1.2, ICE, STUN/TURN client+server, SRTP, gossip, leader election, KG sync. |
| `src/learning/` | Continuous learning: autonomous research loop, internet fetch, preprocess, Bayesian updates, atom birth/death monitors, confidence thresholds. |
| `src/chat/` | Chat intent-dispatch helpers (self-ID routing, concept-query extraction, unknown-word replies). |
| `src/parts/*` | The cognitive "organs": `soul`, `goals`, `emotion`, `episodic`, `imagination`, `meta`, `perception`, `reasoning`, `action`. |
| `src/persistence/` | Snapshots + chat-state save/load: writer/reader, Merkle + Ed25519 signing, compaction, delta, schema migration. |
| `src/safety/` | Crypto + guardrails: sha256/md5/sha1, scram, aes_gcm, ed25519/rsa/ecdsa, constitutional filter, permission tiers, reversibility classifier, DP. |

## Next steps

- `docs/CHAT_USAGE.md` -- full chat walkthrough: every admin command, teaching,
  self-directed learning, self-identification, inspection, persistence.
- `docs/GETTING_STARTED.md` -- install on Linux / WSL2 / macOS / Vercel hybrid.
- `docs/adr/` -- architecture decisions. Start at ADR-0001 (substrate),
  ADR-0014 (no-LLM), then the R36F-prefixed series for macro rationale and the
  `r39-*` ADRs for the latest sprint.
- `infra/vercel-proxy/ARCHITECTURE.md` -- the Vercel-hybrid deployment shape.
- `ANALYSIS.md` -- honest project analysis, deployment options, and how
  CrossEngin compares to LLMs.
- `docs/DEPLOY_RUNBOOK.md` -- turnkey Vercel-hybrid deploy steps.
