#!/usr/bin/env bash
# Shell twin of src/util/run_dir.nova: the per-user runtime directory for
# CrossEngin's default state and IPC files (audit F-24). Source this file,
# then use:
#     d="$(ce_run_dir)" || exit 70
#     p="$(ce_run_path NAME)" || exit 70
#
#   1. $CE_RUN_DIR (used as given; the test harness sets /tmp)
#   2. $XDG_RUNTIME_DIR/crossengin   (if $XDG_RUNTIME_DIR is a dir we own)
#   3. $HOME/.crossengin/run         (if $HOME is a dir we own)
#   4. /tmp/crossengin-run-<euid>
# Directories we create get mode 0700, one level at a time (no mkdir -p,
# like run_dir.nova). 2-4 must be a real directory (not a symlink) owned by
# the effective uid with no group/other bits; otherwise this fails with
# status 70 (fail closed). Keep in sync with run_dir.nova.

_ce_owned_dir() {
    [ -d "$1" ] && [ -O "$1" ]
}

ce_run_dir() {
    if [ -n "${CE_RUN_DIR:-}" ]; then
        [ -d "$CE_RUN_DIR" ] || (umask 077; mkdir "$CE_RUN_DIR") 2>/dev/null
        printf '%s\n' "$CE_RUN_DIR"
        return 0
    fi
    local d
    if [ -n "${XDG_RUNTIME_DIR:-}" ] && _ce_owned_dir "$XDG_RUNTIME_DIR"; then
        d="$XDG_RUNTIME_DIR/crossengin"
    elif [ -n "${HOME:-}" ] && _ce_owned_dir "$HOME"; then
        (umask 077; mkdir "$HOME/.crossengin") 2>/dev/null
        d="$HOME/.crossengin/run"
    else
        d="/tmp/crossengin-run-$(id -u)"
    fi
    (umask 077; mkdir "$d") 2>/dev/null
    if [ ! -d "$d" ] || [ -L "$d" ] || [ ! -O "$d" ] \
       || [ -n "$(find "$d" -maxdepth 0 -perm /077 2>/dev/null)" ]; then
        echo "FATAL: runtime directory $d is not a private (0700) directory owned by you; fix it or set CE_RUN_DIR" >&2
        exit 70
    fi
    printf '%s\n' "$d"
}

ce_run_path() {
    local d
    d="$(ce_run_dir)" || return 70
    printf '%s/%s\n' "$d" "$1"
}
