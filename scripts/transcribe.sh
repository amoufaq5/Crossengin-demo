#!/usr/bin/env bash
# CrossEngin STT subprocess shim (P2.5).
#
# Speech-to-text. Takes a WAV file path; emits the transcript on stdout,
# one line. This is the runtime backend for `src/io/transducers/stt_seam.nova`
# when the seam is configured with `CE_STT_BACKEND=subprocess` -- the seam
# forks /bin/sh -c "scripts/transcribe.sh <wav>" and reads the child's
# stdout.
#
# Backend auto-detection at runtime (highest quality first):
#   1. whisper-cli    -- the official whisper.cpp CLI. Install:
#                          git clone https://github.com/ggerganov/whisper.cpp
#                          cd whisper.cpp && make
#                          bash ./models/download-ggml-model.sh tiny.en
#                          sudo cp main /usr/local/bin/whisper-cli   # or
#                          sudo ln -s $PWD/main /usr/local/bin/whisper-cli
#   2. main           -- the legacy whisper.cpp binary name (same project).
#                        Install: same as above, leave the binary named `main`.
#   3. vosk-transcriber -- the Python vosk wrapper. Install:
#                          pip install vosk vosk-transcriber
#                          # download a small model from https://alphacephei.com/vosk/models
#   4. (fallback)     -- echo "[stt: no backend installed]" and exit 0.
#                        The seam treats this as a "stub" result with
#                        confidence 0 so the agent keeps running rather
#                        than crashing on a sealed sandbox.
#
# Contract (the seam relies on this):
#   * Reads `$1` as the WAV file path. Bare `--help` / `-h` is also recognised.
#   * Prints exactly ONE line to stdout containing the transcript (or the
#     "[stt: ...]" placeholder).
#   * Exits 0 on success AND on "no backend available" AND on "input WAV
#     missing" (so a caller that forks this script in a sealed environment
#     never sees a non-zero exit -- the placeholder line tells it the
#     transcript is unavailable). Exits 2 only on a missing argument
#     (programmer error, distinct from a runtime backend miss).
#   * Diagnostics go to stderr -- caller may capture or discard.
#
# Usage:    scripts/transcribe.sh <wav-path>
#           CE_STT_LANG=en scripts/transcribe.sh /tmp/ce_input.wav
#           CE_STT_MODEL=tiny.en scripts/transcribe.sh /tmp/ce_input.wav
#
# Env knobs (forwarded to the backend if it supports them):
#   CE_STT_LANG   -- BCP-47 language tag (default 'en')
#   CE_STT_MODEL  -- model name for whisper (default 'tiny.en')

set -uo pipefail

case "${1:-}" in
    -h|--help)
        echo "usage: $0 <wav-path>"
        echo "  Runs the best installed STT backend (whisper.cpp / vosk)"
        echo "  against the WAV at <wav-path>. Prints the transcript to"
        echo "  stdout, one line. Exits 0 on success and on the no-backend"
        echo "  fallback; exits 2 only on missing argument / missing file."
        exit 0
        ;;
esac

if [ $# -lt 1 ]; then
    echo "ERROR: no WAV path supplied; usage: $0 <wav-path>" >&2
    exit 2
fi

WAV="$1"
if [ ! -f "$WAV" ]; then
    # Print the placeholder and exit 0: the seam treats this exactly like
    # "no backend installed" -- the agent has no transcript but also has
    # no fatal error to propagate. Diagnostics go to stderr.
    echo "ERROR: WAV not found: $WAV" >&2
    echo "[stt: input wav missing]"
    exit 0
fi

LANG_TAG="${CE_STT_LANG:-en}"
MODEL="${CE_STT_MODEL:-tiny.en}"

# Probe in quality order. The seam wants ONE line of transcript on stdout;
# every backend gets a tail | head -1 to enforce that.

if command -v whisper-cli >/dev/null 2>&1; then
    # whisper-cli (official whisper.cpp wrapper) writes a .txt sidecar by
    # default; we capture the stdout transcript with --no-prints + --print-progress
    # disabled. Falls back to stderr on missing model.
    OUT="$(whisper-cli -m "models/ggml-${MODEL}.bin" -f "$WAV" \
            --no-prints --language "$LANG_TAG" 2>/dev/null \
          | tr -d '\r' \
          | grep -v '^$' \
          | head -n 1)"
    if [ -n "$OUT" ]; then
        echo "$OUT"
        exit 0
    fi
    # Fall through to next backend on empty output.
fi

if command -v main >/dev/null 2>&1; then
    # Legacy whisper.cpp binary. Same flags shape as whisper-cli; older
    # builds use --print-colors which we disable for a clean stdout.
    OUT="$(main -m "models/ggml-${MODEL}.bin" -f "$WAV" \
            --no-prints --language "$LANG_TAG" 2>/dev/null \
          | tr -d '\r' \
          | grep -v '^$' \
          | head -n 1)"
    if [ -n "$OUT" ]; then
        echo "$OUT"
        exit 0
    fi
fi

if command -v vosk-transcriber >/dev/null 2>&1; then
    # vosk-transcriber emits the transcript on stdout. The Python wrapper
    # handles model selection via VOSK_MODEL_PATH or an installed model.
    OUT="$(vosk-transcriber -i "$WAV" -l "$LANG_TAG" 2>/dev/null \
          | tr -d '\r' \
          | grep -v '^$' \
          | head -n 1)"
    if [ -n "$OUT" ]; then
        echo "$OUT"
        exit 0
    fi
fi

# No backend available, or every backend produced no output. Emit the
# placeholder; the seam interprets this as a stub result with confidence 0.
echo "[stt: no backend installed]"
exit 0
