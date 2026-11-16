#!/usr/bin/env bash
# Scenario web-hardening -- audit F-18 for scripts/web.py.
#   - /api/sessions and /metrics must not publish raw ce_sid cookie values
#     (the only session credential).
#   - Host header must be one of ours (DNS-rebinding guard).
#   - POST /api/chat must be application/json and same-origin (CSRF guard).

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0
it_section "scenario web-hardening: no cookie leak, Host/Origin/Content-Type checks"

for tool in python3 curl; do
    if ! command -v $tool >/dev/null 2>&1; then
        printf "  ${C_YEL}SKIP${C_RST}  %s missing\n" "$tool"
        PASS=$((PASS+1)); summary "scenario_web_hardening"; exit $?
    fi
done

PORT=$((20000 + (RANDOM % 1000)))
JAR=$(mktemp); LOG=$(mktemp)
CE_PORT="$PORT" CE_BIN="$CHAT" python3 "$WEB_PY" >"$LOG" 2>&1 &
SRV=$!
trap 'kill $SRV 2>/dev/null; wait $SRV 2>/dev/null; rm -f "$JAR" "$LOG"' EXIT
for _ in $(seq 1 15); do
    grep -q "CrossEngin web at" "$LOG" 2>/dev/null && break
    kill -0 $SRV 2>/dev/null || break
    sleep 1
done
URL="http://127.0.0.1:$PORT"

# Create a session (cookie lands in the jar).
curl -s --max-time 60 -c "$JAR" -b "$JAR" -H 'Content-Type: application/json' \
     -d '{"message":"hello"}' "$URL/api/chat" >/dev/null
SID=$(awk '$6=="ce_sid"{print $7}' "$JAR" | tail -1)
assert_match "$SID" '^[0-9a-f-]{36}$' "a session cookie was issued"

SESS=$(curl -s --max-time 10 "$URL/api/sessions")
assert_nomatch "$SESS" "$SID" "/api/sessions does not contain the cookie value"
assert_match "$SESS" '"id": "s-[0-9a-f]{12}"' "/api/sessions shows an opaque id"
METRICS=$(curl -s --max-time 30 "$URL/metrics")
assert_nomatch "$METRICS" "$SID" "/metrics does not contain the cookie value"

CODE=$(curl -s --max-time 10 -o /dev/null -w '%{http_code}' -H 'Host: evil.example' "$URL/api/sessions")
assert_eq "$CODE" "403" "foreign Host header -> 403"

CODE=$(curl -s --max-time 10 -o /dev/null -w '%{http_code}' -H 'Origin: http://evil.example' \
       -H 'Content-Type: application/json' -d '{"message":"/status"}' "$URL/api/chat")
assert_eq "$CODE" "403" "cross-origin POST -> 403"

CODE=$(curl -s --max-time 10 -o /dev/null -w '%{http_code}' -H 'Content-Type: text/plain' \
       -d '{"message":"/status"}' "$URL/api/chat")
assert_eq "$CODE" "415" "text/plain POST (no preflight) -> 415"

CODE=$(curl -s --max-time 60 -o /dev/null -w '%{http_code}' -H "Origin: http://127.0.0.1:$PORT" \
       -H 'Content-Type: application/json' -b "$JAR" -d '{"message":"hello"}' "$URL/api/chat")
assert_eq "$CODE" "200" "same-origin JSON POST still works"

summary "scenario_web_hardening"
