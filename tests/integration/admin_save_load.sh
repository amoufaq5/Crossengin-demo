#!/usr/bin/env bash
# Admin commands -- /save and /load edge cases.

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0

SNAP_DEFAULT="/tmp/crossengin.snap"
SNAP_EXPLICIT="/tmp/ce_int_admin_save.snap"
SNAP_BADDIR="/this_dir_does_not_exist_xyz/snap.snap"
CORRUPT="/tmp/ce_int_corrupt.snap"

trap 'rm -f "$SNAP_EXPLICIT" "$SNAP_EXPLICIT.tmp" "$CORRUPT"' EXIT
rm -f "$SNAP_EXPLICIT" "$SNAP_EXPLICIT.tmp" "$CORRUPT"

# -------------------- /save --------------------
it_section "admin: /save"

# Default path: no arg.
OUT=$(run_chat '/save')
assert_match "$OUT" "saved soul=.*-> /tmp/crossengin.snap durably" "/save with no path uses default"
assert_file_exists "$SNAP_DEFAULT" "default snapshot file exists"

# Explicit path.
OUT=$(run_chat "/save $SNAP_EXPLICIT")
assert_match "$OUT" "saved soul=.*-> $SNAP_EXPLICIT durably" "/save PATH uses that path"
assert_file_exists "$SNAP_EXPLICIT" "explicit snapshot file exists"

# Invalid directory: failure message.
OUT=$(run_chat "/save $SNAP_BADDIR")
assert_match "$OUT" "save FAILED" "/save to invalid dir prints FAILED message"

# -------------------- /load --------------------
it_section "admin: /load"

# Missing file.
OUT=$(run_chat '/load /tmp/no_such_snap_file_xyz.snap')
assert_match "$OUT" "load FAILED" "/load missing file prints FAILED"

# Corrupt file: write a non-snapshot text and try to load it.
echo "this is not a snapshot, just garbage" > "$CORRUPT"
OUT=$(run_chat "/load $CORRUPT")
assert_match "$OUT" "load FAILED" "/load corrupt file prints FAILED"

# Valid file: round-trip a teach -> save -> load and verify the rehydrate
# report.
OUT=$(run_chat "/teach widget
/save $SNAP_EXPLICIT
/load $SNAP_EXPLICIT")
assert_match "$OUT" "loaded $SNAP_EXPLICIT" "/load valid file reports the path"
assert_match "$OUT" "soul: name=Aurora" "/load reports soul name in rehydrate"
assert_match "$OUT" "kgs: blob_count=" "/load reports kgs blob count"
assert_match "$OUT" "reasoning KG: " "/load reports reasoning KG transition"
assert_match "$OUT" "language KG : " "/load reports language KG transition"

summary "admin_save_load"
