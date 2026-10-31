# User Guide — Deploy, Feed Data, Compare to LLMs

A plain-English answer to four common questions:

1. How do I run CrossEngin on my own PC or on Oracle Free Cloud?
2. What data can I feed it (Excel, PDF, etc.) to teach it?
3. Can I give it a topic and let it search the internet on its own?
4. How does it compare to an LLM?

Read this alongside [`docs/USING.md`](USING.md) (operator's guide,
`/assert` and `.cerec` packs) and
[`docs/GETTING_STARTED.md`](GETTING_STARTED.md) (environment setup).

> **Honest headline up front.** CrossEngin is **not an LLM**. It is a
> symbolic cognitive substrate (Moment-Signal Cognition — see
> [`docs/adr/0100-moment-signal-cognition.md`](adr/0100-moment-signal-cognition.md)).
> Everything below follows from that: no GPU is needed, no model
> weights are trained, and "learning" means atoms land in a knowledge
> graph with provenance, not gradient descent.

---

## 1. Install and run

CrossEngin compiles to a **single statically-linked Linux x86-64
ELF** (`bin/crossengin`). From
[`docs/GETTING_STARTED.md`](GETTING_STARTED.md): *"Where you can run a
Linux ELF, you can run CrossEngin."*

Toolchain needed on the host:

- GNU `as`, `ld` (binutils)
- `make`, `gcc`
- `setarch` (from `util-linux`) — defeats ASLR during the NOVA
  bootstrap. See
  [`docs/adr/0100-nova-bootstrap-setarch-workaround.md`](adr/0100-nova-bootstrap-setarch-workaround.md).
- `git`

No libc dependency for the output binary. No Python, no Node, no
CUDA, no Rust.

### 1a — Local PC (RTX 2070 Ti, 16 GB RAM): the first-class path

The GPU is not used anywhere by this project. The 2070 Ti is
irrelevant; a plain CPU with 2–4 cores is enough. 16 GB RAM is far
more than needed (bootstrap is small and arena-allocated, no GC).

On **Ubuntu 22.04**, or **WSL2 (Ubuntu)** on Windows:

```bash
# One-time host tooling
sudo apt update
sudo apt install -y build-essential binutils make gcc util-linux git

# Clone side-by-side
cd ~
git clone https://github.com/amoufaq5/nova NOVA
git clone https://github.com/amoufaq5/Crossengin-demo

# Build NOVA (the compiler for CrossEngin)
cd ~/NOVA
make bootstrap-setarch       # setarch -R make bootstrap
setarch -R make              # produces bin/nova

# Point CrossEngin at it, then build CrossEngin
export NOVA_ROOT=$HOME/NOVA
cd ~/Crossengin-demo
./scripts/bootstrap.sh       # verifies tooling + NOVA, runs sanity check
make build                   # compiles every src/**/*.nova
```

Smoke test:

```bash
./scripts/test.sh unit       # runs the full unit test suite
./bin/crossengin --help      # confirms the binary runs
```

Chat REPL and the demo scenarios:

```bash
./bin/crossengin ./examples/crossengin_chat.nova
# or the full daemon:
./bin/crossengin ./examples/crossengin_daemon.nova
# the daemon exposes a web UI on 127.0.0.1:8080
```

**Important:** do not install CUDA, do not install PyTorch, do not
install any ML runtime. None of that is used.

### 1b — Oracle Free Cloud

Oracle's Always-Free tier offers two shapes. **Only one of them
works** for CrossEngin today:

| Shape | arch | RAM | CrossEngin fit |
|---|---|---|---|
| **AMD VM.Standard.E2.1.Micro** | x86-64 | 1 GB | ✅ **Use this one** |
| ARM Ampere A1 (up to 4 OCPU) | aarch64 | up to 24 GB | ❌ Won't bootstrap today |

**Why the Ampere A1 does not work.** NOVA's bootstrap is literally
x86-64 assembly (`boot/nova_boot.s`, 106 k lines). NOVA can
cross-compile *to* ARM64 as an output target, but you still need an
x86-64 host to run the bootstrap. CrossEngin's `scripts/bootstrap.sh`
has no aarch64 path. Treating this as a future roadmap item.

**On the AMD E2.1.Micro** (1 GB RAM is tight but workable):

```bash
# Oracle Linux 8/9 or Ubuntu 22.04 image
sudo dnf install -y binutils make gcc util-linux git     # Oracle Linux
# or:
sudo apt install -y build-essential binutils make gcc util-linux git  # Ubuntu

# Add swap — 1 GB RAM is tight for the stage-1 build
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# Then the same build steps as 1a, but build serially:
cd ~/NOVA && make bootstrap-setarch && setarch -R make -j1
export NOVA_ROOT=$HOME/NOVA
cd ~/Crossengin-demo && ./scripts/bootstrap.sh && make build -j1
```

Open port 8080 in the VCN security list only if you want the web UI
reachable externally; otherwise it stays bound to 127.0.0.1.

### 1c — macOS and Windows

- **macOS**: Linux-ELF only, so run inside Docker (`linux/amd64`
  platform explicitly on Apple Silicon). The build toolchain lives
  inside the container; your host just needs Docker.
- **Windows**: use **WSL2** with the Ubuntu distro and follow the 1a
  steps. Native Windows build via mingw-w64 cross exists for NOVA
  itself but is not wired into CrossEngin's Makefile.

---

## 2. What data you can feed it

CrossEngin ingests structured and semi-structured data into a
knowledge graph. Supported formats today:

| Format | Supported? | Importer | Notes |
|---|---|---|---|
| **CSV** | ✅ | [`src/ingest/importers/csv_facts.nova`](../src/ingest/importers/csv_facts.nova) | RFC-4180 subset. Rows → atoms + implications. |
| **JSON** | ✅ | [`src/ingest/importers/json_records.nova`](../src/ingest/importers/json_records.nova) | Also `src/data/json.nova`. |
| **YAML** | ✅ | [`src/ingest/importers/yaml_records.nova`](../src/ingest/importers/yaml_records.nova) | |
| **PDF** | ⚠️ partial | [`src/data/pdf_text.nova`](../src/data/pdf_text.nova) | Reads text from **uncompressed** PDF content streams. Many real-world PDFs are compressed/scanned and will not fully parse. For scanned PDFs, OCR via the Tesseract effector path first. |
| **RSS 2.0 / Atom 1.0** | ✅ | [`src/io/transducers/kg_rss_ingest.nova`](../src/io/transducers/kg_rss_ingest.nova) | Dedup by guid; `provenance=rss:<feed_url>`. |
| **N-Triples / Wikidata / WordNet / ConceptNet** | ✅ | dedicated importers in `src/ingest/importers/` | For bulk KG seeding. |
| **Audio / image / video records** | ✅ | `audio_records.nova`, `image_records.nova`, `video_records.nova` | Plus the full transducer stack (MFCC, Canny, HOG, OCR, …). |
| **Excel / XLSX** | ❌ **Not implemented** | — | **Workaround: save as CSV in Excel**, then feed through the CSV importer. Native XLSX importer is a straightforward future addition (XLSX is a ZIP of XML, and the CSV importer is the model to copy). |
| **TSV, DOCX** | ❌ | — | Same workaround — convert to CSV / plain text. |

### "Training" means something different here

Feeding data into CrossEngin is **not** training in the ML sense:

- No weights are tuned.
- No GPU is involved.
- There is no epoch, no loss curve, no checkpoint file.

What actually happens, per
[`src/learning/forward_forward.nova`](../src/learning/forward_forward.nova)
(lines 7–11): *"Hinton's Forward-Forward (2022) replaces
backpropagation with a per-layer GOODNESS objective … There is no
backward pass and no gradient flowing between layers … matching the
substrate's design invariant (no global backprop, no offline training
run)."*

Ingest produces:

- new **atoms** in the knowledge graph, with
- **source and provenance** attached to each,
- **Bayesian belief updates** on existing claims,
- narrow **local Hebbian / anti-Hebbian** weight tweaks,
- **rule inference** that may fire on the new atoms.

That means a single new fact can take effect instantly, and every
belief can be traced back to the source atoms that support it. There
is no retraining round.

### How to actually run an ingest

Three scales, cheapest first (also covered in
[`docs/USING.md`](USING.md)):

1. **Interactive** — paste facts into the chat REPL via `/assert`.
2. **Pack** — write a `.cerec` file and feed it in.
3. **Bulk importer** — call the importer binary directly against a
   CSV / JSON / YAML / PDF / RSS feed. For messy sources, pre-digest
   through [`scripts/llm_extract.sh`](../scripts/llm_extract.sh) (an
   external LLM-as-preprocessor sidecar) and then absorb the
   extracted triples.

---

## 3. Can it search the internet and teach itself?

**Short answer:** partly. Give it URLs or RSS feeds and it will fetch,
parse, and ingest on a schedule. Give it only the string
`"antibiotics"` and it cannot yet find sources on its own.

### What works today

- **Whitelisted fetch** —
  [`src/learning/internet_fetch.nova`](../src/learning/internet_fetch.nova)
  (ADR-0028): host whitelist, 30 requests / hour, ≤1 in-flight,
  ≥2 s per domain, URL cache, ingestion as `provenance=fetched`.
- **Autonomous research loop** —
  [`src/learning/autonomous_research.nova`](../src/learning/autonomous_research.nova)
  dequeues `SLT_UNKNOWN_QUERY` triggers, picks a URL, runs the
  pipeline `if_permit → transport → if_ingest`, and lands bytes as
  `provenance=fetched` evidence in the right domain KG. State
  machine: FETCHING → PREPROCESSING → INGESTING.
- **RSS/Atom feeds** —
  [`src/io/transducers/kg_rss_ingest.nova`](../src/io/transducers/kg_rss_ingest.nova)
  parses standard feeds and emits one FACT atom per unseen guid.

### What does NOT work today

- **No search-engine integration.** Grep for `crawler`, `web_search`
  across the tree returns nothing meaningful.
- **No general web crawler.** The fetcher only touches URLs you
  (or the autonomous-research orchestrator) explicitly request, and
  only when the host is on the whitelist.
- **HTTPS is partial.** The native HTTP client is HTTP/1.1 GET only
  (`src/io/transducers/http_client.nova`); HTTPS is deferred to the
  TLS audit roadmap. For `https://` URLs today, the dispatcher falls
  through to a curl shim via
  [`scripts/learn.sh`](../scripts/learn.sh).

### Practical pattern today

To "teach it a topic":

1. Collect a handful of seed sources manually — a few Wikipedia
   pages, government data pages, authoritative blogs, RSS feeds —
   relevant to the topic.
2. Whitelist their hosts in the fetch config.
3. Point `scripts/learn.sh` at the seed URLs; it fetches and ingests
   on the rate-limited pipeline.
4. The autonomous-research loop then expands from the seeds as it
   generates `SLT_UNKNOWN_QUERY` triggers from gaps in the KG.

Full topic → source discovery (a search-engine effector) is a future
roadmap item.

---

## 4. CrossEngin vs. LLMs

A dimension-by-dimension view. Neither row is "the winner" overall;
these are different tools.

| Dimension | **CrossEngin** | **Standard LLM** |
|---|---|---|
| **Core representation** | Discrete atoms, typed signals, KG triples; symbolic. | Dense token embeddings; subsymbolic. |
| **How it "learns"** | Online. Bayesian belief updates + local Hebbian + rule inference + source-authority weighting. One-shot ingest admissible. | Offline. Gradient descent across billions of parameters, big GPU clusters, days–weeks per training run. |
| **Hardware** | Single x86-64 ELF, no GPU, measured in MB. Runs on a 1 GB Oracle micro VM. | GB-scale weights, GPU/TPU required for training; non-trivial GPU for even local inference of good models. |
| **Determinism** | Deterministic given the KG state and the seed. | Stochastic at generation time (temperature > 0); non-determinism baked in. |
| **Auditability** | Every belief traces back to the specific atoms that support it, each with `provenance` and source tier (ADR-0028). | Opaque. No per-fact citation out of the box; RAG is a bolt-on, not a guarantee. |
| **Hallucinations** | Structurally cannot invent atoms that no source backs. May be wrong, but each claim is traceable. | Known failure mode; mitigation (RAG, guardrails) is external. |
| **Fluency / open-ended generation** | Minimal — surface text comes from templates and KG queries. Not conversational in the GPT sense. | State of the art. The point of an LLM. |
| **Multilingual / open-world coverage** | Only what has been ingested. English-first today. | Effectively unlimited, breadth-wise. |
| **Updating knowledge** | Ingest a new feed; the new atom is live immediately. | Re-train or layer RAG; base weights are frozen. |
| **Privacy / offline** | Fully offline by default. Internet fetch is opt-in, rate-limited, whitelisted. | Most mainstream models are hosted. Local models (llama.cpp etc.) exist but need the heavy weights. |
| **Cost to run** | Pennies / month on a free micro VM. | Dollars–hundreds / month depending on model and traffic. |
| **Where it wins** | Auditable, personal, offline knowledge agent that must cite sources and run on cheap hardware. | Open-ended generation, conversation, breadth, few-shot novel tasks. |
| **Where it loses** | Open conversation, broad language fluency, "ask me anything" surface. | Auditability, per-claim provenance, cheap-hardware deployment, privacy by default. |

### They can be combined

[`scripts/llm_extract.sh`](../scripts/llm_extract.sh) is an existing
sidecar: it hands raw text to an external LLM, gets structured
triples back, and feeds those into CrossEngin's KG. The LLM is used
as a parser, not as the source of truth; CrossEngin keeps provenance
and belief semantics. This is the honest "both" story — LLM for
reading-comprehension-at-scale, CrossEngin for the auditable
long-term memory.

---

## Appendix — Common pitfalls

- **"My bootstrap crashes."** You skipped `setarch -R`. See
  [`docs/adr/0100-nova-bootstrap-setarch-workaround.md`](adr/0100-nova-bootstrap-setarch-workaround.md).
- **"CSV import ingests only the header."** Likely CR/LF line endings
  from Windows. Save as *CSV UTF-8 (Unix)* in Excel, or
  `dos2unix` the file.
- **"The RSS ingest reports zero new facts."** You're hitting the
  guid dedup — the feed has not changed since the last ingest.
- **"HTTPS fetch times out."** Native HTTP client is HTTP/1.1 only;
  the HTTPS code path is `scripts/learn.sh` + curl. Confirm the
  URL is on the whitelist and `curl` is installed.
- **"I want to use my GPU."** You can't, and you don't need to.
  CrossEngin is CPU-only by design.
