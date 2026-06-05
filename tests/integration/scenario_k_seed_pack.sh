#!/usr/bin/env bash
# Scenario K -- /seed domain seed packs (P1.9).
#
# Boot the chat once, list the available packs, install the medical pack,
# verify KG growth, ask about a medical concept that came in with the pack,
# and confirm /status reflects the new atom count. Also covers the unknown-
# pack error path and the --reset force-install.

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0

# Defensive: prior scenarios in the suite (scenario_a_durability.sh) save a
# snapshot to /tmp/crossengin.snap. If that snapshot lingers and a future
# integration step calls /load, atom counts shift mid-run. We don't /load
# here, so just clean snapshot + dlog up front so we always boot from the
# fresh-seed 572-atom baseline.
rm -f /tmp/crossengin.snap /tmp/crossengin.dlog

it_section "scenario K: /seed domain seed packs"

# Run the chat: list packs, install medical, ask about a medical concept,
# then list again (should now be marked [installed]).
OUT=$(printf '/status
/seed
/seed medical
/status
/seed
/seed medical
/seed --reset medical
/seed bogus
/help
/quit
' | "$CHAT" 2>&1)

# 1. /seed (no arg) listed 3 packs.
assert_match "$OUT" "domain seed packs \\(3 available\\)" \
    "/seed lists 3 available packs"
assert_match "$OUT" "medical \\(~[0-9]+ atoms\\)" \
    "/seed listing shows medical with atom count"
assert_match "$OUT" "ops_runbook \\(~[0-9]+ atoms\\)" \
    "/seed listing shows ops_runbook with atom count"
assert_match "$OUT" "code_review \\(~[0-9]+ atoms\\)" \
    "/seed listing shows code_review with atom count"

# 2. /seed medical installed the pack: line of the form
#    (seed pack 'medical' installed: N atoms + M operators; KG now K atoms)
assert_match "$OUT" "seed pack 'medical' installed: [0-9]+ atoms \\+ [0-9]+ operators; KG now [0-9]+ atoms" \
    "/seed medical installs and reports atom + operator counts"

# 3. After install, /seed (no arg) marks medical as [installed].
assert_match "$OUT" "medical \\(~[0-9]+ atoms\\) \\[installed\\]" \
    "/seed listing marks medical as installed after install"

# 4. Re-install without --reset reports 'already installed'.
assert_match "$OUT" "seed pack 'medical' already installed" \
    "/seed medical second time short-circuits"

# 5. /seed --reset medical re-applies.
RESET_COUNT=$(echo "$OUT" | grep -cE "seed pack 'medical' installed:")
assert_match "$(echo "$RESET_COUNT")" "^2$" \
    "/seed --reset medical re-applies (two install lines total)"

# 6. /seed bogus surfaces a clean error.
assert_match "$OUT" "unknown pack: bogus" \
    "/seed bogus prints unknown-pack error"

# 7. /help advertises /seed.
assert_match "$OUT" "/seed \\[PACK\\]" \
    "/help advertises /seed with [PACK] usage"

# 8. KG growth across /status calls. Extract the two "knowledge: N atoms" lines.
KG_LINES=$(echo "$OUT" | grep -oE "knowledge: [0-9]+ atoms")
KG_BEFORE=$(echo "$KG_LINES" | sed -n '1p' | grep -oE "[0-9]+" | head -1)
KG_AFTER=$(echo "$KG_LINES" | sed -n '2p' | grep -oE "[0-9]+" | head -1)
# After medical install, KG must grow by at least 30 atoms.
if [ -n "$KG_BEFORE" ] && [ -n "$KG_AFTER" ]; then
    DELTA=$((KG_AFTER - KG_BEFORE))
    if [ "$DELTA" -ge 30 ]; then
        PASS=$((PASS+1))
        printf "  ${C_GRN}PASS${C_RST}  /status reflects KG growth (%d -> %d, +%d atoms)\n" \
            "$KG_BEFORE" "$KG_AFTER" "$DELTA"
    else
        FAIL=$((FAIL+1))
        printf "  ${C_RED}FAIL${C_RST}  /status KG growth too small (%d -> %d, +%d atoms; expected >= 30)\n" \
            "$KG_BEFORE" "$KG_AFTER" "$DELTA"
    fi
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  could not extract KG counts from /status output\n"
fi

# 9. After /seed medical, send the agent a medical-flavoured input that the
#    PACK (not the foundational seed) made known. The pack adds 'antibiotic'
#    so the perceive(m=...) line must show a match for it. Done in a separate
#    chat invocation so we know the trailing perceive corresponds to the
#    pack's word.
OUT2=$(printf '/seed medical
antibiotic
/quit
' | "$CHAT" 2>&1)
PERCEIVES=$(echo "$OUT2" | grep -oE "perceive\(m=[0-9]+,unk=[0-9]+\)")
P1=$(echo "$PERCEIVES" | sed -n '1p')
assert_match "$P1" "perceive\\(m=[1-9][0-9]*,unk=0\\)" \
    "agent recognises a pack-only word ('antibiotic') after /seed medical"

summary "scenario_k_seed_pack"
