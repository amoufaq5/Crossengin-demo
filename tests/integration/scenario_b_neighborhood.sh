#!/usr/bin/env bash
# Scenario B -- Neighborhood paraphrase.
#
# Boot fresh -> ask "fever" -> verify the reasoning surfaces a related
# concept from the structural neighborhood (infection / treat / headache /
# recover) in the agent's reply OR via /reflect's tentative inferences.
#
# The seed wires fever -> infection -> treat (xrefs) and fever -> headache,
# headache -> pain, infection -> symptom (operators). On a bare "fever"
# percept, the agent should NOT just say "okay" -- it should derive a
# neighbour and speak it.

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0

it_section "scenario B: neighborhood paraphrase on 'fever'"

# Pipe "fever" into a fresh chat. Capture the agent line plus /reflect output.
OUT=$(run_chat 'fever
/reflect')

# 1. Comprehension: at least one matched concept, no unknown tokens
#    (the seed knows "fever").
assert_match "$OUT" "perceive\\(m=[1-9][0-9]*,unk=0\\)" "fever fully comprehended"

# 2. The agent's spoken intent should be either ack ("okay") or a derived
#    concept word from the neighborhood. We require a NON-empty reply line.
assert_match "$OUT" "agent> [^[]" "agent produced a non-error reply (not [refused]/[silent])"

# 3. The neighborhood vocabulary -- infection / treat / headache / recover /
#    symptom / pain / virus -- should surface either as the agent's spoken
#    word OR as a /reflect tentative inference. We grep across the full
#    transcript.
NEIGH_RE='infection|treat|headache|recover|symptom|pain|virus|medicine|doctor|rest'
assert_match "$OUT" "$NEIGH_RE" "a neighborhood concept surfaces (agent reply or /reflect)"

# 4. /reflect should report the simulation count even with no new inferences.
assert_match "$OUT" "reflected on [1-9][0-9]* concept" "/reflect reports concept count"

summary "scenario_b_neighborhood"
