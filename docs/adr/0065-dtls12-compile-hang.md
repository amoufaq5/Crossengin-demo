# ADR-0065: dtls12.nova compile hang — the long `+`-chain expression blowup

## Status

Accepted (source-level fix applied)

## Date

2026-06-12

## Context

`/home/user/NOVA/nova build src/federation/dtls12.nova` printed
`=== Nova Compiler Starting ===` and then **never finished** (still running at
a 120s timeout, 0% progress past the banner). dtls12.nova is 2420 lines.

This is a hard CI blocker (the #2 P0): the unit-test runner globs
`tests/unit/*.nova`, and `tests/unit/test_dtls12.nova` imports
`src/federation/dtls12.nova`. Because compiling that import never terminates,
`make test` / `make build` can never complete and there is no green CI.

The fix had to be a SOURCE-LEVEL change inside CrossEngin's
`src/federation/dtls12.nova` — the NOVA compiler is self-hosting and must not
be touched.

## Decision

### Root cause

The hang is triggered by a single construct: `fn dtls_stats_line(state)`
(was at lines 2332-2354) built its entire result as **one `return`
expression with ~40 chained `+` string-concatenation operands**:

```nova
return "dtls: state=" + dtls_state_name(...)
    + " msg_seq=" + int_to_str(...)
    + " epoch="   + int_to_str(...)
    ...                                   // ~40 `+` terms total
    + " rekeys="  + int_to_str(...)
```

NOVA's compiler handles a long left-associative `+` chain in a single
expression with a code path whose cost grows **super-exponentially** in the
number of operands. Measured on this toolchain with a minimal reproducer (a
`return "a=" + int_to_str(x) + " b=" + int_to_str(x) + ...` chain of N
repeated terms):

| chained `+` terms | compile time |
| ----------------- | ------------ |
| 6                 | 0.024 s      |
| 11                | 0.39 s       |
| 12                | 1.6 s        |
| 13                | 5.9 s        |
| 14                | 23.8 s       |
| 16                | > 60 s (HANG)|
| ~40 (dtls_stats_line) | never terminates |

Each added term multiplies the time by roughly 3-4x — a clear
exponential/non-terminating blowup, not a constant-factor slowdown. At ~40
terms the build is hopeless. This is a compiler-side defect (almost certainly
an exponential traversal/duplication when lowering a deep right-skewed or
re-balanced `+` AST), but it is fully avoidable at the source level by not
constructing such a deep single expression.

This is NOT NOVA codegen bug #11 (the `0x100000` pointer-threshold SIGSEGV).
That bug is a runtime/codegen *crash* on large-integer arithmetic; this is a
compile-time *hang* on a long string-concatenation expression. The large
literals in dtls12.nova (`_DTLS_SEQ_MASK = 281474976710655`,
`_DTLS_REPLAY_MASK64 = 18446744073709551615`) are bare `let` constants whose
arithmetic already goes through the `int_*` escape-hatch builtins
(`int_and`, `int_shl`, `int_or`, ...), and the functions using them compiled
fine in the bisection — they are not the trigger.

### The fix

Rewrite `dtls_stats_line` to accumulate the line as a sequence of
**statement-level** concatenations instead of one giant expression, keeping
each individual expression's `+` count small (<= 3):

```nova
let s = "dtls: state=" + dtls_state_name(state[DTLS_S_SLOT_STATE])
s = s + " msg_seq=" + int_to_str(state[DTLS_S_SLOT_MSG_SEQ])
s = s + " epoch="   + int_to_str(state[DTLS_S_SLOT_EPOCH])
...
s = s + " rekeys="  + int_to_str(state[DTLS_S_SLOT_REKEYS])
return s
```

This is behaviour-preserving: the produced string is byte-identical (same
fields, same order, same separators). A warning comment in the function
records the hazard and the threshold so a future refactor does not silently
re-introduce a 40-term chain.

## Consequences

- `timeout 90 nova build src/federation/dtls12.nova -o /tmp/d.bin` now
  **completes in 0.15 s** (was: never, >60 s timeout). Before: HANG. After:
  0.153 s.
- `timeout 120 nova run tests/unit/test_dtls12.nova` now **runs to
  completion in ~11 s** (was: could never even compile). It no longer hangs,
  so the toolchain blocker is removed and `make test` can complete.
- All four `dtls_stats_line` test groups (state/replay/new-fields/rekeys,
  including every per-field "stats line mentions X" assertion) **pass** with
  the rewritten function — confirming the rewrite is behaviourally complete.

## Honest gaps

- **`test_dtls12` is not fully green yet: 440 pass, 10 still FAIL.** These 10
  failures are PRE-EXISTING and INDEPENDENT of this ADR's fix. They were
  invisible because the compile hang meant the suite had literally never run
  (cf. ADR-0058's "latent bug invisible because the module was untested").
  Proof: building a variant where `dtls_stats_line` is replaced by a trivial
  stub yields the EXACT SAME 10 failures (plus the 10 stats-line failures the
  stub introduces) — the 10 do not involve `dtls_stats_line` at all. They
  split into:
  - **`dtls_advance_epoch` slot semantics (9 of 10).** The tests poke raw
    slot indices and expect a reset/preserve contract: `recv_seq reset to 0`,
    `aead_records_out/in preserved across CCS`, `key_block / *_write_key /
    *_write_iv pointer changed (fresh allocation)`, and
    `post-advance km is fresh non-zero pointer`. The test pokes e.g.
    `st[31] = 17` calling it RECV_SEQ, but slot 31 is
    `DTLS_S_SLOT_AEAD_RECORDS_IN` (RECV_SEQ is slot 26) — a test/source slot-
    index mismatch and/or an `dtls_advance_epoch` that does not re-allocate the
    key buffers the tests expect. Diagnosing and fixing `dtls_advance_epoch`
    (or correcting the slot indices in the test) is a separate defect, out of
    scope for this compile-hang P0 pass, and was deliberately NOT touched (the
    mandate is a fix to the hang construct, not unrelated DTLS logic).
  - **`label[14] == 's'` (1 of 10) is a wrong TEST assertion.** The label is
    `"EXTRACTOR-dtls_srtp"`; byte 14 is `_` (0x5F = 95), not `s` (115). The
    sibling assertions (`len == 19`, `label[10] == 'd'`, `label[18] == 'p'`)
    pass. The exporter is correct; the test's expected value is the typo.
  - **Path to green:** a follow-up should (a) reconcile the `dtls_advance_epoch`
    reset/preserve contract with the slot constants the tests assert, and
    (b) correct the `label[14]` expected byte to 95. Neither is a toolchain
    change.

## Implementation Notes

### Bisection method

- Worked on `/tmp/dtls_full.nova` (a copy). Confirmed imports alone
  (sha256/p256/aes_gcm/x509 + trivial `main`) compile in 0.12 s, so the
  trigger is in dtls12's own code.
- A .nova file is a flat list of top-level `fn`/`let` decls. Built reduced
  copies by keeping lines `1..cut` (imports + all `let` constants + a prefix
  of the functions) and appending `fn _tmp_main(){}; _tmp_main()`. Each
  `cut` was a function boundary, so the prefix always parsed. `timeout 60
  nova build` each; rc=124 ⇒ hang ⇒ trigger is in the kept prefix, rc=0 ⇒
  trigger is later. Binary search on the function index (111 functions):

  | kept through | line | result |
  | ------------ | ---- | ------ |
  | fn 54        | 1307 | OK (0.15 s) |
  | fn 82        | 1580 | OK (0.13 s) |
  | fn 96        | 2212 | OK (0.20 s) |
  | fn 103       | 2365 | HANG |
  | fn 99        | 2277 | OK |
  | fn 101       | 2363 | HANG |
  | fn 100       | 2331 | OK |
  | fn 101 only (dtls_stats_line, 2332-2354) | — | HANG |

  Isolated to the single function `dtls_stats_line`.

### Minimal reproducer (hangs the NOVA compiler)

```nova
fn f(x) {
    return "a=" + int_to_str(x)
        + " b=" + int_to_str(x)
        + " b=" + int_to_str(x)
        + " b=" + int_to_str(x)
        + " b=" + int_to_str(x)
        + " b=" + int_to_str(x)
        + " b=" + int_to_str(x)
        + " b=" + int_to_str(x)
        + " b=" + int_to_str(x)
        + " b=" + int_to_str(x)
        + " b=" + int_to_str(x)
        + " b=" + int_to_str(x)
        + " b=" + int_to_str(x)
        + " b=" + int_to_str(x)
        + " b=" + int_to_str(x)
        + " b=" + int_to_str(x)
}
fn main(){ print(f(1)) }
main()
```

(16 chained `+` terms; `timeout 60 nova build` never finishes. Dropping to
~10 terms compiles, ~13 takes 6 s, ~14 takes 24 s — the blowup is clearly
exponential in the operand count.)

### Recommended compiler-side fix (out of scope for this app-level pass)

The durable fix is in NOVA, not the app: lower a left-associative `+` chain
iteratively (fold `a + b + c + ...` into a single left-deep walk that emits
one concat per operand) instead of whatever traversal currently duplicates
work per node. The expression should be O(n) in operand count, not O(k^n).
Until then, every NOVA module must keep single-expression `+` chains short
(<= ~10 string terms) and use statement-level accumulation for longer joins —
a lint for this would prevent recurrence.

### Before / after timings

- `nova build src/federation/dtls12.nova`: **HANG (>60 s, never)** → **0.153 s**.
- `nova run tests/unit/test_dtls12.nova`: **could not compile** → **~11 s,
  runs to completion**, 440 passed / 10 pre-existing FAIL (see Honest gaps).

### Files changed

- `src/federation/dtls12.nova` — `dtls_stats_line` rewritten to
  statement-level accumulation (behaviour-preserving) + hazard comment.
- `docs/adr/0065-dtls12-compile-hang.md` — this ADR.
