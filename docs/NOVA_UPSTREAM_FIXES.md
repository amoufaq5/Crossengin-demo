# NOVA Upstream Fixes — Status

The five NOVA runtime gaps CrossEngin's Phase 0-7 work surfaced have
all landed upstream in `amoufaq5/NOVA`. This doc is the pointer:
the workarounds in CrossEngin can be retired on their respective PR
branches in the next rebase pass.

## Merged NOVA PRs

| NOVA PR | Gap | What it fixes | Workaround to drop |
|---|---|---|---|
| [NOVA #13](https://github.com/amoufaq5/NOVA/pull/13) | **D-3** | codegen dedups `_g_<name>` emissions when a module is imported via two legitimate paths (`tool.nova` → `_g_TR_TAG` collision). Applies to both x86-64 and wasm global emit loops. | CrossEngin `/mcp` — PR #29's inline 3-fn shim can be dropped; re-import `effector_mcp.nova` directly. |
| [NOVA #14](https://github.com/amoufaq5/NOVA/pull/14) | **P-4** | `_nova_fork` Linux tag-wraps return (`lea rax, [rax + rax + 1]`) so `if pid == 0` discriminates parent vs child; `_nova_waitpid` and `_nova_kill_proc` untag pid at entry. | PR #21's `src/nl/ollama_spawn.nova` — remove the `getpid() != parent_pid` child detection. |
| [NOVA #15](https://github.com/amoufaq5/NOVA/pull/15) | **B-5** | `store64` maps tagged-0 (raw 1) → raw 0 in memory; `load64` maps raw 0 → tagged-0 (round-trip preserved). argv/envp NULL terminators now work. | PR #21's `src/nl/ollama_spawn.nova` — drop the `os_store_null_terminator` inline asm helper. |
| [NOVA #16](https://github.com/amoufaq5/NOVA/pull/16) | **P-3** | `_nova_exec` Linux threads `_g___envp` into execve (replacing hardcoded `mov rdx, 0`). Child inherits parent's PATH/HOME/etc — the POSIX norm. | PR #21's `/ingest_ollama` can drop the print-only pivot once fork + exec + store64 are wired together; the shebang + `getenv()` paths work from NOVA's side. |
| [NOVA #17](https://github.com/amoufaq5/NOVA/pull/17) | **F-4** | `sys_read` / `sys_write` tag-polymorphic prolog on `buf` (untags an `alloc()`-backed buffer, passes a raw pointer unchanged) + unconditional `sar rdx, 1` on `count`. | PR #25's `src/factory/agent_bundle.nova:ab_read_file` — try the plain 3-arg `sys_read` path first; keep the alloc+load8 pattern as a dev-container fallback only. |

## When to retire the workarounds

Each dependent CrossEngin PR carries its own workaround commit. When
that PR is rebased against the current `claude/zealous-keller-NTz2n`
head, the rebaser can drop the workaround commit and revert the
callsite to the primitive — the upstream fix is in place.

PRs where the cleanup should happen on next rebase:
- [#21 — phase 2 Ollama](https://github.com/amoufaq5/Crossengin-demo/pull/21) — `src/nl/ollama_spawn.nova` + `/ingest_ollama`.
- [#25 — phase 5 agent Rx](https://github.com/amoufaq5/Crossengin-demo/pull/25) — `src/factory/agent_bundle.nova`.
- [#29 — phase 6 /mcp](https://github.com/amoufaq5/Crossengin-demo/pull/29) — re-import `src/io/effectors/effector_mcp.nova`.

The cleanup is intentionally not a single PR against the default
branch: the workaround code only exists on those feature branches,
so the cleanup commits belong there.

## Remaining NOVA gaps

Five other gaps surfaced during Phases 0-6 are still open upstream.
Per `docs/NOVA_RUNTIME_GAPS.md` (PR #27) they are tracked via the
NOVA umbrella issue (`amoufaq5/nova#12`):
- Missing `setenv()` — CrossEngin falls back to shell init + systemd
  `Environment=`.
- `secure_random` seccomp-blocked in the dev sandbox — key material
  must come in via env (see `bundle_signing.nova`).
- `envp=NULL` for a *strict* empty-env exec form — a new 3-arg
  `exec_program(path, argv, envp)` would replace the current
  inherit-by-default.
- No in-process HTTPS — blocks Phase 3 pt2's `src/io/effectors/search_engine.nova`.
- `exec_program` tag handling of path/argv — now the only remaining
  blocker for a full in-process `/ingest_ollama` one-step wrapper
  (NOVA #16 fixed envp but path/argv tagging is a separate rework).
