#!/usr/bin/env bash
# Scenario AAAA -- forward-chaining rule inference over the KG (R20B).
#
# Companion to scenario_kkk_query.sh (R15D mini-SPARQL declarative
# query), scenario_ttt_link_prediction.sh (R18B link prediction),
# scenario_xxx_temporal.sh (R19C Allen temporal reasoning). R20B
# ships the missing DECLARATIVE INFERENCE surface: substrate-internal
# Datalog-style rules that derive new facts from existing ones by
# iterating to fixpoint.
#
# This scenario drives a stand-alone driver under
# tests/integration/_scenario_aaaa_rule_inference_driver/ which:
#   1. Seeds a KG with 5 parent relationships forming a chain
#      (parent(0,1), parent(1,2), ..., parent(4,5)).
#   2. Adds the two classical ancestor rules.
#   3. Runs forward chaining to fixpoint.
#   4. Asserts the derived ancestor count, iteration count, and
#      fixpoint termination flag.
#   5. Also runs a cycle-prevention rule to verify it terminates
#      without runaway.
#   6. Inspects provenance for one derived atom.
#
# The scenario then verifies the chat dispatch path:
#   - /rule_add lands a parse-success line;
#   - /rule_run reports (rules=R derived=D iterations=I);
#   - /help mentions /rule_add and /rule_run.
#
# Total assertions: ~12.

. "$(dirname "$0")/_lib.sh"

PASS=0; FAIL=0

NOVA_ROOT="${NOVA_ROOT:-$HOME/NOVA}"
NOVA="$NOVA_ROOT/nova"

it_section "scenario AAAA: forward-chaining rule inference + /rule_add /rule_run"

# --- guard: NOVA toolchain available -----------------------------------
if [ ! -x "$NOVA" ]; then
    FAIL=$((FAIL+1))
    echo "FAIL: NOVA launcher not found at '$NOVA'"
    summary "scenario_aaaa_rule_inference"
    exit 1
fi

# --- step 1: write + run the inline driver -----------------------------
DRIVER_DIR="$REPO_ROOT/tests/integration/_scenario_aaaa_rule_inference_driver"
mkdir -p "$DRIVER_DIR"
DRIVER="$DRIVER_DIR/rule_inference_driver.nova"

cat > "$DRIVER" <<'EOF'
// Driver for scenario_aaaa_rule_inference.sh.
//
// Seeds a 5-parent chain, runs forward chaining, and prints a sequence
// of DRIVER lines for the shell to assert against.

import "std/syscall"
import "std/string"
import "std/io"
import "../../../src/kg/atom_store.nova"
import "../../../src/kg/multi_kg_manager.nova"
import "../../../src/kg/rule_inference.nova"

fn main() {
    // Seed a chain of 5 parent relationships: parent(0,1)..parent(4,5).
    let reg = kg_registry_new()
    let kg = kg_spawn(reg, "rule_test")
    let i = 0
    while i < 5 {
        let label = "parent|" + int_to_str(i) + "|" + int_to_str(i + 1)
        kg_add_atom(kg, ATOM_RELATION, label, 0)
        i = i + 1
    }
    let pre_count = kg_atom_count(kg)
    io_println("DRIVER initial_facts=" + int_to_str(pre_count))

    // Build engine + add 2 transitive ancestor rules.
    let e = rule_engine_new()
    rule_engine_add(e, "RULE ancestor(?a, ?b) <- parent(?a, ?b)")
    rule_engine_add(e, "RULE ancestor(?a, ?c) <- ancestor(?a, ?b), parent(?b, ?c)")
    io_println("DRIVER rule_count=" + int_to_str(rule_engine_size(e)))

    // Run to fixpoint.
    let result = rule_engine_run(e, kg, 100)
    let derived = result[1]
    let iters   = result[2]
    let hit_cap = rule_engine_hit_cap(e)
    io_println("DRIVER derived=" + int_to_str(derived))
    io_println("DRIVER iterations=" + int_to_str(iters))
    io_println("DRIVER hit_cap=" + int_to_str(hit_cap))

    // Count ancestor atoms by scanning labels with prefix "ancestor|".
    let atoms = kg_atoms(kg)
    let n_ancestors = 0
    let j = 0
    while j < len(atoms) {
        let a = atoms[j]
        if a != 0 {
            if atom_kind(a) == ATOM_RELATION {
                let label = atom_label(a)
                if len(label) >= 9 {
                    if char_at(label, 0) == 97 {
                        if char_at(label, 1) == 110 {
                            if char_at(label, 2) == 99 {
                                if char_at(label, 3) == 101 {
                                    if char_at(label, 4) == 115 {
                                        if char_at(label, 5) == 116 {
                                            if char_at(label, 6) == 111 {
                                                if char_at(label, 7) == 114 {
                                                    if char_at(label, 8) == 124 {
                                                        n_ancestors = n_ancestors + 1
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        j = j + 1
    }
    io_println("DRIVER ancestor_count=" + int_to_str(n_ancestors))

    // Cycle prevention test: re-init, seed one foo fact, add a self-rule.
    let kg2 = kg_spawn(reg, "rule_cycle_test")
    kg_add_atom(kg2, ATOM_RELATION, "foo|x|y", 0)
    let e2 = rule_engine_new()
    rule_engine_add(e2, "RULE foo(?a, ?b) <- foo(?a, ?b)")
    let r2 = rule_engine_run(e2, kg2, 50)
    io_println("DRIVER cycle_derived=" + int_to_str(r2[1]))
    io_println("DRIVER cycle_iterations=" + int_to_str(r2[2]))
    io_println("DRIVER cycle_hit_cap=" + int_to_str(rule_engine_hit_cap(e2)))

    // Idempotency: run #1 derives N; run #2 must derive 0.
    let r_again = rule_engine_run(e, kg, 100)
    io_println("DRIVER rerun_derived=" + int_to_str(r_again[1]))

    // Provenance: the first derived ancestor atom is at id=pre_count.
    // (atoms are added in declaration order; the 5 parents take ids 0..4.)
    let first_derived = pre_count
    let prov = rule_engine_explain(e, first_derived)
    io_println("DRIVER prov_entries=" + int_to_str(len(prov)))
    if len(prov) > 0 {
        io_println("DRIVER prov_rule_idx=" + int_to_str(prov[0][1]))
        io_println("DRIVER prov_source_count=" + int_to_str(len(prov[0][2])))
    }

    // Exercise the chat-dispatch surface so the emit lines land in OUT.
    rule_cmd(e, kg, "add", "RULE descendant(?a, ?b) <- parent(?b, ?a)")
    rule_cmd(e, kg, "run", "")
}

main()
EOF

OUT="$("$NOVA" run "$DRIVER" 2>&1)"
RC=$?
echo "$OUT" | sed 's/^/    /'
assert_eq "$RC" "0" "rule_inference driver exits 0"

# --- step 2: initial setup -------------------------------------------------
INIT_FACTS=$(echo "$OUT" | grep -E '^DRIVER initial_facts=' | head -1 | cut -d= -f2)
RULE_COUNT=$(echo "$OUT" | grep -E '^DRIVER rule_count=' | head -1 | cut -d= -f2)
assert_eq "$INIT_FACTS" "5" "5 initial parent facts seeded"
assert_eq "$RULE_COUNT" "2" "2 ancestor rules added"

# --- step 3: derivation count ---------------------------------------------
# 5 parents form chain 0->1->2->3->4->5 = 6 nodes.
# Ancestor pairs: C(6,2) = 15.
ANCESTOR_COUNT=$(echo "$OUT" | grep -E '^DRIVER ancestor_count=' | head -1 | cut -d= -f2)
DERIVED=$(echo "$OUT" | grep -E '^DRIVER derived=' | head -1 | cut -d= -f2)
assert_eq "$ANCESTOR_COUNT" "15" "5-parent chain (6 nodes) derives 15 ancestor pairs"
assert_eq "$DERIVED" "15" "engine reports 15 newly derived atoms"

# --- step 4: fixpoint reached cleanly --------------------------------------
HIT_CAP=$(echo "$OUT" | grep -E '^DRIVER hit_cap=' | head -1 | cut -d= -f2)
assert_eq "$HIT_CAP" "0" "engine reached natural fixpoint (no cap hit)"

# Iterations must be finite + small. For a chain of length 6 with the 2
# transitive rules, the engine reaches fixpoint in O(chain_length) outer
# iterations + 1 confirmation pass. Loosely <= 10.
ITERS=$(echo "$OUT" | grep -E '^DRIVER iterations=' | head -1 | cut -d= -f2)
if [ -n "$ITERS" ] && [ "$ITERS" -le 10 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  fixpoint reached in <= 10 iterations (got %s)\n" "$ITERS"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  fixpoint took too long (got %s iterations)\n" "$ITERS"
fi

# --- step 5: cycle prevention ----------------------------------------------
CYCLE_DERIVED=$(echo "$OUT" | grep -E '^DRIVER cycle_derived=' | head -1 | cut -d= -f2)
CYCLE_CAP=$(echo "$OUT" | grep -E '^DRIVER cycle_hit_cap=' | head -1 | cut -d= -f2)
assert_eq "$CYCLE_DERIVED" "0" "cycle rule (foo<-foo) derives 0 new atoms"
assert_eq "$CYCLE_CAP" "0" "cycle rule terminates naturally (no cap hit)"

# --- step 6: idempotent re-run ---------------------------------------------
RERUN_DERIVED=$(echo "$OUT" | grep -E '^DRIVER rerun_derived=' | head -1 | cut -d= -f2)
assert_eq "$RERUN_DERIVED" "0" "re-running engine derives 0 new atoms (idempotent)"

# --- step 7: provenance ----------------------------------------------------
PROV_N=$(echo "$OUT" | grep -E '^DRIVER prov_entries=' | head -1 | cut -d= -f2)
PROV_RULE=$(echo "$OUT" | grep -E '^DRIVER prov_rule_idx=' | head -1 | cut -d= -f2)
PROV_SOURCES=$(echo "$OUT" | grep -E '^DRIVER prov_source_count=' | head -1 | cut -d= -f2)
# The first derived atom (id 5, the first ancestor) was produced by rule 0
# (the base case ancestor(?a,?b) <- parent(?a,?b)) from exactly 1 source
# parent atom.
if [ -n "$PROV_N" ] && [ "$PROV_N" -ge 1 ]; then
    PASS=$((PASS+1))
    printf "  ${C_GRN}PASS${C_RST}  derived atom has >= 1 provenance entry (got %s)\n" "$PROV_N"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  derived atom has no provenance (got %s)\n" "$PROV_N"
fi
assert_eq "$PROV_RULE" "0" "first ancestor was derived by rule 0 (base case)"
assert_eq "$PROV_SOURCES" "1" "base-case derivation has 1 source atom"

# --- step 8: RULE_ADD / RULE_RUN chat-dispatch emit lines -----------------
assert_match "$OUT" "RULE_ADD head=descendant premises=1" \
    "RULE_ADD emit line shape lands"
assert_match "$OUT" "RULE_RUN rules=3 derived=" \
    "RULE_RUN emit line shape lands (3 rules in engine now)"

# --- step 9: chat dispatch /rule_add and /rule_run --------------------------
if [ -x "$CHAT" ]; then
    CHAT_OUT=$(run_chat '/rule_add')
    assert_match "$CHAT_OUT" "usage: /rule_add" "/rule_add with no arg prints usage"

    CHAT_OUT=$(run_chat '/rule_run')
    assert_match "$CHAT_OUT" "RULE_RUN rules=0 derived=0 iterations=" \
        "/rule_run on empty engine emits RULE_RUN line"

    CHAT_OUT=$(printf '/rule_add RULE ancestor(?a, ?b) <- parent(?a, ?b)\n/rule_run\n/quit\n' | "$CHAT" 2>&1)
    assert_match "$CHAT_OUT" "RULE_ADD head=ancestor" \
        "/rule_add accepts an ancestor rule"
    assert_match "$CHAT_OUT" "RULE_RUN rules=1 derived=" \
        "/rule_run after /rule_add shows 1 rule"

    HELP_OUT=$(run_chat '/help')
    assert_match "$HELP_OUT" "/rule_add" "/help lists /rule_add"
    assert_match "$HELP_OUT" "/rule_run" "/help lists /rule_run"
else
    FAIL=$((FAIL+1))
    printf "  ${C_RED}FAIL${C_RST}  CHAT binary not built at %s\n" "$CHAT"
fi

summary "scenario_aaaa_rule_inference"
