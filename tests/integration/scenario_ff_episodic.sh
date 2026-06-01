#!/usr/bin/env bash
# Scenario FF -- episodic memory consolidation cycle end-to-end.
#
# Long-term memory promotion: scan recent observations, detect clusters of
# atoms that co-occur within a small temporal window, mint each into an
# "episodic atom" with Beta(alpha, beta) belief, persist via the v2
# snapshot's EPISODIC sub-block. Verifies:
#
#   1. A NOVA driver minting episodic atoms produces a snapshot whose text
#      form carries the new `episodic.atoms.*` lines.
#   2. The wire format declares `ver 2` (no major bump from R5D's v2).
#   3. The new sub-block round-trips: a re-parse + re-apply rehydrates the
#      same cluster members, count, first/last observation timestamps, and
#      Beta(alpha, beta) belief verbatim.
#   4. A snapshot WITHOUT episodic atoms still parses without error
#      (forward-compat: legacy 2-element blob shape).
#
# This is the acceptance test for the episodic-consolidation cycle landed
# in this session (R6F). The cycle's wiring into the memory loop is
# covered by tests/unit/test_episodic.nova; this scenario validates the
# on-disk seam.

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

NOVA_ROOT="${NOVA_ROOT:-$HOME/NOVA}"
NOVA="$NOVA_ROOT/nova"
DEMO_DRIVER="$REPO_ROOT/examples/episodic_demo.nova"
LEGACY_DRIVER="$REPO_ROOT/examples/episodic_legacy_load.nova"
OUT_SNAP="/tmp/ce_int_scenario_ff.snap"
LEGACY_PATH="/tmp/ce_int_scenario_ff_legacy.snap"

trap 'rm -f "$OUT_SNAP" "$OUT_SNAP.tmp" "$LEGACY_PATH" "$LEGACY_PATH.tmp"' EXIT
rm -f "$OUT_SNAP" "$OUT_SNAP.tmp" "$LEGACY_PATH" "$LEGACY_PATH.tmp"

it_section "scenario FF: episodic consolidation + snapshot round-trip"

# --- guard: NOVA toolchain available ---
if [ ! -x "$NOVA" ]; then
    FAIL=$((FAIL+1))
    echo "FAIL: NOVA launcher not found at '$NOVA'"
    summary "scenario_ff_episodic"
    exit 1
fi

assert_file_exists "$DEMO_DRIVER"   "demo driver source exists"
assert_file_exists "$LEGACY_DRIVER" "legacy-load driver source exists"

# --- step 1: run the consolidation + snapshot round-trip driver --------
OUT="$(CE_EPI_DEMO_SNAP="$OUT_SNAP" "$NOVA" run "$DEMO_DRIVER" 2>&1)"
RC=$?
echo "$OUT" | sed 's/^/    /'

assert_eq "$RC" "0" "demo driver exits 0"

# --- step 2: verify the driver's stdout reports a successful consolidation
MINTED="$(echo "$OUT" | grep -E '^minted=' | head -1 | cut -d= -f2)"
ATOMS_PRE="$(echo "$OUT" | grep -E '^atoms_count=' | head -1 | cut -d= -f2)"
SAVE_OK="$(echo "$OUT" | grep -E '^save_ok=' | head -1 | cut -d= -f2)"
RELOAD_OK="$(echo "$OUT" | grep -E '^reload_ok=' | head -1 | cut -d= -f2)"
RELOAD_VER="$(echo "$OUT" | grep -E '^reload_ver=' | head -1 | cut -d= -f2)"
RELOAD_SUBL="$(echo "$OUT" | grep -E '^reload_sublists=' | head -1 | cut -d= -f2)"
RELOAD_RECS="$(echo "$OUT" | grep -E '^reload_atoms_records=' | head -1 | cut -d= -f2)"
RELOAD_ATOMS="$(echo "$OUT" | grep -E '^reload_atoms=' | head -1 | cut -d= -f2)"
RELOAD_MEM="$(echo "$OUT" | grep -E '^reload_member_count=' | head -1 | cut -d= -f2)"
RELOAD_FIRST="$(echo "$OUT" | grep -E '^reload_first_ns=' | head -1 | cut -d= -f2)"
RELOAD_LAST="$(echo "$OUT" | grep -E '^reload_last_ns=' | head -1 | cut -d= -f2)"
RELOAD_COUNT="$(echo "$OUT" | grep -E '^reload_count=' | head -1 | cut -d= -f2)"
RELOAD_ALPHA="$(echo "$OUT" | grep -E '^reload_alpha=' | head -1 | cut -d= -f2)"
RELOAD_BETA="$(echo "$OUT" | grep -E '^reload_beta=' | head -1 | cut -d= -f2)"

assert_eq "$MINTED"        "1"          "5x(1,2,3) -> 1 episodic atom minted"
assert_eq "$ATOMS_PRE"     "1"          "store has 1 atom after consolidation"
assert_eq "$SAVE_OK"       "1"          "snapshot save reports success"
assert_eq "$RELOAD_OK"     "1"          "snapshot reload returns valid handle"
assert_eq "$RELOAD_VER"    "2"          "reloaded snapshot declares ver 2"
assert_eq "$RELOAD_SUBL"   "3"          "EPISODIC blob has 3 sub-lists post-reload"
assert_eq "$RELOAD_RECS"   "1"          "blob[2] has 1 episodic-atom record"
assert_eq "$RELOAD_ATOMS"  "1"          "post-apply store has 1 atom"
assert_eq "$RELOAD_MEM"    "3"          "cluster members count survives (3)"
assert_eq "$RELOAD_FIRST"  "0"          "first_seen survives (0)"
assert_eq "$RELOAD_LAST"   "40"         "last_seen survives (40)"
assert_eq "$RELOAD_COUNT"  "5"          "co-occurrence count survives (5)"
assert_eq "$RELOAD_ALPHA"  "1000"       "alpha at uniform prior survives (1000)"
assert_eq "$RELOAD_BETA"   "1000"       "beta at uniform prior survives (1000)"

# --- step 3: inspect the on-disk wire format for the new keys ------------
assert_file_exists "$OUT_SNAP" "snapshot file exists on disk"

SNAP_TEXT="$(cat "$OUT_SNAP" 2>/dev/null)"
assert_match "$SNAP_TEXT" "^crossengin-snapshot v1$"            "header banner present"
assert_match "$SNAP_TEXT" "^ver 2$"                              "wire format declares ver 2"
assert_match "$SNAP_TEXT" "^episodic\\.present 1$"               "EPISODIC section flagged present"
assert_match "$SNAP_TEXT" "^episodic\\.atoms\\.count 1$"         "new episodic.atoms.count line"
assert_match "$SNAP_TEXT" "^episodic\\.atoms\\[0\\]\\.member_count 3$" "cluster has 3 members"
assert_match "$SNAP_TEXT" "^episodic\\.atoms\\[0\\]\\.members\\[0\\] 1$" "members[0] = 1"
assert_match "$SNAP_TEXT" "^episodic\\.atoms\\[0\\]\\.members\\[1\\] 2$" "members[1] = 2"
assert_match "$SNAP_TEXT" "^episodic\\.atoms\\[0\\]\\.members\\[2\\] 3$" "members[2] = 3"
assert_match "$SNAP_TEXT" "^episodic\\.atoms\\[0\\]\\.count 5$"  "count line is 5"
assert_match "$SNAP_TEXT" "^episodic\\.atoms\\[0\\]\\.first_ns 0$" "first_ns line is 0"
assert_match "$SNAP_TEXT" "^episodic\\.atoms\\[0\\]\\.last_ns 40$" "last_ns line is 40"
assert_match "$SNAP_TEXT" "^episodic\\.atoms\\[0\\]\\.alpha 1000$" "alpha line is 1000"
assert_match "$SNAP_TEXT" "^episodic\\.atoms\\[0\\]\\.beta 1000$"  "beta line is 1000"
assert_match "$SNAP_TEXT" "^episodic\\.atoms\\[0\\]\\.provenance consolidation/cooccurrence$" \
    "provenance line carries default label"
assert_match "$SNAP_TEXT" "^end$"                                "file ends with 'end' line"

# --- step 4: forward-compat with a legacy 2-element EPISODIC blob -------
cat >"$LEGACY_PATH" <<'V2_LEGACY_EOF'
crossengin-snapshot v1
tag 5361
ver 2
instance 7
timestamp 1700000001
sections 5
meta.creator unknown/<v1>
meta.created_ns 0
meta.compaction_threshold -1
meta.encryption none
soul.present 1
soul.name Aurora
soul.constcount 0
kgs.present 0
episodic.present 1
episodic.moments.count 0
episodic.episodes.count 0
synapses.present 0
selfmodel.present 0
end
V2_LEGACY_EOF

OUT2="$(CE_EPI_LEGACY_SNAP="$LEGACY_PATH" "$NOVA" run "$LEGACY_DRIVER" 2>&1)"
RC2=$?
echo "$OUT2" | sed 's/^/    /'
assert_eq "$RC2" "0" "legacy driver exits 0"

LEG_LOAD="$(echo "$OUT2" | grep -E '^legacy_load=' | head -1 | cut -d= -f2)"
LEG_SUBL="$(echo "$OUT2" | grep -E '^legacy_sublists=' | head -1 | cut -d= -f2)"
LEG_RECS="$(echo "$OUT2" | grep -E '^legacy_atoms_records=' | head -1 | cut -d= -f2)"

assert_eq "$LEG_LOAD" "1"  "legacy v2 (no episodic.atoms) loads cleanly"
assert_eq "$LEG_SUBL" "3"  "blob normalized to 3 sub-lists (third empty)"
assert_eq "$LEG_RECS" "0"  "legacy snapshot rehydrates 0 episodic atoms"

summary "scenario_ff_episodic"
