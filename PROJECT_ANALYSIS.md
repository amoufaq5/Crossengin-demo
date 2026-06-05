# CrossEngin — Full Technical Analysis

> Reviewer's note: this is an independent read of the repository as it stands
> (~181k lines of NOVA across 469 files, 50 ADRs, 33+ development rounds).
> Everything below is grounded in the actual source, with `file:line`
> citations. Where a capability is wired structurally but not yet live on the
> integrated tick path, that is called out explicitly — the project's own
> `docs/design/data_flow.md` is admirably honest about this and so is this report.

---

## 0. What CrossEngin actually is (the one-paragraph truth)

CrossEngin is a **non-LLM cognitive substrate**. It is not a neural network, not
a transformer, and it samples no language model anywhere on its forward path —
every `LLM` token in the source is a comment asserting *no LLM* (ADR-0014), e.g.
`src/reader/reader.nova:9` "All cognition is substrate/KG activation; no LLM is
touched." Cognition is modeled as **integer-only** activation spreading over a
fabric of uniform units: **atoms** (knowledge), **synapses** (signed weighted
edges), **signals** (an 18-type taxonomy), and **knowledge graphs** (long-term
store). It is written entirely in **NOVA**, a self-hosting compiled language that
emits native x86-64 / arm64 / macOS / Windows / WASM with **zero runtime
dependencies**. All arithmetic is **milli-fixed-point** (`1.0 == 1000`), so there
is not a single float in the cognition path.

---

# PART A — The nine architectural questions

## A1. Full project analysis & quality

### Subsystem map

```
                        Operator surfaces
        scripts/web.py · bin/crossengin-chat REPL · /admin commands
                               │
                  ┌────────────┴─────────────┐
                  │   Unified daemon (1 proc) │  bin/crossengin
                  │   8-loop hybrid scheduler │
                  └────────────┬─────────────┘
        ┌───────────┬──────────┼───────────┬───────────┐
        ▼           ▼          ▼           ▼           ▼
   PERCEPTION    READER       KGs       REASONING    ACTION
   image/audio   5-stage    atoms +    forward-     output +
   video/stream  lexical→   synapses   chain +      effector
   (src/io)      coherence  episodic   counterfac.  gate + TTS
        └───────────┴──────────┼───────────┴───────────┘
                               ▼
                    Substrate kernel (9 modules)
            parts · gates · resonance · signal_dispatch ·
            synapse_graph · tick_driver
                               ▼
                Persistence + Federation
       snapshot + Merkle + Ed25519 · SWIM gossip · Noise-XK · NAT
```

### Quality scorecard (independent assessment)

| Dimension | Grade | Evidence |
|---|---|---|
| **Architectural coherence** | A | Clean 20-subsystem layering; one-for-one ADR↔folder mapping; the substrate kernel is deliberately tiny (9 modules). |
| **Documentation** | A+ | 50 ADRs, per-subsystem READMEs, 10 deep-dive audits (IMAGE/AUDIO/FEDERATED/SECAGG/TLS/DP), runbooks. Rare in any codebase. |
| **Breadth of implementation** | A | Real SIFT/ORB/HOG, Lucas-Kanade, SGM stereo, FFT/MFCC, Klatt synth, ChaCha20-Poly1305, Ed25519, 2048-bit DH, SWIM gossip, DTLS 1.2, X.509 — all hand-written in NOVA. |
| **Crypto/safety correctness** | A− | RFC-cited (8032, 7919, 6347, 8489, 180-4); test vectors in audits. Single-cert X.509 only (no CA chain) — acknowledged. |
| **Test discipline** | B+ | 378 test files, 93 unit suites, scenario + failmode integration tests, benchmark baselines with regression gates. |
| **Verifiability right now** | C | Cannot build in this container — requires the external NOVA toolchain at `$HOME/NOVA`; `bin/` is empty. Correctness is asserted via NOVA's own test harness, not reproducible here. |
| **Integration completeness** | B− | The honest gap: per `docs/design/data_flow.md:55-60`, predictive-coding error and emotional modulation are wired in the module APIs but the **live tick currently passes `error=0` and `modulator=1.0`**. Several advanced loops are "module exists, not yet on the hot path." |
| **Empirical AGI evidence** | D | The AGI-relevant claims (theory of mind, self-awareness, initiative) are *mechanisms that exist*, not *capabilities demonstrated by benchmark*. No task-level eval suite proves emergent behavior. |

**Bottom line:** This is an unusually disciplined, internally consistent,
genuinely from-scratch systems project — the engineering quality is high and the
documentation is exceptional. The honest caveat is that it is a **substrate with
the wiring for cognition**, not yet a system with **demonstrated** cognition: the
most interesting loops are partially live, and the headline AGI properties are
architectural affordances rather than measured results.

---

## A2. How learning happens & how reasoning happens

### Learning — five concurrent mechanisms, all integer math

CrossEngin has **no single learning rule**. It layers five, each with its own
trigger and update equation. All constants are milli (`÷1000`).

**(1) Synaptic plasticity — fused Hebbian + error-driven** (`synapse_graph.nova:225-239`)

```
dw_hebb  = η_h · pre · post                 # η_h = SYN_ETA_H = 0.02
dw_err   = η_e · pre · error                # η_e = SYN_ETA_E = 0.03
dw_total = modulator · (dw_hebb + dw_err)
w' = clamp(w + dw_total, −1.0, +1.0)
elig' = clamp(elig + pre·post, 0, 1.0);  elig ← 0.9·elig each tick
```
Synapses with `|w| < 0.02 ∧ elig < 0.01` are **pruned** (death). This is the
core "learning rate": **η_h = 0.02 Hebbian, η_e = 0.03 error-driven**, globally
scaled by an emotion-derived `modulator ∈ [0.2, 2.5]`.

**(2) Bayesian belief tracking — Beta(α,β) per atom** (`bayesian_updates.nova`)

Every atom carries a belief `[α, β]` (prior `Beta(1,1)`, stored as `1000,1000`).
On evidence:
```
decay:    α ← 1 + (α−1)·r,  β ← 1 + (β−1)·r       # r = retain factor
observe:  supports ? α += weight : β += weight
conflict EWMA: rec_sup ← 0.9·rec_sup + w_support
confidence (posterior mean) = α / (α+β)
```
Evidence `weight` is **source-tiered**: Tier-A=1.0, Tier-B=0.6, Tier-C=0.3,
user-teaching=1.5. An atom is **contested** when conflict fraction ≥ 0.4 and
total evidence ≥ 8.0.

**(3) Predictive coding** (`predictive_coding_runtime.nova`)
```
precision_weighted_error = (actual − predicted) · precision
emit error signal only if |error| > 0.15   (surprise preempts at 0.30)
```
This error is what *should* feed `dw_err` above — **note the integration gap:
the live tick currently passes error=0** (`data_flow.md:57`).

**(4) Atom birth / death** (`atom_birth_monitor.nova`, `atom_death_monitor.nova`)
- Birth gate: pattern recurs ≥5× (≥3× under surprise) **and** novel (cosine <0.9
  to any existing atom) **and** stable across ≥3 moments → mint a new
  `ATOM_CONCEPT` with `α = 1000 + weight`.
- Death gate: `activation < 0.02 ∧ evidence(α+β) < 4.0 ∧ not protected ∧ not
  cross-referenced` → two-phase tombstone→hard-delete with a rescue window.

**(5) Resonance / assembly formation** (`resonance_engine.nova`)
Reciprocally connected, co-active (≥0.4) pairs get **bidirectionally**
potentiated by 0.05/step (seed 0.2), forming stable attractor assemblies — the
substrate's "bound percept."

**Learning trigger arbitration** (`self_learning_triggers.nova`): five sources
(user request 1.0, prediction error 0.7, unknown query 0.6, imagination gap 0.4,
curiosity 0.3) are scored `priority = source · gap · goal_alignment` and queued
(depth 8, dedup by concept, user always preempts).

### Reasoning — symbolic forward/abductive chaining over operator atoms

Reasoning is **not** statistical. Relations are first-class **operator atoms**
(`ROP_CAUSAL`, `ROP_IMPLY`, `ROP_ANALOGY`, `ROP_EVIDENCE`) whose confidence is
itself a Bayesian belief updated by co-firing on success/failure.

```
ALGORITHM reason_forward_chain(rkg, seed, max_steps=3):
    visited = {seed}; frontier = {seed}; trace = []
    repeat max_steps times:
        next = {}
        for atom in frontier:
            for op in operators_with_premise(atom):
                if op.kind in {CAUSAL, IMPLY} and op.conclusion ∉ visited:
                    trace += [op, atom, op.conclusion, op.confidence]
                    visited += op.conclusion;  next += op.conclusion
        frontier = next
    return trace
```

**Confidence math** (`reasoning_module.nova:147-167`):
- Chain (serial links, AND): `c = Π cᵢ` (each weak link weakens the proof).
- Support (independent sources, OR / noisy-OR): `c = c + cᵢ − c·cᵢ`.

Other reasoning modes:
- **Abduction**: best causal premise pointing *to* an observation (argmax conf).
- **Means-ends**: collect `IMPLY` premises pointing to a goal → subgoals.
- **Proof checker** (`proof_checker.nova`): bidirectional BFS, depth ≤6, ≤1024
  visits, returns `[valid, chain, strength, visited]` with per-step clamping to
  avoid integer overflow. Exposed as the `/prove` admin command.

---

## A3. How initiation happens & how consequences are considered

### Initiation (initiative / agency) — drive-generated goals

The agent acts **without external prompting** because four intrinsic **drives**
spawn goals every tick (`drive_generators.nova`):

| Drive | Fires when | Priority formula |
|---|---|---|
| Curiosity | knowledge_gap ≥ 0.3 | `gap · novelty` |
| Social | time_since_interaction ≥ 500 | `min(Δt, 1.0)` |
| Task | pending_requests > 0 | fixed 0.9 (highest) |
| Homeostasis | valence < 0.3 **or** mem_load > 0.8 | 0.6 / 0.5 |

Goals form a hierarchy (`goal_engine.nova`); arbitration selects the
**highest-priority active *leaf*** (only leaves execute), progress rolls up as
the **mean of children**, blocking propagates upward, and stale goals decay
(`priority ← priority · r`). This is the "self-directed" part of the AGI claim:
behavior originates from internal drives, not just stimuli.

### Consequence consideration — a two-front gate

**(a) Imagination forecasts outcomes before acting** (`forward_sim.nova`):
```
ALGORITHM forward_simulate(ikg, state, steps, min_conf):
    cur = state
    repeat steps times:
        p = highest-confidence pattern whose situation ⊆ cur,
            that adds ≥1 new atom, with conf ≥ min_conf
        if none: return cur                  # stall
        cur' = cur ∪ p.successor
        if cur' == cur: return cur           # fixpoint
        cur = cur'
    return cur
```
- **Counterfactual**: simulate factual vs. a clamped state (remove/add one atom),
  measure **divergence = |symmetric difference|** of the two outcome sets.
- **Scenario planner**: branch per candidate decision, score each by
  `#goals_reached`, pick `argmax` (or `argmin` for risk).

**(b) Safety gate vets every external action** (`constitutional_filter.nova:48-58`):
```
gate(action):
    if constitutional_veto:  return VETOED   # terminal — user cannot override
    if hard_stop:            return HALTED
    tier = max(default_tier(action), reversibility_floor(action))
    if tier == APPROVE: return user_approved ? EXECUTE : SUSPEND
    if tier == NOTIFY:  return NOTIFY
    return EXECUTE
```
Reversibility is classified per action class (`reversibility_classifier.nova`):
REVERSIBLE (read, fetch) → auto; RECOVERABLE (write, speak) → notify;
IRREVERSIBLE (send_msg, hard_delete, spend, self_modify) → **require approval**.
Unknown actions **fail safe to IRREVERSIBLE**. Every gate decision is logged
(ADR-0043), and a 4-level override exists (belief-edit/pin, goal-veto,
hard-stop, kill-switch).

---

## A4. Are there tokens / embeddings?

**Tokens:** There is **no LLM tokenizer and no token vocabulary**. "Tokenization"
means *whitespace splitting + lowercasing* of surface text in the reader's stage 1
(`lexical_anchor.nova`), matching each surface token to a **word atom** in the
language KG. STT produces text tokens; that's the only sense of "token" present.

**Embeddings:** Yes — but **tiny, deterministic, and not learned**:
- **8-dimensional integer vectors**, each component in `[0,1000]` milli
  (`atom_store.nova`, `ATOM_EMBED_DIMS = 8`).
- Word embeddings are **character-hashed**: each char adds 40 to dimension
  `char % 8` (`word_atoms.nova:43-51`). Words sharing letters get similar vectors
  — a deliberately cheap fuzzy-match, **not** a trained semantic embedding.
- Similarity is **integer cosine** with Newton's-method `isqrt` (no floats).
- `semantic_search.nova` adds an integer **TF-IDF** (`tf = 1+log₂(count)`,
  `idf = log₂(N/df)+100`) for the `/find` command.

So: **no learned token embeddings, no 768-d transformer vectors** — knowledge
lives in the *graph topology and Bayesian beliefs*, not in dense vectors. The 8-d
vectors are only a coarse routing/clustering aid (and the LSH ANN index key).

---

## A5. CrossEngin vs. an LLM — full comparison & rating

Ratings are **1–10 for the stated dimension**, not overall "goodness." They
describe *what each architecture is structurally good at*.

| Aspect | CrossEngin | LLM (e.g. GPT/Claude class) | Notes |
|---|---:|---:|---|
| Natural-language fluency | 2 | 10 | CE has templated output only; no generative language model. |
| World knowledge breadth (out of box) | 2 | 10 | LLM pretrained on web-scale corpus; CE seeds ~700 atoms, learns the rest live. |
| **Continual / online learning** | 9 | 3 | CE learns every tick and persists it; LLMs are frozen post-training (need fine-tune/RAG). |
| **Provenance & explainability** | 10 | 3 | CE: `/why` walks a real proof tree; every belief has α/β + source tier. LLM: post-hoc rationalization. |
| **Determinism / reproducibility** | 10 | 4 | CE is integer, seedable, bit-reproducible. LLMs sample. |
| Reasoning rigor (verifiable) | 7 | 5 | CE has a real proof checker; LLM reasoning is fluent but unverifiable. |
| Reasoning breadth (fuzzy/common-sense) | 3 | 9 | LLM generalizes far beyond its rules; CE only chains operators it possesses. |
| **Resource footprint** | 10 | 2 | CE: no GPU, no runtime deps, MBs of RAM. LLM: GPUs, GBs–TBs. |
| **Auditability / safety gating** | 9 | 5 | CE gates every irreversible action with reversibility tiers + constitution. |
| **Initiative / autonomy** | 8 | 3 | CE has intrinsic drives; an LLM is reactive to prompts. |
| **Privacy (local, federated)** | 9 | 4 | CE runs fully local; SecAgg/DP federation. LLMs typically cloud. |
| Multimodal perception (built-in) | 7 | 6 | CE ships classical CV/audio stacks in-tree; LLMs need adapters. |
| Maturity / ecosystem | 2 | 10 | LLMs have vast tooling; CE is a single research codebase. |
| Empirical capability *today* | 3 | 9 | LLMs demonstrably solve tasks; CE's headline capabilities are mechanisms, not benchmarked results. |

**Synthesis:** They are near-**complementary opposites**. The LLM is a
knowledge-and-fluency engine that cannot learn online, cannot truly explain
itself, and is heavy. CrossEngin is a transparent, lightweight, continually
learning, self-auditing agent that **cannot speak fluently or reason outside its
acquired rules**. The natural future is **hybrid**: an LLM for language/world
priors, CrossEngin for persistent memory, provenance, drives, and the safety
gate. (CE's own ADR-0014 deliberately keeps the LLM out of the *cognition* path —
a hybrid would put it at the *language I/O* edge only.)

---

## A6. How it can be used / deployed

Build path (`MANUAL.md`): clone the **NOVA** toolchain to `$HOME/NOVA`, `make` it
(needs only `gcc/as/ld/make/git` — no npm/python/cargo/jvm), then in the repo:
```
make test        # 93 unit suites
make install     # build runnable artifacts into bin/
./bin/crossengin # the whole agent in one process
```
Artifacts are **native static ELF** (x86-64 Linux). Windows PE is a real
`make cross-windows` target (mingw, runnable under WSL2/Docker, smoke-tested
under wine). **Caveat (honest):** the README markets arm64/macOS/WASM, but the
**Makefile has no WASM or macOS build target today** — those are aspirational,
not shipped. Deployment forms that *do* exist:
1. **Single-process daemon** (`bin/crossengin`) — embedded/edge agent.
2. **CLI REPL** (`bin/crossengin-chat`) — persistent state across turns.
3. **Web app** (`scripts/web.py`) — see A7.
4. **Federated cluster** — `crossengin-fed-coordinator` (port 8777, 30 s rounds,
   `FED_JOIN`→`FED_ROUND`→`FED_STAT_MASKED`→`FED_AGGREGATE`, per-soul DP epsilon)
   + KG pub/sub binaries, SWIM gossip, leader election, distributed
   SPARQL/Datalog, SecAgg.
5. **Windows native** via `make cross-windows` (WSL2/Docker).
6. **One-click Codespaces** devcontainer (2 vCPU / 4 GB; builds NOVA + CE in
   ~2 min).

Footprint: **no GPU, no external runtime**, MB-scale memory. Snapshots are
crash-safe (`write→fsync→rename`), tamper-evident (SHA-256 Merkle root +
Ed25519 signature), and support incremental deltas + compaction.

## A7. Chatbot, web app — and what else?

**Web app (`scripts/web.py`):** a **pure Python-stdlib** `ThreadingHTTPServer`
(no Flask, no third-party libs) that spawns **one `crossengin-chat` subprocess
per session cookie**, so every browser gets isolated cognitive state (its own
soul, KGs, decision log). Features: per-cookie LRU cap (default 8), request
serialization, a Prometheus `/metrics` endpoint (P2.9), `/api/sessions`,
`/api/atoms` KG browser, and the full admin surface (`/teach /pin /reflect
/learn /status /halt /resume /why /history`) over HTTP. Loopback-bound by default
(admin commands shouldn't face the LAN).

Session isolation is strong: the hybrid **scheduler is held per-session**, so each
tenant has its own tick clock, idle counter, and event queue — a stuck tenant
cannot starve the others. The substrate part registry and gate router are
process-shared.

So CrossEngin can be used as:
- a **chatbot / companion** (REPL or web),
- a **web service** with Prometheus observability,
- an **embedded edge agent** (single static binary),
- a **federated knowledge network** (gossip + SecAgg + DP),
- a **domain expert** via seed packs (`medical`, `ops_runbook`, `code_review`),
- a **research substrate** for studying continual learning / agency.

## A8. Enterprise vs. consumer use

**Enterprise.** The differentiators are *provenance, privacy, and audit*:
- Every fact carries a source tier + Bayesian confidence; `/why` reconstructs the
  reasoning — strong fit for **regulated domains** (healthcare via `medical_pack`,
  ops via `ops_runbook_pack`, compliance).
- **Federated learning with SecAgg (2048-bit DH) + differential privacy +
  Byzantine-robust aggregation** means many sites learn a shared model **without
  sharing raw data** — ideal for hospitals/banks.
- **Deterministic + fully auditable + reversibility-gated** actions suit
  safety-critical automation; the kill-switch/hard-stop/override chain is a
  governance story regulators like.
- On-prem / air-gapped: no GPU, no cloud, no telemetry by default.

**Consumer.** A **private, local, persistent companion** that genuinely
*remembers* you across sessions (episodic memory + soul/identity), runs on modest
hardware or in-browser (WASM), keeps all data on-device, and shows initiative via
drives. The honest consumer caveat: **language output is templated**, so today it
feels more like a transparent reasoning/memory agent than a chatty assistant —
this is exactly where a hybrid LLM-at-the-edge would help.

## A9. Where is the room to grow (technically)?

1. **Close the integration gap** — make predictive-coding error and emotional
   modulation *live* on the tick (`data_flow.md:55-60` flags both as currently
   `0`/neutral). This is the single highest-leverage fix: it activates the
   error-driven half of the learning rule that is already written.
2. **Language generation** — templated output is the biggest capability ceiling.
   Either a small grammar-based NLG layer or a hybrid LLM strictly at the I/O
   edge (preserving ADR-0014's no-LLM-in-cognition rule).
3. **Embeddings** — 8-d char-hash vectors are a coarse routing key. A learned (or
   at least higher-dimensional distributional) embedding would sharpen ANN
   recall, concept promotion, and semantic search.
4. **Empirical eval harness** — add task-level benchmarks that *demonstrate* the
   AGI-relevant claims (continual-learning curves, theory-of-mind probes,
   plan-quality metrics), not just unit assertions.
5. **Scale of the KG** — atom store is hash-indexed O(1) and LSH-ANN'd, but
   inference (forward-chaining, Datalog) and Louvain/PageRank analytics need
   profiling at 10⁶+ atoms; current benches top out far lower.
6. **Reproducible build in CI** — `bin/` is empty and the build needs the
   external NOVA toolchain; a containerized, pinned NOVA + green CI badge would
   make correctness independently verifiable.
7. **Multi-cert X.509 / CA chains** — current cert validation is single-cert
   (SDP-fingerprint pinning); full chain traversal is deferred.

---

# PART B — The seven mechanism questions

## B1. How it calls and fetches data

```
unknown query / curiosity ──► self_learning_triggers ──► if_permit gate
                                                              │
   whitelist? rate-ok? not in-flight? domain-spaced? cached? ─┘
                                │ FETCH_OK
                                ▼
                http_client.http_get(url, max_bytes)   ── pure NOVA HTTP/1.1
                                │  [status, headers, body]
                                ▼
                if_ingest ─► validate type (html/json/text) + ≤2MB
                          ─► wrap as ATOM_FACT, provenance=fetched, tier-weighted
                          ─► cache (7-day TTL)
```
- **HTTP** (`http_client.nova`): in-process HTTP/1.1 GET, `Connection: close`, no
  redirects/compression/chunking; resolves dotted-quad or an env DNS cache.
- **Gating** (`internet_fetch.nova`): **30 req/hr**, **≥2 s** between same-host
  hits, **≤1 in-flight**, **≤2 MB**, 7-day cache; whitelist-only.
- **RSS/Atom** (`kg_rss_ingest.nova`): parses XML, dedups by `guid`/link, mints
  one `ATOM_FACT` per item (≤100 items, ≤1 MB feed) with `provenance=rss:<url>`.
- **Fetched bytes never enter any LLM** — they become atoms with provenance.

## B2. Learning rate & mechanism

The "learning rate" is not one number but a small set of explicit constants:

| Mechanism | Rate / constant | Value |
|---|---|---|
| Hebbian plasticity | `SYN_ETA_H` | **0.02** |
| Error-driven plasticity | `SYN_ETA_E` | **0.03** |
| Emotion modulator (global gain on both) | `[PM_MIN, PM_MAX]` | **0.2 – 2.5** |
| Eligibility-trace decay | `SYN_ELIG_DECAY` | **0.9 / tick** |
| Bayesian evidence weight | source tier | **0.3 / 0.6 / 1.0 / 1.5** |
| Conflict EWMA decay | `BAYES_REC_DECAY` | **0.9** |
| Resonance potentiation | `RES_DELTA` | **0.05 / step** |
| Atom-birth threshold | recurrences / novelty | **≥5× / cosine<0.9** |

Update equations are in **A2**. The defining property: learning is **local**
(per-synapse, per-atom), **online** (every tick), **bounded** (weights clamped
±1.0, beliefs decay), and **modulated** by emotion — there is no global
backpropagation and no gradient descent.

## B3. How data is structured (preprocessing)

An **atom** (`atom_store.nova:19`):
```
[TAG, id, kg_id, kind, label, payload, belief[α,β], embed[8], xrefs,
 provenance[tier,part], created_moment, updated_moment, version]
kind ∈ {FACT, RELATION, CONCEPT, SKILL, LANG, RULE}
```
Text → atoms via the **five-stage reader** (`reader.nova`):
```
text ─► (1) lexical_anchor : split+lowercase, match tokens→word atoms
     ─► (2) context_bias   : reweight senses by previous-context centroid
     ─► (3) spreading_act  : seed 1.0, 2 hops, decay 0.5, threshold 0.2
     ─► (4) coherence_check: mean pairwise cosine ≥ accept floor
     ─► (5) fetch/route/learn : route to parts, trigger learning on gaps
```
Above the atom layer sits the **concept layer** (`concept_layer.nova`): tight
clusters (mean pairwise cosine > 0.7) are **promoted** into DAG concepts with
typed **schema slots** (fill-ratio drives competence + knowledge-gap detection)
and four **facet vectors** (lexical / semantic / relational / affective).

## B4. How training happens & how data is stored

**"Training"** here is the continuous learning of B2 — there is no offline
train/test split, no epoch loop, no parameter file. The system simply runs, and
every tick mutates synapses, beliefs, and the atom population. The four-phase
tick (`data_flow.md`):
```
snapshot ─► integrate (leaky-integrate + fire + refractory) ─► propagate
         ─► learn (Hebbian+error plasticity, eligibility decay)
```
**Storage / persistence** (`src/persistence/`):
- **Snapshot v2**: line-oriented ASCII, sections SOUL / KGS(atoms) / EPISODIC /
  SYNAPSES / SELFMODEL; atoms serialize id+kind+label+α+β+embed; synapses
  serialize src/dst/weight per part.
- **Crash-safe**: `write tmp → fsync → atomic rename → fsync dir`.
- **Incremental**: `snapshot_delta` ADD/MOD/DEL ops with a parent fingerprint;
  periodic **compaction** collapses deltas into a fresh full snapshot.
- **Tamper-evidence**: SHA-256 **Merkle** tree over atom bytes → 64-hex root,
  optionally **Ed25519-signed** (`merkle_signing.nova`). Any 1-bit edit changes
  the root.
- **Schema migration** framework versions the atom format (v1→v2→v3).

## B5. How it simulates events & consequences

See **A3** for the algorithms. Summary:
- **Forward simulation** rolls the active-atom state forward up to *N* steps by
  repeatedly applying the highest-confidence *productive* pattern, stopping at a
  stall or fixpoint.
- **Counterfactual** clamps one atom (remove/add), re-simulates, and reports
  **divergence = |symmetric difference|** between factual and counterfactual
  outcome sets — a concrete causal-impact number.
- **Scenario planner** branches per decision, scores by `#goals_reached`, returns
  best/worst — feeding long-horizon goal selection.
- **Dream recombination** (idle) probabilistically blends memory fragments
  (per-atom inclusion prob = `creativity`, deterministic by seed) to *discover*
  new patterns that later become forward-sim rules.

## B6. How a skill is developed from a gained KG

Skills are first-class (`skills_kg.nova` + `competence_tracker.nova`):
1. **Grounding** — facts/operators about a domain accumulate as atoms with rising
   Bayesian confidence; concept **slot fill-ratio** measures structural
   understanding.
2. **Competence assessment** — three kinds:
   `KNOW = mean atom confidence`, `DO = mean skill reliability`,
   `UNDERSTAND = mean concept fill-ratio`.
3. **Tiering** (`competence_tracker.nova`):
   ```
   CAPABLE  : mean ≥ 0.75 AND evidence ≥ 20
   PARTIAL  : mean ≥ 0.50
   AWARE    : grounded but < 0.50
   UNKNOWN  : no grounding
   ```
   This gives an **honest self-model** — the agent's "I can do X" never exceeds
   its evidence (feeds `self_model_query` and theory-of-mind).
4. **Closure** (`confidence_thresholds.nova`) — a learning episode ends only when
   evidence-strength + posterior-mean + ≥80% self-test + ≥2 independent sources
   thresholds pass (higher bars for high-stakes skills), or a hard fetch cap
   forces a *provisional* close (kept, but not credited to competence).

So a skill "develops" as: gather grounded atoms → confidence climbs → slots fill
→ self-tests pass → multi-source corroboration → tier crosses to CAPABLE.

## B7. How to deploy it and in what form

Covered in **A6/A7**. Concisely:
```
make install                              # native static binaries, no deps
./bin/crossengin                          # 1) embedded daemon
./bin/crossengin-chat                     # 2) CLI companion (persistent)
python3 scripts/web.py  → :8765           # 3) web app (per-cookie isolation)
./bin/crossengin-fed-coordinator ...      # 4) federated cluster
# 5) compile to WASM for in-browser; 6) Codespaces one-click devcontainer
```
Forms: **edge daemon · CLI chatbot · web service (Prometheus-observable) ·
federated knowledge mesh · in-browser WASM · domain expert via seed packs.**
No GPU, no runtime deps, crash-safe + tamper-evident persistence.

---

## Appendix — key numeric constants (single reference)

| Constant | Value | Meaning |
|---|---|---|
| `FP_SCALE` | 1000 | milli fixed-point (1.0) |
| `SYN_ETA_H / SYN_ETA_E` | 0.02 / 0.03 | Hebbian / error learning rate |
| `W_MIN / W_MAX` | −1.0 / +1.0 | synapse weight bounds |
| `PM_MOD_MIN / MAX` | 0.2 / 2.5 | emotion plasticity modulator |
| `BEL_PRIOR` | 1.0 (1000) | Beta(1,1) uniform prior |
| source tiers | 1.0 / 0.6 / 0.3 / 1.5 | A / B / C / user evidence weight |
| `PC_THETA_ERR / SURPRISE` | 0.15 / 0.30 | predictive-coding thresholds |
| `BIRTH_FREQ / NOVELTY / STABILITY` | 5 / 0.9 / 3 | atom-birth gates |
| `DEATH_STRENGTH / BELIEF` | 0.02 / 4.0 | atom-death gates |
| `RES_COACT / DELTA / SEED` | 0.4 / 0.05 / 0.2 | resonance assembly |
| `LOOP_REASON_DEPTH` | 3 | forward-chain steps/cycle |
| `PROOF_DEFAULT_DEPTH / VISITS` | 6 / 1024 | proof-checker BFS bounds |
| `ATOM_EMBED_DIMS` | 8 | embedding dimensionality |
| `IF_MAX_PER_HOUR / SPACING / BYTES / TTL` | 30 / 2s / 2MB / 7d | fetch gating |
| `CT_HIGH_MEAN / STRENGTH / SOURCES` | 0.85 / 20 / 2 | high-stakes closure |
| `TIER_CAPABLE mean / evidence` | 0.75 / 20 | competence "CAPABLE" |
```
