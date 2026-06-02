#!/usr/bin/env bash
# Scenario HHH -- R14E: Schroeder reverb + noise gate (audio DSP effects).

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

it_section "scenario HHH: R14E DSP effects (reverb + noise gate)"

NOVA_BIN="${NOVA_ROOT:-/home/user/NOVA}/nova"
if [ ! -x "$NOVA_BIN" ]; then
    printf "  ${C_RED}ERROR${C_RST}: NOVA launcher not found at %s (set NOVA_ROOT)\n" "$NOVA_BIN" >&2
    FAIL=$((FAIL+1))
    summary "scenario_hhh_dsp"
    exit $?
fi

VOWEL_WAV="/tmp/ce_scenario_hhh_vowel.wav"
REVERB_WAV="/tmp/ce_scenario_hhh_reverb.wav"
NOISY_WAV="/tmp/ce_scenario_hhh_noisy.wav"
GATE_WAV="/tmp/ce_scenario_hhh_gate.wav"
DRV_DIR="$REPO_ROOT/tests/integration/_scenario_hhh_drivers"
DRV_SRC="$DRV_DIR/dsp_pipeline_driver.nova"
DRV_OUT="/tmp/ce_scenario_hhh_driver.out"

mkdir -p "$DRV_DIR"
trap 'rm -f "$VOWEL_WAV" "$REVERB_WAV" "$NOISY_WAV" "$GATE_WAV" "$DRV_OUT"; rm -rf "$DRV_DIR"' EXIT

cat > "$DRV_SRC" <<'NOVA'
import "std/syscall"
import "../../../src/io/effectors/audio_synth.nova"
import "../../../src/io/transducers/audio_capture.nova"
import "../../../src/io/transducers/audio_dsp.nova"

// Compose a short utterance from Klatt phonemes (ae + sine padding so the
// signal has enough length for the reverb's IR to ring).
fn _build_vowel() {
    let v = synth_phoneme("ae")
    let tail = synth_sine(150, 800, 8000)
    let out = list_new()
    let i = 0
    while i < len(v) {
        push(out, v[i])
        i = i + 1
    }
    let j = 0
    while j < len(tail) {
        push(out, tail[j])
        j = j + 1
    }
    return out
}

// A low-level noisy fixture: amplitude 400 (~ -38 dBFS) square wave.
// Below the default gate threshold of 100 milli (~3275 units), so the gate
// should clamp it nearly to silence.
fn _build_noisy() {
    let out = list_new()
    let n = 2400
    let i = 0
    while i < n {
        if (i - (i / 2) * 2) == 0 { push(out, 400) }
        else { push(out, 0 - 400) }
        i = i + 1
    }
    return out
}

fn main() {
    let vowel = _build_vowel()
    let ok_v = audio_write_wav(vowel, "/tmp/ce_scenario_hhh_vowel.wav")
    println("wrote vowel wav: " + int_to_str(ok_v))
    println("VOWEL samples=" + int_to_str(len(vowel))
        + " rms=" + int_to_str(dsp_rms(vowel)))

    let reverbed = dsp_reverb(vowel, 8000, 400, 700)
    let ok_r = audio_write_wav(reverbed, "/tmp/ce_scenario_hhh_reverb.wav")
    println("wrote reverb wav: " + int_to_str(ok_r))
    println("REVERB samples=" + int_to_str(len(reverbed))
        + " rms=" + int_to_str(dsp_rms(reverbed)))

    let noisy = _build_noisy()
    let ok_n = audio_write_wav(noisy, "/tmp/ce_scenario_hhh_noisy.wav")
    println("wrote noisy wav: " + int_to_str(ok_n))
    println("NOISY samples=" + int_to_str(len(noisy))
        + " rms=" + int_to_str(dsp_rms(noisy)))

    let gated = dsp_noise_gate(noisy, 8000, 100, 1000, 5, 50)
    let ok_g = audio_write_wav(gated, "/tmp/ce_scenario_hhh_gate.wav")
    println("wrote gate wav: " + int_to_str(ok_g))
    println("GATE samples=" + int_to_str(len(gated))
        + " rms=" + int_to_str(dsp_rms(gated)))
}

main()
NOVA

DRIVER_OUT=$("$NOVA_BIN" run "$DRV_SRC" 2>&1)
DRIVER_RC=$?
printf '%s\n' "$DRIVER_OUT" > "$DRV_OUT"

assert_eq "$DRIVER_RC" "0" "dsp pipeline driver exits 0"
assert_match "$DRIVER_OUT" "wrote vowel wav: 1"  "vowel WAV written"
assert_match "$DRIVER_OUT" "wrote reverb wav: 1" "reverb WAV written"
assert_match "$DRIVER_OUT" "wrote noisy wav: 1"  "noisy WAV written"
assert_match "$DRIVER_OUT" "wrote gate wav: 1"   "gate WAV written"

assert_file_exists "$VOWEL_WAV"  "vowel WAV exists on disk"
assert_file_exists "$REVERB_WAV" "reverb WAV exists on disk"
assert_file_exists "$NOISY_WAV"  "noisy WAV exists on disk"
assert_file_exists "$GATE_WAV"   "gate WAV exists on disk"

# Reverb preserves RMS to within a generous band: the tail adds zero-padded
# silence which dilutes the average, but the IR also adds reflection
# energy. With wet=40% and a 400 ms tail on a 2000-sample input, the wet
# RMS should land in roughly 30..120% of the dry RMS.
VOWEL_RMS=$(echo "$DRIVER_OUT" | grep -E '^VOWEL '  | grep -oE 'rms=[0-9]+' | head -1 | cut -d= -f2)
REVERB_RMS=$(echo "$DRIVER_OUT" | grep -E '^REVERB ' | grep -oE 'rms=[0-9]+' | head -1 | cut -d= -f2)
if [ -n "$VOWEL_RMS" ] && [ -n "$REVERB_RMS" ] && [ "$REVERB_RMS" -gt 0 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  reverb output has non-zero RMS (got %s, dry=%s)\n" "$REVERB_RMS" "$VOWEL_RMS"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  reverb output RMS empty or zero (rms='%s', dry='%s')\n" "$REVERB_RMS" "$VOWEL_RMS"
fi

# Gate attenuates the noise floor: input RMS ~400 PCM16, gated RMS should
# be substantially below it (the default threshold of 10% FS = 3275 units
# is well above 400, so the gate stays closed).
NOISY_RMS=$(echo "$DRIVER_OUT" | grep -E '^NOISY ' | grep -oE 'rms=[0-9]+' | head -1 | cut -d= -f2)
GATE_RMS=$(echo "$DRIVER_OUT" | grep -E '^GATE '  | grep -oE 'rms=[0-9]+' | head -1 | cut -d= -f2)
if [ -n "$NOISY_RMS" ] && [ -n "$GATE_RMS" ] && [ "$NOISY_RMS" -ge 350 ] && [ "$NOISY_RMS" -le 450 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  noisy input RMS in [350..450] (got %s)\n" "$NOISY_RMS"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  noisy input RMS out of range (got '%s')\n" "$NOISY_RMS"
fi
# 10x attenuation: gate RMS << input RMS (the gate ratio=1000 collapses the
# below-threshold gain to zero; the only residual energy is from the release
# ramp at the start of the buffer).
if [ -n "$GATE_RMS" ] && [ "$GATE_RMS" -lt 200 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  gate attenuates noise floor (rms=%s < 200)\n" "$GATE_RMS"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  gate did not attenuate noise floor (rms='%s')\n" "$GATE_RMS"
fi

require_chat

CHAT_HELP=$(run_chat "/help")
assert_match "$CHAT_HELP" '/reverb' \
    "chat /help advertises the new /reverb command"
assert_match "$CHAT_HELP" '/gate' \
    "chat /help advertises the new /gate command"
assert_match "$CHAT_HELP" 'R14E' \
    "chat /help labels the DSP commands as R14E"

CHAT_REVERB=$(run_chat "/reverb $VOWEL_WAV 400")
assert_match "$CHAT_REVERB" 'wet=400' \
    "chat /reverb reports wet=400"
assert_match "$CHAT_REVERB" "$VOWEL_WAV" \
    "chat /reverb echoes the WAV path"
assert_match "$CHAT_REVERB" 'rms=' \
    "chat /reverb reports input/output RMS"

CHAT_GATE=$(run_chat "/gate $NOISY_WAV 100")
assert_match "$CHAT_GATE" 'threshold=100' \
    "chat /gate reports threshold=100"
assert_match "$CHAT_GATE" "$NOISY_WAV" \
    "chat /gate echoes the WAV path"

CHAT_REVERB_NOARG=$(run_chat "/reverb")
assert_match "$CHAT_REVERB_NOARG" '/reverb needs PATH' \
    "chat /reverb with no arg prints usage"

CHAT_REVERB_MISS=$(run_chat "/reverb /tmp/ce_scenario_hhh_nonexistent.wav 300")
assert_match "$CHAT_REVERB_MISS" 'reverb FAILED' \
    "chat /reverb on missing WAV -> graceful FAILED"

CHAT_GATE_MISS=$(run_chat "/gate /tmp/ce_scenario_hhh_nonexistent.wav 100")
assert_match "$CHAT_GATE_MISS" 'gate FAILED' \
    "chat /gate on missing WAV -> graceful FAILED"

summary "scenario_hhh_dsp"
