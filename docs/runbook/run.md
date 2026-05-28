# Run

Three runnable artifacts ship via `make install` into `./bin/`. The end-to-end
walkthrough lives in the top-level [`MANUAL.md`](../../MANUAL.md); this page is
the per-artifact reference.

## bin/crossengin — the unified daemon (the whole agent)

The full ADR-0036 six-loop agent in one process, driven by the ADR-0037
event/idle hybrid scheduler. Pure substrate, NO LLM.

```sh
make install
./bin/crossengin
# or, without installing:
$NOVA_ROOT/nova run examples/crossengin_daemon.nova
```

What it does, per cycle:
- **perception** — the five-stage reader anchors the input to concept atoms.
- **memory** — the moment is captured + recorded episodically.
- **reasoning** — forward-chaining from the percept yields conclusions.
- **emotion** — appraisal of the agent's *own comprehension* → conditioned mood.
- **goals** — drives regenerate; the active goal is arbitrated.
- **action** — output is generated *from a reasoning conclusion* via a reverse
  concept→word lookup, then gated (constitutional veto blocks forbidden text)
  and logged to the tamper-evident decision log.

Conditioned mood drives the substrate tick's plasticity modulator; a
predictive-coding residual drives its error. A run of empty ticks throttles the
scheduler 100Hz → 10Hz idle, which gates imagination and triggers a
checkpoint. At idle the self-learning arbiter drains its trigger queue and
`ask_user_to_teach` ingests new word↔concept bindings — the agent grows its KGs
at runtime. On shutdown the agent reboots by rehydrating in mandatory order
(soul → KGs).

Exit code: `0` on `crossengin: OK`, non-zero with `FAILURE(S)` otherwise.

## bin/crossengin-selfcheck — the substrate kernel spine

Boots the Phase 1 kernel (parts, node pools, signals, gates, tick) and asserts
liveness. Useful for verifying the substrate itself.

```sh
./bin/crossengin-selfcheck                # or: bash scripts/run.sh
```

Tail of expected output:

```
substrate self-check: OK
```

Exits 0 on success; non-zero with `SELFCHECK FAILED: <invariant>` if any
substrate invariant did not hold.

What it exercises:
- `part_registry` / `part_lifecycle` — seven fixed parts + a spawned KG part.
- `node_pool_manager` / `first_nodes` — node pools and stable first-node blocks.
- `synapse_graph` / `resonance_engine` — a feedforward chain and a resonant pair.
- `signal_dispatch` / `gate_router` — typed signals, learned routing, and the
  privileged constitutional broadcast.
- `tick_driver` — the four-phase substrate tick (snapshot, integrate,
  propagate, learn).

## bin/crossengin-spine — the safety + IO + persistence spine

The Phase 8/9/10 spine without the substrate or cognition layers: soul +
constitution, input transduction, governed output through the safety gate
(forbidden utterances vetoed and logged), checkpoint and rehydrate. Useful for
exercising the safety chain alone.

```sh
./bin/crossengin-spine
# ... per-step OK / FAIL lines ...
# companion spine: OK
```

## A word on the seed

`bin/crossengin` boots with the seed in
[`src/seed/first_atoms.nova`](../../src/seed/first_atoms.nova) — the foundational
self-knowledge (self, user, query, response, help, ok) plus a tiny medical
demo chain (fever → infection ⇒ treat) and the two output syntax patterns.
Everything else is learned at runtime from input. To change the seed, edit
`first_atoms.nova` (and the matching `tests/unit/test_first_atoms.nova`); the
daemon picks it up automatically.

## Where things go on disk

CrossEngin's *runtime* state is in-memory only; production durability
(`*.cesnap` substrate snapshots and `*.celog` decision logs) is the documented
NOVA enhancement #9/#10 seam. Built binaries live under `bin/`; build artifacts
are under `/tmp/` per `nova build` invocation.
