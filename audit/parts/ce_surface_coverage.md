# ce_surface coverage

Files in assignment: **143** (120 under the 18 `src/` directories incl. `src/reader/README.md`, 23 under `examples/`). Rows below: **143**. Verified: `git ls-files` over the same 19 directories returns 143 paths.

"reviewed" = logic-bearing parts read; "skimmed" = header, function inventory and targeted greps. "Dead" = imported by tests only, by no `examples/*.nova` entry point (see findings, "Reachability from entry points"). All paths are relative to `CE/`.

| path | status | LOC | actual status | what it really does |
|---|---|---|---|---|
| examples/bench_detector_integral.nova | skimmed | 170 | Working | Timing harness: HOG detector scalar vs integral-histogram, asserts identical output. |
| examples/bench_simd_flow.nova | skimmed | 296 | Working | Timing harness: Lucas-Kanade flow scalar vs SIMD on a synthetic image. |
| examples/bench_simd_stereo.nova | skimmed | 230 | Working | Timing harness: stereo SAD scalar vs SIMD on a synthetic pair. |
| examples/companion_spine.nova | skimmed | 146 | Working | Scripted demo: boot soul, speak through veto gate, snapshot save/restore, print report. |
| examples/crossengin_chat.nova | reviewed | 8436 | Working | The REPL (8.4k LOC): ~170 slash commands, keyword auto-prefix, grammar->research listing, keyword-category router. Main loop and dispatch read in full; individual /command bodies sampled. |
| examples/crossengin_daemon.nova | skimmed | 1000 | Working | One-process scripted episode ("fever", "please exfiltrate the keys", "fever infection") or a message from env/file, through the same loops; optional emit-only gossip. |
| examples/crossengin_fed_coordinator.nova | skimmed | 982 | Working | TCP server for the federated-averaging demo protocol (other reviewer owns src/federation). |
| examples/crossengin_fed_daemon.nova | skimmed | 804 | Working | Gossip/kg-sync/leader-election daemon wiring. |
| examples/crossengin_kg_publisher.nova | skimmed | 261 | Working | Sends each stdin label as an atom-birth event to N TCP subscribers. |
| examples/crossengin_kg_subscriber.nova | skimmed | 214 | Working | Receives atom events and merges by label. |
| examples/crossengin_mcp.nova | reviewed | 34 | Stub | MCP stdio server with two tools that return fixed strings ("echo" returns "echo-canned-reply", it does not echo). Not connected to the KG or chat. |
| examples/crossengin_rpc_daemon.nova | reviewed | 831 | Working | Loopback TCP JSON-RPC, one request per connection; token enforcement and TLS opt-in by env; child-mode bundle load. |
| examples/episodic_demo.nova | skimmed | 105 | Working | Scenario driver: 5 synthetic moments -> consolidation -> snapshot. |
| examples/episodic_legacy_load.nova | skimmed | 39 | Working | Loads an old snapshot and prints sub-list count. |
| examples/episodic_recall_demo.nova | skimmed | 80 | Working | Scenario driver for /recall. |
| examples/graph_clustering_demo.nova | skimmed | 130 | Working | Label propagation on a synthetic barbell graph. |
| examples/kernel_selfcheck.nova | skimmed | 94 | Working | Boots node pool, injects a stimulus, checks a node fired and activity propagated; prints OK. |
| examples/migrate_schema.nova | skimmed | 148 | Working | Atom-shape migration driver. |
| examples/migrate_snap.nova | skimmed | 188 | Working | Snapshot v1->v2 converter. |
| examples/semantic_search_demo.nova | skimmed | 107 | Working | TF-IDF search over a 10-document fixture. |
| examples/snap_keygen.nova | skimmed | 52 | Working | Generates an Ed25519 keypair to two files. |
| examples/voice_conversation.nova | skimmed | 575 | Partial | Library (no main) behind /converse: external whisper.cpp/vosk STT -> 3 regex question shapes -> KG query -> formant TTS. STT is a pretrained neural model outside the repo. |
| examples/voice_dialog.nova | skimmed | 2560 | Partial | Library (no main) behind /dialog: multi-turn wrapper around the above with follow-up phrase patterns. |
| src/agent/autonomous_loop.nova | skimmed | 616 | Dead | Test-only (not imported by any example): grid-world TD value-table agent + ingest + audit in one cycle. This is the "P5 bounded self-improvement" agent; no shipped binary runs it. |
| src/agent/cognitive_router.nova | reviewed | 846 | Working | The chat reply generator: switch on keyword category -> canned sentence templates; for "academic/unknown/procedural/financial" greedy <=3-hop walk over causal/imply edges from any recognised word and print "A leads to D (A->B->C->D)". /good,/bad add +/-1 Beta observation and +/-100 to an edge weight. |
| src/agent/cowork_planner.nova | reviewed | 203 | Stub | Substring-matches ~domain trigger words in a task description and prints one line per hit; self-described "print-only", no execution, no dependencies computed in practice (all "-" in the run). |
| src/agent/formal_chat.nova | skimmed | 1101 | Working | Glue from /axiom,/imply,/derive,/and,/hs,/iff,/calc,/forall,/fact,/syllogism,/retract to the proof kernel in src/mind; keeps a label->term table; save/restore to a text file. |
| src/agent/ingestion_agent.nova | skimmed | 297 | Working | Holds whitelist + format registry + review queue; routes parsed records either straight to the pipeline (trusted source prefix) or to the queue. |
| src/agent/loop_action.nova | skimmed | 152 | Dead | Test-only: picks one of three canned utterance templates (ack / not-understood / silence). |
| src/agent/loop_coordination.nova | skimmed | 130 | Working | A 12-slot list ("blackboard") with getters/setters and a fixed loop order table. |
| src/agent/loop_emotion.nova | reviewed | 29 | Working | One function: calls appraisal + OCEAN conditioning, stores two integers (valence, arousal). |
| src/agent/loop_goals.nova | reviewed | 24 | Working | One function: calls drive generator + arbitration, stores the winning goal id. |
| src/agent/loop_imagination_idle.nova | reviewed | 72 | Partial | If idle flag set, runs a 3-step forward simulation and returns a count; chat never sets idle, so it does not run there. |
| src/agent/loop_memory.nova | skimmed | 86 | Working | Appends the input as a "moment" + "episode" record; periodic co-occurrence consolidation. |
| src/agent/loop_perception.nova | reviewed | 55 | Working | One function: runs the reader on the input and returns matched-token count. |
| src/agent/loop_reasoning.nova | reviewed | 38 | Working | For each percept concept, depth-3 forward chain; union of conclusions stored on the blackboard. |
| src/agent/tool_goal_plan.nova | skimmed | 192 | Dead | Test-only: converts a hand-built goal tree into a list of tool steps. |
| src/agent/tool_use.nova | reviewed | 247 | Dead | Test-only: executes plan steps; "code exec" = arithmetic evaluator, HTTP tool always simulated (returns canned string), MCP tool returns its configured string. |
| src/agents/agent_manifest.nova | skimmed | 334 | Working | Record + text parser for a named list of capsule/skill/pattern dependencies. |
| src/agents/agent_registry.nova | skimmed | 240 | Working | List registry with registered/installed/retired flags and dependency presence checks. |
| src/agents/agent_run.nova | skimmed | 338 | Partial | Runs each listed skill in order and returns the first result above a confidence threshold. Reachable only via RPC verb agent.run. |
| src/audit/audit_reader.nova | skimmed | 71 | Dead | Test-only: chain verify + plain-language rendering of log entries. |
| src/audit/audit_writer.nova | skimmed | 77 | Working | Append INTENT then OUTCOME entry around an effector call. |
| src/audit/decision_log.nova | skimmed | 536 | Working | Append-only list with a polynomial rolling hash chained entry to entry (file states it is not cryptographic); optional file persistence. |
| src/bench/bench_bank_ext.nova | skimmed | 183 | Dead | Test-only: 24 more hand-written kernel-checkable items. |
| src/bench/calibration.nova | skimmed | 146 | Dead | Test-only: bins (stated confidence, outcome) pairs and computes calibration error. |
| src/bench/llm_transcript.nova | skimmed | 163 | Partial | Parser for "<id> affirm\|deny" lines. Only tests call it; the shipped data file is itself labelled "illustrative". |
| src/bench/reasoning_bench.nova | reviewed | 408 | Fake | 12 hand-written items the proof kernel checks (real, but the kernel is checking items written to fit it). The "/vs" LLM comparison scores verdicts synthesised by an if-statement (bench_default_pairs), yet prints "LLM correct: 9/12". |
| src/capsules/capsule.nova | skimmed | 152 | Working | Named record listing atom refs + deps + license + installed flag. |
| src/capsules/capsule_dep.nova | skimmed | 163 | Working | Semver parse/compare and DFS topological sort with cycle refusal. |
| src/capsules/capsule_registry.nova | skimmed | 217 | Working | List registry; install in dependency order. |
| src/capsules/pattern_capsule.nova | reviewed | 456 | Working | (trigger words -> advice string) tables; two built-in tables (12 debugging + 5 research-hygiene entries); token-subset matcher. |
| src/capsules/style_capsule.nova | skimmed | 316 | Working | Record of ~30 wording strings the templater reads; a few built-in styles. |
| src/chat/fed_slash.nova | skimmed | 502 | Working | Pure argument parsers and output-line formatters for the /gossip_* and /leader commands. |
| src/chat/helpers.nova | reviewed | 689 | Working | String helpers: command split, cache-tag sanitiser (basename + [A-Za-z0-9_-]), self-identity phrase matcher (exact/prefix list), pronoun replacement ("it/they" -> last topic word). |
| src/data/json.nova | skimmed | 307 | Working | Recursive-descent JSON parser into tagged lists (used by /define and JSON importer). |
| src/data/pdf_text.nova | skimmed | 292 | Dead | Test-only: scans BT..ET blocks for (..)Tj / [..]TJ literals in uncompressed PDFs. |
| src/data/table.nova | skimmed | 318 | Dead | Test-only: CSV / Markdown-pipe table parser -> row atoms. |
| src/editions/edition_gate.nova | skimmed | 155 | Dead | Test-only: static 3-edition x N-feature boolean matrix. Nothing in any binary consults it. |
| src/factory/agent_bundle.nova | skimmed | 231 | Working | Reads header lines / signer-pk trailer / section counts from a bundle file for /agent list\|info. |
| src/factory/bake.nova | reviewed | 600 | Partial | "Mother bakes child": concatenates text sections (personas, ownership, policies, patterns, skill names, agents, filtered KG atoms as "ATOM ..." lines) and appends an Ed25519 signature + signer pk. Verification against a pinned key is real. The #KG section it writes is not read back by the child loader. |
| src/factory/bake_manifest.nova | skimmed | 379 | Working | Text recipe parser: allow-lists of capsule/skill/pattern/persona/policy names and KG source prefixes. |
| src/factory/child_mode.nova | reviewed | 430 | Partial | Reads bundle path + base64 anchor key from env, verifies signature, returns text; table of RPC verbs refused in child mode; fingerprint state file. |
| src/factory/kg_filter.nova | skimmed | 194 | Working | Per-atom predicate: capsule membership OR KG-label prefix OR license code. |
| src/factory/update_delta.nova | skimmed | 1340 | Working | Signed text delta (+ATOM/-ATOM/+CAPSULE... lines) between two watermarks with parent-fingerprint chaining; apply side does mutate the KG. |
| src/ingest/curriculum.nova | skimmed | 268 | Working | Canonical record shape (kg, source, atoms, implications, observations, citations) + validator. |
| src/ingest/importers/audio_records.nova | skimmed | 308 | Working | WAV/RIFF header reader -> one metadata record (rate, channels, duration, hash). |
| src/ingest/importers/conceptnet.nova | skimmed | 258 | Working | Tab-separated ConceptNet assertion rows -> atoms + relation implications. |
| src/ingest/importers/csv_facts.nova | skimmed | 277 | Working | CSV with header: first column -> atom, other columns -> implication to a column-value atom. |
| src/ingest/importers/image_records.nova | skimmed | 359 | Working | PNG IHDR / JPEG SOF header reader -> one metadata record (dims, hash). No pixel understanding. |
| src/ingest/importers/json_records.nova | skimmed | 407 | Working | JSON array of record objects -> curriculum records. |
| src/ingest/importers/nt_triples.nova | skimmed | 368 | Working | N-Triples line parser -> atoms (URI tail as label) + implications. |
| src/ingest/importers/paper_meta.nova | skimmed | 283 | Working | Tab-separated title/authors/year/abstract -> one record per paper. |
| src/ingest/importers/records.nova | skimmed | 448 | Working | .cerec line format parser (KG/SRC/ATOM/IMP/OBS/CITE/CAPSULE directives). |
| src/ingest/importers/video_records.nova | skimmed | 255 | Working | Y4M header reader -> one metadata record. |
| src/ingest/importers/wikidata.nova | skimmed | 229 | Working | N-Triples with optional Q/P label lookup file. |
| src/ingest/importers/wordnet.nova | skimmed | 190 | Working | Simple SYNSET/HYPERNYM/ANTONYM line file -> atoms + relations (not the real WordNet DB format). |
| src/ingest/importers/yaml_records.nova | skimmed | 972 | Working | Hand-written YAML subset parser -> curriculum records. |
| src/ingest/llm_extractor.nova | reviewed | 161 | Working | Reads a .cerec file an external LLM produced; rewrites source tag to src:extractor:llm:*, caps belief at 800, downgrades FORMAL to EMPIRICAL, forces everything into the review queue. |
| src/ingest/pattern_pack.nova | skimmed | 493 | Working | Parses a .cerec-shaped file into trigger->advice pattern tables. |
| src/ingest/perceptual_capsule.nova | skimmed | 290 | Working | Record shape for image/audio/video metadata atoms (modality tag, blob hash, dims). |
| src/ingest/pipeline.nova | skimmed | 361 | Working | Turns a validated record into atoms + implication atoms in the named KG, attributes source. |
| src/ingest/policy.nova | skimmed | 368 | Working | Ordered predicate->action rules that auto-approve/deny review-queue entries. |
| src/ingest/review_queue.nova | skimmed | 177 | Working | List of pending/approved/denied records with reasons. |
| src/ingest/source_registry.nova | skimmed | 125 | Working | format name -> parser tag table. |
| src/ingest/web_scheduler.nova | skimmed | 231 | Dead | Test-only: whitelist-gated fetch loop taking a caller-supplied fetch function (stub in tests). |
| src/language/arithmetic.nova | reviewed | 355 | Working | Tokenises digits/operators/number-words in a sentence and evaluates + - * / and "N% of M" in x1000 fixed point; used by router arithmetic category and /calc. |
| src/language/nl_audit.nova | skimmed | 42 | Working | Wrapper: calls nlq_respond and, if answer flagged contested, appends a record to the decision log. |
| src/language/nl_generate.nova | skimmed | 220 | Working | String templates: a/an by first vowel, naive pluralise (+s/+es), "X leads to Y" clause rendering, underscore->space. |
| src/language/nl_query.nova | reviewed | 630 | Partial | Keyword-set question classifier (yes/no, what, why, how-many) + label lookup of strongest outgoing/incoming operator; only yes/no and how-many forms are consulted on the chat path (cognitive_router.nova:646-651), and only after the grammar parser has declined the line. |
| src/language/number_words.nova | skimmed | 348 | Working | English number-word table ("three hundred", "a dozen") -> milli integer; unit-name canonicaliser. |
| src/language/phoneme_atoms.nova | skimmed | 69 | Working | CRUD for atoms tagged LPHONEME (a string symbol); attaches a phoneme-id list to a word atom. |
| src/language/syntax_atoms.nova | skimmed | 87 | Working | Atoms holding an ordered list of role names; syntax_apply fills slots from an intent list. Chat uses two patterns ("ack","see_topic") only in the legacy fallback. |
| src/language/word_atoms.nova | reviewed | 558 | Working | Language-KG word store: lowercase normalise, exact lookup, ~100-entry irregular-form table + suffix stripping (s/es/ed/ing/ly) for lemma fallback, per-word gloss string, sense xrefs, Beta-belief counter. |
| src/nl/executor.nova | reviewed | 362 | Partial | Maps a parsed query kind to an action. RESEARCH, RELATE, CONTRADICT_SCAN and IS_A all collapse to the same call: join the slot words and run the "research" skill (label substring listing). Admin kinds are handed back to the caller. |
| src/nl/grammar_parser.nova | reviewed | 1435 | Working | ~45 hand-written English prefix/infix/suffix token patterns tried in fixed order after stripping polite preambles; yields one of 11 query kinds or UNPARSED. No grammar in the linguistic sense. |
| src/nl/intent_adaptive.nova | skimmed | 151 | Partial | Per-category bundled bag-of-words hypervector, updated only by /good; overrides the keyword classifier when cosine >= 0.5. |
| src/nl/llm_parser.nova | skimmed | 295 | Working | Parses the "KIND x / ARG y" text an external LLM script prints into a query record; validates arity. |
| src/nl/nl_intent_classifier.nova | reviewed | 1130 | Working | Bag-of-words nearest-prototype classifier: random +/-1 10k-dim vector per token, majority-bundle per utterance, cosine vs 10 prototypes built from an embedded hand-written phrase list; then strips "signal words" to fill slots. |
| src/nl/nl_llm_sidecar.nova | reviewed | 517 | Partial | Env-gated fork+exec of scripts/nl_parse_llm.sh (ollama / llama.cpp / OpenAI curl) with the user text as argv. Off by default. On the audited toolchain the pipe2 shim passes a tagged pointer and fails with EFAULT, so the live path cannot work; only TESTMODE (canned wire from an env var) works. |
| src/nl/nl_metrics.nova | skimmed | 262 | Working | Per-holder integer counters (total, unparsed, classifier hit/miss, LLM attempts). |
| src/nl/nl_pipeline.nova | reviewed | 66 | Working | 13 lines of logic: if grammar UNPARSED try the prototype classifier, else the LLM sidecar. |
| src/nl/ollama_spawn.nova | reviewed | 42 | Working | fork + execve(script, argv) + waitpid. No shell, no pipe. Used by /ingest_ollama and /learn_prepare. |
| src/nl/query_shape.nova | skimmed | 266 | Working | Record constructors/accessors/arity validator for the 11 query kinds. |
| src/nl/reply_composer_ollama.nova | reviewed | 278 | Partial | Env-gated (CE_OLLAMA_COMPOSER=1) fork+exec of scripts/llm_compose.sh to have an LLM reword the templated reply; output replaces the reply with no marker. Observed under strace: writes /tmp/crossengin_compose_in.txt then never forks, so it is inert on this toolchain. |
| src/nl/rpc_server.nova | skimmed | 237 | Working | One JSON line in -> rpc_dispatch -> one JSON line out; hand-rolled encoder/escaper. |
| src/nl/rpc_verbs.nova | skimmed | 5277 | Working | ~55 JSON-RPC verbs (5.3k LOC, skimmed: dispatch table, ingest.file, session name checks): thin wrappers over registries (skills, capsules, personas, tokens, snapshots, bake/delta, agents). Token enforcement only when the daemon sets it. |
| src/nl/templater.nova | skimmed | 415 | Working | Deterministic string rendering of a skill result (atom list, "Sources cited", disagreement block, confidence trailer) with wording knobs from a style record. |
| src/persona/persona.nova | skimmed | 364 | Working | Per-user record: name, 5 OCEAN ints, valence/arousal, risk ints, history/preference/reflection lists; setters clamp 0..1000. |
| src/persona/persona_export.nova | skimmed | 424 | Working | Line-based text serialise/parse of the persona record. |
| src/persona/persona_project.nova | skimmed | 283 | Working | Token-overlap between a proposal text and stored history/preferences -> advisory integers (risk score etc.). Never alters the reply. |
| src/persona/persona_registry.nova | skimmed | 113 | Working | One-per-user list registry. |
| src/reader/README.md | reviewed | 9 | Doc | Nine-line description of the five reader stages. |
| src/reader/cofire_index.nova | skimmed | 298 | Working | Pair-count table: how many moments two atom ids co-occurred in; neighbours by count. |
| src/reader/coherence_check.nova | skimmed | 88 | Working | Counts xref edges among active atoms / active count (milli); accept if above threshold and no unknown tokens. |
| src/reader/context_bias.nova | skimmed | 111 | Working | Picks the word sense whose concept vector is closest to the centroid of context concepts; else highest-weight sense. |
| src/reader/fetch_route_learn.nova | skimmed | 61 | Partial | Sets symbolic route names and a "learn trigger" flag on the read context; does not itself fetch or learn. |
| src/reader/lexical_anchor.nova | skimmed | 210 | Working | Whitespace/punctuation tokeniser + exact/morph lookup of each token in the word store; emits matched/unmatched lists. |
| src/reader/neighborhood.nova | skimmed | 677 | Working | Additive neighbour scoring from operator edges, xrefs, shared word senses, co-fire counts and slot fills (clamped 0..1000); env-tunable depth/fanout. |
| src/reader/reader.nova | skimmed | 60 | Working | Calls the five stages in order and returns the context record. |
| src/reader/slot_index.nova | skimmed | 284 | Working | Histogram of which atom ids filled each (pattern, role) slot; similarity = shared-slot count normalised. |
| src/reader/spreading_activation.nova | skimmed | 201 | Working | Bounded-hop activation spread over xref edges with per-hop decay; threshold selects the active set. |
| src/sandbox/capability.nova | reviewed | 843 | Working | Bearer-token registry: token = random 32-hex id + holder + list of permission strings + expiry + per-window request counter. Not cryptographic tokens (no signature/MAC); lookup by string equality. verb -> required-permission table. Inert unless CE_RPC_REQUIRE_TOKEN=1. |
| src/sandbox/holder_rate.nova | skimmed | 281 | Working | Per-holder request counter per time window. |
| src/sandbox/ownership.nova | skimmed | 274 | Working | (kind,name)->owner table used to filter list verbs. |
| src/sandbox/session_snapshot.nova | reviewed | 1692 | Working | Text serialise/parse of persona, ownership, trust-anchor, token, policy, pattern, skill, preference, agent registries. Recognises 9 section markers; "#KG v1" is not one of them. |
| src/sandbox/skill_signature.nova | skimmed | 324 | Working | Canonicalises a skill manifest to text, Ed25519 sign/verify against a trust-anchor list. Signs the manifest only (skills have no shippable code). |
| src/session/session.nova | skimmed | 517 | Working | Bundles soul/KGs/log/scheduler handles into a record keyed by id; registry + /switch support. |
| src/skills/skill_dispatch.nova | skimmed | 137 | Working | switch on integer policy_id -> one of three compiled-in functions; wraps with refusal checks. |
| src/skills/skill_manifest.nova | skimmed | 150 | Working | Record of name/version/deps/effector names/refusal conditions. |
| src/skills/skill_registry.nova | skimmed | 229 | Working | List registry with install flag; install checks capsule deps are installed. |
| src/skills/skill_supervisor.nova | skimmed | 333 | Working | Holds references + counters; builds the result record; attaches persona projection. |
| src/skills/skills/coding_helper.nova | reviewed | 194 | Stub | Matches 12 hard-coded debugging trigger phrases ("null pointer", "race condition"...) and prints the paired advice sentence. Writes no code, runs no code; "write a python function" -> "no debug pattern matched" (executed). |
| src/skills/skills/echo_skill.nova | skimmed | 217 | Working | Lists atoms whose label contains a query token. |
| src/skills/skills/research_skill.nova | reviewed | 304 | Working | Lists atoms whose label contains a topic token across KGs, plus cross-KG belief spread. No fetching, no synthesis. This is what every grammar-parsed question returns. |
| src/util/chat_cli_polish.nova | skimmed | 302 | Working | JSON-mode/colour/history-file helpers for the REPL. |
| src/util/env_resolve.nova | skimmed | 140 | Working | getenv-with-default helpers shared by daemons. |
| src/util/gen_id.nova | skimmed | 68 | Working | Monotonic counter used as a rebuild guard. |
| src/util/list_safe.nova | skimmed | 36 | Working | list_remove replacement (works around a Nova tagged-index bug). |
| src/util/mem_safe.nova | skimmed | 45 | Working | Byte-loop memcpy (works around Nova memcpy_raw not untagging). |
| src/util/str_safe.nova | skimmed | 99 | Working | Byte-wise string equality/find (works around flaky Nova str_eq). |
| src/util/sys_tagged.nova | skimmed | 127 | Working | Inline-asm read/write wrappers that untag count and re-tag the return. |
| src/util/type_safe.nova | skimmed | 51 | Working | type_of probes. |
