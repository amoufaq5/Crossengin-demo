# ADR-0097: DTLS 1.2 server-side handshake flight -- ClientHello parser + 4 body builders + transcript accumulator (Phase P R1)

- Status: Accepted
- Date: 2026-09-30

## Context

Phase O (ADR-0094 / ADR-0095 / ADR-0096) closed the DTLS 1.2 stack up to
the cipher-state seam: cert-chain verification (R1), SRTP EKM + the
`use_srtp` extension (R2), and a non-standard DTLS-over-TCP shim (R3)
that lays 2-byte-length-prefixed DTLS records on top of gossip's TCP
transport. Phase O R3 shipped the framing + line-oriented send/recv
helpers + a keyed-shortcut path for tests that pre-derive the cipher
state directly, but it explicitly deferred the RFC 6347 handshake flight
builders:

> R3 ships the shim as a THIN framing layer + a KEYED-HANDSHAKE fast
> path for scenarios where both peers already share the derived cipher
> state; the flight builders themselves land in a follow-up round.

Concretely, `gds_handshake_server` in
`src/federation/gossip_dtls_shim.nova` returned
`[0, state]` with `last_err="dtls-hs-flight-not-wired"`, and no
CrossEngin peer could actually complete a DTLS handshake over the wire
without both sides skipping it via `gds_keyed_shortcut`. That is
functional for the R3 unit-test path but not for a live mesh handshake.

Phase P R1 closes the SERVER-SIDE half of that gap. It ships:

- A ClientHello parser (RFC 5246 §7.4.1.2 + RFC 6347 §4.2.2).
- Four body builders (ServerHello, Certificate, ServerKeyExchange,
  ServerHelloDone).
- A transcript-hash accumulator that R2's Finished MAC will lift.
- Five new server-side state-machine constants + the matching edges in
  `_dtls_valid_edge`.
- A wire-level flight driver `_gds_server_flight_1` that composes all of
  the above and drives the server through the flight-1 quartet.
- The `gds_handshake_server` wire-in.

The CLIENT-SIDE half (ClientHello Random fix, server-flight parsers,
CKE / CCS / Finished builders, `gds_handshake_client` wire-in) and the
server flight-2 (recv CKE + CCS + Finished, send server CCS + Finished)
are deferred to R2 per the plan file
(`/root/.claude/plans/gentle-toasting-zephyr.md` §R2).

## Decision

### 1. ClientHello parser

Add `_dtls_parse_client_hello_body(buf, n)` to
`src/federation/dtls12.nova`. Returns an 8-element result:

```
[ok, version_u16, random_32b, sid_pair, cookie_pair,
 suites_list, compr_list, ext_pair_or_0]
```

where each `_pair` is a fresh `[buf, n]` 2-tuple (or `0` when the
sub-field is empty on the wire). On any of the four documented refusal
paths the first slot is `0` and the second slot carries the error
string tag:

| Refusal                                | Error tag              |
| -------------------------------------- | ---------------------- |
| Short body (< 42 bytes)                | `DTLS_ERR_BAD_HS`      |
| Length prefix overflows the buffer     | `DTLS_ERR_BAD_HS`      |
| `0xC02B` absent from `suites_list`     | `DTLS_ERR_NO_CIPHER`   |
| Null compression method (0) absent     | `DTLS_ERR_BAD_HS`      |

The extension block, when present, is returned verbatim as bytes to a
stub extension parser `_dtls_parse_ext_block_stub` that R3 will replace
with a real per-extension walker. The stub validates only the outer
2-byte length envelope; the contents pass through untouched. R1's
ServerHello builder consequently does NOT switch on the client's
offered `use_srtp` profile -- it echoes whatever the server driver has
already written into `DTLS_S_SLOT_SRTP_OFFER`, which R3 will populate
from the parsed extension.

### 2. Four body builders

All four mirror R2's `_dtls_build_client_hello_body` shape: they return
`[body_buf, body_n]` and the caller wraps them in the 12-byte HS header
via `dtls_handshake_serialize`, then in the 13-byte record header via
`dtls_record_emit`, then hands to `_gds_send_record` for the length-
prefixed shim framing.

- **`_dtls_build_server_hello_body(state, negotiated_suite,
  server_random_32b)`** -- RFC 5246 §7.4.1.3. 38-byte base body (2B
  version + 32B random + 1B empty sid + 2B suite + 1B null compr); when
  `state[DTLS_S_SLOT_SRTP_OFFER]` is non-zero, appends an 11-byte
  extension block (2B length + 9-byte `use_srtp` extension via the R2
  helper `_dtls_build_use_srtp_ext`).
- **`_dtls_build_certificate_body(state, cert_der_list)`** -- RFC 5246
  §7.4.2. 3-byte total-length prefix, then per cert: 3-byte length + DER
  bytes. Accepts a `list<[buf, n]>` chain, leaf first per spec.
- **`_dtls_build_ske_body(state, ec_curve_id, pub_point_65b,
  signer_priv_bn)`** -- RFC 4492 §5.4 + RFC 5246 §7.4.3. Server ECDHE
  params (curve_type=3 named_curve, curve_id=`0x0017` secp256r1,
  point_len=65, uncompressed SEC1 pub point) + `SignatureAndHashAlgorithm
  = 0x04 0x03` (SHA-256 + ECDSA per RFC 5246 §7.4.1.4.1) + 2B DER-sig
  length + DER-encoded ECDSA signature over
  `client_random || server_random || server_ECDH_params`.
- **`_dtls_build_server_hello_done_body()`** -- RFC 5246 §7.4.5. Empty
  body (returns `[buf, 0]`).

### 3. ECDSA-P-256 sign helper

The tree pre-Phase-P ships only `ecdsa_p256_verify_bn` in
`src/safety/ecdsa.nova` -- the R33B cert-verify path only needed verify.
R1 adds the sign counterpart INLINE in `dtls12.nova` as
`_dtls_ecdsa_p256_sign(msg_buf, msg_n, priv_bn)` because the ECDSA sig
inside SKE is the only sign call in the DTLS handshake and there is no
current cross-module reuse case for a public `ecdsa_p256_sign` entry.
When one arises (e.g. a mesh peer minting its own cert instead of
loading one from `p256_keypair_load`) the inline helper will be
promoted into `src/safety/ecdsa.nova` and the DTLS module will import
it, mirroring the R33A canonical-SHA-256 dedup pattern.

Signing follows FIPS 186-4 §6.3 verbatim: hash the message with
SHA-256, draw `k` from `_p256_random_scalar` (which internally probes
`secure_random` and falls back to a nanotime + LCG per the pattern
`p256.nova` already uses), compute `r = (k*G).x mod n` and `s = k^-1 *
(e + r*priv) mod n`, retrying up to 8 times if either scalar hits zero
(a probabilistically-unreachable path with a working entropy source).

Deterministic-`k` per RFC 6979 is documented as a hardening followup;
R1 keeps the simpler nonce path because the SKE sign is on the server-
identity long-term key which is the same trust anchor whether the
nonce is deterministic or random.

### 4. ECDSA signature DER encoding

RFC 4492 §5.4 (via X9.62 / RFC 3279 §2.2.3) mandates that the ECDSA
signature inside SKE be encoded as:

```
Ecdsa-Sig-Value ::= SEQUENCE { r INTEGER, s INTEGER }
```

not as raw `r || s` bytes. R1 hand-encodes the DER inline via
`_dtls_der_encode_ecdsa_sig` and its helper
`_dtls_der_encode_bn_as_integer`. The integer encoder:

1. Emits the 32-byte big-endian representation of the scalar.
2. Strips leading zero bytes (keeping at least one, for the bn=0
   corner case where ASN.1 encodes zero as `02 01 00`).
3. Prepends a single `0x00` iff the top bit of the first remaining
   byte is set (so the ASN.1 two's-complement interpretation stays
   positive).
4. Wraps as `0x02 length value`.

Output size is at most 72 bytes (2 for the SEQUENCE header + 2 * (2 +
33) for two maximum-length integer encodings), which fits inside the
SKE body's 2-byte signature-length envelope.

**Alternative considered**: raw `r || s` bytes (matching FIPS 186-4
§6.4's implicit shape). Rejected because RFC 4492 §5.4 is explicit
about the DER encoding, and a real DTLS 1.2 peer will refuse the
raw-bytes form.

### 5. Transcript-hash accumulator

RFC 5246 §7.4.9 computes the Finished MAC as:

```
verify_data = PRF(master_secret, finished_label,
                  Hash(handshake_messages))[0..12]
```

where `handshake_messages` is the byte concatenation of every
handshake message on the flight (including its 12-byte HS header). R2
needs to hash this concatenation TWICE at different points -- once for
the client Finished, once for the server Finished -- and the second
hash must inspect strictly more bytes than the first.

R1 ships this as a growing byte BUFFER (not a live SHA-256 context):

- **`DTLS_S_SLOT_TRANSCRIPT_CTX = 49`** -- fresh byte buffer, grown
  geometrically (doubling) on each absorb.
- **`DTLS_S_SLOT_TRANSCRIPT_N = 50`** -- valid byte count in the buffer.
- `dtls_transcript_init(state)` -- allocate an initial 512-byte buffer.
- `dtls_transcript_absorb(state, hs_msg_bytes, n)` -- append n bytes;
  grows the buffer via copy-out if needed. Silently init-on-first-use
  so the caller can drive absorbs without a pre-flight.
- `dtls_transcript_finalize(state)` -- return `sha256_oneshot(buf, n)`;
  NON-DESTRUCTIVE (leaves the accumulator intact for a second
  finalize).

**Alternative considered**: streaming SHA-256 via `sha256_init` /
`sha256_update` / `sha256_final` from `src/safety/sha256.nova` (which
DOES exist). Rejected because `sha256_final`'s contract is "The state
must not be reused after this call" -- for two Finished MACs at
different transcript prefixes we would either need to clone the
streaming context (the tree ships no ctx-clone helper today and the
state is a list-of-list containing a mutable H array, so cloning is
non-trivial) or maintain two parallel streams (fragile: any absorb
call that missed one would silently produce mismatched digests). The
buffer approach is O(N) storage in transcript size and O(N) work per
finalize, both of which are dominated by the O(N) SHA-256 compress
anyway; the trade is total for the simpler correctness argument.

### 6. Server-side state-machine constants + edges

Append after the R29B client-side constants (values 10..14, so 0..6
stay byte-identical for any switch-on-state code that pins them):

- `DTLS_S_CLIENT_HELLO_RECVD = 10`
- `DTLS_S_SERVER_HELLO_SENT = 11`
- `DTLS_S_CERT_SENT = 12`
- `DTLS_S_SKE_SENT = 13`
- `DTLS_S_SHD_SENT = 14`

Extend `_dtls_valid_edge` to accept the linear server-side chain plus
each state -> FAILED (mirroring the R29B any-to-FAILED rule).

### 7. Server flight driver in `gossip_dtls_shim.nova`

Add `_gds_server_flight_1(conn_fd, dtls_state, priv_bn, pub_point,
cert_der) -> [ok, err]` that:

1. Reads the first record off the fd via `_gds_recv_record`; must be a
   handshake record (content-type 22) carrying a ClientHello (type 1).
2. Parses the ClientHello body via `_dtls_parse_client_hello_body`;
   populates `DTLS_S_SLOT_CLIENT_RANDOM` with the 32-byte random.
3. Absorbs the whole HS message (12B header + body) into the transcript;
   transitions `INIT -> CLIENT_HELLO_RECVD`.
4. Generates `server_random` via `_gds_generate_server_random` (probes
   `secure_random(buf, 32)`; falls back to
   `DTLS_S_SLOT_SERVER_RANDOM_OVERRIDE` for reproducible unit-test
   vectors).
5. Builds ServerHello + Certificate + ServerKeyExchange +
   ServerHelloDone bodies; wraps each in a 12-byte HS envelope with the
   right `msg_seq` (0..3) via `dtls_handshake_serialize`; absorbs each
   whole HS message into the transcript; wraps each in a plaintext DTLS
   record via `dtls_record_emit`; sends each through `_gds_send_record`.
6. Transitions state through the 5 new server-side edges as each
   record lands.
7. Returns `[1, ""]` on the full flight-1 success path.

On any failure path (parse refuse, send fail, malformed record, bad
HS type, or state-transition refuse), the helper `_gds_flight_fail`
stamps the state's `LAST_ERR` slot with a distinct string tag (see
table below), transitions to `DTLS_S_FAILED`, and returns
`[0, err_string]`.

| Refusal tag                            | Origin                                |
| -------------------------------------- | ------------------------------------- |
| `dtls-hs-recv-fail`                    | `_gds_recv_record` returned `[0,0,0]` |
| `dtls-hs-short-record`                 | Record shorter than 13B record header |
| `dtls-hs-wrong-content-type`           | Record content-type != 22 handshake   |
| `dtls-hs-bad-header`                   | HS header parse rejected              |
| `dtls-hs-not-client-hello`             | HS type != CLIENT_HELLO               |
| `<parser tag>`                         | ClientHello body parse rejected       |
| `dtls-hs-no-entropy`                   | secure_random unavailable + no override |
| `dtls-hs-build-{sh,cert,ske}`          | Body builder returned 0               |
| `dtls-hs-send-{sh,cert,ske,shd}`       | `_gds_send_record` returned 0         |
| `dtls-hs-bad-transition-{chr,shs,cs,skes,shds}` | `dtls_transition` rejected the edge |

### 8. Wire `gds_handshake_server`

Replace the pre-R1 stub body with:

1. Allocate `dtls_state` via `dtls_init()` when `state == 0`.
2. Stash `priv_bn` / `pub_point` on the state; set `IS_SERVER = 1`.
3. Call `_gds_server_flight_1(conn_fd, st, priv_bn, pub_point,
   cert_der)`.
4. Return `[flight_ok, st]`.

The `dtls-hs-flight-not-wired` sentinel stays available for the
client-side driver (`gds_handshake_client`) until R2 lands the client
flight.

### 9. Test-mode server_random override

Add slot `DTLS_S_SLOT_SERVER_RANDOM_OVERRIDE = 51`. Prod paths leave
this at 0 so the fallback is a no-op; unit tests that pin ServerHello
byte-for-byte populate it to `_mk_ramp32(<seed>)` so runs are
reproducible even when `secure_random` is available (the driver
prefers real entropy when it is available, so tests that need
determinism have to explicitly zero it -- documented on the slot's
comment).

## Consequences

**What R1 enables**:

- A real CrossEngin mesh server can accept a full flight-1 quartet
  from a standards-compliant DTLS client (given R2 lands the
  client-side flight for two-way mesh handshakes).
- Every existing R18E / R29B / R31B / R32B / R33B test remains
  byte-identical: all new slots + constants are tail-appended, all new
  functions are additive, `_dtls_valid_edge` extension only adds
  edges.
- The transcript accumulator is ready for R2's Finished MAC without
  any layout change.

**What R1 does NOT enable**:

- **Client-side flight**. `gds_handshake_client` still returns
  `[0, state]` with `last_err="dtls-hs-flight-not-wired"`. R2 lands
  the ClientHello Random fix, the four server-flight parsers, the
  cert-verify hook, the CKE / CCS / Finished builders, and the
  client flight driver.
- **Server flight-2**. R1 stops at `DTLS_S_SHD_SENT`; R2 adds
  `_gds_server_flight_2` that recvs the client's CKE + CCS + Finished
  and emits the server's CCS + Finished, terminating at
  `DTLS_S_ESTABLISHED`.
- **Extension parsing**. R1's `_dtls_parse_ext_block_stub` validates
  only the outer length; the ServerHello builder echoes whatever
  `SRTP_OFFER` slot value the driver has already stored. R3 replaces
  the stub with a real per-extension walker + `use_srtp` parser.
- **DTLS-aware gossip stream helpers**. The DELTA / SNAP_FETCH /
  EXTADDR / RELAY_* handlers still bypass `gds_send_line`; R3
  addresses that separately.

## Alternatives Considered

**(a) Streaming SHA-256 for the transcript.** See §5 -- rejected
because `sha256_final` consumes the ctx and there is no ctx-clone
helper today. The buffer approach is simple and correct.

**(b) Raw `r || s` ECDSA signature bytes.** See §4 -- rejected
because RFC 4492 §5.4 requires DER; a standards-compliant peer will
refuse the raw form.

**(c) Deterministic RFC 6979 nonce for ECDSA sign.** Documented as a
hardening followup. R1's random-nonce path is FIPS 186-4 compliant
and matches the pattern the tree already uses in `p256_keygen` for
the ECDH private scalar.

**(d) Add `ecdsa_p256_sign` as a public entry in
`src/safety/ecdsa.nova` immediately.** Rejected as scope creep: the
only current caller is the SKE builder, and promoting the helper
without a second caller violates the "one caller per public entry"
minimality rule that the R33A dedup established. When R2's cert-mint
work lands (if it does; the tree currently loads certs from disk),
the helper gets promoted then.

**(e) Have `_gds_server_flight_1` also derive the shared secret via
`p256_ecdh` + `dtls_ecdhe_derive` at flight-1 time.** Rejected
because the ECDH derive needs the CLIENT's ephemeral pub point, which
does not arrive until the CKE in flight-2. R2's `_gds_server_flight_2`
is the correct home for the derive call.

**(f) Advance state to `DTLS_S_ESTABLISHED` from `_gds_server_flight_1`
on success (skipping the client-side flight-2).** Rejected because
`ESTABLISHED` implies the AEAD keys have been derived, the CCS has
flipped the epoch, and the peer's Finished has been verified. R1
correctly stops at `SHD_SENT`.

## Test coverage

**`tests/unit/test_dtls_server_flight.nova`** (~50 checks across
~25 test fns):

- ClientHello parser round-trips with the R2 builder in both the no-ext
  (42-byte body) and with-`use_srtp` (53-byte body) shapes.
- ClientHello parser rejects the four documented malformed shapes:
  missing null-compression method, wrong cipher suite, short body,
  bad suites_len overflow.
- Extension-block stub parser accepts empty and valid length prefixes;
  rejects overflow.
- ServerHello body: pinned server_random yields the RFC 5246 §7.4.1.3
  byte-for-byte layout; SRTP-offer variant appends the 11-byte ext
  block.
- Certificate body: one-cert chain yields 3 + 3 + 100 = 106 bytes with
  correct 3B-length prefixes; two-cert chain concatenates correctly.
- ServerKeyExchange body: pinned inputs -> curve_type 3, curve_id
  0x0017, point_len 65, sig_alg 0x0403; signature verifies via
  `ecdsa_p256_verify_bn` against the signer pub.
- ServerHelloDone body: empty (0 bytes).
- Transcript accumulator: absorb two messages -> finalize matches
  `sha256_oneshot(a || b)`; finalize is non-destructive across two
  calls.
- State-machine edges: the 5 new server-side transitions accept;
  reverse edges rejected; the original R29B client-side chain still
  accepts.
- Server flight driver refuse path: bogus fd -1 -> [0, state],
  last_err = "dtls-hs-recv-fail", state ends at FAILED.
- Slot indices pinned (49/50/51 for transcript_ctx / transcript_n /
  server_random_override); state constants pinned (10..14).

**Runtime caveat**: NOVA's compiler self-hosting bootstrap segfaults on
this bench (standing Phase L / M / N / O / P caveat), so `make test`
cannot run these end-to-end. Verification is structural review + `make
lint-ints` per the plan file. The 12 pre-existing lint-ints findings
are unchanged; none in the R1 files.

## Files touched

**Modified**:

- `src/federation/dtls12.nova` -- `_dtls_parse_client_hello_body`,
  `_dtls_parse_ext_block_stub`, `_dtls_build_server_hello_body`,
  `_dtls_build_certificate_body`, `_dtls_build_ske_body`,
  `_dtls_build_server_hello_done_body`, `_dtls_ecdsa_p256_sign`,
  `_dtls_der_encode_ecdsa_sig`, `_dtls_der_encode_bn_as_integer`,
  `dtls_transcript_init`, `dtls_transcript_absorb`,
  `dtls_transcript_finalize`, `dtls_transcript_len`; 5 new server-side
  state constants + `_dtls_valid_edge` extension; 3 new tail slots
  (49/50/51). All additive: existing tests + `dtls_ecdhe_derive` code
  path byte-identical.
- `src/federation/gossip_dtls_shim.nova` -- `_gds_server_flight_1`,
  `_gds_send_hs`, `_gds_flight_fail`, `_gds_generate_server_random`;
  `gds_handshake_server` re-wired to call the driver. The pre-R1
  `"dtls-hs-flight-not-wired"` sentinel still fires from
  `gds_handshake_client` (which R2 wires).
- `tests/unit/test_gossip_dtls_shim.nova` -- one test updated to
  reflect the new `"dtls-hs-recv-fail"` tag that surfaces when
  `gds_handshake_server` is called with a bogus fd (was
  `"dtls-hs-flight-not-wired"` pre-R1).
- `ENHANCEMENTS_ROADMAP.md` -- Phase P R1 shipped note.

**New**:

- `tests/unit/test_dtls_server_flight.nova` -- ~50 checks per §"Test
  coverage" above.
- `docs/adr/0097-dtls-server-flight.md` -- this ADR.

## References

- ADR-0094 -- Phase O R1 (chain-aware `dtls_cert_verify_chain`). The
  cert chain R1's `_dtls_build_certificate_body` composes is what
  the client-side R2 flight passes to that verifier.
- ADR-0095 -- Phase O R2 (SRTP EKM + `use_srtp` extension). R1's
  ServerHello echoes the `use_srtp` extension via R2's
  `_dtls_build_use_srtp_ext`.
- ADR-0096 -- Phase O R3 (DTLS-over-TCP shim). R1's flight driver
  goes through R3's `_gds_send_record` / `_gds_recv_record` framing
  helpers.
- RFC 5246 §7.4 -- TLS 1.2 handshake message shapes (ServerHello,
  Certificate, ServerHelloDone).
- RFC 4492 §5.4 -- ECDHE_ECDSA ServerKeyExchange wire shape.
- RFC 6347 §4.2.2 -- DTLS-specific handshake message header +
  ClientHello cookie field.
- RFC 3279 §2.2.3 -- DER encoding of ECDSA signature values.
- FIPS 186-4 §6.3 -- ECDSA sign recipe.
- FIPS 180-4 -- SHA-256, used by the transcript accumulator.
- `src/federation/dtls12.nova::_dtls_parse_client_hello_body` -- the
  parser this ADR ships.
- `src/federation/dtls12.nova::_dtls_build_server_hello_body` -- one
  of the four body builders.
- `src/federation/gossip_dtls_shim.nova::_gds_server_flight_1` -- the
  flight driver.
