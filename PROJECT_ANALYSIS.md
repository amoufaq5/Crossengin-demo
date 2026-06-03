# CrossEngin — Project Analysis & Roadmap

> An independent, code-grounded review of the CrossEngin substrate as of v1.0
> (R22F). Conclusions are drawn from reading the source — the NOVA toolchain was
> not available in the review environment, so the project's own "tests green"
> counts are reported as self-stated, not independently reproduced.

---

## 1. What CrossEngin is

A **non-LLM cognitive substrate** written in NOVA (a custom, dependency-free,
self-hosting language compiling to x86-64 ELF). Rather than a neural network it
runs a fabric of uniform leaky-integrate-and-fire nodes joined by plastic
synapses; above that sit symbolic **knowledge graphs of atoms** whose truth is
tracked as **Bayesian Beta(α,β) beliefs**. A six-loop agent
(perception → memory → reasoning → emotion → goals → action) plus an idle
**imagination** loop is driven by an event/idle hybrid scheduler. It learns at
runtime, reasons by forward-chaining over causal/implicative operators, weighs
consequences through a reversibility-graded safety gate, and persists itself to
disk. **No LLM, no tensors, no gradient descent, and no token vocabulary
participate in cognition** (ADR-0014).

**Artifact scale:** 181 source modules (~87k lines NOVA), 202 unit-test files +
113 integration scripts (~49k test lines), 50 ADRs, 57 docs.

---

## 2. Quality assessment

**Overall grade: B+/A−** as a research substrate.

### Strengths
- **Real implementations, not stubs** across every subsystem sampled (node
  kernel, Beta-belief math, forward-chaining, safety gate, Merkle/Ed25519, DTW/
  MFCC, federated learning).
- **Disciplined engineering:** 50 ADRs bind every module; headers cite ADRs and
  deps; every module has happy/edge/failure unit tests (ADR-0049); hash-chained
  audit log; crash-safe persistence (tmp → fsync → atomic rename → parent fsync).
- **Coherent philosophy** applied consistently: uniform kernel, integer milli-
  fixed-point everywhere (no floats), fail-safe defaults, constitution-first
  signal ordering.
- **Learning maps to published algorithms:** Beta-Binomial conjugate priors;
  Friston precision-weighted predictive coding; Collins & Loftus spreading
  activation; Bonawitz secure aggregation; Yin et al. Byzantine trimmed-mean/
  median; semi-naive Datalog.
- **Security maturity** unusual for research code: Noise-XK mutual auth, RFC 7919
  DH, Ed25519, Merkle proofs, differential-privacy budget.

### Weaknesses / caveats
- **Unproven at scale.** ADRs target 1M nodes/part @ 100Hz with true
  concurrency; the toolchain does not deliver that yet. Modules are
  "functionally correct at *configurable* (small) capacity."
- **Shallow knowledge/language.** ~570–700 seed atoms, ~250 English lemmas;
  output is telegraphic (reverse concept→word lookup).
- **Internal crypto inconsistency.** The gossip transport uses production-grade
  Noise-XK + Ed25519 + RFC 7919, but the secure-aggregation DH seam is explicit
  MVP crypto (`g=2`, non-safe prime, weak RNG) — documented in-code as breaking
  "under modern crypto adversaries."
- **README is a 2,500-line changelog** — high detail, poor navigability.
- **Not independently built here** — test-pass claims are self-reported.

---

## 3. How learning happens

| Mechanism | Module | Essence |
|---|---|---|
| Belief representation | `kg/atom_store.nova` | Beta(α,β) milli pseudo-counts; confidence = α/(α+β) |
| Evidence updates | `learning/bayesian_updates.nova` | Conjugate update + decay + EWMA conflict → `CONTESTED` flag (≥0.4 ratio, ≥8.0 mass) |
| Source weighting | `learning/source_authority.nova` | user 1.5 > Tier-A 1.0 > B 0.6 > C 0.3; conflict policies neutral/normative/classical |
| Predictive coding | `learning/predictive_coding_runtime.nova` | Precision-weighted error; emit >0.15, surprise >0.30 |
| Self-directed triggers | `learning/self_learning_triggers.nova` | curiosity / imagination-gap / prediction-error / unknown-query / user-request → priority arbiter queue |
| Teach ingestion | `learning/ask_user_to_teach.nova` | Beta(4,1) Tier-A prior; ask-budget gated |
| Internet learning | `learning/internet_fetch.nova` + `source_authority` | whitelist → rate-limit → cache → validate → tiered ingest |
| Episode close | `learning/confidence_thresholds.nova` | low/high-stakes "learned enough" gates + hard caps |
| Sub-symbolic plasticity | `substrate/tick_driver.nova` + `learning/plasticity_modulation.nova` | Hebbian + error-driven, emotion-modulated (0.2×–2.5×), batched at tick boundary |
| Lifecycle | `learning/atom_birth_monitor.nova` / `atom_death_monitor.nova` | birth: freq≥5 + ≥3 episodes + novelty<0.9; death: cold-atom GC, 2-phase tombstone |
| Federation | `learning/federated_aggregator.nova` + `secure_aggregation.nova` + `byzantine_aggregation.nova` | DP (Laplace, ε=1.0) + pairwise masking (sum-only) + trimmed-mean/median |

## 4. How reasoning happens

- **Forward chaining** over operator atoms (causal/implicative/analogical/
  evidential) — `parts/reasoning/reasoning_module.nova`. Produces "see treat"
  from "fever" with no LLM choosing words (reverse concept→word lookup names the
  conclusion).
- **Abduction, analogical transfer, means-ends, evidential combination** — same
  module, five thin strategies.
- **Spreading activation** settles input onto an active concept set
  (`reader/spreading_activation.nova`).
- **Mini-Datalog rule engine** (`kg/rule_inference.nova`) — declarative rules
  forward-chained to fixpoint with provenance; `kg/rule_explain.nova` builds
  recursive proof trees to ground facts.
- **BFS proof checker** (`parts/reasoning/proof_checker.nova`) validates
  premise→conclusion chains and renders human-readable proofs.
- **Mini-SPARQL** (`kg/query.nova`): BGP + FILTER + OPTIONAL + UNION + ORDER BY +
  GROUP BY + aggregates over the KG.

**Key property:** every conclusion is symbolically traceable — explainable by
construction, unlike opaque LLM activations.

## 5. Initiative & consequence-handling

**Initiative** = idle-gated imagination. After 20 empty ticks the hybrid
scheduler drops 100Hz→10Hz and gates the 7th loop on; `loop_imagination_step`
forward-simulates 3 steps on active concepts into a scratch KG. Via `/reflect`
these become tentative Beta(2,1) atoms; when later perception corroborates one
its belief crosses threshold and it is **promoted to real knowledge**. Four
intrinsic drives + the trigger queue also generate unprompted goals/episodes.

**Consequence gate** (every outward action):
1. `reversibility_classifier.nova` → reversible / recoverable / irreversible
   (unlisted ⇒ irreversible, fail-safe).
2. `permission_tiers.nova` → AUTO / NOTIFY / APPROVE = MAX(static default,
   reversibility floor); irreversible always ≥ APPROVE.
3. `constitutional_filter.nova` `safety_gate`: constitutional veto (terminal —
   no approval clears it) → hard-stop → tier → approval. Dual veto paths (literal
   text + concept intent). Loyalty: constitution > enterprise > user > system.

Plus graded overrides (`override_mechanism.nova`): belief edit (+pin), goal veto
(subtree prune), hard stop, kill switch. Every decision is written to a
hash-chained, tamper-evident log; `/why` reconstructs reasoning from stored
state, no LLM.

## 6. Tokens / embeddings

**No LLM tokens or learned embeddings anywhere.** "token" = lexical
whitespace tokens in the reader; "embedding" = hand-rolled 8-dimensional integer
lexical vectors (`ATOM_EMBED_DIMS=8`) used for integer-cosine similarity and LSH
ANN. Units of meaning are **symbolic atoms with Bayesian beliefs**, not float
vectors. No BPE vocabulary, no token embeddings, no tensors, no attention.

## 7. CrossEngin vs LLM (ratings 1–10, vs frontier LLM baseline)

| Aspect | CE | LLM |
|---|---|---|
| Language fluency / generation | 2 | 10 |
| World-knowledge breadth | 2 | 9 |
| Continuous / online learning | 9 | 3 |
| Explainability / provenance | 10 | 2 |
| Symbolic reasoning rigor | 8 | 5 |
| Hallucination resistance | 9 | 4 |
| Safety / consequence model | 9 | 5 |
| Initiative / self-direction | 7 | 4 |
| Determinism / auditability | 9 | 3 |
| Resource footprint | 9 | 2 |
| Multimodal depth | 5 | 8 |
| Theory of mind / long-horizon goals | 6 | 6 |
| Common-sense coverage | 2 | 8 |
| Maturity / proven at scale | 3 | 10 |
| Privacy / on-device / federation | 9 | 4 |

**Verdict:** complementary, not competing. CE wins on transparency, online
learning, safety, auditability, hallucination resistance, footprint, privacy;
loses on fluency, knowledge breadth, maturity. A natural pairing is an LLM
language *surface* over a CE reasoning/memory/safety *core* (keeping cognition
LLM-free per ADR-0014).

## 8. Deployment surfaces

- `bin/crossengin` — full unified daemon (durable snapshots).
- `bin/crossengin-chat` — persistent REPL, ~80 admin commands.
- `scripts/web.py` — stdlib-only browser chat (`:8765`), per-cookie session
  isolation, `POST /api/chat`, `/api/sessions`.
- `scripts/chat.sh` — zero-dependency bash shim.
- KG sync publisher/subscriber + federation mesh (SWIM gossip, leader election,
  distributed rules/query, Noise-XK transport, signed attestation).
- Ops: JSON logging (`CE_LOG_JSON=1`), `crossengin-doctor.sh` preflight,
  `/metrics`, snapshot diff/migrate, real-time pacing.

Runs today as a single Linux x86-64 process (or one-click Codespaces /
devcontainer) — at configurable small scale.

## 9. Usable as

Chatbot / REPL · browser web app · embeddable daemon/library · voice assistant
(TTS, wake-word, speaker ID, STT seam) · edge/IoT cognitive agent · vision/audio
analytics tool · explainable KG/inference service (SPARQL + Datalog + proof
trees + PageRank/Louvain/link-prediction/temporal).

## 10. Enterprise vs consumer

**Enterprise:** auditable, governable agent (hash-chained decision log + plain-
language "why"); domain seed packs (medical, ops_runbook, code_review);
constitution>enterprise>user>system loyalty; privacy-preserving **federated
learning** across business units (DP + secure aggregation + Byzantine
tolerance); multi-tenant via `/switch` and per-cookie web isolation. Fit:
on-prem explainable expert/runbook assistant where black-box LLMs are
disallowed.

**Consumer:** private, offline, on-device companion with a persistent identity
(OCEAN traits, mood, emotion) that learns the individual over time via `/teach`
and `/learn` (URL/file/RSS/dir). Limitation: terse, narrow language today.

---

## 11. Roadmap — where to grow, in priority order

### Tier 1 — unblock the core thesis
1. **Scale the substrate.** Land the NOVA enhancements (`nova-deps.toml #1–#14`):
   true concurrency, sub-ms ticks, million-node pools. Without this the substrate
   thesis stays unproven. *Biggest single lever.*
2. **Enrich language production.** Replace reverse concept→word lookup with a
   richer non-LLM grammar/syntax-planning layer (or a clearly-bounded LLM
   *surface* kept out of cognition) so output stops being telegraphic.
3. **Bootstrap knowledge at scale.** The `/learn` plumbing exists; add large
   trusted-corpus ingestion + tier-aware provenance so the seed grows from
   hundreds to millions of atoms.

### Tier 2 — close documented seams
4. **Real TLS transport** for `internet_fetch` (currently a seam).
5. **Harden secure-aggregation DH** to match the rest of the crypto stack
   (RFC 7919 Group 14, CSPRNG, order-q generator) — remove the MVP-crypto
   inconsistency.
6. **Wire the STT input bridge** and roll KG-sync into the daemon's idle path.
7. **Cross-modal grounding.** Promote `perception/sensor_fusion` from primitive
   to a live driver binding perception to the concept layer.

### Tier 3 — measurement & robustness
8. **Capability benchmarks** (reasoning accuracy, learning retention, task
   success) alongside the existing mechanics tests.
9. **Hardened toolchain + CI** that builds and runs the suite on every push, so
   "green" is reproducible, not asserted.
10. **Higher-resolution clock** and a vetted fixed-point numerics library to lift
    real-time pacing and similarity-math constraints.

---

*Bottom line:* an unusually disciplined, genuinely-implemented, philosophically-
coherent attempt at a transparent, continually-learning, safety-first cognitive
substrate — strongest exactly where LLMs are weakest. Its decisive risks are
unproven scale and shallow language/knowledge; its decisive opportunities are
scaling the substrate and enriching language production while keeping cognition
LLM-free.
