#!/usr/bin/env python3
"""CrossEngin secure-channel echo helper.

A tiny single-connection TCP server that talks the same PSK
ChaCha20-Poly1305 framing as `src/io/transducers/secure_channel.nova`.
Spawned by `tests/integration/scenario_v_secure_channel.sh` so the NOVA
client has a known-correct counterpart to round-trip against.

Wire format (mirrors secure_channel.nova exactly):
  Handshake:
    client -> 12-byte session nonce N0
    derive session_key = ChaCha20-block(PSK, N0, counter=0)[0..32]
    derive nonce_prefix = N0[0..4]
    each subsequent frame:
      [4 BE length] [12 nonce] [ciphertext] [16 tag]
      nonce = nonce_prefix || counter_le_8
      ciphertext = ChaCha20(session_key, nonce, counter=1) XOR plaintext
      poly_key = ChaCha20-block(session_key, nonce, counter=0)[0..32]
      tag      = Poly1305(poly_key, ciphertext)

Behaviour:
  * Accepts the handshake frame (16-byte magic "CE-SC-HS-OK\0\0\0\0\0").
  * If the magic matches, echoes the SAME magic back (server-side
    handshake-ack) using its OWN send counter starting at 1. The client
    increments its recv counter past 1 to consume this.
  * Reads subsequent application frames (counter 2, 3, ...) and echoes
    them back transformed: replaces "ping" with "pong" (case-insensitive
    prefix); otherwise just echoes verbatim.
  * Exits after a single completed round-trip (one application frame in,
    one out) or after a 5s overall timeout.

Usage:
  python3 secure_channel_echo.py <port> <psk_hex>
    port:    integer 1..65535
    psk_hex: 64 hex chars (32 bytes)

Exit codes:
  0  -- successful echo
  1  -- bad arguments or PSK
  2  -- handshake mismatch
  3  -- MAC verification failure
  4  -- timeout / connection error
"""

from __future__ import annotations

import os
import socket
import struct
import sys
import threading
import time


# ---------------------------------------------------------------------------
# ChaCha20 (pure Python, RFC 7539-compatible; matches src/safety/chacha20.nova)
# ---------------------------------------------------------------------------

CC_CONST = (0x61707865, 0x3320646e, 0x79622d32, 0x6b206574)


def _mask32(x: int) -> int:
    return x & 0xFFFFFFFF


def _rotl32(x: int, n: int) -> int:
    return _mask32((x << n) | (x >> (32 - n)))


def _quarter_round(state, a, b, c, d):
    state[a] = _mask32(state[a] + state[b])
    state[d] = _rotl32(state[d] ^ state[a], 16)
    state[c] = _mask32(state[c] + state[d])
    state[b] = _rotl32(state[b] ^ state[c], 12)
    state[a] = _mask32(state[a] + state[b])
    state[d] = _rotl32(state[d] ^ state[a], 8)
    state[c] = _mask32(state[c] + state[d])
    state[b] = _rotl32(state[b] ^ state[c], 7)


def chacha20_block(key: bytes, nonce: bytes, counter: int) -> bytes:
    assert len(key) == 32
    assert len(nonce) == 12
    state = list(CC_CONST)
    state += list(struct.unpack("<8I", key))
    state.append(_mask32(counter))
    state += list(struct.unpack("<3I", nonce))
    orig = state[:]
    for _ in range(10):
        _quarter_round(state, 0, 4, 8, 12)
        _quarter_round(state, 1, 5, 9, 13)
        _quarter_round(state, 2, 6, 10, 14)
        _quarter_round(state, 3, 7, 11, 15)
        _quarter_round(state, 0, 5, 10, 15)
        _quarter_round(state, 1, 6, 11, 12)
        _quarter_round(state, 2, 7, 8, 13)
        _quarter_round(state, 3, 4, 9, 14)
    out = bytearray()
    for i in range(16):
        out += struct.pack("<I", _mask32(state[i] + orig[i]))
    return bytes(out)


def chacha20_xor(key: bytes, nonce: bytes, counter: int, data: bytes) -> bytes:
    out = bytearray()
    produced = 0
    ctr = counter
    while produced < len(data):
        block = chacha20_block(key, nonce, ctr)
        chunk = data[produced:produced + 64]
        out += bytes(b ^ k for b, k in zip(chunk, block[: len(chunk)]))
        produced += len(chunk)
        ctr += 1
    return bytes(out)


# ---------------------------------------------------------------------------
# Poly1305 (pure Python, RFC 7539-compatible)
# ---------------------------------------------------------------------------

P130 = (1 << 130) - 5


def poly1305_mac(key: bytes, msg: bytes) -> bytes:
    assert len(key) == 32
    r = int.from_bytes(key[:16], "little") & 0x0ffffffc0ffffffc0ffffffc0fffffff
    s = int.from_bytes(key[16:], "little")
    a = 0
    off = 0
    while off < len(msg):
        chunk = msg[off:off + 16]
        # n = LE int + appended 1 bit at top of chunk
        n = int.from_bytes(chunk, "little") | (1 << (8 * len(chunk)))
        a = ((a + n) * r) % P130
        off += 16
    tag = (a + s) % (1 << 128)
    return tag.to_bytes(16, "little")


# ---------------------------------------------------------------------------
# Frame helpers (matches src/io/transducers/secure_channel.nova exactly)
# ---------------------------------------------------------------------------

NONCE_LEN = 12
TAG_LEN = 16
KEY_LEN = 32
LEN_HDR = 4
HANDSHAKE_MAGIC = b"CE-SC-HS-OK" + b"\x00" * 5    # 16 bytes total


def derive_session_key(psk: bytes, nonce: bytes) -> bytes:
    block = chacha20_block(psk, nonce, 0)
    return block[:32]


def build_nonce(prefix: bytes, counter: int) -> bytes:
    assert len(prefix) == 4
    return prefix + counter.to_bytes(8, "little")


def make_frame(key: bytes, prefix: bytes, counter: int, plaintext: bytes) -> bytes:
    nonce = build_nonce(prefix, counter)
    ct = chacha20_xor(key, nonce, 1, plaintext)
    poly_key = chacha20_block(key, nonce, 0)[:32]
    tag = poly1305_mac(poly_key, ct)
    body = nonce + ct + tag
    return struct.pack(">I", len(body)) + body


def open_frame(key: bytes, sock: socket.socket) -> bytes | None:
    hdr = recv_exact(sock, LEN_HDR)
    if hdr is None:
        return None
    body_len = struct.unpack(">I", hdr)[0]
    body = recv_exact(sock, body_len)
    if body is None:
        return None
    nonce = body[:NONCE_LEN]
    ct = body[NONCE_LEN:body_len - TAG_LEN]
    tag = body[body_len - TAG_LEN:]
    poly_key = chacha20_block(key, nonce, 0)[:32]
    expected = poly1305_mac(poly_key, ct)
    if tag != expected:
        return None
    return chacha20_xor(key, nonce, 1, ct)


def recv_exact(sock: socket.socket, n: int) -> bytes | None:
    buf = bytearray()
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            return None
        buf += chunk
    return bytes(buf)


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: secure_channel_echo.py <port> <psk_hex>", file=sys.stderr)
        return 1
    port = int(sys.argv[1])
    psk_hex = sys.argv[2]
    try:
        psk = bytes.fromhex(psk_hex)
    except ValueError:
        print("PSK is not valid hex", file=sys.stderr)
        return 1
    if len(psk) != KEY_LEN:
        print(f"PSK must be {KEY_LEN} bytes ({KEY_LEN * 2} hex chars)", file=sys.stderr)
        return 1

    ss = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    ss.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    ss.bind(("127.0.0.1", port))
    ss.listen(1)
    ss.settimeout(5.0)

    # Cooperative readiness signal: emit "READY" on stdout so the bash
    # harness can wait for the line. flush so the FD doesn't buffer.
    print(f"READY {port}", flush=True)

    try:
        conn, _addr = ss.accept()
    except socket.timeout:
        print("accept timeout", file=sys.stderr)
        return 4
    conn.settimeout(5.0)
    try:
        # 1) read the 12-byte handshake nonce.
        hs_nonce = recv_exact(conn, NONCE_LEN)
        if hs_nonce is None or len(hs_nonce) != NONCE_LEN:
            print("handshake: nonce short", file=sys.stderr)
            return 2
        # 2) derive the session key.
        key = derive_session_key(psk, hs_nonce)
        prefix = hs_nonce[:4]
        # 3) read the handshake magic frame (counter 1 from client).
        magic_in = open_frame(key, conn)
        if magic_in is None:
            print("handshake: open_frame failed (MAC reject or transport)",
                  file=sys.stderr)
            return 3
        if magic_in[:11] != HANDSHAKE_MAGIC[:11]:
            print(f"handshake: magic mismatch: {magic_in!r}", file=sys.stderr)
            return 2
        # 4) echo the magic back as the server's counter-1 frame.
        conn.sendall(make_frame(key, prefix, 1, HANDSHAKE_MAGIC))
        # 5) read one application frame.
        payload = open_frame(key, conn)
        if payload is None:
            print("app: open_frame failed", file=sys.stderr)
            return 3
        # 6) transform: "ping" -> "pong", else echo.
        text = payload.decode("utf-8", errors="replace")
        if text.lower().startswith("ping"):
            reply_text = "pong" + text[4:]
        else:
            reply_text = text
        reply = reply_text.encode("utf-8")
        # 7) emit the echo (server's frame counter 2).
        conn.sendall(make_frame(key, prefix, 2, reply))
        return 0
    finally:
        try:
            conn.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        conn.close()
        ss.close()


if __name__ == "__main__":
    sys.exit(main())
