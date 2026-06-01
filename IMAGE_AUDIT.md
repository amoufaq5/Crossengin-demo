# IMAGE_AUDIT — what real visual perception in CrossEngin would take

Status: **deferred runtime seam (NOVA enhancement #15 / ADR-0014 visual half).**
P3.1 lands the minimum-viable plank: a pure-NOVA decoder for the Portable Grey
Map binary format (`src/io/transducers/image_pgm.nova`), a pluggable visual
perception seam that turns pixel statistics into substrate-shaped feature
atoms (`src/io/transducers/visual_perception.nova`), the chat-side admin
command `/see PATH`, and the `scripts/image_to_pgm.sh` ImageMagick/ffmpeg
shim. This document mirrors `TLS_AUDIT.md` / `STT_AUDIT.md` / `WASM_AUDIT.md` —
the realistic path, not a promise.

## Why visual perception is structurally hard

A camera sensor is not a typewriter and not a microphone. Speech-to-text at
least carries information in one dimension (time); a single image is two
dimensions of raw intensity with no inherent boundaries between "object" and
"background" — no tokens, no phonemes, nothing the substrate can directly
bind to a concept atom. Every interesting decoder is multi-stage AND every
interesting feature pipeline downstream of the decoder is its own multi-week
(or multi-month) lift. The deferred runtime seam therefore has two distinct
halves: (1) the binary-decoding half — turn a JPEG/PNG/WebP file into a
pixel buffer — and (2) the perception half — turn a pixel buffer into
something the agent's concept atoms can latch onto. Pure NOVA covers neither
today; the plank we land in P3.1 is PGM (trivial decode, ~30 lines) + crude
statistics (mean, dominant intensity bucket, histogram entropy) so the
framework can be exercised end-to-end against a tractable fixture format.

The sandbox tested against has neither a camera nor the common image-
decoding libraries (no `convert`, no `magick`, no `ffmpeg` here today). The
unit suite covers the in-memory PGM decoder + stats AND the pure-NOVA
PNG decoder (signature + chunk iteration + zlib + full DEFLATE inflate
+ scanline unfilter); the shim's "no backend installed" branch is what
CI sees for non-PGM / non-PNG input (JPEG, WebP, HEIC, etc.).

## Why PGM, and why only PGM

The Portable Grey Map binary (P5) variant of netpbm is the simplest
standardized image format on Earth: ASCII header (`P5`, dims, maxval)
followed by raw 8-bit grayscale bytes. No compression, no filters, no DCT,
no Huffman, no color tables, no interlacing, no alpha, no metadata. A
correct decoder is ~30 lines of straight-line NOVA. The format is also a
common test fixture shape: `convert input.jpg -colorspace Gray output.pgm`
or `ffmpeg -i input.png -vf format=gray output.pgm` produces it directly.
A working PGM decoder PROVES the framework (the pluggable seam, the
feature-extraction helpers, the `/see` admin command, the integration
scaffold) without the multi-week trap of writing a real JPEG decoder.

ASCII PGM (`P2`, decimal pixel encoding) and 16-bit PGM (maxval > 255) are
deferred follow-ups — both shims and the common test corpus default to P5
8-bit.

## Realistic options for CrossEngin, in increasing difficulty

1. **Subprocess shim to ImageMagick / ffmpeg** *(easiest — landed)*. The
   operator points `/see` at a PGM, or pre-converts via
   `scripts/image_to_pgm.sh PATH` (probes `convert` → `magick` → `ffmpeg`
   → 16x16 grey placeholder, always exit 0). Same shape as
   `scripts/transcribe.sh` for STT — a thin escape hatch over a domain we
   don't intend to write ourselves.
2. **WASM-bundled `stb_image.h`** *(medium)*. Once P2.7 WASM matures the
   agent can host Sean Barrett's public-domain stb_image (~3000 lines of C,
   supports JPEG/PNG/BMP/TGA/PSD/HDR/GIF) compiled to WASM (~150 KB blob).
   The blocker is P2.7 WASI — without filesystem / argv it has no way to
   read a path. Same shape as `WASM_AUDIT.md` envisions for whisper-WASM
   on the STT side.
3. **Pure-NOVA PNG via zlib** *(LANDED, ~600 lines of NOVA)*. PNG = chunked
   container (IHDR/IDAT/IEND) + zlib(DEFLATE) on the pixel stream + per-
   scanline filter prediction (Sub / Up / Average / Paeth) + optional
   palette / interlacing. The DEFLATE decoder shipped in two halves:
   Item 3 (stored / BTYPE=00 only -- accepts `pngcrush -force` / `optipng
   -o0` / zlib level 0); follow-up extended it with static (BTYPE=01) +
   dynamic (BTYPE=10) Huffman so the pure-NOVA decoder ingests any
   standard PNG from a camera, phone, screenshot tool, or web download.
   Grayscale-8 only (truecolor RGB / RGBA / palette / 16-bit / Adam7
   interlace stay deferred).
4. **Pure-NOVA JPEG** *(harder, ~6-8 weeks)*. JPEG = SOI/EOI markers +
   Huffman tables (DC + AC, per channel) + zig-zag scan + 8x8 IDCT + YCbCr-
   to-RGB + 4:2:0 chroma subsampling. The IDCT is the numerical heart;
   it fits in NOVA with the small-multiplier discipline gotcha #11 already
   imposes elsewhere.

## Vision feature pipeline beyond pixels

Decoding the pixel buffer is half the battle. The other half is turning
that buffer into something the agent's concept atoms can latch onto.
P3.1 ships a deliberately crude set — `image_dim_<small|medium|large>`,
`image_<dark|mid|bright>`, `image_bucket_<0..7>`, `image_hist_<peaked|
uniform>` — that the substrate can bind exactly the way it binds a word
atom. The realistic feature ladder, each rung its own multi-week lift:

| Feature                          | NOVA effort         |
|----------------------------------|---------------------|
| Mean intensity / histogram       | landed              |
| Sobel edge magnitude             | DONE (P3.3)         |
| Harris corner detector           | DONE (P3.3)         |
| SIFT keypoint DETECTION (scale-  | DONE (P3.3 cont.)   |
|   space + DoG extrema only)      |                     |
| Canny edge with hysteresis       | DONE (P3.3 cont.)   |
| HOG (oriented gradients)         | 2-3 weeks           |
| SIFT-like 128-D descriptor       | DONE (P3.3 cont. v2)|
| Color histograms (HSV / Lab)     | 2-3 weeks           |
| CNN feature vector (untrained)   | 4-8 weeks           |
| CNN feature vector (trained)     | 6-12 months         |

A "production agent that can see photographs and reason about them" is
weeks 1-4 for JPEG decode + Sobel + Harris (~1.5 months honestly), 4-8
weeks for SIFT-quality keypoints, and many months for a trained CNN-like
embedding. Pure-NOVA CNN training is unrealistic this decade; the WASM
stb_image + an embedded ONNX-runtime path is the realistic embedded-model
option once both halves land.

## P3.3 structural features (landed)

After P3.1 P3.1.PNG landed the pixel-statistics half, P3.3 added the
first two STRUCTURAL feature pipelines so the substrate can perceive
gradient structure and corner geometry, not just intensity moments:

- **Sobel edge detection** (`src/io/transducers/image_sobel.nova`).
  Convolves the grayscale image with the standard 3x3 Sobel-X and
  Sobel-Y kernels. Output: per-pixel L1-norm edge magnitude + a 4-bin
  orientation bucket (0 / 45 / 90 / 135 degrees). Per-image atoms:
  `image_edge_dense` (when more than 10% of pixels exceed the magnitude
  threshold) or `image_edge_sparse`, plus an `image_orient_<deg>` atom
  for the dominant orientation bucket.
- **Harris corner detection** (`src/io/transducers/image_harris.nova`).
  Builds the 2x2 structure tensor M = [[Ix^2, Ix*Iy], [Ix*Iy, Iy^2]]
  from the Sobel gradients, smooths it via a 3x3 box filter, and
  computes the response det(M) - k * trace(M)^2 in milli-fixed-point
  (k = 0.04 -> 40 milli). 3x3 non-maximum suppression keeps only local
  peaks. Returns the top-N corners by response. Per-image atoms:
  `image_corner_count_<low|mid|high>` for the bucketed count, plus
  spatial-distribution labels `image_corner_dense_<top|bottom|left|right>`
  for the directional skew of the corner set.
- **SIFT keypoint DETECTION** (`src/io/transducers/image_sift.nova`,
  P3.3 cont.). The full SIFT pipeline is (1) scale-space + DoG
  extrema, (2) sub-pixel refinement + orientation histograms, (3)
  128-dimensional descriptor, (4) matching. The initial drop shipped
  piece (1); the P3.3 cont. v2 follow-up landed pieces (3) and (4) as
  well -- see the "SIFT 128-D descriptor + matcher" entry below.
  Piece (1) returns the keypoint LOCATIONS in (x, y, octave, scale)
  space. The scale-invariance comes from a 3-octave Gaussian pyramid
  (1x, 1/2x, 1/4x downsampled), each octave with 5 blur levels (the
  3x3 Gaussian kernel applied 3x per level, so the effective sigma
  between adjacent levels is wide enough to produce meaningful DoG
  signal), and 3x3x3 spatial-and-scale extremum checking on the 4 DoG
  layers per octave. Candidates are filtered by contrast
  (`|DoG|*1000/255 > 30` milli-normalized, matching Lowe's 0.03
  threshold) and by Harris-style edge rejection (we reuse
  `harris_apply` from R1.6 and require a Harris corner within
  Chebyshev distance 2 of each candidate). Per-image atom:
  `image_keypoint_count_<low|mid|high>` (low <10, mid 10..100, high
  >100). Dimensions capped at 256x256 per axis (3 octaves * 5 blur
  levels means up to 15x the per-pixel work of the input; 256x256
  keeps every intermediate accumulator well under the 2^20 codegen
  pointer-threshold ceiling). Minimum dim 32x32 (smaller images
  cannot usefully sample 3 octaves).
- **SIFT 128-D descriptor + matcher** (`src/io/transducers/image_sift.nova`,
  P3.3 cont. v2 -- the previously-deferred descriptor + matching half).
  For every keypoint produced by piece (1), the descriptor builds a
  rotation-invariant 128-D feature vector: walk the 16x16 window
  around the keypoint, accumulate gradient magnitudes into a 4x4 grid
  of 8-bin direction histograms (Gaussian-weighted by distance from
  the keypoint), normalize the resulting 128-int vector to L2 = 1000
  milli, cap each component at 200 milli (Lowe's illumination
  threshold), and re-normalize. The dominant-orientation alignment
  step rotates the descriptor frame so the same physical feature in
  two rotated images produces structurally-related vectors -- the
  rotation-invariance Lowe's paper is famous for. The matcher
  implements Lowe's ratio test: `sift_match_keypoints` returns the
  list of `[idx_a, idx_b, distance]` triples for which the best
  match's L2 distance is < 0.7 (700 milli) of the second-best
  candidate's distance. atan2 is computed via integer table lookup
  (8 quadrants + integer ratio sub-bin) so no float, no trig. Per-
  image atom: `image_descriptors_<low|mid|high>` mirrors the keypoint
  bucket and counts how many keypoints survived the descriptor build
  (uniform regions yield no gradient -> valid=0). New chat admin:
  `/match_images A B` decodes two PGM paths, detects + describes
  keypoints in each, runs the matcher, and prints
  `(matched N keypoint(s); A=...kps B=...kps)`. Caps + minimums
  inherit from the detection piece -- the descriptor's only extra
  requirement is that the input image be >= 16 pixels on each axis
  (the descriptor window itself is 16x16).
- **Canny edge detection** (`src/io/transducers/image_canny.nova`,
  P3.3 cont.). Canny (1986) is the CANONICAL edge detector and the
  standard preprocessing step for almost every downstream computer-
  vision task. Where Sobel ships the raw gradient magnitude, Canny
  adds two more stages on top: (1) Gaussian 3x3 smoothing (same
  1/2/4/2/1 weights image_sift uses), (2) Sobel signed gradients +
  L1-norm magnitude + direction-bin quantization (4 bins: 0/45/90/
  135 degrees), (3) non-maximum suppression along the gradient
  direction (keep this pixel only if its magnitude strictly exceeds
  both neighbors along the gradient axis -- thins thick edges to a
  single pixel), and (4) hysteresis thresholding with LOW=50 and
  HIGH=100 milli-normalized magnitudes via 8-connected worklist
  flood-fill (no recursion -- NOVA has no tail-call optimization, so
  a recursive flood would blow the stack on long edge chains). Per-
  image atom: `image_canny_edges_<low|mid|high>` (<20 milli low,
  20..100 mid, >=100 high). Strict-subset property holds by
  construction: NMS + thresholding can only DROP pixels relative to
  Sobel's above-threshold set, so every Canny edge has a non-zero
  Sobel magnitude there (verified by unit test). Dimensions capped
  at 512x512 per axis (same as Sobel/Harris); minimum dim 32x32
  (smaller images don't have enough interior pixels for the
  flood-fill to be informative).

Sobel + Harris fire only when the image is at least 16x16 in each axis
(the kernel needs a 3x3 neighborhood and the count buckets need
meaningful scale). SIFT-detection + Canny run only on images >= 32x32
(SIFT's 3-octave scale-space cannot sample usefully below that;
Canny's NMS + hysteresis flood-fill needs enough interior pixels for
the chain to be informative). Dimensions are capped at 512x512 for
Sobel/Harris/Canny, 256x256 for SIFT-detection, to keep all
intermediate accumulators well under NOVA's 2^20 codegen pointer
threshold (gotcha #11).

## Mapping features to atoms

Each detected feature becomes an atom of the form
`visual_<feature>_<value>`, created on first observation via
`atom_birth_monitor` (ADR-0025) with a Beta(α, β) prior reflecting
confidence:
- **High-confidence** features (mean intensity, dimensions, histogram
  stats — derived directly from every pixel) get **Beta(4, 1)**: initial
  belief mean `4/(4+1) = 800` milli, the same ballpark the STT subprocess
  path reports for a successful transcription.
- **Low-confidence** features (heuristic detectors with false-positive
  rates above ~10% — corner detection on noisy images, edge detection
  without smoothing) get **Beta(2, 1)**: initial belief mean `667` milli,
  leaving room for downstream evidence to push either way.
- Subsequent observations update the Beta posteriors via the standard
  Bayesian path (`atom_belief_update` in `kg/atom_store.nova`), exactly as
  words are updated when re-heard.

The current shipped seam emits only crude labels; the atom-creation side
(binding each label to an `ATOM_VISUAL` concept atom, attaching the
source-authority tier, dispatching the perception event to the reader)
lives in `src/agent/loop_perception.nova` and is a separate follow-up.

## Wall-clock estimate

| Milestone                                          | Effort           |
|----------------------------------------------------|------------------|
| PGM + crude stats + ImageMagick shim               | landed (P3.1)    |
| Sobel + Harris structural features                 | DONE (P3.3)      |
| SIFT keypoint DETECTION (no descriptor)            | DONE (P3.3 cont.)|
| Canny edge with NMS + hysteresis                   | DONE (P3.3 cont.)|
| JPEG decode in pure NOVA                           | 6-8 weeks        |
| PNG decode (zlib + filters)                        | DONE (grayscale-8)|
| Color histograms                                   | 2-3 weeks        |
| SIFT 128-D descriptor + matching                   | DONE (P3.3 cont. v2)|
| WASM-bundled stb_image bridge                      | 2 weeks post-P2.7|
| CNN embeddings (untrained / trained)               | 2-12 months      |

Combined honest estimate: **2-4 months** to a daemon that can ingest
photographs (JPEG decode + Sobel + Harris + color histograms + atom-
binding wire-up). Production-grade scene understanding (SIFT / CNN /
VQA) is **6-12 months** of focused effort.

## Recommended path

Today: **`scripts/image_to_pgm.sh` shim** for any operator who needs to
feed real photographs to a CrossEngin daemon. Auto-detecting (convert →
magick → ffmpeg → placeholder) and exits 0 in all branches so the seam
never crashes on a sealed sandbox. Set `CE_PGM_MAX_DIM=256` to respect
the pure-NOVA decoder's 1024x1024 pixel-area cap.

Next: pure-NOVA PNG (grayscale-8) LANDED — the modality bridge can
ingest PNG screenshots / UI captures / web downloads at any zlib level
(0..9, stored + static + dynamic Huffman). JPEG is still the natural
next step for the **photograph** path (cameras and phones default to
JPEG, not PNG). PNG truecolor RGB / RGBA / palette / 16-bit / Adam7
interlace remain deferred follow-ups on top of the grayscale-8 base.
Pure-NOVA WebP and HEIC are not on any roadmap within the next year.

## NOVA gotchas worked around in P3.1

- **Codegen pointer-threshold (gotcha #11, NOVA enhancement #6+).** Any
  in-function multiply whose product exceeds ~2^20 misroutes into
  `str_repeat`. The PGM decoder caps dimensions at 1024 per axis so
  `width * height <= 1048576 == 2^20` and the product stays under the
  empirical ceiling. Larger PGMs are refused at parse time with a clear
  "downsample first" error.
- **`read_file` builtin NUL stop.** NOVA's `read_file` returns a NUL-
  terminated string buffer, and `len()` stops at the first embedded
  NUL. For binary pixel data (every byte 0..255 is a valid grayscale
  value) this is fatal. We use `sys_open` + `sys_read` in a loop
  accumulating into a raw byte buffer (`alloc(N) + store8/load8`) so
  embedded zero bytes round-trip correctly.
- **ASCII-vs-binary PGM.** P3.1 targets binary P5 only; `pgm_parse_bytes`
  returns "pgm: not a P5 binary PGM (only 'P5' is supported)" if magic
  byte 1 is `2` (ASCII PGM) so an operator who feeds a `P2` file sees
  the right diagnostic. ASCII PGM is a deferred follow-up.

## Cross-references

* `src/io/transducers/deflate_decode.nova` — pure-NOVA DEFLATE decompressor
  (BTYPE=00 stored + BTYPE=01 static Huffman + BTYPE=02 dynamic Huffman,
  RFC 1951). Accepts the inner DEFLATE stream of any standard PNG. Item 3
  shipped stored-only; the static + dynamic Huffman follow-up extended it
  so phone-camera / screenshot / web-downloaded PNGs decode end-to-end.
* `src/io/transducers/png_decode.nova` — pure-NOVA grayscale-8 PNG decoder
  (signature + chunk iteration with CRC32 + IHDR/IDAT/IEND + zlib unwrap
  + DEFLATE inflate + scanline unfilter for filters 0-4).
* `src/io/transducers/image_pgm.nova` — pure-NOVA PGM-P5 decoder + stats.
* `src/io/transducers/image_sobel.nova` — pure-NOVA Sobel edge detector
  (DONE, P3.3).
* `src/io/transducers/image_harris.nova` — pure-NOVA Harris corner
  detector with milli-fixed-point response (DONE, P3.3).
* `src/io/transducers/image_sift.nova` — pure-NOVA SIFT keypoint
  detection (scale-space + DoG extrema, DONE in P3.3 cont.) plus the
  128-D descriptor + Lowe-ratio-test matcher (DONE in P3.3 cont. v2).
  Reuses `harris_apply` from R1.6 for the edge-rejection filter; the
  descriptor + matcher add `sift_describe`, `sift_match_descriptors`,
  `sift_match`, `sift_match_keypoints`, `sift_describe_all`, and the
  `sift_descriptor_count_label` count-bucket helper.
* `src/io/transducers/image_canny.nova` — pure-NOVA Canny edge detector
  with Gaussian smoothing + Sobel signed gradients + non-maximum
  suppression + 8-connected hysteresis worklist flood-fill (DONE,
  P3.3 cont.). Reimplements the Gaussian + Sobel kernels rather than
  importing the SIFT/Sobel modules so the module stays a leaf with no
  cross-module dependency; the Sobel reimplementation is necessary
  anyway because Canny needs the SIGNED gradients (Gx, Gy) and
  `image_sobel.sobel_apply` returns only the L1 magnitude.
* `src/io/transducers/visual_perception.nova` — pluggable seam + feature
  extraction (extended in P3.3 to call Sobel + Harris on images
  >= 16x16, SIFT-detection + descriptor on images >= 32x32 -- the
  descriptor pass emits a parallel `image_descriptors_<bucket>` atom --
  and Canny edge density on images >= 32x32 emitting
  `image_canny_edges_<low|mid|high>`).
* `scripts/image_to_pgm.sh` — ImageMagick / ffmpeg / placeholder shim.
* `examples/crossengin_chat.nova` — `/see PATH` admin command + dispatch
  + /help entry, plus `/match_images A B` for image-to-image keypoint
  correspondence (P3.3 cont. v2).
* `tests/unit/test_deflate.nova` — 46 in-memory assertions for the
  DEFLATE inflate: BTYPE=00 stored regression, BTYPE=01 static Huffman
  "hello" / empty / overlapping copy / length-extra-bits / distance > 256
  edges, BTYPE=02 dynamic Huffman pangram round-trip, BTYPE=11 reserved
  rejection. Pre-encoded fixtures via Python `zlib.compressobj(level=9,
  wbits=-15)`, no Python dependency at test time.
* `tests/unit/test_png_decode.nova` — 44 in-memory assertions for the
  PNG signature parser + CRC32 + chunk iteration + IHDR + DEFLATE wiring
  (stored regression smoke + BTYPE=11 reserved smoke; the deep DEFLATE
  coverage now lives in `test_deflate.nova`).
* `tests/unit/test_image_pgm.nova` — 43 in-memory assertions covering
  parse, stats, resize, and malformed inputs.
* `tests/unit/test_image_sobel.nova` — in-memory assertions covering
  Sobel kernel response, orientation buckets, density math, caps.
* `tests/unit/test_image_harris.nova` — in-memory assertions covering
  Harris corner detection on flat / edge / corner fixtures plus the
  count + spatial-distribution label helpers.
* `tests/unit/test_image_sift.nova` — in-memory assertions covering
  SIFT-detection on uniform / single-bright-spot / four-spots fixtures
  plus the dimension caps, count-bucket helpers, and per-keypoint
  accessors.
* `tests/unit/test_sift_descriptor.nova` — 28 in-memory assertions
  covering the 128-D descriptor pipeline (L2 norm ~= 1000 milli on a
  bright-spot keypoint, component cap honored, structurally-different
  fixtures land far apart, rotated copy stays structurally similar,
  Lowe-ratio-test pass + fail cases, keypoint-list matcher) plus
  invalid-input handling (null data, tiny image, uniform region,
  size-mismatch descriptors, edge-keypoint window shift).
* `tests/unit/test_image_canny.nova` — 22 in-memory assertions covering
  Canny on uniform / vertical-step / diagonal-step / hysteresis-bridge
  fixtures; the Canny-vs-Sobel STRICT-SUBSET invariant (every Canny
  edge lands on a non-zero Sobel magnitude); density-milli math + the
  density-label round-trip; dimension caps + too-small-image handling.
* `tests/integration/scenario_q_image_see.sh` — end-to-end /see chat
  assertions against gradient + uniform + 16x16 edge + 32x32 four-spots
  fixtures (+1 assertion for `image_canny_edges_mid` on the four-spots
  fixture).
* `tests/integration/scenario_cc_image_match.sh` — end-to-end
  /match_images chat assertions: same-image self-match returns N >= 1,
  per-image keypoint counts are reported, missing / partial arguments
  print the usage line, and the chat reaches /quit cleanly after the
  matcher probing sequence.
* `nova-deps.toml` enhancement #15 — upstream tracker for full visual
  stack (JPEG / PNG decode, feature extraction, embeddings).
* `STT_AUDIT.md` — sibling audit for the audio modality bridge.
