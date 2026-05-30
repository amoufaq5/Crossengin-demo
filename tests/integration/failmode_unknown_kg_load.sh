#!/usr/bin/env bash
# Failure mode -- /load on a snapshot containing a kgs.atoms[N].kg label that
# the running daemon does not know.
#
# Fixed behavior (per src/persistence/snapshot_disk.nova: kg_section_apply,
# after the bug-fix sprint):
#   kg_section_apply validates each atom's kg label against the known-KG set
#   (reasoning / language / imagination / world). Unknown labels trigger a
#   "snapshot atom #N has unknown kg 'X' -- skipped" warning and the atom
#   is silently dropped instead of being installed into an auto-spawned KG.
#   This blocks a malicious snapshot from creating arbitrary KGs.
#
# Previously (KNOWN-broken state pinned by P1.7): kg_spawn was idempotent on
# label so unknown labels silently auto-created new KGs.

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

# FIXED BEHAVIOR: the load still succeeds (the other 1136 atoms install
# fine), but the unknown-kg atom is SKIPPED with a warning. new_atoms is 0
# because the malicious unknown-kg atom did NOT create an auto-spawned KG.
assert_match "$OUT_LOAD" "loaded $HACKED_SNAP" "/load on unknown-KG snapshot succeeds (skip-with-warning)"
assert_match "$OUT_LOAD" "warning: snapshot atom #[0-9]+ has unknown kg 'unknownkg' -- skipped" "warning identifies the skipped atom + unknown kg label"
assert_match "$OUT_LOAD" "new_atoms=0" "/load reports new_atoms=0 (unknown-kg atom rejected, not auto-spawned)"
# /status must still work.
assert_match "$OUT_LOAD" "soul +: Aurora" "/status still reports Aurora after the load"

summary "failmode_unknown_kg_load"
