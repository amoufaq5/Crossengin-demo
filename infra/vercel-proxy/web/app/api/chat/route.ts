/**
 * /api/chat -- Vercel Function that proxies a chat turn to the self-hosted
 * CrossEngin backend.
 *
 * Request shape (POST):
 *   { session_id: string, input: string }
 *
 * Response: streamed text body from the backend. The backend wrapper (see
 * `infra/vercel-proxy/backend/server.py`) writes each `agent>` line and any
 * trace tail directly to the response; we forward the body unmodified so
 * the browser side (`app/page.tsx`) can render it incrementally.
 *
 * Env vars (configured in the Vercel project settings, or .env.local for
 * `next dev`):
 *   CROSSENGIN_URL    -- e.g. https://crossengin.example.com (no trailing /)
 *   CROSSENGIN_TOKEN  -- shared bearer used between this function and the
 *                        backend's `Authorization: Bearer ...` validator
 *
 * Error envelope:
 *   - 500 if env vars are missing (don't ship a broken function to prod)
 *   - 502 if the backend is unreachable / TCP error
 *   - pass-through status (4xx / 5xx body verbatim) for anything else
 */
import { NextRequest } from "next/server";

// Node runtime so we get the full `fetch` plus stream pipeline. The Edge
// runtime would also work, but Node keeps the local `vercel dev` flow
// straightforward and matches what most self-hosted backends expect.
export const runtime = "nodejs";

// Vercel Hobby tier caps function duration at 60s; Pro at 300s. The chat
// turns we forward are short by design (one CrossEngin invocation per turn;
// see scripts/chat.sh), but we still set an explicit ceiling so a wedged
// backend doesn't burn the whole budget. Update vercel.json `maxDuration`
// in lockstep if you raise this.
export const maxDuration = 60;

type ChatRequest = {
  session_id?: string;
  input?: string;
};

function jsonError(status: number, error: string, hint?: string) {
  return new Response(
    JSON.stringify({ error, ...(hint ? { hint } : {}) }),
    {
      status,
      headers: { "content-type": "application/json; charset=utf-8" },
    },
  );
}

export async function POST(req: NextRequest): Promise<Response> {
  // ---- env-var sanity -----------------------------------------------------
  const backend = process.env.CROSSENGIN_URL;
  const token = process.env.CROSSENGIN_TOKEN;
  if (!backend || !token) {
    // 500 (not 502): the proxy itself is misconfigured. The browser-side
    // hint lets a deployer diagnose without inspecting Vercel logs.
    return jsonError(
      500,
      "proxy not configured",
      "set CROSSENGIN_URL and CROSSENGIN_TOKEN in Vercel project env",
    );
  }

  // ---- request body -------------------------------------------------------
  let body: ChatRequest;
  try {
    body = (await req.json()) as ChatRequest;
  } catch {
    return jsonError(400, "invalid json body");
  }
  const session_id = (body.session_id ?? "").trim();
  const input = (body.input ?? "").trim();
  if (!input) {
    return jsonError(400, "missing input");
  }
  if (input.length > 8 * 1024) {
    // Soft cap: chat turns are line-shaped. Anything larger is almost
    // certainly a misuse (image paste, log dump). Mitigates the
    // "expensive prompt" DoS vector documented in SECURITY.md.
    return jsonError(413, "input too large (>8KB)");
  }

  // ---- forward to backend -------------------------------------------------
  let upstream: Response;
  try {
    upstream = await fetch(`${backend.replace(/\/+$/, "")}/chat`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${token}`,
        // Surface the session id so the backend can route to the right
        // child process / log stream. Body field is canonical; header is
        // for observability (Vercel logs strip POST bodies by default).
        "x-crossengin-session": session_id || "anonymous",
      },
      body: JSON.stringify({ session_id, input }),
      // Cap the upstream fetch so we don't sit on a Vercel function slot
      // waiting for a wedged backend. AbortSignal.timeout is the standard
      // wire here; tweak in lockstep with `maxDuration` above.
      signal: AbortSignal.timeout((maxDuration - 5) * 1000),
    });
  } catch (e) {
    // Network-level failure (DNS, TCP refused, TLS handshake, timeout).
    // 502 is the canonical "bad gateway" response.
    const msg = e instanceof Error ? e.message : "unknown";
    return jsonError(502, "backend unreachable", msg);
  }

  // ---- stream the body back unmodified -----------------------------------
  // upstream.body is a ReadableStream<Uint8Array>; piping it through a new
  // Response keeps memory flat regardless of payload size.
  return new Response(upstream.body, {
    status: upstream.status,
    headers: {
      "content-type":
        upstream.headers.get("content-type") ?? "text/plain; charset=utf-8",
      // Keep the proxy out of intermediate caches; chat responses are
      // per-turn and per-session.
      "cache-control": "no-store",
    },
  });
}

// Useful for `vercel dev` health checks: a bare GET returns 405 so the
// route's existence is verifiable without spawning an upstream call.
export async function GET() {
  return jsonError(405, "use POST");
}
