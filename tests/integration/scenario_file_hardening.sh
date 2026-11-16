#!/usr/bin/env bash
# Scenario file-hardening -- audit F-24.
#   1. A symlink planted at <snapshot>.tmp must not be followed by /save.
#   2. With no CE_RUN_DIR, default state lands in a private 0700 runtime
#      dir ($HOME/.crossengin/run here), not /tmp.
#   3. A runtime dir that is group/other accessible is refused (exit 70).

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

summary "scenario_file_hardening"
