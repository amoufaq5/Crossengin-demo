#!/usr/bin/env python3
"""
CrossEngin test-fixture generator: grayscale-8 PNG (P3.1.PNG full DEFLATE).

Emits a tiny PNG-8 grayscale fixture suitable for the pure-NOVA PNG decoder
in src/io/transducers/png_decode.nova. The decoder now supports ALL three
DEFLATE block types (stored / static Huffman / dynamic Huffman) per RFC 1951
sections 3.2.4 / 3.2.6 / 3.2.7, so this generator defaults to zlib level 9
(dynamic Huffman, exactly what a phone camera or screenshot tool would
produce). The `--level` flag picks the zlib compression level (0..9):
  * level 0  -> stored DEFLATE blocks (BTYPE=00); the Item-3 MVP path.
  * level 1..4 -> typically static Huffman (BTYPE=01); short payloads.
  * level 5..9 -> typically dynamic Huffman (BTYPE=10); the real-world
    default for most encoders.

Usage:
    python3 scripts/gen_test_png.py [<width> <height> [<out-path>] [--level N]]
    python3 scripts/gen_test_png.py 16 16 /tmp/test.png
    python3 scripts/gen_test_png.py 16 16 /tmp/test_l0.png --level 0

Defaults: 8x8 grayscale gradient written to /tmp/ce_test.png at level 9.

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


def build_stored_png(width: int, height: int, pixels: bytes, level: int = 9) -> bytes:
    """
    Build an end-to-end PNG-8 grayscale file. zlib `level` selects the
    DEFLATE encoding strategy:
      level=0  -> stored / uncompressed DEFLATE blocks (BTYPE=00).
      level=1..4 -> typically static-Huffman blocks (BTYPE=01) for short
                    payloads.
      level=5..9 -> typically dynamic-Huffman blocks (BTYPE=10); zlib's
                    real-world default.
    The pure-NOVA decoder supports ALL three modes since the full DEFLATE
    inflate landed alongside the static + dynamic Huffman tables.
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

    # Compress raw at the requested level. zlib picks the DEFLATE block
    # type (stored / static / dynamic) based on its own cost heuristic;
    # level 0 forces stored, level 9 prefers dynamic for most inputs.
    co = zlib.compressobj(level=level)
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
    """Returns (width, height, out_path, level). --level N is an optional
    trailing flag picking the zlib compression level (default 9)."""
    # Pull --level off first so positional args stay simple.
    level = 9
    positional = []
    i = 1
    while i < len(argv):
        a = argv[i]
        if a == "--level":
            if i + 1 >= len(argv):
                print("ERROR: --level requires an integer 0..9", file=sys.stderr)
                sys.exit(2)
            try:
                level = int(argv[i + 1])
            except ValueError:
                print(f"ERROR: --level argument must be int; got {argv[i+1]}", file=sys.stderr)
                sys.exit(2)
            i += 2
            continue
        positional.append(a)
        i += 1

    width = 8
    height = 8
    out_path = "/tmp/ce_test.png"
    if len(positional) >= 2:
        try:
            width = int(positional[0])
            height = int(positional[1])
        except ValueError:
            print(f"ERROR: width/height must be integers; got {positional[:2]}", file=sys.stderr)
            sys.exit(2)
    if len(positional) >= 3:
        out_path = positional[2]
    # Cap dimensions at 1024 to match the pure-NOVA decoder's PNG_MAX_DIM.
    if width <= 0 or height <= 0:
        print("ERROR: width and height must be positive", file=sys.stderr)
        sys.exit(2)
    if width > 1024 or height > 1024:
        print("ERROR: width and height must be <= 1024 (decoder cap)", file=sys.stderr)
        sys.exit(2)
    if level < 0 or level > 9:
        print(f"ERROR: --level must be 0..9; got {level}", file=sys.stderr)
        sys.exit(2)
    return width, height, out_path, level


def main() -> int:
    width, height, out_path, level = parse_argv(sys.argv)
    pixels = gradient_pixels(width, height)
    png_bytes = build_stored_png(width, height, pixels, level=level)
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
