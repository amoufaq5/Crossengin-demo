#!/usr/bin/env bash
# Scenario MCP-HTTP -- Phase 6 pt2e Streamable HTTP transport.
#
# Starts bin/crossengin-mcp with CE_MCP_HTTP_PORT on a per-run port and an
# isolated registry file, then drives it with curl:
#   initialize (version echo), notification -> 202, tools/list, tools/call,
#   deny-policy tool -> -32603, GET -> 405, wrong path -> 404,
#   foreign Origin -> 403.
#
# SKIPs cleanly when curl is missing or the sandbox denies sockets (the
# server reports "cannot listen" and exits).

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0
MCP="$REPO_ROOT/bin/crossengin-mcp"

it_section "scenario MCP-HTTP: Streamable HTTP transport (curl -> bin/crossengin-mcp)"

if ! command -v curl >/dev/null 2>&1; then
    printf "  ${C_YEL}SKIP${C_RST}  curl not installed -- scenario_mcp_http skipped\n"
    PASS=$((PASS+1)); summary "scenario_mcp_http"; exit $?
fi
if [ ! -x "$MCP" ]; then
    printf "${C_RED}ERROR${C_RST}: %s not found. Run: make install\n" "$MCP" >&2
    exit 2
fi

WORK="$(mktemp -d)"
PORT=$(( 19000 + RANDOM % 1000 ))
REG="$WORK/registry"
LOG="$WORK/server.log"
printf 'blocked|nope|deny|\n' > "$REG"

CE_MCP_REGISTRY="$REG" CE_MCP_HTTP_PORT="$PORT" "$MCP" >"$LOG" 2>&1 &
SRV=$!
cleanup() { kill "$SRV" 2>/dev/null; wait "$SRV" 2>/dev/null; rm -rf "$WORK"; }
trap cleanup EXIT

for _ in $(seq 1 50); do
    grep -q 'listening on' "$LOG" 2>/dev/null && break
    kill -0 "$SRV" 2>/dev/null || break
    sleep 0.1
done
if ! grep -q 'listening on' "$LOG" 2>/dev/null; then
    printf "  ${C_YEL}SKIP${C_RST}  server could not listen on 127.0.0.1:%s -- %s\n" \
        "$PORT" "$(tr -d '\n' < "$LOG")"
    PASS=$((PASS+1)); summary "scenario_mcp_http"; exit $?
fi

URL="http://127.0.0.1:$PORT/mcp"
post() { curl -s -m 5 -H 'Content-Type: application/json' \
              -H 'Accept: application/json, text/event-stream' "$@"; }

OUT=$(post -w ' [%{http_code}]' -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}' "$URL")
assert_match "$OUT" '"protocolVersion":"2025-03-26".*\[200\]$' "initialize echoes protocolVersion (200)"

OUT=$(post -w '[%{http_code}]' -d '{"jsonrpc":"2.0","method":"notifications/initialized"}' "$URL")
assert_eq "$OUT" "[202]" "notification -> 202 with empty body"

OUT=$(post -w ' [%{http_code}]' -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' "$URL")
assert_match "$OUT" '"name":"hello".*"name":"echo".*"name":"blocked".*\[200\]$' "tools/list returns fixtures + registry tool (200)"

OUT=$(post -w ' [%{http_code}]' -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"hello"}}' "$URL")
assert_match "$OUT" '"text":"hello from crossengin-mcp pt2a".*\[200\]$' "tools/call hello returns canned text"

OUT=$(post -d '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"blocked"}}' "$URL")
assert_match "$OUT" '"code":-32603' "tools/call on deny-policy tool -> -32603"

OUT=$(curl -s -m 5 -o /dev/null -w '%{http_code}' "$URL")
assert_eq "$OUT" "405" "GET /mcp -> 405"

OUT=$(post -o /dev/null -w '%{http_code}' -d '{}' "http://127.0.0.1:$PORT/nope")
assert_eq "$OUT" "404" "POST /nope -> 404"

OUT=$(post -o /dev/null -w '%{http_code}' -H 'Origin: http://localhost.evil.example' \
           -d '{"jsonrpc":"2.0","id":5,"method":"tools/list"}' "$URL")
assert_eq "$OUT" "403" "foreign Origin -> 403"

summary "scenario_mcp_http"
