# CrossEngin -- Vercel proxy (web/)

A Next.js 14 App Router app whose only job is hosting the chat UI plus a
single Vercel Function (`app/api/chat/route.ts`) that proxies turns to the
self-hosted CrossEngin backend (see `../backend/`).

This is the **Vercel half** of the hybrid pattern documented in
`docs/GETTING_STARTED.md` Section 5: Vercel runs the convenience surface
(domain, TLS, edge), the Linux box runs the actual CrossEngin process.

## Layout

```
web/
  app/
    layout.tsx          -- root layout (HTML wrapper)
    page.tsx            -- chat UI: text input + Send button + streaming log
    api/
      chat/
        route.ts        -- POST handler; forwards to ${CROSSENGIN_URL}/chat
  package.json
  next.config.js
  tsconfig.json
  vercel.json           -- function runtime + maxDuration pin
  .env.example          -- env var reference (DO NOT commit .env.local)
```

## One-time setup

```bash
# 1. Install Node 18.17+ and pnpm (or npm/yarn).
node --version            # >= 18.17
corepack enable
corepack prepare pnpm@latest --activate

# 2. Install deps.
pnpm install

# 3. Configure env vars for local dev. The route reads from process.env.
cp .env.example .env.local
$EDITOR .env.local        # set CROSSENGIN_URL + CROSSENGIN_TOKEN
```

## Local development (against a local backend)

In one terminal, run the backend:

```bash
cd ../backend && docker-compose up
# backend listens on http://localhost:8080
```

In another terminal, run Next.js dev mode:

```bash
pnpm dev
# Next.js dev server on http://localhost:3000
# /api/chat forwards to whatever CROSSENGIN_URL points at in .env.local
```

Open <http://localhost:3000> and type. The chat UI sends each message to
`/api/chat`, the route forwards it to `${CROSSENGIN_URL}/chat`, and the
backend wrapper spawns `bin/crossengin` and streams the response back.

## Deploying to Vercel

```bash
# 1. Install the Vercel CLI once.
npm i -g vercel

# 2. Link this directory to a Vercel project (first time only).
vercel link

# 3. Configure production env vars. The route will refuse to forward
#    requests until both are set.
vercel env add CROSSENGIN_URL production
vercel env add CROSSENGIN_TOKEN production
# Use `openssl rand -hex 32` to generate the token; paste the same value
# into the backend service's environment as well.

# 4. Deploy.
vercel deploy --prod
```

The CLI prints the production URL on success. Hit `/` for the chat UI;
the function endpoint is `/api/chat`.

## Type-checking + linting

```bash
pnpm typecheck            # tsc --noEmit
pnpm lint                 # next lint
```

CI integrations that gate deploys on type-checks should run `pnpm typecheck`
on PR; it's also a fast local sanity check after editing the route.

## How the proxy fails

| Status | Meaning                                                    |
|--------|------------------------------------------------------------|
| 200    | Backend responded; body is the streamed `agent>` line.     |
| 400    | Empty input or malformed JSON.                             |
| 413    | Input > 8KB (DoS soft cap; see SECURITY.md).               |
| 405    | GET on /api/chat (only POST is wired).                     |
| 500    | `CROSSENGIN_URL` or `CROSSENGIN_TOKEN` env var missing.    |
| 502    | Backend unreachable (DNS / TCP / TLS / timeout).           |
| pass   | 4xx/5xx from the backend are returned with body verbatim.  |

## Cost model (Vercel Hobby tier, single-user)

Vercel Hobby is free for personal use under the per-month bandwidth cap;
a single-user chat workload sits well below the limit. The function
duration ceiling is 60s (raise to 300s on Pro if you push long-running
prompts). See `../ARCHITECTURE.md` for the end-to-end cost discussion
including the Linux backend.
