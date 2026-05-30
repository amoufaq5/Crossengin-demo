#!/usr/bin/env python3
"""
CrossEngin test-fixture generator: stored-DEFLATE grayscale-8 PNG (P3.1.PNG).

Emits a tiny PNG-8 grayscale fixture suitable for the pure-NOVA PNG decoder
in src/io/transducers/png_decode.nova. The MVP only handles BTYPE=00
(stored / uncompressed) DEFLATE blocks, so this generator hand-rolls the
zlib + DEFLATE wrapping with `zlib.compressobj(level=0)` -- the standard
library's level-0 compression emits stored-only blocks. Reference PNGs
from any tool that supports zlib level 0 (pngcrush -force, optipng -o0,
explicit zlib level=0 in PIL) decode the same way.

Usage:
    python3 scripts/gen_test_png.py [<width> <height> [<out-path>]]
    python3 scripts/gen_test_png.py 16 16 /tmp/test.png

Defaults: 8x8 grayscale gradient written to /tmp/ce_test.png.

Exit code: 0 on success; nonzero on argv error or write failure.

Why a python helper instead of in-NOVA generation:
  * NOVA's MVP DEFLATE encoder is out of scope -- the decoder is the
    load-bearing piece for the agent's perception path.
  * Integration tests run on systems where Python is reliably present
    (the CrossEngin web frontend already uses scripts/web.py).
  * The fixture is deterministic at the byte level: feeding the same
    seed produces the same PNG bytes across runs, so the decoder is
    tested against an externally-validated reference.
"""

import struct
import sys
import zlib


def png_chunk(chunk_type: bytes, data: bytes) -> bytes:
    """Pack one PNG chunk: [length:4 BE][type:4][data:length][crc:4 BE]."""
    crc = zlib.crc32(chunk_type + data) & 0xFFFFFFFF
    return struct.pack(">I", len(data)) + chunk_type + data + struct.pack(">I", crc)


def build_stored_png(width: int, height: int, pixels: bytes) -> bytes:
    """
    Build an end-to-end PNG-8 grayscale file using stored-only DEFLATE
    compression (zlib level=0), suitable for the pure-NOVA decoder.
    """
    if len(pixels) != width * height:
        raise ValueError(
            f"pixels has {len(pixels)} bytes; expected {width * height}"
        )

    # 8-byte PNG signature.
    signature = b"\x89PNG\r\n\x1a\n"

    # IHDR data: width:4 BE, height:4 BE, bit_depth:1, color_type:1,
    # compression:1, filter:1, interlace:1. bit_depth=8, color_type=0
    # (grayscale), compression=0, filter=0, interlace=0.
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 0, 0, 0, 0)

    # Build the raw scanline buffer: 1 filter byte (None=0) + width pixel
    # bytes per row, concatenated row-major top-to-bottom.
    raw = bytearray()
    for row in range(height):
        raw.append(0)  # filter type None
        for col in range(width):
            raw.append(pixels[row * width + col])

    # Compress raw with zlib level=0 (stored-only DEFLATE).
    co = zlib.compressobj(level=0)
    compressed = co.compress(bytes(raw)) + co.flush()

    # Assemble the file.
    out = bytearray()
    out += signature
    out += png_chunk(b"IHDR", ihdr)
    out += png_chunk(b"IDAT", compressed)
    out += png_chunk(b"IEND", b"")
    return bytes(out)


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


def parse_argv(argv):
    """Returns (width, height, out_path)."""
    width = 8
    height = 8
    out_path = "/tmp/ce_test.png"
    if len(argv) >= 3:
        try:
            width = int(argv[1])
            height = int(argv[2])
        except ValueError:
            print(f"ERROR: width/height must be integers; got {argv[1:3]}", file=sys.stderr)
            sys.exit(2)
    if len(argv) >= 4:
        out_path = argv[3]
    # Cap dimensions at 1024 to match the pure-NOVA decoder's PNG_MAX_DIM.
    if width <= 0 or height <= 0:
        print("ERROR: width and height must be positive", file=sys.stderr)
        sys.exit(2)
    if width > 1024 or height > 1024:
        print("ERROR: width and height must be <= 1024 (decoder cap)", file=sys.stderr)
        sys.exit(2)
    return width, height, out_path


def main() -> int:
    width, height, out_path = parse_argv(sys.argv)
    pixels = gradient_pixels(width, height)
    png_bytes = build_stored_png(width, height, pixels)
    try:
        with open(out_path, "wb") as f:
            f.write(png_bytes)
    except OSError as e:
        print(f"ERROR: cannot write {out_path}: {e}", file=sys.stderr)
        return 2
    print(out_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
