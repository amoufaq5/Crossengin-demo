# Build

CrossEngin is written in [NOVA](https://github.com/amoufaq5/nova) and compiled
with the NOVA self-hosting toolchain. NOVA has no third-party dependencies; it
needs only GNU `as`, `ld`, `make`, and `gcc`.

## 1. Get and build NOVA

CrossEngin expects a NOVA checkout next to it (`$HOME/NOVA` by default):

```sh
git clone https://github.com/amoufaq5/nova "$HOME/NOVA"
cd "$HOME/NOVA" && make          # builds bin/nova (the compiler) + the launcher
```

If your NOVA checkout lives elsewhere, pass `NOVA_ROOT=/path/to/NOVA` to every
CrossEngin `make` invocation (see below). `make check-nova` verifies the
toolchain is reachable.

## 2. Build CrossEngin

From the repository root:

```sh
make build                       # compile every module under src/ (excluding *.pending)
# or, if NOVA is not at $HOME/NOVA:
make build NOVA_ROOT=/path/to/NOVA
```

`make build` compiles each implemented module independently with
`nova build <module>`; a green run means every module type-checks and lowers to
x86-64. Interface-only modules that depend on an unlanded NOVA enhancement are
checked in as `*.nova.pending` and are intentionally skipped.

## 3. Install the runnable artifact

```sh
make install                     # builds bin/crossengin-selfcheck
./bin/crossengin-selfcheck       # boots the substrate, prints a liveness report
```

## How modules and imports resolve

- A module imports its direct CrossEngin dependencies by relative path, e.g.
  `import "node_pool_manager.nova"`. NOVA de-duplicates diamond imports, so a
  test need only import the module under test.
- NOVA runtime/core modules are imported via the `std/` namespace, e.g.
  `import "std/node_pool"`, which resolves to `$NOVA_ROOT/src/runtime/...` and
  therefore honors `NOVA_ROOT`.

## Notes

- The assembler prints one harmless warning per build
  (`end of file not at end of a line`); it does not affect the output.
- `make clean` removes `bin/` and build logs.
