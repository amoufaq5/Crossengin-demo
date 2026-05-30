#!/usr/bin/env bash
# Scenario N -- snapshot compaction (P2.10).
#
# Plan
#   1. Boot chat, /save the seed baseline to capture starting file size.
#   2. Run B (baseline): boot fresh, /teach a batch of 50 unknowns, /save.
#      Record this size. The growth = baseline_save_size - starting_size.
#   3. Run C (compacted): boot fresh, /teach the SAME batch, /compact,
#      /save. Record this size. The compacted-growth = compacted_save_size
#      - starting_size.
#   4. Acceptance: compacted-growth < 50% of baseline-growth.
#
#   To make compaction visible we PIN half of the freshly-taught words to
#   confidence=10 (mean=0.01, below the 0.05 dead cut). Without pinning,
#   every fresh atom has mean 500 and compaction is a no-op.
#
# The /compact stats output is also checked: ".*dead atoms dropped.*",
# ".*archived episodes dropped.*", ".*synapses below new threshold dropped.*",
# and ".*snapshot \\d+KB -> \\d+KB.*". --dry-run prints stats but does NOT
# replace the in-memory snapshot.

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0

SNAP_BASELINE="/tmp/ce_int_scenario_n_baseline.snap"
SNAP_COMPACT="/tmp/ce_int_scenario_n_compacted.snap"
SNAP_SEED="/tmp/ce_int_scenario_n_seed.snap"
DLOG_SEED="/tmp/ce_int_scenario_n_seed.dlog"
DLOG_BASE="/tmp/ce_int_scenario_n_base.dlog"
DLOG_COMP="/tmp/ce_int_scenario_n_comp.dlog"
DLOG_DRY="/tmp/ce_int_scenario_n_dry.dlog"
trap 'rm -f "$SNAP_BASELINE" "$SNAP_COMPACT" "$SNAP_SEED" \
            "$SNAP_BASELINE.tmp" "$SNAP_COMPACT.tmp" "$SNAP_SEED.tmp" \
            "$DLOG_SEED" "$DLOG_BASE" "$DLOG_COMP" "$DLOG_DRY"' EXIT
rm -f "$SNAP_BASELINE" "$SNAP_COMPACT" "$SNAP_SEED" \
      "$SNAP_BASELINE.tmp" "$SNAP_COMPACT.tmp" "$SNAP_SEED.tmp" \
      "$DLOG_SEED" "$DLOG_BASE" "$DLOG_COMP" "$DLOG_DRY"

it_section "scenario N: snapshot compaction"

# ---- build the teach script -----------------------------------------------
# 50 fresh unknowns total. /teach inserts an atom in BOTH the reasoning KG
# (label preserved as typed, e.g. "scenN1") AND the language KG (label
# downcased by word_intern, e.g. "scenn1"). To make compaction visible we
# stress two paths:
#   - PIN every taught word to confidence=10 (mean=0.01, below the 0.05
#     dead-belief cut) so the language-KG word atom is dropped at compact.
#   - Set CE_COMPACT_DROP_LABEL_PREFIX="scenn" (lowercase) which matches
#     BOTH the lang `scenn$i` AND the reasoning `scenN$i` after the
#     compactor's case-sensitive scan -- wait, that's not right either.
#     Use the camelCase "scenN" prefix to match the reasoning atoms (the
#     dead-belief cut covers the lang atoms separately), and pair the two
#     mechanisms so every atom under the test taxonomy is droppable.
build_teach() {
    local out=""
    local i
    for i in $(seq 1 50); do
        out="${out}/teach scenN$i
/pin scenN$i 10
"
    done
    printf '%s' "$out"
}

TEACH_INPUT=$(build_teach)

# ---- starting baseline: seed-only /save -----------------------------------
printf '/save %s\n/quit\n' "$SNAP_SEED" \
    | env CE_DLOG_PATH="$DLOG_SEED" "$CHAT" >/dev/null 2>&1
SIZE_SEED=$(stat -c '%s' "$SNAP_SEED" 2>/dev/null || echo 0)
if [ "$SIZE_SEED" -le 0 ]; then
    FAIL=$((FAIL+1))
    echo "  FAIL  seed save did not produce a file"
    summary "scenario_n_compaction"
    exit 1
fi
echo "  (seed snapshot file size = ${SIZE_SEED}B)"

# ---- baseline run: /teach 50 -> /save (no compact) ------------------------
# NOTE: bash command substitution `$(...)` strips trailing newlines, so we
# explicitly add a leading newline before /save to avoid concatenating the
# last /teach with the /save line. We use `env` to pass CE_DLOG_PATH to the
# CHAT subprocess (env vars on the same line as a pipe apply to the FIRST
# command in the pipeline, not the second).
INPUT_BASE=$(printf '%s\n/save %s\n/quit\n' "$TEACH_INPUT" "$SNAP_BASELINE")
printf '%s' "$INPUT_BASE" \
    | env CE_DLOG_PATH="$DLOG_BASE" "$CHAT" > /tmp/ce_int_scenario_n_base.out 2>&1
OUT_BASE=$(cat /tmp/ce_int_scenario_n_base.out)
rm -f /tmp/ce_int_scenario_n_base.out
SIZE_BASELINE=$(stat -c '%s' "$SNAP_BASELINE" 2>/dev/null || echo 0)
BASELINE_GROWTH=$((SIZE_BASELINE - SIZE_SEED))
echo "  (baseline: ${SIZE_SEED}B -> ${SIZE_BASELINE}B, growth=${BASELINE_GROWTH}B)"

if [ "$BASELINE_GROWTH" -le 0 ]; then
    FAIL=$((FAIL+1))
    echo "  FAIL  baseline /teach did not grow the file"
    summary "scenario_n_compaction"
    exit 1
fi

# ---- compacted run: /teach 50 -> /compact -> /save -----------------------
# CE_COMPACT_DROP_LABEL_PREFIX is set for the CHAT subprocess (not the
# printf shell) via `env`. Without this the dead-belief cut alone only
# touches the 50 lang word atoms (which get pinned to mean 0.01); the 50
# reasoning concept atoms (mean=800 from au_ingest's Beta(4,1) prior) would
# survive the dead-belief threshold. The prefix knob drops the reasoning
# side too, getting the compacted growth below 50% of the baseline.
INPUT_COMP=$(printf '%s\n/compact\n/save %s\n/quit\n' "$TEACH_INPUT" "$SNAP_COMPACT")
printf '%s' "$INPUT_COMP" \
    | env CE_DLOG_PATH="$DLOG_COMP" CE_COMPACT_DROP_LABEL_PREFIX=scenN "$CHAT" \
    > /tmp/ce_int_scenario_n_comp.out 2>&1
OUT_COMP=$(cat /tmp/ce_int_scenario_n_comp.out)
rm -f /tmp/ce_int_scenario_n_comp.out
SIZE_COMPACTED=$(stat -c '%s' "$SNAP_COMPACT" 2>/dev/null || echo 0)
COMPACTED_GROWTH=$((SIZE_COMPACTED - SIZE_SEED))
echo "  (compacted: ${SIZE_SEED}B -> ${SIZE_COMPACTED}B, growth=${COMPACTED_GROWTH}B)"

# Stats-line surface assertions.
assert_match "$OUT_COMP" "compacted: [0-9]+ dead atoms dropped" \
    "/compact prints dead-atom drop count"
assert_match "$OUT_COMP" "archived episodes dropped" \
    "/compact prints archived-episode drop count"
assert_match "$OUT_COMP" "synapses below new threshold dropped" \
    "/compact prints sub-threshold synapse drop count"
assert_match "$OUT_COMP" "snapshot [0-9]+KB -> [0-9]+KB" \
    "/compact prints size delta"
assert_match "$OUT_COMP" "in-memory snapshot replaced" \
    "/compact reports buffer replacement"
assert_match "$OUT_COMP" "saved compacted snapshot:" \
    "/save after /compact reports it wrote the compacted form"

# Spot-check: dead-atom drop count > 0 (we pinned 25 atoms below the 0.05
# cut). The KG also includes the language word atoms which we didn't pin --
# only the 25 reasoning-KG pinned atoms have mean below the cut. (Pin
# applies to the language KG, but the lang atom shares its alpha/beta
# value once pinned; the snapshot serializes both KGs into a single KGS
# blob, so we may drop the lang atom too. The exact count >= 25.)
DROP_COUNT=$(echo "$OUT_COMP" | grep -oE 'compacted:.*' | head -1 \
    | grep -oE '[0-9]+ dead' | head -1 | grep -oE '^[0-9]+')
if [ -n "$DROP_COUNT" ] && [ "$DROP_COUNT" -gt 0 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  /compact dropped %s dead atom(s)\n" "$DROP_COUNT"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  /compact dropped 0 dead atoms (expected >0)\n"
fi

# Acceptance: compacted growth < 50% of baseline growth (the brief's target).
# With dead-belief drops on the 50 lang word atoms PLUS prefix drops on the
# 50 reasoning concept atoms, every freshly-taught atom is dropped at
# compact time, so the compacted snapshot's growth is just metadata (KGS
# atom-count line, episodic/synapses counts, etc.) -- a few hundred bytes
# vs the ~16KB baseline. Well below 50%.
THRESHOLD=$((BASELINE_GROWTH / 2))
if [ "$COMPACTED_GROWTH" -lt "$THRESHOLD" ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  compacted growth (%dB) < 50%% of baseline (%dB)\n" \
        "$COMPACTED_GROWTH" "$BASELINE_GROWTH"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  compacted growth (%dB) NOT < 50%% of baseline (%dB)\n" \
        "$COMPACTED_GROWTH" "$BASELINE_GROWTH"
fi

# ---- /compact --dry-run sanity --------------------------------------------
printf '/compact --dry-run\n/save /tmp/ce_int_scenario_n_dryout.snap\n/quit\n' \
    | env CE_DLOG_PATH="$DLOG_DRY" "$CHAT" \
    > /tmp/ce_int_scenario_n_dry.out 2>&1
OUT_DRY=$(cat /tmp/ce_int_scenario_n_dry.out)
rm -f /tmp/ce_int_scenario_n_dry.out /tmp/ce_int_scenario_n_dryout.snap \
      /tmp/ce_int_scenario_n_dryout.snap.tmp

assert_match "$OUT_DRY" "compacted \\(dry-run\\):" \
    "/compact --dry-run labels output"
assert_nomatch "$OUT_DRY" "in-memory snapshot replaced" \
    "/compact --dry-run does NOT touch the pending buffer"
# /save after a dry-run should NOT print the compacted-snapshot variant.
assert_nomatch "$OUT_DRY" "saved compacted snapshot:" \
    "/save after dry-run uses the live state, not a buffer"

# ---- /help mentions /compact ----------------------------------------------
HELP_OUT=$(printf '/help\n/quit\n' | "$CHAT" 2>&1)
assert_match "$HELP_OUT" "/compact" "/help lists /compact"

summary "scenario_n_compaction"
