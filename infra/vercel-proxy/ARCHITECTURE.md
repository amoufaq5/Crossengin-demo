# Vercel-hybrid reference architecture

This is the architecture R36F's `docs/GETTING_STARTED.md` Section 5 names
but defers ("infra/vercel-proxy/ reference architecture deferred"). The
diagram + flow below mirror what the code in `web/` + `backend/` actually
implements.

## End-to-end flow

```
+---------+   HTTPS    +---------------------------+   HTTPS    +-----------------------------+
| Browser | ---------> |     Vercel edge / CDN     | ---------> |     Linux backend host       |
+---------+            |  - serves app/page.tsx    |  Bearer    |  - server.py listens :8080  |
                       |  - runs /api/chat route   |  token     |  - spawns bin/crossengin-   |
                       +---------------------------+            |    chat per session_id      |
                                                                |  - /data volume for         |
                                                                |    persistence              |
                                                                +-----------------------------+
```

### Per-turn timeline

1. User types into `<input>` in `web/app/page.tsx`.
2. Browser issues `POST /api/chat` with `{session_id, input}`.
3. Vercel Function `web/app/api/chat/route.ts` reads env vars, forwards
   the body verbatim to `${CROSSENGIN_URL}/chat` with
   `Authorization: Bearer ${CROSSENGIN_TOKEN}`.
4. The Linux backend (`backend/server.py`) validates the bearer and
   either:
   - (default) routes to the persistent `bin/crossengin-chat` child
     bound to that `session_id`, writing the input to stdin and
     blocking until the next prompt token.
   - (one-shot fallback when `CE_BIN=bin/crossengin`) runs the
     `scripts/chat.sh` algorithm: write input to `/tmp/crossengin_input`,
     run the binary, grep the `agent>` line.
5. Reply text is written as the HTTP response body.
6. Vercel Function streams the body back to the browser; `page.tsx`
   renders it as the next agent turn.

## Components shipped

| Component                                        | Path                                  | Role                                              |
|--------------------------------------------------|---------------------------------------|---------------------------------------------------|
| Next.js 14 App Router project                    | `web/`                                | Chat UI + Vercel Function host.                   |
| `/api/chat` Vercel Function                      | `web/app/api/chat/route.ts`           | Bearer-token proxy with timeouts + size caps.     |
| Chat UI                                          | `web/app/page.tsx`                    | Streamed-render text turns.                       |
| Vercel deploy manifest                           | `web/vercel.json`                     | Function runtime + maxDuration pin.               |
| HTTP wrapper (Python)                            | `backend/server.py`                   | Listens :8080; spawns CrossEngin per session.     |
| Container build                                  | `backend/Dockerfile`                  | Builds NOVA + CrossEngin from source.             |
| Local dev orchestration                          | `backend/docker-compose.yml`          | One-command `docker compose up`.                  |
| Container entrypoint                             | `backend/entrypoint.sh`               | Refuses to start without a real token.            |

## Authentication model

**v0.1: shared bearer token over HTTPS.** A single `CROSSENGIN_TOKEN`
secret is configured on both ends -- the Vercel project's env vars and
the backend service's env. The backend validates the bearer with a
constant-time compare (`hmac.compare_digest`) on every `/chat` call;
`/health` is unauthenticated by design (orchestrators probe it).

### Why a bearer (not a session cookie, mTLS, OAuth)?

- Simplest correct primitive for a single-user pattern. The trust
  boundary is the Vercel function -- the browser never sees the token.
- mTLS is the right answer for production at scale, but requires
  certificate provisioning on both sides; that's out of scope for v0.1.
- OAuth / signed JWTs are the upgrade path for multi-tenant use; see
  the rotation discussion below.

### Token rotation in v0.1

1. Generate a new token: `openssl rand -hex 32`.
2. Set it in the backend service (e.g. `fly secrets set
   CROSSENGIN_TOKEN=...`); the deploy redeploys with the new env.
3. Set it in the Vercel project env (`vercel env add CROSSENGIN_URL
   production`); redeploy with `vercel deploy --prod`.

There is **no overlap window** -- between step 2 and step 3 the Vercel
function will get 401s. Acceptable for personal use; not appropriate
for production multi-tenant rotation.

### Upgrade path: signed JWTs with key rotation

Replace the bearer with a Vercel-side-signed JWT that the backend
verifies with the public half. Then:

- Rotate the signing key + provision the new public key to the backend
  ahead of cutover; backend accepts both during the overlap window.
- Add `iat` / `exp` claims so leaked tokens have a bounded lifetime.
- Add a `sub` claim per end-user once multi-tenant is in scope.

This is the v2 design; not shipped here.

## Latency budget

| Hop                                          | Typical              | Note                                              |
|----------------------------------------------|----------------------|---------------------------------------------------|
| Browser -> Vercel edge                       | 20-80ms              | CDN POP near user.                                |
| Vercel function cold start                   | 100-300ms (first hit) | Warm: <10ms.                                     |
| Vercel function -> Linux backend (over TLS)  | 10-150ms             | One TCP round-trip + TLS; closer = faster.        |
| CrossEngin substrate tick                    | >=10ms minimum       | 100Hz substrate; ADR-0037 / GETTING_STARTED 5.4.  |
| CrossEngin chat turn                         | 50-500ms typical     | Depends on the message + KG state.                |
| Vercel function -> browser                   | 20-80ms              | Same path back.                                   |
| **End-to-end target**                        | **<1s warm**         | **<2s cold**                                      |

The Vercel function `maxDuration` is pinned to 60s in `vercel.json`.
Tune up to 300s on Vercel Pro if you need long-running interactions;
keep the backend's `CE_REQUEST_TIMEOUT_S` in lockstep.

### Streaming caveat (honest)

CrossEngin's chat surface is line-shaped, not token-shaped: the wrapper
flushes a single `agent>` line + trace per turn rather than streaming
tokens as the model "thinks." The Vercel function uses `Response.body`
piping so larger payloads stay flat in memory, but partial-token
streaming (SSE / chunked deltas) is a future-round concern. v0.1 ships
the line-flush shape because that's what `bin/crossengin*` actually
produces.

## Cost model

| Component         | Tier                              | Approx cost (single-user, low traffic) |
|-------------------|-----------------------------------|----------------------------------------|
| Vercel Hobby      | Free                              | $0/mo (well under bandwidth cap).      |
| Vercel Pro        | $20/seat/mo                       | Only needed for >60s function duration. |
| Hetzner CX11/CX21 | Cheapest viable VPS               | ~5-6 EUR/mo.                           |
| Fly.io shared-1x  | 256MB / shared CPU                | ~1.94 USD/mo + bandwidth.              |
| Render Starter    | 0.5 CPU / 512MB                   | $7/mo.                                 |
| Storage (`/data`) | Local SSD on host                 | Included with the tier above.          |
| S3 backup target  | Backblaze B2 / Cloudflare R2      | <$0.10/mo for KG snapshots.            |

For a single user: **~5 EUR/month total** with Hetzner + Vercel Hobby
is the floor. That matches the "personal companion on a Linux box"
positioning in GETTING_STARTED.md.

## What this scaffold does NOT do

- **No Kubernetes / Terraform.** docker-compose is the only deployment
  artifact. K8s / IaC are reasonable for v2; out of scope for v0.1.
- **No multi-tenant routing.** `session_id` is treated as an opaque
  key for per-session child routing -- there's no user model, no
  per-user quotas, no audit trail beyond what the backend already
  logs to stdout. CrossEngin v1 is single-user; the hybrid pattern is
  for that case.
- **No partial-token streaming.** See latency budget caveat above.
- **No Vercel Edge runtime.** The function runs on Node runtime so the
  full `fetch` + stream API is available; Edge would require a
  rewrite of the upstream-stream piping.

## Cross-references

- `docs/GETTING_STARTED.md` Section 5 -- the user-facing description.
- `docs/adr/r36f-0004-substrate-not-pipeline.md` -- why CrossEngin can't
  itself run on Vercel.
- `SECURITY.md` (next to this file) -- threat model + mitigations.
- `scripts/web.py` -- the in-tree single-host equivalent (no Vercel).
