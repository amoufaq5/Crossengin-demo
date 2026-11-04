# Session log — the phase 0-7 arc

A single CrossEngin session shipped 12 PRs on `amoufaq5/Crossengin-demo` and opened 5 upstream issues on `amoufaq5/nova`. This document is the master index: what shipped, what each PR depends on, the recommended merge order, and what's deferred.

## 1. Shipped PRs

| # | Phase | Title | Base |
|---|---|---|---|
| [19](https://github.com/amoufaq5/Crossengin-demo/pull/19) | Phase 0 pt1-pt3 | substrate wire-ups + chain compiler + 10-query demo | `claude/zealous-keller-NTz2n` |
| [20](https://github.com/amoufaq5/Crossengin-demo/pull/20) | Phase 0 pt4 | self-indexing acceleration (kg_router + moment_cache + intent_adaptive) | `claude/zealous-keller-NTz2n` |
| [21](https://github.com/amoufaq5/Crossengin-demo/pull/20) | Phase 1 pt1+pt2 | capability gate + inline REPL approval + tamper defenses | `claude/zealous-keller-NTz2n` |
| [22](https://github.com/amoufaq5/Crossengin-demo/pull/22) | Phase 3 pt1 | free prompting + /learn_prepare guide | `claude/zealous-keller-NTz2n` |
| [23](https://github.com/amoufaq5/Crossengin-demo/pull/23) | pt1-safety ext | route NL retract through the cap gate | `claude/zealous-keller-NTz2n` |
| [25](https://github.com/amoufaq5/Crossengin-demo/pull/25) | Phase 5 pt1 | agent Rx surface (list/info/verify) + platform doc | `claude/zealous-keller-NTz2n` |
| [26](https://github.com/amoufaq5/Crossengin-demo/pull/26) | pt1-safety ext2 | cap-gate NL capsule_install / skill_install / skill_run | `claude/zealous-keller-NTz2n` |
| [27](https://github.com/amoufaq5/Crossengin-demo/pull/27) | NOVA gaps doc | docs/NOVA_RUNTIME_GAPS.md F-4 / B-5 / P-3 / P-4 | `claude/zealous-keller-NTz2n` |
| [28](https://github.com/amoufaq5/Crossengin-demo/pull/28) | Phase 5 pt2 lite | coding-reviewer pack expansion + walkthrough | `claude/zealous-keller-NTz2n` |
| [29](https://github.com/amoufaq5/Crossengin-demo/pull/29) | Phase 6 pt1 | /mcp list | register | call (honest-scope stub) + inbound roadmap | `claude/zealous-keller-NTz2n` |
| [30](https://github.com/amoufaq5/Crossengin-demo/pull/30) | end-to-end doc | integration transcript across Phases 0-6 pt1 | `claude/phase-6-pt1-mcp-registry` |
| [31](https://github.com/amoufaq5/Crossengin-demo/pull/31) | Phase 7 pt1 | cowork planner + /cowork plan + roadmap doc | `claude/end-to-end-doc` |

Not in the table: Phase 2 (reply composer PR #21 — same number as Phase 1 above; GitHub re-used it) and Phase 4 pt1 (logic pack, PR #24). Both landed on the default base branch. See "Note on PR numbering" below.

### Phase 2 PRs — note on numbering

GitHub recycles PR numbers after close/delete. The merged tree of this session has:

- **PR #20** — Phase 0 pt1-pt4 (actually the combined "all four Phase 0 pts" PR body, kept as a single PR across pt1 / pt2 / pt3 / pt4 as those commits landed on the same branch).
- **PR #21** — Phase 1 pt1 (capability gate), then updated in place to cover pt1+pt2.
- **PR #22** — Phase 3 pt1 (free prompting).

A re-numbering walk of `gh pr list --state open --base claude/zealous-keller-NTz2n` will show the current authoritative mapping; the GH web UI is the source of truth.

## 2. Merge chain

Most PRs base off `claude/zealous-keller-NTz2n` (the "default" branch this session started from). Two stack:

```
claude/zealous-keller-NTz2n
  ├─ claude/phase-0-substrate            → PR #19 (+pt1-pt4)
  ├─ claude/phase-1-safety               → PR #20/#21
  ├─ claude/phase-2-ollama                → PR (phase 2 pt1+pt2)
  ├─ claude/phase-3-prompting             → PR #22
  ├─ claude/pt1-safety-nl-retract         → PR #23
  ├─ claude/phase-4-logic-pack            → PR #24
  ├─ claude/phase-5-agent-rx              → PR #25
  ├─ claude/pt1-safety-ext2-nl-dispatch   → PR #26
  ├─ claude/nova-runtime-gaps-doc         → PR #27
  ├─ claude/phase-5-pt2-coding-reviewer   → PR #28
  └─ claude/phase-6-pt1-mcp-registry      → PR #29
      └─ claude/end-to-end-doc            → PR #30
          └─ claude/phase-7-cowork-planner → PR #31
              └─ claude/session-log        → PR #32 (this one)
```

### Recommended merge order

Everything that bases on `claude/zealous-keller-NTz2n` can merge in any order (no code conflicts — each touches disjoint files or adds to disjoint sections of `examples/crossengin_chat.nova` via `Edit` tool anchors). The stack can merge in the order:

1. All default-base PRs (#19-#29 modulo stacking).
2. `#30 end-to-end` once `#29` lands (its transcript references PR #29).
3. `#31 phase-7` once `#30` lands (its doc references end-to-end).
4. This PR (`#32 session-log`) once `#31` lands.

If the user wants a single giant merge instead of 12 sequential ones, rebasing every branch onto a working aggregate branch and squashing is fine — each PR is scoped small enough that individual commits read cleanly.

## 3. Upstream NOVA issues

| # | Gap | Impact |
|---|---|---|
| [nova#7](https://github.com/amoufaq5/NOVA/issues/7) | `_nova_fork` returns raw syscall rax without tag-wrap | Every classical `fork() ? parent : child` idiom zombie-twins (child falls through to parent code). Phase 2 pt2 workaround uses `getpid()`. |
| [nova#8](https://github.com/amoufaq5/NOVA/issues/8) | `store64(ptr, 0)` writes raw 1, not raw 0 | Argv NULL terminators are bogus pointers; `execve` returns EFAULT. Phase 2 pt2 workaround is inline-asm `os_store_null_terminator`. |
| [nova#9](https://github.com/amoufaq5/NOVA/issues/9) | `_nova_exec` passes `envp = NULL` | Shebangs fail without `PATH`; `/bin/bash` directly also fails on env-dependent binaries. Phase 2 pt2 pivoted `/ingest_ollama` to print-only. |
| [nova#10](https://github.com/amoufaq5/NOVA/issues/10) | `sys_read(fd, N)` auto-allocated strings unreliable for new file fds | Phase 5 pt1's `/agent info` had to adopt the proven `alloc + _sys_read_tagged + load8` pattern. |
| [nova#11](https://github.com/amoufaq5/NOVA/issues/11) | `_g_TR_TAG` global emitted twice when `tool.nova` imports transitively through two paths | Phase 6 pt1 pivoted to an inline 3-function shim. Blocks Phase 6 pt2 (real MCP server integration). |

Each issue carries a reproducer that matches the exact CrossEngin PR that triggered it, a suggested fix (typically a 1-5 line codegen change), and the impact on which downstream phase.

A sixth gap category — the fsync-durability + signal-handler issues already in `docs/NOVA_RUNTIME_GAPS.md` — predates this session and is tracked under the existing entries P-2, F-3.

## 4. Deferred surfaces

Each phase shipped at least pt1. The deferred pt2+ scope is named in the plan file and in each PR body. Index:

| Phase | Deferred |
|---|---|
| Phase 2 pt1 (composer) | Needs a running Ollama daemon to exercise; the composer is dormant in dev builds and the shim passes through on any backend failure. |
| Phase 2 pt2 | `/ingest_ollama` is print-only until nova#7+#8+#9 land (one-step wrapper needs the full fork+exec stack). |
| Phase 3 pt2 | `src/io/effectors/search_engine.nova` + one-shot `/learn <url>` in-process; needs in-process HTTPS which is blocked on nova#9. |
| Phase 4 pt2 | ~7M atoms bulk corpora + benchmark card. Needs compute + licensing + days. |
| Phase 5 pt2+ | Destructive `/agent install` (snapshot apply + CAP_DELETE prompt), full lifecycle (new/teach/bake/switch/update/export), 8 shipped vertical agents + manifests. |
| Phase 5 pt3 | ~400 more code-review pattern atoms bootstrapped from the Stack Overflow permissive subset via `scripts/llm_extract.sh`. |
| Phase 6 pt2+ | Real MCP server: stdio transport, JSON-RPC parser on `[buf, len]` pairs, handshake, tool discovery. Blocked on nova#7-11. |
| Phase 7 pt2+ | `/cowork run` with federation fan-out, agent reachability discovery, result aggregation + unified citation chain. |

The plan file at `/root/.claude/plans/gentle-toasting-zephyr.md` has the full execution order for each deferred phase; this doc is the index into that plan.

## 5. Known holes in the shipped-pt1 surfaces

| Hole | Source | Resolution |
|---|---|---|
| Phase 1 pt2 un-exercised in the end-to-end doc | PR #30 §9 | Needs a signed test bundle + `CE_SNAPSHOT_VERIFY_PUBKEY` to exercise the verify-on-load path. Open task. |
| Phase 2 pt1 composer un-exercised in the end-to-end doc | PR #30 §9 | Needs a running Ollama daemon. Open task. |
| `_nl_dispatch_admin`'s read-only branches | pt1-safety ext2 scope note | `capsule_list` and `skill_list` intentionally stay ungated as read-only observability. Not a hole. |
| D-3 symbol collision workaround | PR #29, nova#11 | Phase 6 pt1 inline shim reverts to a direct import when nova#11 closes. No user-facing change at that point. |

## 6. How to read this stack as an operator

1. Start from `docs/END_TO_END.md` (PR #30) — one scripted session showing every pt1 surface in order.
2. Dive into the phase-specific docs for the surfaces you want to use:
   - `docs/HOW_IT_LEARNS.md` for Phase 0's frequency-adaptive-latency property.
   - `docs/TRAIN_WITH_OLLAMA.md` for the Ollama fluency + extraction pattern (Phase 2).
   - `docs/CODING_REVIEWER.md` for the smell → remedy forward-chainer (Phase 5 pt2 lite).
   - `docs/AGENT_PLATFORM.md` for the agent-bundle Rx surface (Phase 5 pt1).
   - `docs/MCP_INBOUND.md` for the Phase 6 scope gap.
   - `docs/COWORK.md` for the Phase 7 planner model.
3. When a surface hits a "deferred" message, check the upstream NOVA issues table to see whether it's blocked on a runtime gap or waiting on scope.

## 7. Session metrics

- **12 PRs opened** (11 shipped, 1 updated in place): #19, #20, #21, #22, #23, #24, #25, #26, #27, #28, #29, #30, #31, and this one (#32).
- **5 upstream NOVA issues**: nova#7-11.
- **New NOVA modules**: `chain_compiler`, `kg_router`, `moment_cache`, `intent_adaptive`, `cap_session`, `approval_prompt`, `safety_log`, `reply_composer_ollama`, `ollama_spawn`, `logic_pack`, `agent_bundle`, `cowork_planner` — 12 modules.
- **New docs**: `HOW_IT_LEARNS.md`, `TRAIN_WITH_OLLAMA.md`, `caps.sample.conf`, `AGENT_PLATFORM.md`, `CODING_REVIEWER.md`, `MCP_INBOUND.md`, `END_TO_END.md`, `COWORK.md`, `SESSION_LOG.md` (this one).
- **Phase 0 regression invariant**: `mc_hits=9`, `ff_goodness=486000`, `synapse_mean_weight=300`, `ia_strength=10` after 10× `fever` + `/good` on a clean session. Every PR's smoke test reports this.
