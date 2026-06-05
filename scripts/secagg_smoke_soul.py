#!/usr/bin/env python3
"""Minimal SecAgg-aware soul client for the P3.8r dropout-resilience
integration test (`tests/integration/scenario_u_secagg.sh`).

Usage:
    secagg_smoke_soul.py [--mode dropout|survivor] [--peer PEER_ID]
                         [--token TOKEN] [--soul-id ID]
                         [--port PORT] [--host HOST]

Modes:
  survivor : full SecAgg-r round-trip. Sends SECAGG_HELLO, FED_JOIN,
             SECAGG_PEER, ACK 0; receives FED_ROUND; emits one
             FED_STAT_MASKED record; sends ACK <round>; then drives
             the dropout-resilience hook: on receiving FED_DROPOUT,
             emits a FED_RECON_MASKED record with the dropped peer's
             mask contribution removed; finally consumes
             FED_AGGREGATE_SUM and exits.

  dropout  : SECAGG_HELLO, FED_JOIN, SECAGG_PEER, ACK 0 -- then CLOSES
             the socket immediately. This simulates the soul that
             vanished after the join handshake. The coordinator will
             detect the closed fd as a dropout and broadcast
             FED_DROPOUT to the surviving peers.

The Python script uses the SAME 15-bit LCG mask derivation as the NOVA
`src/learning/secure_aggregation.nova` module so a survivor's
FED_RECON_MASKED line will arithmetically cancel against the
coordinator's expected sum. The hash function and LCG iteration count
are mirrored verbatim.
"""

import argparse
import socket
import sys
import time


# Mirrored from src/learning/secure_aggregation.nova (P3.8 / ADR-0055).
_LCG_MUL = 6917
_LCG_INC = 31
_LCG_MASK = 32767  # 2^15 - 1


def _hash_str(s: str) -> int:
    h = 1
    for c in s.encode("ascii", errors="strict"):
        h = (h * 31) & _LCG_MASK
        h = (h + c) & _LCG_MASK
    return 1 if h == 0 else h


def _lcg_step(seed: int) -> int:
    p1 = (seed * _LCG_MUL) & _LCG_MASK
    mid = (p1 + _LCG_INC) & _LCG_MASK
    p2 = (mid * _LCG_MUL) & _LCG_MASK
    nxt = (p2 + _LCG_INC) & _LCG_MASK
    high = nxt // 256
    mixed = (nxt ^ high) & _LCG_MASK
    return 1 if mixed == 0 else mixed


def _seed_for_pair(token: str, round_id: int) -> int:
    return _hash_str(f"{token}:{round_id}")


def mask_for_peer(token: str, round_id: int, k_dim: int) -> int:
    """Same as sa_mask_for_peer in NOVA -- k+1 LCG iterations."""
    cur = _seed_for_pair(token, round_id)
    for _ in range(k_dim + 1):
        cur = _lcg_step(cur)
    return cur


def id_compare(a: str, b: str) -> int:
    if a < b:
        return -1
    if a > b:
        return 1
    return 0


def apply_masks(soul_id: str, x: int, k_dim: int, peers):
    """peers is a list of (peer_id, token); mirrors sa_apply_masks."""
    masked = x
    for peer_id, token in peers:
        m = mask_for_peer(token, 1, k_dim)  # round_id fixed to 1 for the test
        cmp = id_compare(soul_id, peer_id)
        if cmp < 0:
            masked += m
        elif cmp > 0:
            masked -= m
    return masked


def reconcile_for_dropped(soul_id: str, masked_x: int, dropped_id: str,
                          k_dim: int, peers):
    """Remove the dropped peer's mask contribution from a masked value."""
    for peer_id, token in peers:
        if peer_id == dropped_id:
            m = mask_for_peer(token, 1, k_dim)
            cmp = id_compare(soul_id, dropped_id)
            if cmp < 0:
                # soul ADDED +m -> remove it (subtract).
                return masked_x - m
            if cmp > 0:
                # soul SUBTRACTED -m -> remove it (add back).
                return masked_x + m
    return masked_x


def recv_line(sock):
    data = bytearray()
    while True:
        b = sock.recv(1)
        if not b:
            return None if not data else bytes(data).decode("ascii", errors="replace")
        if b == b"\n":
            return bytes(data).decode("ascii", errors="replace")
        data.extend(b)


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--mode", choices=["survivor", "dropout"], default="survivor")
    p.add_argument("--peer", required=True)
    p.add_argument("--token", required=True)
    p.add_argument("--soul-id", required=True)
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--port", type=int, default=8777)
    p.add_argument("--x-promo", type=int, default=100)
    p.add_argument("--x-atr", type=int, default=50)
    p.add_argument("--tag", default="topic:test")
    args = p.parse_args()

    peers = [(args.peer, args.token)]

    # Dial with a small retry budget so the coord has time to bind.
    sock = None
    deadline = time.time() + 8.0
    last_err = None
    while time.time() < deadline:
        try:
            sock = socket.create_connection((args.host, args.port), timeout=5.0)
            break
        except (ConnectionRefusedError, OSError) as e:
            last_err = e
            time.sleep(0.2)
    if sock is None:
        sys.stderr.write(f"secagg_smoke_soul: cannot dial {args.host}:{args.port}: {last_err}\n")
        return 1

    try:
        # Handshake: SECAGG_HELLO + OK + FED_JOIN + SECAGG_PEER + ACK 0.
        sock.sendall(b"SECAGG_HELLO ce-fed v2-sa\n")
        ok = recv_line(sock)
        sys.stderr.write(f"secagg_smoke_soul[{args.soul_id}]: server replied {ok!r}\n")
        sock.sendall(f"FED_JOIN {args.soul_id} 1000\n".encode("ascii"))
        sock.sendall(f"SECAGG_PEER {args.peer} {args.token}\n".encode("ascii"))
        sock.sendall(b"ACK 0\n")
        if args.mode == "dropout":
            # Goal: drop AFTER the JOIN handshake but BEFORE the round
            # is processed. Closing immediately gives the coordinator
            # an EOF on the next recv (which is the FED_STAT_MASKED
            # read in _fed_collect_masked_with_dropout) -> flags this
            # soul as dropped.
            sys.stderr.write(f"secagg_smoke_soul[{args.soul_id}]: DROPOUT mode -- closing after handshake\n")
            sock.close()
            return 0
        # Survivor: receive FED_ROUND, emit one FED_STAT_MASKED, ACK,
        # then loop reading either FED_AGGREGATE_SUM (clean) or
        # FED_DROPOUT (recon path) until EOF / round completes.
        rnd = recv_line(sock)
        sys.stderr.write(f"secagg_smoke_soul[{args.soul_id}]: round line {rnd!r}\n")
        # Mask + send the test stat.
        mp = apply_masks(args.soul_id, args.x_promo, 0, peers)
        ma = apply_masks(args.soul_id, args.x_atr, 1, peers)
        # NOVA round_id we always operate against is 1 for the test.
        sock.sendall(f"FED_STAT_MASKED 1 {args.tag} {mp} {ma}\n".encode("ascii"))
        sock.sendall(b"ACK 1\n")
        # Track the unreconciled stat in case the coord sends FED_DROPOUT.
        last_mp, last_ma = mp, ma
        while True:
            line = recv_line(sock)
            if line is None:
                break
            sys.stderr.write(f"secagg_smoke_soul[{args.soul_id}]: recv {line!r}\n")
            if line.startswith("FED_AGGREGATE_SUM "):
                # Clean completion -- coordinator broadcasts SUM, we exit.
                break
            if line.startswith("FED_DROPOUT "):
                parts = line.split(" ")
                # FED_DROPOUT <round> <dropped_id>
                dropped_id = parts[2]
                adj_p = reconcile_for_dropped(args.soul_id, last_mp,
                                              dropped_id, 0, peers)
                adj_a = reconcile_for_dropped(args.soul_id, last_ma,
                                              dropped_id, 1, peers)
                sock.sendall(
                    f"FED_RECON_MASKED 1 {args.soul_id} {args.tag} {adj_p} {adj_a}\n".encode("ascii")
                )
                sock.sendall(b"ACK 1\n")
                last_mp, last_ma = adj_p, adj_a
                # Continue reading for the eventual AGGREGATE_SUM.
                continue
            if line.startswith("BYE"):
                break
            # Any other event -> just keep reading.
    finally:
        try:
            sock.close()
        except Exception:
            pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
