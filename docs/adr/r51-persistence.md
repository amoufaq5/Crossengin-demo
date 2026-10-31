# R51: Persistence of reasoning operators (learned chains survive a restart)

## Status

Accepted — R51 round. Closes the durability gap so learned knowledge —
atoms **and** the reasoning operators that link them — survives a `/save` +
restart + `/load`, not just the atoms.

## Date

2026-06-08

## Context

`/save` and `/load` already rehydrated atoms: labels, Bayesian beliefs, and
(R-earlier) the lexical fixture for `ATOM_LANG` words (ltype = LWORD, char-vector
embedding, sense xrefs). But they dropped the **reasoning operators** — the
`ATOM_RELATION` atoms (ADR-0031) that carry `op` / `premise` / `conclusion` and
make forward-chaining work.

The symptom, live in the chat:

- `/research photosynthesis` (R50) → learns words + operators; "what is
  photosynthesis" reasons `photosynthesis -> energy -> work -> tired`.
- `/save` → fresh process → `/load` → reasoning KG restored 584 → 590,
  `/find photosynthesis` → `atom_id=584 sim=1000` (the atom is plainly there) —
  but "what is photosynthesis" now says **"i don't have a model of
  photosynthesis yet"**. The concept survived; the *reasoning over it* did not.

Root cause: `kg_section_build` serialized only `[kg, id, kind, label, alpha,
beta]`. An operator's `premise`/`conclusion` payload was never written, so after
a load every operator was a bare `ATOM_RELATION` with no links. Worse, those
payloads are atom **ids**, and ids are not stable across a reload — a fresh
process re-mints them from 0 — so even a naive id round-trip would re-link
operators to the wrong atoms.

## Decision

Serialize operators **by label** and re-resolve them on apply.

- **`kg_section_build`** — for any atom that is an operator (canonical check:
  `atom_payload_has(a, "op")`, the same marker `is_operator` uses, which
  `rop_new` co-sets with premise/conclusion), emit three extra record fields:
  `[6]` op kind, `[7]` premise *label* (resolved via `kg_atom(kg, premise_id)`),
  `[8]` conclusion *label*. Non-operators emit `op = -1` and empty labels.
- **`kg_section_serialize` / parser** — three optional lines per operator
  (`…[N].op` / `.premise` / `.conclusion`), emitted **only** when `op >= 0` so
  non-operator atoms add zero bytes and the snapshot stays compact. The
  per-record shape (`_ensure_records`) widened from 6 to 9 fields; the parser
  fills the new suffixes.
- **`kg_section_apply` second pass** — runs *after* the per-KG index rebuild (so
  `kg_find_atom` is O(1) and every atom in the blob already exists). For each
  operator record: re-find the operator atom, the premise, and the conclusion
  **by label** in the now-rehydrated target KG, and re-attach the payload with
  the **fresh** atom ids. An operator whose premise or conclusion can't be found
  by label is silently dropped, never mis-linked — the same accept-only-if-known
  conservatism as R49.

By-label is the load-bearing choice: it survives id drift *and* the
re-seeded-substrate case (the chat installs the 584-atom seed before `/load`, so
a snapshot operator merges onto the live atom of the same label rather than a
stale id).

## Verification

- **Unit** (`test_snapshot_disk_full`, 73 → 84 checks): a new
  `test_kg_section_operator_round_trip` builds a `ROP_CAUSAL` operator
  (`virus -> infection`), round-trips it through the snapshot text format, and
  applies it to a *fresh* registry. It asserts the operator's premise/conclusion
  re-resolve **by label to the freshly-minted ids** (not the stale source ids),
  `is_operator` holds, the op kind survives, and `rk_operators_from(virus)` finds
  the operator again. All 12 snapshot suites + `reasoning_atoms`, `episodic`,
  `schema_migration` pass.
- **End-to-end**, live in the chat (deterministic, no network — a local
  `crossengin_learn_*` cache + triples sidecar):
  - `/learn photosynthesis` → 5 words, 3 operators, KG=590; "what is
    photosynthesis" reasons `photosynthesis -> energy -> work -> tired` (the
    learned `photosynthesis|causal|energy` operator chaining into seed
    operators). `/save /tmp/persist_test.snap`.
  - **Fresh process**, `/load` only (no re-learning): reasoning 584 → 590,
    `applied=1146 new_atoms=9`; "what is photosynthesis" reasons **identically**:
    `photosynthesis -> energy -> work -> tired`. The same reload that previously
    said "i don't have a model" now reasons.

## Consequences / scope

- Learned reasoning is now durable: research a topic → persist → reboot → still
  reason over it. Combined with R50 (self-initiated research), the knowledge the
  agent gathers on its own initiative survives a restart instead of evaporating.
- Cost is paid only by operators: +3 snapshot lines each; ordinary atoms are
  unchanged on disk. The legacy `kgs.atoms` count line and the
  informational-id contract are untouched (the reader keys everything by label).
- Re-resolution is **intra-KG**: an operator is re-linked within its own KG.
  Today every operator lives in the reasoning KG, so this is complete; a
  cross-KG operator (premise in one KG, conclusion in another) would need a
  `(kg, label)` pair per endpoint — a later refinement if such operators appear.
- Backwards compatible: a pre-R51 snapshot simply has no `.op` lines, so every
  record parses as a non-operator (`op = -1`) and the second pass is a no-op —
  old snapshots load exactly as before (verified by the unchanged legacy test).
