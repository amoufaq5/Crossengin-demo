# E1: ablation study harness

E1 measures which of the chat's learning mechanisms change what it says, and
whether each one makes the replies more or less correct on a fixed replay.
The design, hypotheses and analysis are fixed in [PREREG.md](PREREG.md).

## Files

| Path | What |
|---|---|
| `PREREG.md` | Pre-registration (hypotheses, outcome, statistics) |
| `arms.tsv` | The 11 arms: name, flags, comparator |
| `inputs/replay_v1.tsv` | 262 replay lines: 200 scored items in six blocks |
| `inputs/gold_v1.tsv` | One gold spec per item |
| `inputs/perms_v1.tsv` | Five episode permutations (seeds 1–5) |
| `inputs/caps_e1.conf` | Denies capabilities that would prompt or reach the network |
| `e1.py` | Lint, permutations, reference check, runner, scoring, statistics (stdlib) |
| `run_e1.sh` | Builds nothing; runs `e1.py run` on `bin/crossengin-chat` |

## Run

```sh
make install                                   # builds bin/crossengin-chat
python3 -I experiments/e1/e1.py --selftest
python3 -I experiments/e1/e1.py lint
bash experiments/e1/run_e1.sh results-$(date +%Y%m%d)   # all arms x 5 perms, ~3 min at -j4
```

`run_e1.sh TAG` writes to `experiments/e1/results/TAG/`. The run stops before
scoring if the full arm is not byte-identical across two runs of the same
permutation (the determinism gate). `e1.py refcheck --chat bin/crossengin-chat
--show` runs each episode alone in the full arm and prints every item's reply
against its gold.
