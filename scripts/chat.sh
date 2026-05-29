#!/usr/bin/env bash
# CrossEngin chat REPL.
#
# A bash-level loop that lets you talk to bin/crossengin one message at a time:
# you type, the script writes your line to /tmp/crossengin_input, runs the
# daemon, extracts the agent's response, and loops. Each turn is a FRESH agent
# boot (in-memory state does not persist between turns -- production durability
# is the documented NOVA enhancement #9/#10 seam). The seeded vocabulary is
# fever/infection/treat plus the foundational self/user/help/ok concepts; the
# constitution blocks anything containing "exfiltrate".
#
# Usage:    scripts/chat.sh              # uses ./bin/crossengin
#           scripts/chat.sh /path/to/bin # override
# Quit:     Ctrl-D, an empty line, or type "quit" / "exit".

set -uo pipefail

BIN="${1:-./bin/crossengin}"
INPUT="/tmp/crossengin_input"

if [ ! -x "$BIN" ]; then
    echo "ERROR: $BIN not found or not executable." >&2
    echo "Run 'make install' first (see MANUAL.md)." >&2
    exit 1
fi

cleanup() { rm -f "$INPUT"; }
trap cleanup EXIT INT TERM

cat <<'INTRO'
CrossEngin chat. Each turn is a fresh boot; the agent forgets between turns
(real persistence is a documented runtime-seam). Seeded vocabulary includes:
self, user, hello, help, ok, yes, fever, infection, treat. The constitution
blocks any message containing "exfiltrate". Type 'quit' or Ctrl-D to exit.

INTRO

while true; do
    printf '> '
    if ! IFS= read -r MSG; then
        echo
        break
    fi
    case "$MSG" in
        ""|quit|exit|q) break ;;
    esac

    printf '%s' "$MSG" > "$INPUT"

    # Capture daemon output; extract just the agent's reply line.
    OUT=$("$BIN" 2>&1) || true
    REPLY=$(printf '%s\n' "$OUT" | grep -m1 '^agent> ' || true)

    if [ -n "$REPLY" ]; then
        printf '%s\n' "$REPLY"
    else
        # No agent> line means the daemon never reached its action stage
        # (segfault, build mismatch, etc.). Show the tail for diagnosis.
        echo "agent> [no response -- daemon trace:]"
        printf '%s\n' "$OUT" | tail -5 | sed 's/^/  /'
    fi
done

echo "bye."
