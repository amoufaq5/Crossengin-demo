# E2: conflicting sources

E2 measures whether CrossEngin's per-source trust (tier weights, or the
meta-observer's learned reliability) gives better-calibrated beliefs than
counting claims equally, and how it compares with majority vote, Dawid–Skene
and TruthFinder. The design, predictions and analysis are fixed in
[PREREG.md](PREREG.md).

| Path | What |
|---|---|
| `PREREG.md` | Pre-registration |
| `e2.py` | Data generator, baselines, calibration-metric port, runner, statistics (stdlib) |
| `e2_driver.nova` | In-process driver: replays a dataset through `pip_ingest_ex` under one arm |

## Run

```sh
python3 -I experiments/e2/e2.py --selftest
python3 -I experiments/e2/e2.py build --nova "$NOVA_ROOT/nova"      # -> bin/e2-driver
python3 -I experiments/e2/e2.py run --driver bin/e2-driver \
    --out experiments/e2/results/run-$(date +%Y%m%d) --jobs 4        # 100 datasets, a few minutes
```

`run` refuses anything other than the pre-registered design (modes M0–M4,
seeds 1–20, 2,000 facts) unless `--partial` is given, and it also refuses
duplicate seeds. If the Python metric port disagrees with the driver's own
`calibration.nova` output on any CrossEngin run, no statistics are written.

`stats --out DIR [--driver BIN]` recomputes the statistics. It refuses in
three cases:
- the run's metric cross-check failed;
- `e2.py`, `e2_driver.nova` or `PREREG.md` changed since the run;
- a `--driver` is given that differs from the run's driver.
