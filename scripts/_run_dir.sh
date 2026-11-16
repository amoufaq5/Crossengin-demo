#!/usr/bin/env bash
# Shell twin of src/util/run_dir.nova: the per-user runtime directory for
# CrossEngin's default state and IPC files (audit F-24). Source this file,
# then use "$(ce_run_dir)" / "$(ce_run_path NAME)".
#
#   1. $CE_RUN_DIR (used as given; the test harness sets /tmp)
#   2. $XDG_RUNTIME_DIR/crossengin
#   3. $HOME/.crossengin/run
#   4. /tmp/crossengin-run
# 2-4 are created 0700 and must not be accessible by group/other; otherwise
# this exits 70 (fail closed).

ce_run_dir() {
    if [ -n "${CE_RUN_DIR:-}" ]; then
        mkdir -p "$CE_RUN_DIR" 2>/dev/null
        printf '%s\n' "$CE_RUN_DIR"
        return 0
    fi
    local d
    if [ -n "${XDG_RUNTIME_DIR:-}" ]; then
        d="$XDG_RUNTIME_DIR/crossengin"
    elif [ -n "${HOME:-}" ]; then
        (umask 077; mkdir -p "$HOME/.crossengin")
        d="$HOME/.crossengin/run"
    else
        d="/tmp/crossengin-run"
    fi
    (umask 077; mkdir -p "$d") 2>/dev/null
    if [ ! -d "$d" ] || [ -L "$d" ] || [ ! -O "$d" ] \
       || [ -n "$(find "$d" -maxdepth 0 -perm /077 2>/dev/null)" ]; then
        echo "FATAL: runtime directory $d is not a private (0700) directory owned by you; fix it or set CE_RUN_DIR" >&2
        exit 70
    fi
    printf '%s\n' "$d"
}

ce_run_path() {
    printf '%s/%s\n' "$(ce_run_dir)" "$1"
}
