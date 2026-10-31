# Capturing an LLM transcript for the reasoning benchmark

The reasoning benchmark (ADR-0086 Phase 7) measures one property an LLM cannot
structurally guarantee: **soundness on checkable questions** -- affirming what is
provable while withholding on what is not, never manufacturing a proof of a
falsehood. The head-to-head harness scores the engine against a **recorded** LLM
transcript over the same bank.

> **Honest scope (Rule 1).** The engine never calls a third-party LLM. There is
> no live-call path anywhere in this repo. A real transcript is therefore
> captured **separately and offline** with whatever LLM you choose, then pasted
> in as a data file. This repo ships only **illustrative** transcripts
> (`data/llm_baseline_sample.txt` for the default bank,
> `data/llm_baseline_ext.txt` for the extended bank) plus the ingestion + scoring
> machinery (`src/bench/llm_transcript.nova`, `src/bench/reasoning_bench.nova`).
> Swap an illustrative file for a real recording and the measurement becomes real;
> the harness is unchanged.

## 1. Each bench item is a yes/no question

A bench item is `[id, axioms, hyps, proof, claim, expected]`. To put it to an
LLM, render the axioms/hypotheses as premises and the `claim` as the proposition,
then ask a single yes/no question:

> "Given these premises, is the following claim TRUE / does it follow?
>  Answer yes or no."

Examples from the extended bank (`src/bench/bench_bank_ext.nova`):

| id  | premises                                   | claim (question)            | ground truth |
|-----|--------------------------------------------|-----------------------------|--------------|
| 103 | (none)                                      | `6 * 7 = 42`                | PROVABLE     |
| 107 | (none)                                      | `7 / 2 = 3`                 | UNPROVABLE   |
| 110 | `p -> q`, `p`                                | `q`                         | PROVABLE     |
| 119 | `p`                                          | `r`                         | UNPROVABLE   |
| 122 | `forall x.(human(x)->mortal(x))`, `human(socrates)` | `mortal(socrates)` | PROVABLE     |
| 125 | `forall x.P(x)`                              | `Q(a)`                      | UNPROVABLE   |

A sound reasoner answers **yes** for PROVABLE and **no** for UNPROVABLE.

## 2. The on-disk transcript format

One record per line: `<item_id> <verdict>`, where `<verdict>` is `affirm`
(the LLM said yes) or `deny` (it said no / declined). Blank lines and lines whose
first non-space character is `#` are comments. Only the first character of the
verdict word is read (`a...` = affirm, anything else = deny), so `affirm`/`a` and
`deny`/`no`/`false` all parse as expected. See `src/bench/llm_transcript.nova`.

```
# id 103: 6 * 7 = 42
103 affirm
# id 107: 7 / 2 = 3 -- LLM rounds and affirms (wrong)
107 affirm
106 deny
```

A missing id defaults to `LLM_DENY` (the conservative no-commitment stance -- it
can never inflate the LLM's false-confident count).

## 3. How to capture a REAL transcript

1. Enumerate the bank's ids and render each item as the yes/no question above.
   (The extended bank is ids 101..126; the default bank is 1..12.)
2. Put each question to your chosen LLM **offline**, in its own context so earlier
   answers cannot leak. Record exactly one verdict per id.
3. Map each answer to `affirm`/`deny` and write one `<id> <verdict>` line into a
   file under `data/`, e.g. `data/llm_baseline_ext.txt`. Keep a `#` comment trail
   noting the model, date, and prompt used, for reproducibility.
4. Do **not** edit the engine to fetch the answers -- the capture is a manual /
   external step by construction (Rule 1).

## 4. Feeding it to the harness and scoring

Read + parse the file, then run it past the bank:

```
import "src/bench/llm_transcript.nova"
import "src/bench/reasoning_bench.nova"

let reg = proof_registry_new()
let tr  = llm_transcript_from_file("data/llm_baseline_ext.txt")  // or _parse(text)
let s   = bench_compare_transcript(reg, tr)
print(bench_compare_render(s))
```

`bench_compare_transcript` pairs each item with its recorded verdict by id (via
`llm_verdict_for`) and scores both sides against the same ground truth. The
scorecard reports:

- **engine correct / accuracy** -- the engine affirms by producing a kernel-
  checked proof and withholds otherwise;
- **engine false proofs** -- structurally **0**: the engine has no proof for a
  non-theorem, so it refuses; its only possible error is an honest abstention;
- **LLM correct / accuracy** -- affirm-on-provable or deny-on-unprovable;
- **LLM false-confident** -- affirm-on-UNPROVABLE, the unjustified commitment
  this comparison exists to expose (e.g. rounding `7/2` to `3`, or bluffing a
  non-entailed goal).

> `bench_compare_transcript` is currently wired to `bench_default_bank()`. To
> score the extended bank, pair `bench_ext_bank()` with the transcript using the
> public `bench_pair` / `bench_compare` functions (same loop, substituting the
> bank) -- no kernel or harness change required.

The takeaway the structure guarantees regardless of which LLM is recorded: the
engine's false-proof column is 0 by construction, while affirm-on-unprovable is a
live failure mode for next-token prediction.
