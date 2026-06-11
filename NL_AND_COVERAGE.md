# Natural Language & Coverage Roadmap

> **Purpose.** A self-contained, execute-in-a-session plan to (N) deepen
> CrossEngin's natural-language capability and (C) close the remaining
> unit-test coverage gaps and raise coverage quality. Companion to
> `ENHANCEMENTS_ROADMAP.md` (P1–P5 + capstone, ADRs 0051–0057), which left the
> substrate an always-on agent; this roadmap sharpens the language surface it
> reasons and converses through, and locks it down with tests.
>
> **Discipline (unchanged from the P1–P5 work).** Every change additive and, where
> risky, behind a flag; every change ships unit tests; keep the affected-test
> sweep green (the full `make test` still can't run here — the NOVA compiler
> hangs on the unrelated `src/federation/dtls12.nova` — so verify per-module +
> reverse-deps, as throughout). One ADR per new subsystem. Honest-gaps section
> in each ADR.

---

## Coverage baseline (measured 2026-06-11)

A module counts as *covered* iff some `tests/unit/*.nova` imports it.

- **238 source modules; 232 covered.** The entire NL stack —
  `language/` (word/phoneme/syntax atoms, arithmetic), `reader/` (the 5-stage
  reader, context-bias, lexical-anchor, spreading-activation, slot/cofire
  indexes, coherence, neighborhood, fetch-route-learn), `chat/`, `perception/`,
  plus `kg/` (incl. `query`, `temporal`), `learning/` (incl. `openie`,
  `entity_resolve`, `preprocess`), and `safety/` — is covered.
- **6 genuinely-untested modules**, all I/O transducers/effectors whose *device/
  socket* paths are integration-only but whose *pure logic* (shell quoting, IP
  parsing, framing, seam state + decoder registries, accessors) is unit-testable:
  `io/effectors/audio_speak`, `io/transducers/stream_audio`,
  `io/transducers/stream_http`, `io/transducers/stream_unix_socket`,
  `io/transducers/video_perception`, `io/transducers/visual_perception`.

So coverage is *nearly complete*; the work is (C) closing those 6 pure-logic
gaps, then (N) adding NL capability — each new NL unit fully tested as it lands.

---

## Track C — Coverage

### C1 — close the 6 untested I/O modules  *(DONE 2026-06-11, ADR-0058)*

> **STATUS: complete.** Coverage is now **238/238** (0 untested). New suites
> covering the pure logic: `test_stream_http` (20), `test_audio_speak` (6),
> `test_stream_audio` (10), `test_stream_unix_socket` (14),
> `test_video_perception` (11), `test_visual_perception` (12) — 73 checks, no
> production module changed. Closing the gap surfaced a latent NOVA-codegen-#11
> overflow in `stream_http`'s `_stream_http_ip_to_int` for 4th octets ≥ 16
> (documented in ADR-0058 "Honest gaps"; fix deferred).

Unit-test the pure, deterministic logic of each (no real sockets/audio/video):
- `audio_speak`: `_shell_quote_single` correctness (quotes, embedded `'`,
  injection safety), argv construction shape.
- `stream_http`: `_stream_http_is_digits`, `_stream_http_ip_to_int` (dotted-quad
  → int, bounds), `stream_http_new` state + accessors/counters.
- `stream_audio`, `stream_unix_socket`: `*_new` state, enabled/initialized
  gates, accessors (the env-gated lifecycle's pure parts).
- `video_perception`, `visual_perception`: seam `*_new`, builtin-decoder
  registry (`*_register_builtin`, `*_decoder_name`), default-decoder selection,
  enabled gating, last-result accessors.
- **Acceptance:** all 6 modules imported + asserted by a new
  `tests/unit/test_<module>.nova`; the integration-only paths are documented as
  such. (ADR-0058.)

### C2 — coverage quality + tracking
- A `make`/script target (or doc) that reports covered/uncovered module counts.
- Raise assertion depth on any thin suite surfaced while doing C1/N work.

---

## Track N — Natural-language depth

Concrete, KG-grounded, fully-unit-testable capabilities built on the existing
reader / word_atoms / openie / query stack. Execute after C1, one per phase.

### N1 — NL question → structured KG answer  *(keystone of this track)*
A bridge from a natural-language question to a `query.nova` query (or a direct
KG lookup) and back to an answer atom. Classify the question form
(yes/no vs wh- : what/who/where/when/how-many), extract the focus entity +
relation via the OpenIE/word-atom layer, resolve the entity (P3
`entity_resolve`), run the query, and render a confidence-qualified answer
(reusing the R74 confidence machinery). **Acceptance:** "what is X" / "is X a Y"
/ "how many Z" answered from a seeded KG with provenance; unit-tested end to end.

### N2 — number-words & units → value
`"three hundred"`, `"a dozen"`, `"2.5 kg"` → milli values feeding
`arithmetic.nova` and table/measure ingestion. Pure, deterministic, fully tested.

### N3 — OpenIE depth: negation, coordination, coreference
Carry negation as a polarity flag (not silent drop), split coordinated objects
("X has A and B" → two triples), and resolve simple intra-sentence pronouns
("it"/"they") to the subject (extending the R75 anaphora work). Confidence-gated.

### N4 — NL generation quality
Render KG facts / reasoning chains as fluent clauses (subject–relation–object
with article/agreement), not template fragments; tie into the chat reply path.

---

## Sequencing
```
C1 coverage closure  ──►  N1 NL Q&A bridge  ──►  N2 number-words
                                                      │
                          N4 NL generation  ◄──  N3 OpenIE depth
```
Do C1 first: a green, fully-covered base makes the NL additions safe to layer.

## What this roadmap does NOT claim
- Not a parser/LLM. N-track stays shallow-heuristic + KG-grounded (the project's
  no-LLM-cognition invariant), gradient-free and auditable.
- The 6 I/O modules' *device* paths remain integration-tested only; C1 covers
  their pure logic, not real audio/video/socket round-trips.
