#!/usr/bin/env bash
# Admin commands -- /learn (TOPIC/URL/FILE source-kind tagging) and /meta.

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0

# -------------------- /learn no arg --------------------
it_section "admin: /learn no arg"

OUT=$(run_chat '/learn')
assert_match "$OUT" "/learn needs an argument" "/learn with no arg prints usage hint"

# -------------------- /learn TOPIC --------------------
it_section "admin: /learn TOPIC kind"

# Pre-populate a tiny topic cache so we don't depend on the network.
TOPIC_TAG=admintopic$$
TOPIC_VOCAB="/tmp/crossengin_learn_${TOPIC_TAG}.txt"
TOPIC_TRIPS="/tmp/crossengin_learn_${TOPIC_TAG}_triples.txt"
trap 'rm -f "$TOPIC_VOCAB" "$TOPIC_TRIPS" "$URL_VOCAB" "$FILE_VOCAB" "$FILE_TRIPS" /tmp/scenario_corpus_admin_$$.txt' EXIT

cat > "$TOPIC_VOCAB" <<'EOF'
zoophyte
quasimoto
heliotrope
EOF
cat > "$TOPIC_TRIPS" <<'EOF'
fever|causal|infection
EOF

OUT=$(run_chat "/learn $TOPIC_TAG")
assert_match "$OUT" "learned about '$TOPIC_TAG' \\[topic\\]" "/learn TOPIC tagged as [topic]"

# -------------------- /learn URL --------------------
it_section "admin: /learn URL kind"

# URL kind: argument starts with http(s)://. The tag is derived from
# host+path by scripts/learn.sh AND by the chat helper _learn_tag_url
# (they must agree). Use a fully-controlled fake URL so no network is hit;
# pre-populate the cache file at the derived tag.
URL_ARG='https://example.invalid/wiki/Adminurl'
URL_TAG=$(echo "$URL_ARG" | sed -E 's|^https?://||; s|/|_|g; s|[^a-zA-Z0-9_-]||g' | cut -c1-64)
URL_VOCAB="/tmp/crossengin_learn_${URL_TAG}.txt"
URL_TRIPS="/tmp/crossengin_learn_${URL_TAG}_triples.txt"
cat > "$URL_VOCAB" <<'EOF'
adminword
EOF

OUT=$(run_chat "/learn $URL_ARG")
assert_match "$OUT" "learned about '$URL_ARG' \\[url\\]" "/learn URL tagged as [url]"

# -------------------- /learn FILE --------------------
it_section "admin: /learn FILE kind"

FILE_ARG=/tmp/scenario_corpus_admin_$$.txt
cat > "$FILE_ARG" <<'EOF'
The cobalt mountain whispers ancient stories
to those who climb its windward face.
EOF
bash "$LEARN_SH" "$FILE_ARG" >/dev/null 2>&1 || true
FILE_TAG=$(basename "$FILE_ARG" | sed -E 's|\.[^.]+$||; s|[^a-zA-Z0-9_-]|_|g' | cut -c1-64)
FILE_VOCAB="/tmp/crossengin_learn_${FILE_TAG}.txt"
FILE_TRIPS="/tmp/crossengin_learn_${FILE_TAG}_triples.txt"

OUT=$(run_chat "/learn $FILE_ARG")
assert_match "$OUT" "learned about '$FILE_ARG' \\[file\\]" "/learn FILE tagged as [file]"

# -------------------- /meta --------------------
it_section "admin: /meta"

OUT=$(run_chat '/meta')
assert_match "$OUT" "meta-observer status" "/meta prints status header"
assert_match "$OUT" "  seed +572" "/meta shows the seed source row at boot"
assert_match "$OUT" "poll\\(s\\) total" "/meta shows the poll count footer"

summary "admin_learn_meta"
