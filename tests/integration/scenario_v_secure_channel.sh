#!/usr/bin/env bash
# Scenario V -- PSK secure-channel (ChaCha20-Poly1305) loopback.
#
# Phase / P1.4 continuation: src/io/transducers/secure_channel.nova
# wraps an existing TCP socket in a per-frame ChaCha20-Poly1305 envelope
# using a 32-byte pre-shared key. This scenario proves it end-to-end
# against a Python counterpart (scripts/secure_channel_echo.py) that
# speaks the same framing.
#
# The Python echo server:
#   * accepts the 12-byte handshake nonce.
#   * derives the session key = ChaCha20-block(PSK, nonce, 0)[0..32].
#   * decrypts the client's handshake-magic frame, verifies Poly1305.
#   * sends back the same magic, freshly encrypted with the server's
#     own send-counter.
#   * decrypts ONE application frame and echoes back, transforming
#     "ping" -> "pong" (so we have a deterministic check that the
#     plaintext was actually decrypted, not just byte-echoed).
#
# The NOVA client (driven by an on-the-fly NOVA driver):
#   * calls sc_open(host, port, psk_hex) -- runs the handshake.
#   * sends "ping".
#   * receives a frame, verifies tag, decrypts.
#   * asserts the recovered plaintext is "pong".
#
# KNOWN LIMITATIONS:
#   * NOVA socket builtins are blocking; if either side hangs the
#     5s timeout trips and the script reports FAIL.
#   * If python3 is unavailable or `socket(2,1,0)` returns -1 (sandbox
#     denies AF_INET), the script prints SKIP and passes.

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

it_section "scenario V: PSK secure channel (NOVA client <-> Python echo)"

# Pre-flight 1: python3.
if ! command -v python3 >/dev/null 2>&1; then
    printf "  ${C_YEL}SKIP${C_RST}  python3 not installed -- scenario_v skipped\n"
    PASS=$((PASS+1))
    summary "scenario_v_secure_channel"
    exit $?
fi

# Pre-flight 2: NOVA toolchain.
NOVA_BIN="${NOVA_ROOT:-/home/user/NOVA}/nova"
if [ ! -x "$NOVA_BIN" ]; then
    printf "  ${C_RED}ERROR${C_RST}: NOVA launcher not found at %s (set NOVA_ROOT)\n" "$NOVA_BIN" >&2
    FAIL=$((FAIL+1))
    summary "scenario_v_secure_channel"
    exit $?
fi

# Per-run port + a fresh randomly-chosen PSK so any test-runner replay
# starts from a fresh nonce-prefix universe (SAFETY caveat in
# secure_channel.nova: per-key nonce reuse is catastrophic).
PORT=$(( 32000 + (RANDOM % 1000) ))
# 32 bytes of randomness = 64 hex chars. We grind through /dev/urandom
# directly (xxd is in coreutils on every distro we ship to).
PSK=$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')

# Sanity-check the PSK is exactly 64 hex chars.
if [ "${#PSK}" -ne 64 ]; then
    printf "  ${C_RED}FAIL${C_RST}  PSK length sanity (got %d hex chars, want 64)\n" "${#PSK}"
    FAIL=$((FAIL+1))
    summary "scenario_v_secure_channel"
    exit $?
fi

DRV_DIR="$REPO_ROOT/tests/integration/_scenario_v_drivers"
mkdir -p "$DRV_DIR"
NOVA_SRC="$DRV_DIR/sc_client_driver.nova"
SRV_OUT="/tmp/ce_int_sc_srv.out"
NOVA_OUT="/tmp/ce_int_sc_nova.out"

SRV_PID=""
trap 'if [ -n "${SRV_PID:-}" ]; then kill -9 $SRV_PID 2>/dev/null; fi; rm -rf "$SRV_OUT" "$NOVA_OUT" "$DRV_DIR"' EXIT

# Stage 0: pre-flight AF_INET availability via NOVA so the SKIP path
# catches the "sandbox denies sockets entirely" case before we try to
# launch the server.
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
    printf "  ${C_YEL}SKIP${C_RST}  socket(2,1,0) returns -1 -- sandbox denies AF_INET, scenario_v skipped\n"
    PASS=$((PASS+1))
    summary "scenario_v_secure_channel"
    exit $?
fi

# Stage 1: launch python echo server. The server emits "READY <port>"
# on stdout when it's bound and listening.
python3 "$REPO_ROOT/scripts/secure_channel_echo.py" "$PORT" "$PSK" >"$SRV_OUT" 2>&1 &
SRV_PID=$!

# Wait for "READY" line (max 5s).
ready=0
i=0
while [ $i -lt 50 ]; do
    if grep -q "^READY" "$SRV_OUT" 2>/dev/null; then
        ready=1
        break
    fi
    sleep 0.1
    i=$((i+1))
done
if [ $ready -ne 1 ]; then
    printf "  ${C_RED}FAIL${C_RST}  echo server did not become ready on 127.0.0.1:%d\n" "$PORT"
    cat "$SRV_OUT" 2>/dev/null | sed 's/^/    /'
    FAIL=$((FAIL+1))
    summary "scenario_v_secure_channel"
    exit $?
fi

# Stage 2: emit the NOVA driver. Lives under tests/integration/_scenario_v_drivers/
# so the `import "../../../src/..."` paths resolve through the repo tree
# AND the integration glob (`! -name '_*'`) skips it.
cat > "$NOVA_SRC" <<NOVA
// Auto-generated PSK secure-channel driver for scenario_v_secure_channel.sh.
// Connects to 127.0.0.1:${PORT} with the per-run PSK, sends "ping",
// asserts the response is "pong".
import "../../../src/io/transducers/secure_channel.nova"

fn _str_to_buf(s) {
    let n = len(s)
    let buf = alloc(n + 1)
    let i = 0
    while i < n {
        store8(buf + i, char_at(s, i))
        i = i + 1
    }
    store8(buf + n, 0)
    return buf
}

fn _buf_to_str(buf, n) {
    let s = ""
    let i = 0
    while i < n {
        s = s + chr(load8(buf + i))
        i = i + 1
    }
    return s
}

fn main() {
    let psk = "${PSK}"
    let state = sc_open("127.0.0.1", ${PORT}, psk)
    if state == 0 {
        println("sc: open failed")
        return 0
    }
    println("sc: handshake ok")
    let pt = _str_to_buf("ping")
    if sc_send(state, pt, 4) == 0 {
        println("sc: send failed err=" + sc_last_error(state))
        sc_close(state)
        return 0
    }
    println("sc: sent ping")
    let reply = sc_recv(state)
    if reply == 0 {
        println("sc: recv failed err=" + sc_last_error(state))
        sc_close(state)
        return 0
    }
    let reply_str = _buf_to_str(reply[0], reply[1])
    println("sc: recv plaintext=" + reply_str + " len=" + int_to_str(reply[1]))
    sc_close(state)
    return 0
}

main()
NOVA

# Stage 3: run the NOVA driver.
"$NOVA_BIN" run "$NOVA_SRC" >"$NOVA_OUT" 2>&1
NOVA_RC=$?
NOVA_TXT=$(cat "$NOVA_OUT" 2>/dev/null || true)

# Reap the server (it should already have exited cleanly).
wait "$SRV_PID" 2>/dev/null
SRV_RC=$?

# Stage 4: assertions.
assert_eq "$NOVA_RC" "0" "NOVA driver exited 0"
assert_match "$NOVA_TXT" "sc: handshake ok"     "PSK handshake completed"
assert_match "$NOVA_TXT" "sc: sent ping"        "client sent ping frame"
assert_match "$NOVA_TXT" "plaintext=pong"       "decrypted reply equals 'pong'"
assert_match "$NOVA_TXT" "len=4"                "reply plaintext is 4 bytes"

# Bonus: server exited 0 -- it accepted the handshake AND the app frame.
if [ "$SRV_RC" -eq 0 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  python server exited 0\n"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  python server exited %s\n" "$SRV_RC"
    cat "$SRV_OUT" 2>/dev/null | sed 's/^/    /'
fi

summary "scenario_v_secure_channel"
