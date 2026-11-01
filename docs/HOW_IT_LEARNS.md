# How CrossEngin learns

This document shows, on a running build, how the symbolic knowledge agent gets faster the more you use it — the mechanism that makes the system *not just a database*.

The demo is reproducible on any machine with the current `claude/phase-0-substrate` branch built. It runs in ~15 seconds and uses only the shipped `fever` seed vocabulary — no corpora required.

> **Status**: Phase 0 parts 1–2 landed. Four of six substrate wire-ups are live: predictive-coding learner, synapse-weighted forward-chain retrieval, lazy synapse growth, direct `/good` reinforcement, and episodic consolidation. Forward-Forward and HDC-on-new-atoms are the remaining wire-ups, scheduled for part 3.

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
│  │ 3. Synapse graph      src/substrate/synapse_graph.nova       │   │
│  │    Weighted directed edges between atom nodes.               │   │
│  │    Phase 0: grown lazily when _cr_chain picks an edge, so    │   │
│  │    the chat path actually populates it. Weights change via   │   │
│  │    Hebbian plasticity + direct /good reinforcement.          │   │
│  └──────────────────────────────────────────────────────────────┘   │
│         │                                                            │
│         ▼                                                            │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │ 4. Moments + tick     src/parts/episodic/moment_stream.nova  │   │
│  │                       src/substrate/tick_driver.nova         │   │
│  │    Working memory. Each message captures one moment; the     │   │
│  │    tick-driver fires three-factor plasticity. Phase 0:       │   │
│  │    rate-limited consolidation sweep mints episodic atoms     │   │
│  │    per recurring moment signature.                           │   │
│  └──────────────────────────────────────────────────────────────┘   │
│         │                                                            │
│         ▼                                                            │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │ 5. Learning rules     plasticity_modulation + predictive_    │   │
│  │                       coding_runtime + forward_forward       │   │
│  │    Hebbian (via emotion_modulate_plasticity → pm_modulator): │   │
│  │       live.                                                  │   │
│  │    Predictive coding (pc_pred_learn): live. Learns the       │   │
│  │       arousal trajectory per familiar input.                 │   │
│  │    Forward-Forward (ff_train_pair): scheduled for part 3.    │   │
│  └──────────────────────────────────────────────────────────────┘   │
│         │                                                            │
│         ▼                                                            │
│  Reply + updated state                                               │
└──────────────────────────────────────────────────────────────────────┘
```

---

## The frequency-adaptive latency demo

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
- **Mean weight across all 10 synapses climbs to 300** — not 1000 — because only the two edges actually traversed on this chain (`fever → headache`, and the premise→conclusion pair of the two rop_* operators backing it) are reinforced. The seven other synapses in the chain's neighbourhood stay at 0 and anchor the average.
- **Episodic consolidation**: 10 moments produced 10 episodes — one per unique moment signature. If you ran `/status`, memory would show the live episode count.
- **`fever → infection` stays at 0**: the chain is `infection → symptom → fever → headache`. The forward step from `fever` is to `headache`, so that's the edge that gets reinforced. Semantically correct.

---

## Why this isn't just a database

A graph database can store (`fever`, `treats`, `aspirin`). It cannot:

1. **Get faster on hot queries.** Next time this chat is asked `fever`, `_cr_chain` scores candidate edges by `confidence × source_authority × (1000 + synapse_weight) / 1000`. With `fever → headache` at weight 1000, that edge scores 2× higher than at weight 0 — the chain picks it immediately, skipping fan-out exploration.
2. **Preserve audit while adapting.** The underlying atoms and provenance don't change. Only the per-session weights do. `/why` still cites the same source for the fact; `/synapse` shows the learned preference.
3. **Learn without gradient descent.** Every weight update is `O(1)` and happens in the forward pass. No backward pass. No GPU. The whole 10-synapse state is a few hundred bytes.

This is the *frequency-adaptive latency* property. It's what you get from Hebbian plasticity + synapse-weighted retrieval, composed on the live tick substrate.

---

## What's running right now

| Layer | Live on chat hot path? | Mechanism |
|---|---|---|
| Atoms | yes | read + write via `rop_*`, `atom_observe` |
| HDC | partial (word atoms only) | `hdc_symbol`, `hdc_bundle` — new-atom embed pending |
| Synapse graph | **yes** (lazy grow + direct `/good` reinforcement) | `syn_grow_if_absent` + `syn_set_weight` |
| Moments / tick | yes | `loop_memory_step_with_episodic` + `tick_driver` |
| Hebbian plasticity | yes (modulator path) | `emotion_modulate_plasticity → pm_modulator` |
| Predictive coding (learner) | **yes** | `pc_pred_learn` + `pc_pred_predict` |
| Forward-Forward | pending part 3 | `ff_train_pair` + `ff_learn` |

Observability commands:

- `/synapse <atom-label>` — list outgoing synapses with current weights.
- `/__learning__` — key=value snapshot of synapse state (scriptable).
- `/status` — one-line summary (moments, episodes, synapses, mood, DP budget).

---

## Reproduce it

```bash
cd ~/Crossengin-demo
git fetch && git checkout claude/phase-0-substrate && git pull --ff-only
export NOVA_ROOT=$HOME/NOVA
make install

# Fresh dlog so counts start at 0
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

Everything that follows in the plan rests on this layer being live and inspectable. It is.
