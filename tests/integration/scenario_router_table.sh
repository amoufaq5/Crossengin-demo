#!/usr/bin/env bash
# Scenario router-table -- B1 (audit C12).
#   The chat's cognitive router keeps its own synapse table, separate from
#   the reasoning part's pool graph.
#   1. /save writes router edges as a "router" entry, never as the
#      reasoning part / legacy block.
#   2. A fresh process restores them (/synapse shows the learned weight).
#   3. A pre-B1 snapshot (router edges stored as the reasoning part) is
#      migrated into the router table on /load.
#   4. Phase 0 counters are unchanged by the split.

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0
it_section "scenario router-table: router edges live in their own table"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export CE_RUN_DIR="$WORK/run"
mkdir -m 700 -p "$CE_RUN_DIR"
grant_caps delete

# 1. learn + save
OUT=$( (for i in 1 2 3; do echo fever; echo /good; done
        echo /__learning__
        echo "/save $WORK/a.snap"; echo /quit) | timeout 120 "$CHAT" 2>&1 | tr -d '\r')
assert_match "$OUT" "synapse_live=10$" "router grew 10 edges"
assert_match "$OUT" "^synapse_mean_weight=90$" "3 legs x 300 over 10 edges = 90"
assert_eq "$(grep -c '^synapses.parts\[[0-9]*\].label router$' "$WORK/a.snap")" "1" "snapshot has one router entry"
assert_eq "$(grep -c '^synapses.parts\[[0-9]*\].label reasoning$' "$WORK/a.snap")" "0" "no reasoning-part entry (pool graph empty)"
assert_eq "$(grep '^synapses.count ' "$WORK/a.snap")" "synapses.count 0" "router edges not mirrored into the legacy block"

# 2. fresh process restores the router table
OUT=$(printf '/load %s\n/synapse fever\n/__learning__\n/quit\n' "$WORK/a.snap" | timeout 120 "$CHAT" 2>&1 | tr -d '\r')
assert_match "$OUT" "synapses: 3 edge\(s\) restored \(parts: 0, router: 3, dropped: 0;" "3 router edges restored"
assert_match "$OUT" "[-]> headache \(node [0-9]+\) weight=300" "fever->headache weight survives"
assert_match "$OUT" "synapse_live=3$" "router table holds the 3 restored edges"

# 3. legacy (pre-B1) layout: the same edges stored as the reasoning part and
#    mirrored into the legacy block, exactly as the old builder wrote them.
python3 - "$WORK/a.snap" "$WORK/legacy.snap" <<'EOF'
import re, sys
src, dst = sys.argv[1], sys.argv[2]
lines = open(src).read().split('\n')
recs = {}
for l in lines:
    m = re.match(r'^synapses\.parts\[0\]\.synapses\[(\d+)\]\.(\w+) (.*)$', l)
    if m:
        recs.setdefault(int(m.group(1)), {})[m.group(2)] = m.group(3)
out = []
for l in lines:
    if l == 'synapses.parts[0].label router':
        out.append('synapses.parts[0].label reasoning')
    elif l.startswith('synapses.count '):
        out.append('synapses.count %d' % len(recs))
        for i in sorted(recs):
            for k in ('src', 'dst', 'weight', 'eligibility'):
                out.append('synapses[%d].%s %s' % (i, k, recs[i][k]))
    else:
        out.append(l)
open(dst, 'w').write('\n'.join(out))
EOF
OUT=$(printf '/load %s\n/synapse fever\n/__learning__\n/quit\n' "$WORK/legacy.snap" | timeout 120 "$CHAT" 2>&1 | tr -d '\r')
assert_match "$OUT" "restored \(parts: 0, router: 3, dropped: 0, migrated from pre-router snapshot;" "legacy reasoning edges migrated to the router table only"
assert_match "$OUT" "[-]> headache \(node [0-9]+\) weight=300" "migrated weight readable by the router"
assert_nomatch "$OUT" "unknown part" "no unknown-part warning"
# re-save after the legacy load: nothing may have landed in the pool graph
printf '/load %s\n/save %s\n/quit\n' "$WORK/legacy.snap" "$WORK/resaved.snap" | timeout 120 "$CHAT" >/dev/null 2>&1
assert_eq "$(grep -c '^synapses.parts\[[0-9]*\].label reasoning$' "$WORK/resaved.snap")" "0" "legacy edges not in the reasoning pool graph after re-save"
assert_eq "$(grep -c '^synapses.parts\[[0-9]*\].label router$' "$WORK/resaved.snap")" "1" "re-save writes them as the router entry"
assert_eq "$(grep '^synapses.count ' "$WORK/resaved.snap")" "synapses.count 0" "re-save legacy block empty"

# 3b. per-session tables: a /switch tenant starts with an empty router table
#     and does not disturb the default session's table.
OUT=$( (for i in 1 2 3; do echo fever; echo /good; done
        echo "/switch alice"; echo /__learning__
        echo "/switch default"; echo /__learning__; echo /quit) | timeout 120 "$CHAT" 2>&1 | tr -d '\r')
assert_eq "$(grep -oE 'synapse_live=[0-9]+' <<<"$OUT" | tr '\n' ' ')" "synapse_live=0 synapse_live=10 " "alice's table empty, default's intact"
# a query another session answered first must still grow + reinforce edges
# in this session's table (the moment cache is per session too)
OUT=$( (echo fever; echo "/switch alice"; echo fever; echo /good; echo /good; echo /__learning__; echo /quit) \
       | timeout 120 "$CHAT" 2>&1 | tr -d '\r')
assert_match "$OUT" "synapse_live=10$" "alice grows her own router edges for a query default answered"
assert_match "$OUT" "^synapse_mean_weight=60$" "alice's /good reinforces her table (3 legs x 200 / 10)"
assert_match "$OUT" "^mc_hits=0$" "alice's moment cache is her own (no hit from default's entry)"

# 4. Phase 0 counters (same run as CI's fever smoke)
OUT=$( (for i in $(seq 1 10); do echo fever; echo /good; done; echo /__learning__; echo /quit) \
       | timeout 120 "$CHAT" 2>&1 | tr -d '\r')
assert_match "$OUT" "^synapse_mean_weight=300$" "Phase 0 synapse_mean_weight=300"
assert_match "$OUT" "^mc_hits=9$" "Phase 0 mc_hits=9"

summary "scenario_router_table"
