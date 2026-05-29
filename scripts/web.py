#!/usr/bin/env python3
"""
CrossEngin web frontend.

Spawns ./bin/crossengin-chat as ONE long-running subprocess and exposes a tiny
HTTP server (Python stdlib only -- no Flask, no Django, no `pip install`) that
lets you talk to it from a browser. Each HTTP /api/chat request sends one line
to the child's stdin and returns whatever the child printed back, up to the
next "> " prompt.

State persists across requests because the child stays alive between them. The
full admin surface (/teach, /pin, /reflect, /learn, /status, /halt, /resume,
/why, /history, /help, /quit) works through the web UI the same way it works
in a terminal -- the browser is simply a different stdin/stdout.

Usage:
    make install
    python3 scripts/web.py
    # open http://localhost:8765/ in a browser

Overrides:
    CE_PORT=9000 CE_BIN=./bin/crossengin-chat python3 scripts/web.py

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


PORT = int(os.environ.get("CE_PORT", 8765))
BIN  = os.environ.get("CE_BIN", "./bin/crossengin-chat")
# Default to loopback because the chat surface exposes admin commands
# (/teach, /halt, /quit -> exit(0)) that should not be reachable from the LAN.
# Override with CE_BIND=0.0.0.0 when you specifically want LAN access.
BIND = os.environ.get("CE_BIND", "127.0.0.1")
PROMPT_END = b"> "
READ_TIMEOUT = 30.0


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
admin commands &mdash; try <code>/help</code>.</p>
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

def make_handler(child):
    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, fmt, *args):
            pass  # quiet access log

        def _send_json(self, code, obj):
            body = json.dumps(obj).encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def _send_html(self, body):
            data = body.encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            if self.path in ("/", "/index", "/index.html"):
                return self._send_html(HTML)
            if self.path == "/api/banner":
                return self._send_json(200, {"banner": child.boot_banner.strip()})
            return self._send_json(404, {"error": "not found"})

        def do_POST(self):
            if self.path != "/api/chat":
                return self._send_json(404, {"error": "not found"})
            length = int(self.headers.get("Content-Length", 0) or 0)
            try:
                payload = json.loads(self.rfile.read(length).decode("utf-8") or "{}")
            except Exception as e:
                return self._send_json(400, {"error": f"bad json: {e}"})
            message = (payload.get("message") or "").strip()
            if not message:
                return self._send_json(400, {"error": "empty message"})
            try:
                reply = child.send(message)
                return self._send_json(200, {"reply": reply.strip()})
            except TimeoutError as e:
                return self._send_json(504, {"error": str(e)})
            except Exception as e:
                return self._send_json(500, {"error": str(e)})

    return Handler


def main():
    child = ChatChild(BIN)
    server = http.server.ThreadingHTTPServer((BIND, PORT), make_handler(child))
    # Reachable hostname for the user (loopback bind is the default).
    pretty_host = "localhost" if BIND in ("127.0.0.1", "0.0.0.0") else BIND
    url = f"http://{pretty_host}:{PORT}/"
    print(f"CrossEngin web at {url}  (talking to {BIN}, bound on {BIND})", file=sys.stderr)
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
        child.shutdown()


if __name__ == "__main__":
    main()
