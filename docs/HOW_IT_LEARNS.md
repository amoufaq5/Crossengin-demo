# How CrossEngin learns

> **Correction (2026-11-16).** This document overstated what it shows. A
> due-diligence audit (audit F-03) found, and the code confirms:
> - The tick's Hebbian weight change is always 0 in the live chat: the
>   activity snapshot is indexed by node slot while synapses are keyed by
>   atom id, so they never line up. The three-factor rule is off.
> - The Forward-Forward goodness and predictive-coding outputs are computed
>   but nothing downstream reads them.
> - After 10 x `/good` the reply is byte-identical to the first one.
> - The four numbers the CI smoke test pins (`mc_hits=9`,
>   `ff_goodness=486000`, `synapse_mean_weight=300`,
>   `ia_proto_strength_unknown=10`) are a reply cache's hit count and
>   counters that grow with each query or `/good`. They are a regression pin
>   for this code path, **not evidence that the system learns**.
>
> - **Update (B1, audit C12):** the router's chain edges used to live in the
>   reasoning part's *pool* graph, where atom ids below the pool size aliased
>   real node slots. They now live in a separate per-session **router table**
>   (atom-id keyed) that no tick runs over. Its weights change only through
>   `/good` / `/bad` (and snapshot `/load`). This removes the aliasing; it
>   does not make anything learn from the tick.
>
> "Gets faster the more you use it" is true only in the sense of memoising
> replies. Read the rest of this page as a description of the wiring, not as
> a demonstration of learning.

> **E1 results (2026-11-19, pre-registered ablation study).** See
> `experiments/e1/results/run-20261119/REPORT.md`. On a scored 200-item
> replay:
> - Turning off the moment cache fixes 23 items and breaks none. It answers
>   one input with another input's reply, and keeps a reply after `/bad`.
> - Substrate ticks, predictive coding and Forward-Forward change no reply at
>   all.
> - Operator confidence (BETA) is what makes feedback visible: with the cache
>   off, removing it breaks 17 items and fixes 2.
> - Intent-adaptive prototypes break 3 items.
> - Router-table weights and the opt-in `CE_HEBB` step have no significant
>   effect, so `CE_HEBB` stays off by default.

> **B3 update (audit F-03 fix, opt-in).** `CE_HEBB=1` turns on a Hebbian
> step on the cognitive router's own table (`cr_hebb_step` in
> `src/agent/cognitive_router.nova`). After every routed reply, cache hit or
> miss, it applies the ADR-0007 rule (`syn_learn_one`, error term 0) to the
> router-table edges of the chain behind the final reply, keyed by atom id.
> Every leg was traversed, so each premise is fully active (1000) and each
> conclusion is active in proportion to the operator's confidence. The step
> is scaled by the plasticity modulator recomputed during the turn, and it
> never grows edges. With it on, ten `fever` turns and no `/good` raise each
> leg of infection→symptom→fever→headache from 0 to 130 (mean weight 0 → 39;
> CI step "CE_HEBB smoke"). Because `/good` compiles a shortcut once both legs
> pass 500, Hebbian weight also brings that compile forward. It is **off by
> default** and stays off until E1 shows whether it helps; with it off,
> nothing in this document changes.

This document walks through, on a running build, the wiring that runs when the same question is asked repeatedly: reply memoisation, `/good` reinforcement of chain edges, and the substrate counters that move with them.

The demo is reproducible on any machine with the current `claude/phase-0-substrate` branch built. It runs in ~15 seconds and uses only the shipped `fever` seed vocabulary — no corpora required.

> **Status**: the wire-ups below are called on the chat path: predictive-coding learner, synapse-weighted forward-chain retrieval, lazy synapse growth, direct `/good` reinforcement, episodic consolidation, HDC embed mode, Forward-Forward goodness on moments, the chain compiler, `kg_router`, `moment_cache` and `intent_adaptive`. "Called" is not "effective": the tick Hebbian update computes Δw = 0 on the live path (slot/atom-id mismatch, audit F-03; the opt-in `CE_HEBB=1` router-table step is the fix under test), and the Forward-Forward and predictive-coding outputs are not read by anything that changes a reply. The visible speed-up is the moment cache returning memoised replies.

---

## The five substrate layers

Each message passes through five layers. Three of them *write state* that persists and shapes future answers.

```
┌──────────────────────────────────────────────────────────────────────┐
│  User message                                                        │
│         │                                                            │
│         ▼                                                            │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │ 1. Atoms (KG)         src/kg/atom_store.nova                 │   │
│  │    Typed facts, each with provenance + Bayesian belief.      │   │
│  │    `fever`, `infection`, `headache` are atoms.               │   │
│  │    rop_* operators are atoms too (rules).                    │   │
│  └──────────────────────────────────────────────────────────────┘   │
│         │                                                            │
│         ▼                                                            │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │ 2. HDC hypervectors   src/kg/hdc_embed.nova                  │   │
│  │    10 000-dim bipolar vectors. Semantic similarity by        │   │
│  │    cosine; bind/bundle compose roles into phrases.           │   │
│  │    Currently wired for word atoms; new-atom embed is Phase 0 │   │
│  │    part 3 (deferred).                                        │   │
│  └──────────────────────────────────────────────────────────────┘   │
│         │                                                            │
│         ▼                                                            │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │ 3. Router table       src/substrate/synapse_graph.nova       │   │
│  │    Weighted directed edges between ATOM ids, one table per   │   │
│  │    session, separate from the substrate's pool graphs (B1).  │   │
│  │    Grown lazily (weight 0) when _cr_chain picks an edge.     │   │
│  │    No tick runs over it: weights change only by direct       │   │
│  │    /good, /bad reinforcement (+/-100 milli per leg).         │   │
│  └──────────────────────────────────────────────────────────────┘   │
│         │                                                            │
│         ▼                                                            │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │ 4. Moments + tick     src/parts/episodic/moment_stream.nova  │   │
│  │                       src/substrate/tick_driver.nova         │   │
│  │    Working memory. Each message captures one moment; the     │   │
│  │    three-factor plasticity rule is off. Phase 0:             │   │
│  │    rate-limited consolidation sweep mints episodic atoms     │   │
│  │    per recurring moment signature.                           │   │
│  └──────────────────────────────────────────────────────────────┘   │
│         │                                                            │
│         ▼                                                            │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │ 5. Learning rules     plasticity_modulation + predictive_    │   │
│  │                       coding_runtime + forward_forward       │   │
│  │    Hebbian (via emotion_modulate_plasticity → pm_modulator): │   │
│  │       called each tick; dw = 0 on the live path (F-03);      │   │
│  │       opt-in CE_HEBB=1 router-table step (B3) learns.        │   │
│  │    Predictive coding (pc_pred_learn): called; its output is  │   │
│  │       not read by anything that changes a reply.             │   │
│  │    Forward-Forward (ff_train_pair): called on /good, /bad;   │   │
│  │       `ff_goodness` in /__learning__ moves, nothing reads it.│   │
│  └──────────────────────────────────────────────────────────────┘   │
│         │                                                            │
│         ▼                                                            │
│  Reply + updated state                                               │
└──────────────────────────────────────────────────────────────────────┘
```

---

## The repeated-question demo (counters, not a latency measurement)

**Setup**: 10 identical queries of `fever` with `/good` after each. We watch the synapse weight on `fever → headache` and the mean weight across all 10 live synapses.

```
$ ./bin/crossengin-chat
=== CrossEngin chat ===

> /__learning__                    # baseline — no synapses yet
synapse_live=0
synapse_total=0
synapse_mean_weight=0
dlog_entries=0
tick=0

> /synapse fever                   # fever has no outgoing synapse yet
(no atom with label 'fever')

> fever                            # first reasoning chain
agent> infection leads to headache (infection->symptom->fever->headache).

> /good                            # reinforce the chain
thanks -- reinforced 3 inference(s).

> /synapse fever                   # synapses now exist
fever (node 534): 2 outgoing synapse(s)
  -> infection (node 535) weight=0
  -> headache  (node 463) weight=100

> /__learning__
synapse_live=10
synapse_mean_weight=30
tick=1
```

Repeat `fever` + `/good` nine more times. Weight climb:

| Turn | fever → headache | mean weight | ticks | moments |
|-----:|-----------------:|------------:|------:|--------:|
|   1  |             100  |         30  |    1  |      1  |
|   2  |             200  |         60  |    2  |      2  |
|   5  |             500  |        150  |    5  |      5  |
|  10  |            1000  |        300  |   10  |     10  |

Observations:

- **Weight climbs linearly** with each `/good` (+100 milli per reinforcement) until it saturates at `W_MAX=1000`.
- **Mean weight across all 10 synapses climbs to 300** — not 1000 — because only the chain's three legs (`infection → symptom`, `symptom → fever`, `fever → headache`) are reinforced, each to `W_MAX=1000`. The seven other edges grown while searching stay at 0: (3 × 1000 + 7 × 0) / 10 = 300.
- **Episodic consolidation**: 10 moments produced 10 episodes — one per unique moment signature. If you ran `/status`, memory would show the live episode count.
- **`fever → infection` stays at 0**: the chain is `infection → symptom → fever → headache`. The forward step from `fever` is to `headache`, so that's the edge that gets reinforced. Semantically correct.

---

## Why this isn't just a database

A graph database can store (`fever`, `treats`, `aspirin`). It cannot:

1. **Prefer reinforced edges.** Next time this chat is asked `fever`, `_cr_chain` scores candidate edges by `confidence × source_authority × (1000 + synapse_weight) / 1000`. With `fever → headache` at weight 1000 (set directly by `/good`), that edge scores 2× higher than at weight 0. Repeat questions are answered faster mainly because the moment cache returns the memoised reply.
2. **Preserve audit while adapting.** The underlying atoms and provenance don't change. Only the per-session weights do. `/why` still cites the same source for the fact; `/synapse` shows the learned preference.
3. **Learn without gradient descent.** Every weight update is `O(1)` and happens in the forward pass. No backward pass. No GPU. The whole 10-synapse state is a few hundred bytes.

What this amounts to today is `/good` reinforcement of chain edges plus reply memoisation. The tick Hebbian rule that was meant to provide frequency-adaptive weights computes no change on the live path (audit F-03). The opt-in `CE_HEBB=1` router-table step (B3) is the candidate fix; E1 tests whether it helps.

---

## What's running right now

| Layer | Live on chat hot path? | Mechanism |
|---|---|---|
| Atoms | yes | read + write via `rop_*`, `atom_observe` |
| HDC | **yes** (embed mode set to HDC at session init) | `atom_set_embed_mode(ATOM_EMBED_MODE_HDC)` |
| Synapse graph | **yes** (lazy grow + direct `/good` reinforcement) | `syn_grow_if_absent` + `syn_set_weight` |
| Moments / tick | yes | `loop_memory_step_with_episodic` + `tick_driver` |
| Hebbian plasticity | called; dw = 0 on the live path (F-03) | `emotion_modulate_plasticity → pm_modulator` |
| Router-table Hebbian step (B3) | opt-in, `CE_HEBB=1`; off by default | `cr_hebb_step` → `syn_learn_one` |
| Predictive coding (learner) | called; output unused by replies | `pc_pred_learn` + `pc_pred_predict` |
| Forward-Forward | called; `ff_goodness` unused by replies | `ff_layer_new` + `ff_train_pair` + `ff_goodness` |
| Chain compiler | **yes** (pt3) | `chain_compile_from_ops_csv` on `/good` |

Observability commands:

- `/synapse <atom-label>` — list outgoing synapses with current weights.
- `/__learning__` — key=value snapshot of synapse + FF state (scriptable).
- `/__compiled__` — list derived operator atoms the chain compiler has minted.
- `/status` — one-line summary (moments, episodes, synapses, mood, DP budget).

---

## Chain compilation (Phase 0 pt3)

The chain compiler watches `/good` reinforcement. When a two-hop segment `A → B → C` of the just-rewarded chain has both legs' synapse weights (set by `/good`) at or above `CHAIN_COMPILE_THRESHOLD` (default 500 milli = half of `W_MAX`), the compiler mints a direct derived operator atom `A → C` labeled `cc:A->C [via B]`. The original chain stays in the KG, so `/why` still traces to the full path.

```
> /__compiled__                    # before any /good
compiled_count=0
compile_threshold=500

> fever
agent> infection leads to headache (infection->symptom->fever->headache).
> /good
...  (repeat four more times — each /good adds 100 milli to every leg)
> /__compiled__
compiled_count=2
compile_threshold=500
  cc:infection->fever [via symptom] (infection -> fever)
  cc:symptom->headache [via fever] (symptom -> headache)
```

Threshold is first cleared on the 5th `/good` (100 × 5 = 500 milli per leg). Because the compiled operator plugs into the same scoring code as any seeded one, the next `fever` query can short-circuit the two-hop traversal through the derived rule.


---

## Reproduce it

```bash
cd ~/Crossengin-demo
git fetch && git checkout claude/phase-0-substrate && git pull --ff-only
export NOVA_ROOT=$HOME/NOVA
make install

# Fresh dlog so counts start at 0 (pin the runtime dir to /tmp for the demo)
export CE_RUN_DIR=/tmp
rm -f /tmp/crossengin.dlog

# 10-query demo (feel free to extend to 20)
{
  echo "/__learning__"
  for i in $(seq 1 10); do echo "fever"; echo "/good"; done
  echo "/synapse fever"
  echo "/__learning__"
  echo "/status"
  echo "/quit"
} | ./bin/crossengin-chat
```

You should see the `fever → headache` weight climb from 0 to 1000 and the moment count climb to 10.

---

## What this unlocks downstream

- **Phase 1 (safety / tamper defense)**: can now enforce capability tiers on retrieval, because retrieval is observable + weighted.
- **Phase 2 (Ollama fluency layer)**: the composer wraps a *grounded* answer whose atoms and synapses can be inspected before and after. The LLM becomes a styler, not a knowledge source.
- **Phase 3 (internet learn + free prompting)**: ingested atoms immediately join the synapse-weighted retrieval, so freshly-fetched facts are reinforcable the same way seeded ones are.
- **Phase 4 (bulk encyclopedic seed)**: synapse graph scales with KG; the per-tenant working set stays hot without reloading corpora.
- **Phase 5 (agent provider platform)**: a baked agent ships its synapse graph alongside its atoms. The receiving customer gets a pre-warmed hot-path layout; their own `/good` feedback then specialises further to their domain.

Everything that follows in the plan rests on this layer. It is inspectable today; whether it learns anything beyond `/good` reinforcement and memoisation has not been measured. An ablation experiment for that (E1, proposed by the 2026-11 audit) is planned but not yet in this repo.
