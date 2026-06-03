#!/usr/bin/env bash
# Scenario TTTT -- RSS / Atom feed ingestion into the KG (R25C).
#
# Companion to the unit suite in tests/unit/test_kg_rss_ingest.nova
# (~25 assertions on the pure parser layer with no IO). Here we drive
# the chat REPL through `/rss <feed_url>` end-to-end against a local
# file:// RSS fixture and assert:
#   1. /rss with no arg prints usage
#   2. /rss against a 3-item RSS file ingests 3 atoms into the KG
#   3. /rss against the SAME file again ingests 0 atoms (dedup on guid)
#   4. /rss against malformed XML reports a parse error gracefully
#   5. /rss against an empty file reports an error gracefully
#   6. /rss against a missing file reports a fetch error gracefully
#
# The chat command emits a one-line summary in the shape
#   RSS feed=<url> fetched=<bytes> parsed=<count> ingested=<count> err="<msg>"
# which is what we grep.

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

it_section "scenario TTTT: /rss command -- RSS/Atom ingestion into KG"

if [ ! -x "$CHAT" ]; then
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  CHAT binary not built at %s\n" "$CHAT"
    summary "scenario_tttt_rss_ingest"
    exit 1
fi

# Build a local RSS fixture (3 items, ASCII-only, RSS 2.0).
FIXTURE=/tmp/ce_int_rss_fixture_$$.xml
EMPTY=/tmp/ce_int_rss_empty_$$.xml
BAD=/tmp/ce_int_rss_bad_$$.xml
MISSING=/tmp/ce_int_rss_nope_$$.xml
trap 'rm -f "$FIXTURE" "$EMPTY" "$BAD" "$MISSING"' EXIT

cat > "$FIXTURE" <<'EOF'
<?xml version="1.0"?>
<rss version="2.0"><channel>
<title>R25C smoke feed</title>
<item><title>Alpha post</title><link>http://feed.test/alpha</link>
<description>The first item</description>
<pubDate>Mon, 01 Jan 2024 00:00:00 GMT</pubDate>
<guid>tttt-alpha-001</guid></item>
<item><title>Beta post</title><link>http://feed.test/beta</link>
<description>The second item</description>
<pubDate>Tue, 02 Jan 2024 00:00:00 GMT</pubDate>
<guid>tttt-beta-002</guid></item>
<item><title>Gamma post</title><link>http://feed.test/gamma</link>
<description>The third item</description>
<pubDate>Wed, 03 Jan 2024 00:00:00 GMT</pubDate>
<guid>tttt-gamma-003</guid></item>
</channel></rss>
EOF

: > "$EMPTY"

cat > "$BAD" <<'EOF'
<?xml version="1.0"?>
this is not even a feed, just some text and a stray < without close
EOF

# --- step 1: usage on empty arg -----------------------------------------
CHAT_OUT=$(run_chat '/rss')
assert_match "$CHAT_OUT" "usage: /rss" \
    "/rss with no arg prints usage"

# --- step 2: ingest the 3-item fixture ----------------------------------
# Run /rss twice in one chat session: first call should report
# ingested=3; second call should report ingested=0 (dedup).
CHAT_OUT=$(run_chat "/rss file://$FIXTURE
/rss file://$FIXTURE")

assert_match "$CHAT_OUT" "RSS feed=file://$FIXTURE fetched=[0-9]+ parsed=3 ingested=3" \
    "first /rss ingests 3 atoms from the fixture"
assert_match "$CHAT_OUT" "ingested=0" \
    "second /rss against same feed adds 0 atoms (dedup on guid)"

# --- step 3: malformed XML --------------------------------------------
CHAT_OUT=$(run_chat "/rss file://$BAD")
assert_match "$CHAT_OUT" "RSS feed=file://$BAD" \
    "/rss against malformed XML prints the RSS line"
assert_match "$CHAT_OUT" "err=\"[^\"]+\"" \
    "/rss against malformed XML reports a non-empty error"
assert_nomatch "$CHAT_OUT" "Segmentation fault" \
    "/rss against malformed XML does NOT segfault"

# --- step 4: empty file ------------------------------------------------
CHAT_OUT=$(run_chat "/rss file://$EMPTY")
assert_match "$CHAT_OUT" "RSS feed=file://$EMPTY" \
    "/rss against empty file prints the RSS line"
assert_match "$CHAT_OUT" "err=\"" \
    "/rss against empty file reports an error tag"

# --- step 5: missing file (fetch error) -------------------------------
CHAT_OUT=$(run_chat "/rss file://$MISSING")
assert_match "$CHAT_OUT" "RSS feed=file://$MISSING fetched=0" \
    "/rss against missing file reports fetched=0"
assert_match "$CHAT_OUT" "ingested=0" \
    "/rss against missing file reports ingested=0"

# --- step 6: unsupported scheme ----------------------------------------
CHAT_OUT=$(run_chat "/rss gopher://example.com/feed")
assert_match "$CHAT_OUT" "err=" \
    "/rss against unsupported scheme reports an error"

summary "scenario_tttt_rss_ingest"
