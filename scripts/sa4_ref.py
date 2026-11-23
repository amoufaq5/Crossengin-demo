#!/usr/bin/env python3
"""Independent reference soul for SecAgg v4 (stdlib only).

A second implementation of the v4 soul, written from the wire and protocol
definitions, used to cross-check the NOVA code byte for byte. It mirrors
src/learning/{sa4_wire,sa4_soul,sa_crypto,sa_roster}.nova and
src/safety/{gf256,shamir,saprg,rng (test backend),ed25519,x25519}.nova
with its own primitives (Ed25519, X25519, ChaCha20-Poly1305, HKDF-SHA256,
the ChaCha20 PRG and GF(256) Shamir on Python integers and hashlib/hmac).

It is a test reference, not a production soul: Python cannot wipe secret
bytes, and its PRG is slow for long vectors.

    sa4_ref.py --selftest              RFC / FIPS vectors and the repo's KATs
    sa4_ref.py --dump A|B|C|D|E        print this implementation's transcript
                                       of a tests/sa4_harness.nova scenario
    sa4_ref.py --harness X DUMPFILE    compare it with the NOVA transcript
                                       (tests/tools/sa4_dump.nova output)

Scenarios: A N=3 honest; B N=5, one soul in U2 but not U3; C N=4, one soul
drops after its ADV; D N=5, one soul in U3 but not U4; E 11 refusals.
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
    if not shares or len(shares) > 255 or len(set(xs)) != len(xs):
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
    """sa4w_parse -> tuple (ev, r, ...) or None."""
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
    if k == "SA4_ADV" and n == 6:
        i, c, s, g = _u32(t[2]), _unhex(t[3], 32), _unhex(t[4], 32), _unhex(t[5], 64)
        if i < 0 or None in (c, s, g):
            return None
        return (EV_ADV, r, i, c, s, g)
    if k == "SA4_SET" and n == 4:
        w, bm = _u32(t[2]), _unhex(t[3], 32)
        if not (1 <= w <= 4) or bm is None:
            return None
        return (EV_SET, r, w, bm)
    if k == "SA4_SHARE" and n == 5:
        f, to, ct = _u32(t[2]), _u32(t[3]), _unhex(t[4], 98)
        if f < 0 or to < 0 or ct is None:
            return None
        return (EV_SHARE, r, f, to, ct)
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
    if k == "SA4_REVEAL" and n == 6:
        f, a = _u32(t[2]), _u32(t[3])
        kind = {"b": 0, "s": 1}.get(t[4], -1)
        sh = _unhex(t[5], 32)
        if f < 0 or a < 0 or kind < 0 or sh is None:
            return None
        return (EV_REVEAL, r, f, a, kind, sh)
    if k == "SA4_END" and n == 5:
        ph, i, c = _u32(t[2]), _u32(t[3]), _u32(t[4])
        if not (1 <= ph <= 3) or i < 0 or c < 0:
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
def fmt_adv(r, i, c, s, g): return "SA4_ADV %d %d %s %s %s" % (r, i, c.hex(), s.hex(), g.hex())
def fmt_set(r, k, bm): return "SA4_SET %d %d %s" % (r, k, bm.hex())
def fmt_share(r, f, to, ct): return "SA4_SHARE %d %d %d %s" % (r, f, to, ct.hex())
def fmt_sig3(r, i, g): return "SA4_SIG3 %d %d %s" % (r, i, g.hex())
def fmt_reveal(r, f, a, kind, sh): return "SA4_REVEAL %d %d %d %s %s" % (r, f, a, "s" if kind == 1 else "b", sh.hex())
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


SIG_DOMAIN = b"crossengin/v4-sa/v1/sig"
ADVSET_DOMAIN = b"crossengin/v4-sa/v1/advset"


def sig_prefix(tag, fp, r):
    return SIG_DOMAIN + bytes([len(tag)]) + tag + fp + be(r, 8)


def adv_transcript(fp, r, i, lw, lay, c, s):
    return sig_prefix(b"adv", fp, r) + be(i, 4) + be(lw, 4) + lay + c + s


def advset_hash(bm_u1, keys):
    return sha256(ADVSET_DOMAIN + bm_u1 + b"".join(c + s for c, s in keys))


def t3_transcript(fp, r, h1, bm2, bm3):
    return sig_prefix(b"u3", fp, r) + h1 + bm2 + bm3


def share_pt(f, to, r, x_to, s_sh, b_sh):
    return b"\x01" + be(f, 4) + be(to, 4) + be(r, 8) + bytes([x_to]) + s_sh + b_sh


def share_pt_parse(pt):
    if len(pt) != 82 or pt[0] != 1:
        return None
    return (int.from_bytes(pt[1:5], "big"), int.from_bytes(pt[5:9], "big"),
            int.from_bytes(pt[9:17], "big"), pt[17], pt[18:50], pt[50:82])


# ============================================================ soul
ST_IDLE, ST_ADV, ST_SHARED, ST_MASKED, ST_SIGNED, ST_DONE, ST_ABORTED = range(7)


class Refuse(Exception):
    def __init__(self, code, why):
        super().__init__(why)
        self.code = code
        self.why = why


class Soul:
    """sa4s_*: handle(line) -> (ok, err, out_lines)."""

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

    def set_input(self, words, layout):
        if self.state != ST_IDLE:
            return False
        if not words or len(words) > 16777216 or len(layout) != 32 or any(not (0 <= w <= M32) for w in words):
            return False
        self.x, self.layout = list(words), bytes(layout)
        return True

    def _wipe(self):
        for k in ("csk", "ssk", "b", "held", "seeds"):
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
            collect = {ST_ADV: (EV_ADV, 1, "bad_adv"), ST_SHARED: (EV_SHARE, 2, "bad_share"),
                       ST_MASKED: (None, 3, None), ST_SIGNED: (EV_SIG3, 4, "bad_sig3")}[self.state]
            if collect[0] is not None and ev == collect[0]:
                self.batch.append(rec)
                if len(self.batch) > self.ro.n:
                    raise Refuse(collect[2], "more lines than souls")
                return (True, "", [])
            if ev == EV_SET and rec[2] == collect[1]:
                return [None, self._on_u1, self._on_u2, self._on_u3, self._on_u4][collect[1]](rec[3])
            raise Refuse("unexpected", "unexpected line in state %d" % self.state)
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
        # Draw order: c key, s key, b_u (sa4_soul.nova header).
        self.csk = self.rng.read(32); self.cpk = x25519_base(self.csk)
        self.ssk = self.rng.read(32); self.spk = x25519_base(self.ssk)
        self.b = self.rng.read(32)
        if self.cpk == bytes(32) or self.spk == bytes(32) or self.cpk == self.spk:
            raise Refuse("rng", "key generation refused")
        sig = ed25519_sign(adv_transcript(self.ro.fp, r, self.me, len(self.x), self.layout, self.cpk, self.spk),
                           self.seed, self.pk)
        self.state = ST_ADV
        self.batch = []
        return (True, "", [fmt_adv(r, self.me, self.cpk, self.spk, sig)])

    def _on_u1(self, bm):
        n, t, r, me = self.ro.n, self.ro.t, self.r, self.me
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
            keys[x - 1] = (rec[3], rec[4])
        if keys[self.mx - 1] != (self.cpk, self.spk): raise Refuse("bad_adv", "own ADV altered")
        allk = [k for x in u1 for k in keys[x - 1]]
        if len(set(allk)) != len(allk): raise Refuse("dup_key", "two advertised keys are equal")
        self.seeds = [None] * n
        for vx in u1:
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
                msg = adv_transcript(self.ro.fp, r, rec[2], len(self.x), self.layout, rec[3], rec[4])
                if not ed25519_verify(msg, rec[5], pk):
                    raise Refuse("bad_sig", "ADV signature does not verify")
        self.keys, self.u1 = keys, u1
        self.h1 = advset_hash(bm, [keys[x - 1] for x in u1])
        # Coefficients: b_u first, then s_u^SK.
        bsh = shamir_split(self.rng, self.b, t, n)
        ssh = shamir_split(self.rng, self.ssk, t, n)
        self.held = [None] * n
        outs = []
        for i in range(n):
            x3 = i + 1
            if x3 not in u1:
                continue
            sl, bl = ssh[i][1], bsh[i][1]
            if x3 == self.mx:
                self.held[i] = (sl, bl)
                continue
            v3 = self._eid(x3)
            ek = enc_key(self.csk, keys[i][0], r, me, v3)
            outs.append(fmt_share(r, me, v3, share_seal(ek, r, me, v3, share_pt(me, v3, r, x3, sl, bl))))
        outs.append(fmt_end(r, 1, me, len(outs)))
        self.batch = []
        self.state = ST_SHARED
        return (True, "", outs)

    def _on_u2(self, bm):
        n, t, r, me, mx = self.ro.n, self.ro.t, self.r, self.me, self.mx
        u2 = bitmap_xs(bm, n)
        if u2 is None: raise Refuse("bad_set", "U2 bitmap has bits above N")
        if not set(u2) <= set(self.u1): raise Refuse("bad_set", "U2 is not a subset of U1")
        if len(u2) < t: raise Refuse("u2_small", "|U2| below the threshold")
        if mx not in u2: raise Refuse("not_in_u2", "this soul is not in U2")
        if len(self.batch) != len(u2) - 1: raise Refuse("bad_share", "share lines do not match U2")
        got = set()
        for rec in self.batch:
            v = rec[2]
            vx = self.ro.x(v)
            if vx == 0: raise Refuse("bad_share", "share from an id not in the roster")
            if rec[3] != me: raise Refuse("bad_share", "share addressed to another soul")
            if vx not in u2: raise Refuse("bad_share", "share from a soul outside U2")
            if vx == mx: raise Refuse("bad_share", "share from this soul to itself")
            if vx in got: raise Refuse("bad_share", "two shares from one soul")
            got.add(vx)
            ek = enc_key(self.csk, self.keys[vx - 1][0], r, v, me)
            if ek is None: raise Refuse("bad_key", "key agreement refused")
            pt = share_open(ek, r, v, me, rec[4])
            if pt is None: raise Refuse("bad_share", "share does not open")
            if len(pt) != 82: raise Refuse("bad_share", "share plaintext has the wrong length")
            p = share_pt_parse(pt)
            if p is None: raise Refuse("bad_share", "share plaintext malformed")
            if (p[0], p[1], p[2], p[3]) != (v, me, r, mx):
                raise Refuse("bad_share", "share plaintext ids, round or x differ")
            self.held[vx - 1] = (p[4], p[5])
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
            if ox in self.u3:
                outs.append(fmt_reveal(r, me, self._eid(ox), 0, hv[1]))
            else:
                outs.append(fmt_reveal(r, me, self._eid(ox), 1, hv[0]))
        outs.append(fmt_end(r, 3, me, len(outs)))
        self._wipe()
        self.done_round = r
        self.state = ST_DONE
        return (True, "", outs)


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
    set2 = fmt_set(r, 2, bitmap(u2))
    u3 = []
    for x in u2:
        me = ro.entries[x - 1][0]
        mine = [l for l in shares if parse(l)[3] == me] + [set2]
        o = feed(souls[x - 1], mine)
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


def refusal_lines():
    """The 11 refusal cases of sa4_dump.nova E, as 'CASE k ok=.. last=..' lines."""
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
             [rl, advs[0], fmt_adv(5, a1[2], a1[3], a1[4], bytes(g)), advs[2], fmt_set(5, 1, bm([1, 2, 3]))],
             [rl] + advs + [fmt_set(5, 1, bm([1, 2, 3, 4]))], [rl, advs[0], advs[1], fmt_set(5, 1, bm([1, 2, 3]))],
             [rl] + advs + [advs[2], fmt_set(5, 1, bm([1, 2, 3]))]]
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
    ro, advs, allv = h_run3(*SCEN[which])
    got = ["ADV " + l for l in advs] + ["OUT " + l for l in allv]
    want = [l.rstrip("\n") for l in open(dump) if l.startswith(("ADV ", "OUT "))]
    fpl = [l for l in open(dump) if l.startswith("#FP ")]
    if fpl:
        print("fingerprint", "MATCH" if fpl[0].split()[1] == ro.fp.hex() else "DIFF")
    same = sum(1 for a, b in zip(got, want) if a == b)
    print("scenario %s: python %d lines, nova %d lines, identical prefix-aligned %d" % (which, len(got), len(want), same))
    for a, b in zip(got, want):
        if a != b:
            print("FIRST DIFF\n  py  : %s\n  nova: %s" % (a[:160], b[:160]))
            break
    return 0 if got == want else 1


# ============================================================ selftest
def selftest():
    H = lambda b: b.hex()
    # GF(256) FIPS-197
    assert gf_mul(0x57, 0x83) == 0xC1 and gf_mul(0x57, 0x13) == 0xFE and gf_inv(0x53) == 0xCA and gf_inv(0) == 0
    assert all(gf_mul(a, gf_inv(a)) == 1 for a in range(1, 256))
    # Shamir S0 round trip
    s0 = shamir_split_coeffs(b"\x42", 3, 5, b"\x13\x37")
    assert all(shamir_combine([s0[i] for i in c], 1) == b"\x42" for c in [(0, 1, 2), (1, 3, 4), (4, 2, 0)])
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
    # wire round trips
    assert parse("SA4_END 5 1 7 2") == (EV_END, 5, 1, 7, 2)
    for bad in ["SA4_END 05 1 7 2", "SA4_END 5 1 7  2", "SA4_END 5 1 7 2 ", "SA4_END 4611686018427387904 1 7 2",
                "SA4_ABORT 1 2 Bad", "SA4_SET 1 5 " + "00" * 32]:
        assert parse(bad) is None, bad
    assert parse("SA4_END 4611686018427387903 1 7 2") is not None
    assert bitmap([1, 9, 255]) [0] == 1 and bitmap_xs(bitmap([1, 9]), 8) is None
    print("sa4_ref selftest: OK")
    return 0


def dump(which):
    """Print this implementation's transcript in the sa4_dump.nova format."""
    if which == "E":
        for line in refusal_lines():
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


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "--selftest":
        sys.exit(selftest())
    if len(sys.argv) == 3 and sys.argv[1] == "--dump" and sys.argv[2] in "ABCDE":
        sys.exit(dump(sys.argv[2]))
    if len(sys.argv) == 4 and sys.argv[1] == "--harness" and sys.argv[2] in "ABCDE":
        sys.exit(harness_compare(sys.argv[2], sys.argv[3]))
    print(__doc__)
    sys.exit(2)
