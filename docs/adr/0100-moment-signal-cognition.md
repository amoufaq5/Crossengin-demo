# ADR-0100: Moment-Signal Cognition (MSC) — the named cognitive architecture

## Status

Proposed

## Date

2026-08-15

## Context

CrossEngin has, through 99 prior ADRs, assembled a coherent alternative
to transformer-based large language models: labeled atoms with Bayesian
belief, source-attributed observations, per-KG grouping, kernel-checked
formal derivation, cross-KG empirical consistency, retract/cascade/undo,
meta-observer source-atrophy tracking, and a truth-seeking chat loop.
Each piece has its own ADR (0006 nodes, 0007 synapses, 0008 signals,
0014 no-LLM cognition, 0016/0023 belief + multi-KG, 0043 audit log,
0050 meta-observer, 0088 kernel, 0092 governance).

What has NOT existed is a single **name** for the whole approach or a
one-page contract that says "here are the four primitives, here's how
they compose, here's what makes MSC different from a transformer LLM
at the architectural level." External readers see "CrossEngin, a NOVA
reasoning engine" and cannot tell whether that means "yet another LLM
variant," "expert system," "knowledge graph tooling," or "genuinely
different family." The gap is a documentation gap, not a code gap —
the primitives all exist and are tested; they just haven't been named
as a coherent architecture.

This ADR closes that gap. It names the architecture **Moment-Signal
Cognition (MSC)** and defines the four load-bearing primitives every
downstream layer (Capsules ADR-0106, Persona ADR-0102, Skills ADR-0103,
NL ADR-0104) will compose over. Nothing in the codebase changes; this
is a naming + contract ADR that gives future contributors a stable
vocabulary and gives external readers a one-page answer to "what IS
this thing?"

## Decision

We adopt **Moment-Signal Cognition (MSC)** as the canonical name for
CrossEngin's cognitive architecture. MSC is defined by four primitives
and one hard commitment.

### The four primitives

1. **Node** — an addressable unit of knowledge with a stable label, a
   kind (`ATOM_FACT`, `ATOM_CONCEPT`, `ATOM_RELATION`, `ATOM_SKILL`,
   `ATOM_LANG`, `ATOM_RULE`), and a Bayesian belief pair
   `(alpha, beta)` in milli. Implemented today as an atom in
   `src/kg/atom_store.nova`. Nodes are inspectable, named, and live
   in per-domain knowledge graphs.

2. **Signal** — a single observation that shifts a node's belief.
   Every signal carries a source tag (`src:pack:medical`,
   `src:paper:doi:...`, `src:extractor:llm:MODEL:RUN`,
   `src:user:owner`) and a sign (+1 supports the node, -1
   contradicts). Implemented today as `bel_observe` in
   `src/kg/atom_store.nova`. Signals are the *only* mechanism by
   which belief moves.

3. **Moment** — a timestamped cluster of nodes that fire (get
   attended to, get observed, or participate in a derivation)
   together. Moments give the architecture a time axis without a
   context window: a node's activation state at moment T is preserved
   in the moment stream (`src/kg/temporal.nova`, `ms_new()`); a
   subsequent moment can reactivate a prior moment's cluster by
   label match, enabling long-range association without the quadratic
   attention cost.

4. **Attribution** — every signal and every derivation is traceable
   backwards through source tags and (for FORMAL derivations) through
   the kernel proof chain. Implemented today via
   `src/parts/meta/meta_observer.nova` (per-source atrophy tracking)
   and `src/parts/reasoning/multi_kg_consistency.nova` (cross-source
   conflict surfacing). Attribution is not optional — an atom without
   a source tag cannot enter a KG through the normal ingest path.

### The hard commitment

Every belief update in MSC is a **signal from a source, at a moment,
reshaping a node**. No hidden weight matrix. No trained-in patterns.
No autoregressive prediction. This commitment, formalized in ADR-0014
(no-LLM cognition), is what makes CrossEngin's outputs
source-attributed, retractable, and kernel-verifiable at the same
time as being cheap to compute (CPU-only, sub-quadratic with the
label hash-index landed R44).

### Where MSC contrasts with transformer LLMs

| Aspect | MSC | Transformer LLM |
|---|---|---|
| Base unit | atom = label + `(α, β)` | token = embedding vector |
| Update rule | one signal → one Bayesian shift | trillions of gradient steps |
| Memory | inspectable atoms in RAM | opaque weight matrices |
| Attribution | every belief traces to a `src:*` tag | none — patterns trained-in |
| Inference | KG walk + kernel proof or belief aggregation | autoregressive token prediction |
| Contradictions | first-class events (`/consistency`, `/kg_consistency`) | silently blended in weights |
| Correction | `/retract LABEL` + cascade + audit log | retrain, filter, or hope |
| Compute | CPU-cheap, sub-quadratic | GPU-heavy matmul, quadratic in context |

MSC is not "a smaller LLM" or "an LLM with a knowledge graph attached."
It is a **different family** of cognitive architecture in which every
belief has provenance, every disagreement is preserved, and every
retraction is auditable. Transformers optimize for fluent breadth at
the cost of trust per unit of content; MSC optimizes for trust per
unit at the (accepted) cost of fluent breadth.

## Options Considered

1. **Skip naming entirely; let external readers infer from module
   docstrings.** Cheap. Rejected: without a name, MSC is invisible in
   any discussion that isn't a code walk-through. "CrossEngin uses
   MSC" is a sentence a reader can search for; "CrossEngin has some
   atoms and beliefs and a kernel" is not.
2. **Name it "Node-Signal Reasoning (NSR)".** Considered. Rejected:
   omits the temporal / moment axis that the moment stream and the
   activation-decay lifecycle actually provide.
3. **Name it "Bayesian Node Networks (BNN)".** Rejected: collides
   with an established ML term (Bayesian neural networks), which are
   a different thing.
4. **Name it "Moment-Signal Cognition (MSC)" (CHOSEN).** Captures
   the three axes actually implemented: symbolic nodes (structure),
   sourced signals (learning), moments (time). "Cognition" signals
   that this is a full architectural family, not a subroutine.

## Consequences

- **Positive:** External readers get a one-word answer for "what is
  this?" — MSC. Every downstream ADR (Capsules, Persona, Skills, NL)
  can reference MSC's four primitives without re-derivation. The
  contrast table with transformers is definitive and cited-back-to-
  here from any doc that needs it.
- **Positive:** Contributors have a common vocabulary — "this is an
  MSC signal, not a proposal to fine-tune"; "this atrophy is
  attribution-driven, not a training artifact."
- **Neutral:** Zero code changes. Every module docstring stays valid.
- **Negative:** Adopting a new name introduces migration cost in
  external docs (README, MANUAL.md, docs/USING.md) — one-off edit
  linking each mention of "the cognitive architecture" back here.
- **Future work:** ADR-0106 (Capsules) is the first downstream layer
  built explicitly ON TOP of MSC's four primitives. ADR-0102
  (Persona), ADR-0103 (Skills), ADR-0104 (NL) follow, each declaring
  MSC as their base.

## Implementation Notes

**This is a documentation-only ADR.** No new code is written; no
existing code changes. Deliverables:

1. This ADR file (`docs/adr/0100-moment-signal-cognition.md`).
2. One-liner in `README.md` naming MSC.
3. One-liner in `MANUAL.md` cross-linking to this ADR.
4. Section in `docs/USING.md` (§0) naming MSC with a link.
5. Updates to `NEXT_SESSION.md` recording R45 kickoff.

**Vocabulary for downstream ADRs and code:**

- "Node" (or "atom" — both spellings are canonical; module code uses
  `atom_*`, prose uses "node")
- "Signal" (or "observation" — code uses `bel_observe`)
- "Moment" (code uses `ms_*` / moment_stream)
- "Attribution" (code uses `src:*` tags + `mo_*` meta-observer)
- "Kernel derivation" for FORMAL proofs (kernel is
  `src/agent/formal_chat.nova` LCF-discipline layer)
- "Belief aggregation" for EMPIRICAL cross-source reconciliation

**Terms we DO NOT use** (to keep MSC distinct from transformer
vocabulary):

- No "training" — MSC learns via signals, not gradient descent. Use
  "ingest" or "observe."
- No "inference" as a synonym for "answer generation" — MSC's
  inference means kernel derivation. Use "query" or "answer" for the
  user-facing path.
- No "context window" — MSC's temporal analog is the moment stream,
  which is persistent, not sliding.
- No "hallucination" — MSC's failure mode is *silence* on unknown
  labels or *low-belief report*, both auditable.

DEPENDS ON: ADR-0006 (node design), ADR-0007 (synapse design),
ADR-0008 (signal taxonomy), ADR-0014 (no-LLM cognition),
ADR-0016 (multi-KG organization), ADR-0023 (Bayesian belief),
ADR-0043 (audit log), ADR-0050 (meta-observer), ADR-0088 (kernel).
FEEDS INTO: ADR-0101 (data acquisition), ADR-0102 (persona),
ADR-0103 (skills), ADR-0104 (NL surface), ADR-0105 (sandbox
architecture), ADR-0106 (capsules).

## Role in the Model Substrate

MSC is the substrate every one of the five consumption modes runs on
— mother-daemon-direct, per-user selective-load, baked-child,
client-app, and embedded — because "the model" IS the composition of
MSC primitives, not a shape sitting above them.

MSC defines the reasoning triad itself: **nodes** are the addressable
knowledge (KG atoms with belief), **signals** are the source-tagged
moment-stamped observations that move belief, and both together are
walked and re-observed inside the **cognitive sandbox** (the mind
where learning, agent production, and answering happen — a distinct
concept from ADR-0105's access-control sandbox). Everything else in
ADR-0200's factory frame — capsules, personas, skills, patterns,
styles, the NL surface, the bake/deploy path — is a layer over these
three components. The LLM-free primary NLP path (ADR-0104 grammar +
HDC + templater) works precisely because MSC's answers are already
symbolic node walks; the sidecar LLM (ADR-0201 in the new series) has
nothing it must generate from scratch, only phrase.

**See also:** ADR-0200 (AI-factory frame that MSC is the substrate
for), ADR-0202 (cognitive sandbox — the runtime side of the triad),
ADR-0211 (LLM-free NLP primary path built on MSC's node walks),
ADR-0201 (sidecar LLM adapter that never touches the MSC reasoning
path).
