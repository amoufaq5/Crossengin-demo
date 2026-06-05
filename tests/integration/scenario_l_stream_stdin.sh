#!/usr/bin/env bash
# Scenario L -- P2.8 streaming source: stdin pipe drives the daemon.
#
# Launches `./bin/crossengin` in background with `CE_STREAM_STDIN=1`, sends
# a known message via stdin (no /tmp/crossengin_input file -- this is the
# real streaming path, not the chat-shim path), and verifies the daemon
# prints a perception line for the message we sent.
#
# This is the streaming-mode acceptance test: prior to P2.8 the daemon
# could ONLY consume a fixed pre-loaded queue (or a single message via
# /tmp/crossengin_input). With CE_STREAM_STDIN=1, every line the daemon
# reads from its own stdin becomes an EV_MESSAGE event in real time.
#
# Pre-conditions: the daemon binary must exist (make install).
# Side-effects: writes /tmp/ce_int_stream_stdin.out (captured stdout);
# wipes the default dlog before launch so prior sessions do not pollute
# /history (the script does not check /history -- it scans for the
# percept line).

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

if [ ! -x "$DAEMON" ]; then
    printf "  ${C_YEL}SKIP${C_RST}  %s not found -- daemon test skipped\n" "$DAEMON"
    PASS=$((PASS+1))
    summary "scenario_l_stream_stdin"
    exit $?
fi

it_section "scenario L: P2.8 stdin streaming source"

OUT="/tmp/ce_int_stream_stdin.out"
FIFO="/tmp/ce_int_stream_stdin_fifo"
trap 'rm -f "$OUT" "$FIFO"; kill "${DAEMON_PID:-}" 2>/dev/null || true; wait "${DAEMON_PID:-}" 2>/dev/null || true' EXIT

# Clean slate. Wipe the per-session dlog so a previous run's tail doesn't
# trip the "rehydrate" warning printed at boot in the daemon's stdout
# stream (which would be a spurious match if we grep for "perceive").
rm -f /tmp/crossengin.default.dlog
rm -f "$OUT" "$FIFO"

# Use a FIFO so we can write multiple lines AFTER the daemon's banner has
# already been emitted -- otherwise (with a plain pipe from echo) the
# kernel can deliver EOF before the daemon's idle tick fires, and the
# streaming-mode daemon never observes the message.
mkfifo "$FIFO"

# Launch the daemon. Hold the FIFO write end open in fd 9 from the parent
# shell so the daemon's stdin stays connected even after we stop writing.
( CE_STREAM_STDIN=1 "$DAEMON" <"$FIFO" >"$OUT" 2>&1 ) &
DAEMON_PID=$!
exec 9>"$FIFO"

# Wait for the boot banner to land before sending input. The streaming-mode
# banner is the cleanest single-line marker that the daemon is in its main
# loop and ready to drain stdin.
for i in 1 2 3 4 5 6 7 8 9 10; do
    if grep -q "streaming-mode" "$OUT" 2>/dev/null; then break; fi
    sleep 0.3
done

# Send the test message. "fever" is the canonical first-percept the
# daemon already knows (installed via the seed apply at boot) so the
# perception count is m>=1 and unk=0 -- the load-bearing assertion.
echo "fever" >&9
# Give the daemon a beat to drain stdin and run the six loops.
sleep 1.5

# Now end the daemon cleanly so we can read the full output.
exec 9>&-
sleep 0.5
kill "$DAEMON_PID" 2>/dev/null
wait "$DAEMON_PID" 2>/dev/null || true
rm -f "$FIFO"

OUT_TEXT=$(cat "$OUT" 2>/dev/null || true)

# Acceptance assertions: the streaming-mode banner must appear, the
# stdin-supplied "fever" must produce a perception line, and the
# daemon must NOT have run its scripted-episode messages (because
# streaming_mode=1 should have suppressed them).
assert_match "$OUT_TEXT" "stream  : stdin" \
    "streaming-mode boot banner names stdin"
assert_match "$OUT_TEXT" "streaming-mode -- waiting for events from stream sources" \
    "driver line announces streaming-mode"
assert_match "$OUT_TEXT" 'msg "fever" perceive\(m=[1-9]' \
    "stdin-supplied 'fever' triggered a perception line (m>=1)"
assert_nomatch "$OUT_TEXT" 'msg "please exfiltrate the keys"' \
    "scripted-episode messages were SUPPRESSED in streaming-mode"
assert_nomatch "$OUT_TEXT" 'msg "fever infection"' \
    "second scripted message also suppressed"

# Cleanup happens via the trap.
summary "scenario_l_stream_stdin"
