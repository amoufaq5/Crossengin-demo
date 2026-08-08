# ADR-0107: Pattern Capsules — reusable heuristics for skills

## Status

Proposed (R53)

## Date

2026-08-15

## Context

Skills produce ProposalResults. The reference skills so far:

- `echo_skill` — trivial; no heuristics
- `research_skill` — walks KGs, aggregates beliefs, surfaces
  cross-KG conflicts. No heuristics beyond the belief-spread
  threshold.
- `coding_helper` — declared but stub-body; explicitly waits on
  ADR-0107 (this doc) because the intended policy is
  "walk a set of debug-methodology patterns and compose a
  proposal from the ones that match the user's problem"

`coding_helper` is the motivating case: writing "step 1: reproduce;
step 2: isolate; step 3: hypothesize" INSIDE the skill code
hardcodes the methodology and makes it un-shareable. If two skills
want to reuse "reproduce → isolate → hypothesize → test → verify",
they duplicate. If someone wants to add a "check-recent-diff"
step, they edit code.

**Pattern Capsules** are the sharing primitive that fixes this.
A Pattern Capsule is a named, versioned, shareable collection of
**patterns** — reusable (trigger, guidance) fragments a skill's
policy consults at run time. A skill's cognition stays a skill
concern; the KNOWLEDGE it applies (which heuristics, in what
order) lives in a capsule.

This mirrors how domain packs work: `research_skill` doesn't hardcode
knowledge; it walks the KG. `coding_helper` shouldn't hardcode
methodology; it walks a pattern capsule.

## Decision

Ship **Pattern Capsules** as a capsule subtype (per ADR-0106).
Each pattern capsule holds a list of **Patterns** where a Pattern
is a 4-tuple:

```
Pattern = [trigger_tokens, guidance, source_tag, confidence]
```

| Field | Meaning | Example |
|---|---|---|
| `trigger_tokens` | lowercased content tokens; ALL must appear in perception for a match | `["null", "pointer"]` |
| `guidance` | human-readable advice/step text the skill weaves into its proposal | `"NULL deref: check the caller for an initialization that only fires on the success branch."` |
| `source_tag` | provenance stamp (goes on any observation the skill records via meta_observer) | `"src:pattern:debug_common:v1"` |
| `confidence` | 0..1000 milli; higher = stronger heuristic; used for match ordering + skill's overall confidence | `700` |

A **Pattern Registry** holds multiple capsules keyed by name, with
process-wide lazy init.

### Matching

`pattern_registry_match(perception_tokens, [capsule_filter])`
walks the registered capsules (all if `capsule_filter` is empty;
otherwise the named subset), tests each pattern's triggers
against `perception_tokens` (ALL-tokens-present match — grammar-
parser-style tokenization), returns the matching patterns sorted
by `confidence` descending.

Match is deterministic: same tokens + same registry → same list.
Skills that lean on patterns inherit that determinism.

### The 5 ADR-0103 guarantees, preserved

Pattern capsules can NEVER:

1. Cause a false-positive success on a refused policy (patterns
   only add guidance TO a proposal; they don't turn refusals
   into approvals)
2. Attach to a persona (patterns are shared, personas are per-
   user; a pattern's `source_tag` is the audit provenance)
3. Dispatch effectors (patterns are text; effector calls are
   still described-not-executed by the skill's policy)
4. Skip meta_observer attribution (the skill's supervisor still
   tags every touched atom; the pattern's `source_tag` is an
   ADDITIONAL parser-side tag, distinct from the skill's tag)
5. Mutate persona / atoms / KGs (patterns are read-only data)

### Built-in pattern capsules (v1, ship-ready)

Two starter capsules ship with R53 so `coding_helper` has content
to consult on install and so `research_skill` picks up a
methodology hint layer:

**`debug_common` v1.0.0** — general-purpose debug heuristics:

- `["null", "pointer"]`      NULL deref: check init-only-on-success path
- `["null", "reference"]`    same, JVM-flavored wording
- `["off", "by", "one"]`     off-by-one: check loop bounds + slice ends
- `["undefined", "variable"]` undefined var: check scope + shadowing
- `["hang", "loop"]`          hang: check the exit condition variable
- `["stack", "overflow"]`     recursion base case / iteration depth
- `["race", "condition"]`     race: check shared state + lock scope
- `["memory", "leak"]`        leak: check ownership + destructor path
- `["type", "error"]`         type: check the call-site + coercion
- `["timeout"]`               timeout: check the network / DB retry path
- `["permission", "denied"]`  perms: check the running user / file ACL

**`research_hygiene` v1.0.0** — research-flow reminders:

- `["single", "source"]`      cross-check at least one more source
- `["contradiction"]`         name both KGs; compute belief spread
- `["recent"]`                prefer sources with fresher timestamps
- `["quote"]`                 prefer primary over secondary quotation
- `["belief", "low"]`         hedge: report as "some evidence suggests"

Both capsules are DATA. They can be replaced (a shop with strict
debug workflows registers `debug_shop_x_v3` and points its skills
at that name via a manifest field, R54+).

### Coding-helper wiring

`coding_helper_policy` becomes:

```
tokens = tokenize(problem_description)
matches = pattern_registry_match(tokens, ["debug_common"])
if len(matches) == 0:
  → confidence 0, "no matching debug pattern; describe the problem in more terms"
else:
  → weave top-N (default 5) patterns into proposal, ranked by confidence
  → set proposal confidence to max(matched.confidence)
  → source_tag on the trace so audit sees which capsule contributed
```

The stub "policy pending" message goes away — the skill now
does real work as soon as `debug_common` is installed.

### Cross-capsule registration

Pattern capsules and Style capsules (ADR-0108) are two capsule
subtypes with SEPARATE registries. That's deliberate:

- Style capsules answer "how do we RENDER the answer"
- Pattern capsules answer "what HEURISTICS did we consult"

They compose but don't share a lookup path. A future ADR could
unify under `capreg_capsules(reg)` with a `capsule_kind` field;
for R53 the split registries keep each concern's API small.

## Options Considered

1. **Data patterns (CHOSEN, this doc).** trigger + guidance +
   source + confidence. Boring, auditable, shareable.
2. **Rule-based patterns** (LHS/RHS pairs like a production
   system). Rejected: adds a match engine + evaluation semantics
   the skill supervisor would have to enforce.
3. **Function-object patterns.** A pattern IS a function the
   skill calls. Rejected: opens the door to arbitrary code
   inside a capsule; violates ADR-0106's "capsules are data"
   invariant.
4. **Patterns as atoms in a KG.** Skills already walk KGs; why
   add a new registry? Rejected because pattern matching is
   token-based (not embedding-based), the "kind" of retrieval
   is different, and audit provenance benefits from a distinct
   source_tag namespace (`src:pattern:*` vs `src:pack:*`).
5. **Patterns baked into skill code.** The current status quo
   for `coding_helper`. Rejected because it makes methodology
   un-shareable (see Context).

## Consequences

- **Positive:** `coding_helper` becomes a real skill on the
  first install of `debug_common`. Shape stays a skill (with
  its ADR-0103 guarantees); the KNOWLEDGE it applies is data.
- **Positive:** New heuristics ship as `.pattern.cerec` packs
  without editing any NOVA source (R55+ .cerec pattern parser).
- **Positive:** Provenance for advice: every guidance line
  carries a source_tag, so `/why` (chat) and the wire's
  `proposal.trace` name exactly which capsule contributed.
- **Positive:** Shared methodology: two skills can point at
  `debug_common`; upgrading it upgrades both.
- **Neutral:** Two more modules (~500 lines including tests).
  Registry is a lazy-init singleton like `style_capsule.nova`;
  same shape.
- **Negative:** Token-based matching is coarse. A pattern for
  `["null", "pointer"]` fires on "null pointer to a valid
  region" (technically a false positive). Fine for a heuristic
  system; refinements (negative-token exclusion, phrase
  matching) are R54+ knobs.
- **Negative:** No hot-reload. A registered pattern capsule is
  live for the process. Fine for the current chat / RPC surface
  (both restart cheaply).

## Wire integration

No RPC verb change for R53. `nl.ask` results already carry
`proposal.trace`; pattern-driven policies write their matched
`source_tag` list into the trace, so a client can render "matched
3 patterns from debug_common v1.0.0" without a new endpoint.
`pattern.list` verb waits for R55 (multi-capsule inventory
surfacing).

## Ship-as-app checklist for R53

- [x] ADR-0107 (this document)
- [x] `src/capsules/pattern_capsule.nova` — Pattern + PatternCapsule
      + Registry + 2 built-ins
- [x] `coding_helper` refactored to consult `debug_common` patterns;
      stub message removed
- [x] Tests: pattern shape + registry (lookup, register-replaces,
      is_known), matcher (single-token / multi-token / no-match /
      confidence ordering), coding_helper end-to-end (real proposal
      with matched patterns, source_tag in trace)
- [x] All 60 existing templater checks + 127 style_capsule checks
      + full R48/R49 NL suite pass unchanged
