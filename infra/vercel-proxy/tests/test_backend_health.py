#!/usr/bin/env python3
"""
Smoke test: the backend /health endpoint.

Usage:
    python3 tests/test_backend_health.py [URL]

Default URL is http://localhost:8080. Exits 0 on pass, 1 on fail; suitable
for a CI gate or a manual sanity check after `docker compose up`.

Validates:
    * /health returns 200.
    * Content-Type is application/json.
    * Body parses as JSON with {"status": "ok", "binary": str,
      "oneshot": bool, "sessions": int}.
"""
import json
import sys
import urllib.error
import urllib.request


def fail(msg):
    print(f"FAIL: {msg}", file=sys.stderr)
    sys.exit(1)


def test_health(base_url):
    url = base_url.rstrip("/") + "/health"
    print(f"GET {url}")
    try:
        req = urllib.request.Request(url, method="GET")
        with urllib.request.urlopen(req, timeout=5) as resp:
            status = resp.status
            content_type = resp.headers.get("Content-Type", "")
            body = resp.read().decode("utf-8")
    except urllib.error.URLError as e:
        fail(f"backend unreachable: {e}")
        return  # unreachable; keeps linters happy

    if status != 200:
        fail(f"expected 200, got {status}")

    if "application/json" not in content_type:
        fail(f"expected JSON content-type, got {content_type!r}")

    try:
        payload = json.loads(body)
    except json.JSONDecodeError as e:
        fail(f"body did not parse as JSON: {e}; body={body!r}")
        return

    required = {
        "status": str,
        "binary": str,
        "oneshot": bool,
        "sessions": int,
    }
    for key, ty in required.items():
        if key not in payload:
            fail(f"missing key {key!r} in {payload!r}")
        if not isinstance(payload[key], ty):
            fail(
                f"key {key!r} has type {type(payload[key]).__name__}, "
                f"expected {ty.__name__}"
            )
    if payload["status"] != "ok":
        fail(f"expected status='ok', got {payload['status']!r}")

    print("PASS: /health 200 with valid JSON shape")
    print(f"  binary       = {payload['binary']}")
    print(f"  oneshot mode = {payload['oneshot']}")
    print(f"  sessions     = {payload['sessions']}")


def test_chat_requires_auth(base_url):
    """A POST to /chat without a bearer token must return 401."""
    url = base_url.rstrip("/") + "/chat"
    body = json.dumps({"session_id": "smoke", "input": "hello"}).encode("utf-8")
    req = urllib.request.Request(
        url,
        method="POST",
        data=body,
        headers={"Content-Type": "application/json"},
    )
    print(f"POST {url} (no auth, expect 401)")
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            status = resp.status
    except urllib.error.HTTPError as e:
        status = e.code
    except urllib.error.URLError as e:
        fail(f"backend unreachable: {e}")
        return

    if status != 401:
        fail(f"expected 401, got {status}")
    print("PASS: unauthenticated /chat returns 401")


def main():
    base_url = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8080"
    test_health(base_url)
    test_chat_requires_auth(base_url)
    print("OK -- backend smoke tests pass")


if __name__ == "__main__":
    main()
