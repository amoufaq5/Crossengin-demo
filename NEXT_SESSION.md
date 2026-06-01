# CrossEngin — Next Session

This file is the source of truth for what works, what does not, and where to
continue. It is updated at every session boundary.

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

- Total unit suites: 131 (131 PASS; **+1 suite / +25 assertions from
  this session's SIFT keypoint detection (scale-space + DoG extrema only,
  descriptor deferred)** -- `test_image_sift.nova` covers uniform-grey
  no-keypoint baseline, single-bright-spot localization, four-spots
  detection, dimension-cap rejection, null-pointer + zero-dim guards,
  count-bucket classifier, count-label formatter, per-keypoint accessors,
  max_keypoints cap honored. **+1 suite / +54 assertions from
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
- Total integration tests: 19 scripts under `tests/integration/` covering 12
  multi-step scenarios (durability across SIGKILL, decision-log durability
  across SIGKILL [P0.7], neighborhood paraphrase, multi-source `/learn`,
  `/meta` table, constitutional veto, web frontend smoke, distributed KG
  sync, session switch isolation, web cookie isolation, plain-HTTP client
  loopback [P1.4], Prometheus `/metrics` scrape endpoint [P2.9 -- 35
  assertions], **PSK secure-channel loopback [P1.4 cont. -- 6
  assertions]**) and 5 admin-command edge-case scripts. Run with `make
  integration`.
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
