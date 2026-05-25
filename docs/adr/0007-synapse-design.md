# ADR-0007: Synapse design (Hebbian + error-driven plasticity, growth, pruning)

## Status

Proposed

## Date

2026-05-25

## Context
Nodes (ADR-0006) are uniform; all CrossEngin specialization therefore lives in the synapses that connect them. The synapse is the substrate's only long-term learnable parameter, so its design determines whether CrossEngin can satisfy its headline capability — continuous learning — at all. We must decide the synapse's representation, its weight update rule(s), and its lifecycle (growth and pruning), and we must do so within hard limits: 1M nodes/part, ~1000 synapses/node means ~1 billion synapse slots per part, ~9 billion across nine parts in v1, all on a single desktop (ADR-0046).

NOVA's `core/channel.nova` gives carriers with layout `[TAG, name, source, destinations, chan_type, filter_min_salience, message_count]` and four channel types (`CHAN_DIRECT`, `CHAN_BROADCAST`, `CHAN_FILTERED`, `CHAN_WEIGHTED`). A synapse is a weighted point-to-point carrier — conceptually `CHAN_WEIGHTED` with exactly one destination plus a learned scalar. But `core/channel.nova` was not built for billions of instances with per-tick weight math, so the representation must change even though the conceptual mapping holds.

The constraints force two non-obvious choices. First, we cannot store synapses as individual channel objects — 9B heap records would exhaust desktop RAM and destroy cache locality in the 100Hz propagation loop. Second, plasticity must be cheap: a weight update that runs over billions of active synapses each tick must be a vectorized array kernel, not a per-object method call. The two-founder team needs one plasticity implementation that serves Hebbian co-firing, error-driven correction (for predictive coding, ADR-0024), and emotion-modulated learning (ADR-0035) without three separate code paths.

## Decision
A synapse is a row in a sparse, CSR-like adjacency structure per part, not an object. For each part we store parallel typed arrays: `pre[]` (source node index), `post[]` (destination node index), `weight[]` (float, bounded), `eligibility[]` (recent co-activation trace), `last_active_tick[]`, and `sig_type_mask[]` (which of the 18 signal types from ADR-0008 this synapse carries). Indexing is CSR by source node so a node's ~1000 outgoing synapses are contiguous. Cross-part synapses (node-to-other-part, per ADR-0002) live in a separate inter-part block keyed by destination part + first-node index (ADR-0010).

Weight learning is a single fused rule with two additive terms. The Hebbian term strengthens co-firing: `dw_hebb = eta_h * pre_act * post_act` (with the eligibility trace decaying between co-fires). The error-driven term corrects prediction mismatch: `dw_err = eta_e * pre_act * error_signal`, where `error_signal` is the ADR-0008 error-type signal arriving at the post-node during predictive coding (ADR-0024). Both terms are computed in one pass over the active-synapse arrays. A global modulator scales `eta_h`/`eta_e` from emotional arousal/valence (ADR-0035) — emotion conditions plasticity rate, not a separate rule. Weights are clamped to `[w_min, w_max]` (e.g. `[-1.0, +1.0]`, sign carrying excitatory vs inhibitory intent per ADR-0008) to prevent runaway potentiation.

Lifecycle: synapses are SPARSE at startup (well below ~1000/node) and GROW. When two unconnected nodes co-activate above a growth threshold for N ticks, a new synapse row is appended (O(1) amortized). PRUNING runs as a periodic GC during idle (enhancement #13): synapses whose `|weight|` and `eligibility` stay below a death threshold for a decay window are removed and their slots reclaimed, capping each node near ~1000 live synapses.

## Options Considered
**Per-synapse channel objects (literal `CHAN_WEIGHTED`).** Most faithful to `core/channel.nova`; each synapse a real channel with its own weight field. Rejected on scale: 9B objects is infeasible in desktop RAM, pointer-chasing wrecks the 100Hz loop, and weight updates become billions of virtual calls. The conceptual mapping is preserved in spirit but the storage must be arrays.

**Dense weight matrices per part.** A 1M×1M matrix per part trivially supports BLAS-style updates (enhancement #4) and is simple to reason about. Rejected: a dense 1M² float matrix is ~4TB per part — utterly impossible. Even at lower precision it is orders of magnitude over budget. Sparsity is not an optimization here; it is mandatory, and it is also biologically and cognitively correct (real connectivity is sparse).

**Hebbian-only plasticity (no error term).** Simpler: one rule, no dependence on error signals. Rejected because it cannot support predictive coding (ADR-0024), which is the mechanism behind self-learning triggers via prediction error (ADR-0026) and a key capability test (ADR-0049). Pure Hebbian learning also drifts and lacks a corrective signal, tending toward degenerate all-strong or all-weak regimes.

**Chosen:** CSR sparse arrays + fused Hebbian/error rule + grow/prune lifecycle. It is the only option that fits ~9B synapses on a desktop, supports both learning signals in one kernel, and gives the continuous-learning and predictive-coding capabilities downstream ADRs require.

## Consequences
- **Positive:** Memory fits the desktop budget (sparse rows, typed arrays, no per-object overhead). One vectorized kernel serves Hebbian, error-driven, and emotion-modulated learning. Growth lets structure expand with experience (continuous learning); pruning bounds memory and removes noise. Sign-as-weight unifies excitatory/inhibitory synapses with the ADR-0008 taxonomy.
- **Negative:** CSR with growth/pruning is complex — appends and compaction must stay crash-safe and not fragment (work for enhancement #2). Debugging a learned weight matrix is hard; we need a synapse-inspector in the harness. Bounded weights and dual learning rates introduce hyperparameters (`eta_h`, `eta_e`, growth/death thresholds, decay window) that must be tuned, a real cost for a 2-person team.
- **Future work:** Directly enables ADR-0024 (predictive coding consumes the error term), ADR-0025 (atom birth/death parallels synapse growth/pruning), ADR-0035 (emotion modulates `eta`). Synapse persistence is part of the substrate snapshot (ADR-0048). Inter-part synapse blocks feed first nodes (ADR-0010) and gate routing (ADR-0009).

## Implementation Notes
New module `core/synapse.nova` exposing `synapse_new(part, pre, post, sig_mask)` (appends a CSR row), `synapse_weight(idx)`, `synapse_set_weight`, and batch entry points `synapse_plasticity_step(part, tick)` (fused Hebbian+error pass) and `synapse_prune(part)` (idle GC). Reuse `core/channel.nova` semantics conceptually (a synapse is the `CHAN_WEIGHTED`, single-destination case) and `core/similarity.nova` for weighting inter-part/cross-KG connections (ADR-0017). Store the CSR arrays in part-owned arenas alongside the node arrays from ADR-0006.

`DEPENDS ON: NOVA enhancement #2 — sparse synapse adjacency (CSR-like) with O(1) weight update, growth, and pruning.` `DEPENDS ON: NOVA enhancement #12 — Hebbian + error-driven plasticity kernels over synapse weight arrays.` Batched propagation along synapses uses `DEPENDS ON: NOVA enhancement #4 — SIMD/GPU batched signal propagation`. Idle pruning hook: `DEPENDS ON: NOVA enhancement #13 — idle-detection + background scheduling hooks`.

Testing: fixture `fixture_two_node_cofire` verifies a synapse strengthens under repeated co-firing and saturates at `w_max`; `fixture_predict_error` injects an ADR-0008 error signal and asserts the error term moves the weight toward reduced future error; `fixture_prune_cycle` runs the decay window and asserts weak synapses are reclaimed and a node stays near its ~1000-synapse cap. Depends on ADR-0006 (node kernel, activation) and ADR-0008 (signal types carried). Validated end-to-end by ADR-0024 and the continuous-learning capability test in ADR-0049.
