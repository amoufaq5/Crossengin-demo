#!/usr/bin/env bash
#
# scripts/rpc_daemon.sh -- Launcher for the CrossEngin JSON-RPC daemon
# (R49 + R50, ADR-0104 §Component 5 + ADR-0109).
#
# Boots ./bin/crossengin-rpc-daemon with sensible defaults, prints the
# wire endpoint, and refuses to bind non-loopback without an explicit
# override so an operator does not accidentally expose a wire that
# executes named skills to a shared LAN.
#
# Usage:
#   scripts/rpc_daemon.sh                       # loopback, port 9876
#   CE_RPC_PORT=19876 scripts/rpc_daemon.sh     # custom port
#   CE_RPC_BIND=192.168.1.10 CE_RPC_BIND_ALLOW_NON_LOOPBACK=1 \
#       scripts/rpc_daemon.sh                   # LAN (only with the
#                                               # explicit allow flag)
#
# See docs/SHIP_AS_APP.md for the full operator manual.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

BIN="${BIN:-./bin/crossengin-rpc-daemon}"
PORT="${CE_RPC_PORT:-9876}"
BIND="${CE_RPC_BIND:-127.0.0.1}"

if [ ! -x "$BIN" ]; then
    cat >&2 <<EOF
ERROR: $BIN not found or not executable.
Run 'make install' first (see docs/SHIP_AS_APP.md).
EOF
    exit 1
fi

# Loopback safety gate. A non-loopback bind exposes a wire that dispatches
# named skills; that MUST be a deliberate choice, not a silent accident.
case "$BIND" in
    127.*|localhost|::1)
        ;;
    *)
        if [ "${CE_RPC_BIND_ALLOW_NON_LOOPBACK:-0}" != "1" ]; then
            cat >&2 <<EOF
ERROR: CE_RPC_BIND=$BIND is not a loopback address.
The RPC wire executes named skills. Binding non-loopback exposes that
to every host on the network. If you know what you're doing, re-run
with CE_RPC_BIND_ALLOW_NON_LOOPBACK=1 . Consider layering TLS or an
SSH tunnel before doing this.
EOF
            exit 2
        fi
        echo "warning: binding non-loopback ($BIND). The wire executes skills." >&2
        ;;
esac

# Port sanity.
case "$PORT" in
    ''|*[!0-9]*)
        echo "ERROR: CE_RPC_PORT=$PORT is not a positive integer." >&2
        exit 2
        ;;
esac
if [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
    echo "ERROR: CE_RPC_PORT=$PORT is out of range." >&2
    exit 2
fi

echo "=== CrossEngin JSON-RPC daemon ==="
echo "binary: $BIN"
echo "endpoint: $BIND:$PORT"
echo "hit with:  scripts/rpc.sh <verb> '<args-json>'"
echo "example:   scripts/rpc.sh nl.ask '{\"text\":\"what is mars\",\"user_id\":\"owner\"}'"
echo

exec env CE_RPC_PORT="$PORT" CE_RPC_BIND="$BIND" "$BIN"
