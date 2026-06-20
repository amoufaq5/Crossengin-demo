# ADR-0090: Contested-domain steelman policy (represent every evidenced position at its strongest, never average into false certainty)

## Status

Proposed

## Date

2026-06-15

## Context
The truth-seeking architecture (ADR-0086) commits CrossEngin to four reasoning axes, and axis D — handling of genuinely contested questions — is the one that most sharply distinguishes us from an LLM. In domains like politics, economics, ethics, and parts of medicine and nutrition, there is no single fact to retrieve: there are multiple internally-coherent positions held by serious people, grounded in different premises and different values. The dominant failure mode of generative systems is to flatten this into one confident-sounding answer (or one trained-in opinion), which is both epistemically wrong and corrosive to user trust. We have already built the substrate pieces that *detect* this — Beta beliefs that flag CONTESTED state (ADR-0023) and a Dung-style argumentation engine that yields multiple surviving preferred extensions (ADR-0089) — but we have no decision governing what the engine *does* with that detection at output time. This ADR is that output discipline.

This matters now because ADR-0093 schedules the contested social/economic/political domains for later rollout, and the debate engine (ADR-0089) is the immediate predecessor in the chain: when its grounded/preferred-extension computation leaves more than one coherent extension standing, it explicitly hands off to "the contested-domain policy." That handoff target is this document. We must define the policy before those domains ship, or the engine will reach a contested verdict and have no principled, auditable way to render it. The constraint, as always, is a small bootstrapped team, NOVA-everywhere (Rule 1: no third-party deps), and no-LLM cognition (ADR-0014) — so this is a deterministic renderer over an existing argument graph, not a learned "balance" model.

The central tension is between two forms of dishonesty we must avoid simultaneously. The first is **false certainty**: picking the highest-confidence position and asserting it as the answer, hiding the live disagreement. The second is **false balance**: presenting a fringe or factually-refuted claim as the equal of a well-corroborated consensus simply because two "sides" exist. A naive steelman policy fixes the first and walks straight into the second. The honest part of this decision is admitting that steelmanning fairly is genuinely hard: deciding what counts as the *strongest* form of a position, and distinguishing a live value disagreement from a settled empirical one, is exactly where bias creeps in. We accept that risk explicitly and constrain it with provenance and evidence-grade weighting rather than pretending it away.

We also draw a hard line that this policy does NOT erase: empirical falsity is not the same as normative disagreement. A position that has been *defeated on the facts* — refuted by FORMAL or EMPIRICAL_STRONG evidence (ADR-0087) and defeated in the argument graph (ADR-0089) — is not steelmanned as a peer of the surviving positions. Steelmanning applies to positions that genuinely survive on the merits, chiefly where the disagreement is about values or premises rather than facts. Mixing these up would make us a both-sides machine, which is its own LLM-adjacent failure.

## Decision
In genuinely contested domains the engine MUST represent every *evidenced, surviving* position with its provenance and confidence, present each at its strongest form ("steelman"), and explain *why* the positions conflict — rather than asserting a single truth or averaging into a confident-looking mean. This is an output discipline layered on top of the existing CONTESTED belief state (ADR-0023) and the multi-preferred-extension result of the debate engine (ADR-0089); it adds no new cognition, only a rendering and gating policy over the argument graph.

- **Trigger (when a query is contested).** A query enters contested-response mode when ANY of: (a) the debate engine (ADR-0089) yields more than one coherent surviving position (preferred extension) above a confidence floor; OR (b) one or more load-bearing atoms in the answer are CONTESTED-flagged per ADR-0023 (`conflict > 0.4` and `belief_strength > 8`); OR (c) the query's domain is tagged contested per ADR-0093 (social/economic/political and the contested medical/nutritional sub-areas). The confidence floor exists so a barely-evidenced fringe extension does not by itself force contested mode.

- **Response format.** Each surviving position is stated at its strongest defensible form, accompanied by: its supporting arguments and the sources behind them (provenance per ADR-0087, including each source's `evidence_grade`), and its confidence/strength (ADR-0023). The engine then reports the *locus of disagreement* — which premises or values the positions differ on — read directly off the ADR-0089 argument trace, so the user sees why reasonable parties diverge, not just that they do.

- **No winner on value-laden disputes.** Where the disagreement is genuinely normative (different values/premises, no factual defeater), the engine does NOT pick a winner. It surfaces the steelmanned positions and the value fork; it may report which position is held by consensus versus minority, but it does not collapse a values question into a verdict.

- **Still rule out the factually refuted.** Where a position has been defeated on the facts in the argument graph (ADR-0089) by FORMAL/EMPIRICAL_STRONG evidence (ADR-0087), it is NOT presented as an equal steelmanned position. The engine reports the supported answer and explicitly notes the refuted claim as refuted. This is the line between contested (steelman all) and settled-but-disputed (answer plus correction).

- **Consensus-vs-minority labeling.** To resist false balance, surviving positions are weighted and labeled by corroboration and evidence grade (ADR-0087): a position carried by many independent EMPIRICAL_STRONG sources is explicitly marked as consensus, a thinly-sourced one as minority. Equal screen space is never equal endorsement, and the rendering must make that explicit.

## Options Considered
- **Pick the single highest-confidence position (rejected).** Simplest to render and reads as decisive. Rejected because it manufactures false certainty in exactly the domains where certainty is unwarranted — this is the LLM failure mode (ADR-0014, ADR-0086 axis D) we exist to avoid. It also throws away the multi-extension result the debate engine (ADR-0089) worked to compute, and silently buries the CONTESTED state ADR-0023 deliberately refuses to collapse.

- **Refuse to answer contested questions (rejected).** Honest about uncertainty and trivially safe from false balance. Rejected as unhelpful and cowardly: the user asked a real question, and "I won't say" abdicates the engine's purpose. It also fails to distinguish value disputes (where refusal-to-verdict is appropriate) from settled-but-disputed questions (where we *can and should* give the supported answer). A blanket refuse erases that distinction.

- **Steelman every evidenced surviving position with provenance and confidence, distinguishing empirical defeat from value disagreement (CHOSEN).** Represents the real epistemic state honestly: multiple live positions where the dispute is normative, a supported answer plus a flagged correction where the dispute is factual. Cost: steelmanning fairly is hard and risks false balance; we mitigate with evidence-grade/corroboration weighting and explicit consensus-vs-minority labels, and we accept residual difficulty as the honest price of axis D. Chosen because it is the only option that is neither falsely certain nor uselessly silent, and because it consumes — rather than discards — the existing ADR-0089/ADR-0023/ADR-0087 machinery.

## Consequences
- **Positive:** The engine's signature differentiator from LLMs becomes concrete and auditable — contested answers carry provenance, confidence, and an explicit map of *why* parties disagree. It honors the CONTESTED state (ADR-0023) and multi-extension result (ADR-0089) end-to-end instead of collapsing them at the last step. The empirical-vs-normative line keeps us from degenerating into a both-sides machine, and consensus/minority labeling gives users calibrated, not merely balanced, output. No new cognition is required — it is a renderer over an existing graph, cheap for a 2-founder team.

- **Negative:** Defining the "strongest form" of a position is a judgment call and a real bias surface; an unfair steelman can mislead as badly as a flat verdict. The confidence floor, the consensus/minority thresholds, and the empirical-defeat boundary are all hand-tuned and domain-dependent (compare the constant-tuning honesty of ADR-0023). Drawing the empirical/normative line wrong in either direction is harmful: treating a values question as factual produces a false verdict; treating a settled fact as contested produces false balance. Contested responses are longer and harder to consume than a single answer, which has a UX cost.

- **Future work:** Per-domain calibration of the confidence floor and consensus thresholds (alongside ADR-0093 rollout); learned-but-auditable steelman quality checks (without an LLM — e.g. requiring each steelman to cite premises present in the argument graph); theory-of-mind integration (ADR-0039) so the engine can frame the value fork in terms the specific user already holds; and a "minority report" surfacing mechanism that flags when today's consensus is showing rising conflict pressure (ADR-0023 EWMA) and may be destabilizing.

## Implementation Notes
- Add a **contested-response renderer** as a read-only consumer over the ADR-0089 argument graph: given the set of surviving preferred extensions, it emits one steelman block per surviving position with `{strongest-claim, supporting-arguments, sources+evidence_grade (ADR-0087), confidence+strength (ADR-0023), consensus|minority label}`, followed by a disagreement-locus block read from the ADR-0089 argument trace. No mutation of beliefs or atoms.
- Trigger gating consumes the ADR-0089 multi-extension result, the ADR-0023 `belief_is_contested` flag, the ADR-0029 hard-conflict flag (two Tier-A sources disagreeing → freeze + surface, which feeds contested mode directly), and the ADR-0093 per-domain contested tag. The confidence floor is a renderer config constant per domain.
- The empirical-defeat path reuses the ADR-0089 acceptability result: a position not in any surviving preferred extension because it was defeated by FORMAL/EMPIRICAL_STRONG evidence (ADR-0087) is routed to the "supported answer + noted refutation" path, NOT the steelman path.
- Every contested response is recorded to the append-only decision log (ADR-0043): which positions were surfaced, their evidence grades, the trigger that fired, and the empirical-vs-normative classification, so the rendering is auditable after the fact.
- Per-domain contested tagging is owned by ADR-0093; this ADR only consumes the tag.
- Testing: (1) a value-laden query (e.g. a policy tradeoff with no factual defeater) returns >=2 steelmanned positions, each with sources and confidence, with NO single verdict and an explicit value-fork explanation. (2) A factually-settled query that some low-grade sources dispute returns the supported answer and notes the refuted claim as refuted — NOT a false-balance pair. (3) A consensus-vs-minority query labels each position correctly by corroboration/evidence grade rather than by screen space. (4) A query below the confidence floor on its second position does NOT enter contested mode.
- DEPENDS ON: ADR-0089 (argument graph + multi-preferred-extension result + trace, the immediate upstream), ADR-0023 (CONTESTED belief state), ADR-0087 (provenance + evidence_grade weighting), ADR-0029 (hard-conflict freeze/surface), ADR-0093 (per-domain contested tagging), ADR-0043 (audit log), ADR-0086 (axis D of the master architecture).

## Implementation status

**Increment 1 (landed): the steelman over the debate engine.**
`src/parts/reasoning/steelman.nova` consumes the ADR-0089 debate output to present
a contested claim as every *surviving* evidenced position at its strength --
never a false verdict, never false balance. `steelman_positions` summarizes each
PREFERRED extension (ADR-0089 inc 6) that takes a stance on the claim;
`steelman_is_contested` is true only when both a supporting and an opposing
position survive; `steelman_render` / `steelman_atom_render` produce the
user-facing text with consensus (strongest evidence) vs minority labelling.

The empirical-defeat-vs-value-disagreement line (the heart of this ADR) falls out
of preferred semantics for free: a side defeated on the merits -- e.g. by a strict
proof -- is in *no* preferred extension, so it is simply absent (reported elsewhere
as refuted), never steelmanned as a peer; only genuinely defensible sides each
survive as their own extension and are steelmanned. Verified via the bootstrap:
`steelman` suite, 7 checks -- a defeasible for/against clash steelmans both sides
(consensus/minority by strength), a proof-settled claim yields a single supported
position (the opposing side absent), and a KG-level clash of two studies renders
two positions.

Sample render:

```
Claim #0 -- CONTESTED; evidenced positions (steelmanned):
  - SUPPORTS the claim (evidence strength 1000, consensus)
  - OPPOSES the claim (evidence strength 400, minority)
```

**Increment 2 (landed): provenance per position.** `steelman_render_prov` /
`steelman_atom_render_prov` attach each surviving position's provenance chain --
for every argument in the position, its premise atom + evidence grade and source
(via debate.nova's `_darg_prov_str`). A position carries its claim-bearing
argument indices (`POS_ARGS`). Sample render:

```
Claim #0 -- CONTESTED; evidenced positions (steelmanned):
  - SUPPORTS (strength 500, consensus):
      from trial_pro [empirical_strong] via src:journal_a
  - OPPOSES (strength 200, minority):
      from trial_con [empirical_weak] via src:journal_b
```

So a contested answer shows every side WITH its sources and grades, and the
weaker-sourced side is labelled minority. Verified: `steelman` suite 11 checks.

**Scope still open:** the per-domain
contested tag (ADR-0093) and the CONTESTED belief flag (ADR-0023) as additional
triggers beyond a multi-extension debate; and routing the debate engine's
contested results into this renderer at the answer path.
