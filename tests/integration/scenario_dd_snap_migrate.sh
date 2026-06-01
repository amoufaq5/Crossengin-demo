#!/usr/bin/env bash
# Scenario DD -- snapshot v1 -> v2 migration end-to-end.
#
# Hand-rolls a synthetic v1 snapshot file (the on-disk wire shape the
# original SNAP_FORMAT_VERSION = 1 writer produced), runs
# scripts/migrate_snapshot.sh to upgrade it to v2, then verifies:
#
#   * the output file exists and is well-formed
#   * the output declares `ver 2` on the wire
#   * the output carries the four v1-recovery meta lines
#   * the wrapper's report line names the migration explicitly
#
# This is the acceptance test for the v1 -> v2 migration procedure landed
# in this session. The contract: a v1 file written by the old daemon can
# be rewritten in place as a v2 file readable by the current daemon
# without a chat session ever booting.

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

OLD_PATH="/tmp/ce_int_scenario_dd_v1.snap"
NEW_PATH="/tmp/ce_int_scenario_dd_v2.snap"
trap 'rm -f "$OLD_PATH" "$NEW_PATH" "$NEW_PATH.tmp"' EXIT
rm -f "$OLD_PATH" "$NEW_PATH" "$NEW_PATH.tmp"

it_section "scenario DD: snapshot v1 -> v2 migration"

# --- step 1: hand-roll a synthetic v1 snapshot ----------------------------
# The shape mirrors what the pre-this-session writer emitted: header banner +
# tag + ver=1 + sections=5 + each section's `.present` flag. We include a
# soul section with a name so the migrated file has SOMETHING to round-trip
# beyond the meta block.
cat >"$OLD_PATH" <<'V1_EOF'
crossengin-snapshot v1
tag 5361
ver 1
instance 42
timestamp 1700000000
sections 5
soul.present 1
soul.name Aurora
soul.constcount 0
kgs.present 0
episodic.present 0
synapses.present 0
selfmodel.present 0
end
V1_EOF

assert_file_exists "$OLD_PATH" "hand-rolled v1 snapshot exists"

# Sanity: the v1 file declares `ver 1`.
if grep -q '^ver 1$' "$OLD_PATH"; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  %s\n" "v1 snapshot declares 'ver 1'"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  %s\n" "v1 snapshot is not declaring ver 1"
fi

# Confirm the v1 file does NOT carry meta lines (they're a v2 addition).
if grep -q '^meta\.' "$OLD_PATH"; then
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  %s\n" "v1 file unexpectedly contains meta lines"
else
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  %s\n" "v1 file has no meta lines (as expected)"
fi

# --- step 2: run the migration wrapper -----------------------------------
MIGRATE_SH="$(cd "$(dirname "$0")/../.." && pwd)/scripts/migrate_snapshot.sh"
if [ ! -x "$MIGRATE_SH" ]; then
    chmod +x "$MIGRATE_SH" 2>/dev/null || true
fi

OUT=$(NOVA_ROOT="${NOVA_ROOT:-$HOME/NOVA}" bash "$MIGRATE_SH" "$OLD_PATH" "$NEW_PATH" 2>&1)
RC=$?

assert_eq "$RC" "0" "migrate_snapshot.sh exits 0"

# Wrapper's report line.
assert_match "$OUT" "migrated v1 -> v2" "wrapper reports v1 -> v2 migration"
assert_match "$OUT" "[0-9]+ -> [0-9]+ bytes" "wrapper reports old -> new byte counts"

# --- step 3: verify the v2 output ----------------------------------------
assert_file_exists "$NEW_PATH" "migrated v2 snapshot exists"

# The output must declare ver 2.
if grep -q '^ver 2$' "$NEW_PATH"; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  %s\n" "v2 snapshot declares 'ver 2'"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  %s\n" "v2 snapshot does not declare ver 2"
fi

# All four meta lines must be present.
NEW_TEXT="$(cat "$NEW_PATH" 2>/dev/null)"
assert_match "$NEW_TEXT" "^meta\\.creator unknown/<v1>$" "meta.creator = unknown/<v1>"
assert_match "$NEW_TEXT" "^meta\\.created_ns 0$"           "meta.created_ns = 0"
assert_match "$NEW_TEXT" "^meta\\.compaction_threshold -1$" "meta.compaction_threshold = -1"
assert_match "$NEW_TEXT" "^meta\\.encryption none$"         "meta.encryption = none"

# Section payload survives the migration.
assert_match "$NEW_TEXT" "^soul\\.name Aurora$" "soul.name 'Aurora' survives migration"
assert_match "$NEW_TEXT" "^instance 42$"        "instance 42 survives migration"
assert_match "$NEW_TEXT" "^timestamp 1700000000$" "timestamp survives migration"
assert_match "$NEW_TEXT" "^end$" "well-formed: ends with 'end' line"

summary "scenario_dd_snap_migrate"
