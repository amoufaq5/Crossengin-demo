# Train CrossEngin with Ollama

CrossEngin is a symbolic reasoning engine. The knowledge path is 100% NOVA — no LLM in the answer loop. Ollama (or any local LLM) sits beside the reasoner as a **fluency layer** (phrases the templated answer) and an **extraction layer** (reads unstructured text and emits `.cerec` records for human review). The LLM never writes to the KG directly; every atom lands through the review queue.

This guide walks a fresh install through enabling both roles with a 3B-class local model.

## 1. Install Ollama + pull a model

```bash
# Install (Linux / macOS):
curl -fsSL https://ollama.com/install.sh | sh

# Pull a lightweight instruction-tuned model (~2 GB RAM):
ollama pull llama3.2:3b-instruct

# Verify it answers:
ollama run llama3.2:3b-instruct "hi"
```

Any model Ollama supports works; the composer prompt is tight and model-agnostic. For stronger extraction a 7B/8B model is better but slower.

## 2. Turn on the reply composer

The composer wraps the templated reply from `router_reply` in natural prose. Reasoning stays symbolic; only the surface sentence changes.

```bash
export CE_OLLAMA_COMPOSER=1
export OLLAMA_COMPOSER_MODEL=llama3.2:3b-instruct      # optional override
export OLLAMA_URL=http://127.0.0.1:11434                # optional override

./bin/crossengin-chat
```

Ask a known chain:

```
> fever
agent> A fever usually points to an infection, and infections tend to bring on headaches.
```

Compare to the composer-off version (the plain templated chain `infection leads to headache (…)` ).

Behaviour on failure:
- Ollama unreachable, model missing, request times out → the composer sidecar passes through the templated reply unchanged. `/why` still cites the same ops either way.
- Composed replies are cached in the moment-cache LRU; the second time a user asks the same question, the fluent reply returns without re-paying the fork+exec cost.

## 3. Persist the env across sessions

Put the exports in your shell init:

```bash
# ~/.bashrc
export CE_OLLAMA_COMPOSER=1
export OLLAMA_COMPOSER_MODEL=llama3.2:3b-instruct
```

Or, for a systemd-managed daemon, in the unit file:

```ini
[Service]
Environment=CE_OLLAMA_COMPOSER=1
Environment=OLLAMA_COMPOSER_MODEL=llama3.2:3b-instruct
```

NOVA has no `setenv` primitive, so there's no `~/.crossengin/ollama.conf` loader — the env-var surface is the config surface.

## 4. Env-var reference

| Env | Default | Role |
|---|---|---|
| `CE_OLLAMA_COMPOSER` | unset | Master gate for the reply composer. `1` enables. |
| `CE_REPLY_COMPOSER_SCRIPT` | `scripts/llm_compose.sh` | Repath the composer sidecar (out-of-tree installs). |
| `OLLAMA_COMPOSER_BACKEND` | `ollama` | `ollama` / `llama-cpp` / `openai` / `dry-run`. |
| `OLLAMA_COMPOSER_MODEL` | `llama3.2:3b-instruct` | Model name passed to `--model`. |
| `OLLAMA_EXTRACTOR_BACKEND` | `ollama` | Same for `scripts/llm_extract.sh`. |
| `OLLAMA_EXTRACTOR_MODEL` | `llama3.2:3b-instruct` | Default model for `/ingest_ollama`'s synthesised command. |
| `OLLAMA_URL` | `http://127.0.0.1:11434` | Where the sidecar scripts reach the Ollama daemon. |
| `OPENAI_API_KEY` / `OPENAI_BASE_URL` | — | OpenAI-compatible endpoint if `BACKEND=openai`. |

The `nl_llm_sidecar` (NL intent fallback) has its own prefix — see `src/nl/nl_llm_sidecar.nova` for `CROSSENGIN_NL_LLM_*`.

## 5. Teach from a local file

The two-step extraction + review flow lands records in the queue, never directly in the KG. The chat command prints the exact commands to run:

```
> /ingest_ollama /path/to/notes.txt
# Phase 2 pt2: run these two commands to ingest '/path/to/notes.txt'
# Step 1 (shell) -- extract .cerec records with Ollama:
scripts/llm_extract.sh --input /path/to/notes.txt --output /tmp/crossengin_ollama_notes.txt.cerec --kg learned --model llama3.2:3b-instruct --run ollama-N --backend ollama
# Step 2 (back in this chat) -- enqueue for review:
/ingest_llm /tmp/crossengin_ollama_notes.txt.cerec llama3.2:3b-instruct ollama-N
# Then: /ingest_review to inspect, /ingest_approve <id> to promote.
```

Run them in order. The LLM extractor is quarantined by design: every record has its source tag rewritten to `src:extractor:llm:<model>:<run>`, FORMAL implications downgrade to EMPIRICAL, and belief caps apply — none of which can bypass review.

```
> /ingest_review
review queue (7 pending, 0 ingested, 0 denied, 0 ingest-failed):
  #1 [pending] kg=learned src=src:extractor:llm:... atoms=2 imps=1
  …

> /ingest_approve 1
(approved record 1 — 2 atoms, 1 implication now live in kg=learned)
```

## 6. Teach from the web

`/learn <url>` fetches and caches text to `/tmp/crossengin_learn_<tag>.txt`. Pt1 of Phase 1 gated this behind an approval prompt (`CAP_AUTONOMOUS_FETCH`) — the user confirms before the agent reaches outward. Once cached, feed it to `/ingest_ollama`:

```
> /learn https://en.wikipedia.org/wiki/Fever
agent> would like to fetch URL: https://en.wikipedia.org/wiki/Fever. approve? [y/N/why]
> y
(fetched 24KB to /tmp/crossengin_learn_fever.txt)

> /ingest_ollama /tmp/crossengin_learn_fever.txt
# Phase 2 pt2: run these two commands …
```

Then same two-step flow as §5.

## 7. Audit

After records land in the KG:

```
> /why fever
atom fever (kg=learned) traces to:
  src:extractor:llm:llama3.2:3b-instruct:ollama-N (sentence 4, line 42 of /tmp/crossengin_learn_fever.txt)
  src:topic:fever (seed)
  …

> /__safety__
safety_attestations=N
  #0 attest autonomous_fetch -> allow
  #1 attest ingest_atom      -> allow
  …
```

Every cap decision is on the hash-chained decision log. Every ingested atom cites its extractor+model+run. The LLM did not write to the KG — the operator approved each record, individually, with the extracted sentence in view.

## Free prompting

Phase 3 pt1 adds an auto-prefix router so a bare-word first token is rewritten to its slash form. Instead of typing `/learn antibiotics` you can just type `learn antibiotics`:

```
> learn antibiotics
(no cache for 'antibiotics' [topic] at /tmp/crossengin_learn_antibiotics.txt)
  run first:  scripts/learn.sh antibiotics
```

The router applies two lists:

- **Allowlist** (auto-prefix fires): `learn`, `teach`, `define`, `know`, `knowledge`, `why`, `status`, `help`, `good`, `bad`, `cap`, `synapse`, `recall`, `find`, `prove`, `explain`, `classify`. All of these are command-first by convention; typing them as the first word of a message is overwhelmingly a request to run the command.
- **Denylist** (never auto-prefix, require explicit `/`): `halt`, `save`, `load`, `retract`, `unretract`, `compact`, `snap_verify`, `fed_*`, `gossip_*`, `agent`, `meta`, `admin`, `drule_*`. These touch durable state, open sockets, or change governance — the explicit slash forces operator awareness.

Everything else (unlisted first-token words, verbs that start with a capital, anything with punctuation) falls through to the natural-language reasoning path unchanged.

A convenience command `/learn_prepare <topic>` prints the exact `scripts/learn.sh <topic>` command for the topic flow (gated by `CAP_AUTONOMOUS_FETCH` so the attestation log records the intent). Run that in a separate shell, then come back to the chat and type `learn <topic>` to ingest the cache.

## Why not a one-step `/ingest_ollama` that runs the shell for you?

In-chat `exec_program` currently hits three NOVA runtime gaps (fork-return tagging, `store64` of literal zero, `envp=NULL` on `_nova_exec`). Until those close, `/ingest_ollama` **prints** the two commands rather than running them. The two-command path is well-tested, bit-safe, and the operator sees exactly what will land. Once the runtime gaps are closed, `/ingest_ollama` can collapse to one step without any user-facing change.
