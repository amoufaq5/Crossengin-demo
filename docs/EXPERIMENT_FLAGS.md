# Experiment flags (E1 ablations)

These environment variables exist for the E1 ablation study (audit §8). **All
are off by default.** With every flag off, the chat's output is byte-identical
to a build without them (checked by `tests/integration/scenario_exp_flags.sh`).

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
| `CE_ABL_SYNW` | The router ignores router-table weights when it scores candidate operators. Edges still grow and `/good` still writes them. | listed in `EXP` `flags` (behaviour is unit-tested) |
| `CE_ABL_BETA` | `/good` and `/bad` no longer update operator confidence. | `[conf=...]` in reasoning traces |

## Trace

`CE_EXP_TRACE=1` prints one line per conversational turn. Admin commands do
not produce a line.

```
EXP {"turn":1,"session":"default","router":1,"cache_hit":1,"category":"unknown",
     "drain_steps":1,"fired":24,"modulator":1322,"pc_error":52,
     "ops":"543,544,546","trace":"unknown: forward-chain ...","flags":""}
```

Fields:

- **`router`:** 1 when the turn went through the cognitive router. When it is 0, the fields `ops`, `trace` and `category` are empty.
- **`fired`:** substrate nodes fired during the turn.
- **`modulator` / `pc_error`:** the values the turn's ticks used.
- **`flags`:** the ablations that are on.

Wall time is not reported; measure it outside the process.

The flags are read once at startup. They are implemented in
`src/exp/exp_flags.nova`, with the clock-only slot in
`src/substrate/tick_driver.nova` (`td_set_clock_only`).
