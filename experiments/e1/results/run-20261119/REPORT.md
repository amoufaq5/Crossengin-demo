# E1 results: which learning mechanisms change what the chat says?

This is the run `run-20261119` of the pre-registered study
([../../PREREG.md](../../PREREG.md)).

| | |
|---|---|
| Git revision | `d6abad26533ec65eef9b4e4a97e9791096953658` (clean; no `src/`, `examples/` or `experiments/e1/` changes) |
| Chat binary SHA-256 | `d377b76b8ccef050…` (full hash in `manifest.json`) |
| Design | the full registered study: 14 arms × 5 permutations, not partial |
| Determinism gate | passed. The full arm was byte-identical across two runs of every permutation |

**Deviations from the pre-registration: none.**

## Summary

- **The moment cache is the only mechanism that changes correctness at full
  strength.** Turning it off fixes 23 items and breaks none. It hides the
  effect of operator confidence (BETA): with the cache off, removing BETA
  costs 17 items.
- **Substrate, predictive coding and Forward-Forward change no reply.** That
  holds for every one of the 200 items in all 5 permutations.
- **Intent-adaptive prototypes (IA) hurt three items.** Turning IA off fixes
  them.
- **Router-table weights (SYNW) have no significant effect.** Neither does
  the B3 Hebbian step (`CE_HEBB`). So `CE_HEBB` stays off by default.

## Primary analysis

The table is `stats.tsv`.
- An item counts as correct for an arm if it is correct in at least 3 of the 5 permutations.
- b = items the arm lost; c = items the arm gained.
- The test is an exact two-sided McNemar test, Holm-adjusted over the 13 comparisons.

| Arm | Compared with | Correct (arm / comparator) | b lost | c gained | p (Holm) | Significant | Items whose text differs |
|---|---|---|---|---|---|---|---|
| abl_substrate | full | 164 / 164 | 0 | 0 | 1 | no | 0 |
| abl_ff | full | 164 / 164 | 0 | 0 | 1 | no | 0 |
| abl_pc | full | 164 / 164 | 0 | 0 | 1 | no | 0 |
| abl_cache | full | 187 / 164 | 0 | 23 | 3.1·10⁻⁶ | **yes** | 49 |
| abl_ia | full | 167 / 164 | 0 | 3 | 1 | no | 3 |
| abl_synw | full | 164 / 164 | 0 | 0 | 1 | no | 6 |
| abl_beta | full | 155 / 164 | 12 | 3 | 0.39 | no | 30 |
| abl_all | full | 170 / 164 | 12 | 18 | 1 | no | 53 |
| hebb | full | 166 / 164 | 2 | 4 | 1 | no | 30 |
| hebb_nocache | abl_cache | 192 / 187 | 1 | 6 | 1 | no | 31 |
| nocache_beta | abl_cache | 172 / 187 | 17 | 2 | 0.0087 | **yes** | 34 |
| nocache_synw | abl_cache | 192 / 187 | 0 | 5 | 0.63 | no | 16 |
| nocache_ia | abl_cache | 190 / 187 | 0 | 3 | 1 | no | 3 |

## Hypotheses

### H1: the moment cache costs correctness. Confirmed.

abl_cache is significantly better than full. It gained 23 items and lost
none. The gains are the predicted ones:
- cluster collisions: R04a–R11b, P21, H03, H04, H06;
- a colliding nonce word: U04;
- flip re-asks: F02q, F07q, F09q;
- hedge follow-ups that the cache answers with the pre-feedback reply: B06q,
  B09q, B10q, B13q, B14q and H39.

### H2: substrate, PC and FF change nothing a user can see. Confirmed.

For abl_substrate, abl_pc and abl_ff:
- `items_text_differs` = 0, so no scored item's reply text differs in any
  permutation;
- b = c = 0.

### H3: operator confidence (BETA) carries the hedge. Confirmed.

| Comparison | Result | Prediction |
|---|---|---|
| nocache_beta vs abl_cache (the main test) | significantly worse: lost 17 (all 15 hedge items B01q–B15q, plus H38 and H39), gained 2 | met |
| abl_beta vs full | lost 12, gained 3; unadjusted p = 0.035, Holm p = 0.39 | direction as predicted; significance was not predicted |
| abl_synw vs full | b + c = 0 | null holds |
| nocache_synw vs abl_cache | b + c = 5 | null holds |
| abl_ia vs full | b + c = 3: B16q, H25 and H40, all gains | null holds |
| nocache_ia vs abl_cache | b + c = 3, the same three items | null holds |

In abl_beta vs full, the cache answers five of the hedge follow-ups in the
full arm anyway. That is why those five items do not count as losses there.

The IA result matches the prediction exactly: the reinforced intent
prototypes misclassify `treat` and the late arithmetic item, and turning IA
off fixes those three items.

### H4: everything off. Not significant (no direction was predicted).

abl_all lost 12 items and gained 18.
- The gains are the cache items.
- The losses are BETA's hedge items, plus H08 and H38.

### H5: the B3 Hebbian step. Null predictions hold, and the decision rule is not met.

| Comparison | lost | gained | b + c | Significant |
|---|---|---|---|---|
| hebb vs full | 2 (H08, P20) | 4 (H07, H37, H40, R22) | 6 | no |
| hebb_nocache vs abl_cache | 1 (P20) | 6 (F01q, F05q, F08q, H36, H37, R22) | 7 | no |

`CE_HEBB` would become the default only if all three conditions held. They
do not:
- Condition 1 fails: hebb_nocache vs abl_cache is not significant.
- Condition 2 holds: hebb vs full shows no significant loss.
- Condition 3 fails: P-block pooled correctness drops in hebb (920) compared
  with full (966).

`CE_HEBB` therefore stays off by default. It does change behaviour: the
reply text differs on 30 items. On net it changes the chain chosen at the
fever fork, gaining 4 items and losing 2.

## Pooled correctness per block

The table is `blocks.tsv`. Values are per mille over items × permutations.

| Arm | R | P | C | U | B | F | H |
|---|---|---|---|---|---|---|---|
| full | 750 | 966 | 1000 | 960 | 625 | 111 | 795 |
| abl_cache | 975 | 1000 | 1000 | 1000 | 937 | 422 | 875 |
| abl_beta | 750 | 966 | 1000 | 960 | 0 | 0 | 770 |
| abl_ia | 750 | 966 | 1000 | 960 | 687 | 111 | 840 |
| abl_synw | 750 | 966 | 1000 | 960 | 625 | 111 | 805 |
| abl_all | 975 | 1000 | 1000 | 1000 | 62 | 0 | 875 |
| hebb | 750 | 920 | 1000 | 960 | 625 | 111 | 830 |
| hebb_nocache | 965 | 953 | 1000 | 1000 | 925 | 622 | 915 |
| nocache_beta | 975 | 1000 | 1000 | 1000 | 0 | 355 | 865 |
| nocache_synw | 975 | 1000 | 1000 | 1000 | 937 | 600 | 915 |
| nocache_ia | 975 | 1000 | 1000 | 1000 | 1000 | 422 | 925 |

abl_substrate, abl_ff and abl_pc are identical to full and are omitted.

**Note on the F block.** Even without the cache, at most 62% of flip
re-asks change their reply *and* stay on topic after `/bad`. Under abl_beta,
F is 0. With confidence updates off, `/bad` changes nothing, so the reply
never changes.

## What this means

1. **The moment cache should not serve replies the way it does now.** It
   returns one input's reply for another input in the same concept cluster.
   It also keeps serving a reply after `/bad` or `/correct`. Possible fixes:
   - key the cache on the input as well as the moment vector;
   - invalidate it on feedback.
2. **Three mechanisms have no behavioural effect in the chat as wired:**
   substrate ticks, predictive coding and Forward-Forward. Either connect
   them to something that changes a reply, or stop describing them as
   learning that affects answers.
3. **Operator confidence (BETA) is the mechanism that makes feedback
   visible.** It is responsible for the hedge, and the cache is what hides it.
4. **The F-03 Hebbian fix makes the router table learn, but that learning
   does not improve these replies.** `CE_HEBB` stays opt-in.

## Files

| File | Contents |
|---|---|
| `manifest.json` | SHA-256 of the binary and of every input, plus the git revision |
| `raw/<arm>/p<k>.out` | the exact chat output |
| `determinism.tsv` | the determinism gate result |
| `scores.tsv` | per arm, permutation and item |
| `stats.tsv` | the primary analysis |
| `blocks.tsv` | pooled correctness per block |
