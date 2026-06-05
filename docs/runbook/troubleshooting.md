# Troubleshooting

## "NOVA launcher not found at '/root/NOVA/nova'"

The Makefile defaults `NOVA_ROOT` to `$HOME/NOVA`. If your shell's `$HOME` is
not where NOVA lives (e.g. it is `/root` but NOVA is at `/home/user/NOVA`), pass
the path explicitly:

```sh
make build NOVA_ROOT=/home/user/NOVA
```

## A program segfaults immediately, before printing anything

The most common cause is **calling a function that was never imported**. NOVA
does not raise a link error for an undefined function call -- it compiles to a
jump to a bogus address and segfaults at runtime. Check that every module whose
functions you call is `import`ed (directly or transitively). CrossEngin imports
are `#include`-style and de-duplicated, so importing the top-level module under
use is enough.

## A program hangs forever (no output, then a timeout)

Two known causes:

1. **Builtin `map` over 16 keys.** NOVA's builtin `map` has a fixed capacity of
   16 and linear-probes forever once full. CrossEngin therefore avoids the
   builtin map for anything that can exceed 16 distinct keys, using id- or
   type-indexed arrays instead (synapse adjacency, the part registry, the gate
   table). Do not reintroduce a `map_new()` with an unbounded key set.
2. **Buffered output.** NOVA stdout is block-buffered and flushes on exit. A
   hung program shows *no* output even past the point of the hang. To locate a
   hang, build the binary and run it directly (it still won't flush until exit,
   so bisect by making the suspect region exit early).

## "symbol `_g_NAME' is already defined" at assembly time

Two imported files define a top-level `let NAME` (or `fn NAME`) with the same
name. Global names share one flat namespace across all imports. Prefix module
constants (the substrate uses `NS_`, `SG_`, `PART_`, `GATE_`, `XSIG_`, ...) and
rename the collision.

## Fixed-point math looks wrong

The substrate uses **integer milli-fixed-point** (1.0 == 1000), not NOVA's
`float_*` builtins (which operate on IEEE-754 doubles -- a different
representation). Multiply with `fp_mul(a, b)` (= `a*b/1000`), not `*`. A raw
`500` means 0.5, not 500.0.

## `map_has` returns 0 for a key you just set

NOVA's builtin `map` treats a stored value of `0` as absent. If you must use a
map with integer values that can be 0, store `value + 1` and subtract on read.
(CrossEngin avoids the builtin map; this is noted for completeness.)
