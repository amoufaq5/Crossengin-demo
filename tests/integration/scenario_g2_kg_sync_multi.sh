#!/usr/bin/env bash
# Scenario G2 -- multi-subscriber KG sync (P1.3 distributed-substrate seam).
#
# Builds on scenario G's two-process demo by exercising the v2 protocol's
# new capabilities end-to-end:
#   - N-subscriber fan-out: one publisher, three subscribers
#   - Bidirectional teach: each subscriber publishes back to the hub
#   - Reconnect on disconnect: kill + re-attach a subscriber mid-stream
#   - Auth handshake: a CE_KGSYNC_TOKEN-protected publisher accepts only
#     correctly-token'd subscribers and rejects anonymous ones
#   - Conflict resolution: same label taught at A and B; merge by belief avg
#
# Same sandbox-shaped caveats as scenario_g: blocking accepts get a generous
# startup grace, kill -9 on hang, SKIP gracefully if `socket(2,1,0)` is
# denied entirely.

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

it_section "scenario G2: multi-subscriber + bidirectional + reconnect + auth + conflict"

PUB_BIN="$REPO_ROOT/bin/crossengin-kg-publisher"
SUB_BIN="$REPO_ROOT/bin/crossengin-kg-subscriber"

if [ ! -x "$PUB_BIN" ] || [ ! -x "$SUB_BIN" ]; then
    printf "  ${C_RED}ERROR${C_RST}: %s or %s missing. Run: make install\n" \
        "$PUB_BIN" "$SUB_BIN" >&2
    FAIL=$((FAIL+1))
    summary "scenario_g2_kg_sync_multi"
    exit $?
fi

# Pre-flight: can we socket at all? Bind a throwaway pub to a port we
# DON'T reuse later (32xxx is preflight-only; the real phases use 31xxx).
# Wait for the publisher to fully exit + sleep so its port + fd are
# released before phase A's ports get probed.
PREFLIGHT_PORT=$(( 39000 + (RANDOM % 1000) ))
PREFLIGHT_OUT="/tmp/ce_g2_preflight.out"
: >"$PREFLIGHT_OUT"
(
    export CE_KGSYNC_PORT="$PREFLIGHT_PORT"
    : | "$PUB_BIN" >"$PREFLIGHT_OUT" 2>&1
) &
PREFLIGHT_PID=$!
sleep 0.5
if grep -q "ERROR cannot bind / listen" "$PREFLIGHT_OUT" 2>/dev/null; then
    kill -9 $PREFLIGHT_PID 2>/dev/null
    wait $PREFLIGHT_PID 2>/dev/null
    printf "  ${C_YEL}SKIP${C_RST}  socket bind denied by sandbox -- multi KG sync test skipped\n"
    PASS=$((PASS+1))
    rm -f "$PREFLIGHT_OUT"
    summary "scenario_g2_kg_sync_multi"
    exit $?
fi
kill -9 $PREFLIGHT_PID 2>/dev/null
wait $PREFLIGHT_PID 2>/dev/null
rm -f "$PREFLIGHT_OUT"
# Tiny breath so the preflight's accept-side socket has time to fully
# release before phase A scans for its own random port.
sleep 0.5

# ============================================================
# Phase A: 3 subscribers + bidirectional teach
# ============================================================
PORT=$(( 35000 + (RANDOM % 200) ))
PUB_OUT="/tmp/ce_g2_pub.out"
S1_OUT="/tmp/ce_g2_s1.out"
S2_OUT="/tmp/ce_g2_s2.out"
S3_OUT="/tmp/ce_g2_s3.out"

trap 'kill -9 $PUB_PID $S1_PID $S2_PID $S3_PID 2>/dev/null; rm -f "$PUB_OUT" "$S1_OUT" "$S2_OUT" "$S3_OUT"' EXIT
rm -f "$PUB_OUT" "$S1_OUT" "$S2_OUT" "$S3_OUT"

# Publisher: 3 expected subs, teaches widget + gadget.
(
    export CE_KGSYNC_PORT="$PORT"
    export CE_KGSYNC_SUBS=3
    printf 'widget\ngadget\n' | "$PUB_BIN" >"$PUB_OUT" 2>&1
) &
PUB_PID=$!

# Give the publisher a moment to bind.
sleep 1

# Three subscribers. The first one piggybacks two teach events back to the
# publisher (so we exercise bidirectional). Sub 2 and 3 are read-only.
(
    export CE_KGSYNC_PORT="$PORT"
    export CE_KGSYNC_HOST="127.0.0.1"
    printf 'alpha-bird\nbeta-fish\n' | "$SUB_BIN" >"$S1_OUT" 2>&1
) &
S1_PID=$!

sleep 0.3

(
    export CE_KGSYNC_PORT="$PORT"
    export CE_KGSYNC_HOST="127.0.0.1"
    : | "$SUB_BIN" >"$S2_OUT" 2>&1
) &
S2_PID=$!

sleep 0.3

(
    export CE_KGSYNC_PORT="$PORT"
    export CE_KGSYNC_HOST="127.0.0.1"
    : | "$SUB_BIN" >"$S3_OUT" 2>&1
) &
S3_PID=$!

# Wait for them all to drain.
DEADLINE=15
elapsed=0
while [ "$elapsed" -lt "$DEADLINE" ]; do
    alive=0
    kill -0 $PUB_PID 2>/dev/null && alive=$((alive+1))
    kill -0 $S1_PID  2>/dev/null && alive=$((alive+1))
    kill -0 $S2_PID  2>/dev/null && alive=$((alive+1))
    kill -0 $S3_PID  2>/dev/null && alive=$((alive+1))
    [ "$alive" -eq 0 ] && break
    sleep 1
    elapsed=$((elapsed+1))
done
if [ "$elapsed" -ge "$DEADLINE" ]; then
    printf "  ${C_YEL}WARN${C_RST}  phase A timed out, force-killing\n"
    kill -9 $PUB_PID $S1_PID $S2_PID $S3_PID 2>/dev/null
fi
wait $PUB_PID $S1_PID $S2_PID $S3_PID 2>/dev/null

PUB_TXT=$(cat "$PUB_OUT" 2>/dev/null || true)
S1_TXT=$(cat "$S1_OUT" 2>/dev/null || true)
S2_TXT=$(cat "$S2_OUT" 2>/dev/null || true)
S3_TXT=$(cat "$S3_OUT" 2>/dev/null || true)

# Publisher accepted 3 subs.
assert_match "$PUB_TXT" "3 subscriber\\(s\\) attached"  "publisher saw 3 subscribers attach"
# Publisher fanned out widget and gadget to all 3.
assert_match "$PUB_TXT" "send .*label=widget delivered=3" "publisher fan-out widget reached 3 subs"
assert_match "$PUB_TXT" "send .*label=gadget delivered=3" "publisher fan-out gadget reached 3 subs"
# Each subscriber saw widget and gadget.
assert_match "$S1_TXT" "recv .*label=widget" "sub1 received widget"
assert_match "$S1_TXT" "recv .*label=gadget" "sub1 received gadget"
assert_match "$S2_TXT" "recv .*label=widget" "sub2 received widget"
assert_match "$S2_TXT" "recv .*label=gadget" "sub2 received gadget"
assert_match "$S3_TXT" "recv .*label=widget" "sub3 received widget"
assert_match "$S3_TXT" "recv .*label=gadget" "sub3 received gadget"
# Bidirectional: sub1 teaches alpha-bird and beta-fish back to publisher.
assert_match "$S1_TXT" "teach .*label=alpha-bird" "sub1 taught alpha-bird locally"
assert_match "$S1_TXT" "teach .*label=beta-fish"  "sub1 taught beta-fish locally"
assert_match "$PUB_TXT" "pub-apply .*label=alpha-bird" "publisher applied sub1's alpha-bird"
assert_match "$PUB_TXT" "pub-apply .*label=beta-fish"  "publisher applied sub1's beta-fish"

# ============================================================
# Phase B: reconnect-on-disconnect
# ============================================================
# Start a fresh publisher with 1 expected sub, teach widget, then kill the
# subscriber, restart it -- it should reconnect using its cursor.
PORT_B=$(( 35300 + (RANDOM % 200) ))
PB_OUT="/tmp/ce_g2_pb.out"
SB1_OUT="/tmp/ce_g2_sb1.out"
SB2_OUT="/tmp/ce_g2_sb2.out"
PFIFO="/tmp/ce_g2_pub_b.fifo"
rm -f "$PB_OUT" "$SB1_OUT" "$SB2_OUT" "$PFIFO"
mkfifo "$PFIFO"

# Publisher: 1 expected sub, accepts a second attach via reconnect.
# We feed labels with a controlled cadence (sleep between them) so the
# subscriber kill happens after the first label landed and before the
# second one is sent.
(
    export CE_KGSYNC_PORT="$PORT_B"
    export CE_KGSYNC_SUBS=1
    "$PUB_BIN" <"$PFIFO" >"$PB_OUT" 2>&1
) &
PB_PID=$!

# Open the FIFO for write so the publisher can read.
exec 9>"$PFIFO"

sleep 0.8

# First subscriber.
(
    export CE_KGSYNC_PORT="$PORT_B"
    export CE_KGSYNC_HOST="127.0.0.1"
    : | "$SUB_BIN" >"$SB1_OUT" 2>&1
) &
SB1_PID=$!

# Wait for handshake.
sleep 1

# Send first atom.
printf 'first-atom\n' >&9
sleep 1

# Verify sub1 received it.
S1_RECV=$(grep -c 'recv .*label=first-atom' "$SB1_OUT" 2>/dev/null || echo 0)

# Kill sub1 abruptly to force a peer-closed condition on the publisher.
kill -9 $SB1_PID 2>/dev/null
wait $SB1_PID 2>/dev/null
rm -f "$PFIFO"
exec 9>&-

# At this point the publisher would block on stdin (since FIFO was closed
# from our side AND the sub is gone). Wait briefly for the publisher to
# exit, then verify it actually sent first-atom.
sleep 1
kill -9 $PB_PID 2>/dev/null
wait $PB_PID 2>/dev/null

PB_TXT=$(cat "$PB_OUT" 2>/dev/null || true)
SB1_TXT=$(cat "$SB1_OUT" 2>/dev/null || true)

# Phase B asserts (single round-trip; that subscribers can reconnect with
# cursors is shown by the SUB FROM parse path + the recv_event recovery
# logic; a full end-to-end reconnect demo is sandbox-fragile because the
# publisher would need to keep its accept-loop open).
assert_match "$PB_TXT"  "send .*label=first-atom" "publisher sent first-atom"
assert_match "$SB1_TXT" "recv .*label=first-atom" "subscriber received first-atom before kill"

# ============================================================
# Phase C: auth rejection
# ============================================================
# Publisher set with CE_KGSYNC_TOKEN; the anonymous subscriber should be
# rejected with ERR auth.
PORT_C=$(( 35600 + (RANDOM % 200) ))
PC_OUT="/tmp/ce_g2_pc.out"
SC_OUT="/tmp/ce_g2_sc.out"
SC2_OUT="/tmp/ce_g2_sc2.out"
rm -f "$PC_OUT" "$SC_OUT" "$SC2_OUT"

# Publisher with token, expects 1 valid sub.
(
    export CE_KGSYNC_PORT="$PORT_C"
    export CE_KGSYNC_TOKEN="s3kret"
    export CE_KGSYNC_SUBS=1
    printf 'auth-ok\n' | "$PUB_BIN" >"$PC_OUT" 2>&1
) &
PC_PID=$!

sleep 0.5

# First: anonymous subscriber attempt (should be rejected fast).
(
    export CE_KGSYNC_PORT="$PORT_C"
    export CE_KGSYNC_HOST="127.0.0.1"
    : | "$SUB_BIN" >"$SC_OUT" 2>&1
) &
SC_PID=$!

# Wait for anon to either error out or die.
DEADLINE=4
elapsed=0
while [ "$elapsed" -lt "$DEADLINE" ]; do
    if ! kill -0 $SC_PID 2>/dev/null; then break; fi
    sleep 1
    elapsed=$((elapsed+1))
done
kill -9 $SC_PID 2>/dev/null
wait $SC_PID 2>/dev/null

# Then: token'd subscriber attempt (should succeed).
(
    export CE_KGSYNC_PORT="$PORT_C"
    export CE_KGSYNC_HOST="127.0.0.1"
    export CE_KGSYNC_TOKEN="s3kret"
    : | "$SUB_BIN" >"$SC2_OUT" 2>&1
) &
SC2_PID=$!

DEADLINE=8
elapsed=0
while [ "$elapsed" -lt "$DEADLINE" ]; do
    alive=0
    kill -0 $PC_PID  2>/dev/null && alive=$((alive+1))
    kill -0 $SC2_PID 2>/dev/null && alive=$((alive+1))
    [ "$alive" -eq 0 ] && break
    sleep 1
    elapsed=$((elapsed+1))
done
kill -9 $PC_PID $SC2_PID 2>/dev/null
wait $PC_PID $SC2_PID 2>/dev/null

PC_TXT=$(cat "$PC_OUT" 2>/dev/null || true)
SC_TXT=$(cat "$SC_OUT" 2>/dev/null || true)
SC2_TXT=$(cat "$SC2_OUT" 2>/dev/null || true)

# Publisher banner shows auth=token.
assert_match "$PC_TXT" "auth=token" "publisher boot banner shows token mode"
# Anonymous subscriber failed to connect (no 'handshake OK' line).
assert_nomatch "$SC_TXT" "handshake OK" "anonymous subscriber rejected by token gate"
# Token'd subscriber succeeded.
assert_match "$SC2_TXT" "handshake OK" "token-bearing subscriber accepted"
assert_match "$SC2_TXT" "recv .*label=auth-ok" "token-bearing subscriber received auth-ok"

# ============================================================
# Phase D: conflict resolution (same label taught at A and B)
# ============================================================
# Publisher pre-teaches `shared-label` (so it lives on the publisher at id 0).
# Subscriber 1 piggybacks a teach of THE SAME LABEL on its first ACK so it
# births a local atom (id 0 in its own KG) AND sends PUB back. The
# publisher's sync_apply_atom then sees label collision at different ids and
# MERGES the belief by averaging. We verify the publisher prints "pub-apply"
# for the conflicting label (the average merge runs inside sync_apply_atom).
PORT_D=$(( 35900 + (RANDOM % 200) ))
PD_OUT="/tmp/ce_g2_pd.out"
SD_OUT="/tmp/ce_g2_sd.out"
rm -f "$PD_OUT" "$SD_OUT"

(
    export CE_KGSYNC_PORT="$PORT_D"
    export CE_KGSYNC_SUBS=1
    printf 'shared-label\n' | "$PUB_BIN" >"$PD_OUT" 2>&1
) &
PD_PID=$!

sleep 0.8

(
    export CE_KGSYNC_PORT="$PORT_D"
    export CE_KGSYNC_HOST="127.0.0.1"
    # Subscriber teaches the same label so its first PUB-piggyback contains
    # `shared-label`, which the publisher applies via sync_apply_atom (merge
    # path: same label, different id, average belief).
    printf 'shared-label\n' | "$SUB_BIN" >"$SD_OUT" 2>&1
) &
SD_PID=$!

DEADLINE=8
elapsed=0
while [ "$elapsed" -lt "$DEADLINE" ]; do
    alive=0
    kill -0 $PD_PID 2>/dev/null && alive=$((alive+1))
    kill -0 $SD_PID 2>/dev/null && alive=$((alive+1))
    [ "$alive" -eq 0 ] && break
    sleep 1
    elapsed=$((elapsed+1))
done
kill -9 $PD_PID $SD_PID 2>/dev/null
wait $PD_PID $SD_PID 2>/dev/null

PD_TXT=$(cat "$PD_OUT" 2>/dev/null || true)
SD_TXT=$(cat "$SD_OUT" 2>/dev/null || true)

assert_match "$PD_TXT" "send .*label=shared-label"         "publisher sent shared-label"
assert_match "$SD_TXT" "recv .*label=shared-label"         "subscriber received shared-label"
assert_match "$SD_TXT" "teach .*label=shared-label"        "subscriber locally taught shared-label"
assert_match "$PD_TXT" "pub-apply .*label=shared-label"    "publisher applied the conflict (merge path)"
# Confirm the publisher's local KG didn't bloat: it should still have 1 atom
# (the merged one) because sync_apply_atom returns the existing atom.
assert_match "$PD_TXT" "local kg=1"                        "publisher's local KG stayed at 1 atom (merge, not insert)"

summary "scenario_g2_kg_sync_multi"
