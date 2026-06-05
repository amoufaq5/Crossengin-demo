/**
 * Smoke test: the /api/chat Vercel Function.
 *
 * Standalone runnable with `tsx` or `node --import tsx/esm`:
 *     npx tsx tests/test_chat_route.ts
 *
 * Mocks global.fetch so we can validate the route's request-shape pass-through
 * without standing up an actual upstream. Asserts:
 *
 *   1. 500 + helpful hint when env vars are missing.
 *   2. 400 on missing/empty input.
 *   3. 413 on input over 8KB cap.
 *   4. 502 when fetch throws (backend unreachable).
 *   5. The forwarded request hits ${CROSSENGIN_URL}/chat with the correct
 *      bearer header + JSON body shape.
 *
 * Exit 0 on all-pass; throws (non-zero) on any fail. Suitable for a
 * pre-commit hook or a CI job that runs against the `web/` workspace.
 */
import assert from "node:assert/strict";

// Stub Next's NextRequest minimally -- the route only uses .json().
type Body = Record<string, unknown>;
class FakeRequest {
  constructor(private _body: Body | string) {}
  async json(): Promise<Body> {
    if (typeof this._body === "string") {
      throw new SyntaxError("invalid JSON");
    }
    return this._body;
  }
}

// We import the route lazily inside each test so env mutations take effect
// before the module is read (`process.env` is captured at request-time, but
// AbortSignal.timeout creation is also import-safe).
async function importRoute() {
  // Clear module cache so each test sees fresh env-read behaviour. With ESM
  // we use a cache-busting query string on the dynamic import URL.
  const path = new URL("../web/app/api/chat/route.ts", import.meta.url).href;
  // @ts-expect-error: dynamic import with query string for cache bust
  return await import(`${path}?v=${Date.now()}`);
}

let passed = 0;
let failed = 0;

async function test(name: string, fn: () => Promise<void>) {
  try {
    await fn();
    console.log(`PASS  ${name}`);
    passed++;
  } catch (e) {
    console.error(`FAIL  ${name}`);
    console.error(e instanceof Error ? e.stack : String(e));
    failed++;
  }
}

await test("500 when env vars missing", async () => {
  delete process.env.CROSSENGIN_URL;
  delete process.env.CROSSENGIN_TOKEN;
  const mod = await importRoute();
  const req = new FakeRequest({ session_id: "s", input: "hi" });
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const resp = await mod.POST(req as any);
  assert.equal(resp.status, 500);
  const body = await resp.json();
  assert.equal(body.error, "proxy not configured");
  assert.match(body.hint, /CROSSENGIN_URL/);
});

await test("400 on empty input", async () => {
  process.env.CROSSENGIN_URL = "https://example.test";
  process.env.CROSSENGIN_TOKEN = "test-token";
  const mod = await importRoute();
  const req = new FakeRequest({ session_id: "s", input: "" });
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const resp = await mod.POST(req as any);
  assert.equal(resp.status, 400);
  const body = await resp.json();
  assert.equal(body.error, "missing input");
});

await test("413 on oversize input", async () => {
  process.env.CROSSENGIN_URL = "https://example.test";
  process.env.CROSSENGIN_TOKEN = "test-token";
  const mod = await importRoute();
  const big = "x".repeat(9 * 1024);
  const req = new FakeRequest({ session_id: "s", input: big });
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const resp = await mod.POST(req as any);
  assert.equal(resp.status, 413);
});

await test("502 when fetch throws", async () => {
  process.env.CROSSENGIN_URL = "https://example.test";
  process.env.CROSSENGIN_TOKEN = "test-token";
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  (global as any).fetch = async () => {
    throw new Error("ECONNREFUSED");
  };
  const mod = await importRoute();
  const req = new FakeRequest({ session_id: "s", input: "hi" });
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const resp = await mod.POST(req as any);
  assert.equal(resp.status, 502);
  const body = await resp.json();
  assert.equal(body.error, "backend unreachable");
  assert.match(body.hint, /ECONNREFUSED/);
});

await test("forwards body + bearer to backend", async () => {
  process.env.CROSSENGIN_URL = "https://backend.example/";  // trailing slash
  process.env.CROSSENGIN_TOKEN = "test-token";
  // Capture the upstream request so we can introspect it.
  let captured: { url: string; init: RequestInit } | undefined;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  (global as any).fetch = async (url: string, init: RequestInit) => {
    captured = { url, init };
    return new Response("agent> hi back\n", {
      status: 200,
      headers: { "content-type": "text/plain" },
    });
  };
  const mod = await importRoute();
  const req = new FakeRequest({ session_id: "abc", input: "hello" });
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const resp = await mod.POST(req as any);
  assert.equal(resp.status, 200);
  assert.ok(captured, "fetch was called");
  // Trailing slash on CROSSENGIN_URL should be stripped.
  assert.equal(captured.url, "https://backend.example/chat");
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const headers = (captured.init.headers ?? {}) as Record<string, string>;
  assert.equal(headers.authorization, "Bearer test-token");
  assert.equal(headers["x-crossengin-session"], "abc");
  const bodyStr =
    typeof captured.init.body === "string" ? captured.init.body : "";
  const fwd = JSON.parse(bodyStr);
  assert.equal(fwd.session_id, "abc");
  assert.equal(fwd.input, "hello");
  // Streamed body comes through.
  const text = await resp.text();
  assert.match(text, /agent>/);
});

console.log(`\n${passed} passed, ${failed} failed`);
if (failed > 0) process.exit(1);
