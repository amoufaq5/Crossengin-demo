#!/usr/bin/env bash
# Admin commands -- /reflect, /halt, /resume.

. "$(dirname "$0")/_lib.sh"
require_chat

PASS=0; FAIL=0

# -------------------- /reflect with empty context --------------------
it_section "admin: /reflect with no recent message"

OUT=$(run_chat '/reflect')
assert_match "$OUT" "nothing recent to reflect on" "/reflect with empty context prints empty-context message"

# -------------------- /reflect after a non-trivial input --------------------
it_section "admin: /reflect after a message"

OUT=$(run_chat 'fever
/reflect')
assert_match "$OUT" "reflected on [0-9]+ concept" "/reflect prints concept count"
# Depth-default (4) may produce zero or more tentative inferences; we just
# assert that the format is one of the two valid shapes.
assert_match "$OUT" "(tentative inference|no new inferences)" "/reflect prints either tentatives or a no-new line"

# -------------------- /reflect with explicit depth --------------------
it_section "admin: /reflect depth=4"

OUT=$(run_chat 'fever
/reflect 4')
assert_match "$OUT" "reflected on [0-9]+ concept" "/reflect 4 prints concept count"

# Deeper depth should reach >= same number of tentative inferences as default
# (depth 4 is the default). With depth 6 there should typically be at least
# one tentative inference on the seeded fever -> infection chain.
OUT=$(run_chat 'fever
/reflect 6')
assert_match "$OUT" "reflected on [0-9]+ concept" "/reflect 6 prints concept count"

# -------------------- /halt then send then /resume --------------------
it_section "admin: /halt and /resume"

OUT=$(run_chat '/halt
fever
/resume
fever')

# halted -> effector drains silently. The chat shows "agent> [silent]" or
# something matching the effector's empty-output marker. The spec calls
# this the "drains silently" path.
assert_match "$OUT" "\\(halted -- effector will drain" "/halt prints halt notice"
assert_match "$OUT" "agent> \\[silent\\]" "halted turn emits [silent] (no spoken reply)"
assert_match "$OUT" "\\(resumed\\)" "/resume prints resume notice"
# After resume, the next fever message should produce a normal (non-silent)
# reply, either a derived word or 'okay'. We slice everything after the
# (resumed) line and look for an agent> line that is NOT [silent]/[refused].
RESUMED_LINES=$(printf '%s\n' "$OUT" | sed -n '/(resumed)/,$p')
RESUMED_REPLY=$(printf '%s\n' "$RESUMED_LINES" | grep -E 'agent>' | tail -1)
if echo "$RESUMED_REPLY" | grep -qE 'agent> [^[]'; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  post-resume turn speaks (got '%s')\n" "$RESUMED_REPLY"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  post-resume turn did not speak (got '%s')\n" "${RESUMED_REPLY:-<none>}"
fi

summary "admin_reflect_halt"
