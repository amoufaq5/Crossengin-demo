# nova_tools_tests_docs — findings

Scope: `NOVA/tools/**`, `NOVA/tests/**`, `NOVA/docs/**`, root `*.md`, `NOVA/packaging/**`, `NOVA/.github/**`, `.gitignore` (421 files; see coverage file).
All execution was done in the scratch copy with the lead's compiler `$S/NOVA/bin/nova` (HEAD `663bf0e`). Probes are in `$S/probes/nova_tools_tests_docs/`.

## Plain-language summary

- The Nova test suite looks large (194 runner tests, ~2,400 assertion calls) but **most of it cannot detect a wrong answer**. The runner only looks at the process exit code. 60 test files have no assertions at all (they print values for a human to eyeball), 70 more rely only on the builtin `assert()`, and that builtin **does nothing when the condition is false** at HEAD (a side effect of the June 2026 value-tagging rework: `false` is now the machine word 1, and `_nova_assert` only fires on machine word 0). 8 more count failures but always exit 0.
- Net: **138 of 194 runner test files (71%) cannot fail on a wrong value**; of the 157 "passing" tests only 34 come from tests that are able to fail. When I re-enabled the dead assertions in a scratch copy, 19 of 58 "passing" test files reported real failures (87 failed assertions), including basic things: enum numbering, list destructuring, closures in `filter`, default parameters.
- The README's "182 tests (176 pass, 6 skip)" was true before the tagging rework. At HEAD it is 194 / 157 / 30 / 7, and the true state is worse than 30 failures because of the dead assertions. A further 10 files in `tests/unit/` (advertised in the README as hundreds of "unit assertions") are not run by anything; 7 of the 10 fail when run by hand.
- The Python tooling is **real and of noticeably better engineering quality than the test suite of the language it serves**: nova-lsp (16k lines, stdlib only) and nova-dap (8.6k lines, drives gdb) both work, and all 30 + 13 of their test scripts pass. The debugger was verified end-to-end against a Nova-built binary. One important LSP function is silently broken: compiler diagnostics never appear, because the LSP's regex does not match the compiler's error format.
- The tree-sitter grammar is real and fairly complete (150/150 corpus tests; parses 355/365 Nova files in this repo and 899/924 in CrossEngin). It is a second, hand-maintained grammar; the TextMate grammar is a third and the LSP's regexes a fourth. None is derived from the compiler's parser.
- There is no REPL and no formatter. `nova pkg` exists but is a local manifest editor for the bundled std modules, not a package manager with a registry.
- Documentation is voluminous (20,880 lines of Markdown) and substantially out of date. Version is stated as 4.2.0, 0.2.0 and 0.1.0 in different places; the bootstrap is described as "handwritten assembly" when `boot/nova_boot.s` is compiler output; the LSP is described as pygls-based when it uses no third-party library; README says "See LICENSE" and no LICENSE file exists.
- There is no formal grammar or spec (the EBNF files were deleted on 2026-05-16). `docs/LANGUAGE_REFERENCE.md` is informal and stale; of 15 documented constructs I compiled, 9 behaved as documented and 6 did not (wrong value, crash, or rejected).
- Packaging (deb/pkg/msi/Homebrew/curl installer) is template-level: the repo has 0 tags and 0 GitHub releases, the Homebrew formula has placeholder checksums, and install URLs point at a GitHub org (`nova-lang`) that is not this repo's origin.
- The `*_AUDIT.md` files are the most honest documents in the repo; they state clearly that macOS was never run on a Mac, Windows only under Wine, WASM is hello-world level, GPU is a Rust shim, and ARM64 is stubbed.
- Process: 316 of 329 commits are authored by "Claude"; work was organised in lettered parallel "rounds" (R1..R61) each logging "0 failed". The June tagging rework was merged with a documented 13 failing tests and a note that `bin/nova` "must NOT be replaced until these clear"; since October the history is ~30 one-line "untag X / tag Y" fixes driven by CrossEngin breakage.

## Findings table

| ID | Sev | Category | Title | File:line | Evidence | Impact | Recommended fix | Effort | Confidence |
|---|---|---|---|---|---|---|---|---|---|
| T-01 | Critical | Tests cannot fail | Builtin `assert()` is a no-op for false conditions | NOVA/src/compiler/codegen.nova:19037-19048 (`test rdi, rdi; jnz .assert_ok`); used by 72 test files, 1,038 calls | Probe `assert(1 == 2, "boom")`, `assert(false,..)`, `assert("a"=="b",..)`, `assert(null,..)` all continue and exit 0. Generated asm passes tagged false = `mov rax, 1`. Mutating `tests/test_closures.nova` expected values to 999 still prints "All closure tests passed!" rc=0 | 70 test files (64 currently "PASS") verify nothing; regressions in core language features are invisible | In `_nova_assert` compare against tagged false (`cmp rdi, 1` / also 0) and exit non-zero; then triage the failures that appear | S (fix) + L (triage) | CONFIRMED |
| T-02 | Critical | Tests cannot fail | 60 of 194 runner tests contain zero assertions | NOVA/tests/run_tests.sh:365-378 (pass = exit code 0); e.g. NOVA/tests/test_add.nova:1-10, test_destructure.nova, test_default_params.nova | `test_destructure` prints `a = 10, b = 10, c = 20` (should be 10/20/30) then "All destructure tests passed!"; `test_default_params` prints `add_with_default(5) = 70362114475905` then "All default param tests passed!" Both PASS | Wrong output is reported as success | Add expected-output files and diff stdout in the runner, or convert to real assertions | M | CONFIRMED |
| T-03 | High | Tests cannot fail | 8 runner tests count failures but always exit 0 | NOVA/tests/test_security.nova (tail), test_system.nova, test_stream.nova, test_soul.nova, test_set.nova, test_guard.nova, test_sys_syntax.nova, test_knowledge.nova | Each ends with `if tests_failed == 0 { println("All ... passed!") }` and no non-zero exit | A failing assertion still yields PASS | `exit(1)` when `tests_failed > 0` | S | CONFIRMED |
| T-04 | High | Stale claim | README test claim "182 tests (176 pass, 6 skip)" is false at HEAD | NOVA/README.md:47, :102, :823; NOVA/ARCHITECTURE.md:121; NOVA/docs/GETTING_STARTED.md:112 | Lead run: 194 total / 157 pass / 30 fail / 7 skip. README states three different counts (182, 170, and 178 in ARCHITECTURE) | Readers are told the suite is green | Generate the number from the runner; do not hand-edit | S | CONFIRMED |
| T-05 | High | Hidden regressions | With assertions re-enabled, 19 of 58 "passing" test files fail | probes `live/summary.txt`; e.g. NOVA/tests/test_enum.nova:11-14, test_closures.nova:6-8, test_secure_random.nova:23 | Substituted a working assert: 87 of 929 assertions fail. Direct probes: `enum D {North,South,East,West}` yields 0,0,1,1; `filter([1..5], fn(x){return x>3})` returns 5 items; `let [a,b]=[7,9]` gives 7,7 | Core features (enums, destructuring, closures-as-predicates, default params, match guards with binding, rest params) are broken at HEAD and nothing reports it | Fix T-01 first, then treat each as a compiler bug | L | CONFIRMED (6 further files inconclusive — harness import artefacts) |
| T-06 | High | Dead tests | `tests/unit/*.nova` (10 files, 658 checks) are run by nothing; 7 of 10 fail | NOVA/tests/unit/test_tuples.nova:60-61 ("glob doesn't pick it up"); NOVA/README.md:24-25 cites them as evidence | Manual run: floats 57 failures (yet rc=0), if_let rc=1, let_destructure panic, match_expr segfault, match_guards segfault, stdlib_list rc=1, tuples 12 failures; closures + 2 poll tests pass | README features R32–R38 (tuples, if-let, match expressions, IEEE floats, list stdlib) are advertised on the strength of tests that now fail | Add `tests/unit` to the runner | S | CONFIRMED |
| T-07 | High | Correctness | `exit(n)` exits with status 2n+1; `nova --version` and `nova --check` exit 1 on success | NOVA/src/compiler/compiler.nova:613-615 (`exit(0)` in check mode) | `exit(0)` → rc 1, `exit(3)` → rc 7; `bin/nova --check ok.nova` prints "OK: syntax check passed" rc=1; `--version` rc=1 | Breaks every script that tests the compiler's exit status (Homebrew formula test at NOVA/tools/Formula/nova.rb:103-106, LSP check path); tests' `exit(1)` shows as "exit code: 3" | Untag the argument in the `exit` shim | S | CONFIRMED |
| L-01 | High | Tooling bug | LSP diagnostics never show compiler errors | NOVA/tools/nova-lsp/nova_lsp/server.py:425-431 (regex wants `file:line:col: error: msg`), :445-484 | Compiler prints `error[line 3]: unexpected }`. Calling `run_compiler_check` on a file with a syntax error returned `[]` | The headline LSP feature that depends on the real compiler is inert; no test covers the real compiler path (tests stub the runner) | Match `error[line N]: msg`; add one integration test that runs `bin/nova --check` | S | CONFIRMED |
| L-02 | Medium | Drift risk | Four independent descriptions of Nova syntax | NOVA/src/compiler/parser.nova; NOVA/tools/tree-sitter-nova/grammar.js; NOVA/tools/vscode-nova/syntaxes/nova.tmLanguage.json; NOVA/tools/nova-lsp/nova_lsp/server.py:599-602 (+ scope_index.py, semantic_tokens.py) | LSP uses regex/line scanning (`FN_DEF_RE`, `LET_DEF_RE`) and a hard-coded table of 152 builtins (server.py:188) vs 189 names in the compiler's `is_builtin_fn` (codegen.nova:2036-2337) | Every language change must be re-implemented in 3 other places by hand; already drifted (builtin list, README says closures "deferred" in tree-sitter while corpus has them) | Have the compiler emit a symbol/AST dump for the LSP; generate the builtin table | L | CONFIRMED |
| D-01 | High | Doc false | "Handwritten assembly bootstrap" is not what is in the repo | NOVA/docs/adr/0002-self-hosting.md:31; NOVA/docs/GETTING_STARTED.md:73; NOVA/README.md:56; NOVA/ANALYSIS.md:60 | `boot/nova_boot.s:2` is `.file 1 "/tmp/nova_combined.nova"` with 3,121 `.loc` directives — it is compiler output. Git: hand-written seed was 2,153→7,379 lines (b95014c..000dbbe), replaced by a 106,045-line self-compiled blob on 2026-05-23 (438e798). README:40 and :773 do say "self-compiled" | The bootstrap cannot be audited or regenerated from a small human-written seed; trust rests on a 106k-line generated file | State it plainly; keep the 7,379-line seed in history as the documented origin, or accept a binary-seed bootstrap and say so | S | CONFIRMED |
| D-02 | Medium | Doc false | Version stated as 4.2.0, 0.2.0 and 0.1.0 | NOVA/README.md:39 (4.2.0); NOVA/src/version.nova:1-8 (0.2.0); NOVA/VERSION:1 and NOVA/src/compiler/compiler.nova:11 (0.1.0); tools/tree-sitter-nova/pyproject.toml:8 (0.0.1) | `bin/nova --version` prints `nova 0.1.0`. ANALYSIS.md:11-47 already documents the conflict | Confusion; "v4.2" implies maturity the project does not have | Use 0.1.0 everywhere | S | CONFIRMED |
| D-03 | Medium | Doc false | "LSP (Python / pygls)" — no pygls anywhere | NOVA/README.md:26; NOVA/docs/IDE_SETUP.md:5, :311; NOVA/docs/adr/0004-lsp-dap-tooling-strategy.md:41-62 | `tools/nova-lsp/pyproject.toml` declares no dependencies; imports are stdlib only; tests ran with pygls not installed | Troubleshooting step "confirm `import pygls` succeeds" sends users the wrong way | Correct the docs (stdlib-only is a plus) | S | CONFIRMED |
| D-04 | Medium | Licence | No LICENSE file; README says "See LICENSE" | NOVA/README.md:1205; NOVA/tools/vscode-nova/README.md:240 | `git ls-files | grep -i license` → only `packaging/macos/resources/license.txt` (MIT text). MIT also declared in pyproject/Cargo/package.json and packaging/debian/copyright | Legally the repo as cloned carries no licence grant at top level | Add a root LICENSE (MIT, matching the scattered declarations) | S | CONFIRMED |
| D-05 | Medium | Doc false | ADR 0002 says self-host equality is a "pre-merge CI gate" | NOVA/docs/adr/0002-self-hosting.md:47-54 | Only workflow is `.github/workflows/release.yml` (tag-triggered, no test job). The ADR also names files that do not exist (`compiler/main.nova`, `register_allocator.nova`, `x86_64_lowering.nova`) | A safety net is documented that does not exist; this is how T-01/T-05 went unnoticed | Add a real CI job: build, self-host diff, run tests | M | CONFIRMED |
| D-06 | Medium | Doc stale | LANGUAGE_REFERENCE does not match the compiler | NOVA/docs/LANGUAGE_REFERENCE.md:23 (floats "stored as 3140"), :79 (named args `host = ...`), :42-43, :52, :182, :320-326 | See spot-check table below: 6 of 15 documented constructs wrong/crash/rejected; reference omits tuples, generics, sum types, if-let, `?`, IEEE floats entirely | The only language reference is unreliable | Regenerate from tested examples | M | CONFIRMED |
| P-01 | Medium | Security / supply chain | Install instructions pipe a script from a GitHub org that is not this repo | NOVA/README.md:121; NOVA/INSTALL.md:58; NOVA/tools/install.sh:17 (`NOVA_REPO` default `nova-lang/nova`); packaging/debian/control:8-9 | Origin is `github.com/amoufaq5/NOVA`. I could not check who owns `nova-lang` (outside session access). install.sh downloads a tarball and installs it with no checksum verification (no sha256 check in the script) | If `nova-lang` is unowned or owned by someone else, the documented one-liner executes their code | Point everything at the real repo; verify sha256 in install.sh | S | CONFIRMED (URL mismatch, no checksum); SUSPECTED (ownership) |
| P-02 | Medium | Unreleased | "Pre-built packages are attached to every tagged release" — there are no tags or releases | NOVA/README.md:117; NOVA/tools/Formula/nova.rb:39,52 (`REPLACE_WITH_RELEASE_SHA256_*`) | `git tag` empty; GitHub API: 0 releases, 0 tags for amoufaq5/NOVA. INSTALL.md:28-32 admits only build-from-source works | Packaging is unexercised templates | Either cut a release or mark as planned | S | CONFIRMED |
| P-03 | Low | Packaging | macOS "install" delivers an unlinked object file | NOVA/tools/install.sh:103-107; NOVA/.github/workflows/release.yml:33-35 | Artifact is `nova_macos.o`; script tells user to link it with clang | Not an installable compiler on macOS | Build on a macOS runner | M | CONFIRMED (by reading) |
| L-03 | Low | Tests | DAP/LSP tests exit 0 on SKIP; most DAP "end-to-end" legs use gcc-built C fixtures | NOVA/tools/nova-dap/tests/test_conditional_breakpoint.py (prints "SKIP — DAP server timeout" and rc=0); tests/fixtures/multi_thread.c | Without `bin/hello_dwarf`, 5 Nova integration legs skip silently; with it, conditional-breakpoint e2e timed out and was reported as SKIP | A broken Nova debug path would not fail the suite | Fail on unexpected skip | S | CONFIRMED |
| X-01 | Low | Proportionality | 58k lines of Python tooling for a language with one known consumer | tools/nova-lsp (16,095 + 18,625 test lines), tools/nova-dap (8,581 + 14,802 test lines) vs src/compiler 34,637 lines | Tooling tests have well over 2,000 live assertions and pass; the language's own tests are mostly inert (T-01..T-03) | Effort went to IDE features (type hierarchy, reverse debugging, profiler) while core language correctness regressed unobserved | Freeze tooling; spend the effort on compiler tests + CI | — | CONFIRMED (numbers); judgement is the reviewer's |

TODO/FIXME/HACK/XXX inventory: tools 18 (all are the literal `/* TODO */` placeholder text that the LSP quick-fix inserts, not unfinished work), tests 0, docs 0, packaging 0, .github 0, root `*.md` 5.

---

## Test quality

### How the runner decides pass/fail
`NOVA/tests/run_tests.sh`: for each `tests/test_*.nova` → compile (60 s timeout) → `as` → `ld` → run (10 s timeout). **PASS iff exit code is 0** (lines 365-378). stdout is discarded on success; there are no golden files and no output diff. One exception: `test_fails_*` must fail to compile and print "undeclared callee" (lines 303-323) — this is the only negative test in the suite. 7 tests are hard-skipped (import, import_lib, fileio, io_random, wal, ffi, ffi_extended; lines 22-33) — so **imports, file I/O and FFI are never tested by the runner**. Many tests are compiled by concatenating `src/` modules into the fixed path `/tmp/nova_combined_test.nova` with `import` lines stripped, so the import mechanism is bypassed even for library tests. `tests/unit/` is not globbed.

### Classification of the 194 runner tests (script: `$S/work_ntd/classify.py`, table `$S/work_ntd/tests.tsv`)

| Class | Meaning | Files | PASS | FAIL | SKIP |
|---|---|---|---|---|---|
| D | No assertions at all: prints values ("golden by eyeball") | 60 | 53 | 2 | 5 |
| A | Only builtin `assert()` — a no-op for false at HEAD | 70 | 64 | 6 (crash / compile error only) | 0 |
| C | User-defined check that counts failures but exits 0 regardless | 8 | 7 | 1 (segfault) | 0 |
| B | Real failure path (non-zero exit on mismatch) | 56 | 33 | 21 | 2 |
| | **Total** | **194** | **157** | **30** | **7** |

- **60 of 194 (31%) contain zero assertions.**
- **138 of 194 (71%) cannot fail on a wrong value** (D + A + C); they fail only if the program crashes or does not compile.
- Assertion calls: 1,038 builtin `assert` (all inert) + 748 calls to user helpers + ~176 inline `if x != y { exit(1) }` checks. Roughly 900 assertions are live; ~1,040 are inert.
- Of the 157 passes, 33 are class B plus the 1 negative compile test → **34 passes carry evidential weight; 123 do not.**
- Class B is concentrated in cognitive/runtime library modules (`assert_test` helper: hdc, sdr, skill, self_model, timeseries, profiler, …) and in tagging regression tests (`test_nova*`, `test_memcpy_raw_tagged`, `test_nanotime_tag`). **Core language feature tests are almost all class A or D.**
- No test compares a value with itself that I found; the weakness is structural (inert assert / print-only), not tautological comparisons.

### Re-enabling the dead assertions (scratch only)
Replaced `assert(` with a working helper in the 64 class-A passing tests: **39 clean, 19 with failing assertions (87 of 929), 6 inconclusive** (my harness broke their relative imports). Failing files: advanced_builtins(4), closures(4), coroutine(7), enum(7 of 8), exhaustiveness(9), exhaustiveness_warn(4), generic_enum(16), is_operator(2), lambda(3), map_comp(1 + segfault), match_expression(1 + segfault), method_calls(2), rest_pattern(3), secure_random(5 of 6), string_utils(9 of 10), struct_brace_init(1), type_check_warn(7), type_match(1), type_name(1).

### `tests/unit/` (not run by anything)
| File | Checks | Result when run by hand at HEAD |
|---|---|---|
| test_closures | 85 | pass |
| test_codegen_poll | 19 | pass |
| test_codegen_wasm_poll | 48 | pass |
| test_floats | 87 | 57 FAIL, exit code 0 |
| test_if_let | 34 | runtime error "index out of bounds", rc=1 |
| test_let_destructure | 39 | panic "expected Box::Of variant", rc=3 |
| test_match_expr | 84 | failures then segfault |
| test_match_guards | 46 | segfault |
| test_stdlib_list | 145 | failures then "index out of bounds" |
| test_tuples | 71 | 12 FAIL, rc=3 |

A 7-line float probe (`let c = 1.5 + 2.25; f_sqrt(16.0)`) segfaults. LIKELY cause for all of the above: features from rounds R31–R38 were not carried through the value-tagging rework.

## Feature coverage matrix

Legend: A = inert builtin assert, B = can fail, C = counts but exits 0, D = print-only; `!` = FAIL at HEAD, `s` = skipped, `u` = unit dir (not run).

| Language feature | Tests | Effective coverage at HEAD |
|---|---|---|
| Integer arithmetic, functions, recursion | add[D], complex[D], smart_ops[D], 7th_param[B], tco[D], ptr_threshold_fix[B!] | Weak (one real test: 7+ params) |
| Bitwise ops | bitwise_assign[B], bitwise_not[B], bitwise_range[D] | Real |
| Compound assignment, multi-assign | compound_assign[A], multi_assign[A] | None |
| Literals (hex/oct/bin/separators), strings, interpolation, multiline | literals[D], numeric_sep[A], strings[D], streq[D], interpolation[D], multiline_strings[D], string_multiply[D], string_utils[A], string_iter[B] | Weak (string_iter only) |
| if/elif/unless/until/loop/while/for, ranges, labeled loops, for-else/while-else | while[D], elif[A], in_unless_until[A], loop[A], for_else[A], while_else[A], for_indexed[D], range[D], range_step[A], inclusive_range[A], labeled_loops[D], break_continue_if[A], ternary_dowhile[A] | None |
| match (statement/expression/guards/if-expr) | match[D], match_guards[D], match_expression[A], match_if_expr[A], unit/match_expr[u!], unit/match_guards[u!] | None; guard-with-binding miscompiles |
| Enums, sum types, exhaustiveness, generics, Result/`?` | enum[A], sum_types[A!], exhaustiveness[A], exhaustiveness_warn[A], generic_enum[A], generic_fn[A!], generic_struct[A], result[A!], try_expr[A] | None; plain enum numbering is wrong |
| Structs, methods, impl, brace-init, update, destructure | struct_methods[D], method_calls[A], impl_blocks[B], struct_brace_init[A], struct_update_syntax[A], struct_destructure[A], struct_const_fold[A], struct_ctor_type_check[A] | Weak (impl_blocks only) |
| Tuples, if-let, let-destructure | unit/tuples[u!], unit/if_let[u!], unit/let_destructure[u!] | None in runner; failing by hand |
| List destructure / rest / spread | destructure[D], rest_pattern[A], spread_call[D] | None; destructure wrong, rest params segfault |
| Lists, slices, negative index, comprehensions, maps, sets | list_comp[D], list_repeat[D], slice[D], negative_index[D], map_list[D], map_literal[D], map_comp[A], map_iter[A], enumerate[A], set[C], unit/stdlib_list[u!] | None |
| Closures / lambdas / fn refs / higher-order | closures[A], lambda[A], fn_ref[D], unit/closures[u] | None in runner |
| Default params, named args | default_params[D], named_args[A] | None; defaults produce garbage |
| try/catch/finally/throw/defer/guard | try_catch[D], try_catch_var[D], finally[D], cross_fn_throw[A], defer[A], guard[C] | None |
| Floats | float[D], ieee754[D], float_utils[B!], unit/floats[u!] | Failing |
| Operators: power, pipe, chained cmp, `??`, `in`/`not in`, `is` | power_op[D], pipe[D], chained_cmp[A], nullish[A], not_in[A], is_operator[A] | None |
| Type annotations / type-check warnings | type_annotations[A], type_check_warn[A], type_match[A], type_name[A], fn_call_type_check[A] | None |
| Coroutines, channels, task pool | coroutine[A], coro_advanced[A!], channel[A], taskpool[A!] | None |
| Optimiser (const fold, DCE, strength reduce) | const_folding[A], dce[A], optimize[B], strength_reduce[B] | Partly real |
| Inline asm, extern, globals, const, keywords | asm[D], extern_fn[D], globals[D], const[A], keywords[A], trailing_comma[A] | None |
| Syscalls / sockets / fork / exec | accept_null_addr[B], udp_syscalls[B], nova7_fork_return[D], nova12_exec_path_argv[B], nova8_store64_zero[A], nova10_sys_read_untag[A], memcpy_raw_tagged[B], nanotime_tag[B], sys_syntax[C], system[C], runtime[B!] | Partly real (recent tagging fixes) |
| Imports, file I/O, FFI | import[s], import_lib[s], fileio[s], io_random[s], ffi[s], ffi_extended[s], ffi_syscall[B!], wal[s] | **None — all skipped or failing** |
| Std modules | json[A], math[A], path[A], csv[B], stdlib[A!], pkg[A], security[C], secure_random[A], stream[C], persistent_alloc[B!] | csv only |
| SIMD / tensor | simd_*[B!]×4, simd_wasm_v128[B], tensor[B!], tensor_perf[B!] | Failing (compile errors) |
| Cognitive modules (not language features) | m7_core[D], m8_mind[D!], m9_fullsystem[B!], mind[B!], scheduler[B!], soul[C], belief[B], goal[B], safety[A], safety_audit[B], imagination[B!], concept[B!], knowledge[C!], hdc[B], sdr[B], skill[B], self_model[B], resonance[B], … | Best-covered area, but 12 failing |
| Cross targets (wasm/windows/arm64) | wasm_basic[D], wasm_features[A], windows[D] + 6 shell scripts that grep emitted asm | Compile-only; nothing is executed on a non-Linux target by the runner |
| Compile errors / diagnostics | fails_unresolved_call (1 test) | One negative test in total |

**Important features with no working test at all:** control flow of every kind; match; enums/sum types/generics; tuples; closures; destructuring; default/named arguments; exceptions/defer; all operators except bitwise; maps/lists/comprehensions; imports; file I/O; FFI; floats; integer overflow / division by zero behaviour; the arena allocator and out-of-memory behaviour; error messages (one negative test); CLI flags (`--check`, `--stats`, `--target`).

## Claims vs reality

| # | Claim | Where | Evidence | Verdict |
|---|---|---|---|---|
| 1 | Self-hosting, stage2.s == stage3.s | README.md:20, :38 | Confirmed by the lead's run | Verified |
| 2 | Version 4.2.0 | README.md:39 | VERSION = 0.1.0; `nova --version` prints 0.1.0; src/version.nova says 0.2.0 | False |
| 3 | "182 tests (176 pass, 6 skip)" / "170 tests (164 pass)" / "178 (172 pass)" | README.md:47, :102; ARCHITECTURE.md:121 | 194 / 157 / 30 fail / 7 skip at HEAD; 71% of tests cannot fail | False |
| 4 | "bootstrapped from handwritten x86-64 assembly"; "stage1: 106,045 lines of handwritten x86-64 assembly" | README.md:56; docs/adr/0002:31; GETTING_STARTED.md:73 | boot/nova_boot.s is compiler output (`.file 1 "/tmp/nova_combined.nova"`, 3,121 `.loc` lines); hand-written seed (≤7,379 lines) was replaced 2026-05-23 | False (true historically for a 7k-line seed) |
| 5 | Bootstrap "106,045 lines (self-compiled)" | README.md:40 | `wc -l boot/nova_boot.s` = 106,045 | Verified |
| 6 | Bootstrap "interprets Nova source code" | README.md:773-774 | It is the compiled compiler, not an interpreter | False |
| 7 | Compiler "16,467 lines of Nova"; parser 2,305; codegen 10,799 | README.md:41, :694-701 | src/compiler = 34,637 lines; parser 5,768; codegen 24,119 | False (stale, understated) |
| 8 | Compiler "~27,873 lines" | ARCHITECTURE.md:17 | 34,637 | False (stale) |
| 9 | "Total Nova ~68,000 lines" | README.md:46 | src/**/*.nova ≈ 64,100; all .nova incl. tests/examples = 90,531 | Partially true |
| 10 | "Zero dependencies. No libc." | README.md:5 | Linux build needs only `as`+`ld` (true). But: Windows target links msvcrt/kernel32 via mingw (WIN32_AUDIT.md:166-172); FFI path uses `gcc -ldl` (Makefile `ffi` target); README itself advertises OpenBLAS, a Python bridge and a llama.cpp C bridge (README.md:179, :210-211; src/runtime/llm_bridge.c); GPU uses a Rust wgpu shim; packaging/debian/control:6 `Depends: binutils, libc6` | Partially true (core Linux path only) |
| 11 | "No C compiler. No package manager. No downloads." | README.md:818 | True for `make` on Linux; ANALYSIS.md:104 lists GCC as needed | Partially true |
| 12 | Targets: Linux x86-64, Windows x86-64, macOS x86-64, WASM, Linux ARM64, Windows ARM64 | README.md:30, :48 | All six emit assembly for a hello program (probe). STABILITY_AUDIT.md:91-97: Windows "Wine-only", macOS "no real-Darwin run", WASM "HELLO-WORLD", ARM64 "STUBBED". ARM64 lists/file I/O stub to exit(1) (codegen.nova:7085, :7307-7319) | Partially true (emit ≠ supported; only Linux x86-64 is tested) |
| 13 | "270+ built-in functions" | README.md:64, :888 | `is_builtin_fn` has 189 distinct names (codegen.nova:2036-2337); LSP table lists 152; 270 only by counting library functions | Partially true |
| 14 | "Zero dynamic dispatch -- all types resolved at compile time" | README.md:802 | Values are dynamically tagged; operators and `type_of` check tags at run time (codegen.nova:19053-19075); "Type annotations (documentation-level)" README.md:258 | False |
| 15 | "full IEEE 754 double-precision" floats | README.md:25 | Float probe segfaults; unit/test_floats 57 failures; README.md:255 simultaneously says "fixed-point floats (3.14 stored as 3140)" | False at HEAD (and self-contradictory) |
| 16 | Tuples, if-let, match expressions, closures, list stdlib "landed" with N unit assertions | README.md:20-24 | The cited unit tests are not run and 6 of 7 fail by hand | Unsupported / regressed |
| 17 | "LSP (Python / pygls)" | README.md:26; ADR 0004 | stdlib only | False |
| 18 | LSP "18 capabilities", DAP "23 capabilities" | README.md:304-305 | Both servers work; all 43 test scripts exit 0 (LSP scripts report ≈1,900 assertions in total; four DAP scripts alone report 141, 100, 211 and 309). Capability count not individually checked; LSP diagnostics are broken (L-01) | Partially true |
| 19 | tree-sitter: "108 corpus tests pass; 242/247 (98.0%) parse" | README.md:333-336 | 150/150 pass; 355/365 (97.3%) of NOVA .nova files parse clean | Verified (numbers stale but accurate in spirit) |
| 20 | tree-sitter "closure literals (R35C) deferred" | README.md:28 | corpus `r35_closures.txt` exists and passes | False (stale, understated) |
| 21 | "Pre-built packages are attached to every tagged release" | README.md:117 | 0 tags, 0 releases | False |
| 22 | `curl … nova-lang/nova … | sh`, `brew tap nova-lang/nova` | README.md:121-129 | Origin is amoufaq5/NOVA; no release to download; formula checksums are placeholders | False |
| 23 | "make examples # Build and run all 29 examples" | README.md:825 | 68 files in examples/ | False (stale) |
| 24 | `--check` syntax validation | README.md:108, :295 | Works, but exits 1 on success | Partially true |
| 25 | Package manager `nova pkg init/install/build` | README.md:300 | `pkg init` writes a manifest; `pkg install foo` → "Nothing to install."; registry is the bundled std list (src/pkg, 520 lines) | Partially true |
| 26 | "Self-host invariant is a pre-merge CI gate" | docs/adr/0002:47-48 | No CI besides the tag-triggered release workflow | False |
| 27 | "Tiny binaries" | README.md:811 | hello_dwarf = 48 KB static ELF; compiler = 1.0 MB (debian/control:17 says ~700KB) | Verified (roughly) |
| 28 | SIMD / matmul "3-5x", BLAS "matching NumPy", retrospective "5.5x / 137x" | README.md:806-807; RETROSPECTIVE:22-25 | No benchmark outputs stored in repo; 4 of 5 SIMD tests fail to compile at HEAD; not run by me | Unsupported |
| 29 | GPU compute backend | GPU_AUDIT.md:8-16 | Nova emits a WGSL string; a separate Rust program (`scripts/wgpu_dispatch`) does the GPU work; skips with no adapter | Partially true (as the audit itself says) |
| 30 | Mobile (iOS/Android) | MOBILE_AUDIT.md:3-10 | Audit: codegen "stubbed", ships hand-written reference `.s` files | Unsupported as a feature (audit is honest) |
| 31 | DWARF debug info | README.md:303 | objdump shows a line table; gdb/DAP stopped at `main` line 30 and listed 5 locals | Verified (Linux ELF) |
| 32 | "License: See LICENSE" | README.md:1203-1205 | No LICENSE file | False |
| 33 | "Ownership model and type system" | first commit message 81868c7 only | Belonged to the deleted Python implementation; no ownership model exists at HEAD; types are advisory | Unsupported (not claimed in current docs) |
| 34 | `git clone https://github.com/nova-lang/nova.git` | INSTALL.md:42 | Not the origin | False |

## Tools

| Tool | Real? | Evidence |
|---|---|---|
| nova-lsp (`tools/nova-lsp`, 16,095 lines + 18,625 test lines) | Working, with one broken core function | Stdlib-only JSON-RPC server. 30/30 test scripts exit 0 (they are plain scripts with `assert`, not pytest; pytest is not needed or installed). Analysis is regex/line-scan plus small hand-written scanners (scope_index.py, semantic_tokens.py) — its own approximate re-implementation of Nova syntax, not the compiler's parser. Diagnostics path broken (L-01). |
| nova-dap (`tools/nova-dap`, 8,581 + 14,802) | Working | Translates DAP to gdb MI3. 13/13 scripts exit 0. With a Nova-built `bin/hello_dwarf`: dap_smoke stops at `main` line 30 and shows 5 variables; data/function breakpoints and instruction stepping pass on the Nova binary; conditional-breakpoint e2e timed out and reported SKIP. Requires gdb (GPL, external process). |
| tree-sitter-nova | Working | `tree-sitter generate` OK; 150/150 corpus tests; 10 of 365 NOVA files and 25 of 924 CrossEngin files produce ERROR nodes. Generated `src/parser.c` is git-ignored, so the Node/Rust/Python/Go/Swift bindings do not build from a clean checkout. |
| vscode-nova | Partial / unverified | Manifest and TextMate tests pass; VSIX build needs `npm install` (timed out here). Not published. |
| Package manager (`nova pkg`) | Partial | Manifest editor over a hard-coded std list; no fetching. |
| REPL | Does not exist | — |
| Formatter | Does not exist (one existed in the Python interpreter deleted in dfa5a2f) | — |
| Formula / install.sh / release-dry-run | Templates | See P-01..P-03. |

Proportionality (facts only): Python tooling totals 58,103 lines (24,676 implementation + 33,427 tests) against a 34,637-line compiler. The tooling's tests are live and green; the compiler's are mostly inert. The only known consumer of the language is the sibling CrossEngin repo.

## Language reference spot-check (docs/LANGUAGE_REFERENCE.md)

There is no formal grammar/spec. `docs/grammar.ebnf` and `grammar_v2.ebnf` were deleted on 2026-05-16 (dfa5a2f). The nearest thing to a grammar is `tools/tree-sitter-nova/grammar.js`.

| # | Construct (reference line) | Result at HEAD | OK? |
|---|---|---|---|
| 1 | hex/octal/binary/separators, `${}` interpolation (:19-27) | `255 511 10 1000000`, `x = 5` | Yes |
| 2 | "Float (fixed-point): 3.14 stored as 3140" (:23) | `print_int(3.14)` prints `2307126535107494543` | No (doc stale) |
| 3 | `let [a, b] = [1, 2]` (:42) | a=1, b=1 (`[7,9]` → 7,7; three elements → 10,10,20) | **No — wrong values** |
| 4 | Rest parameters `fn f(label, ...args)` (:52) | Segfault | **No** |
| 5 | Spread call `f(...nums)` (:62) | 60 | Yes |
| 6 | Default parameter `timeout = 30` (:75) | `connect("h", 8080)` returns 8080 (default not applied) | **No — wrong value** |
| 7 | Named args `connect(host = "localhost", …)` (:79) | Parse error "expected ) but got ="; the `name: value` form works | No (doc wrong) |
| 8 | `|x| x * 2`, block lambda, implicit return (:81-88) | 8, 3, 42 | Yes |
| 9 | if-expression, unless, until, do-while (:109-128) | correct | Yes |
| 10 | for-else, labeled break, `0..=10`, `range_step`, while-else (:137-170) | correct | Yes |
| 11 | match with `x if x > 10 =>` guard (:182) | `f(50)` prints "other" | **No — wrong branch** |
| 12 | match as expression (:186-190) | "Not Found" | Yes |
| 13 | try/catch/finally, throw, defer, guard (:197-219) | correct | Yes |
| 14 | `**`, chained comparison, ternary, `??`, `~`, string repeat, `in`/`not in`, pipe (:225-280) | correct | Yes |
| 15 | `enum Color { Red, Green, Blue }` (:320-326) | Red=0, Green=0, Blue=1 | **No — wrong values** |
| + | Struct ctor, field assign, method sugar (:303-314) | correct | Yes |
| + | Map literal `{a: 1, b: 2}` then `map_get(m,"b")` (:28) | 0 with bare keys; 2 with quoted keys; `m["b"]` segfaults | Partly |
| + | `[x * x for x in range(5)]` (:536) | exits 1 with no output | No |

## What the *_AUDIT.md files admit

- **GPU_AUDIT.md** — "minimum viable": Nova only writes a WGSL shader string; a standalone Rust shim does dispatch. No SPIR-V, no buffer pool, no async, no i64/f64, no CUDA path, no browser path, no timing queries, no device selection (:189-221). Skips when no adapter is present, which was the case in its own sandbox (:18-23).
- **SIMD_AUDIT.md** — Linux x86-64 only; no AVX2 runtime detection (SIGILL on older CPUs); int32 only; no bounds checking; cross-target callers get wrong-ABI code silently (:139-160).
- **WASM_AUDIT.md** — float-to-string approximate; string ops untested beyond hello-world; no FFI (silently emits ELF-shaped output); wasmtime not available when written; smoke only runs if `WASM_OK=1` (:154-172).
- **WIN32_AUDIT.md** — `fork` child semantics do not work; `setsid` returns -1; only `kill -9` supported; WSACleanup never called; **"Real-Windows verification has NOT been performed; only Wine"** (:164-185). Uses msvcrt.
- **MACOS_AUDIT.md** — binary "cannot" be run in the sandbox; sockets/fork/exec/time/sleep "unverified"; no real Darwin run (:12, :79-90).
- **MOBILE_AUDIT.md** — ARM64 codegen "stubbed: it crashes on any non-trivial input"; the smoke targets ship hand-written reference assembly; no file I/O; no Xcode/NDK integration (:3-10, :125-136). (Slightly out of date: ARM64 now emits real code for simple functions.)
- **DWARF_AUDIT.md** — every variable typed as `int`; no `.debug_str`; no Windows CodeView; macOS DWARF and ARM64 debug info deferred; WASM source maps out of scope (:67-80).
- **STABILITY_AUDIT.md** — target matrix: Windows "PRODUCTION (Wine-only)", macOS "MINIMUM VIABLE", WASM "HELLO-WORLD", ARM64 "STUBBED"; no machine-readable builtin arity contract; "unverified syscall paths: mapped but untested" (:83-100, :158-166).

None of these audits mentions the inert `assert` or the exit-status bug; they predate the tagging rework.

## Development process and drift (NEXT_SESSION.md, RETROSPECTIVE, git log)

- 329 commits, 2026-05-15 → 2026-11-16; **316 authored by "Claude <noreply@anthropic.com>"**, 13 by the owner (PR merges). 171 commits in May, 119 in June, none July–September, 39 in Oct–Nov.
- Day 1 was a Python interpreter with an EBNF grammar, "ownership model and type system" (81868c7); rewritten as a "cognitive architecture language" next day (dfa5a2f); assembly seed and self-hosting within three days (b95014c, 1ca6462); Python implementation deleted 2026-05-19 (47f68a1).
- NEXT_SESSION.md (8,930 lines) is a reverse-chronological hand-off log between AI sessions, organised as rounds R9…R38 with parallel lettered tracks (A = compiler, B = tree-sitter, C–F = CrossEngin/LSP/DAP). RETROSPECTIVE describes "cross-agent coordination patterns" and a rule that tooling rounds land one round after parser rounds. Branch names such as `claude/festive-franklin-PP7mW` appear in the audits.
- Every round entry reports the suite as "N passed / 0 failed / 6 skipped" (NEXT_SESSION.md:1561, :5262, :7963 …). Those numbers were produced by a runner in which most assertions were print-only even then; after tagging, also inert.
- Known-bug list (NEXT_SESSION.md:8334-8375): 7th-parameter bug (fixed), `char_at` "broken", `map_new()` "16-slot limit causes infinite loops; use parallel lists", `soul` reserved, `none` keyword unusable in runtime modules.
- The pivotal event is the **value-tagging rework (2026-06-13/16)**, undertaken to fix integers ≥ 1 MB (later ≥ 16 GiB) being mistaken for pointers (NOVA_BUG_THRESHOLD.md). docs/PTR_TAGGING_PLAN.md:171-190 records "164 pass / 13 fail" and "`bin/nova` must NOT be replaced until these clear". It was merged anyway. From 2026-10-05 the log is ~30 commits of the form "untag X before syscall / tag return of Y (closes Crossengin UPSTREAM §N)", i.e. bugs are being found one at a time by the downstream project rather than by Nova's tests.
- Drift: effort after mid-May went increasingly to breadth (six targets, GPU, mobile, packaging for four OSes, 40+ IDE features, ADRs for a storage engine and Raft consensus — docs/adr/0007, 0008) while the single thing that protects all of it — a test suite that can fail, run by CI — was never built.

## Packaging and release

- `packaging/debian`, `packaging/macos`, `packaging/windows`, `packaging/homebrew`, `tools/Formula/nova.rb`, `tools/install.sh`: coherent, plausible templates. None has produced a published artifact: `git tag` is empty and the GitHub API reports 0 releases and 0 tags for amoufaq5/NOVA.
- `.github/workflows/release.yml` only triggers on `v*` tags or manual dispatch, so it has never been required to pass; it has no test job.
- Formula checksums are literal placeholders (nova.rb:39, :52); its `test do` block would fail because `nova --version` exits 1 (T-07).
- Maintainer e-mail `maintainers@nova-lang.org` and URLs under `github.com/nova-lang/…` appear throughout packaging; ownership of that org/domain is unverified.

## Licence and third-party code

- No root LICENSE. MIT text exists only in `packaging/macos/resources/license.txt` and `packaging/debian/copyright`; MIT is declared in the pyproject/Cargo/package.json manifests. Copyright line says "2025-2026 The Nova Project" although history begins 2026-05-15.
- No vendored third-party source or `node_modules` in my area. `tools/tree-sitter-nova/bindings/**`, `binding.gyp`, `Package.swift`, `setup.py`, `Makefile` are the standard scaffolding generated by the tree-sitter CLI (MIT) — LIKELY verbatim template output with the language name substituted.
- Dependencies: nova-lsp and nova-dap — Python stdlib only (nova-dap shells out to gdb, GPL, as a separate process). vscode-nova — `vscode-languageclient` (MIT) plus dev-only TypeScript/eslint/vsce (MIT/Apache-2.0/BSD). tree-sitter-nova — tree-sitter runtime (MIT).
- Outside my area but stated in the docs I reviewed: `src/runtime/llm_bridge.c` (llama.cpp bridge), `src/runtime/python.nova`, `src/runtime/blas.nova` exist and are advertised in README.md:179, :210-211.

## Executed / not verified

Executed: 25 Nova probes; mutation test of test_closures; live-assert rerun of 64 tests; 10 unit tests by hand; 7 class-C tests; all 30 LSP and 13 DAP test scripts (DAP also with a Nova-built hello_dwarf); `run_compiler_check` against a syntax error; tree-sitter generate/test/parse over NOVA and CE; hello program for all six `--target` values (compile only); `nova pkg init/install`; GitHub API release/tag listing.

Not verified: ownership of `nova-lang` GitHub org / nova-lang.org; VSIX build; any non-Linux binary actually running; SIMD/GPU performance figures; LSP/DAP capability counts; the 6 inconclusive live-assert files (json, math, path, pkg, channel, nova10). I did not read every line of the Python tooling or of NEXT_SESSION.md — both were skimmed and exercised through their tests.
