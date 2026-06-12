# ADR-0064: Fix P0 segfault in test_code_review_pack — missing imagination_engine import

## Status

Proposed

## Date

2026-06-12

## Context

`/home/user/NOVA/nova run tests/unit/test_code_review_pack.nova` compiled
cleanly ("Compiled: ...") but the produced binary segfaulted at runtime (exit
139) deterministically on every run. The same symptom appeared in
`test_ops_pack.nova` and `test_medical_pack.nova`, all three sharing the same
`_setup()` helper pattern.

### Diagnosis

Bisection via temporary `/tmp` probe files established the following:

1. **Importing the pack alone and calling `kg_registry_new()` passes** — no
   crash in module initialisation.
2. **Calling `reasoning_kg_init` and `lang_kg_init` passes** — no crash in
   those two `kg_spawn` wrappers.
3. **Calling `imagination_kg_init(reg)` segfaults** unless
   `imagination_engine.nova` is imported explicitly in the test file.
4. **Calling `kg_spawn(reg, "imagination")` directly works** — proving that
   `kg_spawn` itself is sound and that the crash comes from the call to
   `imagination_kg_init`.

**Root cause: `imagination_kg_init` is called by the test but never imported.**

`imagination_kg_init` is defined exclusively in
`src/parts/imagination/imagination_engine.nova`. The test only imports
`src/seed/packs/code_review_pack.nova`, whose transitive import chain
(ask_user_to_teach → word_atoms → cross_kg_references / hdc_embed;
reasoning_atoms → multi_kg_manager → ann_index / differential_privacy;
meta_observer → multi_kg_manager / source_authority) does NOT include
`imagination_engine.nova`.

NOVA does not report an error at compile time when a function is called but
not imported — the compiler emits a call to an unresolved or garbage address.
At runtime the CPU jumps into an invalid region and takes a SIGSEGV. This is a
known NOVA linker behaviour (not codegen bug #11): the binary compiles
"successfully" but carries a bad call target.

### What was ruled out

NOVA codegen bug #11 (pointer-threshold arithmetic: smart-op dispatch
misroutes `+`, `*`, `==`, etc. when BOTH operands ≥ 0x100000) was the first
suspect. Careful analysis showed it is NOT triggered here:
- `label_hash` masks its accumulator to 15 bits before each multiply, so its
  `h * 31` intermediate stays in [0, 1,015,777] — below the 1,048,576
  threshold for both operands individually and keeps both below the threshold.
- `bel_mean`'s `b[0] * FP_SCALE` (max 4,000 × 1,000 = 4,000,000) has both
  operands individually below 0x100000 (< 1,048,576), so the smart multiply
  dispatches to the integer path.
- No arithmetic in the pack's functions themselves crosses the threshold.

## Decision

Add the missing import to `tests/unit/test_code_review_pack.nova`:

```nova
import "../../src/parts/imagination/imagination_engine.nova"
```

This one-line addition makes `imagination_kg_init` properly resolved at
compile time, eliminating the garbage-address call site. No production source
file is modified. The fix is the narrowest possible: it targets the test that
is broken, leaves the pack itself unchanged, and does not touch any shared
helper.

`test_ops_pack.nova` and `test_medical_pack.nova` were confirmed to carry the
**identical** latent segfault (both call `imagination_kg_init` without importing
`imagination_engine.nova`) and are fixed with the same one-line import in this
P0 pass, so no known-segfaulting suite is left behind.

## Consequences

- **`test_code_review_pack` is deterministically green (3/3 runs)** after the
  fix: 10 checks, all pass, exit 0.
- **No source module was changed**, so every existing test that imports
  `imagination_engine.nova` is unaffected. The reverse-dependency tests below
  all remain green (listed in Implementation Notes).
- The underlying NOVA linker behaviour (silent compile + runtime crash for
  unresolved imports) is unchanged. A repo-wide import-completeness lint is
  being tracked separately (see Honest gaps).

## Honest gaps

- **NOVA silent-compile on unresolved imports is a systemic toolchain risk
  (tracked).** Any module that calls a function whose defining module is not in
  its transitive import closure compiles silently and segfaults at runtime —
  there is no link-time "undefined symbol" error. This masked three P0 segfaults
  here. The correct long-term remedy is a NOVA-side change to **error on
  unresolved call targets at compile time** (tracked as a NOVA toolchain work
  item, like codegen bug #11); a cheaper interim CrossEngin guard is an
  import-completeness lint (every called identifier must be defined in the
  transitive import set). Out of scope for this P0 fix, recorded here.
- **NOVA codegen bug #11** (pointer-threshold arithmetic) is a separate systemic
  risk; see ADR-0066 for the `int_*` standard and the `make lint-ints` guard now
  in place. It was ruled out as the cause of this incident.

## Implementation Notes

**Files changed (one import line each, same fix):**
- `tests/unit/test_code_review_pack.nova`
- `tests/unit/test_ops_pack.nova` (`ops_runbook_pack` → 10 checks OK)
- `tests/unit/test_medical_pack.nova` (`medical_pack` → 22 checks OK)

Each adds `import "../../src/parts/imagination/imagination_engine.nova"` with a
comment explaining that `imagination_kg_init` is called in `_setup()` but is not
in the pack's transitive import chain. No production source file is modified.

**Reverse-dependency tests run and their results:**

| Test file | Checks | Result |
|---|---|---|
| `test_atom_store.nova` | 42 | OK |
| `test_word_atoms.nova` | 115 | OK |
| `test_ask_user_to_teach.nova` | 19 | OK |
| `test_reasoning_atoms.nova` | 13 | OK |
| `test_meta_observer.nova` | 39 | OK |
| `test_multi_kg_manager.nova` | 23 | OK |
| `test_imagination_engine.nova` | 14 | OK |
| `test_code_review_pack.nova` (the fix) | 10 | OK (3/3 runs) |

All 7 reverse-dependency suites pass; 275 checks total, zero regressions.
