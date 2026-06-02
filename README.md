# CrossEngin

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/amoufaq5/Crossengin-demo)

CrossEngin is a non-LLM cognitive **substrate** system, implemented in
[NOVA](https://github.com/amoufaq5/nova). It targets AGI-relevant capability —
continuous learning, self-directed skill acquisition, theory of mind,
initiative, counterfactual reasoning, long-horizon goals, and self-awareness of
identity, state, and goals over time — by running a fabric of uniform
computational units rather than orchestrating a pipeline of modules.

> **Status: v1.0 — all 10 phases complete and assembled into one unified agent
> process.** Implemented in NOVA and verified against the real self-hosting
> toolchain: 148 modules compile (`make build`). R12C adds
> `src/kg/louvain.nova` — Blondel-2008 two-phase greedy modularity
> optimiser, the gold-standard companion to R11F's label-propagation
> detector. Phase 1 picks moves analytically (DQ in integer-only
> milli units: `gain_scaled = 2m*k_u_in_C - k_u*Sigma_tot_C`); Phase 2
> aggregates communities into super-nodes and recurses until no merge
> improves modularity. On the **Zachary 1977 karate-club benchmark
> (34 nodes, 78 edges)** Louvain reports modularity 399 milli vs
> R11F's 256 milli (**+143 milli, 56% relative improvement**) and
> finds 3 communities vs LPA's 2. On the barbell + 3-triangle
> fixtures both algorithms find the same global optimum (423/667
> milli). New chat admin: `/louvain` prints
> `(LOUVAIN n=N largest=L modularity=M milli edges=E depth=D)`.
> Module exports `louvain_communities`, `louvain_label_at`,
> `louvain_community_members`, `louvain_largest_community`,
> `louvain_modularity`, `louvain_levels`, `louvain_dendrogram` (the
> hierarchical merge tree, finest -> coarsest). 67 unit assertions
> (`tests/unit/test_louvain.nova`) + 19 integration assertions
> (`tests/integration/scenario_zz_louvain.sh`); all green. R11F's
> 71 unit checks remain bit-identically green. R11B extends
> `src/io/transducers/audio_pitch.nova` (R10F's file) with parallel
> YIN-class entry points (`pitch_estimate_frame_yin`, `pitch_track_yin`,
> `pitch_run_yin_command`) that cure R10F's first-formant snap on
> harmonic-rich natural speech. YIN (de Cheveigne & Kawahara 2002)
> replaces autocorrelation's argmax with the cumulative mean normalized
> difference function `d'(tau) = d(tau) * tau * 1000 / running_sum`,
> whose MINIMUM marks the period (no formant ambiguity). Pure integer
> arithmetic, no FFT, no floats. R10F autocorrelation API stays
> unchanged for back-compat. **JFK head-to-head: R10F mean 220 Hz
> (formant snap) -> R11B YIN mean 145 Hz (in adult-male [80..180] Hz
> band).** Klatt /uw/: 296 Hz -> 145 Hz. Pure 100/200/400 Hz sines:
> both methods parity (exact). New chat admin: `/pitch_yin PATH`
> prints `(pitch_yin PATH: f0_mean=N Hz, ...)`. 35 unit assertions
> (`tests/unit/test_audio_pitch_yin.nova`) + 9 integration assertions
> (`tests/integration/scenario_vv_yin_pitch.sh`); all green. R10F's
> 52 unit + 20 integration tests remain bit-identically green. R11F adds
> `src/kg/graph_clustering.nova` — Raghavan-2007 label-propagation
> community detection over the KG's xref link graph, the STRUCTURAL
> companion to R10C's textual TF-IDF ranker. R10C asks "which atoms
> LOOK alike" (TF-IDF over labels); R11F asks "which atoms are LINKED
> to each other" (xref-induced communities). Pure integer arithmetic,
> no FP weights. Each atom starts with its own atom_id as label; per
> pass, every atom (in deterministic-shuffled order) adopts its
> neighbours' most-frequent label, tie-breaking by lowest id. Up to
> 20 iterations; Raghavan's empirical < 5 iters holds on barbell +
> 3-clique fixtures. Newman modularity Q in milli (scale 1000):
> `(sum_intra * 1000) / m - (sum_a_sq * 1000) / (4*m*m)`, signed so
> anti-clusterings stay representable. New chat admin: `/communities`
> prints `(COMMUNITIES n=N largest=L modularity=M milli edges=E
> iter=I)`. Barbell fixture (two 4-cliques + bridge) -> 2 communities,
> 13 edges, modularity 423 milli, 2 iterations; 3 disjoint triangles
> -> 3 communities, 9 edges, modularity 667 milli; single 4-clique ->
> modularity ~ 0. Public API: `gc_label_propagation(kg, max_iter)`,
> `gc_label_propagation_seeded(kg, max_iter, seed)`, `gc_label_at`,
> `gc_community_count`, `gc_community_members`,
> `gc_largest_community`, `gc_modularity`. 71 unit assertions
> (`tests/unit/test_graph_clustering.nova`) + 20 integration
> assertions (`tests/integration/scenario_xx_communities.sh`); all
> green. R10C/R8F/R5/R8E remain bit-identically green. R10F earlier
> shipped
> `src/io/transducers/audio_pitch.nova` — autocorrelation-based F0 (pitch)
> estimation that completes the audio triad next to R6E Klatt synthesis
> and R7F+R9B VAD. Per ~30 ms frame compute
> `R(tau) = sum x(n) * x(n+tau)` over tau in [sr/f0_max..sr/f0_min] (32..320
> samples @ 16 kHz / 50..500 Hz), pick argmax, then sweep integer multiples
> for octave-down correction at the classical 0.92 threshold. Voicing rides
> on the normalized peak `R(best_tau) / R(0) >= 0.300`. Output in centi-Hz
> (Hz × 100) to preserve sub-Hz resolution in pure integer arithmetic. Pure
> sines at 100, 200, 400 Hz @ 16 kHz hit exactly 100/200/400 Hz; white
> noise + silence resolve unvoiced; Klatt /uw/ vowel resolves at 296 Hz
> (formant snap, in [50..500] Hz band, voicing 868 milli); JFK
> adult-male WAV resolves at 220 Hz mean across 287 voiced frames
> (first-formant snap; YIN-class cure on the R10F roadmap; see
> AUDIO_AUDIT.md "R10F"). New chat admin: `/pitch PATH` prints
> `(pitch PATH: f0_mean=N Hz, f0_range=L-H Hz [...])`; graceful FAILED
> on missing WAV. 52 unit assertions (`tests/unit/test_audio_pitch.nova`)
> + 20 integration assertions (`tests/integration/scenario_tt_pitch.sh`);
> all green. R10C adds
> `src/kg/semantic_search.nova` — a purely textual TF-IDF +
> integer-cosine ranker over atom labels. Closes the KG read story
> alongside exact lookup (`atom_store.kg_find_atom`), episodic
> retrieval (R6F + R8F `episodic_recall_*`), and embedding-cosine
> nearest-neighbour (P3.4 `ann_query`). No neural embedding, no LLM
> call -- deterministic counting math in milli-fixed-point
> (FP_SCALE=1000). Tokenize splits on whitespace + ASCII punctuation,
> lowercase, drops < 3 chars / > 30 chars. Sub-linear TF
> (`1 + log2(count)`) + IDF (`log2(n) - log2(df) + smoothing`, the
> log subtraction sidesteps integer-div precision loss when df ~ n)
> + cosine (`dot * 1000 / (norm_q * norm_d)` with Newton sqrt).
> Sparse index: forward `[atom_id -> [(tid, tfidf_milli)]]` + inverted
> `[tid -> [atom_id...]]` + lazy IDF cache. Public API:
> `ss_index_new`, `ss_index_add_atom` (idempotent), `ss_search`,
> `ss_search_by_atom_id` (excludes the query atom). New chat admin:
> `/find <query>` builds a transient index over `kg_atoms` and prints
> top-5 as `FIND query="..." matched=N` / `RESULT rank=K atom_id=A
> sim=M milli` / `FIND_END query="..."`. On the 10-atom
> semantic_search_demo fixture, `/find "machine learning"` ranks the
> ML atom (id=1) at sim=521 milli, the deep-learning atom (id=2) at
> 171 milli; identical-vector cosine = 1000 milli; orthogonal (disjoint
> vocab) = 0. 73 unit assertions
> (`tests/unit/test_semantic_search.nova`) + 21 integration assertions
> (`tests/integration/scenario_rr_semantic_search.sh`); all green.
> R8F episodic retrieval (96 + 19), R6F consolidation (79 + 18), and
> R5 atom-store tests remain bit-identically green. +1 from R10B
> adding
> `src/io/transducers/vosk_backend.nova` — Vosk offline STT as a
> first-class alternative to whisper.cpp (~50 MB English model, pure-C
> streaming recognizer; JFK conf=968 milli). Auto-pick now does
> whisper > vosk > stub; `CE_STT_BACKEND=vosk` forces the new path.
> R10B also closes the R8B follow-up on per-utterance whisper
> confidence: `whisper_transcribe_with_confidence` parses
> `src/io/transducers/vosk_backend.nova` — Vosk offline STT as a
> first-class alternative to whisper.cpp (~50 MB English model, pure-C
> streaming recognizer; JFK conf=968 milli). Auto-pick now does
> whisper > vosk > stub; `CE_STT_BACKEND=vosk` forces the new path.
> R10B also closes the R8B follow-up on per-utterance whisper
> confidence: `whisper_transcribe_with_confidence` parses
> whisper-cli's `-ojf` JSON output for per-token probabilities
> (JFK lands at 895 milli, up from the legacy 800 ballpark). New
> tests: `test_vosk_backend.nova` (39 checks),
> `test_whisper_backend.nova` extended 28 -> 41 checks,
> `scenario_qq_vosk.sh` (16 assertions). All green. See AUDIO_AUDIT.md
> "R10B: per-utterance confidence + Vosk offline backend". R10D adds
> `src/io/transducers/image_optical_flow.nova` — Lucas-Kanade dense
> per-pixel optical flow between two consecutive PGM frames. For each
> interior pixel, compute integer image gradients (Ix, Iy via central
> differences) and the temporal gradient (It = I_next - I_prev) over a
> WIN_SIZE x WIN_SIZE window centered there, then solve the 2x2 normal
> equations via the closed-form integer inverse:
> det = (Sum Ix^2)(Sum Iy^2) - (Sum IxIy)^2; u_milli, v_milli scaled
> by 1000 / det. det == 0 (no-texture / aperture problem) marks the
> pixel invalid (flow reads 0). Default WIN_SIZE = 5 (OpenCV's
> calcOpticalFlowPyrLK default); dims cap 256x256. On the smooth
> quadratic-bowl fixture shifted DIAGONALLY by (1, 1): u ~ 918 milli,
> v ~ 1042 milli at probed interior pixels (target 1000, 1000 -- right
> on). Texture-less constant-fill fixture: 0 / 1024 pixels valid (100%
> degeneracy detection). Identical-frame fixture: mean magnitude = 0,
> density label "low". New chat admin: `/flow prev.pgm next.pgm` prints
> `(flow WxH mean_mag=Nmilli valid=K image_optical_flow_density_*)`.
> Visual seam emits `image_optical_flow_magnitude_*` +
> `image_optical_flow_density_*` atoms when `CE_VP_FLOW_PREV` env
> points at the previous PGM frame. 53 unit assertions
> (`tests/unit/test_optical_flow.nova`) + 11 integration assertions
> (`tests/integration/scenario_ss_optical_flow.sh`); all green. R5C
> SIFT, R6D ORB, R7E/R8D/R9A stereo, R5E Canny suites remain
> bit-identically green.
> R11A extends R10D with the classical Bouguet 2000 coarse-to-fine
> Gaussian pyramid + iterative warping so multi-pixel shifts stay
> inside the LK linear regime at every level. New public API
> `lk_pyramid_build`, `lk_warp_image`,
> `lk_optical_flow_pyramid(prev, next, w, h, win, levels=3, iter=3)`;
> chat `/flow_pyr prev.pgm next.pgm`. On the 8-px shift fixture
> R10D under-estimated at u=5697 milli; R11A pyramid reads
> u=7531 milli (target 8000, within +/-500). 4-px down: v=4116
> (target 4000); diag (3, 3): u=2962 v=2762 (target 3000, 3000).
> Per-iteration correction clamped at +/-4000 milli per pixel to
> suppress boundary-discontinuity outliers in the coarse-level
> warp. 52 new unit assertions
> (`tests/unit/test_optical_flow_pyramid.nova`) + 12 integration
> assertions (`tests/integration/scenario_uu_pyramid_flow.sh`).
> +1 from R9F adding
> `src/learning/byzantine_aggregation.nova` — two coordinate-wise robust
> aggregation rules (trimmed mean + median) that tolerate up to f
> malicious participants per federated round. The federated
> aggregator gains a parallel `fed_acc_byz_*` accumulator that keeps
> per-participant rows so the reducer can inspect each contribution;
> `byz_aggregate(updates, strategy, trim_k)` dispatches BYZ_NONE /
> BYZ_TRIMMED_MEAN / BYZ_MEDIAN. `CE_FL_BYZ_STRATEGY=trimmed|median|none`
> + `CE_FL_BYZ_TRIM_K=<k>` env knobs flip strategy without code edits.
> On the canonical 5-soul fixture with one 100x poisoning outlier
> (honest mean 705/205 milli), BYZ_NONE yields the poisoned 2563/2163,
> BYZ_TRIMMED_MEAN (trim_k=1) recovers 710/210, BYZ_MEDIAN recovers
> 710/210 -- ~370x skew reduction. The SecAgg vs Byzantine trade-off
> (filtering needs per-soul values; SecAgg hides them) is
> deliberately surfaced in SECAGG_AUDIT.md: operators pick ONE
> privacy posture per round. R9F adds 74 unit assertions
> (`tests/unit/test_byzantine_aggregation.nova`) + 15 integration
> assertions (`tests/integration/scenario_pp_byz_fl.sh`); all green;
> R5's SecAgg (170 unit + 48 integration) and P3.7 federated
> aggregator (91 unit) tests remain bit-identically green. R8F
> extended `kg/episodic.nova` in place with the READ-side companion
> to R6F's consolidation cycle -- six retrieval functions
> (`episodic_recall_by_member`, `episodic_recall_by_window`,
> `episodic_recall_by_pattern`, `episodic_recall_top_belief`,
> `episodic_recall_most_recent`, `episodic_provenance`) so other parts
> of the substrate can pull memories OUT of the episodic store by member,
> time window, pattern overlap, belief, or recency. Each returns up to
> `top_k` (default 10, cap 1000) ranked by a composite key (primary =
> count / last_seen / confidence depending on the API; secondary =
> last_seen desc; tertiary = id asc). New chat admin command `/recall
> {member <id> | window <start> <end> | top | recent}` routes through
> `episodic_recall_cmd` which runs a transient consolidation against the
> live moment stream and prints RECALL / EPISODE / RECALL_END lines.
> Module count unchanged (extension only); +1 from
> 77 R8F unit
> assertions (`tests/unit/test_episodic_retrieval.nova`) + 19 integration
> assertions (`tests/integration/scenario_mm_episodic_recall.sh`) all
> PASS; R6F's existing 79 episodic unit assertions and 37 episodic
> integration assertions remain bit-identically green (the read API is
> a pure extension of the write side). +1 from
> `persistence/schema_migration.nova` added in R8E -- a generic,
> declarative KG-atom schema-evolution framework that generalizes R5D's
> one-off snapshot v1->v2 migration into per-atom-kind ADD / RENAME /
> RETYPE / REMOVE rules. Each atom carries a `schema_version` payload
> field; migrations are registered once and frozen for bit-reproducibility
> across sessions. Two demo migrations ship today: V1->V2 ADD `created_ns`
> across every atom kind (defaulting to the snapshot's `timestamp` when
> the ADD default is 0), V2->V3 RENAME `label` -> `display_label` on
> FACT atoms only (LANG / CONCEPT / SKILL keep `label`). A new optional
> `schema.atoms_version <int>` line in the v2 meta block carries the
> per-file generation; older v2 readers ignore it (forward-compatible).
> The schema layer is orthogonal to the wire layer -- R5D's v1->v2
> container migration still works bit-identically. ~78 unit
> assertions (test_schema_migration.nova) + 17 integration assertions
> (scenario_ll_schema_migrate.sh); all green; R5D's snapshot migrate
> tests (37) + R6F's episodic tests (79 unit + 37 integration) all
> still pass. Documented in SNAPSHOT_FORMAT.md "Atom-shape schema
> evolution (R8E)" section,
> +1 from
> `io/transducers/image_stereo.nova` added in R7E -- block-matching
> Sum-of-Absolute-Differences (SAD) stereo disparity from horizontally
> separated PGM-P5 pairs, plus depth recovery via
> `depth_mm = baseline_mm * focal_pixels / disparity`. Per pixel: extract
> a 7x7 block in LEFT centered there, slide along the same scanline in
> RIGHT from x down to x - 64, compute SAD at each offset, store the
> minimizing offset as disparity. Depth at zero disparity clamps to
> STEREO_MAX_DEPTH_MM (100 m) as an "unknown / infinity" sentinel. On a
> synthesized "right = left shifted left by 10 px" textured pair the
> unit test asserts disparity == 10 EXACTLY at probed interior points;
> mean lands at 6-8 because the leftmost half-window columns cannot
> reach the true disparity. New chat admin: `/depth L.pgm R.pgm` prints
> `(depth WxH mean_disp=D density=Dmilli image_stereo_density_*)`.
> Visual seam emits `image_stereo_disparity_mean_*` +
> `image_stereo_density_*` atoms when `CE_VP_STEREO_RIGHT` env points
> at the companion right PGM. R8D LR-check + sub-pixel refinement
> (`/depth_q`) and R9A Semi-Global Matching (`/depth_sgm`) extend the
> quality / smoothness side: R9A aggregates the SAD cost volume along
> 4 scanline paths (Hirschmuller 2008 recurrence with P1=8 / P2=32
> default penalties) so the disparity is smooth in textureless
> regions where block-matching speckles -- the unit test asserts
> SGM variance <= BM variance in a noisy-flat band. Cap dims at
> 128x128 with MAX_DISP<=64 to keep the cost volume under 4MB.
> ~54 + 42 + 39 unit assertions + 10 + 11 + 13 integration
> assertions; all green. See IMAGE_AUDIT.md for the 8-path / MI
> data-term follow-ups,
> +1 from
> `io/transducers/audio_vad.nova` added in R7F (energy + ZCR Voice
> Activity Detection: 30 ms frames, 4-state hysteresis machine with K=3
> speech-on / M=10 speech-off thresholds; integrated into
> `audio_capture_to_pcm_vad` and `stt_transcribe_wav_vad` so STT only
> sees confirmed-speech PCM) and extended in R9B with adaptive noise-
> floor calibration so `/listen` resolves on natural recordings: VAD
> takes the MIN per-frame energy across the leading ~480 ms as the
> noise floor estimate and lifts the live threshold to
> `max(noise_floor × 3, R7F_floor)`. R9B also relaxes
> `audio_capture_to_pcm` to scan past optional RIFF sub-chunks
> (LIST/INFO/bext/...) so whisper.cpp's bundled JFK 16 kHz WAV parses
> cleanly. End-to-end `/listen /tmp/whisper.cpp/samples/jfk.wav`
> now produces `vad_segments=1` and the full JFK transcript through
> whisper. See AUDIO_AUDIT.md for the algorithm + verification,
> +1 from
> `io/transducers/whisper_backend.nova` added in R8B (whisper.cpp STT
> backend wired into the seam from R7F — `/listen` actually transcribes
> when whisper-main + ggml-tiny.en.bin are installed). Spawns the
> whisper-cli binary via fork+exec from NOVA with stdout drained into
> the seam's `[transcript, confidence_milli, error]` triple. Pre-flights
> `binary not found` / `model not found` / `wav not found` so each
> install gap surfaces precisely. Auto-picks `whisper` when env unset +
> binary+model present, falls back to `stub`. Env knobs:
> `CE_STT_BACKEND=whisper|stub|subprocess`,
> `CE_WHISPER_BIN=/path/to/whisper-main`,
> `CE_WHISPER_MODEL=/path/to/ggml-tiny.en.bin`. Confidence ballpark
> 800 milli on success (per-utterance confidence via
> `--print-confidence` is a future task). On the dev container the
> bundled JFK sample transcribes to "And so my fellow Americans ask not
> what your country can do for you, ask what you can do for your
> country." See AUDIO_AUDIT.md "R8B: whisper.cpp STT backend" for the
> install layout + verification details,
> +1 from
> `io/transducers/noise_xk.nova` added in R6C and upgraded in R7C to
> 2048-bit RFC 7919 Group 14 DH — pure-NOVA Noise XK
> mutual-auth handshake + ChaCha20-Poly1305 transport encryption for
> kg_sync v3, closing the federation audit's "plaintext TCP" gap. Ships
> SHA-256 (FIPS 180-4), HMAC-SHA256 + HKDF (RFC 2104 / RFC 5869),
> 2048-bit DH over RFC 7919 Group 14 via `bn2048_modpow_ct` (Montgomery
> REDC, R5A), and the Noise XK state machine
> (`-> e, es; <- e, ee; -> s, se`) on top of `chacha20.nova` +
> `poly1305.nova` + `bignum_2048.nova`. `kg_sync.nova` extended with
> `kgsync_v3_handshake_initiator/responder` + `kgsync_v3_send_line` /
> `kgsync_v3_recv_line` that wrap every line in an AEAD frame; v2
> plaintext stays the default, `CE_KGSYNC_REQUIRE_NOISE=1` opts in to
> v3-only. ~42 unit assertions + 12 integration assertions; R7C
> handshake budgeted at **~5-15 s** wall-clock (4 modpow ops at ~1-4 s
> each via Montgomery REDC); MITM with a wrong responder static key
> correctly rejected at msg1 AEAD verify (auth contract survives the
> DH widening). The R6C 256-bit field-prime DH was below the RFC 7919
> Group 1 floor and is retired in favor of this 2048-bit upgrade.
> Documented in [`FEDERATED_AUDIT.md`](./FEDERATED_AUDIT.md),
> +1 from
> `kg/episodic.nova` added in R6F -- the ADR-0022 episodic-memory
> consolidation cycle. Scans the recent moment stream for clusters of
> atoms that co-occur >=5 times within a small temporal window
> (>=3 atoms within 10 ticks @100Hz), promotes each into a compound
> "episodic atom" with Beta(alpha, beta) belief (ADR-0023) and
> provenance label, and persists the result through the v2 snapshot's
> EPISODIC section (new `episodic.atoms.*` sub-block; NO version bump,
> a snapshot from a pre-this-build writer parses cleanly). Wired into
> the memory loop (ADR-0036) as a sub-task -- ADR-0036 reserves the
> 6+1 loop slots, so consolidation rides on memory, which already owns
> moments + episodes. New API in `src/kg/episodic.nova`:
> `episodic_consolidate`, `episodic_match`,
> `episodic_match_observation`, `episodic_update_belief`,
> `episodic_observe`. New 79 unit assertions
> (`tests/unit/test_episodic.nova`) + 37 integration assertions
> (`tests/integration/scenario_ff_episodic.sh`) all PASS; all
> existing scenarios (durability A/A2/A3, snapshot DD migration,
> KG/perception Q) still green. Also +1 from
> `io/transducers/image_orb.nova` added in P3.3 cont. v3 ORB feature
> detector + Hamming-distance matcher -- the patent-free, integer-only
> SIFT alternative (Rublee 2011): FAST-9 16-pixel Bresenham-circle
> 9-of-9-contiguous corner test (t=20) + Harris-proximity ranking
> reusing `harris_apply` from R1.6 + intensity-centroid orientation
> (m_01/m_10 over a 31x31 patch, quantized to 30 buckets via a
> precomputed cos/sin milli-unit table) + 256-bit rBRIEF descriptor
> (LFSR-generated point pairs from a Galois 16-bit LFSR, polynomial
> x^16+x^14+x^13+x^11+1, seed 0x12345; each pair rotated by the
> keypoint angle before sampling) + Hamming-distance matcher with
> Lowe ratio 0.75 (popcount-of-XOR over 8 int32 chunks; byte-wise
> XOR / popcount synthesized from int_add / int_mul / % since NOVA
> exposes no native bitwise builtins). On the 40x40 four-spots
> reference fixture ORB finds 96 keypoints per image with 96
> self-matches and 96 rotation matches (rotation invariance verified
> by the unit suite); the spots-vs-vertical-edge cross fixture
> produces 0 matches (the Harris-proximity filter rejects every FAST
> candidate on a single-direction edge). New chat admin:
> `/orb_match A B`. Documented in [`IMAGE_AUDIT.md`](./IMAGE_AUDIT.md),
> unchanged from the snapshot
> v1 -> v2 migration session -- the bump landed inside the existing
> `persistence/snapshot_{writer,disk,reader}.nova` trio +
> `examples/migrate_snap.nova` (NEW) +
> `scripts/migrate_snapshot.sh` (NEW) + `SNAPSHOT_FORMAT.md` (NEW). The
> v2 format adds an OPTIONAL
> `meta.{creator,created_ns,compaction_threshold,encryption}` block; a v1
> file migrates transparently via `snap_migrate_v1_to_v2`, and v3+ files
> are rejected loudly with an upgrade-required diagnostic. +1 from
> `io/transducers/image_canny.nova` added in P3.3 cont. Canny edge
> detection -- the canonical edge detector after Sobel + Harris + SIFT.
> Pure-NOVA Gaussian 3x3 smoothing + signed Sobel gradients + non-maximum
> suppression along the gradient direction + 8-connected hysteresis
> worklist flood-fill with LOW=50 / HIGH=100 milli-normalized magnitude
> thresholds; produces single-pixel-wide edges (strict subset of Sobel's
> above-threshold set) and the `image_canny_edges_<low|mid|high>` feature
> atom on images >= 32x32. Documented in
> [`IMAGE_AUDIT.md`](./IMAGE_AUDIT.md),
> +1 from
> `safety/bignum_256.nova` added in R6B Montgomery REDC mirror for the
> 256-bit case -- a parallel `bn256_*` prefix to the existing `bn_*`
> from `bignum.nova` with CIOS-form Montgomery REDC backing
> `bn256_modpow_ct`. Observed **~14x speedup** vs the legacy
> bit-by-bit reducer (Mont ~3.1 ms vs Legacy ~45 ms) on the
> Curve25519 prime with the full 254-bit `p-1` exponent; the
> headline Fermat check `bn256_modpow_ct(2, p-1, p) == 1` passes in
> ~3.1 ms wall-clock. Same INTENTIONAL OMISSION as bignum_2048: no
> non-CT `bn256_modpow` (the existing `bn_modpow` in `bignum.nova`
> covers the offline-only case). The new prefix is ship-able alongside
> the legacy `bn_*` without touching any in-use call site;
> `bn256_curve25519_p()` exposes the Curve25519 field prime
> `p = 2^255 - 19` lazily. **R7B realized this speedup in production**
> by migrating `src/learning/secure_aggregation.nova`'s DH-256 path
> (`sa_dh_generate_keys` + `sa_dh_shared_secret_for_peer`) from
> `bn_modpow_ct` to `bn256_modpow_ct`: measured 2-soul-pair DH round
> drops from **~260 ms to ~12.9 ms** (~20x), per-modpow_ct
> ~65 ms -> ~3.2 ms; all 142 unit tests + scenario_u_secagg's 48
> assertions still pass bit-identically (wire format unchanged --
> `bn_*` and `bn256_*` share the same 8 x 32-bit limb layout and
> 64-char hex serialization). +1 from
> `safety/bignum_2048.nova` added in P3.9 cont. 2048-bit DH on RFC 7919
> Group 14 -- the cryptographically-reasonable upgrade to the 256-bit
> v2-sa-dh strawman SECAGG_AUDIT.md flagged as broken; **extended in
> R4D with Montgomery REDC (CIOS form) for ~10x speedup**. The bn2048
> module is a 64-limb (32-bit-per-limb) pure-NOVA bignum parallel to
> `bignum.nova`; only `bn2048_modpow_ct` (Montgomery ladder, now backed
> by Montgomery REDC under the hood) is exposed -- the non-CT variant
> is intentionally omitted because a 2048-bit private exponent can't
> safely tolerate any timing leak. RFC 7919 Group 14 constants land as
> `rfc7919_group14_p()` and `rfc7919_group14_g()`. Verified by the
> headline Fermat's-little-theorem check `bn2048_modpow_ct(2, p-1, p)
> == 1` (~**1.2s wall-clock**, was ~15s pre-Mont).
> `src/learning/secure_aggregation.nova` extended with
> `sa_dh_generate_keys_2048` / `sa_dh_shared_secret_for_peer_2048` +
> the `CE_SECAGG_DH_2048` env flag + a SA_DH_BITS state slot routing
> `sa_mask_for_peer` to the right shared-secret derivation. The chat
> gates on a single `CE_SECAGG_DH_2048` env probe; everything else runs
> through the existing v2-sa-dh pipeline. Cost reality (post-Mont):
> 2-soul DH-2048 round = ~**8.7s wall-clock** (was ~60s); integration
> scenario U.dh2048 completes in ~**19s** end-to-end (was ~141s),
> +1 from
> `io/transducers/audio_capture.nova` added in P2.5 cont. real microphone
> capture (parecord/arecord/sox auto-detect via `scripts/audio_capture.sh`
> + silent-WAV fallback) wired into `stream_audio.nova` via the
> `CE_AUDIO_CAPTURE_CMD=auto` sentinel,
> +1 from `io/transducers/jpeg_decode.nova` added in P3.1.JPEG minimum-viable
> JPEG modality -- structural-half pure-NOVA parser (segment markers + DQT +
> SOF0 + DHT tables); **P3.1.JPEG cont. this session: entropy decode + IDCT
> pipeline shipped** -- canonical Huffman build (T.81 Annex C) + MSB-first
> bit reader with 0xFF 0x00 byte-stuffing + DC differential / AC RLE
> decoder + dequant + un-zig-zag + separable 8x8 integer IDCT (10-bit
> fixed-point cosine table) + MCU block assembly, all wired into
> `_jpeg_decode_scan`. `jpeg_decode_grayscale(path)` now returns real
> pixel data for baseline-sequential 8-bit single-component JPEGs up to
> 512x512; pixel values match libjpeg/Pillow within +/-3. The visual
> seam (`_vp_decode_jpeg`) feeds decoded buffers through the same
> `vp_features_for_image` surface PGM/PNG use. See
> [`JPEG_AUDIT.md`](./JPEG_AUDIT.md) for the full pipeline notes;
> +1 from `safety/bignum.nova`
> added in P3.9 pure-NOVA 256-bit unsigned bignum library -- the DH
> key-exchange prerequisite the federated SecAgg MVP could not ship
> without (Item 6 of the brief), now landed as a leaf primitive
> alongside `chacha20.nova` and `poly1305.nova`; documented in
> [`SECAGG_AUDIT.md`](./SECAGG_AUDIT.md). **P3.8r extension:**
> `src/learning/secure_aggregation.nova` extended with
> dropout-resilience -- the `sa_recompute_without` /
> `sa_reconcile_for_dropped` pair, FED_DROPOUT + FED_RECON_MASKED wire
> formatters + parsers, and the `CE_FED_ROUND_DEADLINE_MS` env helper
> (default 5000 ms). The 3-soul A/B/C round where B drops mid-round
> now ends with the coordinator's sum equal to x_A + x_C exactly (no
> garbage mask residue), shipped without adding a new module --
> dropout resilience moved from "limitations" to "shipped" in
> SECAGG_AUDIT.md.
> **P3.9 extension (this session):** `bn_modpow_ct` (Montgomery ladder;
> constant-time per bit) added to `src/safety/bignum.nova` so DH/ECDH
> private exponents can be exported to remote-callable paths without
> leaking via wall-clock timing. **DH key agreement landed (v2-sa-dh):**
> `src/learning/secure_aggregation.nova` extended with
> `sa_dh_generate_keys` / `sa_dh_shared_secret_for_peer` /
> `sa_register_peer_dh` + FED_DH_PUBLIC wire format/parse/dispatch +
> the `CE_SECAGG_DH` env flag; the coordinator collects soul pubkeys
> during the handshake and broadcasts them back via the new
> `_fed_broadcast_dh_pubkeys` phase; the chat soul gates on a single
> `CE_SECAGG_DH` env probe and the rest of the path runs through the
> existing v2-sa pipeline (the DH-derived shared secret slots in where
> the pre-shared token used to). Caveats called out loudly in
> SECAGG_AUDIT.md: 256-bit DH prime + weak-random private-key generation
> + `p_25519` is a field prime not a safe DH prime -- the MVP
> demonstrates the wire protocol + flow, not the cryptographic
> strength,
> +1 from `kg/ann_index.nova`
> added in P3.4 LSH approximate-nearest-neighbor over atom embeddings,
> +1 from `realtime_pacer.nova`
> added in P0.6 wall-clock pacer, +1 from `http_client.nova` added in P1.4
> plain-HTTP in-process transport seam,
> +3 from `safety/{chacha20,poly1305}.nova` + `io/transducers/secure_channel.nova`
> added in the P1.4 PSK secure-channel continuation -- pure-NOVA
> ChaCha20-Poly1305 (RFC 7539) over TCP as a "noise envelope" alternative to
> TLS framing, documented in [`TLS_AUDIT.md`](./TLS_AUDIT.md), +4 from `seed/pack_registry.nova` +
> `seed/packs/{medical,ops_runbook,code_review}_pack.nova` added in P1.9
> domain seed packs, +2 from `reader/cofire_index.nova` +
> `reader/slot_index.nova` added in P2.1/P2.2 co-fire + syntactic-slot
> similarity side-indices, +3 from
> `io/transducers/stream_{stdin,unix_socket,http}.nova` added in P2.8
> real-time streaming event sources,
> +1 from `persistence/snapshot_compaction.nova` added in P2.10 snapshot
> compaction pass,
> +2 from `io/transducers/{stt_seam,stream_audio}.nova` added in P2.5
> STT framework + audit,
> +1 from `parts/reasoning/proof_checker.nova` added in P3.5 minimum
> viable proof checker,
> +1 from `safety/differential_privacy.nova` added in P3.6 minimum-viable
> differential privacy at the KG-query surface (integer Laplace mechanism +
> per-session epsilon-budget accountant, ADR-0053 -- documented in
> [`DP_AUDIT.md`](./DP_AUDIT.md)),
> +2 from `io/transducers/{image_pgm,visual_perception}.nova` added in P3.1
> minimum-viable image modality -- pure-NOVA PGM-P5 decoder + pluggable
> visual perception seam producing feature atoms, documented in
> [`IMAGE_AUDIT.md`](./IMAGE_AUDIT.md),
> +1 from `io/transducers/image_sift.nova` added in P3.3 cont. SIFT
> keypoint DETECTION (scale-space + DoG extrema; the P3.3 cont. v2
> follow-up landed the 128-D descriptor + Lowe-ratio-test matcher
> in the SAME module) -- 3-octave Gaussian pyramid, 5 blur levels
> per octave, 4 DoG layers, 3x3x3 spatial-and-scale extremum check,
> contrast threshold 30 milli-normalized + Harris-style edge rejection
> reusing `harris_apply` from R1.6; the descriptor pass walks a 16x16
> window around each keypoint, builds a 4x4 grid of 8-bin direction
> histograms (Gaussian-weighted by distance), normalizes to L2 =
> 1000 milli, caps at 200 milli, and re-normalizes; producing the
> `image_keypoint_count_<low|mid|high>` and
> `image_descriptors_<low|mid|high>` feature atoms on images >= 32x32
> plus the new `/match_images A B` admin command for image-to-image
> keypoint correspondence (object recognition / image stitching /
> motion tracking foundation), documented in
> [`IMAGE_AUDIT.md`](./IMAGE_AUDIT.md),
> +2 from `io/transducers/{video_y4m,video_perception}.nova` added in P3.2
> minimum-viable video modality -- pure-NOVA Y4M (raw YUV4MPEG2) decoder +
> pluggable video perception seam producing per-frame feature atoms +
> motion / scene-change labels, surfaced via the chat `/play PATH [N]`
> admin command and the `scripts/video_to_y4m.sh` ffmpeg shim for
> compressed video input, documented in [`VIDEO_AUDIT.md`](./VIDEO_AUDIT.md),
> +1 from `learning/federated_aggregator.nova` added in P3.7
> minimum-viable federated multi-soul learning -- per-soul DP-noised
> per-source promotion/atrophy rates + coordinator-side aggregation +
> EMA pull toward the federation mean, surfaced via the chat
> `/fed_join` / `/fed_stats` / `/fed_leave` admin commands and the
> `bin/crossengin-fed-coordinator` daemon, documented in
> [`FEDERATED_AUDIT.md`](./FEDERATED_AUDIT.md)), 141 unit-test suites pass
> (`make test`,
> +1 suite / +34 assertions from `test_orb.nova` added in P3.3 cont. v3
> ORB feature detector + Hamming-distance matcher: FAST-9 4-corner
> detection on a 40x40 four-spots fixture surfaces 96 keypoints; orb
> self-match yields 96 matches at Hamming distance 0; identical
> descriptors -> 0; fully flipped 8-chunk descriptors (256-bit XOR =
> all ones) -> Hamming 256; single-bit difference -> 1; cross-fixture
> spots-vs-vertical-edge -> 0 matches (Harris filter rejects every FAST
> candidate on a straight edge); 90-degree rotated four-spots -> at
> least 1 match survives at ratio 900 milli (rotation invariance via
> the intensity-centroid orientation + cos/sin rotation table); too-
> small (16x16), too-large (300x300), null data_ptr, zero-width all
> return 0 keypoints; matcher edge cases (empty inputs, < 2 candidates
> in B, size-mismatch descriptors) all return empty / -1; count-bucket
> labels + density labels round-trip; orb_kp_x/y/angle/score
> accessors return values in expected ranges. Documented in
> [`IMAGE_AUDIT.md`](./IMAGE_AUDIT.md),
> +1 suite / +22 assertions from `test_image_canny.nova` added in
> P3.3 cont. Canny edge detection: uniform 32x32 -> 0 edges; vertical
> step -> 30 edges (single-column NMS-thinned from Sobel's 60); diagonal
> step -> edges along |x-y| <= 2; hysteresis bridge fixture -> chain of
> weak pixels kept; **Canny edges are a STRICT SUBSET of Sobel edges**
> (every kept Canny pixel lands on a non-zero Sobel magnitude;
> canny_n <= sobel_count); density-milli math + density-label
> round-trip; dimension cap (>512) rejects without crashing; too-small
> (2x2) images return empty edge list; result-tuple accessors work,
> documented in [`IMAGE_AUDIT.md`](./IMAGE_AUDIT.md),
> +1 suite / +87 assertions from `test_jpeg_decode.nova` covering
> P3.1.JPEG structural parser + P3.1.JPEG cont. entropy decode + IDCT
> pipeline: in-memory baseline-grayscale fixture builder; segment
> iteration walks SOI/APP0/DQT/SOF0/DHT/SOS/EOI; DQT/SOF0/DHT parsing;
> canonical Huffman table build + bit reader; 8x8 IDCT (all-zero block
> -> 128 everywhere, DC-only block -> uniform value); dequant + un-zig-zag
> round-trip; end-to-end `jpeg_decode_grayscale_bytes` on a synthetic
> 16x16 stream; real-Pillow first-pixel match within +/-3 of libjpeg;
> rejects oversized dims (> 512 decode cap, > 1024 structural), SOF2
> (progressive), and bad SOI; documented in
> [`JPEG_AUDIT.md`](./JPEG_AUDIT.md),
> +1 suite / +46 assertions from `test_deflate.nova` added in
> P3.1.PNG full DEFLATE inflate -- extends the Item-3 stored-only
> path (BTYPE=00) with RFC 1951 BTYPE=01 static Huffman + BTYPE=02
> dynamic Huffman so the pure-NOVA PNG decoder ingests any standard
> grayscale-8 PNG from a camera, phone, screenshot tool, or web
> download (zlib level 0..9 all decode). Test coverage: stored-
> block regression; static "hello" round-trip; static empty block;
> 8 'a' overlapping copy (length > distance); 12 'A' + 'B' and
> 12 'X' length-extra-bits; HELLO + 270 X + HELLO + 5 Y multi-byte
> distance (> 256); a 22,500-byte dynamic-Huffman pangram round-
> trip; BTYPE=11 reserved rejection. Documented in
> [`IMAGE_AUDIT.md`](./IMAGE_AUDIT.md),
> +1 suite / +25 assertions from `test_image_sift.nova`
> added in P3.3 cont. SIFT keypoint DETECTION: uniform-grey 32x32 -> 0
> keypoints; single bright 5x5 spot at (13,13) in 32x32 -> 1 keypoint at
> (15,15) with contrast 55; 32x32 four-spots fixture -> 4 keypoints
> (one per spot) at the spot centers; dimension caps reject < 32x32 and
> > 256x256; per-keypoint accessors round-trip; max_keypoints cap
> honored, documented in [`IMAGE_AUDIT.md`](./IMAGE_AUDIT.md),
> +1 suite / +28 assertions from `test_sift_descriptor.nova` added
> in P3.3 cont. v2 SIFT 128-D descriptor + matcher (the previously-
> deferred descriptor + matching half of Lowe 2004): descriptor L2
> norm ~= 1000 milli on a bright-spot keypoint, component cap honored,
> distance to self == 0, structurally-different fixtures > 200 milli
> apart, rotated copy stays structurally similar (< 2263 milli max
> theoretical), Lowe-ratio-test pass on a clear best match + reject on
> an ambiguous pair + reject with < 2 candidates, keypoint-list matcher
> self-pairing, empty-input / size-mismatch / null-data / tiny-image /
> uniform-image rejection, edge-keypoint window shift, sift_describe_all
> parallel-list shape, known-diff descriptor distance == 1000,
> documented in [`IMAGE_AUDIT.md`](./IMAGE_AUDIT.md),
> +1 suite / +66 assertions from `test_bignum.nova` added in
> P3.9 pure-NOVA 256-bit bignum library: `bn_new` / `bn_from_int` /
> `bn_from_hex` / `bn_to_hex` / `bn_zero` / `bn_eq` / `bn_cmp` / `bn_add`
> / `bn_sub` / `bn_mul` (full 512-bit product as `[hi, lo]`) / `bn_mod`
> / `bn_modmul` / `bn_modpow`, with the textbook `2^10 mod 1000 = 24`
> and the Curve25519 prime sanity check `2^255 mod (2^255-19) = 19`
> verified end-to-end. The const-time follow-up `bn_modpow_ct`
> (Montgomery ladder; +12 of the 66 assertions: equivalence with
> `bn_modpow` on a 100-vector deterministic sweep + textbook +
> Curve25519 + timing-comparison report) closes the side-channel
> leak on the exponent's Hamming weight so DH/ECDH private-key
> exponents can be exported to remote-callable paths without leaking
> via wall-clock timing. `bn_modpow` is now documented loudly as
> "fast, side-channel-unsafe; offline self-tests only";
> `bn_modpow_ct` is the crypto-safe variant consumers must use for
> any private exponent. Documented in
> [`SECAGG_AUDIT.md`](./SECAGG_AUDIT.md) ("bignum landed; DH key
> exchange unblocked + shipped as v2-sa-dh"),
> (and `test_bignum_2048.nova` from P3.9 cont. extended in R4D
> for Montgomery REDC: now **65 assertions** total, +7 new for the
> mont-ctx round-trip, mont == legacy equivalence on small N=1009,
> and the speedup-ratio measurement on RFC 7919 Group 14. The
> headline check Fermat's little theorem on the safe prime
> `bn2048_modpow_ct(2, p-1, p) == 1` -- now ~1.2s wall-clock under
> Montgomery REDC, was ~15-18s pre-Mont; **~10x speedup** measured
> end-to-end. The 2-soul DH-2048 pair-equivalence test in
> `test_secure_aggregation.nova` drops from ~60-140s to ~8.7s.
> Documented in [`SECAGG_AUDIT.md`](./SECAGG_AUDIT.md)
> ("Montgomery REDC landed; timing reduced from ~18s to ~1.2s
> per modpow_ct")),
> +1 suite / +70 assertions from `test_bignum_256.nova` added in R6B
> Montgomery REDC mirror for the 256-bit case: full coverage of the
> new `bn256_*` API (`bn256_new` / `bn256_from_int` / `bn256_from_hex` /
> `bn256_to_hex` / `bn256_eq` / `bn256_cmp` / `bn256_add` / `bn256_sub` /
> `bn256_mul` / `bn256_mod` / `bn256_modmul` / `bn256_modpow_ct` plus
> the Montgomery primitives `bn256_mont_ctx_new` / `bn256_to_mont` /
> `bn256_from_mont` / `bn256_montmul` / `bn256_modpow_ct_mont` and the
> legacy equivalence anchor `_bn256_modpow_ct_legacy`); the headline
> Fermat check `bn256_modpow_ct(2, p-1, p) == 1` on the Curve25519
> prime; mont == legacy equivalence on 2 pseudo-random vectors at
> small N=1009 PLUS one cross-check on the Curve25519 prime with an
> arbitrary 64-bit exponent; speedup-ratio measurement on the
> Curve25519 prime with the full 254-bit `p-1` exponent reporting
> **~14x speedup** (Mont ~3.1 ms vs Legacy ~45 ms),
> +1 suite / +27 assertions from `test_realtime_pacer.nova`
> added in P0.6 real-time wall-clock pacer,
> +1 suite / +37 assertions from `test_decision_log_durable.nova` added in
> P0.7 decision-log durable path,
> +3 suites / +132 assertions from `test_snapshot_{episodic,synapses,
> selfmodel}.nova` added in P0.1 full-state persistence,
> +2 suites / +82 assertions from `test_meta_observer_feedback.nova` +
> `test_atom_death_attribution.nova` added in P1.1 meta-observer feedback
> into source_authority + P1.6 atom-death attribution,
> +18 assertions to `test_learn_tag.nova` (22 -> 40) from P1.5 composite
> `/learn` kinds: batch `@/path/urls.txt`, RSS `rss:URL`, recursive
> `dir:/path` directory walk,
> +1 suite / +59 assertions from `test_http_client.nova` added in P1.4
> plain-HTTP client + dispatcher,
> +3 suites / +51 assertions from `test_chacha20.nova` (26),
> `test_poly1305.nova` (9), `test_secure_channel.nova` (16) added in the
> P1.4 PSK secure-channel continuation -- RFC 7539 ChaCha20 + Poly1305
> primitives plus the per-frame PSK envelope, documented in
> [`TLS_AUDIT.md`](./TLS_AUDIT.md),
> +33 assertions added to `test_secure_aggregation.nova` (93 -> 126; further
> extended to 157 in P3.9 DH key agreement below: 2-soul DH-derived
> pair-mask match, full 2-soul DH sum demo, FED_DH_PUBLIC wire
> formatter + parser + dispatch, default-off `CE_SECAGG_DH` env probe,
> `sa_register_peer_dh` idempotency, `sa_dh_generate_keys` validity --
> all of which exercise `bn_modpow_ct` on 256-bit private exponents
> via DH commutativity)
> in P3.8r dropout-resilience: 3-soul A/B/C round where B drops mid-
> round; A + C reconcile by removing m_AB and m_BC mask contributions;
> coordinator's sum equals x_A + x_C exactly (200, the brief's
> expected). Plus signed-mask `sa_recompute_without` determinism +
> sign-mirror invariants across paired souls; FED_DROPOUT +
> FED_RECON_MASKED wire formatter / parser shapes (including signed-
> integer adjusted values for the residual-flips-sign case); top-
> level dispatch through `sa_parse_line` for the two new events;
> default `CE_FED_ROUND_DEADLINE_MS=5000` env helper,
> +4 suites / +73 assertions from `test_pack_registry.nova` +
> `test_medical_pack.nova` + `test_ops_pack.nova` +
> `test_code_review_pack.nova` added in P1.9 domain seed packs,
> +2 suites / +58 assertions from `test_cofire_index.nova` +
> `test_slot_index.nova` added in P2.1/P2.2 co-fire + syntactic-slot
> similarity side-indices, plus +15 assertions to
> `test_neighborhood_activation.nova` (30 -> 45) covering
> `find_neighbors_full` with the two new index sources,
> +1 suite / +28 assertions from `test_stream_stdin.nova` added in P2.8
> real-time streaming event sources,
> +1 suite / +48 assertions from `test_snapshot_compaction.nova` added in
> P2.10 snapshot compaction pass,
> +1 suite / +46 assertions from `test_ann_index.nova` added in P3.4
> LSH approximate-nearest-neighbor over atom embeddings (40x speedup
> over linear cosine scan at 1000 atoms, K=8 hyperplanes / 256 buckets;
> see `tests/benchmark/bench_ann_query.nova`),
> +1 suite / +26 assertions from `test_stt_seam.nova` added in P2.5
> STT framework + audit -- the speech-to-text half of the audio
> modality bridge, pluggable behind `EV_MESSAGE` -- documented in
> [`STT_AUDIT.md`](./STT_AUDIT.md), with `scripts/transcribe.sh` as the
> auto-detecting subprocess shim and `src/io/transducers/stream_audio.nova`
> as the env-gated audio-capture source,
> +1 suite / +28 assertions from `test_audio_capture.nova` added in
> P2.5 cont. real microphone capture: state-struct defaults +
> hand-built canonical WAV round-trips (mono passthrough with KNOWN
> samples [100, 0, -200, 32000, -32000] at 16 kHz; 8 kHz / 44.1 kHz /
> 48 kHz sample-rate variants) + malformed-WAV rejection (bad RIFF
> magic / bad WAVE magic / non-PCM format / non-16-bit width /
> truncated header / missing file) + stereo-to-mono averaging,
> +1 suite / +55 assertions from `test_audio_vad.nova` added in R7F
> Voice Activity Detection: energy (sum of absolutes) + ZCR (sign
> flips) per 30 ms frame; 4-state hysteresis machine (SILENCE →
> SPEECH_CANDIDATE → SPEECH → SILENCE_CANDIDATE → SILENCE) with K=3
> speech-on / M=10 speech-off commit thresholds; thresholds scale
> linearly with frame_size so the same module works at 8/16/22.05/
> 44.1/48 kHz. Rejects pure-noise inputs via the ZCR ceiling
> (alternating ±3000 = max ZCR = silence verdict). R9B extended with
> +31 assertions for adaptive noise-floor calibration (MIN over
> leading 480 ms × 3 multiplier, R7F floor preserved bit-identical);
> total now 86 checks,
> +1 suite / +28 assertions from `test_whisper_backend.nova` added in
> R8B -- whisper.cpp STT backend wired into the seam: env-resolver
> fallback (default canonical install paths when CE_WHISPER_BIN /
> CE_WHISPER_MODEL are unset), openable-ness probe (uses sys_open as
> the access-proxy), three pre-flight error paths ("binary not
> found", "model not found", "wav not found"), transcript cleanup
> (trim whitespace + collapse internal newlines to single spaces +
> dedup runs of spaces, handles empty + all-whitespace input),
> result-tuple accessors, and a stt_seam round-trip through
> STT_BACKEND_WHISPER dispatch (verified via the seam's last_error
> surfacing the precise install gap),
> +1 suite / +56 assertions from `test_proof_checker.nova` added in P3.5
> minimum-viable proof checker -- bounded BFS over the operator graph
> returning audit-grade derivation traces with composed Bayesian
> confidence, surfaced via the chat `/prove PREMISE CONCLUSION [DEPTH]`
> admin command,
> +1 suite / +52 assertions from `test_differential_privacy.nova` added in
> P3.6 minimum-viable differential privacy at the KG-query surface --
> integer Laplace mechanism (Geometric-on-Z), per-session epsilon-budget
> accountant, `kg_atom_count_dp` / `kg_atom_belief_mean_dp` opt-in
> wrappers, surfaced via the chat `/dp_status` + `/dp_query atoms` admin
> commands, documented in [`DP_AUDIT.md`](./DP_AUDIT.md),
> +1 suite / +43 assertions from `test_image_pgm.nova` added in P3.1
> minimum-viable image modality -- pure-NOVA PGM-P5 binary decoder
> (header + raw bytes, no compression) with histogram / mean-intensity
> / nearest-neighbor resize / dominant-intensity bucket statistics
> and the pluggable `visual_perception.nova` seam producing crude
> feature atoms (image_dim_*, image_dark/mid/bright, image_bucket_*,
> image_hist_peaked/uniform); surfaced via the chat `/see PATH` admin
> command and the `scripts/image_to_pgm.sh` ImageMagick/ffmpeg shim
> for non-PGM input, documented in [`IMAGE_AUDIT.md`](./IMAGE_AUDIT.md),
> +1 suite / +34 assertions from `test_video_y4m.nova` added in P3.2
> minimum-viable video modality -- pure-NOVA Y4M raw-video decoder
> (ASCII header + per-frame iterator over the YCbCr planes, no
> compression) with mean-absolute-difference motion proxy across
> the luma plane, and the pluggable `video_perception.nova` seam
> producing per-frame feature atoms + motion_<low|mid|high> +
> scene_change labels; surfaced via the chat `/play PATH [N]` admin
> command and the `scripts/video_to_y4m.sh` ffmpeg shim for
> compressed video input, documented in [`VIDEO_AUDIT.md`](./VIDEO_AUDIT.md)),
> 27 end-to-end integration
> scripts run (`make integration`, +1 from `scenario_a3_dlog.sh` added in
> P0.7 dlog durability across SIGKILL, +1 from `scenario_a2_full_state.sh`
> added in P0.1 full-state persistence across SIGKILL, +2 from
> `scenario_h_session_switch.sh` + `scenario_i_web_isolation.sh` added in
> P0.8 chat /switch + web.py per-cookie routing,
> +1 from `scenario_j_http_client.sh` added in P1.4 plain-HTTP loopback
> against `python3 -m http.server`,
> +1 from `scenario_v_secure_channel.sh` added in the P1.4 PSK
> secure-channel continuation -- NOVA client opens a ChaCha20-Poly1305
> envelope over TCP against a Python counterpart
> (`scripts/secure_channel_echo.py`), sends "ping", asserts the decrypted
> reply equals "pong",
> +9 dropout-resilience assertions extending
> `scenario_u_secagg.sh` (P3.8r): scenario U.r spawns a 2-soul SecAgg
> round where a Python `scripts/secagg_smoke_soul.py` helper acts as
> the dropout peer (handshake then close); the surviving soul-helper
> emits FED_RECON_MASKED with the dropped peer's mask removed; the
> coordinator logs DROPOUT soul=bob, broadcasts FED_DROPOUT,
> collects the reconciled stat, and the final FED_AGGREGATE_SUM
> line carries the survivor's raw values exactly (sum_promo=100,
> sum_atr=50, n_part=1),
> +1 from `scenario_k_seed_pack.sh` added in P1.9 `/seed` domain pack
> install + listing,
> +1 from `scenario_m_metrics_endpoint.sh` added in P2.9 Prometheus
> text-format `/metrics` scrape endpoint over `scripts/web.py`,
> +1 from `scenario_l_stream_stdin.sh` added in P2.8 stdin streaming
> source acceptance test,
> +1 from `scenario_w_audio_capture.sh` added in P2.5 cont. microphone-
> capture end-to-end: `scripts/audio_capture.sh /tmp/...wav 1` produces
> a valid PCM-16 mono 16 kHz WAV (silent-fallback in the sandbox, real
> audio on hardware -- header magic-bytes + numeric-fields all verified
> via a one-shot Python parser); a tiny on-the-fly NOVA driver then runs
> `stream_audio_init_from_env` with `CE_AUDIO_CAPTURE_CMD=auto`, confirms
> the auto sentinel resolves to `use_auto=1`, `stream_audio_poll` invokes
> `audio_capture_record` end-to-end, the produced WAV is parsed by
> `audio_capture_to_pcm` (sample_rate=16000, samples non-empty), and the
> `EV_MESSAGE` post-path round-trips through the scheduler queue via
> `hs_post_event`,
> +1 from `scenario_ii_vad.sh` added in R7F VAD end-to-end: Klatt-
> synthesizes a 4-diphthong utterance ("AY EY OW OY") padded with
> leading/trailing silence, writes the WAV via `audio_write_wav`,
> reads back via `audio_capture_to_pcm_vad`, asserts >=1 speech segment
> + non-empty filtered PCM (4800 samples = the speech burst with K=3
> back-dating). Pure-silence WAV -> 0 segments + empty filtered PCM;
> pure-noise WAV (alternating ±3000 = max ZCR) -> 0 segments (ZCR
> ceiling rejects high-energy noise). Chat `/help` advertises
> `/listen`; `/listen <wav>` reports `vad_segments=N` and the active
> STT backend,
> +1 from `scenario_jj_whisper.sh` added in R8B whisper.cpp STT
> backend end-to-end: Klatt-synthesizes a 4-phoneme utterance,
> writes the WAV, calls `whisper_transcribe(bin, model, wav)`
> directly; asserts the pipeline runs without crash; then runs
> the bundled `jfk.wav` (16 kHz mono PCM16) through the same
> path and asserts the transcript contains "Americans" -- proving
> the whisper.cpp tiny.en model actually decoded English on top
> of NOVA's fork+exec/pipe2/dup2/read drain pipeline. Also
> exercises `stt_seam_new_whisper(model_path)` + the
> STT_BACKEND_STUB fallback (no whisper invocation on the stub
> path) + the seam's `last_error` surfacing precise install gaps.
> SKIPs gracefully if whisper-main / ggml-tiny.en.bin are not
> installed (10 of 13 assertions still run; the model-decode
> assertions are the optional 3),
> +1 from `scenario_oo_vad_natural.sh` added in R9B adaptive VAD +
> JFK end-to-end: synthetic silence -> 0 segments (R7F floor
> preserved when leading audio is exact-zero), synthetic noisy
> + speech -> 1 segment (adaptive threshold lifts above amp=200
> triangle lead-in noise without losing the amp=3000 speech burst),
> JFK 16 kHz WAV decoded by parser past the LIST/INFO sub-chunk
> -> 1 VAD segment + filtered PCM 170880 samples (~10.7 s of the
> 11 s clip), end-to-end `/listen JFK` reports `vad_segments=1`
> + transcript contains "fellow Americans" or "your country" +
> `backend=whisper`. SKIPs cleanly if the JFK WAV or whisper-main
> are not installed,
> +1 from `scenario_n_compaction.sh` added in P2.10 snapshot compaction
> pass: /save -> /teach 50 -> /compact -> /save shrinks file growth by
> >50% vs the baseline /save -> /teach 50 -> /save,
> +1 from `scenario_o_proof_checker.sh` added in P3.5 minimum-viable
> proof checker: /seed medical -> /prove headache hydration prints the
> headache -> dehydration -> hydration operator chain with composed
> confidence and visit/depth counters,
> +1 from `scenario_p_dp_budget.sh` added in P3.6 differential privacy
> at the KG-query surface: /dp_status initial budget -> 130 /dp_query
> atoms drains the 10000 milli-eps budget to zero (with true vs noisy
> count per call, noise variance > 0 across draws) -> /dp_query past
> exhaustion returns "budget exhausted",
> +1 from `scenario_q_image_see.sh` added in P3.1 minimum-viable
> image modality: hand-rolled 4x4 gradient + uniform-grey PGM
> fixtures, /see prints the operator-readable summary
> (dims + mean + dominant bucket + entropy) and the feature-atom
> labels (image_dim_small + image_mid + image_bucket_0 on the
> gradient; image_bright + image_hist_peaked + image_bucket_6 on the
> uniform fixture); malformed input is rejected with the parser's
> bracketed error and the chat survives to /quit cleanly, extended in
> P3.3 cont. (SIFT keypoint DETECTION) with +2 assertions covering a
> hand-rolled 32x32 four-spots PGM fixture: the summary line carries
> "32x32"; the feature line surfaces `image_keypoint_count_low` (4
> keypoints, below the low/mid threshold of 10),
> +1 from `scenario_s_video_play.sh` added in P3.2 minimum-viable
> video modality: a hand-rolled 5-frame 4x4 Y4M fixture with two
> forced scene changes, /play prints per-frame event lines (image
> features + motion + scene_change labels) and the operator-readable
> summary (`played PATH: N frame(s), <w>x<h>, motion=<...>, scene
> changes: 2, decoder=y4m`); /help advertises /play; malformed
> input is rejected with the parser's bracketed error and the chat
> survives to /quit cleanly,
> +1 from `scenario_r_federated.sh` added in P3.7 minimum-viable
> federated multi-soul: a coordinator daemon accepts a chat's
> FED_JOIN, opens round 1, collects the soul's noised FED_STAT batch,
> broadcasts FED_AGGREGATE, and the chat receives + EMA-blends the
> federation-wide rate back into local source_authority -- the
> framework piece of P3.7 with `FEDERATED_AUDIT.md` walking the
> trust model, composition, sybil, and convergence trade-offs,
> +1 from `scenario_aa_atom_search.sh` added in P-AA web atom-search:
> `python3 scripts/web.py` -> `GET /api/atoms?q=fever&limit=5` returns
> `{"atoms": [...]}` listing the fever concept atom and its three
> operator atoms; `GET /atoms` serves a tiny vanilla-JS HTML page
> (search box + KG filter + table); second `/api/atoms` call within
> the cache window confirms the `CE_ATOMS_CACHE_S` (default 30s)
> probe cache; 14 assertions,
> +1 from `scenario_bb_why_deep.sh` added in P-BB `/why-deep [N]`:
> `/teach widget` -> ask -> `/why-deep 3` prints a decision header,
> a `proof:` line (operator chain via P3.5 `proof_checker.nova`), an
> `activated by:` line surfacing the raw input, and an `upstream
> evidence:` section listing per-atom belief mean + source provenance
> (`user_taught` for `/teach` atoms, `seed` for first_atoms); 13
> assertions),
> three benchmarks report metrics
> (`make benchmark`), and six runnable artifacts build and run
> (`make install`): the substrate kernel self-check, the safety+IO+persistence
> companion spine, **`bin/crossengin` — the whole agent in one process**
> (substrate + knowledge + soul + goals + scheduler + IO + safety + persistence,
> no LLM), the distributed-substrate seam's two halves
> (`bin/crossengin-kg-publisher` / `bin/crossengin-kg-subscriber`), and the
> federated-coordinator (`bin/crossengin-fed-coordinator`, P3.7). The unified assembly was previously blocked by NOVA's import-path
> dedup (blocker #10); that is now **fixed in the toolchain** (path
> canonicalization — see [`NEXT_SESSION.md`](./NEXT_SESSION.md)). What remains is
> production hardening of the documented runtime seams (fsync-durable
> persistence, TLS fetch, STT/TTS bridge, a sub-second wall-clock pacer, SIMD) so
> the daemon can run continuously across real restarts. NEXT_SESSION.md records
> exactly what works, what does not, and where to continue.

## What works now (v1.0)

The Phase 1 substrate kernel (`src/substrate/`):

- **node_pool_manager** — the uniform leaky-integrate-and-fire node kernel over
  a pre-allocated pool, with novelty tracking and the integer milli-fixed-point
  convention (ADR-0006).
- **signal_dispatch** — the 18 `XSIG_*` signal types with ADR-0008 priorities
  and a priority-bucketed FIFO dispatch queue.
- **synapse_graph** — sparse weighted synapses with Hebbian + error-driven
  plasticity, eligibility decay, growth, and idle prune/reclaim (ADR-0007).
- **first_nodes** — stable per-part input blocks and modality presets (ADR-0010).
- **part_registry / part_lifecycle** — the seven fixed parts plus dynamic,
  per-domain KG parts (ADR-0001).
- **gate_router** — learned content-based routing with the privileged,
  non-learnable constitutional broadcast (ADR-0009, ADR-0045).
- **resonance_engine** — bidirectional co-activation reinforcement into stable
  assemblies.
- **tick_driver** — the four-phase substrate tick: snapshot → integrate →
  propagate → learn (ADR-0006, ADR-0001).

The Phase 3 knowledge layer (`src/kg/`):

- **atom_store** — the persistent knowledge atom with immutable (kg_id, id)
  identity, versioned mutation, and a Bayesian alpha/beta belief; also the
  shared milli belief + integer-cosine vector helpers (ADR-0016, ADR-0023).
- **multi_kg_manager** — per-domain knowledge graphs with embedding centroids
  (ADR-0004).
- **cross_kg_references** — automatic + earned cross-KG links and the
  spawn-on-new-domain heuristic (ADR-0017).
- **schemas** — entity-type validation with required/optional fields and
  min/max constraints (ADR-0018).
- **concept_layer** — the concept DAG with promotion, schema slots, facet
  vectors, members, and kg_span (ADR-0018).
- **skills_kg** — procedural skills (ATOM_SKILL) with Bayesian reliability,
  step rules, activation, and retirement (ADR-0019).
- **competence_tracker** — the self-model: per-domain competence (know/do/
  understand) computed from belief/skill/concept state, with four tiers
  (ADR-0020).

The Phase 2 language layer (`src/language/`) and reader (`src/reader/`):

- **word_atoms / phoneme_atoms / syntax_atoms** — words (with lexical vectors
  and weighted concept senses), phonemes, and ordered syntax patterns as
  ATOM_LANG atoms in a language KG (ADR-0015).
- **reader** (five stages, ADR-0011/0012, no LLM per ADR-0014):
  - **lexical_anchor** — tokenize and match to word atoms; SENSORY on a hit,
    CURIOSITY on an out-of-vocabulary token.
  - **context_bias** — resolve polysemy by similarity to the active context.
  - **spreading_activation** — spread over cross-KG edges and settle on an
    active concept set.
  - **coherence_check** — accept a mutually-referencing reading or escalate.
  - **fetch_route_learn** — route a comprehended percept and strengthen
    anchors, or trigger ask-user / fetch learning.

The Phase 4 memory and learning fabric (`src/parts/episodic/`, `src/learning/`):

- **moment_stream** — timestamped, append-only moment records with a
  PERCEIVED→SETTLED→CONSOLIDATED lifecycle (ADR-0021).
- **episode_storage** — episodes over moments with decay, recall reinforcement,
  tiering, and drop (ADR-0022).
- **consolidation** — recurring co-activation signatures become atom-birth
  candidates (ADR-0022).
- **bayesian_updates** — tracked beliefs with decay, tiered evidence, conflict,
  and a CONTESTED flag (ADR-0023).
- **predictive_coding_runtime** — precision-weighted prediction error with
  suppression/surprise thresholds and the upward error signal (ADR-0024).
- **atom_birth_monitor / atom_death_monitor** — novelty/frequency/stability
  gated atom birth, and decay/belief gated death with tombstoning (ADR-0025).
- **plasticity_modulation** — the learning-rate modulator from emotional
  arousal/valence/reward (ADR-0035/0007).

The Phase 5 self-directed learning layer (`src/learning/`):

- **self_learning_triggers** — gap detection (prediction error, curiosity,
  imagination gap, unknown query, user request), priority scoring, and an
  arbitration queue with user pre-emption (ADR-0026).
- **confidence_thresholds** — the low/high-stakes "learned enough" gates and
  hard caps that close a learning episode (ADR-0030).
- **ask_user_to_teach** — gap→question with an ask budget; ingests the reply as
  Beta(4,1) user-taught Tier-A evidence (ADR-0027).
- **source_whitelist / source_authority** — the allowed-domain gate, source
  tiers (A/B/C) with evidence weights, recency-policy conflict resolution, and
  user-taught precedence (ADR-0028/0029).
- **internet_fetch** — whitelist + rate-limit + cache + validation + tiered
  ingestion (ADR-0028); the TLS transport itself is a deferred seam (NOVA
  enhancement #11).

The Phase 6 cognitive subsystems (`src/parts/`):

- **goals** (`goals/`) — priority-sorted goal trees with rollup, block
  propagation, leaf arbitration, and staleness decay; the four intrinsic drives;
  and serialization with load-time validation (ADR-0033).
- **soul** (`soul/`) — the behavioral identity: slow identity (gated, audited
  revision) + OCEAN, fast state, medium goal summary, and the cross-cutting
  values, constitution (privileged XSIG_CONST veto), themes, and loyalty
  hierarchy (ADR-0034).
- **emotion** (`emotion/`) — OCC appraisal → valence/arousal/emotion-type, OCEAN
  conditioning, and emotion-modulated plasticity + episodic encoding (ADR-0035).
- **reasoning** (`reasoning/`) — operator atoms (causal/implicative/analogical/
  evidential) and five thin strategies: forward chaining, abduction, analogical
  transfer, evidential combination, and means-ends decomposition (ADR-0031).
- **imagination** (`imagination/`) — learned pattern atoms and four modes:
  forward simulation, counterfactual, dream recombination, and scenario planning
  (ADR-0032).

The Phase 7 agent architecture (`src/scheduler/`, `src/agent/`, `src/parts/meta/`):

- **scheduler** (`scheduler/`) — the hybrid 100Hz tick (`tick_loop` over the
  substrate) + event-driven coordination (`event_dispatch`), fused with idle
  detection in `hybrid_scheduler` (ADR-0037).
- **agent loops** (`agent/`) — the six cognitive loops (perception, memory,
  reasoning, emotion, goals, action) + the idle-gated imagination loop, over a
  shared `loop_coordination` blackboard (ADR-0036).
- **meta** (`parts/meta/`) — the self-model query API ("what/state/goals/
  competence", ADR-0038), theory-of-mind user model (ADR-0039),
  long-horizon goal accrual + revisit scan (ADR-0040), and the
  meta-learning observer (ADR-0050) that watches per-source promotion /
  atrophy and (P1.1) FEEDS those rates back into `source_authority` by
  promoting / demoting host tiers when sustained signal crosses thresholds
  -- 70% promotion over a 10-atom window promotes one tier; 50% atrophy
  demotes; the chat surfaces both via `/meta-feedback` (dry-run) and
  `/meta-apply` (commit). Atom death attribution (P1.6) is wired so a
  durable atom dying outright bumps the observer's atrophy counter
  immediately rather than waiting for the next poll.

The Phase 8 safety and audit stack (`src/safety/`, `src/audit/`):

- **reversibility_classifier** — classifies each action class as reversible /
  recoverable / irreversible, defaulting any unlisted action to irreversible
  (fail-safe); also home to the shared `ACT_*` action-class constants (ADR-0042).
- **permission_tiers** — the AUTO / NOTIFY / APPROVE tiers as the MAX of a
  static per-class default and the reversibility floor, so irreversible actions
  are always ≥ APPROVE; unknown classes default to APPROVE (ADR-0041).
- **decision_log** — the append-only, hash-chained decision record: every entry
  links to its predecessor so mutation, reorder, and tail-truncation all fail
  `dl_verify` (ADR-0043).
- **audit_writer / audit_reader** — the write path (intent entry before the
  effector, outcome after; corrections and overrides appended) and the
  inspection path (chain verification + plain-language "why did you do X?"
  rendered purely from stored state, no LLM) (ADR-0043, ADR-0038).
- **override_mechanism** — the four graded user interventions: belief edit
  (privileged α/β write + pin), goal veto (subtree prune + standing regen-block),
  hard stop (drain actions, substrate alive), and kill switch (clean snapshots,
  panic skips); all but panic-kill are logged (ADR-0044).
- **constitutional_filter** — the safety gate: constitutional veto (terminal,
  unclearable by user approval) → hard stop → permission tier, plus the soul
  loyalty resolution (constitution > enterprise > user > system) (ADR-0045).

The Phase 9 IO and effectors layer (`src/io/`):

- **output_generation** (`io/effectors/`) — pure-substrate language production
  (ADR-0013), the reverse of the reader: a communicative intent (role→concept
  assignments) resolves to real word atoms, a learned syntax-pattern atom orders
  them, and the text is emitted; well-formed patterns win, ill-formed are pruned,
  and accepted phrasings strengthen via plasticity. NO LLM (ADR-0014).
- **effector_gate** (`io/effectors/`) — the action chokepoint: every outward
  action runs the Phase 8 `safety_gate` (constitutional veto → hard stop →
  permission tier), logs an intent entry **before** the effector and an outcome
  **after** (ADR-0043). The text/SPEAK effector is fully implemented; governed
  speak vetoes a constitutionally-forbidden utterance by its text and never
  emits it.
- **input_transducer** (`io/transducers/`) — modality → reader-ready normalized
  percept (ADR-0011/0012, ADR-0021); strictly outside cognition (ADR-0014).
  Text/file are normalized now; audio (STT) is the honest deferred bridge seam.
- **audio_synth / audio_speak** (`io/effectors/`) — the audio modality bridge
  (Phase 19 Tier-4 #1; P2.6 multi-formant upgrade; P6 full-ARPAbet expansion).
  `audio_synth.nova` is the always-on Mode-1 floor: a pure-NOVA Klatt-style
  two-formant phoneme synthesizer covering the full English ARPAbet inventory
  (~44 distinct phonemes, 53 dispatches counting aliases like a/aa/ah): 20
  monophthongs with F1+F2+F3 (a/aa/ah, ae, e/eh, er, i/iy, ih, ix, ax, axr,
  o/oh/ao, ow, u/uw, uh), 4 diphthongs with linear formant glides (aw, ay,
  ey, oy), 6 plosives as silence+burst (b/d/g/k/p/t), 2 affricates as
  sequenced stop+fricative (ch=t+sh, jh=d+zh), 10 fricatives via a
  small-multiplier LCG pseudo-noise (s, z, f, v, sh, zh, th, dh, h/hh), 3
  onset nasals with damping (n, m, ng), 4 syllabic nasals/liquids with
  reduced amplitude (em, en, eng, el), and 4 liquids/glides (l, r, w, y), +
  a 440 Hz unknown fallback. 5 ms attack + 10 ms release anti-click ADSR per
  phoneme, and a 44-byte RIFF/WAVE/PCM writer (8 kHz, 16-bit, mono) durable
  via `sys_fsync` before close. The legacy single-carrier sine synth lives
  on as `synth_phoneme_sine` and is selectable at runtime via
  `CE_SYNTH_MODE=sine`; `CE_SYNTH_MODE=silence` emits zero samples for CI.
  `audio_speak.nova` layers Mode-2 espeak escalation and Mode-3 aplay/paplay
  best-effort playback on top. See `AUDIO_AUDIT.md` for the phoneme inventory
  audit + diphthong/affricate canonical formant tables.

The Phase 10 persistence layer (`src/persistence/`):

- **snapshot_writer** (ADR-0048) — the substrate-snapshot container: a tagged,
  versioned image with fixed, ordered sections `[SOUL][KGS][EPISODIC][SYNAPSES]
  [SELFMODEL]`, each holding a subsystem-serialized blob. Generic over the blobs
  (so it stays standalone); the crash-safe disk write (temp → fsync → atomic
  rename) is the runtime seam.
- **snapshot_reader** (ADR-0048) — parse + tag/version rejection, and the
  **load-bearing mandatory rehydration order** (soul → KGs → episodic): it
  refuses to load KGs before the soul (constitution must be live before any atom
  is admitted) or episodic before KGs (moments would dangle), and emits the
  ordered rehydration plan. The decision log persists independently and is not
  rolled back by a restore.

Three runnable artifacts build via `make install`: `examples/kernel_selfcheck.nova`
boots the substrate kernel; `examples/companion_spine.nova` runs the safety + IO +
persistence spine; and **`examples/crossengin_daemon.nova` → `bin/crossengin` is
the whole agent in one process**, driven by the ADR-0037 hybrid scheduler as a
real event-driven loop: input arrives as events; each step drains one and ticks
the substrate; on an event the full ADR-0036 six-loop cycle runs (perception via
the five-stage reader → memory → reasoning → emotion → goals → action) over a
shared concept KG, so a word read in perception seeds reasoning and imagination.
Affect emerges from the agent's own comprehension and becomes the tick's
plasticity modulator (with a predictive-coding residual as its error); a run of
empty ticks throttles the scheduler 100Hz→10Hz idle, gating imagination and
triggering a checkpoint. Output emerges from the substrate's reasoning: a reverse concept→word lookup
finds the naming word for a new conclusion and speaks it through the gated
effector ("see treat" after reading "fever"), no LLM picking the wording. The
agent also *grows its knowledge graphs at runtime*: unknown surface forms fire
self-learning triggers; at idle the arbiter drains them and `ask_user_to_teach`
ingests new word atoms + concept bindings (Beta(4,1) Tier-A prior) — a
follow-up event with the freshly-taught vocabulary is then comprehended. Forbidden actions are vetoed and logged; on shutdown the agent reboots
by rehydrating in mandatory order. This unified cross-subtree assembly is what
the import-path fix unblocked.

> Integration note: each loop is a self-contained unit over the shared
> blackboard, so the loops compose without tripping NOVA's import-dedup limit
> (blocker #10). Wiring all loops + the scheduler together in one program is the
> Phase 10 `main`, which will need a `nova_packages/` shim (see NEXT_SESSION.md).

## What "substrate, not workflow" means

Intelligence is intended to emerge from substrate dynamics, not from a
controller calling cognitive modules in sequence. The primitives are:

- **node** — uniform computational unit; specialization comes from learned
  state, not type. ~1M per part in v1 (target 1B), sparsely connected.
- **synapse** — persistent weighted connection; learns via Hebbian +
  error-driven plasticity; grows and prunes.
- **signal** — ephemeral typed message flowing through synapses (18 types).
- **atom** — persistent, mutable knowledge unit produced by nodes, stored in a
  domain knowledge graph, cross-referenced across graphs.
- **moment** — timestamped perception record; the entry point for input.
- **gate** — learned, content-based router between signals and parts.
- **KG (multi)** — domain-organized knowledge stores, spawned per domain.
- **reader** — five-stage hybrid input processor (not a parser, not an LLM).

A first principle runs through the whole design: **no LLM participates in
cognition.** The NOVA LLM bridge is reserved for speech-to-text / text-to-speech
modality conversion only (ADR-0014).

## Repository layout

```
docs/
  adr/        50 Architecture Decision Records (ADR-0001 .. ADR-0050)
  design/     architecture overview and supporting design docs
  runbook/    build / test / operational docs
src/
  substrate/  node pool, synapse, signal, tick, resonance  (the kernel)
  reader/     five-stage reader (ADR-0011, ADR-0012)
  gates/      learned signal routing (ADR-0009)
  parts/      perception, episodic, soul, reasoning, imagination, action, meta
  kg/         multi knowledge-graph store (ADR-0016, ADR-0017)
  learning/   self-directed learning (ADR-0026 .. ADR-0030)
  safety/     permission tiers, reversibility, constitution (ADR-0041 .. 0045)
  io/         transducers (STT/TTS modality) and motor effectors
  scheduler/  hybrid 100Hz tick + event scheduler (ADR-0037)
  audit/      append-only decision log (ADR-0043)
  persistence/ ordered substrate snapshot + rehydration (ADR-0048)
tests/        unit / integration / benchmark
scripts/      bootstrap.sh, run.sh, test.sh
examples/     runnable demos (kernel self-check)
```

Directories without code yet contain a `README.md` describing their
responsibility and governing ADRs.

## Building and running

CrossEngin compiles with the NOVA self-hosting toolchain in a sibling checkout
(`$HOME/NOVA` by default). NOVA has no third-party dependencies; it needs only
GNU `as`, `ld`, `make`, and `gcc`.

```sh
# one-time: verify host tools, locate/build the NOVA compiler
bash scripts/bootstrap.sh

# compile every module under src/
make build

# compile and run every unit test
make test

# build all runnable artifacts into ./bin/
make install
./bin/crossengin                  # the whole agent in one process
./bin/crossengin-selfcheck        # substrate kernel spine
./bin/crossengin-spine            # safety + IO + persistence spine
./bin/crossengin-kg-publisher     # distributed-substrate seam: publisher
./bin/crossengin-kg-subscriber    # distributed-substrate seam: subscriber
```

### Operations utilities

Three small shell tools cover the operations layer around the binaries:
preflight, structured-log mode, and snapshot diff.

```sh
# Preflight: green/yellow/red checklist of host env + deps + paths + a
# 3-second TCP probe of en.wikipedia.org (used by `/learn TOPIC`). Exits 0
# when every critical check passes; 1 if any critical fails. Optional
# helpers (ffmpeg, ImageMagick, espeak, aplay, parecord, whisper-cli,
# vosk-transcriber, wat2wasm, wasmtime, node, python3) appear as WARN
# when missing -- they do NOT gate the exit code.
bash scripts/crossengin-doctor.sh

# Structured JSON logging. `CE_LOG_JSON=1` flips the chat's per-turn
# operator log lines (the "agent>" preamble + the "perceive(m=N,unk=N)"
# line) and the daemon's per-cycle log line to one-line JSON objects:
#   {"ts":<int>,"level":"info","session":"<id>","event":"perceive",
#    "msg":"<input>","m":<int>,"unk":<int>}
# Default (env unset) preserves the legacy human-readable output BIT-
# IDENTICAL so existing log aggregators / web.py /metrics scrape stay
# valid. Daemon adds extra fields (hz, reason, mood_v, mod, routed).
CE_LOG_JSON=1 ./bin/crossengin-chat
CE_LOG_JSON=1 ./bin/crossengin

# Snapshot file diff: structural delta between two ./bin/crossengin*
# snapshot files. Reports atoms added/removed (by kg+label), beliefs
# changed (signed alpha/beta delta), sections added/removed, and soul
# mood/OCEAN drift. ANSI colours on a tty, plain when piped.
bash scripts/snap_diff.sh old.snap new.snap
```

### Distributed KG sync (publisher / subscriber demo)

Phase 20 / Tier-4 #2 ships the distributed-substrate seam: two or more
`bin/crossengin-kg-*` processes exchange atom-birth + belief-update events
over a TCP socket so subscriber daemons mirror the publisher's KG state
without sharing memory. P1.3 upgraded the protocol to v2 (the v1 lines are
still recognised); the new capabilities are N-subscriber fan-out, three new
event kinds (`PROMOTE` / `ATROPHY` / `DELETE`), bidirectional teach (a
subscriber can publish back to the publisher), reconnect-on-disconnect with
a `SUB FROM <id>` cursor resume, optional shared-token auth, and a
local-id-stable belief-average merge when both ends teach the same label.
Wire protocol is text, one operation per line, defined in
`src/io/transducers/kg_sync.nova`:

```
HELLO ce-kg-sync v2 [token=<TOK>]            -- handshake (anon or authed)
OK v2 protocol accepted                      -- handshake good
ERR auth                                     -- handshake refused (bad token)
SUB *                                        -- subscribe to all events
SUB FROM <id>                                -- resume after the given atom id
ATOM <kg> <id> <kind> <alpha> <beta> <label> -- atom birth (publisher -> subscriber)
PUB  <kg> <id> <kind> <alpha> <beta> <label> -- atom birth (subscriber -> publisher)
PROMOTE <kg> <id> <alpha> <beta>             -- belief update
ATROPHY <kg> <id>                            -- sub-threshold mark
DELETE  <kg> <id>                            -- atom killed
ACK <id>                                     -- per-event ack
BYE                                          -- graceful close
```

The publisher binds 127.0.0.1 by default (set `CE_KGSYNC_BIND=0.0.0.0` to
expose), listens on port 8766 (override via `CE_KGSYNC_PORT`), accepts the
number of subscribers given by `CE_KGSYNC_SUBS` (default 1 for backwards
compat), and -- if `CE_KGSYNC_TOKEN` is set -- gates new connections against
that token. The main `bin/crossengin` daemon is not touched; rolling the
seam into its idle loop is a future enhancement.

```sh
# v1-shape single-subscriber demo (unchanged)
./bin/crossengin-kg-subscriber > /tmp/sub.out &      # waits for handshake
sleep 0.5
printf 'widget\ngadget\nfever\n' | ./bin/crossengin-kg-publisher
grep widget /tmp/sub.out     # recv kg=language id=0 label=widget

# v2 fan-out: one publisher, three subscribers, token-gated
export CE_KGSYNC_TOKEN=s3kret
./bin/crossengin-kg-subscriber > /tmp/sub1.out &
./bin/crossengin-kg-subscriber > /tmp/sub2.out &
./bin/crossengin-kg-subscriber > /tmp/sub3.out &
sleep 0.5
printf 'widget\ngadget\n' | CE_KGSYNC_SUBS=3 ./bin/crossengin-kg-publisher
```

Point the build at a NOVA checkout elsewhere with `make NOVA_ROOT=/path/to/NOVA build`.

**For a complete walkthrough — prerequisites, three artifacts with expected
output, writing a new test, and troubleshooting — see [`MANUAL.md`](./MANUAL.md).**
Per-topic references: [`docs/runbook/build.md`](./docs/runbook/build.md),
[`docs/runbook/test.md`](./docs/runbook/test.md),
[`docs/runbook/run.md`](./docs/runbook/run.md), and
[`docs/design/overview.md`](./docs/design/overview.md) for the architecture.

## NOVA dependency and version note

The CrossEngin specification was written against an assumed "NOVA v4.1". The
NOVA checkout this repository builds against reports **v0.2.0**
(`src/version.nova`) / **v0.9.0** (launcher). CrossEngin pins to that actual
self-hosting toolchain and treats the larger capabilities (1M-node arenas,
sparse synapse adjacency at scale, true concurrency, 100Hz wall-clock pacing,
multi-KG, outbound fetch) as **upstream NOVA enhancements** that the ADRs assume
will land. Those enhancements are enumerated in
[`nova-deps.toml`](./nova-deps.toml) (`#1`..`#14`) and referenced throughout the
ADRs as `DEPENDS ON: NOVA enhancement #N`. Code that cannot yet be implemented
against the current toolchain is checked in as `*.nova.pending` (interface only)
and tracked in [`NEXT_SESSION.md`](./NEXT_SESSION.md).

## Decision records

Every architectural decision is recorded under [`docs/adr/`](./docs/adr/),
numbered `0001`–`0050` and grouped Foundation → Computation substrate → Reader
and language → Knowledge representation → Memory and learning → Self-directed
learning → Cognitive subsystems → Agent architecture → Safety and audit →
Operations and milestones. Start at
[`docs/adr/0001-substrate-architecture.md`](./docs/adr/0001-substrate-architecture.md).

## License

Proprietary and confidential. See [`LICENSE`](./LICENSE).
