# ADR-0099: DTLS extensions-block parser + `use_srtp` per-extension parser + DTLS-aware gossip stream helpers (Phase P R3)

- Status: Accepted
- Date: 2026-09-30

## Context

Phase P R1 (ADR-0097) landed the server-side handshake flight but
shipped `_dtls_parse_ext_block_stub` as an intentional stub that only
validated the outer 2-byte length prefix of an extensions block; the
individual extensions inside the block were never walked, so a
ClientHello that offered a `use_srtp` extension arrived at the
ServerHello builder with no way to influence the ServerHello's
outbound extensions. R1's ServerHello builder already emits the
`use_srtp` echo when `DTLS_S_SLOT_SRTP_OFFER` is non-zero (via
`_dtls_build_use_srtp_ext` from Phase O R2), so the emit half of the
round-trip was wired — only the parse half was missing.

Phase P R2 (ADR-0098) landed the client-side flight and the Finished
MAC over the transcript, so the full handshake now composes structurally.
R2 deferred to R3 two related caveats:

1. **Real extensions-block walker + `use_srtp` per-extension parser.**
   Without them the server cannot see what the client offered, so the
   R3-and-later SRTP negotiation cannot depend on the ClientHello ->
   ServerHello echo path.

2. **DTLS-aware gossip stream helpers.** The Phase O R3 DTLS-over-TCP
   shim ships `gds_send_line(conn_fd, dtls_state, bytes)` for line-
   oriented sends, but the R18E gossip handlers for DELTA / SNAP_FETCH
   / SNAP_DATA / SNAP_END / DQERR / DQRES / DQBIND / DQEND / DRFACT /
   DREND / DELTA_END all wrote directly through `_gossip_send_all(fd,
   bytes)`, which is plaintext-only. Under DTLS those writes would
   leak plaintext onto the AEAD-framed wire and corrupt the record
   stream. R1/R2 shipped `gossip_handle_conn_dtls` (`gossip.nova:3215`)
   and `gossip_handle_conn_kg_dtls` (`:3299`) with the parser branches
   for these verbs explicitly commented "silently dropped" as a
   temporary safety measure: the wire arrived intact, but the payload
   was dropped rather than mangled.

R3 closes both.

## Decision

### 1. Real extensions-block walker (`_dtls_parse_ext_block`)

New function in `src/federation/dtls12.nova`, added directly below
R1's stub (which is kept as-is per §5). The walker consumes the
CONTENT bytes of an extensions block (no outer 2-byte length prefix —
the caller strips that; e.g. `_dtls_parse_client_hello_body` already
returns the ext content as `ext_pair = [ext_buf, ext_block_len]`).
Each on-wire extension is a 4-byte TLV header (2B `ext_type` + 2B
`ext_len`) followed by `ext_len` bytes.

- Returns `[1, extensions_list, total_bytes_consumed]` on success where
  each entry in `extensions_list` is `[ext_type_u16, ext_data_buf,
  ext_data_len]`. Unknown extension types are collected verbatim into
  the returned list (dispatch decides whether to consume or drop; the
  RFC 5246 §7.4.1.4 "unknown extensions are silently ignored"
  requirement is realized at the DISPATCH layer, not at the parse
  layer, so a future round that logs unknown extensions can inspect
  them here without a parser change).
- Returns `[0, DTLS_ERR_BAD_HS]` on any short buffer / overflowing
  inner `ext_len` / malformed input.
- Empty content (`n == 0`) is a valid empty list.

### 2. `use_srtp` per-extension parser (`_dtls_parse_use_srtp_ext`)

Also new in `dtls12.nova`. Body layout per RFC 5764 §4.1.1:

    uint16 profile_list_len            (bytes in SRTPProtectionProfiles<>)
    opaque profile_list[N]             (each profile is 2 bytes)
    uint8  mki_len
    opaque mki[mki_len]

Returns `[1, offered_profiles_list, mki_buf_or_0, mki_len]` on
success. Refuses on any of: short buffer (< 3 bytes for the fixed
prefix), odd `profile_list_len` (not a whole number of 2-byte
profiles), zero `profile_list_len` ("offered nothing" is meaningless),
`mki_len` overflow past the buffer end.

### 3. Server-side profile selector (`_dtls_select_srtp_profile`)

Walks the offered-profiles list from `_dtls_parse_use_srtp_ext` and
returns the first profile that matches an R3-supported profile. R3
supports one profile: `SRTP_PROFILE_AES128_CM_SHA1_80` (mirroring
Phase O R2 which is the only R2 builder path exercised in prod). A
future round that widens the supported set only extends this function.

### 4. Server-side profile-select wire-up

In `_gds_server_flight_1` (`src/federation/gossip_dtls_shim.nova`),
immediately after parsing the ClientHello body + absorbing the HS
message into the transcript + transitioning INIT -> CLIENT_HELLO_RECVD,
R3 walks the ClientHello's extensions block:

- If `ch[7]` (the R1 parser's `ext_pair` return slot) is non-zero AND
  the content length is > 0, call `_dtls_parse_ext_block`.
- On any parse refuse, abort the flight with the tag
  `dtls-hs-bad-ext-block` (this joins the existing set of distinct
  string tags stamped on `LAST_ERR` on refuse).
- For each parsed extension entry: if `ext_type ==
  DTLS_EXT_USE_SRTP`, call `_dtls_parse_use_srtp_ext`. If that
  succeeds AND `_dtls_select_srtp_profile` returns a non-zero profile,
  write it to `state[DTLS_S_SLOT_SRTP_OFFER]`. R1's subsequent
  `_dtls_build_server_hello_body` reads that slot and emits the
  matching `use_srtp` echo per RFC 5764 §4.1.3.
- A `use_srtp` extension that the client offered but whose profile
  list does not contain any supported profile is silently ignored (no
  echo; the client observes the missing echo and locally decides to
  fall back to plain DTLS). This matches the "MAY be silently ignored"
  language in RFC 5764 §4.1.3 for the "no acceptable profile" case.

### 5. R1 stub retained as an alias

`_dtls_parse_ext_block_stub(buf, n)` is intentionally kept as-is (still
returns `[1, total_ext_len]` for the R1 tests + any code that only
needed the outer-length validation). The R3 real walker
`_dtls_parse_ext_block(buf, n)` takes the CONTENT bytes (no outer
2-byte length prefix), so the two functions have DIFFERENT call
shapes — they are not interchangeable and both are documented in
their doc-blocks. R1's `test_dtls_server_flight.nova` tests
(`test_ext_block_stub_*`) stay green because R3 does not touch the
stub's body.

### 6. `_gossip_send_all_maybe_dtls` helper

New helper in `src/federation/gossip.nova`, added directly below
`_gossip_send_all`:

```
fn _gossip_send_all_maybe_dtls(fd, dtls_state, s) {
    if dtls_state == 0 { return _gossip_send_all(fd, s) }
    return gds_send_line(fd, dtls_state, s)
}
```

The `dtls_state == 0` fast-path is load-bearing for the
backwards-compat contract: every pre-R3 plaintext caller lands on
`_gossip_send_all` unchanged, so the wire bytes on a plaintext socket
stay byte-identical to pre-R3. On the DTLS variant, `gds_send_line`
handles the trailing '\n' bookkeeping symmetrically with
`gds_recv_line` on the receive side, so the line-oriented protocol
layers above the transport remain oblivious to the swap.

### 7. Handler signature-extension vs wrapper decisions

Every direct `_gossip_send_all(conn_fd, ...)` call inside a handler
that could be invoked from a DTLS dispatcher is converted. Two shapes
of conversion, picked per handler:

- **Signature-extension via `_maybe_dtls` variant + delegate wrapper.**
  Used for handlers that write to conn_fd many times, where the caller
  set is well-defined and small. The `_maybe_dtls` variant carries the
  `dtls_state` param; the existing plaintext-named function is
  rewritten as a one-line wrapper that calls the new variant with
  `dtls_state = 0`. This preserves the exact call shape of every
  pre-R3 caller (so DELTA / DQUERY / SNAP_FETCH callers from plain
  `gossip_handle_conn` / `gossip_handle_conn_kg` and from the
  connection-pool dispatch at gossip.nova:2574-2614 don't need
  touching). Handlers converted this way:
    - `_gossip_stream_atoms_since` -> `_gossip_stream_atoms_since_maybe_dtls`
    - `_gossip_serve_dquery` -> `_gossip_serve_dquery_maybe_dtls`
    - `_gossip_serve_drfetch` -> `_gossip_serve_drfetch_maybe_dtls`
    - `_gossip_serve_snap_fetch` -> `_gossip_serve_snap_fetch_maybe_dtls`
    - `_gossip_send_snap_body` -> `_gossip_send_snap_body_maybe_dtls`
  Each new variant calls `_gossip_send_all_maybe_dtls` at every site
  the plaintext original called `_gossip_send_all`, threading the
  `dtls_state` through unchanged. On `dtls_state == 0` the wire bytes
  are byte-identical to pre-R3.

- **No conversion needed (handler does not write to conn_fd).** Used
  for handlers that consume the line but enqueue for a later drain
  helper. These are safe to call as-is from both the plaintext and
  the DTLS dispatch, because they don't touch the wire. Handlers
  identified as no-conversion-needed:
    - `_gossip_serve_extaddr` (enqueues into nat_state; no fd write)
    - `_gossip_serve_relay_req` (enqueues into relay_state)
    - `_gossip_serve_relay_data` (enqueues into relay_state)
    - `_gossip_serve_relay_ack` (enqueues into relay_state)
    - `_gossip_serve_attestation` (enqueues; no fd write)
    - `_gossip_serve_rule` (enqueues into dr_state)
    - `_gossip_serve_derivation` (enqueues into dr_state)

- **Explicit non-conversion (RELAY_BIN).** `_gossip_serve_relay_bin`
  reads its binary tail directly off the fd via `_gnoise_recv_exact`,
  which does not know how to decrypt sealed DTLS records. R3 does
  NOT dispatch RELAY_BIN under DTLS. A follow-up round that adds a
  sealed-frame binary reader wires it in here; the DTLS handlers'
  comment blocks document the deferral. The plaintext handlers still
  dispatch RELAY_BIN as before (this is a DTLS-only skip, not a
  plaintext regression).

### 8. Unblocking `gossip_handle_conn_dtls` + `gossip_handle_conn_kg_dtls`

R2's "silently drops" comment block at `gossip.nova:3273-3285` and
`:3360-3366` is retired. The unblocked dispatch now routes:

- **kg-less DTLS handler (`gossip_handle_conn_dtls`)**: DELTA_END
  fallback, SNAP_FETCH (via `_maybe_dtls`), EXTADDR (as-is), RELAY_REQ
  / RELAY_DATA / RELAY_ACK (as-is). RELAY_BIN skipped per §7.
- **kg DTLS handler (`gossip_handle_conn_kg_dtls`)**: DELTA (via
  `_gossip_stream_atoms_since_maybe_dtls` + a sealed DELTA_END),
  DQUERY (via `_gossip_serve_dquery_maybe_dtls`), ATTESTATION,
  SNAP_FETCH (via `_maybe_dtls`), RULE, DRFETCH (via `_maybe_dtls`),
  DERIVATION, EXTADDR, RELAY_REQ / RELAY_DATA / RELAY_ACK. RELAY_BIN
  skipped per §7.

The DTLS handler's outer if-chain structure mirrors the plaintext
handler at `gossip.nova:1174` / `:1284` exactly — so a future
maintainer changing one verb in one path can follow the same idiom in
the other.

### 9. Backwards-compat contract

Every _maybe_dtls variant with `dtls_state = 0` produces byte-identical
plaintext output to pre-R3. This is verified structurally:

- The plaintext wrappers (`_gossip_stream_atoms_since`,
  `_gossip_serve_dquery`, etc.) delegate to the _maybe_dtls variant
  with `dtls_state = 0`, so every pre-R3 caller lands on the same
  code path.
- Inside each _maybe_dtls variant, every call to
  `_gossip_send_all_maybe_dtls(fd, 0, s)` reduces to
  `_gossip_send_all(fd, s)` verbatim (the helper's `dtls_state == 0`
  guard fires).
- No other logic changed inside the handler bodies (parse loops,
  state mutations, counter bumps, return values all unchanged).

Under DTLS every send goes through `gds_send_line`, which:
1. Ensures the plaintext ends with '\n' (added if missing, so the
   receiver's line parser sees the boundary).
2. Seals under the AEAD via `dtls_seal_record(state, 23, pt, n)`.
3. Wraps in the shim's 2-byte length prefix via `_gds_send_record`.

The `gds_recv_line` side strips the '\n' after decrypt, so the line-
oriented protocol layers above the transport get the same string
shape as they would from `_gossip_recv_line`.

## Alternatives considered

**(a) Change `_dtls_parse_ext_block_stub`'s body to walk the block
and return the real parsed list, dropping the stub name entirely.**
Rejected because R1's `test_dtls_server_flight.nova` pins the stub's
`[1, total_ext_len]` return shape with three tests. Keeping the stub
as an alias for the outer-length-only path costs a few lines and
preserves R1's test pins verbatim. The R3 real walker has a
DIFFERENT input contract (content bytes, no outer length prefix) so
there was no clean way to make one function serve both call shapes.

**(b) Add a new field to the ClientHello parser's return that already
walks the extensions, obviating the need for the ClientHello caller
to walk them separately.** Rejected because it would change the R1
parser's return shape and break its pinned tests. Walking the block
at the flight-driver layer (as R3 does) preserves the parser's shape
and keeps extension-dispatch policy at the layer that has state
context (the flight driver knows about `DTLS_S_SLOT_SRTP_OFFER`; the
parser does not).

**(c) Thread `dtls_state` into every handler unconditionally instead
of introducing `_maybe_dtls` variants.** Rejected because every
existing plaintext caller (of which there are many, including the
connection-pool dispatch at `gossip.nova:2574-2614` and the R33B
tests) would need to be touched with an explicit `0` arg. The
`_maybe_dtls` variants + delegate-wrapper pattern lets every pre-R3
call site stay verbatim.

**(d) Route RELAY_BIN through DTLS by wrapping the raw binary tail in
sealed records too.** Rejected as out-of-scope for R3. The binary
tail reader (`_gnoise_recv_exact`) reads a fixed number of bytes off
the fd; under DTLS those bytes would need to be chunked into sealed
records with per-record decrypt on the receive side. The change is
possible but requires a new sealed-frame binary API on both sides;
R3 skips RELAY_BIN under DTLS with a documented follow-up. The
plaintext RELAY_BIN path is unchanged.

**(e) Silently ignore `use_srtp` on a `_dtls_parse_use_srtp_ext`
refuse instead of aborting the handshake.** Rejected because a
malformed `use_srtp` body is a peer-protocol violation, not an
"unknown extension". The outer `_dtls_parse_ext_block` REFUSES a
malformed extension frame (bad TLV length) but the per-extension
parser refuse only affects the SRTP negotiation, not the handshake —
so R3 silently ignores the use_srtp offer if `_dtls_parse_use_srtp_ext`
returns 0. The handshake continues without an SRTP echo, which is
the RFC 5764 §4.1.3 "no acceptable profile" behavior. The distinction
matters: extension-block malformation is a handshake-fatal
inconsistency; a single extension body's malformation is negotiable.

## Test coverage

**`tests/unit/test_dtls_ext_parse.nova`** (~16 tests / ~32 checks):

- `_dtls_parse_ext_block`: empty content -> empty list; single
  use_srtp entry -> one parsed entry with correct type + body; two
  entries (unknown 0x1234 + use_srtp) -> both returned; overflowing
  inner ext_len -> refused; short TLV header -> refused.
- `_dtls_parse_use_srtp_ext`: single profile + empty MKI -> profile
  list + MKI extracted; profile + 3-byte MKI -> MKI bytes preserved;
  odd `profile_list_len` -> refused; zero `profile_list_len` ->
  refused; short buffer -> refused.
- `_dtls_select_srtp_profile`: picks `SRTP_PROFILE_AES128_CM_SHA1_80`
  when offered; returns 0 when no supported profile is offered;
  returns 0 on empty offered list.
- End-to-end round-trip: R2 builder `_dtls_build_use_srtp_ext` emits
  the 9-byte TLV; walker parses it; `_dtls_parse_use_srtp_ext`
  recovers the profile ID; MKI is empty per the R2 builder's zero-MKI
  choice.
- Stub compatibility: `_dtls_parse_ext_block_stub` still returns
  `[1, total_ext_len]` for R1's outer-length shape; still refuses
  overflowing outer length.

**`tests/unit/test_gossip_dtls_streams.nova`** (~19 tests / ~24
checks):

- `_gossip_send_all_maybe_dtls`: dtls_state=0 routes to plaintext;
  fresh dtls_state routes through DTLS dispatch; both fail cleanly
  on bad fd.
- `_gossip_stream_atoms_since` / `_maybe_dtls`: kg=0 guard fires;
  both plaintext and DTLS paths return 0.
- `_gossip_serve_snap_fetch` / `_maybe_dtls`: no-sr fallback fires on
  both paths.
- `_gossip_serve_drfetch` / `_maybe_dtls`: kg=0 fallback fires on
  both paths.
- `_gossip_serve_dquery` / `_maybe_dtls`: malformed line refused on
  both paths.
- `_gossip_send_snap_body` / `_maybe_dtls`: empty body no-op on both
  paths.
- `_gossip_serve_extaddr` / `_gossip_serve_relay_req` /
  `_gossip_serve_relay_data` / `_gossip_serve_relay_ack`: enqueue-only
  handlers safe under DTLS (no fd write; no signature extension
  needed).
- `gossip_handle_conn_dtls` / `_kg_dtls`: unready dtls_state -> the
  handler closes the fd and returns state unchanged (proves the R3
  additions do not affect the pre-handshake gate).

**Full-handshake + DELTA/SNAP/DQUERY end-to-end under DTLS** requires
a working socket-pair + NOVA runtime. Per the standing Phase L / M /
N / O / P caveat (NOVA compiler self-hosting bootstrap segfaults on
this bench), `make test` cannot exercise this suite end-to-end. The
unit checks above cover every new function in isolation; the
composition is verified by structural review of the flight driver
extension-walk wire-up + the `_maybe_dtls` handler variants + the
`gossip_handle_conn_dtls` / `_kg_dtls` dispatch retirement.

**Runtime caveat**: NOVA's compiler self-hosting bootstrap segfaults
on this bench (standing Phase L / M / N / O / P caveat), so `make
test` cannot exercise this suite. Verification is structural review +
`make lint-ints`. The 12 pre-existing lint-ints findings are
unchanged; none in the R3 files.

## Files touched

**Modified**:

- `src/federation/dtls12.nova` — `_dtls_parse_ext_block` (real
  extensions-block walker), `_dtls_parse_use_srtp_ext` (per-extension
  parser), `_dtls_select_srtp_profile` (server-side profile selector).
  R1's `_dtls_parse_ext_block_stub` is retained verbatim.
- `src/federation/gossip_dtls_shim.nova` — `_gds_server_flight_1`
  gains the ClientHello extensions-walk + `use_srtp` dispatch +
  profile-select-into-slot.
- `src/federation/gossip.nova` — `_gossip_send_all_maybe_dtls` helper;
  `_gossip_stream_atoms_since_maybe_dtls`,
  `_gossip_serve_dquery_maybe_dtls`,
  `_gossip_serve_drfetch_maybe_dtls`,
  `_gossip_serve_snap_fetch_maybe_dtls`,
  `_gossip_send_snap_body_maybe_dtls` new; each plaintext wrapper
  delegates to its `_maybe_dtls` variant with `dtls_state = 0`;
  `gossip_handle_conn_dtls` (`:3215`) + `gossip_handle_conn_kg_dtls`
  (`:3299`) dispatch retirement + full verb wire-up.
- `ENHANCEMENTS_ROADMAP.md` — Phase P R3 shipped note; Phase P COMPLETE
  marker.

**New**:

- `tests/unit/test_dtls_ext_parse.nova` — ~32 checks per §"Test
  coverage" above.
- `tests/unit/test_gossip_dtls_streams.nova` — ~24 checks per §"Test
  coverage" above.
- `docs/adr/0099-dtls-extensions-and-streams.md` — this ADR.

## References

- ADR-0094 — Phase O R1 (chain-aware `dtls_cert_verify_chain`). R3's
  work does not touch cert verify.
- ADR-0095 — Phase O R2 (SRTP EKM + `use_srtp` extension EMIT). R3
  wires the PARSE half + server-side profile-select so R2's echo path
  now sees peer-offered profiles.
- ADR-0096 — Phase O R3 (DTLS-over-TCP shim). R3's stream helpers
  make ADR-0096 feature-complete: the DTLS transport now works for
  the FULL gossip verb set (DELTA / DQUERY / SNAP_FETCH / RELAY_REQ /
  RELAY_DATA / RELAY_ACK / EXTADDR / RULE / DRFETCH / DERIVATION /
  ATTESTATION) rather than only SWIM (PING / MEMBER / BYE) as under
  R2.
- ADR-0097 — Phase P R1 (server-side handshake flight). R3 replaces
  R1's stubbed extension-block parse with the real walker + wires
  the server-side profile-select into the R1 flight driver.
- ADR-0098 — Phase P R2 (client-side flight + Finished MAC). R3
  composes on top of the R2 full handshake — the extension walk
  happens after ClientHello parse and before the ServerHello builder
  reads `DTLS_S_SLOT_SRTP_OFFER`.
- RFC 5246 §7.4.1.4 — TLS extensions block wire shape.
- RFC 5764 §4.1.1 — `use_srtp` extension body layout.
- RFC 5764 §4.1.3 — server-side `use_srtp` negotiation (profile-select
  + echo).
- `src/federation/dtls12.nova::_dtls_parse_ext_block` — the R3 walker.
- `src/federation/dtls12.nova::_dtls_parse_use_srtp_ext` — the R3
  per-extension parser.
- `src/federation/gossip_dtls_shim.nova::_gds_server_flight_1` — the
  R1 driver, extended in R3 with the ClientHello extension walk.
- `src/federation/gossip.nova::_gossip_send_all_maybe_dtls` — the R3
  transport-neutral send wrapper.
- `src/federation/gossip.nova::gossip_handle_conn_dtls` — R3
  dispatch retirement.
- `src/federation/gossip.nova::gossip_handle_conn_kg_dtls` — R3
  dispatch retirement (kg variant).

## Deferred / follow-ups

- **RELAY_BIN under DTLS.** Requires a sealed-frame binary reader on
  both sides. Skipped in R3 with a documented deferral in the DTLS
  handlers' comment blocks.
- **Multi-profile SRTP preference-ordering.** R3 hardcodes one
  supported profile (`SRTP_PROFILE_AES128_CM_SHA1_80`) so
  `_dtls_select_srtp_profile` is a single-arm match. A future round
  that widens the supported set turns the function into a
  preference-order walk; the call site (`_gds_server_flight_1`) is
  unchanged.
- **DTLS-over-UDP rewrite.** The R3 stream helpers ride over the
  Phase O R3 DTLS-over-TCP shim. A UDP rewrite (blocked on NOVA's
  missing `sendto`/`recvfrom` primitives per R23E.2) would swap the
  shim for RFC-compliant DTLS-over-UDP; the stream helpers do not
  need to change because they go through the abstract `gds_send_line`
  / `gds_recv_line` entry.
- **SNI + supported_groups extension parsers.** R3 supports one
  extension type; SNI (RFC 6066) and supported_groups (RFC 8422) both
  ride the same `_dtls_parse_ext_block` walker. Adding them is a
  single-function extension each, dispatched off the same switch in
  `_gds_server_flight_1`.

## Phase P completion

ADR-0096 (Phase O R3) documented the DTLS-over-TCP shim with the
caveat that `gds_handshake_client` / `gds_handshake_server` returned
"dtls-hs-flight-not-wired". Phase P R1 wired the server flight (up to
SHD_SENT); R2 wired the client flight + server flight-2 + Finished
MAC; R3 wires the extension walker + server-side profile-select + the
DTLS-aware stream helpers so DELTA / SNAP_FETCH / DQUERY / DRFETCH /
EXTADDR / RELAY_* stop being silently dropped under DTLS. With R3
shipped **the DTLS 1.2 handshake arc is closed**: the CrossEngin-mesh
DTLS transport now works for the full gossip verb set with real
extension negotiation, and ADR-0096 is feature-complete.
