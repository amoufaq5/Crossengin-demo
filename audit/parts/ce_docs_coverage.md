# ce_docs coverage

Row count: **245** = 233 md files under `docs/` (`git ls-files docs | grep .md$` = 233: 193 ADRs + 40 others) + 12 assigned root-level md files. Three non-md files under docs/ (`caps.sample.conf`, `samples/sample_agent.bundle`, `samples/sample_agent.pub`) are noted at the bottom. Paths are relative to `CE/`. Total assigned doc lines: 82650.

"Actual status" is `Doc` for all (no executable content). ADR rows give title + the status string the ADR itself declares. "skimmed" for ADRs = title, status and decision paragraph read; long changelog-style files were sampled because they are append-only per-round logs with highly repetitive structure.

| path | status | LOC | actual status | description |
|---|---|---:|---|---|
| docs/AGENT_PLATFORM.md | reviewed (1-60), rest skimmed | 151 | Doc | Signed "agent bundle" text format and read-only /agent list|info|verify; install/bake lifecycle deferred. |
| docs/ARCHITECTURE.md | reviewed | 164 | Doc (aspirational; round labels wrong) | Aug-22 "one-page map": CrossEngin "is an AI model"; 5 deployment modes with shipped/planned table; round numbers and ADR cross-refs do not match the ADR files. |
| docs/CHAT_USAGE.md | skimmed | 867 | Doc | Slash-command guide for the chat REPL after R39 (June), lightly updated in Sept. |
| docs/CODING_REVIEWER.md | reviewed | 92 | Doc | Describes an 80-atom/37-edge smell->remedy lookup pack; user types a smell label (e.g. `null_deref`) and gets the linked remedy label. No code is read. |
| docs/CONTRIBUTING.md | reviewed (1-75), rest skimmed | 243 | Doc | The round model: one letter = one AI agent with exclusive file ownership, one commit per agent, NEXT_SESSION write-up with "honest caveats". |
| docs/COWORK.md | reviewed | 63 | Doc | "Multi-agent cowork" pt1 = print-only planner: 26 keywords -> 6 domains; no dispatch; example agent is a "fabricated bundle". |
| docs/DEPLOY_RUNBOOK.md | skimmed | 166 | Doc (audience does not exist yet) | Vercel + Linux backend deploy runbook; states the backend host and token "do not exist yet". |
| docs/DEPLOY_TLS.md | skimmed | 216 | Doc | stunnel/nginx TLS sidecar recipe for the RPC daemon (R54.1); later superseded by in-process TLS (R86-R94). |
| docs/END_TO_END.md | skimmed | 311 | Doc | Scripted chat transcript chaining Phase 0-6 pt1 commands (Nov 2026). |
| docs/GETTING_STARTED.md | skimmed | 408 | Doc | Install on Linux/WSL2/macOS + "Vercel hybrid" explanation (June). |
| docs/HOW_IT_LEARNS.md | reviewed | 221 | Doc | Nov-2026 demo: repeat "fever" + /good ten times; synapse weight rises +100 per /good to 1000. Calls this "frequency-adaptive latency" but shows no latency measurement. |
| docs/IP_AUDIT.md | reviewed | 432 | Doc (self-audit by header comments) | Licensing audit of 112 files in 3 dirs: all "hand-rolled from public spec"; method = read file header comments + grep imports; excludes data packs, scripts, web/, infra/. |
| docs/MCP_INBOUND.md | reviewed (1-50), rest skimmed | 294 | Doc | States the existing MCP module "is not an MCP server" (name -> canned string registry); pt1 adds /mcp list|register|call over that registry; real server deferred (pt2a stdio server landed 11-09). |
| docs/NOVA_RUNTIME_GAPS.md | skimmed (preface, R-1, vision gaps, priority list) | 837 | Doc | Canonical list of ~30 NOVA runtime gaps/bugs with workarounds (no CSPRNG in container, str_eq unreliable on short literals with 1,465 call sites, broken nanotime, etc.). |
| docs/NOVA_UPSTREAM_FIXES.md | skimmed | 54 | Doc | Pointer: NOVA PRs #13-#18 that retired CrossEngin workarounds (Nov). |
| docs/POSITIONING.md | reviewed | 119 | Doc (marketing) | Sales brief: "the biggest brain of all AI"; three buyer audiences, competitor table, three licence tiers. |
| docs/PT2_SAFETY_DEMO.md | skimmed | 136 | Doc | Demo of Ed25519-signed snapshot verify-on-load; keys generated with openssl. |
| docs/SEGFAULT_TRIAGE_R3A.md | skimmed (summary + table) | 431 | Doc | Oct-01 triage: ~29 unit tests SIGSEGV; ~22-24 traced to NOVA `str_eq` flakiness. |
| docs/SESSION_LOG.md | reviewed | 125 | Doc | Index of the Nov-09 "Phase 0-7 arc": 20 PRs in one session, deferred-scope table per phase. |
| docs/SHIP_AS_APP.md | skimmed (1-45, headings; 5,770 lines, 55 per-round "7.x" verb sections appended) | 5770 | Doc (operator manual turned changelog) | JSON-RPC daemon operator manual (R50) that grew a section per round up to R111. |
| docs/TOUR.md | reviewed (1-30) | 90 | Doc | 5-minute tour (June 14): repeats "roughly 6M nodes... 100Hz"; calls AGI capability "an architectural programme, not a benchmarked claim". |
| docs/TRAIN_WITH_OLLAMA.md | reviewed (1-70), rest skimmed | 165 | Doc | How to enable an Ollama model to (a) rewrite replies into prose and (b) extract .cerec records from text. "Train" here means prompt an LLM to produce records for review. |
| docs/UPSTREAM_NOVA_BUGS.md | skimmed | 1025 | Doc | Manifest of 18 NOVA codegen/runtime bugs CrossEngin worked around, with upstream-fix status. |
| docs/USER_GUIDE_DEPLOY_DATA_COMPARE.md | reviewed (headline, section 4, appendix) | 300 | Doc | Plain-English guide (Oct 31) with the most balanced LLM comparison in the repo ("Neither row is the winner"; fluency "Minimal"). |
| docs/USING.md | reviewed | 567 | Doc | Operator guide (Aug 3): /assert, .cerec packs, importers, LLM-as-preprocessor (ollama/llama.cpp/openai), and the "honest gap analysis vs Claude/ChatGPT". |
| docs/VISION.md | reviewed | 283 | Doc (aspirational) | Aug 21-22 vision: mother/child "AI Factory", 5 deployment modes, competitor tables ("Zero" hallucination, "no external deps"), Phase A-J roadmap; ADR cross-refs mismatch the files. |
| docs/WEB_UI.md | skimmed | 266 | Doc | Guide to the browser SPA served by a Python stdlib shim (R108). |
| docs/adr/0001-substrate-architecture.md | skimmed (title/status/decision) | 42 | Doc (ADR) | ADR-0001: Substrate architecture vs modular workflow — status: Proposed |
| docs/adr/0002-seven-core-primitives.md | skimmed (title/status/decision) | 51 | Doc (ADR) | ADR-0002: Seven core primitives (node/synapse/signal/atom/moment/gate/KG/reader) — status: Proposed |
| docs/adr/0003-scaling-plan.md | reviewed | 47 | Doc (ADR) | ADR-0003: Scaling plan (1M v1 -> 1B target, sparse connectivity, growth strategy) — status: Proposed |
| docs/adr/0004-multi-kg-organization.md | skimmed (title/status/decision) | 42 | Doc (ADR) | ADR-0004: Multi-KG organization by domain with cross-references — status: Proposed |
| docs/adr/0005-nova-language-and-enhancements.md | skimmed (title/status/decision) | 46 | Doc (ADR) | ADR-0005: NOVA as implementation language with required enhancements — status: Proposed |
| docs/adr/0006-node-design.md | skimmed (title/status/decision) | 44 | Doc (ADR) | ADR-0006: Node design (uniform behavior, sparse connectivity, atom production) — status: Proposed |
| docs/adr/0007-synapse-design.md | skimmed (title/status/decision) | 44 | Doc (ADR) | ADR-0007: Synapse design (Hebbian + error-driven plasticity, growth, pruning) — status: Proposed |
| docs/adr/0008-signal-taxonomy.md | skimmed (title/status/decision) | 59 | Doc (ADR) | ADR-0008: Signal taxonomy (18 types) — status: Proposed |
| docs/adr/0009-gate-design.md | skimmed (title/status/decision) | 44 | Doc (ADR) | ADR-0009: Gate design (learned routing, signal-content-based, broadcast support) — status: Proposed |
| docs/adr/0010-first-nodes.md | skimmed (title/status/decision) | 44 | Doc (ADR) | ADR-0010: First nodes (specialized sensory input receivers per part) — status: Proposed |
| docs/adr/0011-reader-hybrid-architecture.md | skimmed (title/status/decision) | 38 | Doc (ADR) | ADR-0011: Reader: Option 5 hybrid (substrate + predictive components) — status: Proposed |
| docs/adr/0012-reader-five-stages.md | skimmed (title/status/decision) | 38 | Doc (ADR) | ADR-0012: Reader five stages (lexical anchor, context bias, spreading activation, coherence check, fetch/route/learn) — status: Proposed |
| docs/adr/0013-output-generation.md | reviewed | 37 | Doc (ADR) | ADR-0013: Output generation: pure substrate, no LLM — status: Proposed |
| docs/adr/0014-no-llm-cognition.md | reviewed | 36 | Doc (ADR) | ADR-0014: No-LLM cognition principle (LLM-bridge only for STT/TTS modality) — status: Proposed |
| docs/adr/0015-language-atoms.md | skimmed (title/status/decision) | 40 | Doc (ADR) | ADR-0015: Language atoms in substrate (words, phonemes, syntax patterns as atoms) — status: Proposed |
| docs/adr/0016-atom-design.md | skimmed (title/status/decision) | 40 | Doc (ADR) | ADR-0016: Atom design (mutable, KG-stored, cross-KG referenced, Bayesian confidence) — status: Proposed |
| docs/adr/0017-multi-kg-cross-references.md | skimmed (title/status/decision) | 40 | Doc (ADR) | ADR-0017: Multi-KG with cross-references (spawn-on-new-domain, similarity-weighted cross-refs, automatic and earned link — status: Proposed |
| docs/adr/0018-concept-layer-evolution.md | skimmed (title/status/decision) | 42 | Doc (ADR) | ADR-0018: Concept layer evolution (hierarchy, schemas, multi-vector embeddings, integration with multi-KG) — status: Proposed |
| docs/adr/0019-procedural-memory-and-skills.md | skimmed (title/status/decision) | 40 | Doc (ADR) | ADR-0019: Procedural memory and KG-skills (skills as procedural rules + skills KG) — status: Proposed |
| docs/adr/0020-self-model-competence.md | skimmed (title/status/decision) | 40 | Doc (ADR) | ADR-0020: Self-model competence tracking (what the system knows it can do) — status: Proposed |
| docs/adr/0021-moments.md | skimmed (title/status/decision) | 44 | Doc (ADR) | ADR-0021: Moments (timestamped perception, lifecycle, episodic integration) — status: Proposed |
| docs/adr/0022-episodic-memory.md | skimmed (title/status/decision) | 45 | Doc (ADR) | ADR-0022: Episodic memory (storage, decay, consolidation, replay during idle) — status: Proposed |
| docs/adr/0023-bayesian-belief-tracking.md | skimmed (title/status/decision) | 59 | Doc (ADR) | ADR-0023: Bayesian belief tracking refinement (alpha/beta per atom, decay, conflict) — status: Proposed |
| docs/adr/0024-predictive-coding.md | skimmed (title/status/decision) | 45 | Doc (ADR) | ADR-0024: Predictive coding between layers (top-down predictions, bottom-up errors) — status: Proposed |
| docs/adr/0025-atom-birth-and-death.md | skimmed (title/status/decision) | 45 | Doc (ADR) | ADR-0025: Atom birth and death (co-activation pattern -> new atom; decay-based GC) — status: Proposed |
| docs/adr/0026-self-learning-triggers.md | skimmed (title/status/decision) | 45 | Doc (ADR) | ADR-0026: Self-learning triggers (unknown query, curiosity drive, imagination gap, prediction error, user request, all c — status: Proposed |
| docs/adr/0027-ask-user-to-teach.md | skimmed (title/status/decision) | 42 | Doc (ADR) | ADR-0027: Ask-user-to-teach mechanism (when, how, integration with response flow) — status: Proposed |
| docs/adr/0028-internet-fetching.md | skimmed (title/status/decision) | 45 | Doc (ADR) | ADR-0028: Internet fetching design (whitelist, rate limiting, validation, audit, cache) — status: Proposed |
| docs/adr/0029-source-authority-weighting.md | skimmed (title/status/decision) | 48 | Doc (ADR) | ADR-0029: Source authority weighting and conflict resolution (Tier A/B/C sources, newest-wins for guidelines, oldest-win — status: Proposed |
| docs/adr/0030-confidence-thresholds.md | skimmed (title/status/decision) | 46 | Doc (ADR) | ADR-0030: Confidence thresholds for "learned enough" (test questions, multi-source agreement, user confirmation, all thr — status: Proposed |
| docs/adr/0031-reasoning.md | skimmed (title/status/decision) | 39 | Doc (ADR) | ADR-0031: Reasoning (hybrid: substrate atoms for inferential operators + module functions for complex multi-step strateg — status: Proposed |
| docs/adr/0032-imagination-evolution.md | skimmed (title/status/decision) | 39 | Doc (ADR) | ADR-0032: Imagination subsystem evolution (current 10 patterns -> learn new patterns from experience; forward/counterfac — status: Proposed |
| docs/adr/0033-goal-engine-evolution.md | skimmed (title/status/decision) | 37 | Doc (ADR) | ADR-0033: Goal engine evolution (existing 4 drives + long-horizon persistence + sub-goal trees + cross-session continuit — status: Proposed |
| docs/adr/0034-soul-wrapper.md | skimmed (title/status/decision) | 40 | Doc (ADR) | ADR-0034: Soul as wrapper (identity slow, state fast, goals medium, values, constitution, themes, loyalty) — status: Proposed |
| docs/adr/0035-emotion-system.md | skimmed (title/status/decision) | 38 | Doc (ADR) | ADR-0035: Emotion system (OCC appraisal of moments against goals/values, OCEAN personality conditioning, emotion-modulat — status: Proposed |
| docs/adr/0036-six-concurrent-loops.md | skimmed (title/status/decision) | 38 | Doc (ADR) | ADR-0036: Six concurrent loops + imagination idle loop (true concurrency, fiber or process, communication channels) — status: Proposed |
| docs/adr/0037-scheduler.md | skimmed (title/status/decision) | 38 | Doc (ADR) | ADR-0037: Scheduler (hybrid: 100Hz substrate tick layered on event-driven coord) — status: Proposed |
| docs/adr/0038-self-model-query-api.md | skimmed (title/status/decision) | 36 | Doc (ADR) | ADR-0038: Self-model query API (system can describe self/state/goals in language) — status: Proposed |
| docs/adr/0039-theory-of-mind.md | reviewed (key sections) | 38 | Doc (ADR) | ADR-0039: Theory of mind in concept layer (user-as-concept with rich properties, updates from observation, used for empa — status: Proposed |
| docs/adr/0040-long-horizon-goals.md | skimmed (title/status/decision) | 40 | Doc (ADR) | ADR-0040: Long-horizon goal persistence (multi-day/multi-week goals surviving process restarts, intermittent attention) — status: Proposed |
| docs/adr/0041-permission-tiers.md | skimmed (title/status/decision) | 38 | Doc (ADR) | ADR-0041: Permission tiers (auto / notify / approve based on action class) — status: Proposed |
| docs/adr/0042-reversibility-classifier.md | skimmed (title/status/decision) | 36 | Doc (ADR) | ADR-0042: Reversibility classifier (per-action-type lookup, default irreversible) — status: Proposed |
| docs/adr/0043-decision-log.md | skimmed (title/status/decision) | 108 | Doc (ADR) | ADR-0043: Decision log (append-only, full trace per action, user-inspectable) — status: Proposed |
| docs/adr/0044-override-mechanism.md | skimmed (title/status/decision) | 41 | Doc (ADR) | ADR-0044: Override mechanism (belief edit, goal veto, hard stop, kill switch) — status: Proposed |
| docs/adr/0045-constitutional-rules.md | skimmed (title/status/decision) | 36 | Doc (ADR) | ADR-0045: Constitutional rules (hard inhibitory signals, enterprise vs user loyalty resolution) — status: Proposed |
| docs/adr/0046-deployment-v1.md | skimmed (title/status/decision) | 37 | Doc (ADR) | ADR-0046: Deployment v1 (personal desktop, single user, single device, federation-ready) — status: Proposed |
| docs/adr/0047-deployment-v2.md | skimmed (title/status/decision) | 37 | Doc (ADR) | ADR-0047: Deployment v2 (enterprise pilot, one tenant per process, base brain + tenant-specific learning) — status: Proposed |
| docs/adr/0048-persistence.md | skimmed (title/status/decision) | 37 | Doc (ADR) | ADR-0048: Persistence (which state survives restart, snapshot format, rehydration order — soul first, then KGs, then epi — status: Proposed |
| docs/adr/0049-testing-and-benchmarks.md | reviewed (key sections) | 37 | Doc (ADR) | ADR-0049: Testing and benchmarks (multi-day companion-quality test, domain-specific QA, the 8 capability tests) — status: Proposed |
| docs/adr/0050-build-sequence-and-milestones.md | reviewed (key sections) | 55 | Doc (ADR) | ADR-0050: Build sequence and milestones (12-step ordered plan from substrate kernel through enterprise pilot) — status: Proposed |
| docs/adr/0051-hdc-vsa-embeddings.md | reviewed (key sections) | 189 | Doc (ADR) | ADR-0051: HDC / VSA embedding layer (P1 keystone) — status: Proposed |
| docs/adr/0052-predictive-coding-three-factor.md | skimmed (title/status/decision) | 162 | Doc (ADR) | ADR-0052: Predictive coding + three-factor learning + Forward-Forward (P2) — status: Proposed |
| docs/adr/0053-ingestion-openie-entity-resolution.md | skimmed (title/status/decision) | 139 | Doc (ADR) | ADR-0053: Ingestion — formats, OpenIE, entity resolution (P3) — status: Proposed |
| docs/adr/0054-agentic-tooling.md | skimmed (title/status/decision) | 128 | Doc (ADR) | ADR-0054: Agentic tooling (P4) — status: Proposed |
| docs/adr/0055-simulation-self-improvement.md | reviewed (key sections) | 122 | Doc (ADR) | ADR-0055: Simulation environment + self-improvement (P5) — status: Proposed |
| docs/adr/0056-followup-integration.md | skimmed (title/status/decision) | 115 | Doc (ADR) | ADR-0056: Follow-up integration round (P1–P5 "Honest gaps") — status: Proposed |
| docs/adr/0057-autonomous-loop.md | reviewed (key sections) | 99 | Doc (ADR) | ADR-0057: The always-on autonomous loop (capstone) — status: Proposed |
| docs/adr/0058-coverage-closure.md | skimmed (title/status/decision) | 80 | Doc (ADR) | ADR-0058: Coverage closure — the last 6 untested modules (NL_AND_COVERAGE C1) — status: Proposed |
| docs/adr/0059-nl-question-bridge.md | skimmed (title/status/decision) | 90 | Doc (ADR) | ADR-0059: NL question → structured KG answer (NL_AND_COVERAGE N1) — status: Proposed |
| docs/adr/0060-number-words.md | skimmed (title/status/decision) | 71 | Doc (ADR) | ADR-0060: number-words & units → value (NL_AND_COVERAGE N2) — status: Proposed |
| docs/adr/0061-openie-depth.md | skimmed (title/status/decision) | 76 | Doc (ADR) | ADR-0061: OpenIE depth — negation, coordination, coreference (NL_AND_COVERAGE N3) — status: Proposed |
| docs/adr/0062-nl-generation.md | skimmed (title/status/decision) | 73 | Doc (ADR) | ADR-0062: NL generation quality (NL_AND_COVERAGE N4) — status: Proposed |
| docs/adr/0063-stream-http-ip-overflow-fix.md | skimmed (title/status/decision) | 114 | Doc (ADR) | ADR-0063: Fix `_stream_http_ip_to_int` IP-packing overflow (NOVA bug #11) — status: Proposed |
| docs/adr/0064-code-review-pack-segfault-fix.md | skimmed (title/status/decision) | 131 | Doc (ADR) | ADR-0064: Fix P0 segfault in test_code_review_pack — missing imagination_engine import — status: Proposed |
| docs/adr/0065-dtls12-compile-hang.md | skimmed (title/status/decision) | 213 | Doc (ADR) | ADR-0065: dtls12.nova compile hang — the long `+`-chain expression blowup — status: Accepted (source-level fix applied) |
| docs/adr/0066-int-safety-bug11-guard.md | skimmed (title/status/decision) | 108 | Doc (ADR) | ADR-0066: int-safety standard + lint guard for NOVA codegen bug #11 (P0) — status: Proposed |
| docs/adr/0067-ci-unblock-revealed-failures.md | reviewed | 83 | Doc (ADR) | ADR-0067: CI unblock — the full unit suite now completes, and the failures it revealed — status: Proposed |
| docs/adr/0068-dtls12-epoch-rotation-fix.md | skimmed (title/status/decision) | 229 | Doc (ADR) | ADR-0068: dtls12 epoch-rotation / SRTP-export — the 10 failing assertions are all TEST bugs — status: Accepted (test-level fix applied; `src/federation/dtls12.nov |
| docs/adr/0069-turn-flaky-segfault.md | skimmed (title/status/decision) | 184 | Doc (ADR) | ADR-0069: Fix flaky SIGSEGV in test_turn — NOVA codegen bug #11 (two-large-operand `!=`) + large hex literal miscompilat — status: Proposed |
| docs/adr/0070-operator-adjacency-index.md | skimmed (title/status/decision) | 102 | Doc (ADR) | ADR-0070: Operator adjacency index — O(degree) reasoning lookups (P1.5) — status: Proposed |
| docs/adr/0071-query-kind-index-fastpath.md | skimmed (title/status/decision) | 70 | Doc (ADR) | ADR-0071: Query `kind` fast-path via the existing kind index (P1.6) — status: Proposed |
| docs/adr/0072-memory-lifecycle-design.md | skimmed (title/status/decision) | 96 | Doc (ADR) | ADR-0072: KG memory lifecycle — design for eviction / reclamation / paging (P1.7) — status: Proposed (design only — no implementation in this pass; see  |
| docs/adr/0073-ice-turn-flaky-segfault.md | skimmed (title/status/decision) | 217 | Doc (ADR) | ADR-0073: Fix flaky SIGSEGV in test_ice_turn — NOVA codegen bug #11 (two-large-operand `==` / `!=`) + large hex literal  — status: Proposed |
| docs/adr/0074-atom-reclamation-mechanism.md | skimmed (title/status/decision) | 89 | Doc (ADR) | ADR-0074: Atom reclamation mechanism — Phase A of the memory lifecycle — status: Accepted (implements the first, zero-id-reuse increment of A |
| docs/adr/0075-death-sweep-reclamation-wiring.md | skimmed (title/status/decision) | 77 | Doc (ADR) | ADR-0075: Wire the death sweep to reclamation — Phase B (working eviction) — status: Accepted (Phase B of ADR-0072; builds on the ADR-0074 mechan |
| docs/adr/0076-phase-c-reference-complete-gate.md | skimmed (title/status/decision) | 88 | Doc (ADR) | ADR-0076: Phase C — reference-complete death gate; id-reuse handle audit — status: Accepted (Phase C, part 1: closes a correctness hazard + rec |
| docs/adr/0077-xref-persistence.md | skimmed (title/status/decision) | 117 | Doc (ADR) | ADR-0077: Persist same-KG general xrefs across a snapshot — status: Accepted — the snapshot round-trip now carries SAME-KG gener |
| docs/adr/0078-cross-kg-xref-persistence.md | skimmed (title/status/decision) | 127 | Doc (ADR) | ADR-0078: Persist cross-KG general xrefs across a snapshot — status: Accepted — the snapshot round-trip now carries CROSS-KG gene |
| docs/adr/0079-kg-compaction.md | skimmed (title/status/decision) | 118 | Doc (ADR) | 0079: In-place KG compaction — status: Accepted — capstone of the memory-lifecycle work (ADRs 0072  |
| docs/adr/0080-death-gate-episodic-protection.md | skimmed (title/status/decision) | 80 | Doc (ADR) | ADR-0080: Death-gate episodic-member protection (future-proofing id reuse) — status: Accepted |
| docs/adr/0081-wire-gc-into-autonomous-loop.md | skimmed (title/status/decision) | 85 | Doc (ADR) | ADR-0081: Wire the memory-lifecycle GC into the live autonomous loop — status: Accepted |
| docs/adr/0082-alias-gate-and-episodic-consolidation-feed.md | skimmed (title/status/decision) | 132 | Doc (ADR) | ADR-0082: Alias-referenced death-gate protection and feeding observation ids into consolidation — status: Accepted |
| docs/adr/0083-chat-state-xref-persistence.md | skimmed (title/status/decision) | 132 | Doc (ADR) | ADR-0083: Persist cross-KG references (xrefs) in the chat_state format — status: Accepted — the chat session save/load path (`chat_state_save |
| docs/adr/0084-alias-autorecord-and-protection-context.md | skimmed (title/status/decision) | 97 | Doc (ADR) | ADR-0084: Synonym alias auto-record + death-gate protection context — status: Accepted |
| docs/adr/0085-chat-state-snapshot-fidelity.md | skimmed (title/status/decision) | 181 | Doc (ADR) | ADR-0085: Close the chat_state vs snapshot fidelity gaps (embeddings, operators, gloss) + xref coactivation count — status: Accepted — Date 2026-06-13. |
| docs/adr/0086-autocompact-trigger.md | skimmed (title/status/decision) | 153 | Doc (ADR) | ADR-0086: Auto-compact trigger via autonomous_loop freelist watch — status: Accepted |
| docs/adr/0086-truth-seeking-reasoning-engine.md | reviewed (key sections) | 261 | Doc (ADR) | ADR-0086: Truth-seeking reasoning engine — master architecture and roadmap — status: Proposed |
| docs/adr/0087-gc-observability.md | skimmed (title/status/decision) | 199 | Doc (ADR) | ADR-0087: GC observability (metrics registry + /gc-stats chat command) — status: Accepted |
| docs/adr/0087-provenance-and-licensing-ledger.md | skimmed (title/status/decision) | 224 | Doc (ADR) | ADR-0087: Provenance and licensing ledger (per-atom license + evidence grade) — status: Proposed |
| docs/adr/0088-formal-verification-path.md | skimmed (title/status/decision) | 639 | Doc (ADR) | ADR-0088: Formal-verification path for math/logic/CS atoms — status: Proposed |
| docs/adr/0088-xref-query-time-traversal.md | skimmed (title/status/decision) | 192 | Doc (ADR) | ADR-0088: Cross-KG xref query-time traversal — status: Accepted |
| docs/adr/0089-argumentation-bayesian-debate-engine.md | skimmed (title/status/decision) | 284 | Doc (ADR) | ADR-0089: Argumentation + Bayesian adjudication debate engine — status: Proposed |
| docs/adr/0089-federation-daemon-mvp.md | skimmed (title/status/decision) | 306 | Doc (ADR) | ADR-0089: MVP federation daemon (gossip + kg_sync + distributed_query) — status: Accepted |
| docs/adr/0090-contested-domain-steelman-policy.md | skimmed (title/status/decision) | 116 | Doc (ADR) | ADR-0090: Contested-domain steelman policy (represent every evidenced position at its strongest, never average into fals — status: Proposed |
| docs/adr/0090-federation-coordination-inference.md | skimmed (title/status/decision) | 293 | Doc (ADR) | ADR-0090: Federation coordination + inference (leader election + distributed rules) — status: Accepted |
| docs/adr/0091-federation-durability.md | skimmed (title/status/decision) | 330 | Doc (ADR) | ADR-0091: Federation durability (snapshot attestation + replication) — status: Accepted |
| docs/adr/0091-tiered-editions.md | reviewed | 46 | Doc (ADR) | ADR-0091: Tiered editions — Edge / Enterprise / Research — status: Proposed |
| docs/adr/0092-autonomous-self-update-governance.md | reviewed (key sections) | 315 | Doc (ADR) | ADR-0092: Autonomous self-update governance & safety gates — status: Proposed |
| docs/adr/0092-perception-module.md | skimmed (title/status/decision) | 271 | Doc (ADR) | ADR-0092: Perception module (parts/perception atoms + module + loop wiring) — status: Accepted |
| docs/adr/0093-action-module.md | skimmed (title/status/decision) | 326 | Doc (ADR) | ADR-0093: Action module (parts/action atoms + module + motor_map + effector-gate wiring) — status: Accepted |
| docs/adr/0093-domain-rollout-math-logic-cs.md | skimmed (title/status/decision) | 175 | Doc (ADR) | ADR-0093: Domain rollout strategy — math/logic/CS first — status: Proposed |
| docs/adr/0094-dtls-cert-chain-completion.md | skimmed (title/status/decision) | 332 | Doc (ADR) | ADR-0094: DTLS cert-verify chain completion (wire cert_chain_verify + truststore + hostname into dtls12) — status: Accepted |
| docs/adr/0094-security-architecture-and-threat-model.md | skimmed (title/status/decision) | 160 | Doc (ADR) | ADR-0094: Security architecture and threat model for the truth-seeking engine — status: Proposed |
| docs/adr/0095-dtls-srtp-completion.md | skimmed (title/status/decision) | 441 | Doc (ADR) | ADR-0095: DTLS-SRTP EKM stub-forward + `use_srtp` ClientHello extension (Phase O R2) — status: Accepted |
| docs/adr/0095-embodiment-sensorimotor-and-robotics.md | skimmed (title/status/decision) | 131 | Doc (ADR) | ADR-0095: Embodiment — sensorimotor architecture and robotics control — status: Proposed |
| docs/adr/0096-dtls-over-tcp-shim.md | reviewed (key sections) | 387 | Doc (ADR) | ADR-0096: Non-standard DTLS-1.2-over-TCP shim for gossip transport (Phase O R3) — status: Accepted |
| docs/adr/0096-machine-learning-policy.md | reviewed (key sections) | 133 | Doc (ADR) | ADR-0096: Machine-learning policy (online local learning yes, LLM/frozen-model cognition no) — status: Proposed |
| docs/adr/0097-dtls-server-flight.md | skimmed (title/status/decision) | 444 | Doc (ADR) | ADR-0097: DTLS 1.2 server-side handshake flight -- ClientHello parser + 4 body builders + transcript accumulator (Phase  — status: Accepted |
| docs/adr/0098-dtls-client-flight-finished.md | skimmed (title/status/decision) | 516 | Doc (ADR) | ADR-0098: DTLS 1.2 client-side handshake flight + Finished MAC + server flight-2 (Phase P R2) — status: Accepted |
| docs/adr/0099-dtls-extensions-and-streams.md | skimmed (title/status/decision) | 452 | Doc (ADR) | ADR-0099: DTLS extensions-block parser + `use_srtp` per-extension parser + DTLS-aware gossip stream helpers (Phase P R3) — status: Accepted |
| docs/adr/0100-moment-signal-cognition.md | reviewed | 214 | Doc (ADR) | ADR-0100: Moment-Signal Cognition (MSC) — the named cognitive architecture — status: Proposed |
| docs/adr/0100-nova-bootstrap-setarch-workaround.md | skimmed (title/status/decision) | 405 | Doc (ADR) | ADR-0100: NOVA bootstrap setarch -R workaround — status: Accepted |
| docs/adr/0101-data-acquisition-pipeline.md | skimmed (title/status/decision) | 422 | Doc (ADR) | ADR-0101: Data Acquisition Pipeline — status: Accepted (codifies R43+; documents the pipeline that R43 shi |
| docs/adr/0101-str-eq-migration.md | skimmed (title/status/decision) | 128 | Doc (ADR) | ADR-0101: `str_eq` → `str_eq_bytes` migration (R3b) — status: Accepted. Shipped by Phase Q R3b. Co-numbered with |
| docs/adr/0102-persona.md | reviewed (key sections) | 363 | Doc (ADR) | ADR-0102: Persona — full, per-user, advise-only — status: Proposed |
| docs/adr/0102-simd-ocr-segv-fixes.md | skimmed (title/status/decision) | 120 | Doc (ADR) | ADR-0102: SIMD / OCR SEGV fixes — class-B outliers (R3c) — status: Accepted. Shipped by Phase Q R3c. Co-numbered with |
| docs/adr/0103-memcpy-raw-tagged-ptr-workarounds.md | skimmed (title/status/decision) | 121 | Doc (ADR) | ADR-0103 — `memcpy_raw` + `rt_str_to_int` tagged-pointer workarounds — status: Accepted (2026-10-01, Phase Q R3d). |
| docs/adr/0103-skill-runtime.md | skimmed (title/status/decision) | 414 | Doc (ADR) | ADR-0103: Skill Runtime — the composition point where knowledge serves users — status: Proposed |
| docs/adr/0104-nl-surface.md | reviewed (key sections) | 463 | Doc (ADR) | ADR-0104: NL Surface Layer — grammar-first + LLM-preprocessor fallback — status: Proposed |
| docs/adr/0104-type-of-regression-and-cluster-d-fixes.md | skimmed (title/status/decision) | 195 | Doc (ADR) | ADR-0104 -- type_of() runtime regression and Cluster D/E residual fixes — status: Superseded by NOVA commit 651a507 (type_of codegen fix, 2026 |
| docs/adr/0105-sandbox-architecture.md | skimmed (title/status/decision) | 341 | Doc (ADR) | ADR-0105: Sandbox Architecture — capability separation, TLS, signed skill install — status: Proposed (R54 delivers capability tokens + verb-cap map; TLS |
| docs/adr/0105-sentinel-equality-and-rebuild-guards.md | skimmed (title/status/decision) | 140 | Doc (ADR) | ADR-0105 -- sentinel-equality (bug-#11) workarounds and rebuild-guard reinforcement — status: Accepted |
| docs/adr/0106-capsules.md | skimmed (title/status/decision) | 311 | Doc (ADR) | ADR-0106: Capsules — named shareable bundles on top of atoms — status: Proposed |
| docs/adr/0106-segfault-arc-closeout.md | skimmed (title/status/decision) | 110 | Doc (ADR) | ADR-0106 -- segfault-arc close-out (R3g residuals) — status: Accepted |
| docs/adr/0107-motor-map-population.md | skimmed (title/status/decision) | 107 | Doc (ADR) | ADR-0107 -- motor_map population + action_module wiring (Phase R1) — status: none stated |
| docs/adr/0107-pattern-capsules.md | skimmed (title/status/decision) | 243 | Doc (ADR) | ADR-0107: Pattern Capsules — reusable heuristics for skills — status: Proposed (R53) |
| docs/adr/0108-action-submit-dispatch.md | skimmed (title/status/decision) | 135 | Doc (ADR) | ADR-0108 -- payload-shim + per-class dispatch in `action_submit` (Phase R2) — status: none stated |
| docs/adr/0108-style-capsules.md | skimmed (title/status/decision) | 231 | Doc (ADR) | ADR-0108: Style Capsules — persona-owned rendering variants — status: Proposed (R52) |
| docs/adr/0109-operand-materialization.md | skimmed (title/status/decision) | 140 | Doc (ADR) | ADR-0109 -- operand materialization + reach-ability + SPEAK tier fix (Phase R3) — status: none stated |
| docs/adr/0109-ship-as-app.md | skimmed (title/status/decision) | 226 | Doc (ADR) | ADR-0109: Ship as App — packaging, distribution, and the daemon story — status: Proposed (R50) |
| docs/adr/0110-relay-bin-dtls-sealed-frame.md | skimmed (title/status/decision) | 143 | Doc (ADR) | ADR-0110 -- RELAY_BIN sealed-frame under DTLS (Phase P R4) — status: none stated |
| docs/adr/0111-auto-broadcast-on-snapshot-save.md | skimmed (title/status/decision) | 255 | Doc (ADR) | ADR-0111 -- Auto-broadcast attestation on snapshot save (Phase M R5) — status: none stated |
| docs/adr/0112-goal-template-registry.md | skimmed (title/status/decision) | 136 | Doc (ADR) | ADR-0112 -- goal-template registry for operand materialization (Phase R4) — status: none stated |
| docs/adr/0113-planner-keyword-heuristics.md | skimmed (title/status/decision) | 133 | Doc (ADR) | ADR-0113 -- planner keyword heuristics for operand materialization (Phase R5) — status: none stated |
| docs/adr/0114-dtls12-handshake-completion.md | skimmed (title/status/decision) | 215 | Doc (ADR) | ADR-0114: DTLS 1.2 handshake state-machine completion (close test_dtls12 to 519/0) — status: Proposed (2026-10-09); §1 superseded by R17 (2026-10-10). |
| docs/adr/adr-0200-crossengin-as-ai-factory.md | reviewed (key sections) | 522 | Doc (ADR) | ADR-0200: CrossEngin as AI Factory (Mother/Child Architecture) — status: Proposed (north-star). This ADR names the platform frame tha |
| docs/adr/adr-0201-nl-surface-small-llm-adapter.md | reviewed (key sections) | 270 | Doc (ADR) | ADR-0201: Sidecar Small-LLM NL Adapter (Fallback) — status: Proposed. Fixes the long-term shape of the small-LLM natural |
| docs/adr/adr-0202-cognitive-sandbox-and-multimodal-learning.md | skimmed (title/status/decision) | 276 | Doc (ADR) | ADR-0202: Cognitive Sandbox and Multimodal Learning — status: Proposed. Names the COGNITIVE sandbox as a first-class runti |
| docs/adr/adr-0203-mother-child-factory-runtime.md | skimmed (title/status/decision) | 286 | Doc (ADR) | ADR-0203: Mother/Child Factory Runtime — status: Proposed. Realizes the bake pipeline promised by ADR-0200 |
| docs/adr/adr-0204-slim-runtime-mode.md | skimmed (title/status/decision) | 212 | Doc (ADR) | ADR-0204: Slim Runtime Mode (`--child-mode`) — status: Proposed. Defines the boot-time flag that turns the standard |
| docs/adr/adr-0205-per-user-selective-load.md | skimmed (title/status/decision) | 200 | Doc (ADR) | ADR-0205: Per-User Selective Load — status: Proposed. Names the third consumption mode — same mother, pe |
| docs/adr/adr-0206-beliefs-and-self-awareness.md | reviewed (key sections) | 248 | Doc (ADR) | ADR-0206: Beliefs and Self-Awareness (First-Class Cognitive State) — status: Proposed. Promotes belief and self-awareness from scattered  |
| docs/adr/adr-0207-rag-and-fine-tuning-obsolescence.md | reviewed | 225 | Doc (ADR) | ADR-0207: RAG and Fine-Tuning Obsolescence — status: Proposed. Names the claim explicitly: given the CrossEngin s |
| docs/adr/adr-0208-latency-and-inference-budget.md | reviewed (key sections) | 227 | Doc (ADR) | ADR-0208: Latency and Inference Budget (Parity with LLMs) — status: Proposed. Establishes per-query-kind latency budgets that ke |
| docs/adr/adr-0209-deployment-form-factors.md | skimmed (title/status/decision) | 254 | Doc (ADR) | ADR-0209: Deployment Form Factors (Five Modes) — status: Proposed. Enumerates the five consumption modes named by ADR |
| docs/adr/adr-0210-agent-production.md | skimmed (title/status/decision) | 242 | Doc (ADR) | ADR-0210: Agent Production (Skills + Patterns + Composed Agents) — status: Tier 1 shipped (R47 -- ADR-0103); tier 2 shipped R109 -- Pha |
| docs/adr/adr-0211-llm-free-nlp-primary-path.md | reviewed (key sections) | 232 | Doc (ADR) | ADR-0211: LLM-Free NLP as Primary Path — status: Proposed. Locks the intended long-term shape of the NL surfa |
| docs/adr/r36f-0001-language-choice-nova.md | reviewed (key sections) | 103 | Doc (ADR) | ADR R36F-0001: NOVA as the implementation language — status: Accepted (R36F) -- decision originally made pre-R0, restated |
| docs/adr/r36f-0002-federated-learning-shape.md | skimmed (title/status/decision) | 91 | Doc (ADR) | ADR R36F-0002: Federated learning shape -- DP composition, EMA pull, Sybil model — status: Accepted (R36F) -- learning loop shape coalesced over R8 (in |
| docs/adr/r36f-0003-federation-stack-dtls-ice-turn-srtp.md | skimmed (title/status/decision) | 103 | Doc (ADR) | ADR R36F-0003: Federation transport -- DTLS 1.2 + ICE + STUN + TURN + SRTP — status: Accepted (R36F) -- transport stack assembled across R30C (IC |
| docs/adr/r36f-0004-substrate-not-pipeline.md | skimmed (title/status/decision) | 102 | Doc (ADR) | ADR R36F-0004: Cognitive substrate over modular pipeline — status: Accepted (R36F) -- restates the core decision originally cap |
| docs/adr/r36f-0005-self-hosting-bit-identical.md | skimmed (title/status/decision) | 89 | Doc (ADR) | ADR R36F-0005: Bit-identical self-hosting as a regression-detection invariant — status: Accepted (R36F) -- ratifies a property of the NOVA toolchain |
| docs/adr/r36f-0006-canonical-crypto-primitives.md | skimmed (title/status/decision) | 111 | Doc (ADR) | ADR R36F-0006: Canonical crypto primitives under `safety/` — status: Accepted (R36F) -- crystallises the pattern established at R |
| docs/adr/r39-autonomous-learning-architecture.md | skimmed (title/status/decision) | 326 | Doc (ADR) | R39: Autonomous learning architecture (trigger -> research -> preprocess -> ingest) — status: Accepted -- R39 round wiring of pre-existing ADR primitives  |
| docs/adr/r39-persistence-and-rehydration.md | skimmed (title/status/decision) | 250 | Doc (ADR) | R39: Persistence and rehydration (chat-state save/load + R40 chat-integration plan) — status: Accepted -- R39 round adds a per-process chat-state save/loa |
| docs/adr/r39-self-identification-wiring.md | reviewed (key sections) | 206 | Doc (ADR) | R39: Self-identification wiring (chat -> self_model_query bridge) — status: Accepted -- R39 round wiring of the pre-existing `self_model |
| docs/adr/r40-per-category-cognition.md | skimmed (title/status/decision) | 161 | Doc (ADR) | R40: Per-category cognition (classify → route → strategy) — status: Accepted — R40 round. Introduces ADR-0055 (input classificat |
| docs/adr/r41-live-internet-learning.md | skimmed (title/status/decision) | 120 | Doc (ADR) | R41: Live internet `/learn` (resolve → fetch → preprocess → ingest) — status: Accepted — R41 round. Closes the "/learn is not connected to |
| docs/adr/r42-tls13-https-client.md | skimmed (title/status/decision) | 94 | Doc (ADR) | R42: In-engine TLS 1.3 client (HTTPS for /learn) — status: Accepted — R42 round. Advances TLS_AUDIT.md from "PSK channe |
| docs/adr/r43-tls-certificate-verification.md | skimmed (title/status/decision) | 102 | Doc (ADR) | R43: Strict TLS authentication — RSA cert-chain verification + pinned anchor — status: Accepted — R43 round. Adds certificate verification to the R |
| docs/adr/r44-triple-extraction-quality.md | skimmed (title/status/decision) | 64 | Doc (ADR) | R44: Cleaner triple extraction (content-word reasoning edges) — status: Accepted — R44 round. Improves `src/learning/preprocess.nova |
| docs/adr/r45-noun-phrase-chunking.md | skimmed (title/status/decision) | 71 | Doc (ADR) | R45: Noun-phrase chunking + block-aware sentence splitting — status: Accepted — R45 round. Extends R44's clean triple extraction  |
| docs/adr/r46-pluggable-pem-trust-store.md | skimmed (title/status/decision) | 75 | Doc (ADR) | R46: Pluggable PEM trust store (anchors not hard-coded) — status: Accepted — R46 round. Generalises the R43 strict-TLS pin fro |
| docs/adr/r47-ecdsa-certificate-verification.md | skimmed (title/status/decision) | 61 | Doc (ADR) | R47: ECDSA certificate verification (key-type-agnostic strict TLS) — status: Accepted — R47 round. Extends the strict-TLS verifier (R43/R |
| docs/adr/r48-reader-bigram-anchoring.md | skimmed (title/status/decision) | 61 | Doc (ADR) | R48: Reader-side bigram anchoring (free-text compounds) — status: Accepted — R48 round. Closes the loop opened by R45: compoun |
| docs/adr/r49-morphological-normalization.md | skimmed (title/status/decision) | 60 | Doc (ADR) | R49: Morphological normalization (inflected free text hits learned atoms) — status: Accepted — R49 round. Improves lexical recall: a user typing |
| docs/adr/r50-autonomous-research.md | skimmed (title/status/decision) | 81 | Doc (ADR) | R50: Autonomous research (self-initiated /learn on unknowns) — status: Accepted — R50 round. Wires the self-learning-trigger queue  |
| docs/adr/r51-persistence.md | skimmed (title/status/decision) | 99 | Doc (ADR) | R51: Persistence of reasoning operators (learned chains survive a restart) — status: Accepted — R51 round. Closes the durability gap so learned k |
| docs/adr/r52-same-turn-reanswer.md | skimmed (title/status/decision) | 91 | Doc (ADR) | R52: Same-turn re-answer after autonomous research — status: Accepted — R52 round (the "h" enhancement). Closes the idle- |
| docs/adr/r53-multi-source-research.md | skimmed (title/status/decision) | 93 | Doc (ADR) | R53: Multi-source, disambiguation-aware research — status: Accepted — R53 round (the "i" enhancement). Replaces R50's s |
| docs/adr/r54-irregular-morphology.md | skimmed (title/status/decision) | 79 | Doc (ADR) | R54: Irregular morphology (a lemma table lifts R49's regular-only limit) — status: Accepted — R54 round (the "j" enhancement). Adds an irregula |
| docs/adr/r55-search-and-independent-sources.md | skimmed (title/status/decision) | 87 | Doc (ADR) | R55: Real search/disambiguation + a genuinely independent source — status: Accepted — R55 round (the "k" enhancement). Adds a real sear |
| docs/adr/r56-reperceived-counts.md | skimmed (title/status/decision) | 69 | Doc (ADR) | R56: Surface re-perceived counts on the same-turn answer — status: Accepted — R56 round (the "l" enhancement). Makes the `perce |
| docs/adr/r57-derivational-morphology.md | skimmed (title/status/decision) | 81 | Doc (ADR) | R57: Derivational morphology (the part-of-speech layer past inflection) — status: Accepted — R57 round (the "m" enhancement). Adds derivationa |
| docs/adr/r58-json-parser.md | skimmed (title/status/decision) | 77 | Doc (ADR) | R58: A real JSON parser (cleaner OpenSearch + a dictionary-API source) — status: Accepted — R58 round (the "n" enhancement). Adds a recursive |
| docs/adr/r59-dictionary-enrichment.md | skimmed (title/status/decision) | 71 | Doc (ADR) | R59: Always-aggregate dictionary definitions in research — status: Accepted — R59 round (the "o" enhancement). Makes the dictio |
| docs/adr/r60-autodefine-unknown-words.md | skimmed (title/status/decision) | 68 | Doc (ADR) | R60: Autodefine unknown words (a dictionary sense without full research) — status: Accepted — R60 round (the "p" enhancement). An unknown conte |
| docs/adr/r61-same-turn-autodefine.md | skimmed (title/status/decision) | 71 | Doc (ADR) | R61: Same-turn autodefine (a defined word answers in one turn) — status: Accepted — R61 round (the "q" enhancement). Extends R52's sa |
| docs/adr/r62-deverbal-morphology.md | skimmed (title/status/decision) | 68 | Doc (ADR) | R62: Deverbal morphology (-tion/-sion via a curated lemma table) — status: Accepted — R62 round (the "r" enhancement). Adds the -tion / |
| docs/adr/r63-definition-genus-operator.md | skimmed (title/status/decision) | 68 | Doc (ADR) | R63: Link a defined word to its definition's genus (so it reasons) — status: Accepted — R63 round (the "s" enhancement). When a word is d |
| docs/adr/r64-why-sources.md | skimmed (title/status/decision) | 57 | Doc (ADR) | R64: Cite knowledge sources in /why — status: Accepted — R64 round (the "t" enhancement). `/why` now lists |
| docs/adr/r65-persist-gloss.md | skimmed (title/status/decision) | 66 | Doc (ADR) | R65: Persist dictionary glosses across a snapshot — status: Accepted — R65 round (the "u" enhancement). The autodefine g |
| docs/adr/r66-synonym-antonym-edges.md | skimmed (title/status/decision) | 63 | Doc (ADR) | R66: Synonym / antonym edges widen the reasoning graph — status: Accepted — R66 round (the "v" enhancement). When a word is d |
| docs/adr/r67-opposite-relation.md | skimmed (title/status/decision) | 61 | Doc (ADR) | R67: A first-class ROP_OPPOSITE relation for antonyms — status: Accepted — R67 round (the "w" enhancement). Antonyms get the |
| docs/adr/r68-knowledge-command.md | skimmed (title/status/decision) | 54 | Doc (ADR) | R68: A consolidated /knowledge WORD view — status: Accepted — R68 round (the "x" enhancement). One read-only co |
| docs/adr/r69-define-sets-gloss.md | skimmed (title/status/decision) | 56 | Doc (ADR) | R69: /define sets the gloss (consistent dictionary learning) — status: Accepted — R69 round (the "y" enhancement). Moves the gloss- |
| docs/adr/r70-knowledge-incoming-senses.md | skimmed (title/status/decision) | 55 | Doc (ADR) | R70: /knowledge shows incoming edges + senses — status: Accepted — R70 round. Extends `/knowledge WORD` (R68) with t |
| docs/adr/r71-source-weighted-chain.md | skimmed (title/status/decision) | 58 | Doc (ADR) | R71: Source-weighted forward chaining — status: Accepted — R71 round. The academic forward-chain now weights |
| docs/adr/r72-opposite-aware-contrast.md | skimmed (title/status/decision) | 57 | Doc (ADR) | R72: Opposite-aware contrast in forward-chain replies — status: Accepted — R72 round. When the academic strategy forward-cha |
| docs/adr/r73-opposite-belief-update.md | skimmed (title/status/decision) | 53 | Doc (ADR) | R73: Opposite-aware belief update (X asserted ⇒ its opposite less likely) — status: Accepted — R73 round. R72 surfaced an antonym as a contrast  |
| docs/adr/r74-confidence-qualified-answers.md | skimmed (title/status/decision) | 54 | Doc (ADR) | R74: Confidence-qualified answers — status: Accepted — R74 round. The academic forward-chain answer is n |
| docs/adr/r75-anaphora-resolution.md | skimmed (title/status/decision) | 58 | Doc (ADR) | R75: Anaphora resolution (a pronoun follows the last topic) — status: Accepted — R75 round. A follow-up pronoun ("it", "they", …)  |
| docs/adr/r86-in-process-tls-scaffolding.md | skimmed (title/status/decision) | 408 | Doc (ADR) | R86: In-process TLS for wire endpoints (scaffolding only) — status: Accepted — R86 round; wire-enabled in R94. R86 scaffolded th |
| docs/bench-capture.md | reviewed (1-16) | 106 | Doc | How to paste an offline LLM transcript for the reasoning benchmark; shipped transcripts are "illustrative", not recorded. |
| docs/design/atom-provenance-schema.md | skimmed | 157 | Doc | Field-level spec for per-atom licence/evidence-grade ledger (ADR-0087). |
| docs/design/data_flow.md | skimmed | 76 | Doc | One substrate tick traced through signal dispatch/gates (Phase 1 kernel). |
| docs/design/int-safety.md | skimmed | 118 | Doc | Developer warning: NOVA miscompiles integer arithmetic reaching 2^20; use int_* builtins + lint. |
| docs/design/overview.md | skimmed | 77 | Doc (stale, 2026-05-25) | Still describes "v0.1, Phase 1 of 10". |
| docs/design/system-architecture.md | skimmed | 190 | Doc | June-15 "single current source of truth" after the truth-seeking expansion; itself superseded by docs/ARCHITECTURE.md in August. |
| docs/design/truth-seeking-overview.md | reviewed (1-60) | 118 | Doc | Narrative for ADR-0086: scope "expanded" from companion to "truth-seeking reasoning engine" that "out-reasons LLMs on checkable questions". |
| docs/runbook/build.md | skimmed | 55 | Doc | Build steps (May). |
| docs/runbook/run.md | skimmed | 94 | Doc | Per-binary run reference (May). |
| docs/runbook/test.md | skimmed | 53 | Doc | Test commands (May). |
| docs/runbook/troubleshooting.md | skimmed | 54 | Doc | NOVA_ROOT path issues etc. (May). |
| docs/runbook/windows.md | skimmed | 171 | Doc | WSL2/Docker instructions (May). |
| docs/session_log/archive.md | skimmed (headings, R44..R38 sections, R28E/R29B, tail "Recommended next session", targeted greps; 18.5k lines of per-agent round write-ups) | 18507 | Doc | Reverse-chronological archive of every round write-up from Phase 1 (May) to R43 (Aug). Primary evidence for process and for the Aug "99 passing / 220 failing" test table. |
| README.md | skimmed (lines 1-140, 4105-4590 read; 43-4104 is an append-only per-round changelog in one blockquote, sampled+grepped) | 4590 | Doc (stale) | Project front page. 20 lines of MSC/substrate pitch + "Status (through R39)" table, then ~4,000 lines of per-round changelog, then a May-era "What works now (v1.0)" module list and a layout section that still says 50 ADRs. |
| ARCHITECTURE.md | skimmed (1-120 read, rest module catalog) | 1094 | Doc (stale, R25D 2026-06-03) | Layout guide + per-module catalog as of round 25 (~190 modules, "50 ADRs"); claims "zero external runtime dependencies" beside scripts/web.py. |
| ANALYSIS.md | reviewed | 173 | Doc (2026-06-14) | Self-analysis: "verified achievements" table (incl. "~6M-node fabric") + candid "Honest gaps" table (AGI is "a programme, not a benchmark"); Vercel deployment options. |
| MANUAL.md | skimmed | 623 | Doc | Build/run/test walkthrough (Codespaces quickstart, make targets); last touched 2026-08-03. |
| NEXT_SESSION.md | reviewed | 126 | Doc (stale) | Says it is "source of truth... updated at every session boundary" but is frozen at R44 (2026-08-03); R44 notes: chat REPL had been segfaulting ~10+ commits, 4 packs/116 atoms. |
| NL_AND_COVERAGE.md | skimmed | 150 | Doc (roadmap, 2026-06-11) | NL + test-coverage roadmap N1-N4/C1-C2; admits full `make test` could not run (compiler hang on dtls12); "covered" = some test imports the module. |
| ENHANCEMENTS_ROADMAP.md | skimmed (1-60, headings, 1925-1960 read; bulk is per-round status log) | 5963 | Doc (roadmap turned changelog) | Began 2026-06-11 as P1-P5 plan (HDC, predictive coding, ingestion, tooling, self-improvement); first lower-case use of "moment-signal"; then accreted 5,900 lines of Phase L-R / NOVA-bug round logs. Contains "does NOT claim AGI". |
| FEDERATED_AUDIT.md | skimmed (head + grep; 6.5k-line per-round addenda) | 6535 | Doc | Federated "multi-soul" learning audit; append-only per-round addenda about gossip/DTLS/TURN/relay rounds. |
| SECAGG_AUDIT.md | skimmed | 1188 | Doc | Secure-aggregation audit: pairwise masking, dropout recovery, DH-256 "strawman" then DH-2048; mask derivation is an LCG. |
| DP_AUDIT.md | skimmed | 319 | Doc | Differential-privacy audit: discrete Laplace on integer milli values; notes NOVA had no floats. |
| REGRESSION_HUNT_R26F.md | reviewed (TL;DR), rest skimmed | 275 | Doc | One-off perf regression sweep vs bench/baseline.json: zero regressions; speed-ups attributed to a rebuilt compiler. |
| RETROSPECTIVE_26_ROUNDS.md | reviewed (sections 1-4, 8), appendices skimmed | 1181 | Doc | Retrospective of 26 rounds / "~156 parallel-agent dispatches" (2026-05-25..06-03): round headlines, file-ownership protocol, failure modes, honest-disclosure notes, open R*.2 follow-ups. |

Non-md files in docs/ (not counted above): `docs/caps.sample.conf` (sample capability config), `docs/samples/sample_agent.bundle` (616-byte signed sample bundle), `docs/samples/sample_agent.pub` (32-byte Ed25519 public key).
