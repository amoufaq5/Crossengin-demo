# ce_tests coverage

Rows: 675. Assignment file count: tests/** + bench/** + data/** + .github/** = 654 files (find; repo copy is not a git checkout so git ls-files is unavailable), plus Makefile, nova-deps.toml and 19 assigned scripts = 675.

'reviewed' = read by hand; 'skimmed (script-analysed)' = assertion statistics extracted by script (probes/ce_tests/tq.py), not read line by line (478 repetitive test files, 132k LOC). Unit-test status 'Working' means the file is a real assertion-bearing test; pass/fail comes from the lead's make test run (see findings).

| path | status | LOC | actual status | what it really does |
|---|---|---|---|---|
| CE/Makefile | reviewed | 362 | Working | Build driver: compiles each src module to fixed /tmp/ce_build_check.bin, runs scripts/test.sh, builds 10 binaries, runs integration *.sh; default NOVA_ROOT=$HOME/NOVA, no NOVA version check |
| CE/nova-deps.toml | reviewed | 144 | Doc | Declarative note of NOVA 'version 0.2.0/0.9.0' + 14 upstream enhancements (7 marked 'required', i.e. not available); read by no tool |
| CE/.github/workflows/build-and-smoke.yml | reviewed | 84 | Partial | Only CI: checks out NOVA default branch unpinned, plain make (non-setarch), make install, pipes 10x 'fever' into chat and greps 5 exact counters; no make test/integration/coverage/lint |
| CE/tests/ce_test.nova | reviewed | 88 | Working | Assertion harness: ce_check/ce_eq/ce_str_eq/ce_near bump global pass/fail counters and print 'FAIL:'; ce_summary exit(1) on any failure |
| CE/tests/benchmark/README.md | reviewed | 17 | Doc | Says benchmark status 'Pending'; quotes ~1132x operator-index speedup |
| CE/tests/benchmark/bench_ann_query.nova | reviewed | 192 | Working | Times LSH bucket lookup vs linear cosine scan on 1000 synthetic atoms (re-run: 79x; ANN returns 23600 of 25000 linear results) |
| CE/tests/benchmark/bench_kg_query.nova | reviewed | 179 | Partial | Insert/lookup rates with 1-second clock (prints count as rate when elapsed=0) + label-index vs scan timing (re-run 74x) |
| CE/tests/benchmark/bench_nl_verbs.nova | reviewed | 426 | Partial | nanotime latency of grammar parse/classifier/executor/RPC on synthetic 1000-atom KG; re-run OOM-killed at 13.6 GB RSS after 6 of 10 phases |
| CE/tests/benchmark/bench_node_throughput.nova | reviewed | 65 | Partial | 8000 ticks of a 96-node pool timed with 1-second clock; reported integrations/sec is just the loop count when elapsed<=1s |
| CE/tests/benchmark/bench_operator_lookup.nova | reviewed | 121 | Working | Edge-index lookup vs full atom scan, 2000 atoms, parity check (re-run 1901x vs documented ~1132x) |
| CE/tests/benchmark/bench_predictive_coding.nova | reviewed | 106 | Dead | Delta-rule predictor on a fixed period-3 sequence; does not compile on current tree ('undeclared callee: sys_open') |
| CE/tests/benchmark/bench_self_improve.nova | reviewed | 43 | Working | Tabular Q-learning on a 5x5 deterministic grid world; before/after greedy return (-200 -> 93, optimal 8 steps); no baseline |
| CE/tests/benchmark/bench_tick_rate.nova | reviewed | 86 | Partial | Tick-loop iterations per second with 1-second clock; output equals the loop count (60000, 5000) |
| CE/tests/benchmark/kg_synthetic_loader.nova | reviewed | 200 | Working | Builds synthetic KG (1000 atoms/5000 relations/10 capsules) for bench_nl_verbs |
| CE/bench/baseline.json | reviewed | 174 | Working | 15 SIMD/vision kernel timings captured once on host 'vm' (2026-06-03); documented as stale (HOG now 40-66% faster) |
| CE/bench/latency_v1/baseline.json | reviewed | 7 | Stub | Empty results array; self-described 'Empty baseline' so --compare is a no-op |
| CE/bench/latency_v1/README.md | reviewed | 129 | Doc | Explains NL latency harness and that baseline is an empty stub |
| CE/data/packs/biology.cerec | reviewed | 279 | Working | Hand-authored fact list: 77 ATOM, 86 IMP, 4 OBS, 5 CITE (cites textbooks by name; no licence line) |
| CE/data/packs/folk_astronomy.cerec | reviewed | 37 | Working | 5 deliberately low-belief atoms (pluto planet etc.) to trigger cross-KG conflict demo |
| CE/data/packs/physics.cerec | reviewed | 152 | Working | 35 ATOM, 35 IMP, 3 OBS; label overlap with solar_system by design |
| CE/data/packs/politics.cerec | reviewed | 236 | Working | 73 ATOM, 58 IMP; descriptive taxonomy of political systems |
| CE/data/packs/religion.cerec | reviewed | 222 | Working | 58 ATOM, 68 IMP; descriptive taxonomy of religions |
| CE/data/packs/solar_system.cerec | reviewed | 170 | Working | 33 ATOM, 49 IMP; only pack with CAPSULE/VERSION/LICENSE (CC-BY-4.0) header |
| CE/data/packs/world_history.cerec | reviewed | 170 | Working | 43 ATOM, 50 IMP; dated historical milestones |
| CE/data/packs/README.md | reviewed | 120 | Doc | Pack catalogue; atom counts (324 total) match files |
| CE/data/packs/samples/climate_facts.yaml | reviewed | 92 | Working | Sample record: 10 atoms/7 implications for YAML adapter |
| CE/data/packs/samples/climate_facts.json | reviewed | 43 | Working | Same sample for JSON adapter |
| CE/data/patterns/security_review.cerec | reviewed | 132 | Working | 25 trigger-phrase -> canned guidance strings (OWASP/CWE paraphrases) for coding_helper substring match |
| CE/data/nl_intent/prototypes.txt | reviewed | 164 | Working | ~130 example utterances for 10 intent kinds; duplicate of corpus hard-coded in src/nl/nl_intent_classifier.nova (file not read at runtime) |
| CE/data/llm_baseline_sample.txt | reviewed | 40 | Fake | 12 invented 'LLM verdicts' (affirm/deny) for the reasoning bench; header calls it both 'illustrative' and 'recorded' |
| CE/data/llm_baseline_ext.txt | reviewed | 65 | Fake | Same, for the extended bank; invented |
| CE/scripts/test.sh | reviewed | 91 | Working | Runs each tests/unit/*.nova via nova run with 60s timeout; PASS iff exit 0 and no 'assertion failed'/' FAIL' in output |
| CE/scripts/coverage.sh | reviewed | 103 | Working | Static BFS over import lines from tests/unit; 'covered' = imported; re-run: 385/397, exits 1 |
| CE/scripts/bench.sh | reviewed | 556 | Partial | Wrapper: runs scripts/bench_*.sh + make -C NOVA bench targets, parses self-reported ns, emits JSON/compare; hard-coded /home/user/NOVA fallback; not re-run |
| CE/scripts/bench_nl_verbs.sh | reviewed | 234 | Partial | Runs bench_nl_verbs.nova, extracts JSON, compares to (empty) baseline |
| CE/scripts/bootstrap.sh | reviewed | 50 | Working | Checks as/ld/make/gcc, runs plain make in $NOVA_ROOT if unbuilt; does not clone or pin NOVA |
| CE/scripts/chat.sh | reviewed | 72 | Working | Loop that boots a fresh daemon per typed line |
| CE/scripts/run.sh | reviewed | 27 | Working | Runs kernel_selfcheck; header still says 'there is no end-user cognitive agent yet' |
| CE/scripts/preload.sh | reviewed | 82 | Working | Calls rpc.sh skill.install for echo+research on a running daemon; no knowledge preloading |
| CE/scripts/learn.sh | reviewed | 389 | Working | curl Wikipedia/URL/file -> top-30 frequent 4-14 letter words + awk regex triples (X is/causes/has Y) into fixed /tmp files; drops negation |
| CE/scripts/learn_smoke.sh | reviewed | 65 | Working | Writes fake vocab+triples to /tmp, runs /learn in chat, checks 2 words and 4-5 operators |
| CE/scripts/learn_smoke_multi.sh | reviewed | 312 | Working | Exercises learn.sh source kinds (topic/url/file/batch/rss/dir); network parts skip when offline |
| CE/scripts/llm_compose.sh | reviewed | 202 | Working | Sends templated reply to Ollama (default llama3.2:3b-instruct)/llama.cpp/OpenAI-compatible API for rewording; falls back to template |
| CE/scripts/llm_extract.sh | reviewed | 231 | Working | Sends a text file to an LLM (ollama/llama-cli/OpenAI API) with a prompt to emit ATOM/IMP/OBS lines; writes .cerec |
| CE/scripts/nl_parse_llm.sh | reviewed | 259 | Working | Sends one user sentence to an LLM to classify into KIND/ARG wire record |
| CE/scripts/crossengin-doctor.sh | reviewed | 250 | Working | Environment checklist (tools, /tmp, binaries, TCP probe to en.wikipedia.org) |
| CE/scripts/migrate_snapshot.sh | reviewed | 74 | Working | Wrapper that runs examples/migrate_snap.nova on two paths |
| CE/scripts/snap_diff.sh | reviewed | 244 | Working | Text diff of two key/value snapshot files (atoms, beliefs, mood) |
| CE/scripts/bake_sample.sh | reviewed | 109 | Working | Generates a signed sample agent bundle + pubkey into docs/samples |
| CE/scripts/int_safety_lint.py | reviewed | 174 | Working | Regex lint for large integer literals in * / comparisons (NOVA codegen bug #11); re-run: 12 findings, exit 1 |
| CE/tests/unit/test_action_atoms.nova | skimmed (script-analysed) | 194 | Working | 79 assertions (77 vs literal, 2 weak >=0/!=0/const); exercises action_atoms |
| CE/tests/unit/test_action_module.nova | skimmed (script-analysed) | 590 | Working | 100 assertions (74 vs literal, 8 weak >=0/!=0/const); has skip-as-pass path; exercises action_module |
| CE/tests/unit/test_admin_bake_child_verb.nova | skimmed (script-analysed) | 181 | Working | 20 assertions (13 vs literal, 0 weak >=0/!=0/const); exercises rpc_verbs, capability, bake_manifest, str_safe |
| CE/tests/unit/test_admin_emit_delta_verb.nova | skimmed (script-analysed) | 207 | Working | 24 assertions (13 vs literal, 0 weak >=0/!=0/const); exercises rpc_verbs, capability, child_mode, str_safe |
| CE/tests/unit/test_admin_list_holder_qps_verb.nova | skimmed (script-analysed) | 160 | Working | 30 assertions (4 vs literal, 0 weak >=0/!=0/const); exercises capability, holder_rate, rpc_verbs, str_safe |
| CE/tests/unit/test_admin_set_holder_qps_verb.nova | skimmed (script-analysed) | 185 | Working | 26 assertions (5 vs literal, 0 weak >=0/!=0/const); exercises capability, holder_rate, rpc_verbs, str_safe |
| CE/tests/unit/test_aes_gcm.nova | skimmed (script-analysed) | 393 | Working | 31 assertions (24 vs literal, 5 weak >=0/!=0/const); exercises aes_gcm |
| CE/tests/unit/test_agent_manifest.nova | skimmed (script-analysed) | 268 | Working | 86 assertions (72 vs literal, 0 weak >=0/!=0/const); exercises agent_manifest, str_safe |
| CE/tests/unit/test_agent_registry.nova | skimmed (script-analysed) | 191 | Working | 51 assertions (49 vs literal, 2 weak >=0/!=0/const); exercises agent_manifest, agent_registry, skill_manifest, skill_registry |
| CE/tests/unit/test_agent_run.nova | reviewed (assert lines sampled) | 291 | Working | 31 assertions (23 vs literal, 1 weak >=0/!=0/const); exercises agent_manifest, agent_registry, agent_run, skill_manifest |
| CE/tests/unit/test_agent_snapshot.nova | skimmed (script-analysed) | 145 | Working | 40 assertions (25 vs literal, 3 weak >=0/!=0/const); exercises session_snapshot, agent_manifest, agent_registry, str_safe |
| CE/tests/unit/test_agent_verbs.nova | skimmed (script-analysed) | 332 | Working | 56 assertions (6 vs literal, 1 weak >=0/!=0/const); exercises rpc_verbs, agent_manifest, agent_registry, skill_registry |
| CE/tests/unit/test_ann_index.nova | skimmed (script-analysed) | 335 | Working | 46 assertions (24 vs literal, 6 weak >=0/!=0/const); exercises atom_store, ann_index, multi_kg_manager |
| CE/tests/unit/test_answer_exclusion.nova | skimmed (script-analysed) | 45 | Working | 5 assertions (4 vs literal, 0 weak >=0/!=0/const); exercises reasoning_atoms, promotion |
| CE/tests/unit/test_appraisal.nova | skimmed (script-analysed) | 44 | Working | 14 assertions (12 vs literal, 0 weak >=0/!=0/const); exercises appraisal |
| CE/tests/unit/test_argumentation.nova | skimmed (script-analysed) | 145 | Working | 37 assertions (37 vs literal, 0 weak >=0/!=0/const); exercises argumentation |
| CE/tests/unit/test_arithmetic.nova | skimmed (script-analysed) | 63 | Working | 23 assertions (23 vs literal, 0 weak >=0/!=0/const); exercises arithmetic |
| CE/tests/unit/test_ask_user_to_teach.nova | skimmed (script-analysed) | 75 | Working | 19 assertions (14 vs literal, 2 weak >=0/!=0/const); exercises ask_user_to_teach |
| CE/tests/unit/test_atom_birth_monitor.nova | skimmed (script-analysed) | 84 | Working | 15 assertions (13 vs literal, 2 weak >=0/!=0/const); exercises atom_birth_monitor |
| CE/tests/unit/test_atom_death_attribution.nova | skimmed (script-analysed) | 227 | Working | 28 assertions (27 vs literal, 0 weak >=0/!=0/const); exercises atom_death_monitor, meta_observer, str_safe |
| CE/tests/unit/test_atom_death_monitor.nova | skimmed (script-analysed) | 198 | Working | 45 assertions (38 vs literal, 4 weak >=0/!=0/const); exercises atom_death_monitor |
| CE/tests/unit/test_atom_store.nova | reviewed (assert lines sampled) | 196 | Working | 77 assertions (74 vs literal, 0 weak >=0/!=0/const); exercises atom_store |
| CE/tests/unit/test_atom_store_index.nova | skimmed (script-analysed) | 305 | Working | 61 assertions (29 vs literal, 21 weak >=0/!=0/const); exercises atom_store, multi_kg_manager |
| CE/tests/unit/test_audio_capture.nova | skimmed (script-analysed) | 320 | Working | 28 assertions (27 vs literal, 1 weak >=0/!=0/const); exercises audio_capture |
| CE/tests/unit/test_audio_dsp.nova | skimmed (script-analysed) | 416 | Working | 34 assertions (12 vs literal, 3 weak >=0/!=0/const); exercises audio_dsp, audio_synth |
| CE/tests/unit/test_audio_melody.nova | skimmed (script-analysed) | 366 | Working | 40 assertions (40 vs literal, 0 weak >=0/!=0/const); exercises audio_melody, audio_pitch, audio_synth |
| CE/tests/unit/test_audio_mfcc.nova | skimmed (script-analysed) | 399 | Working | 41 assertions (14 vs literal, 6 weak >=0/!=0/const); exercises audio_mfcc, audio_synth |
| CE/tests/unit/test_audio_noise_reduce.nova | skimmed (script-analysed) | 318 | Working | 33 assertions (23 vs literal, 1 weak >=0/!=0/const); exercises audio_noise_reduce, audio_synth |
| CE/tests/unit/test_audio_pitch.nova | skimmed (script-analysed) | 530 | Working | 52 assertions (30 vs literal, 1 weak >=0/!=0/const); exercises audio_pitch, audio_synth |
| CE/tests/unit/test_audio_pitch_yin.nova | skimmed (script-analysed) | 436 | Working | 35 assertions (17 vs literal, 0 weak >=0/!=0/const); exercises audio_pitch, audio_synth |
| CE/tests/unit/test_audio_records.nova | skimmed (script-analysed) | 222 | Working | 31 assertions (27 vs literal, 4 weak >=0/!=0/const); exercises audio_records, perceptual_capsule, curriculum, atom_store |
| CE/tests/unit/test_audio_speak.nova | skimmed (script-analysed) | 37 | Working | 6 assertions (4 vs literal, 1 weak >=0/!=0/const); exercises audio_speak |
| CE/tests/unit/test_audio_spectrogram.nova | skimmed (script-analysed) | 507 | Working | 49 assertions (32 vs literal, 3 weak >=0/!=0/const); exercises audio_spectrogram, audio_synth |
| CE/tests/unit/test_audio_synth.nova | skimmed (script-analysed) | 887 | Working | 157 assertions (92 vs literal, 5 weak >=0/!=0/const); exercises audio_synth |
| CE/tests/unit/test_audio_tts.nova | skimmed (script-analysed) | 302 | Working | 68 assertions (53 vs literal, 1 weak >=0/!=0/const); exercises audio_tts |
| CE/tests/unit/test_audio_vad.nova | skimmed (script-analysed) | 646 | Working | 86 assertions (65 vs literal, 4 weak >=0/!=0/const); exercises audio_vad |
| CE/tests/unit/test_audio_wakeword.nova | skimmed (script-analysed) | 399 | Working | 42 assertions (28 vs literal, 8 weak >=0/!=0/const); exercises audio_wakeword, audio_synth |
| CE/tests/unit/test_audit_reader.nova | skimmed (script-analysed) | 62 | Working | 14 assertions (6 vs literal, 8 weak >=0/!=0/const); exercises audit_writer, audit_reader |
| CE/tests/unit/test_audit_writer.nova | skimmed (script-analysed) | 74 | Working | 25 assertions (24 vs literal, 0 weak >=0/!=0/const); exercises audit_writer |
| CE/tests/unit/test_autocompact_trigger.nova | skimmed (script-analysed) | 265 | Working | 50 assertions (42 vs literal, 0 weak >=0/!=0/const); exercises autonomous_loop |
| CE/tests/unit/test_autonomous_loop.nova | reviewed (assert lines sampled) | 102 | Working | 20 assertions (8 vs literal, 3 weak >=0/!=0/const); exercises autonomous_loop |
| CE/tests/unit/test_autonomous_research.nova | skimmed (script-analysed) | 290 | Working | 58 assertions (55 vs literal, 0 weak >=0/!=0/const); exercises autonomous_research, self_learning_triggers, multi_kg_manager, atom_store |
| CE/tests/unit/test_bake.nova | skimmed (script-analysed) | 315 | Working | 53 assertions (28 vs literal, 1 weak >=0/!=0/const); exercises bake, bake_manifest, bundle_signing, multi_kg_manager |
| CE/tests/unit/test_bake_manifest.nova | skimmed (script-analysed) | 280 | Working | 88 assertions (80 vs literal, 8 weak >=0/!=0/const); exercises bake_manifest, str_safe |
| CE/tests/unit/test_base64.nova | skimmed (script-analysed) | 131 | Working | 35 assertions (35 vs literal, 0 weak >=0/!=0/const); exercises base64 |
| CE/tests/unit/test_bayesian_updates.nova | reviewed (assert lines sampled) | 74 | Working | 20 assertions (16 vs literal, 1 weak >=0/!=0/const); exercises bayesian_updates |
| CE/tests/unit/test_belief_decay.nova | skimmed (script-analysed) | 116 | Working | 12 assertions (8 vs literal, 0 weak >=0/!=0/const); exercises verify, belief_decay |
| CE/tests/unit/test_bench_bank_ext.nova | skimmed (script-analysed) | 40 | Working | 9 assertions (8 vs literal, 1 weak >=0/!=0/const); exercises bench_bank_ext |
| CE/tests/unit/test_bignum.nova | skimmed (script-analysed) | 509 | Working | 66 assertions (63 vs literal, 3 weak >=0/!=0/const); exercises bignum |
| CE/tests/unit/test_bignum_2048.nova | skimmed (script-analysed) | 423 | Working | 65 assertions (61 vs literal, 3 weak >=0/!=0/const); exercises bignum_2048 |
| CE/tests/unit/test_bignum_256.nova | skimmed (script-analysed) | 448 | Working | 70 assertions (66 vs literal, 3 weak >=0/!=0/const); exercises bignum_256 |
| CE/tests/unit/test_bignum_mind.nova | skimmed (script-analysed) | 133 | Working | 18 assertions (16 vs literal, 1 weak >=0/!=0/const); exercises bignum |
| CE/tests/unit/test_bundle_signing.nova | skimmed (script-analysed) | 183 | Working | 25 assertions (22 vs literal, 2 weak >=0/!=0/const); exercises bundle_signing, ed25519, str_safe |
| CE/tests/unit/test_byzantine_aggregation.nova | skimmed (script-analysed) | 485 | Working | 74 assertions (68 vs literal, 1 weak >=0/!=0/const); exercises byzantine_aggregation, federated_aggregator, str_safe |
| CE/tests/unit/test_calibration.nova | reviewed (assert lines sampled) | 103 | Working | 18 assertions (16 vs literal, 1 weak >=0/!=0/const); exercises calibration |
| CE/tests/unit/test_capability.nova | skimmed (script-analysed) | 439 | Working | 84 assertions (47 vs literal, 2 weak >=0/!=0/const); exercises capability, rpc_verbs, multi_kg_manager, capsule_registry |
| CE/tests/unit/test_capability_gate.nova | skimmed (script-analysed) | 118 | Working | 40 assertions (34 vs literal, 4 weak >=0/!=0/const); exercises capability_gate |
| CE/tests/unit/test_capability_rate_limit.nova | skimmed (script-analysed) | 317 | Working | 48 assertions (31 vs literal, 5 weak >=0/!=0/const); exercises capability, session_snapshot, rpc_verbs, multi_kg_manager |
| CE/tests/unit/test_capability_wire.nova | skimmed (script-analysed) | 1652 | Working | 265 assertions (98 vs literal, 4 weak >=0/!=0/const); exercises capability, holder_rate, rpc_verbs, multi_kg_manager |
| CE/tests/unit/test_capsule.nova | skimmed (script-analysed) | 84 | Working | 35 assertions (35 vs literal, 0 weak >=0/!=0/const); exercises capsule |
| CE/tests/unit/test_capsule_dep.nova | skimmed (script-analysed) | 140 | Working | 32 assertions (31 vs literal, 1 weak >=0/!=0/const); exercises capsule_dep |
| CE/tests/unit/test_capsule_registry.nova | skimmed (script-analysed) | 148 | Working | 36 assertions (34 vs literal, 1 weak >=0/!=0/const); exercises capsule_registry |
| CE/tests/unit/test_cascade.nova | skimmed (script-analysed) | 202 | Working | 28 assertions (24 vs literal, 0 weak >=0/!=0/const); exercises cascade |
| CE/tests/unit/test_ce_test.nova | reviewed (assert lines sampled) | 51 | Working | 15 assertions (12 vs literal, 0 weak >=0/!=0/const); exercises harness only |
| CE/tests/unit/test_chacha20.nova | skimmed (script-analysed) | 171 | Working | 25 assertions (24 vs literal, 0 weak >=0/!=0/const); exercises chacha20 |
| CE/tests/unit/test_chacha20_poly1305.nova | skimmed (script-analysed) | 389 | Working | 55 assertions (55 vs literal, 0 weak >=0/!=0/const); exercises chacha20, poly1305, chacha20_poly1305 |
| CE/tests/unit/test_chat_cli_polish.nova | skimmed (script-analysed) | 361 | Working | 53 assertions (51 vs literal, 1 weak >=0/!=0/const); exercises chat_cli_polish, str_safe |
| CE/tests/unit/test_chat_fed_slash_commands.nova | skimmed (script-analysed) | 313 | Working | 44 assertions (44 vs literal, 0 weak >=0/!=0/const); exercises fed_slash, gossip, distributed_query, atom_store |
| CE/tests/unit/test_chat_helpers.nova | skimmed (script-analysed) | 264 | Working | 100 assertions (95 vs literal, 0 weak >=0/!=0/const); exercises helpers |
| CE/tests/unit/test_chat_intent_dispatch.nova | skimmed (script-analysed) | 197 | Working | 67 assertions (67 vs literal, 0 weak >=0/!=0/const); exercises helpers |
| CE/tests/unit/test_chat_state_persistence.nova | reviewed (assert lines sampled) | 813 | Working | 165 assertions (131 vs literal, 25 weak >=0/!=0/const); has skip-as-pass path; exercises chat_state, reasoning_atoms, word_atoms |
| CE/tests/unit/test_child_mode.nova | skimmed (script-analysed) | 269 | Working | 23 assertions (17 vs literal, 5 weak >=0/!=0/const); exercises child_mode, bake, bake_manifest, bundle_signing |
| CE/tests/unit/test_child_mode_wire.nova | skimmed (script-analysed) | 282 | Working | 16 assertions (16 vs literal, 0 weak >=0/!=0/const); exercises rpc_verbs, capability, child_mode, multi_kg_manager |
| CE/tests/unit/test_code_review_pack.nova | skimmed (script-analysed) | 90 | Working | 10 assertions (1 vs literal, 7 weak >=0/!=0/const); exercises code_review_pack, imagination_engine |
| CE/tests/unit/test_coding_helper.nova | skimmed (script-analysed) | 365 | Working | 58 assertions (33 vs literal, 1 weak >=0/!=0/const); exercises skill_dispatch, coding_helper, capsule_registry, pattern_capsule |
| CE/tests/unit/test_cofire_index.nova | skimmed (script-analysed) | 181 | Working | 35 assertions (35 vs literal, 0 weak >=0/!=0/const); exercises cofire_index |
| CE/tests/unit/test_cognitive_router.nova | skimmed (script-analysed) | 308 | Working | 55 assertions (48 vs literal, 6 weak >=0/!=0/const); has skip-as-pass path; exercises cognitive_router, str_safe |
| CE/tests/unit/test_coherence_check.nova | skimmed (script-analysed) | 79 | Working | 11 assertions (9 vs literal, 0 weak >=0/!=0/const); exercises context_bias, spreading_activation, coherence_check |
| CE/tests/unit/test_competence_tracker.nova | skimmed (script-analysed) | 138 | Working | 27 assertions (21 vs literal, 1 weak >=0/!=0/const); exercises competence_tracker |
| CE/tests/unit/test_concept_layer.nova | skimmed (script-analysed) | 180 | Working | 34 assertions (28 vs literal, 3 weak >=0/!=0/const); exercises concept_layer |
| CE/tests/unit/test_confidence_thresholds.nova | skimmed (script-analysed) | 66 | Working | 23 assertions (23 vs literal, 0 weak >=0/!=0/const); exercises confidence_thresholds |
| CE/tests/unit/test_consolidation.nova | reviewed | 68 | Working | 10 assertions (10 vs literal, 0 weak >=0/!=0/const); exercises consolidation |
| CE/tests/unit/test_constitution.nova | skimmed (script-analysed) | 45 | Working | 11 assertions (11 vs literal, 0 weak >=0/!=0/const); exercises constitution |
| CE/tests/unit/test_constitutional_filter.nova | skimmed (script-analysed) | 83 | Working | 22 assertions (22 vs literal, 0 weak >=0/!=0/const); exercises constitutional_filter |
| CE/tests/unit/test_context_bias.nova | skimmed (script-analysed) | 90 | Working | 9 assertions (6 vs literal, 0 weak >=0/!=0/const); exercises context_bias |
| CE/tests/unit/test_contradiction.nova | skimmed (script-analysed) | 349 | Working | 52 assertions (34 vs literal, 0 weak >=0/!=0/const); exercises contradiction |
| CE/tests/unit/test_corroboration.nova | skimmed (script-analysed) | 98 | Working | 20 assertions (20 vs literal, 0 weak >=0/!=0/const); exercises corroboration |
| CE/tests/unit/test_counterfactual.nova | reviewed | 51 | Working | 8 assertions (7 vs literal, 0 weak >=0/!=0/const); exercises counterfactual |
| CE/tests/unit/test_cross_kg_references.nova | skimmed (script-analysed) | 109 | Working | 20 assertions (18 vs literal, 1 weak >=0/!=0/const); exercises cross_kg_references |
| CE/tests/unit/test_daemon_tls_bootstrap.nova | skimmed (script-analysed) | 147 | Working | 9 assertions (7 vs literal, 0 weak >=0/!=0/const); exercises base64, tls_config, ed25519 |
| CE/tests/unit/test_debate.nova | skimmed (script-analysed) | 266 | Working | 46 assertions (43 vs literal, 2 weak >=0/!=0/const); exercises debate |
| CE/tests/unit/test_decay_exemption.nova | skimmed (script-analysed) | 91 | Working | 13 assertions (6 vs literal, 0 weak >=0/!=0/const); exercises verify, bayesian_updates |
| CE/tests/unit/test_decision_log.nova | skimmed (script-analysed) | 106 | Working | 25 assertions (23 vs literal, 0 weak >=0/!=0/const); exercises decision_log |
| CE/tests/unit/test_decision_log_durable.nova | skimmed (script-analysed) | 232 | Working | 38 assertions (36 vs literal, 2 weak >=0/!=0/const); has skip-as-pass path; exercises decision_log, sys_tagged |
| CE/tests/unit/test_decision_record.nova | skimmed (script-analysed) | 127 | Working | 33 assertions (31 vs literal, 0 weak >=0/!=0/const); exercises decision_record |
| CE/tests/unit/test_deflate.nova | skimmed (script-analysed) | 395 | Working | 46 assertions (45 vs literal, 1 weak >=0/!=0/const); exercises deflate_decode |
| CE/tests/unit/test_der.nova | skimmed (script-analysed) | 503 | Working | 73 assertions (71 vs literal, 0 weak >=0/!=0/const); exercises der |
| CE/tests/unit/test_detector_integral.nova | skimmed (script-analysed) | 366 | Working | 23 assertions (13 vs literal, 1 weak >=0/!=0/const); exercises image_detector |
| CE/tests/unit/test_differential_privacy.nova | skimmed (script-analysed) | 300 | Working | 52 assertions (40 vs literal, 3 weak >=0/!=0/const); exercises differential_privacy |
| CE/tests/unit/test_distributed_query.nova | skimmed (script-analysed) | 299 | Working | 36 assertions (33 vs literal, 2 weak >=0/!=0/const); exercises distributed_query, atom_store, multi_kg_manager, str_safe |
| CE/tests/unit/test_distributed_rules.nova | skimmed (script-analysed) | 365 | Working | 42 assertions (31 vs literal, 4 weak >=0/!=0/const); exercises gossip, distributed_rules, atom_store, multi_kg_manager |
| CE/tests/unit/test_dns_resolver.nova | skimmed (script-analysed) | 80 | Working | 17 assertions (16 vs literal, 0 weak >=0/!=0/const); exercises dns_resolver |
| CE/tests/unit/test_domain_contested.nova | skimmed (script-analysed) | 125 | Working | 23 assertions (14 vs literal, 6 weak >=0/!=0/const); exercises nl_query |
| CE/tests/unit/test_dp_budget_ui.nova | skimmed (script-analysed) | 398 | Working | 81 assertions (72 vs literal, 2 weak >=0/!=0/const); exercises differential_privacy, dp_budget_ui |
| CE/tests/unit/test_dr_async_fetch.nova | skimmed (script-analysed) | 731 | Working | 99 assertions (88 vs literal, 8 weak >=0/!=0/const); has skip-as-pass path; exercises gossip, distributed_rules, atom_store, multi_kg_manager |
| CE/tests/unit/test_dream_recombination.nova | reviewed | 42 | Working | 6 assertions (5 vs literal, 0 weak >=0/!=0/const); exercises dream_recombination |
| CE/tests/unit/test_drive_generators.nova | skimmed (script-analysed) | 58 | Working | 15 assertions (10 vs literal, 5 weak >=0/!=0/const); exercises drive_generators |
| CE/tests/unit/test_dtls12.nova | skimmed (script-analysed) | 2981 | Working | 519 assertions (439 vs literal, 41 weak >=0/!=0/const); exercises dtls12, str_safe |
| CE/tests/unit/test_dtls_cert_chain.nova | skimmed (script-analysed) | 425 | Working | 46 assertions (39 vs literal, 5 weak >=0/!=0/const); exercises dtls12, x509_verify, str_safe |
| CE/tests/unit/test_dtls_client_flight.nova | skimmed (script-analysed) | 661 | Working | 93 assertions (77 vs literal, 13 weak >=0/!=0/const); exercises dtls12, gossip_dtls_shim, sha256, p256 |
| CE/tests/unit/test_dtls_ext_parse.nova | skimmed (script-analysed) | 305 | Working | 45 assertions (43 vs literal, 0 weak >=0/!=0/const); exercises dtls12 |
| CE/tests/unit/test_dtls_server_flight.nova | skimmed (script-analysed) | 507 | Working | 93 assertions (86 vs literal, 4 weak >=0/!=0/const); exercises dtls12, gossip_dtls_shim, sha256, p256 |
| CE/tests/unit/test_ecdsa.nova | skimmed (script-analysed) | 435 | Working | 25 assertions (25 vs literal, 0 weak >=0/!=0/const); exercises ecdsa |
| CE/tests/unit/test_ed25519.nova | skimmed (script-analysed) | 558 | Working | 62 assertions (58 vs literal, 1 weak >=0/!=0/const); exercises ed25519 |
| CE/tests/unit/test_edition_gate.nova | skimmed (script-analysed) | 114 | Working | 50 assertions (33 vs literal, 14 weak >=0/!=0/const); exercises edition_gate |
| CE/tests/unit/test_effector_gate.nova | skimmed (script-analysed) | 86 | Working | 23 assertions (22 vs literal, 0 weak >=0/!=0/const); exercises effector_gate |
| CE/tests/unit/test_effectors.nova | skimmed (script-analysed) | 67 | Working | 19 assertions (18 vs literal, 0 weak >=0/!=0/const); exercises effector_code_exec, effector_file_ops, effector_http_action, effector_mcp |
| CE/tests/unit/test_emotion_plasticity_mod.nova | reviewed | 31 | Working | 7 assertions (6 vs literal, 0 weak >=0/!=0/const); exercises plasticity_mod |
| CE/tests/unit/test_entity_resolve.nova | skimmed (script-analysed) | 159 | Working | 29 assertions (22 vs literal, 0 weak >=0/!=0/const); exercises entity_resolve |
| CE/tests/unit/test_episode_storage.nova | skimmed (script-analysed) | 72 | Working | 19 assertions (18 vs literal, 1 weak >=0/!=0/const); exercises episode_storage |
| CE/tests/unit/test_episodic.nova | skimmed (script-analysed) | 370 | Working | 79 assertions (60 vs literal, 1 weak >=0/!=0/const); exercises episodic, snapshot_disk |
| CE/tests/unit/test_episodic_retrieval.nova | skimmed (script-analysed) | 411 | Working | 77 assertions (76 vs literal, 1 weak >=0/!=0/const); exercises episodic |
| CE/tests/unit/test_epistemic_status.nova | skimmed (script-analysed) | 113 | Working | 23 assertions (16 vs literal, 2 weak >=0/!=0/const); exercises epistemic_status |
| CE/tests/unit/test_event_dispatch.nova | skimmed (script-analysed) | 48 | Working | 15 assertions (13 vs literal, 0 weak >=0/!=0/const); exercises event_dispatch |
| CE/tests/unit/test_face_detect.nova | skimmed (script-analysed) | 346 | Working | 37 assertions (27 vs literal, 5 weak >=0/!=0/const); exercises image_face_detect |
| CE/tests/unit/test_face_recognize.nova | skimmed (script-analysed) | 416 | Working | 48 assertions (48 vs literal, 0 weak >=0/!=0/const); exercises image_face_recognize |
| CE/tests/unit/test_fed_daemon_attest.nova | skimmed (script-analysed) | 454 | Working | 54 assertions (47 vs literal, 6 weak >=0/!=0/const); exercises gossip, snapshot_attestation, ed25519, fed_slash |
| CE/tests/unit/test_fed_daemon_boot.nova | skimmed (script-analysed) | 361 | Working | 49 assertions (37 vs literal, 12 weak >=0/!=0/const); exercises atom_store, multi_kg_manager, reasoning_atoms, meta_observer |
| CE/tests/unit/test_fed_daemon_leader.nova | skimmed (script-analysed) | 388 | Working | 49 assertions (38 vs literal, 4 weak >=0/!=0/const); exercises gossip, leader_election |
| CE/tests/unit/test_fed_daemon_replication.nova | skimmed (script-analysed) | 439 | Working | 59 assertions (49 vs literal, 4 weak >=0/!=0/const); exercises gossip, snapshot_attestation, snapshot_replication, ed25519 |
| CE/tests/unit/test_fed_daemon_rules.nova | skimmed (script-analysed) | 336 | Working | 44 assertions (32 vs literal, 4 weak >=0/!=0/const); exercises atom_store, multi_kg_manager, rule_inference, gossip |
| CE/tests/unit/test_fed_daemon_transport.nova | skimmed (script-analysed) | 229 | Working | 21 assertions (19 vs literal, 2 weak >=0/!=0/const); exercises p256_keypair, fed_slash |
| CE/tests/unit/test_federated_aggregator.nova | skimmed (script-analysed) | 495 | Working | 90 assertions (72 vs literal, 10 weak >=0/!=0/const); exercises federated_aggregator |
| CE/tests/unit/test_fetch_route_learn.nova | skimmed (script-analysed) | 80 | Working | 11 assertions (10 vs literal, 0 weak >=0/!=0/const); exercises context_bias, spreading_activation, coherence_check, fetch_route_learn |
| CE/tests/unit/test_field25519.nova | skimmed (script-analysed) | 376 | Working | 25 assertions (11 vs literal, 0 weak >=0/!=0/const); exercises field25519 |
| CE/tests/unit/test_first_atoms.nova | skimmed (script-analysed) | 82 | Working | 18 assertions (2 vs literal, 13 weak >=0/!=0/const); exercises first_atoms |
| CE/tests/unit/test_first_nodes.nova | skimmed (script-analysed) | 84 | Working | 29 assertions (29 vs literal, 0 weak >=0/!=0/const); exercises first_nodes |
| CE/tests/unit/test_formal_chat.nova | skimmed (script-analysed) | 567 | Working | 76 assertions (59 vs literal, 6 weak >=0/!=0/const); exercises formal_chat, recheck, cascade |
| CE/tests/unit/test_formal_consistency.nova | skimmed (script-analysed) | 747 | Working | 117 assertions (97 vs literal, 7 weak >=0/!=0/const); exercises formal_chat, recheck, cascade, contradiction |
| CE/tests/unit/test_formal_ingest.nova | skimmed (script-analysed) | 123 | Working | 18 assertions (14 vs literal, 2 weak >=0/!=0/const); exercises formal_ingest |
| CE/tests/unit/test_forward_forward.nova | reviewed | 109 | Working | 8 assertions (4 vs literal, 0 weak >=0/!=0/const); exercises forward_forward |
| CE/tests/unit/test_forward_sim.nova | reviewed | 51 | Working | 7 assertions (7 vs literal, 0 weak >=0/!=0/const); exercises forward_sim |
| CE/tests/unit/test_gaps_register.nova | skimmed (script-analysed) | 286 | Working | 83 assertions (83 vs literal, 0 weak >=0/!=0/const); exercises gaps_register |
| CE/tests/unit/test_gate_router.nova | skimmed (script-analysed) | 115 | Working | 24 assertions (22 vs literal, 0 weak >=0/!=0/const); exercises gate_router |
| CE/tests/unit/test_gc_metrics.nova | skimmed (script-analysed) | 240 | Working | 86 assertions (80 vs literal, 4 weak >=0/!=0/const); exercises gc_metrics |
| CE/tests/unit/test_goal_engine.nova | skimmed (script-analysed) | 94 | Working | 20 assertions (17 vs literal, 0 weak >=0/!=0/const); exercises goal_engine |
| CE/tests/unit/test_goal_persistence.nova | skimmed (script-analysed) | 60 | Working | 11 assertions (10 vs literal, 0 weak >=0/!=0/const); exercises goal_persistence |
| CE/tests/unit/test_goal_templates.nova | skimmed (script-analysed) | 134 | Working | 34 assertions (31 vs literal, 3 weak >=0/!=0/const); exercises goal_templates |
| CE/tests/unit/test_goals_in_soul.nova | skimmed (script-analysed) | 35 | Working | 7 assertions (7 vs literal, 0 weak >=0/!=0/const); exercises goals_in_soul |
| CE/tests/unit/test_gossip.nova | skimmed (script-analysed) | 268 | Working | 34 assertions (28 vs literal, 2 weak >=0/!=0/const); exercises gossip |
| CE/tests/unit/test_gossip_dtls_shim.nova | skimmed (script-analysed) | 483 | Working | 57 assertions (45 vs literal, 7 weak >=0/!=0/const); exercises gossip_dtls_shim, dtls12 |
| CE/tests/unit/test_gossip_dtls_streams.nova | skimmed (script-analysed) | 254 | Working | 24 assertions (22 vs literal, 0 weak >=0/!=0/const); exercises gossip, gossip_dtls_shim, dtls12 |
| CE/tests/unit/test_gossip_noise.nova | skimmed (script-analysed) | 388 | Working | 44 assertions (25 vs literal, 7 weak >=0/!=0/const); exercises gossip |
| CE/tests/unit/test_gossip_relay.nova | skimmed (script-analysed) | 369 | Working | 61 assertions (55 vs literal, 6 weak >=0/!=0/const); exercises gossip, gossip_relay, str_safe |
| CE/tests/unit/test_gossip_relay_bin_dtls.nova | skimmed (script-analysed) | 285 | Working | 27 assertions (16 vs literal, 2 weak >=0/!=0/const); exercises gossip, gossip_dtls_shim, dtls12 |
| CE/tests/unit/test_graph_clustering.nova | skimmed (script-analysed) | 375 | Working | 57 assertions (30 vs literal, 0 weak >=0/!=0/const); exercises atom_store, multi_kg_manager, cross_kg_references, graph_clustering |
| CE/tests/unit/test_hdc_embed.nova | reviewed (assert lines sampled) | 371 | Working | 69 assertions (43 vs literal, 2 weak >=0/!=0/const); exercises hdc_embed, ann_index, multi_kg_manager, word_atoms |
| CE/tests/unit/test_hkdf_sha256.nova | skimmed (script-analysed) | 312 | Working | 29 assertions (29 vs literal, 0 weak >=0/!=0/const); exercises sha256, hkdf_sha256 |
| CE/tests/unit/test_hog_integral.nova | skimmed (script-analysed) | 517 | Working | 34 assertions (21 vs literal, 3 weak >=0/!=0/const); exercises image_hog |
| CE/tests/unit/test_holder_rate.nova | skimmed (script-analysed) | 318 | Working | 73 assertions (56 vs literal, 10 weak >=0/!=0/const); exercises holder_rate, str_safe |
| CE/tests/unit/test_http_client.nova | skimmed (script-analysed) | 358 | Working | 103 assertions (93 vs literal, 3 weak >=0/!=0/const); exercises http_client, internet_fetch |
| CE/tests/unit/test_hybrid_scheduler.nova | skimmed (script-analysed) | 38 | Working | 11 assertions (11 vs literal, 0 weak >=0/!=0/const); exercises hybrid_scheduler |
| CE/tests/unit/test_ice.nova | skimmed (script-analysed) | 466 | Working | 70 assertions (63 vs literal, 4 weak >=0/!=0/const); exercises ice, str_safe |
| CE/tests/unit/test_ice_turn.nova | skimmed (script-analysed) | 895 | Working | 142 assertions (130 vs literal, 7 weak >=0/!=0/const); exercises ice_turn, str_safe |
| CE/tests/unit/test_identity.nova | skimmed (script-analysed) | 41 | Working | 13 assertions (13 vs literal, 0 weak >=0/!=0/const); exercises identity |
| CE/tests/unit/test_image_canny.nova | skimmed (script-analysed) | 334 | Working | 22 assertions (14 vs literal, 4 weak >=0/!=0/const); exercises image_canny, image_sobel |
| CE/tests/unit/test_image_detector.nova | skimmed (script-analysed) | 381 | Working | 32 assertions (26 vs literal, 2 weak >=0/!=0/const); exercises image_detector |
| CE/tests/unit/test_image_harris.nova | skimmed (script-analysed) | 233 | Working | 19 assertions (15 vs literal, 1 weak >=0/!=0/const); exercises image_harris, str_safe |
| CE/tests/unit/test_image_hog.nova | skimmed (script-analysed) | 596 | Working | 58 assertions (47 vs literal, 5 weak >=0/!=0/const); exercises image_hog |
| CE/tests/unit/test_image_ocr.nova | skimmed (script-analysed) | 318 | Working | 40 assertions (35 vs literal, 1 weak >=0/!=0/const); exercises image_ocr |
| CE/tests/unit/test_image_panorama.nova | skimmed (script-analysed) | 457 | Working | 59 assertions (46 vs literal, 8 weak >=0/!=0/const); exercises image_panorama |
| CE/tests/unit/test_image_pgm.nova | skimmed (script-analysed) | 334 | Working | 43 assertions (38 vs literal, 5 weak >=0/!=0/const); exercises image_pgm |
| CE/tests/unit/test_image_records.nova | skimmed (script-analysed) | 315 | Working | 40 assertions (37 vs literal, 3 weak >=0/!=0/const); exercises image_records, perceptual_capsule, curriculum, atom_store |
| CE/tests/unit/test_image_segmentation.nova | skimmed (script-analysed) | 333 | Working | 69 assertions (61 vs literal, 3 weak >=0/!=0/const); exercises image_segmentation |
| CE/tests/unit/test_image_sift.nova | skimmed (script-analysed) | 273 | Working | 27 assertions (20 vs literal, 1 weak >=0/!=0/const); exercises image_sift |
| CE/tests/unit/test_image_sobel.nova | skimmed (script-analysed) | 216 | Working | 30 assertions (23 vs literal, 5 weak >=0/!=0/const); exercises image_sobel |
| CE/tests/unit/test_image_tracker.nova | skimmed (script-analysed) | 262 | Working | 40 assertions (40 vs literal, 0 weak >=0/!=0/const); exercises image_tracker |
| CE/tests/unit/test_imagination_engine.nova | reviewed | 58 | Working | 14 assertions (14 vs literal, 0 weak >=0/!=0/const); exercises imagination_engine |
| CE/tests/unit/test_ingest_chat_integration.nova | skimmed (script-analysed) | 106 | Working | 20 assertions (19 vs literal, 0 weak >=0/!=0/const); exercises ingestion_agent, llm_extractor |
| CE/tests/unit/test_ingest_conceptnet.nova | skimmed (script-analysed) | 94 | Working | 26 assertions (26 vs literal, 0 weak >=0/!=0/const); exercises conceptnet |
| CE/tests/unit/test_ingest_csv.nova | skimmed (script-analysed) | 114 | Working | 21 assertions (20 vs literal, 0 weak >=0/!=0/const); exercises csv_facts |
| CE/tests/unit/test_ingest_curriculum.nova | skimmed (script-analysed) | 99 | Working | 21 assertions (17 vs literal, 4 weak >=0/!=0/const); exercises curriculum, atom_store |
| CE/tests/unit/test_ingest_file_multimodal.nova | skimmed (script-analysed) | 329 | Working | 28 assertions (2 vs literal, 1 weak >=0/!=0/const); exercises rpc_verbs, capability, ingestion_agent, review_queue |
| CE/tests/unit/test_ingest_file_wire.nova | skimmed (script-analysed) | 1132 | Working | 143 assertions (14 vs literal, 0 weak >=0/!=0/const); exercises rpc_verbs, capability, ingestion_agent, review_queue |
| CE/tests/unit/test_ingest_llm_extractor.nova | skimmed (script-analysed) | 103 | Working | 15 assertions (14 vs literal, 0 weak >=0/!=0/const); exercises llm_extractor |
| CE/tests/unit/test_ingest_nt.nova | skimmed (script-analysed) | 98 | Working | 30 assertions (19 vs literal, 5 weak >=0/!=0/const); exercises nt_triples |
| CE/tests/unit/test_ingest_paper_meta.nova | skimmed (script-analysed) | 101 | Working | 20 assertions (18 vs literal, 0 weak >=0/!=0/const); exercises paper_meta |
| CE/tests/unit/test_ingest_pipeline.nova | skimmed (script-analysed) | 191 | Working | 26 assertions (20 vs literal, 5 weak >=0/!=0/const); exercises pipeline |
| CE/tests/unit/test_ingest_pipeline_capsule.nova | skimmed (script-analysed) | 153 | Working | 28 assertions (26 vs literal, 1 weak >=0/!=0/const); exercises pipeline, capsule_registry |
| CE/tests/unit/test_ingest_policy.nova | skimmed (script-analysed) | 816 | Working | 106 assertions (59 vs literal, 5 weak >=0/!=0/const); exercises policy, curriculum, review_queue, multi_kg_manager |
| CE/tests/unit/test_ingest_records.nova | skimmed (script-analysed) | 156 | Working | 39 assertions (36 vs literal, 0 weak >=0/!=0/const); exercises records |
| CE/tests/unit/test_ingest_records_capsule.nova | skimmed (script-analysed) | 132 | Working | 33 assertions (32 vs literal, 0 weak >=0/!=0/const); exercises records |
| CE/tests/unit/test_ingest_review_queue.nova | skimmed (script-analysed) | 133 | Working | 28 assertions (23 vs literal, 5 weak >=0/!=0/const); exercises review_queue |
| CE/tests/unit/test_ingest_source_registry.nova | skimmed (script-analysed) | 81 | Working | 26 assertions (25 vs literal, 1 weak >=0/!=0/const); exercises source_registry |
| CE/tests/unit/test_ingest_web_scheduler.nova | skimmed (script-analysed) | 103 | Working | 20 assertions (17 vs literal, 2 weak >=0/!=0/const); exercises web_scheduler |
| CE/tests/unit/test_ingest_wikidata.nova | skimmed (script-analysed) | 97 | Working | 24 assertions (24 vs literal, 0 weak >=0/!=0/const); exercises wikidata |
| CE/tests/unit/test_ingest_wordnet.nova | skimmed (script-analysed) | 94 | Working | 18 assertions (17 vs literal, 0 weak >=0/!=0/const); exercises wordnet |
| CE/tests/unit/test_ingestion_agent.nova | skimmed (script-analysed) | 133 | Working | 28 assertions (21 vs literal, 2 weak >=0/!=0/const); exercises ingestion_agent |
| CE/tests/unit/test_input_classifier.nova | skimmed (script-analysed) | 80 | Working | 35 assertions (34 vs literal, 1 weak >=0/!=0/const); exercises input_classifier |
| CE/tests/unit/test_input_transducer.nova | skimmed (script-analysed) | 55 | Working | 19 assertions (19 vs literal, 0 weak >=0/!=0/const); exercises input_transducer |
| CE/tests/unit/test_internet_fetch.nova | skimmed (script-analysed) | 147 | Working | 36 assertions (20 vs literal, 1 weak >=0/!=0/const); exercises internet_fetch |
| CE/tests/unit/test_jpeg_decode.nova | reviewed (assert lines sampled) | 672 | Working | 88 assertions (70 vs literal, 14 weak >=0/!=0/const); has skip-as-pass path; exercises jpeg_decode |
| CE/tests/unit/test_json.nova | skimmed (script-analysed) | 107 | Working | 47 assertions (46 vs literal, 0 weak >=0/!=0/const); exercises json |
| CE/tests/unit/test_json_records.nova | skimmed (script-analysed) | 314 | Working | 65 assertions (49 vs literal, 2 weak >=0/!=0/const); exercises json_records, curriculum, source_registry, ingestion_agent |
| CE/tests/unit/test_kg_filter.nova | skimmed (script-analysed) | 243 | Working | 22 assertions (22 vs literal, 0 weak >=0/!=0/const); exercises kg_filter, bake_manifest, multi_kg_manager, atom_store |
| CE/tests/unit/test_kg_query.nova | skimmed (script-analysed) | 327 | Working | 50 assertions (48 vs literal, 1 weak >=0/!=0/const); exercises atom_store, multi_kg_manager, cross_kg_references, query |
| CE/tests/unit/test_kg_query_agg.nova | skimmed (script-analysed) | 373 | Working | 67 assertions (67 vs literal, 0 weak >=0/!=0/const); exercises atom_store, multi_kg_manager, cross_kg_references, query |
| CE/tests/unit/test_kg_query_ext.nova | skimmed (script-analysed) | 367 | Working | 60 assertions (60 vs literal, 0 weak >=0/!=0/const); exercises atom_store, multi_kg_manager, cross_kg_references, query |
| CE/tests/unit/test_kg_rss_ingest.nova | skimmed (script-analysed) | 351 | Working | 59 assertions (46 vs literal, 7 weak >=0/!=0/const); has skip-as-pass path; exercises kg_rss_ingest, multi_kg_manager, atom_store, sys_tagged |
| CE/tests/unit/test_kg_sync.nova | skimmed (script-analysed) | 574 | Working | 169 assertions (137 vs literal, 26 weak >=0/!=0/const); exercises kg_sync, multi_kg_manager |
| CE/tests/unit/test_kg_sync_delta.nova | skimmed (script-analysed) | 502 | Working | 93 assertions (89 vs literal, 2 weak >=0/!=0/const); exercises kg_sync |
| CE/tests/unit/test_kg_temporal.nova | skimmed (script-analysed) | 539 | Working | 80 assertions (80 vs literal, 0 weak >=0/!=0/const); exercises atom_store, multi_kg_manager, temporal |
| CE/tests/unit/test_lbp.nova | skimmed (script-analysed) | 531 | Working | 45 assertions (37 vs literal, 3 weak >=0/!=0/const); exercises image_lbp |
| CE/tests/unit/test_leader_election.nova | skimmed (script-analysed) | 328 | Working | 40 assertions (39 vs literal, 1 weak >=0/!=0/const); exercises leader_election |
| CE/tests/unit/test_learn_pipeline.nova | reviewed (assert lines sampled) | 172 | Working | 21 assertions (15 vs literal, 5 weak >=0/!=0/const); exercises learn_pipeline |
| CE/tests/unit/test_learn_tag.nova | skimmed (script-analysed) | 356 | Working | 40 assertions (31 vs literal, 0 weak >=0/!=0/const); exercises harness only |
| CE/tests/unit/test_learning_policy.nova | skimmed (script-analysed) | 71 | Working | 24 assertions (18 vs literal, 0 weak >=0/!=0/const); exercises learning_policy |
| CE/tests/unit/test_lexical_anchor.nova | skimmed (script-analysed) | 109 | Working | 27 assertions (26 vs literal, 1 weak >=0/!=0/const); exercises lexical_anchor |
| CE/tests/unit/test_licenses.nova | skimmed (script-analysed) | 90 | Working | 38 assertions (35 vs literal, 0 weak >=0/!=0/const); exercises licenses |
| CE/tests/unit/test_link_prediction.nova | skimmed (script-analysed) | 461 | Working | 77 assertions (67 vs literal, 0 weak >=0/!=0/const); exercises atom_store, multi_kg_manager, cross_kg_references, link_prediction |
| CE/tests/unit/test_lipsync.nova | skimmed (script-analysed) | 522 | Working | 41 assertions (25 vs literal, 0 weak >=0/!=0/const); exercises lipsync |
| CE/tests/unit/test_list_safe.nova | skimmed (script-analysed) | 77 | Working | 23 assertions (23 vs literal, 0 weak >=0/!=0/const); exercises list_safe |
| CE/tests/unit/test_lk_mulacc_simd.nova | skimmed (script-analysed) | 438 | Working | 28 assertions (5 vs literal, 0 weak >=0/!=0/const); exercises image_optical_flow |
| CE/tests/unit/test_lk_u8_simd.nova | skimmed (script-analysed) | 376 | Working | 34 assertions (12 vs literal, 1 weak >=0/!=0/const); exercises image_optical_flow |
| CE/tests/unit/test_llm_transcript.nova | skimmed (script-analysed) | 74 | Working | 10 assertions (10 vs literal, 0 weak >=0/!=0/const); exercises llm_transcript |
| CE/tests/unit/test_long_horizon_goals.nova | skimmed (script-analysed) | 46 | Working | 9 assertions (8 vs literal, 0 weak >=0/!=0/const); exercises long_horizon_goals |
| CE/tests/unit/test_loop_action.nova | skimmed (script-analysed) | 137 | Working | 11 assertions (8 vs literal, 1 weak >=0/!=0/const); exercises loop_action |
| CE/tests/unit/test_loop_coordination.nova | skimmed (script-analysed) | 39 | Working | 16 assertions (16 vs literal, 0 weak >=0/!=0/const); exercises loop_coordination |
| CE/tests/unit/test_loop_emotion.nova | reviewed | 24 | Working | 3 assertions (0 vs literal, 0 weak >=0/!=0/const); exercises loop_emotion |
| CE/tests/unit/test_loop_goals.nova | reviewed | 18 | Working | 3 assertions (0 vs literal, 1 weak >=0/!=0/const); exercises loop_goals |
| CE/tests/unit/test_loop_imagination_idle.nova | reviewed | 30 | Working | 2 assertions (1 vs literal, 0 weak >=0/!=0/const); exercises loop_imagination_idle |
| CE/tests/unit/test_loop_memory.nova | reviewed | 31 | Working | 4 assertions (4 vs literal, 0 weak >=0/!=0/const); exercises loop_memory |
| CE/tests/unit/test_loop_perception.nova | reviewed | 73 | Working | 8 assertions (3 vs literal, 0 weak >=0/!=0/const); exercises loop_perception |
| CE/tests/unit/test_loop_reasoning.nova | reviewed | 32 | Working | 3 assertions (2 vs literal, 0 weak >=0/!=0/const); exercises loop_reasoning |
| CE/tests/unit/test_louvain.nova | skimmed (script-analysed) | 431 | Working | 67 assertions (30 vs literal, 2 weak >=0/!=0/const); exercises atom_store, multi_kg_manager, cross_kg_references, louvain |
| CE/tests/unit/test_loyalty.nova | skimmed (script-analysed) | 33 | Working | 9 assertions (9 vs literal, 0 weak >=0/!=0/const); exercises loyalty |
| CE/tests/unit/test_lp_audit.nova | skimmed (script-analysed) | 88 | Working | 15 assertions (14 vs literal, 0 weak >=0/!=0/const); exercises learn_pipeline |
| CE/tests/unit/test_lp_corroboration.nova | skimmed (script-analysed) | 75 | Working | 5 assertions (5 vs literal, 0 weak >=0/!=0/const); exercises learn_pipeline |
| CE/tests/unit/test_maintenance.nova | skimmed (script-analysed) | 122 | Working | 18 assertions (16 vs literal, 0 weak >=0/!=0/const); exercises maintenance |
| CE/tests/unit/test_md5.nova | skimmed (script-analysed) | 285 | Working | 16 assertions (10 vs literal, 0 weak >=0/!=0/const); exercises md5 |
| CE/tests/unit/test_medical_pack.nova | skimmed (script-analysed) | 156 | Working | 22 assertions (2 vs literal, 17 weak >=0/!=0/const); exercises medical_pack, str_safe, imagination_engine |
| CE/tests/unit/test_merkle.nova | skimmed (script-analysed) | 550 | Working | 58 assertions (43 vs literal, 3 weak >=0/!=0/const); exercises merkle, str_safe |
| CE/tests/unit/test_merkle_signing.nova | skimmed (script-analysed) | 367 | Working | 51 assertions (44 vs literal, 4 weak >=0/!=0/const); exercises merkle_signing, ed25519 |
| CE/tests/unit/test_meta_observer.nova | skimmed (script-analysed) | 202 | Working | 35 assertions (33 vs literal, 2 weak >=0/!=0/const); exercises meta_observer, reflection_loop |
| CE/tests/unit/test_meta_observer_feedback.nova | skimmed (script-analysed) | 273 | Working | 54 assertions (53 vs literal, 0 weak >=0/!=0/const); exercises meta_observer, source_authority |
| CE/tests/unit/test_mkgc_scale.nova | reviewed | 121 | Working | 5 assertions (5 vs literal, 0 weak >=0/!=0/const); exercises multi_kg_consistency |
| CE/tests/unit/test_moment_stream.nova | skimmed (script-analysed) | 76 | Working | 29 assertions (29 vs literal, 0 weak >=0/!=0/const); exercises moment_stream |
| CE/tests/unit/test_motor_map.nova | skimmed (script-analysed) | 169 | Working | 52 assertions (51 vs literal, 0 weak >=0/!=0/const); exercises motor_map |
| CE/tests/unit/test_multi_kg_consistency.nova | skimmed (script-analysed) | 138 | Working | 15 assertions (9 vs literal, 0 weak >=0/!=0/const); exercises multi_kg_consistency |
| CE/tests/unit/test_multi_kg_manager.nova | skimmed (script-analysed) | 308 | Working | 86 assertions (80 vs literal, 0 weak >=0/!=0/const); exercises multi_kg_manager, cross_kg_references, reasoning_atoms, episodic |
| CE/tests/unit/test_nat_traversal.nova | reviewed (assert lines sampled) | 1204 | Working | 217 assertions (190 vs literal, 22 weak >=0/!=0/const); exercises nat_traversal, str_safe |
| CE/tests/unit/test_neighborhood_activation.nova | skimmed (script-analysed) | 486 | Working | 47 assertions (12 vs literal, 18 weak >=0/!=0/const); exercises context_bias, neighborhood, spreading_activation |
| CE/tests/unit/test_nl_audit.nova | skimmed (script-analysed) | 87 | Working | 13 assertions (11 vs literal, 2 weak >=0/!=0/const); exercises nl_audit |
| CE/tests/unit/test_nl_chat_llm_fallback.nova | skimmed (script-analysed) | 150 | Working | 26 assertions (23 vs literal, 0 weak >=0/!=0/const); exercises nl_llm_sidecar, nl_metrics, grammar_parser, query_shape |
| CE/tests/unit/test_nl_chat_wire.nova | skimmed (script-analysed) | 223 | Working | 29 assertions (17 vs literal, 1 weak >=0/!=0/const); exercises grammar_parser, executor, templater, multi_kg_manager |
| CE/tests/unit/test_nl_contested.nova | skimmed (script-analysed) | 87 | Working | 14 assertions (6 vs literal, 5 weak >=0/!=0/const); exercises nl_query |
| CE/tests/unit/test_nl_executor.nova | skimmed (script-analysed) | 530 | Working | 76 assertions (66 vs literal, 7 weak >=0/!=0/const); exercises executor, grammar_parser |
| CE/tests/unit/test_nl_generate.nova | reviewed (assert lines sampled) | 99 | Working | 35 assertions (35 vs literal, 0 weak >=0/!=0/const); exercises nl_generate |
| CE/tests/unit/test_nl_grammar_parser.nova | skimmed (script-analysed) | 1263 | Working | 314 assertions (314 vs literal, 0 weak >=0/!=0/const); exercises grammar_parser |
| CE/tests/unit/test_nl_intent_classifier.nova | reviewed (assert lines sampled) | 339 | Working | 71 assertions (53 vs literal, 1 weak >=0/!=0/const); exercises nl_intent_classifier, nl_metrics, query_shape, str_safe |
| CE/tests/unit/test_nl_llm_parser.nova | skimmed (script-analysed) | 271 | Working | 66 assertions (57 vs literal, 9 weak >=0/!=0/const); exercises llm_parser, query_shape, str_safe |
| CE/tests/unit/test_nl_llm_sidecar.nova | skimmed (script-analysed) | 237 | Working | 53 assertions (51 vs literal, 2 weak >=0/!=0/const); exercises nl_llm_sidecar, nl_metrics, llm_parser, query_shape |
| CE/tests/unit/test_nl_metrics.nova | skimmed (script-analysed) | 224 | Working | 74 assertions (69 vs literal, 0 weak >=0/!=0/const); exercises nl_metrics, str_safe |
| CE/tests/unit/test_nl_pipeline_gap_recording.nova | skimmed (script-analysed) | 237 | Working | 17 assertions (5 vs literal, 2 weak >=0/!=0/const); exercises rpc_verbs, multi_kg_manager, atom_store, skill_registry |
| CE/tests/unit/test_nl_query.nova | skimmed (script-analysed) | 224 | Working | 55 assertions (53 vs literal, 0 weak >=0/!=0/const); exercises nl_query |
| CE/tests/unit/test_nl_query_shape.nova | skimmed (script-analysed) | 237 | Working | 86 assertions (74 vs literal, 7 weak >=0/!=0/const); exercises query_shape |
| CE/tests/unit/test_nl_rpc_llm_fallback.nova | skimmed (script-analysed) | 262 | Working | 43 assertions (29 vs literal, 0 weak >=0/!=0/const); exercises rpc_verbs, nl_llm_sidecar, nl_intent_classifier, nl_metrics |
| CE/tests/unit/test_nl_rpc_metrics_verb.nova | skimmed (script-analysed) | 481 | Working | 90 assertions (10 vs literal, 0 weak >=0/!=0/const); exercises rpc_verbs, nl_llm_sidecar, nl_metrics, query_shape |
| CE/tests/unit/test_nl_rpc_server.nova | skimmed (script-analysed) | 259 | Working | 37 assertions (4 vs literal, 0 weak >=0/!=0/const); exercises rpc_server, rpc_verbs, multi_kg_manager, atom_store |
| CE/tests/unit/test_nl_rpc_verbs.nova | skimmed (script-analysed) | 461 | Working | 87 assertions (10 vs literal, 0 weak >=0/!=0/const); exercises rpc_verbs, query_shape, multi_kg_manager, atom_store |
| CE/tests/unit/test_nl_templater.nova | skimmed (script-analysed) | 388 | Working | 60 assertions (15 vs literal, 3 weak >=0/!=0/const); exercises templater, executor, query_shape, skill_supervisor |
| CE/tests/unit/test_node_pool_manager.nova | reviewed (assert lines sampled) | 114 | Working | 40 assertions (37 vs literal, 2 weak >=0/!=0/const); exercises node_pool_manager |
| CE/tests/unit/test_noise_xk.nova | skimmed (script-analysed) | 353 | Working | 44 assertions (27 vs literal, 10 weak >=0/!=0/const); exercises chacha20, noise_xk, str_safe |
| CE/tests/unit/test_number_words.nova | skimmed (script-analysed) | 112 | Working | 45 assertions (45 vs literal, 0 weak >=0/!=0/const); exercises number_words |
| CE/tests/unit/test_ocean_conditioning.nova | skimmed (script-analysed) | 43 | Working | 8 assertions (6 vs literal, 0 weak >=0/!=0/const); exercises ocean_conditioning |
| CE/tests/unit/test_openie.nova | skimmed (script-analysed) | 168 | Working | 64 assertions (55 vs literal, 9 weak >=0/!=0/const); exercises openie |
| CE/tests/unit/test_operand_builder.nova | skimmed (script-analysed) | 206 | Working | 41 assertions (38 vs literal, 0 weak >=0/!=0/const); exercises operand_builder, goal_templates |
| CE/tests/unit/test_ops_pack.nova | skimmed (script-analysed) | 88 | Working | 10 assertions (1 vs literal, 7 weak >=0/!=0/const); exercises ops_runbook_pack, imagination_engine |
| CE/tests/unit/test_optical_flow.nova | skimmed (script-analysed) | 429 | Working | 53 assertions (49 vs literal, 3 weak >=0/!=0/const); exercises image_optical_flow, str_safe |
| CE/tests/unit/test_optical_flow_perpixel.nova | skimmed (script-analysed) | 475 | Working | 34 assertions (18 vs literal, 3 weak >=0/!=0/const); exercises image_optical_flow, str_safe |
| CE/tests/unit/test_optical_flow_pyramid.nova | skimmed (script-analysed) | 424 | Working | 52 assertions (38 vs literal, 5 weak >=0/!=0/const); exercises image_optical_flow, str_safe |
| CE/tests/unit/test_orb.nova | skimmed (script-analysed) | 478 | Working | 43 assertions (23 vs literal, 4 weak >=0/!=0/const); exercises image_orb |
| CE/tests/unit/test_output_generation.nova | skimmed (script-analysed) | 123 | Working | 14 assertions (8 vs literal, 3 weak >=0/!=0/const); exercises output_generation |
| CE/tests/unit/test_override_mechanism.nova | skimmed (script-analysed) | 96 | Working | 27 assertions (27 vs literal, 0 weak >=0/!=0/const); exercises override_mechanism |
| CE/tests/unit/test_override_wire.nova | skimmed (script-analysed) | 333 | Working | 89 assertions (79 vs literal, 8 weak >=0/!=0/const); exercises override_wire, override_mechanism, multi_kg_manager, atom_store |
| CE/tests/unit/test_ownership.nova | skimmed (script-analysed) | 1059 | Working | 173 assertions (84 vs literal, 0 weak >=0/!=0/const); exercises ownership, capability, rpc_verbs, multi_kg_manager |
| CE/tests/unit/test_p256.nova | skimmed (script-analysed) | 401 | Working | 52 assertions (38 vs literal, 11 weak >=0/!=0/const); exercises p256, str_safe |
| CE/tests/unit/test_p256_keypair_load.nova | skimmed (script-analysed) | 254 | Working | 31 assertions (19 vs literal, 7 weak >=0/!=0/const); exercises p256_keypair |
| CE/tests/unit/test_pack_biology.nova | skimmed (script-analysed) | 109 | Working | 23 assertions (6 vs literal, 17 weak >=0/!=0/const); exercises ingestion_agent, multi_kg_consistency |
| CE/tests/unit/test_pack_physics.nova | skimmed (script-analysed) | 80 | Working | 6 assertions (6 vs literal, 0 weak >=0/!=0/const); exercises ingestion_agent, multi_kg_consistency |
| CE/tests/unit/test_pack_politics.nova | skimmed (script-analysed) | 103 | Working | 17 assertions (6 vs literal, 11 weak >=0/!=0/const); exercises ingestion_agent, multi_kg_consistency |
| CE/tests/unit/test_pack_registry.nova | skimmed (script-analysed) | 163 | Working | 27 assertions (9 vs literal, 5 weak >=0/!=0/const); exercises pack_registry, imagination_engine |
| CE/tests/unit/test_pack_religion.nova | skimmed (script-analysed) | 99 | Working | 14 assertions (6 vs literal, 8 weak >=0/!=0/const); exercises ingestion_agent, multi_kg_consistency |
| CE/tests/unit/test_pack_solar_system.nova | skimmed (script-analysed) | 108 | Working | 16 assertions (15 vs literal, 0 weak >=0/!=0/const); exercises ingestion_agent, multi_kg_consistency |
| CE/tests/unit/test_pack_world_history.nova | skimmed (script-analysed) | 62 | Working | 9 assertions (5 vs literal, 4 weak >=0/!=0/const); exercises ingestion_agent |
| CE/tests/unit/test_pagerank.nova | skimmed (script-analysed) | 537 | Working | 87 assertions (49 vs literal, 6 weak >=0/!=0/const); exercises atom_store, multi_kg_manager, cross_kg_references, pagerank |
| CE/tests/unit/test_part_lifecycle.nova | skimmed (script-analysed) | 78 | Working | 21 assertions (18 vs literal, 0 weak >=0/!=0/const); exercises part_lifecycle |
| CE/tests/unit/test_part_registry.nova | skimmed (script-analysed) | 76 | Working | 26 assertions (24 vs literal, 1 weak >=0/!=0/const); exercises part_registry |
| CE/tests/unit/test_pattern_capsule.nova | skimmed (script-analysed) | 338 | Working | 68 assertions (43 vs literal, 7 weak >=0/!=0/const); exercises pattern_capsule, str_safe |
| CE/tests/unit/test_pattern_pack.nova | skimmed (script-analysed) | 902 | Working | 144 assertions (85 vs literal, 6 weak >=0/!=0/const); exercises pattern_pack, pattern_capsule, rpc_verbs, capability |
| CE/tests/unit/test_pdf_text.nova | skimmed (script-analysed) | 168 | Working | 18 assertions (15 vs literal, 0 weak >=0/!=0/const); exercises pdf_text, openie |
| CE/tests/unit/test_pem_truststore.nova | skimmed (script-analysed) | 50 | Working | 5 assertions (5 vs literal, 0 weak >=0/!=0/const); exercises pem_truststore |
| CE/tests/unit/test_perception_atoms.nova | skimmed (script-analysed) | 200 | Working | 77 assertions (69 vs literal, 5 weak >=0/!=0/const); exercises perception_atoms |
| CE/tests/unit/test_perception_module.nova | skimmed (script-analysed) | 221 | Working | 45 assertions (30 vs literal, 1 weak >=0/!=0/const); exercises perception_module |
| CE/tests/unit/test_perceptual_capsule.nova | skimmed (script-analysed) | 187 | Working | 61 assertions (59 vs literal, 0 weak >=0/!=0/const); exercises perceptual_capsule, curriculum, atom_store, str_safe |
| CE/tests/unit/test_permission_tiers.nova | skimmed (script-analysed) | 63 | Working | 24 assertions (24 vs literal, 0 weak >=0/!=0/const); exercises permission_tiers |
| CE/tests/unit/test_persona.nova | skimmed (script-analysed) | 204 | Working | 85 assertions (84 vs literal, 1 weak >=0/!=0/const); exercises persona |
| CE/tests/unit/test_persona_export.nova | skimmed (script-analysed) | 185 | Working | 59 assertions (52 vs literal, 6 weak >=0/!=0/const); exercises persona_export |
| CE/tests/unit/test_persona_project.nova | skimmed (script-analysed) | 180 | Working | 37 assertions (27 vs literal, 4 weak >=0/!=0/const); exercises persona_project |
| CE/tests/unit/test_persona_registry.nova | skimmed (script-analysed) | 117 | Working | 36 assertions (33 vs literal, 1 weak >=0/!=0/const); exercises persona_registry |
| CE/tests/unit/test_phoneme_atoms.nova | skimmed (script-analysed) | 54 | Working | 12 assertions (10 vs literal, 1 weak >=0/!=0/const); exercises phoneme_atoms |
| CE/tests/unit/test_pitch_auto.nova | skimmed (script-analysed) | 336 | Working | 31 assertions (16 vs literal, 0 weak >=0/!=0/const); exercises audio_pitch, audio_synth |
| CE/tests/unit/test_planner.nova | skimmed (script-analysed) | 124 | Working | 21 assertions (20 vs literal, 0 weak >=0/!=0/const); exercises planner |
| CE/tests/unit/test_plasticity_modulation.nova | skimmed (script-analysed) | 40 | Working | 10 assertions (10 vs literal, 0 weak >=0/!=0/const); exercises plasticity_modulation |
| CE/tests/unit/test_png_decode.nova | skimmed (script-analysed) | 504 | Working | 44 assertions (35 vs literal, 9 weak >=0/!=0/const); exercises deflate_decode, png_decode |
| CE/tests/unit/test_poly1305.nova | skimmed (script-analysed) | 334 | Working | 47 assertions (47 vs literal, 0 weak >=0/!=0/const); exercises chacha20, poly1305 |
| CE/tests/unit/test_predictive_coding_runtime.nova | skimmed (script-analysed) | 95 | Working | 30 assertions (22 vs literal, 0 weak >=0/!=0/const); exercises predictive_coding_runtime |
| CE/tests/unit/test_preference_snapshot.nova | skimmed (script-analysed) | 188 | Working | 36 assertions (29 vs literal, 1 weak >=0/!=0/const); exercises session_snapshot, user_preference, str_safe |
| CE/tests/unit/test_preprocess.nova | skimmed (script-analysed) | 460 | Working | 100 assertions (76 vs literal, 5 weak >=0/!=0/const); exercises preprocess, str_safe |
| CE/tests/unit/test_promotion.nova | skimmed (script-analysed) | 141 | Working | 38 assertions (37 vs literal, 0 weak >=0/!=0/const); exercises promotion |
| CE/tests/unit/test_promotion_pass.nova | skimmed (script-analysed) | 168 | Working | 23 assertions (22 vs literal, 1 weak >=0/!=0/const); exercises promotion_pass |
| CE/tests/unit/test_proof_checker.nova | skimmed (script-analysed) | 285 | Working | 56 assertions (42 vs literal, 1 weak >=0/!=0/const); exercises proof_checker, str_safe |
| CE/tests/unit/test_proof_serial.nova | skimmed (script-analysed) | 188 | Working | 20 assertions (20 vs literal, 0 weak >=0/!=0/const); exercises proof_serial |
| CE/tests/unit/test_proofs.nova | skimmed (script-analysed) | 65 | Working | 15 assertions (15 vs literal, 0 weak >=0/!=0/const); exercises proofs |
| CE/tests/unit/test_psola.nova | skimmed (script-analysed) | 297 | Working | 34 assertions (9 vs literal, 3 weak >=0/!=0/const); exercises audio_psola, audio_pitch, audio_synth |
| CE/tests/unit/test_raft_cluster.nova | skimmed (script-analysed) | 104 | Working | 21 assertions (21 vs literal, 0 weak >=0/!=0/const); exercises raft_cluster |
| CE/tests/unit/test_raft_core.nova | skimmed (script-analysed) | 160 | Working | 35 assertions (35 vs literal, 0 weak >=0/!=0/const); exercises raft_core |
| CE/tests/unit/test_raft_membership.nova | skimmed (script-analysed) | 94 | Working | 22 assertions (22 vs literal, 0 weak >=0/!=0/const); exercises raft_membership |
| CE/tests/unit/test_raft_partition.nova | skimmed (script-analysed) | 81 | Working | 15 assertions (15 vs literal, 0 weak >=0/!=0/const); exercises raft_partition |
| CE/tests/unit/test_reader.nova | skimmed (script-analysed) | 62 | Working | 13 assertions (12 vs literal, 0 weak >=0/!=0/const); exercises reader |
| CE/tests/unit/test_reader_xref_traversal.nova | skimmed (script-analysed) | 440 | Working | 51 assertions (45 vs literal, 3 weak >=0/!=0/const); exercises neighborhood |
| CE/tests/unit/test_realtime_pacer.nova | skimmed (script-analysed) | 149 | Working | 27 assertions (20 vs literal, 3 weak >=0/!=0/const); exercises realtime_pacer |
| CE/tests/unit/test_reasoning_atoms.nova | skimmed (script-analysed) | 147 | Working | 30 assertions (26 vs literal, 0 weak >=0/!=0/const); exercises reasoning_atoms |
| CE/tests/unit/test_reasoning_bench.nova | reviewed (assert lines sampled) | 223 | Working | 45 assertions (37 vs literal, 2 weak >=0/!=0/const); exercises reasoning_bench |
| CE/tests/unit/test_reasoning_module.nova | skimmed (script-analysed) | 72 | Working | 12 assertions (11 vs literal, 0 weak >=0/!=0/const); exercises reasoning_module |
| CE/tests/unit/test_reasoning_workflow.nova | skimmed (script-analysed) | 231 | Working | 37 assertions (31 vs literal, 2 weak >=0/!=0/const); exercises formal_chat, recheck, contradiction |
| CE/tests/unit/test_recheck.nova | skimmed (script-analysed) | 198 | Working | 27 assertions (23 vs literal, 1 weak >=0/!=0/const); exercises recheck, formal_ingest |
| CE/tests/unit/test_reflection_loop.nova | skimmed (script-analysed) | 157 | Working | 16 assertions (6 vs literal, 3 weak >=0/!=0/const); exercises reflection_loop |
| CE/tests/unit/test_relay_ranking.nova | skimmed (script-analysed) | 310 | Working | 42 assertions (41 vs literal, 0 weak >=0/!=0/const); exercises gossip, gossip_relay, str_safe |
| CE/tests/unit/test_relay_secure.nova | skimmed (script-analysed) | 376 | Working | 44 assertions (40 vs literal, 4 weak >=0/!=0/const); exercises gossip, gossip_relay, gossip_relay_secure, noise_xk |
| CE/tests/unit/test_relay_secure_binary.nova | skimmed (script-analysed) | 432 | Working | 51 assertions (41 vs literal, 7 weak >=0/!=0/const); exercises gossip, gossip_relay, gossip_relay_secure, noise_xk |
| CE/tests/unit/test_research_skill.nova | skimmed (script-analysed) | 280 | Working | 25 assertions (24 vs literal, 0 weak >=0/!=0/const); exercises skill_dispatch, research_skill, ingestion_agent |
| CE/tests/unit/test_research_sources.nova | skimmed (script-analysed) | 214 | Working | 58 assertions (42 vs literal, 0 weak >=0/!=0/const); exercises research_sources, str_safe |
| CE/tests/unit/test_resonance_engine.nova | skimmed (script-analysed) | 100 | Working | 20 assertions (20 vs literal, 0 weak >=0/!=0/const); exercises resonance_engine |
| CE/tests/unit/test_reversibility_classifier.nova | skimmed (script-analysed) | 53 | Working | 21 assertions (21 vs literal, 0 weak >=0/!=0/const); exercises reversibility_classifier |
| CE/tests/unit/test_rng.nova | skimmed (script-analysed) | 474 | Working | 56 assertions (52 vs literal, 0 weak >=0/!=0/const); exercises sha256, chacha20, rng |
| CE/tests/unit/test_router_audit.nova | skimmed (script-analysed) | 72 | Working | 6 assertions (5 vs literal, 1 weak >=0/!=0/const); exercises cognitive_router |
| CE/tests/unit/test_rsa.nova | skimmed (script-analysed) | 66 | Working | 5 assertions (5 vs literal, 0 weak >=0/!=0/const); exercises rsa |
| CE/tests/unit/test_rule_explain.nova | skimmed (script-analysed) | 360 | Working | 54 assertions (39 vs literal, 5 weak >=0/!=0/const); exercises atom_store, multi_kg_manager, rule_inference, rule_explain |
| CE/tests/unit/test_rule_inference.nova | reviewed (assert lines sampled) | 358 | Working | 47 assertions (43 vs literal, 0 weak >=0/!=0/const); exercises atom_store, multi_kg_manager, rule_inference |
| CE/tests/unit/test_scenario_planner.nova | skimmed (script-analysed) | 43 | Working | 6 assertions (6 vs literal, 0 weak >=0/!=0/const); exercises scenario_planner |
| CE/tests/unit/test_schema_migration.nova | skimmed (script-analysed) | 407 | Working | 78 assertions (68 vs literal, 2 weak >=0/!=0/const); exercises schema_migration, snapshot_disk, snapshot_reader, atom_store |
| CE/tests/unit/test_schemas.nova | skimmed (script-analysed) | 78 | Working | 13 assertions (13 vs literal, 0 weak >=0/!=0/const); exercises schemas, str_safe |
| CE/tests/unit/test_scram.nova | skimmed (script-analysed) | 515 | Working | 43 assertions (40 vs literal, 0 weak >=0/!=0/const); exercises scram, str_safe |
| CE/tests/unit/test_search.nova | skimmed (script-analysed) | 124 | Working | 11 assertions (10 vs literal, 1 weak >=0/!=0/const); exercises search |
| CE/tests/unit/test_search_back.nova | skimmed (script-analysed) | 85 | Working | 10 assertions (9 vs literal, 1 weak >=0/!=0/const); exercises search_back |
| CE/tests/unit/test_search_uni.nova | skimmed (script-analysed) | 81 | Working | 6 assertions (6 vs literal, 0 weak >=0/!=0/const); exercises search_uni |
| CE/tests/unit/test_secure_aggregation.nova | skimmed (script-analysed) | 942 | Working | 170 assertions (114 vs literal, 21 weak >=0/!=0/const); exercises secure_aggregation, str_safe |
| CE/tests/unit/test_secure_channel.nova | skimmed (script-analysed) | 169 | Working | 16 assertions (13 vs literal, 2 weak >=0/!=0/const); exercises chacha20, secure_channel, str_safe |
| CE/tests/unit/test_self_confidence_verb.nova | skimmed (script-analysed) | 335 | Working | 46 assertions (6 vs literal, 0 weak >=0/!=0/const); exercises rpc_verbs, multi_kg_manager, atom_store, capability |
| CE/tests/unit/test_self_gaps_verb.nova | skimmed (script-analysed) | 307 | Working | 51 assertions (5 vs literal, 0 weak >=0/!=0/const); exercises rpc_verbs, capability, gaps_register, str_safe |
| CE/tests/unit/test_self_improve.nova | reviewed (assert lines sampled) | 195 | Working | 55 assertions (32 vs literal, 2 weak >=0/!=0/const); exercises self_improve, state, skills_kg |
| CE/tests/unit/test_self_learning_triggers.nova | reviewed (assert lines sampled) | 90 | Working | 27 assertions (27 vs literal, 0 weak >=0/!=0/const); exercises self_learning_triggers |
| CE/tests/unit/test_self_model_query.nova | reviewed | 44 | Working | 9 assertions (0 vs literal, 9 weak >=0/!=0/const); exercises self_model_query, str_safe |
| CE/tests/unit/test_self_override_list_verb.nova | skimmed (script-analysed) | 252 | Working | 42 assertions (5 vs literal, 0 weak >=0/!=0/const); exercises rpc_verbs, capability, override_wire, str_safe |
| CE/tests/unit/test_self_override_verb.nova | skimmed (script-analysed) | 447 | Working | 66 assertions (14 vs literal, 0 weak >=0/!=0/const); exercises rpc_verbs, capability, override_wire, override_mechanism |
| CE/tests/unit/test_semantic_search.nova | reviewed (assert lines sampled) | 387 | Working | 74 assertions (62 vs literal, 2 weak >=0/!=0/const); exercises semantic_search |
| CE/tests/unit/test_sensor_fusion.nova | skimmed (script-analysed) | 360 | Working | 59 assertions (51 vs literal, 0 weak >=0/!=0/const); exercises sensor_fusion, str_safe |
| CE/tests/unit/test_session.nova | skimmed (script-analysed) | 255 | Working | 66 assertions (57 vs literal, 5 weak >=0/!=0/const); exercises session, identity, state, str_safe |
| CE/tests/unit/test_session_attach_fed.nova | skimmed (script-analysed) | 125 | Working | 29 assertions (29 vs literal, 0 weak >=0/!=0/const); exercises session, str_safe |
| CE/tests/unit/test_session_paths.nova | skimmed (script-analysed) | 200 | Working | 22 assertions (22 vs literal, 0 weak >=0/!=0/const); exercises session |
| CE/tests/unit/test_session_snapshot.nova | skimmed (script-analysed) | 1204 | Working | 228 assertions (136 vs literal, 12 weak >=0/!=0/const); exercises session_snapshot, capability, skill_signature, ownership |
| CE/tests/unit/test_sha1.nova | skimmed (script-analysed) | 352 | Working | 17 assertions (12 vs literal, 0 weak >=0/!=0/const); exercises sha1 |
| CE/tests/unit/test_sha256.nova | skimmed (script-analysed) | 373 | Working | 20 assertions (16 vs literal, 0 weak >=0/!=0/const); exercises sha256 |
| CE/tests/unit/test_sift_descriptor.nova | skimmed (script-analysed) | 495 | Working | 33 assertions (24 vs literal, 1 weak >=0/!=0/const); exercises image_sift |
| CE/tests/unit/test_signal_dispatch.nova | skimmed (script-analysed) | 127 | Working | 51 assertions (47 vs literal, 0 weak >=0/!=0/const); exercises signal_dispatch |
| CE/tests/unit/test_simd_production.nova | skimmed (script-analysed) | 368 | Working | 35 assertions (12 vs literal, 1 weak >=0/!=0/const); exercises image_stereo, image_optical_flow |
| CE/tests/unit/test_skill_install_wire.nova | skimmed (script-analysed) | 370 | Working | 23 assertions (2 vs literal, 0 weak >=0/!=0/const); exercises rpc_verbs, capability, skill_signature, ed25519 |
| CE/tests/unit/test_skill_manifest.nova | skimmed (script-analysed) | 95 | Working | 36 assertions (36 vs literal, 0 weak >=0/!=0/const); exercises skill_manifest |
| CE/tests/unit/test_skill_registry.nova | skimmed (script-analysed) | 169 | Working | 44 assertions (39 vs literal, 4 weak >=0/!=0/const); exercises skill_registry |
| CE/tests/unit/test_skill_run_scoping.nova | skimmed (script-analysed) | 276 | Working | 28 assertions (13 vs literal, 0 weak >=0/!=0/const); exercises ownership, capability, rpc_verbs, multi_kg_manager |
| CE/tests/unit/test_skill_signature.nova | skimmed (script-analysed) | 344 | Working | 50 assertions (34 vs literal, 2 weak >=0/!=0/const); exercises skill_signature, ed25519, skill_manifest, echo_skill |
| CE/tests/unit/test_skill_supervisor.nova | skimmed (script-analysed) | 284 | Working | 46 assertions (32 vs literal, 11 weak >=0/!=0/const); exercises skill_dispatch, echo_skill, capsule_registry, persona |
| CE/tests/unit/test_skills_kg.nova | skimmed (script-analysed) | 112 | Working | 26 assertions (24 vs literal, 0 weak >=0/!=0/const); exercises skills_kg |
| CE/tests/unit/test_slic.nova | skimmed (script-analysed) | 364 | Working | 61 assertions (32 vs literal, 7 weak >=0/!=0/const); exercises image_superpixels |
| CE/tests/unit/test_slot_index.nova | skimmed (script-analysed) | 154 | Working | 23 assertions (22 vs literal, 0 weak >=0/!=0/const); exercises slot_index |
| CE/tests/unit/test_snapshot_attestation.nova | skimmed (script-analysed) | 390 | Working | 66 assertions (62 vs literal, 4 weak >=0/!=0/const); exercises snapshot_attestation, ed25519 |
| CE/tests/unit/test_snapshot_broadcast_hook.nova | skimmed (script-analysed) | 228 | Working | 27 assertions (21 vs literal, 6 weak >=0/!=0/const); exercises snapshot_broadcast_hook, snapshot_attestation, gossip, ed25519 |
| CE/tests/unit/test_snapshot_compaction.nova | skimmed (script-analysed) | 411 | Working | 48 assertions (42 vs literal, 4 weak >=0/!=0/const); exercises snapshot_disk, snapshot_compaction, str_safe |
| CE/tests/unit/test_snapshot_delta.nova | skimmed (script-analysed) | 654 | Working | 84 assertions (68 vs literal, 13 weak >=0/!=0/const); exercises snapshot_disk, snapshot_delta |
| CE/tests/unit/test_snapshot_disk.nova | skimmed (script-analysed) | 127 | Working | 31 assertions (29 vs literal, 2 weak >=0/!=0/const); exercises snapshot_disk |
| CE/tests/unit/test_snapshot_disk_full.nova | skimmed (script-analysed) | 628 | Working | 127 assertions (94 vs literal, 24 weak >=0/!=0/const); exercises snapshot_disk, state, values, ask_user_to_teach |
| CE/tests/unit/test_snapshot_episodic.nova | skimmed (script-analysed) | 261 | Working | 51 assertions (47 vs literal, 4 weak >=0/!=0/const); exercises snapshot_disk |
| CE/tests/unit/test_snapshot_migrate.nova | skimmed (script-analysed) | 182 | Working | 37 assertions (30 vs literal, 7 weak >=0/!=0/const); exercises snapshot_disk, snapshot_reader |
| CE/tests/unit/test_snapshot_reader.nova | skimmed (script-analysed) | 111 | Working | 25 assertions (25 vs literal, 0 weak >=0/!=0/const); exercises snapshot_reader |
| CE/tests/unit/test_snapshot_replication.nova | skimmed (script-analysed) | 313 | Working | 73 assertions (68 vs literal, 3 weak >=0/!=0/const); exercises snapshot_replication, snapshot_attestation, ed25519, snapshot_writer |
| CE/tests/unit/test_snapshot_selfmodel.nova | skimmed (script-analysed) | 194 | Working | 38 assertions (30 vs literal, 8 weak >=0/!=0/const); exercises snapshot_disk |
| CE/tests/unit/test_snapshot_synapses.nova | skimmed (script-analysed) | 427 | Working | 89 assertions (76 vs literal, 13 weak >=0/!=0/const); exercises snapshot_disk, part_registry, first_nodes |
| CE/tests/unit/test_snapshot_writer.nova | skimmed (script-analysed) | 69 | Working | 27 assertions (27 vs literal, 0 weak >=0/!=0/const); exercises snapshot_writer |
| CE/tests/unit/test_soul_state.nova | skimmed (script-analysed) | 40 | Working | 11 assertions (11 vs literal, 0 weak >=0/!=0/const); exercises state |
| CE/tests/unit/test_source_authority.nova | skimmed (script-analysed) | 59 | Working | 22 assertions (16 vs literal, 0 weak >=0/!=0/const); exercises source_authority |
| CE/tests/unit/test_source_whitelist.nova | skimmed (script-analysed) | 42 | Working | 14 assertions (6 vs literal, 0 weak >=0/!=0/const); exercises source_whitelist |
| CE/tests/unit/test_speaker_id.nova | skimmed (script-analysed) | 401 | Working | 53 assertions (51 vs literal, 2 weak >=0/!=0/const); exercises audio_speaker_id, audio_synth |
| CE/tests/unit/test_spreading_activation.nova | reviewed | 78 | Working | 9 assertions (6 vs literal, 0 weak >=0/!=0/const); exercises context_bias, spreading_activation |
| CE/tests/unit/test_srtp.nova | skimmed (script-analysed) | 1088 | Working | 131 assertions (100 vs literal, 8 weak >=0/!=0/const); exercises srtp |
| CE/tests/unit/test_steelman.nova | skimmed (script-analysed) | 80 | Working | 11 assertions (9 vs literal, 2 weak >=0/!=0/const); exercises steelman |
| CE/tests/unit/test_stereo.nova | skimmed (script-analysed) | 350 | Working | 54 assertions (48 vs literal, 4 weak >=0/!=0/const); exercises image_stereo, str_safe |
| CE/tests/unit/test_stereo_quality.nova | skimmed (script-analysed) | 453 | Working | 42 assertions (32 vs literal, 5 weak >=0/!=0/const); exercises image_stereo, str_safe |
| CE/tests/unit/test_stereo_sgm.nova | skimmed (script-analysed) | 452 | Working | 39 assertions (20 vs literal, 5 weak >=0/!=0/const); exercises image_stereo, str_safe |
| CE/tests/unit/test_stereo_u8_simd.nova | skimmed (script-analysed) | 389 | Working | 25 assertions (15 vs literal, 2 weak >=0/!=0/const); exercises image_stereo |
| CE/tests/unit/test_str_safe.nova | skimmed (script-analysed) | 68 | Working | 27 assertions (27 vs literal, 0 weak >=0/!=0/const); exercises str_safe |
| CE/tests/unit/test_stream_audio.nova | skimmed (script-analysed) | 29 | Working | 10 assertions (8 vs literal, 2 weak >=0/!=0/const); exercises stream_audio |
| CE/tests/unit/test_stream_http.nova | skimmed (script-analysed) | 78 | Working | 24 assertions (24 vs literal, 0 weak >=0/!=0/const); exercises stream_http |
| CE/tests/unit/test_stream_stdin.nova | skimmed (script-analysed) | 134 | Working | 28 assertions (27 vs literal, 1 weak >=0/!=0/const); exercises stream_stdin, hybrid_scheduler, part_lifecycle |
| CE/tests/unit/test_stream_unix_socket.nova | skimmed (script-analysed) | 46 | Working | 14 assertions (13 vs literal, 1 weak >=0/!=0/const); exercises stream_unix_socket |
| CE/tests/unit/test_stt_seam.nova | skimmed (script-analysed) | 218 | Working | 27 assertions (25 vs literal, 1 weak >=0/!=0/const); exercises stt_seam |
| CE/tests/unit/test_stun_rfc8489.nova | skimmed (script-analysed) | 632 | Working | 135 assertions (91 vs literal, 20 weak >=0/!=0/const); exercises stun_rfc8489, str_safe |
| CE/tests/unit/test_style_capsule.nova | skimmed (script-analysed) | 342 | Working | 52 assertions (25 vs literal, 0 weak >=0/!=0/const); exercises style_capsule, templater, skill_supervisor, persona |
| CE/tests/unit/test_synapse_graph.nova | reviewed (assert lines sampled) | 165 | Working | 55 assertions (49 vs literal, 2 weak >=0/!=0/const); exercises synapse_graph, signal_dispatch |
| CE/tests/unit/test_syntax_atoms.nova | skimmed (script-analysed) | 74 | Working | 14 assertions (13 vs literal, 1 weak >=0/!=0/const); exercises syntax_atoms |
| CE/tests/unit/test_table.nova | skimmed (script-analysed) | 92 | Working | 24 assertions (24 vs literal, 0 weak >=0/!=0/const); exercises table, query, str_safe |
| CE/tests/unit/test_themes.nova | skimmed (script-analysed) | 31 | Working | 7 assertions (7 vs literal, 0 weak >=0/!=0/const); exercises themes |
| CE/tests/unit/test_theory_of_mind.nova | reviewed | 47 | Working | 13 assertions (12 vs literal, 0 weak >=0/!=0/const); exercises theory_of_mind |
| CE/tests/unit/test_three_factor.nova | reviewed | 113 | Working | 18 assertions (6 vs literal, 6 weak >=0/!=0/const); exercises synapse_graph |
| CE/tests/unit/test_tick_driver.nova | skimmed (script-analysed) | 263 | Working | 38 assertions (24 vs literal, 7 weak >=0/!=0/const); exercises tick_driver |
| CE/tests/unit/test_tick_loop.nova | reviewed | 31 | Working | 8 assertions (7 vs literal, 0 weak >=0/!=0/const); exercises tick_loop |
| CE/tests/unit/test_tls13_keyschedule.nova | skimmed (script-analysed) | 136 | Working | 6 assertions (5 vs literal, 0 weak >=0/!=0/const); exercises tls13_client |
| CE/tests/unit/test_tls_alerts.nova | skimmed (script-analysed) | 142 | Working | 31 assertions (26 vs literal, 4 weak >=0/!=0/const); exercises tls_alerts, str_safe |
| CE/tests/unit/test_tls_cert.nova | skimmed (script-analysed) | 365 | Working | 41 assertions (40 vs literal, 0 weak >=0/!=0/const); exercises ed25519, tls_cert |
| CE/tests/unit/test_tls_cert_chain.nova | skimmed (script-analysed) | 323 | Working | 14 assertions (14 vs literal, 0 weak >=0/!=0/const); exercises ed25519, tls_cert, x509 |
| CE/tests/unit/test_tls_config.nova | skimmed (script-analysed) | 173 | Working | 22 assertions (22 vs literal, 0 weak >=0/!=0/const); exercises tls_config, ed25519 |
| CE/tests/unit/test_tls_handshake_msgs.nova | skimmed (script-analysed) | 406 | Working | 54 assertions (46 vs literal, 8 weak >=0/!=0/const); exercises tls_handshake |
| CE/tests/unit/test_tls_kdf.nova | skimmed (script-analysed) | 339 | Working | 27 assertions (24 vs literal, 0 weak >=0/!=0/const); exercises sha256, hkdf_sha256, tls_kdf |
| CE/tests/unit/test_tls_keyshare.nova | skimmed (script-analysed) | 191 | Working | 14 assertions (13 vs literal, 1 weak >=0/!=0/const); exercises field25519, x25519, tls_keyshare |
| CE/tests/unit/test_tls_keyshare_rng.nova | skimmed (script-analysed) | 211 | Working | 27 assertions (27 vs literal, 0 weak >=0/!=0/const); exercises field25519, x25519, rng, tls_keyshare |
| CE/tests/unit/test_tls_record_aead.nova | skimmed (script-analysed) | 315 | Working | 41 assertions (37 vs literal, 0 weak >=0/!=0/const); exercises chacha20, poly1305, chacha20_poly1305, tls_record |
| CE/tests/unit/test_tls_scaffold.nova | skimmed (script-analysed) | 207 | Working | 70 assertions (65 vs literal, 5 weak >=0/!=0/const); exercises tls_config, tls_record, tls_handshake, tls_wire_hook |
| CE/tests/unit/test_tls_session.nova | skimmed (script-analysed) | 251 | Working | 23 assertions (21 vs literal, 0 weak >=0/!=0/const); exercises rng, ed25519, tls_session, tls_handshake |
| CE/tests/unit/test_tls_session_tamper.nova | skimmed (script-analysed) | 332 | Working | 15 assertions (15 vs literal, 0 weak >=0/!=0/const); exercises rng, ed25519, tls_session, tls_handshake |
| CE/tests/unit/test_tls_state.nova | skimmed (script-analysed) | 174 | Working | 68 assertions (67 vs literal, 1 weak >=0/!=0/const); exercises tls_state, str_safe |
| CE/tests/unit/test_tls_transcript.nova | skimmed (script-analysed) | 227 | Working | 16 assertions (16 vs literal, 0 weak >=0/!=0/const); exercises tls_transcript, sha256 |
| CE/tests/unit/test_tls_wire_hook.nova | skimmed (script-analysed) | 292 | Working | 40 assertions (35 vs literal, 3 weak >=0/!=0/const); exercises tls_config, tls_wire_hook, rng, ed25519 |
| CE/tests/unit/test_tool.nova | skimmed (script-analysed) | 94 | Working | 25 assertions (24 vs literal, 0 weak >=0/!=0/const); exercises tool |
| CE/tests/unit/test_tool_goal_plan.nova | skimmed (script-analysed) | 122 | Working | 15 assertions (14 vs literal, 0 weak >=0/!=0/const); exercises tool_goal_plan |
| CE/tests/unit/test_tool_use.nova | skimmed (script-analysed) | 152 | Working | 28 assertions (27 vs literal, 0 weak >=0/!=0/const); exercises tool_use, moment_stream |
| CE/tests/unit/test_truststore_dir.nova | skimmed (script-analysed) | 221 | Working | 20 assertions (20 vs literal, 0 weak >=0/!=0/const); exercises pem_truststore |
| CE/tests/unit/test_turn.nova | skimmed (script-analysed) | 2197 | Working | 406 assertions (326 vs literal, 4 weak >=0/!=0/const); exercises turn |
| CE/tests/unit/test_turn_server.nova | skimmed (script-analysed) | 792 | Working | 111 assertions (90 vs literal, 6 weak >=0/!=0/const); exercises turn, turn_server |
| CE/tests/unit/test_type_of_probe.nova | skimmed (script-analysed) | 51 | Working | 11 assertions (11 vs literal, 0 weak >=0/!=0/const); exercises harness only |
| CE/tests/unit/test_unify.nova | skimmed (script-analysed) | 82 | Working | 14 assertions (10 vs literal, 4 weak >=0/!=0/const); exercises unify |
| CE/tests/unit/test_update_apply_verb.nova | skimmed (script-analysed) | 176 | Working | 17 assertions (14 vs literal, 0 weak >=0/!=0/const); exercises rpc_verbs, capability, child_mode, str_safe |
| CE/tests/unit/test_update_delta.nova | skimmed (script-analysed) | 482 | Working | 67 assertions (45 vs literal, 4 weak >=0/!=0/const); exercises update_delta, bake, bake_manifest, bundle_signing |
| CE/tests/unit/test_user_preference.nova | skimmed (script-analysed) | 297 | Working | 78 assertions (78 vs literal, 0 weak >=0/!=0/const); exercises user_preference, str_safe |
| CE/tests/unit/test_user_preference_verbs.nova | skimmed (script-analysed) | 386 | Working | 48 assertions (21 vs literal, 1 weak >=0/!=0/const); has skip-as-pass path; exercises rpc_verbs, capability, user_preference, str_safe |
| CE/tests/unit/test_values.nova | reviewed | 28 | Working | 8 assertions (8 vs literal, 0 weak >=0/!=0/const); exercises values |
| CE/tests/unit/test_verify.nova | skimmed (script-analysed) | 710 | Working | 87 assertions (84 vs literal, 1 weak >=0/!=0/const); exercises verify |
| CE/tests/unit/test_verify_big.nova | skimmed (script-analysed) | 118 | Working | 11 assertions (11 vs literal, 0 weak >=0/!=0/const); exercises proof_serial |
| CE/tests/unit/test_video_motion_vectors.nova | skimmed (script-analysed) | 239 | Working | 30 assertions (25 vs literal, 3 weak >=0/!=0/const); exercises video_motion_vectors |
| CE/tests/unit/test_video_perception.nova | skimmed (script-analysed) | 37 | Working | 11 assertions (11 vs literal, 0 weak >=0/!=0/const); exercises video_perception |
| CE/tests/unit/test_video_records.nova | skimmed (script-analysed) | 194 | Working | 35 assertions (31 vs literal, 4 weak >=0/!=0/const); exercises video_records, perceptual_capsule, curriculum, atom_store |
| CE/tests/unit/test_video_smooth.nova | skimmed (script-analysed) | 214 | Working | 25 assertions (24 vs literal, 0 weak >=0/!=0/const); exercises video_smooth |
| CE/tests/unit/test_video_y4m.nova | skimmed (script-analysed) | 284 | Working | 34 assertions (30 vs literal, 4 weak >=0/!=0/const); exercises video_y4m |
| CE/tests/unit/test_visibility_composed.nova | skimmed (script-analysed) | 173 | Working | 25 assertions (25 vs literal, 0 weak >=0/!=0/const); exercises ownership, user_preference |
| CE/tests/unit/test_visual_perception.nova | skimmed (script-analysed) | 36 | Working | 12 assertions (12 vs literal, 0 weak >=0/!=0/const); exercises visual_perception |
| CE/tests/unit/test_voice_clone.nova | skimmed (script-analysed) | 407 | Working | 55 assertions (39 vs literal, 8 weak >=0/!=0/const); exercises audio_voice_clone, audio_synth, audio_pitch |
| CE/tests/unit/test_voice_conversation.nova | skimmed (script-analysed) | 264 | Working | 27 assertions (16 vs literal, 0 weak >=0/!=0/const); exercises harness only |
| CE/tests/unit/test_voice_dialog.nova | skimmed (script-analysed) | 2142 | Working | 319 assertions (241 vs literal, 0 weak >=0/!=0/const); exercises atom_store, multi_kg_manager, whisper_backend |
| CE/tests/unit/test_vosk_backend.nova | skimmed (script-analysed) | 307 | Working | 45 assertions (36 vs literal, 5 weak >=0/!=0/const); has skip-as-pass path; exercises vosk_backend, stt_seam |
| CE/tests/unit/test_webrtc.nova | skimmed (script-analysed) | 321 | Working | 59 assertions (50 vs literal, 9 weak >=0/!=0/const); exercises webrtc, str_safe |
| CE/tests/unit/test_whisper_backend.nova | skimmed (script-analysed) | 465 | Working | 50 assertions (47 vs literal, 1 weak >=0/!=0/const); exercises whisper_backend, stt_seam |
| CE/tests/unit/test_wire_pagination.nova | skimmed (script-analysed) | 790 | Working | 147 assertions (20 vs literal, 0 weak >=0/!=0/const); exercises rpc_verbs, nl_metrics, multi_kg_manager, atom_store |
| CE/tests/unit/test_word_atoms.nova | skimmed (script-analysed) | 332 | Working | 115 assertions (110 vs literal, 1 weak >=0/!=0/const); exercises word_atoms |
| CE/tests/unit/test_world_model.nova | skimmed (script-analysed) | 108 | Working | 40 assertions (38 vs literal, 0 weak >=0/!=0/const); exercises world_model |
| CE/tests/unit/test_x25519.nova | skimmed (script-analysed) | 296 | Working | 15 assertions (15 vs literal, 0 weak >=0/!=0/const); exercises field25519, x25519 |
| CE/tests/unit/test_x509.nova | skimmed (script-analysed) | 612 | Working | 55 assertions (49 vs literal, 2 weak >=0/!=0/const); exercises x509 |
| CE/tests/unit/test_x509_r92.nova | skimmed (script-analysed) | 507 | Working | 60 assertions (60 vs literal, 0 weak >=0/!=0/const); exercises der, x509 |
| CE/tests/unit/test_x509_verify.nova | skimmed (script-analysed) | 105 | Working | 14 assertions (13 vs literal, 0 weak >=0/!=0/const); exercises x509_verify, str_safe |
| CE/tests/unit/test_yaml_records.nova | skimmed (script-analysed) | 637 | Working | 129 assertions (93 vs literal, 1 weak >=0/!=0/const); exercises yaml_records, curriculum, source_registry, atom_store |
| CE/tests/unit/fixtures/x509_test_certs.nova | skimmed (data) | 441 | Working | Hard-coded test certificate byte arrays for x509 tests |
| CE/tests/integration/README.md | reviewed | 100 | Doc | Describes scenario/admin/failmode scripts |
| CE/tests/integration/_lib.sh | reviewed | 130 | Working | Shared integration-test helpers. Source this from every tests/integration/*.sh script. It exports: [0 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/admin_help_status.sh | skimmed (header+grep) | 146 | Working | Admin commands -- /help, /status, /history, unknown command, quit/exit/empty. These are the read-only commands plus the exit paths; bundled together s [33 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/admin_learn_meta.sh | skimmed (header+grep) | 78 | Working | Admin commands -- /learn (TOPIC/URL/FILE source-kind tagging) and /meta. [7 assert calls; ext: whisper; skip refs: 0] |
| CE/tests/integration/admin_reflect_halt.sh | skimmed (header+grep) | 66 | Working | Admin commands -- /reflect, /halt, /resume. [8 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/admin_save_load.sh | skimmed (header+grep) | 61 | Working | Admin commands -- /save and /load edge cases. [12 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/admin_teach_pin.sh | skimmed (header+grep) | 75 | Working | Admin commands -- /teach and /pin edge cases. [10 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/failmode_chat_long_line.sh | skimmed (header+grep) | 91 | Working | Failure mode -- piping a long line into chat stdin. The original test target was 10K characters; while writing this test we [6 assert calls; ext: python3; skip refs: 0] |
| CE/tests/integration/failmode_constitution_bypass_attempts.sh | reviewed | 105 | Working | Failure mode -- multiple rephrasings of the "exfiltrate" intent must all trigger the constitutional veto, even the ones that AVOID the literal [2 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/failmode_corrupt_snap_recovery.sh | skimmed (header+grep) | 77 | Working | Failure mode -- /load on a truncated snapshot reports a clear error and the running session is unaffected. [6 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/failmode_disk_full_save.sh | skimmed (header+grep) | 58 | Partial | Failure mode -- /save to a write-denied path reports failure cleanly. We can't realistically exhaust /tmp in a sandbox, so we exercise the [7 assert calls; ext: none; skip refs: 2] |
| CE/tests/integration/failmode_dlog_corrupt_tail.sh | skimmed (header+grep) | 90 | Working | Failure mode -- dlog with appended garbage at the tail recovers cleanly. The dl_open recovery loop is supposed to: [5 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/failmode_kgsync_subscriber_drop.sh | skimmed (header+grep) | 180 | Partial | Failure mode -- kg-sync subscriber dies mid-stream. Scenario: publisher binds and accepts; subscriber connects + handshakes; [2 assert calls; ext: none; skip refs: 1] |
| CE/tests/integration/failmode_killed_mid_fsync.sh | skimmed (header+grep) | 90 | Working | Failure mode -- kill -9 during the /save window must not leave a partial snapshot at the final path. [4 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/failmode_runaway_atom_births.sh | skimmed (header+grep) | 94 | Working | Failure mode -- feeding many distinct unknown words rapidly must not blow up the KG. The atom_birth_monitor's gating + the seed/teach paths should res [4 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/failmode_save_load_ping_pong.sh | skimmed (header+grep) | 101 | Working | Failure mode -- alternating /save and /load 20 times in ONE chat session must not progressively corrupt state. After 20 round-trips, the knowledge [8 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/failmode_session_eviction.sh | skimmed (header+grep) | 118 | Partial | Failure mode -- web.py LRU eviction: with CE_WEB_MAX_SESSIONS=2, hitting 5 unique cookies must evict the first 3 (LRU) and keep the most-recent 2 [8 assert calls; ext: python3,curl; skip refs: 3] |
| CE/tests/integration/failmode_soul_mood_overflow.sh | skimmed (header+grep) | 85 | Working | Failure mode -- repeated high-arousal triggers must not overflow the mood valence / arousal counters. [1 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/failmode_unknown_kg_load.sh | skimmed (header+grep) | 52 | Partial | Failure mode -- /load on a snapshot containing a kgs.atoms[N].kg label that the running daemon does not know. [7 assert calls; ext: none; skip refs: 4] |
| CE/tests/integration/failmode_web_concurrent_burst.sh | skimmed (header+grep) | 156 | Partial | Failure mode -- 20 concurrent POSTs to /api/chat with the same cookie must serialize. The web.py ChatChild.send acquires request_lock for the whole [4 assert calls; ext: python3,curl; skip refs: 3] |
| CE/tests/integration/failmode_web_huge_payload.sh | skimmed (header+grep) | 171 | Partial | Failure mode -- POSTing a 1MB body to /api/chat must not crash the server. The web.py handler reads Content-Length bytes and json.loads them. A huge [1 assert calls; ext: python3,curl; skip refs: 3] |
| CE/tests/integration/scenario_a2_full_state.sh | skimmed (header+grep) | 100 | Working | Scenario A2 -- Full-state durability across abrupt restart. Extends scenario_a (which only checks widget survives) to verify the [14 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_a3_dlog.sh | skimmed (header+grep) | 67 | Working | Scenario A3 -- Decision-log durability across abrupt restart (P0.7). Boot fresh -> send 3 messages (each generates dlog entries) -> SIGKILL -> [3 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_a_durability.sh | skimmed (header+grep) | 74 | Working | Scenario A -- Durability across abrupt restart. Boot fresh -> /teach widget -> /save -> SIGKILL -> relaunch -> /load -> [8 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_aa_atom_search.sh | skimmed (header+grep) | 180 | Partial | Scenario AA -- /api/atoms search endpoint (web atom-search UI). python3 scripts/web.py (background) -> GET /api/atoms?q=fever -> verify the [7 assert calls; ext: python3,curl; skip refs: 2] |
| CE/tests/integration/scenario_aaa_psola.sh | skimmed (header+grep) | 129 | Working | Scenario AAA -- R12D: TD-PSOLA pitch shifting + time stretching. [13 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_aaaa_rule_inference.sh | skimmed (header+grep) | 252 | Working | Scenario AAAA -- forward-chaining rule inference over the KG (R20B). Companion to scenario_kkk_query.sh (R15D mini-SPARQL declarative [19 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_aaaaa_dialog.sh | skimmed (header+grep) | 164 | Working | Scenario AAAAA -- R25B.2: multi-turn voice dialogue (conversation state + follow-up handling). Letter `aaaaa` (5x) is the first free 5-letter [13 assert calls; ext: whisper; skip refs: 0] |
| CE/tests/integration/scenario_b_neighborhood.sh | skimmed (header+grep) | 42 | Working | Scenario B -- Neighborhood paraphrase. Boot fresh -> ask "fever" -> verify the reasoning surfaces a related [4 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_bb_why_deep.sh | skimmed (header+grep) | 107 | Working | Scenario BB -- /why-deep [N] recursive decision tree. Boot the chat, teach a word (`/teach widget`), ask it back, then run [10 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_bbb_dp_ui.sh | skimmed (header+grep) | 121 | Working | Scenario BBB -- /dp admin command + status pane DP budget reporting (R12F / ADR-0053 follow-up). [21 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_bbbb_sensor_fusion.sh | skimmed (header+grep) | 167 | Working | Scenario BBBB -- /fuse cross-modal sensor fusion: image + audio coregistered observation primitive (R20C). [7 assert calls; ext: python3; skip refs: 0] |
| CE/tests/integration/scenario_bbbbb_kg_delta.sh | skimmed (header+grep) | 351 | Working | Scenario BBBBB -- R29F: kg_sync delta-compression on top of R23C snapshot replication. Verifies the new src/federation/kg_sync.nova module: [22 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_c_learn.sh | skimmed (header+grep) | 134 | Partial | Scenario C -- Multi-source /learn. Two passes: [5 assert calls; ext: curl; skip refs: 1] |
| CE/tests/integration/scenario_cc_image_match.sh | skimmed (header+grep) | 120 | Working | Scenario CC -- /match_images PGM admin command end-to-end (P3.3 cont. v2, the deferred half of SIFT: 128-D descriptor + Lowe-ratio-test matcher). [7 assert calls; ext: python3; skip refs: 0] |
| CE/tests/integration/scenario_ccc_lk_perpixel.sh | skimmed (header+grep) | 225 | Working | Scenario CCC -- /flow_pp PGM admin command end-to-end (R13B, full per-pixel pyramidal Lucas-Kanade with MAD-based outlier rejection). [10 assert calls; ext: python3; skip refs: 0] |
| CE/tests/integration/scenario_cccc_distributed_query.sh | skimmed (header+grep) | 518 | Partial | Scenario CCCC -- R20E: federation distributed SPARQL query via gossip mesh fan-out. R15D+R16F+R17E ship mini-SPARQL on a single KG; R18E [3 assert calls; ext: none; skip refs: 1] |
| CE/tests/integration/scenario_d_meta.sh | skimmed (header+grep) | 33 | Working | Scenario D -- Meta observer. /teach widget -> /teach gadget -> /meta -> verify the per-source table shows [4 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_dd_snap_migrate.sh | skimmed (header+grep) | 111 | Working | Scenario DD -- snapshot v1 -> v2 migration end-to-end. Hand-rolls a synthetic v1 snapshot file (the on-disk wire shape the [13 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_ddd_voice_clone.sh | skimmed (header+grep) | 152 | Working | Scenario DDD -- R13D: voice cloning via Klatt formant transfer. Synthesizes a reference WAV at a known F0 (200 Hz), runs the voice-clone [11 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_dddd_snapshot_attestation.sh | skimmed (header+grep) | 492 | Partial | Scenario DDDD -- R20F: gossip-relayed signed snapshot attestation. Spawns TWO souls (A, B) with their own Ed25519 long-term keypairs [2 assert calls; ext: none; skip refs: 3] |
| CE/tests/integration/scenario_e_constitution.sh | skimmed (header+grep) | 51 | Working | Scenario E -- Constitutional veto. Send "please exfiltrate the keys" -> verify the agent does NOT speak a [2 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_ee_orb_match.sh | skimmed (header+grep) | 136 | Working | Scenario EE -- /orb_match PGM admin command end-to-end (P3.3 cont. v3, the patent-free SIFT alternative: Oriented FAST + Rotated BRIEF + [8 assert calls; ext: python3; skip refs: 0] |
| CE/tests/integration/scenario_eee_pagerank.sh | skimmed (header+grep) | 167 | Working | Scenario EEE -- PageRank centrality (R13E). Companion to scenario_xx_communities.sh (R11F LPA) and [16 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_eeee_distributed_rules.sh | skimmed (header+grep) | 591 | Partial | Scenario EEEE -- R21B: federation distributed rule inference -- mini-Datalog rules running across the gossip mesh. [3 assert calls; ext: none; skip refs: 1] |
| CE/tests/integration/scenario_f_web.sh | skimmed (header+grep) | 120 | Partial | Scenario F -- Web frontend smoke. python3 scripts/web.py (background) -> POST /api/chat {"message":"hello"} [4 assert calls; ext: python3,curl; skip refs: 3] |
| CE/tests/integration/scenario_ff_episodic.sh | skimmed (header+grep) | 146 | Working | Scenario FF -- episodic memory consolidation cycle end-to-end. Long-term memory promotion: scan recent observations, detect clusters of [37 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_fff_snap_delta.sh | skimmed (header+grep) | 188 | Working | Scenario FFF -- R13F: incremental delta-snapshot writes. Verifies the new src/persistence/snapshot_delta.nova module: [8 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_ffff_tts.sh | skimmed (header+grep) | 180 | Working | Scenario FFFF -- R21C: text-to-speech pipeline (text -> G2P -> Klatt -> WAV). Drives both surfaces: [18 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_g2_kg_sync_multi.sh | skimmed (header+grep) | 357 | Partial | Scenario G2 -- multi-subscriber KG sync (P1.3 distributed-substrate seam). Builds on scenario G's two-process demo by exercising the v2 protocol's [24 assert calls; ext: none; skip refs: 2] |
| CE/tests/integration/scenario_g_kg_sync.sh | skimmed (header+grep) | 130 | Partial | Scenario G -- KG sync across two processes. Phase 20 / Tier 4 #2 distributed-substrate seam: one publisher process [13 assert calls; ext: none; skip refs: 3] |
| CE/tests/integration/scenario_gg_noise_kg.sh | skimmed (header+grep) | 404 | Partial | Scenario GG -- Noise XK encrypted KG sync end-to-end (R6, R7C 2048-bit DH). Federation gap closer. v2 of kg_sync ran in plaintext TCP; v3 wraps every [11 assert calls; ext: none; skip refs: 2] |
| CE/tests/integration/scenario_ggg_hog.sh | skimmed (header+grep) | 178 | Working | Scenario GGG -- /hog PGM admin command end-to-end (R14D, HOG dense descriptor: Dalal-Triggs 2005 oriented-gradient histogram). [8 assert calls; ext: python3; skip refs: 0] |
| CE/tests/integration/scenario_gggg_hog_integral.sh | skimmed (header+grep) | 399 | Working | Scenario GGGG -- R21D: integral histogram of gradients accelerator for the R14D HOG dense descriptor. [14 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_h2_session_paths.sh | skimmed (header+grep) | 134 | Partial | Scenario H2 -- per-session snapshot + dlog paths. P1.2 closes the per-session disk-image gap: a `/switch alice` followed by [13 assert calls; ext: none; skip refs: 1] |
| CE/tests/integration/scenario_h_session_switch.sh | skimmed (header+grep) | 97 | Working | Scenario H -- /switch in-process tenant isolation. One chat process, two sessions: the default ("default" / "Aurora") and one [16 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_hh_stereo.sh | skimmed (header+grep) | 157 | Working | Scenario HH -- /depth PGM admin command end-to-end (R7E, block-matching SAD stereo disparity from PGM-P5 stereo pairs). [10 assert calls; ext: python3; skip refs: 0] |
| CE/tests/integration/scenario_hhh_dsp.sh | skimmed (header+grep) | 186 | Working | Scenario HHH -- R14E: Schroeder reverb + noise gate (audio DSP effects). [20 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_hhhh_gossip_noise.sh | skimmed (header+grep) | 437 | Partial | Scenario HHHH -- R21E: Noise-protected gossip (mesh-level wire encryption). Spawns THREE souls (A, B, C) each with its own Noise XK static keypair [7 assert calls; ext: python3; skip refs: 2] |
| CE/tests/integration/scenario_i_web_isolation.sh | skimmed (header+grep) | 161 | Partial | Scenario I -- web.py per-cookie session isolation. Launch scripts/web.py in the background. Make two POSTs with distinct [7 assert calls; ext: python3,curl; skip refs: 3] |
| CE/tests/integration/scenario_ii_vad.sh | skimmed (header+grep) | 230 | Partial | Scenario II -- R7F: Voice Activity Detection over Klatt-synthesized audio. Exercises the new src/io/transducers/audio_vad.nova module end-to-end: [15 assert calls; ext: none; skip refs: 1] |
| CE/tests/integration/scenario_iii_ed25519.sh | skimmed (header+grep) | 187 | Working | Scenario III -- Ed25519 signing primitive (RFC 8032) end-to-end. Where this fits: CrossEngin's crypto stack already covers [11 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_iiii_panorama.sh | skimmed (header+grep) | 243 | Partial | Scenario IIII -- R22D: image-pair panorama stitching. Verifies the R22D pipeline end-to-end through the chat /pano admin: [15 assert calls; ext: none; skip refs: 1] |
| CE/tests/integration/scenario_j_http_client.sh | skimmed (header+grep) | 197 | Partial | Scenario J -- in-process plain HTTP/1.1 client loopback. Phase / P1.4: the new pure-NOVA http_client (src/io/transducers/http_client.nova) [8 assert calls; ext: python3,curl; skip refs: 6] |
| CE/tests/integration/scenario_jj_whisper.sh | skimmed (header+grep) | 325 | Partial | Scenario JJ -- R8B: whisper.cpp STT backend end-to-end. Exercises the new src/io/transducers/whisper_backend.nova module: [15 assert calls; ext: whisper; skip refs: 7] |
| CE/tests/integration/scenario_jjj_detector.sh | skimmed (header+grep) | 235 | Working | Scenario JJJ -- /detect HOG sliding-window template-matching admin command end-to-end (R15C, builds on R14D HOG dense descriptor). [7 assert calls; ext: python3; skip refs: 0] |
| CE/tests/integration/scenario_jjjj_rule_explain.sh | skimmed (header+grep) | 216 | Working | Scenario JJJJ -- recursive provenance walks + proof-tree rendering (R22E). Companion to scenario_aaaa_rule_inference.sh (R20B forward chaining) and [20 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_k_seed_pack.sh | skimmed (header+grep) | 108 | Working | Scenario K -- /seed domain seed packs (P1.9). Boot the chat once, list the available packs, install the medical pack, [11 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_kk_stereo_quality.sh | skimmed (header+grep) | 217 | Working | Scenario KK -- /depth_q PGM admin command end-to-end (R8D, the quality follow-ups on top of R7E's SAD block-matching stereo [11 assert calls; ext: python3; skip refs: 0] |
| CE/tests/integration/scenario_kkk_query.sh | skimmed (header+grep) | 123 | Working | Scenario KKK -- mini-SPARQL declarative query language (R15D). Companion to scenario_rr_semantic_search.sh (R10C /find textual [17 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_kkkk_melody.sh | skimmed (header+grep) | 195 | Working | Scenario KKKK -- R22F: melody extraction (F0 contour -> MIDI note sequence). Exercises the full /melody admin command path on a synthesized 4-note [16 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_l_stream_stdin.sh | skimmed (header+grep) | 95 | Partial | Scenario L -- P2.8 streaming source: stdin pipe drives the daemon. Launches `./bin/crossengin` in background with `CE_STREAM_STDIN=1`, sends [5 assert calls; ext: none; skip refs: 1] |
| CE/tests/integration/scenario_ll_schema_migrate.sh | skimmed (header+grep) | 162 | Working | Scenario LL -- KG atom schema-evolution end-to-end. Hand-rolls a V2-shape snapshot whose meta block LACKS the [12 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_lll_merkle.sh | skimmed (header+grep) | 153 | Working | Scenario LLL -- Merkle-tree tamper-evident atom-hash chain (R15E). Where this fits: the v2 snapshot format (R5D) -- with schema evolution [11 assert calls; ext: python3; skip refs: 0] |
| CE/tests/integration/scenario_llll_lipsync.sh | skimmed (header+grep) | 308 | Working | Scenario LLLL -- /lipsync audio-vision lip sync detection (R23B). R23B ships a structural lip-sync detector [10 assert calls; ext: python3; skip refs: 0] |
| CE/tests/integration/scenario_m_metrics_endpoint.sh | skimmed (header+grep) | 270 | Partial | Scenario M -- /metrics Prometheus scrape endpoint (P2.9). python3 scripts/web.py (background) -> POST /api/chat {"message":"hello"} [31 assert calls; ext: python3,curl; skip refs: 2] |
| CE/tests/integration/scenario_mm_episodic_recall.sh | skimmed (header+grep) | 99 | Working | Scenario MM -- episodic memory retrieval / /recall chat command (R8F). Read-side companion to scenario_ff_episodic.sh. R6F shipped the WRITE [19 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_mmm_merkle_signing.sh | skimmed (header+grep) | 202 | Working | Scenario MMM -- Ed25519 sign + verify of the Merkle snapshot root (R16A). Where this fits: R15E (lll) shipped the Merkle root tamper detector -- [12 assert calls; ext: python3; skip refs: 0] |
| CE/tests/integration/scenario_mmmm_snap_replication.sh | skimmed (header+grep) | 531 | Partial | Scenario MMMM -- R23C: federation snapshot replication via gossip. Spawns TWO souls (A, B) with their own Ed25519 long-term keypairs. [0 assert calls; ext: none; skip refs: 2] |
| CE/tests/integration/scenario_mmmm_tracker.sh | skimmed (header+grep) | 187 | Working | Scenario MMMM -- R23D: image object tracking via Kalman filter + greedy Hungarian assignment over a sequence of PGM frames. [10 assert calls; ext: python3; skip refs: 0] |
| CE/tests/integration/scenario_n_compaction.sh | skimmed (header+grep) | 187 | Working | Scenario N -- snapshot compaction (P2.10). Plan [10 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_nn_stereo_sgm.sh | skimmed (header+grep) | 241 | Working | Scenario NN -- /depth_sgm PGM admin command end-to-end (R9A, Semi-Global Matching stereo on top of R7E's SAD block-matching and [13 assert calls; ext: python3; skip refs: 0] |
| CE/tests/integration/scenario_nnn_face_detect.sh | skimmed (header+grep) | 221 | Working | Scenario NNN -- /faces Viola-Jones-style Haar cascade face detector admin command end-to-end (R16D, structural -- see IMAGE_AUDIT.md). [7 assert calls; ext: python3; skip refs: 0] |
| CE/tests/integration/scenario_nnnn_voice_conversation.sh | skimmed (header+grep) | 235 | Partial | Scenario NNNN -- R25B: end-to-end voice conversation pipeline (STT -> question parser -> SPARQL -> KG executor -> result formatter [17 assert calls; ext: whisper; skip refs: 3] |
| CE/tests/integration/scenario_o_proof_checker.sh | skimmed (header+grep) | 72 | Working | Scenario O -- /prove proof-checker on medical seed pack (P3.5 / ADR-0052). Boot the chat, install the medical pack, query a few proofs via /prove [10 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_oo_vad_natural.sh | skimmed (header+grep) | 290 | Partial | Scenario OO -- R9B: VAD threshold tuning for natural speech at 16 kHz. R7F (commit 8af9f90) shipped energy + ZCR + K=3/M=10 hysteresis VAD that [13 assert calls; ext: whisper; skip refs: 7] |
| CE/tests/integration/scenario_ooo_spectrogram.sh | skimmed (header+grep) | 213 | Partial | Scenario OOO -- R16E STFT / spectrogram chat round-trip. Exercises the full /spec admin command path on three fixtures: [15 assert calls; ext: whisper; skip refs: 3] |
| CE/tests/integration/scenario_oooo_nat_traversal.sh | skimmed (header+grep) | 801 | Partial | Scenario OOOO -- R23E: NAT traversal -- STUN-like external addr discovery + gossip-piggyback advertisement (R23E) [41 assert calls; ext: none; skip refs: 11] |
| CE/tests/integration/scenario_p_dp_budget.sh | skimmed (header+grep) | 118 | Working | Scenario P -- /dp_status + /dp_query DP budget tracking (P3.6 / ADR-0053). Boot the chat, query /dp_status (initial budget), run /dp_query atoms many [8 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_pp_byz_fl.sh | skimmed (header+grep) | 126 | Working | Scenario pp -- Byzantine-resilient federated aggregation (P3.10 / ADR-0056). [14 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_ppp_query_ext.sh | skimmed (header+grep) | 146 | Working | Scenario PPP -- mini-SPARQL extensions (R16F): OPTIONAL + UNION + ORDER BY. Sibling of scenario_kkk_query.sh (R15D BGP+FILTER+LIMIT). [21 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_pppp_ocr.sh | skimmed (header+grep) | 192 | Working | Scenario PPPP -- /ocr PGM admin command end-to-end (R24C template-matching OCR). Synthesizes PGM fixtures in /tmp using the SAME 8x8 bitmap-font glyph [9 assert calls; ext: python3; skip refs: 0] |
| CE/tests/integration/scenario_q_image_see.sh | skimmed (header+grep) | 263 | Working | Scenario Q -- /see PGM admin command end-to-end (P3.1 / ADR-0014). Build a hand-rolled binary PGM (P5) fixture in /tmp, boot the chat, [22 assert calls; ext: python3; skip refs: 0] |
| CE/tests/integration/scenario_qq_vosk.sh | skimmed (header+grep) | 353 | Partial | Scenario QQ -- R10B: whisper confidence parsing + Vosk offline backend. Exercises two follow-ups from R8B: [16 assert calls; ext: python3,whisper,vosk; skip refs: 6] |
| CE/tests/integration/scenario_qqq_mfcc.sh | skimmed (header+grep) | 215 | Partial | Scenario QQQ -- R17B MFCC (Mel-Frequency Cepstral Coefficients) chat round-trip and vowel discriminability. [17 assert calls; ext: whisper; skip refs: 2] |
| CE/tests/integration/scenario_qqqq_pitch_auto.sh | skimmed (header+grep) | 329 | Partial | Scenario QQQQ -- R22F.2: Auto-switching pitch detector (R10F autocorrelation <-> R11B YIN) driven by per-frame harmonicity score. [2 assert calls; ext: whisper; skip refs: 1] |
| CE/tests/integration/scenario_r_federated.sh | skimmed (header+grep) | 170 | Partial | Scenario R -- federated learning round-trip (P3.7 / ADR-0054). One soul (chat) joins a single-soul federation coordinator. The [15 assert calls; ext: none; skip refs: 3] |
| CE/tests/integration/scenario_rr_semantic_search.sh | skimmed (header+grep) | 150 | Working | Scenario RR -- TF-IDF semantic search retrieval / /find chat command (R10C). Companion to scenario_mm_episodic_recall.sh. R8F shipped /recall (episodi [19 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_rrr_lbp.sh | skimmed (header+grep) | 239 | Working | Scenario RRR -- /lbp LBP (Local Binary Patterns, Ojala 1996) texture descriptor admin command end-to-end (R17D, classifier-input feature [7 assert calls; ext: python3; skip refs: 0] |
| CE/tests/integration/scenario_rrrr_video_smooth.sh | skimmed (header+grep) | 120 | Working | Scenario RRRR -- R24F: video temporal smoothing -- Kalman over R23D tracker outputs. [11 assert calls; ext: python3; skip refs: 0] |
| CE/tests/integration/scenario_s_video_play.sh | skimmed (header+grep) | 203 | Working | Scenario S -- /play Y4M admin command end-to-end (P3.2 / ADR-0014). Build a hand-rolled raw Y4M (YUV4MPEG2) fixture in /tmp with 5 frames [15 assert calls; ext: python3; skip refs: 0] |
| CE/tests/integration/scenario_ss_optical_flow.sh | skimmed (header+grep) | 168 | Working | Scenario SS -- /flow PGM admin command end-to-end (R10D, Lucas-Kanade dense optical flow on PGM-P5 frame pairs). [11 assert calls; ext: python3; skip refs: 0] |
| CE/tests/integration/scenario_sss_query_agg.sh | skimmed (header+grep) | 146 | Working | Scenario SSS -- mini-SPARQL aggregates (R17E): COUNT, SUM, AVG, MIN, MAX, GROUP BY. Sibling of scenario_kkk_query.sh (R15D BGP+FILTER+LIMIT) [22 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_t_png_see.sh | skimmed (header+grep) | 149 | Partial | Scenario T -- /see PNG admin command end-to-end (P3.1.PNG full DEFLATE). Generate three PNG fixtures via scripts/gen_test_png.py exercising ALL [10 assert calls; ext: python3; skip refs: 1] |
| CE/tests/integration/scenario_tt_pitch.sh | skimmed (header+grep) | 259 | Partial | Scenario TT -- R10F: autocorrelation-based F0 (pitch) estimation. Exercises the new src/io/transducers/audio_pitch.nova module end-to-end: [15 assert calls; ext: whisper; skip refs: 3] |
| CE/tests/integration/scenario_ttt_link_prediction.sh | skimmed (header+grep) | 169 | Working | Scenario TTT -- link prediction over the KG xref graph (R18B). Companion to scenario_xx_communities.sh (R11F LPA), [29 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_tttt_rss_ingest.sh | skimmed (header+grep) | 109 | Working | Scenario TTTT -- RSS / Atom feed ingestion into the KG (R25C). Companion to the unit suite in tests/unit/test_kg_rss_ingest.nova [11 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_u_secagg.sh | skimmed (header+grep) | 660 | Partial | Scenario U -- secure aggregation (SecAgg) round-trip (P3.8 / ADR-0055). Two chat souls join a SecAgg-mode federated coordinator. Each soul [48 assert calls; ext: python3; skip refs: 8] |
| CE/tests/integration/scenario_uu_pyramid_flow.sh | skimmed (header+grep) | 196 | Working | Scenario UU -- /flow_pyr PGM admin command end-to-end (R11A, pyramidal Lucas-Kanade optical flow on PGM-P5 frame pairs). [11 assert calls; ext: python3; skip refs: 0] |
| CE/tests/integration/scenario_uuu_wakeword.sh | skimmed (header+grep) | 209 | Working | Scenario UUU -- R18C wake-word detection chat round-trip via DTW on MFCC sequences. [20 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_uuuu_noise_reduce.sh | skimmed (header+grep) | 350 | Partial | Scenario UUUU -- R26C spectral-subtraction Wiener noise reduction. Exercises the new src/io/transducers/audio_noise_reduce.nova module [12 assert calls; ext: whisper; skip refs: 2] |
| CE/tests/integration/scenario_v_secure_channel.sh | skimmed (header+grep) | 212 | Partial | Scenario V -- PSK secure-channel (ChaCha20-Poly1305) loopback. Phase / P1.4 continuation: src/io/transducers/secure_channel.nova [5 assert calls; ext: python3; skip refs: 5] |
| CE/tests/integration/scenario_vv_yin_pitch.sh | skimmed (header+grep) | 239 | Partial | Scenario VV -- R11B: YIN-class F0 estimator (cumulative mean normalized difference function) -- end-to-end head-to-head against R10F autocorrelation. [4 assert calls; ext: whisper; skip refs: 2] |
| CE/tests/integration/scenario_vvv_face_recognize.sh | skimmed (header+grep) | 217 | Working | Scenario VVV -- /face_enroll + /face_recognize LBP-gallery nearest- neighbor face identity matching admin commands end-to-end (R18D, [14 assert calls; ext: python3; skip refs: 0] |
| CE/tests/integration/scenario_vvvv_gossip_relay.sh | skimmed (header+grep) | 392 | Partial | Scenario VVVV -- R26E: gossip relay -- 3-soul A -> C -> B forwarding when direct A <-> B dial is blocked. [3 assert calls; ext: none; skip refs: 2] |
| CE/tests/integration/scenario_w_audio_capture.sh | skimmed (header+grep) | 305 | Partial | Scenario W -- P2.5 cont. real microphone capture end-to-end. Exercises the audio-input half of the modality bridge that landed in [22 assert calls; ext: python3,arecord,sox; skip refs: 6] |
| CE/tests/integration/scenario_ww_segmentation.sh | skimmed (header+grep) | 208 | Partial | Scenario WW -- R11E: spatial k-means image segmentation. Exercises the new src/io/transducers/image_segmentation.nova module [15 assert calls; ext: none; skip refs: 1] |
| CE/tests/integration/scenario_www_gossip.sh | skimmed (header+grep) | 358 | Partial | Scenario WWW -- R18E: SWIM-style gossip protocol -- 3-soul peer discovery + KG delta propagation + DEAD-marking on a killed peer. [6 assert calls; ext: none; skip refs: 1] |
| CE/tests/integration/scenario_wwww_relay_rank.sh | skimmed (header+grep) | 343 | Working | Scenario WWWW -- R26E.2: STUN-like relay candidate ranking. R26E shipped TCP gossip relay with a "first-alive non-target peer" [6 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_x_doctor.sh | skimmed (header+grep) | 86 | Working | Scenario X -- crossengin-doctor parses cleanly + reports a sane checklist. Runs scripts/crossengin-doctor.sh, captures stdout+stderr, parses the [5 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_xx_communities.sh | skimmed (header+grep) | 147 | Working | Scenario XX -- KG graph clustering / community detection (R11F). Companion to scenario_rr_semantic_search.sh. R10C shipped /find -- a [16 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_xxx_temporal.sh | skimmed (header+grep) | 127 | Working | Scenario XXX -- temporal reasoning via Allen's interval algebra (R19C). Companion to scenario_xx_communities.sh (R11F LPA), [21 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_xxxx_relay_secure.sh | skimmed (header+grep) | 526 | Partial | Scenario XXXX -- R26E.2: Noise-XK end-to-end wrap around the R26E gossip relay (gossip_relay_secure.nova). [0 assert calls; ext: none; skip refs: 2] |
| CE/tests/integration/scenario_y_json_logs.sh | skimmed (header+grep) | 116 | Partial | Scenario Y -- CE_LOG_JSON=1 emits valid one-line JSON per turn. Launch bin/crossengin-chat with CE_LOG_JSON=1 in the env, feed "fever", [6 assert calls; ext: python3; skip refs: 2] |
| CE/tests/integration/scenario_yy_slic.sh | skimmed (header+grep) | 208 | Partial | Scenario YY -- R12B: SLIC superpixel segmentation. Exercises the new src/io/transducers/image_superpixels.nova module [15 assert calls; ext: none; skip refs: 1] |
| CE/tests/integration/scenario_yyy_speaker_id.sh | skimmed (header+grep) | 209 | Working | Scenario YYY -- R19D speaker identification via MFCC + DTW gallery chat round-trip. The voice analog of R18D's LBP-gallery face [22 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_yyyy_rule_convergence.sh | skimmed (header+grep) | 1004 | Partial | Scenario YYYY -- R27E: federated rule-engine convergence stress test. R21B (commit d752b9b) shipped distributed rule inference over the [0 assert calls; ext: none; skip refs: 1] |
| CE/tests/integration/scenario_z_snap_diff.sh | skimmed (header+grep) | 93 | Working | Scenario Z -- snap_diff.sh reports atom-set deltas between two snapshots. Boot chat -> /save snap1 -> /teach widget -> /save snap2 -> run [18 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_zz_louvain.sh | skimmed (header+grep) | 154 | Working | Scenario ZZ -- Louvain modularity-optimising community detection (R12C). Companion to scenario_xx_communities.sh. R11F shipped label [13 assert calls; ext: none; skip refs: 0] |
| CE/tests/integration/scenario_zzz_leader.sh | skimmed (header+grep) | 478 | Partial | Scenario ZZZ -- R19E: federation leader election (Bully algorithm) on top of R18E SWIM gossip. 3-soul mesh elects the highest-ID soul as leader; [6 assert calls; ext: none; skip refs: 1] |
| CE/tests/integration/scenario_zzzz_relay_binary.sh | skimmed (header+grep) | 503 | Partial | Scenario ZZZZ -- R27C.2: Bulk binary path for Noise-XK-wrapped relay payloads (gossip_relay_secure.nova). [0 assert calls; ext: none; skip refs: 1] |
| CE/tests/integration/_scenario_aaaa_rule_inference_driver/rule_inference_driver.nova | skimmed (header) | 106 | Working | Driver for scenario_aaaa_rule_inference.sh. |
| CE/tests/integration/_scenario_eee_pagerank_driver/pagerank_driver.nova | skimmed (header) | 164 | Working | Scenario eee -- in-process driver for PageRank centrality (R13E). |
| CE/tests/integration/_scenario_fff_drivers/delta_bench_driver.nova | skimmed (header) | 262 | Working | Scenario FFF -- in-process driver for snapshot delta-write benchmarking. |
| CE/tests/integration/_scenario_j_drivers/http_loopback_driver.nova | skimmed (header) | 23 | Working | Auto-generated loopback driver for scenario_j_http_client.sh. |
| CE/tests/integration/_scenario_j_drivers/prechk_socket.nova | skimmed (header) | 7 | Working | NOVA driver for the same-named scenario script |
| CE/tests/integration/_scenario_jjjj_rule_explain_driver/rule_explain_driver.nova | skimmed (header) | 88 | Working | Driver for scenario_jjjj_rule_explain.sh. |
| CE/tests/integration/_scenario_pp_drivers/byz_aggregation_driver.nova | skimmed (header) | 80 | Working | Scenario pp -- in-process driver for Byzantine-resilient federated aggregation. |
| CE/tests/integration/_scenario_ttt_link_prediction_driver/link_prediction_driver.nova | skimmed (header) | 213 | Working | Scenario ttt -- in-process driver for link prediction (R18B). |
| CE/tests/integration/_scenario_vvvv_drivers/a.nova | skimmed (header) | 108 | Working | NOVA driver for the same-named scenario script |
| CE/tests/integration/_scenario_vvvv_drivers/b.nova | skimmed (header) | 108 | Working | NOVA driver for the same-named scenario script |
| CE/tests/integration/_scenario_vvvv_drivers/c.nova | skimmed (header) | 108 | Working | NOVA driver for the same-named scenario script |
| CE/tests/integration/_scenario_vvvv_drivers/prechk.nova | skimmed (header) | 7 | Working | NOVA driver for the same-named scenario script |
| CE/tests/integration/_scenario_xxx_temporal_driver/temporal_driver.nova | skimmed (header) | 114 | Working | Scenario xxx -- in-process driver for temporal reasoning (R19C). |
| CE/tests/integration/_scenario_yyyy_rule_convergence_driver/rule_convergence_driver.nova | skimmed (header) | 438 | Working | Driver for scenario_yyyy_rule_convergence.sh -- R27E federated |
| CE/tests/integration/_scenario_zz_louvain_driver/louvain_driver.nova | skimmed (header) | 156 | Working | Scenario zz -- in-process driver for Louvain community detection. |
