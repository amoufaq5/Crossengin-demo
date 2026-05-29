#!/usr/bin/env python3
"""
CrossEngin web frontend.

Spawns one `./bin/crossengin-chat` child PER unique session cookie and routes
each HTTP request to that cookie's child, so multiple browsers / users hitting
the same server get isolated cognitive state (the chat process holds the soul,
KGs, decision log, etc.). One `request_lock` per child serializes the
send-and-wait handshake across concurrent requests on the same cookie; a
registry-level lock guards add/evict so two unknown cookies do not race to
spawn duplicate children. An LRU cap (default 8, override CE_WEB_MAX_SESSIONS)
evicts the least-recently-used child by sending /quit and waiting.

State persists across requests because the child stays alive between them. The
full admin surface (/teach, /pin, /reflect, /learn, /status, /halt, /resume,
/why, /history, /help, /switch, /quit) works through the web UI the same way
it works in a terminal -- the browser is simply a different stdin/stdout.

Usage:
    make install
    python3 scripts/web.py
    # open http://localhost:8765/ in a browser

Overrides:
    CE_PORT=9000 CE_BIN=./bin/crossengin-chat python3 scripts/web.py
    CE_WEB_MAX_SESSIONS=16 python3 scripts/web.py   # raise the LRU cap

Diagnostic endpoint:
    GET /api/sessions -> JSON list of {id, last_active_ms, age_ms}.

Requires: Python 3.7+ (for ThreadingHTTPServer). No third-party libraries.
"""

import http.server
import json
import os
import signal
import subprocess
import sys
import threading
import time
import uuid


PORT = int(os.environ.get("CE_PORT", 8765))
BIN  = os.environ.get("CE_BIN", "./bin/crossengin-chat")
# Default to loopback because the chat surface exposes admin commands
# (/teach, /halt, /quit -> exit(0)) that should not be reachable from the LAN.
# Override with CE_BIND=0.0.0.0 when you specifically want LAN access.
BIND = os.environ.get("CE_BIND", "127.0.0.1")
# Per-cookie LRU cap. The web frontend spawns one chat subprocess per unique
# session cookie; when the count exceeds this, the least-recently-used child
# is evicted (sent /quit, then awaited). Default 8 keeps memory modest even on
# small VMs; raise it if you need to host more concurrent users.
MAX_SESSIONS = int(os.environ.get("CE_WEB_MAX_SESSIONS", 8))
PROMPT_END = b"> "
READ_TIMEOUT = 30.0
COOKIE_NAME = "ce_sid"


# --------------------------------------------------------------------------
# The chat child process: a reader thread streams its stdout into a buffer;
# `send` writes a line and waits until the buffer ends with "> " (the chat's
# next prompt), then returns everything before that marker.

class ChatChild:
    def __init__(self, binary):
        if not os.path.isfile(binary) or not os.access(binary, os.X_OK):
            raise SystemExit(
                f"ERROR: {binary} not found or not executable.\n"
                f"  Build it first:  make install"
            )
        self.proc = subprocess.Popen(
            [binary],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            bufsize=0,
            # New session so the child does not receive the server's SIGINT
            # alongside the orderly shutdown. We deliver /quit to it ourselves.
            start_new_session=True,
        )
        self.buffer = b""
        # Two locks. `lock` guards the buffer (held briefly by the reader
        # thread and the prompt waiter). `request_lock` serializes the entire
        # send-and-wait handshake across concurrent HTTP requests, so request B
        # never consumes request A's reply or interleaves stdin bytes.
        self.lock = threading.Lock()
        self.request_lock = threading.Lock()
        self.reader = threading.Thread(target=self._reader, daemon=True)
        self.reader.start()
        try:
            self.boot_banner = self._wait_for_prompt(timeout=10.0)
        except TimeoutError:
            self.shutdown()
            raise SystemExit("ERROR: chat did not produce a prompt within 10s")

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

    def _wait_for_prompt(self, timeout=READ_TIMEOUT):
        deadline = time.time() + timeout
        while time.time() < deadline:
            with self.lock:
                if self.buffer.endswith(PROMPT_END):
                    out = self.buffer[:-len(PROMPT_END)]
                    self.buffer = b""
                    return out.decode("utf-8", errors="replace")
                if self.proc.poll() is not None:
                    out = self.buffer
                    self.buffer = b""
                    return out.decode("utf-8", errors="replace")
            time.sleep(0.02)
        raise TimeoutError(f"no prompt within {timeout:.0f}s")

    def send(self, message):
        # Serialize the whole stdin.write + prompt-wait across concurrent
        # callers. Without this, two threads writing to stdin in quick
        # succession would race for the same "> "-terminated reply.
        with self.request_lock:
            if self.proc.poll() is not None:
                raise RuntimeError("chat process has exited")
            self.proc.stdin.write((message + "\n").encode("utf-8"))
            self.proc.stdin.flush()
            return self._wait_for_prompt()

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


# --------------------------------------------------------------------------
# Per-cookie store: cookie -> (ChatChild, created_ts, last_active_ts). An
# LRU cap caps the number of concurrent children; insertion above the cap
# evicts the least-recently-used entry first. A registry-level lock guards
# add / evict so two unknown cookies do not race for the same slot.

class SessionStore:
    def __init__(self, binary, max_sessions):
        self.binary = binary
        self.max_sessions = max_sessions
        # cookie -> [ChatChild, created_ms, last_active_ms]
        self.children = {}
        self.lock = threading.Lock()
        # Capture the chat's boot banner once so /api/banner can echo it
        # without spawning a child for the caller's cookie. We use a primer
        # child for this and shut it down immediately -- a one-shot ~100ms
        # round-trip that also surfaces misconfigured binary paths BEFORE
        # the HTTP server binds its port.
        primer = ChatChild(binary)
        self._boot_banner = primer.boot_banner
        primer.shutdown()

    @property
    def boot_banner(self):
        # The header banner the chat prints once on startup. Useful as a
        # "welcome" string in the JS UI -- we expose it via /api/banner.
        return self._boot_banner

    def get_or_create(self, cookie):
        """Return the ChatChild bound to `cookie`. Spawns one if absent."""
        with self.lock:
            entry = self.children.get(cookie)
            if entry is not None:
                # Bump last_active so the LRU eviction prefers idle children.
                entry[2] = int(time.time() * 1000)
                return entry[0]
            # Cap check BEFORE spawn so a flood of new cookies cannot push us
            # past max_sessions transiently.
            self._evict_lru_if_needed()
            child = ChatChild(self.binary)
            now_ms = int(time.time() * 1000)
            self.children[cookie] = [child, now_ms, now_ms]
            return child

    def _evict_lru_if_needed(self):
        # Caller holds self.lock.
        while len(self.children) >= self.max_sessions:
            # Pick the entry with the smallest last_active_ms.
            victim_cookie, victim_entry = min(
                self.children.items(),
                key=lambda kv: kv[1][2],
            )
            del self.children[victim_cookie]
            # /quit the victim outside our brief lock -- shutdown() can
            # block for up to 3s waiting for the child to drain.
            child = victim_entry[0]
            threading.Thread(target=child.shutdown, daemon=True).start()

    def snapshot(self):
        """Return a JSON-serializable list of session diagnostics."""
        now_ms = int(time.time() * 1000)
        with self.lock:
            out = []
            for cookie, entry in self.children.items():
                _child, created_ms, last_active_ms = entry
                out.append({
                    "id": cookie,
                    "last_active_ms": last_active_ms,
                    "age_ms": now_ms - created_ms,
                })
            return out

    def shutdown_all(self):
        with self.lock:
            entries = list(self.children.values())
            self.children.clear()
        for entry in entries:
            try:
                entry[0].shutdown()
            except Exception:
                pass


# --------------------------------------------------------------------------
# Static chat UI -- 60 lines of HTML + JS, embedded so this whole frontend is
# one file you can deploy anywhere.

HTML = r"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>CrossEngin chat</title>
<style>
  body { font: 14px/1.5 system-ui, -apple-system, "Segoe UI", sans-serif;
         max-width: 760px; margin: 2rem auto; padding: 0 1rem; color: #222; }
  h1 { margin: 0 0 .25rem; font-size: 1.25rem; }
  .meta { color: #666; margin-bottom: 1rem; font-size: 13px; }
  #log { border: 1px solid #ddd; border-radius: 6px; padding: .75rem;
         height: 62vh; overflow-y: auto;
         font-family: ui-monospace, "SF Mono", Menlo, monospace; font-size: 13px;
         white-space: pre-wrap; }
  #log > div { margin: 0 0 .25rem; }
  #log .me    { color: #1a52b8; }
  #log .agent { color: #0a7f2e; }
  #log .info  { color: #888; }
  #log .err   { color: #b22; }
  form { display: flex; gap: .5rem; margin-top: .75rem; }
  input[type=text] { flex: 1; padding: .5rem .75rem; font: inherit;
                     border: 1px solid #aaa; border-radius: 6px; }
  button { padding: .5rem 1rem; font: inherit; border: 1px solid #888;
           border-radius: 6px; background: #f4f4f4; cursor: pointer; }
  button:hover { background: #eaeaea; }
  .hint { color: #888; font-size: 12px; margin-top: .5rem; }
  code { background: #f4f4f4; padding: 0 .2rem; border-radius: 3px; }
</style>
</head>
<body>
<h1>CrossEngin chat</h1>
<p class="meta">Talking to a persistent <code>bin/crossengin-chat</code>; the
agent's state carries across messages. Lines starting with <code>/</code> are
admin commands &mdash; try <code>/help</code>. Your session is bound to a
cookie; close the tab and reopen to keep it, clear cookies to start fresh.</p>
<div id="log"></div>
<form id="form" autocomplete="off">
  <input id="msg" type="text" placeholder="say something, or /help" autofocus>
  <button type="submit">Send</button>
</form>
<p class="hint">Examples: <code>fever</code> &middot; <code>/status</code>
&middot; <code>/reflect</code> &middot; <code>/teach widget</code> &middot;
<code>/learn fever</code> (after <code>scripts/learn.sh fever</code>)</p>

<script>
const log  = document.getElementById('log');
const form = document.getElementById('form');
const msg  = document.getElementById('msg');

function add(cls, text) {
  const div = document.createElement('div');
  div.className = cls;
  div.textContent = text;
  log.appendChild(div);
  log.scrollTop = log.scrollHeight;
}

fetch('/api/banner').then(r => r.json()).then(j => {
  if (j.banner) add('info', j.banner);
}).catch(() => {});

form.addEventListener('submit', async (e) => {
  e.preventDefault();
  const text = msg.value;
  if (!text) return;
  msg.value = '';
  add('me', '> ' + text);
  let sendBtn = form.querySelector('button');
  sendBtn.disabled = true;
  try {
    const r = await fetch('/api/chat', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({message: text}),
    });
    const j = await r.json();
    if (j.reply !== undefined) {
      add('agent', j.reply || '(no output)');
    } else if (j.error) {
      add('err', 'ERROR: ' + j.error);
    }
  } catch (err) {
    add('err', 'network ERROR: ' + err.message);
  } finally {
    sendBtn.disabled = false;
    msg.focus();
  }
});
</script>
</body>
</html>
"""


# --------------------------------------------------------------------------
# HTTP server.

def _parse_cookie(header_value):
    """Pull out the ce_sid cookie value from a Cookie: header. Returns None
    if absent or malformed. We accept the bare-pair format browsers actually
    send (`ce_sid=<uuid>; other=value`), no quoting, no Path/Domain attribs."""
    if not header_value:
        return None
    for part in header_value.split(";"):
        if "=" not in part:
            continue
        k, v = part.strip().split("=", 1)
        if k == COOKIE_NAME:
            return v.strip()
    return None


def _valid_uuid(s):
    """True iff `s` parses as a UUID. Rejecting garbage cookies stops a
    malicious client from spawning unbounded children just by varying the
    string -- only well-formed UUIDs get a chat process."""
    if not s:
        return False
    try:
        uuid.UUID(s)
        return True
    except (ValueError, TypeError, AttributeError):
        return False


def make_handler(store):
    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, fmt, *args):
            pass  # quiet access log

        def _cookie_for(self):
            """Return (cookie, is_new). When the incoming request has a valid
            ce_sid cookie we reuse it; otherwise mint a fresh UUID and signal
            to the caller that Set-Cookie should be sent on the response."""
            incoming = _parse_cookie(self.headers.get("Cookie", ""))
            if _valid_uuid(incoming):
                return incoming, False
            return str(uuid.uuid4()), True

        def _send_json(self, code, obj, set_cookie=None):
            body = json.dumps(obj).encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            if set_cookie:
                self.send_header(
                    "Set-Cookie",
                    f"{COOKIE_NAME}={set_cookie}; Path=/; HttpOnly; SameSite=Strict",
                )
            self.end_headers()
            self.wfile.write(body)

        def _send_html(self, body, set_cookie=None):
            data = body.encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            if set_cookie:
                self.send_header(
                    "Set-Cookie",
                    f"{COOKIE_NAME}={set_cookie}; Path=/; HttpOnly; SameSite=Strict",
                )
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            cookie, is_new = self._cookie_for()
            set_cookie = cookie if is_new else None
            if self.path in ("/", "/index", "/index.html"):
                return self._send_html(HTML, set_cookie=set_cookie)
            if self.path == "/api/banner":
                return self._send_json(
                    200,
                    {"banner": store.boot_banner.strip()},
                    set_cookie=set_cookie,
                )
            if self.path == "/api/sessions":
                # Diagnostic endpoint -- list every live cookie -> child entry
                # with its created/last-active timestamps. Read-only; safe to
                # expose on the loopback bind. Does NOT spawn a child for the
                # caller's cookie so a curl probe doesn't bloat the registry.
                return self._send_json(
                    200,
                    {"sessions": store.snapshot()},
                    set_cookie=set_cookie,
                )
            return self._send_json(404, {"error": "not found"}, set_cookie=set_cookie)

        def do_POST(self):
            cookie, is_new = self._cookie_for()
            set_cookie = cookie if is_new else None
            if self.path != "/api/chat":
                return self._send_json(404, {"error": "not found"}, set_cookie=set_cookie)
            length = int(self.headers.get("Content-Length", 0) or 0)
            try:
                payload = json.loads(self.rfile.read(length).decode("utf-8") or "{}")
            except Exception as e:
                return self._send_json(400, {"error": f"bad json: {e}"}, set_cookie=set_cookie)
            message = (payload.get("message") or "").strip()
            if not message:
                return self._send_json(400, {"error": "empty message"}, set_cookie=set_cookie)
            try:
                child = store.get_or_create(cookie)
                reply = child.send(message)
                return self._send_json(
                    200,
                    {"reply": reply.strip()},
                    set_cookie=set_cookie,
                )
            except TimeoutError as e:
                return self._send_json(504, {"error": str(e)}, set_cookie=set_cookie)
            except Exception as e:
                return self._send_json(500, {"error": str(e)}, set_cookie=set_cookie)

    return Handler


def main():
    store = SessionStore(BIN, MAX_SESSIONS)
    server = http.server.ThreadingHTTPServer((BIND, PORT), make_handler(store))
    # Reachable hostname for the user (loopback bind is the default).
    pretty_host = "localhost" if BIND in ("127.0.0.1", "0.0.0.0") else BIND
    url = f"http://{pretty_host}:{PORT}/"
    print(
        f"CrossEngin web at {url}  (talking to {BIN}, bound on {BIND}, "
        f"max sessions={MAX_SESSIONS})",
        file=sys.stderr,
    )
    if BIND == "0.0.0.0":
        print("WARNING: bound on 0.0.0.0 -- admin commands are reachable from the LAN.",
              file=sys.stderr)
    print("Ctrl-C to stop.", file=sys.stderr)

    stop_event = threading.Event()

    def _stop(signum, frame):
        if not stop_event.is_set():
            stop_event.set()
            # Triggers serve_forever's loop to exit. Called from the signal
            # context; nothing here may block (server.shutdown does block, so
            # we leave it for the finally block below).
            threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, _stop)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nshutting down...", file=sys.stderr)
    finally:
        if not stop_event.is_set():
            server.shutdown()
        server.server_close()
        store.shutdown_all()


if __name__ == "__main__":
    main()
