#!/usr/bin/env bash
# CrossEngin microphone-capture subprocess shim (P2.5 cont.).
#
# Captures N seconds of audio from the default microphone into a 16-bit
# little-endian mono WAV file at 16 kHz, in the exact shape
# `src/io/transducers/audio_capture.nova` (and downstream
# `stt_seam.nova` / whisper.cpp / vosk) expects. This is the input
# half of the audio modality bridge -- the output half (TTS) shipped
# in P19 + P2.6 (`audio_speak.nova`); P2.5 first round shipped the
# STT FRAMEWORK; this round (P2.5 cont.) closes the loop by adding
# real microphone capture and the auto-detect path in
# `stream_audio.nova`.
#
# Backend auto-detection at runtime (PulseAudio preferred -- modern
# desktop Linux ships pipewire-pulse by default, so parecord is the
# most likely to "just work"):
#   1. parecord (PulseAudio)  -- `parecord --format=s16le --rate=16000
#                                  --channels=1 --file-format=wav -d default
#                                  /tmp/out.wav` with the SIGALRM-based
#                                  duration limit set via `timeout`.
#   2. arecord (ALSA)         -- `arecord -f S16_LE -r 16000 -c 1 -d N
#                                  /tmp/out.wav`. Requires /dev/snd to exist
#                                  and the user to be in the `audio` group.
#   3. sox (Linux/macOS)      -- `sox -d -r 16000 -c 1 -b 16 -e signed
#                                  /tmp/out.wav trim 0 N`. Optional fallback;
#                                  not usually present without `apt install sox`.
#   4. (silent fallback)      -- when none of the above are on PATH OR no
#                                audio device is available (no /dev/snd AND
#                                no PulseAudio socket), write a deterministic
#                                N-second silent WAV: 44-byte RIFF/WAVE/PCM
#                                header + N * 16000 * 2 zero bytes. Exit 0.
#                                Lets the framework run end-to-end on a
#                                sealed sandbox (CI, container, headless)
#                                without crashing; a real deployment with
#                                hardware "just works" because the higher
#                                priority backends fire first.
#
# Contract (the seam relies on this):
#   * Reads `$1` as the destination WAV path (default /tmp/ce_input.wav).
#   * Reads `$2` as the capture duration in SECONDS (default 5; clamped
#     to [1..30] so a runaway env never hangs the daemon).
#   * Prints exactly ONE line to stdout: the absolute destination path.
#   * Exits 0 on success AND on the silent-fallback path. Exits 2 only
#     on a malformed numeric duration (programmer error, distinct from
#     the runtime backend miss).
#   * Diagnostics go to stderr -- caller may capture or discard.
#
# Usage:
#   scripts/audio_capture.sh                      # default: 5s -> /tmp/ce_input.wav
#   scripts/audio_capture.sh /tmp/foo.wav         # custom path, 5s
#   scripts/audio_capture.sh /tmp/foo.wav 1       # 1-second capture
#
# The output is ALWAYS:
#   * 16-bit signed little-endian PCM
#   * mono (1 channel)
#   * 16000 Hz sample rate
#   * 44-byte canonical RIFF/WAVE/PCM header
# matching what `audio_capture_to_pcm` in audio_capture.nova parses.

set -uo pipefail

case "${1:-}" in
    -h|--help)
        echo "usage: $0 [<out-wav-path>] [<duration-seconds>]"
        echo "  Captures audio from the default microphone for N seconds"
        echo "  (default 5) into a 16-bit mono 16kHz WAV at <out-wav-path>"
        echo "  (default /tmp/ce_input.wav). Detects parecord/arecord/sox;"
        echo "  falls back to a deterministic silent WAV on a headless"
        echo "  sandbox so the framework end-to-end keeps working."
        echo
        echo "  Prints the destination path to stdout. Exits 0 on success"
        echo "  and on the silent-fallback path."
        exit 0
        ;;
esac

DST="${1:-/tmp/ce_input.wav}"
DUR="${2:-5}"

# Clamp duration to [1..30] seconds. A bad-arg path is operator error.
case "$DUR" in
    ''|*[!0-9]*)
        echo "ERROR: duration '$DUR' is not a positive integer" >&2
        exit 2
        ;;
esac
if [ "$DUR" -lt 1 ]; then DUR=1; fi
if [ "$DUR" -gt 30 ]; then DUR=30; fi

SAMPLE_RATE=16000
CHANNELS=1
BITS=16

# --- Detect whether an audio device is even plausibly present ---------------
# Two paths in 2026 Linux: ALSA (/dev/snd) or PulseAudio/pipewire-pulse
# (the per-user socket). If NEITHER is present, the silent fallback is
# guaranteed to be the right path -- even if `parecord` / `arecord` are
# on PATH they would fail at runtime. Documented so the operator can
# diagnose "why am I getting silence on this hardware?".
have_audio_device() {
    if [ -d /dev/snd ]; then return 0; fi
    if [ -n "${PULSE_SERVER:-}" ]; then return 0; fi
    if [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -S "$XDG_RUNTIME_DIR/pulse/native" ]; then return 0; fi
    if [ -S "/run/user/$(id -u 2>/dev/null)/pulse/native" ]; then return 0; fi
    return 1
}

# --- Mode 1: parecord (PulseAudio / pipewire-pulse) -------------------------
# parecord with --file-format=wav emits a canonical WAV (no separate
# format negotiation). The shape matches the parameter set this script
# documents (s16le / 16000 Hz / mono). `timeout` SIGTERMs at N seconds
# -- parecord's own -d flag depends on the version; using timeout is
# portable.
if command -v parecord >/dev/null 2>&1 && have_audio_device; then
    if timeout "$DUR" parecord \
            --format=s16le \
            --rate="$SAMPLE_RATE" \
            --channels="$CHANNELS" \
            --file-format=wav \
            -d default \
            "$DST" >/dev/null 2>&1; then
        if [ -s "$DST" ]; then
            echo "$DST"
            exit 0
        fi
    fi
    # SIGTERM (143) on a successful capture is normal -- timeout fired.
    # The file is still valid if it grew.
    if [ -s "$DST" ]; then
        echo "$DST"
        exit 0
    fi
    echo "WARN: parecord did not produce a non-empty WAV; trying next backend" >&2
fi

# --- Mode 2: arecord (ALSA) -------------------------------------------------
# arecord has a native -d (duration in seconds) flag -- we still wrap
# in timeout for belt-and-braces against an arecord build that ignores
# -d in some edge case (the seam contract is "exit at most after N+1 s").
if command -v arecord >/dev/null 2>&1 && have_audio_device; then
    if timeout "$((DUR + 1))" arecord \
            -q \
            -f S16_LE \
            -r "$SAMPLE_RATE" \
            -c "$CHANNELS" \
            -d "$DUR" \
            "$DST" >/dev/null 2>&1; then
        if [ -s "$DST" ]; then
            echo "$DST"
            exit 0
        fi
    fi
    echo "WARN: arecord did not produce a non-empty WAV; trying next backend" >&2
fi

# --- Mode 3: sox -d (PortAudio under the hood, optional on Linux) ----------
# `sox -d <out>` reads from the default capture device; `trim 0 N` caps
# duration. Less common than parecord/arecord on stock distros but it's
# the canonical macOS path so this fallback covers more deployments.
if command -v sox >/dev/null 2>&1 && have_audio_device; then
    if timeout "$((DUR + 1))" sox -q \
            -d \
            -r "$SAMPLE_RATE" \
            -c "$CHANNELS" \
            -b "$BITS" \
            -e signed-integer \
            "$DST" trim 0 "$DUR" >/dev/null 2>&1; then
        if [ -s "$DST" ]; then
            echo "$DST"
            exit 0
        fi
    fi
    echo "WARN: sox -d did not produce a non-empty WAV; trying silent fallback" >&2
fi

# --- Mode 4: silent-WAV fallback --------------------------------------------
# No usable backend OR no device. Emit a deterministic N-second silent
# WAV so the downstream seam still has bytes to parse and the framework
# runs end-to-end. The header is the same 44-byte canonical layout the
# pure-NOVA `audio_capture_to_pcm` parses; the body is N * SR * 2 zero
# bytes (PCM16 silence). Exit 0: a sealed sandbox is a runtime condition,
# not a programmer error.
echo "INFO: no audio-capture backend on PATH (tried: parecord, arecord, sox)." >&2
echo "INFO: writing ${DUR}s silent WAV to $DST." >&2

N_SAMPLES=$((SAMPLE_RATE * DUR))
DATA_SIZE=$((N_SAMPLES * 2))
TOTAL_RIFF_SIZE=$((36 + DATA_SIZE))

# Compose the 44-byte canonical PCM16 mono WAV header in shell.
# Writing little-endian 32-bit integers via printf's \x escapes.
write_le_u32() {
    local v=$1
    local b0=$((v & 0xff))
    local b1=$(((v >> 8) & 0xff))
    local b2=$(((v >> 16) & 0xff))
    local b3=$(((v >> 24) & 0xff))
    printf '\\x%02x\\x%02x\\x%02x\\x%02x' "$b0" "$b1" "$b2" "$b3"
}
write_le_u16() {
    local v=$1
    local b0=$((v & 0xff))
    local b1=$(((v >> 8) & 0xff))
    printf '\\x%02x\\x%02x' "$b0" "$b1"
}

BYTE_RATE=$((SAMPLE_RATE * CHANNELS * BITS / 8))
BLOCK_ALIGN=$((CHANNELS * BITS / 8))

# Header (44 bytes): RIFF + size + WAVE + fmt + 16 + 1(PCM) + chan + sr +
# byte_rate + block_align + bps + data + data_size
HDR_FMT="RIFF$(write_le_u32 "$TOTAL_RIFF_SIZE")WAVEfmt $(write_le_u32 16)"
HDR_FMT="${HDR_FMT}$(write_le_u16 1)$(write_le_u16 "$CHANNELS")"
HDR_FMT="${HDR_FMT}$(write_le_u32 "$SAMPLE_RATE")$(write_le_u32 "$BYTE_RATE")"
HDR_FMT="${HDR_FMT}$(write_le_u16 "$BLOCK_ALIGN")$(write_le_u16 "$BITS")"
HDR_FMT="${HDR_FMT}data$(write_le_u32 "$DATA_SIZE")"

# Atomic write: header to tmp, append zeros, mv into place. Using
# /dev/zero | head -c DATA_SIZE for the silence body -- no per-byte loop
# in shell (which would be glacially slow at 5s * 16000 samp/s * 2B).
TMP="${DST}.tmp.$$"
{
    printf '%b' "$HDR_FMT"
    head -c "$DATA_SIZE" /dev/zero
} > "$TMP"

# Sanity: the file should be exactly 44 + DATA_SIZE bytes.
WANT_BYTES=$((44 + DATA_SIZE))
GOT_BYTES=$(wc -c < "$TMP" 2>/dev/null || echo 0)
if [ "$GOT_BYTES" -ne "$WANT_BYTES" ]; then
    echo "WARN: silent WAV is $GOT_BYTES bytes, expected $WANT_BYTES" >&2
fi

mv -f "$TMP" "$DST"
echo "$DST"
exit 0
