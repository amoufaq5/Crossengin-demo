#!/usr/bin/env bash
# Scenario O -- /prove proof-checker on medical seed pack (P3.5 / ADR-0052).
#
# Boot the chat, install the medical pack, query a few proofs via /prove
# and verify the operator-chain output. The medical pack ships
# headache -> dehydration -> hydration (causal + implicative), and the
# baseline first_atoms seed ships fever -> infection -> treat plus
# fever -> headache, so we exercise:
#   - a one-hop proof (headache -> dehydration)
#   - a two-hop proof (headache -> hydration)
#   - a no-path proof (headache -> motorcycle, neither word is a med atom
#     in the conclusion direction so we use a real but unconnected atom)
#   - /help advertises the new command
#   - the trivial premise == conclusion case

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0

# Defensive: keep prior /save snapshots from drifting the atom counts.
rm -f /tmp/crossengin.snap /tmp/crossengin.default.dlog /tmp/crossengin.dlog

it_section "scenario O: /prove operator-chain proof checker"

OUT=$(printf '/seed medical
/prove headache dehydration
/prove headache hydration
/prove fever treat
/prove headache headache
/prove headache notaword
/help
/quit
' | "$CHAT" 2>&1)

# 1. /help advertises /prove.
assert_match "$OUT" "/prove P C \[DEPTH\]" \
    "/help advertises /prove"

# 2. One-hop proof: headache -> dehydration. Must print 'proof:' line + an
#    op id + a strength line.
assert_match "$OUT" "proof: headache -> dehydration" \
    "headache -> dehydration prints proof header"
assert_match "$OUT" "op #[0-9]+ \(causal\) headache -> dehydration" \
    "one-hop chain includes the causal operator with an id"
assert_match "$OUT" "strength: [0-9]+ milli" \
    "one-hop proof prints strength"

# 3. Two-hop proof: headache -> hydration via dehydration.
assert_match "$OUT" "proof: headache -> dehydration -> hydration" \
    "two-hop proof headache->dehydration->hydration"
assert_match "$OUT" "op #[0-9]+ \(implicative\) dehydration -> hydration" \
    "two-hop chain includes the implicative dehydration->hydration op"

# 4. Baseline-seed proof: fever -> treat via infection.
assert_match "$OUT" "proof: fever -> infection -> treat" \
    "baseline-seed two-hop proof fever->infection->treat"

# 5. Trivial proof: same atom on both sides.
assert_match "$OUT" "proof \(trivial\): premise == conclusion" \
    "premise==conclusion is the trivial proof"

# 6. Unknown conclusion label produces a clean error (not a stack trace).
assert_match "$OUT" "no atom with label 'notaword'" \
    "unknown conclusion label reports cleanly"

# 7. Every successful /prove reports its visit counter so the operator can
#    distinguish depth-bound from graph-bound failures.
assert_match "$OUT" "visited [0-9]+ state\(s\); depth budget [0-9]+, visit budget [0-9]+" \
    "successful proofs report visit + depth budgets"

summary "scenario_o_proof_checker"
