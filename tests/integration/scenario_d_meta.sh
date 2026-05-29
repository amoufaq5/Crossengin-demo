#!/usr/bin/env bash
# Scenario D -- Meta observer.
#
# /teach widget -> /teach gadget -> /meta -> verify the per-source table shows
# a `user-teach` row with 2 attributed atoms and 100% promotion rate.
# Also verify `seed` row exists.

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0

it_section "scenario D: meta observer per-source table"

OUT=$(run_chat '/teach widget
/teach gadget
/meta')

# Header row appears.
assert_match "$OUT" "source +atoms +tentative +durable +promotion%" "meta header shows expected columns"

# Seed row present.
assert_match "$OUT" "  seed +572" "seed source row appears with 572 atoms"

# user-teach row with 2 atoms, both durable, 100% promotion.
# user-teach atoms ingested by au_ingest with Beta(4,1) get confidence
# 800/1000 -> durable (>= 750). So tentative=0, durable=2, promotion=100.0.
assert_match "$OUT" "  user-teach +2 +0 +2 +100\\.0" "user-teach row: 2 atoms / 0 tentative / 2 durable / 100.0 promotion"

# At least one /meta poll occurred.
assert_match "$OUT" "[1-9][0-9]* poll\\(s\\) total" "/meta increments poll counter"

summary "scenario_d_meta"
