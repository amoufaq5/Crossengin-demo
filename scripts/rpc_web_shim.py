#!/usr/bin/env python3
"""
rpc_web_shim.py -- Minimal HTTP shim that bridges a browser to the
CrossEngin JSON-RPC TCP daemon (R51 origin, R108 polish; ADR-0109 +
ADR-0209 Mode 4).

Two responsibilities:

  1. Serve the static SPA under `web/` (HTML + JS + CSS)
  2. Route `POST /rpc/<verb>` requests to the TCP RPC daemon and
     stream the daemon's response back, mapping wire error strings
     to appropriate HTTP status codes so the browser can render
     rate-limit / auth / cap banners uniformly.

The shim uses the Python 3 stdlib only (`http.server`, `socket`) --
no pip install, no venv, no framework -- so a fresh Linux / macOS /
Windows box with Python 3 can run it without prep.

The shim's design mirrors the R49 daemon's:
  - Loopback default (127.0.0.1)
  - Per-request connection to the daemon (mirrors the daemon's
    serial-accept shape)
  - Line-oriented JSON framing (one request per connection; the
    daemon closes after writing the response line)
  - No auth of its own, no TLS. Both the shim and the daemon bind
    loopback by default; the wire is safe for local-first use.
    Non-loopback binds require an explicit env flag. Cap tokens
    still enforce access at the daemon.

Usage:
  scripts/rpc_web_shim.py                              # 127.0.0.1:8080
  CE_WEB_PORT=18080 scripts/rpc_web_shim.py            # override port
  scripts/rpc_web_shim.py --cors http://localhost:9000 # CORS allow-list

Env:
  CE_WEB_PORT       port the shim listens on (default 8080)
  CE_WEB_BIND       bind IP (default 127.0.0.1)
  CE_WEB_BIND_ALLOW_NON_LOOPBACK  set to "1" to bind non-loopback
  CE_RPC_HOST       TCP daemon host (default 127.0.0.1)
  CE_RPC_PORT       TCP daemon port (default 9876)
  CE_WEB_ROOT       static-file root (default: <repo>/web)
  CE_WEB_TIMEOUT_S  per-request timeout when talking to the daemon
                    (default 30 seconds)
  CE_WEB_CORS       comma-separated CORS allow-list; equivalent to
                    passing `--cors <origin>` once per entry.

Flags:
  --cors <origin>   whitelist an origin for CORS (may be repeated).
                    Default is NO CORS headers. When the request's
                    `Origin` header matches an entry, the shim
                    emits `Access-Control-Allow-Origin: <origin>` +
                    Methods/Headers; unknown origins get no CORS.
                    An `OPTIONS` preflight returns 204 with the
                    same headers.

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

# CORS allow-list built at boot from --cors flags + CE_WEB_CORS. Empty
# means "no CORS headers at all" (loopback-first default).
CORS_ORIGINS: set[str] = set()

# Whitelist of RPC verbs the shim forwards. Anything else -> 405. The
# daemon has its own allow-list; the shim's is a defense-in-depth
# curtain that prevents a browser from targeting admin verbs that the
# SPA has no UI for and no business calling.
_ALLOWED_VERBS = {
    # NL surface
    "nl.ask",
    "nl.parse_only",
    "nl.metrics",
    # Registry list verbs
    "kg.list",
    "capsule.list",
    "capsule.install",
    "skill.list",
    "skill.run",
    "pattern.list",
    "session.list",
    "ownership.list",
    # Persona
    "persona.show",
    "persona.project",
    # Ingest
    "ingest.review",
    "ingest.approve",
    "ingest.deny",
    # Self-awareness (R103)
    "self.confidence",
    "self.gaps",
    # Preferences (R101)
    "user.preference.list",
    "user.preference.set",
    "user.preference.clear",
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


def _forward_to_daemon(verb: str, args: dict, token: str) -> str:
    """One connection per request, mirroring the daemon's serial shape.

    The daemon expects `{"verb": ..., "args": {...}, "token": "..."}` at
    top level (rpc_server.nova lifts `token` into the RpcContext for
    the capability gate). We only include the `token` field when the
    caller supplied one; absent field == anonymous, which is what a
    fresh SPA (pre-login) sends and what the daemon accepts when
    enforcement is off.
    """
    body: dict = {"verb": verb, "args": args}
    if token:
        body["token"] = token
    request = json.dumps(body, separators=(",", ":")) + "\n"
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


def _classify_error(err: str) -> int:
    """Map a wire error string to an HTTP status code.

    Sources in the daemon:
      - `"rate limit exceeded: ..."`               (capability.nova)
      - `"capability required: unknown token"`     (capability.nova) -> 401
      - `"capability required: token revoked"`     (capability.nova) -> 401
      - `"capability required: token expired"`     (capability.nova) -> 401
      - `"capability required: request missing 'token' field"`     -> 403
      - `"capability required: <capname>"`         (capability.nova) -> 403
      - `"capability required: admin:preference"`  (rpc_verbs.nova)  -> 403
      - `"unknown verb: <name>"`                   (rpc_verbs.nova)  -> 405
      - anything else                                                -> 400
    """
    e = err.lower()
    if "rate limit" in e:
        return 429
    if "capability required" in e:
        # Distinguish "the token itself is bad" (401) from "the token
        # is fine but lacks this cap" (403).
        if "unknown token" in e or "token revoked" in e or "token expired" in e:
            return 401
        return 403
    if "insufficient capability" in e:
        return 403
    if "invalid capability" in e:
        return 401
    if e.startswith("unknown verb"):
        return 405
    return 400


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
    server_version = "CrossEngin-web-shim/1.1"

    # Quieter logging -- default BaseHTTPRequestHandler logs every request
    # including static assets. We keep POST logs (they show verb dispatch)
    # and drop GETs for static files below.
    def log_message(self, format: str, *args) -> None:  # noqa: A003 (name inherited)
        sys.stderr.write("%s %s\n" % (self.address_string(), format % args))

    # ---- OPTIONS (CORS preflight) --------------------------------------
    def do_OPTIONS(self) -> None:  # noqa: N802
        # Even absent CORS, respond 204 to preflights so a mis-configured
        # browser at least sees "no headers" rather than a hang.
        self.send_response(204)
        self._maybe_cors_headers()
        self.send_header("Content-Length", "0")
        self.end_headers()

    # ---- POST /rpc/<verb> -----------------------------------------------
    def do_POST(self) -> None:  # noqa: N802
        parsed = urlsplit(self.path)
        if not parsed.path.startswith("/rpc/"):
            self._json(404, {"ok": False, "result": None,
                             "error": f"unknown POST path: {parsed.path}"})
            return
        verb = parsed.path[len("/rpc/"):]
        if verb not in _ALLOWED_VERBS:
            self._json(405, {"ok": False, "result": None,
                             "error": f"verb not allowed by shim: {verb}"})
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
        # Lift the caller-supplied token out of `args` so it rides at
        # the top of the wire message (where rpc_server.nova reads it).
        # A pre-R108 client that doesn't send one still works when the
        # daemon has enforcement off.
        token_val = ""
        if isinstance(body.get("token"), str):
            token_val = body.pop("token")
        try:
            wire_response = _forward_to_daemon(verb, body, token_val)
        except (ConnectionRefusedError, socket.timeout, OSError) as e:
            self._json(502, {"ok": False, "result": None,
                             "error": f"daemon unreachable at {RPC_HOST}:{RPC_PORT}: {e}"})
            return
        # Pass the daemon's response through as-is BUT set the HTTP
        # status from the envelope so the browser can distinguish
        # rate-limit / auth / cap / other errors uniformly. The body
        # (already JSON, already compact enough) is preserved verbatim.
        status = 200
        try:
            env = json.loads(wire_response) if wire_response else {}
        except json.JSONDecodeError:
            env = {}
        if isinstance(env, dict) and env.get("ok") is False:
            status = _classify_error(str(env.get("error") or ""))
        self._raw(status, wire_response.encode("utf-8"),
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
        # Compact JSON: no whitespace between separators. Cuts ~30% off
        # the body of small envelopes on the wire.
        body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        self._raw(status, body, content_type="application/json")

    def _raw(self, status: int, body: bytes, *, content_type: str) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self._maybe_cors_headers()
        self.end_headers()
        self.wfile.write(body)

    def _maybe_cors_headers(self) -> None:
        """Echo the request's Origin when it matches the allow-list.

        Loopback-first design: the default is NO CORS headers at all.
        An operator opts in with `--cors <origin>` (or CE_WEB_CORS);
        only exactly-matching origins get whitelisted. We deliberately
        do NOT send `Allow-Origin: *` -- if you want that, list each
        origin explicitly. Preflight-style Methods + Headers ride
        alongside so a browser preflight succeeds in one round-trip.
        """
        if not CORS_ORIGINS:
            return
        origin = self.headers.get("Origin", "")
        if origin and origin in CORS_ORIGINS:
            self.send_header("Access-Control-Allow-Origin", origin)
            self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")
            self.send_header("Access-Control-Allow-Headers", "Content-Type")
            self.send_header("Vary", "Origin")


def _parse_argv(argv: list[str]) -> None:
    """Fill CORS_ORIGINS from --cors flags + CE_WEB_CORS. Unknown flags
    print a usage line and exit 2 (mirrors the loopback safety gate)."""
    i = 1
    while i < len(argv):
        a = argv[i]
        if a == "--cors":
            if i + 1 >= len(argv):
                sys.stderr.write("ERROR: --cors requires an origin argument\n")
                raise SystemExit(2)
            CORS_ORIGINS.add(argv[i + 1])
            i += 2
            continue
        if a.startswith("--cors="):
            CORS_ORIGINS.add(a[len("--cors="):])
            i += 1
            continue
        if a in ("-h", "--help"):
            sys.stdout.write(__doc__ or "")
            raise SystemExit(0)
        sys.stderr.write(f"ERROR: unknown flag: {a}\n")
        sys.stderr.write("Usage: rpc_web_shim.py [--cors <origin>]...\n")
        raise SystemExit(2)
    env_cors = os.environ.get("CE_WEB_CORS", "").strip()
    if env_cors:
        for origin in env_cors.split(","):
            origin = origin.strip()
            if origin:
                CORS_ORIGINS.add(origin)


def main() -> int:
    _parse_argv(sys.argv)
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
    cors_line = ""
    if CORS_ORIGINS:
        cors_line = "CORS allow-list: " + ", ".join(sorted(CORS_ORIGINS)) + "\n"
    sys.stderr.write(
        f"=== CrossEngin web shim ===\n"
        f"listening on http://{WEB_BIND}:{WEB_PORT}/\n"
        f"static root: {WEB_ROOT}\n"
        f"forwarding /rpc/<verb> POSTs to {RPC_HOST}:{RPC_PORT} "
        f"(daemon: crossengin-rpc-daemon)\n"
        f"{cors_line}"
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
