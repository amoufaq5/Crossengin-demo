#!/usr/bin/env bash
# crossengin-doctor -- environment + dependency check.
#
# Runs a green/yellow/red checklist over everything CrossEngin needs at
# runtime: kernel version, NOVA toolchain reachability, compiled binaries,
# /tmp writability + space, snapshot + dlog paths, optional helper tools
# (curl, ffmpeg, ImageMagick, audio tools, transcribers, wasm runtimes,
# node, python3), and a 3-second TCP probe to en.wikipedia.org (the
# `/learn TOPIC` default source).
#
# Exit codes:
#   0  all CRITICAL checks pass (optional ones may be yellow)
#   1  one or more CRITICAL checks failed
#
# Output: per-check colored marker, then a "X/Y checks pass" summary line.
# Tests (tests/integration/scenario_x_doctor.sh) parse that summary, so its
# wording is stable.
#
# Run from anywhere:  bash scripts/crossengin-doctor.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ---- colour helpers ------------------------------------------------------
if [ -t 1 ] && [ "${CE_DOCTOR_NO_COLOR:-0}" != "1" ]; then
    C_GRN=$'\033[32m'; C_RED=$'\033[31m'; C_YEL=$'\033[33m'
    C_DIM=$'\033[2m'; C_BLD=$'\033[1m'; C_RST=$'\033[0m'
else
    C_GRN=""; C_RED=""; C_YEL=""; C_DIM=""; C_BLD=""; C_RST=""
fi

PASS=0
FAIL=0
WARN=0
TOTAL=0

# A check that GATES exit-status (CRITICAL). Pass:  green tick.  Fail: red X.
critical() {
    # critical <name> <ok-cond:0|1> [detail]
    TOTAL=$((TOTAL+1))
    if [ "$2" -eq 1 ]; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}OK  ${C_RST}  %-48s %s\n" "$1" "${3:-}"
    else
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  %-48s %s\n" "$1" "${3:-}"
    fi
}

# A check that does NOT gate exit-status (OPTIONAL). Missing = yellow WARN.
optional() {
    # optional <name> <ok-cond:0|1> [detail]
    TOTAL=$((TOTAL+1))
    if [ "$2" -eq 1 ]; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}OK  ${C_RST}  %-48s %s\n" "$1" "${3:-}"
    else
        WARN=$((WARN+1))
        printf "  ${C_YEL}WARN${C_RST}  %-48s %s\n" "$1" "${3:-not installed}"
    fi
}

section() {
    printf "${C_DIM}== %s ==${C_RST}\n" "$1"
}

# ---- begin checks --------------------------------------------------------

printf "${C_BLD}=== crossengin-doctor: environment + dependency check ===${C_RST}\n"
printf "repo  : %s\n" "$REPO_ROOT"
printf "user  : %s\n" "$(id -un 2>/dev/null || echo unknown)"
printf "host  : %s\n" "$(uname -n 2>/dev/null || echo unknown)"
printf "date  : %s\n" "$(date -Iseconds 2>/dev/null || date)"
printf "\n"

# ---- kernel + platform ---------------------------------------------------
section "kernel + platform"
KERN_FULL="$(uname -r 2>/dev/null || echo unknown)"
KERN_MAJOR="${KERN_FULL%%.*}"
case "$KERN_MAJOR" in
    ''|*[!0-9]*) KERN_MAJOR=0 ;;
esac
if [ "$KERN_MAJOR" -ge 5 ]; then
    critical "linux kernel >= 5.0" 1 "($KERN_FULL)"
else
    critical "linux kernel >= 5.0" 0 "($KERN_FULL -- may lack newer syscalls)"
fi

ARCH="$(uname -m 2>/dev/null || echo unknown)"
case "$ARCH" in
    x86_64|amd64) critical "arch x86_64" 1 "($ARCH)" ;;
    *)            optional "arch x86_64" 0 "($ARCH -- CrossEngin built for x86_64)" ;;
esac

# ---- NOVA toolchain ------------------------------------------------------
section "nova toolchain"
NOVA_ROOT="${NOVA_ROOT:-$HOME/NOVA}"
if [ -d "$NOVA_ROOT" ]; then
    critical "NOVA_ROOT directory" 1 "($NOVA_ROOT)"
else
    critical "NOVA_ROOT directory" 0 "(missing $NOVA_ROOT -- set NOVA_ROOT=/path/to/NOVA)"
fi
if [ -x "$NOVA_ROOT/nova" ]; then
    critical "nova launcher executable" 1 "($NOVA_ROOT/nova)"
elif [ -x "$NOVA_ROOT/bin/nova" ]; then
    critical "nova launcher executable" 1 "($NOVA_ROOT/bin/nova)"
else
    critical "nova launcher executable" 0 "(not found under $NOVA_ROOT; run 'cd \$NOVA_ROOT && make')"
fi

# ---- CrossEngin binaries -------------------------------------------------
section "crossengin binaries (./bin)"
for bin in crossengin crossengin-chat crossengin-selfcheck crossengin-spine \
           crossengin-kg-publisher crossengin-kg-subscriber \
           crossengin-fed-coordinator; do
    if [ -x "$REPO_ROOT/bin/$bin" ]; then
        sz="$(wc -c < "$REPO_ROOT/bin/$bin" 2>/dev/null | tr -d ' ')"
        critical "bin/$bin" 1 "($sz bytes)"
    else
        critical "bin/$bin" 0 "(missing; run 'make install')"
    fi
done

# ---- filesystem: /tmp ----------------------------------------------------
section "filesystem"
TMP_PROBE="/tmp/.ce_doctor_probe.$$"
if : >"$TMP_PROBE" 2>/dev/null; then
    rm -f "$TMP_PROBE"
    critical "/tmp writable" 1 ""
else
    critical "/tmp writable" 0 "(cannot create files under /tmp)"
fi

# Free space at /tmp in MB. df -P keeps a 1-block-per-line POSIX format.
TMP_FREE_KB="$(df -P /tmp 2>/dev/null | awk 'NR==2 {print $4}')"
case "$TMP_FREE_KB" in
    ''|*[!0-9]*) TMP_FREE_KB=0 ;;
esac
TMP_FREE_MB=$((TMP_FREE_KB / 1024))
if [ "$TMP_FREE_MB" -ge 100 ]; then
    critical "/tmp free space >= 100MB" 1 "(${TMP_FREE_MB}MB)"
else
    critical "/tmp free space >= 100MB" 0 "(${TMP_FREE_MB}MB -- snapshots / dlog need headroom)"
fi

# Snapshot dir: derive from $CE_SNAP_DIR, else $CE_SNAP_PATH's dirname, else /tmp.
SNAP_DIR="${CE_SNAP_DIR:-}"
if [ -z "$SNAP_DIR" ]; then
    if [ -n "${CE_SNAP_PATH:-}" ]; then SNAP_DIR="$(dirname "${CE_SNAP_PATH}")"
    else SNAP_DIR="/tmp"; fi
fi
if [ -d "$SNAP_DIR" ] && [ -w "$SNAP_DIR" ]; then
    SNAP_FREE_KB="$(df -P "$SNAP_DIR" 2>/dev/null | awk 'NR==2 {print $4}')"
    case "$SNAP_FREE_KB" in ''|*[!0-9]*) SNAP_FREE_KB=0 ;; esac
    SNAP_FREE_MB=$((SNAP_FREE_KB / 1024))
    critical "snapshot dir writable" 1 "($SNAP_DIR, ${SNAP_FREE_MB}MB free)"
else
    critical "snapshot dir writable" 0 "($SNAP_DIR -- not writable; set CE_SNAP_DIR)"
fi

# Decision-log path: derive from $CE_DLOG_PATH (file) or $CE_DLOG_DIR.
DLOG_PATH="${CE_DLOG_PATH:-}"
if [ -n "$DLOG_PATH" ]; then
    DLOG_DIR="$(dirname "$DLOG_PATH")"
else
    DLOG_DIR="${CE_DLOG_DIR:-/tmp}"
fi
if [ -d "$DLOG_DIR" ] && [ -w "$DLOG_DIR" ]; then
    critical "dlog dir writable" 1 "($DLOG_DIR)"
else
    critical "dlog dir writable" 0 "($DLOG_DIR -- not writable; set CE_DLOG_DIR)"
fi

# ---- optional helper tools ----------------------------------------------
section "optional helper tools"
for tool_pair in \
    "curl:HTTP fetch for /learn TOPIC" \
    "ffmpeg:video transcode for /play" \
    "convert:ImageMagick for /see PNG" \
    "espeak:fallback TTS for /speak" \
    "aplay:WAV playback for /speak" \
    "parecord:PulseAudio capture for STT" \
    "whisper-cli:Whisper STT backend" \
    "vosk-transcriber:Vosk STT backend" \
    "python3:scripts/web.py + smoke clients" \
    "wat2wasm:WebAssembly text -> binary" \
    "wasmtime:WebAssembly runtime" \
    "node:Node.js runtime" ; do
    tool="${tool_pair%%:*}"
    desc="${tool_pair#*:}"
    if command -v "$tool" >/dev/null 2>&1; then
        path="$(command -v "$tool")"
        optional "$tool" 1 "($path -- $desc)"
    else
        optional "$tool" 0 "(missing -- $desc)"
    fi
done

# ---- network probe ------------------------------------------------------
section "network"
NET_HOST="${CE_DOCTOR_NET_HOST:-en.wikipedia.org}"
NET_PORT="${CE_DOCTOR_NET_PORT:-443}"
NET_OK=0
# Prefer bash's /dev/tcp pseudo-fd (no extra deps); fall back to nc / curl.
if (exec 3<>"/dev/tcp/${NET_HOST}/${NET_PORT}") 2>/dev/null & probe_pid=$!; then
    # Wait up to 3 seconds for the connect.
    for _ in 1 2 3; do
        if ! kill -0 "$probe_pid" 2>/dev/null; then break; fi
        sleep 1
    done
    if kill -0 "$probe_pid" 2>/dev/null; then
        kill "$probe_pid" 2>/dev/null
        wait "$probe_pid" 2>/dev/null || true
        NET_OK=0
    else
        wait "$probe_pid" 2>/dev/null
        if [ $? -eq 0 ]; then NET_OK=1; fi
    fi
fi
if [ "$NET_OK" -eq 0 ] && command -v curl >/dev/null 2>&1; then
    if curl --silent --max-time 3 --output /dev/null --head \
            "https://${NET_HOST}/" 2>/dev/null; then
        NET_OK=1
    fi
fi
optional "tcp connect ${NET_HOST}:${NET_PORT}" "$NET_OK" \
    "(3s probe -- required by /learn TOPIC)"

# ---- summary ------------------------------------------------------------
printf "\n"
SUMM_COLOR="$C_GRN"
if [ "$FAIL" -gt 0 ]; then
    SUMM_COLOR="$C_RED"
elif [ "$WARN" -gt 0 ]; then
    SUMM_COLOR="$C_YEL"
fi
# Load-bearing summary line. scenario_x_doctor.sh greps this exact wording:
#   "<PASS>/<TOTAL> checks pass"
printf "${SUMM_COLOR}%d/%d checks pass${C_RST}  (warn=%d fail=%d)\n" \
    "$PASS" "$TOTAL" "$WARN" "$FAIL"

if [ "$FAIL" -gt 0 ]; then
    printf "${C_RED}crossengin-doctor: %d critical check(s) failed.${C_RST}\n" "$FAIL"
    exit 1
fi
if [ "$WARN" -gt 0 ]; then
    printf "${C_YEL}crossengin-doctor: critical checks pass; %d optional dep(s) missing.${C_RST}\n" "$WARN"
fi
exit 0
