#!/usr/bin/env bash
# Scenario MM -- episodic memory retrieval / /recall chat command (R8F).
#
# Read-side companion to scenario_ff_episodic.sh. R6F shipped the WRITE
# side (consolidation cycle + snapshot persistence); R8F adds the READ
# side (the six retrieval functions + the /recall chat command). This
# scenario drives the substrate through a known two-cluster observation
# sequence, runs consolidation, and exercises every /recall subcommand
# via the same `episodic_recall_cmd` dispatcher the chat binary routes
# to. The shell asserts on the formatted RECALL stdout lines.
#
# Fixture: 5x (1,2,3) at ts 0/10/20/30/40 then 5x (4,5,6) at ts
# 200/210/220/230/240 -- the two clusters consolidate independently
# (the temporal gap exceeds EPISODIC_COOCCUR_WINDOW=10 ticks per ADR-0037,
# so they cannot fuse). After consolidation: episode id=0 is the newer
# {4,5,6} cluster (the scan walks newest-first), episode id=1 is the
# older {1,2,3} cluster.

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

NOVA_ROOT="${NOVA_ROOT:-$HOME/NOVA}"
NOVA="$NOVA_ROOT/nova"
DEMO_DRIVER="$REPO_ROOT/examples/episodic_recall_demo.nova"

it_section "scenario MM: episodic memory retrieval API + /recall command"

# --- guard: NOVA toolchain available ---
if [ ! -x "$NOVA" ]; then
    FAIL=$((FAIL+1))
    echo "FAIL: NOVA launcher not found at '$NOVA'"
    summary "scenario_mm_episodic_recall"
    exit 1
fi

assert_file_exists "$DEMO_DRIVER" "demo driver source exists"

# --- step 1: run the recall driver end-to-end ---------------------------
OUT="$("$NOVA" run "$DEMO_DRIVER" 2>&1)"
RC=$?
echo "$OUT" | sed 's/^/    /'

assert_eq "$RC" "0" "demo driver exits 0"

# --- step 2: confirm consolidation produced two clusters ----------------
DRIVER_MOMENTS="$(echo "$OUT" | grep -E '^DRIVER moments=' | head -1 | cut -d= -f2)"
DRIVER_MINTED="$(echo "$OUT" | grep -E '^DRIVER minted=' | head -1 | cut -d= -f2)"
DRIVER_STORE="$(echo "$OUT" | grep -E '^DRIVER store_size=' | head -1 | cut -d= -f2)"

assert_eq "$DRIVER_MOMENTS" "10" "10 moments captured (5 + 5 triplets)"
assert_eq "$DRIVER_MINTED"  "2"  "consolidation mints exactly 2 episodic atoms"
assert_eq "$DRIVER_STORE"   "2"  "transient store carries 2 atoms"

# --- step 3: /recall member 1 -> the {1,2,3} cluster --------------------
assert_match "$OUT" "^RECALL member=1 matched=1$"            "/recall member 1 reports 1 hit"
assert_match "$OUT" "^EPISODE id=1 members=\\{1,2,3\\} count=5 first_ns=0 last_ns=40 " \
    "/recall member 1 returns the {1,2,3} episode (id=1)"
assert_match "$OUT" "^RECALL_END member=1$"                  "/recall member 1 emits END marker"

# --- step 4: /recall member 4 -> the {4,5,6} cluster --------------------
assert_match "$OUT" "^RECALL member=4 matched=1$"            "/recall member 4 reports 1 hit"
assert_match "$OUT" "^EPISODE id=0 members=\\{4,5,6\\} count=5 first_ns=200 last_ns=240 " \
    "/recall member 4 returns the {4,5,6} episode (id=0)"

# --- step 5: /recall member 99 -> empty result --------------------------
assert_match "$OUT" "^RECALL member=99 matched=0$"           "/recall member 99 reports 0 hits"

# --- step 6: /recall window 0 50 -> the older cluster only --------------
assert_match "$OUT" "^RECALL window=0\\.\\.50 matched=1$"    "/recall window [0,50] -> 1 hit"

# --- step 7: /recall window 100 200 -> the newer cluster only -----------
# The newer cluster's span [200,240] touches the window upper bound 200
# (inclusive overlap), so it admits the {4,5,6} episode and rejects the
# older {1,2,3} span [0,40] which falls fully below 100.
assert_match "$OUT" "^RECALL window=100\\.\\.200 matched=1$" "/recall window [100,200] -> 1 hit"

# --- step 8: /recall window 0 1000 -> both, ordered by recency desc -----
assert_match "$OUT" "^RECALL window=0\\.\\.1000 matched=2$"  "/recall window [0,1000] -> 2 hits"

# --- step 9: /recall top -> top-belief, tiebreak by recency desc --------
# Both episodes start at the uniform prior (alpha = beta = BEL_PRIOR), so
# confidence ties at 500. The composite key falls through to last_seen
# desc -- the newer {4,5,6} (id=0, last_seen=240) wins.
assert_match "$OUT" "^RECALL top_belief matched=2$"          "/recall top reports 2 hits"

# --- step 10: /recall recent -> the newer cluster leads -----------------
assert_match "$OUT" "^RECALL most_recent matched=2$"         "/recall recent reports 2 hits"

# --- step 11: empty arg prints a usage line + store_size ----------------
assert_match "$OUT" "^usage: /recall \\{member <id> \\| window <start> <end> \\| top \\| recent\\}$" \
    "empty /recall prints a usage line"
assert_match "$OUT" "^RECALL store_size=2$"                  "usage line includes store_size"

# --- step 12: unknown subcommand prints diagnostic ----------------------
assert_match "$OUT" "^\\(unknown /recall subcommand: bogus -- try member\\|window\\|top\\|recent\\)$" \
    "unknown subcommand prints diagnostic"

summary "scenario_mm_episodic_recall"
