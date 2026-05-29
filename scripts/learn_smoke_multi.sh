#!/usr/bin/env bash
# Multi-source smoke test for scripts/learn.sh (Phase 15 / Tier 2 item #3).
#
# Exercises all three source kinds the /learn admin command now supports:
#   1. TOPIC -- the legacy behaviour (Wikipedia fetch).
#   2. URL   -- arbitrary http(s):// URL.
#   3. FILE  -- a local plain-text corpus on disk.
#
# For each kind, drives scripts/learn.sh and asserts:
#   - the script exits 0,
#   - the expected /tmp/crossengin_learn_<tag>.txt was created,
#   - the file has >= 10 lines of candidate vocabulary.
#
# Network-dependent kinds (TOPIC, URL) are SKIPPED with a clear note if curl
# cannot reach Wikipedia (sandbox / offline / DNS blocked), so the test still
# proves the FILE path end-to-end in an air-gapped environment.
#
# Run:  bash scripts/learn_smoke_multi.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LEARN="$REPO_ROOT/scripts/learn.sh"

if [ ! -x "$LEARN" ]; then
    echo "ERROR: $LEARN not executable" >&2
    exit 2
fi

pass=0
fail=0
skip=0

# Probe network once. If curl fails to fetch Wikipedia in 5s, skip both
# fetch-flavoured cases and surface a clear note.
NET_OK=1
if ! curl -sLf --max-time 5 -A "crossengin-learn-smoke/0.1" \
        -o /dev/null "https://en.wikipedia.org/wiki/Aspirin"; then
    NET_OK=0
    echo "NOTE: curl cannot reach en.wikipedia.org in 5s -- TOPIC and URL tests will SKIP."
fi

# --- helper: assert /tmp/crossengin_learn_<tag>.txt has >= 10 lines ---------
check_cache() {
    local label="$1" tag="$2" min="$3"
    local cache="/tmp/crossengin_learn_${tag}.txt"
    if [ ! -f "$cache" ]; then
        echo "FAIL: $label: $cache not created"
        fail=$((fail + 1))
        return 1
    fi
    local n
    n=$(wc -l < "$cache")
    if [ "$n" -lt "$min" ]; then
        echo "FAIL: $label: $cache has $n lines (< $min)"
        fail=$((fail + 1))
        return 1
    fi
    echo "PASS: $label: $cache ($n words)"
    pass=$((pass + 1))
    return 0
}

# --- (1) TOPIC ---------------------------------------------------------------
if [ "$NET_OK" -eq 1 ]; then
    echo
    echo "[1/3] TOPIC: scripts/learn.sh fever"
    if "$LEARN" fever > /tmp/learn_smoke_topic.log 2>&1; then
        check_cache "TOPIC fever" "fever" 10
    else
        echo "FAIL: TOPIC fever: learn.sh exited non-zero"
        cat /tmp/learn_smoke_topic.log
        fail=$((fail + 1))
    fi
else
    echo "[1/3] TOPIC: SKIP (network unavailable)"
    skip=$((skip + 1))
fi

# --- (2) URL -----------------------------------------------------------------
URL="https://en.wikipedia.org/wiki/Aspirin"
URL_TAG="enwikipediaorg_wiki_Aspirin"
if [ "$NET_OK" -eq 1 ]; then
    echo
    echo "[2/3] URL: scripts/learn.sh $URL"
    if "$LEARN" "$URL" > /tmp/learn_smoke_url.log 2>&1; then
        # Confirm the bash script logged kind=url (smoke for the case branch).
        if ! grep -q "kind=url" /tmp/learn_smoke_url.log; then
            echo "FAIL: URL: expected 'kind=url' in log, did not see it"
            cat /tmp/learn_smoke_url.log
            fail=$((fail + 1))
        else
            check_cache "URL $URL" "$URL_TAG" 10
        fi
    else
        echo "FAIL: URL $URL: learn.sh exited non-zero"
        cat /tmp/learn_smoke_url.log
        fail=$((fail + 1))
    fi
else
    echo "[2/3] URL: SKIP (network unavailable)"
    skip=$((skip + 1))
fi

# --- (3) FILE ----------------------------------------------------------------
echo
echo "[3/3] FILE: scripts/learn.sh /tmp/learn_smoke_corpus.txt"
CORPUS="/tmp/learn_smoke_corpus.txt"
trap 'rm -f "$CORPUS" /tmp/learn_smoke_topic.log /tmp/learn_smoke_url.log /tmp/learn_smoke_file.log' EXIT

# A ~200-word toy corpus with a few "X is Y" / "X causes Y" / "X has Y"
# patterns so the triple extractor has something to chew on too. Mostly
# 4-14-char words so the vocab filter accepts them.
cat > "$CORPUS" <<'EOF'
The river flows through the valley. The valley contains many trees.
Trees produce oxygen. Oxygen is a gas. Gas has weight. Weight affects gravity.
Gravity pulls objects downward. Objects have mass. Mass is the amount of matter.
Matter is composed of atoms. Atoms have nuclei. Nuclei contain protons.
Protons have positive charge. Charge causes electrical forces. Forces move objects.
Objects accelerate when forces act upon them. Newton described these laws.
Light has speed. Speed is distance over time. Time can be measured.
Measurement requires units. Units include meters and seconds. Seconds count moments.
Moments build into hours. Hours build into days. Days build into years.
Years measure the journey of planets. Planets orbit stars. Stars produce light.
Light reveals colors. Colors come from wavelengths. Wavelengths describe waves.
Waves carry energy. Energy is conserved. Conservation is a fundamental law.
Laws describe behavior. Behavior can be predicted. Predictions guide research.
Research expands knowledge. Knowledge benefits everyone. Everyone learns something.
EOF

if "$LEARN" "$CORPUS" > /tmp/learn_smoke_file.log 2>&1; then
    if ! grep -q "kind=file" /tmp/learn_smoke_file.log; then
        echo "FAIL: FILE: expected 'kind=file' in log, did not see it"
        cat /tmp/learn_smoke_file.log
        fail=$((fail + 1))
    else
        # Expected tag from basename(/tmp/learn_smoke_corpus.txt) minus '.txt' = learn_smoke_corpus.
        check_cache "FILE $CORPUS" "learn_smoke_corpus" 10
    fi
else
    echo "FAIL: FILE $CORPUS: learn.sh exited non-zero"
    cat /tmp/learn_smoke_file.log
    fail=$((fail + 1))
fi

# Negative test: nonexistent file path must fail with exit 2 and not write any cache.
echo
echo "[bonus] FILE not-found must error out cleanly"
if "$LEARN" "/tmp/this_file_should_not_exist_$$" > /dev/null 2>&1; then
    echo "FAIL: missing-file path: learn.sh exited 0 (should be 2)"
    fail=$((fail + 1))
else
    echo "PASS: missing-file path returns non-zero"
    pass=$((pass + 1))
fi

# --- summary -----------------------------------------------------------------
echo
echo "---------------------------------------------------------------"
echo "learn_smoke_multi: pass=$pass fail=$fail skip=$skip"
if [ "$fail" -ne 0 ]; then
    exit 1
fi
exit 0
