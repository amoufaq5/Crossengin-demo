# CrossEngin -- backend service (backend/)

A Python HTTP wrapper around `bin/crossengin-chat` (with a one-shot
fallback for `bin/crossengin`), packaged for Docker deployment. This is
the Linux half of the Vercel-hybrid pattern documented in
`docs/GETTING_STARTED.md` Section 5.

## What it exposes

| Method | Path     | Auth                          | Purpose                              |
|--------|----------|-------------------------------|--------------------------------------|
| GET    | /health  | none                          | Liveness probe for orchestrators.    |
| POST   | /chat    | `Bearer ${CROSSENGIN_TOKEN}`  | One chat turn; body streamed back.   |

`/chat` accepts `{"session_id": str, "input": str}`. The wrapper routes by
`session_id` to a per-session persistent chat child (mirrors
`scripts/web.py`'s per-cookie model). Cap is `CE_MAX_SESSIONS` (default 8);
LRU eviction sends `/quit` to the oldest child when full.

## Local development

```bash
docker-compose up --build
# wrapper listening on http://localhost:8080
# CROSSENGIN_TOKEN=local-dev-token (dev default; entrypoint refuses unless
# CE_ALLOW_DEV_TOKEN=1, which compose sets for you)
curl -s http://localhost:8080/health
curl -s -X POST http://localhost:8080/chat \
    -H "Authorization: Bearer local-dev-token" \
    -H "Content-Type: application/json" \
    -d '{"session_id":"smoke","input":"hello"}'
```

## chat.sh invocation strategy

The repo ships two chat surfaces:

- `bin/crossengin` -- one-shot daemon driven by `scripts/chat.sh`. Reads
  `/tmp/crossengin_input`, prints one `agent>` line, exits. Stateless.
- `bin/crossengin-chat` -- persistent REPL with admin commands. Driven
  by `scripts/web.py`. Holds cognitive state across turns.

The wrapper defaults to `bin/crossengin-chat` because cross-turn state
is what makes the proxy useful for actual conversation (each HTTP
request maps to a turn in a stateful session). Set
`CE_BIN=bin/crossengin` to use the one-shot variant -- the wrapper then
runs the `scripts/chat.sh` algorithm (write input file -> run binary ->
grep `agent>` line). This is **strictly worse** for chat UX but might
match a stateless-batch use case.

A future round (`R37F.2`?) could add a `scripts/chat.sh --batch` mode
that takes input on stdin and emits the reply on stdout in a single
process per call, removing the `/tmp/crossengin_input` choreography and
unlocking simpler container builds. Not implemented in v0.1.

## Deploying to a real host

The Dockerfile builds NOVA + CrossEngin from source inside the image
(matches `docs/GETTING_STARTED.md` Section 2.5). Cold-build time is
~minutes; bake an image once + push to a registry for fast restarts.

### Fly.io

```bash
# 1. One-time: install flyctl + sign in.
brew install flyctl   # or: curl -L https://fly.io/install.sh | sh
fly auth login

# 2. Create the app. The CLI generates a fly.toml in the cwd; commit it
#    next to this README under a feature branch if you want it tracked.
cd infra/vercel-proxy/backend
fly launch --no-deploy --dockerfile Dockerfile --name crossengin-backend

# 3. Set the secret. Same value goes into Vercel project env.
TOKEN=$(openssl rand -hex 32)
fly secrets set CROSSENGIN_TOKEN="$TOKEN"
# Echo it once into a password manager; you'll need it for Vercel.

# 4. Deploy.
fly deploy

# 5. The Vercel function reaches the backend at the auto-assigned
#    crossengin-backend.fly.dev hostname (TLS terminated by Fly's edge).
#    Set CROSSENGIN_URL=https://crossengin-backend.fly.dev in Vercel.
```

Internal-network deploy (production hardening): use `fly.toml` with
`internal_port = 8080` and an `[[services.ports]]` block that limits
traffic to Fly's 6PN private network, then run the Vercel proxy in a
`fly machines` instance peered to the backend. See
`infra/vercel-proxy/SECURITY.md` for the threat model.

### Hetzner (or any plain VPS)

```bash
# 1. Provision an Ubuntu 24.04 VPS (CX11 / CCX13 -- ~5 EUR/month is
#    plenty for single-user).
# 2. Install Docker + docker compose plugin per the official docs.
# 3. Clone this repo on the box, cd to infra/vercel-proxy/backend/.
# 4. Generate the token + write a production override.
mkdir -p /etc/crossengin
TOKEN=$(openssl rand -hex 32)
printf 'CROSSENGIN_TOKEN=%s\nCE_ALLOW_DEV_TOKEN=0\n' "$TOKEN" \
    > /etc/crossengin/env
chmod 600 /etc/crossengin/env

# 5. Front it with Caddy for TLS + bearer-token-aware logging. Add to
#    /etc/caddy/Caddyfile:
#       crossengin.example.com {
#         reverse_proxy 127.0.0.1:8080
#       }
# 6. Run with docker compose, env-loading from the file above:
docker compose --env-file /etc/crossengin/env up -d --build
```

### Render (or any container PaaS)

```yaml
# render.yaml (sketch -- not committed)
services:
  - type: web
    name: crossengin-backend
    runtime: docker
    repo: https://github.com/amoufaq5/Crossengin-demo
    dockerfilePath: infra/vercel-proxy/backend/Dockerfile
    plan: starter
    envVars:
      - key: CROSSENGIN_TOKEN
        sync: false   # set in dashboard
      - key: CE_PORT
        value: 8080
    healthCheckPath: /health
    disk:
      name: crossengin-data
      mountPath: /data
      sizeGB: 1
```

Render handles TLS + a public hostname; point `CROSSENGIN_URL` at the
service's auto-assigned domain.

## Environment variables (full list)

| Variable             | Default                 | Purpose                                                |
|----------------------|-------------------------|--------------------------------------------------------|
| `CROSSENGIN_TOKEN`   | (required)              | Bearer the wrapper validates on `/chat`.               |
| `CE_ALLOW_DEV_TOKEN` | unset                   | Set to `1` to allow the dev default; never in prod.    |
| `CE_BIN`             | `bin/crossengin-chat`   | Binary to spawn; one-shot fallback for `bin/crossengin`. |
| `CE_PORT`            | `8080`                  | Listen port.                                           |
| `CE_BIND`            | `0.0.0.0`               | Listen interface (use `127.0.0.1` behind a reverse proxy). |
| `CE_MAX_SESSIONS`    | `8`                     | LRU cap for persistent children.                       |
| `CE_REQUEST_TIMEOUT_S` | `30.0`                | Per-turn read timeout.                                 |
| `CE_REPO_ROOT`       | `/opt/crossengin/repo`  | Where the CrossEngin checkout lives in the image.      |

## Smoke tests

`../tests/test_backend_health.py` validates `/health` returns 200 and
the JSON shape the orchestrator probes expect. Run with:

```bash
cd ..
python3 tests/test_backend_health.py http://localhost:8080
```

(The script exits 0 on pass, 1 on fail; suitable for a CI smoke gate.)
