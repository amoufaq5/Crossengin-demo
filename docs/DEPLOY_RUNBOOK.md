# CrossEngin -- Vercel-hybrid deploy runbook

A turnkey, step-by-step runbook for the **Vercel-hybrid** deployment
(`infra/vercel-proxy/ARCHITECTURE.md`): Vercel hosts the chat UI + a single
proxy function, and a Linux box runs the actual CrossEngin process. A live
deploy needs two things that do not exist yet -- a Linux backend host and a
shared bearer token -- so this runbook provisions both.

End-to-end shape:

```
Browser --HTTPS--> Vercel edge (/api/chat) --HTTPS (Bearer)--> Linux backend
                                                  server.py :8080
                                                  -> bin/crossengin-chat per session_id
                                                  -> /data volume
```

Every command below is cross-checked against `infra/vercel-proxy/web/`,
`infra/vercel-proxy/backend/`, and the README/ARCHITECTURE docs.

---

## Step 1 -- Provision the Linux backend host + build the image

1. Provision an Ubuntu 24.04 host (Hetzner CX11 / any plain VPS is plenty for
   single-user; the Dockerfile pins `ubuntu:24.04`). Install Docker + the
   `docker compose` plugin.

2. Clone this repo on the box and build the backend image:

   ```bash
   cd infra/vercel-proxy/backend
   docker compose up --build
   ```

   The Dockerfile **builds NOVA + CrossEngin from source** inside the image
   (it clones both repos per `scripts/bootstrap.sh`). Cold-build time is
   ~minutes. For fast restarts, **bake the image once and push it to a
   registry**, then pull it on the host instead of rebuilding:

   ```bash
   docker build -t <registry>/crossengin-backend:v0.1 .
   docker push <registry>/crossengin-backend:v0.1
   ```

3. The compose file already mounts a persistence volume (`./data:/data`). For
   production prefer a **named volume** so cognitive state (decision log, KG
   snapshots) survives container replacement.

> Note: the dev compose ships `CROSSENGIN_TOKEN=local-dev-token` +
> `CE_ALLOW_DEV_TOKEN=1`. The entrypoint **refuses to start** on that default
> unless the bypass flag is set, so you MUST override the token (Step 2) for
> any non-localhost deployment.

---

## Step 2 -- Generate the shared token

The same secret is configured on both ends; the backend validates it with a
constant-time compare (`hmac.compare_digest`).

```bash
TOKEN=$(openssl rand -hex 32)
echo "$TOKEN"          # copy this once into a password manager -- you need it for Vercel too
```

Set it on the backend environment (and disable the dev bypass). For the plain
docker-compose host, write a production override file:

```bash
sudo mkdir -p /etc/crossengin
printf 'CROSSENGIN_TOKEN=%s\nCE_ALLOW_DEV_TOKEN=0\n' "$TOKEN" \
    | sudo tee /etc/crossengin/env >/dev/null
sudo chmod 600 /etc/crossengin/env

docker compose --env-file /etc/crossengin/env up -d --build
```

(On Fly.io use `fly secrets set CROSSENGIN_TOKEN="$TOKEN"`; on Render set it in
the dashboard. Recipes are in `infra/vercel-proxy/backend/README.md`.)

---

## Step 3 -- Smoke-test the backend

`/health` is unauthenticated (orchestrators probe it); `/chat` needs the
bearer. Exactly the curls from `backend/README.md`:

```bash
curl -s http://localhost:8080/health

curl -s -X POST http://localhost:8080/chat \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"session_id":"smoke","input":"hello"}'
```

`/health` returns 200 + a JSON body; `/chat` returns the agent's reply text.
You can also run the CI smoke gate:

```bash
cd infra/vercel-proxy
python3 tests/test_backend_health.py http://localhost:8080   # exits 0 on pass
```

---

## Step 4 -- Deploy the Vercel half

```bash
cd infra/vercel-proxy/web
npm i -g vercel
vercel link                      # first time only: link this dir to a project

vercel env add CROSSENGIN_URL production    # https://<your-backend-host>
vercel env add CROSSENGIN_TOKEN production   # paste the SAME token from Step 2

vercel deploy --prod
```

The route (`web/app/api/chat/route.ts`) **refuses to forward** until both env
vars are set (it returns 500 if either is missing). `CROSSENGIN_URL` must point
at the TLS-terminated public hostname of your backend (Step 5).

---

## Step 5 -- Verify end-to-end + hardening checklist

Verify: open the Vercel production URL, type a message, and confirm the
`agent>` reply renders. The path is
Browser -> `/api/chat` -> `${CROSSENGIN_URL}/chat` (Bearer) -> `server.py` ->
`bin/crossengin-chat`.

Proxy failure codes worth knowing (`web/README.md`): 400 empty/malformed,
413 input > 8KB, 405 GET on `/api/chat`, 500 env var missing, 502 backend
unreachable.

### Hardening checklist

- [ ] **HTTPS/TLS in front of the backend.** `server.py` speaks plain HTTP on
      :8080 -- terminate TLS with Caddy / a reverse proxy (or Fly/Render's
      edge) and bind `CE_BIND=127.0.0.1` behind it. Never expose :8080 raw.
- [ ] **Atomic snapshot writes are a known gap.** Chat-state persistence does a
      single open + truncate (no tmp + rename) and takes no multi-process lock;
      avoid concurrent writers and back up `/data` out-of-band.
- [ ] **Tune `CE_MAX_SESSIONS`** (default 8). It is the LRU cap on persistent
      children; the oldest gets `/quit` on overflow. Raise it for more
      concurrent users, watch memory.
- [ ] **Bake the image to a registry** (Step 1) so restarts pull instead of
      rebuilding NOVA + CrossEngin from source (~minutes cold).
- [ ] **Rotate the token** by updating it on the backend then in Vercel; there
      is no overlap window (brief 401s between the two), acceptable for
      personal use. JWT-with-key-rotation is the documented upgrade path
      (`infra/vercel-proxy/SECURITY.md`).
- [ ] **Keep timeouts in lockstep:** `vercel.json` pins `maxDuration` (60s;
      300s on Pro); match the backend's `CE_REQUEST_TIMEOUT_S`.

---

## Cross-references

- `infra/vercel-proxy/ARCHITECTURE.md` -- flow, auth model, latency/cost budgets.
- `infra/vercel-proxy/backend/README.md` -- env var table + Fly/Hetzner/Render recipes.
- `infra/vercel-proxy/web/README.md` -- Vercel-side setup + failure codes.
- `infra/vercel-proxy/SECURITY.md` -- threat model + mitigations.
- `docs/GETTING_STARTED.md` Section 5 -- the user-facing description of the pattern.
