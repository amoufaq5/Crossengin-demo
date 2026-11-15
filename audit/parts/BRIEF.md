# Shared brief for audit sub-reviewers

You are one reviewer in a technical due-diligence audit of two sibling repositories:

- `/home/user/NOVA` — "Nova", a self-hosting compiled language (compiler written in Nova, emits x86-64 assembly, assembled with `as`/`ld`). Claims to be "a language for AGI through Moment-Signal Computing".
- `/home/user/Crossengin-demo` — "CrossEngin", ~190k lines of Nova claiming to implement "Moment-Signal Cognition (MSC)", a non-LLM, non-transformer route to AGI (nodes, signals, moments, attribution; knowledge graph; etc.).

The founder has lost track of what the project has become and wants an honest account. Be candid and kind; never flattering, never dismissive. **Judge by what the code DOES, not by names, comments or docs.** When something has a grand name ("consciousness", "soul", "reasoning", "imagination", "emotion", "belief", "learning"), state in plain algorithmic terms what the code computes (e.g. "increments an integer counter clamped to 0..100", "substring match over a list").

## Hard rules
- READ-ONLY on both repos. Never modify, create or delete anything under `/home/user/NOVA` or `/home/user/Crossengin-demo`. No git commits, no pushes, no network calls to paid APIs.
- Write output ONLY under `/home/user/audit/parts/` (the two files named in your assignment).
- Scratch copies you may build/run in: `$S/NOVA` (compiler already built at `$S/NOVA/bin/nova`) and `$S/CE`, where
  `S=/tmp/claude-0/-home-user/0f6d34e6-ba9a-56d7-bcb5-b0fca8a83a57/scratchpad`.
  Put any probe programs you write in `$S/probes/<your-agent-name>/`. Compile+run a Nova program with: `$S/NOVA/nova run file.nova` (or `$S/NOVA/nova build file.nova -o out`). Do NOT run `make` inside `$S/NOVA` or `$S/CE` (fixed /tmp paths shared with other reviewers; the lead is running the full suites). Always wrap executions in `timeout 60`.
- Every claim must cite `path:line` (repo-relative, prefixed `NOVA/` or `CE/`). Label each conclusion CONFIRMED (verified by reading the code or by execution), LIKELY, or SUSPECTED.
- Cover EVERY file in your assignment. Large generated/vendored/repetitive files may be "skimmed" — say why.

## What to hunt for (in every file)
1. What it actually computes (one line per file).
2. Stubs / placeholders / TODO / `pending` / functions returning constants / unimplemented branches.
3. Fake or canned results: hard-coded outputs, demos that print expected answers, random numbers presented as measurements.
4. Tests that cannot fail or only compare against values the code itself just produced.
5. Hidden dependence on technology the project says it avoids: LLM APIs (OpenAI, Anthropic, Ollama, llama.cpp), pretrained models/embeddings (whisper, vosk, word vectors), neural-net libraries (torch/tf/jax), BLAS/numpy as the core computation, Python sidecars, shell-outs (`curl`, `ffmpeg`, etc.). Say exactly where and how central.
6. Dead/orphaned code not reachable from any entry point or test.
7. Correctness bugs, security problems (memory safety, injection, path traversal, shelling out with untrusted input, weak/hand-rolled crypto, hard-coded keys/secrets), and naming that overstates function.
8. TODO/FIXME/HACK/XXX inventory counts.

## Output (two files)
1. `/home/user/audit/parts/<name>_coverage.md` — a markdown table with ONE ROW PER FILE in your assignment: `| path | status (reviewed/skimmed) | LOC | actual status (Working/Partial/Stub/Fake/Dead/Doc) | one-line plain description of what it really does |`. Every file must appear. Verify your row count against `git ls-files` for your directories and state the count at the top.
2. `/home/user/audit/parts/<name>_findings.md` — structured findings: a short plain-language summary (10–20 lines) of what this area really is; then a findings table (ID, severity Critical/High/Medium/Low, category, title, file:line, evidence, impact, recommended fix, effort S/M/L, confidence label); then any detailed notes your assignment asks for.

Your final message back to the lead should be a concise summary (max ~60 lines): the most important 10–15 findings with file:line, anything you executed and its result, and anything you could not verify. Raw facts over prose.
