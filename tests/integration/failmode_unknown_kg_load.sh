#!/usr/bin/env bash
# Failure mode -- /load on a snapshot containing a kgs.atoms[N].kg label that
# the running daemon does not know.
#
# Current behavior (per src/persistence/snapshot_disk.nova: kg_section_apply):
#   `kg_spawn(kg_reg, kg_lbl)` is idempotent -- it auto-creates a NEW KG with
#   the unknown label if one doesn't exist, then installs the atom there.
#   This means an unknown kg label is silently accepted; the atom lands in a
#   new auto-spawned KG; the /load reports success and `new_atoms=1` (or
#   whatever the count is).
#
# This test asserts that current behavior. If the policy ever changes to
# "skip unknown KGs with a warning" or "error out", this test must be updated.

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0

REAL_SNAP=/tmp/ce_int_unkkg_real_$$.snap
HACKED_SNAP=/tmp/ce_int_unkkg_hacked_$$.snap
trap 'rm -f "$REAL_SNAP" "$REAL_SNAP.tmp" "$HACKED_SNAP" "$HACKED_SNAP.tmp"' EXIT
rm -f "$REAL_SNAP" "$REAL_SNAP.tmp" "$HACKED_SNAP" "$HACKED_SNAP.tmp"

it_section "failmode: /load on snapshot with unknown KG label"

# --- Step 1: get a real, valid snapshot. ----------------------------------
OUT=$(run_chat "/save $REAL_SNAP")
assert_match "$OUT" "saved soul=.*-> $REAL_SNAP durably" "baseline /save succeeded"
assert_file_exists "$REAL_SNAP" "baseline snapshot present"

# --- Step 2: surgically rewrite the FIRST atom's `kg` field to an unknown
#     label (`unknownkg`). We need ONLY one atom rewritten -- the rest stay
#     in their valid KGs so the load still completes most of its work.
sed 's|^kgs.atoms\[0\].kg reasoning$|kgs.atoms[0].kg unknownkg|' "$REAL_SNAP" > "$HACKED_SNAP"
HACK_LINES=$(grep -c '^kgs.atoms\[0\].kg unknownkg$' "$HACKED_SNAP" || echo 0)
assert_eq "$HACK_LINES" "1" "hack: atoms[0].kg rewritten to 'unknownkg' once"

# --- Step 3: load it and observe the behavior. ----------------------------
OUT_LOAD=$(printf '/load %s\n/status\n/quit\n' "$HACKED_SNAP" | "$CHAT" 2>&1)

# CURRENT BEHAVIOR: the load succeeds; the unknown kg label is treated as a
# new KG to auto-spawn (kg_spawn is idempotent on label). The integration
# point is `kg_section_apply` in src/persistence/snapshot_disk.nova.
assert_match "$OUT_LOAD" "loaded $HACKED_SNAP" "/load on unknown-KG snapshot succeeds (current behavior)"
# `new_atoms=` will be at least 1 because the unknown-KG atom is new (no
# existing same-label atom in a same-named KG).
assert_match "$OUT_LOAD" "new_atoms=[1-9][0-9]*" "/load reports >=1 new atoms (unknown-kg atom was created)"
# /status must still work.
assert_match "$OUT_LOAD" "soul +: Aurora" "/status still reports Aurora after the load"

# KNOWN: kg_section_apply (snapshot_disk.nova) does kg_spawn on any label it
# sees -- there is no warning for "unrecognized kg label" today. If the
# policy ever grows a skip-with-warning behavior, the assertions above need
# to flip (`load FAILED`/`warning skipping kg=`/etc) and the test must be
# updated. Documenting present behavior, not blessing it as right.

summary "failmode_unknown_kg_load"
