#!/usr/bin/env bash
# Scenario DDD -- R13D: voice cloning via Klatt formant transfer.
#
# Synthesizes a reference WAV at a known F0 (200 Hz), runs the voice-clone
# pipeline (analyze + apply + synth), and verifies the cloned synth's
# F0 matches the reference's F0 (R11B YIN).

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

it_section "scenario DDD: R13D voice cloning (Klatt formant transfer)"

NOVA_BIN="${NOVA_ROOT:-/home/user/NOVA}/nova"
if [ ! -x "$NOVA_BIN" ]; then
    printf "  ${C_RED}ERROR${C_RST}: NOVA launcher not found at %s (set NOVA_ROOT)\n" "$NOVA_BIN" >&2
    FAIL=$((FAIL+1))
    summary "scenario_ddd_voice_clone"
    exit $?
fi

REF_WAV="/tmp/ce_scenario_ddd_ref.wav"
CLONE_WAV="/tmp/ce_scenario_ddd_clone.wav"
DRV_DIR="$REPO_ROOT/tests/integration/_scenario_ddd_drivers"
DRV_SRC="$DRV_DIR/voice_clone_driver.nova"
DRV_OUT="/tmp/ce_scenario_ddd_driver.out"

mkdir -p "$DRV_DIR"
trap 'rm -f "$REF_WAV" "$CLONE_WAV" "$DRV_OUT" /tmp/cloned.wav; rm -rf "$DRV_DIR"' EXIT

cat > "$DRV_SRC" <<'NOVA'
import "std/syscall"
import "../../../src/io/effectors/audio_synth.nova"
import "../../../src/io/effectors/audio_voice_clone.nova"
import "../../../src/io/transducers/audio_capture.nova"
import "../../../src/io/transducers/audio_pitch.nova"

fn _report(label, samples, sample_rate) {
    let contour = pitch_track_yin(samples, sample_rate)
    let voiced = pitch_voiced_count(contour)
    let mean_c = pitch_mean_voiced(contour)
    println(label + " samples=" + int_to_str(len(samples))
        + " sample_rate=" + int_to_str(sample_rate)
        + " f0_mean=" + int_to_str(mean_c)
        + " voiced=" + int_to_str(voiced))
}

fn main() {
    // 1. Synthesize a reference WAV at F0 = 200 Hz via synth_sine (R6E's
    //    pure-tone primitive). 9600 samples = 1.2 s @ 8 kHz.
    let ref_pcm = synth_sine(200, 9600, 8000)
    let ok1 = audio_write_wav(ref_pcm, "/tmp/ce_scenario_ddd_ref.wav")
    println("wrote ref wav: " + int_to_str(ok1))
    _report("REF", ref_pcm, 8000)

    // 2. Analyze the reference -> profile.P0 should be ~200 Hz via R11B YIN.
    let profile = vc_analyze_reference("/tmp/ce_scenario_ddd_ref.wav")
    let prof_valid = vc_profile_is_valid(profile)
    let p0_centi = vc_profile_p0_centihz(profile)
    println("PROFILE valid=" + int_to_str(prof_valid)
        + " p0_centi=" + int_to_str(p0_centi)
        + " sr=" + int_to_str(vc_profile_sample_rate(profile)))

    // 3. Apply profile to a default R6E formant label list and check the
    //    output table is the right length. (Inspection only -- we don't
    //    write this anywhere; the next step does the actual synth.)
    let labels = list_new()
    push(labels, "ae")
    push(labels, "iy")
    push(labels, "uw")
    let mapped = vc_apply_profile(labels, profile)
    println("APPLIED table_len=" + int_to_str(len(mapped)))

    // 4. Synthesize new utterance ("aeaeaeae" -- 8 voiced characters)
    //    via vc_synth_with_profile and write to disk.
    let cloned = vc_synth_with_profile("aeaeaeae", profile)
    let ok2 = audio_write_wav(cloned, "/tmp/ce_scenario_ddd_clone.wav")
    println("wrote clone wav: " + int_to_str(ok2))
    _report("CLONE", cloned, 8000)
}

main()
NOVA

DRIVER_OUT=$("$NOVA_BIN" run "$DRV_SRC" 2>&1)
DRIVER_RC=$?
printf '%s\n' "$DRIVER_OUT" > "$DRV_OUT"

assert_eq "$DRIVER_RC" "0" "voice-clone driver exits 0"
assert_match "$DRIVER_OUT" "wrote ref wav: 1" "reference WAV written to disk"
assert_match "$DRIVER_OUT" "wrote clone wav: 1" "cloned WAV written to disk"
assert_file_exists "$REF_WAV"   "reference WAV exists on disk"
assert_file_exists "$CLONE_WAV" "cloned WAV exists on disk"

# Profile P0 should be ~200 Hz (20000 centi-Hz) via R11B YIN on the
# 200 Hz sine reference. Allow +/- 200 centi-Hz tolerance.
P0_CENTI=$(echo "$DRIVER_OUT" | grep -oE 'p0_centi=[0-9]+' | head -1 | cut -d= -f2)
if [ -n "$P0_CENTI" ] && [ "$P0_CENTI" -ge 19800 ] && [ "$P0_CENTI" -le 20200 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  PROFILE.P0: %s centi in [19800..20200] (~200 Hz)\n" "$P0_CENTI"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  PROFILE.P0: '%s' centi out of [19800..20200]\n" "$P0_CENTI"
fi

# Clone YIN F0 should also be ~200 Hz (transferred pitch). Allow +/- 1500
# centi-Hz tolerance for envelope/formant micro-coloring.
CLONE_LINE=$(printf '%s\n' "$DRIVER_OUT" | grep -E '^CLONE ' | head -1)
CLONE_MEAN=$(echo "$CLONE_LINE" | grep -oE 'f0_mean=[0-9]+' | head -1 | cut -d= -f2)
if [ -n "$CLONE_MEAN" ] && [ "$CLONE_MEAN" -ge 18500 ] && [ "$CLONE_MEAN" -le 21500 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  CLONE: f0_mean=%s centi in [18500..21500] (~200 Hz transferred)\n" "$CLONE_MEAN"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  CLONE: f0_mean='%s' centi out of [18500..21500]\n" "$CLONE_MEAN"
fi

# Applied table should have length 3 (we passed [ae, iy, uw]).
TABLE_LEN=$(echo "$DRIVER_OUT" | grep -oE 'APPLIED table_len=[0-9]+' | head -1 | cut -d= -f2)
if [ "$TABLE_LEN" = "3" ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  APPLIED: table_len=3 (ae, iy, uw)\n"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  APPLIED: table_len='%s' (expected 3)\n" "$TABLE_LEN"
fi

# --- chat helper assertions ---
require_chat

CHAT_HELP=$(run_chat "/help")
assert_match "$CHAT_HELP" '/clone' \
    "chat /help advertises the new /clone command"
assert_match "$CHAT_HELP" 'R13D' \
    "chat /help labels /clone as R13D"

CHAT_NOARG=$(run_chat "/clone")
assert_match "$CHAT_NOARG" '/clone needs REFERENCE.wav TEXT' \
    "chat /clone with no arg prints usage"

CHAT_MISSING=$(run_chat "/clone /tmp/ce_scenario_ddd_nonexistent.wav hello")
assert_match "$CHAT_MISSING" 'clone FAILED' \
    "chat /clone on missing WAV -> graceful FAILED"

# Happy path: use the reference we just wrote.
CHAT_HAPPY=$(run_chat "/clone $REF_WAV aeaeaeae")
assert_match "$CHAT_HAPPY" 'p0=' \
    "chat /clone reports profile P0"
assert_match "$CHAT_HAPPY" '/tmp/cloned.wav' \
    "chat /clone wrote /tmp/cloned.wav"

summary "scenario_ddd_voice_clone"
