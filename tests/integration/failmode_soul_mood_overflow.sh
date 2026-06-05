#!/usr/bin/env bash
# Failure mode -- repeated high-arousal triggers must not overflow the mood
# valence / arousal counters.
#
# soul.mood.valence and soul.mood.arousal both range 0..1000 per the persistence
# format (snapshot_disk.nova). After many high-arousal turns, both fields
# must STILL be inside that range -- no integer wrap, no negative spillover,
# no >1000 readings.
#
# We pound the chat with 50 emotionally-charged inputs (alternating positive
# / negative valence triggers) and then read /status. The numeric mood line
# is `mood     : valence=NUM arousal=NUM`.

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0

it_section "failmode: 50 high-arousal turns -- mood stays in valid range"

# Build input. The emotion appraisal classifies words crudely -- we use a mix
# of strong positive ("praise excellent wonderful") and strong negative
# ("danger threat attack") plus neutral noise.
INPUT_FILE=/tmp/ce_int_mood_input_$$.txt
trap 'rm -f "$INPUT_FILE"' EXIT
{
    for i in $(seq 1 25); do
        echo "wonderful excellent praise success joy"
        echo "danger threat attack pain fear"
    done
    echo "/status"
    echo "/quit"
} > "$INPUT_FILE"

OUT=$(timeout 30 "$CHAT" <"$INPUT_FILE" 2>&1)

assert_match "$OUT" "bye\\." "chat returned cleanly after 50 mood-laden turns"

# Extract final mood line.
MOOD_LINE=$(echo "$OUT" | grep -E "^mood +: valence=" | tail -1)
if [ -z "$MOOD_LINE" ]; then
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  could not find /status mood line\n"
    summary "failmode_soul_mood_overflow"
    exit $?
fi
PASS=$((PASS+1))
printf "  ${C_GRN}PASS${C_RST}  captured mood line: %s\n" "$MOOD_LINE"

# Parse valence and arousal.
VAL=$(echo "$MOOD_LINE" | grep -oE 'valence=-?[0-9]+' | grep -oE -- '-?[0-9]+')
ARO=$(echo "$MOOD_LINE" | grep -oE 'arousal=-?[0-9]+' | grep -oE -- '-?[0-9]+')

# Valence is the 0..1000 form per src/parts/emotion/appraisal.nova (the
# signed -1000..1000 form is only used internally in plasticity_mod).
if [ -n "$VAL" ] && [ "$VAL" -ge 0 ] && [ "$VAL" -le 1000 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  valence=%s in [0, 1000]\n" "$VAL"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  valence=%s OUTSIDE [0, 1000] -- possible overflow!\n" "$VAL"
fi

# Arousal is 0..1000.
if [ -n "$ARO" ] && [ "$ARO" -ge 0 ] && [ "$ARO" -le 1000 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  arousal=%s in [0, 1000]\n" "$ARO"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  arousal=%s OUTSIDE [0, 1000] -- possible overflow!\n" "$ARO"
fi

# Also check ALL intermediate mood lines (if /status was triggered repeatedly
# it would surface them) -- here we just verify NO line shows a numeric
# overflow tell-tale like negative or 4-digit-plus values.
BAD=$(echo "$OUT" | grep -E "^mood +: " | grep -oE '(valence|arousal)=(-[0-9]+|[0-9]{5,}|[1-9][0-9]{3,})' || true)
if [ -z "$BAD" ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  no out-of-range mood value found in any /status reading\n"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  out-of-range mood readings: %s\n" "$BAD"
fi

summary "failmode_soul_mood_overflow"
