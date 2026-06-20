# ADR-0089: Argumentation + Bayesian adjudication debate engine

## Status

Proposed

## Date

2026-06-15

## Context
ADR-0001 produces answers from spreading activation, and ADR-0031 adds
multi-step reasoning strategies as substrate-adjacent helpers. ADR-0023 tracks a
Beta belief per atom. This is sufficient to answer "what is X" by surfacing the
highest-belief triple, but it is not a *reasoning* engine in the sense ADR-0086
requires: there is no inspectable structure showing *why* a conclusion holds,
*what would defeat it*, and *which competing conclusion the evidence actually
favors*. Those are exactly the questions on which LLMs are unreliable (fluent but
unfaithful chains of thought), and they are the questions a truth-seeking engine
must answer faithfully and out-reason an LLM on.

We need a reasoning layer that is (a) structured and auditable — it yields an
argument graph, not a vibe; (b) capable of handling defeasible knowledge — most
real claims have exceptions and counter-arguments; (c) adjudicated by calibrated
confidence, not by counting; and (d) entirely within the no-LLM line (ADR-0014).
Computational argumentation provides the structure (the ASPIC+ family of strict
and defeasible rules with rebut/undercut/undermine attacks, and Dung's
abstract-argumentation acceptability semantics); the Beta beliefs of ADR-0023
provide the confidence. These methodologies are published theory — unencumbered
— so building them natively in NOVA is both clean (Rule 3) and novel as an
*integrated substrate-native* reasoner.

## Decision
We add a **debate engine** as the answer path for reasoning queries (simple
lookups keep the fast path of ADR-0071). It runs a five-stage pipeline over the
substrate, producing a conclusion, an argument trace, and a confidence:

```
query
  -> (1) retrieval        : HDC/KG spreading activation gathers candidate
                            claims (atoms) and the rules that connect them
  -> (2) construction     : build arguments — trees of strict rules (deductive,
                            truth-preserving) and defeasible rules (hold by
                            default, may be defeated), each leaf an atom with a
                            provenance ledger record (ADR-0087)
  -> (3) attack           : compute attack relations between arguments —
                            REBUT (conclusion vs conclusion), UNDERCUT (attack a
                            defeasible inference step), UNDERMINE (attack a
                            premise atom)
  -> (4) acceptability    : evaluate the argument graph under Dung semantics
                            (grounded for the skeptical default; preferred when
                            multiple coherent positions exist) to find which
                            arguments survive
  -> (5) adjudication      : assign confidence to each surviving conclusion by
                            combining its arguments' premise beliefs (ADR-0023)
                            and evidence grades (ADR-0087) into a Beta posterior
  -> answer + argument trace + confidence
```

**Strict vs defeasible.** Strict rules come from `FORMAL` atoms and logical
identities; an argument built only from strict rules and `FORMAL` premises is a
*proof* and is adjudicated near-certain (ties into ADR-0088). Defeasible rules
carry the everyday "normally/typically" knowledge and are the ones attacks can
defeat.

**Adjudication.** Acceptability (stage 4) decides *which* conclusions are
defensible; Bayesian adjudication (stage 5) decides *how confident* we are in
each. A conclusion that is grounded-accepted with high-grade, high-belief,
mutually corroborating premises gets high confidence; one that merely survives in
some preferred extension among conflicting positions is reported with lower
confidence and, in contested domains, handed to the steelman policy (ADR-0090)
rather than collapsed to a single answer.

**Explainability is the product, not a debug aid.** The argument trace —
arguments, their premises with provenance, the attacks, and which extension each
survived in — is a first-class output, logged to the decision log (ADR-0043) and
renderable to the user on request. This is the faithful "show your work" that
distinguishes the engine from post-hoc LLM rationalization.

**Substrate-native.** Argument construction reads atoms/synapses and writes the
argument graph as substrate structure; it does not orchestrate the substrate from
above (respecting ADR-0001). It is the ADR-0031 reasoning helper grown into a
principled, auditable form.

## Options Considered
- **Highest-belief triple only (status quo, rejected).** No argument, no attack
  analysis, no defeasibility — cannot explain itself or handle exceptions, and
  cannot demonstrably beat LLM reasoning on checkable questions.
- **Pure probabilistic (Bayesian network over atoms) (rejected).** ADR-0023
  already rejected a full Bayes net as intractable at 1M nodes / 100Hz, and a
  pure-probability answer still yields no inspectable argument structure or
  defeat reasoning. Probability is the *adjudicator*, not the whole engine.
- **Pure symbolic argumentation, no probabilities (rejected).** Gives structure
  and explainability but treats every surviving argument as equally good and
  cannot express calibrated confidence or graded evidence (ADR-0087). Brittle on
  noisy real-world knowledge.
- **Argumentation + Bayesian adjudication (CHOSEN).** Symbolic structure for
  defensibility and explanation; Beta beliefs for calibrated confidence;
  grounded/preferred semantics to separate "defensible" from "merely possible".
  More machinery and tuning, but it is the only option that is simultaneously
  auditable, defeasible, calibrated, and inside the no-LLM line.
- **Wrap an LLM as the reasoner (rejected).** Violates ADR-0014; produces
  unfaithful, unauditable chains — the exact failure this engine exists to fix.

## Consequences
- **Positive:** Reasoning becomes structured, defeasible, and auditable, with
  calibrated confidence and a faithful argument trace; the engine can be measured
  against LLMs on the verifiable proving ground (ADR-0093) where its arguments are
  checkable; strict-only arguments degenerate cleanly into proofs (ADR-0088);
  contested questions route to steelmanning (ADR-0090) instead of false certainty.
- **Negative:** Dung acceptability is, in general, computationally expensive
  (preferred-extension enumeration is intractable on large graphs) — we must
  bound argument-graph size per query and prefer grounded (polynomial) semantics
  by default, escalating to preferred only on small contested subgraphs;
  construction + attack computation add real per-query latency versus a lookup;
  several rule/threshold choices need empirical tuning per domain.
- **Future work:** Learn defeasible-rule strengths from outcomes; cache stable
  argument subgraphs as substrate structure; structured-argumentation benchmarks
  vs LLMs on math/logic/CS (ADR-0093, Phase 7); preference orderings over
  arguments learned from source track record (ADR-0029 future work).

## Implementation Notes
- Grow `mind/reasoning.nova` (ADR-0031) into a debate module: `argue(query)`
  returning `{conclusion, confidence, argument_graph}`. Stages map to:
  retrieval over `core/similarity.nova` + HDC (ADR-0051) and synapse spreading;
  construction/attack as substrate graph structure (arguments as node clusters,
  attacks as typed synapses); acceptability as a grounded-extension fixpoint with
  a bounded preferred fallback; adjudication via `core/belief.nova`.
- Bound the working argument graph per query (configurable cap) to keep
  acceptability tractable under the 100Hz tick (ADR-0037, ADR-0003 budget).
- Strict/defeasible rule typing reads `evidence_grade`/`proof_ref` from the
  provenance ledger (ADR-0087); `FORMAL`-only strict arguments coordinate with
  ADR-0088 verification.
- Emit the argument trace to ADR-0043; expose a render path for user-facing
  "show your work". Route low-confidence / multi-extension contested results to
  ADR-0090.
- Testing: a defeasible chain with a known exception (expect the exception's
  undercut to defeat the default conclusion); a strict/`FORMAL` chain (expect a
  near-certain proof-grade answer); a balanced two-sided contested query (expect
  two surviving preferred extensions handed to ADR-0090, not a confident single
  answer); a latency fixture asserting bounded graph size keeps a query within
  tick budget.
- DEPENDS ON: ADR-0023 (Beta adjudication), ADR-0087 (evidence grade/proof ref),
  ADR-0031 (reasoning helper base), ADR-0043 (argument-trace audit), ADR-0051
  (HDC retrieval). No new NOVA enhancement strictly required beyond the existing
  graph/arithmetic primitives; benefits from #4 (batched propagation) for
  large argument graphs.

## Implementation status

**Increment 1 (landed): abstract argumentation + grounded acceptability
(stages 3-4).** `src/parts/reasoning/argumentation.nova` implements the symbolic
core: an argumentation framework `af_new`/`af_attack` (arguments as indices, a
binary attack relation, Dung 1995) and `af_grounded` — the grounded labelling
computed as the least fixed point (an argument is IN iff every attacker is OUT;
OUT iff some attacker is IN; otherwise UNDEC). `af_grounded_extension` returns the
accepted set. This is the skeptical "which arguments survive" stage; it is pure
(builtins only) and exactly testable. Verified via the bootstrap: `argumentation`
suite, 22 checks — single attack (A in, B out), 2-cycle (both UNDEC, empty
extension), reinstatement chain A→B→C (A,C in; B out), self-attack (UNDEC),
unattacked (all in), defense C→B→A (A reinstated), and an unreinstated case (a
surviving second attacker keeps the target OUT).

**Increment 2 (landed): rebut wiring + Bayesian adjudication (stages 3 rebut +
5).** `src/parts/reasoning/debate.nova` binds abstract arguments to claims --
`darg_new(conclusion_id, sign, weight, strict)` -- and turns "which arguments
survive" into "how confident". `debate_build_af` derives the rebut attack
relation (same conclusion, opposite sign), with the ASPIC+ asymmetry that a
*strict* argument (a proof, ADR-0088) defeats a defeasible opponent but is not
rebutted back. `debate_decide` builds the AF, runs `af_grounded`, and
`debate_adjudicate` combines only the surviving (IN) arguments into a Beta
posterior (each supporting IN argument adds to alpha, each opposing to beta,
weighted by evidence mass derived upstream from belief x grade, ADR-0023/0087).
An unresolved rebut cycle leaves the claim at the prior 0.5 and is flagged by
`debate_is_contested` -- the signal ADR-0090 steelmans rather than collapsing.
Verified via the bootstrap: `debate` suite, 9 checks (single support 0.666, two
supports 0.75, single against 0.333, contested rebut 0.5 + flagged, strict
defeats defeasible both directions).

**Increment 3 (landed): argument construction from atoms (stages 1-2) -- the
full pipeline on the real KB.** `construct_arguments(rkg, target_id)` builds the
debate arguments for a claim from the reasoning KG: each operator concluding the
target is an argument FOR it, an oppositional operator (ROP_OPPOSITE) is an
argument AGAINST, and each argument's weight and strictness come from its PREMISE
atom -- `arg_weight_from_atom` = premise confidence (ADR-0023) x grade weight
(ADR-0087 increment 3), with FORMAL premises given a heavy fixed mass; `arg_strict
_from_atom` sets the strict flag from a FORMAL grade (ADR-0088). `debate_atom(rkg,
target_id)` then runs the whole pipeline (construct -> rebut AF -> grounded ->
adjudicate), so the engine reasons over actual atoms, not synthetic inputs.
Verified via the bootstrap: `debate` suite now 16 checks -- a strong empirical
premise -> 0.6, a FORMAL premise -> ~0.99, two clashing defeasible studies ->
contested 0.5 (flagged for ADR-0090), and a strict proof defeating defeasible
doubt -> ~0.99 resolved.

**Scope still open:** undercut/undermine attacks (attacking an inference step or a
premise, beyond rebut); preferred semantics for multi-extension contested cases
(→ ADR-0090); the first-class argument trace to the decision log (ADR-0043); `debate_verdict_for` is now wired as the real ADR-0092 promotion gate (f) --
a candidate promotes only if its argument wins the debate (inc 4 of ADR-0092).

**Increment 4 (landed): the argument trace (explainability).** `debate.nova` now
emits a first-class, auditable trace -- `debate_trace_build` / `debate_atom_trace`
record the claim, the arguments, their attacks, the grounded labelling (IN/OUT/
UNDEC per argument), the adjudicated confidence, and the contested flag, with
accessors (`debate_trace_confidence` / `_contested` / `_label` / ...).
`debate_trace_render` produces human-readable "show your work" text, e.g.:

```
Debate on claim #0:
  arg0 FOR (strict-proof, weight 99000) -> IN
  arg1 AGAINST (defeasible, weight 125) -> OUT
  => confidence 990
```

This is the faithful, re-checkable explanation that distinguishes the engine from
post-hoc LLM rationalization. Verified via the bootstrap: `debate` suite now 34
checks (trace structure for contested / proof-wins cases + the rendered output).

**Increment 5 (landed): undermine attacks.** `debate_build_af` now also derives
UNDERMINE edges (ADR-0089 stage 3): an argument is defeated by refuting the
*premise* it rests on, not only by rebutting its conclusion. A `darg` carries its
premise atom (`DARG_PREMISE`); B undermines A iff B concludes A's premise while
arguing against it. `construct_arguments` sets each argument's premise from the
operator. Verified via the bootstrap: `debate` suite 37 checks -- an argument
whose premise is refuted goes OUT and its claim falls to the prior, with rebut /
construction / trace / closed-loop unchanged.

**Increment 6 (landed): preferred semantics.** `argumentation.nova` adds
`af_preferred_extensions` -- the maximal admissible sets (Dung's credulous
semantics), the distinct *coherent positions* a framework admits where the
skeptical grounded extension is undecided. A 2-cycle A<->B (empty grounded) yields
two positions {A} and {B}; a 4-cycle yields {A,C} and {B,D}. `af_num_positions`
counts them. This is the multi-extension input ADR-0090 steelmans -- each
preferred extension is one defensible side. Bounded (PREF_MAX_ARGS=16, else
grounded fallback) since enumeration is exponential. Verified via the bootstrap:
`argumentation` suite 37 checks (2-cycle/4-cycle multi-position, single, unattacked,
self-attack).

**Increment 7 (landed): undercut attacks -- the ASPIC+ attack triad is complete.**
A `darg` carries its inference/rule (`DARG_RULE`, the operator id);
`debate_build_af` adds UNDERCUT edges symmetric with undermine -- B undercuts A
iff B concludes that A's RULE is inapplicable (argues against the rule id) -- with
the asymmetry that a STRICT inference (a proof, truth-preserving) cannot be
undercut. `construct_arguments` sets each argument's rule from its operator.
Stage 3 now covers all three ASPIC+ attacks: REBUT (conclusion), UNDERMINE
(premise), UNDERCUT (inference). Verified via the bootstrap: `debate` suite 42
checks -- an undercut defeasible argument goes OUT and its claim falls to the
prior, while a strict (proof) argument is immune to undercut and stays ~0.99.

**Increment 8 (landed): provenance in the trace.** `debate_trace_render_prov`
(and `debate_atom_trace_render_prov`) render the argument trace WITH each
argument's provenance chain -- its premise atom + evidence grade and the source
rule it argues through -- realizing ADR-0089's "premises with provenance".
`_darg_prov_str` resolves the premise/rule atom ids in the KG. Sample:
`arg0 FOR: aspirin [empirical_strong] via src:wikipedia -> IN`. Verified:
`debate` suite 46 checks.

**Increment 9 (landed): traces persist to the decision log.**
`src/parts/reasoning/decision_record.nova` writes a debate trace (and a steelman
position-set, and a governed-promotion outcome) as one immutable, hash-chained
`DLK_DECISION` entry in the ADR-0043 append-only log: claim id, adjudicated
confidence, contested flag, the premise atom ids weighed, and an OK/VETOED
outcome. So a debate is now auditable after the fact and survives a restart —
`drec_render` reconstructs it in plain language with no LLM (ADR-0014/0038). See
ADR-0043's Implementation Status. Verified: `decision_record` 33 checks.

**Increment 10 (landed): the answer path routes contested claims through the
steelman.** `src/language/nl_query.nova` adds a `NLQ_CONTESTED` answer form; a
yes/no or why claim with both supporting and opposing evidence runs through
`construct_arguments` -> `debate_is_contested` and, when contested, returns
`steelman_render` of every surviving position instead of collapsing to a
single-edge verdict. See ADR-0090's Increment 3. Verified: `nl_contested` 14
checks.

**Scope still open:** the proof-checker kernel (ADR-0088) feeding strict
arguments; benchmarking the adjudicator against LLM judgments (ADR-0093 Phase
7).
