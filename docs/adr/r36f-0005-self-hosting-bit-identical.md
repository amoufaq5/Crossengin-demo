# ADR R36F-0005: Bit-identical self-hosting as a regression-detection invariant

## Status
Accepted (R36F) -- ratifies a property of the NOVA toolchain that
CrossEngin depends on. NOVA ADR R36F-0002 covers the NOVA-side
implementation; this ADR is the CrossEngin-side rationale.

## Context
CrossEngin's hot path runs on top of the NOVA compiler. A regression
in `parser.nova` or `codegen.nova` will silently change CrossEngin
behaviour -- maybe a synapse weight drifts by 1 ULP, maybe a list
iteration walks one extra slot. Such bugs are nearly impossible to
catch by visual inspection of compiler diffs because the compiler
diffs and the substrate diffs live in different repos and have very
different shapes.

The classical defence is a large test suite + diff review. The NOVA
test suite is 177 tests at R35; CrossEngin's is 50+ modules. Neither
catches "the codegen now emits one extra `nop` per function" -- a
change that doesn't break correctness but breaks reproducibility.

## Decision
**The NOVA self-hosting invariant `stage2.s == stage3.s` is treated as
a load-bearing CI gate for CrossEngin.** Concretely:

  - The NOVA compiler bootstraps via three stages: stage1 (handwritten
    x86-64 assembly seed) -> stage2 (stage1 compiles
    `compiler/main.nova`) -> stage3 (stage2 compiles
    `compiler/main.nova`).
  - **stage2 and stage3 must produce byte-identical assembly output.**
    Any divergence is a compiler bug.
  - Verified via `make self-host` in the NOVA repo; this is the
    pre-merge gate for any change to `parser.nova` / `codegen.nova` /
    `register_allocator.nova` / `x86_64_lowering.nova`.
  - CrossEngin's `scripts/bootstrap.sh` verifies `$NOVA_ROOT` points
    at a NOVA tree where `make self-host` passes.

## Consequences
**Positive.**
  - **Regressions in the toolchain are detected in 30 seconds**, not
    in 2 hours of debugging substrate behaviour. The diff between
    stage2.s and stage3.s is the smallest possible repro.
  - **Compiler refactors are safe.** When R26F (the "regression hunt"
    round) added 600+ lines of test coverage, the self-host invariant
    confirmed no compiler bug snuck in alongside the test refactor.
  - **Cross-repo coupling stays cheap.** CrossEngin can pin a NOVA
    commit; we know the NOVA commit isn't silently changing codegen.

**Negative.**
  - **Non-determinism is forbidden in codegen.** Hashmap iteration
    order, random tag generation, timestamp inclusion -- any of these
    in the codegen output breaks the invariant. We accept this
    constraint and document it in NOVA's `parser.nova` / `codegen.nova`
    contributor guide.
  - **Compiler-level optimisations are slower to ship.** A
    "smarter register allocator" PR has to land twice: once to
    produce stage2.s changes, once to confirm stage3.s now matches.
    This is the right speed; it forces the contributor to think
    about the fixed point.

**Follow-up rounds.**
  - R26F regression hunt added a CI script for `make self-host` on
    every commit to NOVA's `main`.
  - R37+: extend the invariant to cross-platform: stage2-on-Linux ==
    stage3-on-Linux AND stage2-on-macOS == stage3-on-macOS. (Linux
    already enforced; macOS / ARM64 has a separate invariant noted
    in NOVA's `MACOS_AUDIT.md`.)

## Alternatives considered
  - **Large test suite only.** Rejected as sole defence: tests catch
    behaviour regressions, not reproducibility regressions.
  - **Compiler diff review only.** Rejected: 16k LOC of NOVA compiler
    code is too much for human review to catch a one-line codegen
    bug.
  - **Property-based testing of the compiler.** Considered; we may
    add it in R37+ as a *complement* to the self-host invariant, not
    a replacement.
  - **Cryptographic hash of compiler output as the invariant.**
    Effectively what bit-identical is, just expressed via filesystem
    diff. The diff has the advantage of showing the contributor
    *where* the divergence is when it occurs.

## Why this matters for CrossEngin specifically
CrossEngin's federation tests assert exact byte sequences on the wire
(R34B's TURN codec, R34C's SRTP wire). A codegen change that flips a
register allocation can change the order of struct field writes, which
can change the order of bytes emitted to the wire buffer, which can
break a peer's wire-codec test. The self-host invariant catches the
underlying compiler change before it touches CrossEngin's CI.
