#!/usr/bin/env bash
# Entry point for the CrossEngin backend image.
#
# Responsibilities (in order):
#   1. Verify the CrossEngin binary exists where server.py will look for it.
#   2. Refuse to start if CROSSENGIN_TOKEN is unset / default.
#   3. Exec server.py (PID 1 so signals propagate cleanly).
#
# All real configuration lives in env vars, not in baked image bytes -- a
# rebuild is not required to rotate the bearer token or change ports.

set -euo pipefail

# Default working directory inside the image: /opt/crossengin/repo.
# (The Dockerfile clones into that path.)
cd "${CE_REPO_ROOT:-/opt/crossengin/repo}"

# CE_BIN is resolved relative to the repo root unless absolute.
CE_BIN="${CE_BIN:-bin/crossengin-chat}"
if [[ "$CE_BIN" != /* ]]; then
    CE_BIN="$(pwd)/$CE_BIN"
fi
export CE_BIN

if [[ ! -x "$CE_BIN" ]]; then
    echo "FATAL: CrossEngin binary not found / not executable at $CE_BIN" >&2
    echo "  Did bootstrap.sh + make install succeed in the image build?" >&2
    exit 1
fi

if [[ -z "${CROSSENGIN_TOKEN:-}" ]]; then
    echo "FATAL: CROSSENGIN_TOKEN env var is required." >&2
    echo "  Generate one with: openssl rand -hex 32" >&2
    exit 2
fi

if [[ "${CROSSENGIN_TOKEN}" == "local-dev-token" && "${CE_ALLOW_DEV_TOKEN:-}" != "1" ]]; then
    echo "REFUSING TO START: CROSSENGIN_TOKEN is set to the docker-compose dev" >&2
    echo "default ('local-dev-token'). Override it for any non-localhost use." >&2
    echo "  (Set CE_ALLOW_DEV_TOKEN=1 to bypass when running on localhost only.)" >&2
    exit 3
fi

echo "[entrypoint] starting crossengin-backend"
echo "[entrypoint]   CE_BIN          = $CE_BIN"
echo "[entrypoint]   CE_PORT         = ${CE_PORT:-8080}"
echo "[entrypoint]   CE_BIND         = ${CE_BIND:-0.0.0.0}"
echo "[entrypoint]   CE_MAX_SESSIONS = ${CE_MAX_SESSIONS:-8}"

# exec so server.py inherits PID 1 and SIGTERM/SIGINT propagate.
exec python3 /opt/crossengin/server.py
