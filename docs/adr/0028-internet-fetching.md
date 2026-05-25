# ADR-0028: Internet fetching design (whitelist, rate limiting, validation, audit, cache)

## Status

Proposed

## Date

2026-05-25

## Context
Many learning episodes (ADR-0026) can only be satisfied from external sources — definitions, current guidelines, factual lookups. The substrate therefore needs a way to reach the internet. This is the single most safety-sensitive capability in CrossEngin: an autonomous system that can issue arbitrary outbound requests is a data-exfiltration and prompt-injection risk, and on a bootstrapped 2-founder budget we cannot build a heavyweight crawler. We must define a narrow, safe, auditable fetch design.

The fetch path must obey the project's safety architecture: it is an action subject to permission tiers (ADR-0041) and reversibility classification (ADR-0042), and every fetch must be recorded (ADR-0043). It must also never become a cognition path — fetched bytes are data to be validated and turned into atoms (ADR-0016), never instructions the substrate obeys, and absolutely never routed to an LLM for interpretation (NO-LLM-COGNITION, ADR-0014).

NOVA today has no outbound HTTP. We are explicitly assuming the upstream enhancement lands. The design must be implementable by two people: prefer a small whitelist and a simple cache over a general web stack.

## Decision
We implement a `net/fetch.nova` component built on NOVA enhancement #11 (whitelisted, rate-limited outbound HTTP with validation + cache). Its rules:

- **Whitelist-only.** Requests are permitted solely to a curated allow-list of domains (e.g., reference encyclopedias, standards/guideline bodies, dictionary APIs) stored as configuration atoms in a `KG-sources`. Any non-whitelisted host is hard-denied at the syscall boundary. v1 ships ~15-30 vetted domains; the user may add entries via an approve-tier action (ADR-0041).
- **Rate limiting.** Token-bucket limiter: global cap 30 requests/hour and ≤1 in-flight request at a time (matching ADR-0026's single-active-external-episode rule), with per-domain courtesy spacing ≥2s. Exhaustion queues or defers the episode rather than dropping it.
- **Validation.** Responses must pass `runtime/validate.nova` checks: enforced TLS, content-type allow-list (text/html, application/json, text/plain), max size 2MB, and structural sanity. Extracted text is treated as inert evidence; any embedded directive-like content is stripped/ignored — fetched content can never trigger actions or be executed.
- **Audit.** Every fetch writes an append-only record (URL, timestamp, status, byte count, hash of body, triggering episode ID) to the decision log via enhancement #9 / `core/safety.nova` (ADR-0043).
- **Cache.** A content cache keyed by normalized URL with per-domain TTL (default 7 days; guideline domains 1 day, classical-reference domains 90 days) stored via `runtime/db.nova`. Cache hits bypass the rate limiter and produce a `cache-hit` audit entry. Extracted atoms carry `provenance=fetched` plus the source tier (ADR-0029).

A fetch is classified by ADR-0042 as reversible (it only reads), so under ADR-0041 routine whitelisted fetches run at the **auto/notify** tier; adding a new whitelist domain is **approve**.

## Options Considered
- **Open outbound fetch (any URL).** Maximally capable. Rejected outright: unacceptable exfiltration and injection surface for an autonomous agent; impossible to audit meaningfully; contradicts the safety-first posture of Group I.
- **No internet; user-teaching + bundled corpus only (ADR-0027).** Safest and simplest. Rejected as the sole strategy: cannot keep current with changing guidelines, and over-burdens the single user; we keep teaching as the complement for non-fetchable gaps.
- **Whitelist + rate-limit + validate + audit + cache (CHOSEN).** Narrow, auditable, cacheable, and buildable by two people. Costs curation effort and limits coverage, which we accept.
- **Route fetch through a hosted LLM/search API for "smart" retrieval.** Convenient. Rejected hard: violates NO-LLM-COGNITION (ADR-0014) by inserting an LLM into knowledge acquisition, adds a paid dependency against the bootstrap constraint, and yields unauditable provenance.

## Consequences
- **Positive:** The system can acquire current external knowledge within a tightly bounded, fully audited, cache-efficient envelope; the whitelist + validation closes the major exfiltration/injection vectors; reuses existing safety and DB machinery.
- **Negative:** Whitelist curation is ongoing manual work for the founders; coverage is deliberately limited; the single-in-flight + 30/hr caps can slow burst learning; cache staleness must be tuned per domain.
- **Future work:** Per-domain trust scoring feeding ADR-0029 tiers; a user-review queue for proposed whitelist additions; optional local mirror of high-value reference corpora to cut network dependence; richer extraction once parsing matures.

## Implementation Notes
- New module `net/fetch.nova`: `fetch_get(url, episode_id)`, `whitelist_check(host)`, `ratelimit_take()`, `cache_get/cache_put(url, body, ttl)`; tag constants `FETCH_OK`, `FETCH_DENIED_HOST`, `FETCH_RATE_LIMITED`, `FETCH_INVALID`.
- Whitelist + per-domain TTL live as atoms in `KG-sources` (`core/knowledge.nova`); cache and audit in `runtime/db.nova`; validation via `runtime/validate.nova`; hashing via `runtime/crypto.nova`.
- Integrates with ADR-0026 (an episode calls `fetch_get`), ADR-0029 (tags each atom's source tier), ADR-0041/042/043 (permission tier, reversibility, audit). Extracted atoms created with `provenance=fetched`.
- Test fixtures: request a non-whitelisted host (expect `FETCH_DENIED_HOST`, audit entry, no socket opened); exceed 30/hr (expect `FETCH_RATE_LIMITED` and episode deferral); oversized/ wrong content-type (expect `FETCH_INVALID`); repeat request within TTL (expect cache hit + `cache-hit` audit, no rate-limit token spent); confirm a body containing directive-like text produces only inert atoms and triggers no action.
- DEPENDS ON: NOVA enhancement #11 — whitelisted, rate-limited outbound HTTP with validation + cache (extends `runtime/io.nova` + `runtime/syscall.nova`); #9 — append-only crash-safe audit log.
