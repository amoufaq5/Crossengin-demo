#!/usr/bin/env python3
"""Malicious SecAgg v4 coordinator for tests (A2.4a). Stdlib only.

It speaks the real v4 wire (src/learning/sa4_wire.nova) to real souls: NOVA
chat souls (/fed_join with CE_SECAGG_MODE=v4) and Python souls
(scripts/sa4_ref.py --connect). It accepts the v4 hello and FED_JOIN, then
drives one round in which it lies in a chosen way (--attack), and logs every
line both ways. A second mode (--check) judges, from that log alone, what
the honest souls revealed: it does not trust the attack code.

    secagg_evil_coord.py --listen HOST:PORT --round R --attack NAME --log FILE
        [--souls K] [--victim ID[,ID..]] [--hide ID] [--groups A1,A2/B1,B2]
        [--r0 ID=KIND,..] [--collude SEEDFILE,..] [--prev-log FILE]
        [--join-s S] [--phase-s S] [--hang-s S] [--trickle-s S]
    secagg_evil_coord.py --check LOG [--x ID=TAG=P:A,TAG=P:A]... [--x ID=W,W,..]...

Roster and tags come from CE_SECAGG_ROSTER and CE_SECAGG_V4_TAGS (or
--roster / --tags). Colluding souls (--collude, their identity seeds) are
simulated here with sa4_ref.Soul: they advertise, share and sign like real
souls, sign any T3 the attack needs, and their c-key is logged so --check
can open the shares honest souls sent them.

Attacks (stage names of tests/integration/scenario_u4_evil.sh):
  honest       an honest round with the true results.
  results      honest round, then forged FED_AGGREGATE_SUM lines: the true
               seed line, a second seed line, wrong round, unknown tag,
               n = 0, n > |U3|, negative, 2^32, 25 digits, the true
               user-teach line, second user-teach lines up to ntags + 1
               lines, then a line for another tag past the after-round cap.
  round0       SA4_ROUND per soul from --r0 ID=KIND (bad-fp, bad-len,
               bad-layout, burn = bad fingerprint with r = 2^62-1, rN =
               honest line for round N); stops after the ADVs.
  own-adv      each soul is sent its own ADV with c_pk altered.
  adv-sig      each soul is sent another soul's ADV with a forged signature.
  adv-old      each soul is sent another soul's ADV from --prev-log (an
               older round): as signed for the souls in --victim, with the
               round field rewritten to this round for the others.
  u1-small     U1 of t-1 souls.        not-in-u1   U1 without the receiver.
  equiv-u1     --victim is shown U1 without --hide, the others the full U1;
               every U2 leaves --hide out, so only U1 / H1 differ.
  tamper-ct    one share ciphertext to every soul has a flipped byte.
  u2-small     U2 of t-1 souls.        not-in-u2   U2 without the receiver.
  u2-notsub    U1 without --hide for everyone, then U2 with it.
  false-dropout  --victim is shown U3 with itself, everyone else U3 without
               it: they reveal its s-share; it must refuse (bad_sig3).
  split-u3     --groups A/B: A is shown U3 without B's last soul, B without
               A's last soul; every soul gets every U3 member's SIG3.
  collude      --groups A/B with --victim in A, colluders from --collude:
               U3_A = everyone, U3_B = everyone but the victim; U4 of each
               group = the group plus the colluders, who sign both T3s.
  sig3-bad     the first other SIG3 each soul checks has a flipped byte.
  own-sig3     each soul is sent its own SIG3 altered.
  u4-notsub    U3 without --hide for everyone, then U4 with it.
  u4-small     U4 of t-1 souls.
  out-of-phase SA4_SET 3 while ADVs are expected.
  early-result FED_AGGREGATE_SUM while ADVs are expected.
  long-line    a line of over 1000 bytes.     nul   a line with a NUL byte.
  hang         silent after the shares (until --hang-s).
  trickle      after the shares, one byte every --trickle-s seconds of a
               line that never ends (until --hang-s).

Log: one line per message, written before it is processed: "S>ID LINE"
(coordinator to soul ID), "ID>S LINE" (soul ID to coordinator); comments
start with "#": "#JOIN ID MS", "#EOF ID MS" (ms since start), "#COLLUDER ID
csk=HEX", "#C ID>S LINE" (a simulated colluder's line, not on the wire).
Bytes outside 0x20..0x7e are written as \\xNN.

--check prints one JSON object: per honest soul its abort code, lines
after the abort, whether it revealed and whether it had been sent t valid
SIG3s over its own T3 (recomputed from what it was sent), whether its
reveals follow the U3 it signed, B / S (holders of its b- / s-shares: honest
reveals plus colluder-held shares, opened here), leak = B >= t and S >= t,
its input rebuilt on a leak, its y with pairwise masks stripped when s is
rebuilt (words equal to the input), and the control aggregate over the
souls whose b was revealed.
"""
import json
import os
import select
import socket
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sa4_ref as R  # noqa: E402

MAXL = 1000
M32 = 0xFFFFFFFF


class _Mark:
    def __init__(self, name):
        self.name = name


EOF = _Mark("eof")
TIMEOUT = _Mark("timeout")
LONG = _Mark("long")


def esc(s):
    return "".join(c if 32 <= ord(c) <= 126 else "\\x%02x" % ord(c) for c in s)


def flip_hex(line, idx, pos):
    """Flip one hex digit of token idx at position pos (stays valid hex)."""
    t = line.split(" ")
    h = list(t[idx])
    h[pos] = "1" if h[pos] != "1" else "2"
    t[idx] = "".join(h)
    return " ".join(t)


# ============================================================ transport
class Conn:
    def __init__(self, sock):
        self.sock = sock
        self.buf = b""
        self.eof = False
        self.dead = False          # a send failed
        self.id = -1
        self.join_ms = 0

    def line(self, timeout):
        end = time.monotonic() + timeout
        while True:
            k = self.buf.find(b"\n")
            if k > MAXL or (k < 0 and len(self.buf) > MAXL):
                self.buf = b""
                return LONG
            if k >= 0:
                b, self.buf = self.buf[:k], self.buf[k + 1:]
                return b.decode("latin-1")
            if self.eof:
                return EOF
            left = end - time.monotonic()
            if left <= 0:
                return TIMEOUT
            try:
                r, _, _ = select.select([self.sock], [], [], left)
            except (OSError, ValueError):
                self.eof = True
                continue
            if not r:
                continue
            try:
                d = self.sock.recv(65536)
            except OSError:
                d = b""
            if not d:
                self.eof = True
            else:
                self.buf += d

    def pump(self):
        """One non-blocking read into the buffer (after select said so)."""
        if self.eof:
            return
        try:
            self.sock.setblocking(False)
            d = self.sock.recv(65536)
        except BlockingIOError:
            return
        except OSError:
            d = b""
        finally:
            try:
                self.sock.settimeout(10)
            except OSError:
                pass
        if not d:
            self.eof = True
        else:
            self.buf += d

    def send(self, data):
        if self.dead:
            return False
        try:
            self.sock.sendall(data)
            return True
        except OSError:            # BrokenPipeError, ConnectionResetError, timeout
            self.dead = True
            return False


class Log:
    def __init__(self, path):
        self.f = open(path, "w", encoding="latin-1")
        self.t0 = time.monotonic()

    def ms(self):
        return int((time.monotonic() - self.t0) * 1000)

    def w(self, s):
        self.f.write(esc(s) + "\n")
        self.f.flush()


# ============================================================ shared math
def y_words(lines, lw):
    recs = sorted((p for p in (R.parse(l) for l in lines) if p and p[0] == R.EV_Y), key=lambda p: p[3])
    w = [x for p in recs for x in p[5]]
    return w if len(w) == lw else None


def strip_pairwise(z, s_sk, spk_of, r, u, others):
    """Remove from y_u the pairwise masks with every id in others (y_u
    carries +PRG(s_uw) for w > u and -PRG(s_uw) for w < u)."""
    for w in others:
        if w == u:
            continue
        ms = R.mask_seed(s_sk, spk_of[w], r, u, w)
        if ms is None:
            return None
        z = R.saprg_mask(z, ms, 1 if w < u else -1)
    return z


def unmask(t, r, lw, K, D, ys, bsh, ssh, spk):
    """Sum over K of the inputs: y minus PRG(b) for K, then the masks of
    every dropped d in D with every u in K undone (s_d rebuilt and checked
    against its s_pk). bsh/ssh: id -> {x: share}. -> (words, why)."""
    agg = [0] * lw
    for u in K:
        if ys.get(u) is None:
            return None, "no y from %d" % u
        if len(bsh.get(u, {})) < t:
            return None, "fewer than t b-shares of %d" % u
        agg = [(a + b) & M32 for a, b in zip(agg, ys[u])]
        b = R.shamir_combine(sorted(bsh[u].items())[:t], 32)
        agg = R.saprg_mask(agg, b, -1)
    for d in D:
        if len(ssh.get(d, {})) < t:
            return None, "fewer than t s-shares of %d" % d
        s = R.shamir_combine(sorted(ssh[d].items())[:t], 32)
        if R.x25519_base(s) != spk.get(d):
            return None, "rebuilt s key of %d does not match its s_pk" % d
        for u in K:
            ms = R.mask_seed(s, spk[u], r, d, u)
            agg = R.saprg_mask(agg, ms, 1 if d < u else -1)
    return agg, ""


# ============================================================ the coordinator
class Evil:
    def __init__(self, o, ro, tags, log):
        self.o, self.ro, self.tags, self.log = o, ro, tags, log
        self.n, self.t = ro.n, ro.t
        self.lw, self.lay, self.fp = 3 * len(tags), R.fed_layout(tags), ro.fp
        self.r = o["round"]
        self.a = o["attack"]
        self.conns = {}
        self.cols = {}
        self.col_seed = {}
        self.adv, self.shares, self.ys, self.sig3, self.rev = {}, {}, {}, {}, {}
        self.end = {1: set(), 2: set(), 3: set()}
        self.abort = {}
        self.quiet = set()         # timed out in a phase
        self.view = {}
        self.sent_adv = {}
        self.victims = [int(v) for v in o["victim"].split(",") if v] if o["victim"] else []
        self.victim = self.victims[0] if self.victims else -1
        self.hide = int(o["hide"]) if o["hide"] else -1
        self.groups = None
        if o["groups"]:
            ga, _, gb = o["groups"].partition("/")
            self.groups = ([int(v) for v in ga.split(",")], [int(v) for v in gb.split(",")])
        self.r0 = {}
        for item in (o["r0"] or "").split(","):
            if item:
                k, _, v = item.partition("=")
                self.r0[int(k)] = v

    X = property(lambda self: self.ro.x)

    def I(self, x):
        return self.ro.entries[x - 1][0]

    # ---- io
    def send(self, i, line, raw=None):
        self.log.w("S>%d %s" % (i, line))
        c = self.conns.get(i)
        if c is None or c.eof:
            return
        c.send(raw if raw is not None else (line + "\n").encode("latin-1"))

    def recv(self, i, terms, cap):
        out = []
        c = self.conns[i]
        while len(out) < cap:
            ln = c.line(self.o["phase_s"])
            if ln is EOF:
                self.log.w("#EOF %d %d" % (i, self.log.ms()))
                break
            if ln is TIMEOUT:
                self.log.w("#TIMEOUT %d %d" % (i, self.log.ms()))
                self.quiet.add(i)
                break
            if ln is LONG:
                self.log.w("#LONG %d" % i)
                self.quiet.add(i)
                break
            self.log.w("%d>S %s" % (i, ln))
            out.append(ln)
            p = R.parse(ln)
            if p and p[0] == R.EV_ABORT:
                self.abort[i] = p[3]
                break
            if ln.split(" ")[0] in terms:
                break
        return out

    def alive(self):
        return [i for i in sorted(self.conns)
                if i not in self.abort and i not in self.quiet and not self.conns[i].eof and not self.conns[i].dead]

    def feed(self, c, lines):
        s = self.cols[c]
        outs = []
        for ln in lines:
            ok, err, o = s.handle(ln)
            for x in o:
                self.log.w("#C %d>S %s" % (c, x))
            outs += o
            if not ok:
                raise RuntimeError("simulated colluder %d refused: %s" % (c, err))
        return outs

    def xs(self, ids):
        return sorted(self.X(i) for i in ids)

    # ---- join
    def join(self, srv):
        want = self.o["souls"]
        end = time.monotonic() + self.o["join_s"]
        pend = []
        while len(self.conns) < want and time.monotonic() < end:
            ready = [p.sock for p in pend if b"\n" in p.buf]
            if ready:
                r = ready
            else:
                r, _, _ = select.select([srv] + [p.sock for p in pend], [], [], min(1.0, max(0.0, end - time.monotonic())))
            for s in r:
                if s is srv:
                    cs, _ = srv.accept()
                    cs.settimeout(10)
                    pend.append(Conn(cs))
                    continue
                c = next(p for p in pend if p.sock is s)
                ln = c.line(5)
                if not isinstance(ln, str):
                    pend.remove(c)
                    c.sock.close()
                    continue
                if c.id == -1 and ln == R.FED_HELLO:
                    c.id = -2
                    c.send((R.FED_OK + "\n").encode("latin-1"))
                    continue
                f = ln.split(" ")
                ok = c.id == -2 and len(f) == 3 and f[0] == "FED_JOIN" and R._u32(f[1]) >= 0
                i = int(f[1]) if ok else -1
                if not ok or self.X(i) == 0 or i in self.conns or i in self.cols:
                    self.log.w("#REJECT %s" % ln[:80])
                    pend.remove(c)
                    c.sock.close()
                    continue
                pend.remove(c)
                c.id = i
                c.join_ms = self.log.ms()
                self.conns[i] = c
                self.log.w("#JOIN %d %d" % (i, c.join_ms))
                print("evil: JOIN id=%d" % i, flush=True)
        for p in pend:
            p.sock.close()
        self.real = sorted(self.conns)
        return len(self.conns) == want

    # ---- per-receiver views (x lists)
    def round_line(self, i):
        k = self.r0.get(i, "") if self.a == "round0" else ""
        fp, r, lw, lay = self.fp, self.r, self.lw, self.lay
        if k == "bad-fp":
            fp = bytes([fp[0] ^ 1]) + fp[1:]
        elif k == "bad-len":
            lw += 3
        elif k == "bad-layout":
            lay = bytes([lay[0] ^ 1]) + lay[1:]
        elif k == "burn":
            fp, r = bytes([fp[0] ^ 1]) + fp[1:], 2 ** 62 - 1
        elif k.startswith("r"):
            r = int(k[1:])
        return R.fmt_round(r, fp, lw, lay)

    def others(self, i, xs, k):
        """xs restricted to the receiver plus the first k others."""
        mx = self.X(i)
        return sorted([mx] + [x for x in xs if x != mx][:k])

    def u1_for(self, i, base):
        a = self.a
        if a == "u1-small":
            return self.others(i, base, self.t - 2)
        if a == "not-in-u1":
            return [x for x in base if x != self.X(i)]
        if a == "equiv-u1" and i == self.victim:
            return [x for x in base if x != self.X(self.hide)]
        if a == "u2-notsub":
            return [x for x in base if x != self.X(self.hide)]
        return list(base)

    def advs_for(self, i, u1):
        lines = [self.adv[self.I(x)] for x in u1]
        a, mx = self.a, self.X(i)
        nxt = [x for x in u1 if x > mx] + [x for x in u1 if x < mx]
        if a == "own-adv" and mx in u1:
            k = u1.index(mx)
            lines[k] = flip_hex(lines[k], 3, 0)
        if a == "adv-sig" and nxt:
            k = u1.index(nxt[0])
            lines[k] = flip_hex(lines[k], 5, 10)
        if a == "adv-old" and nxt:
            k = u1.index(nxt[0])
            old = self.old_adv.get(self.I(nxt[0]))
            if old is not None:
                if i not in self.victims:
                    f = old.split(" ")
                    f[1] = str(self.r)
                    old = " ".join(f)
                lines[k] = old
        return lines

    def u2_for(self, i, base):
        a, mx = self.a, self.X(i)
        d = [x for x in base if x in self.view[i][1]]
        if a == "u2-small":
            return self.others(i, d, self.t - 2)
        if a == "not-in-u2":
            return [x for x in d if x != mx]
        if a == "u2-notsub":
            return sorted(set(d) | {self.X(self.hide)})
        if a == "equiv-u1":
            # Every soul (the hidden one too) gets the same U2 without
            # --hide, so the transcripts differ only in U1 / H1.
            return [x for x in d if x != self.X(self.hide)]
        return d

    def shares_for(self, i, u2):
        got = self.shares.get(i, {})
        lines = [got[self.I(x)] for x in u2 if x != self.X(i) and self.I(x) in got]
        if self.a == "tamper-ct" and lines and i not in self.cols:
            lines[0] = flip_hex(lines[0], 4, 20)
        return lines

    def u3_for(self, i, base):
        a = self.a
        d = [x for x in base if x in self.view[i][2]]
        if a == "false-dropout" and i != self.victim:
            return [x for x in d if x != self.X(self.victim)]
        if a == "split-u3":
            ga, gb = self.groups
            drop = gb[-1] if i in ga else ga[-1]
            return [x for x in d if x != self.X(drop)]
        if a == "collude" and self.groups and i in self.groups[1]:
            return [x for x in d if x != self.X(self.victim)]
        if a == "u4-notsub":
            return [x for x in d if x != self.X(self.hide)]
        return d

    def u4_for(self, i, base):
        a = self.a
        d = [x for x in base if x in self.view[i][3]]
        if a == "u4-small":
            return self.others(i, d, self.t - 2)
        if a == "u4-notsub":
            return sorted(set(d) | {self.X(self.hide)})
        if a == "collude":
            g = self.groups[0] if i in self.groups[0] else self.groups[1]
            return self.xs([j for j in g if j in self.sig3] + list(self.cols))
        return d

    def t3_of(self, i):
        v = self.view[i]
        keys = {}
        for ln in self.sent_adv[i]:
            p = R.parse(ln)
            if p and p[0] == R.EV_ADV:
                keys[self.X(p[2])] = (p[3], p[4])
        h1 = R.advset_hash(R.bitmap(v[1]), [keys.get(x, (b"", b"")) for x in v[1]])
        return R.t3_transcript(self.fp, self.r, h1, R.bitmap(v[2]), R.bitmap(v[3]))

    def sig3_for(self, i, u4):
        lines = []
        t3 = None
        for x in u4:
            j = self.I(x)
            if j in self.cols:          # colluders sign whatever T3 this soul signed
                if t3 is None:
                    t3 = self.t3_of(i)
                seed = self.col_seed[j]
                lines.append(R.fmt_sig3(self.r, j, R.ed25519_sign(t3, seed, R.ed25519_pk_from_seed(seed))))
            elif j in self.sig3:
                lines.append(self.sig3[j])
        mx = self.X(i)
        if self.a == "sig3-bad":
            k = next((k for k, x in enumerate(u4) if x != mx), -1)
            if 0 <= k < len(lines):
                lines[k] = flip_hex(lines[k], 3, 10)
        if self.a == "own-sig3" and mx in u4:
            k = u4.index(mx)
            lines[k] = flip_hex(lines[k], 3, 10)
        return lines

    # ---- the round
    def run(self):
        a = self.a
        honest_rl = R.fmt_round(self.r, self.fp, self.lw, self.lay)
        for i in self.real:
            self.send(i, self.round_line(i))
        for c in self.cols:
            self.adv[c] = self.feed(c, [honest_rl])[0]
            self.log.w("#COLLUDER %d csk=%s" % (c, self.cols[c].csk.hex()))
        for i in self.real:
            for ln in self.recv(i, ("SA4_ADV",), 1):
                p = R.parse(ln)
                if p and p[0] == R.EV_ADV and p[2] == i:
                    self.adv[i] = ln
        if a == "round0":
            return
        if a in ("out-of-phase", "early-result", "long-line", "nul"):
            bad = {"out-of-phase": R.fmt_set(self.r, 3, R.bitmap(self.xs(self.adv))),
                   "early-result": "FED_AGGREGATE_SUM %d seed 1 1 1" % self.r,
                   "long-line": "SA4_SET %d 1 %s" % (self.r, "a" * 1000),
                   "nul": "SA4_SET %d 1 \0" % self.r}[a]
            for i in self.alive():
                self.send(i, bad)
            for i in self.alive():
                self.recv(i, (), 2)
            return
        # phase 1
        base = self.xs(self.adv)
        for i in self.alive():
            self.view[i] = {1: self.u1_for(i, base)}
            self.sent_adv[i] = self.advs_for(i, self.view[i][1])
            for ln in self.sent_adv[i]:
                self.send(i, ln)
            self.send(i, R.fmt_set(self.r, 1, R.bitmap(self.view[i][1])))
        for c in self.cols:
            self.view[c] = {1: list(base)}
            self.sent_adv[c] = [self.adv[self.I(x)] for x in base]
            for ln in self.feed(c, self.sent_adv[c] + [R.fmt_set(self.r, 1, R.bitmap(base))]):
                p = R.parse(ln)
                if p and p[0] == R.EV_SHARE:
                    self.shares.setdefault(p[3], {})[c] = ln
        for i in [j for j in self.real if j in self.view and j in self.alive()]:
            for ln in self.recv(i, ("SA4_END",), self.n + 2):
                p = R.parse(ln)
                if p and p[0] == R.EV_SHARE and p[2] == i:
                    self.shares.setdefault(p[3], {})[i] = ln
                if p and p[0] == R.EV_END and p[2] == 1:
                    self.end[1].add(i)
        if a in ("hang", "trickle"):
            return
        # phase 2
        base = self.xs([i for i in self.end[1] if i in self.alive()] + list(self.cols))
        for i in [j for j in self.alive() if j in self.view]:
            self.view[i][2] = self.u2_for(i, base)
            for ln in self.shares_for(i, self.view[i][2]):
                self.send(i, ln)
            self.send(i, R.fmt_set(self.r, 2, R.bitmap(self.view[i][2])))
        for c in self.cols:
            self.view[c][2] = [x for x in base if x in self.view[c][1]]
            outs = self.feed(c, self.shares_for(c, self.view[c][2]) + [R.fmt_set(self.r, 2, R.bitmap(self.view[c][2]))])
            self.ys[c] = [ln for ln in outs if ln.startswith("SA4_Y ")]
        for i in [j for j in self.alive() if 2 in self.view.get(j, {})]:
            got = self.recv(i, ("SA4_END",), self.lw // 100 + 3)
            self.ys[i] = [ln for ln in got if ln.startswith("SA4_Y ")]
            if any(ln.startswith("SA4_END %d 2 " % self.r) for ln in got):
                self.end[2].add(i)
        # phase 3
        base = self.xs([i for i in self.end[2] if i in self.alive()] + list(self.cols))
        for i in [j for j in self.alive() if j in self.end[2]]:
            self.view[i][3] = self.u3_for(i, base)
            self.send(i, R.fmt_set(self.r, 3, R.bitmap(self.view[i][3])))
        for c in self.cols:
            self.view[c][3] = [x for x in base if x in self.view[c][2]]
            self.sig3[c] = self.feed(c, [R.fmt_set(self.r, 3, R.bitmap(self.view[c][3]))])[0]
        for i in [j for j in self.alive() if 3 in self.view.get(j, {})]:
            for ln in self.recv(i, ("SA4_SIG3",), 1):
                p = R.parse(ln)
                if p and p[0] == R.EV_SIG3 and p[2] == i:
                    self.sig3[i] = ln
        # phase 4
        base = self.xs([i for i in self.sig3 if i in self.alive()] + list(self.cols))
        for i in [j for j in self.alive() if j in self.sig3]:
            self.view[i][4] = self.u4_for(i, base)
            for ln in self.sig3_for(i, self.view[i][4]):
                self.send(i, ln)
            self.send(i, R.fmt_set(self.r, 4, R.bitmap(self.view[i][4])))
        for i in [j for j in self.alive() if 4 in self.view.get(j, {})]:
            got = self.recv(i, ("SA4_END",), self.n + 2)
            self.rev[i] = [p for p in (R.parse(ln) for ln in got) if p and p[0] == R.EV_REVEAL]
            if any(ln.startswith("SA4_END %d 3 " % self.r) for ln in got):
                self.end[3].add(i)
        self.results()

    # ---- results
    def aggregate(self, i):
        """The sum over the U3 that soul i signed, from the reveals."""
        v = self.view[i]
        K = [self.I(x) for x in v[3]]
        D = [self.I(x) for x in v[2] if x not in v[3]]
        bsh, ssh = {}, {}
        for w, recs in self.rev.items():
            for p in recs:
                (bsh if p[4] == 0 else ssh).setdefault(p[3], {})[self.X(w)] = p[5]
        for c, s in self.cols.items():
            for x, hv in enumerate(s.held or []):
                if hv is not None:
                    ssh.setdefault(self.I(x + 1), {})[self.X(c)] = hv[0]
                    bsh.setdefault(self.I(x + 1), {})[self.X(c)] = hv[1]
        ys = {u: y_words(self.ys.get(u, []), self.lw) for u in K}
        spk = {j: R.parse(self.adv[j])[4] for j in self.adv}
        agg, why = unmask(self.t, self.r, self.lw, K, D, ys, bsh, ssh, spk)
        return agg, len(K), why

    def results(self):
        done = [i for i in sorted(self.end[3]) if not self.conns[i].eof]
        cache = {}
        for i in done:
            key = tuple(self.view[i][3])
            if key not in cache:
                cache[key] = self.aggregate(i)
            agg, u3n, why = cache[key]
            lines = []
            sums = {}
            if agg is None:
                self.log.w("#NOSUM %s" % why)
            else:
                for k, tag in enumerate(self.tags):
                    sums[tag] = (agg[3 * k], agg[3 * k + 1], agg[3 * k + 2])
                    if agg[3 * k + 2] >= 1:
                        lines.append("FED_AGGREGATE_SUM %d %s %d %d %d" % ((self.r, tag) + sums[tag]))
            if self.a == "results" and agg is not None:
                r = self.r
                sp, sa, n = sums["seed"]
                up, ua, un = sums["user-teach"]
                lines = ["FED_AGGREGATE_SUM %d seed %d %d %d" % (r, sp, sa, n),
                         "FED_AGGREGATE_SUM %d seed %d %d %d" % (r, sp + 1, sa + 1, n),
                         "FED_AGGREGATE_SUM %d user-teach %d %d %d" % (r + 1, up, ua, un),
                         "FED_AGGREGATE_SUM %d nosuchtag 1 1 1" % r,
                         "FED_AGGREGATE_SUM %d user-teach 1 1 0" % r,
                         "FED_AGGREGATE_SUM %d user-teach 1 1 %d" % (r, u3n + 1),
                         "FED_AGGREGATE_SUM %d user-teach -5000 -7 2" % r,
                         "FED_AGGREGATE_SUM %d user-teach 4294967296 1 2" % r,
                         "FED_AGGREGATE_SUM %d user-teach 1234567890123456789012345 1 2" % r,
                         "FED_AGGREGATE_SUM %d user-teach %d %d %d" % (r, up, ua, un)]
                extra = [tg for tg in self.tags if tg not in ("seed", "user-teach")]
                lines += ["FED_AGGREGATE_SUM %d user-teach %d %d %d" % (r, up + 7, ua, un)] * max(0, len(self.tags) + 1 - len(lines))
                lines += ["FED_AGGREGATE_SUM %d %s 1 1 1" % (r, extra[0] if extra else "seed")]
            for ln in lines:
                self.send(i, ln)
            self.send(i, "BYE")
            print("evil: results to %d: %s" % (i, "; ".join(lines)[:300]), flush=True)

    # ---- the end
    def watch(self, max_s, trickle=None):
        """Read every connection until EOF or max_s; with trickle, send one
        byte of a line that never ends to every soul every trickle s."""
        end = time.monotonic() + max_s
        nxt = time.monotonic()
        sent = {}
        while time.monotonic() < end:
            live = [c for c in self.conns.values() if not c.eof]
            if not live:
                break
            if trickle and time.monotonic() >= nxt:
                for c in live:
                    k = sent.get(c.id, 0)
                    data = ("SA4_SET %d 2 " % self.r).encode() + b"0" * 4096
                    c.send(data[k % len(data):k % len(data) + 1])
                    sent[c.id] = k + 1
                nxt = time.monotonic() + trickle
            wait = max(0.0, min(end, nxt if trickle else end) - time.monotonic())
            try:
                r, _, _ = select.select([c.sock for c in live], [], [], min(wait, 0.25))
            except (OSError, ValueError):
                break
            for c in live:
                if c.sock in r:
                    c.pump()
                if c.sock in r or c.buf:
                    while True:
                        ln = c.line(0)
                        if ln is TIMEOUT:
                            break
                        if ln is EOF:
                            self.log.w("#EOF %d %d" % (c.id, self.log.ms()))
                            break
                        if ln is LONG:
                            self.log.w("#LONG %d" % c.id)
                            continue
                        self.log.w("%d>S %s" % (c.id, ln))
                        p = R.parse(ln)
                        if p and p[0] == R.EV_ABORT:
                            self.abort.setdefault(c.id, p[3])
        for i, k in sorted(sent.items()):
            self.log.w("#TRICKLE %d %d" % (i, k))

    def finish(self):
        if self.a == "hang":
            self.watch(self.o["hang_s"])
        elif self.a == "trickle":
            self.watch(self.o["hang_s"], trickle=self.o["trickle_s"])
        self.watch(3.0)            # aborted and finished souls close by themselves
        for c in self.conns.values():
            if not c.eof:          # mid-round: half-close, keep reading what it says
                self.log.w("#SHUTDOWN %d %d" % (c.id, self.log.ms()))
                try:
                    c.sock.shutdown(socket.SHUT_WR)
                except OSError:
                    pass
        self.watch(5.0)
        for c in self.conns.values():
            if not c.eof:
                self.log.w("#OPEN %d" % c.id)
            c.sock.close()


def coord_main(o):
    ro = R.roster_load(o["roster"])
    tags = R.fed_tags(o["tags"])
    log = Log(o["log"])
    ev = Evil(o, ro, tags, log)
    for path in [p for p in (o["collude"] or "").split(",") if p]:
        seed = R.seed_load(path)
        s = R.Soul(ro, seed, R.OsRng(), 0)
        if not s.set_input([0] * ev.lw, ev.lay):
            raise ValueError("colluder input refused")
        ev.cols[s.me] = s
        ev.col_seed[s.me] = seed
    if o["souls"] is None:
        o["souls"] = ro.n - len(ev.cols)
    ev.old_adv = {}
    if o["prev_log"]:
        for raw in open(o["prev_log"], encoding="latin-1"):
            i, _, rest = raw.rstrip("\n").partition(">S ")
            if rest.startswith("SA4_ADV ") and i.isdigit():
                ev.old_adv.setdefault(int(i), rest)
    log.w("#EVIL attack=%s round=%d n=%d t=%d colluders=%s" % (ev.a, ev.r, ro.n, ro.t, sorted(ev.cols)))
    host, _, port = o["listen"].rpartition(":")
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        srv.bind((host, int(port)))
        srv.listen(64)
    except OSError as e:
        print("evil: ERROR cannot bind / listen: %s" % e, flush=True)
        return 3
    print("evil: listening on %s n=%d t=%d attack=%s round=%d" % (o["listen"], ro.n, ro.t, ev.a, ev.r), flush=True)
    if not ev.join(srv):
        print("evil: only %d of %d soul(s) joined" % (len(ev.conns), o["souls"]), flush=True)
    srv.close()
    try:
        if ev.conns:
            ev.run()
    finally:
        ev.finish()
        log.f.close()
    print("evil: done aborts=%s revealers=%s" % (json.dumps(ev.abort, sort_keys=True), sorted(i for i in ev.rev if ev.rev[i])),
          flush=True)
    return 0


# ============================================================ analysis
def parse_x(spec, tags):
    i, _, v = spec.partition("=")
    if "=" in v:
        x = {}
        for item in v.split(","):
            tag, _, pa = item.partition("=")
            p, _, a = pa.partition(":")
            x[tag] = (int(p), int(a))
        return int(i), R.fed_words(tags, x)
    return int(i), [int(w) for w in v.split(",") if w != ""]


def check_main(o):
    ro = R.roster_load(o["roster"])
    tags = R.fed_tags(o["tags"]) if o["tags"] else []
    n, t = ro.n, ro.t
    xin = dict(parse_x(s, tags) for s in o["x"])
    to, frm = {}, {}                      # id -> [(seq, line)]
    cols_csk, joins, eofs = {}, {}, {}
    seq = 0
    for raw in open(o["check"], encoding="latin-1"):
        raw = raw.rstrip("\n")
        seq += 1
        if raw.startswith("#"):
            f = raw[1:].split(" ")
            if f[0] == "COLLUDER" and len(f) == 3 and f[2].startswith("csk="):
                cols_csk[int(f[1])] = bytes.fromhex(f[2][4:])
            elif f[0] == "JOIN" and len(f) == 3:
                joins[int(f[1])] = int(f[2])
            elif f[0] == "EOF" and len(f) == 3:
                eofs.setdefault(int(f[1]), int(f[2]))
            continue
        if raw.startswith("S>"):
            i, _, ln = raw[2:].partition(" ")
            to.setdefault(int(i), []).append((seq, ln))
        else:
            i, _, ln = raw.partition(">S ")
            if i.isdigit():
                frm.setdefault(int(i), []).append((seq, ln))
    souls = sorted(set(joins) | set(frm))
    X = ro.x

    def P(ln):
        return R.parse(ln)

    def first(lst, pred):
        return next(((s, ln, p) for s, ln in lst for p in [P(ln)] if p and pred(p)), (None, None, None))

    own_adv, spk, cpk = {}, {}, {}
    for v in souls:
        _, ln, p = first(frm.get(v, []), lambda p: p[0] == R.EV_ADV and p[2] == v)
        if p:
            own_adv[v] = p
            cpk[v], spk[v] = p[3], p[4]
    rounds = {}
    for v in souls:
        _, _, p = first(to.get(v, []), lambda p: p[0] == R.EV_ROUND)
        if p:
            rounds[v] = p
    # Colluder c-keys: must match the c_pk of the colluder's ADV that the
    # honest souls were sent.
    col_ok = {}
    for c, csk in cols_csk.items():
        seen = set()
        for v in souls:
            for _, ln in to.get(v, []):
                p = P(ln)
                if p and p[0] == R.EV_ADV and p[2] == c:
                    seen.add(p[3])
        col_ok[c] = seen == {R.x25519_base(csk)}
    # Holders of each soul's shares: honest reveals + shares sent to colluders.
    bsh, ssh = {}, {}
    for w in souls:
        for _, ln in frm.get(w, []):
            p = P(ln)
            if p and p[0] == R.EV_REVEAL and p[2] == w:
                (bsh if p[4] == 0 else ssh).setdefault(p[3], {})[X(w)] = p[5]
    col_held = {}
    for u in souls:
        r = rounds[u][1] if u in rounds else -1
        for _, ln in frm.get(u, []):
            p = P(ln)
            if not (p and p[0] == R.EV_SHARE and p[2] == u and p[3] in cols_csk and col_ok.get(p[3]) and u in cpk):
                continue
            c = p[3]
            ek = R.enc_key(cols_csk[c], cpk[u], p[1], u, c)
            pt = R.share_open(ek, p[1], u, c, p[4]) if ek else None
            q = R.share_pt_parse(pt) if pt else None
            if q and q[:4] == (u, c, r, X(c)):
                ssh.setdefault(u, {})[X(c)] = q[4]
                bsh.setdefault(u, {})[X(c)] = q[5]
                col_held[u] = col_held.get(u, 0) + 1
    res = {"n": n, "t": t, "colluders": sorted(cols_csk), "colluder_keys_ok": all(col_ok.values()),
           "souls": {}, "reveal_lines": 0}
    ysv = {}
    for v in souls:
        fl, tl = frm.get(v, []), to.get(v, [])
        d = {}
        sa, _, pa = first(fl, lambda p: p[0] == R.EV_ABORT)
        d["abort"] = pa[3] if pa else None
        d["lines_after_abort"] = sum(1 for s, _ in fl if sa is not None and s > sa)
        d["lines_from"] = len(fl)
        revs = [(s, p) for s, ln in fl for p in [P(ln)] if p and p[0] == R.EV_REVEAL]
        res["reveal_lines"] += len(revs)
        d["revealed"] = bool(revs)
        d["reveals"] = len(revs)
        if v in joins and v in eofs:
            d["close_ms"] = eofs[v] - joins[v]
        rnd = rounds.get(v)
        r = rnd[1] if rnd else -1
        lw = rnd[3] if rnd else 0
        # What v was sent, phase by phase.
        sets = {}
        for s, ln in tl:
            p = P(ln)
            if p and p[0] == R.EV_SET and p[1] == r and p[2] not in sets:
                sets[p[2]] = (s, p[3])
        u = {k: R.bitmap_xs(b, n) for k, (_, b) in sets.items()}
        d["sig3_valid"] = None
        d["sig3_ok"] = None
        d["reveal_rule_ok"] = None
        if all(k in sets for k in (1, 2, 3)) and rnd and all(u[k] is not None for k in (1, 2, 3)):
            keys = {}
            for s, ln in tl:
                p = P(ln)
                if s < sets[1][0] and p and p[0] == R.EV_ADV and p[1] == r:
                    keys.setdefault(X(p[2]), (p[3], p[4]))
            h1 = R.advset_hash(sets[1][1], [keys.get(x, (b"", b"")) for x in u[1]])
            t3 = R.t3_transcript(rnd[2], r, h1, R.bitmap(u[2]), sets[3][1])
            _, _, ps = first(fl, lambda p: p[0] == R.EV_SIG3 and p[2] == v)
            d["own_sig3_over_t3"] = bool(ps) and R.ed25519_verify(t3, ps[3], ro.by_id[v][2])
            if 4 in sets and u.get(4) is not None:
                valid = set()
                for s, ln in tl:
                    p = P(ln)
                    if sets[3][0] < s < sets[4][0] and p and p[0] == R.EV_SIG3 and X(p[2]) in u[4] and X(p[2]) in u[3]:
                        if R.ed25519_verify(t3, p[3], ro.by_id[p[2]][2]):
                            valid.add(X(p[2]))
                d["sig3_valid"] = len(valid)
                d["sig3_ok"] = len(valid) >= t and set(u[4]) <= set(u[3]) and X(v) in u[4] and X(v) in valid
            if revs:
                about = [p[3] for _, p in revs]
                rule = len(set(about)) == len(about) and sorted(X(a) for a in about) == sorted(u[2])
                for s, p in revs:
                    want = 0 if X(p[3]) in u[3] else 1
                    rule = rule and p[4] == want and p[2] == v and 4 in sets and s > sets[4][0]
                d["reveal_rule_ok"] = rule
        elif revs:
            d["reveal_rule_ok"] = False
        # Leak judgement about v.
        B, S = bsh.get(v, {}), ssh.get(v, {})
        d["B"], d["S"] = len(B), len(S)
        d["colluder_held"] = col_held.get(v, 0)
        d["leak"] = len(B) >= t and len(S) >= t
        y = y_words([ln for _, ln in fl], lw) if lw else None
        ysv[v] = y
        d["s_rebuilt"] = None
        d["y_minus_pairwise_matches"] = None
        d["x_rebuilt"] = None
        d["x_match"] = None
        xv = xin.get(v)
        if len(S) >= t and v in spk:
            s_sk = R.shamir_combine(sorted(S.items())[:t], 32)
            d["s_rebuilt"] = R.x25519_base(s_sk) == spk[v]
            if d["s_rebuilt"] and y is not None and 2 in sets and u.get(2):
                spk_seen = {}
                for s, ln in tl:
                    p = P(ln)
                    if s < sets.get(1, (0,))[0] and p and p[0] == R.EV_ADV and p[1] == r:
                        spk_seen.setdefault(p[2], p[4])
                z = strip_pairwise(y, s_sk, spk_seen, r, v, [ro.entries[x - 1][0] for x in u[2]])
                if z is not None and xv is not None:
                    d["y_minus_pairwise_matches"] = sum(1 for a, b in zip(z, xv) if a == b)
                if z is not None and len(B) >= t:
                    b = R.shamir_combine(sorted(B.items())[:t], 32)
                    d["x_rebuilt"] = R.saprg_mask(z, b, -1)
                    d["x_match"] = (d["x_rebuilt"] == xv) if xv is not None else None
        res["souls"][str(v)] = d
    # Control: the souls whose b-shares were revealed (t of them) and whose
    # y is on the wire; the others in their U2 must have t s-shares.
    K = [v for v in souls if ysv.get(v) is not None and len(bsh.get(v, {})) >= t]
    ctl = None
    if K:
        v0 = K[0]
        r0 = rounds[v0][1]
        u2 = None
        for _, ln in to.get(v0, []):
            p = P(ln)
            if p and p[0] == R.EV_SET and p[2] == 2:
                u2 = R.bitmap_xs(p[3], n)
                break
        D = [ro.entries[x - 1][0] for x in (u2 or []) if ro.entries[x - 1][0] not in K]
        agg, why = unmask(t, r0, rounds[v0][3], K, D, ysv, bsh, ssh, spk)
        exp = None
        if all(k in xin for k in K):
            exp = [sum(xin[k][j] for k in K) & M32 for j in range(rounds[v0][3])]
        ctl = {"set": K, "dropped": D, "agg": agg, "why": why, "expected": exp,
               "exact": agg is not None and agg == exp}
    res["control"] = ctl
    res["leaks"] = sorted(int(k) for k, d in res["souls"].items() if d["leak"])
    res["revealers"] = sorted(int(k) for k, d in res["souls"].items() if d["revealed"])
    res["bad_revealers"] = sorted(int(k) for k, d in res["souls"].items()
                                  if d["revealed"] and not (d["sig3_ok"] and d["reveal_rule_ok"]))
    res["after_abort"] = sorted(int(k) for k, d in res["souls"].items() if d["lines_after_abort"])
    print(json.dumps(res, sort_keys=True))
    return 0


def main(argv):
    o = {"listen": None, "round": "1", "attack": "honest", "log": None, "souls": None, "victim": "", "hide": "",
         "groups": "", "r0": "", "collude": "", "prev_log": "", "join_s": "20", "phase_s": "20", "hang_s": "15",
         "trickle_s": "0.5", "check": None, "x": [], "roster": os.environ.get("CE_SECAGG_ROSTER", ""),
         "tags": os.environ.get("CE_SECAGG_V4_TAGS", "")}
    i = 0
    while i < len(argv):
        k = argv[i][2:].replace("-", "_") if argv[i].startswith("--") else None
        if k not in o or i + 1 >= len(argv):
            print("secagg_evil_coord: bad argument %r" % argv[i], file=sys.stderr)
            return 2
        if k == "x":
            o["x"].append(argv[i + 1])
        else:
            o[k] = argv[i + 1]
        i += 2
    if o["check"]:
        return check_main(o)
    if not o["listen"] or not o["log"]:
        print(__doc__, file=sys.stderr)
        return 2
    o["round"] = int(o["round"])
    o["souls"] = int(o["souls"]) if o["souls"] else None
    for k in ("join_s", "phase_s", "hang_s", "trickle_s"):
        o[k] = float(o[k])
    return coord_main(o)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
