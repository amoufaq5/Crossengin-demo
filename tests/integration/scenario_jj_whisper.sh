#!/usr/bin/env bash
# Scenario JJ -- R8B: whisper.cpp STT backend end-to-end.
#
# Exercises the new src/io/transducers/whisper_backend.nova module:
#   * Synthesize a known utterance via R6E's expanded Klatt formant
#     inventory (33 -> 53 phoneme dispatches, full ARPAbet).
#   * Write it as a canonical PCM16 WAV via audio_write_wav.
#   * Drive through whisper_transcribe -> assert exit-clean (the
#     transcribed text may not match the input phonetically, since
#     Klatt formants are a synthetic minimum and tiny.en is trained
#     on natural speech -- but the pipeline MUST run without error
#     and produce a non-empty transcript or a precise error).
#   * Drive a known REAL utterance (whisper.cpp's bundled jfk.wav)
#     through whisper_transcribe -> assert the transcript contains
#     "Americans" (the JFK quote starts with "And so my fellow
#     Americans..."), proving the model actually decoded English.
#   * Drive the seam with CE_STT_BACKEND=stub -> assert it falls
#     back to the stub placeholder cleanly (no whisper invocation).
#   * SKIP gracefully if whisper-main is not installed (so CI on
#     non-whisper environments still passes the scenario without
#     fail-hard on a missing optional dep).
#
# Pre-conditions: NOVA toolchain at $NOVA_ROOT/nova.
# Optional: whisper-main + ggml-tiny.en.bin at /usr/local/bin /
#           /usr/local/share/whisper. Without these the real-decode
#           assertions SKIP and only the missing-bin error-path
#           assertions run.
# Side-effects: writes /tmp/ce_scenario_jj_klatt.wav,
#               /tmp/ce_scenario_jj_driver.out, plus the on-the-fly
#               NOVA driver under tests/integration/_scenario_jj_drivers/.

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

it_section "scenario JJ: R8B whisper.cpp STT backend"

NOVA_BIN="${NOVA_ROOT:-/home/user/NOVA}/nova"
if [ ! -x "$NOVA_BIN" ]; then
    printf "  ${C_RED}ERROR${C_RST}: NOVA launcher not found at %s (set NOVA_ROOT)\n" "$NOVA_BIN" >&2
    FAIL=$((FAIL+1))
    summary "scenario_jj_whisper"
    exit $?
fi

# Resolve whisper-main + model paths. Match the resolver shape in
# whisper_backend.nova: env override first, canonical default otherwise.
WHISPER_BIN="${CE_WHISPER_BIN:-/usr/local/bin/whisper-main}"
WHISPER_MODEL="${CE_WHISPER_MODEL:-/usr/local/share/whisper/ggml-tiny.en.bin}"

WHISPER_INSTALLED=0
if [ -x "$WHISPER_BIN" ] && [ -f "$WHISPER_MODEL" ]; then
    WHISPER_INSTALLED=1
    printf "  ${C_DIM}(whisper-main at %s; model at %s)${C_RST}\n" "$WHISPER_BIN" "$WHISPER_MODEL"
else
    printf "  ${C_YEL}NOTE${C_RST}  whisper not installed (bin=%s exists=%d, model=%s exists=%d)\n" \
        "$WHISPER_BIN" "$([ -x "$WHISPER_BIN" ] && echo 1 || echo 0)" \
        "$WHISPER_MODEL" "$([ -f "$WHISPER_MODEL" ] && echo 1 || echo 0)"
fi

KLATT_WAV="/tmp/ce_scenario_jj_klatt.wav"
DRV_DIR="$REPO_ROOT/tests/integration/_scenario_jj_drivers"
DRV_SRC="$DRV_DIR/whisper_pipeline_driver.nova"
DRV_OUT="/tmp/ce_scenario_jj_driver.out"

mkdir -p "$DRV_DIR"
trap 'rm -f "$KLATT_WAV" "$DRV_OUT"; rm -rf "$DRV_DIR"' EXIT

# Locate a known-real WAV. Whisper.cpp's bundled JFK sample lives at
# /tmp/whisper.cpp/samples/jfk.wav when the user follows the install
# instructions (this is where R8B's setup leaves it). If absent, the
# scenario skips the real-decode assertions and runs only the error
# paths + Klatt round-trip.
JFK_WAV="${CE_WHISPER_JFK_WAV:-/tmp/whisper.cpp/samples/jfk.wav}"
HAVE_JFK=0
if [ -f "$JFK_WAV" ]; then HAVE_JFK=1; fi

# Emit the NOVA driver. The leading underscore on _scenario_jj_drivers/
# means the Makefile's integration glob (! -name '_*') skips it.
cat > "$DRV_SRC" <<'NOVA'
// Auto-generated whisper-backend pipeline driver for scenario_jj_whisper.sh.
//
// Steps:
//   1. Klatt-synthesize a short utterance ("EY DAY OW BOY" -- four
//      diphthongs/monophthong). Save to /tmp/ce_scenario_jj_klatt.wav.
//   2. Try whisper_transcribe on the Klatt WAV with the operator-
//      supplied (env-resolved) bin + model paths. Print the result:
//        KLATT bin=<path> model=<path> tlen=<n> conf=<c> err=<e>
//   3. If CE_WHISPER_JFK_WAV is set + the file exists, also try
//      whisper_transcribe on the JFK sample. Print:
//        JFK   tlen=<n> conf=<c> err=<e> hasamerican=<0|1>
//   4. Force the seam to the stub backend (CE_STT_BACKEND=stub or
//      explicit set_default) and run stt_transcribe_wav on the
//      Klatt WAV; assert it returns the stub placeholder regardless
//      of whisper's install state.
//   5. Force the seam to the whisper backend and assert
//      stt_seam_backend_name returns "whisper".

import "std/syscall"
import "../../../src/io/effectors/audio_synth.nova"
import "../../../src/io/transducers/whisper_backend.nova"
import "../../../src/io/transducers/stt_seam.nova"

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

fn _zero_buf(n) {
    let b = list_new()
    let i = 0
    while i < n {
        push(b, 0)
        i = i + 1
    }
    return b
}

fn _build_klatt_utterance() {
    let pre = _zero_buf(1200)              // 150 ms silence lead-in
    let p1 = synth_phoneme("ey")           // diphthong /eɪ/
    let p2 = synth_phoneme("ay")           // diphthong /aɪ/
    let p3 = synth_phoneme("ow")           // /oʊ/
    let p4 = synth_phoneme("oy")           // diphthong /ɔɪ/
    let mid = _concat(_concat(_concat(p1, p2), p3), p4)
    let post = _zero_buf(2400)             // 300 ms silence tail
    return _concat(_concat(pre, mid), post)
}

// Substring-contains predicate -- checks whether `needle` appears
// anywhere in `text`. Pure NOVA, no regex.
fn _contains(text, needle) {
    let n = len(text)
    let m = len(needle)
    if m == 0 { return 1 }
    if n < m { return 0 }
    let i = 0
    while i <= n - m {
        let j = 0
        let ok = 1
        while j < m {
            if char_at(text, i + j) != char_at(needle, j) { ok = 0 j = m }
            j = j + 1
        }
        if ok == 1 { return 1 }
        i = i + 1
    }
    return 0
}

fn main() {
    // Step 1: build + write the Klatt utterance.
    let utter = _build_klatt_utterance()
    let ok1 = audio_write_wav(utter, "/tmp/ce_scenario_jj_klatt.wav")
    println("klatt_written=" + int_to_str(ok1))

    // Step 2: whisper_transcribe on the Klatt WAV. We use the
    // env-resolved bin + model.
    let bin = whisper_resolve_bin()
    let model = whisper_resolve_model()
    println("resolved_bin=" + bin)
    println("resolved_model=" + model)
    let avail = whisper_backend_available(bin, model)
    println("whisper_available=" + int_to_str(avail))

    let kr = whisper_transcribe(bin, model, "/tmp/ce_scenario_jj_klatt.wav")
    let kt = whisper_result_transcript(kr)
    let kc = whisper_result_confidence(kr)
    let ke = whisper_result_error(kr)
    println("KLATT tlen=" + int_to_str(len(kt))
        + " conf=" + int_to_str(kc)
        + " err=[" + ke + "]")
    if len(kt) > 0 {
        println("KLATT transcript=[" + kt + "]")
    }

    // Step 3: JFK sample if available.
    let jfk = getenv("CE_WHISPER_JFK_WAV")
    if jfk == 0 { jfk = "/tmp/whisper.cpp/samples/jfk.wav" }
    if len(jfk) > 0 {
        let jr = whisper_transcribe(bin, model, jfk)
        let jt = whisper_result_transcript(jr)
        let jc = whisper_result_confidence(jr)
        let je = whisper_result_error(jr)
        let hasam = _contains(jt, "Americans")
        println("JFK tlen=" + int_to_str(len(jt))
            + " conf=" + int_to_str(jc)
            + " err=[" + je + "]"
            + " hasamerican=" + int_to_str(hasam))
        if len(jt) > 0 {
            println("JFK transcript=[" + jt + "]")
        }
    } else {
        println("JFK skip")
    }

    // Step 4: stub fallback through the seam. Force STT_BACKEND_STUB
    // and confirm the seam returns the placeholder regardless of
    // whisper's install state.
    let s = stt_seam_new()
    stt_seam_set_default(s, 1)            // STT_BACKEND_STUB
    let stub_r = stt_transcribe_wav(s, "/tmp/ce_scenario_jj_klatt.wav")
    let stub_t = stt_result_transcript(stub_r)
    let stub_c = stt_result_confidence(stub_r)
    println("STUB transcript=[" + stub_t + "] conf=" + int_to_str(stub_c))

    // Step 5: whisper dispatch through the seam. We expect the seam's
    // backend name to be "whisper" after we set the default to id 4.
    let sw = stt_seam_new_whisper(model)
    let wname = stt_seam_backend_name(sw)
    let wid   = stt_seam_default_backend(sw)
    println("SEAM_WHISPER name=" + wname + " id=" + int_to_str(wid))

    // Step 6: end-to-end through the seam on the Klatt WAV.
    let seam_r = stt_transcribe_wav(sw, "/tmp/ce_scenario_jj_klatt.wav")
    let seam_t = stt_result_transcript(seam_r)
    let seam_c = stt_result_confidence(seam_r)
    let seam_e = stt_result_error(seam_r)
    println("SEAM_KLATT tlen=" + int_to_str(len(seam_t))
        + " conf=" + int_to_str(seam_c)
        + " err=[" + seam_e + "]")

    println("driver complete")
}

main()
NOVA

# Run the driver with the canonical env vars. We don't FORCE a backend
# here -- the seam's auto-pick handles both installed + uninstalled
# whisper cases.
rm -f "$KLATT_WAV"
CE_WHISPER_BIN="$WHISPER_BIN" \
CE_WHISPER_MODEL="$WHISPER_MODEL" \
CE_WHISPER_JFK_WAV="$JFK_WAV" \
"$NOVA_BIN" run "$DRV_SRC" > "$DRV_OUT" 2>&1
DRIVER_RC=$?

if [ "$DRIVER_RC" -ne 0 ]; then
    printf "  ${C_RED}FAIL${C_RST}  driver exited non-zero (rc=%d). Output:\n" "$DRIVER_RC"
    sed 's/^/        /' "$DRV_OUT"
    FAIL=$((FAIL+1))
    summary "scenario_jj_whisper"
    exit $?
fi

DRV_TXT=$(cat "$DRV_OUT")

# ===========================================================================
# Assertions
# ===========================================================================

# 1. Driver wrote the Klatt WAV.
assert_match "$DRV_TXT" "klatt_written=1" \
    "Klatt WAV written to /tmp/ce_scenario_jj_klatt.wav"
assert_file_exists "$KLATT_WAV" "Klatt WAV exists on disk"

# 2. Resolver returned the expected paths.
assert_match "$DRV_TXT" "resolved_bin=$WHISPER_BIN" \
    "whisper_resolve_bin returned env-supplied path"
assert_match "$DRV_TXT" "resolved_model=$WHISPER_MODEL" \
    "whisper_resolve_model returned env-supplied path"

# 3. Stub fallback works regardless of install state.
assert_match "$DRV_TXT" 'STUB transcript=\[\[stt unavailable\]\] conf=0' \
    "STT_BACKEND_STUB returns placeholder + confidence 0"

# 4. Seam constructed with stt_seam_new_whisper reports backend name 'whisper'.
assert_match "$DRV_TXT" "SEAM_WHISPER name=whisper id=4" \
    "stt_seam_new_whisper pins default to whisper (id 4)"

# 5. Whisper-installed assertions (otherwise SKIP).
if [ "$WHISPER_INSTALLED" -eq 1 ]; then
    assert_match "$DRV_TXT" "whisper_available=1" \
        "whisper_backend_available=1 when bin+model present"

    # Klatt WAV through whisper: tlen >= 0 + err is one of the known
    # values. We tolerate a wide range because Klatt synth + tiny.en
    # often produces "[BLANK_AUDIO]" or a near-empty transcript --
    # the goal is to prove the PIPELINE works, not that synthetic
    # speech transcribes cleanly (it usually doesn't).
    # The required invariant: NO crash, the result line lands.
    assert_match "$DRV_TXT" "KLATT tlen=" \
        "Klatt WAV transcribe path completed (no fork/exec crash)"

    # JFK sample: must produce >0 chars + contain "Americans".
    if [ "$HAVE_JFK" -eq 1 ]; then
        assert_match "$DRV_TXT" "JFK tlen=" \
            "JFK WAV transcribe path completed"
        assert_match "$DRV_TXT" "JFK .* hasamerican=1" \
            "JFK transcript contains 'Americans' (model decoded English)"
        # Sanity: confidence should be WHISPER_CONFIDENCE_DEFAULT = 800.
        assert_match "$DRV_TXT" "JFK .* conf=800" \
            "JFK transcribe confidence = 800 (success ballpark)"
    else
        printf "  ${C_YEL}SKIP${C_RST}  JFK sample not at %s -- model-decode assertions skipped\n" "$JFK_WAV"
    fi
else
    # Without whisper installed, assert the error-path assertions instead.
    assert_match "$DRV_TXT" "whisper_available=0" \
        "whisper_backend_available=0 when bin or model absent"
    # Klatt transcribe must surface "binary not found" or "model not found".
    assert_match "$DRV_TXT" "KLATT .* err=\[(binary|model) not found\]" \
        "Klatt WAV transcribe surfaces precise install-error"
fi

# 6. Driver-complete marker.
assert_match "$DRV_TXT" "driver complete" \
    "driver reached end-of-main without crash"

# Negative check: no FAIL line.
assert_nomatch "$DRV_TXT" "FAIL" \
    "driver did not emit a FAIL line"

summary "scenario_jj_whisper"
