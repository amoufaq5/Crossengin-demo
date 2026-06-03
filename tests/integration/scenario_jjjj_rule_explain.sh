#!/usr/bin/env bash
# Scenario JJJJ -- recursive provenance walks + proof-tree rendering (R22E).
#
# Companion to scenario_aaaa_rule_inference.sh (R20B forward chaining) and
# scenario_eeee_distributed_rules.sh (R21B distributed Datalog). R22E ships
# the missing piece: recursive walks over R20B's provenance table that
# follow derived-from-derived chains all the way to ground facts and
# render the result as an indented text tree + structured nested list.
#
# This scenario drives a stand-alone driver under
# tests/integration/_scenario_jjjj_rule_explain_driver/ which:
#   1. Builds a 5-parent chain (parent(0,1)..parent(4,5)).
#   2. Runs the classical transitive ancestor rules to fixpoint.
#   3. Explains ancestor(0,4): asserts height >= 4, ground facts list,
#      and the presence of the rule head pred + intermediate atom IDs
#      in the rendered text.
#   4. Explains a ground parent fact: asserts the leaf is GROUND with
#      height 1.
#   5. Explains a missing atom_id: asserts the MISSING sentinel.
#
# The scenario then verifies the chat dispatch path:
#   - /explain on an unknown atom_id reports a graceful error.
#   - /help lists /explain.
#
# Total assertions: ~12.

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

NOVA_ROOT="${NOVA_ROOT:-$HOME/NOVA}"
NOVA="$NOVA_ROOT/nova"

it_section "scenario JJJJ: recursive provenance walks + /explain (R22E)"

# --- guard: NOVA toolchain available -----------------------------------
if [ ! -x "$NOVA" ]; then
    FAIL=$((FAIL+1))
    echo "FAIL: NOVA launcher not found at '$NOVA'"
    summary "scenario_jjjj_rule_explain"
    exit 1
fi

# --- step 1: write + run the inline driver -----------------------------
DRIVER_DIR="$REPO_ROOT/tests/integration/_scenario_jjjj_rule_explain_driver"
mkdir -p "$DRIVER_DIR"
DRIVER="$DRIVER_DIR/rule_explain_driver.nova"

cat > "$DRIVER" <<'EOF'
// Driver for scenario_jjjj_rule_explain.sh.
//
// Seeds a 5-parent chain, runs forward chaining to fixpoint, then walks
// the provenance for ancestor(0,4), a ground parent fact, and a missing
// atom. Prints a sequence of DRIVER lines for the shell to assert.

import "std/syscall"
import "std/string"
import "std/io"
import "../../../src/kg/atom_store.nova"
import "../../../src/kg/multi_kg_manager.nova"
import "../../../src/kg/rule_inference.nova"
import "../../../src/kg/rule_explain.nova"

fn main() {
    // Seed a chain of 5 parent relationships: parent(0,1)..parent(4,5).
    let reg = kg_registry_new()
    let kg = kg_spawn(reg, "explain_test")
    let i = 0
    while i < 5 {
        let label = "parent|" + int_to_str(i) + "|" + int_to_str(i + 1)
        kg_add_atom(kg, ATOM_RELATION, label, 0)
        i = i + 1
    }
    io_println("DRIVER initial_facts=" + int_to_str(kg_atom_count(kg)))

    // Build the rule engine with the standard ancestor rules and run to
    // fixpoint.
    let e = rule_engine_new()
    rule_engine_add(e, "RULE ancestor(?a, ?b) <- parent(?a, ?b)")
    rule_engine_add(e, "RULE ancestor(?a, ?c) <- ancestor(?a, ?b), parent(?b, ?c)")
    let r = rule_engine_run(e, kg, 100)
    io_println("DRIVER derived=" + int_to_str(r[1]))
    io_println("DRIVER iterations=" + int_to_str(r[2]))

    // Locate ancestor(0,4): the brief's "ancestor(0, 4) for 5-link
    // transitive chain has 4 levels in proof tree" target.
    let a04_atom = kg_find_atom(kg, "ancestor|0|4")
    let a04_id = atom_id(a04_atom)
    io_println("DRIVER ancestor_0_4_id=" + int_to_str(a04_id))

    // Explain it and print summary tokens.
    let tree04 = explain_atom(kg, e, a04_id)
    io_println("DRIVER tree04_height=" + int_to_str(proof_height(tree04)))
    io_println("DRIVER tree04_nodes=" + int_to_str(proof_node_count(tree04)))
    io_println("DRIVER tree04_grounds=" + int_to_str(len(proof_ground_facts(tree04))))
    io_println("DRIVER tree04_root_rule=" + proof_rule_name(tree04))
    io_println("DRIVER tree04_root_label=" + proof_label(tree04))

    // Print the indented text rendering.
    io_println("DRIVER tree04_text_begin")
    let txt = proof_render_text(tree04, 50)
    io_println(txt)
    io_println("DRIVER tree04_text_end")

    // Explain a ground parent fact: should be height 1, GROUND.
    let p01_atom = kg_find_atom(kg, "parent|0|1")
    let p01_id = atom_id(p01_atom)
    let tree_p = explain_atom(kg, e, p01_id)
    io_println("DRIVER ground_p01_height=" + int_to_str(proof_height(tree_p)))
    io_println("DRIVER ground_p01_is_ground=" + int_to_str(proof_is_ground(tree_p)))
    io_println("DRIVER ground_p01_rule_name=" + proof_rule_name(tree_p))

    // Explain a missing atom_id (999 won't exist).
    let tree_m = explain_atom(kg, e, 999)
    io_println("DRIVER missing_rule_name=" + proof_rule_name(tree_m))
    io_println("DRIVER missing_is_truncated=" + int_to_str(proof_is_truncated(tree_m)))

    // Drive the chat dispatch path: missing-atom rejection should land
    // on the engine-explicit form (since rule_inference's chat engine
    // is private, our chat command uses _explain_chat_engine; that
    // engine has no rules pre-loaded so /explain on a derived atom
    // would be a ground fact, not a recursive walk -- but the
    // explain_cmd_with_engine variant accepts our explicit engine).
    explain_cmd_with_engine(kg, e, int_to_str(a04_id))
    // Also exercise the chat-engine surface so the chat command's
    // error-path emit lands in the output.
    explain_chat_cmd(kg, "999")

    // Verify the structured render is well-formed (4-tuple shape).
    let s = proof_render_structured(tree04)
    io_println("DRIVER struct04_len=" + int_to_str(len(s)))
    io_println("DRIVER struct04_atom_id=" + int_to_str(s[0]))
    io_println("DRIVER struct04_rule_idx=" + int_to_str(s[2]))
    io_println("DRIVER struct04_kids=" + int_to_str(len(s[3])))
}

main()
EOF

OUT="$("$NOVA" run "$DRIVER" 2>&1)"
RC=$?
echo "$OUT" | sed 's/^/    /'
assert_eq "$RC" "0" "rule_explain driver exits 0"

# --- step 2: basic setup ----------------------------------------------------
INIT=$(echo "$OUT" | grep -E '^DRIVER initial_facts=' | head -1 | cut -d= -f2)
DERIVED=$(echo "$OUT" | grep -E '^DRIVER derived=' | head -1 | cut -d= -f2)
assert_eq "$INIT" "5" "5 initial parent facts seeded"
assert_match "$OUT" "DRIVER derived=15" "fixpoint derives 15 ancestor atoms"

# --- step 3: ancestor(0,4) proof shape -------------------------------------
HEIGHT04=$(echo "$OUT" | grep -E '^DRIVER tree04_height=' | head -1 | cut -d= -f2)
NODES04=$(echo "$OUT" | grep -E '^DRIVER tree04_nodes=' | head -1 | cut -d= -f2)
GROUNDS04=$(echo "$OUT" | grep -E '^DRIVER tree04_grounds=' | head -1 | cut -d= -f2)
ROOT_RULE=$(echo "$OUT" | grep -E '^DRIVER tree04_root_rule=' | head -1 | cut -d= -f2)
ROOT_LABEL=$(echo "$OUT" | grep -E '^DRIVER tree04_root_label=' | head -1 | cut -d= -f2)
if [ -n "$HEIGHT04" ] && [ "$HEIGHT04" -ge 4 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  ancestor(0,4) proof tree height >= 4 (got %s)\n" "$HEIGHT04"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  ancestor(0,4) proof tree height should be >= 4 (got %s)\n" "$HEIGHT04"
fi
assert_eq "$GROUNDS04" "4" "ancestor(0,4) ground-fact leaves count to 4"
assert_eq "$ROOT_RULE" "ancestor" "ancestor(0,4) root rule name is 'ancestor'"
assert_eq "$ROOT_LABEL" "ancestor|0|4" "ancestor(0,4) root label preserved"

# --- step 4: text render contains rule names + atom IDs ---------------------
# The text body for ancestor(0,4)'s walk must contain the via/GROUND tokens
# and the chain of ancestor labels.
assert_match "$OUT" "ancestor\|0\|4\" via ancestor" \
    "text render names ancestor rule at root"
assert_match "$OUT" "parent\|0\|1\" GROUND" \
    "text render bottoms out at parent(0,1) ground fact"
assert_match "$OUT" "parent\|3\|4\" GROUND" \
    "text render mentions parent(3,4) ground fact"

# --- step 5: ground-fact explain --------------------------------------------
GP_HEIGHT=$(echo "$OUT" | grep -E '^DRIVER ground_p01_height=' | head -1 | cut -d= -f2)
GP_IS_GROUND=$(echo "$OUT" | grep -E '^DRIVER ground_p01_is_ground=' | head -1 | cut -d= -f2)
GP_RULE=$(echo "$OUT" | grep -E '^DRIVER ground_p01_rule_name=' | head -1 | cut -d= -f2)
assert_eq "$GP_HEIGHT" "1" "ground parent(0,1) explain has height 1"
assert_eq "$GP_IS_GROUND" "1" "ground parent(0,1) explain marked ground"
assert_eq "$GP_RULE" "GROUND" "ground parent(0,1) rule name is GROUND"

# --- step 6: missing atom graceful error -----------------------------------
MISSING_RULE=$(echo "$OUT" | grep -E '^DRIVER missing_rule_name=' | head -1 | cut -d= -f2)
assert_eq "$MISSING_RULE" "MISSING" "missing atom_id resolves to MISSING sentinel"

# --- step 7: chat-dispatch emit lines --------------------------------------
# explain_cmd_with_engine on the existing derived atom_id emits an
# EXPLAIN line.
assert_match "$OUT" "EXPLAIN atom=" "EXPLAIN emit line lands"
assert_match "$OUT" "height=" "EXPLAIN summary mentions height"
# explain_chat_cmd on the missing atom 999 lands an "atom 999 not in KG" line.
assert_match "$OUT" "EXPLAIN error=atom 999 not in KG" \
    "/explain on missing atom emits graceful error"

# --- step 8: structured rendering ------------------------------------------
STRUCT_LEN=$(echo "$OUT" | grep -E '^DRIVER struct04_len=' | head -1 | cut -d= -f2)
STRUCT_KIDS=$(echo "$OUT" | grep -E '^DRIVER struct04_kids=' | head -1 | cut -d= -f2)
assert_eq "$STRUCT_LEN" "4" "proof_render_structured returns 4-tuple"
assert_eq "$STRUCT_KIDS" "2" "ancestor(0,4) root has 2 children (chained rule)"

# --- step 9: /help lists /explain (chat-binary path) -----------------------
if [ -x "$CHAT" ]; then
    HELP_OUT=$(run_chat '/help')
    assert_match "$HELP_OUT" "/explain" "/help lists /explain"
    CHAT_OUT=$(run_chat '/explain')
    assert_match "$CHAT_OUT" "usage: /explain" "/explain with no arg prints usage"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  CHAT binary not built at %s\n" "$CHAT"
fi

summary "scenario_jjjj_rule_explain"
