# Vercel-proxy smoke tests

Two tiny end-to-end checks that exercise the seams between the Vercel
function and the backend wrapper:

- `test_backend_health.py` -- hits `/health` + asserts the JSON shape,
  hits `/chat` without auth + asserts 401. Stdlib-only Python; no
  dependencies. Run after `docker compose up`.
- `test_chat_route.ts` -- imports `app/api/chat/route.ts` and mocks
  `fetch` to validate the request shape + error cases (env missing,
  empty input, oversize input, network failure, happy path). Run from
  the `web/` workspace.

## Running

```bash
# Backend smoke (needs docker-compose backend up)
python3 infra/vercel-proxy/tests/test_backend_health.py http://localhost:8080

# Route smoke (needs the web/ workspace installed)
cd infra/vercel-proxy/web
pnpm install
# tsx is a one-off dev dependency for running TS scripts; install when needed:
# pnpm add -D tsx
npx tsx ../tests/test_chat_route.ts
```

## Honest status

The Python smoke test is straight stdlib + standard URL patterns -- it
will run anywhere Python 3.7+ is present.

The TS test is **written but not auto-run in this sandbox**: invoking it
requires `tsx` (or equivalent ESM TS loader) which is not in the v0.1
manifest. We did not pad `package.json` with a dev dependency on `tsx`
because the route under test is dependency-light; bring it in via
`pnpm add -D tsx` if you want CI to gate on this file.

The route module imports `next/server` for the `NextRequest` type only;
when you actually run the test, `next` must already be installed
(`pnpm install` in `web/` does that).
