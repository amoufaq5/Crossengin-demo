#!/usr/bin/env bash
# Scenario LL -- KG atom schema-evolution end-to-end.
#
# Hand-rolls a V2-shape snapshot whose meta block LACKS the
# `schema.atoms_version` line (the pre-R8E shape, treated as implicit
# atom schema v1). Runs the schema-migration driver
# (examples/migrate_schema.nova) to upgrade every atom to v3, then
# verifies:
#
#   * the output file exists and is well-formed
#   * the output declares `schema.atoms_version 3` on the wire
#   * the migration's report line names old-v -> new-v explicitly
#   * a second run of the driver is a no-op (idempotent: already v3)
#
# The wire-format (v2) is untouched: R5D's container migration
# (`snap_migrate_v1_to_v2`) is a different layer and is exercised by
# scenario_dd_snap_migrate.sh. This scenario exists to prove the
# ATOM SHAPE migration layer (R8E).

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

OLD_PATH="/tmp/ce_int_scenario_ll_v1.snap"
NEW_PATH="/tmp/ce_int_scenario_ll_v3.snap"
RE_PATH="/tmp/ce_int_scenario_ll_v3_again.snap"
trap 'rm -f "$OLD_PATH" "$NEW_PATH" "$RE_PATH" "$NEW_PATH.tmp" "$RE_PATH.tmp"' EXIT
rm -f "$OLD_PATH" "$NEW_PATH" "$RE_PATH" "$NEW_PATH.tmp" "$RE_PATH.tmp"

it_section "scenario LL: KG atom schema-evolution"

# --- step 1: hand-roll a pre-R8E v2 snapshot (no schema.atoms_version) ----
# The file declares ver 2 on the wire and a v2 meta block, but lacks the
# `schema.atoms_version` line -- exactly what a snapshot written by a
# pre-R8E daemon looks like. The atom payloads are correspondingly the
# implicit v1 shape (no `created_ns` payload, FACT atoms with a `label`
# payload that hasn't been renamed to `display_label` yet).
cat >"$OLD_PATH" <<'V2_EOF'
crossengin-snapshot v1
tag 5361
ver 2
instance 7
timestamp 1700000000
sections 5
meta.creator crossengin/0.1.0
meta.created_ns 1700000000000000000
meta.compaction_threshold -1
meta.encryption none
soul.present 0
kgs.present 1
kgs.atoms 2
kgs.atoms.count 2
kgs.atoms[0].kg reasoning
kgs.atoms[0].id 0
kgs.atoms[0].kind 1
kgs.atoms[0].label legacy_fact
kgs.atoms[0].alpha 1000
kgs.atoms[0].beta 1000
kgs.atoms[1].kg reasoning
kgs.atoms[1].id 1
kgs.atoms[1].kind 3
kgs.atoms[1].label legacy_concept
kgs.atoms[1].alpha 1000
kgs.atoms[1].beta 1000
episodic.present 0
synapses.present 0
selfmodel.present 0
end
V2_EOF

assert_file_exists "$OLD_PATH" "hand-rolled v2 snapshot exists"

# Sanity: the v2 file declares `ver 2` and has NO schema.atoms_version line.
if grep -q '^ver 2$' "$OLD_PATH"; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  %s\n" "v2 snapshot declares 'ver 2'"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  %s\n" "v2 snapshot does not declare ver 2"
fi

if grep -q '^schema\.atoms_version' "$OLD_PATH"; then
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  %s\n" "pre-R8E file unexpectedly has schema.atoms_version"
else
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  %s\n" "pre-R8E file has no schema.atoms_version (as expected)"
fi

# --- step 2: run the schema-migration driver -----------------------------
NOVA_ROOT="${NOVA_ROOT:-$HOME/NOVA}"
NOVA="$NOVA_ROOT/nova"

if [ ! -x "$NOVA" ]; then
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  %s\n" "NOVA launcher not found at $NOVA; set NOVA_ROOT"
    summary "scenario_ll_schema_migrate"
fi

cd "$REPO_ROOT" || exit 1
OUT=$(CE_MIGRATE_OLD="$OLD_PATH" CE_MIGRATE_NEW="$NEW_PATH" \
    "$NOVA" run examples/migrate_schema.nova 2>&1 | grep -v '^Compiled:')
RC=$?

assert_eq "$RC" "0" "migrate_schema driver exits 0"

# The report line names both endpoints.
assert_match "$OUT" "migrated atoms v1 -> v3" "driver reports v1 -> v3 schema migration"
assert_match "$OUT" "[0-9]+ atoms across [0-9]+ KGs" "driver reports atom + KG counts"

# --- step 3: verify the migrated output ----------------------------------
assert_file_exists "$NEW_PATH" "migrated snapshot exists"

# The output MUST declare schema.atoms_version 3.
if grep -q '^schema\.atoms_version 3$' "$NEW_PATH"; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  %s\n" "v3-schema snapshot declares 'schema.atoms_version 3'"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  %s\n" "migrated snapshot is missing 'schema.atoms_version 3'"
fi

# The wire format must stay at v2 -- the schema layer is orthogonal.
if grep -q '^ver 2$' "$NEW_PATH"; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  %s\n" "migrated snapshot still declares wire 'ver 2'"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  %s\n" "migrated snapshot lost wire 'ver 2'"
fi

# The atom payloads survive (kg label, atom label, alpha, beta).
NEW_TEXT="$(cat "$NEW_PATH" 2>/dev/null)"
assert_match "$NEW_TEXT" "^kgs\\.atoms\\[0\\]\\.kg reasoning$"     "atom[0] kg label survives"
assert_match "$NEW_TEXT" "^kgs\\.atoms\\[0\\]\\.label legacy_fact$" "atom[0] label survives (wire side)"
assert_match "$NEW_TEXT" "^kgs\\.atoms\\[1\\]\\.label legacy_concept$" "atom[1] label survives (wire side)"
assert_match "$NEW_TEXT" "^kgs\\.atoms\\.count 2$"                  "atom count survives"

# --- step 4: idempotency -------------------------------------------------
# Run the driver AGAIN on the already-migrated file; the report must
# show v3 -> v3 (no migration steps applied) and the bytes must be
# identical (modulo the byte-count line).
OUT2=$(CE_MIGRATE_OLD="$NEW_PATH" CE_MIGRATE_NEW="$RE_PATH" \
    "$NOVA" run examples/migrate_schema.nova 2>&1 | grep -v '^Compiled:')
RC2=$?

assert_eq "$RC2" "0" "second run exits 0"
assert_match "$OUT2" "migrated atoms v3 -> v3" "driver reports v3 -> v3 (already current)"

# The re-saved file's atoms_version is still 3.
if grep -q '^schema\.atoms_version 3$' "$RE_PATH"; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  %s\n" "re-saved file remains at schema v3"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  %s\n" "re-saved file lost schema.atoms_version 3"
fi

# Well-formed output.
assert_match "$NEW_TEXT" "^end$" "migrated file ends with 'end'"

summary "scenario_ll_schema_migrate"
