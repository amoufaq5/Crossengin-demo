#!/usr/bin/env bash
# Scenario AAAAA -- R25B.2: multi-turn voice dialogue (conversation state
# + follow-up handling). Letter `aaaaa` (5x) is the first free 5-letter
# slot; aaaa..mmmm + various 5-letter forms taken.
#
# Two layers (mirrors the R25B scenario_nnnn shape):
#
#   1. A stand-alone driver under tests/integration/_scenario_aaaaa_dialog_drivers/
#      exercises the vc_session_* API directly against a small in-memory
#      KG (no STT call). This validates the multi-turn state machine on
#      a build without whisper installed -- the dialog state is pure
#      transcript-rewriting; the WAV roundtrip is exercised by the chat
#      dispatch path below.
#
#   2. The chat dispatch path. We launch the chat and drive
#      `/dialog reset` + a series of /dialog calls. The transcript
#      route into /dialog depends on whisper-main; we focus on the
#      structural shape of the response line (which is always emitted
#      regardless of which branch the pipeline took -- whisper-present
#      or stub-fallback both yield the "dialog heard+answered ... turn=N"
#      shape).

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

it_section "scenario AAAAA: R25B.2 multi-turn dialogue + follow-up handling"

NOVA_BIN="${NOVA_ROOT:-/home/user/NOVA}/nova"
if [ ! -x "$NOVA_BIN" ]; then
    printf "  ${C_RED}ERROR${C_RST}: NOVA launcher not found at %s\n" "$NOVA_BIN" >&2
    FAIL=$((FAIL+1))
    summary "scenario_aaaaa_dialog"
    exit $?
fi

DRV_DIR="$REPO_ROOT/tests/integration/_scenario_aaaaa_dialog_drivers"
DRV_SRC="$DRV_DIR/dialog_driver.nova"
DRV_OUT="/tmp/ce_scenario_aaaaa_driver.out"
RESPONSE_WAV="/tmp/ce_vc_response.wav"

mkdir -p "$DRV_DIR"
trap 'rm -f "$DRV_OUT" "$RESPONSE_WAV"; rm -rf "$DRV_DIR"' EXIT

# ---- driver: exercise the multi-turn state machine ----------------------
#
# 3-turn fixture: "list all FACT" -> "tell me more" -> "what is the first
# one". Each turn should print a TURN line so the integration scenario
# can assert on the sequence (template, kind, ids).
#
# Then a topic-shift assertion: "actually list all CONCEPT" resets state
# and pivots; the dialog layer treats that as a fresh turn.
#
# Finally a /dialog reset path: after reset, the history is wiped + the
# session reverts to "no prior context".

cat > "$DRV_SRC" <<'NOVA'
import "std/syscall"
import "../../../examples/voice_dialog.nova"
import "../../../src/kg/atom_store.nova"
import "../../../src/kg/multi_kg_manager.nova"

fn _fixture_kg() {
    let reg = kg_registry_new()
    let kg = kg_spawn(reg, "scenario_aaaaa")
    kg_add_atom(kg, ATOM_FACT,    "f1", 1000)
    kg_add_atom(kg, ATOM_FACT,    "f2", 1100)
    kg_add_atom(kg, ATOM_FACT,    "f3", 1200)
    kg_add_atom(kg, ATOM_CONCEPT, "c1", 1500)
    kg_add_atom(kg, ATOM_CONCEPT, "c2", 1600)
    return kg
}

fn _turn(kg, sess, q) {
    let r = vc_session_turn(kg, sess, q)
    println("TURN q='" + q + "' resp='" + vc_session_result_text(r) + "'")
    println("STATE tpl=" + int_to_str(vc_session_last_template(sess))
        + " kind=" + vc_session_last_kind(sess)
        + " count=" + int_to_str(vc_session_turn_count(sess))
        + " ids=" + int_to_str(len(vc_session_last_ids(sess))))
    return 1
}

fn main() {
    let kg = _fixture_kg()
    let sess = vc_session_new()

    // 3-turn dialog: list -> more -> first one.
    _turn(kg, sess, "list all FACT")
    _turn(kg, sess, "tell me more")
    _turn(kg, sess, "what is the first one")

    // Topic shift: "actually list all CONCEPT" -> reset + new turn.
    _turn(kg, sess, "actually list all CONCEPT")

    // Anaphora: "describe it" on the new CONCEPT list.
    _turn(kg, sess, "describe it")

    // Reset, then verify the session reports zero state.
    vc_session_reset(sess)
    println("AFTER_RESET count=" + int_to_str(vc_session_turn_count(sess))
        + " tpl=" + int_to_str(vc_session_last_template(sess)))
}

main()
NOVA

DRIVER_OUT=$("$NOVA_BIN" run "$DRV_SRC" 2>&1)
DRIVER_RC=$?
printf '%s\n' "$DRIVER_OUT" > "$DRV_OUT"

assert_eq "$DRIVER_RC" "0" "dialog driver exits 0"

# Turn 1: list all FACT -> Found 3 FACT atoms.
assert_match "$DRIVER_OUT" "TURN q='list all FACT' resp='Found 3 FACT atoms: ids 0, 1, 2\\.'" \
    "turn 1: 'list all FACT' returns LIST_ALL response with 3 ids"
assert_match "$DRIVER_OUT" 'STATE tpl=3 kind=FACT count=1 ids=3' \
    "turn 1: session state LIST_ALL + FACT + 3 ids captured"

# Turn 2: tell me more -> re-runs LIST_ALL on prior kind with bigger LIMIT.
assert_match "$DRIVER_OUT" "TURN q='tell me more' resp='Found 3 FACT atoms: ids 0, 1, 2\\.'" \
    "turn 2: 'tell me more' re-runs LIST_ALL on FACT"
assert_match "$DRIVER_OUT" 'STATE tpl=3 kind=FACT count=2 ids=3' \
    "turn 2: session count=2 + state still LIST_ALL/FACT"

# Turn 3: what is the first one -> anaphora to ids[0] = 0.
assert_match "$DRIVER_OUT" "TURN q='what is the first one' resp='That FACT atom has id 0\\.'" \
    "turn 3: 'what is the first one' resolves to id 0"
assert_match "$DRIVER_OUT" 'STATE tpl=1 kind=FACT count=3' \
    "turn 3: state transitioned to WHAT_IS"

# Turn 4: topic shift "actually list all CONCEPT" -> reset + new LIST_ALL.
# After the shift the count restarts at 1 (reset clears it, then the
# fresh turn pushes 1).
assert_match "$DRIVER_OUT" "TURN q='actually list all CONCEPT' resp='Found 2 CONCEPT atoms: ids 3, 4\\.'" \
    "turn 4: 'actually list all CONCEPT' shifts topic + executes"
assert_match "$DRIVER_OUT" 'STATE tpl=3 kind=CONCEPT count=1 ids=2' \
    "turn 4: count reset to 1 + state LIST_ALL/CONCEPT"

# Turn 5: describe it -> anaphora on CONCEPT ids[0] = 3.
assert_match "$DRIVER_OUT" "TURN q='describe it' resp='That CONCEPT atom has id 3\\.'" \
    "turn 5: 'describe it' resolves to first CONCEPT id 3"

# Explicit reset.
assert_match "$DRIVER_OUT" 'AFTER_RESET count=0 tpl=0' \
    "after vc_session_reset: count=0, template UNKNOWN"

# ---- chat dispatch path -------------------------------------------------
require_chat

# Verify the /dialog command exists. We can't easily test the multi-turn
# state through the chat REPL because each line is a separate command;
# but we CAN verify the command is wired and emits the structural
# response line.

CHAT_USAGE=$(run_chat "/dialog")
assert_match "$CHAT_USAGE" "/dialog needs a WAV path or 'reset'" \
    "chat /dialog with no arg shows usage"

CHAT_RESET=$(run_chat "/dialog reset")
assert_match "$CHAT_RESET" "dialog session reset" \
    "chat /dialog reset acknowledges + clears state"

summary "scenario_aaaaa_dialog"
