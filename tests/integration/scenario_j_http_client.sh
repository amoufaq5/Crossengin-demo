#!/usr/bin/env bash
# Scenario J -- in-process plain HTTP/1.1 client loopback.
#
# Phase / P1.4: the new pure-NOVA http_client (src/io/transducers/http_client.nova)
# replaces the curl shim for `http://` URLs. This scenario proves it
# end-to-end against a real local server: python -m http.server on a
# per-run port. The test artifact is a tiny on-the-fly NOVA program that
# calls if_dispatch_transport / http_get against 127.0.0.1, prints the
# status + body length + a known body marker.
#
# KNOWN LIMITATIONS (sandbox-shaped, same as scenario_g):
#   * NOVA socket builtins are blocking. The server gets a generous
#     startup grace; we kill if either side hangs past the deadline.
#   * If python3 (or its http.server) is unavailable, the script prints
#     a clear SKIP and still passes -- CI elsewhere does the real run.
#   * If `socket(2,1,0)` returns -1 (sandbox denies AF_INET entirely),
#     the script also SKIPs cleanly.

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

it_section "scenario J: plain-HTTP client loopback (python http.server <- NOVA http_get)"

# Pre-flight 1: python3.
if ! command -v python3 >/dev/null 2>&1; then
    printf "  ${C_YEL}SKIP${C_RST}  python3 not installed -- scenario_j skipped\n"
    PASS=$((PASS+1))
    summary "scenario_j_http_client"
    exit $?
fi

# Pre-flight 2: NOVA toolchain.
NOVA_BIN="${NOVA_ROOT:-/home/user/NOVA}/nova"
if [ ! -x "$NOVA_BIN" ]; then
    printf "  ${C_RED}ERROR${C_RST}: NOVA launcher not found at %s (set NOVA_ROOT)\n" "$NOVA_BIN" >&2
    FAIL=$((FAIL+1))
    summary "scenario_j_http_client"
    exit $?
fi

# Per-run port + scratch dirs (avoid collisions).
PORT=$(( 31000 + (RANDOM % 1000) ))
SRV_DIR=$(mktemp -d /tmp/ce_int_http_srv_XXXXXX)
SRV_OUT="/tmp/ce_int_http_srv.out"
NOVA_OUT="/tmp/ce_int_http_nova.out"

# The NOVA driver lives in tests/integration/_scenario_j_drivers/ so that
# its `import "../../src/..."` paths resolve. The leading underscore makes
# the Makefile's integration glob (! -name '_*') skip it, and `make build`
# already only walks src/.
DRV_DIR="$REPO_ROOT/tests/integration/_scenario_j_drivers"
mkdir -p "$DRV_DIR"
NOVA_SRC="$DRV_DIR/http_loopback_driver.nova"

KNOWN_PATH="$SRV_DIR/test_html.html"
KNOWN_CONTENT="crossengin-http-client-loopback-marker-c4f1"
cat > "$KNOWN_PATH" <<EOF
<html><body><h1>${KNOWN_CONTENT}</h1></body></html>
EOF

trap 'kill -9 $SRV_PID 2>/dev/null; rm -rf "$SRV_DIR" "$SRV_OUT" "$NOVA_OUT" "$DRV_DIR"' EXIT

# Compose the NOVA driver. Lives under tests/integration/_scenario_j_drivers/
# (filtered out of `make integration` by the `_*` glob exclusion) so the
# `import "../../src/..."` paths resolve through the repo tree.
cat > "$NOVA_SRC" <<NOVA
// Auto-generated loopback driver for scenario_j_http_client.sh.
// Calls if_dispatch_transport("http://127.0.0.1:\$PORT/test_html.html", 4096)
// and prints a status + body marker the bash side asserts on.
import "../../../src/learning/internet_fetch.nova"

fn main() {
    let url = "http://127.0.0.1:${PORT}/test_html.html"
    let r = if_dispatch_transport(url, 4096)
    let tag    = if_tr_tag(r)
    let status = if_tr_status(r)
    let body   = if_tr_body(r)
    let err    = if_tr_err(r)
    println("loopback tag=" + int_to_str(tag)
        + " status=" + int_to_str(status)
        + " body_len=" + int_to_str(len(body))
        + " err='" + err + "'")
    // Print the body so the bash side can grep for the known marker.
    println("--- body begin ---")
    println(body)
    println("--- body end ---")
}

main()
NOVA

# --- Stage 0: pre-flight AF_INET via NOVA so the SKIP path catches the
# "sandbox denies sockets entirely" case before we try to launch the server.
PRECHK_SRC="$DRV_DIR/prechk_socket.nova"
cat > "$PRECHK_SRC" <<'NOVA'
fn main() {
    let s = socket(2, 1, 0)
    if s < 0 { println("socket-deny"); exit(0) }
    close_fd(s)
    println("socket-ok")
}
main()
NOVA
PRECHK_OUT=$("$NOVA_BIN" run "$PRECHK_SRC" 2>/dev/null | tail -1 || echo "socket-deny")
if [ "$PRECHK_OUT" != "socket-ok" ]; then
    printf "  ${C_YEL}SKIP${C_RST}  socket(2,1,0) returns -1 -- sandbox denies AF_INET, scenario_j skipped\n"
    PASS=$((PASS+1))
    summary "scenario_j_http_client"
    exit $?
fi

# --- Stage 1: launch python http.server on $PORT serving $SRV_DIR. -------
(
    cd "$SRV_DIR" && python3 -m http.server "$PORT" --bind 127.0.0.1 >"$SRV_OUT" 2>&1
) &
SRV_PID=$!

# Wait for the server to be ready (poll up to 5s). We probe with a tiny
# bash-only TCP open via /dev/tcp; pure POSIX wouldn't have this, but bash
# does, and we already require bash.
ready=0
i=0
while [ $i -lt 25 ]; do
    if exec 9<>/dev/tcp/127.0.0.1/"$PORT" 2>/dev/null; then
        exec 9<&- 2>/dev/null
        exec 9>&- 2>/dev/null
        ready=1
        break
    fi
    sleep 0.2
    i=$((i+1))
done
if [ $ready -ne 1 ]; then
    printf "  ${C_RED}FAIL${C_RST}  python http.server did not become ready on 127.0.0.1:%d\n" "$PORT"
    cat "$SRV_OUT" 2>/dev/null | sed 's/^/    /'
    FAIL=$((FAIL+1))
    summary "scenario_j_http_client"
    exit $?
fi

# --- Stage 2: run the NOVA driver. ---------------------------------------
"$NOVA_BIN" run "$NOVA_SRC" >"$NOVA_OUT" 2>&1
NOVA_RC=$?
NOVA_TXT=$(cat "$NOVA_OUT" 2>/dev/null || true)

# Kill the server now we're done with it.
kill -9 "$SRV_PID" 2>/dev/null
wait "$SRV_PID" 2>/dev/null

# --- Stage 3: assertions. -------------------------------------------------
assert_eq "$NOVA_RC" "0" "NOVA driver exited 0"
assert_match "$NOVA_TXT" "loopback tag=1" "dispatcher took the HTTP_OK branch (tag=IF_TRANSPORT_HTTP_OK)"
assert_match "$NOVA_TXT" "status=200"     "server returned 200"
assert_match "$NOVA_TXT" "$KNOWN_CONTENT" "body contains the known marker"
assert_match "$NOVA_TXT" "err=''"         "err is empty on success"

# Body length should be at least the size of the known marker + the HTML
# wrapper. The HTML wrapper around the marker is < 100 bytes, so >= 50 is
# a safe floor.
BODY_LEN_LINE=$(echo "$NOVA_TXT" | grep -oE 'body_len=[0-9]+' | head -1 | sed 's/body_len=//')
if [ -n "$BODY_LEN_LINE" ] && [ "$BODY_LEN_LINE" -ge 50 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  body_len >= 50 (got %s)\n" "$BODY_LEN_LINE"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  body_len floor missed (got '%s')\n" "$BODY_LEN_LINE"
fi

# Bonus: a malformed URL takes the bad-url branch.
BAD_SRC="$DRV_DIR/http_badurl_driver.nova"
cat > "$BAD_SRC" <<'NOVA'
import "../../../src/learning/internet_fetch.nova"
fn main() {
    let r = if_dispatch_transport("not-a-url", 1024)
    println("bad tag=" + int_to_str(if_tr_tag(r)))
}
main()
NOVA
BAD_TXT=$("$NOVA_BIN" run "$BAD_SRC" 2>&1)
assert_match "$BAD_TXT" "bad tag=4" "dispatcher took the BAD_URL branch (tag=IF_TRANSPORT_BAD_URL)"

# Bonus: https takes the deferred branch (no network needed).
DEF_SRC="$DRV_DIR/http_https_driver.nova"
cat > "$DEF_SRC" <<'NOVA'
import "../../../src/learning/internet_fetch.nova"
fn main() {
    let r = if_dispatch_transport("https://en.wikipedia.org/wiki/X", 1024)
    println("def tag=" + int_to_str(if_tr_tag(r)) + " err='" + if_tr_err(r) + "'")
}
main()
NOVA
DEF_TXT=$("$NOVA_BIN" run "$DEF_SRC" 2>&1)
assert_match "$DEF_TXT" "def tag=3"                      "dispatcher took the DEFERRED branch for https"
assert_match "$DEF_TXT" "TLS_AUDIT.md"                   "deferred error references TLS_AUDIT.md"

summary "scenario_j_http_client"
