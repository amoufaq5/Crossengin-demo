#!/usr/bin/env python3
"""SecAgg v4 soul differential cases (A2.3b; v4-sa2 since A2.4b, v4-sa3 since A2.4c): NOVA soul vs scripts/sa4_ref.py.

    sa4_cases.py gen            print the case script (deterministic)
    sa4_cases.py run SCRIPT     run it through the Python soul
    sa4_cases.py check          gen + run in process; check the expected
                                outcome of the named cases and the honest
                                anchors

tests/tools/sa4_script.nova runs the same script through the NOVA soul
(sa4s_handle). Both print, per step, ok / state / round / done round /
output lines; only the human-readable reason text ('E ' lines) may differ.
tests/integration/scenario_sa4_pyref.sh compares the two.

A script is a list of cases. 'CASE name n idx r last' starts a fresh soul
(roster of n harness souls, soul index idx, test RNG for round r, last round
last); 'I spec' calls set_input with a named malformed input; 'L line' feeds
one line. The cases are honest rounds built with the Python soul (every
signer's keys and one-time seeds kept, so shares, complaints and signatures
can be forged) and then perturbed: refusals in every phase and every abort
code, low-order keys, set_input validation, v4-sa2 commitment cases (every
share / path byte class, another x's share, B / M altered in an ADV,
ciphertext and REVEAL proof lengths), v4-sa3 cases (CHECK: structural share
faults refuse bad_share, content faults become a COMPLAINT; e_pk low-order /
non-canonical / foreign; SET 5 / final SET 2 refusals; ACCUSE / COMPLAINT at
the accused: valid complaints give an OPEN, forged ones END 5 0; SHSIG /
OPEN / COMPLAINT lines out of phase), and seeded random mutations, moves,
duplications and deletions of every line of five rounds.

check: the outcome of a case is its event sequence joined by '>':
'complaint:<kinds>' (a step that sent COMPLAINT lines; kinds of the failing
content check in ascending sender x), 'open:<n>' (a step that sent SA4_END
r 5: n OPEN lines), the abort code, 'done'.
"""
import os
import random
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "scripts"))
import sa4_ref as R  # noqa: E402

OUT = []


def case(name, n, idx, r, last, lines, pre=()):
    OUT.append("CASE %s %d %d %d %d" % (name, n, idx, r, last))
    for p in pre:
        OUT.append("I " + p)
    for line in lines:
        OUT.append("L " + line)


class H:
    """An honest round of harness souls (all keys kept). Phases of ph():
    0 SA4_ROUND; 1 ADVs + SET 1; 2 shares + SET 5 (CHECK, U2'); 3 final
    SET 2 (U2); 4 SET 3; 5 SIG3s + SET 4."""

    def __init__(self, n, r, last, U1, U2, U3, U4, U2p=None):
        self.n, self.r, self.last = n, r, last
        ro = self.ro = R.h_roster(n)
        U2p = list(U2) if U2p is None else U2p
        self.U1, self.U2p, self.U2, self.U3, self.U4 = U1, U2p, U2, U3, U4
        souls = {}
        for x in U1:
            e = ro.entries[x - 1]
            s = R.Soul(ro, bytes.fromhex(R.H_SEEDS[x - 1]), R.h_rng(e[0], r), last, e)
            s.set_input(R.h_input(x - 1, R.H_L), R.h_layout())
            souls[x] = s
        self.rl = R.fmt_round(r, ro.fp, R.H_L, R.h_layout())
        self.adv = {x: souls[x].handle(self.rl)[2][0] for x in U1}
        self.set1 = R.fmt_set(r, 1, R.bitmap(U1))
        self.csk, self.cpk, self.eseed, self.sh, self.shsig = {}, {}, {}, {}, {}
        for x in U1:
            o = []
            for l in [self.adv[y] for y in U1] + [self.set1]:
                ok, err, oo = souls[x].handle(l)
                assert ok, err
                o += oo
            self.csk[x], self.cpk[x], self.eseed[x] = souls[x].csk, souls[x].cpk, souls[x].eseed
            self.h1 = souls[x].h1
            for l in o:
                if l.startswith("SA4_SHARE"):
                    p = R.parse(l)
                    self.sh[(x, ro.x(p[3]))] = l
                if l.startswith("SA4_SHSIG"):
                    self.shsig[x] = l
        self.set5 = R.fmt_set(r, 5, R.bitmap(U2p))
        for x in U2p:
            for l in [self.sh[(v, x)] for v in U2p if v != x] + [self.set5]:
                ok, err, oo = souls[x].handle(l)
                assert ok and not any(q.startswith("SA4_COMPLAINT") for q in oo), err
        self.set2 = R.fmt_set(r, 2, R.bitmap(U2))
        for x in U2:
            ok, err, oo = souls[x].handle(self.set2)
            assert ok, err
        self.set3 = R.fmt_set(r, 3, R.bitmap(U3))
        self.sig = {}
        for x in U3:
            ok, err, oo = souls[x].handle(self.set3)
            assert ok, err
            self.sig[x] = oo[0]
        self.set4 = R.fmt_set(r, 4, R.bitmap(U4))

    def id(self, x):
        return self.ro.entries[x - 1][0]

    def ph(self, t, k):
        if k == 0:
            return [self.rl]
        if k == 1:
            return [self.adv[x] for x in self.U1] + [self.set1]
        if k == 2:
            return [self.sh[(v, t)] for v in self.U2p if v != t] + [self.set5]
        if k == 3:
            return [self.set2]
        if k == 4:
            return [self.set3]
        return [self.sig[x] for x in self.U4] + [self.set4]

    def upto(self, t, k):
        out = []
        for j in range(k + 1):
            out += self.ph(t, j)
        return out

    def rest(self, t, k):
        """Phases k..5."""
        out = []
        for j in range(k, 6):
            out += self.ph(t, j)
        return out

    def signed_adv(self, x, c, s, r=None, bc=None, mr=None):
        """ADV of soul x signed with its real key; B / M default to its honest ones."""
        r = self.r if r is None else r
        a = R.parse(self.adv[x])
        bc = a[6] if bc is None else bc
        mr = a[7] if mr is None else mr
        msg = R.adv_transcript(self.ro.fp, r, self.id(x), R.H_L, R.h_layout(), c, s, bc, mr)
        seed = bytes.fromhex(R.H_SEEDS[x - 1])
        g = R.ed25519_sign(msg, seed, R.ed25519_pk_from_seed(seed))
        return R.fmt_adv(r, self.id(x), c, s, g, bc, mr)

    def e(self, v, t):
        """The one-time key of the share v -> t."""
        return R.eph(self.eseed[v], self.r, self.id(v), self.id(t))

    def share_pt(self, v, t):
        p = R.parse(self.sh[(v, t)])
        ek = R.enc_key(self.csk[t], p[5], self.r, self.id(v), self.id(t))
        return R.share_open(ek, self.r, self.id(v), self.id(t), p[4])

    def forge_share(self, v, t, pt, r=None, aad=None, epk=None):
        """SHARE v -> t sealed under v's real one-time key (e_pk default its own)."""
        r = self.r if r is None else r
        e = self.e(v, t)
        ek = R.enc_key(e, self.cpk[t], self.r, self.id(v), self.id(t))
        a = aad if aad is not None else (self.r, self.id(v), self.id(t))
        ct = R.share_seal(ek, a[0], a[1], a[2], pt)
        return R.fmt_share(r, self.id(v), self.id(t), ct, R.x25519_base(e) if epk is None else epk)

    def lh(self, u, v):
        """Leaf of the line u -> v as v received it."""
        p = R.parse(self.sh[(u, v)])
        return R.sleaf(self.ro.fp, self.r, self.id(u), v, self.id(v), p[5], p[4])

    def complaint(self, v, u, lh=None, r=None, h1=None, signer=None, line_r=None, about=None):
        """COMPLAINT of v about u (signed by signer, default v), over the leaf of u -> v."""
        lh = self.lh(u, v) if lh is None else lh
        signer = v if signer is None else signer
        seed = bytes.fromhex(R.H_SEEDS[signer - 1])
        msg = R.complaint_transcript(self.ro.fp, self.r if r is None else r, self.id(v),
                                     self.id(u if about is None else about), self.h1 if h1 is None else h1, lh)
        g = R.ed25519_sign(msg, seed, R.ed25519_pk_from_seed(seed))
        return R.fmt_complaint(self.r if line_r is None else line_r, self.id(v), self.id(u if about is None else about),
                               lh, g)


def alt(q, off, xor=1):
    """q with byte off xor-ed."""
    q = bytearray(q); q[off] ^= xor
    return bytes(q)


def flip_sig3(line, byte=10):
    p = R.parse(line)
    g = bytearray(p[3]); g[byte] ^= 1
    return R.fmt_sig3(p[1], p[2], bytes(g))


def with_epk(line, epk):
    """SHARE line with its e_pk token replaced."""
    t = line.split(" ")
    t[4] = epk.hex()
    return " ".join(t)


# ---- scripted refusals in every phase
def gen_scripted():

    A = H(4, 5, 4, [1, 2, 3, 4], [1, 2, 3, 4], [1, 2, 3, 4], [1, 2, 3, 4])
    for t in (1, 2, 3, 4):
        case("honest4_t%d" % t, 4, t - 1, 5, 4, A.upto(t, 5))
    T = 1
    base0 = A.ph(T, 0)
    advs = [A.adv[x] for x in A.U1]
    case("adv_reorder", 4, 0, 5, 4, base0 + advs[::-1] + [A.set1] + A.rest(T, 2))
    case("adv_dup_count_ok", 4, 0, 5, 4, base0 + [advs[0], advs[1], advs[1], advs[3], A.set1])
    case("adv_dup_extra", 4, 0, 5, 4, base0 + advs + [advs[2], A.set1])
    case("adv_beyond_n", 4, 0, 5, 4, base0 + advs + [advs[2], advs[3]])
    a3 = R.parse(advs[2])
    case("adv_wrong_round", 4, 0, 5, 4, base0 + advs[:2] + [A.signed_adv(3, a3[3], a3[4], r=6)])
    case("adv_round_again", 4, 0, 5, 4, base0 + advs[:2] + [A.rl])
    case("set1_twice", 4, 0, 5, 4, base0 + advs + [A.set1, A.set1])
    case("set1_self_missing", 4, 0, 5, 4, base0 + advs[1:] + [R.fmt_set(5, 1, R.bitmap([2, 3, 4]))])
    case("set1_self_missing_t2", 4, 1, 5, 4, base0 + [advs[0]] + advs[2:] + [R.fmt_set(5, 1, R.bitmap([1, 3, 4]))])
    case("set1_bits_above_n", 4, 0, 5, 4, base0 + advs + [R.fmt_set(5, 1, R.bitmap([1, 2, 3, 4, 5]))])
    case("set1_bit_256", 4, 0, 5, 4, base0 + advs + [R.fmt_set(5, 1, R.bitmap([1, 2, 3, 256]))])
    case("set1_small", 4, 0, 5, 4, base0 + advs[:2] + [R.fmt_set(5, 1, R.bitmap([1, 2]))])
    case("set1_wrong_phase", 4, 0, 5, 4, base0 + advs + [R.fmt_set(5, 2, R.bitmap([1, 2, 3, 4]))])
    case("set5_in_adv", 4, 0, 5, 4, base0 + advs + [R.fmt_set(5, 5, R.bitmap([1, 2, 3, 4]))])
    case("set1_wrong_round", 4, 0, 5, 4, base0 + advs + [R.fmt_set(6, 1, R.bitmap([1, 2, 3, 4]))])
    case("adv_outside_u1", 4, 0, 5, 4, base0 + advs + [R.fmt_set(5, 1, R.bitmap([1, 2, 3]))])
    case("adv_outside_u1b", 4, 0, 5, 4, base0 + advs[:3] + [R.fmt_set(5, 1, R.bitmap([1, 2, 4]))])
    a2 = R.parse(advs[1])
    case("adv_c_eq_s_unsigned", 4, 0, 5, 4, base0 + [advs[0], R.fmt_adv(5, a2[2], a2[3], a2[3], a2[5], a2[6], a2[7])] + advs[2:] + [A.set1])
    case("adv_c_eq_s_signed", 4, 0, 5, 4, base0 + [advs[0], A.signed_adv(2, a2[3], a2[3])] + advs[2:] + [A.set1])
    a1 = R.parse(advs[0])
    case("adv_c_eq_other_s", 4, 0, 5, 4, base0 + [advs[0], A.signed_adv(2, a1[4], a2[4])] + advs[2:] + [A.set1])
    case("adv_id_not_in_roster", 4, 0, 5, 4, base0 + advs[:3] + [R.fmt_adv(5, 999, a2[3], a2[4], a2[5], a2[6], a2[7]), A.set1])
    case("adv_id_0", 4, 0, 5, 4, base0 + advs[:3] + [R.fmt_adv(5, 0, a2[3], a2[4], a2[5], a2[6], a2[7]), A.set1])
    own = a1
    case("own_adv_altered", 4, 0, 5, 4, base0 + [R.fmt_adv(5, own[2], own[4], own[3], own[5], own[6], own[7])] + advs[1:] + [A.set1])
    g = bytearray(a2[5]); g[0] ^= 1
    case("adv_bad_sig", 4, 0, 5, 4, base0 + [advs[0], R.fmt_adv(5, a2[2], a2[3], a2[4], bytes(g), a2[6], a2[7])] + advs[2:] + [A.set1])
    gg = bytearray(own[5]); gg[0] ^= 1
    case("own_adv_bad_sig", 4, 0, 5, 4, base0 + [R.fmt_adv(5, own[2], own[3], own[4], bytes(gg), own[6], own[7])] + advs[1:] + [A.set1] + A.ph(T, 2))
    # v4-sa2: B and M are covered by the ADV signature and by the own-ADV check
    for nm, k in [("B", 6), ("M", 7)]:
        for pos in (0, 31):
            q = list(a2); q[k] = alt(a2[k], pos)
            case("adv_%s%d_altered" % (nm, pos), 4, 0, 5, 4, base0 + [advs[0], R.fmt_adv(*q[1:])] + advs[2:] + [A.set1])
            q = list(own); q[k] = alt(own[k], pos)
            case("own_adv_%s%d_altered" % (nm, pos), 4, 0, 5, 4, base0 + [R.fmt_adv(*q[1:])] + advs[1:] + [A.set1])
    # a validly signed ADV whose M (or B) is not the one the shares were dealt
    # under: R1 accepts it; CHECK complains about the share (commit) for M;
    # B cannot be checked by a soul, but H1 covers it, so T3 differs (bad_sig3).
    case("adv_M_resigned", 4, 0, 5, 4, base0 + [advs[0], A.signed_adv(2, a2[3], a2[4], mr=alt(a2[7], 3))] + advs[2:] + [A.set1] + A.rest(T, 2))
    case("adv_B_resigned", 4, 0, 5, 4, base0 + [advs[0], A.signed_adv(2, a2[3], a2[4], bc=alt(a2[6], 3))] + advs[2:] + [A.set1] + A.rest(T, 2))
    tk = advs[1].split(" ")
    case("adv_v1_6tok", 4, 0, 5, 4, base0 + [advs[0], " ".join(tk[:5] + tk[7:])] + advs[2:] + [A.set1])
    case("adv_7tok", 4, 0, 5, 4, base0 + [advs[0], " ".join(tk[:6] + tk[7:])] + advs[2:] + [A.set1])
    P = 2 ** 255 - 19
    odd = {"zero": 0, "one": 1, "p": P, "p1": P + 1, "pm1": P - 1,
           "ord8": 0xe0eb7a7c3b41b8ae1656e3faf19fc46ada098deb9c32b1fd866205165f49b800,
           "ord8b": 0x5f9c95bca3508c24b1d0b1559c83ef5b04445cc4581c8e86d8224eddd09f1157,
           "two255m1": 2 ** 255 - 1, "all_ff": 2 ** 256 - 1}
    for nm, v in odd.items():
        k = v.to_bytes(32, "little")
        case("adv_c_%s" % nm, 4, 0, 5, 4, base0 + [advs[0], A.signed_adv(2, k, a2[4])] + advs[2:] + [A.set1])
        case("adv_s_%s" % nm, 4, 0, 5, 4, base0 + [advs[0], A.signed_adv(2, a2[3], k)] + advs[2:] + [A.set1])
    hb = bytearray(a2[3]); hb[31] |= 0x80
    case("adv_c_highbit", 4, 0, 5, 4, base0 + [advs[0], A.signed_adv(2, bytes(hb), a2[4])] + advs[2:] + [A.set1])
    # CHECK (SET 5): pass 1 structure -> bad_share; pass 2 content -> COMPLAINT
    pre2 = A.upto(T, 1)
    shs = A.ph(T, 2)[:-1]
    s5 = A.set5
    case("share_reorder", 4, 0, 5, 4, pre2 + shs[::-1] + [s5] + A.rest(T, 3))
    case("share_dup", 4, 0, 5, 4, pre2 + [shs[0], shs[0], shs[2], s5])
    case("share_dup_extra", 4, 0, 5, 4, pre2 + shs + [shs[0], s5])
    case("share_beyond_n", 4, 0, 5, 4, pre2 + shs + shs[:2])
    case("share_to_other", 4, 0, 5, 4, pre2 + [A.sh[(2, 3)]] + shs[1:] + [s5])
    case("share_wrong_round_line", 4, 0, 5, 4, pre2 + [A.forge_share(2, 1, A.share_pt(2, 1), r=6)])
    case("share_from_self", 4, 0, 5, 4, pre2 + [A.sh[(2, 1)].replace("SA4_SHARE 5 300 7", "SA4_SHARE 5 7 7")] + shs[1:] + [s5])
    case("share_from_unknown", 4, 0, 5, 4, pre2 + [A.sh[(2, 1)].replace("SA4_SHARE 5 300 7", "SA4_SHARE 5 301 7")] + shs[1:] + [s5])
    case("share_hdr_from_swapped", 4, 0, 5, 4, pre2 + [A.sh[(2, 1)].replace("SA4_SHARE 5 300 7", "SA4_SHARE 5 65536 7")] + shs[1:] + [s5])
    case("share_outside_u2p", 4, 0, 5, 4, pre2 + shs + [R.fmt_set(5, 5, R.bitmap([1, 2, 3]))])
    case("share_missing", 4, 0, 5, 4, pre2 + shs[:2] + [s5])
    case("set5_none", 4, 0, 5, 4, pre2 + [s5])
    case("set2_in_shared", 4, 0, 5, 4, pre2 + shs + [A.set2])
    case("set2_in_shared_empty", 4, 0, 5, 4, pre2 + [A.set2])
    case("set5_twice", 4, 0, 5, 4, pre2 + shs + [s5, s5])
    case("set5_bits_above_n", 4, 0, 5, 4, pre2 + shs + [R.fmt_set(5, 5, R.bitmap([1, 2, 3, 4, 5]))])
    case("set5_wrong_round", 4, 0, 5, 4, pre2 + shs + [R.fmt_set(6, 5, R.bitmap([1, 2, 3, 4]))])
    case("share_in_checked", 4, 0, 5, 4, pre2 + shs + [s5, shs[0]])
    pt = bytearray(A.share_pt(2, 1))
    post = shs[1:] + [s5] + A.rest(T, 3)
    for nm, off, val in [("ver", 0, 1), ("from", 4, pt[4] ^ 1), ("to", 8, pt[8] ^ 1), ("round", 16, pt[16] ^ 1),
                         ("x", 17, 2), ("x0", 17, 0), ("sbyte", 20, pt[20] ^ 1), ("ok", 20, pt[20])]:
        q = bytearray(pt); q[off] = val
        case("share_pt_%s" % nm, 4, 0, 5, 4, pre2 + [A.forge_share(2, 1, bytes(q))] + post)
    # v4-sa2 commitment: every share is checked against the dealer's signed
    # root M (content kind "commit" -> COMPLAINT in v4-sa3).
    D = R.depth(4)
    for nm, off in [("s0", 18), ("s31", 49), ("b0", 50), ("b31", 81)] + \
            [("path%d_%s" % (k, e), 82 + 32 * k + (0 if e == "lo" else 31)) for k in range(D) for e in ("lo", "hi")]:
        case("share_cm_%s" % nm, 4, 0, 5, 4, pre2 + [A.forge_share(2, 1, alt(pt, off))] + post)
    pt3 = A.share_pt(2, 3)                       # the dealer's shares and path for x = 3
    po = bytearray(pt3); po[5:9] = pt[5:9]; po[17] = pt[17]
    case("share_cm_otherx", 4, 0, 5, 4, pre2 + [A.forge_share(2, 1, bytes(po))] + post)
    case("share_cm_otherpath", 4, 0, 5, 4, pre2 + [A.forge_share(2, 1, bytes(pt[:82]) + pt3[82:])] + post)
    case("share_cm_swap_sb", 4, 0, 5, 4, pre2 + [A.forge_share(2, 1, bytes(pt[:18]) + bytes(pt[50:82]) + bytes(pt[18:50]) + bytes(pt[82:]))] + post)
    pt4 = A.share_pt(4, 1)
    case("share_cm_last", 4, 0, 5, 4, pre2 + shs[:2] + [A.forge_share(4, 1, alt(pt4, 60))] + [s5] + A.rest(T, 3))
    bad_open = A.sh[(3, 1)].replace("SA4_SHARE 5 65536 7", "SA4_SHARE 5 70000 7")
    # two content failures: complaints in ascending sender x whatever the batch order
    case("share_cm_then_noopen", 4, 0, 5, 4, pre2 + [A.forge_share(2, 1, alt(pt, 18)), shs[1], bad_open, s5] + A.rest(T, 3))
    case("share_noopen_then_cm", 4, 0, 5, 4, pre2 + [bad_open, shs[1], A.forge_share(2, 1, alt(pt, 18)), s5] + A.rest(T, 3))
    case("share_all_bad", 4, 0, 5, 4, pre2 + [A.forge_share(2, 1, alt(pt, 0, 3)), R.fmt_share(5, 65536, 7, R.garbage(R.parse(shs[1])[4]), R.parse(shs[1])[5]),
                                               A.forge_share(4, 1, alt(pt4, 4)), s5] + A.rest(T, 3))
    # plaintext / ciphertext length: D + 1 or D - 1 path nodes (sealed with the
    # real key) -> bad_share (structural); the v1 98-byte ct no longer parses.
    case("share_ct_len_dplus1", 4, 0, 5, 4, pre2 + [A.forge_share(2, 1, bytes(pt) + bytes(32))] + post)
    case("share_ct_len_dminus1", 4, 0, 5, 4, pre2 + [A.forge_share(2, 1, bytes(pt[:-32]))] + post)
    case("share_ct_v1len", 4, 0, 5, 4, pre2 + [A.forge_share(2, 1, bytes(pt[:82]))] + post)
    case("share_pt_v1_v1len", 4, 0, 5, 4, pre2 + [A.forge_share(2, 1, b"\x01" + bytes(pt[1:82]))] + post)
    p0 = R.parse(shs[0])
    ct, epk0 = p0[4], p0[5]
    case("share_ct_k9", 4, 0, 5, 4, pre2 + [R.fmt_share(5, 300, 7, ct + bytes(32 * 7), epk0)] + post)
    case("share_ct_k8", 4, 0, 5, 4, pre2 + [R.fmt_share(5, 300, 7, ct + bytes(32 * 6), epk0)] + post)
    case("share_ct_halfbyte", 4, 0, 5, 4, pre2 + [shs[0] + "0"] + post)
    case("share_aad_round", 4, 0, 5, 4, pre2 + [A.forge_share(2, 1, bytes(pt), aad=(6, 300, 7))] + post)
    case("share_wrong_key", 4, 0, 5, 4, pre2 + [A.sh[(3, 1)].replace("SA4_SHARE 5 65536 7", "SA4_SHARE 5 300 7")] + post)
    case("share_garbage", 4, 0, 5, 4, pre2 + [R.fmt_share(5, 300, 7, R.garbage(ct), epk0)] + post)
    case("share_ct_flip_tag", 4, 0, 5, 4, pre2 + [R.fmt_share(5, 300, 7, alt(ct, len(ct) - 1), epk0)] + post)
    # v4-sa3 one-time key e_pk: the 5 low-order points, non-canonical
    # encodings and the top bit are refused structurally (bad_share); a
    # canonical twist point or another soul's e_pk gives a COMPLAINT (open).
    for i, lo in enumerate(R.LOW_ORDER):
        case("share_epk_low%d" % i, 4, 0, 5, 4, pre2 + [with_epk(shs[0], lo)] + post)
    for nm, v in [("p", P), ("p1", P + 1), ("p4", P + 4), ("two255m1", 2 ** 255 - 1)]:
        case("share_epk_%s" % nm, 4, 0, 5, 4, pre2 + [with_epk(shs[0], v.to_bytes(32, "little"))] + post)
    hb0 = bytearray(epk0); hb0[31] |= 0x80
    case("share_epk_highbit", 4, 0, 5, 4, pre2 + [with_epk(shs[0], bytes(hb0))] + post)
    case("share_epk_twist2", 4, 0, 5, 4, pre2 + [with_epk(shs[0], bytes([2]) + bytes(31))] + post)
    case("share_epk_other", 4, 0, 5, 4, pre2 + [with_epk(shs[0], R.parse(shs[1])[5])] + post)
    case("share_epk_flip0", 4, 0, 5, 4, pre2 + [with_epk(shs[0], alt(epk0, 0))] + post)
    case("share_epk_low_last", 4, 0, 5, 4, pre2 + [A.forge_share(2, 1, bytes(pt), aad=(6, 300, 7))] + shs[1:2] + [with_epk(shs[2], R.LOW_ORDER[4]), s5])
    t5 = shs[0].split(" ")
    case("share_5tok", 4, 0, 5, 4, pre2 + [" ".join(t5[:4] + t5[5:])] + post)
    case("share_7tok", 4, 0, 5, 4, pre2 + [shs[0] + " 00"] + post)
    case("share_epk_upper", 4, 0, 5, 4, pre2 + [" ".join(t5[:4] + [t5[4].upper()] + t5[5:])] + post)
    case("share_epk_63", 4, 0, 5, 4, pre2 + [" ".join(t5[:4] + [t5[4][:63]] + t5[5:])] + post)
    case("share_swap_epk_ct", 4, 0, 5, 4, pre2 + [" ".join(t5[:4] + [t5[5], t5[4]])] + post)
    case("set1_in_shared", 4, 0, 5, 4, pre2 + [A.set1])
    case("adv_in_shared", 4, 0, 5, 4, pre2 + [advs[1]])
    # SHSIG / COMPLAINT / ACCUSE / OPEN / END lines out of phase at a soul
    for st, prefix in (("adv", base0 + advs[:2]), ("shared", pre2 + shs[:1]), ("checked", pre2 + shs + [s5]),
                       ("masked", A.upto(T, 3)), ("signed", A.upto(T, 4))):
        case("shsig_in_%s" % st, 4, 0, 5, 4, prefix + [A.shsig[2]])
        case("open_in_%s" % st, 4, 0, 5, 4, prefix + [R.fmt_open(5, 300, 7, bytes(32))])
        case("end4_in_%s" % st, 4, 0, 5, 4, prefix + [R.fmt_end(5, 4, 300, 0)])
        if st != "checked":
            case("complaint_in_%s" % st, 4, 0, 5, 4, prefix + [A.complaint(2, 1)])
            case("accuse_in_%s" % st, 4, 0, 5, 4, prefix + [R.fmt_accuse(5, R.bitmap([2]))])
    case("shsig_63", 4, 0, 5, 4, pre2 + [A.shsig[2][:-2]])
    case("end6", 4, 0, 5, 4, pre2 + shs + ["SA4_END 5 6 7 0"])
    case("set6", 4, 0, 5, 4, pre2 + shs + ["SA4_SET 5 6 " + "0f" + "00" * 31])
    # final SET 2 (U2) in CHECKED: U2' = {1, 2, 3}, soul 4 left out
    Q = H(4, 5, 4, [1, 2, 3, 4], [1, 2, 3], [1, 2, 3], [1, 2, 3], U2p=[1, 2, 3])
    preq = Q.upto(1, 2)
    case("q_honest_t1", 4, 0, 5, 4, Q.upto(1, 5))
    case("q_honest_t3", 4, 2, 5, 4, Q.upto(3, 5))
    case("u2_not_sub_u2p", 4, 0, 5, 4, preq + [R.fmt_set(5, 2, R.bitmap([1, 2, 3, 4]))])
    case("u2_bits_above_n", 4, 0, 5, 4, preq + [R.fmt_set(5, 2, R.bitmap([1, 2, 3, 5]))])
    case("u2_final_small", 4, 0, 5, 4, preq + [R.fmt_set(5, 2, R.bitmap([1, 2]))])

    case("u2_final_twice", 4, 0, 5, 4, preq + [Q.set2, Q.set2])
    case("u2_final_wrong_round", 4, 0, 5, 4, preq + [R.fmt_set(4, 2, R.bitmap([1, 2, 3]))])
    case("set3_in_checked", 4, 0, 5, 4, preq + [Q.set3])
    case("set5_in_checked", 4, 0, 5, 4, preq + [Q.set5])
    case("share_from_outside_u2p", 4, 0, 5, 4, Q.upto(1, 1) + [Q.sh[(2, 1)], Q.sh[(4, 1)], Q.set5])
    # a complaint, then the coordinator leaves the dealer out: done
    C = H(4, 5, 4, [1, 2, 3, 4], [1, 3, 4], [1, 3, 4], [1, 3, 4], U2p=[1, 2, 3, 4])
    cs = C.ph(1, 2)
    cpt = C.share_pt(2, 1)
    case("complain_then_done", 4, 0, 5, 4, C.upto(1, 1) + [C.forge_share(2, 1, alt(cpt, 20))] + cs[1:] + C.rest(1, 3))
    case("complain_then_u2_with_it", 4, 0, 5, 4, C.upto(1, 1) + [C.forge_share(2, 1, alt(cpt, 20))] + cs[1:] + [A.set2])
    case("complain_then_u2_without_it_t3", 4, 2, 5, 4, C.upto(3, 5))
    case("u2_final_self_missing", 4, 2, 5, 4, C.upto(3, 2) + [R.fmt_set(5, 2, R.bitmap([1, 2, 4]))])
    B = H(4, 5, 4, [1, 2, 3], [1, 2, 3], [1, 2, 3], [1, 2, 3])
    case("u1eqt_honest", 4, 0, 5, 4, B.upto(1, 5))
    case("u1eqt_honest_x3", 4, 2, 5, 4, B.upto(3, 5))
    case("u2p_not_subset_u1", 4, 0, 5, 4, B.upto(1, 1) + B.ph(1, 2)[:-1] + [R.fmt_set(5, 5, R.bitmap([1, 2, 3, 4]))])
    case("u2p_small", 4, 0, 5, 4, B.upto(1, 1) + B.ph(1, 2)[:1] + [R.fmt_set(5, 5, R.bitmap([1, 2]))])
    case("u2p_self_missing", 4, 0, 5, 4, A.upto(1, 1) + [R.fmt_set(5, 5, R.bitmap([2, 3, 4]))])
    pre3 = A.upto(T, 3)
    case("set3_twice", 4, 0, 5, 4, pre3 + [A.set3, A.set3])
    case("set3_self_missing", 4, 0, 5, 4, pre3 + [R.fmt_set(5, 3, R.bitmap([2, 3, 4]))])
    case("set3_small", 4, 0, 5, 4, pre3 + [R.fmt_set(5, 3, R.bitmap([1, 2]))])
    case("set3_not_subset", 4, 0, 5, 4, B.upto(1, 3) + [R.fmt_set(5, 3, R.bitmap([1, 2, 3, 4]))])
    case("y_in_masked", 4, 0, 5, 4, pre3 + ["SA4_Y 5 300 0 1 00000000"])
    case("sig3_in_masked", 4, 0, 5, 4, pre3 + [A.sig[2]])
    case("share_in_masked", 4, 0, 5, 4, pre3 + [shs[0]])
    case("set3_wrong_round", 4, 0, 5, 4, pre3 + [R.fmt_set(4, 3, R.bitmap([1, 2, 3, 4]))])
    case("set4_in_masked", 4, 0, 5, 4, pre3 + [A.set4])
    case("set5_in_masked", 4, 0, 5, 4, pre3 + [A.set5])
    # REVEAL lines are never accepted by a soul: a proof of D(N)+1 units (or
    # any length the parser accepts) is 'unexpected', any other length is
    # a malformed line.
    pre4s = A.upto(T, 4)
    for k in (1, 2, D + 1, 9, 10):
        rv = R.fmt_reveal(5, 300, 7, 0, bytes(32), bytes(32 * k))
        case("reveal_proof_k%d" % k, 4, 0, 5, 4, pre4s + [rv])
    case("reveal_v1_6tok", 4, 0, 5, 4, pre4s + ["SA4_REVEAL 5 300 7 b " + "00" * 32])
    case("reveal_proof_odd", 4, 0, 5, 4, pre4s + ["SA4_REVEAL 5 300 7 s " + "00" * 32 + " " + "00" * 97])
    C5 = H(5, 9, 0, [1, 2, 3, 4, 5], [1, 2, 3, 4, 5], [1, 2, 3, 4, 5], [1, 2, 3, 4, 5])
    for t in (1, 3, 5):
        pre4 = C5.upto(t, 4)
        sigs = [C5.sig[x] for x in C5.U4]
        for pos in (1, 2, 3, 4, 5):
            if pos == t:
                continue
            ss = list(sigs); ss[pos - 1] = flip_sig3(ss[pos - 1])
            case("sig3_bad_t%d_at%d" % (t, pos), 5, t - 1, 9, 0, pre4 + ss + [C5.set4, "garbage"])
        case("sig3_reorder_t%d" % t, 5, t - 1, 9, 0, pre4 + sigs[::-1] + [C5.set4])
        case("sig3_dup_t%d" % t, 5, t - 1, 9, 0, pre4 + sigs[:4] + [sigs[1], C5.set4])
        case("sig3_beyond_n_t%d" % t, 5, t - 1, 9, 0, pre4 + sigs + [sigs[1]])
        ss = list(sigs); ss[t - 1] = flip_sig3(ss[t - 1])
        case("sig3_own_altered_t%d" % t, 5, t - 1, 9, 0, pre4 + ss + [C5.set4])
        drop = 5 if t != 5 else 4
        case("sig3_outside_u4_t%d" % t, 5, t - 1, 9, 0, pre4 + sigs + [R.fmt_set(9, 4, R.bitmap([x for x in range(1, 6) if x != drop]))])
        case("u4_self_missing_t%d" % t, 5, t - 1, 9, 0, pre4 + [s for i, s in enumerate(sigs) if i != t - 1] + [R.fmt_set(9, 4, R.bitmap([x for x in range(1, 6) if x != t]))])
        case("u4_small_t%d" % t, 5, t - 1, 9, 0, pre4 + sigs[:3] + [R.fmt_set(9, 4, R.bitmap([1, 2, 3]))])
        case("sig3_none_t%d" % t, 5, t - 1, 9, 0, pre4 + [C5.set4])
        case("sig3_wrong_round_t%d" % t, 5, t - 1, 9, 0, pre4 + [C5.sig[1].replace("SA4_SIG3 9 ", "SA4_SIG3 10 ")])
        case("sig3_unknown_id_t%d" % t, 5, t - 1, 9, 0, pre4 + sigs[:4] + [C5.sig[5].replace("SA4_SIG3 9 4294967295 ", "SA4_SIG3 9 12 ")] + [C5.set4])
        full = C5.upto(t, 5)
        case("after_done_t%d" % t, 5, t - 1, 9, 0, full + [C5.rl, C5.set4, "garbage"])
        case("after_done_bad_t%d" % t, 5, t - 1, 9, 0, full + ["garbage", C5.rl])
    D5 = H(5, 9, 0, [1, 2, 3, 4, 5], [1, 2, 3, 4, 5], [1, 2, 3, 4], [1, 2, 3, 4])
    case("u4_not_subset_u3", 5, 0, 9, 0, D5.upto(1, 4) + [D5.sig[x] for x in (1, 2, 3, 4)] + [R.fmt_set(9, 4, R.bitmap([1, 2, 3, 4, 5]))])
    case("sig3_from_outside_u3", 5, 0, 9, 0, D5.upto(1, 4) + [D5.sig[x] for x in (1, 2, 3, 4)] + [C5.sig[5], D5.set4])
    case("D_honest_t1", 5, 0, 9, 0, D5.upto(1, 5))
    case("D_honest_t2", 5, 1, 9, 0, D5.upto(2, 5))
    E5 = H(5, 9, 0, [1, 2, 3, 4], [1, 2, 3, 4], [1, 2, 3, 4], [1, 2, 3, 4])
    case("n5_u1eqt_t1", 5, 0, 9, 0, E5.upto(1, 5))
    case("n5_u1eqt_t4", 5, 3, 9, 0, E5.upto(4, 5))
    case("n5_u1eqt_u2small", 5, 0, 9, 0, E5.upto(1, 1) + E5.ph(1, 2)[:2] + [R.fmt_set(9, 5, R.bitmap([1, 2, 3]))])
    case("idle_bad_line", 3, 0, 5, 4, ["hello", "SA4_ROUND"])
    case("idle_set", 3, 0, 5, 4, [R.fmt_set(5, 1, R.bitmap([1, 2, 3]))])
    case("idle_set_r0", 3, 0, 5, 4, [R.fmt_set(0, 1, R.bitmap([1, 2, 3]))])
    case("idle_abort_line", 3, 0, 5, 4, ["SA4_ABORT 5 7 x"])
    case("idle_accuse", 3, 0, 5, 4, [R.fmt_accuse(5, R.bitmap([2]))])
    fp3 = R.h_roster(3).fp
    rl3 = R.fmt_round(5, fp3, R.H_L, R.h_layout())
    case("round_trailing_space", 3, 0, 5, 4, [rl3 + " "])
    case("round_max", 3, 0, 5, 4, [R.fmt_round(2 ** 62 - 1, fp3, R.H_L, R.h_layout())])
    case("round_too_big", 3, 0, 5, 4, [R.fmt_round(2 ** 62, fp3, R.H_L, R.h_layout())])
    case("round_stale_eq", 3, 0, 4, 4, [R.fmt_round(4, fp3, R.H_L, R.h_layout())])
    case("round_upper_hex", 3, 0, 5, 4, [rl3.upper().replace("SA4_ROUND", "SA4_ROUND")])
    case("round_lw0", 3, 0, 5, 4, [R.fmt_round(5, fp3, 0, R.h_layout())])
    case("round_lw_big", 3, 0, 5, 4, [R.fmt_round(5, fp3, 16777217, R.h_layout())])
    case("round_twice_r", 3, 0, 5, 4, [rl3, rl3])


# ---- the accused (soul x1): SA4_ACCUSE with forwarded COMPLAINT lines (7.6)
def acc_round():
    """U2' = 1..4, the final U2 = {1, 2, 3} (complainer 4 left out)."""
    return H(4, 5, 4, [1, 2, 3, 4], [1, 2, 3], [1, 2, 3], [1, 2, 3], U2p=[1, 2, 3, 4])


def gen_accuse():
    Q = acc_round()
    pre = Q.upto(1, 2)
    fin = Q.rest(1, 3)
    acc4 = R.fmt_accuse(5, R.bitmap([4]))
    c4 = Q.complaint(4, 1)
    case("acc_valid_done", 4, 0, 5, 4, pre + [c4, acc4] + fin)
    case("acc_valid_two", 4, 0, 5, 4, pre + [Q.complaint(4, 1), Q.complaint(3, 1), R.fmt_accuse(5, R.bitmap([3, 4]))])
    case("acc_valid_two_rev", 4, 0, 5, 4, pre + [Q.complaint(3, 1), Q.complaint(4, 1), R.fmt_accuse(5, R.bitmap([3, 4]))])
    case("acc_valid_three", 4, 0, 5, 4, pre + [Q.complaint(v, 1) for v in (2, 3, 4)] + [R.fmt_accuse(5, R.bitmap([2, 3, 4]))])
    # forged / replayed / equivocated complaints: no OPEN, no refusal (END 5 0)
    p4 = R.parse(c4)
    forged = {
        "zero_sig": R.fmt_complaint(5, Q.id(4), Q.id(1), p4[4], bytes(64)),
        "flip_sig": R.fmt_complaint(5, Q.id(4), Q.id(1), p4[4], alt(p4[5], 40)),
        "wrong_signer": Q.complaint(4, 1, signer=3),
        "other_leaf": Q.complaint(4, 1, lh=Q.lh(1, 3)),
        "flip_lh": Q.complaint(4, 1, lh=alt(Q.lh(1, 4), 31)),
        "zero_lh": Q.complaint(4, 1, lh=bytes(32)),
        "other_round": Q.complaint(4, 1, r=4),
        "other_h1": Q.complaint(4, 1, h1=R.sha256(b"x")),
        "v2_domain": None,
        "signed_about_other": Q.complaint(4, 1, about=2),
    }
    # a v4-sa2-domain signature over the same transcript bytes
    old = R.SIG_DOMAIN
    R.SIG_DOMAIN = b"crossengin/v4-sa/v2/sig"
    forged["v2_domain"] = Q.complaint(4, 1)
    R.SIG_DOMAIN = old
    fa = forged["signed_about_other"].split(" ")
    fa[3] = str(Q.id(1))
    forged["signed_about_other"] = " ".join(fa)
    for nm, cl in forged.items():
        case("acc_forged_%s" % nm, 4, 0, 5, 4, pre + [cl, acc4] + fin)
    case("acc_forged_and_valid", 4, 0, 5, 4, pre + [forged["zero_sig"].replace(" %d %d " % (Q.id(4), Q.id(1)), " %d %d " % (Q.id(3), Q.id(1)), 1), c4, R.fmt_accuse(5, R.bitmap([3, 4]))])
    # structural ACCUSE / COMPLAINT faults at the accused
    case("acc_bits_above_n", 4, 0, 5, 4, pre + [c4, R.fmt_accuse(5, R.bitmap([4, 5]))])
    case("acc_empty", 4, 0, 5, 4, pre + [R.fmt_accuse(5, bytes(32))])
    case("acc_self", 4, 0, 5, 4, pre + [c4, R.fmt_accuse(5, R.bitmap([1]))])
    case("acc_self_and_other", 4, 0, 5, 4, pre + [c4, c4, R.fmt_accuse(5, R.bitmap([1, 4]))])
    case("acc_no_lines", 4, 0, 5, 4, pre + [acc4])
    case("acc_too_many_lines", 4, 0, 5, 4, pre + [c4, Q.complaint(3, 1), acc4])
    case("acc_about_other", 4, 0, 5, 4, pre + [Q.complaint(4, 2), acc4])
    case("acc_from_outside", 4, 0, 5, 4, pre + [Q.complaint(3, 1), acc4])
    case("acc_from_unknown", 4, 0, 5, 4, pre + [c4.replace("SA4_COMPLAINT 5 70000 ", "SA4_COMPLAINT 5 70001 "), acc4])
    case("acc_two_from_one", 4, 0, 5, 4, pre + [c4, c4, R.fmt_accuse(5, R.bitmap([3, 4]))])
    case("acc_beyond_n", 4, 0, 5, 4, pre + [c4] * 5)
    case("acc_twice", 4, 0, 5, 4, pre + [c4, acc4, acc4])
    case("acc_complaints_then_set2", 4, 0, 5, 4, pre + [c4, Q.set2])
    case("acc_wrong_round", 4, 0, 5, 4, pre + [c4, R.fmt_accuse(6, R.bitmap([4]))])
    case("acc_complaint_wrong_round", 4, 0, 5, 4, pre + [Q.complaint(4, 1, line_r=6), acc4])
    case("acc_complaint_upper", 4, 0, 5, 4, pre + [c4.upper().replace("SA4_COMPLAINT", "SA4_COMPLAINT"), acc4])
    tc = c4.split(" ")
    case("acc_complaint_5tok", 4, 0, 5, 4, pre + [" ".join(tc[:5]), acc4])
    case("acc_complaint_7tok", 4, 0, 5, 4, pre + [c4 + " 00", acc4])
    case("acc_complaint_lh63", 4, 0, 5, 4, pre + [" ".join(tc[:4] + [tc[4][:63]] + tc[5:]), acc4])
    case("acc_complaint_sig_short", 4, 0, 5, 4, pre + [c4[:-2], acc4])
    case("acc_accuse_4tok", 4, 0, 5, 4, pre + [c4, acc4 + " 00"])
    case("acc_accuse_short", 4, 0, 5, 4, pre + [c4, acc4[:-2]])
    case("acc_open_after", 4, 0, 5, 4, pre + [c4, acc4, R.fmt_open(5, 7, 70000, bytes(32))])
    case("acc_complaint_after", 4, 0, 5, 4, pre + [c4, acc4, c4])
    case("acc_set5_after", 4, 0, 5, 4, pre + [c4, acc4, Q.set5])
    case("acc_u2_small", 4, 0, 5, 4, pre + [c4, acc4, R.fmt_set(5, 2, R.bitmap([1, 2]))])
    case("acc_u2_not_sub", 4, 0, 5, 4, pre + [c4, acc4, R.fmt_set(5, 2, R.bitmap([1, 2, 3, 5]))])
    case("acc_u2_self_missing", 4, 0, 5, 4, pre + [c4, acc4, R.fmt_set(5, 2, R.bitmap([2, 3, 4]))])
    case("acc_u2_keeps_complainer", 4, 0, 5, 4, pre + [c4, acc4, R.fmt_set(5, 2, R.bitmap([1, 2, 3, 4]))] + Q.rest(1, 4))
    # an accused that itself complained (about 2): U2 with 2 is refused
    Qc = H(4, 5, 4, [1, 2, 3, 4], [1, 3, 4], [1, 3, 4], [1, 3, 4], U2p=[1, 2, 3, 4])
    cpt = Qc.share_pt(2, 1)
    precc = Qc.upto(1, 1) + [Qc.forge_share(2, 1, alt(cpt, 50))] + Qc.ph(1, 2)[1:]
    c3 = Qc.complaint(3, 1)
    case("acc_complainer_accused_ok", 4, 0, 5, 4, precc + [c3, R.fmt_accuse(5, R.bitmap([3])), R.fmt_set(5, 2, R.bitmap([1, 3, 4]))])
    case("acc_complainer_accused_u2_has_it", 4, 0, 5, 4, precc + [c3, R.fmt_accuse(5, R.bitmap([3])), R.fmt_set(5, 2, R.bitmap([1, 2, 3, 4]))])
    case("acc_accuse_names_complained", 4, 0, 5, 4, precc + [Qc.complaint(2, 1), R.fmt_accuse(5, R.bitmap([2]))])
    # the receiving side of ACCUSE in other targets: x3 accused by 1 and 4
    case("acc_t3_valid", 4, 2, 5, 4, Q.upto(3, 2) + [Q.complaint(1, 3), Q.complaint(4, 3), R.fmt_accuse(5, R.bitmap([1, 4]))])
    case("acc_t3_set2", 4, 2, 5, 4, Q.upto(3, 2) + [Q.complaint(4, 3), acc4] + Q.rest(3, 3))
# ---- low-order keys and set_input validation
def gen_keys_inputs():
    A = H(4, 5, 4, [1, 2, 3, 4], [1, 2, 3, 4], [1, 2, 3, 4], [1, 2, 3, 4])
    advs = [A.adv[x] for x in A.U1]
    a2 = R.parse(advs[1])
    lo = ["0000000000000000000000000000000000000000000000000000000000000000",
          "0100000000000000000000000000000000000000000000000000000000000000",
          "e0eb7a7c3b41b8ae1656e3faf19fc46ada098deb9c32b1fd866205165f49b800",
          "5f9c95bca3508c24b1d0b1559c83ef5b04445cc4581c8e86d8224eddd09f1157",
          "ecffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f",
          "edffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f",
          "eeffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f",
          "cdeb7a7c3b41b8ae1656e3faf19fc46ada098deb9c32b1fd866205165f49b880",
          "4c9c95bca3508c24b1d0b1559c83ef5b04445cc4581c8e86d8224eddd09f11d7",
          "d9ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
          "daffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
          "dbffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"]
    for i, h in enumerate(lo):
        k = bytes.fromhex(h)
        case("lo_c_%d" % i, 4, 0, 5, 4, A.ph(1, 0) + [advs[0], A.signed_adv(2, k, a2[4])] + advs[2:] + [A.set1])
        case("lo_s_%d" % i, 4, 0, 5, 4, A.ph(1, 0) + [advs[0], A.signed_adv(2, a2[3], k)] + advs[2:] + [A.set1])
    # set_input
    rl = A.rl
    for spec in ["empty", "big", "word_2p32", "word_neg", "lay31", "lay33", "len1"]:
        case("in_" + spec, 4, 0, 5, 4, [rl], pre=["reset", spec])
    case("in_after_round", 4, 0, 5, 4, [rl], pre=["after_round"])
    case("in_fail_keeps_old", 4, 0, 5, 4, [rl], pre=["word_neg"])
    case("in_maxword", 4, 0, 5, 4, [rl], pre=["maxword"])


# ---- seeded random perturbations of every line of four rounds
rnd = random.Random(1234)


def gen_random():
    def mutate(line):
        t = line.split(" ")
        m = rnd.randrange(8)
        if m == 0:  # flip a hex char in the longest token
            j = max(range(len(t)), key=lambda i: len(t[i]))
            s = list(t[j]); p = rnd.randrange(len(s)); s[p] = rnd.choice("0123456789abcdef"); t[j] = "".join(s)
        elif m == 1:  # numeric token +-1
            js = [i for i in range(1, len(t)) if t[i].isdigit() and len(t[i]) < 12]
            if js:
                j = rnd.choice(js); t[j] = str(max(0, int(t[j]) + rnd.choice([-1, 1])))
        elif m == 2:
            t = t[:-1]
        elif m == 3:
            t = t + [t[-1]]
        elif m == 4:  # swap id token with another roster id
            js = [i for i in range(2, len(t)) if t[i].isdigit()]
            if js:
                j = rnd.choice(js); t[j] = str(rnd.choice(R.H_IDS + [0, 1, 299]))
        elif m == 5:
            t[0] = rnd.choice(["SA4_ROUND", "SA4_ADV", "SA4_SET", "SA4_SHARE", "SA4_SIG3", "SA4_Y", "SA4_END", "SA4_REVEAL", "SA4_ABORT",
                               "SA4_SHSIG", "SA4_COMPLAINT", "SA4_ACCUSE", "SA4_OPEN"])
        elif m == 6:  # bitmap byte random
            js = [i for i in range(len(t)) if len(t[i]) == 64]
            if js:
                j = rnd.choice(js); s = list(t[j]); s[rnd.randrange(2)] = rnd.choice("0123456789abcdef"); t[j] = "".join(s)
        else:
            j = rnd.randrange(len(t)); t[j] = t[j][:-1]
        return " ".join(t)
    seqs = []
    for (n, r, last, U, tgts) in [(4, 5, 4, ([1,2,3,4],)*4, (1, 3)), (5, 9, 0, ([1,2,3,4,5],[1,2,3,4,5],[1,2,3,4],[1,2,3,4]), (2, 5))]:
        Hh = H(n, r, last, *U)
        for tg in tgts:
            seqs.append(("n%d_t%d" % (n, tg), n, tg, r, last, Hh.upto(tg, 5) if tg in Hh.U3 else Hh.upto(tg, 4)))
    # v4-sa3: the accused x1 (a valid complaint by 4, ACCUSE, OPEN, final U2 without 4)
    Q = acc_round()
    seqs.append(("acc", 4, 1, 5, 4, Q.upto(1, 2) + [Q.complaint(4, 1), R.fmt_accuse(5, R.bitmap([4]))] + Q.rest(1, 3)))
    for (tag, n, tg, r, last, seq) in seqs:
        if True:
            for i in range(len(seq)):
                for k in range(6):
                    s = list(seq); s[i] = mutate(s[i])
                    case("mut_%s_i%d_%d" % (tag, i, k), n, tg - 1, r, last, s)
                # move line i to the end, before final set
                s = list(seq); l = s.pop(i); s.insert(len(s) - 1, l)
                case("mv_%s_i%d" % (tag, i), n, tg - 1, r, last, s)
                s = list(seq); s.insert(i, seq[i])
                case("dupl_%s_i%d" % (tag, i), n, tg - 1, r, last, s)
                s = list(seq); del s[i]
                case("del_%s_i%d" % (tag, i), n, tg - 1, r, last, s)


def run(path, emit=print):
    soul = ro = e = None
    idx = r = last = 0
    k = 0
    for raw in open(path).read().split("\n"):
        if raw.startswith("CASE "):
            f = raw.split(" ")
            name, n, idx, r, last = f[1], int(f[2]), int(f[3]), int(f[4]), int(f[5])
            ro = R.h_roster(n)
            e = ro.entries[idx]
            soul = R.Soul(ro, bytes.fromhex(R.H_SEEDS[idx]), R.h_rng(e[0], r), last, e)
            soul.set_input(R.h_input(idx, R.H_L), R.h_layout())
            emit("C " + name)
            k = 0
        elif raw.startswith("I "):
            spec = raw[2:]
            lay = R.h_layout()
            w = R.h_input(idx, R.H_L)
            ok = None
            if spec == "reset":
                soul = R.Soul(ro, bytes.fromhex(R.H_SEEDS[idx]), R.h_rng(e[0], r), last, e)
            elif spec == "empty": ok = soul.set_input([], lay)
            elif spec == "big": ok = soul.set_input([0] * 16777217, lay)
            elif spec == "word_2p32": w[5] = 2 ** 32; ok = soul.set_input(w, lay)
            elif spec == "word_neg": w[5] = -1; ok = soul.set_input(w, lay)
            elif spec == "lay31": ok = soul.set_input(w, lay[:31])
            elif spec == "lay33": ok = soul.set_input(w, lay + b"\0")
            elif spec == "len1": ok = soul.set_input([5], lay)
            elif spec == "maxword": w[3] = 2 ** 32 - 1; ok = soul.set_input(w, lay)
            elif spec == "after_round":
                soul.handle(R.fmt_round(r, ro.fp, R.H_L, lay)); ok = soul.set_input(w, lay)
            emit("I %s ok=%s st=%d" % (spec, "-" if ok is None else int(ok), soul.state))
        elif raw.startswith("L "):
            ok, err, outs = soul.handle(raw[2:])
            emit("S %d ok=%d st=%d r=%d dr=%d n=%d" % (k, 1 if ok else 0, soul.state, soul.r, soul.done_round, len(outs)))
            for o in outs:
                emit("O " + o)
            if ok and any(o.startswith("SA4_COMPLAINT ") for o in outs):
                # reason text only (E lines are not compared): the failing
                # content-check kinds, ascending sender x
                err = "complaint " + ",".join(soul.check_kinds[x] for x in sorted(soul.check_kinds))
            emit("E " + err)
            k += 1


# ---- self-check: expected outcome of the named cases and the honest anchors
DONE = "done"
EXPECT = {
    "honest4_t1": DONE, "honest4_t2": DONE, "honest4_t3": DONE, "honest4_t4": DONE, "u1eqt_honest": DONE,
    "u1eqt_honest_x3": DONE, "D_honest_t1": DONE, "D_honest_t2": DONE, "n5_u1eqt_t1": DONE, "n5_u1eqt_t4": DONE,
    "q_honest_t1": DONE, "q_honest_t3": DONE, "complain_then_u2_without_it_t3": DONE,
    "adv_reorder": DONE, "share_reorder": DONE, "share_pt_ok": DONE,
    # B is not checkable by a soul, but H1 covers it: T3 differs -> bad_sig3
    "adv_B_resigned": "bad_sig3",
    # v4-sa3: content failures become a COMPLAINT (then the honest final U2
    # still holds the dealer -> bad_set); structural faults stay aborts.
    "adv_M_resigned": "complaint:commit>bad_set",
    "share_pt_ver": "complaint:version>bad_set", "share_pt_from": "complaint:fields>bad_set",
    "share_pt_to": "complaint:fields>bad_set", "share_pt_round": "complaint:fields>bad_set",
    "share_pt_x": "complaint:fields>bad_set", "share_pt_x0": "complaint:fields>bad_set",
    "share_pt_sbyte": "complaint:commit>bad_set", "share_cm_s0": "complaint:commit>bad_set",
    "share_cm_s31": "complaint:commit>bad_set", "share_cm_b0": "complaint:commit>bad_set",
    "share_cm_b31": "complaint:commit>bad_set", "share_cm_path0_lo": "complaint:commit>bad_set",
    "share_cm_path0_hi": "complaint:commit>bad_set", "share_cm_path1_lo": "complaint:commit>bad_set",
    "share_cm_path1_hi": "complaint:commit>bad_set", "share_cm_otherx": "complaint:commit>bad_set",
    "share_cm_otherpath": "complaint:commit>bad_set", "share_cm_swap_sb": "complaint:commit>bad_set",
    "share_cm_last": "complaint:commit>bad_set",
    "share_cm_then_noopen": "complaint:commit,open>bad_set", "share_noopen_then_cm": "complaint:commit,open>bad_set",
    "share_all_bad": "complaint:version,open,fields>bad_set",
    "share_aad_round": "complaint:open>bad_set", "share_wrong_key": "complaint:open>bad_set",
    "share_garbage": "complaint:open>bad_set", "share_ct_flip_tag": "complaint:open>bad_set",
    "share_epk_twist2": "complaint:open>bad_set", "share_epk_other": "complaint:open>bad_set",
    "share_epk_flip0": "complaint:open>bad_set",
    "complain_then_done": "complaint:commit>done", "complain_then_u2_with_it": "complaint:commit>bad_set",
    "share_ct_len_dplus1": "bad_share", "share_ct_len_dminus1": "bad_share", "share_ct_k8": "bad_share",
    "share_ct_v1len": "bad_line", "share_pt_v1_v1len": "bad_line", "share_ct_k9": "bad_line",
    "share_ct_halfbyte": "bad_line",
    "share_epk_low0": "bad_share", "share_epk_low1": "bad_share", "share_epk_low2": "bad_share",
    "share_epk_low3": "bad_share", "share_epk_low4": "bad_share", "share_epk_p": "bad_share",
    "share_epk_p1": "bad_share", "share_epk_p4": "bad_share", "share_epk_two255m1": "bad_share",
    "share_epk_highbit": "bad_share", "share_epk_low_last": "bad_share",
    "share_5tok": "bad_line", "share_7tok": "bad_line", "share_epk_upper": "bad_line", "share_epk_63": "bad_line",
    "share_swap_epk_ct": "bad_line",
    "share_dup": "bad_share", "share_dup_extra": "bad_share", "share_beyond_n": "bad_share",
    "share_to_other": "bad_share", "share_from_self": "bad_share", "share_from_unknown": "bad_share",
    "share_hdr_from_swapped": "bad_share", "share_outside_u2p": "bad_share", "share_missing": "bad_share",
    "set5_none": "bad_share", "share_from_outside_u2p": "bad_share", "share_wrong_round_line": "bad_round",
    "set2_in_shared": "unexpected", "set2_in_shared_empty": "unexpected", "set5_twice": "unexpected",
    "set5_in_adv": "unexpected", "set5_bits_above_n": "bad_set", "set5_wrong_round": "bad_round",
    "share_in_checked": "unexpected", "set5_in_checked": "unexpected", "set3_in_checked": "unexpected",
    "set5_in_masked": "unexpected",
    "u2p_not_subset_u1": "bad_set", "u2p_small": "u2_small", "u2p_self_missing": "not_in_u2",
    "u2_not_sub_u2p": "bad_set", "u2_bits_above_n": "bad_set", "u2_final_small": "u2_small",
    "u2_final_self_missing": "not_in_u2", "u2_final_twice": "unexpected", "u2_final_wrong_round": "bad_round",
    "shsig_in_adv": "unexpected", "shsig_in_shared": "unexpected", "shsig_in_checked": "unexpected",
    "shsig_in_masked": "unexpected", "shsig_in_signed": "unexpected", "shsig_63": "bad_line",
    "open_in_adv": "unexpected", "open_in_shared": "unexpected", "open_in_checked": "unexpected",
    "open_in_masked": "unexpected", "open_in_signed": "unexpected",
    "end4_in_checked": "unexpected", "end4_in_shared": "unexpected",
    "complaint_in_adv": "unexpected", "complaint_in_shared": "unexpected", "complaint_in_masked": "unexpected",
    "accuse_in_adv": "unexpected", "accuse_in_shared": "unexpected", "accuse_in_signed": "unexpected",
    "end6": "bad_line", "set6": "bad_line", "idle_accuse": "unexpected",
    # the accused (7.6)
    "acc_valid_done": "open:1>done", "acc_valid_two": "open:2", "acc_valid_two_rev": "open:2",
    "acc_valid_three": "open:3", "acc_forged_and_valid": "open:1",
    "acc_forged_zero_sig": "open:0>done", "acc_forged_flip_sig": "open:0>done",
    "acc_forged_wrong_signer": "open:0>done", "acc_forged_other_leaf": "open:0>done",
    "acc_forged_flip_lh": "open:0>done", "acc_forged_zero_lh": "open:0>done",
    "acc_forged_other_round": "open:0>done", "acc_forged_other_h1": "open:0>done",
    "acc_forged_v2_domain": "open:0>done", "acc_forged_signed_about_other": "open:0>done",
    "acc_bits_above_n": "bad_set", "acc_empty": "bad_set", "acc_self": "bad_set", "acc_self_and_other": "bad_set",
    "acc_no_lines": "bad_complaint", "acc_too_many_lines": "bad_complaint", "acc_about_other": "bad_complaint",
    "acc_from_outside": "bad_complaint", "acc_from_unknown": "bad_complaint", "acc_two_from_one": "bad_complaint",
    "acc_beyond_n": "bad_complaint", "acc_twice": "open:1>unexpected", "acc_complaints_then_set2": "bad_complaint",
    "acc_wrong_round": "bad_round", "acc_complaint_wrong_round": "bad_round", "acc_complaint_upper": "bad_line",
    "acc_complaint_5tok": "bad_line", "acc_complaint_7tok": "bad_line", "acc_complaint_lh63": "bad_line",
    "acc_complaint_sig_short": "bad_line", "acc_accuse_4tok": "bad_line", "acc_accuse_short": "bad_line",
    "acc_open_after": "open:1>unexpected", "acc_complaint_after": "open:1>unexpected",
    "acc_set5_after": "open:1>unexpected", "acc_u2_small": "open:1>u2_small", "acc_u2_not_sub": "open:1>bad_set",
    "acc_u2_self_missing": "open:1>not_in_u2", "acc_u2_keeps_complainer": "open:1>bad_sig3",
    "acc_complainer_accused_ok": "complaint:commit>open:1", "acc_complainer_accused_u2_has_it": "complaint:commit>open:1>bad_set",
    "acc_accuse_names_complained": "complaint:commit>open:1",
    "acc_t3_valid": "open:2", "acc_t3_set2": "open:1>done",
    "adv_B0_altered": "bad_sig", "adv_B31_altered": "bad_sig", "adv_M0_altered": "bad_sig",
    "adv_M31_altered": "bad_sig", "adv_bad_sig": "bad_sig",
    "own_adv_B0_altered": "bad_adv", "own_adv_B31_altered": "bad_adv", "own_adv_M0_altered": "bad_adv",
    "own_adv_M31_altered": "bad_adv", "own_adv_altered": "bad_adv",
    "adv_v1_6tok": "bad_line", "adv_7tok": "bad_line",
    "reveal_proof_k1": "bad_line", "reveal_proof_k2": "unexpected", "reveal_proof_k3": "unexpected",
    "reveal_proof_k9": "unexpected", "reveal_proof_k10": "bad_line", "reveal_v1_6tok": "bad_line",
    "reveal_proof_odd": "bad_line",
}


def gen_all():
    gen_scripted()
    gen_accuse()
    gen_keys_inputs()
    gen_random()


def outcomes(lines):
    """Per case: the event sequence (complaint:<kinds> / open:<n> / abort code / done)."""
    got, cur = {}, None
    for ln in lines:
        if ln.startswith("C "):
            cur = ln[2:]
            got[cur] = []
            step = []
        elif ln.startswith("S "):
            step = [ln]
        elif ln.startswith("O "):
            step.append(ln)
        elif ln.startswith("E "):
            ev = got[cur]
            outs = [l[2:] for l in step[1:]]
            if any(o.startswith("SA4_COMPLAINT ") for o in outs):
                ev.append("complaint:" + ln[2:].split(" ", 1)[1])
            for o in outs:
                p = o.split(" ")
                if p[0] == "SA4_END" and len(p) == 5 and p[2] == "5":
                    ev.append("open:%d" % sum(1 for q in outs if q.startswith("SA4_OPEN ")))
                if p[0] == "SA4_ABORT":
                    ev.append(p[-1])
            if " st=5 " in step[0] and DONE not in ev:
                ev.append(DONE)
    return {k: ">".join(v) or None for k, v in got.items()}


def check():
    """gen + run in process; assert the outcome of every EXPECT case."""
    import tempfile
    gen_all()
    fd, path = tempfile.mkstemp()
    try:
        with os.fdopen(fd, "w") as fh:
            fh.write("\n".join(OUT))
        lines = []
        run(path, lines.append)
    finally:
        os.unlink(path)
    got = outcomes(lines)
    ncase = sum(1 for o in OUT if o.startswith("CASE "))
    bad = [(k, v, got.get(k, "missing")) for k, v in sorted(EXPECT.items()) if got.get(k, "missing") != v]
    for k, v, g in bad:
        print("sa4_cases check: %s expected %s, got %s" % (k, v, g))
    ev = [v.split(">") for v in got.values() if v]
    print("sa4_cases check: %d cases run, %d outcomes checked, %d refused, %d done, %d with a complaint, "
          "%d with an OPEN" % (len(got), len(EXPECT),
                               sum(1 for v in ev if any(e != DONE and ":" not in e for e in v)),
                               sum(1 for v in ev if v[-1] == DONE),
                               sum(1 for v in ev if any(e.startswith("complaint:") for e in v)),
                               sum(1 for v in ev if any(e.startswith("open:") and e != "open:0" for e in v))))
    if bad or len(got) != ncase:
        print("sa4_cases check: MISMATCH")
        return 1
    print("sa4_cases check: OK")
    return 0


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "gen":
        gen_all()
        print("\n".join(OUT))
        sys.exit(0)
    if len(sys.argv) == 3 and sys.argv[1] == "run":
        run(sys.argv[2])
        sys.exit(0)
    if len(sys.argv) == 2 and sys.argv[1] == "check":
        sys.exit(check())
    print(__doc__)
    sys.exit(2)
