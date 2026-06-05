# ADR R36F-0001: NOVA as the implementation language

## Status
Accepted (R36F) -- decision originally made pre-R0, restated and ratified across rounds R0..R35.

## Context
CrossEngin needs a systems language that can carry a cognitive substrate
of ~6M nodes, 60M synapses, raw signal traffic at ~100Hz, and grow with
the project across an 18-30 month v1 timeline without forcing the team
to rewrite the runtime mid-flight. The implementation language must
support:

  - Deterministic memory management (no GC pauses during signal
    propagation).
  - Direct syscall access (raw sockets for federation, mmap for
    persistence) without dragging libc / libstdc++ ABI compatibility
    along for the ride.
  - Bit-identical builds across compiler-versions so we can detect
    regressions without diff-noise (see ADR R36F-0005).
  - First-class arenas, lists-of-lists, and inline assembly because the
    substrate hot path runs at hundreds of thousands of ticks/sec.

The candidate languages we evaluated:

  - **Rust**: closest fit on the systems-language axis; borrow checker
    forces upfront thinking; cargo ecosystem is huge. Downsides: the
    compile-time cost of debug builds is brutal at 60+ kLOC, the
    macro / generics surface is too rich to keep two founders' mental
    model converged, no native primitives for our specific substrate
    abstractions, and we'd be the ones writing the federation crypto
    primitives anyway.
  - **Go**: easy on team mental load; the GC is a non-starter on a
    100Hz substrate tick. Eliminated early.
  - **C / C++**: ABI fragmentation and the maintenance burden of being
    "just another C codebase" without strong build hygiene make this
    expensive in year 2+.
  - **Python**: doesn't ship. Eliminated for the substrate; retained
    for tooling (LSP, DAP, training-loop orchestration) under the
    "Python servers, NOVA runtime" split.

## Decision
**CrossEngin is implemented in NOVA.** All substrate code, federation
primitives, audit / safety modules, parts (perception, KGs, soul,
reasoning, etc.), and persistence layers are NOVA. The NOVA compiler
lives in its own repo (`amoufaq5/NOVA`) and is consumed via the
`$NOVA_ROOT` environment variable; CrossEngin is a downstream consumer
of the NOVA toolchain.

The supporting tooling -- LSP, DAP, the round-orchestration scripts --
is allowed to be Python (see NOVA ADR R36F-0004 for the symmetric
reasoning on that repo). The NOVA build artifact is a single Linux ELF
binary.

## Consequences
**Positive.**
  - **Toolchain self-host invariant** (ADR R36F-0005): the stage2
    compiler reproduces stage3 byte-for-byte, so regressions in
    `parser.nova` / `codegen.nova` are detected by a 30-second `make
    self-host` rather than by debugging substrate behaviour.
  - **No libc surprise**: federation crypto, syscalls, and IO are all
    walked through NOVA's own primitives, so we don't inherit
    cross-distro ABI drift.
  - **Federation primitives built in NOVA** (rounds R28-R35): DTLS 1.2,
    SRTP, ICE, TURN, gossip, leader election all live as NOVA modules
    and reuse the canonical `safety/sha256.nova` / `safety/p256.nova`
    leaves (ADR R36F-0006). The federation stack does not depend on
    OpenSSL.
  - **One language for two founders** keeps mental-model load low. We
    don't context-switch between language paradigms when moving from
    substrate to federation to safety to learning.

**Negative.**
  - **NOVA bus factor**: the compiler is also written by us. A bug in
    `codegen.nova` blocks CrossEngin progress. The NOVA self-host
    invariant + the NOVA test suite mitigate this somewhat (Rounds R8,
    R17, R21, R26, R30 each hardened the toolchain).
  - **Smaller standard library**: we don't get Rust's `std`, Go's stdlib,
    or Python's PyPI. Each common primitive (SHA-256, JSON, base64,
    base32, HMAC, AES, P-256, etc.) was written by us. This was the
    bulk of R25-R34's effort and is the reason ADR R36F-0006 exists.
  - **Onboarding curve**: a new contributor must learn NOVA before
    contributing to CrossEngin. The `docs/GETTING_STARTED.md` +
    `docs/CONTRIBUTING.md` files in this repo, plus the NOVA repo's
    `docs/LANGUAGE_REFERENCE.md`, are the on-ramp.

**Follow-up rounds.**
  - R36F documents this decision (this ADR).
  - R37+: anything in `src/` that needs NOVA language extensions
    (e.g. the static-slot closure lowering follow-up in NOVA ADR
    R36F-0005) blocks CrossEngin until NOVA ships the extension.

## Alternatives considered
  - **Rust + C-FFI federation**: rejected because we'd be writing
    crypto primitives in Rust + C bindings to OpenSSL, doubling the
    surface area we have to audit. ADR R36F-0006 puts crypto in NOVA.
  - **Python prototype**: rejected because v1 ships as a desktop
    companion that must respect a 100Hz substrate tick; Python's GIL +
    interpreter overhead exclude this path.
  - **Multi-language polyglot**: rejected because two founders cannot
    keep N language toolchains in their heads while also writing the
    substrate. Tooling (Python LSP/DAP) is the only exception, and
    that exception is justified by the cost of writing an LSP in NOVA
    being far higher than reusing pygls.
