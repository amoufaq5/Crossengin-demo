#!/usr/bin/env bash
#
# scripts/preload.sh -- Populate a running CrossEngin RPC daemon with
# the reference skills so it is useful the moment it comes up (R50,
# ADR-0109).
#
# The daemon (crossengin-rpc-daemon) boots with an empty capsule
# registry and un-installed reference skills. This script drives the
# `skill.install` verb for the two reference skills (echo, research)
# so the operator can hit `nl.ask` immediately.
#
# Capsule preloading requires the packs to already be REGISTERED in
# the daemon's process (via the ingestion pipeline). The standalone
# daemon does not include the ingestion agent (R49 design decision --
# ingest is chat-REPL-only for now), so capsule preloading via wire is
# a no-op here; a future release wires the pipeline into the daemon
# (see docs/adr/0109-ship-as-app.md "Deferred to R51+").
#
# Usage:
#   scripts/preload.sh              # loopback default port
#   CE_RPC_PORT=19876 scripts/preload.sh
#
# Env:
#   CE_RPC_HOST     daemon host (default 127.0.0.1)
#   CE_RPC_PORT     daemon port (default 9876)
#   CE_RPC_PRELOAD_QUIET=1   suppress per-verb progress lines

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

RPC="./scripts/rpc.sh"
if [ ! -x "$RPC" ]; then
    echo "ERROR: $RPC not found. Run from repo root." >&2
    exit 1
fi

QUIET="${CE_RPC_PRELOAD_QUIET:-0}"

_step() {
    local label="$1"; shift
    if [ "$QUIET" != "1" ]; then
        printf '  %-40s ' "$label"
    fi
    local resp
    resp=$("$@" 2>&1)
    local rc=$?
    if [ $rc -ne 0 ]; then
        [ "$QUIET" != "1" ] && echo "FAIL"
        echo "  $resp" >&2
        return 1
    fi
    # Look for "ok":true in the response.
    if printf '%s' "$resp" | grep -q '"ok":true'; then
        [ "$QUIET" != "1" ] && echo "OK"
    else
        [ "$QUIET" != "1" ] && echo "SKIP"
        [ "$QUIET" != "1" ] && printf '    %s\n' "$resp"
    fi
    return 0
}

echo "=== CrossEngin preload (daemon at ${CE_RPC_HOST:-127.0.0.1}:${CE_RPC_PORT:-9876}) ==="

# ---- reference skills (echo + research) ----------------------------------
# These are pre-REGISTERED at daemon boot in crossengin_rpc_daemon.nova
# (`_rpcd_build_ctx`). We install them so `skill.run {"name":"research",...}`
# picks up a supervisor.
_step "install skill: echo"     "$RPC" skill.install '{"name":"echo"}'
_step "install skill: research" "$RPC" skill.install '{"name":"research"}'

# ---- sanity ping (surface what the daemon has) ---------------------------
if [ "$QUIET" != "1" ]; then
    echo
    echo "  daemon inventory:"
    printf '    KGs      : ' && "$RPC" kg.list      | tr -d '\n' && echo
    printf '    skills   : ' && "$RPC" skill.list   | tr -d '\n' && echo
    printf '    capsules : ' && "$RPC" capsule.list | tr -d '\n' && echo
fi

echo "preload done."
