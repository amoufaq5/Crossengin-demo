# ce_security — coverage

Row count: **125** files. Verified against `git -C /home/user/Crossengin-demo ls-files`: src/federation 24, src/safety 34 (33 .nova + README), src/net 14, src/persistence 10, infra 22, web 3, .devcontainer 3 = 110 directory files (all present, none missing), plus 10 assigned scripts, LICENSE, .gitignore and 3 key-like files under docs/. Other `*.example`/`*.conf` files are inside infra/ and counted there.

"reviewed" = read in full or all non-comment code read. "skimmed" = header contract, function list, and targeted greps (RNG, sockets, file I/O, stubs, compare loops) read; done for long codec files whose bodies are repetitive byte-packing and whose behaviour is pinned by the unit tests I executed. "(test-only)" = no file under CE/examples imports it, directly or transitively (import-graph walk, CE/examples/*.nova).

Additional files read because the assignment questions depend on them (not in my row count): CE/src/learning/secure_aggregation.nova, CE/src/learning/federated_aggregator.nova, CE/src/io/transducers/noise_xk.nova, CE/src/io/transducers/tls13_client.nova (parts), CE/src/sandbox/capability.nova (parts), CE/src/nl/rpc_verbs.nova (dispatcher + file verbs), CE/src/parts/soul/constitution.nova (check fn), CE/examples/crossengin_rpc_daemon.nova, crossengin_fed_daemon.nova (parts), crossengin_chat.nova (gate + command dispatch), NOVA/src/compiler/codegen.nova (secure_random).

| path | status | LOC | actual status | what it really does |
|---|---|---|---|---|
| CE/src/federation/raft_core.nova | reviewed | 216 | Working (test-only) | Pure in-memory Raft rules (term, vote, append, majority commit) on lists; no network/timers; imported only by tests. |
| CE/src/federation/raft_cluster.nova | reviewed | 181 | Working (test-only) | Loops over N in-process raft_core nodes delivering votes/appends synchronously; a simulation harness. |
| CE/src/federation/raft_membership.nova | reviewed | 106 | Working (test-only) | Joint-consensus majority arithmetic over lists of node ids; no log, no RPC. |
| CE/src/federation/raft_partition.nova | reviewed | 114 | Working (test-only) | In-process partition simulator: delivers calls only to a member subset, counts majority vs full cluster. |
| CE/src/federation/snapshot_broadcast_hook.nova | skimmed | 125 | Working | Glue: after snapshot save, builds a signed attestation tuple and calls gossip broadcast (opt-in env, daemon only). |
| CE/src/federation/ice.nova | skimmed | 436 | Partial (test-only) | ICE candidate list + RFC 8445 priority formulas + pair state enum; connectivity check `ice_check_pair` is a stub returning 0. |
| CE/src/federation/snapshot_attestation.nova | skimmed | 553 | Working | Formats/parses/verifies `soul_id|ts|merkle_root|ed25519 sig` tuples and keeps a per-soul latest table. |
| CE/src/federation/leader_election.nova | reviewed | 571 | Partial | "Bully": queues ELECTION/OK/VICTORY in an outbox nobody drains; effective result = highest id among locally gossip-alive peers after a timeout. |
| CE/src/federation/distributed_query.nova | skimmed | 608 | Working | Sends a mini-SPARQL query line to each gossip-alive peer over TCP, merges rows with provenance; unauthenticated. |
| CE/src/federation/snapshot_replication.nova | skimmed | 609 | Working | Tracks observed attestations, serves/fetches snapshot bytes by merkle root over gossip TCP, checks root on receipt. |
| CE/src/federation/webrtc.nova | reviewed | 649 | Stub (test-only) | SDP offer/answer string builder/parser with placeholder ufrag/pwd/fingerprint; rtc_send/rtc_recv return "needs DTLS" error. |
| CE/src/federation/kg_sync.nova | skimmed | 677 | Working | KG delta protocol: per-KG revision counter, KG_DELTA_REQ/RESP text lines (INS/UPD/RETR), 256KB cap. |
| CE/src/federation/ice_turn.nova | skimmed | 717 | Partial (test-only) | State glue between ICE agent and TURN client codec (relay candidate escalation); no live sockets. |
| CE/src/federation/gossip_relay_secure.nova | skimmed | 965 | Working (test-only) | Wraps relay payloads in the Noise-XK-derived ChaCha20-Poly1305 session; only tests import it. |
| CE/src/federation/gossip_relay.nova | skimmed | 976 | Working | RELAY_REQ/DATA/ACK text lines so peer A can ask peer C to forward to B over TCP; plaintext, unauthenticated. |
| CE/src/federation/srtp.nova | skimmed | 998 | Working codec (test-only) | SRTP AES-CM-128 + HMAC-SHA1-80 packet protect/unprotect + key derivation + replay window; RFC 3711 vectors; no media path uses it. |
| CE/src/federation/turn_server.nova | skimmed | 1289 | Partial (test-only) | TURN server allocation state machine as pure functions on byte buffers; no socket I/O, no data forwarding. |
| CE/src/federation/stun_rfc8489.nova | skimmed | 1300 | Working codec (test-only) | STUN message encode/decode, MESSAGE-INTEGRITY (HMAC-SHA1), FINGERPRINT (CRC32); RFC 5769 vectors. |
| CE/src/federation/nat_traversal.nova | skimmed | 1475 | Partial (test-only) | STUN-like external-address query over TCP text or UDP; NAT type guess from two answers; `nat_hole_punch` returns 0 (stub). |
| CE/src/federation/gossip_dtls_shim.nova | skimmed | 1510 | Partial | Non-standard "DTLS records over TCP with 2-byte length prefix" wrapper for gossip; self-interop only; opt-in CE_FED_TRANSPORT=dtls. |
| CE/src/federation/distributed_rules.nova | skimmed | 2243 | Working | Mini-Datalog rule/derivation exchange between gossip peers (RULE/DERIV/DRFETCH lines) over TCP; unauthenticated. |
| CE/src/federation/turn.nova | skimmed | 2768 | Working codec (test-only) | TURN (RFC 5766) message codec + client allocation state machine + long-term credential (MD5 key, HMAC-SHA1); no live relay. |
| CE/src/federation/gossip.nova | reviewed | 3657 | Working | SWIM-like membership + KG delta gossip over short-lived plaintext TCP connections; xorshift peer pick; optional Noise/DTLS wrappers; no auth by default. |
| CE/src/federation/dtls12.nova | reviewed | 4331 | Partial | DTLS 1.2 record/handshake codec, ECDHE-ECDSA-AES128-GCM flights, cert chain verify, replay window; no UDP transport, no retransmit timers, no cookie exchange; 5 dead *_R29B2_STUB fns. |
| CE/src/safety/README.md | reviewed | 14 | Doc | 14-line status note for the safety directory. |
| CE/src/safety/reversibility_classifier.nova | reviewed | 72 | Working | Constant table: 10 action-type ints -> reversible/recoverable/irreversible. |
| CE/src/safety/safety_log.nova | reviewed | 86 | Working | Appends an "attest cap -> allow/deny" record to the decision log; renders/list them. |
| CE/src/safety/approval_prompt.nova | reviewed | 89 | Working | Prints "approve? [y/N/why]" and reads a line from stdin; y/yes = approve. |
| CE/src/safety/permission_tiers.nova | reviewed | 91 | Working | Constant table action-type -> auto/notify/approve, max() with reversibility floor. |
| CE/src/safety/constitutional_filter.nova | reviewed | 113 | Working | Decision ladder (veto > halted > tier); veto = case-sensitive substring match of rule text in input, or KG-neighbor match of a concept label. |
| CE/src/safety/override_mechanism.nova | reviewed | 144 | Working | Sets halt/kill flags in a 4-slot list, overwrites an atom alpha/beta, marks goal subtree vetoed; writes audit entries. |
| CE/src/safety/capability_gate.nova | reviewed | 164 | Working | Pure function (capability int, 4 context flags) -> allow/require_approval/deny via if-chain. |
| CE/src/safety/rsa.nova | skimmed | 191 | Working | RSA signature VERIFY only (PKCS#1 v1.5 + PSS, SHA-256) on bn2048; 5 checks vs one openssl-made vector. |
| CE/src/safety/pem_truststore.nova | skimmed | 201 | Working | Splits a PEM bundle, base64-decodes, extracts RSA/EC public keys as trust anchors; directory mode needs a manifest file (TODO readdir). |
| CE/src/safety/hkdf_sha256.nova | skimmed | 210 | Working | HKDF extract/expand over HMAC-SHA256; RFC 5869 vectors. |
| CE/src/safety/cap_session.nova | reviewed | 213 | Working | Per-session allow/deny override array per capability + parser for `cap = allow|deny` config file. |
| CE/src/safety/x25519.nova | skimmed | 219 | Working | X25519 Montgomery ladder on field25519; RFC 7748 vectors. |
| CE/src/safety/ecdsa.nova | reviewed | 295 | Working | ECDSA P-256 verify (range check r,s in [1,n-1]; no low-s rule); RFC 6979 A.2.5 vectors; verify only. |
| CE/src/safety/chacha20_poly1305.nova | skimmed | 296 | Working | RFC 8439 AEAD seal/open with XOR-fold tag compare; RFC vectors. |
| CE/src/safety/p256_keypair.nova | skimmed | 310 | Working | Reads/writes raw 32-byte P-256 private + 33-byte public key files. |
| CE/src/safety/rng.nova | reviewed | 322 | Partial | RNG interface: OS backend (always fails on Linux x86-64 because NOVA secure_random passes tagged ptr -> EFAULT), deterministic test backend, FIFO callback backend. |
| CE/src/safety/chacha20.nova | skimmed | 359 | Working | ChaCha20 block/stream; RFC 7539 vectors. |
| CE/src/safety/dp_budget_ui.nova | skimmed | 401 | Working | ASCII bar + status text for the epsilon counter. |
| CE/src/safety/x509_verify.nova | reviewed | 437 | Partial | RSA/ECDSA chain signature check to pinned anchor + leaf SAN + leaf validity; no basicConstraints/CA check, no intermediate expiry, no revocation. |
| CE/src/safety/poly1305.nova | skimmed | 451 | Working | Poly1305 MAC with 5x26-bit limbs; RFC vectors. |
| CE/src/safety/sha1.nova | skimmed | 511 | Working (test-only) | SHA-1 + HMAC-SHA1 (for STUN/SRTP); FIPS/RFC 2202 vectors. |
| CE/src/safety/md5.nova | skimmed | 538 | Working (test-only) | MD5 (for TURN long-term key); RFC 1321 vectors. |
| CE/src/safety/differential_privacy.nova | reviewed | 591 | Partial | Integer epsilon counter + two-sided geometric noise from a 15-bit LCG seeded with constant (budget+7919); noise shrinks for eps<0.01 (cap bug). |
| CE/src/safety/sha256.nova | reviewed | 592 | Working | SHA-256 + HMAC-SHA256, oneshot and streaming; FIPS 180-4 / RFC 4231 vectors. |
| CE/src/safety/bignum.nova | skimmed | 721 | Working | 256-bit bignum with shift-subtract modmul (legacy; used by SecAgg DH helper). |
| CE/src/safety/scram.nova | skimmed | 725 | Working | SCRAM-SHA-256 message math + PBKDF2-HMAC-SHA256 + base64; RFC 7677 vectors; MAC compare not constant-time. |
| CE/src/safety/field25519.nova | skimmed | 839 | Working | GF(2^255-19) arithmetic for x25519. |
| CE/src/safety/aes_gcm.nova | skimmed | 854 | Working | AES-128/256 (table S-box) + GCM; FIPS 197 / SP 800-38D vectors; self-described as cache-timing exposed. |
| CE/src/safety/p256.nova | reviewed | 890 | Working (weak keygen) | P-256 field/group ops, ECDH, keygen; double-and-add (not constant time); key bytes fall back to 15-bit LCG when secure_random fails (always on Linux x86-64). |
| CE/src/safety/x509.nova | skimmed | 906 | Partial | X.509 DER parser for ECDSA-P256 certs + validity check; no SAN/basicConstraints/keyUsage/revocation (documented). |
| CE/src/safety/bignum_256.nova | skimmed | 966 | Working | 256-bit bignum with Montgomery REDC and ladder modpow. |
| CE/src/safety/bignum_2048.nova | skimmed | 1010 | Working | 2048-bit bignum, Montgomery modpow, MODP group-14 constants. |
| CE/src/safety/ed25519.nova | reviewed | 1292 | Working (weak keygen) | Ed25519 keygen/sign/verify + SHA-512; RFC 8032 vectors; keygen seed falls back to 15-bit LCG (32,767 possible keys) when secure_random fails. |
| CE/src/net/tls/tls_state.nova | skimmed | 212 | Working (test-only) | Enum + legal-transition table for a TLS 1.3 state machine; not imported by any binary. |
| CE/src/net/tls/tls_wire_hook.nova | skimmed | 554 | Partial | Wraps an accepted fd in the in-house TLS 1.3 server session when a config is supplied; pass-through otherwise (default). |
| CE/src/net/tls/base64.nova | skimmed | 149 | Working | Base64 decoder for env-supplied DER/key material. |
| CE/src/net/tls/der.nova | skimmed | 258 | Working | Minimal ASN.1 DER tag/length walker. |
| CE/src/net/tls/tls_handshake.nova | skimmed | 915 | Working | Serialize/parse six TLS 1.3 handshake message types (single suite/group). |
| CE/src/net/tls/x509.nova | skimmed | 1033 | Partial | Ed25519-only X.509 subset parser + 2-cert (leaf,root) chain check with validity; rejects everything else. |
| CE/src/net/tls/tls_transcript.nova | skimmed | 155 | Working | Rolling SHA-256 transcript hash. |
| CE/src/net/tls/tls_record.nova | skimmed | 437 | Working | TLS 1.3 record header + ChaCha20-Poly1305 record protect/unprotect (has a stale TODO(R94) comment). |
| CE/src/net/tls/tls_kdf.nova | skimmed | 258 | Working | HKDF-Expand-Label / Derive-Secret; RFC 8448 trace vectors. |
| CE/src/net/tls/tls_session.nova | skimmed | 1301 | Partial | TLS 1.3 handshake driver (x25519 + Ed25519 + ChaCha20-Poly1305 only); tested only against itself in-process. |
| CE/src/net/tls/tls_keyshare.nova | skimmed | 183 | Working | x25519 keyshare glue reading 32 bytes from rng_ctx. |
| CE/src/net/tls/tls_alerts.nova | skimmed | 201 | Working | Alert code enum + 2-byte serialize/parse. |
| CE/src/net/tls/tls_cert.nova | skimmed | 344 | Working | CertificateVerify sign/verify (Ed25519) over the transcript context string. |
| CE/src/net/tls/tls_config.nova | skimmed | 247 | Working | Holder for server cert DER, raw Ed25519 seed, root DER. |
| CE/src/persistence/snapshot_reader.nova | skimmed | 149 | Working | Checks container tag/version and returns sections in fixed order soul->KGs->episodic. |
| CE/src/persistence/bundle_signing.nova | skimmed | 236 | Working | Signs/verifies child bundle text with Ed25519; loads signer seed from env var hex. |
| CE/src/persistence/merkle.nova | reviewed | 438 | Working | SHA-256 Merkle root/proof over canonical atom strings; duplicate-last pairing, no leaf/node domain separation. |
| CE/src/persistence/snapshot_writer.nova | skimmed | 475 | Working | In-memory 5-section snapshot container (lists) + names of durable-write steps. |
| CE/src/persistence/schema_migration.nova | skimmed | 502 | Working | Versioned atom-schema migration step registry applied on load. |
| CE/src/persistence/snapshot_compaction.nova | skimmed | 522 | Working | Drops low-belief atoms / old episodes / dead synapses from a snapshot by thresholds. |
| CE/src/persistence/merkle_signing.nova | reviewed | 555 | Working | Ed25519 sign/verify of the Merkle root hex; reads/writes raw 32-byte key files (0600 priv) via tmp+rename. |
| CE/src/persistence/snapshot_delta.nova | skimmed | 827 | Working | Writes/reads incremental delta files (changed atoms since parent fingerprint), mode 0644, tmp+rename. |
| CE/src/persistence/chat_state.nova | skimmed | 1232 | Dead (test-only) | Alternative chat-state save/load to /tmp/crossengin/chat_state.dat; no binary imports it. |
| CE/src/persistence/snapshot_disk.nova | reviewed | 3066 | Working | Line-oriented `key value` text snapshot encode/decode, tmp+fsync+rename write (0644, no O_EXCL/O_NOFOLLOW), optional Merkle root + Ed25519 sig over KGS section only. |
| CE/infra/tls/nginx.rpc.conf.example | reviewed | 45 | Doc/config | nginx stream TLS terminator example in front of the plaintext RPC daemon. |
| CE/infra/tls/stunnel.rpc.conf.example | reviewed | 68 | Doc/config | stunnel TLS terminator example (accept 0.0.0.0:9977 -> 127.0.0.1:9876). |
| CE/infra/vercel-proxy/SECURITY.md | skimmed | 166 | Doc | Threat-model notes; acknowledges admin commands reachable via /chat and missing rate limiting. |
| CE/infra/vercel-proxy/ARCHITECTURE.md | skimmed | 156 | Doc | Describes browser -> Vercel function -> Python wrapper -> chat binary. |
| CE/infra/vercel-proxy/web/app/api/chat/route.ts | reviewed | 131 | Working | Unauthenticated public POST handler; forwards {session_id,input} to backend with server-held bearer token; 8KB input cap. |
| CE/infra/vercel-proxy/web/app/page.tsx | reviewed | 162 | Working | React chat page; random UUID session id; posts to /api/chat; renders text (no innerHTML). |
| CE/infra/vercel-proxy/web/app/layout.tsx | reviewed | 16 | Working | Next.js root layout boilerplate. |
| CE/infra/vercel-proxy/web/README.md | skimmed | 116 | Doc | Deploy instructions. |
| CE/infra/vercel-proxy/web/vercel.json | reviewed | 19 | Config | Function runtime/duration + two response headers. |
| CE/infra/vercel-proxy/web/package.json | reviewed | 27 | Config | next ^14.2.5, react 18; no lockfile committed. |
| CE/infra/vercel-proxy/web/next.config.js | reviewed | 15 | Config | reactStrictMode only. |
| CE/infra/vercel-proxy/web/.env.example | reviewed | 18 | Config | Two placeholders: CROSSENGIN_URL, CROSSENGIN_TOKEN (no real secret; no LLM provider keys). |
| CE/infra/vercel-proxy/web/tsconfig.json | reviewed | 21 | Config | TypeScript config. |
| CE/infra/vercel-proxy/web/next-env.d.ts | reviewed | 5 | Config | Next type shim. |
| CE/infra/vercel-proxy/backend/README.md | skimmed | 165 | Doc | Backend run instructions. |
| CE/infra/vercel-proxy/backend/docker-compose.yml | reviewed | 59 | Config | Publishes 8080 on all interfaces with hard-coded token "local-dev-token" + CE_ALLOW_DEV_TOKEN=1. |
| CE/infra/vercel-proxy/backend/Dockerfile | reviewed | 84 | Config | Ubuntu 24.04; unauthenticated git clone of NOVA + Crossengin-demo `main` from GitHub (unpinned); builds; runs as root. |
| CE/infra/vercel-proxy/backend/entrypoint.sh | reviewed | 51 | Working | Checks binary + token env, refuses dev token unless override flag, execs server.py. |
| CE/infra/vercel-proxy/backend/server.py | reviewed | 377 | Working | Python http.server on 0.0.0.0:8080; bearer check (hmac.compare_digest); pipes input line to a per-session chat subprocess stdin; one-shot mode uses shared /tmp/crossengin_input. |
| CE/infra/vercel-proxy/tests/test_backend_health.py | reviewed | 109 | Working | Smoke test: GET /health returns expected JSON. |
| CE/infra/vercel-proxy/tests/test_chat_route.ts | reviewed | 149 | Working | 5 route tests with mocked fetch (env missing, empty input, too large, unreachable, happy path). |
| CE/infra/vercel-proxy/tests/README.md | skimmed | 41 | Doc | How to run the two tests. |
| CE/web/styles.css | skimmed | 555 | Working | CSS for the RPC web UI. |
| CE/web/app.js | reviewed | 790 | Working | Vanilla-JS SPA calling /rpc/<verb>; stores cap token in localStorage; several innerHTML sinks interpolating server error strings. |
| CE/web/index.html | reviewed | 250 | Working | Static HTML shell for the SPA. |
| CE/.devcontainer/setup.sh | reviewed | 48 | Working | Installs build-essential, clones github.com/amoufaq5/nova (unpinned), builds. |
| CE/.devcontainer/README.md | reviewed | 31 | Doc | Codespaces instructions. |
| CE/.devcontainer/devcontainer.json | reviewed | 27 | Config | Ubuntu 24.04 devcontainer running setup.sh. |
| CE/scripts/web.py | reviewed | 1164 | Working | Python HTTP server (loopback default, no auth, no Origin check) that pipes each POSTed message into a per-cookie chat subprocess; /api/sessions lists all session ids. |
| CE/scripts/rpc_web_shim.py | reviewed | 419 | Working | Static file server + POST /rpc/<verb> -> TCP RPC daemon bridge; verb allow-list, traversal guard, opt-in CORS; no auth, no Origin/Host check. |
| CE/scripts/serve_web.sh | reviewed | 50 | Working | Execs rpc_web_shim.py. |
| CE/scripts/rpc.sh | reviewed | 105 | Working | Sends one JSON-RPC line via nc or /dev/tcp; verb interpolated into JSON unescaped. |
| CE/scripts/rpc_daemon.sh | reviewed | 76 | Working | Launches RPC daemon; refuses non-loopback bind without override flag. |
| CE/scripts/gen_tls_cert.sh | reviewed | 146 | Working | openssl self-signed cert/key generator for the TLS sidecar (0600 key). |
| CE/scripts/snap_keygen.sh | reviewed | 67 | Working | openssl Ed25519 keypair -> raw 32-byte .priv/.pub (safe alternative to the Nova keygen). |
| CE/scripts/secure_channel_echo.py | reviewed | 278 | Working | Independent Python ChaCha20-Poly1305 PSK echo server used as interop counterpart in one integration test. |
| CE/scripts/fed_smoke_client.py | reviewed | 66 | Working | Connects to fed coordinator, sends HELLO + FED_JOIN, closes. |
| CE/scripts/secagg_smoke_soul.py | reviewed | 217 | Working | Python SecAgg soul client re-implementing the same 15-bit LCG mask derivation. |
| CE/LICENSE | reviewed | 41 | Doc | 41-line custom "Proprietary and Confidential" license; no rights granted. |
| CE/.gitignore | reviewed | 44 | Config | Ignores build output, *.cesnap/*.celog, pycache; does NOT ignore *.priv/*.key/.env*. |
| CE/docs/caps.sample.conf | reviewed | 26 | Doc/config | Commented sample capability policy file. |
| CE/docs/samples/sample_agent.bundle | reviewed | 26 | Doc/sample | Sample child bundle text with an Ed25519 signature line; no private key. |
| CE/docs/samples/sample_agent.pub | reviewed | 1 | Doc/sample | 32 raw bytes: Ed25519 public key for the sample bundle (public only). |
