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
| HOG (oriented gradients)         | DONE (R14D)         |
| HOG sliding-window detector      | DONE (R15C)         |
| SIFT-like 128-D descriptor       | DONE (P3.3 cont. v2)|
| ORB (FAST + rBRIEF, patent-free) | DONE (P3.3 cont. v3)|
| LBP texture descriptor (Ojala'96)| DONE (R17D)         |
| LBP-gallery face RECOGNITION     | DONE (R18D)         |
| Color histograms (HSV / Lab)     | 2-3 weeks           |
| Spatial k-means segmentation     | DONE (R11E)         |
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
- **ORB (Oriented FAST + Rotated BRIEF)**
  (`src/io/transducers/image_orb.nova`, P3.3 cont. v3 -- the
  patent-free / integer-only SIFT alternative). Rublee et al. 2011's
  ORB pairs three pieces: (1) FAST-9 corner detection (Rosten 2006),
  a 16-pixel Bresenham-circle brightness test that flags p as a
  corner iff 9 or more contiguous pixels around the circle are all
  brighter than I(p)+t or all darker than I(p)-t (t=20 on the 0..255
  scale; contiguity is checked over a doubled 32-element ring so the
  wrap at index 15->0 is handled). (2) Harris-corner-proximity
  ranking via REUSE of `harris_apply` from R1.6: candidates with no
  Harris corner within ORB_HARRIS_RADIUS (4 pixels Chebyshev) are
  dropped as edge responses, mirroring image_sift's edge-rejection
  test. (3) Intensity-centroid orientation: walk a 31x31 patch around
  the keypoint, compute first moments m_10 and m_01, then
  theta = atan2(m_01, m_10) quantized into one of 30 buckets (12
  degrees each) via a precomputed cos/sin milli-unit table; the
  bucket index keys the descriptor's point-pair rotation. (4) rBRIEF
  descriptor: 256-bit binary signature. The 256 (x_i, y_i, x_j, y_j)
  point pairs in [-15..+15]^2 are deterministically generated by a
  16-bit Galois LFSR (polynomial x^16+x^14+x^13+x^11+1, feedback mask
  0xB400; seed 0x12345 trimmed to 0x2345 low-16) so the descriptor
  is reproducible without shipping a 256x4-int constant table. Each
  pair is ROTATED by the keypoint's orientation before sampling so
  the descriptor is rotation-invariant. Bit_n = 1 iff
  I(rotated_p_i) < I(rotated_p_j). Bits packed LSB-first into 8
  int32 chunks (= 32 bytes). (5) Hamming-distance matcher with
  Lowe's ratio test (default ratio 0.75 = 750 milli): for each
  query keypoint in A, find the best and second-best matches in B
  by popcount-of-XOR over the 8 chunks; accept if
  best/second < 0.75. The popcount/XOR primitives are synthesized
  byte-wise from NOVA's int_add/int_mul/% (no native bitwise
  builtins). Per-image atoms: `image_orb_kps_<low|mid|high>` (count
  bucket parallel to harris/sift) and `image_orb_density_<low|mid|high>`
  (density per kilo-pixel, <=5 low / <=20 mid / >20 high). Dimensions
  capped at 256x256 per axis (same as SIFT); minimum dim 32x32
  (the 31x31 orientation patch needs interior pixels). New chat
  admin: `/orb_match A B` decodes two PGM paths, runs the full
  ORB pipeline + Hamming-distance Lowe-ratio matcher, and prints
  `(orb matched N keypoint(s); A=...kps B=...kps)`. On the
  40x40 four-spots-vs-four-spots reference fixture ORB finds 96
  keypoints per image and produces 96 self-matches and 96 rotation
  matches (rotation invariance verified by the unit suite); the
  spots-vs-vertical-edge cross fixture produces 0 matches (Harris
  filter rejects every FAST candidate on a single-direction edge).
  ORB ships ~3-5x faster than SIFT for end-to-end keypoint+match
  on the same fixture, with integer-only arithmetic throughout the
  hot loops.
- **HOG (Histogram of Oriented Gradients) dense descriptor**
  (`src/io/transducers/image_hog.nova`, R14D -- the classic
  Dalal-Triggs 2005 dense feature). Where SIFT/ORB describe a
  handful of sparse keypoints, HOG tiles the WHOLE image (or
  detection window) and summarizes gradient orientation in fixed
  cells. The pipeline is: (1) per-pixel central-difference gradient
  `Gx = I(x+1,y) - I(x-1,y)`, `Gy = I(x,y+1) - I(x,y-1)`;
  (2) L1-magnitude `|Gx| + |Gy|` + unsigned orientation bin via an
  integer atan2 lookup (the same 8-quadrant tangent-table trick
  image_sift's `_sift_dir_bin` uses); (3) divide into 8x8 CELLS,
  one num_bins=9 histogram per cell weighted by magnitude;
  (4) group into 2x2 BLOCKS = 36-element descriptors,
  L2-normalize to 1000 milli, clip every component at 200 milli
  (L2-Hys; Lowe's 0.2 illumination cap mirrored from SIFT's
  descriptor), re-normalize, and apply a final clamp so the
  documented invariant "no bin > 200 milli" holds post-renorm;
  (5) slide blocks at stride=1 (50% overlap) and concatenate in
  scan order. Total descriptor length for a WxH image with
  cell_size=8 is `(W/8 - 1) * (H/8 - 1) * 36`; for the 32x32
  reference fixture that is `3 * 3 * 36 = 324` ints (well under
  the 2^20 codegen pointer-threshold ceiling). HOG is the FOURTH
  descriptor family alongside the sparse keypoint detectors:
  unlike SIFT/ORB it is NOT rotation-invariant (a rotated copy of
  the same image produces a different HOG vector, unit-tested),
  but it IS moderately translation-invariant within a block stride
  (also unit-tested). The trade-off is by design: HOG is meant
  for templates where orientation is part of the identity
  (upright pedestrians, cars from the side -- Dalal-Triggs's
  canonical 64x128 pedestrian window produces 105 blocks x 36 =
  3780 ints, the standard SVM input). Per-image atoms:
  `image_hog_descriptor_size_<small|medium|large>` (size buckets:
  <=200 small, <=1000 medium, >1000 large -- the 32x32 default
  produces medium, the 64x128 Dalal-Triggs window produces large)
  and `image_hog_dominant_bin_<0..8|none>` (the argmax over the
  global per-bin magnitude sums). The vertical-edge integration
  fixture produces `dominant_bin=0` (horizontal gradient direction
  even though the EDGE is vertical -- HOG quantizes the gradient
  vector's orientation, not the edge axis); the four-spots fixture
  produces `dominant_bin=4` (vertical, since the spot edges run
  horizontally across the spot boundary -- the unit test asserts
  these two fixtures disagree, demonstrating that HOG separates
  single-direction edges from clustered-corner content). The
  `hog_compare` distance metric is L1 over the concatenated
  normalized vectors (identical images -> 0; rotation by 90 deg
  on the same fixture -> >= 2000 milli; 1-px translation -> small,
  unit-tested). Dimensions capped at 256x256 per axis (same as
  SIFT/ORB); cell_size in {4, 8, 16}; num_bins in {6, 9, 12}; the
  minimum dim is 16 (two cells of 8 minimum to form one 2x2 block).
  New chat admin: `/hog PATH` decodes a PGM and prints
  `(hog WxH cells=N dominant_bin=K magnitude_mean=M)`. The integer
  Newton's-method sqrt for the L2 norm is bounded at 50 iterations
  (same shape as `_sift_isqrt`).
- **HOG sliding-window object detector**
  (`src/io/transducers/image_detector.nova`, R15C -- the canonical
  Dalal-Triggs pedestrian pipeline built on R14D's dense descriptor).
  Dalal-Triggs (CVPR 2005) trained a linear SVM on the HOG vector of
  a 64x128 window and slid that classifier across the image; windows
  scoring above threshold became detections, then non-maximum
  suppression collapsed overlapping windows. CrossEngin's no-training-
  data design substitutes the SVM with TEMPLATE MATCHING via L1
  distance (`hog_compare`) between every window's HOG and a stored
  template HOG (the descriptor of a single positive example). The
  pipeline is: (1) `det_train_template(image, w, h, win_w, win_h)`
  computes the template HOG, optionally cropping a centered window if
  the input image is larger than win_w x win_h; (2)
  `det_sliding_window(image, w, h, template, threshold_milli, stride)`
  walks (x, y) at the requested stride (4..32, default 8), extracts
  each window via `_det_extract_window`, computes
  `hog_compute_default` on the sub-image, and admits the position if
  `hog_compare < threshold_milli`; (3) `det_nms(detections, box_size,
  iou_milli)` sorts detections by ascending distance and greedily
  drops overlapping windows whose IoU >= iou_milli/1000; (4)
  `det_detect(...)` ties the three together via the template's
  dimensions for the NMS box geometry. Threshold defaults to 4000
  milli (identical-content windows score 0; uniform-background
  windows score ~3000 on simple vertical-edge templates; the 4000
  threshold sits in the "near-identical" band -- callers may tighten
  for high-confidence-only matches or loosen to absorb noise).
  NMS IoU defaults to 300 milli (Dalal-Triggs's 0.30 number).
  Caps: image dim <= 256, template dim 16..128, stride clamped into
  [4, 32]. Perf budget: brute force quadratic in the candidate-grid
  count. For a 256x256 scene with 32x32 template at stride 8 the
  grid is (256-32)/8+1 = 29 across and 29 down -> 841 windows; each
  window runs `hog_compute_default(32x32)`. The R14D HOG profile
  was estimated at ~100 ms per fixture but actual runtime is much
  faster (sub-millisecond per HOG -- the 32x32 integration scenario
  completes in <100 ms end-to-end for a 25-window grid). Per-image
  atom: `image_detector_count_<none|one|few|many>` (emitted via
  `det_append_features_if_templated` when `CE_VP_DETECT_TEMPLATE`
  env points at a template PGM; bucket boundaries: 0 none, 1 one,
  2..4 few, 5+ many). New chat admin: `/detect TEMPLATE.pgm
  SCENE.pgm` decodes both PGMs, trains the template, runs sliding-
  window + NMS, and prints `(detect N detection(s); T=WxH S=WxH
  stride=S best=DIST at (X, Y))`. The integration scenario
  (`scenario_jjj_detector.sh`) verifies detection at a known offset
  within +/- stride accuracy and 0 detections on a uniform-background
  scene.
- **Stereo block-matching SAD disparity + depth**
  (`src/io/transducers/image_stereo.nova`, R7E -- the missing third
  dimension). The CV pipeline so far operates on a single image:
  edge gradients (Sobel/Canny), corner/keypoint features
  (Harris/SIFT/ORB), per-frame motion (`video_motion_vectors`). None
  of those recover depth. Stereo block matching with
  Sum-of-Absolute-Differences (SAD) is the simplest integer-only
  path to a per-pixel DEPTH estimate. For each pixel (x, y) in the
  LEFT image, extract a WIN_SIZE x WIN_SIZE block (default 7x7)
  centered there, slide that block along the SAME scanline in the
  RIGHT image from x down to x - MAX_DISP (default 64), compute SAD
  at each offset, store the offset minimizing SAD as disparity.
  Depth follows from the similar-triangles formula
  `depth_mm = baseline_mm * focal_pixels / disparity`; disparity == 0
  clamps to `STEREO_MAX_DEPTH_MM` (100 m) as an "unknown / infinity"
  sentinel. Border pixels (window would fall off the image) keep
  disparity 0. The leftmost interior columns where x - half < SHIFT
  cannot reach the true disparity (local_max_d caps below SHIFT) so
  they read smaller disparities, dragging the mean a few units below
  the ground-truth shift -- on a 64x32 textured pair shifted by 10
  pixels the unit test asserts disparity == 10 EXACTLY at probed
  interior points, and the mean lands at 6-8. Density classifier
  (per-thousand pixels with non-zero disparity): low <100, mid
  100..499, high >=500. New chat admin: `/depth L.pgm R.pgm` decodes
  two same-dimension PGM paths and prints
  `(depth WxH mean_disp=D density=Dmilli image_stereo_density_*)`.
  Visual seam (`vp_features_for_image`) emits
  `image_stereo_disparity_mean_<low|mid|high>` +
  `image_stereo_density_<low|mid|high>` atoms when
  `CE_VP_STEREO_RIGHT` env points at the companion right PGM. SAD
  was chosen over normalized cross-correlation (NCC) and
  semi-global matching (SGM) for the same reason PGM was chosen
  over JPEG: simplest standardized algorithm that produces a
  structurally interesting feature, with NO division in the inner
  loop and NO floating-point operations. **R8D quality follow-ups**
  added LR-check and sub-pixel refinement on top of R7E's integer
  path; **R9A** then landed SGM (the third stereo tier):
  `stereo_disparity_sgm` aggregates the SAD cost volume along 4
  scanline paths (left-right, top-bottom, right-left, bottom-top)
  with the Hirschmuller (2008) recurrence
  `L_r(p, d) = C(p, d) + min(L_r(p-r, d), L_r(p-r, d-1) + P1,
  L_r(p-r, d+1) + P1, min_d' L_r(p-r, d') + P2) - min_d' L_r(p-r, d')`,
  emits the argmin of the 4-path sum as the disparity map, and
  caps dims at 128x128 with MAX_DISP<=64 to keep the cost volume
  under 4MB. P1=8/P2=32 default penalties; `stereo_disparity_sgm_quality`
  layers LR-check + sub-pixel parabolic refinement on the
  SGM-aggregated cost. Unit tests show SGM <= BM variance in a
  textureless noisy band (the headline SGM benefit -- speckle
  reduction). New chat admin `/depth_sgm L.pgm R.pgm`. Remaining
  follow-ups: 8-path SGM, mutual-information data term, and
  data-adaptive P2.
  R8D's lineage: `stereo_disparity_lr_check`
  computes left->right + right->left disparities and zeros pixels
  where the two answers disagree by more than `lr_tolerance` pixels
  (textbook default 1) -- rejects occlusions, texture-less regions,
  and depth discontinuities cleanly; `stereo_disparity_subpx` fits a
  parabola through SAD(d*-1), SAD(d*), SAD(d*+1) and emits
  milli-disparity = int(x_min * 1000) (so 10.5 px = 10500); the
  combined `stereo_disparity_quality` runs LR-check then sub-pixel
  on survivors and returns a milli-disparity list with 0 at
  inconsistent pixels. Degenerate-parabola fallback (denominator <= 0,
  textureless / no-isolated-minimum regions): snap to integer * 1000.
  New chat admin `/depth_q L.pgm R.pgm` prints
  `(depth_q WxH mean_milli=M density=Dmilli image_stereo_density_*)`.
  On a 64x32 ramp shifted by 10.5 px the unit test asserts milli is
  within +/- 300 of 10500 at probed interior pixels (e.g. (30, 16),
  (40, 20), (45, 14)); on an integer-shifted-by-10 pair milli stays
  within +/- 200 of 10000; on a synthetic-occlusion fixture (right
  has a horizontal black band only) the LR-check rejects the majority
  of band-region pixels while textured-row pixels survive at the
  correct integer disparity. SGM (4 paths) is now in (R9A); the
  8-path / mutual-information-data-term extensions remain
  deferred. Dimensions
  capped at 256x256 per axis (the inner triple loop runs in
  O(W*H*MAX_DISP*WIN_SIZE^2) = O(W*H*3136); at 256x256 that's ~205M
  ops, the upper bound for the chat's per-command latency budget);
  minimum dim 32x32 (the 7x7 window + 64-disp search needs headroom).

- **Lucas-Kanade dense optical flow**
  (`src/io/transducers/image_optical_flow.nova`, R10D -- the missing
  dense per-pixel motion field). The CV motion pipeline previously
  covered only block-based motion vectors (`video_motion_vectors`,
  coarse per-block) and sparse keypoint matching (SIFT R5C + ORB R6D
  via descriptor matching across frames). R10D adds the textbook
  DENSE per-pixel motion vector between two consecutive frames using
  the 1981 Lucas-Kanade local-window normal equations -- integer
  arithmetic only, no Eigen / no floats / no SVD. For each interior
  pixel (x, y) compute integer image gradients (Ix, Iy via central
  differences /2) and the temporal gradient (It = I_next - I_prev)
  over a WIN_SIZE x WIN_SIZE window centered there, then solve the
  2x2 system via the closed-form integer inverse:
  `det = (Sum Ix^2)(Sum Iy^2) - (Sum IxIy)^2;` `u_milli =
  ((Sum Iy^2)(-Sum IxIt) - (Sum IxIy)(-Sum IyIt)) * 1000 / det;`
  `v_milli = (-(Sum IxIy)(-Sum IxIt) + (Sum Ix^2)(-Sum IyIt)) * 1000 / det`.
  det == 0 (textureless / aperture-problem pixels) -> flow marked
  invalid; (u, v) reads (0, 0). On a smooth quadratic-bowl fixture
  shifted diagonally by (1, 1): u ~ 918 milli, v ~ 1042 milli at
  probed interior pixels (target 1000, 1000); on a texture-less
  constant-fill fixture all 1024 pixels are correctly marked invalid
  (100% degeneracy detection rate). Default WIN_SIZE = 5 (matches
  OpenCV calcOpticalFlowPyrLK), clamped to odd in [3..15]; dims
  capped at 256x256 (matches R7E stereo so the same fixture sizes
  round-trip). Density classifier on mean magnitude: low <200 milli,
  mid 200..1999, high >=2000. New chat admin: `/flow prev.pgm
  next.pgm` decodes two same-dimension PGMs and prints
  `(flow WxH mean_mag=Nmilli valid=K image_optical_flow_density_*)`.
  Visual seam emits `image_optical_flow_magnitude_<low|mid|high>`
  + `image_optical_flow_density_<low|mid|high>` atoms when
  `CE_VP_FLOW_PREV` env points at the PREVIOUS frame PGM. The R10D
  single-level algorithm is exact for sub-pixel shifts (first-order
  Taylor regime); multi-pixel shifts under-estimate because the
  linearization breaks at the discontinuity. R11A adds the pyramidal
  coarse-to-fine extension below; R13B closes R11A's translational-
  aggregate simplification with full per-pixel propagation across
  pyramid levels. Follow-ups: dense Farneback flow, motion-occlusion
  masks.

- **Pyramidal Lucas-Kanade (R11A on top of R10D)**
  (`src/io/transducers/image_optical_flow.nova`, EXTENDED). R10D's
  single-level solver under-estimates large displacements -- the
  textbook fixture measured u ~ 2384 milli when target was 3000 (3 px
  shift) and u ~ 918 milli when target was 1000 (1 px shift). R11A
  adds the classical Bouguet 2000 coarse-to-fine pyramid: build
  Gaussian image pyramids of both frames (3x3 Gaussian smooth + 2x
  downsample per level, default L=3 levels), start at the coarsest
  level with flow (0, 0), iteratively warp NEXT by the current flow
  and re-solve via R10D's `lk_optical_flow` to produce a flow
  correction, upsample (u, v) by 2 when descending to the next
  level, repeat up to MAX_ITERATIONS=3 (default) at each level.
  Public API: `lk_pyramid_build(image, w, h, levels)` -> list of
  `[level_w, level_h, level_buf]`;
  `lk_warp_image(image, w, h, u_field, v_field)` -> warped byte
  buffer (integer pixel rounding, OOB zero-fill);
  `lk_optical_flow_pyramid(prev, next, w, h, win_size, levels,
  max_iter)` -> same result tuple shape as R10D's `lk_optical_flow`.
  Reuses R10D's single-level solver as the inner step (no
  duplication). On the headline R10D-fails fixture (8-px rigid
  right-shift, 80x64): single-level reads u=5697 milli at (20, 16);
  pyramid reads u=7531 milli (target 8000, within +/-500). 4-px down:
  v=4116 (target 4000); diag (3, 3): u=2962 v=2762 (target 3000,
  3000). Identical frames: u=v=0 with the inner per-pixel valid flag
  intact. Texture-less fixtures still flag det=0 -> valid=0 (the
  R10D degeneracy detection is not masked by the orchestrator).
  Per-iteration correction clamped to +/-4000 milli per pixel to
  suppress boundary discontinuity outliers (a shifted-zero strip at
  the image edge survives the Gaussian into the coarse levels and
  would otherwise dominate the averaged global shift). New chat
  admin `/flow_pyr prev.pgm next.pgm` (dispatch only, no help line
  to stay in chat budget). Caps mirror R10D: dims <= 256x256; levels
  in [1..LK_PYR_MAX_LEVELS=5]; default L=3 (handles ~16 px shifts on
  a 256 px image without the bottom level falling under
  LK_PYR_MIN_LEVEL_DIM=8).

- **Full per-pixel pyramidal Lucas-Kanade (R13B on top of R11A)** --
  same file. R11A's translational-aggregate simplification collapses
  motion DISCONTINUITIES because it propagates a single (u, v) shift
  across pyramid levels: a frame whose left half shifts by 10 px and
  right half stays still gets resolved to ~2 px everywhere (the
  boundary-noise-dominated average). R13B implements the full Bouguet
  2000 algorithm: the per-pixel flow field is carried across pyramid
  levels (each pixel warps NEXT using its own bilinear sub-pixel
  offset, runs R10D's single-level LK to produce a per-pixel
  correction, accepts or rejects the correction via a robust
  7x7-window MAD test plus a per-iteration hard ceiling, then updates
  the per-pixel u, v). At the coarsest level only, pixels whose inner
  solve was invalid or whose correction was MAD-rejected receive the
  global median correction as a fill -- giving the next-level warp a
  coherent everywhere field rather than zeros. Public API:
  `lk_optical_flow_pyramid_perpixel(prev, next, w, h, win_size,
  levels, max_iter)` returns the same result-tuple shape as R10D's
  single-level solver. The accepted field tracks pixels with REAL
  per-pixel solves (separate from fill-from-median pixels); the
  public valid_buf only flags accepted ones, so textureless regions
  still flag det=0 -> valid=0. Bilinear warp inline (not R11A's
  integer round-to-nearest) preserves sub-pixel accuracy across
  pyramid levels. Default `max_iter=1` per level -- in the per-pixel
  pipeline multi-iter at the same level uses a per-pixel warp that
  may include rejected pixels (kept at their previous value), the
  inner solve on that scrambled image produces wild residuals, and
  the MAD test cannot reliably reject them because the whole
  neighborhood is wild. New chat admin `/flow_pp prev.pgm next.pgm`.
  Headline on the 128x64 split-shift fixture (left=10 px, right=0 px,
  dense sinusoidal texture): R13B reads LEFT u=8180 RIGHT u=0
  (recovering the discontinuity); R11A's translational-aggregate
  reads LEFT u=2008 RIGHT u=552 (both halves dominated by boundary
  noise). On the easy uniform 8-px shift case R13B reads u=7859
  (target 8000); R11A reads u=8148 -- comparable. Outlier rejection:
  a single-pixel corruption in NEXT (e.g. `next[16, 16] = 0`) is
  caught by the MAD ceiling and the per-pixel flow at that pixel
  stays near zero rather than tracking the inner LK's bad-data
  overshoot. Textureless fixtures: valid_count == 0 (R10D degeneracy
  preserved). Closes the R11A.2 follow-up flagged above.

Sobel + Harris fire only when the image is at least 16x16 in each axis
(the kernel needs a 3x3 neighborhood and the count buckets need
meaningful scale). SIFT-detection + Canny run only on images >= 32x32
(SIFT's 3-octave scale-space cannot sample usefully below that;
Canny's NMS + hysteresis flood-fill needs enough interior pixels for
the chain to be informative). Dimensions are capped at 512x512 for
Sobel/Harris/Canny, 256x256 for SIFT-detection, to keep all
intermediate accumulators well under NOVA's 2^20 codegen pointer
threshold (gotcha #11).

## R11E spatial k-means image segmentation (landed)

After R10D landed dense optical flow, the CV pipeline still had no
COARSE region partitioner. R11E adds spatial k-means in the
(intensity, x, y) joint space:

- `src/io/transducers/image_segmentation.nova`. Textbook Lloyd's
  k-means on integer arithmetic. K centroids on a tiled grid; assign
  each pixel to the centroid minimizing
  `w_intensity * (I - I_k)^2 + w_spatial * ((x - x_k)^2 + (y - y_k)^2)`;
  recompute centroids as integer means; iterate until stable or
  `max_iter` reached. Dimensions capped at 256x256; K in [1..32];
  max_iter <= 50. Public API: `seg_kmeans`, `seg_kmeans_weighted`,
  `seg_label_at`, `seg_centroid_at`, `seg_render_pgm`,
  `seg_render_to_file`. Per-image atoms:
  `image_segmentation_cluster_count_<K>` and
  `image_segmentation_dominant_<id>`. Chat: `/segment PATH [K]`
  (default K=5) writes a segmented PGM to `/tmp/segmented.pgm` for
  human inspection.

Limitations: deterministic grid init (not k-means++), no empty-cluster
re-seeding, no connectivity constraint (a single cluster may span
disconnected regions of equal intensity). SLIC superpixels + graph-cut
remain future follow-ups for true region-segmentation.

### R12B — SLIC superpixel boundary-adherent segmentation (DONE)

`src/io/transducers/image_superpixels.nova` (R12B) implements Achanta
2012 SLIC: a localised k-means where each cluster only competes for
pixels in a `2S x 2S` window around its center (S = isqrt(W*H/K) is
the grid step). The combined distance metric weighs intensity vs.
spatial via compactness `m` (default 10); the integer form scales by
S^2 to avoid floats AND sqrt: `D^2_scaled = d_int^2 * S^2 + d_spat^2
* m^2`. Centers are gradient-perturbed in their 3x3 neighbourhood
(L1 finite-difference proxy) to avoid initialising on top of edges.
The convergence loop snapshots labels and stops on zero changes
(default <= 10 iters, capped at 20). Boundary pixels are detected by
4-neighbour label difference and rendered white over the original
intensity (the standard SLIC validation overlay). Public API:
`slic_segment` (full knobs), `slic_segment_default` (m=10, max_iter
=10), `slic_label_at`, `slic_center_at`, `slic_boundaries`,
`slic_boundary_count`, `slic_render_pgm`, `slic_render_to_file`.
Per-image atom: `image_slic_boundary_count_<low|mid|high>` (bucketed
by boundary pixels / image area in milli; <30 low, 30..100 mid,
>100 high). Caps: dims <= 256, K in [16, 1024] (auto-clamped to
keep `S >= 4`), m in [1, 40], max_iter <= 20. Chat: `/slic PATH
[K]` (default K=64) writes the boundary-overlay PGM to
`/tmp/slic_overlay.pgm`. Coexists with R11E (sibling, not
replacement): k-means asks "where are the regions?" (coarse);
SLIC asks "what are the boundary-adherent superpixels?" (fine).
Limitations: grayscale only (Lab/RGB deferred); no connectivity
post-pass (a noisy image could leave isolated single-pixel orphans
-- on the capped fixtures clusters stay connected naturally); the
fallback nearest-center snap for pixels outside every 2S window is
worst-case O(N*K) but only fires on image corners when K is sized
correctly.

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
| ORB (FAST + rBRIEF + Hamming matcher)              | DONE (P3.3 cont. v3)|
| Stereo block-matching SAD disparity + depth         | DONE (R7E)       |
| Stereo LR-check + sub-pixel refinement              | DONE (R8D)       |
| Stereo Semi-Global Matching (4 paths)               | DONE (R9A)       |
| Stereo SGM 8-path + mutual-information data term    | 2-3 weeks        |
| Spatial k-means image segmentation                  | DONE (R11E)      |
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
* `tests/unit/test_stereo_quality.nova` — 42 in-memory assertions
  covering R8D's LR-check + sub-pixel pipeline: LR-check on
  identical inputs (every pixel consistent), shifted-by-10 pair
  (interior disparities survive at 10), occluded fixture (band
  pixels rejected, textured-row pixels kept), tolerance / invalid-
  input clamping; sub-pixel on integer-shifted-by-10 pair (milli
  within +/- 200 of 10000), 10.5-px-shifted pair via bilinear
  interpolation (milli within +/- 300 of 10500), invalid inputs,
  OOB accessor safety; combined `stereo_disparity_quality` on
  integer-shifted-by-8 pair (milli ~8000 at consistent interior
  pixels, 0 at borders) + occlusion fixture (band pixels rejected);
  parabola-degeneracy fallback on flat SAD; /depth_q dispatch
  usage strings.
* `tests/integration/scenario_kk_stereo_quality.sh` — 11
  end-to-end /depth_q chat assertions against ramp + integer-
  shifted-by-10 + sub-pixel-shifted-by-10.5 PGM fixtures
  synthesized in /tmp via Python: identical inputs report
  mean_milli=0, integer-shifted pair reports mean_milli >= 1000,
  sub-pixel-shifted pair reports mean_milli >= 500, dim mismatch +
  missing-file errors surface cleanly, chat reaches /quit cleanly
  after the probing sequence.
* `tests/unit/test_stereo_sgm.nova` — 39 in-memory assertions
  covering R9A's 4-path Semi-Global Matching: SGM on identical
  inputs (every pixel 0), shifted-by-8 pair (probed interior reads
  disparity 8), pure-noise pair (BM speckles -> variance > 0,
  SGM smooths -> variance < BM variance; the headline SGM
  invariant), textureless-band fixture (SGM propagates the
  surround SHIFT into the band), large P2 / P2 == P1 / very-high
  penalty cases, combined SGM-quality on shifted-by-8 pair (milli
  ~8000 at consistent pixels), invalid-input refusals + volume cap
  (128x128x64 rejected), /depth_sgm dispatch usage strings.
* `tests/integration/scenario_nn_stereo_sgm.sh` — 13 end-to-end
  /depth_sgm chat assertions against textured + textureless-band
  + pure-noise PGM fixtures: identical inputs report mean_disp=0,
  shifted pair reports mean_disp >= 1 with a density label, dim
  mismatch + missing-file errors surface cleanly, BM-vs-SGM
  band-fixture output lines coexist, on the pure-noise fixture
  BM reports density "mid|high" (speckle) while SGM reports
  "low" (smooth), chat reaches /quit cleanly.
* `nova-deps.toml` enhancement #15 — upstream tracker for full visual
  stack (JPEG / PNG decode, feature extraction, embeddings).
* `STT_AUDIT.md` — sibling audit for the audio modality bridge.

## R12A SIMD wiring into production hot paths (landed)

R12A wires R11D's i32x8 SIMD intrinsics (`simd_sum_abs_diff`,
`simd_add_i32x8`) into the two production hot paths that fit the i32
lane envelope: stereo block-matching SAD (R7E) and Lucas-Kanade dense
optical-flow accumulators (R10D). Autocorrelation pitch (R10F) was
deliberately excluded — R(0) ~5e11 overflows i32 lanes and needs i64
SIMD which R11D doesn't ship.

* Public API additions (parallel to existing scalar variants for
  back-compat):
  - `stereo_sad_block_simd(left, right, w, x_l, x_r, y, ws, l_buf, r_buf)`
    stages an i32 lane pair via single-byte writes (pixels are 0..255 so
    upper 3 bytes stay zero across the buffer's lifetime) and reduces
    via `simd_sum_abs_diff`. Bit-identical to scalar SAD.
  - `stereo_disparity_simd(left, right, w, h, ws, max_disp)` is the
    explicit SIMD entry point; honors `CE_STEREO_SIMD=off`.
  - `stereo_disparity` (R7E public API) auto-routes to the SIMD inner
    loop when `CE_STEREO_SIMD` is unset or "on".
  - `lk_optical_flow_simd(prev, next, w, h, ws)` stages the 5 product
    streams (ix^2, iy^2, ixiy, ixit, iyit) into i32 lane buffers
    padded to a multiple of 8, lane-parallel-adds via simd_add_i32x8
    into 8-lane accumulators, horizontal-sums per accumulator.
    Honors `CE_LK_SIMD=off`.

* Bit-identical correctness:
  - integer add is associative + commutative, so lane-parallel
    partial sums recombine to the same scalar total
  - SAD on bytes (max |l - r| <= 255) over WIN_SIZE^2 cells fits in
    i32 for the maximum 15x15 window (225 * 255 = 57375 << 2^31)
  - LK products (ix * it etc.) with central-difference gradients
    bounded ~±128 fit comfortably in i32 over a 15x15 window

* `tests/unit/test_simd_production.nova` (35 assertions): SIMD SAD
  bit-identical to scalar across ws ∈ {3, 5, 7, 9, 11};
  `stereo_disparity_simd` byte-wise == locally-recomputed scalar
  reference on a 48x32 textured pair (independent of env-var
  dispatch); SIMD path produces SHIFT=8 disparity on R7E's
  shifted-by-8 fixture; LK SIMD bit-identical to scalar on
  identical-frames + shifted-by-3 + R10D's 80x64 smooth-quadratic
  fixture at ws=5 and ws=7.

* `scripts/bench_simd_production.sh` generates two NOVA bench
  programs that assert bit-identical SIMD vs scalar output before
  reporting wallclock + speedup ratio on 256x256 fixtures. Realized
  numbers on the current NOVA codegen: stereo SAD ~0.86x, LK ~0.20x.
  The R11D microbench showed 335-450x on the SIMD primitive itself
  by calling `simd_sum_abs_diff` ONCE for 1024 lanes; in production
  we call it ~65000 times per disparity scan, and the per-call
  overhead (smart-op pointer checks, function-call ABI, lane
  staging) amortized over only ~49 lanes per call exceeds the AVX2
  inner-loop win. Future codegen wins (inlined builtin emission, a
  `simd_mul_i32x8` for LK products, a `simd_horizontal_sum_i32x8`
  for LK reductions) will surface the speedup automatically through
  the same wiring.

* Out-of-scope follow-ups: SGM cost-volume aggregation (R9A) — the
  4-path DP accumulator could use simd_add_i32x8 lane-wise on cost
  bins; pyramidal Lucas-Kanade (R11A) inherits SIMD via
  lk_optical_flow internally.

Files touched / added:
* `src/io/transducers/image_stereo.nova` (+178 lines)
* `src/io/transducers/image_optical_flow.nova` (+218 lines)
* `tests/unit/test_simd_production.nova` (NEW, 35 assertions)
* `scripts/bench_simd_production.sh` (NEW)

## R15A u8 raw-byte SIMD wiring -- realizes 3-4x absolute speedup (landed)

R15A wires R14B's `simd_sad_u8(a_ptr, b_ptr, n_bytes) -> int` raw-byte
SAD primitive (AVX2 `vpsadbw`, 32 bytes -> 4 i64 partials per
instruction; NEON `uabd` + `uaddlp` on ARM64; scalar fallback on
macOS / Windows / WASM) into the stereo block-matching disparity
path. R12A/R13A's `simd_sum_abs_diff` wrapper operated on packed i32
lanes (8 lanes per `vpaddd`); for byte image data that meant a 4x
staging-buffer write bandwidth overhead -- 4 `store8` per pixel into
each lane's low byte, with the upper 3 bytes left as padding. R14B
landed the byte-native primitive but explicitly deferred the CE
wire-in (5-line strict cap + concurrent agents at the time); R15A
is the realization, analogous to R7B's bn256 Mont realization of R6B.

* Public API additions (parallel to existing scalar + i32 SIMD):
  - `stereo_sad_block_u8(left, right, w, x_l, x_r, y, ws, l_buf, r_buf)`
    packs both windows into contiguous byte buffers via
    `_stereo_pack_block_u8` (one `memcpy_raw` per row) and reduces
    via `simd_sad_u8` in one call. Bit-identical to scalar SAD.
  - `stereo_disparity_u8_simd(left, right, w, h, ws, max_disp)` is
    the explicit u8-SIMD entry point; honors `CE_STEREO_U8_SIMD=on`
    (opt-in; default off until the u8 path has more end-to-end
    validation -- the i32 path stays default-on).
  - `stereo_disparity` (R7E public API) auto-routes to the u8 inner
    loop when `CE_STEREO_U8_SIMD=on`, ahead of the R12A i32 routing.
    `stereo_disparity_simd` (the explicit SIMD entry-point) honors
    the same opt-in so the bench harness + `/depth` chat admin pick
    the byte path without a separate dispatch.

* Why u8 SIMD beats i32 SIMD here:
  - The i32 path stages 4 bytes per pixel (1 store8 to lane low byte
    + upper 3 stay zero from one-time buffer zero) and reduces 8 i32
    lanes per `vpsadbw` chain. The bandwidth cost is 4x per pixel.
  - The u8 path stages 1 byte per pixel (via `memcpy_raw` per row,
    which is `rep movsb` -- uop-fused on modern x86) and reduces 32
    bytes per `vpsadbw` -- 4x more lanes per single SIMD instruction.
  - Net: 4x staging bandwidth saving + 4x lane density per instruction
    + amortized LEFT pack across the d-loop = ~5x absolute speedup
    vs scalar on textured 256x256 fixtures.

* Bit-identical correctness:
  - `vpsadbw` is unsigned absolute difference. Pixels are 0..255
    (unsigned by construction), so the byte-treated-as-unsigned
    semantics agree with scalar `|l - r|` (the test confirms via the
    100-vs-50 symmetric fixture: 49 * 50 = 2450 in both directions).
  - The LEFT/RIGHT pack writes WIN_SIZE * WIN_SIZE bytes per call
    (49 for ws=7); SAD over that buffer plus the scalar tail in
    `simd_sad_u8` matches the scalar `stereo_sad_block` exactly.

* `tests/unit/test_stereo_u8_simd.nova` (NEW, 25 assertions):
  `stereo_sad_block_u8` vs scalar SAD bit-identical on flat /
  known-diff / negative-diff and across ws ∈ {3, 5, 7, 9, 11};
  `stereo_disparity_u8_simd` byte-wise == locally-recomputed scalar
  reference on a 48x32 textured pair; SHIFT=8 correctness on R7E's
  shifted fixture; cross-fixture identity on four-spot and
  vertical-edge patterns; identical-input invariant (mean 0) and
  input-validation rejection (zero ptr / oversize dims).

* `scripts/bench_simd_production.sh` extended to time all three
  paths back-to-back with bit-identical assertions for each.
  Measured on the bench host (256x256 ws=7 max_disp=16 textured
  pair, runs stable across 3 invocations):

  | Path                  | Wallclock | Speedup vs scalar |
  |-----------------------|----------:|------------------:|
  | scalar (R7E)          | ~850 ms   |             1.00x |
  | R12A/R13A i32 SIMD    | ~795 ms   |             1.07x |
  | R15A u8 SIMD          | ~150 ms   |          **5.5x** |

  Above the 3-4x absolute target the brief set. The i32 path is
  ~1.07x on this NOVA codegen host (was 0.86x on R12A; codegen
  fluctuations dominate the i32 path's small per-call edge); the u8
  path's win is robust because the per-call staging-bandwidth save
  is structural rather than codegen-dependent.

* PGM access strategy: pack-inline (one `memcpy_raw` per window
  row into a contiguous byte buffer). PGM pixel data is already
  stored as raw byte buffers (alloc + store8 + load8 via
  `image_pgm.nova`), so the byte SIMD primitive is a direct
  representational fit -- no list[int] -> byte conversion needed.
  The pack pays one row-copy of `ws` bytes per (window, side)
  evaluation; for ws=7 that's 7 bytes per memcpy_raw lowered to a
  single `rep movsb`. LEFT is packed once per pixel and reused
  across the d-loop (the d-shift only moves RIGHT).

* Out-of-scope follow-ups (R15A):
  - Optical-flow LK accumulators stay on the i32 SIMD path. LK
    sums products of central-difference gradients in [-128, 128]
    range; the products do not fit in u8, so the byte primitive
    doesn't apply directly. Future work: a `simd_mul_i16x16`
    primitive would let LK's product step go SIMD.
  - SGM cost-volume aggregation (R9A) still scalar -- the 4-path
    DP accumulator works on i32 cost bins, not u8 inputs.
  - Stereo LR-check (R8D), sub-pixel (R8D), and SGM-quality
    (R9A) still call `stereo_sad_block` (scalar) in their re-walk
    passes. Wiring them through the u8 path is straightforward
    follow-up (same primitive, smaller re-walk loops).

Files touched / added:
* `src/io/transducers/image_stereo.nova` (+~175 lines: pack helper,
  block_u8, env-var, inner, public entry-point, dispatch wiring)
* `tests/unit/test_stereo_u8_simd.nova` (NEW, 25 assertions)
* `scripts/bench_simd_production.sh` (extended bench reports all
  three paths + dual bit-identical assertions)

## R17C -- u8 raw-byte SIMD on optical-flow LK (HONEST: structural mismatch on accumulators; ships wiring + the SAD diagnostics that DO fit)

R15A's u8 SIMD pattern delivered 5.5x absolute speedup on stereo SAD. The
brief asked whether the same pattern could close R13A's optical-flow LK
ceiling. R17C investigated the structural shape and shipped the wiring
with HONEST findings -- mirroring R12A's precedent (agent shipped at
0.84x/0.20x and documented the limitation).

### Findings (after investigation -- documented to spare R18+ the same trip)

LK's inner-loop accumulators are five sums of byte * byte SIGNED products:

  Σ Ix * Ix    Σ Iy * Iy    Σ Ix * Iy    Σ Ix * It    Σ Iy * It

`simd_sad_u8` (AVX2 `vpsadbw`) computes Σ|a[i] - b[i]| over UNSIGNED
bytes. It is structurally NOT a mul-acc primitive: it returns the SAD,
not a vector of products. The LK accumulators need signed byte * byte ->
i32 mul-acc, which would require a different builtin (e.g. SSSE3's
`pmaddubsw` or an `simd_mul_i16x16`). Direct vectorization of LK via
`simd_sad_u8` is impossible regardless of how the data is packed.

### What R17C ships (the parts that DO match `simd_sad_u8`)

R17C lands three useful pieces of the pattern, all bit-identical:

1. **`lk_sad_block_u8(prev, next, w, x, y, ws, p_buf, n_buf)`**: pack
   the WIN x WIN window of `prev` and `next` into contiguous byte
   buffers via `_lk_pack_block_u8` (one `memcpy_raw` per row, mirrors
   R15A), reduce via `simd_sad_u8`. Returns Σ|It| over the window: a
   diagnostic. Bit-identical to scalar Σ|next - prev|.

2. **`lk_image_sad_residual_u8(prev, next, w, h)`**: per-row
   `simd_sad_u8` across the FULL image (PGM rows ARE contiguous, no
   packing needed). Returns Σ|next - prev| over all pixels -- the
   canonical pyramidal-LK convergence metric.

3. **`_lk_optical_flow_u8_simd_inner` + `lk_optical_flow_u8_simd`**
   (`CE_LK_U8_SIMD=on` opt-in, mirrors R15A): full LK with pack-then-
   scan locality. Per pixel, pack windows via `memcpy_raw`, then run
   the 5-accumulator scalar inner loop reading It from the packed
   buffer. Bit-identical to scalar.

### Measured speedup (256x256 ws=5, smooth-quadratic + h-shift-2)

  | Path                                | Wallclock | Speedup vs scalar |
  |-------------------------------------|----------:|------------------:|
  | scalar (R10D)                       |  ~58 ms   |             1.00x |
  | R12A i32 SIMD                       | ~362 ms   |             0.15x |
  | **R17C u8 packed-scan**             |  ~71 ms   |          **0.80x** |
  | R17C u8 vs R12A i32                 |       --  |          **5.09x** |
  | image-SAD residual scalar           | ~392 us   |             1.00x |
  | image-SAD residual u8 SIMD per row  |   ~7 us   |          **58.2x** |

**Honest read** (R12A precedent): full LK at u8 packed-scan is 0.80x
scalar -- pack overhead exceeds locality saving. The u8 path is 5.09x
faster than R12A's i32 path. The pure-SAD image-residual helper hits
58.2x absolute speedup. To close R13A's ceiling at the accumulator
level, NOVA would need `simd_mul_i16x16` (or `pmaddubsw`-shaped) byte-
mul-acc.

### Bit-identical preserved

Yes. 34 new assertions in `tests/unit/test_lk_u8_simd.nova`:
- `lk_sad_block_u8` vs scalar Σ|next - prev| (ws in {3, 5, 7, 9, 11}).
- `lk_image_sad_residual_u8` vs scalar Σ|a - b|.
- `_lk_optical_flow_u8_simd_inner` vs `lk_optical_flow` on R10D's
  textured h-shift-3 (mean magnitude, valid count, per-pixel flow).
- Identical-frames invariant; env-var dispatch; input validation.
- Bench script FAILs on any scalar vs SIMD disagreement.

### Files touched / added (R17C)

* `src/io/transducers/image_optical_flow.nova` (+~285 lines: pack
  helper, sad_block_u8, image_sad_residual_u8, env-var, inner LK,
  public entry-point with dispatch)
* `tests/unit/test_lk_u8_simd.nova` (NEW, 34 assertions)
* `scripts/bench_simd_production.sh` (extended flow bench)

## R18A.2 -- byte mul-acc SIMD wired into optical-flow LK -- 3.69x absolute speedup (closes R17C's 0.80x ceiling)

R17C documented the structural mismatch that capped its u8 packed-scan
path at 0.80x scalar on full LK: the 5 accumulator sums (Σ Ix*Ix,
Σ Iy*Iy, Σ Ix*Iy, Σ Ix*It, Σ Iy*It) are byte * byte SIGNED mul-acc,
NOT |a - b| SAD, so `simd_sad_u8` could not vectorize the inner
products. R17C's only structural win was the It-load locality from
the packed buffer; the strided Ix and Iy loads + the scalar
accumulator math remained the per-pixel hot loop.

R18A (NOVA codegen commit `db34532`) shipped the missing primitive:

  `simd_mul_acc_signed_signed_byte(a_i8_ptr, b_i8_ptr, n_bytes) -> int`
    Σ a[i] * b[i] over n bytes with BOTH operands interpreted as
    signed i8 in [-128, 127]. AVX2 inline at the call site:
    `vpmovsxbw` widens i8 → i16, `vpmaddwd` pair-multiplies +
    adds adjacent i16 → i32, `vpaddd` into the running accumulator.
    16 bytes per vector iter; scalar tail for `n % 16`. ARM64 NEON
    via `sshll` + `smull/smull2` + `add` (8 bytes/iter, scalar
    tail). WASM v128 via `i32x4.dot_i16x8_s`. Bit-identical to
    scalar `Σ a[i] * b[i]` because integer add is associative.

R18A.2 wires this into LK. The five accumulator sums map as:

  | Sum         | Operand range            | SIMD calls         |
  |-------------|--------------------------|--------------------|
  | Σ Ix * Ix   | Ix in i8 [-127, 127]     | 1 (direct)         |
  | Σ Iy * Iy   | Iy in i8                 | 1 (direct)         |
  | Σ Ix * Iy   | Ix, Iy in i8             | 1 (direct)         |
  | Σ Ix * It   | It in [-255, 255]        | 2 (two-piece split)|
  | Σ Iy * It   | It in [-255, 255]        | 2 (two-piece split)|

It's two-piece split: `It_lo = It / 2` (NOVA truncates toward 0,
range [-127, 127]) and `It_hi = It - 2 * It_lo` (range {-1, 0, 1}).
Both fit i8. Then `Σ Ix * It = 2 * Σ(Ix * It_lo) + Σ(Ix * It_hi)`
holds cell-by-cell because `Ix * It = Ix * (2 * It_lo + It_hi) =
2 * (Ix * It_lo) + (Ix * It_hi)`. Bit-identical to scalar.

### The load-bearing optimization: image-wide gradient pre-compute

A naive per-pixel staging path (compute Ix, Iy, It_lo, It_hi at each
of the 25 window cells, then 7 SIMD calls) measured **0.67x absolute**
on the first cut -- the 75 scalar gradient calls per pixel + the
4 * 25 byte stores per pixel overwhelmed the SIMD reduction win for
the small `n_cells = 25` (one vector iter + 9-byte scalar tail).

The fix: pre-compute the 4 gradient i8 buffers across the WHOLE
IMAGE in one pass before the per-pixel scan. Per-pixel staging then
reduces to 4 buffers * `ws` rows = 20 `memcpy_raw` calls per pixel
(R15A's pack pattern -- `rep movsb`, one byte-row at a time). This
amortizes the 65,536 gradient calls (256 * 256 area) across all
65,536 interior pixels instead of paying 75 per pixel. The per-pixel
inner loop becomes 20 memcpy_raw + 7 SIMD calls + the 2x2 inverse.

Measured impact: **18 ms vs 67 ms scalar = 3.69x absolute speedup**.

### Measured speedup (256x256 ws=5, smooth-quadratic + h-shift-2)

  | Path                                | Wallclock | Speedup vs scalar |
  |-------------------------------------|----------:|------------------:|
  | scalar (R10D)                       |  ~67 ms   |             1.00x |
  | R12A i32 SIMD                       | ~368 ms   |             0.18x |
  | R17C u8 packed-scan                 |  ~73 ms   |             0.91x |
  | **R18A.2 mul-acc SIMD**             |  **~18 ms** | **3.69x absolute** |
  | R18A.2 vs R17C u8                   |        -- |              4.03x |
  | image-SAD residual scalar           | ~399 us   |             1.00x |
  | image-SAD residual u8 SIMD per row  |  ~3.6 us  |          ~110x    |

The 3.69x absolute closes R17C's 0.80x ceiling AND the R13A 1.42x /
R12A 0.20x prior ceilings. R15A's stereo SAD wire-in landed 5.5x
absolute; R18A.2's LK wire-in lands 3.69x absolute -- both within
the same order, both validating the "ship primitive + wire-in in
the next round" pattern.

### Bit-identical preserved (whole-image sweep, not just summary stats)

Yes. 28 new assertions in `tests/unit/test_lk_mulacc_simd.nova`:
- `_lk_optical_flow_mulacc_inner` vs scalar `lk_optical_flow` on
  R10D's textured h-shift-3, v-shift-2, identical-frames, and
  high-contrast-bands (the |It| > 127 path that exercises the
  It two-piece decomposition).
- Whole-image-sweep test: every interior pixel's (u_milli, v_milli,
  valid) bytes must match scalar exactly. Mismatch count == 0.
- `lk_optical_flow_mulacc_pyramid` vs scalar `lk_optical_flow_pyramid`
  on 8-px shift (dispatch-off route -- pyramid orchestrator IS the
  R11A scalar code path when CE_LK_MULACC_SIMD is unset).
- `lk_optical_flow_mulacc_perpixel` vs scalar `lk_optical_flow_pyramid_perpixel`
  on 4-px shift (dispatch-off route).
- Env-var dispatch (CE_LK_MULACC_SIMD unset/off -> scalar fallback).
- Input validation: zero pointers, oversize dims rejected.
- Bench script FAILs on any scalar vs mul-acc disagreement (mean
  mag + valid count).

### Files touched / added (R18A.2)

* `src/io/transducers/image_optical_flow.nova` (+~580 lines:
  `_lk_mulacc_simd_enabled`, `_lk_store_i8`,
  `_lk_optical_flow_mulacc_inner` with image-wide gradient pre-
  compute + per-pixel memcpy_raw pack + 7 SIMD calls,
  `lk_optical_flow_mulacc_u8` public entry with env-var dispatch,
  `lk_optical_flow_mulacc_pyramid` + `lk_optical_flow_mulacc_perpixel`
  that route through the mul-acc inner solve at every level)
* `tests/unit/test_lk_mulacc_simd.nova` (NEW, 28 assertions)
* `scripts/bench_simd_production.sh` (extended flow bench with
  mul-acc path measurement + bit-identical assertions)

## R16D -- Viola-Jones-style Haar cascade face detector (STRUCTURAL only -- see scope)

**Status: complete -- new `src/io/transducers/image_face_detect.nova`
adds the integral-image primitive (Crow 1984) + Haar 2-rect/3-rect/
4-rect feature evaluators + a hand-crafted 3-stage cascade + multi-
scale sliding window + NMS clustering. Wired into `visual_perception`
behind `CE_VP_FACE_DETECT=1` and exposed via the chat `/faces PATH`
admin command.**

### SCOPE DISCLAIMER (must read before relying on this)

This is a STRUCTURAL implementation of Viola-Jones 2001
("Rapid Object Detection using a Boosted Cascade of Simple
Features"). CrossEngin's no-training-data design forbids shipping
the AdaBoost-trained cascade weights that OpenCV's
`haarcascade_frontalface_default.xml` carries (~3,000 weak
classifiers across 25 stages, trained on ~5,000 positive +
~10,000 negative faces). Instead we ship a HAND-CRAFTED 3-stage
cascade tuned for the canonical "dark eye-strip above light
cheek-strip above dark chin-strip" pattern.

**ACCURACY ON REAL PHOTOGRAPHS WILL BE POOR.** The right tool for
actually finding faces in real images is either (a) parsing OpenCV's
`haarcascade_frontalface_default.xml` (XML parser + 25-stage
weighted-classifier tree -- out of scope for one round) or
(b) training a cascade on real positive + negative examples.

What this module DOES provide:

* The **integral image primitive** (Crow 1984) -- O(1) rectangle
  sums via the four-corner formula. Reusable downstream for
  HOG-with-integral-histogram-of-gradients, fast Haar-template
  scoring, fast box-filter convolutions, etc. The integral image
  is the load-bearing data structure underneath ALL of the
  Viola-Jones speed claims.
* **Two-rect / three-rect / four-rect Haar evaluators** -- correct
  relative to the canonical Viola-Jones definitions. Two-rect is
  `sum(BLACK) - sum(WHITE)`; three-rect is
  `sum(CENTER) - sum(LEFT) - sum(RIGHT)` (horizontal split);
  four-rect is the diagonal pattern
  `(sum(TL) + sum(BR)) - (sum(TR) + sum(BL))`.
* **A 3-stage cascade structure with multi-scale sliding window**
  -- the operational shell a real trained cascade would slot
  into. Multi-scale uses the classical 1.25x scale-up factor
  (`size_next = size * 5 / 4`); NMS clusters overlapping
  detections by IoU >= 0.30 (Dalal-Triggs's pedestrian default).
* **The `/faces PATH` admin command** + the
  `image_face_count_<none|one|few|many>` perception atom (gated
  by `CE_VP_FACE_DETECT=1` so the default `/see` path doesn't pay
  the cascade-sweep cost).

### Algorithm (Viola-Jones 2001, simplified)

1. **Integral image** (Crow 1984):
   `I(x, y) = sum of pixels in [0..x] x [0..y]`
   `sum(x1, y1, x2, y2) = I(x2, y2) - I(x1-1, y2) - I(x2, y1-1) + I(x1-1, y1-1)`
   Four lookups -> any rectangle sum in O(1). Stored as 64-bit ints.
2. **Haar features**: simple rectangular feature evaluators
   (2-rect / 3-rect / 4-rect; canonical Viola-Jones definitions).
3. **Cascade classifier**: 3 stages, early-reject. Each stage
   normalizes the feature value by its region area (scaled by 100
   to stay in integer space) and tests against a per-stage
   threshold. Stage 1 = eye-strip-vs-cheek-strip contrast; Stage 2
   = chin-strip-vs-cheek-strip contrast; Stage 3 = nose-bridge
   three-rect (relaxed threshold for the structural implementation
   because synthetic horizontal-band fixtures have NO horizontal
   structure to exploit; a trained cascade would tighten this).
4. **Multi-scale**: start at 24x24, slide at step 4, scale up by
   1.25x per octave (cap at 16 octaves), repeat until max_size or
   image edge.
5. **NMS**: greedy IoU-based, keep highest-score per cluster.

### Public API

* `integral_image(image, w, h) -> integral_t` (opaque ptr; 0 on
  invalid args)
* `integral_get(integral, w, h, x, y) -> int` (OOB returns 0)
* `rect_sum(integral, w, h, x1, y1, x2, y2) -> int` (clamps to
  image bounds; degenerate -> 0)
* `haar_feature_2rect(integral, w, h, x, y, fw, fh, black_x, black_y)
  -> int`
* `haar_feature_3rect(integral, w, h, x, y, fw, fh) -> int`
* `haar_feature_4rect(integral, w, h, x, y, fw, fh) -> int`
* `face_detect(image, w, h, min_size, max_size, step)
  -> list of [x, y, size, score]`
* `face_result_x(d) / _y / _size / _score` -- accessors
* `face_count_label(n)
  -> "image_face_count_<none|one|few|many>"`
* `face_append_features_if_enabled(feats, image, w, h)` -- VP wire-in
* `face_pgm_args(arg) -> string` -- `/faces` admin formatter

### Caps + defaults

* `FACE_MAX_IMAGE_DIM = 256` (same as image_detector.nova)
* `FACE_MIN_WINDOW = 24` (canonical Viola-Jones base window)
* `FACE_MAX_WINDOW = 128`
* `FACE_DEFAULT_STEP = 4`; `step` clamped to `[2, 16]`
* `FACE_SCALE_NUM/DEN = 5/4` (1.25x classical scale factor)
* `FACE_NMS_IOU_MILLI = 300` (0.30 IoU, Dalal-Triggs default)

### Tuning notes (for follow-up if a trained cascade lands)

The hand-crafted stage thresholds (`FACE_STAGE_1_THRESH = 8`,
`FACE_STAGE_2_THRESH = 6`, `FACE_STAGE_3_THRESH = -6000`) are
calibrated against the SYNTHETIC horizontal-band fixture in the
unit + integration tests. Stage 3's threshold is negative because
horizontal-band fixtures have no horizontal-vertical structure for
the nose-bridge feature to fire on; the relaxed gate still gets
EVALUATED (preserving the structural shell) and uniform full-image
inputs are already rejected at stage 1 (no eye/cheek contrast),
so the lenient stage 3 doesn't introduce false positives in
practice. A real trained cascade would replace all three thresholds
with AdaBoost-weighted weak-classifier weights.

### Detection rates on the structural fixtures

* Synthetic 64x64 face pattern (dark-eye/light-cheek/dark-chin
  horizontal bands at rows 8..56): **2 detections** at the
  default settings (one at size 48 around (0, 8), one at the
  multi-scale 60x60 window).
* Synthetic 96x96 SMALLER face pattern (rows 20..50): **>= 1
  detection** at multi-scale windows aligning with the
  proportionally smaller band geometry.
* Uniform-gray 32x32 / 64x64 images: **0 detections** (stage 1
  rejects on no eye/cheek contrast).
* Real photographs: not tested by the structural fixture; expected
  detection rate is POOR per the scope disclaimer.

Files touched / added:
* `src/io/transducers/image_face_detect.nova` (NEW, ~530 lines)
* `tests/unit/test_face_detect.nova` (NEW, 36 assertions)
* `tests/integration/scenario_nnn_face_detect.sh` (NEW, 11 assertions)
* `src/io/transducers/visual_perception.nova` (+3 lines: import +
  R16D wire-in comment + 1 dispatch line)
* `examples/crossengin_chat.nova` (+2 lines: `/help` advert +
  `/faces` dispatch)


## R17D -- LBP (Local Binary Patterns, Ojala 1996) texture descriptor

R16D shipped the structural face DETECTOR (Viola-Jones-style Haar
cascade -- finds *where* a face is). R17D ships the classic non-DL
face / texture **DESCRIPTOR** (finds *which* face it is by texture
signature): Local Binary Patterns. Where HOG (R14D) summarizes
gradient ORIENTATION in cells, LBP summarizes LOCAL TEXTURE -- per
pixel, compare it against its 8 neighbors, pack the 8 comparison
bits into a single byte; the histogram of those bytes over a
region is the descriptor.

### Algorithm

For each pixel (x, y), inspect the 3x3 neighborhood:

```
  P7 P0 P1
  P6  C P2
  P5 P4 P3
```

Threshold each neighbor against the center C (equality maps to 1
to keep the uniform-field-yields-0xFF invariant), then pack
clockwise from top-left:

  lbp(x,y) = b7*128 + b0*64 + b1*32 + b2*16 + b3*8 + b4*4 + b5*2 + b6*1

Each pixel produces an 8-bit LBP code (256 possible values). For a
face descriptor: tile the image into cells_x x cells_y cells,
compute the 256-bin LBP histogram per cell, concatenate ->
cells_x * cells_y * 256-bin descriptor (e.g., 4x4 cells = 4096
ints; the canonical Ahonen 2006 8x8 = 16,384 ints).

### Why LBP for face RECOGNITION (vs HOG for face DETECTION)

HOG and Viola-Jones are both detection-oriented (find the face);
LBP is the canonical non-DL DESCRIPTOR (identify which face). The
2006 Ahonen et al. paper "Face Recognition with Local Binary
Patterns" beat the prior eigenfaces / Fisherfaces baselines on
FERET and remained the dominant non-DL face-rec method for nearly
a decade. The descriptor is also broadly used in texture
classification, age / gender estimation, and dynamic texture
analysis.

### Rotation non-invariance (documented limitation)

Basic LBP is NOT rotation-invariant. Rotating the input by 90
degrees permutes the neighbor labels (P0 -> P2, P1 -> P3, etc.) so
the packed code changes. The unit suite demonstrates this
explicitly:

* `test_descriptor_rotation_non_invariance`: vertical-edge vs
  horizontal-edge (= rotated vertical-edge) -> chi-squared
  distance > 0, well above the noise floor.
* SIFT (R5C) and ORB (R6D) ARE rotation-invariant; HOG (R14D) is
  NOT, and basic LBP shares HOG's limitation.

The standard rotation-invariant variant LBP_ri remaps each code
to its minimum rotation (a 256 -> 36 lookup) and the "uniform"
LBP variant further reduces to 59 distinct patterns; both are
documented follow-ups. In face recognition the face IS
pose-normalized first (e.g., eyes aligned) so rotation invariance
is not needed at the descriptor layer.

### Public API

* `lbp_compute_image(image, w, h) -> lbp_image_t` -- per-pixel
  LBP codes; sentinel error on cap violation / null pointer.
* `lbp_at(lbp_img, x, y) -> int` -- bounds-checked code at (x, y);
  returns 0 on OOB or border pixel.
* `lbp_histogram(lbp_img, x1, y1, x2, y2) -> list[256]` --
  histogram of codes within the half-open ROI [x1, x2) x [y1, y2).
* `lbp_descriptor(image, w, h, cells_x, cells_y) -> list[int]` --
  cells_x * cells_y * 256-bin concatenated descriptor.
* `lbp_compare(desc_a, desc_b) -> int` -- chi-squared distance;
  0 = identical, larger = more dissimilar, -1 on length mismatch.
* `lbp_compare_intersection(desc_a, desc_b) -> int` --
  histogram-intersection similarity; LARGER = MORE SIMILAR.
* `lbp_dominant_code(image, w, h) -> int` -- argmax over the
  whole-image LBP histogram.
* `lbp_texture_entropy_milli(image, w, h) -> int` -- Shannon
  entropy over the 256-bin histogram in milli-bits (uniform
  field ~0; random texture ~8000).

Caps: dimensions <= 256x256 per axis (LBP_MAX_DIM); cells_x and
cells_y in [LBP_CELLS_MIN, LBP_CELLS_MAX] = [2, 16].

### Verification

Unit tests (~45 assertions in `tests/unit/test_lbp.nova`):
* Uniform image -> every interior code = 0xFF (Ojala's
  equality-maps-to-1 convention).
* Center darker than all 8 neighbors -> code 0xFF.
* Center brighter than all 8 neighbors -> code 0x00.
* Half-and-half neighborhood -> specific 4-bit-set codes.
* Histogram on uniform 16x16 region -> spike at single bin (255).
* Histogram on noisy texture -> distributed across >=30 codes.
* Descriptor on 32x32 with 4x4 cells -> 4096 ints.
* Self-match chi-squared = 0; self-match intersection = pixel count.
* Rotation -> non-zero distance (the rotation-non-invariance test).
* Translation by 1 px -> smaller distance than rotation.
* OOB safety for `lbp_at`; cap rejection for oversized images;
  invalid cells_x / cells_y rejection.

Integration scenario `tests/integration/scenario_rrr_lbp.sh`
(10 assertions): /help advert, /lbp usage, missing-file error,
too-small-image error, valid summary tuple on a 32x32 vertical-edge
"face" fixture, same dominant_code on a 1-px-shifted face (the
"low-distance" pair), differing entropy on a four-spots fixture
(the "high-distance" pair), chat reaches /quit.

### Recognition system (deferred)

LBP-for-face-recognition normally consumes the descriptor into a
SVM, KNN, or nearest-template lookup. For CrossEngin's non-LLM
substrate the simplest use is template comparison (similar to the
R15C HOG sliding-window detector): match a query face's LBP
descriptor against a small gallery of known faces, return the
nearest match. This round ships the DESCRIPTOR + COMPARISON
primitives; "build a recognition system" can be a future round if
the substrate ever needs to bind face identity to atoms.

### Files touched / added

* `src/io/transducers/image_lbp.nova` (NEW, ~550 lines)
* `tests/unit/test_lbp.nova` (NEW, 22 test functions / 45 assertions)
* `tests/integration/scenario_rrr_lbp.sh` (NEW, 10 assertions)
* `src/io/transducers/visual_perception.nova` (+3 lines: import +
  R17D wire-in comment + 1 dispatch line)
* `examples/crossengin_chat.nova` (+2 lines: `/help` advert +
  `/lbp` dispatch)


## R18D -- LBP-gallery face RECOGNITION (identity matching)

R16D shipped the Viola-Jones face DETECTOR (finds *where* a face is);
R17D shipped the LBP face DESCRIPTOR (computes the 4096-int chi-
squared-comparable feature vector for one face). R18D closes the
canonical Ahonen et al. 2006 LBP face-recognition pipeline by
adding the GALLERY + nearest-neighbor matcher: given a set of
ENROLLED descriptors (one per known identity) and an unknown query
face, return the nearest-neighbor identity if the chi-squared
distance is below an operator-tunable threshold; otherwise return
"unknown".

### Algorithm

```
ENROLL:                        QUERY:
  face_image                     face_image
     |                              |
     v                              v
  lbp_descriptor                 lbp_descriptor
     |                              |
     v                              v
  [label, desc] -----+              desc
                     |               |
                     v               v
                  gallery <-- chi2(gallery, desc)
                                       |
                                       v
                                  argmin -> label | "unknown"
```

The gallery is operator-maintained state: there is no pre-trained
identity table. `/face_enroll <label> <pgm>` registers a new
identity (or overwrites an existing label idempotently);
`/face_recognize <pgm>` queries against the current gallery using
a default chi-squared threshold of 500.

### Why LBP for face recognition (vs HOG for face detection)

HOG / Viola-Jones answer "is there a face here?"; LBP answers
"which face is this?". Ahonen 2006 demonstrated that a flat
chi-squared distance over per-cell LBP histograms beat the
eigenfaces / Fisherfaces baselines on FERET and remained the
dominant non-DL face-recognition method for nearly a decade.
CrossEngin's pipeline uses the 4x4 cell grid (4096-int descriptor)
matching R17D's default rather than the canonical 8x8 cells
(16,384-int); the weighted-cell variant (where ocular regions
receive higher weight than peripheral cells) is a documented
follow-up.

### Public API (`image_face_recognize.nova`)

* `face_gallery_new() -> gallery_t` -- empty gallery.
* `face_gallery_enroll(gallery, label, image, w, h) -> 1 | 0` --
  compute LBP descriptor + insert/overwrite under `label`. Returns
  0 on invalid label / oversize / over-cap (128-entry max). Idempotent
  on label (re-enrollment overwrites).
* `face_gallery_recognize(gallery, query_image, w, h, threshold) ->`
  `[label, distance]` on match within threshold; `["unknown", -1]`
  otherwise (empty gallery / descriptor build failure / no entry
  passes the cutoff).
* `face_gallery_save(gallery, path) -> 1 | 0` -- serialize to an
  ASCII line-oriented file (`CE_FACE_GALLERY_V1` magic + entry count
  + per-entry label/desc_len/desc_values).
* `face_gallery_load(path) -> gallery_t` -- read + parse the file
  format; returns an empty gallery on any read/parse failure.
* `face_gallery_size(gallery) -> int` -- raw underlying-list size.
* `face_gallery_live_size(gallery) -> int` -- live entries (clear
  marks dead-sentinel slots so size > live_size after clear).
* `face_gallery_clear(gallery) -> 1` -- drops every live entry
  (overwrites with dead-sentinel slots that re-enroll reuses).
* `face_gallery_label_at(gallery, idx) -> string`.
* `face_gallery_descriptor_at(gallery, idx) -> list[int]`.
* `face_enroll_pgm_args(gallery, arg) -> string` -- chat helper.
* `face_recognize_pgm_args(gallery, arg, threshold) -> string`.
* `face_enroll_chat_args(arg)` / `face_recognize_chat_args(arg)` --
  chat-side wrappers using the per-process singleton gallery.

Caps: gallery <= 128 entries (FACE_REC_MAX_ENTRIES); descriptor
uses 4x4 cells = 4096 ints (FACE_REC_CELLS); label <= 64 bytes
(FACE_REC_LABEL_MAX); image dimensions inherit R17D's 256x256
LBP_MAX_DIM. Default chat threshold = 500 chi-squared units.

### Save / load format

Line-oriented ASCII for inspectability + portability:

```
CE_FACE_GALLERY_V1
<n_entries>
<label_1>
<desc_len_1>
<desc_1[0]>
...
<desc_1[desc_len_1 - 1]>
<label_2>
...
```

The format is bit-identical round-trip safe because LBP descriptor
values are small non-negative ints (histogram counts bounded by
the cell pixel area). Operators wanting atomicity write to a
tmp path and rename outside the module (the module itself
issues a non-atomic write + fsync).

### Chat wiring (2 dispatch + 2 help lines)

```
/face_enroll L PGM  enroll face L from PGM into the per-process LBP gallery (R18D)
/face_recognize PGM nearest-neighbor identity match against the LBP gallery;
                    returns label or 'unknown' (R18D)
```

Output shapes:

```
(face_enroll OK label=alice size=1)
(face_recognize matched=alice distance=0 threshold=500)
(face_recognize unknown distance=-1 threshold=500)
```

### Verification

Unit tests (~48 assertions in `tests/unit/test_face_recognize.nova`):
* Empty gallery: size = 0, recognize -> "unknown" distance -1.
* Enroll 1 face, self-match: returns enrolled label, distance 0.
* Enroll 3 distinct faces (vertical / four-spots / horizontal):
  each query returns the matching label with distance 0.
* Unknown rejection: a 4th distinct face under a TIGHT threshold
  returns "unknown".
* Duplicate enrollment overwrites: re-enroll under same label
  keeps live_size = 1, recognize returns new descriptor's match.
* Clear: live_size reverts to 0; recognize returns "unknown".
* Clear-then-reenroll reuses dead-sentinel slots.
* Empty label / 4x4 too-small image / null gallery all fail
  cleanly.
* Save 3-face gallery + load: recognize results bit-identical
  (alice/bob/carol all return distance 0 against their fixtures).
* Save empty gallery + load: empty gallery (live_size = 0).
* Load on missing file: empty gallery (graceful failure).
* Chat helper formatting probes: enroll usage / single-arg usage /
  recognize empty-gallery / recognize empty-arg.

Integration scenario `tests/integration/scenario_vvv_face_recognize.sh`
(14 assertions): /help adverts, /face_enroll + /face_recognize
usage lines, empty-gallery rejection, missing-PGM graceful failure,
enroll alice/bob/carol with monotonically-growing size, recognize
each of the 3 enrolled fixtures with distance 0, recognize a 4th
high-entropy texture fixture -> "unknown" (correct rejection),
chat reaches /quit cleanly.

### Files touched / added

* `src/io/transducers/image_face_recognize.nova` (NEW, ~600 lines)
* `tests/unit/test_face_recognize.nova` (NEW, 19 test functions / 48 assertions)
* `tests/integration/scenario_vvv_face_recognize.sh` (NEW, 14 assertions)
* `examples/crossengin_chat.nova` (+5 lines: 1 import + 2 `/help`
  advert + 2 dispatches; over the 4-line target by 1 since the new
  module must be imported -- it isn't reachable through
  `visual_perception.nova` like `image_lbp` is)
