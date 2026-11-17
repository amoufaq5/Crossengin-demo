#!/usr/bin/env python3
"""E1 ablation harness: which learning mechanisms change what the chat says?

Pre-registration: experiments/e1/PREREG.md. Inputs: experiments/e1/inputs/.

Usage:
  e1.py --selftest                        built-in checks (no chat binary needed)
  e1.py lint                              validate replay, gold, perms and arms
  e1.py perms --seeds 1,2,3,4,5           print a permutation table (perms_v1.tsv)
  e1.py stdin --perm K                    print the chat stdin for permutation K
  e1.py refcheck --chat BIN [--show]      run each episode alone (full arm) and
                                          report items whose gold fails there
  e1.py run --chat BIN --out DIR [--arms a,b] [--perms 1,2] [--jobs 4]
                                          run arms x perms, the determinism gate,
                                          then parse, score and stats into DIR
  e1.py stats --out DIR                   recompute scores and stats from DIR/raw

Every chat process gets a fresh private run dir (mode 0700) and an environment
built from scratch (no inherited variables): HOME, CE_RUN_DIR, CE_EXP_TRACE=1,
CE_CAPS_CONF and the arm's own flags. Stdlib only.
"""

import argparse
import hashlib
import json
import math
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
INPUTS = os.path.join(HERE, "inputs")
REPLAY = os.path.join(INPUTS, "replay_v1.tsv")
GOLD = os.path.join(INPUTS, "gold_v1.tsv")
PERMS = os.path.join(INPUTS, "perms_v1.tsv")
ARMS = os.path.join(HERE, "arms.tsv")
CAPS = os.path.join(INPUTS, "caps_e1.conf")

BLOCK_ORDER = ["R", "P", "C", "U", "F", "H"]
MAJORITY = 3            # an item is correct in an arm if correct in >= 3 of 5 perms
ALPHA = 0.05
CHAT_TIMEOUT = 300

# First words the chat rewrites into admin commands (_try_auto_prefix), and
# words that end the session. Replay lines must not start with them.
AUTO_PREFIX = {"why", "define", "explain", "find", "prove", "recall", "classify",
               "learn", "teach", "know", "knowledge", "cap", "synapse"}
ALONE_PREFIX = {"help", "status", "good", "bad"}
SESSION_END = {"quit", "exit"}
ALLOWED_ADMIN = {"/good", "/bad", "/correct"}

MARKER_RE = re.compile(r"^\(unknown command: /__e1_(\S+) -- try /help\)\s*$")
CHAIN_RE = re.compile(r"[a-z0-9_]+(?:->[a-z0-9_]+)+")


# ---------------------------------------------------------------- inputs

def read_tsv(path):
    out = []
    with open(path, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            out.append((n, line.split("\t")))
    return out


def load_replay(path=REPLAY):
    rows = []
    for n, cols in read_tsv(path):
        if len(cols) != 4:
            raise ValueError("%s:%d: want 4 columns, got %d" % (path, n, len(cols)))
        iid, block, episode, text = cols
        rows.append({"id": iid, "block": block, "episode": episode, "text": text, "line": n})
    return rows


def load_gold(path=GOLD):
    gold = {}
    for n, cols in read_tsv(path):
        if len(cols) < 2:
            raise ValueError("%s:%d: want id<TAB>spec[<TAB>note]" % (path, n))
        if cols[0] in gold:
            raise ValueError("%s:%d: duplicate gold id %s" % (path, n, cols[0]))
        gold[cols[0]] = cols[1]
    return gold


def load_arms(path=ARMS):
    arms = []
    for n, cols in read_tsv(path):
        if len(cols) != 3:
            raise ValueError("%s:%d: want name<TAB>env<TAB>comparator" % (path, n))
        name, env, comp = cols
        envd = {}
        if env != "-":
            for kv in env.split():
                k, v = kv.split("=", 1)
                envd[k] = v
        arms.append({"name": name, "env": envd, "comparator": None if comp == "-" else comp})
    return arms


def episodes_by_block(rows):
    """{block: [episode_id, ...]} in file order, and {episode_id: [rows]}."""
    order, eps = {b: [] for b in BLOCK_ORDER}, {}
    for r in rows:
        if r["episode"] not in eps:
            eps[r["episode"]] = []
            order[r["block"]].append(r["episode"])
        eps[r["episode"]].append(r)
    return order, eps


def scored_ids(rows, gold):
    return [r["id"] for r in rows if r["id"] != "-" and gold.get(r["id"], "-") != "-"]


def make_perm(rows, seed):
    """Episode order for one permutation: blocks in fixed order, episodes
    shuffled within each block by random.Random(seed)."""
    order, _ = episodes_by_block(rows)
    rng = random.Random(seed)
    out = []
    for b in BLOCK_ORDER:
        e = list(order[b])
        rng.shuffle(e)
        out.extend(e)
    return out


def load_perms(path=PERMS):
    perms = {}
    for n, cols in read_tsv(path):
        if len(cols) != 3:
            raise ValueError("%s:%d: want perm<TAB>seed<TAB>episodes" % (path, n))
        perms[int(cols[0])] = {"seed": int(cols[1]), "episodes": cols[2].split(",")}
    return perms


def build_stdin(rows, episode_order):
    """Chat stdin: each scored or probe item is preceded by an inert marker
    line (/__e1_<id>); feedback lines follow their item without a marker."""
    _, eps = episodes_by_block(rows)
    out = []
    for e in episode_order:
        for r in eps[e]:
            if r["id"] != "-":
                out.append("/__e1_" + r["id"])
            out.append(r["text"])
    out += ["/__e1___end", "/__learning__", "/quit"]
    return "\n".join(out) + "\n"


# ---------------------------------------------------------------- lint

def lint_line(text):
    """Return a problem string for a replay line, or None."""
    if text.strip() == "":
        return "blank line ends the session"
    if text != text.strip():
        return "leading/trailing whitespace"
    words = text.lower().split()
    if words[0] in SESSION_END:
        return "'%s' ends the session" % words[0]
    if text.startswith("/"):
        if words[0] not in ALLOWED_ADMIN:
            return "admin command %s not allowed" % words[0]
        return None
    if words[0] in AUTO_PREFIX:
        return "first word '%s' is rewritten into an admin command" % words[0]
    if len(words) == 1 and words[0] in ALONE_PREFIX:
        return "'%s' alone is rewritten into an admin command" % words[0]
    if len(words) > 60 or len(text) > 1000:
        return "line too long"
    return None


def lint(rows, gold, perms, arms):
    errs = []
    seen = set()
    for r in rows:
        p = lint_line(r["text"])
        if p:
            errs.append("replay:%d: %s: %r" % (r["line"], p, r["text"]))
        if r["block"] not in BLOCK_ORDER:
            errs.append("replay:%d: unknown block %s" % (r["line"], r["block"]))
        if r["id"] != "-":
            if r["id"] in seen:
                errs.append("replay:%d: duplicate id %s" % (r["line"], r["id"]))
            seen.add(r["id"])
            if r["id"] not in gold:
                errs.append("replay:%d: no gold row for %s" % (r["line"], r["id"]))
            if not re.match(r"^[A-Za-z0-9]+$", r["id"]):
                errs.append("replay:%d: id must be alphanumeric" % r["line"])
        elif not r["text"].startswith("/"):
            errs.append("replay:%d: unscored line must be feedback" % r["line"])
    for gid, spec in gold.items():
        if gid not in seen:
            errs.append("gold: %s not in replay" % gid)
        if spec != "-":
            try:
                for kind, val in parse_spec(spec):
                    if kind == "differs" and val not in seen:
                        errs.append("gold: %s differs= unknown id %s" % (gid, val))
            except ValueError as e:
                errs.append("gold: %s: %s" % (gid, e))
    order, _ = episodes_by_block(rows)
    all_eps = sorted(e for b in BLOCK_ORDER for e in order[b])
    for k, p in sorted(perms.items()):
        if sorted(p["episodes"]) != all_eps:
            errs.append("perms: perm %d is not a permutation of the episodes" % k)
        if p["episodes"] != make_perm(rows, p["seed"]):
            errs.append("perms: perm %d does not match seed %d" % (k, p["seed"]))
    names = {a["name"] for a in arms}
    for a in arms:
        if a["comparator"] and a["comparator"] not in names:
            errs.append("arms: %s compares against unknown arm %s" % (a["name"], a["comparator"]))
    return errs


# ---------------------------------------------------------------- parse

class ParseError(Exception):
    pass


def parse_output(raw):
    """Split a chat transcript into items keyed by marker id. Each item has
    'body' (its text without EXP lines), 'agent' (first agent> line, without
    the prefix) and 'exp' (the parsed EXP json or None)."""
    if "approve? [y/N" in raw:
        raise ParseError("an approval prompt appeared (it eats the next line)")
    if re.search(r"\(dlog: .* loaded", raw):
        raise ParseError("a previous run's dlog was loaded")
    if not raw.rstrip().endswith("bye."):
        raise ParseError("the session did not end with 'bye.'")
    items, cur, order = {}, None, []
    for seg in re.split(r"(?m)^> ", raw)[1:]:
        first = seg.split("\n", 1)[0]
        m = MARKER_RE.match(first)
        if m:
            cur = m.group(1)
            if cur == "__end":
                cur = None
                continue
            if cur in items:
                raise ParseError("marker %s seen twice" % cur)
            items[cur] = []
            order.append(cur)
            continue
        if cur is not None:
            items[cur].append(seg)
    out = {}
    for iid in order:
        text = "".join(items[iid])
        if not items[iid]:
            raise ParseError("item %s has no output" % iid)
        lines = text.split("\n")
        exps = [l for l in lines if l.startswith("EXP {")]
        if len(exps) > 1:
            raise ParseError("item %s has %d EXP lines" % (iid, len(exps)))
        body = "\n".join(l for l in lines
                         if not l.startswith("EXP {") and not l.startswith("[nl-ic] "))
        agent = ""
        for l in lines:
            if l.startswith("agent> "):
                agent = l[len("agent> "):].rstrip()
                break
        exp = json.loads(exps[0][4:]) if exps else None
        out[iid] = {"body": body.strip("\n"), "agent": agent, "exp": exp}
    return out


# ---------------------------------------------------------------- scoring

SPEC_KINDS = {"about", "chain", "ops", "line", "prefix", "has", "differs", "nl", "cat"}


def parse_spec(spec):
    parts = []
    for p in spec.split(" && "):
        if "=" not in p:
            raise ValueError("bad spec part %r" % p)
        k, v = p.split("=", 1)
        if k not in SPEC_KINDS:
            raise ValueError("unknown spec kind %r" % k)
        parts.append((k, v))
    return parts


def chain_nodes(agent):
    m = CHAIN_RE.search(agent)
    return m.group(0).split("->") if m else []


def eval_spec(spec, item, items):
    """1 if every part of the spec holds for `item`, else 0. A missing item
    is wrong."""
    if item is None:
        return 0
    agent, exp = item["agent"], item["exp"]
    for k, v in parse_spec(spec):
        if k == "about":
            nodes = chain_nodes(agent)
            ok = bool(nodes) and v in (nodes[0], nodes[-1])
        elif k == "chain":
            ok = v in chain_nodes(agent)
        elif k == "ops":
            ok = exp is not None and exp.get("ops") == v
        elif k == "line":
            ok = agent == v
        elif k == "prefix":
            ok = agent.startswith(v)
        elif k == "has":
            ok = v in agent
        elif k == "differs":
            other = items.get(v)
            ok = other is not None and agent != "" and other["agent"] != "" and agent != other["agent"]
        elif k == "nl":
            ok = exp is not None and str(exp.get("nl")) == v
        elif k == "cat":
            ok = exp is not None and exp.get("category") == v
        if not ok:
            return 0
    return 1


def score_items(items, gold, ids):
    return {i: eval_spec(gold[i], items.get(i), items) for i in ids}


# ---------------------------------------------------------------- statistics

def mcnemar_exact(b, c):
    """Two-sided exact McNemar p-value (binomial test of b vs c at 1/2)."""
    n = b + c
    if n == 0:
        return 1.0
    k = min(b, c)
    tail = sum(math.comb(n, i) for i in range(k + 1))
    return min(1.0, 2.0 * tail / (2 ** n))


def holm(pvals):
    """Holm step-down adjusted p-values for {name: p}."""
    names = sorted(pvals, key=lambda n: (pvals[n], n))
    m = len(names)
    adj, running = {}, 0.0
    for i, n in enumerate(names):
        running = max(running, min(1.0, (m - i) * pvals[n]))
        adj[n] = running
    return adj


def majority(scores, perms, iid):
    return 1 if sum(scores[p][iid] for p in perms) >= MAJORITY else 0


def compute_stats(per_arm, arms, ids, perms, bodies):
    """per_arm[arm][perm][id] -> 0/1. bodies[arm][perm][id] -> text.
    Returns (stats rows, discordance rows)."""
    rows, praw = [], {}
    for a in arms:
        if not a["comparator"]:
            continue
        A, B = per_arm[a["name"]], per_arm[a["comparator"]]
        b = c = 0
        for i in ids:
            ma, mb = majority(A, perms, i), majority(B, perms, i)
            if mb == 1 and ma == 0:
                b += 1
            elif mb == 0 and ma == 1:
                c += 1
        p = mcnemar_exact(b, c)
        praw[a["name"]] = p
        acc_a = sum(majority(A, perms, i) for i in ids)
        acc_b = sum(majority(B, perms, i) for i in ids)
        diff_items = sum(1 for i in ids if any(
            bodies[a["name"]][k].get(i) != bodies[a["comparator"]][k].get(i) for k in perms))
        rows.append({"arm": a["name"], "comparator": a["comparator"], "n": len(ids),
                     "correct_arm": acc_a, "correct_comp": acc_b, "b_lost": b, "c_gained": c,
                     "p_exact": p, "items_text_differs": diff_items})
    adj = holm(praw)
    for r in rows:
        r["p_holm"] = adj[r["arm"]]
        r["reject"] = 1 if adj[r["arm"]] < ALPHA else 0
    return rows


# ---------------------------------------------------------------- running

def decode(raw_bytes):
    return raw_bytes.decode("utf-8", "replace").replace("\r", "")


def run_chat(chat, stdin_text, arm_env, caps=CAPS):
    """Run one chat process; returns its raw stdout+stderr bytes."""
    d = tempfile.mkdtemp(prefix="e1-")
    os.chmod(d, 0o700)
    env = {"HOME": d, "CE_RUN_DIR": d, "CE_EXP_TRACE": "1", "CE_CAPS_CONF": caps}
    env.update(arm_env)
    try:
        p = subprocess.run([chat], input=stdin_text.encode(), stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT, env=env, cwd=d, timeout=CHAT_TIMEOUT)
        return p.stdout
    finally:
        shutil.rmtree(d, ignore_errors=True)


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def cmd_run(args):
    rows, gold, perms, arms = load_replay(), load_gold(), load_perms(), load_arms()
    errs = lint(rows, gold, perms, arms)
    if errs:
        print("\n".join(errs), file=sys.stderr)
        return 2
    chat = os.path.abspath(args.chat)
    partial = False
    if args.arms:
        want = args.arms.split(",")
        unknown = [w for w in want if w not in {a["name"] for a in arms}]
        if unknown:
            print("unknown arm(s): %s" % ",".join(unknown), file=sys.stderr)
            return 2
        partial = len(want) < len(arms)
        arms = [a for a in arms if a["name"] in want]
    pk = sorted(perms) if not args.perms else [int(x) for x in args.perms.split(",")]
    bad = [k for k in pk if k not in perms]
    if bad:
        print("unknown perm(s): %s" % ",".join(map(str, bad)), file=sys.stderr)
        return 2
    partial = partial or pk != sorted(perms)
    if partial and not args.partial:
        print("a subset of arms or perms is not the pre-registered study; pass --partial", file=sys.stderr)
        return 2
    if not any(a["name"] == "full" for a in arms):
        print("the full arm is required (determinism gate)", file=sys.stderr)
        return 2
    names = {a["name"] for a in arms}
    for a in arms:
        if a["comparator"] and a["comparator"] not in names:
            a["comparator"] = None
    out = os.path.abspath(args.out)
    if os.path.exists(out) and os.listdir(out):
        print("refusing to write into non-empty %s" % out, file=sys.stderr)
        return 2
    os.makedirs(os.path.join(out, "raw"), exist_ok=True)
    jobs = [(a, k, "") for a in arms for k in pk]
    full = [a for a in arms if a["name"] == "full"][0]
    jobs += [(full, k, ".rerun") for k in pk]

    def one(job):
        a, k, suffix = job
        raw = run_chat(chat, build_stdin(rows, perms[k]["episodes"]), a["env"])
        path = os.path.join(out, "raw", a["name"], "p%d%s.out" % (k, suffix))
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(raw)
        return path

    with ThreadPoolExecutor(max_workers=args.jobs) as ex:
        list(ex.map(one, jobs))
    manifest = {
        "schema": "e1-results-v1",
        "chat_sha256": sha256_file(chat),
        "inputs_sha256": input_hashes(),
        "git": git_state(),
        "python": sys.version.split()[0],
        "arms": [a["name"] for a in arms], "perms": pk, "jobs": args.jobs,
        "partial": partial, "majority": MAJORITY, "alpha": ALPHA,
    }
    with open(os.path.join(out, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=1, sort_keys=True)
    return analyse(out, rows, gold, arms, pk, partial)


def input_hashes():
    return {os.path.relpath(p, HERE): sha256_file(p)
            for p in (REPLAY, GOLD, PERMS, ARMS, CAPS, os.path.abspath(__file__),
                      os.path.join(INPUTS, "gen_v1.py"))}


def git_state():
    root = os.path.dirname(os.path.dirname(HERE))
    try:
        rev = subprocess.run(["git", "-C", root, "rev-parse", "HEAD"], stdout=subprocess.PIPE,
                             stderr=subprocess.DEVNULL, timeout=30).stdout.decode().strip()
        dirty = subprocess.run(["git", "-C", root, "status", "--porcelain", "--", "src", "examples",
                                "experiments/e1"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                               timeout=30).stdout.decode().strip() != ""
        return {"rev": rev, "dirty": dirty}
    except (OSError, subprocess.SubprocessError):
        return {"rev": "", "dirty": None}


def analyse(out, rows, gold, arms, pk, partial):
    # Determinism gate: the full arm, run twice, must be byte-identical.
    gate = []
    for k in pk:
        a = os.path.join(out, "raw", "full", "p%d.out" % k)
        b = os.path.join(out, "raw", "full", "p%d.rerun.out" % k)
        if not (os.path.exists(a) and os.path.exists(b)):
            print("DETERMINISM GATE: missing full-arm output for perm %d" % k, file=sys.stderr)
            return 3
        with open(a, "rb") as fa, open(b, "rb") as fb:
            gate.append((k, fa.read() == fb.read()))
    with open(os.path.join(out, "determinism.tsv"), "w") as f:
        f.write("perm\tidentical\n")
        for k, same in gate:
            f.write("%d\t%d\n" % (k, 1 if same else 0))
    if not gate or not all(s for _, s in gate):
        print("DETERMINISM GATE FAILED: the full arm differs between two runs", file=sys.stderr)
        return 3
    ids = scored_ids(rows, gold)
    per_arm, bodies = {}, {}
    with open(os.path.join(out, "scores.tsv"), "w") as sf:
        sf.write("arm\tperm\titem\tblock\tcorrect\tagent\n")
        blocks = {r["id"]: r["block"] for r in rows}
        for a in arms:
            per_arm[a["name"]], bodies[a["name"]] = {}, {}
            for k in pk:
                with open(os.path.join(out, "raw", a["name"], "p%d.out" % k), "rb") as rf:
                    raw = decode(rf.read())
                try:
                    items = parse_output(raw)
                except ParseError as e:
                    print("parse error in %s p%d: %s" % (a["name"], k, e), file=sys.stderr)
                    return 4
                missing = [i for i in ids if i not in items]
                if missing:
                    print("%s p%d: missing items %s" % (a["name"], k, ",".join(missing[:10])), file=sys.stderr)
                    return 4
                sc = score_items(items, gold, ids)
                per_arm[a["name"]][k] = sc
                bodies[a["name"]][k] = {i: items[i]["body"] for i in ids}
                for i in ids:
                    sf.write("%s\t%d\t%s\t%s\t%d\t%s\n" % (a["name"], k, i, blocks[i], sc[i],
                                                         items[i]["agent"].replace("\t", " ")))
    if len(pk) < MAJORITY and not partial:
        print("statistics need at least %d perms" % MAJORITY, file=sys.stderr)
        return 5
    stats = compute_stats(per_arm, arms, ids, pk, bodies) if len(pk) >= MAJORITY else []
    cols = ["arm", "comparator", "n", "correct_arm", "correct_comp", "b_lost", "c_gained",
            "p_exact", "p_holm", "reject", "items_text_differs"]
    with open(os.path.join(out, "stats.tsv"), "w") as f:
        f.write("\t".join(cols) + "\n")
        for r in stats:
            f.write("\t".join(("%.6g" % r[c]) if isinstance(r[c], float) else str(r[c]) for c in cols) + "\n")
    with open(os.path.join(out, "blocks.tsv"), "w") as f:
        f.write("arm\tblock\tn_item_perm\tcorrect\n")
        for a in arms:
            for b in BLOCK_ORDER:
                bi = [i for i in ids if blocks[i] == b]
                tot = sum(per_arm[a["name"]][k][i] for k in pk for i in bi)
                f.write("%s\t%s\t%d\t%d\n" % (a["name"], b, len(bi) * len(pk), tot))
    print("ok: %d arm(s) x %d perm(s)%s; results in %s" % (
        len(arms), len(pk), " (partial)" if partial else "", out))
    return 0


def cmd_stats(args):
    rows, gold = load_replay(), load_gold()
    out = os.path.abspath(args.out)
    man = json.load(open(os.path.join(out, "manifest.json")))
    now = input_hashes()
    changed = [k for k, v in man["inputs_sha256"].items() if now.get(k) != v]
    if changed:
        print("inputs differ from the run's manifest: %s" % ", ".join(sorted(changed)), file=sys.stderr)
        return 2
    arms = [a for a in load_arms() if a["name"] in man["arms"]]
    names = {a["name"] for a in arms}
    for a in arms:
        if a["comparator"] and a["comparator"] not in names:
            a["comparator"] = None
    return analyse(out, rows, gold, arms, man["perms"], man.get("partial", False))


def cmd_refcheck(args):
    """Run every non-H episode alone in a fresh full-arm session and evaluate
    its items' gold there. H items are evaluated in one run of the file
    order. Reports failures; it does not change anything."""
    rows, gold = load_replay(), load_gold()
    order, eps = episodes_by_block(rows)
    chat = os.path.abspath(args.chat)
    units = [[e] for b in BLOCK_ORDER if b != "H" for e in order[b]]
    file_order = [e for b in BLOCK_ORDER for e in order[b]]

    def one(u):
        return u, parse_output(decode(run_chat(chat, build_stdin(rows, u), {})))

    with ThreadPoolExecutor(max_workers=args.jobs) as ex:
        results = list(ex.map(one, units))
    whole = parse_output(decode(run_chat(chat, build_stdin(rows, file_order), {})))
    fails, n = 0, 0
    for u, items in results + [(order["H"], whole)]:
        for e in u:
            for r in eps[e]:
                if r["id"] == "-" or gold.get(r["id"], "-") == "-":
                    if args.show and r["id"] != "-":
                        print("%-6s probe  %-38s | %s" % (r["id"], r["text"], items[r["id"]]["agent"]))
                    continue
                n += 1
                ok = eval_spec(gold[r["id"]], items.get(r["id"]), items)
                it = items.get(r["id"]) or {"agent": "<missing>", "exp": None}
                if not ok:
                    fails += 1
                if args.show or not ok:
                    ops = it["exp"]["ops"] if it["exp"] else "-"
                    print("%-6s %-5s %-38s | %s | ops=%s | gold: %s" % (
                        r["id"], "ok" if ok else "FAIL", r["text"], it["agent"], ops, gold[r["id"]]))
    print("refcheck: %d of %d scored items fail their gold in isolation" % (fails, n))
    return 0


# ---------------------------------------------------------------- selftest

def selftest():
    checks = []

    def check(name, cond):
        checks.append((name, bool(cond)))

    check("mcnemar b=0 c=6", abs(mcnemar_exact(0, 6) - 0.03125) < 1e-12)
    check("mcnemar b=c=3", mcnemar_exact(3, 3) == 1.0)
    check("mcnemar b=1 c=9", abs(mcnemar_exact(1, 9) - 2 * 11 / 1024) < 1e-12)
    check("mcnemar n=0", mcnemar_exact(0, 0) == 1.0)
    check("mcnemar symmetric", mcnemar_exact(2, 7) == mcnemar_exact(7, 2))
    h = holm({"a": 0.01, "b": 0.04, "c": 0.03})
    check("holm a", abs(h["a"] - 0.03) < 1e-12)
    check("holm c", abs(h["c"] - 0.06) < 1e-12)
    check("holm b monotone", abs(h["b"] - 0.06) < 1e-12)
    check("holm cap", holm({"x": 0.6, "y": 0.7})["y"] == 1.0)

    raw = ("=== banner ===\n\n> (unknown command: /__e1_A1 -- try /help)\n"
           "> [nl-ic] classifier init: 10 prototypes\nagent> virus leads to fever (virus->infection->symptom->fever).\n"
           "       reasoning: x\nEXP {\"turn\":0,\"nl\":0,\"router\":1,\"ops\":\"542,543,544\",\"category\":\"unknown\"}\n"
           "> noted -- weakened 3 inference(s)\n"
           "> (unknown command: /__e1_A2 -- try /help)\n> agent> = 4\n"
           "> (unknown command: /__e1___end -- try /help)\n> learn stuff\n> bye.\n")
    items = parse_output(raw)
    check("parse ids", sorted(items) == ["A1", "A2"])
    check("parse agent", items["A1"]["agent"] == "virus leads to fever (virus->infection->symptom->fever).")
    check("parse exp", items["A1"]["exp"]["ops"] == "542,543,544")
    check("parse feedback kept in item", "weakened" in items["A1"]["body"])
    check("parse no exp", items["A2"]["exp"] is None)
    check("parse init line stripped", "[nl-ic]" not in items["A1"]["body"])
    for bad, why in (("> approve? [y/N/why] \n> bye.\n", "approval"),
                     ("(dlog: /x/crossengin.dlog loaded 3 prior entries)\n> bye.\n", "dlog"),
                     ("> (unknown command: /__e1_A -- try /help)\n> agent> x\n", "no bye")):
        try:
            parse_output(bad)
            check("parse rejects " + why, False)
        except ParseError:
            check("parse rejects " + why, True)
    check("about head", eval_spec("about=virus", items["A1"], items) == 1)
    check("about tail", eval_spec("about=fever", items["A1"], items) == 1)
    check("about middle fails", eval_spec("about=symptom", items["A1"], items) == 0)
    check("chain middle", eval_spec("chain=symptom", items["A1"], items) == 1)
    check("chain absent", eval_spec("chain=pain", items["A1"], items) == 0)
    check("decode strips CR", decode(b"a\r\nb") == "a\nb")
    check("ops", eval_spec("ops=542,543,544", items["A1"], items) == 1)
    check("ops wrong", eval_spec("ops=542", items["A1"], items) == 0)
    check("line", eval_spec("line== 4", items["A2"], items) == 1)
    check("prefix and nl", eval_spec("prefix=virus && nl=0", items["A1"], items) == 1)
    check("and fails", eval_spec("prefix=virus && nl=1", items["A1"], items) == 0)
    check("ops needs exp", eval_spec("ops=", items["A2"], items) == 0)
    check("differs", eval_spec("differs=A1", items["A2"], items) == 1)
    check("differs same", eval_spec("differs=A1", items["A1"], items) == 0)
    check("missing item wrong", eval_spec("has=x", None, items) == 0)
    check("lint blank", lint_line("") is not None)
    check("lint why", lint_line("why is it") is not None)
    check("lint good alone", lint_line("good") is not None)
    check("lint good morning ok", lint_line("good morning") is None)
    check("lint quit", lint_line("quit now") is not None)
    check("lint /load", lint_line("/load x") is not None)
    check("lint /bad ok", lint_line("/bad") is None)
    rows = [{"id": "a", "block": "R", "episode": "E1", "text": "x", "line": 1},
            {"id": "-", "block": "R", "episode": "E1", "text": "/good", "line": 2},
            {"id": "b", "block": "R", "episode": "E2", "text": "y", "line": 3},
            {"id": "c", "block": "H", "episode": "E3", "text": "z", "line": 4}]
    check("perm deterministic", make_perm(rows, 7) == make_perm(rows, 7))
    check("perm keeps H last", make_perm(rows, 3)[-1] == "E3")
    s = build_stdin(rows, ["E2", "E1", "E3"])
    check("stdin layout", s == "/__e1_b\ny\n/__e1_a\nx\n/good\n/__e1_c\nz\n/__e1___end\n/__learning__\n/quit\n")
    sc = {1: {"i": 1}, 2: {"i": 1}, 3: {"i": 0}, 4: {"i": 0}, 5: {"i": 1}}
    check("majority 3 of 5", majority(sc, [1, 2, 3, 4, 5], "i") == 1)
    ok = all(c for _, c in checks)
    for name, c in checks:
        if not c:
            print("FAIL:", name)
    print("e1 selftest: %d checks -> %s" % (len(checks), "OK" if ok else "FAIL"))
    return 0 if ok else 1


# ---------------------------------------------------------------- main

def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--selftest", action="store_true")
    sub = ap.add_subparsers(dest="cmd")
    sub.add_parser("lint")
    p = sub.add_parser("perms")
    p.add_argument("--seeds", default="1,2,3,4,5")
    p = sub.add_parser("stdin")
    p.add_argument("--perm", type=int, required=True)
    p = sub.add_parser("refcheck")
    p.add_argument("--chat", required=True)
    p.add_argument("--jobs", type=int, default=4)
    p.add_argument("--show", action="store_true")
    p = sub.add_parser("run")
    p.add_argument("--chat", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--arms", default="")
    p.add_argument("--perms", default="")
    p.add_argument("--jobs", type=int, default=4)
    p.add_argument("--partial", action="store_true",
                   help="allow a subset of arms or perms (not the pre-registered study)")
    p = sub.add_parser("stats")
    p.add_argument("--out", required=True)
    args = ap.parse_args(argv)
    if args.selftest:
        return selftest()
    if args.cmd == "lint":
        errs = lint(load_replay(), load_gold(), load_perms(), load_arms())
        print("\n".join(errs) if errs else "lint: ok")
        return 1 if errs else 0
    if args.cmd == "perms":
        rows = load_replay()
        print("# E1 permutations: perm<TAB>seed<TAB>episode order (e1.py perms)")
        for k, s in enumerate(int(x) for x in args.seeds.split(",")):
            print("%d\t%d\t%s" % (k + 1, s, ",".join(make_perm(rows, s))))
        return 0
    if args.cmd == "stdin":
        sys.stdout.write(build_stdin(load_replay(), load_perms()[args.perm]["episodes"]))
        return 0
    if args.cmd == "refcheck":
        return cmd_refcheck(args)
    if args.cmd == "run":
        return cmd_run(args)
    if args.cmd == "stats":
        return cmd_stats(args)
    ap.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())
