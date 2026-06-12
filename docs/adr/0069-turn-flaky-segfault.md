# ADR-0069: Fix flaky SIGSEGV in test_turn — NOVA codegen bug #11 (two-large-operand `!=`) + large hex literal miscompilation

## Status

Proposed

## Date

2026-06-12

## Context

ADR-0067 recorded that `test_turn` intermittently segfaulted (exit 139) under
the full suite run but passed 12/12 times in isolation. The primary hypothesis
was a silent undefined-symbol reference (the same class of bug that caused
`test_code_review_pack` / `test_pack_registry` to segfault — ADR-0064). The
symptom was ASLR-dependent: the crash address changed between runs, exactly as
expected when a garbage address is called or dereferenced.

ADR-0067 left this as a tracked flake: "no deterministic reproducer yet; root-
causing it likely requires the silent-undefined-symbol toolchain fix or a memory
sanitiser." This ADR records the investigation that produced a deterministic
reproducer and the two root causes found.

### Investigation

**Step 1 — undefined-symbol audit.** All functions called in
`tests/unit/test_turn.nova` were mapped to their definitions:

- `ce_eq`, `ce_assert`, `ce_fail`, `suite_begin`, `suite_end` — defined in
  the test harness (imported).
- All `turn_*` and `_turn_*` symbols — defined in
  `src/federation/turn.nova` (imported).
- `malloc`, `free`, `load8` — NOVA built-ins, always resolved.
- `push`, `pop`, `len`, `str_eq` — NOVA built-ins.

No undefined symbol was found. The undefined-symbol hypothesis was ruled out.

**Step 2 — int-safety lint.** `make lint-ints` (scripts/int_safety_lint.py)
reported clean for both `src/federation/turn.nova` and
`tests/unit/test_turn.nova`. This is expected: the lint only flags large
literals adjacent to `*`; it does not cover `==` / `!=` with large operands
(the "two-large-operand" case noted as a known gap in ADR-0066).

**Step 3 — manual audit of smart-op candidates.** The NOVA smart-op table
(NOVA/NOVA_BUG_THRESHOLD.md) lists eight operators that are dispatched through
pointer-aware code when BOTH operands are ≥ 0x100000 (1,048,576):
`+  *  <  >  <=  >=  ==  !=`. A systematic scan of `turn.nova` against
`TURN_MAGIC_COOKIE = 554869826 (0x2112A442)` found two sites:

```
_turn_walk_attrs   (line ~739): if cookie != TURN_MAGIC_COOKIE { ... }
turn_classify_message (line ~782): if cookie != TURN_MAGIC_COOKIE { ... }
```

In both cases `cookie` is read from the wire buffer via `_turn_get_u32` (which
may return any 32-bit value), and `TURN_MAGIC_COOKIE` is always `0x2112A442` ≥
0x100000. When the incoming packet carries a valid cookie (`cookie ==
0x2112A442`), **both** operands are ≥ 0x100000, triggering bug #11's `!=`
dispatch to `_nova_str_eq`. Under ASLR, the integer `cookie` value is treated
as a heap pointer and dereferenced, causing SIGSEGV. When the cookie is wrong
(e.g. all-zeros in error-path tests), only one operand is large and the bug is
not triggered, which explains why most tests pass while only the
valid-magic-cookie path crashes.

**Step 4 — 100-run stability before the fix.** Confirmed the flake: 2/100 runs
segfaulted. The failing output showed all attribute-walking tests returning
`-2` (TURN_ERR_COOKIE) — precisely the check_cookie guard being hit via the
garbage string comparison.

**Step 5 — second bug: large hex literal miscompilation.** After fixing the
`!=` comparisons in `turn.nova`, rerunning 100 times still produced 2 failures
— but now with wrong byte values (`u32 cookie byte 0 expected=33 got=3`). A
`/tmp` probe confirmed that `int_shr(0x2112A442, 24)` sometimes returns wrong
values, while `int_shr(554869826, 24)` always returns 33. This is a distinct
NOVA compiler bug: large hex literals (≥ 0x100000) are sometimes miscompiled
with incorrect constant values, whereas decimal literals of the same value are
always correct. All large hex literals in `test_turn.nova` (six occurrences of
`0x2112A442` as a `_turn_test_put_u32` argument, two as `int_shr` operands, one
`int_xor` operand, one `0xC0000201`, one `0x12345678`) were replaced with their
decimal equivalents.

### Two root causes

1. **NOVA codegen bug #11 — two-large-operand `!=`** (primary SIGSEGV cause).
   `cookie != TURN_MAGIC_COOKIE` where both values are ≥ 0x100000 dispatches
   `!=` to `_nova_str_eq`, which dereferences the integer as a heap pointer.
   Under ASLR this address is usually unmapped → SIGSEGV.

2. **NOVA large hex literal miscompilation** (secondary wrong-value cause). Hex
   literals ≥ 0x100000 (such as `0x2112A442`) are sometimes stored with wrong
   constant values in the compiled binary; decimal literals of the same value
   compile correctly. Manifests as wrong bytes in buffers constructed by tests.

## Decision

### Fix 1 — `src/federation/turn.nova`

Replace both `cookie != TURN_MAGIC_COOKIE` comparisons with an `int_xor`-based
guard. `int_xor` is a pure scalar built-in unaffected by smart-op dispatch; it
returns 0 iff the two values are equal; `0 != 0` is always safe (0 < 0x100000):

```nova
// _turn_walk_attrs and turn_classify_message — same change:
if int_xor(cookie, TURN_MAGIC_COOKIE) != 0 {
    // ... reject ...
}
```

### Fix 2 — `tests/unit/test_turn.nova`

Replace every large hex literal (≥ 0x100000) with its decimal equivalent:

- `0x2112A442` → `554869826` (TURN_MAGIC_COOKIE value, 9 occurrences total)
- `0xC0000201` → `3221225985` (XOR address test)
- `0x12345678` → `305419896`  (port/address fixture)

Additionally replace two direct `ce_eq(label, large_val, large_val)` calls with
`ce_eq(label, int_xor(large_val, other), 0)` to avoid the same two-large-
operand `==` hazard in the test assertions themselves.

## Consequences

- `test_turn` passes **100/100 runs** after both fixes. The flake is eliminated.
- Check count is 452 (was 451): one existing `ce_eq("u32 round-trip", ...,
  0x2112A442)` check was split into explicit byte checks for bytes 1 and 2
  (bytes 0 and 3 checks already existed); all original 451 checks are
  preserved.
- No other test suite is affected: only `src/federation/turn.nova` and
  `tests/unit/test_turn.nova` were changed.
- `make lint-ints` continues to pass (the `int_xor` call-sites are not in the
  lint's scope, but they are correct by construction).

## Honest gaps

- **The `int_safety_lint.py` does not catch two-large-operand `==` / `!=`.**
  This was already noted as a gap in ADR-0066. The cases found here (`cookie !=
  TURN_MAGIC_COOKIE`) are exactly the class the lint admits it cannot see
  ("the rarer two-large-operand `+`/comparison case"). Extending the lint to
  detect large-literal comparisons (`==` / `!=`) would have caught this.
  Tracked as a lint improvement.
- **Large hex literal miscompilation is undocumented in ADR-0064/ADR-0066.**
  It is a third distinct NOVA compiler bug (separate from silent-undefined-
  symbol and codegen bug #11). Only decimal literals are safe for values ≥
  0x100000. Applying this standard to the full codebase is out of scope for
  this fix but should be tracked.
- **The underlying NOVA bugs are not fixed here.** As with all prior P0 fixes,
  the NOVA compiler/runtime is intentionally left unmodified (the self-hosting
  bootstrap is unrecoverable if broken). The fixes are app-level workarounds.
- **`test_dtls12` (10 failures) remains unresolved.** See ADR-0067.

## Implementation Notes

**Files changed:**

- `src/federation/turn.nova`
  - `_turn_walk_attrs` (~line 739): `cookie != TURN_MAGIC_COOKIE` →
    `int_xor(cookie, TURN_MAGIC_COOKIE) != 0`
  - `turn_classify_message` (~line 782): same replacement

- `tests/unit/test_turn.nova`
  - ~line 100: `_turn_test_put_u32(buf, 0, 0x2112A442)` + single round-trip
    check → decimal `554869826` + explicit byte-0..3 checks
  - ~line 196: `let addr = 0xC0000201` → `let addr = 3221225985`
  - ~line 203: `int_xor(addr, 0x2112A442)` → `int_xor(addr, 554869826)`
  - `ce_eq("xor addr matches manual", x_addr, expected_addr)` →
    `ce_eq("xor addr matches manual", int_xor(x_addr, expected_addr), 0)`
  - `ce_eq("xor round-trip addr", res2[0], addr)` →
    `ce_eq("xor round-trip addr", int_xor(res2[0], addr), 0)`
  - 6× `_turn_test_put_u32(buf, 4, 0x2112A442)` → `…554869826…`
  - 1× `int_shr(0x2112A442, 16)` → `int_shr(554869826, 16)`
  - 2× `int_shr(0x2112A442, (3 - m) * 8)` → `int_shr(554869826, …)`
  - 1× `_turn_test_put_u32(buf, off + 4, 0x12345678)` → `…305419896…`

**Probes:** `/tmp/probe_turn_bug.nova` and `/tmp/probe_u32.nova` were created
during investigation and deleted after use.

**Run counts:**
- Pre-fix: 2/100 segfaulted (exit 139); 2/100 produced wrong-value failures.
- Post-fix (both changes applied): 100/100 pass, 452 checks each, exit 0.

**Companion ADRs:** 0063 (stream_http), 0064 (pack segfaults, undefined-symbol
pattern), 0065 (dtls12 hang), 0066 (int-safety standard + lint), 0067 (CI
unblock; first recorded `test_turn` flake).
