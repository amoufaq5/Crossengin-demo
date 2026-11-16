#!/usr/bin/env bash
# Scenario file-hardening -- audit F-24.
#   1. A symlink planted at <snapshot>.tmp must not be followed by /save.
#   2. With no CE_RUN_DIR, default state lands in a private 0700 runtime
#      dir ($HOME/.crossengin/run here), not /tmp.
#   3. A runtime dir that is group/other accessible is refused (exit 70).
#   4. A symlinked runtime dir is refused (exit 70).
#   5. Explicit per-file paths (CE_DLOG_PATH, CE_SNAP_PATH) bypass the run dir;
#      a missing HOME falls back to /tmp/crossengin-run-<uid>.
#   6. The daemon reads its command input from the run dir; a planted
#      /tmp/crossengin_input is ignored.

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0
it_section "scenario file-hardening: snapshot temp symlink, private run dir"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# 1. planted symlink
printf 'VICTIM-CONTENT\n' > "$WORK/victim"
ln -s "$WORK/victim" "$WORK/s.snap.tmp"
OUT=$(printf '/save\n/quit\n' | CE_SNAP_PATH="$WORK/s.snap" timeout 60 "$CHAT" 2>&1)
assert_eq "$(cat "$WORK/victim")" "VICTIM-CONTENT" "symlink target untouched by /save"
assert_eq "$([ -f "$WORK/s.snap" ] && [ ! -L "$WORK/s.snap" ] && echo yes)" "yes" "snapshot written as a regular file"
assert_eq "$(stat -c '%a' "$WORK/s.snap" 2>/dev/null)" "600" "snapshot mode is 0600"

# 2. default run dir
mkdir -p "$WORK/home"
OUT=$(printf 'hello\n/quit\n' | env -u CE_RUN_DIR -u XDG_RUNTIME_DIR -u CE_DLOG_PATH \
      HOME="$WORK/home" timeout 60 "$CHAT" 2>&1)
assert_eq "$(stat -c '%a' "$WORK/home/.crossengin/run" 2>/dev/null)" "700" "run dir created 0700"
assert_eq "$([ -f "$WORK/home/.crossengin/run/crossengin.dlog" ] && echo yes)" "yes" "default dlog lives in the run dir"

# 3. insecure run dir refused
mkdir -p "$WORK/home2/.crossengin/run"
chmod 755 "$WORK/home2/.crossengin/run"
OUT=$(printf '/quit\n' | env -u CE_RUN_DIR -u XDG_RUNTIME_DIR -u CE_DLOG_PATH \
      HOME="$WORK/home2" timeout 60 "$CHAT" 2>&1); RC=$?
assert_match "$OUT" "is not a private \\(0700\\) directory" "0755 run dir refused with a message"
assert_eq "$RC" "70" "chat exits 70 on an insecure run dir"

# 4. a symlinked run dir is refused (even when the target is a 0700 dir)
mkdir -m 700 "$WORK/real" "$WORK/home3" "$WORK/home3/.crossengin"
ln -s "$WORK/real" "$WORK/home3/.crossengin/run"
OUT=$(printf '/quit\n' | env -u CE_RUN_DIR -u XDG_RUNTIME_DIR -u CE_DLOG_PATH \
      HOME="$WORK/home3" timeout 60 "$CHAT" 2>&1); RC=$?
assert_eq "$RC" "70" "symlinked run dir refused (exit 70)"

# 5. explicit per-file overrides win: the insecure run dir is never consulted
OUT=$(printf '/quit\n' | env -u CE_RUN_DIR -u XDG_RUNTIME_DIR \
      CE_DLOG_PATH="$WORK/o.dlog" CE_SNAP_PATH="$WORK/o.snap" \
      HOME="$WORK/home2" timeout 60 "$CHAT" 2>&1); RC=$?
assert_eq "$RC" "0" "explicit CE_DLOG_PATH/CE_SNAP_PATH boot despite an insecure run dir"

# 5b. a HOME that is missing (service accounts: HOME=/nonexistent) falls
#     back to the private /tmp/crossengin-run-<uid> instead of exiting 70
OUT=$(printf '/quit\n' | env -u CE_RUN_DIR -u XDG_RUNTIME_DIR -u CE_DLOG_PATH \
      HOME="$WORK/no_such_home" timeout 60 "$CHAT" 2>&1); RC=$?
assert_eq "$RC" "0" "missing HOME falls back to /tmp/crossengin-run-<uid>"
assert_eq "$(stat -c '%a' "/tmp/crossengin-run-$(id -u)" 2>/dev/null)" "700" "/tmp/crossengin-run-<uid> is 0700"

# 6. the daemon reads its command input from the run dir, not /tmp
DAEMON="$REPO_ROOT/bin/crossengin"
if [ -x "$DAEMON" ]; then
    mkdir -m 700 "$WORK/rd" "$WORK/rd_empty"
    printf 'fever\n' > "$WORK/rd/crossengin_input"
    OUT=$(CE_RUN_DIR="$WORK/rd" timeout 120 "$DAEMON" 2>&1)
    assert_match "$OUT" "^agent> " "daemon answers input from \$CE_RUN_DIR/crossengin_input"
    PLANTED=/tmp/crossengin_input
    if [ ! -e "$PLANTED" ]; then
        printf 'fever\n' > "$PLANTED"
        OUT=$(CE_RUN_DIR="$WORK/rd_empty" timeout 120 "$DAEMON" 2>&1)
        rm -f "$PLANTED"
        assert_eq "$(grep -c '^agent> ' <<<"$OUT")" "0" "planted /tmp/crossengin_input is ignored"
    fi
fi

summary "scenario_file_hardening"
