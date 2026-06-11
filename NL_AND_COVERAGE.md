# CrossEngin Non-LLM Coverage, Fluency, Common-Sense & Simulation Roadmap

> **Purpose.** Execution-ready, **strictly non-LLM** techniques to close the four
> capabilities CrossEngin is weakest at: **breadth/coverage**, **language
> fluency**, **common sense + analogy**, and **simulation for problem-solving +
> agentic work**. No transformers, no gradient descent, no token sampling.
>
> **Companion docs.** `ENHANCEMENTS_ROADMAP.md` (P1–P5 capability plan) and
> `LAYER_EXPANSION.md` (substrate primitives L0–L3). This file is the
> language/knowledge/reasoning layer those two build toward.
>
> **Honest framing up front.** Without an LLM you do NOT fully close these gaps.
> Realistic ceilings:
>   - Breadth: broad factual/relational coverage; misses the implicit 95%.
>   - Fluency: clear & grammatical, NOT native/creative. (The gap that stays.)
>   - Common sense / analogy: **genuinely strong** — symbolic AI's home turf.
>   - Problem-solving / agentic: **competitive in formalizable domains**.

---

## THE SINGLE HIGHEST-ROI ACTION

**Bulk-import Wikidata + ConceptNet + WordNet before building any extraction
machinery.** It simultaneously fixes breadth (C1), injects common sense (X1),
and gives the reasoning/sim layers rich material — with zero scraping, zero
extraction, zero LLM. Do this first. Everything else compounds on top of it.

---

## SECTION C — Breadth & Coverage

Avoid the trap: do NOT scrape breadth one triple at a time (recall ceiling).
Import breadth that already exists in structured form, then grow autonomously.

### C1 Bulk-import curated knowledge bases  *(highest ROI)*
Build importers under `src/data/` mapping each public dump → atom/edge schema
with provenance + source-authority weight (ADR-0029):
- **Wikidata** — 100M+ entities; the world-knowledge backbone.
- **ConceptNet** — 34M commonsense edges (also feeds Section X).
- **WordNet** — synonyms / hypernyms / senses → fixes synonym + word-sense gap.
- **Wiktionary** — definitions + morphology, multilingual → fixes English-only.
- **DBpedia**, **UMLS** (medical — pairs with `medical_pack`), **Cyc/OpenCyc**.
- New modules: `src/data/import_wikidata.nova`, `import_conceptnet.nova`,
  `import_wordnet.nova` (shared `kb_import_core.nova` for dedup + entity-link).
- **Accept:** N-million atoms imported with provenance; synonym query resolves
  via WordNet; spot-check facts against source.

### C2 NELL-style never-ending learning
- Bootstrap from seed facts + extraction patterns → extract new facts → learn
  new patterns → iterate, with confidence + self-consistency gates.
- Drive target selection from `XSIG_CURIOSITY` toward coverage gaps.
- New: `src/learning/never_ending.nova`.
- **Accept:** runs unattended for K cycles, net-positive precision maintained.

### C3 Densify via inference (coverage compounds from same data)
- Reuse `rule_inference` (forward-chain), `link_prediction` (Adamic-Adar),
  `cross_kg_references` (federate domain KGs).
- Every imported fact multiplies: rules derive, link-pred fills, xref federates.
- **Accept:** derived-atom count grows measurably from a fixed import.

### C4 Distant supervision + Hearst patterns (text, when needed)
- High-precision lexical patterns ("X such as Y, Z" → `Y isA X`) to bootstrap;
  hand off to OpenIE (ENHANCEMENTS P3) for recall.
- **Accept:** pattern precision > threshold on a labeled sample.

---

## SECTION F — Language Fluency

Honest: classical NLG → "grammatical & clear," not "native." Still a large step
up from `_smq_template_triple`. This is a SOLVED engineering problem.

### F1 Reiter-Dale NLG pipeline (the architecture)
```
content selection → document planning → microplanning → surface realization
  (which atoms)      (order/structure)   (lexical choice,   (grammar, morphology,
                                          aggregation,        agreement, tense)
                                          referring exprs)
```
- New: `src/language/nlg_pipeline.nova` orchestrating the four stages.
- Today's templates are only the last inch done crudely — build the rest.

### F2 Surface realizer (SimpleNLG-style)
- Reimplement SimpleNLG core: morphology, subject-verb agreement, tense,
  pluralization, articles. New: `src/language/realizer.nova`.
- **Accept:** generates agreement-correct, tense-correct varied sentences from
  a structured spec (unit tests on agreement/plural/tense).

### F3 Construction Grammar — a "constructicon"  *(deep, well-aligned)*
- Treat language as learned form-meaning pairs ("constructions") stored as
  atoms. Mine recurring n-gram/phrase patterns from the ingested corpus →
  construction-atoms `{form_template, meaning, frequency}`.
- Generation = select constructions matching the meaning to express.
- Non-neural, learnable from corpus, fits the atom model exactly.
- New: `src/language/constructicon.nova`.
- **Accept:** mined constructions reproduce held-out corpus phrasing above
  template baseline.

### F4 N-gram fluency re-ranking (corpus-driven naturalness, no gradient)
- Build an n-gram model by COUNTING over ingested text (frequency tables).
- Generate several candidate realizations → score by n-gram probability → pick
  most fluent. New: `src/language/ngram_lm.nova`.
- **Accept:** reranking prefers the human-natural candidate on a test set.

### F5 Microplanning details
- **Aggregation** ("X is red. X is fast." → "X is red and fast").
- **Referring expressions** (pronouns / definite descriptions — extend R75 anaphora).
- **Lexical choice** via HDC similarity (best-fitting word for context).
- **Accept:** aggregation + pronoun substitution fire correctly on examples.

---

## SECTION X — Common Sense & Analogy

The strongest non-LLM area — rich pre-neural literature; HDC is a native analogy
engine. Most likely part of the plan to be competitive with an LLM.

### X1 Import a commonsense KB
- **ConceptNet** (the implicit knowledge you lack: "coffee is hot", "rain → wet").
- **Cyc / OpenCyc** — decades of hand-coded common sense + inference engine.
- (Covered mechanically by C1 importers; called out here for purpose.)
- **Accept:** commonsense query ("is coffee hot?") answered from imported edges.

### X2 Structure-Mapping Engine (SME)  *(classical analogy)*
- Gentner's Structure-Mapping Theory: map RELATIONAL structure between domains
  ("atom : nucleus :: solar system : sun") by aligning relations, not surface.
- New: `src/parts/reasoning/analogy_sme.nova`.
- **Accept:** maps a known cross-domain analogy; recovers corresponding roles.

### X3 HDC vector analogy (free with P1)
- Proportional analogy via bind/unbind: `king ⊗ male⁻¹ ⊗ female ≈ queen`.
- Combine: SME for structural analogy, HDC for fast associative analogy.
- **Accept:** proportional-analogy vector query returns the right atom.

### X4 Qualitative reasoning (naive physics, Forbus)
- Reason about the physical world qualitatively ("tip the glass → water spills")
  without numbers. Common sense about the physical world; feeds Section S.
- New: `src/parts/reasoning/qualitative.nova`.
- **Accept:** predicts qualitative outcome of a simple physical scenario.

### X5 Scripts / frames (Schank & Abelson)
- Stereotyped event sequences (restaurant script) as schema-atoms; fills in
  unstated steps ("they ordered → they'll pay").
- **Accept:** script fills an omitted step in a narrative.

### X6 Case-based reasoning (plugs into episodic memory)
- Solve a new problem by retrieving the most similar past EPISODE and adapting it
  (`episode_storage`, `moment_stream`). Common sense as "what worked before."
- **Accept:** retrieves + adapts a prior case to a novel-but-similar problem.

### (also study) Copycat (Hofstadter/Mitchell)
- Fluid analogy via parallel terraced scan; reference for creative analogy.

---

## SECTION S — Simulation for Problem-Solving & Agentic Work

Where the agent THINKS. Almost entirely mature, proven, non-neural classical AI.
Expands `src/sim/world_model.nova` (ENHANCEMENTS P5) into a solving substrate.

### S1 Classical planning (STRIPS / PDDL)
- Actions as `{preconditions, effects}` atoms; search a sequence achieving goal.
- New: `src/parts/reasoning/planner.nova`. Pair with **HTN** for goal
  decomposition (matches `goal_engine`).
- **Accept:** solves a multi-step blocks-world-style problem; plan verified.

### S2 Monte Carlo Tree Search over the world model  *(non-neural)*
- The search half of AlphaGo, no net: roll out imagined action sequences in the
  world model, back up values, pick best. Engine for problems too fuzzy for
  rigid planning; drives reasoning AND agentic action selection.
- New: `src/parts/reasoning/mcts.nova`.
- **Accept:** MCTS beats random + greedy baselines on a toy decision task.

### S3 Physics in the world model
- Qualitative (X4) for common-sense outcomes; quantitative (dimensional atoms
  L0-4 + a CAS/numeric engine) for precise prediction. Enables physical
  problem-solving + robotics modeling.
- **Accept:** predicts a projectile/lever outcome within tolerance.

### S4 Verification-in-the-loop
- `proof_checker` validates candidate solutions; `reversibility_classifier` +
  `constitutional_filter` gate risky actions IN SIM before reality.
- **Accept:** an unsound candidate solution is rejected by the checker.

### S5 Curriculum + self-play (autonomous, non-gradient skill growth)
- Generate progressively harder problems (gated by `competence_tracker`);
  practice in sim; three-factor learning (L3-1) consolidates what works.
- Multi-agent self-play via the federation layer (negotiation/coordination).
- **Accept:** task metric improves across sessions with no human teaching.

### S6 Domain sandboxes for agentic work
- Code-execution sandbox, simulated APIs/filesystem → safe tool practice (P4).
- Every sandbox action returns as a moment → ingested → learned.
- **Accept:** agent completes a sandboxed multi-tool task; failures lower competence.

### The fully non-LLM agentic loop
```
perceive → model state → PLAN (PDDL/HTN) or SEARCH (MCTS) over world_model
  → simulate rollouts (forward_sim) → verify (proof_checker) + safety-gate
  → act (effector) → observe result as new moment → three-factor learning
  → update competence + world model      (repeat)
```

---

## Capability ceilings (set expectations honestly)

| Capability | Non-LLM ceiling | Stack |
|---|---|---|
| Breadth | Broad factual/relational; misses implicit | C1 import + C2 NELL + C3 inference |
| Fluency | Clear & grammatical, not native (gap stays) | F1 pipeline + F2 realizer + F3 constructicon + F4 n-gram |
| Common sense / analogy | **Genuinely strong** | X1 import + X2 SME + X3 HDC + X4 qualitative + X5 scripts + X6 CBR |
| Problem-solving / agentic | **Competitive (formalizable domains)** | S1 PDDL/HTN + S2 MCTS + S3 physics + S4 verify + S5 curriculum |

## Suggested build order
1. **C1** bulk KB import (unlocks everything; do first).
2. **X1–X3** common sense + analogy (strongest payoff; reuses C1 + HDC/P1).
3. **S1–S2** planning + MCTS (problem-solving on the imported knowledge).
4. **F1–F2** NLG pipeline + realizer (make it speak clearly).
5. **C2, S5** never-ending learning + curriculum (autonomous growth).
6. **F3–F4, X4–X6, S3–S6** refinements.

## Cross-cutting (same disciplines as the other roadmaps)
- Every module: `tests/unit/test_<module>.nova` + one integration scenario.
- Provenance + confidence mandatory on every imported/derived atom.
- One ADR per subsystem with an honest-gaps section.
- Mode flags for risky cutovers; keep `make test` green.

## Research lineage (read before building)
- Coverage: Wikidata/ConceptNet/WordNet/Cyc; NELL (Mitchell et al., CMU);
  Hearst patterns (Hearst 1992); distant supervision (Mintz 2009).
- Fluency: Reiter & Dale (NLG architecture); SimpleNLG (Gatt & Reiter);
  Construction Grammar (Goldberg); n-gram LMs (Jelinek).
- Common sense / analogy: Structure-Mapping (Gentner 1983); Copycat
  (Hofstadter & Mitchell); HDC/VSA (Kanerva; Plate HRR); qualitative reasoning
  (Forbus); scripts (Schank & Abelson); CBR (Kolodner).
- Simulation: STRIPS (Fikes & Nilsson); PDDL; HTN (Erol); MCTS (Coulom; Kocsis
  & Szepesvári UCT).

## What this does NOT claim
- These raise the ceilings; they do not reach LLM-level NL or generality.
- Fluency stays visibly behind native; accept "clear & correct" as the win.
- Common-sense/analogy + formalizable problem-solving are where this can
  genuinely compete — focus competitive claims THERE, not on open-ended NL.
