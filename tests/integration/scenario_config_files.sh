#!/usr/bin/env bash
# Scenario config-files -- the chat's optional config files must load.
# caps.conf (CE_CAPS_CONF) and the fetch whitelist (CE_FETCH_WHITELIST_CONF)
# were read with sys_read(fd, 4096) -- wrong arity, expecting a string --
# which read nothing, so both files were silently ignored.

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0
it_section "scenario config-files: caps.conf + fetch whitelist load"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
printf '# test\nautonomous_fetch=allow\n' > "$WORK/caps.conf"
printf 'zz-test-domain.example\n' > "$WORK/fw.conf"

OUT=$(printf '/cap list\n/__sa__\n/quit\n' | CE_CAPS_CONF="$WORK/caps.conf" \
      CE_FETCH_WHITELIST_CONF="$WORK/fw.conf" timeout 60 "$CHAT" 2>&1)
assert_match "$OUT" "autonomous_fetch override=allow" "caps.conf grant applied"
assert_match "$OUT" "domain=zz-test-domain.example" "fetch whitelist file loaded"

summary "scenario_config_files"
