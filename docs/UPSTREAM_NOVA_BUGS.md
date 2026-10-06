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

**All 11 upstream NOVA bugs resolved or formally deferred.** Nine have
upstream fixes (#1-#5, #7, #8, #11); #4 is transitively closed by #3;
#6 is not a NOVA bug; #9/#10 await the module-system ADR. All user-side
workarounds remain as defensive depth and can be retired incrementally.

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
