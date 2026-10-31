#!/usr/bin/env bash
#
# scripts/rpc.sh -- One-shot client for the CrossEngin JSON-RPC daemon
# (R49 + R50, ADR-0104 §Component 5 + ADR-0109).
#
# Sends one JSON-RPC request line to a running daemon, prints the
# response line to stdout, exits.
#
# Usage:
#   scripts/rpc.sh <verb> [<args-json>]
#
# Examples:
#   scripts/rpc.sh kg.list
#   scripts/rpc.sh nl.parse_only '{"text":"what is mars"}'
#   scripts/rpc.sh nl.ask '{"text":"is earth a planet","user_id":"owner"}'
#   scripts/rpc.sh skill.list
#   scripts/rpc.sh skill.install '{"name":"research"}'
#   scripts/rpc.sh skill.run '{"name":"research","arg":"mars"}'
#
# Env:
#   CE_RPC_HOST     daemon host (default 127.0.0.1)
#   CE_RPC_PORT     daemon port (default 9876)
#   CE_RPC_JQ       set to any value to pretty-print with jq if installed
#   CE_RPC_TOKEN    if set, sent as the request's "token" field (needed
#                   when the daemon is in sandbox-enforced mode, R54;
#                   see docs/adr/0105-sandbox-architecture.md)

set -uo pipefail

if [ $# -lt 1 ]; then
    cat >&2 <<EOF
Usage: $0 <verb> [<args-json>]
  verb       one of: nl.ask, nl.parse_only, kg.list, capsule.list,
             capsule.install, skill.list, skill.run, persona.show,
             persona.project, ingest.review, ingest.approve, ingest.deny
  args-json  optional JSON object for the verb's args (default: {})
EOF
    exit 2
fi

VERB="$1"
ARGS="${2:-{}}"
HOST="${CE_RPC_HOST:-127.0.0.1}"
PORT="${CE_RPC_PORT:-9876}"

# Validate that ARGS looks like a JSON object. Cheap check: starts with
# '{' and ends with '}'. jq would be authoritative but we don't want a
# hard jq dependency for the client script.
first="${ARGS:0:1}"
last="${ARGS: -1}"
if [ "$first" != "{" ] || [ "$last" != "}" ]; then
    echo "ERROR: args must be a JSON object like '{\"key\":\"value\"}', got: $ARGS" >&2
    exit 2
fi

# Compose request. NOTE: this uses `printf` -- no eval, no shell expansion
# of the args payload once composed, so a quoted "-o" or "; rm ..." inside
# the payload doesn't reach the shell.
if [ -n "${CE_RPC_TOKEN:-}" ]; then
    # Escape any backslash / double-quote in the token id before splicing.
    ESC_TOKEN=$(printf '%s' "$CE_RPC_TOKEN" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
    REQ=$(printf '{"verb":"%s","token":"%s","args":%s}\n' "$VERB" "$ESC_TOKEN" "$ARGS")
else
    REQ=$(printf '{"verb":"%s","args":%s}\n' "$VERB" "$ARGS")
fi

# Send + read one line. Prefer `nc` if present; fall back to bash /dev/tcp.
send_via_nc() {
    # `nc -q 1` waits 1s after EOF on stdin before closing -- gives the
    # daemon time to write its response line back on some ncs.
    if nc -h 2>&1 | grep -q '\-q '; then
        printf '%s' "$REQ" | nc -q 1 "$HOST" "$PORT"
    elif nc -h 2>&1 | grep -q '\-N '; then
        # BSD-flavored nc uses -N to half-close after EOF on stdin.
        printf '%s' "$REQ" | nc -N "$HOST" "$PORT"
    else
        printf '%s' "$REQ" | nc "$HOST" "$PORT"
    fi
}

send_via_bash_tcp() {
    exec 3<>"/dev/tcp/$HOST/$PORT" || return 1
    printf '%s' "$REQ" >&3
    IFS= read -r line <&3
    exec 3<&- 3>&- 2>/dev/null || true
    printf '%s\n' "$line"
}

if command -v nc >/dev/null 2>&1; then
    RESP=$(send_via_nc)
else
    RESP=$(send_via_bash_tcp)
fi

if [ -z "$RESP" ]; then
    echo "ERROR: no response from $HOST:$PORT" >&2
    exit 1
fi

# Pretty-print via jq if the operator asked for it and jq is present.
if [ -n "${CE_RPC_JQ:-}" ] && command -v jq >/dev/null 2>&1; then
    printf '%s\n' "$RESP" | jq .
else
    printf '%s\n' "$RESP"
fi
