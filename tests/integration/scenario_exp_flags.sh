#!/usr/bin/env bash
# Scenario exp-flags -- B2 (E1 ablation switches, all off by default).
#   1. CE_EXP_TRACE adds only `EXP {json}` lines: stripping them gives the
#      untraced output byte for byte, and every EXP line is valid JSON.
#   2. Each CE_ABL_* flag prints its banner and has observable evidence in
#      the trace or in /__learning__ (the switch is really wired).
#   3. A value other than "1" leaves a flag off.

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0
it_section "scenario exp-flags: ablation switches + per-turn trace"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

INPUT='fever
/good
fever
what causes headache
/bad
hello
what is fever
infection
/good
/__learning__
/quit'

# Same run dir path for every run so path-bearing lines match.
run() {
    rm -rf "$WORK/w"; mkdir -m 700 -p "$WORK/w"
    printf '%s\n' "$INPUT" | env HOME="$WORK/w" CE_RUN_DIR="$WORK/w" "$@" timeout 120 "$CHAT" 2>&1 | tr -d '\r'
}

field() {  # field <text> <key> -> space-separated values over EXP lines
    grep '^EXP ' <<<"$1" | sed 's/^EXP //' | python3 -c "
import sys, json
print(' '.join(str(json.loads(l)['$2']) for l in sys.stdin))"
}

BASE=$(run)
TRACED=$(run CE_EXP_TRACE=1)
assert_eq "$(grep -v '^EXP ' <<<"$TRACED")" "$BASE" "trace adds only EXP lines"
assert_eq "$(grep -c '^EXP ' <<<"$TRACED")" "6" "one EXP line per conversational turn"
assert_eq "$(field "$TRACED" nl)" "0 0 0 0 1 0" "NL-answered turn traced with nl=1"
assert_eq "$(field "$TRACED" turn)" "0 1 2 3 4 5" "turn counts traced turns"
JSON_OK=$(grep '^EXP ' <<<"$TRACED" | sed 's/^EXP //' | python3 -c '
import sys, json
keys = {"turn","session","nl","router","cache_hit","category","drain_steps","fired","modulator","pc_error","ops","trace","flags"}
rows = [json.loads(l) for l in sys.stdin]
print("ok" if rows and all(set(r) == keys for r in rows) else "bad")')
assert_eq "$JSON_OK" "ok" "EXP lines are JSON with the documented keys"
assert_match "$TRACED" '^EXP \{"turn":1,.*"cache_hit":1' "repeat query is a cache hit in the trace"
assert_nomatch "$BASE" "experiment: ablations" "no banner by default"

# SUBSTRATE: pools silent, clock still runs.
OUT=$(run CE_EXP_TRACE=1 CE_ABL_SUBSTRATE=1)
assert_match "$OUT" "^\(experiment: ablations on: substrate\)$" "substrate banner"
assert_eq "$(field "$OUT" fired)" "0 0 0 0 0 0" "substrate: no node fires"
assert_match "$(field "$TRACED" fired)" "[1-9]" "control: nodes fire without the flag"
assert_eq "$(grep -oE '^tick=[0-9]+' <<<"$OUT")" "$(grep -oE '^tick=[0-9]+' <<<"$BASE")" "substrate: clock still advances"

# PC: prediction error held at 0.
OUT=$(run CE_EXP_TRACE=1 CE_ABL_PC=1)
assert_eq "$(field "$OUT" pc_error)" "0 0 0 0 0 0" "pc: error held at 0"
assert_match "$(field "$TRACED" pc_error)" "[1-9]" "control: nonzero error without the flag"
# modulator / pc_error are the values the turn's tick used: turn 0 ticks with
# the initial 1000 / 0.
assert_eq "$(field "$TRACED" modulator | cut -d' ' -f1) $(field "$TRACED" pc_error | cut -d' ' -f1)" "1000 0" "trace: turn 0 reports the values its tick used"

# CACHE: never looked up or filled.
OUT=$(run CE_EXP_TRACE=1 CE_ABL_CACHE=1)
assert_eq "$(field "$OUT" cache_hit)" "0 0 0 0 0 0" "cache: no hits"
assert_match "$OUT" "^mc_entries=0$" "cache: nothing stored"

# FF: /good and /bad do not train the layer.
OUT=$(run CE_ABL_FF=1)
assert_nomatch "$(grep '^ff_goodness=' <<<"$OUT")" "^$(grep '^ff_goodness=' <<<"$BASE")$" "ff: goodness differs from the trained run"

# IA: prototypes never reinforced.
OUT=$(run CE_ABL_IA=1)
assert_match "$BASE" "^ia_proto_strength_" "control: ia prototype reinforced"
assert_nomatch "$OUT" "^ia_proto_strength_" "ia: no prototype reinforced"

# BETA: operator confidence not updated by /good, /bad.
OUT=$(run CE_ABL_BETA=1)
assert_match "$OUT" "^\(experiment: ablations on: beta\)$" "beta banner"
assert_eq "$([ "$(grep 'conf=' <<<"$OUT")" != "$(grep 'conf=' <<<"$BASE")" ] && echo differs)" "differs" "beta: reported confidence differs"

# SYNW: flag listed in the trace; weights no longer compile shortcut
# operators (scoring is unit-tested).
OUT=$(run CE_EXP_TRACE=1 CE_ABL_SYNW=1)
assert_eq "$(field "$OUT" flags | tr ' ' '\n' | sort -u)" "synw" "synw listed in every EXP line"
CC_INPUT='what causes headache
/good
/good
/good
/good
/good
/good
/__compiled__
/quit'
cc_run() {
    rm -rf "$WORK/w"; mkdir -m 700 -p "$WORK/w"
    printf '%s\n' "$CC_INPUT" | env HOME="$WORK/w" CE_RUN_DIR="$WORK/w" "$@" timeout 120 "$CHAT" 2>&1 | tr -d '\r'
}
assert_match "$(cc_run)" "compiled_count=[1-9]" "control: six /good compile a shortcut"
assert_match "$(cc_run CE_ABL_SYNW=1)" "compiled_count=0" "synw: no weight-gated compilation"

# Only "1" turns a flag on.
OUT=$(run CE_ABL_CACHE=true CE_ABL_FF=0)
assert_eq "$OUT" "$BASE" "values other than 1 leave flags off"

summary "scenario_exp_flags"
