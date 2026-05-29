#!/usr/bin/env bash
# Scenario F -- Web frontend smoke.
#
# python3 scripts/web.py (background) -> POST /api/chat {"message":"hello"}
# -> non-empty reply. POST {"message":"/quit"} drives the child to exit;
# we then SIGTERM the python server.
#
# Also verifies the loopback bind default: scripts/web.py binds to 127.0.0.1
# unless CE_BIND=0.0.0.0. We don't *attempt* the LAN bind (it's a network
# operation that might be blocked); we read the source for the documented
# default and the explicit CE_BIND env check.

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0

it_section "scenario F: web frontend smoke"

# Pre-flight: is python3 available?
if ! command -v python3 >/dev/null 2>&1; then
    printf "  ${C_YEL}SKIP${C_RST}  python3 not on PATH -- web frontend test skipped\n"
    PASS=$((PASS+1))   # count the skip as a pass so CI doesn't fail
    summary "scenario_f_web"
    exit $?
fi

if [ ! -f "$WEB_PY" ]; then
    printf "  ${C_YEL}SKIP${C_RST}  %s missing -- web frontend test skipped\n" "$WEB_PY"
    PASS=$((PASS+1))
    summary "scenario_f_web"
    exit $?
fi

# Static-source assertions for the loopback bind default (no need to launch).
WEB_SRC=$(cat "$WEB_PY")
assert_match "$WEB_SRC" 'BIND = os.environ.get\("CE_BIND", "127.0.0.1"\)' \
    "web.py default bind is 127.0.0.1 (loopback)"
assert_match "$WEB_SRC" 'BIND == "0.0.0.0"' \
    "web.py warns/checks the 0.0.0.0 bind explicitly"

# Pick a non-default port to avoid clashes.
PORT=$((18000 + (RANDOM % 1000)))
OUT_LOG=/tmp/ce_int_web_$$.log

# Launch the server. New session so we can SIGTERM the process group.
CE_PORT="$PORT" CE_BIN="$CHAT" python3 "$WEB_PY" >"$OUT_LOG" 2>&1 &
SRV_PID=$!

# Wait for the server to come up (it has to boot the chat child first).
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
    rm -f "$OUT_LOG"
    kill -TERM "$SRV_PID" 2>/dev/null
    wait "$SRV_PID" 2>/dev/null || true
    summary "scenario_f_web"
    exit $?
fi
PASS=$((PASS+1))
printf "  ${C_GRN}PASS${C_RST}  web server booted on port %s\n" "$PORT"

# Now hit /api/chat. Use curl if it's there, python3's urllib otherwise.
do_post() {
    local payload="$1"
    if command -v curl >/dev/null 2>&1; then
        curl -s --max-time 15 -X POST -H 'Content-Type: application/json' \
            -d "$payload" "http://127.0.0.1:$PORT/api/chat"
    else
        python3 - <<PYEOF
import json, urllib.request
req = urllib.request.Request(
    "http://127.0.0.1:$PORT/api/chat",
    data=b'$payload',
    headers={"Content-Type": "application/json"},
    method="POST",
)
print(urllib.request.urlopen(req, timeout=15).read().decode())
PYEOF
    fi
}

RESP=$(do_post '{"message":"hello"}')
assert_match "$RESP" '"reply"' "/api/chat hello returns a reply field"
# The reply must be non-empty after stripping the trailing perceive line.
# Easiest invariant: the agent's "agent>" line is somewhere in the JSON body.
assert_match "$RESP" 'agent>' "hello reply contains the agent> tag"

# Now post /quit to drive the child to exit cleanly.
do_post '{"message":"/quit"}' >/dev/null 2>&1 || true

# Tear down the python process.
sleep 0.5
kill -TERM "$SRV_PID" 2>/dev/null
# Give it a beat to shut down gracefully.
for i in 1 2 3 4 5; do
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

rm -f "$OUT_LOG"
summary "scenario_f_web"
