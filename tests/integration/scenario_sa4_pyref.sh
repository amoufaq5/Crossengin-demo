#!/usr/bin/env bash
# Scenario sa4_pyref -- SecAgg v4: NOVA soul vs an independent Python soul
# (A2.3b).
#   scripts/sa4_ref.py is a second implementation of the v4 soul with its
#   own primitives (stdlib only). Driven with the same seeds, roster and
#   deterministic RNG as tests/sa4_harness.nova, it must produce exactly the
#   lines the NOVA soul produces (tests/tools/sa4_dump.nova), in five
#   scenarios:
#     A  N = 3, all honest                     (roster fingerprint too)
#     B  N = 5, one soul in U2 but not U3      (s-shares revealed)
#     C  N = 4, one soul drops after its ADV
#     D  N = 5, one soul in U3 but not U4      (no SIG3 from it)
#     E  11 refusals (abort line and code)
#   Every ADV/SHARE/Y/SIG3/REVEAL line carries a signature, ciphertext,
#   masked words or a share, so a match pins the KDFs, AEAD framing, Shamir
#   layout, PRG, mask signs, transcripts and reveal policy on both sides; E
#   compares abort lines. A tampered transcript must be reported as a
#   difference (negative control).
#   Then a differential run: tests/tools/sa4_cases.py builds 753 cases
#   (honest rounds perturbed in every phase: every abort code, forged shares
#   and signatures, low-order keys, set_input validation, and seeded random
#   mutations / moves / duplications / deletions of every line of four
#   rounds); the NOVA soul (tests/tools/sa4_script.nova) and the Python soul
#   must give the same ok / state / round / output lines at every step.
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

for X in A B C D E; do
    SA4DUMP=$X "$WORK/dump" > "$WORK/nova_$X.txt" 2>&1
    assert_eq "$?" "0" "NOVA scenario $X runs"
    case $X in
        E) N=$(grep -c '^CASE ' "$WORK/nova_$X.txt") ;;
        *) N=$(grep -c -E '^(ADV|OUT) ' "$WORK/nova_$X.txt") ;;
    esac
    assert_match "$N" '^[1-9][0-9]*$' "NOVA scenario $X printed lines ($N)"
    case $X in
        A|B|C|D) assert_match "$(head -3 "$WORK/nova_$X.txt")" "#$X ok=1 sum_ok=1" "NOVA scenario $X: round completes, sum correct" ;;
    esac
    RES=$(python3 -I "$REF" --harness $X "$WORK/nova_$X.txt" 2>&1)
    assert_eq "$?" "0" "scenario $X: Python and NOVA lines identical"
    if [ "$X" = "A" ]; then
        assert_match "$RES" 'fingerprint MATCH' "scenario A: roster fingerprint identical"
    fi
    python3 -I "$REF" --dump $X > "$WORK/py_$X.txt" 2>&1
    case $X in
        E) assert_eq "$(grep -c '^CASE ' "$WORK/py_$X.txt")" "$N" "scenario E: same number of refusals" ;;
        *) assert_eq "$(grep -c -E '^(ADV|OUT) ' "$WORK/py_$X.txt")" "$N" "scenario $X: same number of lines" ;;
    esac
done

# Differential run over perturbed rounds (only the reason text may differ).
python3 -I "$REPO_ROOT/tests/tools/sa4_cases.py" gen > "$WORK/cases.txt" 2>&1
assert_eq "$?" "0" "differential: case script generated"
NC=$(grep -c '^CASE ' "$WORK/cases.txt")
assert_match "$NC" '^[1-9][0-9]{2,}$' "differential: $NC cases"
"$NOVA" build "$REPO_ROOT/tests/tools/sa4_script.nova" -o "$WORK/script" >"$WORK/build2.log" 2>&1
assert_eq "$?" "0" "differential: NOVA driver builds"
SA4SCRIPT="$WORK/cases.txt" "$WORK/script" > "$WORK/cases_nova.txt" 2>&1
assert_eq "$?" "0" "differential: NOVA soul runs every case"
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

# Negative control: change one hex digit of one masked Y word.
awk 'BEGIN{d=0} /^OUT SA4_Y / && d==0 { n=split($0,f," "); w=f[n]; c=substr(w,1,1); r=(c=="0")?"1":"0"; f[n]=r substr(w,2); s=f[1]; for(i=2;i<=n;i++) s=s" "f[i]; print s; d=1; next } {print}' \
    "$WORK/nova_A.txt" > "$WORK/tampered_A.txt"
assert_eq "$(cmp -s "$WORK/nova_A.txt" "$WORK/tampered_A.txt"; echo $?)" "1" "negative control: tampered copy differs"
python3 -I "$REF" --harness A "$WORK/tampered_A.txt" > "$WORK/neg.txt" 2>&1
assert_eq "$?" "1" "negative control: a tampered Y line is reported"
assert_match "$(cat "$WORK/neg.txt")" 'FIRST DIFF' "negative control: first difference printed"

summary "scenario_sa4_pyref"
