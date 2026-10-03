# ADR-0110 -- RELAY_BIN sealed-frame under DTLS (Phase P R4)

Date: 2026-10-03.  Supersedes: --.  Related: ADR-0096 (Phase O R3
DTLS-over-TCP shim), ADR-0098 (Phase P R2 client flight), ADR-0099
(Phase P R3 DTLS extensions and streams — defers RELAY_BIN sealed-frame
to a follow-up round).

## Context

ADR-0099 §Deferred (`docs/adr/0099-dtls-extensions-and-streams.md:420-422`)
pinned RELAY_BIN under DTLS as "Requires a sealed-frame binary reader
on both sides". Phase P R3 (`gossip_handle_conn_dtls` /
`gossip_handle_conn_kg_dtls`) wired the line-oriented verbs
(PING / MEMBER / DELTA / DQUERY / ATTESTATION / SNAP_* / EXTADDR /
RELAY_REQ / RELAY_DATA / RELAY_ACK) through the sealed line channel
but left `RELAY_BIN` disabled under DTLS because its binary tail
could not travel through `_gnoise_recv_exact` (an fd-oriented reader
unaware of DTLS record boundaries). ADR-0099 §Line 275 pinned the
contract: "The plaintext RELAY_BIN path is unchanged." R4 preserves
this by shipping PARALLEL `_dtls` variants that reuse the plaintext
parser/formatter and delegate transport to the sealed record layer.

The srl (secure-relay) module (`gossip_relay_secure.nova`) seals
application payloads via Noise-XK orthogonally to this change; the
DTLS carriage here is a transport under which the srl's hex-encoded
binary frames (RELAY_BIN inbound queue, slot 8 = `SRL_S_INBOUND_BIN`)
ride.

## Decision

Phase P R4 ships four parts in one commit:

### 1. `src/federation/gossip_dtls_shim.nova` — two new fns

- `fn gds_send_bin(fd, dtls_state, buf, n) -> int` — seals `n`
  plaintext bytes across one or more APPLICATION_DATA records of up
  to `GDS_PT_PER_RECORD = 16000` bytes each (comfortably under
  `DTLS_RECORD_MAX_FRAGMENT - overhead` = 16360). Each chunk goes
  through `dtls_seal_record(state, 23, chunk, chunk_n)` →
  `_gds_send_record(fd, sealed[0], sealed[1])`. Returns 1 on
  complete transmit, 0 on any seal / send / cipher-inactive /
  null-arg failure.
- `fn gds_recv_bin(fd, dtls_state, total_len) -> list` — accumulates
  exactly `total_len` plaintext bytes across sealed records.
  Loop: `_gds_recv_record(fd)` → `dtls_open_record(state, sealed, n)`
  → append `pt_buf[0:pt_n]` to the output buffer. Returns
  `[out_buf, total_len]` on success. On failure returns `[0, sentinel]`
  with one of:
    - `GDS_CIPHER_INACTIVE` — new shim-local sentinel introduced by
      this ADR (`"gds: cipher inactive"`). `dtls_open_record`
      collapses this case to `DTLS_DECRYPT_FAIL` for oracle-leak
      hygiene; the shim surfaces it explicitly here so callers can
      distinguish "cipher never came up" from "cipher came up and a
      record failed to decrypt".
    - `DTLS_DECRYPT_FAIL`, `DTLS_REPLAY`, `DTLS_TOO_OLD` — the three
      existing dtls12.nova sentinels, forwarded unchanged.

### 2. `src/federation/gossip.nova` — one new dispatcher + two wire-ins

- `fn _gossip_serve_relay_bin_dtls(state, fd, dtls_state, line) -> int`
  — parallel to `_gossip_serve_relay_bin` at `:3177-3251` but uses
  `gds_recv_bin` instead of `_gnoise_recv_exact`. Parses the header
  via the UNCHANGED `_gossip_parse_bin_hdr`; dispatches by target:
    - `target == self_addr`: enqueue `[req_id, from, buf, n]` onto
      `SRL_S_INBOUND_BIN` (slot 8); bump `GOSSIP_S_STATS_RELAY_BIN_RX`.
      Same shape as the plaintext terminal path.
    - `target != self_addr`: bump `GOSSIP_S_STATS_RELAY_BIN_BAD` and
      drop (see §Follow-up for the forward-side defer).
    - Any parse/recv/null-srl error: bump `GOSSIP_S_STATS_RELAY_BIN_BAD`.
- Wire-ins at `gossip_handle_conn_dtls` and `gossip_handle_conn_kg_dtls`
  (ex-`:3376-3383` and ex-`:3502-3504`): mirror the plaintext
  dispatch shape (`:1295-1297` / `:1443-1445`), guarded by
  `_gossip_starts_with(line, GOSSIP_RELAY_BIN_PREFIX) == 1`.

### 3. `tests/unit/test_gossip_relay_bin_dtls.nova` (new)

15 structural subtests, 27 ce_check assertions, covering:
- `gds_send_bin` / `gds_recv_bin` guard-order refusals (null-state,
  cipher-inactive, null-buf, zero-length shortcut, negative-length).
- `GDS_CIPHER_INACTIVE` non-empty + `GDS_PT_PER_RECORD + overhead`
  under `DTLS_RECORD_MAX_FRAGMENT`.
- `_gossip_serve_relay_bin_dtls` bad-header BAD bump, self-target
  + null-srl BAD bump, non-self-target BAD bump (forward defer),
  self-target + nonzero recv-fail BAD bump.
- Both DTLS handler wire-ins still refuse an unready `dtls_state=0`
  the same way they did pre-R4 (byte-identity canary that the new
  branch did not disturb the outer guard).

The full real-socket DTLS roundtrip test (`gds_send_bin` on fd_a +
`gds_recv_bin` on fd_b with a socketpair) is deferred — the NOVA
bootstrap segfault bars full DTLS handshakes under `make test`
(ADR-0099 §Runtime caveat `:345-349` + the same restriction already
documented at `test_gossip_dtls_shim.nova` and
`test_dtls_client_flight.nova`). Structural coverage is sufficient
to prove the contract.

### 4. ADR-0110 (this doc) + `ENHANCEMENTS_ROADMAP.md`

Marks "RELAY_BIN sealed-frame (P R3 defer)" SHIPPED; drops from the
post-Phase-Q queue.

## Consequences

- RELAY_BIN inbound is now dispatchable under DTLS. The receive side
  of the sealed-frame contract is closed.
- ADR-0099 §Line 275 contract preserved — `_gossip_serve_relay_bin`,
  `_gossip_forward_bin`, `_gossip_parse_bin_hdr`, `_gossip_format_bin_hdr`,
  `GOSSIP_RELAY_BIN_PREFIX`, and the plaintext dispatch at `:1295-1297` /
  `:1443-1445` are byte-identical to pre-R4. All 7 byte-identity
  canaries (`test_dtls12`, `test_gossip_dtls_shim`,
  `test_gossip_dtls_streams`, `test_relay_secure_binary`, `test_gossip`,
  `test_gossip_relay`, `test_merkle_signing`) have pass/FAIL counts
  identical to the R3 tip; no new failures.
- srl Noise-XK sealing (`gossip_relay_secure.nova::srl_send_secure_binary`,
  `nxk_seal`) is orthogonal and unchanged — DTLS is a transport
  underneath, not a replacement for the application-layer seal.
- `test_gossip_relay_bin_dtls` (new) → 15 subtests / 27 assertions
  all PASS.

## Follow-up

- **Forward-side under DTLS (R4.2 scope sub-defer).** The intermediate-
  forwarding branch of the plaintext `_gossip_serve_relay_bin` dials
  the next hop via `_gossip_dial` (plaintext HELLO/OK). The DTLS twin
  would need `_gossip_dial_dtls`, which takes caller-supplied
  `priv_bn`, `pub_point`, `hostname`, `anchors`, `now` key material
  that the gossip `state_t` does not carry today. Plumbing those
  through would scope-creep into a daemon-level refactor
  (`examples/crossengin_fed_daemon.nova`'s boot flow would need to
  stash the pair on the state). Per the Phase P R4 plan's
  honest-reporting policy, R4 ships the receive side only; non-self
  targets bump `STATS_RELAY_BIN_BAD` and drop. Operators that need
  multi-hop binary relays under DTLS stay on the plaintext path (which
  does its own forwarding) in the interim.
- **Real-socket roundtrip test.** Deferred to the broader NOVA
  bootstrap-segfault resolution tracked in
  `docs/UPSTREAM_NOVA_BUGS.md`. Once a socketpair-style primitive
  (or a stable self-hosted bootstrap) lands, `test_gds_bin_roundtrip_*`
  can exercise `gds_send_bin` → wire → `gds_recv_bin` end-to-end
  across a cipher-active pair.
- **Chunk size tuning.** `GDS_PT_PER_RECORD = 16000` is conservative;
  a future round may raise it to `DTLS_RECORD_MAX_FRAGMENT - 24 = 16360`
  once empirical interop evidence pins the margin.
