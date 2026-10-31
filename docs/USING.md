# Using CrossEngin — feed it data, ask it things

**A truth-seeking, non-LLM reasoning engine written in NOVA.**

This guide answers three questions honestly:

1. **How do I feed the system data — from a handful of facts up to a
   real corpus?**
2. **How do I use it — the actual commands, workflows, and files?**
3. **What does it do like Claude/ChatGPT, and what doesn't it do yet?**

For build + test instructions, see [`../MANUAL.md`](../MANUAL.md).
For rolling status and design, see
[`../NEXT_SESSION.md`](../NEXT_SESSION.md). This document is the
**user-facing operator's guide** — what to type, what happens, how to
scale it up.

---

## 0. What CrossEngin is in one paragraph

CrossEngin implements **Moment-Signal Cognition (MSC)** — see
[`../docs/adr/0100-moment-signal-cognition.md`](adr/0100-moment-signal-cognition.md)
for the architectural contract. In plain terms: it holds beliefs as
explicit `(alpha, beta)` Bayesian counts on labeled atoms, arranged
into multiple knowledge graphs (one per domain). It exposes
contradictions with kernel-checked FALSE witnesses (formal layer) and
cross-KG belief spreads (empirical layer). It can retract a belief
and cascade the withdrawal, then bring the belief back symmetrically.
Every atom carries its source; the meta-observer tracks which sources
produce beliefs that decay. There is **no LLM in the answer path** and
**no gradient descent anywhere**. It learns by absorbing observations,
one at a time, tagged by source.

---

## 1. Starting the chat REPL

Once built (see `../MANUAL.md`), run:

```
NOVA_ROOT=~/NOVA ~/NOVA/nova examples/crossengin_chat.nova
```

You'll see:

```
=== CrossEngin chat ===
state persists across turns; type 'quit' / 'exit' / empty / Ctrl-D to leave
type /help for admin commands (/teach, /pin, /status, /halt, ...)
(seed: 584 atoms, Aurora ready)
>
```

Type `/help` to see every slash command. Type free text to talk to it
(current NL output is symbolic — see §7 on the gap).

---

## 2. Teaching it, one fact at a time

For small-scale interactive teaching:

```
> /assert electron
axiom 'electron' asserted (PROMOTED)

> /imp electron charged
imp 'electron -> charged' asserted (PROMOTED)

> /assert charged
axiom 'charged' asserted (PROMOTED)

> /consistency
formal env consistent (no FALSE witness derivable)

> /teach photon
> /pin photon 900
```

Commands you'll actually use:

- `/assert LABEL` — kernel-checked FORMAL axiom.
- `/imp A B` — kernel-checked implication A → B.
- `/teach WORD` — learn a word + concept binding (softer, EMPIRICAL).
- `/pin W C` — set word W's confidence to C (0..1000 milli).
- `/consistency` — scan formal env for contradictions; kernel-checked.
- `/kg_consistency [T]` — scan empirical beliefs across KGs at
  spread threshold T milli (default 500).
- `/retract LABEL` — withdraw the belief + cascade unpinning.
- `/unretract LABEL` — bring it back.
- `/derivation LABEL` — show the proof behind a FORMAL claim.
- `/retractions` — audit log of every retraction this session.
- `/save PATH` / `/load PATH` — durable snapshot.

This is the "kid learning from a parent" path — one fact at a time,
each with a source, each retractable.

---

## 3. Feeding a whole domain — `.cerec` packs

For medium-scale ingest (dozens to hundreds of atoms per pack), author
a **`.cerec` file** — CrossEngin's native line-based record format.

Example (`data/packs/solar_system.cerec` excerpt):

```
KG astronomy
SRC src:pack:solar_system:v1

ATOM sun 1 1000
ATOM star 3 950
ATOM planet 3 950
IMP sun star FORMAL
IMP earth planet FORMAL

OBS sun +1 1000
CITE src:pack:solar_system:v1 src:paper:doi:iau-2006 supports
```

Directives:

| Directive | Fields | Purpose |
|---|---|---|
| `KG` | `kg_name` | opens a new record; target KG |
| `SRC` | `src:tag` | source attribution for meta-observer |
| `ATOM` | `label kind belief` | kind ∈ 1..6; belief 0..1000 milli |
| `IMP` | `ante conseq strength` | strength ∈ FORMAL, EMPIRICAL |
| `OBS` | `label sign weight` | sign ∈ +1, -1; weight 0..1000 milli |
| `CITE` | `src:from src:to relation` | relation ∈ supports, contradicts, extends |

Comments (`#`) and blank lines are ignored. A new `KG` directive
closes the previous record.

To ingest:

```
> /ingest cerec data/packs/solar_system.cerec astronomy src:pack:solar_system:v1
ingest[cerec ...]: 1 ingested, 0 queued for review, 0 dropped,
                   33 atoms added, 0 parse errors
```

**Trusted vs untrusted sources.** The ingestion agent has a list of
trusted source-tag prefixes (default: `src:pack:`, `src:cerec:`,
`src:user:`). Records from trusted prefixes ingest directly; everything
else lands in the review queue for owner approval:

```
> /ingest_review           # list queue
> /ingest_approve 3        # approve entry #3
> /ingest_deny 5 reason... # deny entry #5 with reason (kept for audit)
```

**Domain packs shipped in this repo** (see
[`../data/packs/README.md`](../data/packs/README.md)):

| Pack | Atoms | Domain |
|---|---|---|
| `solar_system.cerec` | 33 | astronomy |
| `physics.cerec` | 35 | classical + particle physics |
| `world_history.cerec` | 43 | history (antiquity → 20th c.) |
| `religion.cerec` | 58 | comparative religion (descriptive) |
| `politics.cerec` | 73 | comparative political science |
| `biology.cerec` | 77 | undergraduate life science |
| `folk_astronomy.cerec` | 5 | deliberate-disagreement demo |

All packs are `src:pack:*:v1` (trusted), so `/ingest cerec ...` puts
them straight into the KGs.

---

## 4. Feeding large / structured data — importers

Beyond hand-authored packs, seven importers convert existing
structured sources into curriculum records:

| Format | Command | Notes |
|---|---|---|
| `.cerec` (native) | `/ingest cerec` | canonical format |
| CSV | `/ingest csv` | RFC-4180 subset with quoting |
| N-Triples RDF | `/ingest ntriples` | any semantic-web dump |
| Wikidata | `/ingest wikidata` | Qxxx/Pxxx-aware + optional labels TSV |
| ConceptNet 5 | `/ingest conceptnet` | 5-column TSV assertions |
| Paper metadata | `/ingest papermeta` | arXiv/OpenAlex/DOI key-value |
| WordNet | `/ingest wordnet` | synset + hypernym + antonym |

Each importer produces the same curriculum-record shape and flows
through the same pipeline. Untrusted sources queue for review;
`ingestion_agent` can be told to trust more prefixes (e.g. after
you've audited a run of `src:wikidata:` records).

**Scale honestly, today:**

- The label hash-index means `/kg_consistency` scan is essentially
  O(N) for typical corpora — millions of atoms is the design target.
- `kg_find_atom` is still a linear scan — the ingest itself is O(N²)
  if a single KG has hundreds of thousands of atoms. A hash-index for
  atom lookup is on the roadmap.
- Snapshots are one blob per KG registry today. Wikidata-scale KGs
  need the page-indexed atom store (NOVA-0007) — unbuilt.

Practical scale that works today without further work:
**tens of thousands of atoms across dozens of KGs**. Enough for a
serious multi-domain reasoner; not a full Wikidata mirror.

---

## 5. Feeding UNSTRUCTURED text — LLM as preprocessor

CrossEngin is a symbolic engine — it can't read a Wikipedia article
directly. But it can accept structured records **extracted from prose
by an external LLM**. This is the ONLY role the LLM plays:
preprocessor, never reasoner. The safety wall is deliberate (ADR-0013 /
ADR-0014):

1. The LLM reads the passage, emits a `.cerec` file with atoms and
   implications.
2. `scripts/llm_extract.sh` invokes the LLM, sanitizes its output,
   writes the `.cerec` file.
3. `/ingest_llm PATH MODEL RUN` pipes the file through
   `src/ingest/llm_extractor.nova`, which enforces:
   - **Source rewrite** — every record's source tag becomes
     `src:extractor:llm:MODEL:RUN`, so provenance is traceable per run.
   - **Belief cap at 800** — no LLM can mint a Tier-A user-taught
     equivalent atom.
   - **FORMAL → EMPIRICAL downgrade** — the LLM cannot smuggle a
     kernel axiom.
   - **Mandatory review queue** — every record ingests-to-queue, no
     matter its source prefix. An owner approves each record before
     atoms land.
4. You review with `/ingest_review` and approve with `/ingest_approve N`
   (or deny with `/ingest_deny N REASON`).

### Supported LLM backends

`scripts/llm_extract.sh` speaks four backends:

```
scripts/llm_extract.sh \
    --input   path/to/article.txt \
    --output  path/to/output.cerec \
    --kg      history \
    --model   llama3.1:8b \
    --run     r-2026-08-15-01 \
    --backend ollama          # or llama-cpp | openai | dry-run
```

- **`ollama`** — local Ollama daemon. Any model in your Ollama
  library. Recommended: `llama3.1:8b`, `llama3.3:70b`, `mistral`,
  `mixtral`, `qwen2.5:7b`.
- **`llama-cpp`** — local llama.cpp `llama-cli`. Pass a `.gguf` model
  path via `--model`.
- **`openai`** — any OpenAI-compatible HTTP endpoint (OpenAI itself,
  Together, Groq, local vLLM, etc.). Reads `$OPENAI_API_KEY` and
  `$OPENAI_BASE_URL`. Model name follows the provider's convention.
- **`dry-run`** — skip the LLM entirely; emit a minimal stub. Useful
  for testing the pipeline end-to-end.

### The prompt sent to the LLM

The full prompt is inline in `scripts/llm_extract.sh` (`_prompt()`).
It:

- Names the target KG and source tag.
- Documents the `.cerec` directives, kinds, and belief scale.
- Requires lowercase snake_case labels and no invented synonyms.
- Requires "one sentence → one atom" — no interpretation, no
  rhetoric.
- Explicitly forbids claims about currently-living named
  individuals.
- Includes one worked example (Gutenberg + printing press).

Adjust per model. Smaller local models often need a stricter
one-shot example added.

### Worked end-to-end example

```
# 1. Have text on disk (curl / wget / pdftotext / anything).
$ cat article.txt
The Louvre Museum in Paris is the world's most-visited museum. It was
originally built as a fortress in the late 12th century...

# 2. Extract structured records.
$ scripts/llm_extract.sh \
    --input   article.txt \
    --output  /tmp/louvre.cerec \
    --kg      culture \
    --model   llama3.1:8b \
    --run     r-2026-08-15-01 \
    --backend ollama
wrote /tmp/louvre.cerec  (12 atoms, 6 implications, 0 observations)
ingest with:  /ingest_llm /tmp/louvre.cerec llama3.1:8b r-2026-08-15-01
then review:  /ingest_review
then approve: /ingest_approve <id>

# 3. Ingest via the chat REPL (mandatory-queue).
> /ingest_llm /tmp/louvre.cerec llama3.1:8b r-2026-08-15-01
llm_extract[llama3.1:8b:r-2026-08-15-01]:
  1 records, 1 enqueued, 0 dropped, 2 belief-capped,
  1 FORMAL->EMPIRICAL, 0 parse errors

# 4. Review + approve.
> /ingest_review
review queue (1 pending, 0 ingested, 0 denied, 0 ingest-failed):
  #1 [pending] kg=culture src=src:extractor:llm:llama3.1:8b:r-2026-08-15-01
     atoms=12 imps=6

> /ingest_approve 1
approved #1: ingested.
```

**How this scales.** A single LLM run over one document costs ~10s +
LLM cost. Batch a corpus of thousands of docs into a queue, review in
bulk. If a specific LLM's per-run atrophy climbs over time (meta-
observer tracks each run's atoms), stop using that model for
extraction.

### Which open-source LLMs work well

Rough guidance for the extraction prompt on modest hardware:

| Model | Verdict |
|---|---|
| `llama3.1:8b` (Ollama) | Good baseline; occasionally misses IMPs |
| `llama3.3:70b` (Ollama) | Best local option for accurate extraction |
| `qwen2.5:14b` | Strong on structured output; recommended |
| `mistral:7b` | Fast, less accurate — good for high-volume, review-heavy |
| `phi3:mini` | Too small for reliable structure emission |
| `deepseek-r1:8b` | Good; sometimes emits prose despite prompt |

Larger local models (70B+) and API models give the highest-fidelity
extraction, but the safety wall applies identically regardless of
source. **The pack's beliefs converge on truth by accumulating
observations from many sources over time, not by trusting any one LLM
run.**

---

## 6. Multi-KG consistency, retraction, and the "truth-seeking" loop

Once you have real content in multiple KGs, three commands surface the
epistemic state:

```
> /consistency
```
Scans the formal env (FORMAL axioms and implications) for
kernel-derivable FALSE. Returns the specific chain of premises. This
is a kernel-checked proof, not a heuristic.

```
> /kg_consistency 200
```
Scans EMPIRICAL beliefs across all KGs for same-labeled atoms whose
belief means diverge by ≥ 200 milli. Reports every conflict with both
KG names and both belief means. Heuristic (empirical beliefs aren't
theorems), but deterministic and auditable.

```
> /retract SOME_LABEL     # withdraws a claim + cascades unpinning
> /unretract SOME_LABEL   # brings it back through the log
> /retractions            # audit log for the session
> /derivation SOME_LABEL  # kernel-proof chain for a FORMAL claim
```

**Worked cross-KG example (in this repo):**

```
> /ingest cerec data/packs/solar_system.cerec astronomy src:pack:solar_system:v1
> /ingest cerec data/packs/folk_astronomy.cerec folk_astronomy src:pack:folk_astronomy:v1
> /kg_consistency 200
(empirical belief conflicts across KGs, spread >= 200 milli:)
  'planet': astronomy believes 950 vs folk_astronomy believes 400
  'sun':    astronomy believes 1000 vs folk_astronomy believes 200
  'earth':  astronomy believes 1000 vs folk_astronomy believes 600
```

Both KGs are kept. Nothing is silently fused. The disagreement is a
first-class event you can act on.

---

## 7. Serving as Claude / ChatGPT — honest gap analysis

**What CrossEngin does that Claude/ChatGPT don't:**

| CrossEngin | Claude / ChatGPT |
|---|---|
| Every belief has a named source | Trained-in patterns; source opaque |
| Kernel-checked FALSE witnesses | Textual "I might be wrong" |
| Retract → cascade → unretract | No retract; regeneration each turn |
| Cross-KG belief disagreement first-class | Blends conflicting sources silently |
| No hallucination surface (atoms exist only from observations) | Fluent text can invent facts |
| Fully inspectable — every atom, source, derivation | Weights are opaque |
| Runs on your machine, no external calls | Cloud dependency |

**What Claude/ChatGPT do that CrossEngin does NOT do today:**

| Capability | CrossEngin today | To close the gap |
|---|---|---|
| Understands natural language | No — parses slash commands | Build an NL→structured-query parser (either a small grammar or an LLM-as-parser under ADR-0013's preprocessor stance) |
| Generates natural-language answers | No — prints structured atoms + traces | Build a deterministic templater (`structured → NL`); LLM-free by design |
| Long conversational context | Session state persists; no NL threading | Would follow the NL layer |
| Broad-corpus world knowledge | 324 atoms in shipped packs | Ingest more content — the pipeline scales |
| Code generation | No | Not a design goal |
| Tool use / function calling | Effector layer exists (`src/io/effectors/`) | Wire specific effectors per skill |
| Multimodal (images, audio) | Transducers exist (`src/io/transducers/`) | Per-modality wiring |

**The shortest path from here to "user asks a question in English, gets
a plain-English answer with sources":**

1. **NL question parser** — LLM-as-preprocessor OR small grammar.
   Parses "does aspirin interact with warfarin?" into a structured
   query `(kg=medicine, atom_relations_touching={aspirin, warfarin})`.
2. **Query executor** — walk the KGs, gather atoms + beliefs +
   sources + contradictions.
3. **Deterministic templater** — render the structured result as
   plain English. Example: `"Yes. This is supported by src:X (belief
   850) and src:Y (belief 900). No contradictions detected."`
4. **JSON-RPC daemon** — wire the above into
   `crossengin_daemon.nova` so a web/mobile client can talk to it.

None of these require new reasoning primitives. They're composition
work. Estimate: `NL parser` + `query executor` + `templater` is
~2000 lines of NOVA, one focused round.

Until then, CrossEngin is best thought of as a **truth-seeking
kernel** you drive with structured commands, not a conversational
assistant. Every capability of a conversational assistant can be
layered on top; the kernel doesn't change.

---

## 8. Common workflows

### Workflow: seed a new domain from scratch

```
# 1. Author a starter .cerec pack (100-500 atoms).
$ $EDITOR data/packs/mydomain.cerec

# 2. Test the pack ingests cleanly (copy any test_pack_*.nova as template).
$ NOVA_ROOT=~/NOVA ~/NOVA/nova tests/unit/test_pack_mydomain.nova

# 3. Ingest into a live session.
> /ingest cerec data/packs/mydomain.cerec mydomain src:pack:mydomain:v1

# 4. Verify no contradictions.
> /consistency
> /kg_consistency 200

# 5. Snapshot.
> /save /tmp/mydomain.snap
```

### Workflow: enrich the domain from external LLM extraction

```
# 1. Get a raw text corpus.
$ ls corpus/*.txt

# 2. Extract each with the LLM helper.
$ for f in corpus/*.txt; do
    scripts/llm_extract.sh \
      --input "$f" --output "/tmp/$(basename $f .txt).cerec" \
      --kg mydomain --model llama3.1:8b \
      --run "r-$(date +%s)-$(basename $f .txt)" \
      --backend ollama
  done

# 3. Ingest each into the review queue.
> /ingest_llm /tmp/doc001.cerec llama3.1:8b r-doc001
> /ingest_llm /tmp/doc002.cerec llama3.1:8b r-doc002

# 4. Review + approve.
> /ingest_review
> /ingest_approve 1
> /ingest_approve 2
```

### Workflow: fold disagreement into a decision

```
# 1. Load two competing sources.
> /ingest cerec data/packs/authority_a.cerec myfield src:pack:auth_a:v1
> /ingest cerec data/packs/authority_b.cerec myfield src:pack:auth_b:v1

# 2. Scan for disagreement.
> /kg_consistency 300

# 3. For each conflict, decide with the human loop:
#    - accept authority_a's claim -> retract auth_b's version;
#    - accept authority_b's claim -> retract auth_a's version;
#    - keep both -> do nothing, atrophy tracker surfaces which source
#      loses observation weight over time.
> /retract some_disputed_label
> /retractions            # verify the audit trail
```

### Workflow: durable session

```
> /save /tmp/session.snap   # writes the full state to disk
# ... quit / crash / new machine ...
> /load /tmp/session.snap
(rehydrated: 584+247 atoms, retraction log restored, dlog re-opened)
```

---

## 9. Reference: file layout

```
data/packs/          -- .cerec content packs (7 shipped)
src/ingest/          -- ingestion framework (§4)
src/ingest/importers -- one file per format (§4)
src/agent/           -- agents including ingestion_agent (§4)
src/parts/reasoning  -- consistency + contradiction + retract (§6)
src/kg/              -- atom store, belief, multi-KG registry
src/agent/formal_chat.nova
                     -- FORMAL axiom/imp/retract/unretract API (§2)
src/parts/meta/meta_observer.nova
                     -- per-source atrophy tracker
src/session/         -- multi-tenant session shape
examples/crossengin_chat.nova
                     -- the REPL you interact with
scripts/llm_extract.sh
                     -- LLM-preprocessor helper (§5)
tests/unit/          -- one test file per module
NEXT_SESSION.md      -- rolling design + status doc
```

---

## 10. What CrossEngin is NOT

- **Not a language model.** There is no learned weight anywhere. Any
  LLM used is a data preprocessor, not a reasoner.
- **Not a database.** Snapshots are round-trippable but there's no
  query language beyond the KG walk primitives.
- **Not "production ready"** in the sense of a hosted service. It is
  a reasoning kernel + a growing set of layers on top. Read
  `NEXT_SESSION.md` for the current "what's built vs. what's next"
  ledger.
- **Not opinionated.** Every belief comes from a source. Every
  disagreement is preserved. Every retraction is logged.

---

## 11. Where to look next

- [`../NEXT_SESSION.md`](../NEXT_SESSION.md) — rolling ledger of
  what's built, what's next, and what's deferred.
- [`../README.md`](../README.md) — one-paragraph project overview.
- [`../MANUAL.md`](../MANUAL.md) — build + test walkthrough.
- Module docstrings — every `src/**/*.nova` file has a header
  documenting purpose, dependencies, and rationale.
- Test files — `tests/unit/test_*.nova` shows the expected usage
  shape for every module.
- Domain packs — `data/packs/*.cerec` are worked examples of every
  directive kind.

The design is deliberately transparent — no opaque state, no hidden
reasoning path, no learned parameters. If something isn't documented,
grep the source.
