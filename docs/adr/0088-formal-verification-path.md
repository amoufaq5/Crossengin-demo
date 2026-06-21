# ADR-0088: Formal-verification path for math/logic/CS atoms

## Status

Proposed

## Date

2026-06-15

## Context
ADR-0086 sets the bar: CrossEngin must not merely *assert* that it out-reasons
LLMs, it must *demonstrate* it on questions where correctness is objectively
checkable. ADR-0087 gives every atom a provenance ledger with an
`evidence_grade ∈ {FORMAL, EMPIRICAL_STRONG, EMPIRICAL_WEAK, TESTIMONIAL,
CONTESTED}` and a `proof_ref` slot, but it stops short of saying what a `FORMAL`
grade *means operationally* or who is entitled to assign it. ADR-0089 already
relies on this distinction: it treats arguments built solely from strict rules
and `FORMAL` premises as *proofs* that defeasible attacks cannot defeat. That
privilege is only sound if a `FORMAL` grade is backed by something machine-
checkable rather than by a source's say-so. This ADR defines that backing.

There is a clean line between two kinds of knowledge the substrate holds. There
are facts we can *verify* — theorems with derivations, well-typed programs,
terminating computations whose result we can recompute — and facts we merely
*source*, where the best we can do is the authority-weighting and conflict
resolution of ADR-0029. The first kind is special: its truth does not erode with
time, does not depend on which source last touched it, and is not a matter of
corroboration but of derivation. Mathematics, logic, and computer science are
almost entirely of the first kind, which is exactly why ADR-0093 opens with them
as the proving ground. To exploit that, the substrate needs a way to carry a
*derivation* alongside a claim and to re-check it on demand.

The constraints are the usual ones. Rule 1 forbids third-party dependencies:
we cannot shell out to Lean, Coq, Isabelle, or any external prover; whatever
checks proofs must be native NOVA. Rule 3 requires the knowledge base to stay
commercially clean, which a checker built on published proof-theory satisfies.
The team is small and bootstrapped, so the checker must be small enough that one
person can audit it and trust it — the entire soundness argument of this path
rests on a tiny trusted core, in the de Bruijn / LCF tradition, built natively.
And it must run inside the tick-driven substrate (ADR-0001) without an LLM
anywhere in the path (ADR-0014).

## Decision
We add a **formal-verification path**: atoms in formally tractable domains may
carry a machine-checkable `proof_ref` (ADR-0087) pointing into a dedicated
`KG-proofs` store, and a small native **proof checker** decides whether that
proof object actually establishes the claim.

**What a proof object is, in NOVA terms.** A proof object is a checked
*derivation*: a finite tree (stored as substrate structure in `KG-proofs`) whose
root is the claim atom, whose leaves are axioms or previously-`FORMAL` atoms, and
whose internal nodes are applications of strict, truth-preserving inference rules
from a fixed, small rule set. It is not a natural-language argument; it is a term
the checker can walk mechanically. A "proof" of a terminating computation is the
recorded reduction trace; a "proof" of a type judgment is the typing derivation.

**The trusted core.** A single tiny kernel — `mind/verify.nova` — is the only
code allowed to *grant* a `FORMAL` grade. Its sole job is to walk a proof object
and confirm every step is a legal instance of an axiom or inference rule, that
all leaves are axioms or already-`FORMAL`, and that the root matches the claim.
Everything outside the kernel (proof search, ingestion, the debate engine) is
*untrusted*: it may *propose* proofs, but only the kernel's `check` verdict
assigns the grade. The kernel must stay small enough to audit by reading it
(LCF-style "small trusted core"); we deliberately keep the rule set minimal and
push convenience elsewhere.

**Grade pinning and the decay exemption.** When the kernel returns `verified`,
the atom's `evidence_grade` is set to `FORMAL` and its belief is pinned near-
certain per ADR-0087, and — critically — it is **exempted from the ADR-0023 time
decay**: a theorem does not become less true while unobserved. The pin is not
permanent faith. It is **conditional on re-checkability**: a `FORMAL` atom is
unpinned (grade dropped, decay re-enabled, belief returned to ordinary
adjudication) the moment a re-check fails — because an axiom it depended on
changed, a referenced lemma lost its own `FORMAL` grade, or the proof object was
tampered with.

**Relationship to the debate engine.** ADR-0089 consumes this directly: a
`FORMAL` atom with a valid `proof_ref` is a strict, truth-preserving premise, and
an argument composed only of such premises and strict rules is a proof that
**defeasible attacks cannot defeat**. Rebut/undercut/undermine attacks from
defeasible arguments simply do not apply to a verified strict argument; the only
thing that can dislodge it is a failed re-check, handled here, not in the debate.

**Honest scope: checking, not discovery.** This ADR delivers proof *checking*,
which is cheap and decidable. It does not deliver proof *search*, which is the
hard, often undecidable part. v1 checks proofs that arrive one of two ways:
(a) supplied by ingestion (a source provides a formal derivation we re-check
rather than trust), or (b) constructed by **bounded search** for shallow,
mechanical obligations (small type-checks, finite case enumeration, terminating
evaluation). Full automated theorem proving — discovering nontrivial proofs — is
explicitly **future work** and out of scope here.

## Options Considered
- **Trust sources only (rejected).** Assign `FORMAL` on the strength of a
  reputable source asserting a theorem. This is just ADR-0029 source weighting
  wearing a different label — it performs *no verification*, so a `FORMAL` grade
  would mean nothing more than "Tier A said so," and ADR-0089's no-defeat
  privilege for proofs would rest on authority rather than derivation. It cannot
  support the measurable "out-reasons LLMs on checkable questions" claim of
  ADR-0086, because nothing was checked.
- **Embed an external prover (Lean / Coq / Isabelle) as the kernel (rejected).**
  Mature, battle-tested checking with huge libraries. Rejected on Rule 1: each is
  a large third-party dependency outside NOVA, dragging in its own runtime,
  licensing surface (Rule 3 risk), and a trusted base far too big for a small
  team to audit or to run inside the 100Hz substrate. It would also sit *outside*
  the substrate, violating the substrate-native principle of ADR-0001.
- **Build a small native checking kernel (CHOSEN).** A tiny, auditable NOVA
  kernel with a fixed minimal rule set, checking proof objects stored as
  substrate structure. More work than trusting sources, and far less capable than
  a mature prover, but it is the only option that is simultaneously verifying,
  dependency-free (Rule 1), commercially clean (Rule 3), small enough to trust,
  and inside the no-LLM substrate. We accept a narrow initial rule set as the
  price of a trustworthy core.

## Consequences
- **Positive:** `FORMAL` becomes a *grounded* grade backed by re-checkable
  derivations, not a label; ADR-0089's proofs-beat-defeasible-attacks rule
  becomes sound; theorems and verified computations stop decaying (ADR-0023
  exemption), correctly modeling that mathematical truth is timeless; CrossEngin
  can put a checkable artifact behind every formal answer, which is exactly what
  the proving-ground measurement of ADR-0086/ADR-0093 needs; the trusted base
  stays tiny and auditable.
- **Negative:** Building a sound proof checker/kernel in NOVA is real,
  exacting work — a kernel bug silently grants `FORMAL` to falsehoods, which is
  the worst failure mode in the whole system, so the kernel needs disproportionate
  test and review effort; the initial rule set is narrow, so many true claims will
  *not* be expressible as proof objects yet and will fall back to ADR-0029
  sourcing; proof objects add storage and re-check cost; encoding ingested
  derivations into the kernel's term language is itself nontrivial curation.
- **Future work:** Proof *search* / bounded automated theorem proving to
  *construct* proofs rather than only check supplied ones; widening the rule set
  (more decision procedures, arithmetic, more of the CS type-theory) without
  bloating the trusted core; proof caching and incremental re-check on dependency
  change; sharing verified lemmas across domain KGs as ADR-0093 opens new slices.

## Implementation Notes
- New store `KG-proofs` holds proof objects as substrate structure (trees of
  rule applications, leaves referencing axiom/`FORMAL` atoms), namespaced as its
  own KG.
- `mind/verify.nova` is the trusted kernel: `check(proof_ref, claim_atom) ->
  {verified | failed}`. It is the *only* writer of a `FORMAL` grade. Keep it
  minimal and reviewable; no untrusted code path may set `FORMAL` directly.
- On `verified`: set `evidence_grade = FORMAL` and pin belief via ADR-0087, set
  the decay-exempt flag read by ADR-0023. On a failed re-check: clear the flag,
  drop the grade, return the atom to ordinary belief/decay and conflict handling.
- Integrates with ADR-0089: the debate engine reads `evidence_grade`/`proof_ref`
  to mark strict premises; a `FORMAL` strict argument is immune to defeasible
  attack and is dislodged only by a kernel re-check failure surfaced from here.
- Re-check triggers: dependency atom changed grade, referenced lemma unpinned,
  proof object mutated, or a periodic substrate sweep.
- Testing: a valid proof verifies and pins its atom near-certain and decay-exempt;
  a tampered proof object fails `check` and unpins (grade dropped, decay
  re-enabled); a defeasible attack against a verified strict/`FORMAL` argument
  has no effect (cannot defeat a proof, per ADR-0089); a `FORMAL` lemma losing its
  grade triggers re-check and unpin of everything that depended on it; a
  non-terminating/over-budget bounded search returns "unproven", never "verified".
- DEPENDS ON: ADR-0087 (grade pinning, `proof_ref` slot), ADR-0089 (strict-
  argument consumer), ADR-0023 (decay exemption hook), ADR-0029 (sourcing
  fallback for unprovable claims); NOVA enhancement #8 (multi-KG namespacing for
  `KG-proofs` and cross-KG lemma references); #9 (audit log of every `check`
  verdict, pin, and unpin).

## Implementation status

**Increment 1 (landed): the `KG-proofs` store.** `src/kg/proofs.nova` is the
table an atom's `proof_ref` (ADR-0087) interns into — the storage layer beneath
the checker kernel. A proof record is `[claim_label, checker_status,
axioms_used, derivation_blob]`; `proof_register` files an obligation
(`UNCHECKED`), and the kernel (future `mind/verify.nova`) records its verdict via
`proof_set_status` (`VERIFIED` / `FAILED`). `atom_proof_verified(reg, a)` makes
FORMAL-grade consistency mean "has a VERIFIED proof" (superseding atom_store's
`atom_grade_consistent`, which only checked a `proof_ref` was present). Slot 0 is
a reserved no-proof placeholder so a `PROV_NONE`/out-of-range ref fails safe to
UNCHECKED (never VERIFIED). Verified via the bootstrap: `proofs` suite, 15 checks.

**Increment 2 (landed): the kernel.** `src/mind/verify.nova` is the small
trusted core -- the only writer of the `FORMAL` grade. Term language v1:
propositional (`atom` / `and` / `imp`). Rule set v1 (classical Hilbert-style,
minimal but real): `AXIOM`, `HYP` (a leaf resting on an already-FORMAL atom
whose proof is currently `VERIFIED` -- the cascading re-check honesty), `AND_I`,
`AND_EL`, `AND_ER`, `MP` (modus ponens). `verify_check(reg, axioms, hyps, proof,
claim_term)` walks the proof tree; `verify_pin_atom(reg, atom, pkt)` runs the
kernel and, on `VERIFIED`, atomically sets `evidence_grade = FORMAL`, pins the
belief at `BEL_FORMAL_PIN`, and stamps the atom's `proof_ref` with the
registered code -- nothing outside this file may do that. `verify_recheck_atom`
re-runs the kernel on a previously-pinned atom and, on failure, flips the proof
to `PROOF_FAILED`, drops the grade, and resets the belief to the uniform prior
(the unpin path for ADR-0088's re-check triggers: dependency change, lemma
unpinned, blob tampered). Verified via the bootstrap: `verify` suite, 31 checks
-- every rule accepted on a valid derivation, every shape of unsound proof
rejected (wrong projection, wrong consequent, MP antecedent mismatch, unchecked
or label-mismatched HYP), and the pin/unpin round-trip end-to-end.

**Increment 3 (landed): the ingestion path is kernel-gated.**
`src/learning/formal_ingest.nova` is the parallel "supplied derivation" ingest
path (ADR-0088 path (a)), beside `govern_fetched_atom` for the empirical track.
`lp_ingest_formal(atom, proofs_reg, src_label, pkt)`: license gate FIRST (an
unclean source cannot drive a FORMAL pin even with a valid derivation -- Rule
3 / ADR-0087 redistribution constraint), then the trusted kernel
(`verify_pin_atom`). On VERIFIED: PROMOTED + grade FORMAL + belief pinned +
`proof_ref` stamped, atomically. On unclean source: QUARANTINED before the
kernel runs. On kernel rejection: CANDIDATE at the uniform prior (the caller
may then route through ordinary empirical promotion as TESTIMONIAL). So the
ONLY path to a FORMAL grade in the entire engine now bottoms out in a
machine-checked derivation -- "a source's say-so is never enough" is now
enforced architecturally, not just stated. HYP-chain ingestion is covered:
an atom ingested as FORMAL can be reused as a HYP for a downstream proof,
which then chains through MP / AND / etc. Verified via the bootstrap:
`formal_ingest` suite, 18 checks (verified-proof PROMOTES + pins FORMAL +
stamps license; unclean source QUARANTINES before the kernel; kernel
rejection falls back to CANDIDATE with belief intact; HYP chains promote;
ingested FORMAL atoms compose into MP chains end-to-end).

**Increment 4 (landed): the decay exemption.** `atom_store.nova` gains
`atom_decay_exempt(a)` (1 iff grade is FORMAL) and `atom_decay_belief(a,
retain)` -- the ADR-0023 per-atom belief-decay hook a future periodic sweep
calls instead of `bel_decay` directly. A verified FORMAL atom is exempt: its
pinned belief is left untouched ("a theorem does not become less true while
unobserved"). The exemption is DERIVED from the grade, not stored as a separate
flag, so it can never drift out of sync and the kernel's unpin path
(`verify_recheck_atom` dropping the grade on a failed re-check) automatically
re-enables decay -- the "pin is conditional on re-checkability" contract. The
GC path was already covered: a pinned belief's strength (~999000) sits far
above `DEATH_BELIEF`, so a FORMAL atom is never collectable. `tb_decay`
(bayesian_updates) now delegates to the shared `bel_decay` so the decay math
has one home. Verified via the bootstrap: `decay_exemption` suite, 13 checks
(ordinary atom decays; FORMAL atom unchanged under aggressive decay; exemption
lifts after unpin; tb_decay refactor still decays); `bayesian_updates` 20 still
green.

**Increment 5 (landed): the periodic belief-decay sweep.**
`src/learning/belief_decay.nova` is the runtime side of increment 4's
exemption hook. `belief_decay_sweep(kg, retain_milli)` walks a KG and calls
`atom_decay_belief` per atom; the multi-KG fold `belief_decay_sweep_all(reg,
retain)` covers every KG in a registry. Verified FORMAL atoms are counted
into a separate `exempted` bucket (the kernel's exemption is honored at the
sweep level); GC-managed atoms (tombstoned / dead) are skipped (the death
monitor owns their lifecycle). Cadence is the caller's decision -- same
contract as `adm_sweep`; a future substrate scheduler tick wires both. So
the FORMAL pin is no longer just a one-shot grant: it survives every periodic
sweep that would otherwise drift the belief toward the prior, exactly as
ADR-0023's "classical atom barely moves" fixture intends -- now realised for
the proof-backed grade specifically. Verified via the bootstrap:
`belief_decay` suite, 12 checks (sweep counts + decays ordinary atoms;
repeated sweeps don't erode FORMAL atoms even at 0.2 retention x 4 rounds;
multi-KG fold sums correctly; retain=1000 is a clean no-op).

**Increment 7 (landed): cascading re-check.**
The dep-graph half of ADR-0088's "lemma loses its grade triggers re-check and
unpin of everything that depended on it". Two layers:
- `src/kg/proofs.nova` adds a `PRF_DEPS` slot to each proof record (the
  dependents -- downstream proofs that used this one via HYP) and a
  `proof_invalidate(reg, code)` that flips `code` to FAILED and recursively
  flips every dependent. Already-FAILED proofs are not re-walked, so diamond
  dep graphs terminate.
- `src/mind/verify.nova`'s `verify_pin_atom` now records dep edges at check
  time (`_verify_register_hyp_deps` walks the proof tree and adds an edge for
  every HYP step), and `verify_unpin_atom` is extracted as the shared atom-
  level unpin (drop grade, reset belief to prior; the proof_ref is left
  pointing at the FAILED record, the informative state for /why audit).
- `src/mind/cascade.nova` is the entry point: `verify_cascade_invalidate(reg,
  kgreg, root_code)` runs `proof_invalidate` then walks every KG and unpins
  every FORMAL atom whose `proof_ref` is no longer VERIFIED. Returns
  `[proofs_flipped, atoms_unpinned]` so the caller / audit can observe the
  blast radius.

So one tampered axiom, or one re-check failure on a lemma, now correctly
withdraws every downstream theorem's FORMAL grade with no further intervention.
Verified via the bootstrap: `cascade` suite, 28 checks (dep edges recorded at
check time; chain cascade flips 2; already-FAILED is a clean no-op; diamond
cascade flips exactly 3 with no double-walk; end-to-end cascade unpins 2 atoms
and resets their beliefs to the prior; a second cascade is idempotent; an
unrelated FORMAL atom in another KG is untouched). `verify`, `formal_ingest`,
`decay_exemption`, `belief_decay`, `maintenance`, `decision_record` all stay
green; `proofs`' 1 pre-existing identical-string failure is unchanged.

**Increment 6 (landed): the maintenance scheduler tick is wired.**
`src/learning/maintenance.nova` is the per-tick cadence hook (ADR-0037):
`maint_on_tick(sched, now)` / `maint_on_tick_reg(sched, reg, now)` run the
belief-decay sweep (and, opt-in, the atom GC) on their own tick intervals,
cheaply skipping when not due. The live chat loop (`examples/crossengin_chat`)
builds a scheduler at boot (`maint_new(0, 64, 990)`) and calls
`maint_on_tick_reg(_maint, kgreg, hs_now(hs))` once per turn, passing the
ACTIVE session's registry so the cadence follows `/switch`. So the FORMAL
decay exemption is now exercised by the running system, not just available:
ordinary beliefs drift toward the prior on the cadence; theorems do not.
Verified via the bootstrap: `maintenance` suite, 18 checks (due/not-due,
steady cadence, first-run warm-up, decay disabled, GC opt-in on an independent
cadence, quiet-tick no-op, and the registry-explicit hook across a switched
registry); the chat compiles with the hook wired.

**Increment 8 (landed): the periodic re-check sweep.**
Increment 7's cascade handles re-check on a KNOWN failure; this is the other
direction -- proactively re-running the kernel over FORMAL proofs on a cadence
to catch SILENT corruption (a tampered proof blob, a dependency that changed
without firing an invalidate) before anything queries the atom.
`src/mind/recheck.nova` adds a re-check registry (`rck_register(rck, atom,
pkt)`, called at pin time -- atoms don't carry their packet, so the registry
holds the (atom, packet) pairs the kernel needs). `rck_sweep_window` re-runs
`verify_check` over a bounded window and, on any failure, cascades through
`verify_cascade_invalidate` so one tampered lemma withdraws its whole downstream
cone. `rcks_on_tick(s, now)` is the cadence wrapper (mirrors maintenance.nova):
SAMPLED -- each due tick re-checks `sample` entries from a cursor that advances
and wraps, so a large proof base is amortised rather than fully re-verified on
any single tick. The FORMAL ingest path (`lp_ingest_formal`) auto-registers
every atom it pins via a wired-or-not handle (`fi_set_recheck_registry`), so
producer and consumer compose with no per-call bookkeeping. Verified via the
bootstrap: `recheck` suite, 27 checks -- a valid proof survives the sweep; a
proof whose lemma silently flipped is caught and its atom withdrawn to UNKNOWN
with belief reset; the cursor advances + wraps so all entries are covered over
successive ticks; due/not-due cadence; disabled cadence is inert; the ingest
path auto-registers a pinned proof and skips a quarantined one.

**Increment 9 (landed): FORMAL ingest is live in the chat.**
`src/agent/formal_chat.nova` is the live producer that makes the whole formal
machinery real in the running system. A fetched page can't supply a derivation,
but an AXIOM is itself a valid leaf proof, and a user (or curated math source)
asserting a foundational axiom IS the "supplied derivation" path. `/axiom
<label>` -> `fc_assert_axiom`: mints/finds the atom, builds the trivial AXIOM
leaf proof, and runs it through `lp_ingest_formal` -- so the Rule-3 license gate
(`user-taught` = OWNER, clean) and the trusted kernel both apply, the pin
auto-registers for the periodic re-check sweep, and the promotion is audited.
The chat boot wires a proofs registry + re-check registry (`fc_boot`) and an
`rcks` scheduler over the boot session's KG; the turn loop now calls
`rcks_on_tick(_rcks, hs_now(hs))` beside `maint_on_tick_reg`, so a sample of
pinned proofs is re-verified each cadence and any silent corruption cascades a
withdrawal. So every piece -- kernel, license gate, FORMAL pin, decay exemption,
GC immunity, dependency cascade, periodic re-check, decision-log audit -- is now
exercised end-to-end from a chat command, not just unit tests. Verified via the
bootstrap: `formal_chat` 16 checks (unbooted is safe; a user axiom pins FORMAL +
auto-registers + survives a clean sweep; an unclean source quarantines and does
NOT register; re-assertion pins both times; render strings distinguish the
outcomes). `crossengin_chat` compiles with the `/axiom` command, the boot
registries, and the per-turn re-check hook wired.

**Increment 10 (landed): derived theorems.** `formal_chat.nova` grows a formal
environment (label -> [term, proof_code, atom]) so a proof can reference an
earlier FORMAL proposition by name, and two new operations over it:
`fc_assert_imp` (assert `L` as the FORMAL implication `A -> C`) and
`fc_prove_mp` (DERIVE `C` by modus ponens from a FORMAL implication and its
FORMAL antecedent). The derivation rests on two HYP steps -- one per premise --
so the kernel records dependency edges from BOTH premises to the new theorem;
the theorem is a real, kernel-checked FORMAL atom, and invalidating either
premise CASCADES a withdrawal of it (and the periodic sweep re-checks it). So
the engine now holds derived theorems, not just asserted axioms. The chat
exposes `/imply L A C` and `/derive C IMP A` (the formal path; the pre-existing
`/prove` is the separate forward-chaining reasoning-KG search, untouched).
A shape mismatch or unknown premise reports CAND_REJECTED (ill-formed request)
distinctly from a kernel/license failure. Verified via the bootstrap:
`formal_chat` 27 checks -- MP derives a FORMAL theorem; unknown premise +
shape mismatch -> REJECTED; the load-bearing case: a derived theorem is
WITHDRAWN when its premise is cascade-invalidated (the HYP dep edges do their
job end-to-end through /derive); the theorem auto-registers for re-check; render
strings distinguish the outcomes. `crossengin_chat` compiles with both commands
wired.

**Increment 11 (landed): more inference forms + chained proofs.** The chat seam
now exposes the kernel's full propositional rule set, not just MP.
`fc_prove_and` (and-introduction: `(L and R)` from two FORMAL conjuncts) and
`fc_prove_and_elim` (and-elimination: recover a conjunct from a FORMAL
conjunction) join `fc_prove_mp`; the chat commands are `/and C L R`, `/andl C
CONJ`, `/andr C CONJ`. Because every derived theorem is recorded in the formal
environment with its proof code, proofs CHAIN automatically: a theorem derived
by MP can be a conjunct in an and-introduction, whose result can feed a further
step. The dependency edges chain too -- a 3-deep proof `p -> q -> (q and r)`
withdraws ENTIRELY when its root axiom `p` is invalidated, every link cascading
through the HYP edges the kernel recorded at each step. Verified via the
bootstrap: `formal_chat` 38 checks -- and-intro + both elims pin FORMAL; a
mis-named conjunct or unknown premise -> REJECTED; and the load-bearing
3-deep chained cascade (invalidating `p` withdraws `p`, `q`, AND `q and r`).
`crossengin_chat` compiles with all five formal commands (`/axiom /imply
/derive /and /andl /andr`) wired and the pre-existing `/prove` untouched.

**Increment 12 (landed): a wider propositional rule set.** The kernel's term
language gains OR and IFF (every connective is now a uniform binary
`[kind, left, right]`, so `term_eq` handles them with one recursive case), and
the rule set gains -- all with NO assumption-discharge machinery, so each stays
a single structurally-obvious check the trusted core's reader can verify:
disjunction introduction (`OR_IL` / `OR_IR`: `L |- (L or R)`), biconditional
introduction + both eliminations (`IFF_I` from the two directions, `IFF_EL` /
`IFF_ER` recovering each), and hypothetical syllogism (`HS`:
`(A->B),(B->C) |- (A->C)`). The dep-recording walker recurses into the new
rules' children, so HYP edges inside them participate in cascade + re-check.
The chat seam exposes the two highest-value chaining forms: `/hs C AB BC`
(compose implications) and `/iff C AB BA` (form an equivalence); a composed
implication can itself be a premise in a further `/hs`, and it cascades when a
source implication is withdrawn. Verified via the bootstrap: `verify` 45 checks
(each new rule accepts a valid derivation and rejects unsound variants -- a
mismatched disjunct, a non-mirroring IFF, a broken HS middle term or wrong
endpoints) and `formal_chat` 47 checks (HS composes + chains on a derived
implication; middle-term mismatch + non-mirror IFF -> REJECTED; a composed
implication cascades when its source is pulled). `crossengin_chat` compiles with
all seven formal commands (`/axiom /imply /derive /and /andl /andr /hs /iff`)
wired.

**Increment 13 (landed): cross-session persistence (re-checkable).** Persisting
a FORMAL atom's GRADE alone would be unsound -- on reload it would claim
theorem-grade with no re-checkable derivation behind it, breaking "the pin is
conditional on re-checkability". So `src/mind/proof_serial.nova` serializes the
DERIVATIONS (terms + proof trees, a flat newline-tagged stream parsed by
recursive descent, no str_eq), and `fc_snapshot` / `fc_restore` round-trip the
whole formal environment in assertion order. Restore RE-RUNS THE KERNEL on each
derivation (re-earning every FORMAL grade from verified ground) rather than
trusting persisted state: a tampered persisted proof simply fails to re-verify
and is not re-pinned. The env entry now also carries its verification packet +
source so the derivation can be re-serialized; the restore rebuilds each proof's
HYP context from the env-so-far. The chat exposes `/fsave [PATH]` and `/fload
[PATH]` over the same durable-write path snapshots use. Verified via the
bootstrap: `proof_serial` 11 checks (term/proof round-trips; a parsed proof
still verifies; a parsed BOGUS proof still fails -- serialization launders
nothing) and `formal_chat` 58 checks (a 5-proposition env snapshots + restores
into a fresh registry/KG with all grades FORMAL again; a restored theorem still
CASCADES when its root is withdrawn -- the dep edges were rebuilt by re-running
the kernel, not copied; a hand-tampered snapshot entry is refused on restore).

**Increment 14 (landed): the formal store rides /save and /load.** The formal
sidecar is now folded into the main chat snapshot path: `_admin_save` writes the
formal env to a `<snap>.formal` file beside the snapshot whenever something
formal was asserted, and `_admin_load` reads it back AND re-runs the kernel over
each persisted derivation. So the snapshot's FORMAL atoms (which carry grade +
pinned belief in the KGS section) are kept re-checkable -- a `/load` re-proves
them rather than trusting them, and a corrupted `.formal` sidecar can never
smuggle a false theorem into the loaded session. The standalone `/fsave` /
`/fload` remain for manual control. Verified: `crossengin_chat` compiles with the
fold wired (the formal modules' behaviour is unchanged from increment 13 --
`formal_chat` 58, `proof_serial` 11 still green).

**Increment 15 (landed): ground arithmetic -- "2+2=4 with a checkable proof".**
The kernel's term language gains numeric literals + `+` / `*` expressions and an
equality PROPOSITION, plus one new rule `EVAL` that DECIDES a ground equality by
RECOMPUTING both sides and comparing (`_eval_arith`, the standard total recursive
evaluation). It stays a small trusted addition because the computation IS the
justification: EVAL cannot accept a false equality (`3+3=7` fails, `6 != 7`) or a
non-arithmetic claim (eval refuses atoms/connectives), so soundness is obvious
from reading the one branch. Serialization (proof_serial) round-trips the new
terms + EVAL, so arithmetic theorems persist + restore like any other. The chat
seam is `/calc L A op B C` (e.g. `/calc t 2 + 2 4`); a false sum is refused, not
pinned. The reasoning benchmark's default bank gains `2+2=4` (proven) and
`2+2=5` (refused) -- the canonical ADR-0093 example, where the engine cannot be
argued into `2+2=5` and an LLM can. Verified via the bootstrap: `verify` 55
checks (true equalities verify incl. nested `(2+3)*4=20`; false + non-arithmetic
rejected; numeric term_eq by value), `proof_serial` 14 (arith + EVAL round-trip
still verifies; a restored false EVAL still fails), `formal_chat` 63 (`/calc`
proves true sums/products, refuses `3+3=7`), `reasoning_bench` 27 (9-item bank,
6 proven incl. arithmetic, still SOUND). Bounded to ground (variable-free)
arithmetic in the safe integer range -- no overflow checking, the honest scope.

**Increment 16 (landed): subtraction + exact division.** Rounds out the four
operations: `TERM_SUB` / `TERM_DIV` join add/mul in `_eval_arith`. Subtraction
handles negatives (`5 - 8 = -3` verifies). Division is EXACT-only: a zero
divisor or a non-even quotient evaluates to "undefined" (not-ok), so `7 / 2 = 3`
is REFUSED -- the engine never rounds `3.5` into a false equality, the sound
choice. Serialization gains the `s` / `d` tags; the `/calc` seam parses `-` and
`/`; the benchmark bank gains `6/2=3` (proven) and `7/2=3` (refused, inexact).
Verified: `verify` 60 (sub incl. negatives; exact div verifies; inexact + div-
by-zero refused), `proof_serial` 15 ((10-4)/2=3 round-trips + verifies),
`formal_chat` 66 (`/calc` sub/div proves the exact ones, refuses the inexact),
`reasoning_bench` 27 (11-item bank, 7 proven, still SOUND). `crossengin_chat`
compiles with the full `{+,-,*,/}` /calc.

**Increment 17 (landed): first-order quantifiers (bounded, sound).** The kernel
gains variables, predicate application, and ∀/∃ terms, plus substitution
(`_subst`) -- and exactly the two quantifier rules that need NO eigenvariable
condition or assumption discharge: **universal instantiation** (`∀x.B ⊢ B[x:=t]`)
and **existential introduction** (`Q[x:=w] ⊢ ∃x.Q`). Both are unconditionally
sound; instantiation/witness terms are restricted to CLOSED terms so the simple
(non-renaming) substitution cannot capture. Universal generalization +
existential elimination are DELIBERATELY omitted (they need discharge +
freshness, which would materially grow the trusted core -- the small-kernel
principle). Substitution is the one new trusted piece, a standard recursion.
The whole first-order syllogism is machine-checked end-to-end: `∀x.(human(x) ->
mortal(x))`, `human(socrates)` ⊢ `mortal(socrates)` via UI then MP. The chat
seam exposes `/forall L P1 P2` (a universal law), `/fact L PRED CONST`, and
`/syllogism C LAW FACT` (UI + MP in one step); serialization round-trips the new
terms + UI/EI so quantified theorems persist + re-verify. Verified via the
bootstrap: `verify` 75 (UI/EI accept valid, reject wrong substitution + open
instantiation + witness mismatch + non-forall; the Socrates syllogism;
quantifier term_eq), `proof_serial` 18 (quantified term + UI/EI round-trip +
re-verify), `formal_chat` 73 (the `/syllogism` Socrates demo, a mismatched fact
refused, the derived predicate theorem persists + restores), `reasoning_bench`
40 (12-item bank incl. a UI item, still SOUND).

**Increment 18 (landed): bounded proof SEARCH (the v2 "construct, don't only
check").** `src/mind/search.nova` forward-chains over known premises to
CONSTRUCT a proof of a goal -- but the search is UNTRUSTED: it builds candidate
proof objects, and `verify_check` remains the sole gate, so however heuristic or
incomplete the search is it can never yield a false theorem (the LCF discipline:
an untrusted tactic proposes, the trusted kernel disposes). Strategy: saturating
forward chaining to a budget -- seed with the premises (AXIOM), then apply MP /
HS / AND-elim / universal-instantiation-at-supplied-constants, deduping derived
[term, proof] pairs by `term_eq`, until the goal appears, a fixpoint is reached,
or the budget is spent. `search_prove_ok` searches AND kernel-confirms. The chat
seam is `fc_can_derive` / `/search PRED CONST`: ask the engine to AUTO-DERIVE a
goal from everything in the formal env (it collects the env's propositions as
premises + the constants to instantiate at). The Socrates conclusion is now
found with NO supplied derivation. Verified via the bootstrap: `search` 11
(Socrates auto-derived + kernel-confirmed; MP chains; HS; AND-elim; trivial
goal; an UNPROVABLE goal returns 0 -- the soundness property; budget
incompleteness stays sound), `formal_chat` 76 (`/search` derives
mortal(socrates), declines immortal(socrates) and mortal(plato)). Incomplete by
design (no backward search / no unification beyond ground instantiation) -- it
finds the shallow mechanical derivations v1 search scopes for.

**Increment 19 (landed): universal generalization (UG), with the eigenvariable
condition.** The one ∀-introduction rule that is tractable WITHOUT assumption
discharge: from a proof of `B[x:=c]` for an eigenconstant `c`, conclude
`∀x.B` -- but only if `c` is genuinely arbitrary. Soundness is entirely in the
side conditions the kernel checks: (a) `c` is a constant; (b) `c` does not occur
in the body `B` (total, not partial, generalization); (c) `B[x:=c]` is exactly
the sub-proof's conclusion; and (d) THE EIGENVARIABLE CONDITION -- `c` occurs in
NO axiom or hypothesis the sub-proof depends on (`_proof_uses_const` walks the
proof's AXIOM/HYP leaves; it deliberately ignores UI-instantiation/EI-witness
terms, since instantiating a universal AT the fresh `c` is legitimate). Without
(d) one could "prove" `∀x.P(x)` from a single axiom `P(c)` -- the classic
unsoundness, now explicitly forbidden and tested. Real new power: `∀x.(P(x)->
Q(x)), ∀x.P(x) ⊢ ∀x.Q(x)` (UI both at a fresh `c`, MP, UG). Serialization gains
the `G` tag. Verified via the bootstrap: `verify` 79 (UG from a single instance
REJECTED; the valid all-P-are-Q derivation; partial-generalization rejected; UG
over a HYP mentioning `c` rejected) and `proof_serial` 19 (UG round-trips +
re-verifies, eigenvariable check intact).

**Increment 20 (landed): overflow safety -- a soundness guard for arithmetic.**
Without it the EVAL decision procedure had a real hole: a large product could
silently wrap 63-bit and EVAL would "verify" a mathematically false equality
(recomputing the SAME wrong value on both checks). `_eval_arith` now detects
overflow per operation -- add/sub by signed wrap detection (same-sign sum that
flips sign; a difference that moves the wrong way), mul by the self-validating
exactness check (`p / a == b`, which catches wrap AND the backend's large-
multiply miscompile). An overflowing expression evaluates to UNDEFINED, so EVAL
REFUSES it rather than asserting a wrong result -- incompleteness, never
unsoundness. Verified via the bootstrap: `verify` 82 (a safe `1e6*1e6=1e12`
still verifies; `2^32 * 2^32` is refused for ANY claimed RHS, including a
plausible one). Bounded-but-honest: equalities the engine cannot compute exactly
are declined, not guessed.

**Increment 21 (landed): existential elimination (EE) -- the discharge rule.**
The last major inference rule, and the one that genuinely grows the trusted core
(deferred until now precisely because it needs assumption DISCHARGE). From a
proof of `exists x.P` and a sub-derivation of `C` that may ASSUME `P(c)` for a
fresh eigenconstant `c`, conclude `C`. The assumption is a temporary HYP carrying
the kernel-internal sentinel `EE_ASSUMED`, inserted into the hyp context ONLY for
the sub-derivation and discharged by the EE step -- it cannot leak (no caller
ever puts EE_ASSUMED in the top-level context; a dangling HYP at top level fails,
tested). Soundness rests on: (a) `c` is a constant; (e1) the premise is really
`exists x.P`; (b) `c` not in the existential; (c) `c` not in `C` (the witness
cannot leak into the conclusion); (d) the sub-derivation concludes exactly `C`
under `P(c)`; (f) the EIGENVARIABLE CONDITION -- `c` occurs in no axiom or
*other* (non-discharged) assumption the sub-derivation uses (`_proof_uses_const`
gained an `except_label` so the discharged `P(c)` is exempt). Verified via the
bootstrap: `verify` 87 (the valid `exists x.P(x) + all-P-imply-q |- q`; concluding
`P(c)` REJECTED -- witness leak; an eigenvariable violation via a c-mentioning
axiom REJECTED; non-existential premise REJECTED; a dangling top-level HYP
REJECTED), `proof_serial` 20 (EE round-trips with its discharged label +
re-verifies). The first-order rule set is now complete: UI, EI, UG, EE.

**Honest note on the trusted core:** EE is the one rule whose soundness is not a
single local structural match -- it requires the scoped-assumption mechanism +
the eigenvariable walk. It remains auditable (the EE branch + `_proof_uses_const`
+ the EE_ASSUMED HYP special-case are all readable in one sitting), but it is the
deliberate, documented exception to the "every rule is a one-line check"
discipline -- which is why it came last.

**Increment 22 (landed): backward (goal-directed) proof search.**
`src/mind/search_back.nova` complements the forward saturating search with a
goal-directed prover: `sb_prove(premises, goal, budget)` recurses on the goal
(AXIOM match / AND-intro / MP via a premise `A->goal` / AND-elim), decrementing
budget per call so cyclic premises terminate. Like all search it is UNTRUSTED --
`sb_prove_ok` gates the result through `verify_check`. Verified: `search_back`
10 checks (trivial; MP chain; AND-intro; AND-elim; unprovable -> 0; cycle
safety).

**Increment 23 (landed): arbitrary-precision integer library.**
`src/mind/bignum.nova` -- signed bignums as `[sign, d0, d1, ...]` base-10000
little-endian digit lists (digit products <= 1e8, within NOVA's safe range):
bn_from_int/str, bn_to_str, bn_cmp, bn_eq, bn_add, bn_sub, bn_mul. The building
block for arithmetic beyond the 63-bit safe range, kept STANDALONE (not yet
wired into the kernel's TERM_NUM -- that integration is a separate, careful
step, since it would touch the trusted arithmetic core). Verified: `bignum` 39
checks (round-trips incl. a 30-digit value + negatives; carry/borrow across
base; (10^20-1)^2; self-checking identities).

**Increment 24 (landed): LLM transcript ingestion + bench wiring.**
`src/bench/llm_transcript.nova` ingests RECORDED LLM verdicts (one
`<id> <affirm|deny>` per line, `#` comments) so a real captured transcript can
drive the head-to-head instead of hardcoded illustrative values:
llm_transcript_parse / llm_verdict_for / llm_transcript_from_file (the file read
mirrors `_dl_read_text`; file syscalls are disabled in this sandbox -- the same
limit that disables `test_decision_log_durable` -- so the file path is compile-
verified and the parse pipeline is exercised inline). `reasoning_bench` gains
`bench_compare_transcript(reg, transcript)`, pairing the default bank with the
transcript's verdicts by item id (missing -> LLM_DENY). Verified: `llm_transcript`
6 checks (inline parse, lookups, default); `reasoning_bench` 45 (incl. a
transcript-driven head-to-head: engine all-correct + zero false proofs, LLM
>=1 false-confident).

**Scope still open:** wiring bignum into the kernel's `TERM_NUM` for unbounded
arithmetic (the standalone library is the building block); non-ground
unification in search (the current forward/backward searches are ground +
structural); and CAPTURING real LLM transcripts (the ingestion path is ready;
the data is the missing piece). The chat wiring is single-session-scoped (the
`rcks` + formal env hold the boot session's state), the same scope cut the
audit-log wiring carries.
