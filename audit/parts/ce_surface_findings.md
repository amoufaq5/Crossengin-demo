# ce_surface findings — CrossEngin language / NL / agent / chat / skills / factory / ingest / sandbox / examples

Reviewer: `ce_surface`. Scope: 120 files under 18 `src/` directories + 23 `examples/` files (143 total, ~59k LOC). All paths relative to `CE/` unless prefixed. Probe artefacts (binary, inputs, raw outputs, strace logs, reachability script) are in `$S/probes/ce_surface/`.

## Plain-language summary

The user-facing system is a **command-line REPL with about 170 slash commands plus a keyword-routed template responder**. A typed line is handled in this order: (1) a 17-word allow-list silently turns the first word into a slash command; (2) slash commands; (3) about 45 hand-written English phrase patterns ("what is X", "tell me about X", "is X a Y"…), every one of which ends in the same action — list the stored items whose name contains a word of X; (4) a keyword scorer that picks one of ten categories, each of which returns a fixed sentence template, optionally filled with a greedy walk of at most three hops over stored `A -> B` edges.

Nothing on this path generalises. A paraphrase, a synonym, a negation, or a question outside the patterns produces either "i don't know '<first unrecognised word>' yet" or an unrelated stored chain. The one thing that could be called inference is the 2–3 hop edge walk ("dog->animal->noise"), and it works as designed.

The shipped default knowledge is **42 hand-written relations** over ~540 seeded words (mostly English function words). The seven optional domain packs add 324 items + 347 relations, but they load into a side store that the reply path does not reason over.

"HDC" is real code (10,000-dimension ±1 vectors, bind/bundle/permute/cosine), but each word's vector is random from a hash of its spelling, so similarity is word-overlap only; it is used for a fallback intent classifier and a reply cache, not for meaning.

LLM use is genuinely off by default and well fenced when used for ingestion (quarantine queue). Two of the three LLM hooks (query-parse fallback and reply rewording) **do not function at all on the audited toolchain** — verified with strace. So "LLM-free" is true in practice, and "optional sidecar fallback" is currently not available.

The system cannot write or run code. It can fork three fixed shell scripts and a few audio helpers, and it **can and does fetch from the internet** (`/research`, `/define`) with no approval prompt and no TLS certificate check, turning fetched text into stored "knowledge".

"Skills", "capsules", "personas", "agents", "cowork", "MCP", "editions" are registries and record formats with careful bookkeeping but almost no behaviour behind them: three compiled-in skills (two list matching labels, one prints canned debugging tips), an MCP server that returns fixed strings, a planner that prints lines. The "mother bakes child model" factory signs a text file with real Ed25519, but the child loader does not read the knowledge section of that file.

The engineering around the edges (argv-based exec, shell quoting, snapshot name checks, signature pinning, review queue) is more careful than the grand naming would suggest; the gap is between the vocabulary (reasoning, learning, self-model, agent platform) and what is computed (counters, substring matches, templates).

## Findings table

| ID | Sev | Category | Title | File:line | Evidence | Impact | Recommended fix | Effort | Confidence |
|---|---|---|---|---|---|---|---|---|---|
| S-01 | Critical | Overstated capability | Chat replies are keyword routing + sentence templates; no generalisation | examples/crossengin_chat.nova:8020-8288; src/perception/input_classifier.nova:233-241,261-402; src/agent/cognitive_router.nova:497-796 | Category chosen by word lists and substring tests; each category returns fixed strings. Transcript T1/T2: "write me a poem about the sea" -> "thanks for sharing that with me"; Arabic input -> "help leads to response (help->response)"; "is fever good or bad?" -> "i think infection leads to headache" | The product described as a non-LLM cognitive system answers almost nothing outside its patterns; this is the central gap between claim and code | Describe it as a rule-based KG REPL; measure coverage on a held-out question set before any capability claim | L | CONFIRMED (read + executed) |
| S-02 | High | Correctness | All grammar-parsed question kinds collapse to one label-substring listing; "is X a Y" never answers yes/no | src/nl/executor.nova (nl_execute_scoped_ex: `skill_kind = 1` for RESEARCH/RELATE/CONTRADICT_SCAN/IS_A; `_er_topic_for` joins slots); src/skills/skills/research_skill.nova | T2: after teaching dog->animal, "is a dog an animal?" prints "research on 'a dog animal':" + atom list; "does X contradict Y" runs no contradiction check | The "15 canonical shapes" differ only in how the topic string is cut out | Give IS_A/RELATE/CONTRADICT real handlers (edge lookup / path search / contradiction scan already exist elsewhere) | M | CONFIRMED |
| S-03 | High | Correctness | Grammar layer shadows better handlers: arithmetic, self-identity and yes/no | examples/crossengin_chat.nova:8022-8024 (order), src/nl/grammar_parser.nova (`_try_what_is`, `_try_who_is`) | Default run: "what is 17 * 23" -> "(topic had no content words after stopword filter)"; "what is 15% of 200" -> "research on '15 of 200': (no matches)"; "who are you" -> "research on 'you'". With `CE_NL_OFF=1` the same inputs give "= 391", "= 30", and the self-model reply | The newer layer made the default experience worse than the older one | Try arithmetic + self-ID before grammar; or make grammar decline when topic is numeric / second-person | S | CONFIRMED (executed both ways) |
| S-04 | High | Correctness | Auto-prefix turns ordinary sentences into admin commands | examples/crossengin_chat.nova:3513-3554, 8020 | Any line whose first word is learn/teach/define/know/why/status/help/good/bad/cap/find/prove/explain/classify/recall/synapse/knowledge is rewritten to `/word …`. T1: "why does fever happen" -> prints the decision-log entry ("most recent: #3 speak (recoverable)…"). "good morning" runs `/good` (executed: "(no reasoning to adjust …)"); "find me a restaurant" runs `/find` | Natural "why …" questions — the core of a reasoning demo — can never reach the reasoner | Remove `why`, `good`, `bad`, `find`, `know`, `help`, `status` from the allow-list or require the whole line to match a command shape | S | CONFIRMED |
| S-05 | High | Fake result | `/vs` prints an "engine 12/12 vs LLM 9/12" scorecard from LLM verdicts generated by an if-statement | src/bench/reasoning_bench.nova:356-387; examples/crossengin_chat.nova:2755-2758, 7514; data/llm_baseline_sample.txt:1-17 | `bench_default_pairs()` sets `llm = LLM_AFFIRM` for every item except id 7; comment says "illustrative placeholders". Output (T2) is headed "head-to-head vs recorded LLM" with no caveat. The data file is likewise self-described "Illustrative … PLAUSIBLE" and only tests read it | A reader of the output would believe an LLM was measured and lost. None was | Delete `/vs` or label output "SIMULATED"; run a real model offline and commit the raw transcript with provenance | S | CONFIRMED |
| S-06 | High | Security | `/research`, `/define`, `/rss` fetch from the internet with no capability prompt and no certificate verification, then store the text as knowledge | examples/crossengin_chat.nova:7475, 7517, 7590 (no `_gate_or_prompt`; compare `/learn URL` at 7523-7525); src/learning/learn_pipeline.nova:22-28, 266-305; src/io/transducers/tls13_client.nova:14, 234 | T2: `/research fever` fetched en.wikipedia.org and added 952 atoms / 59 relations with no prompt although `autonomous_fetch` default is `require_approval`. Whitelist "admits exactly the host" being fetched | Policy bypass; any on-path attacker can inject "facts"; `CE_AUTORESEARCH=1` does this unprompted for every unknown word | Route all three through `_gate_or_prompt(CAP_AUTONOMOUS_FETCH…)`; verify certificates (x509 module is already imported) | S–M | CONFIRMED (executed; note: this probe made real GETs to wikipedia.org and dictionaryapi.dev) |
| S-07 | High | Non-functional feature | LLM sidecar parse and Ollama reply composer cannot run on the audited toolchain | src/nl/nl_llm_sidecar.nova:284-291, 425-457; src/nl/reply_composer_ollama.nova:105-112, 236-262 | strace: sidecar `pipe2(0x5a9b7931, 0) = -1 EFAULT` (inline asm passes Nova's tagged value); composer writes `/tmp/crossengin_compose_in.txt` then makes no pipe/fork/exec call. A fake script was never executed in either case | README's "optional sidecar LLM fallback" does not exist in practice; only the env-var TESTMODE path (canned wire) passes | Untag in the asm shims as `src/util/sys_tagged.nova` does; add one integration test that execs a real script | S | CONFIRMED (strace) |
| S-08 | High | Overstated capability | "Mother bakes child model": the knowledge section of a bundle is written but never loaded by the child | src/factory/bake.nova:114-116 (`#KG v1` writer); src/sandbox/session_snapshot.nova:892-900 (9 recognised markers, no `#KG`); examples/crossengin_rpc_daemon.nova:654-676 | Loader applies personas/ownership/policies/patterns/skills/agents only; `ATOM` lines after the unrecognised marker are appended to the previous section body | A "child" boots with names and policies but none of the mother's knowledge | Add a `#KG` apply step (delta apply at update_delta.nova:914 already mutates KGs) + a round-trip test asserting atom count | M | CONFIRMED by code reading; not executed |
| S-09 | Medium | Overstated capability | Domain packs are not connected to the reply path | examples/crossengin_chat.nova:1512 (`/ingest`), src/agent/cognitive_router.nova:785 (single `kg`) | After `/ingest cerec data/packs/biology.cerec …` (77 atoms added): "does photosynthesis produce oxygen" -> "i don't have a model of 'photosynthesis' yet"; "what is a mitochondrion" -> "(no matches across 6 scanned KGs)" | Shipped knowledge cannot be used to answer questions | Ingest packs into (or bridge to) the reasoning KG and word store | M | CONFIRMED (executed) |
| S-10 | Medium | Overstated capability | "Learning" from feedback changes counters, not behaviour | src/agent/cognitive_router.nova:810-846; examples/crossengin_chat.nova:7348-7386 | `fever` + `/good`×10: 3 edge beliefs 500->916, synapse mean 0->300, "ff_goodness" 1583->486000, two shortcut atoms minted; the reply to `fever` is byte-identical before and after | `/__learning__` numbers move, giving an impression of learning without an observable effect | Add a test where feedback changes which answer is chosen | M | CONFIRMED (executed) |
| S-11 | Medium | Correctness | Every unrecognised token is "learned" as a stub word, including garbage | examples/crossengin_chat.nova:2992 (`_drain_and_teach`), 8308 | "asdkfj qwerty zzzz" -> "(learned 4 new word(s) -- 606 atoms total)"; a 26-line session grew the store 584 -> 613 with no meaning attached | Atom counts are inflated; "atoms" is not a knowledge metric | Do not mint on unknown; or mark stubs and exclude from counts | S | CONFIRMED |
| S-12 | Medium | Security | Input lines longer than 1023 bytes are split and the tail is executed as a new line, including slash commands | examples/crossengin_chat.nova:685-703 (relies on std `read_line` chunking) | 1023×"a" + "/status" on one line ran `/status` | Text pasted or piped from a document can smuggle commands past the "first character is /" check (e.g. `/save PATH`, `/research`) | Reassemble until newline before dispatch; reject over-length lines whole | S | CONFIRMED (executed) |
| S-13 | Medium | Security | RPC daemon has authentication off by default; token fallback generator is weak | examples/crossengin_rpc_daemon.nova:153-159; src/sandbox/capability.nova (capability_token_id_mint: 15-bit LCG seed from `nanotime()` when `secure_random` fails; lookup via `str_eq_bytes`) | Without `CE_RPC_REQUIRE_TOKEN=1` all ~55 verbs incl. `admin.*`, `session.save`, `admin.bake_child` are open to any local process. If the CSPRNG is unavailable tokens have ≤32,767 values, silently | Local privilege boundary absent by default; guessable tokens in degraded mode | Default to enforced; fail closed if `secure_random` fails | S | CONFIRMED by reading; not executed |
| S-14 | Medium | Naming | "Capability tokens" are bearer strings in an in-memory list, not cryptographic capabilities; chat "caps" are a 9-entry allow/prompt table | src/sandbox/capability.nova:1-20; examples/crossengin_chat.nova:3599-3650 | No signature, MAC or attenuation; chat gate applied to 8 of ~170 commands (grep `_gate_or_prompt(`) | "Sandbox with capability tokens" suggests isolation that is not there: no process, filesystem or syscall confinement exists anywhere | Rename to "API tokens / approval prompts"; document that there is no sandbox | S | CONFIRMED |
| S-15 | Medium | Unreachable code | The "autonomous agent" with tools, planning and "bounded self-improvement" is not in any binary | src/agent/autonomous_loop.nova, tool_use.nova, tool_goal_plan.nova, loop_action.nova; src/parts/meta/self_improve.nova; src/parts/goals/planner.nova | Import-graph reachability: test-only (see section). `self_improve` is a tabular value-iteration agent on a toy grid | Headline P5 features exist only in unit tests | Either wire into an entry point or stop listing as shipped | M | CONFIRMED |
| S-16 | Medium | Stub | Skills / MCP / cowork are scaffolding | src/skills/skills/coding_helper.nova; examples/crossengin_mcp.nova:18-31; src/agent/cowork_planner.nova | coding_helper: 12 trigger phrases -> advice string; "write a python function to sort a list" -> "no debug pattern matched". MCP tools return fixed strings ("echo" does not echo). `/cowork plan` prints 4 lines, all "agent=? … depends_on=-" | "Agent platform" has no agent behaviour | Label as scaffolding; build one real skill end to end | L | CONFIRMED (executed) |
| S-17 | Medium | Hidden dependency | Voice path depends on whisper.cpp / vosk (pretrained neural models) via shell | examples/voice_conversation.nova:10-11, 458-459; scripts/transcribe.sh:80-113 | "no LLM in the loop" (file header) is true narrowly, but speech recognition is an external neural model | Contradicts "non-neural" framing for the voice demo | State the dependency plainly | S | CONFIRMED by reading |
| S-18 | Low | Correctness | Self-identity template is ungrammatical and ignores the name | src/parts/meta/self_model_query.nova:33-38 | "who are you" (NL off) -> "I am understand and assist; my nature is curious." | Cosmetic, but it is the first thing a visitor asks | Use soul name; "My purpose is …" | S | CONFIRMED |
| S-19 | Low | Security | Fixed predictable temp paths | src/nl/reply_composer_ollama.nova:45; examples/crossengin_chat.nova:7764 (`/tmp/crossengin.dlog`), 1700 (`/tmp/crossengin_ollama_*.cerec`); scripts/learn.sh:255 | World-writable `/tmp`, fixed names, no `O_EXCL`/`O_NOFOLLOW` | Symlink clobber on multi-user hosts | Use `$XDG_RUNTIME_DIR`/mkstemp | S | LIKELY |
| S-20 | Low | Security | Tool file "sandbox" is a string-prefix check | src/io/effectors/effector_file_ops.nova:15-36 | `/tmp/ce_tool_/../../etc/x` passes `_fo_has_prefix` | Test-only module today | Canonicalise path; reject `..` | S | CONFIRMED by reading |
| S-21 | Low | Security | Several local-file commands take arbitrary paths with no gate | examples/crossengin_chat.nova:7516 (`/fload`), 7529 (`/save`), `/persona export`, `/ingest` | `/fload /etc/passwd` -> "restored 0 formal propositions from /etc/passwd"; `/save <dir>/../snapX.snap` wrote the file | Acceptable for a local REPL operator; matters combined with S-12 | Gate writes behind the existing prompt | S | CONFIRMED (executed) |
| S-22 | Low | Docs drift | Help text advertises commands that only print a description of test-only modules | examples/crossengin_chat.nova:7636-7640 | `/nat`, `/relay`, `/relay_secure`, `/webrtc` print "ships in src/federation/…"; those modules are unreachable from any entry point | Suggests features that are not in the binary | Remove or mark "not wired" | S | CONFIRMED |
| S-23 | Low | Docs drift | Classifier threshold comment says 3000 bp, code uses 3500 | src/nl/nl_intent_classifier.nova:39 vs 317 | Runtime banner prints `threshold_bp=3500` | Minor | Fix comment | S | CONFIRMED |
| S-24 | Info | Good practice | Process spawning uses execve with argv (no shell) for the three scripts; `sh -c` users quote arguments | src/nl/ollama_spawn.nova:34-41; src/io/transducers/stt_seam.nova:470-472; src/io/effectors/audio_speak.nova:105-117 | Injection attempts `/ingest_ollama fever; touch X`, `/learn_prepare $(touch X)`, `/listen x'; touch X; '` created no files | No command injection found on these paths | — | — | CONFIRMED (executed) |
| S-25 | Info | Good practice | LLM-extracted records are quarantined; bundle verification pins an external key; snapshot names are validated | src/ingest/llm_extractor.nova; src/factory/child_mode.nova:225-245; src/nl/rpc_verbs.nova:3242-3266 | Source tag rewritten, belief capped at 800, forced to review queue; anchor key from env, not from the bundle | These parts are done properly | — | — | CONFIRMED by reading |

TODO/FIXME/HACK/XXX inventory in scope: **0** real markers (4 grep hits are the literal `\uXXXX`). "honest scope / deferred / placeholder / stub / illustrative" comments: 69 lines.

## Chat path (actual dispatch order)

Source: `examples/crossengin_chat.nova` `main()` loop at 7923-8433.

1. `_take_line()` (814): read line; cap to 64 tokens / byte limit. Lines over 1023 bytes arrive pre-split (S-12).
2. Empty / `quit` / `exit` -> leave (7935-7952).
3. `_try_auto_prefix` (8020 -> 3513): if first word is in a 17-word allow-list, prepend `/`.
4. `_try_admin` (8022 -> 7440): if line starts with `/`, linear `if` chain over ~170 command names; unknown -> "(unknown command …)". Always consumes the line.
5. `_try_nl` (8024 -> 2506), unless `CE_NL_OFF` set:
   a. `grammar_parse` (src/nl/grammar_parser.nova:1300-1433): ~45 ordered token-pattern matchers after preamble stripping. Greeting-only -> falls through.
   b. If unparsed: `nl_ic_try_classify` — bag-of-words hypervector cosine vs 10 prototypes built from an embedded phrase list (threshold 0.35).
   c. If still unparsed: LLM sidecar (off by default; non-functional, S-07).
   d. If parsed: `nl_execute` -> research skill -> `templater_render` -> prints "research on '<words>': …" (label-substring listing). Six admin-like kinds (list/install/run/retract) go to the slash handlers with a prompt.
6. Otherwise the "cognition path":
   a. Pronoun substitution: `it/they/…` -> last topic word (8033).
   b. Reader: tokenise, look each token up in the word store (exact, then lemma table/suffix strip), spread activation over stored links (8056).
   c. Bookkeeping that does not affect the reply text: moment/episode append, forward-chain into `ctx_conclusions`, two mood integers, goal arbitration, a 1-scalar predictor (8061-8098).
   d. Deny-phrase check -> "[refused]" (8111-8114).
   e. Self-identity phrase list -> one of 5 template sentences (8126-8158).
   f. `classify_input` keyword scorer -> category (8175); optional override by a per-category vector trained only by `/good` (8183-8188).
   g. Reply cache lookup keyed on bundled vectors of recognised atoms (8201-8208).
   h. `router_reply` (8210 -> cognitive_router.nova:785): per-category template; four categories try yes/no lookup or a greedy ≤3-hop edge walk; else "i don't know '<word>' yet".
   i. Optional LLM rewording (8222; off by default; non-functional).
   j. Legacy fallback "okay"/"see <topic>" (8250-8287) — unreachable in practice because `router_reply` always returns a non-empty string.
7. Post-turn: optional autonomous internet research (`CE_AUTORESEARCH=1`, 8305), stub-mint unknown words (8308), print reply + `perceive(m,unk)` + `reasoning:` trace.

**Share of the path that is keyword/regex/template matching:** all reply selection. The only steps that compute something not literally stored are (i) the greedy edge walk of depth ≤3, (ii) the arithmetic evaluator, (iii) suffix-stripping lemma lookup. There is no variable binding, no unification on this path (the proof kernel is reachable only through explicit `/axiom`, `/derive`, `/syllogism` commands with hand-supplied labels), no semantic similarity, no negation ("not" is an unknown word: "fever is not real" -> "'not' is new to me").

**Reply to a sentence outside its patterns:** if any token is unrecognised: "i don't know '<first unrecognised non-stopword>' yet -- i'll look into it." (and it mints stub atoms). If all tokens are recognised: whatever ≤3-hop chain starts at any recognised word, or "i hear you -- could you say a bit more…". If the sentence contains "i/me/my": "thanks for sharing that with me -- i'll keep it in mind."

## Transcript

Binary built with `$S/NOVA/nova build examples/crossengin_chat.nova -o $S/probes/ce_surface/chat` (40 s, 4.7 MB). Run with `HOME` and `CE_DLOG_PATH` pointed at the probe directory, `timeout 60`. Verbatim, trimmed (long atom listings cut with `…`). Full outputs: `$S/probes/ce_surface/out1.txt`, `out2.txt`.

### T1 — default configuration

```
(seed: 584 atoms, Aurora ready)
> hello
agent> hello! what would you like to explore?
       reasoning: social: greeting (no KG write)
> who are you
agent> research on 'you':
  [reasoning] you belief=500
  [reasoning] young belief=500
  [reasoning] you=>user belief=500 …
Confidence: 500/1000  |  parser: grammar  |  style: default
> what is a dog
agent> research on 'a dog':
  (no matches across 4 scanned KGs)
> fever
agent> infection leads to headache (infection->symptom->fever->headache).
       perceive(m=1,unk=0)
       reasoning: unknown: forward-chain infection->symptom->fever->headache
> why does fever happen
most recent: #3 speak (recoverable)
  tier    : notify
  outcome : ok
  trace   : 0 node(s)
  sources : prior knowledge
> /teach dog
(ingested 'dog' -- 585 atoms now)
> /learn dog is an animal
(no cache for 'dog is an animal' [topic] at /tmp/crossengin_learn_dog is an animal.txt)
  run first:  scripts/learn.sh dog is an animal
> is a dog an animal
agent> research on 'a dog animal':
  [reasoning] dog belief=800
  [language] dog belief=500
⚠ Sources disagree on 'dog' (spread 300 milli, 2 sources). …
> does dog lead to noise
agent> i don't know 'lead' yet -- i'll look into it.
       (learned 4 new word(s) -- 589 atoms total)
> tell me about dogs
agent> research on 'dogs':
  (no matches across 4 scanned KGs)
> a canine is a creature, right?
agent> research on 'a canine creature right':
  [reasoning] right belief=500 …
> what is 17 * 23
agent> (topic had no content words after stopword filter)
Confidence: 0/1000  |  parser: grammar  |  style: default
> what is seventeen times twenty three
agent> research on 'seventeen times twenty three':
  [reasoning] three belief=500
  [reasoning] twenty belief=500 …
> if I have 3 apples and eat one how many remain
agent> noted -- 'apples' is new to me. teach me with /learn so it sticks.
       reasoning: factual: assertion with new term (queued to learn)
> what is the capital of France
agent> research on 'the capital of france':
  (no matches across 4 scanned KGs)
> write me a poem about the sea
agent> thanks for sharing that with me -- i'll keep it in mind.
       reasoning: personal: acknowledged (episodic, not asserted as fact)
> ما هي الحمى
agent> help leads to response (help->response).
       perceive(m=0,unk=3)
       reasoning: unknown: forward-chain help->response
       (learned 3 new word(s) -- 602 atoms total)
> asdkfj qwerty zzzz !!!! ####
agent> i don't know 'asdkfj' yet -- i'll look into it.
       (learned 4 new word(s) -- 606 atoms total)
> I feel sad today
agent> i'm sorry you're feeling sad. i'm here if you want to talk about it.
> is democracy better than monarchy
agent> that's a matter of judgement -- both 'democracy' and 'monarchy' have a case, and which wins depends on what you value most. i can lay out considerations for each, but i won't assert one as the truth.
> how do i bake bread
agent> i don't have a stored procedure for 'bake' yet -- teach me the steps with /learn and i'll remember them.
> what can you do
agent> I have no calibrated competences yet -- I'm still learning what I can do.
> /status
soul     : Aurora (purpose: understand and assist)
mood     : valence=856 arousal=473
knowledge: 613 atoms in shared KG, 0 tentative reflections
```

### T2 — teaching a fact properly (`/teach` + `/correct`), 2-hop, arithmetic, CI sequence, commands

```
> /teach dog      -> (ingested 'dog' -- 585 atoms now)
> /teach animal   -> (ingested 'animal' -- 586 atoms now)
> /teach noise    -> (ingested 'noise' -- 587 atoms now)
> /correct dog is animal        -> got it -- learned 'dog is animal' and adjusted my earlier reasoning.
> /correct animal causes noise  -> got it -- learned 'animal causes noise' and adjusted my earlier reasoning.
> dog
agent> dog leads to noise (dog->animal->noise).
       reasoning: unknown: forward-chain dog->animal->noise
> is dog an animal?
agent> research on 'dog animal':
  [reasoning] dog belief=800
  [reasoning] animal belief=800
  [reasoning] correct:dog-is->animal belief=500 …          (no "yes")
> does dog cause noise?
agent> i think dog leads to noise (dog->animal->noise).
       reasoning: academic: forward-chain dog->animal->noise [conf=500]
> are dogs animals
agent> dog leads to noise (dog->animal->noise).                (plural matched; question not answered)
> canines belong to the animal kingdom
agent> i don't know 'canines' yet -- i'll look into it.
> 17 * 23
agent> = 391
> what is 15% of 200
agent> research on '15 of 200':
  (no matches across 4 scanned KGs)
> two plus two
agent> i don't know 'plus' yet -- i'll look into it.
> who made you
agent> i don't know 'made' yet -- i'll look into it.
> what is your name
agent> research on 'your name':
  [reasoning] name belief=500 …
> fever
agent> infection leads to headache (infection->symptom->fever->headache).
> /good   (×10)   -> thanks -- reinforced 3 inference(s).   (each time)
> /__learning__
synapse_live=12  synapse_total=12  synapse_mean_weight=250  ff_goodness=486000
mc_entries=11  mc_hits=0  mc_misses=11  ia_proto_strength_unknown=10  dlog_entries=25  tick=11
> fever
agent> infection leads to headache (infection->symptom->fever->headache).       (unchanged)
> /learn ../../etc/passwd
(no cache for '../../etc/passwd' [file] at /tmp/crossengin_learn_passwd.txt)        (basename sanitised)
> /fload /etc/passwd
(re-verified + restored 0 formal propositions from /etc/passwd)
> /skill list
  echo v1.0.0 (uninstalled)   research v1.0.0 (installed)   coding_helper v1.0.0 (uninstalled)
> /mcp list
mcp_services_registered=0
> /cap list
  read_kb … default=allow   autonomous_fetch … default=require_approval   … delete … default=require_approval
> /research fever
(search resolved 'fever' -> https://en.wikipedia.org/wiki/Fever)
(  en.wikipedia/search: 989 word(s), 59 operator(s), 952 new atom(s))
(genus: fever -> temperature)
(+ dictionary: 6 definition(s), 26 word(s), 7 operator(s))
(autonomously learned about 'fever' [best source: en.wikipedia/search, 59 operator(s)]; KG=1636)     (no approval prompt)
> /define dog
(defining 'dog' -> https://api.dictionaryapi.dev/api/v2/entries/en/dog ...)
(genus: dog -> mammal)   (learned 143 word(s), 7 operator(s) from 28 definition(s) of 'dog')
> /ingest_ollama fever; touch …/PWNED
error: input file not found: fever; touch …/PWNED          (no file created: argv exec, no shell)
> /learn_prepare $(touch …/PWNED2)
agent> would like to fetch topic via scripts/learn.sh: $(touch …/PWNED2). approve? [y/N/why]
agent> declined (fetch topic via scripts/learn.sh).
> /vs
head-to-head vs recorded LLM (ADR-0086 Phase 7):
  items: 12   engine correct: 12 / 12   engine false proofs: 0
  LLM correct: 9 / 12 (acc 750 milli)   LLM false-confident: 3 (affirmed an unprovable claim)
> <one 18,000-byte line of "fever fever …">
(warning: input line over 64 tokens; kept first 64)      ×16 — processed as 16 separate inputs
```

### T3 — variants

```
CE_NL_OFF=1:
> who are you            -> I am understand and assist; my nature is curious.
> what are your goals    -> I am pursuing: assist the user.
> how do you feel        -> My state: valence 856, arousal 473, energy 1000 (milli).
> what is 17 * 23        -> = 391
> what is 15% of 200     -> = 30
> why does the sun rise  -> most recent: #13 speak (recoverable) …     (auto-prefixed to /why)
> fever is not real      -> noted -- 'not' is new to me. teach me with /learn so it sticks.
> is fever good or bad?  -> i think infection leads to headache (infection->symptom->fever->headache).

After /ingest cerec data/packs/biology.cerec biology src:pack:biology:v1  ("77 atoms added"):
> is a human a mammal                  -> research on 'a human mammal': [biology] human belief=1000 … (list, no yes)
> does photosynthesis produce oxygen   -> i don't have a model of 'photosynthesis' yet -- want me to /learn it?

/skill install coding_helper; /skill run coding_helper my loop hangs with a null pointer
  -> "1. NULL deref: check whether the caller initialises the value only on a success branch…  [confidence 800/1000; src:pattern:debug_common:v1]"
/skill run coding_helper write a python function to sort a list
  -> "(no debug pattern matched your problem description)"
/cowork plan research fever then write a clinical report and review code security
  -> cowork_tasks=4;  step_1 domain=clinical trigger="clinical" agent=? … depends_on=-   (4 such lines)
/mcp register weather sunny-25C; /mcp call weather   -> ok=1  bytes=9  body="sunny-25C"
```

**Characterisation.** It greets, does integer arithmetic when the line is bare, echoes a named feeling, hedges on "X better than Y", and walks stored edges two or three hops from a recognised word. It cannot answer a yes/no question about a fact it was just taught, recognise a paraphrase or synonym, handle negation, count, or respond sensibly to anything open-ended. Replies are internally labelled "reasoning: …" even for canned social lines.

## LLM touchpoints

| # | Where | Trigger | Default | What goes to the LLM | What comes back and how it is presented | Works on audited toolchain? |
|---|---|---|---|---|---|---|
| 1 | src/nl/nl_llm_sidecar.nova -> scripts/nl_parse_llm.sh (backends: `ollama run`, llama.cpp, OpenAI-compatible `curl` with `$OPENAI_API_KEY`) | grammar + prototype classifier both fail, and `CROSSENGIN_NL_LLM_ENABLED=1` | Off | Raw user text | `KIND/ARG` lines -> same research listing; trailer shows `parser: llm` (disclosed) | **No** — `pipe2` EFAULT (strace). TESTMODE env returns a canned wire and does work |
| 2 | src/nl/reply_composer_ollama.nova -> scripts/llm_compose.sh | every router reply when `CE_OLLAMA_COMPOSER=1` | Off | Templated reply + atom labels | One line that **replaces** the reply after `agent>` with no marker; `reasoning:` trace unchanged; cached | **No** — never forks (strace) |
| 3 | examples/crossengin_chat.nova:1688 `/ingest_ollama` -> scripts/llm_extract.sh | explicit command | n/a | A local file's text | `.cerec` triples -> review queue, source `src:extractor:llm:<model>:<run>`, belief ≤800 (disclosed, quarantined) | Yes (script ran; failed only because input file absent) |
| 4 | `/ingest_llm PATH MODEL RUN` (src/ingest/llm_extractor.nova) | explicit command | n/a | — (reads a pre-made file) | Same quarantine | Yes |
| 5 | scripts/transcribe.sh (whisper.cpp / vosk) via src/io/transducers/stt_seam.nova | `/listen`, `/converse`, `/dialog` | Falls back to "[stt unavailable]" | WAV | Transcript used as the user's text | Not an LLM, but a pretrained neural model; stub path observed |

Is it off by default? Yes for all. Capability with LLM off vs on: on this toolchain identical (hooks 1–2 inert). If repaired: hook 1 would only widen which sentences map onto the same 11 query kinds — the answer would still be the substring listing; hook 2 would make template sentences read fluently, which would be **LLM prose presented as the engine's own voice** under a "reasoning:" label. That is the one place output from an LLM would be passed off as CrossEngin's (SUSPECTED as a risk; not observable today).

No Python sidecar, embedding file, or neural library is used by the chat binary (`grep` for torch/numpy/onnx in scope: none). `scripts/web.py`, `rpc_web_shim.py` are HTTP shims outside my scope.

## HDC (question 3)

Real implementation: `src/kg/hdc_embed.nova` — `HDC_DIMS = 10000` (51), ±1 vectors from FNV-1a(label) seeding a 31-bit LCG (74-104), `hdc_bind` = elementwise product (247), `hdc_bundle` = majority sign (268), `hdc_permute` = cyclic shift (299), `hdc_cosine` integer milli (320). Vectors are Nova lists of 10,000 tagged ints (80 KB per symbol).

Because a symbol's vector depends only on its spelling, any two different words are ~orthogonal: "dog" and "canine" have cosine ≈ 0. Bundles therefore measure shared-token overlap. `hdc_bind` and `hdc_permute` have no caller anywhere in `src/` or `examples/` outside `hdc_embed.nova` itself (grep) — the rest of the system uses only `hdc_symbol`, `hdc_bundle`, `hdc_cosine`, i.e. bag-of-words.

Live-path uses: (a) fallback intent classifier (src/nl/nl_intent_classifier.nova), (b) `/good`-trained category prototypes (src/nl/intent_adaptive.nova), (c) reply cache key (examples/crossengin_chat.nova:277-300, 8201-8229), (d) word-atom embed field (`atom_set_embed_mode(ATOM_EMBED_MODE_HDC)`, 7748) feeding `/find`/`/ann_query`. None of these affects which fact is retrieved for a question. CONFIRMED.

## Reader / language / grammar (question 4)

- **Reader "five stages"** (src/reader): tokenise + dictionary lookup -> pick a sense by vector centroid -> bounded spreading activation over stored links -> edge-density "coherence" number -> set a route name / learn flag. Its product on the chat path is the list of recognised atom ids (`percept`) and two counts `m`/`unk`. Real, small, deterministic. `neighborhood.nova` adds neighbour scoring from five counters. No parsing of sentence structure.
- **Language**: word store with lemma fallback (≈100 irregular forms + suffix rules, word_atoms.nova), phoneme and syntax atoms (records), a number-word reader, a competent small arithmetic evaluator, an a/an + pluralise sentence renderer, and `nl_query` (keyword question classifier + strongest-edge lookup) which is the nearest thing to question answering but is only consulted for yes/no and how-many forms after the grammar layer has declined — which for "is X a Y" it never does (S-02/S-03).
- **Anaphora**: replace any of a fixed pronoun list with the previous turn's first content word (src/chat/helpers.nova:659-690).
- **Grammar parser**: ordered list of literal English token sequences. Hand-coded English throughout: stopword lists (4 separate copies: cognitive_router.nova:355, echo_skill, research_skill, pattern_capsule), category word lists (input_classifier.nova:233-241), feeling lists (cognitive_router.nova:431-432), preamble list, irregular-form table. English only; non-Latin text becomes unknown tokens (Arabic probe: `perceive(m=0,unk=3)`).

## Agent loops, goals, self-model, reflection, self-improvement (question 5)

| Name | What it computes | Reachable? |
|---|---|---|
| Six loops (src/agent/loop_*.nova) | perception = run reader; memory = append record; reasoning = depth-3 forward chain into a list; emotion = two integers from `matched*300 - unk*150`; goals = pick highest-priority goal id; action = choose 1 of 3 canned templates | First five run each chat turn; only perception's output reaches the reply. `loop_action` is test-only |
| Imagination idle loop | 3-step forward simulation when idle flag set | Chat never sets idle |
| Self-model | `selfmodel_identity/state/goals` string templates over soul fields; "competence records" list (0 entries in every run) | Yes, but shadowed by grammar in default config |
| `/reflect` | forward-simulate from last conclusions into a side KG | Yes ("nothing recent to reflect on" in probe) |
| Planner / tool use / goal->plan | hand-built step lists executed against arithmetic, prefix-checked file I/O, simulated HTTP, canned MCP | Test-only |
| Bounded self-improvement (P5) | tabular value iteration on a toy grid; "self-edit" = write a best-action entry after a deny-list check and a log append | Test-only (`src/parts/meta/self_improve.nova`, `src/agent/autonomous_loop.nova`) |

## Self-modification / code execution surface

**Can it write or execute code?** No. There is no code generator, interpreter, `eval`, dynamic loader or compiler invocation anywhere in scope. "effector_code_exec" is the arithmetic evaluator (src/io/effectors/effector_code_exec.nova:15-19). "Skills" are three functions compiled into the binary selected by integer id; installing a skill flips a flag. `coding_helper` prints advice strings and lists "proposed effector calls (NOT executed by runtime)".

**Can it modify itself?** Only its data: atom/edge beliefs, edge weights, minted stub words, "compiled" shortcut edges (`cc:A->C [via B]`), persona fields, registries, snapshots. Nothing alters program text or control flow. "ACT_SELF_MODIFY" labels KG writes.

**Can it fork processes?** Yes, fixed targets only:

| Target | Call site | How | User-controlled input |
|---|---|---|---|
| scripts/llm_extract.sh | chat `/ingest_ollama` (1688-1735) | execve argv | file path as one argv element |
| scripts/learn.sh | chat `/learn_prepare` (1632-1661), behind y/N prompt | execve argv | topic as one argv element; script puts it into a `curl` URL and a `/tmp/crossengin_learn_<topic>.txt` filename (learn.sh:251-255 — topic not sanitised in the script's own path; LIKELY path-shaping issue when run directly) |
| scripts/nl_parse_llm.sh, scripts/llm_compose.sh | LLM hooks | execve argv; **script path itself comes from env** (`CROSSENGIN_NL_LLM_SCRIPT`, `CE_REPLY_COMPOSER_SCRIPT`) | inert today |
| `/bin/sh -c "bash scripts/transcribe.sh '<path>'"`, `aplay`/`paplay`/`arecord` | `/listen`, `/speak`, `/say`, `/converse` (src/io) | sh -c with single-quote escaping | path / text, quoted |

Injection attempts on all three reachable paths failed (S-24).

**Can it fetch from the internet?** Yes, in-process (own DNS-over-UDP, HTTP/1.1 and TLS 1.3 client, no certificate verification): `/learn http(s)://…` (prompted), `/research TOPIC`, `/define WORD`, `/rss URL` (not prompted, S-06), and automatically for unknown words when `CE_AUTORESEARCH=1` / `CE_AUTODEFINE=1`. Hosts actually contacted in the probe: en.wikipedia.org, api.dictionaryapi.dev. Fetched HTML is stripped, split into sentences, and surface patterns ("X is a Y", "X causes Y") become stored edges with a `src:` tag. Also opens sockets for federation commands (`/fed_join` prompted; `/gossip_start` not).

**What contains it?** Mechanically:
- *"Sandbox"* = no OS-level confinement of any kind (no chroot, namespaces, seccomp, rlimits, uid change). The word refers to (a) the RPC token table, (b) the chat approval prompt, (c) a `/tmp/ce_tool_` string-prefix check in a test-only module.
- *Chat capability gate* (`_gate_or_prompt`, 3599): 9 named permissions with allow / deny / ask-y/N, overridable from `~/.crossengin/caps.conf`; applied to `/teach`, `/learn URL`, `/load`, `/retract`, `/fed_join`, `/learn_prepare`, `/ingest_ollama` and four NL-triggered actions. Every other command is ungated. Decisions are appended to the decision log ("attestation").
- *"Capability tokens"* = random 128-bit hex bearer ids held in an in-memory list with a permission-string set; no cryptography beyond the RNG. Off by default.
- *Constitution* = deny-phrase substring/concept match -> "[refused]".
- *Decision log* = append-only list chained by a polynomial rolling hash, self-described as not cryptographic (src/audit/decision_log.nova:155-163).
- *Child mode* = a table of RPC verbs to refuse + env flag making the chat gate deny non-read permissions.

Net: the system is contained mainly by having very little it can do, not by an enforcement boundary.

## Factory (question 6)

A child bundle is a text file: header lines (name, version, domain, baked-at, mother fingerprint), then `#PERSONA`, `#OWNERSHIP`, `#POLICY`, `#PATTERN`, `#SKILL`, `#AGENT` sections (registry dumps filtered by a manifest allow-list), a `#KG v1` section (`ATOM <kg> <id> <kind> <license> <tier> <label>` + `XREF` lines for atoms passing a capsule/prefix/license filter), then `#SIGNATURE <hex>` and `#SIGNER-PK <hex>`. Signing is Ed25519 over the prefix bytes via `src/persistence/bundle_signing.nova` (crypto correctness is another reviewer's area); verification uses a key pinned by env (`CROSSENGIN_MOTHER_ANCHOR_PK_B64`, `CE_AGENT_VERIFY_PUBKEY_HEX`), not the embedded one — correct design. There are no weights or parameters: "model" = this text file. The child loader ignores `#KG` (S-08). `docs/samples` bundle is produced by `scripts/bake_sample.sh` with openssl and hand-typed sections, not by `bake_child`. Deltas (`update_delta.nova`) are signed, chained, and do apply `+ATOM/-ATOM`.

## Skills / capsules / persona / sessions / editions / MCP / cowork (question 7)

| Feature | Real? | Reachable from |
|---|---|---|
| Skill registry/supervisor/dispatch | Real bookkeeping; 3 compiled-in policies | chat `/skill`, RPC `skill.*`, every grammar-parsed question (research) |
| Capsules (atom membership sets, semver deps, toposort) | Real bookkeeping; none shipped installed ("no capsules registered yet") | chat `/capsule`, RPC |
| Pattern capsules | Two built-in trigger->advice tables + loader | coding_helper, RPC `pattern.*` |
| Style capsules | Wording knobs for the templater | templater |
| Persona | Record + export/import + advisory token-overlap "projection"; does not change replies | chat `/persona`, RPC |
| Sessions | Real: multiple independent state bundles, `/switch` | chat, daemon |
| Editions | Static boolean matrix | **tests only** |
| MCP | Stdio JSON-RPC server returning fixed strings; in-chat registry of name->string | `crossengin_mcp` binary; chat `/mcp` |
| Cowork | Keyword -> printed line | chat `/cowork plan` |
| Agents (manifest/registry/run) | List of skills tried in order | RPC `agent.*`; chat `/agent` only lists/verifies bundle files |
| Capability tokens / ownership / holder rate | Real bookkeeping | RPC daemon when enforcement env set |

## Ingest and shipped knowledge (question 8)

Knowledge enters by: (1) hand-written seed in `src/seed/first_atoms.nova`; (2) operator commands `/teach`, `/correct`, `/pin`, formal `/axiom…`; (3) file importers — `.cerec`, CSV, JSON, YAML, N-Triples, Wikidata-flavoured NT, ConceptNet TSV, a simplified WordNet-like format, paper TSV, and header-only image/audio/video metadata; (4) web fetch + sentence-pattern mining; (5) dictionary JSON API; (6) LLM-extracted `.cerec` (quarantined). No ConceptNet/Wikidata/WordNet data is shipped — only the parsers.

Counts (CONFIRMED by `/__atoms__` and grep):
- Default chat boot: 584 atoms in the reasoning KG = 542 concept atoms (largely function words: self, user, i, you, is, are, what, why…) + **42 relation atoms** (e.g. `virus->infection`, `symptom->fever`, `sleep->dream`, `exfiltrate->leak`); plus 416 language word atoms.
- `data/packs/*.cerec` (7 packs, not loaded by default): **324 ATOM + 347 IMP + 24 OBS** lines; largest biology 77/90. Authorship is hand/assistant-written prose with textbook citations in comments; no evidence either way of LLM generation (not determinable from the files).
- `src/seed/packs/` 4 code packs (medical, logic, code_review, ops_runbook) loadable via `/seed` — outside my directories.
- `data/nl_intent/prototypes.txt` 164 lines of hand-written phrases for 10 intents; `data/patterns/security_review.cerec` 132 lines of trigger->advice.

## Security notes (question 9)

Covered in S-06, S-12, S-13, S-14, S-19, S-20, S-21, S-24, S-25. Additional observations:
- Untrusted text parsing: line caps (64 tokens, per-token byte clip) are enforced (814-838); the JSON, YAML, .cerec and NT parsers are hand-written cursor parsers over Nova strings (bounds-checked by the runtime; memory safety depends on Nova, another reviewer's area). Not fuzzed here.
- Path traversal: learn-cache tags are basename + `[A-Za-z0-9_-]` (helpers.nova `_learn_tag*`); RPC snapshot names reject `/`, `\`, `.`, `..` (rpc_verbs.nova:3242-3266); RPC `ingest.file` takes a body, not a path. Chat file commands take raw paths by design.
- MCP tool policy: per-tool `allow|deny|ask` string and a field allow-list stored beside canned responses; since tools only return stored strings, the policy protects nothing substantive.
- RPC daemon: loopback bind by default, one request per connection, 64 KB cap; optional TLS server from env-supplied key material.
- Env-controlled script paths (`CROSSENGIN_NL_LLM_SCRIPT`, `CE_REPLY_COMPOSER_SCRIPT`) and cwd-relative `scripts/*.sh`: whoever controls the environment or working directory controls what is executed. Normal for a dev tool; unsuitable for a daemon.

## Reachability from entry points

Method: `$S/probes/ce_surface/reach.py` — transitive closure of `import "…"` statements (relative paths resolved, `std/` ignored) starting from each `examples/*.nova`, over all `src/**/*.nova`. File-level only: a reachable file can still contain functions nothing calls. No unresolved imports.

- `src/**/*.nova`: **397 files, 187,870 LOC**.
- Reachable from at least one example: **341 files, 166,784 LOC**.
- **Unreachable from every example: 56 files, 21,086 LOC (11%)** — all 56 are imported by tests, none is imported by nothing.
- Per entry point (src files reached): crossengin_chat 308; crossengin_daemon 129; crossengin_rpc_daemon 125; crossengin_fed_daemon 51; migrate_snap / migrate_schema / episodic_demo / episodic_legacy_load 45; companion_spine 33; crossengin_fed_coordinator 22; voice_conversation / voice_dialog 21; kg_publisher / kg_subscriber 14; kernel_selfcheck 13; semantic_search_demo / graph_clustering_demo 9; snap_keygen / episodic_recall_demo 7; three bench_* 5; **crossengin_mcp 3**.

Unreachable (test-only) modules, with LOC:

```
src/agent/autonomous_loop.nova 616          src/agent/loop_action.nova 152
src/agent/tool_goal_plan.nova 192           src/agent/tool_use.nova 247
src/audit/audit_reader.nova 71              src/bench/bench_bank_ext.nova 183
src/bench/calibration.nova 146              src/data/pdf_text.nova 292
src/data/table.nova 318                     src/editions/edition_gate.nova 155
src/federation/gossip_relay_secure.nova 965 src/federation/ice.nova 436
src/federation/ice_turn.nova 717            src/federation/nat_traversal.nova 1475
src/federation/raft_cluster.nova 181        src/federation/raft_core.nova 216
src/federation/raft_membership.nova 106     src/federation/raft_partition.nova 114
src/federation/srtp.nova 998                src/federation/stun_rfc8489.nova 1300
src/federation/turn.nova 2768               src/federation/turn_server.nova 1289
src/federation/webrtc.nova 649              src/ingest/web_scheduler.nova 231
src/io/effectors/effector_code_exec.nova 20 src/io/effectors/effector_file_ops.nova 40
src/io/effectors/effector_http_action.nova 65  src/io/transducers/stream_audio.nova 394
src/kg/schemas.nova 226                     src/learning/atom_birth_monitor.nova 125
src/learning/bayesian_updates.nova 119      src/learning/confidence_thresholds.nova 98
src/learning/learning_policy.nova 120       src/mind/search_uni.nova 84
src/mind/unify.nova 133                     src/net/tls/tls_state.nova 212
src/parts/action/action_atoms.nova 534      src/parts/action/action_module.nova 686
src/parts/action/goal_templates.nova 237    src/parts/action/motor_map.nova 255
src/parts/action/operand_builder.nova 174   src/parts/episodic/consolidation.nova 137
src/parts/goals/goal_persistence.nova 105   src/parts/goals/planner.nova 169
src/parts/imagination/counterfactual.nova 61   src/parts/imagination/dream_recombination.nova 46
src/parts/imagination/scenario_planner.nova 79 src/parts/meta/long_horizon_goals.nova 82
src/parts/meta/self_improve.nova 422        src/parts/meta/theory_of_mind.nova 100
src/parts/soul/goals_in_soul.nova 55        src/parts/soul/values.nova 51
src/persistence/chat_state.nova 1232        src/safety/md5.nova 538
src/safety/sha1.nova 511                    src/sim/world_model.nova 159
```

Reading of the list: the whole **action module** (action atoms, motor map, tool use, planner, goal->plan), the **autonomous/self-improving agent**, **theory of mind**, **counterfactual / dream / scenario imagination**, **values**, **unification-based proof search** (`mind/unify`, `search_uni`), **Raft**, and the **WebRTC/ICE/STUN/TURN/SRTP/NAT stack (~10.9k LOC)** exist only under unit tests. Chat commands `/nat`, `/relay`, `/relay_secure`, `/webrtc` print text describing some of them (S-22).

Not counted above but effectively dead inside reachable files: the legacy "okay / see <topic>" fallback (crossengin_chat.nova:8250-8287) and `loop_imagination_step` on the chat path.

## Could not verify

- Behaviour of the LLM hooks with a real Ollama (none installed; and hooks are inert here regardless). Whether they work on the founder's own Nova build is unknown — the failure is in how inline asm reads a tagged argument, so it should reproduce on any build of this Nova checkout.
- S-08 was established by reading the loader, not by baking and booting a child.
- RPC daemon, fed daemons, kg publisher/subscriber, MCP binary were read, not run.
- Crypto primitive correctness (Ed25519, TLS) and Nova runtime memory safety are outside this scope.
- `rpc_verbs.nova` (5.3k LOC) was skimmed: dispatch table, ingest.file, session name validation, token plumbing only.
