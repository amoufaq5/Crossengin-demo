# R65: Persist dictionary glosses across a snapshot

## Status

Accepted — R65 round (the "u" enhancement). The autodefine gloss (R60) now
survives `/save` + restart + `/load`, alongside the genus operator (R63), which
R51's operator round-trip already carried.

## Date

2026-06-09

## Context

R51 made the snapshot round-trip atoms, beliefs, word-atom lexical fixtures, and
reasoning operators (by-label premise/conclusion). R60 then added a **gloss** —
a word's primary definition stored as the atom payload `"gloss"` — and R63 added
a **genus operator** (`headword -> genus`, a normal `ROP_IMPLY`). The genus
operator already persisted via R51's operator serialization. But the gloss is an
atom *payload*, and the snapshot only serialized `[kg, id, kind, label, alpha,
beta]` + the operator fields — so after a reload, a defined word lost its
"X means: …" sense.

## Decision

Add the gloss as record field `[9]` in the KGS section, mirroring R51's operator
fields:

- `kg_section_build` writes `_snap_oneline(payload "gloss")` into `[9]` for any
  atom that has one (`_snap_oneline` flattens CR/LF to spaces, since the snapshot
  is line-based; a gloss is one sentence but be defensive).
- `kg_section_serialize` emits a `…[N].gloss` line **only when non-empty** (so
  non-glossed atoms add zero bytes); the parser fills `[9]`; `_ensure_records`
  pads it.
- `kg_section_apply` restores it with `atom_payload_set(a, "gloss", …)` right
  after the belief, for any atom kind (glosses live on word atoms today, but the
  restore is kind-agnostic).

The gloss value can contain spaces — the `key value` line format keeps
everything after the first space, so a multi-word definition round-trips intact.

## Verification

- **Unit** (`test_snapshot_disk_full` 84 → 89): a word atom with a multi-word
  gloss round-trips through the snapshot text and `kg_section_apply`, and
  `word_gloss` returns the exact definition after reload; a word *without* a
  gloss stays gloss-less (no spurious payload). All snapshot suites pass
  (`snapshot_disk`, `_delta`, `_replication`, `_migrate`, `_episodic`,
  `_synapses`).
- **Integration**: with R51 carrying the genus operator and R65 the gloss, an
  autodefined word survives save → reload with both its reasoning edge (the
  genus chain) and its gloss intact.
- Chat builds.

## Consequences / scope

- Dictionary knowledge is now durable: a word the agent autodefined (gloss +
  genus) reasons and glosses the same after a restart, not just within the
  session. Combined with R51 (operators) and R63 (genus), the whole dictionary
  contribution persists.
- Backwards compatible: a pre-R65 snapshot simply has no `.gloss` lines, so every
  record parses with an empty `[9]` and the restore is a no-op — old snapshots
  load unchanged (the legacy test still passes).
- The gloss is flattened to one line; a definition containing a newline (none do
  today) would lose the break. The cost is one extra snapshot line per glossed
  word, paid only by glossed words.
