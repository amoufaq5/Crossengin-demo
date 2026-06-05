# Vercel-hybrid -- security model

Threat-by-threat walkthrough of the v0.1 reference architecture.
Companion to `ARCHITECTURE.md`; each threat below maps to a code-level
mitigation in `web/` or `backend/` or to a documented operational
practice.

## Trust boundaries

1. **Browser <-> Vercel function** -- public internet; TLS-terminated
   at Vercel's edge. The browser never sees the backend bearer; it
   only knows it's talking to its own origin.
2. **Vercel function <-> Linux backend** -- public internet (unless
   you use Fly's internal 6PN; see below). TLS-terminated by the
   backend's reverse proxy (Caddy / Fly edge / Render edge). The bearer
   token is the only auth.
3. **Inside the Linux backend** -- the wrapper trusts the CrossEngin
   binary completely. Anything the agent can do, an authenticated
   `/chat` caller can trigger (admin commands like `/teach`, `/halt`).

## Threats

### T1 -- Token leakage (HIGH)

If `CROSSENGIN_TOKEN` leaks, an attacker has unrestricted chat access
+ admin-command access (the persistent chat surface exposes `/teach`,
`/halt`, `/quit` etc.; see `scripts/web.py` for the surface).

**Mitigations:**

- **Never log the token.** `server.py`'s access log is silent
  (`log_message` is a no-op). `route.ts` does not include the bearer
  in any error envelope. Confirm before adding logging middleware.
- **Don't bake into source.** `.env.example` ships placeholders;
  `.env.local` is gitignored at the Next.js scaffold level. Backend
  reads from container env only.
- **Use `hmac.compare_digest`.** Backend's `_check_auth` uses
  constant-time compare to defeat naive timing-side-channel attacks.
- **Rotate on suspicion of leak.** See `ARCHITECTURE.md` rotation
  steps. The window between backend rotation + Vercel rotation is
  a 401 outage; for personal use this is acceptable.
- **Bound the radius.** Use distinct tokens per environment (dev /
  staging / prod). The dev-default `local-dev-token` is refused by
  `entrypoint.sh` unless `CE_ALLOW_DEV_TOKEN=1` is set.

### T2 -- DoS via expensive prompts (MEDIUM)

A caller (with valid token OR via a leaked compromised proxy) sends
prompts that take a long time to process / large payloads to thrash
the substrate.

**Mitigations:**

- **Vercel function input cap** -- `route.ts` rejects `input > 8KB`
  with 413. Chat turns are line-shaped; >8KB is a misuse.
- **Function maxDuration: 60s** -- `vercel.json` pins a hard ceiling;
  longer requests are killed by Vercel's runtime.
- **Backend request timeout: 30s** -- `CE_REQUEST_TIMEOUT_S` (default
  30s) bounds the per-turn wait on the child's prompt.
- **LRU session cap** -- `CE_MAX_SESSIONS` (default 8) caps concurrent
  children; eviction sends `/quit` to the oldest.

**Not yet implemented (future work):**

- Per-IP rate limiting at the Vercel function. Vercel doesn't ship a
  built-in primitive; integrate Upstash Redis (`@upstash/ratelimit`)
  or Vercel KV in the v1 hardening pass.
- Per-token rate limiting at the backend. Add a token-bucket on the
  `_check_auth` path keyed on the bearer hash.

### T3 -- Backend exposure to the open internet (MEDIUM)

The backend is reachable from anywhere; only the bearer protects
`/chat`. A determined attacker can brute-force the token (low
probability with `openssl rand -hex 32`, but the surface exists).

**Mitigations:**

- **Use Fly's internal 6PN.** Run both the Vercel proxy (as a Fly
  Machine) and the backend on Fly; bind the backend to the 6PN
  interface only. Public internet can't reach `:8080`.
- **Behind a private VPN / WireGuard.** Run the backend on a Hetzner
  VPS, expose `:8080` only over WireGuard, run a tiny Vercel-callable
  proxy on a separate cheap VM that has WG + public access.
- **Restrict by Vercel IP range.** Vercel publishes its egress IP
  ranges; configure the reverse proxy (Caddy / nginx) to drop traffic
  from anywhere else. The ranges change periodically -- automate
  the update.

**Not yet implemented (future work):**

- A Caddyfile / nginx.conf template under `infra/vercel-proxy/proxy/`
  that does TLS + IP-range filtering for the public-VPS deploy. This
  is the obvious R37F.2 follow-up.

### T4 -- Cookie / session-id spoofing (LOW)

`session_id` is opaque, generated client-side by the chat UI
(`crypto.randomUUID()` in `page.tsx`). An attacker who knows another
user's `session_id` could speak through their persistent child.

**Mitigations:**

- **CrossEngin v1 is single-user.** This threat is informational for
  v0.1; for v2 multi-tenant, replace the opaque id with a JWT `sub`
  claim carried in the bearer.
- **Children don't share disk.** v0.1 each child has its own
  in-memory state; the on-disk `/data` volume holds shared state
  (decision log, KG snapshots). v2 should namespace `/data` per
  tenant.

### T5 -- Stdin/stdout interleave (LOW)

A race between concurrent `/chat` calls on the same `session_id`
could interleave bytes on the child's stdin, corrupting the protocol.

**Mitigation:** `ChatChild.send` holds `request_lock` across the
entire `stdin.write` + `wait_for_prompt`. This mirrors `scripts/web.py`
and is the correct primitive.

### T6 -- Container escape via CrossEngin binary (HIGH if exploited; LOW likelihood)

If `bin/crossengin` has a memory-safety bug, an attacker with `/chat`
access could potentially execute arbitrary code as the container UID.

**Mitigations:**

- **Drop to non-root.** The Dockerfile currently runs as root; a v0.1.1
  hardening pass should add a dedicated user (`useradd -u 10001
  crossengin`) and switch to it after `make install`. (TODO.)
- **Read-only root filesystem.** Add `read_only: true` +
  `tmpfs: /tmp` to docker-compose service. Persistence lives in
  `/data` which is bind-mounted writable.
- **Drop capabilities.** Add `cap_drop: [ALL]` to docker-compose; the
  wrapper needs no special caps.
- **seccomp profile.** Default Docker seccomp is fine for v0.1; a
  v0.1.1 should generate a tight profile from `strace -ff`.

These hardening steps are documented but not all encoded in the v0.1
docker-compose -- doing so adds friction for `docker-compose up` first
runs. The docker-compose ships the permissive defaults; production
deployments should layer the above on top.

## What we are NOT defending against

- **Vercel as a trusted intermediary.** The Vercel function holds the
  bearer in process env; Vercel's security model is the floor here.
  If you don't trust Vercel, host the proxy yourself (Cloudflare
  Workers + KV; or a tiny Caddy on a different VM).
- **Cognitive-state exfiltration via the agent's own surface.**
  CrossEngin's constitution blocks messages containing "exfiltrate"
  (see `scripts/chat.sh` header), but a more sophisticated jailbreak
  is the application-layer concern of `src/safety/`. The proxy is
  not the right enforcement point.
- **Compromised Linux host.** If the VPS is rooted, the bearer is
  the smaller problem; rotate all secrets + redeploy from clean
  images.

## Cross-references

- `ARCHITECTURE.md` -- the deployment shape.
- `web/app/api/chat/route.ts` -- proxy-side input caps + timeouts.
- `backend/server.py` -- bearer validation + LRU eviction.
- `backend/entrypoint.sh` -- dev-token refusal.
- `docs/adr/` (R36F series) -- the rationale behind the substrate
  itself.
