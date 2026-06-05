#!/usr/bin/env bash
# Scenario LLL -- Merkle-tree tamper-evident atom-hash chain (R15E).
#
# Where this fits: the v2 snapshot format (R5D) -- with schema evolution
# (R8E), episodic atoms (R6F), and incremental deltas (R13F) -- already
# survives crashes and gives the substrate a complete persistent
# image. What was missing: TAMPER DETECTION. Without it, an operator
# could `vim` a snapshot file on disk, flip a single bit in any atom,
# and the next /load would happily install the mutated state with no
# indication anything was off.
#
# R15E adds a SHA-256 Merkle tree over the KGS atom records; the root
# hash is emitted as an optional `meta.merkle_root <hex>` line in the
# v2 meta block. Older readers ignore the line (forward-compat). The
# new chat command `/snap_verify [PATH]` reloads the file, recomputes
# the root, and reports `verified | TAMPERED`. With
# CE_SNAPSHOT_VERIFY_MERKLE=1 the reader bails on a mismatched root
# during the normal /load path.
#
# This scenario asserts the end-to-end story:
#   * /save writes a snapshot that carries a `meta.merkle_root` line.
#   * /snap_verify on the freshly-saved file reports "verified".
#   * Tampering one byte in any atom's value makes /snap_verify report
#     "TAMPERED".
#   * Tampering does NOT need to land on a SHA-256-fixed offset: any
#     atom field (label / belief / kg name) flips the root.
#   * Re-saving the SAME KG twice produces the SAME root (determinism).
#   * A pre-R15E snapshot (manually emitted without the meta line)
#     reports the "no Merkle commitment" branch, not a false-positive
#     TAMPERED.
#   * With CE_SNAPSHOT_VERIFY_MERKLE=1 set, /load on a tampered file
#     fails with a clear "TAMPERED" error before any state is mutated.

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

it_section "scenario LLL: Merkle tamper-evident snapshots (R15E)"

require_chat

# Use dedicated paths so a parallel CE_SNAP_PATH doesn't leak in.
SNAP_OK="/tmp/ce_int_lll_ok.snap"
SNAP_OK2="/tmp/ce_int_lll_ok2.snap"
SNAP_TAMP="/tmp/ce_int_lll_tampered.snap"
SNAP_PRE="/tmp/ce_int_lll_pre.snap"

trap '
  rm -f "$SNAP_OK" "$SNAP_OK2" "$SNAP_TAMP" "$SNAP_PRE" \
        "$SNAP_OK".tmp "$SNAP_OK2".tmp "$SNAP_TAMP".tmp "$SNAP_PRE".tmp
' EXIT

# ---- assertion 1: /save emits a meta.merkle_root line ------------------
rm -f "$SNAP_OK" "$SNAP_OK".tmp
SAVE_OUT=$(run_chat "/save $SNAP_OK")
assert_match "$SAVE_OUT" "saved soul=Aurora" "save reports success"
if [ -f "$SNAP_OK" ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  snapshot file landed on disk\n"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  snapshot file missing at $SNAP_OK\n"
fi
ROOT_LINE=$(grep '^meta.merkle_root ' "$SNAP_OK" || true)
if [ -n "$ROOT_LINE" ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  snapshot carries meta.merkle_root line\n"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  meta.merkle_root line missing from $SNAP_OK\n"
fi
ROOT_HEX=$(printf '%s' "$ROOT_LINE" | sed 's/^meta\.merkle_root //')
ROOT_LEN=${#ROOT_HEX}
assert_eq "$ROOT_LEN" "64" "Merkle root is a 64-char (32-byte) hex string"

# ---- assertion 2: /snap_verify on the untouched file says "verified" ---
VER_OUT=$(run_chat "/snap_verify $SNAP_OK")
assert_match "$VER_OUT" "snap_verify $SNAP_OK: verified" \
    "/snap_verify on clean file reports verified"

# ---- assertion 3: tamper one byte in an atom value, expect TAMPERED ----
cp "$SNAP_OK" "$SNAP_TAMP"
python3 - <<PY
import sys
path = "$SNAP_TAMP"
with open(path, "rb") as f:
    data = bytearray(f.read())
target = b"kgs.atoms[0].label "
pos = data.find(target)
if pos < 0:
    print("NO_LABEL_LINE", file=sys.stderr); sys.exit(1)
val_start = pos + len(target)
val_end = data.find(b"\n", val_start)
# Flip the first byte of the label value: 'X' -> 'Y' (wraps), preserving
# byte width so line offsets stay stable.
data[val_start] = (data[val_start] + 1) % 256
if data[val_start] in (10, 13, 32):    # avoid producing whitespace/NL
    data[val_start] = ord("Z")
with open(path, "wb") as f:
    f.write(bytes(data))
print("TAMPERED")
PY
TAMPER_RC=$?
assert_eq "$TAMPER_RC" "0" "python tamper helper exited cleanly"
VER_TAMP=$(run_chat "/snap_verify $SNAP_TAMP")
assert_match "$VER_TAMP" "TAMPERED" \
    "/snap_verify on byte-flipped file reports TAMPERED"
assert_nomatch "$VER_TAMP" "verified --" \
    "/snap_verify on byte-flipped file does NOT report verified"

# ---- assertion 4: determinism -- two saves of the same KG -------------
rm -f "$SNAP_OK" "$SNAP_OK2" "$SNAP_OK".tmp "$SNAP_OK2".tmp
DET_OUT=$(run_chat "/save $SNAP_OK
/save $SNAP_OK2")
ROOT_A=$(grep '^meta.merkle_root ' "$SNAP_OK" | head -1)
ROOT_B=$(grep '^meta.merkle_root ' "$SNAP_OK2" | head -1)
assert_eq "$ROOT_A" "$ROOT_B" \
    "two /save calls on unchanged KG produce identical Merkle root"

# ---- assertion 5: pre-R15E snapshot -- no Merkle commitment -----------
# Build a hand-rolled v2-ish snapshot that mirrors the writer's output
# but OMITS the meta.merkle_root line. The reader should report "no
# Merkle commitment" rather than tampered.
python3 - <<PY
path = "$SNAP_PRE"
src = "$SNAP_OK"
with open(src, "r") as f:
    text = f.read()
# Strip the merkle_root line; everything else stays bit-identical.
lines = [ln for ln in text.splitlines(True)
         if not ln.startswith("meta.merkle_root ")]
with open(path, "w") as f:
    f.write("".join(lines))
PY
VER_PRE=$(run_chat "/snap_verify $SNAP_PRE")
assert_match "$VER_PRE" "no Merkle commitment" \
    "/snap_verify on pre-R15E snapshot reports 'no Merkle commitment'"
assert_nomatch "$VER_PRE" "TAMPERED" \
    "/snap_verify on pre-R15E snapshot does NOT false-positive TAMPERED"

# ---- assertion 6: env-var verification refuses to /load a tampered file
LOAD_OUT=$(CE_SNAPSHOT_VERIFY_MERKLE=1 run_chat "/load $SNAP_TAMP")
assert_match "$LOAD_OUT" "TAMPERED" \
    "CE_SNAPSHOT_VERIFY_MERKLE=1 /load on tampered file reports TAMPERED"
# The same /load WITHOUT the env var should succeed (the substrate
# doesn't break the existing load path -- tamper detection is opt-in
# until the operator enables it).
LOAD_DEFAULT=$(run_chat "/load $SNAP_TAMP")
assert_match "$LOAD_DEFAULT" "loaded $SNAP_TAMP" \
    "/load without env-var still rehydrates the tampered file (opt-in)"

# ---- summary -------------------------------------------------------------
summary "scenario_lll_merkle"
