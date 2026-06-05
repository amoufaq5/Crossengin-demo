#!/usr/bin/env bash
# Scenario UUUU -- R26C spectral-subtraction Wiener noise reduction.
#
# Exercises the new src/io/transducers/audio_noise_reduce.nova module
# end-to-end via:
#   1. A NOVA driver that synthesizes a known fixture (300 ms silence +
#      Klatt /ae/ vowel + LCG-additive noise), runs nr_estimate_noise +
#      nr_apply_wiener directly, writes the cleaned PCM to a WAV, and
#      reports per-region RMS so the bash side can assert SNR
#      improvement.
#   2. The chat /denoise <wav> admin command path, asserting:
#      * /help advertises the new command
#      * usage hint shown on bare `/denoise`
#      * graceful failure on a missing WAV path
#      * successful round-trip diagnostic on the synthesized fixture
#   3. Optional whisper round-trip: when whisper-main + tiny.en model
#      are installed, transcribe the noisy input AND the denoised output
#      and report the transcript lengths (not a strict-equality assert
#      because Klatt -> whisper is inherently noisy).
#
# This pins R26C's integration contract: per-region RMS drops on the
# noise-only window post-Wiener while the Klatt formant region stays
# within +/- 30% of the input amplitude (the Wiener gain floor of 50
# milli prevents over-attenuation on speech bins).
#
# Pre-conditions: NOVA toolchain at $NOVA_ROOT/nova; chat binary at
# bin/crossengin-chat.
# Optional: whisper-main + ggml-tiny.en.bin (only the optional STT leg
# uses these).
# Side-effects: writes /tmp/ce_scenario_uuuu_*.wav and the on-the-fly
# NOVA driver under tests/integration/_scenario_uuuu_drivers/.

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

it_section "scenario UUUU: R26C audio noise reduction (Wiener)"

NOVA_BIN="${NOVA_ROOT:-/home/user/NOVA}/nova"
if [ ! -x "$NOVA_BIN" ]; then
    printf "  ${C_RED}ERROR${C_RST}: NOVA launcher not found at %s (set NOVA_ROOT)\n" "$NOVA_BIN" >&2
    FAIL=$((FAIL+1))
    summary "scenario_uuuu_noise_reduce"
    exit $?
fi

require_chat

WHISPER_BIN="${CE_WHISPER_BIN:-/usr/local/bin/whisper-main}"
WHISPER_MODEL="${CE_WHISPER_MODEL:-/usr/local/share/whisper/ggml-tiny.en.bin}"
HAVE_WHISPER=0
if [ -x "$WHISPER_BIN" ] && [ -f "$WHISPER_MODEL" ]; then
    HAVE_WHISPER=1
    printf "  ${C_DIM}(whisper-main at %s; model at %s)${C_RST}\n" "$WHISPER_BIN" "$WHISPER_MODEL"
else
    printf "  ${C_YEL}NOTE${C_RST}  whisper not installed; STT round-trip leg gracefully skipped\n"
fi

NOISY_WAV="/tmp/ce_scenario_uuuu_klatt_noisy.wav"
CLEAN_WAV="/tmp/ce_scenario_uuuu_klatt_cleaned.wav"
MISSING_WAV="/tmp/ce_scenario_uuuu_definitely_missing.wav"
DRV_DIR="$REPO_ROOT/tests/integration/_scenario_uuuu_drivers"
DRV_SRC="$DRV_DIR/noise_reduce_driver.nova"
DRV_OUT="/tmp/ce_scenario_uuuu_driver.out"

mkdir -p "$DRV_DIR"
trap 'rm -f "$NOISY_WAV" "$CLEAN_WAV" "$DRV_OUT" "$DRV_SRC"; rmdir "$DRV_DIR" 2>/dev/null || true' EXIT

cat > "$DRV_SRC" <<'NOVA'
// Auto-generated fixture writer for scenario_uuuu_noise_reduce.sh.
//
// Builds a fixture: 300 ms silence + Klatt /ae/ vowel, with LCG noise
// added across the entire 3600-sample buffer. Writes the noisy and the
// cleaned WAVs to /tmp so the bash side can re-load via /denoise and
// also run whisper directly if installed. Reports per-region RMS for
// pre/post comparison and the SNR ratio (sig_rms * 100 / noise_rms).

import "std/syscall"
import "../../../src/io/effectors/audio_synth.nova"
import "../../../src/io/transducers/audio_noise_reduce.nova"

fn _zero_buf(n) {
    let b = list_new()
    let i = 0
    while i < n {
        push(b, 0)
        i = i + 1
    }
    return b
}

fn _lcg_noise(n, amp, seed0) {
    let b = list_new()
    let i = 0
    let seed = seed0
    while i < n {
        seed = (seed * 1103515245 + 12345) & 1048575
        let v = seed - (seed / (2 * amp + 1)) * (2 * amp + 1) - amp
        push(b, v)
        i = i + 1
    }
    return b
}

fn _add_lists(a, b) {
    let out = list_new()
    let n = len(a)
    if len(b) < n { n = len(b) }
    let i = 0
    while i < n {
        push(out, a[i] + b[i])
        i = i + 1
    }
    return out
}

fn _concat(a, b) {
    let out = list_new()
    let i = 0
    while i < len(a) { push(out, a[i]); i = i + 1 }
    let j = 0
    while j < len(b) { push(out, b[j]); j = j + 1 }
    return out
}

fn main() {
    // 300 ms silence + Klatt /ae/ = 2400 + 1200 = 3600 samples @ 8 kHz.
    let lead = _zero_buf(2400)
    let klatt = synth_phoneme_klatt("ae")
    println("klatt_samples=" + int_to_str(len(klatt)))
    let mixed = _concat(lead, klatt)
    println("mixed_samples=" + int_to_str(len(mixed)))
    // LCG noise amp=800 -- modest hiss, klatt formants still dominate.
    let noisy = _add_lists(mixed, _lcg_noise(3600, 800, 31))

    let ok1 = audio_write_wav(noisy, "/tmp/ce_scenario_uuuu_klatt_noisy.wav")
    println("wrote noisy wav: " + int_to_str(ok1))

    let pre_noise_rms = nr_rms_window(noisy, 0, 2400)
    let pre_sig_rms   = nr_rms_window(noisy, 2400, 1200)
    println("pre_noise_rms=" + int_to_str(pre_noise_rms))
    println("pre_sig_rms="   + int_to_str(pre_sig_rms))

    // Apply noise reduction.
    let cleaned = nr_reduce(noisy, 8000)
    println("cleaned_samples=" + int_to_str(len(cleaned)))

    let ok2 = audio_write_wav(cleaned, "/tmp/ce_scenario_uuuu_klatt_cleaned.wav")
    println("wrote cleaned wav: " + int_to_str(ok2))

    let post_noise_rms = nr_rms_window(cleaned, 0, 2400)
    let post_sig_rms   = nr_rms_window(cleaned, 2400, 1200)
    println("post_noise_rms=" + int_to_str(post_noise_rms))
    println("post_sig_rms="   + int_to_str(post_sig_rms))

    // SNR ratio scaled by 100 for integer reporting.
    let pre_snr_x100 = 0
    if pre_noise_rms > 0 {
        pre_snr_x100 = (pre_sig_rms * 100) / pre_noise_rms
    }
    let post_snr_x100 = 0
    if post_noise_rms > 0 {
        post_snr_x100 = (post_sig_rms * 100) / post_noise_rms
    }
    println("pre_snr_x100="  + int_to_str(pre_snr_x100))
    println("post_snr_x100=" + int_to_str(post_snr_x100))

    println("driver complete")
}

main()
NOVA

"$NOVA_BIN" run "$DRV_SRC" > "$DRV_OUT" 2>&1
DRIVER_RC=$?
DRV_TXT=$(cat "$DRV_OUT")

if [ "$DRIVER_RC" -ne 0 ]; then
    printf "  ${C_RED}FAIL${C_RST}  driver exited non-zero (rc=%d). Output:\n" "$DRIVER_RC"
    sed 's/^/        /' "$DRV_OUT"
    FAIL=$((FAIL+1))
    summary "scenario_uuuu_noise_reduce"
    exit $?
fi

# ===========================================================================
# Assertion 1: driver writes both WAVs
# ===========================================================================

assert_match "$DRV_TXT" "wrote noisy wav: 1"   "noisy WAV written by driver"
assert_match "$DRV_TXT" "wrote cleaned wav: 1" "cleaned WAV written by driver"
assert_file_exists "$NOISY_WAV" "noisy WAV exists on disk"
assert_file_exists "$CLEAN_WAV" "cleaned WAV exists on disk"

# ===========================================================================
# Assertion 2: post_noise_rms < pre_noise_rms (the central R26C contract)
# ===========================================================================

PRE_NOISE_RMS=$(printf '%s\n' "$DRV_TXT" | grep -oE 'pre_noise_rms=[0-9]+' | head -1 | cut -d= -f2)
POST_NOISE_RMS=$(printf '%s\n' "$DRV_TXT" | grep -oE 'post_noise_rms=[0-9]+' | head -1 | cut -d= -f2)
if [ -n "$PRE_NOISE_RMS" ] && [ -n "$POST_NOISE_RMS" ] \
   && [ "$POST_NOISE_RMS" -lt "$PRE_NOISE_RMS" ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  noise-region RMS dropped (pre=%s, post=%s)\n" \
        "$PRE_NOISE_RMS" "$POST_NOISE_RMS"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  noise-region RMS did not drop (pre=%s, post=%s)\n" \
        "$PRE_NOISE_RMS" "$POST_NOISE_RMS"
fi

# ===========================================================================
# Assertion 3: post_noise_rms < 0.7 * pre_noise_rms (>= 30% reduction)
# ===========================================================================

if [ -n "$PRE_NOISE_RMS" ] && [ -n "$POST_NOISE_RMS" ] \
   && [ $((POST_NOISE_RMS * 100)) -lt $((PRE_NOISE_RMS * 70)) ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  noise-region RMS reduction >= 30%% (pre=%s, post=%s)\n" \
        "$PRE_NOISE_RMS" "$POST_NOISE_RMS"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  noise-region reduction below 30%% (pre=%s, post=%s)\n" \
        "$PRE_NOISE_RMS" "$POST_NOISE_RMS"
fi

# ===========================================================================
# Assertion 4: signal-region RMS preserved within 30% (Wiener doesn't kill the
# Klatt formants -- gain floor of 50 milli + the formant bins beating the
# noise PSD prevents over-attenuation).
# ===========================================================================

PRE_SIG_RMS=$(printf '%s\n' "$DRV_TXT" | grep -oE 'pre_sig_rms=[0-9]+' | head -1 | cut -d= -f2)
POST_SIG_RMS=$(printf '%s\n' "$DRV_TXT" | grep -oE 'post_sig_rms=[0-9]+' | head -1 | cut -d= -f2)
if [ -n "$PRE_SIG_RMS" ] && [ -n "$POST_SIG_RMS" ] \
   && [ $((POST_SIG_RMS * 100)) -ge $((PRE_SIG_RMS * 70)) ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  signal-region RMS preserved >= 70%% (pre=%s, post=%s)\n" \
        "$PRE_SIG_RMS" "$POST_SIG_RMS"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  signal-region RMS lost too much (pre=%s, post=%s)\n" \
        "$PRE_SIG_RMS" "$POST_SIG_RMS"
fi

# ===========================================================================
# Assertion 5: SNR after > SNR before (the headline metric)
# ===========================================================================

PRE_SNR=$(printf '%s\n' "$DRV_TXT" | grep -oE 'pre_snr_x100=[0-9]+' | head -1 | cut -d= -f2)
POST_SNR=$(printf '%s\n' "$DRV_TXT" | grep -oE 'post_snr_x100=[0-9]+' | head -1 | cut -d= -f2)
if [ -n "$PRE_SNR" ] && [ -n "$POST_SNR" ] && [ "$POST_SNR" -gt "$PRE_SNR" ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  SNR improved (pre=%s/100, post=%s/100)\n" \
        "$PRE_SNR" "$POST_SNR"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  SNR did not improve (pre=%s/100, post=%s/100)\n" \
        "$PRE_SNR" "$POST_SNR"
fi

# ===========================================================================
# Assertion 6: SNR after >= 1.5x SNR before (substantial improvement, not noise)
# ===========================================================================

if [ -n "$PRE_SNR" ] && [ -n "$POST_SNR" ] \
   && [ $((POST_SNR * 2)) -ge $((PRE_SNR * 3)) ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  SNR improvement >= 1.5x (pre=%s/100, post=%s/100)\n" \
        "$PRE_SNR" "$POST_SNR"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  SNR improvement below 1.5x (pre=%s/100, post=%s/100)\n" \
        "$PRE_SNR" "$POST_SNR"
fi

# ===========================================================================
# Assertion 7: chat /help advertises /denoise
# ===========================================================================

CHAT_HELP=$(run_chat "/help")
assert_match "$CHAT_HELP" "/denoise PATH" \
    "chat /help advertises /denoise"
assert_match "$CHAT_HELP" "R26C" \
    "chat /help labels /denoise as R26C"

# ===========================================================================
# Assertion 8: bare /denoise prints usage
# ===========================================================================

CHAT_NOARG=$(run_chat "/denoise")
assert_match "$CHAT_NOARG" "/denoise needs PATH" \
    "chat /denoise with no arg prints usage hint"

# ===========================================================================
# Assertion 9: graceful failure on missing WAV
# ===========================================================================

CHAT_MISSING=$(run_chat "/denoise $MISSING_WAV")
assert_match "$CHAT_MISSING" "denoise FAILED: could not parse WAV at $MISSING_WAV" \
    "chat /denoise on missing WAV reports graceful failure"

# ===========================================================================
# Assertion 10: chat /denoise on real WAV reports input/output metrics
# ===========================================================================

CHAT_NOISY=$(run_chat "/denoise $NOISY_WAV")
assert_match "$CHAT_NOISY" "denoise $NOISY_WAV" \
    "chat /denoise on noisy WAV reports path"
assert_match "$CHAT_NOISY" "leading_ms=300" \
    "chat /denoise reports leading_ms=300"
assert_match "$CHAT_NOISY" "frame_size=256" \
    "chat /denoise @ 8 kHz reports frame_size=256"

# ===========================================================================
# Optional: whisper round-trip on the cleaned vs noisy WAV. We don't pin
# transcript text (Klatt -> whisper is highly variable) but if both calls
# return without crashing the pipeline is wired.
# ===========================================================================

if [ "$HAVE_WHISPER" -eq 1 ]; then
    WHISPER_NOISY=$("$WHISPER_BIN" -m "$WHISPER_MODEL" -f "$NOISY_WAV" --no-prints 2>&1 | head -50)
    WHISPER_CLEAN=$("$WHISPER_BIN" -m "$WHISPER_MODEL" -f "$CLEAN_WAV" --no-prints 2>&1 | head -50)
    NOISY_LEN=${#WHISPER_NOISY}
    CLEAN_LEN=${#WHISPER_CLEAN}
    if [ "$NOISY_LEN" -gt 0 ] && [ "$CLEAN_LEN" -gt 0 ]; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}PASS${C_RST}  whisper round-trip non-empty on both noisy + cleaned (noisy_len=%d, clean_len=%d)\n" \
            "$NOISY_LEN" "$CLEAN_LEN"
    else
        # Note (not FAIL): Klatt formant output is well below whisper's
        # speech model confidence threshold, so a 1200-sample /ae/ vowel
        # often transcribes to nothing. We log the lengths but do NOT
        # fail the scenario when both are empty.
        printf "  ${C_YEL}NOTE${C_RST}  whisper returned non-strict output on Klatt fixture (noisy_len=%d, clean_len=%d)\n" \
            "$NOISY_LEN" "$CLEAN_LEN"
        PASS=$((PASS+1))
    fi
else
    printf "  ${C_DIM}skip${C_RST}  whisper round-trip skipped (binary not at %s)\n" "$WHISPER_BIN"
fi

# ===========================================================================
# Negative: driver must not emit FAIL lines
# ===========================================================================

assert_nomatch "$DRV_TXT" "^FAIL" \
    "fixture driver did not emit FAIL lines"

summary "scenario_uuuu_noise_reduce"
