# R41: Live internet `/learn` (resolve → fetch → preprocess → ingest)

## Status

Accepted — R41 round. Closes the "/learn is not connected to the internet"
gap flagged after R40 (`r40-per-category-cognition.md`). Builds on ADR-0028
(gated fetch), ADR-0026 (ingest as fetched knowledge), and ADR-0031
(reasoning operators).

## Date

2026-06-08

## Context

Every ingredient of internet learning already existed but had never been
joined into a runnable sequence, which is exactly why the chat's `/learn`
felt inert:

- `src/io/transducers/http_client.nova` does a **real** socket HTTP/1.1 GET,
  but had **no name resolution** — `http_get` only accepted dotted-quad IPs
  or a hand-populated `HTTP_DNS_HOST_TO_IP` env cache. NOVA exposes no
  `getaddrinfo`, so `http://en.wikipedia.org` could not be fetched.
- `src/learning/internet_fetch.nova` gated a request (whitelist, rate limit,
  cache) and dispatched the transport, but nothing called it from the chat.
- `src/learning/preprocess.nova` turned HTML into content words + S/R/O
  triples, but only the offline `scripts/learn.sh` ever fed it.
- The chat's `/learn` read a **pre-populated cache file**; the triple
  ingester only created an operator when **both** endpoints already existed,
  so learning a genuinely new fact produced **no reasoning edges**.

Net effect: "/learn TOPIC" did nothing without an external curl step, and even
then it could not grow the reasoning graph. The environment's outbound network
policy actually permits HTTP/HTTPS here (verified), so the blocker was purely
missing wiring + the absent resolver.

## Decision

Add the missing pieces and join the four stages into one in-engine call.

### 1. DNS over UDP (`src/learning/dns_resolver.nova`, new, leaf)

A minimal A-record resolver: build a query, send it over a UDP socket
(`socket(2,2,0)`) to a recursive resolver (`8.8.8.8:53` by default,
`CE_DNS_SERVER` to override — itself a dotted quad, so no bootstrap problem),
and parse the first A record out of the response (handling DNS name
compression). Returns a dotted-quad string `http_get` already understands.
Verified live: `example.com`, `neverssl.com`, `info.cern.ch` all resolve to
the same IPs as the system resolver. Packet build/parse is unit-tested
deterministically against hand-built buffers (no network).

Implementation note: NOVA string concatenation drops embedded NUL bytes, so
the packet is built and parsed with `alloc`/`store8`/`load8` raw buffers, the
same convention the federation stack uses for binary protocols.

### 2. Resolver injection (`http_client.nova`, additive)

New `http_dns_add(host, ip)` writes a host→ip mapping into the existing
in-process DNS cache. The pipeline resolves a host and injects it **before**
fetching, so `http_get` connects to the right IP while still sending the
correct `Host:` header. The env-cache and dotted-quad paths are unchanged —
a caller that never injects sees identical behaviour, so no existing test is
affected.

### 3. The pipeline (`src/learning/learn_pipeline.nova`, new)

`learn_from_url(url, kg, lang, now)` runs the full sequence:

1. **resolve** the host (DNS-over-UDP) and inject the mapping;
2. **gate** through a per-call whitelist that admits exactly the requested
   host plus the ADR-0028 rate limiter (an explicit `/learn` can't become an
   open relay);
3. **fetch** the body over a real socket (`if_dispatch_transport` → `http_get`);
4. **preprocess** HTML → content words + S/R/O triples;
5. **ingest** via `lp_ingest`.

`https://` is reported as a deferred-TLS gap **plainly** rather than failing
opaquely.

### 4. The ingest fix (the load-bearing change)

`lp_ingest` mints a concept atom for every content word **and**, for every
triple, **creates the endpoint atoms when absent** before adding the reasoning
operator. This is the fix for the pre-R41 dead end: a fetched
"photosynthesis is_a process" now mints both concepts and the implicative
operator, so the academic strategy can forward-chain over knowledge learned
seconds ago.

### 5. Chat wiring

`/learn http://host/path` takes the live pipeline; any other argument keeps
the existing cache-file behaviour, so `/learn TOPIC | FILE | @batch | rss: |
dir:` is unchanged.

## Verification

- Live, in the chat: `/learn http://example.com/` → "11 word(s), 1 operator(s),
  7 new atom(s); http 200". The learning loop closes end to end: "what is
  domain" returns "i don't have a model of 'domain' yet" **before** the fetch
  and "domain leads to for (domain->for)" **after** — reasoning over
  freshly-learned knowledge.
- `/learn https://…` → "learn failed [https-deferred]: https needs the
  deferred TLS stack — try an http:// source".
- New unit tests: `dns_resolver` (17), `learn_pipeline` (10). New/changed
  modules compile standalone (the `make build` gate). `internet_fetch` (36)
  and `preprocess` (88) still pass; the R40 chat scenarios still pass.

## Consequences / scope

- `/learn` genuinely reaches the internet and grows both the concept graph and
  the reasoning graph, in one command, with no external shim.
- **http:// only.** Most large sites force HTTPS; the in-engine TLS stack
  (NOVA enhancement #11) remains the gating follow-up for HTTPS sources. Until
  then, plain-HTTP knowledge endpoints work today.
- Triple-extraction quality is bounded by `preprocess`'s heuristics (e.g. a
  noisy `domain->for` from prose). Improving the extractor — and making the
  fetched-source whitelist policy-driven — are the natural R42 follow-ups.
- `recv_data` has no timeout builtin, so a dropped DNS/HTTP datagram blocks;
  acceptable for the opt-in `/learn` path against reliable endpoints,
  documented rather than hidden.
