#!/usr/bin/env bash
# Failure mode -- web.py LRU eviction: with CE_WEB_MAX_SESSIONS=2, hitting
# 5 unique cookies must evict the first 3 (LRU) and keep the most-recent 2
# in the session store.
#
# We use 5 hand-crafted UUID cookies (well-formed so the _valid_uuid filter
# admits them). Each /api/chat request with a distinct cookie spawns one
# ChatChild. After 5 requests, /api/sessions must list exactly 2 entries
# (the two most-recent cookies).

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0

it_section "failmode: web LRU eviction (CE_WEB_MAX_SESSIONS=2, 5 cookies)"

if ! command -v python3 >/dev/null 2>&1; then
    printf "  ${C_YEL}SKIP${C_RST}  python3 missing -- eviction test skipped\n"
    PASS=$((PASS+1))
    summary "failmode_session_eviction"
    exit $?
fi
if ! command -v curl >/dev/null 2>&1; then
    printf "  ${C_YEL}SKIP${C_RST}  curl missing -- eviction test skipped\n"
    PASS=$((PASS+1))
    summary "failmode_session_eviction"
    exit $?
fi
if [ ! -f "$WEB_PY" ]; then
    printf "  ${C_YEL}SKIP${C_RST}  %s missing -- eviction test skipped\n" "$WEB_PY"
    PASS=$((PASS+1))
    summary "failmode_session_eviction"
    exit $?
fi

PORT=$((24000 + (RANDOM % 1000)))
OUT_LOG=/tmp/ce_int_evict_$$.log
trap 'kill -TERM $SRV_PID 2>/dev/null; kill -9 $SRV_PID 2>/dev/null; rm -f "$OUT_LOG"' EXIT
rm -f "$OUT_LOG"

# Cap to 2.
CE_PORT="$PORT" CE_BIN="$CHAT" CE_WEB_MAX_SESSIONS=2 python3 "$WEB_PY" >"$OUT_LOG" 2>&1 &
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
    summary "failmode_session_eviction"
    exit $?
fi
PASS=$((PASS+1))
printf "  ${C_GRN}PASS${C_RST}  web server booted on port %s with max_sessions=2\n" "$PORT"
assert_match "$(cat "$OUT_LOG")" "max sessions=2" "boot banner confirms max_sessions=2"

# Make 5 unique UUID cookies.
COOKIES=()
for i in 1 2 3 4 5; do
    c=$(python3 -c "import uuid; print(uuid.uuid4())")
    COOKIES+=("$c")
done

# Fire 5 sequential requests, each with a distinct cookie. We sleep 0.5s
# between each so the last_active_ms ordering is unambiguous (the LRU pick
# wants the smallest timestamp).
for i in 0 1 2 3 4; do
    sid="${COOKIES[$i]}"
    RESP=$(curl -s --max-time 15 \
        -H "Cookie: ce_sid=$sid" \
        -X POST -H 'Content-Type: application/json' \
        -d '{"message":"hello"}' "http://127.0.0.1:$PORT/api/chat")
    if echo "$RESP" | grep -qE '"reply"|"error"'; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}PASS${C_RST}  cookie #%d (%s...) got a response\n" "$((i+1))" "${sid:0:8}"
    else
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  cookie #%d got no response: %s\n" "$((i+1))" "$RESP"
    fi
    sleep 0.5
done

# Now query /api/sessions. With max=2, only the LAST two cookies should
# survive. The first 3 should have been evicted.
SESSIONS_JSON=$(curl -s --max-time 10 "http://127.0.0.1:$PORT/api/sessions")
assert_match "$SESSIONS_JSON" '"sessions"' "/api/sessions returned a sessions array"

# Count entries.
SESS_COUNT=$(echo "$SESSIONS_JSON" | grep -oE '"id"' | wc -l)
assert_eq "$SESS_COUNT" "2" "/api/sessions reports exactly 2 (max_sessions) entries"

# The last 2 cookies must be the ones present.
LAST1="${COOKIES[3]}"
LAST2="${COOKIES[4]}"
EVICTED1="${COOKIES[0]}"
EVICTED2="${COOKIES[1]}"
EVICTED3="${COOKIES[2]}"
assert_match "$SESSIONS_JSON" "$LAST1" "most-recent-2: cookie #4 present"
assert_match "$SESSIONS_JSON" "$LAST2" "most-recent-2: cookie #5 present"
assert_nomatch "$SESSIONS_JSON" "$EVICTED1" "cookie #1 was evicted (LRU)"
assert_nomatch "$SESSIONS_JSON" "$EVICTED2" "cookie #2 was evicted (LRU)"
assert_nomatch "$SESSIONS_JSON" "$EVICTED3" "cookie #3 was evicted (LRU)"

# Cleanup.
kill -TERM "$SRV_PID" 2>/dev/null
for i in 1 2 3 4 5; do
    sleep 0.3
    if ! kill -0 "$SRV_PID" 2>/dev/null; then break; fi
done
kill -KILL "$SRV_PID" 2>/dev/null
wait "$SRV_PID" 2>/dev/null || true

summary "failmode_session_eviction"
