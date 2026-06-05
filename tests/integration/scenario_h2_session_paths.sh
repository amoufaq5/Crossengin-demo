#!/usr/bin/env bash
# Scenario H2 -- per-session snapshot + dlog paths.
#
# P1.2 closes the per-session disk-image gap: a `/switch alice` followed by
# `/save` (no path arg) must write alice's snapshot to its OWN file at
# /tmp/crossengin.alice.snap, leaving the default session's snapshot at
# /tmp/crossengin.default.snap untouched. The daemon under CE_SESSION_ID=alice
# must read AND write the same alice file when booted alone (single-session
# driving mode -- this scenario uses the chat to seed and the daemon to
# verify the disk image).
#
# Coverage:
#   1. `/save` default-path resolution: with the active session set to
#      `default`, the snapshot lands at /tmp/crossengin.default.snap; with
#      the active session set to `alice`, it lands at /tmp/crossengin.alice.snap.
#   2. The two snapshots are DISTINCT files (same process can't accidentally
#      clobber the default tenant's image by switching to alice).
#   3. Save in default, /switch alice, /save -- both files exist; the default
#      file is byte-identical to what it was BEFORE the alice save (proof
#      that the alice save did not touch the default file).
#   4. Round-trip via the chat: /switch alice + /save + restart chat +
#      /switch alice + /load (no path) successfully rehydrates the alice KG
#      with the alice-only taught word.
#   5. Daemon round-trip: a daemon launched with CE_SESSION_ID=alice writes
#      its dlog to /tmp/crossengin.alice.dlog (NOT /tmp/crossengin.default.dlog).
#   6. Legacy back-compat: CE_SNAP_PATH wins over the per-session derivation.

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0

DEFAULT_SNAP="/tmp/crossengin.default.snap"
ALICE_SNAP="/tmp/crossengin.alice.snap"
DEFAULT_DLOG="/tmp/crossengin.default.dlog"
ALICE_DLOG="/tmp/crossengin.alice.dlog"
LEGACY_SNAP="/tmp/ce_h2_legacy.snap"

trap 'rm -f "$DEFAULT_SNAP" "$DEFAULT_SNAP.tmp" "$ALICE_SNAP" "$ALICE_SNAP.tmp" "$DEFAULT_DLOG" "$ALICE_DLOG" "$LEGACY_SNAP" "$LEGACY_SNAP.tmp"' EXIT
rm -f "$DEFAULT_SNAP" "$DEFAULT_SNAP.tmp" "$ALICE_SNAP" "$ALICE_SNAP.tmp" \
      "$DEFAULT_DLOG" "$ALICE_DLOG" "$LEGACY_SNAP" "$LEGACY_SNAP.tmp"

it_section "scenario H2: per-session snapshot + dlog paths"

# --- 1. /save default -> /tmp/crossengin.default.snap --------------------
OUT1=$(printf '/teach widget
/save
/quit
' | "$CHAT" 2>&1)
assert_match "$OUT1" "saved soul=Aurora.*-> $DEFAULT_SNAP durably" \
    "/save (no arg) in default lands at /tmp/crossengin.default.snap"
assert_file_exists "$DEFAULT_SNAP" "default snapshot file exists after /save"

# Capture the default snapshot checksum BEFORE we touch alice.
CHK_DEFAULT_PRE=$(md5sum "$DEFAULT_SNAP" 2>/dev/null | awk '{print $1}')

# --- 2. /switch alice, /save -> /tmp/crossengin.alice.snap ---------------
OUT2=$(printf '/teach widget
/save
/switch alice
/teach gadget
/save
/quit
' | "$CHAT" 2>&1)
assert_match "$OUT2" "saved soul=Aurora.*-> $DEFAULT_SNAP durably" \
    "default save still hits default file when both sessions are active"
assert_match "$OUT2" "saved soul=Default.*-> $ALICE_SNAP durably" \
    "/save after /switch alice lands at /tmp/crossengin.alice.snap"
assert_file_exists "$ALICE_SNAP" "alice snapshot file exists after /save"

# --- 3. The default file was NOT touched by alice's save -----------------
CHK_DEFAULT_POST=$(md5sum "$DEFAULT_SNAP" 2>/dev/null | awk '{print $1}')
assert_eq "$CHK_DEFAULT_POST" "$CHK_DEFAULT_PRE" \
    "alice's /save did not clobber the default snapshot"

# --- 4. The two files are distinct ---------------------------------------
CHK_ALICE=$(md5sum "$ALICE_SNAP" 2>/dev/null | awk '{print $1}')
if [ "$CHK_ALICE" != "$CHK_DEFAULT_POST" ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  default and alice snapshots have distinct contents\n"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  default and alice snapshots ended up byte-identical\n"
fi

# --- 5. Restart chat, /switch alice, /load (no path) rehydrates alice ----
# The reload must report the alice path AND the alice-taught word ("gadget")
# must be recognized in subsequent perception.
OUT3=$(printf '/switch alice
/load
gadget
/quit
' | "$CHAT" 2>&1)
assert_match "$OUT3" "loaded $ALICE_SNAP" \
    "/load (no arg) after /switch alice reads alice's per-session snapshot"
# After /load, the "gadget" perception line should show m>=1 / unk=0.
PERCEIVE_GADGET=$(echo "$OUT3" | grep -oE "perceive\(m=[0-9]+,unk=[0-9]+\)" | head -1)
assert_match "$PERCEIVE_GADGET" "perceive\\(m=[1-9][0-9]*,unk=0\\)" \
    "alice's KG remembers 'gadget' after the per-session load"

# --- 6. Daemon CE_SESSION_ID=alice writes its dlog to alice.dlog --------
# The daemon's scripted episode produces 7 dlog entries by default. The dlog
# under CE_SESSION_ID=alice must land at /tmp/crossengin.alice.dlog AND the
# default file must not be touched.
if [ -x "$DAEMON" ]; then
    rm -f "$DEFAULT_DLOG" "$ALICE_DLOG"
    OUT4=$(CE_SESSION_ID=alice "$DAEMON" 2>&1)
    assert_match "$OUT4" "session=alice" \
        "daemon banner reports active session id"
    assert_match "$OUT4" "persisted to $ALICE_DLOG" \
        "daemon under CE_SESSION_ID=alice persists dlog at alice path"
    assert_file_exists "$ALICE_DLOG" "alice dlog file exists after daemon run"
    if [ ! -f "$DEFAULT_DLOG" ]; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}PASS${C_RST}  daemon under CE_SESSION_ID=alice did NOT touch default dlog\n"
    else
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  daemon under CE_SESSION_ID=alice unexpectedly touched %s\n" \
            "$DEFAULT_DLOG"
    fi
else
    printf "  ${C_YEL}SKIP${C_RST}  daemon binary not built; skipping daemon dlog assertions\n"
fi

# --- 7. Legacy CE_SNAP_PATH override still wins --------------------------
OUT5=$(CE_SNAP_PATH="$LEGACY_SNAP" printf '/teach widget
/save
/quit
' | CE_SNAP_PATH="$LEGACY_SNAP" "$CHAT" 2>&1)
assert_match "$OUT5" "saved soul=.*-> $LEGACY_SNAP durably" \
    "CE_SNAP_PATH legacy override beats per-session derivation"
assert_file_exists "$LEGACY_SNAP" "legacy snapshot file exists"

summary "scenario_h2_session_paths"
