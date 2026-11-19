# E2 results: does per-source trust give better-calibrated beliefs?

This is the run `run-20261119` of the pre-registered study
([../../PREREG.md](../../PREREG.md)).

| | |
|---|---|
| Code | git `ed45bdb` (clean). No change to `src/` or `experiments/e2/` since registration (B6, `9ca81cd`). |
| Driver SHA-256 | `88c239bbcc4ee93a…`, built from `experiments/e2/e2_driver.nova`. Input hashes are in `manifest.json`. |
| Design | The full registered design: modes M0–M4 × seeds 1–20, 2,000 facts each, 600 scored runs. Not partial. |
| Metric cross-check | 0 failures. The Python port equals `calibration.nova` on all 300 CrossEngin runs. |

**Deviation: packaging only.** The per-dataset folder `data/` (datasets,
beliefs per arm, mo weights per batch) is committed as one deterministic
archive, `data.tar.xz` (SHA-256 `fbdbe7aa…f7ecb0ac9e3`), because it is 31 MB
uncompressed. `e2.py stats` reads only `scores.tsv` and `manifest.json`, and
reproduces `stats.tsv` exactly. The datasets can also be regenerated with
`e2.py gen`.

## Summary

- **CrossEngin's trust weighting does not give better-calibrated beliefs.**
  - The fixed tiers (graded) are worse than counting every claim equally
    (flat) in every mode.
  - The learned weights (mo) beat flat only when one source lies
    systematically (M2).
- **One-coin Dawid–Skene is far better calibrated when its independence
  assumption holds.** Its Brier score is 56 to 156 points lower than mo's in M0,
  M2 and M3. It is much worse when sources copy each other (M1) or collude (M4).
  CrossEngin's arms are not.
- **Majority vote is better calibrated than every CrossEngin arm, except mo
  in M2.**
- **Why the CrossEngin arms are under-confident:** every arm is limited by the
  belief model's neutral declaration prior. That prior is worth five
  pseudo-observations, against about three claims per fact. Any weight below
  1000 makes beliefs *less* sharp, so tier weighting raises accuracy but
  worsens Brier.

## Primary analysis

`stats.tsv` holds the primary analysis.
- d = Brier(arm) − Brier(comparator) per seed, then the mean over 20 seeds.
  Negative means the arm is better.
- 95% percentile CI from a paired bootstrap over seeds with 10,000 resamples;
  Holm-adjusted over 25 tests.
- A `p_boot` of 0 means every resample fell on one side of 0, so p < 10⁻⁴.

| Mode | graded − flat | mo − flat | mo − dawid_skene | mo − majority | mo − truthfinder |
|---|---|---|---|---|---|
| M0 independent | **+8.6** [8.2, 9.0] | **+1.6** [1.4, 1.8] | **+79.1** [77.8, 80.4] | **+28.0** [27.5, 28.5] | **−4.9** [−5.3, −4.5] |
| M1 copying | **+4.3** [3.7, 4.9] | **+6.1** [5.7, 6.5] | **−82.2** [−87.6, −76.7] | **+26.7** [26.0, 27.4] | +0.3 [−0.2, 0.7] (n.s.) |
| M2 liar | **+19.0** [18.5, 19.4] | **−19.1** [−19.6, −18.6] | **+156.0** [155.0, 157.0] | **−15.8** [−16.3, −15.3] | **−13.3** [−13.8, −12.8] |
| M3 sparse experts | **+12.9** [12.3, 13.5] | **+3.2** [2.6, 3.8] | **+56.1** [54.2, 58.0] | **+19.5** [18.7, 20.4] | **−1.5** [−2.2, −0.8] |
| M4 collusion | **+1.8** [1.3, 2.4] | **+5.4** [5.0, 5.8] | **−103.4** [−107.8, −98.5] | **+12.7** [11.7, 13.7] | **−2.5** [−2.9, −2.1] |

Bold = significant after Holm. 24 of 25 tests are significant; the exception
is M1 mo vs truthfinder (Holm p = 0.28).

## Means per mode and arm

`summary.tsv` holds these means. All values are in milli.

| Mode | Metric | flat | graded | mo | majority | dawid_skene | truthfinder |
|---|---|---|---|---|---|---|---|
| M0 | Brier | 177.5 | 186.1 | 179.1 | 151.1 | **100.0** | 183.9 |
| M0 | accuracy | 809 | 852 | 828 | 809 | **856** | 841 |
| M1 | Brier | 183.1 | 187.3 | 189.2 | **162.5** | 271.3 | 188.9 |
| M1 | accuracy | 765 | **841** | 757 | 765 | 687 | 753 |
| M2 | Brier | 223.3 | 242.3 | 204.3 | 220.1 | **48.4** | 217.6 |
| M2 | accuracy | 651 | 565 | 733 | 651 | **930** | 739 |
| M3 | Brier | 194.9 | 207.8 | 198.1 | 178.6 | **141.9** | 199.6 |
| M3 | accuracy | 745 | 788 | 756 | 745 | **791** | 775 |
| M4 | Brier | 217.6 | 219.3 | 222.9 | **210.2** | 326.3 | 225.3 |
| M4 | accuracy | 663 | **691** | 661 | 663 | 649 | 671 |

M4 accuracy on the 20% of target facts is near zero for every method:

| flat | graded | mo | majority | dawid_skene | truthfinder |
|---|---|---|---|---|---|
| 75 | 48 | 25 | 75 | 0 | 29 |

On those facts three colluders outvote about one honest claim.

## Predictions

### H1: tier weighting does not help. Confirmed, and stronger than predicted.

Graded is significantly worse than flat in all five modes, not only in M2
(where it was predicted to be worse). It is most often the *most accurate*
CrossEngin arm, but its down-weighting leaves beliefs closer to 500, so its
Brier score is worse.

### H2: the meta-observer helps only against a liar. Confirmed.

- In M2, mo is significantly better than flat (−19.1): it drives the liar's
  weight to 0.
- It is not better in M0, M1 or M3. It is in fact slightly but significantly
  worse there, because relative weights below 1000 also shrink the honest
  evidence.

### H3: Dawid–Skene beats the meta-observer except under collusion. Partly confirmed.

| Mode | Prediction | Result |
|---|---|---|
| M0, M2, M3 | mo significantly worse | confirmed |
| M4 | mo significantly better (restated after the M4 development run) | confirmed |
| M1 | mo significantly worse | **refuted**: mo is significantly better (−82.2) |

M1 refutes the prediction because one-coin Dawid–Skene assumes sources err
independently. The two copiers echo the least reliable source, and
Dawid–Skene rates that block as highly reliable. It becomes confidently wrong
(Brier 271, ECE 216).

### H4 and H5: majority and TruthFinder. No direction was predicted.

- Majority beats mo in M0, M1, M3 and M4, and loses to it in M2.
- mo beats TruthFinder in M0, M2, M3 and M4 by small margins. In M1 there is
  no difference.

## What this means

The pre-registration named this implication in case H3 held. H3 held in
four of five modes. CrossEngin's source-trust machinery is not a calibrated
truth-discovery method, and tuning the meta-observer would not change that:
the limit is the belief model.

1. **The declaration prior.** A neutral declaration is worth five
   pseudo-observations, which swamps the roughly three claims a fact
   receives. Declaring at Beta(1,1), as `kg_add_atom` does, would remove most
   of the under-confidence.
2. **The form of the source weight.** Weights in [0, 1] can only dilute
   evidence. A likelihood-based weight, such as log-odds of the estimated
   reliability as in Dawid–Skene, can sharpen a belief, and can invert a
   source below chance.
3. **Correlated sources.** M1 and M4 show what a purely likelihood-based
   method does with copying and collusion: it becomes confidently wrong.
   CrossEngin's flat counting fails more gently there. Any redesign should
   keep that robustness, for example by down-weighting sources whose claims
   are nearly always identical.

## Files

| File | Contents |
|---|---|
| `manifest.json` | Driver and input hashes, modes, seeds, cross-check failures (0) |
| `scores.tsv` | Brier, ECE, accuracy, and M4 target accuracy for every mode, seed and arm |
| `stats.tsv` | The 25 tests |
| `summary.tsv` | Means per mode and arm |
| `data.tar.xz` | `data/<mode>-sNN/`: dataset, per-arm beliefs, mo weights per batch |
