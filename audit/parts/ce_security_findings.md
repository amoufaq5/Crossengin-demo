# ce_security — findings (CE federation / safety / net / persistence / infra / web / socket scripts)

Labels: CONFIRMED = read in code or executed; LIKELY; SUSPECTED. Paths are `CE/…` or `NOVA/…`, repo-relative.

## Plain-language summary

This area is about 59,000 lines (roughly 31% of CE/src) of hand-written cryptography and network protocol code in Nova. The low-level primitives are real and competently done: SHA-256, HMAC, HKDF, ChaCha20-Poly1305, AES-GCM, P-256, ECDSA verify, Ed25519, X25519, SCRAM/PBKDF2, MD5, SHA-1 all reproduce the official RFC/NIST test vectors (I ran 28 unit suites; all pass). The file headers are unusually honest about what is a stub.

Three things undercut it:

1. **There is no working random number source.** NOVA's `secure_random` builtin passes a tagged pointer and tagged length to `getrandom`, so on Linux x86-64 it always fails with EFAULT. CE interpreted this as "the sandbox blocks getrandom" and added a fallback: a 15-bit LCG seeded from `nanotime() & 32767`. Every key, nonce and token minted in Nova therefore has at most 32,767 possible values. I recovered a generated Ed25519 seed by brute force in under a second.
2. **Privacy features do not deliver privacy.** DP noise comes from a 15-bit LCG seeded with a constant, so the noise sequence is identical in every process. SecAgg masks are 15-bit values reused across every statistic in a round.
3. **Most of the protocol stack is not connected to anything.** The WebRTC/ICE/STUN/TURN/SRTP/Raft modules (about 12,500 LOC) are imported only by unit tests. The chat commands `/webrtc`, `/nat`, `/relay`, `/relay_secure` print a sentence saying the feature "ships in src/federation/…" and call nothing. What is live is plaintext, unauthenticated-by-default TCP: gossip, kg_sync, the federation coordinator and the JSON-RPC daemon.

"Federated learning" averages two integers per data source (promotion rate, atrophy rate). "Leader election" is "highest id among peers I currently believe alive". "Raft" is an in-process simulation. The safety layer is a set of small integer tables plus one substring rule (`"exfiltrate"`); it is on the live chat path, and works as a confirmation prompt, not as a security boundary.

Nothing here is dishonest in the code comments; the gap is between the README-level names and what is wired.

## Findings table

| ID | Sev | Category | Title | File:line | Evidence | Impact | Recommended fix | Effort | Conf. |
|---|---|---|---|---|---|---|---|---|---|
| S-01 | Critical | Crypto / RNG | `secure_random` always fails on Linux x86-64; all keygen falls back to a 15-bit LCG | NOVA/src/compiler/codegen.nova:19515-19535 and :22547-22548 (`secure_random: jmp _nova_secure_random`, no untag); CE/src/safety/ed25519.nova:1161-1181; CE/src/safety/p256.nova:747-764; CE/src/io/transducers/noise_xk.nova:440-455; CE/src/sandbox/capability.nova:804-822 | `strace` of a probe: `getrandom(0x4b412001, 65, 0) = -1 EFAULT` (odd pointer = 2p+1, length 65 = 2·32+1). Probe printed `got=-1`. Python `os.getrandom` works in the same sandbox. I generated a seed with `_ed_random_seed()` and recovered LCG state 9805 by trying 32,767 seeds. | Every Ed25519 signing key (snapshot signing via `examples/snap_keygen.nova:42`), P-256 ephemeral key (DTLS, TLS 1.3 client), Noise static/ephemeral key, and RPC capability token id made in Nova has ≤15 bits of entropy. Signatures can be forged, sessions decrypted, tokens guessed. | Fix the builtin (untag both args: `sar rdi,1; sar rsi,1`, retag result). Delete every LCG fallback; fail closed. Regenerate all keys. Add a test that asserts `secure_random(buf,32)==32`. | S (fix) + M (remove fallbacks, rotate) | CONFIRMED |
| S-02 | High | Tests | RNG test reports OK while skipping the OS backend | CE/tests/unit/test_rng.nova (output: `SKIP: OS entropy source not available in this container…` then `rng: OK (48 checks)`); CE/src/safety/rng.nova:44-49 | Ran it: rc=0 with the SKIP line. Comments attribute the failure to seccomp. | The one test that could have caught S-01 cannot fail. | Make the OS-backend check a hard failure on Linux. | S | CONFIRMED |
| S-03 | Critical | Crypto | ECDSA signing nonce `k` drawn from the same broken RNG | CE/src/federation/dtls12.nova:1985-1992 (`let k = _p256_random_scalar()`), comment at :1975-1977 says RFC 6979 is a "hardening followup" | With 32,767 possible `k`, one observed signature reveals the DTLS certificate private key (`priv = (s·k − e)/r`). | Long-term DTLS identity key compromise from a single handshake transcript. | Implement RFC 6979 deterministic k (HMAC-SHA256 already exists). | S | CONFIRMED (code); exploit not run |
| S-04 | High | Crypto | DTLS/TLS hello randoms are zero or unchecked when RNG fails | CE/src/federation/dtls12.nova:1267-1281 (zero-fill ClientHello.random); CE/src/io/transducers/tls13_client.nova:378-383 (`secure_random` return ignored) | Read. Given S-01 this is the path taken every time. | No handshake freshness; replay of recorded handshakes becomes possible. | Fail the handshake when entropy is unavailable. | S | CONFIRMED |
| S-05 | Critical | Privacy / DP | DP noise is deterministic: 15-bit LCG seeded with `budget + 7919` | CE/src/safety/differential_privacy.nova:189-192, :130-145 | Probe: two fresh `dp_new(10000)` states returned identical noisy counts `500/500 475/475 512/512 533/533 503/503 514/514`. | Anyone who knows the code can subtract the noise exactly. The epsilon accounting is bookkeeping with no privacy behind it. | Seed from a working CSPRNG and sample with a real sampler (≥64-bit uniform, exact discrete Laplace). | M | CONFIRMED |
| S-06 | High | Privacy / DP | Noise gets *smaller* for epsilon < 0.01 | CE/src/safety/differential_privacy.nova:446-454 (`denom` computed before `s` is capped at 100000) | Probe, mean abs noise ×1000 over 200 draws: eps=1.0 → 1360; eps=0.1 → 10840; eps=0.01 → 95730; eps=0.005 → 1365; eps=0.001 → 170. | A caller asking for stronger privacy gets nearly none while being charged less budget. | Cap `s` before computing `denom`, or reject eps below the representable floor. | S | CONFIRMED |
| S-07 | Medium | Privacy / DP | Geometric sampler uses 10-bit uniforms from a ≤32,768-state generator; ratio is 1/(1+eps) not exp(−eps) | CE/src/safety/differential_privacy.nova:454-460 | Read. Ratio choice is conservative (effective eps = ln(1+eps)), but tails are truncated and the state space is tiny, so the formal guarantee does not hold. | Not a DP mechanism in the formal sense even after S-05 is fixed. | Use an exact sampler (Canonne–Kamath–Steinke) on 64-bit randomness. | M | CONFIRMED (read) |
| S-08 | Critical | Privacy / SecAgg | SecAgg masks are 15-bit, derived by a 15-bit string hash, and reused for every source tag in a round | CE/src/learning/secure_aggregation.nova:420-449 (`_sa_hash_str`, `_sa_seed_for_pair`), :758-780 (`sa_mask_for_peer` depends only on secret, round, k_dim∈{0,1}); CE/src/learning/federated_aggregator.nova:445-457 | Read. `masked = x ± mask` in plain integers (no modulus). Same mask is added to every row, so the difference of any two masked rows equals the difference of the raw values. Mask space is 32,767 regardless of DH size. | The coordinator can recover individual contributions. The 2048-bit DH option does not help because its output is hashed to 15 bits. | Derive masks with HKDF/ChaCha20 from the pair secret with (round, tag, dim) in the info string; work mod 2^k. | M | CONFIRMED (read); attack not run |
| S-09 | High | Privacy / SecAgg | SecAgg DH private key comes from `nanotime()` folded to 15 bits; default DH modulus is 2^255−19 used as a finite-field group | CE/src/learning/secure_aggregation.nova:495-520, :249, :480-486 | Read; comments flag both "LOUDLY". No `secure_random` attempt at all here. | Pair secrets are guessable (32,767) and the 256-bit FFDH is breakable anyway. | Use X25519 (already in tree) with a working RNG. | S | CONFIRMED |
| S-10 | High | Network / authn | All federation listeners are plaintext and anonymous by default | CE/src/federation/gossip.nova:1201-1300 (no auth after `HELLO`), :1711-1717 (default 127.0.0.1:8770), :2234-2242 (Noise strict opt-in); CE/src/io/transducers/kg_sync.nova:1063-1071 (token unset → anonymous); CE/src/learning/federated_aggregator.nova:874-885; CE/examples/crossengin_fed_daemon.nova:243-250 (default transport "tcp"), :680 | Read. An unauthenticated peer can: dump every KG atom (`DELTA`), inject atoms, inject peers (`MEMBER <addr>` makes the daemon dial arbitrary host:port), request snapshot bodies, relay data, and run distributed queries/rules. No example binary calls `gossip_set_noise_keys`. | Safe only while bound to loopback. Any non-loopback `CE_GOSSIP_SELF` exposes the knowledge graph for read and write. | Require an authenticated transport before any verb; refuse non-loopback bind without keys. | M | CONFIRMED |
| S-11 | High | Network / authz | JSON-RPC daemon runs with no authentication unless `CE_RPC_REQUIRE_TOKEN=1` | CE/examples/crossengin_rpc_daemon.nova:150-159, :535-551; CE/src/nl/rpc_verbs.nova:5135-5150 (`authorize is a no-op` when not enforced) | Read. 53 verbs including `admin.*`, `session.save/load/delete`, `ingest.file` (feeds attacker bytes to hand-written image/audio/JSON/YAML parsers), `skill.install`, `update.apply`. | Any local process (or a web page via S-14) can drive admin verbs. With enforcement on, tokens are plain bearer strings compared by lookup, and wire-minted ones are guessable (S-01). | Enforce by default; make "no auth" the explicit opt-in. | S | CONFIRMED |
| S-12 | Medium | File access | `admin.bake_child` takes caller-chosen `manifest_path` (read) and `output_path` (write) with no path restriction | CE/src/nl/rpc_verbs.nova:3761-3767, :3790-3793, :3819 | Read. Contrast with `_rpc_snap_name_check` (:3242-3270) which is a sound allow-list for session names. Write requires signer keys in env; read leaks only parse-error text. | Arbitrary file overwrite (bundle text + `.tmp`) as the daemon user when auth is off or an admin token is guessed. | Confine both to configured directories. | S | CONFIRMED (read) |
| S-13 | High | Web | Vercel function is a public, unauthenticated, unthrottled relay to the chat REPL including slash commands | CE/infra/vercel-proxy/web/app/api/chat/route.ts:53-105; CE/infra/vercel-proxy/backend/server.py:311-322; CE/infra/vercel-proxy/SECURITY.md:19-27 (acknowledged) | Read. Input is forwarded verbatim; only `.trim()` and an 8KB cap. `session_id` is caller-chosen. Embedded newlines pass through, so one request can send several lines. | Anyone who can reach the deployment can send `/quit`, `/halt`, `/teach`, `/load <path>`, `/save <path>`, `/learn <url>` to the backend, evict other users' sessions (LRU 8), or attach to a known session id. | Add end-user auth and rate limiting; strip leading `/` and newlines at the proxy; give the web surface a non-admin entry point. | M | CONFIRMED |
| S-14 | High | Web | Local web servers have no Origin/Host check and accept any Content-Type → cross-site request forgery and DNS rebinding | CE/scripts/web.py:1088-1117; CE/scripts/rpc_web_shim.py:237-268 | Read. `json.loads` is applied regardless of Content-Type, so a hostile page can `fetch('http://127.0.0.1:8765/api/chat', {method:'POST', body:'{"message":"/learn http://…"}'})` with no preflight. | A web page open in the user's browser can run chat admin commands or the shim's allowed RPC verbs (`skill.run`, `capsule.install`, `ingest.approve`). | Require `Content-Type: application/json`, validate `Origin`/`Host`, add a per-launch secret. | S | CONFIRMED (read); not exploited |
| S-15 | Medium | Web | `/api/sessions` returns every session cookie value | CE/scripts/web.py:1003-1012, :339-351 | Read. Cookie is HttpOnly/SameSite=Strict but the ids are handed out by an unauthenticated GET. | Any local client can take over another user's chat session. | Return counts or hashed ids. | S | CONFIRMED |
| S-16 | Medium | Safety bypass | Approval prompts are answered on the same stdin as the request | CE/src/safety/approval_prompt.nova:66-84; CE/examples/crossengin_chat.nova:3635-3648; CE/scripts/web.py:156; CE/infra/vercel-proxy/backend/server.py:312 | Read. Over web/proxy, a message `"/learn http://x\ny"` supplies its own approval. | The human-in-the-loop gate is void on every non-terminal surface. | Reject embedded newlines; deny approval-required actions on non-TTY surfaces. | S | CONFIRMED (read); not executed |
| S-17 | Medium | SSRF | `/learn <url>` fetches any host with no private-address filter | CE/examples/crossengin_chat.nova:5093-5094, :7522-7526; CE/src/io/transducers/http_client.nova:975-982 | Read; grep for 127./169.254/private found no filter. Gate is the y/N prompt (see S-16). | Reachable through S-13/S-14 to probe internal services / cloud metadata from the backend host. | Block loopback, link-local and RFC 1918 targets by default. | S | CONFIRMED (read) |
| S-18 | High | Local / tmp | Daemons take commands from fixed world-writable paths | CE/examples/crossengin_daemon.nova:525 (`/tmp/crossengin_input`); CE/examples/crossengin_fed_daemon.nova:605 (`/tmp/crossengin_fed_input`); CE/infra/vercel-proxy/backend/server.py:172 (same file shared by concurrent requests) | Read. | Any local user can inject input or `EXIT`; in one-shot proxy mode concurrent requests overwrite each other's input. | Use a per-user 0700 runtime dir or a Unix socket with peer-cred check. | S | CONFIRMED |
| S-19 | Medium | Local / tmp | Snapshots, decision log and learn caches default to predictable `/tmp` names; snapshot mode 0644; no O_EXCL/O_NOFOLLOW | CE/examples/crossengin_chat.nova:155 (`/tmp/crossengin.snap`), :7764 (`/tmp/crossengin.dlog`), :5098 (`/tmp/crossengin_learn_<tag>.txt`); CE/src/persistence/snapshot_disk.nova:2710, :2734-2735 | Read. `<path>.tmp` is opened with O_CREAT\|O_TRUNC and follows symlinks. A planted learn-cache file is ingested as knowledge. | Symlink clobber, world-readable memory dump, knowledge poisoning by other local users. | Default to `$HOME/.crossengin` (0700), files 0600, O_NOFOLLOW\|O_EXCL on tmp. | S | CONFIRMED (read) |
| S-20 | Medium | Persistence | Snapshot signature covers only the KGS section; verification is opt-in | CE/src/persistence/snapshot_disk.nova:1616-1628, :2897-2912; CE/examples/crossengin_chat.nova:5557-5578 | Read. SOUL (identity + constitution rules), EPISODIC, SYNAPSES, SELFMODEL are outside the Merkle root. | A signed snapshot can have its constitutional rules removed or memories altered and still verify. | Sign a hash of the whole canonical file. | S | CONFIRMED |
| S-21 | Medium | Persistence / DoS | Snapshot parser trusts counts and indices from the file | CE/src/persistence/snapshot_disk.nova:2266-2271, :2278-2280, :1892-1898 | Probe: a snapshot with `episodic.moments[0].atom_count 900000000` was killed (rc=137) while padding the list. Negative index into `list_set` not confirmed (my minimal file was rejected for other reasons). | Loading an untrusted snapshot (also reachable via gossip snapshot replication) exhausts memory. | Bound counts/indices against file size before allocating; reject negatives. | S | CONFIRMED (DoS); SUSPECTED (negative index write) |
| S-22 | Low | Persistence | Merkle tree has no leaf/node domain separation and duplicates the last leaf | CE/src/persistence/merkle.nova:203-225, :278 | Read. `[a,b,c]` and `[a,b,c,c]` give the same root. | Appending a duplicate final atom is undetected; textbook second-preimage weakness. | RFC 6962 construction (0x00/0x01 prefixes, no duplication). | S | CONFIRMED (read) |
| S-23 | High | PKI | Chain verifier does not check basicConstraints/CA, keyUsage, intermediate validity or revocation | CE/src/safety/x509_verify.nova:396-437 | Read: per-link signature, anchor key match, leaf SAN, leaf dates only. | Any holder of a valid leaf certificate under a trusted root can issue certificates for other names. | Enforce CA:TRUE + pathLen on issuers and validity on every cert. | M | CONFIRMED |
| S-24 | Medium | PKI | TLS 1.3 client is unauthenticated by default | CE/src/io/transducers/tls13_client.nova:259-263 (strict only with `CE_TLS_STRICT=1`), header :12-17 | Read. | `/learn https://…` content can be replaced by an on-path attacker and becomes knowledge-graph input. | Make strict the default with the system CA bundle. | S | CONFIRMED |
| S-25 | Medium | Naming / function | "Leader election" never exchanges election messages | CE/src/federation/leader_election.nova:295-312, :395-407, :494-503 | `le_drain_pending` has no caller outside the file; comments say "the bully wire is queued but not delivered". | Each node picks max(id) of its own alive view; two nodes with different views both believe they lead. Fine for a demo, not for single-writer guarantees. | Rename to "highest-alive-id heuristic" or wire the messages. | S | CONFIRMED |
| S-26 | Medium | Dead code / drift | WebRTC, ICE, STUN, TURN (client+server), SRTP, NAT traversal, Raft, secure relay, MD5, SHA-1, tls_state are imported only by tests | Import-graph walk from CE/examples/*.nova (script in probes); CE/examples/crossengin_chat.nova:7636-7640 | `/nat`, `/relay`, `/relay_secure`, `/webrtc` each `println` a description and return. 13 files, 12,475 LOC. | Maintenance and audit cost with no product path; the chat UI implies features exist. | Move to an `experimental/` tree or delete; make the commands say "not wired". | S | CONFIRMED |
| S-27 | Medium | Interop | No handshake protocol is tested against an independent implementation | CE/src/net/tls/tls_session.nova:6-8 ("Both peers are constructed in the same process"); CE/src/federation/gossip_dtls_shim.nova:1-14 ("NON-STANDARD"); CE/src/io/transducers/noise_xk.nova:18-36 (2048-bit FFDH, not a Noise DH function) | grep for `openssl s_client`/`s_server` in tests and scripts: none. openssl appears only as a source of certificate fixtures. | Self-consistency hides spec deviations; "DTLS", "Noise XK", "TLS 1.3 server" cannot be assumed compatible with anything else. | Add `openssl s_client`/`s_server` and a reference Noise test to CI. | M | CONFIRMED |
| S-28 | Medium | Side channels | Secret-dependent timing throughout | CE/src/safety/aes_gcm.nova:90-99 (table S-box, acknowledged); CE/src/safety/p256.nova:72-78 (double-and-add); CE/src/safety/scram.nova:212-213; CE/src/sandbox/capability.nova:737 (token lookup by string compare) | Read. Nova offers no constant-time guarantee (tagged ints, list-backed bignums). | Remote timing recovery is plausible for AES-GCM/ECDH on a LAN; moot until S-01 is fixed. | Do not expose hand-rolled crypto to hostile networks; terminate with a vetted library (the repo's own nginx/stunnel examples already do this). | L | CONFIRMED (read) |
| S-29 | Medium | Secrets handling | TLS private key supplied via environment variable; dev token committed in compose | CE/examples/crossengin_rpc_daemon.nova:177, :209; CE/infra/vercel-proxy/backend/docker-compose.yml:34-35 (`local-dev-token`, `CE_ALLOW_DEV_TOKEN: "1"`, port 8080 published) | Read. | Key visible in `/proc/<pid>/environ` and process listings; a copied compose file exposes a known token on all interfaces. | Read keys from 0600 files; bind compose port to 127.0.0.1. | S | CONFIRMED |
| S-30 | Low | Web / XSS | `innerHTML` with server error strings; admin token in localStorage | CE/web/app.js:225, :255, :285, :311, :342, :455; :31 | Read. Daemon errors echo caller arguments (e.g. `unknown role: <x>`). | Mostly self-XSS today; any XSS yields the stored capability token. | Use `textContent`. | S | LIKELY |
| S-31 | Low | Supply chain | Docker and devcontainer builds clone unpinned `main` from GitHub; container runs as root | CE/infra/vercel-proxy/backend/Dockerfile (ARG NOVA_REF=main, no USER); CE/.devcontainer/setup.sh (`git clone --depth 1 https://github.com/amoufaq5/nova`) | Read. | Unreproducible images; compromise of either repo flows into deployments. | Pin commit SHAs; add a non-root USER. | S | CONFIRMED |
| S-32 | Medium | Legal | Licence says "Proprietary and Confidential … must not be disclosed"; build files assume the repos are anonymously clonable from GitHub; NOVA has no licence file | CE/LICENSE:1-20; CE/README.md:4588-4590; CE/infra/vercel-proxy/backend/Dockerfile (unauthenticated clone); CE/web/index.html:244 (public GitHub link); `ls /home/user/NOVA \| grep -i licen` → empty | Read. No third-party code attribution found (grep for "ported/adapted/copied from" in my dirs: none), so no copied-code conflict seen. Repo name is "Crossengin-demo". | If the repos are public, the confidentiality clause is already contradicted; NOVA with no licence is "all rights reserved" by default, which blocks outside contributors and users. | Decide: private repos, or a real licence for both. | S | CONFIRMED (text); LIKELY (public visibility — not checked online) |
| S-33 | Low | Hygiene | `.gitignore` does not exclude key material | CE/.gitignore:1-41 | No `*.priv`, `*.key`, `*.pem`, `.env*` patterns; keygen tools write `<base>.priv` wherever the user points. | Easy accidental commit of a signing key. | Add the patterns. | S | CONFIRMED |
| S-34 | Low | Safety logic | Only one constitutional rule ships and it is a case-sensitive substring | CE/examples/crossengin_chat.nova:6153, :6160; CE/src/parts/soul/constitution.nova:100-112 | `str_find(action_text, "exfiltrate")`. "Exfiltrate" or "ex-filtrate" passes the text rule; the concept rule depends on seeded synonym edges. | The "constitutional gate" is a one-word blocklist on user input, not a check on agent actions. | Describe it as such; if kept, normalise case. | S | CONFIRMED |
| S-35 | Low | Dead code | Five `*_R29B2_STUB` functions remain in dtls12 | CE/src/federation/dtls12.nova:4066, :4087, :4095, :4100, :4123 | Read; header :132-159 says they are historical. | Confusing names (one "STUB" is said to be real). | Delete. | S | CONFIRMED |
| S-36 | Low | Scripts | `rpc.sh` interpolates the verb into JSON unescaped; unbounded Content-Length reads | CE/scripts/rpc.sh:62-64; CE/scripts/web.py:1093; CE/scripts/rpc_web_shim.py:248 | Read. | Local-only nuisance / memory DoS. | Escape; cap body size. | S | CONFIRMED |

TODO/FIXME/HACK/XXX count in my directories: 5 (CE/src/safety/pem_truststore.nova:146,148; CE/src/safety/scram.nova:97; CE/src/net/tls/tls_record.nova:149; CE/infra/vercel-proxy/SECURITY.md:130). The low count is misleading: deferred work is recorded as prose ("R29B.2", "future round", "out of scope") in file headers rather than as TODO markers.

## Crypto/protocol module status

"Vectors" = official RFC/NIST/FIPS vectors present in CE/tests/unit and the suite passed when I ran it (`timeout 180 $S/NOVA/nova run tests/unit/test_<x>.nova`). "Live" = imported (transitively) by a CE/examples entry point; import does not prove a call.

| Module (file) | LOC | Real / partial / sim | Official vectors? (run result) | Interop with independent peer? | Live path? |
|---|---|---|---|---|---|
| SHA-256 + HMAC (safety/sha256.nova) | 592 | Real | FIPS 180-4, RFC 4231 — OK 20 checks | n/a (KAT) | Yes (all binaries) |
| HKDF (safety/hkdf_sha256.nova) | 210 | Real | RFC 5869 — OK 29 | n/a | rpc_daemon |
| ChaCha20 / Poly1305 / AEAD | 359 / 451 / 296 | Real | RFC 7539/8439 — OK 55 (AEAD), 56 (poly) | Yes for the PSK channel only: Python peer `scripts/secure_channel_echo.py` | Yes |
| AES-GCM (safety/aes_gcm.nova) | 854 | Real, table-based | FIPS 197, SP 800-38D TC1 — OK 45 | No | Yes (via DTLS code) |
| P-256 ECDH (safety/p256.nova) | 890 | Real math, broken keygen (S-01) | RFC 5903 §8.1 — OK 52 | No | Yes |
| ECDSA P-256 verify (safety/ecdsa.nova) | 295 | Real (verify only; no low-s) | RFC 6979 A.2.5 — OK 25 | Verifies openssl-made certs in fixtures | Yes |
| Ed25519 (safety/ed25519.nova) | 1292 | Real math, broken keygen (S-01) | RFC 8032 — OK 62 (sign ≈ 523 ms) | No | Yes (snapshot signing) |
| X25519 (safety/x25519.nova, field25519) | 219 / 839 | Real | RFC 7748 — OK 15 | No | rpc_daemon (TLS opt-in) |
| RSA verify (safety/rsa.nova) | 191 | Real, verify only | One openssl-generated signature — OK 5 | That vector only | Yes (TLS client strict mode) |
| SCRAM-SHA-256 + PBKDF2 (safety/scram.nova) | 725 | Real message math | RFC 7677 §3 — OK 43 | No | Imported; used by TURN code only |
| MD5, SHA-1 (safety/md5.nova, sha1.nova) | 538 / 511 | Real | RFC 1321, FIPS 180-4, RFC 2202 — OK 16 / 17 | n/a | No (test-only); protocol-mandated uses only |
| CSPRNG interface (safety/rng.nova) | 322 | Partial: OS backend never works (S-01) | none; test SKIPs OS backend — "OK 48" | n/a | rpc_daemon TLS only |
| X.509 chain verify (safety/x509_verify.nova, x509.nova) | 437 / 906 | Partial (S-23) | Real openssl chain fixture — OK 14 | Fixture chain only | Yes |
| TLS 1.3 client (io/transducers/tls13_client.nova) | 838 | Real 1-RTT client, one suite, unauthenticated by default | RFC 8448 key schedule — OK 28 | Docs claim live runs against example.com/wikipedia (TLS_AUDIT.md); not reproducible here (no network) | Yes (`/learn https://`) |
| TLS 1.3 server (net/tls/*, 14 files) | 6247 | Partial: one suite (x25519/Ed25519/ChaCha20), opt-in | tls_kdf OK 27; tls_session OK 35 (self-handshake) | No — both ends in one process | rpc_daemon, only if `CROSSENGIN_TLS=1` |
| DTLS 1.2 (federation/dtls12.nova) | 4331 | Partial: codec + flights + AEAD; no UDP, no retransmit, no cookie | Internal KATs (PRF, GCM) — OK 519 | No | fed_daemon only if `CE_FED_TRANSPORT=dtls`, and then over TCP (non-standard shim) |
| Noise XK (io/transducers/noise_xk.nova) | 1293 | Real state machine, non-standard DH (2048-bit MODP), broken keygen | HMAC vectors only; self-handshake — OK 44 (54 s) | No | kg_sync if `CE_KGSYNC_REQUIRE_NOISE=1`; gossip Noise not wired in any binary |
| STUN (federation/stun_rfc8489.nova) | 1300 | Real codec | RFC 5769 — OK 135 | No live server test | No (test-only) |
| TURN client / server (turn.nova, turn_server.nova) | 2768 / 1289 | Codec + state machines; no sockets, no forwarding | — (not run) | No | No |
| ICE (ice.nova, ice_turn.nova) | 436 / 717 | Partial: `ice_check_pair` stub | — | No | No |
| SRTP (federation/srtp.nova) | 998 | Real codec | RFC 3711 B.3 — OK 135 | No | No |
| WebRTC (federation/webrtc.nova) | 649 | Stub: SDP strings; send/recv return error | — | No | No (`/webrtc` prints a sentence) |
| NAT traversal (nat_traversal.nova) | 1475 | Partial; hole punch stub | — | No | No |
| Merkle + signing (persistence/merkle*.nova) | 438 / 555 | Real (S-22) | SHA vectors + self-consistency — OK 60 | No | Yes |
| Raft (4 files) | 617 | In-process simulation | n/a — raft_core OK 35 | n/a | No |
| Gossip (federation/gossip.nova) | 3657 | Real TCP, plaintext | n/a | Self only | Yes (fed_daemon, chat `/gossip_start`) |
| Bully election (leader_election.nova) | 571 | Local heuristic (S-25) | n/a | n/a | Yes |
| SecAgg (learning/secure_aggregation.nova) | 1374 | Real pairwise masking over real TCP; masks cryptographically void (S-08/09) | n/a — OK 170 | Python re-implementation of the same LCG | Yes (fed_coordinator, chat) |
| DP (safety/differential_privacy.nova) | 591 | Budget counter real; noise void (S-05/06) | n/a — OK 52 (tests use fixed seeds) | n/a | Yes (`/dp_query`, fed stats) |
| Capability tokens (sandbox/capability.nova) | 843 | Bearer strings in a registry + roles + rate window; not cryptographic | n/a — capability_gate OK 40 | n/a | rpc_daemon if enforcement on |

Other suites run and passing: scram 43, merkle 60, x509_verify 14, differential_privacy 52, constitutional_filter 22. 28 of 28 suites returned rc=0.

## Network attack surface

| Listener | Started by | Default bind | Transport | Auth by default | What an unauthenticated peer can do |
|---|---|---|---|---|---|
| JSON-RPC daemon | CE/examples/crossengin_rpc_daemon.nova (`scripts/rpc_daemon.sh`) | 127.0.0.1, port required via env | Plain TCP, one JSON line per connection; optional in-house TLS | None (`CE_RPC_REQUIRE_TOKEN` opt-in) | All 53 verbs: ask/parse, install/run skills, ingest files in 9+ formats, approve ingest queue, save/load/delete sessions, issue/revoke tokens, bake child bundles (file write, S-12), apply updates |
| Gossip | fed_daemon; chat `/gossip_start` (prompts for approval) | 127.0.0.1:8770 | Plain TCP text lines | None | Read all atoms, inject atoms and peers, fetch snapshot bodies, relay, distributed query/rules (S-10) |
| kg_sync publisher | crossengin_kg_publisher | port 8766 | Plain TCP | None (`CE_KGSYNC_TOKEN` opt-in, Noise opt-in) | Subscribe to all atom events |
| Federation coordinator | crossengin_fed_coordinator | port 8777 (per comment at federated_aggregator.nova:903-905) | Plain TCP | None (`CE_FED_TOKEN` opt-in) | Join rounds, submit arbitrary stats, receive aggregates |
| web.py | manual | 127.0.0.1:8765 | HTTP | None | Full chat REPL incl. about 165 slash commands; list session ids (S-14/15) |
| rpc_web_shim.py | `scripts/serve_web.sh` | 127.0.0.1:8080 (non-loopback needs flag) | HTTP | None | 21 allow-listed RPC verbs; static files (traversal guard looks sound: `resolve()` + `relative_to`) |
| vercel backend server.py | Docker | 0.0.0.0:8080 | HTTP (TLS expected from a front proxy) | Bearer token, constant-time compare | With token: full chat REPL. `/health` is open and reveals binary path + session count |
| Vercel function | Vercel | public | HTTPS | None | Everything the backend token allows (S-13) |
| Unix socket transducer | stream_unix_socket.nova | `/tmp/crossengin.sock` | — | not reviewed in depth | SUSPECTED same class as S-18 |
| File "sockets" | daemons | `/tmp/crossengin_input`, `/tmp/crossengin_fed_input` | file poll | None | Inject input / EXIT (S-18) |

Outbound: `/learn` HTTP(S) fetch to any host (S-17); gossip dials any `host:port` a peer advertises; `scripts/learn.sh` and the `llm_*.sh` / `nl_parse_llm.sh` scripts and `OLLAMA_EXTRACTOR_MODEL` (CE/examples/crossengin_chat.nova:1701-1703) indicate shell-outs to curl and a local LLM — outside my assignment; flagged for the lead.

`.env.example` (CE/infra/vercel-proxy/web/.env.example) reveals only `CROSSENGIN_URL` and `CROSSENGIN_TOKEN` placeholders. No LLM provider or third-party service keys appear in infra/.

## Secrets scan results

Working tree, excluding `.git`:

- PEM private-key blocks (`BEGIN … PRIVATE KEY`): none. Certificate PEM markers appear only as string constants in a parser and its tests.
- Provider token patterns (`sk-…`, `ghp_…`, `AKIA…`, `xox?-…`, `AIza…`, JWTs): none.
- Hard-coded credential-like strings: `local-dev-token` (CE/infra/vercel-proxy/backend/docker-compose.yml:34), `test-token` (CE/infra/vercel-proxy/tests/test_chat_route.ts:75), `s3kret` and `ce-secagg-shared-token` (CE/tests/integration/scenario_g2_kg_sync_multi.sh:239, scenario_u_secagg.sh:80). All are test/dev values; only the compose one can ship by accident (S-29).
- Key-like files: `docs/samples/sample_agent.pub` is a 32-byte public key; `sample_agent.bundle` has a signature, no private key; `docs/caps.sample.conf` is comments. No `.priv`, `.key`, `.pem`, `.env` tracked.
- No hard-coded private keys or PSKs found as `let` constants in src/ (regex over `let *KEY/PSK/TOKEN/SECRET* = "<16+ chars>"`). Tests embed private keys as fixtures (expected).
- History (cheap check only; lead is scanning fully): 749 commits; `git log --all -S'PRIVATE KEY'` returns 1 commit (f67d941, a safety/learning change; not inspected further); no deleted files matching `*.pem|*.key|*.priv|*.env|secret|credential`.

The real "secrets" problem is S-01: keys generated by the repo's own tooling are effectively public.

## DP / SecAgg / federation reality

- **What is federated:** per-source-tag integers from the meta-observer report — promotion rate and atrophy rate in milli-units (CE/src/learning/federated_aggregator.nova:443-457, wire `FED_STAT <round> <tag> <promo> <atr>` :44-50). No synapse weights, no KG atoms, no model parameters. The result nudges a local per-source authority score by a 90/10 EMA (header :11-15). Separately, gossip/kg_sync replicate KG atoms verbatim; that is replication, not learning.
- **Is it networked:** yes. Coordinator and souls are separate processes over TCP; Python smoke clients drive integration scenarios (`scripts/fed_smoke_client.py`, `scripts/secagg_smoke_soul.py`).
- **DP:** mechanism is a two-sided geometric (discrete Laplace) with sensitivity supplied by the caller; accounting is basic sequential composition by integer subtraction (differential_privacy.nova:236-262). Calibration ratio is conservative. The guarantee is void because the noise is a fixed public sequence (S-05) and inverts at small epsilon (S-06). Live uses: chat `/dp_query` with eps=0.1 (CE/examples/crossengin_chat.nova:6466) and fed stat emission (federated_aggregator.nova:324). In SecAgg mode the raw values are masked without DP noise (federated_aggregator.nova:448-452).
- **SecAgg:** genuine pairwise additive masking with dropout reconciliation lines, run across processes. Cryptographically void: 15-bit masks, 15-bit seed hash, mask reuse across tags, no modular arithmetic, weak DH keys (S-08, S-09). The module header itself calls it an "MVP" and the audit doc lists gaps.
- **Byzantine mode** exists as an alternative (plaintext per-soul values); not reviewed.

## Raft / gossip / leader election

- Raft: four files, pure functions on lists, synchronous delivery inside one process, no sockets or timers; headers say so (CE/src/federation/raft_core.nova:1-12). Imported only by tests. CONFIRMED simulation.
- Gossip: real short-lived TCP connections between processes (CE/src/federation/gossip.nova:1081-1112). Peer selection uses xorshift with default seed 2463534242 (:596) — fine for load spreading. CONFIRMED networked.
- Bully: local heuristic; no election message crosses the wire (S-25).

## Safety layer, mechanically

| Component | What it computes | Live? | Trivial bypass? |
|---|---|---|---|
| reversibility_classifier | 10-entry if-chain: action int → 1/2/3 | Yes | n/a (table) |
| permission_tiers | 10-entry table → auto/notify/approve, then max with reversibility floor | Yes (effector gate, rpc) | n/a. Note the floor makes `speak` NOTIFY, contradicting its AUTO default (permission_tiers.nova:32 vs reversibility_classifier.nova:61) |
| capability_gate | if-chain on capability int + 4 caller-supplied 0/1 flags | Yes (chat `_gate_or_prompt`) | The caller sets the flags; chat always passes `authorized=1, source_clean=1` (crossengin_chat.nova:3621) |
| cap_session | 10-slot allow/deny override array, loadable from `~/.crossengin/caps.conf`, editable by `/cap grant` | Yes | By design the operator can grant anything; over the web surface the remote user is the operator |
| approval_prompt | reads a line from stdin, `y`/`yes` approves | Yes | S-16 |
| constitutional_filter | substring match of rule text in the input line, or KG-neighbour match; returns veto | Yes (chat :8111, daemon :653) | S-34. It screens user input text, not actions the agent takes |
| override_mechanism | sets halt/kill flags, edits belief numbers, marks goals vetoed | rpc_daemon (self.override) and chat `/halt` | n/a |
| safety_log | appends attest records to the decision log (hash-chained log lives in src/audit, not reviewed) | Yes | Log file defaults to `/tmp/crossengin.dlog` (S-19) |
| rate limiting | per-token and per-holder request counters over a nanotime window (sandbox/capability.nova, holder_rate.nova) | Only with `CE_RPC_REQUIRE_TOKEN=1` | Unknown tokens are rejected before any counter; no limit on guessing |
| content filter | No separate module exists beyond the constitution substring rule | — | — |

Unit suites for these pass (capability_gate 40, constitutional_filter 22) and they do test real branches. They establish that the tables return what the tables say.

## Relevance / drift numbers

CE/src total: 187,870 Nova LOC. Networking/crypto/protocol code:

| Bucket | LOC |
|---|---|
| src/federation (24 files) | 27,074 |
| src/safety crypto primitives (23 of 33 .nova files; excludes the 8 safety-layer files and 2 DP files) | 13,135 |
| src/net/tls (14 files) | 6,247 |
| src/persistence Merkle + signing (3 files) | 1,229 |
| net/crypto files elsewhere (noise_xk, secure_channel, tls13_client, http_client, kg_sync, stream_http, stream_unix_socket, secure_aggregation, federated_aggregator, byzantine_aggregation, dns_resolver, capability, skill_signature, holder_rate) | 11,729 |
| **Total** | **59,414 (31.6% of src)** |

For scale, the directories whose names suggest cognition (kg 14,492; parts 9,542; learning minus the federation files ≈ 5,950; agent 4,088; mind 2,463; substrate 1,974; perception 1,712; scheduler 417) total about 40,600 LOC. `src/io` (47,298) is mostly audio/image/video signal processing. Classification of those directories is by name only; other reviewers own them.

Reachability from CE/examples/*.nova (import graph): none of webrtc.nova, ice.nova, ice_turn.nova, turn.nova, turn_server.nova, srtp.nova, stun_rfc8489.nova, nat_traversal.nova is imported by any example. dtls12.nova is imported by crossengin_chat, crossengin_daemon and crossengin_fed_daemon, and is exercised only when `CE_FED_TRANSPORT=dtls`, over TCP.

## Executed

- 28 unit suites (listed in the module table): all rc=0.
- Probe `sr.nova` + `strace`: `secure_random` → EFAULT, returns −1.
- Probe `kg.nova` + Python brute force: Ed25519 seed recovered from 15-bit state.
- Probe `dp.nova`: identical noise across fresh states; noise inversion below eps=0.01.
- Probe `snap.nova`: huge `atom_count` kills the loader (rc=137).
- Import-reachability script `reach.py` over CE/examples and CE/tests.

Probes are in `/tmp/claude-0/-home-user/0f6d34e6-ba9a-56d7-bcb5-b0fca8a83a57/scratchpad/probes/ce_security/`.

## Not verified

- No exploit was run end to end against a live daemon (ECDSA key recovery, SecAgg unmasking, CSRF, newline approval bypass are from code reading).
- Whether `secure_random` also fails on macOS/ARM64/Windows targets (only Linux x86-64 was run; the ARM64 path at NOVA/src/compiler/codegen.nova:7326-7343 has a different shape).
- Live TLS 1.3 client interop claimed in TLS_AUDIT.md (no network).
- Negative-index write in the snapshot parser.
- Whether the GitHub repos are public.
- Bodies of the long codec files (turn, turn_server, srtp, stun, distributed_rules, gossip_relay*, snapshot_delta/compaction, schema_migration, bignum*) were skimmed, not read line by line; TURN/ICE/webrtc/nat/raft_cluster/gossip suites were not run.
- src/audit hash-chained decision log, src/sandbox beyond the authorize path, and src/nl/rpc_verbs.nova beyond the dispatcher and file verbs belong to other reviewers.
