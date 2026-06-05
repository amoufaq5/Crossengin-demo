#!/usr/bin/env bash
# Scenario Y -- CE_LOG_JSON=1 emits valid one-line JSON per turn.
#
# Launch bin/crossengin-chat with CE_LOG_JSON=1 in the env, feed "fever",
# capture stdout, isolate the perception log line, and verify that
# `python3 -c "import json; json.loads(LINE)"` parses it. Also asserts:
#   * the parsed object has the documented fields (ts, level, session,
#     event=="perceive", msg=="fever", m, unk)
#   * default mode (CE_LOG_JSON unset) does NOT emit JSON (backward-compat)
#
# Why python3 instead of a regex: the brief mandates that downstream
# log aggregators can pipe these lines straight into `json.loads`, so the
# verifier IS json.loads.

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0

# python3 is a required dep for this scenario. The doctor's optional-tools
# section flags it, but here we hard-skip with a clean message rather than
# fail the suite if the env truly lacks python3.
if ! command -v python3 >/dev/null 2>&1; then
    printf "  ${C_YEL}SKIP${C_RST}  python3 not available; cannot verify json.loads\n"
    summary "scenario_y_json_logs"
    exit $?
fi

it_section "scenario Y: CE_LOG_JSON=1 emits valid JSON"

# Clean state: fresh dlog + snapshot per run so the boot banner is consistent.
rm -f /tmp/crossengin.default.snap /tmp/crossengin.default.dlog \
      /tmp/crossengin.dlog

OUT="$(printf 'fever\n/quit\n' | CE_LOG_JSON=1 "$CHAT" 2>&1)"

# --- step 1: the perceive line is JSON --------------------------------------
# The JSON line is prefixed by the "> " prompt in stdout because the chat
# echoes its prompt before draining; strip leading "> " before parsing.
JSON_LINE="$(printf '%s\n' "$OUT" \
    | grep -E '\{"ts":.*"event":"perceive"' \
    | head -n 1 \
    | sed -E 's/^(> )+//')"
if [ -z "$JSON_LINE" ]; then
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  no perceive JSON line in output\n"
    printf '%s\n' "$OUT" | tail -10 | sed 's/^/        /'
else
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  perceive line captured: %s\n" "$JSON_LINE"

    # The hard verification: python3's json.loads must accept it.
    if python3 -c "import json,sys; json.loads(sys.argv[1])" "$JSON_LINE" 2>/dev/null; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}PASS${C_RST}  json.loads parses the perceive line\n"
    else
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  json.loads rejected: %s\n" "$JSON_LINE"
    fi

    # Documented field set: ts, level, session, event, msg, m, unk.
    FIELDS_OK="$(python3 -c '
import json, sys
d = json.loads(sys.argv[1])
need = {"ts","level","session","event","msg","m","unk"}
missing = need - set(d.keys())
print("OK" if not missing else "MISSING:" + ",".join(sorted(missing)))
print("event=" + str(d.get("event")))
print("msg=" + str(d.get("msg")))
print("m=" + str(d.get("m")))
print("unk=" + str(d.get("unk")))
' "$JSON_LINE" 2>/dev/null)"
    assert_match "$FIELDS_OK" "^OK$"             "all documented fields present"
    assert_match "$FIELDS_OK" "event=perceive"   "event field == perceive"
    assert_match "$FIELDS_OK" "msg=fever"        "msg field == fever (the input)"
    assert_match "$FIELDS_OK" "m=1"              "m field == 1 (fever is known)"
    assert_match "$FIELDS_OK" "unk=0"            "unk field == 0 (no unknown tokens)"
fi

# --- step 2: also confirm the reply line is JSON when in JSON mode ---------
REPLY_LINE="$(printf '%s\n' "$OUT" \
    | grep -E '\{"ts":.*"event":"reply"' \
    | head -n 1 \
    | sed -E 's/^(> )+//')"
if [ -n "$REPLY_LINE" ]; then
    if python3 -c "import json,sys; json.loads(sys.argv[1])" "$REPLY_LINE" 2>/dev/null; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}PASS${C_RST}  reply line is also valid JSON\n"
    else
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  reply line malformed: %s\n" "$REPLY_LINE"
    fi
else
    # Not strictly required by the brief but a useful canary.
    printf "  ${C_YEL}note${C_RST}  no reply JSON line found (only the perceive line is mandatory)\n"
fi

# --- step 3: backward-compat -- default mode emits NO JSON -----------------
rm -f /tmp/crossengin.default.snap /tmp/crossengin.default.dlog \
      /tmp/crossengin.dlog
OUT_DEFAULT="$(printf 'fever\n/quit\n' | "$CHAT" 2>&1)"
DEFAULT_HAS_JSON="$(printf '%s\n' "$OUT_DEFAULT" \
    | grep -E '\{"ts":.*"event":"perceive"' | wc -l)"
if [ "$DEFAULT_HAS_JSON" -eq 0 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  default mode (no CE_LOG_JSON) emits NO JSON\n"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  default mode unexpectedly emitted JSON (%d lines)\n" \
        "$DEFAULT_HAS_JSON"
fi
# Also assert the legacy human-readable perceive line is preserved in default.
assert_match "$OUT_DEFAULT" "perceive\\(m=[0-9]+,unk=[0-9]+\\)" \
    "default mode keeps legacy 'perceive(m=N,unk=N)' line"

summary "scenario_y_json_logs"
