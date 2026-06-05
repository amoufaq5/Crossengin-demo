#!/usr/bin/env bash
# Scenario FFFF -- R21C: text-to-speech pipeline (text -> G2P -> Klatt -> WAV).
#
# Drives both surfaces:
#   1. A stand-alone driver under tests/integration/_scenario_ffff_drivers/
#      that exercises the audio_tts API directly: G2P on a dictionary word,
#      G2P on an unknown word (rule fallback), tts_speak round-trip on
#      "hello world", determinism check (two invocations -> identical bytes).
#   2. The chat dispatch path: launch the chat, type "/say hello world",
#      assert the response shape and that /tmp/tts_out.wav was written.
#
# Pick: 'ffff' (free quadruple letter; aaaa/bbbb/cccc/dddd taken).

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

it_section "scenario FFFF: R21C TTS pipeline + /say command"

NOVA_BIN="${NOVA_ROOT:-/home/user/NOVA}/nova"
if [ ! -x "$NOVA_BIN" ]; then
    printf "  ${C_RED}ERROR${C_RST}: NOVA launcher not found at %s\n" "$NOVA_BIN" >&2
    FAIL=$((FAIL+1))
    summary "scenario_ffff_tts"
    exit $?
fi

OUT_WAV="/tmp/tts_out.wav"
DRV_DIR="$REPO_ROOT/tests/integration/_scenario_ffff_tts_driver"
DRV_SRC="$DRV_DIR/tts_pipeline_driver.nova"
DRV_OUT="/tmp/ce_scenario_ffff_driver.out"

mkdir -p "$DRV_DIR"
trap 'rm -f "$OUT_WAV" "$DRV_OUT"; rm -rf "$DRV_DIR"' EXIT

cat > "$DRV_SRC" <<'NOVA'
import "std/syscall"
import "../../../src/io/effectors/audio_tts.nova"

fn main() {
    // ---- G2P on a known dictionary word ------------------------------
    let hello = tts_g2p_word("hello")
    println("DICT hello count=" + int_to_str(len(hello))
        + " seq=" + tts_phonemes_to_string(hello))

    // ---- G2P on an unknown word: rule fallback should never crash ----
    let xyz = tts_g2p_word("xyzwz")
    println("FALLBACK xyzwz count=" + int_to_str(len(xyz))
        + " seq=" + tts_phonemes_to_string(xyz))

    // ---- end-to-end TTS on "hello world" -----------------------------
    let phs = tts_g2p("hello world")
    println("G2P hello_world count=" + int_to_str(len(phs))
        + " seq=" + tts_phonemes_to_string(phs))

    let wav = tts_speak("hello world", 16000)
    let ok = tts_save_wav(wav, "/tmp/tts_out.wav")
    println("SAVE hello_world ok=" + int_to_str(ok)
        + " bytes=" + int_to_str(len(wav)))

    // ---- determinism: two invocations -> identical bytes -------------
    audio_synth_mode_reset()
    audio_lcg_reset()
    let a = tts_speak("hello world", 16000)
    audio_synth_mode_reset()
    audio_lcg_reset()
    let b = tts_speak("hello world", 16000)
    let mismatch = 0
    let i = 0
    while i < len(a) {
        if a[i] != b[i] { mismatch = mismatch + 1 }
        i = i + 1
    }
    println("DETERMINISM mismatch=" + int_to_str(mismatch)
        + " len_a=" + int_to_str(len(a))
        + " len_b=" + int_to_str(len(b)))

    // ---- empty input -> 44-byte header-only WAV ----------------------
    let empty = tts_speak("", 16000)
    println("EMPTY bytes=" + int_to_str(len(empty)))
}

main()
NOVA

# Make sure no stale WAV from a prior run shows up as a false-positive.
rm -f "$OUT_WAV"

DRIVER_OUT=$("$NOVA_BIN" run "$DRV_SRC" 2>&1)
DRIVER_RC=$?
printf '%s\n' "$DRIVER_OUT" > "$DRV_OUT"

assert_eq "$DRIVER_RC" "0" "tts pipeline driver exits 0"
assert_match "$DRIVER_OUT" 'DICT hello count=4' \
    "G2P on dictionary word 'hello' -> 4 phonemes"
assert_match "$DRIVER_OUT" 'DICT hello.*seq=hh eh l ow' \
    "G2P 'hello' -> /HH EH L OW/ (canonical)"
assert_match "$DRIVER_OUT" 'FALLBACK xyzwz count=[1-9]' \
    "G2P unknown 'xyzwz' produces a non-empty fallback (rule path)"
assert_match "$DRIVER_OUT" 'G2P hello_world count=[89]' \
    "G2P 'hello world' phoneme count in [8..9] range"
assert_match "$DRIVER_OUT" 'SAVE hello_world ok=1' \
    "tts_save_wav reports success on /tmp/tts_out.wav"
assert_match "$DRIVER_OUT" 'SAVE hello_world.*bytes=[0-9]{4,}' \
    "WAV bytes count is 4+ digits (>= 1000)"
assert_match "$DRIVER_OUT" 'DETERMINISM mismatch=0' \
    "deterministic: same input -> bit-identical output"
assert_match "$DRIVER_OUT" 'EMPTY bytes=44' \
    "empty text -> 44-byte header-only WAV"

assert_file_exists "$OUT_WAV" "/tmp/tts_out.wav exists on disk"

# WAV header sanity: starts with 'RIFF', has 'WAVE' at offset 8, declares
# sample rate 16000 (0x3E80 -> 0x80 0x3E 0x00 0x00 at offsets 24..27).
if [ -f "$OUT_WAV" ]; then
    HEAD=$(od -An -tx1 -N12 "$OUT_WAV" | tr -d ' \n')
    if [[ "$HEAD" == 52494646* ]]; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}PASS${C_RST}  WAV starts with RIFF magic (52 49 46 46)\n"
    else
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  WAV header missing RIFF; got %s\n" "$HEAD"
    fi
    if [[ "$HEAD" == *57415645* ]]; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}PASS${C_RST}  WAV contains WAVE marker at byte 8\n"
    else
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  WAV missing WAVE marker; got %s\n" "$HEAD"
    fi
    # Sample rate field
    SR=$(od -An -tx1 -j24 -N4 "$OUT_WAV" | tr -d ' \n')
    if [ "$SR" = "803e0000" ]; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}PASS${C_RST}  WAV sample rate field = 16000 (LE 80 3E 00 00)\n"
    else
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  WAV sample rate field unexpected: %s\n" "$SR"
    fi
fi

# File-size > 1KB invariant from the brief.
if [ -f "$OUT_WAV" ]; then
    BYTES=$(wc -c < "$OUT_WAV" | tr -d ' ')
    if [ "$BYTES" -gt 1024 ]; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}PASS${C_RST}  /tmp/tts_out.wav size=%s > 1024 bytes\n" "$BYTES"
    else
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  /tmp/tts_out.wav too small: %s bytes\n" "$BYTES"
    fi
fi

# ---- chat dispatch path ---------------------------------------------------
require_chat

CHAT_HELP=$(run_chat "/help")
assert_match "$CHAT_HELP" '/say TEXT' \
    "chat /help advertises the new /say command"
assert_match "$CHAT_HELP" 'R21C' \
    "chat /help labels /say as R21C"

# Wipe pre-existing WAV so the chat test asserts on fresh output.
rm -f "$OUT_WAV"
CHAT_SAY=$(run_chat "/say hello world")
assert_match "$CHAT_SAY" "said 'hello world'" \
    "chat /say echoes the spoken text"
assert_match "$CHAT_SAY" 'wrote /tmp/tts_out.wav' \
    "chat /say reports the WAV path"
assert_match "$CHAT_SAY" 'phonemes=[89]' \
    "chat /say reports phoneme count in the 8..9 range"
assert_file_exists "$OUT_WAV" "chat /say wrote the WAV"

CHAT_SAY_EMPTY=$(run_chat "/say")
assert_match "$CHAT_SAY_EMPTY" '/say needs TEXT' \
    "chat /say with no arg shows graceful usage"
assert_nomatch "$CHAT_SAY_EMPTY" 'said ' \
    "chat /say with no arg does NOT emit a spoken-text line"

summary "scenario_ffff_tts"
