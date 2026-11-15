# 00 — Inventory

Audit date: 2026-11-15. Two sibling repositories were audited at the checked-out branch `claude/loving-pasteur-5sndgr` (identical to the latest mainline work in each). Full git history was fetched (the clones were shallow) so archaeology covers first commit → HEAD.

| | **NOVA** (the language) | **Crossengin-demo** ("CE", the MSC system) |
|---|---|---|
| HEAD | `663bf0e` (2026-11-16 commit date) | `78a1dc7` (2026-11-10) |
| First commit | `81868c7` 2026-05-15 | `9a4a092` 2026-05-22 |
| Commits on HEAD (all branches) | 329 (340) | 749 (863) |
| Authors | "Claude" 316, `amoufaq5` 13 (merge commits) | "Claude"/"claude" 711, `amoufaq5` 38 (merge commits) |
| Distinct days with commits | 2026-05: 37 commits, 06: 68 (in shallow window) — active May–Jun, quiet Jul–Sep, bug-fix only Oct–Nov | 76 distinct days; peak 61 commits on 2026-06-03, 52 on 2026-08-02 |
| Tracked files | 597 | 1,412 |
| Licence file | **none** | `LICENSE` — "Proprietary and Confidential" |

Every commit except merges is authored by an AI coding agent ("Claude"); the human account appears only on PR merges. **CONFIRMED** (`git log --format=%an | sort | uniq -c`).

## 1. NOVA — what is in the repo

| Area | Path | Files | LOC | Language | Notes |
|---|---|---:|---:|---|---|
| Compiler | `src/compiler/` | 9 | 34,637 | Nova | `codegen.nova` alone is 24,119 lines; lexer 1,000; parser 5,768; ast 795; ir 486; regalloc 197; lower_x64 684; lower_arm64 772; driver 816 |
| Bootstrap seed | `boot/nova_boot.s` | 1 | 106,045 | x86-64 asm | **Compiler-emitted** (first line `.file 1 "/tmp/nova_combined.nova"`), not hand-written. Last regenerated 2026-05-31 (`e4289df`); 75 compiler commits since |
| Package manager | `src/pkg/` | 1 | 520 | Nova | compiled into the compiler |
| Runtime library | `src/runtime/` | 40 | 11,872 | Nova (+ `llm_bridge.c`, 348 lines C) | alloc, io, scheduler, coroutines, tensor, simd, blas FFI, embedding, llm, python bridge, db … |
| "MSC" core types | `src/core/` | 19 | 7,192 | Nova | moment, signal, node, channel, path, similarity, soul, system, belief, goal, safety, imagination, concept … |
| "Mind" systems | `src/mind/` | 5 | 2,800 | Nova | academic, experiential, emotion, memory, reasoning |
| Agent | `src/agent/` | 4 | 2,151 | Nova | agent REPL, cognitive-LLM pipeline, RAG, preprocess |
| Cognitive library | `src/cognitive/` | 10 | 3,150 | Nova | HDC, SDR, active inference, predictive coding, … (added in one commit `accad2f`) |
| Stdlib / tooling / storage | `src/stdlib`, `src/tooling`, `src/storage` | 7 | 2,122 | Nova | list, float; visualizer/profiler; WAL |
| Editor/debug tooling | `tools/` | ~150 | ~68,000 | **Python** (LSP 35.5k, DAP 24.1k), JS/TS, tree-sitter | larger than the compiler |
| Tests | `tests/` | 215 | 22,361 | Nova + sh | `tests/run_tests.sh` runner |
| Examples | `examples/` | 68 | 6,009 | Nova | |
| Docs | root `*.md`, `docs/` | 43 | ~21,000 | Markdown | `NEXT_SESSION.md` is 8,930 lines |
| Packaging | `packaging/` | 17 | ~700 | deb / pkg / msi / brew | |
| CI | `.github/workflows/` | 1 | 264 | YAML | **release workflow only — no test CI** |

Build system: GNU Make + `as` + `ld` (binutils). No libc is linked into compiled programs. Runtime dependencies of compiled programs: none (direct Linux syscalls). Optional: OpenBLAS, llama.cpp, CPython via FFI (`src/runtime/blas.nova`, `llm.nova`, `llm_bridge.c`, python bridge).

Compiler stages (as built by `Makefile:10-18`): `ast → lexer → parser → ir → regalloc → lower_x64 → codegen → pkg → compiler` concatenated into one 34,385-line source file and compiled as a unit. `lower_arm64.nova` is not part of that build.

## 2. Crossengin-demo — what is in the repo

| Area | Path(s) | Files | LOC | Notes |
|---|---|---:|---:|---|
| Cognition core | `src/substrate, parts, gates, scheduler, kg, mind, learning, seed, sim, preference, perception` | ~146 | ~44,000 | the "MSC substrate", knowledge graph, learning |
| NL / agent / chat | `src/language, reader, nl, agent, agents, chat, skills, capsules, persona, session, ingest` | ~100 | ~32,000 | parsing, intent dispatch, templating, importers |
| Networking / crypto / infra | `src/federation, safety, net, persistence, sandbox, factory, audit, editions` | ~100 | ~66,000 | DTLS, ICE/STUN/TURN, SRTP, Noise, ECDSA, Raft, gossip, snapshots, capability tokens |
| Media I/O | `src/io` | 65 | 47,327 | JPEG/PNG, ORB/HOG/LBP, optical flow, audio DSP, STT glue, HTTP |
| Other src | `src/bench, data, util` | 15 | ~2,700 | |
| **src total** | `src/` | 397 | 187,870 | all Nova |
| Entry points | `examples/` | 23 | 17,482 | `crossengin_chat.nova`, `crossengin_daemon.nova`, MCP, RPC, federation daemons |
| Tests | `tests/unit` 479, `tests/integration` 146, `tests/benchmark` 10 | 635 | ~163,600 | |
| Docs | root `*.md` + `docs/` (193 ADRs) | 277 | ~100,000 | README is 4,590 lines |
| Scripts | `scripts/` | 36 | 7,896 | bash + python (web shim, LLM helper scripts) |
| Web / infra | `web/`, `infra/` | ~25 | ~3,600 | static chat UI, Vercel proxy, TLS configs |
| Data | `data/packs/*.cerec` etc. | 14 | ~1,900 | hand-format knowledge packs |
| CI | `.github/workflows/` | 1 | 84 | build + "10-query fever smoke" (5 exact counters) |

Build: `make NOVA_ROOT=… install` compiles each of 397 modules individually, then 10 binaries from `examples/`. Depends on a sibling NOVA checkout (unpinned).

## 3. Where the lines went (git numstat, lines added, non-merge commits)

**NOVA**

| Month | compiler/lang | MSC/cognitive | runtime | Python tooling | tests | docs |
|---|---:|---:|---:|---:|---:|---:|
| 2026-05 | 135,618* | 15,626 | 12,146 | 1,431 (+11,388 legacy Python interpreter, later deleted) | 14,656 | 12,878 |
| 2026-06 | 15,486 | **0** | 367 | **68,217** | 9,252 | 13,389 |
| 2026-10 | 514 | 0 | 315 | 0 | 324 | 475 |
| 2026-11 | 135 | 0 | 23 | 0 | 188 | 0 |

\* includes the 106k-line generated bootstrap seed.

Commits touching `src/core|mind|agent|cognitive`: **16, all in May 2026; none since.** Commits touching the compiler: 175 across all months. Commits touching `tools/`: 53.

**Crossengin-demo** (lines added, all time)

| Area | Lines added | Share of src+tests+docs |
|---|---:|---:|
| Tests | 165,735 | 32% |
| Docs | 117,411 | 23% |
| Networking / crypto / infra | 66,809 | 13% |
| Media I/O | 48,922 | 10% |
| Cognition core | 42,715 | 8% |
| NL / agent / chat | 34,298 | 7% |
| Entry points | 20,318 | 4% |
| Scripts / infra / web | 14,025 | 3% |

Within `src/` at HEAD: cognition core ≈ 23%, NL/agent/chat ≈ 17%, networking/crypto/infra ≈ 35%, media I/O ≈ 25%.

## 4. Build & test results obtained during this audit (executed, scratch copies)

| Check | Result | Label |
|---|---|---|
| `make bin/nova` from committed seed | OK, 1.6 s | CONFIRMED |
| `make self-host` (stage2.s vs stage3.s) | byte-identical; stage4 also identical modulo the embedded input path; 5 repeat runs deterministic | CONFIRMED |
| `make test` (NOVA quick suite) | **fails** at `test_runtime` ("sys_mmap failed") | CONFIRMED |
| `bash tests/run_tests.sh` (NOVA) | Total 194 / **Pass 157 / Fail 30 / Skip 7** (README claims 176 pass, 6 skip). Same with ASLR disabled | CONFIRMED |
| CE `make install` | 397 modules + 10 binaries compile, 6.5 min | CONFIRMED |
| CE `make test` | 478 files: **475 pass, 3 fail**, 19 min. Two failures LIKELY caused by shared fixed `/tmp` paths during parallel audit runs; one is a 60 s timeout under load | CONFIRMED |

See `coverage.md` for the per-file ledger and `MSC_DUE_DILIGENCE_REPORT.md` for findings.
