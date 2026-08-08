#!/usr/bin/env python3
"""
rpc_web_shim.py -- Minimal HTTP shim that bridges a browser to the
CrossEngin JSON-RPC TCP daemon (R51, ADR-0109).

Two responsibilities:

  1. Serve the static SPA under `web/` (HTML + JS + CSS)
  2. Route `POST /rpc/<verb>` requests to the TCP RPC daemon and
     stream the daemon's response back

The shim uses the Python 3 stdlib only (`http.server`, `socket`) --
no pip install, no venv, no framework -- so a fresh Linux / macOS /
Windows box with Python 3 can run it without prep.

The shim's design mirrors the R49 daemon's:
  - Loopback default (127.0.0.1)
  - Per-request connection to the daemon (mirrors the daemon's
    serial-accept shape)
  - Line-oriented JSON framing (one request per connection; the
    daemon closes after writing the response line)
  - No auth, no TLS. Both the shim and the daemon bind loopback
    by default; the wire is safe for local-first use. Non-loopback
    binds require an explicit env flag.

Usage:
  scripts/rpc_web_shim.py                       # default: 127.0.0.1:8080
  CE_WEB_PORT=18080 scripts/rpc_web_shim.py     # override web port

Env:
  CE_WEB_PORT       port the shim listens on (default 8080)
  CE_WEB_BIND       bind IP (default 127.0.0.1)
  CE_WEB_BIND_ALLOW_NON_LOOPBACK  set to "1" to bind non-loopback
  CE_RPC_HOST       TCP daemon host (default 127.0.0.1)
  CE_RPC_PORT       TCP daemon port (default 9876)
  CE_WEB_ROOT       static-file root (default: <repo>/web)
  CE_WEB_TIMEOUT_S  per-request timeout when talking to the daemon
                    (default 30 seconds)

Then open http://127.0.0.1:8080/ in a browser.
"""

from __future__ import annotations

import json
import os
import socket
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import urlsplit

# ---- config from env -----------------------------------------------------

WEB_PORT = int(os.environ.get("CE_WEB_PORT", "8080"))
WEB_BIND = os.environ.get("CE_WEB_BIND", "127.0.0.1")
ALLOW_NON_LOOPBACK = os.environ.get("CE_WEB_BIND_ALLOW_NON_LOOPBACK", "0") == "1"

RPC_HOST = os.environ.get("CE_RPC_HOST", "127.0.0.1")
RPC_PORT = int(os.environ.get("CE_RPC_PORT", "9876"))
RPC_TIMEOUT_S = float(os.environ.get("CE_WEB_TIMEOUT_S", "30"))

REPO_ROOT = Path(__file__).resolve().parent.parent
WEB_ROOT = Path(os.environ.get("CE_WEB_ROOT", str(REPO_ROOT / "web")))

_ALLOWED_VERBS = {
    "nl.ask",
    "nl.parse_only",
    "kg.list",
    "capsule.list",
    "capsule.install",
    "skill.list",
    "skill.run",
    "persona.show",
    "persona.project",
    "ingest.review",
    "ingest.approve",
    "ingest.deny",
}

# Static-file extension -> content-type. Deliberately narrow; the shim
# is not a general-purpose file server.
_MIME = {
    ".html": "text/html; charset=utf-8",
    ".css":  "text/css; charset=utf-8",
    ".js":   "application/javascript; charset=utf-8",
    ".json": "application/json",
    ".svg":  "image/svg+xml",
    ".ico":  "image/x-icon",
    ".png":  "image/png",
    ".txt":  "text/plain; charset=utf-8",
}


def _forward_to_daemon(verb: str, args: dict) -> str:
    """One connection per request, mirroring the daemon's serial shape."""
    request = json.dumps({"verb": verb, "args": args}) + "\n"
    with socket.create_connection((RPC_HOST, RPC_PORT), timeout=RPC_TIMEOUT_S) as s:
        s.sendall(request.encode("utf-8"))
        # Half-close write side so the daemon knows we're done sending.
        try:
            s.shutdown(socket.SHUT_WR)
        except OSError:
            pass
        # Read until EOF -- the daemon closes after writing its line.
        chunks = []
        while True:
            chunk = s.recv(65536)
            if not chunk:
                break
            chunks.append(chunk)
    return b"".join(chunks).decode("utf-8", errors="replace").strip()


def _safe_static_path(url_path: str) -> Path | None:
    """Resolve a URL path to a file under WEB_ROOT. Returns None if the
    path escapes the root (defense against `../` traversal)."""
    if url_path in ("", "/"):
        url_path = "/index.html"
    # Strip leading slash so `WEB_ROOT / rel` doesn't drop the root.
    rel = url_path.lstrip("/")
    # Reject any component with '..' explicitly; also resolve() below is
    # our authoritative check.
    if ".." in rel.split("/"):
        return None
    candidate = (WEB_ROOT / rel).resolve()
    try:
        candidate.relative_to(WEB_ROOT.resolve())
    except ValueError:
        return None
    if not candidate.exists() or not candidate.is_file():
        return None
    return candidate


class Handler(BaseHTTPRequestHandler):
    server_version = "CrossEngin-web-shim/1.0"

    # Quieter logging -- default BaseHTTPRequestHandler logs every request
    # including static assets. We keep POST logs (they show verb dispatch)
    # and drop GETs for static files below.
    def log_message(self, format: str, *args) -> None:  # noqa: A003 (name inherited)
        sys.stderr.write("%s %s\n" % (self.address_string(), format % args))

    # ---- POST /rpc/<verb> -----------------------------------------------
    def do_POST(self) -> None:  # noqa: N802
        parsed = urlsplit(self.path)
        if not parsed.path.startswith("/rpc/"):
            self._json(404, {"ok": False, "result": None,
                             "error": f"unknown POST path: {parsed.path}"})
            return
        verb = parsed.path[len("/rpc/"):]
        if verb not in _ALLOWED_VERBS:
            self._json(400, {"ok": False, "result": None,
                             "error": f"unknown verb: {verb}"})
            return
        content_length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(content_length) if content_length > 0 else b"{}"
        try:
            body = json.loads(raw.decode("utf-8") or "{}")
        except json.JSONDecodeError as e:
            self._json(400, {"ok": False, "result": None,
                             "error": f"bad JSON body: {e}"})
            return
        if not isinstance(body, dict):
            self._json(400, {"ok": False, "result": None,
                             "error": "body must be a JSON object (args map)"})
            return
        try:
            wire_response = _forward_to_daemon(verb, body)
        except (ConnectionRefusedError, socket.timeout, OSError) as e:
            self._json(502, {"ok": False, "result": None,
                             "error": f"daemon unreachable at {RPC_HOST}:{RPC_PORT}: {e}"})
            return
        # Pass the daemon's response through as-is. Its envelope is
        # already {ok, result, error}; the browser can use it directly.
        self._raw(200, wire_response.encode("utf-8"),
                  content_type="application/json")

    # ---- GET / (static) -------------------------------------------------
    def do_GET(self) -> None:  # noqa: N802
        parsed = urlsplit(self.path)
        # A GET on /rpc/* is a client mistake; help them out.
        if parsed.path.startswith("/rpc/"):
            self._json(405, {"ok": False, "result": None,
                             "error": "RPC endpoint takes POST, not GET"})
            return
        # Health check.
        if parsed.path == "/healthz":
            self._raw(200, b"ok\n", content_type="text/plain; charset=utf-8")
            return
        path = _safe_static_path(parsed.path)
        if path is None:
            self._raw(404, b"not found\n",
                      content_type="text/plain; charset=utf-8")
            return
        try:
            data = path.read_bytes()
        except OSError as e:
            self._raw(500, f"read error: {e}\n".encode("utf-8"),
                      content_type="text/plain; charset=utf-8")
            return
        ctype = _MIME.get(path.suffix.lower(), "application/octet-stream")
        self._raw(200, data, content_type=ctype)

    # ---- helpers --------------------------------------------------------
    def _json(self, status: int, payload: dict) -> None:
        body = json.dumps(payload).encode("utf-8")
        self._raw(status, body, content_type="application/json")

    def _raw(self, status: int, body: bytes, *, content_type: str) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        # Loopback-first design: no CORS by default. If you're bridging
        # a browser served from a different origin, set the header here.
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)


def main() -> int:
    # Loopback safety: refuse a non-loopback bind unless the operator
    # explicitly opted in. Mirrors scripts/rpc_daemon.sh's gate.
    if not (WEB_BIND.startswith("127.") or WEB_BIND in ("localhost", "::1")) \
            and not ALLOW_NON_LOOPBACK:
        sys.stderr.write(
            f"ERROR: CE_WEB_BIND={WEB_BIND} is not a loopback address.\n"
            "The web shim forwards to the RPC wire which dispatches skills.\n"
            "Rerun with CE_WEB_BIND_ALLOW_NON_LOOPBACK=1 if you know what\n"
            "you're doing. Consider layering TLS or an SSH tunnel first.\n"
        )
        return 2
    if not WEB_ROOT.exists():
        sys.stderr.write(f"ERROR: static root not found: {WEB_ROOT}\n")
        return 1
    server = HTTPServer((WEB_BIND, WEB_PORT), Handler)
    sys.stderr.write(
        f"=== CrossEngin web shim ===\n"
        f"listening on http://{WEB_BIND}:{WEB_PORT}/\n"
        f"static root: {WEB_ROOT}\n"
        f"forwarding /rpc/<verb> POSTs to {RPC_HOST}:{RPC_PORT} "
        f"(daemon: crossengin-rpc-daemon)\n"
        f"open the URL above in a browser; Ctrl-C to stop.\n"
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        sys.stderr.write("\nbye.\n")
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
