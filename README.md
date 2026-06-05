# CrossEngin

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/amoufaq5/Crossengin-demo)

> **New here?** Start with [`docs/GETTING_STARTED.md`](docs/GETTING_STARTED.md)
> (Linux / Windows WSL2 / macOS / Vercel hybrid), then
> [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md) for the round-based
> development model. Architecture decisions live under
> [`docs/adr/`](docs/adr/) -- the R36F-prefixed series covers the rounds-up
> rationale (language choice, federation stack, substrate commitment,
> self-hosting invariant, canonical crypto primitives).

CrossEngin is a non-LLM cognitive **substrate** system, implemented in
[NOVA](https://github.com/amoufaq5/nova). It targets AGI-relevant capability —
continuous learning, self-directed skill acquisition, theory of mind,
initiative, counterfactual reasoning, long-horizon goals, and self-awareness of
identity, state, and goals over time — by running a fabric of uniform
computational units rather than orchestrating a pipeline of modules.

## Status (through R38)

| Track | Latest round | What landed |
|---|---|---|
| Substrate v1 | R0..R29 | 10-phase agent assembled; ~6M-node fabric on tick-driven core. |
| Federation transport | R30C / R31B / R32B / R33B / R34B / R34C / R35A / R35B / R35D / R36A / R36B / R38B / R38C | DTLS 1.2 + ICE + STUN + TURN + SRTP wire stack; DTLS-SRTP keying per RFC 5764 §4.2 with R36B keying-material cache; TURN client state machine; ICE-TURN escalation; TURN long-term-credential auth (RFC 5389 §10) + per-permission cadence + 401 auto-retry; R38B PRF rekey on `dtls_advance_epoch` (closes R33B's last DTLS caveat); R38C TURN SERVER-side state machine (allocations + permissions + channels + tick). |
| Safety / crypto leaves | R33A / R34A / R37C | Canonical `safety/sha256.nova` (R33A/R34A) + canonical `safety/md5.nova` + `safety/sha1.nova` (R37C); dedup of inline copies across noise_xk, merkle, ecdsa, dtls12, turn, srtp. |
| Learning / DP | R8 / R19 / R23 | DP composition, EMA pull = 0.1, no secure aggregation in v1. |
| Voice / STT | R34D | STT confidence threshold + clarifying-question fallback. |
| NOVA toolchain | external | `stage2.s == stage3.s` self-host invariant treated as a load-bearing CI gate. |

See [`NEXT_SESSION.md`](NEXT_SESSION.md) for the per-round detail and
[`docs/adr/r36f-0001-language-choice-nova.md`](docs/adr/r36f-0001-language-choice-nova.md)
.. R36F-0006 for the rationale behind each track.

> **R35A note.** v1.0 -- all 10 phases complete and assembled into one
> unified agent process. Implemented in NOVA and verified against the
> real self-hosting toolchain.
>
> R38C (R34B.3 / R35B.3) adds the SERVER-side TURN state machine that
> closes R35B's exit caveat ("the TURN server's allocation pool, peer-
> side enforcement, and data forwarding are NOT modeled"). New module
> `src/federation/turn_server.nova` (~890 lines) layered READ-ONLY on
> R34B's wire codec + R35B's client machine + R36A's auth helpers --
> all four prior turn rounds remain byte-untouched. **State**:
> `turn_server_init()` returns a list with positional slots
> (allocations_list, port_pool, port_pool_next, active_allocations_count,
> 8 counter slots for allocates received/granted/rejected, refreshes,
> permissions granted, channels bound, data forwarded, allocations
> expired; realm + nonce_counter; relay_ip_v4 buf). Default port pool
> is 49152..65535 (RFC 5766 §6.2 ephemeral); `turn_server_init_with_port_range`
> lets callers shrink the pool for exhaustion tests. **Per-allocation
> record**: client_addr (4B ip + 2B port = 6B buf), relayed_port,
> lifetime_sec, expiry_unix, permissions_list (`[peer_ip, peer_port,
> expiry]` per peer), channels_list (`[chan_num, ip, port, expiry]`
> per binding), last_activity_unix, auth_realm + auth_nonce.
> **Handlers**: `turn_server_handle_allocate` -- no auth -> 401 with
> REALM + NONCE; with creds -> SUCCESS + relay port from pool; stale
> NONCE on re-allocate -> 438; non-UDP REQUESTED-TRANSPORT -> 442;
> pool empty -> 508; same client w/o delete -> 437. `turn_server_handle_refresh`
> -- no allocation -> 437; lifetime=0 -> SUCCESS + delete + return
> port to pool; lifetime>0 -> SUCCESS + extend expiry.
> `turn_server_handle_create_permission` -- per peer
> XOR-PEER-ADDRESS, append to permissions_list with expiry = now + 300
> (RFC 5766 §8); multi-peer in one request supported.
> `turn_server_handle_channel_bind` -- channel_num MUST be in
> [0x4000, 0x7FFE]; same channel + diff peer -> 400 conflict; same
> channel + same peer -> idempotent refresh; success auto-adds a
> permission (RFC 5766 §11.2 implicit-permission rule); expiry =
> now + 600. `turn_server_handle_send` -- looks up the allocation
> for the client_addr; checks the peer has either an active
> permission OR an active channel binding; if not, drops silently
> (RFC 5766 §10.3); on success returns `[peer_ip, peer_port,
> data_buf, data_n]` for the caller's wire driver to forward.
> `turn_server_tick(state, now)` -- walks allocations_list back-to-
> front and removes expired entries (returns ports to the pool +
> bumps `stats_expired`); within each surviving allocation prunes
> expired permissions + channels; returns `[n_alloc_expired,
> n_perm_expired, n_chan_expired]`. R34B's "build response helpers"
> section (success + error response emitters for all four request-
> bearing methods) covers everything except a 401 response with
> REALM + NONCE attributes -- `turn_server_emit_401_response` is the
> SINGLE locally-duplicated emit helper. **111 new assertions** in
> `tests/unit/test_turn_server.nova`: init shape (16384-port pool,
> all counters 0, default realm); allocate without auth -> 401
> parseable via R34B's `turn_parse_401_response`; credentialed retry
> via R34B's `turn_emit_allocate_request_authed` -> SUCCESS with
> XOR-RELAYED-ADDRESS + LIFETIME echoed via R34B's parser;
> stale-NONCE rejection; non-UDP transport -> 442; pool exhaustion
> (1-port pool, 2 clients) -> 508; dup-allocate same client -> 437;
> refresh active -> SUCCESS w/ new lifetime; refresh non-existent
> -> 437; refresh lifetime=0 -> delete + port returned; CP one peer
> + three peers (single multi-attr request) + no allocation -> 437;
> CB 0x4000 happy path + 0x3FFF / 0x7FFF out of range -> 400 +
> same-channel-different-peer conflict -> 400 + same-channel-same-
> peer idempotent refresh; send to permitted peer -> returns data;
> send to non-permitted -> drop; send through channel binding only
> (no explicit permission) works (channel implies permission); send
> with no allocation -> drop; tick removes expired allocation +
> expired permission within active allocation + expired channel
> within active allocation; multi-allocation (3 distinct clients,
> independent permissions). Honest caveat: this is server-side STATE
> -- no socket I/O. The wire driver (a future round) hooks up the
> UDP listener, parses incoming packets, dispatches to these
> handlers, and sends responses + forwarded data. Auth verification
> (HMAC-SHA1 over the message via `turn_verify_message_integrity`)
> is structurally supported but not consulted by the handler -- any
> message with USERNAME + MESSAGE-INTEGRITY attributes is accepted.
> A future round can wire in the credential database + run the
> `turn_verify_message_integrity` check before granting the
> allocation. R34B / R35B / R35D / R36A test suites all pass
> byte-identical post-R38C.
>
> R37F (R36F.2) materializes the Vercel-hybrid reference architecture
> R36F's `docs/GETTING_STARTED.md` Section 5 named but deferred. Lands
> `infra/vercel-proxy/` as a complete scaffold: a Next.js 14 App Router
> app (`web/`) with a streamed chat UI (`app/page.tsx`) and a single
> Vercel Function (`app/api/chat/route.ts`) that forwards `/api/chat`
> POSTs to `${CROSSENGIN_URL}/chat` with `Authorization: Bearer
> ${CROSSENGIN_TOKEN}`; a Python HTTP wrapper (`backend/server.py`)
> that listens `:8080`, validates the bearer in constant time
> (`hmac.compare_digest`), and routes per `session_id` to a persistent
> `bin/crossengin-chat` child (the `scripts/web.py` pattern -- LRU cap
> `CE_MAX_SESSIONS=8`, eviction sends `/quit`); a Dockerfile
> (`ubuntu:24.04`) that clones NOVA + CrossEngin, runs `bootstrap.sh`,
> `make install`s the binaries, and exposes `:8080`; a
> `docker-compose.yml` for one-command local dev (volume mount
> `./data:/data` for persistence; `entrypoint.sh` refuses to start
> with the dev-default token unless `CE_ALLOW_DEV_TOKEN=1`); deploy
> recipes (`backend/README.md`) for Fly.io / Hetzner VPS / Render;
> `ARCHITECTURE.md` (end-to-end flow + latency budget + ~5 EUR/mo
> single-user cost model + JWT upgrade path for v2); `SECURITY.md`
> (six-threat walkthrough: token leakage / DoS via expensive prompts
> / backend exposure / session-id spoofing / stdin interleave /
> container escape, with code-level mitigations); two smoke tests
> (`tests/test_backend_health.py` -- `/health` 200 + `/chat` 401
> without auth; `tests/test_chat_route.ts` -- mocks fetch, validates
> request-shape pass-through across the 500/400/413/502 + happy-path
> cases). `docs/GETTING_STARTED.md` Section 5.3 replaces the "TODO
> reference architecture" pointer with the full scaffold layout,
> local + production deploy commands, and a configuration env-vars
> table. R37F.2 candidates (documented but unshipped): a `chat.sh
> --batch` mode that takes input on stdin and emits the reply on
> stdout in a single process per call (removes the
> `/tmp/crossengin_input` choreography); per-IP rate-limiting at the
> Vercel function via Upstash Redis; an `infra/vercel-proxy/proxy/`
> Caddyfile template with Vercel-IP-range filtering for public-VPS
> deploys; Dockerfile hardening (non-root user, read-only rootfs,
> `cap_drop: [ALL]`). Honest caveat: the v0.1 token-rotation flow
> has no overlap window -- between backend rotation and Vercel
> rotation the function returns 401; the JWT-with-public-key
> upgrade path in `ARCHITECTURE.md` lifts that limitation but is not
> shipped here.
>
> R37C (R36A.2 / R34C.2) retires both remaining inline MD5 + SHA-1 +
> HMAC-SHA1 copies in the tree. R36A re-inlined MD5 + SHA-1 +
> HMAC-SHA1 into `src/federation/turn.nova` (~200 lines) because
> R34C's `_srtp_hmac_sha1` was underscore-prefixed (private);
> un-mangling on R34C's side would have broken a sealed module.
> R34C re-inlined SHA-1 + HMAC-SHA1 into `src/federation/srtp.nova`
> (~150 lines) and documented the duplication as an R34A.3-style
> follow-up candidate. R37C ships the canonical `src/safety/md5.nova`
> (lifted from R36A's `_turn_md5_*` -- the only inline source) and
> `src/safety/sha1.nova` (lifted from R34C's `_srtp_sha1_*` -- the
> cleaner of the two source copies; R36A's SHA-1 aliased its helpers
> onto MD5's helpers in a namespace tangle). Both consumers now
> `import` the canonicals and expose their underscore-prefixed local
> symbols as thin one-line wrappers; all 359 prior turn assertions +
> 131 prior srtp assertions hold byte-identical (the same wrapper-
> preservation contract R33A + R34A used for SHA-256). New tests
> `tests/unit/test_md5.nova` (16 assertions; RFC 1321 §A.5 KAT) and
> `tests/unit/test_sha1.nova` (17 assertions; FIPS 180-4 Appendix A
> + RFC 3174 + RFC 2202 HMAC-SHA1 KAT) pin the canonicals against
> the published vectors. Module count delta: +2; net line delta:
> -227 (+536 md5 + +509 sha1 + +280 test_md5 + +347 test_sha1 -
> 420 turn - 194 srtp). Honest caveat: MD5 is LITTLE-endian per
> RFC 1321 §3.5 while SHA-1 + SHA-256 are BIG-endian; the
> implementations bake this in via `_md5_store_le32` vs
> `_sha1_store_be32`. Both consumers' call sites consume digest
> bytes directly without re-encoding so the byte-order asymmetry
> never escapes the canonical.
>
> R36A (R34B.2 / R35B.2 / R35D.2) closes three TURN-related deferrals
> in one bundle: long-term-credential authentication (RFC 5389 §10 /
> RFC 5766 §4), per-permission refresh cadence, and a permission-
> lifetime override hook. Extension to `src/federation/turn.nova`
> (~830 lines added; existing 1669 lines + the R34B / R35B blocks
> preserved byte-for-byte) and `src/federation/ice_turn.nova` (~230
> lines added; existing 485 lines preserved). Inline MD5 (RFC 1321)
> and HMAC-SHA1 (RFC 2104 + RFC 3174) are added LOCAL to `turn.nova`
> because R34C's `_srtp_hmac_sha1` is underscore-prefixed (private);
> a future R36A.2 can canonicalize alongside the SHA-256 dedup work
> R33A established. **Auth flow** (RFC 5389 §15.4):
> `turn_emit_allocate_request_authed(txn, lifetime, transport,
> username, password, realm, nonce)` builds an Allocate with
> USERNAME + REALM + NONCE attributes followed by MESSAGE-INTEGRITY
> (20-byte HMAC-SHA1 keyed on `MD5(username:realm:password)`). The
> length field counts the FULL body including MI, but the HMAC is
> computed over the prefix [0..MI_attr_start) -- RFC 5389 §15.4
> spec rule. `turn_parse_401_response(buf, n) -> [realm_buf,
> realm_n, nonce_buf, nonce_n] | TURN_ERR_*` extracts the auth
> challenge from a 401 Unauthorized response.
> `turn_verify_message_integrity(buf, n, key)` re-computes the
> HMAC over the same prefix and compares against the embedded
> value -- returns 0 (no crash) on missing MI per documented
> tolerance. **Per-permission cadence** (RFC 5766 §8 / §11):
> `TURN_PERM_LIFETIME_DEFAULT = 300` (already in R35B) +
> `TURN_CHANNEL_LIFETIME_DEFAULT = 600`. New
> `turn_client_tick_perms(state, now) -> [n_perms_expired,
> n_channels_expired]` walks both lists and removes entries whose
> `expiry < now`, bumping `stats_perm_expired` +
> `stats_channel_expired` counters. `turn_client_tick_authed(state,
> now)` is the composed alloc-expiry + perm-cadence tick callers
> drop in to replace R35B's `turn_client_tick`. **Lifetime
> override** (RFC 5766 §8): CreatePermission success responses do
> NOT echo back a granted lifetime (unlike Allocate which echoes
> LIFETIME). R35B stamped the client-side estimate at `now + 300`;
> R36A keeps that default and adds `turn_set_perm_lifetime_default(
> state, secs)` for non-RFC servers, stored in a new state slot
> consulted by `turn_client_restamp_last_permission`. State slots
> 0..23 from R35B preserved byte-for-byte; R36A appends 3 new slots
> (perm-lifetime default, perm-expired counter, channel-expired
> counter). **ICE-TURN 401 auto-retry** (R35D.2): the original
> `ice_turn_handle_allocate_response` classified any 401 as
> `RELAY_FAILED`; R36A's parallel
> `ice_turn_handle_allocate_response_authed` parses out REALM +
> NONCE, transitions to a new `ICE_TURN_AUTH_PENDING` state, and
> returns `ICE_TURN_RELAY_AUTH_PENDING`. Caller then invokes
> `ice_turn_credentials(state, username, password)` to supply the
> creds; we emit a credentialed Allocate via the R36A authed
> emitter and bump `stats_auth_retries`. A SECOND 401 -- meaning
> the credentials were wrong -- classifies `RELAY_FAILED` and
> stops. New ice_turn state slots appended: `auth_realm_buf` /
> `_n` + `auth_nonce_buf` / `_n` (freshly-alloc'd copies that
> outlive the recv buf) + `auth_state` (NONE / PENDING / OK /
> FAILED) + `stats_auth_retries`. **136 new assertions** -- 82
> turn + 54 ice_turn. Turn coverage: MD5 RFC 1321 §A.5 vectors
> (empty / "abc" / "message digest"), HMAC-SHA1 RFC 2202 TC1
> (`0x0b * 20` key + "Hi There") + TC2 ("Jefe" + "what do ya want
> for nothing?"), `turn_hmac_sha1_key` matches direct MD5,
> attr-order on the authed emit (LIFETIME / REQUESTED-TRANSPORT /
> USERNAME / REALM / NONCE / MESSAGE-INTEGRITY), MI-position rule
> (re-compute HMAC over [0..MI_attr_start) and confirm equality
> with the embedded value), self-emit MI verify, wrong-key MI
> fails, no-MI message returns 0 (no crash), parse_401 extracts
> REALM + NONCE / rejects no-REALM / rejects non-401 codes,
> `TURN_PERM_LIFETIME_DEFAULT = 300` + `TURN_CHANNEL_LIFETIME_DEFAULT
> = 600`, tick_perms removes-when-expired / keeps-in-window /
> mixed-window per-record pruning, channel pruning via
> `_turn_record_channel_r36a` with 600s default, composed
> `tick_authed` (alloc + perms in one call), perm lifetime override
> reflected after recv via `turn_client_restamp_last_permission`,
> tick_perms on IDLE = `[0, 0]` no-crash, R35B-shape state
> auto-extends to 27 slots. ICE-TURN coverage: init_authed state
> shape (23 slots, all auth fields zero), 401 -> AUTH_PENDING
> (REALM + NONCE stashed as freshly-alloc'd copies), credentialed
> re-emit is a real Allocate Request with 6 attrs ending in MI,
> credentialed re-emit success -> ACTIVE + relay candidate
> injected, second 401 -> RELAY_FAILED + AUTH_FAILED, non-401 errors
> fall through to the R35D handler unchanged, credentials() refused
> when not PENDING, first-try success skips the auth path, full
> end-to-end flow (gather host -> all pairs fail -> escalate ->
> 401 -> credentials -> success -> relay candidate present in
> ice_agent), counter does not bump on refused credentials() call.
> **323 prior turn + 88 prior ice_turn assertions byte-identical**
> (R36A appends to the tail of each suite). Honest caveat: MD5 is
> cryptographically broken for collision resistance (Wang 2004),
> but RFC 5389 §15.4 mandates `MD5(user:realm:pass)` as the
> HMAC-SHA1 key for the long-term-credential mechanism, so R36A
> remains on-spec. Modern replacements are SCRAM-SHA1 / SCRAM-SHA256
> (RFC 7635) -- deferred. The retry uses the SAME txn id as the
> initial Allocate (keeps response correlation simple); rotating
> the txn between the two requests would need an additional state
> slot.
>
> R35A (R34C.2) closes the DTLS-SRTP keying loop per RFC 5764 §4.2.
> Before R35A, the SRTP master key + salt had to be supplied
> out-of-band by the caller of R34C's `srtp_derive_keys`; with R35A
> they are extracted from the completed DTLS handshake's TLS-1.2
> PRF via the well-known label `"EXTRACTOR-dtls_srtp"` (19 ASCII
> bytes) and the seed `client_random || server_random`. The
> 60-byte PRF output is partitioned per §4.2 into client + server
> SRTP master keys (16B each) and client + server SRTP master
> salts (14B each), and each peer picks "its" half based on
> `is_server`. Two new public functions: `dtls_export_srtp_
> keying_material(state) -> 60-byte buf | 0` in
> `src/federation/dtls12.nova` (composed over the existing
> `dtls_prf_sha256`; refuses when `cipher_active == 0`), and
> `srtp_init_from_dtls(dtls_state, is_server) -> [encr_key (16B),
> auth_key (20B), salt (14B)] | 0` in `src/federation/srtp.nova`
> (calls the exporter, slices "our" 16-byte mk + 14-byte ms per
> `is_server`, forwards to the existing R34C `srtp_derive_keys`).
> `srtp.nova` gains a one-way import edge to `dtls12.nova`; the
> reverse direction is intentionally absent so dtls12 stays
> import-graph-leaf-shaped under safety/. 40 new assertions across
> the two suites: 16 dtls12 R35A (cipher_active gate, 60-byte
> output, alice/bob byte-identical exporter output, RFC label
> length + 4 ASCII spot bytes, per-state repeat determinism) +
> 24 srtp R35A (pre-handshake gate for both is_server values,
> 3-element list shape, client/server keys asymmetric -- encr +
> auth + salt all differ -- repeat determinism, one-direction
> seal+open round-trip with client-keys, cross-side seal+open
> returns SRTP_AUTH_FAIL pinning the §4.2 half-selection rule).
> 353 prior dtls12 + 111 prior srtp assertions byte-identical
> (R35A appends to the tail of each suite). Honest caveat:
> exporter PRF cost is two HMAC-SHA256 iterations; called once
> per session post-handshake, not on the per-packet hot path, so
> per-call recompute is fine.
>
> R38B (R33B.4) closes R33B's last DTLS caveat -- the deferred
> "real DTLS-CCS rekeys via the PRF (key_block expansion under the
> new epoch's seed)" note. `dtls_advance_epoch(state)` now re-runs
> the TLS 1.2 PRF on every advance to re-expand the 40-byte
> `key_block` from the SAME `master_secret` +
> `server_random || client_random` seed (RFC 5246 §6.3 / RFC 6347
> §4.1.2.6), and re-slices the four sub-buffers
> (`client_write_key`, `server_write_key`, `client_write_iv`,
> `server_write_iv`) via the existing `_dtls_slice_key_block`
> helper. A new tail-appended slot
> `DTLS_S_SLOT_STATS_REKEYS = 45` accumulates a per-advance
> counter exposed via `dtls_stats_rekeys(state)` and surfaced on
> `dtls_stats_line` as `rekeys=<n>`. R38B ships variant A: re-run
> the SAME PRF inputs -- the resulting 40 bytes are byte-identical
> to pre-advance. Variant B (mix the epoch into the seed,
> non-standard) is documented as a future research item. Cross-
> epoch differentiation is provided by the AEAD AAD layer (RFC
> 6347 §4.1.2.1 puts the epoch in the upper 16 bits of the AAD
> seq_num), so byte-identical keys do NOT enable cross-epoch
> replay -- the PRF re-run is telemetry + a hook, NOT the load-
> bearing security property. 35 new dtls12 R38B assertions across
> 9 test functions (init zero counter, advance bumps counter
> monotonically, pre-cipher advance bumps counter but skips PRF,
> post-advance key_block + 4 sub-buffer pointers reallocated +
> bytes byte-identical, cross-epoch seal/open after rekey,
> variant A determinism, R36B cache invalidation invariant
> intact, stats line includes `rekeys=`, per-state independence).
> 417 prior dtls12 assertions byte-identical (slot 45 tail-
> appended; slots 0..44 untouched; new `rekeys=` field appended
> at the END of `dtls_stats_line` so R33B / R36B substring scans
> still match). Honest caveat: variant A is on-spec but doesn't
> add cryptographic cross-epoch key differentiation -- the AAD
> epoch upper bits do; variant B would, but it's non-standard.
>
> R36B (R35A.2 / R33B.3) closes R35A's "future hardening" caveat
> by memoizing the 60-byte PRF expansion in a fresh tail-appended
> state slot (`DTLS_S_SLOT_SRTP_KM_CACHED = 43`). First call to
> `dtls_export_srtp_keying_material(state)` computes the PRF as
> before and stashes the returned buf pointer in the slot; every
> subsequent call serves THAT SAME pointer (not a fresh copy) and
> bumps a cumulative cache-hit counter
> (`DTLS_S_SLOT_STATS_SRTP_KM_HITS = 44`, exposed via
> `dtls_stats_srtp_km_hits(state)`). Cache invalidation hook:
> `dtls_advance_epoch(state)` (the R33B CCS-on-epoch-change reset
> path) clears the cache slot back to 0 so a real DTLS
> re-handshake never serves stale SRTP keys -- if the
> master_secret is genuinely unchanged the next exporter call
> recomputes the same 60 bytes (idempotent), and if it changed
> we MUST recompute. The hits counter is cumulative and is NOT
> reset on epoch advance, mirroring the R32B / R33B telemetry
> pattern. 32 new dtls12 R36B assertions across 8 test functions
> (init zero-cache shape, miss-populates / does-NOT-bump-hits,
> same-pointer hit + hits bumps to 1/2, advance_epoch invalidates
> + miss recomputes + next hit bumps to 3, cached bytes
> byte-identical, per-state independence, cipher_active gate
> still runs first). 369 prior dtls12 assertions byte-identical
> (slots 43+44 tail-appended; slots 0..42 untouched). Honest
> caveat: invalidating on every epoch advance is the
> safe-but-slightly-wasteful default -- a pure key_block CCS
> (no re-handshake; same master_secret) will pay one extra PRF
> expansion next call (two HMAC-SHA256 iterations).
>
> R35D lands the ICE-TURN integration layer -- when ICE's
> peer-to-peer candidate gathering exhausts host + server-reflexive
> candidates without a usable pair, the orchestrator escalates to a
> TURN-relay candidate via R34B's TURN codec. New module
> `src/federation/ice_turn.nova` (~360 lines, leaf consumer of
> `ice.nova` + `turn.nova`, modifies NEITHER) implements
> `ice_turn_init` / `ice_turn_check_escalation` /
> `ice_turn_begin_allocate` / `ice_turn_handle_allocate_response` /
> `ice_turn_relay_priority`. Escalation decision: ALL ICE pairs in
> `ICE_CHECK_FAILED` terminal state AND TURN not already activated
> -> `ICE_TURN_ESCALATE`. One-way: once `turn_active=1`, subsequent
> checks return `NO_ESCALATION`. Begin-allocate emits a 36-byte
> Allocate Request via `turn_emit_allocate_request(txn_id,
> lifetime=600, transport=UDP17)` and latches `turn_active`. On
> successful Allocate Response, extracts the relayed (ip, port) and
> injects it as an `ICE_TYPE_RELAY` local candidate into R30C's
> agent via existing `ice_add_local_candidate(...)`. On 401 / 437
> error response, captures err_code + reason and bumps the failure
> counter; ice_agent stays unchanged. Relay candidate priority
> (RFC 8445 §5.1.2.1) = `2^24 * 0 + 256 * 65535 + (256 - 1) =
> 16777215` -- verified hand-computed AND against R30C's
> `ice_candidate_priority(ICE_TYPE_RELAY, 65535, 1)`.
> `tests/unit/test_ice_turn.nova` adds 88 new assertions: init
> shape, relay priority (RFC formula + R30C cross-check),
> `check_escalation` decision tree (empty / some-succeeded /
> in-progress / all-failed / already-active), `begin_allocate`
> classifier round-trip + counter + txn-id mirror,
> `handle_allocate_response` happy path (relayed addr extracted,
> RELAY-typed candidate added to ice_agent, all candidate fields
> correct), 401 / 437 / malformed-bytes error paths (failure
> counter, ice_agent unchanged), end-to-end flow (gather host+srflx
> -> drive 4 pairs to FAILED -> escalate -> allocate -> success
> -> re-form 3x2=6 pairs with relay local present). Out of scope
> (documented in module header): USERNAME / MESSAGE-INTEGRITY /
> NONCE / REALM long-term-credential auth handshake (R34B's emit
> path doesn't generate them; R35D inherits the limitation),
> downgrade-after-escalation (RFC 8445 allows re-nomination but
> R35D is one-way escalate), Refresh / Permission / Channel
> lifecycle (R35B's `turn_client_*` state machine handles those at
> `063824e`), CreatePermission for each remote peer (follow-up
> wiring on top of R35D + R35B), multi-relay environments. Prior
> assertions byte-identical: R30C ice `OK (70 checks)` + R34B turn
> `OK (323 checks)` -- 200 original R34B assertions plus R35B's
> 123 state-machine extension assertions in the same suite.
>
> R35B lands the TURN client-side allocation state machine on top of
> R34B's wire codec. Extension to `src/federation/turn.nova`
> (~500 lines added; the wire codec block 1..1052 unchanged
> byte-for-byte). Six-state lifecycle (`TURN_STATE_IDLE` ->
> `_PENDING` -> `_ACTIVE` -> `_REFRESHING` -> `_EXPIRED` / `_FAILED`),
> 24-slot positional state list (state, current txn_id, relayed +
> mapped IP/port, lifetime + expiry, last_err_code, permissions_list,
> channels_list, 9 counter slots, in-flight method, pending peer for
> in-flight perm/chanbind). Public API: `turn_client_init`,
> `turn_client_send_allocate` (IDLE -> PENDING), `turn_client_send_
> refresh` (ACTIVE -> REFRESHING), `turn_client_send_permission` (must
> be ACTIVE; stamps the peer for the response handler to append),
> `turn_client_send_channel_bind` (must be ACTIVE; rejects channel_num
> outside `[0x4000, 0x7FFE]` per RFC 5766 §11 BEFORE emit),
> `turn_client_recv(state, buf, n, now)` dispatches to one of
> `TURN_RECV_ALLOCATED` / `_ALLOCATE_FAILED` / `_REFRESHED` /
> `_REFRESH_FAILED` / `_REFRESH_DELETED` / `_PERMITTED` /
> `_PERM_FAILED` / `_CHANNEL_BOUND` / `_CHANNEL_FAILED` / `_DATA` /
> `_IGNORED`, and `turn_client_tick(state, now)` transitions ACTIVE
> -> EXPIRED when `expiry < now`. Mismatched txn_ids on incoming
> responses are IGNORED per RFC 8489 §6.3.3. CreatePermission success
> appends `[peer_ip, peer_port, now+300]` (RFC 5766 §8 default) to
> `permissions_list`; ChannelBind success appends `[chan_num,
> peer_ip, peer_port]` to `channels_list`. Refresh with `lifetime=0`
> transitions ACTIVE -> EXPIRED (RFC 5766 §7 server-initiated delete).
> `tests/unit/test_turn.nova` extended to **323 assertions total** --
> the prior 200 R34B assertions are byte-identical (lines 1..852
> unchanged), plus 123 new R35B assertions covering: initial state
> IDLE + all 9 counters zero, send_allocate / send_refresh /
> send_permission / send_channel_bind state transitions and counter
> bumps, recv of Allocate success / Allocate error (401) / Refresh
> success / Refresh delete (lifetime=0) / Refresh error / perm
> success+error / chanbind success+error / Data Indication / mismatched
> txn / truncated buf, tick before/after expiry, channel_num band
> enforcement (0x3FFF / 0x7FFF / 0x8000 rejected, 0x4000 boundary
> accepted), multi-peer permissions (3 peers added in sequence), full
> lifecycle walk IDLE->PENDING->ACTIVE->REFRESHING->EXPIRED->PENDING
> (re-allocate after EXPIRED), ACTIVE->EXPIRED via tick. Deferred:
> server-side allocation pool (RFC 5766 §6.2 -- a future round if
> anyone needs to RUN a relay), per-permission refresh cadence (the
> data structure carries expiry stamps but `tick` only reports
> allocation expiry), 401-retry credential composition, IPv6.
> Honest caveat: permission expiry is a CLIENT-side estimate
> (`now+300` per RFC §8 default) because the CreatePermission success
> response does NOT echo a permission lifetime; clients should re-issue
> CreatePermission well inside the 5-minute window.
>
> R34B lands the TURN protocol wire codec (RFC 5766 / 8656) -- the
> last R28E.2 deferred item. New module `src/federation/turn.nova`
> (~700 lines, leaf) implements parse + emit for the six TURN
> message methods (Allocate / Refresh / Send / Data /
> CreatePermission / ChannelBind) plus eight TURN attributes
> (CHANNEL-NUMBER, LIFETIME, XOR-PEER-ADDRESS, DATA,
> XOR-RELAYED-ADDRESS, REQUESTED-TRANSPORT, DONT-FRAGMENT,
> RESERVATION-TOKEN). Wire format reuses STUN's 20-byte header +
> TLV-attribute framing (magic cookie 0x2112A442, 12-byte
> transaction id) from R30C's `src/federation/stun_rfc8489.nova`,
> adds TURN-specific method/class packing (e.g. Allocate Request =
> 0x0003, Allocate Success Response = 0x0103). Public emit API
> covers the five client-side messages; public parse API decodes
> Allocate Success / Error, Refresh Success, and Data Indication.
> `turn_classify_message(buf, n) -> [method, class, length,
> txn_ptr]` for the demuxer. `tests/unit/test_turn.nova` adds 200
> new assertions: Allocate request->success-response round-trip
> (LIFETIME + REQUESTED-TRANSPORT + XOR-RELAYED + XOR-MAPPED all
> decode), Allocate Error 401 / 437, Refresh with lifetime 0
> (delete) / 60 / 600 (RFC 5766 §2.2 default), CreatePermission
> single + multi-peer (three peers), Send Indication large-payload
> round-trip via the symmetric Data Indication parser, ChannelBind
> round-trip, malformed message rejections (short header / bad
> cookie / truncated TLV / unaligned length / wrong-method-for-
> parser / IPv6 family / top-2-bits-non-zero), STUN-shared
> attribute tolerance (SOFTWARE / USERNAME / MESSAGE-INTEGRITY /
> REALM / NONCE / FINGERPRINT injected -- codec extracts the
> right values without choking), auth-required error response.
> Skipped per the brief: IPv6 XOR addresses (parse rejects family=2
> with `TURN_ERR_FAMILY`), long-term-credential authentication on
> the emit side (parse side correctly handles 401 + REALM + NONCE),
> EVEN-PORT / ADDITIONAL-ADDRESS-FAMILY attributes, relay state
> machine (allocation lifecycle, permission table, channel
> bookkeeping, channel-data framing). Honest caveat:
> MESSAGE-INTEGRITY + FINGERPRINT are TOLERATED on incoming
> messages (presence does not reject) but NOT verified -- a future
> hardening round should plumb the STUN MI verifier through.
>
> R34C lands the SRTP wire codec (RFC 3711) -- the next federation
> primitive after R29B/R31B/R32B/R33B's DTLS 1.2 + R30C's ICE.
> New module `src/federation/srtp.nova`: AES-CM-128 stream cipher
> (RFC 3711 §4.1.1, salt || ssrc || packet_index XOR construction
> with per-block counter increment), HMAC-SHA1-80 authenticator
> (RFC 2104 + truncation to 80 bits per RFC 3711 §4.2, with the
> 32-bit ROC appended to the AAD), AES-CM-based key derivation
> (RFC 3711 §4.3 -- master key + salt -> encryption key (16B,
> label 0x00) + auth key (20B, label 0x01) + SRTP salt (14B,
> label 0x02)), 64-packet sliding anti-replay window keyed on
> the 48-bit extended sequence (same pattern R32B used for DTLS
> 1.2 but on the RTP seq), and the RFC 3711 §3.3.1 ROC estimator
> for guessing the rollover counter on a wrapping 16-bit seq.
> Public API: `srtp_state_init` / `srtp_seal_packet` /
> `srtp_open_packet` / `srtp_kdf` / `srtp_derive_keys` /
> `srtp_authenticate` / `srtp_encrypt` / `srtp_decrypt`.
> AES-128 block primitive is reused from R30B's `src/safety/
> aes_gcm.nova` (no duplication). SHA-1 is inlined locally as
> `_srtp_sha1_*` -- it is NOT currently in `src/safety/` and the
> R34C brief deferred the canonical extraction; future R34A.3-style
> dedup can move it to `src/safety/sha1.nova` when a second
> consumer needs SHA-1. `tests/unit/test_srtp.nova` adds 111 new
> assertions: SHA-1 KATs (RFC 3174 Appendix A: "abc", "", FIPS
> Appendix B.2 56-char, 55-byte one-block boundary), HMAC-SHA1
> RFC 2202 TC1 + TC2 + TC4 + long-key normalization,
> AES-CM keystream against published AES-128-ECB vectors,
> **RFC 3711 §B.3 KDF official test vector verified
> byte-identical for all three labels**, full seal+open round-trip
> across header (12B) + 32-byte payload + 10-byte tag, tamper
> rejection on tag-flip + ct-flip + header-flip (all three flow
> to SRTP_AUTH_FAIL and do NOT advance the replay window), replay
> rejection of the same packet_index (-> SRTP_REPLAY), 64-packet
> jump slides the window (idx=0 -> idx=64 -> replay of idx=0 ->
> SRTP_TOO_OLD), ROC rollover send-side at seq=65534 -> 65535 -> 0
> (send_seq wraps, send_roc bumps), ROC rollover recv-side via
> the §3.3.1 estimator. DTLS-SRTP key extraction (RFC 5764) is
> NOT in scope -- master key + salt come from the caller; a future
> round wires DTLS's PRF output into `srtp_derive_keys`. Honest
> design caveat: the `srtp_open_packet` API takes `hdr_n` from the
> caller rather than parsing RTP CSRC count + extension header --
> a real WebRTC caller knows its own header length from RTP byte 0
> + extension parsing, and exposing this as an explicit parameter
> keeps the codec layer-agnostic.
>
> R34D adds an STT-confidence gate to the voice dialog policy. When
> whisper-cli's per-utterance confidence (averaged from per-token `"p":`
> probabilities in the R10B `-ojf` JSON output) is below threshold, the
> dialog responds "I did not catch that clearly. Could you repeat?"
> rather than advancing the state machine on a probably-misheard
> transcript. Default threshold 0.5; configurable per
> `CE_VOICE_STT_CONF_THRESHOLD` (integer percent, 0..100). New
> `vc_session_turn_with_confidence(kg, session, transcript, conf_milli)`
> entry; `last_stt_confidence` telemetry slot in the session state.
> R31F kind-pivot + R32F multi-kind clarify routing both remain intact
> for high-confidence transcripts (verified via 5 regression
> assertions). +42 new voice_dialog unit assertions, +4 new
> whisper_backend unit assertions. All 319 prior voice_dialog assertions
> stay byte-identical -- the new gate is strictly additive on top of
> `vc_session_turn`. Calibration of the confidence threshold against
> ground truth is deferred (the 0.5 default is the brief's intuitive
> cut, not a per-environment learned value).
>
> R34A (R33A.2) retires the FOURTH and last inline SHA-256 copy in the
> tree: `src/federation/dtls12.nova`'s `dtls_sha256` + `dtls_hmac_sha256`
> are now thin one-line wrappers around R33A's canonical
> `sha256_oneshot` / `hmac_sha256` in `src/safety/sha256.nova`. R33A
> landed the canonical and refactored 3 of 4 consumers (noise_xk,
> merkle, ecdsa); dtls12 was held back because R33B was concurrently
> wiring cert verify into the same file (file-ownership rule). R33B
> landed at `37706b8`; R34A is the planned follow-up that closes the
> last duplication. The DTLS-specific composition (HKDF-Extract /
> HKDF-Expand RFC 5869 + TLS 1.2 PRF P_SHA256 RFC 5246 §5) stays
> inline because it composes HMAC-SHA256 in recipes that have no
> analog in the canonical module; it picks up the canonical SHA-256
> + HMAC transparently through the `dtls_hmac_sha256` wrapper. Lines
> removed: ~290 inlined FIPS 180-4 SHA-256 + HMAC + 32-bit helpers +
> K-table + IV + compression. Lines added: 9 (one import + two
> 1-line wrapper bodies + header doc updates). Net: -216 lines in
> dtls12.nova. The dedup completes the 4-of-4 retirement R32C's exit
> report tracked. All 353 prior dtls12 assertions remain
> byte-identical -- the wrapper pattern (proven on 3 of 4 modules by
> R33A) preserves wire-level identity by construction; the canonical
> implementation was lifted from R32C's ecdsa.nova SHA-256 (FIPS
> 180-4 spec-conformant, bit-equivalent to dtls12's prior inline
> copy). Module count delta: 0 (no new files); inline-SHA-256 copy
> count: **4 -> 0** (canonical is now the single authoritative source).
>
> R33B finalizes DTLS 1.2: cert verify is wired (R29B.3 retires the last
> `_R29B2_STUB` slot by importing R32C's `x509_parse` +
> `x509_check_validity` + `ecdsa_p256_verify_bn` -- five distinct
> failure tags for parse / not-yet-valid / expired / sig / fingerprint
> mismatch, plus optional SHA-256 fingerprint binding per RFC 4572 §5)
> and the anti-replay sliding window now resets on
> `dtls_advance_epoch` per RFC 6347 §4.1.2.6 (the R32B.2 deferral).
> AAD now stamps the epoch as `(epoch << 48) | seq` per RFC 5246
> §6.2.3.3, so cross-epoch ciphertexts carry distinguishable AEAD tags
> even when the window resets. All 297 prior R29B + R31B + R32B
> assertions remain byte-identical (epoch=0 AAD collapses to plain
> seq; new state slots are tail-appended). 17 new R33B test functions
> add 56 assertions covering all five cert outcomes, epoch-reset
> state transitions, cross-epoch AEAD round-trip, and the six new
> stats-line fields. Cert chain validation is single-cert only --
> CrossEngin's actual cert use case is SDP-fingerprint pinning, so
> CA traversal is deferred to a hardening round if needed.
>
> R33A lands the canonical `src/safety/sha256.nova` (FIPS 180-4
> SHA-256 + RFC 2104 HMAC-SHA256) and refactors three of four
> previously-duplicated copies (`noise_xk.nova`, `merkle.nova`,
> `ecdsa.nova`) to import it. R32C's exit report flagged the SHA-256
> dedup as the fourth duplicated cryptographic primitive in the tree;
> R33A closes that loop for three of the four. `dtls12.nova` is left
> alone in this round -- R33B owns the dtls12 dedup in parallel, and
> a follow-up round retires the fourth copy once both land. Lines
> removed (~800 inlined SHA-256 across the 3 modules) vs lines added
> (~520 canonical module + ~42 wrapper-and-import lines across the
> 3 consumers): net -240 lines. API exported from the canonical:
> `sha256_oneshot(buf, n)` / `sha256_oneshot_bytes(byte_list)` /
> `sha256_oneshot_str(s)` / streaming
> `sha256_init` / `sha256_update` / `sha256_final` / and
> `hmac_sha256(key_buf, key_n, msg_buf, msg_n)`. Each consumer keeps
> its pre-existing public symbol shape (`sha256_buf` /
> `_mk_sha256_buf` / `ecdsa_sha256` etc.) as a thin one-line wrapper
> so existing tests and call sites compile unchanged. All prior 44
> noise_xk + 60 merkle + 25 ecdsa + 297 dtls12 unit assertions remain
> green; `tests/unit/test_sha256.nova` adds 20 new assertions covering
> FIPS 180-4 known-answer vectors, streaming-vs-oneshot equivalence
> (5 splitting strategies), and RFC 4231 HMAC-SHA256 TC1 + TC2 + TC4
> + the long-key normalization branch.
>
> R33E closes the R32A.2 caveat by threading a transient `nat_state_t`
> through `nat_query_stun(addr)` and `nat_detect_type(addr1, addr2)`
> so the env flag `CE_NAT_USE_RFC8489=1` activates the UDP RFC 8489
> path on the **stateless** surface too, not just the stateful
> `nat_query_stun_with_state(state, addr)`. Approach: transient-per-call
> (each stateless call allocates its own `nat_state_t`, used for the
> codec + UDP path, discarded on exit -- no module-singleton
> `stun_state_t`, no shared mutable codec state, two concurrent
> stateless callers can never race on txn ids or sockets). Module-level
> 6-slot snapshot (`nat_stateless_last_path` / `_udp_sent` / `_recvd` /
> `_timeouts` / `_external` / `_error`) reflects the LAST stateless
> call only (replaced not accumulated), so tests + integration
> scenarios can confirm the UDP path was actually taken without a
> caller-visible state allocation. `nat_detect_type` is automatically
> threaded (it calls `nat_query_stun(addr)` twice). All 162 prior
> R23E + R31C + R32A unit assertions pass byte-identical; **+47 new
> R33E unit assertions** (total now 209 for nat_traversal). **+13 new
> R33E integration assertions** under `STATELESS_UDP_PATH` sub-scenario
> in `scenario_oooo_nat_traversal.sh`. Honest caveat: the module-level
> snapshot is the one piece of shared mutable state R33E introduces;
> the codec state itself is per-call transient, so two concurrent
> stateless callers can race on the snapshot but cannot corrupt each
> other's call result (NOVA is single-threaded today, so moot).
>
> R32C lands the cryptographic primitives R29B's
> `dtls_cert_verify_R29B2_STUB` slot needs but does NOT wire them in
> (that's R32C.2). Two new safety modules: `src/safety/x509.nova`
> (RFC 5280 §4.1 minimal X.509 v3 parser -- DER primitives for
> INTEGER / OID / SEQUENCE / SET / BIT STRING / OCTET STRING /
> UTCTime / GeneralizedTime / BOOLEAN; cert handle pulls out
> serialNumber, signature OID (must be ecdsa-with-SHA256 =
> 1.2.840.10045.4.3.2), issuer CN, subject CN, validity, the 65-byte
> uncompressed P-256 public key, the ECDSA-Sig-Value `r`/`s`, and the
> byte-exact tbsCertificate slice for hash-and-verify; validity check
> compares Unix seconds against parsed notBefore/notAfter), and
> `src/safety/ecdsa.nova` (FIPS 186-4 §6.4 ECDSA-P-256 verify on top
> of R30B's `p256.nova`, plus a self-contained SHA-256 -- the third
> copy of FIPS 180-4 in the tree, alongside `noise_xk.nova`,
> `merkle.nova`, and `dtls12.nova`; documented duplication, refactor
> target is `src/safety/sha256.nova`). ECDSA verify: range-checks
> `r`, `s` in `[1, n-1]` before any curve math, computes
> `w = s^-1 mod n` via Fermat, `(X, Y) = u1*G + u2*Q` via two scalar
> mults + one affine add, accepts iff `X mod n == r`. Verified against
> the canonical RFC 6979 §A.2.5 ECDSA-P-256 + SHA-256 vectors
> (`"sample"` AND `"test"` messages with the published Q, r, s);
> verifies both uncompressed and compressed SEC1 public-key encodings.
> **Combined cert+verify smoke test PASSES** on an OpenSSL-generated
> self-signed P-256 cert hardcoded as a 397-byte DER vector (notBefore
> 2026-06-04, notAfter 2126-05-11, subject/issuer CN
> `CrossEnginTest`): `x509_parse` extracts tbs + pubkey + r + s,
> `ecdsa_sha256(tbs)` matches the openssl reference
> `cfa7c41cc9cf98bd772c5398ca92692f30ca193e3dff5527105aafb957fd1ce6`,
> `ecdsa_p256_verify_bn` returns 1. Tamper-rejection verified on all
> four paths: flipped `r` byte, flipped `s` byte, flipped message
> hash, wrong public key (Q + G) -- each returns 0; also r/s == 0
> AND r/s == n (out-of-range), wrong-tag and truncated public-key
> buffers all reject. Module count delta: **+2**. Test delta:
> **+79 unit assertions** (`tests/unit/test_x509.nova` 54 checks +
> `tests/unit/test_ecdsa.nova` 25 checks; full suite now 227 tests
> all passing). Honest caveats: (a) ECDSA verify is NOT
> constant-time -- inherits R30B.3 hardening item from `p256.nova`'s
> data-dependent double-and-add; for VERIFY this is academic (all
> inputs are public), but documented; (b) X.509 extensions parsing,
> certificate chains, RSA / Ed25519 keys, CRL / OCSP revocation are
> all out of scope and deferred; (c) SHA-256 is duplicated rather
> than extracted to a shared module -- documented in both module
> headers, refactor tracked. R32C does NOT touch `dtls12.nova`,
> `p256.nova`, `aes_gcm.nova`, `bignum_256.nova`, or any federation
> module -- R32C.2 lands the wiring in the same way R31B wired
> R30B's primitives.
>
> R32B closes R31B's "no anti-replay sliding window yet" caveat by
> extending `src/federation/dtls12.nova` with the canonical RFC 6347
> §4.1.2.6 algorithm. R31B (commit `af8e47c`) wired real P-256 ECDHE
> + AES-128-GCM into DTLS records but left `RECV_SEQ` advancing
> monotonically on success only -- the open path would NOT reject a
> replayed sealed record. R32B now does. Four new state slots
> appended at indices 32..35 (preserving byte-identical layout of
> slots 0..31): `RECV_HIGH_WATERMARK` (u64 highest validated seq),
> `RECV_REPLAY_MASK` (64-bit sliding bitmap, bit i = "seq hw-i has
> been seen"), `STATS_REPLAY`, `STATS_TOO_OLD`. Two new error tags
> `DTLS_REPLAY` + `DTLS_TOO_OLD` distinct from `DTLS_DECRYPT_FAIL`
> so callers can tell pre-AEAD rejection from AEAD oracle failure.
> The anti-replay check runs BEFORE the AEAD decrypt -- a replay
> short-circuits without calling `gcm_open`, both because it would
> be wasted crypto work and (critically) because we do NOT want to
> give an attacker an oracle on bogus seq numbers. The window
> updates only AFTER the AEAD tag check passes, so a forged record
> at `high_watermark + N` with a bad MAC cannot advance the
> watermark and lock out the legitimate next packet. Algorithm:
> S > hw -> tentatively accept (slide window after AEAD), S in
> window with bit clear -> accept (set bit after AEAD), S in
> window with bit set -> `DTLS_REPLAY`, S < hw-63 -> `DTLS_TOO_OLD`.
> Verification: **66 new R32B unit assertions** in
> `tests/unit/test_dtls12.nova` (total now 297; R31B's 84 + R29B's
> 147 = 231 prior assertions pass byte-identical;
> `dtls12: OK (297 checks)`). Coverage includes sequential
> seq=1..4 (watermark advances to 4); replay seq=2 returns
> `DTLS_REPLAY` and watermark/mask are unchanged; big-jump seq=1
> then seq=100 slides window + clears mask + then seq=1 is
> `DTLS_TOO_OLD`; out-of-order seq=1,5,3 -> 3 accepted, replay 3
> -> `DTLS_REPLAY`; too-old seq=1,200,50 -> `DTLS_TOO_OLD`;
> watermark=64 boundary; **tamper-does-not-advance-window**
> (forge seq=10 with flipped tag -> AEAD fails -> watermark/mask
> stay -> legitimate seq=1 still passes); replay short-circuits
> before AEAD (no `TAMPER_*` counter bumps); end-to-end with
> R31B's full ECDHE round-trip (Alice seals one 32B payload, Bob
> opens cleanly, the SAME sealed bytes replayed return
> `DTLS_REPLAY`). `dtls_stats_line` extended with `hi_watermark=`,
> `replay=`, `too_old=` fields. Honest caveats: (a) cross-epoch
> reset deferred -- DTLS 1.2 ChangeCipherSpec MUST reset the
> window per RFC 6347 §4.1.2.6 and R32B does not yet do that
> (wire driver landing in R31B.2's "no handshake state-machine
> integration" follow-up); (b) 64-bit window only (RFC permits
> 256; R32B matches the OpenSSL default); (c) no constant-time
> bit-check (replay-vs-accept latency leaks the same fact the
> distinct return code already does). R32B does NOT modify
> `p256.nova`, `aes_gcm.nova`, `webrtc.nova`, or any other
> federation module. Module count delta: 0.
>
> R32A closes R31C's deferred R31C.2 by wiring
> `src/federation/nat_traversal.nova`'s RFC 8489 path to actual UDP
> sockets via R28C's `sys_socket_udp` / `sys_sendto` /
> `sys_recvfrom` builtins. R31C had migrated the codec but kept
> `nat_query_stun_with_state` on the TCP-text wire because UDP was
> believed unavailable at write time; R28C had in fact already
> shipped the UDP syscalls across 6 codegen backends. When
> `CE_NAT_USE_RFC8489=1` is set in the env, `nat_query_stun_with_state`
> now opens a UDP socket, dispatches the RFC 8489 Binding Request
> through R30C's codec, waits up to `CE_NAT_RFC8489_TIMEOUT_MS`
> (default 1000ms) for a Binding Success Response on `sys_recvfrom`,
> parses the XOR-MAPPED-ADDRESS into `NAT_S_MY_EXTERNAL`, and closes
> the fd. When the env flag is unset / 0, the legacy R23E TCP text
> path runs **bit-identical** -- the original body lifted into a
> private `_nat_query_stun_tcp` helper, no byte changes. Three new
> state slots `NAT_S_UDP_SENT`, `NAT_S_UDP_RECVD`,
> `NAT_S_UDP_TIMEOUTS` track the UDP-layer activity with R31C-shape
> accessors `nat_udp_sent_count`, `nat_udp_recvd_count`,
> `nat_udp_timeout_count`. NEW split helpers `nat_udp_open`,
> `nat_udp_send_binding_request_at`, `nat_udp_recv_binding_response`,
> `nat_udp_query_rfc8489_with_state` expose the layers so tests can
> drive both sides of a loopback round-trip in one process.
> Verification: **+61 unit assertions** in
> `tests/unit/test_nat_traversal.nova` across 14 new
> `test_r32a_*` functions (R23E's 33 + R31C's 17 test functions
> stay byte-identical; pre-R32A 101 -> R32A 162). The loopback
> round-trip test binds a real UDP responder socket, sends a real
> Binding Request, receives + parses a real Binding Success Response,
> and verifies XOR-MAPPED-ADDRESS round-trips through to
> `NAT_S_MY_EXTERNAL`. The timeout test verifies `sys_recvfrom`
> returning -1 bumps `NAT_S_UDP_TIMEOUTS` and does NOT corrupt the
> existing external addr. **+17 integration assertions** in
> `tests/integration/scenario_oooo_nat_traversal.sh` across two
> sub-scenarios: `UDP_RT` runs the full loopback round-trip in a
> child NOVA process; `UDP_FLAG` spawns a child with
> `CE_NAT_USE_RFC8489=1` against a closed UDP port and verifies
> the dispatch actually walks the UDP path
> (`NAT_S_UDP_SENT=1, NAT_S_UDP_TIMEOUTS=1, last_error=udp-timeout`)
> rather than the legacy TCP path (which would have produced
> `dial-failed`). R32A modifies ONLY
> `src/federation/nat_traversal.nova`,
> `tests/unit/test_nat_traversal.nova`, the scenario script, and
> the three docs. It does NOT touch `stun_rfc8489.nova`,
> `ice.nova`, `dtls12.nova`, or any other federation module.
> Module count delta: 0.
>
> R31C migrates `src/federation/nat_traversal.nova` (R23E) to route
> the wire half through R30C's `src/federation/stun_rfc8489.nova`,
> while preserving every R23E public API function byte-identical.
> R23E shipped an ad-hoc STUN-LIKE TCP text wire (`STUN_REQUEST\n` /
> `EXTERNAL <ip>:<port>\n`) -- great for soul-to-soul federation,
> NOT RFC 8489 compliant (no 20-byte header, magic cookie, txn id,
> TLV attributes, XOR-MAPPED-ADDRESS, MESSAGE-INTEGRITY,
> FINGERPRINT). R30C shipped the real RFC 8489 codec. R31C migrates:
> NEW public helpers `nat_send_binding_request`,
> `nat_recv_binding_response`, `nat_emit_rfc8489_binding_request`,
> `nat_parse_rfc8489_binding_response`,
> `nat_format_rfc8489_success_response_ipv4` ALL route through
> `stun_rfc8489` exclusively -- this module owns NO RFC 8489 byte
> arithmetic. NEW state slots `NAT_S_STUN_STATE` (lazy),
> `NAT_S_RFC_REQUESTS`, `NAT_S_RFC_OK`, `NAT_S_RFC_BAD`.
> `nat_recv_binding_response` writes the decoded XOR-MAPPED-ADDRESS
> back into the existing `NAT_S_MY_EXTERNAL` slot so the R23E
> status line stays the source of truth. Legacy STUN-LIKE TCP text
> wire stays **default-on** (the scenario\_oooo manual STUN /
> GOSSIP\_HELLO multiplexer dispatches on the first newline-
> terminated text line; binary RFC 8489 would break that dispatcher
> -- separate concern). Env flag `CE_NAT_USE_RFC8489=1`
> + `nat_use_rfc8489_enabled()` are wired; R31C.2 wires actual UDP
> dispatch once NOVA exposes `sendto/recvfrom`. Explicit legacy-
> compat shims `nat_legacy_emit_stunlike_request`,
> `nat_legacy_parse_stunlike_response`,
> `nat_legacy_format_stunlike_response` are named for callers that
> hardcoded the old wire. Verification: **48 new R31C unit
> assertions** in `tests/unit/test_nat_traversal.nova` (extends the
> file additively; R23E's 53 asserts pass byte-identical, total
> 101). Coverage: emitted Binding Request parses as RFC 8489 with
> right type / cookie / FINGERPRINT (`stun_msg_parse`,
> `stun_verify_fingerprint`); MESSAGE-INTEGRITY round-trip across
> right + wrong passwords; high-level send/recv round-trip writes
> 203.0.113.99:54321 back into `NAT_S_MY_EXTERNAL`; bad-packet path
> bumps `NAT_S_RFC_BAD` without clobbering the external slot; the
> three legacy-compat shims emit / parse the original text wire
> byte-for-byte; the env flag defaults to off. **+6 integration
> assertions** in `tests/integration/scenario_oooo_nat_traversal.sh`
> -- soul B drives an in-process RFC 8489 emit + parse cycle
> alongside the legacy TCP text query so the integration test
> witnesses both wires. R31C does NOT modify `stun_rfc8489.nova`,
> `ice.nova`, `gossip*.nova`, or any other federation module.
> Module count delta: 0.
>
> R31B wires R30B's P-256 ECDH + AES-128-GCM AEAD primitives into
> R29B's DTLS 1.2 record-layer + handshake skeleton -- the three
> cryptographic `_R29B2_STUB`-tagged slots in
> `src/federation/dtls12.nova` now have real implementations.
> Replaced: `dtls_ecdhe_derive_R29B2_STUB` -> `dtls_ecdhe_derive`
> (generates a P-256 keypair via `p256_keygen`, derives the
> shared secret via `p256_derive(priv, peer_pub_compressed)`,
> runs the TLS 1.2 PRF over `(pms, "master secret", C_rand ||
> S_rand)` for the 48-byte master_secret, runs PRF again over
> `(master_secret, "key expansion", S_rand || C_rand)` for the
> 40-byte key_block, slices into `client_write_key(16) ||
> server_write_key(16) || client_write_IV(4) ||
> server_write_IV(4)` per RFC 5246 §6.3 + RFC 5288 §3 (MAC keys
> are 0 bytes for the AEAD suite)). Replaced:
> `dtls_seal_record_R29B2_STUB` -> `dtls_seal_record` (builds the
> 12-byte nonce as `implicit_IV(4) || explicit_IV(8 = seq_num
> big-endian)`, builds the 13-byte AAD per RFC 5246 §6.2.3.3 as
> `seq_num(8) || type(1) || version(2) || length(2 PLAINTEXT
> length)`, calls `gcm_seal`, wraps in record header || explicit_IV
> || ciphertext || tag(16)). Replaced:
> `dtls_open_record_R29B2_STUB` -> `dtls_open_record` (parses
> header + explicit_IV, reconstructs nonce + AAD, calls `gcm_open`,
> increments `recv_seq` ONLY on tag-validated success). The legacy
> `_R29B2_STUB` functions remain in the file as regression guards
> (the R29B unit test `test_stubs_return_DTLS_ERR_STUB` still
> pins them against DTLS_ERR_STUB). New `dtls_state` slots:
> `IS_SERVER` (drives which key/IV pair seal vs open uses),
> `CIPHER_ACTIVE` (set 0->1 once derive finishes), `PRIV_BN`,
> `LOCAL_PUB`, `PEER_PUB`, `CLIENT_RANDOM`, `SERVER_RANDOM`,
> `MASTER_SECRET`, `KEY_BLOCK`, the four sliced sub-buffers,
> per-direction `SEND_SEQ` / `RECV_SEQ`, `TAMPER_CT` / `TAMPER_TAG`
> / `TAMPER_AAD` rejection counters, and `AEAD_RECORDS_OUT` /
> `AEAD_RECORDS_IN`. New error tag `DTLS_DECRYPT_FAIL` (returned
> by `dtls_open_record` on any failure mode -- intentionally
> indistinct per RFC 5246 §7.2.2 to avoid leaking oracle bits).
> Verification: **84 new R31B unit assertions** in
> `tests/unit/test_dtls12.nova` (total now 231); R29B's 147
> assertions pass byte-identical. End-to-end ECDHE round-trip
> verified (Alice + Bob derive matching master_secret + key_block
> + sliced keys + IVs byte-identically). AEAD round-trip
> verified on 16B / 64B / 1024B payloads. Cross-side AEAD
> verified (Alice seals -> Bob opens, Bob seals -> Alice opens).
> Tamper detection covered for all three paths (ciphertext byte
> flip, tag byte flip, seq_num bump that corrupts AAD); each
> tamper counter bumps independently. Stubs still tagged:
> `dtls_cert_verify_R29B2_STUB` (R31B does not land X.509 parsing
> + ECDSA verify -- MITM is trivial without that),
> `dtls_extract_srtp_keys_R29B2_STUB` (R28E.2 follow-up: RFC 5705
> EKM for SRTP-DTLS interop). Honest design caveats: (a) no
> anti-replay sliding window yet -- `RECV_SEQ` only advances
> monotonically (R31B.2); (b) no constant-time scalar
> multiplication (inherits R30B.3 hardening item from p256.nova);
> (c) no handshake state-machine integration -- `dtls_ecdhe_derive`
> does not advance DTLS_S_* states (the wire driver does that in
> R31B.2); (d) `dtls_ecdhe_keygen_seeded` is test-only (production
> callers must use `dtls_ecdhe_keygen` which pulls from
> `secure_random`). dtls12.nova is no longer a TRUE leaf: it now
> imports `src/safety/p256.nova` + `src/safety/aes_gcm.nova`.
> Module count delta: 0.
>
> R30B lands the leaf cryptography primitives R29B.2 needs to
> de-stub the DTLS record-layer + handshake skeleton: a NIST P-256
> ECDH module (`src/safety/p256.nova`) and an AES-128-GCM AEAD
> module (`src/safety/aes_gcm.nova`). R29B (commit `a3b1233`)
> tagged five `_R29B2_STUB` slots in `dtls12.nova` and called out
> two crypto prerequisites: P-256 scalar multiplication (the
> existing `bignum_2048.nova` ships only RFC 7919 G14 2048-bit
> MODP DH, NOT short-Weierstrass curves) and AES-128 + GHASH (the
> existing `chacha20.nova` + `poly1305.nova` are ChaCha20-Poly1305,
> NOT AES-GCM). R30B ships BOTH. `p256.nova` provides field
> arithmetic over GF(p) with p = 2^256 - 2^224 + 2^192 + 2^96 - 1
> (Mont-REDC-backed via the existing `bignum_256.nova`), Jacobian
> point arithmetic using the Bernstein-Lange dbl-2001-b doubling +
> add-2007-bl addition formulas for a = -3, double-and-add scalar
> multiplication, SEC1 compressed (0x02/0x03 + 32B X) and
> uncompressed (0x04 + 32B X + 32B Y) point encoding with
> decompression via the sqrt-mod-p trick a^((p+1)/4), and the public
> ECDH API `p256_keygen` + `p256_derive(priv, peer_pub, n)`.
> `aes_gcm.nova` provides FIPS 197 AES-128 encrypt-only (S-box, key
> schedule, round function), NIST SP 800-38D GHASH over GF(2^128)
> with the bit-reversed convention and 0xe1 || 0^15 reduction
> polynomial, and the public AEAD API `gcm_seal(key, iv12, aad,
> aad_n, pt, pt_n)` + `gcm_open(key, iv12, aad, aad_n, ct_tag,
> ct_tag_n)`. Verified against RFC 5903 §8.1 ECDH NIST P-256 Test
> Vector byte-identical both halves (priv * G = (gix, giy) AND
> priv * peer = expected Z), FIPS 197 Appendix C.1 AES single-block,
> SP 800-38D Appendix B Test Cases 1-2-3-4 (empty / single-block /
> multi-block with and without AAD), GHASH H*0 sanity, 5-scalar
> ECDH self-consistency sweep (A*B == B*A), `gcm_open` tamper
> rejection on ciphertext byte / tag byte / AAD / wrong key, and a
> non-block-aligned `gcm_seal`/`gcm_open` round-trip. **52 P-256
> assertions + 45 AES-GCM assertions = 97 new unit assertions.**
> R30B does NOT modify `dtls12.nova` -- the `_R29B2_STUB` slots
> stay tagged; R30B.2 will wire them. R30B does NOT ship constant-
> time scalar multiplication (double-and-add leaks bit pattern;
> tracked as R30B.3 Montgomery-ladder hardening). Module count
> delta: +2 (`src/safety/p256.nova`, `src/safety/aes_gcm.nova`).
>
> R30C closes the ICE half of the R28E.2 follow-up list flagged by
> R28E (commit `8c566fb`, WebRTC SDP signaling). R29B took DTLS;
> R30C ships TWO new modules in parallel: (1)
> `src/federation/stun_rfc8489.nova` -- a true RFC 8489 STUN client
> wire codec (20-byte header with magic cookie 0x2112A442 + 12-byte
> transaction id; TLV attribute block with 4-byte padding; Binding
> Request 0x0001 / Binding Success Response 0x0101 / Binding Error
> Response 0x0111; XOR-MAPPED-ADDRESS for IPv4 + IPv6;
> MESSAGE-INTEGRITY HMAC-SHA1 with length-field patch per RFC 8489
> 14.5; FINGERPRINT CRC32 with XOR mask 0x5354554E per RFC 8489
> 14.7; USERNAME, ERROR-CODE, SOFTWARE attributes). Pure-NOVA SHA-1
> + HMAC-SHA1 + CRC32 bundled in-module so the file is a TRUE LEAF
> (no imports of `dtls12.nova`'s SHA-256). Verified against
> SHA-1(\"abc\") FIPS 180-2, SHA-1(\"\") FIPS 180-2, the 56-byte
> two-block-pad input, HMAC-SHA1 RFC 2202 TC1 + TC2, and
> CRC32(\"123456789\") = 0xCBF43926. Public client API:
> `stun_init`, `stun_send_binding_request`, `stun_recv` (matches by
> txn id, decodes XOR-MAPPED-ADDRESS or ERROR-CODE),
> `stun_verify_message_integrity`, `stun_verify_fingerprint`. R30C
> does NOT modify `nat_traversal.nova` (R23E's STUN-like ad-hoc
> newline wire) -- a future R30C.2 will migrate callers. (2)
> `src/federation/ice.nova` -- an RFC 8445 ICE agent subset:
> candidate types (host / srflx / relay-stub) with the
> §5.1.2.1 priority formula
> `priority = 2^24*type_pref + 256*local_pref + (256 - component_id)`;
> candidate pair priority §6.1.2.3
> `2^32 * MIN(G,D) + 2 * MAX(G,D) + (G > D ? 1 : 0)`; pair formation
> with address-family + component-id filters; per-pair check state
> Waiting / In-Progress / Succeeded / Failed; regular nomination
> (lite version) on the first Succeeded pair. Public API:
> `ice_init(is_controller)`, `ice_add_local_candidate`,
> `ice_add_remote_candidate`, `ice_form_pairs`, `ice_get_pair`,
> `ice_mark_pair_in_progress` / `_succeeded` / `_failed`,
> `ice_get_nominated`. R30C does NOT ship: actual STUN binding-request
> driving on pair sockets (R30C.2), TURN relay candidate gathering
> (R30C.3), mDNS candidate obfuscation, trickle ICE, ICE restart,
> aggressive nomination. Verification: **135 STUN unit assertions**
> in `tests/unit/test_stun_rfc8489.nova` + **70 ICE unit assertions**
> in `tests/unit/test_ice.nova` covering header byte layout, TLV
> attribute padding, MESSAGE-INTEGRITY tamper detection, FINGERPRINT
> tamper detection, all three RFC 5769 wire samples (§2.1 Sample
> Request / §2.2 IPv4 Response / §2.3 IPv6 Response) parse
> correctly with the 192.0.2.1:32853 mapped address decoded for the
> v4 sample, the priority formula validated against four hand-
> computed worked examples (host/lp=65535, srflx/lp=10000,
> relay/lp=0, component tiebreak), the pair-priority formula validated
> against three worked examples (G<D, G>D, G=D), and the
> state-machine table (4 valid + 4 invalid edges). Module count
> delta: +2 (`src/federation/stun_rfc8489.nova`,
> `src/federation/ice.nova`).
>
> R29B lands `src/federation/dtls12.nova` -- the DTLS 1.2
> record-layer + handshake skeleton + crypto primitives for the
> R28E.2 follow-up flagged by R28E (commit `8c566fb`). R28E shipped
> WebRTC SDP signaling and stubbed the data plane with the sentinel
> `RTC_ERR_NEEDS_DTLS`; R29B starts closing that gap. The new module
> is a TRUE LEAF (no imports of other CrossEngin modules) so parallel
> R28E.2 agents (ICE / SRTP / STUN-TURN) cannot collide with it.
> Delivers: (1) RFC 6347 section 4.1 record layer
> (`DTLSPlaintext { type, version=0xfefd, epoch, sequence_number(48b),
> length, fragment }`) with `dtls_record_serialize` /
> `dtls_record_parse` round-tripping byte-identical to the spec;
> (2) RFC 6347 section 4.2.2 handshake envelope
> (`Handshake { msg_type, length(24b), message_seq,
> fragment_offset(24b), fragment_length(24b), body }`) -- R29B ships
> the unfragmented happy path only, parser rejects fragmented
> envelopes; (3) state machine skeleton INIT ->
> CLIENT\_HELLO\_SENT -> SERVER\_HELLO\_RECVD -> CERTIFICATE\_RECVD
> -> FINISHED -> ESTABLISHED + any-state-to-FAILED;
> (4) `dtls_client_init(state, server_name)` builds a 42-byte
> ClientHello body (32-byte zero-Random placeholder, empty
> session\_id + cookie, one cipher suite, null compression), wraps
> in handshake envelope, wraps in DTLSPlaintext record, advances
> state; (5) cipher-suite gate accepts ONLY
> ECDHE-ECDSA-AES128-GCM-SHA256 (0xC02B, RFC 5289 -- the WebRTC
> browser-interop minimum), all others return `DTLS_ERR_NO_CIPHER`;
> (6) pure-NOVA SHA-256 + HMAC-SHA256 + HKDF-Extract + HKDF-Expand +
> TLS 1.2 PRF (P\_SHA256) bundled in-module. Verified against:
> SHA-256("abc") FIPS 180-2 vector, SHA-256("") FIPS 180-2 vector,
> HMAC-SHA256 RFC 4231 test case 1
> (`b0344c61...e32cff7`), HKDF RFC 5869 test vector 1 PRK
> (`077709362c2e32df...7c2b3e5`) + 42-byte OKM
> (`3cb25f25...887185865`), and a self-consistent PRF round-trip
> with determinism + length-budget + label-discrimination +
> multi-A() iteration coverage. R29B does NOT ship: real ECDHE
> P-256 key exchange (needs `src/safety/p256.nova` -- bignum\_2048
> ships only RFC 7919 Group 14), X.509 cert parsing + ECDSA verify,
> AES-128-GCM record AEAD (chacha20.nova ships ChaCha20+Poly1305
> only), HelloVerifyRequest cookie exchange, anti-replay sliding
> window, retransmission scheduling (counter tracked, no timer
> driven), SRTP master-key extractor (RFC 5705 EKM with
> `dtls_srtp` label), DTLS 1.3. Every stub is suffixed
> `_R29B2_STUB` so future agents can grep them. Verification:
> **147-assertion unit suite** in `tests/unit/test_dtls12.nova`
> (NEW; 35 tests) covers record-layer byte-layout across 3 hand-
> constructed wire vectors (handshake/alert/application\_data,
> varying epoch + 48-bit seq), record-parser rejections (short
> header / bogus content-type / truncated fragment), handshake
> envelope round-trip + 3 rejection paths (short / nonzero
> frag\_off / mismatched frag\_len), msg\_seq monotonicity +
> flight retransmit counter, state-machine edge table (5 valid
> forward + any-to-FAILED + 4 invalid edges), `dtls_client_init`
> end-to-end + non-INIT rejection, cipher-suite gate (accept /
> reject / mixed / empty), 5 RFC test vectors above,
> PRF determinism + multi-block path, and 5 R29B.2 stub regression
> guards. All **221 unit tests pass** (+1 new in R29B); federation
> baselines hold (gossip 34, gossip\_noise 44, gossip\_relay 61,
> nat\_traversal 53, leader\_election 40, webrtc 19). Module count
> +1 (`src/federation/dtls12.nova`).
>
> R28A closes the BEHAVIOURAL gap R27E (commit `ada38e1`)
> documented in R21B distributed rule inference: the per-round DRFETCH
> fan-out was synchronous with a hardcoded 500 ms ACK timeout, so a slow
> peer caused subsequent rounds to dial fewer peers and the chain
> extension to stop short of full closure. R28A adds **opt-in adaptive
> per-peer DRFETCH timeout + late-ACK isolation** inside
> `src/federation/distributed_rules.nova`: each peer's recent DRFETCH
> RTTs are tracked in a 5-sample rolling window, the next-round timeout
> is `min(5000, max(500, 2 × median + 200))` ms (the 500 ms floor
> matches R21B's hardcoded default so a fast peer keeps its existing
> budget; slow peers grow their budget over rounds), and a DRFETCH
> late-ACK is silently dropped (counter `dr_stats_late_drops`) without
> propagating to the gossip `SUSPECT` path -- only PING/ACK timeouts
> mark SUSPECT. The dispatch shape stays sequential (the same per-peer
> serial order R21B uses); an earlier R28A draft tried a phase-1-
> dispatch / phase-2-collect pipelining and regressed every sub-
> scenario because NOVA's single-threaded peer handlers blocked their
> accept queues while holding multiple connections open. Opt-in via
> `CE_DR_ASYNC_FETCH=on` (any of `on`/`1`/`yes`); with the env var
> unset the legacy R21B path is bit-for-bit unchanged. Verification:
> **35-assertion unit suite** in `tests/unit/test_dr_async_fetch.nova`
> (NEW) drives the per-peer latency table + adaptive-timeout
> calculator + late-drop isolation without live sockets; R21B's
> existing 42-assertion suite + all federation prior suites
> (gossip 34, gossip\_noise 44, gossip\_relay 61, distributed\_query
> 36, rule\_inference 47) remain green. Module count unchanged at 191.
> R27E's scenario\_yyyy re-run with `CE_DR_ASYNC_FETCH=on`:
> **STABLE 5-soul derives the FULL 55 ancestor closure** in 11
> fixpoint rounds (latency 46716 ms, well under the 60 s budget).
> All three cross-soul probes (`ancestor|0:10`, `ancestor|0:5`,
> `ancestor|5:10`) materialise. Driver STATS:
> `derived=55 rounds=11 async=1 async_rx=30 late_drops=0
> timeout_adj=0`. R21B sync baseline on the same host: 35 derived
> in 6 rounds (PARTIAL closure -- exactly the failure mode R27E
> documented). R28A closes the gap completely on this scenario.
>
> R31A (this round, layered on top of R30A under the same
> `CE_DRFETCH_PIPELINE=on` switch) closes R30A's
> "`sys_poll` parallelises the response WAIT but not the connection
> ESTABLISHMENT" caveat by making the dial pass non-blocking too.
> Two new NOVA builtins (shipped on the NOVA side this round:
> `sys_fcntl_setfl_nonblock` + `sys_getsockopt_so_error`) provide
> the POSIX recipe — `socket()` + `fcntl(F_SETFL, O_NONBLOCK)` +
> `connect()` returning `-EINPROGRESS=-115` + `sys_poll(POLLOUT)` +
> `getsockopt(SO_ERROR)`. Phase 1 of the pipelined DRFETCH path is
> now two sub-phases: (1a) every peer's TCP handshake races in
> parallel via one `sys_poll(POLLOUT)` call, (1b) post-dial
> HELLO/OK + DRFETCH-header sends walk serially over the survivors
> after `O_NONBLOCK` is cleared. Four new diagnostic counters
> (`conn_dispatched / _ready / _timeouts / _so_error`) join the
> R30A `pipe_*` family in `dr_stats_line` when the pipeline is on.
> Honest expectation: at 5 peers on loopback the dial cost is
> ~10us so the parallel-dial win is invisible; the win materialises
> above ~50 peers on lossy WAN where each dial costs 50-150 ms.
> Verification: **+23 new R31A assertions** layered on top of R30A's
> 74 in `tests/unit/test_dr_async_fetch.nova` (97 total) covering
> the new counters, wrapper API, SO\_ERROR readback semantics, and
> CE\_DRFETCH\_PIPELINE=0 bit-identical-to-R30A guarantee; scenario\_yyyy
> gains a PHASE1\_PARALLEL sub-scenario.
>
> R30A (prior round, opt-in via `CE_DRFETCH_PIPELINE=on`) implements
> **true pipelined DRFETCH** on top of R28A using NOVA R29A's new
> `sys_poll(fds, nfds, timeout_ms)` builtin. Phase 1 dispatches the
> DRFETCH header to every alive peer back-to-back (no waiting for
> ACKs between dispatches); phase 2 builds a POSIX pollfd array
> (`alloc(N*8)`, `{fd:i32 @0, events:i16 @4, revents:i16 @6}`),
> calls `sys_poll(fds, N, MAX(per-peer adaptive timeout))` once,
> then drains ready FDs in arrival order and attributes each
> response to its originating peer. R28A's late-ACK isolation
> invariant is preserved: a pipeline timeout bumps the new
> `dr_stats_pipeline_timeouts` counter and the existing
> `dr_stats_late_drops` (compat), but NEVER touches gossip's
> SUSPECT counter -- only PING/ACK liveness probes propagate
> suspicion. Four new diagnostic counters
> (`pipe_dispatched / _ready / _timeouts / _partial`) surface in
> `dr_stats_line` ONLY when the pipeline path is active, so legacy
> log scrapers keep working under the default config. The R30A
> design is the same phase-1 / phase-2 shape R28A had to abandon
> when NOVA had no multi-fd wait; R29A unblocked it. Verification:
> **+39 new assertions** in the same `tests/unit/test_dr_async_fetch.nova`
> harness (74 total) covering the new slots, pollfd layout
> assertions, late-ACK isolation, zero / one-peer degenerate
> cases, dispatcher precedence
> (`pipeline > async > sync`), and stats-line shape; scenario\_yyyy
> gains a PIPELINED sub-scenario that re-runs 5-soul STABLE with
> the flag on and emits a result-table row honest about the round
> count vs R28A's baseline. On a CI host loaded enough to time
> out the R28A serial baseline this round, R30A still achieves
> full 55 ancestor closure in 11 rounds (counters
> `dispatched=22 ready=15 timeouts=7 partial=7`), suggesting the
> multi-fd wait collapses what would have been 5 serial 500 ms
> adaptive RCVTIMEO windows into ONE such window. Honest caveat:
> `sys_poll` parallelises the response WAIT but not the
> connection ESTABLISHMENT -- phase 1 still walks `_gossip_dial`
> serially because NOVA's `connect(2)` is blocking; for meshes
> where the dial-serial cost dominates (50+ peers on lossy WAN)
> the pipeline win shrinks. With `CE_DRFETCH_PIPELINE` unset the
> R28A serial-adaptive path is the safe default.
>
> R29F adds `src/federation/kg_sync.nova` -- a delta-compression path
> on top of R23C's snapshot replication. R23C's `SNAP_FETCH <root>`
> recovers full snapshots over gossip; that's the right shape for a
> peer that lost its disk, but a peer that's just been offline for a
> few minutes pays a full-snapshot cost (~1 MiB on a 10k-atom KG) to
> recover what is often a handful of atom-insertions. R29F closes that
> gap: every insert / update / retract bumps a monotonic `kg_rev`
> counter; a stale peer reports its `since_rev` via
> `KG_DELTA_REQ <since>` and the source returns
> `KG_DELTA_RESP <from> <to> <n>\n[changes]` covering only the
> missed window. Each change is `INS|UPD|RETR <atom_id> <rev>
> <payload>` so the applier can dedupe by rev. A 256 KB cap
> (env-override `CE_KGSYNC_DELTA_CAP`) bounds the response size;
> over-cap requests get the `KG_DELTA_FULL_SNAPSHOT_REQUIRED
> <current_rev>` sentinel and the caller falls back to R23C. The
> applier tracks `applied_rev` so replaying the same delta is a
> no-op; the parser rejects malformed shape, non-digit revs,
> n-mismatch, out-of-window revs, and non-monotonic revs. Bytes
> saving on a 15-change handoff at rev=35: **delta = 503 bytes,
> equivalent text snapshot = 970 bytes** (1.9x; the absolute saving
> grows with KG size). Bytes saving at the cap-fallback boundary
> (500 changes, rev=535 KG): **sentinel = 36 bytes, equivalent
> snapshot = 21,290 bytes** (591x -- the snapshot path is the only
> viable shape at that scale, which is why the fallback exists).
> Verification: **93-assertion unit suite** in
> `tests/unit/test_kg_sync_delta.nova` (NEW; covers state-management,
> wire codec round-trip, idempotency, cap fallback, four tamper
> rejection cases) + **26-assertion integration scenario** in
> `tests/integration/scenario_bbbbb_kg_delta.sh` (NEW; 2-soul
> handoff with wire-byte assertions). All prior tests remain green.
>
> R28E lands `src/federation/webrtc.nova` -- the SIGNALING
> half of WebRTC data-channel support for browser-to-soul federation.
> CrossEngin federation up to R27 is native-only (TCP/UDP raw sockets);
> browsers cannot open arbitrary AF\_INET sockets, so a browser
> participant in a CE federation needs WebRTC. R28E ships the
> HTTP-signaled SDP offer/answer exchange: `rtc_create_offer(state)`
> emits a well-formed `v=0` / `o=` / `s=` /
> `m=application 9 DTLS/SCTP webrtc-datachannel` SDP with placeholder
> ice-ufrag / ice-pwd / fingerprint / setup attributes (the values
> are wire-shape-only; real values require the R28E.2 DTLS + ICE
> work); `rtc_receive_offer(state, sdp_offer)` parses + emits an
> answer with `a=setup:active`; `rtc_receive_answer(state,
> sdp_answer)` accepts the answer + patches the matching offer's
> remote\_id slot. The data plane is the documented R28E.2 STUB:
> `rtc_send(state, channel, payload)` and `rtc_recv(state, channel)`
> both return the sentinel
> `RTC_ERR_NEEDS_DTLS = "rtc: needs DTLS (R28E.2 stub)"`. R28E.2
> follow-up list: (1) **DTLS 1.2 / 1.3 client + server** (X.509
> self-signed cert + SHA-256 fingerprint, full record layer,
> handshake state machine, cipher-suite negotiation
> ECDHE-ECDSA-AES128-GCM-SHA256 minimum for browser interop, SRTP
> master-key extraction via RFC 5705); (2) **ICE agent** (RFC 8445 /
> 8839) -- RFC-8489 STUN client (R23E ships a STUN-LIKE wire that's
> NOT RFC 8489), candidate gathering (host / srflx / relay),
> connectivity checks, nominated-pair selection; (3) **SRTP**
> (RFC 3711) AES-128-GCM + per-packet seq# on DTLS-derived keys; (4)
> **STUN / TURN server interaction** (ship CE's own RFC 5389 / 5766
> or document configuring `stun:stun.l.google.com:19302`). Smaller
> follow-ups: wire `rtc_signaling_register` into
> `src/io/transducers/stream_http.nova` (today accepts only
> `/api/event`; needs path routing or `/rtc/*` listener); SCTP
> framing on top of DTLS records; optional WebSocket signaling
> alongside REST. Verification: **59-assertion unit suite** in
> `tests/unit/test_webrtc.nova` (NEW; 19 tests) covers init defaults,
> session-id monotonicity, offer SDP shape (v=0 first +
> m=application + setup:actpass + fingerprint + ice-ufrag),
> CRLF-vs-LF parser tolerance, rejection of empty / missing-v /
> missing-o / missing-s / audio-only SDP, receive\_offer happy +
> rejection paths, receive\_answer happy + malformed, rtc\_send /
> rtc\_recv return `RTC_ERR_NEEDS_DTLS` + bump attempt counters,
> null-channel returns `RTC_ERR_NO_CHANNEL`, signaling\_register
> stub, stats line, full alice<->bob round-trip. Integration scenario
> documented in FEDERATED\_AUDIT.md but NOT run end-to-end (a real
> browser-to-soul test needs a real browser + the R28E.2 DTLS / ICE /
> SRTP stack). All 217 unit tests pass (+1 new); federation
> baselines hold: gossip\_relay 61, gossip 34, noise\_xk 44,
> nat\_traversal 53, leader\_election 40. Module count +1
> (`src/federation/webrtc.nova`).
>
> R27E stress-tests R21B distributed rule inference (commit
> `d752b9b`, federation/distributed\_rules.nova) under realistic network
> jitter: peer drops mid-fixpoint, peer rejoin via gossip rediscovery,
> and convergence latency growth as the soul count scales 1->5. R21B's
> 3-soul scenario\_eeee\_distributed\_rules verified ALGORITHM correctness
> on a calm mesh (10 ancestor pairs from a 4-edge chain); R27E tests
> BEHAVIOUR under churn (a 5-soul mesh + 10-edge chain + 4 sub-scenarios:
> stable, drop, rejoin, latency-vs-peer-count). Driver in
> `tests/integration/_scenario_yyyy_rule_convergence_driver/
> rule_convergence_driver.nova` (one source, parameterized by
> CE\_YYYY\_\* env vars so the scenario shell spawns 5 souls with
> distinct roles + parent-edge slices without code-gen'ing a per-soul
> template). Empirical findings (3 runs on a 16 GB CI host):
> 1) **stable 5-soul**: full closure (55 ancestor pairs) typically
> achievable but only under quiet hosts; partial closure (20-40 pairs)
> is the realistic norm because R21B's per-round DRFETCH is synchronous
> and a peer that takes >500 ms to ACK gets marked SUSPECT mid-fixpoint
> -- subsequent rounds dial fewer peers, federated parent set shrinks,
> chain extension stops. The pre-fixpoint pre-ping sweep (driver calls
> gossip\_send\_ping for every known peer + drains inbound, up to 6
> retries) recovers the alive set before the first DRFETCH but a
> per-round in-flight failure can still happen. 2) **drop**:
> closure tracks the post-cut reachability graph EXACTLY at 16 ancestor
> pairs (closure of {0..2} u {3..7} u {8..10} = 3+10+3), and the
> 3 C-dependent edges 0->3, 0->10, 6->8 are correctly absent (no false
> positives). 3) **rejoin**: C restarts on the same port; A's view
> resurrects within the 30 s post-rejoin window; closure recovers past
> the drop-only baseline. 4) **latency 1-5 souls**: monotonic growth
> latency\_ms across n=2 (~5 s), n=3 (~13 s), n=4 (~17 s), n=5
> (~22 s) -- LINEAR-ish, well under quadratic. Verification: 33
> integration assertions in `scenario_yyyy_rule_convergence.sh`
> (NEW; letter `yyyy` free; covers socket pre-flight, driver compile,
> 4 sub-scenarios x avg 8 assertions each, latency growth + result
> table). All existing federation + KG scenarios remain green. R21B
> source (`src/federation/distributed_rules.nova`) is unchanged;
> minimal additions only would have been a metrics-exposure accessor
> but the existing `dr_stats_line(dr)` + `dr_stats_derived(dr)` +
> `dr_stats_rounds(dr)` + `dr_stats_rules_tx(dr)` + `dr_stats_derivs_tx(dr)`
> + `dr_stats_fetches_tx(dr)` + `dr_last_derived(dr)` + `dr_last_rounds(dr)`
> accessors already cover the round-count + message-count + fetch-count
> surface the latency scenario needs.
>
> R26C adds `src/io/transducers/audio_noise_reduce.nova` —
> spectral-subtraction Wiener noise reduction that closes the frequency-
> domain denoising gap in CrossEngin's audio chain. R14E's noise gate
> attenuates whole sub-threshold windows wholesale (perfect for chopping
> inter-utterance silences) but leaves the noise floor that overlaps a
> speech utterance intact. R26C subtracts the noise in the **per-frame
> STFT domain** so the bins occupied by speech harmonics stay loud while
> the broad noise floor between them gets pulled down. Algorithm: estimate
> per-bin noise PSD `|N(k)|^2` by averaging FFT magnitude-squared across
> the leading silence frames (first 300 ms by default); for each subsequent
> frame compute the Wiener gain `H(k) = max(0, |X(k)|^2 - |N(k)|^2) /
> |X(k)|^2` clamped to `[NR_GAIN_FLOOR_MILLI = 50, NR_GAIN_CEIL_MILLI =
> 1000]` in milli (Berouti et al. 1979 spectral-floor variant -- the 5%
> floor avoids "musical noise" artifacts that a hard zero produces);
> apply the gain to the complex `X(k)` preserving phase; inverse-FFT each
> frame via R16E `ifft_radix2`; overlap-add with a synthesis Hann window
> using the standard Griffin-Lim COLA reconstruction `out[t] =
> sum(time_re_n * h_n) / sum(h_n^2)`. Public API:
> `nr_estimate_noise(pcm, sample_rate, leading_ms) -> noise_spectrum`,
> `nr_apply_wiener(pcm, sample_rate, noise_spectrum) -> cleaned_pcm`,
> `nr_reduce(pcm, sample_rate) -> cleaned_pcm` (convenience: estimate
> from first 300 ms + apply), plus `nr_rms` / `nr_rms_window` diagnostic
> helpers. Reuses R16E for the FFT primitives; iSTFT (overlap-add) rolled
> in this module. Verification: 33 unit assertions in
> `tests/unit/test_audio_noise_reduce.nova` (NEW; defaults + accessors,
> noise estimation on noise vs silence, Wiener pass-through on pure
> signal, silence round-trip, mixed silence-lead + sine + noise drop in
> noise region while signal region preserved, Klatt /ae/ + LCG noise SNR
> improvement, length-mismatched noise_spectrum graceful empty return,
> empty input). 18 integration assertions in
> `tests/integration/scenario_uuuu_noise_reduce.sh` (NEW; letter `uuuu`
> free; NOVA driver builds the Klatt + noise fixture, writes both noisy
> and cleaned WAVs, reports per-region RMS; bash asserts noise-region
> drop >= 30%, signal-region preserved >= 70%, SNR improved, SNR >= 1.5x
> improvement; chat /denoise path is driven for /help advertising,
> bare-usage hint, missing-WAV graceful error, success diagnostic; optional
> whisper round-trip leg runs when `/usr/local/bin/whisper-main` is
> present). Calibration on the Klatt /ae/ fixture: noise-region RMS 461 ->
> 204 (55.7% reduction), signal-region RMS 7703 -> 7607 (99% preserved),
> SNR 16.7 -> 37.3 (**+6.97 dB, 2.23x improvement**). All prior audio
> suites stay green. Chat: `/denoise <wav>` admin command wired into
> `examples/crossengin_chat.nova` (1 import + 1 help + 1 dispatch line).
> Module count: +1 transducer. Honest scope: R26C ships the classical
> integer Wiener handling stationary noise; R26C.2 deferred list covers
> multi-band Wiener, continuous noise re-estimation (R7F VAD-driven),
> soft-decision Wiener / MMSE-STSA (Ephraim-Malah 1984), DNN-based
> denoising.
>
> R26E adds `src/federation/gossip_relay.nova` --
> peer-to-peer routing through an intermediary when direct dial
> isn't possible. R18E shipped SWIM gossip assuming every peer can
> reach every other peer's TCP port; R23E added NAT-type detection
> but UDP hole-punching is stubbed pending NOVA `sendto`/`recvfrom`.
> Until full NAT traversal, peers behind symmetric NATs or strict
> firewalls cannot reach each other directly. R26E's relay closes
> that gap: when peer A wants to send to peer B but the direct dial
> fails, A picks a common-reachable peer C, sends RELAY\_REQ to C,
> C verifies it can reach B + forwards as RELAY\_DATA with
> via=C, from=A annotations. B records the relayed payload + the
> via annotation so diagnostics confirm the A->C->B path; A caches
> (target=B, via=C) so the second send to B short-circuits straight
> to the relay path. The wire piggybacks on the existing R18E
> plaintext v1 gossip listener (HELLO/OK handshake reused; three new
> message types RELAY\_REQ / RELAY\_DATA / RELAY\_ACK additive to
> the existing PING/MEMBER/DELTA/ATOM/DQUERY/ATTESTATION/SNAP\_FETCH/
> RULE/DRFETCH/DERIVATION/EXTADDR set). Public API:
> `relay_init(gossip_state) -> relay_state`,
> `relay_send(relay, target, payload) -> 1 ok | 0 error`
> (auto-routes: direct first, falls back to relay),
> `relay_handle_request(relay, line) -> 1 forwarded` (peer-relay
> dispatch), `relay_chosen_via(relay, target) -> peer_addr | -1`
> (cache diagnostics), `relay_drain_inbound(relay) -> count` (called
> per tick to process inbound queues populated by gossip dispatchers).
> Honest scope: TCP-based relay over pre-known mesh peers; any alive
> peer can serve as relay. Noise-XK wrapping of the relay segments is
> still R26E.2 follow-up; STUN-like relay discovery shipped as R27B
> (see below). Verification: 61 unit assertions in
> `tests/unit/test_gossip_relay.nova` (wire codec round-trips, parse
> rejection on bad shapes, intermediate selection, cache idempotence,
> received-queue annotations); 13 integration assertions in
> `tests/integration/scenario_vvvv_gossip_relay.sh` (3-soul A->C->B
> mesh, test hook simulates partition without iptables, asserts
> via=ADDR\_C from=ADDR\_A annotation round-trips, cache hit on
> second send).
>
> R27C (R26E.2 follow-up) closes the second-to-last hole in the R26E.2
> list: end-to-end Noise-XK wrap around the R26E relay payload. The
> base R26E relay forwards plaintext bytes through the intermediary
> peer C -- C can read AND tamper with every payload it forwards.
> New module `src/federation/gossip_relay_secure.nova` (~330 lines)
> layers a Noise-XK AEAD frame on top: A and B pre-share a post-Split
> nxk_state (out-of-band or via R7C kg\_sync v3 handshake) with the
> two transport keys k\_init\_to\_resp + k\_resp\_to\_init and per-
> direction monotonic 64-bit nonce counters. A nxk\_seals the
> plaintext under its k\_init\_to\_resp; the resulting binary frame
> `[4B BE len || ct || 16B Poly1305 tag]` is hex-encoded for transit
> over the R18E line-based gossip wire and handed to R26E
> `relay_send`. C forwards opaque hex (no key, no decrypt). B's
> `srl_drain_relay_recv` walks the underlying relay's received-queue
> from a monotonic cursor, hex-decodes, nxk\_opens under its
> responder role (which picks k\_init\_to\_resp on the recv side via
> R7C's `_nxk_role_recv_picks(responder)`), and pushes the plaintext
> onto a per-record `[from, pt_buf, pt_n]` srl recv queue. Any
> tampered byte anywhere in transit yields a Poly1305 tag mismatch
> on B, the frame is dropped, decrypt\_failed bumps; the bad bytes
> never reach the recv queue. Public API:
> `srl_init(relay_state) -> srl_state`,
> `srl_register_peer_session(srl, peer_id, nxk_state, role) -> 1 ok`
> (pre-register the post-Split nxk\_state with the role THIS soul
> played in the Noise XK handshake -- INITIATOR or RESPONDER),
> `srl_send_secure(srl, target, pt_buf, pt_n) -> 1 ok | 0 error`
> (refuses to send when no session for target -- a missing session
> is a configuration error, not a silent fallthrough to plaintext
> through the relay), `srl_drain_relay_recv(srl) -> count` (per-
> tick drain that decrypts inbound + enqueues plaintext),
> `srl_recv_secure(srl)` (drain-and-clear the plaintext recv
> queue), inspectors `srl_received_at` / `srl_received_from` /
> `srl_received_pt_buf` / `srl_received_pt_n` /
> `srl_received_pt_str`, helpers `srl_str_to_buf` /
> `srl_buf_to_str`, stats `srl_stats_sent` / `_delivered` /
> `_decrypt_failed` / `_no_session`, status line `srl_stats_line`.
> The R26E `gossip_relay.nova` module is UNCHANGED -- srl is a leaf
> above it. The R7C `noise_xk.nova` module is UNCHANGED -- srl
> calls `nxk_seal` / `nxk_open` + role constants. Honest scope: hex
> wire doubles per-frame on-the-wire size (acceptable for control-
> plane traffic; bulk transfer would need a binary-clean RELAY\_DATA
> variant); session-key bootstrap (the post-Split state) is the
> caller's responsibility; per-message ratchet and group sessions
> are R27C.2 follow-ups. Verification: 44 unit assertions in
> `tests/unit/test_relay_secure.nova` (init zero-state, session
> registration + idempotent rekey, send refuses without session,
> round-trip wrap/unwrap, tampered ciphertext rejected, wrong
> peer's session decrypt fails, drain drops unpaired from-peer,
> recv\_secure drain-and-clear, buf<->str round-trip, stats line);
> 11 integration assertions in
> `tests/integration/scenario_xxxx_relay_secure.sh` (letter `xxxx`
> free; vvvv = R26E, wwww = R27B). 3-soul mesh A/B/C; A + B
> pre-share Noise-XK session keys (forged via `_srl_test_forge_nxk`
> to skip the ~5-15s real handshake; the seal/open AEAD codepath is
> exercised on real `nxk_seal` / `nxk_open`). A calls
> `srl_send_secure` twice; C MITM-tampers the second forwarded hex
> payload by flipping one nibble. Asserts NOVA pre-flight + 3 souls
> compile + mid-flight liveness, A's secure send returned 1, A's
> underlying relay routed via=C, C forwarded both wrapped frames,
> C's srl delivered=0 (no session -- blind), C explicitly attempts
> decrypt with a stranger session and ALL 2 attempts fail
> (peek\_attempts=2, peek\_fail=2), B's srl delivered=1 (the clean
> first frame), B's recv\[0\] plaintext exactly equals the
> originator's input string (E2E round-trip confirmed through an
> unreading relay), B's decrypt\_failed >= 1 (the tampered second
> frame was rejected and dropped before reaching the recv queue).
> All federation tests stay green: gossip\_relay 61, gossip 34,
> gossip\_noise 44, noise\_xk 44.
>
> R27C.2 (R28B follow-up) closes the documented hex-overhead hole
> in R27C: extends `src/federation/gossip_relay_secure.nova` with a
> bulk binary path so a 10KB payload moves at half the wire bytes.
> New wire prefix `RELAY_BIN <req_id> <target> <via> <from>
> <total_len>\n[total_len raw binary bytes]`; the gossip
> dispatcher in `gossip.nova` recognises the prefix, drains the
> binary tail via `_gnoise_recv_exact` (the same helper R21E uses
> for handshake framing), and either pushes a terminal record onto
> the srl's pinned binary inbound queue or forwards to the next
> hop. New API:  `srl_send_secure_binary(srl, target, pt_buf,
> pt_n)`, `srl_send_secure_auto(...)` (auto-routes hex vs binary on
> a 1024-byte ciphertext threshold so callers do not have to think
> about it), `srl_drain_relay_recv_binary(srl)`, `srl_drain_all`
> convenience drain, `srl_bin_format_header / _parse_header` test
> helpers, `srl_inject_binary_record` (unit-test bypass for the
> socket). Wiring on `gossip.nova` side: `GOSSIP_RELAY_BIN_PREFIX`,
> `GOSSIP_S_SRL_STATE`, `gossip_set_srl_state`,
> `_gossip_serve_relay_bin` dispatcher; parser branches in the
> plaintext kg-less and kg-aware `gossip_handle_conn` variants.
> Honest scope: binary path not wired to the R21E noise-wrapped
> transport (the srl AEAD wrap is sufficient confidentiality for
> bulk frames; doubling the encryption costs CPU for no security
> gain); threshold is a constant (1024 bytes); same
> per-frame routing metadata exposed (target / via / from in the
> header line). Verification: 51 unit assertions in
> `tests/unit/test_relay_secure_binary.nova` (header round-trip,
> send refuses without session, full inject + drain happy path,
> tampered AEAD body rejected, 5KB + 10KB byte-pattern
> round-trips, wire-size win observed) + 10 integration
> assertions in `tests/integration/scenario_zzzz_relay_binary.sh`
> (3-soul A->C->B mesh, 10KB binary frame routed through C, C's
> gossip bin_fwd=2, B's gossip bin_rx=2, B's srl bin_delivered=1,
> recv\[0\] 10240-byte plaintext matches the originator's
> deterministic byte pattern, tamper detection bin_decrypt_fail=1
> on a single-byte flip, binary wire-size = 0.50x hex wire-size
> on the 10KB payload). R27C scenario_xxxx still passes 11/11
> (the hex path is unchanged); 219 / 219 unit tests pass.
>
> R27B (R26E.2 follow-up) extends `src/federation/gossip_relay.nova`
> with NAT-type-aware ranked relay selection. The base R26E picker
> walked alive peers in gossip-table order and returned the first
> non-target non-self non-unreachable candidate -- ignoring observed
> NAT topology. R27B ranks candidates by R23E NAT type (open=4,
> cone=3, unknown=2, symmetric=1, blocked=0; blocked peers are
> skipped entirely rather than ranked last). Tie-break is least-
> recently-used (LRU): two peers with the same NAT rank rotate
> across consecutive calls so load spreads. Public API:
> `relay_set_peer_nat_type(state, peer, type) -> 1` (souls feed
> from R23E `nat_detect_type` results),
> `relay_get_peer_nat_type(state, peer) -> str` (defaults to
> "unknown" for unprofiled peers),
> `relay_rank_candidates(state, target) -> list` (sorted
> best->worst), `relay_choose_candidate_ranked(state, target) ->
> peer_addr | -1` (top of rank list; bumps LRU on selection),
> `relay_mark_relay_failed(state, peer) -> removed_count`
> (invalidates cache entries pointing at a failed relay). The
> ranked picker is OPT-IN via `CE_RELAY_RANK_NAT=on` -- when set,
> `relay_send`'s intermediate-selection step dispatches to the
> ranked picker; otherwise the legacy first-alive picker runs (so
> existing call sites see no behaviour change). Verification: 42
> unit assertions in `tests/unit/test_relay_ranking.nova`
> (NAT-rank table, registry round-trip, the brief's headline
> `[open, cone, symmetric] -> [open, cone, symmetric]`, unknown
> placement between cone and symmetric, blocked filtering, LRU
> rotation across 3 cone peers, NAT-rank dominates LRU, empty pool
> returns -1, all-blocked returns -1, target/self/unreachable
> exclusion, cache invalidation on failure) and 11 integration
> assertions in `tests/integration/scenario_wwww_relay_rank.sh`
> (single-driver 4-peer mock mesh: 1 open + 1 cone + 1 symmetric +
> 1 blocked; asserts ranking + LRU + back-compat + dispatch
> integration). R22F.2 extends `src/io/transducers/audio_pitch.nova` (R10F +
> R11B's file) with a harmonicity-driven auto-switch between R10F
> autocorrelation and R11B YIN. R22F (audio_melody) chose R10F by default
> because R11B YIN's octave-down anti-snap subharmonic-collapses pure sines;
> but for harmonic-rich speech / instrument content R11B YIN avoids the
> formant snap that R10F suffers. R22F.2 picks per frame: a single-frame
> STFT magnitude spectrum is computed via R16E, gated on spectral
> peakiness (max_bin / avg_bin >= 5x to reject broadband noise), then the
> count of DISTINCT prominent peaks (above 30% of the dominant, with
> adjacent-bin leakage neighbours merged) drives the harmonicity score
> (350 milli * num_distinct, capped at 1000). Above
> PITCH_HARMONIC_THRESHOLD_MILLI (600 default) -> YIN; below -> R10F.
> Pure 200 Hz sine scores 350 (one peak after leakage merging) -> AC.
> Harmonic 200 Hz with 2nd + 3rd harmonics scores 1000 -> YIN. Klatt /ae/
> vowel (F1 + F2 formants) scores 700 -> YIN. White noise gates to 0 ->
> AC (autocorrelation then marks it unvoiced). Public API:
> `pitch_harmonicity_score(pcm_frame, sample_rate) -> int_milli`,
> `pitch_estimate_frame_auto(pcm_frame, sample_rate) -> [f0_centihz,
> voicing_milli, method_used]`, `pitch_track_auto(pcm_buffer, sample_rate)
> -> list[[f0, voicing, method]]`, plus `pitch_auto_method_count(contour,
> method)` and the method-label accessors `pitch_method_autocorr() = 0`,
> `pitch_method_yin() = 1`, `pitch_method_none() = 2`. Verification: 31
> unit assertions in `tests/unit/test_pitch_auto.nova` (NEW; constants +
> accessors, harmonicity_score on pure sine / harmonic / noise / silence
> / Klatt /ae/ / short buffer, pitch_estimate_frame_auto routing across
> all 5 fixtures, pitch_track_auto on harmonic-all-YIN + mixed sine-and-
> harmonic + short input, pitch_result_method accessor, method_count on
> empty contour). 11 integration assertions in
> `tests/integration/scenario_qqqq_pitch_auto.sh` (NEW; pure sine: every
> frame routes to AC, F0 ~ 200 Hz; harmonic-rich: majority routes to YIN,
> F0 ~ 200 Hz; mixed sine + Klatt /ae/ + harmonic + silence: both AC and
> YIN frames present in same contour; JFK natural-speech sample: 311/366
> frames routed to YIN (85% majority), mean F0 178.57 Hz lies in plausible
> voice band, much lower than R10F's standalone formant-snap ~220 Hz).
> All prior audio suites stay green (R6E Klatt 209, R7F VAD 86, R8B/R10B
> STT 28, R10F pitch 52, R11B YIN 35, R12D PSOLA, R13D voice clone, R14E
> DSP 34, R16E STFT 49, R17B MFCC 41, R18C wakeword, R19D speaker_id,
> R21C TTS 68, R22F melody 40). Chat: `/pitch_auto <wav>` admin command
> available via `pitch_run_auto_command` (not yet wired into the chat
> dispatch table; reserved for an optional +1 admin line).
>
> R25B.6 closes R31F's deferred multi-kind ambiguity gap. A new
> classifier output `VC_FOLLOWUP_CLARIFY` (the SIXTH class) fires
> when the more-cue path's remainder names 2+ known kinds (e.g.
> "more facts and rules" after CONCEPT). The dispatcher emits a
> "Did you mean RULE or FACT atoms?" turn, stashes the candidate
> kinds in a new session slot (`pending_clarify_kinds`), and
> parses the NEXT user turn as a kind-selector FIRST. Bare kind
> names ("RULE"), morphology-routed phrases ("the rules"), and the
> "both" / "either" / "all" -> first-match shortcut all resolve to
> a chosen kind which is then dispatched as KIND_PIVOT (prior
> template against new kind, LIMIT reset). After 2 failed
> resolution turns we give up: emit an apologetic message and
> dispatch first-match KIND_PIVOT so the operator still gets a
> usable answer. Env opt-out `CE_VOICE_NO_CLARIFY=1` preserves
> R31F's deterministic "first kind wins" behaviour byte-identically.
> New public probes: `vc_followup_clarify()`,
> `voice_followup_clarify_candidates(session, query)`,
> `vc_resolve_clarify_selector(query, candidates)`,
> `vc_render_clarify_question(candidates)`,
> `vc_clarify_suppressed_by_env()`, plus session accessors
> `vc_session_pending_clarify_kinds`, `_template`, `_attempts`,
> `_raw`, `vc_session_is_pending_clarify`. Honest design caveat:
> the clarify-attempt counter persists across non-explicit topic
> shifts (a non-resolution reply that names a third unrelated kind
> bumps the counter rather than restarting the ambiguity budget;
> the explicit "actually" / "never mind" markers DO reset the
> session and cancel pending state). "both" shipped as
> first-candidate-wins, rejecting the multi-dispatch shape that
> would have touched every public API. Verification: +40 assertions
> across +25 new test functions (test_voice_dialog now ~207 total),
> 166 of the 167 prior assertions pass byte-identical, 1 prior
> assertion RELABELED from `vc_followup_kind_pivot()` to
> `vc_followup_clarify()` (the multi-kind classifier label; its
> companion target-probe `= FACT` assertion is unchanged).
>
> R25B.5 closes R30F's deferred kind-pivot routing gap. A new
> classifier output `VC_FOLLOWUP_KIND_PIVOT` (alongside CONTINUE /
> PIVOT / ANAPHORA / NONE) fires when the more-cue path's remainder
> NAMES a known R15D kind (case-insensitive after `_vd_stem`
> morphology) different from the prior turn's kind. The explicit
> "what about KIND" / "how about KIND" path also routes through
> KIND_PIVOT when the named kind differs from the prior. The
> handler in `vc_session_turn` dispatches the prior template
> (LIST_ALL by default) against the new kind via the existing
> `_vd_pivot_turn`, RESETTING the LIMIT to the baseline 10 (no
> escalation -- this is a kind shift, not a "more rows" request).
> New public probe `voice_followup_kind_pivot_target(session,
> query) -> string` returns the target kind name on KIND_PIVOT
> inputs ("" otherwise). THE R29C/R30F-documented headline case
> ("tell me more about that atom in the rule engine" after
> `list all FACT`) is now correctly classified as KIND_PIVOT and
> dispatched as LIST_ALL on RULE. Honest design caveat: multi-kind
> ambiguous remainders ("more facts and rules" after CONCEPT)
> return the FIRST match in tokeniser order; the multi-turn
> do-over loop is the safety net. Verification: +20 assertions
> (test_voice_dialog now 167 total), 141 of the 147 prior
> assertions pass byte-identical, 6 PIVOT->KIND_PIVOT relabels
> (all on inputs R25B.5 explicitly captures as kind-pivots; no
> dispatch/end-state assertion was changed).
>
> R25B.4 closes R25B.3's two documented failure modes: (a) kind-weighted
> Jaccard `(2*|kind_matches| + |other_matches|) / (2*|kind_terms| +
> |other_terms|)` lifts borderline kind-naming remainders to CONTINUE
> even when the uniform Jaccard rounds below the 0.2 threshold, and
> (b) an English s-suffix morphology pass (`_vd_stem`) normalises
> trailing-s plurals on the way into the tokeniser so "facts" matches
> "fact" / "rules" matches "rule" / "entities" matches "entity"
> (with standard quirks: length-<4 / -ss / -us / -is / -as / -os
> tails preserved; -ies->-y for length>=5). New public probes
> `vc_stem(tok)` and `vc_weighted_score(prior_other, prior_kind_stem,
> now)`. R25B.3 behaviour is byte-identical when the uniform Jaccard
> already says CONTINUE; the new weighted pass only fires on
> borderline misses. HONEST: the R29C-documented "tell me more about
> that atom in the rule engine" after `list all FACT` was STILL
> PIVOT under R25B.4 because the remainder named a different known
> kind (rule); the kind-pivot routing pass through `_vd_known_kind`
> closing that residual case is now R25B.5 (see above).
> Verification: +48 assertions (test_voice_dialog now 147 total),
> all 99 R25B.3 assertions still byte-identical, brief's 5+ new
> classifier fixtures correctly classified.
>
> R25B.3 extends R25B.2's dialog manager with topic-shift detection:
> a content-word Jaccard heuristic distinguishes "tell me more"
> continuations from "tell me more about cats" PIVOTs. New public
> classifier `voice_followup_classify(session, query) -> i32` returns
> one of `VC_FOLLOWUP_NONE` / `_CONTINUE` / `_PIVOT` / `_ANAPHORA`;
> anaphora keeps priority so "describe the first one" still resolves
> to `last_ids[0]`. Stopword stripping covers cue words, R25B template
> keywords, pronouns, determiners, ordinals, common verbs of saying;
> Jaccard threshold 0.2 (encoded as 2/10 in NOVA integer arithmetic).
> When a more-cue with unrelated remainder fires, the session is
> reset and the remainder is re-parsed fresh; history STILL records
> the pivot turn even on UNKNOWN parse so the operator sees the
> shift. R25B.2 behaviour is byte-identical for non-pivot transcripts
> -- the existing 44-assertion R28D fixture passes unchanged.
> Verification: +55 assertions (test_voice_dialog now 99 total),
> brief's 4 fixtures classified 4/4 correctly, full unit suite 219/219.
>
> R25B.2 adds `examples/voice_dialog.nova` — the multi-turn cousin of
> R25B's single-turn `/converse`. A session object accumulates the last
> 5 turns + most recent template / kind / entity-id list across calls;
> a follow-up parser layer in front of the R25B parser recognises
> `tell me more` (escalates LIST_ALL LIMIT and re-runs on prior kind),
> `the second one` / `the third one` / `the last one` (anaphora to
> `last_ids[N]`), `describe it` / `what is it` / `tell me about him`
> (anaphora to `last_ids[0]`), `what about Y` / `and Y` (pivots prior
> template onto new kind), and `actually X` / `never mind` /
> `change subject X` (topic-shift detection resets the session and
> parses the remainder fresh). R25B's public API is unchanged —
> single-turn callers see byte-identical behaviour. Public API:
> `vc_session_new() -> session_t`, `vc_session_turn(kg, session,
> question_text) -> [response_text, session]`, `vc_session_history(
> session) -> list[turn_t]`, `vc_session_reset(session) -> 1` (mutates
> in place), plus turn + session accessors. History caps at 5 turns
> (FIFO eviction; `turn_count` stays monotonic). Chat: `/dialog <wav>`
> admin command (2-line wiring: import + dispatch); session persists
> across calls; `/dialog reset` clears it. Verification: 44 unit
> assertions in `tests/unit/test_voice_dialog.nova` (NEW; session
> bookkeeping, R25B parity, "tell me more" + LIMIT escalation,
> anaphora "it" + ordinals + chain across WHAT_IS, "what about Y"
> pivot, topic shift with + without remainder, history cap at 5 after
> 7 turns) + 13 integration assertions in
> `tests/integration/scenario_aaaaa_dialog.sh` (NEW; 5-turn fixture
> exercises the full follow-up state machine, then chat `/dialog
> reset` path). Full unit suite: 219/219 pass; all R25B tests stay
> green (27 unit + 20 integration). Honest scope (R25B.4+ deferred):
> real label lookup (returns "atom has id 42" not "atom labelled
> foo"), cross-pronoun gender/number tracking, conversational repair
> ("no, the OTHER one"), backchannel handling. (R25B.3 handles
> fuzzy intent matching / topic-shift detection -- see paragraph
> above.)
>
> R25B adds `examples/voice_conversation.nova` — the end-to-end voice
> conversation demo that threads the existing audio + cognition legs
> into a single tangible pipeline. Speak a question into a WAV, get a
> spoken answer from the knowledge graph: STT (R8B whisper.cpp or R10B
> Vosk via `stt_seam.nova`) decodes the WAV; a rule-based question
> parser maps three English templates ("what is X" / "how many X" /
> "list all X") to SPARQL strings; R15D's `kg_query_compile_and_run`
> executes against the live KG; a result-to-text formatter composes an
> English sentence ("There are 5 FACT atoms." / "No FACT atoms found."
> / "Found 3 FACT atoms: ids 0, 1, 2."); R21C TTS synthesises the
> reply to a response WAV. No LLM in the loop — just integer DSP +
> rule-based parsing + R15D/R16F/R17E mini-SPARQL. Public API:
> `vc_handle_question(kg, wav_path) -> [response_text,
> response_wav_path]`, `vc_parse_question(text) -> [tpl_id, kind]`,
> `vc_build_sparql(parsed) -> sparql_string`, `vc_format_result(parsed,
> bindings) -> sentence_string`, plus template-id accessors
> `vc_template_what_is() = 1`, `vc_template_how_many() = 2`,
> `vc_template_list_all() = 3`, `vc_template_unknown() = 0`.
> Recognised kind tokens: FACT / CONCEPT / RELATION / SKILL / LANG /
> RULE (the R15D dictionary). Trailing punctuation is stripped; case
> is insensitive on the leading keyword. Verification: 20 unit
> assertions in `tests/unit/test_voice_conversation.nova` (NEW;
> template recognition + casing + tolerance + graceful fallback,
> SPARQL builder exact-string match on each template, formatter
> stub-binding coverage including the "There are 5 FACT atoms."
> sentence per brief mandate). 20 integration assertions in
> `tests/integration/scenario_nnnn_voice_conversation.sh` (NEW; letter
> `nnnn` free; stand-alone driver exercises parser/SPARQL/formatter,
> then `/converse` round-trip from `/say` synthesised WAV through STT
> + KG + TTS; the end-to-end STT leg gracefully informational-skips
> when `/usr/local/bin/whisper-main` is missing). Honest scope: R25B
> is the structural pipeline + 3 question templates; R25B.2 deferred
> list covers conversation state, multi-turn dialogue, STT error
> correction, ambiguity resolution, prosody, multi-template stitching,
> and streaming audio. Chat: `/converse <wav>` admin command wired
> into `examples/crossengin_chat.nova` (1 import + 1 dispatch + 1
> help line). Module count: +1 (in examples/ not src/).
>
> R23C adds `src/federation/snapshot_replication.nova` — the
> bytes-on-the-wire half of federation snapshot durability. R13F shipped
> incremental snapshot deltas; R20F shipped gossip-relayed signed snapshot
> attestations ("at ts T I sealed root R"). R23C closes the gap: when peer
> B's gossip handler verifies an inbound ATTESTATION it also pokes
> `sr_observe_attestation`, which records the root in a known-roots
> table; the daemon periodically calls `gossip_drive_snap_fetches` which
> walks the pending entries and dials each peer with `SNAP_FETCH
> <root_hex>`. The originator replies with the snapshot bytes framed as
> `SNAP_DATA <line>` per text line, terminated by `SNAP_END`. The
> receiver assembles the body, verifies (header, end-line, meta.merkle_root
> equals the signed root), and stores the bytes in a local replica
> table; from that point on peer B can ALSO serve the same root if peer
> C asks, giving the federation O(log N) snapshot-durability fan-out
> without a coordinator. Tamper rejection: a snapshot whose
> meta.merkle_root differs from the signed root is dropped (verify_fail
> counter advances, replica table unchanged). Defense-in-depth: the LOAD
> path (`snap_load_with_deltas` + `CE_SNAPSHOT_VERIFY_MERKLE=1`) still
> runs per-atom Merkle re-derivation, catching atom-level tampering that
> left the meta line untouched. Public API: `sr_init`,
> `sr_observe_attestation`, `sr_fetch_pending`, `sr_local_snapshots`,
> `sr_serve_snap_request`, `sr_observe_snap_response`,
> `sr_register_local`, plus diagnostics (`sr_status_line`,
> `sr_pending_fetch_tasks`, `sr_known_roots`, `sr_replica_lines`,
> `sr_have_root`) and gossip hooks (`gossip_set_sr_state`,
> `gossip_send_snap_fetch`, `gossip_drive_snap_fetches`,
> `gossip_sr_status_line`). Verification: 73 unit assertions in
> `tests/unit/test_snapshot_replication.nova` (NEW; sr_init shape,
> observe attestation registration + dedupe, register_local idempotence,
> replica serve hit/miss, observe_snap_response verify+store on legit
> bytes, REJECT on (tampered, garbage, truncated, unknown-root) bytes,
> already-have-root short-circuit, wire codec round-trip, status line
> format). 11 integration assertions in
> `tests/integration/scenario_mmmm_snap_replication.sh` (NEW; 2-soul
> mesh; both souls register their own snapshot, B's known-roots /
> replica table grow when A's attestation arrives, tamper-injected
> snapshot rejected, /snap_replicas chat dispatch works). All prior
> federation suites (R18E gossip, R19E leader, R20E distributed_query,
> R20F snapshot attestation, R21B distributed_rules, R21E
> gossip_noise) remain green. Chat: `/snap_replicas` info-line
> dispatch wired into `examples/crossengin_chat.nova`.
> R23E adds `src/federation/nat_traversal.nova` — a STUN-like
> external address discovery + gossip-piggyback advertisement layer for
> federation across NATs. R18E shipped the SWIM gossip mesh assuming
> direct reachability; real-world peers behind home-router / mobile /
> corporate NATs can only OUT-connect, so they need an external way to
> learn their public addr and advertise it. R23E ships the canonical
> STUN flow on TCP: `nat_query_stun(addr)` connects to any well-connected
> peer (any CE soul with a publicly reachable port can serve
> `STUN_REQUEST`) and reads back `EXTERNAL ip:port`. The server side
> learns the dialer's external addr via the kernel's
> `accept_conn(fd, sa_buf, sa_len_buf)` sockaddr_in fill.
> `nat_advertise(gossip_state, nat_state, ext_addr)` broadcasts an
> `EXTADDR <internal> <external>` line to every alive gossip peer via
> the SWIM connection; the receiver's gossip parser dispatches into
> nat_state's peer-ext table. NAT-type heuristic
> (`nat_detect_type_from_replies`) classifies "open" / "cone" /
> "symmetric" / "blocked" from two STUN responses. UDP hole-punching
> is documented but stubbed (R23E.2 — requires NOVA `sendto/recvfrom`,
> not yet exposed by the compiler). Public API: `nat_init`,
> `nat_query_stun`, `nat_advertise`, `nat_detect_type`,
> `nat_local_addrs`, `nat_peer_external_addrs`, `nat_set_external`,
> `nat_get_external`, `nat_hole_punch` (stub), `nat_status_line`, plus
> wire helpers `nat_parse_stun_response`, `nat_format_stun_response`,
> `nat_extract_peer_addr`, `nat_serve_stun_conn_sa`,
> `nat_record_inbound_extaddr`, `nat_serve_stun_one_shot`.
> Verification: 53 unit assertions in `tests/unit/test_nat_traversal.nova`
> (NEW; parse + format round-trip, sockaddr_in extraction, peer table
> set / get / update, local-addrs enumeration, type heuristic on cone /
> symmetric / open / blocked / malformed inputs, hole-punch stub
> bumps counter + returns 0); 12 integration assertions in
> `tests/integration/scenario_oooo_nat_traversal.sh` (NEW; 2-soul mesh
> with A as STUN-like rendezvous + B as querier-advertiser). All prior
> federation suites (R18E gossip, R19E leader election, R20E
> distributed_query, R20F snapshot attestation, R21B distributed_rules,
> R21E gossip_noise, R23C snapshot replication) remain green. Chat:
> `/nat` info-line dispatch wired into `examples/crossengin_chat.nova`.
> R23D adds `src/io/transducers/image_tracker.nova` — image
> object tracking via per-track Kalman filter (predict + update with
> per-coordinate variance) plus greedy minimum-L2 Hungarian assignment
> over per-frame detections from R15C HOG sliding-window or R16D Haar
> face detectors. State is [x, y, vx, vy, w, h] with positions in
> milli-pixels for sub-pixel accuracy in the integer domain. Per
> frame: predict pushes position forward by velocity; greedy assignment
> matches detections to predicted tracks below a 50-pixel L2 cap;
> Kalman update blends prediction with observation via gain = var /
> (var + R); unmatched detections spawn probational tracks; unmatched
> tracks age out to "lost" after 5 consecutive misses; matched
> probational tracks promote to "confirmed" after 5 hits. Public
> API: `tracker_new() -> tracker_t`, `tracker_step(tracker,
> detections, frame_idx) -> tracker`, `tracker_active_tracks(tracker)
> -> list[track_t]`, `tracker_confirmed_tracks(tracker)`,
> `tracker_all_tracks(tracker)`, `tracker_track_at(tracker,
> track_id) -> track_t | 0`, plus per-track accessors `track_state(t)
> -> [x_milli, y_milli, vx_milli, vy_milli, w, h]`, `track_id`,
> `track_age`, `track_status`, `track_hits`, `track_missed`,
> `track_x_px`, `track_y_px`, and `track_predict(track)` for the
> Kalman predict step in isolation. Verification: 40 unit assertions
> in `tests/unit/test_image_tracker.nova` (NEW; constants, single
> detection -> probational track, 5 consecutive frames -> confirmed,
> 5 moving frames -> velocity (+vx, +vy) with correct sign in
> [2000, 6000] milli/frame, detection disappears for 5 frames ->
> lost, two parallel tracks correctly associated across 6 frames,
> crossing-tracks scenario preserves identity via greedy assignment,
> empty detections -> no spawn, Kalman predict advances position
> by exactly +vx +vy, accessor and detection-helper shape checks).
> 13 integration assertions in
> `tests/integration/scenario_mmmm_tracker.sh` (NEW; bash driver
> writes a 5-frame 40x40 PGM fixture with a bright 6x6 square
> moving from (10,10) to (30,30) at +5/+5 per frame and a
> 10-frame lost fixture; asserts `/track` scans 5 frames, reports
> 1 confirmed track, velocity ~ (5000, 5000) milli/frame (actual
> ~4806), final position near (30, 30) (actual (29, 29)); lost
> fixture (5 moving + 5 black) marks track lost; `/track` with no
> arg -> usage; missing dir -> graceful FAILED; `/help` advertises
> /track as R23D). Existing CV suites stay green (R15C HOG detector
> 32, R16D face_detect 36, R17D LBP 45, R18D face_recognize 48,
> R21D HOG integral 42, R22A detector integral 22, R22D panorama
> 59 checks). Chat: `/track <video_dir>` admin command wired
> into `examples/crossengin_chat.nova`. Module count: +1.
> R24F adds `src/io/transducers/video_smooth.nova` — video temporal
> smoothing on top of R23D. Given a sequence of per-frame detection
> results (possibly noisy / missing / false-positive), produces a
> temporally-smoothed sequence of confirmed tracks with predicted
> positions for missing frames. Wraps a single shared R23D tracker
> plus a per-frame history list of `track_at_frame = [track_id,
> x_milli, y_milli, vx_milli, vy_milli, w, h, was_real]` snapshots;
> `was_real=1` when a detection matched this frame, `was_real=0`
> when only the R23D `track_predict` step ran (so the stored
> position IS the Kalman prediction). Public API: `vsmooth_init()`,
> `vsmooth_step(state, detections, frame_idx)`,
> `vsmooth_dense_field(state, num_frames) ->
> list[list[track_at_frame]]` (N frames x M tracks; missing-frame
> entries already carry the post-predict position),
> `vsmooth_track_continuity(state, track_id) -> int_milli` (1000 =
> real detection every frame the track was present; 800 = 4/5;
> 0 if track unknown), plus `vsmooth_frame_record`,
> `vsmooth_tracker`, and per-snapshot accessors `tat_track_id`,
> `tat_x_milli`, `tat_y_milli`, `tat_vx_milli`, `tat_vy_milli`,
> `tat_w`, `tat_h`, `tat_was_real`, `tat_x_px`, `tat_y_px`.
> Verification: 25 unit assertions in
> `tests/unit/test_video_smooth.nova` (NEW; init shape, 5 moving
> frames -> dense field 5 slots, 5 frames with frame 3 missing ->
> dense field still has frame-3 snapshot with `was_real=0` and
> predicted `x_px` between frame-2 and frame-4 positions, 5/5 real
> -> continuity 1000, 4/5 real -> continuity 800, two simultaneous
> tracks tracked independently with both continuity 1000 and ~70 px
> y-gap, empty step -> empty record, accessors). 11 integration
> assertions in `tests/integration/scenario_rrrr_video_smooth.sh`
> (NEW; 5-frame 40x40 PGM fixture with bright 6x6 square at (10,10)
> -> (15,15) -> ALL-BLACK -> (25,25) -> (30,30); asserts /smooth
> dense field of 5 slots, tracks_in_field=1, track #1 present=5/5
> real=4 predicted=1 continuity_milli=800; /smooth no arg -> usage;
> missing dir -> graceful FAILED; /help advertises /smooth and
> labels it R24F). Existing CV suites stay green (R23D tracker 40
> checks). Chat: `/smooth <video_dir>` admin command wired into
> `examples/crossengin_chat.nova`. Module count: +1.
> R24C adds `src/io/transducers/image_ocr.nova` — image OCR via
> character template matching. A gallery of (char, template) pairs is
> slid across the image; at each position the best-matching template
> above a threshold is emitted as a (char, x, y, score) detection;
> cross-character NMS collapses overlapping detections; survivors are
> sorted into reading order and concatenated to recover the text
> string. Score is `1000 - dist * 1000 / max_dist` where `dist` is the
> L2 sum-of-squared-differences and `max_dist = 255 * 255 * tw * th`.
> A built-in 8x8 bitmap font ships covering uppercase A-Z + digits 0-9
> (36 hand-drawn glyphs encoded as row masks). Public API:
> `ocr_template_gallery_new()`, `ocr_gallery_add_char(gallery,
> char_code, image, w, h) -> ok`, `ocr_gallery_size`,
> `ocr_recognize_text(image, w, h, gallery, threshold_milli) ->
> list[[char, x, y, score, tw, th]]`, `ocr_to_text(detections) ->
> str`, `ocr_default_gallery() -> 36-glyph 8x8 ASCII font`,
> `ocr_render_text(text, gallery) -> [image_ptr, w, h]`,
> `ocr_pgm_args(arg) -> chat admin string`. Verification: 40 unit
> assertions in `tests/unit/test_image_ocr.nova` (NEW; empty gallery,
> 5-template add, uniform-shape rule, self-match score=1000,
> noisy-match score>800 with one pixel flipped, wrong-character picks
> correct template, confidence threshold drops low-score detections,
> NMS collapses 3 overlapping same-char detections to 1, empty image
> -> 0 detections, "HELLO" round-trip rendering then OCR -> "HELLO",
> default gallery has 36 entries, 8x8 each). 10 integration
> assertions in `tests/integration/scenario_pppp_ocr.sh` (NEW;
> "HI"/"HELLO"/"ABC" synth fixtures recognized with correct
> detection counts, uniform-grey gibberish -> text="" detections=0,
> missing file -> graceful FAILED, /help advertises /ocr).
> Existing CV suites stay green. Honest scope: template-matching OCR
> works PERFECTLY for clean rendered text matching the gallery font;
> real-world text in photographs requires CNN-based OCR which CE
> can't do without a learned model. Chat: `/ocr <pgm>` admin command
> wired into `examples/crossengin_chat.nova`. Module count: +1.
> R23B adds `src/perception/lipsync.nova` — audio-vision
> lip sync detection. Given a sequence of PGM video frames + an audio WAV,
> the detector reports whether the speaker on screen is actually saying the
> words in the audio. Per-frame mouth-open score: lower-third of R16D Haar
> face box, intensity gradient between a tight central inner rectangle and
> the surrounding outer rim (open mouths have a dark oral cavity in the
> centre; closed mouths are uniform skin tone), score in milli with
> `darkness_score = (mean_outer - mean_inner) * 1000 / mean_outer`. Per-frame
> audio voicing: PCM sliced into one chunk per video frame, per-chunk energy
> + ZCR vs a per-chunk-scaled R7F VAD threshold. Pearson-style milli
> correlation between the two sequences gates a 1/0 verdict against
> `SYNC_THRESHOLD_MILLI=400`. Catches the gross failure modes R20C sensor
> fusion's identity match cannot: pre-recorded audio dubbed over silent
> video, off-camera voice with matching face on screen, sub-frame sync
> drift. Public API: `lipsync_mouth_open_score`, `lipsync_correlate`,
> `lipsync_voicing_per_frame`, `lipsync_detect(video_frames, audio_pcm,
> sample_rate) -> [sync_score_milli, is_synced_bool]`, `lipsync_pgm_args`
> (chat /lipsync entry; loads `frame_001.pgm`..`frame_NNN.pgm` from a
> directory + a WAV). Verification: 41 unit assertions in
> `tests/unit/test_lipsync.nova` (NEW; mouth-open score on synthesised open
> / closed / uniform / bright-interior / null / OOB fixtures; correlation
> on identical=1000, anti-correlated=-1000, random near zero, empty /
> length-mismatched / zero-variance / single-element SENTINEL; voicing on
> silence=all zeros, voiced PCM=some ones; lipsync_detect on matched=
> is_synced=true score=1000, mismatched=is_synced=false score=0, empty /
> null / bad-rate SENTINEL; chat format on sentinel + well-formed + null;
> public constants + accessor round-trip). 12 integration assertions in
> `tests/integration/scenario_llll_lipsync.sh` (NEW; 5-frame PGM fixture
> open/closed/open/closed/open + matched and mismatched WAVs synthesised by
> a one-off NOVA driver; matched -> is_synced=true sync_score_milli=1000;
> mismatched -> is_synced=false sync_score_milli=0; missing dir / WAV /
> args -> graceful error; threshold printed for operator interpretation).
> Honest scope: heuristic lower-third mouth ROI + intensity gradient is
> fragile on real photos (beard / teeth / side-on); R23B.2 follow-up
> swaps in a learned lip landmark localizer behind the same public API.
> All prior perception tests stay green (R20C sensor_fusion 25, R16D
> face_detect 36, R7F VAD 86, R10F pitch 52). Chat: `/lipsync DIR W.wav`
> admin command wired into `examples/crossengin_chat.nova` (1 import +
> 1 dispatch + 1 help line). Module count: +1.
> R22F adds `src/io/transducers/audio_melody.nova` — audio
> melody extraction lifting per-frame F0 estimates (R10F autocorrelation,
> R11B YIN) into a symbolic MIDI note sequence with start/end times. R10F
> + R11B answer "what is the pitch in frame i?"; R22F answers "what notes
> did the speaker / singer just produce?" and renders them in a human-
> readable string like `(melody: A4-440ms D4-220ms E4-440ms ... | 7
> notes)`. Public API: `melody_extract(pcm, sample_rate) -> list[note_t]`,
> `melody_to_text(notes) -> str`, `note_midi(note)`, `note_start_ms`,
> `note_end_ms`, `note_duration_ms`, `note_confidence`, plus helpers
> `hz_to_midi(centihz) -> int_midi` and `midi_to_note_name(midi) -> str`.
> Hz to MIDI conversion uses `midi = 12 * log2(freq_hz / 440) + 69`
> implemented with integer milli arithmetic over a 12-entry centi-Hz
> table (MIDI 21..32, exact at every A reference and within +/- 1
> centi-Hz elsewhere) and a 16-entry log2 fractional lookup. Note name
> rendering follows the standard MIDI convention (C4 = MIDI 60).
> Verification: 40 unit assertions in `tests/unit/test_audio_melody.nova`
> (NEW; constants + sentinels, Hz-to-MIDI on A4/C4/A3/A5/E4/unvoiced,
> MIDI-to-name on C4/A4/B4/C5/A0/C#4, note accessors, pure A4 sine 1s
> -> 1 note MIDI 69 with [900,1000] ms duration, pure C4 sine 500ms ->
> 1 note MIDI 60 with [420,510] ms, silence + empty + white-noise PCM
> all -> 0 notes, 3-note A4+C5+D5 sequence -> 3 notes in correct order,
> short-note < MIN_NOTE_MS rejection, melody_to_text renders empty + 3
> notes correctly). 16 integration assertions in
> `tests/integration/scenario_kkkk_melody.sh` (NEW; driver synthesises
> 4-note A4+C5+D5+A4 WAV + silent reference, asserts `/melody` reports
> 4 notes in correct order with NAME-DURms format and each duration in
> [150,250] ms; silent WAV -> "no notes detected"; missing path ->
> graceful FAILED; no-arg -> usage; `/help` advertises /melody as R22F).
> Existing audio suites stay green (R6E Klatt 209, R7F VAD 86, R8B/R10B
> STT 28, R10F pitch 52, R11B YIN 35, R12D PSOLA, R13D voice clone,
> R14E DSP 34, R16E STFT 49, R17B MFCC 41, R18C wakeword 41, R19D
> speaker_id, R21C TTS 68). Chat: `/melody <wav>` admin command wired
> into `examples/crossengin_chat.nova`. Module count: 182 (+1 from
> R22E's 181). R22E adds `src/kg/rule_explain.nova` — recursive provenance
> walks over R20B's rule engine, producing human-readable proof trees.
> R20B shipped `rule_engine_explain(engine, atom_id)` returning ONE
> level of provenance (the rule + premise atoms for a derived fact);
> R21B shipped `dr_derivation_provenance` for the federated case;
> R22E walks the chain BACKWARD: when an atom was derived from atoms
> that were themselves derived, follow the recursion to ground facts
> and assemble a complete proof tree. Public API: `explain_atom(kg,
> engine, atom_id) -> proof_tree_t`, `proof_render_text(tree,
> max_depth) -> str`, `proof_render_structured(tree) -> nested_list`,
> `proof_height(tree) -> int`, `proof_ground_facts(tree) ->
> list[atom_id]`, `proof_node_count(tree) -> int`, plus
> `explain_atom_with_depth(kg, engine, atom_id, max_depth)` for
> caller-controlled truncation. Depth cap at 50 (`EXPLAIN_MAX_DEPTH`)
> defends against pathological cycles; a per-branch visited-set
> short-circuits any reentry to a CYCLE sentinel; missing atoms
> resolve to a MISSING sentinel; depth-cap leaves render as
> TRUNCATED sentinels. For the canonical 5-link transitive ancestor
> chain (parent(0,1)..parent(4,5)) the engine derives 15 ancestors;
> the proof tree for `ancestor(0, 4)` has height 5, 8 nodes, and
> bottoms out at 4 distinct parent ground facts. Text render is the
> classic two-space indented list:
> `- atom 17 "ancestor|0|4" via ancestor (rule #1)` at the root with
> `- atom 0 "parent|0|1" GROUND` at the leaves. Verification: 54
> unit assertions in `tests/unit/test_rule_explain.nova` (NEW;
> covers ground-fact leaf, 1-step + 2-step derivations, 5-link
> transitive ancestor chain, max_depth truncation, cycle-via-dedupe
> handling, missing-atom sentinel, text + structured renderings
> with snapshot match, ground-fact deduplication, node-count
> utility, chat-engine bridge). 21 integration assertions in
> `tests/integration/scenario_jjjj_rule_explain.sh` (NEW; standalone
> driver seeds the 5-parent chain, runs the classical ancestor
> rules, walks ancestor(0, 4) and asserts height + grounds + root
> rule + text-render tokens + structured shape; ground parent fact
> is a height-1 GROUND leaf; missing atom_id resolves to MISSING;
> chat dispatch lists /explain in /help + usage on no-arg). Chat:
> `/explain <atom_id>` admin command wired into
> `examples/crossengin_chat.nova`. All prior KG suites remain green
> (R20B rule_inference 47 checks, R21B distributed_rules 42
> checks). Module count: +1.
> R22D adds `src/io/transducers/image_panorama.nova` — image-pair
> panorama stitching, the classical 4-step CV recipe (feature
> matching + RANSAC homography + warp + linear blend) consuming
> CrossEngin's existing R5C SIFT + R6D ORB matchers. Given two
> overlapping PGM images, `pano_match_features` (default ORB) emits
> correspondence pairs, `pano_ransac_homography` solves a 3x3
> homography via the Direct Linear Transform (DLT) on 4 sampled
> correspondences per iteration with inlier scoring by Chebyshev
> reprojection distance, `pano_warp` backward-warps the second image
> via the inverse homography + bilinear sampling, and `pano_blend`
> averages the overlap 50/50. Convenience wrapper `pano_stitch(a, b,
> w, h)` composes all four stages and emits PGM-P5 bytes; when
> feature matching collapses (< 4 matches, e.g. uniform images), the
> pipeline gracefully falls back to a known translation that places
> B beside A with `PANO_DEFAULT_OVERLAP_PX` (=10) overlap. All
> arithmetic is integer (milli-fixed-point homography cells; identity
> is `[1000,0,0,0,1000,0,0,0,1000]`); LCG-deterministic RANSAC
> sampler (seed 19937) yields the same H across runs given the same
> match list. Caps: max input dim 256/axis, max output dim 512/axis,
> max RANSAC iterations 500. Public API: `pano_match_features`,
> `pano_ransac_homography`, `pano_warp`, `pano_blend`, `pano_stitch`,
> `pano_pgm_args` (chat dispatch), `pano_homography_identity`,
> `pano_homography_translation`, `pano_homography_invert`,
> `pano_homography_apply`, `pano_inlier_count`, `pano_homography`
> (accessors). Verification: 18 test functions / 59 unit assertions
> in `tests/unit/test_image_panorama.nova` (NEW; identity +
> translation homography apply, invert round-trip, identity warp
> preserves image, translation warp shifts pixel, warp input
> validation, RANSAC with 4 inliers + 0 outliers recovers exact H
> within 1 px, RANSAC with 4 inliers + 4 outliers rejects outliers,
> blend 100%-A in A-only region + 50/50 in overlap + 100%-B in
> B-only region, uniform-image stitch returns valid PGM via
> fallback, checkerboard-halves stitch covers full canvas width
> with non-zero pixels at both edges). 17 integration assertions in
> `tests/integration/scenario_iiii_panorama.sh` (NEW; 36x32
> checkerboard pair fixture with 10-pixel overlap, `/pano` echoes
> dims + matches + wrote=yes + output 62x32, stitched.pgm exists +
> size 1997 bytes > 1024 + begins with P5 magic, no-arg usage
> prompt, missing-file graceful FAILED). All prior CV suites stay
> green (R5C SIFT 25, R6D ORB 34, R14D HOG 55, R15C HOG detector
> 32, R16D face_detect 36, R17D LBP 45, R21D HOG integral 42). Chat:
> `/pano LEFT RIGHT` admin command wired into
> `examples/crossengin_chat.nova`. Module count: +1.
> R22A wires R21D's HOG integral histogram into R15C's
> sliding-window object detector: `det_sliding_window` now builds the
> per-image integral planes ONCE per scale and queries every
> candidate window's per-cell histograms via four-corner rectangle
> sums on the precomputed buffer. Realizes the structural
> amortization win R21D flagged but could not deliver on a single
> isolated `hog_compute` call. Realized speedup on the 256x256 /
> 32x32 / stride 8 surface (841 candidate windows): **~2.15x
> absolute** (range 2.11x to 2.40x across 5 runs). Bit-identical
> output to the scalar path; opt-in via `CE_DETECTOR_INTEGRAL=on`.
> Verification: 22 unit assertions in
> `tests/unit/test_detector_integral.nova` (NEW; bit-identical
> detection list on positive 64x64 + negative uniform + self-match +
> 96x96 dense + per-window-descriptor identity + det_detect
> end-to-end + NMS preserved + edge cases). All prior CV suites
> stay green (R14D HOG 55, R15C HOG detector 32, R21D HOG integral
> 42, R16D face_detect 36). Bench surface extended in
> `scripts/bench_simd_production.sh` with the new R22A section
> (scalar vs integral wallclock + speedup ratio with warm-up).
> R21E adds Noise-protected gossip: every R18E gossip
> connection is now wrapped in R7C Noise XK (mutually authenticated +
> AEAD-encrypted with RFC 7919 Group 14 2048-bit DH) once both peers
> have static keypairs registered, with strict-mode plaintext refusal
> via `CE_GOSSIP_REQUIRE_NOISE=1`. PING / ACK / MEMBER / DELTA / ATOM /
> DQUERY* / ATTESTATION / RULE* / DERIVATION lines all ride the same
> `gconn` abstraction that hides plaintext-vs-noise from the per-line
> dispatch. Public API: `gossip_set_noise_keys`,
> `gossip_register_peer_pubkey`, `gossip_noise_set_strict`,
> `gossip_send_ping_gconn`, `gossip_handle_conn_kg_gconn`,
> `gossip_noise_status_line` plus three stats accessors. Verification:
> 44 unit assertions in `tests/unit/test_gossip_noise.nova` (NEW; state
> defaults, configured flag, per-peer registry round-trip + overwrite +
> unknown lookup, strict-mode toggle + env-driven default, in-process
> handshake completion + session-hash agreement + peer-static recovery,
> PING-line seal/open round-trip, MITM rejection at msg1 with wrong
> peer pubkey, strict-mode dial refusal without opening a socket, gconn
> structural accessors, status-line tokens). 12 integration assertions
> in `tests/integration/scenario_hhhh_gossip_noise.sh` (NEW; 3-soul
> Noise mesh handshake convergence + Stage 2 STRICT refusal of
> plaintext + Stage 3 MITM rejection with wrong peer pubkey). Existing
> federation suites stay green (R7C noise_xk 44 checks, R18E gossip 34
> checks, R19E leader 40 checks, R20E dquery 36 checks, R20F
> attestation 66 checks). Chat: `/gossip_noise` admin command wired
> into `examples/crossengin_chat.nova`. R21B adds `src/federation/distributed_rules.nova` —
> federated forward-chaining mini-Datalog rule inference across the R18E
> gossip mesh. R20B shipped local rule inference on a single KG; R20E
> shipped distributed SPARQL fan-out; R21B bridges them so a rule's
> premises can match facts from ANY peer's KG and derived conclusions
> can be broadcast to the entire mesh. Wire protocol adds three line
> types over the existing gossip TCP exchange: `RULE <rule_string>`
> broadcasts the rule on `dr_add_rule` so all peers ingest it on the
> next round; `DRFETCH <pred>` requests every RELATION atom matching
> the predicate from one peer (replies as `DRFACT <peer_addr> <pred>
> <arg1> <arg2> <atom_id>` lines terminated by `DREND`); `DERIVATION
> <rule_idx> <pred> <arg1> <arg2> <origin_addr> <contrib_csv>`
> broadcasts a derived fact so peers cache it locally with the
> originating peers' provenance attached. Each round: drain inbound
> RULE + DERIVATION queues, then for every rule fetch the federated
> fact set per premise (local + DRFETCH from each alive peer), run
> the cross-join, dedupe via `kg_find_atom`, broadcast DERIVATION.
> Per-atom provenance carries the head predicate name + the unique
> set of peer addresses that contributed atoms (the "(which rule,
> which peers)" answer the brief specifies). `dr_run_to_fixpoint(dr,
> kg, max_rounds)` iterates until natural fixpoint or cap. Public API:
> `dr_init(gossip, engine)`, `dr_add_rule(dr, rule_string)`,
> `dr_run_round(dr, kg)`, `dr_run_to_fixpoint(dr, kg, max_rounds)`,
> `dr_derivation_provenance(dr, atom_id)`. Verification: 42 unit
> assertions in `tests/unit/test_distributed_rules.nova` (NEW;
> bootstrap shape, single-soul-equivalent fixpoint matching R20B,
> rule broadcast on add, inbound RULE queue drained on next round,
> cross-soul join with provenance, inbound DERIVATION caching +
> dedupe, max_rounds cap, stats line, chat info-line dispatch). 15
> integration assertions in
> `tests/integration/scenario_eeee_distributed_rules.sh` (NEW; 3-soul
> mesh, partitioned parents A: parent(0,1)+parent(2,3); B: parent(1,2);
> C: parent(3,4); A originates the two ancestor rules at tick 30,
> runs dr_run_to_fixpoint at tick 60; observed convergence: **10
> ancestors derived (full C(5,2) closure), 4 rounds, 24 DRFETCH
> dispatches, `ancestor|0|4` present with cross-soul provenance
> recording 2 unique peer contributors**). Chat: `/drule_add <rule>`
> + `/drule_run` info-only dispatch wired into
> `examples/crossengin_chat.nova`. All prior federation suites (R18E
> gossip, R19E leader election, R20E distributed_query, R20F snapshot
> attestation, R21E gossip_noise) remain green; R20B rule_inference
> (47 assertions) unchanged. Module count: 174 (+1 from R20F's 173).
> R21C adds `src/io/effectors/audio_tts.nova` — the end-to-end
> text-to-speech pipeline that closes the TTS leg of the audio chain. CE
> already had speech IN (R8B whisper / R10B vosk STT) and a usable
> speech-synthesis floor (R6E Klatt with the 44-phoneme ARPAbet
> inventory); what was missing was a complete TTS pipeline that takes
> free-form English text and produces playable WAV. R21C closes that gap
> with a curated ~120-word dictionary + rule-based G2P (grapheme-to-
> phoneme) stage in front of the existing Klatt synth and a WAV writer
> behind it. Pipeline: tokenize on whitespace + punctuation -> per-word
> G2P (dictionary first, then rule fallback) -> per-phoneme R6E Klatt
> synthesis -> PCM concat with brief word-break silences -> 44-byte WAV
> header at the caller-requested sample rate -> sys_write + sys_fsync.
> Dictionary covers greetings, pronouns, function words, common verbs +
> nouns, numbers 0-10, and CrossEngin domain terms. Rule fallback
> handles silent-prefix strip (kn/wr/pn/mn/gn/ps), silent-e CVCe upgrade
> (cake -> /K EY K/), two-letter digraph greedy match (sh/th/ch/ng/ph/wh
> /ck/qu + 11 vowel digraphs), single-letter fallback (x -> /K/+/S/;
> unknown bytes -> /AX/ schwa). Output is byte-deterministic. Public
> API: `tts_g2p`, `tts_g2p_word`, `tts_g2p_marked`, `tts_tokenize`,
> `tts_synth_phonemes(phonemes, sample_rate)`,
> `tts_speak(text, sample_rate)`, `tts_save_wav(wav_bytes, path)`,
> `tts_phonemes_to_string`, `tts_dict_size()`, `tts_say_run(text)`.
> Chat: `/say <text>` admin (1 import + 1 dispatch + 1 help). 68 unit
> assertions in `tests/unit/test_audio_tts.nova` (NEW). 22 integration
> assertions in `tests/integration/scenario_ffff_tts.sh` (NEW). All
> prior audio suites remain green (R6E Klatt, R7F VAD, R8B/R10B STT,
> R10F/R11B pitch, R12D PSOLA, R13D voice clone, R14E DSP, R16E STFT,
> R17B MFCC, R18C wake-word, R19D speaker_id). Module count: +1 (new
> `src/io/effectors/audio_tts.nova`). R20B adds
> `src/kg/rule_inference.nova` — a forward-chaining
> mini-Datalog rule engine over the KG. The KG had nine READ surfaces
> (episodic recall, TF-IDF, LSH ANN, LPA + Louvain clustering, PageRank,
> mini-SPARQL queries, link prediction, temporal reasoning) but no
> DECLARATIVE INFERENCE surface: a rule engine that derives new facts
> from existing ones by iterating to fixpoint. R20B closes that gap.
> Rule surface: `RULE head(?a, ?b) <- premise1 AND premise2` where each
> premise is a binary predicate atom and the conjunction token is any
> of `AND` / `&&` / `,` / the UTF-8 wedge. Facts live as
> RELATION-kind atoms with canonical labels "pred|arg1|arg2"; the pipe
> separator is reserved from identifier tokens so it never collides
> with predicate names. Dedupe is O(1) amortised via `kg_find_atom`'s
> label hash. Forward-chaining runs to natural fixpoint (no new atoms
> derived in a pass) or to one of the runaway caps (default
> max_iterations=100, max_derived_atoms=10000). Each derivation is
> recorded in the engine's provenance table; `rule_engine_explain(
> engine, atom_id)` returns the list of `[atom_id, rule_index,
> source_atom_ids]` entries that produced the atom. Public API:
> `rule_parse(rule_string)`, `rule_engine_new()`, `rule_engine_add(
> engine, rule_string)`, `rule_engine_run(engine, kg, max_iterations)
> -> [augmented_kg, derived_count, iterations]`, `rule_engine_explain(
> engine, atom_id)`. Verification: 47 unit assertions in
> `tests/unit/test_rule_inference.nova` (NEW; covers parser shape +
> error cases for every conjunction token + arity mismatch + missing
> arrow + empty body; engine construction, single-rule single-fact
> derivation, multi-rule cooperation, transitive closure on 4-parent
> + 5-parent chains, fixpoint termination, cycle prevention via
> dedupe, provenance traceback to source atoms, max-iterations cap,
> idempotent re-run). 21 integration assertions in
> `tests/integration/scenario_aaaa_rule_inference.sh` (NEW; standalone
> driver seeds the classical 5-parent chain, runs to fixpoint, asserts
> 15 derived ancestor pairs by C(6, 2) + fixpoint in 5 iterations +
> no cap hit + cycle rule terminates + idempotency + provenance shape
> + chat wiring through the chat binary). Chat: `/rule_add <rule>` +
> `/rule_run [max_iters]` admin commands wired into
> `examples/crossengin_chat.nova`. All prior KG suites remain green
> (R6F+R8F episodic, R10C semantic search, R11F LPA + R12C Louvain,
> R13E PageRank, R15D+R16F+R17E mini-SPARQL, R18B link prediction,
> R19C temporal reasoning). Module count: 173 (+1 from R19E's 172).
> R20C adds `src/perception/sensor_fusion.nova` — the cross-modal
> binding primitive that ties independent visual + audio observations into a
> single fused atom. The vision pipeline (`io/transducers/visual_perception.nova`
> R3.1 onward; R18D LBP-gallery face recognition) and audio pipeline
> (`audio_capture.nova` + `stt_seam.nova` + R19D MFCC-gallery speaker ID) each
> perceived the world in their own modalities; before R20C there was no
> mechanism to bind a visual face observation to a temporally-coincident audio
> speech observation from the same identity. R20C closes that gap with
> temporal-window correlation (default 100ms, the McGurk-effect cross-modal
> binding window in nanoseconds = 100_000_000) + cross-modal identity matching
> (face_label == speaker_label → FUSE_BINDING_STRONG; else temporal-only
> FUSE_BINDING_WEAK; "unknown" sentinel suppressed) + joint provenance
> (`fuse_provenance(fused_atom)` returns `[image_source_atom_id,
> audio_source_atom_id]`). Public API: `fuse_observation(image_atoms,
> audio_atoms, ts_ns)`, `fuse_correlate_by_time(image_obs, audio_obs,
> window_ns)`, `fuse_correlate_by_identity(face_label, speaker_label)`,
> `fuse_provenance(fused_atom)`. Greedy 1-to-1 audio consumption (one
> audio observation matches at most one image observation per
> correlation pass). Honest scope: R20C ships the fusion PRIMITIVE; the
> live capture-stream driver (per-modality ring buffers + ring-update
> callbacks into `fuse_correlate_by_time`) is R20C.2. Demonstrated on
> synthetic streams via the `/fuse` admin chat command. Verification:
> 59 unit assertions in `tests/unit/test_sensor_fusion.nova` (NEW).
> 10 integration assertions in `tests/integration/scenario_bbbb_sensor_fusion.sh`
> (NEW). All perception suites remain green. Module count: +1 (new
> `src/perception/` directory). R20F adds
> `src/federation/snapshot_attestation.nova` — gossip-relayed signed
> snapshot attestation that lets peers PROVE to each other that they
> saved a particular Merkle root at a particular nanosecond. R15E
> already gives every snapshot a tamper-evident Merkle root; R16A
> binds it to an Ed25519 long-term key the operator holds; R18E
> gossip + R19E leader election connect peers into a federated
> mesh. R20F is the bridge: each soul periodically computes its
> current Merkle root (cached from the last snapshot save), signs
> the `(soul_id || ts_ns || merkle_root)` tuple with its long-term
> key, and broadcasts an ATTESTATION line via the gossip TCP
> exchange. Peers receive ATTESTATION; verify the signature against
> the originator's known pubkey (resolved from a per-peer table
> seeded out-of-band at federation bootstrap — the same shape R19E
> uses for `soul_id -> addr` registration, the same pubkey bytes
> R7C Noise XK negotiates for static-key auth); on accept, append
> to a per-peer attestation log. Tampered attestations (bit-flipped
> root, bit-flipped signature, wrong pubkey, mutated soul_id /
> ts_ns) are dropped — a `bad_counter` advances, the log stays
> clean. Wire shape: `ATTESTATION <soul_id> <ts_ns> <merkle_root_hex>
> <sig_hex>\n` (single line, piggyback over the existing gossip TCP
> handshake). Canonical signing pre-image: `soul_id_le64 ||
> ts_ns_le64 || root_bytes` (48 bytes fixed-width; both endpoints
> produce bit-identical bytes from the same tuple). Public API:
> `att_make(soul_id, ts_ns, root_bytes, seed, pk)`, `att_verify(att,
> pk)`, `att_store_new()`, `att_store_add(store, att)`,
> `att_store_for_peer(store, peer_id)`, `att_store_latest(store,
> peer_id)`, `att_to_wire(att)`, `att_parse_wire(line)`. Plus the
> gossip-side hooks: `gossip_set_att_store(state, store)`,
> `gossip_register_att_pubkey(state, peer_id, pk)`,
> `gossip_broadcast_attestation(state, att)`,
> `gossip_stats_att_rx(state)`, `gossip_stats_att_bad(state)`.
> Verification: 66 unit assertions in
> `tests/unit/test_snapshot_attestation.nova` (NEW; round-trip,
> bit-flipped root rejected, bit-flipped signature rejected, wrong
> pubkey rejected, mutated soul_id / ts_ns rejected, wire codec
> lossless round-trip, parse rejection of malformed inputs, store
> add + count, latest-by-ts not insertion-order, per-peer filtering,
> the 48-byte canonical pre-image byte layout pinned to a known
> vector). 14 integration assertions in
> `tests/integration/scenario_dddd_snapshot_attestation.sh` (NEW;
> spawns two souls on random local ports with their own Ed25519
> long-term keypairs registered in each other's pubkey table,
> broadcasts signed attestations via gossip, asserts the recipient's
> store carries the expected root + verifies signature; second
> stage: soul A injects a TAMPERED attestation signed with a wrong
> seed, soul B's gossip handler drops it (bad-counter advances,
> store NOT polluted); `/attest_log <peer>` smoke test of the chat
> dispatch). Chat: `/attest_log <peer_id>` admin command wired into
> `examples/crossengin_chat.nova`. All prior federation suites
> remain green (R7C Noise XK, R18E gossip, R19E leader election).
> Module count: +1. R19E adds
> `src/federation/leader_election.nova` —
> Garcia-Molina's Bully algorithm (1982, simplified for N ≤ 16
> meshes) layered on top of R18E SWIM gossip. R18E gives every soul
> a converged view of "who is alive"; R19E is the next federation
> primitive: agreement on a single coordinator for tasks needing
> linearizability (monotonic IDs, distributed event ordering,
> single-writer schemas). Each soul carries a numeric `self_id`
> (typically the hash of its R7C Noise XK static pubkey) plus a
> separate `addr -> id` map registered by the daemon at bootstrap.
> Election sequence: on startup or detected leader-DEAD, the
> initiator transitions to `LE_STATE_ELECTING`, stamps
> `election_started_ns = nanotime()`, and enqueues ELECTION to every
> alive peer with a higher ID. Higher-ID peers respond with OK and
> start own elections; the highest-ID peer times out with no OK
> received and broadcasts VICTORY. VICTORY is accepted only when
> `from_id >= self_id` (lower-ID claimants are ignored). Default
> election timeout is 2 * gossip ping interval (2000 ms). Because
> R18E gossip's wire format doesn't carry ELECTION/OK/VICTORY, the
> bully message queue is exposed via `le_drain_pending` for future
> transports; `le_election_check` resolves timeouts using
> `gossip_peer_table` as ground truth (the highest-ID non-DEAD peer
> inclusive of self is the natural winner — SUSPECT peers are
> counted as candidates to hedge SWIM's stale-LAST_SEEN false
> positives). A stability check in `le_step`'s STABLE branch yields
> the leadership to a higher-ID peer that has since reappeared
> (handles partial-view self-elections + the previously-killed-
> leader restart case). Public API:
> `le_init(gossip_state, self_id)`, `le_current_leader(state) -> id
> | -1`, `le_is_leader(state)`, `le_step(state)`,
> `le_force_election(state)`. 40 unit assertions in
> `tests/unit/test_leader_election.nova` (NEW; covers bootstrap, peer
> map, 3-soul [10, 20, 30] highest-wins, leader-death triggering
> re-election, lone-soul self-election, force-election overriding a
> stable leader, message handlers, gossip-derived deferral). ~11
> integration assertions in `tests/integration/scenario_zzz_leader.sh`
> (NEW; precompiles 3 soul drivers with IDs [10, 20, 30] on random
> ports, verifies soul C self-elects + at least one follower
> converges within 20s, kill C and observe B re-elect within 15s,
> restart C and verify no soul stuck in ELECTING). Chat: `/leader`
> dispatch + help line. All prior federation suites (R6C/R7C
> scenario_gg_noise_kg, R18E scenario_www_gossip) remain green.
> Module count: 172 (+1 from R19E, R18E count was 169).
> R18E adds `src/federation/gossip.nova` — a SWIM-style
> (Das et al. 2002) gossip protocol on top of short-lived TCP probes
> that closes R7C kg_sync v3's "N > 2 without a central hub" gap.
> Each soul maintains `[addr, last_seen_ns, suspicion_count, status]`
> per known peer; every PING_INTERVAL ms (default 1000) the soul
> picks a random alive peer, dials TCP, sends `PING <seq>
> <self_addr>`, awaits `ACK <seq>` within PING_TIMEOUT ms (default
> 500). On 3 missed PINGs the peer is marked DEAD; ACK resets
> suspicion. Each PING piggybacks 2-3 random `MEMBER <addr>
> <status>` lines so the receiver learns about peers it has not
> directly probed. Periodic `DELTA <self_addr> <last_synced_ns>`
> requests stream every atom whose `updated_ns > since_ns` as ATOM
> lines (kg_sync v2 wire format) to keep KGs converged. Listening fd
> is `O_NONBLOCK` via fcntl; client fds get
> `SO_RCVTIMEO/SO_SNDTIMEO = 500ms` via setsockopt -- without those
> the 3-soul mesh deadlocks on tick 0 when every soul tries to ping
> simultaneously. Membership merge respects the no-resurrect
> invariant: gossip claims about ALIVE cannot override a local
> suspicion > 0, so 3 missed PINGs always reach DEAD. Public API:
> `gossip_init(self_addr, bootstrap_peers)`, `gossip_step(state,
> kg)`, `gossip_peer_table(state)`, `gossip_alive_peers(state)` plus
> the helper surface exercised by the unit tests. 34 unit
> assertions in `tests/unit/test_gossip.nova` + 13 integration
> assertions in `tests/integration/scenario_www_gossip.sh` (NEW;
> precompiles 3 soul drivers, spawns the 3-process mesh, verifies
> peer-table convergence within 8s, observes DEAD-marking within 2s
> of killing a soul, confirms KG-delta propagation A → B / C). All
> prior federation suites (R6C/R7C scenario_gg_noise_kg) remain
> green. Module count: 171. R18C adds `src/io/transducers/audio_wakeword.nova` — a
> wake-word matched filter built on R17B's MFCC + R7F's VAD via
> Dynamic Time Warping ("Hey Nova", "Computer", etc.). DTW lattice
> `D[i][j] = local(input[i], reference[j]) + min(D[i-1][j],
> D[i][j-1], D[i-1][j-1])` with `D[0][0] = local(input[0],
> reference[0])` and the boundary rows / columns taking only the
> available neighbour; final distance `= D[N-1][M-1] / (N + M)`
> path-normalized. Local distance is L2² between two 13-dim MFCC
> vectors via R17B's `mfcc_l2_distance_sq` (skipping coef 0 so
> loudness doesn't dominate the spectral match). VAD interlock
> (R7F adaptive mode disabled — wake-words lead with speech, not
> silence) prevents pure-noise / silence buffers from ever firing.
> Caps: 256 frames per template / input (4 s @ 16 kHz hop=256); DTW
> lattice 256×256 = 65536 int63 cells. Public API:
> `wake_train_template[_from_pcm]`, `wake_template_save/load`,
> `wake_detect`, `wake_dtw_distance`, `wake_smooth`. New chat
> admin: `/wake_train PATH` saves the template to
> `/tmp/wakeword.template`; `/wake PATH` loads + detects, prints
> `(wake PATH: detected={true|false} distance=N milli
> (threshold=30000), end_frame=K)`. On Klatt /ay ey/ vs /ay ey/:
> distance = 0 milli² (DTW perfect alignment), detected=true. On
> /ay ey/ vs /uw ow/: distance = 202356690 milli² — 6700× safety
> margin above the 30000 default threshold — detected=false.
> Save/load is bit-identical (per-coef equality across every
> frame). 41 unit assertions
> (`tests/unit/test_audio_wakeword.nova`) + 20 integration
> assertions (`tests/integration/scenario_uuu_wakeword.sh`); all
> green. All prior audio suites (R6E Klatt, R7F VAD, R8B/R10B STT,
> R10F/R11B pitch, R12D PSOLA, R13D voice clone, R14E DSP, R16E
> STFT, R17B MFCC) remain bit-identically green. R18B adds `src/kg/link_prediction.nova` — three classical
> link-prediction scores over the KG xref graph (Common Neighbors;
> Jaccard, in milli; Adamic-Adar, in milli with integer log2 hub
> down-weight). Companion to clustering (R11F LPA + R12C Louvain) and
> centrality (R13E PageRank); answers the orthogonal "which UNFORMED
> edges should exist?" question. `lp_predict_top_k` filters out
> already-linked atoms so the result is candidate edges only;
> tie-break is ASCENDING target atom_id. On a 4-clique-minus-one
> fixture CN(0, 3) = 2, J(0, 3) = 1000 milli, AA(0, 3) = 2000 milli;
> on a triangle-with-missing-edge {0--1, 1--2} the missing 0--2 edge
> ranks top-1 by Jaccard at 1000 milli; on a hub-vs-rare fixture
> Jaccard ties candidates {1, 2} at 500 milli each (ASC tiebreak
> picks atom 1), while Adamic-Adar strictly prefers atom 2 (rare
> neighbour weight 1000 vs hub 500) — concrete demonstration that
> the two methods can rank the same query differently. Public API:
> `lp_common_neighbors`, `lp_jaccard`, `lp_adamic_adar`,
> `lp_predict_top_k`, `lp_method_parse`, `lp_method_name`. New chat
> admin: `/predict <atom_id> [top_k] [method]` (method in
> `{cn, jaccard, aa}`; default jaccard, top_k=5) prints
> `PREDICT source=X method=NAME top_k=K hits=H edges=[id=A,score=B
> ...]`. 77 unit assertions (`tests/unit/test_link_prediction.nova`)
> + 31 integration assertions
> (`tests/integration/scenario_ttt_link_prediction.sh`); all green.
> All prior KG suites (R6F+R8F episodic, R10C semantic search, R11F
> LPA, R12C Louvain, R13E PageRank, R15D/R16F/R17E mini-SPARQL)
> remain bit-identically green. R19C adds `src/kg/temporal.nova` —
> Allen's 13-relation interval algebra (Allen 1983, CACM 26(11))
> over atom `[created, updated]` timestamps. The 13 jointly-exhaustive
> pairwise-disjoint relations (before, meets, overlaps, starts,
> during, finishes, equals + their six inverses) are decided by a
> top-down comparison tree on the four endpoint comparisons; every
> pair of finite intervals matches exactly one. Public API:
> `tmp_relation(a, b) -> ALLEN_* code`, `tmp_relation_name(code)`
> / `tmp_relation_parse(name)` for round-trip,
> `tmp_relation_inverse(code)` for the symmetric pair,
> `tmp_query_relation(kg, source_id, relation_code)` for the
> "atoms in this relation to source" walk (returns ASC by id),
> `tmp_chain(kg, start_id, max_hops)` for a maximal before-chain
> picking the earliest-starting successor (ties broken by ASC id),
> `tmp_overlap_set(kg, atom_id)` for all atoms whose intervals
> share an instant with the source (includes self). New chat admin:
> `/temporal <atom_id> <relation>` (relation in `{before, after,
> meets, met_by, overlaps, overlapped_by, starts, started_by,
> during, contains, finishes, finished_by, equals}`) prints
> `TEMPORAL source=X relation=NAME hits=H ids=[A B C ...]`. On a
> 5-atom temporally-ordered fixture (`[10,20]`, `[30,40]`,
> `[50,60]`, `[70,80]`, `[90,100]`): `tmp_query_relation(0, AFTER)`
> returns `{1, 2, 3, 4}`; `tmp_query_relation(2, BEFORE)` returns
> `{0, 1}`; `tmp_chain(0, 5)` walks `{0, 1, 2, 3, 4}`. On a triadic
> overlap fixture (`[10,30]`, `[20,40]`, `[25,35]`):
> `tmp_overlap_set(0)` returns all `{0, 1, 2}`. Inverse pair check:
> `tmp_relation(A, B) == BEFORE` iff `tmp_relation(B, A) == AFTER`.
> 80 unit assertions (`tests/unit/test_kg_temporal.nova`) + 21
> integration assertions (`tests/integration/scenario_xxx_temporal.sh`);
> all green. R19D adds `src/io/transducers/audio_speaker_id.nova` — the
> voice analog of R18D's LBP-gallery face recognition. R17B shipped
> MFCC; R18C shipped DTW on a single template (wake-word matched
> filter); R18D shipped a labelled gallery + nearest-neighbour
> classifier for visual identity. R19D closes the analogous shape
> for audio: a labelled gallery of enrolled speaker MFCC
> fingerprints + a DTW NN classifier that returns the closest
> enrolled label or "unknown" when no entry passes the configured
> threshold. Per-pair scoring reuses R18C's `wake_dtw_distance` so
> the integer-only DTW math is shared (skip coef 0, path-normalize
> by N+M, length-tolerant warp). Classification: per query, run
> DTW against every alive entry; if `min_dist < threshold` return
> `[argmin_label, min_dist]`, else `["unknown", -1]`. Caps:
> `SPK_GALLERY_MAX_ENTRIES = 64`, `SPK_LABEL_MAX = 64` bytes,
> per-entry frames capped at 256 (mirrors R18C). Default threshold
> = 30000 milli² (matches R18C). Persistence is ASCII line-oriented
> (`CE_SPK_GALLERY 1` magic + `n_entries N` + per-entry metadata +
> `frame <c0> <c1> ... <c12>` lines); round-trip bit-identical for
> the 3-speaker gallery. Public API: `spk_gallery_new`,
> `spk_gallery_enroll[_from_pcm]`, `spk_gallery_recognize[_from_pcm]`,
> `spk_gallery_save`, `spk_gallery_load`, `spk_gallery_size`,
> `spk_gallery_clear`, `spk_gallery_label_at`,
> `spk_gallery_default_threshold`. New chat admins:
> `/spk_enroll LABEL PATH.wav` registers a speaker, prints
> `(spk_enroll OK label=LABEL size=N)`;
> `/spk_recognize PATH.wav` matches and prints
> `(spk_recognize matched=LABEL distance=D threshold=T)` or
> `(spk_recognize unknown distance=-1 threshold=T)`. On
> Klatt /iy ae iy/ self-match: distance = 0 (DTW perfect
> alignment). Cross-speaker (alice `/iy ae iy/` vs dave
> `/a ah a/`) lands well above the 30000 threshold, so dave
> recognized against an alice-only gallery returns "unknown".
> 53 unit assertions (`tests/unit/test_speaker_id.nova`) + 22
> integration assertions
> (`tests/integration/scenario_yyy_speaker_id.sh`); all green.
> All prior audio suites (R6E Klatt, R7F VAD, R8B/R10B STT,
> R10F/R11B pitch, R12D PSOLA, R13D voice clone, R14E DSP, R16E
> STFT, R17B MFCC, R18C wakeword) remain bit-identically green.
> R18A.2 EXTENDS `src/io/transducers/image_optical_flow.nova`
> with byte mul-acc SIMD wired into the 5 Lucas-Kanade accumulator
> sums (Σ Ix², Σ Iy², Σ IxIy, Σ IxIt, Σ IyIt) -- closes R17C's
> 0.80x ceiling at **3.69x absolute speedup** on full LK (256x256
> ws=5 smooth-quadratic). The new
> `simd_mul_acc_signed_signed_byte(a_i8, b_i8, n)` NOVA codegen
> primitive (R18A, commit `db34532`) is the structural fit R17C
> documented as the missing piece: AVX2 `vpmovsxbw + vpmaddwd`
> inline, ARM64 NEON `sshll + smull/smull2`, WASM v128
> `i32x4.dot_i16x8_s`, scalar fallback elsewhere. The 5 accumulators
> map to 7 SIMD calls per pixel: 3 direct (Σ Ix², Σ Iy², Σ IxIy --
> all i8×i8) + 4 for the It two-piece split. It in [-255, 255] is
> outside i8, so we decompose `It = 2 * It_lo + It_hi` where
> `It_lo = It / 2` (NOVA truncate-toward-0, range [-127, 127]) and
> `It_hi = It - 2*It_lo` (range {-1, 0, 1}), both i8. Then
> `Σ Ix*It = 2 * Σ(Ix*It_lo) + Σ(Ix*It_hi)` cell-by-cell -- bit-
> identical to scalar because integer add is associative. The
> load-bearing optimization: pre-compute the 4 gradient i8 buffers
> across the WHOLE IMAGE in one pass before the per-pixel scan,
> so per-pixel staging becomes 20 `memcpy_raw` calls (R15A pack
> pattern) + 7 SIMD calls instead of 75 scalar gradient calls.
> Without the pre-compute the small `n_cells = 25` doesn't let
> AVX2's 16-byte vector iter amortize the staging (initial cut
> measured 0.67x). New API: `lk_optical_flow_mulacc_u8(prev, next,
> w, h, win_size)` (env-var dispatch `CE_LK_MULACC_SIMD=on`,
> default off; falls back to scalar `lk_optical_flow` otherwise),
> `lk_optical_flow_mulacc_pyramid` (R11A pyramidal with mul-acc
> inner solve at every level), `lk_optical_flow_mulacc_perpixel`
> (R13B per-pixel pyramidal with mul-acc inner solve). 28 new
> assertions in `tests/unit/test_lk_mulacc_simd.nova` (whole-image
> bit-identical sweep -- mismatch count == 0 across all interior
> pixels; textured h-shift / v-shift / identical-frames; high-
> contrast-bands exercising the |It| > 127 path; pyramid + per-
> pixel dispatch-off bit-identical; env-var dispatch; input
> validation). Bench script
> (`scripts/bench_simd_production.sh`) extends the flow bench to
> 4 paths (scalar / R12A i32 SIMD / R17C u8 packed-scan / R18A.2
> mul-acc) and FAILs on any disagreement. Headline numbers:
> scalar = 67 ms, i32 SIMD = 368 ms (0.18x -- byte→i32 staging),
> u8 packed-scan = 73 ms (0.91x -- locality only), mul-acc = 18 ms
> (**3.69x absolute**, 4.03x vs R17C u8). All prior optical-flow
> suites (R10D `test_optical_flow.nova` 53 assertions, R11A
> `test_optical_flow_pyramid.nova` 52, R13B
> `test_optical_flow_perpixel.nova` 34, R17C `test_lk_u8_simd.nova`
> 34) remain bit-identically green. R16E adds `src/io/transducers/audio_spectrogram.nova` — a
> Short-Time Fourier Transform / spectrogram built on an integer-only
> radix-2 Cooley-Tukey FFT, closing the frequency-domain gap in the
> audio chain (every prior audio module — R6E Klatt, R7F VAD, R7F
> STT, R10F/R11B pitch, R12D PSOLA, R13D voice clone, R14E reverb /
> gate / compressor — operates in the time domain). A 512-entry
> milli-precision cos/sin twiddle table at the base size 1024, looked
> up with a stride for smaller N; a Hann window cache keyed by
> frame_size; in-place bit-reversal permutation; `log2(N)`
> decimation-in-time butterfly stages; integer Newton sqrt for
> `|X[k]| = sqrt(re^2 + im^2)`. Defaults `FRAME_SIZE=512` /
> `HOP_SIZE=256` (32 ms / 16 ms @ 16 kHz, 50% overlap, matching
> whisper / MFCC conventions); allowed sizes are powers of 2 in
> `{64, 128, 256, 512, 1024}`; sample-rate range `[8000, 48000]` Hz;
> input cap `480000` samples (30 s @ 16 kHz). Public API: `stft`,
> `stft_magnitude`, `stft_bin_to_hz`, `stft_frame_to_ms`,
> `stft_peak_frequency`, `stft_total_magnitude`, `fft_radix2`,
> `ifft_radix2`. New chat command `/spec PATH` (2 lines in
> `examples/crossengin_chat.nova`) runs the STFT and reports
> `(frames=N, bins=K, peak_frequency_first_frame=F Hz, …)`. 49 unit
> + 19 integration assertions, all green; FFT peak at bin 6 for a
> 200 Hz @ 16 kHz / N=512 sine (expected 6.4); Klatt /ae/ peak at
> 1718 Hz (F2=1720 Hz target); JFK 16 kHz WAV produces 686 frames
> and ~2.18e9 total magnitude. R16F extends R15D's `src/kg/query.nova` mini-SPARQL with
> the three remaining "SPARQL 1.0 core" surface features: **OPTIONAL**
> (left-outer-join semantics — keep the binding even when the inner
> block doesn't match; the introduced vars render as `?` in the
> emit-line), **UNION** (alternation — `{ left } UNION { right }`
> concatenates each branch's bindings with SPARQL bag semantics), and
> **ORDER BY** (`[ASC|DESC]` + `(field)` — sort by the integer field
> of the most-recently-bound atom; ties broken by atom_id ASCENDING
> for stability; LIMIT applies after the sort). The parser gains 6
> new keywords (`OPTIONAL`, `UNION`, `ORDER`, `BY`, `ASC`, `DESC`),
> two new structural tokens (`TOK_LPAREN` / `TOK_RPAREN` for the
> `DESC(alpha)` paren form), and two new AST node tags
> (`PAT_OPTIONAL` / `PAT_UNION`); the executor's pattern loop is
> lifted into an `_qry_exec_patterns` recursive helper so OPTIONAL
> and UNION compose freely inside their inner brace groups. ORDER
> BY runs an in-place stable insertion sort over the binding list
> (keyed on the atom's integer field, tiebroken by atom_id ASC)
> before LIMIT applies. R15D's `kg_query_parse / _execute /
> _compile_and_run` public API is unchanged; new accessors
> `kg_query_orderby_has / _field / _dir` round out the
> parsed_query_t surface. 60 unit assertions
> (`tests/unit/test_kg_query_ext.nova`) + 22 integration assertions
> (`tests/integration/scenario_ppp_query_ext.sh`); all green.
> All 55 R15D `test_kg_query.nova` assertions remain bit-identically
> green (the BGP+FILTER+LIMIT surface is untouched). R17E completes the
> mini-SPARQL "SPARQL 1.1 analytical" subset by extending
> `src/kg/query.nova` once more with **aggregate functions** (`COUNT`,
> `SUM`, `AVG`, `MIN`, `MAX`) and **GROUP BY**. Each aggregate SELECT
> item is a parenthesised `(AGGFN(?var [field]) AS ?alias)` tuple --
> `COUNT(?a)` counts the rows in the binding set; `SUM(?a alpha)`,
> `AVG(?a alpha)`, `MIN(?a alpha)`, `MAX(?a alpha)` read the `field`
> off the atom bound to `?var` and reduce. Without `GROUP BY`,
> aggregates fold the WHERE-clause output into a single row; with
> `GROUP BY ?var`, the binding set partitions by the int value bound
> to `?var` (e.g. `?a kind ?kind . GROUP BY ?kind` partitions by atom
> kind code) and emits one row per non-empty group. Empty-set
> sentinels: COUNT=SUM=0, AVG=MIN=MAX=`QRY_AGG_EMPTY` (-1). Integer
> arithmetic throughout (AVG = SUM / COUNT, truncating). FILTER
> applies before aggregation; LIMIT applies after. On R15D's 10-atom
> fixture: `COUNT(?a)` over FACTs = 5; `SUM(?a alpha)` = 15000;
> `AVG(?a alpha)` = 3000; `MIN/MAX` = 1000 / 5000; `GROUP BY ?kind`
> returns two rows (FACT count=5, CONCEPT count=5). The parser gains
> 7 new keywords (`COUNT`, `SUM`, `AVG`, `MIN`, `MAX`, `GROUP`, `AS`),
> two new parsed_query_t slots (`QRY_AGGS`, `QRY_GROUPBY`), and new
> accessors `kg_query_aggs / _aggs_has / _groupby_has / _groupby_var`.
> 67 unit assertions (`tests/unit/test_kg_query_agg.nova`) + 24
> integration assertions (`tests/integration/scenario_sss_query_agg.sh`);
> all green. The 55 R15D + 60 R16F unit assertions remain
> bit-identically green; R15D/R16F integration scenarios likewise
> pass unchanged. R16A adds
> `src/persistence/merkle_signing.nova` — an
> Ed25519 sign + verify wrap of the R15E Merkle root, closing the
> last gap in the snapshot attestation chain. R15E shipped tamper
> detection against an operator who edits a single atom byte (the
> recomputed root disagrees with the stored claim); R16A closes the
> gap against an attacker who controls the WHOLE file (such an
> attacker can rewrite both the atom AND the meta.merkle_root claim
> to match). With R16A, the writer optionally signs the recomputed
> Merkle root with a long-term Ed25519 key
> (`CE_SNAPSHOT_SIGN_KEY=<priv>` env), emitting
> `meta.merkle_signature <128-char hex>` as another optional v2
> meta-block line. The verifier holds ONLY the matching pubkey
> out-of-band (`CE_SNAPSHOT_VERIFY_PUBKEY=<pub>`); on /load it
> recomputes the root and asks Ed25519 to verify the file's
> signature against the recomputed root under the trusted pubkey.
> An attacker who tampers the file but does NOT control the priv
> key cannot forge a fresh signature — load fails loudly. New chat
> command `/snap_sign_status` reports whether the file carries a
> signature, whether the pubkey is configured, and the last verify
> result (`verified | TAMPERED | no_signature | no_pubkey |
> file_missing`). New helper `examples/snap_keygen.nova` produces a
> fresh 32-byte priv (mode 0600) + 32-byte pub (mode 0644). Strict
> mode `CE_SNAPSHOT_REQUIRE_SIGNATURE=1` REFUSES an unsigned file
> when a verify pubkey is configured; lenient default warns +
> proceeds (the same opt-in shape R15E's verify env uses). Sign
> latency ~241 ms per /save measured on this sandbox (~one
> ed25519_sign per snapshot save, NOT per atom — linear in saves,
> not KG size). Determinism verified live: two /save calls on an
> unchanged KG produce bit-identical `meta.merkle_signature` hex
> (Ed25519 is deterministic, not probabilistic). Tamper detection
> verified live: flipping `kgs.atoms[0].label` makes
> /snap_sign_status report `last_verify=TAMPERED`, and
> CE_SNAPSHOT_VERIFY_PUBKEY=<pub> /load refuses the file with
> `(load FAILED: Merkle signature mismatch...)`. 51 unit
> assertions + 16 integration assertions; all green. All existing
> snapshot tests pass unchanged: `test_merkle` 60,
> `test_snapshot_writer` 27, `test_snapshot_disk` 31,
> `test_snapshot_episodic` 51, `test_snapshot_synapses` 89,
> `test_snapshot_selfmodel` 38, `test_snapshot_compaction` 48,
> `test_snapshot_reader` 25, `test_snapshot_migrate` 37,
> `test_snapshot_disk_full` 72, `test_snapshot_delta` 84,
> `test_schema_migration` 78. R15E added
> `src/persistence/merkle.nova` — a SHA-256
> Merkle-tree tamper-evident atom-hash chain over the v2 snapshot's
> KGS section, closing the integrity gap that lived between R5D's
> crash-safe writer and R14F's Ed25519 signing primitive. Without it
> an operator could `vim` a snapshot file on disk, flip a single bit
> in any atom, and the next `/load` would happily install the mutated
> state with no indication anything was off. The Merkle root is a
> 32-byte SHA-256 summary built bottom-up over canonical
> per-atom-record bytes (`kg=<label>|id=<id>|kind=<kind>|label=<label>|alpha=<a>|beta=<b>`,
> field order fixed); pair-and-hash with last-leaf duplication on odd
> counts (Bitcoin convention); root emitted as an OPTIONAL
> `meta.merkle_root <hex>` line in the v2 meta block (pre-R15E readers
> ignore the line — additive, no major bump). The new chat command
> `/snap_verify [PATH]` recomputes the root over the loaded KGS and
> reports `verified | TAMPERED | no Merkle commitment`. With
> `CE_SNAPSHOT_VERIFY_MERKLE=1` the normal `/load` path becomes a
> tripwire that refuses any file whose recomputed root disagrees with
> the meta claim. Inclusion proofs (`merkle_proof` →
> direction-tagged sibling-hash list, `merkle_verify_proof` ↔ in
> O(log N) hash ops) round out the public API for a future
> federation-peer attestation surface. The module ships its OWN
> SHA-256 (FIPS 180-4, byte-identical to noise_xk's `sha256_buf`) to
> keep the persistence import graph minimal — no chacha20 / poly1305
> / bignum_2048 transit just for an integrity check. **Tamper
> detection verified live: flipping a single byte in
> `kgs.atoms[0].label` changes the root, `/snap_verify` reports
> TAMPERED, and `CE_SNAPSHOT_VERIFY_MERKLE=1 /load` refuses the
> file.** Determinism verified live too: two `/save` calls on an
> unchanged KG produce bit-identical `meta.merkle_root` hex. 60 unit
> assertions + 13 integration assertions; all green. All existing
> snapshot tests pass unchanged: `test_snapshot_writer` 27,
> `test_snapshot_disk` 31, `test_snapshot_episodic` 51,
> `test_snapshot_synapses` 89, `test_snapshot_selfmodel` 38,
> `test_snapshot_compaction` 48, `test_snapshot_reader` 25,
> `test_snapshot_migrate` 37, `test_snapshot_disk_full` 72,
> `test_snapshot_delta` 84, `test_schema_migration` 78. R15D adds
> `src/kg/query.nova` — a mini-SPARQL declarative
> query language over the KG: text-based triple patterns + FILTER + LIMIT
> that compose for arbitrary atom queries, closing the long-standing
> "operator wants a declarative query surface" gap left by R6F/R8F
> episodic, R10C TF-IDF search, R11F/R12C clustering, and R13E PageRank
> (all PROGRAMMATIC read paths -- pick which `_cmd` to call). Operators
> who know SPARQL can now write `SELECT ?a WHERE { ?a kind FACT . ?a
> links ?b . FILTER alpha > 500 . } LIMIT 5` and have it tokenize ->
> recursive-descent parse -> iterate triple patterns over `kg_atoms` ->
> accumulate / extend / filter bindings -> return up to LIMIT rows.
> Supports: triple patterns (subject predicate object .), variables
> (`?var` matches any value and binds), literal predicates (kind, label,
> alpha, beta, created_ns, links), FILTER predicates (>, <, =, != on
> int fields alpha/beta/count/created_ns/version/kind, scoped to the
> most-recently-bound atom), implicit AND across multiple patterns,
> LIMIT N (default 100, max 10000). Out of scope: OPTIONAL / UNION /
> MINUS / boolean FILTER composition / regex / ORDER BY / GROUP BY /
> aggregates. Lex-error sniff (sentinels look like `<unterm-string>`)
> and parse-error sentinels (`[ERR_OBJ_TAG, msg]`) surface as
> `QUERY error=...` lines on the chat dispatch path -- malformed
> input never crashes the process. Public API: `kg_query_parse(qs)`,
> `kg_query_execute(kg, parsed)`, `kg_query_compile_and_run(kg, qs)`,
> + accessors `kg_query_vars / _patterns / _limit / _is_parsed`. New
> chat admin: `/query <SPARQL_string>` -- prints `QUERY bindings=N
> vars=V limit=L` + up to first 5 `BINDING i: a=X b=Y` rows +
> `QUERY_END`. 55 unit assertions (`tests/unit/test_kg_query.nova`) +
> 18 integration assertions (`tests/integration/scenario_kkk_query.sh`);
> all green. All existing KG tests (R6F/R8F episodic, R10C semantic,
> R11F/R12C clustering, R13E PageRank) remain bit-identically green.
> R14E adds `src/io/transducers/audio_dsp.nova` — classical DSP
> effects (Schroeder 1962 reverb + level-dependent noise gate + symmetric
> compressor), closing the *effects* leg of the audio chain next to R6E
> synth, R7F/R9B VAD, R8B/R10B STT, R10F/R11B pitch, R12D PSOLA, and
> R13D voice cloning. Reverb is the textbook Schroeder structure: 4
> parallel feedback comb filters (delays {5963, 4998, 4327, 3911}
> scaled to working sample rate from the 16 kHz reference) into 2
> cascaded allpass filters (delays {1051, 357}, fixed gain 0.7), mixed
> with the dry signal as `(wet * wet_signal + (1000 - wet) * dry) / 1000`
> in millis. Output is `len(pcm) + 400ms * sr / 1000` samples so the
> IR rings out cleanly past the input. The noise gate computes a 30 ms
> RMS envelope; below threshold it attenuates by `ratio_milli`
> (1000 = hard gate, 500 = 2:1) with linear attack/release ramps
> (default 5 ms / 50 ms) so the gain change at the threshold crossing
> doesn't click. The compressor inverts that: it attenuates ABOVE
> threshold, useful for taming the loud peaks of a `room=1000` reverb.
> All integer arithmetic; ring buffers for delay lines; PCM16 per-sample
> clipping. **Reverb impulse response (impulse at sample 0, 4000-sample
> input @ 8 kHz, wet=1000, room=800): 7200 output samples, 610 non-zero
> in the tail past the input** (the IR decay); first comb spike at
> sample 1955. **Noise-gate attenuation on a 400-PCM16 square wave below
> the default 100 milli threshold: input RMS 400 -> output RMS 0** (full
> -inf-dB attenuation when `ratio_milli=1000`). Hardest engineering
> problem was NOT the DSP -- the sum-of-squares envelope reaches ~1e12
> and the reverb's wet/dry mix product hits ~3e7, both well above
> NOVA's 1 MB smart-op pointer-threshold bug (`NOVA_BUG_THRESHOLD.md`).
> Workaround: route the affected binops through `int_mul`, `int_add`,
> `int_sub`, `int_div`, `int_shr`, and a sign-bit `int_lt` helper that
> stays scalar even when both operands are huge. New chat admins:
> `/reverb PATH [WET_MILLI]` (writes `<PATH>.reverb.wav`, reports
> input/output RMS) and `/gate PATH [THRESHOLD_MILLI]` (writes
> `<PATH>.gate.wav`, same diagnostic). 34 unit assertions + 23
> integration assertions; all green. All R6E/R7F/R9B/R8B/R10F/R11B/
> R12D/R13D audio tests pass unchanged. R15A wires R14B's
> `simd_sad_u8(a_ptr, b_ptr, n_bytes)` raw-byte SAD primitive (AVX2
> `vpsadbw`, 32 bytes -> 4 i64 partials per instruction) into the
> stereo block-matching disparity path, closing R13A's 1.93x absolute
> ceiling that was bounded by the byte->i32 staging overhead of R12A's
> `simd_sum_abs_diff` wrapper. Adds `stereo_sad_block_u8` and
> `stereo_disparity_u8_simd` (with `CE_STEREO_U8_SIMD=on` env-var
> dispatch from the public `stereo_disparity` API), using
> `_stereo_pack_block_u8` to pack a `WIN_SIZE x WIN_SIZE` window into
> a contiguous byte buffer (one `memcpy_raw` per row) before the
> single-call SAD reduction. PGM data is stored as raw byte buffers
> (alloc + store8 + load8) so the byte SIMD path is a direct fit
> without representation conversion. **256x256 ws=7 max_disp=16
> textured pair: scalar ~850 ms, R12A/R13A i32 SIMD ~795 ms (~1.07x),
> R15A u8 SIMD ~150 ms — a ~5.5x absolute speedup vs scalar and
> ~5.3x vs the i32 SIMD path, comfortably above the 3-4x target.**
> Bit-identical: u8 SIMD vs scalar = 0 pixel mismatches on the bench
> fixture; 25 new unit assertions verify byte-wise identity across
> ws ∈ {3, 5, 7, 9, 11}, the shifted-by-8 R7E fixture, a four-spot
> pattern, and a vertical-edge fixture. All existing stereo /
> optical-flow regression suites green (`test_stereo` 54,
> `test_stereo_quality` 42, `test_stereo_sgm` 39, `test_simd_production`
> 35). `scripts/bench_simd_production.sh` extended to time all three
> paths back-to-back with bit-identical assertions. R17C applies the
> same u8 SIMD pattern to optical-flow LK with HONEST findings (mirrors
> R12A's precedent of shipping wiring at 0.84x/0.20x and documenting
> the limitation). LK's inner-loop accumulators are five sums of byte
> * byte SIGNED products which are structurally NOT a SAD primitive —
> `simd_sad_u8` returns Σ|a - b|, not a vector of products. R17C ships
> the parts of the pattern that DO fit: `lk_sad_block_u8` (window SAD
> via `_lk_pack_block_u8` + `simd_sad_u8`), `lk_image_sad_residual_u8`
> (per-row `simd_sad_u8` across the FULL image; canonical pyramidal-LK
> convergence metric; **~58x absolute speedup** on 256x256), and
> `lk_optical_flow_u8_simd` (full LK with pack-then-scan locality on
> It reads; opt-in via `CE_LK_U8_SIMD=on`). Full LK measured: scalar
> ~58 ms, R12A i32 SIMD ~362 ms (0.15x), R17C u8 packed-scan ~71 ms
> (0.80x scalar but **5.09x faster than R12A's i32 path**). Bit-
> identical preserved (34 new assertions; `test_lk_u8_simd.nova`).
> All existing LK regression suites green (`test_optical_flow` 53,
> `test_optical_flow_pyramid` 52, `test_optical_flow_perpixel` 34).
> Closing R13A's accumulator ceiling requires a NOVA `pmaddubsw` /
> `simd_mul_i16x16` byte-mul-acc primitive (flagged out-of-scope in
> R15A's known limitations and re-flagged here). R14F adds `src/safety/ed25519.nova` — a pure-NOVA RFC 8032
> Ed25519 digital-signature primitive on top of the existing `bn256_*`
> Montgomery REDC stack, closing the signature gap in the crypto suite
> (alongside ChaCha20-Poly1305 AEAD, Curve25519/G14 DH, Noise XK mutual
> auth, and Byzantine-resilient SecAgg). Self-contained: ships SHA-512
> (FIPS 180-4) inline (the existing noise_xk has SHA-256 but not
> SHA-512), field arithmetic over p = 2^255 - 19 (cached Montgomery
> context for ~0.1-0.5 ms per fe_mul), Edwards curve point ops in
> extended projective (X:Y:Z:T) form per RFC 8032 5.1.4, constant-time
> scalar mult via Montgomery ladder, scalar arithmetic mod the
> subgroup order L = 2^252 + 27742317777372353535851937790883648493,
> and the public `ed25519_keygen` / `ed25519_sign` / `ed25519_verify`
> API (32B seed, 32B pubkey, 64B signature). **All three RFC 8032 §7.1
> reference test vectors pass bit-exact** (#1 empty message: pubkey
> hex `d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a`,
> signature hex matches the published 64-byte value; #2 1-byte "72";
> #3 2-byte "af82" — all match). **Sign latency ~400 ms; verify
> ~780 ms** on this sandbox (dominated by Edwards scalar_mult; one
> in sign, two in verify). Tamper-detection paths all return 0:
> wrong message, flipped signature bit, wrong pubkey. 46 unit
> assertions + 12 integration assertions; all green. All existing
> crypto tests pass unchanged (`test_bignum_256` 70, `test_chacha20`
> 26, `test_poly1305` 9, `test_secure_aggregation` 170). R13D adds
> `src/io/effectors/audio_voice_clone.nova` — non-LLM voice cloning via
> Klatt formant transfer, the audio *cloning* leg next to R6E synthesis,
> R7F/R9B VAD, R8B/R10B STT, R10F/R11B F0 estimation, and R12D TD-PSOLA.
> Given a reference WAV of the target speaker, the pipeline extracts
> their mean P0 (via R11B YIN) + per-formant centers (via integer-only
> Levinson-Durbin LPC on the autocorrelation, then peak-pick on the
> `|1/A(e^jw)|^2` spectrum evaluated at a 50-Hz grid), builds a
> transferred phoneme formant table (direct match for observed phonemes;
> ratio-scaled R6E defaults for unobserved), and synthesizes new text in
> the cloned voice via a continuous-phase glottal-source + light-formant
> mix at the target P0. **LPC on Klatt /ae/ (F1=660, F2=1720, F3=2410)
> recovers (650, 1700, 2450) -- all within +/- 50 Hz.** **200 Hz
> reference -> profile.P0 = 20000 centi-Hz exact; cloned synth YIN F0 =
> 20000 centi-Hz exact (pitch transferred faithfully).** Identity
> profile (R6E defaults + ratio 1000) returns each phoneme unchanged.
> Caps: reference WAV <= 30 s (= 480000 samples @ 16 kHz); LPC order
> <= 12 (i32-friendly Levinson-Durbin range). New chat admin:
> `/clone REF.wav TEXT` analyzes the reference, synths text in the
> cloned voice, writes `/tmp/cloned.wav`, echoes
> `(clone REF: p0=X Hz, F1=Y Hz, F2=Z Hz, wrote /tmp/cloned.wav [N
> samples])`. 55 unit assertions + 14 integration assertions; all
> green. All R6E/R7F/R9B/R8B/R10F/R11B/R12D audio tests pass unchanged.
> R12D adds
> `src/io/transducers/audio_psola.nova` -- TD-PSOLA pitch shifting +
> time stretching (Moulines & Charpentier 1990) -- the audio
> *manipulation* leg next to R6E synthesis, R7F/R9B VAD, R8B/R10B STT,
> and R10F/R11B F0 estimation. Where naive resampling changes pitch
> AND speed together, TD-PSOLA changes either independently: pitch
> marks (R11B YIN-driven) anchor Hann-windowed segments at the local
> glottal-pulse peak; pitch shift redeposits segments at a
> denser/sparser grid (formants preserved); time stretch walks input
> marks at rate 1/beta (F0 preserved). Pure integer arithmetic,
> integer-milli Hann window via a 256-entry quarter-wave cosine
> table. **200 Hz sine pitch shifted by factor 2000 milli (1 octave
> up) yields YIN mean F0 = 40005 centi-Hz = 400.05 Hz** (the doubled
> F0 within 0.05 Hz of the target). Time stretch by factor 2000
> milli: 9600 input samples -> 19200 output samples (exact 2x). New
> chat admin: `/pitch_shift PATH FACTOR_MILLI` echoes input/output
> sample counts. Caps: input PCM <= 480000 samples (30 s @ 16 kHz);
> pitch/time factor in [250..4000] (-/+ 2 octaves). 34 unit assertions
> + 16 integration assertions; all green. All R6E/R7F/R9B/R8B/R10F/
> R11B audio tests pass unchanged. R12A wires R11D's i32x8
> SIMD intrinsics (`simd_sum_abs_diff`, `simd_add_i32x8`) into the two
> production hot paths identified in scope: stereo block-matching SAD
> (R7E `image_stereo.nova`) and Lucas-Kanade dense optical-flow
> accumulators (R10D `image_optical_flow.nova`). Adds
> `stereo_sad_block_simd`, `stereo_disparity_simd` (with
> `CE_STEREO_SIMD` env-var dispatch from the public `stereo_disparity`
> API), and `lk_optical_flow_simd` (with `CE_LK_SIMD` env-var
> fallback). All existing regression suites stay bit-identical green
> (R7E 54, R8D 42, R9A 39, R10D 53, R11A 52). New
> `tests/unit/test_simd_production.nova` ships 35 assertions verifying
> bit-identical SIMD vs scalar output across ws ∈ {3, 5, 7, 9, 11} and
> on the R10D 80x64 textured fixture. Realized 256x256 wallclock
> (current NOVA codegen): stereo SAD ~0.86x, LK ~0.20x — below the
> R11D microbench's 335-450x because per-builtin-call overhead
> amortized over ~49 lanes (one window) is larger than the AVX2
> inner-loop win; future NOVA codegen inlining will surface the
> primitive's speedup automatically through the same wiring. See
> `scripts/bench_simd_production.sh` for the bit-identical-checked
> bench harness. R12B adds
> `src/io/transducers/image_superpixels.nova` — SLIC (Simple Linear
> Iterative Clustering, Achanta 2012), the standard boundary-adherent
> superpixel segmenter and the natural complement to R11E's global
> k-means. R11E does coarse `(intensity, x, y)` Lloyd's clustering --
> works but cluster lines can cross intensity edges. R12B's SLIC
> restricts each cluster's search to a `2S x 2S` window around its
> center (where `S = sqrt(W*H / K)` is the grid step), making the
> algorithm O(N) regardless of K. Combined distance metric weighs
> intensity vs. spatial via compactness factor m (paper default 10);
> integer form `D^2_scaled = d_int^2 * S^2 + d_spat^2 * m^2` avoids
> floats AND avoids sqrt (argmin only). Centers are gradient-perturbed
> in their 3x3 neighbourhood to avoid initialising on top of edges.
> Boundary pixels are detected by 4-neighbour label difference; the
> overlay render draws them white over the original intensity.
> **4-quadrant 64x64 fixture (TL=0, TR=85, BL=170, BR=255) with K=16:
> 16 centers placed, step=16, converges in 2 iterations, 732 boundary
> pixels (~18% of the image), TL/TR/BL/BR pixels each land in a
> cluster whose center is in the matching quadrant with intensity
> within tol 30 of the quadrant intensity.** Public API:
> `slic_segment`, `slic_segment_default`, `slic_label_at`,
> `slic_center_at`, `slic_boundaries`, `slic_boundary_count`,
> `slic_render_pgm`, `slic_render_to_file`, `slic_pgm_args` (chat),
> `slic_append_features` (VP wiring). New chat admin: `/slic PATH
> [K]` (default K=64) prints `(slic WxH k=K step=S iterations=N
> converged=yes/no boundary_px=B wrote=yes path=/tmp/slic_overlay.pgm)`.
> Caps: dims <= 256, K in [16, 1024] (auto-clamped to keep S >= 4),
> m in [1, 40], max_iter <= 20. 61 unit assertions
> (`tests/unit/test_slic.nova`) + 16 integration assertions
> (`tests/integration/scenario_yy_slic.sh`); all green.
> R11E / R10D / R10F / R11B remain bit-identically green. R13E adds
> `src/kg/pagerank.nova` — Brin & Page 1998 PageRank centrality, the
> CENTRALITY companion to R11F (LPA) and R12C (Louvain) clustering.
> Clustering asks "which atoms hang together?"; PageRank answers
> "which atoms are individually most important?" by computing the
> steady-state distribution of a damped random walk in
> integer-milli units (no FP, fully deterministic). The per-atom
> update `PR_new(i) = (1-d)/N + d * SUM_{j in In(i)}(PR(j)/out_deg(j))`
> uses MICRO precision (`pr * 1000` per division) + an O(N)
> renormalisation step each pass to absorb integer-truncation bias;
> without that pass the Zachary karate fixture leaks ~40% of its
> mass over 30 iterations. Dangling atoms (no out-edges) hand their
> mass uniformly across the graph each iteration so no PR leaks.
> On the **Zachary 1977 karate-club benchmark (34 atoms, 78 edges)
> PageRank converges in 10 iterations and the top-2 atoms are
> {0 (Mr Hi, PR=97 milli), 33 (Officer, PR=100 milli)}** -- the
> classic Brin & Page centrality ranking, recovering Zachary's two
> faction leaders without any text or label information. Total mass
> is conserved within +/- 50 milli for N=34. On the **barbell
> (two 4-cliques joined by a bridge) the bridge atoms (3, 4) own
> the top-2 PR slots (149 milli each) with the six clique-interior
> atoms tied at 116 milli** -- every cross-clique walk has to cross
> the bridge, so the bridge accumulates centrality. Public API:
> `pagerank_compute(kg, damping_milli, max_iter)`,
> `pagerank_default(kg)` (Brin & Page defaults: d=850, iter=50),
> `pagerank_at(result, atom_id)`,
> `pagerank_top_k(result, k)`, `pagerank_converged`,
> `pagerank_iterations`, `pagerank_n_atoms`, `pagerank_damping`,
> `pagerank_total_mass`. New chat admin: `/pagerank` prints
> `PAGERANK n=N iterations=I converged=yes/no top=[id=X,pr=Y ...]`.
> Convergence threshold is L_inf < 2 milli (the brief's "< 1 milli"
> with a 1-milli tolerance to absorb the unavoidable integer-noise
> ping-pong on dense graphs). 90 unit assertions
> (`tests/unit/test_pagerank.nova`) + 23 integration assertions
> (`tests/integration/scenario_eee_pagerank.sh`); all green.
> R11F's 71, R12C's 72 unit checks remain bit-identically green.
> R12C adds
> `src/kg/louvain.nova` — Blondel-2008 two-phase greedy modularity
> optimiser, the gold-standard companion to R11F's label-propagation
> detector. Phase 1 picks moves analytically (DQ in integer-only
> milli units: `gain_scaled = 2m*k_u_in_C - k_u*Sigma_tot_C`); Phase 2
> aggregates communities into super-nodes and recurses until no merge
> improves modularity. On the **Zachary 1977 karate-club benchmark
> (34 nodes, 78 edges)** Louvain reports modularity 399 milli vs
> R11F's 256 milli (**+143 milli, 56% relative improvement**) and
> finds 3 communities vs LPA's 2. On the barbell + 3-triangle
> fixtures both algorithms find the same global optimum (423/667
> milli). New chat admin: `/louvain` prints
> `(LOUVAIN n=N largest=L modularity=M milli edges=E depth=D)`.
> Module exports `louvain_communities`, `louvain_label_at`,
> `louvain_community_members`, `louvain_largest_community`,
> `louvain_modularity`, `louvain_levels`, `louvain_dendrogram` (the
> hierarchical merge tree, finest -> coarsest). 67 unit assertions
> (`tests/unit/test_louvain.nova`) + 19 integration assertions
> (`tests/integration/scenario_zz_louvain.sh`); all green. R11F's
> 71 unit checks remain bit-identically green. R11B extends
> `src/io/transducers/audio_pitch.nova` (R10F's file) with parallel
> YIN-class entry points (`pitch_estimate_frame_yin`, `pitch_track_yin`,
> `pitch_run_yin_command`) that cure R10F's first-formant snap on
> harmonic-rich natural speech. YIN (de Cheveigne & Kawahara 2002)
> replaces autocorrelation's argmax with the cumulative mean normalized
> difference function `d'(tau) = d(tau) * tau * 1000 / running_sum`,
> whose MINIMUM marks the period (no formant ambiguity). Pure integer
> arithmetic, no FFT, no floats. R10F autocorrelation API stays
> unchanged for back-compat. **JFK head-to-head: R10F mean 220 Hz
> (formant snap) -> R11B YIN mean 145 Hz (in adult-male [80..180] Hz
> band).** Klatt /uw/: 296 Hz -> 145 Hz. Pure 100/200/400 Hz sines:
> both methods parity (exact). New chat admin: `/pitch_yin PATH`
> prints `(pitch_yin PATH: f0_mean=N Hz, ...)`. 35 unit assertions
> (`tests/unit/test_audio_pitch_yin.nova`) + 9 integration assertions
> (`tests/integration/scenario_vv_yin_pitch.sh`); all green. R10F's
> 52 unit + 20 integration tests remain bit-identically green. R11F adds
> `src/kg/graph_clustering.nova` — Raghavan-2007 label-propagation
> community detection over the KG's xref link graph, the STRUCTURAL
> companion to R10C's textual TF-IDF ranker. R10C asks "which atoms
> LOOK alike" (TF-IDF over labels); R11F asks "which atoms are LINKED
> to each other" (xref-induced communities). Pure integer arithmetic,
> no FP weights. Each atom starts with its own atom_id as label; per
> pass, every atom (in deterministic-shuffled order) adopts its
> neighbours' most-frequent label, tie-breaking by lowest id. Up to
> 20 iterations; Raghavan's empirical < 5 iters holds on barbell +
> 3-clique fixtures. Newman modularity Q in milli (scale 1000):
> `(sum_intra * 1000) / m - (sum_a_sq * 1000) / (4*m*m)`, signed so
> anti-clusterings stay representable. New chat admin: `/communities`
> prints `(COMMUNITIES n=N largest=L modularity=M milli edges=E
> iter=I)`. Barbell fixture (two 4-cliques + bridge) -> 2 communities,
> 13 edges, modularity 423 milli, 2 iterations; 3 disjoint triangles
> -> 3 communities, 9 edges, modularity 667 milli; single 4-clique ->
> modularity ~ 0. Public API: `gc_label_propagation(kg, max_iter)`,
> `gc_label_propagation_seeded(kg, max_iter, seed)`, `gc_label_at`,
> `gc_community_count`, `gc_community_members`,
> `gc_largest_community`, `gc_modularity`. 71 unit assertions
> (`tests/unit/test_graph_clustering.nova`) + 20 integration
> assertions (`tests/integration/scenario_xx_communities.sh`); all
> green. R10C/R8F/R5/R8E remain bit-identically green. R10F earlier
> shipped
> `src/io/transducers/audio_pitch.nova` — autocorrelation-based F0 (pitch)
> estimation that completes the audio triad next to R6E Klatt synthesis
> and R7F+R9B VAD. Per ~30 ms frame compute
> `R(tau) = sum x(n) * x(n+tau)` over tau in [sr/f0_max..sr/f0_min] (32..320
> samples @ 16 kHz / 50..500 Hz), pick argmax, then sweep integer multiples
> for octave-down correction at the classical 0.92 threshold. Voicing rides
> on the normalized peak `R(best_tau) / R(0) >= 0.300`. Output in centi-Hz
> (Hz × 100) to preserve sub-Hz resolution in pure integer arithmetic. Pure
> sines at 100, 200, 400 Hz @ 16 kHz hit exactly 100/200/400 Hz; white
> noise + silence resolve unvoiced; Klatt /uw/ vowel resolves at 296 Hz
> (formant snap, in [50..500] Hz band, voicing 868 milli); JFK
> adult-male WAV resolves at 220 Hz mean across 287 voiced frames
> (first-formant snap; YIN-class cure on the R10F roadmap; see
> AUDIO_AUDIT.md "R10F"). New chat admin: `/pitch PATH` prints
> `(pitch PATH: f0_mean=N Hz, f0_range=L-H Hz [...])`; graceful FAILED
> on missing WAV. 52 unit assertions (`tests/unit/test_audio_pitch.nova`)
> + 20 integration assertions (`tests/integration/scenario_tt_pitch.sh`);
> all green. R10C adds
> `src/kg/semantic_search.nova` — a purely textual TF-IDF +
> integer-cosine ranker over atom labels. Closes the KG read story
> alongside exact lookup (`atom_store.kg_find_atom`), episodic
> retrieval (R6F + R8F `episodic_recall_*`), and embedding-cosine
> nearest-neighbour (P3.4 `ann_query`). No neural embedding, no LLM
> call -- deterministic counting math in milli-fixed-point
> (FP_SCALE=1000). Tokenize splits on whitespace + ASCII punctuation,
> lowercase, drops < 3 chars / > 30 chars. Sub-linear TF
> (`1 + log2(count)`) + IDF (`log2(n) - log2(df) + smoothing`, the
> log subtraction sidesteps integer-div precision loss when df ~ n)
> + cosine (`dot * 1000 / (norm_q * norm_d)` with Newton sqrt).
> Sparse index: forward `[atom_id -> [(tid, tfidf_milli)]]` + inverted
> `[tid -> [atom_id...]]` + lazy IDF cache. Public API:
> `ss_index_new`, `ss_index_add_atom` (idempotent), `ss_search`,
> `ss_search_by_atom_id` (excludes the query atom). New chat admin:
> `/find <query>` builds a transient index over `kg_atoms` and prints
> top-5 as `FIND query="..." matched=N` / `RESULT rank=K atom_id=A
> sim=M milli` / `FIND_END query="..."`. On the 10-atom
> semantic_search_demo fixture, `/find "machine learning"` ranks the
> ML atom (id=1) at sim=521 milli, the deep-learning atom (id=2) at
> 171 milli; identical-vector cosine = 1000 milli; orthogonal (disjoint
> vocab) = 0. 73 unit assertions
> (`tests/unit/test_semantic_search.nova`) + 21 integration assertions
> (`tests/integration/scenario_rr_semantic_search.sh`); all green.
> R8F episodic retrieval (96 + 19), R6F consolidation (79 + 18), and
> R5 atom-store tests remain bit-identically green. +1 from R10B
> adding
> `src/io/transducers/vosk_backend.nova` — Vosk offline STT as a
> first-class alternative to whisper.cpp (~50 MB English model, pure-C
> streaming recognizer; JFK conf=968 milli). Auto-pick now does
> whisper > vosk > stub; `CE_STT_BACKEND=vosk` forces the new path.
> R10B also closes the R8B follow-up on per-utterance whisper
> confidence: `whisper_transcribe_with_confidence` parses
> `src/io/transducers/vosk_backend.nova` — Vosk offline STT as a
> first-class alternative to whisper.cpp (~50 MB English model, pure-C
> streaming recognizer; JFK conf=968 milli). Auto-pick now does
> whisper > vosk > stub; `CE_STT_BACKEND=vosk` forces the new path.
> R10B also closes the R8B follow-up on per-utterance whisper
> confidence: `whisper_transcribe_with_confidence` parses
> whisper-cli's `-ojf` JSON output for per-token probabilities
> (JFK lands at 895 milli, up from the legacy 800 ballpark). New
> tests: `test_vosk_backend.nova` (39 checks),
> `test_whisper_backend.nova` extended 28 -> 41 checks,
> `scenario_qq_vosk.sh` (16 assertions). All green. See AUDIO_AUDIT.md
> "R10B: per-utterance confidence + Vosk offline backend". R10D adds
> `src/io/transducers/image_optical_flow.nova` — Lucas-Kanade dense
> per-pixel optical flow between two consecutive PGM frames. For each
> interior pixel, compute integer image gradients (Ix, Iy via central
> differences) and the temporal gradient (It = I_next - I_prev) over a
> WIN_SIZE x WIN_SIZE window centered there, then solve the 2x2 normal
> equations via the closed-form integer inverse:
> det = (Sum Ix^2)(Sum Iy^2) - (Sum IxIy)^2; u_milli, v_milli scaled
> by 1000 / det. det == 0 (no-texture / aperture problem) marks the
> pixel invalid (flow reads 0). Default WIN_SIZE = 5 (OpenCV's
> calcOpticalFlowPyrLK default); dims cap 256x256. On the smooth
> quadratic-bowl fixture shifted DIAGONALLY by (1, 1): u ~ 918 milli,
> v ~ 1042 milli at probed interior pixels (target 1000, 1000 -- right
> on). Texture-less constant-fill fixture: 0 / 1024 pixels valid (100%
> degeneracy detection). Identical-frame fixture: mean magnitude = 0,
> density label "low". New chat admin: `/flow prev.pgm next.pgm` prints
> `(flow WxH mean_mag=Nmilli valid=K image_optical_flow_density_*)`.
> Visual seam emits `image_optical_flow_magnitude_*` +
> `image_optical_flow_density_*` atoms when `CE_VP_FLOW_PREV` env
> points at the previous PGM frame. 53 unit assertions
> (`tests/unit/test_optical_flow.nova`) + 11 integration assertions
> (`tests/integration/scenario_ss_optical_flow.sh`); all green. R5C
> SIFT, R6D ORB, R7E/R8D/R9A stereo, R5E Canny suites remain
> bit-identically green.
> R11A extends R10D with the classical Bouguet 2000 coarse-to-fine
> Gaussian pyramid + iterative warping so multi-pixel shifts stay
> inside the LK linear regime at every level. New public API
> `lk_pyramid_build`, `lk_warp_image`,
> `lk_optical_flow_pyramid(prev, next, w, h, win, levels=3, iter=3)`;
> chat `/flow_pyr prev.pgm next.pgm`. On the 8-px shift fixture
> R10D under-estimated at u=5697 milli; R11A pyramid reads
> u=7531 milli (target 8000, within +/-500). 4-px down: v=4116
> (target 4000); diag (3, 3): u=2962 v=2762 (target 3000, 3000).
> Per-iteration correction clamped at +/-4000 milli per pixel to
> suppress boundary-discontinuity outliers in the coarse-level
> warp. 52 new unit assertions
> (`tests/unit/test_optical_flow_pyramid.nova`) + 12 integration
> assertions (`tests/integration/scenario_uu_pyramid_flow.sh`).
> R13B (this session) closes R11A's translational-aggregate
> simplification: `lk_optical_flow_pyramid_perpixel(prev, next, w, h,
> win, levels=3, max_iter=1)` propagates the per-pixel flow field
> across pyramid levels with a 7x7 MAD-based outlier rejection at
> each pixel (replacing R11A's blanket +/-4000 milli ceiling on the
> global average). Bilinear warp inline preserves sub-pixel accuracy
> across levels. Headline on a 128x64 motion-discontinuity fixture
> (dense sinusoidal texture, left half shift=10 px, right half
> shift=0 px): R13B reads LEFT u=8180 RIGHT u=0 -- each half
> recovered independently; R11A's translational-aggregate reads
> LEFT u=2008 RIGHT u=552 -- both halves collapse toward boundary
> noise. On the easy uniform 8-px shift R13B reads u=7859 vs R11A
> u=8148 -- comparable, no regression. New chat admin `/flow_pp
> prev.pgm next.pgm`. 34 new unit assertions
> (`tests/unit/test_optical_flow_perpixel.nova`) + 11 integration
> assertions (`tests/integration/scenario_ccc_lk_perpixel.sh`).
> +1 from R9F adding
> `src/learning/byzantine_aggregation.nova` — two coordinate-wise robust
> aggregation rules (trimmed mean + median) that tolerate up to f
> malicious participants per federated round. The federated
> aggregator gains a parallel `fed_acc_byz_*` accumulator that keeps
> per-participant rows so the reducer can inspect each contribution;
> `byz_aggregate(updates, strategy, trim_k)` dispatches BYZ_NONE /
> BYZ_TRIMMED_MEAN / BYZ_MEDIAN. `CE_FL_BYZ_STRATEGY=trimmed|median|none`
> + `CE_FL_BYZ_TRIM_K=<k>` env knobs flip strategy without code edits.
> On the canonical 5-soul fixture with one 100x poisoning outlier
> (honest mean 705/205 milli), BYZ_NONE yields the poisoned 2563/2163,
> BYZ_TRIMMED_MEAN (trim_k=1) recovers 710/210, BYZ_MEDIAN recovers
> 710/210 -- ~370x skew reduction. The SecAgg vs Byzantine trade-off
> (filtering needs per-soul values; SecAgg hides them) is
> deliberately surfaced in SECAGG_AUDIT.md: operators pick ONE
> privacy posture per round. R9F adds 74 unit assertions
> (`tests/unit/test_byzantine_aggregation.nova`) + 15 integration
> assertions (`tests/integration/scenario_pp_byz_fl.sh`); all green;
> R5's SecAgg (170 unit + 48 integration) and P3.7 federated
> aggregator (91 unit) tests remain bit-identically green. R8F
> extended `kg/episodic.nova` in place with the READ-side companion
> to R6F's consolidation cycle -- six retrieval functions
> (`episodic_recall_by_member`, `episodic_recall_by_window`,
> `episodic_recall_by_pattern`, `episodic_recall_top_belief`,
> `episodic_recall_most_recent`, `episodic_provenance`) so other parts
> of the substrate can pull memories OUT of the episodic store by member,
> time window, pattern overlap, belief, or recency. Each returns up to
> `top_k` (default 10, cap 1000) ranked by a composite key (primary =
> count / last_seen / confidence depending on the API; secondary =
> last_seen desc; tertiary = id asc). New chat admin command `/recall
> {member <id> | window <start> <end> | top | recent}` routes through
> `episodic_recall_cmd` which runs a transient consolidation against the
> live moment stream and prints RECALL / EPISODE / RECALL_END lines.
> Module count unchanged (extension only); +1 from
> 77 R8F unit
> assertions (`tests/unit/test_episodic_retrieval.nova`) + 19 integration
> assertions (`tests/integration/scenario_mm_episodic_recall.sh`) all
> PASS; R6F's existing 79 episodic unit assertions and 37 episodic
> integration assertions remain bit-identically green (the read API is
> a pure extension of the write side). +1 from
> `persistence/schema_migration.nova` added in R8E -- a generic,
> declarative KG-atom schema-evolution framework that generalizes R5D's
> one-off snapshot v1->v2 migration into per-atom-kind ADD / RENAME /
> RETYPE / REMOVE rules. Each atom carries a `schema_version` payload
> field; migrations are registered once and frozen for bit-reproducibility
> across sessions. Two demo migrations ship today: V1->V2 ADD `created_ns`
> across every atom kind (defaulting to the snapshot's `timestamp` when
> the ADD default is 0), V2->V3 RENAME `label` -> `display_label` on
> FACT atoms only (LANG / CONCEPT / SKILL keep `label`). A new optional
> `schema.atoms_version <int>` line in the v2 meta block carries the
> per-file generation; older v2 readers ignore it (forward-compatible).
> The schema layer is orthogonal to the wire layer -- R5D's v1->v2
> container migration still works bit-identically. ~78 unit
> assertions (test_schema_migration.nova) + 17 integration assertions
> (scenario_ll_schema_migrate.sh); all green; R5D's snapshot migrate
> tests (37) + R6F's episodic tests (79 unit + 37 integration) all
> still pass. Documented in SNAPSHOT_FORMAT.md "Atom-shape schema
> evolution (R8E)" section,
> +1 from
> `io/transducers/image_stereo.nova` added in R7E -- block-matching
> Sum-of-Absolute-Differences (SAD) stereo disparity from horizontally
> separated PGM-P5 pairs, plus depth recovery via
> `depth_mm = baseline_mm * focal_pixels / disparity`. Per pixel: extract
> a 7x7 block in LEFT centered there, slide along the same scanline in
> RIGHT from x down to x - 64, compute SAD at each offset, store the
> minimizing offset as disparity. Depth at zero disparity clamps to
> STEREO_MAX_DEPTH_MM (100 m) as an "unknown / infinity" sentinel. On a
> synthesized "right = left shifted left by 10 px" textured pair the
> unit test asserts disparity == 10 EXACTLY at probed interior points;
> mean lands at 6-8 because the leftmost half-window columns cannot
> reach the true disparity. New chat admin: `/depth L.pgm R.pgm` prints
> `(depth WxH mean_disp=D density=Dmilli image_stereo_density_*)`.
> Visual seam emits `image_stereo_disparity_mean_*` +
> `image_stereo_density_*` atoms when `CE_VP_STEREO_RIGHT` env points
> at the companion right PGM. R8D LR-check + sub-pixel refinement
> (`/depth_q`) and R9A Semi-Global Matching (`/depth_sgm`) extend the
> quality / smoothness side: R9A aggregates the SAD cost volume along
> 4 scanline paths (Hirschmuller 2008 recurrence with P1=8 / P2=32
> default penalties) so the disparity is smooth in textureless
> regions where block-matching speckles -- the unit test asserts
> SGM variance <= BM variance in a noisy-flat band. Cap dims at
> 128x128 with MAX_DISP<=64 to keep the cost volume under 4MB.
> ~54 + 42 + 39 unit assertions + 10 + 11 + 13 integration
> assertions; all green. See IMAGE_AUDIT.md for the 8-path / MI
> data-term follow-ups,
> +1 from
> `io/transducers/audio_vad.nova` added in R7F (energy + ZCR Voice
> Activity Detection: 30 ms frames, 4-state hysteresis machine with K=3
> speech-on / M=10 speech-off thresholds; integrated into
> `audio_capture_to_pcm_vad` and `stt_transcribe_wav_vad` so STT only
> sees confirmed-speech PCM) and extended in R9B with adaptive noise-
> floor calibration so `/listen` resolves on natural recordings: VAD
> takes the MIN per-frame energy across the leading ~480 ms as the
> noise floor estimate and lifts the live threshold to
> `max(noise_floor × 3, R7F_floor)`. R9B also relaxes
> `audio_capture_to_pcm` to scan past optional RIFF sub-chunks
> (LIST/INFO/bext/...) so whisper.cpp's bundled JFK 16 kHz WAV parses
> cleanly. End-to-end `/listen /tmp/whisper.cpp/samples/jfk.wav`
> now produces `vad_segments=1` and the full JFK transcript through
> whisper. See AUDIO_AUDIT.md for the algorithm + verification,
> +1 from
> `io/transducers/whisper_backend.nova` added in R8B (whisper.cpp STT
> backend wired into the seam from R7F — `/listen` actually transcribes
> when whisper-main + ggml-tiny.en.bin are installed). Spawns the
> whisper-cli binary via fork+exec from NOVA with stdout drained into
> the seam's `[transcript, confidence_milli, error]` triple. Pre-flights
> `binary not found` / `model not found` / `wav not found` so each
> install gap surfaces precisely. Auto-picks `whisper` when env unset +
> binary+model present, falls back to `stub`. Env knobs:
> `CE_STT_BACKEND=whisper|stub|subprocess`,
> `CE_WHISPER_BIN=/path/to/whisper-main`,
> `CE_WHISPER_MODEL=/path/to/ggml-tiny.en.bin`. Confidence ballpark
> 800 milli on success (per-utterance confidence via
> `--print-confidence` is a future task). On the dev container the
> bundled JFK sample transcribes to "And so my fellow Americans ask not
> what your country can do for you, ask what you can do for your
> country." See AUDIO_AUDIT.md "R8B: whisper.cpp STT backend" for the
> install layout + verification details,
> +1 from
> `io/transducers/noise_xk.nova` added in R6C and upgraded in R7C to
> 2048-bit RFC 7919 Group 14 DH — pure-NOVA Noise XK
> mutual-auth handshake + ChaCha20-Poly1305 transport encryption for
> kg_sync v3, closing the federation audit's "plaintext TCP" gap. Ships
> SHA-256 (FIPS 180-4), HMAC-SHA256 + HKDF (RFC 2104 / RFC 5869),
> 2048-bit DH over RFC 7919 Group 14 via `bn2048_modpow_ct` (Montgomery
> REDC, R5A), and the Noise XK state machine
> (`-> e, es; <- e, ee; -> s, se`) on top of `chacha20.nova` +
> `poly1305.nova` + `bignum_2048.nova`. `kg_sync.nova` extended with
> `kgsync_v3_handshake_initiator/responder` + `kgsync_v3_send_line` /
> `kgsync_v3_recv_line` that wrap every line in an AEAD frame; v2
> plaintext stays the default, `CE_KGSYNC_REQUIRE_NOISE=1` opts in to
> v3-only. ~42 unit assertions + 12 integration assertions; R7C
> handshake budgeted at **~5-15 s** wall-clock (4 modpow ops at ~1-4 s
> each via Montgomery REDC); MITM with a wrong responder static key
> correctly rejected at msg1 AEAD verify (auth contract survives the
> DH widening). The R6C 256-bit field-prime DH was below the RFC 7919
> Group 1 floor and is retired in favor of this 2048-bit upgrade.
> Documented in [`FEDERATED_AUDIT.md`](./FEDERATED_AUDIT.md),
> +1 from
> `kg/episodic.nova` added in R6F -- the ADR-0022 episodic-memory
> consolidation cycle. Scans the recent moment stream for clusters of
> atoms that co-occur >=5 times within a small temporal window
> (>=3 atoms within 10 ticks @100Hz), promotes each into a compound
> "episodic atom" with Beta(alpha, beta) belief (ADR-0023) and
> provenance label, and persists the result through the v2 snapshot's
> EPISODIC section (new `episodic.atoms.*` sub-block; NO version bump,
> a snapshot from a pre-this-build writer parses cleanly). Wired into
> the memory loop (ADR-0036) as a sub-task -- ADR-0036 reserves the
> 6+1 loop slots, so consolidation rides on memory, which already owns
> moments + episodes. New API in `src/kg/episodic.nova`:
> `episodic_consolidate`, `episodic_match`,
> `episodic_match_observation`, `episodic_update_belief`,
> `episodic_observe`. New 79 unit assertions
> (`tests/unit/test_episodic.nova`) + 37 integration assertions
> (`tests/integration/scenario_ff_episodic.sh`) all PASS; all
> existing scenarios (durability A/A2/A3, snapshot DD migration,
> KG/perception Q) still green. Also +1 from
> `io/transducers/image_orb.nova` added in P3.3 cont. v3 ORB feature
> detector + Hamming-distance matcher -- the patent-free, integer-only
> SIFT alternative (Rublee 2011): FAST-9 16-pixel Bresenham-circle
> 9-of-9-contiguous corner test (t=20) + Harris-proximity ranking
> reusing `harris_apply` from R1.6 + intensity-centroid orientation
> (m_01/m_10 over a 31x31 patch, quantized to 30 buckets via a
> precomputed cos/sin milli-unit table) + 256-bit rBRIEF descriptor
> (LFSR-generated point pairs from a Galois 16-bit LFSR, polynomial
> x^16+x^14+x^13+x^11+1, seed 0x12345; each pair rotated by the
> keypoint angle before sampling) + Hamming-distance matcher with
> Lowe ratio 0.75 (popcount-of-XOR over 8 int32 chunks; byte-wise
> XOR / popcount synthesized from int_add / int_mul / % since NOVA
> exposes no native bitwise builtins). On the 40x40 four-spots
> reference fixture ORB finds 96 keypoints per image with 96
> self-matches and 96 rotation matches (rotation invariance verified
> by the unit suite); the spots-vs-vertical-edge cross fixture
> produces 0 matches (the Harris-proximity filter rejects every FAST
> candidate on a single-direction edge). New chat admin:
> `/orb_match A B`. Documented in [`IMAGE_AUDIT.md`](./IMAGE_AUDIT.md),
> +1 from
> `io/transducers/image_hog.nova` added in R14D Histogram of Oriented
> Gradients (Dalal-Triggs 2005) dense descriptor -- the FOURTH descriptor
> family alongside the sparse keypoint detectors (SIFT R5C, ORB R6D,
> Harris R1.6). Where sparse keypoints describe only a handful of
> distinctive points, HOG tiles the WHOLE image and summarizes gradient
> orientation in fixed 8x8 cells, building a long fixed-topology
> descriptor (the feature that powered classical pedestrian detection
> and the standard baseline for "describe the image as a single vector"
> tasks). Per-pixel central-difference gradient -> L1-magnitude +
> unsigned orientation bin (integer atan2 via 8-quadrant tangent table)
> -> 8x8 cell histogram (9 bins, magnitude-weighted) -> 2x2 block
> concatenation (36 ints) -> L2-Hys normalization (L2 = 1000 milli,
> clip at 200 milli, re-normalize, final clamp so "no bin > 200" is
> a documented invariant) -> stride-1 sliding (50% overlap) ->
> concatenated descriptor. For the 32x32 reference fixture: 3x3=9
> blocks x 36 = 324 ints. For Dalal-Triggs' canonical 64x128
> pedestrian window: 7x15=105 blocks x 36 = 3780 ints. HOG is NOT
> rotation-invariant by design (unit-tested: a 90-deg rotated copy of
> the vertical-edge fixture produces L1 distance >= 2000 milli; SIFT/ORB
> would match such a rotation) but IS moderately translation-invariant
> within a block stride. New per-image atoms:
> `image_hog_descriptor_size_<small|medium|large>` and
> `image_hog_dominant_bin_<0..8|none>`. New chat admin: `/hog PATH`
> prints `(hog WxH cells=N dominant_bin=K magnitude_mean=M)`. On the
> 32x32 four-spots fixture dominant_bin=4 (vertical); on the 32x32
> vertical-edge fixture dominant_bin=0 (horizontal -- the gradient
> direction is perpendicular to the edge); the integration scenario
> asserts these disagree. R21D extends this module with an
> integral-histogram acceleration of the per-cell aggregation step:
> a precomputed `(W * H * NUM_BINS)` cumulative-magnitude buffer
> recovers any cell's per-bin total in 4 four-corner lookups
> (`hog_compute_integral` / `hog_compute_integral_default`), structured
> to amortize across many downstream queries at the same scale (e.g.
> R15C's sliding-window detector evaluating overlapping windows). The
> integral path is BIT-IDENTICAL to the scalar path on every fixture
> (unit-tested across vertical-edge / horizontal-edge / diagonal /
> four-spots / 64x128 Dalal-Triggs window / cell_size=4 / num_bins=6 /
> num_bins=12). Opt-in via `CE_HOG_INTEGRAL=on`; the scalar path stays
> default until the wire-into-R15C round flips the contract. On a
> single isolated `hog_compute_*` call the integral path is ~4-5x
> slower (build cost dominates) -- the operational win is reserved for
> the downstream amortization surface. **R22A wires R21D into R15C's
> sliding-window detector** (`det_sliding_window`): the integral
> histogram is built ONCE per scale and every candidate window's
> per-cell histograms are recovered via four-corner rectangle sums
> on the precomputed planes. Realized speedup on 256x256 / 32x32 /
> stride 8 (841 windows): **~2.15x absolute** (range 2.11x to 2.40x
> across 5 runs). Bit-identical detection list to the scalar path
> across positive / negative / self-match / dense-scan / end-to-end
> fixtures. Opt-in via `CE_DETECTOR_INTEGRAL=on`. Documented in
> [`IMAGE_AUDIT.md`](./IMAGE_AUDIT.md),
> +1 from
> `io/transducers/image_detector.nova` added in R15C HOG-based
> sliding-window object detector -- the canonical Dalal-Triggs
> (CVPR 2005) pedestrian pipeline built on R14D's HOG descriptor.
> A linear-SVM classifier is the original Dalal-Triggs choice;
> CrossEngin's no-training-data design substitutes TEMPLATE
> MATCHING via the existing `hog_compare` L1 distance: every
> candidate window's HOG is compared against a single template HOG
> (extracted from a positive example), and windows within a
> distance threshold are accepted. `det_train_template(image, w, h,
> win_w, win_h)` returns the template HOG; `det_sliding_window(
> image, w, h, template, threshold_milli, stride)` walks (x, y) at
> the requested stride (4..32, default 8); `det_nms(detections,
> box_size, iou_milli)` sorts by ascending distance and greedily
> drops overlapping windows (default IoU = 300 milli, Dalal-Triggs's
> 0.30); `det_detect(...)` ties them together using the template's
> dimensions for NMS box geometry. New chat admin: `/detect
> TEMPLATE.pgm SCENE.pgm` -> `(detect N detection(s); T=WxH S=WxH
> stride=S best=DIST at (X, Y))`. New per-image atom:
> `image_detector_count_<none|one|few|many>` (emitted when
> `CE_VP_DETECT_TEMPLATE` env points at a template PGM). The
> integration scenario asserts detection at a known (16, 16) offset
> within +/- stride accuracy and 0 detections on a uniform-gray
> scene. Documented in [`IMAGE_AUDIT.md`](./IMAGE_AUDIT.md),
> +1 from
> `io/transducers/image_face_detect.nova` added in R16D Viola-Jones-
> style Haar cascade face detector (STRUCTURAL only -- see scope
> disclaimer). Adds the integral-image primitive (Crow 1984) -- O(1)
> rectangle sums via the four-corner formula, reusable downstream
> for HOG-with-integral-histogram-of-gradients -- plus two-/three-/
> four-rect Haar feature evaluators (canonical Viola-Jones
> definitions) + a hand-crafted 3-stage cascade tuned for the
> "dark eye-strip / light cheek-strip / dark chin-strip" pattern +
> multi-scale sliding window (1.25x scale-up per octave) + IoU-0.30
> NMS clustering. Without a real trained cascade (OpenCV's
> `haarcascade_frontalface_default.xml` ships ~3,000 weak
> classifiers across 25 AdaBoost stages, untrainable in CrossEngin's
> no-training-data design), accuracy on REAL PHOTOGRAPHS will be
> POOR -- the structural-implementation purpose is to provide the
> integral-image primitive + cascade shell a trained classifier
> would slot into. New chat admin: `/faces PATH.pgm` ->
> `(faces N detection(s); WxH min=S max=S step=S best_score=K at
> (X, Y) size=S)`. New per-image atom:
> `image_face_count_<none|one|few|many>` (emitted when
> `CE_VP_FACE_DETECT=1`). The integration scenario asserts >= 1
> detection on a synthetic dark/light/dark horizontal-band fixture
> and 0 on uniform-gray. Documented in
> [`IMAGE_AUDIT.md`](./IMAGE_AUDIT.md),
> +1 from
> `io/transducers/image_lbp.nova` added in R17D LBP (Local Binary
> Patterns, Ojala 1996) texture descriptor -- the classic non-DL
> face / texture DESCRIPTOR (Ahonen et al. 2006, "Face Recognition
> with Local Binary Patterns") that complements R16D's Viola-Jones
> face DETECTOR. Per-pixel 3x3 neighborhood comparison packs 8
> threshold bits clockwise from top-left into a single byte; the
> histogram of those bytes over a region is the descriptor. Public
> API: `lbp_compute_image / lbp_at / lbp_histogram / lbp_descriptor /
> lbp_compare` (chi-squared) `/ lbp_compare_intersection /
> lbp_dominant_code / lbp_texture_entropy_milli`. Descriptor on a
> 32x32 image with cells=4x4 returns 4096 ints (4 x 4 cells x 256
> bins); self-match chi-squared distance is 0; rotation produces a
> DIFFERENT descriptor (basic LBP is NOT rotation-invariant,
> documented in the algorithm header and unit-tested -- contrast
> with SIFT / ORB which ARE rotation-invariant). New chat admin:
> `/lbp PATH.pgm` -> `(lbp WxH dominant_code=C entropy=E_milli)`.
> New per-image atoms:
> `image_lbp_dominant_code_<uniform_bright|uniform_dark|bright|dark|mixed|none>`
> and `image_lbp_texture_<peaked|mid|distributed>` (emitted in the
> structural-features path when image >= 32x32). Documented in
> [`IMAGE_AUDIT.md`](./IMAGE_AUDIT.md),
>
> `io/transducers/image_face_recognize.nova` added in R18D LBP-
> gallery face RECOGNITION (identity matching). Where R16D answers
> "is there a face?" (Viola-Jones detection) and R17D's LBP
> describes "what does this face look like?" as a 4096-int feature
> vector, R18D answers "which face is this?" by chi-squared
> comparing the query descriptor against a small operator-maintained
> gallery of enrolled identities. Public API:
> `face_gallery_new / face_gallery_enroll / face_gallery_recognize /
> face_gallery_save / face_gallery_load / face_gallery_size /
> face_gallery_clear`. Gallery cap = 128 entries; chat default
> threshold = 500 chi-squared units. Save/load uses an ASCII
> line-oriented format (`CE_FACE_GALLERY_V1` magic + entry count +
> per-entry label/desc_len/desc_values) that is bit-identical round-
> trip safe. New chat admins: `/face_enroll <label> <pgm>` enrolls
> a face under a label (idempotent on label -- re-enrollment
> overwrites); `/face_recognize <pgm>` runs the nearest-neighbor
> match and prints either `(face_recognize matched=<label>
> distance=<D> threshold=500)` or `(face_recognize unknown
> distance=-1 threshold=500)`. Documented in
> [`IMAGE_AUDIT.md`](./IMAGE_AUDIT.md),
> unchanged from the snapshot
> v1 -> v2 migration session -- the bump landed inside the existing
> `persistence/snapshot_{writer,disk,reader}.nova` trio +
> `examples/migrate_snap.nova` (NEW) +
> `scripts/migrate_snapshot.sh` (NEW) + `SNAPSHOT_FORMAT.md` (NEW). The
> v2 format adds an OPTIONAL
> `meta.{creator,created_ns,compaction_threshold,encryption}` block; a v1
> file migrates transparently via `snap_migrate_v1_to_v2`, and v3+ files
> are rejected loudly with an upgrade-required diagnostic. +1 from
> `io/transducers/image_canny.nova` added in P3.3 cont. Canny edge
> detection -- the canonical edge detector after Sobel + Harris + SIFT.
> Pure-NOVA Gaussian 3x3 smoothing + signed Sobel gradients + non-maximum
> suppression along the gradient direction + 8-connected hysteresis
> worklist flood-fill with LOW=50 / HIGH=100 milli-normalized magnitude
> thresholds; produces single-pixel-wide edges (strict subset of Sobel's
> above-threshold set) and the `image_canny_edges_<low|mid|high>` feature
> atom on images >= 32x32. Documented in
> [`IMAGE_AUDIT.md`](./IMAGE_AUDIT.md),
> +1 from
> `safety/bignum_256.nova` added in R6B Montgomery REDC mirror for the
> 256-bit case -- a parallel `bn256_*` prefix to the existing `bn_*`
> from `bignum.nova` with CIOS-form Montgomery REDC backing
> `bn256_modpow_ct`. Observed **~14x speedup** vs the legacy
> bit-by-bit reducer (Mont ~3.1 ms vs Legacy ~45 ms) on the
> Curve25519 prime with the full 254-bit `p-1` exponent; the
> headline Fermat check `bn256_modpow_ct(2, p-1, p) == 1` passes in
> ~3.1 ms wall-clock. Same INTENTIONAL OMISSION as bignum_2048: no
> non-CT `bn256_modpow` (the existing `bn_modpow` in `bignum.nova`
> covers the offline-only case). The new prefix is ship-able alongside
> the legacy `bn_*` without touching any in-use call site;
> `bn256_curve25519_p()` exposes the Curve25519 field prime
> `p = 2^255 - 19` lazily. **R7B realized this speedup in production**
> by migrating `src/learning/secure_aggregation.nova`'s DH-256 path
> (`sa_dh_generate_keys` + `sa_dh_shared_secret_for_peer`) from
> `bn_modpow_ct` to `bn256_modpow_ct`: measured 2-soul-pair DH round
> drops from **~260 ms to ~12.9 ms** (~20x), per-modpow_ct
> ~65 ms -> ~3.2 ms; all 142 unit tests + scenario_u_secagg's 48
> assertions still pass bit-identically (wire format unchanged --
> `bn_*` and `bn256_*` share the same 8 x 32-bit limb layout and
> 64-char hex serialization). +1 from
> `safety/bignum_2048.nova` added in P3.9 cont. 2048-bit DH on RFC 7919
> Group 14 -- the cryptographically-reasonable upgrade to the 256-bit
> v2-sa-dh strawman SECAGG_AUDIT.md flagged as broken; **extended in
> R4D with Montgomery REDC (CIOS form) for ~10x speedup**. The bn2048
> module is a 64-limb (32-bit-per-limb) pure-NOVA bignum parallel to
> `bignum.nova`; only `bn2048_modpow_ct` (Montgomery ladder, now backed
> by Montgomery REDC under the hood) is exposed -- the non-CT variant
> is intentionally omitted because a 2048-bit private exponent can't
> safely tolerate any timing leak. RFC 7919 Group 14 constants land as
> `rfc7919_group14_p()` and `rfc7919_group14_g()`. Verified by the
> headline Fermat's-little-theorem check `bn2048_modpow_ct(2, p-1, p)
> == 1` (~**1.2s wall-clock**, was ~15s pre-Mont).
> `src/learning/secure_aggregation.nova` extended with
> `sa_dh_generate_keys_2048` / `sa_dh_shared_secret_for_peer_2048` +
> the `CE_SECAGG_DH_2048` env flag + a SA_DH_BITS state slot routing
> `sa_mask_for_peer` to the right shared-secret derivation. The chat
> gates on a single `CE_SECAGG_DH_2048` env probe; everything else runs
> through the existing v2-sa-dh pipeline. Cost reality (post-Mont):
> 2-soul DH-2048 round = ~**8.7s wall-clock** (was ~60s); integration
> scenario U.dh2048 completes in ~**19s** end-to-end (was ~141s),
> +1 from
> `io/transducers/audio_capture.nova` added in P2.5 cont. real microphone
> capture (parecord/arecord/sox auto-detect via `scripts/audio_capture.sh`
> + silent-WAV fallback) wired into `stream_audio.nova` via the
> `CE_AUDIO_CAPTURE_CMD=auto` sentinel,
> +1 from `io/transducers/jpeg_decode.nova` added in P3.1.JPEG minimum-viable
> JPEG modality -- structural-half pure-NOVA parser (segment markers + DQT +
> SOF0 + DHT tables); **P3.1.JPEG cont. this session: entropy decode + IDCT
> pipeline shipped** -- canonical Huffman build (T.81 Annex C) + MSB-first
> bit reader with 0xFF 0x00 byte-stuffing + DC differential / AC RLE
> decoder + dequant + un-zig-zag + separable 8x8 integer IDCT (10-bit
> fixed-point cosine table) + MCU block assembly, all wired into
> `_jpeg_decode_scan`. `jpeg_decode_grayscale(path)` now returns real
> pixel data for baseline-sequential 8-bit single-component JPEGs up to
> 512x512; pixel values match libjpeg/Pillow within +/-3. The visual
> seam (`_vp_decode_jpeg`) feeds decoded buffers through the same
> `vp_features_for_image` surface PGM/PNG use. See
> [`JPEG_AUDIT.md`](./JPEG_AUDIT.md) for the full pipeline notes;
> +1 from `safety/bignum.nova`
> added in P3.9 pure-NOVA 256-bit unsigned bignum library -- the DH
> key-exchange prerequisite the federated SecAgg MVP could not ship
> without (Item 6 of the brief), now landed as a leaf primitive
> alongside `chacha20.nova` and `poly1305.nova`; documented in
> [`SECAGG_AUDIT.md`](./SECAGG_AUDIT.md). **P3.8r extension:**
> `src/learning/secure_aggregation.nova` extended with
> dropout-resilience -- the `sa_recompute_without` /
> `sa_reconcile_for_dropped` pair, FED_DROPOUT + FED_RECON_MASKED wire
> formatters + parsers, and the `CE_FED_ROUND_DEADLINE_MS` env helper
> (default 5000 ms). The 3-soul A/B/C round where B drops mid-round
> now ends with the coordinator's sum equal to x_A + x_C exactly (no
> garbage mask residue), shipped without adding a new module --
> dropout resilience moved from "limitations" to "shipped" in
> SECAGG_AUDIT.md.
> **P3.9 extension (this session):** `bn_modpow_ct` (Montgomery ladder;
> constant-time per bit) added to `src/safety/bignum.nova` so DH/ECDH
> private exponents can be exported to remote-callable paths without
> leaking via wall-clock timing. **DH key agreement landed (v2-sa-dh):**
> `src/learning/secure_aggregation.nova` extended with
> `sa_dh_generate_keys` / `sa_dh_shared_secret_for_peer` /
> `sa_register_peer_dh` + FED_DH_PUBLIC wire format/parse/dispatch +
> the `CE_SECAGG_DH` env flag; the coordinator collects soul pubkeys
> during the handshake and broadcasts them back via the new
> `_fed_broadcast_dh_pubkeys` phase; the chat soul gates on a single
> `CE_SECAGG_DH` env probe and the rest of the path runs through the
> existing v2-sa pipeline (the DH-derived shared secret slots in where
> the pre-shared token used to). Caveats called out loudly in
> SECAGG_AUDIT.md: 256-bit DH prime + weak-random private-key generation
> + `p_25519` is a field prime not a safe DH prime -- the MVP
> demonstrates the wire protocol + flow, not the cryptographic
> strength,
> +1 from `kg/ann_index.nova`
> added in P3.4 LSH approximate-nearest-neighbor over atom embeddings,
> +1 from `realtime_pacer.nova`
> added in P0.6 wall-clock pacer, +1 from `http_client.nova` added in P1.4
> plain-HTTP in-process transport seam,
> +3 from `safety/{chacha20,poly1305}.nova` + `io/transducers/secure_channel.nova`
> added in the P1.4 PSK secure-channel continuation -- pure-NOVA
> ChaCha20-Poly1305 (RFC 7539) over TCP as a "noise envelope" alternative to
> TLS framing, documented in [`TLS_AUDIT.md`](./TLS_AUDIT.md), +4 from `seed/pack_registry.nova` +
> `seed/packs/{medical,ops_runbook,code_review}_pack.nova` added in P1.9
> domain seed packs, +2 from `reader/cofire_index.nova` +
> `reader/slot_index.nova` added in P2.1/P2.2 co-fire + syntactic-slot
> similarity side-indices, +3 from
> `io/transducers/stream_{stdin,unix_socket,http}.nova` added in P2.8
> real-time streaming event sources,
> +1 from `persistence/snapshot_compaction.nova` added in P2.10 snapshot
> compaction pass,
> +1 from `persistence/snapshot_delta.nova` added in R13F incremental
> delta snapshots -- the writer / reader / fingerprint-guard / compactor
> for sibling `.delta.NNN` files alongside a full snapshot, so the hot
> path drops from O(KG-size) bytes per save to O(changed) bytes. Wired
> into `snapshot_disk.nova` via 5 additive entry points
> (`snap_make_delta_writer`, `snap_delta_save`, `snap_load_with_deltas`,
> `snap_delta_compact`, `snap_delta_count_for`); R8E schema migration
> + R6F episodic preservation interop confirmed. Measured 4x speedup on
> a 5000-atom KG (full ~13 ms vs delta ~3 ms; the 1000-atom case is
> fsync-floor-bound at ~1.6x). Documented in
> [`SNAPSHOT_FORMAT.md`](./SNAPSHOT_FORMAT.md).
> +2 from `io/transducers/{stt_seam,stream_audio}.nova` added in P2.5
> STT framework + audit,
> +1 from `parts/reasoning/proof_checker.nova` added in P3.5 minimum
> viable proof checker,
> +1 from `safety/differential_privacy.nova` added in P3.6 minimum-viable
> differential privacy at the KG-query surface (integer Laplace mechanism +
> per-session epsilon-budget accountant, ADR-0053 -- documented in
> [`DP_AUDIT.md`](./DP_AUDIT.md)),
> +1 from `safety/dp_budget_ui.nova` added in R12F operator-facing
> DP budget reporting -- ASCII bar / status / log / warn / reset
> presentation layer on top of the R12F query-log + warn-threshold
> slots in `differential_privacy.nova`, with the chat-side `/dp
> <subcommand>` admin command and a one-line `dp       :` row in
> `/status` (documented in the R12F follow-up section of
> [`DP_AUDIT.md`](./DP_AUDIT.md)),
> +2 from `io/transducers/{image_pgm,visual_perception}.nova` added in P3.1
> minimum-viable image modality -- pure-NOVA PGM-P5 decoder + pluggable
> visual perception seam producing feature atoms, documented in
> [`IMAGE_AUDIT.md`](./IMAGE_AUDIT.md),
> +1 from `io/transducers/image_sift.nova` added in P3.3 cont. SIFT
> keypoint DETECTION (scale-space + DoG extrema; the P3.3 cont. v2
> follow-up landed the 128-D descriptor + Lowe-ratio-test matcher
> in the SAME module) -- 3-octave Gaussian pyramid, 5 blur levels
> per octave, 4 DoG layers, 3x3x3 spatial-and-scale extremum check,
> contrast threshold 30 milli-normalized + Harris-style edge rejection
> reusing `harris_apply` from R1.6; the descriptor pass walks a 16x16
> window around each keypoint, builds a 4x4 grid of 8-bin direction
> histograms (Gaussian-weighted by distance), normalizes to L2 =
> 1000 milli, caps at 200 milli, and re-normalizes; producing the
> `image_keypoint_count_<low|mid|high>` and
> `image_descriptors_<low|mid|high>` feature atoms on images >= 32x32
> plus the new `/match_images A B` admin command for image-to-image
> keypoint correspondence (object recognition / image stitching /
> motion tracking foundation), documented in
> [`IMAGE_AUDIT.md`](./IMAGE_AUDIT.md),
> +2 from `io/transducers/{video_y4m,video_perception}.nova` added in P3.2
> minimum-viable video modality -- pure-NOVA Y4M (raw YUV4MPEG2) decoder +
> pluggable video perception seam producing per-frame feature atoms +
> motion / scene-change labels, surfaced via the chat `/play PATH [N]`
> admin command and the `scripts/video_to_y4m.sh` ffmpeg shim for
> compressed video input, documented in [`VIDEO_AUDIT.md`](./VIDEO_AUDIT.md),
> +1 from `learning/federated_aggregator.nova` added in P3.7
> minimum-viable federated multi-soul learning -- per-soul DP-noised
> per-source promotion/atrophy rates + coordinator-side aggregation +
> EMA pull toward the federation mean, surfaced via the chat
> `/fed_join` / `/fed_stats` / `/fed_leave` admin commands and the
> `bin/crossengin-fed-coordinator` daemon, documented in
> [`FEDERATED_AUDIT.md`](./FEDERATED_AUDIT.md)), 142 unit-test suites pass
> (`make test`,
> +1 suite / +84 assertions from `test_snapshot_delta.nova` added in
> R13F incremental delta snapshots: writer accumulation (ADD/MOD/DEL),
> text round-trip with empty / single-op / multi-op blobs, parse
> hardening (missing-trailer / bad-header rejected), apply semantics
> (ADD creates via replace-by-label, MOD patches alpha/beta, DEL
> calls kg_remove_atom, unknown-KG silently skipped), fingerprint
> guard (mismatched parent_snapshot refused, matching parent accepted),
> multi-delta sequencing, path layout (3-digit zero-padded
> `.delta.NNN`), enumeration (contiguous range + gap-stop), disk
> round-trips (parent-only / one delta / three deltas), compaction
> (below-threshold no-op + collapse 10 deltas + prune), R8E schema
> migration interop (atoms reach SCHEMA_CURRENT_VERSION post-delta-
> apply), R6F episodic preservation (parent's episodic moment survives
> the delta + compact round-trip), `snap_make_delta_writer`
> convenience. Integration scenario `scenario_fff_snap_delta.sh`
> (+14 assertions) benches a 1000-atom KG showing delta is ~1.6x
> faster than full on tmpfs (fsync-floor-bound at this size) and ~4x
> faster on a 5000-atom KG. Documented in
> [`SNAPSHOT_FORMAT.md`](./SNAPSHOT_FORMAT.md),
> +1 from `scenario_ggg_hog.sh` added in R14D HOG dense descriptor:
> /help advertises /hog; /hog with no arg prints usage; /hog on
> missing file surfaces parser error; /hog on too-small (8x8) image
> prints the minimum-dim error; /hog on a 32x32 four-spots fixture
> returns a valid `(hog 32x32 cells=16 dominant_bin=4 magnitude_mean=N)`
> tuple; /hog on a 32x32 vertical-edge fixture returns dominant_bin=0
> (horizontal gradient direction); the two fixtures produce different
> dominant bins (HOG separates clustered corners from single-direction
> edges); magnitude_mean > 0 on edge fixture; cells=16 matches the
> expected 4x4 cell grid; the chat survives all probing and reaches
> /quit cleanly. Documented in
> [`IMAGE_AUDIT.md`](./IMAGE_AUDIT.md),
> +1 suite / +34 assertions from `test_orb.nova` added in P3.3 cont. v3
> ORB feature detector + Hamming-distance matcher: FAST-9 4-corner
> detection on a 40x40 four-spots fixture surfaces 96 keypoints; orb
> self-match yields 96 matches at Hamming distance 0; identical
> descriptors -> 0; fully flipped 8-chunk descriptors (256-bit XOR =
> all ones) -> Hamming 256; single-bit difference -> 1; cross-fixture
> spots-vs-vertical-edge -> 0 matches (Harris filter rejects every FAST
> candidate on a straight edge); 90-degree rotated four-spots -> at
> least 1 match survives at ratio 900 milli (rotation invariance via
> the intensity-centroid orientation + cos/sin rotation table); too-
> small (16x16), too-large (300x300), null data_ptr, zero-width all
> return 0 keypoints; matcher edge cases (empty inputs, < 2 candidates
> in B, size-mismatch descriptors) all return empty / -1; count-bucket
> labels + density labels round-trip; orb_kp_x/y/angle/score
> accessors return values in expected ranges. Documented in
> [`IMAGE_AUDIT.md`](./IMAGE_AUDIT.md),
> +1 suite / +22 assertions from `test_image_canny.nova` added in
> P3.3 cont. Canny edge detection: uniform 32x32 -> 0 edges; vertical
> step -> 30 edges (single-column NMS-thinned from Sobel's 60); diagonal
> step -> edges along |x-y| <= 2; hysteresis bridge fixture -> chain of
> weak pixels kept; **Canny edges are a STRICT SUBSET of Sobel edges**
> (every kept Canny pixel lands on a non-zero Sobel magnitude;
> canny_n <= sobel_count); density-milli math + density-label
> round-trip; dimension cap (>512) rejects without crashing; too-small
> (2x2) images return empty edge list; result-tuple accessors work,
> documented in [`IMAGE_AUDIT.md`](./IMAGE_AUDIT.md),
> +1 suite / +55 assertions from `test_image_hog.nova` added in R14D
> HOG (Histogram of Oriented Gradients) dense descriptor: uniform 32x32
> -> all-zero per-cell histograms (degenerate); vertical-edge fixture ->
> dominant bin 0 (horizontal gradient); horizontal-edge fixture ->
> dominant bin 4 (vertical gradient); diagonal-edge fixture -> dominant
> bin in {2, 6}; L2-Hys invariant -- every block component <= 200
> milli post-final-clip; sum_sq in expected range; `hog_compare` ==
> 0 on identical images, >= 2000 milli on a 90-deg rotated copy
> (**HOG is NOT rotation-invariant** -- the documented trade-off
> versus SIFT/ORB), and SMALLER than rotation on a 1-px translation;
> per-cell-histogram OOB queries return the empty list sentinel;
> oversized (300x300) / zero-pointer / invalid-cell-size (5) /
> invalid-num-bins (7) / too-small (8x8) inputs return the empty
> result; 32x32 descriptor length = 324, 64x64 = 1764; cell_size=4
> and num_bins=6 alternative configurations work; dominant-bin and
> descriptor-size label round-trips. Documented in
> [`IMAGE_AUDIT.md`](./IMAGE_AUDIT.md),
> +1 suite / +87 assertions from `test_jpeg_decode.nova` covering
> P3.1.JPEG structural parser + P3.1.JPEG cont. entropy decode + IDCT
> pipeline: in-memory baseline-grayscale fixture builder; segment
> iteration walks SOI/APP0/DQT/SOF0/DHT/SOS/EOI; DQT/SOF0/DHT parsing;
> canonical Huffman table build + bit reader; 8x8 IDCT (all-zero block
> -> 128 everywhere, DC-only block -> uniform value); dequant + un-zig-zag
> round-trip; end-to-end `jpeg_decode_grayscale_bytes` on a synthetic
> 16x16 stream; real-Pillow first-pixel match within +/-3 of libjpeg;
> rejects oversized dims (> 512 decode cap, > 1024 structural), SOF2
> (progressive), and bad SOI; documented in
> [`JPEG_AUDIT.md`](./JPEG_AUDIT.md),
> +1 suite / +46 assertions from `test_deflate.nova` added in
> P3.1.PNG full DEFLATE inflate -- extends the Item-3 stored-only
> path (BTYPE=00) with RFC 1951 BTYPE=01 static Huffman + BTYPE=02
> dynamic Huffman so the pure-NOVA PNG decoder ingests any standard
> grayscale-8 PNG from a camera, phone, screenshot tool, or web
> download (zlib level 0..9 all decode). Test coverage: stored-
> block regression; static "hello" round-trip; static empty block;
> 8 'a' overlapping copy (length > distance); 12 'A' + 'B' and
> 12 'X' length-extra-bits; HELLO + 270 X + HELLO + 5 Y multi-byte
> distance (> 256); a 22,500-byte dynamic-Huffman pangram round-
> trip; BTYPE=11 reserved rejection. Documented in
> [`IMAGE_AUDIT.md`](./IMAGE_AUDIT.md),
> +1 suite / +25 assertions from `test_image_sift.nova`
> added in P3.3 cont. SIFT keypoint DETECTION: uniform-grey 32x32 -> 0
> keypoints; single bright 5x5 spot at (13,13) in 32x32 -> 1 keypoint at
> (15,15) with contrast 55; 32x32 four-spots fixture -> 4 keypoints
> (one per spot) at the spot centers; dimension caps reject < 32x32 and
> > 256x256; per-keypoint accessors round-trip; max_keypoints cap
> honored, documented in [`IMAGE_AUDIT.md`](./IMAGE_AUDIT.md),
> +1 suite / +28 assertions from `test_sift_descriptor.nova` added
> in P3.3 cont. v2 SIFT 128-D descriptor + matcher (the previously-
> deferred descriptor + matching half of Lowe 2004): descriptor L2
> norm ~= 1000 milli on a bright-spot keypoint, component cap honored,
> distance to self == 0, structurally-different fixtures > 200 milli
> apart, rotated copy stays structurally similar (< 2263 milli max
> theoretical), Lowe-ratio-test pass on a clear best match + reject on
> an ambiguous pair + reject with < 2 candidates, keypoint-list matcher
> self-pairing, empty-input / size-mismatch / null-data / tiny-image /
> uniform-image rejection, edge-keypoint window shift, sift_describe_all
> parallel-list shape, known-diff descriptor distance == 1000,
> documented in [`IMAGE_AUDIT.md`](./IMAGE_AUDIT.md),
> +1 suite / +66 assertions from `test_bignum.nova` added in
> P3.9 pure-NOVA 256-bit bignum library: `bn_new` / `bn_from_int` /
> `bn_from_hex` / `bn_to_hex` / `bn_zero` / `bn_eq` / `bn_cmp` / `bn_add`
> / `bn_sub` / `bn_mul` (full 512-bit product as `[hi, lo]`) / `bn_mod`
> / `bn_modmul` / `bn_modpow`, with the textbook `2^10 mod 1000 = 24`
> and the Curve25519 prime sanity check `2^255 mod (2^255-19) = 19`
> verified end-to-end. The const-time follow-up `bn_modpow_ct`
> (Montgomery ladder; +12 of the 66 assertions: equivalence with
> `bn_modpow` on a 100-vector deterministic sweep + textbook +
> Curve25519 + timing-comparison report) closes the side-channel
> leak on the exponent's Hamming weight so DH/ECDH private-key
> exponents can be exported to remote-callable paths without leaking
> via wall-clock timing. `bn_modpow` is now documented loudly as
> "fast, side-channel-unsafe; offline self-tests only";
> `bn_modpow_ct` is the crypto-safe variant consumers must use for
> any private exponent. Documented in
> [`SECAGG_AUDIT.md`](./SECAGG_AUDIT.md) ("bignum landed; DH key
> exchange unblocked + shipped as v2-sa-dh"),
> (and `test_bignum_2048.nova` from P3.9 cont. extended in R4D
> for Montgomery REDC: now **65 assertions** total, +7 new for the
> mont-ctx round-trip, mont == legacy equivalence on small N=1009,
> and the speedup-ratio measurement on RFC 7919 Group 14. The
> headline check Fermat's little theorem on the safe prime
> `bn2048_modpow_ct(2, p-1, p) == 1` -- now ~1.2s wall-clock under
> Montgomery REDC, was ~15-18s pre-Mont; **~10x speedup** measured
> end-to-end. The 2-soul DH-2048 pair-equivalence test in
> `test_secure_aggregation.nova` drops from ~60-140s to ~8.7s.
> Documented in [`SECAGG_AUDIT.md`](./SECAGG_AUDIT.md)
> ("Montgomery REDC landed; timing reduced from ~18s to ~1.2s
> per modpow_ct")),
> +1 suite / +70 assertions from `test_bignum_256.nova` added in R6B
> Montgomery REDC mirror for the 256-bit case: full coverage of the
> new `bn256_*` API (`bn256_new` / `bn256_from_int` / `bn256_from_hex` /
> `bn256_to_hex` / `bn256_eq` / `bn256_cmp` / `bn256_add` / `bn256_sub` /
> `bn256_mul` / `bn256_mod` / `bn256_modmul` / `bn256_modpow_ct` plus
> the Montgomery primitives `bn256_mont_ctx_new` / `bn256_to_mont` /
> `bn256_from_mont` / `bn256_montmul` / `bn256_modpow_ct_mont` and the
> legacy equivalence anchor `_bn256_modpow_ct_legacy`); the headline
> Fermat check `bn256_modpow_ct(2, p-1, p) == 1` on the Curve25519
> prime; mont == legacy equivalence on 2 pseudo-random vectors at
> small N=1009 PLUS one cross-check on the Curve25519 prime with an
> arbitrary 64-bit exponent; speedup-ratio measurement on the
> Curve25519 prime with the full 254-bit `p-1` exponent reporting
> **~14x speedup** (Mont ~3.1 ms vs Legacy ~45 ms),
> +1 suite / +27 assertions from `test_realtime_pacer.nova`
> added in P0.6 real-time wall-clock pacer,
> +1 suite / +37 assertions from `test_decision_log_durable.nova` added in
> P0.7 decision-log durable path,
> +3 suites / +132 assertions from `test_snapshot_{episodic,synapses,
> selfmodel}.nova` added in P0.1 full-state persistence,
> +2 suites / +82 assertions from `test_meta_observer_feedback.nova` +
> `test_atom_death_attribution.nova` added in P1.1 meta-observer feedback
> into source_authority + P1.6 atom-death attribution,
> +18 assertions to `test_learn_tag.nova` (22 -> 40) from P1.5 composite
> `/learn` kinds: batch `@/path/urls.txt`, RSS `rss:URL`, recursive
> `dir:/path` directory walk,
> +1 suite / +59 assertions from `test_http_client.nova` added in P1.4
> plain-HTTP client + dispatcher,
> +3 suites / +51 assertions from `test_chacha20.nova` (26),
> `test_poly1305.nova` (9), `test_secure_channel.nova` (16) added in the
> P1.4 PSK secure-channel continuation -- RFC 7539 ChaCha20 + Poly1305
> primitives plus the per-frame PSK envelope, documented in
> [`TLS_AUDIT.md`](./TLS_AUDIT.md),
> +33 assertions added to `test_secure_aggregation.nova` (93 -> 126; further
> extended to 157 in P3.9 DH key agreement below: 2-soul DH-derived
> pair-mask match, full 2-soul DH sum demo, FED_DH_PUBLIC wire
> formatter + parser + dispatch, default-off `CE_SECAGG_DH` env probe,
> `sa_register_peer_dh` idempotency, `sa_dh_generate_keys` validity --
> all of which exercise `bn_modpow_ct` on 256-bit private exponents
> via DH commutativity)
> in P3.8r dropout-resilience: 3-soul A/B/C round where B drops mid-
> round; A + C reconcile by removing m_AB and m_BC mask contributions;
> coordinator's sum equals x_A + x_C exactly (200, the brief's
> expected). Plus signed-mask `sa_recompute_without` determinism +
> sign-mirror invariants across paired souls; FED_DROPOUT +
> FED_RECON_MASKED wire formatter / parser shapes (including signed-
> integer adjusted values for the residual-flips-sign case); top-
> level dispatch through `sa_parse_line` for the two new events;
> default `CE_FED_ROUND_DEADLINE_MS=5000` env helper,
> +4 suites / +73 assertions from `test_pack_registry.nova` +
> `test_medical_pack.nova` + `test_ops_pack.nova` +
> `test_code_review_pack.nova` added in P1.9 domain seed packs,
> +2 suites / +58 assertions from `test_cofire_index.nova` +
> `test_slot_index.nova` added in P2.1/P2.2 co-fire + syntactic-slot
> similarity side-indices, plus +15 assertions to
> `test_neighborhood_activation.nova` (30 -> 45) covering
> `find_neighbors_full` with the two new index sources,
> +1 suite / +28 assertions from `test_stream_stdin.nova` added in P2.8
> real-time streaming event sources,
> +1 suite / +48 assertions from `test_snapshot_compaction.nova` added in
> P2.10 snapshot compaction pass,
> +1 suite / +46 assertions from `test_ann_index.nova` added in P3.4
> LSH approximate-nearest-neighbor over atom embeddings (40x speedup
> over linear cosine scan at 1000 atoms, K=8 hyperplanes / 256 buckets;
> see `tests/benchmark/bench_ann_query.nova`),
> +1 suite / +26 assertions from `test_stt_seam.nova` added in P2.5
> STT framework + audit -- the speech-to-text half of the audio
> modality bridge, pluggable behind `EV_MESSAGE` -- documented in
> [`STT_AUDIT.md`](./STT_AUDIT.md), with `scripts/transcribe.sh` as the
> auto-detecting subprocess shim and `src/io/transducers/stream_audio.nova`
> as the env-gated audio-capture source,
> +1 suite / +28 assertions from `test_audio_capture.nova` added in
> P2.5 cont. real microphone capture: state-struct defaults +
> hand-built canonical WAV round-trips (mono passthrough with KNOWN
> samples [100, 0, -200, 32000, -32000] at 16 kHz; 8 kHz / 44.1 kHz /
> 48 kHz sample-rate variants) + malformed-WAV rejection (bad RIFF
> magic / bad WAVE magic / non-PCM format / non-16-bit width /
> truncated header / missing file) + stereo-to-mono averaging,
> +1 suite / +55 assertions from `test_audio_vad.nova` added in R7F
> Voice Activity Detection: energy (sum of absolutes) + ZCR (sign
> flips) per 30 ms frame; 4-state hysteresis machine (SILENCE →
> SPEECH_CANDIDATE → SPEECH → SILENCE_CANDIDATE → SILENCE) with K=3
> speech-on / M=10 speech-off commit thresholds; thresholds scale
> linearly with frame_size so the same module works at 8/16/22.05/
> 44.1/48 kHz. Rejects pure-noise inputs via the ZCR ceiling
> (alternating ±3000 = max ZCR = silence verdict). R9B extended with
> +31 assertions for adaptive noise-floor calibration (MIN over
> leading 480 ms × 3 multiplier, R7F floor preserved bit-identical);
> total now 86 checks,
> +1 suite / +28 assertions from `test_whisper_backend.nova` added in
> R8B -- whisper.cpp STT backend wired into the seam: env-resolver
> fallback (default canonical install paths when CE_WHISPER_BIN /
> CE_WHISPER_MODEL are unset), openable-ness probe (uses sys_open as
> the access-proxy), three pre-flight error paths ("binary not
> found", "model not found", "wav not found"), transcript cleanup
> (trim whitespace + collapse internal newlines to single spaces +
> dedup runs of spaces, handles empty + all-whitespace input),
> result-tuple accessors, and a stt_seam round-trip through
> STT_BACKEND_WHISPER dispatch (verified via the seam's last_error
> surfacing the precise install gap),
> +1 suite / +56 assertions from `test_proof_checker.nova` added in P3.5
> minimum-viable proof checker -- bounded BFS over the operator graph
> returning audit-grade derivation traces with composed Bayesian
> confidence, surfaced via the chat `/prove PREMISE CONCLUSION [DEPTH]`
> admin command,
> +1 suite / +52 assertions from `test_differential_privacy.nova` added in
> P3.6 minimum-viable differential privacy at the KG-query surface --
> integer Laplace mechanism (Geometric-on-Z), per-session epsilon-budget
> accountant, `kg_atom_count_dp` / `kg_atom_belief_mean_dp` opt-in
> wrappers, surfaced via the chat `/dp_status` + `/dp_query atoms` admin
> commands, documented in [`DP_AUDIT.md`](./DP_AUDIT.md),
> +1 suite / +43 assertions from `test_image_pgm.nova` added in P3.1
> minimum-viable image modality -- pure-NOVA PGM-P5 binary decoder
> (header + raw bytes, no compression) with histogram / mean-intensity
> / nearest-neighbor resize / dominant-intensity bucket statistics
> and the pluggable `visual_perception.nova` seam producing crude
> feature atoms (image_dim_*, image_dark/mid/bright, image_bucket_*,
> image_hist_peaked/uniform); surfaced via the chat `/see PATH` admin
> command and the `scripts/image_to_pgm.sh` ImageMagick/ffmpeg shim
> for non-PGM input, documented in [`IMAGE_AUDIT.md`](./IMAGE_AUDIT.md),
> +1 suite / +34 assertions from `test_video_y4m.nova` added in P3.2
> minimum-viable video modality -- pure-NOVA Y4M raw-video decoder
> (ASCII header + per-frame iterator over the YCbCr planes, no
> compression) with mean-absolute-difference motion proxy across
> the luma plane, and the pluggable `video_perception.nova` seam
> producing per-frame feature atoms + motion_<low|mid|high> +
> scene_change labels; surfaced via the chat `/play PATH [N]` admin
> command and the `scripts/video_to_y4m.sh` ffmpeg shim for
> compressed video input, documented in [`VIDEO_AUDIT.md`](./VIDEO_AUDIT.md)),
> 27 end-to-end integration
> scripts run (`make integration`, +1 from `scenario_a3_dlog.sh` added in
> P0.7 dlog durability across SIGKILL, +1 from `scenario_a2_full_state.sh`
> added in P0.1 full-state persistence across SIGKILL, +2 from
> `scenario_h_session_switch.sh` + `scenario_i_web_isolation.sh` added in
> P0.8 chat /switch + web.py per-cookie routing,
> +1 from `scenario_j_http_client.sh` added in P1.4 plain-HTTP loopback
> against `python3 -m http.server`,
> +1 from `scenario_v_secure_channel.sh` added in the P1.4 PSK
> secure-channel continuation -- NOVA client opens a ChaCha20-Poly1305
> envelope over TCP against a Python counterpart
> (`scripts/secure_channel_echo.py`), sends "ping", asserts the decrypted
> reply equals "pong",
> +9 dropout-resilience assertions extending
> `scenario_u_secagg.sh` (P3.8r): scenario U.r spawns a 2-soul SecAgg
> round where a Python `scripts/secagg_smoke_soul.py` helper acts as
> the dropout peer (handshake then close); the surviving soul-helper
> emits FED_RECON_MASKED with the dropped peer's mask removed; the
> coordinator logs DROPOUT soul=bob, broadcasts FED_DROPOUT,
> collects the reconciled stat, and the final FED_AGGREGATE_SUM
> line carries the survivor's raw values exactly (sum_promo=100,
> sum_atr=50, n_part=1),
> +1 from `scenario_k_seed_pack.sh` added in P1.9 `/seed` domain pack
> install + listing,
> +1 from `scenario_m_metrics_endpoint.sh` added in P2.9 Prometheus
> text-format `/metrics` scrape endpoint over `scripts/web.py`,
> +1 from `scenario_l_stream_stdin.sh` added in P2.8 stdin streaming
> source acceptance test,
> +1 from `scenario_w_audio_capture.sh` added in P2.5 cont. microphone-
> capture end-to-end: `scripts/audio_capture.sh /tmp/...wav 1` produces
> a valid PCM-16 mono 16 kHz WAV (silent-fallback in the sandbox, real
> audio on hardware -- header magic-bytes + numeric-fields all verified
> via a one-shot Python parser); a tiny on-the-fly NOVA driver then runs
> `stream_audio_init_from_env` with `CE_AUDIO_CAPTURE_CMD=auto`, confirms
> the auto sentinel resolves to `use_auto=1`, `stream_audio_poll` invokes
> `audio_capture_record` end-to-end, the produced WAV is parsed by
> `audio_capture_to_pcm` (sample_rate=16000, samples non-empty), and the
> `EV_MESSAGE` post-path round-trips through the scheduler queue via
> `hs_post_event`,
> +1 from `scenario_ii_vad.sh` added in R7F VAD end-to-end: Klatt-
> synthesizes a 4-diphthong utterance ("AY EY OW OY") padded with
> leading/trailing silence, writes the WAV via `audio_write_wav`,
> reads back via `audio_capture_to_pcm_vad`, asserts >=1 speech segment
> + non-empty filtered PCM (4800 samples = the speech burst with K=3
> back-dating). Pure-silence WAV -> 0 segments + empty filtered PCM;
> pure-noise WAV (alternating ±3000 = max ZCR) -> 0 segments (ZCR
> ceiling rejects high-energy noise). Chat `/help` advertises
> `/listen`; `/listen <wav>` reports `vad_segments=N` and the active
> STT backend,
> +1 from `scenario_jj_whisper.sh` added in R8B whisper.cpp STT
> backend end-to-end: Klatt-synthesizes a 4-phoneme utterance,
> writes the WAV, calls `whisper_transcribe(bin, model, wav)`
> directly; asserts the pipeline runs without crash; then runs
> the bundled `jfk.wav` (16 kHz mono PCM16) through the same
> path and asserts the transcript contains "Americans" -- proving
> the whisper.cpp tiny.en model actually decoded English on top
> of NOVA's fork+exec/pipe2/dup2/read drain pipeline. Also
> exercises `stt_seam_new_whisper(model_path)` + the
> STT_BACKEND_STUB fallback (no whisper invocation on the stub
> path) + the seam's `last_error` surfacing precise install gaps.
> SKIPs gracefully if whisper-main / ggml-tiny.en.bin are not
> installed (10 of 13 assertions still run; the model-decode
> assertions are the optional 3),
> +1 from `scenario_oo_vad_natural.sh` added in R9B adaptive VAD +
> JFK end-to-end: synthetic silence -> 0 segments (R7F floor
> preserved when leading audio is exact-zero), synthetic noisy
> + speech -> 1 segment (adaptive threshold lifts above amp=200
> triangle lead-in noise without losing the amp=3000 speech burst),
> JFK 16 kHz WAV decoded by parser past the LIST/INFO sub-chunk
> -> 1 VAD segment + filtered PCM 170880 samples (~10.7 s of the
> 11 s clip), end-to-end `/listen JFK` reports `vad_segments=1`
> + transcript contains "fellow Americans" or "your country" +
> `backend=whisper`. SKIPs cleanly if the JFK WAV or whisper-main
> are not installed,
> +1 from `scenario_n_compaction.sh` added in P2.10 snapshot compaction
> pass: /save -> /teach 50 -> /compact -> /save shrinks file growth by
> >50% vs the baseline /save -> /teach 50 -> /save,
> +1 from `scenario_o_proof_checker.sh` added in P3.5 minimum-viable
> proof checker: /seed medical -> /prove headache hydration prints the
> headache -> dehydration -> hydration operator chain with composed
> confidence and visit/depth counters,
> +1 from `scenario_p_dp_budget.sh` added in P3.6 differential privacy
> at the KG-query surface: /dp_status initial budget -> 130 /dp_query
> atoms drains the 10000 milli-eps budget to zero (with true vs noisy
> count per call, noise variance > 0 across draws) -> /dp_query past
> exhaustion returns "budget exhausted",
> +1 from `scenario_q_image_see.sh` added in P3.1 minimum-viable
> image modality: hand-rolled 4x4 gradient + uniform-grey PGM
> fixtures, /see prints the operator-readable summary
> (dims + mean + dominant bucket + entropy) and the feature-atom
> labels (image_dim_small + image_mid + image_bucket_0 on the
> gradient; image_bright + image_hist_peaked + image_bucket_6 on the
> uniform fixture); malformed input is rejected with the parser's
> bracketed error and the chat survives to /quit cleanly, extended in
> P3.3 cont. (SIFT keypoint DETECTION) with +2 assertions covering a
> hand-rolled 32x32 four-spots PGM fixture: the summary line carries
> "32x32"; the feature line surfaces `image_keypoint_count_low` (4
> keypoints, below the low/mid threshold of 10),
> +1 from `scenario_s_video_play.sh` added in P3.2 minimum-viable
> video modality: a hand-rolled 5-frame 4x4 Y4M fixture with two
> forced scene changes, /play prints per-frame event lines (image
> features + motion + scene_change labels) and the operator-readable
> summary (`played PATH: N frame(s), <w>x<h>, motion=<...>, scene
> changes: 2, decoder=y4m`); /help advertises /play; malformed
> input is rejected with the parser's bracketed error and the chat
> survives to /quit cleanly,
> +1 from `scenario_r_federated.sh` added in P3.7 minimum-viable
> federated multi-soul: a coordinator daemon accepts a chat's
> FED_JOIN, opens round 1, collects the soul's noised FED_STAT batch,
> broadcasts FED_AGGREGATE, and the chat receives + EMA-blends the
> federation-wide rate back into local source_authority -- the
> framework piece of P3.7 with `FEDERATED_AUDIT.md` walking the
> trust model, composition, sybil, and convergence trade-offs,
> +1 from `scenario_aa_atom_search.sh` added in P-AA web atom-search:
> `python3 scripts/web.py` -> `GET /api/atoms?q=fever&limit=5` returns
> `{"atoms": [...]}` listing the fever concept atom and its three
> operator atoms; `GET /atoms` serves a tiny vanilla-JS HTML page
> (search box + KG filter + table); second `/api/atoms` call within
> the cache window confirms the `CE_ATOMS_CACHE_S` (default 30s)
> probe cache; 14 assertions,
> +1 from `scenario_bb_why_deep.sh` added in P-BB `/why-deep [N]`:
> `/teach widget` -> ask -> `/why-deep 3` prints a decision header,
> a `proof:` line (operator chain via P3.5 `proof_checker.nova`), an
> `activated by:` line surfacing the raw input, and an `upstream
> evidence:` section listing per-atom belief mean + source provenance
> (`user_taught` for `/teach` atoms, `seed` for first_atoms); 13
> assertions),
> three benchmarks report metrics
> (`make benchmark`), and six runnable artifacts build and run
> (`make install`): the substrate kernel self-check, the safety+IO+persistence
> companion spine, **`bin/crossengin` — the whole agent in one process**
> (substrate + knowledge + soul + goals + scheduler + IO + safety + persistence,
> no LLM), the distributed-substrate seam's two halves
> (`bin/crossengin-kg-publisher` / `bin/crossengin-kg-subscriber`), and the
> federated-coordinator (`bin/crossengin-fed-coordinator`, P3.7). The unified assembly was previously blocked by NOVA's import-path
> dedup (blocker #10); that is now **fixed in the toolchain** (path
> canonicalization — see [`NEXT_SESSION.md`](./NEXT_SESSION.md)). What remains is
> production hardening of the documented runtime seams (fsync-durable
> persistence, TLS fetch, STT/TTS bridge, a sub-second wall-clock pacer, SIMD) so
> the daemon can run continuously across real restarts. NEXT_SESSION.md records
> exactly what works, what does not, and where to continue.

## What works now (v1.0)

The Phase 1 substrate kernel (`src/substrate/`):

- **node_pool_manager** — the uniform leaky-integrate-and-fire node kernel over
  a pre-allocated pool, with novelty tracking and the integer milli-fixed-point
  convention (ADR-0006).
- **signal_dispatch** — the 18 `XSIG_*` signal types with ADR-0008 priorities
  and a priority-bucketed FIFO dispatch queue.
- **synapse_graph** — sparse weighted synapses with Hebbian + error-driven
  plasticity, eligibility decay, growth, and idle prune/reclaim (ADR-0007).
- **first_nodes** — stable per-part input blocks and modality presets (ADR-0010).
- **part_registry / part_lifecycle** — the seven fixed parts plus dynamic,
  per-domain KG parts (ADR-0001).
- **gate_router** — learned content-based routing with the privileged,
  non-learnable constitutional broadcast (ADR-0009, ADR-0045).
- **resonance_engine** — bidirectional co-activation reinforcement into stable
  assemblies.
- **tick_driver** — the four-phase substrate tick: snapshot → integrate →
  propagate → learn (ADR-0006, ADR-0001).

The Phase 3 knowledge layer (`src/kg/`):

- **atom_store** — the persistent knowledge atom with immutable (kg_id, id)
  identity, versioned mutation, and a Bayesian alpha/beta belief; also the
  shared milli belief + integer-cosine vector helpers (ADR-0016, ADR-0023).
- **multi_kg_manager** — per-domain knowledge graphs with embedding centroids
  (ADR-0004).
- **cross_kg_references** — automatic + earned cross-KG links and the
  spawn-on-new-domain heuristic (ADR-0017).
- **schemas** — entity-type validation with required/optional fields and
  min/max constraints (ADR-0018).
- **concept_layer** — the concept DAG with promotion, schema slots, facet
  vectors, members, and kg_span (ADR-0018).
- **skills_kg** — procedural skills (ATOM_SKILL) with Bayesian reliability,
  step rules, activation, and retirement (ADR-0019).
- **competence_tracker** — the self-model: per-domain competence (know/do/
  understand) computed from belief/skill/concept state, with four tiers
  (ADR-0020).

The Phase 2 language layer (`src/language/`) and reader (`src/reader/`):

- **word_atoms / phoneme_atoms / syntax_atoms** — words (with lexical vectors
  and weighted concept senses), phonemes, and ordered syntax patterns as
  ATOM_LANG atoms in a language KG (ADR-0015).
- **reader** (five stages, ADR-0011/0012, no LLM per ADR-0014):
  - **lexical_anchor** — tokenize and match to word atoms; SENSORY on a hit,
    CURIOSITY on an out-of-vocabulary token.
  - **context_bias** — resolve polysemy by similarity to the active context.
  - **spreading_activation** — spread over cross-KG edges and settle on an
    active concept set.
  - **coherence_check** — accept a mutually-referencing reading or escalate.
  - **fetch_route_learn** — route a comprehended percept and strengthen
    anchors, or trigger ask-user / fetch learning.

The Phase 4 memory and learning fabric (`src/parts/episodic/`, `src/learning/`):

- **moment_stream** — timestamped, append-only moment records with a
  PERCEIVED→SETTLED→CONSOLIDATED lifecycle (ADR-0021).
- **episode_storage** — episodes over moments with decay, recall reinforcement,
  tiering, and drop (ADR-0022).
- **consolidation** — recurring co-activation signatures become atom-birth
  candidates (ADR-0022).
- **bayesian_updates** — tracked beliefs with decay, tiered evidence, conflict,
  and a CONTESTED flag (ADR-0023).
- **predictive_coding_runtime** — precision-weighted prediction error with
  suppression/surprise thresholds and the upward error signal (ADR-0024).
- **atom_birth_monitor / atom_death_monitor** — novelty/frequency/stability
  gated atom birth, and decay/belief gated death with tombstoning (ADR-0025).
- **plasticity_modulation** — the learning-rate modulator from emotional
  arousal/valence/reward (ADR-0035/0007).

The Phase 5 self-directed learning layer (`src/learning/`):

- **self_learning_triggers** — gap detection (prediction error, curiosity,
  imagination gap, unknown query, user request), priority scoring, and an
  arbitration queue with user pre-emption (ADR-0026).
- **confidence_thresholds** — the low/high-stakes "learned enough" gates and
  hard caps that close a learning episode (ADR-0030).
- **ask_user_to_teach** — gap→question with an ask budget; ingests the reply as
  Beta(4,1) user-taught Tier-A evidence (ADR-0027).
- **source_whitelist / source_authority** — the allowed-domain gate, source
  tiers (A/B/C) with evidence weights, recency-policy conflict resolution, and
  user-taught precedence (ADR-0028/0029).
- **internet_fetch** — whitelist + rate-limit + cache + validation + tiered
  ingestion (ADR-0028); the TLS transport itself is a deferred seam (NOVA
  enhancement #11).

The Phase 6 cognitive subsystems (`src/parts/`):

- **goals** (`goals/`) — priority-sorted goal trees with rollup, block
  propagation, leaf arbitration, and staleness decay; the four intrinsic drives;
  and serialization with load-time validation (ADR-0033).
- **soul** (`soul/`) — the behavioral identity: slow identity (gated, audited
  revision) + OCEAN, fast state, medium goal summary, and the cross-cutting
  values, constitution (privileged XSIG_CONST veto), themes, and loyalty
  hierarchy (ADR-0034).
- **emotion** (`emotion/`) — OCC appraisal → valence/arousal/emotion-type, OCEAN
  conditioning, and emotion-modulated plasticity + episodic encoding (ADR-0035).
- **reasoning** (`reasoning/`) — operator atoms (causal/implicative/analogical/
  evidential) and five thin strategies: forward chaining, abduction, analogical
  transfer, evidential combination, and means-ends decomposition (ADR-0031).
- **imagination** (`imagination/`) — learned pattern atoms and four modes:
  forward simulation, counterfactual, dream recombination, and scenario planning
  (ADR-0032).

The Phase 7 agent architecture (`src/scheduler/`, `src/agent/`, `src/parts/meta/`):

- **scheduler** (`scheduler/`) — the hybrid 100Hz tick (`tick_loop` over the
  substrate) + event-driven coordination (`event_dispatch`), fused with idle
  detection in `hybrid_scheduler` (ADR-0037).
- **agent loops** (`agent/`) — the six cognitive loops (perception, memory,
  reasoning, emotion, goals, action) + the idle-gated imagination loop, over a
  shared `loop_coordination` blackboard (ADR-0036).
- **meta** (`parts/meta/`) — the self-model query API ("what/state/goals/
  competence", ADR-0038), theory-of-mind user model (ADR-0039),
  long-horizon goal accrual + revisit scan (ADR-0040), and the
  meta-learning observer (ADR-0050) that watches per-source promotion /
  atrophy and (P1.1) FEEDS those rates back into `source_authority` by
  promoting / demoting host tiers when sustained signal crosses thresholds
  -- 70% promotion over a 10-atom window promotes one tier; 50% atrophy
  demotes; the chat surfaces both via `/meta-feedback` (dry-run) and
  `/meta-apply` (commit). Atom death attribution (P1.6) is wired so a
  durable atom dying outright bumps the observer's atrophy counter
  immediately rather than waiting for the next poll.

The Phase 8 safety and audit stack (`src/safety/`, `src/audit/`):

- **reversibility_classifier** — classifies each action class as reversible /
  recoverable / irreversible, defaulting any unlisted action to irreversible
  (fail-safe); also home to the shared `ACT_*` action-class constants (ADR-0042).
- **permission_tiers** — the AUTO / NOTIFY / APPROVE tiers as the MAX of a
  static per-class default and the reversibility floor, so irreversible actions
  are always ≥ APPROVE; unknown classes default to APPROVE (ADR-0041).
- **decision_log** — the append-only, hash-chained decision record: every entry
  links to its predecessor so mutation, reorder, and tail-truncation all fail
  `dl_verify` (ADR-0043).
- **audit_writer / audit_reader** — the write path (intent entry before the
  effector, outcome after; corrections and overrides appended) and the
  inspection path (chain verification + plain-language "why did you do X?"
  rendered purely from stored state, no LLM) (ADR-0043, ADR-0038).
- **override_mechanism** — the four graded user interventions: belief edit
  (privileged α/β write + pin), goal veto (subtree prune + standing regen-block),
  hard stop (drain actions, substrate alive), and kill switch (clean snapshots,
  panic skips); all but panic-kill are logged (ADR-0044).
- **constitutional_filter** — the safety gate: constitutional veto (terminal,
  unclearable by user approval) → hard stop → permission tier, plus the soul
  loyalty resolution (constitution > enterprise > user > system) (ADR-0045).

The Phase 9 IO and effectors layer (`src/io/`):

- **output_generation** (`io/effectors/`) — pure-substrate language production
  (ADR-0013), the reverse of the reader: a communicative intent (role→concept
  assignments) resolves to real word atoms, a learned syntax-pattern atom orders
  them, and the text is emitted; well-formed patterns win, ill-formed are pruned,
  and accepted phrasings strengthen via plasticity. NO LLM (ADR-0014).
- **effector_gate** (`io/effectors/`) — the action chokepoint: every outward
  action runs the Phase 8 `safety_gate` (constitutional veto → hard stop →
  permission tier), logs an intent entry **before** the effector and an outcome
  **after** (ADR-0043). The text/SPEAK effector is fully implemented; governed
  speak vetoes a constitutionally-forbidden utterance by its text and never
  emits it.
- **input_transducer** (`io/transducers/`) — modality → reader-ready normalized
  percept (ADR-0011/0012, ADR-0021); strictly outside cognition (ADR-0014).
  Text/file are normalized now; audio (STT) is the honest deferred bridge seam.
- **kg_rss_ingest** (`io/transducers/`, R25C) — RSS 2.0 + Atom 1.0 feed
  parser + KG ingest pipeline: tag-walks the XML, decodes the five named
  entities + decimal numeric references, strips CDATA wrappers (inner
  content kept verbatim), and emits one FACT atom per never-seen guid
  carrying full payload (title / link / description / pubdate / guid /
  feed_url) and provenance `"rss:<feed_url>"`. Re-ingest of the same
  feed is a no-op (dedup on guid, falls back to link). Caps: 100 items
  per feed, 1 MB XML, 200-byte label, 4000-byte description. Wired as
  the chat command `/rss <feed_url> [max_items]`. http:// URLs route
  through `http_client.http_get`; file:///abs/path through sys_open +
  sys_read. The first ingestion pathway that LETS THE SUBSTRATE LEARN
  FROM THE WEB at the structured-record level.
- **audio_synth / audio_speak** (`io/effectors/`) — the audio modality bridge
  (Phase 19 Tier-4 #1; P2.6 multi-formant upgrade; P6 full-ARPAbet expansion).
  `audio_synth.nova` is the always-on Mode-1 floor: a pure-NOVA Klatt-style
  two-formant phoneme synthesizer covering the full English ARPAbet inventory
  (~44 distinct phonemes, 53 dispatches counting aliases like a/aa/ah): 20
  monophthongs with F1+F2+F3 (a/aa/ah, ae, e/eh, er, i/iy, ih, ix, ax, axr,
  o/oh/ao, ow, u/uw, uh), 4 diphthongs with linear formant glides (aw, ay,
  ey, oy), 6 plosives as silence+burst (b/d/g/k/p/t), 2 affricates as
  sequenced stop+fricative (ch=t+sh, jh=d+zh), 10 fricatives via a
  small-multiplier LCG pseudo-noise (s, z, f, v, sh, zh, th, dh, h/hh), 3
  onset nasals with damping (n, m, ng), 4 syllabic nasals/liquids with
  reduced amplitude (em, en, eng, el), and 4 liquids/glides (l, r, w, y), +
  a 440 Hz unknown fallback. 5 ms attack + 10 ms release anti-click ADSR per
  phoneme, and a 44-byte RIFF/WAVE/PCM writer (8 kHz, 16-bit, mono) durable
  via `sys_fsync` before close. The legacy single-carrier sine synth lives
  on as `synth_phoneme_sine` and is selectable at runtime via
  `CE_SYNTH_MODE=sine`; `CE_SYNTH_MODE=silence` emits zero samples for CI.
  `audio_speak.nova` layers Mode-2 espeak escalation and Mode-3 aplay/paplay
  best-effort playback on top. See `AUDIO_AUDIT.md` for the phoneme inventory
  audit + diphthong/affricate canonical formant tables.

The Phase 10 persistence layer (`src/persistence/`):

- **snapshot_writer** (ADR-0048) — the substrate-snapshot container: a tagged,
  versioned image with fixed, ordered sections `[SOUL][KGS][EPISODIC][SYNAPSES]
  [SELFMODEL]`, each holding a subsystem-serialized blob. Generic over the blobs
  (so it stays standalone); the crash-safe disk write (temp → fsync → atomic
  rename) is the runtime seam.
- **snapshot_reader** (ADR-0048) — parse + tag/version rejection, and the
  **load-bearing mandatory rehydration order** (soul → KGs → episodic): it
  refuses to load KGs before the soul (constitution must be live before any atom
  is admitted) or episodic before KGs (moments would dangle), and emits the
  ordered rehydration plan. The decision log persists independently and is not
  rolled back by a restore.

Three runnable artifacts build via `make install`: `examples/kernel_selfcheck.nova`
boots the substrate kernel; `examples/companion_spine.nova` runs the safety + IO +
persistence spine; and **`examples/crossengin_daemon.nova` → `bin/crossengin` is
the whole agent in one process**, driven by the ADR-0037 hybrid scheduler as a
real event-driven loop: input arrives as events; each step drains one and ticks
the substrate; on an event the full ADR-0036 six-loop cycle runs (perception via
the five-stage reader → memory → reasoning → emotion → goals → action) over a
shared concept KG, so a word read in perception seeds reasoning and imagination.
Affect emerges from the agent's own comprehension and becomes the tick's
plasticity modulator (with a predictive-coding residual as its error); a run of
empty ticks throttles the scheduler 100Hz→10Hz idle, gating imagination and
triggering a checkpoint. Output emerges from the substrate's reasoning: a reverse concept→word lookup
finds the naming word for a new conclusion and speaks it through the gated
effector ("see treat" after reading "fever"), no LLM picking the wording. The
agent also *grows its knowledge graphs at runtime*: unknown surface forms fire
self-learning triggers; at idle the arbiter drains them and `ask_user_to_teach`
ingests new word atoms + concept bindings (Beta(4,1) Tier-A prior) — a
follow-up event with the freshly-taught vocabulary is then comprehended. Forbidden actions are vetoed and logged; on shutdown the agent reboots
by rehydrating in mandatory order. This unified cross-subtree assembly is what
the import-path fix unblocked.

> Integration note: each loop is a self-contained unit over the shared
> blackboard, so the loops compose without tripping NOVA's import-dedup limit
> (blocker #10). Wiring all loops + the scheduler together in one program is the
> Phase 10 `main`, which will need a `nova_packages/` shim (see NEXT_SESSION.md).

## What "substrate, not workflow" means

Intelligence is intended to emerge from substrate dynamics, not from a
controller calling cognitive modules in sequence. The primitives are:

- **node** — uniform computational unit; specialization comes from learned
  state, not type. ~1M per part in v1 (target 1B), sparsely connected.
- **synapse** — persistent weighted connection; learns via Hebbian +
  error-driven plasticity; grows and prunes.
- **signal** — ephemeral typed message flowing through synapses (18 types).
- **atom** — persistent, mutable knowledge unit produced by nodes, stored in a
  domain knowledge graph, cross-referenced across graphs.
- **moment** — timestamped perception record; the entry point for input.
- **gate** — learned, content-based router between signals and parts.
- **KG (multi)** — domain-organized knowledge stores, spawned per domain.
- **reader** — five-stage hybrid input processor (not a parser, not an LLM).

A first principle runs through the whole design: **no LLM participates in
cognition.** The NOVA LLM bridge is reserved for speech-to-text / text-to-speech
modality conversion only (ADR-0014).

## Repository layout

```
docs/
  adr/        50 Architecture Decision Records (ADR-0001 .. ADR-0050)
  design/     architecture overview and supporting design docs
  runbook/    build / test / operational docs
src/
  substrate/  node pool, synapse, signal, tick, resonance  (the kernel)
  reader/     five-stage reader (ADR-0011, ADR-0012)
  gates/      learned signal routing (ADR-0009)
  parts/      perception, episodic, soul, reasoning, imagination, action, meta
  kg/         multi knowledge-graph store (ADR-0016, ADR-0017)
  learning/   self-directed learning (ADR-0026 .. ADR-0030)
  safety/     permission tiers, reversibility, constitution (ADR-0041 .. 0045)
  io/         transducers (STT/TTS modality) and motor effectors
  scheduler/  hybrid 100Hz tick + event scheduler (ADR-0037)
  audit/      append-only decision log (ADR-0043)
  persistence/ ordered substrate snapshot + rehydration (ADR-0048)
tests/        unit / integration / benchmark
scripts/      bootstrap.sh, run.sh, test.sh
examples/     runnable demos (kernel self-check)
```

Directories without code yet contain a `README.md` describing their
responsibility and governing ADRs.

## Building and running

CrossEngin compiles with the NOVA self-hosting toolchain in a sibling checkout
(`$HOME/NOVA` by default). NOVA has no third-party dependencies; it needs only
GNU `as`, `ld`, `make`, and `gcc`.

```sh
# one-time: verify host tools, locate/build the NOVA compiler
bash scripts/bootstrap.sh

# compile every module under src/
make build

# compile and run every unit test
make test

# build all runnable artifacts into ./bin/
make install
./bin/crossengin                  # the whole agent in one process
./bin/crossengin-selfcheck        # substrate kernel spine
./bin/crossengin-spine            # safety + IO + persistence spine
./bin/crossengin-kg-publisher     # distributed-substrate seam: publisher
./bin/crossengin-kg-subscriber    # distributed-substrate seam: subscriber
```

### Operations utilities

Three small shell tools cover the operations layer around the binaries:
preflight, structured-log mode, and snapshot diff.

```sh
# Preflight: green/yellow/red checklist of host env + deps + paths + a
# 3-second TCP probe of en.wikipedia.org (used by `/learn TOPIC`). Exits 0
# when every critical check passes; 1 if any critical fails. Optional
# helpers (ffmpeg, ImageMagick, espeak, aplay, parecord, whisper-cli,
# vosk-transcriber, wat2wasm, wasmtime, node, python3) appear as WARN
# when missing -- they do NOT gate the exit code.
bash scripts/crossengin-doctor.sh

# Structured JSON logging. `CE_LOG_JSON=1` flips the chat's per-turn
# operator log lines (the "agent>" preamble + the "perceive(m=N,unk=N)"
# line) and the daemon's per-cycle log line to one-line JSON objects:
#   {"ts":<int>,"level":"info","session":"<id>","event":"perceive",
#    "msg":"<input>","m":<int>,"unk":<int>}
# Default (env unset) preserves the legacy human-readable output BIT-
# IDENTICAL so existing log aggregators / web.py /metrics scrape stay
# valid. Daemon adds extra fields (hz, reason, mood_v, mod, routed).
CE_LOG_JSON=1 ./bin/crossengin-chat
CE_LOG_JSON=1 ./bin/crossengin

# Snapshot file diff: structural delta between two ./bin/crossengin*
# snapshot files. Reports atoms added/removed (by kg+label), beliefs
# changed (signed alpha/beta delta), sections added/removed, and soul
# mood/OCEAN drift. ANSI colours on a tty, plain when piped.
bash scripts/snap_diff.sh old.snap new.snap
```

### Benchmarks

Performance benches live under `scripts/bench_*.sh` (shell harness, NOVA-
side timing via `nanotime()`) and `tests/benchmark/*.nova` (long-running
substrate benches behind `make benchmark`). The unified entry point is
`scripts/bench.sh`, which discovers every shell bench, runs them, parses
the per-bench wallclock + speedup numbers, and emits a JSON report:

```sh
# Run every bench, print the JSON report to stdout.
scripts/bench.sh > /tmp/bench.json

# Human-readable mode (tees per-bench output + a summary table).
scripts/bench.sh --human

# Regression detection: re-run, compare against a committed baseline.
scripts/bench.sh --compare bench/baseline.json     # exit 2 on >50% slowdown

# List what would run without executing.
scripts/bench.sh --list

# Skip the slow SIMD-production bench (~50 seconds).
scripts/bench.sh --quick
```

The current baseline lives in [`bench/baseline.json`](./bench/baseline.json);
[`BENCHMARKS.md`](./BENCHMARKS.md) is the operator-facing summary table
(15 benches, scalar/SIMD/integral paths across stereo SAD, optical-flow LK,
HOG detection, and the NOVA-side AVX2 microbenches) and documents how to add
a new bench so the harness picks it up automatically.

Headline numbers from the R25E baseline (256x256 imagery, x86-64 + AVX2):

* Stereo SAD u8 SIMD: **~5.9x** over scalar
* Optical-flow LK mul-acc SIMD: **~3.4x** over scalar
* HOG detector integral-histogram: **~1.08x typical, ~2.15x peak** (R22A amortization)
* Image-residual SAD u8 SIMD: **~107x** (pure vectorization case)
* NOVA AVX2 `simd_sum_abs_diff` primitive: **~141x** in isolation

See [`BENCHMARKS.md`](./BENCHMARKS.md) for the full table and column
definitions, and the FASTER/NOMINAL/SLOWER/REGRESS verdict scheme used by
`--compare`.

### Distributed KG sync (publisher / subscriber demo)

Phase 20 / Tier-4 #2 ships the distributed-substrate seam: two or more
`bin/crossengin-kg-*` processes exchange atom-birth + belief-update events
over a TCP socket so subscriber daemons mirror the publisher's KG state
without sharing memory. P1.3 upgraded the protocol to v2 (the v1 lines are
still recognised); the new capabilities are N-subscriber fan-out, three new
event kinds (`PROMOTE` / `ATROPHY` / `DELETE`), bidirectional teach (a
subscriber can publish back to the publisher), reconnect-on-disconnect with
a `SUB FROM <id>` cursor resume, optional shared-token auth, and a
local-id-stable belief-average merge when both ends teach the same label.
Wire protocol is text, one operation per line, defined in
`src/io/transducers/kg_sync.nova`:

```
HELLO ce-kg-sync v2 [token=<TOK>]            -- handshake (anon or authed)
OK v2 protocol accepted                      -- handshake good
ERR auth                                     -- handshake refused (bad token)
SUB *                                        -- subscribe to all events
SUB FROM <id>                                -- resume after the given atom id
ATOM <kg> <id> <kind> <alpha> <beta> <label> -- atom birth (publisher -> subscriber)
PUB  <kg> <id> <kind> <alpha> <beta> <label> -- atom birth (subscriber -> publisher)
PROMOTE <kg> <id> <alpha> <beta>             -- belief update
ATROPHY <kg> <id>                            -- sub-threshold mark
DELETE  <kg> <id>                            -- atom killed
ACK <id>                                     -- per-event ack
BYE                                          -- graceful close
```

The publisher binds 127.0.0.1 by default (set `CE_KGSYNC_BIND=0.0.0.0` to
expose), listens on port 8766 (override via `CE_KGSYNC_PORT`), accepts the
number of subscribers given by `CE_KGSYNC_SUBS` (default 1 for backwards
compat), and -- if `CE_KGSYNC_TOKEN` is set -- gates new connections against
that token. The main `bin/crossengin` daemon is not touched; rolling the
seam into its idle loop is a future enhancement.

```sh
# v1-shape single-subscriber demo (unchanged)
./bin/crossengin-kg-subscriber > /tmp/sub.out &      # waits for handshake
sleep 0.5
printf 'widget\ngadget\nfever\n' | ./bin/crossengin-kg-publisher
grep widget /tmp/sub.out     # recv kg=language id=0 label=widget

# v2 fan-out: one publisher, three subscribers, token-gated
export CE_KGSYNC_TOKEN=s3kret
./bin/crossengin-kg-subscriber > /tmp/sub1.out &
./bin/crossengin-kg-subscriber > /tmp/sub2.out &
./bin/crossengin-kg-subscriber > /tmp/sub3.out &
sleep 0.5
printf 'widget\ngadget\n' | CE_KGSYNC_SUBS=3 ./bin/crossengin-kg-publisher
```

Point the build at a NOVA checkout elsewhere with `make NOVA_ROOT=/path/to/NOVA build`.

**For a complete walkthrough — prerequisites, three artifacts with expected
output, writing a new test, and troubleshooting — see [`MANUAL.md`](./MANUAL.md).**
Per-topic references: [`docs/runbook/build.md`](./docs/runbook/build.md),
[`docs/runbook/test.md`](./docs/runbook/test.md),
[`docs/runbook/run.md`](./docs/runbook/run.md), and
[`docs/design/overview.md`](./docs/design/overview.md) for the architecture.

**For the system layout, module catalog, and cross-references between
the ~190 NOVA modules in `src/`, see [`ARCHITECTURE.md`](./ARCHITECTURE.md).**
That document is the index — the per-subsystem audits (`IMAGE_AUDIT.md`,
`AUDIO_AUDIT.md`, `FEDERATED_AUDIT.md`, `SECAGG_AUDIT.md`,
`SNAPSHOT_FORMAT.md`, etc.) are the deep-dives.

## NOVA dependency and version note

The CrossEngin specification was written against an assumed "NOVA v4.1". The
NOVA checkout this repository builds against reports **v0.2.0**
(`src/version.nova`) / **v0.9.0** (launcher). CrossEngin pins to that actual
self-hosting toolchain and treats the larger capabilities (1M-node arenas,
sparse synapse adjacency at scale, true concurrency, 100Hz wall-clock pacing,
multi-KG, outbound fetch) as **upstream NOVA enhancements** that the ADRs assume
will land. Those enhancements are enumerated in
[`nova-deps.toml`](./nova-deps.toml) (`#1`..`#14`) and referenced throughout the
ADRs as `DEPENDS ON: NOVA enhancement #N`. Code that cannot yet be implemented
against the current toolchain is checked in as `*.nova.pending` (interface only)
and tracked in [`NEXT_SESSION.md`](./NEXT_SESSION.md).

## Decision records

Every architectural decision is recorded under [`docs/adr/`](./docs/adr/),
numbered `0001`–`0050` and grouped Foundation → Computation substrate → Reader
and language → Knowledge representation → Memory and learning → Self-directed
learning → Cognitive subsystems → Agent architecture → Safety and audit →
Operations and milestones. Start at
[`docs/adr/0001-substrate-architecture.md`](./docs/adr/0001-substrate-architecture.md).

## License

Proprietary and confidential. See [`LICENSE`](./LICENSE).
