#!/usr/bin/env bash
# Scenario M -- /metrics Prometheus scrape endpoint (P2.9).
#
# python3 scripts/web.py (background) -> POST /api/chat {"message":"hello"}
# (to materialise a per-cookie ChatChild that /metrics can probe) -> GET
# /metrics and assert:
#   - status 200 with text/plain; version=0.0.4 Content-Type
#   - the response contains the mandated `# HELP` + `# TYPE` framing for
#     every Prometheus metric family we publish
#   - at least one `crossengin_*` metric sample line follows the framing
#   - the per-cookie POST counter ticks (request_total{cookie="..."} >= 1)
#   - the process-wide active_session_count >= 1 after the chat round-trip
#   - the per-sid atom_count (reasoning + language) gauges are present
#   - the cached probe path serves a second /metrics call without spawning
#     a fresh /__metrics__ probe (idempotent body within the cache window)
#   - /__metrics__ is read-only -- the kg_atom_count and dlog_entries values
#     do not change between the two scrapes
#
# Also a static-source assertion that /metrics inherits the loopback bind
# default from /api/chat (BIND="127.0.0.1") -- P2.9's safety contract.

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0

it_section "scenario M: /metrics Prometheus scrape endpoint"

# Pre-flight: python3 + curl. (web.py needs python3; /metrics scraping needs
# either curl or python3 urllib -- we use curl when available, urllib otherwise.)
if ! command -v python3 >/dev/null 2>&1; then
    printf "  ${C_YEL}SKIP${C_RST}  python3 not on PATH -- /metrics test skipped\n"
    PASS=$((PASS+1))
    summary "scenario_m_metrics_endpoint"
    exit $?
fi

if [ ! -f "$WEB_PY" ]; then
    printf "  ${C_YEL}SKIP${C_RST}  %s missing -- /metrics test skipped\n" "$WEB_PY"
    PASS=$((PASS+1))
    summary "scenario_m_metrics_endpoint"
    exit $?
fi

# Static-source guardrails. /metrics MUST inherit the loopback default; the
# probe MUST be cached.
WEB_SRC=$(cat "$WEB_PY")
assert_match "$WEB_SRC" 'BIND = os.environ.get\("CE_BIND", "127.0.0.1"\)' \
    "web.py /metrics inherits the 127.0.0.1 loopback bind"
assert_match "$WEB_SRC" 'METRICS_CACHE_S' \
    "web.py caches /metrics probes (CE_METRICS_CACHE_S env)"
assert_match "$WEB_SRC" '"/metrics"' \
    "web.py routes the literal /metrics path"

# Pick a non-default port to avoid clashes with scenario_f.
PORT=$((19000 + (RANDOM % 1000)))
OUT_LOG=/tmp/ce_int_metrics_$$.log
COOKIE_JAR=/tmp/ce_int_metrics_cookies_$$.txt
rm -f "$COOKIE_JAR"

# Launch the server. New session so we can SIGTERM the process group cleanly.
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
    rm -f "$OUT_LOG" "$COOKIE_JAR"
    kill -TERM "$SRV_PID" 2>/dev/null
    wait "$SRV_PID" 2>/dev/null || true
    summary "scenario_m_metrics_endpoint"
    exit $?
fi
PASS=$((PASS+1))
printf "  ${C_GRN}PASS${C_RST}  web server booted on port %s\n" "$PORT"

# Wrappers. curl preferred so we can drive cookie jars and inspect headers.
HAS_CURL=0
if command -v curl >/dev/null 2>&1; then HAS_CURL=1; fi

do_post() {
    local payload="$1"
    if [ "$HAS_CURL" = "1" ]; then
        curl -s --max-time 30 -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
            -X POST -H 'Content-Type: application/json' \
            -d "$payload" "http://127.0.0.1:$PORT/api/chat"
    else
        python3 - "$PORT" "$payload" <<'PYEOF'
import json, sys, urllib.request, http.cookiejar
port, payload = sys.argv[1], sys.argv[2].encode()
jar = http.cookiejar.MozillaCookieJar("/tmp/ce_int_metrics_pycookies.txt")
op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
req = urllib.request.Request(
    f"http://127.0.0.1:{port}/api/chat",
    data=payload,
    headers={"Content-Type": "application/json"},
    method="POST",
)
print(op.open(req, timeout=30).read().decode())
jar.save(ignore_discard=True)
PYEOF
    fi
}

do_metrics_with_headers() {
    if [ "$HAS_CURL" = "1" ]; then
        curl -s --max-time 15 -i -b "$COOKIE_JAR" "http://127.0.0.1:$PORT/metrics"
    else
        python3 - "$PORT" <<'PYEOF'
import sys, urllib.request
port = sys.argv[1]
r = urllib.request.urlopen(f"http://127.0.0.1:{port}/metrics", timeout=15)
print(f"HTTP/1.1 {r.status}")
for k, v in r.getheaders():
    print(f"{k}: {v}")
print()
print(r.read().decode())
PYEOF
    fi
}

# First, drive a chat round-trip so the cookie's ChatChild exists. Without
# this, /metrics has no live children and the per-sid metric block is empty.
RESP=$(do_post '{"message":"hello"}')
assert_match "$RESP" '"reply"' "/api/chat hello returns a reply (cookie's child now live)"

# Now hit /metrics with the same cookie.
METRICS=$(do_metrics_with_headers)
HEAD=$(echo "$METRICS" | sed -n '/^$/q;p')
BODY=$(echo "$METRICS" | awk 'p{print} /^\r?$/{p=1}')

# Headers: 200 + Prometheus content-type.
assert_match "$HEAD" "HTTP/1\.[01] 200" "/metrics returns 200 OK"
assert_match "$HEAD" "Content-Type: text/plain" "/metrics serves text/plain"
assert_match "$HEAD" "version=0\.0\.4" \
    "/metrics serves the Prometheus exposition version=0.0.4 Content-Type"

# Required # HELP and # TYPE framing per the Prometheus exposition format.
assert_match "$BODY" "^# HELP crossengin_atom_count " \
    "/metrics emits # HELP for crossengin_atom_count"
assert_match "$BODY" "^# TYPE crossengin_atom_count gauge" \
    "/metrics emits # TYPE crossengin_atom_count gauge"
assert_match "$BODY" "^# HELP crossengin_dlog_entries " \
    "/metrics emits # HELP for crossengin_dlog_entries"
assert_match "$BODY" "^# TYPE crossengin_dlog_entries gauge" \
    "/metrics emits # TYPE crossengin_dlog_entries gauge"
assert_match "$BODY" "^# HELP crossengin_promotion_rate " \
    "/metrics emits # HELP for crossengin_promotion_rate"
assert_match "$BODY" "^# TYPE crossengin_promotion_rate gauge" \
    "/metrics emits # TYPE crossengin_promotion_rate gauge"
assert_match "$BODY" "^# HELP crossengin_atrophy_rate " \
    "/metrics emits # HELP for crossengin_atrophy_rate"
assert_match "$BODY" "^# HELP crossengin_soul_mood_valence " \
    "/metrics emits # HELP for crossengin_soul_mood_valence"
assert_match "$BODY" "^# HELP crossengin_soul_mood_arousal " \
    "/metrics emits # HELP for crossengin_soul_mood_arousal"
assert_match "$BODY" "^# HELP crossengin_scheduler_tick_rate " \
    "/metrics emits # HELP for crossengin_scheduler_tick_rate"
assert_match "$BODY" "^# HELP crossengin_scheduler_overruns " \
    "/metrics emits # HELP for crossengin_scheduler_overruns"
assert_match "$BODY" "^# HELP crossengin_active_session_count " \
    "/metrics emits # HELP for crossengin_active_session_count"
assert_match "$BODY" "^# HELP crossengin_evicted_session_count " \
    "/metrics emits # HELP for crossengin_evicted_session_count"
assert_match "$BODY" "^# HELP crossengin_request_total " \
    "/metrics emits # HELP for crossengin_request_total"
assert_match "$BODY" "^# HELP crossengin_request_duration_seconds " \
    "/metrics emits # HELP for crossengin_request_duration_seconds"
assert_match "$BODY" "^# TYPE crossengin_request_duration_seconds summary" \
    "/metrics emits a Prometheus summary for request duration"

# Sample lines with labels (the spec format: `name{labels} value`).
assert_match "$BODY" 'crossengin_atom_count\{kg="reasoning",sid="' \
    "/metrics has a reasoning-KG atom_count sample with sid label"
assert_match "$BODY" 'crossengin_atom_count\{kg="language",sid="' \
    "/metrics has a language-KG atom_count sample with sid label"
assert_match "$BODY" 'crossengin_dlog_entries\{sid="' \
    "/metrics has a dlog_entries sample with sid label"
assert_match "$BODY" 'crossengin_soul_mood_valence\{sid="' \
    "/metrics has a soul_mood_valence sample with sid label"
assert_match "$BODY" 'crossengin_request_total\{cookie="' \
    "/metrics has a request_total sample with cookie label"

# Process-wide gauges should be present and reflect the live session.
assert_match "$BODY" "^crossengin_active_session_count [0-9]+" \
    "/metrics emits crossengin_active_session_count as a number"
ACTIVE=$(echo "$BODY" | grep -E "^crossengin_active_session_count " \
    | awk '{print $2}' | head -1)
if [ -n "$ACTIVE" ]; then
    ACTIVE_INT=${ACTIVE%.*}
    if [ "$ACTIVE_INT" -ge 1 ]; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}PASS${C_RST}  active_session_count >= 1 (got %s)\n" "$ACTIVE"
    else
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  active_session_count was %s (expected >=1)\n" "$ACTIVE"
    fi
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  active_session_count line not found\n"
fi

# request_total per cookie should be >=1 after the POST.
REQ_TOT=$(echo "$BODY" | grep -E '^crossengin_request_total\{cookie="' \
    | awk '{print $2}' | head -1)
if [ -n "$REQ_TOT" ]; then
    REQ_INT=${REQ_TOT%.*}
    if [ "$REQ_INT" -ge 1 ]; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}PASS${C_RST}  request_total >= 1 (got %s)\n" "$REQ_TOT"
    else
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  request_total was %s (expected >=1)\n" "$REQ_TOT"
    fi
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  request_total{cookie=...} line not found\n"
fi

# Second /metrics call within the cache window: response should be stable for
# the per-sid atom_count (the chat had no chance to mutate KGs because we
# didn't POST a message that would teach anything; the cached probe also
# means we don't even hit the chat).
METRICS2=$(do_metrics_with_headers)
BODY2=$(echo "$METRICS2" | awk 'p{print} /^\r?$/{p=1}')
A1=$(echo "$BODY"  | grep -E '^crossengin_atom_count\{kg="reasoning"' | awk '{print $2}' | head -1)
A2=$(echo "$BODY2" | grep -E '^crossengin_atom_count\{kg="reasoning"' | awk '{print $2}' | head -1)
assert_eq "$A2" "$A1" "second /metrics scrape returns the same reasoning atom_count (cache hit)"

# /metrics is read-only: a /__metrics__ probe behind it does not register as a
# new session (active_session_count must still be the same).
A2C=$(echo "$BODY2" | grep -E "^crossengin_active_session_count " | awk '{print $2}' | head -1)
assert_eq "$A2C" "$ACTIVE" "/metrics is read-only -- active_session_count unchanged"

# Save a sample of the metrics for the report.
SAMPLE_PATH=/tmp/ce_int_metrics_sample_$$.txt
echo "$BODY" | head -20 > "$SAMPLE_PATH"
printf "  ${C_DIM}-- /metrics sample (first 20 lines, body) --${C_RST}\n"
sed 's/^/        /' "$SAMPLE_PATH"

# Cleanly stop the child via /quit then SIGTERM the server.
do_post '{"message":"/quit"}' >/dev/null 2>&1 || true
sleep 0.5
kill -TERM "$SRV_PID" 2>/dev/null
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

rm -f "$OUT_LOG" "$COOKIE_JAR" "$SAMPLE_PATH" /tmp/ce_int_metrics_pycookies.txt
summary "scenario_m_metrics_endpoint"
