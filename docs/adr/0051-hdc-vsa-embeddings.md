# ADR-0051: HDC / VSA embedding layer (P1 keystone)

## Status

Proposed

## Date

2026-06-11

## Context

CrossEngin's atoms carry a semantic embed vector used for fuzzy matching,
similarity search (`semantic_search.nova`), the LSH side-index (`ann_index.nova`),
and concept facets. Until now that vector was `word_lexical_vec` from
`word_atoms.nova`: an 8-dimensional hash where each character bumps one of eight
buckets. That captures **spelling, not meaning**. "car" and "automobile" share no
characters, so their lexical vectors are far apart even though the words denote
the same thing; conversely "car" and "cat" look similar. Every downstream
capability that leans on "one atom answers many phrasings" — entity resolution,
retrieval, tool selection, reasoning over neighbours — is brittle on top of this
representation. The `ENHANCEMENTS_ROADMAP.md` names this the **keystone (P1)**:
ingestion (P3) built on a weak embedding fragments the KG because entity
resolution can't tell synonyms apart.

We want meaning-bearing vectors that are **local, online, gradient-free and
auditable** (the project's design invariant): no tokenizer-as-LLM, no
backpropagation, no offline training run. Vector Symbolic Architectures / Hyper-
dimensional Computing (Kanerva 2009; Plate's HRR; Gayler) fit exactly: very high
dimension makes random vectors near-orthogonal, and three algebraic operations —
**bind**, **bundle**, **permute** — compose them into structured, one-shot,
queryable representations with no learning rule at all.

## Decision

Add `src/kg/hdc_embed.nova`: a VSA over **D = 10,000 bipolar hypervectors**
(each coordinate +1 or -1), stored as the same "list of ints" shape as the
existing `vec_*` embeddings so they are a drop-in replacement in the atom embed
slot and flow through the dimension-agnostic `ann_index` unchanged.

Operations:

| Function | Meaning |
|---|---|
| `hdc_dims()` | the standard dimensionality (10000) |
| `hdc_random_atom_vector(seed)` | deterministic +/-1 hypervector from an integer seed |
| `hdc_str_seed(label)` / `hdc_symbol(label)` | a label's stable seed / symbol vector |
| `hdc_bind(a, b)` | element-wise multiply (role (x) filler); self-inverse for bipolar |
| `hdc_unbind(c, key)` | recover a filler (== `hdc_bind`) |
| `hdc_bundle(list)` | element-wise sum then sign (superposition / set membership) |
| `hdc_permute(v, k)` | cyclic shift by k (order / slot protection); inverse is `-k` |
| `hdc_cosine(a, b)` | signed similarity in milli, [-1000, 1000] |
| `hdc_encode_edges(edges)` / `hdc_encode_atom(label, edges)` | bundle of (relation (x) neighbour) over an atom's edges |

**Meaning lives in the neighbourhood.** An atom is encoded as the bundle of
`bind(relation, neighbour)` over its edges; its own (spelling-derived) symbol is
deliberately *not* folded in, so two atoms with the same neighbours land close
together regardless of how they're spelled. This is what makes "car" and
"automobile" resolve together once both are described by shared neighbours.

**Determinism + provenance.** Every symbol vector is a pure function of its label
(FNV-1a seed -> glibc LCG bit stream), so the same label yields the same vector
across calls, processes and snapshots — no stored random codebooks, nothing to
persist or drift, and any vector is re-derivable for audit.

**Cutover behind a flag.** `atom_store.nova` gains `ATOM_EMBED_MODE`
(`atom_embed_mode()` / `atom_set_embed_mode()` / `atom_embed_is_hdc()`),
defaulting to `LEGACY`. Producers consult it: `word_atoms.word_atom_new` now
writes `word_embed_vec(form)`, which returns the byte-identical lexical hash in
LEGACY mode and a hypervector in HDC mode. Because the default is LEGACY, every
existing unit test and snapshot is unchanged; flipping the flag is the explicit,
auditable switch the roadmap asks for.

## Options Considered

- **Bipolar +/-1 hypervectors as int lists, D=10000 (CHOSEN).** Matches the
  roadmap's `bind = mult`, `bundle = sign(sum)` spec exactly; reuses the existing
  integer milli-fixed-point + `isqrt` cosine convention; bind is *exactly* self-
  inverse (`(+/-1)^2 = 1`), so unbind has no algebraic error, only superposition
  noise. Drop-in for the atom embed slot and `ann_index`.
- **Reuse NOVA's `std/cognitive/hdc.nova` (rejected).** NOVA ships a float/raw-
  memory HDC, but `atom_store.nova` already documents that NOVA's `std/embed`
  doesn't link cleanly into CrossEngin (duplicate symbols), and a raw-pointer
  representation wouldn't slot into the list-shaped embed/`ann_index`/cosine path.
  We mirror its proven LCG and majority-vote bundle, re-expressed in CrossEngin's
  integer idiom.
- **Real-valued / dense learned embeddings (rejected).** Would require a training
  run and gradient machinery, violating the no-backprop, no-offline-training
  invariant.
- **Just widen the lexical hash (rejected).** More dimensions of a character
  histogram is still spelling, not meaning; "car"/"automobile" stay far apart.

## Consequences

- **Positive.** Synonyms-by-neighbourhood become close in vector space
  (measured: `cos(encode(car), encode(automobile)) = 731 > 700`, while the raw
  spelling symbols are near-orthogonal and `cos(encode(car), encode(dog)) ~ 0`).
  Structured records are queryable in one shot (`(France (x) capital) -> Paris`).
  The representation is deterministic and auditable, and the cutover is gated so
  nothing breaks until we choose to switch. `ann_index` needed no change — LSH
  scales to D=10k; tests build it with K=16 (65,536 buckets).
- **Negative / costs.** A 10,000-int list per atom is ~1250x the storage of the
  8-dim vector, and `hdc_symbol` recomputes a 10k-step PRNG on each call (no cache
  yet). For large KGs this matters; see Honest gaps. Bundling has finite capacity
  (crosstalk grows with the number of superposed pairs).

## Honest gaps

- **Capacity is finite and unmanaged.** Measured recovery from a single bundle:
  perfect through ~35 superposed pairs, degrading gracefully to 58/60 at N=60
  (D=10000). Real atoms with very high degree will exceed this; we do not yet
  segment or normalise high-degree neighbourhoods. Mitigation (future): cap edges
  per encode, weight by belief, or use multiple bundles.
- **No symbol-vector cache.** `hdc_symbol(label)` is pure but recomputed every
  call; `hdc_encode_edges` calls it per endpoint. A label->vector memo (or
  persisting the vector on the language atom) is needed before HDC mode is
  economical at scale.
- **The cutover is partial.** Only `word_atom_new` honours the flag so far.
  `snapshot_disk.nova` reconstructs embeds with `word_lexical_vec` and
  `concept_layer.nova` facets are still lexical; both need the same
  `word_embed_vec`-style branch before HDC can be the global default. They remain
  correct in the default LEGACY mode.
- **`semantic_search.nova` is not re-pointed.** Despite the roadmap wording, that
  module is a TF-IDF *term* index, not an embed-cosine search, so "re-point its
  cosine at HDC" doesn't apply to it directly; the embed cosine that HDC replaces
  is `atom_store.vec_cosine` (used by `ann_index`). Entity resolution (P3) is the
  natural first real consumer of `hdc_cosine`.
- **Even-count bundles use a fixed +1 tie-break.** When a bundle has an even
  number of members a coordinate can sum to zero; we resolve to +1. This injects a
  tiny DC bias rather than a random tie-break vector. Harmless at the thresholds
  we use, but worth a random tie-breaker if exactness ever matters.
- **Seed space.** Symbol seeds are 31-bit (FNV folded into the LCG range), so
  collisions are astronomically unlikely for realistic vocabularies but not
  literally impossible.

## Implementation Notes

- `hdc_embed.nova` imports `atom_store.nova` for `isqrt`, `FP_SCALE`, and the
  vector shape; it is the only new dependency `word_atoms.nova` picks up.
- **NOVA codegen bug #11.** The pointer-threshold multiply heuristic miscompiles
  `a * b` when either operand is >= 0x100000 (1,048,576). The PRNG multiplies by
  large LCG/FNV constants, so it uses the overflow-safe `int_mul`/`int_mod`/
  `int_div`/`int_add` builtins (the same choice NOVA's own std HDC makes). The
  bipolar arithmetic (bind/bundle/cosine) only multiplies tiny operands (+/-1, and
  accumulators bounded by D), so it uses bare operators. This was verified
  empirically: the bare-operator LCG crashes ("Killed") after a few thousand
  iterations; the `int_*` form runs clean and produces balanced (~4950/10000) bits
  with ~50% Hamming distance between adjacent seeds (near-orthogonality).
- **Cosine is signed.** `hdc_cosine` returns [-1000, 1000] rather than clamping at
  0 like `vec_cosine` (which assumes the non-negative lexical vectors), because
  bipolar anti-correlation is meaningful.
- **Tests.** `tests/unit/test_hdc_embed.nova` (39 checks) covers bipolarity,
  determinism, near-orthogonality, the bind self-inverse, bundle membership,
  permute round-trip, the France/capital/Paris record recovery, the
  car/automobile synonym acceptance (> 700), capacity/crosstalk at N = 5/35/60,
  and an `ann_index` query round-trip at D=10k. `tests/unit/test_word_atoms.nova`
  gains a case proving `word_atom_new` honours the mode flag. All prior tests pass
  unchanged with the flag at its LEGACY default.
- **Next (P1 -> P2/P3).** Cache symbol vectors; extend the flag branch to
  `snapshot_disk` and `concept_layer`; make `entity_resolve.nova` (P3) the first
  consumer of `hdc_cosine` for synonym collapse before insertion.
```
P1 HDC embeddings  --►  P2 predictive coding + 3-factor  --►  P3 ingestion/OpenIE
```
