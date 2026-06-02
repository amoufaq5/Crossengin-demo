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
| SIFT-like 128-D descriptor       | DONE (P3.3 cont. v2)|
| ORB (FAST + rBRIEF, patent-free) | DONE (P3.3 cont. v3)|
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

