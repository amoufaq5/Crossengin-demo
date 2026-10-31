# CrossEngin Web UI — operator + user guide (R108)

Written for two audiences in one document:

- **Operators** who run the HTTP shim and want to know what it exposes,
  how CORS + loopback + cap-tokens fit together, and how to smoke-test
  it after a version bump.
- **End users** who open the SPA in a browser and want to know what
  each panel does, how sign-in works, and what the coloured banners
  mean.

The SPA is `web/index.html` + `web/app.js` + `web/styles.css`, served
by the stdlib-only Python shim at `scripts/rpc_web_shim.py`. The shim
forwards every `POST /rpc/<verb>` to the JSON-RPC TCP daemon at
`127.0.0.1:9876`. This document is versioned to R108; earlier
information for the R51 minimal SPA lives in `docs/SHIP_AS_APP.md`
§7.5.

## Running the shim

Loopback default, no CORS, no auth:

```bash
python3 scripts/rpc_web_shim.py
# listening on http://127.0.0.1:8080/
# forwarding /rpc/<verb> POSTs to 127.0.0.1:9876
```

Non-default port (`CE_WEB_PORT`), non-loopback bind
(`CE_WEB_BIND` + explicit opt-in), and a whitelisted origin for
cross-origin browsers all layer via env / flags:

```bash
CE_WEB_PORT=18080 python3 scripts/rpc_web_shim.py
CE_WEB_BIND=0.0.0.0 CE_WEB_BIND_ALLOW_NON_LOOPBACK=1 python3 scripts/rpc_web_shim.py
python3 scripts/rpc_web_shim.py --cors http://localhost:9000
python3 scripts/rpc_web_shim.py --cors http://localhost:9000 --cors https://ops.example.com
CE_WEB_CORS=http://a.example,http://b.example python3 scripts/rpc_web_shim.py
```

`--cors` may be repeated; only exactly-matching `Origin` headers get a
CORS response, and the shim never emits `Allow-Origin: *`. A preflight
`OPTIONS` request returns `204` with `Access-Control-Allow-Methods:
POST, OPTIONS` and `Access-Control-Allow-Headers: Content-Type`.

## Signing in

The daemon enforces access via ADR-0054 capability tokens (see
`docs/SHIP_AS_APP.md` §7.7). The SPA collects the token in a modal
on first load:

1. Open `http://127.0.0.1:8080/` — the login modal appears.
2. Paste the token your operator issued via `capability.issue`
   (e.g. `tk-9a2f...`).
3. Click **Sign in**.

The token is stored in `localStorage` under `crossengin_token`; it
never leaves your browser except as the top-level `token` field of
each RPC body posted to the shim. Click **Continue without token**
to skip the modal — this works only when the daemon is running with
enforcement off (`CE_RPC_REQUIRE_TOKEN=0`).

**Log out** clears the token and re-opens the modal. When the daemon
rejects a call with `401` (unknown / revoked / expired token, or a
missing token when required), the modal re-opens automatically.

## HTTP status mapping (R108)

The shim inspects each wire envelope and picks an HTTP status the
browser can key on:

| envelope                                                | status |
|---------------------------------------------------------|:------:|
| `{ok:true, ...}`                                        |  200   |
| `{ok:false, error:"rate limit exceeded: ..."}`          |  429   |
| `{ok:false, error:"capability required: unknown token"}` | 401    |
| `{ok:false, error:"capability required: token revoked"}` | 401    |
| `{ok:false, error:"capability required: token expired"}` | 401    |
| `{ok:false, error:"capability required: <cap>"}`         | 403    |
| `{ok:false, error:"insufficient capability ..."}`        | 403    |
| `{ok:false, error:"invalid capability ..."}`             | 401    |
| `{ok:false, error:"unknown verb: <name>"}`               | 405    |
| any other `{ok:false, ...}`                              | 400    |
| shim allow-list rejects the verb                         | 405    |
| daemon unreachable                                       | 502    |

The envelope body is preserved verbatim so a curl-based client can
still parse `.error`; the status just gives browsers (and reverse
proxies) a first-class signal.

## Panel walk-through

The sidebar picks one of nine panels. Every list panel uses the R107
cursor pagination — an initial page of 50, plus a **Load more** button
that appears while the response carries a non-empty `next_after`.

### Ask (default)

The R51 core: freeform NL question, dispatches `nl.ask`, renders the
templated answer, cited sources, disagreement warnings when sources
disagree by ≥300 milli-belief, persona projection (advise-only),
effector calls (described, not executed), and a debug pane with the
raw `StructuredQuery`. **Parse only** posts `nl.parse_only` for a
grammar-parse debug view without dispatching a skill.

### Capsules

Every capsule visible to your holder (`capsule.list`). Rows show name,
version, and an `(uninstalled)` marker for capsules that are known but
not currently installed for the caller.

### Skills

Every skill visible to your holder (`skill.list`). Rows show name,
version, and hover-tooltip description; uninstalled skills are
labeled.

### KGs

Knowledge-graph labels the holder can see (`kg.list`), one per row.

### Patterns

Pattern-capsule inventory (`pattern.list`) — each row lists the pack
name, version, pattern count, and the source-tag prefix used at
match time.

### Confidence

Ad-hoc `self.confidence` probe: type a topic, submit, and the panel
shows the mode used (`exact` / `fuzzy` / `hybrid`), matched atom
count, aggregate confidence (rendered as a percentage of milli),
majority epistemic status, and the top-5 per-match rows with per-KG
label + belief + weight.

### Gaps

`self.gaps` entries for the current holder, paginated (cursor
`<timestamp_nanos>:<idx_within_ns>`). Each row shows the reason
(`no_match` / `low_confidence` / `refused` / `unparsed` /
`skill_refused`), the topic, an optional detail string, and the
timestamp (rendered as an ISO 8601 second when the number looks
Unix-shaped; raw counter otherwise).

### NL metrics

`nl.metrics` per-holder table (`total`, `unparsed`,
`llm_fallback_attempts`, `_successes`, `_failures`, and a derived
`fallback %`). The aggregate row `_total_all_holders` — invariant
across pages per R107 — is highlighted.

### Preferences

Per-user selective load (`user.preference.set`, `.list`, `.clear` —
ADR-0205). Pick a kind (capsule / skill / pattern / kg), type a name,
toggle enabled, and submit; **Clear** removes the row for the current
name (or every row for that holder when the name field is empty).

## Error banners

A coloured banner slides in at the top of the page and auto-dismisses
after 5 s (or clears on the next successful call):

- **Amber (warn)** — rate limit exceeded. Retry in ~1 s.
- **Red (bad)** — the token lacks permission for the action, or the
  token is missing/invalid (the login modal re-opens in the second
  case).
- **Grey (net)** — the shim is unreachable. Check that
  `scripts/rpc_web_shim.py` is running and the browser can reach the
  port.

Each banner carries an "x" close button (44 px min-height on mobile
for touch).

## Mobile support

The SPA is responsive at two breakpoints:

- `≤ 780 px` — sidebar collapses into a horizontal chip strip above
  the main pane (kept from R51).
- `≤ 640 px` — sidebar hides entirely and toggles via the header
  hamburger (`&#9776;`); panels stack single-column, base font
  bumps to 15.5 px, every interactive control gets a 44 px min-height
  (iOS accessibility guideline), and the login modal fills the
  viewport.

The `<meta name="viewport" content="width=device-width,initial-scale=1">`
is still in the head; Chrome DevTools' 375×667 (iPhone 8) profile
renders without horizontal scroll.

## Manual smoke checklist

R108 has no NOVA `.nova` unit coverage — it is Python + HTML/CSS/JS.
Verification is manual against a live daemon:

1. **Shim starts + serves static.**
   ```bash
   python3 scripts/rpc_web_shim.py &
   curl -sI http://127.0.0.1:8080/ | head -1     # HTTP/1.0 200 OK
   curl -s  http://127.0.0.1:8080/healthz         # "ok"
   ```

2. **RPC forwarding.**
   ```bash
   curl -s -X POST http://127.0.0.1:8080/rpc/kg.list \
     -H 'Content-Type: application/json' -d '{"limit":5}'
   # {"ok":true,"result":{"labels":[...],"next_after":"..."},"error":""}
   ```

3. **Auth mapping (daemon enforcement on).**
   ```bash
   curl -si -X POST http://127.0.0.1:8080/rpc/capability.list \
     -H 'Content-Type: application/json' -d '{}'
   # HTTP/1.0 401 (or 403, depending on the daemon's config)
   ```

4. **Rate-limit mapping.** With an admin token, drop `qps_max=1`
   on a reader token, then hit it twice back-to-back:
   ```bash
   curl -si -X POST http://127.0.0.1:8080/rpc/kg.list \
     -H 'Content-Type: application/json' \
     -d '{"token":"tk-reader","limit":1}'
   # second call within one second -> HTTP/1.0 429
   ```

5. **CORS preflight.**
   ```bash
   python3 scripts/rpc_web_shim.py --cors http://localhost:9000 &
   curl -si -X OPTIONS http://127.0.0.1:8080/rpc/kg.list \
     -H 'Origin: http://localhost:9000'
   # HTTP/1.0 204
   # Access-Control-Allow-Origin: http://localhost:9000
   # Access-Control-Allow-Methods: POST, OPTIONS
   # Access-Control-Allow-Headers: Content-Type
   ```

6. **JSON compaction.** Wire responses now dump with
   `separators=(",", ":")`:
   ```bash
   curl -s -X POST http://127.0.0.1:8080/rpc/kg.list \
     -H 'Content-Type: application/json' -d '{"limit":1}' \
     | grep -c '  ' && echo "not compact" || echo "compact"
   ```

7. **Mobile viewport.** Chrome DevTools -> device toolbar ->
   `iPhone SE` (375×667). No horizontal scroll; the sidebar
   collapses under the hamburger; every button ≥ 44 px tall.

## Non-goals in R108

- **Streaming / SSE / WebSockets** — the daemon is line-oriented, one
  response per connection. A push channel needs runtime work.
- **Batch requests** — a batched wire violates the daemon's one-line-
  per-connection invariant.
- **Native mobile client** — deferred per ADR-0209 Mode 5.
- **Client-side offline mode** — the SPA is a thin RPC console, not
  a PWA.

## References

- ADR-0209 — Deployment form factors (this SPA is Mode 4).
- ADR-0054 / R55.x — Capability tokens.
- R107 (`docs/SHIP_AS_APP.md` §7.56) — Uniform cursor pagination the
  SPA now consumes.
- `scripts/rpc_web_shim.py` — the shim source (stdlib only).
- `web/app.js` — the SPA client (vanilla JS, no framework).
