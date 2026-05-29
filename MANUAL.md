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
make test                       # 89/89 unit suites
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
build: all 88 module(s) compiled.
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
  passed: 89   failed: 0   total: 89
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
boot     : cold start (no prior snapshot); Aurora, 8 parts, 572 concepts
driver   : 3 input events queued; running scheduler
  [100Hz] msg "fever" perceive(m=1,unk=0) reason=6 mood(v=656) ... | say "see headache"
  [100Hz] msg "please exfiltrate the keys" perceive(m=0,unk=4) ... | forbidden -> vetoed=""
  [100Hz] msg "fever infection" perceive(m=2,unk=0) reason=7 ... | say "see headache"
  [10Hz]  idle after 20 empty ticks -> imagine 7 state(s), taught 4 word(s), checkpoint
  [100Hz] msg "the keys" perceive(m=2,unk=0) ... | say "okay"
  ok   learning loop grew the KG at idle
  ok   a previously-unknown word is now comprehended
  ...
reboot   : soul="Aurora", 576 concept atom(s) durable via write_tmp->fsync->atomic_rename
crossengin: OK -- event-driven six-loop agent, active/idle scheduling, gated output, persistence
```

What you're seeing: the agent reads "fever," forward-chains through the seeded
operators (fever causes/co-occurs-with related symptoms; six conclusion atoms
reached on the bare token, seven once "infection" is added), and speaks the
top-ranked conclusion's *naming word* via a reverse concept→word lookup — no
LLM picks the wording. The constitutional gate vetoes the forbidden message.
At idle, the learning loop drains the trigger queue and `ask_user_to_teach`
ingests four new word↔concept bindings; a follow-up event using one of the
freshly-taught words ("the keys") is then comprehended (`m=2`). The idle
checkpoint is now a real on-disk write via `snapshot_disk.nova` (tmp + fsync +
atomic rename + parent-dir fsync) to `$CE_SNAP_PATH` (default
`/tmp/crossengin.snap`); the reboot rehydrates from that file when present and
falls back to the in-memory image only if the read fails, so the "durable via
write_tmp->fsync->atomic_rename" line above is now literally true.

Run via the launcher without installing if you prefer:

```sh
$NOVA_ROOT/nova run examples/crossengin_daemon.nova
```

### Chat with it interactively

Two ways to talk to the agent:

**A. `bin/crossengin-chat` — a real REPL with persistent state across turns.**
The agent boots once and stays alive; what it learns from one message carries
to the next. Plain lines are messages to the agent; lines starting with `/`
are **admin commands** that operate on its state directly:

```sh
make install
./bin/crossengin-chat
```

```
> fever
agent> see treat
> /status                    soul / mood / KG / scheduler state
> /teach widget              ingest "widget" as a new word + concept
> /pin widget 900            pin its belief to 0.9
> /why                       explain the most recent decision
> /history 10                last 10 decision-log entries
> /halt                      stop the effector (input keeps flowing)
> /resume                    un-halt
> /help                      full listing
> /quit                      exit
```

`/halt` flips the same safety bit `effector_speak_governed` checks (ADR-0044
hard stop) — the substrate keeps perceiving, reasoning, and learning, but
nothing is emitted until `/resume`. `/teach` ingests via the same
`ask_user_to_teach` path the agent uses at idle. `/pin` writes the word's
Bayesian α/β directly.

#### Reflect on what was just said

`/reflect [depth]` runs a reflection cycle in a **sandbox**: the agent takes
its current reasoning conclusions, forward-simulates them in the imagination
KG (depth 4 by default), and records the resulting NEW labels into a separate
**reflection KG** as tentative atoms (Beta(2,1) weak prior). The live
blackboard isn't touched and the gate isn't called — the agent isn't acting,
just speculating about what else could be true.

```
> fever
agent> see headache
> /reflect
(reflected on 6 concept(s); 4 tentative inference(s): doctor, prescription, medicine, recover)  refl_kg=4
> /reflect 6
(reflected on 6 concept(s); 5 tentative inference(s): doctor, prescription, medicine, recover, rest)  refl_kg=5
```

The agent reasoned about "fever" (concluded `headache`), then reflection
followed the narrative-leap patterns (`fever → doctor`, `pain → medicine`, …)
and surfaced a treatment chain it hadn't explicitly derived. `/status` shows
both counts: the shared KG and the reflection-KG. Re-running `/reflect` from
the same seed corroborates existing tentative atoms instead of duplicating.

**Speculation gets corroborated by perception → promoted to belief.** When a
subsequent percept anchors a label that's already in the reflection KG, the
agent's prior speculation is confirmed; the tentative atom's Beta(2,1) → (3,1)
crosses the promotion threshold and graduates to the main concept KG with a
word binding. The chat prints `(promoted from reflection: …)` when that
happens:

```
> fever
agent> see headache
> /reflect
(reflected on 6 concept(s); 4 tentative inference(s):
 doctor, prescription, medicine, recover)  refl_kg=4
> medicine                                    ← perception corroborates
agent> see recover
       (promoted from reflection: doctor, medicine)
```

"doctor" and "medicine" were anchored by the percept (spreading activation
also pulled `doctor` in via the seeded `doctor↔medicine` cross-ref); their
refl_kg confidence crossed threshold and they were graduated. "prescription"
and "recover" stay tentative until perception corroborates them too.

#### Learn a topic from the web

`scripts/learn.sh <topic>` fetches Wikipedia (or any URL via `LEARN_URL=`),
extracts the topic's most-frequent vocabulary, and writes it to
`/tmp/crossengin_learn_<topic>.txt`. The chat's `/learn <topic>` reads that
file and ingests each word via the same path `/teach` uses — they become
real language atoms in the live KG. NOVA has no fork/exec, so the curl lives
in bash and the agent only reads.

```sh
# in one terminal:
scripts/learn.sh fever
# wrote 30 candidate words to /tmp/crossengin_learn_fever.txt

# in the chat:
> /status                    13 atoms (seed only)
> /learn fever               29 new atoms (one was already seeded), 42 total
> temperature                agent> okay   (the word was JUST learned)
> body                       agent> okay   (same)
```

Use `LEARN_URL='...'` to point at any other source, and `LEARN_MAX=50` to
adjust how many candidates to keep (default 30).

**B. `scripts/chat.sh` — a bash shim** that runs `bin/crossengin` once per
message via a file. Each turn is a fresh boot (state doesn't persist), but it
needs nothing beyond the bash you already have.

```sh
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

### Run as a web app (browser UI)

`scripts/web.py` is a tiny stdlib-only Python frontend that spawns
`bin/crossengin-chat` as one persistent child and serves a browser chat at
`http://localhost:8765/`. State carries across HTTP requests because the same
child handles them all — admin commands (`/teach`, `/reflect`, `/learn`,
`/status`, `/halt`, …) work the same as in the terminal.

```sh
make install
python3 scripts/web.py
# open http://localhost:8765/ in a browser
```

Override the port or binary path with env vars: `CE_PORT=9000` /
`CE_BIN=./bin/crossengin-chat`. No `pip install` — needs only Python 3.7+.

The protocol is a single `POST /api/chat` with JSON `{"message": "..."}`
returning `{"reply": "..."}`. Plain `curl` works:

```sh
curl -s -X POST -H 'Content-Type: application/json' \
  -d '{"message":"fever"}' http://localhost:8765/api/chat
# {"reply": "agent> see headache"}

curl -s -X POST -H 'Content-Type: application/json' \
  -d '{"message":"/reflect"}' http://localhost:8765/api/chat
# {"reply": "(reflected on 6 concept(s); 4 tentative inference(s):
#   doctor, prescription, medicine, recover)  refl_kg=4"}
```

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
