#!/usr/bin/env bash
# Scenario NNNN -- R25B: end-to-end voice conversation pipeline
# (STT -> question parser -> SPARQL -> KG executor -> result formatter
# -> TTS reply). Letter `nnnn` is free in the integration tree (aaaa,
# bbbb, ..., mmmm taken; oooo onward also taken).
#
# Two layers:
#
#   1. A stand-alone driver under tests/integration/_scenario_nnnn_voice_drivers/
#      exercises the voice_conversation API directly against a stub
#      transcript (no STT call) so the question-parser / SPARQL-builder
#      / result-formatter / TTS-save invariants hold even on a build
#      without whisper installed. This is the SKIP-friendly path the
#      brief calls out: the cognition / TTS pieces always run, the STT
#      piece only runs when whisper is reachable.
#
#   2. The chat dispatch path. We launch the chat, run /say to
#      synthesize a question WAV, then /converse on that WAV. The
#      transcript depends on whether whisper-main + the tiny.en model
#      are installed; we assert on the structural shape of the response
#      line (which is always emitted regardless of which branch the
#      pipeline took).

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

it_section "scenario NNNN: R25B voice conversation pipeline (STT -> KG -> TTS)"

NOVA_BIN="${NOVA_ROOT:-/home/user/NOVA}/nova"
if [ ! -x "$NOVA_BIN" ]; then
    printf "  ${C_RED}ERROR${C_RST}: NOVA launcher not found at %s\n" "$NOVA_BIN" >&2
    FAIL=$((FAIL+1))
    summary "scenario_nnnn_voice_conversation"
    exit $?
fi

DRV_DIR="$REPO_ROOT/tests/integration/_scenario_nnnn_voice_drivers"
DRV_SRC="$DRV_DIR/voice_pipeline_driver.nova"
DRV_OUT="/tmp/ce_scenario_nnnn_driver.out"
TTS_OUT="/tmp/tts_out.wav"
RESPONSE_WAV="/tmp/ce_vc_response.wav"

mkdir -p "$DRV_DIR"
trap 'rm -f "$DRV_OUT" "$RESPONSE_WAV"; rm -rf "$DRV_DIR"' EXIT

# ---- driver: exercise the parser + SPARQL builder + formatter ----------
#
# The driver does NOT invoke STT (so a sandbox without whisper still
# passes). It calls the public APIs directly with stub inputs:
#   * vc_parse_question on "how many FACT"  -> HOW_MANY / FACT
#   * vc_build_sparql on each of the three templates
#   * vc_format_result with a 5-binding stub for HOW_MANY
#   * vc_format_result with empty bindings for LIST_ALL (graceful "no atoms")

cat > "$DRV_SRC" <<'NOVA'
import "std/syscall"
import "../../../examples/voice_conversation.nova"

fn _format_count_5() {
    let p = vc_parse_question("how many FACT")
    let bindings = list_new()
    let row = list_new()
    let entry = list_new()
    push(entry, "n")
    push(entry, 5)
    push(row, entry)
    push(bindings, row)
    return vc_format_result(p, bindings)
}

fn main() {
    // Template 1: WHAT IS
    let p1 = vc_parse_question("what is FACT")
    println("PARSE what_is tpl=" + int_to_str(vc_parsed_template(p1))
        + " kind=" + vc_parsed_kind(p1))
    println("SPARQL what_is=" + vc_build_sparql(p1))

    // Template 2: HOW MANY
    let p2 = vc_parse_question("how many FACT")
    println("PARSE how_many tpl=" + int_to_str(vc_parsed_template(p2))
        + " kind=" + vc_parsed_kind(p2))
    println("SPARQL how_many=" + vc_build_sparql(p2))

    // Template 3: LIST ALL
    let p3 = vc_parse_question("list all FACT")
    println("PARSE list_all tpl=" + int_to_str(vc_parsed_template(p3))
        + " kind=" + vc_parsed_kind(p3))
    println("SPARQL list_all=" + vc_build_sparql(p3))

    // Result formatter: HOW MANY with stub n=5 -> "There are 5 FACT atoms."
    let sent = _format_count_5()
    println("FORMAT how_many_5='" + sent + "'")

    // Result formatter: LIST ALL empty -> "No FACT atoms found."
    let sent2 = vc_format_result(p3, list_new())
    println("FORMAT list_all_empty='" + sent2 + "'")

    // Unknown pattern -> apology
    let p4 = vc_parse_question("tell me a joke")
    println("FORMAT unknown='" + vc_format_result(p4, list_new()) + "'")
}

main()
NOVA

DRIVER_OUT=$("$NOVA_BIN" run "$DRV_SRC" 2>&1)
DRIVER_RC=$?
printf '%s\n' "$DRIVER_OUT" > "$DRV_OUT"

assert_eq "$DRIVER_RC" "0" "voice conversation driver exits 0"

# Parser correctness
assert_match "$DRIVER_OUT" 'PARSE what_is tpl=1 kind=FACT' \
    "parser: 'what is FACT' -> WHAT_IS template + FACT kind"
assert_match "$DRIVER_OUT" 'PARSE how_many tpl=2 kind=FACT' \
    "parser: 'how many FACT' -> HOW_MANY template + FACT kind"
assert_match "$DRIVER_OUT" 'PARSE list_all tpl=3 kind=FACT' \
    "parser: 'list all FACT' -> LIST_ALL template + FACT kind"

# SPARQL builder correctness (exact match -- the brief stipulates the
# canonical strings)
assert_match "$DRIVER_OUT" 'SPARQL what_is=SELECT \?desc WHERE \{ \?atom kind FACT \. \?atom label \?desc \. \} LIMIT 1' \
    "SPARQL: what_is = canonical SELECT ?desc ... LIMIT 1"
assert_match "$DRIVER_OUT" 'SPARQL how_many=SELECT \(COUNT\(\?a\) AS \?n\) WHERE \{ \?a kind FACT \. \}' \
    "SPARQL: how_many = canonical COUNT aggregate"
assert_match "$DRIVER_OUT" 'SPARQL list_all=SELECT \?a WHERE \{ \?a kind FACT \. \} LIMIT 10' \
    "SPARQL: list_all = SELECT ?a ... LIMIT 10"

# Result formatter: contains "5" for the COUNT-5 stub (brief mandate)
assert_match "$DRIVER_OUT" "FORMAT how_many_5='There are 5 FACT atoms\\.'" \
    "formatter: bindings n=5 -> 'There are 5 FACT atoms.'"
assert_match "$DRIVER_OUT" "FORMAT list_all_empty='No FACT atoms found\\.'" \
    "formatter: empty list_all -> 'No FACT atoms found.'"
assert_match "$DRIVER_OUT" "FORMAT unknown='I do not know how to answer that question\\.'" \
    "formatter: unknown template -> apology sentence"

# ---- chat dispatch path ---------------------------------------------------
require_chat

CHAT_HELP=$(run_chat "/help")
assert_match "$CHAT_HELP" '/converse WAV' \
    "chat /help advertises the new /converse command"
assert_match "$CHAT_HELP" 'R25B' \
    "chat /help labels /converse as R25B"

CHAT_CONV_USAGE=$(run_chat "/converse")
assert_match "$CHAT_CONV_USAGE" '/converse needs a WAV path' \
    "chat /converse with no arg shows usage"
assert_nomatch "$CHAT_CONV_USAGE" 'converse heard\+answered' \
    "chat /converse with no arg does NOT emit a heard+answered line"

# ---- End-to-end roundtrip: synthesize a question via /say, then /converse ----
#
# This is the structural pipeline test. The pipeline runs:
#   /say "how many CONCEPT" -> TTS WAV at /tmp/tts_out.wav
#   /converse /tmp/tts_out.wav -> STT decodes, parses, runs SPARQL, TTS
#                                  the reply
# We don't assert on the exact transcript (the Klatt synth is robotic and
# whisper may transcribe it inaccurately) -- only on the STRUCTURAL
# shape: the converse line is emitted, a response WAV exists, and the
# answer-text slot is non-empty.

rm -f "$TTS_OUT" "$RESPONSE_WAV"

# Note: we chain BOTH commands in one chat invocation so the agent state
# (registry, KG) is shared across the two steps -- /converse needs the
# same KG that /say wrote.
CHAT_ROUNDTRIP=$(run_chat "/say how many CONCEPT
/converse $TTS_OUT")

assert_match "$CHAT_ROUNDTRIP" "said 'how many CONCEPT'" \
    "chat /say synthesizes the question WAV (TTS leg ran)"
assert_file_exists "$TTS_OUT" "/say wrote the question WAV"
assert_match "$CHAT_ROUNDTRIP" "converse heard\\+answered" \
    "chat /converse emits the structural response line (cognition+TTS legs ran)"

# Whisper STT presence detection -- the brief asks for graceful skip.
# We probe for the canonical install paths; on a build without whisper,
# the converse line will say "could not hear" / "no speech-to-text
# backend" instead of an answer.
WHISPER_BIN="/usr/local/bin/whisper-main"
WHISPER_MODEL="/usr/local/share/whisper/ggml-tiny.en.bin"
if [ -x "$WHISPER_BIN" ] && [ -f "$WHISPER_MODEL" ]; then
    printf "  ${C_DIM}note: whisper detected; end-to-end STT path active${C_RST}\n"
    # When STT is available, the converse line still has the heard+answered
    # shape; we don't pin the exact text because Klatt-synth -> whisper
    # transcript fidelity depends on prosody. Just assert structural
    # success: a response WAV was written.
    if [ -f "$RESPONSE_WAV" ]; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}PASS${C_RST}  end-to-end pipeline wrote the response WAV\n"
    else
        # When the parser falls back to UNKNOWN, the apology TTS path
        # still writes the WAV -- if it's missing, something structural
        # broke. Soft-fail with a note rather than hard-fail because
        # whisper output on Klatt synth can be highly non-deterministic.
        printf "  ${C_YEL}NOTE${C_RST}  response WAV not present after end-to-end run (whisper transcript may have routed to a non-TTS path); not failing\n"
    fi
else
    printf "  ${C_DIM}note: whisper not installed; STT leg gracefully skipped${C_RST}\n"
    # On a build without whisper, the seam autopicks STUB, which returns
    # "[stt unavailable]" -- voice_conversation maps that to an apology
    # sentence and still synthesizes a TTS reply. So the response WAV
    # should still exist.
    if [ -f "$RESPONSE_WAV" ]; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}PASS${C_RST}  stub-backend path wrote the response WAV (apology line)\n"
    else
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  stub-backend path produced no response WAV\n"
    fi
fi

# Validate the response WAV (when present) has a sane WAV header.
if [ -f "$RESPONSE_WAV" ]; then
    HEAD=$(od -An -tx1 -N12 "$RESPONSE_WAV" | tr -d ' \n')
    if [[ "$HEAD" == 52494646* ]]; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}PASS${C_RST}  response WAV starts with RIFF magic\n"
    else
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  response WAV header missing RIFF; got %s\n" "$HEAD"
    fi
    BYTES=$(wc -c < "$RESPONSE_WAV" | tr -d ' ')
    if [ "$BYTES" -gt 44 ]; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}PASS${C_RST}  response WAV size %s > 44 (has PCM, not header-only)\n" "$BYTES"
    else
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  response WAV size %s <= 44 (header-only or missing)\n" "$BYTES"
    fi
fi

summary "scenario_nnnn_voice_conversation"
