#!/usr/bin/env bash
# Fetch a topic page (or arbitrary URL, or local text file, or batch source)
# and extract candidate vocabulary + structural triples for the chat's
# `/learn <ARG>` admin command.
#
# Six source kinds are accepted:
#   TOPIC  scripts/learn.sh fever
#          -> fetches https://en.wikipedia.org/wiki/fever (override LEARN_URL=)
#   URL    scripts/learn.sh https://example.com/page
#          -> fetches the URL verbatim, derives tag from host+path
#   FILE   scripts/learn.sh /path/to/local.txt   (also ./rel or ../rel)
#          -> reads the file from disk, derives tag from the basename
#   BATCH  scripts/learn.sh @/path/to/urls.txt   (P1.5)
#          -> one URL per line; recursively ingests each and concatenates the
#             per-URL caches into a combined /tmp/crossengin_learn_batch_<tag>.txt
#   RSS    scripts/learn.sh rss:https://feeds.example.com/atom.xml   (P1.5)
#          -> fetches the feed, parses the first 5 <link>...</link> items, and
#             treats them as a BATCH. Tag is rss_<host>.
#   DIR    scripts/learn.sh dir:/path/to/corpus/   (P1.5)
#          -> walks the directory recursively for *.txt and *.md files; treats
#             each as a FILE corpus and concatenates them into a combined cache.
#
# In every kind the downstream pipeline is identical: BODY is split into
# lowercase alphabetic words for /tmp/crossengin_learn_<tag>.txt, and the same
# 5-word sliding-window extractor mines /tmp/crossengin_learn_<tag>_triples.txt.
# For BATCH/RSS/DIR the per-source caches stay on disk too, and an extra
# /tmp/crossengin_learn_batch_<tag>.txt (or _rss_<tag>.txt / _dir_<tag>.txt)
# concatenates them; the chat's `/learn <ARG>` ingests the combined cache and
# also re-derives each per-source tag to ingest its individual cache.
# The user types `/learn <ARG>` (the original argument) in the chat -- the chat
# re-derives the same <tag> via the matching logic in `_learn_tag`.
#
# Usage:    scripts/learn.sh <topic|url|file|@batch|rss:URL|dir:PATH>
#           LEARN_URL='https://...' scripts/learn.sh <topic>   # override URL only for topic-kind
#           LEARN_MAX=50 scripts/learn.sh <topic>              # words to keep (default 30)
#           LEARN_MAX_TRIPLES=30 scripts/learn.sh <topic>      # triples (default 20)
#           LEARN_RSS_MAX=5 scripts/learn.sh rss:URL           # RSS items to ingest (default 5)
#
# Then in bin/crossengin-chat:  /learn <ARG>

set -uo pipefail

if [ $# -lt 1 ]; then
    echo "usage: $0 <topic|url|file|@batch|rss:URL|dir:PATH>"
    echo "  TOPIC: fetches https://en.wikipedia.org/wiki/<topic> by default"
    echo "  URL:   fetches the URL verbatim (http:// or https:// prefix)"
    echo "  FILE:  reads from disk (/abs/path, ./rel, or ../rel)"
    echo "  BATCH: @/path/to/urls.txt (one URL per line, recursive per-URL ingest)"
    echo "  RSS:   rss:URL  fetches feed, ingests first 5 article links"
    echo "  DIR:   dir:/path/  walks .txt+.md files under the directory"
    echo "  writes /tmp/crossengin_learn_<tag>.txt + ..._<tag>_triples.txt."
    echo "  Then in bin/crossengin-chat:  /learn <ARG>"
    exit 1
fi

ARG="$1"
SELF="${BASH_SOURCE[0]}"

# --- helper: sanitise a free-form string into an alphanumeric tag (used by
# the BATCH / RSS / DIR derivers and the existing URL / FILE clauses). The
# rules MUST match the NOVA helpers `_learn_tag_url` / `_learn_tag_file` /
# `_learn_tag_batch` / `_learn_tag_rss` / `_learn_tag_dir` in
# examples/crossengin_chat.nova.
_tag_sanitise() {
    # Replace non-alnum/_/- with '_' and cap at 64 chars.
    echo "$1" | sed -E 's|[^a-zA-Z0-9_-]|_|g' | cut -c1-64
}

# ============================================================================
# BATCH / RSS / DIR: composite dispatchers (P1.5).
#
# Each one builds a per-source tag list, then drives the existing single-source
# pipeline (TOPIC/URL/FILE) recursively for each input. After all per-source
# caches have been written, we concatenate them into a single combined cache
# at /tmp/crossengin_learn_batch_<TAG>.txt so the chat's /learn @... line can
# do a single read for the combined corpus AND re-derive each per-source tag
# to also pull the individual cache.
# ============================================================================

# Dispatch the composite kinds early -- they never fall through to the URL/
# TOPIC/FILE block below. Returns after writing the combined cache.
case "$ARG" in
    @*)
        # ---- BATCH: one URL per line in a local file --------------------
        LIST_PATH="${ARG#@}"
        if [ -z "$LIST_PATH" ] || [ ! -f "$LIST_PATH" ]; then
            echo "ERROR: batch list file not found: '$LIST_PATH'" >&2
            exit 2
        fi
        LIST_BASE=$(basename "$LIST_PATH")
        LIST_STEM="${LIST_BASE%.*}"
        BATCH_TAG=$(_tag_sanitise "batch_${LIST_STEM}")
        COMBINED="/tmp/crossengin_learn_${BATCH_TAG}.txt"
        : > "$COMBINED"
        echo "batch: $LIST_PATH  (kind=batch tag=$BATCH_TAG)"
        n_urls=0
        n_ok=0
        # Read lines without losing the last when EOF lacks newline.
        while IFS= read -r url || [ -n "$url" ]; do
            # Trim leading/trailing whitespace; skip blanks and #-comments.
            url="${url#"${url%%[![:space:]]*}"}"
            url="${url%"${url##*[![:space:]]}"}"
            [ -z "$url" ] && continue
            case "$url" in \#*) continue ;; esac
            n_urls=$((n_urls + 1))
            echo "  [batch $n_urls] $url"
            # Recursive self-call -- the URL clause writes its own per-URL
            # cache files. We don't fail-fast on a single URL failure.
            if "$SELF" "$url" >/dev/null 2>&1; then
                URL_TAG=$(echo "$url" | sed -E 's|^https?://||; s|/|_|g; s|[^a-zA-Z0-9_-]||g' | cut -c1-64)
                URL_CACHE="/tmp/crossengin_learn_${URL_TAG}.txt"
                if [ -f "$URL_CACHE" ]; then
                    cat "$URL_CACHE" >> "$COMBINED"
                    n_ok=$((n_ok + 1))
                fi
            else
                echo "    (skip: fetch failed for $url)"
            fi
        done < "$LIST_PATH"
        # De-duplicate the combined word list (each URL's cache is already
        # ranked; the union just loses cross-URL frequency info, which is fine
        # for vocabulary ingestion).
        if [ -s "$COMBINED" ]; then
            sort -u "$COMBINED" -o "$COMBINED"
        fi
        N=$(wc -l < "$COMBINED")
        echo "batch: $n_ok/$n_urls URLs ingested, wrote $N combined words to $COMBINED"
        echo
        echo "Next: in bin/crossengin-chat type  /learn $ARG"
        exit 0
        ;;
    rss:*)
        # ---- RSS: fetch feed, extract <link>...</link> entries ----------
        FEED_URL="${ARG#rss:}"
        if [ -z "$FEED_URL" ]; then
            echo "ERROR: rss: requires a feed URL (e.g. rss:https://...)" >&2
            exit 2
        fi
        # Tag from host of the feed URL.
        FEED_HOST=$(echo "$FEED_URL" | sed -E 's|^https?://||; s|/.*$||; s|[^a-zA-Z0-9_-]|_|g' | cut -c1-32)
        RSS_TAG=$(_tag_sanitise "rss_${FEED_HOST}")
        COMBINED="/tmp/crossengin_learn_${RSS_TAG}.txt"
        : > "$COMBINED"
        echo "rss: $FEED_URL  (kind=rss tag=$RSS_TAG)"
        RSS_MAX="${LEARN_RSS_MAX:-5}"
        if ! FEED_BODY=$(curl -sLf --max-time 15 -A "crossengin-learn/0.1" "$FEED_URL"); then
            echo "ERROR: RSS fetch failed -- network blocked, URL bad, or feed missing." >&2
            exit 2
        fi
        # Lossy extraction: grep <link>...</link> (RSS 2.0) and href=URL on
        # <link href="..."> (Atom). Skip the feed's own self-link by dropping
        # the exact FEED_URL match.
        LINKS=$(echo "$FEED_BODY" \
            | tr '\n' ' ' \
            | grep -oE '<link[^>]*>[^<]*</link>|<link[^>]*href="[^"]+"' \
            | sed -E 's|<link[^>]*href="([^"]+)".*|\1|; s|<link[^>]*>([^<]+)</link>|\1|' \
            | sed -E 's|^[[:space:]]+||; s|[[:space:]]+$||' \
            | grep -E '^https?://' \
            | grep -vxF "$FEED_URL" \
            | head -n "$RSS_MAX")
        n_links=0
        n_ok=0
        for link in $LINKS; do
            n_links=$((n_links + 1))
            echo "  [rss $n_links] $link"
            if "$SELF" "$link" >/dev/null 2>&1; then
                URL_TAG=$(echo "$link" | sed -E 's|^https?://||; s|/|_|g; s|[^a-zA-Z0-9_-]||g' | cut -c1-64)
                URL_CACHE="/tmp/crossengin_learn_${URL_TAG}.txt"
                if [ -f "$URL_CACHE" ]; then
                    cat "$URL_CACHE" >> "$COMBINED"
                    n_ok=$((n_ok + 1))
                fi
            else
                echo "    (skip: fetch failed for $link)"
            fi
        done
        if [ -s "$COMBINED" ]; then
            sort -u "$COMBINED" -o "$COMBINED"
        fi
        N=$(wc -l < "$COMBINED")
        echo "rss: $n_ok/$n_links items ingested, wrote $N combined words to $COMBINED"
        echo
        echo "Next: in bin/crossengin-chat type  /learn $ARG"
        exit 0
        ;;
    dir:*)
        # ---- DIR: recursive walk of .txt / .md files --------------------
        DIR_PATH="${ARG#dir:}"
        if [ -z "$DIR_PATH" ] || [ ! -d "$DIR_PATH" ]; then
            echo "ERROR: directory not found: '$DIR_PATH'" >&2
            exit 2
        fi
        # Strip trailing slash before basename so basename(/a/b/) == 'b'.
        DIR_TRIM="${DIR_PATH%/}"
        DIR_BASE=$(basename "$DIR_TRIM")
        DIR_TAG=$(_tag_sanitise "dir_${DIR_BASE}")
        COMBINED="/tmp/crossengin_learn_${DIR_TAG}.txt"
        : > "$COMBINED"
        echo "dir: $DIR_PATH  (kind=dir tag=$DIR_TAG)"
        n_files=0
        n_ok=0
        # -print0 + read -d '' keeps spaces in paths intact.
        while IFS= read -r -d '' f; do
            n_files=$((n_files + 1))
            echo "  [dir $n_files] $f"
            if "$SELF" "$f" >/dev/null 2>&1; then
                FILE_TAG=$(basename "$f" | sed -E 's|\.[^.]+$||; s|[^a-zA-Z0-9_-]|_|g' | cut -c1-64)
                FILE_CACHE="/tmp/crossengin_learn_${FILE_TAG}.txt"
                if [ -f "$FILE_CACHE" ]; then
                    cat "$FILE_CACHE" >> "$COMBINED"
                    n_ok=$((n_ok + 1))
                fi
            else
                echo "    (skip: ingest failed for $f)"
            fi
        done < <(find "$DIR_PATH" -type f \( -name '*.txt' -o -name '*.md' \) -print0 2>/dev/null)
        if [ -s "$COMBINED" ]; then
            sort -u "$COMBINED" -o "$COMBINED"
        fi
        N=$(wc -l < "$COMBINED")
        echo "dir: $n_ok/$n_files files ingested, wrote $N combined words to $COMBINED"
        echo
        echo "Next: in bin/crossengin-chat type  /learn $ARG"
        exit 0
        ;;
esac

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
