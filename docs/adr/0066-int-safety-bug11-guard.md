# ADR-0066: int-safety standard + lint guard for NOVA codegen bug #11 (P0)

## Status

Proposed

## Date

2026-06-12

## Context

NOVA codegen bug #11 (documented in `NOVA/NOVA_BUG_THRESHOLD.md`) is the root of
the P0 blocker class. NOVA's "smart-op" dispatch for **exactly eight operators**
— `+  *  <  >  <=  >=  ==  !=` — inspects each operand against `PTR_THRESHOLD =
0x100000` (1,048,576) and, if it looks like a heap pointer, routes the operation
into string-concat / list / strcmp code. Any genuine integer that crosses the
threshold therefore miscompiles to wrong results or a SIGSEGV. (The bitwise
operators `& | ^ ~ << >>` and `-` / `/` / `%` are pure scalar and are **not**
affected.)

This single bug produced four separate P0 symptoms in CrossEngin:

- **stream_http** dotted-quad packing overflow (ADR-0063, fixed).
- **code_review_pack** runtime SIGSEGV (ADR-0064).
- **dtls12** compile-time hang (ADR-0065).
- Plus latent, undiscovered instances anywhere a value can exceed 1 MB.

**Why we do not fix the compiler here.** The genuine fix is a low-bit pointer
tag (all values become 63-bit tagged; `+`/`*`/`==` dispatch on bit 0, not on
magnitude). The NOVA bug doc estimates this at **2–3 weeks of compiler work plus
a bootstrap regeneration and a full self-host sweep**. NOVA is self-hosting and
this environment has no second toolchain; a botched codegen change is
unrecoverable. Raising `PTR_THRESHOLD` is also ruled out (the doc measured the
`brk()` heap starting as low as ~4.5 MB under ASLR, so any raise misclassifies
real pointers). Attempting either inside a feature session would be a
disproportionate, hard-to-reverse risk. The compiler fix is recorded below as a
tracked NOVA work item; this ADR addresses the bug's *blast radius* in
CrossEngin safely and immediately.

## Decision

1. **Bless the `int_*` coding standard** (already partially in use): any
   arithmetic whose operand *or* result can reach `0x100000` must use the
   scalar-only escape-hatch builtins `int_add / int_sub / int_mul / int_div /
   int_mod / int_shl / int_shr / int_and / int_or / int_xor`, never the raw
   smart operators. The raw `+`/`*` stay for their string-concat / list-repeat
   ergonomics only. Documented for developers in `docs/design/int-safety.md`.

2. **Add an automated CI gate** — `scripts/int_safety_lint.py` + `make
   lint-ints`. It statically flags integer literals ≥ `0x100000` used as a raw
   operand of multiplication `*` outside an `int_*` call (the dominant,
   high-signal trigger behind 5 of the 6 historical incidents — LCG multipliers,
   byte packing, accumulators). A reviewed-safe occurrence is silenced with a
   trailing `// int-safe`. Exit non-zero on any unguarded finding, so it gates
   like `make coverage`. Pure static text analysis — no toolchain needed, so it
   runs even while bug #11 still blocks a full `make test`.

3. **Fix the one latent instance the lint surfaced** — the SWIM gossip PRNG
   (`src/federation/gossip.nova`, `_gossip_rng_next` / `_gossip_rng_in_range`):
   a glibc LCG `(x*1103515245 + 12345) mod 2^31`. Both `x` (seeds/feedback ~2^31)
   and the multiplier exceed the threshold, so the raw `*` miscompiled for large
   seeds. Rewritten with `int_mul`/`int_add`/`int_mod` (mathematically
   identical). All three gossip suites — which assert *seeded, reproducible* peer
   picks — stay green (34 + 44 + 61 = 139 checks), confirming the rewrite changed
   no observed behaviour and closed the latent crash for large seeds.

## Consequences

- `make lint-ints` is **clean** across the 126k-LOC tree (zero false positives),
  and is now a green, fast CI gate that catches the multiplication class of bug
  #11 before it ships.
- The known dominant-trigger latent bug (gossip LCG) is closed.
- The four P0 symptoms are each addressed in their own ADR (0063–0065 + this);
  the systemic cause is documented with a concrete compiler-fix design.

## Honest gaps

- **The lint covers the `*`-with-large-literal case only.** It cannot see large
  values carried purely in **variables** (e.g. `a * b` where both are large at
  runtime — the original `stream_http`/`dtls` shapes), nor the rarer
  **two-large-operand** `+`/comparison case. Those remain covered by the `int_*`
  coding standard under code review, not by the automated gate. Widening the
  lint would require range/dataflow analysis.
- **The real fix is still a NOVA toolchain change** (tagged values), tracked
  below and deliberately out of scope here.
- The gossip fix is verified behaviour-identical only over the seed ranges the
  tests exercise; the LCG is mathematically identical for all seeds, but no test
  asserts the >2^20 seed sequence explicitly.

## Tracked NOVA work item (the genuine fix)

`NOVA/src/compiler/codegen.nova` — replace magnitude-based smart-op dispatch with
a low-bit integer tag:
- values become 63-bit; bit 0 = 1 ⇒ integer (shifted, sign-extended), bit 0 = 0
  ⇒ pointer (heap is 8-byte aligned, low bit already 0);
- `+ * == …` dispatch on bit 0; integer ops shift-out/shift-back; pointer
  load/store stay byte-exact; allocator unchanged.
- Effort per the bug doc: ~2–3 weeks + bootstrap regen + full test sweep.
- Alternative: move the allocator to an `mmap` arena at a fixed high address so
  `PTR_THRESHOLD` can be raised safely, retiring the bug class.

## Implementation Notes

- New: `scripts/int_safety_lint.py`, `docs/design/int-safety.md`, `make
  lint-ints` target. Modified: `src/federation/gossip.nova` (two RNG fns).
- Companion ADRs for the individual symptoms: 0063 (stream_http), 0064
  (code_review_pack), 0065 (dtls12).
