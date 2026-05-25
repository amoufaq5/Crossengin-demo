# ADR-0015: Language atoms in substrate (words, phonemes, syntax patterns as atoms)

## Status

Proposed

## Date

2026-05-25

## Context
The reader (ADR-0011/012) anchors surface tokens to "language atoms," and the output path (ADR-0013) realizes concepts through "language nodes" and "syntax-pattern atoms." Both presuppose that language itself is represented IN the substrate as data the system can learn and change. This ADR defines that representation. It must be decided now because it is the shared substrate that comprehension and generation both stand on, and because storing language as atoms (rather than as a hard-coded lexicon or an external model) is what makes the NO-LLM-COGNITION principle (ADR-0014) actually workable.

The constraint is consistency with the substrate model (§2): everything persistent is an ATOM, mutable and KG-stored (ADR-0016), living in domain-organized KGs (ADR-0004, ADR-0017). Language must obey the same rules — no privileged hard-coded dictionary, no frozen grammar. A 2-founder team cannot hand-author and maintain a large lexicon and grammar anyway; language must be learned and grow like every other domain. The open question is the schema: what exactly is a word atom, a phoneme atom, a syntax-pattern atom, and how do they reference concept atoms in other KGs.

## Decision
We store **words, phonemes, and syntax patterns as mutable atoms in a dedicated language KG** (`KG-language`), structured per the general atom design of ADR-0016 and integrated via the multi-KG cross-reference mechanism of ADR-0017.

Three atom kinds, all built with `atom_new` and carrying Bayesian confidence (alpha/beta via `core/belief.nova`):
- **Word atoms:** surface form + cross-KG references to the concept atom(s) they name (in `KG-medicine`, `KG-general`, etc.), weighted by `core/similarity.nova`. Polysemy = multiple weighted references; the reader's context bias (ADR-0012 stage 2) selects among them.
- **Phoneme atoms:** sound units referenced by word atoms, used at the modality boundary by the STT/TTS adapters (ADR-0014). They let the system align spoken and written forms without an LLM.
- **Syntax-pattern atoms:** learned ordering/agreement templates (e.g., a slot pattern over concept roles) that sequence word atoms during generation (ADR-0013) and group them during the reader's binding/coherence stage (ADR-0012 stage 4).

All three are LEARNED and MUTABLE. New words are born from co-activation when an unknown token co-occurs reliably with a concept (atom birth, ADR-0025) — often via ask-the-user (ADR-0027) or fetch (ADR-0028). Confidence updates with use (ADR-0023); weak, stale language atoms decay and are GC'd (ADR-0025). Syntax-pattern atoms strengthen via Hebbian + error-driven plasticity (ADR-0007) when phrasings succeed. `KG-language` is thus a first-class learning domain, not configuration.

## Options Considered
1. **Hard-coded lexicon + grammar tables (compiled in).** Fast, deterministic, no cold start. Rejected: immutable and unlearnable, violates the substrate model (§2) and the everything-is-an-atom rule (ADR-0016), unmaintainable by 2 founders at scale, and cannot personalize or acquire new terms — exactly the brittleness ADR-0011 rejected.
2. **Embeddings-only (words as vectors, no discrete atoms).** Smooth similarity, integrates with concept layer (ADR-0018). Rejected as the representation: vectors alone can't carry discrete cross-KG references, Bayesian confidence, or syntax structure, and aren't individually auditable/mutable as units. Embeddings are retained as a FACET of word atoms (multi-vector, ADR-0018), not the whole.
3. **Language baked into the concept layer (no separate language KG).** Fewer moving parts. Rejected: conflates "the concept of a dog" with "the word dog" and "the sound /dawg/"; a single concept may have many words across registers/languages, and words decay/change independently of concepts. A dedicated `KG-language` with cross-refs keeps these orthogonal (ADR-0017).
4. **Words/phonemes/syntax as mutable atoms in a dedicated language KG (CHOSEN).** Obeys the substrate and atom models, learnable and auditable, cleanly separated from concepts yet linked by weighted cross-refs, and shared identically by reader and output. Cold-start weakness is accepted and mitigated by ADR-0027/028 seeding.

## Consequences
- **Positive:** Language is just another learnable, auditable domain — no privileged hard-coding; comprehension (ADR-0012) and generation (ADR-0013) share one representation; polysemy, multilingualism, and personalized vocabulary fall out naturally from weighted cross-refs; supports NO-LLM-COGNITION by giving the substrate its own linguistic knowledge.
- **Negative:** Cold start with an empty `KG-language` is weak and depends heavily on early teaching (ADR-0027) and fetch (ADR-0028); syntax-pattern atoms are a hard representational problem (encoding order/agreement as atoms) and the riskiest part of this ADR; large language KGs stress the multi-KG indexing of ADR-0017.
- **Future work:** ADR-0016 fixes the concrete atom layout this builds on; ADR-0018 integrates word embeddings as a multi-vector facet; ADR-0025 governs language-atom birth/death; ADR-0027/028 seed and grow `KG-language`; ADR-0039 (theory of mind) may add per-user vocabulary cross-refs.

## Implementation Notes
Define `crossengin/language/lang_atoms.nova`: tag constants `ATOM_WORD`, `ATOM_PHONEME`, `ATOM_SYNTAX`; constructors `word_atom_new(form, concept_refs)`, `phoneme_atom_new(symbol)`, `syntax_atom_new(slot_pattern)`; accessors for surface form, references, and alpha/beta. Store all in `KG-language` via `core/knowledge.nova`; cross-KG references use `core/similarity.nova` weights per ADR-0017. Confidence via `core/belief.nova`; plasticity for syntax patterns via the ADR-0007 kernels. The reader (`crossengin/reader/reader.nova`) and output (`crossengin/output/generate.nova`) both import this module — it is their shared substrate.
Testing: `tests/language/word_birth.nova` asserts an unknown token + repeated concept co-activation creates a `word_atom` (ADR-0025); `tests/language/polysemy_refs.nova` asserts a word atom holds multiple weighted concept references and the reader selects by context; `tests/language/syntax_order.nova` asserts a syntax-pattern atom imposes correct word order in generation.
DEPENDS ON: NOVA enhancement #8 — multi-KG namespacing + cross-KG reference edges with similarity weights (for `KG-language` and word->concept refs). DEPENDS ON: NOVA enhancement #12 — plasticity kernels so syntax-pattern atoms learn from successful phrasings.
