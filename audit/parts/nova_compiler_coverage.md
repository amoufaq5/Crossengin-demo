# nova_compiler — coverage table

Reviewer: `nova_compiler`. Scope: NOVA `src/compiler/*`, `src/pkg/*`, `src/stdlib/*`, `src/tooling/*`, `src/storage/*`, `src/version.nova`, `boot/*`, `Makefile`, `build_compiler.sh`, `nova`, `scripts/*`, `VERSION`.

**Row count: 30 files** — matches `git ls-files src/compiler src/pkg src/stdlib src/tooling src/storage src/version.nova boot Makefile build_compiler.sh nova scripts VERSION | wc -l` = 30 (145,138 lines total, of which 106,045 are the generated seed `boot/nova_boot.s`).

"reviewed" = read in full or read all load-bearing parts and exercised by execution. "skimmed" = structure, function inventory and targeted sections read; reason given.

| path | status | LOC | actual status | what it really does |
|---|---|---|---|---|
| NOVA/src/compiler/ast.nova | reviewed | 795 | Working | 71 constructor/accessor functions; every AST node is a plain list `[tag, field..., line]`. Includes `AST_MIND/SOUL/SYSTEM/FLOW` tags. |
| NOVA/src/compiler/lexer.nova | reviewed | 1000 | Working (no diagnostics) | Hand-written byte-at-a-time tokenizer. Emits no errors at all: unknown characters are skipped (`:985`), unterminated strings and overflowing integer literals are accepted silently. |
| NOVA/src/compiler/parser.nova | skimmed (5.7k lines; read error path, type-check pass, program driver, pattern/generic handling; rest inventoried by function) | 5768 | Working | Recursive-descent parser producing list-ASTs; desugars match/patterns/struct-init in the parser; stops at first error (`par_error` → `exit`). Contains a "type-check" pass (`tc_*`, `:4827-5743`) that only prints warnings for literal arguments. |
| NOVA/src/compiler/ir.nova | reviewed | 486 | Dead | Defines 49 IR opcodes, emit helpers and a live-range calculator. Compiled into the binary but never called by the compile path. |
| NOVA/src/compiler/regalloc.nova | reviewed | 197 | Dead | Linear-scan register allocator over IR live ranges. Never called. |
| NOVA/src/compiler/lower_x64.nova | skimmed (dead code; read entry points) | 684 | Dead | IR → x86-64 lowering. Compiled into the binary, never called (`lx_init`/`lx_lower_function` have no caller outside the file). |
| NOVA/src/compiler/lower_arm64.nova | skimmed (dead code; read header + function list) | 772 | Dead | IR → AArch64 lowering. Not in `COMPILER_SRC`, no caller anywhere; only "reachable" as an importable std package name. `--target=arm64` uses a separate AST walker in codegen.nova. |
| NOVA/src/compiler/codegen.nova | skimmed (24k lines; read driver, expr/stmt core, identifier resolution, optimizer entry, classifier/arith/alloc/index/map/float/exit runtime, MSC desugaring, ARM header; the 8.3k-line `gen_runtime` and WASM runtime inventoried by label) | 24119 | Partial | The real compiler back end. AST-walking stack-machine emitter of GAS Intel-syntax text for 6 targets, plus the whole runtime library written as ~7,500 `out("asm line")` calls. Linux x86-64 works with significant bugs (see findings); other targets partial/stub. |
| NOVA/src/compiler/compiler.nova | reviewed | 816 | Working (wrong exit codes) | CLI driver: arg parsing, textual import splicing (imports only honoured at top of file), then `tokenize → parse_program → fold → DCE → gen_program → write_file`. Exits 1 on success paths that call `exit(0)`. |
| NOVA/src/pkg/pkg.nova | reviewed | 520 | Partial | Edits a `nova.pkg` key=value manifest; `install` copies std files from `src/runtime` into `nova_packages/`. No registry, no versions, no remote fetch ("remote packages not yet supported", `:425`). Also holds the hard-coded list of 62 std package names. |
| NOVA/src/stdlib/float.nova | reviewed + executed | 180 | Partial (broken at HEAD) | 17 small float helpers (clamp, lerp, sign, distance…) over builtin `f_*` functions. Not on the import path (must be `cat`-ed). All four functions I executed returned 0.0. |
| NOVA/src/stdlib/list.nova | reviewed + executed | 197 | Partial (broken at HEAD) | 13 list helpers; most are one-line wrappers over builtins (`map_list`, `filter`, `sum`, `list_slice`, `reduce`). Not on the import path. Executed: `sum` gives 12 for [1,2,3,4], `list_take(l,2)` returns 3 elements, because the builtins underneath are wrong. |
| NOVA/src/storage/wal.nova | reviewed + executed | 274 | Partial (test fails at HEAD) | Append-only log file: 20-byte header (magic, seq, len, CRC-32) + payload ≤4096 bytes; sequential reader stops at first bad record; truncate helper. Real code; its test fails at HEAD and is skipped by the runner. |
| NOVA/src/tooling/visualizer.nova | skimmed (library outside compiler path; read function list + export) | 342 | Working (per lead's suite: PASS) | Records node/synapse/signal events in lists; writes an HTML file with inline SVG circles and lines. |
| NOVA/src/tooling/time_machine.nova | skimmed (read replay/record functions) | 328 | Working; name overstates | "Time-travel debugger" = a capped list of snapshot copies indexed by tick. "Replay" copies stored snapshots and overwrites fields; nothing is re-executed. |
| NOVA/src/tooling/kg_visualizer.nova | skimmed | 521 | Partial (its test fails to compile at HEAD) | BFS subgraph extraction over a knowledge-graph list structure; exports HTML/SVG and Graphviz DOT text. |
| NOVA/src/tooling/profiler.nova | skimmed (read tick/section/export functions) | 280 | Working; name overstates | Counts manually-advanced integer "ticks" between `start_section`/`end_section` calls and event counters. No clock, no sampling. "Flamegraph export" writes `name total` lines. |
| NOVA/src/version.nova | reviewed | 14 | Dead | Returns/prints "0.2.0". Referenced by nothing. Disagrees with `VERSION` (0.1.0) and the launcher (0.9.0). |
| NOVA/boot/nova_boot.s | skimmed (generated; verified provenance, symbol set, old classifier) | 106045 | Working (stale seed) | Compiler-emitted assembly of an older compiler, committed as the bootstrap seed. Last changed 2026-05-31; 304 functions vs 479 in today's source. |
| NOVA/boot/Makefile | reviewed | 15 | Working | `as` + `ld` on nova_boot.s. |
| NOVA/Makefile | reviewed | 706 | Working | Three-step bootstrap (seed → stage1 → stage2 = bin/nova), self-host diff, cross targets, smoke targets (most skip silently when toolchains are missing), packaging wrappers. Uses fixed `/tmp/nova_*` paths. |
| NOVA/build_compiler.sh | reviewed | 15 | Dead / stale | Concatenates only 5 of the 9 compiler sources and calls the seed an "interpreter". Superseded by the Makefile. |
| NOVA/nova | reviewed | 107 | Working (minor defects) | Bash launcher: `run`/`build`/`pkg`/`test`/`self-host`/`version`. Hard-codes "v0.9.0"; hides assembler errors; leaks the compiler's "Compiled:" line into program stdout. |
| NOVA/VERSION | reviewed | 1 | Doc | `0.1.0`. |
| NOVA/scripts/build-deb.sh | skimmed (packaging script; read header, version handling, destructive commands) | 149 | Working (unexecuted) | Stages `bin/nova` and runs `dpkg-deb --build`; writes a recipe file instead when the tool is missing. |
| NOVA/scripts/build-msi.sh | skimmed | 135 | Partial (unexecuted) | WiX candle/light wrapper; "recipe-only mode" when WiX is absent. |
| NOVA/scripts/build-pkg.sh | skimmed | 163 | Partial (unexecuted) | macOS pkgbuild/productbuild wrapper; recipe-only on Linux. Placeholder team id `XXXXXXXXXX` (`:94`). |
| NOVA/scripts/sign.sh | skimmed | 115 | Partial (unexecuted) | Wraps gpg / productsign+notarytool / signtool; reads credentials from environment variables; skips when unset. No secrets committed. |
| NOVA/scripts/wgpu_dispatch/Cargo.toml | reviewed | 33 | Working (unexecuted) | Rust crate manifest: depends on `wgpu 0.20`, `pollster`, `bytemuck`. |
| NOVA/scripts/wgpu_dispatch/src/main.rs | skimmed (read header + config parsing) | 361 | Working (unexecuted) | Rust program that runs a WGSL vector-add shader via wgpu and compares with a CPU loop. This Rust sidecar is the whole of Nova's "GPU" support; Nova only writes the shader text and a config file. |

TODO/FIXME/HACK/XXX inventory in scope (excluding the generated seed): **1** hit (`scripts/build-pkg.sh:94`, a placeholder team id). The code base records known defects as prose comments ("Bug #13", "UPSTREAM_NOVA_BUGS §17", "pre-fix") instead: 19 such references in codegen.nova.
