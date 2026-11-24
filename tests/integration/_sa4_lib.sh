#!/usr/bin/env bash
# Shared helpers for SecAgg v4 network scenarios (A2.4a). Source it after
# _lib.sh. The caller sets T (a private 0700 scratch dir) and PORT before
# starting souls, and calls sa4_cleanup from its EXIT trap.
#
#   sa4_skip <why>                SKIP, or FAIL under CE_IT_STRICT=1
#   sa4_keys <n>                  identities 1..n: $T/k<i>.priv/.pub, id i*10,
#                                 name soul<i>; roster lines in $T/line<i>
#   sa4_roster <file> <i...>      roster of those souls (mode 0644)
#   wait_all <secs> <pid...>      wait with a hang guard: on the deadline the
#                                 processes and their children are killed
#                                 and a FAIL is counted (never a bare wait)
#   stage_wait <secs>             wait_all over every pid in SP, then clear SP
#   chat_soul <dir> <name> <roster> <i> [ENV=VAL...]   -> CHAT_PID
#       a NOVA chat soul: /teach, /fed_join 127.0.0.1:$PORT, /quit; output in
#       <dir>/<name>.out; run dir ${SA4_RUNBASE:-<dir>}/run_<name>
#   py_soul <dir> <name> <roster> <i> <x> [args...]    -> PY_PID
#       a Python soul (scripts/sa4_ref.py --connect); state file
#       ${SA4_RUNBASE:-<dir>}/state_<name>
#   chat_x <chat.out> <id>        "<id>=tag=promo:atr,..." from the chat's
#                                 "input (stays local)" lines (present tags)
#   jget <json file> <a.b.c>      one value (strings bare, the rest as JSON)
# Tags: SA4_TAGS (default seed,user-teach).

SA4_CHAT_BIN="$REPO_ROOT/bin/crossengin-chat"
SA4_REF="$REPO_ROOT/scripts/sa4_ref.py"
SA4_KG="$REPO_ROOT/scripts/secagg_keygen.sh"
SA4_TAGS="${SA4_TAGS:-seed,user-teach}"
STRICT="${CE_IT_STRICT:-0}"
PIDS=()
SP=()

sa4_skip() {
    if [ "$STRICT" = "1" ]; then
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  (strict) SKIP not allowed: %s\n" "$1"
    else
        printf "  ${C_YEL}SKIP${C_RST}  %s\n" "$1"
    fi
}

sa4_cleanup() {
    local p
    for p in "${PIDS[@]}"; do pkill -9 -P "$p" 2>/dev/null; kill -9 "$p" 2>/dev/null; done
}

sa4_keys() {
    local i
    for i in $(seq 1 "$1"); do
        bash "$SA4_KG" "$T/k$i" $((i * 10)) "soul$i" | sed -n 's/^roster line: //p' > "$T/line$i"
    done
}

sa4_roster() {
    local f="$1" i; shift
    { echo "crossengin-secagg-roster v1"; for i in "$@"; do cat "$T/line$i"; done; } > "$f"
    chmod 644 "$f"
}

wait_all() {
    local deadline="$1"; shift
    local elapsed=0 alive p
    while [ "$elapsed" -lt "$deadline" ]; do
        alive=0
        for p in "$@"; do kill -0 "$p" 2>/dev/null && alive=1; done
        [ "$alive" -eq 0 ] && break
        sleep 1; elapsed=$((elapsed + 1))
    done
    # Recheck after the loop: a process that exited during the last sleep
    # is not a hang.
    alive=0
    for p in "$@"; do kill -0 "$p" 2>/dev/null && alive=1; done
    if [ "$alive" -ne 0 ]; then
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  process(es) hung past %ss, force-killed\n" "$deadline"
        # Chats run inside a subshell: kill its children (the binary) too.
        for p in "$@"; do pkill -9 -P "$p" 2>/dev/null; kill -9 "$p" 2>/dev/null; done
    fi
    for p in "$@"; do wait "$p" 2>/dev/null; done
}

stage_wait() { [ "${#SP[@]}" -gt 0 ] && wait_all "$1" "${SP[@]}"; SP=(); }

chat_soul() {
    local d="$1" name="$2" ro="$3" k="$4"; shift 4
    (
        export CE_RUN_DIR="${SA4_RUNBASE:-$d}/run_$name"
        mkdir -p "$CE_RUN_DIR"; chmod 700 "$CE_RUN_DIR"
        export CE_SECAGG_ENABLED=1 CE_SECAGG_MODE=v4 CE_SECAGG_ROSTER="$ro" CE_SECAGG_ID_KEY="$T/k$k.priv"
        export CE_SECAGG_V4_TAGS="$SA4_TAGS" CE_SESSION_ID="$name"
        export CE_SNAP_PATH="$d/$name.snap" CE_DLOG_PATH="$d/$name.dlog"
        local kv
        for kv in "$@"; do export "$kv"; done
        printf '/teach widget\n/teach gadget%s\n/cap grant network_send\n/fed_join 127.0.0.1:%s\n/fed_leave\n/quit\n' "$k" "$PORT" \
            | "$SA4_CHAT_BIN" > "$d/$name.out" 2>&1
    ) &
    CHAT_PID=$!; PIDS+=("$CHAT_PID"); SP+=("$CHAT_PID")
}

py_soul() {
    local d="$1" name="$2" ro="$3" k="$4" x="$5"; shift 5
    CE_SECAGG_ROSTER="$ro" CE_SECAGG_ID_KEY="$T/k$k.priv" \
        python3 -I "$SA4_REF" --connect "127.0.0.1:$PORT" --tags "$SA4_TAGS" --x "$x" \
        --state "${SA4_RUNBASE:-$d}/state_$name" --timeout 30 "$@" > "$d/$name.out" 2>&1 &
    PY_PID=$!; PIDS+=("$PY_PID"); SP+=("$PY_PID")
}

chat_x() {
    local x
    x=$(sed -n 's/.*input (stays local) tag=\([^ ]*\) promo=\([0-9]*\) atr=\([0-9]*\) present=1.*/\1=\2:\3/p' "$1" | paste -sd, -)
    echo "$2=$x"
}

jget() {
    python3 -I -c '
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    for k in sys.argv[2].split("."):
        d = d[int(k)] if isinstance(d, list) else d[k]
except (OSError, ValueError, KeyError, IndexError, TypeError):
    print("(missing)"); sys.exit(0)
print(d if isinstance(d, str) else json.dumps(d, sort_keys=True))' "$1" "$2"
}
