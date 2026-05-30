#!/usr/bin/env bash
# CrossEngin image-conversion subprocess shim (P3.1).
#
# Converts an arbitrary image (JPEG, PNG, WebP, BMP, GIF, TIFF, HEIC, etc.)
# into the binary PGM (P5) format that
# `src/io/transducers/image_pgm.nova` knows how to decode. JPEG / PNG /
# WebP decode in pure NOVA is weeks of work each (see `IMAGE_AUDIT.md`);
# until then this shim is the recommended path for any production
# operator who needs the visual seam to see real photographs.
#
# Backend auto-detection at runtime (highest quality / least surprise first):
#   1. ImageMagick `convert` (or `magick convert` on IM 7+).
#        Install: apt-get install imagemagick
#                 dnf install ImageMagick
#                 brew install imagemagick
#   2. ImageMagick `magick` (IM 7+ unified binary).
#   3. ffmpeg with PGM output.
#        Install: apt-get install ffmpeg
#   4. (fallback) -- generate a 16x16 grey PGM placeholder so the
#        downstream seam still has SOMETHING to decode and the
#        operator sees a clear "no backend" diagnostic on stderr.
#        Exit 0 with the placeholder path -- the seam treats the
#        decoded image as a valid (if uninformative) input.
#
# Contract (the visual_perception seam relies on this shape):
#   * Reads `$1` as the source image path.
#   * Reads `$2` (optional) as the destination PGM path; defaults to
#     `${CE_PGM_OUT:-/tmp/ce_image.pgm}`.
#   * Optional `CE_PGM_MAX_DIM` env caps the largest output side
#     (default 256 -- well under the pure-NOVA decoder's 1024x1024
#     pixel-area cap and small enough that the in-memory PGM stays
#     well under 64 KiB).
#   * Prints exactly ONE line to stdout: the absolute destination path.
#   * Exits 0 on success AND on "no backend available". Exits 2 only on
#     missing argument or an unreadable source file.
#   * Diagnostics go to stderr -- caller may capture or discard.
#
# Usage:
#   scripts/image_to_pgm.sh photo.jpg
#   scripts/image_to_pgm.sh photo.jpg /tmp/out.pgm
#   CE_PGM_MAX_DIM=128 scripts/image_to_pgm.sh photo.jpg

set -uo pipefail

case "${1:-}" in
    -h|--help)
        echo "usage: $0 <image-path> [<out-pgm-path>]"
        echo "  Runs the best installed image-conversion backend"
        echo "  (ImageMagick / ffmpeg) to produce a binary PGM the"
        echo "  CrossEngin visual seam can decode. Prints the PGM path"
        echo "  to stdout. Exits 0 on success and on the no-backend"
        echo "  fallback (which writes a 16x16 grey placeholder)."
        echo
        echo "Env knobs:"
        echo "  CE_PGM_OUT      destination path (default /tmp/ce_image.pgm)"
        echo "  CE_PGM_MAX_DIM  longest side in pixels (default 256)"
        exit 0
        ;;
esac

if [ $# -lt 1 ]; then
    echo "ERROR: no image path supplied; usage: $0 <image-path> [<out-pgm-path>]" >&2
    exit 2
fi

SRC="$1"
DST="${2:-${CE_PGM_OUT:-/tmp/ce_image.pgm}}"
MAX_DIM="${CE_PGM_MAX_DIM:-256}"

# A missing source file is unambiguous operator error -- the visual
# seam should be told the input was bad, not handed a placeholder that
# silently masks the typo.
if [ ! -f "$SRC" ]; then
    echo "ERROR: image not found: $SRC" >&2
    exit 2
fi

# --- Mode 0: PNG passthrough (P3.1.PNG) ---------------------------------------
# When the source is already a PNG, the pure-NOVA decoder in
# src/io/transducers/png_decode.nova can ingest it directly -- the
# visual_perception seam routes `.png` paths to the PNG backend via
# file-extension detection. We skip the convert/ffmpeg step entirely
# and echo the original PNG path so the caller can feed it straight to
# the seam. Caveat: the pure-NOVA decoder supports stored-DEFLATE only,
# so a standard libpng-compressed PNG will trip the documented
# "deflate: BTYPE=01/10 not implemented (TODO)" error. The visual_seam
# surfaces that error; the operator can re-run with the original SRC
# through ImageMagick to fall back to PGM if needed.
case "$SRC" in
    *.png|*.PNG)
        echo "INFO: input is PNG; routing through pure-NOVA decoder (no conversion)." >&2
        echo "$SRC"
        exit 0
        ;;
esac

# --- Mode 1: ImageMagick `convert` ---------------------------------------
if command -v convert >/dev/null 2>&1; then
    # `-resize NxN>` only shrinks (no upscale); `-colorspace Gray` flattens
    # to grayscale; the explicit `pgm:` prefix forces P5 output regardless
    # of the destination extension.
    if convert "$SRC" \
            -resize "${MAX_DIM}x${MAX_DIM}>" \
            -colorspace Gray \
            -depth 8 \
            "pgm:$DST" 2>/dev/null; then
        echo "$DST"
        exit 0
    fi
    echo "WARN: ImageMagick convert failed; trying next backend" >&2
fi

# --- Mode 2: ImageMagick 7 `magick` ------------------------------------------
if command -v magick >/dev/null 2>&1; then
    if magick "$SRC" \
            -resize "${MAX_DIM}x${MAX_DIM}>" \
            -colorspace Gray \
            -depth 8 \
            "pgm:$DST" 2>/dev/null; then
        echo "$DST"
        exit 0
    fi
    echo "WARN: ImageMagick magick failed; trying next backend" >&2
fi

# --- Mode 3: ffmpeg ----------------------------------------------------------
if command -v ffmpeg >/dev/null 2>&1; then
    # ffmpeg writes gray8 raw via the `pgm` codec when the output
    # extension is .pgm. `-vf scale` enforces the longest-side cap.
    if ffmpeg -nostdin -loglevel error -y \
            -i "$SRC" \
            -vf "scale='min(${MAX_DIM},iw)':'min(${MAX_DIM},ih)':force_original_aspect_ratio=decrease,format=gray" \
            -frames:v 1 \
            "$DST" 2>/dev/null; then
        if [ -s "$DST" ]; then
            echo "$DST"
            exit 0
        fi
    fi
    echo "WARN: ffmpeg conversion failed; falling back to placeholder" >&2
fi

# --- Mode 4: 16x16 grey placeholder -----------------------------------------
# No conversion backend present. Write a deterministic placeholder PGM so
# the seam still has bytes to decode (and the operator gets a clear
# diagnostic on stderr). Exit 0 with the placeholder path: a sealed
# sandbox is a runtime condition, not a programmer error.
echo "INFO: no image-conversion backend on PATH (tried: convert, magick, ffmpeg)." >&2
echo "INFO: writing 16x16 grey placeholder to $DST." >&2
{
    printf 'P5\n16 16\n255\n'
    # 256 bytes of value 128 (mid-grey).
    head -c 256 /dev/zero | tr '\000' '\200'
} > "$DST"
echo "$DST"
exit 0
