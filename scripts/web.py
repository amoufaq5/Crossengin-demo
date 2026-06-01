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

Diagnostic endpoints:
    GET /api/sessions -> JSON list of {id, last_active_ms, age_ms}.
    GET /metrics      -> Prometheus text-format scrape (P2.9). Bound to the
                        same loopback default as /api/chat -- the probe is
                        read-only (calls the chat's `/__metrics__` admin
                        command, which only polls mo_poll and reads counters)
                        and rate-limited to once per CE_METRICS_CACHE_S
                        (default 10 seconds) per cookie. Cached responses
                        let external scrapers (Prometheus, Grafana Agent)
                        hit /metrics at the usual 15s scrape interval
                        without serializing on the chat children.

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
# P2.9: how long a /metrics probe response is reused before refreshing. The
# probe is cheap (one round-trip into a chat child plus a ~few-line parse) but
# we don't want a Prometheus scraper at 15s intervals to serialize against
# normal /api/chat traffic, so default 10s gives at most one fresh probe per
# scrape window even with multiple scrapers per cookie.
METRICS_CACHE_S = float(os.environ.get("CE_METRICS_CACHE_S", 10.0))
# P-AA: how long a /__atoms__ probe response is reused before refreshing. The
# probe walks the active session's reasoning + language KGs and emits up to
# ~1000 ATOM lines; a 30s cache keeps the GET /api/atoms search snappy even
# under a tight reload loop in the browser without serializing on the chat
# child for every keystroke.
ATOMS_CACHE_S = float(os.environ.get("CE_ATOMS_CACHE_S", 30.0))
# Hard cap on the /api/atoms response size so an unbounded q="" search can't
# blow up the browser. The chat-side probe is already capped at ~1000 atoms
# per session; the server-side filter trims further to this many matches.
ATOMS_RESPONSE_LIMIT = int(os.environ.get("CE_ATOMS_RESPONSE_LIMIT", 200))


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
        # P2.9: per-cookie POST counter and a tiny rolling latency window for
        # the Prometheus scrape. `request_total` is a plain int (Counter); the
        # latency window is the last N samples we average + cap into the
        # response (a Prometheus Summary's _count / _sum is exact, the
        # quantiles are approximate -- a uniform-cap rolling window is good
        # enough at our request rate). `evicted_total` counts LRU evictions
        # since startup (a process-wide Counter); the live total is len(children).
        self.request_total = {}            # cookie -> int
        self.request_durations = []        # rolling list of seconds (float)
        self.request_durations_max = 256
        self.evicted_total = 0
        # P2.9 probe cache: cookie -> (expire_at, parsed_dict). The dict is the
        # `key=value` map parsed out of the /__metrics__ block; we re-render
        # the Prometheus text on every /metrics call but skip the actual probe
        # while the cache is fresh. Each entry has its own expiry so different
        # cookies don't share a single TTL.
        self.metrics_cache = {}            # cookie -> (float expire, dict)
        self.metrics_lock = threading.Lock()
        # P-AA: per-cookie /__atoms__ cache. Same shape as metrics_cache, but
        # the value is the parsed atom list (see _parse_atoms_block).
        self.atoms_cache = {}              # cookie -> (float expire, list[dict])
        self.atoms_lock = threading.Lock()
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
            self.evicted_total += 1
            # /quit the victim outside our brief lock -- shutdown() can
            # block for up to 3s waiting for the child to drain.
            child = victim_entry[0]
            threading.Thread(target=child.shutdown, daemon=True).start()

    def note_request(self, cookie, duration_s):
        """Record one /api/chat POST for this cookie (counter += 1) and
        append the wall-clock duration to the rolling latency window. Called
        from the request handler after `child.send` returns (success or not).
        """
        with self.lock:
            self.request_total[cookie] = self.request_total.get(cookie, 0) + 1
            self.request_durations.append(float(duration_s))
            if len(self.request_durations) > self.request_durations_max:
                # Drop oldest -- the rolling window stays bounded so a long-
                # running server doesn't grow without bound. Prometheus
                # quantiles are approximate anyway; the _count / _sum we
                # emit IS exact (running totals on top of the bounded list).
                self.request_durations.pop(0)

    def request_metrics_snapshot(self):
        """Return ({cookie: count}, [durations]) for the /metrics renderer.
        Both shallow copies; the caller iterates without holding our lock."""
        with self.lock:
            return dict(self.request_total), list(self.request_durations)

    def evicted_count(self):
        with self.lock:
            return self.evicted_total

    def cookie_for_probe(self):
        """Return the cookie of the most-recently-active child, or None if
        there are no live children. /metrics callers without their own cookie
        (typical for a Prometheus scrape) probe whatever sessions exist
        instead of spawning a fresh child for the scraper itself."""
        with self.lock:
            if not self.children:
                return None
            # Most-recently-active first -- a scrape that piggy-backs on the
            # already-warm child is cheaper than waking an idle one.
            return max(
                self.children.items(),
                key=lambda kv: kv[1][2],
            )[0]

    def probe_metrics(self, cookie, now):
        """Run a /__metrics__ probe against the chat child bound to `cookie`
        (or serve a cached value within METRICS_CACHE_S). Returns a parsed
        `dict` of `key -> value` (values are strings; the renderer converts).
        Raises if the cookie has no live child."""
        with self.metrics_lock:
            entry = self.metrics_cache.get(cookie)
            if entry is not None and entry[0] > now:
                return dict(entry[1])
        # Fall through: probe the child without holding metrics_lock. The
        # child's request_lock serializes against /api/chat already.
        with self.lock:
            child_entry = self.children.get(cookie)
            child = child_entry[0] if child_entry else None
        if child is None:
            raise RuntimeError(f"no live child for cookie {cookie}")
        raw = child.send("/__metrics__")
        parsed = _parse_metrics_block(raw)
        with self.metrics_lock:
            self.metrics_cache[cookie] = (now + METRICS_CACHE_S, parsed)
        return dict(parsed)

    def probe_atoms(self, cookie, now):
        """Run a /__atoms__ probe against the chat child bound to `cookie`
        (or serve a cached value within ATOMS_CACHE_S). Returns a list of
        dicts shaped like
            {"id": int, "label": str, "kind": str, "kg": str, "belief_mean": int}
        ready for the /api/atoms JSON response. Raises if the cookie has no
        live child."""
        with self.atoms_lock:
            entry = self.atoms_cache.get(cookie)
            if entry is not None and entry[0] > now:
                return list(entry[1])
        with self.lock:
            child_entry = self.children.get(cookie)
            child = child_entry[0] if child_entry else None
        if child is None:
            raise RuntimeError(f"no live child for cookie {cookie}")
        raw = child.send("/__atoms__")
        parsed = _parse_atoms_block(raw)
        with self.atoms_lock:
            self.atoms_cache[cookie] = (now + ATOMS_CACHE_S, parsed)
        return list(parsed)

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
# P2.9: /metrics. The chat child's `/__metrics__` admin command emits a block
# bounded by `METRICS_BEGIN` / `METRICS_END` with one `key=value` line per
# metric. We parse that into a dict, then render Prometheus text-format with
# the per-cookie labels.

# Prometheus label-value escaping per the exposition format spec: backslash,
# newline, double-quote.
def _esc_label(v):
    return (
        str(v)
        .replace("\\", "\\\\")
        .replace("\n", "\\n")
        .replace('"', '\\"')
    )


def _parse_metrics_block(raw):
    """Extract `key=value` lines bounded by METRICS_BEGIN / METRICS_END.
    Returns a dict; unparseable lines are skipped silently (the chat-side
    block is well-defined, but the chat also prints a trailing perceive line
    we want to ignore)."""
    out = {}
    in_block = False
    for line in raw.splitlines():
        line = line.strip()
        if line == "METRICS_BEGIN":
            in_block = True
            continue
        if line == "METRICS_END":
            in_block = False
            continue
        if not in_block:
            continue
        if "=" not in line:
            continue
        k, v = line.split("=", 1)
        out[k.strip()] = v.strip()
    return out


# Map kind ids (atom_kind from src/kg/atom_store.nova) to human labels. The
# chat emits the raw integer; the python side renames so the JSON consumer
# (browser) gets a readable string. Anything outside the table is reported
# as "unknown" with the numeric value preserved for diagnosis.
_KIND_NAMES = {
    1: "fact",
    2: "relation",
    3: "concept",
    4: "skill",
    5: "lang",
    6: "rule",
}


def _parse_atoms_block(raw):
    """Extract `ATOM kg=... id=... kind=... label=... belief_mean=...` lines
    bounded by ATOMS_BEGIN / ATOMS_END. Returns a list of dicts. Unparseable
    lines are skipped (defensive against trailing perceive lines from the
    chat surface)."""
    out = []
    in_block = False
    for line in raw.splitlines():
        stripped = line.strip()
        if stripped == "ATOMS_BEGIN":
            in_block = True
            continue
        if stripped == "ATOMS_END":
            in_block = False
            continue
        if not in_block:
            continue
        if not stripped.startswith("ATOM "):
            continue
        # Parse the four whitespace-separated KEY=VALUE pairs that come after
        # the ATOM prefix. label= can contain anything but newline -- it is
        # the LAST field, so we split off the leading 4 tokens and take the
        # remainder as the label. (No labels with spaces today, but this
        # keeps the parser robust if a future ingestor allows them.)
        body = stripped[len("ATOM "):]
        fields = {}
        # Walk tokens left-to-right; once we hit "label=" capture the rest.
        rest = body
        while rest:
            eq = rest.find("=")
            if eq < 0:
                break
            key = rest[:eq]
            value_start = eq + 1
            if key == "label":
                # Take everything until the next space-delimited key (we know
                # belief_mean is the only field that comes after label in the
                # chat-emitted order, so split on " belief_mean=" if present).
                tail = rest[value_start:]
                marker = " belief_mean="
                if marker in tail:
                    label_val, _, rest_after = tail.partition(marker)
                    fields["label"] = label_val
                    rest = "belief_mean=" + rest_after
                else:
                    fields["label"] = tail
                    rest = ""
                continue
            sp = rest.find(" ", value_start)
            if sp < 0:
                fields[key] = rest[value_start:]
                rest = ""
            else:
                fields[key] = rest[value_start:sp]
                rest = rest[sp + 1:]
        # Must have id + label at a minimum to be usable.
        if "id" not in fields or "label" not in fields:
            continue
        try:
            atom_id_int = int(fields["id"])
        except ValueError:
            continue
        try:
            kind_int = int(fields.get("kind", "0"))
        except ValueError:
            kind_int = 0
        try:
            belief_int = int(fields.get("belief_mean", "0"))
        except ValueError:
            belief_int = 0
        out.append({
            "id": atom_id_int,
            "label": fields["label"],
            "kind": _KIND_NAMES.get(kind_int, "unknown"),
            "kg": fields.get("kg", ""),
            "belief_mean": belief_int,
        })
    return out


def _milli_to_unit(v):
    """ADR-0050 percentages and ADR-0034 mood values are stored as milli
    (0..1000). The Prometheus convention is a unit-scale 0..1 gauge, so we
    divide by 1000 for the on-the-wire value."""
    try:
        return float(v) / 1000.0
    except (TypeError, ValueError):
        return 0.0


def _as_float(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return 0.0


def render_prometheus(store):
    """Compose a Prometheus text-format response from a probe of every live
    session plus the process-wide counters. The body is a single string with
    LF line terminators per the spec; the HTTP handler sets the matching
    `Content-Type: text/plain; version=0.0.4` header."""
    now = time.time()
    lines = []

    # ---- per-session gauges (probed via /__metrics__) -------------------
    # Walk the live children with their cookies; the probe is cached per
    # cookie so a tight scrape loop only round-trips into the child once
    # per METRICS_CACHE_S.
    sessions = store.snapshot()
    per_sid_metrics = []  # [(sid, parsed_dict)]
    for sess in sessions:
        sid = sess["id"]
        try:
            parsed = store.probe_metrics(sid, now)
        except Exception:
            # A child that has exited mid-probe shouldn't poison the whole
            # response; just skip its row.
            continue
        per_sid_metrics.append((sid, parsed))

    def emit(name, help_text, metric_type, samples):
        # samples: list of (label_str, float_value)
        lines.append(f"# HELP {name} {help_text}")
        lines.append(f"# TYPE {name} {metric_type}")
        for label_str, value in samples:
            if label_str:
                lines.append(f"{name}{{{label_str}}} {value}")
            else:
                lines.append(f"{name} {value}")

    # atom_count (reasoning + language)
    reasoning_samples = []
    language_samples = []
    refl_samples = []
    dlog_samples = []
    valence_samples = []
    arousal_samples = []
    tick_rate_samples = []
    overrun_samples = []
    promotion_samples = {}   # source -> [(sid, value)]
    atrophy_samples = {}     # source -> [(sid, value)]
    for sid, parsed in per_sid_metrics:
        lbl = f'sid="{_esc_label(sid)}"'
        reasoning_samples.append(
            (f'kg="reasoning",sid="{_esc_label(sid)}"',
             _as_float(parsed.get("atom_count_reasoning", 0))))
        language_samples.append(
            (f'kg="language",sid="{_esc_label(sid)}"',
             _as_float(parsed.get("atom_count_language", 0))))
        refl_samples.append(
            (lbl, _as_float(parsed.get("refl_atom_count", 0))))
        dlog_samples.append(
            (lbl, _as_float(parsed.get("dlog_entries", 0))))
        valence_samples.append(
            (lbl, _milli_to_unit(parsed.get("soul_mood_valence", 0))))
        arousal_samples.append(
            (lbl, _milli_to_unit(parsed.get("soul_mood_arousal", 0))))
        tick_rate_samples.append(
            (lbl, _as_float(parsed.get("scheduler_rate_hz", 0))))
        overrun_samples.append(
            (lbl, _as_float(parsed.get("scheduler_overruns", 0))))
        # promotion_milli_<source> / atrophy_milli_<source>
        for k, v in parsed.items():
            if k.startswith("promotion_milli_"):
                src = k[len("promotion_milli_"):]
                promotion_samples.setdefault(src, []).append(
                    (f'source="{_esc_label(src)}",sid="{_esc_label(sid)}"',
                     _milli_to_unit(v)))
            elif k.startswith("atrophy_milli_"):
                src = k[len("atrophy_milli_"):]
                atrophy_samples.setdefault(src, []).append(
                    (f'source="{_esc_label(src)}",sid="{_esc_label(sid)}"',
                     _milli_to_unit(v)))

    emit("crossengin_atom_count",
         "Atoms in a per-session knowledge graph (kg label: reasoning|language).",
         "gauge", reasoning_samples + language_samples)
    emit("crossengin_refl_atom_count",
         "Tentative reflection-KG atoms per session.",
         "gauge", refl_samples)
    emit("crossengin_dlog_entries",
         "Decision-log entries per session (ADR-0043).",
         "gauge", dlog_samples)
    # Promotion / atrophy: one TYPE line per metric name, sources interleaved.
    promo_all = []
    for src, rows in promotion_samples.items():
        promo_all.extend(rows)
    emit("crossengin_promotion_rate",
         "Per-source promotion rate (tentative->durable) from /meta (ADR-0050, unit scale 0..1).",
         "gauge", promo_all)
    atroph_all = []
    for src, rows in atrophy_samples.items():
        atroph_all.extend(rows)
    emit("crossengin_atrophy_rate",
         "Per-source atrophy rate (durable->sub-threshold or vanished) from /meta (ADR-0050, unit scale 0..1).",
         "gauge", atroph_all)
    emit("crossengin_soul_mood_valence",
         "Soul mood valence (ADR-0034, unit scale 0..1).",
         "gauge", valence_samples)
    emit("crossengin_soul_mood_arousal",
         "Soul mood arousal (ADR-0034, unit scale 0..1).",
         "gauge", arousal_samples)
    emit("crossengin_scheduler_tick_rate",
         "Current hybrid-scheduler rate in Hz (100=active, 10=idle; ADR-0037).",
         "gauge", tick_rate_samples)
    emit("crossengin_scheduler_overruns",
         "Realtime pacer overrun count per session (P0.6; 0 in chat mode -- pacer is daemon-only).",
         "counter", overrun_samples)

    # ---- process-wide gauges -------------------------------------------
    emit("crossengin_active_session_count",
         "Total live sessions in web.py's per-cookie store.",
         "gauge", [("", float(len(sessions)))])
    emit("crossengin_evicted_session_count",
         "Cumulative LRU evictions since web.py startup.",
         "counter", [("", float(store.evicted_count()))])

    # ---- per-cookie request counter ------------------------------------
    request_total, durations = store.request_metrics_snapshot()
    request_rows = [
        (f'cookie="{_esc_label(c)}"', float(n))
        for c, n in request_total.items()
    ]
    emit("crossengin_request_total",
         "Total /api/chat POST count per cookie since web.py startup.",
         "counter", request_rows)

    # ---- request duration summary --------------------------------------
    # Approximate: _count and _sum are exact over the rolling window; the
    # 0.5 / 0.9 / 0.99 quantiles are computed from the window snapshot.
    count = len(durations)
    total = sum(durations)
    lines.append("# HELP crossengin_request_duration_seconds /api/chat wall-clock latency over the last 256 requests.")
    lines.append("# TYPE crossengin_request_duration_seconds summary")
    if count > 0:
        ordered = sorted(durations)
        for q in (0.5, 0.9, 0.99):
            idx = int(q * (count - 1))
            lines.append(
                f'crossengin_request_duration_seconds{{quantile="{q}"}} {ordered[idx]}'
            )
    lines.append(f"crossengin_request_duration_seconds_count {count}")
    lines.append(f"crossengin_request_duration_seconds_sum {total}")

    # Spec requires a trailing newline; concatenate and add the LF.
    return "\n".join(lines) + "\n"


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


# P-AA: tiny standalone HTML+JS for the /atoms search page. Vanilla JS so the
# page works without any framework or build step; the form GETs /api/atoms?q=...
# and renders the resulting JSON as a table.
ATOMS_HTML = r"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>CrossEngin atom search</title>
<style>
  body { font: 14px/1.5 system-ui, -apple-system, "Segoe UI", sans-serif;
         max-width: 880px; margin: 2rem auto; padding: 0 1rem; color: #222; }
  h1 { margin: 0 0 .25rem; font-size: 1.25rem; }
  .meta { color: #666; margin-bottom: 1rem; font-size: 13px; }
  form { display: flex; gap: .5rem; margin-bottom: 1rem; align-items: center; }
  input[type=text] { flex: 1; padding: .5rem .75rem; font: inherit;
                     border: 1px solid #aaa; border-radius: 6px; }
  select { padding: .5rem; font: inherit; border: 1px solid #aaa;
           border-radius: 6px; }
  button { padding: .5rem 1rem; font: inherit; border: 1px solid #888;
           border-radius: 6px; background: #f4f4f4; cursor: pointer; }
  button:hover { background: #eaeaea; }
  table { width: 100%; border-collapse: collapse; font: 13px/1.4 ui-monospace,
          "SF Mono", Menlo, monospace; }
  th, td { padding: .35rem .6rem; border-bottom: 1px solid #eee;
           text-align: left; vertical-align: top; }
  th { background: #f9f9f9; color: #333; font-weight: 600; font-size: 12px;
       text-transform: uppercase; letter-spacing: .03em; }
  tr:hover { background: #fafafa; }
  .empty { color: #888; padding: 1rem .6rem; }
  .err   { color: #b22; padding: 1rem .6rem; }
  .belief { color: #555; font-variant-numeric: tabular-nums; }
  .kind   { color: #0a7f2e; }
  .kg     { color: #1a52b8; }
  code { background: #f4f4f4; padding: 0 .2rem; border-radius: 3px; }
  nav { color: #888; font-size: 12px; margin-bottom: 1rem; }
  nav a { color: #1a52b8; text-decoration: none; }
</style>
</head>
<body>
<h1>CrossEngin atom search</h1>
<nav><a href="/">chat</a> &middot; <a href="/atoms">atoms</a> &middot;
  <a href="/metrics">metrics</a> &middot; <a href="/api/sessions">sessions</a>
</nav>
<p class="meta">Browse the active session's knowledge graphs by label
substring. Type any fragment of a label (case-sensitive substring) and press
Search.</p>
<form id="form" autocomplete="off">
  <input id="q" type="text" placeholder="label substring (e.g. fever)" autofocus>
  <select id="kg">
    <option value="">all KGs</option>
    <option value="reasoning">reasoning</option>
    <option value="language">language</option>
  </select>
  <input id="limit" type="text" value="50" style="flex:0 0 4rem">
  <button type="submit">Search</button>
</form>
<div id="result"></div>

<script>
const form   = document.getElementById('form');
const qIn    = document.getElementById('q');
const kgIn   = document.getElementById('kg');
const limIn  = document.getElementById('limit');
const resBox = document.getElementById('result');

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, ch => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
  }[ch]));
}

function renderRows(atoms) {
  if (!atoms.length) {
    resBox.innerHTML = '<div class="empty">no matching atoms.</div>';
    return;
  }
  const rows = atoms.map(a => `
    <tr>
      <td>${escapeHtml(a.id)}</td>
      <td>${escapeHtml(a.label)}</td>
      <td class="kind">${escapeHtml(a.kind)}</td>
      <td class="kg">${escapeHtml(a.kg)}</td>
      <td class="belief">${escapeHtml(a.belief_mean)}</td>
    </tr>`).join('');
  resBox.innerHTML = `<table>
    <thead><tr>
      <th>ID</th><th>Label</th><th>Kind</th><th>KG</th><th>Belief (milli)</th>
    </tr></thead>
    <tbody>${rows}</tbody>
  </table>`;
}

form.addEventListener('submit', async (e) => {
  e.preventDefault();
  const q = qIn.value;
  const kg = kgIn.value;
  const limit = limIn.value;
  const params = new URLSearchParams();
  if (q)    params.set('q', q);
  if (kg)   params.set('kg', kg);
  if (limit) params.set('limit', limit);
  resBox.innerHTML = '<div class="empty">searching...</div>';
  try {
    const r = await fetch('/api/atoms?' + params.toString());
    const j = await r.json();
    if (j.error) {
      resBox.innerHTML = '<div class="err">ERROR: ' + escapeHtml(j.error) + '</div>';
    } else {
      renderRows(j.atoms || []);
    }
  } catch (err) {
    resBox.innerHTML = '<div class="err">network ERROR: ' + escapeHtml(err.message) + '</div>';
  }
});

// Convenience: empty submit shows everything (up to limit).
form.dispatchEvent(new Event('submit'));
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


def _url_decode(s):
    """Tiny percent-decoder for query-string values. Replaces '+' with space
    and '%XX' with the matching byte. Avoids pulling in urllib.parse for a
    three-line conversion (the only chars we expect are letters, digits,
    underscore, dash, and the occasional %20 from a browser submit)."""
    if not s:
        return ""
    s = s.replace("+", " ")
    out = []
    i = 0
    while i < len(s):
        ch = s[i]
        if ch == "%" and i + 2 < len(s):
            try:
                out.append(chr(int(s[i + 1:i + 3], 16)))
                i += 3
                continue
            except ValueError:
                pass
        out.append(ch)
        i += 1
    return "".join(out)


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

        def _send_text(self, body, content_type="text/plain; charset=utf-8"):
            data = body.encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(data)))
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
            if self.path == "/metrics":
                # P2.9: Prometheus text-format scrape. Read-only (the
                # underlying probe just polls counters via /__metrics__);
                # bound to the same loopback default as /api/chat. We do NOT
                # call store.get_or_create here -- a Prometheus scraper has
                # no business spawning a fresh ChatChild just to scrape.
                # render_prometheus walks the existing live sessions and
                # piggy-backs on them via the per-cookie probe cache.
                try:
                    body = render_prometheus(store)
                except Exception as e:
                    return self._send_json(500, {"error": str(e)})
                # Standard exposition Content-Type per the OpenMetrics spec
                # (Prometheus accepts text/plain too, but versioned form is
                # the canonical choice -- avoid the "no version" warning in
                # Prometheus's log when it scrapes us).
                return self._send_text(
                    body,
                    content_type="text/plain; version=0.0.4; charset=utf-8",
                )
            # P-AA: server-side rendered HTML atom search UI. Static page;
            # the JS hits /api/atoms below. Like /, we Set-Cookie on a fresh
            # visit so the JS query travels with the cookie that owns the
            # session whose atoms we want to surface.
            if self.path == "/atoms":
                return self._send_html(ATOMS_HTML, set_cookie=set_cookie)
            # P-AA: /api/atoms?q=&limit=&kg= -- searches the active session's
            # KGs by label substring. Read-only (the underlying /__atoms__
            # probe just walks atom storage); we DO call get_or_create here
            # so a browser visiting /atoms can ALWAYS see its own session
            # (the chat is what owns the per-cookie cognitive state).
            if self.path.startswith("/api/atoms"):
                # Parse the query string manually to avoid importing urllib.parse
                # for a 3-field decode -- the spec is tiny.
                qs = ""
                if "?" in self.path:
                    qs = self.path.split("?", 1)[1]
                params = {}
                for part in qs.split("&") if qs else []:
                    if "=" in part:
                        k, v = part.split("=", 1)
                        params[_url_decode(k)] = _url_decode(v)
                    elif part:
                        params[_url_decode(part)] = ""
                q = params.get("q", "")
                kg_filter = params.get("kg", "")
                try:
                    limit = int(params.get("limit", ATOMS_RESPONSE_LIMIT))
                except ValueError:
                    limit = ATOMS_RESPONSE_LIMIT
                if limit <= 0 or limit > ATOMS_RESPONSE_LIMIT:
                    limit = ATOMS_RESPONSE_LIMIT
                try:
                    store.get_or_create(cookie)
                    atoms = store.probe_atoms(cookie, time.time())
                except Exception as e:
                    return self._send_json(
                        500, {"error": str(e)}, set_cookie=set_cookie,
                    )
                matched = []
                for a in atoms:
                    if q and q not in a["label"]:
                        continue
                    if kg_filter and a["kg"] != kg_filter:
                        continue
                    matched.append(a)
                    if len(matched) >= limit:
                        break
                return self._send_json(
                    200,
                    {"atoms": matched},
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
            # P2.9: time the round-trip so /metrics can publish a request
            # duration summary. The counter ticks once per attempt regardless
            # of outcome (a 504/500 is still a request the operator wanted to
            # count).
            t0 = time.time()
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
            finally:
                store.note_request(cookie, time.time() - t0)

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
