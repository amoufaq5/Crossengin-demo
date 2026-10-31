# ADR-0108: Style Capsules — persona-owned rendering variants

## Status

Proposed (R52)

## Date

2026-08-15

## Context

R48p4 shipped `src/nl/templater.nova`, the deterministic
ProposalResult → English renderer. It ships with an inline default
style: `Sources cited (N atoms):`, `⚠ Sources disagree on 'X'`,
`Persona projection: valence +425, arousal 200, risk 500/1000.`,
`Would perform (described, not executed):`, `Confidence: C/1000  |
parser: P  |  style: S`.

Two things drove the style-capsule idea from day one:

1. **Persona is per-user.** Different users legitimately want
   different phrasings. An operator wants terse output; a formal
   audit context wants full sentences; a chat UI wants
   bullet-friendly output; a screen-reader wants headings.
2. **The templater is deterministic.** Templater guarantees "same
   input → same output, forever." A style capsule must NOT break
   that: same PR + same style capsule → same string. Determinism
   moves to (PR, style) rather than PR alone.

R48p4 hardcoded ONE style. Users have no dial. The
`persona_style_capsule(p)` field exists (R46), the templater's
trailer says `style: <name>`, but nothing consults the ref to
actually change wording.

R52 closes that gap.

## Decision

Introduce **Style Capsules** as a capsule subtype (per ADR-0106).
A style capsule is a data object holding a set of **rendering
knobs** — small strings and flags the templater reads to compose
output. The templater's structural pipeline (which sections it
produces, in what order) stays fixed; only wording + presence
flags vary.

### Style knobs (v1)

Every style capsule declares these knobs. Missing knobs fall back
to `default`. Knobs are DATA, not code — no template language, no
placeholder substitution language (we tried, it makes the
templater harder to audit than the wording it renders).

| Slot | Meaning | Example (default) |
|---|---|---|
| `NAME` | Style capsule name | `"default"` |
| `BULLET` | Prefix for list items | `"  - "` |
| `ANSWER_HEADER` | Header before the proposal body (empty = omit) | `""` |
| `SOURCES_HDR_1` | "Sources cited (" | `"Sources cited ("` |
| `SOURCES_HDR_2_SING` | ") for singular" | `" atom):\n"` |
| `SOURCES_HDR_2_PLUR` | ") for plural" | `" atoms):\n"` |
| `SOURCE_KG_OPEN` | KG-name delimiter open | `"["` |
| `SOURCE_KG_CLOSE` | KG-name delimiter close | `"] "` |
| `SOURCE_BELIEF_PREFIX` | Belief label | `": belief "` |
| `SOURCE_BELIEF_SUFFIX` | Belief unit | `"/1000"` |
| `DISAGREE_MARKER` | Warning glyph/prefix | `"⚠"` |
| `DISAGREE_HDR_1` | "Sources disagree on '" | `" Sources disagree on '"` |
| `DISAGREE_HDR_2` | "' (spread " | `"' (spread "` |
| `DISAGREE_HDR_3` | " milli, " | `" milli, "` |
| `DISAGREE_HDR_4` | " sources)." | `" sources).\n"` |
| `PROJECTION_LABEL` | Advisory header | `"Persona projection: valence "` |
| `PROJECTION_MID_1` | ", arousal " | `", arousal "` |
| `PROJECTION_MID_2` | ", risk " | `", risk "` |
| `PROJECTION_SUFFIX` | Trailer for projection line | `"/1000.\n"` |
| `EFFECTOR_HDR` | "Would perform (described, not executed):" | `"Would perform (described, not executed):\n"` |
| `TRAILER_HDR_1` | "Confidence: " | `"Confidence: "` |
| `TRAILER_HDR_2` | " / parser: " | `"/1000  \|  parser: "` |
| `TRAILER_HDR_3` | " / style: " | `"  \|  style: "` |
| `SHOW_SOURCES` | List sources? | `1` |
| `SHOW_DISAGREEMENTS` | Callout disagreements? | `1` |
| `SHOW_PROJECTION` | Show projection line? | `1` |
| `SHOW_EFFECTORS` | Show effector calls? | `1` |
| `SHOW_TRAILER` | Show confidence/parser/style trailer? | `1` |

The knob list is intentionally boring. A future style capsule that
wants a NEW behavior (e.g. wrap URLs, add HTML tags) is a NEW knob
with a `default` fallback, not a new template language. That keeps
the templater auditable — a reader of the templater can enumerate
every knob it reads.

### Built-in styles (v1, ship-ready)

- **`default`** — matches R48p4 verbatim. Zero user-visible drift
  from what existing tests + audit trails expect.
- **`terse`** — ASCII-only bullets `"- "`, no disagreement / no
  projection / no trailer sections. One-liner header
  `"Answer:"`. For chat UIs where the wire also delivers the
  structured payload separately.
- **`formal`** — long-form academic wording:
  `"Sources consulted ("`, `"Note: sources differ on '<X>'"`,
  `"Advisory factors:"`, compact trailer.

### Lookup path

`persona.style_capsule_ref` (a string, empty for default) is the
key. The templater does:

```
style_ref = persona_style_capsule(persona)  // "" if no persona / no ref
knobs     = style_registry_lookup(style_ref)  // 0 if unknown -> use default
render_using(knobs, pr)
```

An unknown style name falls back to `default` (with a trace crumb
in the log so operators see the miss); no crash, no refusal.

### The 5 ADR-0103 guarantees, preserved

Style capsules NEVER change:
1. Refusal shape (refusal wording may vary; refusal existence does not)
2. Persona projection PRESENCE (may hide the LINE but the
   projection is still on the ExecutionResult for the RPC layer)
3. Effector-calls PRESENCE (may hide the LINE; the calls stay in
   `proposal.effector_calls` on the wire)
4. Meta-observer attribution (skill_run controls that; style
   capsules don't touch atoms)
5. Persona read-only (templater reads the capsule name; capsule
   itself is a static data object)

So a style capsule can HIDE information from a rendered answer,
but the underlying ExecutionResult that the wire (RPC) returns is
unchanged. Client code that wants the structured data (a UI
rendering source chips, an audit reader) reads `atoms[]`,
`effector_calls[]`, `projection` directly — style capsules don't
gate access to those.

## Options Considered

1. **Data knobs (CHOSEN, this doc).** Wordings + flags. Boring.
   Auditable. No template DSL to learn or defend.
2. **A tiny template DSL** (e.g. Jinja-lite). Rejected: adds a
   syntax to parse, adds an evaluator to secure, adds a way to
   silently break determinism (a bug in the evaluator changes
   every rendered answer).
3. **Style as a full skill.** The templater would invoke a "style
   skill" that produces the string. Rejected: overkill. The
   templater is deterministic and cheap; skills are for reasoning.
4. **Style baked into the persona.** Rejected: same style should
   be shareable across users (a team standardizes on `formal`),
   and capsules are the sharing primitive already (ADR-0106).
5. **Per-user templater subclass.** Rejected: adds subclassing
   pattern to a codebase that has none.

## Consequences

- **Positive:** Users can change how CrossEngin talks to them
  without touching cognition. Personas ship with a style name.
- **Positive:** Templater stays deterministic (same PR + same
  style → same output).
- **Positive:** Auditable knob list — reviewers can enumerate
  every string a style controls.
- **Positive:** Zero regression risk for the `default` style.
  Existing tests keep passing byte-identically (verified: all
  60 templater checks still green after refactor).
- **Neutral:** Adds one module (`src/capsules/style_capsule.nova`)
  and refactors the templater to consult knobs. ~250 lines.
- **Negative:** The knob list is broad. A style that wants a
  qualitatively different shape (JSON output, HTML output) needs
  more than knobs — that's a new templater kind, tracked as
  R55+ (templater subtypes: text, HTML, JSON).
- **Negative:** No hot-reload. A style change requires re-running
  the templater; persona-swaps a style ref, next render picks it
  up. Fine for the current chat / RPC surface.

## Registration + discovery

A style capsule is a `Capsule` per ADR-0106 with an extra data
payload: the knob list. The capsule registry stores them
alongside knowledge capsules; the `style_registry_*` module scans
the capreg for `capsule_kind == CAPSULE_KIND_STYLE` and indexes
them by name.

For v1, the three built-in styles (`default`, `terse`, `formal`)
are pre-registered when the style module is imported. External
style capsules can register via the same API (or eventually via
a `.style` payload in a `.cerec` pack).

## Wire integration

The RPC verb `persona.show` already returns `style_capsule` on
the persona record. No wire change needed. A client that wants
to LIST available styles adds a new verb (`style.list`, R53+); for
v1 that inventory lives in the operator docs.

## Ship-as-app checklist for R52

- [x] ADR-0108 (this document)
- [x] `src/capsules/style_capsule.nova` — knob type + registry +
      3 built-ins
- [x] Templater refactored to read knobs from the current style
- [x] Tests: 3 styles render deterministically, unknown-style
      falls back to default, sections respect SHOW_* flags
- [x] All 60 existing templater checks pass unchanged (default
      style renders byte-identically to R48p4)

## Role in the Model Substrate

Style Capsules serve the consumption modes with a rendered surface
— client-app (mode 4) most visibly, per-user selective-load (mode
2) via `persona.style_capsule_ref`, embedded (mode 5) when the
device presents text, and mother-daemon-direct (mode 1) whenever
the operator uses the NL layer. Baked-child instances (mode 3)
ship with a style-capsule-set allowlist alongside the persona set.

Style Capsules are NOT part of the reasoning triad. They configure
the **NL surface** — specifically the deterministic templater
(ADR-0104 Component 4) — with the wording knobs that vary phrasing
without varying content. This split is what lets the LLM-free
primary NLP path stay LLM-free: style variation is data (knob
strings), never a generative call, so the sidecar LLM (ADR-0201)
adds no expressiveness the deterministic templater lacks — it only
covers phrasings the grammar has not yet parsed. Style is thus the
audit-safe surface for tone and register while the substrate below
stays byte-deterministic.

**See also:** ADR-0211 (LLM-free NLP primary path — style capsules
are the phrasing dial the deterministic templater reads), ADR-0201
(sidecar LLM adapter — must respect the same slot-only render
contract style capsules define), ADR-0208 (bake manifest persona +
style set), ADR-0200 (five consumption modes — style capsules
serve every rendered surface).
