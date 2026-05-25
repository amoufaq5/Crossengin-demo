# Data flow: a stimulus through one substrate tick

This traces how activation moves through the Phase 1 substrate. It reflects the
implemented code (`src/substrate/`), not a future aspiration.

## Entry: a percept becomes a routed signal

1. An external stimulus is expressed as a signal, e.g.
   `sig_new(XSIG_SENSORY, src, dst, strength, trace, meta)` (ADR-0008). Its
   priority is seeded from its type.
2. A gate routes it (`gate_route`). For `XSIG_SENSORY` the seeded route resolves
   to the perception part; for `XSIG_CONST` the gate broadcasts to **every**
   part unconditionally (ADR-0009/0045).
3. The signal is delivered to the destination part's first-node block via
   `part_inject` → `fn_inject` (broadcast across `[0, count)`, ADR-0010). Each
   first node accumulates the strength into its inbox.

## The tick (`tick_driver._td_exec`, ADR-0006)

For each active part, one tick runs four phases in order:

```
   snapshot ──▶ integrate ──▶ propagate ──▶ learn
```

1. **snapshot** — record every live node's activation at tick start (a list
   indexed by node id). Learning later reads this, so it sees a consistent
   pre-tick view rather than post-refractory zeros.
2. **integrate** — run the uniform kernel on each live node
   (`npm_node_integrate`): leaky-integrate the inbox plus bias into activation,
   decay the novelty trace, and if activation crosses threshold, fire (record
   the tick, bump the fire and novelty counters) and reset to refractory 0. The
   inbox is drained. Nodes that fired are collected.
3. **propagate** — each fired node emits a unit spike down its outgoing synapses
   (`syn_out` → `syn_transmit`); the weighted contribution
   (`fp_mul(weight, spike)`) lands in each destination's inbox for the **next**
   tick. Negative weights inhibit (ADR-0008 sign convention).
4. **learn** — the fused Hebbian + error-driven plasticity pass
   (`syn_plasticity_step`) updates every live synapse from the snapshot, then
   decays eligibility (ADR-0007).

## Across ticks

Because propagation fills inboxes for the *next* tick, activation flows one hop
per tick: a stimulated first node fires at tick *t*, and a node downstream of it
fires at *t+1*. The self-check demonstrates exactly this (`first node 0` fires
at tick 1, the `interior` node at tick 2).

## Resonance (optional, per tick)

`resonance_engine.res_step` can run over the snapshot to potentiate reciprocally
connected, co-active pairs in **both** directions, deepening stable assemblies
(the `<=>` dynamic). This is the substrate basis for bound percepts (XSIG_BIND).

## Not yet in the path

Predictive-coding error signals (the `error` term to `syn_plasticity_step` is
currently 0), emotional modulation (the plasticity `modulator` is currently the
neutral 1.0), inter-part signal emission through gates from fired nodes, and the
six concurrent loops are later phases (ADR-0024, 0035, 0036, 0037).
