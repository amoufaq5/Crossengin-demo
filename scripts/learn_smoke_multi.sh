#!/usr/bin/env bash
# Multi-source smoke test for scripts/learn.sh (Phase 15 / Tier 2 item #3 +
# Phase P1.5 batch / RSS / directory dispatch).
#
# Exercises every source kind the /learn admin command now supports:
#   1. TOPIC -- the legacy behaviour (Wikipedia fetch).
#   2. URL   -- arbitrary http(s):// URL.
#   3. FILE  -- a local plain-text corpus on disk.
#   4. BATCH -- @/path/to/urls.txt (P1.5) one URL per line; combined +
#               per-URL caches.
#   5. RSS   -- rss:URL (P1.5) parse first 5 links from the feed.
#   6. DIR   -- dir:/path (P1.5) recursive .txt+.md walk.
#
# For each kind, drives scripts/learn.sh and asserts:
#   - the script exits 0,
#   - the expected /tmp/crossengin_learn_<tag>.txt was created,
#   - the file has >= the expected number of vocab lines (for offline kinds
#     the lower bound is exact; for fetch kinds we just assert non-empty).
#
# Network-dependent kinds (TOPIC, URL, RSS, BATCH-over-URLs) are SKIPPED with
# a clear note if curl cannot reach Wikipedia (sandbox / offline / DNS
# blocked), so the test still proves the FILE / BATCH-of-files / DIR paths
# end-to-end in an air-gapped environment.
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
    echo "[1/6] TOPIC: scripts/learn.sh fever"
    if "$LEARN" fever > /tmp/learn_smoke_topic.log 2>&1; then
        check_cache "TOPIC fever" "fever" 10
    else
        echo "FAIL: TOPIC fever: learn.sh exited non-zero"
        cat /tmp/learn_smoke_topic.log
        fail=$((fail + 1))
    fi
else
    echo "[1/6] TOPIC: SKIP (network unavailable)"
    skip=$((skip + 1))
fi

# --- (2) URL -----------------------------------------------------------------
URL="https://en.wikipedia.org/wiki/Aspirin"
URL_TAG="enwikipediaorg_wiki_Aspirin"
if [ "$NET_OK" -eq 1 ]; then
    echo
    echo "[2/6] URL: scripts/learn.sh $URL"
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
    echo "[2/6] URL: SKIP (network unavailable)"
    skip=$((skip + 1))
fi

# --- (3) FILE ----------------------------------------------------------------
echo
echo "[3/6] FILE: scripts/learn.sh /tmp/learn_smoke_corpus.txt"
CORPUS="/tmp/learn_smoke_corpus.txt"
# The trap covers every temp artefact produced from here on: per-kind logs
# (file/topic/url/batch/rss/dir) and the fixture inputs (test_urls.txt and
# the dir corpus). Caches under /tmp/crossengin_learn_* are LEFT in place so a
# subsequent chat session can /learn them by hand.
trap 'rm -rf "$CORPUS" /tmp/learn_smoke_topic.log /tmp/learn_smoke_url.log /tmp/learn_smoke_file.log /tmp/learn_smoke_batch.log /tmp/learn_smoke_rss.log /tmp/learn_smoke_dir.log /tmp/test_urls.txt /tmp/test_corpus_dir' EXIT

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

# --- (4) BATCH (@urls.txt) ---------------------------------------------------
# Builds a tiny urls.txt at /tmp/test_urls.txt with two Wikipedia URLs. If
# network is unavailable, the BATCH dispatch path itself still runs but the
# combined cache will be empty -- we only assert the dispatcher executed
# (kind=batch in the log + combined-cache file written, even if zero words).
echo
echo "[4/6] BATCH: scripts/learn.sh @/tmp/test_urls.txt"
cat > /tmp/test_urls.txt <<'EOF'
# Two example URLs for the batch smoke (Wikipedia stays HTTP-fetchable).
https://en.wikipedia.org/wiki/Aspirin
https://en.wikipedia.org/wiki/Fever
EOF
if "$LEARN" @/tmp/test_urls.txt > /tmp/learn_smoke_batch.log 2>&1; then
    if ! grep -q "kind=batch" /tmp/learn_smoke_batch.log; then
        echo "FAIL: BATCH: expected 'kind=batch' in log, did not see it"
        cat /tmp/learn_smoke_batch.log
        fail=$((fail + 1))
    else
        # The bash script derives tag=batch_test_urls (basename without .ext,
        # prefixed batch_). The combined cache is /tmp/crossengin_learn_<tag>.txt.
        if [ "$NET_OK" -eq 1 ]; then
            check_cache "BATCH @urls.txt" "batch_test_urls" 10
        else
            # No network -> file exists but empty; just assert presence.
            if [ -f "/tmp/crossengin_learn_batch_test_urls.txt" ]; then
                echo "PASS: BATCH (network down) created combined cache file (no fetch)"
                pass=$((pass + 1))
            else
                echo "FAIL: BATCH: combined cache file was not created"
                fail=$((fail + 1))
            fi
        fi
    fi
else
    echo "FAIL: BATCH @/tmp/test_urls.txt: learn.sh exited non-zero"
    cat /tmp/learn_smoke_batch.log
    fail=$((fail + 1))
fi

# --- (5) RSS -----------------------------------------------------------------
# Uses a well-known feed at Wikipedia (Special:RecentChanges has a feed view).
# If the network is unavailable, skip the whole step.
RSS_URL="https://en.wikipedia.org/wiki/Special:RecentChanges?format=feed"
RSS_TAG="rss_en_wikipedia_org"
if [ "$NET_OK" -eq 1 ]; then
    echo
    echo "[5/6] RSS: scripts/learn.sh rss:$RSS_URL"
    if "$LEARN" "rss:$RSS_URL" > /tmp/learn_smoke_rss.log 2>&1; then
        if ! grep -q "kind=rss" /tmp/learn_smoke_rss.log; then
            echo "FAIL: RSS: expected 'kind=rss' in log, did not see it"
            cat /tmp/learn_smoke_rss.log
            fail=$((fail + 1))
        else
            # Combined cache may or may not have words depending on which
            # links the feed exposed; just assert the file exists.
            if [ -f "/tmp/crossengin_learn_${RSS_TAG}.txt" ]; then
                echo "PASS: RSS: combined cache /tmp/crossengin_learn_${RSS_TAG}.txt exists"
                pass=$((pass + 1))
            else
                echo "FAIL: RSS: combined cache was not created"
                fail=$((fail + 1))
            fi
        fi
    else
        echo "FAIL: RSS $RSS_URL: learn.sh exited non-zero"
        cat /tmp/learn_smoke_rss.log
        fail=$((fail + 1))
    fi
else
    echo "[5/6] RSS: SKIP (network unavailable)"
    skip=$((skip + 1))
fi

# --- (6) DIR (dir:/path/) ----------------------------------------------------
# Builds a tiny corpus dir with two files (one .txt and one .md), then asserts
# the dispatcher walked both and wrote a non-empty combined cache.
echo
echo "[6/6] DIR: scripts/learn.sh dir:/tmp/test_corpus_dir/"
rm -rf /tmp/test_corpus_dir
mkdir -p /tmp/test_corpus_dir
cat > /tmp/test_corpus_dir/animals.txt <<'EOF'
The river flows through the valley. The valley contains many trees.
Trees produce oxygen. Oxygen is a gas. Gas has weight. Weight affects gravity.
Gravity pulls objects downward. Objects have mass. Mass is the amount of matter.
EOF
cat > /tmp/test_corpus_dir/plants.md <<'EOF'
# Plants notes
Plants grow upward. Roots absorb water. Water carries nutrients.
Leaves catch sunlight. Sunlight powers photosynthesis. Photosynthesis produces energy.
Energy is stored in glucose. Glucose feeds the plant. The plant feeds animals.
EOF
if "$LEARN" dir:/tmp/test_corpus_dir/ > /tmp/learn_smoke_dir.log 2>&1; then
    if ! grep -q "kind=dir" /tmp/learn_smoke_dir.log; then
        echo "FAIL: DIR: expected 'kind=dir' in log, did not see it"
        cat /tmp/learn_smoke_dir.log
        fail=$((fail + 1))
    else
        # tag=dir_test_corpus_dir (basename of the directory after stripping
        # trailing slash, prefixed dir_).
        check_cache "DIR dir:/tmp/test_corpus_dir/" "dir_test_corpus_dir" 10
    fi
else
    echo "FAIL: DIR dir:/tmp/test_corpus_dir/: learn.sh exited non-zero"
    cat /tmp/learn_smoke_dir.log
    fail=$((fail + 1))
fi

# Negative test: nonexistent file path must fail with exit 2 and not write any cache.
echo
echo "[bonus 1/4] FILE not-found must error out cleanly"
if "$LEARN" "/tmp/this_file_should_not_exist_$$" > /dev/null 2>&1; then
    echo "FAIL: missing-file path: learn.sh exited 0 (should be 2)"
    fail=$((fail + 1))
else
    echo "PASS: missing-file path returns non-zero"
    pass=$((pass + 1))
fi

# Negative test: @-prefix with a missing list file must exit 2.
echo "[bonus 2/4] BATCH @-prefix with missing list must error out"
if "$LEARN" "@/tmp/this_list_should_not_exist_$$" > /dev/null 2>&1; then
    echo "FAIL: missing batch-list path: learn.sh exited 0 (should be 2)"
    fail=$((fail + 1))
else
    echo "PASS: missing batch-list path returns non-zero"
    pass=$((pass + 1))
fi

# Negative test: dir: with a missing directory must exit 2.
echo "[bonus 3/4] DIR dir: with missing directory must error out"
if "$LEARN" "dir:/tmp/this_dir_should_not_exist_$$" > /dev/null 2>&1; then
    echo "FAIL: missing dir path: learn.sh exited 0 (should be 2)"
    fail=$((fail + 1))
else
    echo "PASS: missing dir path returns non-zero"
    pass=$((pass + 1))
fi

# Negative test: rss: with empty URL must exit 2.
echo "[bonus 4/4] RSS rss: with empty URL must error out"
if "$LEARN" "rss:" > /dev/null 2>&1; then
    echo "FAIL: empty rss URL: learn.sh exited 0 (should be 2)"
    fail=$((fail + 1))
else
    echo "PASS: empty rss URL returns non-zero"
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
