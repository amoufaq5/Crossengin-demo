#!/usr/bin/env bash
# Fetch a topic page and extract candidate vocabulary for the chat's
# `/learn <topic>` admin command.
#
# Default source is Wikipedia; override with LEARN_URL='...' for any URL that
# returns HTML or plain text. Output is /tmp/crossengin_learn_<topic>.txt --
# one candidate word per line, deduplicated, lowercased, alphabetic only.
#
# Usage:    scripts/learn.sh <topic>
#           LEARN_URL='https://...' scripts/learn.sh <topic>
#           LEARN_MAX=50 scripts/learn.sh <topic>   # words to keep (default 30)
#
# Then in bin/crossengin-chat:  /learn <topic>

set -uo pipefail

if [ $# -lt 1 ]; then
    echo "usage: $0 <topic>"
    echo "  fetches https://en.wikipedia.org/wiki/<topic> by default,"
    echo "  extracts candidate vocabulary, writes /tmp/crossengin_learn_<topic>.txt."
    echo "  Then in bin/crossengin-chat:  /learn <topic>"
    exit 1
fi

TOPIC="$1"
URL="${LEARN_URL:-https://en.wikipedia.org/wiki/$TOPIC}"
OUT="/tmp/crossengin_learn_${TOPIC}.txt"
MAX_WORDS="${LEARN_MAX:-30}"

echo "fetching: $URL"
if ! BODY=$(curl -sLf --max-time 15 -A "crossengin-learn/0.1" "$URL"); then
    echo "ERROR: fetch failed -- network blocked, URL bad, or page missing."
    echo "Workaround for sandboxed environments: write the words yourself:"
    echo "  printf 'word1\\nword2\\nword3\\n' > $OUT"
    echo "  then in chat: /learn $TOPIC"
    exit 2
fi

# Strip script/style blocks, then all tags, then HTML entities. Split into
# lowercase alphabetic words, filter to plausible lemmas (4-14 chars), then
# rank by occurrence count -- topic-relevant words appear most often on the
# page, while page-nav / boilerplate tends to appear once or twice.
echo "$BODY" \
    | sed -E 's|<script[^<]*</script>||g; s|<style[^<]*</style>||g; s/<[^>]*>/ /g; s/&[a-z]+;//g' \
    | tr -c '[:alpha:]' '\n' \
    | tr '[:upper:]' '[:lower:]' \
    | awk 'length($0) >= 4 && length($0) <= 14' \
    | sort \
    | uniq -c \
    | sort -rn \
    | head -n "$MAX_WORDS" \
    | awk '{print $2}' > "$OUT"

N=$(wc -l < "$OUT")
echo "wrote $N candidate words to $OUT"
echo
echo "Next: in bin/crossengin-chat type  /learn $TOPIC"
