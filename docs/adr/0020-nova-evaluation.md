# ADR-0020: NOVA evaluation — design inspiration, not implementation language

## Status

Accepted

## Context

NOVA is a self-hosted compiled programming language authored by the project owner. It has a working compiler, a passing test suite, and a small but real ecosystem. Its grammar includes declarative blocks (`mind { … }`, `soul { … }`, `system { … }`) whose vocabulary aligns suggestively with Crossengin's architectural concepts.

The design conversation included a multi-round evaluation of NOVA's viability as Crossengin's implementation language. The conversation explored what NOVA can currently do, what it would need to be able to do to support Crossengin's needs, and what the realistic engineering path to closing the gap looks like. This ADR records that evaluation so that the decision in ADR-0003 (Python+PyTorch+Rust, NOVA out as implementation language) has a documented technical basis.

## Decision

**NOVA is not used as the implementation language for Crossengin Demo.** NOVA continues as a parallel design-and-language-research effort, and its declarative grammar inspires Crossengin's configuration schemas. The implementation-language decision is revisitable in 12–18 months if NOVA's GPU compute and Python interop stories materialize with working examples and benchmarks.

This ADR is the source of truth for the technical evaluation behind that decision.

## Evaluation summary

**What NOVA currently is (as of the design conversation):**

- A self-hosted compiled language with ~115 of 118 non-skipped tests passing.
- IEEE 754 float support added.
- Basic libc FFI working through the `--link-libc + gcc -ldl` toolchain configuration.
- Working compiler, working module system, working basic standard library.
- Declarative blocks `mind { … }`, `soul { … }`, `system { … }` exist in the grammar; their semantics are still being defined.

**What NOVA would need to support Crossengin as an implementation language:**

1. **GPU compute that executes kernels.** Crossengin trains and runs neural networks. Neural network training requires CUDA kernels (or equivalent on other GPU stacks) that execute on the device. Current state in NOVA: `libcuda` can be dlopen'd, but the dlopen is a stub — no kernels actually execute. Closing this gap requires a full GPU kernel toolchain (cuBLAS, cuDNN, NCCL or equivalent, a kernel-launch ABI, a memory-allocator interop with CUDA's runtime, autograd or an equivalent). This is multi-engineer-year work, separable from Crossengin.

2. **Mature ML ecosystem bindings.** PyTorch, transformers, numpy, scipy, the `pgvector` Python client, the Apache AGE Python client, every preprocessing-pipeline tool the project will use. Current state: none of these are bound from NOVA. Each binding is a non-trivial engineering project on its own.

3. **Python interop that can drive PyTorch.** NOVA can call `PyRun_SimpleString` from its libc FFI, but cannot pass tensors back and forth between NOVA and Python, cannot subclass Python classes, cannot meaningfully drive PyTorch's API. Closing this gap requires building a real CPython embedding layer (cf. PyO3 in the Rust ecosystem — many person-years of work).

**The three gaps above are structural.** NOVA can close them in time, but the time required is on the order of years, not months. Crossengin's v0 ship target is in the months range. The two timelines do not align.

**What NOVA's contribution to Crossengin is:**

- **DSL inspiration.** NOVA's `mind { … }`, `soul { … }`, `system { … }` grammar is the inspiration for Crossengin's YAML/Pydantic configuration schemas for the cognitive-architecture blocks (per ADRs 9, 11, 13, 14). The vocabulary translates directly; the implementation does not.
- **Continued language research.** NOVA continues as the user's parallel research project. The two efforts cross-pollinate at the schema-design level.

**Revisit conditions for the NOVA-as-implementation question.** This decision is revisitable in 12–18 months if all of the following hold:

1. NOVA has demonstrated GPU compute executing real kernels with measurable performance (a benchmark on a non-trivial model).
2. NOVA has a usable Python interop layer that can pass tensors and drive PyTorch's API (a worked example).
3. The NOVA ecosystem includes bindings for at least the core ML libraries Crossengin uses (PyTorch, numpy, a database client).

If all three hold at the 12–18-month revisit, the decision can be re-examined. If they do not, Crossengin continues on Python+PyTorch+Rust without further re-litigation until a clear technical reason emerges.

## Consequences

Positive: the implementation-language decision in ADR-0003 has a documented technical basis. Future contributors who ask "why not NOVA?" get a complete answer that names the three structural gaps and the revisit conditions. NOVA's contribution to Crossengin is clearly defined (DSL inspiration, not implementation), which keeps the two projects healthy as parallel efforts. The revisit conditions are concrete enough that a future re-evaluation can be done objectively.

Negative: NOVA's design beauty does not directly accelerate Crossengin's v0 deliverable. The user's personal investment in NOVA does not pay off in Crossengin's implementation. The 12–18-month revisit window is a real commitment; if NOVA's gaps close ahead of schedule, Crossengin will already be invested in Python and a switch would be a rewrite.

Neutral: the two-track structure (Crossengin on Python+PyTorch+Rust, NOVA on its own language-research path) is the honest division of effort given the current state of NOVA's tooling.

## Alternatives considered

**NOVA as implementation language for v0.** Discussed at length in the design conversation. The user initially preferred this on alignment grounds (NOVA's grammar speaks Crossengin's vocabulary). The assistant pushed back on the three structural gaps above. The user accepted the assistant's recommendation. NOVA-as-implementation remains revisitable per the conditions above.

**NOVA for v0 with a Python fallback wrapper** (NOVA glue code calling Python via the existing `PyRun_SimpleString` FFI). Considered. The Python interop layer cannot pass tensors meaningfully; "glue code in NOVA calling Python for the real ML work" produces an architecture where every actual operation crosses an FFI boundary that costs more than it saves. Rejected as adding complexity without delivering NOVA's advantages.

**NOVA for the configuration schemas only** (configs written in NOVA syntax, parsed by Crossengin's Python runtime). Considered. Rejected on tooling grounds — Pydantic + YAML is already extremely well-supported in the Python ecosystem (editor support, validation, OpenAPI generation, library compatibility). Adopting a NOVA-syntax config layer adds tooling burden without proportional benefit. The NOVA-inspired *vocabulary* of the configs is what matters; the syntactic form can be standard YAML.

**Drop NOVA entirely.** Rejected. NOVA is the user's own research project and is contributing real design inspiration to Crossengin. There is no reason to terminate a project that is producing value, even if its value to Crossengin is at the inspiration level rather than the implementation level.

## Open questions

- Concrete revisit checkpoint at 12–18 months: which engineer evaluates, what the deliverable looks like (a short ADR addendum updating this one, either confirming the decision stands or proposing a superseding ADR), and what the criteria are for "demonstrated" in each of the three revisit conditions.

## References

- ADR-0003 (Implementation language and stack) — the decision this ADR supports.
- ADR-0011 (Soul values governance), ADR-0013 (Consciousness model), ADR-0014 (Behavior and personality) — the configuration schemas where NOVA's `mind { … }`, `soul { … }`, `system { … }` vocabulary inspires the structure.
- The user is decision owner; the assistant's evaluation here is in service of the user's authority to choose.
