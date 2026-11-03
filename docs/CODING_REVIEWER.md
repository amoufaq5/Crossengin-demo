# The CrossEngin Coding Reviewer

`src/seed/packs/code_review_pack.nova` is a domain pack that turns the generic CrossEngin reasoning engine into a prototype code reviewer: ask about a smell, the forward-chainer walks a `rop_*` operator, you get a concrete remedy with the pack's source tag on every cited atom.

Phase 5 pt1 shipped the agent Rx surface (`/agent list | info | verify`). Phase 5 pt2 lite doubled this pack: **80 atoms + 37 operators**. This document is the operator walkthrough.

## 1. What's in the pack

**Vocabulary (18 atoms)** — the words a reviewer uses: `function, class, variable, test, refactor, mock, stub, fixture, assertion, patch, diff, commit, branch, review, approver, comment, merge_conflict, coverage`.

**Smells (32 atoms)** — categorised:

| Category | Smells |
|---|---|
| Concurrency + state | `race, leak, deadlock` |
| Correctness | `regression, off_by_one, null_deref, dead_code, duplication, shadowed_var, missing_test, magic_number, tight_coupling` |
| Control flow | `goto_statement, nested_conditionals, recursion_bound, string_concat_loop, long_parameter_list` |
| Naming + hygiene | `inconsistent_naming, missing_docstring, dead_import, commented_out_code, copy_paste, premature_optimization, global_mutation` |
| Error handling | `broad_exception, swallowed_exception, unchecked_return` |
| Security | `log_injection, sql_injection, xss_vuln, hardcoded_secret, weak_crypto` |

**Remedies (30 atoms)** — the actions a reviewer requests: `add_lock, add_cleanup, request_coverage, extract_const, request_changes, add_assertion, split_function, rename_symbol, guard_clause, request_revert, remove_goto, flatten_conditionals, bound_recursion, use_stringbuilder, extract_parameter_object, enforce_naming, add_docstring, remove_import, remove_dead_code, deduplicate, measure_first, encapsulate_state, narrow_exception, log_and_rethrow, check_return, sanitize_input, parameterize_query, escape_output, use_env_secret, use_strong_crypto`.

**Operators (37)** — `smell → remedy` edges the forward-chainer traverses, each tagged `src:pack:code_review:<smell>-><remedy>`. Example edges:

| Smell | → | Remedy | Kind |
|---|---|---|---|
| `race` | → | `add_lock` | `ROP_IMPLY` |
| `null_deref` | → | `guard_clause` | `ROP_IMPLY` |
| `sql_injection` | → | `parameterize_query` | `ROP_IMPLY` |
| `sql_injection` | → | `sanitize_input` | `ROP_IMPLY` (second remedy) |
| `copy_paste` | → | `deduplicate` | `ROP_IMPLY` |
| `hardcoded_secret` | → | `use_env_secret` | `ROP_IMPLY` |
| `deadlock` | → | `request_changes` | `ROP_CAUSAL` |

Some smells map to multiple remedies (`sql_injection` → `parameterize_query` AND `sanitize_input`). The forward-chainer picks the one with the strongest synapse weight on each query, so `/good` after an answer tunes which remedy the reviewer prefers.

## 2. Installing

```
> /seed code_review
(seed pack 'code_review' installed: 80 atoms + 37 operators; KG now 700 atoms)

> /__corpora__
  pack=src:pack:code_review  atoms=80  promo_rate_milli=0  atrophy_rate_milli=0
packs_installed=1
```

Re-running `/seed code_review` is a no-op (canary `refactor` detected); add `--reset` to re-apply.

## 3. Using it as a reviewer

Type a smell name and the reviewer surfaces the remedy:

```
> null_deref
agent> null_deref leads to guard_clause (null_deref->guard_clause).

> sql_injection
agent> sql_injection leads to parameterize_query (sql_injection->parameterize_query).

> copy_paste
agent> copy_paste leads to deduplicate (copy_paste->deduplicate).
```

`/why <atom>` traces the citation:

```
> /why guard_clause
guard_clause (kg=reasoning) traces to:
  src:pack:code_review (from pack_install_code_review)
```

The atoms the reviewer leaned on are also surfaced by the moment cache so a repeat query returns from the LRU without re-walking the chain (Phase 0 pt4).

## 4. Tuning with feedback

`/good` after a suggested remedy increments the `rop_*` operator's confidence AND its Hebbian synapse weight (Phase 0 pt2 `router_apply_feedback`). After 5 reinforcements the chain-compiler (Phase 0 pt3) mints a direct derived operator — so `null_deref` → `guard_clause` eventually compiles into a one-hop rule without needing to re-traverse the `smell → remedy` scaffold.

`/bad` weakens the same edge. Combined with multiple-remedy smells (`sql_injection` → `parameterize_query` OR `sanitize_input`), the reviewer learns the operator's remedy preference over time. The synapse weight is session-local by default; `/save` persists it.

## 5. Baking a reviewer agent

Once tuned, the reviewer can be baked into a signed, portable bundle with `bake_child_ex` (see `docs/AGENT_PLATFORM.md`). The bundle carries the atoms, operators, and session-tuned synapse weights — ready to drop into another daemon under `~/.crossengin/agents/`. Verify on load with `/agent verify <path>` using the mother's Ed25519 public key (`CE_AGENT_VERIFY_PUBKEY_HEX`).

Phase 5 pt1 shipped the Rx half of that flow (list / info / verify). The bake + install destructive-apply half is Phase 5 pt3+.

## 6. What's next

**Phase 5 pt3+** will bootstrap ~400 more pattern atoms from the Stack Overflow permissive subset via Phase 2's Ollama extractor (`scripts/llm_extract.sh`), then promote individual records through the review queue (`/ingest_llm` → `/ingest_approve`). The current 80-atom pack is the kernel; ~500 atoms is the target the `AGENT_PLATFORM.md` roadmap names.

The `/agent verify` + bake pipeline is ready today; what the pt3 ingest adds is depth, not shape.
