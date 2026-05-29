#!/usr/bin/env bash
# Scenario C -- Multi-source /learn.
#
# Two passes:
#   (1) TOPIC kind: scripts/learn.sh fever -> /learn fever -> KG grew.
#       If curl is blocked, write /tmp/crossengin_learn_fever.txt by hand
#       with a known word list, note "NETWORK SKIPPED" in the output, and
#       proceed -- /learn ingestion is what we're testing, not the fetch.
#   (2) FILE  kind: hand-write a 200-word corpus to /tmp/scenario_corpus.txt,
#       scripts/learn.sh on that file -> /learn /tmp/scenario_corpus.txt ->
#       KG grew (a new word from the corpus appears).

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0

it_section "scenario C: multi-source /learn"

# ---------- pass 1: TOPIC kind ------------------------------------------
TOPIC=fever
VOCAB_T="/tmp/crossengin_learn_${TOPIC}.txt"
TRIPLES_T="/tmp/crossengin_learn_${TOPIC}_triples.txt"
rm -f "$VOCAB_T" "$TRIPLES_T"

NET_OK=0
if curl -s --max-time 5 https://en.wikipedia.org >/dev/null 2>&1; then
    NET_OK=1
fi

if [ "$NET_OK" -eq 1 ]; then
    bash "$LEARN_SH" "$TOPIC" >/dev/null 2>&1 || true
fi
if [ ! -s "$VOCAB_T" ]; then
    echo "  ${C_YEL}NOTE${C_RST}  network blocked or fetch failed -- hand-writing fever vocab"
    cat > "$VOCAB_T" <<'EOF'
temperature
body
chills
sweating
shivering
inflammation
malaria
flu
rash
EOF
    cat > "$TRIPLES_T" <<'EOF'
fever|causal|chills
fever|causal|sweating
flu|causal|fever
EOF
fi
assert_file_exists "$VOCAB_T" "topic vocab cache written"

# Drive /learn fever in the chat. Capture KG count before/after by way of
# the /status output bracketing the /learn call.
OUT_T=$(run_chat '/status
/learn fever
/status')

# The /status line is "knowledge: N atoms in shared KG, M tentative ...".
# Take the first number from the FIRST and SECOND occurrences (one per /status).
BEFORE=$(echo "$OUT_T" | grep "knowledge:" | sed -n '1p' | grep -oE '[0-9]+' | head -1)
AFTER=$( echo "$OUT_T" | grep "knowledge:" | sed -n '2p' | grep -oE '[0-9]+' | head -1)
if [ -n "$BEFORE" ] && [ -n "$AFTER" ] && [ "$AFTER" -gt "$BEFORE" ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  KG grew via topic /learn: %s -> %s\n" "$BEFORE" "$AFTER"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  KG did not grow via topic /learn: '%s' -> '%s'\n" "$BEFORE" "$AFTER"
fi

# The /learn line should tag the source as [topic].
assert_match "$OUT_T" "learned about 'fever' \\[topic\\]" "topic kind tagged correctly in /learn output"

# ---------- pass 2: FILE kind -------------------------------------------
CORPUS=/tmp/scenario_corpus.txt
VOCAB_F="/tmp/crossengin_learn_scenario_corpus.txt"
TRIPLES_F="/tmp/crossengin_learn_scenario_corpus_triples.txt"
rm -f "$VOCAB_F" "$TRIPLES_F"

# Hand-write a ~200-word corpus containing a couple distinctive lemmas
# (kaleidoscope, mountaintop) that are NOT in the seed.
cat > "$CORPUS" <<'EOF'
A kaleidoscope sits on the mountaintop.
The mountaintop above the valley is covered with snow each winter.
At sunrise the kaleidoscope catches the light and casts colors on the rocks.
Travelers climb the mountaintop carrying lanterns and small mirrors.
They speak of the kaleidoscope as a marvel that the elders left behind.
The valley below the mountaintop holds villages that thrive in summer.
Children gather flowers near the path that leads up the mountaintop slope.
At dusk the kaleidoscope still glows with reflected starlight on the stone.
Old maps mark the mountaintop with strange symbols and faded letters.
The kaleidoscope rotates slightly when the wind passes across the peak.
Hikers say that the mountaintop air carries a faint sound like distant bells.
The kaleidoscope was first described in a journal kept by mountain monks.
At noon the kaleidoscope is brightest and the mountaintop is warm to touch.
Birds nest in the cracks near the mountaintop where the kaleidoscope stands.
Many drawings of the kaleidoscope hang in the village hall below the slopes.
Each season the mountaintop changes color and the kaleidoscope mirrors it.
Travelers who reach the mountaintop are given a token shaped like a small kaleidoscope.
Legends of the kaleidoscope endure long after the climbers descend the slope.
The mountaintop and the kaleidoscope are inseparable in the local stories.
Few have ever damaged the kaleidoscope or climbed past it to the true peak.
EOF
bash "$LEARN_SH" "$CORPUS" >/dev/null 2>&1 || true
assert_file_exists "$VOCAB_F" "file vocab cache written"

# Drive /learn $CORPUS.
OUT_F=$(run_chat '/status
/learn '"$CORPUS"'
/status
kaleidoscope')

BEFORE_F=$(echo "$OUT_F" | grep "knowledge:" | sed -n '1p' | grep -oE '[0-9]+' | head -1)
AFTER_F=$( echo "$OUT_F" | grep "knowledge:" | sed -n '2p' | grep -oE '[0-9]+' | head -1)
if [ -n "$BEFORE_F" ] && [ -n "$AFTER_F" ] && [ "$AFTER_F" -gt "$BEFORE_F" ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  KG grew via file /learn: %s -> %s\n" "$BEFORE_F" "$AFTER_F"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  KG did not grow via file /learn: '%s' -> '%s'\n" "$BEFORE_F" "$AFTER_F"
fi

assert_match "$OUT_F" "learned about '${CORPUS}' \\[file\\]" "file kind tagged correctly in /learn output"

# After learning the corpus, a follow-up "kaleidoscope" line should be
# comprehended (m>=1).
assert_match "$OUT_F" "perceive\\(m=[1-9][0-9]*,unk=" "kaleidoscope perceived after corpus /learn"

# Cleanup.
rm -f "$CORPUS" "$VOCAB_F" "$TRIPLES_F"

summary "scenario_c_learn"
