#!/usr/bin/env python3
"""
CrossEngin test-fixture generator: baseline-sequential grayscale JPEG (P3.1.JPEG).

Emits a tiny baseline-sequential 8-bit grayscale JPEG fixture suitable for
the pure-NOVA JPEG header parser in src/io/transducers/jpeg_decode.nova.
The MVP only parses the STRUCTURAL half (segment markers + DQT + SOF0 + DHT);
the entropy decode + IDCT + block assembly are deferred per JPEG_AUDIT.md.
This script's job is to produce a fixture that the structural parser can
walk end-to-end without crashing -- the entropy data is opaque, but the
segments around it (SOI, JFIF APP0, DQT, SOF0, DHT, SOS, EOI) are
real and correctly framed.

Usage:
    python3 scripts/gen_test_jpeg.py [<width> <height> [<out-path>]]
    python3 scripts/gen_test_jpeg.py 16 16 /tmp/test.jpg

Defaults: 16x16 grayscale gradient written to /tmp/ce_test.jpg.

Exit code: 0 on success; nonzero on argv error or write failure.

Implementation strategy:
  We use Pillow (PIL.Image) if it is available -- the standard library
  has no JPEG encoder. The image is created as 8-bit grayscale ("L" mode)
  and saved with quality=80, optimize=False so libjpeg produces a clean
  baseline-sequential stream with both DC and AC Huffman tables in DHT.
  If Pillow is NOT installed, we fall back to a HAND-ROLLED minimal
  JPEG stream that carries only the segments the structural parser
  inspects (SOI, APP0, DQT with a single zero table, SOF0 with the
  requested dimensions, DHT with a single DC table, SOS, two bytes of
  fake entropy data, EOI). The hand-rolled fallback is NOT a decodable
  JPEG -- a real decoder will choke on the entropy stream -- but it
  exercises the structural parser without needing Pillow.

Why a python helper instead of in-NOVA generation:
  * JPEG encoding (forward DCT + zig-zag + quantization + Huffman) is
    weeks of work outside this MVP's scope; the decoder is the load-
    bearing piece for the agent's perception path.
  * Pillow is one `pip install Pillow` away on any dev sandbox.
  * The hand-rolled fallback covers CI environments where Pillow is
    not available -- it produces enough STRUCTURE for the parser to
    test against.
"""

import struct
import sys


def parse_argv(argv):
    """Returns (width, height, out_path)."""
    width = 16
    height = 16
    out_path = "/tmp/ce_test.jpg"
    if len(argv) >= 3:
        try:
            width = int(argv[1])
            height = int(argv[2])
        except ValueError:
            print(f"ERROR: width/height must be integers; got {argv[1:3]}", file=sys.stderr)
            sys.exit(2)
    if len(argv) >= 4:
        out_path = argv[3]
    # Cap dimensions at 1024 to match the pure-NOVA decoder's JPEG_MAX_DIM.
    if width <= 0 or height <= 0:
        print("ERROR: width and height must be positive", file=sys.stderr)
        sys.exit(2)
    if width > 1024 or height > 1024:
        print("ERROR: width and height must be <= 1024 (decoder cap)", file=sys.stderr)
        sys.exit(2)
    return width, height, out_path


def gradient_pixels(width: int, height: int) -> bytes:
    """
    Deterministic gradient: pixel(x,y) = clamp((x * 16 + y * 8) % 256, 0, 255).
    Produces a smooth 2-D gradient covering most of the 0..255 range so
    feature extraction has something interesting to label.
    """
    out = bytearray(width * height)
    for y in range(height):
        for x in range(width):
            out[y * width + x] = (x * 16 + y * 8) % 256
    return bytes(out)


def uniform_pixels(width: int, height: int, value: int) -> bytes:
    """
    All-uniform pixel buffer. Useful for IDCT round-trip tests: a uniform
    image encodes to mostly-DC coefficients and decodes back to (very nearly)
    the same uniform value. After P3.1.JPEG cont. (entropy + IDCT) this
    fixture exercises the DC-only IDCT path end-to-end.
    """
    return bytes([value & 0xFF] * (width * height))


def reference_decode_first_pixel(jpeg_bytes: bytes) -> int:
    """
    Decode the first pixel of a JPEG via Pillow (if available) so the
    pure-NOVA decoder's first-pixel value can be compared against a real
    libjpeg reference. Returns the pixel intensity (0..255), or -1 if
    Pillow is unavailable.
    """
    try:
        from PIL import Image
        import io
        img = Image.open(io.BytesIO(jpeg_bytes))
        if img.mode != "L":
            img = img.convert("L")
        return img.getpixel((0, 0))
    except ImportError:
        return -1


def try_pillow_jpeg(width: int, height: int, pixels: bytes) -> bytes:
    """
    Encode a grayscale JPEG via Pillow. Returns the JPEG bytes, or raises
    if Pillow is not available.
    """
    try:
        from PIL import Image
    except ImportError:
        raise ImportError("Pillow is not installed")

    import io
    img = Image.frombytes("L", (width, height), pixels)
    buf = io.BytesIO()
    # quality=80 + optimize=False produces a baseline-sequential stream
    # with standard libjpeg DC + AC Huffman tables.
    img.save(buf, format="JPEG", quality=80, optimize=False)
    return buf.getvalue()


def hand_rolled_jpeg(width: int, height: int) -> bytes:
    """
    Build a minimal baseline JPEG with the segments the structural parser
    inspects. Not a decodable image -- the entropy data is two zero bytes.
    But the markers + DQT + SOF0 + DHT framing is real and conforms to
    ITU-T T.81 so the pure-NOVA header parser walks it cleanly.
    """
    out = bytearray()

    # SOI
    out += bytes([0xFF, 0xD8])

    # APP0 (JFIF): length=16, "JFIF\0", version 1.01, density units=0,
    # x/y density=1, thumb=0x0.
    app0_payload = b"JFIF\x00" + bytes([0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00])
    out += bytes([0xFF, 0xE0]) + struct.pack(">H", 2 + len(app0_payload)) + app0_payload

    # DQT: one 8-bit table (Pq=0, Tq=0) of 64 zeros. A real JPEG uses
    # the standard "luminance" Annex K quantization table; for our
    # structural parse the values are opaque.
    dqt_payload = bytes([0x00]) + bytes(64)
    out += bytes([0xFF, 0xDB]) + struct.pack(">H", 2 + len(dqt_payload)) + dqt_payload

    # SOF0: precision=8, height, width, n_components=1
    #  (grayscale: Y at id=1, sampling 1:1, qtable 0).
    sof0_payload = (
        bytes([8])
        + struct.pack(">H", height)
        + struct.pack(">H", width)
        + bytes([1])
        + bytes([1, 0x11, 0])     # comp id=1, H=1 V=1, qtable=0
    )
    out += bytes([0xFF, 0xC0]) + struct.pack(">H", 2 + len(sof0_payload)) + sof0_payload

    # DHT: one DC luminance table (Tc=0, Th=0). BITS = 16 zero counts (no codes),
    # symbols = empty. This is technically an empty Huffman table; valid framing
    # but useless for entropy decode.
    dht_payload = bytes([0x00]) + bytes(16)
    out += bytes([0xFF, 0xC4]) + struct.pack(">H", 2 + len(dht_payload)) + dht_payload

    # SOS: one component (Y), Td=0, Ta=0, Ss=0, Se=63, AhAl=0.
    sos_payload = bytes([1, 1, 0x00, 0, 63, 0])
    out += bytes([0xFF, 0xDA]) + struct.pack(">H", 2 + len(sos_payload)) + sos_payload

    # Fake entropy data (two zero bytes -- a real decoder would choke).
    out += bytes([0x00, 0x00])

    # EOI
    out += bytes([0xFF, 0xD9])

    return bytes(out)


def main() -> int:
    width, height, out_path = parse_argv(sys.argv)
    pixels = gradient_pixels(width, height)
    used_pillow = False
    try:
        jpeg_bytes = try_pillow_jpeg(width, height, pixels)
        used_pillow = True
    except ImportError:
        jpeg_bytes = hand_rolled_jpeg(width, height)
    try:
        with open(out_path, "wb") as f:
            f.write(jpeg_bytes)
    except OSError as e:
        print(f"ERROR: cannot write {out_path}: {e}", file=sys.stderr)
        return 2
    note = " (via Pillow)" if used_pillow else " (hand-rolled fallback; entropy data is fake)"
    print(f"{out_path}{note}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
