# ADR-0063: Fix `_stream_http_ip_to_int` IP-packing overflow (NOVA bug #11)

## Status

Proposed

## Date

2026-06-12

## Context

ADR-0058 (Coverage closure, 2026-06-11) documented a latent bug in
`src/io/transducers/stream_http.nova`: the `_stream_http_ip_to_int` helper
packed a dotted-quad IP address using raw `*` and `+` operators:

```nova
let b_p = b * k256
let c_p = c * k256 * k256
let d_p = d * k256 * k256 * k256
return a + b_p + c_p + d_p
```

NOVA codegen bug #11 (documented in `/home/user/NOVA/NOVA_BUG_THRESHOLD.md`) causes
NOVA's "smart-op" runtime dispatch for `+`, `*`, `==`, `!=`, `<`, `>`, `<=`,
`>=` to inspect both operands against the threshold `0x100000` (1048576). If
either operand is at or above that threshold the smart-op misroutes the
operation: `*` jumps to `str_repeat` / `_nova_list_repeat` and `+` jumps to
`_nova_concat`, producing garbage results or a SIGSEGV.

In the IP-packing code:

- `c * 65536` produces a result >= 0x100000 for *any* non-zero third octet
  (e.g. `1 * 65536 = 65536 = 0x10000`, which is still below the threshold, but
  `16 * 65536 = 1048576 = 0x100000` already hits it).
- `d * 16777216` (256^3) produces a result >= 0x100000 for any fourth octet >= 1.
  Every real-world IPv4 address whose last octet is >= 1 overflows here.
- The accumulating `+` chain then combines large intermediates, triggering the
  `+` → `_nova_concat` misroute too.

ADR-0058 deferred the fix and narrowed the test suite to low-octet addresses
(4th octet <= 15) to stay below the threshold. This ADR closes that deferral.

## Decision

Rewrite the packing step in `_stream_http_ip_to_int` using the `int_mul` and
`int_add` escape-hatch builtins. These builtins emit plain x86-64 scalar
instructions (`imul`, `lea`) with no smart-op dispatch prologue and are safe for
the full int64 range.

The key insight: *writing a large integer literal is safe*; only the arithmetic
*operations* (`+`, `*`, etc.) are affected by bug #11. Passing a literal such as
`16777216` directly to `int_mul` does not trigger the threshold check. The fix
therefore uses plain literal multipliers:

```nova
let b_p = int_mul(b, 256)
let c_p = int_mul(c, 65536)
let d_p = int_mul(d, 16777216)
return int_add(int_add(int_add(a, b_p), c_p), d_p)
```

The validation logic (require exactly 4 tokens, each in 0..255) is left
completely intact.

The same `int_mul` / `int_add` pattern is already established in the repo:
`src/kg/hdc_embed.nova`, `src/language/number_words.nova`, and
`src/safety/bignum_2048.nova` all use it for arithmetic that crosses the
0x100000 threshold.

**Why string-comparison in the new tests:**
Comparing two integers >= 0x100000 with `==` also triggers bug #11 (the
`==` smart-op jumps to `_nova_str_eq`). To assert large expected values
correctly we convert the result to a string with `int_to_str` and compare with
`ce_str_eq`. This is the same technique used in `tests/unit/test_bignum.nova`
and `examples/bench_int_safe.nova`.

## Consequences

- `_stream_http_ip_to_int` is now correct for all valid IPv4 addresses,
  including `127.0.0.1`, `192.168.x.y`, `10.x.x.x`, and `255.255.255.255`.
- The production code path (`stream_http_init` → `make_sockaddr_in`) will
  correctly encode any operator-supplied bind address via `CE_STREAM_HTTP_BIND`.
- The test suite grows from 20 to 24 checks; all pass.
- No other file is modified.

## Honest gaps

This fix addresses one specific instance of NOVA codegen bug #11. The bug is
systemic: any module that performs integer arithmetic whose operands or result
can reach 0x100000 is at risk. A repo-wide `int`-safety lint (grepping for raw
`*` and `+` with large literal operands, or calls whose results feed into other
arithmetic) is being tracked separately and is out of scope for this ADR.

The long-term fix for bug #11 is a tagged-value representation for all NOVA
integers (see `NOVA_BUG_THRESHOLD.md` "Future work — Option 1"). Until that
lands, the `int_*` builtins remain the correct and blessed workaround for any
arithmetic path whose values may exceed 0x100000.

## Implementation Notes

Files touched:

- `src/io/transducers/stream_http.nova` — lines 120-128: replaced the four
  `let k256 = 256` / `b * k256` / `c * k256 * k256` / `d * k256 * k256 * k256`
  / `a + b_p + c_p + d_p` lines with `int_mul` / `int_add` equivalents (plus
  an explanatory comment).
- `tests/unit/test_stream_http.nova` — added `test_ip_to_int_high_octets()` with
  4 new `ce_str_eq` assertions covering `192.168.1.10` (167880896),
  `10.0.0.1` (16777226), `255.255.255.255` (4294967295), and `1.2.3.4`
  (67305985); wired it into `main()`.
- `docs/adr/0063-stream-http-ip-overflow-fix.md` — this document.

Check count: 24 (up from 20 in ADR-0058).
