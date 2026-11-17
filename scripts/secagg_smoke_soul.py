#!/usr/bin/env python3
"""Minimal SecAgg-aware soul client (protocol v3n-sa) for the integration
test `tests/integration/scenario_u_secagg.sh`.

Usage:
    secagg_smoke_soul.py --soul-id ID --peer P1[,P2...] --token TOKEN
                         [--mode survivor|dropout] [--port PORT] [--host HOST]
                         [--x-promo N] [--x-atr N] [--tag TAG]
                         [--nonce HEX32] [--fault none|no-nonce|no-peer|legacy-hello|legacy-peer|dh-public|leave-after-stat]
                         [--wire-log PATH]
    secagg_smoke_soul.py --print-mask --soul-id A --peer B --token T
                         --nonce HEX32 --peer-nonce HEX32 [--round R]
                         [--dim D] [--tag TAG]
    secagg_smoke_soul.py --selftest

Handshake (v3n-sa):
    SECAGG_HELLO ce-fed v3n-sa       -> the exact "OK ce-fed v3n-sa protocol
                                        accepted" reply is required
    FED_JOIN <soul_id> 1000
    SECAGG_PEER <peer_id>            one per --peer; NO token on the wire
                                     (--token is a LOCAL pair secret)
    SECAGG_NONCE <soul_id> <32 hex>  fresh per run (os.urandom), or --nonce
    ACK 0
  then the relay: SECAGG_NONCE <peer> <hex> lines (only ids in --peer are
  accepted), ended by "ACK 0". Every peer must have a nonce, else the soul
  refuses (exit 2) without sending stats. Then FED_ROUND <rid> <deadline>;
  the round id is parsed from that line (never hardcoded).

Modes:
  survivor : the full round: FED_STAT_MASKED <rid> ..., ACK <rid>, then
             FED_AGGREGATE_SUM / FED_DROPOUT / BYE handling. On FED_DROPOUT
             it reconciles ONLY when CE_SECAGG_ALLOW_RECON=1 (same limits as
             the NOVA soul: no duplicate, known peers only, never the last
             mask); otherwise it logs "refusing reconciliation
             (CE_SECAGG_ALLOW_RECON not set)" and leaves without sending
             anything.
  dropout  : the handshake and the relay drain, then CLOSES the socket
             (the soul that vanished after joining).

Faults (negative tests): no-nonce omits SECAGG_NONCE; no-peer omits every
SECAGG_PEER line; legacy-hello sends the old v3-sa HELLO; legacy-peer sends
the old token-carrying 3-field SECAGG_PEER line; dh-public announces a
(fake) FED_DH_PUBLIC key. The coordinator must reject each (dh-public only
without CE_SECAGG_ALLOW_WEAK_DH=1).

Mask derivation: byte-identical to _sa_mask32 in
src/learning/secure_aggregation.nova (v3n-sa):
    mask = first 4 bytes (big-endian) of SHA-256("ce-secagg-v3n|"
           + f(id_lo) + f(id_hi) + f(secret) + f(nonce_lo) + f(nonce_hi)
           + f(str(round)) + f(source) + f(str(dim)))
    f(v) = "<len(v)>:<v>|"; nonce_lo / nonce_hi belong to id_lo / id_hi.
All masked arithmetic is modulo 2^32. The privacy this gives the coordinator
is COMPUTATIONAL (SHA-256 as a PRF over a secret that never leaves the
soul), not information-theoretic.
"""

import argparse
import hashlib
import os
import socket
import sys
import time

# Mirrored from src/learning/secure_aggregation.nova (_sa_mask32, SA_MOD).
SA_MOD = 1 << 32
HELLO = "SECAGG_HELLO ce-fed v3n-sa"
OK = "OK ce-fed v3n-sa protocol accepted"
LEGACY_HELLO = "SECAGG_HELLO ce-fed v3-sa"
NONCE_HEX_LEN = 32

# Fixed vector shared with tests/unit/test_secure_aggregation.nova
# (test_sa_mask_python_parity): alice -> bob, token tok-ab, round 1, dim 0,
# source topic:test, alice nonce 00..01, bob nonce 00..02.
PARITY_NONCE_A = "0" * 31 + "1"
PARITY_NONCE_B = "0" * 31 + "2"
PARITY_EXPECTED = 4135031036


def _kdf_field(v: str) -> str:
    # NOVA counts bytes; the ids, tokens and nonces used here are ASCII.
    return f"{len(v.encode('ascii'))}:{v}|"


def id_compare(a: str, b: str) -> int:
    ab, bb = a.encode("ascii"), b.encode("ascii")
    if ab < bb:
        return -1
    if ab > bb:
        return 1
    return 0


def mask_for_peer(id_a: str, id_b: str, secret: str, nonce_a: str, nonce_b: str,
                  round_id: int, k_dim: int, source: str = "") -> int:
    """Same as _sa_mask32 in NOVA (v3n-sa)."""
    lo, hi, nlo, nhi = id_a, id_b, nonce_a, nonce_b
    if id_compare(id_a, id_b) > 0:
        lo, hi, nlo, nhi = id_b, id_a, nonce_b, nonce_a
    msg = ("ce-secagg-v3n|" + _kdf_field(lo) + _kdf_field(hi) + _kdf_field(secret)
           + _kdf_field(nlo) + _kdf_field(nhi)
           + _kdf_field(str(round_id)) + _kdf_field(source) + _kdf_field(str(k_dim)))
    return int.from_bytes(hashlib.sha256(msg.encode("ascii")).digest()[:4], "big")


class Refused(Exception):
    pass


def apply_masks(soul_id, x, k_dim, peers, token, my_nonce, peer_nonces, rid, source=""):
    """Mirrors sa_apply_masks_src: refuses (never returns raw x) with no
    peers or a peer without a nonce."""
    if not peers:
        raise Refused("0 peers")
    masked = x % SA_MOD
    for peer_id in peers:
        pn = peer_nonces.get(peer_id)
        if not pn or not my_nonce:
            raise Refused(f"missing nonce for {peer_id}")
        m = mask_for_peer(soul_id, peer_id, token, my_nonce, pn, rid, k_dim, source)
        cmp = id_compare(soul_id, peer_id)
        if cmp < 0:
            masked = (masked + m) % SA_MOD
        elif cmp > 0:
            masked = (masked - m) % SA_MOD
        else:
            raise Refused("peer equals own id")
    return masked


def reconcile_for_dropped(soul_id, masked_x, dropped_id, k_dim, token, my_nonce,
                          peer_nonces, rid, source=""):
    """Remove the dropped peer's mask contribution from a masked value."""
    m = mask_for_peer(soul_id, dropped_id, token, my_nonce, peer_nonces[dropped_id],
                      rid, k_dim, source)
    cmp = id_compare(soul_id, dropped_id)
    if cmp < 0:
        return (masked_x - m) % SA_MOD      # soul ADDED +m -> remove it
    if cmp > 0:
        return (masked_x + m) % SA_MOD      # soul SUBTRACTED m -> add back
    return masked_x


def is_nonce_hex(s: str) -> bool:
    return len(s) == NONCE_HEX_LEN and all(c in "0123456789abcdef" for c in s)


def selftest() -> int:
    got = mask_for_peer("alice", "bob", "tok-ab", PARITY_NONCE_A, PARITY_NONCE_B,
                        1, 0, "topic:test")
    sym = mask_for_peer("bob", "alice", "tok-ab", PARITY_NONCE_B, PARITY_NONCE_A,
                        1, 0, "topic:test")
    other = mask_for_peer("alice", "bob", "tok-ab", "0" * 31 + "3", PARITY_NONCE_B,
                          1, 0, "topic:test")
    ok = (got == PARITY_EXPECTED and sym == got and other != got)
    print(f"selftest parity mask={got} expected={PARITY_EXPECTED} symmetric={sym == got} "
          f"nonce_changes_mask={other != got} -> {'OK' if ok else 'FAIL'}")
    return 0 if ok else 1


class Wire:
    def __init__(self, sock, log_path, soul_id):
        self.sock = sock
        self.log = open(log_path, "a") if log_path else None
        self.soul_id = soul_id
        self.buf = bytearray()

    def send(self, line: str):
        self.sock.sendall((line + "\n").encode("ascii"))
        if self.log:
            self.log.write(f"> {line}\n")
            self.log.flush()

    def recv(self):
        data = bytearray()
        while True:
            try:
                b = self.sock.recv(1)
            except socket.timeout:
                self._err("timeout waiting for a line from the coordinator")
                return None
            if not b:
                line = None if not data else bytes(data).decode("ascii", errors="replace")
                break
            if b == b"\n":
                line = bytes(data).decode("ascii", errors="replace")
                break
            data.extend(b)
        if self.log:
            self.log.write(f"< {line if line is not None else '<EOF>'}\n")
            self.log.flush()
        return line

    def _err(self, msg):
        sys.stderr.write(f"secagg_smoke_soul[{self.soul_id}]: {msg}\n")


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--mode", choices=["survivor", "dropout"], default="survivor")
    p.add_argument("--fault", choices=["none", "no-nonce", "no-peer", "legacy-hello",
                                       "legacy-peer", "dh-public", "leave-after-stat"],
                   default="none")
    p.add_argument("--peer", default="", help="peer soul id; comma-separated for several peers")
    p.add_argument("--token", default="", help="LOCAL pair secret (never sent on the wire)")
    p.add_argument("--soul-id", default="")
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--port", type=int, default=8777)
    p.add_argument("--x-promo", type=int, default=100)
    p.add_argument("--x-atr", type=int, default=50)
    p.add_argument("--tag", default="topic:test")
    p.add_argument("--nonce", default="", help="fix this soul's nonce (tests only)")
    p.add_argument("--wire-log", default="")
    p.add_argument("--timeout", type=float, default=15.0)
    p.add_argument("--print-mask", action="store_true")
    p.add_argument("--peer-nonce", default="")
    p.add_argument("--round", type=int, default=1)
    p.add_argument("--dim", type=int, default=0)
    p.add_argument("--selftest", action="store_true")
    args = p.parse_args()

    if args.selftest:
        return selftest()
    if args.print_mask:
        print(mask_for_peer(args.soul_id, args.peer, args.token, args.nonce,
                            args.peer_nonce, args.round, args.dim, args.tag))
        return 0

    sid = args.soul_id
    if not sid or not args.token:
        sys.stderr.write("secagg_smoke_soul: --soul-id and --token are required\n")
        return 2

    def log(msg):
        sys.stderr.write(f"secagg_smoke_soul[{sid}]: {msg}\n")

    peers = [pid for pid in args.peer.split(",") if pid]
    if not peers:
        log("refusing: 0 peers")
        return 2
    if len(set(peers)) != len(peers) or sid in peers:
        log("refusing: duplicate peer or own id in --peer")
        return 2
    my_nonce = args.nonce or os.urandom(NONCE_HEX_LEN // 2).hex()
    if not is_nonce_hex(my_nonce):
        log("refusing: --nonce must be 32 lowercase hex chars")
        return 2

    sock = None
    deadline = time.time() + 8.0
    last_err = None
    while time.time() < deadline:
        try:
            sock = socket.create_connection((args.host, args.port), timeout=args.timeout)
            break
        except (ConnectionRefusedError, OSError) as e:
            last_err = e
            time.sleep(0.2)
    if sock is None:
        log(f"cannot dial {args.host}:{args.port}: {last_err}")
        return 1
    w = Wire(sock, args.wire_log, sid)

    try:
        w.send(LEGACY_HELLO if args.fault == "legacy-hello" else HELLO)
        ok = w.recv()
        log(f"server replied {ok!r}")
        if ok != OK:
            log("server rejected HELLO")
            return 3
        w.send(f"FED_JOIN {sid} 1000")
        for pid in peers:
            if args.fault == "no-peer":
                break
            if args.fault == "legacy-peer":
                w.send(f"SECAGG_PEER {pid} {args.token}")
            else:
                w.send(f"SECAGG_PEER {pid}")
        if args.fault == "dh-public":
            w.send(f"FED_DH_PUBLIC {sid} " + "ab" * 32)
        if args.fault != "no-nonce":
            w.send(f"SECAGG_NONCE {sid} {my_nonce}")
        w.send("ACK 0")
        # Relay drain: SECAGG_NONCE lines for declared peers until ACK 0.
        peer_nonces = {}
        while True:
            line = w.recv()
            if line is None:
                log("refusing: coordinator closed during the relay phase")
                return 2
            if line == "ACK 0":
                break
            parts = line.split(" ")
            if (len(parts) == 3 and parts[0] == "SECAGG_NONCE" and parts[1] in peers
                    and is_nonce_hex(parts[2]) and parts[1] not in peer_nonces):
                peer_nonces[parts[1]] = parts[2]
                continue
            log(f"refusing: unexpected relay line {line!r}")
            return 2
        missing = [pid for pid in peers if pid not in peer_nonces]
        if missing:
            log(f"refusing: missing nonce for {missing[0]}")
            return 2
        log(f"relay complete: {len(peer_nonces)} peer nonce(s)")
        if args.mode == "dropout":
            log("DROPOUT mode -- closing after handshake + relay")
            return 0
        rnd = w.recv()
        log(f"round line {rnd!r}")
        parts = (rnd or "").split(" ")
        if len(parts) != 3 or parts[0] != "FED_ROUND" or not parts[1].isdigit() or int(parts[1]) <= 0:
            log("refusing: malformed FED_ROUND line")
            return 2
        rid = int(parts[1])
        try:
            mp = apply_masks(sid, args.x_promo, 0, peers, args.token, my_nonce,
                             peer_nonces, rid, args.tag)
            ma = apply_masks(sid, args.x_atr, 1, peers, args.token, my_nonce,
                             peer_nonces, rid, args.tag)
        except Refused as e:
            log(f"refusing to mask: {e}")
            return 2
        w.send(f"FED_STAT_MASKED {rid} {args.tag} {mp} {ma}")
        if args.fault == "leave-after-stat":
            # Test fault: send the masked stat, then FED_LEAVE instead of
            # ACK, and go away (the coordinator must treat this as a dropout).
            w.send(f"FED_LEAVE {sid}")
            return 0
        w.send(f"ACK {rid}")
        last_mp, last_ma = mp, ma
        reconciled = []
        allow_recon = os.environ.get("CE_SECAGG_ALLOW_RECON") == "1"
        while True:
            line = w.recv()
            if line is None:
                break
            log(f"recv {line!r}")
            if line.startswith("FED_AGGREGATE_SUM "):
                break
            if line.startswith("FED_DROPOUT "):
                dparts = line.split(" ")
                if len(dparts) != 3 or dparts[1] != str(rid):
                    log("refusing reconciliation: malformed FED_DROPOUT")
                    break
                dropped_id = dparts[2]
                if not allow_recon:
                    log("refusing reconciliation (CE_SECAGG_ALLOW_RECON not set); abandoning round")
                    break
                # Same limits as fed_agg_emit_recon_masked: no duplicates,
                # only known peers, and never strip the last remaining mask.
                if (dropped_id in reconciled or dropped_id not in peers
                        or len(peers) - len(reconciled) - 1 < 1):
                    log(f"refusing reconciliation for {dropped_id} (limits); abandoning round")
                    break
                reconciled.append(dropped_id)
                adj_p = reconcile_for_dropped(sid, last_mp, dropped_id, 0, args.token,
                                              my_nonce, peer_nonces, rid, args.tag)
                adj_a = reconcile_for_dropped(sid, last_ma, dropped_id, 1, args.token,
                                              my_nonce, peer_nonces, rid, args.tag)
                w.send(f"FED_RECON_MASKED {rid} {sid} {args.tag} {adj_p} {adj_a}")
                w.send(f"ACK {rid}")
                last_mp, last_ma = adj_p, adj_a
                continue
            if line.startswith("BYE"):
                log("BYE before FED_AGGREGATE_SUM: round aborted")
                break
    finally:
        try:
            sock.close()
        except Exception:
            pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
