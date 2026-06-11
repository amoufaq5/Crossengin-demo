# ADR-0060: number-words & units → value (NL_AND_COVERAGE N2)

## Status

Proposed

## Date

2026-06-11

## Context

`arithmetic.nova` evaluates digit expressions, but a large fraction of natural-
language quantity is spelled out ("three hundred", "a dozen", "two thousand five
hundred") or carries a unit ("2.5 kg"). Table/measure ingestion and the
arithmetic router both need a numeric value out of those forms.

## Decision

A new pure, dependency-free module `src/language/number_words.nova`:

- `numw_words_to_value(text)` → `[ok, value]`: the classic accumulate-on-scale
  algorithm over a curated word table — ones/teens, tens, multipliers (hundred,
  dozen=12, score=20), scales (thousand/million/billion), with "a"/"an"/"and"
  filler and hyphenated compounds. ADD words grow the running group, a MULT word
  multiplies it (a bare multiplier means 1×), a SCALE word flushes group×scale
  into the total.
- `numw_parse(text)` → `[ok, milli, unit]`: scans for the first number — a digit
  token (`"2.5"`) **or** a word run — yields it in MILLI (×1000 fixed point, the
  house convention so it feeds `arithmetic.nova` directly), and attaches the
  first recognised measurement unit after it (`numw_unit_canon` folds
  singular/plural/abbrev: kilograms→kg, metres→m, percent→%).

**Codegen discipline.** Scaled milli values routinely exceed NOVA codegen bug
#11's `0x100000` threshold ("two million" = 2,000,000,000 milli), so every value
computation uses the `int_*` escape-hatch builtins (`int_mul`/`int_add`), never
the smart-op `*`/`+`. Loop indices and small literal comparisons stay on the
ordinary operators (operand < threshold ⇒ the int path is taken correctly).

## Consequences

- "three hundred", "a dozen", "twenty-one", "two thousand five hundred", "2.5
  kg", "five kg of flour" all parse to the right milli value + unit, unit-tested
  (`test_number_words`, 45 checks). Large values are asserted via `int_to_str`
  string equality (a `==` between two ≥-threshold ints would itself miscompile).
- Pure and additive: no existing module changed, no flag needed.

## Honest gaps

- ~~**Not yet wired into `arithmetic.nova`.**~~ **Done (follow-up).**
  `arith_eval` now runs `_ar_normalize_numbers` first, rewriting spelled-out
  number runs to digits ("two hundred plus fifty" → "200 plus 50") before the
  char-level scan; digit-only inputs pass through unchanged (no number word ⇒
  identical text), so `test_arithmetic` keeps its old checks and gains word-
  number ones (16 → 23). Caveat: arithmetic between two ≥-threshold operands
  ("two million plus two million") still hits codegen bug #11 — a pre-existing
  arithmetic limitation, not specific to word intake.
- **Ordinals and fractions** ("third", "two and a half", "1/2") are out of scope;
  only cardinals and decimal digit tokens are handled.
- **Unit conversion is not done.** A unit is captured and canonicalised, not
  scaled to a base (kg↔g); measure ingestion can layer that on the `[milli,
  unit]` pair.
- **Negative numbers** are not parsed as part of a phrase (no "minus three"); the
  arithmetic evaluator owns subtraction.

## Implementation Notes

- New files only: `src/language/number_words.nova`,
  `tests/unit/test_number_words.nova`.
- Next on `NL_AND_COVERAGE.md`: N3 — OpenIE depth (negation polarity,
  coordination split, intra-sentence coreference).
