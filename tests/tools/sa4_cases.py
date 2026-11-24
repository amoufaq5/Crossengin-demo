#!/usr/bin/env python3
"""SecAgg v4 soul differential cases (A2.3b, v4-sa2 since A2.4b): NOVA soul vs scripts/sa4_ref.py.

    sa4_cases.py gen            print the case script (deterministic)
    sa4_cases.py run SCRIPT     run it through the Python soul
    sa4_cases.py check          gen + run in process; check the expected
                                outcome (abort code or done) of the named
                                v4-sa2 cases and the honest anchors

tests/tools/sa4_script.nova runs the same script through the NOVA soul
(sa4s_handle). Both print, per step, ok / state / round / done round /
output lines; only the human-readable reason text ('E ' lines) may differ.
tests/integration/scenario_sa4_pyref.sh compares the two.

A script is a list of cases. 'CASE name n idx r last' starts a fresh soul
(roster of n harness souls, soul index idx, test RNG for round r, last round
last); 'I spec' calls set_input with a named malformed input; 'L line' feeds
one line. The cases are honest rounds built with the Python soul (every
signer's keys kept, so shares and signatures can be forged) and then
perturbed: refusals in every phase and every abort code, low-order keys,
set_input validation, v4-sa2 commitment cases (every share / path byte
class, another x's share, B / M altered in an ADV, ciphertext and REVEAL
proof lengths), and seeded random mutations, moves, duplications and
deletions of every line of four rounds.
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
    def __init__(self, n, r, last, U1, U2, U3, U4):
        self.n, self.r, self.last = n, r, last
        ro = self.ro = R.h_roster(n)
        self.U1, self.U2, self.U3, self.U4 = U1, U2, U3, U4
        souls = {}
        for x in U1:
            e = ro.entries[x - 1]
            s = R.Soul(ro, bytes.fromhex(R.H_SEEDS[x - 1]), R.h_rng(e[0], r), last, e)
            s.set_input(R.h_input(x - 1, R.H_L), R.h_layout())
            souls[x] = s
        self.rl = R.fmt_round(r, ro.fp, R.H_L, R.h_layout())
        self.adv = {x: souls[x].handle(self.rl)[2][0] for x in U1}
        self.set1 = R.fmt_set(r, 1, R.bitmap(U1))
        self.csk, self.cpk, self.sh = {}, {}, {}
        for x in U1:
            o = []
            for l in [self.adv[y] for y in U1] + [self.set1]:
                ok, err, oo = souls[x].handle(l)
                assert ok, err
                o += oo
            self.csk[x] = souls[x].csk
            self.cpk[x] = souls[x].cpk
            for l in o:
                if l.startswith("SA4_SHARE"):
                    p = R.parse(l)
                    self.sh[(x, ro.x(p[3]))] = l
        self.set2 = R.fmt_set(r, 2, R.bitmap(U2))
        for x in U2:
            for l in [self.sh[(v, x)] for v in U2 if v != x] + [self.set2]:
                ok, err, oo = souls[x].handle(l)
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
            return [self.sh[(v, t)] for v in self.U2 if v != t] + [self.set2]
        if k == 3:
            return [self.set3]
        return [self.sig[x] for x in self.U4] + [self.set4]

    def upto(self, t, k):
        out = []
        for j in range(k + 1):
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

    def share_pt(self, v, t):
        p = R.parse(self.sh[(v, t)])
        ek = R.enc_key(self.csk[v], self.cpk[t], self.r, self.id(v), self.id(t))
        return R.share_open(ek, self.r, self.id(v), self.id(t), p[4])

    def forge_share(self, v, t, pt, r=None, aad=None):
        r = self.r if r is None else r
        ek = R.enc_key(self.csk[v], self.cpk[t], self.r, self.id(v), self.id(t))
        a = aad if aad is not None else (self.r, self.id(v), self.id(t))
        ct = R.share_seal(ek, a[0], a[1], a[2], pt)
        return R.fmt_share(r, self.id(v), self.id(t), ct)


def alt(q, off, xor=1):
    """q with byte off xor-ed."""
    q = bytearray(q); q[off] ^= xor
    return bytes(q)


def flip_sig3(line, byte=10):
    p = R.parse(line)
    g = bytearray(p[3]); g[byte] ^= 1
    return R.fmt_sig3(p[1], p[2], bytes(g))


# ---- scripted refusals in every phase
def gen_scripted():

    A = H(4, 5, 4, [1, 2, 3, 4], [1, 2, 3, 4], [1, 2, 3, 4], [1, 2, 3, 4])
    for t in (1, 2, 3, 4):
        case("honest4_t%d" % t, 4, t - 1, 5, 4, A.upto(t, 4))
    T = 1
    base0 = A.ph(T, 0)
    advs = [A.adv[x] for x in A.U1]
    case("adv_reorder", 4, 0, 5, 4, base0 + advs[::-1] + [A.set1] + A.ph(T, 2) + A.ph(T, 3) + A.ph(T, 4))
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
    # under: R1 accepts it; R2 refuses the share (bad_commit) for M; B cannot
    # be checked by a soul, but H1 covers it, so the T3 differs (bad_sig3).
    case("adv_M_resigned", 4, 0, 5, 4, base0 + [advs[0], A.signed_adv(2, a2[3], a2[4], mr=alt(a2[7], 3))] + advs[2:] + [A.set1] + A.ph(T, 2) + A.ph(T, 3) + A.ph(T, 4))
    case("adv_B_resigned", 4, 0, 5, 4, base0 + [advs[0], A.signed_adv(2, a2[3], a2[4], bc=alt(a2[6], 3))] + advs[2:] + [A.set1] + A.ph(T, 2) + A.ph(T, 3) + A.ph(T, 4))
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
    # R2
    pre2 = A.upto(T, 1)
    shs = A.ph(T, 2)[:-1]
    case("share_reorder", 4, 0, 5, 4, pre2 + shs[::-1] + [A.set2] + A.ph(T, 3) + A.ph(T, 4))
    case("share_dup", 4, 0, 5, 4, pre2 + [shs[0], shs[0], shs[2], A.set2])
    case("share_dup_extra", 4, 0, 5, 4, pre2 + shs + [shs[0], A.set2])
    case("share_beyond_n", 4, 0, 5, 4, pre2 + shs + shs[:2])
    case("share_to_other", 4, 0, 5, 4, pre2 + [A.sh[(2, 3)]] + shs[1:] + [A.set2])
    case("share_wrong_round_line", 4, 0, 5, 4, pre2 + [A.forge_share(2, 1, A.share_pt(2, 1), r=6)])
    case("share_from_self", 4, 0, 5, 4, pre2 + [A.sh[(2, 1)].replace("SA4_SHARE 5 300 7", "SA4_SHARE 5 7 7")] + shs[1:] + [A.set2])
    case("share_from_unknown", 4, 0, 5, 4, pre2 + [A.sh[(2, 1)].replace("SA4_SHARE 5 300 7", "SA4_SHARE 5 301 7")] + shs[1:] + [A.set2])
    case("share_hdr_from_swapped", 4, 0, 5, 4, pre2 + [A.sh[(2, 1)].replace("SA4_SHARE 5 300 7", "SA4_SHARE 5 65536 7")] + shs[1:] + [A.set2])
    case("share_outside_u2", 4, 0, 5, 4, pre2 + shs + [R.fmt_set(5, 2, R.bitmap([1, 2, 3]))])
    case("share_missing", 4, 0, 5, 4, pre2 + shs[:2] + [A.set2])
    case("set2_none", 4, 0, 5, 4, pre2 + [A.set2])
    pt = bytearray(A.share_pt(2, 1))
    for nm, off, val in [("ver", 0, 1), ("from", 4, pt[4] ^ 1), ("to", 8, pt[8] ^ 1), ("round", 16, pt[16] ^ 1),
                         ("x", 17, 2), ("x0", 17, 0), ("sbyte", 20, pt[20] ^ 1), ("ok", 20, pt[20])]:
        q = bytearray(pt); q[off] = val
        case("share_pt_%s" % nm, 4, 0, 5, 4, pre2 + [A.forge_share(2, 1, bytes(q))] + shs[1:] + [A.set2] + A.ph(T, 3) + A.ph(T, 4))
    # v4-sa2: every share is checked against the dealer's signed root M
    # (bad_commit), after open / length / fields (bad_share), share by share
    # in batch order.
    D = R.depth(4)
    post = shs[1:] + [A.set2] + A.ph(T, 3) + A.ph(T, 4)
    for nm, off in [("s0", 18), ("s31", 49), ("b0", 50), ("b31", 81)] + \
            [("path%d_%s" % (k, e), 82 + 32 * k + (0 if e == "lo" else 31)) for k in range(D) for e in ("lo", "hi")]:
        case("share_cm_%s" % nm, 4, 0, 5, 4, pre2 + [A.forge_share(2, 1, alt(pt, off))] + post)
    pt3 = A.share_pt(2, 3)                       # the dealer's shares and path for x = 3
    po = bytearray(pt3); po[5:9] = pt[5:9]; po[17] = pt[17]
    case("share_cm_otherx", 4, 0, 5, 4, pre2 + [A.forge_share(2, 1, bytes(po))] + post)
    case("share_cm_otherpath", 4, 0, 5, 4, pre2 + [A.forge_share(2, 1, bytes(pt[:82]) + pt3[82:])] + post)
    case("share_cm_swap_sb", 4, 0, 5, 4, pre2 + [A.forge_share(2, 1, bytes(pt[:18]) + bytes(pt[50:82]) + bytes(pt[18:50]) + bytes(pt[82:]))] + post)
    pt4 = A.share_pt(4, 1)
    case("share_cm_last", 4, 0, 5, 4, pre2 + shs[:2] + [A.forge_share(4, 1, alt(pt4, 60))] + [A.set2])
    bad_open = A.sh[(3, 1)].replace("SA4_SHARE 5 65536 7", "SA4_SHARE 5 70000 7")
    case("share_cm_then_noopen", 4, 0, 5, 4, pre2 + [A.forge_share(2, 1, alt(pt, 18)), shs[1], bad_open, A.set2])
    case("share_noopen_then_cm", 4, 0, 5, 4, pre2 + [bad_open, shs[1], A.forge_share(2, 1, alt(pt, 18)), A.set2])
    # plaintext / ciphertext length: D + 1 or D - 1 path nodes (sealed with the
    # real key) -> bad_share; the v1 98-byte ciphertext no longer parses.
    case("share_ct_len_dplus1", 4, 0, 5, 4, pre2 + [A.forge_share(2, 1, bytes(pt) + bytes(32))] + post)
    case("share_ct_len_dminus1", 4, 0, 5, 4, pre2 + [A.forge_share(2, 1, bytes(pt[:-32]))] + post)
    case("share_ct_v1len", 4, 0, 5, 4, pre2 + [A.forge_share(2, 1, bytes(pt[:82]))] + post)
    case("share_pt_v1_v1len", 4, 0, 5, 4, pre2 + [A.forge_share(2, 1, b"\x01" + bytes(pt[1:82]))] + post)
    ct = R.parse(shs[0])[4]
    case("share_ct_k9", 4, 0, 5, 4, pre2 + [R.fmt_share(5, 300, 7, ct + bytes(32 * 7))] + post)
    case("share_ct_k8", 4, 0, 5, 4, pre2 + [R.fmt_share(5, 300, 7, ct + bytes(32 * 6))] + post)
    case("share_ct_halfbyte", 4, 0, 5, 4, pre2 + [shs[0] + "0"] + post)
    case("share_aad_round", 4, 0, 5, 4, pre2 + [A.forge_share(2, 1, bytes(pt), aad=(6, 300, 7))] + shs[1:] + [A.set2])
    case("share_wrong_key", 4, 0, 5, 4, pre2 + [A.sh[(3, 1)].replace("SA4_SHARE 5 65536 7", "SA4_SHARE 5 300 7")] + shs[1:] + [A.set2])
    case("set1_in_shared", 4, 0, 5, 4, pre2 + [A.set1])
    case("adv_in_shared", 4, 0, 5, 4, pre2 + [advs[1]])
    B = H(4, 5, 4, [1, 2, 3], [1, 2, 3], [1, 2, 3], [1, 2, 3])
    case("u1eqt_honest", 4, 0, 5, 4, B.upto(1, 4))
    case("u1eqt_honest_x3", 4, 2, 5, 4, B.upto(3, 4))
    case("u2_not_subset_u1", 4, 0, 5, 4, B.upto(1, 1) + B.ph(1, 2)[:-1] + [R.fmt_set(5, 2, R.bitmap([1, 2, 3, 4]))])
    case("u2_small", 4, 0, 5, 4, B.upto(1, 1) + B.ph(1, 2)[:1] + [R.fmt_set(5, 2, R.bitmap([1, 2]))])
    case("u2_self_missing", 4, 0, 5, 4, B.upto(1, 1) + [R.fmt_set(5, 2, R.bitmap([2, 3]))])
    pre3 = A.upto(T, 2)
    case("set3_twice", 4, 0, 5, 4, pre3 + [A.set3, A.set3])
    case("set3_self_missing", 4, 0, 5, 4, pre3 + [R.fmt_set(5, 3, R.bitmap([2, 3, 4]))])
    case("set3_small", 4, 0, 5, 4, pre3 + [R.fmt_set(5, 3, R.bitmap([1, 2]))])
    case("set3_not_subset", 4, 0, 5, 4, B.upto(1, 2) + [R.fmt_set(5, 3, R.bitmap([1, 2, 3, 4]))])
    case("y_in_masked", 4, 0, 5, 4, pre3 + ["SA4_Y 5 300 0 1 00000000"])
    case("sig3_in_masked", 4, 0, 5, 4, pre3 + [A.sig[2]])
    case("share_in_masked", 4, 0, 5, 4, pre3 + [shs[0]])
    case("set3_wrong_round", 4, 0, 5, 4, pre3 + [R.fmt_set(4, 3, R.bitmap([1, 2, 3, 4]))])
    case("set4_in_masked", 4, 0, 5, 4, pre3 + [A.set4])
    # REVEAL lines are never accepted by a soul: a proof of D(N)+1 units (or
    # any length the parser accepts) is 'unexpected', any other length is
    # a malformed line.
    pre4s = A.upto(T, 3)
    for k in (1, 2, D + 1, 9, 10):
        rv = R.fmt_reveal(5, 300, 7, 0, bytes(32), bytes(32 * k))
        case("reveal_proof_k%d" % k, 4, 0, 5, 4, pre4s + [rv])
    case("reveal_v1_6tok", 4, 0, 5, 4, pre4s + ["SA4_REVEAL 5 300 7 b " + "00" * 32])
    case("reveal_proof_odd", 4, 0, 5, 4, pre4s + ["SA4_REVEAL 5 300 7 s " + "00" * 32 + " " + "00" * 97])
    C = H(5, 9, 0, [1, 2, 3, 4, 5], [1, 2, 3, 4, 5], [1, 2, 3, 4, 5], [1, 2, 3, 4, 5])
    for t in (1, 3, 5):
        pre4 = C.upto(t, 3)
        sigs = [C.sig[x] for x in C.U4]
        for pos in (1, 2, 3, 4, 5):
            if pos == t:
                continue
            ss = list(sigs); ss[pos - 1] = flip_sig3(ss[pos - 1])
            case("sig3_bad_t%d_at%d" % (t, pos), 5, t - 1, 9, 0, pre4 + ss + [C.set4, "garbage"])
        case("sig3_reorder_t%d" % t, 5, t - 1, 9, 0, pre4 + sigs[::-1] + [C.set4])
        case("sig3_dup_t%d" % t, 5, t - 1, 9, 0, pre4 + sigs[:4] + [sigs[1], C.set4])
        case("sig3_beyond_n_t%d" % t, 5, t - 1, 9, 0, pre4 + sigs + [sigs[1]])
        ss = list(sigs); ss[t - 1] = flip_sig3(ss[t - 1])
        case("sig3_own_altered_t%d" % t, 5, t - 1, 9, 0, pre4 + ss + [C.set4])
        drop = 5 if t != 5 else 4
        case("sig3_outside_u4_t%d" % t, 5, t - 1, 9, 0, pre4 + sigs + [R.fmt_set(9, 4, R.bitmap([x for x in range(1, 6) if x != drop]))])
        case("u4_self_missing_t%d" % t, 5, t - 1, 9, 0, pre4 + [s for i, s in enumerate(sigs) if i != t - 1] + [R.fmt_set(9, 4, R.bitmap([x for x in range(1, 6) if x != t]))])
        case("u4_small_t%d" % t, 5, t - 1, 9, 0, pre4 + sigs[:3] + [R.fmt_set(9, 4, R.bitmap([1, 2, 3]))])
        case("sig3_none_t%d" % t, 5, t - 1, 9, 0, pre4 + [C.set4])
        case("sig3_wrong_round_t%d" % t, 5, t - 1, 9, 0, pre4 + [C.sig[1].replace("SA4_SIG3 9 ", "SA4_SIG3 10 ")])
        case("sig3_unknown_id_t%d" % t, 5, t - 1, 9, 0, pre4 + sigs[:4] + [C.sig[5].replace("SA4_SIG3 9 4294967295 ", "SA4_SIG3 9 12 ")] + [C.set4])
        full = C.upto(t, 4)
        case("after_done_t%d" % t, 5, t - 1, 9, 0, full + [C.rl, C.set4, "garbage"])
        case("after_done_bad_t%d" % t, 5, t - 1, 9, 0, full + ["garbage", C.rl])
    D = H(5, 9, 0, [1, 2, 3, 4, 5], [1, 2, 3, 4, 5], [1, 2, 3, 4], [1, 2, 3, 4])
    case("u4_not_subset_u3", 5, 0, 9, 0, D.upto(1, 3) + [D.sig[x] for x in (1, 2, 3, 4)] + [R.fmt_set(9, 4, R.bitmap([1, 2, 3, 4, 5]))])
    case("sig3_from_outside_u3", 5, 0, 9, 0, D.upto(1, 3) + [D.sig[x] for x in (1, 2, 3, 4)] + [C.sig[5], D.set4])
    case("D_honest_t1", 5, 0, 9, 0, D.upto(1, 4))
    case("D_honest_t2", 5, 1, 9, 0, D.upto(2, 4))
    E = H(5, 9, 0, [1, 2, 3, 4], [1, 2, 3, 4], [1, 2, 3, 4], [1, 2, 3, 4])
    case("n5_u1eqt_t1", 5, 0, 9, 0, E.upto(1, 4))
    case("n5_u1eqt_t4", 5, 3, 9, 0, E.upto(4, 4))
    case("n5_u1eqt_u2small", 5, 0, 9, 0, E.upto(1, 1) + E.ph(1, 2)[:2] + [R.fmt_set(9, 2, R.bitmap([1, 2, 3]))])
    case("idle_bad_line", 3, 0, 5, 4, ["hello", "SA4_ROUND"])
    case("idle_set", 3, 0, 5, 4, [R.fmt_set(5, 1, R.bitmap([1, 2, 3]))])
    case("idle_set_r0", 3, 0, 5, 4, [R.fmt_set(0, 1, R.bitmap([1, 2, 3]))])
    case("idle_abort_line", 3, 0, 5, 4, ["SA4_ABORT 5 7 x"])
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
            t[0] = rnd.choice(["SA4_ROUND", "SA4_ADV", "SA4_SET", "SA4_SHARE", "SA4_SIG3", "SA4_Y", "SA4_END", "SA4_REVEAL", "SA4_ABORT"])
        elif m == 6:  # bitmap byte random
            js = [i for i in range(len(t)) if len(t[i]) == 64]
            if js:
                j = rnd.choice(js); s = list(t[j]); s[rnd.randrange(2)] = rnd.choice("0123456789abcdef"); t[j] = "".join(s)
        else:
            j = rnd.randrange(len(t)); t[j] = t[j][:-1]
        return " ".join(t)
    for (n, r, last, U, tgts) in [(4, 5, 4, ([1,2,3,4],)*4, (1, 3)), (5, 9, 0, ([1,2,3,4,5],[1,2,3,4,5],[1,2,3,4],[1,2,3,4]), (2, 5))]:
        Hh = H(n, r, last, *U)
        for tg in tgts:
            seq = Hh.upto(tg, 4) if tg in Hh.U3 else Hh.upto(tg, 3)
            for i in range(len(seq)):
                for k in range(6):
                    s = list(seq); s[i] = mutate(s[i])
                    case("mut_n%d_t%d_i%d_%d" % (n, tg, i, k), n, tg - 1, r, last, s)
                # move line i to the end, before final set
                s = list(seq); l = s.pop(i); s.insert(len(s) - 1, l)
                case("mv_n%d_t%d_i%d" % (n, tg, i), n, tg - 1, r, last, s)
                s = list(seq); s.insert(i, seq[i])
                case("dupl_n%d_t%d_i%d" % (n, tg, i), n, tg - 1, r, last, s)
                s = list(seq); del s[i]
                case("del_n%d_t%d_i%d" % (n, tg, i), n, tg - 1, r, last, s)


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
            emit("E " + err)
            k += 1


# ---- self-check: expected final outcome of the named v4-sa2 and anchor cases
DONE = "done"
EXPECT = {
    "honest4_t1": DONE, "honest4_t2": DONE, "honest4_t3": DONE, "honest4_t4": DONE, "u1eqt_honest": DONE,
    "u1eqt_honest_x3": DONE, "D_honest_t1": DONE, "D_honest_t2": DONE, "n5_u1eqt_t1": DONE, "n5_u1eqt_t4": DONE,
    "adv_reorder": DONE, "share_reorder": DONE, "share_pt_ok": DONE,
    # B is not checkable by a soul, but H1 covers it: T3 differs -> bad_sig3
    "adv_B_resigned": "bad_sig3",
    "share_pt_ver": "bad_share", "share_pt_from": "bad_share", "share_pt_to": "bad_share",
    "share_pt_round": "bad_share", "share_pt_x": "bad_share", "share_pt_x0": "bad_share",
    "share_pt_sbyte": "bad_commit", "share_cm_s0": "bad_commit", "share_cm_s31": "bad_commit",
    "share_cm_b0": "bad_commit", "share_cm_b31": "bad_commit", "share_cm_path0_lo": "bad_commit",
    "share_cm_path0_hi": "bad_commit", "share_cm_path1_lo": "bad_commit", "share_cm_path1_hi": "bad_commit",
    "share_cm_otherx": "bad_commit", "share_cm_otherpath": "bad_commit", "share_cm_swap_sb": "bad_commit",
    "share_cm_last": "bad_commit", "share_cm_then_noopen": "bad_commit", "share_noopen_then_cm": "bad_share",
    "share_ct_len_dplus1": "bad_share", "share_ct_len_dminus1": "bad_share", "share_ct_k8": "bad_share",
    "share_ct_v1len": "bad_line", "share_pt_v1_v1len": "bad_line", "share_ct_k9": "bad_line",
    "share_ct_halfbyte": "bad_line",
    "adv_B0_altered": "bad_sig", "adv_B31_altered": "bad_sig", "adv_M0_altered": "bad_sig",
    "adv_M31_altered": "bad_sig", "adv_bad_sig": "bad_sig",
    "own_adv_B0_altered": "bad_adv", "own_adv_B31_altered": "bad_adv", "own_adv_M0_altered": "bad_adv",
    "own_adv_M31_altered": "bad_adv", "own_adv_altered": "bad_adv", "adv_M_resigned": "bad_commit",
    "adv_v1_6tok": "bad_line", "adv_7tok": "bad_line",
    "reveal_proof_k1": "bad_line", "reveal_proof_k2": "unexpected", "reveal_proof_k3": "unexpected",
    "reveal_proof_k9": "unexpected", "reveal_proof_k10": "bad_line", "reveal_v1_6tok": "bad_line",
    "reveal_proof_odd": "bad_line",
}


def check():
    """gen + run in process; assert the outcome of every EXPECT case."""
    import tempfile
    gen_scripted()
    gen_keys_inputs()
    gen_random()
    fd, path = tempfile.mkstemp()
    try:
        with os.fdopen(fd, "w") as fh:
            fh.write("\n".join(OUT))
        lines = []
        run(path, lines.append)
    finally:
        os.unlink(path)
    got, cur = {}, None
    for ln in lines:
        if ln.startswith("C "):
            cur = ln[2:]
            got[cur] = None
        elif ln.startswith("O SA4_ABORT ") and got[cur] is None:
            got[cur] = ln.split(" ")[-1]
        elif ln.startswith("S ") and " st=5 " in ln and got[cur] is None:
            got[cur] = DONE
    ncase = sum(1 for o in OUT if o.startswith("CASE "))
    bad = [(k, v, got.get(k, "missing")) for k, v in sorted(EXPECT.items()) if got.get(k, "missing") != v]
    for k, v, g in bad:
        print("sa4_cases check: %s expected %s, got %s" % (k, v, g))
    print("sa4_cases check: %d cases run, %d outcomes checked, %d refused, %d done" %
          (len(got), len(EXPECT), sum(1 for v in got.values() if v not in (None, DONE)),
           sum(1 for v in got.values() if v == DONE)))
    if bad or len(got) != ncase:
        print("sa4_cases check: MISMATCH")
        return 1
    print("sa4_cases check: OK")
    return 0


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "gen":
        gen_scripted()
        gen_keys_inputs()
        gen_random()
        print("\n".join(OUT))
        sys.exit(0)
    if len(sys.argv) == 3 and sys.argv[1] == "run":
        run(sys.argv[2])
        sys.exit(0)
    if len(sys.argv) == 2 and sys.argv[1] == "check":
        sys.exit(check())
    print(__doc__)
    sys.exit(2)
