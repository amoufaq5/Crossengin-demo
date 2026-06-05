#!/usr/bin/env bash
# Scenario QQ -- R10B: whisper confidence parsing + Vosk offline backend.
#
# Exercises two follow-ups from R8B:
#   1. The new whisper.cpp confidence path
#      (`whisper_transcribe_with_confidence`) which parses `-ojf` JSON
#      output for per-token probabilities and averages them into a
#      real per-utterance milli value.
#   2. The new Vosk offline backend
#      (`src/io/transducers/vosk_backend.nova`) wired into stt_seam.
#
# Pipeline:
#   * Locate JFK sample (same path scenario_jj_whisper uses); SKIP
#     real-decode assertions if absent.
#   * Drive the whisper-with-confidence path on JFK. Confidence
#     MUST be in (800, 1000] -- proves the JSON parser produced a
#     real per-utterance value (legacy ballpark was a flat 800; a
#     value > 800 can only come from the JSON path).
#   * Drive the Vosk backend on JFK. Confidence MUST be in (500, 1000]
#     -- studio-quality audio averages ~0.95+ per word for the small
#     model. SKIP if Vosk isn't installed.
#   * Drive the seam with CE_STT_BACKEND=whisper -- assert it
#     dispatches to whisper.
#   * Drive the seam with CE_STT_BACKEND=vosk -- assert it
#     dispatches to vosk.
#   * Drive the seam with CE_STT_BACKEND=stub -- assert it
#     returns the stub placeholder.
#   * Drive the seam with CE_STT_BACKEND unset -- assert auto-pick
#     selects whisper when installed, else vosk when installed, else stub.
#
# Pre-conditions: NOVA toolchain at $NOVA_ROOT/nova.
# Optional: whisper-main + ggml-tiny.en.bin (for whisper assertions),
#           python3 + vosk + vosk-model-small-en-us (for vosk assertions),
#           jfk.wav at /tmp/whisper.cpp/samples/jfk.wav (for real-decode).
# Side-effects: writes /tmp/ce_scenario_qq_driver.out, plus the on-the-fly
#               NOVA driver under tests/integration/_scenario_qq_drivers/.

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

it_section "scenario QQ: R10B whisper confidence + Vosk offline backend"

NOVA_BIN="${NOVA_ROOT:-/home/user/NOVA}/nova"
if [ ! -x "$NOVA_BIN" ]; then
    printf "  ${C_RED}ERROR${C_RST}: NOVA launcher not found at %s (set NOVA_ROOT)\n" "$NOVA_BIN" >&2
    FAIL=$((FAIL+1))
    summary "scenario_qq_vosk"
    exit $?
fi

# Resolve whisper-main + model paths (match whisper_backend.nova resolver).
WHISPER_BIN="${CE_WHISPER_BIN:-/usr/local/bin/whisper-main}"
WHISPER_MODEL="${CE_WHISPER_MODEL:-/usr/local/share/whisper/ggml-tiny.en.bin}"
WHISPER_INSTALLED=0
if [ -x "$WHISPER_BIN" ] && [ -f "$WHISPER_MODEL" ]; then
    WHISPER_INSTALLED=1
    printf "  ${C_DIM}(whisper-main at %s)${C_RST}\n" "$WHISPER_BIN"
else
    printf "  ${C_YEL}NOTE${C_RST}  whisper not installed; whisper assertions skipped\n"
fi

# Resolve python3 + vosk model paths (match vosk_backend.nova resolver).
VOSK_BIN="${CE_VOSK_BIN:-/usr/local/bin/python3}"
VOSK_MODEL="${CE_VOSK_MODEL:-/usr/local/share/vosk/vosk-model-small-en-us-0.15}"
VOSK_INSTALLED=0
if [ -x "$VOSK_BIN" ] && [ -f "$VOSK_MODEL/am/final.mdl" ]; then
    # Probe the python wheel: import vosk OR module-not-found.
    if "$VOSK_BIN" -c "from vosk import Model, KaldiRecognizer" 2>/dev/null; then
        VOSK_INSTALLED=1
        printf "  ${C_DIM}(python3 + vosk wheel + model at %s)${C_RST}\n" "$VOSK_MODEL"
    else
        printf "  ${C_YEL}NOTE${C_RST}  vosk wheel not importable; vosk assertions skipped\n"
    fi
else
    printf "  ${C_YEL}NOTE${C_RST}  vosk not installed (bin=%s exists=%d, model=%s/am/final.mdl exists=%d)\n" \
        "$VOSK_BIN" "$([ -x "$VOSK_BIN" ] && echo 1 || echo 0)" \
        "$VOSK_MODEL" "$([ -f "$VOSK_MODEL/am/final.mdl" ] && echo 1 || echo 0)"
fi

# Locate JFK sample.
JFK_WAV="${CE_WHISPER_JFK_WAV:-/tmp/whisper.cpp/samples/jfk.wav}"
HAVE_JFK=0
if [ -f "$JFK_WAV" ]; then HAVE_JFK=1; fi

DRV_DIR="$REPO_ROOT/tests/integration/_scenario_qq_drivers"
DRV_SRC="$DRV_DIR/r10b_pipeline_driver.nova"
DRV_OUT="/tmp/ce_scenario_qq_driver.out"

mkdir -p "$DRV_DIR"
trap 'rm -f "$DRV_OUT"; rm -rf "$DRV_DIR"' EXIT

# Emit the NOVA driver. We probe each backend through both the bare
# helper (`whisper_transcribe_with_confidence`, `vosk_transcribe`) AND
# through the seam dispatcher with CE_STT_BACKEND set to each variant.
cat > "$DRV_SRC" <<'NOVA'
// Auto-generated R10B pipeline driver for scenario_qq_vosk.sh.
//
// Reports one line per probe; the bash script asserts on each line.

import "std/syscall"
import "../../../src/io/transducers/whisper_backend.nova"
import "../../../src/io/transducers/vosk_backend.nova"
import "../../../src/io/transducers/stt_seam.nova"

// Substring-contains predicate.
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
    // ---- env-resolved paths probe ----------------------------------------
    let wbin = whisper_resolve_bin()
    let wmodel = whisper_resolve_model()
    let vbin = vosk_resolve_bin()
    let vmodel = vosk_resolve_model()
    let w_avail = whisper_backend_available(wbin, wmodel)
    let v_avail = vosk_backend_available(vbin, vmodel)
    println("resolved_whisper_bin=" + wbin)
    println("resolved_vosk_bin=" + vbin)
    println("whisper_available=" + int_to_str(w_avail))
    println("vosk_available=" + int_to_str(v_avail))

    // ---- backend registry probe ------------------------------------------
    let s0 = stt_seam_new()
    let wid = stt_seam_backend_id_for(s0, "whisper")
    let vid = stt_seam_backend_id_for(s0, "vosk")
    println("whisper_id=" + int_to_str(wid))
    println("vosk_id=" + int_to_str(vid))

    // ---- whisper with confidence (JFK) -----------------------------------
    let jfk = getenv("CE_WHISPER_JFK_WAV")
    if jfk == 0 { jfk = "/tmp/whisper.cpp/samples/jfk.wav" }
    if len(jfk) == 0 { jfk = "/tmp/whisper.cpp/samples/jfk.wav" }

    let wr = whisper_transcribe_with_confidence(wbin, wmodel, jfk)
    let wt = whisper_result_transcript(wr)
    let wc = whisper_result_confidence(wr)
    let we = whisper_result_error(wr)
    let has_amer_w = _contains(wt, "Americans")
    println("WHIS_JFK tlen=" + int_to_str(len(wt))
        + " conf=" + int_to_str(wc)
        + " err=[" + we + "]"
        + " hasamerican=" + int_to_str(has_amer_w))

    // ---- vosk on JFK -----------------------------------------------------
    let vr = vosk_transcribe(vbin, vmodel, jfk)
    let vt = vosk_result_transcript(vr)
    let vc = vosk_result_confidence(vr)
    let ve = vosk_result_error(vr)
    // Vosk's small-en model lower-cases everything; check for "americans".
    let has_amer_v = _contains(vt, "americans")
    println("VOSK_JFK tlen=" + int_to_str(len(vt))
        + " conf=" + int_to_str(vc)
        + " err=[" + ve + "]"
        + " hasamericans=" + int_to_str(has_amer_v))

    // ---- seam with explicit CE_STT_BACKEND=whisper ----------------------
    // We can't change env from within the driver; the bash wrapper sets
    // the env on each driver invocation. Inside the driver we just
    // resolve the default backend and report what we got.
    let s_w = stt_seam_new()
    let name_w = stt_seam_backend_name(s_w)
    let bid_w = stt_seam_default_backend(s_w)
    println("AUTO_PICK name=" + name_w + " id=" + int_to_str(bid_w))

    // ---- forced-stub through the seam ----------------------------------
    let s_stub = stt_seam_new()
    stt_seam_set_default(s_stub, 1)        // STT_BACKEND_STUB
    let r_stub = stt_transcribe_wav(s_stub, jfk)
    println("STUB_JFK transcript=[" + stt_result_transcript(r_stub)
        + "] conf=" + int_to_str(stt_result_confidence(r_stub)))

    // ---- forced-vosk through the seam ----------------------------------
    let s_vosk = stt_seam_new_vosk(vmodel)
    let r_v_seam = stt_transcribe_wav(s_vosk, jfk)
    println("SEAM_VOSK_JFK tlen=" + int_to_str(len(stt_result_transcript(r_v_seam)))
        + " conf=" + int_to_str(stt_result_confidence(r_v_seam))
        + " err=[" + stt_result_error(r_v_seam) + "]")

    // ---- forced-whisper through the seam --------------------------------
    let s_whis = stt_seam_new_whisper(wmodel)
    let r_w_seam = stt_transcribe_wav(s_whis, jfk)
    println("SEAM_WHIS_JFK tlen=" + int_to_str(len(stt_result_transcript(r_w_seam)))
        + " conf=" + int_to_str(stt_result_confidence(r_w_seam))
        + " err=[" + stt_result_error(r_w_seam) + "]")

    println("driver complete")
}

main()
NOVA

# Run the driver multiple times with different CE_STT_BACKEND envs to
# verify auto-pick semantics. Each run produces a labelled output blob;
# the assertions below match against the relevant blob.

run_driver() {
    # run_driver <stt_env_value> <output_path>
    local env_val="$1"
    local out="$2"
    rm -f "$out"
    if [ -z "$env_val" ]; then
        CE_WHISPER_BIN="$WHISPER_BIN" \
        CE_WHISPER_MODEL="$WHISPER_MODEL" \
        CE_WHISPER_JFK_WAV="$JFK_WAV" \
        CE_VOSK_BIN="$VOSK_BIN" \
        CE_VOSK_MODEL="$VOSK_MODEL" \
        "$NOVA_BIN" run "$DRV_SRC" > "$out" 2>&1
    else
        CE_WHISPER_BIN="$WHISPER_BIN" \
        CE_WHISPER_MODEL="$WHISPER_MODEL" \
        CE_WHISPER_JFK_WAV="$JFK_WAV" \
        CE_VOSK_BIN="$VOSK_BIN" \
        CE_VOSK_MODEL="$VOSK_MODEL" \
        CE_STT_BACKEND="$env_val" \
        "$NOVA_BIN" run "$DRV_SRC" > "$out" 2>&1
    fi
    return $?
}

# Run with no CE_STT_BACKEND (auto-pick).
run_driver "" "$DRV_OUT.auto"
RC_AUTO=$?

# Run with CE_STT_BACKEND=whisper (explicit).
run_driver "whisper" "$DRV_OUT.whisper"
RC_W=$?

# Run with CE_STT_BACKEND=vosk (explicit).
run_driver "vosk" "$DRV_OUT.vosk"
RC_V=$?

# Run with CE_STT_BACKEND=stub (explicit).
run_driver "stub" "$DRV_OUT.stub"
RC_S=$?

if [ "$RC_AUTO" -ne 0 ] || [ "$RC_W" -ne 0 ] || [ "$RC_V" -ne 0 ] || [ "$RC_S" -ne 0 ]; then
    printf "  ${C_RED}FAIL${C_RST}  one or more driver invocations exited non-zero (rc=%d/%d/%d/%d)\n" \
        "$RC_AUTO" "$RC_W" "$RC_V" "$RC_S"
    [ -f "$DRV_OUT.auto" ] && { printf "  --- AUTO ---\n"; sed 's/^/        /' "$DRV_OUT.auto"; }
    FAIL=$((FAIL+1))
    summary "scenario_qq_vosk"
    exit $?
fi

AUTO_TXT=$(cat "$DRV_OUT.auto")
WHIS_TXT=$(cat "$DRV_OUT.whisper")
VOSK_TXT=$(cat "$DRV_OUT.vosk")
STUB_TXT=$(cat "$DRV_OUT.stub")

# ===========================================================================
# Assertions (~10)
# ===========================================================================

# 1. Backend registry: vosk + whisper both have well-known IDs.
assert_match "$AUTO_TXT" "whisper_id=4" \
    "whisper backend registered with id 4 (R8B)"
assert_match "$AUTO_TXT" "vosk_id=5" \
    "vosk backend registered with id 5 (R10B)"

# 2. Stub-forced seam returns the placeholder regardless of install state.
assert_match "$STUB_TXT" 'STUB_JFK transcript=\[\[stt unavailable\]\] conf=0' \
    "CE_STT_BACKEND=stub returns stub placeholder + confidence 0"

# 3. Whisper confidence path: must report conf > 800 on JFK (proving the
#    JSON parser produced a real per-utterance value, not the 800 ballpark).
if [ "$WHISPER_INSTALLED" -eq 1 ] && [ "$HAVE_JFK" -eq 1 ]; then
    assert_match "$WHIS_TXT" "WHIS_JFK .* hasamerican=1" \
        "whisper JFK transcript contains 'Americans' (model decoded English)"
    # Parse the milli value and assert in (800, 1000].
    JFK_W_CONF=$(echo "$WHIS_TXT" | grep -oE 'WHIS_JFK .* conf=[0-9]+' | head -1 | grep -oE '[0-9]+$' || echo 0)
    if [ "$JFK_W_CONF" -gt 800 ] && [ "$JFK_W_CONF" -le 1000 ]; then
        printf "  ${C_GRN}PASS${C_RST}  whisper JFK confidence=%d in (800, 1000] (real per-utterance)\n" "$JFK_W_CONF"
        PASS=$((PASS+1))
    else
        printf "  ${C_RED}FAIL${C_RST}  whisper JFK confidence=%d not in (800, 1000]\n" "$JFK_W_CONF"
        FAIL=$((FAIL+1))
    fi
    # 4. With CE_STT_BACKEND=whisper, the auto-pick should also be whisper.
    assert_match "$WHIS_TXT" "AUTO_PICK name=whisper" \
        "CE_STT_BACKEND=whisper -> seam picks whisper"
    # 5. SEAM_WHIS_JFK should report non-empty transcript + conf > 0.
    assert_match "$WHIS_TXT" "SEAM_WHIS_JFK tlen=[1-9]" \
        "seam dispatch through whisper produces non-empty transcript"
else
    printf "  ${C_YEL}SKIP${C_RST}  whisper or JFK sample unavailable -- whisper assertions skipped\n"
fi

# 6. Vosk path: JFK must produce a transcript + confidence > 500.
if [ "$VOSK_INSTALLED" -eq 1 ] && [ "$HAVE_JFK" -eq 1 ]; then
    assert_match "$VOSK_TXT" "VOSK_JFK .* hasamericans=1" \
        "vosk JFK transcript contains 'americans' (model decoded English)"
    JFK_V_CONF=$(echo "$VOSK_TXT" | grep -oE 'VOSK_JFK .* conf=[0-9]+' | head -1 | grep -oE '[0-9]+$' || echo 0)
    if [ "$JFK_V_CONF" -gt 500 ] && [ "$JFK_V_CONF" -le 1000 ]; then
        printf "  ${C_GRN}PASS${C_RST}  vosk JFK confidence=%d in (500, 1000] (high quality)\n" "$JFK_V_CONF"
        PASS=$((PASS+1))
    else
        printf "  ${C_RED}FAIL${C_RST}  vosk JFK confidence=%d not in (500, 1000]\n" "$JFK_V_CONF"
        FAIL=$((FAIL+1))
    fi
    # 7. With CE_STT_BACKEND=vosk, the auto-pick should also be vosk.
    assert_match "$VOSK_TXT" "AUTO_PICK name=vosk" \
        "CE_STT_BACKEND=vosk -> seam picks vosk"
    # 8. SEAM_VOSK_JFK should also produce non-empty transcript.
    assert_match "$VOSK_TXT" "SEAM_VOSK_JFK tlen=[1-9]" \
        "seam dispatch through vosk produces non-empty transcript"
else
    printf "  ${C_YEL}SKIP${C_RST}  vosk or JFK sample unavailable -- vosk assertions skipped\n"
fi

# 9. Auto-pick: with no CE_STT_BACKEND, whisper > vosk > stub.
if [ "$WHISPER_INSTALLED" -eq 1 ]; then
    assert_match "$AUTO_TXT" "AUTO_PICK name=whisper" \
        "auto-pick: whisper installed -> whisper selected"
elif [ "$VOSK_INSTALLED" -eq 1 ]; then
    assert_match "$AUTO_TXT" "AUTO_PICK name=vosk" \
        "auto-pick: only vosk installed -> vosk selected"
else
    assert_match "$AUTO_TXT" "AUTO_PICK name=stub" \
        "auto-pick: neither installed -> stub selected"
fi

# 10. CE_STT_BACKEND=stub overrides the auto-pick.
assert_match "$STUB_TXT" "AUTO_PICK name=stub" \
    "CE_STT_BACKEND=stub overrides auto-pick"

# Driver-complete markers.
assert_match "$AUTO_TXT" "driver complete" \
    "auto-pick driver reached end-of-main"
assert_match "$WHIS_TXT" "driver complete" \
    "whisper driver reached end-of-main"

# Negative check: no FAIL line.
assert_nomatch "$AUTO_TXT" "FAIL" \
    "auto driver did not emit a FAIL line"

summary "scenario_qq_vosk"
