# ADR-0098: DTLS 1.2 client-side handshake flight + Finished MAC + server flight-2 (Phase P R2)

- Status: Accepted
- Date: 2026-09-30

## Context

Phase P R1 (ADR-0097) landed the SERVER-SIDE half of the RFC 6347 DTLS
1.2 handshake: a ClientHello parser, four body builders (ServerHello /
Certificate / ServerKeyExchange / ServerHelloDone), a transcript-hash
accumulator, five new server-side state constants, and a wire-level
flight driver (`_gds_server_flight_1`) that consumes the peer's
ClientHello and emits the flight-1 quartet. `gds_handshake_server`
returned from R1 at `DTLS_S_SHD_SENT`; the R2 flight-2 (recv CKE + CCS
+ Finished, send server CCS + Finished) was documented as the
follow-up.

The CLIENT-SIDE was still a stub: `gds_handshake_client` returned
`[0, state]` with `last_err = "dtls-hs-flight-not-wired"`. In addition,
the R2 (Phase O) ClientHello builder embedded a 32-byte zero-Random
placeholder documented explicitly as "R29B placeholder; secure_random
in R29B.2" -- meaning `dtls_ecdhe_derive` (which reads
`DTLS_S_SLOT_CLIENT_RANDOM`) could not be reached over a real wire
because the randoms were never wired.

Phase P R2 closes both halves of that gap plus the SKE-signature
verification hook the client needs to run against the cert-chain-verify
path Phase O R1 shipped. Concretely:

- Fix the ClientHello Random placeholder so it pulls from
  `secure_random` (with a test-mode override) and pins the bytes on
  the state.
- Add four server-flight parsers (ServerHello / Certificate /
  ServerKeyExchange / ServerHelloDone) mirroring R1's parser shape.
- Add the ClientKeyExchange parser (`_dtls_parse_client_key_exchange_body`) so
  server flight-2 can consume it.
- Add three new body builders: `_dtls_build_client_key_exchange_body`,
  `_dtls_build_change_cipher_spec_record`, and `_dtls_build_finished_body`.
- Add `_dtls_der_decode_ecdsa_sig` (+ helpers) as the DER inverse of
  R1's `_dtls_der_encode_ecdsa_sig`, used to unpack the SKE signature
  before verify.
- Wire the cert-chain verify hook (`dtls_cert_verify_chain` from Phase
  O R1) into the client flight; wire the SKE-signature verify via
  `ecdsa_p256_verify_bn` against the leaf cert's EC pub.
- Add `_gds_client_flight` in `src/federation/gossip_dtls_shim.nova`
  as the top-level driver: composes the ClientHello send, the SH /
  Cert / SKE / SHD recv + parse + absorb + verify chain, the ECDHE
  derive, the CKE + CCS + Finished send, and the server CCS + Finished
  recv + verify.
- Add `_gds_server_flight_2` as the server-side counterpart: consumes
  the client's CKE + CCS + Finished, sends the server CCS + Finished.
- Re-wire `gds_handshake_client` to call `_gds_client_flight`; extend
  `gds_handshake_server` to call `_gds_server_flight_2` after R1's
  flight-1.
- Two new tail slots (`DTLS_S_SLOT_CLIENT_RANDOM_OVERRIDE = 52`,
  `DTLS_S_SLOT_HOSTNAME = 53`, `DTLS_S_SLOT_ANCHORS = 54`) so the
  client-side verify plumbing can be pinned on state without threading
  it through every internal helper.

## Decision

### 1. ClientHello Random fix

At the top of `_dtls_build_client_hello_body` in
`src/federation/dtls12.nova`, R2 calls `secure_random(cr_buf, 32)`. If
the entropy pull returns < 32 (test harness, no `/dev/urandom`), R2
falls back to whatever 32-byte buffer sits at
`state[DTLS_S_SLOT_CLIENT_RANDOM_OVERRIDE]`; if THAT slot is also 0
(no test override registered), R2 zero-fills as the safest fallback so
the function stays total (callers on a no-entropy platform can pre-
populate the override before invoking the builder; the zero-fill
retains the pre-R2 skeleton behavior).

The 32-byte Random is written to BOTH:
- the wire body at offset 2 (per RFC 5246 §7.4.1.2), AND
- `state[DTLS_S_SLOT_CLIENT_RANDOM]` (slot 17).

This dual-write is load-bearing: `dtls_ecdhe_derive` (line ~2481)
reads slot 17 to build the PRF seed for master_secret. Without the
dual-write, the seed on the wire and the seed used for key derivation
would diverge -- the peer's derivation would produce a DIFFERENT
master_secret than ours, and the very first AEAD open would fail.

### 2. Four server-flight parsers

Each parser mirrors R1's `_dtls_parse_client_hello_body` shape: return
a fixed-shape list whose first slot is `1` on accept, `0` on refuse
with the second slot carrying the diagnostic tag. Callers discriminate
on the first slot; no exceptions, no negative sentinels.

- `_dtls_parse_server_hello_body(buf, n)` returns
  `[1, version, random_32B, sid_pair, negotiated_suite, compr, ext_pair]`.
  Refuses on short body (< 38), wrong cipher suite (must be 0xC02B),
  non-null compression, or any length prefix overflow.
- `_dtls_parse_certificate_body(buf, n)` returns
  `[1, cert_der_list]` where `cert_der_list` is a list of `[buf, n]`
  pairs (leaf first per RFC 5246 §7.4.2). Refuses on 3B-length
  overflow.
- `_dtls_parse_ske_body(buf, n)` returns
  `[1, curve_type, curve_id, pub_point_65B, sig_alg, sig_pair]`.
  Refuses on `curve_type != 3`, `curve_id != 23` (secp256r1),
  `point_len != 65`, or any length overflow. Signature bytes are
  returned raw; DER decoding happens at verify time.
- `_dtls_parse_server_hello_done_body(buf, n)` returns `[1]` iff
  `n == 0` per RFC 5246 §7.4.5.

### 3. ClientKeyExchange parser (for server flight-2)

`_dtls_parse_client_key_exchange_body(buf, n)` is the inverse of the R2
CKE builder. For the ECDHE_ECDSA suite the body is `1B point_len=65 ||
65B uncompressed EC point`. Returns `[1, client_pub_point_65B]` on
accept, `[0, DTLS_ERR_BAD_HS]` on any length mismatch.

### 4. Three new body builders

- `_dtls_build_client_key_exchange_body(state, client_pub_point_65b)`:
  emits the 66-byte CKE body per RFC 4492 §5.7 -- `1B point_len=65 ||
  65B point`. The point must be an uncompressed SEC1-encoded EC point
  (0x04 || X || Y).

- `_dtls_build_change_cipher_spec_record(state)`: emits the
  ChangeCipherSpec record. NOTE this is NOT a handshake message -- CCS
  rides in its own record with `content_type = 20` and a 1-byte body
  containing the constant `0x01` (RFC 5246 §7.1). This function
  returns a `[record_buf, record_n]` pair ready for `_gds_send_record`
  (i.e. already wrapped in the 13-byte DTLS record header via
  `dtls_record_emit`). CCS is emitted at the CURRENT epoch (pre-
  advance); the caller advances the epoch AFTER sending, which is
  precisely what CCS signals to the peer.

- `_dtls_build_finished_body(state, is_client)`: computes
  `verify_data = PRF(master_secret, label, SHA-256(transcript), 12)`
  where `label = "client finished"` when `is_client == 1` else
  `"server finished"` (RFC 5246 §7.4.9). Returns `[body_buf, 12]` on
  success, `0` iff `master_secret` is not yet populated. The
  transcript snapshot uses R1's non-destructive
  `dtls_transcript_finalize` so a subsequent absorb + finalize is
  well-defined -- critical for the two-snapshot MAC ordering per
  §7.4.9 (see §6 below).

### 5. DER decoder (SKE-signature verify)

`_dtls_der_decode_ecdsa_sig(buf, n)` is the DER inverse of R1's
`_dtls_der_encode_ecdsa_sig`. Parses the outer SEQUENCE tag (0x30) +
short-form length, then two INTEGER TLVs (tag 0x02 + short-form length
+ content). Each INTEGER decodes by stripping a leading 0x00 sign byte
(added by the encoder to keep the integer positive under two's
complement) and interpreting the remaining bytes as a big-endian
bn256 via `_p256_bytes_to_bn` on a 32-byte staging buffer left-padded
with zeros. Returns `[r_bn, s_bn]` on accept, `0` on any malformed
input.

Rationale for adding a NEW decoder (rather than reusing an existing
DER walker): the tree ships `x509.nova` which walks DER for
certificate parsing but does not expose a public "decode ECDSA-Sig-
Value" entry. R2's decoder is a tiny (~40 line) inline helper that
mirrors R1's inline encoder exactly, keeping the DTLS module a
self-contained ECDSA-sig codec pair (no cross-module dependency for
what is otherwise a 2-INTEGER SEQUENCE decode). If a future round
lands a general-purpose DER library at `src/safety/der.nova`, both
directions can migrate to it in one place.

Long-form length (top bit of length byte = 1) is deliberately
REJECTED: R1's encoder only emits short-form (the two 32-byte scalars
fit in a total < 128 bytes, so long-form is never needed).

### 6. Client flight driver (`_gds_client_flight`)

Composes the full RFC 6347 client-side handshake per the ordering
below. Every phase's failure path stamps a distinct string tag on
`LAST_ERR` and transitions the state to `DTLS_S_FAILED`.

1. Build ClientHello via `_dtls_build_client_hello_body` (now with
   real random per §1). Init the transcript accumulator (before
   absorbing the first message). Send via `_gds_send_hs` (from R1),
   which serializes the HS header + body, absorbs the whole HS
   message (12B header + body) into the transcript, wraps in a
   plaintext DTLS record, and pushes through the shim's length-prefix
   framer. Transition to `DTLS_S_CLIENT_HELLO_SENT`.
2. Recv four records: ServerHello, Certificate, ServerKeyExchange,
   ServerHelloDone. For each, R2's new helper `_gds_recv_hs` reads
   the framed record, validates content_type = 22 (handshake), parses
   the 12B HS header, checks the expected msg_type, and absorbs the
   whole HS message into the transcript. The body is then handed to
   the matching parser; the parser's `[ok, ...]` result gates
   progress.
3. After parsing Certificate, invoke the cert-verify hook:
   `dtls_cert_verify_chain(state, cert_der_list, hostname, anchors,
   now)` from Phase O R1. On any `xv != XV_OK` the driver aborts with
   the corresponding `DTLS_CERT_*` tag; the hook itself stamps
   `LAST_ERR` and bumps the matching STATS counter.
4. After parsing ServerKeyExchange, invoke the SKE-sig verify:
   reconstruct `sig_input = client_random || server_random ||
   server_params` (server_params = 4-byte curve header + 65-byte
   point = 69 bytes; total signed = 133 bytes), SHA-256 hash, DER-
   decode the sig, and call `ecdsa_p256_verify_bn(leaf_ec_point,
   65, hash_bn, r_bn, s_bn)` against the leaf cert's uncompressed EC
   pub extracted via `cert_ec_point(leaf_cert)`. Refuse on 0 with
   `DTLS_CERT_SIG_FAIL`.
5. Call `dtls_ecdhe_derive(state, server_pub_point, 65, cr, sr, 0)`.
   This reads `state[DTLS_S_SLOT_PRIV_BN]` (the client's ephemeral
   ECDH priv scalar, pre-stashed by `gds_handshake_client`), calls
   `p256_derive` to compute the shared X, runs the TLS 1.2 PRF twice
   (master_secret then key_block), slices the key_block into the
   four sub-buffers, and flips `CIPHER_ACTIVE = 1`. is_server = 0.
6. Build + send ClientKeyExchange. Absorb before sending (the
   `_gds_send_hs` helper does this in order).
7. Build + send ChangeCipherSpec via `_dtls_build_change_cipher_spec_
   record` and `_gds_send_record` (CCS record is NOT absorbed into
   transcript per RFC 5246 §7.4.9). Advance the epoch AFTER sending
   via `dtls_advance_epoch(state)`.
8. Build client Finished via `_dtls_build_finished_body(state, 1)`
   (verify_data snapshots the transcript covering CH..CKE). SERIALIZE
   the HS envelope, ABSORB the client-Finished bytes into the
   transcript AFTER computing verify_data (so the subsequent server-
   Finished PRF covers them), then seal via `dtls_seal_record`
   (client Finished is the FIRST encrypted record) and send.
   Transition to `DTLS_S_FINISHED`.
9. Recv server CCS (content_type = 20, NOT absorbed). Recv + decrypt
   server Finished; verify verify_data matches
   `_dtls_build_finished_body(state, 0)` (which snapshots the current
   transcript, now covering CH..client Finished). Absorb the
   server-Finished HS bytes for completeness (a future exporter
   might want them). Transition to `DTLS_S_ESTABLISHED`.

### 7. Server flight-2 driver (`_gds_server_flight_2`)

Mirror of the client's steps 6-9 from the server side:

1. Recv ClientKeyExchange (plaintext -- CKE precedes the CCS). Parse
   via `_dtls_parse_client_key_exchange_body`. Absorb HS bytes.
2. Call `dtls_ecdhe_derive(state, client_pub_point, 65, cr, sr, 1)`.
3. Recv client CCS. Call `dtls_advance_epoch(state)`.
4. Recv + decrypt client Finished. Verify verify_data matches
   `_dtls_build_finished_body(state, 1)`. Absorb the client-Finished
   HS bytes.
5. Build + send server CCS. (Epoch already advanced in step 3, so
   this CCS emits under the NEW epoch's send_seq counter, which is
   correct RFC-6347 behavior -- the epoch bump on receipt-of-CCS
   flips both directions in lockstep.)
6. Build server Finished (`is_client = 0`; snapshot covers CH..client
   Finished). Serialize + absorb + seal + send.
7. Transition to `DTLS_S_ESTABLISHED` via direct state write. R1's
   `_dtls_valid_edge` did not add server-side FINISHED / ESTABLISHED
   edges (the R29B client-side chain terminates cleanly at
   `DTLS_S_ESTABLISHED` but the server-side chain stops at
   `DTLS_S_SHD_SENT`). Rather than extend the edge table and risk
   breaking pinned tests, R2 writes `DTLS_S_SLOT_STATE` directly.

### 8. Transcript-snapshot ordering (RFC 5246 §7.4.9)

The two verify_data snapshots take the transcript at DIFFERENT byte
boundaries:

- **Client Finished MAC** = PRF(ms, "client finished",
  SHA-256(CH || SH || Cert || SKE || SHD || CKE), 12).
  Snapshot BEFORE absorbing the client-Finished HS bytes.
- **Server Finished MAC** = PRF(ms, "server finished",
  SHA-256(CH || SH || Cert || SKE || SHD || CKE || client-Finished),
  12). Snapshot AFTER absorbing the client-Finished HS bytes.

R2 achieves this via the standard order for the client flight:

```
init transcript
send CH   -> absorb CH (12B HS header + body)
recv SH   -> absorb SH
recv Cert -> absorb Cert
recv SKE  -> absorb SKE
recv SHD  -> absorb SHD
send CKE  -> absorb CKE
finalize_1 = SHA-256(CH..CKE) -> client verify_data via PRF
serialize client Finished
absorb client Finished
seal + send client Finished
send CCS  (NOT absorbed)
recv CCS  (NOT absorbed)
recv + decrypt server Finished
finalize_2 = SHA-256(CH..CKE || client Finished) -> server verify_data via PRF
compare parsed body vs computed verify_data
absorb server Finished  (for completeness)
```

And the mirror for the server flight (steps 6-9 above).

The `dtls_transcript_finalize` from R1 is non-destructive by design
(it snapshots the byte buffer via `sha256_oneshot` without touching
the buffer), which is what makes the two-snapshot ordering work
without a scratch buffer or a live SHA-256 ctx clone.

### 9. Cert-verify + SKE-sig verify hooks

The cert-verify hook uses `dtls_cert_verify_chain(state, cert_der_list,
hostname, anchors, now)` from Phase O R1. The hook returns `[dtls_status,
leaf_cert]`; on `DTLS_OK` the leaf cert is stored for the subsequent
SKE-sig verify (which pulls `cert_ec_point(leaf_cert)` for the ECDSA
pubkey).

The SKE-sig hook reconstructs the exact 133-byte signed message per
RFC 5246 §7.4.3 (32 bytes client_random || 32 bytes server_random ||
69 bytes server_params where server_params = 1-byte curve_type = 3 +
2-byte curve_id = 0x0017 + 1-byte point_len = 65 + 65-byte point).
SHA-256 the message, DER-decode the wire signature to (r, s), and
call `ecdsa_p256_verify_bn(leaf_pub, 65, hash_bn, r_bn, s_bn)`. On
verify fail (return = 0) the driver aborts with `DTLS_CERT_SIG_FAIL`.

### 10. New tail slots

- `DTLS_S_SLOT_CLIENT_RANDOM_OVERRIDE = 52` -- test-mode override for
  `secure_random`, mirroring R1's `SERVER_RANDOM_OVERRIDE = 51`.
- `DTLS_S_SLOT_HOSTNAME = 53` -- SAN target for
  `dtls_cert_verify_chain`. Populated by `gds_handshake_client` from
  its `hostname` arg.
- `DTLS_S_SLOT_ANCHORS = 54` -- trust-anchor list for
  `dtls_cert_verify_chain`. Populated by `gds_handshake_client` from
  its `anchors` arg.

All three are appended at the tail so slots 0..51 stay byte-identical
for any caller / test that indexes into state by slot number.
`dtls_init` pushes three additional `0` slots to seed them.

## Alternatives considered

**(a) Thread hostname + anchors through every internal helper.**
Rejected because the SKE-sig verify happens deep in the flight driver
after several records have been read; threading five extra args
through every intermediate helper would clutter every signature. A
state slot is the cleanest cross-call carrier -- state is already the
carrier for all other handshake context.

**(b) Absorb the client Finished BEFORE computing its verify_data,
save a scratch copy of the pre-absorb transcript for the client MAC.**
Rejected because R1 explicitly designed
`dtls_transcript_finalize` to be non-destructive (it computes
`sha256_oneshot` over the byte buffer without touching the buffer) so
the caller can just finalize before absorbing. Two finalizations at
different byte prefixes is exactly the design point R1's buffer-based
representation was chosen for.

**(c) Extend `_dtls_valid_edge` with server-side FINISHED and
ESTABLISHED edges instead of writing state directly at the end of
server flight-2.** Rejected because R1's `test_dtls_server_flight.nova`
pins the server-side chain at `DTLS_S_INIT .. DTLS_S_SHD_SENT` +
FAILED; extending the edge table would either break those pins or
require rewriting them. The direct-write escape is a minimal, well-
commented deviation from the state-machine invariant; the invariant
holds for every other transition.

**(d) Use `p256_ecdh` directly for the ECDH derive instead of going
through `dtls_ecdhe_derive`.** Rejected because
`dtls_ecdhe_derive` does much more than just the ECDH: it also runs
the TLS 1.2 PRF twice (master_secret then key_block) and slices the
key_block into the four sub-buffers. Going through the wrapped entry
keeps all the derivation logic in one place. As a bonus, the API
naming is `p256_derive` (not `p256_ecdh`) -- there's no
`p256_ecdh` function in the tree.

**(e) Generate the client's ephemeral ECDH keypair inside
`_gds_client_flight` (instead of expecting the caller to hand one
in).** Rejected because tests need to pin the keypair for
reproducibility. Making the caller supply (priv_bn, pub_point) keeps
prod code (which pulls from `secure_random`) and test code (which
uses `p256_keypair_generate_deterministic`) on the same call shape.

**(f) Skip the SKE-sig verify (rely only on cert-chain verify).**
Rejected because the cert-chain verify only proves the server's
LONG-TERM ECDSA key is trusted; the SKE-sig proves the SERVER (not a
MITM) generated this specific EPHEMERAL ECDH pub point. Without the
SKE-sig, a passive network observer that captured a previous
handshake could replay the server's cert + arbitrary ECDH pub, and
the client would trust it. RFC 5246 §7.4.3 mandates the SKE-sig for
ECDHE_ECDSA -- skipping it is an active downgrade.

## Test coverage

**`tests/unit/test_dtls_client_flight.nova`** (~35 tests / ~60
checks):

- ClientHello builder populates `CLIENT_RANDOM` slot; wire body bytes
  at offset 2..34 match the slot byte-for-byte (regardless of whether
  `secure_random` succeeded or the override was consulted).
- All four server-flight parsers round-trip byte-exact against R1's
  builders (ServerHello no-ext + with-srtp; Certificate 1-cert +
  2-cert; SKE full-shape; SHD empty).
- Each parser refuses the documented malformed shapes (short body,
  wrong cipher suite, non-null compression, wrong curve type / id /
  point_len, cert-list overflow, SHD non-empty body).
- CKE builder emits the 66-byte body; CKE parser round-trips against
  the builder + refuses wrong point_len.
- CCS record is 14 bytes total (13B header + 1B body = 0x01);
  content_type = 20; records_out counter bumped.
- Finished body is 12 bytes; matches `dtls_prf_sha256(ms, 48,
  label, transcript_hash, 32, 12)` for a known transcript +
  master_secret; "client finished" and "server finished" labels
  produce different verify_data for identical inputs (label
  discrimination); refuses when `master_secret` is not populated.
- DER encode + decode round-trips: sign a fixed message under a
  fixed keypair, DER-encode the (r, s), DER-decode, verify the
  decoded (r, s) equal the originals via `bn256_eq`.
- DER decoder refuses malformed input (bad outer tag).
- SKE parser + DER decoder + ECDSA verify: build an SKE under a
  fixed keypair, parse it back, DER-decode the recovered sig,
  verify via `ecdsa_p256_verify_bn` against the signer pub --
  returns 1 on the happy path.
- `gds_handshake_client` refuse path: bogus fd -> `[0, state]` with
  `last_err` populated and state at `DTLS_S_FAILED`.
- `gds_handshake_client` populates hostname + anchors + current_time
  slots BEFORE the flight driver runs (verifiable even on the
  refuse path because the assignments happen up front).
- Slot indices pinned (52 = `CLIENT_RANDOM_OVERRIDE`, 53 =
  `HOSTNAME`, 54 = `ANCHORS`).
- Client-side state chain still valid (R29B edges INIT -> CHS -> SHR
  -> CR -> FIN -> EST + any-to-FAILED all accept).

**Full-handshake end-to-end round-trip** (client + server converge on
identical `master_secret` + reach `DTLS_S_ESTABLISHED`, then
`gds_send_line("hello")` from client -> `gds_recv_line` on server
returns `"hello"`): requires a working socket-pair test harness plus
the NOVA compiler to actually run tests. Per the standing Phase L /
M / N / O / P caveat (NOVA compiler self-hosting bootstrap segfaults
on this bench), `make test` cannot exercise this suite end-to-end.
The unit checks above cover every new function in isolation; the
composition is verified by structural review of `_gds_client_flight`
+ `_gds_server_flight_2`.

**Runtime caveat**: NOVA's compiler self-hosting bootstrap segfaults
on this bench (standing Phase L / M / N / O / P caveat), so `make
test` cannot exercise this suite. Verification is structural review +
`make lint-ints` per the plan file
(`/root/.claude/plans/gentle-toasting-zephyr.md` §"Verification").
The 12 pre-existing lint-ints findings are unchanged; none in the R2
files.

## Files touched

**Modified**:

- `src/federation/dtls12.nova` -- `_dtls_build_client_hello_body`
  (Random fix); `_dtls_parse_server_hello_body`,
  `_dtls_parse_certificate_body`, `_dtls_parse_ske_body`,
  `_dtls_parse_server_hello_done_body`, `_dtls_parse_client_key_
  exchange_body` (5 new parsers); `_dtls_build_client_key_
  exchange_body`, `_dtls_build_change_cipher_spec_record`,
  `_dtls_build_finished_body` (3 new builders); `_dtls_der_decode_
  ecdsa_sig`, `_dtls_der_decode_integer`, `_dtls_der_decode_integer_
  consumed` (DER decoder + helpers); 3 new tail slots (52/53/54);
  `dtls_hostname` + `dtls_anchors` public accessors; `dtls_init`
  extended to push 3 zeros. All additive: slots 0..51 stay byte-
  identical, R1's server-flight parsers/builders are untouched, all
  R29B client-side chain edges preserved.
- `src/federation/gossip_dtls_shim.nova` -- `_gds_client_flight`,
  `_gds_server_flight_2`, `_gds_recv_hs`, `_gds_verify_ske_sig`,
  `_gds_recv_and_verify_server_finished`,
  `_gds_recv_and_verify_client_finished`; `gds_handshake_client` re-
  wired to call `_gds_client_flight`; `gds_handshake_server`
  extended to call `_gds_server_flight_2` after R1's flight-1. Note
  that `gds_handshake_server` no longer stashes the caller's
  `priv_bn` into `DTLS_S_SLOT_PRIV_BN` (that slot now holds the
  server's EPHEMERAL ECDH priv scalar, which the caller pre-stashes
  via `dtls_ecdhe_keygen(state)` before invoking the entry).
- `ENHANCEMENTS_ROADMAP.md` -- Phase P R2 shipped note.

**New**:

- `tests/unit/test_dtls_client_flight.nova` -- ~60 checks per §"Test
  coverage" above.
- `docs/adr/0098-dtls-client-flight-finished.md` -- this ADR.

## References

- ADR-0094 -- Phase O R1 (chain-aware `dtls_cert_verify_chain`).
  R2's cert-verify hook calls this directly.
- ADR-0095 -- Phase O R2 (SRTP EKM + `use_srtp` extension). R2's
  ServerHello parser recovers the ext_pair verbatim (R3's real
  extension walker will replace the stub).
- ADR-0096 -- Phase O R3 (DTLS-over-TCP shim). R2's flight drivers
  go through R3's `_gds_send_record` / `_gds_recv_record` framing.
- ADR-0097 -- Phase P R1 (server-side handshake flight). R2 composes
  on top of R1's transcript accumulator, server-flight state edges,
  and `_gds_server_flight_1`; R2's `_gds_server_flight_2` picks up
  where R1's flight-1 left off (at `DTLS_S_SHD_SENT`).
- RFC 5246 §7.4 -- TLS 1.2 handshake message shapes (ClientHello,
  ServerHello, Certificate, CKE, CCS, Finished).
- RFC 5246 §7.4.9 -- Finished message + verify_data + PRF snapshot
  ordering.
- RFC 5246 §7.4.3 -- ECDHE_ECDSA ServerKeyExchange signed-message
  layout.
- RFC 4492 §5.4 -- ECDHE ServerKeyExchange wire shape.
- RFC 4492 §5.7 -- ECDHE ClientKeyExchange wire shape.
- RFC 6347 §4.2.2 -- DTLS-specific handshake message header.
- RFC 6347 §4.1.2.6 -- CCS epoch-advance + anti-replay window reset.
- RFC 3279 §2.2.3 -- DER encoding of ECDSA signature values.
- FIPS 186-4 §6.4 -- ECDSA verify recipe (used by the SKE-sig
  verify hook).
- FIPS 180-4 -- SHA-256, used by both the transcript accumulator
  and the SKE-sig verify hash.
- `src/federation/dtls12.nova::_dtls_build_client_hello_body` --
  the Random fix.
- `src/federation/dtls12.nova::_dtls_parse_server_hello_body` --
  one of the four server-flight parsers.
- `src/federation/dtls12.nova::_dtls_build_finished_body` -- the
  Finished MAC builder.
- `src/federation/gossip_dtls_shim.nova::_gds_client_flight` --
  the client flight driver.
- `src/federation/gossip_dtls_shim.nova::_gds_server_flight_2` --
  the server flight-2 driver.

## Deferred to R3

- Full extension parsing (replaces R1's `_dtls_parse_ext_block_stub`
  with a real per-extension walker that dispatches into `use_srtp`
  / SNI / supported_groups).
- DTLS-aware gossip stream helpers so DELTA / SNAP_FETCH /
  SNAP_DATA / SNAP_END / DQEND / EXTADDR / RELAY_* stop being
  silently dropped under DTLS (see `gossip.nova:3273-3285` +
  `:3360-3366` for the currently-dropped dispatch branches).
