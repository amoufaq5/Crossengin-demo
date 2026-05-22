# ADR-0003: Implementation language and primary stack

## Status

Accepted (user-overridable)

## Context

Crossengin needs a primary implementation language and toolchain that supports: GPU-backed neural training and inference (PyTorch or equivalent), graph and vector database client libraries (for PostgreSQL with `pgvector` and Apache AGE), preprocessing pipelines over large text and image corpora, and performance-critical paths where Python overhead is unacceptable.

The user is also the author of NOVA, a separate self-hosted compiled programming language. NOVA's role in Crossengin was an open question entering the design conversation: implementation language, parallel research project, or design inspiration only. NOVA's current state (per the multi-round evaluation summarized in ADR-0020) is a real, working, self-hosted compiler with IEEE 754 float support and basic libc FFI, but without GPU compute that executes kernels, without mature ML ecosystem bindings (no PyTorch, no transformers, no `pgvector` client), and with Python interop limited to `PyRun_SimpleString` (which cannot meaningfully drive PyTorch).

A v0 ship in 2026 with a small team requires battle-tested ML tooling. Re-creating PyTorch's CUDA kernel ecosystem, autograd, distributed-training primitives, and the surrounding library universe in a new language is a multi-year project unto itself, separable from building Crossengin.

## Decision

The primary implementation stack for Crossengin Demo is:

- **Python 3.11+** as the primary language.
- **PyTorch** for neural network construction, training, and inference.
- **Rust** (via PyO3 / maturin) for performance-critical paths where Python overhead is the bottleneck (e.g., per-token preprocessing in hot loops, frame-extraction parsers, memory-index update batches).
- **PostgreSQL 16+** with `pgvector` and Apache AGE extensions as the memory substrate (full ADR-0006 covers this).
- **Tooling:** `uv` for dependency management, `ruff` and `black` for linting and formatting, `pytest` for tests, `mypy` for static type checking. All Apache 2.0 or MIT licensed.

**NOVA is explicitly not used as the implementation language for Crossengin Demo.** NOVA continues as a parallel design lab; its declarative `mind { … }`, `soul { … }`, and `system { … }` grammars inspire the YAML / Pydantic-typed configuration schemas Crossengin uses for cognitive-architecture configuration. The NOVA-as-implementation question may be revisited in 12–18 months if NOVA's GPU compute and Python interop stories have matured with working benchmarks. ADR-0020 records the technical evaluation in detail.

## Consequences

Positive: Python + PyTorch + Rust is the path of least resistance for everything Crossengin needs to do in v0. Every dependency in the planned stack is permissively licensed (Apache 2.0, MIT, BSD, PostgreSQL license — see ADR-0019), and every dependency has a large user base with active maintenance. Hiring is easier — ML engineers already know this stack. Performance escape hatch (Rust via PyO3) is available without abandoning Python.

Negative: a meaningful share of the project's intellectual output (NOVA's language design) does not directly accelerate the v0 deliverable. The two efforts must be kept disciplined as parallel tracks. If NOVA matures to the point of viability later, migrating Crossengin to it would be a large rewrite.

Neutral: NOVA's grammar shapes Crossengin's config schemas, so the two projects cross-pollinate at the schema-design level even though they share no implementation code.

## Alternatives considered

**NOVA as the implementation language.** The user's initial preference, given the personal investment in NOVA and the architectural elegance of building Crossengin in a language whose grammar already speaks the right vocabulary (`mind`, `soul`, `system`). The assistant strongly recommended against this for the v0 timeframe, on the following grounds:

1. *GPU compute.* NOVA does not currently execute GPU kernels. Its `libcuda` dlopen is a stub. Training and inference at the scale Crossengin requires depend on an entire CUDA kernel ecosystem (cuBLAS, cuDNN, NCCL, Triton or equivalent) that does not exist for NOVA.
2. *ML ecosystem bindings.* No `transformers`, no `torch`, no `numpy`, no `pgvector` client. Each one is a multi-engineer-month project to bind, and the binding work is not differentiating engineering.
3. *Python interop.* NOVA can call `PyRun_SimpleString` but cannot pass tensors back and forth, cannot subclass Python classes, cannot meaningfully drive PyTorch. Closing this gap requires building a real CPython embedding layer.

The user accepted this recommendation. The status is `Accepted (user-overridable)` because the underlying decision is the user's, not the assistant's, and reversal at any point is the user's prerogative.

**Rust as the primary language (with Python only as a calling-convention shim).** Considered. Rejected for v0 because the team's ML productivity is materially higher in Python, the PyTorch ecosystem is Python-centric, and Rust's ML libraries (Burn, candle, etc.) are immature relative to PyTorch for the kinds of model surgery (LoRA, custom training loops, custom attention) that Crossengin will need.

**Julia.** Mature numerical ecosystem, good multiple-dispatch story, but a smaller production-AI community than Python. The integration tax (calling `pgvector`, Apache AGE, RunPod orchestration tooling — all Python- or shell-native) outweighs Julia's per-line elegance.

**Mojo.** Closest analog to NOVA's pitch: a Python-superset language with systems-language performance. Rejected for v0 because Mojo is not yet open under a fully permissive license (it remains partially proprietary as of the design conversation), which violates the strict-permissive posture in ADR-0019.

## References

- ADR-0019 (Licensing posture) for the strict-permissive constraint on dependencies.
- ADR-0020 (NOVA evaluation) for the full technical assessment of NOVA's viability.
- The user is decision owner on the NOVA-vs-Python choice; this ADR is `Accepted (user-overridable)`.
