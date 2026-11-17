# Experiment flags (E1 ablations)

These environment variables exist for the E1 ablation study (audit §8). **All
are off by default.** With every flag off, the chat's output was byte-identical
to the previous build when B2 landed. That was checked by hand, in text and
JSON mode, over scripted and random sessions; CI does not compare against an
older build. `tests/integration/scenario_exp_flags.sh` checks that the trace
adds only `EXP` lines and that values other than `1` leave a flag off.

A flag is on only when its value is exactly `1`. When any ablation is on, the
chat prints one banner line at startup, for example
`(experiment: ablations on: ff,pc)`. JSON mode suppresses the banner.

| Variable | What it switches off | Where to see it |
|---|---|---|
| `CE_ABL_SUBSTRATE` | Substrate ticks become clock-only. The logical clock still advances, so timestamps, decay and `tick=` stay meaningful, but no part integrates, fires, propagates or learns. | `EXP` `fired` is 0 |
| `CE_ABL_FF` | `/good` and `/bad` no longer train the Forward-Forward layer. | `ff_goodness` in `/__learning__` |
| `CE_ABL_PC` | Predictive coding: the prediction error is held at 0, and the predictor is neither trained nor queried. | `EXP` `pc_error` is 0 |
| `CE_ABL_CACHE` | The moment cache is neither looked up nor filled. | `EXP` `cache_hit` is 0; `mc_entries=0` |
| `CE_ABL_IA` | Adaptive intent prototypes neither override the category nor get reinforced. | no `ia_proto_strength_*` rows |
| `CE_ABL_SYNW` | Router-table weights change no behaviour. The router ignores them when it scores candidate operators, and `/good` no longer compiles weight-gated A→C shortcut operators (the chain compiler). Edges still grow and `/good` still writes the weights. | `compiled_count=0` in `/__compiled__` |
| `CE_ABL_BETA` | `/good` and `/bad` no longer update operator confidence. | `[conf=...]` in reasoning traces |

## CE_HEBB (B3, audit F-03)

`CE_HEBB=1` is not an ablation: it turns **on** a Hebbian step on the
cognitive router's table after every routed reply, cache hit or miss
(`cr_hebb_step`). It applies `syn_learn_one` to the existing router-table
edges of the reply's chain (first premise activation 1000, each conclusion
= premise activation × operator confidence, error 0, the turn's modulator).
It never grows edges. It prints its own startup banner, adds `hebb_steps`
and `hebb_updates` rows to `/__learning__`, and appears as `hebb` at the end
of the `EXP` `flags` field. Off by default; with it off, output is unchanged.

## Trace

`CE_EXP_TRACE=1` prints one line per conversational turn, including turns the
NL grammar answers. Admin commands do not produce a line.

```
EXP {"turn":1,"session":"default","nl":0,"router":1,"cache_hit":1,
     "category":"unknown","drain_steps":1,"fired":24,"modulator":1322,
     "pc_error":-227,"ops":"543,544,546","trace":"unknown: forward-chain ...",
     "flags":""}
```

Fields:

- **`turn`:** 0-based count of traced turns.
- **`nl`:** 1 when the NL grammar answered. No tick runs on such a turn, so `drain_steps` and `fired` are 0 and `modulator` / `pc_error` repeat the current values.
- **`router`:** 1 when the turn went through the cognitive router. When it is 0, the fields `ops`, `trace` and `category` are empty.
- **`modulator` / `pc_error`:** the values passed to the turn's tick. The turn recomputes both after that tick, and the new values drive the next turn's tick.
- **`fired`:** substrate nodes fired by the turn's tick. That tick runs before the turn's own input is injected, so it integrates the previous turn's stimulus; turn 0 always shows 0.
- **`flags`:** the ablations that are on, then `hebb` when `CE_HEBB=1`.

Wall time is not reported; measure it outside the process.

The flags are read once at startup. They are implemented in
`src/exp/exp_flags.nova`, with the clock-only slot in
`src/substrate/tick_driver.nova` (`td_set_clock_only`).
