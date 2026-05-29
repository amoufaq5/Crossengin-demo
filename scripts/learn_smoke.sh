#!/usr/bin/env bash
# Smoke test for the /learn triples-ingestion path.
#
# Writes a fake vocabulary file and a fake triples sidecar file under a unique
# topic name, then drives bin/crossengin-chat with `/learn <topic>` and checks
# the response line for the expected operator count. No network required.
#
# Run:  bash scripts/learn_smoke.sh
# Pre-req: ./bin/crossengin-chat must exist (NOVA_ROOT=... make install).
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHAT="$REPO_ROOT/bin/crossengin-chat"

if [ ! -x "$CHAT" ]; then
    echo "ERROR: $CHAT not built. Run: NOVA_ROOT=/path/to/NOVA make install" >&2
    exit 2
fi

TOPIC="smoke$$"
VOCAB="/tmp/crossengin_learn_${TOPIC}.txt"
TRIPS="/tmp/crossengin_learn_${TOPIC}_triples.txt"
trap 'rm -f "$VOCAB" "$TRIPS"' EXIT

# Two new words plus three triples. Subjects/objects mix seed atoms
# (fever, infection, virus, symptom, doctor, medicine) with one freshly-taught
# word (smokeword) and one bogus word (nonsense) -- the bogus pair must NOT
# produce an operator.
cat > "$VOCAB" <<'EOF'
smokeword
smoketwo
EOF
cat > "$TRIPS" <<'EOF'
fever|causal|infection
virus|causal|fever
fever|is_a|symptom
doctor|has|medicine
smokeword|is_a|fever
nonsense|is_a|fever
fever|is_a|nonsenseword
EOF

# Run the chat once and capture the /learn line.
OUT="$(printf '/learn %s\nquit\n' "$TOPIC" | "$CHAT" 2>&1)"
LINE="$(grep "learned about '${TOPIC}'" <<<"$OUT" || true)"

if [ -z "$LINE" ]; then
    echo "FAIL: /learn output not found"
    echo "----"; echo "$OUT"; echo "----"
    exit 1
fi
echo "$LINE"

# Expected: 5 operators -- the four where both endpoints exist (2 seed-seed
# triples: fever->infection, virus->fever; fever->symptom; doctor->medicine;
# plus smokeword->fever after vocab ingestion). The two referencing the
# bogus word must drop.
WORDS="$(grep -oE '[0-9]+ word\(s\)'    <<<"$LINE" | grep -oE '[0-9]+')"
OPS="$(  grep -oE '[0-9]+ operator\(s\)' <<<"$LINE" | grep -oE '[0-9]+')"

if [ "$WORDS" != "2" ];   then echo "FAIL: expected 2 words, got '$WORDS'"; exit 1; fi
if [ "${OPS:-0}" -lt 4 ]; then echo "FAIL: expected >=4 operators, got '${OPS:-0}'"; exit 1; fi
if [ "${OPS:-0}" -gt 5 ]; then echo "FAIL: expected <=5 operators (drop bogus), got '${OPS:-0}'"; exit 1; fi

echo "PASS: /learn ingested ${WORDS} word(s) and ${OPS} operator(s); bogus triples dropped."
