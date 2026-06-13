# ADR-0067: CI unblock — the full unit suite now completes, and the failures it revealed

## Status

Proposed

## Date

2026-06-12

## Context

Until the P0 fixes (ADR-0063–0066), `make test` could never finish: the NOVA
compiler hung on `dtls12.nova` (ADR-0065), and `scripts/test.sh` globs
`tests/unit/*.nova` alphabetically, so the run died at `test_dtls12` and **every
test after `d…` never executed**. That hid the true state of roughly the back
half of the suite. With the hang fixed, the suite runs end-to-end for the first
time, and surfaced four pre-existing failures (one of which masked two more
bugs). This ADR records the unblock outcome and the triage.

## Decision

Run the full suite, catalogue every revealed failure, and drive the
deterministic ones to green where the fix is safe and unambiguous; track the
ambiguous / non-reproducible ones explicitly rather than guessing.

### Revealed failures and disposition

| Test | Symptom | Root cause | Disposition |
|---|---|---|---|
| `test_pack_registry` | SIGSEGV (139) | `imagination_kg_init` called without importing `imagination_engine.nova` — NOVA silently compiles an unresolved call (same class as ADR-0064) | **Fixed** — one-line import. 31 checks green. |
| `test_http_client` | exit 1 then SIGSEGV | **three** stacked bugs: (1) `let none = …` — `none` is now a reserved token, parse error; (2) `_hc_ip_to_int` used `b*256`, `c*256*256`, `d*256*256*256` + sum — **codegen bug #11** (variable-driven products cross 0x100000; the lint can't see non-literal operands); (3) `HTTP_ERR_CHUNKED` **referenced but never defined** — silent undefined-symbol → garbage `err`, and `str_eq` against the undefined constant crashed | **Fixed** — rename var; `int_mul`/`int_add` packing (as ADR-0063); define the missing constant. 103 checks green, deterministic. |
| `test_dtls12` | exit 1, 10 failed | epoch-rotation logic: `dtls_advance_epoch` does not reset `recv_seq`, does not preserve `aead_records_in/out` across CCS, and does not allocate fresh key buffers — **OR** the tests poke raw slot indices that don't match the slot constants. Plus 1 provably-wrong assertion (`label[14]=='s'`, but byte 14 of `"EXTRACTOR-dtls_srtp"` is `'_'`=95). | **Tracked — needs a decision** (crypto-sensitive; code-wrong vs test-wrong is ambiguous). The compile-hang that hid it is fixed; the logic is untouched. |
| `test_turn` | SIGSEGV (139), **intermittent** | flaky: passes 12/12 in isolation, failed once under the full run. ASLR-dependent bad address — consistent with a silent undefined-symbol reference or an uninitialised/garbage-pointer read somewhere in the STUN/TURN paths. | **Tracked — flaky**, no deterministic repro yet. |

### Two systemic NOVA toolchain defects (root of most of the above)

Recorded here as tracked NOVA work items (the real fixes belong in the compiler,
deliberately not attempted — the self-hosting bootstrap is unrecoverable if
broken):

1. **Silent compile of unresolved symbols.** A reference to an undefined
   function *or constant* (missing import, missing `let`) compiles to a garbage
   address with no error, then crashes at runtime — ASLR-dependent, hence the
   flakiness. This caused the pack segfaults (ADR-0064), the `HTTP_ERR_CHUNKED`
   crash, and is the prime suspect for `test_turn`'s flake. **Fix:** NOVA should
   emit a link-time "undefined symbol" error. Interim CrossEngin guard: an
   import/definition-completeness lint.
2. **Codegen bug #11** (magnitude-based smart-op dispatch). See ADR-0066 +
   `docs/design/int-safety.md` + `make lint-ints`.

## Consequences

- `make test` **completes** for the first time. With the fixes here, the only
  deterministic red is `test_dtls12` (pre-existing epoch logic); `test_turn` is
  an intermittent flake. The other ~270 suites pass.
- Two of the four revealed failures (`pack_registry`, `http_client`) are fully
  green and committed.
- The `http_client` IP-packing fix confirms codegen bug #11's **variable-driven**
  case (which the literal-only lint cannot catch — see ADR-0066 honest gaps),
  reinforcing the int_* coding standard.

## Honest gaps

- **`test_dtls12` (10 failures) is not fixed here.** It is DTLS 1.2 epoch-rotation
  correctness; fixing it blind risks miscompiling the cipher-state machine. It
  needs a deliberate decision: correct `dtls_advance_epoch`, or correct the
  tests' slot-index assumptions, or accept as a tracked P1. The 1 label assertion
  is provably a test bug; the 9 epoch ones require DTLS judgement.
- **`test_turn` flake** has no deterministic reproducer; root-causing it likely
  requires the silent-undefined-symbol toolchain fix (item 1) or a memory
  sanitiser, neither available here.
- The real fixes for both systemic defects are NOVA toolchain changes, out of
  scope for this app-level P0 pass.

## Implementation Notes

- Fixed in this pass: `tests/unit/test_pack_registry.nova` (import),
  `tests/unit/test_http_client.nova` (var rename),
  `src/io/transducers/http_client.nova` (int_* IP packing + `HTTP_ERR_CHUNKED`
  definition). Earlier P0 commits: ADR-0063–0066.
- Companion ADRs: 0063 (stream_http), 0064 (pack segfaults), 0065 (dtls12 hang),
  0066 (int-safety standard + lint).
