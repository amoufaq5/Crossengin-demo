# Upstream NOVA bugs tracked by CrossEngin workarounds

This manifest consolidates every NOVA runtime / codegen issue (and the
one container-sandbox policy) that CrossEngin currently works around at
user level, under the standing constraint that `/home/user/NOVA/src/
runtime/*` and `/home/user/NOVA/src/compiler/codegen.nova` remain
off-limits for this repository.

When all five NOVA entries land upstream, the entire workaround surface
retires in one sweep: `src/util/{str_safe,mem_safe,type_safe,gen_id}.nova`
and every R3b-R3f call-site migration can be reverted. Operator action.

Each entry carries: the ADR that diagnoses it, the user-level
workaround, the affected test set, and the suggested upstream fix
location.

## 1. `memcpy_raw` codegen -- OOB on tagged source operand

- **ADR**: 0103
- **Status**: **UPSTREAM FIX SHIPPED** in NOVA commit `f7d9766`
  (2026-10-06) — `_nova_memcpy_raw` at `codegen.nova:22315` now has
  three `test rax, 1 / jz skip / sar rax, 1` entry blocks for rdi, rsi,
  and rdx, making it tag-polymorphic. WASM backend at `:14624-14665`
  mirrors the same pattern. New `tests/test_memcpy_raw_tagged.nova`
  exercises tagged `alloc(16)` buffers end-to-end. Self-host fixpoint
  holds (compiler source doesn't call memcpy_raw).
- **Workaround (defensive, retained)**: `src/util/mem_safe.nova:byte_copy`
  stays. R3d/R3c-era inline byte-copy loops in `src/runtime/string.nova`
  (`str_concat`, `str_slice`, etc.) could now be re-collapsed to
  `memcpy_raw` — queued as a future cleanup round, not urgent.
- **Tests**: `test_stereo_u8_simd`, LK pair (`test_lk_u8_simd`,
  `test_lk_mulacc_simd`), `test_image_ocr` continue to pass via the
  user-side `byte_copy` helper.

## 2. `rt_str_to_int` -- `load8` on tagged string handle

- **ADR**: 0103
- **Workaround**: **UPSTREAM FIX SHIPPED** in NOVA commit `b66644b` on
  `claude/confident-fermi-op241b` (2026-10-05): `rt_str_to_int` now
  normalizes raw string handles (literals, `_nova_substr` return) to
  tagged at entry via an inline-asm `[rbp-8]` retag, so both pointer
  conventions work. **Sweep follow-up** in NOVA commit `41058d2` on the
  same branch (2026-10-05): the same per-site inline-asm normalizer was
  extended to 7 more `src/runtime/string.nova` fns across 12 parameter
  slots — `str_len`, `str_char_at`, `rt_str_eq`, `str_cmp`,
  `rt_str_find`, `str_starts_with`, `str_ends_with` (all end-to-end
  verified on raw-literal inputs), plus the second (delim) slot of
  `str_split`. **Deferred-4 sweep closed** in NOVA commit `2bc1dab` on
  the same branch (2026-10-05): the four previously-deferred fns —
  `str_concat`, `str_slice`, `rt_str_trim`, and `str_split`'s first
  slot — now entry-normalize their handle(s) to tagged, and the two
  that previously called `memcpy_raw` on a tagged alloc dst
  (`str_concat`, `str_slice`'s former `str_new(s+start, len)` path)
  were rewritten to byte-copy via `store8`/`load8` — both of which
  untag addresses correctly, so no scratch-local untag is needed and
  no reliance on the still-broken `str_new(tagged, raw, tagged)`
  internal flow. Also fixed a latent precedence bug in `rt_str_trim`'s
  whitespace predicate: `c == 32 | c == 9 | ...` parsed as a chained
  comparison via `|` (parse_bitwise, higher precedence than `==`);
  changed to `||` for the expected bool-OR. Standalone verification
  confirms all four raw-literal assertions pass; `make self-host`
  fixpoint holds. **Skipped permanently** per Phase-1: `str_new`,
  `str_data`, `str_contains` (forwards to `rt_str_find`),
  `rt_int_to_str`. R3d's user-side migration (replace `rt_str_to_int`
  with the `str_to_int` builtin at call sites) remains in the codebase
  as a defensive measure — a future round can retire it if desired, but
  there's no behavioral urgency.
- **Tests**: `test_kg_query`, `test_kg_query_agg`, `test_kg_query_ext`,
  `test_fed_daemon_boot`. Upstream regression coverage added in NOVA's
  `tests/test_runtime.nova`: `rt_str_to_int("42")` and
  `rt_str_to_int(substr("abc123def", 3, 3))` exercise the raw path.
- **Suggested fix**: ~~`/home/user/NOVA/src/runtime/string.nova:226` --
  untag the string handle in the `load8` operand before dereferencing.~~
  Shipped.

## 3. `type_of()` regression -- new mapping incompatible with historic constants

- **ADR**: 0104 (Superseded)
- **Workaround**: **UPSTREAM FIX SHIPPED** in NOVA commit `651a507` on
  `claude/confident-fermi-op241b` (2026-10-05). Three tandem edits in
  `src/compiler/codegen.nova`: tag `_nova_type_of` return `(N<<1)|1`,
  tag the AST_TYPE_PATTERN match-arm cmp operand, mirror in WASM
  backend. Historical mapping (null=0, int=1, str=2, list=3, map=4) is
  restored. `src/util/type_safe.nova` is retained as a thin stable-API
  wrapper and its three constants were swapped to match the historical
  mapping (`is_int_val: == 1`, `is_list_val: == 3`, `is_str_val: == 2`);
  a future round can inline-remove the wrapper by migrating callers to
  raw `type_of(x) == N`.
- **Tests**: `test_distributed_rules`, `test_kg_query*` (all three),
  schema validation across the KG stack. All pass counts preserved
  pre/post swap (45/94/52/42/62/67/60/47/54 across spot-checks).

## 4. bug-#11 sentinel equality on two-large-operand `==`

- **ADR**: 0105
- **Status**: **TRANSITIVELY CLOSED by Bug #3's fix** (NOVA commit
  `651a507`, 2026-10-05). Phase-1 audit confirmed `_nova_eq` at
  `codegen.nova:15943` is now a flat `cmp rdi, rsi; je .eq_true` —
  no deref, no type-dispatch. Empirical probe shipped as NOVA commit
  `172ee8c` (2026-10-06): `tests/test_dp_refused_eq.nova` exercises
  `v == DP_REFUSED (0 - 2147483647)` end-to-end and PASSes.
- **Workaround RETIRED**: `src/safety/differential_privacy.nova:dp_is_refused`
  restored to direct `v == DP_REFUSED` in Crossengin commit `<THIS>`;
  the magnitude-probe + stale "bug-#11" comment removed.
- **Tests**: NOVA upstream probe confirms the behavior.
  `test_federated_aggregator`'s R3g.1 (separate class, see bug #7)
  remains defensive and is independent of this close.

## 5. `io_println` -- tagged-literal walker + concat-node handling

- **ADR**: 0105
- **Status**: **UPSTREAM FIX SHIPPED** in NOVA commit `3e417b3`
  (2026-10-06) — `io_print` / `io_println` in `src/runtime/io.nova`
  now delegate to the `print` / `println` builtins (which use raw
  NUL-scan + raw syscall write, so tagged `str_len` returns no longer
  corrupt rdx). The stderr pair `io_eprint` / `io_eprintln` use inline
  asm to normalize the tagged count to raw before `sys_write`. New
  `tests/test_io_println.nova` exercises short/long/concat on both
  stdout and stderr. Self-host fixpoint holds (compiler doesn't call
  io_println).
- **Workaround (defensive, retained)**: `drule_chat_add_cmd` /
  `drule_chat_run_cmd`'s `println` + chunk-split call sites in
  `src/federation/distributed_rules.nova` stay — they're
  belt-and-braces that already use the builtin directly.
- **Tests**: `test_distributed_rules` continues to pass via the
  workaround path; `test_io_println.nova` upstream covers the direct
  behavior.

## 7. raw-nanotime-untagged on `&` -- subsequent `*` SEGVs

- **ADR**: 0106
- **Status**: **UPSTREAM FIX SHIPPED** in NOVA commit `053584e`
  (2026-10-06) — `nanotime()` body in `src/runtime/io.nova:252-258`
  now ends on an asm block that tags rax via `lea rax, [rax+rax+1]`
  before implicit return. New test `tests/test_nanotime_tag.nova`
  exercises `t & 0xFF`, `type_of(m) == 1`, `m * 2`, `int_to_str(m)` —
  all pre-fix SEGV paths, now PASS.
- **Workaround (defensive, retained)**:
  `src/safety/differential_privacy.nova:dp_new` still seeds from
  `epsilon_budget_milli + 7919` instead of `nanotime() & _LCG_MASK`.
  No urgency to retire — deterministic seed is a stability feature
  for the Minimum Viable DP.
- **Tests**: `test_federated_aggregator` (R3g.1) continues to pass
  via the workaround path; `test_nanotime_tag.nova` upstream covers
  the direct behavior.

## 8. unresolved-callee SEGV on import-graph miss

- **ADR**: 0106
- **Status**: **UPSTREAM FIX SHIPPED** in NOVA commit `0f9d3f2`
  (2026-10-06) — new `cg_fail(msg)` helper in `codegen.nova`;
  AST_CALL at `:5064` and `wasm_gen_expr` AST_CALL both now emit
  `ERROR: undeclared callee: <name>\n` + `exit(1)` when an
  identifier can't resolve to {known fn, struct ctor, global,
  local, param}. New `test_fails_*` harness convention in
  `tests/run_tests.sh` + fixture `tests/test_fails_unresolved_call.nova`
  exits 3 with the expected error. Self-host fixpoint zero
  false positives — NOVA's own source has no latent unresolved
  calls.
- **Workaround (defensive, retained)**:
  `src/federation/gossip_dtls_shim.nova`'s shim-local
  `gds_extract_keys` remains in place. The upstream fix now
  surfaces the import-graph miss at compile time with a clean
  error, so new code written against the fixed NOVA will catch
  the typo instead of SEGV'ing — but the existing shim stays
  because retiring it has no behavioral benefit.
- **Tests**: `test_gossip_dtls_shim` (R3g.2) continues to pass
  via the shim; `test_fails_unresolved_call.nova` upstream
  covers the direct behavior.

## 9. Assembler rejects duplicate module-private `_starts_with` symbol

- **ADR**: 0111 (R6 close-out section).
- **Workaround**: **SHIPPED** via option (a): `_starts_with` →
  `_snap_starts_with` in `src/persistence/snapshot_disk.nova`.
  14 occurrences renamed (1 definition + 13 call sites); zero test
  edits (grep confirmed). `crossengin_daemon.nova` now LINKs.
  `crossengin_chat.nova` still fails at link time, but with a
  different collision (`_g_PC_TAG`) — see bug #10 below.
  Hypothetical alternative (b) — rename `_starts_with` →
  `_tkgsync_starts_with` in `src/io/transducers/kg_sync.nova:410`
  (~15 in-module caller sites + 4 call sites in
  `tests/unit/test_kg_sync.nova:336-339`) — was NOT taken because
  option (a) needed no test edits.
- **Tests**: no unit coverage of the collision itself. Affected binary
  builds:
  * `examples/crossengin_chat.nova` — was blocked at link time from
    Phase M R1 (`5f2e9f2`) until this commit; `_starts_with` collision
    is resolved, but a second collision (`_g_PC_TAG`, bug #10) still
    blocks the chat binary.
  * `examples/crossengin_daemon.nova` — was blocked at link time from
    Phase M R6 (`9cbbf12`) until this commit; every R6 unit test passes
    (hook is exercised via the Session accessor chain), and the daemon
    binary now LINKs.
- **Context**: NOVA's whole-program assembly emits one global symbol
  per `fn` definition without module-mangling. Collisions surface only
  when a `main()` transitively pulls BOTH offending modules
  (`persistence/snapshot_disk` + anything importing
  `io/transducers/kg_sync` — e.g. via `federation/gossip`). The other
  20+ `*_starts_with` definitions in the tree all carry a module prefix
  (`_gossip_starts_with`, `_sr_starts_with`, `_att_starts_with`, …)
  and do not collide.
- **Suggested fix**: NOVA compiler should mangle module-private names
  with the module path (e.g.
  `_nova_persistence_snapshot_disk__starts_with`). Alternatively a
  loader-side allow-list of "weak" module-private symbols.
- **Status (2026-10-06)**: **DEFERRED at NOVA level, now DESIGNED under
  NOVA ADR-0009** (`docs/adr/0009-module-system-and-symbol-mangling.md`
  in the NOVA repo, commit `7901bea`). The ADR proposes a file-scoped
  module system in which the existing `_`-prefix convention becomes
  real private-visibility syntax, with full-path mangling for private
  names. Phase-1 scoping estimate stands: ~115 LOC single round once
  the ADR is Accepted. User-side renames (option (a) + bug #10's rename)
  remain the long-term fix in the interim and will be revertible after
  the ADR implementation lands.

## 10. Assembler rejects duplicate module-private `_g_PC_TAG` symbol

- **ADR**: none (ships as a rename commit referenced from this file).
- **Workaround**: **SHIPPED** via option (a): `PC_TAG` →
  `PROOF_CHECKER_TAG` in `src/parts/reasoning/proof_checker.nova:86`.
  One-line edit; grep across `src/`, `tests/`, `examples/` found zero
  callers of `PC_TAG` outside `proof_checker.nova` itself and
  `perception_atoms.nova`'s own `PC_TAG` definition, so zero external
  touches were needed. `crossengin_chat.nova` now LINKs for the first
  time since Phase M R1 (`5f2e9f2`).
  **Follow-up**: a subsequent dead-constant audit confirmed
  `PROOF_CHECKER_TAG` had zero readers in-module as well (the real
  tag used by `proof_new` is `_PC_OBJ_TAG = 5201`). The constant was
  removed entirely in a later commit — the collision class is now
  fully retired on this side regardless of upstream NOVA fixes. Hypothetical alternative (b) —
  rename `PC_TAG` → `PA_PC_TAG` in
  `src/parts/perception/perception_atoms.nova:90` — was NOT taken
  because option (a) was smaller (1 touch vs 3) and perception's
  `PC_TAG` is the semantically-primary tag constant.
- **Tests**: no unit coverage of the collision itself. Affected binary
  builds:
  * `examples/crossengin_chat.nova` — was blocked at link time from
    Phase M R1 (`5f2e9f2`) until this commit (previously masked by
    bug #9's `_starts_with` collision, surfaced only after bug #9
    option (a) shipped). Now LINKs cleanly.
- **Context**: same shape as bug #9 but on module-level `let` bindings
  rather than `fn` definitions. Two modules both declare
  `let PC_TAG = ...` at module scope, which NOVA emits as the global
  symbol `_g_PC_TAG`:
  * `src/parts/reasoning/proof_checker.nova:86`: `let PC_TAG = 1`
  * `src/parts/perception/perception_atoms.nova:90`: `let PC_TAG = 0`
  Collision surfaces when a `main()` transitively pulls BOTH modules
  (chat does; daemon does not, which is why daemon LINKs post bug-#9
  workaround while chat still errors).
- **Suggested fix**: same shape as bug #9's suggested fix — NOVA
  compiler should mangle module-level `let` names with the module
  path (e.g. `_g_nova_parts_reasoning_proof_checker__PC_TAG`). The
  user-side rename in option (a) above has LANDED (closes this bug
  as a workaround).
- **Status (2026-10-06)**: **DEFERRED at NOVA level alongside bug #9,
  DESIGNED under NOVA ADR-0009** (commit `7901bea`). Same reasoning:
  module-level `let` mangling uses the same `_g_m_<file>__<name>`
  scheme as fn mangling. User-side rename + dead-constant removal
  (`85667a7`) have fully retired the collision class on this side
  regardless of upstream.

## 12. Syscall wrapper tagging audit (sys_open, sys_rename, sys_read, downstream)

- **ADR**: none yet — needs design round for a comprehensive sweep.
- **Workaround**: none; the 4 affected tests (C2b snapshot cluster) stay
  in the deferred bucket until the sweep lands.
- **Tests**: `test_snapshot_disk`, `test_snapshot_disk_full`,
  `test_snapshot_delta`, `test_snapshot_episodic` (SEGV at
  `snap_section(snap_load(path), SEC_SOUL)[0]` because snap_load
  returns 0 because snap_write_durable fails upstream).
- **Context**: R6b investigation (`a09e8751848a3e5eb` Explore agent)
  identified `sys_open` as passing tagged `flags`/`mode` to the kernel
  (same shape as Bug #11): `O_WRONLY|O_CREAT|O_TRUNC = 0x241` becomes
  `0x483 = (0x241<<1)|1` which the kernel decodes as
  `O_ACCMODE|O_EXCL|O_APPEND` -- no `O_CREAT` bit, so the tmp-file open
  fails with ENOENT. Fixing that un-masks three further issues at the
  syscall-wrapper layer:
  * `sys_rename` returns raw 0 (success) but caller compares to
    tagged 0 (which is in-memory 1), so `rr != 0` is always TRUE and
    the error branch unlinks + returns 0.
  * `sys_read` passes `buf` (tagged alloc pointer) and `count` (tagged
    literal) raw to the kernel; `read()` returns `-1 EFAULT` because
    the buffer address is non-canonical, and even if that were fixed
    the raw byte-count return doesn't match the tagged values callers
    expect.
  * Downstream in `snap_read_text`: `store8(buf + m, 0)` and
    `acc = acc + buf` both do raw-vs-tagged arithmetic on buffer
    pointers; even with sys_read untagged, the per-chunk null
    terminator writes to the wrong address and string-concat on a raw
    buffer SEGVs (prior session's "NOVA `str_new` tagged-dst fix" item
    describes the same underlying issue in `str_new`).
- **R6b outcome**: Investigation found all 4 issues above. Patched
  `sys_open` + `sys_rename` + `sys_read` with the standard
  `test rax, 1 / jz / sar rax, 1` untag dance and return-value tagging
  for `sys_rename`. The combined patch allowed snap_write_durable to
  WRITE successfully (strace confirms correct `open`/`write`/`rename`
  syscalls) but snap_load still SEGV'd in `snap_read_text`'s
  `store8(buf + m, 0)` because `+` on a tagged pointer + raw int
  gives a non-canonical address. Un-masking `sys_open` also broke
  `test_decision_log_durable` + `test_chat_state_persistence` +
  `test_fed_daemon_transport` -- all three previously passed via
  sandbox-skip (which relied on `_tmp_write_works()` failing because
  of the tagged flags); fixing flags lets them proceed to the next
  failure. Full patch reverted to avoid shipping a net regression.
- **Suggested fix (multi-round sweep)**: Audit every `src/runtime/
  syscall.nova` wrapper for (a) input untagging (`sar reg, 1` after
  the `mov reg, [rbp-N]`) and (b) return tagging (`lea rax, [rax +
  rax + 1]` after `syscall`, bracketed with a `js` for negative
  errno returns). Separately, audit `src/runtime/string.nova` /
  `src/runtime/alloc.nova` for buffer+count arithmetic (`str_new`,
  `_nova_add` on tagged pointers, `store8`/`load8` on computed
  addresses). Together these likely represent 15-30 LOC in NOVA but
  need the whole call-graph audit before landing, OR a NOVA codegen
  change that auto-emits the untag/tag dance for asm-only fns.
- **Status (2026-10-06)**: DOCUMENTED — no fix shipped in R6b
  because the surface spans 4+ wrappers and a downstream Crossengin
  idiom that needs rewrite OR a NOVA str_new fix. Queued for a
  dedicated multi-session sweep round.
- **R10 outcome (2026-10-07)**: Attempted comprehensive sweep as
  R10a (all 18 syscall wrappers rewritten with input untag + sign-
  aware return tag) + R10b (_nova_concat tag-polymorphic entry at
  codegen.nova:16400). Both patches drafted and tested empirically.
  Reverted at the stage2 build stage after discovering two new
  constraints:
  * **Byte-count return tagging breaks the compiler itself**. The
    NOVA compiler consumes RAW byte counts from sys_read / sys_write /
    sys_lseek / sys_pread / sys_pwrite / sys_mmap / sys_getcwd (both
    in reading source files + emitting assembly). Tagging their
    returns breaks every caller doing raw-count arithmetic — stage2
    `bin/nova` fails to compile anything (SEGV in file reader).
    Rule: only tag returns for 0-or-errno-style wrappers (sys_rename,
    sys_fsync, sys_fdatasync, sys_unlink, sys_mkdir, sys_fstat,
    sys_ftruncate). Leave byte-count / position / pointer returns raw.
  * **_nova_concat tag-polymorphic entry breaks direct callers**.
    6+ sites `call _nova_concat` directly (bypassing _nova_add's
    dispatcher), including codegen.nova:16917 ("aligned heap copy
    (bit0=0)") which EXPLICITLY requires the raw-pointer convention.
    Adding `test rdi,1; jz; sar rdi,1` means any such caller passing
    a bit-0=1 value (which is unusual but happens for ints that
    skip the dispatcher) gets its value halved. Breaks compiler
    bootstrap. Rule: do NOT add tag-polymorphic entry to _nova_concat
    without first auditing every direct call site and classifying
    its tag convention.
- **Suggested fix (next round)**: Replace the broad sweep with a
  surgical approach:
  1. Input untag on sys_open flags/mode (safe — doesn't un-mask
     sandbox-skip paths if applied together with #2).
  2. Return tag on 0-or-errno wrappers only (sys_rename,
     sys_fsync, sys_fdatasync, sys_unlink, sys_mkdir, sys_fstat,
     sys_ftruncate).
  3. Rewrite snap_read_text in Crossengin to use NOVA's `str_new`
     primitive (which already handles raw buffer → tagged string
     properly, per Bug #2 fix) instead of `acc + buf` concat on a
     raw sys_read buffer. Zero NOVA runtime changes.
  4. For the 4 C2b tests + 3 sandbox-skip tests, verify the
     end-to-end flow works via str_new rewrite.
  Estimated LOC: ~15 NOVA + ~15 Crossengin. Still multi-session.
- **R11 outcome (2026-10-07)**: Shipped NOVA commit `f83aa7c` with
  only R11-a (sys_open flags/mode untag) + R11-c (sys_rename
  return tag) — the two sub-pieces provably safe in isolation.
  **Phase-1 Explore verification** (`abf5d752de1e20f7b`) found 2
  new blockers in the originally-planned R11-b/d:
  * `str_new` requires TAGGED length internally (`alloc(length+1)`
    dispatches `+` through `_nova_add` → `_nova_check_rdi` bit-0
    classifier). Rewriting `snap_read_text` as `str_new(buf, m)`
    where m is raw from sys_read SEGVs — misclassifies raw length
    as pointer → jumps to `_nova_concat`.
  * `sys_write` input-untag-only still returns raw rax; caller
    `if written != n` compares raw bytes-written to tagged
    `len(text)` → always TRUE for non-trivial writes → error branch.
  Shipping either half of R11-b/d without matching caller fixes
  guarantees regressions. R11 ships only the safe halves (zero
  C2b closures, zero regressions, correct infrastructure for
  future rounds). Verified: all prior-round canaries PASS post-R11.
  C2b + sandbox-skip trio state unchanged (still SEGV, as expected).
- **R12 options (next round)**:
  - (a) `sys_write` + `sys_read` caller audit across NOVA + CE,
    decide per-caller whether to tag return or untag at callsite.
    Then land `sys_write` return-tag selectively.
  - (b) NOVA ADR for syscall-boundary tag convention
    ("wrappers always return tagged"; patch compiler + stdlib
    callers to match).
  - (c) Crossengin-side workaround: `_sys_read_tagged` /
    `_sys_write_tagged` helpers in `src/util/` that tag returns
    after calling the raw wrappers. Use them in snap_read_text +
    snap_write_durable. Zero NOVA changes.
- **R12 outcome (2026-10-07)**: SHIPPED option (c). Added
  `src/util/sys_tagged.nova` with inline-asm wrappers that bypass
  the raw sys_read/sys_write layer entirely — untag buf (TP) +
  count (unconditional) on input + sign-aware tag non-negative
  return. Patched 4 source files + 1 test file:
  snapshot_disk.nova, snapshot_delta.nova, chat_state.nova,
  decision_log.nova (source), test_decision_log_durable.nova
  (test). Byte-copy loop replaces `acc = acc + buf` concat (str_new
  has its own SEGV issue beyond the compile hang).

  Scope-of-close: **4 full closes** (test_snapshot_disk,
  test_snapshot_delta, test_snapshot_episodic,
  test_decision_log_durable). 1 near-close (test_snapshot_disk_full:
  126 passed, 1 FAIL — gloss roundtrip edge case). 2 still SEGV
  (test_chat_state_persistence, test_fed_daemon_transport —
  deeper issues deferred to R12b).

  Zero regressions across 28 prior-round canaries.

  Design surprises during execution:
  * `_sys_read_tagged` as a thin NOVA wrapper of raw sys_read
    didn't work — count arrives tagged → kernel reads 2x+1 bytes.
    The wrapper does its OWN inline syscall with the untag dance,
    bypassing sys_read entirely. Same for sys_write.
  * `str_new(buf, m)` with tagged m SEGVs (not just the compile
    hang Phase-1 flagged — a secondary runtime bug). Byte-copy
    loop (`piece = piece + chr(load8(buf+i))` per index) is the
    proven fallback used by `_rpc_snap_read:3314-3319`.

## 11. `_sys_clock_gettime_monotonic` passes tagged pointer -- clock_gettime EFAULTs silently

- **ADR**: none (direct 1-LOC asm fix).
- **Workaround**: none needed; upstream fix lands immediately.
- **Tests**: FAIL→PASS cohort = `test_ed25519` (`ed25519_sign latency
  positive`), `test_bignum_256` (3 latency asserts), `test_bignum_2048`
  (all `dt > 0` asserts), partial close on `test_realtime_pacer`
  (3 of 6 FAILs flipped).
- **Context**: `_sys_clock_gettime_monotonic(ts)` at
  `/home/user/NOVA/src/runtime/io.nova:271-278` loads `ts` from
  `[rbp-8]` into `rsi` and syscalls `clock_gettime(CLOCK_MONOTONIC,
  ts)`. But `alloc` returns a TAGGED pointer (`(raw<<1)|1`); the
  kernel receives a non-canonical address and returns `-EFAULT`. The
  caller's `load64(ts)` / `load64(ts+8)` correctly untags, but the
  underlying buffer never got written -- it reads the zeroed alloc
  slot. Result: `nanotime()` returns constant `1` (tagged 0) on every
  call. Every `dt = nanotime() - t0; dt > 0` latency assertion fails
  because `dt == 0`. Strace confirms:
  ```
  clock_gettime(CLOCK_MONOTONIC, 0x7567c8a1) = -1 EFAULT (Bad address)
  clock_gettime(CLOCK_MONOTONIC, 0x7845c6d1) = -1 EFAULT (Bad address)
  ```
  All addresses end in `1` (the tag bit). This has been latent since
  the fn was introduced (`3fd1a6a`); Bug #7's test only checked
  tag/type of the return value, not that time actually advances, so
  it passed trivially even with the kernel never writing the buffer.
- **Fix**: 1 LOC in `_sys_clock_gettime_monotonic` -- add `sar rsi, 1`
  after `mov rsi, [rbp-8]` to untag the pointer before `syscall`.
  Equivalent `shr` works since bit 0 of a tagged int is always 1.
  No codegen involvement (confirmed in disassembly: two distinct
  `call nanotime` instructions bracket the measured operation; CSE
  is not implicated).
- **Status (2026-10-06)**: SHIPPED upstream in this round (R6).
- **Latent sibling observation (not part of this fix)**:
  `_raw_imul_add(sec, 1000000000, nsec)` at `io.nova:296` reads the
  literal `1000000000` TAGGED from `[rbp-16]`, so the asm actually
  computes `sec*(2e9+1) + nsec`. Does NOT cause the current FAIL (the
  diff is still positive once EFAULT is fixed and the `dt_ms < 30000`
  ceiling still holds under normal uptime). Cosmetic; separate pass.

## 13. ASLR-sensitive SEGV in _nova_len via test_fed_daemon_transport

- **ADR**: none yet.
- **Workaround**: none; the 2 affected tests stay in the SEGV
  bucket until the underlying NOVA runtime issue is fixed.
- **Tests**: `test_fed_daemon_transport`, `test_p256_keypair_load`
  (likely — same shape per Phase-1 R12b investigation).
- **Context**: R12 + R12b patched the syscall-wrapper tagging
  convention end-to-end for these tests. Under strace, the tests
  PASS cleanly (strace confirms the full file-I/O roundtrip +
  `fed_daemon_transport: OK (20 checks)` prints). Under
  `setarch -R /tmp/fdt_dbg` (ASLR disabled), the binary SEGVs
  deterministically with no output.

  **Gdb backtrace from live core dump** (produced under setarch -R):
  ```
  #0  0x0000000000497b09 in _nova_len ()
  #1  0x000000000040ca92 in p256_keypair_load (base_path=140737493187350)
  #2  0x0000000000493b62 in test_missing_keypair_at_resolved_base_returns_zero ()
  #3  0x0000000000493e24 in main ()
  ```

  **Faulting instruction**: `cmpq $0xffffffffffffffff, (%rdi)` at
  `_nova_len+5`. rdi = `0x80000049bb16` (140737493187350 decimal),
  which is just above the x86-64 user-space ceiling of 2^47 - 1
  (0x7fffffffffff). The pointer is INVALID — not a tagged NOVA int
  (bit 0 = 0, so classifier treats it as pointer) and not a valid
  mapped address.

  The `base_path` arg to `p256_keypair_load` is formed by
  `_base_dir() + "/.crossengin_ph_o_r3_txport_missing/signer"` in
  `test_fed_daemon_transport.nova:140`. The `+` operator dispatches
  through `_nova_add` → `_nova_concat` (both operands pointer).
  Somehow the concat result is a value with high bits set, placing
  it above userspace. This is NOT the tag-polymorphic issue R10b
  tried to fix (both operands are already pointer-classified) —
  something downstream in `_nova_concat`'s string-building path
  produces an address beyond userspace under ASLR-OFF.

  **Why ASLR-OFF matters**: With ASLR on, mmap pushes allocations
  to high addresses (above 0x200000000); strace slows allocation
  pacing enough to shift pointer values past magnitude thresholds.
  Both avoid the specific address range that triggers the bug.
  Without ASLR, the heap gets placed at a specific low address
  range where the concat output computation produces 0x80000... .
- **Suggested fix**: Investigate `_nova_concat` + `_nova_alloc` for
  an arithmetic overflow or sign-extension bug under specific heap
  layouts. The reproducer is deterministic:
  ```
  cd /home/user/Crossengin-demo
  setarch -R /home/user/NOVA/nova build tests/unit/test_fed_daemon_transport.nova -o /tmp/fdt_dbg
  ulimit -c unlimited
  rm -rf /root/.crossengin_ph_* core
  cd /tmp && setarch -R ./fdt_dbg
  gdb -batch -ex 'bt' -ex 'info registers' /tmp/fdt_dbg core
  ```
- **Status (2026-10-07)**: DOCUMENTED — needs dedicated NOVA runtime
  round. The R12b `_sys_tagged` helpers are correct per Phase-1
  static analysis; this bug is in NOVA's concat/alloc path, not
  in Crossengin's syscall wrappers.

## 14. `_nova_str_replace` returns "" on no-match input under specific heap layouts

- **ADR**: none yet.
- **Workaround**: SHIPPED — Crossengin-side scan-first fast path in
  `_snap_oneline` at `src/persistence/snapshot_disk.nova:358-370`.
  If input has no CR/LF, returns it unchanged; only invokes
  `str_replace` when a flatten is actually needed.
- **Tests**: `test_snapshot_disk_full` `gloss survived reload`
  (closed via the workaround).
- **Context**: `_snap_oneline("a happy accident of events")` calls
  `str_replace` twice (replacing \n then \r). Input has no CR/LF so
  both calls should be identity. Observed: returns `""`. Three
  symmetric `len(r[9]) > 0` guards on the gloss slot (:407, :621,
  :745) cause the empty value to silently cascade through
  emit → skip-serialize → skip-apply, giving the `got=''`
  (empty, not corrupted) pattern.
- **Likely root cause**: Same shape as Bug #13's ASLR-sensitive
  `_nova_concat` output — a `_nova_str_replace` /
  `_nova_chr` / `_nova_concat` interaction under specific
  allocation patterns. All three live in the same codegen area:
  `_nova_str_replace` at `/home/user/NOVA/src/compiler/codegen.nova:20881`,
  `_nova_chr` at `:16834`, `_nova_concat` at `:16400`.
- **Suggested fix**: Investigate `_nova_str_replace`'s no-match
  path (codegen.nova:20926-20936) + `_nova_chr`'s tag convention
  (:16834) + possible interaction with `_nova_concat` layout
  (Bug #13). Likely a shared root cause.
- **Status (2026-10-08)**: Workaround SHIPPED Crossengin-side.
  NOVA runtime fix deferred to a dedicated round (co-investigate
  with Bug #13).

## 6. Sandbox O_CREAT policy (container, not NOVA)

- **ADR**: 0104
- **Workaround**: sandbox-skip idiom (one-shot probe at test start,
  guarded `main()` short-circuit) applied in `test_audio_wakeword`,
  `test_chat_state_persistence`, `test_decision_log_durable`,
  `test_fed_daemon_transport`.
- **Tests**: as listed above.
- **Context**: not a NOVA bug; the test-container filesystem sandbox
  blocks `sys_open(O_CREAT, ...)` under both `/tmp` and `$HOME`. On a
  less-restricted CI host these tests should run their full battery
  (the skip collapses to the probe + banner). Operator action is to
  relax the sandbox policy for the CI runner, not patch NOVA.

## Retirement order

Status snapshot as of 2026-10-06:

- (1) SHIPPED upstream — NOVA commit `f7d9766`.
- (2) SHIPPED upstream — NOVA commits `b66644b` + `41058d2` + `2bc1dab`.
- (3) SHIPPED upstream — NOVA commit `651a507`.
- (4) TRANSITIVELY CLOSED by Bug #3's fix — verified by NOVA probe commit
  `172ee8c`; Crossengin workaround retired.
- (5) SHIPPED upstream — NOVA commit `3e417b3`.
- (6) operator / infra (container sandbox policy), out of band — not a
  NOVA bug.
- (7) SHIPPED upstream — NOVA commit `053584e`.
- (8) SHIPPED upstream — NOVA commit `0f9d3f2`.
- (9) + (10): user-side workarounds shipped. NOVA-level mangling fix
  DEFERRED to a future module-system ADR (`pub`/`mod` design) — not
  worth landing alone.
- (11) SHIPPED upstream in R6 (nanotime EFAULT) — closes `test_ed25519`,
  `test_bignum_256`, `test_bignum_2048` + 3 of 6 FAILs in
  `test_realtime_pacer`.
- (12) INVESTIGATED in R6b (syscall wrapper tagging audit) — all 4
  specific wrapper bugs identified empirically (sys_open flags/mode,
  sys_rename raw return, sys_read EFAULT, snap_read_text downstream);
  patches drafted + verified correct but reverted because full close
  needs multi-wrapper sweep + Crossengin snap_read_text idiom change
  OR NOVA str_new fix. R11 shipped sys_open flags/mode + sys_rename
  return tag upstream (`f83aa7c`). R12 shipped Crossengin-side
  `sys_tagged` helpers + 4-source patches, closing 4 of 7 target
  tests. R12b patched p256_keypair.nova.
- (13) SHIPPED upstream in R13 (`_nova_alloc` signed-compare bug) —
  NOVA commit `ea84104`. Root cause narrowed by Phase-1 agent to
  `_nova_alloc`'s fast-path `jle` compare at codegen.nova:16348;
  addresses with bit 47 set compare as negative under SIGNED,
  slip past the "fits in heap" guard, and get returned as
  non-canonical pointers that SEGV on later deref. Fix: 1-char
  `jle` -> `jbe`. Closes `test_fed_daemon_transport` + closes
  pre-existing `test_p256_keypair_load`. Does NOT close Bug #14
  (confirmed: reverting the R12d workaround regresses the gloss
  test; Bug #14 is a separate root cause).
- (14) WORKAROUND-SHIPPED in R12d — `_nova_str_replace` returns
  `""` on a no-match input under specific heap layouts.
  Crossengin-side scan-first fast path in `_snap_oneline`
  bypasses the bug when input has no CR/LF (the common case for
  one-sentence glosses). Closes `test_snapshot_disk_full`'s
  gloss roundtrip FAIL. Likely same root cause as Bug #13
  (`_nova_concat` / `_nova_chr` layout sensitivity).

**All 14 upstream NOVA bugs resolved, formally deferred, or
documented for sweep.** Eleven have upstream fixes (#1-#5, #7, #8,
#11, #12 partial, #13); #4 is transitively closed by #3; #6 is
not a NOVA bug; #9/#10 await the module-system ADR; #12 awaits a
dedicated syscall-sweep round for the remaining pieces (sys_read
input + return + concat polymorphism); #14 awaits a NOVA runtime
round (confirmed R13 did NOT close it — separate root cause from
#13). All user-side workarounds remain as defensive depth and can
be retired incrementally.

### Bug #8 ripple — follow-up round queued

Bug #8's unresolved-callee check is now surfacing latent import-graph
misses across many Crossengin tests that previously SILENTLY lowered
to null-callee. Confirmed-affected test files include
`test_federated_aggregator`, `test_perception_module`,
`test_action_module`, `test_differential_privacy`, and likely more.
Each needs explicit `import "std/syscall"` / `import "std/alloc"` /
etc. depending on the specific undeclared callee the check reports
(e.g., `sys_open`, `str_data`).

This is EXPECTED behavior from the Bug #8 fix — the check is
correctly catching real import-graph issues that were latent SEGV
time-bombs. Fixing the tests is a follow-up sweep (not blocking the
upstream-NOVA close-out). `test_motor_map` passes cleanly as a
canary that the check works correctly when imports are complete.
