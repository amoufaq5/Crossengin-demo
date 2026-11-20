#!/usr/bin/env bash
# Scenario sroster -- SecAgg v4 roster and identity keys (A2.1).
#   1. scripts/secagg_keygen.sh writes a 0600 seed and a 0644 public key,
#      prints a roster line, and refuses to overwrite, to follow a planted
#      symlink, or to take a bad id or name.
#   2. examples/secagg_roster_check.nova loads a roster built from those
#      lines: N, t, x and a fingerprint that an independent Python hash of
#      the canonical text reproduces.
#   3. Each soul's seed maps to its own roster entry; a 0644 seed, a
#      symlinked seed, a seed not in the roster, a group-writable roster and
#      a tampered roster line are refused.
#   4. openssl agrees: the public key in the roster is the one openssl
#      derives from the seed.

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0
it_section "scenario sroster: SecAgg v4 roster + identity keys"

skip() {
    echo "SKIP: $1"
    if [ "${CE_IT_STRICT:-0}" = "1" ]; then exit 1; fi
    exit 0
}

NOVA="${NOVA_ROOT:-$HOME/NOVA}/nova"
[ -x "$NOVA" ] || skip "NOVA launcher not found at $NOVA"
command -v openssl >/dev/null 2>&1 || skip "openssl not on PATH"
command -v python3 >/dev/null 2>&1 || skip "python3 not on PATH"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
chmod 700 "$WORK"
KG="$REPO_ROOT/scripts/secagg_keygen.sh"

"$NOVA" build "$REPO_ROOT/examples/secagg_roster_check.nova" -o "$WORK/check" >"$WORK/build.log" 2>&1
assert_eq "$?" "0" "roster checker builds"

# 1. key generation
L1=$(bash "$KG" "$WORK/s1" 5 alpha | sed -n 's/^roster line: //p')
L2=$(bash "$KG" "$WORK/s2" 17 beta | sed -n 's/^roster line: //p')
L3=$(bash "$KG" "$WORK/s3" 40 gamma | sed -n 's/^roster line: //p')
L4=$(bash "$KG" "$WORK/s4" 41 delta | sed -n 's/^roster line: //p')
assert_match "$L1" '^5 alpha [0-9a-f]{64}$' "keygen prints a roster line"
assert_eq "$(stat -c '%a %s' "$WORK/s1.priv")" "600 32" "seed is 0600, 32 bytes"
assert_eq "$(stat -c '%a %s' "$WORK/s1.pub")" "644 32" "public key is 0644, 32 bytes"
assert_eq "$(od -An -vtx1 "$WORK/s1.pub" | tr -d ' \n')" "${L1##* }" "roster line carries the .pub bytes"
bash "$KG" "$WORK/s1" 5 alpha >/dev/null 2>&1
assert_eq "$?" "1" "keygen refuses to overwrite"
ln -s "$WORK/victim" "$WORK/s9.priv"
bash "$KG" "$WORK/s9" 9 nine >/dev/null 2>&1
assert_eq "$?" "1" "keygen refuses a planted symlink"
assert_eq "$([ -e "$WORK/victim" ] && echo created || echo absent)" "absent" "symlink target not created"
bash "$KG" "$WORK/s8" 4294967296 big >/dev/null 2>&1
assert_eq "$?" "2" "keygen refuses id 2^32"
bash "$KG" "$WORK/s8" 8 'bad name' >/dev/null 2>&1
assert_eq "$?" "2" "keygen refuses a bad name"

# openssl derives the same public key from the seed
SEEDHEX=$(od -An -vtx1 "$WORK/s2.priv" | tr -d ' \n')
printf '302e020100300506032b657004220420%s' "$SEEDHEX" | xxd -r -p > "$WORK/s2.der" 2>/dev/null \
  || python3 -I -c "import sys; sys.stdout.buffer.write(bytes.fromhex(sys.argv[1]))" "302e020100300506032b657004220420$SEEDHEX" > "$WORK/s2.der"
OSSL=$(openssl pkey -inform DER -in "$WORK/s2.der" -pubout -outform DER 2>/dev/null | tail -c 32 | od -An -vtx1 | tr -d ' \n')
assert_eq "$OSSL" "${L2##* }" "openssl derives the roster key from the seed"

# 2. roster
R="$WORK/roster"
{ echo "# demo roster"; echo "crossengin-secagg-roster v1"; echo "$L1"; echo "$L2"; echo "$L3"; echo "$L4"; } > "$R"
chmod 644 "$R"
OUT=$(CE_SECAGG_ROSTER="$R" "$WORK/check" 2>&1); RC=$?
assert_eq "$RC" "0" "roster accepted"
assert_match "$OUT" '^roster ok: n=4 t=3$' "n=4, t=3"
assert_match "$OUT" 'soul id=40 name=gamma x=3' "gamma has x=3"
assert_match "$OUT" 'self: CE_SECAGG_ID_KEY not set' "no identity without CE_SECAGG_ID_KEY"
FP=$(echo "$OUT" | sed -n 's/^fingerprint: //p')
PYFP=$(python3 -I - "$R" <<'PY'
import hashlib, sys
lines = [l.strip() for l in open(sys.argv[1]).read().split("\n")]
lines = [l for l in lines if l and not l.startswith("#")]
canon = lines[0] + "\n" + "".join(" ".join(l.split()) + "\n" for l in lines[1:])
print(hashlib.sha256(canon.encode()).hexdigest())
PY
)
assert_eq "$FP" "$PYFP" "fingerprint matches an independent Python hash"

# 3. identities
for pair in s1:alpha s2:beta s3:gamma s4:delta; do
    f="${pair%%:*}"; n="${pair##*:}"
    OUT=$(CE_SECAGG_ROSTER="$R" CE_SECAGG_ID_KEY="$WORK/$f.priv" "$WORK/check" 2>&1)
    assert_match "$OUT" "^self: id=[0-9]+ name=$n " "$f.priv is $n"
done
cp "$WORK/s1.priv" "$WORK/loose.priv"; chmod 644 "$WORK/loose.priv"
OUT=$(CE_SECAGG_ROSTER="$R" CE_SECAGG_ID_KEY="$WORK/loose.priv" "$WORK/check" 2>&1); RC=$?
assert_eq "$RC" "1" "0644 seed refused"
assert_match "$OUT" 'group/others' "0644 seed: reason printed"
ln -s "$WORK/s1.priv" "$WORK/link.priv"
OUT=$(CE_SECAGG_ROSTER="$R" CE_SECAGG_ID_KEY="$WORK/link.priv" "$WORK/check" 2>&1); RC=$?
assert_eq "$RC" "1" "symlinked seed refused"
bash "$KG" "$WORK/s5" 99 epsilon >/dev/null
OUT=$(CE_SECAGG_ROSTER="$R" CE_SECAGG_ID_KEY="$WORK/s5.priv" "$WORK/check" 2>&1); RC=$?
assert_eq "$RC" "1" "seed not in the roster refused"
assert_match "$OUT" 'not in the roster' "unknown key: reason printed"
cp "$R" "$WORK/roster.gw"; chmod 664 "$WORK/roster.gw"
OUT=$(CE_SECAGG_ROSTER="$WORK/roster.gw" "$WORK/check" 2>&1); RC=$?
assert_eq "$RC" "1" "group-writable roster refused"
sed 's/^17 beta/17 beta2/' "$R" > "$WORK/roster.t"; chmod 644 "$WORK/roster.t"
OUT=$(CE_SECAGG_ROSTER="$WORK/roster.t" "$WORK/check" 2>&1)
FP2=$(echo "$OUT" | sed -n 's/^fingerprint: //p')
assert_eq "$([ -n "$FP2" ] && [ "$FP2" != "$FP" ] && echo differs)" "differs" "edited roster has a different fingerprint"
{ echo "crossengin-secagg-roster v1"; echo "$L2"; echo "$L1"; } > "$WORK/roster.o"; chmod 644 "$WORK/roster.o"
OUT=$(CE_SECAGG_ROSTER="$WORK/roster.o" "$WORK/check" 2>&1); RC=$?
assert_eq "$RC" "1" "out-of-order ids refused"
OUT=$(env -u CE_SECAGG_ROSTER "$WORK/check" 2>&1); RC=$?
assert_eq "$RC" "1" "missing CE_SECAGG_ROSTER refused"

summary "scenario_sroster"
