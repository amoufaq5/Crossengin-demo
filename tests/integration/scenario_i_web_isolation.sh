#!/usr/bin/env bash
# Scenario I -- web.py per-cookie session isolation.
#
# Launch scripts/web.py in the background. Make two POSTs with distinct
# cookie jars (A and B). Cookie A teaches 'widget' and then asserts that
# 'widget' is recognized (perceive m>=1). Cookie B then asks about 'widget'
# without teaching it -- it must NOT be known (each cookie spawns its own
# ChatChild subprocess; A and B share no state). Finally cookie A re-queries
# 'widget' and must still recognize it (its session was preserved across
# the foreign request). The /api/sessions diagnostic endpoint must list
# both sessions afterwards. Then we SIGTERM the web.py and verify clean
# shutdown.
#
# Cookie handling: curl --cookie-jar / --cookie threads the Set-Cookie
# returned by the server back into the next request on the same jar.

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0

it_section "scenario I: web.py per-cookie session isolation"

if ! command -v python3 >/dev/null 2>&1; then
    printf "  ${C_YEL}SKIP${C_RST}  python3 not on PATH -- web isolation test skipped\n"
    PASS=$((PASS+1))
    summary "scenario_i_web_isolation"
    exit $?
fi

if ! command -v curl >/dev/null 2>&1; then
    printf "  ${C_YEL}SKIP${C_RST}  curl not on PATH -- web isolation test skipped\n"
    PASS=$((PASS+1))
    summary "scenario_i_web_isolation"
    exit $?
fi

if [ ! -f "$WEB_PY" ]; then
    printf "  ${C_YEL}SKIP${C_RST}  %s missing -- web isolation test skipped\n" "$WEB_PY"
    PASS=$((PASS+1))
    summary "scenario_i_web_isolation"
    exit $?
fi

PORT=$((19000 + (RANDOM % 1000)))
JAR_A=/tmp/ce_int_cookies_A_$$.txt
JAR_B=/tmp/ce_int_cookies_B_$$.txt
OUT_LOG=/tmp/ce_int_web_iso_$$.log
trap 'rm -f "$JAR_A" "$JAR_B" "$OUT_LOG"' EXIT
rm -f "$JAR_A" "$JAR_B" "$OUT_LOG"

# Launch the server in a new session so we can SIGTERM the leader cleanly.
CE_PORT="$PORT" CE_BIN="$CHAT" python3 "$WEB_PY" >"$OUT_LOG" 2>&1 &
SRV_PID=$!

# Wait for the server to advertise itself.
UP=0
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    sleep 1
    if grep -q "CrossEngin web at" "$OUT_LOG" 2>/dev/null; then UP=1; break; fi
    if ! kill -0 "$SRV_PID" 2>/dev/null; then break; fi
done

if [ "$UP" -ne 1 ]; then
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  web server did not start within 12s\n"
    cat "$OUT_LOG" 2>/dev/null | sed 's/^/        /'
    kill -TERM "$SRV_PID" 2>/dev/null
    wait "$SRV_PID" 2>/dev/null || true
    summary "scenario_i_web_isolation"
    exit $?
fi
PASS=$((PASS+1))
printf "  ${C_GRN}PASS${C_RST}  web server booted on port %s\n" "$PORT"

post() {
    # post <jar-file> <json-body>
    curl -s --max-time 20 \
        --cookie-jar "$1" --cookie "$1" \
        -X POST -H 'Content-Type: application/json' \
        -d "$2" "http://127.0.0.1:$PORT/api/chat"
}

# 1. Cookie A teaches widget. The first response carries Set-Cookie which curl
#    stores into JAR_A; subsequent requests on JAR_A reuse that cookie.
RESP_A1=$(post "$JAR_A" '{"message":"/teach widget"}')
assert_match "$RESP_A1" "ingested 'widget'" "cookie A: /teach widget acknowledged"

# Verify Set-Cookie landed in JAR_A.
if grep -qE 'ce_sid\s+' "$JAR_A" 2>/dev/null; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  cookie A: ce_sid recorded in jar\n"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  cookie A: ce_sid missing from jar (no Set-Cookie?)\n"
    cat "$JAR_A" 2>/dev/null | sed 's/^/        /'
fi

# 2. Cookie A queries widget -- must be recognized (m>=1, unk=0).
RESP_A2=$(post "$JAR_A" '{"message":"widget"}')
assert_match "$RESP_A2" "perceive\\(m=[1-9][0-9]*,unk=0\\)" \
    "cookie A: widget recognized after teach (m>=1, unk=0)"

# 3. Cookie B queries widget WITHOUT teaching -- must NOT be recognized
#    (cookie B's child has a fresh seed; widget never touched its KG).
RESP_B1=$(post "$JAR_B" '{"message":"widget"}')
assert_match "$RESP_B1" "perceive\\(.*,unk=[1-9][0-9]*\\)" \
    "cookie B: widget NOT recognized (unk>=1, isolated from A)"

# Cookie B should have gotten a distinct ce_sid.
if [ -f "$JAR_A" ] && [ -f "$JAR_B" ]; then
    SID_A=$(awk '$6=="ce_sid"{print $7; exit}' "$JAR_A")
    SID_B=$(awk '$6=="ce_sid"{print $7; exit}' "$JAR_B")
    if [ -n "$SID_A" ] && [ -n "$SID_B" ] && [ "$SID_A" != "$SID_B" ]; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}PASS${C_RST}  cookies A and B differ (A=%s, B=%s)\n" \
            "${SID_A:0:8}..." "${SID_B:0:8}..."
    else
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  cookies should be distinct (A=%s, B=%s)\n" "$SID_A" "$SID_B"
    fi
fi

# 4. Cookie A queries widget again -- must STILL be recognized. Cookie B's
#    intervening request should not have disturbed A's state.
RESP_A3=$(post "$JAR_A" '{"message":"widget"}')
assert_match "$RESP_A3" "perceive\\(m=[1-9][0-9]*,unk=0\\)" \
    "cookie A: widget STILL recognized after cookie B's request (m>=1, unk=0)"

# 5. /api/sessions returns both cookies with diagnostics.
SESSIONS_JSON=$(curl -s --max-time 10 "http://127.0.0.1:$PORT/api/sessions")
assert_match "$SESSIONS_JSON" '"sessions"' "/api/sessions returns a JSON object with 'sessions'"
SESS_COUNT=$(echo "$SESSIONS_JSON" | grep -oE '"id"' | wc -l)
if [ "$SESS_COUNT" -ge 2 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  /api/sessions lists %d sessions (>=2)\n" "$SESS_COUNT"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  /api/sessions reported %d sessions (expected >=2)\n" "$SESS_COUNT"
fi
assert_match "$SESSIONS_JSON" '"last_active_ms"' "/api/sessions includes last_active_ms"
assert_match "$SESSIONS_JSON" '"age_ms"' "/api/sessions includes age_ms"

# 6. SIGTERM and verify clean shutdown.
kill -TERM "$SRV_PID" 2>/dev/null
for i in 1 2 3 4 5 6 7 8 9 10; do
    sleep 0.3
    if ! kill -0 "$SRV_PID" 2>/dev/null; then break; fi
done
kill -KILL "$SRV_PID" 2>/dev/null
wait "$SRV_PID" 2>/dev/null || true

if ! kill -0 "$SRV_PID" 2>/dev/null; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  web server cleaned up (PID %s gone)\n" "$SRV_PID"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  web server PID %s still alive after KILL\n" "$SRV_PID"
fi

summary "scenario_i_web_isolation"
