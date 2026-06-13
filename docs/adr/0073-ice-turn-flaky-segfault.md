# ADR-0073: Fix flaky SIGSEGV in test_ice_turn — NOVA codegen bug #11 (two-large-operand `==` / `!=`) + large hex literal miscompilation

## Status

Proposed

## Date

2026-06-12

## Context

`tests/unit/test_ice_turn.nova` intermittently exited 139 (SIGSEGV) during
the full suite run (`bash scripts/test.sh`) but passed consistently in
isolation. The symptom was ASLR-dependent: the crash address varied between
runs. This is the same failure signature as ADR-0069 (test_turn) and the
class identified in ADR-0066 (int-safety standard).

### Investigation

**Step 1 — undefined-symbol audit.** All symbols called in
`tests/unit/test_ice_turn.nova` were mapped to their definitions. No
undefined symbol was found. The undefined-symbol hypothesis (ADR-0064
class) was ruled out.

**Step 2 — int-safety lint.** `make lint-ints` reported clean for both
`src/federation/ice_turn.nova` and `tests/unit/test_ice_turn.nova`. This
was expected: the lint only flags large literals adjacent to `*`; it does
not cover `==` / `!=` with large operands (the "two-large-operand" gap
noted in ADR-0066).

**Step 3 — manual audit of smart-op candidates in test_ice_turn.nova.**
The NOVA smart-op table lists eight operators dispatched through pointer-
aware code when BOTH operands are >= 0x100000: `+ * < > <= >= == !=`. A
scan of `test_ice_turn.nova` found two unsafe `ce_eq` call sites:

```
test_relay_priority_rfc_formula   (line ~126):
    ce_eq("relay priority = 16777215 ...", ice_turn_relay_priority(), 16777215)

test_relay_priority_matches_r30c  (line ~134-135):
    ce_eq("R35D priority = R30C priority ...", ice_turn_relay_priority(), r30c)
```

In both cases `ice_turn_relay_priority()` returns
`_ICE_TURN_RELAY_PRIORITY = 16777215 (0xFFFFFF >= 0x100000)`, and the
second operand is also 16777215.  The `ce_eq` harness calls `got == expected`
which dispatches to `_nova_eq`.  The `_nova_eq` smart-op has an early
equality fast-path (`cmp %rsi, %rdi; je .eq_true`) that bypasses pointer
checking when both values are equal, which suppressed the crash in most
runs.  Under certain ASLR layouts the fast path is not reached (e.g. when
the comparison occurs in a context where the compiler emits a call rather
than a direct compare), triggering the full pointer dispatch.

**Step 4 — manual audit of `_ice_turn_is_parse_err` in ice_turn.nova.**
The function compared its argument `r` against `TURN_ERR_HEADER = 0 - 1`,
`TURN_ERR_COOKIE = 0 - 2`, etc. (all the way to `TURN_ERR_METHOD = 0 - 7`).
These constants evaluate to large unsigned values (0xFFFFFFFFFFFFFFFF,
0xFFFFFFFFFFFFFFFE, etc.) which are >= 0x100000. When `r` is a list pointer
returned by a successful parse (also >= 0x100000), every one of these
equality comparisons is a two-large-operand `==` — dispatching to
`_nova_str_eq`, which dereferences the integer as a heap pointer. Under
certain ASLR layouts this produces garbage "equal" or "not-equal" results,
causing the parse-error detection to misfire and `ice_turn_handle_allocate_-
response_authed` to take the wrong branch (returning `RELAY_FAILED` instead
of `AUTH_PENDING`), followed by subsequent assertion failures and eventually
a SIGSEGV.

**Step 5 — large hex literal miscompilation.** A `0x2112A442` hex literal
in the test helper `_itt_emit_401_with_attrs` (line 574 of
`test_ice_turn.nova`) was used as the TURN_MAGIC_COOKIE value written into
synthesized wire buffers. Per ADR-0069's second root cause finding, large
hex literals (>= 0x100000) are sometimes miscompiled with incorrect constant
values; decimal literals of the same value always compile correctly. When
the put value was wrong, `_turn_walk_attrs` rejected the cookie and returned
`TURN_ERR_COOKIE`, causing the 401 test path to fail non-deterministically.

**Step 6 — 50-run stability before and after the fix.**

- Pre-fix: 2/50 runs segfaulted or produced wrong-value failures.
- Post-fix (all three changes applied): 50/50 pass, 142 checks each,
  exit 0.

### Three root causes

1. **NOVA codegen bug #11 — two-large-operand `==` in test assertions**
   (primary). `ce_eq(label, 16777215, 16777215)` where both operands are
   >= 0x100000 dispatches `==` to `_nova_str_eq`, which dereferences the
   integer as a heap pointer. The `_nova_eq` fast path suppresses this in
   most runs but is not guaranteed.

2. **NOVA codegen bug #11 — two-large-operand `==` in `_ice_turn_is_parse_err`**
   (secondary, wrong-branch cause). Comparing a list pointer against negative
   TURN_ERR_* constants (which are large unsigned values) dispatches to
   `_nova_str_eq`. This caused the 401 detection logic to misfire, leading
   to wrong return codes and assertion failures.

3. **NOVA large hex literal miscompilation** (tertiary, wrong-value cause).
   `0x2112A442` in the test helper was sometimes compiled with the wrong
   value, causing the TURN magic cookie check to fail on synthesized test
   packets.

## Decision

### Fix 1 — `tests/unit/test_ice_turn.nova`

Replace the two `ce_eq` calls comparing `ice_turn_relay_priority()` against
`16777215` or `r30c` with the `int_xor`-based equivalence idiom:

```nova
// test_relay_priority_rfc_formula:
ce_eq("relay priority = 16777215 (RFC 8445 §5.1.2.1)",
      int_xor(ice_turn_relay_priority(), 16777215), 0)

// test_relay_priority_matches_r30c:
ce_eq("R35D priority = R30C priority (RELAY, lp=65535, c=1)",
      int_xor(ice_turn_relay_priority(), r30c), 0)
```

`int_xor` is a pure scalar built-in unaffected by smart-op dispatch; it
returns 0 iff the two values are equal; `0 == 0` is always safe (0 <
0x100000).

### Fix 2 — `src/federation/ice_turn.nova`

Replace the series of `r == TURN_ERR_*` comparisons in
`_ice_turn_is_parse_err` with a single sign-bit test:

```nova
fn _ice_turn_is_parse_err(r) {
    // TURN_ERR_* are negative integers; list (success) is a positive
    // heap pointer. `r < 0` is safe: the constant 0 is always < 0x100000,
    // so only one operand is ever large -- the smart-op takes the scalar
    // integer (signed cmp) path, never the pointer path.
    if r < 0 { return 1 }
    return 0
}
```

### Fix 3 — `tests/unit/test_ice_turn.nova`

Replace the large hex literal `0x2112A442` in `_itt_emit_401_with_attrs`
with its decimal equivalent:

```nova
_turn_test_put_u32(buf, 4, 554869826)   // was: 0x2112A442
```

## Consequences

- `test_ice_turn` passes **50/50 runs** after all three fixes. The flake is
  eliminated.
- Check count is 142 (unchanged): all original 142 checks are preserved.
  The `int_xor` rewrite changes operand values passed to `ce_eq` but
  preserves test semantics (both pass iff the original equality holds).
- Reverse-dependency tests are unaffected:
  - `test_turn`:        452 checks, exit 0.
  - `test_turn_server`: 111 checks, exit 0.
  - `test_webrtc`:       59 checks, exit 0.
  - `test_ice`:          70 checks, exit 0.
- `make lint-ints` continues to pass.

## Honest gaps

- **`int_safety_lint.py` does not catch two-large-operand `==` / `!=`.**
  Already noted in ADR-0066 and again in ADR-0069. The cases found here
  are exactly the class the lint admits it cannot see. Extending the lint
  to detect large-literal comparisons would have caught the test assertions
  in Fix 1. The `_ice_turn_is_parse_err` case (Fix 2) requires value-range
  analysis (knowing that `0 - N` is a large unsigned) which is harder to
  lint statically.
- **`_ice_turn_is_parse_err` previously used enum-matching style.** The
  `r < 0` fix is semantically equivalent but less explicit about which
  error codes are recognized. If new TURN_ERR_* constants are ever added
  with non-negative values this guard would silently pass them as success.
  A comment documents the invariant.
- **Large hex literal miscompilation is undocumented in ADR-0064/ADR-0066.**
  First identified in ADR-0069 for `test_turn.nova`; now found in
  `test_ice_turn.nova`. Only decimal literals are safe for values >=
  0x100000. Applying this standard to the full codebase is out of scope
  for this fix but should be tracked.
- **The underlying NOVA bugs are not fixed here.** As with all prior P0
  fixes, the NOVA compiler/runtime is intentionally left unmodified (the
  self-hosting bootstrap is unrecoverable if broken). All fixes are app-
  level workarounds.

## Implementation Notes

**Files changed:**

- `tests/unit/test_ice_turn.nova`
  - Line ~126 (`test_relay_priority_rfc_formula`):
    `ce_eq(..., ice_turn_relay_priority(), 16777215)` →
    `ce_eq(..., int_xor(ice_turn_relay_priority(), 16777215), 0)`
  - Lines ~134-135 (`test_relay_priority_matches_r30c`):
    `ce_eq(..., ice_turn_relay_priority(), r30c)` →
    `ce_eq(..., int_xor(ice_turn_relay_priority(), r30c), 0)`
  - Line ~574 (`_itt_emit_401_with_attrs`):
    `_turn_test_put_u32(buf, 4, 0x2112A442)` → `..., 554869826)`

- `src/federation/ice_turn.nova`
  - `_ice_turn_is_parse_err` (~line 372-385):
    Seven `r == TURN_ERR_*` checks replaced with single `if r < 0`

**Probes:** `tests/unit/_probe_priority.nova`, `_probe_sort.nova`,
`_probe_gt.nova`, `_probe_mul.nova`, `_probe_pair_pri.nova` were created
during investigation and deleted after use.

**Run counts:**
- Pre-fix: intermittent crash (once in full suite run; ~2/50 in repeated
  50-run stress test after investigation reproduced the conditions).
- Post-fix (all three changes applied): 50/50 pass, 142 checks each, exit 0.

**Companion ADRs:** 0063 (stream_http), 0064 (pack segfaults), 0065 (dtls12
hang), 0066 (int-safety standard + lint), 0067 (CI unblock), 0068 (dtls12
epoch fix), 0069 (turn flaky segfault — sibling fix for TURN_MAGIC_COOKIE
comparisons and hex literal miscompilation).
