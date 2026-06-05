# ADR R36F-0003: Federation transport -- DTLS 1.2 + ICE + STUN + TURN + SRTP

## Status
Accepted (R36F) -- transport stack assembled across R30C (ICE),
R31B (DTLS PRF), R32B (DTLS cert verify), R33B (DTLS cert-verify wire +
replay window), R34B (TURN codec), R34C (SRTP wire), R35A (DTLS-SRTP
keying), R35B (TURN client state machine), R35D (ICE-TURN integration).

## Context
CrossEngin v2 needs peer-to-peer federation between desktop instances
across NAT, residential networks, and enterprise firewalls without
relying on a central coordinator. The candidate transport stacks were:

  1. **QUIC + custom federation framing.** Modern, one-protocol,
     0-RTT, multiplexed. Strong story for cloud-to-cloud. Weak story
     for NAT traversal in residential settings without a STUN-equivalent
     side channel.
  2. **HTTP/3 over QUIC.** Inherits QUIC's strengths. Forces a request-
     response shape that fights against gossip's push-mostly traffic.
  3. **WebRTC-style stack (DTLS 1.2 + ICE + STUN + TURN + SRTP).**
     Designed exactly for the residential NAT-traversal case. Mature
     spec coverage (RFCs 5245, 5389, 5764, 5766, 8445, 8489, 6347).
     Larger surface area but the surface area maps 1:1 to RFCs we can
     test against.
  4. **Plain TLS over TCP.** Easy. Loses to NAT-traversal: a residential
     peer behind double NAT has no inbound TCP path without a relay.

## Decision
**CrossEngin federation uses the DTLS 1.2 + ICE + STUN + TURN + SRTP
stack.** Implementation lives in `src/federation/`:

  - `ice.nova` (R30C) -- RFC 8445 ICE agent: candidate gathering, pair
    checking, nomination.
  - `stun_rfc8489.nova` -- RFC 8489 STUN binding requests +
    XOR-MAPPED-ADDRESS for server-reflexive candidates.
  - `turn.nova` (R34B + R35B) -- RFC 5766/8656 TURN: Allocate /
    Refresh / Send / Data / CreatePermission / ChannelBind, with a
    client-side six-state lifecycle machine.
  - `ice_turn.nova` (R35D) -- the escalation glue: when ICE checks
    exhaust, allocate a TURN relay candidate.
  - `dtls12.nova` (R31B + R32B + R33B + R35A) -- RFC 6347 DTLS 1.2 with
    ECDHE key exchange, TLS-1.2 PRF, cert-verify wire, anti-replay
    window per epoch, and the RFC 5764 §4.2 SRTP keying-material
    exporter (label `"EXTRACTOR-dtls_srtp"`).
  - `srtp.nova` (R34C + R35A) -- RFC 3711 SRTP: AES-CM-128 + HMAC-SHA1
    -80 + KDF + anti-replay, keyed via the DTLS exporter.

**Trust model.**
  - **Peer identity = self-signed certificate.** Each CrossEngin
    instance generates a fresh P-256 cert at first run and pins its
    fingerprint in the local peer table.
  - **No CA chain validation.** Federation peers are not browsers;
    there is no root-of-trust hierarchy. The DTLS-SRTP cert-pinning
    pattern (out-of-band fingerprint exchange + per-session pin
    verification) is sufficient for the v1 / v2 scope.
  - **PFS via ECDHE.** Compromise of a long-term peer key cannot
    decrypt past sessions.
  - **Replay protection via DTLS sequence-number window + SRTP
    anti-replay.**

## Consequences
**Positive.**
  - **NAT traversal works** in residential, enterprise, and
    carrier-grade NAT environments via the ICE / TURN escalation path.
  - **Spec-mapped tests.** Each RFC clause has a test assertion in
    `tests/unit/test_*.nova`. Regressions show up as a specific
    assertion failure pinning a specific clause.
  - **No OpenSSL dependency.** The crypto leaves (`safety/sha256.nova`,
    `safety/p256.nova`, `safety/aes_gcm.nova`, `safety/x509.nova`)
    are NOVA-native and audited per ADR R36F-0006.

**Negative.**
  - **Implementation cost was high.** Rounds R28-R35 of the federation
    track are dominated by transport. We chose to accept this cost
    upfront rather than ship a worse but cheaper transport.
  - **Cert pinning is brittle in mobility scenarios.** A peer that
    rotates its cert (e.g. fresh-install reset) must re-exchange
    fingerprints out of band. v2's attestation flow will subsume this.
  - **MKI = 0 in SRTP (R34C/R35A).** WebRTC interop default; per-stream
    rekey requires a fresh DTLS handshake. We document this; a future
    R37+ round can lift it if real-time rekey ever matters.

**Follow-up rounds.**
  - Orchestrator that ties `webrtc.nova` / `ice.nova` / `dtls12.nova` /
    `srtp.nova` into one end-to-end call site (deferred at R35A).
  - TURN long-term-credential auth (USERNAME / MESSAGE-INTEGRITY /
    NONCE / REALM) -- R34B's emit path doesn't generate them; R35D
    inherits the limitation.
  - DTLS 1.3 migration (post-v1).

## Alternatives considered
  - **QUIC.** Rejected as the *primary* transport because NAT-traversal
    without a coordinator is not in the QUIC spec; we'd have to layer
    ICE on top anyway. We may add QUIC as a same-LAN fast-path in v2.
  - **HTTP/3.** Rejected: forces request-response shape on a federation
    that is gossip-push-mostly.
  - **Plain TLS over TCP.** Rejected: no inbound path through NAT
    without a relay; the relay would be a central coordinator.
  - **Noise Protocol over UDP.** Considered for the handshake layer;
    rejected in favour of DTLS 1.2 to match the WebRTC stack so we can
    interop with browser clients in v3.
  - **CA chain validation.** Rejected for v1 because no federation root
    of trust exists. Cert pinning is the operationally simpler model.
