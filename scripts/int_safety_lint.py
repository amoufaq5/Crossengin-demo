#!/usr/bin/env python3
# int_safety_lint.py -- guard against NOVA codegen bug #11 (P0, ADR-0066).
#
# NOVA's "smart-op" dispatch treats any operand >= 0x100000 (1048576) as a heap
# pointer and misroutes the operation into string-concat / list code, producing
# wrong results or a SIGSEGV (see NOVA/NOVA_BUG_THRESHOLD.md). Per that doc's
# authoritative table, EXACTLY EIGHT operators are smart-dispatched and thus
# affected: + * < > <= >= == != . The bitwise ops (& | ^ ~ << >>) and - / %
# are pure scalar and are NOT affected. The fix is the int_* escape-hatch
# builtins (int_mul/int_add/...). This linter makes the otherwise-invisible
# landmine a CI gate.
#
# Precision: it flags the dominant, statically-detectable, high-signal case -- a
# large *literal* that is a RAW operand of multiplication `*` (the LCG-multiplier
# / byte-packing / accumulator class behind 5 of the 6 historical incidents),
# outside an int_* call. It cannot see large values carried only in VARIABLES,
# nor the rarer two-large-operand `+`/comparison case (that needs range analysis
# / both-operand inspection); those remain covered by the int_* coding standard
# under review. `*` is chosen because multiplication is the operator that most
# readily lifts a value across the threshold, and it gives zero false positives
# across the current 126k-LOC tree.
#
# A reviewed-safe occurrence is silenced with a trailing `// int-safe` comment.
# Exit status: 0 if clean, 1 if any unannotated finding (so `make lint-ints`
# fails loudly). Pure static text analysis -- no NOVA toolchain needed.
#
# Usage: python3 scripts/int_safety_lint.py [root]   (default root: src)

import os, re, sys

THRESHOLD = 0x100000  # 1048576
# Danger operator: raw multiplication. `*` is smart-dispatched (affected) AND is
# the operator that most readily co-occurs with a large other operand (LCG
# multiplier, byte packing, accumulators). + and the comparisons are also smart-
# dispatched but a SINGLE large literal there usually pairs with a small operand
# (safe), so they are not flagged to keep zero false positives; the two-large
# case is covered by the int_* coding standard under review (see ADR-0066).
DANGER = ['*']
INT_BUILTIN = re.compile(r'int_(mul|add|sub|div|mod|shl|shr|and|or|xor|neg)\s*$')
NUM = re.compile(r'0[xX][0-9a-fA-F]+|\d+')


def strip_code(line):
    """Return (code_without_strings_and_comments, had_int_safe_marker)."""
    int_safe = 'int-safe' in line
    out, i, n = [], 0, len(line)
    in_str = False
    while i < n:
        c = line[i]
        if in_str:
            if c == '\\' and i + 1 < n:
                out.append('  '); i += 2; continue
            if c == '"':
                in_str = False; out.append(' '); i += 1; continue
            out.append(' '); i += 1; continue
        if c == '"':
            in_str = True; out.append(' '); i += 1; continue
        if c == '/' and i + 1 < n and line[i + 1] == '/':
            break  # line comment -> rest is not code
        out.append(c); i += 1
    return ''.join(out), int_safe


def value_of(tok):
    try:
        return int(tok, 16) if tok.lower().startswith('0x') else int(tok)
    except ValueError:
        return -1


def enclosing_call_is_int(code, start):
    """True if the literal at index `start` sits inside an int_*( ... ) call."""
    depth = 0
    i = start - 1
    while i >= 0:
        c = code[i]
        if c == ')':
            depth += 1
        elif c == '(':
            if depth == 0:
                # identifier immediately before this '('
                return bool(INT_BUILTIN.search(code[:i]))
            depth -= 1
        i -= 1
    return False


def adjacent_danger_op(code, start, end):
    """True if a danger operator touches the literal token [start,end)."""
    # look left (skip spaces)
    j = start - 1
    while j >= 0 and code[j] == ' ':
        j -= 1
    left2 = code[max(0, j - 1):j + 1]
    left1 = code[j] if j >= 0 else ''
    # look right (skip spaces)
    k = end
    while k < len(code) and code[k] == ' ':
        k += 1
    right2 = code[k:k + 2]
    right1 = code[k] if k < len(code) else ''
    for op in DANGER:
        if len(op) == 2:
            if left2 == op or right2 == op:
                return op
        else:
            # avoid mis-reading part of a 2-char op (<<,>>) as < or >
            if left1 == op and left2 not in ('<<', '>>'):
                return op
            if right1 == op and right2 not in ('<<', '>>'):
                return op
    return None


# A comparison against a NEGATIVE literal: `x == 0 - 1`, `x != 0 - 7`. In two's
# complement a negative is 0xFFFF...  >= 0x100000, so `==`/`!=` against it is a
# two-large-operand compare whenever the other side is also large (a pointer or
# a negative value) -> bug #11, ASLR-flaky (see ADR-0073). Use `< 0` (one small
# operand) or int_xor instead. Catches the literal form; named negative-sentinel
# constants (e.g. `== SOME_ERR` where SOME_ERR = 0 - 1) are a documented lint
# blind spot covered by the `< 0` coding standard under review.
NEG_CMP = re.compile(r'(==|!=)\s*0\s*-\s*\d')


def scan_file(path):
    findings = []
    with open(path, 'r', errors='replace') as f:
        for lineno, raw in enumerate(f, 1):
            code, int_safe = strip_code(raw.rstrip('\n'))
            if int_safe:
                continue
            if NEG_CMP.search(code):
                findings.append((lineno, '== neg', '0 - N',
                                 raw.strip()))
            for m in NUM.finditer(code):
                if value_of(m.group(0)) < THRESHOLD:
                    continue
                s, e = m.start(), m.end()
                if enclosing_call_is_int(code, s):
                    continue
                op = adjacent_danger_op(code, s, e)
                if op:
                    findings.append((lineno, op, m.group(0), raw.strip()))
    return findings


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else 'src'
    total = 0
    print("=== int-safety lint (NOVA codegen bug #11 guard) ===")
    for dirpath, _, files in os.walk(root):
        for fn in sorted(files):
            if not fn.endswith('.nova'):
                continue
            p = os.path.join(dirpath, fn)
            for (lineno, op, lit, text) in scan_file(p):
                total += 1
                if op == '== neg':
                    print(f"  {p}:{lineno}: comparison against a negative literal "
                          f"(bug #11 risk; use `< 0` or int_xor, or annotate // int-safe)")
                else:
                    print(f"  {p}:{lineno}: large literal {lit} is a raw '{op}' "
                          f"operand (bug #11 risk; use int_* or annotate // int-safe)")
                print(f"      {text}")
    print("-" * 40)
    if total == 0:
        print("int-safety: clean -- no unguarded large-literal arithmetic.")
        return 0
    print(f"int-safety: {total} finding(s) need int_* or an audited // int-safe.")
    return 1


if __name__ == '__main__':
    sys.exit(main())
