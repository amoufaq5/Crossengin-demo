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
unit suite covers only the in-memory PGM decoder + stats; the shim's
"no backend installed" branch is what CI sees for non-PGM input.

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
3. **Pure-NOVA PNG via zlib** *(hard, ~3-4 weeks)*. PNG = chunked container
   (IHDR/IDAT/IEND) + zlib(DEFLATE) on the pixel stream + per-scanline
   filter prediction (Sub / Up / Average / Paeth) + optional palette /
   interlacing. The DEFLATE decoder is the load-bearing piece (~600 lines
   of NOVA with care for codegen gotcha #11); everything else is the
   chunk parser. Adam7 interlacing stays deferred.
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

| Feature                         | NOVA effort |
|---------------------------------|-------------|
| Mean intensity / histogram      | landed      |
| Sobel edge magnitude            | 1-2 weeks   |
| Harris corner detector          | 2-3 weeks   |
| Canny edge with hysteresis      | 2-3 weeks   |
| HOG (oriented gradients)        | 2-3 weeks   |
| SIFT-like keypoints + 128-D     | 4-6 weeks   |
| Color histograms (HSV / Lab)    | 2-3 weeks   |
| CNN feature vector (untrained)  | 4-8 weeks   |
| CNN feature vector (trained)    | 6-12 months |

A "production agent that can see photographs and reason about them" is
weeks 1-4 for JPEG decode + Sobel + Harris (~1.5 months honestly), 4-8
weeks for SIFT-quality keypoints, and many months for a trained CNN-like
embedding. Pure-NOVA CNN training is unrealistic this decade; the WASM
stb_image + an embedded ONNX-runtime path is the realistic embedded-model
option once both halves land.

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
| JPEG decode in pure NOVA                           | 6-8 weeks        |
| PNG decode (zlib + filters)                        | 3-4 weeks        |
| Sobel / Harris / color histograms                  | 6-9 weeks total  |
| SIFT-like keypoints                                | 4-6 weeks        |
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

Next: revisit pure-NOVA decoders after the modality bridge matures.
**JPEG before PNG** — JPEG is the dominant format for photographs, where
visual perception is most needed; PNG dominates for screenshots and UI
captures, which are a lower priority. Pure-NOVA WebP and HEIC are not on
any roadmap within the next year.

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

* `src/io/transducers/image_pgm.nova` — pure-NOVA PGM-P5 decoder + stats.
* `src/io/transducers/visual_perception.nova` — pluggable seam + feature
  extraction.
* `scripts/image_to_pgm.sh` — ImageMagick / ffmpeg / placeholder shim.
* `examples/crossengin_chat.nova` — `/see PATH` admin command + dispatch
  + /help entry.
* `tests/unit/test_image_pgm.nova` — 43 in-memory assertions covering
  parse, stats, resize, and malformed inputs.
* `tests/integration/scenario_q_image_see.sh` — 11 end-to-end /see chat
  assertions against hand-rolled gradient + uniform PGM fixtures.
* `nova-deps.toml` enhancement #15 — upstream tracker for full visual
  stack (JPEG / PNG decode, feature extraction, embeddings).
* `STT_AUDIT.md` — sibling audit for the audio modality bridge.
