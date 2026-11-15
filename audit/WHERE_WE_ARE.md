# Where we are

*A plain-language account for the founder. Audit date: 15 November 2026. Everything here is backed by file and line references in `MSC_DUE_DILIGENCE_REPORT.md`; the labels CONFIRMED / LIKELY / SUSPECTED are used there.*

**One caveat first.** The "founder's statement of the original vision" in the audit brief was left as the unfilled placeholder, and there is no `/vision` folder. The "original vision" below is therefore reconstructed from the earliest commits and documents. If your own memory of the goal differs, send it and the drift table should be redone against it.

---

## 1. What this project actually is today

You have two things. **NOVA** is a small programming language whose compiler is written in itself and really does rebuild itself byte-for-byte; it turns programs into Linux machine code with no outside libraries. **CrossEngin** is a very large program written in NOVA (about 190,000 lines) whose working core is a **notebook of facts with confidence scores**: each fact remembers where it came from, how many times it was supported or contradicted, and facts of the form "A leads to B" can be chained up to three steps to answer a question. You talk to it through a command prompt with about 170 slash-commands; ordinary sentences are matched against lists of English keywords and answered from fill-in-the-blank templates. Around that core sit a great many well-made but mostly disconnected parts — a simulated network of spiking "neurons", image and audio decoders, encrypted networking, a federation layer — which are tested on their own but do not take part in producing answers.

It is not, today, a new computing paradigm and it is not on a measurable path to general intelligence. It is a real self-hosting compiler plus a hand-built, inspectable knowledge-base engine, wrapped in far more scaffolding than either needs.

---

## 2. Original vision vs. current reality

| | What was said at the start | What exists now |
|---|---|---|
| **The language** | 15 May: a language "for AI/AGI" with tensors, automatic differentiation, an ownership model and a type system. 16 May: rewritten as a "cognitive architecture language" where the compiler knows the whole signal graph and optimises across it. | A dynamically typed scripting-style language compiled to x86-64. No type checking, no ownership model, no tensors in the core. The compiler does not know about any signal graph; the `mind` / `soul` / `~>` syntax is shorthand for ordinary function calls. |
| **Self-hosting** | Compiler written in NOVA, bootstrapped from hand-written assembly. | True that it is written in NOVA and reproduces itself exactly. The hand-written assembly was replaced in May by a 106,000-line machine-generated file, so the project can no longer be rebuilt from human-written source alone. |
| **Moment-Signal Computing** | "Cognition emerges from signals flowing through specialised processing nodes." Moments are structured experiences; signals carry them between perceiver, knower, rememberer, reasoner, feeler and actor nodes. | Three different things have carried this name (see §5). The one the system actually runs on is: a fact store where each fact has two counters (supported / contradicted) and a source label. |
| **No LLMs, no deep learning** | Explicitly non-LLM, non-transformer. Early CrossEngin rules rejected even "LLM polish". | Holds for the default path: no neural network runs when you type a question. But speech recognition calls Whisper or Vosk (both neural networks), and there are opt-in scripts that use Ollama or an OpenAI-style API to extract facts and to rewrite replies. Two of the three LLM hooks are currently broken, which is why the default stays clean. |
| **A fabric of ~6 million uniform units** | "~6M-node fabric on a tick-driven core." | The chat program creates 64 nodes. They tick once per message and nothing reads their state to decide the reply. |
| **Continuous learning** | Learns from experience; "gets faster the more it's used". | It stores new words and facts you teach it with specific commands, and it nudges counters when you type `/good` or `/bad`. A plain sentence such as "cats are mammals" is not stored. No test shows any ability improving with experience. |
| **AGI-relevant capability** | Theory of mind, self-awareness, counterfactual reasoning, long-horizon goals. | The modules with those names are small bookkeeping routines, and most are only reachable from their own unit tests. The project's own roadmap document says "It does not claim AGI… unproven… research wager". |
| **Evidence** | An 18–30-month plan with capability tests as exit gates. | "All 10 phases" were committed in two days. No capability test was ever run. There is no benchmark comparing the system with any baseline. |

---

## 3. Drift timeline

Almost every commit (1,027 of 1,078) was written by an AI coding agent; your account appears on merges. The pattern below is what tends to happen when an agent is asked to "continue" without a fixed target: each session finishes something, lists what is still missing, and the next session builds the missing things. That loop produces breadth very quickly and never returns to the central question.

| When | What happened | Evidence |
|---|---|---|
| **15 May** | NOVA starts as a Python interpreter for a tensor/autograd language "for AI/AGI". | `NOVA 81868c7` |
| **16 May, morning** | Redesigned as a "causal-first" language (causal graphs, do-calculus). | `d93d22c`, `08d60f4` |
| **16 May, afternoon** | Rewritten as a "cognitive architecture language for non-LLM agents". 14,000 lines deleted. | `dfa5a2f` |
| **16 May, evening** | "Moment-Signal Computing" appears for the first time, in a README performance section. Hand-written assembly bootstrap begins. | `95270d9`, `b95014c` |
| **17–19 May** | The compiler becomes self-hosting. The MSC "core" and "mind" libraries are written. **These are the last days anyone works on MSC inside NOVA** (16 commits in total, none after May). | `1ca6462`, `b6c5317`, `c17f938` |
| **20–25 May** | Language features pile up. An LLM bridge (llama.cpp), RAG, OpenBLAS and a Python bridge are added to the "non-LLM" language. | `0990d42`, `438e798` |
| **22 May** | CrossEngin starts as a *different* plan: Python + PyTorch + LoRA, with a note that NOVA is "explicitly not used". | `CE 9a4a092` |
| **24–26 May** | Pivot to "NOVA-first, no-LLM substrate". All design records deleted and rewritten in 20 minutes. All ten phases of an 18–30-month plan committed in two days; "v1.0" declared. | `e2c5cd7`, `19c1fe7`, `f5adfd3`, `671074f` |
| **29 May – 5 June** | The breadth sprint. JPEG and PNG decoders, feature detectors, audio processing, DTLS, TURN, SRTP, Raft, secure aggregation. About 100,000 lines of source in eight days, 61 commits on 3 June alone. In NOVA, the same week produces 68,000 lines of Python editor tooling. | CE `src/io` 96.6% landed 29 May–3 June |
| **6–22 June** | Language understanding and formal-logic work in CrossEngin. NOVA undergoes a risky change to how numbers are stored ("tagging"), merged with 13 known failures. | NOVA `9dc758e`…`74f1365` |
| **1–26 August** | The natural-language layer and "sandbox" grow. **3 August: the architecture is named "Moment-Signal Cognition" in a document that states "Zero code changes".** 22 August: reframed as an "AI Factory" where a "mother model" bakes "child models" for enterprises. LLM extractor and LLM fallback parser added. | CE `d2ba6e2`, ADR-0100, `51fcab9`, `59ba707`, `d0961eb` |
| **Sept – Oct** | Mostly repairing breakage caused by the NOVA number-storage change. 28,000 lines of documentation in October. | ~30 one-line fixes in NOVA |
| **9–10 Nov** | "Agent platform" work: an MCP server (returns fixed strings), a "cowork" planner (prints lines), an Ollama reply composer. A commit message plainly admits that the learning layers had "zero live callers outside tests". | CE `197e614`, `9ee9716` |

**Where the effort went.** In CrossEngin's source, roughly 23% is the cognition core, 17% is language/chat, 35% is networking and cryptography, and 25% is media decoding. Tests (164,000 lines) and documentation (about 100,000 lines) together outweigh the source. In NOVA, the Python editor tooling (58,000 lines) is larger than the compiler (35,000 lines).

---

## 4. What is real, what is partial, what is placeholder

**Real and working (verified by running it)**
- The NOVA compiler builds in under two seconds and reproduces itself exactly.
- CrossEngin builds: 397 modules and 10 programs compile cleanly.
- The fact store with confidence counters, source labels, retraction and an audit log.
- A small formal proof checker.
- Three-step chaining over taught "A leads to B" facts.
- The JPEG and PNG decoders (checked against a reference decoder on real files) and the hash/signature primitives (pass official test vectors).
- The CrossEngin unit tests: 478 files, about 21,000 real checks.
- The editor support and debugger for NOVA.

**Partial**
- The NOVA language itself: many documented features give wrong answers or crash (see below).
- Natural-language understanding: about 45 fixed English sentence shapes; anything else gets an unrelated or canned reply.
- Learning from web pages: fetches a page, counts words, applies five text patterns. It turns "the earth is not flat" into "earth is-a flat".
- Speech: works only by calling Whisper or Vosk.
- Other platforms: Windows and macOS output assembles but was never run on those systems; ARM is a stub.

**Placeholder, inert, or reachable only from tests**
- The spiking-neuron "fabric": runs, but its learning rule always computes zero on the live path and nothing reads it.
- "Forward-Forward" and "predictive coding": run, output unused.
- Theory of mind, imagination/dreams, planner, autonomous agent, self-improvement, world model: test-only.
- The WebRTC / TURN / SRTP / Raft stack (about 12,000 lines): test-only; the chat commands for them print a description.
- "Baked child models": the signature is real, but the knowledge section of a bundle is never loaded back.
- The MCP server: returns fixed strings.
- The "head-to-head vs LLM" score shown by `/vs`: the LLM's answers are written into the code by hand.
- Differential privacy and secure aggregation: structurally present, mathematically void (the noise is the same every run; keys have 15 bits of randomness).

**Four problems you should know about immediately**
1. **NOVA's `assert` does nothing.** A false assertion continues silently. About 70% of NOVA's own tests therefore cannot fail. When assertions were switched back on in a scratch copy, a third of the "passing" tests failed.
2. **There is no working secure random number generator.** A bug in the compiler makes the operating-system call fail every time, and the fallback has only 32,767 possible values. Every key, token and signature the system generates for itself can be guessed.
3. **Nothing is tested automatically on GitHub.** NOVA has no test workflow at all; CrossEngin's checks five fixed numbers. The documents say otherwise.
4. **The install instructions point at a GitHub organisation (`nova-lang`) that is not yours.** Whoever controls that name controls what users install.

---

## 5. The core idea, restated clearly

"Moment-Signal Computing" has meant three different things:

1. **In NOVA (May):** six kinds of hand-written handler ("perceiver", "knower"…) pass message records to each other through a priority queue. There is no numerical computation; similarity is a fixed-weight sum of string comparisons.
2. **In early CrossEngin (May):** a network of simple spiking neurons with strengthening and weakening connections. This is a known family of models (leaky integrate-and-fire neurons with Hebbian and reward-modulated learning). It is implemented and unit-tested, but nothing uses it.
3. **In CrossEngin since August (the official definition):** 
   - a **node** is a named fact;
   - a **signal** is one piece of evidence for or against it, which adds one to a "supported" counter or a "contradicted" counter;
   - confidence is supported ÷ (supported + contradicted);
   - a **moment** is a timestamped record of which facts were touched together;
   - **attribution** means every piece of evidence carries a source label.

The third is the simplest correct description of what the system does. Stated without the project's vocabulary: *a knowledge graph in which every fact carries a running tally of evidence and a record of who said it, answered by following stored links.* Each ingredient is well known (the counting scheme is standard Bayesian bookkeeping; knowledge graphs with provenance and confidence have been built for decades; link-following is classic rule chaining). The combination is sensible and the "say unknown rather than guess, and show your sources" stance is a worthwhile goal. But it is a design for a trustworthy database, not a mechanism from which understanding could emerge, and nothing in the repository tests whether it does anything a much simpler program could not.

---

## 6. What is genuinely valuable here

- **A self-hosting compiler exists and works.** Few projects get this far. It carries 190,000 lines of real code. As a demonstration of what can be built, and as a learning asset, it is real.
- **The auditable-knowledge idea is coherent.** Facts with provenance, graded evidence, retraction with cascade, an audit log and a small proof checker fit together. This is the part of CrossEngin that is both working and on the reply path.
- **Several components are correct in their own right:** the image decoders, the hash and signature code, the graph algorithms, the editor tooling.
- **The CrossEngin test suite is honest work** — small fixtures with hand-derived expectations.
- **The internal notes are often candid.** Many source files and design records state their own limits plainly. The overstatement is concentrated in the top-level README, vision and positioning documents.
- **You now know precisely which claims are unsupported**, which is what makes a refocus possible.

What is *not* an asset as it stands: the AGI framing, the "new computing paradigm" framing, the spiking fabric, the networking stack, and NOVA as a language for other people (no types, silent wrong answers, no release, no licence).

---

## 7. Recommended focus

**Option A — Turn the claim into one testable question (recommended).**
Freeze everything except the fact store, the chaining, and the evidence counters. Ask: *does a provenance-and-evidence-tracking knowledge base answer multi-step questions, and handle conflicting sources, better than simple baselines?* Run the five small experiments in the report (§8), the first of which takes hours. 
*For:* cheap (weeks), honest, and it produces a result either way. A positive result on conflicting-source handling would be a real, publishable, narrow contribution. 
*Against:* the likely outcome on plain question-answering is "equal to a 50-line graph search", and you need to be prepared for that.

**Option B — Make the fabric the research.**
Take the spiking network seriously: connect it so that it, not the lookup code, decides something, and test it on one small learning task against a small conventional network. 
*For:* closest to the original "cognition emerges from signals" idea. 
*Against:* highest risk; this is an active research field with strong existing work; the current implementation uses about 1 KB of memory per node per tick and would need rewriting.

**Option C — The language as the product.**
Stabilise NOVA and present it as a small self-hosting systems language. 
*For:* the bootstrap is a genuine achievement. 
*Against:* it has no type system, many silent miscompilations, and no advantage over existing small languages. Honest positioning would be "educational compiler", not a commercial product.

**Recommendation: Option A, preceded by one week of repair.** The repair week is: fix `assert`, fix the random number generator, add real automated tests, pin the NOVA version CrossEngin builds against, correct the README and vision documents, add a licence to NOVA, and fix the install address. Then run the decisive experiments before writing any more features. Whatever they show, set the rule that no new module is added unless an experiment needs it — that single rule would have prevented most of the drift.
