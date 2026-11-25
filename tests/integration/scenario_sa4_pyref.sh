#!/usr/bin/env bash
# Scenario sa4_pyref -- SecAgg v4 (v4-sa3): NOVA soul and coordinator vs an
# independent Python soul and coordinator oracle (A2.3b; verifiable shares
# A2.4b; complaint round and blame A2.4c).
#   scripts/sa4_ref.py is a second implementation of the v4 soul with its
#   own primitives (stdlib only). Driven with the same seeds, roster and
#   deterministic RNG as tests/sa4_harness.nova, it must produce exactly the
#   lines the NOVA soul produces (tests/tools/sa4_dump.nova), in these
#   scenarios:
#     A  N = 3, all honest                     (roster fingerprint too)
#     B  N = 5, one soul in U2 but not U3      (s-shares revealed)
#     C  N = 4, one soul drops after its ADV
#     D  N = 5, one soul in U3 but not U4      (no SIG3 from it)
#     E  21 refusals (abort line and code; v4-sa2: own ADV with B or M
#        altered, a peer ADV with M altered, a v1 6-token ADV; v4-sa3:
#        SET 2 in SHARED, a 5-token SHARE, ACCUSE naming the receiver, two
#        complaints from one soul, a final U2 with a complained-about soul,
#        ACCUSE twice)
#     F G H I J P  v4-sa3 rounds with the coordinator (SPEC A2.4c section
#        15): NOVA souls + NOVA coordinator vs Python souls + the Python
#        coordinator oracle. F sender garbage (code 1), G false complaint
#        (code 2), H silent accused (code 3), I downlink tamper (code 5),
#        J bad SHSIG (code 4), P plain. Every soul line (SHARE, SHSIG,
#        COMPLAINT, OPEN, END 4/5, Y, SIG3, REVEAL), the blame codes and why
#        texts, the evidence texts (length and SHA-256) and the sum must be
#        identical; the NOVA evidence files of F and G are judged by
#        sa4_ref.py --judge (sender / complainer), a tampered copy is
#        refused.
#   Every ADV/SHARE/Y/SIG3/REVEAL line carries a signature, ciphertext,
#   masked words or a share, so a match pins the KDFs, AEAD framing, Shamir
#   layout, PRG, mask signs, transcripts, share commitments (B_u, Merkle
#   root, authentication paths, reveal proofs), one-time keys, share roots
#   and reveal policy; E compares abort lines. A tampered transcript must be
#   reported as a difference (negative control).
#   Then a differential run: tests/tools/sa4_cases.py builds 1111 cases
#   (honest rounds perturbed in every phase: every abort code, forged shares
#   and signatures, shares or paths that do not match the dealer's
#   commitment (v4-sa3: a signed COMPLAINT, not an abort), one-time keys
#   (low-order, non-canonical, foreign), B/M altered or re-signed in an ADV,
#   wrong share ciphertext lengths, SET 5 / COMPLAINT / ACCUSE / OPEN / final
#   SET 2 cases, set_input validation, and seeded random mutations / moves /
#   duplications / deletions of every line of five rounds); the NOVA soul
#   (tests/tools/sa4_script.nova) and the Python soul must give the same ok /
#   state / round / output lines at every step. The case file is larger than
#   NOVA's read_file limit, so it is run in parts split at CASE lines.
#   Needs no sockets.

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0
it_section "scenario sa4_pyref: SecAgg v4 NOVA soul vs Python reference soul"

skip() {
    echo "SKIP: $1"
    if [ "${CE_IT_STRICT:-0}" = "1" ]; then exit 1; fi
    exit 0
}

NOVA="${NOVA_ROOT:-$HOME/NOVA}/nova"
[ -x "$NOVA" ] || skip "NOVA launcher not found at $NOVA"
command -v python3 >/dev/null 2>&1 || skip "python3 not on PATH"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
REF="$REPO_ROOT/scripts/sa4_ref.py"

OUT=$(python3 -I "$REF" --selftest 2>&1)
assert_eq "$?" "0" "Python reference self-test (RFC 7748/8032/8439/5869, FIPS-197, repo KATs)"
assert_match "$OUT" 'selftest: OK' "self-test reports OK"

"$NOVA" build "$REPO_ROOT/tests/tools/sa4_dump.nova" -o "$WORK/dump" >"$WORK/build.log" 2>&1
assert_eq "$?" "0" "transcript dumper builds"

for X in A B C D E F G H I J P; do
    SA4DUMP=$X SA4EVDIR="$WORK" "$WORK/dump" > "$WORK/nova_$X.txt" 2>&1
    assert_eq "$?" "0" "NOVA scenario $X runs"
    case $X in
        E) N=$(grep -c '^CASE ' "$WORK/nova_$X.txt") ;;
        *) N=$(grep -c -E '^(ADV|OUT) ' "$WORK/nova_$X.txt") ;;
    esac
    assert_match "$N" '^[1-9][0-9]*$' "NOVA scenario $X printed lines ($N)"
    case $X in
        A|B|C|D) assert_match "$(head -3 "$WORK/nova_$X.txt")" "#$X ok=1 sum_ok=1" "NOVA scenario $X: round completes, sum correct" ;;
        F|G|H|I|J|P) assert_match "$(head -1 "$WORK/nova_$X.txt")" "^#$X ok=1 sum_ok=1 " "NOVA scenario $X: round completes with the coordinator, sum correct" ;;
    esac
    RES=$(python3 -I "$REF" --harness $X "$WORK/nova_$X.txt" 2>&1)
    assert_eq "$?" "0" "scenario $X: Python and NOVA lines identical"
    if [ "$X" = "A" ]; then
        assert_match "$RES" 'fingerprint MATCH' "scenario A: roster fingerprint identical"
    fi
    python3 -I "$REF" --dump $X > "$WORK/py_$X.txt" 2>&1
    case $X in
        E) assert_eq "$(grep -c '^CASE ' "$WORK/py_$X.txt")" "$N" "scenario E: same number of refusals"
           assert_eq "$N" "21" "scenario E: 21 refusal cases"
           assert_eq "$(grep -c '^CASE 1[12] ok=0 last=SA4_ABORT 5 7 bad_adv' "$WORK/nova_E.txt")" "2" "scenario E: own ADV with B or M altered refused (bad_adv)"
           assert_match "$(grep '^CASE 13 ' "$WORK/nova_E.txt")" 'ok=0 last=SA4_ABORT 5 7 bad_sig' "scenario E: peer ADV with M altered refused (bad_sig)"
           assert_match "$(grep '^CASE 14 ' "$WORK/nova_E.txt")" 'ok=0 last=SA4_ABORT 5 7 bad_line' "scenario E: v1 (6-token) ADV refused (bad_line)"
           assert_match "$(grep '^CASE 15 ' "$WORK/nova_E.txt")" 'ok=0 last=SA4_ABORT 5 7 unexpected' "scenario E: SET 2 right after the shares refused (no skipped check)"
           assert_match "$(grep '^CASE 16 ' "$WORK/nova_E.txt")" 'ok=0 last=SA4_ABORT 5 7 bad_line' "scenario E: 5-token (v4-sa2) SHARE refused (bad_line)"
           assert_match "$(grep '^CASE 17 ' "$WORK/nova_E.txt")" 'ok=0 last=SA4_ABORT 5 7 bad_set' "scenario E: ACCUSE naming the receiver refused (bad_set)"
           assert_match "$(grep '^CASE 18 ' "$WORK/nova_E.txt")" 'ok=0 last=SA4_ABORT 5 7 bad_complaint' "scenario E: two complaints from one soul refused (bad_complaint)"
           assert_match "$(grep '^CASE 19 ' "$WORK/nova_E.txt")" 'ok=0 last=SA4_ABORT 5 7 bad_set' "scenario E: final U2 with a complained-about soul refused (bad_set)"
           assert_match "$(grep '^CASE 20 ' "$WORK/nova_E.txt")" 'ok=0 last=SA4_ABORT 5 7 unexpected' "scenario E: ACCUSE twice refused (unexpected)"
           assert_eq "$(grep -c '^CASE 15 ok=0 last=SA4_ABORT 5 7 unexpected' "$WORK/py_E.txt")" "1" "scenario E: the Python soul refuses SET 2 in SHARED too" ;;
        *) assert_eq "$(grep -c -E '^(ADV|OUT) ' "$WORK/py_$X.txt")" "$N" "scenario $X: same number of lines" ;;
    esac
    case $X in
        F|G|H|I|J|P)
            assert_eq "$(grep -E '^(BLAME|EVIDENCE|#SUM) ' "$WORK/nova_$X.txt")" "$(grep -E '^(BLAME|EVIDENCE|#SUM) ' "$WORK/py_$X.txt")" "scenario $X: blame codes, why texts, evidence hashes and sum identical"
            assert_eq "$(grep -o ' state=[0-9]* u2=[0-9,]* counters=[0-9,]*' "$WORK/nova_$X.txt" | sed 's/ state=[0-9]*//')" "$(grep -o ' state=[0-9]* u2=[0-9,]* counters=[0-9,]*' "$WORK/py_$X.txt" | sed 's/ state=[0-9]*//')" "scenario $X: final U2 and verdict counters identical" ;;
    esac
done
assert_eq "$(grep -c '^BLAME ' "$WORK/nova_P.txt")" "0" "round P: nobody blamed"
assert_match "$(grep '^#P ' "$WORK/nova_P.txt")" 'counters=0,0,0,0' "round P: honest round runs no verdict crypto"
assert_eq "$(grep -c '^OUT SA4_COMPLAINT ' "$WORK/nova_P.txt")" "0" "round P: no complaint"
assert_match "$(grep '^BLAME ' "$WORK/nova_F.txt")" '^BLAME 4294967295 1 proven: sent soul 7 a share that fails the open check$' "round F: sender code 1"
assert_match "$(grep '^BLAME ' "$WORK/nova_G.txt")" '^BLAME 65536 2 proven: false complaint about soul 7 ' "round G: false complainer code 2"
assert_match "$(grep '^BLAME ' "$WORK/nova_H.txt")" '^BLAME 4294967295 3 did not open its share to soul 7 ' "round H: silent accused code 3"
assert_match "$(grep '^BLAME ' "$WORK/nova_I.txt")" '^BLAME 7 5 complaint about soul 4294967295 names a share it was not sent ' "round I: downlink victim code 5, no OPEN"
assert_eq "$(grep -c '^OUT SA4_OPEN ' "$WORK/nova_I.txt")" "0" "round I: the accused reveals nothing for a share it did not send"
assert_match "$(grep '^BLAME ' "$WORK/nova_J.txt")" '^BLAME 4294967295 4 share signature does not verify ' "round J: bad SHSIG code 4"
assert_match "$(grep '^EVIDENCE ' "$WORK/nova_F.txt")" '^EVIDENCE 4294967295 2682 a4aa559d2ffdf5d839e25d218b331c725eee5ad630eec8ca655c92dc68f6e556$' "round F: evidence matches the spec vector"
assert_match "$(grep '^EVIDENCE ' "$WORK/nova_G.txt")" '^EVIDENCE 65536 2349 cde1d077e3ec278046be151992ec1ce9482f1ad2c6982bec2ca191841c526c3b$' "round G: evidence matches the spec vector"
for H in H I J; do
    assert_eq "$(grep -c '^EVIDENCE ' "$WORK/nova_$H.txt")" "0" "round $H: no evidence (code not transferable)"
done
# The standalone judge on the NOVA coordinator's evidence files.
J=$(python3 -I "$REF" --judge "$WORK/evidence_F_4294967295.txt" --roster "$WORK/roster.txt" 2>&1)
assert_eq "$?" "0" "judge: round F evidence is valid"
assert_eq "$J" "verdict: sender 4294967295" "judge: round F blames the sender"
J=$(python3 -I "$REF" --judge "$WORK/evidence_G_65536.txt" --roster "$WORK/roster.txt" 2>&1)
assert_eq "$?" "0" "judge: round G evidence is valid"
assert_eq "$J" "verdict: complainer 65536" "judge: round G blames the complainer"
sed 's/^code 1$/code 2/' "$WORK/evidence_F_4294967295.txt" > "$WORK/ev_bad.txt"
J=$(python3 -I "$REF" --judge "$WORK/ev_bad.txt" --roster "$WORK/roster.txt" 2>&1)
assert_eq "$?" "2" "judge: evidence with the claimed code changed is refused"
assert_match "$J" '^invalid: ' "judge: prints invalid"
awk '/^open /{ c = substr($2, 1, 1); r = (c == "0") ? "1" : "0"; print "open " r substr($2, 2); next } { print }' "$WORK/evidence_F_4294967295.txt" > "$WORK/ev_bad2.txt"
J=$(python3 -I "$REF" --judge "$WORK/ev_bad2.txt" --roster "$WORK/roster.txt" 2>&1)
assert_eq "$?" "2" "judge: evidence with another one-time key is refused"
assert_match "$J" 'opening does not match e_pk' "judge: names the key mismatch"

# Differential run over perturbed rounds (only the reason text may differ).
python3 -I "$REPO_ROOT/tests/tools/sa4_cases.py" gen > "$WORK/cases.txt" 2>&1
assert_eq "$?" "0" "differential: case script generated"
NC=$(grep -c '^CASE ' "$WORK/cases.txt")
assert_match "$NC" '^[1-9][0-9]{2,}$' "differential: $NC cases"
"$NOVA" build "$REPO_ROOT/tests/tools/sa4_script.nova" -o "$WORK/script" >"$WORK/build2.log" 2>&1
assert_eq "$?" "0" "differential: NOVA driver builds"
# NOVA's read_file returns at most 4 MiB - 1 bytes: split at CASE lines.
awk -v d="$WORK" '/^CASE /{ if (n % 300 == 0) { f = sprintf("%s/cases_part_%02d.txt", d, n / 300) } n++ } { print > f }' "$WORK/cases.txt"
NP=0; PRC=0
: > "$WORK/cases_nova.txt"
for P in "$WORK"/cases_part_*.txt; do
    NP=$((NP + 1))
    SA4SCRIPT="$P" "$WORK/script" >> "$WORK/cases_nova.txt" 2>&1 || PRC=1
done
assert_eq "$PRC" "0" "differential: NOVA soul runs every case ($NP parts)"
SA4SCRIPT="$WORK/cases.txt" "$WORK/script" > "$WORK/whole.txt" 2>&1
assert_eq "$?" "2" "differential: the NOVA driver refuses a script at the read_file limit (no silent cut)"
python3 -I "$REPO_ROOT/tests/tools/sa4_cases.py" run "$WORK/cases.txt" > "$WORK/cases_py.txt" 2>&1
assert_eq "$?" "0" "differential: Python soul runs every case"
grep -v '^E ' "$WORK/cases_nova.txt" > "$WORK/cn.txt"
grep -v '^E ' "$WORK/cases_py.txt" > "$WORK/cp.txt"
assert_eq "$(grep -c '^C ' "$WORK/cn.txt")" "$NC" "differential: NOVA reported every case"
assert_eq "$(grep -c '^S .* ok=0 ' "$WORK/cn.txt")" "$(grep -c '^S .* ok=0 ' "$WORK/cp.txt")" "differential: same number of refused steps"
DIFF=$(diff "$WORK/cn.txt" "$WORK/cp.txt" | head -5)
assert_eq "$DIFF" "" "differential: every step identical (ok, state, round, output lines)"
CODES=$(grep -o 'SA4_ABORT [0-9]* [0-9]* [a-z0-9_]*' "$WORK/cn.txt" | awk '{print $4}' | sort -u | wc -l)
assert_match "$CODES" '^(2[0-9]|[3-9][0-9])$' "differential: $CODES distinct abort codes exercised"
# v4-sa3: a share that does not open or does not match the dealer's
# commitment is no longer an abort (bad_commit / bad_share) but a signed
# COMPLAINT; the accused answers a valid one with SA4_OPEN.
NCP=$(grep -c '^O SA4_COMPLAINT ' "$WORK/cn.txt")
assert_match "$NCP" '^[1-9][0-9]*$' "differential: $NCP COMPLAINT lines (content failures, incl. shares that miss the dealer's commitment)"
assert_eq "$NCP" "$(grep -c '^O SA4_COMPLAINT ' "$WORK/cp.txt")" "differential: same COMPLAINT lines on both sides"
NOP=$(grep -c '^O SA4_OPEN ' "$WORK/cn.txt")
assert_match "$NOP" '^[1-9][0-9]*$' "differential: $NOP OPEN lines (accused answers valid complaints)"
assert_eq "$(grep -c 'SA4_ABORT [0-9]* [0-9]* bad_commit' "$WORK/cn.txt")" "0" "differential: bad_commit is no longer emitted (content failures become complaints)"
assert_match "$(grep -c 'SA4_ABORT [0-9]* [0-9]* bad_complaint' "$WORK/cn.txt")" '^[1-9][0-9]*$' "differential: bad_complaint refusals exercised"
python3 -I "$REPO_ROOT/tests/tools/sa4_cases.py" check > "$WORK/check.txt" 2>&1
assert_eq "$?" "0" "differential: named v4-sa3 case outcomes (sa4_cases.py check)"
assert_match "$(tail -1 "$WORK/check.txt")" 'check: OK' "differential: case check reports OK"

# Negative control: change one hex digit of one masked Y word.
awk 'BEGIN{d=0} /^OUT SA4_Y / && d==0 { n=split($0,f," "); w=f[n]; c=substr(w,1,1); r=(c=="0")?"1":"0"; f[n]=r substr(w,2); s=f[1]; for(i=2;i<=n;i++) s=s" "f[i]; print s; d=1; next } {print}' \
    "$WORK/nova_A.txt" > "$WORK/tampered_A.txt"
assert_eq "$(cmp -s "$WORK/nova_A.txt" "$WORK/tampered_A.txt"; echo $?)" "1" "negative control: tampered copy differs"
python3 -I "$REF" --harness A "$WORK/tampered_A.txt" > "$WORK/neg.txt" 2>&1
assert_eq "$?" "1" "negative control: a tampered Y line is reported"
assert_match "$(cat "$WORK/neg.txt")" 'FIRST DIFF' "negative control: first difference printed"

summary "scenario_sa4_pyref"
