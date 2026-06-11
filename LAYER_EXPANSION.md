# CrossEngin Layer 0–3 Expansion Roadmap

> **Purpose.** Execution-ready specs for expanding the four substrate units —
> **atom (L0)**, **moment (L1)**, **signal (L2)**, **synapse (L3)** — from thin
> records into a rich, self-organizing, moment-signal learning system.
>
> **Companion docs.** Read `ENHANCEMENTS_ROADMAP.md` first (P1–P5 capability
> plan). This file deepens the *substrate primitives* those phases build on.
>
> **Design invariant (unchanged).** No tokenization-as-LLM, no global
> backprop, no offline training run. Everything local, online, gradient-free,
> auditable. Every atom carries provenance + confidence.
>
> **Research lineage.** Predictive coding (Rao & Ballard; Friston); three-factor
> plasticity (Frémaux & Gerstner); STDP (Bi & Poo); HDC/VSA (Kanerva; Plate HRR);
> activation decay (ACT-R, Anderson); subjective logic (Jøsang); metaplasticity
> (Abraham & Bear); homeostatic scaling (Turrigiano).

---

## Highest-leverage subset (build these first)

If resources are limited, these four unlock the most and form the core loop:

1. **L0-1** multi-facet HDC embeddings — cross-modal grounding (keystone).
2. **L2-1 + L2-2** bidirectional predict/error streams + neuromodulator bus.
3. **L3-1 + L3-3** three-factor/eligibility/STDP + structural plasticity.
4. **L1-4 + L1-5** real-vs-imagined tagging + causal moment links.

Everything else is high-value refinement layered on after the loop runs.

---

## LAYER 0 — Atom: rich representation

**Current:** `{id, label, kind, embedding(8d), confidence, provenance, edges}`.
**Touches:** `src/kg/atom_store.nova`, `concept_layer.nova`, `schemas.nova`.

### L0-1 Multi-facet HDC embeddings  *(keystone)*
- One atom → several D=10k HDC vectors: `SEMANTIC`, `PHONETIC`
  (`language/phoneme_atoms`), `VISUAL` (vision stack), `STRUCTURAL` (graph pos).
- Extend `concept_layer.nova` facet vectors (multi-facet already exists).
- New: `atom_facet_vec(atom, facet)`, `atom_facet_cosine(a, b, facet)`.
- **Unlocks:** "car"≈"automobile" (semantic), "kar" (phonetic), car-image (visual).
- **Accept:** cross-facet retrieval test; semantic facet > 700 for synonyms.

### L0-2 Confidence as a distribution (subjective logic)
- Replace scalar `confidence` with `{belief, disbelief, uncertainty}` (sum=1000).
- Update `query.nova` + R71–R75 belief code to carry the triple.
- **Unlocks:** "no idea" (high uncertainty) distinct from "conflicting"
  (high belief AND disbelief). Honest reasoning + graceful degradation.
- **Accept:** unknown atom → uncertainty≈1000; contradiction → belief+disbelief high.

### L0-3 Temporal validity
- Add `valid_from` / `valid_to` per fact-atom; wire to `temporal.nova` (Allen).
- **Unlocks:** facts that change over time ("X is CEO of Y" in an interval).
- **Accept:** query at time T returns only valid-at-T facts.

### L0-4 Quantitative / dimensional atoms
- New kind `QUANTITY`: `{magnitude, unit, dimension}`. New `src/data/units.nova`
  for unit algebra (m/s² etc.).
- **Unlocks:** physics, math, measurement reasoning (prerequisite for "learn physics").
- **Accept:** "9.8 m/s²" parses to a QUANTITY; unit-consistent arithmetic test.

### L0-5 Compositional / hierarchical atoms
- An atom's embedding = HDC `bundle` of its sub-atoms (recursive composition).
- New: `atom_compose(parts)` → composite atom; `atom_decompose(a)` (unbind probe).
- **Unlocks:** "red car" = "red" ⊗ "car", queryable; true compositionality.
- **Accept:** decompose recovers parts above noise threshold.

### L0-6 Activation state + decay (ACT-R)
- Per-atom `base_activation` that decays with time, rises with use/recall.
- **Unlocks:** recency/frequency effects, attention focus, soft forgetting.
- **Accept:** unused atom's activation decays; recalled atom's rises.

### L0-7 Procedural (skill) atoms
- Skill-atoms carry an executable body (plan/effector sequence) + competence.
- Extend `skills_kg.nova` + `competence_tracker.nova`.
- **Unlocks:** the agentic tooling layer (ENHANCEMENTS P4).
- **Accept:** a skill-atom executes; competence updates on outcome.

---

## LAYER 1 — Moment: structured experience

**Current:** `{timestamp, active_atoms[], salience, source_signals[]}`.
**Touches:** `src/parts/episodic/moment_stream.nova`, `episode_storage.nova`,
`consolidation.nova`.

### L1-1 Multi-scale temporal hierarchy
- micro-moment (tick) → episode (bounded event) → arc (goal-spanning sequence).
- **Unlocks:** reasoning across timescales (this second vs this project).
- **Accept:** arc groups its constituent episodes; roll-up query works.

### L1-2 Moment embeddings
- HDC-`bundle` active atoms → one **moment hypervector**.
- **Unlocks:** episodic retrieval by similarity; prediction target for L2/P2.
- **Accept:** similar moments cosine-cluster; nearest-moment recall test.

### L1-3 Situational frame / context
- Tag each moment `{where, who, active_goal, modality}`.
- **Unlocks:** context-dependent recall and reasoning.
- **Accept:** same atom recalled differently under different frames.

### L1-4 Real-vs-imagined tagging  *(core-loop)*
- Moment flag: `PERCEIVED | RECALLED | IMAGINED` (from `dream_recombination`,
  `forward_sim`).
- **Unlocks:** Forward-Forward positive/negative pairs; safe planning (imagined
  chains not confused with reality).
- **Accept:** imagined moments excluded from belief updates; FF uses them as neg.

### L1-5 Causal moment links  *(core-loop)*
- Edge between moments: "A led to B" (with confidence).
- **Unlocks:** learning dynamics → reasoning-about-the-world; consequence prediction.
- **Accept:** after repetition, predict B from A above chance.

### L1-6 Affective stamping
- Each moment carries valence/arousal from `emotion/appraisal`.
- **Unlocks:** affective memory ("that felt bad"); supplies the L3 neuromodulator.
- **Accept:** reward-paired moment raises later selection of its actions.

---

## LAYER 2 — Signal: a modulated nervous system

**Current:** 18 typed signals, priority-bucketed O(10) dispatch.
**Touches:** `src/substrate/signal_dispatch.nova`, `gate_router.nova`.
**Rule:** do NOT inflate the 18-type taxonomy; expand *dynamics*, not type count.

### L2-1 Bidirectional predict/error streams  *(core-loop)*
- Make PREDICT (top-down) and ERROR (bottom-up) an explicit matched pair flowing
  opposite directions through the same routes.
- **Unlocks:** real predictive coding — the engine of learning (P2).
- **Accept:** top-down prediction cancels matching bottom-up input (error→0).

### L2-2 Neuromodulatory broadcast bus  *(core-loop)*
- A *global* low-dim signal (reward / mood / attention-uncertainty) every synapse
  reads — distinct from point-to-point signals.
- **Unlocks:** the third factor in three-factor learning; explore/exploit switch.
- **Accept:** raising reward scalar globally biases plasticity sign.

### L2-3 Oscillatory / phase binding
- Give `XSIG_BIND` a phase; atoms firing in-phase bind into one percept.
- **Unlocks:** the **binding problem** — which active atoms belong together.
- **Accept:** two overlapping objects separate by binding phase.

### L2-4 Gain / gating modulation
- `XSIG_ATTEND` boosts, `XSIG_INHIBIT` suppresses routes dynamically.
- **Unlocks:** attention — focus compute on the relevant subgraph (scaling).
- **Accept:** attended subgraph processed; unattended down-weighted.

---

## LAYER 3 — Synapse: adaptive structure

**Current:** sparse signed typed weighted graph, two-factor Hebbian.
**Touches:** `src/substrate/synapse_graph.nova`, `resonance_engine.nova`,
atom birth/death (ADR-0025).

### L3-1 Three-factor + eligibility + STDP  *(core-loop)*
```
Δw_ij = pre_i × post_j × neuromod(reward, error, surprise)
      + eligibility_trace (delayed reward)
      + STDP asymmetry (A-before-B > B-before-A, from moment timestamps)
```
- **Unlocks:** credit assignment without backprop; delayed-reward; temporal causality.
- **Accept:** learns a delayed-reward association pure Hebbian cannot.

### L3-2 Dual-timescale weights
- Each edge: `fast_w` (short-term, decaying — working memory) + `slow_w`
  (long-term, stable).
- **Unlocks:** one-shot working memory + durable consolidation, no overwrite.
- **Accept:** fast_w decays within N ticks; slow_w persists across snapshot.

### L3-3 Structural plasticity (grow/prune)  *(core-loop)*
- Synaptogenesis: form edges between repeatedly co-firing atoms.
- Pruning: remove long-unused edges. Extend atom birth/death (ADR-0025) to edges.
- **Unlocks:** the graph self-organizes its *topology*, not just weights.
- **Accept:** new edge appears after sustained co-fire; idle edge pruned.

### L3-4 Metaplasticity
- Per-edge learning rate that itself adapts: often-revised edges become stable.
- **Unlocks:** stable core beliefs + flexible periphery; no catastrophic overwrite.
- **Accept:** heavily-reinforced edge resists a single contradicting update.

### L3-5 Homeostatic normalization
- Cap/renormalize total synaptic weight per atom.
- **Unlocks:** stability at scale (guards `failmode_runaway_atom_births`).
- **Accept:** runaway excitation test stays bounded.

### L3-6 Hyperedges (n-ary relations)
- A single edge over several atoms: "X gives Y to Z at T".
- **Unlocks:** event/relational knowledge binary triples can't express; lifts the
  extraction-recall ceiling (ties to ENHANCEMENTS P3 OpenIE).
- **Accept:** an n-ary event round-trips through store + query.

---

## How the layers compound (build the loop, not the parts)
```
L0 multi-facet + compositional atoms  ──► L1 richer moment embeddings
L1 causal moment links                ──► L2 predict/error streams
L2 neuromodulator + phase binding     ──► L3 three-factor + binding
L3 structural plasticity + hyperedges ──► grow new L0 atoms/relations
                                                  │
                                            (closed, self-organizing loop)
```

## Cross-cutting requirements
- Every expansion: `tests/unit/test_<module>.nova` + one integration scenario.
- Mode flags for risky cutovers (embedding mode, confidence-triple) so prior
  tests stay byte-identical until explicit switch.
- One ADR per expansion (continue `docs/adr/`), each with an honest-gaps section.
- Provenance + confidence mandatory on every atom/edge written.

## What this does NOT claim
- These are the *mechanisms* a moment-signal AGI bet requires, not a guarantee of
  general intelligence. Credit assignment without backprop at scale remains open;
  L3-1 uses the best-known local approximations.
- "Affective stamping" / "feel" = functional appraisal for control & motivation,
  not sentience.
