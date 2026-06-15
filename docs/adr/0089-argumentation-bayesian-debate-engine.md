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
