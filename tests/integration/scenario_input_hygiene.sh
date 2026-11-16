#!/usr/bin/env bash
# Scenario input-hygiene -- audit F-22 + F-25.
#   F-25: a line longer than read_line()'s 1023-byte chunk used to be split,
#         so 1023 x "a" + "/status" executed /status. A NUL byte inside the
#         first chunk had the same effect, and the approval prompt read only
#         the first chunk of its answer line, so the rest ran as a command.
#   F-22: the keyword auto-prefix turned "good morning" into /good (a reward
#         signal). Bare "good" must still work.

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0
it_section "scenario input-hygiene: long-line smuggling + bare-only auto-prefix"

IN="$(mktemp)"
trap 'rm -f "$IN"' EXIT

python3 -c "print('a' * 1023 + '/status'); print('/quit')" > "$IN"
OUT=$(timeout 60 "$CHAT" < "$IN" 2>&1)
assert_nomatch "$OUT" "soul +: Aurora" "1023-byte prefix + /status does not run /status"
assert_match   "$OUT" "bye\\." "chat exits cleanly after the long line"

python3 -c "import sys; sys.stdout.buffer.write(b'x\x00' + b'A' * 1021 + b'/status\n/quit\n')" > "$IN"
OUT=$(timeout 60 "$CHAT" < "$IN" 2>&1)
assert_nomatch "$OUT" "soul +: Aurora" "NUL inside the first chunk does not split the line"

python3 -c "import sys; sys.stdout.buffer.write(b'/learn http://127.0.0.1:9/x\n' + b'n' * 1023 + b'/status\n/quit\n')" > "$IN"
OUT=$(timeout 60 "$CHAT" < "$IN" 2>&1)
assert_match   "$OUT" "declined \\(fetch URL\\)" "over-long approval answer is a decline"
assert_nomatch "$OUT" "soul +: Aurora" "approval answer tail does not run as a command"

OUT=$(printf 'fever\ngood morning\n/quit\n' | timeout 60 "$CHAT" 2>&1)
assert_nomatch "$OUT" "reinforced" "'good morning' is not treated as /good"

OUT=$(printf 'fever\ngood\n/quit\n' | timeout 60 "$CHAT" 2>&1)
assert_match "$OUT" "reinforced" "bare 'good' still auto-prefixes to /good"

summary "scenario_input_hygiene"
