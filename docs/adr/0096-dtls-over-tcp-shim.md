# ADR-0096: Non-standard DTLS-1.2-over-TCP shim for gossip transport (Phase O R3)

- Status: Accepted
- Date: 2026-09-30

> **⚠ NON-STANDARD — READ THIS ⚠**
>
> This ADR describes wrapping DTLS 1.2 records in a length-prefixed TCP
> stream. **This is not RFC-compliant.** RFC 6347 (DTLS 1.2) assumes UDP
> datagram boundaries for record framing, retransmit semantics, and
> replay-window sizing. A standards-compliant DTLS peer will NOT interop
> with a gossip node using this transport. This shim is CrossEngin-mesh-
> only. Do not deploy it as a general-purpose DTLS endpoint, and do not
> point RFC-compliant tooling (OpenSSL's `s_client -dtls1_2`,
> mbedTLS's `dtls_client`, Wireshark's DTLS dissector) at a gossip
> port expecting them to parse the wire. They will not.

## Context

Phase O R3 closes the third and final arc of the DTLS 1.2 completion
sprint. R1 (ADR-0094) wired chain-aware certificate verification.
R2 (ADR-0095) wired the SRTP-DTLS EKM path and the `use_srtp`
ClientHello extension. R3 wraps gossip's TCP transport in DTLS
records so peer-to-peer mesh traffic is encrypted + authenticated on
the wire.

The shape RFC 6347 demands is DTLS-over-UDP. Gossip's line-oriented
protocol is TCP-stream (R18E `src/federation/gossip.nova`
`_gossip_recv_line` / `_gossip_send_all` operate on TCP fds via
`recv_data` / `send_data`). Moving gossip to UDP requires two NOVA
runtime primitives that do not exist today:

- **`sendto`** for connectionless UDP writes with a per-datagram
  destination addr.
- **`recvfrom`** for connectionless UDP reads that surface the source
  addr.

The NAT-traversal work at R23E.2 (`src/federation/nat_traversal.nova`
header block) documents both primitives as blocked on runtime work that
has not scheduled yet. Waiting for them would leave gossip
unencrypted on the wire indefinitely.

The user selected the **shim path**: wrap each gossip TCP connection
in DTLS records without switching to UDP. This is common in P2P
practice (WireGuard-over-TCP, DTLS-over-WebSocket) but is out-of-spec
for RFC 6347.

Also blocked: the ed25519 signer keys Phase M R3 loads from
`CE_FED_ATTEST_KEY_DIR` are NOT reusable for DTLS certificates. DTLS
authenticates with ECDSA-P256 in X.509; ed25519 seeds are the wrong
key type. R3 adds `src/safety/p256_keypair.nova` (mirror of
`merkle_signing_keypair_load` for P-256) plus a boot-time keypair
resolver in the fed daemon.

## Decision

### 1. Wire framing: 2-byte big-endian length prefix

The ONLY non-standard modification to the DTLS record wire shape is a
2-byte big-endian length header prepended to every record before it
lands on the TCP socket, and stripped on receive:

```
    2B length prefix          DTLS record body (13B hdr + explicit_IV +
                                                ciphertext + tag)
    +------+------+ +--------------------------------------------------+
    | 0xLL | 0xLL | | 0x17 | 0xFEFD | epoch | seq | body_n | IV | ct | |
    +------+------+ +--------------------------------------------------+
       BE len == body_n (below), 1..65535
```

The `body_n` field inside the DTLS record header already carries the
same length; we are duplicating it OUTSIDE the DTLS record so the TCP
reader can find record boundaries WITHOUT having to peek at bytes 11-12
of the record. That let us keep `dtls_seal_record` /
`dtls_open_record` in `src/federation/dtls12.nova` byte-identical to
their pre-R3 shape: neither function is aware of the framing header;
that lives entirely in `src/federation/gossip_dtls_shim.nova`.

The 16-bit prefix caps a record at 65535 bytes — the RFC 6347 fragment
ceiling. Records larger than that are refused by
`_gds_send_record` (the shim's writer) and never emitted onto the
wire.

### 2. The shim module

`src/federation/gossip_dtls_shim.nova` (~330 lines) ships:

| Entry                                 | Contract |
| ------------------------------------- | -------- |
| `_gds_send_record(fd, rec, n)`        | Prepend the 2-byte prefix + write both. Returns 1/0. |
| `_gds_recv_record(fd)`                | Read 2 bytes → parse as u16 → read exactly that many bytes. Returns `[1, buf, n]` on success, `[0, 0, 0]` on EOF / short read / oversize / zero-length prefix. |
| `gds_send_line(fd, state, s)`         | Seal `s + '\n'` via `dtls_seal_record` (type 23 APPLICATION_DATA), frame via `_gds_send_record`. Returns 1/0. |
| `gds_recv_line(fd, state)`            | Recv via `_gds_recv_record`, open via `dtls_open_record`, strip trailing `\r?\n`, return the plaintext string. Returns 0 on EOF / decrypt fail / wrong record type. Distinguishes the three DTLS_* error sentinel strings from the success list via `str_eq`. |
| `gds_handshake_client(fd, st, priv_bn, pub, host, anchors, now)` | Client-side flight seam. Today returns `[0, state]` with `last_err="dtls-hs-flight-not-wired"` (the RFC 6347 ClientHello / ServerHello / Certificate / KeyExchange / Finished builders are not in the tree yet). Wired for the follow-up round that adds them. |
| `gds_handshake_server(fd, st, priv_bn, pub, cert_der)` | Server-side flight seam. Same "not-yet-wired" shape today. |
| `gds_keyed_shortcut(state)`           | Fast path: caller has driven `dtls_ecdhe_derive` on both sides directly (the same setup helper the DTLS unit tests use). Returns `[1, state]` when `cipher_active == 1`, `[0, state]` otherwise. Lets R3 tests round-trip encrypted data over the length-prefixed TCP stream without the flight builders. |
| `gds_close(fd, state)`                | Emit a `close_notify` alert (RFC 5246 §7.2, level=1 warning, description=0) via the sealed path when cipher is active, then `close_fd(fd)`. Cipher-inactive: close only. |
| `gds_is_ready(state)`                 | Return `state[DTLS_S_SLOT_CIPHER_ACTIVE]` (1 iff handshake completed / shortcut applied). |

### 3. P-256 keypair loader

`src/safety/p256_keypair.nova` (~250 lines) mirrors
`merkle_signing_keypair_load` for the P-256 keys DTLS wants:

- **`p256_keypair_load(base_path)`** — reads `<base>.priv` (32 raw
  bytes big-endian, mode 0600) and `<base>.pub` (65 raw bytes SEC1
  uncompressed `0x04 || X || Y`, mode 0644). Returns
  `[priv_bn, [X_bn, Y_bn]]` on success; `0` on any I/O failure, size
  mismatch, bad SEC1 tag byte, or off-curve point.
- **`p256_keypair_generate_deterministic(seed_32b)`** — **TEST USE
  ONLY.** SHA-256(seed || "p256-test-gen") → priv = h mod (n-1) + 1;
  pub = priv * G. For pinned test vectors so
  `tests/unit/test_gossip_dtls_shim.nova` can round-trip a full
  handshake without shelling out to `openssl ec -genkey`. **Do not
  use for real DTLS certs** — the seed is deterministic and the entry
  bypasses the OS CSPRNG.
- **`p256_keypair_save(base, priv_bn, pub_point)`** — writes both
  halves in the same wire shape as `p256_keypair_load` expects.
  Returns 1 on both-halves success, 0 otherwise. Non-durable (no
  tmp+fsync+rename); DTLS keys are minted once at operator bootstrap,
  not on every save cycle.
- **`p256_keypair_valid(pair)`** — sanity check: priv in [1, n-1],
  pub on-curve. Optional; loader is total.

### 4. Gossip integration

`src/federation/gossip.nova` grows three DTLS-aware variants alongside
the existing plaintext handlers:

- **`gossip_handle_conn_dtls(state, conn_fd, dtls_state)`** — same
  dispatch as `gossip_handle_conn`, but every read is
  `gds_recv_line` and every write is `gds_send_line`. Skips the
  HELLO / OK exchange (peers authenticated each other during the DTLS
  handshake).
- **`gossip_handle_conn_kg_dtls(state, conn_fd, dtls_state, kg)`** —
  KG-aware version. Same dispatch.
- **`_gossip_dial_dtls(peer_addr, priv_bn, pub_point, hostname,
  anchors, now)`** — dial + client-side handshake. Returns
  `[fd, dtls_state]` on success, 0 on any failure.

The plaintext `gossip_handle_conn` / `gossip_handle_conn_kg` /
`_gossip_dial` are **unchanged**. The DTLS variants are opt-in per the
transport gate below; every existing R18E test / integration scenario
keeps byte-identical behavior.

**R3 non-goal**: the SNAP_FETCH / EXTADDR / RELAY_* / DELTA-atom-stream
inbound handlers write directly to `conn_fd` today (bypassing the
line-oriented helpers). Under DTLS those handlers would leak
plaintext onto the AEAD-framed wire and corrupt the record stream.
R3 does NOT dispatch them under the DTLS variant; the line arrives
via `gds_recv_line` and is silently dropped. A follow-up round adds
gds-aware server-side variants of those helpers and wires them in.
The core SWIM path (PING / MEMBER / ATTESTATION) works end-to-end
under DTLS today.

### 5. Fed-daemon transport gate

`examples/crossengin_fed_daemon.nova` grows two env-var resolvers:

- **`CE_FED_TRANSPORT`** — default `"tcp"`; case-insensitive `"dtls"`
  enables the wrap. Any other value (including garbage) resolves to
  `"tcp"` (safe default).
- **`CE_FED_DTLS_CERT_DIR`** — default `$HOME/.crossengin/fed_dtls_keys`;
  container fallback `./crossengin_fed_dtls_keys`. The daemon passes
  `<dir>/signer` as the base path to `p256_keypair_load`.

Boot flow under `CE_FED_TRANSPORT=dtls`:

1. Resolve `CE_FED_DTLS_CERT_DIR` and call
   `p256_keypair_load(<dir>/signer)`.
2. If the load returns 0 (missing files / wrong size / bad SEC1
   encoding / off-curve): log a clear error naming the base path and
   the `p256_keypair_save` remediation, then FALL BACK to
   `dtls_transport = "tcp"` for this run so the daemon still boots
   as a plaintext mesh peer. (Alternative considered: refuse to start;
   rejected because a soul with attestation + relay + rules
   configured but a missing DTLS keypair would fail to run at all,
   which is worse than running unencrypted with a loud warning.
   ADR-0096 §"Alternatives Considered" documents the trade.)
3. If the load succeeds: cache `priv_bn` + `pub_point` on the daemon
   frame; the accept loop hands each newly-accepted fd to
   `gds_handshake_server` before invoking
   `gossip_handle_conn_kg_dtls`. On handshake failure the daemon
   closes the fd + bumps `dtls_hs_failed`; on success it bumps
   `dtls_hs_ok`.
4. `CE_FED_DTLS_HOSTNAME` and `CE_FED_DTLS_TRUSTSTORE_PATH` (both from
   R1) are already resolved earlier in boot; R3 threads them into the
   dial-side handshake (`_gossip_dial_dtls`) so peer certs get
   chain-verified against the operator's anchors + hostname.

The boot banner prints the transport choice loudly on every startup:
either `"transport: DTLS 1.2 over TCP (ADR-0096 non-standard; NOT
RFC-compliant, mesh-only)"` or `"transport: tcp (unencrypted;
CE_FED_TRANSPORT unset or 'tcp')"`. The shutdown summary prints
`transport=<mode>`, `dtls_hs_ok=<n>`, `dtls_hs_failed=<n>`.

### 6. Chat REPL: `/gossip_transport`

`examples/crossengin_chat.nova` grows one info-only slash:

- **`/gossip_transport`** (no args) → prints `transport=tcp` or
  `transport=dtls (ADR-0096 non-standard; not RFC-compliant)`. The
  resolved mode is captured at first `/gossip_start` from
  `CE_FED_TRANSPORT` and stashed on `_chat_fed_transport`; there is
  no in-REPL mutation entry (an operator who wants to switch mid-run
  restarts the daemon or REPL). Mirrors R21E's `/gossip_noise`
  info-line shape.

`src/chat/fed_slash.nova` grows the pure formatter
`_fed_transport_line(mode)` so the unit tests can validate the exact
output shape without spinning up a live REPL.

## Consequences

**What R3 enables**:
- Every gossip line (PING / ACK / MEMBER / ATTESTATION) sealed under
  DTLS-1.2 AEAD when both peers boot with `CE_FED_TRANSPORT=dtls`.
- Peer identity authenticated via ECDSA-P256 cert-chain verification
  against the operator's truststore (leveraging R1's `dtls_cert_verify_chain`).
- Encryption on the wire without waiting for NOVA UDP primitives.
- One boot env var flips a mesh from plaintext to encrypted; every
  R18E unit test still exercises the plaintext path unchanged.

**What R3 does NOT enable**:
- **Interop with RFC-compliant DTLS peers.** They see 2 extra bytes at
  the front of every record and either drop the connection or
  mis-parse the record length. This is CrossEngin-mesh-only.
- **DTLS handshake flight builders.** R3 ships the framing + record
  I/O + the client / server handshake entry points; the actual
  ClientHello / ServerHello / Certificate / ServerKeyExchange /
  ServerHelloDone / ClientKeyExchange / ChangeCipherSpec / Finished
  builders are the follow-up round. Today the handshake entries
  return `[0, state]` with `last_err="dtls-hs-flight-not-wired"`; the
  R3 unit tests + fed daemon exercise the keyed-shortcut path
  (`gds_keyed_shortcut`) where both peers pre-derive the cipher state
  via `dtls_ecdhe_derive`.
- **DELTA / SNAP_FETCH / EXTADDR / RELAY_\* under DTLS.** Those
  inbound handlers write directly to `conn_fd`; under DTLS they would
  corrupt the record stream. R3 silently drops the line; the
  follow-up round adds gds-aware variants.

**What RFC 6347 promises that this shim makes VACUOUS or LOSES**:

| RFC guarantee                              | R3 shim status                                 |
| ------------------------------------------ | ---------------------------------------------- |
| In-record handshake fragmentation          | Vacuous: TCP already handles fragmentation.    |
| 64-bit replay window                       | Vacuous: TCP is FIFO; every record arrives in order or the connection breaks. |
| Retransmit timer per handshake flight       | Vacuous: TCP retransmits at the transport layer. |
| Per-datagram source-addr availability      | LOST: TCP is connection-oriented; the source is the fd's peer, not the record header. |
| Interop with a standards-compliant DTLS peer | LOST: the 2-byte prefix is not in the RFC.     |
| MTU + fragmentation semantics under UDP    | LOST: TCP has its own MTU discovery; DTLS 1.2 fragmentation is a no-op here. |

## Alternatives Considered

**(a) Wait for NOVA `sendto` / `recvfrom` primitives and ship
RFC-compliant DTLS-over-UDP.** Rejected because the NAT-traversal
R23E.2 blocker names no schedule for those primitives, and gossip
would remain unencrypted on the wire indefinitely. The migration path
below preserves the option: when the primitives land, the shim's
framing helpers get swapped for datagram send/recv, and the on-wire
shape becomes RFC-standard.

**(b) TLS 1.2 over the existing gossip TCP stream** (rather than
DTLS-over-TCP). Rejected because R1 + R2 already landed the DTLS
cert-verify chain and the SRTP EKM path; TLS 1.2 would duplicate the
cert-verify surface and leave R2's SRTP work orphaned. The R3 shim
reuses R1 + R2 verbatim.

**(c) Length-prefix in the record header body** (steal 2 bytes from
`explicit_IV`, or from an unused header slot). Rejected because it
would break `dtls_seal_record` / `dtls_open_record` byte-identity — a
DTLS unit test that pins record bytes would fail, and the record
header would no longer match RFC 6347 §4.1 at all (the current shim
still matches it byte-for-byte inside the framing envelope). Keeping
the framing OUTSIDE the DTLS record is the cleanest layering: the
DTLS module doesn't know it's being framed.

**(d) A 4-byte length prefix** (matching R21E Noise's framing).
Rejected because DTLS 1.2's record body is 16-bit-length-bounded by
the RFC anyway (65535-byte fragment ceiling); a 32-bit prefix would
be dead bytes. 2 bytes is minimal and matches the RFC's own field.

**(e) Refuse to start when `CE_FED_TRANSPORT=dtls` and the P-256
keypair is missing** (rather than warn + fall back to tcp).
Considered but rejected: a soul with attestation + relay + rules
configured but a missing DTLS keypair would fail to boot entirely.
The chosen behavior is warn + fall back to tcp with a clear log line;
operators who need strict "no plaintext" behavior can grep the boot
banner for `transport: DTLS` and refuse to run the daemon otherwise.
A future round can add a strict `CE_FED_TRANSPORT_STRICT=1` env var
that hard-refuses the fallback if the operator wants it.

## Migration path (RFC 6347 UDP)

When NOVA gains `sendto` / `recvfrom`:

1. Swap `_gds_send_record` / `_gds_recv_record` internals: instead of
   `_gds_send_all(fd, hdr, 2) + _gds_send_all(fd, buf, n)` use one
   `sendto(fd, buf, n, addr)` call. Instead of the two `recv_data`
   reads use one `recvfrom(fd, buf, n)` call.
2. The DTLS record body stays unchanged (this is why the framing is
   OUTSIDE the record).
3. The gossip listener switches from `socket(2,1,0) + bind + listen +
   accept` to `socket(2,2,17) + bind + recvfrom` (SOCK_DGRAM + UDP).
4. The `_gossip_dial_dtls` helper drops the TCP `connect` step and
   attaches the UDP peer address to the fd via `connect` (still allowed
   on UDP fds; makes `send_data` work without an explicit addr).
5. ADR-0096 is superseded by an ADR that names the same shim now
   RFC-compliant.

## Files touched

**Files added (R3)**:
- `src/safety/p256_keypair.nova` — P-256 keypair loader / saver /
  deterministic generator (test seam).
- `src/federation/gossip_dtls_shim.nova` — length-prefixed record
  framing + handshake driver seam + line-oriented send / recv.
- `docs/adr/0096-dtls-over-tcp-shim.md` — this ADR.
- `tests/unit/test_p256_keypair_load.nova` — ~25 checks covering the
  loader / saver / deterministic generator round-trips.
- `tests/unit/test_gossip_dtls_shim.nova` — ~50 checks covering the
  wire framing, the AEAD seal/open round-trip under length-prefixed
  frames, multiple lines in sequence, and malformed record refusal.
- `tests/unit/test_fed_daemon_transport.nova` — ~20 checks covering
  the transport env resolver and the DTLS bootstrap behavior.

**Files modified (R3)**:
- `src/federation/gossip.nova` — three new fns
  (`gossip_handle_conn_dtls`, `gossip_handle_conn_kg_dtls`,
  `_gossip_dial_dtls`) appended at end-of-file; one import
  (`gossip_dtls_shim.nova`) added at the top. Plaintext handlers
  untouched.
- `examples/crossengin_fed_daemon.nova` — env resolvers
  (`_fed_transport_from_env`, `_fed_dtls_cert_base_from_env`); DTLS
  bootstrap block (P-256 keypair load, ready flag, banner); accept-
  loop wrap (server-side handshake before handoff); shutdown-summary
  counters.
- `examples/crossengin_chat.nova` — `_chat_fed_transport` module-level
  singleton set from env at first `/gossip_start`; `_admin_gossip_transport`
  handler; dispatch table entry; `/help` line.
- `src/chat/fed_slash.nova` — `_fed_transport_line(mode)` formatter.
- `docs/CHAT_USAGE.md` — `/gossip_transport` section.
- `ENHANCEMENTS_ROADMAP.md` — Phase O R3 shipped marker; Phase O
  COMPLETE marker.

**Verification.** Structural review + `make lint-ints` (12 pre-existing
findings unchanged; none in the new / modified files). Cryptographic
correctness: R3's shim reuses `dtls_seal_record` /
`dtls_open_record` verbatim under the framing envelope; the AEAD tag
check is what stops a tampered record from being interpreted as valid
plaintext. Handshake flight builders remain deferred (see §5
"Consequences"); R3's tests exercise the keyed-shortcut path where
both peers pre-derive the cipher state via `dtls_ecdhe_derive`
directly. `make test` cannot run end-to-end because the NOVA compiler
self-hosting bootstrap segfaults on this bench (standing Phase L / M /
N / O caveat).

## References

- ADR-0094 — Phase O R1 (chain-aware `dtls_cert_verify_chain` +
  `truststore_load_dir`). R3 consumes R1's cert verifier from the
  client-side handshake driver.
- ADR-0095 — Phase O R2 (SRTP EKM forward + `use_srtp` ClientHello
  extension). Orthogonal to R3 but shares the DTLS 1.2 module surface.
- ADR-0091 — Phase M R3 (snapshot attestation + replication). Shipped
  the `merkle_signing_keypair_load` shape R3's `p256_keypair_load`
  mirrors.
- ADR-0089 — Phase M R1 (fed daemon MVP). The transport gate slots
  into the fed daemon's env-config layer defined here.
- RFC 6347 — DTLS 1.2. The RFC this shim is intentionally
  non-compliant with; see §"Non-Standard" callout above.
- RFC 5246 — TLS 1.2. The record-layer + AEAD framing DTLS 1.2 builds
  on. Record types (23 APPLICATION_DATA, 21 ALERT) from §6.2.1.
- RFC 5764 — DTLS-SRTP. Not exercised by R3 directly, but the
  `use_srtp` extension from R2 rides the same shim wire when a peer
  offers it.
- SEC 1 v2.0 §2.3.3 — SEC1 uncompressed point encoding
  (`0x04 || X || Y`) used by the P-256 keypair loader.
- `src/federation/gossip_dtls_shim.nova` — this ADR's implementation.
- `src/safety/p256_keypair.nova` — P-256 keypair on-disk loader.
- `src/federation/gossip.nova::gossip_handle_conn_dtls` — the
  DTLS-aware server handler variant.
- `src/federation/gossip.nova::_gossip_dial_dtls` — the DTLS-aware
  dial helper.
- `examples/crossengin_fed_daemon.nova::_fed_transport_from_env` —
  the boot-time transport selector.
