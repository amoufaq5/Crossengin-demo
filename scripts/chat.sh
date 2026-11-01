#!/usr/bin/env bash
# CrossEngin chat REPL shim.
#
# bin/crossengin-chat is a self-contained interactive REPL that reads
# lines from its own stdin and keeps state across turns within one boot.
# For an interactive session, just run the binary directly:
#
#     ./bin/crossengin-chat
#
# This shim exists for the one-message-per-boot batched-send style used
# by scenario tests: you type a line, the shim boots a fresh daemon with
# that line piped to its stdin, prints whatever the daemon printed after
# the first prompt, and loops. State does NOT persist between turns in
# this mode (each turn is a fresh boot) — if you want persistence, use
# the direct invocation above.
#
# Usage:    scripts/chat.sh              # uses ./bin/crossengin-chat
#           scripts/chat.sh /path/to/bin # override
# Quit:     Ctrl-D, an empty line, or type "quit" / "exit".

set -uo pipefail

BIN="${1:-./bin/crossengin-chat}"

if [ ! -x "$BIN" ]; then
    echo "ERROR: $BIN not found or not executable." >&2
    echo "Run 'make install' first." >&2
    exit 1
fi

cat <<'INTRO'
CrossEngin chat (batched shim mode). Each turn is a fresh boot; state
does not persist between turns -- for a persistent REPL, run
./bin/crossengin-chat directly instead. Type 'quit' or Ctrl-D to exit.

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

    # Pipe the message plus /quit to the daemon's stdin so it processes
    # one turn and exits cleanly. Everything the daemon prints AFTER the
    # first "> " prompt and BEFORE the final "bye." is the reply.
    OUT=$(printf '%s\n/quit\n' "$MSG" | "$BIN" 2>&1) || true
    REPLY=$(printf '%s\n' "$OUT" | awk '
        !seen && /^> / {
            seen = 1
            # If anything follows the "> " on the same line, keep it.
            rest = substr($0, 3)
            if (length(rest) > 0) print rest
            next
        }
        seen && /^bye\.$/ { exit }
        seen { print }
    ')

    if [ -n "$REPLY" ]; then
        printf '%s\n' "$REPLY"
    else
        echo "[no response -- daemon trace:]"
        printf '%s\n' "$OUT" | tail -8 | sed 's/^/  /'
    fi
done

echo "bye."
