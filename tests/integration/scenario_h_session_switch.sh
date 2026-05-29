#!/usr/bin/env bash
# Scenario H -- /switch in-process tenant isolation.
#
# One chat process, two sessions: the default ("default" / "Aurora") and one
# created via /switch alice. /teach widget in default, /switch alice, /teach
# gadget; switching back to default must still recognize widget (m>=1, unk=0)
# but NOT gadget (gadget was taught only in alice, so it should look unknown
# and trigger an auto-learn for default). Switching back to alice must still
# recognize gadget. The Session struct (ADR-0051) carries soul + KGs + ctx +
# log + engine + mo + hs per tenant, so each /teach lands in only one tenant's
# KG -- this scenario is the per-tenant isolation acceptance test (Phase 18,
# Half A).

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0

it_section "scenario H: /switch in-process tenant isolation"

# Run a single chat: teach widget in default, switch to alice, teach gadget,
# then verify each side's recognition. Each turn emits a "perceive(m=...,unk=...)"
# trailer; we grep for it after each query.
OUT=$(printf '/teach widget
/switch alice
/teach gadget
/switch default
widget
gadget
/switch alice
gadget
widget
/quit
' | "$CHAT" 2>&1)

# 1. The default got widget; alice got gadget. Each /teach line acknowledged.
assert_match "$OUT" "ingested 'widget'" "default session ingested 'widget'"
assert_match "$OUT" "ingested 'gadget'" "alice session ingested 'gadget'"

# 2. /switch alice (which did not exist) was the create+activate path.
assert_match "$OUT" "created and switched to new session 'alice'" \
    "/switch alice created the session"

# 3. /switch default (which exists) was the activate-only path.
assert_match "$OUT" "switched to session 'default' \\(Aurora," \
    "/switch default re-activated the existing default session"

# 4. Order matters. Extract the perceive lines in order; map them to:
#    1st = widget in default        (must be m>=1, unk=0  -- WIDGET KNOWN)
#    2nd = gadget in default        (must be unk=1        -- GADGET NOT KNOWN)
#    3rd = gadget in alice          (must be m>=1, unk=0  -- GADGET KNOWN)
#    4th = widget in alice          (must be unk=1        -- WIDGET NOT KNOWN
#                                    because it was only taught in default;
#                                    alice's KG never saw it)
PERCEIVES=$(echo "$OUT" | grep -oE "perceive\(m=[0-9]+,unk=[0-9]+\)")
P1=$(echo "$PERCEIVES" | sed -n '1p')
P2=$(echo "$PERCEIVES" | sed -n '2p')
P3=$(echo "$PERCEIVES" | sed -n '3p')
P4=$(echo "$PERCEIVES" | sed -n '4p')

assert_match "$P1" "perceive\\(m=[1-9][0-9]*,unk=0\\)" \
    "default knows widget post-switch (m>=1, unk=0)"
assert_match "$P2" "perceive\\(.*,unk=[1-9][0-9]*\\)" \
    "default does NOT know gadget (unk>=1, taught in alice only)"
assert_match "$P3" "perceive\\(m=[1-9][0-9]*,unk=0\\)" \
    "alice knows gadget after switch back (m>=1, unk=0)"
assert_match "$P4" "perceive\\(.*,unk=[1-9][0-9]*\\)" \
    "alice does NOT know widget (unk>=1, taught in default only)"

# 5. /switch with no arg lists sessions; verify the listing format.
OUT2=$(printf '/switch alice
/switch
/quit
' | "$CHAT" 2>&1)
assert_match "$OUT2" "sessions \\(2 total\\):"     "/switch lists 2 sessions after one create"
assert_match "$OUT2" "\\*alice"                    "/switch marks the active session with *"
assert_match "$OUT2" "default"                     "/switch lists the default session"
assert_match "$OUT2" "\"Aurora\""                  "/switch shows default's display name"
assert_match "$OUT2" "\\(\\* = active\\)"          "/switch prints the legend"

# 6. /switch <self> is a no-op-style activate (same session) -- must report
#    the switch line with the existing name and atom count, NOT a "created"
#    line.
OUT3=$(printf '/switch default
/switch default
/quit
' | "$CHAT" 2>&1)
assert_match "$OUT3" "switched to session 'default' \\(Aurora" \
    "/switch <active id> succeeds and reports the active session"
assert_nomatch "$OUT3" "created and switched to new session 'default'" \
    "/switch <existing id> does NOT report 'created'"

# 7. /help must advertise /switch.
OUT4=$(run_chat '/help')
assert_match "$OUT4" "/switch \\[ID\\]" "/help advertises /switch with [ID] usage"

summary "scenario_h_session_switch"
