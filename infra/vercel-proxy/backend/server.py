#!/usr/bin/env python3
"""
CrossEngin HTTP wrapper for the Vercel-hybrid pattern.

Listens on :8080 and exposes two endpoints:

  GET  /health      Liveness probe. Returns 200 + JSON body. No auth.
  POST /chat        Body: {"session_id": str, "input": str}
                    Auth: `Authorization: Bearer ${CROSSENGIN_TOKEN}`
                    Response: streamed text body containing the agent's reply.

How `/chat` actually invokes CrossEngin
---------------------------------------
The repo ships two chat surfaces in `bin/`:

  - `bin/crossengin`       -- one-shot daemon. Reads /tmp/crossengin_input,
                              prints one `agent>` line, exits. This is what
                              `scripts/chat.sh` drives in a bash loop.
  - `bin/crossengin-chat`  -- persistent REPL with admin commands. This is
                              what `scripts/web.py` keeps as long-lived
                              children per cookie.

The wrapper defaults to the persistent variant (`CE_BIN=bin/crossengin-chat`)
because it preserves per-session cognitive state across HTTP turns (the
`scripts/web.py` pattern). If you really want the one-shot semantics --
fresh boot per turn -- set `CE_BIN=bin/crossengin` and the wrapper falls
back to the `scripts/chat.sh` interaction shape (write input file -> run
binary -> grep `agent>` line). This is documented in ARCHITECTURE.md.

Limitations honestly noted
--------------------------
- v0.1 does NOT implement streaming token-by-token; the agent surface is
  line-shaped. The HTTP body is the full `agent>` line + trace; we flush
  once when the child's prompt returns. SSE / chunked streaming with
  partial tokens is a future round.
- Bearer-token rotation is manual (restart the service with a new env).
  SECURITY.md documents the JWT-with-key-rotation upgrade path.
- Session isolation reuses scripts/web.py's per-cookie store via the
  `session_id` field; we treat it as the cookie equivalent. A malicious
  caller flooding distinct session_ids can still trigger LRU eviction.
  Mitigation: rate-limit at the Vercel function (SECURITY.md).

Env vars (read at startup)
--------------------------
  CROSSENGIN_TOKEN     required, the bearer this server validates
  CE_BIN               default: bin/crossengin-chat
  CE_PORT              default: 8080
  CE_BIND              default: 0.0.0.0 (the proxy is the trust boundary)
  CE_MAX_SESSIONS      default: 8 (LRU cap; matches scripts/web.py)
  CE_REQUEST_TIMEOUT_S default: 30.0
"""
import http.server
import json
import os
import subprocess
import sys
import threading
import time


# -----------------------------------------------------------------------------
# Config
# -----------------------------------------------------------------------------
TOKEN = os.environ.get("CROSSENGIN_TOKEN", "")
BIN = os.environ.get("CE_BIN", "bin/crossengin-chat")
PORT = int(os.environ.get("CE_PORT", "8080"))
BIND = os.environ.get("CE_BIND", "0.0.0.0")
MAX_SESSIONS = int(os.environ.get("CE_MAX_SESSIONS", "8"))
REQUEST_TIMEOUT_S = float(os.environ.get("CE_REQUEST_TIMEOUT_S", "30.0"))

# The persistent chat surface emits its prompt as "> " at end-of-reply.
PROMPT_END = b"> "


# -----------------------------------------------------------------------------
# Persistent chat child -- mirrors the design in scripts/web.py.
#
# We deliberately keep this self-contained (no import from scripts/web.py) so
# the backend image can run with just this single file + the CrossEngin
# binaries on PATH. The scripts/web.py version has extra surface (metrics,
# atom search) that the Vercel proxy does not need.
# -----------------------------------------------------------------------------
class ChatChild:
    """One persistent `bin/crossengin-chat` subprocess.

    `send(message)` writes a line to stdin and blocks until the next prompt.
    `shutdown()` sends `/quit` and reaps the process.
    """

    def __init__(self, binary):
        if not os.path.isfile(binary) or not os.access(binary, os.X_OK):
            raise RuntimeError(
                f"binary not found / not executable: {binary} "
                f"(set CE_BIN; default bin/crossengin-chat)"
            )
        self.proc = subprocess.Popen(
            [binary],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            bufsize=0,
            start_new_session=True,
        )
        self.buffer = b""
        self.lock = threading.Lock()
        self.request_lock = threading.Lock()
        self.reader = threading.Thread(target=self._reader, daemon=True)
        self.reader.start()
        try:
            self.boot_banner = self._wait_for_prompt(timeout=10.0)
        except TimeoutError:
            self.shutdown()
            raise RuntimeError("child did not produce a prompt within 10s")

    def _reader(self):
        while True:
            try:
                c = self.proc.stdout.read(1)
                if not c:
                    break
                with self.lock:
                    self.buffer += c
            except Exception:
                break

    def _wait_for_prompt(self, timeout):
        deadline = time.time() + timeout
        while time.time() < deadline:
            with self.lock:
                if self.buffer.endswith(PROMPT_END):
                    out = self.buffer[: -len(PROMPT_END)]
                    self.buffer = b""
                    return out.decode("utf-8", errors="replace")
                if self.proc.poll() is not None:
                    out = self.buffer
                    self.buffer = b""
                    return out.decode("utf-8", errors="replace")
            time.sleep(0.02)
        raise TimeoutError(f"no prompt within {timeout:.0f}s")

    def send(self, message):
        with self.request_lock:
            if self.proc.poll() is not None:
                raise RuntimeError("chat process has exited")
            self.proc.stdin.write((message + "\n").encode("utf-8"))
            self.proc.stdin.flush()
            return self._wait_for_prompt(REQUEST_TIMEOUT_S)

    def shutdown(self):
        try:
            if self.proc.poll() is None:
                self.proc.stdin.write(b"/quit\n")
                self.proc.stdin.flush()
                self.proc.wait(timeout=3.0)
        except Exception:
            pass
        try:
            self.proc.kill()
        except Exception:
            pass


# -----------------------------------------------------------------------------
# Fallback: scripts/chat.sh-style one-shot invocation for `CE_BIN=bin/crossengin`
# -----------------------------------------------------------------------------
def chat_oneshot(binary, message):
    """Spawn the one-shot daemon per turn (the scripts/chat.sh shape).

    Each call writes `message` to /tmp/crossengin_input, runs the binary,
    and extracts the first `agent>` line. Stateless across calls.
    """
    input_path = "/tmp/crossengin_input"
    with open(input_path, "w", encoding="utf-8") as fp:
        fp.write(message)
    try:
        result = subprocess.run(
            [binary],
            capture_output=True,
            timeout=REQUEST_TIMEOUT_S,
        )
        out = (result.stdout or b"").decode("utf-8", errors="replace")
        for line in out.splitlines():
            if line.startswith("agent> "):
                return line
        # No agent line -- return the tail for diagnosis (mirrors chat.sh).
        tail = "\n".join(out.splitlines()[-5:])
        return f"agent> [no response -- daemon trace:]\n{tail}"
    finally:
        try:
            os.unlink(input_path)
        except OSError:
            pass


# -----------------------------------------------------------------------------
# Session store (LRU per session_id). Mirrors scripts/web.py.
# -----------------------------------------------------------------------------
class SessionStore:
    def __init__(self, binary, max_sessions):
        self.binary = binary
        self.max_sessions = max_sessions
        self.children = {}  # session_id -> [ChatChild, created_ms, last_active_ms]
        self.lock = threading.Lock()

    def get_or_create(self, session_id):
        with self.lock:
            entry = self.children.get(session_id)
            if entry is not None:
                entry[2] = int(time.time() * 1000)
                return entry[0]
            self._evict_lru_if_needed()
            child = ChatChild(self.binary)
            now_ms = int(time.time() * 1000)
            self.children[session_id] = [child, now_ms, now_ms]
            return child

    def _evict_lru_if_needed(self):
        # Caller holds self.lock.
        while len(self.children) >= self.max_sessions:
            victim_sid, victim_entry = min(
                self.children.items(),
                key=lambda kv: kv[1][2],
            )
            del self.children[victim_sid]
            threading.Thread(
                target=victim_entry[0].shutdown, daemon=True
            ).start()

    def shutdown_all(self):
        with self.lock:
            entries = list(self.children.values())
            self.children.clear()
        for entry in entries:
            try:
                entry[0].shutdown()
            except Exception:
                pass


# -----------------------------------------------------------------------------
# HTTP layer
# -----------------------------------------------------------------------------
def _check_auth(headers):
    """Constant-ish-time bearer compare. Returns True iff the header carries
    a Bearer scheme whose value equals CROSSENGIN_TOKEN."""
    if not TOKEN:
        return False
    h = headers.get("Authorization", "")
    if not h.startswith("Bearer "):
        return False
    presented = h[len("Bearer "):].strip()
    # Constant-time-ish compare (avoids early-exit timing leak). Stdlib
    # hmac.compare_digest is the canonical primitive here.
    import hmac
    return hmac.compare_digest(presented, TOKEN)


def make_handler(store, oneshot_mode):
    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, fmt, *args):
            # Quiet access log; SECURITY.md notes the no-secret-logging rule.
            pass

        def _send_json(self, code, obj):
            body = json.dumps(obj).encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def _send_text_stream(self, body_text):
            data = body_text.encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            if self.path == "/health":
                # Unauthenticated by design: container orchestrators and
                # load balancers need an unauth probe. Returns minimal info.
                return self._send_json(
                    200,
                    {
                        "status": "ok",
                        "binary": store.binary,
                        "oneshot": oneshot_mode,
                        "sessions": len(store.children),
                    },
                )
            return self._send_json(404, {"error": "not found"})

        def do_POST(self):
            if self.path != "/chat":
                return self._send_json(404, {"error": "not found"})
            if not _check_auth(self.headers):
                return self._send_json(401, {"error": "unauthorized"})
            length = int(self.headers.get("Content-Length", "0") or 0)
            if length <= 0 or length > 1 << 16:
                return self._send_json(
                    400, {"error": "invalid Content-Length"}
                )
            raw = self.rfile.read(length)
            try:
                payload = json.loads(raw.decode("utf-8"))
            except Exception as e:
                return self._send_json(400, {"error": f"bad json: {e}"})
            session_id = (payload.get("session_id") or "").strip() or "default"
            message = (payload.get("input") or "").strip()
            if not message:
                return self._send_json(400, {"error": "empty input"})

            try:
                if oneshot_mode:
                    reply = chat_oneshot(store.binary, message)
                else:
                    child = store.get_or_create(session_id)
                    reply = child.send(message)
            except TimeoutError as e:
                return self._send_json(504, {"error": str(e)})
            except Exception as e:
                return self._send_json(500, {"error": str(e)})
            return self._send_text_stream(reply.strip() + "\n")

    return Handler


# -----------------------------------------------------------------------------
# Entrypoint
# -----------------------------------------------------------------------------
def main():
    if not TOKEN:
        print(
            "FATAL: CROSSENGIN_TOKEN env var is empty. Refusing to start an "
            "unauthenticated proxy. Generate one with `openssl rand -hex 32`.",
            file=sys.stderr,
        )
        sys.exit(2)

    # Pick the invocation shape. Default = persistent chat; if the caller
    # points CE_BIN at the one-shot daemon name, use chat.sh-style spawn.
    oneshot_mode = os.path.basename(BIN) == "crossengin"

    # In one-shot mode we don't pre-spawn anything; we only need the
    # binary to be executable. In persistent mode the SessionStore
    # spawns lazily per session_id.
    if not os.path.isfile(BIN) or not os.access(BIN, os.X_OK):
        print(
            f"FATAL: binary not found or not executable: {BIN}\n"
            f"  (set CE_BIN; default bin/crossengin-chat)",
            file=sys.stderr,
        )
        sys.exit(2)

    store = SessionStore(BIN, MAX_SESSIONS)
    handler_cls = make_handler(store, oneshot_mode)
    server = http.server.ThreadingHTTPServer((BIND, PORT), handler_cls)
    print(
        f"crossengin-backend listening on http://{BIND}:{PORT} "
        f"(binary={BIN}, oneshot={oneshot_mode}, "
        f"max_sessions={MAX_SESSIONS})",
        file=sys.stderr,
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("shutting down...", file=sys.stderr)
    finally:
        server.server_close()
        store.shutdown_all()


if __name__ == "__main__":
    main()
