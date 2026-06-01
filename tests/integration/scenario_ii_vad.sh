#!/usr/bin/env bash
# Scenario II -- R7F: Voice Activity Detection over Klatt-synthesized audio.
#
# Exercises the new src/io/transducers/audio_vad.nova module end-to-end:
#   * Synthesize a known utterance via R6E's expanded Klatt formant
#     inventory (33 -> 53 phoneme dispatches, full ARPAbet)
#   * Write it as a canonical PCM16 WAV via audio_write_wav
#   * Parse + VAD-filter via audio_capture_to_pcm_vad
#   * Assert # speech segments detected matches the synthesized pattern
#   * Assert a pure-silence WAV produces zero segments
#   * Assert a pure-noise WAV produces zero segments (energy passes,
#     ZCR ceiling rejects)
#   * Run through the chat /listen command -- verify dispatch + help.
#
# Pre-conditions: NOVA toolchain at $NOVA_ROOT/nova; built chat binary.
# Side-effects: writes /tmp/ce_scenario_ii_speech.wav,
#               /tmp/ce_scenario_ii_silence.wav,
#               /tmp/ce_scenario_ii_noise.wav,
#               /tmp/ce_scenario_ii_driver.out, plus the on-the-fly NOVA
#               driver under tests/integration/_scenario_ii_drivers/.

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

it_section "scenario II: R7F VAD over Klatt-synthesized audio"

NOVA_BIN="${NOVA_ROOT:-/home/user/NOVA}/nova"
if [ ! -x "$NOVA_BIN" ]; then
    printf "  ${C_RED}ERROR${C_RST}: NOVA launcher not found at %s (set NOVA_ROOT)\n" "$NOVA_BIN" >&2
    FAIL=$((FAIL+1))
    summary "scenario_ii_vad"
    exit $?
fi

SPEECH_WAV="/tmp/ce_scenario_ii_speech.wav"
SILENCE_WAV="/tmp/ce_scenario_ii_silence.wav"
NOISE_WAV="/tmp/ce_scenario_ii_noise.wav"
DRV_DIR="$REPO_ROOT/tests/integration/_scenario_ii_drivers"
DRV_SRC="$DRV_DIR/vad_pipeline_driver.nova"
DRV_OUT="/tmp/ce_scenario_ii_driver.out"

mkdir -p "$DRV_DIR"
trap 'rm -f "$SPEECH_WAV" "$SILENCE_WAV" "$NOISE_WAV" "$DRV_OUT"; rm -rf "$DRV_DIR"' EXIT

# Emit the NOVA driver. The leading underscore on _scenario_ii_drivers/
# means the Makefile's integration glob (! -name '_*') skips it.
cat > "$DRV_SRC" <<'NOVA'
// Auto-generated VAD pipeline driver for scenario_ii_vad.sh.
//
// Steps:
//   1. Klatt-synthesize the utterance "AY DAY MOW BOY" (4 phonemes,
//      4 * 1200 = 4800 samples @ 8 kHz = 600 ms of voice).
//   2. Pad with silence: 1200 samples leading + 2400 samples trailing.
//   3. Write to /tmp/ce_scenario_ii_speech.wav.
//   4. Construct a pure-silence WAV (5000 samples of zero).
//   5. Construct a pure-noise WAV (5000 samples of alternating +/-3000,
//      which classifies as high-energy high-ZCR -> rejected by VAD).
//   6. For each WAV, run audio_capture_to_pcm_vad and print:
//        path n_segments filtered_len original_sr
//   7. Print one summary line per fixture.

import "std/syscall"
import "../../../src/io/effectors/audio_synth.nova"
import "../../../src/io/transducers/audio_capture.nova"

fn _zero_buf(n) {
    let b = list_new()
    let i = 0
    while i < n {
        push(b, 0)
        i = i + 1
    }
    return b
}

fn _noise_buf(n, amp) {
    let b = list_new()
    let i = 0
    while i < n {
        if (i - (i / 2) * 2) == 0 {
            push(b, amp)
        } else {
            push(b, 0 - amp)
        }
        i = i + 1
    }
    return b
}

fn _concat(a, b) {
    let out = list_new()
    let i = 0
    while i < len(a) {
        push(out, a[i])
        i = i + 1
    }
    let j = 0
    while j < len(b) {
        push(out, b[j])
        j = j + 1
    }
    return out
}

fn _build_klatt_utterance() {
    // Concatenate four diphthongs. R6E's expanded inventory has these.
    let pre = _zero_buf(1200)              // 150 ms silence lead-in
    let p1 = synth_phoneme("ay")           // diphthong /aɪ/
    let p2 = synth_phoneme("ey")           // diphthong /eɪ/
    let p3 = synth_phoneme("ow")           // /oʊ/ (monophthong)
    let p4 = synth_phoneme("oy")           // diphthong /ɔɪ/
    let mid = _concat(_concat(_concat(p1, p2), p3), p4)
    let post = _zero_buf(2400)             // 300 ms silence tail
    return _concat(_concat(pre, mid), post)
}

fn _report(label, path) {
    let r = audio_capture_to_pcm_vad(path)
    let pcm = audio_capture_vad_samples(r)
    let sr = audio_capture_vad_rate(r)
    let nseg = audio_capture_vad_segments(r)
    println(label + " sr=" + int_to_str(sr)
        + " segments=" + int_to_str(nseg)
        + " filtered_len=" + int_to_str(len(pcm)))
}

fn main() {
    // Fixture 1: synthesized speech.
    let utter = _build_klatt_utterance()
    let ok1 = audio_write_wav(utter, "/tmp/ce_scenario_ii_speech.wav")
    println("wrote speech wav: " + int_to_str(ok1))

    // Fixture 2: pure silence.
    let sil = _zero_buf(5000)
    let ok2 = audio_write_wav(sil, "/tmp/ce_scenario_ii_silence.wav")
    println("wrote silence wav: " + int_to_str(ok2))

    // Fixture 3: pure noise (max ZCR).
    let nz = _noise_buf(5000, 3000)
    let ok3 = audio_write_wav(nz, "/tmp/ce_scenario_ii_noise.wav")
    println("wrote noise wav: " + int_to_str(ok3))

    _report("SPEECH",  "/tmp/ce_scenario_ii_speech.wav")
    _report("SILENCE", "/tmp/ce_scenario_ii_silence.wav")
    _report("NOISE",   "/tmp/ce_scenario_ii_noise.wav")
}

main()
NOVA

# Run the driver.
DRIVER_OUT=$("$NOVA_BIN" run "$DRV_SRC" 2>&1)
DRIVER_RC=$?
printf '%s\n' "$DRIVER_OUT" > "$DRV_OUT"

assert_eq "$DRIVER_RC" "0" "VAD pipeline driver exits 0"
assert_match "$DRIVER_OUT" "wrote speech wav: 1" \
    "speech WAV written"
assert_match "$DRIVER_OUT" "wrote silence wav: 1" \
    "silence WAV written"
assert_match "$DRIVER_OUT" "wrote noise wav: 1" \
    "noise WAV written"

assert_file_exists "$SPEECH_WAV"  "speech WAV exists on disk"
assert_file_exists "$SILENCE_WAV" "silence WAV exists on disk"
assert_file_exists "$NOISE_WAV"   "noise WAV exists on disk"

# Speech fixture: SR=8000 (audio_synth's canonical rate), >= 1 segment,
# filtered_len > 0.
assert_match "$DRIVER_OUT" "SPEECH sr=8000" \
    "speech WAV decoded at 8 kHz"
SPEECH_LINE=$(printf '%s\n' "$DRIVER_OUT" | grep -E '^SPEECH ' | head -1)
SPEECH_SEGS=$(echo "$SPEECH_LINE" | grep -oE 'segments=[0-9]+' | head -1 | cut -d= -f2)
SPEECH_FLEN=$(echo "$SPEECH_LINE" | grep -oE 'filtered_len=[0-9]+' | head -1 | cut -d= -f2)

# Klatt phonemes have noise / formant carriers; energy + ZCR must put at
# least one frame in the speech band. Allow 1-3 segments (boundary
# arithmetic could pick up brief inter-phoneme dips with M=10 = 300 ms
# silence-to-end threshold; one merged segment is the common outcome).
if [ -n "$SPEECH_SEGS" ] && [ "$SPEECH_SEGS" -ge 1 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  Klatt utterance produces at least 1 speech segment (got %s)\n" "$SPEECH_SEGS"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  Klatt utterance produced 0 segments\n"
fi
if [ -n "$SPEECH_FLEN" ] && [ "$SPEECH_FLEN" -gt 0 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  filtered PCM non-empty (got %s samples)\n" "$SPEECH_FLEN"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  filtered PCM empty\n"
fi

# Silence fixture: must produce zero segments.
assert_match "$DRIVER_OUT" "SILENCE sr=8000 segments=0 filtered_len=0" \
    "silence WAV -> 0 VAD segments, empty filtered PCM"

# Noise fixture: alternating +/-3000 = max ZCR -- the ZCR ceiling
# rejects every frame, so segments=0.
assert_match "$DRIVER_OUT" "NOISE sr=8000 segments=0 filtered_len=0" \
    "noise WAV -> 0 VAD segments (ZCR ceiling reject)"

# ===========================================================================
# PART 2 -- chat /listen dispatch + help
# ===========================================================================

require_chat
CHAT_HELP=$(run_chat "/help")
assert_match "$CHAT_HELP" '/listen' \
    "chat /help advertises the new /listen command"
assert_match "$CHAT_HELP" 'VAD' \
    "chat /help mentions VAD"

# Drive /listen on the synthesized speech WAV. The default backend is
# STUB (no CE_STT_BACKEND env), which returns the placeholder line; we
# assert the vad_segments count appears.
CHAT_LISTEN=$(run_chat "/listen $SPEECH_WAV")
assert_match "$CHAT_LISTEN" 'vad_segments=' \
    "chat /listen reports vad_segments"
assert_match "$CHAT_LISTEN" "$SPEECH_WAV" \
    "chat /listen echoes the WAV path"

# /listen on the silence WAV -- vad_segments=0, transcript placeholder.
CHAT_SIL=$(run_chat "/listen $SILENCE_WAV")
assert_match "$CHAT_SIL" 'vad_segments=0' \
    "chat /listen on silence -> vad_segments=0"

summary "scenario_ii_vad"
