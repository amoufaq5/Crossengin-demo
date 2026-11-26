#!/usr/bin/env python3
"""Independent reference soul for SecAgg v4, protocol v4-sa3 (stdlib only).

A second implementation of the v4 soul, written from the wire and protocol
definitions, used to cross-check the NOVA code byte for byte. It mirrors
src/learning/{sa4_wire,sa4_soul,sa_crypto,sa_roster}.nova and
src/safety/{gf256,shamir,saprg,rng (test backend),ed25519,x25519}.nova
with its own primitives (Ed25519, X25519, ChaCha20-Poly1305, HKDF-SHA256,
the ChaCha20 PRG and GF(256) Shamir on Python integers and hashlib/hmac),
plus a Python oracle of the coordinator (Coord, coord_verdicts,
coord_rebuild) and the standalone evidence judge.

It is a test reference, not a production soul: Python cannot wipe secret
bytes, and its PRG is slow for long vectors.

    sa4_ref.py --selftest              RFC / FIPS vectors, the repo's KATs, the
                                       v4-sa3 vectors (SPEC A2.4c section 15)
                                       and the blame scenarios
    sa4_ref.py --dump X                print this implementation's transcript
                                       of a tests/sa4_harness.nova scenario:
                                       A..D (souls only), E (refusals),
                                       F G H I J P K L (souls + coordinator:
                                       ADV / OUT lines, BLAME and EVIDENCE)
    sa4_ref.py --harness X DUMPFILE    compare it with the NOVA transcript
                                       (tests/tools/sa4_dump.nova output)
    sa4_ref.py --judge FILE [--roster R]
                                       standalone judge of an evidence file
                                       (roster default CE_SECAGG_ROSTER):
                                       'verdict: sender <u>' / 'verdict:
                                       complainer <v>' (exit 0) or
                                       'invalid: <why>' (exit 2)
    sa4_ref.py --connect HOST:PORT --tags T1,T2 [--x TAG=PROMO:ATR,...]
               [--state FILE] [--fault F[,F..]] [--timeout SEC]
                                       live soul against a v4 fed coordinator
                                       (A2.3c). Roster and identity seed from
                                       CE_SECAGG_ROSTER / CE_SECAGG_ID_KEY.
                                       Faults (tests; several comma-separated):
                                       stop-after-adv, stop-after-shares,
                                       stop-after-check (leaves after its
                                       END 4: in U2, never sends Y),
                                       stop-after-y, stop-after-sig3,
                                       bad-adv-sig, bad-sig3, swap-reveal,
                                       silent, drip, bad-b-reveal /
                                       bad-s-reveal (the first b / s REVEAL's
                                       share altered, proof kept),
                                       inconsistent-deal (the b-share of the
                                       lowest other x is altered before the
                                       tree is built -> dealer blamed at
                                       rebuild). v4-sa3, aimed at the lowest
                                       other x in U1: bad-share-open (= the
                                       A2.3c bad-share: ct := garbage(ct)),
                                       bad-share-fields (x_to := x_to mod N
                                       + 1), bad-commit-share (b-share that
                                       does not match M_u), low-epk (e_pk :=
                                       a low-order point), foreign-e (seal
                                       under e' = H("prepared" || e), send
                                       X25519_base(e), reveal e'). Others:
                                       false-complaint (complain about the
                                       lowest other sender's valid share),
                                       complain-all, no-open (answer ACCUSE
                                       with END 5 0), silent-check (leave
                                       after SET 5 without answering),
                                       bad-shsig (byte 0 of SHSIG flipped).
    sa4_ref.py --pins [FILE]           print (and write) the known answers:
                                       v4-sa2 tree KATs, transcripts (v3 SIG
                                       domain), v4-sa3 K1..K9, rounds F-J, P.

v4-sa2 (verifiable shares): each dealer signs B_u = H(b_u) and the Merkle
root M_u over per-x leaves H(0 || hs_x || hb_x) in its ADV; each share
carries its authentication path; each REVEAL carries other-hash || path.
coord_rebuild() is a Python oracle of the coordinator's lazy robust rebuild
(excluded revealers, blamed dealer).

v4-sa3 (verifiable blame, A2.4c): every share is sealed under a one-time
X25519 key e_uv (eseed = the last rng draw of R0; SA4_SHARE carries e_pk),
the sender signs the share root over (e_pk, ct) leaves and H1 (SA4_SHSIG),
receivers check in a CHECK phase (SA4_SET 5) and complain with a signed
SA4_COMPLAINT instead of aborting, the accused reveals e_uv (SA4_OPEN) only
for a valid complaint about the exact line it sent (SA4_ACCUSE), and the
coordinator judges lazily before the final SA4_SET 2: blame codes 1..5,
evidence text for codes 1 / 2 (judge_evidence).

Scenarios: A N=3 honest; B N=5, one soul in U2 but not U3; C N=4, one soul
drops after its ADV; D N=5, one soul in U3 but not U4; E 21 refusals;
F..J, P blame rounds (N=5, r=13): F code 1, G code 2, H code 3, I code 5,
J code 4, P plain; K, L as F, G with 70000 in U1 but not in U2' (the
evidence covers U1; the round then cancels).
"""
import hashlib
import hmac
import os
import stat
import sys

# ============================================================ primitives
M32 = 0xFFFFFFFF


def sha256(b):
    return hashlib.sha256(b).digest()


# ---- GF(2^8) / Shamir (src/safety/gf256.nova, shamir.nova)
def gf_mul(a, b):
    a &= 255
    b &= 255
    r = 0
    for _ in range(8):
        r ^= a & ((0 - (b & 1)) & 255)
        hm = (0 - ((a >> 7) & 1)) & 255
        a = ((a << 1) & 255) ^ (0x1B & hm)
        b >>= 1
    return r


def gf_inv(a):
    t = gf_mul(a, a)
    t = gf_mul(t, a)
    for _ in range(5):
        t = gf_mul(t, t)
        t = gf_mul(t, a)
    return gf_mul(t, t)          # a^254


def shamir_split_coeffs(secret, t, n, coeffs):
    """coeffs: (t-1)*len(secret) bytes, c_1 first (shamir.nova layout)."""
    sl = len(secret)
    out = []
    for x in range(1, n + 1):
        y = bytearray(sl)
        for j in range(sl):
            acc = 0
            for k in range(t - 1, 0, -1):
                acc = gf_mul(acc, x) ^ coeffs[(k - 1) * sl + j]
            y[j] = gf_mul(acc, x) ^ secret[j]
        out.append((x, bytes(y)))
    return out


def shamir_split(rng, secret, t, n):
    return shamir_split_coeffs(secret, t, n, rng.read((t - 1) * len(secret)))


def lagrange0(xs):
    lam = []
    for i, xi in enumerate(xs):
        num = den = 1
        for m, xm in enumerate(xs):
            if m != i:
                num = gf_mul(num, xm)
                den = gf_mul(den, xm ^ xi)
        lam.append(gf_mul(num, gf_inv(den)))
    return lam


def shamir_combine(shares, slen):
    xs = [x for x, _ in shares]
    if slen < 1 or not shares or len(shares) > 255 or len(set(xs)) != len(xs):
        return None
    if any(x < 1 or x > 255 or len(y) != slen for x, y in shares):
        return None
    lam = lagrange0(xs)
    out = bytearray(slen)
    for l, (_, y) in zip(lam, shares):
        for j in range(slen):
            out[j] ^= gf_mul(l, y[j])
    return bytes(out)


# ---- ChaCha20 / Poly1305 / AEAD (RFC 8439)
def _rotl(v, c):
    return ((v << c) & M32) | (v >> (32 - c))


def _qr(s, a, b, c, d):
    s[a] = (s[a] + s[b]) & M32; s[d] = _rotl(s[d] ^ s[a], 16)
    s[c] = (s[c] + s[d]) & M32; s[b] = _rotl(s[b] ^ s[c], 12)
    s[a] = (s[a] + s[b]) & M32; s[d] = _rotl(s[d] ^ s[a], 8)
    s[c] = (s[c] + s[d]) & M32; s[b] = _rotl(s[b] ^ s[c], 7)


def chacha_words(key, ctr, nonce):
    st = [0x61707865, 0x3320646E, 0x79622D32, 0x6B206574]
    st += [int.from_bytes(key[i:i + 4], "little") for i in range(0, 32, 4)]
    st += [ctr & M32] + [int.from_bytes(nonce[i:i + 4], "little") for i in range(0, 12, 4)]
    w = st[:]
    for _ in range(10):
        _qr(w, 0, 4, 8, 12); _qr(w, 1, 5, 9, 13); _qr(w, 2, 6, 10, 14); _qr(w, 3, 7, 11, 15)
        _qr(w, 0, 5, 10, 15); _qr(w, 1, 6, 11, 12); _qr(w, 2, 7, 8, 13); _qr(w, 3, 4, 9, 14)
    return [(w[i] + st[i]) & M32 for i in range(16)]


def chacha_block(key, ctr, nonce):
    return b"".join(v.to_bytes(4, "little") for v in chacha_words(key, ctr, nonce))


def chacha_xor(key, ctr, nonce, data):
    out = bytearray()
    for i in range(0, len(data), 64):
        ks = chacha_block(key, ctr + i // 64, nonce)
        out += bytes(a ^ b for a, b in zip(data[i:i + 64], ks))
    return bytes(out)


def poly1305(key, msg):
    r = int.from_bytes(key[:16], "little") & 0x0FFFFFFC0FFFFFFC0FFFFFFC0FFFFFFF
    s = int.from_bytes(key[16:32], "little")
    p = (1 << 130) - 5
    acc = 0
    for i in range(0, len(msg), 16):
        acc = (acc + int.from_bytes(msg[i:i + 16] + b"\x01", "little")) * r % p
    return ((acc + s) & ((1 << 128) - 1)).to_bytes(16, "little")


def _pad16(b):
    return b"\0" * ((16 - len(b) % 16) % 16)


def _aead_mac_data(aad, ct):
    return aad + _pad16(aad) + ct + _pad16(ct) + len(aad).to_bytes(8, "little") + len(ct).to_bytes(8, "little")


def aead_seal(key, nonce, aad, pt):
    ct = chacha_xor(key, 1, nonce, pt)
    return ct + poly1305(chacha_block(key, 0, nonce)[:32], _aead_mac_data(aad, ct))


def aead_open(key, nonce, aad, wire):
    if len(wire) < 16:
        return None
    ct, tag = wire[:-16], wire[-16:]
    if not hmac.compare_digest(poly1305(chacha_block(key, 0, nonce)[:32], _aead_mac_data(aad, ct)), tag):
        return None
    return chacha_xor(key, 1, nonce, ct)


# ---- PRG (src/safety/saprg.nova)
def saprg_expand(seed, n):
    out = []
    ctr = 0
    while len(out) < n:
        out += chacha_words(seed, ctr, bytes(12))
        ctr += 1
    return out[:n]


def saprg_mask(x, seed, sign):
    m = saprg_expand(seed, len(x))
    if sign < 0:
        return [(a - b) & M32 for a, b in zip(x, m)]
    return [(a + b) & M32 for a, b in zip(x, m)]


# ---- deterministic RNG = rng_test_new (src/safety/rng.nova)
class TestRng:
    """ChaCha20(key=SHA-256(seed), nonce=0^12, ctr=0,1,..) as one byte stream."""
    def __init__(self, seed):
        self.key = sha256(seed)
        self.ctr = 0
        self.buf = b""

    def read(self, n):
        while len(self.buf) < n:
            self.buf += chacha_block(self.key, self.ctr, bytes(12))
            self.ctr += 1
        out, self.buf = self.buf[:n], self.buf[n:]
        return out


class OsRng:
    def read(self, n):
        b = os.urandom(n)
        if len(b) != n:
            raise OSError("short urandom")
        return b


# ---- HKDF-SHA256 (RFC 5869), salt empty == 32 zero bytes
def hkdf(salt, ikm, info, n):
    prk = hmac.new(salt if salt else bytes(32), ikm, hashlib.sha256).digest()
    out, t, i = b"", b"", 1
    while len(out) < n:
        t = hmac.new(prk, t + info + bytes([i]), hashlib.sha256).digest()
        out += t
        i += 1
    return out[:n]


# ---- X25519 (RFC 7748)
P = 2 ** 255 - 19


def x25519(k, u):
    kb = bytearray(k)
    kb[0] &= 248; kb[31] &= 127; kb[31] |= 64
    kk = int.from_bytes(kb, "little")
    x1 = int.from_bytes(u, "little") & ((1 << 255) - 1)
    x2, z2, x3, z3, swap = 1, 0, x1, 1, 0
    for t in range(254, -1, -1):
        kt = (kk >> t) & 1
        swap ^= kt
        if swap:
            x2, x3, z2, z3 = x3, x2, z3, z2
        swap = kt
        A = (x2 + z2) % P; AA = A * A % P; B = (x2 - z2) % P; BB = B * B % P; E = (AA - BB) % P
        C = (x3 + z3) % P; D = (x3 - z3) % P; DA = D * A % P; CB = C * B % P
        x3 = (DA + CB) ** 2 % P; z3 = x1 * (DA - CB) ** 2 % P
        x2 = AA * BB % P; z2 = E * (AA + 121665 * E) % P
    if swap:
        x2, x3, z2, z3 = x3, x2, z3, z2
    return (x2 * pow(z2, P - 2, P) % P).to_bytes(32, "little")


def x25519_base(k):
    return x25519(k, (9).to_bytes(32, "little"))


# ---- Ed25519 (RFC 8032), extended coordinates
ED_D = -121665 * pow(121666, P - 2, P) % P
ED_L = 2 ** 252 + 27742317777372353535851937790883648493
SQRT_M1 = pow(2, (P - 1) // 4, P)


def _pt_add(p1, p2):
    X1, Y1, Z1, T1 = p1; X2, Y2, Z2, T2 = p2
    A = (Y1 - X1) * (Y2 - X2) % P; B = (Y1 + X1) * (Y2 + X2) % P
    C = 2 * T1 * T2 * ED_D % P; D = 2 * Z1 * Z2 % P
    E, F, G, H = B - A, D - C, D + C, B + A
    return (E * F % P, G * H % P, F * G % P, E * H % P)


def _pt_mul(k, pt):
    q = (0, 1, 1, 0)
    while k:
        if k & 1:
            q = _pt_add(q, pt)
        pt = _pt_add(pt, pt)
        k >>= 1
    return q


def _pt_enc(pt):
    X, Y, Z, _ = pt
    zi = pow(Z, P - 2, P)
    x, y = X * zi % P, Y * zi % P
    return (y | ((x & 1) << 255)).to_bytes(32, "little")


def _pt_dec(b):
    """RFC 8032 5.1.3 as _ed_point_decode: reject y >= p, non-square, -0."""
    if len(b) != 32:
        return None
    sign = b[31] >> 7
    y = int.from_bytes(b, "little") & ((1 << 255) - 1)
    if y >= P:
        return None
    u = (y * y - 1) % P
    v = (ED_D * y * y + 1) % P
    x = u * pow(v, 3, P) * pow(u * pow(v, 7, P), (P - 5) // 8, P) % P
    if (x * x * v - u) % P:
        x = x * SQRT_M1 % P
        if (x * x * v - u) % P:
            return None
    if x == 0 and sign:
        return None
    if (x & 1) != sign:
        x = P - x
    return (x, y, 1, x * y % P)


_ED_BY = 4 * pow(5, P - 2, P) % P
ED_B = _pt_dec(_ED_BY.to_bytes(32, "little"))
_IDENT_ENC = (1).to_bytes(32, "little")


def ed25519_pk_from_seed(seed):
    h = bytearray(hashlib.sha512(seed).digest()[:32])
    h[0] &= 248; h[31] &= 127; h[31] |= 64
    return _pt_enc(_pt_mul(int.from_bytes(h, "little"), ED_B))


def ed25519_sign(msg, seed, pk):
    h = hashlib.sha512(seed).digest()
    a = bytearray(h[:32]); a[0] &= 248; a[31] &= 127; a[31] |= 64
    a = int.from_bytes(a, "little")
    r = int.from_bytes(hashlib.sha512(h[32:] + msg).digest(), "little") % ED_L
    R = _pt_enc(_pt_mul(r, ED_B))
    k = int.from_bytes(hashlib.sha512(R + pk + msg).digest(), "little") % ED_L
    return R + ((r + k * a) % ED_L).to_bytes(32, "little")


def ed25519_verify(msg, sig, pk):
    """Cofactorless [s]B == R + [k]A, s < L, canonical A and R (as NOVA)."""
    if len(sig) != 64 or len(pk) != 32:
        return False
    s = int.from_bytes(sig[32:], "little")
    if s >= ED_L:
        return False
    A = _pt_dec(pk)
    R = _pt_dec(sig[:32])
    if A is None or R is None:
        return False
    k = int.from_bytes(hashlib.sha512(sig[:32] + pk + msg).digest(), "little") % ED_L
    return _pt_enc(_pt_mul(s, ED_B)) == _pt_enc(_pt_add(R, _pt_mul(k, A)))


def ed25519_pk_check(pk):
    p = _pt_dec(pk)
    if p is None:
        return False
    for _ in range(3):
        p = _pt_add(p, p)
    return _pt_enc(p) != _IDENT_ENC


# ============================================================ sa_crypto
SAC_DOMAIN = b"crossengin/v4-sa/v1"
SAC_SHARE_AAD = b"crossengin/v4-sa/v1/share"


def be(v, n):
    return v.to_bytes(n, "big")


def kdf_info(purpose, r, a, b):
    return SAC_DOMAIN + bytes([len(purpose)]) + purpose + be(r, 8) + be(a, 4) + be(b, 4)


def agree(sk, peer_pk, purpose, r, a, b):
    shared = x25519(sk, peer_pk)
    if shared == bytes(32):
        return None
    return hkdf(b"", shared, kdf_info(purpose, r, a, b), 32)


def mask_seed(s_sk, peer_s_pk, r, me, peer):
    if me == peer:
        return None
    return agree(s_sk, peer_s_pk, b"mask", r, min(me, peer), max(me, peer))


def enc_key(c_sk, peer_c_pk, r, sender, receiver):
    if sender == receiver:
        return None
    return agree(c_sk, peer_c_pk, b"enc", r, sender, receiver)


def share_aad(r, sender, receiver):
    return SAC_SHARE_AAD + be(r, 8) + be(sender, 4) + be(receiver, 4)


def share_seal(key, r, s, v, pt):
    return aead_seal(key, bytes(12), share_aad(r, s, v), pt)


def share_open(key, r, s, v, wire):
    return aead_open(key, bytes(12), share_aad(r, s, v), wire)


# ============================================================ roster
ROSTER_HEADER = "crossengin-secagg-roster v1"


def threshold(n):
    return max(2 * n // 3 + 1, n // 2 + 1)


class Roster:
    def __init__(self, entries):
        self.entries = entries          # list of (id, name, pk bytes, pk hex, x)
        self.n = len(entries)
        self.t = threshold(self.n)
        self.canon = ROSTER_HEADER + "\n" + "".join("%d %s %s\n" % (e[0], e[1], e[3]) for e in entries)
        self.fp = sha256(self.canon.encode("ascii"))
        self.by_id = {e[0]: e for e in entries}

    def x(self, i):
        e = self.by_id.get(i)
        return e[4] if e else 0


def _dec_ok(s, maxlen):
    return 1 <= len(s) <= maxlen and s.isascii() and s.isdigit() and not (len(s) > 1 and s[0] == "0")


def roster_parse(text):
    """sroster_parse; raises ValueError with the NOVA-style reason."""
    if len(text) > 65536:
        raise ValueError("file larger than 64 KiB")
    for i, c in enumerate(text):
        o = ord(c)
        if not (32 <= o <= 126 or o == 10 or (o == 13 and i + 1 < len(text) and text[i + 1] == "\n")):
            raise ValueError("non-printable character")
    entries, seen_header, prev = [], False, -1
    for li, raw in enumerate(text.split("\n")):
        if len(raw) > 1024:
            raise ValueError("line %d: longer than 1024 bytes" % (li + 1))
        line = raw[:-1] if raw.endswith("\r") else raw
        line = line.strip(" ")
        if not line or line[0] == "#":
            continue
        if not seen_header:
            if line != ROSTER_HEADER:
                raise ValueError("line %d: expected header" % (li + 1))
            seen_header = True
            continue
        f = [x for x in line.split(" ") if x]
        if len(f) != 3:
            raise ValueError("line %d: expected '<id> <name> <public key>'" % (li + 1))
        if not _dec_ok(f[0], 10) or int(f[0]) > M32:
            raise ValueError("line %d: bad id" % (li + 1))
        i = int(f[0])
        if i <= prev:
            raise ValueError("line %d: ids must be strictly ascending" % (li + 1))
        if not (1 <= len(f[1]) <= 64 and all(c.isascii() and (c.isalnum() or c in "_-") for c in f[1])):
            raise ValueError("line %d: bad name" % (li + 1))
        if len(f[2]) != 64 or any(c not in "0123456789abcdef" for c in f[2]):
            raise ValueError("line %d: bad public key" % (li + 1))
        if len(entries) >= 255:
            raise ValueError("line %d: more than 255 souls" % (li + 1))
        if any(e[1] == f[1] for e in entries):
            raise ValueError("line %d: duplicate name" % (li + 1))
        if any(e[3] == f[2] for e in entries):
            raise ValueError("line %d: duplicate public key" % (li + 1))
        pk = bytes.fromhex(f[2])
        if not ed25519_pk_check(pk):
            raise ValueError("line %d: public key is not a valid Ed25519 key" % (li + 1))
        entries.append((i, f[1], pk, f[2], len(entries) + 1))
        prev = i
    if not seen_header:
        raise ValueError("missing header")
    if len(entries) < 2:
        raise ValueError("needs at least 2 souls")
    return Roster(entries)


def _open_checked(path, private):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    st = os.fstat(fd)
    if not stat.S_ISREG(st.st_mode):
        os.close(fd); raise ValueError(path + ": not a regular file")
    if private:
        if st.st_uid != os.geteuid() or st.st_mode & 0o77:
            os.close(fd); raise ValueError(path + ": must be owned by you, mode 600")
    elif st.st_uid not in (os.geteuid(), 0) or st.st_mode & 0o22:
        os.close(fd); raise ValueError(path + ": bad owner or writable by group/others")
    return fd


def roster_load(path):
    fd = _open_checked(path, False)
    with os.fdopen(fd, "rb") as fh:
        data = fh.read(65537)
    if len(data) > 65536 or b"\0" in data:
        raise ValueError("roster too large or contains NUL")
    return roster_parse(data.decode("latin-1"))


def seed_load(path):
    fd = _open_checked(path, True)
    with os.fdopen(fd, "rb") as fh:
        data = fh.read(33)
    if len(data) != 32:
        raise ValueError("identity: must be exactly 32 bytes")
    return data


# ============================================================ wire
EV_ROUND, EV_ADV, EV_SET, EV_SHARE, EV_Y, EV_SIG3, EV_REVEAL, EV_END, EV_ABORT = range(40, 49)
EV_SHSIG, EV_COMPLAINT, EV_ACCUSE, EV_OPEN = 49, 50, 51, 52        # v4-sa3
PHASE_CHECK, PHASE_OPEN = 4, 5                                      # SA4_END phases


def _unhex(s, n):
    if len(s) != 2 * n or any(c not in "0123456789abcdef" for c in s):
        return None
    return bytes.fromhex(s)


def _u32(s):
    return int(s) if _dec_ok(s, 10) and int(s) <= M32 else -1


def _round(s):
    return int(s) if _dec_ok(s, 19) and int(s) <= 2 ** 62 - 1 else -1


def _tokens(line):
    if not (1 <= len(line) <= 1000):
        return None
    if any(not (33 <= ord(c) <= 126) and c != " " for c in line):
        return None
    t = line.split(" ")
    if any(x == "" for x in t):
        return None
    return t


def parse(line):
    """sa4w_parse -> tuple (ev, r, ...) or None (v4-sa3 grammar)."""
    t = _tokens(line)
    if t is None or len(t) < 2:
        return None
    r = _round(t[1])
    if r < 0:
        return None
    k, n = t[0], len(t)
    if k == "SA4_ROUND" and n == 5:
        fp, lw, lay = _unhex(t[2], 32), _u32(t[3]), _unhex(t[4], 32)
        if fp is None or lay is None or not (1 <= lw <= 16777216):
            return None
        return (EV_ROUND, r, fp, lw, lay)
    if k == "SA4_ADV" and n == 8:
        i, c, s = _u32(t[2]), _unhex(t[3], 32), _unhex(t[4], 32)
        bc, mr, g = _unhex(t[5], 32), _unhex(t[6], 32), _unhex(t[7], 64)
        if i < 0 or None in (c, s, bc, mr, g):
            return None
        return (EV_ADV, r, i, c, s, g, bc, mr)
    if k == "SA4_SET" and n == 4:
        w, bm = _u32(t[2]), _unhex(t[3], 32)
        if not (1 <= w <= 5) or bm is None:
            return None
        return (EV_SET, r, w, bm)
    if k == "SA4_SHARE" and n == 6:
        # v4-sa3: SA4_SHARE r from to epk64 ct; record [43, r, from, to, ct, epk]
        hl = len(t[5])
        ct = _unhex(t[5], hl // 2) if hl % 64 == 4 and 1 <= (hl // 2 - 98) // 32 <= 8 else None
        f, to, epk = _u32(t[2]), _u32(t[3]), _unhex(t[4], 32)
        if f < 0 or to < 0 or ct is None or epk is None:
            return None
        return (EV_SHARE, r, f, to, ct, epk)
    if k == "SA4_SHSIG" and n == 4:
        f, g = _u32(t[2]), _unhex(t[3], 64)
        if f < 0 or g is None:
            return None
        return (EV_SHSIG, r, f, g)
    if k == "SA4_COMPLAINT" and n == 6:
        f, a, lh, g = _u32(t[2]), _u32(t[3]), _unhex(t[4], 32), _unhex(t[5], 64)
        if f < 0 or a < 0 or lh is None or g is None:
            return None
        return (EV_COMPLAINT, r, f, a, lh, g)
    if k == "SA4_ACCUSE" and n == 3:
        bm = _unhex(t[2], 32)
        if bm is None:
            return None
        return (EV_ACCUSE, r, bm)
    if k == "SA4_OPEN" and n == 5:
        f, a, e = _u32(t[2]), _u32(t[3]), _unhex(t[4], 32)
        if f < 0 or a < 0 or e is None:
            return None
        return (EV_OPEN, r, f, a, e)
    if k == "SA4_Y" and n == 6:
        f, ci, cn, hx = _u32(t[2]), _u32(t[3]), _u32(t[4]), t[5]
        if f < 0 or ci < 0 or cn < 1 or ci >= cn or not (8 <= len(hx) <= 800) or len(hx) % 8:
            return None
        b = _unhex(hx, len(hx) // 2)
        if b is None:
            return None
        return (EV_Y, r, f, ci, cn, [int.from_bytes(b[j:j + 4], "big") for j in range(0, len(b), 4)])
    if k == "SA4_SIG3" and n == 4:
        i, g = _u32(t[2]), _unhex(t[3], 64)
        if i < 0 or g is None:
            return None
        return (EV_SIG3, r, i, g)
    if k == "SA4_REVEAL" and n == 7:
        f, a = _u32(t[2]), _u32(t[3])
        kind = {"b": 0, "s": 1}.get(t[4], -1)
        sh = _unhex(t[5], 32)
        pl = len(t[6])
        pf = _unhex(t[6], pl // 2) if pl % 64 == 0 and 2 <= pl // 64 <= 9 else None
        if f < 0 or a < 0 or kind < 0 or sh is None or pf is None:
            return None
        return (EV_REVEAL, r, f, a, kind, sh, pf)
    if k == "SA4_END" and n == 5:
        ph, i, c = _u32(t[2]), _u32(t[3]), _u32(t[4])
        if not (1 <= ph <= 5) or i < 0 or c < 0:
            return None
        return (EV_END, r, ph, i, c)
    if k == "SA4_ABORT" and n == 4:
        i = _u32(t[2])
        c = t[3]
        if i < 0 or not (1 <= len(c) <= 32) or any(ch not in "abcdefghijklmnopqrstuvwxyz0123456789_" for ch in c):
            return None
        return (EV_ABORT, r, i, c)
    return None


def fmt_round(r, fp, lw, lay): return "SA4_ROUND %d %s %d %s" % (r, fp.hex(), lw, lay.hex())
def fmt_adv(r, i, c, s, g, bc, mr): return "SA4_ADV %d %d %s %s %s %s %s" % (r, i, c.hex(), s.hex(), bc.hex(), mr.hex(), g.hex())
def fmt_set(r, k, bm): return "SA4_SET %d %d %s" % (r, k, bm.hex())
def fmt_share(r, f, to, ct, epk): return "SA4_SHARE %d %d %d %s %s" % (r, f, to, epk.hex(), ct.hex())
def fmt_shsig(r, f, g): return "SA4_SHSIG %d %d %s" % (r, f, g.hex())
def fmt_complaint(r, f, a, lh, g): return "SA4_COMPLAINT %d %d %d %s %s" % (r, f, a, lh.hex(), g.hex())
def fmt_accuse(r, bm): return "SA4_ACCUSE %d %s" % (r, bm.hex())
def fmt_open(r, f, a, e): return "SA4_OPEN %d %d %d %s" % (r, f, a, e.hex())
def fmt_sig3(r, i, g): return "SA4_SIG3 %d %d %s" % (r, i, g.hex())
def fmt_reveal(r, f, a, kind, sh, pf): return "SA4_REVEAL %d %d %d %s %s %s" % (r, f, a, "s" if kind == 1 else "b", sh.hex(), pf.hex())
def fmt_end(r, ph, i, c): return "SA4_END %d %d %d %d" % (r, ph, i, c)
def fmt_abort(r, i, code): return "SA4_ABORT %d %d %s" % (r, i, code)


def fmt_y_lines(r, f, words):
    cn = (len(words) + 99) // 100
    return ["SA4_Y %d %d %d %d %s" % (r, f, ci, cn, "".join("%08x" % w for w in words[ci * 100:ci * 100 + 100]))
            for ci in range(cn)]


def bitmap(xs):
    bm = bytearray(32)
    for x in xs:
        bm[(x - 1) >> 3] |= 1 << ((x - 1) & 7)
    return bytes(bm)


def bitmap_xs(bm, n):
    out = []
    for x in range(1, 257):
        if (bm[(x - 1) >> 3] >> ((x - 1) & 7)) & 1:
            if x > n:
                return None
            out.append(x)
    return out


SIG_DOMAIN = b"crossengin/v4-sa/v3/sig"           # v4-sa3 (was v2)
ADVSET_DOMAIN = b"crossengin/v4-sa/v2/advset"
BCOMMIT_DOMAIN = b"crossengin/v4-sa/v2/bcommit"
BSHARE_DOMAIN = b"crossengin/v4-sa/v2/bshare"
SSHARE_DOMAIN = b"crossengin/v4-sa/v2/sshare"
SHARE_PT_VERSION = 2


def sig_prefix(tag, fp, r):
    return SIG_DOMAIN + bytes([len(tag)]) + tag + fp + be(r, 8)


def adv_transcript(fp, r, i, lw, lay, c, s, bc, mr):
    """SIGPFX("adv") || id || L || layout || c_pk || s_pk || B || M (235 bytes)."""
    return sig_prefix(b"adv", fp, r) + be(i, 4) + be(lw, 4) + lay + c + s + bc + mr


def advset_hash(bm_u1, keys):
    """H1; keys: (c_pk, s_pk, B, M) per soul of U1, ascending x."""
    return sha256(ADVSET_DOMAIN + bm_u1 + b"".join(b"".join(k) for k in keys))


def t3_transcript(fp, r, h1, bm2, bm3):
    return sig_prefix(b"u3", fp, r) + h1 + bm2 + bm3


# ---- commitments (v4-sa2): B_u, per-x share hashes, Merkle tree M_u
def depth(n):
    """D(N) = max(1, ceil(log2 N))."""
    return max(1, (n - 1).bit_length())


def b_commit(fp, r, u, b):
    return sha256(BCOMMIT_DOMAIN + fp + be(r, 8) + be(u, 4) + b)


def h_bshare(fp, r, u, x, sh):
    return sha256(BSHARE_DOMAIN + fp + be(r, 8) + be(u, 4) + bytes([x]) + sh)


def h_sshare(fp, r, u, x, sh):
    return sha256(SSHARE_DOMAIN + fp + be(r, 8) + be(u, 4) + bytes([x]) + sh)


def leaf_hash(hs, hb):
    return sha256(b"\x00" + hs + hb)


def node_hash(left, right):
    return sha256(b"\x01" + left + right)


def tree_levels(leaves, d):
    """levels[0] = the 2^d leaves (padding = 32 zero bytes, not hashed),
    levels[d] = [root]."""
    lv = [list(leaves) + [bytes(32)] * ((1 << d) - len(leaves))]
    for _ in range(d):
        p = lv[-1]
        lv.append([node_hash(p[2 * j], p[2 * j + 1]) for j in range(len(p) // 2)])
    return lv


def tree_path(levels, i):
    """Authentication path of leaf index i: path[0] = sibling at the leaf level."""
    return [levels[k][(i >> k) ^ 1] for k in range(len(levels) - 1)]


def path_fold(leaf, i, path):
    h = leaf
    for node in path:
        h = node_hash(node, h) if i & 1 else node_hash(h, node)
        i >>= 1
    return h


def deal_tree(fp, r, u, ssh, bsh, d):
    """ssh / bsh: [(x, share)] for x = 1..N -> tree levels (root = M_u)."""
    leaves = [leaf_hash(h_sshare(fp, r, u, x, s), h_bshare(fp, r, u, x, b)) for (x, s), (_, b) in zip(ssh, bsh)]
    return tree_levels(leaves, d)


def share_leaf(fp, r, u, x, s, b):
    return leaf_hash(h_sshare(fp, r, u, x, s), h_bshare(fp, r, u, x, b))


def reveal_proof(fp, r, u, x, kind, s, b, path):
    """The proof a receiver at x sends with its kind-b (0) or kind-s (1) reveal."""
    other = h_sshare(fp, r, u, x, s) if kind == 0 else h_bshare(fp, r, u, x, b)
    return other + b"".join(path)


def reveal_proof_ok(fp, r, u, x, kind, share, proof, mroot, d):
    if len(proof) != 32 * (d + 1) or len(share) != 32 or not (1 <= x <= 255):
        return False
    other, path = proof[:32], [proof[32 * (k + 1):32 * (k + 2)] for k in range(d)]
    if kind == 0:
        leaf = leaf_hash(other, h_bshare(fp, r, u, x, share))
    else:
        leaf = leaf_hash(h_sshare(fp, r, u, x, share), other)
    return path_fold(leaf, x - 1, path) == mroot


def share_pt(f, to, r, x_to, s_sh, b_sh, path):
    return bytes([SHARE_PT_VERSION]) + be(f, 4) + be(to, 4) + be(r, 8) + bytes([x_to]) + s_sh + b_sh + b"".join(path)


def share_pt_parse(pt, d):
    """-> (from, to, r, x_to, s-share, b-share, [path]) or None (v2 only, 82 + 32 d bytes)."""
    if len(pt) != 82 + 32 * d or pt[0] != SHARE_PT_VERSION:
        return None
    return (int.from_bytes(pt[1:5], "big"), int.from_bytes(pt[5:9], "big"),
            int.from_bytes(pt[9:17], "big"), pt[17], pt[18:50], pt[50:82],
            [pt[82 + 32 * k:114 + 32 * k] for k in range(d)])


# ---- v4-sa3: one-time share keys, share tree, complaint transcripts
SLEAF_DOMAIN = b"crossengin/v4-sa/v3/sleaf"
GARBAGE_DOMAIN = b"crossengin/v4-sa/v3/test-garbage"
EVID_HEADER = "crossengin-sa4-evidence v1"
# The canonical u for which X25519 with any clamped scalar is zero (curve
# 8-torsion and twist 4-torsion), in the order of the spec (section 4).
LOW_ORDER = [bytes(32), (1).to_bytes(32, "little"),
             bytes.fromhex("e0eb7a7c3b41b8ae1656e3faf19fc46ada098deb9c32b1fd866205165f49b800"),
             bytes.fromhex("5f9c95bca3508c24b1d0b1559c83ef5b04445cc4581c8e86d8224eddd09f1157"),
             bytes.fromhex("ecffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f")]


def epk_ok(pk):
    """sa4w_epk_ok: 32 bytes, canonical (< p), not one of LOW_ORDER (no X25519)."""
    return len(pk) == 32 and int.from_bytes(pk, "little") < P and pk not in LOW_ORDER


def eph(eseed, r, u, v):
    """sac_eph_key: e_uv = HKDF(eseed_u, kdf_info("eph", r, u, v)); None for u == v."""
    if u == v or not (0 <= u <= M32) or not (0 <= v <= M32):
        return None
    return hkdf(b"", eseed, kdf_info(b"eph", r, u, v), 32)


def sleaf(fp, r, u, x, v, epk, ct):
    """sa4w_sleaf: H(0x00 || SLEAF || fp || r || u || u8 x || v || e_pk || ct)."""
    return sha256(b"\x00" + SLEAF_DOMAIN + fp + be(r, 8) + be(u, 4) + bytes([x]) + be(v, 4) + epk + ct)


def share_levels(n, d, leaves_by_x):
    """Share tree S_u over roster positions x = 1..N ({x: sleaf}, zero elsewhere)."""
    return tree_levels([leaves_by_x.get(x, bytes(32)) for x in range(1, n + 1)], d)


def shares_transcript(fp, r, u, h1, root):
    """T_sh = SIGPFX("shares") || u32be u || H1 || S_u (138 bytes)."""
    return sig_prefix(b"shares", fp, r) + be(u, 4) + h1 + root


def complaint_transcript(fp, r, v, u, h1, lh):
    """T_c = SIGPFX("complaint") || u32be v || u32be u || H1 || lh (145 bytes)."""
    return sig_prefix(b"complaint", fp, r) + be(v, 4) + be(u, 4) + h1 + lh


def share_check(fp, r, u, v, xv, d, key, ct, mroot):
    """sa4w_share_check -> (kind, (s, b, path) or None); kind "" = pass, else
    the first failing step: key, open, length, version, fields, commit."""
    if key is None:
        return ("key", None)
    pt = share_open(key, r, u, v, ct)
    if pt is None:
        return ("open", None)
    if len(pt) != 82 + 32 * d:
        return ("length", None)
    p = share_pt_parse(pt, d)
    if p is None:
        return ("version", None)
    if (p[0], p[1], p[2], p[3]) != (u, v, r, xv):
        return ("fields", None)
    if path_fold(share_leaf(fp, r, u, xv, p[4], p[5]), xv - 1, p[6]) != mroot:
        return ("commit", None)
    return ("", (p[4], p[5], p[6]))


def judge_key(e, cvpk, r, u, v):
    """The coordinator's / judge's key: sac_enc_key(e, c_v^PK, r, u, v)."""
    return enc_key(e, cvpk, r, u, v)


def garbage(ct):
    """Test helper: G0 = H(GARBAGE_DOMAIN || ct), G(i+1) = H(G(i)), first len(ct) bytes."""
    out, g = b"", sha256(GARBAGE_DOMAIN + ct)
    while len(out) < len(ct):
        out += g
        g = sha256(g)
    return out[:len(ct)]


# ============================================================ soul
ST_IDLE, ST_ADV, ST_SHARED, ST_MASKED, ST_SIGNED, ST_DONE, ST_ABORTED = range(7)
ST_CHECKED, ST_OPENED = 7, 8                 # v4-sa3: after SET 5 / after SA4_ACCUSE

# --fault names that change what the soul deals in R1 (target: the lowest
# other x in U1) -> the internal kind (f3 values).
DEAL_FAULTS = {"bad-share": "garbage", "bad-share-open": "garbage", "bad-share-fields": "fields",
               "bad-commit-share": "commit", "low-epk": "lowepk", "foreign-e": "foreign_e"}


class Refuse(Exception):
    def __init__(self, code, why):
        super().__init__(why)
        self.code = code
        self.why = why


class Soul:
    """sa4s_*: handle(line) -> (ok, err, out_lines).

    Test faults: fault = comma-separated --fault names (see DEAL_FAULTS,
    inconsistent-deal, false-complaint, complain-all, no-open, bad-shsig);
    f3 = {x: "garbage"|"fields"|"commit"|"lowepk"|"foreign_e", "false": set
    of sender xs to complain about anyway, "silent": answer no complaint,
    "badsig": flip SHSIG byte 0, "open_any" / "nolh" / "nosig": mutants of the
    accused's gate (tests only)}."""

    def __init__(self, roster, seed, rng, last_round, entry=None):
        self.ro = roster
        self.seed = seed
        self.pk = ed25519_pk_from_seed(seed)
        if entry is None:
            entry = next((e for e in roster.entries if e[2] == self.pk), None)
            if entry is None:
                raise ValueError("identity: key not in the roster")
        self.me, self.mx = entry[0], entry[4]
        self.rng = rng
        self.last = last_round
        self.state = ST_IDLE
        self.r = -1
        self.done_round = -1
        self.x = None
        self.layout = None
        self.batch = []
        self.d = depth(roster.n)
        self.fault = None          # test faults (comma-separated --fault names)
        self.f3 = {}
        self.eseed = None
        self.sleaves = None
        self.u2p = None
        self.complained = set()
        self.check_kinds = {}      # sender x -> failing content-check kind (tests)
        self.prepared = None

    def _faults(self):
        return set((self.fault or "").split(",")) - {""}

    def set_input(self, words, layout):
        if self.state != ST_IDLE:
            return False
        if not words or len(words) > 16777216 or len(layout) != 32 or any(not (0 <= w <= M32) for w in words):
            return False
        self.x, self.layout = list(words), bytes(layout)
        return True

    def _wipe(self):
        for k in ("csk", "ssk", "b", "held", "seeds", "bsh", "ssh", "tree", "eseed", "sleaves", "prepared"):
            setattr(self, k, None)
        self.batch = []

    def _eid(self, x):
        return self.ro.entries[x - 1][0]

    def handle(self, line):
        if self.state == ST_ABORTED:
            return (False, "refused: round already aborted", [])
        try:
            if self.state == ST_DONE:
                raise Refuse("unexpected", "line after the round finished")
            rec = parse(line)
            if rec is None:
                raise Refuse("bad_line", "malformed line")
            ev = rec[0]
            if self.state == ST_IDLE:
                if ev != EV_ROUND:
                    raise Refuse("unexpected", "expected SA4_ROUND")
                return self._on_round(rec)
            if rec[1] != self.r:
                raise Refuse("bad_round", "line for another round")
            st = self.state
            coll = {ST_ADV: (EV_ADV, "bad_adv"), ST_SHARED: (EV_SHARE, "bad_share"),
                    ST_CHECKED: (EV_COMPLAINT, "bad_complaint"), ST_SIGNED: (EV_SIG3, "bad_sig3")}.get(st)
            if coll and ev == coll[0]:
                self.batch.append(rec)
                if len(self.batch) > self.ro.n:
                    raise Refuse(coll[1], "more lines than souls")
                return (True, "", [])
            if st == ST_ADV and ev == EV_SET and rec[2] == 1:
                return self._on_u1(rec[3])
            if st == ST_SHARED and ev == EV_SET and rec[2] == 5:
                return self._on_check(rec[3])
            if st == ST_CHECKED and ev == EV_ACCUSE:
                return self._on_accuse(rec[2])
            if st in (ST_CHECKED, ST_OPENED) and ev == EV_SET and rec[2] == 2:
                if self.batch:
                    raise Refuse("bad_complaint", "complaints without SA4_ACCUSE")
                return self._on_u2(rec[3])
            if st == ST_MASKED and ev == EV_SET and rec[2] == 3:
                return self._on_u3(rec[3])
            if st == ST_SIGNED and ev == EV_SET and rec[2] == 4:
                return self._on_u4(rec[3])
            raise Refuse("unexpected", "unexpected line in state %d" % st)
        except Refuse as e:
            self._wipe()
            self.state = ST_ABORTED
            return (False, "refused: " + e.why, [fmt_abort(max(self.r, 0), self.me, e.code)])

    def _on_round(self, rec):
        _, r, fp, lw, lay = rec
        self.r = r
        if self.x is None:
            raise Refuse("no_input", "no input set for the round")
        if fp != self.ro.fp:
            raise Refuse("bad_fp", "roster fingerprint differs")
        if r <= self.last:
            raise Refuse("stale_round", "round is not after the last round")
        if lw != len(self.x):
            raise Refuse("bad_len", "vector length differs from the input")
        if lay != self.layout:
            raise Refuse("bad_layout", "vector layout differs")
        # Draw order: c key, s key, b_u, b coefficients, s coefficients,
        # eseed (v4-sa3: the last draw, so every v4-sa2 byte is unchanged).
        self.csk = self.rng.read(32); self.cpk = x25519_base(self.csk)
        self.ssk = self.rng.read(32); self.spk = x25519_base(self.ssk)
        self.b = self.rng.read(32)
        if self.cpk == bytes(32) or self.spk == bytes(32) or self.cpk == self.spk:
            raise Refuse("rng", "key generation refused")
        # Shares for every roster x, dealt here (v4-sa2) in the same rng
        # order as before: b_u coefficients first, then s_u^SK.
        n, t = self.ro.n, self.ro.t
        self.bsh = shamir_split(self.rng, self.b, t, n)
        self.ssh = shamir_split(self.rng, self.ssk, t, n)
        if "inconsistent-deal" in self._faults():      # commit to an off-polynomial b-share
            lx = 1 if self.mx != 1 else 2
            x0, y0 = self.bsh[lx - 1]
            self.bsh[lx - 1] = (x0, bytes([y0[0] ^ 1]) + y0[1:])
        self.tree = deal_tree(self.ro.fp, r, self.me, self.ssh, self.bsh, self.d)
        self.bcm = b_commit(self.ro.fp, r, self.me, self.b)
        self.mroot = self.tree[-1][0]
        sig = ed25519_sign(adv_transcript(self.ro.fp, r, self.me, len(self.x), self.layout, self.cpk, self.spk,
                                          self.bcm, self.mroot), self.seed, self.pk)
        try:
            self.eseed = self.rng.read(32)
        except OSError:
            raise Refuse("rng", "rng refused")
        if len(self.eseed) != 32:
            raise Refuse("rng", "rng refused")
        self.state = ST_ADV
        self.batch = []
        return (True, "", [fmt_adv(r, self.me, self.cpk, self.spk, sig, self.bcm, self.mroot)])

    def _on_u1(self, bm):
        n, t, r, me, fp, d = self.ro.n, self.ro.t, self.r, self.me, self.ro.fp, self.d
        u1 = bitmap_xs(bm, n)
        if u1 is None: raise Refuse("bad_set", "U1 bitmap has bits above N")
        if len(u1) < t: raise Refuse("u1_small", "|U1| below the threshold")
        if self.mx not in u1: raise Refuse("not_in_u1", "this soul is not in U1")
        if len(self.batch) != len(u1): raise Refuse("bad_set", "ADV lines do not match U1")
        keys = [None] * n
        for rec in self.batch:
            x = self.ro.x(rec[2])
            if x == 0: raise Refuse("bad_adv", "ADV from an id not in the roster")
            if x not in u1: raise Refuse("bad_set", "ADV from a soul outside U1")
            if keys[x - 1] is not None: raise Refuse("bad_adv", "two ADV lines from one soul")
            if rec[3] == rec[4]: raise Refuse("dup_key", "a soul advertised c_pk == s_pk")
            keys[x - 1] = (rec[3], rec[4], rec[6], rec[7])
        if keys[self.mx - 1] != (self.cpk, self.spk, self.bcm, self.mroot):
            raise Refuse("bad_adv", "own ADV altered")
        allk = [k for x in u1 for k in keys[x - 1][:2]]
        if len(set(allk)) != len(allk): raise Refuse("dup_key", "two advertised keys are equal")
        self.seeds = [None] * n
        for vx in u1:                                # unchanged v4-sa2 loop (incl. the c-key check)
            if vx != self.mx:
                v = self._eid(vx)
                if enc_key(self.csk, keys[vx - 1][0], r, me, v) is None:
                    raise Refuse("bad_key", "key agreement refused")
                ms = mask_seed(self.ssk, keys[vx - 1][1], r, me, v)
                if ms is None: raise Refuse("bad_key", "mask key agreement refused")
                self.seeds[vx - 1] = ms
        for rec in self.batch:
            if rec[2] != me:
                pk = self.ro.by_id[rec[2]][2]
                msg = adv_transcript(fp, r, rec[2], len(self.x), self.layout, rec[3], rec[4], rec[6], rec[7])
                if not ed25519_verify(msg, rec[5], pk):
                    raise Refuse("bad_sig", "ADV signature does not verify")
        self.keys, self.u1 = keys, u1
        self.h1 = advset_hash(bm, [keys[x - 1] for x in u1])
        # Test faults aimed at the lowest other x in U1.
        kinds = dict((k, v) for k, v in self.f3.items() if isinstance(k, int))
        lowx = next((x for x in u1 if x != self.mx), 0)
        for f in sorted(self._faults()):
            if f in DEAL_FAULTS and lowx:
                kinds[lowx] = DEAL_FAULTS[f]
        # The shares were dealt in R0; each carries its authentication path.
        # v4-sa3: each is sealed under a one-time key e_uv (e_pk on the line).
        self.held = [None] * n
        self.sleaves = {}
        outs = []
        for i in range(n):
            x3 = i + 1
            if x3 not in u1:
                continue
            sl, bl, path = self.ssh[i][1], self.bsh[i][1], tree_path(self.tree, i)
            if x3 == self.mx:
                self.held[i] = (sl, bl, path)
                continue
            v3 = self._eid(x3)
            kind = kinds.get(x3)
            if kind == "commit":                 # after the tree: does not match M_u
                bl = bytes([bl[0] ^ 1]) + bl[1:]
            e = eph(self.eseed, r, me, v3)
            epk = x25519_base(e)
            key = enc_key(e, keys[i][0], r, me, v3)
            if key is None: raise Refuse("bad_key", "key agreement refused")
            pt = share_pt(me, v3, r, (x3 % n) + 1 if kind == "fields" else x3, sl, bl, path)
            ct = share_seal(key, r, me, v3, pt)
            if kind == "garbage":
                ct = garbage(ct)
            elif kind == "lowepk":
                epk = LOW_ORDER[2]
            elif kind == "foreign_e":            # seal under e', send X25519_base(e), reveal e'
                e1 = sha256(b"prepared" + e)
                ct = share_seal(enc_key(e1, keys[i][0], r, me, v3), r, me, v3, pt)
                self.prepared = (x3, e1)
            self.sleaves[x3] = sleaf(fp, r, me, x3, v3, epk, ct)
            outs.append(fmt_share(r, me, v3, ct, epk))
            e = key = pt = None
        self.sroot = share_levels(n, d, self.sleaves)[-1][0]
        g = ed25519_sign(shares_transcript(fp, r, me, self.h1, self.sroot), self.seed, self.pk)
        if self.f3.get("badsig") or "bad-shsig" in self._faults():
            g = bytes([g[0] ^ 1]) + g[1:]
        nsh = len(outs)
        outs.append(fmt_shsig(r, me, g))
        outs.append(fmt_end(r, 1, me, nsh))
        self.bsh = self.ssh = self.tree = None
        self.batch = []
        self.state = ST_SHARED
        return (True, "", outs)

    def _on_check(self, bm):
        """SET 5 (U2'): structural pass 1 (refuse), content pass 2 (complain)."""
        n, t, r, me, mx, fp, d = self.ro.n, self.ro.t, self.r, self.me, self.mx, self.ro.fp, self.d
        u2p = bitmap_xs(bm, n)
        if u2p is None: raise Refuse("bad_set", "U2' bitmap has bits above N")
        if not set(u2p) <= set(self.u1): raise Refuse("bad_set", "U2' is not a subset of U1")
        if len(u2p) < t: raise Refuse("u2_small", "|U2'| below the threshold")
        if mx not in u2p: raise Refuse("not_in_u2", "this soul is not in U2'")
        if len(self.batch) != len(u2p) - 1: raise Refuse("bad_share", "share lines do not match U2'")
        got = {}
        for rec in self.batch:                      # pass 1: structure (batch order)
            vx = self.ro.x(rec[2])
            if vx == 0: raise Refuse("bad_share", "share from an id not in the roster")
            if rec[3] != me: raise Refuse("bad_share", "share addressed to another soul")
            if vx not in u2p: raise Refuse("bad_share", "share from a soul outside U2'")
            if vx == mx: raise Refuse("bad_share", "share from this soul to itself")
            if vx in got: raise Refuse("bad_share", "two shares from one soul")
            if len(rec[4]) != 98 + 32 * d: raise Refuse("bad_share", "share ciphertext has the wrong length")
            if not epk_ok(rec[5]): raise Refuse("bad_share", "share one-time key is not a valid X25519 key")
            got[vx] = rec
        false = set(self.f3.get("false", ()))
        fl = self._faults()
        if "false-complaint" in fl and got:
            false.add(min(got))
        if "complain-all" in fl:
            false |= set(got)
        self.complained = set()
        self.check_kinds = {}
        outs = []
        for vx in sorted(got):                      # pass 2: content (ascending sender x)
            rec = got[vx]
            v = rec[2]
            key = enc_key(self.csk, rec[5], r, v, me)
            if key is None: raise Refuse("bad_key", "key agreement refused")
            kind, val = share_check(fp, r, v, me, mx, d, key, rec[4], self.keys[vx - 1][3])
            key = None
            if kind == "" and vx not in false:
                self.held[vx - 1] = val
                continue
            self.check_kinds[vx] = kind or "false"
            lh = sleaf(fp, r, v, mx, me, rec[5], rec[4])
            g = ed25519_sign(complaint_transcript(fp, r, me, v, self.h1, lh), self.seed, self.pk)
            self.complained.add(vx)
            outs.append(fmt_complaint(r, me, v, lh, g))
        self.csk = None                             # c^SK is no longer needed
        self.u2p = u2p
        outs.append(fmt_end(r, PHASE_CHECK, me, len(outs)))
        self.batch = []
        self.state = ST_CHECKED
        return (True, "", outs)

    def _on_accuse(self, bm):
        """ACCUSE (complainer set): reveal e_uv only for a valid complaint."""
        n, r, me, mx, fp = self.ro.n, self.r, self.me, self.mx, self.ro.fp
        cx = bitmap_xs(bm, n)
        if cx is None: raise Refuse("bad_set", "ACCUSE bitmap has bits above N")
        if not cx: raise Refuse("bad_set", "empty ACCUSE set")
        if not set(cx) <= set(self.u2p) - {mx}:
            raise Refuse("bad_set", "ACCUSE set is not a subset of U2' without this soul")
        if len(self.batch) != len(cx):
            raise Refuse("bad_complaint", "complaint lines do not match the ACCUSE set")
        byx = {}
        for rec in self.batch:
            vx = self.ro.x(rec[2])
            if rec[3] != me: raise Refuse("bad_complaint", "complaint about another soul")
            if vx == 0 or vx not in cx: raise Refuse("bad_complaint", "complaint from a soul outside the ACCUSE set")
            if vx in byx: raise Refuse("bad_complaint", "two complaints from one soul")
            byx[vx] = rec
        silent = self.f3.get("silent") or "no-open" in self._faults()
        outs = []
        for vx in sorted(byx):
            rec = byx[vx]
            v = rec[2]
            if silent:
                continue
            ok = self.f3.get("open_any") or (
                (self.f3.get("nolh") or rec[4] == self.sleaves.get(vx)) and     # compare first
                (self.f3.get("nosig") or ed25519_verify(complaint_transcript(fp, r, v, me, self.h1, rec[4]), rec[5],
                                                        self.ro.entries[vx - 1][2])))
            if not ok:
                continue                            # never reveal for an invalid complaint; never refuse
            e = eph(self.eseed, r, me, v)
            if self.prepared is not None and self.prepared[0] == vx:
                e = self.prepared[1]
            outs.append(fmt_open(r, me, v, e))
            e = None
        outs.append(fmt_end(r, PHASE_OPEN, me, len(outs)))
        self.batch = []
        self.state = ST_OPENED
        return (True, "", outs)

    def _on_u2(self, bm):
        """Final SET 2 (U2), in CHECKED (empty batch) or OPENED."""
        n, t, r, me, mx = self.ro.n, self.ro.t, self.r, self.me, self.mx
        u2 = bitmap_xs(bm, n)
        if u2 is None: raise Refuse("bad_set", "U2 bitmap has bits above N")
        if not set(u2) <= set(self.u2p): raise Refuse("bad_set", "U2 is not a subset of U2'")
        if len(u2) < t: raise Refuse("u2_small", "|U2| below the threshold")
        if mx not in u2: raise Refuse("not_in_u2", "this soul is not in U2")
        if set(u2) & self.complained:
            raise Refuse("bad_set", "U2 contains a soul whose share this soul complained about")
        for x in range(1, n + 1):
            if x not in u2:
                self.held[x - 1] = None
        self.eseed = None
        self.sleaves = None
        self.prepared = None
        y = saprg_mask(self.x, self.b, 1)
        for ox in u2:
            if ox != mx:
                y = saprg_mask(y, self.seeds[ox - 1], -1 if self._eid(ox) < me else 1)
        self.u2 = u2
        self.csk = self.ssk = self.b = self.seeds = None
        outs = fmt_y_lines(r, me, y)
        outs.append(fmt_end(r, 2, me, len(outs)))
        self.batch = []
        self.state = ST_MASKED
        return (True, "", outs)

    def _on_u3(self, bm):
        n, t, r = self.ro.n, self.ro.t, self.r
        u3 = bitmap_xs(bm, n)
        if u3 is None: raise Refuse("bad_set", "U3 bitmap has bits above N")
        if not set(u3) <= set(self.u2): raise Refuse("bad_set", "U3 is not a subset of U2")
        if len(u3) < t: raise Refuse("u3_small", "|U3| below the threshold")
        if self.mx not in u3: raise Refuse("not_in_u3", "this soul is not in U3")
        self.t3 = t3_transcript(self.ro.fp, r, self.h1, bitmap(self.u2), bm)
        self.mysig = ed25519_sign(self.t3, self.seed, self.pk)
        self.u3 = u3
        self.state = ST_SIGNED
        self.batch = []
        return (True, "", [fmt_sig3(r, self.me, self.mysig)])

    def _on_u4(self, bm):
        n, t, r, me, mx = self.ro.n, self.ro.t, self.r, self.me, self.mx
        u4 = bitmap_xs(bm, n)
        if u4 is None: raise Refuse("bad_set", "U4 bitmap has bits above N")
        if not set(u4) <= set(self.u3): raise Refuse("bad_set", "U4 is not a subset of U3")
        if len(u4) < t: raise Refuse("u4_small", "fewer than t consistency signatures")
        if mx not in u4: raise Refuse("not_in_u4", "this soul is not in U4")
        if len(self.batch) != len(u4): raise Refuse("bad_sig3", "signature lines do not match U4")
        sigs = [None] * n
        for rec in self.batch:
            x = self.ro.x(rec[2])
            if x == 0: raise Refuse("bad_sig3", "signature from an id not in the roster")
            if x not in u4: raise Refuse("bad_sig3", "signature from a soul outside U4")
            if sigs[x - 1] is not None: raise Refuse("bad_sig3", "two signatures from one soul")
            sigs[x - 1] = rec[3]
        if sigs[mx - 1] != self.mysig: raise Refuse("bad_sig3", "own signature altered")
        valid = 1
        for vx in u4:
            if valid < t and vx != mx:
                if not ed25519_verify(self.t3, sigs[vx - 1], self.ro.entries[vx - 1][2]):
                    raise Refuse("bad_sig3", "consistency signature does not verify")
                valid += 1
        if valid < t: raise Refuse("bad_sig3", "fewer than t valid consistency signatures")
        outs = []
        for ox in self.u2:
            hv = self.held[ox - 1]
            if hv is None: raise Refuse("internal", "missing held share")
            u = self._eid(ox)
            kind = 0 if ox in self.u3 else 1
            pf = reveal_proof(self.ro.fp, r, u, mx, kind, hv[0], hv[1], hv[2])
            outs.append(fmt_reveal(r, me, u, kind, hv[1] if kind == 0 else hv[0], pf))
        outs.append(fmt_end(r, 3, me, len(outs)))
        self._wipe()
        self.done_round = r
        self.state = ST_DONE
        return (True, "", outs)


# ============================================================ coordinator oracle (A2.4c, v4-sa3)
# Coordinator states (sa4_coord.nova numbers) and their run order.
C_ADV, C_SHARES, C_Y, C_SIG3, C_REVEAL, C_READY, C_DONE, C_CANCELLED, C_CHECK, C_OPEN = range(10)
C_ORDER = [0, 1, 4, 5, 6, 7, 8, 9, 2, 3]


def phase_order(st):
    """sa4c_phase_order: position of state st in the run order 0, 1, 8, 9, 2, 3, 4, 5, 6, 7."""
    return C_ORDER[st]


class Coord:
    """Python oracle of the v4-sa3 coordinator (sa4_coord.nova): receipt
    (8.4), closes (8.5), verdicts (8.6, coord_verdicts), codes (8.7),
    evidence (8.8). The Y / SIG3 / REVEAL phases are simplified (the sum is
    rebuilt by coord_rebuild). Mutations for tests (all off = spec):
    no_epk_check, no_lh_check, no_csig_check, no_exclude, no_epk_struct,
    robust_order, no_early_stop."""

    def __init__(self, ro, r, lw, lay, **mut):
        self.ro, self.r, self.lw, self.lay, self.mut = ro, r, lw, lay, mut
        self.fp, self.n, self.t, self.d = ro.fp, ro.n, ro.t, depth(ro.n)
        self.st = C_ADV
        self.P = {x: dict(adv=None, bad=False, why="", code=0, aborted=0, sh={}, shl={}, shsig=None, end1=-1,
                          comp={}, compl={}, end4=-1, opens={}, end5=-1, yw=[], y=None, sig3=None, rev=[])
                  for x in range(1, ro.n + 1)}
        self.count = dict(judged=0, skipped=0, roots=0, verifies=0)
        self.evidence = {}          # id -> text
        self.roots = {}             # x -> (ok, levels)
        self.accused = {}           # x -> ascending complainer xs
        self.u1 = self.u2p = self.u2 = self.u3 = self.u4 = []
        self.h1 = None
        self.cancel = ""

    def I(self, x):
        return self.ro.entries[x - 1][0]

    def bad(self, x, why, code=0):
        """'out x, code k, why': leave x out; first why / code wins."""
        p = self.P[x]
        p["bad"] = True
        if not p["why"]:
            p["why"] = why
        if code and not p["code"]:
            p["code"] = code

    def live(self, xs):
        return [x for x in xs if not self.P[x]["bad"]]

    def blamed(self, i):
        return self.P[self.ro.x(i)]["code"]

    def why(self, i):
        return self.P[self.ro.x(i)]["why"]

    def codes(self):
        return {self.I(x): self.P[x]["code"] for x in self.P if self.P[x]["code"]}

    def counters(self):
        c = self.count
        return [c["judged"], c["skipped"], c["roots"], c["verifies"]]

    def expect(self):
        """sa4c_expect: the ids the current state reads from."""
        lst = {C_ADV: range(1, self.n + 1), C_SHARES: self.u1, C_CHECK: self.u2p, C_OPEN: sorted(self.accused),
               C_Y: self.u2, C_SIG3: self.u3, C_REVEAL: self.u4}.get(self.st, [])
        return [self.I(x) for x in self.live(lst)]

    def keep(self):
        """sa4c_keep: the ids still in the round after the last close."""
        lst = {C_SHARES: self.u1, C_CHECK: self.u2p, C_OPEN: self.live(self.u2p), C_Y: self.u2,
               C_SIG3: self.u3, C_REVEAL: self.u4}.get(self.st, range(1, self.n + 1))
        return [self.I(x) for x in lst]

    def recv(self, fid, line):
        x = self.ro.x(fid)
        if x == 0:
            return
        p = self.P[x]
        if p["bad"]:
            return
        if self.st not in (C_ADV, C_SHARES, C_CHECK, C_OPEN, C_Y, C_SIG3, C_REVEAL):
            return
        rec = parse(line)
        if rec is None: return self.bad(x, "malformed line")
        if rec[1] != self.r: return self.bad(x, "line for another round")
        ev, st = rec[0], self.st
        if ev == EV_ABORT:
            p["aborted"] = 1
            return self.bad(x, "aborted the round (%s); possibly a victim, not evidence of misbehaviour" % rec[3])
        if st == C_ADV:
            if ev != EV_ADV or rec[2] != fid or p["adv"]: return self.bad(x, "bad ADV")
            msg = adv_transcript(self.fp, self.r, fid, self.lw, self.lay, rec[3], rec[4], rec[6], rec[7])
            if not ed25519_verify(msg, rec[5], self.ro.entries[x - 1][2]):
                return self.bad(x, "ADV signature does not verify")
            p["adv"] = rec
            return
        if st == C_SHARES:
            if x not in self.u1: return self.bad(x, "soul not in the current set")
            if p["end1"] >= 0: return self.bad(x, "line after END")
            if ev == EV_SHARE:
                if rec[2] != fid: return self.bad(x, "share for another sender")
                if p["shsig"] is not None: return self.bad(x, "share after the share signature")
                tx = self.ro.x(rec[3])
                if tx == 0: return self.bad(x, "share to an id not in the roster")
                if tx == x: return self.bad(x, "share to itself")
                if tx not in self.u1: return self.bad(x, "share to a soul outside U1")
                if len(rec[4]) != 98 + 32 * self.d:
                    return self.bad(x, "share ciphertext length does not match the roster's tree depth")
                if not self.mut.get("no_epk_struct") and not epk_ok(rec[5]):
                    return self.bad(x, "share one-time key is not a valid X25519 key")
                if tx in p["sh"]: return self.bad(x, "two shares to one soul")
                p["sh"][tx], p["shl"][tx] = rec, line
                return
            if ev == EV_SHSIG:
                if rec[2] != fid: return self.bad(x, "share signature for another id")
                if p["shsig"] is not None: return self.bad(x, "second share signature")
                p["shsig"] = rec[3]
                return
            if ev == EV_END:
                if rec[2] != 1: return self.bad(x, "wrong END phase")
                if rec[3] != fid: return self.bad(x, "END for another id")
                if rec[4] != len(p["sh"]): return self.bad(x, "END count differs")
                if rec[4] != len(self.u1) - 1: return self.bad(x, "not one share per soul in U1")
                if p["shsig"] is None: return self.bad(x, "no share signature")
                p["end1"] = rec[4]
                return
            return self.bad(x, "unexpected line while collecting shares")
        if st == C_CHECK:
            if x not in self.u2p: return self.bad(x, "soul not in the current set")
            if p["end4"] >= 0: return self.bad(x, "line after END")
            if ev == EV_COMPLAINT:
                if rec[2] != fid: return self.bad(x, "complaint for another id")
                ax = self.ro.x(rec[3])
                if ax == 0: return self.bad(x, "complaint about an id not in the roster")
                if ax == x: return self.bad(x, "complaint about itself")
                if ax not in self.u2p: return self.bad(x, "complaint about a soul outside U2'")
                if ax in p["comp"]: return self.bad(x, "two complaints about one soul")
                p["comp"][ax], p["compl"][ax] = rec, line
                return
            if ev == EV_END:
                if rec[2] != 4: return self.bad(x, "wrong END phase")
                if rec[3] != fid: return self.bad(x, "END for another id")
                if rec[4] != len(p["comp"]): return self.bad(x, "END count differs")
                p["end4"] = rec[4]
                return
            return self.bad(x, "unexpected line while collecting complaints")
        if st == C_OPEN:
            if x not in self.accused: return self.bad(x, "soul not in the current set")
            if p["end5"] >= 0: return self.bad(x, "line after END")
            if ev == EV_OPEN:
                if rec[2] != fid: return self.bad(x, "opening for another id")
                vx = self.ro.x(rec[3])
                if vx == 0 or vx not in self.accused[x]:
                    return self.bad(x, "opening for a complaint that was not forwarded")
                if vx in p["opens"]: return self.bad(x, "two openings for one complaint")
                p["opens"][vx] = rec[4]
                return
            if ev == EV_END:
                if rec[2] != 5: return self.bad(x, "wrong END phase")
                if rec[3] != fid: return self.bad(x, "END for another id")
                if rec[4] != len(p["opens"]): return self.bad(x, "END count differs")
                p["end5"] = rec[4]
                return
            return self.bad(x, "unexpected line while collecting openings")
        if st == C_Y and x in self.u2:
            if ev == EV_Y:
                p["yw"].extend(rec[5]); return
            if ev == EV_END and rec[2] == 2:
                p["y"] = p["yw"]; return
        if st == C_SIG3 and ev == EV_SIG3 and x in self.u3:
            if ed25519_verify(self.t3, rec[3], self.ro.entries[x - 1][2]):
                p["sig3"] = line
            return
        if st == C_REVEAL and x in self.u4:
            if ev == EV_REVEAL: p["rev"].append(rec)
            return
        return self.bad(x, "unexpected line in phase %d" % st)

    def close(self):
        """Close the current phase -> [(to id, line)] in routing order."""
        r, out, st = self.r, [], self.st
        if st == C_ADV:
            self.u1 = [x for x in range(1, self.n + 1) if self.P[x]["adv"] and not self.P[x]["bad"]]
            bm = bitmap(self.u1)
            self.h1 = advset_hash(bm, [tuple(self.P[x]["adv"][k] for k in (3, 4, 6, 7)) for x in self.u1])
            advl = [fmt_adv(*self.P[x]["adv"][1:]) for x in self.u1]
            for x in self.u1:
                out += [(self.I(x), l) for l in advl] + [(self.I(x), fmt_set(r, 1, bm))]
            self.st = C_SHARES
        elif st == C_SHARES:
            for x in self.u1:
                if not self.P[x]["bad"] and self.P[x]["end1"] < 0:
                    self.bad(x, "share batch incomplete")
            self.u2p = self.live(self.u1)
            if len(self.u2p) < self.t:
                return self._cancel("|U2'| %d below t" % len(self.u2p))
            bm = bitmap(self.u2p)
            for vx in self.u2p:
                out += [(self.I(vx), self.P[ux]["shl"][vx]) for ux in self.u2p if ux != vx]
                out.append((self.I(vx), fmt_set(r, 5, bm)))
            self.st = C_CHECK
        elif st == C_CHECK:
            for x in self.u2p:
                if not self.P[x]["bad"] and self.P[x]["end4"] < 0:
                    self.bad(x, "did not finish the check phase")
            self.accused = {}
            for vx in self.live(self.u2p):
                for ax in self.P[vx]["comp"]:
                    if not self.P[ax]["bad"]:
                        self.accused.setdefault(ax, []).append(vx)
            if not self.accused:
                return self._set2(out)
            for ax in sorted(self.accused):
                vs = sorted(self.accused[ax])
                self.accused[ax] = vs
                out += [(self.I(ax), self.P[vx]["compl"][ax]) for vx in vs]
                out.append((self.I(ax), fmt_accuse(r, bitmap(vs))))
            self.st = C_OPEN
        elif st == C_OPEN:
            coord_verdicts(self)
            for ux in sorted(self.accused):
                if not self.P[ux]["bad"] and self.P[ux]["end5"] < 0:
                    self.bad(ux, "did not finish the open phase")
            return self._set2(out)
        elif st == C_Y:
            self.u3 = [x for x in self.u2 if not self.P[x]["bad"] and self.P[x]["y"] is not None]
            self.t3 = t3_transcript(self.fp, r, self.h1, bitmap(self.u2), bitmap(self.u3))
            out += [(self.I(x), fmt_set(r, 3, bitmap(self.u3))) for x in self.u3]
            self.st = C_SIG3
        elif st == C_SIG3:
            self.u4 = [x for x in self.u3 if self.P[x]["sig3"]]
            sl = [self.P[x]["sig3"] for x in self.u4]
            for x in self.u4:
                out += [(self.I(x), l) for l in sl] + [(self.I(x), fmt_set(r, 4, bitmap(self.u4)))]
            self.st = C_REVEAL
        elif st == C_REVEAL:
            self.st = C_READY
        return out

    def _cancel(self, why):
        self.cancel = why
        self.st = C_CANCELLED
        return []

    def _set2(self, out):
        """Final SET 2: U2 = U2' souls not left out."""
        self.u2 = self.live(self.u2p)
        if self.mut.get("no_exclude"):
            self.u2 = [x for x in self.u2p if self.P[x]["end4"] >= 0]
        if len(self.u2) < self.t:
            return self._cancel("|U2| %d below t" % len(self.u2))
        out += [(self.I(x), fmt_set(self.r, 2, bitmap(self.u2))) for x in self.u2]
        self.st = C_Y
        return out

    def root_ok(self, ux):
        """Share root of u over the lines the coordinator holds, SHSIG verified (cached)."""
        if ux not in self.roots:
            p = self.P[ux]
            u = self.I(ux)
            leaves = {vx: sleaf(self.fp, self.r, u, vx, rec[3], rec[5], rec[4]) for vx, rec in p["sh"].items()}
            lv = share_levels(self.n, self.d, leaves)
            self.count["roots"] += 1
            self.count["verifies"] += 1
            ok = p["shsig"] is not None and ed25519_verify(shares_transcript(self.fp, self.r, u, self.h1, lv[-1][0]),
                                                          p["shsig"], self.ro.entries[ux - 1][2])
            self.roots[ux] = (ok, lv)
        return self.roots[ux][0]

    def make_evidence(self, ux, vx, code, e):
        """Evidence text (8.8) for code 1 (against sender u) or 2 (against complainer v)."""
        L = [EVID_HEADER, "fp " + self.fp.hex(), "round %d" % self.r, "code %d" % code,
             "sender %d" % self.I(ux), "complainer %d" % self.I(vx), "u1 " + bitmap(self.u1).hex()]
        for x in self.u1:
            a = self.P[x]["adv"]
            L.append("key %d %s %s %s %s" % (a[2], a[3].hex(), a[4].hex(), a[6].hex(), a[7].hex()))
        L.append("share " + self.P[ux]["shl"][vx])
        if code == 1:
            L += ["path " + b"".join(tree_path(self.roots[ux][1], vx - 1)).hex(),
                  "shsig " + self.P[ux]["shsig"].hex()]
        else:
            L += ["path -", "shsig -"]
        L += ["complaint " + self.P[vx]["compl"][ux], "open " + e.hex()]
        return "\n".join(L) + "\n"


def coord_verdicts(c):
    """The verdict loop (8.6) on a Coord in state OPEN: pairs (complainer x,
    accused x) ascending, early stop, codes 1..5, evidence, counters."""
    fp, r, d, m = c.fp, c.r, c.d, c.mut
    pairs = sorted((vx, ux) for ux, vs in c.accused.items() for vx in vs)
    for vx, ux in pairs:
        if not m.get("no_early_stop") and len(c.live(c.u2p)) < c.t:
            break                                   # the round is lost
        if c.P[vx]["bad"] or c.P[ux]["bad"]:
            c.count["skipped"] += 1
            continue
        c.count["judged"] += 1
        v, u = c.I(vx), c.I(ux)
        cp = parse(c.P[vx]["compl"][ux])            # re-parse the raw COMPLAINT line
        line = c.P[ux]["sh"][vx]
        if not m.get("no_lh_check") and cp[4] != sleaf(fp, r, u, vx, v, line[5], line[4]):
            c.bad(vx, "complaint about soul %d names a share it was not sent (not proven)" % u, 5)
            continue
        c.count["verifies"] += 1
        if not m.get("no_csig_check") and not ed25519_verify(
                complaint_transcript(fp, r, v, u, c.h1, cp[4]), cp[5], c.ro.entries[vx - 1][2]):
            c.bad(vx, "complaint about soul %d does not verify (not proven)" % u, 5)
            continue
        e = c.P[ux]["opens"].get(vx) if c.P[ux]["end5"] >= 0 else None
        if e is None or (not m.get("no_epk_check") and x25519_base(e) != line[5]):
            c.bad(ux, "did not open its share to soul %d with its one-time key (not proven)" % v, 3)
            continue
        kind, _ = share_check(fp, r, u, v, vx, d, judge_key(e, c.P[vx]["adv"][3], r, u, v), line[4],
                              c.P[ux]["adv"][7])
        if m.get("robust_order") and not c.root_ok(ux):
            c.bad(ux, "share signature does not verify over the shares it sent (not proven)", 4)
            continue
        if kind == "":
            c.bad(vx, "proven: false complaint about soul %d (the share opens and matches)" % u, 2)
            c.evidence[v] = c.make_evidence(ux, vx, 2, e)
        elif c.root_ok(ux):
            c.bad(ux, "proven: sent soul %d a share that fails the %s check" % (v, kind), 1)
            c.evidence[u] = c.make_evidence(ux, vx, 1, e)
        else:
            c.bad(ux, "share signature does not verify over the shares it sent (not proven)", 4)
    return c.count


def judge_evidence(ro, text):
    """Standalone judge (section 9): roster + evidence text ->
    ("sender", u) | ("complainer", v) | ("invalid", why).

    Strict: the exact 8.8 lines and keys, canonical hex / decimal, no extra
    line; code 2 must carry exactly `path -` and `shsig -`; the complaint
    line (both codes) must be the canonical SA4_COMPLAINT of v about u for
    round r whose leaf is the recomputed one and whose signature verifies.
    One malleability remains and cannot be removed: X25519 clamps the
    scalar, so bits 0-2 of byte 0 and bits 6-7 of byte 31 of the `open` key
    are not bound by X25519_base(e) == e_pk (32 encodings of one opening
    judge alike). Evidence files are therefore not unique; the verdict is."""
    if not text.endswith("\n"):
        return ("invalid", "format")
    L = text[:-1].split("\n")
    if not L or L[0] != EVID_HEADER:
        return ("invalid", "format")
    i = [1]

    def take(key):
        if i[0] >= len(L) or not L[i[0]].startswith(key + " "):
            raise ValueError(key)
        i[0] += 1
        return L[i[0] - 1][len(key) + 1:]
    try:
        fp = _unhex(take("fp"), 32)
        r = _round(take("round"))
        code = {"1": 1, "2": 2}.get(take("code"), 0)
        su, sv = _u32(take("sender")), _u32(take("complainer"))
        bm = _unhex(take("u1"), 32)
        if fp is None or r < 0 or code == 0 or su < 0 or sv < 0 or bm is None:
            return ("invalid", "format")
        u1 = bitmap_xs(bm, ro.n)
        if fp != ro.fp:
            return ("invalid", "roster fingerprint differs")
        if u1 is None:
            return ("invalid", "format")
        keys = []
        for x in u1:
            f = take("key").split(" ")
            if len(f) != 5 or _u32(f[0]) != ro.entries[x - 1][0]:
                return ("invalid", "key lines do not match U1")
            ks = tuple(_unhex(z, 32) for z in f[1:])
            if None in ks:
                return ("invalid", "format")
            keys.append(ks)
        shl, path_s, sig_s, cpl, e_s = take("share"), take("path"), take("shsig"), take("complaint"), take("open")
    except ValueError:
        return ("invalid", "format")
    if i[0] != len(L):
        return ("invalid", "format")
    h1 = advset_hash(bm, keys)
    kt = {ro.entries[x - 1][0]: k for x, k in zip(u1, keys)}
    sh, e = parse(shl), _unhex(e_s, 32)
    if sh is None or sh[0] != EV_SHARE or fmt_share(*sh[1:]) != shl or e is None:
        return ("invalid", "format")
    u, v, d = sh[2], sh[3], depth(ro.n)
    ux, vx = ro.x(u), ro.x(v)
    if sh[1] != r or (u, v) != (su, sv) or u == v or ux not in u1 or vx not in u1:
        return ("invalid", "ids or round")
    if len(sh[4]) != 98 + 32 * d or not epk_ok(sh[5]):
        return ("invalid", "share structure")
    if x25519_base(e) != sh[5]:
        return ("invalid", "opening does not match e_pk")
    lh = sleaf(fp, r, u, vx, v, sh[5], sh[4])
    kind, _ = share_check(fp, r, u, v, vx, d, judge_key(e, kt[v][0], r, u, v), sh[4], kt[u][3])
    if kind != "":
        pb = _unhex(path_s, 32 * d)
        g = _unhex(sig_s, 64)
        if pb is None or g is None:
            return ("invalid", "no sender signature")
        root = path_fold(lh, vx - 1, [pb[32 * k:32 * k + 32] for k in range(d)])
        if not ed25519_verify(shares_transcript(fp, r, u, h1, root), g, ro.entries[ux - 1][2]):
            return ("invalid", "the sender did not sign this share")
        verdict = ("sender", u)
    else:
        if path_s != "-" or sig_s != "-":           # 8.8: code 2 carries exactly "path -" / "shsig -"
            return ("invalid", "format")
        verdict = ("complainer", v)
    # The complaint line, for both verdicts: the canonical SA4_COMPLAINT of
    # v about u in round r naming this share, signed by v over H1 (for
    # code 1 the coordinator verified the same line before judging, so no
    # evidence file it writes carries anything else).
    cp = parse(cpl)
    if cp is None or cp[0] != EV_COMPLAINT or fmt_complaint(*cp[1:]) != cpl or cp[1] != r or \
            (cp[2], cp[3]) != (v, u) or cp[4] != lh:
        return ("invalid", "complaint does not name this share")
    if not ed25519_verify(complaint_transcript(fp, r, v, u, h1, lh), cp[5], ro.entries[vx - 1][2]):
        return ("invalid", "the complainer did not sign this complaint")
    if (code == 1) != (verdict[0] == "sender"):
        return ("invalid", "claimed code differs from the verdict")
    return verdict


def judge_main(argv):
    """--judge FILE [--roster R]: prints 'verdict: sender <u>' / 'verdict:
    complainer <v>' (exit 0) or 'invalid: <why>' (exit 2)."""
    path, rpath = argv[0], os.environ.get("CE_SECAGG_ROSTER", "")
    if len(argv) == 3 and argv[1] == "--roster":
        rpath = argv[2]
    elif len(argv) != 1:
        print("sa4_ref: usage: --judge FILE [--roster R]")
        return 2
    try:
        ro = roster_load(rpath)
        with open(path, "rb") as fh:
            data = fh.read(1 << 24)
        text = data.decode("ascii")
    except (ValueError, OSError, UnicodeDecodeError) as e:
        print("invalid: cannot read input: %s" % e)
        return 2
    v = judge_evidence(ro, text)
    if v[0] == "invalid":
        print("invalid: " + v[1])
        return 2
    print("verdict: %s %d" % v)
    return 0


class Net:
    """In-process round: Python souls + the Coord oracle. faults: {x: f3
    dict}; tamper(phase, msgs) -> msgs on the downlink (evil coordinator /
    MITM); up(from_id, line) -> line on the uplink."""

    def __init__(self, ro, seeds, r, lw, faults=None, coord_mut=None, rngf=None, last=0, fault_names=None):
        self.ro, self.r, self.lw = ro, r, lw
        lay = h_layout()
        self.C = Coord(ro, r, lw, lay, **(coord_mut or {}))
        self.S, self.refused, self.all_lines = {}, {}, []
        self.adv_lines, self.trace = [], []
        for e in ro.entries:
            x = e[4]
            rng = rngf(e) if rngf else TestRng(b"sa4-oracle" + be(e[0], 4) + be(r, 8))
            s = Soul(ro, seeds[x - 1], rng, last, e)
            s.f3 = dict((faults or {}).get(x, {}))
            s.fault = (fault_names or {}).get(x)
            s.set_input(h_input(x - 1, lw), lay)
            self.S[e[0]] = s
        self.pending = [(e[0], fmt_round(r, ro.fp, lw, lay)) for e in ro.entries]
        self.tamper = None
        self.up = None

    def deliver(self, msgs):
        for to, line in msgs:
            ok, err, outs = self.S[to].handle(line)
            if not ok and to not in self.refused:
                self.refused[to] = (outs[-1].split(" ")[-1] if outs else "-", err)
            for o in outs:
                self.all_lines.append((to, o))
                self.C.recv(to, self.up(to, o) if self.up else o)

    def run(self, stop_after=None):
        self.deliver(self.pending)
        while self.C.st not in (C_READY, C_CANCELLED):
            ph = self.C.st
            msgs = self.C.close()
            if self.tamper:
                msgs = self.tamper(ph, msgs)
            self.deliver(msgs)
            if stop_after == ph:
                break
        return self

    def result(self):
        C = self.C
        if C.st != C_READY:
            return None
        advs = {C.I(x): C.P[x]["adv"] for x in C.u1}
        ys = {C.I(x): C.P[x]["y"] for x in C.u3}
        revs = {C.I(x): C.P[x]["rev"] for x in C.u4}
        return coord_rebuild(self.ro, self.r, self.lw, advs, ys, revs, C.u2, C.u3)[0]

    def expected(self):
        out = [0] * self.lw
        for x in self.C.u3:
            out = [(a + b) & M32 for a, b in zip(out, h_input(x - 1, self.lw))]
        return out

    def opens(self):
        return [parse(l) for _, l in self.all_lines if l.startswith("SA4_OPEN ")]

    def codes(self):
        return self.C.codes()


# ============================================================ coordinator oracle (A2.4b)
def coord_rebuild(ro, r, lw, advs, ys, reveals, u2, u3):
    """Python oracle of the coordinator's lazy robust rebuild (SPEC.md,
    coordinator steps 1-5) and unmask (sa4c_unmask order: U2 ascending x).

    advs: {id: ADV record}; ys: {id: masked words}; reveals: {revealer id:
    [REVEAL records]}; u2, u3: ascending x lists.
    -> (sum words or None, excluded revealer ids sorted, blamed dealer id or
    None, why). A revealer with a proof of the wrong length (not D+1 units)
    is left out entirely (structural, not 'excluded'); the first reveal per
    (revealer, dealer, kind) is used."""
    n, t, d, fp = ro.n, ro.t, depth(ro.n), ro.fp
    I = lambda x: ro.entries[x - 1][0]
    rv = {}
    for w, recs in reveals.items():
        if ro.x(w) == 0 or any(len(p[6]) != 32 * (d + 1) for p in recs):
            continue
        m = {}
        for p in recs:
            m.setdefault((p[3], p[4]), (p[5], p[6]))
        rv[ro.x(w)] = m
    rxs = sorted(rv)
    bad, checked = set(), {}

    def out(total, blamed, why):
        return total, sorted(I(x) for x in bad), blamed, why
    total = [0] * lw
    for x in u3:
        total = [(a + b) & M32 for a, b in zip(total, ys[I(x)])]
    for ax in u2:
        u = I(ax)
        kind = 0 if ax in u3 else 1
        adv = advs[u]

        def good(sec):
            if sec is None:
                return False
            return b_commit(fp, r, u, sec) == adv[6] if kind == 0 else x25519_base(sec) == adv[4]
        cand = [x for x in rxs if x not in bad and (u, kind) in rv[x]]
        if len(cand) < t:
            return out(None, None, "fewer than t good shares about soul %d" % u)
        sec = shamir_combine([(x, rv[x][(u, kind)][0]) for x in cand[:t]], 32)
        if not good(sec):
            ver = []
            for x in cand:
                if len(ver) >= t:
                    break
                key = (x, u, kind)
                if key not in checked:
                    sh, pf = rv[x][(u, kind)]
                    checked[key] = reveal_proof_ok(fp, r, u, x, kind, sh, pf, adv[7], d)
                if checked[key]:
                    ver.append(x)
                else:
                    bad.add(x)          # "reveal about soul u does not match its commitment"
            if len(ver) < t:
                return out(None, None, "fewer than t good shares about soul %d" % u)
            sec = shamir_combine([(x, rv[x][(u, kind)][0]) for x in ver], 32)
            if not good(sec):
                return out(None, u, "soul %d dealt shares that do not match its commitment" % u)
        if kind == 0:
            total = saprg_mask(total, sec, -1)
            continue
        for vx in u3:
            v = I(vx)
            ms = mask_seed(sec, advs[v][4], r, u, v)
            if ms is None:
                return out(None, None, "mask key agreement refused")
            total = saprg_mask(total, ms, -1 if u > v else 1)
    return out(total, None, "")


def o_roster(n):
    """Oracle roster: ids 10, 20, ..; seeds SHA-256("sa4-oracle-seed" || i)."""
    seeds = [sha256(b"sa4-oracle-seed" + bytes([i])) for i in range(n)]
    text = ROSTER_HEADER + "\n" + "".join("%d o%d %s\n" % (10 * (i + 1), i + 1, ed25519_pk_from_seed(sd).hex())
                                          for i, sd in enumerate(seeds))
    return roster_parse(text), seeds


def o_round(ro, seeds, r, lw, drop_after=(), faults=None, harness=False):
    """Run Python souls (all of U1 = roster) through one round.
    drop_after: x's that leave after their Y (in U2, not U3).
    -> dict(advs, ys, reveals, u2, u3, inputs, refused)."""
    faults = faults or {}
    lay = h_layout()
    souls = {}
    for e in ro.entries:
        x = e[4]
        rng = h_rng(e[0], r) if harness else TestRng(b"sa4-oracle" + be(e[0], 4) + be(r, 8))
        s = Soul(ro, seeds[x - 1], rng, 0, e)
        f = faults.get(x)
        if isinstance(f, dict):
            s.f3 = dict(f)
        else:
            s.fault = f
        s.set_input(h_input(x - 1, lw), lay)
        souls[x] = s
    refused = {}

    def feed(x, lines):
        outs = []
        for ln in lines:
            ok, err, o = souls[x].handle(ln)
            outs += o
            if not ok:
                refused[ro.entries[x - 1][0]] = o[-1].split(" ")[-1] if o else "-"
                return None
        return outs
    rl = fmt_round(r, ro.fp, lw, lay)
    advl = [feed(x, [rl])[0] for x in sorted(souls)]
    u1 = sorted(souls)
    shares = []
    for x in u1:
        o = feed(x, advl + [fmt_set(r, 1, bitmap(u1))])
        shares += [l for l in o if l.startswith("SA4_SHARE ")]
    # v4-sa3 CHECK (no coordinator verdicts here): U2' = U1; every
    # complained-about soul is left out of the final U2.
    u2p = list(u1)
    complaints = {}
    for x in u2p:
        me = ro.entries[x - 1][0]
        o = feed(x, [l for l in shares if parse(l)[3] == me] + [fmt_set(r, 5, bitmap(u2p))])
        if o is None:
            continue
        for l in o:
            if l.startswith("SA4_COMPLAINT "):
                complaints.setdefault(me, []).append(parse(l)[3])
    accused = set(ro.x(a) for v in complaints.values() for a in v)
    u2 = [x for x in u2p if x not in accused and ro.entries[x - 1][0] not in refused]
    ys, u3 = {}, []
    for x in u2:
        me = ro.entries[x - 1][0]
        o = feed(x, [fmt_set(r, 2, bitmap(u2))])
        if o is None:
            continue
        ys[me] = [w for l in o if l.startswith("SA4_Y ") for w in parse(l)[5]]
        if x not in drop_after:
            u3.append(x)
    sigs = []
    for x in u3:
        sigs += feed(x, [fmt_set(r, 3, bitmap(u3))])
    reveals = {}
    for x in u3:
        o = feed(x, sigs + [fmt_set(r, 4, bitmap(u3))])
        reveals[ro.entries[x - 1][0]] = [parse(l) for l in o if l.startswith("SA4_REVEAL ")]
    return {"advs": {p[2]: p for p in map(parse, advl)}, "ys": ys, "reveals": reveals, "u2": u2, "u3": u3,
            "inputs": {ro.entries[x - 1][0]: h_input(x - 1, lw) for x in u1}, "refused": refused,
            "complaints": complaints}


def o_rebuild(ro, r, lw, rd, reveals=None):
    return coord_rebuild(ro, r, lw, rd["advs"], rd["ys"], rd["reveals"] if reveals is None else reveals,
                         rd["u2"], rd["u3"])


def o_expected(ro, rd, lw):
    out = [0] * lw
    for x in rd["u3"]:
        out = [(a + b) & M32 for a, b in zip(out, rd["inputs"][ro.entries[x - 1][0]])]
    return out


def o_lie(ro, rd, revealer_x, dealer_x, kind, xor=1, pos=0):
    """Copy of rd["reveals"] with one reveal's share byte altered (proof kept)."""
    w, u = ro.entries[revealer_x - 1][0], ro.entries[dealer_x - 1][0]
    out = {}
    for k, recs in rd["reveals"].items():
        new = []
        for p in recs:
            if k == w and p[3] == u and p[4] == kind:
                sh = bytearray(p[5]); sh[pos] ^= xor
                p = p[:5] + (bytes(sh),) + p[6:]
            new.append(p)
        out[k] = new
    return out


def oracle_selftest():
    """Coordinator-oracle scenarios; returns the number of checks."""
    k = 0
    # N = 4 harness souls, t = 3, |R| = 4 (one spare revealer).
    ro4 = h_roster(4)
    seeds4 = [bytes.fromhex(h) for h in H_SEEDS[:4]]
    lw = 6
    rd = o_round(ro4, seeds4, 5, lw, harness=True)
    exp = o_expected(ro4, rd, lw)
    assert not rd["refused"] and rd["u3"] == [1, 2, 3, 4]
    assert o_rebuild(ro4, 5, lw, rd) == (exp, [], None, ""); k += 1
    I4 = lambda x: ro4.entries[x - 1][0]
    # one bad b reveal (x1 about x2): correct sum, x1 excluded
    assert o_rebuild(ro4, 5, lw, rd, o_lie(ro4, rd, 1, 2, 0)) == (exp, [I4(1)], None, ""); k += 1
    # one liar about two dealers: excluded once, correct sum
    two = o_lie(ro4, {"reveals": o_lie(ro4, rd, 1, 2, 0)}, 1, 3, 0)
    assert o_rebuild(ro4, 5, lw, rd, two) == (exp, [I4(1)], None, ""); k += 1
    # a liar outside the first t (x4) is not looked at: correct sum, no exclusion
    assert o_rebuild(ro4, 5, lw, rd, o_lie(ro4, rd, 4, 2, 0)) == (exp, [], None, ""); k += 1
    # |R| - t + 1 = 2 liars about x3: refused
    # (xor 2 for the second: with xs 1,2,3 both Lagrange weights are 1, so two
    # equal errors would cancel and give the right b -- harmless, but no test)
    lie2 = o_lie(ro4, {"reveals": o_lie(ro4, rd, 1, 3, 0)}, 2, 3, 0, xor=2)
    got = o_rebuild(ro4, 5, lw, rd, lie2)
    assert got[0] is None and got[1] == [I4(1), I4(2)] and got[2] is None and "fewer than t" in got[3], got; k += 1
    # a truncated proof (x4): left out structurally, correct sum
    cut = dict(rd["reveals"])
    cut[I4(4)] = [p[:6] + (p[6][:-32],) for p in cut[I4(4)]]
    assert o_rebuild(ro4, 5, lw, rd, cut) == (exp, [], None, ""); k += 1
    # inconsistent dealer x1: no receiver refuses, rebuild blames x1
    rdi = o_round(ro4, seeds4, 5, lw, faults={1: "inconsistent-deal"}, harness=True)
    assert not rdi["refused"] and rdi["u3"] == [1, 2, 3, 4]
    got = o_rebuild(ro4, 5, lw, rdi)
    assert got[0] is None and got[1] == [] and got[2] == I4(1) and "dealt shares" in got[3], got; k += 1
    # bad-commit-share from x1: its lowest other receiver (x2) complains
    # (v4-sa3: no refusal); x1 left out of U2, the sum over x2..x4 is correct
    rdc = o_round(ro4, seeds4, 5, lw, faults={1: "bad-commit-share"}, harness=True)
    assert rdc["refused"] == {} and rdc["complaints"] == {I4(2): [I4(1)]}, (rdc["refused"], rdc["complaints"])
    assert rdc["u2"] == [2, 3, 4] and o_rebuild(ro4, 5, lw, rdc) == (o_expected(ro4, rdc, lw), [], None, ""); k += 1
    # N = 7 (t = 5), x4 drops after its Y: |U3| = 6, s of x4 rebuilt.
    ro7, seeds7 = o_roster(7)
    rd7 = o_round(ro7, seeds7, 3, lw, drop_after=(4,))
    I7 = lambda x: ro7.entries[x - 1][0]
    exp7 = o_expected(ro7, rd7, lw)
    assert rd7["u3"] == [1, 2, 3, 5, 6, 7] and not rd7["refused"]
    assert o_rebuild(ro7, 3, lw, rd7) == (exp7, [], None, ""); k += 1
    # bad s reveal (x1 about x4) with the dropout: correct sum, x1 excluded
    assert o_rebuild(ro7, 3, lw, rd7, o_lie(ro7, rd7, 1, 4, 1)) == (exp7, [I7(1)], None, ""); k += 1
    # clamped-bit s error: the rebuilt s differs only in bit 0 of byte 0
    lam = lagrange0([1, 2, 3, 5, 6])
    clamp = o_lie(ro7, rd7, 1, 4, 1, xor=gf_inv(lam[0]))
    cs = [(x, next(p[5] for p in clamp[I7(x)] if p[3] == I7(4) and p[4] == 1)) for x in (1, 2, 3, 5, 6)]
    s_alt = shamir_combine(cs, 32)
    assert s_alt != shamir_combine([(x, next(p[5] for p in rd7["reveals"][I7(x)] if p[3] == I7(4)))
                                    for x in (1, 2, 3, 5, 6)], 32)
    assert o_rebuild(ro7, 3, lw, rd7, clamp) == (exp7, [], None, ""); k += 1
    # one liar about an s-secret (x4) and a b-secret (x5): excluded once
    both = o_lie(ro7, {"reveals": o_lie(ro7, rd7, 1, 4, 1)}, 1, 5, 0)
    assert o_rebuild(ro7, 3, lw, rd7, both) == (exp7, [I7(1)], None, ""); k += 1
    # two liars about different dealers: the global exclusion leaves |R| - 2 < t
    # candidates for the second dealer -> refused
    two7 = o_lie(ro7, {"reveals": o_lie(ro7, rd7, 1, 4, 1)}, 2, 5, 0)
    got = o_rebuild(ro7, 3, lw, rd7, two7)
    assert got[0] is None and got[1] == [I7(1), I7(2)] and got[2] is None, got; k += 1
    # lazy verification, N = 7 with no dropout (|R| = 7): liars x1 (inside
    # the first t) and x7 (after the t-th verified share) about x3. Proofs
    # are checked only until t verify, so only x1 is excluded.
    rd7f = o_round(ro7, seeds7, 4, lw)
    exp7f = o_expected(ro7, rd7f, lw)
    assert rd7f["u3"] == [1, 2, 3, 4, 5, 6, 7] and not rd7f["refused"]
    lazy = o_lie(ro7, {"reveals": o_lie(ro7, rd7f, 1, 3, 0)}, 7, 3, 0)
    assert o_rebuild(ro7, 4, lw, rd7f, lazy) == (exp7f, [I7(1)], None, ""); k += 1
    return k


# ============================================================ harness replay
H_IDS = [7, 300, 65536, 70000, 4294967295]
H_SEEDS = ["9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60",
           "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb",
           "c5aa8df43f9f837bedb7442f31dcb7b166d38535076f094b85ce3a2e0b4458f7",
           "f5e5767cf153319517630f226876b86c8160cc583bc013744c6bf255f5cc0ee5",
           "833fe62409237b9d62ec77587520911e9a759cec1d19755b7da901b96dca3d42"]
H_PKS = ["d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a",
         "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c",
         "fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025",
         "278117fc144c72340f67d0f2316e8386ceffbf2b2428c9c51fef7c597f1d426e",
         "ec172b93ad5e563bf4932c70e1245034c35467ef2efd4d64ebf819683467e2bf"]
H_L = 150


def h_roster(n):
    return roster_parse(ROSTER_HEADER + "\n" + "".join("%d s%d %s\n" % (H_IDS[i], i + 1, H_PKS[i]) for i in range(n)))


def h_layout():
    return sha256(b"sa4 test layout v1")


def h_input(i, lw):
    return [((i + 1) * 1000003 + k * 7919 + 4000000000) & M32 for k in range(lw)]


def h_rng(i, r):
    return TestRng(b"sa4-test" + be(i, 4) + be(r, 8))


def h_run3(n, r, last, drop_before, drop_after, drop_sig):
    """Mirror of sa4h_run3 (tests/sa4_harness.nova) -> (advs, all)."""
    ro = h_roster(n)
    souls = []
    for i in range(n):
        e = ro.entries[i]
        s = Soul(ro, bytes.fromhex(H_SEEDS[i]), h_rng(e[0], r), last, e)
        s.set_input(h_input(i, H_L), h_layout())
        souls.append(s)

    def feed(s, lines):
        outs = []
        for ln in lines:
            ok, err, o = s.handle(ln)
            outs += o
            if not ok:
                raise RuntimeError(err)
        return outs

    rl = fmt_round(r, ro.fp, H_L, h_layout())
    advs = []
    for s in souls:
        advs += feed(s, [rl])
    allv = []
    set1 = fmt_set(r, 1, bitmap(range(1, n + 1)))
    shares, u2 = [], []
    for i, s in enumerate(souls):
        o = feed(s, advs + [set1])
        allv += o
        if i != drop_before:
            shares += [l for l in o if l.startswith("SA4_SHARE ")]
            u2.append(i + 1)
    # v4-sa3 CHECK: U2' = u2; per soul (ascending x) its shares + SET 5, then
    # at once (an honest round has no complaint) the final SET 2 (as
    # sa4h_run3 in tests/sa4_harness.nova).
    set5 = fmt_set(r, 5, bitmap(u2))
    set2 = fmt_set(r, 2, bitmap(u2))
    u3 = []
    for x in u2:
        me = ro.entries[x - 1][0]
        allv += feed(souls[x - 1], [l for l in shares if parse(l)[3] == me] + [set5])
        o = feed(souls[x - 1], [set2])
        allv += o
        if x - 1 != drop_after:
            u3.append(x)
    set3 = fmt_set(r, 3, bitmap(u3))
    sigs, u4 = [], []
    for x in u3:
        o = feed(souls[x - 1], [set3])
        allv += o
        if x - 1 != drop_sig:
            sigs += o
            u4.append(x)
    set4 = fmt_set(r, 4, bitmap(u4))
    for x in u4:
        allv += feed(souls[x - 1], sigs + [set4])
    return ro, advs, allv


SCEN = {"A": (3, 5, 4, -1, -1, -1), "B": (5, 9, 0, -1, 2, -1), "C": (4, 11, 0, 0, -1, -1),
        "D": (5, 13, 0, -1, -1, 1)}


# ---- v4-sa3 harness rounds with the coordinator oracle (section 15):
# N = 5 harness roster, r = 13, last 0, L = 150, rng h_rng(id, 13).
def _flip_last_hex(line):
    return line[:-1] + ("0" if line[-1] != "0" else "1")


def _round_i_tamper(ph, msgs):
    """Round I: the routed line 4294967295 -> 7 altered on 7's downlink."""
    return [(to, _flip_last_hex(l) if ph == C_SHARES and to == 7 and l.startswith("SA4_SHARE 13 4294967295 7 ")
             else l) for to, l in msgs]


def _round_kl_tamper(ph, msgs):
    """Rounds K, L: nothing reaches 70000 after its ADV (in U1, left out of
    U2' at the shares close: "share batch incomplete")."""
    return [(to, l) for to, l in msgs if to != 70000]


H_ROUNDS = {
    "F": ({5: {1: "garbage"}}, None),                       # 4294967295 sends 7 garbage: code 1
    "G": ({3: {"false": {1}}}, None),                       # 65536 complains falsely about 7: code 2
    "H": ({5: {1: "garbage", "silent": 1}}, None),          # as F, accused silent: code 3
    "I": ({}, _round_i_tamper),                             # downlink tamper: 7 code 5
    "J": ({5: {1: "garbage", "badsig": 1}}, None),          # as F plus bad SHSIG: code 4
    "P": ({}, None),                                        # plain
    # U1 != U2' (70000 silent after its ADV): the evidence covers U1
    "K": ({5: {1: "garbage"}}, _round_kl_tamper),           # as F: code 1, then |U2| 3 < t
    "L": ({3: {"false": {1}}}, _round_kl_tamper),           # as G: code 2, then |U2| 3 < t
}


def h_round(name):
    """Run harness round F..J / P (souls + coordinator oracle) -> Net."""
    faults, tam = H_ROUNDS[name]
    ro = h_roster(5)
    net = Net(ro, [bytes.fromhex(h) for h in H_SEEDS[:5]], 13, H_L, faults=faults,
              rngf=lambda e: h_rng(e[0], 13), last=0)
    net.tamper = tam
    return net.run()


def h_round_lines(name):
    """Dump lines of round F..J / P: header, ADV / OUT (soul output in
    delivery order), BLAME <id> <code> <why>, EVIDENCE <id> <bytes> <sha256>."""
    net = h_round(name)
    C = net.C
    tot = net.result()
    ok = 1 if C.st == C_READY else 0
    head = "#%s ok=%d sum_ok=%d state=%d u2=%s counters=%s" % (
        name, ok, 1 if tot is not None and tot == net.expected() else 0, C.st,
        ",".join(str(C.I(x)) for x in C.u2), ",".join(str(k) for k in C.counters()))
    out = [head]
    for to, l in net.all_lines:
        out.append(("ADV " if l.startswith("SA4_ADV ") else "OUT ") + l)
    for i, code in sorted(C.codes().items()):
        out.append("BLAME %d %d %s" % (i, code, C.why(i)))
    for i, text in sorted(C.evidence.items()):
        out.append("EVIDENCE %d %d %s" % (i, len(text), sha256(text.encode("ascii")).hex()))
    if tot is not None:
        out.append("#SUM " + sha256(b"".join(be(w, 4) for w in tot)).hex())
    return out


def refusal_lines():
    """The 21 refusal cases of sa4_dump.nova E, as 'CASE k ok=.. last=..' lines."""
    ro = h_roster(3)
    lay = h_layout()
    rl = fmt_round(5, ro.fp, H_L, lay)

    def fresh(i):
        e = ro.entries[i]
        s = Soul(ro, bytes.fromhex(H_SEEDS[i]), h_rng(e[0], 5), 4, e)
        s.set_input(h_input(i, H_L), lay)
        return s
    advs = [fresh(i).handle(rl)[2][0] for i in range(3)]
    fpx = bytes([ro.fp[0] ^ 1]) + ro.fp[1:]
    a1 = parse(advs[1])
    g = bytearray(a1[5]); g[5] ^= 1
    bm = lambda xs: bitmap(xs)
    cases = [[fmt_round(5, fpx, H_L, lay)], [fmt_round(4, ro.fp, H_L, lay)], [fmt_round(5, ro.fp, H_L + 1, lay)],
             [fmt_round(5, ro.fp, H_L, fpx)], ["SA4_ROUND 05 x"], [rl, fmt_set(5, 2, bm([1, 2, 3]))],
             [rl, fmt_set(6, 1, bm([1, 2, 3]))],
             [rl, advs[0], fmt_adv(5, a1[2], a1[3], a1[4], bytes(g), a1[6], a1[7]), advs[2], fmt_set(5, 1, bm([1, 2, 3]))],
             [rl] + advs + [fmt_set(5, 1, bm([1, 2, 3, 4]))], [rl, advs[0], advs[1], fmt_set(5, 1, bm([1, 2, 3]))],
             [rl] + advs + [advs[2], fmt_set(5, 1, bm([1, 2, 3]))]]
    # v4-sa2: own ADV relayed back with B (then M) altered, a peer ADV with M
    # altered under its original signature, and a v1 (6-token) ADV.
    a0 = parse(advs[0])
    flip = lambda b, i, m: b[:i] + bytes([b[i] ^ m]) + b[i + 1:]
    cases.append([rl, fmt_adv(5, a0[2], a0[3], a0[4], a0[5], flip(a0[6], 0, 1), a0[7]), advs[1], advs[2], fmt_set(5, 1, bm([1, 2, 3]))])
    cases.append([rl, fmt_adv(5, a0[2], a0[3], a0[4], a0[5], a0[6], flip(a0[7], 31, 128)), advs[1], advs[2], fmt_set(5, 1, bm([1, 2, 3]))])
    cases.append([rl, advs[0], fmt_adv(5, a1[2], a1[3], a1[4], a1[5], a1[6], flip(a1[7], 0, 1)), advs[2], fmt_set(5, 1, bm([1, 2, 3]))])
    cases.append([rl, advs[0], "SA4_ADV 5 %d %s %s %s" % (a1[2], a1[3].hex(), a1[4].hex(), a1[5].hex()), advs[2], fmt_set(5, 1, bm([1, 2, 3]))])
    # v4-sa3 (cases 15..20): SET 2 in SHARED, a 5-token (v4-sa2) SHARE,
    # ACCUSE naming the receiver, two complaints from one soul, a final U2
    # containing a complained-about soul, ACCUSE twice.
    set1, set5, set2 = fmt_set(5, 1, bm([1, 2, 3])), fmt_set(5, 5, bm([1, 2, 3])), fmt_set(5, 2, bm([1, 2, 3]))

    def share_to_7(i):
        s = fresh(i)
        outs = []
        for ln in [rl] + advs + [set1]:
            outs += s.handle(ln)[2]
        return next(l for l in outs if l.startswith("SA4_SHARE ") and parse(l)[3] == 7)
    sh2, sh3 = share_to_7(1), share_to_7(2)
    p2 = parse(sh2)
    cpl = fmt_complaint(5, 300, 7, bytes([11]) * 32, bytes(64))
    pre = [rl] + advs + [set1, sh2, sh3, set5]
    cases.append([rl] + advs + [set1, sh2, sh3, set2])
    cases.append([rl] + advs + [set1, " ".join(sh2.split(" ")[:4] + sh2.split(" ")[5:])])
    cases.append(pre + [fmt_accuse(5, bm([1]))])
    cases.append(pre + [cpl, cpl, fmt_accuse(5, bm([2, 3]))])
    cases.append([rl] + advs + [set1, fmt_share(5, 300, 7, garbage(p2[4]), p2[5]), sh3, set5, set2])
    cases.append(pre + [cpl, fmt_accuse(5, bm([2])), fmt_accuse(5, bm([2]))])
    got = []
    for k, c in enumerate(cases):
        s = fresh(0)
        outs, ok, err = [], 1, ""
        for ln in c:
            o_ok, o_err, o = s.handle(ln)
            outs += o
            if not o_ok:
                ok, err = 0, o_err
                break
        got.append("CASE %d ok=%d last=%s" % (k, ok, outs[-1] if outs else "(none)"))
    return got


def refusal_cases(dump):
    got = refusal_lines()
    want = [l.split(" err=")[0] for l in open(dump) if l.startswith("CASE ")]
    for a, b in zip(got, want):
        print(("SAME " if a == b else "DIFF ") + a[:110] + ("" if a == b else "\n     nova: " + b[:110]))
    return 0 if got == want else 1


def harness_compare(which, dump):
    if which == "E":
        return refusal_cases(dump)
    if which in H_ROUNDS:
        # ADV / OUT lines always; BLAME / EVIDENCE lines when the dump has any.
        mine = h_round_lines(which)
        dl = [l.rstrip("\n") for l in open(dump)]
        pre = ["ADV ", "OUT "] + [k for k in ("BLAME ", "EVIDENCE ") if any(l.startswith(k) for l in dl)]
        got = [l for l in mine if l.startswith(tuple(pre))]
        want = [l for l in dl if l.startswith(tuple(pre))]
    else:
        ro, advs, allv = h_run3(*SCEN[which])
        got = ["ADV " + l for l in advs] + ["OUT " + l for l in allv]
        want = [l.rstrip("\n") for l in open(dump) if l.startswith(("ADV ", "OUT "))]
    fpl = [l for l in open(dump) if l.startswith("#FP ")] if which == "A" else []
    if fpl:
        print("fingerprint", "MATCH" if fpl[0].split()[1] == h_roster(3).fp.hex() else "DIFF")
    same = sum(1 for a, b in zip(got, want) if a == b)
    print("scenario %s: python %d lines, nova %d lines, identical prefix-aligned %d" % (which, len(got), len(want), same))
    for a, b in zip(got, want):
        if a != b:
            print("FIRST DIFF\n  py  : %s\n  nova: %s" % (a[:160], b[:160]))
            break
    return 0 if got == want else 1


# ============================================================ v4-sa2 pins
KAT_FP = bytes(range(32))
KAT_R = 7
KAT_U = 300


def kat_shares(n):
    """KAT vector: s-share of x = [x]*32, b-share of x = [255 - x]*32."""
    return [(x, bytes([x]) * 32) for x in range(1, n + 1)], [(x, bytes([255 - x]) * 32) for x in range(1, n + 1)]


def pin_lines():
    """The v4-sa2 known answers (tree KATs, transcripts) as 'PIN name hex' lines."""
    out = ["# vector: fp = 00 01 .. 1f, r = 7, u = 300; s-share(x) = [x]*32, b-share(x) = [255-x]*32,"
           " b = [0x42]*32; tree pins: D, root, path of x = N and of x = 1 (path[0] first, concatenated)"]
    fp, r, u = KAT_FP, KAT_R, KAT_U
    out.append("PIN hs_1 " + h_sshare(fp, r, u, 1, bytes([1]) * 32).hex())
    out.append("PIN hb_1 " + h_bshare(fp, r, u, 1, bytes([254]) * 32).hex())
    out.append("PIN leaf_1 " + share_leaf(fp, r, u, 1, bytes([1]) * 32, bytes([254]) * 32).hex())
    out.append("PIN bcommit " + b_commit(fp, r, u, bytes([0x42]) * 32).hex())
    for n in (2, 3, 5, 255):
        d = depth(n)
        ssh, bsh = kat_shares(n)
        lv = deal_tree(fp, r, u, ssh, bsh, d)
        out.append("PIN tree_n%d_d %d" % (n, d))
        out.append("PIN tree_n%d_root %s" % (n, lv[-1][0].hex()))
        out.append("PIN tree_n%d_path_x%d %s" % (n, n, b"".join(tree_path(lv, n - 1)).hex()))
        out.append("PIN tree_n%d_path_x1 %s" % (n, b"".join(tree_path(lv, 0)).hex()))
    # transcripts: id = 300, L = 150, layout = h_layout(), c/s/B/M = [1]/[2]/[3]/[4]*32
    k1 = tuple(bytes([v]) * 32 for v in (1, 2, 3, 4))
    k2 = tuple(bytes([v]) * 32 for v in (5, 6, 7, 8))
    tr = adv_transcript(fp, r, 300, H_L, h_layout(), *k1)
    out.append("PIN adv_transcript_len %d" % len(tr))
    out.append("PIN adv_transcript " + tr.hex())
    out.append("PIN adv_transcript_sha256 " + sha256(tr).hex())
    h1 = advset_hash(bitmap([1, 2]), [k1, k2])
    out.append("PIN h1_u1_12 " + h1.hex())
    out.append("PIN t3_sha256 " + sha256(t3_transcript(fp, r, h1, bitmap([1, 2]), bitmap([1, 2]))).hex())
    spt = share_pt(300, 7, r, 2, bytes([0x11]) * 32, bytes([0x22]) * 32, [bytes([0x33]) * 32, bytes([0x44]) * 32])
    out.append("PIN share_pt_n3 " + spt.hex())
    # reveal proofs of the N = 3 tree for x = 2: kind b and kind s
    ssh, bsh = kat_shares(3)
    lv = deal_tree(fp, r, u, ssh, bsh, 2)
    pth = tree_path(lv, 1)
    out.append("PIN reveal_n3_x2_b " + reveal_proof(fp, r, u, 2, 0, ssh[1][1], bsh[1][1], pth).hex())
    out.append("PIN reveal_n3_x2_s " + reveal_proof(fp, r, u, 2, 1, ssh[1][1], bsh[1][1], pth).hex())
    return out + sa3_pin_lines()


def sa3_pin_lines():
    """The v4-sa3 vectors of SPEC section 15 (K1..K9, harness rounds F-J, P)."""
    fp = KAT_FP
    B = lambda v: bytes([v]) * 32
    out = ["# v4-sa3 (A2.4c): K1..K9 and harness rounds F, G, H, I, J, P (N = 5, r = 13, last 0, L = 150)"]
    e = eph(B(14), 7, 300, 65536)
    out.append("PIN k1_eph " + e.hex())
    out.append("PIN k2_epk " + x25519_base(e).hex())
    out.append("PIN k3_sleaf " + sleaf(fp, 7, 300, 3, 65536, B(12), bytes([13]) * 162).hex())
    out.append("PIN k4_share_root_n5 " + share_levels(5, depth(5), {2: B(1), 3: B(2), 4: B(3), 5: B(4)})[-1][0].hex())
    st = shares_transcript(fp, 7, 300, B(9), B(10))
    out.append("PIN k5_shares_transcript_len %d" % len(st))
    out.append("PIN k5_shares_transcript_sha256 " + sha256(st).hex())
    ct = complaint_transcript(fp, 7, 65536, 300, B(9), B(11))
    out.append("PIN k6_complaint_transcript_len %d" % len(ct))
    out.append("PIN k6_complaint_transcript_sha256 " + sha256(ct).hex())
    adv = adv_transcript(fp, 7, 300, 150, h_layout(), B(1), B(2), B(3), B(4))
    out.append("PIN k7_adv_v3_sha256 " + sha256(adv).hex())
    g = garbage(bytes(162))
    out.append("PIN k8_garbage_sha256 " + sha256(g).hex())
    out.append("PIN k8_garbage_16 " + g[:16].hex())
    hro = h_roster(5)
    s7 = Soul(hro, bytes.fromhex(H_SEEDS[0]), h_rng(7, 13), 0, hro.entries[0])
    s7.set_input(h_input(0, H_L), h_layout())
    s7.handle(fmt_round(13, hro.fp, H_L, h_layout()))
    e7 = eph(s7.eseed, 13, 7, 300)
    out.append("PIN k9_eseed_7_r13 " + s7.eseed.hex())
    out.append("PIN k9_e_7_300 " + e7.hex())
    out.append("PIN k9_epk_7_300 " + x25519_base(e7).hex())
    for name in "FGHIJP":
        net = h_round(name)
        C = net.C
        tot = net.result()
        out.append("PIN round_%s_codes %s" % (name, ",".join("%d:%d" % kv for kv in sorted(C.codes().items())) or "-"))
        out.append("PIN round_%s_u2 %s" % (name, ",".join(str(C.I(x)) for x in C.u2)))
        out.append("PIN round_%s_counters %s" % (name, ",".join(str(k) for k in C.counters())))
        out.append("PIN round_%s_sum_sha256 %s" % (name, sha256(b"".join(be(w, 4) for w in tot)).hex()
                                                    if tot is not None else "-"))
        lines = [l for _, l in net.all_lines]
        for tag, pfx in (("complaint", "SA4_COMPLAINT "), ("open", "SA4_OPEN ")):
            got = [l for l in lines if l.startswith(pfx)]
            out.append("PIN round_%s_%s_sha256 %s" % (name, tag, sha256("\n".join(got).encode()).hex() if got else "-"))
        for i, code in sorted(C.codes().items()):
            out.append("PIN round_%s_why_%d_sha256 %s" % (name, i, sha256(C.why(i).encode()).hex()))
        for i, text in sorted(C.evidence.items()):
            out.append("PIN round_%s_evidence_%d_len %d" % (name, i, len(text)))
            out.append("PIN round_%s_evidence_%d_sha256 %s" % (name, i, sha256(text.encode()).hex()))
        if name == "P":
            out.append("PIN round_P_h1 " + C.h1.hex())
            out.append("PIN round_P_s7 " + net.S[7].sroot.hex())
            sl = [l for to, l in net.all_lines if to == 7 and l.startswith("SA4_SHARE ")][0]
            out.append("PIN round_P_share_7_300_len %d" % len(sl))
            out.append("PIN round_P_share_7_300_sha256 " + sha256(sl.encode()).hex())
            out.append("PIN round_P_shsig_7 " + [l for to, l in net.all_lines
                                                if to == 7 and l.startswith("SA4_SHSIG ")][0].split(" ")[3])
    return out


# SPEC section 15 literal values (single tokens), checked by --selftest.
SA3_PINS = {
    "k1_eph": "2a6fb16b824d2eb89fb3938d1653fd71ed19046646ccf5efc2b973e0afe987d4",
    "k2_epk": "19c84ab13a138f54b813bfa5c5260c43bf8cf49d06ca8321a26b8739c9851924",
    "k3_sleaf": "de12c14647d745a5d76f797f9861de08ab5ba803fd89438c5307d1bbc4adf225",
    "k4_share_root_n5": "d84e8f937c944f5d86b1ccb7c6acc6b0dc56dba8545874230940a057fc99ab9c",
    "k5_shares_transcript_len": "138",
    "k5_shares_transcript_sha256": "fcabfcf49bd21049cf9a8cadd8cbe60d9d0665506942a59448d95f13bacb3437",
    "k6_complaint_transcript_len": "145",
    "k6_complaint_transcript_sha256": "2d67c4b49a0de7573dfa4db43836c8256d6215bee38f6a2c955e1c5024336af9",
    "k7_adv_v3_sha256": "c745c7942d938a41cc13b5adc36287c254bfde40566c0f7050fd07630a0c9ff9",
    "k8_garbage_sha256": "f4b04e6ec606faa8cf511c53a337c6ff58ae0b183a8b0675e03b2701f19ec243",
    "k8_garbage_16": "59faa26b2045ebe113270dcc877ccf50",
    "k9_eseed_7_r13": "1c877af76e30246684df075a75dbfa6486f58e856ef944441f32c0cd90b65b72",
    "k9_e_7_300": "2a522e22a02179ca3f06c7ed6d0f087c1ea62a4999222c2858438091ae11a382",
    "k9_epk_7_300": "387ce9af5f678e69955e2fca71238c11bfdff07ba9d2caa2aa1531d6a10d864a",
    "round_P_codes": "-", "round_P_u2": "7,300,65536,70000,4294967295", "round_P_counters": "0,0,0,0",
    "round_P_h1": "b790829fd8824f8876f83342084d9d1ec4b7339000595034d1278317f85b8ad5",
    "round_P_s7": "9bca948c77fdce96b8617af47d058f20490ad1b24f9425ba594337b272ebf192",
    "round_P_share_7_300_len": "472",
    "round_P_share_7_300_sha256": "915c92c61297c0d4a491292144673cc2db5ee75fac4688bc0c99337d7a2c2011",
    "round_P_shsig_7": "b120d4cefb0386603a74a8035e688743869c162b6f8b1d3cf671b2e96794a506"
                       "c6a0633e48ca3e65ffe3134c12718bfd814652619d2ca45024ed3af76220bc0c",
    "round_P_sum_sha256": "ad504de5aafeadff232fe7ff4b20c22448f9acd710f8fb466a99e4fe17ac5818",
    "round_F_codes": "4294967295:1", "round_F_u2": "7,300,65536,70000",
    "round_F_evidence_4294967295_len": "2682",
    "round_F_evidence_4294967295_sha256": "a4aa559d2ffdf5d839e25d218b331c725eee5ad630eec8ca655c92dc68f6e556",
    "round_F_sum_sha256": "6b6ae2e32cd96e84501ec09392e0919e0e0334f34b5548091bd82664d44f1a52",
    "round_G_codes": "65536:2", "round_G_u2": "7,300,70000,4294967295", "round_G_evidence_65536_len": "2349",
    "round_G_evidence_65536_sha256": "cde1d077e3ec278046be151992ec1ce9482f1ad2c6982bec2ca191841c526c3b",
    "round_G_sum_sha256": "36c6cac61e4177e5115f0daffca73ff17234fd311e840fe864d51aabf8e0032b",
    "round_H_codes": "4294967295:3", "round_H_open_sha256": "-",
    "round_H_sum_sha256": "6b6ae2e32cd96e84501ec09392e0919e0e0334f34b5548091bd82664d44f1a52",
    "round_I_codes": "7:5", "round_I_u2": "300,65536,70000,4294967295", "round_I_open_sha256": "-",
    "round_I_sum_sha256": "d0a1e8961b9dda9606a84f78ab1f0d6dcfef768a0fe608307c23fe4cedd974b7",
    "round_J_codes": "4294967295:4",
    "round_J_sum_sha256": "6b6ae2e32cd96e84501ec09392e0919e0e0334f34b5548091bd82664d44f1a52",
}
# SPEC section 15 lines and why texts, checked verbatim by --selftest.
_C_F = ("SA4_COMPLAINT 13 7 4294967295 1982ce8c421f2de75974893a2e6c5b6571ccd3e458a66207c46553fc62456e7d "
        "f9b728b867253b294da615aa90e60784299d4efebddf7edff450c075f4f774f1b8afdd260479579cfc219b6ad77c768f49"
        "b17bf4e367e33d1c357ba0817ac709")
_O_F = "SA4_OPEN 13 4294967295 7 29b6fd379c68f018417d5e6ceaca1cf67d0591c8632ae31258fd71e2c229da38"
SA3_ROUNDS = {
    "F": ([_C_F, "SA4_END 13 4 7 1", _O_F, "SA4_END 13 5 4294967295 1"],
          {4294967295: "proven: sent soul 7 a share that fails the open check"}),
    "G": (["SA4_COMPLAINT 13 65536 7 be303983092904aee8aacaa3d1a9f0ca7eacb93927dc384a8d01fe5476885b33 "
           "e30574093f8f6dd24a7e357a5a55f688fe4ffce98672e887e4f2dc69e18a429c3df4fffa74513954dcf38df1d0122399"
           "8cecc5aa25e2ee54e8fb81f0f9f3680c",
           "SA4_OPEN 13 7 65536 b05ff3a1c45772e87e9e7f7c0256f40ed89891ef8ea3822b1af0ce63c14d8e5b",
           "SA4_END 13 5 7 1"],
          {65536: "proven: false complaint about soul 7 (the share opens and matches)"}),
    "H": ([_C_F, "SA4_END 13 5 4294967295 0"],
          {4294967295: "did not open its share to soul 7 with its one-time key (not proven)"}),
    "I": (["SA4_COMPLAINT 13 7 4294967295 008da9b870066f271dbd9d4326e4895591820d61d40bb4447e2784d63da74725 "
           "6b5d703fb997b7d45a541d65389278c6bc8823b8502c556e6d9a7986fff6dae25c51206d411c9102afcdf87b3d4e4935"
           "c5ae70e3922e03d265ed4a48ded2fc07", "SA4_END 13 5 4294967295 0"],
          {7: "complaint about soul 4294967295 names a share it was not sent (not proven)"}),
    "J": ([_C_F, _O_F, "SA4_END 13 5 4294967295 1"],
          {4294967295: "share signature does not verify over the shares it sent (not proven)"}),
    "P": (["SA4_END 13 4 7 0", "SA4_END 13 4 4294967295 0",
           "SA4_SHARE 13 7 300 387ce9af5f678e69955e2fca71238c11bfdff07ba9d2caa2aa1531d6a10d864a a80fec5c451f3a"
           "259a498351e7ea4118359c089c4a379197a21aadd44c8f969aa5122c154408e77df52b090f95005fdbac39aab4abe8ae98"
           "5558ab3407a6aef939962daa6f783aa60e2d53b990e21041c46934210ab7e31c0b30366a9f87681f34088faf8fce48622"
           "69a6ed2e64228beb8b11af6eb45dfd7089ce9d0096740d96035593782e7b604ba8f5bb76a6cb036a0578d01afdf45a82"
           "1f413d01ae268ae49c48f6fea92576f52404246686294da1ff49fbcb65b0f5c0f2dff452fcdcc3d52a7"], {}),
}
# harness A-D: the SA4_Y lines of v4-sa2 (sha256 over the lines joined by
# newlines); eseed is the last rng draw, so v4-sa3 keeps them.
Y_PINS = {"A": (6, "4431f209b457489171587094cafb93e326f11ca906d2de158d83e8a5ca785a89"),
          "B": (10, "65d5d7ca006f3404a0451e75860629759db6e434cd48696f524732bec11f1da6"),
          "C": (6, "ab7bdd08b1bcaf9b4e065f894a7641cf4aa24f4a888590ca968c6c96962fb492"),
          "D": (10, "4ee256519adae3ec6d3c794583f59a9f40d34a4ea14950e7b589cc5964013a88")}


def pins_selftest():
    """Tree properties and the pinned values; returns the pin lines."""
    fp, r, u = KAT_FP, KAT_R, KAT_U
    assert [depth(n) for n in (2, 3, 4, 5, 8, 9, 10, 16, 17, 255)] == [1, 2, 2, 3, 3, 4, 4, 4, 5, 8]
    for n in (2, 3, 5, 8, 255):
        d = depth(n)
        ssh, bsh = kat_shares(n)
        lv = deal_tree(fp, r, u, ssh, bsh, d)
        root = lv[-1][0]
        assert len(lv[0]) == 1 << d and all(lf == bytes(32) for lf in lv[0][n:])
        for i in range(1 << d):              # every position, padding included
            assert path_fold(lv[0][i], i, tree_path(lv, i)) == root
            if n <= 8 and i < n:             # the index bit matters (real leaves)
                for b in range(d):
                    assert path_fold(lv[0][i], i ^ (1 << b), tree_path(lv, i)) != root
        for x in ([1, 2, n] if n > 8 else range(1, n + 1)):
            sh_s, sh_b, pth = ssh[x - 1][1], bsh[x - 1][1], tree_path(lv, x - 1)
            pb = reveal_proof(fp, r, u, x, 0, sh_s, sh_b, pth)
            ps = reveal_proof(fp, r, u, x, 1, sh_s, sh_b, pth)
            assert reveal_proof_ok(fp, r, u, x, 0, sh_b, pb, root, d)
            assert reveal_proof_ok(fp, r, u, x, 1, sh_s, ps, root, d)
            assert not reveal_proof_ok(fp, r, u, x, 1, sh_b, pb, root, d)   # b proof used as s proof
            assert not reveal_proof_ok(fp, r, u, x, 0, sh_s, ps, root, d)   # and the reverse
            assert not reveal_proof_ok(fp, r, u, x, 0, sh_b, pb[:-32], root, d)
            assert not reveal_proof_ok(fp, r, u, x, 0, sh_b, pb + bytes(32), root, d)
            assert not reveal_proof_ok(fp, r, u, x, 0, bytes([sh_b[0] ^ 1]) + sh_b[1:], pb, root, d)
            if x < n:
                assert not reveal_proof_ok(fp, r, u, x + 1, 0, sh_b, pb, root, d)  # another x
            hs, hb = h_sshare(fp, r, u, x, sh_s), h_bshare(fp, r, u, x, sh_b)
            assert path_fold(node_hash(hs, hb), x - 1, pth) != root      # leaf hashed as a node
            assert path_fold(sha256(hs + hb), x - 1, pth) != root        # no prefix
            assert path_fold(leaf_hash(hb, hs), x - 1, pth) != root      # order hs, hb
        if d >= 2:                           # an inner node presented as a leaf at depth d-1
            assert path_fold(lv[1][0], 0, tree_path(lv, 0)[1:]) == root
    pl = pin_lines()
    vals = dict(l.split(" ")[1:3] for l in pl if l.startswith("PIN "))
    for k, v in list(PINS.items()) + list(SA3_PINS.items()):
        assert vals[k] == v, "pin " + k
    assert sha256("\n".join(pl).encode("ascii")).hex() == PINS_ALL, "pin file digest"
    return pl


PINS = {
    "hs_1": "dedb8985274c2034269288c11171cf2af47351a1ad96910667a1cf40ddc98e54",
    "hb_1": "5b5dec45f421070478331ddf151614a7d0d72669ec3c412bc32a88d683410c8f",
    "leaf_1": "32499f0776218cb385e0bc12889a2a756688e1171876503f505f773865b8b4cd",
    "bcommit": "b2943cc0a9bb4d9292f868a29a56b8006ae2b337a7e4e8880a1a0bc8726d5c0d",
    "tree_n2_root": "0b88dab2d65003c3d8c2eaa1444b067900408cd414ce2ea4a020e429bc88d198",
    "tree_n3_root": "0527c3401851a7b47fccb649a4b5828daad1d7971b6e195d509a4e76846ee7d7",
    "tree_n5_root": "ed9dfe68f8ea4897ca1501c80600c347c52183cc3cf8596c47ff389b46365077",
    "tree_n255_root": "a5265bbbc439d2192f473172c1eb8eb8e77822f634cfe2f1fcd43f2b26ad573e",
    "adv_transcript_sha256": "c745c7942d938a41cc13b5adc36287c254bfde40566c0f7050fd07630a0c9ff9",   # v3 SIG domain
    "h1_u1_12": "5301bba390762bc4105514164ce503fe8a6b01c58a234f67c587bae1bc20612c",
    "t3_sha256": "64ad326ee74596fc30c60e5b97d89b2dead841998a434791aac81cd427f93f0d",               # v3 SIG domain
    "share_pt_n3": "020000012c000000070000000000000007021111111111111111111111111111111111111111111111111111111111111111222222222222222222222222222222222222222222222222222222222222222233333333333333333333333333333333333333333333333333333333333333334444444444444444444444444444444444444444444444444444444444444444",
}
PINS_ALL = "6b42dec6765e0780ab88061ea4f9961feef9f3d376a49c6d29c18a34135c4f76"


# ============================================================ selftest
def _selftest_files():
    import tempfile
    d = tempfile.mkdtemp()
    try:
        ro = os.path.join(d, "roster")
        with open(ro, "w") as fh:
            fh.write(h_roster(3).canon)
        for mode, ok in [(0o644, True), (0o600, True), (0o664, False), (0o646, False)]:
            os.chmod(ro, mode)
            try:
                roster_load(ro)
                got = True
            except (ValueError, OSError):
                got = False
            assert got == ok, "roster mode %o" % mode
        sd = os.path.join(d, "seed")
        with open(sd, "wb") as fh:
            fh.write(bytes.fromhex(H_SEEDS[0]))
        for mode, ok in [(0o600, True), (0o400, True), (0o640, False), (0o604, False)]:
            os.chmod(sd, mode)
            try:
                seed_load(sd)
                got = True
            except (ValueError, OSError):
                got = False
            assert got == ok, "seed mode %o" % mode
        os.chmod(sd, 0o600)
        with open(sd, "ab") as fh:
            fh.write(b"x")
        for path in [sd, os.path.join(d, "missing")]:
            try:
                seed_load(path)
                assert False, path
            except (ValueError, OSError):
                pass
        os.symlink(ro, os.path.join(d, "link"))
        os.mkfifo(os.path.join(d, "fifo"), 0o600)
        for name in ["link", "fifo"]:
            try:
                roster_load(os.path.join(d, name))
                assert False, name
            except (ValueError, OSError):
                pass
    finally:
        for name in os.listdir(d):
            os.unlink(os.path.join(d, name))
        os.rmdir(d)


def selftest():
    H = lambda b: b.hex()
    # GF(256) FIPS-197
    assert gf_mul(0x57, 0x83) == 0xC1 and gf_mul(0x57, 0x13) == 0xFE and gf_inv(0x53) == 0xCA and gf_inv(0) == 0
    assert all(gf_mul(a, gf_inv(a)) == 1 for a in range(1, 256))
    # Shamir S0 round trip
    s0 = shamir_split_coeffs(b"\x42", 3, 5, b"\x13\x37")
    assert all(shamir_combine([s0[i] for i in c], 1) == b"\x42" for c in [(0, 1, 2), (1, 3, 4), (4, 2, 0)])
    # Refusals as shamir.nova: empty secret, x = 0, duplicate x, length mismatch.
    assert shamir_combine([(1, b""), (2, b"")], 0) is None
    assert shamir_combine([(0, b"\x01"), (2, b"\x02")], 1) is None
    assert shamir_combine([(1, b"\x01"), (1, b"\x02")], 1) is None
    assert shamir_combine([(1, b"\x01"), (2, b"\x02\x03")], 1) is None
    # ChaCha20 RFC 8439 2.3.2, A.1 #1 (== saprg P1)
    assert H(chacha_block(bytes(range(32)), 1, bytes.fromhex("000000090000004a00000000"))).startswith("10f1e7e4d13b5915500fdd1fa32071c4")
    assert b"".join(w.to_bytes(4, "little") for w in saprg_expand(bytes(32), 16)) == bytes.fromhex(
        "76b8e0ada0f13d90405d6ae55386bd28bdd219b8a08ded1aa836efcc8b770dc7"
        "da41597c5157488d7724e03fb8d84a376a43b8f41518a11cc387b669b2ee6586")
    # Poly1305 2.5.2 + AEAD 2.8.2
    assert H(poly1305(bytes.fromhex("85d6be7857556d337f4452fe42d506a80103808afb0db2fd4abff6af4149f51b"),
                      b"Cryptographic Forum Research Group")) == "a8061dc1305136c6c22b8baf0c0127a9"
    pt = b"Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it."
    w = aead_seal(bytes(range(0x80, 0xA0)), bytes.fromhex("070000004041424344454647"), bytes.fromhex("50515253c0c1c2c3c4c5c6c7"), pt)
    assert H(w[-16:]) == "1ae10b594f09e26a7e902ecbd0600691"
    # HKDF RFC 5869 A.1, A.3 (empty salt)
    assert H(hkdf(bytes(range(13)), b"\x0b" * 22, bytes(range(0xF0, 0xFA)), 42)) == (
        "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865")
    assert H(hkdf(b"", b"\x0b" * 22, b"", 42)) == (
        "8da4e775a563c18f715f802a063c5a31b8a11f5c5ee1879ec3454e5f3c738d2d9d201395faa4b61a96c8")
    # X25519 RFC 7748 5.2 #1 and 6.1
    assert H(x25519(bytes.fromhex("a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4"),
                    bytes.fromhex("e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c"))) == \
        "c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552"
    ask = bytes.fromhex("77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a")
    bsk = bytes.fromhex("5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb")
    apk, bpk = x25519_base(ask), x25519_base(bsk)
    assert H(x25519(ask, bpk)) == "4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742"
    # RFC 7748 5.2 #2: u has bit 255 set (must be masked), and the
    # iterated vector after one step (clamping of a scalar used as-is).
    assert H(x25519(bytes.fromhex("4b66e9d4d1b4673c5ad22691957d6af5c11b6421e0ea01d42ca4169e7918ba0d"),
                    bytes.fromhex("e5210f12786811d3f4b7959d0538ae2c31dbe7106fc03c3efc4cd549c715a493"))) == \
        "95cbde9476e8907d7aade45cb4b873f88b595a68799fa152e6f8f7647aac7957"
    nine = (9).to_bytes(32, "little")
    assert H(x25519(nine, nine)) == "422c8e7a6227d7bca1350b3e2bb7279f7897b87bb6854b783c60e80311ae3079"
    # sa_crypto KATs (tests/unit/test_sa_crypto.nova)
    assert H(kdf_info(b"mask", 7, 1, 2)) == "63726f7373656e67696e2f76342d73612f7631046d61736b00000000000000070000000100000002"
    assert H(agree(ask, bpk, b"mask", 7, 1, 2)) == "1c40444cfd660fb3f068a66b47f45f10bc961766cb01deb3b56c6c9e635ede31"
    assert mask_seed(bsk, apk, 7, 2, 1) == mask_seed(ask, bpk, 7, 1, 2)
    assert H(enc_key(ask, bpk, 7, 1, 2)) == "aa6c7416cef9c8946631a745cf271e62411c72b9225178167cab104f8f2d9b82"
    assert H(enc_key(bsk, apk, 7, 2, 1)) == "33cfefeb284f5d1c804dbd7fc799f9c66a4319dc6cd16f6b82ed0a38611a6297"
    assert agree(ask, bytes(32), b"mask", 1, 1, 2) is None and agree(ask, (1).to_bytes(32, "little"), b"enc", 1, 1, 2) is None
    k = bytes.fromhex("aa6c7416cef9c8946631a745cf271e62411c72b9225178167cab104f8f2d9b82")
    spt = bytes.fromhex("00000001000000025f28a38f8d0b5ae9811911c712a179ce5ce8e6ea65a07d0b40e582742107ba06"
                        "5f28a38f8d0b5ae9811911c712a179ce5ce8e6ea65a07d0b40e582742107ba06")
    assert H(share_seal(k, 7, 1, 2, spt)) == (
        "38e639c2a1773506182229534914ae0789170e05f9f458d3fb1199dbcf952f2918ac0cff5c0326f3f4285c85bcb50f34"
        "68710afb836bfac5904dec32821adeb8550476e7f2adf82bac5a6372d5dcb7f281e904cd05136f3b")
    assert share_open(k, 7, 1, 2, share_seal(k, 7, 1, 2, spt)) == spt and share_open(k, 7, 2, 1, share_seal(k, 7, 1, 2, spt)) is None
    # Ed25519 RFC 8032 7.1 TEST 1..3
    for sd, pk, m, sig in [
        ("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60", H_PKS[0], b"",
         "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"),
        ("4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb", H_PKS[1], b"\x72",
         "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00"),
        ("c5aa8df43f9f837bedb7442f31dcb7b166d38535076f094b85ce3a2e0b4458f7", H_PKS[2], b"\xaf\x82",
         "6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a")]:
        pkb = ed25519_pk_from_seed(bytes.fromhex(sd))
        assert H(pkb) == pk
        g = ed25519_sign(m, bytes.fromhex(sd), pkb)
        assert H(g) == sig and ed25519_verify(m, g, pkb) and not ed25519_verify(m + b"x", g, pkb)
        bad_s = g[:32] + (int.from_bytes(g[32:], "little") + ED_L).to_bytes(32, "little")
        assert not ed25519_verify(m, bad_s, pkb)                     # s >= L refused
    # pk_check: identity (01 00..) and the order-2 point (ec ff..7f) refused
    assert not ed25519_pk_check(_IDENT_ENC)
    assert not ed25519_pk_check(bytes.fromhex("ecffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f"))
    assert not ed25519_pk_check(bytes.fromhex("edffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f"))  # y = p
    assert all(ed25519_pk_check(bytes.fromhex(p)) for p in H_PKS)
    # Strict decoding (as src/safety/ed25519.nova): a non-canonical y that
    # is on the curve and not small order (y = p + 3), and signatures that
    # verify only if R = "-0" (01 00..00 80) or R with y = p + 1 were read
    # as the identity: s = k a with R = identity satisfies [s]B = R + [k]A.
    assert not ed25519_pk_check((P + 3).to_bytes(32, "little"))
    assert _pt_dec((3).to_bytes(32, "little")) is not None
    sd0 = bytes.fromhex("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60")
    pk0 = ed25519_pk_from_seed(sd0)
    h0 = bytearray(hashlib.sha512(sd0).digest()[:32]); h0[0] &= 248; h0[31] &= 127; h0[31] |= 64
    a0 = int.from_bytes(h0, "little")
    for r_enc in [(1 | (1 << 255)).to_bytes(32, "little"), (P + 1).to_bytes(32, "little")]:
        k0 = int.from_bytes(hashlib.sha512(r_enc + pk0 + b"m").digest(), "little") % ED_L
        assert not ed25519_verify(b"m", r_enc + (k0 * a0 % ED_L).to_bytes(32, "little"), pk0)
    k1 = int.from_bytes(hashlib.sha512(_IDENT_ENC + pk0 + b"m").digest(), "little") % ED_L
    assert ed25519_verify(b"m", _IDENT_ENC + (k1 * a0 % ED_L).to_bytes(32, "little"), pk0)  # control
    # File checks (as sa_roster.nova): roster not group/other-writable,
    # seed owned by us with no group/other bits, regular files only.
    _selftest_files()
    # wire round trips
    assert parse("SA4_END 5 1 7 2") == (EV_END, 5, 1, 7, 2)
    for bad in ["SA4_END 05 1 7 2", "SA4_END 5 1 7  2", "SA4_END 5 1 7 2 ", "SA4_END 4611686018427387904 1 7 2",
                "SA4_ABORT 1 2 Bad", "SA4_SET 1 6 " + "00" * 32, "SA4_SET 1 0 " + "00" * 32, "SA4_END 1 6 2 0",
                "SA4_END 1 0 2 0"]:
        assert parse(bad) is None, bad
    assert parse("SA4_END 4611686018427387903 1 7 2") is not None
    assert bitmap([1, 9, 255]) [0] == 1 and bitmap_xs(bitmap([1, 9]), 8) is None
    # v4-sa2 wire: 8-token ADV, ct of 98 + 32k bytes (k = 1..8), 7-token REVEAL
    # with a proof of 32k bytes (k = 2..9); v1 shapes refused.
    g32, g64 = bytes(range(32)), bytes(range(64))
    adv = fmt_adv(5, 7, g32, g32[::-1], g64, b"\x03" * 32, b"\x04" * 32)
    assert parse(adv) == (EV_ADV, 5, 7, g32, g32[::-1], g64, b"\x03" * 32, b"\x04" * 32)
    assert parse(" ".join(adv.split(" ")[:5] + adv.split(" ")[7:])) is None          # v1 ADV
    for k in range(0, 10):
        ln = fmt_share(5, 7, 300, bytes(98 + 32 * k), g32)
        assert (parse(ln) is not None) == (1 <= k <= 8), k
        rv = fmt_reveal(5, 7, 300, 0, g32, bytes(32 * k))
        assert (parse(rv) is not None) == (2 <= k <= 9), k
    assert parse(fmt_share(5, 7, 300, bytes(98 + 32 * 2), g32)[:-1]) is None
    assert parse(fmt_share(5, 7, 300, bytes(98 + 32), g32).replace("0000", "000A", 1)) is None
    rv = fmt_reveal(5, 7, 300, 1, g32, g64 + g32)
    assert parse(rv) == (EV_REVEAL, 5, 7, 300, 1, g32, g64 + g32)
    assert parse(" ".join(rv.split(" ")[:6])) is None                                  # v1 REVEAL
    assert max(len(fmt_adv(2 ** 62 - 1, M32, g32, g32, g64, g32, g32)),
               len(fmt_share(2 ** 62 - 1, M32, M32, bytes(98 + 32 * 8), g32)),
               len(fmt_reveal(2 ** 62 - 1, M32, M32, 0, g32, bytes(32 * 9)))) <= 1000
    pt2 = share_pt(300, 7, 5, 2, g32, g32[::-1], [g32, g32])
    assert share_pt_parse(pt2, 2) == (300, 7, 5, 2, g32, g32[::-1], [g32, g32])
    assert share_pt_parse(pt2, 1) is None and share_pt_parse(b"\x01" + pt2[1:], 2) is None
    wire3_selftest()
    pins = pins_selftest()
    for line in pins:
        if not line.startswith(("PIN adv_transcript ", "PIN tree_n255_path")):
            print(line)
    k = oracle_selftest()
    kb = blame_selftest()
    print("sa4_ref selftest: pins %d (v4-sa2 + v4-sa3), rebuild oracle scenarios %d, blame checks %d" % (
        sum(1 for l in pins if l.startswith("PIN ")), k, kb))
    print("sa4_ref selftest: OK")
    return 0


def wire3_selftest():
    """v4-sa3 wire: new lines, grammar edges, sizes, epk_ok, LOW_ORDER."""
    g32, g64 = bytes(range(32)), bytes(range(64))
    big, rr = M32, 2 ** 62 - 1
    for ln, rec in [(fmt_shsig(5, 7, g64), (EV_SHSIG, 5, 7, g64)),
                    (fmt_complaint(5, 7, 300, g32, g64), (EV_COMPLAINT, 5, 7, 300, g32, g64)),
                    (fmt_accuse(5, g32), (EV_ACCUSE, 5, g32)),
                    (fmt_open(5, 300, 7, g32), (EV_OPEN, 5, 300, 7, g32)),
                    (fmt_share(5, 7, 300, bytes(162), g32), (EV_SHARE, 5, 7, 300, bytes(162), g32)),
                    (fmt_set(5, 5, g32), (EV_SET, 5, 5, g32)), (fmt_end(5, 4, 7, 0), (EV_END, 5, 4, 7, 0)),
                    (fmt_end(5, 5, 7, 3), (EV_END, 5, 5, 7, 3))]:
        assert parse(ln) == rec, ln
        t = ln.split(" ")
        assert parse(" ".join(t[:-1])) is None and parse(ln + " 0") is None, ln     # token counts
        assert parse(ln.upper().replace("SA4_", "sa4_").replace("sa4_", "SA4_", 1)) in (None, rec)
    # v4-sa2 5-token SHARE; epk of 63 / 65 hex or upper case; SET 6 / END 6
    assert parse("SA4_SHARE 1 2 3 " + "00" * 162) is None
    assert parse("SA4_SHARE 1 2 3 " + "0" * 63 + " " + "00" * 162) is None
    assert parse("SA4_SHARE 1 2 3 " + "0" * 66 + " " + "00" * 162) is None
    assert parse("SA4_SHARE 1 2 3 " + "A" * 64 + " " + "00" * 162) is None
    assert parse("SA4_COMPLAINT 1 2 3 " + "00" * 32 + " " + "00" * 63) is None
    assert parse("SA4_OPEN 1 2 3 " + "00" * 31) is None and parse("SA4_ACCUSE 1 " + "00" * 33) is None
    assert parse("SA4_SHSIG 1 2 " + "00" * 65) is None
    sizes = {}
    for n in (3, 10, 255):
        d = depth(n)
        ls = {"SHARE": fmt_share(rr, big, big, bytes(98 + 32 * d), bytes([9]) + bytes(31)),
              "SHSIG": fmt_shsig(rr, big, bytes(64)), "SET5": fmt_set(rr, 5, bytes(32)),
              "COMPLAINT": fmt_complaint(rr, big, big, bytes(32), bytes(64)), "ACCUSE": fmt_accuse(rr, bytes(32)),
              "OPEN": fmt_open(rr, big, big, bytes(32)), "END": fmt_end(rr, 5, big, big)}
        assert all(parse(v) for v in ls.values())
        sizes[n] = {k: len(v) for k, v in ls.items()}
    assert [sizes[n]["SHARE"] for n in (3, 10, 255)] == [441, 569, 825], sizes
    assert sizes[3]["SHSIG"] == 169 and sizes[3]["COMPLAINT"] == 249 and sizes[3]["ACCUSE"] == 95
    assert sizes[3]["OPEN"] == 115 and sizes[3]["SET5"] == 94 and sizes[3]["END"] == 51
    assert parse("SA4_Y 1 2 0 1 " + "0" * 984) is None                       # 1001 bytes
    # epk_ok and the low-order table (literal values of SPEC section 4)
    assert [pt.hex() for pt in LOW_ORDER] == [
        "0000000000000000000000000000000000000000000000000000000000000000",
        "0100000000000000000000000000000000000000000000000000000000000000",
        "e0eb7a7c3b41b8ae1656e3faf19fc46ada098deb9c32b1fd866205165f49b800",
        "5f9c95bca3508c24b1d0b1559c83ef5b04445cc4581c8e86d8224eddd09f1157",
        "ecffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f"]
    ks = [sha256(b"k%d" % i) for i in range(4)]
    assert all(x25519(k, pt) == bytes(32) for pt in LOW_ORDER for k in ks)
    assert not any(epk_ok(pt) for pt in LOW_ORDER)
    assert not epk_ok(P.to_bytes(32, "little")) and not epk_ok((P + 1).to_bytes(32, "little"))
    assert not epk_ok(bytes(31) + b"\x80") and not epk_ok(bytes(31)) and not epk_ok(bytes(33))
    assert epk_ok(bytes([2]) + bytes(31)) and x25519(ks[0], bytes([2]) + bytes(31)) != bytes(32)
    for i in range(64):                       # canonical u outside the list: DH never zero
        u = bytearray(sha256(b"u%d" % i)); u[31] &= 0x7F
        if epk_ok(bytes(u)):
            assert x25519(ks[1], bytes(u)) != bytes(32)
    assert eph(bytes(32), 1, 5, 5) is None and eph(bytes(32), 1, 5, M32 + 1) is None
    assert len(shares_transcript(bytes(32), 1, 1, bytes(32), bytes(32))) == 138
    assert len(complaint_transcript(bytes(32), 1, 1, 2, bytes(32), bytes(32))) == 145
    assert [phase_order(st) for st in (0, 1, 8, 9, 2, 3, 4, 5, 6, 7)] == list(range(10))
    # harness A-D: v4-sa2 SA4_Y lines unchanged; every soul sends END 4 0
    for k, (cnt, dig) in Y_PINS.items():
        ro, advs, allv = h_run3(*SCEN[k])
        y = [l for l in allv if l.startswith("SA4_Y ")]
        assert len(y) == cnt and sha256("\n".join(y).encode()).hex() == dig, "harness %s Y lines" % k
        assert sum(1 for l in allv if l.startswith("SA4_END %d 4 " % SCEN[k][1])) == SCEN[k][0] - (SCEN[k][3] >= 0)
        assert not any(l.startswith(("SA4_COMPLAINT", "SA4_ABORT")) for l in allv)
    # refusal cases E (21, the last six v4-sa3)
    rl = refusal_lines()
    want = ["unexpected", "bad_line", "bad_set", "bad_complaint", "bad_set", "unexpected"]
    assert len(rl) == 21 and [l.split(" ")[-1] for l in rl[15:]] == want, rl[15:]


def _chk(cond, what):
    if not cond:
        raise AssertionError("blame selftest: " + what)
    return 1


def blame_selftest():
    """Rounds F-J / P (section 15, verbatim), the judge, and the prototype's
    oracle scenarios incl. the mutants the spec lists (each must be seen)."""
    k = 0
    evid = {}
    for name, (lines, whys) in SA3_ROUNDS.items():
        net = h_round(name)
        evid[name] = dict(net.C.evidence)
        got = [l for _, l in net.all_lines]
        k += _chk(all(l in got for l in lines), "round %s lines" % name)
        k += _chk({i: net.C.why(i) for i in whys} == whys and set(net.C.codes()) == set(whys), "round %s whys" % name)
        k += _chk(net.result() == net.expected(), "round %s sum" % name)
        k += _chk(not net.refused, "round %s: no soul refused" % name)
        for who, text in net.C.evidence.items():
            want = ("sender", who) if net.C.codes()[who] == 1 else ("complainer", who)
            k += _chk(judge_evidence(net.ro, text) == want, "round %s judge" % name)
            # negative: every tampered evidence is invalid -- every line
            # (header, round, sender, complainer, u1, the '-' fields of
            # code 2, the complaint of code 1 ...), each with its last
            # character changed and with a trailing space
            L = text.split("\n")
            for i, ln in enumerate(L[:-1]):
                for t1 in ((_flip_last_hex(ln) if not ln.startswith("code ") else "code %d" % (3 - int(ln[5:]))),
                           ln + " "):
                    t2 = "\n".join(L[:i] + [t1] + L[i + 1:])
                    k += _chk(judge_evidence(net.ro, t2)[0] == "invalid", "round %s tampered %r" % (name, t1[:12]))
            # the share and complaint lines must carry the evidence's round
            # (no signature covers their round token)
            for pfx in ("share SA4_SHARE ", "complaint SA4_COMPLAINT "):
                t2 = "\n".join(l.replace(pfx + "%d " % net.C.r, pfx + "%d " % (net.C.r + 1), 1) for l in L)
                k += _chk(t2 != text and judge_evidence(net.ro, t2)[0] == "invalid",
                          "round %s: %s line of another round" % (name, pfx.split(" ")[0]))
            for extra in ("x\n", "\n", "open " + "00" * 32 + "\n"):
                k += _chk(judge_evidence(net.ro, text + extra)[0] == "invalid", "round %s: appended line" % name)
            if want[0] == "sender":
                for key in ("path ", "shsig "):
                    t2 = "\n".join(("%s-" % key) if l.startswith(key) else l for l in L)
                    k += _chk(judge_evidence(net.ro, t2)[0] == "invalid", "round %s: code 1 with %s-" % (name, key))
            # the one known malleability: the X25519 clamp bits of `open`
            # are not bound (SECAGG_AUDIT A2.4c, "Evidence and judge")
            for bi, bit in ((0, 1), (0, 4), (31, 0x40), (31, 0x80)):
                t2 = "\n".join(l if not l.startswith("open ") else "open " + bytes(
                    b ^ (bit if j == bi else 0) for j, b in enumerate(bytes.fromhex(l[5:]))).hex() for l in L)
                k += _chk(judge_evidence(net.ro, t2) == want, "round %s: open clamp bit %d/%#x not bound" % (name, bi, bit))
            k += _chk(judge_evidence(net.ro, text[:-1])[0] == "invalid", "no final newline")
            k += _chk(judge_evidence(h_roster(4), text)[0] == "invalid", "other roster")
    # U1 != U2' (rounds K, L: 70000 sent its ADV, then nothing; left out of
    # U2' at the shares close). The evidence covers U1 -- the key lines and
    # H1 the signer used -- so it is byte-identical to rounds F / G (an
    # evidence builder over U2' would write another H1: invalid).
    for name, twin, want in (("K", "F", {4294967295: 1}), ("L", "G", {65536: 2})):
        net = h_round(name)
        C = net.C
        k += _chk(C.u1 == [1, 2, 3, 4, 5] and C.u2p == [1, 2, 3, 5] and C.why(70000) == "share batch incomplete" and
                  net.codes() == want and C.st == C_CANCELLED and C.cancel == "|U2| 3 below t" and not net.refused,
                  "round %s: U1 != U2', codes %s" % (name, net.codes()))
        k += _chk(C.evidence == evid[twin], "round %s: evidence identical to round %s" % (name, twin))
        for who, text in C.evidence.items():
            k += _chk(judge_evidence(net.ro, text) == (("sender", who) if want[who] == 1 else ("complainer", who)),
                      "round %s judge" % name)
    ro, seeds = o_roster(5)

    def case(faults=None, mut=None, n=5, names=None):
        r_, s_ = (ro, seeds) if n == 5 else o_roster(n)
        return Net(r_, s_, 5, 6, faults, mut, fault_names=names).run()
    net = case()
    k += _chk(net.codes() == {} and net.C.counters() == [0, 0, 0, 0] and not net.opens(), "honest: no blame crypto")
    k += _chk(net.result() == net.expected(), "honest sum")
    for kind in ("garbage", "fields", "commit"):
        net = case({1: {3: kind}})
        k += _chk(net.codes() == {10: 1} and 3 in net.C.u3 and net.result() == net.expected(), "bad share " + kind)
        k += _chk(judge_evidence(ro, net.C.evidence[10]) == ("sender", 10), "judge " + kind)
        k += _chk(net.C.why(10) == "proven: sent soul 30 a share that fails the %s check" %
                  {"garbage": "open", "fields": "fields", "commit": "commit"}[kind], "why " + kind)
    net = case({1: {2: "garbage", 3: "fields", 4: "commit", 5: "garbage"}})
    k += _chk(net.codes() == {10: 1} and net.C.counters()[:2] == [1, 3] and net.C.u3 == [2, 3, 4, 5], "all-bad sender")
    net = case({4: {"false": {2}}})
    k += _chk(net.codes() == {40: 2} and net.C.counters()[2] == 0, "false complaint: code 2, no root")
    net = case({4: {"false": {1, 2, 3, 5}}})
    k += _chk(net.codes() == {40: 2} and net.C.counters()[:2] == [1, 3], "complain-all: judged once")
    k += _chk(case({1: {3: "garbage", "silent": 1}}).codes() == {10: 3}, "silent accused: code 3")
    k += _chk(case({1: {3: "garbage", "badsig": 1}}).codes() == {10: 4}, "bad SHSIG: code 4")
    # the false-complainer guarantee needs an answer: if the accused does
    # not open, the accused is removed (code 3) and the liar stays
    net = case({4: {"false": {1}}, 1: {"silent": 1}})
    k += _chk(net.codes() == {10: 3} and net.C.u3 == [2, 3, 4, 5] and net.result() == net.expected(),
              "false complaint, silent accused: accused code 3, liar stays")
    # U1 != U2' at N = 10 (x10's END 1 lost on the uplink) with a code-1 and
    # a code-2 verdict: both evidence files cover U1 and are judged
    net = Net(*o_roster(10), 5, 6, {1: {4: "garbage"}, 6: {"false": {3}}})
    net.up = lambda fid, l: "SA4_END 5 1 100 x" if fid == 100 and l.startswith("SA4_END 5 1 ") else l
    net.run()
    C = net.C
    k += _chk(C.u1 == list(range(1, 11)) and C.u2p == list(range(1, 10)) and net.codes() == {10: 1, 60: 2} and
              C.st == C_READY and net.result() == net.expected(), "U1 != U2' (N = 10): codes %s" % net.codes())
    k += _chk(judge_evidence(net.ro, C.evidence[10]) == ("sender", 10) and
              judge_evidence(net.ro, C.evidence[60]) == ("complainer", 60) and
              all(("u1 " + bitmap(C.u1).hex() + "\n") in t and t.count("\nkey ") == 10 for t in C.evidence.values()),
              "U1 != U2' (N = 10): evidence over U1, judged")
    # A1 with an honest coordinator: corrupt receiver 30 signs a second ADV
    # (other c key) and a network attacker shows it to honest sender 10
    # only. 30's complaint verifies over the coordinator's H1, not 10's, so
    # 10 cannot verify it, sends no OPEN, and is removed with code 3.
    net = Net(ro, seeds, 5, 6)
    adv_b = {}

    def a1_tamper(ph, msgs):
        out = []
        for to, l in msgs:
            if ph == C_ADV and l.startswith("SA4_ADV 5 30 "):
                if "line" not in adv_b:
                    q = parse(l)
                    cb = x25519_base(sha256(b"second c key"))
                    g = ed25519_sign(adv_transcript(ro.fp, 5, 30, 6, h_layout(), cb, q[4], q[6], q[7]), seeds[2],
                                     ro.entries[2][2])
                    adv_b["line"] = fmt_adv(5, 30, cb, q[4], g, q[6], q[7])
                if to == 10:
                    l = adv_b["line"]
            out.append((to, l))
        return out
    net.tamper = a1_tamper
    net.run()
    k += _chk(net.codes() == {10: 3} and net.C.why(10) == "did not open its share to soul 30 with its one-time key "
              "(not proven)" and not net.opens() and not net.C.evidence and not net.refused and net.C.st == C_READY,
              "A1, honest coordinator + network attacker: honest sender code 3, no OPEN, no evidence")
    # coordinator receipt and check close (8.4 / 8.5), oracle side:
    # a complaint about a soul outside U2' is refused with the 8.4 why
    net = Net(ro, seeds, 5, 6)
    cpl50 = fmt_complaint(5, 10, 50, bytes(32), bytes(64))
    net.up = lambda fid, l: ("SA4_END 5 1 50 x" if fid == 50 and l.startswith("SA4_END 5 1 ") else
                             cpl50 if fid == 10 and l.startswith("SA4_END 5 4 ") else l)
    net.run(stop_after=C_SHARES)
    k += _chk(net.C.u2p == [1, 2, 3, 4] and net.C.why(10) == "complaint about a soul outside U2'" and
              net.C.P[1]["bad"] and not net.C.P[1]["comp"], "oracle: complaint about a soul outside U2' refused")
    # complaints about a soul left out in the check phase are not
    # forwarded; neither are those of a complainer left out after it
    # complained: no ACCUSE, no open phase, no verdict crypto
    for nm, bad_id in (("accused", 10), ("complainer", 30)):
        net = Net(ro, seeds, 5, 6, {1: {3: "garbage"}})
        seen = []
        net.tamper = lambda ph, msgs: (seen.extend((ph, to, l) for to, l in msgs), msgs)[1]
        net.up = lambda fid, l, b=bad_id: "SA4_END 5 4 %d x" % b if fid == b and l.startswith("SA4_END 5 4 ") else l
        net.run()
        k += _chk(net.C.why(bad_id) == "malformed line" and net.C.accused == {} and net.codes() == {} and
                  not any(l.startswith(("SA4_ACCUSE ", "SA4_COMPLAINT ")) for _, _, l in seen) and
                  net.C.counters() == [0, 0, 0, 0] and bad_id not in [net.C.I(x) for x in net.C.u2] and
                  net.C.st == C_READY and net.result() == net.expected(),
                  "oracle: left-out %s -> complaint not forwarded" % nm)
    net = case({1: {"badsig": 1}})
    k += _chk(net.codes() == {} and net.C.u3 == [1, 2, 3, 4, 5], "bad SHSIG alone harmless")
    net = case({1: {3: "lowepk"}})
    k += _chk(net.codes() == {} and 1 not in net.C.u2p and 3 in net.C.u3 and
              net.C.why(10) == "share one-time key is not a valid X25519 key", "low-order e_pk left out at receipt")
    net = case({1: {3: "lowepk"}}, {"no_epk_struct": 1})
    k += _chk(net.refused.get(30, ("",))[0] == "bad_share", "MUTANT 13 (no epk_ok at receipt) seen")
    net = case({1: {3: "foreign_e"}})
    k += _chk(net.codes() == {10: 3} and 3 in net.C.u3, "foreign e: code 3, victim stays")
    net = case({1: {3: "foreign_e"}}, {"no_epk_check": 1})
    k += _chk(net.codes().get(30) == 2, "MUTANT 7 (judge without X25519_base(e) == e_pk) seen: victim framed")
    k += _chk(judge_evidence(ro, net.C.evidence[30]) == ("invalid", "opening does not match e_pk"),
              "the standalone judge refuses the framing evidence (split key)")
    net = case({1: {3: "garbage"}, 2: {3: "garbage"}})
    k += _chk(net.C.st == C_CANCELLED and net.codes() == {10: 1, 20: 1}, "two cheaters of one victim at N=5 cancel")
    net = case({1: {3: "garbage"}}, {"no_exclude": 1})
    k += _chk(net.refused.get(30, ("",))[0] == "bad_set", "MUTANT 16 (proven sender kept) seen: victim refuses")
    # --fault names (live soul modes) end as the spec says
    for f, want in (("bad-share-open", {10: 1}), ("bad-share", {10: 1}), ("bad-share-fields", {10: 1}),
                    ("bad-commit-share", {10: 1}), ("false-complaint", {10: 2}), ("complain-all", {10: 2}),
                    ("bad-shsig", {}), ("bad-shsig,bad-share-open", {10: 4}), ("low-epk", {}),
                    ("foreign-e", {10: 3})):
        net = case(names={1: f})
        k += _chk(net.codes() == want and net.C.st == C_READY and net.result() == net.expected(),
                  "--fault %s: codes %s" % (f, net.codes()))
    net = case({1: {3: "garbage"}}, names={1: "no-open"})
    k += _chk(net.codes() == {10: 3}, "--fault no-open: code 3")
    # verdict order (A3): a false complainer is proven before the root
    for mut, want in ((None, {20: 2, 10: 3}), ("robust_order", {10: 4})):
        net = Net(ro, seeds, 5, 6, {2: {"false": {1}}}, {mut: 1} if mut else None)
        net.up = lambda fid, l: _flip_last_hex(l) if fid == 10 and l.startswith("SA4_SHARE 5 10 30 ") else l
        net.run()
        k += _chk(net.codes() == want, "verdict order %s: %s" % (mut, net.codes()))
    # early stop (N = 10, five false complainers about 10)
    net = case({x: {"false": {1}} for x in (6, 7, 8, 9, 10)}, n=10)
    k += _chk(net.C.st == C_CANCELLED and net.C.counters()[0] == 4, "early stop after 4 judged")
    net = case({x: {"false": {1}} for x in (6, 7, 8, 9, 10)}, {"no_early_stop": 1}, n=10)
    k += _chk(net.C.counters()[0] == 5, "MUTANT 12 (no early stop) seen")
    # the accused's gate: forged complaints give no OPEN and no refusal
    net = Net(ro, seeds, 5, 6).run(stop_after=C_SHARES)
    s10, h1 = net.S[10], net.C.h1
    line = net.C.P[1]["sh"][3]
    lh = sleaf(ro.fp, 5, 10, 3, 30, line[5], line[4])
    sg = lambda sd, x, rr, v, hh: ed25519_sign(complaint_transcript(ro.fp, rr, v, 10, hh, lh), sd, ro.entries[x - 1][2])
    forged = {"zero signature": fmt_complaint(5, 30, 10, lh, bytes(64)),
              "wrong signer": fmt_complaint(5, 30, 10, lh, sg(seeds[3], 4, 5, 30, h1)),
              "other leaf": fmt_complaint(5, 40, 10, lh, sg(seeds[3], 4, 5, 40, h1)),
              "other round": fmt_complaint(5, 30, 10, lh, sg(seeds[2], 3, 4, 30, h1)),
              "other H1": fmt_complaint(5, 30, 10, lh, sg(seeds[2], 3, 5, 30, sha256(b"x")))}
    genuine = fmt_complaint(5, 30, 10, lh, sg(seeds[2], 3, 5, 30, h1))

    def accuse(cl, f3=None):
        st = Soul.__new__(Soul)
        st.__dict__ = dict(s10.__dict__, batch=[], state=ST_CHECKED, f3=dict(f3 or {}))
        st.handle(cl)
        return st.handle(fmt_accuse(5, bitmap([ro.x(parse(cl)[2])])))
    for nm, cl in forged.items():
        ok, err, outs = accuse(cl)
        k += _chk(ok and outs == [fmt_end(5, 5, 10, 0)], "forged complaint (%s): END 5 0, no OPEN" % nm)
    ok, err, outs = accuse(genuine)
    k += _chk(ok and len(outs) == 2 and x25519_base(parse(outs[0])[4]) == line[5], "genuine complaint opens")
    ok, err, outs = accuse(forged["other leaf"], {"nolh": 1})
    k += _chk(ok and outs[0].startswith("SA4_OPEN"), "MUTANT 1 (accused lh check) seen: forged complaint opens")
    ok, err, outs = accuse(forged["zero signature"], {"nosig": 1})
    k += _chk(ok and outs[0].startswith("SA4_OPEN"), "MUTANT 2 (accused signature check) seen")
    # coordinator lh / signature checks (mutants 8, 9: honest accused code 3)
    for variant, mut, want in (("leaf", None, {40: 5}), ("leaf", "no_lh_check", {10: 3}),
                               ("sig", None, {40: 5}), ("sig", "no_csig_check", {10: 3})):
        net = Net(ro, seeds, 5, 6, {4: {"false": {1}}}, {mut: 1} if mut else None)

        def up(fid, l, variant=variant):
            if fid == 40 and l.startswith("SA4_COMPLAINT "):
                q = parse(l)
                if variant == "leaf":
                    lh2 = sha256(b"bogus")
                    return fmt_complaint(5, 40, 10, lh2, ed25519_sign(complaint_transcript(
                        ro.fp, 5, 40, 10, net.S[40].h1, lh2), seeds[3], ro.entries[3][2]))
                return fmt_complaint(5, 40, 10, q[4], bytes(64))
            return l
        net.up = up
        net.run()
        k += _chk(net.codes() == want and not net.opens(), "coordinator %s check %s: %s" % (variant, mut, net.codes()))
    # final SET 2 / ACCUSE refusals at the soul (7.6, 7.7)
    for nm, lines_, code in (("ACCUSE without complaint lines", [fmt_accuse(5, bitmap([3]))], "bad_complaint"),
                             ("ACCUSE naming the accused", [fmt_accuse(5, bitmap([1]))], "bad_set"),
                             ("empty ACCUSE", [fmt_accuse(5, bytes(32))], "bad_set"),
                             ("ACCUSE bit above N", [fmt_accuse(5, bitmap([6]))], "bad_set"),
                             ("complaint about another soul",
                              [forged["zero signature"].replace(" 30 10 ", " 30 20 ", 1), fmt_accuse(5, bitmap([3]))],
                              "bad_complaint"),
                             ("complaints then SET 2", [forged["zero signature"], fmt_set(5, 2, bitmap([1, 2, 3, 4, 5]))],
                              "bad_complaint"),
                             ("U2 not in U2'", [fmt_set(5, 2, bitmap([1, 2, 3, 4, 5, 6]))], "bad_set"),
                             ("U2 small", [fmt_set(5, 2, bitmap([1, 2, 3]))], "u2_small"),
                             ("U2 without me", [fmt_set(5, 2, bitmap([2, 3, 4, 5]))], "not_in_u2")):
        st = Soul.__new__(Soul)
        st.__dict__ = dict(s10.__dict__, batch=[], state=ST_CHECKED)
        res = [st.handle(l) for l in lines_][-1]
        k += _chk(not res[0] and res[2][-1].endswith(" " + code) and st.eseed is None, "%s -> %s" % (nm, code))
    # pass 1 (structure) before pass 2 (content): a structural fault anywhere
    # in the batch refuses before any share is opened or anything signed
    net = Net(ro, seeds, 5, 6)
    net.tamper = lambda ph, msgs: [(to, (fmt_share(5, 50, 10, parse(l)[4], LOW_ORDER[1])
                                         if l.startswith("SA4_SHARE 5 50 10 ") else
                                         fmt_share(5, 20, 10, garbage(parse(l)[4]), parse(l)[5])
                                         if l.startswith("SA4_SHARE 5 20 10 ") else l)) for to, l in msgs]
    net.run(stop_after=C_SHARES)
    k += _chk(net.refused.get(10, ("",))[0] == "bad_share" and net.S[10].check_kinds == {} and
              not any(to == 10 and l.startswith("SA4_COMPLAINT") for to, l in net.all_lines),
              "pass 1 before pass 2: refused before any content check")
    # U2 must be a subset of U2' (x1 left out at receipt: U2' = 2..5)
    net = Net(ro, seeds, 5, 6, {1: {3: "lowepk"}}).run(stop_after=C_SHARES)
    ok, err, outs = net.S[30].handle(fmt_set(5, 2, bitmap([1, 2, 3, 4, 5])))
    k += _chk(not ok and outs[-1].endswith(" bad_set") and "subset of U2'" in err, "U2 not a subset of U2'")
    # the victim refuses a U2 with the soul it complained about; SET 2 right after shares
    net = Net(ro, seeds, 5, 6)
    net.tamper = lambda ph, msgs: [(to, l.replace("SA4_SET 5 5 ", "SA4_SET 5 2 ")) for to, l in msgs]
    net.run()
    k += _chk(len(net.refused) == 5 and all(v[0] == "unexpected" for v in net.refused.values()), "SET 2 in SHARED")
    net = Net(ro, seeds, 5, 6)
    net.tamper = lambda ph, msgs: [(to, l) for to, l in msgs
                                   if not (ph == C_SHARES and to == 30 and l.startswith("SA4_SHARE 5 20 "))]
    net.run()
    k += _chk(net.refused.get(30, ("",))[0] == "bad_share", "dropped share: bad_share")
    # wipes: c^SK after CHECK, eseed after final SET 2 and after a refusal
    net = Net(ro, seeds, 5, 6).run(stop_after=C_SHARES)
    k += _chk(all(sl.csk is None and sl.eseed is not None for sl in net.S.values()), "c^SK wiped after CHECK")
    net = Net(ro, seeds, 5, 6).run(stop_after=C_CHECK)            # right after the final SET 2
    k += _chk(all(sl.state == ST_MASKED and sl.eseed is None and sl.sleaves is None and sl.csk is None
                  for sl in net.S.values()), "eseed and sleaves wiped at the final SET 2")
    net = Net(ro, seeds, 5, 6, {1: {3: "garbage"}}).run(stop_after=C_OPEN)
    k += _chk(all(sl.eseed is None and all(net.S[i].held[0] is None for i in (20, 30, 40, 50))
                  for sl in net.S.values() if sl.state == ST_MASKED), "eseed / held share outside U2 wiped")
    return k


def pins_main(path=None):
    text = "\n".join(pins_selftest()) + "\n"
    if path:
        with open(path, "w") as fh:
            fh.write(text)
    sys.stdout.write(text)
    return 0


def dump(which):
    """Print this implementation's transcript in the sa4_dump.nova format."""
    if which == "E":
        for line in refusal_lines():
            print(line)
        return 0
    if which in H_ROUNDS:
        for line in h_round_lines(which):
            print(line)
        return 0
    ro, advs, allv = h_run3(*SCEN[which])
    if which == "A":
        print("#FP " + ro.fp.hex())
    for line in advs:
        print("ADV " + line)
    for line in allv:
        print("OUT " + line)
    return 0


# ============================================================ live soul (A2.3c)
FED_HELLO = "SECAGG_HELLO ce-fed v4-sa3"
FED_OK = "OK ce-fed v4-sa3 protocol accepted"
LAYOUT_HEADER = "crossengin-fed-layout v1"
TAG_CHARS = set("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_:-")


def fed_tags(s):
    """sa4f_tags_parse: comma-separated, sorted, de-duplicated."""
    tags = s.split(",")
    for t in tags:
        if not (1 <= len(t) <= 64) or any(c not in TAG_CHARS for c in t):
            raise ValueError("bad tag %r" % t)
    out = sorted(set(tags), key=lambda t: t.encode("ascii"))
    if len(out) > 256:
        raise ValueError("more than 256 tags")
    return out


def fed_layout(tags):
    text = LAYOUT_HEADER + "\n" + "".join("%s promo atr present\n" % t for t in tags)
    return sha256(text.encode("ascii"))


def fed_words(tags, x):
    """x: {tag: (promo, atr)} -> [promo, atr, present] per tag."""
    w = []
    for t in tags:
        if t in x:
            w += [x[t][0], x[t][1], 1]
        else:
            w += [0, 0, 0]
    return w


def fed_parse_result(line):
    """sa4f_parse_result: strict FED_AGGREGATE_SUM -> (r, tag, sp, sa, n) or None."""
    t = _tokens(line)
    if t is None or len(t) != 6 or t[0] != "FED_AGGREGATE_SUM":
        return None
    r = _round(t[1])
    if r < 0 or not (1 <= len(t[2]) <= 64) or any(c not in TAG_CHARS for c in t[2]):
        return None
    sp, sa, n = _u32(t[3]), _u32(t[4]), _u32(t[5])
    if sp < 0 or sa < 0 or n < 0:
        return None
    return (r, t[2], sp, sa, n)


def fed_result_why(rec, r, tags, u3n, applied):
    """sa4f_result_why."""
    if rec is None:
        return "not a FED_AGGREGATE_SUM line"
    if rec[0] != r:
        return "for another round"
    if rec[1] not in tags:
        return "tag not in CE_SECAGG_V4_TAGS"
    if rec[1] in applied:
        return "second result for this tag"
    if rec[4] < 1:
        return "n_part below 1"
    if rec[4] > u3n:
        return "n_part above |U3|"
    return ""


def round_ok(soul, rec):
    """sa4s_round_ok: '' when the soul would accept this SA4_ROUND record."""
    if rec is None:
        return "bad_line"
    if rec[0] != EV_ROUND:
        return "unexpected"
    if soul.x is None:
        return "no_input"
    if rec[2] != soul.ro.fp:
        return "bad_fp"
    if rec[1] <= soul.last:
        return "stale_round"
    if rec[3] != len(soul.x):
        return "bad_len"
    if rec[4] != soul.layout:
        return "bad_layout"
    return ""


def _corrupt_hex_token(line, idx, pos=0):
    t = line.split(" ")
    h = list(t[idx])
    h[pos] = "1" if h[pos] == "0" else "0"
    t[idx] = "".join(h)
    return " ".join(t)


# --fault names: SOUL_FAULTS change what the soul computes (Soul.fault);
# the others act on the wire / the connection in _connect_loop.
SOUL_FAULTS = set(DEAL_FAULTS) | {"inconsistent-deal", "false-complaint", "complain-all", "no-open", "bad-shsig"}
KNOWN_FAULTS = SOUL_FAULTS | {"stop-after-adv", "stop-after-shares", "stop-after-check", "stop-after-y", "stop-after-sig3",
                              "bad-adv-sig", "bad-sig3", "swap-reveal", "silent", "drip", "bad-b-reveal",
                              "bad-s-reveal", "silent-check"}


def connect_main(argv):
    import socket
    opt = {"--x": "", "--state": None, "--fault": None, "--timeout": "60", "--tags": None, "--connect": None,
           "--deadline": "300"}
    i = 0
    while i < len(argv):
        if argv[i] not in opt or i + 1 >= len(argv):
            print("sa4_ref: bad argument %r" % argv[i])
            return 2
        opt[argv[i]] = argv[i + 1]
        i += 2
    host, _, port = opt["--connect"].rpartition(":")
    tags = fed_tags(opt["--tags"])
    x = {}
    if opt["--x"]:
        for item in opt["--x"].split(","):
            tag, _, v = item.partition("=")
            pv, _, av = v.partition(":")
            x[tag] = (int(pv), int(av))
    ro = roster_load(os.environ.get("CE_SECAGG_ROSTER", ""))
    seed = seed_load(os.environ.get("CE_SECAGG_ID_KEY", ""))
    last = 0
    if opt["--state"] and os.path.exists(opt["--state"]):
        last = int(open(opt["--state"]).read().strip())
    soul = Soul(ro, seed, OsRng(), last)
    faults = set((opt["--fault"] or "").split(",")) - {""}
    bad = faults - KNOWN_FAULTS
    if bad:
        print("sa4_ref: unknown --fault %s" % ",".join(sorted(bad)))
        return 2
    soul.fault = ",".join(sorted(faults & SOUL_FAULTS)) or None     # faults inside the soul
    if not soul.set_input(fed_words(tags, x), fed_layout(tags)):
        print("sa4_ref: input refused")
        return 2
    fault = faults                              # wire-level faults: checked by membership
    sock = None
    import time
    for _ in range(50):                      # the coordinator may still be starting
        try:
            sock = socket.create_connection((host, int(port)), timeout=float(opt["--timeout"]))
            break
        except ConnectionRefusedError:
            time.sleep(0.2)
    if sock is None:
        print("sa4_ref: cannot connect to %s:%s" % (host, port))
        return 3
    deadline = time.monotonic() + float(opt["--deadline"])   # bounds the whole session

    def send(line):
        data = (line + "\n").encode("latin-1")
        if "drip" in fault:                    # one byte at a time, slowly
            for k in range(len(data)):
                sock.sendall(data[k:k + 1])
                time.sleep(0.2)
            return
        sock.sendall(data)

    pending = bytearray()

    def recv():
        # The deadline is checked before every socket read, so a peer that
        # trickles bytes cannot stretch the session past --deadline.
        while True:
            nl = pending.find(b"\n")
            if nl >= 0:
                if nl > 1000:
                    raise ValueError("line over 1000 bytes")
                line = bytes(pending[:nl])
                del pending[:nl + 1]
                return line.decode("latin-1")
            if len(pending) > 1000:
                raise ValueError("line over 1000 bytes")
            left = deadline - time.monotonic()
            if left <= 0:
                raise TimeoutError("session deadline (--deadline) passed")
            sock.settimeout(min(left, float(opt["--timeout"])))
            chunk = sock.recv(1024)
            if not chunk:
                return None
            pending.extend(chunk)

    try:
        sock.sendall((FED_HELLO + "\n").encode("latin-1"))
        reply = recv()
        if reply != FED_OK:
            print("sa4_ref: handshake refused")
            return 3
        sock.sendall(("FED_JOIN %d 1000\n" % soul.me).encode("latin-1"))
    except (ValueError, OSError) as e:          # nothing secret exists yet
        print("sa4_ref: handshake failed: %s" % e)
        return 3
    print("sa4_ref: joined as id=%d x=%d" % (soul.me, soul.mx), flush=True)
    if "silent" in fault:                     # joins, then never answers
        try:
            while recv() is not None:
                pass
            print("sa4_ref: fault silent: coordinator closed")
        except (ValueError, OSError):
            print("sa4_ref: fault silent: timed out or bad line")
        return 0
    try:
        return _connect_loop(soul, tags, opt, fault, sock, send, recv)
    except (ValueError, OSError) as e:          # socket.timeout is an OSError
        if soul.state == ST_ABORTED:            # refused, then the abort line could not be sent
            print("sa4_ref: refused; the abort line was not delivered: %s" % e)
            return 3
        if soul.state != ST_DONE:
            soul._wipe()
            soul.state = ST_ABORTED
            try:
                sock.sendall((fmt_abort(max(soul.r, 0), soul.me, "transport") + "\n").encode("latin-1"))
            except OSError:
                pass
            print("sa4_ref: refused: transport: %s (abort code transport)" % e)
            return 3
        print("sa4_ref: transport after the round: %s" % e)
        return 0


def _connect_loop(soul, tags, opt, fault, sock, send, recv):
    sums = 0
    applied = []
    after_done = 0
    u3n = 0
    while True:
        line = recv()
        if line is None:
            if soul.state != ST_DONE:            # mid-round EOF: the caller wipes and aborts
                raise ConnectionError("coordinator closed the connection")
            print("sa4_ref: coordinator closed (state %d)" % soul.state)
            return 0
        if soul.state == ST_DONE:
            if line == "BYE":
                print("sa4_ref: BYE after %d aggregate(s)" % sums)
                return 0
            after_done += 1
            if after_done > len(tags):           # an honest coordinator sends at most one per tag
                print("sa4_ref: too many lines after the round; closing")
                return 0
            rec = fed_parse_result(line)
            why = fed_result_why(rec, soul.done_round, tags, u3n, applied)
            if why == "":
                applied.append(rec[1])
                print("sa4_ref: AGGREGATE_SUM round=%d tag=%s sum_promo=%d sum_atr=%d n_part=%d" % rec, flush=True)
                sums += 1
            else:
                print("sa4_ref: ignored a result line (%s)" % why, flush=True)
            continue
        rec = parse(line)
        if soul.state == ST_IDLE and opt["--state"] and rec is not None and rec[0] == EV_ROUND:
            if round_ok(soul, rec) == "":              # write-ahead, only for a round we accept
                with open(opt["--state"] + ".tmp", "w") as fh:
                    fh.write("%d\n" % rec[1])
                    fh.flush()
                    os.fsync(fh.fileno())
                os.replace(opt["--state"] + ".tmp", opt["--state"])
        if rec is not None and rec[0] == EV_SET and rec[2] == 3:
            xs = bitmap_xs(rec[3], soul.ro.n)
            if xs is not None:
                u3n = len(xs)
        st0 = soul.state
        ok, err, outs = soul.handle(line)
        if "bad-adv-sig" in fault:
            outs = [_corrupt_hex_token(o, 7) if o.startswith("SA4_ADV ") else o for o in outs]
        if "bad-sig3" in fault:
            outs = [_corrupt_hex_token(o, 3) if o.startswith("SA4_SIG3 ") else o for o in outs]
        for f in ("bad-b-reveal", "bad-s-reveal"):          # alter the share, keep the proof
            if f in fault:
                want, done1, new = f[4], False, []
                for o in outs:
                    if o.startswith("SA4_REVEAL ") and o.split(" ")[4] == want and not done1:
                        o = _corrupt_hex_token(o, 5)
                        done1 = True
                    new.append(o)
                outs = new
        if "swap-reveal" in fault:
            new = []
            for o in outs:
                if o.startswith("SA4_REVEAL "):
                    t = o.split(" ")
                    t[4] = "s" if t[4] == "b" else "b"
                    o = " ".join(t)
                new.append(o)
            outs = new
        if ok and st0 == ST_SHARED and soul.state == ST_CHECKED:
            if soul.complained:
                print("sa4_ref: complained about %s" % ",".join(str(soul._eid(x)) for x in sorted(soul.complained)),
                      flush=True)
            if "silent-check" in fault:             # answers nothing after SET 5
                print("sa4_ref: fault silent-check: leaving", flush=True)
                soul._wipe()
                sock.close()
                return 0
        if ok and soul.state == ST_OPENED and st0 == ST_CHECKED:
            print("sa4_ref: accused: %d opening(s)" % sum(1 for o in outs if o.startswith("SA4_OPEN ")), flush=True)
        try:
            for o in outs:
                send(o)
        except OSError:
            if ok:
                raise
        if not ok:
            code = outs[-1].split(" ")[-1] if outs else "-"
            print("sa4_ref: %s (abort code %s)" % (err, code))
            return 3
        stops = {"stop-after-adv": ST_ADV, "stop-after-shares": ST_SHARED, "stop-after-check": ST_CHECKED,
                 "stop-after-y": ST_MASKED,
                 "stop-after-sig3": ST_SIGNED}
        sf = next((f for f in sorted(fault) if f in stops), None)
        if sf is not None and soul.state == stops[sf] and outs:
            print("sa4_ref: fault %s: leaving" % sf)
            sock.close()
            return 0
        if soul.state == ST_DONE:
            print("sa4_ref: round %d done" % soul.done_round, flush=True)


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "--connect":
        sys.exit(connect_main(sys.argv[1:]))
    if len(sys.argv) == 2 and sys.argv[1] == "--selftest":
        sys.exit(selftest())
    if len(sys.argv) in (2, 3) and sys.argv[1] == "--pins":
        sys.exit(pins_main(sys.argv[2] if len(sys.argv) == 3 else None))
    if len(sys.argv) in (3, 5) and sys.argv[1] == "--judge":
        sys.exit(judge_main(sys.argv[2:]))
    if len(sys.argv) == 3 and sys.argv[1] == "--dump" and sys.argv[2] in list("ABCDE") + list(H_ROUNDS):
        sys.exit(dump(sys.argv[2]))
    if len(sys.argv) == 4 and sys.argv[1] == "--harness" and sys.argv[2] in list("ABCDE") + list(H_ROUNDS):
        sys.exit(harness_compare(sys.argv[2], sys.argv[3]))
    print(__doc__)
    sys.exit(2)
