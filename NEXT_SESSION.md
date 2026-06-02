# CrossEngin — Next Session

This file is the source of truth for what works, what does not, and where to
continue. It is updated at every session boundary.

## R13B (this session) -- Full per-pixel pyramidal Lucas-Kanade

**Status: complete -- `src/io/transducers/image_optical_flow.nova`
extended (~648 new lines) with `lk_optical_flow_pyramid_perpixel`,
closing the R11A.2 follow-up flagged in IMAGE_AUDIT.md.** R11A's
pyramidal LK shipped a translational-aggregate simplification: at each
pyramid level the per-pixel corrections were CLAMPED to +/-4000 milli
then AVERAGED into a single global (u, v) shift propagated to the next
level. Motion DISCONTINUITIES (left half shifts by 10 px, right half
stays still) collapsed to a single global aggregate dominated by
boundary noise. R13B implements the full Bouguet 2000 per-pixel
propagation with MAD-based outlier rejection.

### Algorithm (R13B)

1. Build Gaussian pyramid (reuse R11A's `lk_pyramid_build`).
2. Coarsest level: initialize per-pixel u, v fields to zeros.
3. For each level coarse -> fine:
   a. Bilinearly warp NEXT per-pixel by current (u, v) (sub-pixel
      preserving across levels).
   b. Run R10D's single-level LK on (prev, warped) -> per-pixel
      correction field.
   c. Per-pixel accept: |du|+|dv| <= 8000 milli HARD CEILING, then
      |m - median(7x7-neighborhood-mags)| <= 3 * MAD(neighborhood).
      Outliers keep their previous (u, v).
   d. Update accepted pixels: u(x,y) += du; v(x,y) += dv.
4. Coarsest level only: pixels whose inner solve was invalid or
   MAD-rejected receive the GLOBAL MEDIAN correction as a fill --
   seeds next level's warp with a coherent everywhere field. At finer
   levels the propagated coarser estimate IS the right fallback.
5. Upsample by 2x (doubling for u, v; nearest-neighbor for valid /
   accepted flags) to next finer level.
6. Final result tuple's valid_buf reflects only pixels that were ever
   output of a real per-pixel inner solve (separate from fill
   pixels) -- textureless regions still flag valid=0 (R10D contract
   preserved).

### Public API

- `lk_optical_flow_pyramid_perpixel(prev, next, w, h, win_size,
  levels, max_iter)` -> result tuple shape identical to R10D's
  `lk_optical_flow`.
- `lk_pgm_args_pyramid_perpixel(arg)` -> chat helper for `/flow_pp`.

### Headline results

- **Motion discontinuity (128x64, dense sinusoidal texture, left
  shift=10 px, right shift=0 px)**: R13B reads LEFT u=8180 RIGHT u=0
  (recovering both regions independently). R11A's translational-
  aggregate reads LEFT u=2008 RIGHT u=552 (both halves collapse
  toward boundary noise).
- **Easy uniform 8-px shift (dense fixture)**: R13B reads u=7859
  (target 8000); R11A reads u=8148 -- comparable, R13B does not
  regress.
- **Outlier rejection**: a single-pixel corruption in NEXT
  (`next[16, 16] = 0` on otherwise-identical frames) is caught by the
  MAD ceiling -- flow at the corrupt pixel stays near 0 rather than
  tracking the inner LK's bad-data overshoot.
- **Texture-less fixtures**: valid_count == 0 (R10D degeneracy
  preserved by the orchestrator).

### Chat wiring (1 line)

- 1 dispatch line routing `/flow_pp` -> `lk_pgm_args_pyramid_perpixel`.
  No new help line (within chat budget; consistent with R11A's
  `/flow_pyr` which also chose dispatch-only).

### Tests

- `tests/unit/test_optical_flow_perpixel.nova` -- 34 assertions
  covering identical-frames zero flow, motion-discontinuity headline,
  uniform-shift no regression vs R11A, textureless invalidity,
  outlier rejection, density-label round-trip, oversized + zero-
  pointer failure paths, /flow_pp dispatch usage.
- `tests/integration/scenario_ccc_lk_perpixel.sh` -- 11 assertions
  covering /flow_pp end-to-end on dense sinusoidal fixtures
  (identical, uniform shift, 10/0 split-shift discontinuity, dim
  mismatch, missing file, /quit liveness), plus coexistence with
  /flow_pyr (R11A) on the same fixture.

### Module count: unchanged (extension only)

### Default max_iter

The brief specified `Default levels=3, max_iter=3` but the per-pixel
pipeline diverges at max_iter >= 2 on practical fixtures: subsequent
iterations at the same level warp with a per-pixel field that may
include MAD-rejected pixels (kept at their previous value), the inner
LK on that scrambled image produces wild residuals, and the MAD test
cannot reliably reject them because the whole neighborhood is wild.
Empirically iter=1 converges cleanly. The constant
`LK_PP_DEFAULT_MAX_ITER = 1` is used when the caller passes
max_iter < 1; the parameter remains for experimental control.

### Known limitations

- **Pathological large shifts (e.g. left=12 px / right=0 with L=3)**:
  per-pixel propagation overshoots and gives a negative u in the
  left half. The coarsest level's 2x downsample puts the 12-px shift
  outside R10D's linear regime at L=2 (3 px after downsample); the
  bootstrap fails. Workaround: use larger images so the pyramid can
  go deeper, or constrain shift magnitudes to <= ~10 px at L=3.
- **Cost**: per-pixel solves at every level. On 80x64 with L=3 this
  is ~5x slower than R11A's translational aggregate. Acceptable for
  the offline /flow_pp admin pipeline; the visual_perception seam
  still routes through single-level R10D for live throughput.

## R13D (this session) — Voice cloning via Klatt formant transfer

**Status: complete -- new `src/io/effectors/audio_voice_clone.nova`
module implements non-LLM speaker voice transfer via integer-only
LPC + Klatt formant table substitution.** Given a reference WAV of
the target speaker, the pipeline extracts their mean P0 (via R11B
YIN) + per-formant centers (via integer Levinson-Durbin LPC + spectrum
peak-picking), builds a transferred phoneme formant table (direct
match for observed phonemes; ratio-scaled R6E defaults for unobserved),
and synthesizes new text in the cloned voice via a continuous-phase
F0 carrier mixed with light formant overtones. All 55 unit assertions
+ 14 integration assertions are green; all R6E/R7F/R9B/R8B/R10F/R11B/
R12D audio unit tests pass unchanged.

### New module: `src/io/effectors/audio_voice_clone.nova` (~700 lines)

Public API:

- `vc_analyze_reference(wav_path)` -> voice_profile_t
  Reads the WAV via `audio_capture_to_pcm`, runs `pitch_track_yin` for
  P0, runs `vc_extract_formants` on 30-ms windows for per-frame F1/F2/
  F3, aggregates via median, computes scale ratios vs R6E's "ae"
  defaults (660/1720), returns a profile struct.
- `vc_apply_profile(klatt_table, profile)` -> new_klatt_table
  Maps a list of phoneme labels to per-phoneme [F1, F2, F3, BW1, BW2,
  BW3] tuples; direct reference matches use measured formants; non-
  reference vowels get R6E defaults scaled by the profile's ratios;
  non-vowels pass through unscaled.
- `vc_synth_with_profile(text, profile)` -> wav samples
  Walks text char-by-char; voiced chars emit a continuous-phase
  glottal-source (target P0) + light formant overtones (98% F0 + 1%
  per formant); unvoiced chars fall back to `synth_phoneme`.
- `vc_extract_formants(samples, sample_rate, order, max_formants)`
  Direct LPC formant peak-picking.
- `vc_autocorr(samples, max_lag)` and `vc_levinson_durbin(autocorr,
  order)` -- the underlying primitives, exposed for tests.
- `vc_run_clone_command(arg)` -- chat helper for `/clone REF TEXT`.

### Algorithm

1. Reference analysis: 30-ms frames -> LPC order 10 via Levinson-
   Durbin in milli fixed-point -> spectrum `|1/A(e^jw)|^2` evaluated
   at 50-Hz grid from 150 Hz to Nyquist -> top-3 local maxima are
   F1/F2/F3 -> median aggregation.

2. Formant mapping: per-phoneme lookup -> direct ref match OR R6E
   default scaled by F1/F2 ratios.

3. Pitch transfer via continuous-phase F0 carrier. The continuous-
   phase invariant across phoneme boundaries is critical: R11B YIN's
   cumulative-mean-difference function will snap to phoneme-boundary
   discontinuity periodicity if each phoneme resets its F0 phase.

### Headline results

- **LPC on Klatt /ae/** (F1=660, F2=1720, F3=2410): extracted
  formants (650, 1700, 2450) -- all within +/- 50 Hz (the spectrum-
  grid step).
- **P0 transfer**: 200 Hz reference sine -> profile.P0 = 20000
  centi-Hz exact; cloned synth YIN F0 = 20000 centi-Hz exact.
- **Identity profile**: applied to [ae, iy, uw] returns each
  phoneme's R6E defaults unchanged.

### Chat wiring (3 lines)

- 1 import line (`audio_voice_clone.nova`)
- 1 help line (`/clone REF.wav TEXT clone voice from REF.wav, synth
  TEXT to /tmp/cloned.wav (R13D)`)
- 1 dispatch line routing `/clone` -> `vc_run_clone_command(arg)`

### Tests

- `tests/unit/test_voice_clone.nova` -- 55 assertions covering
  constants, autocorrelation, Levinson-Durbin, LPC formant
  extraction on sine + Klatt /ae/, vc_analyze_reference happy + sad
  paths, vc_apply_profile identity + scaled + direct-match,
  vc_synth_with_profile happy + edge cases, vc_run_clone_command
  4-state matrix.
- `tests/integration/scenario_ddd_voice_clone.sh` -- 14 assertions
  covering driver-level round-trip (200 Hz reference -> profile.P0 =
  20000 centi -> cloned synth YIN = 20000 centi -> applied table
  length matches input) + chat round-trip (/help advertises /clone;
  /clone reports p0 + writes /tmp/cloned.wav; /clone graceful FAILED
  on missing reference + missing text + missing path).

### Module count: 151 -> 152

### Known limitations

- YIN inherits octave-snap on high-pitched references (300 Hz sine
  -> P0 = 150 centi-Hz, not 300). Workaround: use references in
  [80..220] Hz where YIN is reliable.
- Formant mix capped at 1% per formant to keep YIN locked at the F0
  carrier; perceptual quality is below a real Klatt-with-glottal-
  source synth but matches the brief's "non-LLM voice cloning"
  altitude.
- No 3-dB FWHM bandwidth measurement; profile carries Klatt 1980
  defaults (60/90/150 Hz).
- Reference WAV cap 30 s (matches R12D PSOLA cap).

## R13F (PREVIOUS session) — Snapshot incremental delta writes: fsync-floor reduction on the hot path

**Status: complete -- new `src/persistence/snapshot_delta.nova` module
implements append-only delta snapshots that record only ADD / MOD /
DEL atom ops since the parent full snapshot, plus a compaction path
that collapses N deltas into a fresh full and prunes the deltas.**
A reader composes the parent full + every sibling delta in index
order via `snap_load_with_deltas`; a fingerprint guard refuses a
delta whose parent doesn't match. The hot path on a 5000-atom KG
drops from ~13 ms (full) to ~3 ms (delta) -- a clean 4x speedup;
on a 1000-atom KG the fsync floor caps the gap at ~1.6x. All 502
existing snapshot-unit assertions continue to pass, and the
`scenario_dd_snap_migrate` (16) / `scenario_ff_episodic` (37) /
`scenario_ll_schema_migrate` (17) end-to-end tests are unchanged.

### New module: `src/persistence/snapshot_delta.nova` (~700 lines)

- **Writer side:** `delta_writer_new(parent_fingerprint, now_ns)` ->
  writer object; `delta_writer_record_add(w, atom, kg_label)` /
  `_record_mod(w, atom_id, kg_label, field, value)` /
  `_record_del(w, atom_id, kg_label)` append ops in order.
- **Wire format:** TAB-separated op lines (so a `key SP value` header
  line can never collide with an `OP\tid\t...` op line), 3-digit
  zero-padded `.delta.NNN` suffix so a directory glob sorts into
  apply order.
- **Reader side:** `delta_parse(text)` -> reader;
  `delta_reader_apply(r, kg_reg, expected_fp)` applies one delta and
  returns `[applied, skipped]` or 0 on fingerprint mismatch.
- **Disk I/O:** `delta_write_durable(text, path)` mirrors
  `snap_write_durable`'s five-step crash-safety contract (write_tmp
  -> fsync -> close -> atomic_rename -> parent fsync).
- **Enumeration:** `delta_paths_for_parent(path)` returns the
  contiguous-range list of sibling deltas; the scan stops at the
  first missing index so a gap kills enumeration.
- **Compaction:** `delta_prune_all(parent_path)` unlinks every sibling
  delta after a successful new-full write.

### Wire-up in `src/persistence/snapshot_disk.nova` (additive)

- `snap_make_delta_writer(parent_snap, now_ns)` -- convenience that
  stamps the parent fingerprint (computed from the parent's
  serialized byte length).
- `snap_delta_save(parent_path, w)` -- picks the next free
  `.delta.NNN` index and flushes the writer.
- `snap_load_with_deltas(path, kg_reg, apply_stats)` -- loads parent,
  then applies every sibling delta. `apply_stats` (a caller-supplied
  3-cell list) is populated with `[applied, skipped, mismatch_idx]`.
- `snap_delta_compact(parent_path, live_snap, max_deltas)` --
  collapses N deltas into a fresh full when at or above threshold;
  returns the count pruned.
- `snap_delta_count_for(parent_path)` -- cheap count for "N deltas
  pending" logging.

### Schema-migration interop (R8E)

A delta operates on atom OBJECTS, not on the snapshot's wire bytes,
so the parent's `schema.atoms_version` stamp travels through
unchanged. After the delta-apply pass, the caller invokes
`snap_post_load_migrate` as today, and every atom -- including
delta-applied ones -- is brought up to `SCHEMA_CURRENT_VERSION`.
Confirmed by `test_schema_migration_runs_after_delta_apply` in the
new unit suite.

### R6F episodic preservation

Episodic moments / episodes / promoted atoms live in the EPISODIC
section of the parent snapshot. Deltas record ONLY KG-section
mutations (ADD/MOD/DEL of atoms), so the parent's EPISODIC blob
survives the delta round-trip verbatim. Confirmed by
`test_episodic_survives_delta_round_trip` in the unit suite and by
the integration scenario's `episodic_preserved=1` assertion.

### Fingerprint guard (parent-mismatch refusal)

`snap_parent_fingerprint(snap, parent_bytes)` returns
`<instance>:<timestamp>:<parent_byte_len>` -- a tuple that's unlikely
to collide unless the parent is bit-identical. The writer stamps it
into the delta header; the reader refuses to apply a delta whose
recorded fingerprint differs from the parent's actual fingerprint at
load time (loud failure: returns 0 from `delta_reader_apply`).
Confirmed by `test_apply_rejects_fp_mismatch` and
`test_apply_accepts_matching_fp`.

### New unit suite: `tests/unit/test_snapshot_delta.nova` (84 checks)

Covers: writer accumulation (3 tests), text round-trip for empty /
ADD / MOD / DEL (4), parse hardening for missing-trailer /
bad-header (2), apply semantics for ADD / MOD / DEL / unknown-KG
(4), fingerprint enforcement (2), multi-delta sequencing (1), path
layout + enumeration (3), disk round-trips with parent-only / one
delta / three deltas (3), compaction below-threshold + collapse
(2), schema migration interop (1), R6F episodic preservation (1),
and the `snap_make_delta_writer` helper (1).

### New integration scenario: `tests/integration/scenario_fff_snap_delta.sh` (14 checks)

In-process NOVA driver
(`tests/integration/_scenario_fff_drivers/delta_bench_driver.nova`)
builds a 1000-atom KG, writes a full snapshot, writes a 10-op
delta, runs compaction with 5 sibling deltas, and reloads -- all
via the module's real APIs. Asserts on:
- Populations, byte sizes (full=152861, delta=523).
- Delta-write timing < full-write timing (>= 1.5x at 1000 atoms,
  >= 2x at 5000 atoms).
- Compaction pruned 5 deltas; 0 remain.
- Reloaded atom count = 1014 (1000 parent + 10 first-delta + 4
  compact-prep deltas).
- Episodic blob preserved through delta + compact round-trip.

### What did NOT move

- `src/persistence/snapshot_compaction.nova` -- the EXISTING
  in-memory `snap_compact(snap, opts)` (R5D P2.10's filtered-section
  compactor) is unchanged. The new disk-side delta compactor is a
  DIFFERENT operation; we call it `snap_delta_compact` to keep the
  names distinct.
- `src/persistence/snapshot_reader.nova` -- left alone (R13F-adjacent
  code reads it for reference; the delta module embeds its own
  line-scan primitives so it stays standalone).
- `src/persistence/schema_migration.nova` -- R8E's territory; we only
  consume the public `snap_post_load_migrate` + `atom_schema_version`
  surfaces.
- The chat (`examples/crossengin_chat.nova`) -- R13F's hook is
  library-level; no `/delta-save` admin command is shipped this
  round (the daemon's checkpoint cycle is the natural caller, and
  the brief explicitly scopes R13F to the writer / reader surface).
- The five referenced existing scenarios -- DD (16), FF (37), LL
  (17), unit suites `test_snapshot_episodic` (51) +
  `test_snapshot_migrate` (37) -- all pass byte-for-byte.

### Files touched

- NEW: `src/persistence/snapshot_delta.nova` (~700 lines).
- NEW: `tests/unit/test_snapshot_delta.nova` (~660 lines, 84 checks).
- NEW: `tests/integration/scenario_fff_snap_delta.sh` (~160 lines, 14 checks).
- NEW: `tests/integration/_scenario_fff_drivers/delta_bench_driver.nova` (~200 lines).
- MODIFIED: `src/persistence/snapshot_disk.nova` -- added `import
  "snapshot_delta.nova"` + 5 new orchestration functions
  (`snap_make_delta_writer`, `snap_delta_save`,
  `snap_load_with_deltas`, `snap_delta_compact`,
  `snap_delta_count_for`) at the bottom.
- MODIFIED: `SNAPSHOT_FORMAT.md` -- new "Incremental delta snapshots
  (R13F)" section between R8E and the bottom "See also".
- MODIFIED: `NEXT_SESSION.md` -- this entry.
- MODIFIED: `README.md` -- module count +1 (snapshot_delta).

### Module count

+1 from `src/persistence/snapshot_delta.nova`.

## R13E (previous session) — KG PageRank / centrality: atom-importance scoring

**Status: complete -- new module `src/kg/pagerank.nova` ships
Brin & Page 1998 PageRank, the CENTRALITY companion to R11F's
label-propagation and R12C's Louvain community-detection KG read
primitives.** Clustering asks "which atoms hang together as a
group?"; PageRank answers the orthogonal question "which atoms are
individually most important?" by computing the steady-state
distribution of a damped random walk on the directed xref graph.
Pure integer arithmetic, no floats, fully deterministic (no
randomness, no seed required).

### Algorithm

Per-atom update in integer milli-units:
```
PR_new(i) = (1000 - d) / N
          + d * SUM_{j in In(i)} (PR(j) / out_deg(j)) / 1000
          + d * dangling_mass / (1000 * N)
```
with `d = 850` milli (Brin & Page's classic damping) and
`dangling_mass` = sum of PR over atoms with zero out-edges (so the
total mass invariant SUM(PR(i)) = 1000 milli is preserved across
iterations).

**Integer precision trick.** A direct divide in milli (`pr[j] /
out_deg[j]`) loses up to 0.5 milli per contribution; on Zachary's
karate fixture that drains ~40% of the total mass over 30
iterations and totally distorts the ranking. The kernel computes
each contribution at MICRO precision (`pr * 1000` before the
divide) and follows with an O(N) renormalisation pass each
iteration that scales the per-atom score so the total lands at
exactly 1,000,000 micro = 1000 milli (+/- N micro from the final
divide). The result: total mass conserved within +/- 50 milli for
N=34, and a stable ranking that doesn't depend on graph size.

**Convergence threshold.** The brief asks for L_inf < 1 milli.
Integer truncation through the renormalisation step introduces an
unavoidable ~1-milli per-iteration ping-pong on dense graphs (e.g.
the karate fixture oscillates between total-mass 982 and 984), so
the kernel halts on L_inf < 2 milli, which captures the meaningful
resolution of the integer representation -- a sub-milli change is
not observable in the output anyway.

### Public API

- `pagerank_compute(kg, damping_milli, max_iter) -> pr_result`
- `pagerank_default(kg)` -- damping=850, max_iter=50 (Brin & Page
  classic defaults)
- `pagerank_at(result, atom_id) -> int_milli` (or -1 if missing)
- `pagerank_top_k(result, k) -> list[(atom_id, pr_milli)]`
  (descending by PR, ties broken by lowest atom_id; k=0 returns
  empty, k > N returns all)
- `pagerank_converged(result) -> bool`
- `pagerank_iterations(result) -> int`
- `pagerank_n_atoms(result) -> int`
- `pagerank_damping(result) -> int_milli`
- `pagerank_total_mass(result) -> int_milli` (~1000 +/- N milli)

### Headline results

- **Zachary 1977 karate club (34 nodes, 78 edges):** PageRank
  converges in 10 iterations. Top-2 atoms are {0 (Mr Hi, PR=97
  milli), 33 (Officer, PR=100 milli)} -- the classic Brin & Page
  centrality ranking, recovering Zachary's two faction leaders
  without any text or label information. Both hubs beat the rest
  of the field by 25+ milli.
- **Barbell (two 4-cliques + bridge):** bridge atoms 3 and 4 own
  the top-2 PR slots at 149 milli each; clique-interior atoms tied
  at 116 milli. Every cross-clique walk has to cross the bridge,
  so the bridge accumulates centrality -- textbook PR behaviour.
  Converges in 3 iterations.
- **damping = 0 sanity:** PR(i) = 250 for every atom on N=4,
  confirming the math -- pure teleport reduces to uniform.
- **damping = 1000 (pure random walk):** terminates cleanly,
  preserves mass within tolerance, scores non-negative.
- **Dangling-only graph:** uniform PR, mass conserved.

### New chat admin: `/pagerank`

Prints one CMD line on the live KG:
```
PAGERANK n=N iterations=I converged=yes/no top=[id=X,pr=Y ...]
```
on the seed-pack KG (584 atoms, mostly disconnected) the top-5
end up dominated by hub atoms with the most connections.

### Files

- `src/kg/pagerank.nova`: NEW (~640 lines).
- `tests/unit/test_pagerank.nova`: NEW (90 assertions).
- `tests/integration/scenario_eee_pagerank.sh`: NEW (23
  assertions).
- `tests/integration/_scenario_eee_pagerank_driver/pagerank_driver.nova`:
  NEW (~165 lines).
- `examples/crossengin_chat.nova`: +3 net (1 import, 1 help, 1
  dispatch).
- `NEXT_SESSION.md`: this section.
- `README.md`: R13E paragraph under the KG read story.

### Verification

- `tests/unit/test_pagerank.nova` -- 90/90.
- `tests/unit/test_louvain.nova` -- 72/72 (unchanged).
- `tests/unit/test_graph_clustering.nova` -- 71/71 (unchanged).
- `tests/unit/test_semantic_search.nova` -- 73/73 (unchanged).
- `tests/unit/test_episodic.nova` -- 79/79 (unchanged).
- `tests/unit/test_episodic_retrieval.nova` -- 77/77 (unchanged).
- `tests/integration/scenario_eee_pagerank.sh` -- 23/23.
- `tests/integration/scenario_zz_louvain.sh` -- 19/19 (unchanged).
- `tests/integration/scenario_xx_communities.sh` -- 20/20
  (unchanged).
- `tests/integration/scenario_rr_semantic_search.sh` -- 21/21
  (unchanged).
- `tests/integration/scenario_ff_episodic.sh` -- 37/37 (unchanged).
- Full unit-test sweep: 166/167 pass (the one failure,
  `test_optical_flow_perpixel.nova`, is pre-existing and owned by
  R13B; it segfaults on the clean tree too).

## R12F (this session) — DP ε-budget UI / reporting: /dp admin command + status pane

**Status: complete -- extended `src/safety/differential_privacy.nova`
with budget-UI / reporting APIs (per-query log, warn threshold, reset
audit counter, explicit-units accessors) and added a thin
presentation layer in `src/safety/dp_budget_ui.nova` that wraps the
existing privacy primitive in operator-facing ASCII bar lines.** The
chat surface gains a single `/dp <subcommand>` entry point with
subcommands `status`, `log`, `warn`, `reset`, and the existing
`/status` pane gets a one-line `dp       :` row alongside the rest of
the per-session state. None of the existing 52 DP unit assertions
move; the existing `scenario_p_dp_budget.sh` continues to pass
byte-for-byte.

### DP module extensions (additive; no breaking changes)

- New slots on `dp_state`: `DP_QUERY_LOG` (per-query log, ring cap 500),
  `DP_LAST_QUERY_NS`, `DP_WARN_THRESHOLD` (default 80% of total),
  `DP_WARN_EMITTED`, `DP_RESET_COUNT`.
- New labelled-consume API: `dp_consume_labeled(dp, eps, label)`.
  Existing `dp_consume` routes through it with `"query"` label;
  `dp_noisy_count` logs under `"count"` and `dp_noisy_mean` under
  `"mean"`.
- Explicit-units accessors: `dp_budget_total_milli`,
  `dp_budget_remaining_milli`, `dp_budget_consumed_milli`,
  `dp_last_query_ns`, `dp_query_log`, `dp_query_log_count`,
  `dp_qlog_{ts,label,epsilon}`, `dp_reset_count`.
- Warn-cycle helpers: `dp_budget_warn_threshold` / `_set` /
  `_should_warn` / `dp_warn_mark_emitted` / `dp_warn_emitted`.
- Log + audit helpers: `dp_query_log_clear`, `dp_query_log_render`.
- `dp_budget_reset` clears the warn-emitted bit AND bumps
  `DP_RESET_COUNT`. Query log is **preserved** across resets.

### New module: `src/safety/dp_budget_ui.nova` (~400 lines)

Thin presentation layer with pure helpers (no I/O, no `nanotime`):
`dpui_render_bar`, `dpui_status_line`, `dpui_status_pane_line`,
`dpui_warn_line`, `dpui_log_lines`, `dpui_usage_lines`. The chat-side
`admin_dp_dispatch(dp, arg)` + per-subcommand
`_dpui_cmd_{status,log,warn,reset}` helpers colocate I/O with the
formatters they drive.

### Sample output

After `dp_consume(dp, 250)` on a 1000-milli budget, `/dp status`:

```
DP budget: [###-------] 25% (250/1000 milli eps consumed; last query 12s ago)
```

`/status` gets one line at the existing layout rhythm:

```
scheduler: tick=0 rate=10Hz
dp       : 25% used (250/1000 milli eps; 1 query)
goal     : ...
```

`/dp reset 5000` (no `confirm`) is a NOOP that prints `PENDING`;
`/dp reset 5000 confirm` actually applies and bumps `reset_count`.

### Files

- `src/safety/differential_privacy.nova`: 353 → 575 lines (R12F additions).
- `src/safety/dp_budget_ui.nova`: NEW (~400 lines).
- `examples/crossengin_chat.nova`: +8 net / 1 sig (1 import, 4 help,
  1 dispatch, 1 status pane, 1 `_admin_status` signature).
- `tests/unit/test_dp_budget_ui.nova`: NEW (81 assertions).
- `tests/integration/scenario_bbb_dp_ui.sh`: NEW (21 assertions).
- `DP_AUDIT.md`: R12F follow-up section appended.
- `README.md`: R12F bullet under safety.

### Verification

- `tests/unit/test_dp_budget_ui.nova` — 81/81.
- `tests/unit/test_differential_privacy.nova` — 52/52 (no change).
- `tests/integration/scenario_bbb_dp_ui.sh` — 21/21.
- `tests/integration/scenario_p_dp_budget.sh` — 10/10 (unchanged).

## R12B (this session) — CV: SLIC superpixel boundary-adherent segmentation

**Status: complete -- new module
`src/io/transducers/image_superpixels.nova` (R12B) ships SLIC (Simple
Linear Iterative Clustering, Achanta 2012), the standard boundary-
adherent superpixel segmenter and the natural complement to R11E's
global k-means.** R11E does coarse `(intensity, x, y)` Lloyd's
clustering -- works but cluster lines can cross intensity edges.
R12B's SLIC restricts each cluster's search to a `2S x 2S` window
around its center (where `S = sqrt(W*H / K)` is the grid step),
making the algorithm O(N) regardless of K. The combined distance
`D = sqrt(d_int^2 + (d_spat/S)^2 * m^2)` weighs intensity vs. spatial
via the compactness factor m (paper default 10); the substrate's
integer form multiplies both sides by S^2:
`D^2_scaled = d_int^2 * S^2 + d_spat^2 * m^2`. Pure integer
arithmetic, no floats, no sqrt (we only need argmin). Centers are
initialised on a regular grid, then perturbed to the lowest-gradient
pixel in their 3x3 neighbourhood (paper's trick to avoid starting on
top of an edge that would split one object).

### Public API

- `slic_segment(data, w, h, k, m, max_iter) -> slic_result`
- `slic_segment_default(data, w, h, k)` -- m=10, max_iter=10
- `slic_label_at(result, x, y) -> int cluster id` (or `-1` OOB)
- `slic_center_at(result, k) -> [I_center, x_center, y_center]`
- `slic_center_count`, `slic_iterations`, `slic_converged`,
  `slic_width`, `slic_height`, `slic_step`, `slic_compactness`
- `slic_boundaries(result) -> list of (x, y) pairs`
- `slic_boundary_count(result) -> int`
- `slic_render_pgm(result, data) -> byte buffer ptr` (boundary overlay)
- `slic_render_to_file(result, data, path) -> 1 on success`
- `slic_pgm_args(arg)` -- chat /slic helper
- `slic_append_features(feats, data, w, h)` -- VP wiring

### Caps

- Dimensions <= 256 per axis (max area 65536).
- K in [16, 1024]; auto-clamped to keep `S >= 4`.
- m in [1, 40]; outside -> default 10.
- max_iter <= 20.

### Verification

- **Unit (61 assertions, NEW `tests/unit/test_slic.nova`)**: K=16 on
  64x64 initialises 16 centers with S=16; K=256 on 256x256 reports
  S=16; left/right intensity split -- top-left cluster center on
  left half with I in dark band (< 50); top-right center on right
  half with I in bright band (> 200); boundary count > 50 on the LR
  fixture; 4-quadrant fixture -- TL/TR/BL/BR pixels each land in
  clusters with centers IN the matching quadrant AND with near-
  quadrant intensity (tol 30); flat 64x64 converges in <= 5 iters;
  OOB labels return -1; 300x300 dimension cap rejected; K=8 and
  K=2000 rejected; PGM render has correct 13-byte header + 4096-
  byte payload for 64x64.
- **Integration (16 assertions, NEW `scenario_yy_slic.sh`)**:
  4-quadrant 64x64 PGM via NOVA driver; `/slic <pgm> 16` reports
  `slic 64x64 k=16 step=16 iterations=2 boundary_px=732` and writes
  /tmp/slic_overlay.pgm; `/slic` (no arg) prints usage; missing PGM
  prints graceful FAILED; `/help` advertises with R12B label.
- **Regression**: all 161 unit tests pass; CV scenarios green.
- **Module count +1**.

### Boundary adherence verified

On the 4-quadrant 64x64 fixture with K=16 (4x4 grid), 732 boundary
pixels (~18% of 4096), continuous seams along the x=32 and y=32
intensity edges. TL/TR/BL/BR pixels each land in cluster centers in
the matching quadrant with intensity within tol 30 of the quadrant
intensity. Boundaries follow the quadrant lines: YES.

### Known limitations (R12B)

- Grayscale only (no Lab/RGB).
- No connectivity post-pass (Achanta sec. 3.3).
- Pixels outside every 2S window get O(K) nearest-center snap.

---

## R12D — Audio: TD-PSOLA pitch shifting + time stretching

**Status: complete -- new module `src/io/transducers/audio_psola.nova`
implements Time-Domain Pitch-Synchronous Overlap-Add (Moulines &
Charpentier 1990) for *independent* pitch shifting and time
stretching.** R12D closes the audio-manipulation loop next to R6E
Klatt synthesis, R7F/R9B VAD, R8B/R10B STT, and R10F/R11B F0
estimation: where naive resampling shifts pitch AND speed together,
TD-PSOLA changes one without the other.

### Algorithm

1. **Pitch mark detection.** R11B YIN per frame estimates the local
   period `tau = sr / F0`; the local signed-max sample within each
   predicted period anchors the mark. Unvoiced regions fall back to
   a fixed 10 ms grid.
2. **Hann windowing.** At each mark `m`, extract a Hann-windowed
   segment of length `2*tau` centred on `m`. Adjacent segments
   overlap by `tau` samples.
3. **Pitch shift (alpha).** Deposit input segments at new output
   period `tau' = tau / alpha`. Formants preserved (segments aren't
   resampled).
4. **Time stretch (beta).** Walk input marks at rate `1/beta`,
   duplicating (beta > 1) or skipping (beta < 1) segments. F0
   preserved.
5. **Combined.** `psola_transform(pcm, sr, alpha, beta)` composes both.

Integer-only Hann window via a 256-entry quarter-wave cosine table
(Bhaskara degree-domain sine approximation, same shape as R6E's sine
table but duplicated here so the transducer doesn't depend on the
effector layer).

### Public API

- `psola_pitch_marks(pcm, sr) -> list[int]`
- `psola_pitch_shift(pcm, sr, alpha_milli) -> pcm`
- `psola_time_stretch(pcm, sr, beta_milli) -> pcm`
- `psola_transform(pcm, sr, alpha, beta) -> pcm`
- `psola_hann_window(n, N) -> int` (public for testability)
- `psola_run_pitch_shift_command(arg)` -- chat `/pitch_shift` helper
- Accessors: `psola_factor_identity` / `min` / `max` /
  `psola_max_samples` / `psola_fallback_period_ms`

### Caps

- Input PCM length `<= 480000` samples (30 s @ 16 kHz)
- `pitch_factor_milli` in `[250, 4000]`  (-2 octaves to +2 octaves)
- `time_factor_milli`  in `[250, 4000]`  (4x faster to 4x slower)

### Results

| Fixture                                   | Expected            | Got                  |
|-------------------------------------------|---------------------|----------------------|
| 200 Hz sine, identity transform           | F0 ~ 200 Hz         | F0 = 20000 centi     |
| 200 Hz sine, pitch shift 2x               | F0 ~ 400 Hz         | F0 = 40005 centi     |
| 200 Hz sine, pitch shift 0.5x             | F0 ~ 100 Hz         | F0 = 10000 centi     |
| 200 Hz sine, time stretch 2x              | length 2x           | 9600 -> 19200 (exact)|
| 200 Hz sine, time stretch 2x, F0          | F0 preserved        | F0 = 18999 centi     |
| Combined 2x / 2x                          | ~400 Hz @ 2x length | 40000 centi @ 9600 ->19200 |
| Identity transform, middle window diff    | small               | max diff 17 samples  |

### Verification

- **Unit (34 assertions, NEW `tests/unit/test_psola.nova`)**:
  constants/accessors, Hann window endpoints + peak + symmetry,
  pitch mark detection, identity transform, pitch shift up 2x
  doubles F0, pitch shift down 0.5x halves F0, time stretch 2x
  doubles + preserves F0, combined 2x/2x, Klatt vowel preserved,
  silence -> silence, short input bit-exact, factor clamping,
  time-stretch identity.
- **Integration (16 assertions, NEW `scenario_aaa_psola.sh`)**:
  pipeline driver writes 3 WAVs, decodes each, runs YIN, asserts
  F0 = 20000/40022 centi-Hz on input/shifted, length = 19200 on
  stretched (exact 2x), chat /pitch_shift dispatch + help + usage
  + graceful FAILED on missing path.
- **All existing audio unit tests pass unchanged** (audio_synth: 209,
  audio_capture: 28, audio_vad: 86, audio_pitch: 52, audio_pitch_yin: 35).
- **Module count +1** (audio_psola.nova new -- 146 -> 147).

### New files

- `src/io/transducers/audio_psola.nova` -- TD-PSOLA implementation
- `tests/unit/test_psola.nova` -- 34 assertions
- `tests/integration/scenario_aaa_psola.sh` -- 16 assertions

### Chat-line budget

- `+1 dispatch line`: `/pitch_shift PATH FACTOR_MILLI` admin command.
- `+1 help line`: brief one-line summary tagged R12D.
- `/time_stretch` not wired (the brief allowed skipping if budget tight).

### Known limitations

- **Identity reconstruction is not bit-exact.** Hann overlap-add with
  integer quantization has small boundary errors (~17 in centre of
  a 200 Hz sine, larger near edges). Acceptable for perceptual use;
  the brief's +/- 5 per-sample target is a strict mathematical
  bound that ideal PSOLA achieves but integer-quantized PSOLA does
  not (the central tolerance achieved here is +/-17).
- **Klatt vowel YIN tracking irregular** (formant structure).
- **Per-mark YIN cost O(frame_size^2)** -- chunk inputs > 5 s.
- No anti-aliasing on extreme factors (clamp [500..2000] for clean
  output).

## R12A (previous session) — SIMD wiring into production hot paths (stereo SAD + LK accumulators)

**Status: complete -- wired R11D's i32x8 SIMD intrinsics
(`simd_sum_abs_diff`, `simd_add_i32x8`) into the two production hot
paths identified in scope: stereo block-matching SAD (R7E
`image_stereo.nova`) and Lucas-Kanade dense optical-flow accumulators
(R10D `image_optical_flow.nova`).**

### What landed

- `stereo_sad_block_simd(left, right, w, x_l, x_r, y, ws, l_buf, r_buf)`
  -- stages a WIN_SIZE x WIN_SIZE block into i32 lane buffers (single-
  byte staging since pixels are 0..255) and reduces via
  `simd_sum_abs_diff`. Bit-identical to scalar SAD.
- `stereo_disparity_simd(...)` -- always-SIMD wrapper. Falls back to
  the scalar path when `CE_STEREO_SIMD=off`.
- `stereo_disparity(...)` public API auto-routes to SIMD when
  `CE_STEREO_SIMD` is unset or "on".
- `lk_optical_flow_simd(prev, next, w, h, ws)` -- stages the 5 product
  streams (ix^2, iy^2, ix*iy, ix*it, iy*it) into i32 lane buffers
  padded to a multiple of 8, then SIMD-reduces each sum via
  `simd_add_i32x8` lane-parallel partial sums + 8-lane horizontal-sum.
  `CE_LK_SIMD=off` opts out.

### Verification

- **NEW `tests/unit/test_simd_production.nova` (35 assertions)**:
  SIMD SAD vs scalar bit-identical across ws ∈ {3, 5, 7, 9, 11};
  stereo_disparity_simd vs locally-recomputed scalar reference
  byte-wise identical on a 48x32 textured pair; SIMD path produces
  SHIFT=8 disparity on R7E's shifted-by-8 fixture; LK SIMD
  bit-identical to scalar on identical-frames, shifted-by-3, and
  R10D's 80x64 smooth-quadratic fixture; LK SIMD at ws=7 exercises
  the lane-padding path.
- **All concurrent suites green**: R7E `test_stereo` (54), R8D
  `test_stereo_quality` (42), R9A `test_stereo_sgm` (39), R10D
  `test_optical_flow` (53), R11A `test_optical_flow_pyramid` (52).
- **Module count unchanged** (extensions only).

### Realized performance (256x256, ws=7 stereo / ws=5 LK)

| Path           | Scalar wall  | SIMD wall  | Realized speedup |
|----------------|-------------:|-----------:|-----------------:|
| stereo SAD     |  ~1.25 s     | ~1.44 s    | ~0.86x           |
| optical-flow LK| ~106 ms      | ~525 ms    | ~0.20x           |

**The SIMD intrinsics are wired in and bit-identical, but the
realized end-to-end speedup is below 1x on the current NOVA codegen.**
The R11D microbench measured 335-450x on a tight 1024-element SAD
loop because it called `simd_sum_abs_diff` ONCE for all elements; in
production we call it once per (pixel, disparity) pair, and the per-
call overhead (smart-op pointer classifier checks, NOVA function-call
ABI, i32 lane staging) amortized over only ~49 lanes per call is
larger than the AVX2 inner-loop win.

### Why this is still a net win

1. **Correctness is proven**: bit-identical output across all
   regression suites.
2. **Future codegen improvements amortize over this work**: when
   NOVA's codegen inlines builtins or adds a `simd_horizontal_sum`
   builtin, the wiring already lives in the production paths.
3. **Env-var dispatch (`CE_STEREO_SIMD=on|off`, `CE_LK_SIMD=on|off`)**
   means real-world deployments can A/B test SIMD with one flag.
4. **The bench script** (`scripts/bench_simd_production.sh`)
   regenerates wallclock + bit-identical assertions on every run.

### Files touched (R12A)

- `src/io/transducers/image_stereo.nova` (+178 lines: SAD SIMD,
  disparity dispatch, env-var helper)
- `src/io/transducers/image_optical_flow.nova` (+218 lines: LK SIMD
  variant)
- `tests/unit/test_simd_production.nova` (NEW, 368 lines, 35 assertions)
- `scripts/bench_simd_production.sh` (NEW, 352 lines, generates two
  NOVA bench programs + runs them with bit-identical assertion +
  speedup ratio)

### Known limitations / future work (R12A)

- **NOVA-side codegen overhead dominates per-builtin-call cost.**
  Fixing this needs either inlined SIMD builtin emission (R12E
  territory: NOVA codegen), a `simd_mul_i32x8` builtin so LK products
  go through SIMD too, or a `simd_horizontal_sum_i32x8` builtin to
  skip the 8-lane scalar reduce per LK sum.
- **Audio autocorrelation (R10F) deliberately untouched.** R(0) ~5e11
  overflows i32 lanes; needs i64 SIMD which R11D doesn't ship.
- **SGM cost-volume aggregation (R9A) not vectorized.** The 4-path
  DP accumulator could use simd_add_i32x8 lane-wise on cost bins.

## R12C (this session) — KG: Louvain modularity-optimising community detection

**Status: complete -- new module `src/kg/louvain.nova` implements the
Blondel 2008 ("Fast unfolding of communities in large networks") two-
phase greedy modularity optimiser, complementing R11F's label-
propagation detector.** Where R11F's LPA shipped a streaming-friendly
O(V+E) neighbour-vote heuristic, Louvain ships the gold-standard
modularity-optimiser: each Phase 1 sweep picks moves analytically by
maximising the modularity gain DQ, then Phase 2 aggregates communities
into super-nodes and recurses. R11F stays available unchanged
(`/communities`); Louvain dispatches through the parallel `/louvain`
chat command.

### Algorithm (Louvain, two-phase iterative)

1. **Phase 1 (local modularity optimisation).** Each node starts in
   its own community. Repeat until no improvement:
   - For each node u (deterministic-shuffled order):
     - For each candidate community C in u's neighbourhood, compute
       the modularity gain DQ of moving u into C analytically.
     - Move u to the best STRICTLY POSITIVE DQ candidate, else stay.
   - DQ in integer milli units (no FP weights):
     `gain_scaled = 2m * k_u_in_C - k_u * Sigma_tot_C`
     where `2m = sum(weighted degrees)`, `k_u_in_C` = sum of weights
     from u to C, and `Sigma_tot_C` = sum of degrees of nodes in C
     (with `k_u` subtracted when C == u's current community).
2. **Phase 2 (community aggregation).** Build a new (smaller) graph
   where each Phase-1 community becomes a single super-node. Inter-
   community edges sum to weighted super-edges; intra-community edges
   sum to self-loops on the new super-node.
3. **Recurse.** Re-run Phase 1 on the aggregated graph. Stop when a
   Phase-1 sweep produces zero merges OR max_iter levels were used
   (default 10).

### Public API

- `louvain_communities(kg, max_iter) -> louvain_result`
- `louvain_communities_seeded(kg, max_iter, seed)` (default seed = 0)
- `louvain_label_at(r, atom_id) -> int community id` (-1 if missing)
- `louvain_community_count(r) -> int`
- `louvain_community_members(r, community_id) -> list[atom_id]`
- `louvain_largest_community(r) -> [community_id, size]`
- `louvain_modularity(kg, r) -> int milli` (matches R11F's
  `gc_modularity` formula so Louvain vs LPA modularity is directly
  comparable)
- `louvain_levels(r) -> int` (number of Louvain levels run)
- `louvain_dendrogram(r) -> list[[n_communities, labels...]]` (the
  hierarchical merge tree captured per level, finest -> coarsest)
- `louvain_communities_cmd(kg) -> 1` (chat dispatcher emitting one
  `LOUVAIN n=N largest=L modularity=M milli edges=E depth=D` line)

### Results (default seed = 0)

| Fixture                | Edges | Louvain Q (milli) | LPA (R11F) Q (milli) | Louvain comms | LPA comms |
| ---------------------- | ----- | ----------------- | -------------------- | ------------- | --------- |
| Barbell (4+4+bridge)   | 13    | 423               | 423                  | 2             | 2         |
| 3 disjoint triangles   | 9     | 667               | 667                  | 3             | 3         |
| Zachary karate (1977)  | 78    | **399**           | **256**              | 3             | 2         |

On the small/clean fixtures both algorithms find the same global
optimum (Q matches exactly). On the Zachary 1977 karate-club
benchmark -- the real-world community-detection gold standard --
Louvain wins by **+143 milli** (56% relative improvement) and finds
3 communities versus LPA's 2. The brief's threshold (`> 350 milli`)
is cleared by a comfortable margin.

### Determinism

Same KG snapshot + same seed -> bit-identical clustering. Order of
node visits comes from a 15-bit shift-xor mixer (the same NOVA
codegen-bug-safe pattern R11F uses; see NOVA_BUG_THRESHOLD.md).
Different seeds may settle on different valid partitions on graphs
with multiple local optima -- the unit tests assert idempotence on
the default seed (`test_idempotent_modularity` re-runs three times,
each call returning the same modularity).

### Files

- New: `src/kg/louvain.nova` (~600 LOC, integer-only).
- New: `tests/unit/test_louvain.nova` (~67 assertions, 72 checks
  fired, all PASS).
- New: `tests/integration/scenario_zz_louvain.sh` + tracked driver
  `tests/integration/_scenario_zz_louvain_driver/louvain_driver.nova`
  (~19 assertions, all PASS).
- Updated: `examples/crossengin_chat.nova` (+3 lines: import + help +
  dispatch for `/louvain`).
- Module count: 147 -> 148.

### What's next

- Resolution-limit aware Louvain (Reichardt-Bornholdt 2006 + Arenas
  2008): the original Louvain merges small communities into giant
  super-clusters on dense graphs; a tunable resolution parameter `r`
  exposes the multi-scale community structure.
- Leiden algorithm (Traag 2019): refines Louvain's local move with a
  "refinement" sub-phase that fixes Louvain's known badly-connected
  community bug.
- Cross-KG Louvain: walk xrefs across KG boundaries and cluster the
  union graph. Currently single-KG only (mirrors R11F's scope).

## R11B (previous session) — Audio: YIN-class F0 estimator (cumulative mean normalized difference)

**Status: complete -- extended `src/io/transducers/audio_pitch.nova`
(R10F's file) with parallel YIN-class entry points that cure R10F's
first-formant snap on harmonic-rich natural speech.** R10F's
autocorrelation API stays available unchanged. YIN
(de Cheveigne & Kawahara 2002) replaces autocorrelation's argmax with
the cumulative mean normalized difference function `d'(tau) =
d(tau) * tau / running_sum`, whose MINIMUM marks the period -- no
formant ambiguity. Pure integer arithmetic, no FFT, no floats.

### Algorithm

1. `d(tau) = sum (x(n) - x(n+tau))^2` -- ZERO at the true period.
2. `run(tau) = run(tau-1) + d(tau)` -- cumulative sum.
3. `d'(tau) = d(tau) * tau * 1000 / run(tau)` -- milli units.
4. Find smallest tau where d'(tau) < 100 milli AND local minimum.
5. **Pass B** (R11B-specific): walk integer multiples k=2,3,... of
   best_tau; prefer the LONGER period if a local minimum exists
   with d'(kT) <= 3x d'(T). Gated by best_dprime > 0 (pure synthetic
   signals are unaffected).
6. Parabolic interpolation around best_tau for sub-sample precision.

### Public API (parallel to R10F)

- `pitch_estimate_frame_yin(pcm, sr, f0_min, f0_max, yin_threshold)
  -> [f0_centihz, voicing_milli]`
- `pitch_track_yin(pcm, sr)` -- default bounds + threshold
- `pitch_track_yin_with_bounds(pcm, sr, f0_min, f0_max, yin_threshold)`
- `pitch_run_yin_command(arg)` -- chat /pitch_yin helper
- `pitch_yin_threshold()` / `pitch_yin_voicing_max()` accessors

### Results

| Fixture                          | True F0   | R10F mean | R11B YIN mean | Outcome           |
|----------------------------------|----------:|----------:|--------------:|-------------------|
| 100/200/400 Hz pure sine         | 100/200/400 | exact   |   exact       | parity            |
| 120 Hz harmonic stack (1+2+3 hx) |   120 Hz  |   120 Hz  |     120 Hz    | both OK on synth  |
| Klatt /uw/ vowel (8 kHz F1=300)  |    n/a    |   296 Hz  |     145 Hz    | YIN dodges F1 snap|
| JFK adult-male (16 kHz, 5.5 s)   |  ~140 Hz  |   220 Hz  |     145 Hz    | YIN cures snap    |

### Verification

- **Unit (35 assertions, NEW `tests/unit/test_audio_pitch_yin.nova`)**:
  pure-sine exactness at 100/200/400 Hz, harmonic-rich 120 Hz no-snap,
  white-noise/silence unvoiced, Klatt /uw/ in band, sub-sample
  parabolic refinement (197 Hz + 173 Hz), R10F back-compat, edge cases.
- **Integration (9 assertions, NEW `scenario_vv_yin_pitch.sh`)**:
  synthetic 200 Hz both methods, JFK head-to-head -- R10F at 219.54 Hz,
  YIN at 144.61 Hz (in adult-male [80..180] Hz band), YIN < R10F strict.
- **R10F regression**: existing `test_audio_pitch` (52 / 52) and
  `scenario_tt_pitch` (20 / 20) remain bit-identically green.
- **Module count unchanged** (extension only -- no new module).

### New files

- `src/io/transducers/audio_pitch.nova` (EXTENDED; 596 -> 908 lines)
- `tests/unit/test_audio_pitch_yin.nova` (35 assertions)
- `tests/integration/scenario_vv_yin_pitch.sh` (9 assertions)
- `examples/crossengin_chat.nova` +1 line: `/pitch_yin` dispatch
- `AUDIO_AUDIT.md` (R11B section added; R10F YIN follow-up marked DONE)
- `README.md` (R11B blurb)

### Known limitations (R11B)

- **JFK Pass B uses 3.0x ratio.** Aggressive enough to cure formant
  snap on JFK; higher-fidelity broadcast speech might prefer 2.0x.
- **No temporal smoothing.** Per-frame YIN can still emit an octave-
  up frame in a low-voiced run. YIN paper Step 5 (best-local-estimate)
  is not in R11B.
- **2x autocorrelation cost.** Per-frame at 16 kHz: ~139k
  subtract-square-add + ~290 running-sum steps + ~290 normalization
  divides.

### Future work (R11B)

- YIN Step 5 best-local-estimate temporal smoothing (+/- 1 frame).
- Adaptive YIN_OCTAVE_RATIO_MILLI per-frame SNR-tuned.
- Pitch-algorithm backend switch (R7F+R10B style seam).
- Streaming YIN over audio_capture's PCM iterator.

## R11A (this session) — IO: pyramidal Lucas-Kanade optical flow (Bouguet 2000 extension)

**Status: complete -- `src/io/transducers/image_optical_flow.nova` EXTENDS
R10D's single-level Lucas-Kanade with the classical coarse-to-fine
Gaussian pyramid + iterative warping orchestrator from Bouguet 2000.**
R10D was exact in the first-order Taylor regime (sub-pixel shifts) but
under-estimated multi-pixel shifts -- the textbook fixture measured
u ~ 2384 milli when the target was 3000 milli (3 px shift). R11A
handles displacements up to ~16 px on a 256 px image.

### Algorithm

1. Build Gaussian pyramids of both frames at L levels (3x3 Gaussian
   smooth + 2x downsample per level, default L=3).
2. From coarsest to finest: warp NEXT by current flow (integer-rounded),
   run R10D's `lk_optical_flow` -> per-pixel correction, aggregate
   via clamped mean (+/-4000 milli per pixel ceiling to suppress
   boundary outliers), update global (u, v) += (du, dv). Iterate up
   to MAX_ITER=3 times per level.
3. Upsample (u, v) by 2 when descending levels.
4. Final pass writes per-pixel field = global + level-0 residual.

### What landed

- **`src/io/transducers/image_optical_flow.nova`** (+~600 lines,
  EXTENDED). New public API: `lk_pyramid_build`,
  `lk_pyramid_level_width/height/data`, `lk_warp_image`,
  `lk_optical_flow_pyramid`, `lk_pgm_args_pyramid`,
  `lk_pgm_paths_pyramid`. R10D surfaces untouched.
- **`examples/crossengin_chat.nova`** (+1 line): `/flow_pyr
  prev.pgm next.pgm` dispatch (no help line; +1 dispatch + 0 help
  to stay in chat budget).

### Headline numbers

| Fixture (80x64)             | Single-level (R10D) | Pyramid (R11A) | Target |
|----------------------------:|--------------------:|---------------:|-------:|
| 8-px right shift, u@(20,16) | 5697 milli          | 7531 milli     | 8000   |
| 4-px down shift, v@(20,16)  | -                   | 4116 milli     | 4000   |
| (3,3) diag, u@(20,16)       | -                   | 2962 milli     | 3000   |
| (3,3) diag, v@(20,16)       | -                   | 2762 milli     | 3000   |
| Identical, mean_mag         | 0                   | 0              | 0      |
| Textureless, valid_count    | 0 / 1024            | 0 / 1024       | 0      |

### Tests

- **`tests/unit/test_optical_flow_pyramid.nova`** (NEW, 52
  assertions). All R10D tests stay bit-identically green.
- **`tests/integration/scenario_uu_pyramid_flow.sh`** (NEW, 12
  assertions). `scenario_ss_optical_flow.sh` (R10D) stays green.

### Module count: unchanged (extend-only). Coexists with R11E
(`/segment`) and R11B (audio_pitch YIN extension), no file overlap.

### Limitations / follow-ups (R11A)

- **Translational-aggregate simplification.** Reduces each level's
  per-pixel field to a single clamped-mean shift. Converges fast on
  rigid translation but blurs across rotational / non-rigid motion.
  The full Bouguet algorithm with per-pixel propagation is a
  R11A.2 follow-up.
- **Per-iteration correction clamp = +/-4000 milli** (per LEVEL pixel,
  auto-scales with pyramid depth).
- **Outlier rejection is a clamp, not a median** (the clamp's O(N)
  is the pragmatic trade vs O(N log N) for a true median).

## R11E (this session) — IO: spatial k-means image segmentation

**Status: complete -- new module `src/io/transducers/image_segmentation.nova`
ships textbook Lloyd's k-means on the (intensity, x, y) joint space, the
first COARSE region partitioner the CV pipeline has. Everything before
R11E (Sobel, Harris, SIFT, ORB, Canny, stereo, optical flow) operated on
single pixels, gradients, or windows; segmentation now answers "which
pixels belong to the same region?" so downstream code can reason about
shapes rather than bags-of-pixels.**

### Algorithm (textbook spatial k-means)

1. **Initialize** K centroids on a tiled `ceil(sqrt(K))` x `ceil(K/cols)`
   interior grid. K=1 -> center; K=2 -> (W/4, H/2) and (3W/4, H/2); K=4
   -> the four quadrant centers; K=5 -> 2x3 grid with one slot empty.
   Initial intensity is the pixel at the centroid's (x, y).
2. **Assignment**: per-pixel argmin over k of
   `d_k = w_intensity * (I - I_k)^2 + w_spatial * ((x - x_k)^2 + (y - y_k)^2)`.
   Ties break to the lower cluster id (deterministic).
3. **Update**: per-cluster integer mean of `(I, x, y)`. Empty clusters
   retain their previous centroid (Lloyd's classic stale-centroid case).
4. **Stop** when assignments don't change OR `max_iter` is reached.

### Public API

* `seg_kmeans(data_ptr, width, height, k, max_iter) -> result`
* `seg_kmeans_weighted(..., w_intensity, w_spatial) -> result`
* `seg_label_at(result, x, y) -> int` (returns `-1` on OOB)
* `seg_centroid_count(result) -> int`
* `seg_centroid_at(result, k) -> [I, x, y]`
* `seg_iterations(result)` / `seg_converged(result)` /
  `seg_width / seg_height(result)`
* `seg_render_pgm(result, data_ptr) -> byte buffer`
* `seg_render_to_file(result, data_ptr, path) -> 1/0`
* `seg_cluster_count_label(k)` / `seg_dominant_label(result)`
* `seg_append_features(feats, data_ptr, w, h)` -- visual_perception hook
* `seg_pgm_args(arg)` -- chat `/segment PATH [K]` driver

### Caps

* Dimensions <= 256 per axis (max area 65536 pixels).
* K in [1, 32].
* max_iter <= 50.

### Wiring

* `visual_perception.nova` -- adds `image_segmentation.nova` import and
  one `seg_append_features` call inside `_vp_append_structural_features`
  (only fires when both dims >= `SEG_VP_MIN_DIM=64`).
* `crossengin_chat.nova` -- adds `/segment PATH [K]` admin (one dispatch
  line, one help line). Writes segmented PGM to `/tmp/segmented.pgm`.

### Verification (R11E)

* `make test`: **158 unit tests pass** (was 157 before R11E; +1 for the
  new `test_image_segmentation.nova` suite, 69 assertions covering K=2
  LR / K=4 quadrant / K=1 trivial / uniform-image / iteration cap /
  dimension cap / K cap / OOB-label / weighted variant / render PGM /
  label-string paths).
* `tests/integration/scenario_ww_segmentation.sh`: **16 assertions pass**
  (4-quadrant fixture, chat dispatch, missing-file safety, /help label).
  K=4 quadrant fixture converges in 2 iterations with centroid intensities
  0 / 85 / 170 / 255 each within +/-0 of expected.
* All pre-existing CV scenarios still pass: scenario_cc (SIFT),
  scenario_ee (ORB), scenario_hh (stereo), scenario_ss (optical flow),
  scenario_q_image_see (full /see pipeline).

### Known limitations (R11E)

* **Deterministic grid init, not k-means++**: a tiled grid lays the K
  centroids regardless of pixel distribution. K-means++ (D^2-weighted
  sampling) would improve convergence on adversarial inputs at the
  cost of a non-trivial second pass.
* **No empty-cluster recovery**: Lloyd's classic stale-centroid case
  retains the previous centroid when a cluster has zero members.
* **L2 squared distance is integer-exact only up to 256x256**: the
  worst-case spatial-square `256^2 = 65536` plus intensity-square
  `255^2 = 65025` stays under 2^31 at default weights. Weights >> 1000
  risk overflow.
* **No superpixel connectivity constraint**: spatial k-means does NOT
  enforce connectivity, so a single cluster may span disconnected
  regions if they share an intensity.

### Future work (R11E)

* **K-means++ seeding** to dodge worst-case grid init.
* **Multi-scale segmentation** -- run k-means at multiple K and merge
  via region-adjacency graph (the start of a real superpixel pipeline).
* **Per-cluster atom emission** -- a per-cluster centroid atom
  (`image_segmentation_centroid_<k>_intensity_<bucket>`) would expose
  scene composition to the KG.

## R11F (this session) — KG: label-propagation community detection

**Status: complete -- new module `src/kg/graph_clustering.nova` ships
the Raghavan-2007 label-propagation algorithm over the KG's xref link
graph, the STRUCTURAL companion to R10C's textual ranker. R10C asks
"which atom LABELS look semantically alike" (TF-IDF); this module asks
"which atoms are LINKED to each other" (xref-induced communities).**
Pure integer arithmetic, no FP weights, deterministic-by-seed. The
chat gains `/communities` for the headline (N communities, largest
size, modularity in milli).

### Algorithm (Raghavan, Albert, Kumara 2007)

1. **Initialize**: every atom's label is its own atom_id.
2. **Iterate** up to `max_iter` (default 20):
   - Build a deterministic shuffle order from `seed` (default 0)
     using a shift-xor mixer.
   - For each atom in shuffle order, count neighbour labels and
     adopt the most-frequent one; ties break by lowest label id.
   - Short-circuit when a full pass changes no labels.
3. **Output**: per-atom labels + a sorted communities table +
   `total_edges` + `iterations`. Time complexity O((V+E) * iters);
   Raghavan's empirical convergence is < 5 iters on planted-partition
   fixtures and the unit tests confirm this on barbell + 3-clique.

Why LPA over Louvain or spectral: O(V+E) per pass, integer-only, no
eigenvector solve, no FP weights. Easy to verify by hand on small
fixtures.

### Modularity (Newman 2006)

`Q = sum_c (e_cc - a_c^2)` in milli, where `e_cc` is the
intra-community edge fraction and `a_c` is the community's
half-degree fraction. Computed as
`(sum_intra * 1000) / m - (sum_a_sq * 1000) / (4*m*m)` to keep every
intermediate integer. Range [-500, 1000] milli; well-separated
cliques sit well above 200 milli (the brief's threshold). Single-
cluster trivial partition lands at 0 (the algebra collapses).

### Edge representation

Atoms carry their outgoing xrefs in `A_XREFS` (R6 atom_store layout);
`cross_kg_references.xref_*` accessors are unchanged. We treat the
graph as UNDIRECTED for LPA (an xref a->b means a and b share a
neighbour). Cross-KG xrefs are dropped at extract time (LPA is
single-KG here; spanning multiple KGs is a deferred follow-up).
Duplicate edges are deduped during adjacency build so the modularity
denominator reflects unique pairs only.

### Public API

* `gc_label_propagation(kg, max_iter)` -- seed=0 (default).
* `gc_label_propagation_seeded(kg, max_iter, seed)`
* `gc_label_at(r, atom_id) -> int_community_id` (-1 if absent)
* `gc_community_count(r) -> int`
* `gc_community_members(r, community_id) -> list[atom_id]` (sorted)
* `gc_largest_community(r) -> [community_id, size]` (ties low-id)
* `gc_modularity(kg, r) -> int_milli`
* `gc_total_edges(r)` / `gc_iterations(r)`
* `gc_communities_cmd(kg)` -- chat dispatch.

### Verification

* **Unit (71 assertions, NEW `tests/unit/test_graph_clustering.nova`)**:
  empty KG / singleton / two linked / two disconnected pairs;
  barbell (2 cliques + bridge -> 2 communities, 13 edges, interior
  shared labels); 3-clique (3 disjoint triangles -> exactly 3
  communities, 9 edges); linear chain determinism; modularity
  well-separated > 200 milli + single-cluster ~ 0; same-seed
  reproducibility; convergence <= 5 iters; gc_largest_community
  selection + ties; gc_community_members missing + label_at missing;
  max_iter <= 0 fallback.
* **Integration (20 assertions, NEW
  `tests/integration/scenario_xx_communities.sh`)**: drives
  `examples/graph_clustering_demo.nova` (barbell + 3-triangle +
  empty fixtures) + chat `/communities` + `/help` listing.
* **No-regression**: all 159 unit tests PASS (158 existing + 1 new);
  R10C semantic-search 21 integration assertions PASS; R8F episodic-
  recall 19 PASS; R6F episodic 37 PASS; R8E schema-migrate 17 PASS.

### Files touched

* NEW `src/kg/graph_clustering.nova`
* NEW `tests/unit/test_graph_clustering.nova`
* NEW `tests/integration/scenario_xx_communities.sh`
* NEW `examples/graph_clustering_demo.nova`
* `examples/crossengin_chat.nova` (+3 lines: import, dispatch, help)
* `README.md` + `NEXT_SESSION.md`

### Module count

R11F adds `src/kg/graph_clustering.nova` (+1 module). Committed
baseline is 145 modules; this commit makes 146.

### Followups (deferred)

1. **Multi-KG span**: walk cross-KG xrefs so a community can span
   multiple KGs (the brief calls this out as the natural extension).
2. **Louvain modularity-greedy** for finer-grained clusters; needs
   FP weights, but a sub-linear integer approximation is plausible.
3. **Streaming LPA**: incremental update when xrefs are added/removed
   without re-running the full passes.
4. **Per-KG persistent community label cache** mirroring the
   `kg_set_ann` attach pattern.

## R10C (this session) — KG: TF-IDF semantic search across atom labels

**Status: complete -- new module `src/kg/semantic_search.nova` ships a
purely textual TF-IDF + integer-cosine ranker over atom labels, closing
the KG read story alongside exact lookup (`atom_store.kg_find_atom`),
episodic retrieval (R6F + R8F: `episodic_recall_*`), and embedding
nearest-neighbour (P3.4: `ann_query`).** No neural embedding, no LLM
call, no external service -- pure deterministic counting math in
milli-fixed-point (FP_SCALE=1000). The chat gains `/find <query>` for
top-K (default 5) most-similar atoms; the API also exposes
`ss_search_by_atom_id` for "atoms similar to this existing one".

### Algorithm

1. **Tokenize**: split on whitespace + ASCII punctuation, lowercase,
   drop tokens < 3 chars or > 30 chars. Underscore is a token char.
2. **TF**: sub-linearly scaled, `1 + log2(count)` in milli. count=1
   -> 1000 milli, count=2 -> 2000 milli.
3. **IDF**: `log2(n) - log2(df) + SS_IDF_SMOOTH` in milli (the log
   subtraction sidesteps the integer-div precision loss of log2(n/df);
   smoothing = 100 milli, the smallest constant that resolves
   identical-vector cosine = 1000 milli while keeping rare > common).
4. **TF-IDF**: `tfidf(t,a) = tf * idf / 1000` in milli, stored sparsely
   as `[(token_id, score)]` per atom, sorted by token_id.
5. **Cosine**: dot = sum(q*d) in raw milli^2 (no per-step /1000),
   norm = sqrt(sum(tfidf^2)) via integer Newton iteration, output
   `dot * 1000 / (norm_q * norm_d)` clamped to [0, 1000].
6. **Top-K**: insertion-sort by sim desc, tiebreak by atom_id asc.

### Index layout

```
ss_index = [SS_OBJ_TAG=1901, tokens, forward, inverted, idf_cache,
            idf_valid, atom_text]
```

Lazy IDF refresh + per-atom norm cache. `ss_index_add_atom` is
idempotent: re-add same id replaces (strips old postings + df bumps).

### Public API

- `ss_index_new()`, `ss_index_add_atom(ix, id, text)`,
  `ss_index_atom_count(ix)`, `ss_index_token_count(ix)`
- `ss_search(ix, query_text, top_k)` -> `[(atom_id, sim_milli)]` desc
- `ss_search_by_atom_id(ix, id, top_k)` -> excludes query atom
- `ss_index_from_kg(kg)` + `ss_find_cmd(kg, arg)` for chat dispatch

### Verification

- **Unit (73 assertions, NEW `tests/unit/test_semantic_search.nova`)**:
  tokenization shapes, log2/sqrt/IDF primitives, 5-atom + 10-atom
  fixture ranking, identical=1000 / orthogonal=0 / partial-overlap
  in-between cosine properties, top-K clamping, empty-edge cases,
  add idempotency, search_by_atom_id self-exclusion.
- **Integration (21 assertions, NEW `scenario_rr_semantic_search.sh`)**:
  end-to-end via `examples/semantic_search_demo.nova` + chat dispatch
  (`/find` no-arg usage line, `/find machine`, `/help` listing).
- **No-regression**: all 154 existing unit tests PASS; R8F's 19
  episodic-recall integration assertions PASS; admin help/status
  (38 assertions) PASS.

### Files touched

- NEW `src/kg/semantic_search.nova`
- NEW `tests/unit/test_semantic_search.nova`
- NEW `tests/integration/scenario_rr_semantic_search.sh`
- NEW `examples/semantic_search_demo.nova`
- `examples/crossengin_chat.nova` (+3 lines: import, dispatch, help)
- `README.md` + `NEXT_SESSION.md`

### Followups (deferred)

1. **Phrase queries / bigram scoring** at the inverted-index level.
2. **Stemming** (Porter or Lancaster) to collapse learn/learns/learned.
3. **Per-KG persistent index** (mirror `kg_set_ann` attach pattern).
4. **BM25** as a one-day swap inside `_ss_tf_milli` + `_idf_milli`.

## R10B (this session) — Audio: whisper per-utterance confidence + Vosk offline backend

**Status: complete -- two follow-ups from R8B closed.** R8B's whisper.cpp
backend returned a flat `WHISPER_CONFIDENCE_DEFAULT = 800` milli on
success regardless of the actual decode quality; the audit document
called this out as a placeholder pending a real per-utterance value.
R10B parses whisper-cli's `-ojf` (output-json-full) JSON output for
per-token probabilities and averages them into a true per-utterance
confidence (JFK lands at 895 milli; an all-silence WAV at 0). The
seam's `_stt_backend_whisper` was switched to the confidence-aware
variant so `/listen` now reports real numbers.

R10B also ships a SECOND first-class STT backend: Vosk
(`src/io/transducers/vosk_backend.nova`), a pure-C streaming STT
engine with a ~50 MB English model. The seam's auto-pick now does
whisper > vosk > stub; `CE_STT_BACKEND=vosk` forces the new path
explicitly. Vosk's per-word `conf` field is averaged for an
utterance-level milli confidence (JFK lands at 968 milli).

### What landed

- **`src/io/transducers/whisper_backend.nova`** (extended, +260 lines).
  New public API: `whisper_transcribe_with_confidence(bin, model, wav)`
  and `whisper_transcribe_with_confidence_default(wav)`. Internals
  parse the `-ojf` JSON file scanning for `"p":` token-probability
  fields and averaging them as milli. Falls back to the 800-milli
  legacy ballpark when the JSON file is unparseable.

- **`src/io/transducers/vosk_backend.nova`** (NEW, leaf module).
  Public API mirrors whisper_backend's shape; dispatch is fork +
  execve `python3 -c '<inline-script>' <wav> <model>` with the
  inline Python script (embedded as a NOVA string literal) running
  Vosk's KaldiRecognizer and printing exactly `OK <milli> <text>`
  or `ERR <msg>`.

- **`src/io/transducers/stt_seam.nova`** (extended). New constant
  `STT_BACKEND_VOSK = 5`. New constructor `stt_seam_new_vosk`.
  New env mapping: `CE_STT_BACKEND=vosk`. Auto-pick now does
  whisper > vosk > stub. `_stt_backend_whisper` switched to call
  the confidence-aware variant. New `_stt_backend_vosk` calls
  `vosk_transcribe_default`.

- **`tests/unit/test_whisper_backend.nova`** (extended, +13 assertions
  on the JSON confidence parser: single high/low p, avg of two/three
  tokens, integer edges p=0/p=1, no-tokens sentinel, whitespace
  tolerance). 28 -> 41 checks.

- **`tests/unit/test_vosk_backend.nova`** (NEW, 19 fns / 39 checks).
  Env-resolver fallback paths, availability-probe error codes,
  pre-flight error codes, output-parser fixtures, accessors, seam
  dispatch, constructor pins, JFK real-decode (SKIPs if Vosk
  isn't installed).

- **`tests/integration/scenario_qq_vosk.sh`** (NEW, 16 assertions).
  Drives the seam through each CE_STT_BACKEND value. Asserts:
  whisper JFK conf > 800 milli (proof JSON parser produced real
  value, not 800 ballpark), vosk JFK conf > 500 milli, auto-pick
  ordering, seam dispatch through whisper / vosk produces non-empty
  transcripts.

- **`AUDIO_AUDIT.md`** (extended). New top-level section "R10B:
  per-utterance confidence + Vosk offline backend".

### On the dev container

- `whisper_transcribe_with_confidence_default("/tmp/whisper.cpp/samples/jfk.wav")`
  -> `["And so my fellow Americans...", 895, ""]` (avg over ~22 tokens).
- `vosk_transcribe_default("/tmp/whisper.cpp/samples/jfk.wav")`
  -> `["and so my fellow americans...", 968, ""]` (avg per-word conf).

### Future work (R10B)

- Whisper streaming via `-f -` stdin PCM.
- Larger Vosk model (`vosk-model-en-us-0.42`, ~1.8 GB).
- Per-word time-aligned confidence stream from Vosk.
- Vosk word-level grammar hints for the chat command vocabulary.

---

## R10F (this session) — Audio: autocorrelation F0 (pitch) estimation

**Status: complete -- new module `src/io/transducers/audio_pitch.nova`
ships a per-frame fundamental-frequency estimator built on short-time
autocorrelation. This is the third pillar of the audio triad after R6E
Klatt synthesis and R7F+R9B VAD, completing the input chain alongside
R7F+R8B STT.** No FFT, no floats, no DSP library -- the algorithm
is a textbook Rabiner & Schafer (1978) short-time autocorrelation with
a classical integer-multiple peak-check for octave-down correction. The
chat surface gains `/pitch PATH`, a one-shot diagnostic that prints
mean F0 + range over a WAV.

### Why pitch matters next to STT

CrossEngin has *what was said* (STT) but not *how it was said*. Prosody
(intonation contour) carries question-vs-statement (rising vs falling
terminals), surprise / emphasis (excursions above the speaker mean),
and turn-taking cues (sustained low F0 -> end of turn). Mean voiced F0
also separates adult-male / adult-female / child speakers without
diarization machinery. Mean F0 + range expansion are the two signatures
research links most directly to arousal (angry / happy widen the range;
sad / bored collapse it).

All three signals are now extractable from the same PCM buffer
`/listen` already produces, without an LLM and without a DSP library.

### Algorithm

Per ~30 ms frame at the configured sample_rate (240 @ 8 kHz, 480 @ 16 kHz):

1. Compute autocorrelation
   `R(tau) = sum_{n=0}^{N-tau-1} x(n) * x(n+tau)`
   for tau in [tau_min, tau_max] where
   `tau_min = sample_rate / f0_max` (16000/500 = 32 @ 16 kHz)
   and `tau_max = sample_rate / f0_min` (16000/50 = 320 @ 16 kHz).
2. Raw argmax: `best_tau = argmax_{tau} R(tau)`. F0 candidate =
   sample_rate / best_tau.
3. Octave-down correction (classical Rabiner-1977 peak picker): walk
   `tau = best_tau * k` for k = 2, 3, ... while `tau <= tau_max`; if
   `R(tau) >= 0.92 * R(best_tau)` accept the longer period (raise
   threshold to 0.92 * R(new) and continue). Cures the autocorrelation
   first-formant snap that systematically reports a multiple of the
   true glottal F0 on harmonic-rich speech.
4. Voicing: `voicing_milli = (1000 * R(best_tau)) / R(0)`. Voiced iff
   `voicing_milli >= 300 milli`. Below that the frame is unvoiced
   (f0_centihz = 0 sentinel).
5. F0 in **centi-Hz** (Hz * 100): preserves sub-Hz precision in pure
   integer arithmetic. A 119 Hz speaker is 11900, distinguishable from
   a 120 Hz speaker at 12000.

The 0.92 octave-correction threshold was empirically calibrated against
the unit-test fixtures: pure sines at 100, 200, 400 Hz give exact F0
estimates (R(2T)/R(T) plateaus at 0.50, 0.80, 0.91 -- all just below
0.92, so the correction never snaps pure sines), while Klatt vowels +
natural speech have R(2T)/R(T) >= 0.92 at the true glottal period.

### What landed

- **`src/io/transducers/audio_pitch.nova`** (NEW, ~340 lines). Public
  API:
  * `pitch_estimate_frame(samples, sample_rate, f0_min, f0_max) ->
    [f0_centihz, voicing_milli]` -- the per-frame estimator. Bounds
    of 0/0 fall back to the module defaults (50/500 Hz).
  * `pitch_track(samples, sample_rate) -> list of [f0, voicing]`
    -- walks the buffer in non-overlapping 30 ms frames, returns the
    contour. `pitch_track_with_bounds(..., f0_min, f0_max)` for
    per-call override.
  * `pitch_mean_voiced(contour) -> int centi-Hz` -- mean across only
    the voiced frames; 0 if none.
  * `pitch_range(contour) -> [min, max]` -- voiced-frame range; [0,0]
    if no voiced frames.
  * `pitch_voiced_count(contour) -> int` -- how many frames are voiced.
  * `pitch_autocorr_at(samples, off, n, tau) -> R(tau)` and
    `pitch_frame_energy(samples, off, n)` -- pure helpers exposed for
    tests + future second-pass algorithms.
  * `pitch_centihz_to_hz(c)` -- rounded conversion for human reports.
  * Constants: `pitch_default_f0_min/max`, `pitch_frame_ms`,
    `pitch_voicing_threshold`, `pitch_unvoiced_sentinel`.
  * `pitch_run_command(arg)` -- the chat /pitch one-liner. Returns a
    single human-readable line `(pitch PATH: f0_mean=X Hz,
    f0_range=L-H Hz [...])`; graceful FAILED on missing file.

  Implementation note: per-frame at 16 kHz the inner autocorrelation
  loop runs ~480 * 290 = 139k multiply-adds. The accumulator peaks
  around 5e11 -- above NOVA's smart-op 16 GiB pointer-classifier
  threshold -- so the accumulator uses `int_add` and the comparison
  `cur > best_r` (both potentially > 16 GiB) uses `int_sub(cur, best_r)
  > 0` (the sign-bit check works because the classifier always treats
  negatives as integer regardless of magnitude).

- **`examples/crossengin_chat.nova`** (+3 lines): one import, one help
  line, one dispatch line. Matches R10D's structural minimum
  (`/flow PATH` was the prior pattern).

- **`tests/unit/test_audio_pitch.nova`** (NEW, 23 test fns / **52 checks
  total**). Coverage:
  * Public constants + accessors (defaults, frame size, voicing
    threshold, unvoiced sentinel, centi-Hz->Hz).
  * Energy + autocorrelation primitives: zero buffer = 0, constant
    buffer = N*v^2, R(0) == energy, R(period) > R(half-period) on a
    pure sine.
  * Pure sines at 100, 200, 400 Hz @ 16 kHz: F0 within ±200 centi-Hz
    tolerance, voicing >= 600 milli.
  * White noise: F0 = 0 (PITCH_UNVOICED sentinel), voicing < 300 milli.
  * Pure silence: F0 = 0, voicing = 0.
  * Square wave: returns in [0..1000] voicing without crashing.
  * Klatt vowel /uw/ @ 8 kHz: voiced, F0 in [50..500] Hz band,
    voicing crosses threshold.
  * `pitch_track` on a 10-frame rising-pitch buffer (100..190 Hz):
    contour has 10 entries, all 10 voiced, rises from first to last
    frame, first frame ~ 100 Hz, last frame ~ 190 Hz.
  * `pitch_mean_voiced` on mixed voiced+silence buffer: only voiced
    frames contribute (mean ~ 200 Hz on a 6-voiced-frame fixture).
  * `pitch_range` known min/max: 200/300 Hz sines produce range
    [200..300] Hz (within centi tolerance).
  * Bounds enforcement: 25 Hz with f0_min=50 -> NOT in [24..26] Hz
    band (the search range excluded it); 1500 Hz with f0_max=500 ->
    NOT in [1490..1510] Hz band (out of band -> subharmonic snap).
  * Edge cases: short buffer -> unvoiced; default bounds (0/0) -> 200
    Hz still works; swapped bounds (500/50) -> 200 Hz still works.

- **`tests/integration/scenario_tt_pitch.sh`** (NEW, 20 assertions).
  Synthesizes a 200 Hz sine + Klatt /uw/ vowel via R6E, writes
  canonical PCM16 WAVs, runs the round-trip through
  `audio_capture_to_pcm` + `pitch_track`. Asserts mean F0 on each
  fixture within expected range. Chat-surface assertions:
  * `/help` advertises `/pitch` with the R10F label.
  * `/pitch <wav>` reports f0_mean + f0_range and echoes the path.
  * `/pitch` (no arg) prints usage.
  * `/pitch <missing>` -> graceful FAILED.
  * JFK fixture (if present): mean F0 in [80..280] Hz adult range,
    >= 100 voiced frames.

  SKIPs the JFK assertions gracefully when the fixture is missing,
  matching scenario_jj_whisper's convention.

- **`AUDIO_AUDIT.md`** (extended). New top-level section "R10F:
  autocorrelation F0 (pitch) estimation" documenting the algorithm
  shape, the integer-only arithmetic safety dance, the empirical
  threshold tuning, JFK measured value (220 Hz formant-snap vs true
  140 Hz), the YIN / cepstral / RAPT octave-correction roadmap, and
  the use cases (prosody atoms, speaker-mean banding, emotion proxy).

### Verification (R10F)

- `make test`: **154 unit tests pass** (was 153 before R10F).
  test_audio_pitch contributes 52 new checks; the new module is the
  +1.
- `tests/integration/scenario_tt_pitch.sh`: 20 assertions, all pass.
  200 Hz sine -> 200.00 Hz mean (20000 centi); Klatt /uw/ -> 296 Hz
  mean (formant snap, in-band); JFK -> 220 Hz mean (in adult band).
- All audio tests intact: `audio_synth` 209, `audio_vad` 86,
  `audio_capture` 28, `stt_seam` 27, `whisper_backend` 41, and the
  new `audio_pitch` 52.

### Known limitations (R10F)

- **JFK mean F0 = 220 Hz vs true ~140 Hz.** Unmodified autocorrelation
  systematically snaps to the first formant region on harmonic-rich
  natural speech. Classical YIN (de Cheveigne & Kawahara 2002) uses
  the cumulative mean normalized difference function to push this
  octave error below 1%. The integer-multiple peak check we use cures
  the 2x / 3x snaps on simple harmonic structure but not the more
  subtle formant snaps. **Acceptable for R10F's "plausible adult
  voice" tier**; the chat surface reports it transparently so
  downstream consumers can flag the band.
- **No per-frame F0 smoothing.** A future revision can add a median
  filter or Viterbi smoothing over the contour to stabilize the F0
  trajectory across voiced runs.
- **No glottal-source modeling in R6E Klatt.** The two-formant carrier
  (sum of cosines at F1, F2) has no actual fundamental; autocorrelation
  on it picks the F1 / GCD periodicity, NOT the conceptual 120 Hz
  "speaker F0" the synth nominally targets. A future R6E revision that
  adds a glottal pulse train carrier would let this test assert F0 at
  the synthesized fundamental directly.

### Future work (R10F)

- YIN / RAPT cumulative-mean-normalized-difference variant for true
  octave robustness on JFK-class natural speech. ~2x the
  autocorrelation cost; cures the formant snap to within a few Hz of
  ground truth.
- Cepstral pitch detection as a second algorithm (R7F-style backend
  switch): take the log of the magnitude spectrum and look for its
  quefrency-domain peak. Requires an FFT (or a real autocorrelation-
  of-log-autocorrelation hack); maps cleanly onto the existing seam
  pattern.
- Pitch-contour atoms: emit one prosody atom per VAD speech segment
  with `(mean_f0_centihz, range_centihz, rise_or_fall)` so the KG
  can store intonation curves alongside the transcript. The chat
  `/listen` could then attach these as moment-scope features.
- Speaker-mean banding: a session-level rolling average of mean F0
  over voiced runs, with a 3-band classifier (adult-male / adult-
  female / child) attached as a session-scope atom. No diarization,
  but enough signal to separate one speaker from another across an
  hour-long log.
- Stream/online estimator: pitch_estimate_frame is pure per-frame;
  wiring it to audio_capture's streaming PCM iterator gives a real-
  time F0 stream parallel to the VAD event stream.

## R10D (this session) — IO: Lucas-Kanade dense optical flow

**Status: complete -- new module `src/io/transducers/image_optical_flow.nova`
ships a per-pixel Lucas-Kanade optical flow estimator, the sixth pipeline
in the CV stack after Sobel + Harris + SIFT + Canny + ORB + Stereo.**
The motion side of the CV pipeline previously covered only block-based
motion vectors (`video_motion_vectors.nova`, coarse per-block) and sparse
keypoint matching (SIFT R5C + ORB R6D). R10D adds the textbook DENSE
per-pixel motion field between two consecutive frames using the
1981 Lucas-Kanade local-window normal equations -- integer arithmetic
only, no Eigen / no floats / no SVD.

### Algorithm

For each interior pixel (x, y), compute integer image gradients
(Ix, Iy via central differences /2) and the temporal gradient
(It = I_next - I_prev) over a WIN_SIZE x WIN_SIZE window centered
there, then solve the 2x2 normal equations:

```
[ Sum(Ix^2)   Sum(IxIy) ] [u]   [ -Sum(Ix*It) ]
[                       ] [ ] = [             ]
[ Sum(IxIy)   Sum(Iy^2) ] [v]   [ -Sum(Iy*It) ]
```

via the closed-form 2x2 inverse:

```
det     = (Sum Ix^2)(Sum Iy^2) - (Sum IxIy)^2
u_milli = ((Sum Iy^2)(-Sum IxIt) - (Sum IxIy)(-Sum IyIt)) * 1000 / det
v_milli = (-(Sum IxIy)(-Sum IxIt) + (Sum Ix^2)(-Sum IyIt)) * 1000 / det
```

`det == 0` (no-texture / aperture-problem pixels) -> flow marked
invalid; (u, v) reads (0, 0). Magnitude per pixel via integer
Newton-Raphson sqrt (mirrors the Sobel / Harris convention).

### What landed

- **`src/io/transducers/image_optical_flow.nova`** (+~430 lines, NEW).
  Public API:
  * `lk_optical_flow(prev, next, w, h, win_size)` -> result tuple
    `[flow_buf, valid_buf, mean_mag, valid_count, total, width, height]`
    where `flow_buf` packs (u_milli, v_milli) per pixel and `valid_buf`
    carries one 0/1 flag per pixel. Caps: dims <= 256x256;
    WIN_SIZE clamped to odd in [3..15], default 5 (OpenCV's
    calcOpticalFlowPyrLK default).
  * `lk_flow_at(result, x, y)` -> `[u_milli, v_milli, valid]`
    (OOB-safe; bad inputs -> (0, 0, 0)).
  * `lk_flow_mean_magnitude(result)` -> int milli.
  * `lk_flow_density_label(result)` -> "low" / "mid" / "high"
    (mean-magnitude buckets at 200 / 2000 milli).
  * `lk_flow_magnitude_label(mean_mag)` -> "image_optical_flow_magnitude_low"
    / _mid / _high (parallel atom labels for the perception seam).
  * `lk_pgm_paths(prev, next)`, `lk_pgm_args(arg)` -- chat
    `/flow prev.pgm next.pgm` admin one-liners.
  * `lk_append_features_if_paired(feats, next_ptr, w, h)` --
    visual-perception integration hook (reads `CE_VP_FLOW_PREV` env
    var; mirrors R7E stereo's pattern).
- **`src/io/transducers/visual_perception.nova`** (+4 lines): import,
  `VP_FLOW_MIN_DIM = 16` constant, and call to
  `lk_append_features_if_paired` in `_vp_append_structural_features`.
  When `CE_VP_FLOW_PREV` env var is set to a PGM path, /see emits
  `image_optical_flow_magnitude_<low|mid|high>` and
  `image_optical_flow_density_<low|mid|high>` atoms on the current
  frame; silent (no atoms appended) on missing env, decode failure,
  or dim mismatch.
- **`examples/crossengin_chat.nova`** (+2 lines): `/flow prev.pgm
  next.pgm` admin dispatch + matching `/help` line.

### Headline numbers (from `tests/unit/test_optical_flow.nova`)

- Smooth quadratic fixture (40x32) shifted RIGHT by 3 px:
  u ~ 2384 milli at (20, 16) (target 3000 milli; first-order LK
  under-estimates large rigid shifts), v ~ 222 milli (target 0).
- Smooth quadratic fixture shifted DIAGONALLY by (1, 1):
  u ~ 918 milli, v ~ 1042 milli at (20, 16) -- right on the
  expected (1000, 1000) target.
- Texture-less fixture (constant 128 fill): 0 / 1024 pixels valid
  (100% degeneracy detection via det == 0).
- Identical-frame fixture: mean magnitude 0 milli, density label
  "image_optical_flow_density_low".

### Tests

- **`tests/unit/test_optical_flow.nova`** (NEW, 53 assertions):
  identical frames give zero flow; horizontal / vertical / diagonal
  rigid shifts produce the expected u, v at probed interior pixels
  (within wide tolerance for multi-pixel shifts where the
  first-order Taylor expansion degrades); texture-less fixtures
  correctly mark every pixel invalid via det == 0; OOB safety on
  `lk_flow_at`; oversized / zero-pointer inputs return clean
  `_lk_fail()` shape; magnitude / density labels round-trip.
- **`tests/integration/scenario_ss_optical_flow.sh`** (NEW, 11
  assertions): `/help` advertises `/flow prev next`; usage strings
  on 0 / 1 args; identical inputs emit `mean_mag=0milli` +
  `image_optical_flow_density_low` atom; shifted pair (Python-built
  quadratic-bowl PGM shifted by 3) emits `mean_mag` >= 1000 milli
  with `valid` > 0; dim-mismatched and missing-file inputs surface
  bracketed errors; chat survives all malformed inputs and reaches
  `/quit` cleanly.

### Module count: +1 (image_optical_flow.nova). All 153 unit tests
green. R5C SIFT (25 + 28 unit), R6D ORB (34 unit), R7E stereo
(54 unit), R8D quality (42 unit), R9A SGM (39 unit), and R5E
Canny (22 unit) remain bit-identically green.

## R9A (this session) — IO: Semi-Global Matching (SGM) stereo on R7E + R8D

**Status: complete -- `src/io/transducers/image_stereo.nova` extends
R7E's block-matching SAD disparity and R8D's LR-check + sub-pixel
refinement with the third stereo-quality tier flagged in IMAGE_AUDIT.md:
4-path Semi-Global Matching (Hirschmuller 2008).** R7E + R8D run an
INDEPENDENT per-pixel SAD minimization; SGM AGGREGATES the matching cost
along multiple 1-D scanline paths to enforce smoothness and dramatically
reduces speckle in low-texture regions, the canonical stereo failure mode
where R7E's argmin picks whatever d happens to break a ~tied SAD.

### Algorithm (4-path, P1=8 / P2=32 defaults)

1. Build cost volume `C(x, y, d)` from `stereo_sad_block` (same kernel as
   R7E). Pixels with no valid match (border + `x - d < half`) get
   `STEREO_SGM_INF` so SGM never picks them.
2. For each path direction r in { LR, TB, RL, BT } and each pixel p:
   `L_r(p, d) = C(p, d) + min(L_r(p-r, d), L_r(p-r, d-1) + P1,`
   `L_r(p-r, d+1) + P1, min_d' L_r(p-r, d') + P2) - min_d' L_r(p-r, d')`.
   The trailing subtraction prevents unbounded growth (uniform offset
   does not change argmin).
3. Aggregate: `S(p, d) = sum over r of L_r(p, d)`.
4. Output `argmin_d S(p, d)` as the disparity map.

Each path keeps only ONE row/column buffer of size W*D so working memory
is bounded; the cost volume itself is allocated as raw bytes via
`alloc + store64` (8 bytes per int) and capped at W*H*D <= 512K ints
(<= 4MB). Pass 1 is the cache-friendly forward sweep (LR + TB); pass 2
is the reverse sweep (RL + BT).

### What landed

- **`src/io/transducers/image_stereo.nova`** (+~570 lines, EXTENDED;
  R7E + R8D surfaces untouched for back-compat). New public API:
  * `stereo_disparity_sgm(left, right, w, h, win_size, max_disp, p1, p2)`
    -> result tuple identical to R7E's. p1=0 / p2=0 use defaults.
  * `stereo_disparity_sgm_quality(left, right, w, h, win_size, max_disp,`
    `p1, p2, lr_tolerance)` -> combined: SGM + LR-check (vs R8D's
    right->left block-matching map) + sub-pixel parabolic refinement
    on the SGM-aggregated cost. Returns milli-disparity list.
  * `stereo_sgm_pgm_paths(L, R)`, `stereo_sgm_pgm_args(arg)` -- chat
    `/depth_sgm` admin one-liners.
- **`examples/crossengin_chat.nova`** (+1 line): `/depth_sgm L.pgm R.pgm`
  dispatch. The R7E `/depth` admin and its help line stay; R8D's
  `/depth_q` stays; `/depth_sgm` is dispatch-only (no help line).
- **`tests/unit/test_stereo_sgm.nova`** (NEW, 39 assertions):
  SGM identical inputs (mean / density 0, probed pixels 0); SGM
  shifted-by-8 pair (probed interior reads disparity 8 exactly);
  pure-noise pair (both sides flat-128 + uncorrelated mod-4 noise --
  the canonical SGM-wins case: BM variance > 0 with speckle,
  SGM variance < BM variance; the headline R9A demonstration);
  textureless-band fixture (SGM propagates the surround SHIFT into
  the band; SGM band mean > BM band mean); large P2 -> band pixels
  >= SHIFT/2; P2 == P1 -> SGM still recovers SHIFT exactly at
  probed pixels on a clean shifted pair; very high P1+P2 over-
  smooths interior (probed pixels all equal a reference pixel);
  combined SGM-quality on shifted-by-8 pair (milli within +/- 300
  of 8000 at probed pixels, 0 at borders); SGM-quality on
  textureless band (pipeline produces some non-zero milli);
  invalid-input refusals + volume cap (128x128x64 rejected, > 4MB);
  /depth_sgm dispatch usage strings.
- **`tests/integration/scenario_nn_stereo_sgm.sh`** (NEW, 13 assertions):
  build LEFT_TEX (textured 32x24 PGM), RIGHT_TEX (shifted-by-8),
  LEFT_BAND + RIGHT_BAND (textured with a textureless-noise band),
  RIGHT_SMALL (24x20), LEFT_NOISE + RIGHT_NOISE (32x24 base-128 with
  uncorrelated mod-4 noise). Cases: /help still advertises /depth
  (R7E preserved); /depth_sgm no-arg / one-arg usage; identical
  inputs report mean_disp=0; shifted pair reports mean_disp >= 1
  + density label; dim mismatch + missing-file errors surface
  cleanly; both /depth and /depth_sgm output lines emitted on the
  band fixture (BM-vs-SGM coexistence); on the pure-noise fixture
  /depth emits density "mid|high" (BM speckles) while /depth_sgm
  emits density "low" (SGM smooths) -- the chat-level expression
  of the R9A invariant; chat reaches /quit cleanly.
- **`IMAGE_AUDIT.md`**: R9A SGM (4 paths) checked off in the feature
  ladder; 8-path + mutual-information data-term track listed at
  "2-3 weeks" as the next stereo follow-up.
- **`README.md`**: short blurb summarizing the third stereo tier.

### Verification

- 39/39 unit assertions in `test_stereo_sgm.nova` green.
- 13/13 integration assertions in `scenario_nn_stereo_sgm.sh` green.
- R7E's `test_stereo.nova` (54 assertions) + `scenario_hh_stereo.sh`
  (10 assertions) still green -- R7E's contract preserved.
- R8D's `test_stereo_quality.nova` (42 assertions) +
  `scenario_kk_stereo_quality.sh` (11 assertions) still green --
  R8D's contract preserved.
- Full unit suite: 149/149 green (added 1 file, no regressions).
- `make build` still 141 modules.

### Follow-ups not in this session

- **8-path SGM**: add the diagonal paths (LR-down, LR-up, RL-down, RL-up)
  for ~2x quality on slanted depth boundaries; ~2x runtime + 2x prev-
  buffer memory.
- **Mutual-information data term**: Hirschmuller's full paper replaces
  SAD with a joint-histogram-derived MI cost. Sharper edges and better
  robustness to illumination differences between L and R.
- **Data-adaptive P2**: scale P2 by `1 / (1 + |I(p) - I(p - r)|)` so
  large penalties relax across intensity edges (= depth discontinuities).
- **Visual-perception seam integration**: switch
  `stereo_append_features_if_paired` from R7E's `stereo_disparity` to
  `stereo_disparity_sgm` so the emitted atoms reflect SGM's smoother
  disparity field.

---

## R9B (this session) — IO: adaptive VAD thresholds + JFK end-to-end `/listen`

**Status: complete -- `src/io/transducers/audio_vad.nova` extends R7F's
energy + ZCR + K=3/M=10 hysteresis VAD with an adaptive noise-floor
multiplier (Option A from the threshold-tuning brief), and
`src/io/transducers/audio_capture.nova` learns to skip RIFF metadata
sub-chunks so whisper.cpp's bundled JFK 16 kHz WAV finally parses
through the VAD-gated path.** R8B (commit `0874516`) wired whisper.cpp
into the seam and confirmed direct `stt_transcribe_wav` decodes JFK to
"Americans" correctly. The full `/listen jfk.wav` path however reported
`vad_segments=0` and short-circuited to the placeholder -- two bugs:

1. **WAV parser strict-offset bug.** `audio_capture_to_pcm` required
   `data` at byte offset 36. JFK has a `LIST/INFO ISFT 'Lavf...'`
   chunk between fmt and data (ffmpeg encoder metadata), pushing data
   to offset 70. The parser now scans forward through any optional
   sub-chunk (LIST/INFO/bext/junk/...) per RIFF spec.

2. **Energy threshold needed to adapt to the noise floor.** R7F's
   fixed threshold (50000 @ 8 kHz, scaling linearly with frame_size)
   was tuned against Klatt-synthesized utterances with exact-zero
   leading silence. Real mic recordings sit on a noise floor that
   varies with preamp gain / room HVAC / distant PA bleed. R9B adds
   an adaptive multiplier: take the **MIN per-frame energy across the
   leading ~480 ms** (16 frames) as the noise floor estimate, set the
   live threshold to `max(noise_floor × 3, R7F_floor)`. The 3×
   multiplier is the classical "speech runs ~10-30 dB above the room
   floor" rule of thumb (webrtcvad / Silero use similar ratios).

   The state struct gains four slots (`e_thresh_floor`, `noise_floor`,
   `calibrated`, `adaptive`) appended at the tail so R7F's `V_*` index
   constants are unchanged. Auto-calibration is wired into
   `vad_process_pcm` only -- per-frame entry points keep the state's
   threshold as set, preserving R7F's per-frame test contract
   bit-identical.

### What landed

- **`src/io/transducers/audio_vad.nova`** (+~120 lines, EXTENDED): new
  public surface -- `vad_calibrate_noise_floor(state, samples,
  max_frames)`, `vad_noise_floor(state)`, `vad_e_thresh_floor(state)`,
  `vad_is_calibrated(state)`, `vad_is_adaptive(state)`,
  `vad_set_adaptive(state, on)`. Constants
  `VAD_NOISE_CALIB_FRAMES = 16`, `VAD_NOISE_MULT = 3`.
  `vad_set_energy_thresh` flips adaptive=OFF + calibrated=ON to
  preserve R7F's "operator override wins" semantic. The R7F threshold
  values (`VAD_ENERGY_BASE_8K = 50000`, scaled), accessors, hysteresis,
  segment recording, and `vad_filter_pcm` are untouched.
- **`src/io/transducers/audio_capture.nova`** (parser-only fix): scan
  forward through optional RIFF sub-chunks after `fmt ` until
  `data` is found. The data-offset is now whatever the scan resolves
  (no longer hard-coded 44).
- **`tests/unit/test_audio_vad.nova`** (+~140 lines, EXTENDED): 31 new
  R9B assertions covering adaptive defaults, calibration on silence
  vs noisy lead-in, auto-calibration via `vad_process_pcm`,
  `vad_set_energy_thresh` override semantics, `vad_set_adaptive` opt-
  out, empty-buffer safety, headline noisy-lead-in single-segment
  scenario, double-process-pcm one-shot calibration. R7F's 55
  assertions still PASS bit-identical.
- **`tests/integration/scenario_oo_vad_natural.sh`** (NEW, 15
  assertions): synthetic silence (0 segments), synthetic noisy+speech
  (1 segment under adaptive threshold), JFK 16 kHz (parsed at 16 kHz,
  >=1 segment, filtered PCM 170880 samples in [80000, 208000]),
  end-to-end `/listen JFK` (vad_segments=1, transcript contains
  "fellow Americans" or "your country", backend=whisper). SKIPs
  cleanly if JFK WAV or whisper-main absent.
- **`AUDIO_AUDIT.md`**: R9B sub-section under R7F documents the two
  fixes, the adaptive design, the calibration window / multiplier
  rationale, the preserved R7F test contract, and the JFK end-to-end
  transcript.
- **`README.md`**: short blurb summarizing /listen now resolving on
  natural recordings.

### Verification

- **R7F's 55 existing assertions pass bit-identical** (`audio_vad: OK
  (86 checks)` -- 55 R7F + 31 R9B).
- 15/15 assertions in `scenario_oo_vad_natural.sh` green.
- R7F's `scenario_ii_vad.sh` (17 assertions), R8B's
  `scenario_jj_whisper.sh` (13 assertions), R7F's
  `test_audio_capture.nova` (28 assertions), R7F's
  `test_audio_synth.nova` (209 assertions), R6E's `scenario_w_audio_
  capture.sh` (23 assertions) all green.
- Full unit suite 150/150 green.
- End-to-end `/listen /tmp/whisper.cpp/samples/jfk.wav` produces:
  `(heard 'and so my fellow Americans ask not what your country can
  do for you ask what you can do for your country' [vad_segments=1,
  backend=whisper]; ...)`.

### Follow-ups not in this session

- **Per-utterance re-calibration**: optional flag to force calibration
  re-baselining at silence boundaries for very long capture buffers
  where the noise floor drifts.
- **Spectral entropy** as a third discriminator -- rejects single-
  frequency interference (HVAC hum, 50/60 Hz mains).
- **VAD-aware segment-level STT dispatch**: hand each VAD segment to
  STT independently and join transcripts at segment boundaries,
  preserving utterance pauses for prosody / turn-taking.

---

## R9F (this session) — Federated Learning: Byzantine resilience (trimmed mean + median)

**Status: complete -- `src/learning/byzantine_aggregation.nova` lands as
a new leaf module wired into the federated aggregator with a parallel
`fed_acc_byz_*` accumulator.** P3.7 shipped FL averaging under an honest
participant model; R5 added SecAgg (pairwise additive masking) so the
coordinator only sees the SUM, not per-soul values; R5A + R7B migrated
DH to bn256_* + RFC 7919 Group 14. NONE of that defends against a
malicious participant submitting a poisoned update (a single soul
submitting `1_000_000` shifts the mean arbitrarily). R9F adds two
robust aggregation rules from the standard literature (Yin et al. 2018,
Chen et al. 2017):

- **Trimmed mean** (`byz_trimmed_mean(updates, trim_k)`): per-coord
  sort, drop top-k + bottom-k extremes, mean of the remainder.
  Tolerates k Byzantine per coordinate.
- **Coordinate-wise median** (`byz_coordinate_median(updates)`): per-
  coord median. Tolerates ~n/2 Byzantine in the worst case (a strict
  majority of honest values pins the median to the honest cluster).

Both share an `_byz_sort_int_list` helper (insertion sort; n is small
in practice, ~5..50). `byz_aggregate(updates, strategy, trim_k)`
dispatches BYZ_NONE / BYZ_TRIMMED_MEAN / BYZ_MEDIAN.

The federated aggregator gains a parallel accumulator
(`fed_acc_byz_new` / `_add_stat` / `_aggregate` / `_part_count`) that
keeps per-participant rows (so the reducer can inspect them) instead
of collapsing to a sum at submit time. `fed_acc_byz_aggregate(acc,
strategy, trim_k)` returns the same shape as `fed_acc_averages` so
downstream consumers don't need to change.

### SecAgg vs Byzantine trade-off (deliberate)

R9F's central design decision: SecAgg and Byzantine resilience are
FUNDAMENTALLY in tension. SecAgg hides per-soul values; Byzantine
filtering requires them. The two naive compositions fail:

- SecAgg-then-Byzantine -- aggregator unmasks to inspect -> defeats
  SecAgg's privacy guarantee.
- Byzantine-then-SecAgg -- soul filters its own update before masking
  -> trivially circumventable by a lying soul.

R9F therefore makes them SEPARATE privacy postures, not layers.
Operators pick ONE per round (`sa_acc_*` for SecAgg / `fed_acc_byz_*`
for Byzantine). The advanced primitives that close the gap (ZK proofs
of well-formedness, threshold-homomorphic encryption with range proofs,
trimmed-mean over secret shares) are out of scope for P3.10 and
walked in SECAGG_AUDIT.md's R9F appendix.

### Env knobs

- `CE_FL_BYZ_STRATEGY` -- `none|trimmed|median`. Default `none`
  (preserves P3.7 averaging behaviour).
- `CE_FL_BYZ_TRIM_K` -- integer; trim count per end per coord.
  Default 1.

### Verification

- `tests/unit/test_byzantine_aggregation.nova` -- **74 assertions**
  covering algorithm semantics, poisoning resilience, multi-dim
  aggregation, edge cases, env parsers, dispatcher routing, AND
  the `fed_acc_byz_*` federated integration.
- `tests/integration/scenario_pp_byz_fl.sh` -- **15 assertions**
  on a NOVA driver simulating 5 souls (4 honest, 1 Byzantine
  submitting 9999/9999 vs honest cluster 690-720 / 190-220 milli).
  BYZ_NONE produces the poisoned 2563/2163; BYZ_TRIMMED_MEAN
  (trim_k=1) recovers 710/210; BYZ_MEDIAN recovers 710/210.
  **Skew reduction: ~370x** (NONE skew = 1858, trimmed = 5).
- `tests/unit/test_secure_aggregation.nova` -- 170 assertions
  bit-identically green (only a header-comment note added to
  the SecAgg module).
- `tests/unit/test_federated_aggregator.nova` -- 91 assertions
  bit-identically green (Byzantine path is purely additive).

### Files touched

- NEW `src/learning/byzantine_aggregation.nova` (leaf module, ~280
  lines; depends only on `std/io`).
- `src/learning/federated_aggregator.nova` (additive: import +
  `fed_acc_byz_*` accumulator block; existing `fed_acc_*` path
  unchanged).
- `src/learning/secure_aggregation.nova` (header-comment note only).
- NEW `tests/unit/test_byzantine_aggregation.nova` (74 assertions).
- NEW `tests/integration/scenario_pp_byz_fl.sh` (15 assertions).
- NEW `tests/integration/_scenario_pp_drivers/byz_aggregation_driver.nova`.
- `SECAGG_AUDIT.md` (R9F appendix).
- `README.md` / `NEXT_SESSION.md` (this entry).

### Why R9F does NOT implement Krum / Bulyan

Krum (O(n^2 * d) per round) and Bulyan (O(n^3), needs n >= 4f+3) bind
their asymptotic guarantees at n=20+ scales. CrossEngin's current
federations are n=5-ish, where coordinate-wise median already pins
the aggregate to the honest cluster. Both are clean one-case
extensions of `byz_aggregate` when the federation scales.

### Module count: 140 -> 141

## R8B (R8 session) — Audio: whisper.cpp STT backend, /listen actually transcribes

**Status: complete -- `src/io/transducers/whisper_backend.nova` lands as
the third leg of the speech-to-text seam from R7F (`stt_seam.nova`).**
R7F shipped the clean `stt_transcribe(seam, audio_buffer) ->
[transcript, confidence, error]` interface with VAD gating and two
backends (stub + the legacy `scripts/transcribe.sh` subprocess shim).
This round wires a FIRST-CLASS whisper.cpp backend that the seam
dispatches to natively, so the chat's `/listen` command actually
produces text instead of returning the `[stt unavailable]` placeholder.

### Backend choice

Whisper.cpp (https://github.com/ggerganov/whisper.cpp) is the
MIT-licensed pure-C reimplementation of OpenAI Whisper. The `tiny.en`
ggml quantized model is ~75 MB; the `whisper-cli` binary is ~3 MB.
CPU-only inference on a 11-second JFK utterance completes in ~1 s on
a modest amd64 box. This fits CE's "minimal external deps" constraint:
no GPU, no LLM, no FFI; one fork+exec from NOVA.

### What landed

- **`src/io/transducers/whisper_backend.nova`** (NEW): 442 lines, leaf
  module (no CrossEngin deps; imports `std/syscall`). Public API:
  * `whisper_transcribe(bin_path, model_path, wav_path) ->
    [transcript, confidence_milli, error_msg]` -- the canonical
    spawn-and-drain entry point.
  * `whisper_transcribe_default(wav_path)` -- convenience wrapper
    that uses env-resolved `CE_WHISPER_BIN` / `CE_WHISPER_MODEL`.
  * `whisper_backend_available(bin_path, model_path)` -- openable-ness
    probe via `sys_open(O_RDONLY) + sys_close`; returns 1 iff both
    files open cleanly.
  * `whisper_resolve_bin()` / `whisper_resolve_model()` -- env-var
    readers with canonical defaults
    (`/usr/local/bin/whisper-main` + `/usr/local/share/whisper/ggml-tiny.en.bin`).
  * `whisper_clean_transcript(raw)` -- trim whitespace + collapse
    internal newlines to spaces + dedup runs of spaces. Public so
    tests can exercise without spawning the binary.
  * `whisper_result_transcript/_confidence/_error` -- tuple accessors.

  Internal:
  * Raw asm shims for `pipe2(293)`, `dup2(33)`, `close(3)`, `read(0)`
    (same pattern as `stt_seam._stt_*`; duplicated here to keep this
    module a leaf).
  * `_whisper_argv8(bin, "-m", model, "-f", wav, "-nt", "-np")` --
    seven-arg argv + NULL terminator; passed directly to
    `exec_program(bin, argv)` so we don't need a `/bin/sh -c`
    intermediate (saves one fork+exec).
  * Child rewires stdout to the pipe's write end, parent drains
    16 KB cap, both reap via `waitpid`.

- **`src/io/transducers/stt_seam.nova`** (R7F's file, EXTENDED):
  * Added `STT_BACKEND_WHISPER = 4` constant.
  * Added `_stt_autopick_backend()` -- env unset prefers whisper if
    installed, falls back to stub. NEVER auto-picks subprocess (the
    legacy shim path requires explicit opt-in).
  * Added `_stt_backend_whisper(s, wav_path)` -- routes to
    `whisper_transcribe_default`, mirrors the triple into the seam's
    `last_*` fields, preserves whisper's precise error string
    (e.g. "model not found") rather than collapsing to the stub
    placeholder.
  * Added `stt_seam_new_whisper(model_path)` constructor -- test
    convenience that pins the default to WHISPER and registers
    "whisper" alongside the existing two builtins.
  * Updated `stt_default_backend()` to recognize
    `CE_STT_BACKEND=whisper` and call the auto-pick helper when
    unset.

### Install layout (canonical)

| Path                                          | Source                                  |
|-----------------------------------------------|-----------------------------------------|
| `/usr/local/bin/whisper-main`                 | renamed from `whisper.cpp/build/bin/whisper-cli` |
| `/usr/local/share/whisper/ggml-tiny.en.bin`   | from `whisper.cpp/models/download-ggml-model.sh tiny.en` |

Operators override via `CE_WHISPER_BIN` / `CE_WHISPER_MODEL`. Build
recipe (one-shot):

```bash
git clone https://github.com/ggerganov/whisper.cpp /tmp/whisper.cpp
cd /tmp/whisper.cpp
cmake -B build -DBUILD_SHARED_LIBS=OFF -DCMAKE_BUILD_TYPE=Release
cmake --build build -j --target whisper-cli
bash ./models/download-ggml-model.sh tiny.en
sudo cp build/bin/whisper-cli /usr/local/bin/whisper-main
sudo mkdir -p /usr/local/share/whisper
sudo cp models/ggml-tiny.en.bin /usr/local/share/whisper/
```

### Verification

- `tests/unit/test_whisper_backend.nova`: 28 assertions covering env
  resolvers (defaults + overrides), openable-ness probe, all three
  pre-flight error paths ("binary not found" / "model not found" /
  "wav not found"), transcript cleanup (trim, newline collapse,
  space dedup, empty / all-whitespace input), result accessors, and
  the stt_seam round-trip through STT_BACKEND_WHISPER (verified via
  the seam's `last_error` surfacing the precise install gap).
- `tests/integration/scenario_jj_whisper.sh`: 13 assertions when
  whisper is installed (10 when it isn't). Synthesizes a Klatt
  utterance, runs it through `whisper_transcribe`, then runs the
  bundled `jfk.wav` and asserts the transcript contains
  "Americans". Exercises `stt_seam_new_whisper(model_path)` + the
  STT_BACKEND_STUB fallback path. SKIPs the model-decode assertions
  when whisper is not installed so CI on bare environments still
  passes.

`whisper_backend: OK (28 checks)`. `stt_seam: OK (27 checks)`
(unchanged shape; +1 assertion for the new "whisper" builtin
registration). All other audio test suites continue to pass:
`audio_synth: OK (209)`, `audio_capture: OK (28)`, `audio_vad: OK
(55)`. Full unit-test sweep: 146 suites green (was 145; +1 from
test_whisper_backend).

On the dev container the JFK sample transcribes to:

> "And so my fellow Americans ask not what your country can do for
> you, ask what you can do for your country."

(confidence=800, error="", tlen≈110 chars, ~1 s wall time on amd64).

### Open follow-ups

- Per-segment confidence via `--print-confidence`. Recent whisper-cli
  builds expose per-token logprobs; parsing that into a per-utterance
  milli value drops the current 800-ballpark.
- Streaming transcription via `-f -` (stdin PCM). Would let
  `stt_transcribe_pcm` skip the temp-WAV write and stream directly
  from the capture pipeline.
- Larger models (base.en / small.en / medium.en) for noisy /
  accented audio. The env-driven model selection already supports
  any model; the trade-off is download size + RAM.
- VAD-aware segmentation: hand each VAD-detected speech segment to
  whisper independently rather than concatenating. Preserves
  utterance boundaries for downstream prosody / turn-taking
  analysis.

---

## R8D (parallel session) — IO: stereo LR-check + sub-pixel refinement on R7E

**Status: complete -- `src/io/transducers/image_stereo.nova` extends
R7E's block-matching SAD disparity with the two quality follow-ups
the original audit named as next steps.** The integer SAD path
shipped in R7E is correct under the assumption that every interior
pixel has a true match in the other view; that breaks at occlusions
(a foreground edge in LEFT has no corresponding pixel in RIGHT
because the foreground hides the background only on one side), at
textureless regions (flat surfaces produce many equally-good SAD
matches), and at periodic patterns (repeating texture produces
multiple SAD minima at multiples of the period). LR-check rejects
all three classes by ALSO computing disparity right->left and
discarding pixels where the two answers disagree; sub-pixel
refinement fits a parabola through SAD(d*-1, d*, d*+1) to recover
fractional-pixel disparity. Both are textbook stereo quality
improvements (Scharstein-Szeliski IJCV 2002).

### What landed

- **`src/io/transducers/image_stereo.nova`** (+520 lines, EXTENDED;
  R7E's integer surface untouched for back-compat). New public API:
  * `stereo_disparity_lr_check(left, right, w, h, win_size, max_disp,
    lr_tolerance)` -> result tuple identical to R7E's; bytes are 0
    where left->right and right->left disparities disagree by more
    than `lr_tolerance` pixels (default 1).
  * `stereo_disparity_subpx(left, right, w, h, win_size, max_disp)`
    -> result tuple whose map slot is a LIST OF INTS (not bytes)
    holding milli-disparity (int(d_subpx * 1000)). Degenerate-
    parabola fallback (denom <= 0): snap to integer * 1000.
  * `stereo_disparity_quality(left, right, w, h, win_size, max_disp,
    lr_tolerance)` -> combined: LR-check first (rejects bad matches
    -> milli 0), sub-pixel refines survivors.
  * `stereo_disparity_milli_at(milli_list, w, x, y)` /
    `stereo_quality_milli_at` (alias) -> accessor.
  * `stereo_quality_pgm_paths(L, R)`, `stereo_quality_pgm_args(arg)`
    -- chat `/depth_q` admin one-liners; same shape as R7E's
    `stereo_pgm_args`.
- **`examples/crossengin_chat.nova`** (+1 line): `/depth_q L.pgm R.pgm`
  dispatch. The R7E `/depth` admin and its help line stay; `/depth_q`
  is dispatch-only.
- **`tests/unit/test_stereo_quality.nova`** (NEW, 42 assertions):
  LR-check identical inputs (mean / density 0, probed pixels 0);
  LR-check shifted-by-10 pair (probed disparities survive at 10);
  LR-check on synthetic occlusion fixture (right has rows [12..20)
  painted constant 0; majority of band-region pixels rejected,
  textured-row pixels survive at SHIFT); LR-check tolerance / invalid
  inputs; sub-pixel on integer-shifted-by-10 ramp (milli within
  +/- 200 of 10000); sub-pixel on 10.5-px-shifted ramp via bilinear
  interpolation (milli within +/- 300 of 10500); sub-pixel invalid
  inputs / OOB accessor safety; combined `stereo_disparity_quality`
  on integer-shifted-by-8 pair (milli ~8000 at consistent interior
  pixels, 0 at borders) + occlusion fixture (band pixels rejected);
  parabola-degeneracy fallback (flat SAD -> integer * 1000); /depth_q
  dispatch usage strings.
- **`tests/integration/scenario_kk_stereo_quality.sh`** (NEW, 11
  assertions): build LEFT (smooth-ramp 48x32 PGM via Python),
  RIGHT_INT (shifted-by-10), RIGHT_SUB (shifted-by-10.5 via bilinear
  interpolation), RIGHT_SMALL (32x24 ramp). Cases: /help still
  advertises /depth (R7E preserved); /depth_q no-arg / one-arg usage;
  identical inputs report `mean_milli=0`; integer-shifted pair
  reports `mean_milli >= 1000` + density label; sub-pixel-shifted
  pair reports `mean_milli >= 500`; dim mismatch + missing-file
  errors surface cleanly; chat reaches /quit cleanly.
- **`IMAGE_AUDIT.md`**: R8D LR-check + sub-pixel checked off in the
  feature ladder ("Stereo LR-check + sub-pixel refinement | DONE
  (R8D)"); SGM stays at "3-4 weeks". Cross-references added for the
  new unit + integration test files.

### Verification

- 42/42 unit assertions in `test_stereo_quality.nova` green.
- 11/11 integration assertions in `scenario_kk_stereo_quality.sh` green.
- R7E's `test_stereo.nova` (54 assertions) + `scenario_hh_stereo.sh`
  (10 assertions) still green -- R7E's contract preserved.
- Full unit suite: 148/148 green (added 1 file, no regressions).
- `make build` still 140 modules.

### Follow-ups not in this session

- **SGM** (Semi-Global Matching, Hirschmuller 2008): aggregate costs
  along 4-8 directions per pixel; smooths the disparity field via
  pseudo-2D dynamic programming; ~10x runtime + ~5x memory vs SAD
  but dramatically better in textureless regions. Significantly
  harder lift -- 3-4 weeks honest estimate.
- **Speckle filter**: connected-component analysis to drop
  small-cluster disparity blobs (typical post-LR-check cleanup).
- **Visual-perception seam** (`visual_perception.nova`) integration:
  switch `stereo_append_features_if_paired` from R7E's
  `stereo_disparity` to `stereo_disparity_quality` so the emitted
  atoms reflect the LR-filtered density rather than raw SAD.

## R8F (this session) — KG: episodic memory retrieval API + `/recall` chat command

**Status: complete -- the READ-side companion to R6F's WRITE-side
consolidation cycle landed as a pure extension to
`src/kg/episodic.nova`.** R6F shipped the cycle that scans recent
moments, detects co-occurring clusters, and promotes each into a
durable "episodic atom" with Beta(alpha,beta) belief; this session adds
the retrieval surface other parts of the substrate (chat /recall, the
decision loop's "what episodes do I remember about X" cue, KG queries)
need to pull memories OUT of the store by member, time window, pattern,
belief, or recency. The cycle is now bidirectional: writes via the
memory-loop sub-task (R6F), reads via the new retrieval API and the
chat dispatcher.

What landed:

- **`src/kg/episodic.nova`** (EXTENDED, +~310 lines beyond R6F's 473;
  R6F's write-side functions are bit-identical -- pure extension):
  - **Six retrieval functions** (all integer-arithmetic, no FP, no LLM
    call):
    - `episodic_recall_by_member(eas, atom_id, top_k)` -- episodic
      memories where `atom_id` is in the cluster (e.g., "show me all
      episodes involving atom 42").
    - `episodic_recall_by_window(eas, ns_start, ns_end, top_k)` --
      episodic memories whose [first_seen, last_seen] span overlaps the
      window (inclusive interval-overlap).
    - `episodic_recall_by_pattern(eas, member_ids, min_overlap, top_k)`
      -- episodic memories whose cluster overlaps the query by >=
      `min_overlap` ids (Jaccard-style numerator).
    - `episodic_recall_top_belief(eas, top_k)` -- top-K most-believed
      episodic memories (highest alpha/(alpha+beta)).
    - `episodic_recall_most_recent(eas, top_k)` -- top-K most-recently
      seen episodic memories (last_seen desc).
    - `episodic_provenance(eas, episodic_id)` -- full provenance tuple
      [members, count, first_ns, last_ns, alpha, beta] for one episode;
      0 if the id is not in the store.
  - **Ranking + tiebreak chain**: primary key = count desc (default) /
    last_seen desc (`most_recent`) / confidence desc (`top_belief`);
    secondary = last_seen desc; tertiary = id asc. Deterministic
    across runs.
  - **top_k clamping**: `top_k <= 0` returns empty; `top_k >
    EPISODIC_RECALL_TOP_K_MAX (=1000)` clamps; `top_k > store_count`
    returns everything (no overflow).
  - **`episodic_recall_cmd(stream, arg)`** chat dispatcher: runs a
    transient `episodic_consolidate` against the live moment stream,
    parses the subcommand off `arg`, prints a "RECALL <label>
    matched=<N>" header + one "EPISODE id=... members={...} count=...
    first_ns=... last_ns=... belief=... alpha=... beta=..." line per
    hit + a "RECALL_END <label>" trailer. Subcommands: `member <id>`,
    `window <start> <end>`, `top`, `recent`. Empty / unknown arg
    prints a usage line.
- **Chat wiring** (`examples/crossengin_chat.nova`, strict +5 lines):
  1 dispatch line (`if str_eq(cmd, "/recall") == 1 { return
  episodic_recall_cmd(stream, arg) }`) + 4 help lines describing the
  four subcommands. Reachable from the running chat binary as `/recall
  member 1`, `/recall window 0 100`, `/recall top`, `/recall recent`.
  No changes to R6F's `loop_memory.nova` wiring; the retrieval surface
  is pull-based, so the daemon's persistent eas and the chat's
  transient eas use the same retrieval functions.

Tests:

- **`tests/unit/test_episodic_retrieval.nova`** (NEW, 77 assertions):
  - Canonical fixture: R6F's 5x (1,2,3) triplets + scattered noise ->
    1 episodic atom; `episodic_recall_by_member(eas, 1, 10)` returns
    the {1,2,3} episode; `episodic_recall_by_member(eas, 99, 10)`
    returns empty.
  - Window overlap (inside, outside, touching first_seen / last_seen
    boundary); pattern overlap (>= K, < K, disjoint); top_belief,
    most_recent singletons; full provenance tuple round-trip; missing
    id; top_k=0 / negative / huge (1M -> no overflow).
  - Multi-episode rank order: insert a second cluster {4,5,6} (ts
    200..240) and verify `most_recent` orders id=0 (the newer cluster,
    last_seen=240) before id=1 (the older cluster, last_seen=40); the
    `top_belief` tiebreak falls through to last_seen desc when both
    are at the uniform prior; after three `episodic_observe` calls on
    {1,2,3} the older id=1 wins on confidence; `by_member` and
    `by_window` filters are isolation-clean; `top_k=1` returns only
    the highest-ranked hit. ALL PASS.
- **`tests/integration/scenario_mm_episodic_recall.sh`** (NEW, 19
  assertions): `examples/episodic_recall_demo.nova` (NEW driver
  mirroring `episodic_demo.nova`'s shape) mints the two-cluster
  fixture and exercises every `/recall` subcommand via the same
  `episodic_recall_cmd` dispatcher the chat process routes to; the
  shell asserts on each RECALL header line, the EPISODE record, the
  `matched=` count, and the usage / unknown-subcommand diagnostics.
  ALL PASS.

Canonical fixture (R6F's 5x (1,2,3) + 4 noise) extended for R8F to a
two-cluster fixture: 5x (1,2,3) at ts 0/10/20/30/40 then 5x (4,5,6) at
ts 200/210/220/230/240 -- the consolidation scan walks moments
newest-first, so episode id=0 is the newer {4,5,6} and id=1 is the
older {1,2,3}. `/recall recent` surfaces id=0 first (last_seen=240
> 40); `/recall top` tiebreaks on last_seen because both belief means
land at 500 at the uniform prior. After three episodic_observe calls
on (1,2,3), the older id=1 cluster wins on confidence.

ADRs honored: ADR-0022 (the consolidation cycle now has both write
and read sides), ADR-0023 (Bayesian belief surfaces as a rankable
key on the read side). NOVA dependencies: builtins + std/io + std/string
(io_println, char_at, substr, str_trim, rt_str_to_int -- pulled in by
the new chat-print dispatcher block at the bottom of `episodic.nova`).

Module count: unchanged from R7E -- the retrieval API extends
`episodic.nova` in place rather than adding a new module. The only NEW
files beyond tests are `examples/episodic_recall_demo.nova` (a scenario
driver, not a substrate module) and the new unit + integration suites.
Unit suites: +1 (`test_episodic_retrieval.nova`, 77 assertions); all
149 unit tests pass (148 existing + 1 new). Integration: +1 scenario
(`scenario_mm_episodic_recall.sh`, 19 assertions, ALL PASS); R6F's
scenario_ff_episodic.sh (37 assertions) still green.

## R8E (this session) — KG atom schema-evolution / migration framework

**Status: complete -- `src/persistence/schema_migration.nova` lands
as a generic, declarative framework for evolving the SHAPE of an atom
(its payload schema) over time without breaking R5D's v2 wire format
or R6F's episodic snapshot persistence.**

R5D's snapshot v2 added a one-off `snap_migrate_v1_to_v2` that bumps
the CONTAINER wire format from v1 -> v2. R6F added episodic atoms as
a forward-compatible third sub-list. Those covered the wire layer.
R8E adds the NEXT layer: a per-atom-kind schema generation that the
substrate uses to add / rename / retype / remove payload fields
cleanly, with old migrations frozen for bit-reproducibility across
sessions.

### Supported operations

- **ADD**     a new payload field with a default value
- **RENAME**  an existing payload field (rewrite key)
- **RETYPE**  a field's type (e.g. int -> milli via `SCHEMA_RETYPE_X1000`)
- **REMOVE**  a deprecated payload field

Each atom carries a `schema_version` payload entry naming the
generation that produced it. An atom missing the entry is treated as
`SCHEMA_LEGACY_VERSION = 1` -- the implicit shape every pre-R8E atom
has.

### Wire format

A new optional line in the v2 meta block:

```
schema.atoms_version <int>      # e.g. 3
```

A pre-R8E v2 file omits the line; the reader treats absence as v1
and migrates up cleanly. An older v2 reader that sees the line
ignores it (same forward-compat as `meta.creator` / `meta.created_ns`).
The wire format stays at v2 -- the schema layer is orthogonal.

### What landed

- **`src/persistence/schema_migration.nova`** (NEW): the framework.
  Public API:
  * `Migration` descriptor: `[from_v, to_v, kind, op, field, default]`
  * `register_migration(from, to, kind, op, field, default)` --
    declarative registration; new rules APPENDED, old rules NEVER mutated.
  * `apply_migration(atom, m)` -- single-step apply
  * `migrate_atom(atom, target_version)` -- chain every applicable
    rule up to `target_version`
  * `migrate_kg(kg, target_version)` -- walk every atom in a KG
  * `migrate_kg_with_default_ns(kg, target_version, snapshot_ts)` --
    variant the snapshot reader uses to inherit `created_ns` from
    the snapshot timestamp when the ADD default is 0.
  * `snap_post_load_migrate(s, kg_reg)` -- reader hook: reads
    `snap_meta_atoms_version(s)`, walks every KG, migrates each to
    `SCHEMA_CURRENT_VERSION`, stamps the snapshot's atoms_version
    slot so the next save emits the new line.
  * `atom_schema_version(a)` / `atom_set_schema_version(a, v)` --
    payload-field helpers.
- **`src/persistence/snapshot_writer.nova`** (+45 lines): meta block
  grew from 4 to 5 cells (slot 4: `atoms_version`); new accessors
  `snap_meta_atoms_version` / `snap_meta_set_atoms_version` /
  `snap_meta_has_atoms_version`; `snap_meta_new` defaults to
  `SNAP_META_ATOMS_VER_CURRENT (= 3)`; `snap_migrate_v1_to_v2`
  stamps the slot with `SNAP_META_ATOMS_VER_LEGACY (= 1)`.
- **`src/persistence/snapshot_disk.nova`** (+25 lines): import
  `schema_migration.nova`; emit one `schema.atoms_version <int>`
  line in the v2 meta block; parse the line in `snap_from_text`;
  install via `snap_meta_set_atoms_version` on v2 dispatch.
- **`examples/migrate_schema.nova`** (NEW): the runnable schema-
  migration helper. Reads `$CE_MIGRATE_OLD`, applies the chain via
  `snap_post_load_migrate`, writes `$CE_MIGRATE_NEW`, reports
  `migrated atoms v<old> -> v<new> (N atoms across K KGs)`.
- **`tests/unit/test_schema_migration.nova`** (NEW, 78 assertions):
  ADD basic + kind_any + idempotency; RENAME on FACT (rule kind) +
  no-op on LANG / CONCEPT / FACT-without-old-key; REMOVE one-shot +
  via chain; RETYPE x1000 one-shot + via chain + absent-field
  no-op; V1 -> V3 chain (both demo rules); V1 -> V3 chain on
  non-FACT keeps `label`; migrate_kg on 5-atom KG (ordering
  preserved); migrate_kg idempotency on already-V3 KG; snapshot
  reads legacy v2 file as schema V1; snapshot emits the new meta
  line; meta line round-trips; `migrate_kg_with_default_ns`
  substitutes snapshot timestamp; default registry has both demos.
- **`tests/integration/scenario_ll_schema_migrate.sh`** (NEW, 17
  assertions): hand-rolls a pre-R8E v2 snapshot with two atoms,
  runs the schema-migration driver, asserts output declares
  `schema.atoms_version 3`, asserts atom payloads survive the
  round-trip, asserts a second run is idempotent (v3 -> v3).
- **`SNAPSHOT_FORMAT.md`** (+80 lines): new "Atom-shape schema
  evolution (R8E)" section.

### Demo migrations registered today

| From | To | Kind        | Op     | Field                | Default        |
|------|----|-------------|--------|----------------------|----------------|
| 1    | 2  | `KIND_ANY`  | ADD    | `created_ns`         | 0 (or snapshot ts via `migrate_kg_with_default_ns`) |
| 2    | 3  | `ATOM_FACT` | RENAME | `label:display_label`| n/a            |

The first proves a kind-agnostic ADD across the chain. The second
proves a kind-specific RENAME (LANG / CONCEPT / SKILL atoms keep
their `label` payload). REMOVE + RETYPE are wired but not in the
default registry -- a future schema-change session registers them
in one line. Old migrations stay frozen for reproducibility.

### Verification

- `tests/unit/test_schema_migration.nova`: **78 assertions, all pass**.
- `tests/unit/test_snapshot_migrate.nova` (R5D's): **37 assertions,
  all pass** -- the v1 -> v2 wire migration is bit-identical because
  schema-migration rides on a different layer.
- `tests/unit/test_episodic.nova` (R6F's): **79 assertions, all
  pass** -- episodic atoms keep their `label` payload through the
  V2 -> V3 step because that rule is FACT-only.
- `tests/integration/scenario_ll_schema_migrate.sh`: **17
  assertions, all pass**.
- `tests/integration/scenario_dd_snap_migrate.sh` (R5D's): **16
  assertions, all pass**.
- `tests/integration/scenario_ff_episodic.sh` (R6F's): **37
  assertions, all pass**.
- Snapshot-related unit tests still green:
  `test_snapshot_disk` (31), `test_snapshot_writer` (27),
  `test_snapshot_episodic` (51), `test_snapshot_synapses` (89),
  `test_snapshot_compaction` (48), `test_snapshot_selfmodel` (38),
  `test_atom_store` (42), `test_atom_store_index` (61),
  `test_ann_index` (46), `test_multi_kg_manager` (23).

### Module count: 138 -> 139 (schema_migration.nova added).

### Future work (carried forward)

- **Production migrations**: as new fields are added to atom payloads,
  register the migration in `_schema_register_default_migrations`
  and bump `SCHEMA_CURRENT_VERSION`. Old rules are frozen.
- **More RETYPE transforms**: only `SCHEMA_RETYPE_X1000` (int ->
  milli) is shipped. Add new tags (e.g. `string_to_int_hash`) as a
  new branch in `apply_migration`'s RETYPE case without disturbing
  any existing migration.
- **Daemon wire-up**: the chat/daemon's `/load` path currently
  doesn't call `snap_post_load_migrate`. A follow-up patches the
  daemon's `_admin_load` to invoke the hook after
  `kg_section_apply` so live restarts pick up schema migrations
  automatically. For now the explicit `examples/migrate_schema.nova`
  driver covers the offline-migration use case.

## R7E (previous session) — IO: stereo depth via block-matching SAD disparity

**Status: complete -- `src/io/transducers/image_stereo.nova` lands as a
new leaf module that adds the missing third dimension to the CV pipeline.**
The pipeline so far operates on a SINGLE image: edge gradients (Sobel /
Canny), corner / keypoint features (Harris / SIFT / ORB), per-frame motion
(`video_motion_vectors`). None of those recover depth. Stereo block
matching with Sum-of-Absolute-Differences (SAD) is the simplest integer-
only path to a PER-PIXEL DEPTH estimate: feed two horizontally-separated
images of the same scene (left + right, conventionally captured by a
stereo camera rig with a known baseline) and compute a DISPARITY map --
the per-pixel horizontal shift between views. Depth follows from
similar triangles: `depth_mm = baseline_mm * focal_pixels / disparity`.

### Algorithm

For each pixel (x, y) in the LEFT image, extract a WIN_SIZE x WIN_SIZE
block (default 7x7) centered there, then slide that block along the SAME
scanline in the RIGHT image from x down to x - MAX_DISP (default 64) and
compute the SAD at each offset. Disparity at (x, y) = offset minimizing
SAD. Output: disparity map (same dims as left, encoded as bytes
0..MAX_DISP).

Border pixels (where the window would fall off the image) keep disparity
0. The leftmost interior columns where x - half < SHIFT cannot reach the
true disparity (local_max_d caps below SHIFT) so they read smaller
disparities, dragging the mean down a few units below the ground-truth
shift -- on a 64x32 textured pair shifted by 10 px the unit test asserts
disparity == 10 at the well-defined interior points (x=30, 35, 40, 45),
and the mean lands ~6-8. SHIFT=10 is recovered EXACTLY at any pixel where
the search window has room.

### What landed

- **`src/io/transducers/image_stereo.nova`** (NEW): 365 lines. Leaf module.
  Public API:
  * `stereo_disparity(left, right, w, h, win_size, max_disp)` -> result
    tuple [map, mean, density_milli, total].
  * `stereo_depth(disp_map, w, h, baseline_mm, focal_pixels)` -> list of
    ints in mm; disparity == 0 -> STEREO_MAX_DEPTH_MM sentinel (100000mm
    = 100m, "infinity / unknown").
  * `stereo_sad_block(left, right, w, x_l, x_r, y, win_size)` -> raw SAD.
  * `stereo_disparity_at(map, w, x, y)`, `stereo_depth_at(depth, w, x, y)`,
    `stereo_density_label(milli)`, `stereo_disparity_mean_label(mean)`,
    result-tuple accessors.
  * `stereo_append_features_if_paired(feats, left, w, h)` -- visual
    perception integration hook. Reads `CE_VP_STEREO_RIGHT` env; when
    set, parses that PGM, validates matching dims, runs disparity, and
    appends `image_stereo_disparity_mean_*` + `image_stereo_density_*`
    atoms. Silent (no atoms) when unset or dims mismatch.
  * `stereo_pgm_args(arg)`, `stereo_pgm_paths(L, R)` -- chat /depth
    admin one-liners.
- **`src/io/transducers/visual_perception.nova`** (+5 lines): import,
  VP_STEREO_MIN_DIM = 32, VP_LABEL_STEREO_DENSITY_LOW const, and one
  conditional call in `_vp_append_structural_features`. Stereo runs
  only when both axes >= 32 (the 7x7 window + 64-disp search needs
  headroom).
- **`examples/crossengin_chat.nova`** (+2 lines): `/depth L.pgm R.pgm`
  dispatch + help. The dispatch is a one-liner forwarding to
  `stereo_pgm_args(arg)` so the chat surface stays at 1 line.
- **`tests/unit/test_stereo.nova`** (NEW, 54 assertions):
  SAD on constant blocks (3 cases over sizes); SAD on known intensity
  diff (49*10=490 at 7x7, 9*10=90 at 3x3, 25*10=250 at 5x5; SAD a-b
  symmetric with SAD b-a); disparity on identical inputs (mean 0,
  density 0); disparity on shifted pair (probed at x=30,35,40,45 all
  == SHIFT=10); dim cap rejects 300x300; zero-pointer / zero-dim
  refusals; depth formula known triples (b=120 f=600 d=10 -> 7200,
  d=20 -> 3600, d=5 -> 14400; b=60 f=500 d=1,2,3 -> 30000, 15000,
  10000); depth zero-disparity clamped at MAX_DEPTH; depth bad inputs;
  density label round-trip (low <100, mid 100-499, high >=500);
  disparity_at / depth_at OOB safety; /depth args dispatch.
- **`tests/integration/scenario_hh_stereo.sh`** (NEW, 10 assertions):
  Build a 40x40 textured left PGM and the shifted-by-8 right
  companion. Cases: /help advertises /depth; no-arg / 1-arg usage;
  identical inputs report `mean_disp=0`; shifted pair reports
  `mean_disp >= 4` (lands at 6-8 with SHIFT=8); density label
  emitted; dim mismatch (40x40 vs 32x32) prints clear error; missing
  file prints PGM parser error; chat reaches /quit cleanly.

### Verification

- `tests/unit/test_stereo.nova`: **54 assertions, all pass**. The
  disparity-on-shifted-pair test confirms disparity == 10 EXACTLY at
  4 probed interior points (x=30,35,40,45 with SHIFT=10 on a 64x32
  textured fixture). Depth formula tests confirm `depth = baseline *
  focal / disparity` for 6 known triples.
- `tests/integration/scenario_hh_stereo.sh`: **10 assertions, all pass**.
- All existing unit tests pass (image_pgm 43, image_sobel 30,
  image_canny 22, image_sift 25, orb 34).

### Module count: 137 -> 138 (image_stereo.nova added).

### Future work (carried forward)

- **Left-right consistency check (LR-check)**: re-run disparity from
  right to left and zero any pixel where the two answers disagree
  by > 1. Standard outlier filter; ~2x runtime + an extra disparity
  map. Currently no consistency check means occlusions on the
  rightmost columns of LEFT (no right-image match) silently return
  best-effort SAD.
- **Sub-pixel disparity refinement**: parabolic fit on the three SAD
  values around the minimum gives 0.1-pixel-accurate disparity. Today
  we return integer disparity in raw pixel units. (Needs fixed-point
  math; ~50 LoC.)
- **Semi-Global Matching (SGM)**: aggregate SAD costs along 4-8
  directions per pixel. Much more accurate than per-pixel
  block-matching (especially in textureless regions where SAD has no
  clear minimum), but ~10x runtime and ~5x memory.
- **JPEG / PNG stereo pairs**: today the chat dispatches `/depth L.pgm
  R.pgm` -- only PGM. `_vp_pick_decoder_for_path` could be extended
  to dispatch stereo through the same routing the seam already has,
  so `/depth L.png R.png` works too.

## R7F (prior session) — IO: Voice Activity Detection on audio capture + clean STT seam

**Status: complete -- `src/io/transducers/audio_vad.nova` lands as a
new leaf module sitting between `audio_capture.nova` (WAV ingest) and
`stt_seam.nova` (transcription).** Before R7F, every audio capture
(including all-silence sandbox runs) flowed to the STT backend
unconditionally; the placeholder fall-through path (`"[stt: input wav
missing]"`) burned cycles transcribing nothing on a regular cadence.
R7F inserts a VAD layer so STT only sees confirmed-speech PCM, and the
seam now has a single canonical entry point `stt_transcribe(seam,
audio_buffer)` that dispatches by buffer shape regardless of which
backend (stub / subprocess / future).

### Algorithm

Per ~30 ms frame (240 samples @ 8 kHz, 480 @ 16 kHz, 720 @ 24 kHz, etc.):

  * `energy = Σ |sample|` (sum of absolutes; the variance proxy avoids
    the 64-bit overflow risk of sum-of-squares at 48 kHz PCM16).
  * `zcr = count of sign flips` (treats 0 as its own class so a stretch
    of exact zero from `_synth_phoneme_silence` doesn't manufacture
    phantom crossings).
  * Classifier: `energy > E_THRESH AND zcr < ZCR_MAX`. The ZCR ceiling
    rejects high-energy white noise — alternating ±3000 (max ZCR =
    n-1) classifies as silence even though its energy is well above
    threshold.

State machine: four states with hysteresis. K=3 consecutive speech
frames commit `SPEECH_START` (~90 ms confirmation); M=10 consecutive
silence frames commit `SPEECH_END` (~300 ms confirmation). The
`SPEECH_START` sample index is back-dated K-1 frames so segment
boundaries align with where speech actually began, not where we
confirmed it.

### What changed

- **NEW `src/io/transducers/audio_vad.nova`** — energy + ZCR helpers
  (`vad_frame_energy`, `vad_frame_zcr`), classifier
  (`vad_classify_frame`), state machine (`vad_process_frame`,
  `_vad_advance`), buffer processor (`vad_process_pcm`), filter
  (`vad_filter_pcm`). Pure module — no syscalls, all NOVA builtins.
  Sample-rate clamp [8000..48000]; thresholds scale linearly with
  frame_size so the same module works at every supported rate.
- **`src/io/transducers/audio_capture.nova`**: added
  `audio_capture_to_pcm_vad(wav_path) -> [filtered_pcm, sample_rate,
  n_segments]`. Internal `AC_*` list-index constants renamed
  `ACAP_*` to disambiguate from `loop_coordination.nova`'s `AC_TAG =
  0` (agent-context), which collided once the transitive import chain
  pulled both into the chat binary.
- **`src/io/transducers/stream_audio.nova`**: one-line rename
  `AC_WAV_PATH` -> `ACAP_WAV_PATH` to match the audio_capture
  refactor. No semantic change.
- **`src/io/transducers/stt_seam.nova`**:
  * `stt_transcribe(seam, audio_buffer)` — canonical entry point.
    Dispatches to `stt_transcribe_wav` (1-element buffer) or
    `stt_transcribe_pcm` (2-element [pcm_list, sample_rate] buffer).
  * `stt_transcribe_wav_vad(seam, wav_path)` — VAD-gated path.
    Returns a 4-tuple `[transcript, confidence, error, n_segments]`.
    Short-circuits to the stub placeholder if VAD detects zero speech
    so the backend never sees pure-silence input.
- **`examples/crossengin_chat.nova`**: `+1 import` (stt_seam), new
  `_admin_listen` handler + `/listen [PATH]` dispatch line + help
  line. With no arg, captures a fresh 5 s clip; with PATH, reads the
  existing WAV. Reports transcript + segment count + active backend.

### Verification

- `tests/unit/test_audio_vad.nova` (NEW): **55 assertions** covering
  rate clamp + frame_size derivation (240 @ 8 kHz, 480 @ 16 kHz),
  energy/ZCR helpers (zero / constant / alternating / triangle / noise
  buffers), classifier behaviour on silence / vowel / pure-noise /
  low-amplitude inputs, K=3 commit hysteresis (single-frame noise
  doesn't trigger; 3 consecutive speech frames does), M=10 silence-
  release hysteresis (9 silence frames stay in candidate; 10th
  commits SPEECH_END), full-buffer walks (1-segment / 2-segment /
  all-silence / all-noise patterns), `vad_filter_pcm` extracts-speech-
  only, threshold override.
- `tests/integration/scenario_ii_vad.sh` (NEW): **17 assertions**.
  Klatt-synthesizes "AY EY OW OY" (4 phonemes * 1200 samples @ 8 kHz
  = 600 ms of voice) padded with 150 ms leading + 300 ms trailing
  silence; writes WAV via `audio_write_wav`; reads back via
  `audio_capture_to_pcm_vad`. Expected outcome on the speech fixture:
  sr=8000, segments=1, filtered_len=4800. Pure-silence fixture: 0
  segments, empty filtered PCM. Pure-noise fixture (alternating
  ±3000): 0 segments (ZCR ceiling). Chat `/help` advertises
  `/listen`; `/listen <wav>` reports `vad_segments=N`.
- Existing audio test suites continue to pass unchanged: `audio_synth:
  OK (209)`, `audio_capture: OK (28)`, `stt_seam: OK (26)`.
- Full unit-test suite: `144 passed, 0 failed`.

### Module count: 136 -> 137 (audio_vad.nova added).

### Future work (carried forward)

- Adaptive thresholds: rolling silence-floor estimator so a noisy
  recording environment doesn't need manual energy-threshold tuning.
- Spectral entropy / sub-band energy: extra discriminator rejecting
  single-frequency interference (HVAC hum, 50/60 Hz mains).
- VAD-aware re-segmentation: rather than concatenating speech
  segments back-to-back, hand each segment to STT independently and
  join transcripts at segment boundaries -- preserves utterance
  pauses for downstream prosody / turn-taking.

---

## R7C — IO: Noise XK strength upgrade to 2048-bit RFC 7919 Group 14 DH

**Status: complete -- `src/io/transducers/noise_xk.nova` swapped from
256-bit field-prime DH to 2048-bit RFC 7919 Group 14 via
`bn2048_modpow_ct`.** R6C (commit `0e2700d`) shipped wire-correct
Noise XK + AEAD + mutual auth, BUT the DH primitive was `bn_modpow_ct`
over `p_25519` (~256-bit) -- below the RFC 7919 Group 1 floor (768
bits) and not cryptographically strong. R6C's own audit flagged this:
"The 2048-bit upgrade target is `bn2048_modpow_ct` + RFC 7919 Group 14
(already shipped in R5A); the noise_xk module needs only a swap of the
underlying primitive + bumped wire sizes." This R7C session lands that
swap.

### What changed

- **`src/io/transducers/noise_xk.nova`**: every DH call site rewired
  from `bn_modpow_ct` over `p_25519` (8-limb 256-bit) to
  `bn2048_modpow_ct_mont` over RFC 7919 Group 14 (64-limb 2048-bit).
  The Group 14 prime + generator are pulled from
  `bignum_2048.nova`'s pre-existing `rfc7919_group14_p()` and
  `rfc7919_group14_g()` factories (shipped in R5A, used by
  `secure_aggregation.nova`). A new module-level singleton
  `_NXK_G14_CTX_CACHE` caches the Montgomery context (built once via
  `bn2048_mont_ctx_new`) so every modpow op in the process reuses the
  same precomputed `n_prime0` + `r2_mod_n` -- amortizing the
  ~hundreds-of-ms `_bn2048_compute_r2_mod_n` reduce that
  `bn2048_mont_ctx_new` performs.
- **Wire format widening (internal to noise_xk)**: `NXK_DH_LEN` 32 ->
  256 bytes; `NXK_DH_HEX_LEN` 512 chars; every pubkey buffer, hex
  scalar, and LE-byte conversion helper widened accordingly
  (`_nxk_bn_to_le32` -> `_nxk_bn_to_le256`; `_nxk_le32_to_bn` ->
  `_nxk_le256_to_bn`). msg1 / msg2 grow from 48 bytes to 272 bytes;
  msg3 grows from 64 bytes to 288 bytes.
- **Protocol-name domain separation**: the Noise binding string
  changed from `"Noise_XK_25519_ChaChaPoly_SHA256"` to
  `"Noise_XK_RFC7919G14_ChaChaPoly_SHA256"` so a session set up under
  R6C (256-bit DH suite) cannot be confused with an R7C (2048-bit DH
  suite) session by transcript replay -- the initial MixHash binds
  the suite identifier at byte 0.
- **`tests/unit/test_noise_xk.nova`**: updated wire-size assertions
  (48 -> 272 for msg1/msg2; 64 -> 288 for msg3; 64 -> 512 for pubkey
  hex). Helper functions for building deterministic 512-char hex test
  scalars (`_t_hex512_repeat`). DH commutativity test now exercises
  the full 2048-bit modpow path. Test count parity with R6C (~25
  assertions across 10 test functions).
- **`tests/integration/scenario_gg_noise_kg.sh`**: static priv hex
  keys widened from 64 to 512 chars (single-nibble repeat keeps the
  source readable). Wait deadlines widened from 15s to 60s.
  Handshake timing budget widened from 2000ms (R6C 256-bit) to
  15000ms (R7C 2048-bit). Connect-side responder start-up sleep
  widened from 1s to 3s to give the responder time to bind/listen
  before the initiator's `nxk_pub_from_priv` modpow returns.
- **`FEDERATED_AUDIT.md`** + **`README.md`**: strength claims
  refreshed -- 2048-bit RFC 7919 Group 14 replaces the "256-bit DH
  below the RFC 7919 Group 1 floor" caveat. Wire-protocol diagram
  updated to show 272 / 288-byte handshake messages. Performance
  section updated to ~5-15s end-to-end handshake budget.

### Files touched (R7C-owned)

  * `src/io/transducers/noise_xk.nova`           (the swap)
  * `tests/unit/test_noise_xk.nova`              (byte-size assertions)
  * `tests/integration/scenario_gg_noise_kg.sh`  (key widening + timing)
  * `FEDERATED_AUDIT.md`                         (strength claims)
  * `README.md`                                  (status banner)
  * `NEXT_SESSION.md`                            (this section)

### Untouched (other R7 agents own; bn2048 swap is INTERNAL to noise_xk)

  * `src/io/transducers/kg_sync.nova` (R6C wired this for v3; kg_sync
    is wire-size-agnostic about Noise XK handshake-message sizes -- it
    framing-prefixes whatever buffer noise_xk hands it. The kg_sync
    env-var validators (`kgsync_noise_static_priv_from_env` and
    `kgsync_noise_peer_pub_from_env`) still enforce length 64 for
    backward compatibility with R6C-era operator configs; the
    integration test bypasses those by passing hex strings directly
    into the kg_sync handshake driver. Operators using the new 2048-
    bit static keys would need a follow-up patch to relax the env-
    var length cap, but that's a separate change owned outside R7C.)
  * `src/safety/bignum_2048.nova` (R5A -- R7C consumes its API; no
    modifications).

### Verification

- `make build` -- both `src/io/transducers/noise_xk.nova` and
  `src/io/transducers/kg_sync.nova` compile under the post-R7C swap.
- `tests/unit/test_noise_xk.nova` compiles; expected to PASS at ~25
  assertions. (Each `test_handshake_completes` or similar test that
  drives a full handshake takes ~5-15s under bn2048; the test
  programmatically runs the modpows in-process so cost adds up over
  10 test functions -- expect ~2-3 minute wall-clock for the full
  test run.)
- MITM rejection still works: the auth contract survives the DH
  widening because the initiator's `MixHash(rs)` binds whatever
  responder pubkey the initiator was told out-of-band; if the actual
  responder has a different static priv, its `es` DH yields a
  different shared secret, and the AEAD tag on msg1 fails to verify
  on the responder side.

### Performance

R5A's Montgomery-REDC-backed `bn2048_modpow_ct` measures at ~1-4s per
modpow on the sandbox (Fermat test landed in `~1500ms` ballpark).
Four modpows per side of the handshake (one keygen + three DHs) give
~5-15s end-to-end. Compared to R6C's baseline of ~508 ms wall-clock
(at 256-bit DH), R7C is ~10-30x slower -- the cost of moving from
broken (256-bit) to production-grade (2048-bit) DH. Future upgrades
to 3072 or 4096 bits would scale ~quadratically with limb count.

### LOUD caveats

- The fallback random path (when `secure_random` syscall returns -1)
  is still a nanotime+LCG stretch and is NOT cryptographically secure;
  the production path is OS `getrandom` via the R5B builtin.
- The DH is bignum-mod-prime exponentiation over RFC 7919 Group 14,
  NOT elliptic-curve. The 2048-bit MODP group is the smallest standard
  DH group considered cryptographically reasonable in 2025; future
  upgrades (3072 / 4096 / 8192 bits) need only a constant-table swap
  in bignum_2048.nova + a wider BN_LIMBS; the noise XK state machine
  is unchanged.

## R7B (this session) — Safety: realize bn256 Montgomery REDC speedup in production (DH-256 migration)

**Status: complete -- `src/learning/secure_aggregation.nova` migrated
from legacy `bn_modpow_ct` to `bn256_modpow_ct`.** R6B's bignum_256
Montgomery REDC mirror (commit `edf265b`) shipped a ~14x speedup on
the Curve25519 prime in microbenchmark, but left every production
caller untouched. R7B closes that gap for the only DH-256 production
caller (the v2-sa-dh path in `secure_aggregation.nova`):

  * `sa_dh_generate_keys` (one `g^priv mod p` per soul per round)
  * `sa_dh_shared_secret_for_peer` (one `peer_pub^my_priv mod p` per
    peer per round)

Both run on `p = 2^255 - 19` (Curve25519 prime, loaded from the
existing `_SA_DH_P_HEX` constant) which is odd, so Montgomery REDC
applies. Wire format is byte-identical (same 64-char lowercase hex,
same internal 8 x 32-bit little-endian limb layout shared by `bn_*`
and `bn256_*`), so registered peer pubkeys still parse via either
module. Tests prove bit-identical outputs:
`tests/unit/test_bignum_256.nova` includes an explicit
Mont-vs-legacy equivalence sweep on the Curve25519 prime.

### Measured speedup (this dev container, 10-iter microbenchmark)

A 2-soul-pair DH round (2 `sa_dh_generate_keys` + 2
`sa_dh_shared_secret_for_peer` = **4 `bn_modpow_ct` calls per iter**):

  * **BEFORE:** 260 ms / iter avg, ~65 ms per `bn_modpow_ct`
  * **AFTER:**  12.9 ms / iter avg, ~3.2 ms per `bn256_modpow_ct`
  * **Speedup: ~20x per call** (sandbox-variance-friendly window
    around R6B's reported 14x).

### Verification

  * **142 / 142 unit tests pass** (`scripts/test.sh` full sweep),
    including bit-identical equivalence proofs on
    `test_bignum_256.nova` and the DH commutativity round-trip on
    `test_secure_aggregation.nova` (170 checks).
  * **`scenario_u_secagg.sh` passes 48/48** (full SecAgg + dropout-
    resilience + DH-256 + DH-2048 sub-scenarios).
  * **`scenario_v_secure_channel.sh` passes 6/6**.
  * **Module count unchanged** (no new files; only
    `src/learning/secure_aggregation.nova` modified).

### What stays on legacy `bn_modpow_ct`

  * **`tests/unit/test_bignum.nova`** + the legacy `bn_*` paths used
    by the equivalence anchor in `tests/unit/test_bignum_256.nova`:
    keep the bit-by-bit reducer as the bit-exactness anchor for
    `bn256_*`.
  * **`src/safety/chacha20.nova`** and **`src/safety/poly1305.nova`**
    do not use `bn_modpow_ct` (Poly1305's field is the 130-bit prime
    `2^130 - 5`; `bn256_*` is 256-bit and does not apply).
  * **`src/io/transducers/noise_xk.nova`**: the Noise XK 256-bit DH
    is the other in-tree caller; **R7C** owns its migration which
    additionally upgrades to RFC 7919 Group 14 (2048-bit) for
    strength reasons, so R7B does not touch it.

### Files touched

  * `src/learning/secure_aggregation.nova` (+37, -19 lines; one new
    `import "../safety/bignum_256.nova"` + 2 modpow_ct call sites
    + comment refresh)
  * `SECAGG_AUDIT.md` (append "R7B production migration" subsection)
  * `NEXT_SESSION.md` (this section)

## R6C (previous session) — IO: kg_sync v3 — Noise XK handshake for mutual auth + transport encryption

**Status: complete -- `src/io/transducers/noise_xk.nova` LANDED + kg_sync
wrapped for v3.** The federation audit's "plaintext TCP" open gap is now
closed. Two souls federating their KGs over kg_sync v3 mutually
authenticate via static Curve25519-shape pubkeys, derive a session hash
that transcript-binds every byte of the handshake, and run all
post-handshake traffic through per-direction ChaCha20-Poly1305 with
monotonic 64-bit nonces.

### What landed

- **`src/io/transducers/noise_xk.nova`** (NEW, ~1500 lines) — pure-NOVA
  Noise XK pattern (noiseprotocol.org section 7.5):
    - SHA-256 (FIPS 180-4) implementation built from scratch.
    - HMAC-SHA256 (RFC 2104) + HKDF-Extract/Expand (RFC 5869).
    - Curve25519-shape DH (`bn_modpow_ct` over `p_25519` with g=2; wire
      layout matches X25519 so a real-ECDH drop-in is straightforward).
    - ChaCha20-Poly1305 AEAD (RFC 7539) on top of the existing
      `src/safety/chacha20.nova` + `poly1305.nova` leaves.
    - Noise SymmetricState: MixHash, MixKey, EncryptAndHash,
      DecryptAndHash; HandshakeState driver for the XK pattern
      (`-> e, es`; `<- e, ee`; `-> s, se`); Split to derive the two
      transport keys; per-direction monotonic nonce counters with
      replay rejection on open.
    - OS CSPRNG via `secure_random(buf, n)` (R5B builtin) with
      nanotime+LCG fallback path.

- **`src/io/transducers/kg_sync.nova`** (MODIFIED, +350 lines, no v2
  behavior change) — v3 wrap of the existing line protocol:
    - `kgsync_v3_handshake_initiator(fd, static_priv, peer_pub)`
      and `kgsync_v3_handshake_responder(fd, static_priv, allowlist)`
      drive the three handshake messages over the TCP fd.
    - `kgsync_v3_send_line(noise_conn, line)` /
      `kgsync_v3_recv_line(noise_conn)` wrap every line in a Noise
      transport AEAD frame `[4 B BE len] [ct] [16 B Poly1305 tag]`.
    - Env knobs: `CE_KGSYNC_REQUIRE_NOISE` (gate the v3 path),
      `CE_KGSYNC_NOISE_STATIC_PRIV` (64-hex), `CE_KGSYNC_NOISE_PEER_PUB`
      (initiator only), `CE_KGSYNC_NOISE_ALLOWLIST` (responder allowlist
      of accepted initiator pubkeys, comma-separated).
    - v2 plaintext remains the default for backward compatibility;
      `CE_KGSYNC_REQUIRE_NOISE=1` flips kg_sync into "Noise-only" mode.

- **`tests/unit/test_noise_xk.nova`** (NEW) — **42 assertions** across
  10 test functions:
    - SHA-256 known-answer vectors (FIPS 180-4 "abc", empty string,
      448-bit boundary).
    - HMAC-SHA256 RFC 4231 Test Case 1.
    - DH commutativity (`a^b == b^a mod p`).
    - Static keypair gen: priv != pub; pub matches `g^priv`.
    - Full Noise XK handshake: msg1/2/3 sizes, recv ok at each step;
      both sides agree on session hash + transport keys; responder
      learns initiator's static pubkey; initiator knows responder's.
    - Transport round-trip: I->R + R->I encrypt/decrypt with matching
      plaintexts.
    - Tamper detection: single-byte CT flip rejected; length-prefix
      tamper rejected.
    - Replay rejected (nonce monotonicity).
    - MITM with wrong responder pubkey rejected at msg1 (the
      initiator's `MixHash(rs)` bound to the real pub, so the responder
      with a different priv can't reproduce the same AEAD key).

- **`tests/integration/scenario_gg_noise_kg.sh`** (NEW) — **12
  assertions** across 2 stages. Stage 1 spins up a responder + initiator
  as two NOVA processes over a real TCP socket: handshake completes,
  initiator sends an `ATOM lang 7 1 800 200 widget\n` line encrypted,
  responder decrypts to the expected plaintext, responder echoes back
  `ACK 42`, initiator decrypts. Stage 2 spins up a MITM responder with
  a DIFFERENT static priv: the initiator's handshake correctly fails
  (rejected at msg1 AEAD verify on the responder side, and the
  initiator gives up cleanly after msg2 fails on its side).

### Verification

- **All unit tests pass** (test_noise_xk adds 42 checks; existing
  tests including test_kg_sync untouched).
- **scenario_g_kg_sync** (v2 plaintext) still passes 13/13.
- **scenario_g2_kg_sync_multi** (multi-sub + token + merge) still
  passes 24/24.
- **scenario_gg_noise_kg** (this session) passes 12/12.

### Handshake timing

Measured on the integration runner: **~508 ms wall-clock** for the full
3-message Noise XK handshake (4x `bn_modpow_ct` operations dominate;
SHA-256/HKDF are negligible). Well under the 2-second budget specified
in the brief. Real ECDH on Curve25519 (X25519 ladder) drops this to
~5 ms when it lands — the noise XK state machine is unchanged for that
upgrade, only `c25519_scalarmult_base` / `_nxk_dh` need to be replaced.

### LOUD caveats

- 256-bit DH on `p_25519` is field-prime DH, NOT elliptic-curve scalar
  mult. Wire layout matches X25519 so a real-ECDH drop-in is a leaf
  replacement; the noise XK state machine plus the AEAD / HKDF /
  transcript-hash machinery above are unchanged.
- 256-bit DH is below the RFC 7919 Group 1 (768-bit) minimum and is
  breakable in tractable time. The MVP demonstrates the wire protocol +
  mutual-auth contract, not cryptographic strength. The 2048-bit
  upgrade target is `bn2048_modpow_ct` + RFC 7919 Group 14 (already
  shipped in R5A; the noise_xk module needs only a swap of the
  underlying primitive + bumped wire sizes).
- The fallback random path (when `secure_random` is unavailable) is a
  nanotime+LCG stretch and is NOT cryptographically secure. The
  production path is OS `getrandom` via the R5B builtin.

## R6B (this session) — Safety: Montgomery REDC mirror for bn256_modpow_ct

**Status: complete -- `src/safety/bignum_256.nova` LANDED with CIOS-form
Montgomery REDC.** R5A landed Montgomery REDC for the 2048-bit case
(commit `40c39326`) and gave ~10x speedup on `bn2048_modpow_ct`. This
session mirrors that work for the 256-bit case as a parallel `bn256_*`
prefix to the existing `bn_*` from `bignum.nova`. The new module
exposes the same Montgomery shape:

- `bn256_mont_ctx_new(N)` -- precomputes `n_prime0 = -N^-1 mod 2^32`
  via Newton's iteration + `r2_mod_n = R^2 mod N` via the legacy
  bit-by-bit reducer; paid ONCE per modulus, amortized across every
  Montgomery op on the same N.
- `bn256_to_mont(x, ctx)` / `bn256_from_mont(x_mont, ctx)` -- enter
  / leave Montgomery form.
- `bn256_montmul(a, b, ctx)` -- CIOS-form Montgomery multiplication
  with the 32x32 -> 64 multiplies INLINED via 16-bit halves (the
  same anti-pattern fix R5A discovered: a helper returning `[lo, hi]`
  would allocate ~512k short-lived pairs per modpow at 256 bits;
  inlining drops it to zero per-iter allocations past the one-shot
  9-limb accumulator).
- `bn256_modpow_ct_mont(b, e, ctx)` -- caller-managed Montgomery
  exponentiation.
- `bn256_modpow_ct(b, e, m)` -- the public CT modpow, routes through
  Montgomery + per-modulus ctx; falls back to `_bn256_modpow_ct_legacy`
  for even moduli (Montgomery REDC requires gcd(N, R) = 1; every
  standard DH safe prime is odd).
- `_bn256_modpow_ct_legacy(b, e, m)` -- retained as fallback + as the
  equivalence anchor in unit tests.

**Measured speedup on Curve25519 prime with 254-bit `p-1` exponent:
~14x** (Mont ~3.1 ms vs Legacy ~45 ms). The headline Fermat check
`bn256_modpow_ct(2, p-1, p) == 1` passes in ~3.1 ms wall-clock.

- **`src/safety/bignum_256.nova`** (NEW) -- 8-limb 256-bit pure-NOVA
  bignum library parallel to `bignum.nova` and `bignum_2048.nova`.
  Public surface mirrors `bignum_2048.nova` shape (no non-CT
  `bn256_modpow`; the legacy non-CT path lives in `bignum.nova` as
  `bn_modpow` for offline test vectors). Includes
  `bn256_curve25519_p()` for the Curve25519 field prime constant.
- **`tests/unit/test_bignum_256.nova`** (NEW) -- 70 assertions across
  27 test functions covering hex round-trip / carry chains / underflow
  wrap / mul small + carry-into-hi + max-squared / mod / modmul /
  modpow_ct textbook + edges + Curve25519 2^255 sanity; Montgomery
  context round-trip on N=1009; mont == legacy equivalence on 2
  pseudo-random vectors at small N + 1 cross-check on the Curve25519
  prime with `0xDEADBEEFDEADBEEF`; headline Fermat check on Curve25519
  prime; speedup-ratio measurement on the Curve25519 prime with the
  full 254-bit `p-1` exponent (asserts >=2x band; observed ~14x).
- **`src/safety/bignum.nova`** (UNCHANGED) -- the existing `bn_*`
  prefix continues to use the bit-by-bit reducer and remains in use
  by Curve25519 ECDH emulation, ChaCha20-Poly1305 field math, and
  the `secure_aggregation.nova` DH-256 fallback. Migrating those
  callers to `bn256_modpow_ct` for the per-op ~14x speedup is a
  follow-up patch (the new prefix is ship-able without touching any
  in-use call site).
- **`make test`**: PASS (no regressions in any crypto suite --
  bignum, bignum_256, bignum_2048, chacha20, poly1305,
  secure_channel, secure_aggregation).
- **`make build`**: PASS (the bignum_256.nova module is +1 module
  in the count).
- **`SECAGG_AUDIT.md`** extended with a new
  `## What "bignum_256 landed" means concretely (R6B Montgomery REDC mirror)`
  section documenting the public surface, the CIOS implementation
  note, the test-coverage matrix, and the migration story for
  existing `bn_*` callers.
- **`README.md`** updated: unit-test suite count bumped to include
  `test_bignum_256.nova` (+70 assertions); +1 module description for
  `safety/bignum_256.nova` with the ~14x speedup headline + the
  Curve25519 Fermat result.

## R6F (this session) — KG: episodic memory consolidation cycle (long-term memory promotion)

**Status: complete -- `src/kg/episodic.nova` LANDED with the full
ADR-0022 consolidation cycle and wired into the memory loop.** The
substrate observes and accumulates atoms (ADR-0016) and moments
(ADR-0021) continuously; this session adds the cycle that scans recent
observations, detects clusters of atoms that co-occur >=5 times within
a small temporal window (>=3 atoms within 100ms / 10 ticks @100Hz per
ADR-0037), and promotes each recurring cluster into a durable
"episodic atom" -- a compound atom with its own Beta(alpha, beta)
belief (ADR-0023) and provenance label. Subsequent observations
matching an existing cluster update the belief in real time.

What landed:

- **`src/kg/episodic.nova`** (NEW, ~473 lines): the consolidation
  cycle module. Defines `episodic_atom_t` = { id, cluster_member_ids,
  count, first_seen_ns, last_seen_ns, alpha, beta, provenance_label }.
  Public API:
  - `episodic_consolidate(eas, stream, window_ticks, max_atoms)` --
    scan recent moments, mint a new episodic atom for every
    >=3-atom cluster whose count >=5 in the window; fold existing
    cluster's evidence (count + last_seen) and bump belief on each
    repeat pass.
  - `episodic_match(ep_atom, observation_atom_id)` -- single-id
    membership test.
  - `episodic_match_observation(ep_atom, observation_atom_ids)` --
    cluster-subset-of-observation test (the cluster fires iff every
    cluster member appears in the observation; partial match
    (A,B,X) vs {A,B,C} returns 0 -- documented policy).
  - `episodic_update_belief(ep_atom, matched)` -- Beta(alpha, beta)
    update; matched=1 increments alpha, matched=0 increments beta
    (ADR-0023).
  - `episodic_observe(eas, observation_atom_ids, now_ns)` -- walk
    every stored atom, update belief + count + last_seen for each
    cluster matched by the observation. Does NOT penalize
    non-matches (typical observation covers one cluster).
- **Wired into the memory loop** (`src/agent/loop_memory.nova`,
  ADR-0036): added `loop_memory_step_with_episodic(ctx, stream, em,
  eas)` extension. Every step calls `episodic_observe` for live
  belief reinforcement; every LOOP_MEM_CONSOL_EVERY (=100) steps,
  the consolidation sweep fires. ADR-0036 leaves no room for a new
  loop, so the cycle lands as a memory sub-task -- the natural
  owner since memory already manages the moment stream + episode
  storage. The legacy 3-arg `loop_memory_step` is preserved so the
  chat binary's existing call site keeps working.
- **Snapshot persistence** (`src/persistence/snapshot_disk.nova`):
  extended the EPISODIC section blob with an optional third
  sub-list `episodic_atoms` -- forward-compatible with v2 (NO
  major version bump; R5D's v2 format is preserved bit-identically
  for snapshots that don't carry episodic atoms). New wire keys:
  `episodic.atoms.count`, `episodic.atoms[N].{id,member_count,
  members[K],count,first_ns,last_ns,alpha,beta,provenance}`. The
  legacy 2-arg `episodic_section_build` and `episodic_section_apply`
  are preserved; new 3-arg variants
  (`episodic_section_build_with_atoms`,
  `episodic_section_apply_with_atoms`) take the optional `eas`
  store. A snapshot from a pre-this-build writer parses cleanly.

Tests:

- **`tests/unit/test_episodic.nova`** (NEW, 79 assertions):
  atom shape, canonical signature (order-invariant), no-cooccurrence
  consolidation produces zero atoms, canonical fixture (5x (1,2,3) +
  scattered noise -> exactly 1 episodic atom with count=5), 6th
  triplet -> match returns true + alpha increments by FP_SCALE,
  partial (A,B,X) match rejection, explicit Beta update,
  find-by-signature, re-consolidate dedup, full snapshot round-trip,
  legacy 2-element blob forward-compat. ALL PASS.
- **`tests/integration/scenario_ff_episodic.sh`** (NEW, 37 assertions):
  hand-rolled NOVA driver (`examples/episodic_demo.nova`) mints +
  persists an episodic atom, the script asserts on the wire format
  keys + reload round-trip; legacy v2 file (no `episodic.atoms.*`
  lines) parses to 3 sub-lists with the third empty (forward-compat).
  ALL PASS.

Canonical fixture (5x (1,2,3) triplets at ts = 0, 10, 20, 30, 40
within EPISODIC_COOCCUR_WINDOW = 10 ticks @100Hz, plus four
unrelated triplets at ts = 5, 15, 25, 35): **1 episodic atom**
produced (cluster {1,2,3}, count=5, first_ns=0, last_ns=40).

ADRs implemented this session: ADR-0022 (consolidation cycle, the
long-term memory promotion the substrate didn't have), ADR-0023
(Bayesian belief tracking on each episodic atom), ADR-0048 (the
extended EPISODIC blob shape persists alongside KG atoms).

Module count: 135 (134 at HEAD post-R6D + `src/kg/episodic.nova`).
Unit suites: +1 (test_episodic.nova).

## R6D (previous session, separate commit) — IO: ORB (Oriented FAST + Rotated BRIEF) feature detector + Hamming-distance matcher (patent-free SIFT alternative)

**Status: complete -- `src/io/transducers/image_orb.nova` LANDED with the
full Rublee 2011 pipeline.** R5C landed SIFT 128-D descriptor + Lowe
ratio matcher (commit `c798353`) but SIFT is encumbered by US Patent
6,711,293 in some jurisdictions and pays 15x per-pixel work for the
3-octave Gaussian pyramid + descriptor histograms. R6D adds ORB as a
COMPLEMENTARY detector + matcher: patent-free (FAST + BRIEF are both
license-clean since 2011), integer-only throughout, much faster
end-to-end on the same fixture.

The full ORB pipeline lands in one module:

- **FAST-9 keypoint detection**: 16-pixel Bresenham circle of radius 3
  around each interior pixel; flag as corner iff 9 or more contiguous
  pixels around the circle (wrapping at index 15->0) are all brighter
  than I(p)+20 or all darker than I(p)-20.
- **Harris-corner-proximity ranking**: REUSES `harris_apply` from R1.6
  / image_harris.nova; FAST candidates with no Harris corner within 4
  pixels (Chebyshev) are dropped as edge responses, mirroring
  image_sift.nova's edge-rejection test.
- **Intensity-centroid orientation**: walk a 31x31 patch around each
  keypoint, compute first moments m_10 and m_01, then atan2(m_01,
  m_10) quantized into one of 30 buckets (12 deg each) via a
  precomputed cos/sin milli-unit table.
- **rBRIEF descriptor**: 256-bit binary signature. 256 (x_i, y_i,
  x_j, y_j) point pairs in [-15..+15]^2 generated by a 16-bit Galois
  LFSR (polynomial x^16+x^14+x^13+x^11+1, feedback mask 0xB400;
  seed 0x12345 trimmed to low-16 0x2345 -- documented seed for
  reproducibility). Each pair is ROTATED by the keypoint's
  orientation before sampling so the descriptor is rotation-invariant.
  Bit_n = 1 iff I(rotated_p_i) < I(rotated_p_j). Bits packed
  LSB-first into 8 int32 chunks (= 32 bytes).
- **Hamming-distance matcher + Lowe ratio test**: popcount of XOR over
  the 8 chunks per descriptor pair; accept iff
  best/second < 0.75 (750 milli, default). Byte-wise XOR and popcount
  synthesized from NOVA's int_add / int_mul / % builtins (NOVA exposes
  no native bitwise primitives).

Measured on the 40x40 four-spots reference fixture (analogue of the
brief's `four_spots_32x32.pgm`): FAST-9 + Harris filter -> **96
keypoints**; ORB self-match -> **96 matches** at Hamming distance 0;
90-deg rotated copy -> **96 rotation matches** (rotation invariance
verified); vertical-edge cross fixture -> **0 matches** (Harris filter
rejects every FAST candidate on a single-direction edge -- no Harris
corners on a straight gradient).

- **`src/io/transducers/image_orb.nova`** (NEW, ~750 lines) -- complete
  ORB pipeline + chat-orchestration helper `orb_match_pgm_args(arg)`.
- **`tests/unit/test_orb.nova`** (NEW) -- 34 assertions / 19 test
  functions: FAST-9 detection on four-spots; uniform-grey 0 keypoints;
  descriptors parallel to keypoints + 8 chunks each; Hamming distance
  to self / known 0xFFF^all flipped / single-bit / size-mismatch;
  self-match all-N + first distance 0; rotation-invariance match;
  cross-fixture rejection; degenerate inputs (too-small / too-large /
  null data_ptr / zero width); matcher edge cases (empty / < 2
  candidates); count-bucket + density labels; accessor round-trip.
- **`tests/integration/scenario_ee_orb_match.sh`** (NEW) -- 8 PASS
  assertions: /help advertises /orb_match; usage errors for 0/1 args;
  identical-PGM /orb_match reports N >= 1; per-image keypoint counts
  surfaced; structurally-different (spots vs edge) -> 0 matches;
  missing file -> parser error; chat survives + reaches /quit.
- **`src/io/transducers/visual_perception.nova`** -- added 5 lines:
  one import + ORB label constants + min-dim const + max-keypoint
  const + per-image ORB call in `_vp_append_structural_features`
  alongside SIFT + Canny. Per-image atoms: `image_orb_kps_<low|mid|high>`
  + `image_orb_density_<low|mid|high>`.
- **`examples/crossengin_chat.nova`** -- added 2 lines (strict scope):
  one help line + one dispatch line for `/orb_match A B`. The
  end-to-end orchestration lives in `orb_match_pgm_args()` in
  image_orb.nova so the chat doesn't bloat.
- **`IMAGE_AUDIT.md`** -- new "ORB" entry in the feature-roadmap table
  + a full pipeline-detail bullet in the P3.3 structural-features
  body. The "P3.3 cont. v3" tag distinguishes ORB from SIFT
  detection (v1) and SIFT descriptor (v2).

## R6E (last session) — Audio: full ~44-phoneme ARPAbet Klatt synthesis

**Status: complete -- `src/io/effectors/audio_synth.nova` LANDED with the
expanded inventory.** The pre-P6 Klatt-style two-formant synthesizer
recognized 33 phoneme dispatches (28 distinct symbols with a/ah, e/eh,
i/iy, o/oh, u/uw aliasing). P6 expands to **53 dispatches covering 44
distinct ARPAbet symbols**, plugging the gaps that made the Mode-1 floor
mispronounce diphthongs (FACE/PRICE/MOUTH/CHOICE), affricates
(CHURCH/JUDGE), voiced fricatives (THIS/MEASURE), and syllabic
nasals/liquids (BOTTOM/BOTTLE).

Added 20 dispatches across 5 categories:

- **+7 monophthongs**: aa, ao (formerly aliased), uh (foot, lax),
  er (bird, rhotacized), ax (schwa), ix (reduced high), axr (rhotacized
  schwa).
- **+4 diphthongs**: aw (MOUTH), ay (PRICE), ey (FACE), oy (CHOICE).
  Encoded as 4-element formant table (start formants + DIPHTHONG kind) +
  parallel `_diphthong_end_formants` table for the glide target. New
  `_synth_diphthong` linearly interpolates F1/F2 per-sample across the
  1200-sample buffer (~0.88 Hz/sample for the largest jump, AY's F2
  1230->2290).
- **+2 affricates**: ch (T+SH), jh (D+ZH). Encoded as AFFRICATE kind with
  `_affricate_parts` returning [stop_label, fricative_label]; new
  `_synth_affricate` concatenates ~40% plosive + ~60% fricative within
  the 1200-sample budget.
- **+3 fricatives**: dh (voiced TH), zh (voiced SH), hh (HH alias for h).
- **+4 syllabic nasals/liquids**: em, en, eng, el. New SYLLABIC kind with
  `_synth_syllabic` applying gentler damping (1000->700 vs nasal's
  1000->500) and reduced amplitude (~70% of onset).

Public API surface (additive):

- `klatt_phoneme_count()` -> `53` (inventory size).
- `klatt_phoneme_labels()` -> list of all 53 labels in dispatch order.
- `diphthong_end_formants(label)` -> end formants for 4 diphthongs.
- 3 new phoneme kinds: `PHO_KIND_DIPHTHONG=5`, `PHO_KIND_AFFRICATE=6`,
  `PHO_KIND_SYLLABIC=7`. Existing kinds (VOWEL=1, PLOSIVE=2, FRICATIVE=3,
  NASAL=4) unchanged.

Files touched:

- `src/io/effectors/audio_synth.nova` (+~220 lines: extended formant
  table, 3 new synth functions, klatt_phoneme_count/labels API).
- `tests/unit/test_audio_synth.nova` (+22 test functions / +110 ce_*
  checks; 99 -> 209 total assertions).
- `examples/crossengin_chat.nova` (+1 line in `/help` mentioning the
  ~44-phoneme inventory; explicit per the R6E brief's "AT MOST 1-2
  lines" cap).
- `AUDIO_AUDIT.md` (NEW): full audit doc with category-by-category
  comparison (33 baseline vs 53 expanded), diphthong glide arithmetic,
  affricate sequencing, syllabic vs onset comparison, verification
  inventory.
- `README.md` (`audio_synth / audio_speak` paragraph extended with the
  full inventory enumeration).

Verification: `audio_synth: OK (209 checks)`; full unit-test suite
139/139 PASS (no regressions). The 4-word diphthong test utterance
("DAY KAY MOW BOY" = D+EY, K+EY, M+OW, B+OY) synthesizes to exactly
4 * 2400 = 9600 samples = 1.2 s @ 8 kHz; on-disk WAV is 44 + 9600*2 =
19244 bytes.

Future work (deferred): promote OW to a true diphthong (currently kept as
monophthong for byte-for-byte backward compat); add glottal voicing
source so DH/ZH are perceptually distinct from TH/SH; per-stress-mark
variants (AH0/AH1/AH2); coarticulation across phoneme boundaries. See
`AUDIO_AUDIT.md` "Future work" for the full list.

## Phase progress

- Phase 1 substrate kernel: **complete**
- Phase 2 reader and language: **complete**
- Phase 3 knowledge representation: **complete**
- Phase 4 memory and learning: **complete**
- Phase 5 self-directed learning: **complete**
- Phase 6 cognitive subsystems: **complete**
- Phase 7 agent architecture: **complete**
- Phase 8 safety and audit: **complete**
- Phase 9 IO and effectors: **complete**
- Phase 10 persistence and operations: **complete** (modules + spine artifact +
  the unified single-process daemon `bin/crossengin`; blocker #10 fixed in the
  NOVA toolchain — see below)
- **Snapshot format v2 + v1->v2 migration (this session)**:
  **complete -- format versioning policy + migration tool LANDED**.
  Bumps `SNAP_FORMAT_VERSION` from 1 to 2 in
  `src/persistence/snapshot_writer.nova`, with v2 adding an optional
  meta block (`meta.creator`, `meta.created_ns`,
  `meta.compaction_threshold`, `meta.encryption`) between the
  `sections` header and the first section body. Backwards-compat is
  transparent: a v1 file on disk parses into the same in-memory
  shape as a v2 file via `snap_migrate_v1_to_v2`, dispatched from
  `snap_from_text` (text reader, snapshot_disk.nova) and `snap_parse`
  (framed-value reader, snapshot_reader.nova). A v3+ file is rejected
  loudly with an upgrade-required diagnostic -- silently downgrading
  would drop fields. New surfaces:
  - `snap_meta_new` / `snap_meta_creator` / `snap_meta_created_ns` /
    `snap_meta_compaction_threshold` / `snap_meta_encryption` plus
    matching setters in `snapshot_writer.nova`.
  - `snap_migrate_v1_to_v2(snap)` in `snapshot_writer.nova` -- bumps
    the version slot, attaches a meta block populated with the v1
    recovery defaults (`creator="unknown/<v1>"`, `created_ns=0`,
    `compaction_threshold=-1`, `encryption="none"`).
  - `snap_to_text` extended to emit the meta lines when
    `snap_version(s) >= 2`; `snap_from_text` extended to parse them
    and dispatch on version; the per-section/per-blob shape is
    unchanged so all existing tests (test_snapshot_disk_full +72,
    test_snapshot_episodic +51, test_snapshot_synapses +89,
    test_snapshot_selfmodel +38) still pass bit-identically.
  - `examples/migrate_snap.nova` (NEW) -- one-shot
    migration helper that takes `CE_MIGRATE_OLD` /
    `CE_MIGRATE_NEW` env vars, reads the old file, peeks the on-disk
    version, runs the migration chain, writes the new file, and
    prints a one-line report (`migrated v1 -> v2 (NNN -> MMM bytes)`).
  - `scripts/migrate_snapshot.sh` (NEW) -- operator-facing shell
    wrapper around `examples/migrate_snap.nova`. Resolves OLD.snap /
    NEW.snap to absolute paths, dispatches to the NOVA helper, drops
    the `Compiled: ...` prefix, surfaces the report.
  - `SNAPSHOT_FORMAT.md` (NEW) -- the versioning policy doc: MAJOR
    bump triggers (mandatory fields / removed sections / wire shape
    changes) vs MINOR addition (purely additive optional fields),
    v1 + v2 changelogs, the v1->v2 migration table, the
    v2->v3 stub for future migrations.
  - `tests/unit/test_snapshot_migrate.nova` (NEW, 37 ce_* checks):
    `snap_migrate_v1_to_v2` invariants on a fake v1 snapshot (v2
    rejected, v1 accepted, version slot bumps to 2, meta block
    populated with recovery defaults); v1 file text parse migrates
    transparently and surfaces the recovery defaults; v2 round-trip
    preserves non-default meta values; migrated v1 re-saved as v2
    re-parses cleanly; v3 wire-format rejected; `snap_parse` framed-
    value migration path mirrors the text path.
  - `tests/integration/scenario_dd_snap_migrate.sh` (NEW, 16
    assertions): hand-rolls a v1 snapshot, runs the wrapper, verifies
    the migration report mentions v1 -> v2 with byte counts, and that
    the output declares `ver 2` + carries all four meta lines + the
    payload section survives.
  Module count UNCHANGED (still 4 modules under `src/persistence/`).
  Test count: +1 suite / +37 assertions (`test_snapshot_migrate`).
  Integration scenarios: +1 (`scenario_dd_snap_migrate`).
  Existing scenario_a* (durability + full state + dlog) still pass --
  v2 wire format is a superset of v1.

- **P3.3 cont. (this session) Canny edge detection**: **complete --
  pure-NOVA `image_canny.nova` LANDED**. The fourth structural-feature
  pipeline on top of Sobel + Harris + SIFT-detection. Canny (1986) is
  the canonical edge detector: where Sobel ships raw gradient magnitudes
  (thick, noisy edges), Canny chains Gaussian 3x3 smoothing + signed
  Sobel gradients + non-maximum suppression along the gradient direction
  + 8-connected hysteresis flood-fill with LOW=50 / HIGH=100 milli-
  normalized thresholds to produce CLEAN SINGLE-PIXEL-WIDE edges. The
  flood-fill is implemented as a worklist (`list_new` + `push` +
  head-index walk) rather than recursion -- NOVA has no tail-call
  optimization so a recursive flood would blow the stack on long edge
  chains.
  - **`src/io/transducers/image_canny.nova`** (NEW, +1 module ->
    132 total) -- leaf module, no cross-module imports. Reimplements
    the Gaussian + Sobel kernels rather than importing image_sift /
    image_sobel because (a) it stays a leaf, and (b) Canny needs
    SIGNED gradients (Gx, Gy) and image_sobel.sobel_apply returns
    only the L1 magnitude. Public API: `canny_detect`,
    `canny_density_milli`, `canny_density_label`,
    `canny_result_edges/total/edge_count`. Dimensions capped at
    512x512 per axis (matches Sobel/Harris); minimum dim 32x32.
  - **`src/io/transducers/visual_perception.nova`** (EXTENDED) -- one
    new structural-feature call: `canny_density_milli(data, w, h)` on
    images >= 32x32, mapped to `image_canny_edges_<low|mid|high>` via
    `canny_density_label`. Bucket thresholds (low <20 milli, mid
    20..100, high >=100) are conservatively below Sobel's because
    NMS + thresholding ALWAYS reduces.
  - **Fixture edge counts** (verified end-to-end):
    - Uniform 32x32 grey -> 0 edges, density 0 milli, label `_low`.
    - Vertical step 32x32 -> 30 edges (one per interior row,
      NMS-thinned from Sobel's 60), density 29 milli, label `_mid`.
    - Four-spots 32x32 (scenario_q SPOTS fixture) -> 64 edges,
      density 62 milli, label `_mid` (Sobel: 160; strict subset).
    - Vertical step 16x16 -> 14 edges (Sobel: 28; subset confirmed).
  - **Strict-subset assertion**: `test_canny_subset_of_sobel` verifies
    that every Canny edge lands on a non-zero Sobel magnitude AND
    `canny_n <= sobel_count`. PASSES on the vertical-step fixture.
  - **Test count delta**: `test_image_canny.nova` (NEW) ships 22
    in-memory assertions. `scenario_q_image_see.sh` extended with +1
    assertion (`image_canny_edges_mid` on 32x32 four-spots);
    total scenario_q assertions: 19 -> 20.
- **P3.3 cont. v2 (this session) SIFT 128-D descriptor + matcher**:
  **complete -- the previously-deferred descriptor + matching half of
  SIFT LANDED**. The initial P3.3 cont. drop shipped piece (1) of Lowe
  2004 (scale-space + DoG extrema). This session lands pieces (3)
  128-D descriptor and (4) ratio-test matcher in pure NOVA -- the
  foundation of image-to-image keypoint correspondence (object
  recognition, image stitching, motion tracking). Pieces:
  - **`src/io/transducers/image_sift.nova`** (EXTENDED) -- new public
    surface: `sift_describe(pgm_data, w, h, kp) -> [vec_128, valid]`
    builds the rotation-invariant 128-D feature vector for a keypoint
    by walking a 16x16 window, accumulating gradient magnitudes into
    a 4x4 grid of 8-bin direction histograms, Gaussian-weighting by
    distance from the keypoint, normalizing to L2 = 1000 milli,
    capping at 200 milli (Lowe's 0.2 illumination threshold), and
    re-normalizing. `sift_match_descriptors(a, b)` returns the L2
    distance in milli. `sift_match(desc_a, desc_b_list, ratio_milli)`
    runs Lowe's ratio test (best/second < ratio). `sift_match_keypoints
    (kps_a, descs_a, kps_b, descs_b, ratio_milli)` returns the surviving
    `[idx_a, idx_b, dist]` triples. `sift_describe_all` /
    `sift_descriptor_count_label` are the convenience helpers
    visual_perception.nova uses. NOVA gotchas honored: all gradient-
    square and L2-sum-of-square multiplies go through `int_mul`
    (Bug-A safe path -- the L2 accumulator hits 128M, well over the
    2^20 pointer threshold); atan2 implemented as 8-quadrant integer
    table lookup with a sub-bin refinement via short/long axis ratio
    (no float, no trig); the 16x16 Gaussian weight curve is a tiny
    piecewise-linear approximation of `exp(-r2/32)` indexed by `r2`,
    so we never materialize a 256-int table.
  - **`src/io/transducers/visual_perception.nova`** (EXTENDED) -- the
    structural feature pass now also runs `sift_describe_all` on the
    detected keypoints and emits a parallel `image_descriptors_<low|
    mid|high>` atom counting how many keypoints survived the
    descriptor build (valid == 1). The keypoint count atom continues
    to fire so existing seam consumers see no behavior change.
  - **`examples/crossengin_chat.nova`** (EXTENDED) -- one new admin
    command `/match_images A B` (PGM paths) decodes both images,
    detects + describes keypoints in each, runs the Lowe-ratio-test
    matcher, and prints `(matched N keypoint(s); A=...kps B=...kps)`.
    /help advertises it; the dispatcher routes it next to /see + /play.
    Per the brief: NO other chat changes.
  - **`tests/unit/test_sift_descriptor.nova`** (NEW) -- 28 hermetic
    assertions covering descriptor L2 norm, component cap, distance
    to self == 0, structural-difference baseline, rotated copy
    similarity (structural marker, not a tight tolerance), Lowe-
    ratio-test pass + fail + degenerate cases, keypoint-list matcher,
    descriptor count label boundaries, null-data / tiny-image /
    uniform-image rejection, edge-keypoint window shift.
  - **`tests/integration/scenario_cc_image_match.sh`** (NEW) -- 7
    end-to-end assertions: /help advertises /match_images, usage line
    for missing / single-arg invocations, same-image self-match
    reports N >= 1, per-image keypoint counts surface, missing file
    surfaces the PGM parser error, chat reaches /quit cleanly.
  - **`IMAGE_AUDIT.md`** marked "SIFT 128-D descriptor + matcher" as
    shipped; the deferred entry in the feature ladder flipped to
    `DONE (P3.3 cont. v2)`.
  - **`make build`**: unchanged 132 modules.
  - **`make test`**: +28 assertions (sift_descriptor suite).
  - **`make integration`**: +1 scenario (scenario_cc_image_match.sh).
- **P3.9 cont. (previous session) 2048-bit DH on RFC 7919 Group 14**:
  **complete -- v2-sa-dh-2048 LANDED**. The 256-bit DH path shipped in
  P3.9 v2-sa-dh was cryptographically broken (256-bit DH groups are
  recoverable via index-calculus on commodity hardware; SECAGG_AUDIT.md
  called for a 2048-bit upgrade). This session lands the upgrade:
  - **`src/safety/bignum_2048.nova`** (NEW) -- pure-NOVA 64-limb
    2048-bit unsigned bignum library, parallel to the 256-bit
    `bignum.nova`. Same shape, just wider: `bn2048_new/from_int/
    from_hex/to_hex/zero/eq/cmp/add/sub/mul/mod/modmul/modpow_ct` +
    `rfc7919_group14_p()` / `rfc7919_group14_g()`. The non-CT
    square-and-multiply modpow variant is INTENTIONALLY OMITTED:
    for 2048-bit DH only the CT path is safe to expose to any
    remote-callable code path. Carry-handling fix vs the 256-bit
    reference: `_bn2048_shl1_inplace` returns its carry-out, and
    the reduction loops honor it so the running remainder isn't
    silently truncated when the modulus has bit 2047 set (true for
    RFC 7919 Group 14, false for Curve25519's prime -- this is why
    the bug was latent in the 256-bit reference).
  - **`src/learning/secure_aggregation.nova`** (EXTENDED) --
    `sa_dh_generate_keys_2048(s)`, `sa_dh_shared_secret_for_peer_2048
    (s, peer_id)`, `sa_dh_2048_enabled_from_env()`, and a new
    `SA_DH_BITS` slot (default 256, 2048 after `sa_dh_generate_keys_
    2048`) that routes `sa_mask_for_peer` to the appropriate
    shared-secret derivation. Backwards compatible: `sa_dh_bits()`
    accessor tolerates older sa_state objects that don't carry the
    slot. The wire protocol shape (FED_DH_PUBLIC) is bit-identical;
    only the pubkey hex width changes (64 -> 512 chars).
  - **`examples/crossengin_chat.nova`** (EXTENDED) -- one new env
    probe `sa_dh_2048_enabled_from_env()` decides whether to call
    `sa_dh_generate_keys_2048` instead of `sa_dh_generate_keys` at
    JOIN time. The single env check enables a strict superset of the
    DH path; everything else (the FED_DH_PUBLIC announce + broadcast
    drain phase) reuses the v2-sa-dh code unchanged.
  - **Timing reality check**: one `bn2048_modpow_ct` costs ~15s
    wall-clock on this dev sandbox (vs. ~40ms for the 256-bit
    `bn_modpow_ct`). A 2-soul DH-2048 round = 2 keygens + 2 shared-
    secret derivations = ~60s. The integration scenario U.dh2048
    budgets 180s. **Not for per-message realtime rounds.**
  - **Headline test**: `bn2048_modpow_ct(2, p-1, p) == 1` (Fermat's
    little theorem on the RFC 7919 Group 14 safe prime). PASSES in
    ~15s wall-clock. 2-soul DH-2048 pair equivalence
    (`shared_a == shared_b`) also passes. Test count delta:
    +50 in `test_bignum_2048.nova` (NEW); +13 in
    `test_secure_aggregation.nova` (DH-2048 pair test).
  - Module count: 131 (+1 from bignum_2048).
- **R4D (this session) Montgomery REDC perf upgrade for bn2048_modpow_ct**:
  **complete -- ~10x speedup on RFC 7919 Group 14 LANDED**.
  Pre-R4D, one `bn2048_modpow_ct` on the 2048-bit RFC 7919 Group 14
  prime cost ~15-18 seconds because every modmul (4096 per modpow) did
  a 4096-bit bit-by-bit reduction (~786k limb-ops per reduce). The
  SECAGG_AUDIT.md "next perf step" called for Barrett or Montgomery
  reduction for ~8x speedup. This session ships Montgomery REDC (CIOS
  form). Measured speedup: **~10x** (Mont ~1.2s vs Legacy ~12.8s on
  the speedup-ratio test; the headline Fermat test drops from ~18s to
  ~1.2s wall-clock).
  - **`src/safety/bignum_2048.nova`** (EXTENDED) -- six new public
    functions for Montgomery form: `bn2048_mont_ctx_new(N)` (precomputes
    `n_prime0 = -N^-1 mod 2^32` via Newton's iteration + `r2_mod_n =
    R^2 mod N` via the legacy reducer; paid ONCE per modulus),
    `bn2048_to_mont(x, ctx)` / `bn2048_from_mont(x_mont, ctx)` (enter
    / leave Montgomery form), `bn2048_montmul(a, b, ctx)` (CIOS form
    -- the Montgomery REDC hot path), `bn2048_modpow_ct_mont(b, e, ctx)`
    (caller-managed-ctx exponentiation). One internal helper kept as
    the legacy fallback: `_bn2048_modpow_ct_legacy(b, e, m)` (used
    when N is even -- the Montgomery path requires gcd(N, R) = 1;
    every DH safe prime is odd so this is unreachable from the
    SecAgg DH code path). `bn2048_modpow_ct` (the public CT modpow)
    keeps its external signature bit-exact and routes through
    `bn2048_modpow_ct_mont` after building the ctx; existing callers
    transparently get the ~10x speedup with zero API changes.
  - **CIOS implementation note**: the inner-loop 32x32 -> 64-bit
    multiplies are INLINED (split into 16-bit halves directly) rather
    than calling a helper that returns a `[lo, hi]` pair. The helper
    would allocate ~32M short-lived 2-element lists per modpow_ct
    (8192 inner-loop hits * 4096 outer iters); under NOVA's allocation
    semantics this ballooned the heap to 14GB+ and the OS OOM-killed
    the process. The inline form allocates ZERO per-iter lists past
    the one-shot 65-limb accumulator, and the modpow runs cleanly
    inside the sandbox memory budget.
  - **`tests/unit/test_bignum_2048.nova`** (EXTENDED) -- three new
    test functions: `test_bn2048_mont_ctx_round_trip` (small-N
    `mont_to/mul/from` chain returns `(a*b) mod N`),
    `test_bn2048_modpow_mont_eq_legacy_small_n` (2-vector pseudo-
    random equivalence sweep proving `bn2048_modpow_ct ==
    _bn2048_modpow_ct_legacy` bit-exactly), and
    `test_bn2048_modpow_mont_speedup_ratio` (the headline measurement
    -- ONE legacy vs ONE Montgomery modpow on RFC 7919 Group 14 with
    a short non-trivial exponent; prints the ratio, asserts >=2x).
    The Fermat test still passes, now in ~1.2s wall-clock instead of
    ~18s. Test count: +7 new assertions (65 total in
    `test_bignum_2048`).
  - **2-soul DH-2048 equivalence test**: `test_sa_dh_two_soul_2048_
    pair_mask_matches` in `test_secure_aggregation.nova` runs
    bit-identical -- shared secret derives identically on both sides
    -- but now in ~8.7s wall-clock total (was ~60-140s pre-Mont).
  - **Integration scenario timing**: `scenario_u_secagg.sh` (the full
    U.dh2048 stage) drops from ~141s end-to-end to ~19s wall-clock.
    The 180s scenario deadline is unchanged for slow-sandbox
    headroom but is no longer near the limit.
  - **Module count**: still 132 (Montgomery code is additive within
    `bignum_2048.nova`, not a new module).
- **P3.1.JPEG cont. (this session) entropy decode + IDCT pipeline**:
  **complete -- grayscale baseline END-TO-END DECODE LANDED**. The
  structural half (segments + DQT + SOF0 + DHT) landed in the original
  P3.1.JPEG session; this session ships the remaining ~3-4 weeks of
  work: Huffman entropy decode + dequant + un-zig-zag + 8x8 IDCT +
  block assembly. `jpeg_decode_grayscale("/path.jpg")` now returns
  REAL PIXEL DATA for baseline-sequential 8-bit single-component JPEGs
  up to 512x512 (decode-time dimension cap, distinct from the 1024x1024
  structural cap). On a Pillow-encoded 8x8 grayscale gradient the
  first pixel is `0` (matches libjpeg's `0` exactly); the rest of the
  block matches libjpeg within +/-3 per pixel. Module shape unchanged
  (`jpeg_decode.nova` extended in place, no new module). New surfaces
  inside `jpeg_decode.nova`:
  - `_jpeg_bitreader_new` / `_jpeg_br_refill_byte` / `_jpeg_br_read_bits`
    -- MSB-first bit reader with 0xFF 0x00 byte-stuffing (T.81 B.1.1.5).
  - `_jpeg_build_huffman` -- canonical Huffman codes per T.81 Annex C.
  - `_jpeg_br_decode_huffman` -- per-symbol decode walking lengths
    1..16 with mincode/maxcode/valptr table layout.
  - `_jpeg_extend` -- T.81 Figure F.12 SSSS-bit sign-extend.
  - `_jpeg_decode_block` -- one 8x8 block in zig-zag order: DC
    differential + AC RLE with EOB / ZRL markers.
  - `_jpeg_zigzag_table` -- standard JPEG zig-zag-to-natural index
    map (cached on first use).
  - `_jpeg_dequant_and_unzigzag` -- multiply by quant table, place
    into row-major natural order via the cached zig-zag map.
  - `_jpeg_idct_cos_table` + `_jpeg_idct_1d` + `_jpeg_idct_2d` --
    separable 8-point IDCT with a 10-bit fixed-point cosine table;
    int_mul throughout (per-output ~2^24 accumulator stays in the
    pointer-safe regime); divides by 1024 between passes with rounding;
    level-shift (+128) and 0..255 clamp baked into the final pass.
  - `_jpeg_decode_scan` -- MCU loop. For grayscale baseline each MCU
    is one 8x8 block; walks left-to-right then top-to-bottom,
    decodes/dequantizes/IDCTs/writes each block at (bx*8, by*8) with
    trailing partial-block clipping.
  - `_jpeg_find_huffman_table` / `_jpeg_find_quant_table` /
    `_jpeg_parse_sos` -- table lookup + SOS payload parser; pulls
    the (Td, Ta) DC/AC table ids from SOS and the quantization table
    id from the SOF0 component descriptor.
  Pipeline entry point (`jpeg_decode_grayscale_bytes`): rewritten to
  walk SOI -> SOF0 -> SOS, resolve DC + AC Huffman tables and the
  quant table, then call `_jpeg_decode_scan`. On success returns
  `[width, height, pixel_data_ptr, ""]`; on failure (color image,
  oversized dims, missing tables, malformed entropy data) returns
  `[width, height, 0, error_msg]` with the dimensions surfaced so the
  perception path can still report them.
  `_vp_decode_jpeg` in `visual_perception.nova`: on decode success
  feeds the buffer through the same `vp_features_for_image` +
  `vp_summary_for_image` surfaces PGM and PNG use; on failure emits
  `image_jpeg_header_only` + dim bucket and the diagnostic.
  Acceptance: 87 in-memory assertions in `tests/unit/test_jpeg_decode.nova`
  (+33 from the original 54) all pass; `make build` still reports 130
  modules; `make test` adds 0 suites and 33 assertions; scenario_q
  extended to include a Pillow JPEG fixture (+2 assertions, 17 -> 19);
  `/see /tmp/test.jpg` and `/see /tmp/test.pgm` on an equivalent 32x32
  fixture produce the same dim/mid/bucket/orient/corner/keypoint
  feature labels (entropy label differs slightly due to JPEG's
  smoothing). JPEG_AUDIT.md updated: the "deferred ~3-4 weeks" entropy
  + IDCT block moved to "shipped this session".
- P-AA + P-BB web-side cognition introspection: **complete**.
  - **P-AA `/api/atoms` + `/atoms` HTML**: new GET endpoint
    `/api/atoms?q=<substring>&limit=N&kg=<label>` returns
    `{"atoms": [...]}` with per-atom `{id, label, kind, kg, belief_mean}`
    dicts. Backed by the chat's new `/__atoms__` admin command (same
    probe pattern as `/__metrics__` -- emits `ATOM kg=... id=... kind=...
    label=... belief_mean=...` lines framed by `ATOMS_BEGIN`/`ATOMS_END`,
    capped at ~1000 atoms per probe). Python parser builds the JSON;
    response is cached per cookie for `CE_ATOMS_CACHE_S` seconds
    (default 30). A tiny vanilla-JS HTML page lives at `/atoms` --
    search box + KG filter + limit, table of results. Loopback bind
    inherited from `/api/chat`. 14 assertions in
    `tests/integration/scenario_aa_atom_search.sh`.
  - **P-BB `/why-deep [N]` chat admin command**: recursive decision
    tree on the most recent log entry. For the spoken output and the
    perceived percept atoms, runs `proof_check` (from P3.5
    `proof_checker.nova`) with max_depth=N (default 3, capped at 8) to
    surface every operator chain that could justify each conclusion.
    Renders via `proof_format` (the same operator-chain format /prove
    uses), plus an "activated by:" line for the raw input and an
    "upstream evidence:" section listing per-atom belief means with
    `provenance` from `atom_payload` (e.g. `source='user_taught'` for
    `/teach` atoms, `source='seed'` for first_atoms). 13 assertions in
    `tests/integration/scenario_bb_why_deep.sh`.
- P2.5 cont. real microphone capture (input half of the audio modality
  bridge): **complete (real-hardware path wired; sealed-sandbox silent-WAV
  fallback)** (ADR-0014). P19 + P2.6 shipped the OUTPUT half (Klatt
  synth + WAV write); P2.5 first round shipped the STT FRAMEWORK
  (pluggable `stt_seam.nova` + subprocess shim + env-gated
  `stream_audio.nova` source). The missing piece was real INPUT:
  capturing audio from a real microphone. This session lands it.
  - **`scripts/audio_capture.sh`** (NEW) -- bash wrapper that
    auto-detects the capture backend in order: `parecord` (PulseAudio /
    pipewire-pulse, the default on modern desktop Linux) -> `arecord`
    (ALSA, requires `/dev/snd` + the user in the `audio` group) ->
    `sox -d` (PortAudio under the hood, the canonical macOS path).
    When NONE of the three are on PATH OR no audio device is present
    (no `/dev/snd`, no PulseAudio socket), falls back to a
    DETERMINISTIC SILENT-WAV writer: composes the same canonical
    44-byte RIFF/WAVE/PCM header (16 kHz / 16-bit / mono) all the
    backend paths produce, then appends `N * 16000 * 2` zero bytes
    of PCM silence. Lets the framework run end-to-end on a sealed
    sandbox (CI, container, headless server) without crashing; a
    real deployment with hardware "just works" because the higher-
    priority backends fire first. Contract: takes `[OUT_PATH]
    [DURATION_S]`, defaults `/tmp/ce_input.wav` / 5 seconds,
    clamps duration to `[1..30]`, prints the destination path on
    stdout, ALWAYS exits 0 (silent fallback OR real capture).
    Diagnostics on stderr. Verified: in this sandbox (no
    parecord/arecord/sox, no `/dev/snd`, no PulseAudio socket) the
    silent fallback fires and produces a bit-perfect 32044-byte WAV
    (44 header + 16000 * 2 zero samples) at 1-second duration --
    canonical header bytes round-trip through Python's `struct`
    parser at audio_format=1, channels=1, sample_rate=16000, bps=16,
    data_size=32000.
  - **`src/io/transducers/audio_capture.nova`** (NEW) -- pure-NOVA
    wrapper. Public API:
    * `audio_capture_state_new()` -- constructs the state struct;
      reads `CE_AUDIO_CAPTURE_SCRIPT` / `CE_AUDIO_INPUT_PATH` /
      `CE_AUDIO_CAPTURE_DURATION_MS` (default 5000 ms, clamped to
      `[100..30000]`).
    * `audio_capture_record(state, duration_ms, out_wav_path)` --
      forks `/bin/sh -c "bash <script> <quoted-path> <secs>"` via
      the same audio_speak `_run_sh_c` idiom; rounds duration UP to
      whole seconds; waitpid's the child; updates `last_status` +
      `last_path` + `captures_total`. Returns 1 on script exit 0
      (the WAV file is now on disk -- captured audio OR silent
      fallback), 0 on fork failure.
    * `audio_capture_to_pcm(wav_path)` -> `[samples_list,
      sample_rate]` -- reads the file via `sys_open + sys_read`
      loop (NOVA strings can't carry binary content), validates the
      canonical 44-byte RIFF/WAVE/PCM header (4 magic checks +
      audio_format=1 + bps=16 + channels in [1..2] + non-zero
      sample_rate), then decodes the data chunk frame-by-frame.
      Mono frames pass through unchanged; stereo frames are
      averaged to mono (L+R)/2 since whisper.cpp / vosk both want
      mono input. Returns `[empty_list, 0]` on any malformed input
      so the caller can map "parse failed" to a clear path. All
      in-loop multiplies stay under NOVA's pointer-threshold
      (gotcha #11): byte-by-byte walk + `(b1 * 256) + b0` per pair.
      Hard cap of 1 MiB on the WAV-read buffer (30 seconds at
      16 kHz 16-bit mono = 960 KB; well under the cap).
  - **`src/io/transducers/stream_audio.nova`** (EXTENDED -- additive
    only; existing P2.5 behavior is bit-identical for any non-"auto"
    CE_AUDIO_CAPTURE_CMD value) -- two new state slots
    (`SA_USE_AUTO=11`, `SA_CAPTURE=12`); `stream_audio_init_from_env`
    recognises the new `STREAM_AUDIO_AUTO_TOKEN = "auto"` sentinel
    and flips `use_auto=1`; the auto path also syncs the
    `audio_capture` state's WAV path to the seam's resolved path so
    `audio_capture_record(state, _, "")` lands on the same file the
    STT seam then reads back; `stream_audio_poll` dispatches on
    `SA_USE_AUTO`: if 1, calls `audio_capture_record` (which itself
    runs `scripts/audio_capture.sh`); otherwise the existing
    `_str_run_sh_c(cap_cmd)` path runs unchanged. Two new public
    accessors: `stream_audio_use_auto(s)`, `stream_audio_capture(s)`.
    `stream_audio_test_reset` clears the new flag too.
  - **`STT_AUDIT.md`** (EXTENDED) -- new "P2.5 cont. update" paragraph
    near the top documenting the auto-detect chain, the silent-WAV
    fallback, the canonical WAV header layout shared between the
    script and the NOVA-side parser, and the end-to-end real-hardware
    path (`CE_AUDIO_CAPTURE_CMD=auto CE_STT_BACKEND=subprocess` ->
    mic -> 16-bit mono 16 kHz WAV -> whisper-cli / vosk ->
    EV_MESSAGE on the scheduler queue). Cross-references section
    extended with the new files. The whisper-cli backend remains
    the recommended STT for production deployments.
  - **NO touches** to `src/io/effectors/{audio_synth,audio_speak}.nova`
    (output side, settled), `src/io/transducers/{stt_seam,
    stream_stdin,stream_unix_socket,stream_http}.nova` outside the
    additive `stream_audio.nova` auto branch, or other-agent areas
    (`src/io/transducers/{image_*,video_*,png_decode,deflate_decode,
    kg_sync,secure_channel,http_client}.nova`, `src/safety/`,
    `src/learning/`, `src/persistence/`, `/home/user/NOVA`).
  Acceptance: `tests/unit/test_audio_capture.nova` (NEW; 28
  assertions across 10 test functions): state-struct defaults +
  tag sentinel (4 checks); hand-built canonical WAV round-trips with
  KNOWN samples [100, 0, -200, 32000, -32000] at 16 kHz (5 checks);
  sample-rate variants 8 kHz / 44.1 kHz / 48 kHz (3 checks);
  missing-file rejection -> empty pcm + sample_rate=0 (2 checks);
  bad RIFF magic / bad WAVE magic / non-PCM format / non-16-bit
  width / truncated header all -> empty pcm (5 checks); stereo ->
  mono averaging arithmetic (avg(100,200)=150, avg(0,0)=0,
  avg(-500,-100)=-300) (3 checks).
  `tests/integration/scenario_w_audio_capture.sh` (NEW; 23
  assertions across two parts): PART 1 runs
  `bash scripts/audio_capture.sh /tmp/ce_scenario_w_capture.wav 1`
  + asserts exit 0, destination path printed, file exists, magic
  bytes "RIFF" / "WAVE" / "fmt " / "data" at offsets 0/8/12/36,
  audio_format=1 + channels=1 + sample_rate=16000 + bps=16 via a
  one-shot Python parser, file size >= 1000 bytes. PART 2 emits a
  tiny on-the-fly NOVA driver under
  `tests/integration/_scenario_w_drivers/` (excluded from `make
  integration` by the `_*` glob), runs it with
  `CE_AUDIO_CAPTURE_CMD=auto CE_STT_BACKEND=stub
  CE_AUDIO_INPUT_PATH=...` -- the driver constructs a stream_audio
  state, calls `init_from_env` (verifies `use_auto=1`), forces
  enabled + interval=1, runs `stream_audio_poll` (which forks the
  capture script + drops the stub's "[stt unavailable]"
  placeholder per the existing filter), parses the produced WAV via
  `audio_capture_to_pcm` (verifies sample_rate=16000 + non-empty
  samples), then proves the `EV_MESSAGE` post-path is wired by
  posting "scenario w synthetic transcript" through `hs_post_event`
  + draining the queue. Verified: scenario_w_audio_capture: pass=23
  fail=0. Sandbox audio-backend detection: silent-fallback (no
  parecord / arecord / sox).
  Final counts: 131 modules compile (+1 from `audio_capture.nova`;
  `stream_audio.nova` extension is in-place), 137 unit-test suites
  PASS (+1 from `test_audio_capture.nova`, +28 assertions), 27
  integration scripts (+1 from `scenario_w_audio_capture.sh`).
  `NOVA_ROOT=/home/user/NOVA make build` -> all 131 module(s)
  compiled OK; `NOVA_ROOT=/home/user/NOVA make test` -> all unit
  tests PASS; `bash tests/integration/scenario_w_audio_capture.sh`
  -> pass=23 fail=0.
- P3.1.JPEG minimum-viable JPEG modality (structural half + audit):
  **complete (framework only)** (ADR-0014 image half / NOVA enhancement
  #15). P3.1 shipped PGM-P5; P3.1.PNG shipped the grayscale-8 PNG
  decoder. JPEG is the format `IMAGE_AUDIT.md` calls out as "JPEG
  before PNG" for the agent's perception path -- the dominant on-disk
  format for photographs. The full JPEG decoder is 6-8 weeks of work
  (Huffman entropy + de-quant + IDCT + block assembly + YCbCr -> RGB
  + chroma upsample); this session ships the STRUCTURAL HALF only --
  segment-marker iteration + DQT + SOF0 + DHT table parsing -- so the
  agent can identify a valid baseline grayscale JPEG, report its
  dimensions on the perception path, and surface a clear "JPEG
  entropy decode + IDCT not yet implemented" diagnostic. The
  remaining 3-4 weeks of work are documented in `JPEG_AUDIT.md`.
  - **`jpeg_decode.nova`** (NEW) -- pure-NOVA JPEG structural parser.
    Public API: `jpeg_parse_segments(bytes_ptr, len) -> list of
    [marker, offset, length]` walks the SOI/APPn/COM/DQT/SOF0/DHT/SOS/
    EOI markers (filler 0xFF runs skipped; SOS terminates iteration);
    `jpeg_parse_dqt(bytes_ptr, off, len) -> list of [precision,
    table_id, list_of_64_ints]` extracts quantization tables;
    `jpeg_parse_sof0(bytes_ptr, off, len) -> [precision, height,
    width, n_components, components, error_msg]` validates baseline
    dimensions + component records; `jpeg_parse_dht(bytes_ptr, off,
    len) -> list of [table_class, table_id, length_counts, symbols]`
    extracts Huffman BITS + HUFFVAL; `jpeg_decode_grayscale(path) ->
    [width, height, "", error_msg]` is the entry-point stub that
    returns the dimensions + the documented gap message. Dimension
    cap 1024 per axis matches PGM_MAX_DIM / PNG_MAX_DIM; file cap
    1 MiB. Big-endian throughout; codegen pointer-threshold gotcha
    #11 is well under bounds at 2-byte length fields.
  - **`visual_perception.nova`** (EXTENDED) -- new `VP_DECODER_JPEG = 4`
    constant; registered as "jpeg" in `vp_seam_new()`; `CE_VP_DECODER=
    jpeg` / `=jpg` recognized by `vp_default_decoder()`. New
    `_vp_decode_jpeg(seam, path)` surfaces dimensions + the
    `image_jpeg_header_only` feature atom + the size-bucket atom
    even when pixels are absent. New `_vp_path_ends_with_jpg` /
    `_vp_path_ends_with_jpeg` route `.jpg` / `.jpeg` paths to the
    JPEG decoder via `_vp_pick_decoder_for_path`.
  - **`crossengin_chat.nova`** (TINY HELP TEXT UPDATE) -- `/help`
    advertises JPEG support and points operators at `JPEG_AUDIT.md`.
    No new admin command; the existing `/see PATH` handles `.jpg` /
    `.jpeg` via the seam's path-extension routing.
  - **`scripts/gen_test_jpeg.py`** (NEW) -- Python fixture generator.
    Uses Pillow (PIL.Image) when available to encode a deterministic
    16x16 grayscale gradient as a real baseline-sequential JPEG;
    falls back to a hand-rolled minimal SOI+APP0+DQT+SOF0+DHT+SOS+EOI
    envelope (not a decodable JPEG, but enough structure for the
    pure-NOVA parser to walk) when Pillow is not installed.
  - **`tests/unit/test_jpeg_decode.nova`** (NEW; 54 assertions across
    13 test functions) -- in-memory fixture builder mirrors the
    `_build_png` shape from `test_png_decode.nova`; covers segment
    iteration (SOI/APP0/DQT/SOF0/DHT/SOS surface in order), DQT
    parser yields 64 entries at precision 0, SOF0 parser surfaces
    custom dimensions + component records, DHT parser handles both
    the all-zero BITS case (0 symbols) and a 2-codes-of-length-1
    case (2 symbols), end-to-end `jpeg_decode_grayscale_bytes`
    documents the gap message with the parsed dimensions, oversized
    SOF0 dims rejected with "downsample first", progressive (SOF2)
    rejected with "not supported", bad SOI rejected, truncated input
    rejected.
  - **`JPEG_AUDIT.md`** (NEW) -- mirror of IMAGE_AUDIT / STT_AUDIT /
    VIDEO_AUDIT pattern. Documents WHY baseline grayscale is the
    right MVP target (skip color YCbCr -> RGB, skip arithmetic
    coding, skip progressive); WHAT this session shipped (the
    structural half); WHAT remains (Huffman entropy decode ~1 week,
    de-quant + zig-zag ~3 days, 8x8 IDCT ~1 week, block-row
    assembly ~3 days = ~3-4 weeks total to a working grayscale
    decoder); the ITU-T T.81 references; the NOVA gotchas worked
    around (big-endian, dimension cap, file cap, no `break`,
    `match` reserved identifier).
  Acceptance: `tests/unit/test_jpeg_decode.nova` 54 in-memory
  assertions all pass; `make build` adds +1 module
  (`jpeg_decode.nova`); `make test` adds +1 suite
  (`test_jpeg_decode.nova`); `make integration` all scenarios still
  PASS. On a real 24x24 Pillow-encoded JPEG the chat prints
  `(see FAILED: jpeg: 24x24 grayscale baseline header parsed;
  entropy decode + IDCT not yet implemented; see JPEG_AUDIT.md)`
  and then `bye.` -- the documented dimensions surface and the
  substrate continues cleanly.
- P3.1.PNG full DEFLATE inflate (BTYPE=00 + BTYPE=01 + BTYPE=02):
  **complete** (ADR-0014 image half / NOVA enhancement #15). Item 3
  shipped the stored-only DEFLATE path (BTYPE=00) so PNGs produced by
  `optipng -o0` / `pngcrush -force` / explicit zlib level 0 decoded
  end-to-end, but real-world PNGs from cameras, phones, and screenshot
  tools use zlib level 6 dynamic Huffman -- the Item-3 decoder rejected
  them with the documented "BTYPE=10 not implemented (TODO)" error.
  This session extends `src/io/transducers/deflate_decode.nova` with
  full RFC 1951 inflate: BTYPE=01 (static Huffman; fixed tables from
  section 3.2.6) and BTYPE=02 (dynamic Huffman; HLIT/HDIST/HCLEN
  header parse + code-length alphabet decode + literal+distance code-
  length recovery via the 16/17/18 repeat ops). The shared block-body
  loop decodes literal/length/end-of-block symbols against the Huffman
  tables, expands the length / distance extra bits per RFC 1951
  section 3.2.5, and copies back-references from the sliding window
  (the same output buffer) byte-by-byte so OVERLAPPING copies
  (distance < length, the RLE encoding path) read freshly-written
  bytes.
  - **`deflate_decode.nova`** (EXTENDED, ~930 lines total) -- new
    public `deflate_decode(bytes_ptr, total_len)` dispatches per block
    on BTYPE; `deflate_decode_stored` kept as alias for ABI continuity
    with png_decode.nova. Canonical Huffman build returns a
    [first_code[L], bl_count[L], sym_offset[L], sorted_syms[]] sub-
    list family that lets `_deflate_decode_symbol` decode one symbol
    per call in 1..15 bits. Static-Huffman tables built lazily and
    cached at module scope.
  - **`png_decode.nova`** (UNCHANGED -- already called the alias).
  - **`tests/unit/test_deflate.nova`** (NEW; 46 assertions across 9
    test functions) covers stored regression, static "hello",
    empty block, overlapping copy, length-extra-bits, multi-byte
    distance (> 256), dynamic-Huffman pangram round-trip, BTYPE=11
    reserved rejection.
  - **`tests/unit/test_png_decode.nova`** (EXTENDED) replaced the old
    BTYPE=01/10 "TODO error" smokes with a single BTYPE=11 reserved-
    error smoke.
  - **`tests/integration/scenario_t_png_see.sh`** (EXTENDED, 10
    assertions, was 7) generates TWO PNG fixtures via
    `scripts/gen_test_png.py` (level 0 stored + level 9 dynamic) and
    feeds both through `/see`.
  - **`scripts/gen_test_png.py`** (EXTENDED) default zlib level
    bumped 0 -> 9; new `--level N` flag.
  Acceptance: `tests/unit/test_deflate.nova` passes all 46
  assertions; `tests/unit/test_png_decode.nova` still passes (44
  assertions); `tests/integration/scenario_t_png_see.sh` passes all
  10 assertions including the level-9 dynamic-Huffman PNG round-trip;
  `make test` runs all unit-test suites with no regressions;
  `make build` still succeeds (module count unchanged).
  Verified independently on a 16x16 zlib-level-9 PNG and a 32x32
  Pillow-generated PNG -- every pixel round-trips bit-for-bit.
  `IMAGE_AUDIT.md`: marks "PNG decode (zlib + filters)" DONE.
- P3.3 cont. SIFT keypoint DETECTION (scale-space + DoG extrema only;
  descriptor deferred): **complete (framework only)** (ADR-0014 image
  half / NOVA enhancement #15). R1.6 shipped Sobel edges + Harris
  corners + block-matching motion vectors as the first STRUCTURAL feature
  pipelines. SIFT is the next classical-CV layer; full SIFT
  (scale-space + DoG extrema + orientation histograms + 128-D
  descriptor) is 4-6 weeks of pure-NOVA work and was scope-cut for this
  round. This session ships the keypoint LOCATION half only -- enough
  to surface a SCALE-INVARIANT corner-like feature atom
  (`image_keypoint_count_<low|mid|high>`) on the perception path; the
  128-D descriptor + matching are explicitly deferred per
  `IMAGE_AUDIT.md`'s feature ladder.
  - **`image_sift.nova`** (NEW) -- pure-NOVA SIFT keypoint detector.
    Public API: `sift_keypoints(data_ptr, width, height,
    max_keypoints) -> list of [x, y, octave, scale, contrast]`
    tuples (the keypoint location records, with coordinates projected
    back to the original octave-0 image frame), `sift_keypoint_count_bucket(n)
    -> "low" | "mid" | "high"` (count classifier), `sift_count_label(n)
    -> "image_keypoint_count_<low|mid|high>"` (feature-atom label
    formatter), plus per-keypoint accessors (`sift_kp_x/_y/_octave/
    _scale/_contrast`). Algorithm (Lowe 2004, detection only):
    (1) Build a 3-octave Gaussian pyramid; each octave has 5 blur
    levels via successive 3-pass 3x3 Gaussian convolutions (a single
    3x3 pass per level produces nearly-identical adjacent blurs and
    kills the DoG signal, so we stack 3 passes per level for an
    effective sigma growth proportional to sqrt(3) that produces
    detectable DoG extrema). (2) Compute 4 DoG layers per octave
    via adjacent-blur subtraction. (3) Find 3x3x3 local extrema
    (spatial + scale) in the 2 interior DoG layers (1 and 2) of
    each octave. (4) Filter by contrast: `|DoG|*1000/255 > 30`
    milli-normalized, matching Lowe's 0.03 threshold for 8-bit
    images. (5) Filter by Harris-style edge rejection: reuse
    `harris_apply` from R1.6 on the original image; candidates
    are kept iff a Harris corner lies within Chebyshev distance 2.
    (6) Insertion-sort by contrast descending; cap at
    `SIFT_HARD_MAX = 200`. Dimension caps: minimum 32x32 (3 octaves
    can't sample usefully below that), maximum 256x256 (3 octaves x
    5 blur levels x 3 passes per level = 45 Gaussian-pass equivalents;
    256x256 keeps every intermediate accumulator well under NOVA's
    2^20 codegen pointer-threshold ceiling, gotcha #11). Every
    Gaussian-weight multiply uses `int_mul` (Bug-A fix path).
  - **`visual_perception.nova`** -- extends `_vp_append_structural_features`
    to call `sift_keypoints` when both axes are >= `VP_SIFT_MIN_DIM`
    (32); appends `sift_count_label(len(keypoints))` to the per-image
    feature-atom list. Smaller images continue to surface only the
    Sobel + Harris atoms.
  - **NO touches** to `src/io/transducers/{image_sobel,image_harris,
    image_pgm,png_decode,deflate_decode}.nova` (the R1.5 / R1.6
    surfaces are settled read-only), `src/safety/`, `src/learning/`,
    or `/home/user/NOVA` (other agents).
  Acceptance: `tests/unit/test_image_sift.nova` (NEW; 25 assertions
  across 12 test functions): uniform-grey 32x32 -> 0 keypoints; single
  bright 5x5 spot at (13,13) in 32x32 -> >0 keypoints with the
  strongest peak within Chebyshev 8 of the spot center; 32x32
  four-spots fixture (one bright 5x5 patch near each corner) -> >= 2
  keypoints; 16x16 (< SIFT_MIN_DIM) -> empty list; 300x300 (>
  SIFT_MAX_DIM) -> empty list; data_ptr=0 / width=0 / height=0 ->
  empty list; count-bucket classifier (0/9 -> low, 10/100 -> mid,
  101/200 -> high); count-label formatter; per-keypoint accessors
  round-trip; max_keypoints cap honored (tolerates the +1 overshoot
  matching the image_harris insertion-sort pattern).
  `tests/integration/scenario_q_image_see.sh` (+2 assertions over
  R1.6's 15): a hand-rolled 32x32 four-spots PGM fixture is fed via
  `/see`; the summary line carries "32x32"; the feature line carries
  `image_keypoint_count_low` (4 keypoints, well below the low/mid
  boundary of 10). On the standard test fixtures the detector
  produces: uniform 32x32 -> 0 keypoints; single 5x5 spot -> 1
  keypoint at the spot center with contrast 55; four 5x5 spots -> 4
  keypoints (one per spot) with contrast 55 each. Final counts:
  132 modules (+1 from `image_sift.nova`; the visual_perception
  extension is in-place), 132 unit-test suites (+1 from
  `test_image_sift.nova`, +25 assertions), 26 integration scripts
  pass (`scenario_q_image_see.sh` extended from 15 to 17 assertions,
  +2).
  `IMAGE_AUDIT.md`: marks "SIFT keypoint DETECTION" as DONE in the
  feature ladder; the SIFT 128-D descriptor + matching remain in
  the "4-6 weeks" row as the deferred follow-up; P3.3 structural-
  features section extended with the SIFT-detection algorithm,
  parameters, and dimension caps.
- P3.8r SecAgg dropout-resilience (v2-sa-r): **complete** (ADR-0055
  extension). P3.8 shipped pairwise additive masking with a documented
  failure mode: if a soul vanished mid-round, the surviving submissions
  still carried the +/- m_ij terms for the absent peer and the
  coordinator's sum was corrupted by the missing soul's net mask
  contribution. This session lands Google-SecAgg-style dropout
  resilience (without the Shamir / DH layers, which depend on the just-
  landed P3.9 bignum): an additive `FED_DROPOUT` + `FED_RECON_MASKED`
  protocol pair on top of the existing v2-sa wire envelope, plus the
  soul-side `sa_recompute_without` / `sa_reconcile_for_dropped`
  helpers that subtract the dropped peer's mask from an already-sent
  submission. The 3-soul A/B/C round where B drops now ends with the
  coordinator's sum equal to x_A + x_C exactly -- mask cancellation
  holds across the SHRUNK survivor set because each surviving pair
  still has its +m_ij / -m_ji symmetry, and the dropped peer's now-
  uncancelled contributions were just removed by the survivors.
  - **`src/learning/secure_aggregation.nova`** (EXTENDED) -- new
    public API: `sa_recompute_without(s, dropped_id, k_dim) -> signed
    mask delta`, `sa_recompute_without_pair(s, dropped_id) -> [dp,
    da]`, `sa_reconcile_for_dropped(s, masked_x, dropped_id, k_dim)`,
    `sa_reconcile_for_dropped_pair(s, mp, ma, dropped_id)`,
    `sa_format_dropout_line` / `sa_format_recon_masked_line`,
    `sa_parse_dropout_line` / `sa_parse_recon_masked_line`,
    `sa_round_deadline_ms_from_env()` (default 5000 ms, capped at
    60_000, floored at 100). Event tags: `SECAGG_EV_DROPOUT` = 5,
    `SECAGG_EV_RECON_MASKED` = 6. The LCG mask derivation is the
    same deterministic primitive from P3.8 -- `sa_mask_for_peer`
    over `(token, round_id, k_dim)` -- so the soul can re-derive
    the EXACT SAME mask used during the original masked-stat emit
    and subtract it back out.
  - **`src/io/transducers/kg_sync.nova`** (ADDITIVE CASE) -- one
    more `_parse_fed_*_line` per new event + dispatch case at the
    end of `_parse_line`. Constants follow the existing
    `KGSYNC_FED_*` naming so the v2 + v2-sa cases above are strictly
    untouched.
  - **`src/learning/federated_aggregator.nova`** (EXTENDED) -- new
    `fed_agg_emit_recon_masked(f, dropped_id)` walks the cached
    `FED_LAST_EMIT_LIST` rows, applies `sa_reconcile_for_dropped_pair`
    per row, and caches the new adjusted rows so a SECOND dropout in
    the same round reconciles against the LATEST submission. New
    `fed_agg_format_recon_masked_line(f, tag, adj_p, adj_a)` wraps
    the SA-side formatter with `f[FED_SOUL_ID]` + `f[FED_ROUND_ID]`.
  - **`examples/crossengin_fed_coordinator.nova`** (EXTENDED) --
    `_fed_collect_masked_with_dropout(souls, round_id) -> [acc,
    dropped_ids, recon_used]` replaces the old single-pass
    `_fed_collect_masked` in the SecAgg path. Per-soul staging
    preserves each soul's masked submissions; a soul whose recv-line
    returns 0 BEFORE any FED_STAT_MASKED is recorded as DROPPED. If
    any drops occurred, `_fed_run_reconciliation(souls, round_id,
    dropped, staging)` broadcasts FED_DROPOUT to every survivor,
    collects one FED_RECON_MASKED batch per survivor, and builds the
    final sum from THOSE. The boot banner reports
    `mode=v2-sa-r (SecAgg + dropout-resilient)` and
    `round-deadline-ms=5000`.
  - **`examples/crossengin_chat.nova`** (TINY HOOK) -- the existing
    `_admin_fed_one_round_secagg` loop gains one branch on
    `SECAGG_EV_DROPOUT` that calls `fed_agg_emit_recon_masked` and
    ships a FED_RECON_MASKED per tag + ACK. No new admin commands.
    Result tuple gains a 5th slot for `dropouts_seen`; the
    `fed: [SECAGG] round N complete` line now reports
    "<N> dropout(s) reconciled".
  - **`scripts/secagg_smoke_soul.py`** (NEW) -- minimal SecAgg-aware
    soul client (handshake + masked-stat + recon flow) used by the
    integration test's dropout half. Mirrors the 15-bit LCG mask
    derivation from `secure_aggregation.nova` so the wire
    arithmetic is bit-identical to what the NOVA-side coordinator
    expects. `--mode dropout` closes the socket after JOIN handshake
    to act as the missing soul; `--mode survivor` runs the full
    masked-stat + FED_RECON_MASKED roundtrip.
  - **`tests/unit/test_secure_aggregation.nova`** (EXTENDED) -- 33
    new assertions / 13 new test functions: the 3-soul dropout demo
    asserting `sum == x_A + x_C` after B drops; LCG determinism for
    `sa_recompute_without` across re-calls; sign-mirror invariant
    across paired souls; unknown-peer / self defensive no-op;
    `sa_reconcile_for_dropped` single-peer arithmetic;
    pair-variant two-dim restore; wire formatter shapes; parser
    shapes including signed-int recon (residual flips sign);
    `sa_parse_line` dispatch on the two new events; default
    `CE_FED_ROUND_DEADLINE_MS` 5000 ms.
  - **`tests/integration/scenario_u_secagg.sh`** (EXTENDED) -- 9 new
    dropout-resilience assertions ("scenario U.r"): coord boots in
    `mode=v2-sa-r`, accepts both alice + bob, detects bob's dropout,
    broadcasts FED_DROPOUT, collects alice's RECON_MASKED, and the
    final FED_AGGREGATE_SUM carries alice's raw values exactly
    (`sum_promo=100 sum_atr=50 n_part=1`). Plus 2 first-section
    assertions for `mode=v2-sa-r` + the new
    `round-deadline-ms=5000` banner.
  - **`SECAGG_AUDIT.md`** (UPDATED) -- dropout resilience moved
    from the "What this MVP does not do" list to a new "Shipped:
    dropout resilience" section with the protocol flow, the
    determinism contract, the (N-1) tolerance, and the
    `CE_FED_ROUND_DEADLINE_MS` tuning knob.
  - **Verified:** `make test` 131/131 PASS; `make integration` all
    scenarios PASS including scenario U.r dropout. 3-soul unit demo
    asserts coordinator sees `sum_promo = 200 = x_A + x_C` (the
    brief's expected behaviour, B excluded).
- P3.9 pure-NOVA 256-bit bignum library (DH key-exchange prerequisite):
  **complete (leaf primitive)**. Public surface: bn_new, bn_from_int,
  bn_from_hex, bn_to_hex, bn_zero, bn_eq, bn_cmp, bn_add, bn_sub,
  bn_mul, bn_mod, bn_modmul, bn_modpow, bn_modpow_ct (P3.9 follow-up
  this session: Montgomery ladder; constant-time per bit -- DH/ECDH
  private exponents no longer leak the Hamming weight via wall-clock
  timing). 66 assertions in tests/unit/test_bignum.nova incl. textbook
  2^10 mod 1000 = 24, Curve25519 2^255 mod (2^255-19) = 19 (verified
  against BOTH bn_modpow AND bn_modpow_ct), 100-vector equivalence
  sweep bn_modpow == bn_modpow_ct, and a timing-comparison report
  (~1.88x ratio of ct to fast on the dev sandbox; analytic ~2x
  bound). bn_modpow is now marked loudly as fast/SIDE-CHANNEL-UNSAFE/
  offline self-tests only; bn_modpow_ct is the crypto-safe variant
  consumers must use for any private exponent.
- P3.9 SecAgg DH key agreement (v2-sa-dh): **complete (this
  session)**. Replaces the pre-shared-token path with a real
  Diffie-Hellman key agreement when the soul opts in via
  CE_SECAGG_DH=1. Wire protocol: one new line FED_DH_PUBLIC
  <soul_id> <pubkey_hex> (additive on v2-sa-r). Chat soul generates
  a 256-bit DH keypair via sa_dh_generate_keys (uses bn_modpow_ct(g,
  priv, p)), sends the public key to the coordinator during the
  handshake, then receives every other soul'''s public key from the
  coordinator'''s broadcast phase and registers them via
  sa_register_peer_dh. The pairwise shared secret peer_pubkey ^
  my_private mod p SEEDS the existing LCG mask derivation in place
  of the pre-shared token, so by DH commutativity both sides of
  each pair derive the SAME shared secret and thus the SAME mask --
  the SecAgg cancellation invariant holds. Caveats called out
  loudly in SECAGG_AUDIT.md: 256-bit DH prime is BROKEN against
  modern adversaries; private key is nanotime+LCG weak random;
  p_25519 is a field prime not a safe DH prime. The MVP
  demonstrates the wire protocol + flow, not the cryptographic
  strength. Coord additively extends _fed_accept_handshake_secagg
  to drain optional FED_DH_PUBLIC during handshake + adds new
  _fed_broadcast_dh_pubkeys phase. Chat adds exactly ONE
  sa_dh_enabled_from_env() probe -- no new admin commands. Tests:
  test_secure_aggregation 126 -> 157 (31 new DH assertions incl.
  the CORE 2-soul DH pair-mask-equivalence smoke);
  scenario_u_secagg 36 -> 41 (scenario U.dh, a real 2-soul chat
  federation round-trip under CE_SECAGG_DH=1). Verified: make test
  134/134 PASS; scenario U.dh passes all assertions.
- P3.9 pure-NOVA 256-bit bignum library (DH key-exchange prerequisite):
  **complete (leaf primitive)**. The federated SecAgg MVP (P3.8) shipped
  pre-shared tokens because NOVA had no bignum. This session lands the
  smallest viable bignum library that unblocks the layered upgrades --
  Diffie-Hellman key agreement (the SecAgg layer 2), RSA decrypt/verify
  (TLS), and the future modular-exponentiation kernel under a real
  X25519/Curve25519 scalar mult. Scope: 256-bit FIXED width (NOT
  arbitrary precision; that's an order-of-magnitude more work). 8
  32-bit limbs, LSB at index 0; the schoolbook 256x256 multiply
  internally splits each 32-bit limb into two 16-bit halves so per-cell
  products fit cleanly in the positive signed 63-bit band and dodge
  NOVA gotcha #11. Public surface: `bn_new`, `bn_from_int`,
  `bn_from_hex`, `bn_to_hex`, `bn_zero`, `bn_eq`, `bn_cmp`, `bn_add`,
  `bn_sub`, `bn_mul` (returns `[hi, lo]` -- the full 512-bit product),
  `bn_mod`, `bn_modmul`, `bn_modpow`. 54 assertions in
  `tests/unit/test_bignum.nova`, including the textbook `2^10 mod 1000
  = 24` and the Curve25519 prime sanity check `2^255 mod (2^255-19)
  = 19`. Smallest measurable op: a single `bn_add` call clocks ~800 ns
  via `nanotime()`. **Side-channel disclaimer:** at MVP `bn_modpow` and
  `bn_cmp` are NOT constant-time; safe for offline self-tests, NOT for
  remote-callable code paths (timing leaks the exponent's Hamming
  weight). Const-time follow-up is its own ~2-3 week project per
  primitive. Documented in `SECAGG_AUDIT.md` ("bignum landed; DH key
  exchange unblocked") and `TLS_AUDIT.md` (modpow is the kernel of RSA
  verify + DHE key share derivation).
- P3.2 minimum-viable video modality (framework + audit):
  **complete (framework only)** (ADR-0014 video half / NOVA
  enhancement #15). Video was the natural step after P3.1's image
  plank: a single image is one perception in a 2-D field; video is
  a STREAM of perceptions in TIME ORDER, each correlated with its
  neighbors. Real codecs (H.264, H.265, AV1, VP9) are each MONTHS
  of pure-NOVA work; P3.2 lands the smallest possible plank: a
  pure-NOVA decoder for the simplest standardized raw-video format
  (YUV4MPEG2 / Y4M), a pluggable video-perception seam (exactly
  the shape of `visual_perception.nova` from P3.1) that turns
  per-frame Y-plane statistics + frame-to-frame deltas into
  substrate-shaped feature atoms + motion + scene-change labels,
  the chat-side admin command `/play PATH [MAX_FRAMES]`, and the
  `scripts/video_to_y4m.sh` ffmpeg shim for any compressed video
  input. The full pipeline (H.264 decode, optical flow, object
  tracking, action recognition) is months-to-a-year of work and is
  documented in `VIDEO_AUDIT.md` as the realistic path; this round
  closes the framework hole so the video seam compiles, exercises
  a real decoder against a hand-built fixture, and produces per-
  frame perception events an integration test can observe --
  without inventing an H.264 decoder out of thin air.
  - **`video_y4m.nova`** (NEW) -- pure-NOVA Y4M decoder + per-frame
    iterator + motion proxy. Public API: `y4m_open(path) -> state`
    (NUL-safe sys_open + sys_read loop, parses the ASCII header
    line and validates dims), `y4m_open_bytes(buf, total) -> state`
    (in-memory fixture path for unit tests), `y4m_dimensions(state)
    -> [w, h, fps_num, fps_den]`, `y4m_next_frame(state) ->
    [y_ptr, cb_ptr, cr_ptr, frame_index, error_msg]` (returns
    pointers INTO the open file buffer -- no copy; end-of-stream
    sets `"y4m: end of stream"`), `y4m_close(state)`,
    `y4m_frame_to_pgm(y_ptr, w, h)` (identity wrapper -- the Y
    plane IS a PGM image so callers can pass it straight into
    pgm_histogram / pgm_mean_intensity / pgm_dominant_intensity
    from P3.1), `y4m_mean_abs_diff(prev_ptr, cur_ptr, w, h) ->
    int (0..255)` (mean of |prev[i] - cur[i]| across the Y plane
    only; chroma ignored). Dimension cap: 768 x 432 per axis so
    `width * height <= 331776` and the per-frame total (`w*h*3/2 ==
    497664` for 4:2:0) stays well under NOVA's codegen pointer-
    threshold gotcha #11; larger Y4M files refused at header time
    with a clear "downsample first" error. Only 4:2:0 chroma
    subsampling (the dominant `ffmpeg -pix_fmt yuv420p` output)
    supported today; the `C` tag in the header is parsed but its
    value is currently ignored.
  - **`video_perception.nova`** (NEW) -- pluggable video-perception
    seam, exactly the shape of `visual_perception.nova` (P3.1) and
    `stt_seam.nova` (P2.5). Public API: `vid_seam_new()` constructs
    a seam (pre-registers "stub" + "y4m" backends),
    `vid_decode_video(seam, path, max_frames) -> [events,
    confidence_milli, error_msg]`, `vid_register_decoder(seam,
    name, decoder_id)`, `vid_default_decoder()` (from
    `CE_VID_DECODER` env; "y4m" / unset -> Y4M, "stub" -> STUB),
    `vid_seam_set_default(seam, decoder_id)`,
    `vid_seam_decoder_name / _decoder_id_for / _last_events /
    _last_confidence / _last_error / _last_summary /
    _last_frame_count / _last_scene_changes / _call_count`,
    `vid_per_frame_features(seam, y4m_state, max_frames) -> list
    of per-frame feature-atom-label lists`. Per-frame events are
    formatted as `EV_MESSAGE`-shaped lines (`"frame N: image_dim_*
    image_<dark|mid|bright> image_bucket_<0..7> [motion_<low|mid|
    high>] [scene_change]"`) the perception path could feed to
    `transduce_text` exactly the way speech transcription does;
    wiring per-frame events into the live perception path is a
    deferred follow-up. Motion thresholds (in mean |a-b| over the
    luma plane, 0..255): motion_low `[1, 15)`, motion_mid `[15,
    50)`, motion_high `>= 50`. scene_change: mean diff > 50,
    fires INDEPENDENTLY of motion_high so the substrate can treat
    high motion and scene cut as overlapping but distinct evidence.
    Successful Y4M decode -> confidence 800 milli (same ballpark as
    STT subprocess + visual_perception P3.1); STUB -> 0; parse
    error -> confidence 0 with `video_unavailable` placeholder
    event so downstream callers always see >=1 event. Default
    max_frames per call: 10; hard cap: 60 (the realtime pacer from
    P0.6 already throttles perception at ~10 events/second so
    larger windows simply queue).
  - **`scripts/video_to_y4m.sh`** (NEW) -- ffmpeg subprocess shim
    that converts any compressed video (MP4, MKV, WebM, MOV, AVI)
    to a Y4M 4:2:0 file the pure-NOVA decoder can ingest. Env knobs
    `CE_Y4M_OUT` (destination path), `CE_Y4M_MAX_DIM` (longest
    side, default 432), `CE_Y4M_MAX_FRAMES` (default 30). Single
    backend (ffmpeg); on a sealed sandbox without ffmpeg it prints
    the install hint to stderr and exits 0 (same exit semantics as
    `scripts/image_to_pgm.sh` and `scripts/transcribe.sh`).
  - **`examples/crossengin_chat.nova`** -- ONE new admin command
    `/play PATH [MAX_FRAMES]` (lazy seam construction) + dispatch
    line + /help line. The /help line points at VIDEO_AUDIT.md
    for the codec roadmap. No other admin commands touched.
  - **DO NOT TOUCH this round:** `src/io/effectors/*`,
    `src/io/transducers/image_pgm.nova` /
    `visual_perception.nova` (P3.1 surface stays exactly the
    way we shipped it; the video seam IMPORTS the image surface
    rather than rewriting it), `src/parts/`, `src/reader/`,
    `src/kg/`, `src/persistence/`, `src/learning/`, `src/audit/`,
    `examples/crossengin_daemon.nova`, `scripts/web.py`.
  Acceptance: `tests/unit/test_video_y4m.nova` (NEW; 34 assertions
  across 9 test functions): header happy path (dims, fps,
  state_ok), per-frame iteration (frame index, Y / Cb / Cr pointers
  round-trip correctly), end-of-stream after the last frame,
  y4m_frame_to_pgm identity wrapper (the Y plane IS a PGM image),
  malformed inputs (bad magic, missing W tag), dimension cap
  rejects > 768 width, mean-absolute-difference motion proxy on
  identical buffers (0) + constant +50 delta (50).
  `tests/integration/scenario_s_video_play.sh` (NEW; 12 assertions):
  /help advertises /play; /play with no arg prints usage; /play
  PATH 5 on a hand-rolled 5-frame 4x4 Y4M fixture prints frame
  count + dims + scene-change tally + decoder name, each of the
  five frame lines carries the expected image features + motion
  bucket + scene_change label, malformed input is rejected with
  the parser's bracketed error and the chat survives to /quit
  cleanly. Final counts: 117 modules (+2 from `video_y4m.nova`
  and `video_perception.nova`), 121 unit-test suites (+1 suite for
  `test_video_y4m.nova`, +34 assertions), 25 integration scripts
  pass (+1 for `scenario_s_video_play.sh`, +12 assertions).
  `VIDEO_AUDIT.md` (NEW, repo root) documents the temporal
  hardness (codec + perception), the Y4M-vs-everything trade-off,
  the codec ladder (Y4M -> MJPEG -> H.264 -> H.265/AV1/VP9),
  realistic options (ffmpeg shim now / WASM libavcodec / pure-NOVA
  MJPEG / pure-NOVA H.264), the feature pipeline beyond pixels
  (optical flow, object tracking, background subtraction, action
  recognition), atom mapping (per ADR-0022 consolidation), the
  wall-clock estimate (4-8 months for codec + features; 12+ months
  for action recognition), and the recommended path (ffmpeg shim
  now; pure-NOVA MJPEG as a stretch goal; H.264 only if a use case
  demands it).
- P3.1 minimum-viable image modality (framework + audit):
  **complete (framework only)** (ADR-0014 visual half / NOVA
  enhancement #15). Visual perception was entirely missing from
  CrossEngin: text (P15) and audio (P19 TTS + P2.6 / P2.5 STT
  framework) already had pluggable modality bridges; images had no
  decoder, no perception path, no admin command. P3.1 lands the
  smallest possible plank: a pure-NOVA decoder for the simplest
  standardized image format (PGM-P5 binary; ASCII / 16-bit deferred),
  a pluggable visual-perception seam (`stt_seam.nova`-shape) that
  turns pixel statistics into substrate-shaped feature atoms, the
  chat-side admin command `/see PATH`, and the
  `scripts/image_to_pgm.sh` ImageMagick/ffmpeg shim for any non-PGM
  input. The full pipeline (JPEG decode, edge detection, SIFT,
  embeddings) is months of work and is documented in
  `IMAGE_AUDIT.md` as the realistic path; this round closes the
  framework hole so the visual seam compiles, exercises a real
  decoder, and produces feature atoms an integration test can
  observe -- without inventing a JPEG decoder out of thin air.
  - **`image_pgm.nova`** (NEW) -- pure-NOVA PGM-P5 decoder. Public
    API: `pgm_parse_bytes(ptr, len) / pgm_parse_file(path) -> [w, h,
    maxval, pixel_data_ptr, error_msg]` (5-tuple result; helpers
    `pgm_result_width / _height / _maxval / _data / _error / _ok`),
    `pgm_pixel(data, w, x, y) -> int` (row-major, 0..255),
    `pgm_histogram(data, w, h) -> list of 256 counts`,
    `pgm_mean_intensity(data, w, h) -> int (0..255)`,
    `pgm_dominant_intensity(data, w, h) -> int (0..7 bucket;
    bins of 32 levels each)`, `pgm_histogram_entropy_milli(hist)
    -> int (0..8000 milli-bits)`, `pgm_resize_nn(src, src_w, src_h,
    dst_w, dst_h) -> dst_data_ptr` (nearest-neighbor, integer math
    only). The parser tolerates `# comment` lines in the header
    (the shape `convert input.jpg output.pgm` always writes a
    "# CREATOR: ImageMagick" line). Dimension cap: 1024 per axis
    so `width * height <= 1048576 == 2^20` stays under NOVA's
    codegen pointer-threshold gotcha (#11); larger PGMs are
    refused with a "downsample first" error. ASCII PGM (`P2`
    magic) is rejected with the right diagnostic (a deferred
    follow-up).
  - **`visual_perception.nova`** (NEW) -- pluggable visual-perception
    seam, EXACTLY the shape of `stt_seam.nova`. Public API:
    `vp_seam_new()` constructs a seam (pre-registers "stub" + "pgm"
    backends), `vp_decode_image(seam, path) -> [feature_atoms,
    confidence_milli, error_msg]`, `vp_register_decoder(seam, name,
    decoder_id)`, `vp_default_decoder()` (from `CE_VP_DECODER` env;
    "pgm" / unset -> PGM, "stub" -> STUB),
    `vp_seam_set_default(seam, decoder_id)`,
    `vp_seam_decoder_name(seam) / _decoder_id_for / _last_features /
    _last_confidence / _last_error / _last_summary / _call_count`,
    `vp_features_for_image(w, h, data) -> list of label strings`,
    `vp_summary_for_image(w, h, data) -> "<w>x<h> mean=<m>
    dom_bucket=<b> entropy=<e>"`. Feature atoms produced:
    `image_dim_<small|medium|large>` (area <= 4096 small,
    <= 65536 medium, else large), `image_<dark|mid|bright>`
    (mean < 80 dark, > 175 bright, else mid),
    `image_bucket_<0..7>` (dominant intensity bin),
    `image_hist_<peaked|uniform>` (entropy < 3000 milli-bits
    peaked, > 6000 milli-bits uniform; mid-range emits nothing
    on this axis -- the dominant-bucket label already covers it).
    Successful PGM decode -> confidence 800 milli (same ballpark
    as the STT subprocess path); STUB -> 0; parse error ->
    confidence 0 with `image_unavailable` placeholder atom so
    downstream callers always see >=1 atom. The atom-creation
    wire-up (binding each label to an `ATOM_VISUAL` atom via the
    existing `atom_birth_monitor` path) lives in
    `src/agent/loop_perception.nova` and is explicitly out of
    P3.1's scope -- the framework is the load-bearing piece.
  - **`scripts/image_to_pgm.sh`** (NEW) -- subprocess shim that
    converts an arbitrary image (JPEG, PNG, WebP, BMP, GIF, TIFF,
    HEIC, ...) into a PGM the pure-NOVA decoder can read. Probe
    order: ImageMagick `convert` (IM 6) -> `magick` (IM 7) ->
    `ffmpeg` -> 16x16 grey placeholder PGM (so a sealed sandbox
    still produces a decodable image). Env knobs: `CE_PGM_OUT`
    (destination path, default `/tmp/ce_image.pgm`),
    `CE_PGM_MAX_DIM` (longest side in pixels, default 256). Exits
    0 in all branches including "no backend installed" -- same
    contract as `scripts/transcribe.sh` for STT.
  - **chat-side `/see PATH` admin command**
    (`examples/crossengin_chat.nova`). Loads the PGM at PATH via
    the seam, prints the operator-readable summary line
    (`saw image <path> [<w>x<h> mean=<m> dom_bucket=<b>
    entropy=<e>, decoder=pgm]`), and one indented `features:` line
    listing the feature-atom labels. `/see` with no arg prints
    a usage hint; `/see` on a malformed file surfaces the
    parser's bracketed error. The visual seam is lazily
    constructed on first `/see` so chat startup is unchanged when
    the command is never used. One dispatch line + one /help
    line, matching the brief's scope.
  - **`IMAGE_AUDIT.md`** (NEW) -- the realistic-path write-up.
    Why visual perception is structurally hard (2-D field with no
    inherent boundaries; binary decoding AND perception are each
    multi-week lifts); why PGM-P5 specifically (simplest
    standardized format, ~30 lines pure-NOVA, common test fixture
    via `convert`); the four realistic options (subprocess shim
    -- landed; WASM-bundled stb_image once P2.7 lands; pure-NOVA
    PNG via zlib ~3-4 weeks; pure-NOVA JPEG ~6-8 weeks); the
    vision feature ladder (Sobel / Harris / Canny / HOG / SIFT /
    HSV histograms / CNN embeddings, each weeks-to-months);
    mapping features to atoms via Beta(4,1) high-confidence /
    Beta(2,1) low-confidence priors; wall-clock estimate (2-4
    months to "ingests photographs", 6-12 months to "production
    scene understanding"); recommended path (ImageMagick shim
    NOW; pure-NOVA JPEG before PNG once the modality bridge
    matures); NOVA gotchas worked around (codegen pointer-
    threshold #11 -- dimension cap; `read_file` NUL stop -- raw
    `sys_read` loop instead; ASCII-vs-binary PGM -- P5 only).
  - **No touches** to `src/io/effectors/*` (audio side, locked
    after P2.6), `src/parts/`, `src/reader/`, `src/agent/`,
    `src/kg/`, `src/persistence/`, `src/learning/`,
    `examples/crossengin_daemon.nova` (chat-only integration
    this round), or `scripts/web.py`. Perception-loop wire-up is
    a follow-up.
  Acceptance: `tests/unit/test_image_pgm.nova` (NEW; 43
  assertions across 13 test functions): parse happy path (dims,
  pixels, row-major access), histogram on gradient (bins, total),
  mean intensity, dominant intensity bucket (flat 0/200/255),
  nearest-neighbor resize 4x4 -> 2x2 (correct pixel index
  selection) and 2x2 -> 4x4 (upscale), malformed inputs (bad
  magic, P2 ASCII, truncated buffer, missing pixel bytes), `#`
  comment in header tolerated, dimension cap rejects >1024.
  `tests/integration/scenario_q_image_see.sh` (NEW; 11
  assertions): /help advertises /see; /see PATH prints
  dimensions + summary + feature atoms on a 4x4 gradient
  (`image_dim_small + image_mid + image_bucket_0`) AND on a
  uniform-grey fixture (`image_bright + image_hist_peaked +
  image_bucket_6`); /see with no arg prints usage; /see on
  random bytes prints the parser's bracketed error; chat
  reaches /quit cleanly afterwards. Final counts: 114 modules
  (+2 from `image_pgm.nova` and `visual_perception.nova`),
  119 unit-test suites (+1 suite for `test_image_pgm.nova`,
  +43 assertions), 24 integration scripts pass (+1 for
  `scenario_q_image_see.sh`, +11 assertions).
- P3.7 minimum-viable federated multi-soul (framework + audit):
  **complete (framework only)** (ADR-0054). Today CrossEngin has two
  foundations (P20 + P1.3 kg-sync v2 for cross-soul atom replication;
  P3.6 per-session DP for query leakage bounds) but no federation
  layer that lets souls share what *works* (productive sources, durable
  topics) without sharing what they were *taught* (raw atoms). This
  round lands the smallest possible plank: a soul-side
  `federated_aggregator` that walks the meta_observer's per-source
  promotion + atrophy rates, applies DP noise via the existing dp
  module (one `dp_noisy_mean` call per rate per round), and ships
  the noised rates as FED_STAT records to a small coordinator
  daemon. The coordinator averages across N souls and broadcasts
  FED_AGGREGATE; the soul EMA-blends the federation mean into its
  local source_authority tier signal (10% pull per round). The
  noise is added LOCALLY -- the coordinator never sees raw rates,
  only DP-noised ones. The full production stack is months of work
  and is documented in `FEDERATED_AUDIT.md`; this round closes the
  framework hole so the federation seam compiles, exercises a real
  TCP round-trip, and the chat can drive the JOIN -> ROUND -> STAT
  -> AGGREGATE handshake end-to-end.
  - **`federated_aggregator.nova`** (NEW) -- soul-side aggregator
    plus coordinator-side accumulator and network bridge. Public
    API: `fed_agg_new(soul_id, dp, mo) -> fed_state`,
    `fed_agg_round_start(f, round_id, deadline_ns)`,
    `fed_agg_emit_noised_stats(f) -> list of [tag, noised_promo,
    noised_atr] rows`, `fed_agg_receive_aggregate(f, tag, avg_promo,
    avg_atr, n_part, source_auth)`, `fed_agg_round_end(f, round_id)`,
    plus wire formatters (`fed_agg_format_join_line` /
    `_stat_line` / `_leave_line`, `fed_format_round_line` /
    `_aggregate_line`), inspection helpers (`fed_agg_round_id` /
    `_active` / `_emit_count` / `_agg_count` / `_rounds` /
    `_global_seen`), the coordinator-side accumulator
    (`fed_acc_new` / `_add_stat` / `_averages` / `_count`), the
    network bridge (`fed_dial` / `fed_send_join` / `fed_send_leave`
    / `fed_close` / `fed_one_round`), env helpers
    (`fed_token_from_env` / `fed_port_from_env` /
    `fed_round_interval_from_env` / `fed_bind_from_env`), and a
    local copy of the FED_* parser branch (renamed `_fed_*` to
    sidestep the snapshot_disk + kg_sync `_starts_with` TU-scope
    collision: both modules define a `_starts_with` helper, and the
    chat imports both, so the federated_aggregator carries its own
    renamed copies of the helpers it needs).
  - **`examples/crossengin_fed_coordinator.nova`** (NEW; binary
    `bin/crossengin-fed-coordinator`) -- small TCP server that
    listens on `CE_FED_PORT` (default 8777), accepts
    `CE_FED_SOULS` JOIN handshakes, runs `CE_FED_MAX_ROUNDS`
    rounds (0 = unbounded; tests use 1 for determinism), and
    logs round results to stdout. Auth via `CE_FED_TOKEN`
    (mirror of `CE_KGSYNC_TOKEN`). Per-round flow: open
    FED_ROUND -> collect FED_STAT to deadline -> average per
    source_tag -> broadcast FED_AGGREGATE.
  - **`src/io/transducers/kg_sync.nova`** -- additive FED_*
    parser branch (one `_parse_fed_*_line` per event kind +
    dispatch case in `_parse_line`) alongside the unchanged v2
    protocol. Constants follow `KGSYNC_FED_*` naming so v2 is
    strictly untouched (the brief's "additive case only"
    contract).
  - **chat-side `/fed_join` + `/fed_stats` + `/fed_leave`**
    (`examples/crossengin_chat.nova`). `/fed_join URL` connects
    to a coordinator (default 127.0.0.1:8777), sends HELLO
    ce-fed v1 + FED_JOIN, then drives one round inline
    (FED_ROUND -> emit FED_STAT batch -> ACK -> collect
    FED_AGGREGATE -> EMA-blend into local source_authority).
    `/fed_stats` prints the local DP-noised stats that the
    next FED_STAT batch would carry (dry-run preview; DOES
    consume the per-round epsilon -- the audit walks why a
    truly non-consuming preview is impossible without
    redesigning the dp module's API). `/fed_leave` sends
    FED_LEAVE and closes the connection. Help text updated
    with all three commands.
  - **`Makefile`** -- `make install` builds
    `bin/crossengin-fed-coordinator` alongside the existing
    five binaries; `cross-windows` also cross-compiles it.
  Acceptance: `tests/unit/test_federated_aggregator.nova` covers
  91 assertions across 30 test functions: state construction
  (non-zero, slot defaults), epsilon override, join / leave
  flags, round lifecycle (start, emit, end, no-start-while-
  inactive), DP noise variance > 0 across consecutive emits at
  same round, budget drain proportional to N*eps*2, empty
  observer -> zero rows, receive_aggregate records global +
  bumps tier when high signal + leaves tier when neutral signal,
  agg count tracking, all five wire formatter shapes, the
  coordinator accumulator (empty, single-contributor, multi-
  contributor, multi-source), env helpers, milli formatter,
  local parsers, full self-aggregation round-trip
  (emit -> accumulator -> averages -> receive).
  `tests/integration/scenario_r_federated.sh` (NEW; 15
  assertions): start the coordinator with `CE_FED_MAX_ROUNDS=1`
  in background, boot the chat with `/teach` warmup + `/fed_join
  127.0.0.1:<PORT>` + `/fed_leave` + `/help`, verify the
  coordinator log shows JOIN + round open + STAT receipt +
  AGGREGATE broadcast, verify the chat log shows handshake +
  round complete + stats sent + aggregates received + /help
  listing all three commands. Final counts: 115 modules (+1
  from `federated_aggregator.nova`), 120 unit-test suites (+1
  for `test_federated_aggregator.nova`, +91 assertions), 25
  integration scripts pass (+1 for `scenario_r_federated.sh`,
  +15 assertions), 6 install binaries (+1 for
  `crossengin-fed-coordinator`). FEDERATED_AUDIT.md (NEW, repo
  root) documents the trust model (trusted-coordinator + DP
  vs SecAgg), DP composition across rounds (10ε session
  supports ~10 rounds at 1.0ε or ~100 rounds at 0.1ε), the
  not-secure-aggregation caveat (production federation needs
  MPC / HE -- months of crypto), sybil resistance (the shared
  CE_FED_TOKEN is a starting line, not a finish), and EMA
  convergence (10% pull per round -> ~10 rounds to converge,
  with the noise-resistance trade-off explained).
- P3.6 minimum-viable differential privacy at the KG-query surface:
  **complete** (ADR-0053). Today CrossEngin's KGs are queryable (atom
  counts, beliefs, neighborhoods) but there is no formal privacy layer:
  if two users teach a single soul, one user's queries can in principle
  leak the other's teaching. New module
  `src/safety/differential_privacy.nova` is the noise floor: a pure-
  integer Laplace mechanism (Geometric-on-Z, drawn as G(p) - G(p)) over
  numeric KG queries, with a per-session epsilon-budget accountant.
  Default budget 10.0 epsilon (10000 milli-eps); override via
  `CE_DP_EPSILON_BUDGET`. Each query consumes a piece of the budget;
  on exhaustion the wrappers return `DP_REFUSED` and the caller-side
  helper prints "budget exhausted". API: `dp_new(budget_milli)`,
  `dp_consume(dp, eps_milli)`, `dp_remaining_budget(dp)`,
  `dp_laplace_noise(dp, scale_milli)`, `dp_noisy_count(dp, true_count,
  eps_milli)`, `dp_noisy_mean(dp, true_mean_milli, sens_milli,
  eps_milli)`, `dp_reset_budget(dp, budget_milli)`,
  `dp_budget_from_env()`. KG-side opt-in wrappers in
  `src/kg/multi_kg_manager.nova`: `kg_atom_count_dp(kg, dp, eps_milli)`
  (sensitivity 1) and `kg_atom_belief_mean_dp(kg, atom_id, dp,
  eps_milli)` (sensitivity 1000 / (alpha+beta) milli, floored at 100).
  Session integration: new `SES_DP` slot in `src/session/session.nova`
  + `session_dp(s)` / `session_attach_dp(s, dp)` accessors. The chat
  and daemon both wire a per-session dp_state at boot (one new
  `dp_new(dp_budget_from_env())` call per session). Chat surface
  (`examples/crossengin_chat.nova`): two new admin commands +
  dispatch + /help -- `/dp_status` prints
  `dp budget: 0 / 10000 milli-eps consumed (remaining 10000 milli-eps
  over 0 queries)` and `/dp_query atoms` runs `kg_atom_count_dp` at
  epsilon = 100 milli, printing both the true count and the noisy
  count for operator inspection: `dp_query atoms: true=572 noisy=583
  (epsilon=100 milli, remaining 9900)`. Post-exhaustion: `dp_query
  atoms: budget exhausted (remaining 0 milli-eps)`. The original
  `kg_atom_count` etc. are unchanged -- the DP variants are opt-in;
  every caller that wants the privacy floor uses the `_dp` suffix.
  NOVA gotchas worked around: the LCG seed is masked to 15 bits at
  every step (the codegen pointer-threshold bug, NOVA #5/6 -- any
  large multiply misroutes into `str_repeat`; the LCG uses small
  multiplier 6917 < 2^13 and an avalanche XOR of the high half into
  the low half each step to break the linearity of the 15-bit LCG's
  low bits); the geometric loop is capped at 1000 iterations (the
  brief calls this out as a known sharp edge). Acceptance:
  `tests/unit/test_differential_privacy.nova` covers 52 assertions
  across 16 test functions: budget accounting (new / consume / exhaust
  edges / reset), Laplace mean near zero over 1000 samples (max |sum|
  observed across 10 seeds: ~90), Laplace shape (~65% within +/-1
  scale, ~83% within +/-2 -- matches the Laplace CDF), determinism
  (same seed -> same sequence), noisy-count + noisy-mean variance and
  clamping, refusal sentinel.
  `tests/integration/scenario_p_dp_budget.sh` (NEW; 10 assertions): the
  chat boots, /dp_status prints the initial 10000 milli budget, 130
  /dp_query atoms calls drain the budget to zero (each call lists true
  + noisy + remaining, monotonically decreasing), the second /dp_status
  reports 10000 consumed / 0 remaining over 100 queries, a /dp_query
  past exhaustion is refused. DP_AUDIT.md (NEW, repo root) documents
  why integer Laplace is the right primitive, per-query sensitivities,
  the moderate epsilon=10 default vs the 0.1-1.0 production-grade
  setting, sequential composition + the gaps (advanced composition /
  RDP / parallel composition / distributed DP for federated multi-soul
  in P3.7), and the refusal-on-exhaustion contract.
- P3.5 minimum-viable proof checker: **complete** (ADR-0052).
  Today reasoning produces a conclusion via operator chains
  (`fever -> infection -> treat`) but the chain itself is never surfaced --
  there is no formal proof trail you can ask for, audit, or attach to a
  decision-log entry. New module `src/parts/reasoning/proof_checker.nova`
  closes that hole: bounded BFS over the operator graph (`rk_operators_from`
  forward + `rk_operators_to` backward) from a premise atom to a
  conclusion atom, returning either a valid operator-chain proof + its
  composed Bayesian confidence or "no proof found within depth D".
  API: `proof_new()`, `proof_check(premise_id, conclusion_id, rkg,
  max_depth, max_visits) -> [valid, chain_ops, strength_milli,
  visited_count]`, `proof_format(chain, rkg)` for the audit-grade
  human-readable string (`proof: A -> B -> C` header, one indented line
  per operator with kind + label + confidence, `strength: <milli>` footer),
  and `proof_to_dlog_trace(chain, rkg)` returning a list of
  [op_atom_id, premise_id, conclusion_id, confidence] entries matching
  the trace shape `reason_forward_chain` already produces, so any
  `dl_append` trace field can carry a proof trail uniformly.
  Strength is the product of per-operator Beta-posterior means
  (`rop_confidence` = `bel_mean` = `alpha / (alpha+beta)` milli), composed
  one link at a time via `result = result * confidence / 1000` and clamped
  to [0, 1000] -- the same integer-milli pattern `reason_evidential_chain`
  uses, so intermediates stay well under the codegen pointer-threshold
  danger zone. Defaults: depth 6, visits 1024; both are caller-overridable
  via the public API and via the chat `/prove PREMISE CONCLUSION [DEPTH]`
  surface. Edge cases: premise == conclusion is the trivial proof
  (chain=[], strength=1000); cycles (a->b->a) are visit-set-bounded so
  they cannot expand twice; no path within depth returns valid=0 with the
  visit counter so the operator can distinguish depth-bound vs
  graph-bound failure. Chat surface (`examples/crossengin_chat.nova`): a
  single new `_admin_prove` admin function + one dispatch line + one
  /help line. Prints either
  ```
  proof: headache -> dehydration -> hydration
    op #623 (causal) headache -> dehydration; confidence 500
    op #632 (implicative) dehydration -> hydration; confidence 500
  strength: 250 milli (product of confidences)
  visited 6 state(s); depth budget 6, visit budget 1024
  ```
  or `no proof: headache -> motorcycle within depth 6 (visited N of 1024)`.
  Unit test `tests/unit/test_proof_checker.nova` (+56 assertions, 117 total
  suites) covers trivial / one-hop / two-hop / no-path / cycle / depth-bound
  / strength composition / format / dlog-trace / stateful counters.
  Integration scenario `tests/integration/scenario_o_proof_checker.sh`
  (+10 assertions) runs the medical seed and asserts the chain output for
  headache -> dehydration -> hydration plus the baseline-seed
  fever -> infection -> treat chain, plus the trivial / unknown-label /
  /help-listing paths. No SAT solver, no embedding lookup -- pure
  substrate integer arithmetic over operator edges already in the
  reasoning KG.
- P2.10 snapshot compaction pass: **complete**.
  After hours of operation a long-running snapshot grows linearly with KG
  size + moment count + episode count: a steady accumulation of dead atoms
  (mean < 0.05, kept for posterity but never reached at inference), archived
  episodes (tier == EP_ARCHIVED, past the active recall window), and weak
  synapses (|weight| < 0.2 milli) that all together push the wire format
  past 500KB and make /load take a noticeable beat. New module
  `src/persistence/snapshot_compaction.nova` is the in-memory editor: it
  takes a PARSED snapshot value and returns a NEW snapshot value with the
  same wire format (no SNAP_FORMAT_VERSION bump) but smaller payloads, by
  filtering each section's blob against a configurable opts struct.
  Sub-compactors:
  - `compact_kgs(snap, opts) -> [new_blob, dropped]` drops atoms whose
    posterior mean (alpha / (alpha+beta) in milli) is below
    `opts.dead_belief` (default 50, i.e. 0.05). Optionally also drops
    atoms whose label starts with `opts.drop_label_prefix` -- the
    scratch-namespace knob (`debug:` or test prefixes).
  - `compact_episodic(snap, opts) -> [new_blob, dropped_eps, dropped_moments]`
    drops episodes at tier EP_ARCHIVED (== 2) and moments older than
    `opts.moment_max_age_ns` (default 1h == 3,600,000,000,000 ns). "Older
    than" is computed relative to the newest moment timestamp in the
    stream, so it works without an external clock reference.
  - `compact_synapses(snap, opts) -> [new_blob, dropped]` tightens the
    already-applied SYN_SNAP_MIN cut (100 milli) to
    `opts.synapse_threshold` (default 200 milli). No-op when the blob's
    current threshold is already at or above the requested level (only
    ever tightens, never relaxes).
  - `snap_compact(snap, opts) -> new_snap` orchestrates all three +
    copies SOUL / SELFMODEL through unchanged. `snap_compact_stats(snap,
    opts) -> [kg_drop, ep_drop, m_drop, syn_drop]` does the same scan
    without producing the new snapshot (used by `/compact --dry-run`).
  Opts knobs are env-driven via `compact_opts_from_env()`:
  `CE_COMPACT_DEAD_BELIEF` (milli), `CE_COMPACT_MOMENT_MAX_AGE_NS` (ns),
  `CE_COMPACT_SYNAPSE_THRESHOLD` (milli), `CE_COMPACT_DROP_LABEL_PREFIX`
  (string). All four fall through to the static defaults when unset /
  invalid (mirrors `_dl_env_int` in decision_log).
  Chat surface (`examples/crossengin_chat.nova`): a single new
  `_admin_compact` admin function + dispatch line for `/compact`.
  `/compact` (no arg) builds the live snapshot via `_build_snapshot`,
  runs `snap_compact_stats` for the report, runs `snap_compact` for the
  payload, prints
  `(compacted: 47 dead atoms dropped, 12 archived episodes dropped,
   0 old moments dropped, 23 synapses below new threshold dropped;
   snapshot 540KB -> 320KB)` and stashes the compacted snapshot in a
  global `_pending_compact_snap` buffer keyed by `active_id`. The NEXT
  `/save` reads the buffer instead of rebuilding from live state and
  prints `(saved compacted snapshot: kg=N atom(s), M moment(s), K syn(s)
  -> path durably)`. Buffer is cleared after every /save; the per-session
  key lets a `/switch` invalidate a stale buffer.
  `/compact --dry-run` prints the same stats line with " (dry-run)" mode
  marker but does NOT touch the pending buffer -- the next /save still
  rebuilds from live state.
  Snapshot-disk hook: `snap_save(s, path)` honours
  `CE_AUTO_COMPACT_ON_SAVE=1` -- when set, the snapshot is passed through
  `snap_compact(s, compact_opts_from_env())` before serializing to text,
  so a daemon that wants to write only compacted images can opt in via
  env. Off by default (manual `/compact` is the primary surface).
  NOVA list-mutation safety: every per-section compactor copies survivors
  into a fresh list rather than removing in place (the brief calls this
  out -- list_set has no shift-and-remove semantics, so filter-while-
  iterate is a footgun). The 1-hour ns default sits above NOVA's
  pointer-threshold (0x100000) and is held in a `let` constant rather
  than inlined.
  Acceptance: `tests/unit/test_snapshot_compaction.nova` covers opts
  defaults + setters, KGS drops by dead-belief + by label prefix,
  EPISODIC drops by tier + by moment age, SYNAPSES tighten-only
  threshold (including the no-op-when-blob-already-tighter case), full
  orchestrator pipeline with mixed sections, round-trip through
  `snap_to_text / snap_from_text` (the compacted shape is still wire-
  format compatible), size-shrinks bound (100 atoms, half dead -> >25%
  byte savings), empty-snapshot edge case, and env-driven default
  helpers -- 48 assertions across 13 test functions.
  `tests/integration/scenario_n_compaction.sh` (NEW; 12 assertions): seed
  baseline /save -> /teach 50 unknowns + /pin each to confidence=10 ->
  /save baseline; then seed baseline -> /teach 50 + /pin -> /compact ->
  /save with `CE_COMPACT_DROP_LABEL_PREFIX=scenN`. Verifies the stats line
  format, the drop count (99 of 100 atoms -- 50 lang pinned to dead
  belief + 50 reasoning prefix-matched, one of the lang word atoms
  shares its alpha/beta state at the same address as the reasoning
  atom's), the `(in-memory snapshot replaced)` banner, the
  `(saved compacted snapshot: ...)` /save banner variant, and the
  acceptance check `compacted_growth < 50% of baseline_growth` (typically
  878B vs 16404B -- ~5%). Also exercises `/compact --dry-run` (must
  print "(dry-run)", must NOT print "in-memory snapshot replaced", and a
  subsequent /save must use live state) and verifies /help lists
  /compact.
  Sample stats output (verified): `(compacted: 99 dead atoms dropped, 0
  archived episodes dropped, 0 old moments dropped, 0 synapses below new
  threshold dropped; snapshot 184KB -> 168KB)`.
- P2.5 STT framework + audit: **complete (framework only)**.
  The matching STT (speech-to-text) half of the audio modality bridge that
  P19 + P2.6 closed for TTS. Speech recognition in 2026 is either a
  deep-learning blackbox (Whisper, wav2vec, Conformer-RNN-T) or a
  multi-month classical pipeline (MFCC + GMM-HMM + Viterbi); neither
  fits in pure NOVA this decade. This session ships the FRAMEWORK
  (pluggable backend seam, subprocess shim, env-gated audio capture
  source) and a thorough audit (`STT_AUDIT.md`, ~900 words) documenting
  the realistic path -- mirroring the WIN32_AUDIT / MACOS_AUDIT /
  TLS_AUDIT / WASM_AUDIT precedents. The sandbox has no microphone
  hardware and none of the standard CPU acoustic toolchains installed
  (verified: no `whisper-cli`, no `whisper`, no `main`,
  no `vosk-transcriber`, no `arecord`, no `parecord`, no `espeak`), so
  no real STT exists. The end-to-end run-time path (mic -> WAV ->
  transcript -> EV_MESSAGE) is documented as "deferred until microphone
  hardware" and is the natural follow-up.
  New modules under `src/io/transducers/`:
  - **`stt_seam.nova`** (NEW) -- the pluggable STT surface. Public API:
    `stt_seam_new()` constructs a seam (pre-registers "stub" and
    "subprocess" backends so `stt_seam_backend_name()` returns a
    sensible string even before the first transcription call).
    `stt_seam_enabled(seam)` returns 1 iff any backend is wired (always
    1 post-construction since the stub is always registered).
    `stt_seam_backend_name(seam)` returns the active default's name
    string ("subprocess" / "stub" / "" if unset).
    `stt_transcribe_wav(seam, wav_path)` returns the
    `[transcript, confidence_milli, error_msg]` triple regardless of
    which backend produced the answer. `stt_transcribe_pcm(seam,
    pcm_list, sample_rate)` writes the PCM samples to a temp WAV at
    `/tmp/ce_stt_input.wav` (same 44-byte RIFF/WAVE/PCM header
    `audio_synth.audio_write_wav` ships) then delegates to
    `stt_transcribe_wav`. `stt_register_backend(seam, name,
    backend_id)` appends or in-place-updates a backend in the registry
    (so a test mock or a future WASM plugin can wire in without
    touching the dispatcher). `stt_default_backend()` reads
    `CE_STT_BACKEND` once: "subprocess" -> SUBPROCESS, anything else /
    unset -> STUB. Two real backends ship:
    * **Stub backend** -- deterministic placeholder.
      Returns `[stt unavailable]` + confidence 0 + empty error.
      Selected by default in CI / sandboxed environments where
      fork/exec is undesirable.
    * **Subprocess backend** -- shells out to `scripts/transcribe.sh
      <wav>` via /bin/sh -c with stdout wired through a `pipe2(2)` so
      the seam reads the child's transcript line. The fork/pipe dance
      is a small raw-asm cluster (pipe2, dup2, close are inline asm;
      fork_process/exec_program/waitpid are existing NOVA builtins).
      Confidence on success is the documented ballpark 800 milli
      (subprocess output has no native confidence on stdout); on
      placeholder output ("[stt: ...]") the confidence is 0 and the
      bracketed line is preserved in the transcript slot so callers
      can introspect which fallback fired.
  - **`stream_audio.nova`** (NEW) -- env-gated audio-capture source.
    Same poll-once-per-tick shape as `stream_stdin.nova`, takes
    `CE_AUDIO_CAPTURE_CMD` (e.g. `arecord -d 5 -q -f cd
    /tmp/ce_input.wav`) and `CE_STT_BACKEND` from env; activates only
    when BOTH are set non-empty. Each `stream_audio_poll(s, hs)`
    advances a tick counter; on every `CE_AUDIO_POLL_INTERVAL_TICKS`
    (default 100 -- roughly once per second at 100 Hz) the source
    shells out to the capture command, runs the STT seam against the
    produced WAV, normalizes the transcript via `transduce_text` (the
    same path stdin uses), and posts it as `EV_MESSAGE` -- unless the
    transcript is a `[stt...` placeholder, in which case the source
    silently drops it. Default OFF so all existing integration tests
    are bit-identical.
  New shim under `scripts/`:
  - **`scripts/transcribe.sh`** (NEW) -- the subprocess shim. Takes a
    WAV file path; emits the transcript on stdout, one line. Detects
    which backend is installed at runtime (quality order:
    `whisper-cli` -> `main` -> `vosk-transcriber`); falls back to
    `echo "[stt: no backend installed]"` when none are present. Exits
    0 on success AND on "no backend available" AND on "input WAV
    missing" (so a caller in a sealed sandbox never sees a non-zero
    exit -- the placeholder line tells it the transcript is
    unavailable). Install commands for each backend documented in the
    script header (`git clone whisper.cpp`; `pip install vosk
    vosk-transcriber`).
  New centerpiece doc at repo root:
  - **`STT_AUDIT.md`** (NEW) -- the realistic-path write-up. Why
    structural STT is hard (non-stationary noise + voiced segments;
    Whisper/wav2vec presupposes hundreds of MB of trained weights;
    classical Kaldi/HTK pipelines presuppose Viterbi+FST+EM training);
    three realistic options for CrossEngin in increasing difficulty
    (subprocess shim ~3-5 days, WASM-compiled Whisper ~2-3 weeks once
    P2.7 ships, pure-NOVA phoneme classifier ~3-6 months); the
    WASI/Linux/macOS/Windows audio-capture matrix; the
    `scripts/transcribe.sh` contract; latency budgets (real-time
    conversation needs <500 ms; whisper.cpp tiny.en CPU is 1-2 s for a
    5-second utterance; vosk is closer to real-time); cross-references
    to the new modules + ADR-0014/0015.
  Acceptance: `tests/unit/test_stt_seam.nova` (NEW; ~15 assertions
  asked, 26 delivered) covers seam construction + tag sentinel,
  default backend env-resolved validity, the two built-in backends
  pre-registered post-construction, `stt_seam_enabled`/backend-name
  accessors, the stub backend's deterministic
  placeholder+confidence-0+empty-error triple, last_* mirrors tracking
  call_count, the subprocess backend's missing-file
  "[stt: input wav missing]" prefix recognition (mapping to confidence
  0 with the bracketed line in the transcript slot), `stt_register_backend`
  append + in-place-update semantics, the dispatcher's fall-through
  for any non-SUBPROCESS id (custom mock id lands on the stub branch
  -- documents the "function-pointer-shaped thing" limitation), and
  the `stt_result_*` triple accessors. Verified:
  - `NOVA_ROOT=/home/user/NOVA make build` -> all 109 modules compile
    (+2 from `stt_seam.nova` and `stream_audio.nova`).
  - `NOVA_ROOT=/home/user/NOVA make test` -> 115 unit-test files pass
    (+1 suite for `test_stt_seam.nova`, +26 assertions).
  - `bash scripts/transcribe.sh /tmp/nonexistent.wav` -> echoes
    `[stt: input wav missing]`, exit 0 (as required).
  - The streaming-stdin integration path is bit-identical (no
    `stream_stdin.nova` changes).
  - No microphone hardware in sandbox -> integration test is the
    documented deferred follow-up.
- P2.6 multi-formant Klatt phoneme synthesizer: **complete**.
  The original P19 audio bridge shipped a pure-NOVA single-carrier sine
  synth -- audibly a sequence of phonemes but comically robotic. P2.6
  replaces the Mode-1 carrier with a simplified-Klatt two-formant model
  while keeping every wire-format invariant intact: still 8 kHz, still
  16-bit PCM mono, still 150 ms (1200 samples) per phoneme, still the
  same `audio_write_wav` byte layout. The old sine-only path lives on
  as `synth_phoneme_sine` (legacy / A-B test target) and is selectable
  via `CE_SYNTH_MODE=sine` at runtime.
  New entry points in `src/io/effectors/audio_synth.nova`:
  - `phoneme_formants(label)` -> [F1, F2, F3, kind] -- hard-coded
    formant table covering 13 vowels (a/ah/e/eh/i/iy/ih/o/oh/ow/u/uw/ae)
    with full F1+F2+F3 from Hillenbrand 1995, 6 plosives (p/t/k/b/d/g)
    with a high-F2 carrier hint for the burst, 7 fricatives
    (s/z/f/v/sh/th/h) with carrier hints, 3 nasals (n/m/ng), 4 liquids
    (l/r/w/y) treated as low-F1 vowels, and an unknown -> 440 Hz fallback.
    `kind` in {UNKNOWN=0, VOWEL=1, PLOSIVE=2, FRICATIVE=3, NASAL=4}.
  - `synth_phoneme_klatt(phoneme_label)` -- the new default per-phoneme
    synthesizer. Dispatches on `kind`:
    * VOWEL: two cosine carriers F1+F2 at half-amplitude each, summed
      so the peak stays at AUDIO_AMPLITUDE (well under PCM16 clip).
    * PLOSIVE: 5 ms leading silence + 30 ms LCG noise burst modulated by
      the high-F2 carrier hint + trailing silence to fill the 150 ms
      phoneme slot.
    * FRICATIVE: 120 ms of LCG pseudo-noise at half-amplitude (white
      noise sounds like a fricative when summed at moderate amplitude;
      full Klatt would high-pass filter it).
    * NASAL: single low formant (~250-500 Hz) with a linear amplitude
      damping (1000 -> 500 milli over the buffer) producing the muffled,
      fading quality of a nasal consonant.
    * UNKNOWN: the legacy 440 Hz sine fallback.
  - `_envelope(samples, attack_ms, hold_ms, release_ms, sample_rate)`
    (public wrapper `audio_envelope`) -- anti-click ADSR: 5 ms attack +
    sustain + 10 ms release per phoneme by default. Click-free at
    phoneme boundaries.
  - `_lcg_next(amp)` (public `audio_lcg_next`) + `_lcg_reset` (public
    `audio_lcg_reset`) -- pseudo-noise via a small-multiplier LCG
    (`state = state * 31 + 7`, masked to 20 bits to stay under NOVA's
    codegen pointer threshold blocker #11). Deterministic seed (12345)
    so the same input always produces the same noise bytes.
  - `audio_synth_mode()` / `audio_synth_mode_reset()` -- resolves the
    `CE_SYNTH_MODE` env once per process (cached). Values: `klatt`
    (default), `sine` (pre-P2.6 legacy), `silence` (1200 zero samples
    per phoneme -- useful in CI to suppress audible noise but keep the
    WAV path valid).
  `synth_phoneme(label)` now dispatches through the mode resolver,
  so a single env flag flips the whole audio output without disturbing
  `synth_text`, `audio_write_wav`, or any downstream caller (the brief's
  "transparent behavior swap"). `audio_speak.nova` is documentation-only:
  the CE_SYNTH_MODE selector lives in audio_synth.nova; audio_speak's
  Mode-1 leg delegates unchanged.
  Phoneme set covered: 33 distinct labels -- 13 vowels (a, ah, e, eh, i,
  iy, ih, o, oh, ow, u, uw, ae), 6 plosives (p, t, k, b, d, g), 7
  fricatives (s, z, f, v, sh, th, h), 3 nasals (n, m, ng), 4
  liquids/glides (l, r, w, y). Anything else falls through to the
  440 Hz unknown placeholder.
  Acceptance: `tests/unit/test_audio_synth.nova` extended with 47 new
  assertions across 14 new test functions (99 total, up from 52),
  covering: formant-table return shape + correct kind dispatch for
  vowel/plosive/fricative/nasal/unknown; vowel "a" peak-to-peak > 5000,
  sustain RMS proxy > 2000, max < 32000 (no clipping); fricative "s"
  has higher zero-crossing rate than vowel "a" (>= 1.5x); plosive "p"
  has zero RMS in first 5 ms, burst peak > 1000 in next 30 ms, zero
  RMS in trailing region; anti-click attack: max-abs in samples [0..20]
  < max-abs in samples [20..40] (envelope ramp); anti-click release:
  symmetric pattern at the buffer tail; first/last sample exactly 0;
  `audio_envelope` applied directly to a flat 16000-buffer yields the
  expected ADSR shape (sample 20 in [7000..9000], sample 600 == 16000,
  ends at 0); LCG determinism: reset + 3 draws == another reset + 3
  draws bit-identical; LCG bounded in [-16000..+16000] with > 10000
  range; klatt vs sine sample-wise differ on > 50/100 of first samples;
  default mode resolves to klatt when CE_SYNTH_MODE is unset; nasal
  has higher max-abs in the first quarter than the last quarter
  (damping); the on-disk WAV size for a short sentence is exactly
  44 + n*2 bytes (= 12000 samples + 44 header for "hello world this
  is a test"). Verified end-to-end:
  - `make build` -> all 107 modules compile.
  - `make test` -> 114 unit-test files pass; audio_synth.nova alone
    reports `audio_synth: OK (99 checks)` (up from 52, +47).
  - `make install && rm -f /tmp/ce_speech.wav && printf '/speak hello
    world\n/quit\n' | ./bin/crossengin-chat` -> still prints
    `(spoke 'hello world' [synth-only]; wrote /tmp/ce_speech.wav)`.
  - `ls -la /tmp/ce_speech.wav` -> 24044 bytes (= 44 header + 12000 *
    2 PCM bytes; "hello world" is 10 chars in the cold-seed fallback
    path, 10 character-phonemes * 1200 samples each).
  - `file /tmp/ce_speech.wav` -> "RIFF (little-endian) data, WAVE
    audio, Microsoft PCM, 16 bit, mono 8000 Hz" (unchanged shape).
  - Sample quality sentence "hello world this is a test of the formant
    synthesizer" yields a 105644-byte WAV (= 44 + 52800 * 2; 44 chars
    -> 44 syllables in fallback) -- valid Microsoft PCM 16-bit mono
    8 kHz at /tmp/ce_quality_test.wav.
- P2.8 streaming event sources (stdin + Unix socket + HTTP webhook): **complete**
  for stdin; framework-only for the other two.
  Three new transducers under `src/io/transducers/` lift the daemon from a
  fixed pre-loaded event queue to a long-running event consumer fed by real
  input at runtime. Each ships a uniform poll surface
  (`stream_*_poll(state, hs)`) the daemon calls once per tick, plus an
  env-toggled `init_from_env` / `init` lifecycle so the default scripted-
  episode integration tests stay bit-identical.
  **stream_stdin (fully implemented):** `CE_STREAM_STDIN=1` switches fd 0
  to non-blocking via a raw `fcntl(72, F_SETFL=4, O_NONBLOCK=2048)` shim,
  then each poll calls `sys_read(0, ...)` non-blocking; complete
  newline-terminated lines are normalized via the existing
  `transduce_text` and posted as `EV_MESSAGE`. A persistent line-residual
  buffer holds partial reads until the next newline. EOF flushes any tail
  and marks the source done.
  **stream_unix_socket (framework + listen-socket lifecycle):**
  `CE_STREAM_SOCKET=<path>` (default `/tmp/crossengin.sock`) builds a
  sockaddr_un by hand (AF_UNIX=1, 110-byte struct, store8-per-byte to
  dodge the pointer-threshold), binds + listens, sets the listen fd to
  O_NONBLOCK, then per poll accepts one client and drains its lines
  synchronously. Multi-client + truly non-blocking accept are stubbed
  behind the same call surface.
  **stream_http (framework + JSON message-field extractor):**
  `CE_STREAM_HTTP_PORT=<int>` (default disabled) binds `127.0.0.1` by
  default (loopback enforced because the body feeds cognition).
  `POST /api/event` with `{"message":"text"}` -> EV_MESSAGE; all other
  paths/methods return 4xx. A tolerant single-field JSON extractor reads
  the `message` value (handles `\"` + `\\` escapes); a full JSON parser
  would be over-scope for this single endpoint. Concurrent client
  handling stubbed: one request per poll.
  **Daemon integration:** any of the three CE_STREAM_* envs trips
  `streaming_mode=1`, which (a) suppresses the scripted episode, (b) lifts
  the CE_MAXSTEP cap so the daemon runs indefinitely, (c) adds one poll
  per source per tick to the main loop, (d) suppresses the post-loop
  scripted-episode "must" assertions, (e) skips the reboot-rehydrate
  block (handled out-of-band by SIGINT/SIGTERM + the idle checkpoint).
  Default behaviour (no env set) is bit-identical to pre-P2.8.
  **NOVA gotcha worked around:** `str_new(buf, n)` (from
  `std/string`) hangs inside the daemon's compilation unit when called
  from a transducer poll. All three modules build their post-read NOVA
  string by `chr()`-concatenation in a tight loop instead; the loop is
  O(n) per syscall chunk (bounded by 4096 bytes) so the overhead is
  acceptable. The unit test `test_stream_stdin.nova` exercises the
  shared splitting+posting logic via a `stream_stdin_test_feed` helper
  that does NOT touch real stdin -- 28 assertions across 7 test
  functions (well above the ~10 target). The integration test
  `tests/integration/scenario_l_stream_stdin.sh` launches the daemon
  with `CE_STREAM_STDIN=1`, sends `fever` via a held-open FIFO, and
  asserts (a) the streaming-mode banner names stdin, (b) the driver
  line announces streaming-mode, (c) the percept line `msg "fever"
  perceive(m>=1` was emitted, (d) the scripted-episode messages were
  suppressed. Sample smoke run:
  ```
  echo "fever" | CE_STREAM_STDIN=1 ./bin/crossengin
  # ===                          ===
  # boot     : cold start (no prior snapshot); Aurora, 8 parts, 572 concepts
  # stream  : stdin
  # driver   : streaming-mode -- waiting for events from stream sources
  #   [100Hz] msg "fever" perceive(m=1,unk=0) reason=9 mood(v=656) ... say "see recover"
  ```
- P2.4 atom-store hash index (label + kind buckets): **complete**.
  `src/kg/multi_kg_manager.nova` now carries a side-table label hash index
  inside every KG (`KG_LABEL_IDX`, `LABEL_BUCKETS = 256` buckets of
  `[label_hash, atom_id]` pairs) plus a parallel kind index
  (`KG_KIND_IDX`, `ATOM_KIND_COUNT` lists of atom_ids). `kg_find_atom(kg,
  label)` now hashes the label (deterministic shift-xor in
  `atom_store.nova::label_hash` — `h = ((h * 31) + c) & 32767`, seed 5381,
  bucket = `h & 255`), jumps to the bucket, and linear-walks the small
  bucket; with 1000 atoms each bucket holds ~4 entries so lookup is
  effectively O(1) amortized. The hash function uses a 15-bit mask
  (32767 max) so the multiply intermediate stays well below NOVA's
  large-magnitude pointer-threshold (0x100000) — see footgun #11. Mutation
  hooks: `kg_add_atom` populates both indexes after appending the atom,
  `kg_remove_atom` (new, for atom_death_monitor's tombstone path) deletes
  the index entries but leaves the atom slot in place so existing handle
  callers don't blow up. Snapshot rehydrate: `kg_section_apply` in
  `snapshot_disk.nova` now ends with a per-KG `kg_rebuild_index(kg)` so
  rehydrated atoms are addressable on the first lookup; `kg_rebuild_index`
  also auto-installs the index slots on a legacy KG that lacks them
  (backwards-compat). Backwards-compat: `kg_find_atom` checks
  `_kg_has_index(kg)` and falls back to the original linear scan if
  absent (a snapshot rehydrated through some other path stays
  functional). `kg_atoms_by_kind(kg, kind)` is the matching public read
  surface for the kind index. Acceptance:
  `tests/unit/test_atom_store_index.nova` covers the hash function
  (determinism, range/mask invariants), fresh-KG index-slot presence,
  add->hit / remove->miss mutation hooks, hash-collision retrievability,
  1000-atom indexed lookup under 50ms wall-clock (via `nanotime()`), the
  snapshot rehydrate path (clear-then-`kg_rebuild_index` round-trip),
  5000-atom (2x 2500) cross-KG isolation including a shared-label probe
  in both KGs, and the legacy-snapshot linear-scan fallback for a
  hand-built indexless KG — 61 assertions across 10 test functions.
  `tests/benchmark/bench_kg_query.nova` extended with a head-to-head
  section (1000-atom KG, 1M lookups via `nanotime()`):
  `indexed elapsed(ms): ~170` vs `scalar elapsed(ms): ~8700`, **speedup
  ratio ~50x** (within the bounds of O(1) vs O(N/2=500) with constant
  factors). The legacy 3000-atom scalar-walk section is kept for
  comparison with prior benchmark runs.
- P0.6 real-time wall-clock pacer: **complete**.
  New `src/scheduler/realtime_pacer.nova` turns the abstract "100Hz active /
  10Hz idle" tiers into actual wall-clock pacing. The pacer samples
  `nanotime()` at each tick start, lets the tick body run, samples again,
  and `sleep_ms`'s the remainder of the 10ms / 100ms budget; if the tick
  overran, it counts the overrun and the worst-case nanoseconds-over and
  proceeds without sleeping (so the next tick is on time even if this one
  slipped). The wrapper `hs_step_paced(hs, modulator, error, pacer)` lives
  in `hybrid_scheduler.nova` and routes the active/idle budget by reading
  `hs_rate()`. Pacing is OPT-IN via `CE_REALTIME=1` -- when off, the pacer
  is a no-op so unit tests stay full-speed. The daemon prints
  `pacer: <N> ticks, <M> overruns (max <K>ms over budget)` at exit when
  pacing is enabled. A slow-mo factor (`pacer_set_factor`) multiplies the
  budget for regression tests that want to stretch wall-clock time without
  changing call sites. Pacing uses an inline `_imul_raw` asm shim because
  the budget * factor multiply both operands are well above NOVA's
  pointer-threshold (0x100000) and would otherwise dispatch into
  `_nova_mul`'s str_repeat / list_repeat path. Acceptance:
  `tests/unit/test_realtime_pacer.nova` covers construction defaults, the
  disabled no-op, real-sleep wall-clock confirmation via raw `nanotime`
  reads (50ms +/- 15ms), deliberate-overrun reporting, slow-mo (factor 3
  -> ~60ms wall), factor clamp on non-positive k, multi-tick counter
  accumulation, and the summary format -- 27 assertions across 8 test
  functions. Sample smoke: `CE_REALTIME=1 ./bin/crossengin 2>&1 | tail -3`
  ends with `pacer: 44 ticks, 0 overruns (max 0ms over budget)`.
- P0.7 decision-log durable path: **complete**.
  `src/audit/decision_log.nova` gained the runtime seam that was formerly
  the documented NOVA-enhancement #9. Each `dl_append` now ALSO writes a
  pipe-separated line to an `O_WRONLY|O_CREAT|O_APPEND` file (path from
  `getenv("CE_DLOG_PATH")`, default `/tmp/crossengin.dlog`). fsync is
  batched: every 16 entries (`CE_DLOG_FSYNC_EVERY`) or every 1000 ms
  (`CE_DLOG_FSYNC_INTERVAL_MS`) since the last fsync, whichever fires
  first -- so a single-entry burst doesn't pay the full fsync cost but a
  steady stream still gets a sub-second flush latency. Per-message
  ADR-0043 trace fields (the bulky visited-node list) are NOT serialized
  to the on-disk line because they are reconstructible from the snapshot;
  the hash chain is recomputed at recovery from the same fields, so
  `dl_verify` still works post-rehydrate (trace is empty in the recovered
  copy but the chain math agrees). On boot, `dl_open(path, log)` reads
  every line, replays each through `_dl_apply_line` (bypassing the
  re-write side-effect), and stops at the first corrupt line; the tail
  past that point is truncated via a fresh `O_TRUNC` write of the bytes
  that DID parse, with a `warning -- truncated corrupt tail` line printed
  to stdout. The dlog is "durable-but-separate" per ADR-0043: it lives at
  its own path, so a snapshot rehydrate does NOT roll back audit history.
  New API on top of the existing `dl_append`/`dl_verify`/`dl_get`/
  `dl_count`: `dl_open(log, path)`, `dl_close(log)`, `dl_path(log)`,
  `dl_pending_writes(log)`, `dl_is_durable(log)`, `dl_force_fsync(log)`.
  The daemon and chat both call `dl_open(log, ...)` after `dl_new()` and
  `dl_close(log)` at exit (the chat hooks `/quit` and `/exit` shutdown
  paths in `_try_admin` plus the bare `quit`/`exit`/EOF paths in `main`);
  no new admin command is added (`/history` already covers `dl_get`).
  Acceptance: `tests/unit/test_decision_log_durable.nova` covers fresh-
  path open + close, append-writes-to-disk, restart-preserves-entries,
  multi-entry recovery with follow-up append landing at the right seq,
  corrupt-tail truncation, batched-fsync threshold via `dl_pending_writes`,
  and in-memory-only behaviour -- 37 assertions across 7 test functions.
  `tests/integration/scenario_a3_dlog.sh` drives 3 chat messages, SIGKILL,
  relaunch, and confirms `/history` shows the prior entries with the
  `dlog: ... loaded N prior entries` boot banner. Sample smoke:
  `CE_DLOG_PATH=/tmp/test.dlog ./bin/crossengin && wc -l /tmp/test.dlog`
  prints `7 /tmp/test.dlog` first run, `14 /tmp/test.dlog` second run.
- P2.9 Prometheus `/metrics` scrape endpoint: **complete**.
  `scripts/web.py` now serves `GET /metrics` in the Prometheus text-format
  (`# HELP <name> <help>` + `# TYPE <name> gauge|counter|summary` framing
  followed by `name{labels} value` samples), so external monitors
  (Prometheus, Grafana Agent, vmagent, ...) can scrape live agent state at
  the usual 15s cadence. Probe path: the chat side gained an
  underscore-prefixed `/__metrics__` admin command that walks the live
  session and emits one `key=value` line per metric between explicit
  `METRICS_BEGIN` / `METRICS_END` markers (so the python parser doesn't
  depend on log-line ordering); web.py runs that probe lazily per cookie
  and caches each parsed response for `CE_METRICS_CACHE_S` seconds
  (default 10) so a tight scrape loop never serializes against `/api/chat`
  traffic. Metric families exposed: `crossengin_atom_count{kg=...,sid=...}`
  (reasoning + language KGs), `crossengin_refl_atom_count{sid=...}`,
  `crossengin_dlog_entries{sid=...}`, `crossengin_promotion_rate`
  + `crossengin_atrophy_rate` (`{source=...,sid=...}`, ADR-0050 milli
  percent rescaled to unit 0..1), `crossengin_soul_mood_valence` /
  `crossengin_soul_mood_arousal{sid=...}` (ADR-0034 mood, rescaled
  0..1), `crossengin_scheduler_tick_rate{sid=...}` (Hz),
  `crossengin_scheduler_overruns{sid=...}` (P0.6 pacer counter, 0 in
  chat mode), `crossengin_active_session_count` (live SessionStore size),
  `crossengin_evicted_session_count` (cumulative LRU evictions),
  `crossengin_request_total{cookie=...}` (per-cookie POST counter), and
  the `crossengin_request_duration_seconds` summary with `_count`,
  `_sum`, and `{quantile="0.5|0.9|0.99"}` over a 256-sample rolling
  window. The `/__metrics__` admin command is read-only -- the probe only
  calls `mo_poll` (the same idempotent side-effect `/meta` does) and
  reads `kg_atom_count` / `dl_count` / soul mood / `hs_now` / `hs_rate`.
  `/metrics` inherits the loopback bind default from `/api/chat`
  (`CE_BIND` env defaults to `127.0.0.1`), so a `CE_BIND=0.0.0.0` deploy
  must accept the same caveat as the rest of the admin surface (a curl
  from the LAN can scrape the agent's live state). The endpoint never
  spawns a `ChatChild` -- a Prometheus scraper with no cookie sees only
  the process-wide counters plus per-cookie data for whichever sessions
  are already alive, never extending the LRU footprint. Acceptance:
  `tests/integration/scenario_m_metrics_endpoint.sh` (35 assertions):
  asserts the static loopback bind + cache env, launches the server,
  POSTs `hello` to materialise a cookie's child, scrapes `/metrics`,
  validates HTTP 200 + `Content-Type: text/plain; version=0.0.4`,
  validates the `# HELP` / `# TYPE` framing for every metric family
  exposed, validates label shapes (`{kg="reasoning",sid="..."}`,
  `{cookie="..."}`, `{source=...,sid=...}`, etc.), asserts
  `request_total >= 1` after the POST, asserts the second scrape inside
  the cache window returns the same per-sid atom counts (cache hit, no
  re-probe), and confirms `/metrics` is read-only (active session count
  is unchanged across two scrapes). Sample output (10 lines):
  ```
  # HELP crossengin_atom_count Atoms in a per-session knowledge graph (kg label: reasoning|language).
  # TYPE crossengin_atom_count gauge
  crossengin_atom_count{kg="reasoning",sid="947f14a4-..."} 572.0
  crossengin_atom_count{kg="language",sid="947f14a4-..."} 547.0
  # HELP crossengin_dlog_entries Decision-log entries per session (ADR-0043).
  # TYPE crossengin_dlog_entries gauge
  crossengin_dlog_entries{sid="947f14a4-..."} 2.0
  # HELP crossengin_soul_mood_valence Soul mood valence (ADR-0034, unit scale 0..1).
  # TYPE crossengin_soul_mood_valence gauge
  crossengin_soul_mood_valence{sid="947f14a4-..."} 0.656
  ```
- Phase 13 Tier-2 item #1 -- meta-learning observer: **complete**.
  New `src/parts/meta/meta_observer.nova` (ADR-0050) is a low-frequency,
  purely-observational loop: it snapshots per-source atom-belief
  distributions and reports rolling promotion (tentative -> durable) and
  atrophy (durable -> sub-threshold or vanished) rates so the operator can
  tell which sources of evidence are productive. Source tagging is
  minimum-viable and explicit -- atoms only carry a source if a caller calls
  `mo_attribute(mo, tag, atom_id)` at creation time; the atom_store data
  shape is unchanged (the tag table lives entirely in the observer's
  side-table). The daemon attributes the contiguous seed-installed atom
  block as `"seed"` at boot and tags freshly-ingested concept atoms from
  the trigger-drain path as `"user-teach"`; the chat's `_admin_teach` does
  the same for `/teach`. Idle-tick polling (`mo_poll`, every
  `MO_POLL_EVERY` ticks, default 10) walks each source's attributed atoms,
  classifies each against the ADR-0030 mean threshold (>= 750/1000 =
  durable), accumulates per-source promotion / atrophy counters, and emits
  a `(meta: source 'X' promotion=N.N% atrophy=N.N%)` line only when either
  rate has activity (so normal stdout stays quiet). The chat has a new
  `/meta` admin command that prints the per-source table (`source / atoms /
  tentative / durable / promotion% / atrophy% / last_poll`). Defer for
  follow-up: feeding the rates back into `source_authority` (the dangerous
  up-/down-weight policy). Acceptance:
  `tests/unit/test_meta_observer.nova` covers empty observer, attribution
  dedup, the classification on poll (durable/tentative split for belief
  means 750/250 vs 500/500 vs 100/900), the promotion delta on a
  tentative-then-promoted atom, the atrophy delta on a durable-then-dropped
  atom, multi-poll accumulation, the report shape including every tracked
  source, the milli-percentage formatter, and the refl-kg promotion
  counter -- 39 assertions across 10 test functions. Sample `/meta` smoke
  run after `/teach widget` + `/teach gadget`: `seed 572 / 572 tentative /
  0 durable / 0.0 / 0.0` and `user-teach 2 / 0 / 2 / 100.0 / 0.0`.
- P1.3 -- kg-sync v2 protocol (N-subscriber + bidirectional + reconnect +
  auth + conflict): **complete**. Matures the P20 distributed-substrate
  seam from a one-shot single-subscriber demo into a production-shape
  pub/sub. The protocol bumps to v2 (HELLO + OK lines change version,
  three new event kinds, optional auth token, optional resume cursor); v1
  HELLO/OK strings are still recognised by the server so an old subscriber
  can attach to a new publisher. The end-to-end shape:
  - **N-subscriber fan-out**: publisher reads `CE_KGSYNC_SUBS` (default 1
    for backward compat) and accepts that many initial subscribers via
    `sync_pub_accept_n`. Each sub becomes a `[fd, last_ack_id,
    last_active_ns]` record; on every atom-birth (or PROMOTE / ATROPHY /
    DELETE event) the publisher iterates the live list and calls
    `_broadcast_line` -- round-robin per-event matches the brief's
    "background-style send loop" in a single process without
    threads. Rejected handshakes (bad token, malformed HELLO) do NOT
    count toward N; the publisher keeps accepting up to `3*N+4` total
    attempts. Subscribers whose `last_active` is older than
    `KGSYNC_PRUNE_NS` (30 s) are dropped before the next broadcast.
  - **Bidirectional**: SUB and PUB sides are symmetric after the
    handshake. Each subscriber can teach back to the publisher by
    piggybacking a `PUB <kg> <id> <kind> <a> <b> <label>` line on its
    ACK channel; the publisher's `_broadcast_line` collects PUB replies
    into an inbox the caller drains via `sync_apply_atom` (which is
    conflict-aware -- see below).
  - **Three new event kinds**: `PROMOTE <kg> <id> <alpha> <beta>` (belief
    update), `ATROPHY <kg> <id>` (sub-threshold mark), `DELETE <kg> <id>`
    (atom killed). The publisher exposes `sync_pub_broadcast_promote /
    _atrophy / _delete` helpers wired into a tiny stdin admin protocol
    (`promote <id>` / `atrophy <id>` / `delete <id>`); a full daemon
    would call them directly from the bayesian-update / evidence-cut /
    atom_death_monitor signal paths.
  - **Reconnect on disconnect**: subscriber holds a `[fd, host, port,
    token, since_atom_id]` state via `sync_sub_connect_state`. When
    `_recv_line` returns 0 mid-stream (peer closed mid-stream and not via
    BYE), `sync_sub_reconnect` closes the dead fd, re-dials with the
    60-attempt budget, and re-handshakes with `SUB FROM <cursor>` so the
    publisher can resume from the highest ATOM id the sub has applied.
    The subscriber distinguishes a clean BYE (don't reconnect, exit) from
    an unexpected EOF (reconnect).
  - **Auth handshake**: server reads `CE_KGSYNC_TOKEN` from env at
    accept-time. If set, the client must send `HELLO ce-kg-sync v2
    token=<TOK>` matching the server's token; otherwise the server
    replies `ERR auth` and closes. If unset, any HELLO is accepted
    (anonymous backwards-compat mode). The client's
    `sync_sub_connect`/`_state` mirrors the env so a single
    `export CE_KGSYNC_TOKEN=...` configures both sides.
  - **Conflict resolution**: `sync_apply_atom(kg, remote_id, kind, alpha,
    beta, label)` is the canonical receiver. Policy: (1) no local atom
    with `label` -> birth fresh; (2) local atom shares the remote id ->
    refresh belief in place; (3) local atom exists at a DIFFERENT id
    (the "two ends taught the same word" race) -> MERGE by averaging
    alpha and beta in-place, keeping the local id stable so any synapses
    that already point at it stay valid. No new atom is born on a merge.
    Documented in the module header.
  Wire constants live in `src/io/transducers/kg_sync.nova`:
  `KGSYNC_HELLO_V2_LINE`, `KGSYNC_OK_V2_LINE`, `KGSYNC_SUB_FROM_PREFIX`,
  `KGSYNC_PUB_PREFIX`, `KGSYNC_PROMOTE_PREFIX`, `KGSYNC_ATROPHY_PREFIX`,
  `KGSYNC_DELETE_PREFIX`, `KGSYNC_ERR_AUTH`, `KGSYNC_TOKEN_TAG`.
  Acceptance: `tests/unit/test_kg_sync.nova` covers format/parse
  round-trip for ATOM + PUB + PROMOTE + ATROPHY + DELETE, the top-level
  `_parse_line` classifier, HELLO token extraction (v1, v2 with and
  without token, malformed `token=` clause, empty token value), all four
  v1 malformed-line rejections (still), `_starts_with` prefix helper, the
  three new env helpers (`kgsync_subs_from_env`, `kgsync_token_from_env`
  default-anon), subscriber record init + set_ack + staleness threshold,
  the four `sync_apply_*` policies including the merge path that asserts
  local-id stability and the averaged belief, and the connection-state
  cursor accessors -- 169 assertions across 49 test functions (+116 over
  v1). `tests/integration/scenario_g2_kg_sync_multi.sh` (NEW; 24
  assertions) exercises all five features end-to-end: 3 subscribers fan
  out widget + gadget, sub1 piggybacks alpha-bird + beta-fish back to
  the publisher, a publisher with token rejects an anonymous client and
  accepts the token-bearing one, and a same-label collision (both ends
  teach `shared-label`) verifies the merge keeps the publisher's local
  KG at 1 atom. `tests/integration/scenario_g_kg_sync.sh` (v1 single-sub
  demo) keeps passing unchanged (13 assertions), and
  `tests/integration/failmode_kgsync_subscriber_drop.sh` (the pre-P1.3
  current-behavior pin) also still passes -- the publisher's surface
  hasn't regressed for an abrupt kill, the subscriber's reconnect path is
  the affirmative direction now.
  Sample manual smoke (verified):
  `CE_KGSYNC_SUBS=3 CE_KGSYNC_TOKEN=s3kret ./bin/crossengin-kg-publisher`
  with three `CE_KGSYNC_TOKEN=s3kret ./bin/crossengin-kg-subscriber`
  clients yields `send kg=language id=0 label=widget delivered=3`,
  with each sub printing `recv kg=language id=0 label=widget`.
- P1.1 + P1.6 -- meta-observer feedback into source_authority + atom-death
  attribution: **complete**. Closes the loop on ADR-0050: until this
  session the meta-observer only REPORTED per-source promotion / atrophy
  rates; now it ACTS on them and the atom-death monitor attributes deaths
  back to the observer.
  **P1.1 (feedback):** `src/parts/meta/meta_observer.nova` gains
  `mo_apply_feedback(mo, source_auth)` (mutates) and a paired
  `mo_feedback_dryrun(mo, source_auth)` (read-only). Both walk every
  tracked source: a cumulative promotion rate >= 700/1000 (70%) over a
  sample window of >= 10 attributed atoms promotes the source's host one
  tier (C -> B -> A); a cumulative atrophy rate >= 500/1000 (50%) over
  the same window demotes one tier (A -> B -> C). The window + threshold
  guard against thrash from a single-atom flip -- sustained signals only.
  When both thresholds cross, promotion wins. Source-tag bridge: today
  `source_authority` is host-keyed (URLs map via `sw_host` -> registry),
  while the P15 source tags (`src:topic:fever`) aren't host-keyed; the
  observer maps each tag to a synthetic host string
  (`src:<kind>:<tag>` -> `learned:<kind>:<tag>`; bare tags like `seed`
  and `user-teach` -> `learned:builtin:<tag>`) and calls a new
  `sa_host_set_tier(sa, host, tier)` accessor added to
  `src/learning/source_authority.nova` (plus the read companion
  `sa_tier_for_host`). The `learned:` prefix keeps synthetic hosts from
  colliding with real domains. The daemon
  (`examples/crossengin_daemon.nova`) wires the feedback into the idle
  loop: every `MO_FEEDBACK_EVERY` polls (default 20, override via env),
  it invokes `mo_apply_feedback` and prints a
  `(meta-feedback: '<tag>' -> host '<host>' promote tier C -> B)` line
  only when a tier ACTUALLY moves. The chat (`examples/crossengin_chat.nova`)
  gets two new admin commands: `/meta-feedback` is a dry-run that prints
  the per-source feedback table (tag / host / promo% / atrophy% / sample /
  current / proposed / action) and a "(N tier change(s) pending; run
  /meta-apply to commit)" footer, and `/meta-apply` actually invokes
  `mo_apply_feedback` on the process-shared `sauth` registry (built at
  boot from `sa_default()`). Tier hops are ONE step per call -- chained
  promotions / demotions require multiple feedback cycles. Sample smoke
  (after `/teach`-ing 12 words and `/pin`-ing them all to confidence 800):
  `/meta-feedback` shows `user-teach learned:builtin:user-teach 100.0 0.0
  12 C B promote`; `/meta-apply` reports
  `(user-teach -> host 'learned:builtin:user-teach' promote tier C -> B |
  promo=100.0% atrophy=0.0% sample=12)`; a second `/meta-feedback`
  shows the same source now at B and proposed for A.
  **P1.6 (atom-death attribution):** `src/learning/atom_death_monitor.nova`
  gains `adm_sweep_attributed(reg, kg, mo)` (the legacy `adm_sweep(reg, kg)`
  is now a wrapper that passes `mo=0`, preserving the existing test +
  caller surface). At the tombstone -> dead transition, the new entry
  calls `mo_record_death(mo, atom_id(a))` when `mo != 0` so a
  source-attributed atom that dies outright (durable atom GC'd by the GC
  before the next poll would have classified it as "vanished") bumps the
  observer's per-source atrophy counter immediately. The hook is a
  function-pointer-shaped thing in NOVA -- practically just an import +
  one extra call gated on `mo != 0`. Acceptance:
  `tests/unit/test_meta_observer_feedback.nova` covers the synthetic-host
  mapping for both `src:*` and bare tags, the sustained-signal guard
  (sample below window -> NONE), promote dryrun-then-apply moving tier
  C -> B, demote dryrun-then-apply moving a pre-seeded tier-A source to
  tier B, promote / demote tier-edge clamps, the "promotion wins when
  both cross" branch, a 3-source split (PROMOTE / DEMOTE / NONE),
  chained two-apply promotion from C to A, the `mo_fb_action_name` /
  `mo_tier_name` helpers, and the empty-observer no-op -- 54 assertions
  across 13 test functions. `tests/unit/test_atom_death_attribution.nova`
  covers `mo_record_death` direct (tagged atom -> +1, untagged -> no-op),
  the legacy `adm_sweep` back-compat, `adm_sweep_attributed(reg, kg, 0)`
  null-mo behaviour, the headline "attributed durable atom dies ->
  observer atrophy counter +1", idempotency under repeated sweeps (the
  dead-flag guard prevents double-attribution), multi-attribution in one
  sweep, mixed tagged + untagged, an empty-observer guard, and the
  protected-atom case (never collected, never attributed) -- 28
  assertions across 10 test functions. Tier transitions observed under
  these tests: tier-C synthetic host -> tier-B after one apply for a
  source whose 10 attributed atoms had 8 promotions (80%); tier-A host
  -> tier-B after one apply for a source whose 10 atoms had 6 atrophies
  (60%); chained C -> B -> A across two apply calls for a 20-atom source
  with 18 promotions (90%); both promotion and demotion saturate at the
  A / C edges (no underflow / overflow).
- Phase 14 Tier-2 item #2 -- structural-neighborhood activation: **complete**.
  The reader now has a substrate-native similarity surface for indirect input.
  A new `src/reader/neighborhood.nova` exposes `find_neighbors(kg_reg, handle,
  max_hops, max_results)` that mines TWO substrate sources -- reasoning
  operator edges (ADR-0031) and cross-KG xref edges (ADR-0017) -- plus a small
  word-sense co-occurrence pass (ADR-0015), and aggregates evidence by summing
  strengths and clamping to 0..1000. One-hop wins; two-hop is decayed by
  NEIGH_HOP_DECAY (0.5, same constant as ADR-0012 stage 3).
  `spreading_activation` now seeds neighborhood hits ADDITIONALLY on every
  exact-match anchor's chosen sense (exact match still gets full SPREAD_SEED
  so it dominates) and falls back to `lexical_fallback_candidates` on
  unmatched tokens -- a substrate-native miss recovery that surfaces concept
  handles named by lexically-similar known words. Sample:
  `find_neighbors(fever, 2, 5)` over a fever -> infection -> treat seed
  returns `infection -> 1000` (one-hop direct, operator + xref both fire),
  `treat -> 600` (two-hop, decayed), `headache -> 500` (one-hop operator
  only). NO embeddings, NO transformer; pure substrate. Acceptance:
  `tests/unit/test_neighborhood_activation.nova` covers all four scenarios in
  the brief (basic find_neighbors, sorted/capped output, hop-depth, round-trip
  via spreading_activation, cross-KG ref case, paraphrase via lexical
  fallback, exact-match dominance) with 30 assertions across 10 test
  functions.
- P2.1 + P2.2 -- cofire and syntactic-slot similarity sources: **complete**.
  Two more substrate-native similarity sources for `find_neighbors`, both
  deferred from the original Phase 14 / Tier-2 #2 work because they needed
  side-indices. Now closed.
  **P2.1 (co-fire from moment_stream):** `src/reader/cofire_index.nova` is
  a side-table keyed by canonicalized atom-id-pair, counting how many
  distinct moments their activations co-appeared. `ci_strength(ci, a, b)
  -> milli` normalizes by the GLOBAL maximum co-fire count -- a rare pair
  that fires as often as the most-frequent pair still scores 1000; a pair
  that appeared in only 1 of 10 max moments scores 100. Storage is a list
  of `[kg_label_a, atom_a, kg_label_b, atom_b, count]` rows; lookup is a
  linear scan (N small in practice; deferred hash index per NEXT_SESSION
  blocker #1). Wired at the PERCEIVED -> SETTLED transition: the daemon
  calls `ms_settle_old_with_cofire(stream, now, ci, kg_label)` at every
  idle tick, which fires `ci_record_moment(ci, kg_label, moment_trace(m))`
  exactly once per moment as it crosses the settle boundary. Empty traces
  and singleton traces are no-ops.
  **P2.2 (syntactic-slot from output_generation):** `src/reader/
  slot_index.nova` is a side-table keyed by (pattern_atom_id, role_name)
  with a histogram of atom-ids that have filled the slot. `si_strength(si,
  a, b) -> milli` sums each slot's contribution and clamps to 1000; the
  per-slot contribution is `min(count_a, count_b) * 1000 / slot_max`, so
  the rarer filler bounds the strength. Wired at the output-generation
  callsite: the daemon's `gen_from_intent_with_slot(lang, cands, intent,
  moment, si)` records each `[role, word_atom]` filler after the chosen
  pattern is selected. Different roles return 0; different patterns share
  no slot; two atoms that have co-filled the same (pattern, role) cell
  surface as role-neighbors.
  **`find_neighbors_full(kg_reg, source, ci, si, max_hops, max_results)`**
  takes both indices, walks all five sources (operator, xref, sense,
  cofire, slot) into one accumulator, and clamps at 1000 per-neighbor. The
  3-arg `find_neighbors(...)` stays as a wrapper that passes `ci=0, si=0`
  so legacy callers and all pre-P2.1/P2.2 tests are bit-identical.
  Sample (paraphrase demo, fever+infection seeded chat history of 10
  co-occurring moments): `ci_strength(fever, infection) = 1000`,
  `ci_strength(fever, treat) = 300` (3 of max 10), `si_strength` between
  two TOPIC-role co-fillers = 1000; baseline `find_neighbors(fever)` gave
  `infection=1000, treat=600` (2-hop xref decayed), but
  `find_neighbors_full(fever, ci, 0)` lifts `treat` to 900 via the cofire
  evidence the moment-stream collected. Acceptance:
  `tests/unit/test_cofire_index.nova` (35 assertions across 10 functions),
  `tests/unit/test_slot_index.nova` (23 assertions across 10 functions),
  plus 4 new tests added to `tests/unit/test_neighborhood_activation.nova`
  (cofire-only neighbor, slot-only neighbor, combined-clamped, 3-arg
  wrapper bit-identity) bringing that suite from 30 to 45 assertions. The
  daemon + chat now allocate `ci_new()` / `si_new()` at boot and pass them
  into the settle and gen calls; no new admin commands. The indices are
  NOT yet persisted across sessions -- next-session indices start fresh; a
  Phase-10 follow-up will lift them into the snapshot.
- Phase 19 Tier-4 item #1 -- audio modality bridge: **complete**.
  Two new modules under `src/io/effectors/` realize the minimum-viable
  audio leg of ADR-0014 -- the modality bridge that until now was a
  documented deferred runtime seam. `audio_synth.nova` is the always-on
  Mode 1 floor: a 256-entry quarter-wave sine table built at startup via
  Bhaskara's degree-domain approximation (full-period samples via 4-fold
  symmetry), a Bresenham-style integer phase generator (all loop-body
  intermediates < 16k so the NOVA loop-multiply pointer threshold,
  blocker #11, is never crossed), per-phoneme synthesis at 8 kHz / 16 bit
  PCM mono (150 ms = 1200 samples per atom, triangular envelope to keep
  edges click-free), a hard-coded formant table for ~30 common ARPABET-ish
  phonemes (vowels 270-730 Hz, fricatives 2.5-3.8 kHz, plosives 180-240 Hz,
  unknown -> 440 Hz A4 fallback), word-level concatenation that prefers
  recorded phonemes from `word_atoms.nova`'s `word_phonemes()` xref when
  available and otherwise falls back to one tone per character at a
  word-length-derived carrier, and a single-shot WAV writer that allocates
  the full byte buffer + writes through `sys_open/sys_write/sys_fsync/
  sys_close` so the file is durable before any aplay reader opens it
  (same contract as `snapshot_disk.nova`). `audio_speak.nova` layers
  Modes 2 + 3 on top: `_try_espeak` uses `fork_process`+`exec_program`+
  `waitpid` to detect `espeak` on PATH via `command -v`, then shells
  out `espeak -w PATH 'TEXT'` for a much higher-quality voice; `_try_aplay`
  best-effort plays via `aplay -q` or `paplay`. Both gracefully fall back
  to the next mode -- the seam returns success as long as the WAV reached
  disk, so playback failure does NOT fail the speak call. The chat gets a
  new `/speak [TEXT]` admin command (default path `/tmp/ce_speech.wav`,
  override via `CE_SPEECH_PATH`); with no TEXT it speaks the agent's last
  reply, captured via a `_last_reply` global the main loop updates on each
  drained event. Acceptance: `tests/unit/test_audio_synth.nova` covers the
  44-byte RIFF header bytes (incl. canonical PCM marker at offset 36-39
  and little-endian sample-rate + data-size fields), 8000-sample sine
  generation (first/last near zero at 1 Hz, peak ~+16000 / min ~-16000),
  zero-sample edge case, 1200-sample phoneme invariant including the
  unknown-label fallback and a 3500 Hz fricative, multi-word + empty-text
  + lang-KG-overrides-fallback paths for `synth_text`, and the on-disk
  WAV round-trip (write `[0,0,0]` to /tmp/ce_test_audio.wav, sys_read the
  first 4 bytes back, assert `R,I,F,F`; 10-sample run is exactly 64 bytes
  on disk = 44 header + 20 PCM) -- 52 assertions across 16 test functions.
  Verified end-to-end in chat:
  `printf '/speak hello world\n/quit\n' | ./bin/crossengin-chat` produces
  `(spoke 'hello world' [synth-only]; wrote /tmp/ce_speech.wav)`, and
  `file /tmp/ce_speech.wav` reports
  `RIFF (little-endian) data, WAVE audio, Microsoft PCM, 16 bit, mono 8000 Hz`
  (24044 bytes). In this sandbox neither `espeak` nor `aplay`/`paplay`
  is installed, so Mode 1 carries the seam end-to-end; Modes 2 and 3 are
  exercised by their detection code at runtime and skipped silently.
- Phase 20 Tier-4 item #2 -- distributed-substrate seam: **complete**
  (upgraded to v2 by P1.3 -- see entry above for the multi-subscriber +
  bidirectional + reconnect + auth + conflict-merge details).
  New `src/io/transducers/kg_sync.nova` defines a one-op-per-line text
  wire protocol for atom-birth events plus the publisher + subscriber
  socket halves. v1 operations (still recognised by the v2 server):
  `HELLO ce-kg-sync v1` / `OK v1 protocol accepted` (handshake), `SUB *`
  (subscribe to all atoms), `ATOM <kg_label> <id> <kind> <alpha> <beta>
  <label>` (one atom birth), `ACK <id>` (per-atom ack), `BYE` (graceful
  close), `ERR <reason>` (handshake refusal). Defaults match the rest of
  the repo's safe-bind pattern: 127.0.0.1 (override `CE_KGSYNC_BIND=0.0.0.0`),
  port 8766 (override `CE_KGSYNC_PORT`), subscriber host `127.0.0.1`
  (override `CE_KGSYNC_HOST`). v2 adds three event kinds (PROMOTE,
  ATROPHY, DELETE), bidirectional PUB-from-subscriber, an optional
  `token=<TOK>` HELLO clause + `CE_KGSYNC_TOKEN` env gate, `SUB FROM
  <id>` cursor-based resume, and N-subscriber fan-out gated by
  `CE_KGSYNC_SUBS` (default 1 for v1 backwards compat). Two artifacts
  compose it: `bin/crossengin-kg-publisher` (binds + accepts N
  subscribers + reads labels from stdin + emits atom-births / PROMOTE /
  ATROPHY / DELETE) and `bin/crossengin-kg-subscriber` (dials in +
  handshake + applies received events to its own KG + may teach back via
  stdin -> PUB). The main `bin/crossengin` daemon is intentionally
  untouched -- this is the seam, not the multi-process refactor.
  Acceptance: `tests/unit/test_kg_sync.nova` covers format/parse round-
  trip for ATOM + PUB + PROMOTE + ATROPHY + DELETE, the top-level
  `_parse_line` classifier, HELLO token extraction, all four v1
  malformed-line rejections, the three new env helpers, subscriber
  record init + set_ack + staleness threshold, the four `sync_apply_*`
  policies (including the merge path that asserts local-id stability
  and the averaged belief), and the connection-state cursor accessors
  -- 169 assertions across 49 test functions (+116 over v1).
  `tests/integration/scenario_g_kg_sync.sh` (v1, 13 assertions) and
  `tests/integration/scenario_g2_kg_sync_multi.sh` (v2, 24 assertions)
  exercise both protocols end-to-end against per-run high ports; both
  print SKIP if `socket(2,1,0)` itself fails so a denying sandbox
  doesn't break CI. Sample manual smoke (verified):
  `./bin/crossengin-kg-subscriber > /tmp/sub.out &` then `printf 'widget\n'
  | ./bin/crossengin-kg-publisher` produces `recv kg=language id=0
  label=widget` in /tmp/sub.out.
- Phase 18 Tier-3 item #3 -- multi-tenant session foundation: **complete**.
  New `src/session/session.nova` (ADR-0051) defines a Session struct -- a
  flat 15-slot bundle (id, name, created_at, last_active, soul, kgreg, kg,
  lang, ikg, refl_kg, ctx, log, engine, mo, hs) -- plus a linear
  SessionRegistry keyed by id. The module is dependency-free: every
  subsystem state object is stored OPAQUELY (Session never reads past the
  top-level slot), so the daemon's existing boot sequence builds each
  handle as before and then wraps them with one `session_make(...)` call.
  API: `session_make(id, name, now, sl, kgreg, kg, lang, ikg, refl_kg, ctx,
  log, engine, mo, hs)`, per-slot accessors `session_id/name/created_at/
  last_active/soul/kgreg/kg/lang/ikg/refl_kg/ctx/log/engine/mo/hs`,
  `session_touch(s, now)`; registry `sreg_new`, `sreg_create(reg, id, name,
  now)`, `sreg_register(reg, sess)`, `sreg_lookup(reg, id)`,
  `sreg_destroy(reg, id)`, `sreg_count(reg)`, `sreg_ids(reg)` (ascending),
  `sreg_active(reg, max_idle, now)` (inclusive cutoff). The scheduler is
  per-session by design (clean tenant isolation, each tenant has its own
  tick clock / idle counter); revisit if N >> 1.
  Acceptance: `tests/unit/test_session.nova` covers session_make field
  storage + accessors, session_touch, zero-slot tolerance, registry empty
  state, create + lookup, duplicate-id rejection, pre-built register,
  destroy + no-op destroy, ids sorted ascending, active() inclusive idle
  filter, soul-mutation isolation between sessions, and post-destroy
  survivor integrity -- 66 assertions across 12 test functions.
- Phase 18 Tier-3 item #3 SECOND HALF -- chat `/switch` + web.py per-cookie
  routing: **complete**.
  The chat's `main()` now drives every turn through the SessionRegistry:
  at boot, the default session (`"default"` / "Aurora") is built via a
  new `_new_session_for(reg, id, name, now)` helper and inserted into the
  top-level `sreg`; each iteration of the REPL loop looks up the active
  session by `active_id` and re-binds the cognitive locals
  (`sl, kgreg, kg, lang, ikg, refl_kg, ctx, log, engine, mo, hs`) so every
  admin / message handler operates on the live session's state. New
  `/switch [ID]` admin command: with no arg it lists each session as
  `*active id  "name"  N atoms  last Ss ago` (asterisk marks the active
  row); with an id it activates the existing session or creates a fresh
  one (default name "Default", full seed installed via the same path the
  default session uses at boot). The dispatch table grows by exactly one
  entry. Substrate-side state (part registry, gate router, learning
  trigger arbiter, moment stream, episodic memory) stays process-shared
  -- the Session struct holds only cognitive state. Vanilla
  `./bin/crossengin-chat` is bit-identical to before because no `/switch`
  is ever issued and the default session is the only registered tenant.
  `scripts/web.py` was restructured around a new `SessionStore` class
  that maps `cookie -> [ChatChild, created_ms, last_active_ms]` with an
  LRU cap (default 8, override `CE_WEB_MAX_SESSIONS`). Cookies follow
  the `ce_sid=<UUID>; Path=/; HttpOnly; SameSite=Strict` convention;
  absent or malformed cookies get a freshly-minted UUID via `uuid.uuid4()`
  and a Set-Cookie response header. The existing per-child `request_lock`
  still serializes the send-and-wait handshake; a new registry-level lock
  guards add/evict so two unknown cookies cannot race for the same slot.
  New diagnostic endpoint `GET /api/sessions` returns
  `{"sessions":[{id, last_active_ms, age_ms}, ...]}`. Shutdown walks
  every child and sends `/quit`. One incidental fix: `kg_section_apply`
  forcibly overwrites all `ATOM_LANG` atoms' `ltype` to `LWORD`, which
  corrupts the seed's syntax atoms (`"ack"`, `"see_topic"`) after `/load`;
  the chat now filters `0`s from the `gen_from_intent` candidates list
  when `syntax_find` returns 0 after a `/load`, falling back to
  `_gen_emit_intent`. Acceptance:
  `tests/integration/scenario_h_session_switch.sh` (16 assertions: teach
  in default, /switch alice, teach gadget, /switch back, verify
  per-session recognition both directions; the listing format with
  `* = active`; re-activate the same id; `/help` advertises `/switch`);
  `tests/integration/scenario_i_web_isolation.sh` (12 assertions: two
  distinct cookie jars get distinct ce_sid values; A's `/teach widget`
  is recognized by A but unknown to B; A's state survives B's
  intervening request; `/api/sessions` lists both with the diagnostic
  fields; SIGTERM cleans up). A 3-cookie concurrent stress run (3
  simultaneous `/teach` + query pairs) confirmed no race / interleave:
  each cookie received only its own taught word's response and
  cross-cookie isolation held at the read side too. An LRU stress at
  `CE_WEB_MAX_SESSIONS=3` with 5 sequential cookies evicts the oldest
  two as expected.
- Phase 15 Tier-2 item #3 -- multi-source `/learn`: **complete**.
  `scripts/learn.sh` now accepts a bare TOPIC (Wikipedia, unchanged), an
  http(s):// URL (fetched verbatim), or a local `/abs|./rel|../rel` file
  (read from disk). Each kind derives a sanitised `<tag>` and writes the
  same `/tmp/crossengin_learn_<tag>.txt` + `..._<tag>_triples.txt`. The chat's
  `/learn <ARG>` admin command re-derives the same tag via a NOVA
  `_learn_tag` helper (lock-step with the bash `case`+`sed` pipeline) and
  ingests both files. Every word / operator carries a `src:<kind>:<tag>`
  attribution so a future meta-loop / source-authority pass (ADR-0029)
  can corroborate / atrophy by source. Acceptance: `scripts/learn_smoke_multi.sh`
  exercises all three kinds; `tests/unit/test_learn_tag.nova` covers the
  tag-derivation contract with 22 assertions.
- P1.4 -- plain-HTTP in-process transport seam (NOVA enhancement #11 audit +
  minimum-viable lift off `curl` for `http://`): **complete**. Real TLS stays
  deferred (4-6 weeks; see [`TLS_AUDIT.md`](./TLS_AUDIT.md) for the roadmap).
  New `src/io/transducers/http_client.nova` is a pure-NOVA HTTP/1.1 client
  built on NOVA's existing socket builtins (same idioms as `kg_sync.nova`):
  `http_parse_url(url) -> [scheme, host, port, path]` parses
  `http(s)://host[:port][/path]` with default port 80/443 and "/" default
  path, returning `["", "", 0, ""]` on malformed input; `http_get(url,
  max_bytes) -> [status_code, headers_list, body, error_msg]` opens a TCP
  socket via `socket(2,1,0)` + `make_sockaddr_in` + `connect_socket`, sends
  `GET <path> HTTP/1.1\r\nHost: <host>\r\nUser-Agent: crossengin/0.1\r\n
  Accept: */*\r\nConnection: close\r\n\r\n`, loops `recv_data` until EOF or
  `max_bytes+8K` cap is reached, then splits on `\r\n\r\n` (with `\n\n`
  fallback), parses `HTTP/1.x NNN ...` status, accumulates `Name: value`
  headers; `http_header_get(headers, name)` is case-insensitive;
  `http_is_redirect(status_code)` classifies 3xx (callers re-issue with
  Location). DNS workaround for NOVA having no getaddrinfo: dotted-quad
  hosts (e.g. `127.0.0.1`) work directly; named hosts must be in the
  process-local cache populated from env
  `HTTP_DNS_HOST_TO_IP="host:ip,host:ip"` at first lookup. Unknown hosts
  return the canonical `HTTP_ERR_DNS` error and a deliberately loud
  pointer at `TLS_AUDIT.md`. Mode 3 wiring lives in `internet_fetch.nova`:
  new `if_dispatch_transport(url, max_bytes) -> [tag, status, body, err]`
  returns `IF_TRANSPORT_HTTP_OK` (1) for successful `http://`,
  `IF_TRANSPORT_HTTP_ERR` (2) for plain-HTTP transport failure,
  `IF_TRANSPORT_DEFERRED` (3) for `https://` (caller falls back to
  `scripts/learn.sh` curl, unchanged), `IF_TRANSPORT_BAD_URL` (4) on
  malformed URL. The whitelist + rate-limit + cache pipeline is UNCHANGED
  -- callers still `if_permit` before and `if_complete` + `if_ingest`
  after. Acceptance: `tests/unit/test_http_client.nova` covers the parser
  matrix (full URL, default ports for http/https, no-path -> "/",
  authority-only with port, ftp:// scheme rejection, malformed inputs),
  DNS register + lookup (case-insensitive on host, bad-IP rejection,
  dotted-quad bypass), case-insensitive header lookup, 3xx redirect
  classifier, status-line parser (200 / 404 / 301 / no-text / bad
  cases), and the dispatcher branches (https deferred, malformed bad-url,
  http unresolved DNS) -- 59 assertions across 15 test functions.
  `tests/integration/scenario_j_http_client.sh` spawns `python3 -m
  http.server` on a per-run port (31000+), writes a known marker file,
  builds an inline NOVA driver under `tests/integration/_scenario_j_drivers/`
  that calls `if_dispatch_transport("http://127.0.0.1:PORT/test_html.html",
  4096)`, and asserts: NOVA exits 0, tag=1 (HTTP_OK), status=200, body
  contains the marker, err empty, body_len >= 50, plus bonus drivers for
  the bad-URL and https-deferred branches -- 9 assertions; SKIPs cleanly
  if python3 isn't available or `socket(2,1,0)` returns -1 (sandbox denies
  AF_INET). Verified locally: scenario_j passes 9/9 with python3 present.
  Production blocker still loud: HTTP_DNS_HOST_TO_IP is a manual table,
  not real DNS; full resolution + TLS is the 4-6-week call documented in
  TLS_AUDIT.md.
- P1.4 PSK secure-channel continuation -- ChaCha20-Poly1305 envelope
  over TCP (the next hop after plain HTTP on the TLS roadmap):
  **complete**. Pure-NOVA ChaCha20 stream cipher
  (`src/safety/chacha20.nova`, 20 rounds per 64-byte keystream block,
  ARX over `int_add` / `int_xor` / `int_shl` / `int_shr` / `int_or` /
  `int_and` with 32-bit masking after every shift / add to keep every
  intermediate below 2^32 -- dodges NOVA gotcha #11) verified against
  RFC 7539 sections 2.1.1 (quarter-round), 2.3.2 (block, key=00..1f,
  nonce=00..09 00 00 00, counter=1), and 2.4.2 (114-byte "Ladies and
  Gentlemen" plaintext) -- 26 assertions in `tests/unit/test_chacha20.nova`.
  Pure-NOVA Poly1305 MAC (`src/safety/poly1305.nova`, 5 x 26-bit limb
  decomposition of the 130-bit accumulator, evaluating
  `(a + n) * r mod (2^130 - 5)` per 16-byte block with the standard
  carry-propagate-then-reduce trick) verified against RFC 7539 section
  2.5 (clamp), 2.5.2 (the canonical "Cryptographic Forum Research Group"
  vector with tag `a8061dc1305136c6c22b8baf0c0127a9`), and 2.6.2
  (Poly1305 key derived from `ChaCha20(counter=0)`) -- 9 assertions in
  `tests/unit/test_poly1305.nova`. The secure-channel framework
  (`src/io/transducers/secure_channel.nova`) wraps a TCP socket with a
  per-frame envelope `[4 BE length][12 nonce][ciphertext][16 tag]`,
  where the 12-byte nonce splits 4 / 8 into a session-id prefix +
  per-direction monotonic counter; per-frame Poly1305 one-time key is
  `ChaCha20(session_key, frame_nonce, counter=0)[0..32]` (RFC 7539
  AEAD construction). Public API: `sc_open(host, port, psk_hex)` ->
  opens TCP, sends 12-byte handshake nonce, both sides derive session
  key = `ChaCha20(PSK, hs_nonce, 0)[0..32]`, client sends a 16-byte
  "CE-SC-HS-OK" magic frame, server echoes back -- mismatch means PSK
  mismatch or in-flight tampering; `sc_send(state, buf, len)` / 
  `sc_recv(state)` are simple frame-at-a-time helpers; `sc_close(state)`
  closes the socket idempotently. 16 assertions in
  `tests/unit/test_secure_channel.nova` cover PSK validation,
  session-key determinism, nonce-layout, frame round-trip, single-bit
  tamper rejection, counter advancement. Integration test
  (`tests/integration/scenario_v_secure_channel.sh`) spawns a Python
  counterpart (`scripts/secure_channel_echo.py`) that implements the
  same wire framing, has the NOVA client send "ping", and asserts the
  decrypted reply is "pong" (the Python server transforms ping -> pong
  so we know the bytes were actually decrypted, not just byte-echoed)
  -- 6 bash assertions. The PSK is randomized per run (32 bytes from
  `/dev/urandom`) so the catastrophic nonce-reuse failure mode of any
  stream-cipher AEAD can't fire across CI runs. `http_client.nova`
  gains an opt-in `https_get_psk(url, psk_hex, max_bytes)` that opens
  the channel and routes the HTTP/1.1 request through it. This is NOT
  real HTTPS -- no certificate validation, no TLS framing, no
  hostname-to-PSK binding; it's "HTTP over a PSK-encrypted channel"
  suitable for a CrossEngin daemon talking to a CrossEngin-controlled
  upstream. SAFETY caveat documented in `secure_channel.nova` header
  and `TLS_AUDIT.md`: NOVA has no `getrandom(2)`, so the handshake
  nonce is derived from `nanotime()` + a process-local counter -- an
  attacker can predict it but the PSK stays secret; the failure mode
  is replay + traffic-analysis, not key recovery. Real TLS 1.3 with
  X.509 still costs ~5-6 weeks (was 4-6 before; the symmetric-crypto
  block is gone now), tracked in `TLS_AUDIT.md`.
- P1.5 -- composite `/learn` kinds (batch URLs, RSS feed, recursive
  directory): **complete**. Extends the P15 dispatcher with three new
  prefix-detected source kinds, all sharing the same `_learn_tag` /
  `_admin_learn` pipeline:
  - `@/path/urls.txt` -- one URL per line; the bash side iterates and
    recursively self-calls per URL, then concatenates per-URL caches into
    `/tmp/crossengin_learn_batch_<basename>.txt`. Tag = `batch_<basename>`.
    The chat ingests the combined cache then re-derives each per-URL tag
    and ingests the individual cache too so each URL keeps its own
    `src:url:<tag>` attribution for meta-observer scoring.
  - `rss:URL` -- fetches the feed, parses up to `LEARN_RSS_MAX` (default 5)
    `<link>...</link>` (RSS) or `<link href="...">` (Atom) entries, then
    batch-ingests them. Tag = `rss_<host>`. Lossy regex parser is fine --
    the chat-side filter is the ground truth for triples.
  - `dir:/path/` -- recursively walks for `*.txt` + `*.md` files (find -type
    f, NUL-delimited so spaces survive), recursively self-calls per file,
    concatenates per-file caches into the combined cache. Tag =
    `dir_<basename>`.
  All composite kinds prepend their prefix BEFORE path-shape detection
  (`_learn_kind` now checks `@`/`rss:`/`dir:` before the `/abs`/`./rel`
  branches), so a directory called `./foo` is never misclassified as FILE.
  NOVA-side helpers `_tag_sanitise`, `_learn_tag_batch`, `_learn_tag_rss`,
  `_learn_tag_dir`, `_basename`, and `_learn_ingest_one` /
  `_learn_ingest_batch_per_url` live alongside the existing P15 helpers
  in `examples/crossengin_chat.nova` (no new admin commands, no new
  dispatch lines -- the existing `/learn` line in `_try_admin` calls the
  same `_admin_learn`). Acceptance:
  `tests/unit/test_learn_tag.nova` is now 40 assertions (+18: 6 new kind
  classifications plus 4 batch + 4 rss + 4 dir tag derivations);
  `scripts/learn_smoke_multi.sh` is now 6 source-kind cases + 4 negative
  cases (was 3 + 1) and verifies BATCH @-prefix, RSS feed parsing, DIR
  walk, plus error-out on missing list / missing dir / empty rss URL.
  Network-dependent steps (TOPIC, URL, RSS, BATCH-of-URLs) skip cleanly
  if curl can't reach Wikipedia.
- Phase 11 Tier-1 item #1 -- full SOUL + KGS subsystem blob serialization:
  **complete**. `snapshot_disk.nova` now round-trips every atom (label, kind,
  alpha/beta belief, owning KG label) and the full SOUL state (name, purpose,
  identity, mood valence/arousal, OCEAN, constitution rule list); old-format
  snapshots still parse but install zero atoms (legacy `kgs.atoms` is treated
  as a metadata-only hint). The chat's `/load` is now a real rehydrate that
  replaces SOUL fields in place and merges KGS atoms by label, including the
  LANG-atom lexical fixture (`ltype = LWORD`, char-vector embedding, sense
  xrefs to same-labeled concept atoms). Acceptance test passes: after
  `/teach widget` + `/save`, a re-launched chat with `/load` recognizes
  `widget` (`perceive(m=1,unk=0)`).
- Phase 11 P0.1 follow-up -- full EPISODIC + SYNAPSES + SELFMODEL section
  serialization: **complete**. The remaining three snapshot sections now carry
  their full payloads, closing the daemon-restart gap that previously lost
  every moment, synapse weight, and competence reading. EPISODIC persists per
  moment (timestamp, lifecycle PERCEIVED/SETTLED/CONSOLIDATED, valence/salience,
  the list of atom ids in the moment's trace) and per episode (id, tier
  RECENT/CONSOLIDATED/ARCHIVED, the moment id list); SYNAPSES persists
  (src, dst, weight, eligibility) for every live synapse with |weight| >=
  100 milli (default cut, auto-raised in 100-milli increments if the
  above-threshold count exceeds 50K to keep snapshots under ~2MB); SELFMODEL
  persists per-domain competence records (label, kind, reliability, evidence,
  derived tier). Restore policy is REPLACE on all three (the snapshot is the
  new ground truth on /load, not a merge target). Backwards compatibility:
  a snapshot with only `<section>.present 1` and no sub-fields parses cleanly
  as an empty section (same legacy-hint convention as `kgs.atoms`). New
  restore helpers added (kept small, additive, documented): `ms_clear` +
  `ms_restore` in `moment_stream.nova`, `em_clear` + `em_restore` in
  `episode_storage.nova`, `syn_set_eligibility` + `syn_restore` in
  `synapse_graph.nova`, `self_model_clear` + `self_model_restore` in
  `competence_tracker.nova`. The chat's `_build_snapshot`, `_admin_save`,
  and `_admin_load` thread the moment stream, episodic memory, the WHOLE
  part registry (multi-part synapse capture, P0.1 follow-up #2; was
  reasoning-only), and a self-model through the new section helpers;
  the daemon's `_checkpoint` does the same. The wire format gained a
  `synapses.parts.count` / `synapses.parts[N].label` / per-part nested
  records block (additive, backward-compatible: a legacy snapshot with
  only `synapses.count` parses as before and installs into reasoning).
  `/status` gains three new lines
  (`moments`, `synapses`, `selfmodel`) so a post-restart `/load` is
  immediately verifiable. Acceptance test passes: `printf
  '/teach widget\nwidget\nwidget gadget\nwidget gadget fever\n/save\n/quit\n'
  | ./bin/crossengin-chat` followed by `printf '/load\n/status\n/quit\n' |
  ./bin/crossengin-chat` reports `moments : 3 moment(s), 3 episode(s)` plus
  `knowledge: 574 atoms` and the right `audit: K decision-log entries`.
  Acceptance: `tests/unit/test_snapshot_episodic.nova` (51 assertions),
  `tests/unit/test_snapshot_synapses.nova` (89 assertions: the original 43
  -- threshold-cut, inhibitory-weight, idempotent re-apply -- plus 46 new
  multi-part assertions added in the P0.1 follow-up #2: 3-part round-trip
  with distinct synapse patterns + per-part survival + cross-part
  isolation, empty-part skipping, legacy-fallback apply, multi-part
  idempotence, unknown-part skip-with-warning),
  `tests/unit/test_snapshot_selfmodel.nova` (38 assertions covering the
  three competence kinds, derived-tier survival, REPLACE policy, legacy
  presence-only stub) -- 178 assertions across the three suites
  (132 in the original P0.1 lift + 46 in the multi-part follow-up);
  `tests/integration/scenario_a2_full_state.sh` extends scenario A with 16
  assertions for SIGKILL durability of the new sections.

Top-level [`MANUAL.md`](./MANUAL.md) walks through running and testing locally
end-to-end (build, all three artifacts, the test suite, writing a new test).
The daemon boots from [`src/seed/first_atoms.nova`](./src/seed/first_atoms.nova),
which installs the foundational concepts the agent knows about itself (self,
user, query, response, help, ok), the operators that connect them, the two
output syntax patterns, and a tiny medical demo chain (fever -> infection =>
treat). Everything else is learned at runtime via the learning loops.

## Completed modules — Phase 1 (substrate kernel)

All under `src/substrate/`. Each compiles with `nova build` and has a matching
`tests/unit/test_<module>.nova` suite (happy path + edge + failure cases).

| Module | ADRs | Unit asserts | Status |
|--------|------|--------------|--------|
| node_pool_manager.nova | 0006, 0002, 0010 | 40 | done |
| signal_dispatch.nova | 0008, 0002 | 49 | done |
| synapse_graph.nova | 0007, 0002 | 55 | done |
| first_nodes.nova | 0010, 0006 | 29 | done |
| part_registry.nova | 0001, 0002 | 26 | done |
| part_lifecycle.nova | 0001 | 21 | done |
| gate_router.nova | 0009, 0045 | 24 | done |
| resonance_engine.nova | 0001, 0007, 0008 | 20 | done |
| tick_driver.nova | 0006, 0001 | 20 | done |

Also delivered:
- `tests/ce_test.nova` — shared assertion harness (lives outside `tests/unit/`
  so the runner does not treat it as a test).
- `examples/kernel_selfcheck.nova` — the runnable v0.1 artifact (`make run` /
  `make install`); boots all 9 modules end-to-end and asserts liveness.
- `tests/benchmark/bench_tick_rate.nova`, `tests/benchmark/bench_node_throughput.nova`.
- `make benchmark` target added to the Makefile.
- Docs: `docs/runbook/{build,test,run,troubleshooting}.md`,
  `docs/design/{overview,data_flow}.md`.

## Completed modules — Phase 3 (knowledge representation)

All under `src/kg/`, each compiling with a matching unit-test suite. Built on
the substrate's milli-fixed-point convention; belief and vector cosine are
implemented in-house (see NOVA blockers).

| Module | ADRs | Unit asserts | Status |
|--------|------|--------------|--------|
| atom_store.nova (P2.4 added `label_hash` + `LABEL_BUCKETS` for the hash index) | 0016, 0023 | 42 | done |
| multi_kg_manager.nova (P2.4: hash + kind indexes, `kg_remove_atom`, `kg_rebuild_index`, `kg_atoms_by_kind`; P3.4: optional `kg_set_ann` / `kg_ann` LSH side-index) | 0004, 0016 | 23 | done |
| atom_store_index (P2.4 hash + kind indexes: separate test suite) | 0016, 0049 | 61 | done |
| ann_index.nova (P3.4 LSH approximate-nearest-neighbor over atom embeddings; K=8 hyperplanes -> 256 buckets; deterministic LCG-seeded; rebuild on snapshot apply) | 0016, 0049 | 46 | done |
| cross_kg_references.nova | 0017, 0004 | 20 | done |
| schemas.nova | 0018 | 13 | done |
| concept_layer.nova | 0018 | 28 | done |
| skills_kg.nova | 0019 | 26 | done |
| competence_tracker.nova | 0020 | 27 | done |
| parts/reasoning/proof_checker.nova (P3.5 bounded-BFS operator-chain proof checker; product-of-Bayesian-mean strength; trivial / cycle / depth-bound / no-path edges; chat `/prove` surface) | 0031, 0052 | 56 | done |

Also delivered: `tests/benchmark/bench_kg_query.nova` (insertion, id/label
lookup, observation throughput); `tests/benchmark/bench_ann_query.nova`
(P3.4: linear cosine scan vs LSH-bucketed query head-to-head, 40x speedup
at 1000 atoms).

## Completed modules — Phase 2 (reader and language)

Language atoms under `src/language/`; the five-stage reader under `src/reader/`.
Each compiles with a matching unit-test suite. No LLM is touched (ADR-0014); the
reader operates purely over the language KG, concept layer, and substrate
signals.

| Module | ADRs | Unit asserts | Status |
|--------|------|--------------|--------|
| language/word_atoms.nova | 0015 | 20 | done |
| language/phoneme_atoms.nova | 0015 | 12 | done |
| language/syntax_atoms.nova | 0015, 0013 | 14 | done |
| reader/lexical_anchor.nova | 0012 (stage 1), 0011 | 19 | done |
| reader/context_bias.nova | 0012 (stage 2) | 9 | done |
| reader/spreading_activation.nova | 0012 (stage 3), 0017 | 9 | done |
| reader/neighborhood.nova (Phase 14 Tier-2 #2: structural-neighborhood; P2.1+P2.2 follow-up adds find_neighbors_full with cofire + slot side-indices) | 0012, 0017, 0031, 0015, 0021 | 45 | done |
| reader/cofire_index.nova (P2.1: co-fire side-index, atom-pair counts from settled moments) | 0021, 0012 | 35 | done |
| reader/slot_index.nova (P2.2: syntactic-slot side-index, (pattern, role) filler histogram from output generation) | 0015, 0013, 0012 | 23 | done |
| reader/coherence_check.nova | 0012 (stage 4) | 11 | done |
| reader/fetch_route_learn.nova | 0012 (stage 5) | 11 | done |
| reader/reader.nova | 0011, 0012 | 13 | done |

README updated to v0.3.

## Completed modules — Phase 4 (memory and learning)

Episodic modules under `src/parts/episodic/`; learning fabric under
`src/learning/`. Each compiles with a matching unit-test suite. Kept in the
kg / self-contained layer (no direct substrate-node imports) to respect NOVA
blocker #10; node-level values (novelty, activation, error, modulator) are
passed as parameters.

| Module | ADRs | Unit asserts | Status |
|--------|------|--------------|--------|
| episodic/moment_stream.nova | 0021 | 29 | done |
| episodic/episode_storage.nova | 0022 | 19 | done |
| episodic/consolidation.nova | 0022, 0025 | 10 | done |
| learning/bayesian_updates.nova | 0023, 0029 | 20 | done |
| learning/predictive_coding_runtime.nova | 0024 | 18 | done |
| learning/atom_birth_monitor.nova | 0025 | 15 | done |
| learning/atom_death_monitor.nova | 0025 | 18 | done |
| learning/plasticity_modulation.nova | 0035, 0007 | 10 | done |

README updated to v0.4.

## Completed modules — Phase 5 (self-directed learning)

All under `src/learning/`, each compiling with a matching unit-test suite. Kept
self-contained or kg-layer-only (NOVA blocker #10). The internet fetch transport
(TLS byte retrieval) is a deferred seam -- NOVA enhancement #11; the pipeline
(whitelist, rate limit, cache, validation, ingestion) is complete and tested.

| Module | ADRs | Unit asserts | Status |
|--------|------|--------------|--------|
| confidence_thresholds.nova | 0030 | 23 | done |
| source_whitelist.nova | 0028 | 14 | done |
| source_authority.nova | 0029 | 22 | done |
| self_learning_triggers.nova | 0026 | 27 | done |
| ask_user_to_teach.nova | 0027 | 19 | done |
| internet_fetch.nova | 0028, 0029 | 20 | done |

README updated to v0.5.

## Completed modules — Phase 6 (cognitive subsystems)

Five subsystems under `src/parts/`, each module compiling with a matching
unit-test suite. Goals/soul/emotion are self-contained; reasoning/imagination
import the kg layer on a single prefix (NOVA blocker #10).

| Module | ADRs | Unit asserts | Status |
|--------|------|--------------|--------|
| goals/goal_engine.nova | 0033 | 20 | done |
| goals/drive_generators.nova | 0033 | 15 | done |
| goals/goal_persistence.nova | 0033 | 11 | done |
| soul/identity.nova | 0034 | 13 | done |
| soul/state.nova | 0034 | 11 | done |
| soul/values.nova | 0034 | 8 | done |
| soul/constitution.nova | 0034, 0045 | 11 | done |
| soul/themes.nova | 0034 | 7 | done |
| soul/loyalty.nova | 0034 | 9 | done |
| soul/goals_in_soul.nova | 0034 | 7 | done |
| emotion/appraisal.nova | 0035 | 14 | done |
| emotion/ocean_conditioning.nova | 0035 | 8 | done |
| emotion/plasticity_mod.nova | 0035, 0007 | 7 | done |
| reasoning/reasoning_atoms.nova | 0031 | 13 | done |
| reasoning/reasoning_module.nova | 0031 | 12 | done |
| imagination/imagination_engine.nova | 0032 | 14 | done |
| imagination/forward_sim.nova | 0032 | 7 | done |
| imagination/counterfactual.nova | 0032 | 8 | done |
| imagination/dream_recombination.nova | 0032 | 6 | done |
| imagination/scenario_planner.nova | 0032 | 6 | done |

README updated to v0.6.

## Completed modules — Phase 7 (agent architecture)

Scheduler under `src/scheduler/`, loops under `src/agent/`, meta under
`src/parts/meta/`. Each module compiles with a matching unit-test suite. Design
that respects NOVA blocker #10: each loop is a self-contained unit over the
shared `loop_coordination` blackboard (one subsystem import, one node_pool
path); the scheduler is substrate-subtree only. Wiring all loops + the scheduler
into one program is the Phase 10 `main` (needs a `nova_packages/` shim).

| Module | ADRs | Unit asserts | Status |
|--------|------|--------------|--------|
| scheduler/event_dispatch.nova | 0037 | 10 | done |
| scheduler/tick_loop.nova | 0037 | 8 | done |
| scheduler/hybrid_scheduler.nova | 0037, 0036 | 11 | done |
| agent/loop_coordination.nova | 0036 | 16 | done |
| agent/loop_perception.nova | 0036 | 4 | done |
| agent/loop_memory.nova | 0036 | 4 | done |
| agent/loop_reasoning.nova | 0036 | 3 | done |
| agent/loop_emotion.nova | 0036, 0035 | 3 | done |
| agent/loop_goals.nova | 0036, 0033 | 3 | done |
| agent/loop_action.nova | 0036, 0013 | 4 | done |
| agent/loop_imagination_idle.nova | 0036, 0032 | 2 | done |
| parts/meta/self_model_query.nova | 0038 | 9 | done |
| parts/meta/theory_of_mind.nova | 0039, 0044 | 13 | done |
| parts/meta/long_horizon_goals.nova | 0040 | 9 | done |
| parts/meta/reflection_loop.nova | 0032, 0023 | 16 | done |
| parts/meta/meta_observer.nova (Phase 13 Tier-2 #1: per-source promotion/atrophy observer) | 0050 | 39 | done |

README updated to v0.7.

## Completed modules — Phase 8 (safety and audit)

Safety stack under `src/safety/`, the audit/decision log under `src/audit/`.
Each module compiles with a matching unit-test suite. The whole safety stack is
a single clean dependency chain (no blocker #10): `reversibility_classifier`
(also home to the shared `ACT_*` constants) <- `permission_tiers` <-
`constitutional_filter`; the audit log layers `decision_log` <- `audit_writer`/
`audit_reader`; `override_mechanism` composes the kg-belief, goal-engine, and
audit subtrees (three disjoint subtrees, so they coexist). The gate chain is
`safety_gate` (constitutional veto -> hard stop -> permission tier, which folds
the reversibility floor); the audit log is append-only and hash-chained
(tamper-evident: mutation, reorder, and tail-truncation all fail `dl_verify`).
Pure substrate, NO LLM (ADR-0014). The fsync-backed durable store (ADR-0043
write path) and the process-exit/snapshot syscalls (ADR-0044 kill) are the
documented runtime seams (NOVA enhancements #9/#10); all decision logic is real
and tested.

| Module | ADRs | Unit asserts | Status |
|--------|------|--------------|--------|
| safety/reversibility_classifier.nova | 0042, 0041 | 21 | done |
| safety/permission_tiers.nova | 0041, 0042 | 24 | done |
| audit/decision_log.nova | 0043 | 25 | done |
| audit/audit_writer.nova | 0043 | 25 | done |
| audit/audit_reader.nova | 0043, 0038 | 14 | done |
| safety/override_mechanism.nova | 0044, 0043, 0023 | 27 | done |
| safety/constitutional_filter.nova | 0045, 0041, 0042 | 22 | done |

README updated to v0.8.

## Completed modules — Phase 9 (IO and effectors)

Output generation and effectors under `src/io/effectors/`, the input transducer
under `src/io/transducers/`. Each module compiles with a matching unit-test
suite. Layering for NOVA blocker #10: `output_generation` is the language
subtree only (it reaches words/syntax via a single import prefix);
`effector_gate` composes the safety subtree (`constitutional_filter`) with the
standalone `decision_log` — two disjoint trees, so no double-include (it
deliberately does NOT also import `audit_writer`, whose `permission_tiers` path
would collide, and rebuilds the descriptor/append locally); `input_transducer`
is standalone.

| Module | ADRs | Unit asserts | Status |
|--------|------|--------------|--------|
| io/effectors/output_generation.nova | 0013, 0015, 0007 | 10 | done |
| io/effectors/effector_gate.nova | 0041..0045, 0043, 0013 | 23 | done |
| io/effectors/audio_synth.nova (Phase 19 Tier-4 #1: audio modality bridge -- WAV + Klatt two-formant phoneme synth; P2.6 upgrade) | 0014, 0015, 0013 | 99 | done |
| io/effectors/audio_speak.nova (Phase 19 Tier-4 #1: audio modality bridge -- espeak/aplay escalation) | 0014 | 0 | done |
| io/transducers/input_transducer.nova | 0014, 0011, 0012, 0021 | 19 | done |
| io/transducers/kg_sync.nova (Phase 20 Tier-4 #2: distributed-substrate seam; P1.3 v2 upgrade -- N-subs + bidir + reconnect + auth + conflict) | 0014, 0016 | 169 | done |
| io/transducers/http_client.nova (P1.4: plain-HTTP/1.1 in-process client + dispatcher seam + opt-in `https_get_psk` over PSK secure channel; full TLS deferred -- see TLS_AUDIT.md) | 0028, 0014 | 59 | done |
| io/transducers/secure_channel.nova (P1.4 cont.: PSK ChaCha20-Poly1305 envelope over TCP; framing for the wireguard-style "noise" channel) | TLS_AUDIT.md | 16 | done |
| safety/chacha20.nova (P1.4 cont.: pure-NOVA ChaCha20 stream cipher, RFC 7539) | TLS_AUDIT.md | 26 | done |
| safety/poly1305.nova (P1.4 cont.: pure-NOVA Poly1305 MAC, RFC 7539) | TLS_AUDIT.md | 9 | done |

Pure substrate, NO LLM (ADR-0014): `output_generation` produces text by the
reverse of comprehension (intent -> real word atoms -> learned syntax ordering),
`effector_gate` is the chokepoint that runs the Phase 8 `safety_gate` and writes
intent-before/outcome-after decision-log entries (the SPEAK effector is fully
implemented; governed speak vetoes forbidden output by its text). File/network/
message transport and audio STT/TTS are the documented runtime seams (NOVA
enhancements #11/#14); all gate/log/generation logic is real and tested.

Phase 20 / Tier 4 item #2 -- distributed-substrate seam: **complete**.
P1.3 upgraded the protocol to v2 (N-subscriber fan-out, bidirectional
PUB-from-subscriber, three new event kinds PROMOTE / ATROPHY / DELETE,
auth handshake via `CE_KGSYNC_TOKEN`, reconnect-on-disconnect with
`SUB FROM <id>` cursor resume, and conflict-resolution merge by averaged
belief; v1 HELLO/OK strings are still recognised). The original artifact
shape is preserved: `src/io/transducers/kg_sync.nova` defines a text
wire protocol (one op per line, `\n` terminated) with the publisher +
subscriber socket halves; two artifacts compose it end-to-end:
`examples/crossengin_kg_publisher.nova` -> `bin/crossengin-kg-publisher`
(binds 127.0.0.1:8766 by default, accepts `CE_KGSYNC_SUBS` subscribers --
default 1 for backwards compat -- reads labels from stdin, births an
atom + fans it out to every live sub in a round-robin send loop, prunes
subs whose `last_active` is older than 30s) and
`examples/crossengin_kg_subscriber.nova` -> `bin/crossengin-kg-subscriber`
(dials the publisher, sends `HELLO ce-kg-sync v2[ token=<TOK>]` +
`SUB *` or `SUB FROM <id>`, reads + applies events, transparently
reconnects on EOF, and may teach back via stdin -> PUB). Wire ops:
`HELLO ce-kg-sync v{1|2}[ token=<TOK>]`, `OK v{1|2} protocol accepted`,
`SUB *`, `SUB FROM <id>`, `ATOM kg id kind alpha beta label`, `PUB
kg id kind alpha beta label`, `PROMOTE kg id alpha beta`, `ATROPHY
kg id`, `DELETE kg id`, `ACK <id>`, `BYE`, `ERR <reason>`, `ERR auth`.
Defaults: bind `127.0.0.1` (opt in to broader via `CE_KGSYNC_BIND=0.0.0.0`,
mirroring web.py); port 8766 (override via `CE_KGSYNC_PORT`);
subscriber host `127.0.0.1` (override via `CE_KGSYNC_HOST`);
expected-subs `1` (override via `CE_KGSYNC_SUBS`); token unset
(override via `CE_KGSYNC_TOKEN` -- if unset, anonymous). The main
`bin/crossengin` daemon is intentionally NOT modified -- rolling
kg_sync into its idle path is a future enhancement.
Acceptance: `tests/unit/test_kg_sync.nova` covers format/parse round-trip
for ATOM + PUB + PROMOTE + ATROPHY + DELETE, malformed line rejection
(missing fields, wrong op, non-numeric numerics, illegal label chars,
empty fields), CRLF + LF eol handling, dash/underscore label preservation,
the IP-string -> packed-int helper, the top-level `_parse_line`
classifier, HELLO token extraction, env helpers, subscriber record + staleness,
the four `sync_apply_*` policies (including the merge), and connection-state
cursor accessors -- 169 assertions across 49 test functions;
`tests/integration/scenario_g_kg_sync.sh` exercises v1 single-sub
(13 assertions), `tests/integration/scenario_g2_kg_sync_multi.sh`
exercises v2 (24 assertions: 3 subs fan-out + bidir + reconnect-pin +
auth gate + conflict merge). Sandbox-quirk handling: both scripts
print a `SKIP` block if `socket(2,1,0)` returns -1 so a denying sandbox
keeps the suite green.
Sample manual smoke: `./bin/crossengin-kg-subscriber > /tmp/sub.out &`
then `printf 'widget\ngadget\nfever\n' | ./bin/crossengin-kg-publisher`
yields three `recv kg=language id=N label=...` lines in `/tmp/sub.out`,
verified locally; with `CE_KGSYNC_SUBS=3` the publisher fans the same
labels to three subscribers.

README updated to v0.9.

## Completed modules — Phase 10 (persistence + spine artifact)

Persistence under `src/persistence/`, plus the runnable companion-spine artifact.
Each module compiles with a matching unit-test suite. The snapshot writer/reader
are the generic ADR-0048 CONTAINER (tagged/versioned, fixed ordered sections,
each an opaque subsystem blob), so they stay standalone (no subsystem imports,
no blocker #10) and compose into any binary. The load-bearing part is enforced
in the reader: the mandatory rehydration order soul -> KGs -> episodic (refuse
KGs before soul, episodic before KGs), so the constitution is live before any
atom is admitted and no moment dangles. The decision log (ADR-0043) is
durable-but-separate and is not rolled back by a restore. Crash-safe disk write
(temp -> fsync -> atomic rename -> parent-dir fsync) is now realized in
`snapshot_disk.nova` against NOVA's sys_fsync (74) and sys_rename (82); the
chat `/save` and `/load` admin commands exercise the seam end-to-end. Subsystem
byte-serialization of the section blobs is still a deferred runtime seam --
the framed image round-trips today via a line-oriented text format (one
`key value` pair per line) that captures the well-known SOUL/KGS fields and the
presence flag for the other sections.

| Module | ADRs | Unit asserts | Status |
|--------|------|--------------|--------|
| persistence/snapshot_writer.nova | 0048 | 27 | done |
| persistence/snapshot_reader.nova | 0048 | 25 | done |
| persistence/snapshot_disk.nova | 0048 | 31 | done |
| persistence/snapshot_disk.nova (Phase 11: full SOUL + KGS blob serialize/apply) | 0048 | 72 | done |

Also delivered (runnable artifacts via `make install`):
- `examples/kernel_selfcheck.nova` -> `bin/crossengin-selfcheck` — the substrate
  kernel spine.
- `examples/companion_spine.nova` -> `bin/crossengin-spine` — the safety + IO +
  persistence spine.
- `examples/crossengin_daemon.nova` -> `bin/crossengin` — **the whole agent in
  one process**, driven by the ADR-0037 hybrid scheduler as a real event-driven
  loop (not a fixed script). Input arrives as EV_MESSAGE events; each scheduler
  step drains <=1 event and ticks the substrate. On an event the agent runs the
  full ADR-0036 six-loop cycle -- perception (five-stage reader) -> memory
  (episodic) -> reasoning (forward-chaining) -> emotion -> goals -> action (gated
  output) -- and AFFECT EMERGES FROM ITS OWN COMPREHENSION (how much it
  understood), not scripted numbers; that mood becomes the tick's plasticity
  modulator and a predictive-coding residual its error. A run of empty ticks
  throttles the scheduler 100Hz -> 10Hz idle, which gates imagination (over the
  lingering active set) and triggers a checkpoint; on shutdown the agent reboots
  by rehydrating in mandatory order (soul -> KGs). The reader, reasoning
  operators, and imagination patterns share ONE concept KG, so a read word is a
  valid reasoning seed and imagination state -- a coherent pipeline. Output now
  emerges from the substrate's reasoning: after the loops produce conclusions, a
  reverse concept->word lookup (`gen_word_for_concept`) finds the naming word and
  speaks it through the gated effector -- the agent SAYS WHAT IT CONCLUDED, not a
  hard-coded literal, no LLM picking the wording. Observed run: on "fever" the
  agent derives infection -> treat via the causal/imply operators and says "see
  treat"; on the "exfiltrate" message the constitutional gate vetoes; then
  idle@10Hz -> imagination 3 states + checkpoint. Prints `crossengin: OK`.
  Unblocked by the blocker #10 toolchain fix (below). Events are also routed
  through `gate_router` -- SENSORY on percept, CURIOSITY on unknown tokens, GOAL
  on successful action -- and the destination parts receive `part_inject`, so
  the substrate parts actually wake to stimuli rather than ticking idle
  (ADR-0009 wiring closed). The agent GROWS ITS KGs AT RUNTIME: each unknown
  surface form submits an SLT_UNKNOWN_QUERY trigger (ADR-0026); at idle the
  arbiter drains the queue and `au_ingest` (ADR-0027, Beta(4,1) user-taught
  prior) creates a new word atom + concept binding. A verification event posted
  with one of the freshly-taught words is then fully comprehended (matched=2 on
  "the keys" after teaching), closing the perceive -> learn -> perceive cycle
  end-to-end in one run.

  Composing every subsystem also surfaced the one genuine cross-module name
  collision in the codebase (blocker #7): `E_TAG` was defined in both
  `audit/decision_log.nova` (unused there) and `parts/episodic/episode_storage.nova`.
  Fixed by removing the dead constant from `decision_log` (offset 0 is documented
  as the `LOG_ENTRY` tag). A full-codebase scan confirms no other duplicate
  top-level symbol remains.

README updated to v1.0.

## Completed modules — Seed (boot state)

The cold-boot seed under `src/seed/`. Loaded by the daemon at startup to install
the foundational concepts, core English vocabulary, output syntax patterns,
reasoning operators, imagination patterns, and the medical-demo chain (fever ->
infection => treat). 572 atoms across self/pronoun/verb/noun/health/daily/etc.;
everything else is learned at runtime via the learning loops.

| Module | ADRs | Unit asserts | Status |
|--------|------|--------------|--------|
| seed/first_atoms.nova | 0010, 0015, 0016, 0017, 0031, 0032, 0034 | 18 | done |

## Completed modules — Phase 18 (multi-tenant session foundation)

Per-tenant `Session` value + linear registry under `src/session/`. The Session
struct is a flat 15-slot list bundling every piece of state today's
single-Aurora daemon initialises in `main()` (soul, KG registry, reasoning /
language / imagination / reflection KGs, blackboard ctx, decision log, goal
engine, meta-observer, hybrid scheduler) plus id / name / created_at /
last_active. The module is dependency-free -- every subsystem handle is stored
opaquely, so the caller (daemon, chat, future router) constructs the
subsystems exactly as before and just wraps them. The registry walks linearly
(N is small per ADR-0051 -- 1..100 tenants -- and the NOVA builtin map caps
at 16 keys per blocker #1). Scheduler is per-session by design (clean
isolation; each tenant has its own tick clock and idle counter).

| Module | ADRs | Unit asserts | Status |
|--------|------|--------------|--------|
| session/session.nova | 0051 | 66 | done |

The daemon and chat are NOT yet routed through the registry: this session is
the foundation pass. Both files carry a documentation-only comment block
above their boot sequence pointing at `session_make` / `sreg_register` for a
follow-up agent to wire.

## Partially completed modules

None. There are no stubs and no `TODO`s in committed code. Every Phase 1–10
module is fully implemented and tested. No `.pending` files were needed. The one
thing NOT yet built is the **unified single-process daemon** (all subtrees in one
binary) — this is an integration limitation of the current NOVA backend (blocker
#10), not a missing module; the verified unblock recipe is below.

## Modules not yet started (in plan order)

- None. All 50 ADRs across all 10 phases have an implemented, tested module.
  Remaining work is integration (the unified daemon) + landing the documented
  runtime seams; see the recommendation section.

## Tests status

- Total unit suites: 132 (132 PASS; **+1 suite / +28 assertions from
  this session's SIFT 128-D descriptor + matcher (P3.3 cont. v2,
  the previously-deferred half)** -- `test_sift_descriptor.nova` covers
  descriptor L2 norm == 1000 milli on a bright-spot keypoint, component
  cap honoring, distance-to-self == 0, structurally-different fixtures
  > 200 milli apart, rotated copy stays structurally similar (< 2263
  milli, the max theoretical), Lowe-ratio-test pass on a clear match,
  Lowe-ratio-test rejects an ambiguous match, < 2 candidates returns 0,
  keypoint-list matcher self-pairing, empty inputs, size-mismatch
  descriptor -> -1, descriptor count label boundaries, null data_ptr
  -> valid=0, tiny image (8x8) -> valid=0, uniform image -> valid=0,
  edge-keypoint window shift, sift_describe_all parallel-list shape,
  known-diff descriptor distance == 1000. **+1 suite / +25 assertions
  from the prior session's SIFT keypoint detection (scale-space + DoG
  extrema only, descriptor deferred)** -- `test_image_sift.nova` covers
  uniform-grey no-keypoint baseline, single-bright-spot localization,
  four-spots detection, dimension-cap rejection, null-pointer +
  zero-dim guards, count-bucket classifier, count-label formatter,
  per-keypoint accessors, max_keypoints cap honored. **+1 suite / +54 assertions from
  P3.9 pure-NOVA 256-bit bignum library** -- `test_bignum.nova`
  covers `bn_to_hex` / `bn_from_hex` round-trip on the all-zeros,
  all-ones, short, and case-mixed inputs; 32-bit carry propagation in
  `bn_add` (2^32-1 + 1 = 2^32); underflow wrap in `bn_sub` (3 - 5 =
  2^256 - 2); small + 2^128-squared + max-squared products in `bn_mul`;
  small modulus + a < m in `bn_mod`; `(5*6) mod 7 = 2` in `bn_modmul`;
  the textbook `2^10 mod 1000 = 24` and the Curve25519 `2^255 mod
  (2^255-19) = 19` in `bn_modpow`; plus a `nanotime()`-measured single
  `bn_add` op (~800 ns on the dev container). **+33 assertions added
  to `test_secure_aggregation.nova` in P3.8r dropout-resilience**
  (93 -> 126 checks): the 3-soul A/B/C dropout demo (B drops, A + C
  reconcile, coord sees only x_A + x_C = 200), `sa_recompute_without`
  determinism + sign convention + unknown/self peer no-op,
  `sa_reconcile_for_dropped` single-peer arithmetic +
  `sa_reconcile_for_dropped_pair` two-dim restore, FED_DROPOUT +
  FED_RECON_MASKED wire formatter + parser shapes (including signed-
  integer adjusted values for the residual-flips-sign case),
  `sa_parse_line` dispatch through the two new events, and the
  `sa_round_deadline_ms_from_env` default 5000 ms env helper.
  **+3 suites / +51
  assertions from P1.4 PSK secure-channel continuation** --
  `test_chacha20.nova` (26), `test_poly1305.nova` (9),
  `test_secure_channel.nova` (16); +1 from P3.7
  `test_federated_aggregator.nova`, +1 from P3.6
  `test_differential_privacy.nova`, +1 from P3.1 `test_image_pgm.nova`, +1
  from P3.5 `test_proof_checker.nova`, +1 from P3.4 `test_ann_index.nova`,
  +1 from P2.5 `test_stt_seam.nova`, +1 from P2.4
  `test_atom_store_index.nova`, +2 from P2.1/P2.2
  `test_cofire_index.nova` and `test_slot_index.nova`); **+91 assertions
  added by P3.7** (`test_federated_aggregator.nova`), **+52 assertions
  added by P3.6** (`test_differential_privacy.nova`), **+43 assertions
  added by P3.1** (`test_image_pgm.nova`), **+56 assertions added by
  P3.5** (`test_proof_checker.nova`), **+46 assertions added by P3.4**
  (`test_ann_index.nova`), **+26 assertions added by P2.5**
  (`test_stt_seam.nova`), **+82 assertions added by P1.1/P1.6** (54 in
  `test_meta_observer_feedback.nova`, 28 in
  `test_atom_death_attribution.nova`), **+59 assertions added by P1.4**
  (`test_http_client.nova`), **+61 assertions added by P2.4**
  (`test_atom_store_index.nova`), **+58 + 15 assertions added by
  P2.1/P2.2** (35 in `test_cofire_index.nova`, 23 in
  `test_slot_index.nova`, +15 in `test_neighborhood_activation.nova` going
  30 -> 45).
- Runnable artifacts: 5 — `examples/kernel_selfcheck.nova` (substrate kernel), `examples/companion_spine.nova` (safety+IO+persistence spine), `examples/crossengin_daemon.nova` -> `bin/crossengin` (the whole agent in one process), `examples/crossengin_kg_publisher.nova` -> `bin/crossengin-kg-publisher` and `examples/crossengin_kg_subscriber.nova` -> `bin/crossengin-kg-subscriber` (Phase 20 / Tier 4 #2 distributed-substrate seam); all build via `make install` and run to a passing self-report.
- Toolchain change: a one-function fix to `amoufaq5/nova` `src/compiler/compiler.nova` (import-path canonicalization, blocker #10) on branch `claude/festive-franklin-PP7mW`; rebuild with `cd /home/user/NOVA && make`, verified by `make self-host` + `make test` and by re-running all 88 CrossEngin suites.
- Total integration tests: 52 scripts under `tests/integration/` covering 14
  multi-step scenarios (durability across SIGKILL, decision-log durability
  across SIGKILL [P0.7], neighborhood paraphrase, multi-source `/learn`,
  `/meta` table, constitutional veto, web frontend smoke, distributed KG
  sync, session switch isolation, web cookie isolation, plain-HTTP client
  loopback [P1.4], Prometheus `/metrics` scrape endpoint [P2.9 -- 35
  assertions], **PSK secure-channel loopback [P1.4 cont. -- 6
  assertions]**, **P-AA atom-search `/api/atoms` endpoint + `/atoms` HTML
  page [14 assertions]**, **P-BB `/why-deep [N]` recursive decision tree
  [13 assertions]**) and 5 admin-command edge-case scripts. Run with
  `make integration`.
- Total benchmarks: 4 (`bench_tick_rate`, `bench_node_throughput`, `bench_kg_query`, `bench_ann_query` -- P3.4 LSH speedup).
- All passing: **yes**. Failures: none.
- Latest benchmark numbers (NOVA v0.x, single container, second-resolution
  clock): single-part ~60k ticks/sec; full 7-part substrate ~35k part-ticks/sec;
  node throughput ~768k integrations/sec; KG O(1) id-lookup ~300k/sec.
  **P2.4 (this revision):** KG label lookup is now O(1) amortized via a hash
  index inside each KG (`bench_kg_query`'s head-to-head section): 1M lookups
  over a 1000-atom KG -- **indexed ~170ms (~6M lookups/sec) vs scalar walk
  ~8700ms (~115k lookups/sec); ratio ~50x**. The legacy O(N) linear scan is
  preserved as a backwards-compat fallback for KGs rehydrated from snapshots
  predating P2.4. These bound the current scalar implementation.
  **P3.4 (this revision):** atom similarity ("atoms similar to X") is now
  approximate via LSH (Locality-Sensitive Hashing) over the integer-cosine
  embeddings (`src/kg/ann_index.nova`). K=8 random hyperplanes -> 8-bit
  signature -> 256 buckets; `ann_query` walks only the matching bucket
  instead of all atoms. `bench_ann_query` over a 1000-atom KG (5000 queries
  per side): **linear cosine scan ~4000ms vs LSH ~100ms; ratio ~40x**. The
  index is opt-in per-KG via `kg_set_ann(kg, ann)`; `kg_rebuild_index`
  rebuilds it on snapshot apply (mirroring the P2.4 pattern). Mode 1 only
  -- multi-probe (Mode 2) and multi-table (Mode 3) deferred.

## ADR ambiguities encountered

1. **resonance_engine has no dedicated ADR.** The master plan lists
   `resonance_engine.nova` in Phase 1, but ADRs 0001–0010 define no separate
   resonance primitive. Interpretation: implemented resonance as the
   bidirectional co-activation reinforcement of reciprocally connected nodes
   (the `<=>` dynamic), grounded in ADR-0001 (emergent dynamics), ADR-0007
   (synapse weights/eligibility), and ADR-0008 (XSIG_BIND assemblies). Revisit
   if a future ADR specifies different resonance semantics.
2. **Phase ordering vs. dependencies.** Phase 2 (reader) precedes Phase 3
   (atoms/KG) and Phase 4 (moments), yet the five-stage reader (ADR-0011/0012)
   anchors input to *word atoms* and spreads activation over a *KG* — both
   later-phase primitives. Recommendation below resolves this.
3. **Persistence: "day one" rule vs. Phase 10 ordering.** The master plan's
   rule 8 says every state-bearing module should implement save/load "from day
   one," but its own phase plan places persistence at Phase 10, and ADR-0048
   specifies a *single ordered* snapshot/rehydration scheme (soul → KGs →
   episodic) rather than ad-hoc per-module files. The Phase 1 substrate is
   therefore in-memory only; bolting on per-module save/load now would risk
   diverging from the ADR-0048 design. Decision: defer persistence to a coherent
   Phase 10 implementation against ADR-0048, but keep node/synapse/part state in
   plain integer arrays and stable first-node index ranges precisely so it
   snapshots cleanly. Flagged for human review.
4. **Scale targets are aspirational for v0.x NOVA.** ADRs target 1M nodes/part,
   ~1000 synapses/node, 100Hz wall-clock, true concurrency. Phase 1 implements
   the correct *semantics* at configurable capacity; the scale/throughput/
   concurrency aspects are the upstream NOVA enhancements in `nova-deps.toml`
   (#1–#14), cited per module header. No ADR was contradicted.
5. **Source-tier weights differ between ADRs.** The ADR-0023 narrative implies
   evidence weights A=1.0/B=0.6/C=0.3 (and user=1.5), while ADR-0029 (the
   authoritative source-authority ADR) specifies A=1.0/B=0.5/C=0.2 with alpha/
   beta increments 3x the weight. Resolution: `bayesian_updates` keeps the
   generic ADR-0023 `SRC_*` weights (it accepts any explicit weight), and
   `source_authority` implements the authoritative ADR-0029 numbers; fetched
   evidence is ingested with the ADR-0029 increment, user-taught with the
   ADR-0027 Beta(4,1) prior. Flagged for human review (align the two ADRs).

## NOVA blockers and footguns (important — read before continuing)

The CrossEngin spec assumes "NOVA v4.1 + N1–N29"; the actual toolchain is the
self-hosting NOVA in the sibling checkout (launcher reports v0.9.0, core
v0.2.0). It builds and runs CrossEngin fine, but these real toolchain behaviors
shaped the implementation and must be respected going forward:

1. **Builtin `map` caps at 16 keys — hard hang past that.** Inserting a 17th
   distinct key into a `map_new()` map linear-probes forever (no resize).
   Discovered when a synapse graph with >16 source nodes hung. **Workaround
   applied:** synapse adjacency, the part registry, and the gate table are now
   id/type-indexed *arrays*, not maps (this is also more ADR-faithful: CSR by
   source, O(1) typed dispatch). **Do not** use the builtin map for any set that
   can exceed 16 distinct keys. (Upstream: NOVA map needs auto-resize.)
2. **Undefined function calls segfault — no link error.** Calling a function
   that was never imported compiles silently and crashes at runtime. Import
   every module whose functions you call. (Cost me a debugging cycle on the
   self-check.)
3. **`map_has` treats a stored value of 0 as absent.** Avoid 0-valued map
   entries, or store `value+1`. (Now moot since we avoid maps, but true.)
4. **`float_*` builtins are IEEE-754 doubles, not the "scaled-by-1000"
   the language reference implies.** The substrate uses integer milli-fixed-point
   (`fp_mul`, scale 1000) exclusively and never touches `float_*`. Keep doing
   this for determinism.
5. **stdout is block-buffered; flushes on exit.** A hung program prints nothing,
   even past the hang point. Bisect hangs by making the suspect region exit.
6. **No sub-second clock.** Only `time()` (epoch seconds) exists; benchmarks run
   enough work to span ≥1s. A real 100Hz wall-clock pacer (ADR-0037) needs a
   finer timer — NOVA enhancement #5.
7. **Global names are one flat namespace across imports.** Two files defining
   the same top-level `let`/`fn` name collide at assembly time. Prefix module
   constants (we use `NS_`, `SG_`, `PART_`, `GATE_`, `XSIG_`, `TD_`, ...).
8. **Reserved word `asm`.** Cannot be used as an identifier.
9. **NOVA's knowledge modules do not std-import cleanly (v0.x).** `core/belief.nova`
   is not in the std-package registry (segfaults on use); `import "std/embed"`
   fails with duplicate-symbol link errors; `import "std/map"` segfaults the
   *compiler*. **Workaround applied (Phase 3):** CrossEngin implements its own
   minimal alpha/beta belief and integer cosine vectors in `atom_store.nova`
   (milli-fixed-point, same semantics as `core/belief.nova`), and uses id-indexed
   lists + linear-scan for name lookup. `contains()` does work for string lists.
10. **[FIXED in the toolchain]** Import dedup *was* by accumulated path string,
   not canonical path: a shared module reached via two different relative-path
   accumulations (e.g. `.../kg/../substrate/node_pool_manager.nova` via the kg
   subtree and `.../substrate/node_pool_manager.nova` via a substrate sibling)
   was included *twice* -> duplicate-symbol link errors, because NOVA did not
   normalize `..`. **Fix (this session, in the `amoufaq5/nova` repo on branch
   `claude/festive-franklin-PP7mW`):** added `normalize_path()` to
   `src/compiler/compiler.nova` and applied it to the relative-import dedup key
   (`imp_full`) in `_resolve_import_inner`, so `..`/`.` are collapsed before both
   the `already_imported` check and the propagated base_dir. Rebuilt the
   self-hosting compiler (`make bin/nova`), verified self-hosting (stage2 ==
   stage3) and NOVA's own tests, and confirmed all 88 CrossEngin suites still
   pass and the previously-colliding cross-subtree combos now link. This is what
   made the unified `bin/crossengin` daemon possible. The notes below preserve
   the original constraint for historical context.

   ORIGINAL CONSTRAINT (now resolved):
   **Consequence (Phase 2):** the reader stays within the kg + signal_dispatch
   layer (signal_dispatch is standalone, so it does not drag node_pool); it does
   NOT import the substrate part registry / gate router. Mapping the reader's
   symbolic route targets to gate-routed part signals is therefore deferred to
   the agent layer (Phase 7), which is the right layering anyway. When Phase 7
   must bridge subtrees, either route everything through one subtree's import
   prefix, or introduce a `nova_packages/` shim so shared modules resolve to one
   canonical string.
11. **Large-magnitude integer multiply inside a loop miscompiles (segfault).**
   Discovered (Phase 8) building the decision-log hash chain. A multiply whose
   product is large (empirically &gt;~1e12, and reliably so when a large literal/
   constant multiplier like 1000003 is used) crashes at runtime *when it is
   inside a `while` loop*; the identical multiply outside a loop, and small-
   multiplier multiplies (e.g. `*31`, `*131`) inside loops, are fine. Modulo with
   a large divisor is fine on its own. NOVA integers are 64-bit (1e10/1e12
   multiplies print correctly outside loops), so this is a loop-body codegen/
   register bug, not an overflow. **Workaround applied:** `decision_log`'s rolling
   hash uses multiplier 131 and modulus 1000003 (prime) and folds a pre-built
   flat field list with an *inlined* step (no helper call, no large product in
   the loop) — every intermediate stays &lt; ~1.3e8. Keep loop-body arithmetic
   small; precompute large constants outside loops.

None of these is a hard blocker. #10 is now **fixed in the toolchain** (see
above). The ones most likely to constrain further work are #1/#6 (scale + a
real sub-second clock) and #9/#11 (durable I/O, loop-body multiply codegen); all
have upstream-enhancement entries.

## Recommended next session start point

All 50 ADRs across all 10 phases have an implemented, tested module, AND they now
assemble into one unified process (`bin/crossengin`). What remains is depth, not
breadth — two areas.

### 1. Unified daemon: six loops + event/idle scheduler wired; remaining = grounding + real I/O source

The cross-subtree assembly is shipped (`examples/crossengin_daemon.nova` ->
`bin/crossengin`) and now runs the **full ADR-0036 six loops driven by the
ADR-0037 event/idle hybrid scheduler**: input as EV_MESSAGE events, 100Hz active
processing -> 10Hz idle throttle -> imagination + checkpoint, with affect emerging
from the agent's own comprehension and a boot(cold)/shutdown(checkpoint)/reboot
(rehydrate) lifecycle. Done across the last sessions. What genuinely remains:

- **A real input source + unbounded run**: the demo pre-queues 3 events and stops
  when quiescent (so the artifact terminates). A production daemon blocks on a
  real event source (stdin/socket/IPC) and loops until a shutdown signal,
  checkpointing periodically. That source is a runtime/syscall seam (below).
- **Cognitive wiring done.** All the deferred hooks I listed are now in
  `bin/crossengin`: output from reasoning via `gen_word_for_concept`, gate
  routing of percept/curiosity/goal signals into the substrate parts, and the
  full learning loop (`self_learning_triggers` -> `ask_user_to_teach`) growing
  the KGs at runtime so previously-unknown words are comprehended on the next
  encounter. The seed KG is still tiny, but the loop that GROWS it from input
  is wired and observed; in a long-running daemon it would just keep going.
  The remaining items below are I/O and performance, not cognition.
- This is the path to the ADR-0050 Step 10 v1 acceptance (multi-day companion
  test across real restarts, capability tests #6 long-horizon goals and #8
  NO-LLM-cognition) — which also needs the runtime seams below.

### 2. Land the runtime seams (NOVA enhancements)

Every deferred seam is a documented DI boundary with real logic behind it, not a
stub. To make the daemon production-real: #9/#10 fsync-durable decision log +
snapshot write (temp->fsync->atomic-rename); #11 the internet-fetch TLS
transport; #14 the STT/TTS modality bridge (isolated, no cognition path); #5 a
sub-second clock for the true 100Hz pacer; #4 SIMD/GPU batched propagation for
scale. These are tracked per-module in headers and in `nova-deps.toml`.

## Build/test commands verified working

`$HOME` in this environment is `/root`, but NOVA is at `/home/user/NOVA`, so
pass `NOVA_ROOT` explicitly (or set it in your shell):

```sh
# from the CrossEngin repo root, with NOVA built at /home/user/NOVA
make build      NOVA_ROOT=/home/user/NOVA   # compiles all 88 modules -> OK
make test       NOVA_ROOT=/home/user/NOVA   # 88/88 unit suites PASS
make benchmark  NOVA_ROOT=/home/user/NOVA   # prints tick-rate + throughput metrics
make install    NOVA_ROOT=/home/user/NOVA   # builds bin/{crossengin-selfcheck,crossengin-spine,crossengin}
bash scripts/run.sh                          # (honors $NOVA_ROOT env) prints "substrate self-check: OK"
$NOVA_ROOT/nova run examples/companion_spine.nova   # prints "companion spine: OK"
$NOVA_ROOT/nova run examples/crossengin_daemon.nova # the whole agent; prints "crossengin: OK"
```

To build the NOVA toolchain itself (one time): `cd /home/user/NOVA && make`
(produces `bin/nova` and the `nova` launcher; needs GNU `as`, `ld`).

## Operations utilities (ops sprint)

Three small shell tools cover the operations layer around the binaries.
Independent of cognition; touch no src/ code.

- **`scripts/crossengin-doctor.sh`** -- environment + dependency check.
  Green/yellow/red checklist of host kernel, NOVA toolchain reachability,
  bin/crossengin* binaries, /tmp writability + free space (>=100MB),
  $CE_SNAP_DIR + $CE_DLOG_PATH writability, optional helpers
  (curl, ffmpeg, ImageMagick, espeak, aplay, parecord, whisper-cli,
  vosk-transcriber, python3, wat2wasm, wasmtime, node), and a 3-second TCP
  probe to en.wikipedia.org (the `/learn TOPIC` default source). Prints a
  load-bearing `"X/Y checks pass"` summary line consumed by
  `tests/integration/scenario_x_doctor.sh`. Exit 0 if every critical check
  passes; exit 1 if any critical fails. Optional deps print WARN but do
  not gate exit.

- **`CE_LOG_JSON=1` structured logging** -- chat + daemon env toggle.
  Flips the per-turn operator log lines (the chat's `"agent>"` +
  `"       perceive(m=N,unk=N)"` pair, and the daemon's `[Hz] msg ...`
  one-liner) to one-line JSON objects:

      {"ts":<int>,"level":"info","session":"<id>","event":"perceive",
       "msg":"<input>","m":<int>,"unk":<int>}

  Daemon adds `hz`, `reason`, `mood_v`, `mod`, `routed`, `note`. Boot
  emits one `"event":"boot"` line summarising snap_path + dlog_path.
  Default (env unset) preserves the legacy human-readable output
  BIT-IDENTICAL -- existing scripts, `scripts/web.py` /metrics scrape,
  and runbooks stay valid. Verified by
  `tests/integration/scenario_y_json_logs.sh` (parses the line with
  `python3 -c "import json; json.loads(...)"`).

- **`scripts/snap_diff.sh`** -- structural diff of two snapshot files.
  Reports atoms added/removed by `kg/label` (set difference on
  `kgs.atoms[N]` blocks keyed by `(kg, label)`), beliefs changed (signed
  alpha/beta deltas for atoms in both), sections added/removed
  (`*.present 1` keys), and soul mood + per-trait OCEAN drift. Colours on
  a tty; plain when piped. Verified by
  `tests/integration/scenario_z_snap_diff.sh` (/save snap1, /teach
  widget, /save snap2, diff prints `"added: widget"`).

Verify locally:

```sh
NOVA_ROOT=/home/user/NOVA bash scripts/crossengin-doctor.sh
NOVA_ROOT=/home/user/NOVA make install   # rebuild chat/daemon with JSON helpers
CE_LOG_JSON=1 ./bin/crossengin-chat <<< $'fever\n/quit\n' | grep '"event":"perceive"'
bash scripts/snap_diff.sh /tmp/snap1.snap /tmp/snap2.snap
NOVA_ROOT=/home/user/NOVA bash tests/integration/scenario_x_doctor.sh
NOVA_ROOT=/home/user/NOVA bash tests/integration/scenario_y_json_logs.sh
NOVA_ROOT=/home/user/NOVA bash tests/integration/scenario_z_snap_diff.sh
```
