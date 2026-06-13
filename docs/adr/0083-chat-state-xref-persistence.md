# ADR-0083: Persist cross-KG references (xrefs) in the chat_state format

## Status

Accepted — the chat session save/load path (`chat_state_save*` /
`chat_state_load*`) now serializes and restores each atom's cross-KG
references (ADR-0017 xrefs), bringing it to parity with the disk-snapshot path
(ADR-0077/0078) for both SAME-KG and CROSS-KG edges. Old chat_state files
without xref records still load (back-compat, zero xrefs).

## Date

2026-06-13

## Context

ADR-0077 and ADR-0078 added xref (cross_kg_references) persistence + restore to
the DISK SNAPSHOT path (`src/persistence/snapshot_disk.nova`): each atom's
xrefs are emitted as `kgs.atoms[i].xref[j].*` key/value lines and re-resolved
BY LABEL on apply, so same- and cross-KG edges round-trip.

The production chat/save path uses a DIFFERENT, lighter line-oriented
"chat-state v1" serialization (`src/persistence/chat_state.nova`). That format
emitted `ATOM`/`TRIPLE`/`DLOG_ENTRY` records but had no concept of xrefs:
`_cs_emit_kg` never read `atom_xrefs(a)`, and `chat_state_load_text` had no
branch to reconstruct them. Consequently a chat `/save` followed by `/load`
silently dropped EVERY cross-KG reference — the snapshot path was xref-complete
while the chat path was not. This ADR closes that gap.

## Decision

Extend the chat-state v1 format with a new per-atom record type, emitted INSIDE
each `KG_BEGIN`/`KG_END` block after the `ATOM` lines:

```
XREF <src_id> <dst_kg_label> <dst_id> <kind> <weight> <earned>
```

- `src_id` / `dst_id` are the ON-DISK atom ids written in the `ATOM` records of
  this file. The enclosing `KG_BEGIN` block names the src KG; `dst_kg_label`
  names the dst KG (a SAME-KG edge stores this KG's own label, so the cross-KG
  case round-trips identically to the snapshot path's `.dstkg` field).
- `kind` / `weight` / `earned` mirror exactly the three xref fields ADR-0077/0078
  persist in the snapshot path (`xref_kind`, `xref_weight`, `xref_earned`).

Restore mirrors snapshot_disk's third-pass strategy. Atom ids are not stable
across a replace-by-label load, so endpoints are re-resolved BY LABEL after
every KG's atoms exist:

1. While parsing `ATOM` lines, record a per-KG `on-disk-id -> atom-label` map.
2. Collect each `XREF` line into a pending list (with its src KG label).
3. After the parse loop, `_cs_resolve_xrefs` maps each endpoint id back to its
   label, looks up the live src/dst atoms via `kg_find`/`kg_find_atom`, and
   reconstructs the edge with `atom_add_xref(src, xref_new(src, dst, kind,
   weight, earned))` — the same constructor the snapshot path uses.

Serializer (`chat_state.nova`):
- Added `import "../kg/cross_kg_references.nova"`.
- Extended `_cs_emit_kg` with a second pass over the KG's atoms that emits one
  `XREF` line per `atom_xrefs(a)` entry.

Parser (`chat_state.nova`):
- Added helpers `_cs_collect_xref`, `_cs_idlabel_record`, `_cs_idlabel_lookup`,
  `_cs_resolve_xrefs`.
- `chat_state_load_text` now tracks the current KG label, records id->label per
  `ATOM`, handles the `XREF` record (hard `PERSIST_ERR_PARSE` on a malformed
  shape, consistent with `ATOM`/`DLOG_ENTRY`), and calls `_cs_resolve_xrefs`
  before returning.

## Consequences

- Chat `/save` + `/load` is now xref-complete: same-KG and cross-KG references
  survive a restart, matching the snapshot path's fidelity.
- BACK-COMPAT: an old chat_state file with no `XREF` records leaves the pending
  list empty, so restore is a no-op and every atom loads with zero xrefs — no
  crash, no behavior change. (Covered by a dedicated test.)
- FORWARD-COMPAT preserved: `XREF` is a known record type within VERSION 1; an
  older reader that predates this change still SKIPs the unknown `XREF` line
  per the format's documented forward-compat contract.
- A malformed `XREF` line (wrong field count) is a hard `PERSIST_ERR_PARSE`,
  matching how `ATOM` and `DLOG_ENTRY` malformed records are handled.

## Honest gaps (what the chat_state format STILL drops vs the snapshot path)

These pre-existed this ADR and are unchanged by it — the chat ATOM format is
deliberately lighter than the snapshot's full atom record:

- **xref co-activation count (`xref_coact` / XR_COACT).** NOT persisted by
  EITHER path. `xref_new` re-initializes coact to 0, and both the snapshot
  tuple `[dst_kg, dst_label, kind, weight, earned]` and this XREF record omit
  it. So the two paths are CONSISTENT here, but a restored earned-in-progress
  edge loses its accumulated coactivations in both.
- **Atom embeddings, payload keys, provenance, version, created/updated
  timestamps, operator premise/conclusion, and the R65 dictionary gloss.** The
  snapshot path persists these (operator fields, gloss); the chat ATOM record
  carries only `id/kind/alpha/beta/label`. This ADR did NOT add them — it only
  closed the xref gap. A chat-loaded atom therefore has an empty embedding and
  no payload/gloss. (Cross-KG *similarity* recompute after load will re-derive
  weights from embeddings, which are absent here — but the stored weight is
  preserved verbatim, so the restored edge is faithful to what was saved.)
- **Word-sense xref de-dup nuance.** The snapshot path has a dedicated
  `_restore_word_senses` pass plus a `_has_xref_kind_to` idempotency guard so a
  double-load never grows the xref count. The chat path restores from a fresh
  registry on each load (not an incremental apply onto a live graph), so a
  single load attaches each XREF exactly once; this ADR did not add an
  idempotency guard because the chat load contract rebuilds, rather than
  merges into, the registry.

## Implementation Notes

- Endpoints are resolved BY LABEL (not by id) to match snapshot_disk and to
  survive the chat format's replace-by-label atom install. The per-file
  id->label map makes the id-carrying `XREF` record exact even though live atom
  ids are reassigned on load.
- KG labels are assumed single-token (no spaces) — true throughout this
  codebase (e.g. `medicine`, `reasoning`, `language`). Atom labels MAY contain
  spaces and are handled correctly because they are never written into the
  `XREF` line; only the integer on-disk ids and the (single-token) dst KG label
  are. If a KG label ever contained a space, the `XREF` record would need a
  key/value encoding like the snapshot path.
- Tests added to `tests/unit/test_chat_state_persistence.nova`:
  `test_round_trip_xrefs` (same-KG + cross-KG edge round-trip, asserting dst kg
  / dst atom id / kind / weight / earned / src endpoint),
  `test_xref_backcompat_no_records` (old file with no XREF -> zero xrefs, no
  crash), and `test_xref_malformed_returns_parse` (truncated XREF ->
  PERSIST_ERR_PARSE). Suite grew from 88 to 118 checks.

## ADRs referenced

- ADR-0017 (multi-KG cross-references)
- ADR-0077 (persist SAME-KG general xrefs across a snapshot)
- ADR-0078 (persist CROSS-KG general xrefs across a snapshot)
