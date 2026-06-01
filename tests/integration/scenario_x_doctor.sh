#!/usr/bin/env bash
# Scenario X -- crossengin-doctor parses cleanly + reports a sane checklist.
#
# Runs scripts/crossengin-doctor.sh, captures stdout+stderr, parses the
# load-bearing "X/Y checks pass" summary line, and asserts:
#   * the script ran (produced output)
#   * the summary line exists with sane integer counts (X<=Y, Y>=10)
#   * the doctor printed at least the kernel + binary + filesystem sections
#   * exit code is 0 (critical pass) or 1 (critical fail) -- not 2 (usage)
#
# Doctor exit:
#   0 if NOVA_ROOT is set + binaries built + /tmp ok (the common case here)
#   1 if any critical check fails (also acceptable for this scenario -- we
#     only verify the SHAPE of the output, not that everyone passes)
# We export NOVA_ROOT explicitly so the doctor's "nova launcher" check
# resolves the real toolchain at /home/user/NOVA rather than $HOME/NOVA.

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

DOCTOR="$REPO_ROOT/scripts/crossengin-doctor.sh"

it_section "scenario X: crossengin-doctor runs + reports a sane checklist"

# Pre-flight: the doctor script must exist.
if [ ! -f "$DOCTOR" ]; then
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  doctor script not found at %s\n" "$DOCTOR"
    summary "scenario_x_doctor"
    exit $?
fi

# Resolve NOVA_ROOT for the doctor invocation. The repo's Makefile + scripts
# default to $HOME/NOVA but the real path on the test host is /home/user/NOVA.
EFFECTIVE_NOVA_ROOT="${NOVA_ROOT:-/home/user/NOVA}"

# Run with colour disabled so the parse below isn't dancing around ANSI.
OUT="$(CE_DOCTOR_NO_COLOR=1 NOVA_ROOT="$EFFECTIVE_NOVA_ROOT" \
        bash "$DOCTOR" 2>&1)"
RC=$?

assert_match "$OUT" "crossengin-doctor: environment" "doctor printed header"
assert_match "$OUT" "kernel \+ platform"            "kernel section printed"
assert_match "$OUT" "crossengin binaries"           "binaries section printed"
assert_match "$OUT" "filesystem"                    "filesystem section printed"
assert_match "$OUT" "optional helper tools"         "optional-tools section printed"

# The load-bearing summary line: "X/Y checks pass". We require sane integers
# (X <= Y, Y >= 10 -- the doctor probes that many even in the most stripped
# environment) and a positive Y.
SUMMARY_LINE="$(printf '%s\n' "$OUT" | grep -E '^[0-9]+/[0-9]+ checks pass' | head -n 1)"
if [ -z "$SUMMARY_LINE" ]; then
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  no 'X/Y checks pass' summary line in output\n"
    printf '%s\n' "$OUT" | tail -10 | sed 's/^/        /'
else
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  summary line present: %s\n" "$SUMMARY_LINE"

    GOT_X="${SUMMARY_LINE%%/*}"
    REST="${SUMMARY_LINE#*/}"
    GOT_Y="${REST%% *}"
    case "$GOT_X" in ''|*[!0-9]*) GOT_X=-1 ;; esac
    case "$GOT_Y" in ''|*[!0-9]*) GOT_Y=-1 ;; esac

    if [ "$GOT_X" -ge 0 ] && [ "$GOT_Y" -ge 10 ] && [ "$GOT_X" -le "$GOT_Y" ]; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}PASS${C_RST}  sane counts (pass=%d total=%d)\n" "$GOT_X" "$GOT_Y"
    else
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  insane counts (pass=%s total=%s)\n" "$GOT_X" "$GOT_Y"
    fi
fi

# Exit code must be 0 (all critical pass) or 1 (some critical fail). 2 means
# usage error / config issue -- we never invoke that path.
if [ "$RC" -eq 0 ] || [ "$RC" -eq 1 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  exit code in {0,1} (rc=%d)\n" "$RC"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  unexpected exit code rc=%d (want 0 or 1)\n" "$RC"
fi

summary "scenario_x_doctor"
