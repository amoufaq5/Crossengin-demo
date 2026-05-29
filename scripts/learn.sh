#!/usr/bin/env bash
# Fetch a topic page (or arbitrary URL, or local text file) and extract
# candidate vocabulary + structural triples for the chat's `/learn <ARG>`
# admin command.
#
# Three source kinds are accepted:
#   TOPIC  scripts/learn.sh fever
#          -> fetches https://en.wikipedia.org/wiki/fever (override LEARN_URL=)
#   URL    scripts/learn.sh https://example.com/page
#          -> fetches the URL verbatim, derives tag from host+path
#   FILE   scripts/learn.sh /path/to/local.txt   (also ./rel or ../rel)
#          -> reads the file from disk, derives tag from the basename
#
# In all three cases the downstream pipeline is identical: BODY is split into
# lowercase alphabetic words for /tmp/crossengin_learn_<tag>.txt, and the same
# 5-word sliding-window extractor mines /tmp/crossengin_learn_<tag>_triples.txt.
# The user types `/learn <ARG>` (the original argument) in the chat -- the chat
# re-derives the same <tag> via the matching logic in `_learn_tag`.
#
# Usage:    scripts/learn.sh <topic|url|file>
#           LEARN_URL='https://...' scripts/learn.sh <topic>   # override URL only for topic-kind
#           LEARN_MAX=50 scripts/learn.sh <topic>              # words to keep (default 30)
#           LEARN_MAX_TRIPLES=30 scripts/learn.sh <topic>      # triples (default 20)
#
# Then in bin/crossengin-chat:  /learn <ARG>

set -uo pipefail

if [ $# -lt 1 ]; then
    echo "usage: $0 <topic|url|file>"
    echo "  TOPIC: fetches https://en.wikipedia.org/wiki/<topic> by default"
    echo "  URL:   fetches the URL verbatim (http:// or https:// prefix)"
    echo "  FILE:  reads from disk (/abs/path, ./rel, or ../rel)"
    echo "  writes /tmp/crossengin_learn_<tag>.txt + ..._<tag>_triples.txt."
    echo "  Then in bin/crossengin-chat:  /learn <ARG>"
    exit 1
fi

ARG="$1"

# Detect the source kind. Tag derivation MUST stay in lockstep with the NOVA
# helper `_learn_tag` in examples/crossengin_chat.nova -- the chat re-derives
# the tag from the user's argument to locate the cache files this script wrote.
case "$ARG" in
    http://*|https://*)
        KIND="url"
        URL="$ARG"
        TAG=$(echo "$ARG" | sed -E 's|^https?://||; s|/|_|g; s|[^a-zA-Z0-9_-]||g' | cut -c1-64)
        ;;
    /*|./*|../*)
        if [ -f "$ARG" ]; then
            KIND="file"
            FILE="$ARG"
            TAG=$(basename "$ARG" | sed -E 's|\.[^.]+$||; s|[^a-zA-Z0-9_-]|_|g' | cut -c1-64)
        else
            echo "ERROR: file not found: $ARG" >&2
            exit 2
        fi
        ;;
    *)
        KIND="topic"
        TOPIC="$ARG"
        URL="${LEARN_URL:-https://en.wikipedia.org/wiki/$TOPIC}"
        TAG="$TOPIC"
        ;;
esac

OUT="/tmp/crossengin_learn_${TAG}.txt"
TRIPLES="/tmp/crossengin_learn_${TAG}_triples.txt"
MAX_WORDS="${LEARN_MAX:-30}"
MAX_TRIPLES="${LEARN_MAX_TRIPLES:-20}"

# Acquire BODY: from disk for FILE-kind, from curl for URL/TOPIC.
if [ "$KIND" = "file" ]; then
    echo "reading: $FILE  (kind=file tag=$TAG)"
    if ! BODY=$(cat "$FILE"); then
        echo "ERROR: failed to read $FILE" >&2
        exit 2
    fi
else
    echo "fetching: $URL  (kind=$KIND tag=$TAG)"
    if ! BODY=$(curl -sLf --max-time 15 -A "crossengin-learn/0.1" "$URL"); then
        echo "ERROR: fetch failed -- network blocked, URL bad, or page missing."
        echo "Workaround for sandboxed environments: write the words yourself:"
        echo "  printf 'word1\\nword2\\nword3\\n' > \"$OUT\""
        echo "  then in chat: /learn \"$ARG\""
        exit 2
    fi
fi

# Strip script/style blocks, then all tags, then HTML entities. Split into
# lowercase alphabetic words, filter to plausible lemmas (4-14 chars), then
# rank by occurrence count -- topic-relevant words appear most often on the
# page, while page-nav / boilerplate tends to appear once or twice. For FILE
# kind the HTML strip is a no-op (plain text passes through cleanly).
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
echo "wrote $N words to $OUT"

# ---- structural triples ---------------------------------------------------
# In addition to vocabulary, mine simple surface patterns from the same body
# so /learn can ingest reasoning operators (ADR-0031), not just words. The
# extractor is intentionally permissive -- /learn drops any triple whose
# subject or object is not already a known atom, so noise is harmless.
#
# Patterns (lowercase, 4-14 alpha chars on each side, same as vocabulary):
#   "X causes Y" / "X caused Y" / "X cause Y"      -> X|causal|Y
#   "X is a Y" / "X is an Y" / "X is the Y"        -> X|is_a|Y
#   "X is Y"                                       -> X|is_a|Y
#   "X has Y" / "X have Y"                         -> X|has|Y
# We also accept a single bridge word (e.g. "may", "can", "often", "usually",
# "the") between the relation and Y so we catch real prose: "X causes the Y",
# "X may cause Y", "X is often Y" all map to the same triple.
#
# Pipeline: strip HTML, lowercase, fold whitespace, then awk over a 5-word
# sliding window. We don't try to be smart -- false positives are fine because
# the chat-side filter is the ground truth.
# Two passes over the cleaned token stream:
#   pass 1: count word occurrences (used to rank candidate triples -- topic-
#           relevant words appear more often than incidental boilerplate).
#   pass 2: extract candidate triples via sliding window, then sort by
#           freq(S)+freq(O) descending and keep top $MAX_TRIPLES.
TOKENS=$(mktemp)
trap 'rm -f "$TOKENS"' EXIT
echo "$BODY" \
    | sed -E 's|<script[^<]*</script>||g; s|<style[^<]*</style>||g; s/<[^>]*>/ /g; s/&[a-z]+;//g' \
    | tr '[:upper:]' '[:lower:]' \
    | tr -c '[:alpha:]' ' ' \
    | tr -s ' ' '\n' > "$TOKENS"

awk -v MAX="$MAX_TRIPLES" '
        BEGIN {
            # Determiners + small filler that may sit between verb and Y.
            det["a"]=1; det["an"]=1; det["the"]=1
            bridge["may"]=1; bridge["can"]=1; bridge["could"]=1; bridge["might"]=1
            bridge["often"]=1; bridge["usually"]=1; bridge["sometimes"]=1
            bridge["also"]=1; bridge["typically"]=1; bridge["generally"]=1
            bridge["not"]=1; bridge["always"]=1; bridge["thus"]=1
            bridge["the"]=1; bridge["a"]=1; bridge["an"]=1
            bridge["in"]=1; bridge["of"]=1; bridge["from"]=1
            is_form["is"]=1; is_form["are"]=1; is_form["be"]=1
            is_form["was"]=1; is_form["were"]=1
            cause_form["causes"]=1; cause_form["caused"]=1; cause_form["cause"]=1
            cause_form["causing"]=1
            has_form["has"]=1; has_form["have"]=1; has_form["had"]=1
        }
        function emit(s, r, o,    key, score) {
            if (length(s) < 4 || length(s) > 14) return
            if (length(o) < 4 || length(o) > 14) return
            if (s == o) return
            key = s "|" r "|" o
            if (key in seen) return
            seen[key] = 1
            score = freq[s] + freq[o]
            # rank-prefixed line so a single sort -rn -k1 brings best to top.
            cand[++n] = score "\t" key
        }
        # First pass over the file: count word occurrences.
        FNR == NR { freq[$0]++; next }
        # Second pass: slide a 6-word window and extract candidate triples.
        {
            w[5]=w[4]; w[4]=w[3]; w[3]=w[2]; w[2]=w[1]; w[1]=w[0]; w[0]=$0
            # --- causal: "X causes Y", and with 1-2 word bridges -----------
            if (w[1] in cause_form)                       emit(w[2], "causal", w[0])
            if ((w[2] in cause_form) && (w[1] in bridge)) emit(w[3], "causal", w[0])
            if ((w[3] in cause_form) && (w[2] in bridge) && (w[1] in bridge))
                                                          emit(w[4], "causal", w[0])
            # --- "X caused by Y" -> Y|causal|X (passive reversal) ----------
            if (w[2] == "caused" && w[1] == "by")         emit(w[0], "causal", w[3])
            # --- is_a: "X is Y", "X is <det> Y", "X is <bridge> Y" --------
            if ((w[1] in is_form) && !(w[0] in det))      emit(w[2], "is_a", w[0])
            if ((w[2] in is_form) && (w[1] in det))       emit(w[3], "is_a", w[0])
            if ((w[2] in is_form) && (w[1] in bridge) && !(w[1] in det)) \
                                                          emit(w[3], "is_a", w[0])
            # "X may be Y" / "X can be Y" -> X|is_a|Y -----------------------
            if ((w[2] in bridge) && (w[1] in is_form))    emit(w[3], "is_a", w[0])
            # --- has: "X has Y", "X have Y", with optional bridge ---------
            if (w[1] in has_form)                         emit(w[2], "has",  w[0])
            if ((w[2] in has_form) && (w[1] in bridge))   emit(w[3], "has",  w[0])
        }
        END {
            for (i = 1; i <= n; i++) print cand[i]
        }
    ' "$TOKENS" "$TOKENS" \
    | sort -rn -k1,1 \
    | head -n "$MAX_TRIPLES" \
    | cut -f2 > "$TRIPLES"

T=$(wc -l < "$TRIPLES")
echo "wrote $T triples to $TRIPLES"
echo
echo "Next: in bin/crossengin-chat type  /learn $ARG"
