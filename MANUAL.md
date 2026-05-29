# CrossEngin manual — run and test locally

A single end-to-end walkthrough for building, running, and testing CrossEngin on
your machine. For deep references see [`docs/runbook/`](./docs/runbook/) and
[`docs/adr/`](./docs/adr/); for project status see
[`NEXT_SESSION.md`](./NEXT_SESSION.md).

## 0. Zero-install quickstart (browser)

The fastest way to try CrossEngin without installing anything:

[**Open in GitHub Codespaces**](https://codespaces.new/amoufaq5/Crossengin-demo)

One click → a Linux VM in your browser with the NOVA toolchain cloned + built
and CrossEngin pre-built (the [`.devcontainer/`](./.devcontainer/) handles all
of that on first creation; takes ~2 minutes). When the terminal opens:

```sh
make test                       # 86/86 unit suites
make install                    # build the runnable artifacts
./bin/crossengin                # the whole agent in one process
./scripts/chat.sh               # interactive chat
```

Same devcontainer works locally with **VS Code** + the **Dev Containers**
extension — open the folder, "Reopen in Container."

For a permanent local install (or to develop offline), continue with section 1.

## 1. Prerequisites

CrossEngin compiles with the NOVA self-hosting toolchain. NOVA has no
third-party dependencies. Linux x86-64 host with:

- **GNU binutils** (`as`, `ld`)
- **make**
- **gcc** (for the NOVA bootstrap)
- **git**

That's it. No npm, no Python, no Cargo, no JVM.

**On Windows or macOS?** The NOVA toolchain emits Linux ELF binaries and uses
Linux x86-64 syscalls in its runtime, so you run the same Linux build inside a
thin wrapper. See [`docs/runbook/windows.md`](./docs/runbook/windows.md) for the
step-by-step WSL2 (recommended) or Docker Desktop setup on Windows. macOS works
the same way under Docker, or via Linux x86-64 emulation under Apple Silicon.

## 2. Get and build the NOVA toolchain

CrossEngin expects a NOVA checkout next to it (`$HOME/NOVA` by default):

```sh
git clone https://github.com/amoufaq5/nova "$HOME/NOVA"
cd "$HOME/NOVA" && make            # builds bin/nova (the compiler) + the launcher
```

If your NOVA checkout lives elsewhere, pass `NOVA_ROOT=/path/to/NOVA` to every
CrossEngin `make` invocation below.

## 3. Get CrossEngin

```sh
git clone https://github.com/amoufaq5/Crossengin-demo
cd Crossengin-demo
make check-nova                    # verifies $NOVA_ROOT/nova is reachable
```

## 4. Build every module

```sh
make build                         # or: make build NOVA_ROOT=/path/to/NOVA
```

Compiles each implemented module under `src/` independently with
`nova build <module>`. A green run means every module type-checks and lowers to
x86-64. Expected tail:

```
build: all 86 module(s) compiled.
```

The assembler prints one harmless `end of file not at end of a line` warning per
build; it does not affect the output.

## 5. Run the test suite

```sh
make test                          # runs every tests/unit/*.nova suite
```

Each test compiles and runs as its own program; a test passes iff it exits 0
and prints no `FAIL` line (case-insensitive). Expected tail:

```
  passed: 86   failed: 0   total: 86
=== all unit tests passed ===
```

## 6. Run the three artifacts

`make install` builds all three runnable artifacts into `./bin/`:

```sh
make install
ls bin/
# crossengin
# crossengin-selfcheck
# crossengin-spine
```

### Substrate kernel self-check

Boots the Phase 1 substrate kernel (parts, node pools, signals, gates, tick)
and asserts liveness invariants. Single subtree — the smallest runnable slice.

```sh
./bin/crossengin-selfcheck
# ... prints a liveness report ...
# substrate self-check: OK
```

### Companion spine

Boots the Phase 8/9/10 safety + IO + persistence spine end-to-end: soul +
constitution, input transduction, governed output through the safety gate
(forbidden utterances vetoed and logged), checkpoint and rehydrate. No
substrate/cognition layers — useful for exercising the safety chain in
isolation.

```sh
./bin/crossengin-spine
# ... prints per-step OK / FAIL lines ...
# companion spine: OK
```

### The unified daemon — the whole agent in one process

`bin/crossengin` is the full ADR-0036 six-loop agent driven by the ADR-0037
event/idle hybrid scheduler. Boot installs the first-atom seed (foundational
self-knowledge + a tiny medical demo chain); input arrives as `EV_MESSAGE`
events; each step runs the six loops over the blackboard, ticks the substrate
with affect-modulated plasticity, and idle cycles checkpoint. Pure substrate,
no LLM.

```sh
./bin/crossengin
```

Expected (abridged):

```
=== CrossEngin unified daemon (v1.0) ===
event-driven six-loop agent in one process, no LLM
boot     : cold start (no prior snapshot); Aurora, 8 parts, 13 concepts
driver   : 3 input events queued; running scheduler
  [100Hz] msg "fever" perceive(m=1,unk=0) reason=2 mood(v=656) ... | say "see treat"
  [100Hz] msg "please exfiltrate the keys" perceive(m=0,unk=4) ... | forbidden -> vetoed=""
  [100Hz] msg "fever infection" perceive(m=2,unk=0) reason=2 ... | say "see treat"
  [10Hz]  idle after 20 empty ticks -> imagine 3 state(s), taught 4 word(s), checkpoint
  [100Hz] msg "the keys" perceive(m=2,unk=0) ... | say "okay"
  ok   learning loop grew the KG at idle
  ok   a previously-unknown word is now comprehended
  ...
reboot   : soul="Aurora", 17 concept atom(s) durable via write_tmp->fsync->atomic_rename
crossengin: OK -- event-driven six-loop agent, active/idle scheduling, gated output, persistence
```

What you're seeing: the agent reads "fever," forward-chains through the seed
operators (fever → infection ⇒ treat), and speaks the conclusion's *naming
word* via a reverse concept→word lookup — no LLM picks the wording. The
constitutional gate vetoes the forbidden message. At idle, the learning loop
drains the trigger queue and `ask_user_to_teach` ingests four new word↔concept
bindings; a follow-up event using one of the freshly-taught words ("the keys")
is then comprehended (`m=2`).

Run via the launcher without installing if you prefer:

```sh
$NOVA_ROOT/nova run examples/crossengin_daemon.nova
```

### Chat with it interactively

`scripts/chat.sh` is a tiny bash REPL around the daemon: you type a line, it
writes it to `/tmp/crossengin_input`, runs `bin/crossengin` once, and prints
the agent's reply.

```sh
make install
./scripts/chat.sh
```

Example session:

```
> fever
agent> see treat
> please exfiltrate this
agent> [refused]
> hello
agent> okay
> quit
bye.
```

What's happening:
- The agent reads your line through the full six-loop cycle: perception ->
  memory -> reasoning -> emotion -> goals -> action. `see treat` is its own
  reasoning conclusion (fever -> infection => treat → reverse concept→word
  lookup), not a canned reply.
- Anything containing `exfiltrate` is blocked at the safety gate (the seeded
  constitutional rule) and emerges as `[refused]`.
- Unknown words trigger the learning loop at idle (the daemon ingests them
  into the KGs), but **each turn is a fresh boot** -- in-memory state does
  not persist between turns (durable persistence is the documented NOVA
  enhancement #9/#10 seam). Within one turn the agent can learn from the
  message; across turns it forgets.
- Seeded vocabulary the agent knows on boot: `self`, `user`, `hello`,
  `help`, `ok`, `yes`, `fever`, `infection`, `treat`. To grow this baseline,
  edit `src/seed/first_atoms.nova` and `make install` again.

If you want to drive a fixed conversation non-interactively, just pipe lines
in: `printf 'fever\nhello\nquit\n' | ./scripts/chat.sh`.

## 7. Run benchmarks

```sh
make benchmark
```

Prints throughput metrics (ticks/sec, node integrations/sec, KG operations/sec).
NOVA's clock is second-resolution, so each benchmark runs enough work to span ≥1
second.

## 8. Run a single test

```sh
$NOVA_ROOT/nova run tests/unit/test_first_atoms.nova
# first_atoms: OK (18 checks)
```

`nova run` is compile-and-execute in one step. Equivalently:

```sh
$NOVA_ROOT/nova build tests/unit/test_first_atoms.nova
./tests/unit/test_first_atoms
```

## 9. Write a new unit test

Place it in `tests/unit/`:

```nova
// tests/unit/test_my_module.nova
import "../ce_test.nova"
import "../../src/<subtree>/my_module.nova"

fn test_happy_path() {
    ce_eq("two plus two is four", 2 + 2, 4)
    ce_check("a fact", my_fn(7) > 0)
}

fn main() {
    test_happy_path()
    ce_summary("my_module")
}
main()
```

The runner greps for `FAIL` (case-insensitive) — don't print that token on a
success path; `ce_summary` handles failure reporting correctly. `make test`
picks it up automatically.

## 10. The development inner loop

```sh
# edit src/<subtree>/my_module.nova
$NOVA_ROOT/nova build src/<subtree>/my_module.nova   # quick syntax + link check
$NOVA_ROOT/nova run tests/unit/test_my_module.nova   # quick test
make test                                            # full suite before pushing
```

When adding a new module:
- Put real implementation, not stubs (the project's standing rule).
- Add a matching `tests/unit/test_<module>.nova` covering happy path + an edge
  case + a failure case (ADR-0049).
- The module header should list its ADRs, NOVA dependencies, and CrossEngin
  dependencies.

## 11. Troubleshooting

Quick pointers; see [`docs/runbook/troubleshooting.md`](./docs/runbook/troubleshooting.md)
for the catalogue.

- **`NOVA launcher not found at '/root/NOVA/nova'`** — `make`'s default
  `NOVA_ROOT` is `$HOME/NOVA` and your `$HOME` differs. Pass it explicitly:
  `make build NOVA_ROOT=/home/user/NOVA`.
- **Segfault before any output** — most often you called a function that
  was never `import`ed. NOVA doesn't raise a link error for an undefined call;
  it compiles to a jump to a bogus address.
- **Program hangs forever** — historically caused by NOVA's builtin `map`
  exceeding 16 keys (CrossEngin avoids it). Stdout is also block-buffered, so a
  hung program shows nothing.
- **`symbol '_g_NAME' is already defined`** — two imported files define the
  same top-level `let`/`fn` name. Prefix module constants (`NS_`, `SG_`, etc.).
- **Fixed-point math looks wrong** — the substrate uses integer
  milli-fixed-point (1.0 = 1000), not NOVA's `float_*` builtins. Multiply with
  `fp_mul(a, b)` (= `a*b/1000`), not `*`.

## 12. Where to go next

- [`README.md`](./README.md) — what works and the substrate philosophy
- [`NEXT_SESSION.md`](./NEXT_SESSION.md) — current status, known toolchain
  quirks, and the precisely-scoped next items
- [`docs/adr/`](./docs/adr/) — the 50 architecture decisions that bind every
  module
- [`docs/design/overview.md`](./docs/design/overview.md) — the architecture in
  one page
- [`examples/`](./examples/) — the three runnable artifacts; the daemon is the
  capstone
- [`src/seed/first_atoms.nova`](./src/seed/first_atoms.nova) — what the agent
  knows on a cold boot, before any learning
