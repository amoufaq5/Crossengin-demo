#!/usr/bin/env bash
# Scenario U4 evil -- SecAgg v4 against a malicious coordinator (A2.4a).
#
# scripts/secagg_evil_coord.py speaks the real v4 wire to real souls (NOVA
# chat souls via /fed_join, Python souls via scripts/sa4_ref.py --connect)
# and lies in one way per stage. Its --check mode then rebuilds, from the
# wire log alone, what each honest soul revealed: abort code, no line after
# the abort, t valid SIG3s over the soul's own T3 before any reveal, the
# holders of each soul's b- and s-shares (honest reveals plus shares sent to
# simulated colluders, opened with their logged c-keys), leak = B >= t and
# S >= t, the input rebuilt on a leak, and a control aggregate.
#
# Roster R5 (ids 10..50, N = 5, t = 4): chat souls 10, 20; Python souls 30,
# 40, 50 (non-zero inputs: a fresh chat's promo/atr words are 0).
#   E.results    honest round (10 tags), then forged results: only the first
#                valid line per tag is applied, the rest are ignored with
#                their reason, the soul closes past the after-round cap.
#   E.replay     the same souls (kept state) get round 5 / 4: stale_round.
#   E.burn       SA4_ROUND r = 2^62-1 with a bad fingerprint: bad_fp, and
#                the last-round file / --state keep 5.
#   E.afterburn  a normal round 6 then completes.
#   E.r0a/r0b    bad_fp / bad_len / bad_layout (chat and Python each).
#   E.ownadv E.advsig E.advold   bad_adv / bad_sig / bad_round + bad_sig.
#   E.u1small E.notinu1          u1_small / not_in_u1.
#   E.equivu1a/b U1 equivocation (chat and Python victim): no REVEAL at all.
#   E.tamper     a share ciphertext altered in transit: bad_share.
#   E.u2small E.notinu2 E.u2notsub   u2_small / not_in_u2 / bad_set.
#   E.fd50 E.fd10  false dropout of a Python / chat soul: the victim refuses
#                (bad_sig3), no b-reveal about it, its s key is rebuilt but
#                its y without pairwise masks equals its input in no word;
#                the control aggregate over the others is exact.
#                Checker negative controls on that log: a REVEAL after the
#                abort, and a soul short of t valid SIG3s, are reported.
#   E.split E.sig3bad E.ownsig3 E.u4notsub E.u4small   bad_sig3 / bad_set /
#                u4_small, no reveal from a refusing soul.
#   E.oop E.early E.long E.nul   unexpected / bad_line / transport.
#   E.hang E.trickle  the chat gives up within CE_SECAGG_V4_SOUL_MS (+3 s),
#                the Python soul within --deadline (+3 s).
# Roster R10 (N = 10, t = 7): 2 chat + 4 Python souls, colluders simulated
# in the coordinator from their seeds.
#   E.col3       C = 3 (= 2t-N-1), best split: min(B, S) < t for every soul.
#   E.col4       C = 4 (= 2t-N): the checker rebuilds the victim's input
#                exactly (positive control: the bound is tight).
#
# Env: CE_IT_STRICT=1 (CI) turns an environment SKIP (socket bind denied,
# python3 or openssl missing) into a FAIL.

. "$(dirname "$0")/_lib.sh"
. "$(dirname "$0")/_sa4_lib.sh"

PASS=0; FAIL=0
it_section "scenario U4 evil: SecAgg v4 souls against a malicious coordinator (A2.4a)"

EVIL="$REPO_ROOT/scripts/secagg_evil_coord.py"
finish() {
    summary "scenario_u4_evil"; exit $?
}

if [ ! -x "$SA4_CHAT_BIN" ]; then
    printf "  ${C_RED}ERROR${C_RST}: %s missing. Run: make install\n" "$SA4_CHAT_BIN" >&2
    FAIL=$((FAIL+1)); finish
fi
command -v python3 >/dev/null 2>&1 || { sa4_skip "python3 not on PATH"; finish; }
command -v openssl >/dev/null 2>&1 || { sa4_skip "openssl not on PATH"; finish; }

T="$(mktemp -d)"
chmod 700 "$T"
trap 'sa4_cleanup; rm -rf "$T"' EXIT
SECONDS=0

sa4_keys 10
sa4_roster "$T/R5" 1 2 3 4 5
sa4_roster "$T/R10" 1 2 3 4 5 6 7 8 9 10
assert_match "$(cat "$T/R10")" '^crossengin-secagg-roster v1' "rosters written"

PORT=$(( 41000 + (RANDOM % 900) * 8 ))
next_port() { PORT=$((PORT + 1)); }
py_x() { echo "seed=${1}1:${1}2,user-teach=${1}3:${1}4"; }
T2="seed,user-teach"
T10="seed,t0,t1,t2,t3,t4,t5,t6,t7,user-teach"
STAGE_CHAT_ENV=(CE_SECAGG_V4_SOUL_MS=60000)
STAGE_PY_ARGS=(--deadline 60)

# stage <name> <roster> <chat souls> <py souls> <evil args...>: run the evil
# coordinator and the souls, wait (bounded), then --check -> $CK.
stage() {
    local name="$1" ro="$2" chats="$3" pys="$4" k n=0 ep; shift 4
    D="$T/$name"; CK="$D/check.json"
    mkdir -p "$D"; chmod 700 "$D"
    next_port
    CE_SECAGG_ROSTER="$ro" CE_SECAGG_V4_TAGS="$SA4_TAGS" \
        python3 -I "$EVIL" --listen "127.0.0.1:$PORT" --log "$D/wire.log" "$@" > "$D/evil.out" 2>&1 &
    ep=$!; PIDS+=("$ep"); SP+=("$ep")
    while [ $n -lt 40 ]; do
        grep -q "evil: listening\|evil: ERROR" "$D/evil.out" 2>/dev/null && break
        sleep 0.25; n=$((n + 1))
    done
    if ! grep -q "evil: listening" "$D/evil.out" 2>/dev/null; then
        stage_wait 10
        if grep -q "cannot bind" "$D/evil.out" 2>/dev/null; then
            sa4_skip "socket bind denied -- $name skipped"
        else
            assert_match "$(cat "$D/evil.out" 2>/dev/null)" "evil: listening" "$name: evil coordinator started"
        fi
        return 1
    fi
    for k in $chats; do chat_soul "$D" "soul$k" "$ro" "$k" "${STAGE_CHAT_ENV[@]}"; done
    for k in $pys; do py_soul "$D" "py$k" "$ro" "$k" "$(py_x "$k")" "${STAGE_PY_ARGS[@]}"; done
    stage_wait 60
    local xs=()
    for k in $chats; do xs+=(--x "$(chat_x "$D/soul$k.out" $((k * 10)))"); done
    for k in $pys; do xs+=(--x "$((k * 10))=$(py_x "$k")"); done
    CE_SECAGG_ROSTER="$ro" CE_SECAGG_V4_TAGS="$SA4_TAGS" \
        python3 -I "$EVIL" --check "$D/wire.log" "${xs[@]}" > "$CK" 2> "$D/check.err"
    return 0
}

# Abort codes per soul from the check JSON: "10=code 20=- ..." (- = none).
codes() {
    python3 -I -c '
import json, sys
try:
    d = json.load(open(sys.argv[1]))["souls"]
except (OSError, ValueError, KeyError):
    print("(no check)"); sys.exit(0)
print(" ".join("%s=%s" % (k, d[k]["abort"] or "-") for k in sorted(d, key=int)))' "$1"
}
all5() { echo "10=$1 20=$1 30=$1 40=$1 50=$1"; }
# max over souls of min(B, S): the coordinator's best progress towards a leak.
maxmin() {
    python3 -I -c '
import json, sys
d = json.load(open(sys.argv[1]))["souls"]
print(max(min(v["B"], v["S"]) for v in d.values()))' "$1" 2>/dev/null || echo "(no check)"
}

nothing_learned() {   # <label>
    assert_eq "$(jget "$CK" reveal_lines)" "0" "$1: no REVEAL line from any soul"
    assert_eq "$(jget "$CK" after_abort)" "[]" "$1: no soul sent a line after its abort"
}
# refusal <label> <codes> <chat soul1 regex> <py3 regex>
refusal() {
    assert_eq "$(codes "$CK")" "$2" "$1: abort codes on the wire"
    assert_match "$(cat "$D/soul1.out" 2>/dev/null)" "fed_join: \\[SA4\\] round not completed: $3" "$1: chat soul 10 says why"
    assert_match "$(cat "$D/py3.out" 2>/dev/null)" "sa4_ref: $4" "$1: Python soul 30 says why"
    nothing_learned "$1"
}
lr_file() {   # lr_file <chat run dir> <id>: the chat's last-round file contents
    local f
    f=$(ls "$1" 2>/dev/null | grep "^crossengin_sa4_last_round_[0-9a-f]*_$2\$" | head -1)
    [ -n "$f" ] && cat "$1/$f"
}
# applied/ignored summary of one soul's result handling
res_sig() {
    local o; o=$(cat "$1" 2>/dev/null)
    printf "seed=%s user-teach=%s t0=%s ignored=%s cap=%s" \
        "$(echo "$o" | grep -c "AGGREGATE_SUM round=5 tag=seed ")" \
        "$(echo "$o" | grep -c "AGGREGATE_SUM round=5 tag=user-teach ")" \
        "$(echo "$o" | grep -c "AGGREGATE_SUM round=5 tag=t0")" \
        "$(echo "$o" | grep -c "ignored a result line")" \
        "$(echo "$o" | grep -c "too many lines after the round; closing")"
}
local_sum() {   # local_sum <tag> <field>: chat souls 1,2 (from output) + Python 3,4,5
    local s=0 f v
    for f in "$D/soul1.out" "$D/soul2.out"; do
        v=$(sed -n "s/.*input (stays local) tag=$1 promo=\([0-9]*\) atr=\([0-9]*\) present=\([0-9]*\).*/\1 \2 \3/p" "$f" \
            | awk -v f="$2" '{ if (f == "promo") print $1; else if (f == "atr") print $2; else print $3 }')
        s=$((s + ${v:-999999}))
    done
    for k in 3 4 5; do
        case "$1:$2" in
            seed:promo) s=$((s + k * 10 + 1));; seed:atr) s=$((s + k * 10 + 2));;
            user-teach:promo) s=$((s + k * 10 + 3));; user-teach:atr) s=$((s + k * 10 + 4));;
            *) s=$((s + 1));;
        esac
    done
    echo "$s"
}

# ===========================================================================
# Kept state: E.results, E.replay, E.burn, E.afterburn share the chat run
# dirs and the Python --state files.
# ===========================================================================
SA4_RUNBASE="$T/keep"; mkdir -p "$SA4_RUNBASE"; chmod 700 "$SA4_RUNBASE"
SA4_TAGS="$T10"
if stage results "$T/R5" "1 2" "3 4 5" --round 5 --attack results; then
    for tag in seed user-teach; do
        L="AGGREGATE_SUM round=5 tag=$tag sum_promo=$(local_sum $tag promo) sum_atr=$(local_sum $tag atr) n_part=5"
        assert_match "$(cat "$D/soul1.out")" "fed: \\[SA4\\] $L\$" "results: chat soul 10 applied the true $tag sum"
        assert_match "$(cat "$D/py4.out")" "sa4_ref: $L\$" "results: Python soul 40 applied the true $tag sum"
    done
    for s in soul1 soul2 py3 py4 py5; do
        assert_eq "$(res_sig "$D/$s.out")" "seed=1 user-teach=1 t0=0 ignored=8 cap=1" \
            "results: $s applied one line per tag, ignored 8, closed at the 11th line (ntags = 10) without parsing it"
    done
    for s in soul2 py5; do
        O=$(cat "$D/$s.out")
        for why in "second result for this tag" "for another round" "tag not in CE_SECAGG_V4_TAGS" \
                   "n_part below 1" "n_part above \\|U3\\|" "not a FED_AGGREGATE_SUM line"; do
            assert_match "$O" "ignored a result line \\($why\\)" "results: $s ignored a line: $why"
        done
        assert_eq "$(echo "$O" | grep -c "ignored a result line (not a FED_AGGREGATE_SUM line)")" "3" \
            "results: $s refused the negative, 2^32 and 25-digit sums"
    done
    assert_nomatch "$(cat "$D"/*.out)" "sum_promo=(-|4294967296|1234567890)" "results: no forged value was applied"
    assert_eq "$(jget "$CK" revealers)" "[10, 20, 30, 40, 50]" "results: every soul revealed"
    assert_eq "$(jget "$CK" bad_revealers)" "[]" "results: every revealer had t valid SIG3s over its own T3 and followed it"
    assert_eq "$(jget "$CK" leaks)" "[]" "results: no soul's input is exposed"
    assert_eq "$(jget "$CK" control.exact)" "true" "results: the aggregate rebuilt from the log equals the sum of the inputs"
    assert_match "$(lr_file "$SA4_RUNBASE/run_soul1" 10)" "^crossengin-sa4-last-round v1 [0-9a-f]{64} 10 5$" "results: chat soul 10 recorded round 5"
    assert_eq "$(cat "$SA4_RUNBASE/state_py3" 2>/dev/null)" "5" "results: Python soul 30 recorded round 5"
fi

SA4_TAGS="$T2"
if stage replay "$T/R5" "1 2" "3 4 5" --round 5 --attack round0 --r0 10=r5,30=r5,20=r4,40=r4,50=r4; then
    refusal replay "$(all5 stale_round)" "refused: round 5 is not after the last round \\(abort code stale_round\\)" \
        "refused: round is not after the last round \\(abort code stale_round\\)"
    assert_match "$(cat "$D/soul2.out")" "round 4 is not after the last round \\(abort code stale_round\\)" "replay: chat soul 20 refused round 4"
    assert_match "$(cat "$D/soul1.out")" "last-round=5" "replay: chat soul 10 loaded its last round (5)"
fi

if stage burn "$T/R5" "1 2" "3 4 5" --round 5 --attack round0 \
        --r0 10=burn,20=burn,30=burn,40=burn,50=burn; then
    refusal burn "$(all5 bad_fp)" "refused: roster fingerprint differs \\(abort code bad_fp\\)" \
        "refused: roster fingerprint differs \\(abort code bad_fp\\)"
    assert_match "$(cat "$D/wire.log")" "S>10 SA4_ROUND 4611686018427387903 " "burn: the round line carried r = 2^62-1"
    assert_match "$(lr_file "$SA4_RUNBASE/run_soul1" 10)" " 10 5$" "burn: chat soul 10 last-round file still holds 5"
    assert_match "$(lr_file "$SA4_RUNBASE/run_soul2" 20)" " 20 5$" "burn: chat soul 20 last-round file still holds 5"
    assert_eq "$(cat "$SA4_RUNBASE/state_py3" "$SA4_RUNBASE/state_py4" "$SA4_RUNBASE/state_py5" 2>/dev/null | tr '\n' ' ')" "5 5 5 " \
        "burn: the Python souls' --state still holds 5"
fi

if stage afterburn "$T/R5" "1 2" "3 4 5" --round 6 --attack honest; then
    assert_eq "$(codes "$CK")" "$(all5 -)" "afterburn: no soul aborted round 6"
    assert_match "$(cat "$D/soul1.out")" "fed: \\[SA4\\] round 6 complete \\(2 sum aggregate" "afterburn: chat soul 10 completed round 6"
    assert_match "$(cat "$D/soul2.out")" "fed: \\[SA4\\] round 6 complete \\(2 sum aggregate" "afterburn: chat soul 20 completed round 6"
    assert_match "$(cat "$D/py5.out")" "BYE after 2 aggregate" "afterburn: Python soul 50 completed round 6"
    assert_eq "$(jget "$CK" control.exact)" "true" "afterburn: exact aggregate"
    assert_match "$(lr_file "$SA4_RUNBASE/run_soul1" 10)" " 10 6$" "afterburn: chat soul 10 recorded round 6"
    assert_eq "$(cat "$SA4_RUNBASE/state_py5" 2>/dev/null)" "6" "afterburn: Python soul 50 recorded round 6"
fi
unset SA4_RUNBASE

# ===========================================================================
# R0 / R1: one stage per check, every soul a victim (fresh state, round 7).
# ===========================================================================
if stage r0a "$T/R5" "1 2" "3 4 5" --round 7 --attack round0 \
        --r0 10=bad-fp,20=bad-len,30=bad-layout,40=bad-fp,50=bad-len; then
    refusal r0a "10=bad_fp 20=bad_len 30=bad_layout 40=bad_fp 50=bad_len" "refused: roster fingerprint differs \\(abort code bad_fp\\)" \
        "refused: vector layout differs \\(abort code bad_layout\\)"
    assert_match "$(cat "$D/soul2.out")" "refused: vector length differs from the input \\(abort code bad_len\\)" "r0a: chat soul 20 refused a wrong L"
    assert_match "$(cat "$D/py5.out")" "refused: vector length differs from the input \\(abort code bad_len\\)" "r0a: Python soul 50 refused a wrong L"
fi
if stage r0b "$T/R5" "1 2" "3 4 5" --round 7 --attack round0 \
        --r0 10=bad-layout,20=bad-fp,30=bad-fp,40=bad-len,50=bad-layout; then
    refusal r0b "10=bad_layout 20=bad_fp 30=bad_fp 40=bad_len 50=bad_layout" "refused: vector layout differs \\(abort code bad_layout\\)" \
        "refused: roster fingerprint differs \\(abort code bad_fp\\)"
fi
if stage ownadv "$T/R5" "1 2" "3 4 5" --round 7 --attack own-adv; then
    refusal own-adv "$(all5 bad_adv)" "refused: own ADV altered \\(abort code bad_adv\\)" "refused: own ADV altered \\(abort code bad_adv\\)"
fi
if stage advsig "$T/R5" "1 2" "3 4 5" --round 7 --attack adv-sig; then
    refusal adv-sig "$(all5 bad_sig)" "refused: ADV signature of soul 20 does not verify \\(abort code bad_sig\\)" \
        "refused: ADV signature does not verify \\(abort code bad_sig\\)"
fi
if stage advold "$T/R5" "1 2" "3 4 5" --round 7 --attack adv-old --prev-log "$T/afterburn/wire.log" --victim 10,30; then
    refusal adv-old "10=bad_round 20=bad_sig 30=bad_round 40=bad_sig 50=bad_sig" \
        "refused: line for another round \\(abort code bad_round\\)" "refused: line for another round \\(abort code bad_round\\)"
    assert_match "$(cat "$D/soul2.out")" "refused: ADV signature of soul 30 does not verify \\(abort code bad_sig\\)" \
        "adv-old: chat soul 20 refused round-6 ADV relabelled as round 7"
    assert_match "$(cat "$D/py4.out")" "refused: ADV signature does not verify \\(abort code bad_sig\\)" \
        "adv-old: Python soul 40 refused round-6 ADV relabelled as round 7"
fi
if stage u1small "$T/R5" "1 2" "3 4 5" --round 7 --attack u1-small; then
    refusal u1-small "$(all5 u1_small)" "refused: \\|U1\\| below the threshold \\(abort code u1_small\\)" \
        "refused: \\|U1\\| below the threshold \\(abort code u1_small\\)"
fi
if stage notinu1 "$T/R5" "1 2" "3 4 5" --round 7 --attack not-in-u1; then
    refusal not-in-u1 "$(all5 not_in_u1)" "refused: this soul is not in U1 \\(abort code not_in_u1\\)" \
        "refused: this soul is not in U1 \\(abort code not_in_u1\\)"
fi
# U1 equivocation: the victim's U1 lacks one soul; H1 differs.
if stage equivu1a "$T/R5" "1 2" "3 4 5" --round 7 --attack equiv-u1 --victim 10 --hide 40; then
    refusal equiv-u1/chat "10=bad_sig3 20=bad_sig3 30=bad_sig3 40=bad_share 50=bad_sig3" \
        "refused: consistency signature of soul [0-9]+ does not verify \\(abort code bad_sig3\\)" \
        "refused: consistency signature does not verify \\(abort code bad_sig3\\)"
fi
if stage equivu1b "$T/R5" "1 2" "3 4 5" --round 7 --attack equiv-u1 --victim 50 --hide 20; then
    assert_eq "$(codes "$CK")" "10=bad_sig3 20=bad_share 30=bad_sig3 40=bad_sig3 50=bad_sig3" "equiv-u1/py: abort codes on the wire"
    assert_match "$(cat "$D/soul2.out")" "refused: share lines do not match U2 \\(abort code bad_share\\)" "equiv-u1/py: chat soul 20 (hidden from 50) refused"
    assert_match "$(cat "$D/py5.out")" "refused: consistency signature does not verify \\(abort code bad_sig3\\)" "equiv-u1/py: Python victim 50 refused"
    nothing_learned equiv-u1/py
fi

# ===========================================================================
# R2
# ===========================================================================
if stage tamper "$T/R5" "1 2" "3 4 5" --round 7 --attack tamper-ct; then
    refusal tamper-ct "$(all5 bad_share)" "refused: share from soul [0-9]+ does not open \\(abort code bad_share\\)" \
        "refused: share does not open \\(abort code bad_share\\)"
fi
if stage u2small "$T/R5" "1 2" "3 4 5" --round 7 --attack u2-small; then
    refusal u2-small "$(all5 u2_small)" "refused: \\|U2\\| below the threshold \\(abort code u2_small\\)" \
        "refused: \\|U2\\| below the threshold \\(abort code u2_small\\)"
fi
if stage notinu2 "$T/R5" "1 2" "3 4 5" --round 7 --attack not-in-u2; then
    refusal not-in-u2 "$(all5 not_in_u2)" "refused: this soul is not in U2 \\(abort code not_in_u2\\)" \
        "refused: this soul is not in U2 \\(abort code not_in_u2\\)"
fi
if stage u2notsub "$T/R5" "1 2" "3 4 5" --round 7 --attack u2-notsub --hide 50; then
    refusal u2-notsub "10=bad_set 20=bad_set 30=bad_set 40=bad_set 50=not_in_u1" \
        "refused: U2 is not a subset of U1 \\(abort code bad_set\\)" "refused: U2 is not a subset of U1 \\(abort code bad_set\\)"
fi

# ===========================================================================
# R3 / R4: false dropout, split views, SIG3 and U4 attacks.
# ===========================================================================
fd_checks() {   # fd_checks <label> <victim id> <others JSON list>
    assert_eq "$(jget "$CK" souls.$2.abort)" "bad_sig3" "$1: the victim $2 refused (bad_sig3)"
    assert_eq "$(jget "$CK" souls.$2.revealed)" "false" "$1: the victim revealed nothing"
    assert_eq "$(jget "$CK" souls.$2.B)" "0" "$1: no b-share of the victim reached the coordinator"
    assert_eq "$(jget "$CK" souls.$2.S)" "4" "$1: t = 4 s-shares of the victim reached it"
    assert_eq "$(jget "$CK" souls.$2.s_rebuilt)" "true" "$1: the coordinator rebuilds the victim's s key (matches its s_pk)"
    assert_eq "$(jget "$CK" souls.$2.y_minus_pairwise_matches)" "0" "$1: the victim's y without pairwise masks equals its input in no word"
    assert_eq "$(jget "$CK" leaks)" "[]" "$1: no leak"
    assert_eq "$(jget "$CK" revealers)" "$3" "$1: the others revealed"
    assert_eq "$(jget "$CK" bad_revealers)" "[]" "$1: each revealer had t valid SIG3s over its own T3 and followed it"
    assert_eq "$(jget "$CK" control.dropped)" "[$2]" "$1: control treats the victim as dropped"
    assert_eq "$(jget "$CK" control.exact)" "true" "$1: control aggregate over the others is exact (mask arithmetic checked)"
    assert_eq "$(jget "$CK" after_abort)" "[]" "$1: no soul sent a line after its abort"
}
if stage fd50 "$T/R5" "1 2" "3 4 5" --round 7 --attack false-dropout --victim 50; then
    fd_checks false-dropout/py 50 "[10, 20, 30, 40]"
    assert_match "$(cat "$D/py5.out")" "sa4_ref: refused: consistency signature does not verify \\(abort code bad_sig3\\)" \
        "false-dropout/py: the Python victim says why"
    assert_match "$(cat "$D/soul1.out")" "fed: \\[SA4\\] AGGREGATE_SUM round=7 tag=seed .* n_part=4$" "false-dropout/py: chat soul 10 got the sum over 4"
fi
# Negative controls for the checker itself (no sockets): a REVEAL written
# into the log after the victim's abort, and two SIG3 lines taken out of
# what soul 40 was sent, must both be reported.
if [ -s "$T/fd50/wire.log" ]; then
    { cat "$T/fd50/wire.log"
      grep -m1 '^40>S SA4_REVEAL ' "$T/fd50/wire.log" | sed 's/^40>S SA4_REVEAL \([0-9]*\) 40 /50>S SA4_REVEAL \1 50 /'
    } > "$T/fd50/forged.log"
    awk '/^S>40 SA4_SIG3 / && n < 2 { n++; next } { print }' "$T/fd50/wire.log" > "$T/fd50/nosig.log"
    for f in forged nosig; do
        CE_SECAGG_ROSTER="$T/R5" CE_SECAGG_V4_TAGS="$T2" python3 -I "$EVIL" --check "$T/fd50/$f.log" > "$T/fd50/$f.json" 2>&1
    done
    assert_eq "$(jget "$T/fd50/forged.json" after_abort)" "[50]" "checker: a line after an abort is reported"
    assert_eq "$(jget "$T/fd50/forged.json" bad_revealers)" "[50]" "checker: a reveal without t valid SIG3s over the soul's T3 is reported"
    assert_eq "$(jget "$T/fd50/nosig.json" souls.40.sig3_valid) $(jget "$T/fd50/nosig.json" bad_revealers)" "2 [40]" \
        "checker: a soul that revealed after only 2 valid SIG3s is reported"
fi
if stage fd10 "$T/R5" "1 2" "3 4 5" --round 7 --attack false-dropout --victim 10; then
    fd_checks false-dropout/chat 10 "[20, 30, 40, 50]"
    assert_match "$(cat "$D/soul1.out")" "round not completed: refused: consistency signature of soul 20 does not verify \\(abort code bad_sig3\\)" \
        "false-dropout/chat: the chat victim says why"
    assert_match "$(cat "$D/py3.out")" "sa4_ref: AGGREGATE_SUM round=7 tag=seed .* n_part=4$" "false-dropout/chat: Python soul 30 got the sum over 4"
fi
if stage split "$T/R5" "1 2" "3 4 5" --round 7 --attack split-u3 --groups 10,30,50/20,40; then
    refusal split-u3 "$(all5 bad_sig3)" "refused: consistency signature of soul 20 does not verify \\(abort code bad_sig3\\)" \
        "refused: consistency signature does not verify \\(abort code bad_sig3\\)"
fi
if stage sig3bad "$T/R5" "1 2" "3 4 5" --round 7 --attack sig3-bad; then
    refusal sig3-bad "$(all5 bad_sig3)" "refused: consistency signature of soul 20 does not verify \\(abort code bad_sig3\\)" \
        "refused: consistency signature does not verify \\(abort code bad_sig3\\)"
fi
if stage ownsig3 "$T/R5" "1 2" "3 4 5" --round 7 --attack own-sig3; then
    refusal own-sig3 "$(all5 bad_sig3)" "refused: own signature altered \\(abort code bad_sig3\\)" \
        "refused: own signature altered \\(abort code bad_sig3\\)"
fi
if stage u4notsub "$T/R5" "1 2" "3 4 5" --round 7 --attack u4-notsub --hide 40; then
    refusal u4-notsub "10=bad_set 20=bad_set 30=bad_set 40=not_in_u3 50=bad_set" \
        "refused: U4 is not a subset of U3 \\(abort code bad_set\\)" "refused: U4 is not a subset of U3 \\(abort code bad_set\\)"
fi
if stage u4small "$T/R5" "1 2" "3 4 5" --round 7 --attack u4-small; then
    refusal u4-small "$(all5 u4_small)" "refused: fewer than t consistency signatures \\(abort code u4_small\\)" \
        "refused: fewer than t consistency signatures \\(abort code u4_small\\)"
fi

# ===========================================================================
# Transport: out of phase, early result, long line, NUL, hang, trickle.
# ===========================================================================
if stage oop "$T/R5" "1 2" "3 4 5" --round 7 --attack out-of-phase; then
    refusal out-of-phase "$(all5 unexpected)" "refused: unexpected line while collecting ADV \\(abort code unexpected\\)" \
        "refused: unexpected line in state 1 \\(abort code unexpected\\)"
fi
if stage early "$T/R5" "1 2" "3 4 5" --round 7 --attack early-result; then
    refusal early-result "$(all5 bad_line)" "refused: malformed line \\(abort code bad_line\\)" "refused: malformed line \\(abort code bad_line\\)"
fi
if stage long "$T/R5" "1 2" "3 4 5" --round 7 --attack long-line; then
    refusal long-line "$(all5 transport)" "the coordinator sent a line over 1000 bytes before the round finished" \
        "refused: transport: line over 1000 bytes \\(abort code transport\\)"
fi
if stage nul "$T/R5" "1 2" "3 4 5" --round 7 --attack nul; then
    refusal nul "10=transport 20=transport 30=bad_line 40=bad_line 50=bad_line" \
        "the coordinator sent a NUL byte before the round finished" "refused: malformed line \\(abort code bad_line\\)"
fi
# within <ms> <lo> <hi>: yes / no (ms)
within() { if [ -n "$1" ] && [ "$1" != "(missing)" ] && [ "$1" -ge "$2" ] && [ "$1" -le "$3" ]; then echo yes; else echo "no ($1 ms)"; fi; }
STAGE_CHAT_ENV=(CE_SECAGG_V4_SOUL_MS=5000)
STAGE_PY_ARGS=(--deadline 5)
if stage hang "$T/R5" "1 2" "3 4 5" --round 7 --attack hang --hang-s 12; then
    refusal hang "$(all5 transport)" "timed out waiting for the coordinator \\(CE_SECAGG_V4_SOUL_MS\\) before the round finished" \
        "refused: transport: timed out \\(abort code transport\\)"
    for id in 10 20; do
        assert_eq "$(within "$(jget "$CK" souls.$id.close_ms)" 4000 8000)" "yes" "hang: chat soul $id gave up within CE_SECAGG_V4_SOUL_MS = 5 s (+3)"
    done
    for id in 30 40 50; do
        assert_eq "$(within "$(jget "$CK" souls.$id.close_ms)" 4000 8000)" "yes" "hang: Python soul $id gave up within --deadline 5 (+3)"
    done
fi
if stage trickle "$T/R5" "1 2" "3 4 5" --round 7 --attack trickle --hang-s 10 --trickle-s 0.5; then
    refusal trickle "$(all5 transport)" "timed out waiting for the coordinator \\(CE_SECAGG_V4_SOUL_MS\\) before the round finished" \
        "refused: transport: "
    for id in 10 20; do
        assert_eq "$(within "$(jget "$CK" souls.$id.close_ms)" 4000 8000)" "yes" "trickle: chat soul $id gave up within CE_SECAGG_V4_SOUL_MS = 5 s (+3)"
    done
    for id in 30 40 50; do
        assert_eq "$(within "$(jget "$CK" souls.$id.close_ms)" 4000 8000)" "yes" "trickle: Python soul $id gave up within --deadline 5 (+3)"
    done
fi
STAGE_CHAT_ENV=(CE_SECAGG_V4_SOUL_MS=60000)
STAGE_PY_ARGS=(--deadline 60)

# ===========================================================================
# Collusion at N = 10, t = 7: 6 real souls (chat 10, 20; Python 30..60),
# colluders 70.. simulated by the coordinator. Victim: Python soul 30.
# ===========================================================================
if stage col3 "$T/R10" "1 2" "3 4 5 6" --round 7 --attack collude --souls 6 --victim 30 \
        --groups 30,10,40,50/20,60 --collude "$T/k7.priv,$T/k8.priv,$T/k9.priv"; then
    assert_eq "$(jget "$CK" colluders)" "[70, 80, 90]" "collude C=3: three colluders (2t-N-1), soul 100 absent"
    assert_eq "$(jget "$CK" colluder_keys_ok)" "true" "collude C=3: colluder c-keys match their ADVs (shares opened by the checker)"
    assert_eq "$(codes "$CK")" "10=- 20=u4_small 30=- 40=- 50=- 60=u4_small" "collude C=3: view A completes, view B cannot get t SIG3s"
    assert_eq "$(jget "$CK" souls.30.B) $(jget "$CK" souls.30.S)" "7 3" "collude C=3: victim 30 has B = 7, S = 3 (colluders only)"
    assert_eq "$(maxmin "$CK")" "3" "collude C=3: best split gives min(B, S) = 3 < t for every soul"
    assert_eq "$(jget "$CK" leaks)" "[]" "collude C=3: no leak"
    assert_eq "$(jget "$CK" bad_revealers)" "[]" "collude C=3: every revealer had t valid SIG3s over its own T3"
    assert_eq "$(jget "$CK" after_abort)" "[]" "collude C=3: no line after an abort"
    assert_match "$(cat "$D/soul2.out")" "refused: fewer than t consistency signatures \\(abort code u4_small\\)" "collude C=3: chat soul 20 (view B) refused"
fi
if stage col4 "$T/R10" "1 2" "3 4 5 6" --round 7 --attack collude --souls 6 --victim 30 \
        --groups 30,10,40/20,50,60 --collude "$T/k7.priv,$T/k8.priv,$T/k9.priv,$T/k10.priv"; then
    assert_eq "$(jget "$CK" colluders)" "[70, 80, 90, 100]" "collude C=4: four colluders (2t-N)"
    assert_eq "$(codes "$CK")" "10=- 20=- 30=- 40=- 50=- 60=-" "collude C=4: both views complete"
    assert_eq "$(jget "$CK" bad_revealers)" "[]" "collude C=4: every revealer followed the rules (t valid SIG3s over its own T3)"
    assert_eq "$(jget "$CK" souls.30.B) $(jget "$CK" souls.30.S)" "7 7" "collude C=4: victim 30 has B = 7, S = 7"
    assert_eq "$(jget "$CK" leaks)" "[30]" "collude C=4: the leak detector fires for the victim only"
    assert_eq "$(jget "$CK" souls.30.x_match)" "true" "collude C=4: the victim's input is rebuilt exactly (bound is tight)"
    assert_eq "$(jget "$CK" souls.30.x_rebuilt)" "[31, 32, 1, 33, 34, 1]" "collude C=4: rebuilt input = 31 32 1 33 34 1"
fi

printf "  ${C_DIM}runtime %ss${C_RST}\n" "$SECONDS"
finish
