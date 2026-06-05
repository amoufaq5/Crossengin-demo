#!/usr/bin/env bash
# CrossEngin video-conversion subprocess shim (P3.2).
#
# Converts an arbitrary video (MP4, MKV, WebM, MOV, AVI, ...) into the
# raw YUV4MPEG2 (Y4M) format that `src/io/transducers/video_y4m.nova`
# knows how to decode. H.264 / H.265 / AV1 / VP9 decode in pure NOVA is
# MONTHS of work each (see `VIDEO_AUDIT.md`); until then this shim is
# the recommended path for any operator who needs the video seam to see
# real footage. Same shape + exit semantics as `scripts/image_to_pgm.sh`.
#
# Backend auto-detection at runtime:
#   1. ffmpeg with yuv4mpegpipe output -- the only realistic backend.
#        Install: apt-get install ffmpeg
#                 dnf install ffmpeg
#                 brew install ffmpeg
#   2. (fallback) -- no backend installed; print the install hint to
#        stderr and exit 0. The seam treats the missing fixture as a
#        soft failure ("y4m: cannot open file") -- same outcome as the
#        image shim's "no backend" placeholder.
#
# Contract (the video_perception seam relies on this shape):
#   * Reads `$1` as the source video path.
#   * Reads `$2` (optional) as the destination Y4M path; defaults to
#     `${CE_Y4M_OUT:-/tmp/ce_video.y4m}`.
#   * Optional `CE_Y4M_MAX_DIM` env caps the longest output side
#     (default 432 -- well under the pure-NOVA decoder's 768x432
#     pixel cap).
#   * Optional `CE_Y4M_MAX_FRAMES` env (default 30) caps the number of
#     frames extracted -- a one-second clip at 30fps is plenty for the
#     perception seam to chew on.
#   * Prints exactly ONE line to stdout: the absolute destination path.
#   * Exits 0 on success AND on "no backend available". Exits 2 only on
#     missing argument or an unreadable source file.
#   * Diagnostics go to stderr -- caller may capture or discard.
#
# Usage:
#   scripts/video_to_y4m.sh clip.mp4
#   scripts/video_to_y4m.sh clip.mp4 /tmp/out.y4m
#   CE_Y4M_MAX_DIM=256 CE_Y4M_MAX_FRAMES=10 scripts/video_to_y4m.sh clip.mp4

set -uo pipefail

case "${1:-}" in
    -h|--help)
        echo "usage: $0 <video-path> [<out-y4m-path>]"
        echo "  Runs ffmpeg to extract the first N frames of the input"
        echo "  video as a raw Y4M (YUV4MPEG2) file the CrossEngin video"
        echo "  seam can decode. Prints the Y4M path to stdout. Exits 0"
        echo "  on success and on the no-backend fallback."
        echo
        echo "Env knobs:"
        echo "  CE_Y4M_OUT         destination path (default /tmp/ce_video.y4m)"
        echo "  CE_Y4M_MAX_DIM     longest side in pixels (default 432)"
        echo "  CE_Y4M_MAX_FRAMES  frames to extract (default 30)"
        exit 0
        ;;
esac

if [ $# -lt 1 ]; then
    echo "ERROR: no video path supplied; usage: $0 <video-path> [<out-y4m-path>]" >&2
    exit 2
fi

SRC="$1"
DST="${2:-${CE_Y4M_OUT:-/tmp/ce_video.y4m}}"
MAX_DIM="${CE_Y4M_MAX_DIM:-432}"
MAX_FRAMES="${CE_Y4M_MAX_FRAMES:-30}"

# A missing source file is unambiguous operator error -- the video
# seam should be told the input was bad, not handed a placeholder.
if [ ! -f "$SRC" ]; then
    echo "ERROR: video not found: $SRC" >&2
    exit 2
fi

# --- Mode 1: ffmpeg ----------------------------------------------------------
if command -v ffmpeg >/dev/null 2>&1; then
    # `yuv4mpegpipe` is ffmpeg's native Y4M demuxer. `format=yuv420p`
    # enforces 4:2:0 chroma subsampling (what the pure-NOVA decoder
    # expects). `-vf scale=...:force_original_aspect_ratio=decrease`
    # respects the longest-side cap without distortion.
    if ffmpeg -nostdin -loglevel error -y \
            -i "$SRC" \
            -vf "scale='min(${MAX_DIM},iw)':'min(${MAX_DIM},ih)':force_original_aspect_ratio=decrease,format=yuv420p" \
            -frames:v "$MAX_FRAMES" \
            -f yuv4mpegpipe \
            "$DST" 2>/dev/null; then
        if [ -s "$DST" ]; then
            echo "$DST"
            exit 0
        fi
    fi
    echo "WARN: ffmpeg conversion failed -- check that '$SRC' is a real video" >&2
fi

# --- Mode 2: no backend ----------------------------------------------
# No conversion backend present. Surface a clear "install ffmpeg" hint
# to stderr and exit 0 so callers don't crash; the video seam will see
# "y4m: cannot open file" on the missing $DST which is the right signal.
echo "(skip: ffmpeg not installed; install via 'apt install ffmpeg' or" >&2
echo "        'brew install ffmpeg' / 'dnf install ffmpeg' -- the video" >&2
echo "        seam needs a real Y4M file at $DST.)" >&2
exit 0
