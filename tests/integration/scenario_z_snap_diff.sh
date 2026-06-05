#!/usr/bin/env bash
# Scenario Z -- snap_diff.sh reports atom-set deltas between two snapshots.
#
# Boot chat -> /save snap1 -> /teach widget -> /save snap2 -> run
# `bash scripts/snap_diff.sh snap1 snap2`, verify it reports "added: widget".
# Also asserts:
#   * the snap_diff "summary:" tail names the right atom delta (+ count >= 1)
#   * the "removed" set stays empty (we only ADDED an atom)
#   * the script exits 0 on success and produces section headers
#   * a no-op diff (snap1 vs snap1) reports "no change" with no spurious adds

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0

SNAP1="/tmp/ce_int_scenario_z.snap1"
SNAP2="/tmp/ce_int_scenario_z.snap2"
SNAP_DIFF="$REPO_ROOT/scripts/snap_diff.sh"

trap 'rm -f "$SNAP1" "$SNAP2" "$SNAP1.tmp" "$SNAP2.tmp" \
            /tmp/crossengin.default.snap /tmp/crossengin.default.dlog' EXIT

# Pre-flight: the diff script must exist.
if [ ! -f "$SNAP_DIFF" ]; then
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  snap_diff script not found at %s\n" "$SNAP_DIFF"
    summary "scenario_z_snap_diff"
    exit $?
fi

it_section "scenario Z: snap_diff reports atom delta after /teach widget"

# Start fresh so neither snapshot has 'widget' pre-loaded from earlier runs.
rm -f "$SNAP1" "$SNAP2" /tmp/crossengin.default.snap /tmp/crossengin.default.dlog

# Save baseline -> teach widget -> save again, in one chat session so the live
# state survives across the two /save calls. The chat's /save flushes the
# section blobs to disk via the same writer the daemon uses (fsync + atomic
# rename), so both files are durable before /quit returns.
OUT="$(printf '/save %s\n/teach widget\n/save %s\n/quit\n' \
        "$SNAP1" "$SNAP2" | "$CHAT" 2>&1)"

assert_match "$OUT" "ingested 'widget'"                "/teach widget acknowledged"
assert_match "$OUT" "saved .*-> $SNAP1 durably"        "snap1 written durably"
assert_match "$OUT" "saved .*-> $SNAP2 durably"        "snap2 written durably"
assert_file_exists "$SNAP1" "snap1 file exists"
assert_file_exists "$SNAP2" "snap2 file exists"

# --- step 1: run snap_diff -------------------------------------------------
DIFF_OUT="$(bash "$SNAP_DIFF" "$SNAP1" "$SNAP2" 2>&1)"
DIFF_RC=$?

assert_eq "$DIFF_RC" "0"                                       "snap_diff exit code 0"
assert_match "$DIFF_OUT" "=== snap_diff ==="                   "snap_diff prints header"
# Use grep -e to avoid `--` being parsed as a flag separator. assert_match
# pipes to grep, so we shape the pattern to start with a printable char that
# is not a leading dash; "-{2} atoms" matches "-- atoms".
assert_match "$DIFF_OUT" "[-]{2} atoms [-]{2}"                 "atoms section header"
assert_match "$DIFF_OUT" "[-]{2} soul [-]{2}"                  "soul section header"
assert_match "$DIFF_OUT" "added:.*widget"                      "reports 'added: widget'"

# The summary line at the tail. We /teach'd one word; the writer emits BOTH
# a language-KG word atom AND a reasoning-KG concept atom for it, so the
# add count is >=1 (1 or 2 depending on seed). Tests "at least 1 added";
# "summary: atoms +0" would mean the diff missed the widget entirely.
SUMMARY_LINE="$(printf '%s\n' "$DIFF_OUT" | grep -E '^summary:' | head -n 1)"
if [ -z "$SUMMARY_LINE" ]; then
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  no 'summary:' line in snap_diff output\n"
else
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  summary line present: %s\n" "$SUMMARY_LINE"
    assert_match "$SUMMARY_LINE" "atoms \\+[1-9]"  "atoms-added count >= 1"
    assert_match "$SUMMARY_LINE" "\\-0 "           "atoms-removed count == 0"
fi

# --- step 2: identity diff (snap1 vs snap1) should report no change --------
NOOP_OUT="$(bash "$SNAP_DIFF" "$SNAP1" "$SNAP1" 2>&1)"
NOOP_RC=$?
assert_eq "$NOOP_RC" "0"                            "snap_diff identity exit code 0"
assert_match "$NOOP_OUT" "(no change|no mood / OCEAN drift)" \
    "identity diff says 'no change' / no drift"
assert_nomatch "$NOOP_OUT" "added:.*widget"         "identity diff has no 'added: widget'"
assert_nomatch "$NOOP_OUT" "removed:.*widget"       "identity diff has no 'removed: widget'"

# --- step 3: usage / missing-args behaviour --------------------------------
USAGE_OUT="$(bash "$SNAP_DIFF" 2>&1)"
USAGE_RC=$?
assert_eq "$USAGE_RC" "2"                           "missing args exits 2 (usage)"
assert_match "$USAGE_OUT" "usage:"                  "usage hint printed"

summary "scenario_z_snap_diff"
