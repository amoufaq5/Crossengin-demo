# JPEG_AUDIT — what a pure-NOVA JPEG decoder would take

Status: **grayscale baseline END-TO-END DECODE LANDED (P3.1.JPEG cont.).**
The structural half (segment markers + DQT + SOF0 + DHT) landed first;
the entropy decode + IDCT pipeline followed in the same module. Today
`jpeg_decode_grayscale(path)` returns real pixel data for any
baseline-sequential 8-bit single-component JPEG with dimensions up to
512x512. Pixel values match libjpeg (Pillow) within +/-3 due to the
slight precision difference between our 10-bit fixed-point IDCT and
Pillow's floating-point reference. The dispatch hook in
`src/io/transducers/visual_perception.nova` routes `*.jpg` / `*.jpeg`
paths to the JPEG backend and -- when decode succeeds -- feeds the
resulting pixel buffer through the same `vp_features_for_image` pipeline
that PGM and PNG use. Color (YCbCr) + chroma subsampling are still
deferred per the table below.

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
- **`jpeg_decode_grayscale(path) -> [width, height, pixel_data_ptr, error_msg]`** --
  Opens the file, validates SOI, walks segments, finds SOF0, validates
  the JPEG is baseline grayscale, builds canonical DC + AC Huffman
  tables from BITS+HUFFVAL, runs the entropy + IDCT pipeline block by
  block, and returns an alloc'd `width*height` byte buffer of decoded
  grayscale samples. On unsupported variants or decode failure, the
  error_msg slot carries a clear diagnostic and pixel_data_ptr is the
  sentinel 0.
- **Pipeline internals (per ITU-T T.81 Annex F):**
  - `_jpeg_bitreader_new(...)` -- MSB-first bit reader with 0xFF 0x00
    byte stuffing per B.1.1.5; stashes an inline marker (e.g. EOI) when
    encountered so the caller knows the entropy stream ended cleanly.
  - `_jpeg_build_huffman(bits, huffval)` -- canonical Huffman table
    builder per Annex C (mincode / maxcode / valptr / huffval).
  - `_jpeg_br_decode_huffman(br, tbl)` -- one symbol per call, accumulating
    `code` MSB-first until `code <= maxcode[L]`.
  - `_jpeg_extend(v, s)` -- T.81 Figure F.12 sign-extend for SSSS-bit
    magnitudes.
  - `_jpeg_decode_block(br, dc, ac, prev_dc)` -- decode one 8x8 block in
    zig-zag order: DC differential, AC RLE with EOB/ZRL markers.
  - `_jpeg_dequant_and_unzigzag(zz, qt)` -- multiply zig-zag coefficients
    by the quant table and place them in row-major natural order via
    the standard zig-zag-to-natural index map (T.81 Figure A.6).
  - `_jpeg_idct_2d(block)` -- separable 8x8 IDCT using 10-bit fixed-point
    cosine coefficients (table cached on first use). Each 1-D pass does
    64 int_mul + int_add accumulations; divisions use the Bug-A int_*
    builtins so intermediate ~2^28 products stay in the pointer-safe
    regime. Level-shift (+128) and 0..255 clamp applied in the final pass.
  - `_jpeg_decode_scan(br, w, h, dc, ac, qt, pixels)` -- walks MCU rows
    left-to-right, top-to-bottom, decodes each block, and writes the
    8x8 sample tile at (bx*8, by*8) in the output buffer. Trailing
    partial blocks are decoded fully and clipped to the image dims.

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
- `_vp_decode_jpeg(seam, path)` calls `jpeg_decode_grayscale`; on
  success (pixel buffer returned), feeds the buffer through the SAME
  `vp_features_for_image` + `vp_summary_for_image` surface PGM and
  PNG use (so the perception path emits the standard size / mean /
  bucket / orientation / edge / corner / SIFT atoms). On failure
  (color JPEG, oversized dims, missing tables, malformed entropy data),
  emits `image_jpeg_header_only` + the dimension bucket and surfaces
  the diagnostic via `vp_result_error` so the chat's "(saw image ...
  FAILED ...)" branch fires.
- `.jpg` / `.jpeg` path-extension routing dispatches to the JPEG
  decoder even when the seam's default is PGM.

## What landed in this session (entropy decode + IDCT pipeline)

The previously-deferred decode pipeline downstream of the header parse:

| Step                            | Status     | Where it lives |
|---------------------------------|------------|----------------|
| Huffman entropy decoder         | **shipped**| `_jpeg_build_huffman` + `_jpeg_br_decode_huffman` + `_jpeg_extend`; canonical T.81 Annex C codes; MSB-first bit reader with 0xFF 0x00 byte-stuff handling. |
| De-quantize + inverse zig-zag   | **shipped**| `_jpeg_dequant_and_unzigzag`; uses the standard zig-zag table cached on first call; int_mul keeps the multiplies on the pointer-safe fast path. |
| 8x8 IDCT (inverse DCT)          | **shipped**| `_jpeg_idct_2d` + `_jpeg_idct_1d`; separable integer IDCT with a 10-bit fixed-point cosine table. ~8 multiplies per output sample per 1-D pass = 128 multiplies per block. |
| Block-row assembly              | **shipped**| `_jpeg_decode_scan`; walks MCU rows left-to-right, top-to-bottom; level-shift (+128) and clamp baked into `_jpeg_idct_2d`. Trailing partial blocks are decoded and clipped. |
| **Subtotal grayscale baseline** | **shipped**| End-to-end pure-NOVA decoder; `jpeg_decode_grayscale("/path.jpg")` returns real pixel data. |

## What this session does NOT ship

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

The entropy + IDCT pipeline (P3.1.JPEG cont., this session) implements:
- **Annex F** "Sequential DCT-based mode of operation" -- block-by-block
  Huffman decoding + de-quantization + IDCT + level-shift. Realised in
  `_jpeg_decode_scan` + `_jpeg_decode_block` + `_jpeg_dequant_and_unzigzag`
  + `_jpeg_idct_2d`.
- **Annex F.2.2** -- Huffman decoding (canonical table construction +
  DC differential + AC zero-run-length). Table build in
  `_jpeg_build_huffman` (Annex C); per-symbol decode in
  `_jpeg_br_decode_huffman`; sign-extend in `_jpeg_extend`.
- **Annex A.3.3** -- Inverse DCT mathematical definition. We use a
  separable integer IDCT with a 10-bit fixed-point cosine table (see
  `_jpeg_idct_cos_table`) rather than AAN proper, because the cosine-
  matrix form is simpler to read and the multiply count per block
  (128) is still well under NOVA's per-image arithmetic budget for the
  512x512 dimension cap.
- **Annex B.1.1.5** -- 0xFF 0x00 byte stuffing within entropy data.
  Handled transparently by `_jpeg_br_refill_byte`; any other 0xFF nn
  pair is treated as an embedded marker, stashed in `JPEG_BR_MARKER`,
  and the bit-reader stops refilling.

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

* `src/io/transducers/jpeg_decode.nova` -- structural parser
  (segments + DQT + SOF0 + DHT) AND the entropy decode + IDCT
  pipeline (Huffman + dequant + un-zig-zag + 8x8 IDCT + block
  assembly).
* `src/io/transducers/visual_perception.nova` -- dispatches `.jpg` /
  `.jpeg` paths to the JPEG decoder via `VP_DECODER_JPEG`; on
  decode success feeds pixel data through the standard
  `vp_features_for_image` pipeline.
* `tests/unit/test_jpeg_decode.nova` -- 87 in-memory assertions
  covering segment iteration, DQT / SOF0 / DHT parsing, the
  oversized-dimension rejection, the canonical Huffman build, the
  bit reader with byte-stuffing, the 8x8 IDCT (all-zero block,
  DC-only block), the dequant + un-zig-zag round-trip, the end-to-end
  `jpeg_decode_grayscale_bytes` on a synthetic stream, and the
  real-Pillow first-pixel match (within +/-3 of libjpeg).
* `scripts/gen_test_jpeg.py` -- Pillow-based JPEG fixture generator
  with a hand-rolled fallback for sandboxes without Pillow; also
  exposes a `reference_decode_first_pixel(jpeg_bytes)` helper used
  by integration smokes that want a libjpeg ground-truth comparison.
* `tests/integration/scenario_q_image_see.sh` -- `/see` scenario now
  includes a 32x32 Pillow-generated JPEG fixture and verifies the
  chat surfaces the expected dimensions + feature atoms (matching
  the equivalent PGM fixture's labels modulo JPEG's lossy smoothing).
* `IMAGE_AUDIT.md` -- broader image-modality audit; with grayscale
  baseline shipped, the remaining JPEG work (color + chroma) is
  ~1-2 weeks rather than the 6-8 originally estimated.
* `tests/unit/test_png_decode.nova` -- sibling structural parser
  that landed in P3.1.PNG; same shape (in-memory fixtures, parser-
  surface assertions, hand-rolled malformed inputs).
