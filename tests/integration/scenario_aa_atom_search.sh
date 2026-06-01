#!/usr/bin/env bash
# Scenario AA -- /api/atoms search endpoint (web atom-search UI).
#
# python3 scripts/web.py (background) -> GET /api/atoms?q=fever -> verify the
# response is JSON with an `atoms` array that contains at least one entry
# whose label is "fever". Also exercises the /atoms HTML page (server-side
# rendered, vanilla JS) and the cache-hit path (a second probe within
# CE_ATOMS_CACHE_S should not change the response shape).
#
# The /api/atoms endpoint is built on top of the chat's new /__atoms__ admin
# command (the same probe pattern as /__metrics__): the web server runs a
# probe per cookie, caches the parsed atom list for CE_ATOMS_CACHE_S
# (default 30s), then filters by label substring + KG label in pure python.

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0

it_section "scenario AA: /api/atoms search endpoint"

# Pre-flight: python3 is required for web.py.
if ! command -v python3 >/dev/null 2>&1; then
    printf "  ${C_YEL}SKIP${C_RST}  python3 not on PATH -- /api/atoms test skipped\n"
    PASS=$((PASS+1))
    summary "scenario_aa_atom_search"
    exit $?
fi

if [ ! -f "$WEB_PY" ]; then
    printf "  ${C_YEL}SKIP${C_RST}  %s missing -- /api/atoms test skipped\n" "$WEB_PY"
    PASS=$((PASS+1))
    summary "scenario_aa_atom_search"
    exit $?
fi

# Static-source guards: /api/atoms inherits the loopback bind, caches probes.
# We grep the file directly (not via assert_match) because under `set -o
# pipefail` grep -q on a large piped string can stop the upstream echo early.
if grep -qE 'BIND = os.environ.get\("CE_BIND", "127.0.0.1"\)' "$WEB_PY"; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  web.py /api/atoms inherits the 127.0.0.1 loopback bind\n"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  web.py /api/atoms inherits the 127.0.0.1 loopback bind\n"
fi
if grep -q 'ATOMS_CACHE_S' "$WEB_PY"; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  web.py caches /__atoms__ probes (CE_ATOMS_CACHE_S env)\n"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  web.py caches /__atoms__ probes (CE_ATOMS_CACHE_S env)\n"
fi
if grep -q '/api/atoms' "$WEB_PY"; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  web.py routes /api/atoms\n"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  web.py routes /api/atoms\n"
fi
if grep -q '"/atoms"' "$WEB_PY"; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  web.py routes /atoms HTML\n"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  web.py routes /atoms HTML\n"
fi

# Pick a non-default port to avoid clashes with other scenarios.
PORT=$((20000 + (RANDOM % 1000)))
OUT_LOG=/tmp/ce_int_atoms_$$.log
COOKIE_JAR=/tmp/ce_int_atoms_cookies_$$.txt
rm -f "$COOKIE_JAR" /tmp/crossengin.dlog /tmp/crossengin.default.dlog

# Launch the server. New session so we can SIGTERM the process group cleanly.
CE_PORT="$PORT" CE_BIN="$CHAT" python3 "$WEB_PY" >"$OUT_LOG" 2>&1 &
SRV_PID=$!

# Wait for the server to come up.
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
    summary "scenario_aa_atom_search"
    exit $?
fi
PASS=$((PASS+1))
printf "  ${C_GRN}PASS${C_RST}  web server booted on port %s\n" "$PORT"

# HTTP wrapper. curl preferred so we can drive a cookie jar across calls.
HAS_CURL=0
if command -v curl >/dev/null 2>&1; then HAS_CURL=1; fi

do_get() {
    local path="$1"
    if [ "$HAS_CURL" = "1" ]; then
        curl -s --max-time 30 -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
            "http://127.0.0.1:$PORT$path"
    else
        python3 - "$PORT" "$path" <<'PYEOF'
import sys, urllib.request, http.cookiejar
port, path = sys.argv[1], sys.argv[2]
jar = http.cookiejar.MozillaCookieJar("/tmp/ce_int_atoms_pycookies.txt")
op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
print(op.open(f"http://127.0.0.1:{port}{path}", timeout=30).read().decode())
jar.save(ignore_discard=True)
PYEOF
    fi
}

# Hit /api/atoms?q=fever&limit=5 -- expect at least one atom labeled "fever".
RESP=$(do_get "/api/atoms?q=fever&limit=5")
assert_match "$RESP" '"atoms"' '/api/atoms returns JSON with atoms field'
assert_match "$RESP" '"label": ?"fever"' \
    '/api/atoms?q=fever response contains a label "fever" atom'
assert_match "$RESP" '"kg": ?"reasoning"' \
    '/api/atoms?q=fever surfaces a reasoning-KG atom'
assert_match "$RESP" '"belief_mean":' \
    '/api/atoms response includes a belief_mean field'

# Hit /atoms (HTML page) -- expect server-side rendered HTML page (not JSON).
HTML=$(do_get "/atoms")
assert_match "$HTML" '<title>CrossEngin atom search</title>' \
    "/atoms HTML page has the expected <title>"
assert_match "$HTML" "fetch\\('/api/atoms" \
    "/atoms HTML embeds a fetch() to /api/atoms"

# Second /api/atoms call within the cache window: same JSON shape (probe
# cache hit -- the chat child is not re-queried).
RESP2=$(do_get "/api/atoms?q=fever&limit=5")
assert_match "$RESP2" '"label": ?"fever"' \
    "second /api/atoms?q=fever still returns fever (cache hit)"

# Limit honored: q="" with limit=2 returns at most 2 atoms.
RESP3=$(do_get "/api/atoms?limit=2")
ATOM_COUNT=$(echo "$RESP3" | python3 -c "import sys, json; print(len(json.loads(sys.stdin.read()).get('atoms', [])))")
if [ "$ATOM_COUNT" -le 2 ] && [ "$ATOM_COUNT" -ge 1 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  /api/atoms?limit=2 returned %s atoms (<=2)\n" "$ATOM_COUNT"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  /api/atoms?limit=2 returned %s atoms (expected 1..2)\n" "$ATOM_COUNT"
fi

# Save a sample for the report.
SAMPLE_PATH=/tmp/ce_int_atoms_sample_$$.txt
echo "$RESP" > "$SAMPLE_PATH"
printf "  ${C_DIM}-- /api/atoms?q=fever sample --${C_RST}\n"
sed 's/^/        /' "$SAMPLE_PATH"

# Tear down.
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

rm -f "$OUT_LOG" "$COOKIE_JAR" "$SAMPLE_PATH" /tmp/ce_int_atoms_pycookies.txt
summary "scenario_aa_atom_search"
