# Ingest options for E2 (conflicting sources)

The E2 experiment (audit §8) asks whether per-source trust yields
better-calibrated beliefs when sources of different reliability make
conflicting claims. B5 adds the production pieces it needs. Every new
behaviour is opt-in: with no flags set, ingestion and the meta-observer behave
as before. The exception is the labelled attribution in "Bug fixes" below,
which is a correctness fix.

**E2 results (2026-11-19).** See
`experiments/e2/results/run-20261119/REPORT.md`.
- Tier weighting is worse calibrated than counting every claim equally.
- The meta-observer's learned weights help only against a systematic liar.
- One-coin Dawid–Skene is far better calibrated unless sources copy each
  other or collude.
- The limit is the belief model (the declaration prior, and weights in [0, 1]
  that can only dilute evidence), not the trust estimate.

## `pip_ingest_ex(reg, record, mo, capreg, flags, sa)`

This is `pip_ingest_with_capreg` with option flags (`src/ingest/pipeline.nova`).
- `sa` is a `source_authority` table. Only `PIP_F_TIER_WEIGHT` uses it, and it
  may be 0.
- With `flags = 0`, the status list, the beliefs and the attributions are the
  same as `pip_ingest_with_capreg`. `test_e2_ingest` checks this.

| Flag | Effect |
|---|---|
| `PIP_F_NO_RESEED` (4) | An `ATOM` line for an atom that already exists is only a declaration. Without it, a seed above the current mean resets alpha and beta to the seed, which wipes every observation so far. EMPIRICAL association atoms follow the same rule. |
| `PIP_F_TIER_WEIGHT` (1) | Every `OBS` weight is scaled by the source's evidence weight: `sa_weight_for_host(sa, mo_tag_to_host(source_tag))`. That is an explicit weight if one was set with `sa_host_set_weight`, otherwise the tier table (A 1000, B 500, C 200; unknown hosts are C). `ATOM` seed mass is not scaled. |
| `PIP_F_SIGNED_ATTR` (2) | Attribution records the direction of each claim through `mo_attribute_signed`. An `OBS` is attributed with its sign and raw weight. An `ATOM` with a seed above 500 counts as +1 and below 500 as −1; a seed of exactly 500 is not a claim. |

**For E2:** declare each fact once at 500, so it carries a neutral prior, and
express every source's claim as an `OBS` line.

## Meta-observer (`src/parts/meta/meta_observer.nova`)

- **`mo_attribute_in(mo, tag, kg_label, atom_id)`.** Attributes an atom
  together with the KG it lives in, because atom ids are local to each KG.
  `mo_attribute(mo, tag, id)` is the unlabelled form; an unlabelled entry is
  resolved in the KG passed to the poll, as before.
- **`mo_attribute_signed(mo, tag, kg_label, atom_id, sign, weight)`.** The
  stance mass of each entry accumulates. The net stance is +1, −1 or 0, and a
  plain attribution counts as +1. The poll uses the *effective* mean: the
  atom's mean for stance +1, and 1000 − mean for −1. So "durable" means the KG
  now agrees with what the source claimed. An entry whose stance cancels out
  counts neither way.
- **`mo_poll_reg(mo, kg, kgreg, refl_kg, now)`.** Resolves labelled entries
  in the registry KG with that label. `mo_poll(mo, kg, refl_kg, now)` is the
  same call with no registry.
- **`mo_live_split(mo, tag, kg, kgreg)`.** The live `[tentative, durable]`
  split, using the same rules as the poll.
- **`mo_source_reliability(mo, tag, kg, kgreg)`.** A continuous reliability
  in milli: the smoothed mean of a source's effective means,
  `(Σ eff + 500) / (n + 1)`. It is 500 for an unknown source. The means
  include the source's own (tier-weighted) evidence, so a loop that feeds
  this back into `sa_host_set_weight` reinforces itself.
- **`mo_attribute_note(mo, tag, kg_label, atom_id)`.** Records an atom whose
  belief the pipeline seeded itself, such as a citation edge (900) or an
  EMPIRICAL association (800), with stance 0. It counts in the sample but
  never as a promotion or atrophy. A later claim on the same atom turns it
  into an ordinary attribution.
- **`mo_stance(mo, tag, kg_label, atom_id)`.**

`sa_host_set_weight(sa, host, w)` and `sa_weight_for_host(sa, host)` are in
`src/learning/source_authority.nova`.

## Bug fixes

1. **The meta-observer looked up ingested atoms in the wrong KG.** The
   pipeline attributed bare atom ids, and `/meta`, `/__metrics__` and the
   daemon polled the reasoning KG. So an ingested atom was judged by whatever
   reasoning atom shared its id.
   - The pipeline now always attributes with the atom's KG label, using
     `citations` for citation atoms. Citation and association atoms are
     recorded as notes, because their beliefs are pipeline-seeded and would
     otherwise count as instant promotions once resolved in the right KG.
   - `/meta`, `/__metrics__` and the daemon poll with the session's KG
     registry.
   - Scenario D checks this: two ingested atoms at 950 now show as durable.
   - Sessions without ingestion print the same `/meta` as before.
2. **Attribution ignored the sign of a claim.** A source that contradicted a
   fact was credited when the fact became durable. This is fixed under
   `PIP_F_SIGNED_ATTR` and the new meta-observer API.
3. **An `ATOM` line could reset an atom's evidence.** This is fixed under
   `PIP_F_NO_RESEED`. The default is unchanged, because
   `test_no_backslide_from_reingest` pins it.

The RPC verb `ingest.approve` had two further bugs:
- it passed the capsule registry where the KG registry belongs, so approval
  crashed;
- it reported `approved:false` on success, because `RQ_APPROVE_OK` is 0.

Both are fixed. The reply now also carries the `RQ_APPROVE_*` code.
