#!/usr/bin/env python3
"""Minimal fed-coordinator smoke client.

Connects to a CrossEngin fed-coordinator over TCP, performs the v1
handshake (HELLO ce-fed v1 + FED_JOIN <soul_id> <epsilon_milli>), then
closes. The coordinator, with CE_FED_MAX_ROUNDS=1, will open one round,
discover the soul went away mid-stream (collect_stats sees EOF, marks fd
inactive), then exit when active_count drops to 0.

Used by `make smoke-windows-ce` to drive the fed-coord under Wine.
"""

import socket
import sys
import time


def main(host: str, port: int) -> int:
    deadline = time.time() + 8.0
    last_err = None
    sock = None
    while time.time() < deadline:
        try:
            sock = socket.create_connection((host, port), timeout=5.0)
            break
        except (ConnectionRefusedError, OSError) as e:
            last_err = e
            time.sleep(0.3)
    if sock is None:
        sys.stderr.write(f"fed_smoke_client: cannot dial {host}:{port}: {last_err}\n")
        return 1

    try:
        sock.sendall(b"HELLO ce-fed v1\n")
        # Try to read the OK line; the coordinator responds with
        # "OK ce-fed v1 protocol accepted\n" before expecting FED_JOIN.
        sock.settimeout(5.0)
        try:
            ok = sock.recv(256)
        except socket.timeout:
            ok = b""
        sys.stderr.write(f"fed_smoke_client: server replied {ok!r}\n")
        # Send FED_JOIN regardless -- the coord parses the line and
        # builds a soul record. soul_id is opaque to the wire format.
        sock.sendall(b"FED_JOIN smoke 1000\n")
        # Drain one more line (the FED_ROUND broadcast); then close.
        sock.settimeout(5.0)
        try:
            rnd = sock.recv(256)
            sys.stderr.write(f"fed_smoke_client: round line {rnd!r}\n")
        except socket.timeout:
            pass
    finally:
        try:
            sock.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        sock.close()
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.stderr.write("usage: fed_smoke_client.py HOST PORT\n")
        sys.exit(2)
    sys.exit(main(sys.argv[1], int(sys.argv[2])))
