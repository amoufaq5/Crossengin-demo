#!/usr/bin/env bash
# Shared integration-test helpers.
#
# Source this from every tests/integration/*.sh script. It exports:
#   PASS / FAIL counters
#   assert_eq      <got> <expected> <name>
#   assert_match   <text> <pattern> <name>      # ERE
#   assert_nomatch <text> <pattern> <name>      # ERE
#   run_chat       <stdin-text>                 # echoes stdout, exit code is chat's
#   it_section "<heading>"                      # prints a labelled banner
#   summary "<script-name>"                     # echoes pass/fail line; exits non-zero on fail
#   REPO_ROOT / CHAT / DAEMON / SNAP / WEB_PY   # path constants
#
# Convention: scripts use `set -uo pipefail` (NOT `set -e` -- we want to record
# failures, not abort) and call `summary` as their last action.

set -uo pipefail

PASS=${PASS:-0}
FAIL=${FAIL:-0}

# Project paths. Absolute so scripts can be run from any cwd.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHAT="$REPO_ROOT/bin/crossengin-chat"
DAEMON="$REPO_ROOT/bin/crossengin"
WEB_PY="$REPO_ROOT/scripts/web.py"
LEARN_SH="$REPO_ROOT/scripts/learn.sh"
SNAP="${CE_SNAP_PATH:-/tmp/crossengin.snap}"

# ANSI colour helpers (only when stdout is a tty).
if [ -t 1 ]; then
    C_GRN=$'\033[32m'; C_RED=$'\033[31m'; C_YEL=$'\033[33m'; C_DIM=$'\033[2m'; C_RST=$'\033[0m'
else
    C_GRN=""; C_RED=""; C_YEL=""; C_DIM=""; C_RST=""
fi

assert_eq() {
    # assert_eq <got> <expected> <name>
    if [ "$1" = "$2" ]; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}PASS${C_RST}  %s\n" "$3"
    else
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  %s\n        expected: '%s'\n        got     : '%s'\n" "$3" "$2" "$1"
    fi
}

assert_match() {
    # assert_match <text> <pattern> <name>
    if echo "$1" | grep -qE "$2"; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}PASS${C_RST}  %s\n" "$3"
    else
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  %s\n        pattern '%s' not found in:\n" "$3" "$2"
        echo "$1" | sed 's/^/          /'
    fi
}

assert_nomatch() {
    # assert_nomatch <text> <pattern> <name>
    if ! echo "$1" | grep -qE "$2"; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}PASS${C_RST}  %s\n" "$3"
    else
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  %s\n        unexpected pattern '%s' found in:\n" "$3" "$2"
        echo "$1" | sed 's/^/          /'
    fi
}

assert_file_exists() {
    # assert_file_exists <path> <name>
    if [ -f "$1" ]; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}PASS${C_RST}  %s\n" "$2"
    else
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  %s (file not found: %s)\n" "$2" "$1"
    fi
}

# Pipe the given text into the chat once, capture stdout+stderr, and echo it
# back. Always feeds /quit as the final line so the process terminates.
run_chat() {
    local input="$1"
    # Append /quit if not already present. (Caller often passes it explicitly
    # to test exit semantics; the implicit fallback prevents a hang.)
    if ! echo "$input" | grep -qE '^/quit|^/exit|^quit|^exit'; then
        input="${input}
/quit"
    fi
    printf '%s\n' "$input" | "$CHAT" 2>&1
}

it_section() {
    printf "%s== %s ==%s\n" "$C_DIM" "$1" "$C_RST"
}

# Echoes a one-line summary and exits non-zero iff any assertion failed. Every
# tests/integration/*.sh script ends with `summary <name>`.
summary() {
    local name="$1"
    if [ "$FAIL" -eq 0 ]; then
        printf "integration %s: ${C_GRN}pass=%d fail=%d${C_RST}\n" "$name" "$PASS" "$FAIL"
    else
        printf "integration %s: ${C_RED}pass=%d fail=%d${C_RST}\n" "$name" "$PASS" "$FAIL"
    fi
    [ "$FAIL" -eq 0 ]
}

# Pre-flight: the chat binary must exist. Every script depends on it.
require_chat() {
    if [ ! -x "$CHAT" ]; then
        printf "${C_RED}ERROR${C_RST}: %s not found. Run: make install\n" "$CHAT" >&2
        exit 2
    fi
}
