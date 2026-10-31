# ADR-0095: DTLS-SRTP EKM stub-forward + `use_srtp` ClientHello extension (Phase O R2)

- Status: Accepted
- Date: 2026-09-30

## Context

Phase O R2 closes the second of three arcs that finish CrossEngin's
DTLS 1.2 story. R1 (ADR-0094) wired chain-aware cert verification;
this ADR-0095 wires SRTP-DTLS interop. R3 (ADR-0096, still queued)
will wrap gossip's TCP transport in DTLS records via a non-RFC-standard
TCP shim.

**Header-comment diagnosis.** The header at `src/federation/dtls12.nova`
line 161 read:

```
dtls_extract_srtp_keys_R29B2_STUB -- still a stub; needs RFC 5705 EKM.
```

That comment was stale by two rounds. R35A landed the RFC 5764 §4.2
exporter `dtls_export_srtp_keying_material` at :2460 (60 bytes,
`"EXTRACTOR-dtls_srtp"` label, seed = `client_random || server_random`,
48-byte master_secret input, PRF-SHA256 expansion). R36B extended it
with the `DTLS_S_SLOT_SRTP_KM_CACHED` memoization slot + a cache-hits
counter + `dtls_advance_epoch` invalidation. Both shipped complete;
the tree already carried more than the header claimed was missing.

**What was actually missing** was three items, none of which required
new cryptographic code:

1. **The stub wrapper still returned `DTLS_ERR_STUB`.** The legacy
   entry `dtls_extract_srtp_keys_R29B2_STUB` at :2406 had never been
   rewired to the real exporter. Any consumer that only knew the
   `_R29B2_STUB` name (documented in the header + tested in
   `test_stubs_return_DTLS_ERR_STUB`) got the sentinel instead of the
   real 60-byte block. The other three R29B.2 stubs
   (`_ecdhe_derive_R29B2_STUB`, `_seal_record_R29B2_STUB`,
   `_open_record_R29B2_STUB`) were similarly named + retained as
   regression guards; only the SRTP one was documented as still
   uncompleted, and this ADR closes that gap.
2. **No public random-accessors.** `dtls_master_secret(state)` at
   :1402 exposes slot 19. Slots 17 (client_random) and 18
   (server_random) had NO public accessor -- callers had to index
   into the state list by raw slot number, which is both an
   encapsulation break AND a lurking bug (a future slot renumber
   would silently return the wrong 32 bytes). R33B skipped these
   two entries when it landed the master_secret accessor; ADR-0095
   lifts the omission.
3. **`use_srtp` ClientHello extension not emitted.** The ClientHello
   body builder at :1046 (now :1147 after R2's rewrite) had the
   comment "no extensions" and produced exactly 42 bytes. RFC 5764
   §4.1 requires SRTP negotiation via a `use_srtp` extension in the
   `Extension extensions<0..2^16-1>` field of ClientHello; without
   it a real SRTP-DTLS peer has no way to know we can speak the
   profile. R2 lands the minimal emission path (one profile per
   ClientHello, empty MKI); parsing the peer's echo is a follow-up.

## Decision

### 1. Forward the legacy stub to the real exporter

`src/federation/dtls12.nova:2406` -- change
`dtls_extract_srtp_keys_R29B2_STUB(state)`:

```
fn dtls_extract_srtp_keys_R29B2_STUB(state) {
    if state == 0 { return 0 }
    return dtls_export_srtp_keying_material(state)
}
```

The `state == 0` guard is a defensive short-circuit for the existing
`test_stubs_return_DTLS_ERR_STUB` test path (which called the stub
with a null state); the real exporter would try to index into it and
crash. Returning 0 is the SAFE reject path the real exporter itself
uses when `cipher_active == 0`, so the null-state case surfaces as
the same non-error zero the caller was already treating as
"no keys yet".

The `_R29B2_STUB` suffix stays on the function name for grep-compat;
the header comment (see §4 below) is rewritten to make clear the
suffix is legacy.

### 2. Add public random-accessors

`src/federation/dtls12.nova` near the `dtls_master_secret` accessor
at :1402 -- add:

```
fn dtls_client_random(state) { return state[DTLS_S_SLOT_CLIENT_RANDOM] }
fn dtls_server_random(state) { return state[DTLS_S_SLOT_SERVER_RANDOM] }
```

Both are pure read-only accessors that mirror the shape of the
existing `dtls_master_secret`, `dtls_client_write_key`, etc. Returns
0 when the slot is unset (pre-derive); callers that need to
distinguish "unset" from "buffer of zero bytes" check
`dtls_cipher_active(state)` first (a non-zero cipher_active
guarantees both randoms have been pinned by `dtls_ecdhe_derive`
at :1550).

### 3. Emit `use_srtp` in ClientHello when a profile is offered

Four new module-level constants (RFC 5764 §4.1):

| Constant                          | Value | RFC 5764 name                    |
| --------------------------------- | ----- | -------------------------------- |
| `DTLS_EXT_USE_SRTP`               | 14    | §4.1.1 extension_type            |
| `SRTP_PROFILE_AES128_CM_SHA1_80`  | 1     | §4.1.2 SRTP_AES128_CM_HMAC_SHA1_80 |
| `SRTP_PROFILE_AES128_CM_SHA1_32`  | 2     | §4.1.2 SRTP_AES128_CM_HMAC_SHA1_32 |
| `SRTP_PROFILE_NULL_SHA1_80`       | 5     | §4.1.2 SRTP_NULL_HMAC_SHA1_80    |
| `SRTP_PROFILE_NULL_SHA1_32`       | 6     | §4.1.2 SRTP_NULL_HMAC_SHA1_32    |

Reserved profile IDs 3 and 4 (SRTP_AEAD_AES_128_GCM,
SRTP_AEAD_AES_256_GCM from RFC 7714) are intentionally NOT surfaced
in R2 because the AES-GCM SRTP path is not wired anywhere in
CrossEngin yet -- a future round that ships the SRTP layer proper
can add both constants + the necessary integration in one hop.

One fresh tail-appended state slot, at index 48 (after R1's slots
46 / 47):

```
let DTLS_S_SLOT_SRTP_OFFER = 48  // int -- SRTP_PROFILE_* offered in CH, 0 = none
```

Public setter + accessor:

```
fn dtls_offer_srtp(state, profile)  -- validates profile, writes to slot 48; returns 1/0
fn dtls_srtp_offer(state)           -- read-only accessor
```

`dtls_offer_srtp` validates the `profile` argument against the four
SRTP_PROFILE_* constants; unknown values (including `0`, the "no
offer" sentinel; the reserved IDs 3 / 4; and garbage) leave the slot
unchanged, stamp `state[DTLS_S_SLOT_LAST_ERR] =
"DTLS_ERR_BAD_SRTP_PROFILE"`, and return 0. This "silent no-op with
observable error" shape matches how `dtls_set_role` handles rejects
and keeps the R2 surface total (no crash on garbage input).

New internal helper `_dtls_build_use_srtp_ext(profile)` returns the
9-byte wire sequence:

```
[00, 14,  00, 05,  00, 02,  00, <profile>,  00]
 |__14=ext_type
        |__05=ext_length
              |__02=SRTPProtectionProfiles<> list length
                    |__<profile>=one 2-byte profile ID
                                  |__00=srtp_mki<> length (empty MKI)
```

`_dtls_build_client_hello_body(state)` (updated to take `state` so
it can inspect slot 48) splices this into a length-prefixed
`Extension extensions<0..2^16-1>` block when the slot is non-zero.
When the slot is 0, no extensions block is appended at all -- the
wire bytes stay byte-identical to the pre-R2 42-byte body so
existing wire-byte tests like the "inner CH body length = 42"
assertion at `tests/unit/test_dtls12.nova:448` keep passing. With
the offer set, body length grows to 42 + 2 (extensions-block
length prefix) + 9 (single extension) = 53 bytes.

### 4. Fix the header comment at :161

Replace the "still a stub" text with a paragraph pointing at the
R36B implementation, this ADR's forward, and the R2-added
extension-emission machinery, matching the shape of R33B's amendment
to the cert-verify entry three lines above it.

### 5. ServerHello echo: DEFERRED (documented simplification)

RFC 5764 §4.1.3 requires the server to echo the accepted profile
back in a `use_srtp` extension in its ServerHello. R2 does NOT emit
this echo because there is NO ServerHello body builder in
`dtls12.nova` yet -- the file's handshake seam only carries the
ClientHello + record-layer + AEAD path; the ServerHello is expected
to come in from a future round that adds the server-side handshake
driver. The internal helper `_dtls_build_use_srtp_ext(profile)`
introduced by R2 is intentionally reusable: whichever round adds
the ServerHello body builder can call it verbatim, gated on either
(a) the peer's parsed ClientHello offer or (b) the local
DTLS_S_SLOT_SRTP_OFFER slot (which in mocked handshake tests both
sides can be preset to the same value, sidestepping the parse
gap).

### 6. Extension PARSING: DEFERRED

Reading an incoming `use_srtp` extension off the wire -- either in
the ServerHello or in a ClientHello received by a server-side
driver -- requires an extensions parser that R2 also does not ship.
The ClientHello builder now WRITES the extension bytes correctly;
a future round adds the read-side (extension walker + per-type
dispatcher) plus the ServerHello builder above. R2's forward-only
scope keeps this ADR bounded and orthogonal to that read-side work.

## Consequences

**What R2 enables:**
- A DTLS peer that already parses `use_srtp` in the ClientHello
  (e.g. any RFC 5764 compliant peer) will now see CrossEngin advertise
  an SRTP profile and can negotiate it back.
- Once the handshake completes (`cipher_active == 1`) the caller can
  extract 60 bytes of RFC 5764 §4.2 keying material via either
  `dtls_extract_srtp_keys_R29B2_STUB(state)` (legacy name) or
  `dtls_export_srtp_keying_material(state)` (canonical name). Both
  hit the R36B cache after the first compute; both return the same
  pointer.
- Callers can read the two 32-byte PRF-seed randoms without slot-
  indexing gymnastics: `dtls_client_random(state)`,
  `dtls_server_random(state)`.
- The `dtls_offer_srtp(state, profile)` setter is a stable public
  entry point; a future round that adds a REPL slash or fed-daemon
  env var can drive it from operator config.

**What R2 does NOT enable:**
- CrossEngin cannot yet parse an incoming `use_srtp` extension --
  the ServerHello echo path is not wired, and neither is a
  server-side ClientHello parser that would inspect the offered
  profile list. Peers that ONLY negotiate SRTP by reading the peer's
  offer are still out of interop scope until that follow-up ships.
- The SRTP RTP/RTCP layer (packet-level seal / open under the 60-byte
  keying material) is not built in this file; the exporter surfaces
  the keys but the caller must plug them into a separate SRTP
  implementation. That is out of scope for `src/federation/dtls12.nova`
  entirely; a dedicated `src/federation/srtp.nova` module would be
  the natural home.
- No handshake-time cipher selection based on the offered SRTP
  profile: `dtls_select_cipher_suite` still only picks the AEAD
  cipher suite for record protection; SRTP profile selection is
  independent per RFC 5764 §4.1.4 and (once parsing lands) will be
  its own function.

## Alternatives Considered

**(a) Rip out the `_R29B2_STUB`-suffixed entries entirely** and
inline the R36B name at every call site. Rejected because:
- The header comment block at :132-186 explicitly enumerates the
  R29B.2 stubs as regression guards against accidental renames. The
  test `test_stubs_return_DTLS_ERR_STUB` at
  `tests/unit/test_dtls12.nova:668` pins the STUB names as
  first-class API surface. Removing them would delete the guard.
- A grep for `_R29B2_STUB` across the tree is used by other agents
  to find "what still needs finishing" -- keeping the suffix on the
  now-forwarded entry preserves that discovery pattern (the header
  comment now steers the grepper to the real implementation instead
  of leaving them thinking the work is undone).
- R33B took exactly the same approach for `dtls_cert_verify_R29B2_STUB`
  (kept the name, forwarded the body, updated the header, updated
  the stub test to assert the new forward semantics). R2's SRTP path
  mirrors that precedent 1:1.

**(b) Implement the full extension framework (SNI +
supported_groups + signature_algorithms + use_srtp) in R2.**
Rejected because:
- R1 was strictly cert-chain scoped and R3 is strictly gossip-
  transport scoped; R2 sitting in the middle stays scoped to the
  SRTP arc for the same reason (each round is one testable unit).
- SNI in particular already has an ADR-0093-era note in the fed
  daemon about non-trivial hostname negotiation semantics; folding
  it into R2 would drag in the ADR-0094 hostname / SAN machinery
  and blur the SRTP forward / emission story that R2's tests pin.
- The `_dtls_build_use_srtp_ext(profile)` helper R2 introduces is
  DELIBERATELY specialized to one extension type; the extensions
  BLOCK it lives inside (2-byte length prefix + concatenated
  extension bytes) is the framework hook -- a future round that
  adds more extensions grows the block by concatenating more
  helper outputs inside the same length envelope. No rewrite
  needed to add extension 2 or 3.

**(c) Immediately parse the peer's `use_srtp` echo in ServerHello
+ negotiate mutual acceptance.** Rejected because there is no
ServerHello body builder in this file yet; parsing an incoming
extension requires knowing where the extension block starts in the
ServerHello wire bytes, which requires the ServerHello parser we
haven't built. R2 keeps the two-way negotiation deferred as an
explicit non-goal.

**(d) Auto-populate slot 48 from an env var at fed daemon boot.**
Rejected as scope creep -- the setter `dtls_offer_srtp(state,
profile)` is a stable seam; a future round that wants
`CE_FED_DTLS_SRTP_PROFILE` env config can call it from
`examples/crossengin_fed_daemon.nova` in one line without touching
this file. R2 keeps the daemon untouched.

## Implementation Notes

**RFC 5764 §4.1.2 profile IDs.** The four values R2 surfaces are
the IDs the RFC's initial IANA registry enumerates as SUPPORTED (not
reserved). The AEAD-GCM profiles from RFC 7714 (IDs 3 and 4) are
intentionally NOT surfaced -- the SRTP AEAD implementation is not
in the tree yet, and offering a profile we cannot honor would be
a footgun in an interop scenario. `dtls_offer_srtp` rejects them
explicitly.

**9-byte wire shape.** The extension is emitted as a single
allocated buffer via `_dtls_build_use_srtp_ext(profile)`. The bytes
match the RFC 5764 §4.1.1 schema verbatim:
`extension_type (2B, BE) || extension_length (2B, BE) ||
SRTPProtectionProfiles<length> || srtp_mki<length>`. The wire
tests in `test_dtls12.nova` (`test_r2_use_srtp_extension_emitted_in_client_hello`,
`test_r2_use_srtp_extension_with_different_profile`) probe every one
of the 9 bytes to lock the shape in as a regression guard.

**Extensions block wrapper.** The ClientHello grows from 42 to 53
bytes when a profile is offered: 42 (pre-R2 fixed prefix) + 2
(extensions-block length prefix carrying value 9) + 9 (the single
extension). The extensions block is APPENDED after the compression
methods list per RFC 5246 §7.4.1.2. When no profile is offered, the
extensions block is NOT emitted at all -- not even an empty
zero-length one -- because pre-R2 wire bytes were exactly 42 and
some existing tests (`tests/unit/test_dtls12.nova:448`) pin that
length. Emitting an empty extensions block would grow the body to
44 and break those tests without any interop benefit.

**Backwards compatibility.**
- `_dtls_build_client_hello_body` now takes `state`. Only ONE caller
  exists in the tree (`dtls_client_init` at :1210) and it was
  updated to pass the parameter. External code that reaches into
  the private `_dtls_*` prefix is out of contract by convention.
- `dtls_extract_srtp_keys_R29B2_STUB(state)` return type widened
  from "always the DTLS_ERR_STUB string" to "int 0 on no-cipher /
  null state OR the 60-byte buffer on success". Callers that
  compared against `DTLS_ERR_STUB` will now see 0 (which
  `if r == 0` catches, so most defensive callers get the same
  outcome). The one existing test that pinned the sentinel behavior
  (`test_stubs_return_DTLS_ERR_STUB` at
  `tests/unit/test_dtls12.nova:686`) is updated to assert the new
  forward semantics: null state -> 0, fresh state -> 0.
- `dtls_init()` now pushes an additional zero to slot 48. State
  lists that other code allocated / cached WITHOUT going through
  `dtls_init` (there are none in the tree) would need a slot
  extension; the audit is that every state comes from `dtls_init`
  today so this is safe.

**Test count.** ~70 new `ce_check` / `ce_eq` assertions across 12
new `test_r2_*` functions:
- `test_r2_extract_srtp_keys_forwards_to_real` -- 3 checks (non-zero
  buf + cache slot populated + boundary byte in range).
- `test_r2_stub_byte_identical_to_real_exporter` -- 4 checks
  (both non-zero + same pointer + byte-identical output).
- `test_r2_ekm_layout_60_bytes` -- 9 checks (buf non-zero + each of
  the 4 RFC 5764 §4.2 slice boundaries at bytes 0/15/16/31/32/45/46/59).
- `test_r2_ekm_deterministic_by_random` -- 3 checks (both
  non-zero + byte-identical output across two separate handshakes).
- `test_r2_client_random_accessor` -- 3 checks (unset returns 0 +
  set returns exact pointer + bytes match source).
- `test_r2_server_random_accessor` -- 3 checks (mirror of client).
- `test_r2_random_accessors_after_handshake` -- 4 checks (alice's cr
  + sr + bob's cr matches alice + bob's sr matches alice).
- `test_r2_offer_srtp_sets_slot` -- 10 checks (four accepted
  profiles + slot value assertions + the accessor).
- `test_r2_offer_srtp_invalid_profile_is_noop` -- 8 checks (999,
  reserved 3, zero sentinel each reject + slot unchanged + last_err
  stamped).
- `test_r2_use_srtp_extension_emitted_in_client_hello` -- 13
  checks (record parses + handshake parses + body length 53 +
  9-byte extension shape byte-by-byte + extensions-block length
  prefix bytes).
- `test_r2_use_srtp_default_absent_from_client_hello` -- 3 checks
  (record + body length 42 + slot 0).
- `test_r2_use_srtp_extension_with_different_profile` -- 2 checks
  (body length 53 + profile_id byte matches 5).
- Modified `test_stubs_return_DTLS_ERR_STUB` (was 1 SRTP-related
  check; now 2 -- null-state forward + fresh-state forward).

## Files touched

**Files modified (R2):**
- `src/federation/dtls12.nova` -- (1) header at :161 rewritten to
  describe the R36B implementation + R2 forward + R2 extension-
  emission story (matches R33B's amendment shape for cert-verify);
  (2) new slot `DTLS_S_SLOT_SRTP_OFFER = 48` + new constants
  `DTLS_EXT_USE_SRTP = 14`, `SRTP_PROFILE_AES128_CM_SHA1_80 = 1`,
  `SRTP_PROFILE_AES128_CM_SHA1_32 = 2`, `SRTP_PROFILE_NULL_SHA1_80
  = 5`, `SRTP_PROFILE_NULL_SHA1_32 = 6` after the R1 counters;
  (3) `dtls_init` extended with one extra `push(st, 0)` for slot
  48; (4) new `_dtls_build_use_srtp_ext(profile)` helper +
  `_dtls_build_client_hello_body(state)` signature widened to take
  state and splice the extension when slot 48 is non-zero;
  (5) `dtls_client_init` call site updated to pass `state`;
  (6) new public accessors `dtls_client_random(state)`,
  `dtls_server_random(state)`, `dtls_srtp_offer(state)` and setter
  `dtls_offer_srtp(state, profile)` near `dtls_master_secret`;
  (7) `dtls_extract_srtp_keys_R29B2_STUB(state)` body replaced with
  a null-guarded forward to `dtls_export_srtp_keying_material`.
- `tests/unit/test_dtls12.nova` -- (1) updated
  `test_stubs_return_DTLS_ERR_STUB` to assert the new forward
  semantics on the SRTP entry (null state -> 0, fresh state -> 0)
  instead of the old DTLS_ERR_STUB sentinel; (2) 12 new
  `test_r2_*` functions covering forward equivalence, layout
  probes, determinism, accessors, setter validation, and wire-byte
  shape; (3) main() extended to call all 12 new tests.
- `ENHANCEMENTS_ROADMAP.md` -- Phase O R2 shipped-note.

**Files added (R2):**
- `docs/adr/0095-dtls-srtp-completion.md` -- this ADR.

**Verification.** Structural review + `make lint-ints` (12
pre-existing findings unchanged; none in `src/federation/dtls12.nova`
or `tests/unit/test_dtls12.nova`). `make test` cannot run end-to-end
because the NOVA compiler self-hosting bootstrap segfaults on this
bench (per Phase L / M / N / R1 standing caveat); the 12 new unit
test functions are authored under the same helpers
(`_tdtls_setup_ecdhe_pair`, `_tdtls_make_random32`, `_tdtls_buf_eq`,
`ce_check`, `ce_eq`) as the passing suite so they slot into a
working bootstrap without change.

**Non-goals for R2** (queued for follow-up rounds):
- No `use_srtp` extension PARSING (read-side; requires an
  extensions walker + per-type dispatcher).
- No ServerHello body builder + ServerHello `use_srtp` echo
  (requires the server-side handshake driver).
- No SRTP RTP/RTCP layer -- the exporter surfaces the 60-byte
  keying material but no packet-level SRTP seal / open is wired.
- No AEAD-GCM SRTP profile support (RFC 7714 IDs 3 / 4).
- No `CE_FED_DTLS_SRTP_PROFILE` env-var wiring in the fed daemon.
- No DTLS-over-TCP transport wrap (R3).

## References

- ADR-0094 -- Phase O R1 (cert-chain + truststore), the round this
  ADR builds on and whose format template it mirrors.
- ADR-0093 -- Phase N R2 (action module), the round R1's format
  template mirrored in turn.
- RFC 5764 -- DTLS-SRTP framework (§4.1 `use_srtp` extension,
  §4.1.2 profile IDs, §4.2 keying-material exporter).
- RFC 5246 -- TLS 1.2 (extensions field in ClientHello §7.4.1.2,
  PRF construction §5).
- RFC 6347 -- DTLS 1.2.
- RFC 5705 -- TLS keying-material exporter framework (RFC 5764 §4.2
  is a specialization).
- RFC 7714 -- AES-GCM authenticated encryption for SRTP (source of
  reserved profile IDs 3 / 4 that R2 intentionally does NOT surface).
- `src/federation/dtls12.nova:2460` -- `dtls_export_srtp_keying_material`
  (R36B real exporter this ADR forwards to).
- `src/federation/dtls12.nova:2406` -- `dtls_extract_srtp_keys_R29B2_STUB`
  (legacy wrapper R2 rewires).
- `src/federation/dtls12.nova:1046` -- `_dtls_build_client_hello_body`
  (extension-emission call site).
