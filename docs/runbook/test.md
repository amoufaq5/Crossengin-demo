# Test

## Unit tests

```sh
make test                         # or: make test NOVA_ROOT=/path/to/NOVA
```

`make test` runs `scripts/test.sh`, which compiles and runs every
`tests/unit/*.nova` program. A test **passes** iff it exits 0 and prints no line
containing `FAIL` (case-insensitive). Each test uses the shared harness in
`tests/ce_test.nova` (`ce_eq`, `ce_check`, `ce_str_eq`, `ce_near`, `ce_summary`);
`ce_summary` prints a per-suite tally and exits non-zero on any failure.

Every implemented module has a matching `tests/unit/test_<module>.nova` covering
a happy path, edge cases, and a failure/bad-input case (ADR-0049).

## Benchmarks

```sh
make benchmark                    # runs every tests/benchmark/*.nova
```

Benchmarks print throughput metrics (ticks/sec, node-integrations/sec). NOVA's
clock is second-resolution, so each benchmark runs enough work to span ≥1s.

## Writing a new unit test

```nova
import "../ce_test.nova"
import "../../src/substrate/<module>.nova"

fn test_something() {
    ce_eq("label", got, expected)
    ce_check("label", condition)
}

fn main() {
    test_something()
    ce_summary("<module>")
}
main()
```

Place it in `tests/unit/`. Do **not** print the token `FAIL` on a success path
(the runner greps for it); `ce_summary` handles failure reporting correctly.

## Gotchas (see docs/runbook/troubleshooting.md)

- NOVA's builtin `map` caps at 16 keys; CrossEngin avoids it in favor of
  id/type-indexed arrays. Don't introduce a `map_new()` with >16 distinct keys.
- NOVA does not error on a call to an undefined function -- it segfaults at
  runtime. Import every module whose functions a test calls.
