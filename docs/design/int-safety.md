# Integer safety in CrossEngin (NOVA codegen bug #11)

> Developer guide. Companion to ADR-0066 and `NOVA/NOVA_BUG_THRESHOLD.md`.
> TL;DR: **for any integer arithmetic that can reach 1,048,576, use the `int_*`
> builtins, not raw `+`/`*`/comparisons.** Run `make lint-ints` before you push.

## The hazard

NOVA overloads eight operators for both numbers and strings/lists and decides
which at runtime by *magnitude*: an operand `>= 0x100000` (1,048,576 = 1 MB) is
assumed to be a heap pointer. When a real integer crosses that line, the
operation is misrouted into string/list code → **wrong result or SIGSEGV**.

**Affected operators (smart-dispatched):**

| `+` | `*` | `<` | `>` | `<=` | `>=` | `==` | `!=` |
|-----|-----|-----|-----|------|------|------|------|

**NOT affected (pure scalar, always safe at any magnitude):**
`-`  `/`  `%`  `&`  `|`  `^`  `~`  `<<`  `>>`

## The rule

Use the scalar-only escape-hatch builtins whenever an operand **or the result**
can reach `0x100000`, or in a hot loop:

| Need | Use | Not |
|------|-----|-----|
| add | `int_add(a, b)` | `a + b` |
| subtract | `int_sub(a, b)` (or raw `-`, which is safe) | — |
| multiply | `int_mul(a, b)` | `a * b` |
| divide / mod | `int_div(a, b)` / `int_mod(a, b)` | — |
| shift | `int_shl(a, k)` / `int_shr(a, k)` | — |
| bitwise | `int_and/or/xor(a, b)` (or raw, which is safe) | — |

Raw `+` and `*` remain correct — and idiomatic — for their string/list meaning:

```nova
let greeting = "hello, " + name   // string concat: fine
let rule     = "-" * 80           // string repeat: fine
let buf      = [0] * 256          // list repeat: fine
```

These are *only* unsafe for large-integer arithmetic.

## Worked example (the gossip LCG)

```nova
// UNSAFE: x (a ~2^31 seed) and 1103515245 both exceed 0x100000 -> raw `*`
//         miscompiles for large seeds.
let v = (x * 1103515245 + 12345) - ((x * 1103515245 + 12345) / m31) * m31

// SAFE: identical arithmetic via the int_* builtins.
let ax = int_add(int_mul(x, 1103515245), 12345)
let v  = int_mod(ax, m31)
```

## The CI gate

`make lint-ints` (`scripts/int_safety_lint.py`) flags large integer **literals**
used as a raw `*` operand outside an `int_*` call — the dominant trigger. It is
the automated half of the standard:

- Fix the flagged line with `int_*` (preferred), **or**
- if the line is genuinely safe and you've verified it, annotate it with a
  trailing `// int-safe` comment to silence the lint.

### What the lint can and cannot catch

- ✅ `x * 16777216`, LCG multipliers, byte-packing literals.
- ❌ large values carried only in **variables** (`a * b` where both are large at
  runtime) — no static range info; covered by this standard under review.
- ❌ two large operands of `+` or a comparison — rare; covered by review.

So the lint is a backstop, not a substitute for applying the rule when you write
arithmetic on values that can grow past a megabyte (timestamps in ns, hashes,
fixed-point milli accumulators, PRNGs, packed addresses, sizes).

## The permanent fix (tracked, NOVA side)

The real resolution is a low-bit pointer tag in `NOVA/src/compiler/codegen.nova`
so dispatch is by tag, not magnitude (see ADR-0066 → "Tracked NOVA work item").
Until that lands, this standard + `make lint-ints` keep CrossEngin safe.
