# ADR-0085: Close the chat_state vs snapshot fidelity gaps (embeddings, operators, gloss) + xref coactivation count

## Status

Accepted — Date 2026-06-13.

The chat session save/load path (`src/persistence/chat_state.nova`:
`chat_state_save*` / `chat_state_load_text`, serializer `_cs_emit_kg`) now
persists, per atom: the EMBEDDING vector, the reasoning OPERATOR payload
(premise/conclusion), and the R60 dictionary GLOSS — closing the residual
ADR-0083 drops relative to the disk-snapshot path
(`src/persistence/snapshot_disk.nova`, `kg_section_*`). Separately, the cross-KG
reference COACTIVATION count (`XR_COACT`) is now persisted by BOTH the
chat_state path AND the snapshot path (gap D, which affected both). Old
chat_state files and old snapshots without the new records/fields still load
(strict backward compatibility).

## Context

ADR-0083 brought the chat_state ATOM format up to persist xrefs, but it still
dropped — relative to the snapshot KGS section — several per-atom fields, and
the xref coactivation count was dropped by both paths (ADR-0083 gap D).

### STEP 1: field-by-field coverage diff (snapshot vs chat_state, BEFORE this ADR)

Snapshot KGS path (`kg_section_build_r` / `kg_section_serialize` /
`kg_section_apply` in `snapshot_disk.nova`) persists, per atom:

| Field                         | Snapshot (KGS) | chat_state (ATOM) before 0085 |
|-------------------------------|----------------|-------------------------------|
| kg label                      | yes (`kgs.atoms[N].kg`) | yes (implicit: KG_BEGIN block) |
| atom id                       | yes            | yes (ATOM field 1)            |
| kind                          | yes            | yes (ATOM field 2)            |
| label                         | yes            | yes (ATOM trailing field)     |
| belief alpha/beta             | yes            | yes (ATOM fields 3/4)         |
| **embedding vector**          | **NO** (re-derived for LANG only via `word_embed_vec`) | **NO** (empty vector) |
| operator `op` kind            | yes (`.op`)    | **NO**                        |
| operator premise (by label)   | yes (`.premise`) | **NO**                      |
| operator conclusion (by label)| yes (`.conclusion`) | **NO**                   |
| R60 gloss                     | yes (`.gloss`, R65) | **NO**                   |
| xref dst kg / dst / kind / weight / earned | yes (`.dstkg/.dst/.kind/.weight/.earned`) | yes (XREF fields 2-6) |
| **xref coactivation (`XR_COACT`)** | **NO** (gap D) | **NO** (gap D)          |
| LANG lexical fixture (`ltype=LWORD`) | yes (re-installed on apply) | NO |
| provenance (`A_PROV`)         | NO             | NO                            |
| created/updated/version timestamps | NO        | NO                            |
| moment trace / salience       | NO (episodic only) | NO                        |

Key finding: the snapshot KGS path does **NOT** persist a raw embedding vector
for general atoms — it only re-derives the deterministic character-vector for
LANG atoms on apply. So there was no shared "snapshot vec encoding" to reuse;
the chat_state EMBED record below is a NEW encoding. Operator and gloss encodings
DO mirror the snapshot path (premise/conclusion by label; gloss as a one-line
string).

## Decision

Persist + restore in `chat_state.nova`, reusing the snapshot path's *resolution
strategy* (by-label, deferred final pass) wherever it applies. New on-disk
records, all emitted INSIDE the `KG_BEGIN`/`KG_END` block after the ATOM lines:

1. **Atom embeddings** (highest value — chat-loaded atoms had empty vectors,
   breaking semantic search / centroids / ANN after a reload). Record:
   ```
   EMBED <id> <dims> <v0> <v1> ... <v(dims-1)>
   ```
   e.g. `EMBED 0 8 11 22 33 0 0 0 0 99`. Restored via `atom_set_embed` after the
   final id->label resolution pass. Only non-zero vectors are emitted (an
   all-zero/default vector is skipped, keeping old-style output byte-identical
   and the back-compat path a no-op). Dims are carried explicitly and validated.

2. **Operator premise/conclusion** payloads. Record:
   ```
   OP <id> <op_kind> <premise_label> | <conclusion_label>
   ```
   premise/conclusion are serialized BY LABEL (atom ids are not stable across a
   replace-by-label load), split on a ` | ` sentinel (labels never contain it),
   and re-resolved to live atom ids in the same KG on load — mirroring the
   snapshot path's R51 operator restore. Re-attached via `atom_payload_set`
   for `op`/`premise`/`conclusion`.

3. **R60/R65 gloss**. Record:
   ```
   GLOSS <id> <gloss text...>
   ```
   Restored onto the atom's `gloss` payload after by-label resolution.

4. **Xref coactivation count (`XR_COACT`)** — gap D, both paths:
   - chat_state: the `XREF` record gains a trailing 7th field
     (`XREF <src_id> <dst_kg> <dst_id> <kind> <weight> <earned> <coact>`).
   - snapshot: each xref tuple gains a 6th element, serialized as the
     `kgs.atoms[N].xref[K].coact` key.
   Both restore via the new `xref_set_coact` accessor (added to
   `cross_kg_references.nova`) after rebuilding the xref with `xref_new` (which
   seeds coact to 0).

Sample serialized records:

- chat_state EMBED:  `EMBED 0 8 11 22 33 0 0 0 0 99`
- chat_state OP:     `OP 2 1 virus | infection`
- chat_state XREF:   `XREF 0 medicine 1 2 700 0 4`   (trailing `4` = coact)
- snapshot xref keys: `kgs.atoms[0].xref[0].coact 3`

### Shared encoding / reuse

- The deferred by-label resolution infrastructure already used for xrefs
  (`_cs_idlabel_record` / `_cs_idlabel_lookup`, `pending_*` accumulators) is
  reused for EMBED/OP/GLOSS — they all resolve in the same final pass once every
  KG's atoms exist.
- Operator and gloss on-disk semantics mirror the snapshot path (R51/R65).
- The coactivation accessor `xref_set_coact` is shared by both load paths.

## Consequences

- A chat `/save` + `/load` now round-trips embeddings, operator chains, glosses,
  and xref coactivation counts, so semantic search / forward-chaining / earned-
  link promotion behave the same after a reboot.
- The snapshot path also round-trips `XR_COACT` now (it was silently dropped),
  so earned-link progress survives a daemon snapshot too.
- File size grows by one EMBED line per non-zero-embedding atom (dims+2 ints) and
  one OP/GLOSS line per operator/glossed atom. Acceptable for the textual format
  (the header already flags a future binary layout for size).
- Strict backward compatibility: old chat_state files (no EMBED/OP/GLOSS, 6-field
  XREF) and old snapshots (no `.coact`) load unchanged — absent records default
  to empty embedding, no operator payload, no gloss, zero coactivation. No
  fields were reordered or removed; only records / trailing fields were added,
  guarded by presence/length checks.

## Honest gaps — what chat_state STILL drops vs the snapshot path after 0085

These are deliberately left and documented rather than half-persisted:

1. **LANG lexical fixture (`ltype = LWORD`).** The snapshot `kg_section_apply`
   re-installs `ltype=LWORD` (and re-derives the embedding) for LANG atoms so
   `is_word_atom` / `word_find` recognize them after load. The chat_state loader
   does NOT re-install `ltype`, so a restored LANG atom is not recognized by
   `word_find` (which gates on `is_word_atom`). The gloss DATA itself round-trips
   (it's restored onto the atom's payload and readable via `word_gloss`, which is
   payload-only), and the embedding now round-trips via the EMBED record — but
   the `ltype` marker is absent. Restoring it would require importing
   `word_atoms.nova` into `chat_state.nova` and re-deriving under the active
   embed mode; left for a follow-up to avoid scope creep and an import cycle.
   The new gloss test asserts on the atom payload directly to be honest about
   this.

2. **Word-sense xrefs auto-rebuild.** The snapshot path walks sibling KGs to
   re-attach word->concept sense xrefs (`_restore_word_senses`). chat_state
   relies purely on the explicit XREF records (which DO carry any sense xrefs
   that existed at save time), so it does not synthesize NEW sense edges on load.
   For a faithful round-trip this is equivalent; it differs only if the snapshot
   path would have minted senses the save did not capture.

3. **Provenance (`A_PROV`), created/updated/version timestamps.** Dropped by
   BOTH paths (never persisted). Not addressed here — would be a separate ADR;
   listed for completeness.

4. **Synapses / episodic / selfmodel sections.** Out of scope: chat_state is
   soul + multi-KG + decision-log only by design; those subsystems are the
   snapshot path's responsibility.

## Implementation Notes

- `src/persistence/chat_state.nova`:
  - `_cs_emit_kg`: emits EMBED (non-zero only), OP (by-label, ` | ` sentinel),
    GLOSS records, and appends the trailing coact field to XREF.
  - `_cs_collect_xref`: reads the optional 7th coact token (default 0).
  - New collectors `_cs_collect_embed` / `_cs_collect_op` / `_cs_collect_gloss`
    and resolvers `_cs_resolve_embeds` / `_cs_resolve_ops` / `_cs_resolve_glosses`
    (final-pass, by-label, never fatal on an unresolvable endpoint).
  - `chat_state_load_text`: new `pending_embeds`/`pending_ops`/`pending_glosses`
    accumulators, EMBED/OP/GLOSS dispatch branches, and the three resolver calls
    added alongside `_cs_resolve_xrefs`. A malformed EMBED/OP/GLOSS is a hard
    `PERSIST_ERR_PARSE` (consistent with ATOM/XREF/DLOG handling).
- `src/kg/cross_kg_references.nova`: added `xref_set_coact(x, c)`.
- `src/persistence/snapshot_disk.nova`: xref tuple gains a 6th `coact` element
  in both same-KG and cross-KG builders; serializer emits `.coact` when present;
  `_ensure_xref_tuples` pads a 6th slot; the from-text parser reads `.coact`;
  the third-pass xref restore applies it via `xref_set_coact`.
- Tests: `test_chat_state_persistence.nova` gains tests 21-25 (embedding,
  operator, xref coact, gloss, ADR-0085 back-compat). `test_snapshot_disk_full`'s
  `test_kg_section_xref_round_trip` now coactivates the causal edge and asserts
  the count survives the snapshot round-trip.
