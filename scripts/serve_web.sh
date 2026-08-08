#!/usr/bin/env bash
#
# scripts/serve_web.sh -- Launcher for the CrossEngin web UI shim
# (R51, ADR-0109).
#
# Boots the Python HTTP shim that serves the SPA under `web/` and
# forwards `POST /rpc/<verb>` requests to the TCP RPC daemon.
#
# Usage:
#   scripts/serve_web.sh                       # 127.0.0.1:8080
#   CE_WEB_PORT=18080 scripts/serve_web.sh     # custom port
#
# Env passed through to the shim:
#   CE_WEB_PORT       (default 8080)
#   CE_WEB_BIND       (default 127.0.0.1)
#   CE_WEB_BIND_ALLOW_NON_LOOPBACK   (set 1 to bind LAN; see security notes)
#   CE_RPC_HOST       (default 127.0.0.1)
#   CE_RPC_PORT       (default 9876)
#   CE_WEB_ROOT       (default: <repo>/web)
#   CE_WEB_TIMEOUT_S  (default 30)
#
# This is intentionally a shell wrapper -- the shim is a plain Python 3
# stdlib script, no venv or pip install needed. If your `python3` lives
# elsewhere, set PYTHON=/path/to/python3.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

SHIM="${SHIM:-./scripts/rpc_web_shim.py}"
PYTHON="${PYTHON:-python3}"

if [ ! -f "$SHIM" ]; then
    echo "ERROR: $SHIM not found." >&2
    exit 1
fi

if ! command -v "$PYTHON" >/dev/null 2>&1; then
    cat >&2 <<EOF
ERROR: '$PYTHON' not on PATH. Install Python 3 (stdlib only; no pip).
On Ubuntu:  sudo apt install python3
On macOS:   brew install python@3   (or use system python3)
On Windows: install from https://python.org (Python 3.9+)
Or set PYTHON=/path/to/python3 before running this script.
EOF
    exit 1
fi

exec "$PYTHON" "$SHIM" "$@"
