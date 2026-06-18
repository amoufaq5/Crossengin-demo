# ADR-0092: Autonomous self-update governance & safety gates

## Status

Proposed

## Date

2026-06-15

## Context

CrossEngin already updates itself from the open web on its own initiative. The
self-learning-trigger queue (ADR-0026) files an `SLT_UNKNOWN_QUERY` for every
unknown term, and the r50 idle-loop drain dequeues one, derives a Wikipedia URL,
and runs `learn_from_url` (DNS + TLS 1.3 + preprocess + `lp_ingest`), minting the
extracted triples and operators directly into the knowledge base. The transport
is real, the extraction is real, and the agent demonstrably closes its own
knowledge gaps. What is missing is *governance*: today a fetched claim becomes a
usable atom almost immediately. There is no gate that runs a new claim through
verification or debate before it is trusted, no license enforcement at the moment
of promotion, and only the coarse controls of r50 (whitelist, one fetch per turn,
`CE_AUTORESEARCH`) bounding what the agent researches and asserts.

This is the load-bearing risk of the ADR-0086 thesis. Autonomous knowledge
acquisition is the difference between a static KB and a system that grows — and it
is also the single largest attack surface. Web content can be subtly wrong, stale,
or deliberately poisoned; an unlicensed source can silently contaminate the
commercially-clean KB (Rule 3); and a self-initiated ingest that overwrites a
high-confidence or user-taught atom is a correctness *and* a trust failure. The
machinery to defend against this now exists in pieces but is not wired into the
research path: the provenance/licensing ledger (ADR-0087), the formal-verification
checker (ADR-0088), the argumentation + Bayesian debate engine (ADR-0089), the
hard-conflict freeze and source tiers of ADR-0029, the CONTESTED belief state of
ADR-0023, and the non-revisable constitution of ADR-0045.

Two constraints shape the design. First, no-LLM cognition (ADR-0014): the loop
routes fetched text through the reader, never an LLM, so every gate must be a
symbolic, auditable computation, not a model judgment. Second, the edition policy
(ADR-0091): Edge may run with autonomous research switched off entirely, so the
governed pipeline must be a wrapper that can be disabled without disabling the rest
of cognition. Autonomous self-update is the Phase 4 item on the ADR-0086 roadmap;
this ADR specifies the governance that makes it safe enough to ship.

## Decision

Define a **governed promotion pipeline** that sits between r39/r50 fetch-extraction
and the trusted knowledge base. A self-researched claim is never inserted as a
trusted fact directly; it enters as a CANDIDATE and may only become a usable atom
by surviving a staged set of automatic gates.

**1. Promotion lifecycle.** Every self-researched claim moves through three states:

- `CANDIDATE` — freshly fetched and extracted by the r50 path. Lives in a staging
  partition (multi-KG #8), **excluded from answers**. It exists, but cognition
  cannot cite it.
- `VERIFIED` / `CORROBORATED` — has cleared the evidence gates below and been
  assigned a license and an evidence grade (ADR-0087).
- `PROMOTED` — trusted, in the live KB, usable in answers.

**2. Gates between CANDIDATE and PROMOTED**, evaluated in order; any failure halts
promotion and is logged:

- **(a) License resolution (ADR-0087).** The source's license must resolve to one
  permitting commercial use of the derived fact. Unresolvable or non-commercial
  sources stay in the quarantine partition and **cannot** be promoted into the
  clean KB. No exceptions.
- **(b) Evidence-grade assignment (ADR-0087).** The candidate is assigned a grade
  from `{FORMAL, EMPIRICAL_STRONG, EMPIRICAL_WEAK, TESTIMONIAL, CONTESTED}`. The
  grade earned gates which downstream uses are allowed and how it weights belief.
- **(c) Proof checking (ADR-0088), for formally-tractable claims.** A claim that
  can be expressed formally is sent to the checker; only a passing proof earns the
  `FORMAL` grade and the `proof_ref`. No proof, no FORMAL — it falls back to an
  empirical grade or is rejected.
- **(d) Corroboration threshold (ADR-0029), for empirical claims.** `EMPIRICAL_STRONG`
  requires multiple independent sources or a sufficiently high source tier; a lone
  fetch is at most `EMPIRICAL_WEAK`.
- **(e) Conflict check.** A candidate that contradicts a high-confidence or
  user-taught (Tier-A, ADR-0027) atom does **not** silently overwrite it. The
  ADR-0029 hard-conflict freeze fires and both atoms are marked CONTESTED
  (ADR-0023). The candidate is **not** promoted; the conflict is queued for human
  adjudication.
- **(f) Debate adjudication (ADR-0089).** Promotion is framed as an *argument* the
  candidate must win against existing beliefs, not a blind insert. The debate
  engine builds the argument graph, computes grounded/preferred acceptability, and
  only an accepted candidate promotes. A contested outcome routes to the steelman
  policy (ADR-0090).

**3. Safety gates on autonomy itself:**

- **Scope.** Research is limited to whitelisted sources (ADR-0028). The agent does
  not browse arbitrary URLs.
- **Rate/budget.** Extend r50's one-fetch-per-turn with explicit per-session fetch
  and promotion budgets; exceeding them defers, it does not bypass.
- **Constitutional bound (ADR-0045).** The constitution constrains which topics may
  be researched and which assertions may be made, and it is a hard inhibitory,
  non-revisable signal. The autonomous loop **cannot self-revise it.**
- **Opt-in / per-edition.** Autonomy is configurable; Edge may disable it entirely
  (ADR-0091). Disabling autonomy must not disable the rest of cognition.
- **Auditability & reversibility.** Every promotion and every rejection is appended
  to the decision log (ADR-0043, #9) with the triggering source, license, grade,
  and gate outcomes. A bad promotion can be overridden (ADR-0044) or garbage-
  collected via atom death (ADR-0025), rolling the KB back to its pre-promotion
  state.

**4. Self-update cannot weaken the self.** The autonomous loop may **never** edit
constitution or soul atoms (ADR-0034, ADR-0045) or its own safety gates. These are
non-revisable by construction; an attempt is refused and logged. Self-update grows
knowledge; it does not touch governance.

## Options Considered

- **Ingest-on-fetch (status quo r50, rejected for trusted use).** A fetched claim
  becomes a usable atom directly. Simple and already working, but there is no
  verification, no license enforcement at promotion, no defense against
  source-poisoning, and no way to prove the KB is clean. Acceptable for an
  exploratory demo, fatal for a system whose thesis is trustworthy autonomous
  knowledge. *(rejected)*
- **Human-approve every promotion (rejected).** Maximally safe per-claim, but it
  does not scale to idle-loop research volumes and defeats the point of autonomy —
  an agent that must ask before learning is not autonomous. Reserve scarce human
  attention for the cases that actually need judgment (hard conflicts, ADR-0029),
  not the routine clean-and-corroborated majority. *(rejected)*
- **Staged governed promotion with automatic gates + human-in-loop only for hard
  conflicts (CHOSEN).** Routine clean, corroborated, non-conflicting candidates
  promote automatically through the gates; only hard conflicts and contested
  outcomes escalate to a human. This keeps autonomy real while bounding its blast
  radius, and every transition is logged and reversible. *(CHOSEN)*

## Consequences

**Positive:**
- Self-initiated research becomes trustworthy: a promoted fact has cleared license,
  grade, proof/corroboration, conflict, and debate gates, and its full chain is in
  the decision log.
- The clean KB stays clean by construction — unlicensed candidates cannot cross the
  license gate into the commercial partition (Rule 3, ADR-0091).
- User-taught and high-confidence knowledge is protected: autonomous research can
  surface a conflict but cannot silently overwrite trusted atoms.
- Every self-update is auditable and reversible, so a mistake is recoverable rather
  than permanent.

**Negative:**
- Promotion latency: a candidate no longer becomes usable the moment it is fetched;
  it waits for the gates, and some claims will sit in staging indefinitely (e.g.
  ambiguous license, no corroborating source).
- Tuning burden: the corroboration threshold, rate/promotion budgets, and the
  formally-tractable/empirical split all need calibration and will mis-handle the
  margins until tuned.
- Source-poisoning is **reduced, not eliminated.** A determined adversarial source
  ecosystem that fabricates multiple "independent" corroborating sources can in
  principle clear the EMPIRICAL_STRONG bar. Tier weighting (ADR-0029) and conflict
  freezing raise the cost of the attack; they do not close it. We state this
  plainly: no gate here is a complete defense against a sophisticated coordinated
  source attack.
- Added complexity in the hottest learning path (a state machine plus four to six
  gate calls per candidate).

**Future work:**
- Independence detection for corroboration (distinguish genuinely independent
  sources from mirror/derivative content) to harden against fabricated consensus.
- Adaptive budgets and grade thresholds learned from promotion/override history
  (ADR-0044) rather than fixed constants.
- Source-reputation feedback: demote a source's tier when its promoted atoms are
  later overridden or contested.

## Implementation Notes

- A **promotion state machine** in `src/learning/` wraps the existing r50
  `learn_from_url` path: extraction now emits CANDIDATE atoms into a staging
  partition (multi-KG #8) instead of inserting trusted atoms directly.
- Gate calls: (a) the ADR-0087 license resolver (`resolve_license`); (b)/(d)
  evidence-grade assignment from corroboration + tier (ADR-0029); (c) the ADR-0088
  proof checker for formally-tractable claims; (e) the ADR-0029 hard-conflict
  freeze + ADR-0023 CONTESTED marking; (f) the ADR-0089 debate adjudication.
- CANDIDATE atoms in the staging partition are excluded from answer construction
  until PROMOTED; promotion moves the atom into the live KB with its license,
  grade, and `proof_ref` set per the ADR-0087 ledger schema
  (`docs/design/atom-provenance-schema.md`).
- Every state transition — promotion and rejection alike — logs to the append-only
  decision log (ADR-0043, enhancement #9) with the source, gate outcomes, and
  resulting grade, so any self-update is walkable and reversible (ADR-0044 /
  ADR-0025).
- Constitution/soul atoms (ADR-0034, ADR-0045) are flagged non-revisable; the
  promotion machine refuses any transition that would write them and logs the
  refusal.
- Domain rollout follows ADR-0093: math/logic/CS first, where the formal proof gate
  (c) is strongest, before broad empirical domains.
- Testing: a well-corroborated, clean, non-conflicting candidate promotes to a
  usable atom; an unlicensed candidate is blocked at the license gate and never
  leaves quarantine; a candidate contradicting a user-taught atom freezes contested
  and is NOT promoted; a formally-tractable candidate that fails proof checking does
  not receive the FORMAL grade; a constitution-edit attempt by the autonomous loop
  is refused and logged.
- DEPENDS ON: NOVA enhancement #8 (multi-KG namespacing for the staging partition),
  #9 (audit log). Builds on ADR-0087, ADR-0088, ADR-0089, ADR-0029. No new
  arithmetic enhancement required.

## Implementation status

**Increment 1 (landed): the promotion state machine + gates.**
`src/learning/promotion.nova` implements the CANDIDATE→PROMOTED lifecycle and the
ordered gates, composing the verified ADR-0087/0088 pieces:
- **(a) license** — `atom_resolve_license` + `lic_commercial_ok`; a
  non-commercial/unresolved source → `CAND_QUARANTINED` (never enters the clean KB).
- **(e) conflict** — a candidate contradicting a protected atom (user-taught
  `LICENSE_OWNER`, or confidence > 0.8) freezes both `CONTESTED` and is NOT
  promoted (`CAND_CONTESTED`); ADR-0029/0023.
- **(b/c/d) grade** — `cand_assign_grade`: `FORMAL` only with a VERIFIED KG-proof
  (ADR-0088), else corroboration-based (`>= 2` independent → `EMPIRICAL_STRONG`,
  a lone fetch → `EMPIRICAL_WEAK`, none → `TESTIMONIAL`).
- **(4) governance** — refuses to promote over a `governance`-flagged atom
  (ADR-0045 non-revisable) → `CAND_REJECTED`.
- On promotion, a grade-weighted observation (ADR-0087 increment 3) sets the
  atom's confidence; `cand_is_usable` gates answer-construction to PROMOTED atoms.

The **(f) debate-adjudication gate is a stub** that currently accepts a clean,
graded, non-conflicting candidate; it becomes real when the debate engine
(ADR-0089) lands. Verified via the bootstrap: `promotion` suite, 21 checks
(clean promote, unlicensed quarantine, user-taught conflict, FORMAL+proof,
unproven fallback, governance refusal, lone-fetch weak).

Note: `cand_promote` takes a bundled `claim` + `pctx` (≤3 args) and
`atom_set_provenance` now takes a `prov_ledger` tuple — NOVA's bootstrap
mis-passes a function's 7th+ argument, so the gate inputs and the 7-arg
provenance setter were restructured to stay within the limit (this also fixed a
latent corruption of the provenance `proof` field under the bootstrap).

**Scope still open:** wiring the machine into the live r50 `learn_from_url` path
(CANDIDATE atoms into a staging partition, excluded from answers until promoted);
the per-session fetch/promotion budgets; and the real debate gate (ADR-0089).
