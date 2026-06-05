#!/usr/bin/env bash
# Scenario BB -- /why-deep [N] recursive decision tree.
#
# Boot the chat, teach a word (`/teach widget`), ask it back, then run
# /why-deep 3 and verify the output has:
#   - a "decision #N speak ..." header
#   - a "proof:" line (operator chain header, or "(no operator chain found)")
#   - an "activated by:" line surfacing the activating user message
#   - an "upstream evidence:" section listing per-atom belief means + source
#   - the /help listing advertises /why-deep
#
# The /why-deep command is built on top of P3.5's proof_checker.nova: it runs
# proof_check() with max_depth=N (capped at 8) between each perceived percept
# atom and each conclusion atom, then renders the per-op chain via
# proof_format().

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0

# Defensive: keep prior /save snapshots from drifting the atom counts.
rm -f /tmp/crossengin.snap /tmp/crossengin.default.dlog /tmp/crossengin.dlog

it_section "scenario BB: /why-deep recursive decision tree"

# Static-source guard: /why-deep should be in the chat surface. (We grep the
# file directly instead of piping the ~120 KB chat source through grep -q,
# because grep -q stops reading early -- which under `set -o pipefail`
# fails the upstream `echo` with SIGPIPE and confuses assert_match.)
CHAT_SRC_PATH="$REPO_ROOT/examples/crossengin_chat.nova"
if grep -q '_admin_why_deep' "$CHAT_SRC_PATH"; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  chat source defines _admin_why_deep\n"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  chat source defines _admin_why_deep\n"
fi
if grep -q '/why-deep' "$CHAT_SRC_PATH"; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  chat dispatcher lists /why-deep\n"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  chat dispatcher lists /why-deep\n"
fi
if grep -qE 'proof_check\(' "$CHAT_SRC_PATH"; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  chat /why-deep calls proof_check from proof_checker.nova\n"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  chat /why-deep calls proof_check from proof_checker.nova\n"
fi

# Teach a widget concept, ask back, then /why-deep 3.
OUT=$(printf '/teach widget
widget
/why-deep 3
/help
/quit
' | "$CHAT" 2>&1)

# Header line: decision #N speak ... outcome=ok tier=notify
assert_match "$OUT" "decision #[0-9]+ speak " \
    "/why-deep prints a decision header line"
assert_match "$OUT" "tier=notify" \
    "/why-deep decision header reports tier"
assert_match "$OUT" "outcome=ok" \
    "/why-deep decision header reports outcome"

# proof: line -- either the operator-chain header from proof_format or the
# fallback "(no operator chain found...)" when widget is the only percept.
assert_match "$OUT" "proof:" \
    "/why-deep prints a proof: line"

# activated by: line surfacing the user message that drove the turn.
assert_match "$OUT" "activated by: msg \"widget\" perceive\(m=[0-9]+\)" \
    "/why-deep prints activated by: msg \"widget\" perceive(...)"

# upstream evidence section: per-atom belief + source provenance.
assert_match "$OUT" "upstream evidence:" \
    "/why-deep prints upstream evidence: header"
assert_match "$OUT" "atom 'widget' belief mean=[0-9]+, source='user_taught'" \
    "/why-deep upstream evidence lists widget atom with user_taught provenance"

# /help advertises /why-deep.
assert_match "$OUT" "/why-deep \[N\]" \
    "/help advertises /why-deep [N]"

# Now exercise a path that yields a real operator chain: fever has known
# operators in the seed (fever -> infection -> treat / fever -> headache).
OUT2=$(printf 'fever
/why-deep 3
/quit
' | "$CHAT" 2>&1)
assert_match "$OUT2" "proof: fever ->" \
    "/why-deep on \"fever\" surfaces an operator chain starting at fever"
assert_match "$OUT2" "op #[0-9]+ \(causal\) fever ->" \
    "/why-deep emits per-op line tagged (causal) for fever"

# Save a sample of the output for the report.
SAMPLE_PATH=/tmp/ce_int_why_deep_sample_$$.txt
echo "$OUT" > "$SAMPLE_PATH"
printf "  ${C_DIM}-- /why-deep teach+widget sample --${C_RST}\n"
sed 's/^/        /' "$SAMPLE_PATH"

rm -f "$SAMPLE_PATH"
summary "scenario_bb_why_deep"
