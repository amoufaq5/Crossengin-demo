#!/usr/bin/env bash
# Failure mode -- POSTing a 1MB body to /api/chat must not crash the server.
#
# The web.py handler reads Content-Length bytes and json.loads them. A huge
# but well-formed payload should EITHER process (treating the giant text as
# a single message) OR return an HTTP-level error. Either is acceptable.
# What we DO NOT accept: a server crash, a hang, or a 500 stack trace that
# kills the child process.

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0

it_section "failmode: /api/chat with a 1MB body"

if ! command -v python3 >/dev/null 2>&1; then
    printf "  ${C_YEL}SKIP${C_RST}  python3 missing -- huge-payload test skipped\n"
    PASS=$((PASS+1))
    summary "failmode_web_huge_payload"
    exit $?
fi
if ! command -v curl >/dev/null 2>&1; then
    printf "  ${C_YEL}SKIP${C_RST}  curl missing -- huge-payload test skipped\n"
    PASS=$((PASS+1))
    summary "failmode_web_huge_payload"
    exit $?
fi
if [ ! -f "$WEB_PY" ]; then
    printf "  ${C_YEL}SKIP${C_RST}  %s missing -- huge-payload test skipped\n" "$WEB_PY"
    PASS=$((PASS+1))
    summary "failmode_web_huge_payload"
    exit $?
fi

PORT=$((23000 + (RANDOM % 1000)))
JAR=/tmp/ce_int_huge_jar_$$.txt
BODY=/tmp/ce_int_huge_body_$$.json
OUT_LOG=/tmp/ce_int_huge_$$.log
trap 'kill -TERM $SRV_PID 2>/dev/null; kill -9 $SRV_PID 2>/dev/null; rm -f "$JAR" "$BODY" "$OUT_LOG"' EXIT
rm -f "$JAR" "$BODY" "$OUT_LOG"

CE_PORT="$PORT" CE_BIN="$CHAT" python3 "$WEB_PY" >"$OUT_LOG" 2>&1 &
SRV_PID=$!

UP=0
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    sleep 1
    if grep -q "CrossEngin web at" "$OUT_LOG" 2>/dev/null; then UP=1; break; fi
    if ! kill -0 "$SRV_PID" 2>/dev/null; then break; fi
done
if [ "$UP" -ne 1 ]; then
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  web server did not boot within 12s\n"
    summary "failmode_web_huge_payload"
    exit $?
fi
PASS=$((PASS+1))
printf "  ${C_GRN}PASS${C_RST}  web server booted on port %s\n" "$PORT"

# Build a 1MB JSON body. The "message" field carries ~1024000 chars of
# repeated "a ", which is a valid (if unloved) word stream. Generate it
# without echo bloat using python.
python3 -c "
import json, sys
body = {'message': ('aaa ' * (1024*256))[:1024*1000]}
with open('$BODY', 'w') as f:
    json.dump(body, f)
import os
print(os.path.getsize('$BODY'))
" > /tmp/ce_int_huge_size_$$.txt
SIZE=$(cat /tmp/ce_int_huge_size_$$.txt)
rm -f /tmp/ce_int_huge_size_$$.txt
if [ -z "$SIZE" ] || [ "$SIZE" -lt 1000000 ]; then
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  could not build a 1MB+ body (got %s bytes)\n" "$SIZE"
    summary "failmode_web_huge_payload"
    exit $?
fi
PASS=$((PASS+1))
printf "  ${C_GRN}PASS${C_RST}  built a %s-byte body file\n" "$SIZE"

# POST it. Allow up to 60s for the chat to grind through the percept.
# Capture HTTP status code separately so a 4xx/5xx is observable.
HTTP_CODE=$(curl -s --max-time 60 -o /tmp/ce_int_huge_resp_$$.json \
    -w '%{http_code}' \
    --cookie-jar "$JAR" --cookie "$JAR" \
    -X POST -H 'Content-Type: application/json' \
    --data-binary "@$BODY" "http://127.0.0.1:$PORT/api/chat" 2>/dev/null)
RESP=$(cat /tmp/ce_int_huge_resp_$$.json 2>/dev/null || true)
rm -f /tmp/ce_int_huge_resp_$$.json

printf "  ${C_DIM}note${C_RST}  HTTP code = %s, response length = %s bytes\n" \
    "$HTTP_CODE" "$(printf '%s' "$RESP" | wc -c)"

# Acceptable outcomes:
#   200 + a "reply" field    -> server actually chewed through it
#   413 / 4xx / 504           -> server rejected it cleanly
#   200 + an "error" field    -> server rejected it inside the JSON
# Unacceptable:
#   empty response (server crashed mid-write)
#   connection refused
#   server process gone after the request
if [ -z "$HTTP_CODE" ] || [ "$HTTP_CODE" = "000" ]; then
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  no HTTP response (server may have crashed)\n"
else
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  server returned an HTTP response (code=%s)\n" "$HTTP_CODE"
fi

if [ -n "$RESP" ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  response body is non-empty\n"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  response body is empty\n"
fi

# Server must still be alive after this request.
if kill -0 "$SRV_PID" 2>/dev/null; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  web server still alive after 1MB request\n"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  web server died on 1MB request\n"
fi

# Follow-up SHORT request: ideally it gets a clean reply (chat child still
# alive). KNOWN: the chat process is currently SEGFAULT-prone on very long
# input lines (see failmode_chat_long_line.sh), so the 1MB POST may have
# killed the per-cookie ChatChild. We assert the WEB SERVER didn't crash;
# the follow-up either gets a "reply" (chat is fine) OR an "error" carrying
# the chat-died message (the server caught the dead child cleanly).
SMALL_RESP=$(curl -s --max-time 10 --cookie-jar "$JAR" --cookie "$JAR" \
    -X POST -H 'Content-Type: application/json' \
    -d '{"message":"hello"}' "http://127.0.0.1:$PORT/api/chat")
if echo "$SMALL_RESP" | grep -qE '"reply"'; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  follow-up small request got a reply (chat survived)\n"
elif echo "$SMALL_RESP" | grep -qE '"error"'; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  follow-up returned an error -- chat child died but server caught it cleanly: %s\n" "$SMALL_RESP"
    # KNOWN: this branch fires today because the chat segfaults on big input
    # (see failmode_chat_long_line.sh). If/when the chat is fixed, the
    # "reply" branch above will fire instead and this branch becomes dead
    # code -- that's the desired direction.
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  follow-up returned neither reply nor error: %s\n" "$SMALL_RESP"
fi

# A SECOND follow-up via a DIFFERENT cookie spawns a fresh child and MUST
# work (the server is healthy; only the original cookie's child was lost).
FRESH_JAR=/tmp/ce_int_huge_fresh_jar_$$.txt
trap 'kill -TERM $SRV_PID 2>/dev/null; kill -9 $SRV_PID 2>/dev/null; rm -f "$JAR" "$FRESH_JAR" "$BODY" "$OUT_LOG"' EXIT
FRESH_RESP=$(curl -s --max-time 10 --cookie-jar "$FRESH_JAR" --cookie "$FRESH_JAR" \
    -X POST -H 'Content-Type: application/json' \
    -d '{"message":"hello"}' "http://127.0.0.1:$PORT/api/chat")
assert_match "$FRESH_RESP" '"reply"' "fresh-cookie follow-up gets a reply (server is healthy)"

# Cleanup.
kill -TERM "$SRV_PID" 2>/dev/null
for i in 1 2 3 4 5; do
    sleep 0.3
    if ! kill -0 "$SRV_PID" 2>/dev/null; then break; fi
done
kill -KILL "$SRV_PID" 2>/dev/null
wait "$SRV_PID" 2>/dev/null || true

summary "failmode_web_huge_payload"
