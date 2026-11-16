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

# URL kind: since R41 (ADR r41 sec. 5) /learn http(s)://... fetches LIVE in
# process; URL cache files written by scripts/learn.sh are only read via
# @batch. So this serves a tiny page from a loopback http.server and grants
# the autonomous_fetch capability the fetch is gated on (non-interactive
# runs would otherwise decline the approval prompt). The URL carries an
# explicit port, which the fetch gate used to refuse.
URL_VOCAB=""
if command -v python3 >/dev/null 2>&1; then
    URL_SRV_DIR=$(mktemp -d /tmp/ce_int_admin_url_XXXXXX)
    cat > "$URL_SRV_DIR/adminurl.html" <<'HTML'
<html><body><p>Adminword quokkas are marsupials. Quokkas live on islands.</p></body></html>
HTML
    URL_PORT=$(( 32000 + (RANDOM % 1000) ))
    # http.server with the request's Host header recorded, so the test can
    # check that the explicit port reaches it (RFC 9110 7.2).
    cat > "$URL_SRV_DIR/srv.py" <<'PY'
import http.server, sys
class H(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        with open("host.txt", "w") as f:
            f.write(self.headers.get("Host", ""))
        super().do_GET()
    def log_message(self, *a):
        pass
http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
PY
    ( cd "$URL_SRV_DIR" && exec python3 srv.py "$URL_PORT" ) >/dev/null 2>&1 &
    URL_SRV_PID=$!
    i=0
    while [ $i -lt 50 ]; do
        if python3 -c "import socket,sys; s=socket.socket(); s.settimeout(0.2); sys.exit(s.connect_ex(('127.0.0.1', $URL_PORT)))" 2>/dev/null; then break; fi
        sleep 0.1; i=$((i+1))
    done
    URL_ARG="http://127.0.0.1:${URL_PORT}/adminurl.html"
    URL_CAPS=$(mktemp /tmp/ce_int_caps.XXXXXX)
    printf 'autonomous_fetch=allow\n' > "$URL_CAPS"
    OUT=$(CE_CAPS_CONF="$URL_CAPS" run_chat "/learn $URL_ARG")
    rm -f "$URL_CAPS"
    kill "$URL_SRV_PID" 2>/dev/null; wait "$URL_SRV_PID" 2>/dev/null
    URL_HOST_SEEN=$(cat "$URL_SRV_DIR/host.txt" 2>/dev/null)
    rm -rf "$URL_SRV_DIR"
    assert_match "$OUT" "learned from $URL_ARG \\[url\\]: [1-9][0-9]* word" "/learn URL (live, loopback with port) tagged as [url]"
    assert_eq "$URL_HOST_SEEN" "127.0.0.1:${URL_PORT}" "Host header carries the non-default port"
else
    printf "  SKIP  python3 not installed -- /learn URL live check skipped\n"
fi

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
assert_match "$OUT" "  seed +584" "/meta shows the seed source row at boot"
assert_match "$OUT" "poll\\(s\\) total" "/meta shows the poll count footer"

summary "admin_learn_meta"
