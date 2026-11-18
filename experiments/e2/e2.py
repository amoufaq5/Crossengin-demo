#!/usr/bin/env python3
"""E2 harness: does per-source trust give better-calibrated beliefs when
sources of different reliability make conflicting claims?

Pre-registration: experiments/e2/PREREG.md.

Usage:
  e2.py --selftest                     built-in checks (no NOVA needed)
  e2.py gen --mode M --seed N --out DIR [--facts 2000]
                                       write facts.tsv, claims.tsv, tiers.tsv
  e2.py build --nova NOVA_LAUNCHER     build bin/e2-driver from e2_driver.nova
  e2.py run --driver BIN --out DIR [--modes M0,..] [--seeds 1-20] [--jobs 4]
                                       generate, run the three CrossEngin arms
                                       and the three baselines, score, stats
  e2.py stats --out DIR                recompute statistics from DIR/scores.tsv

Everything is deterministic given the seed. Stdlib only.
"""

import argparse
import hashlib
import json
import math
import os
import random
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))

MODES = ["M0", "M1", "M2", "M3", "M4"]
CE_ARMS = ["flat", "graded", "mo"]
BASELINES = ["majority", "dawid_skene", "truthfinder"]
ARMS = CE_ARMS + BASELINES
N_SOURCES = 10
FACTS = 2000
COVERAGE = 0.3
BATCHES = 5
BOOT = 10000
ALPHA = 0.05
# Pre-registered comparisons: (arm, comparator). Lower Brier is better.
COMPARISONS = [("graded", "flat"), ("mo", "flat"), ("mo", "dawid_skene"),
               ("mo", "majority"), ("mo", "truthfinder")]


# ---------------------------------------------------------------- data

def source_tag(i):
    return "src:e2:s%02d" % i


def nominal_reliability(i):
    """s00 .. s09: 0.55 .. 0.95, linear."""
    return 0.55 + 0.40 * i / (N_SOURCES - 1)


def nominal_tier(r):
    """The graded arm's prior: the tier a curator would give the source's
    nominal (M0) reliability. 1 = A, 2 = B, 3 = C."""
    if r >= 0.85:
        return 1
    if r >= 0.70:
        return 2
    return 3


def generate(mode, seed, n_facts=FACTS):
    """Return (facts, claims, tiers, meta). facts: [(fid, truth)];
    claims: [(fid, source, value)] in arrival order; tiers: [(source, tier)].

    Modes (PREREG section 3):
      M0 independent errors.
      M1 copying: s01 and s02 copy s00 (the least reliable) with prob 0.8 on
         every fact s00 claims.
      M2 liar: s08 asserts the false value on every claim and covers 0.6 of
         the facts (its nominal tier is still A).
      M3 sparse experts: s08 and s09 cover 0.05 of facts; s00-s02 cover 0.6.
      M4 collusion: s05, s06, s07 assert the false value on a target 20% of
         the facts (and claim every target fact); elsewhere they are honest
         at their nominal reliability.
    """
    if mode not in MODES:
        raise ValueError("unknown mode " + mode)
    rng = random.Random("e2:%s:%d" % (mode, seed))
    facts = [("f%05d" % i, rng.randint(0, 1)) for i in range(n_facts)]
    cov = [COVERAGE] * N_SOURCES
    rel = [nominal_reliability(i) for i in range(N_SOURCES)]
    if mode == "M2":
        cov[8] = 0.6
    if mode == "M3":
        cov[8] = cov[9] = 0.05
        cov[0] = cov[1] = cov[2] = 0.6
    target = set()
    if mode == "M4":
        target = {fid for fid, _ in facts if rng.random() < 0.2}
    claims = []
    s00 = {}
    for fid, truth in facts:
        for s in range(N_SOURCES):
            covered = rng.random() < cov[s]
            r = rng.random()
            if mode == "M4" and s in (5, 6, 7) and fid in target:
                claims.append((fid, source_tag(s), 1 - truth))
                continue
            if not covered:
                continue
            if mode == "M2" and s == 8:
                val = 1 - truth
            else:
                val = truth if r < rel[s] else 1 - truth
            if mode == "M1" and s in (1, 2) and fid in s00 and rng.random() < 0.8:
                val = s00[fid]
            if s == 0:
                s00[fid] = val
            claims.append((fid, source_tag(s), val))
    rng.shuffle(claims)
    tiers = [(source_tag(i), nominal_tier(nominal_reliability(i))) for i in range(N_SOURCES)]
    meta = {"mode": mode, "seed": seed, "facts": n_facts, "claims": len(claims),
            "target": sorted(target)}
    return facts, claims, tiers, meta


def write_dataset(d, facts, claims, tiers, meta):
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "facts.tsv"), "w") as f:
        for fid, t in facts:
            f.write("%s\t%d\n" % (fid, t))
    with open(os.path.join(d, "claims.tsv"), "w") as f:
        for fid, s, v in claims:
            f.write("%s\t%s\t%d\n" % (fid, s, v))
    with open(os.path.join(d, "tiers.tsv"), "w") as f:
        for s, t in tiers:
            f.write("%s\t%d\n" % (s, t))
    with open(os.path.join(d, "meta.json"), "w") as f:
        json.dump(meta, f, sort_keys=True)


# ---------------------------------------------------------------- metrics
# Exact ports of src/bench/calibration.nova (integer milli, truncating
# division on non-negative values).

def cal_brier(samples):
    n = len(samples)
    if n == 0:
        return 0
    s = sum((p - 1000 * o) ** 2 for p, o in samples)
    return s // n // 1000


def cal_ece(samples):
    n = len(samples)
    if n == 0:
        return 0
    cnt, sump, sumo = [0] * 10, [0] * 10, [0] * 10
    for p, o in samples:
        b = min(p // 100, 9)
        cnt[b] += 1
        sump[b] += p
        sumo[b] += o
    ece = 0
    for b in range(10):
        c = cnt[b]
        if c > 0:
            diff = abs(sump[b] // c - sumo[b] * 1000 // c)
            ece += diff * c // n
    return ece


def cal_accuracy(samples):
    n = len(samples)
    if n == 0:
        return 0
    ok = sum(1 for p, o in samples if (1 if p >= 500 else 0) == o)
    return ok * 1000 // n


def milli(p):
    """Probability -> integer milli in 0..1000 (floor, clamped)."""
    return max(0, min(1000, int(math.floor(p * 1000.0))))


# ---------------------------------------------------------------- baselines

def _by_fact(claims):
    out = {}
    for fid, s, v in claims:
        out.setdefault(fid, []).append((s, v))
    return out


def majority(facts, claims):
    """Laplace-smoothed share of 'true' claims: (pos + 1) / (n + 2)."""
    bf = _by_fact(claims)
    res = {}
    for fid, _ in facts:
        cl = bf.get(fid, [])
        pos = sum(v for _, v in cl)
        res[fid] = milli((pos + 1) / (len(cl) + 2))
    return res


def dawid_skene(facts, claims, iters=50):
    """One-coin Dawid-Skene EM: one accuracy a_s per source, prior 0.5.
    a_s is smoothed (agree + 1) / (n + 2) and clipped to [0.01, 0.99]."""
    bf = _by_fact(claims)
    srcs = sorted({s for _, s, _ in claims})
    acc = {s: 0.7 for s in srcs}
    post = {}
    for _ in range(iters):
        for fid, _ in facts:
            lo = 0.0
            for s, v in bf.get(fid, []):
                a = acc[s]
                w = math.log(a / (1 - a))
                lo += w if v == 1 else -w
            lo = max(-50.0, min(50.0, lo))
            post[fid] = 1.0 / (1.0 + math.exp(-lo))
        agree = {s: 0.0 for s in srcs}
        n = {s: 0 for s in srcs}
        for fid, s, v in claims:
            p = post[fid]
            agree[s] += p if v == 1 else 1 - p
            n[s] += 1
        new = {s: min(0.99, max(0.01, (agree[s] + 1) / (n[s] + 2))) for s in srcs}
        delta = max(abs(new[s] - acc[s]) for s in srcs) if srcs else 0
        acc = new
        if delta < 1e-9:
            break
    return {fid: milli(post.get(fid, 0.5)) for fid, _ in facts}


def truthfinder(facts, claims, iters=20, gamma=0.3, rho=0.5, t0=0.9):
    """TruthFinder (Yin, Han & Yu 2008) for binary facts. Each fact has two
    candidate values; mutually exclusive values imply each other with -rho.
    Output p(true) = s(T) / (s(T) + s(F)), the normalised confidences."""
    bf = _by_fact(claims)
    srcs = sorted({s for _, s, _ in claims})
    trust = {s: t0 for s in srcs}
    conf = {}
    for _ in range(iters):
        for fid, _ in facts:
            sig = [0.0, 0.0]
            for s, v in bf.get(fid, []):
                t = min(trust[s], 1 - 1e-9)
                sig[v] += -math.log(1 - t)
            adj = [sig[0] - rho * sig[1], sig[1] - rho * sig[0]]
            conf[fid] = [1.0 / (1.0 + math.exp(-gamma * x)) for x in adj]
        tot = {s: 0.0 for s in srcs}
        n = {s: 0 for s in srcs}
        for fid, s, v in claims:
            tot[s] += conf[fid][v]
            n[s] += 1
        new = {s: (tot[s] / n[s]) if n[s] else t0 for s in srcs}
        delta = max(abs(new[s] - trust[s]) for s in srcs) if srcs else 0
        trust = new
        if delta < 1e-9:
            break
    res = {}
    for fid, _ in facts:
        c = conf.get(fid, [0.5, 0.5])
        res[fid] = milli(c[1] / (c[0] + c[1]))
    return res


BASELINE_FN = {"majority": majority, "dawid_skene": dawid_skene, "truthfinder": truthfinder}


# ---------------------------------------------------------------- driver

def run_driver(driver, d, arm, batches=BATCHES):
    env = {"E2_DIR": d, "E2_ARM": arm, "E2_BATCHES": str(batches)}
    p = subprocess.run([driver], env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                       timeout=3600)
    out = p.stdout.decode("utf-8", "replace")
    beliefs, metric, weights = {}, None, []
    for line in out.splitlines():
        parts = line.split()
        if not parts:
            continue
        if parts[0] == "P" and len(parts) == 3:
            beliefs[parts[1]] = int(parts[2])
        elif parts[0] == "M":
            metric = dict(kv.split("=", 1) for kv in parts[1:])
        elif parts[0] == "W" and len(parts) == 4:
            weights.append((int(parts[1]), parts[2], int(parts[3])))
        elif parts[0] == "E2" and len(parts) > 1 and parts[1] == "ERROR:":
            raise RuntimeError("driver: " + line)
    if metric is None or p.returncode != 0:
        raise RuntimeError("driver failed (rc=%d) on %s/%s:\n%s" % (p.returncode, d, arm, out[-2000:]))
    return beliefs, {k: int(v) for k, v in metric.items()}, weights


def score(facts, beliefs):
    samples = [(beliefs[fid], t) for fid, t in facts]
    return {"brier": cal_brier(samples), "ece": cal_ece(samples), "acc": cal_accuracy(samples)}


# ---------------------------------------------------------------- statistics

def bootstrap_diff(diffs, reps=BOOT, seed=0):
    """Paired bootstrap over seeds of the mean difference. Returns
    (mean, lo95, hi95, p_two_sided). p = 2 * min(share <= 0, share >= 0),
    capped at 1 (percentile-bootstrap test of mean diff = 0)."""
    n = len(diffs)
    mean = sum(diffs) / n
    rng = random.Random("e2-boot:%d" % seed)
    means = []
    for _ in range(reps):
        s = 0
        for _ in range(n):
            s += diffs[rng.randrange(n)]
        means.append(s / n)
    means.sort()
    lo = means[int(0.025 * reps)]
    hi = means[int(0.975 * reps) - 1]
    le = sum(1 for m in means if m <= 0) / reps
    ge = sum(1 for m in means if m >= 0) / reps
    return mean, lo, hi, min(1.0, 2 * min(le, ge))


def holm(pvals):
    names = sorted(pvals, key=lambda k: (pvals[k], k))
    m = len(names)
    adj, run = {}, 0.0
    for i, k in enumerate(names):
        run = max(run, min(1.0, (m - i) * pvals[k]))
        adj[k] = run
    return adj


def compute_stats(rows, modes, seeds):
    """rows: list of dicts mode, seed, arm, brier, ece, acc."""
    tab = {(r["mode"], r["seed"], r["arm"]): r for r in rows}
    out, praw = [], {}
    for mode in modes:
        for a, b in COMPARISONS:
            diffs = [tab[(mode, s, a)]["brier"] - tab[(mode, s, b)]["brier"] for s in seeds]
            key = "%s:%s-vs-%s" % (mode, a, b)
            mean, lo, hi, p = bootstrap_diff(diffs, seed=len(out))
            praw[key] = p
            out.append({"mode": mode, "arm": a, "comparator": b, "mean_brier_diff": mean,
                        "lo95": lo, "hi95": hi, "p_boot": p, "key": key})
    adj = holm(praw)
    for r in out:
        r["p_holm"] = adj[r["key"]]
        r["reject"] = 1 if adj[r["key"]] < ALPHA else 0
    return out


# ---------------------------------------------------------------- commands

def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def parse_seeds(s):
    if "-" in s:
        a, b = s.split("-")
        return list(range(int(a), int(b) + 1))
    return [int(x) for x in s.split(",")]


def cmd_run(args):
    driver = os.path.abspath(args.driver)
    out = os.path.abspath(args.out)
    if os.path.exists(out) and os.listdir(out):
        print("refusing to write into non-empty %s" % out, file=sys.stderr)
        return 2
    modes = args.modes.split(",")
    seeds = parse_seeds(args.seeds)
    partial = modes != MODES or seeds != list(range(1, 21)) or args.facts != FACTS
    if partial and not args.partial:
        print("not the pre-registered design (modes M0-M4, seeds 1-20, 2000 facts); pass --partial",
              file=sys.stderr)
        return 2
    os.makedirs(out)
    units = [(m, s) for m in modes for s in seeds]

    def one(u):
        mode, seed = u
        d = os.path.join(out, "data", "%s-s%02d" % (mode, seed))
        facts, claims, tiers, meta = generate(mode, seed, args.facts)
        write_dataset(d, facts, claims, tiers, meta)
        rows, xcheck = [], []
        for arm in CE_ARMS:
            beliefs, m, weights = run_driver(driver, d, arm)
            sc = score(facts, beliefs)
            # Cross-check: the Python port must reproduce the driver's own
            # calibration.nova numbers exactly.
            same = (sc["brier"] == m["brier"] and sc["ece"] == m["ece"] and sc["acc"] == m["acc"])
            xcheck.append((mode, seed, arm, same))
            with open(os.path.join(d, "beliefs_%s.tsv" % arm), "w") as f:
                for fid, _ in facts:
                    f.write("%s\t%d\n" % (fid, beliefs[fid]))
            if weights:
                with open(os.path.join(d, "weights_%s.tsv" % arm), "w") as f:
                    for b, s, w in weights:
                        f.write("%d\t%s\t%d\n" % (b, s, w))
            rows.append(dict(mode=mode, seed=seed, arm=arm, **sc))
        for arm in BASELINES:
            beliefs = BASELINE_FN[arm](facts, claims)
            with open(os.path.join(d, "beliefs_%s.tsv" % arm), "w") as f:
                for fid, _ in facts:
                    f.write("%s\t%d\n" % (fid, beliefs[fid]))
            rows.append(dict(mode=mode, seed=seed, arm=arm, **score(facts, beliefs)))
        # Target-subset accuracy for the adversarial modes (secondary).
        if meta["target"]:
            tgt = set(meta["target"])
            for r in rows:
                b = {}
                with open(os.path.join(d, "beliefs_%s.tsv" % r["arm"])) as f:
                    for line in f:
                        fid, v = line.split()
                        b[fid] = int(v)
                r["acc_target"] = cal_accuracy([(b[fid], t) for fid, t in facts if fid in tgt])
        return rows, xcheck

    with ThreadPoolExecutor(max_workers=args.jobs) as ex:
        results = list(ex.map(one, units))
    rows = [r for rs, _ in results for r in rs]
    xcheck = [x for _, xs in results for x in xs]
    bad = [x for x in xcheck if not x[3]]
    with open(os.path.join(out, "scores.tsv"), "w") as f:
        f.write("mode\tseed\tarm\tbrier\tece\tacc\tacc_target\n")
        for r in rows:
            f.write("%s\t%d\t%s\t%d\t%d\t%d\t%s\n" % (r["mode"], r["seed"], r["arm"], r["brier"],
                                                     r["ece"], r["acc"], r.get("acc_target", "")))
    manifest = {
        "schema": "e2-results-v1", "driver_sha256": sha256_file(driver),
        "inputs_sha256": {n: sha256_file(os.path.join(HERE, n))
                          for n in ("e2.py", "e2_driver.nova", "PREREG.md")},
        "modes": modes, "seeds": seeds, "facts": args.facts, "partial": partial,
        "python": sys.version.split()[0], "metric_crosscheck_failures": len(bad),
    }
    with open(os.path.join(out, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=1, sort_keys=True)
    if bad:
        print("METRIC CROSS-CHECK FAILED for %d run(s), e.g. %s" % (len(bad), bad[0]), file=sys.stderr)
        return 3
    return write_stats(out, rows, modes, seeds)


def write_stats(out, rows, modes, seeds):
    if len(seeds) < 2:
        print("ok: %d run(s) scored (statistics need >= 2 seeds)" % len(rows))
        return 0
    stats = compute_stats(rows, modes, seeds)
    with open(os.path.join(out, "stats.tsv"), "w") as f:
        cols = ["mode", "arm", "comparator", "mean_brier_diff", "lo95", "hi95", "p_boot", "p_holm", "reject"]
        f.write("\t".join(cols) + "\n")
        for r in stats:
            f.write("\t".join(("%.6g" % r[c]) if isinstance(r[c], float) else str(r[c]) for c in cols) + "\n")
    with open(os.path.join(out, "summary.tsv"), "w") as f:
        f.write("mode\tarm\tmean_brier\tmean_ece\tmean_acc\n")
        for mode in modes:
            for arm in ARMS:
                rs = [r for r in rows if r["mode"] == mode and r["arm"] == arm]
                f.write("%s\t%s\t%.1f\t%.1f\t%.1f\n" % (
                    mode, arm, sum(r["brier"] for r in rs) / len(rs),
                    sum(r["ece"] for r in rs) / len(rs), sum(r["acc"] for r in rs) / len(rs)))
    print("ok: %d run(s); results in %s" % (len(rows), out))
    return 0


def cmd_stats(args):
    out = os.path.abspath(args.out)
    man = json.load(open(os.path.join(out, "manifest.json")))
    now = {n: sha256_file(os.path.join(HERE, n)) for n in man["inputs_sha256"]}
    changed = [n for n, h in man["inputs_sha256"].items() if now[n] != h]
    if changed:
        print("inputs differ from the run's manifest: %s" % ", ".join(changed), file=sys.stderr)
        return 2
    rows = []
    with open(os.path.join(out, "scores.tsv")) as f:
        next(f)
        for line in f:
            c = line.rstrip("\n").split("\t")
            rows.append(dict(mode=c[0], seed=int(c[1]), arm=c[2], brier=int(c[3]), ece=int(c[4]), acc=int(c[5])))
    return write_stats(out, rows, man["modes"], man["seeds"])


def cmd_build(args):
    out = os.path.join(REPO, "bin", "e2-driver")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    p = subprocess.run([args.nova, "build", os.path.join(HERE, "e2_driver.nova"), "-o", out], cwd=REPO)
    return p.returncode


# ---------------------------------------------------------------- selftest

def selftest():
    checks = []

    def check(name, cond):
        checks.append((name, bool(cond)))

    # Metric port against calibration.nova's own values (probe in the B5
    # mapping: (733,1),(733,0),(91,0) -> Brier 205, ECE 185).
    smp = [(733, 1), (733, 0), (91, 0)]
    check("brier port", cal_brier(smp) == 205)
    check("ece port", cal_ece(smp) == 185)
    check("acc port", cal_accuracy(smp) == 666)
    check("p=1000 lands in bin 9", cal_ece([(1000, 1)]) == 0)
    check("empty", cal_brier([]) == 0 and cal_ece([]) == 0)
    check("milli clamps", milli(1.2) == 1000 and milli(-0.1) == 0)
    # Generator.
    f1, c1, t1, m1 = generate("M0", 3, 300)
    f2, c2, t2, m2 = generate("M0", 3, 300)
    check("generator deterministic", f1 == f2 and c1 == c2)
    check("seeds differ", generate("M0", 4, 300)[1] != c1)
    check("coverage about 0.3", 0.25 < len(c1) / (300 * N_SOURCES) < 0.35)
    check("tiers", [t for _, t in t1] == [3, 3, 3, 3, 2, 2, 2, 1, 1, 1])
    fm, cm, _, _ = generate("M2", 3, 600)
    tr = dict(fm)
    liar = [(f, v) for f, s, v in cm if s == source_tag(8)]
    check("M2 liar always false", liar and all(v != tr[f] for f, v in liar))
    fc, cc, _, mc = generate("M4", 3, 600)
    tr = dict(fc)
    tg = set(mc["target"])
    col = [(f, v) for f, s, v in cc if s in (source_tag(5), source_tag(6), source_tag(7)) and f in tg]
    check("M4 colluders claim every target fact falsely", len(col) == 3 * len(tg) and all(v != tr[f] for f, v in col))
    # Baselines on a toy: 3 reliable sources agree, 1 liar disagrees.
    facts = [("a", 1), ("b", 0)]
    claims = [("a", "s1", 1), ("a", "s2", 1), ("a", "s3", 1), ("a", "lie", 0),
              ("b", "s1", 0), ("b", "s2", 0), ("b", "s3", 0), ("b", "lie", 1)]
    mv = majority(facts, claims)
    check("majority laplace", mv["a"] == 666 and mv["b"] == 333)
    ds = dawid_skene(facts, claims)
    check("dawid-skene follows the agreeing sources", ds["a"] > 900 and ds["b"] < 100)
    tf = truthfinder(facts, claims)
    check("truthfinder follows the agreeing sources", tf["a"] > 500 and tf["b"] < 500)
    check("uncovered fact is 500", majority([("z", 1)], [])["z"] == 500 and dawid_skene([("z", 1)], [])["z"] == 500)
    # Statistics.
    m, lo, hi, p = bootstrap_diff([1.0] * 20, reps=500)
    check("bootstrap constant diff", m == 1.0 and lo == 1.0 and p == 0.0)
    m, lo, hi, p = bootstrap_diff([1, -1] * 10, reps=2000)
    check("bootstrap null diff not significant", p > 0.5)
    check("bootstrap deterministic", bootstrap_diff([3, 1, 4, 1, 5], reps=300) == bootstrap_diff([3, 1, 4, 1, 5], reps=300))
    h = holm({"a": 0.01, "b": 0.04, "c": 0.03})
    check("holm", abs(h["a"] - 0.03) < 1e-12 and abs(h["c"] - 0.06) < 1e-12 and abs(h["b"] - 0.06) < 1e-12)
    check("seed ranges", parse_seeds("1-3") == [1, 2, 3] and parse_seeds("2,5") == [2, 5])
    ok = all(c for _, c in checks)
    for n, c in checks:
        if not c:
            print("FAIL:", n)
    print("e2 selftest: %d checks -> %s" % (len(checks), "OK" if ok else "FAIL"))
    return 0 if ok else 1


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--selftest", action="store_true")
    sub = ap.add_subparsers(dest="cmd")
    p = sub.add_parser("gen")
    p.add_argument("--mode", required=True)
    p.add_argument("--seed", type=int, required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--facts", type=int, default=FACTS)
    p = sub.add_parser("build")
    p.add_argument("--nova", required=True)
    p = sub.add_parser("run")
    p.add_argument("--driver", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--modes", default=",".join(MODES))
    p.add_argument("--seeds", default="1-20")
    p.add_argument("--facts", type=int, default=FACTS)
    p.add_argument("--jobs", type=int, default=4)
    p.add_argument("--partial", action="store_true")
    p = sub.add_parser("stats")
    p.add_argument("--out", required=True)
    args = ap.parse_args(argv)
    if args.selftest:
        return selftest()
    if args.cmd == "gen":
        write_dataset(args.out, *generate(args.mode, args.seed, args.facts))
        return 0
    if args.cmd == "build":
        return cmd_build(args)
    if args.cmd == "run":
        return cmd_run(args)
    if args.cmd == "stats":
        return cmd_stats(args)
    ap.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())
