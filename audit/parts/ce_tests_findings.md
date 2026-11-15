# ce_tests findings — CrossEngin tests, benchmarks, data, CI, build and LLM scripts

Reviewer: `ce_tests`. Scope: `CE/tests/**`, `CE/bench/**`, `CE/data/**`, `CE/Makefile`, `CE/nova-deps.toml`, `CE/.github/**`, 19 scripts. Probe programs and raw outputs are in `$S/probes/ce_tests/`.

## Plain-language summary

The unit-test suite is large and, for what it tests, real: 478 files, 21,340 assertions, none empty, every file imports the shared harness and ends in `ce_summary`, and the runner correctly turns any failed assertion into a failed test. About 82% of the public functions in `src/` are named in at least one unit test. The tests I read by hand set up a tiny fixture of two to six hand-made items and check a value worked out by hand, so they are honest tests of small mechanisms.

What the suite does not contain is any measurement of the thing the project claims. There is no test or benchmark that scores the cognitive system on a task against held-out data, a baseline (lookup table, keyword search, LLM) or a learning curve on unseen inputs. The benchmarks measure speed of data-structure operations. The one "reasoning benchmark vs LLM" has 12 items whose proofs are written into the benchmark, and the "LLM" side is verdicts the author invented. The two "learning" benchmarks are tabular Q-learning on a 5x5 grid and a delta rule memorising a 3-step repeating sequence.

CI runs none of the 478 tests. It builds the binaries and checks five exact counters after typing "fever" ten times ("fever" is the query word, not the FEVER dataset). I reproduced those five numbers exactly; they are a determinism check, and two of the modules behind them have no unit test at all. CI builds NOVA from an unpinned default branch using the build target the project's own ADR calls flaky.

"Learning from the internet" (`scripts/learn.sh`) is `curl` plus word-frequency counting plus an awk pattern match; I confirmed it turns "Fever is not infection" into the fact `fever is_a infection`. Three other scripts call an LLM (Ollama by default, llama.cpp or the OpenAI API optionally) to extract facts, classify questions and reword replies. The docs disclose this, but it is in tension with "non-LLM" as a headline.

One re-run benchmark was killed by the kernel at 13.6 GB of memory on a 1,000-atom graph.

## Findings table

| ID | Sev | Category | Title | File:line | Evidence | Impact | Recommended fix | Effort | Confidence |
|---|---|---|---|---|---|---|---|---|---|
| T-01 | Critical | Evidence | No task-performance evaluation exists anywhere | `CE/tests/benchmark/*`, `CE/src/bench/*`, `CE/BENCHMARKS.md:1-190` | Every benchmark is latency/throughput or a self-built toy (table below). No dataset, no held-out split, no baseline system. grep for dataset names/accuracy metrics in tests and docs finds only `reasoning_bench`/`calibration` | The AGI/"cognition" claim has zero supporting measurements; nothing would detect it being false | Build one small held-out QA set over the shipped packs; score the system against keyword lookup and an LLM; publish the numbers whatever they are | M | CONFIRMED |
| T-02 | Critical | Fake result | "Head-to-head vs LLM" uses invented LLM answers | `CE/src/bench/reasoning_bench.nova:356-382`, `CE/data/llm_baseline_sample.txt:1-40`, `CE/docs/adr/0086-truth-seeking-reasoning-engine.md:200-204`, `CE/examples/crossengin_chat.nova:2755-2757` | `bench_default_pairs` hard-codes the LLM to affirm every unprovable item except id 7. The data file header says "PLAUSIBLE, RECORDED transcript -- the verdicts a capable LLM emitted" and also "Illustrative". ADR reports "engine 11/11 … illustrative LLM 8/11 with 3 false-confident"; chat `/vs` prints it | A user running `/vs` sees a scoreboard where the engine beats an LLM that was never run. The strawman has an LLM asserting a bare atom `z` with no premises | Remove `/vs` output until a real transcript exists; delete "RECORDED" from the header; record real model outputs with model name and date | S | CONFIRMED |
| T-03 | High | Evidence | Reasoning benchmark supplies the proofs it then "finds" | `CE/src/bench/reasoning_bench.nova:59-63,169-228`; `CE/src/bench/bench_bank_ext.nova` | Each item carries its own `proof` field (`pf_mp(q, pf_axiom(pq), pf_axiom(p))`); `bench_verdict` only calls `verify_check`. Items with `proof == 0` are "refused" by an `if` | Measures that a proof checker accepts valid proofs and rejects invalid ones on 12 (+~25) author-written items. It does not measure reasoning, search or question answering; "accuracy 1000 milli" is by construction | Rename to "proof-checker soundness self-test"; a real benchmark must have the engine produce the derivation from the question | S | CONFIRMED |
| T-04 | High | CI | CI runs no tests | `CE/.github/workflows/build-and-smoke.yml:47-84` | Steps: checkout, NOVA `make`, `make install`, 10x "fever" smoke, five `grep -qE` asserts. No `make test`, `integration`, `coverage`, `lint-ints`, `benchmark` | 478 unit tests and 130 integration scripts never gate a merge; regressions only surface if someone runs them locally | Add `make test` (about an hour serial on this machine, so shard it) and `make coverage`/`lint-ints` | S | CONFIRMED |
| T-05 | High | Reproducibility | NOVA toolchain unpinned everywhere | `CE/.github/workflows/build-and-smoke.yml:27-31`, `CE/.devcontainer/setup.sh:25`, `CE/scripts/bootstrap.sh:32-41`, `CE/nova-deps.toml:15-18` | CI checks out `amoufaq5/NOVA` with no `ref:`; devcontainer does `git clone --depth 1`; bootstrap only tells the user to clone. `nova-deps.toml` "pins" `version = "0.2.0"` but no tool reads the file | A CE commit cannot be rebuilt later against the compiler it was written for; CE depends on specific NOVA fixes (PRs #14-18, `db34532`) | Pin a NOVA commit SHA in CI and devcontainer (or a submodule); make `check-nova` compare it | S | CONFIRMED |
| T-06 | High | Reproducibility | CI uses the NOVA build target the project documents as flaky | `CE/.github/workflows/build-and-smoke.yml:33-45` vs `CE/docs/adr/0100-nova-bootstrap-setarch-workaround.md:10-14`, `NOVA/Makefile:28-34` | CI runs plain `make`; ADR-0100: plain targets "are **flaky under ASLR**", use `bootstrap-setarch` | CI likely fails intermittently for reasons unrelated to the change | Use the `*-setarch` targets in CI and `setup.sh` until the compiler bug is fixed | S | LIKELY (not run on GitHub) |
| T-07 | High | Correctness | `learn.sh` records negated sentences as positive facts | `CE/scripts/learn.sh:320-323` (bridge list contains `not`), `:369-374` | Probe input "Fever is not infection. Water is not poison. The earth is not flat. Vaccines never cause autism." produced `fever|is_a|infection`, `water|is_a|poison`, `earth|is_a|flat`, `never|causal|autism` | The internet-learning path writes the opposite of what the source says into the knowledge graph | Remove `not` from the bridge set; drop any window containing a negator | S | CONFIRMED (executed) |
| T-08 | High | Performance | NL latency benchmark is OOM-killed at 13.6 GB | `CE/tests/benchmark/bench_nl_verbs.nova`; `CE/docs/adr/adr-0208-latency-and-inference-budget.md:47-58` | Re-run: 6 of 10 phases printed, then SIGKILL; `dmesg`: `anon-rss:13674240kB`. Measured `rpc_nl_ask_research` median 21 ms, p99 1,022 ms against a 500 ms p99 budget; `nl_execute_scoped_ex` p99 1,033 ms | A few hundred queries on a 1,000-atom graph exhaust 13 GB: memory is never reclaimed on this path. `make bench-nl` cannot complete; a long-running daemon would die | Profile allocation per query; fix or document the leak; commit a real baseline | M | CONFIRMED (executed; other reviewers shared the memory limit, but the process itself held 13.6 GB) |
| T-09 | Medium | Evidence | CI "invariants" are golden numbers; two of the modules have no unit test | `CE/.github/workflows/build-and-smoke.yml:78-83`, `CE/scripts/coverage.sh` output | Reproduced twice: `mc_hits=9 mc_misses=1 ff_goodness=486000 synapse_mean_weight=300 ia_proto_strength_unknown=10`. `coverage.sh` lists `src/parts/episodic/moment_cache.nova` and `src/nl/intent_adaptive.nova` as uncovered. The asserted intent for "fever" is `unknown`; the reply all ten times is "infection leads to headache (infection->symptom->fever->headache)." | The check proves the program is deterministic, not that it is right; `ia_proto_strength_unknown=10` pins a counter for failing to classify the query | Keep as a regression check, name it so; add behavioural unit tests for the two modules | S | CONFIRMED (executed) |
| T-10 | Medium | Benchmark validity | Throughput benchmarks print the loop count as the rate | `CE/tests/benchmark/bench_node_throughput.nova:19-22,52-62`, `bench_tick_rate.nova:18-21`, `bench_kg_query.nova` | Clock is `time()` (1 s resolution); `safe_div` returns the numerator when elapsed is 0. Re-run: "integrations/sec 768000" (= 96 x 8000), "ticks/sec 60000" (= ticks), "inserts/sec 3000" with "elapsed(s) 0" | The published "hundreds of thousands of ticks/sec" style figures (`CE/docs/adr/r36f-0001-language-choice-nova.md:21`) are iteration counts, not measurements | Use `nanotime()` (works on this host) and report ns/op | S | CONFIRMED (executed) |
| T-11 | Medium | Benchmark rot | `bench_predictive_coding` no longer compiles; `make benchmark` cannot fail | `CE/tests/benchmark/bench_predictive_coding.nova:17-19`, `CE/Makefile:206-211` | Re-run: `ERROR: undeclared callee: sys_open`, rc=1. Makefile pipes each run through `grep -v`, discarding the exit status | The benchmark cited by ADR-0052 as evidence the loop "is learning" is dead, and nothing reports it | Fix the import; propagate exit codes | S | CONFIRMED (executed) |
| T-12 | Medium | Test quality | Tests that pass by skipping | `CE/tests/unit/test_chat_state_persistence.nova:772-784`, `test_decision_log_durable.nova:219`, `test_action_module.nova:586`, `test_dr_async_fetch.nova:585-586`, `test_vosk_backend.nova:255,265`, `test_jpeg_decode.nova:590`, `test_kg_rss_ingest.nova:285` | Pattern: probe `/tmp` write or socket; on failure `ce_check("… skipped cleanly", 1)` and return. 96 unit files and 49 of 130 integration scripts contain a skip path | In a restricted environment a whole persistence/network suite reports PASS with one assertion; pass counts overstate what ran | Print `SKIP` and have `test.sh` count skips separately | S | CONFIRMED |
| T-13 | Medium | Test quality | 16 test files assert that stubs return their stub value | `CE/tests/unit/test_nat_traversal.nova:209-213`, `test_stt_seam.nova`, `test_dtls12.nova`, `test_jpeg_decode.nova:17-18` | "hole punch returns 0 (not implemented)"; JPEG test expects the "entropy decode TODO" error; 44 such assertions | Green tests for features that do not exist; the feature count looks larger than it is | Mark these as pending in the summary | S | CONFIRMED |
| T-14 | Medium | Security | `learn.sh` topic becomes a file path and URL unsanitised | `CE/scripts/learn.sh:270-275,277-278`; called from chat at `CE/examples/crossengin_chat.nova:1645-1648` | `TAG="$TOPIC"`, `OUT="/tmp/crossengin_learn_${TAG}.txt"`, `URL=".../wiki/$TOPIC"`. A topic such as `a/../../home/u/x` writes outside `/tmp`; `?`/`#` alter the URL. Quoting prevents shell injection | Path traversal on write via `/learn_prepare <topic>` (gated by a capability prompt); predictable `/tmp` names allow symlink clobbering on shared machines | Pass topic through `_tag_sanitise`; URL-encode; use `mktemp -d` | S | CONFIRMED by reading (not exploited) |
| T-15 | Medium | Reproducibility | Fixed `/tmp` filenames make parallel builds and tests race | `CE/Makefile:187-194,244-321` (`/tmp/ce_build_check.bin`, `/tmp/ce_build.log`, `/tmp/ce_install.log`), `CE/tests/integration/_lib.sh:27` (`/tmp/crossengin.default.snap`), 39 unit tests, 109 of 130 integration scripts | Only one integration script uses `mktemp` | `make -j`, two checkouts, or two CI jobs on one host corrupt each other; integration tests delete the user's default snapshot | Use `mktemp`/`$TMPDIR` and `CE_SNAP_PATH` consistently | M | CONFIRMED |
| T-16 | Medium | Coverage | "Coverage" is import reachability and currently fails | `CE/scripts/coverage.sh:4-8`; `CE/Makefile:198-203` | Re-run: `covered: 385 uncovered: 12 total: 397`, exit 1. Uncovered includes `cowork_planner`, `kg_router`, `moment_cache`, `intent_adaptive`, `cap_session`, `safety_log`, `approval_prompt`, `mcp_server_stdio`, `ollama_spawn`, `reply_composer_ollama` | A module counts as covered if a test imports anything that imports it; no line or branch coverage exists in either repo | Report it as "import reachability"; add tests for the 12 | S | CONFIRMED (executed) |
| T-17 | Medium | Disclosure | LLM dependence sits beside a "non-LLM" headline | `CE/scripts/llm_extract.sh:27-38`, `llm_compose.sh:49-50`, `nl_parse_llm.sh`, `CE/examples/crossengin_chat.nova:1701-1707`, `CE/src/nl/nl_llm_sidecar.nova:102-112`, `CE/src/nl/reply_composer_ollama.nova:42-43` | Default model `llama3.2:3b-instruct` via Ollama; optional `llama-cli`; optional `curl $OPENAI_BASE_URL/chat/completions` with `$OPENAI_API_KEY` | When enabled, an LLM decides what facts enter the graph (after review), which intent a question has, and the final wording. All three are opt-in and fall back cleanly; `CE/docs/USER_GUIDE_DEPLOY_DATA_COMPARE.md:285-292` describes this honestly | State in the README that fluent replies, open-text understanding and bulk fact extraction use an LLM when available | S | CONFIRMED |
| T-18 | Low | Security | User text can inject wire records past the LLM classifier | `CE/scripts/nl_parse_llm.sh:239-243` | `_emit` writes `# input: $INPUT` unescaped before the sanitised records; an input containing a newline then `KIND retract` becomes a record the parser reads first | Low: the user already controls the query; matters if input comes from an untrusted channel | Strip newlines from `$INPUT` in the audit header | S | LIKELY |
| T-19 | Low | Lint | `make lint-ints` fails with 12 findings | `CE/scripts/int_safety_lint.py:1-12`; e.g. `CE/src/factory/child_mode.nova:381` | Re-run: "int-safety: 12 finding(s)", exit 1. The lint exists because NOVA treats any integer operand >= 1,048,576 as a heap pointer | Sites at risk of silent wrong arithmetic; gate not enforced | Fix or annotate; add to CI | S | CONFIRMED (executed) |
| T-20 | Low | Docs drift | Stale claims in build files | `CE/.devcontainer/setup.sh:42` ("86/86 pass"), `CE/scripts/run.sh:4-6` ("there is no end-user cognitive agent yet"), `CE/tests/benchmark/README.md:17` ("Status: Pending"), `CE/bench/latency_v1/README.md:47-52` (says `nanotime()` is broken; it works here), `CE/data/nl_intent/prototypes.txt:17-23` (duplicate of a hard-coded corpus) | — | Readers cannot tell which statement is current | Sweep | S | CONFIRMED |
| T-21 | Low | Provenance | Knowledge packs have no verifiable source or licence | `CE/data/packs/biology.cerec:8-9`, `politics.cerec:3-6`, `solar_system.cerec` header | 324 atoms across 7 packs, counts match `CE/data/packs/README.md`. Text cites textbooks by name; only `solar_system` has a `LICENSE` line (CC-BY-4.0). Belief values (950, 1000) are author-assigned | Fine as demo data; cannot be presented as curated from the cited references. Whether a person or an LLM wrote them cannot be determined from the repo | Add provenance and licence lines to every pack | S | CONFIRMED (counts); authorship not determinable |
| T-22 | Low | Runner | `nova run` hides compiler diagnostics | `NOVA/nova:31-33` | Compile output is piped through `grep -v "^===" \|\| true` and `as` stderr goes to `/dev/null`; failure still surfaces as a non-zero exit when `as` fails | A compile error shows as an unexplained FAIL | Preserve compiler stderr and exit status | S | CONFIRMED by reading |
| T-23 | Low | Runner | Timeouts are reported as `FAIL (exit 143)`, never `TIMEOUT` | `CE/scripts/test.sh:63-68` | `timeout --preserve-status` returns the child's status (128+15=143 on TERM), but the script tests for 124/137. Lead's run: `test_bignum_2048.nova FAIL (exit 143)` after printing timing lines and no assertion failure | A slow test on a loaded machine is indistinguishable from a crash; still counted as a failure, so nothing is hidden | Drop `--preserve-status` or also treat 143 as timeout | S | CONFIRMED |

## Test quality numbers

Method: `probes/ce_tests/tq.py` parses every `ce_check/ce_eq/ce_str_eq/ce_near` call in `CE/tests/unit/*.nova` and classifies the expected-value argument. I read 20 files in full and the assertion lines of 20 more (substrate, kg, learning, reasoning, nl, agent, imagination, soul); the rest are script-classified only.

| Measure | Value |
|---|---|
| Unit test files / LOC | 478 / 132,403 (plus 1 fixture file) |
| Assertions | 21,340; median 34 per file, min 2, max 519 |
| Files with zero assertions | 0 |
| Files not importing the harness or not calling `ce_summary` | 0 |
| Files with 3 or fewer assertions | 4: `test_loop_emotion` (3), `test_loop_goals` (3), `test_loop_reasoning` (3), `test_loop_imagination_idle` (2) — the per-loop tests of the "cognitive loop" |
| Expected value is a literal or named constant | 16,654 (78%) |
| … of which the literal is 0 or 1 (status flag, membership) | 7,775 (36% of all) |
| … of which the literal is >= 1000 (candidate golden numbers) | 538 (2.5%) |
| Relational checks (`a > b`, `x < 750`) | 2,586 (12%) |
| Weak checks (`>= 0`, `> 0`, `!= 0`, constant true) | 1,222 (5.7%); 22 are literally `ce_check(label, 1)` |
| Files where at least half the assertions are weak | 9, mostly pack-loading tests (`test_medical_pack`, `test_pack_biology`, `test_pack_politics`, `test_self_model_query` 9 of 9 substring checks) |
| Expected value computed at run time (variable, call, expression) | 873 (4.1%) — the pool where tautologies could hide |
| Identical expression on both sides | 5 (3 in the harness self-test) |
| Assertions that a stub returns its stub value | 44 in 16 files |
| Files with a skip path | 96 mention skip; 9 contain an explicit skip-counted-as-pass assertion |
| Public functions in `src/` named in some unit test | 4,633 of 5,628 (82%) |
| `src/` modules with a same-named test / directly imported by a test / import-reachable | 326 / 379 / 385 of 397 |

What the hand-read sample showed:
- Typical pattern (`test_forward_sim`, `test_consolidation`, `test_counterfactual`, `test_three_factor`, `test_synapse_graph`, `test_nl_generate`): build a 2-6 element fixture, call one function, compare with a hand-derived value. These are independent expectations, not tautologies.
- Characterization values exist but are small in number and locally derivable (`emotion_modulate_plasticity(900,500,900) == 2140`, "confidence after support 666"). The global golden numbers (486000 etc.) live in CI, not in the unit tests.
- Mild tautologies: `test_loop_emotion` "soul mood synced" compares two outputs of the same call; `test_loop_perception` parity checks compare the loop wrapper with the function it wraps.
- "Learning" tests are fit-the-training-set checks: `test_forward_forward` trains on four 4-element vectors and asserts those same four are separated; `test_autonomous_loop` asserts last-cycle return exceeds first-cycle return on the grid world. None evaluates on inputs not seen in training.
- Semantic tests construct their own answer: `test_hdc_embed` gets "car ~ automobile > 700" by giving both words the same hand-written neighbour list.

How a test fails: `ce_summary` calls `exit(1)` if any check failed (`CE/tests/ce_test.nova:82-88`); `scripts/test.sh:66-78` marks FAIL on non-zero exit, timeout (124/137), or output matching `assertion failed|(^| )FAIL` case-insensitively.

Can a failure be swallowed? I probed the harness (`probes/ce_tests/probe_*.nova`):
- Unequal large integers (above the 1,048,576 "pointer" threshold) are reported correctly; string-vs-int mismatch is reported.
- A test that never calls `ce_summary` exits 0 but still prints `FAIL:`, which the runner catches.
- An out-of-bounds index aborts with rc=1.
- `ce_check` accepts any truthy value (`2`, a string) as a pass.
- The remaining swallow routes are the skip paths (T-12) and assertions that are simply never reached.
- The reverse error exists: the case-insensitive ` fail` grep turns a test that prints an informational "failed to …" line into a FAIL.

## Benchmarks & evidence inventory

| Name | What it measures | Baseline? | Reproducible? | Reported vs re-run |
|---|---|---|---|---|
| `tests/benchmark/bench_node_throughput.nova` | Loop of 8000 ticks over 96 nodes, 1-second clock | No | Runs; output not a measurement | Docs give no number. Re-run: "768000 integrations/sec" = loop count |
| `tests/benchmark/bench_tick_rate.nova` | Tick iterations, 1-second clock | No | Same | Re-run: 60000 and 5000 = loop counts. ADR r36f-0001 says "hundreds of thousands of ticks/sec" |
| `tests/benchmark/bench_kg_query.nova` | Insert/lookup rate; label index vs scan (1M lookups, 1000 atoms) | Internal (scan vs index) | Yes | Re-run: index 290 ms vs scan 21,653 ms = 74x. Rate lines are counts (elapsed 0) |
| `tests/benchmark/bench_operator_lookup.nova` | Edge index vs full scan, 2000 atoms, parity check | Internal | Yes | Reported ~1132x (1330 ms vs 1 ms); re-run 1901x (6603 ms vs 3 ms). Ratio over a 1-3 ms denominator is noise |
| `tests/benchmark/bench_ann_query.nova` | LSH bucket vs linear cosine, 1000 atoms | Internal | Yes | Session log says 40x; re-run 79x. ANN returned 23,600 of 25,000 results (94% recall, not reported as such) |
| `tests/benchmark/bench_self_improve.nova` | Tabular Q-learning, 5x5 deterministic grid, greedy return before/after | Untrained self only | Yes (seeded) | Re-run: -200 -> 93, optimal 8 steps by session 20. Textbook result; no comparison to any other learner |
| `tests/benchmark/bench_predictive_coding.nova` | Delta rule on a period-3 sequence, error first 10 vs last 10 ticks | Self only | No — compile error | ADR-0052 cites it; re-run fails `undeclared callee: sys_open` |
| `tests/benchmark/bench_nl_verbs.nova` + `scripts/bench_nl_verbs.sh` + `bench/latency_v1/baseline.json` | Per-phase latency of NL query path, synthetic 1000-atom KG | Baseline file is empty | No — OOM at 13.6 GB | Nothing reported. Partial re-run: grammar parse 3 µs median; classifier 5.1 ms; execute 20.8 ms median / 1,033 ms p99; research RPC 21.4 ms / 1,022 ms p99 |
| `scripts/bench.sh` + `scripts/bench_simd_production.sh` + `bench/baseline.json` + `BENCHMARKS.md` | Wall-clock of stereo SAD, Lucas-Kanade, HOG, SAD/dot kernels, scalar vs SIMD | Scalar version of same kernel | Not re-run (needs `make` in NOVA and a 600 s budget) | Reported 5.94x stereo, 3.35x LK, 106x image SAD, 141x/45x primitives; file itself records 0.16x and 0.82x cases and that the baseline is stale. Self-timed by the programs. Unrelated to cognition |
| `src/bench/reasoning_bench.nova` + `bench_bank_ext.nova` (chat `/bench`) | Whether the proof checker accepts 12 (+~25) supplied proofs and rejects supplied non-proofs | No | Yes (deterministic) | Reported 11/11 or 12/12, 0 false proofs. Guaranteed by construction (T-03) |
| `src/bench/reasoning_bench.nova:363-387` + `data/llm_baseline_*.txt` (chat `/vs`) | Same bank vs "LLM verdicts" | Invented | Yes | Reported engine 11/11 vs LLM 8/11. LLM side fabricated (T-02) |
| `src/bench/calibration.nova` | Brier score and ECE over supplied (confidence, outcome) pairs | n/a | Yes | A correct metric implementation; never applied to real system output |
| CI "10-query fever smoke" | Five exact counters after 10 identical inputs | Golden numbers | Yes | Matches exactly on re-run (T-09) |
| `tests/integration/scenario_fff_snap_delta.sh` | Delta snapshot write at least 3x faster than full write | Internal | Not run | — |

Answer to the key question: there is no test or benchmark that measures accuracy on questions, generalisation to unseen inputs, a learning curve on held-out data, or a comparison with a lookup table, keyword search or a real LLM. CONFIRMED by inventory and grep.

## Integration tests

- 146 files: 130 shell scripts (27,289 lines with drivers), 14 NOVA driver programs in `_scenario_*` directories, `_lib.sh`, README.
- They drive the built binaries through stdin and grep the output. Groups: 5 `admin_*` (slash-command edge cases), 14 `failmode_*` (corrupt snapshot, killed mid-fsync, long line, veto bypass attempts), about 110 `scenario_*` covering durability, KG sync, federation, web shim, audio/vision kernels, crypto, rule inference, pagerank and similar.
- External tools: 38 scripts use `python3`, 9 `curl`, 14 `nc`, 12 reference whisper, 1 vosk, 1 `arecord`, 1 `sox`. None references Ollama or a hosted API. Network-touching ones probe for sockets and skip.
- Skips: 49 of 130 have a skip path (missing binary, missing whisper/vosk model, sandbox denying sockets). A skip counts as a pass.
- `make integration` runs every non-underscore `*.sh` after `make install` (`CE/Makefile:323-337`). It is not in CI. I did not run it (fixed `/tmp` paths shared with other reviewers).
- `failmode_constitution_bypass_attempts.sh:86-95` documents that the "constitutional veto" is a keyword match plus a seeded synonym list, and that novel paraphrases pass.

## CI & reproducibility

- One workflow, `build-and-smoke.yml`. Gates: NOVA builds, `make install` builds 10 binaries, five counters match. Nothing else.
- NOVA: default branch, no SHA, plain `make` (T-05, T-06). CE's Makefile only checks that `$(NOVA_ROOT)/nova` is executable (`CE/Makefile:181-186`).
- The smoke step relies on the default non-`pipefail` shell: `crossengin-chat` exits 1 on `/quit` (observed rc=1), which would fail the step if `pipefail` were on.
- One-command build from a clean checkout does not exist. `scripts/bootstrap.sh` checks tools and builds NOVA if a checkout is already present at `$HOME/NOVA`; it does not clone. The devcontainer does clone (unpinned, shallow) and runs `make build`.
- Hard-coded locations: `$HOME/NOVA` default (`Makefile:17`, `test.sh:14`, `bootstrap.sh:10`), `/home/user/NOVA` fallback (`scripts/bench.sh:69`), fixed `/tmp` files (T-15), `/usr/local/bin/whisper-main` (`tests/integration/scenario_jj_whisper.sh:48-49`).
- `nova-deps.toml` lists 14 NOVA enhancements CE "depends on"; 7 are `status = "required"` (not available): sparse synapse adjacency, true concurrency, 100 Hz tick scheduler, learned gate routing, snapshot rehydration, outbound HTTP, idle scheduling. The file is documentation only.

## scripts/coverage.sh

"Coverage" means: a `src/` module is covered if some unit test imports it directly or transitively. Re-run without a toolchain: 385 covered, 12 uncovered, exit 1. There is no line or branch coverage tool in either repository. My closest estimate of real coverage is the function-name measure above (82% of public functions named in a test), which is an upper bound on function coverage and says nothing about branches.

## LLM script analysis

| Script | Provider / model | Prompt | Where the output goes | Injection review |
|---|---|---|---|---|
| `llm_extract.sh` | `ollama run $MODEL` (default); `llama-cli -m`; `curl $OPENAI_BASE_URL/chat/completions` with `$OPENAI_API_KEY`; `dry-run`. Chat default model `llama3.2:3b-instruct` (`crossengin_chat.nova:1701-1704`) | "You are an extraction preprocessor … emit a .cerec file" with ATOM/IMP/OBS format rules and one worked example; passage inlined (`:82-149`) | Written to a `.cerec`; `/ingest_ollama` forks the script then `/ingest_llm` queues records for operator review; source tagged `src:extractor:llm:…`, beliefs capped at 800 per the header (cap is in `src/ingest/llm_extractor.nova`, not verified by me) | Variables quoted; JSON built with `jq --arg`; passage is expanded once inside a heredoc and not re-evaluated. Prompt injection from the passage is possible by nature. Output path `/tmp/crossengin_ollama_<basename>.cerec` is predictable |
| `nl_parse_llm.sh` | Same four backends | "Convert a single natural-language question into a StructuredQuery wire record … Do NOT answer" with the 12 kinds and five examples (`:98-150`) | KIND/ARG lines parsed by `src/nl/llm_parser.nova`, then executed by the normal query path; used when the grammar and prototype classifier both fail | Quoted; T-18 newline injection in the audit comment |
| `llm_compose.sh` | Same; default `llama3.2:3b-instruct` via `$OLLAMA_COMPOSER_MODEL` | "You rewrite a single sentence in a natural, conversational tone … Preserve every noun phrase" (`:103-116`) | Replaces the templated reply shown to the user; falls back to the template on empty, refusal-looking or over-long output | Quoted; template text reaches the prompt unescaped |
| `learn.sh` | No LLM. `curl` to `https://en.wikipedia.org/wiki/<topic>` or any URL/RSS/file | n/a | Top 30 most frequent 4-14 letter words become vocabulary; awk window emits `X|is_a|Y`, `X|causal|Y`, `X|has|Y`; chat `/learn` keeps triples whose both ends are known atoms | T-07 negation, T-14 path/URL |
| `preload.sh` | No LLM | n/a | Calls `skill.install` for `echo` and `research` on a running daemon; loads no knowledge | Clean |

Do the docs present LLM-extracted knowledge as the system learning? Partly. `docs/USER_GUIDE_DEPLOY_DATA_COMPARE.md:285-292` is candid ("LLM for reading-comprehension-at-scale"). The same document's comparison table says the system learns "Online. Bayesian belief updates + local Hebbian + rule inference" (`:262`) and that it "Structurally cannot invent atoms that no source backs" (`:266`); T-07 shows the non-LLM path can invert a source, and LLM-extracted atoms are only as good as the operator's review.

## data/

- `.cerec` format: line-oriented directives — `KG name`, `SRC tag`, `ATOM label kind belief`, `IMP a b FORMAL|EMPIRICAL`, `OBS label sign weight`, `CITE`, optional `CAPSULE/VERSION/DESCRIPTION/LICENSE`.
- Facts per pack (ATOM / IMP / OBS): biology 77/86/4, politics 73/58/4, religion 58/68/5, world_history 43/50/4, physics 35/35/3, solar_system 33/49/4, folk_astronomy 5/1/0. Total 324 atoms, 347 implications.
- These are short hand-written ontologies (labels like `mitochondrion`, edges like `sun -> star`). They are the system's "knowledge" in demos, alongside the 584 seed atoms compiled into the binary.
- `data/patterns/security_review.cerec`: 25 trigger phrases mapped to fixed advice paragraphs.
- `data/nl_intent/prototypes.txt`: about 130 example sentences for 10 intents; the classifier uses a copy embedded in source, so editing this file changes nothing.

## TODO / stub inventory (CE `src/` and `tests/`)

Marker counts (word-boundary grep): TODO 12 src / 2 tests; FIXME 0; HACK 0; XXX 2 / 2 (both format strings, not markers); KNOWN 4 / 44; "not implemented" 6 / 1; placeholder 58 / 49; stub 104 / 145; deferred 88 / 21; workaround 19 / 3. By directory for the combined set in `src/`: io 102, federation 62, learning 17, safety 12, parts 10, ingest 7, kg 7, net 6, all others 3 or fewer. The project rarely writes TODO; unfinished work is labelled "stub", "deferred" or "placeholder".

Most consequential:
1. `CE/src/safety/scram.nova:502-506` — "Production nonce generator stub. Returns 0 until NOVA's runtime exposes `sys_getrandom`."
2. `CE/src/net/tls/tls_record.nova:149` — "TODO(R94): AEAD encrypt(header, fragment, key_schedule) -> ciphertext."
3. `CE/src/net/tls/tls_record.nova:53-56` — "Every stub in this module returns this string in place of the real bytes/struct it will one day return."
4. `CE/src/learning/internet_fetch.nova:268` — "https deferred to scripts/learn.sh -- see TLS_AUDIT.md" (native fetch is HTTP only; HTTPS is `curl`).
5. `CE/src/io/transducers/stt_seam.nova:95-98` — "Placeholder transcript the stub backend returns" (speech-to-text is whisper/vosk or a placeholder string).
6. `CE/src/io/transducers/visual_perception.nova:105` — "(jpeg_decode.nova; entropy decode TODO)" (JPEG decoding is not implemented).
7. `CE/src/io/transducers/visual_perception.nova:588` — returns "image: stub decoder (no pixel data)".
8. `CE/src/io/transducers/png_decode.nova:514-517` — "only grayscale (color_type=0) is supported (TODO: RGB/RGBA/palette)".
9. `CE/tests/unit/test_nat_traversal.nova:211` — "hole punch returns 0 (not implemented)".
10. `CE/src/federation/ice.nova:45` — "stub `ice_check_pair` returns 0; a real check builds a STUN …".
11. `CE/src/federation/dtls12.nova:4059` — a caller relying "on a stub gets a clean 'not implemented' signal".
12. `CE/src/federation/webrtc.nova:126` — "not yet implemented."
13. `CE/src/parts/soul/constitution.nova:19-22` — "Today's KNOWN scope: the concept-veto catches percepts whose handle equals the forbidden concept OR appears as an operator / xref neighbor".
14. `CE/src/safety/pem_truststore.nova:148` — "TODO(NOVA-sys_readdir): swap this manifest fallback for a real" directory read.
15. `CE/src/bench/reasoning_bench.nova:357-359` — "The verdicts here are illustrative placeholders for real captured transcripts".
Also `CE/tests/ce_test.nova:40-46`: the harness avoids NOVA's `str_eq` because it "gives WRONG results on a family of specific string literals".

## Executed

| What | Result |
|---|---|
| 8 benchmarks under `tests/benchmark` (timeout 120 each) | 6 ran, 1 compile error, 1 OOM-killed; numbers above |
| `scripts/coverage.sh` | 385/397, exit 1 |
| `scripts/int_safety_lint.py` | 12 findings, exit 1 |
| CI smoke, isolated snapshot/dlog paths, twice | Five counters match exactly; chat rc=1 |
| Same smoke with "what is a virus" and with nonsense input | Counters differ (0s; `ff_goodness=1771`), confirming the numbers are specific to "fever" |
| `learn.sh` copy redirected to scratch, negation probe | Negated sentences emitted as positive triples |
| Harness probes (`probe_eq`, `probe_nosummary`, `probe_crash`) | Harness detects failures correctly |
| `tests/unit/test_predictive_coding_runtime.nova` | OK, 30 checks |

## Not verified

- Full `make test` totals: the lead's run was still in progress when I finished. State at 23:21 UTC: 92 of 478 tests run, 90 PASS, 2 FAIL. `test_audio_wakeword` fails 1 of 35 checks at `CE/tests/unit/test_audio_wakeword.nova:216-219` (template save returned 0 but load of the fixed path `/tmp/ce_test_wake_template_rt.template` returned a record: either a stale file from another run, which is finding T-15 in action, or a real save bug; not determined). `test_bignum_2048` was terminated at the 60 s cap (T-23) on a machine shared with other reviewers.
- `make integration`, `scripts/bench.sh`, the SIMD benchmark numbers, anything needing Ollama/whisper/network.
- Whether CI is currently green on GitHub.
- 438 unit-test files and 128 integration scripts were classified by script and header only.
