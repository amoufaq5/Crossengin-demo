# JPEG_AUDIT — what a pure-NOVA JPEG decoder would take

Status: **structural half landed (P3.1.JPEG); entropy decode + IDCT
deferred ~3-4 weeks.** This document mirrors `IMAGE_AUDIT.md` /
`STT_AUDIT.md` / `VIDEO_AUDIT.md` -- the realistic path, not a promise.
The first plank lands in this session: a pure-NOVA segment-marker
parser + DQT / SOF0 / DHT table extractor in
`src/io/transducers/jpeg_decode.nova`. The dispatch hook in
`src/io/transducers/visual_perception.nova` routes `*.jpg` / `*.jpeg`
paths to the JPEG backend; the dimensions surface to the operator and
the perception path receives an `image_jpeg_header_only` atom + the
size bucket. Pixel-level decoding is the next 3-4 weeks of work
documented below.

## Why baseline grayscale is the right MVP target

The original JPEG specification (ITU-T T.81, 1992) is a four-mode
family:
1. **Baseline sequential DCT** (SOF0): 8-bit precision, Huffman entropy
   coding, sequential block-by-block decoding. The MVP target.
2. **Extended sequential DCT** (SOF1/SOF3): 12-bit precision OR
   arithmetic coding. Both deferred.
3. **Progressive DCT** (SOF2): multiple scans of partial DCT data with
   spectral selection + successive approximation. Each scan refines
   the same blocks; rendering requires accumulating across scans.
   Deferred (significant additional complexity over baseline).
4. **Lossless** (SOF3): predictor-based, no DCT at all. A separate
   pipeline; rarely used in practice. Deferred.

The vast majority of "photograph" JPEGs in the wild are mode 1: baseline
sequential, 8-bit, Huffman, with three components (Y, Cb, Cr) and
4:2:0 chroma subsampling. The grayscale subset (one component, Y only,
4:4:4 sampling) is the easiest end-to-end target -- it ships the entire
decoder pipeline (Huffman, de-quant, IDCT, block assembly) without the
two extra complications color brings (YCbCr -> RGB color-space
conversion, upsampling the subsampled Cb/Cr planes back to the Y plane's
resolution). Once grayscale lands the YCbCr -> RGB step is a tight
~50-line addition; the subsampling upsample step is another ~100 lines
(bilinear is fine).

Skipping color in the MVP also skips three sources of subtle bugs:
the level-shift, the 5-coefficient color matrix, and the four
sampling-factor permutations (4:4:4 / 4:2:2 / 4:2:0 / 4:1:1) each
requiring different MCU geometry. A pure-grayscale baseline MVP gets
the framework right; color is an incremental layer.

## What this session ships

`src/io/transducers/jpeg_decode.nova`:
- **`jpeg_parse_segments(bytes_ptr, len) -> list of [marker, offset, length]`** --
  Walk a JPEG bytestream marker by marker. Handles SOI (no length),
  EOI (no length, ends walk), RST0..RST7 (no length), filler 0xFF
  runs, length-prefixed segments (APP0/APP1/.../COM/DQT/SOF0/DHT/SOS),
  and the SOS-terminates-iteration convention (entropy data follows
  SOS and is not walked further).
- **`jpeg_parse_dqt(bytes_ptr, segment_off, segment_len) -> list of
  [precision, table_id, list_of_64_ints]`** -- Each DQT segment can
  carry multiple quantization tables back-to-back. Pq=0 is 8-bit
  (64 byte values); Pq=1 is 16-bit (128 byte values, big-endian per
  entry). Always 64 logical entries per table in zig-zag order.
- **`jpeg_parse_sof0(bytes_ptr, segment_off, segment_len) -> [precision,
  height, width, n_components, components_list, error_msg]`** --
  Validates precision == 8 (baseline only), dimensions in (0, 1024],
  n_components in [1, 4]. Component records carry id, H/V sampling
  factors, and quantization table id.
- **`jpeg_parse_dht(bytes_ptr, segment_off, segment_len) -> list of
  [table_class, table_id, length_counts, symbols]`** -- A DHT segment
  can carry multiple Huffman tables. `length_counts` is the 16-element
  BITS array (codes of each length 1..16); `symbols` is the HUFFVAL
  list (length = sum of BITS).
- **`jpeg_decode_grayscale(path) -> [width, height, "", error_msg]`** --
  Opens the file, validates SOI, walks segments, finds SOF0, validates
  the JPEG is baseline grayscale, and returns the dimensions WITHOUT
  decoding pixels. The error_msg slot carries the documented
  "entropy decode + IDCT not yet implemented; see JPEG_AUDIT.md" string
  with the parsed dimensions embedded, so the perception path can
  still surface the width / height and a clear "feature is coming"
  message.

`scripts/gen_test_jpeg.py`:
- If Pillow is installed: encodes a deterministic 16x16 grayscale
  gradient via `Image.frombytes("L", ...).save(..., quality=80)` so
  libjpeg produces a real baseline-sequential JPEG with DC + AC
  Huffman tables in DHT.
- If Pillow is NOT installed: hand-rolls a minimal SOI+APP0+DQT+SOF0+
  DHT+SOS+EOI envelope around two zero entropy bytes. Not a decodable
  JPEG (a real decoder will choke on the entropy data) but enough
  structure for the pure-NOVA parser to walk end-to-end.

`src/io/transducers/visual_perception.nova`:
- New `VP_DECODER_JPEG` constant (id=4); registered as "jpeg" in
  `vp_seam_new()`.
- `vp_default_decoder()` accepts `CE_VP_DECODER=jpeg` (or `=jpg`) and
  returns the JPEG constant.
- `_vp_decode_jpeg(seam, path)` calls `jpeg_decode_grayscale`,
  emits the `image_jpeg_header_only` + dimension-bucket feature atoms,
  surfaces the gap diagnostic in `vp_result_error`, and writes the
  operator-readable summary "image: jpeg WxH header parsed (pixel
  decode pending; see JPEG_AUDIT.md)" to `vp_seam_last_summary`.
- `.jpg` / `.jpeg` path-extension routing dispatches to the JPEG
  decoder even when the seam's default is PGM.

## What this session does NOT ship (the next 3-4 weeks)

The decode pipeline downstream of the header parse:

| Step                            | Effort     | What it does |
|---------------------------------|------------|--------------|
| Huffman entropy decoder         | ~1 week    | Build canonical Huffman trees from BITS+HUFFVAL; bit-level reader; resolve DC differential coding + AC RLE/EOB markers. |
| De-quantize + inverse zig-zag   | ~3 days    | Multiply each of 64 coefficients by the corresponding quant-table entry; un-zig-zag from JPEG's serpentine scan order to the 8x8 row-major layout. |
| 8x8 IDCT (inverse DCT)          | ~1 week    | Apply the 64-coefficient inverse DCT to each 8x8 block. The classic AAN (Arai-Agui-Nakajima) factorization needs only 5 multiplies per 1-D pass, 64 multiplies total per block. Fixed-point milli-arithmetic. |
| Block-row assembly              | ~3 days    | Walk MCU rows, decode 8x8 blocks in the SOS-declared component order, level-shift (+128), clamp to 0..255, write into the output pixel buffer. |
| **Subtotal grayscale baseline** | **~3-4 wk**| End-to-end pure-NOVA decoder for the format the MVP targets. |

Beyond grayscale baseline:

| Extension                       | Additional effort | Notes |
|---------------------------------|-------------------|-------|
| YCbCr -> RGB color conversion   | ~3 days           | 3-channel + 3x3 matrix multiply + level shift. |
| 4:2:0 / 4:2:2 chroma upsample   | ~3-5 days         | Bilinear upsample Cb/Cr to Y resolution; handle MCU geometry. |
| Progressive (SOF2)              | ~2-3 weeks        | Spectral selection + successive approximation + multi-scan accumulation. |
| Arithmetic coding (SOF1/3)      | ~2 weeks          | Patent-encumbered until 2007; rarely seen in practice. |
| 12-bit precision                | ~1 week           | All accumulator widths double; codegen pointer-threshold needs care. |
| EXIF rotation orientation       | ~1 day            | Read APP1, swap dims + transpose pixels per ITU-R BT.601. |
| ICC color profile               | ~1 week           | Embedded profile parsing + color management. |

## Reference: ITU-T T.81 (the JPEG standard)

The structural parser implements:
- **Annex B** "Compressed data formats" -- segment markers, length
  fields, the SOI / SOF / DHT / DQT / SOS / EOI sequence.
- **Annex B.2.4.1** -- DQT segment layout (Pq:4 | Tq:4 + 64-or-128 byte
  table).
- **Annex B.2.2** -- SOF0 segment layout (precision + Y + X + Nf +
  per-component header).
- **Annex B.2.4.2** -- DHT segment layout (Tc:4 | Th:4 + BITS[16] +
  HUFFVAL[sum(BITS)]).
- **Annex B.1.1.2** -- marker filler bytes (multiple 0xFF runs).
- **Annex B.1.1.4** -- 0xFF 0x00 byte stuffing within entropy data
  (relevant only when the entropy decoder lands).

The deferred entropy + IDCT pipeline would implement:
- **Annex F** "Sequential DCT-based mode of operation" -- block-by-block
  Huffman decoding + de-quantization + IDCT + level-shift.
- **Annex F.2.2** -- Huffman decoding (canonical table construction +
  DC differential + AC zero-run-length).
- **Annex A.3.3** -- Inverse DCT mathematical definition (the AAN
  factorization is recommended for fixed-point implementations).

## NOVA gotchas worked around in P3.1.JPEG

- **Big-endian everywhere.** JPEG length fields, dimensions, DQT 16-bit
  entries are all 2-byte big-endian. The parser uses `int_mul`-based
  byte combination same as `png_decode.nova`, so a 16-bit length up
  to 65535 stays safe under NOVA's codegen pointer-threshold gotcha
  #11 (we are nowhere near the 2^20 ceiling at that field width).
- **Dimension cap = 1024 per axis = 1048576 pixel area.** Matches
  `PGM_MAX_DIM` / `PNG_MAX_DIM`. Larger files are refused at SOF0 with
  a "downsample first" diagnostic; the rare JPEG larger than 1024 on
  either axis is uncommon in chat-paste flows and can be pre-resized
  by the operator.
- **File cap = 1 MiB.** Stricter than PNG's 2 MiB; JPEG's heavy
  compression means a 1024x1024 8-bit grayscale photograph is
  typically 50-300 KB on disk, well under the cap. A malicious oversized
  JPEG is truncated at 1 MiB and the parser fails cleanly at the
  truncated marker.
- **No `break` keyword.** The segment iterator's filler-skipping inner
  loop uses a `scanning = 0` sentinel pattern instead of `break`,
  matching the pattern used in `image_sift.nova` and other modules
  in CrossEngin's codebase. The codegen path for `break` has not
  been validated across every NOVA target the project supports.
- **`match` is a reserved identifier in NOVA.** The unit-test's
  substring helper uses `let ok = 1` rather than `let match = 1`.

## Cross-references

* `src/io/transducers/jpeg_decode.nova` -- the structural parser
  (segments + DQT + SOF0 + DHT) and the entry-point stub for the
  full grayscale decoder.
* `src/io/transducers/visual_perception.nova` -- dispatches `.jpg` /
  `.jpeg` paths to the JPEG decoder via `VP_DECODER_JPEG`.
* `tests/unit/test_jpeg_decode.nova` -- 54 in-memory assertions
  covering segment iteration, DQT / SOF0 / DHT parsing, the
  oversized-dimension rejection, and the documented-gap error
  message.
* `scripts/gen_test_jpeg.py` -- Pillow-based JPEG fixture generator
  with a hand-rolled fallback for sandboxes without Pillow.
* `IMAGE_AUDIT.md` -- broader image-modality audit; lists JPEG as
  the most-wanted format and estimates the full decoder at 6-8
  weeks (the structural half landed here is ~10% of that estimate).
* `tests/unit/test_png_decode.nova` -- sibling structural parser
  that landed in P3.1.PNG; same shape (in-memory fixtures, parser-
  surface assertions, hand-rolled malformed inputs).
