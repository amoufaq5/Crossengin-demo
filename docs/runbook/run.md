# Run

## v0.1: the substrate self-check

There is **no end-user cognitive agent yet** (see NEXT_SESSION.md). The runnable
artifact at this stage is the substrate self-check, which boots the implemented
kernel, wires a small slice of it, drives it for several ticks, and prints a
liveness report.

```sh
bash scripts/run.sh               # or: NOVA_ROOT=/path/to/NOVA bash scripts/run.sh
```

Equivalently, build and run the binary:

```sh
make install
./bin/crossengin-selfcheck
```

Expected output (abridged):

```
=== CrossEngin substrate self-check (v0.1) ===
parts spawned        : 8 (8 active)
  dynamic KG: kg-medicine
perception nodes     : 9   synapses: 3
SENSORY routes to    : 1 part(s); perception in set = 1
CONST broadcasts to  : 8 part(s) (all)
ticks run            : 8
total node fires     : 23
first node 0 fired   : tick 1
interior fired       : tick 2  (propagation across ticks)
resonant pair {1,2}  : strength 600
substrate self-check: OK
```

The self-check exits 0 on success and non-zero (printing `SELFCHECK FAILED`) if
any substrate invariant did not hold.

## What it exercises

- `part_registry` / `part_lifecycle` — the seven fixed parts plus a spawned
  `kg-medicine` domain part.
- `node_pool_manager` / `first_nodes` — node pools and the stable first-node
  block per part.
- `synapse_graph` / `resonance_engine` — a feedforward chain and a resonant
  pair.
- `signal_dispatch` / `gate_router` — typed signals, learned routing, and the
  privileged constitutional broadcast.
- `tick_driver` — the four-phase substrate tick (snapshot, integrate,
  propagate, learn) and cross-tick signal propagation.

## Not yet runnable

The conversational daemon, CLI/socket interface, persistence, reader, KGs, and
learning fabric are not implemented yet. See NEXT_SESSION.md for the roadmap.
