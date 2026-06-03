# CrossEngin Snapshot Format

This document specifies the on-disk snapshot wire format (ADR-0048), the
version-bump policy that governs how it evolves, and the migration table
mapping older versions onto the current one.

## Version policy

CrossEngin snapshots carry a single integer version field (`ver`) at the
top of every file. The format version increments according to one rule:

* **MAJOR bump (SNAP_FORMAT_VERSION += 1)** — required when a field
  becomes MANDATORY, a field is REMOVED, a section's shape changes
  incompatibly, or the wire format changes in any way that an older
  reader cannot parse correctly. Each MAJOR bump ships with an explicit
  migration function (`snap_migrate_vN_to_v(N+1)`) and a corresponding
  entry in the migration table below.

* **MINOR addition (no `SNAP_FORMAT_VERSION` bump)** — allowed when
  fields are added OPTIONALLY: an older reader that doesn't recognize
  the new line names treats them as ignorable, and a writer that emits
  them stays compatible with both readers. Adding an optional field
  never requires a migration step.

The constants `SNAP_FORMAT_VERSION` (the current version) and
`SNAP_FORMAT_VERSION_MIN_SUPPORTED` (the oldest version we still know
how to migrate from) live in `src/persistence/snapshot_writer.nova`. A
reader that opens a file declaring a version newer than
`SNAP_FORMAT_VERSION` rejects it loudly — silently downgrading would
drop fields the file contains.

## Version history

### v1 — original line-oriented wire format

The format the system shipped with. Section blobs are emitted as
`key value\n` pairs; sections are SOUL, KGS, EPISODIC, SYNAPSES, and
SELFMODEL in mandatory order; the file ends with a literal `end` line.
The container header reads:

```
crossengin-snapshot v1
tag <int>
ver 1
instance <int>
timestamp <int>
sections 5
```

No metadata block. There's no way to know which build wrote the file,
when it was written, what compaction threshold was used, or whether the
content is encrypted.

### v2 — meta block (current)

Adds an OPTIONAL meta block immediately after the `sections` header,
before any section's `.present` line. Four new keys:

```
meta.creator <string>                # e.g. "crossengin/0.1.0"
meta.created_ns <int>                # creation timestamp in nanoseconds
meta.compaction_threshold <int>      # value used during write, -1 = unknown
meta.encryption <string>             # "none" or "chacha20-psk"
```

The block is optional on the wire — a v2 file that omits one or more
fields parses correctly, and the missing values default to the v1
migration recovery values (see the table below).

Sections are unchanged from v1. A v2 reader that opens a v1 file
transparently migrates via `snap_migrate_v1_to_v2`. A v1 reader that
opens a v2 file ignores the meta lines (they look like any other
`key val` pair the reader doesn't dispatch into a section).

The `meta.encryption` slot exists today as a placeholder for a future
encrypted-at-rest mode. The current implementation only emits `"none"`;
attempts to load a file with any other value will currently parse the
content as plain text (the encryption seam is not yet wired into
snap_save/snap_load — see ADR-0048).

## Migration table

| From | To | Function                | Recovery defaults                              |
|------|----|-------------------------|------------------------------------------------|
| v1   | v2 | `snap_migrate_v1_to_v2` | creator = `"unknown/<v1>"`                     |
|      |    |                         | created_ns = `0`                               |
|      |    |                         | compaction_threshold = `-1` (unknown)          |
|      |    |                         | encryption = `"none"`                          |
| v2   | v3 | `snap_migrate_v2_to_v3` | *(future: stub — no v3 fields landed yet)*     |

The reader (`snap_from_text` in `src/persistence/snapshot_disk.nova`
and `snap_parse` in `src/persistence/snapshot_reader.nova`) dispatches
on the `ver` field and calls the corresponding migration function in
the chain until the snapshot reaches `SNAP_FORMAT_VERSION`.

## Atom-shape schema evolution (R8E)

Separate from the snapshot **container** format above, CrossEngin's
**atom payloads** carry their own evolution layer: a per-atom-kind
schema generation that lets the substrate add / rename / retype /
remove payload fields without bumping `SNAP_FORMAT_VERSION`. The
schema layer is forward-compatible with the v2 container: it rides
on an optional meta line.

### Wire-format extension

A new optional line in the v2 meta block names the snapshot's
per-atom-kind schema generation:

```
schema.atoms_version <int>      # e.g. 3
```

A pre-R8E v2 file omits this line; the reader treats absence as
`SCHEMA_LEGACY_VERSION = 1` (the implicit shape every pre-R8E atom
has). A v2 reader that doesn't know about the line ignores it (same
forward-compat as the other `meta.*` lines).

### Per-atom payload field

Each atom carries a `schema_version` payload entry naming the schema
generation that produced it. An atom rehydrated from a pre-R8E
snapshot has no such entry and reads as `SCHEMA_LEGACY_VERSION` via
`atom_schema_version(a)`.

### Migration descriptor

A Migration is a 6-element list registered via
`register_migration(from_v, to_v, kind, op, field, default)`:

| Field      | Meaning                                              |
|------------|------------------------------------------------------|
| `from_v`   | atom schema version this migration starts from      |
| `to_v`     | the version the atom lands at after this step       |
| `kind`     | `ATOM_FACT` / `ATOM_CONCEPT` / ... or `SCHEMA_KIND_ANY` (-1) for kind-agnostic |
| `op`       | `SCHEMA_OP_ADD` / `RENAME` / `RETYPE` / `REMOVE`     |
| `field`    | payload key (for RENAME: `"old:new"`)                |
| `default`  | ADD: default value; RETYPE: transform tag (`SCHEMA_RETYPE_X1000`) |

The registry is module-state in `src/persistence/schema_migration.nova`.
New migrations are APPENDED; old migrations are NEVER mutated, so the
chain a snapshot from any historic build runs is bit-for-bit
reproducible across sessions.

### Demo migrations shipped today

| From | To | Kind        | Op     | Field                | Default        |
|------|----|-------------|--------|----------------------|----------------|
| 1    | 2  | `KIND_ANY`  | ADD    | `created_ns`         | 0 (or snapshot timestamp via `migrate_kg_with_default_ns`) |
| 2    | 3  | `ATOM_FACT` | RENAME | `label:display_label`| n/a            |

The first proves a kind-agnostic ADD; the second proves a
kind-specific RENAME (LANG / CONCEPT / SKILL atoms keep `label`).
REMOVE and RETYPE are exercised by unit tests via
`register_migration` + the synthetic ruleset escape hatch.

### Reader hook

After `snap_from_text` returns and the daemon's `kg_section_apply`
installs the live atoms, the next step is
`snap_post_load_migrate(s, kg_reg)`. It reads the snapshot's
`schema.atoms_version` (defaulting to `SCHEMA_LEGACY_VERSION`),
walks every KG in the registry, runs `migrate_atom` on each atom
up to `SCHEMA_CURRENT_VERSION`, and stamps the snapshot's
atoms_version slot so a subsequent `snap_save` emits the new
line.

### Migration tool

* **Explicit one-shot:** `examples/migrate_schema.nova` reads
  `$CE_MIGRATE_OLD`, applies the schema-migration chain, and writes
  `$CE_MIGRATE_NEW`. Reports:

  ```
  migrated atoms v1 -> v3 (N atoms across K KGs)
  written <bytes> bytes to <path>
  ```

* **Inline:** any caller that uses `snap_load + snap_save + the
  post-load migration hook` gets migrations applied transparently on
  load and persisted on the next save.

### See also

* `src/persistence/schema_migration.nova` — Migration descriptor,
  registry, ADD / RENAME / RETYPE / REMOVE ops, `migrate_atom`,
  `migrate_kg`, `snap_post_load_migrate`.
* `tests/unit/test_schema_migration.nova` — unit tests for the
  ADD / RENAME / RETYPE / REMOVE ops, chain, idempotency.
* `tests/integration/scenario_ll_schema_migrate.sh` — end-to-end
  test on a hand-rolled pre-R8E v2 snapshot.
* `examples/migrate_schema.nova` — the runnable schema-migration
  helper.

## Merkle-tree tamper detection (R15E)

Separate from the schema layer, CrossEngin's snapshot also carries an
**integrity commitment**: a SHA-256 Merkle tree over the KGS atom
records, with the root hash emitted as an optional v2 meta line. Any
single-bit edit to any atom flips the root with overwhelming
probability, so an operator can detect that a snapshot file on disk
has been tampered with (or corrupted by a partial-write bug). Combined
with R14F Ed25519 signing of the root, the next round will offer full
attestation; this round ships the Merkle root only and leaves signing
as follow-up.

### Wire-format extension

A new optional line in the v2 meta block names the snapshot's KGS-atom
Merkle root:

```
meta.merkle_root <hex>           # 64-char SHA-256 (lowercase hex)
```

A pre-R15E v2 file omits this line; the reader treats absence as
"no commitment was made" (so `/snap_verify` reports a friendly
"no Merkle commitment" line rather than a false-positive TAMPERED).
Other v2 readers that don't know about the line ignore it (same
forward-compat as the other `meta.*` lines).

### Algorithm

The tree follows the standard pair-and-hash recursion:

1. **Leaf hashes:** `leaf_i = SHA-256(canonical_atom_bytes_i)`, where
   the canonical form is a deterministic single-line ASCII rendering
   of the atom record:
   `"kg=<kg_label>|id=<id>|kind=<kind>|label=<label>|alpha=<alpha>|beta=<beta>"`.
2. **Tree construction:** pair adjacent nodes,
   `node = SHA-256(left_hash || right_hash)`. For an odd count at any
   level the last node is duplicated for pairing (Bitcoin convention).
3. **Root:** the single node remaining at the top of the recursion.
4. **Empty input:** the sentinel root is `SHA-256("")` —
   `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`.
5. **Single-leaf input:** root == leaf hash (no extra pair-and-hash;
   the Bitcoin convention).

The canonical serialization concatenates fields in a FIXED ORDER (kg,
id, kind, label, alpha, beta). The Merkle tree is order-sensitive at
the LEAF LEVEL too: reversing the atom list produces a different root.
This is by design — the snapshot writer commits to a specific atom
order and the reader recomputes against that same order. If we ever
wanted bag-of-atoms semantics, the writer would have to sort
canonically before hashing.

### Verification surfaces

Three call sites recompute and compare the root:

* **`/snap_verify [PATH]`** — explicit one-shot chat command. Loads
  the file, recomputes the root over the parsed KGS atoms, compares
  to the meta line, and prints `verified | TAMPERED | no Merkle
  commitment`.
* **`snap_load(path)` with `CE_SNAPSHOT_VERIFY_MERKLE=1`** — the
  normal rehydrate path becomes a tripwire. A mismatch returns the
  same 0 sentinel a parse failure already uses (so callers don't
  need a new error path) and prints a `(load FAILED: ...)` line.
* **`snap_verify_merkle(s)` / `snap_verify_path(path)`** — module-
  level APIs for any future federation-peer attestation surface.

### Inclusion proofs

`merkle_proof(atom_records, target_idx)` returns the list of sibling
hashes from the leaf at `target_idx` up to the root, each tagged with
its direction (left or right). A verifier with the proof, the
target atom, and the expected root can confirm membership in
O(log N) hash ops without seeing the rest of the tree — the property
that makes Merkle attractive for light clients, log shipping, and
federation. Today proofs are computed on demand and NOT persisted;
the wire format reserves room to add them later under a new optional
meta block.

### See also

* `src/persistence/merkle.nova` — Merkle module: local SHA-256
  (FIPS 180-4, byte-identical to noise_xk's), canonical atom
  serialization, `merkle_root`, `merkle_proof`,
  `merkle_verify_proof`, KGS-blob helpers, env-var hook.
* `tests/unit/test_merkle.nova` — unit tests covering the SHA-256
  primitive, canonical serialization, root edge cases (empty /
  single-leaf / two-leaf / three-leaf odd-duplication), inclusion
  proofs (length bound, in-tree verification, tamper detection on
  every input), determinism, and order sensitivity.
* `tests/integration/scenario_lll_merkle.sh` — end-to-end test:
  /save emits the meta line, /snap_verify on clean file reports
  verified, byte-flip in any atom flips the root, determinism on
  two saves of the same KG, pre-R15E snapshot reports "no
  commitment" rather than false-positive TAMPERED, env-var verify
  refuses to /load a tampered file.

## Migration tools

* **Inline (transparent):** `snap_load(path)` runs the migration chain
  automatically, so a v1 file on disk loads as a v2 snapshot in memory.
  The next `snap_save` (which the chat's `/save` and the daemon's
  checkpoint already invoke) rewrites the file in v2 shape.

* **Explicit (one-shot):** `scripts/migrate_snapshot.sh OLD.snap NEW.snap`
  reads the old file, runs the migration chain, and writes the migrated
  snapshot to a new path. Reports:

  ```
  migrated v1 -> v2 (NNN -> MMM bytes)
  ```

  Implementation: the shell wrapper invokes `examples/migrate_snap.nova`,
  which composes `snap_load + snap_save`. Uses env vars
  `CE_MIGRATE_OLD` and `CE_MIGRATE_NEW` because NOVA doesn't expose
  argc/argv to user programs — the same env-var pattern the rest of the
  codebase uses (`CE_SNAP_PATH`, `CE_DLOG_PATH`, etc.).

## Forward-compat notes

A reader that opens a file declaring a version newer than the build
supports (today: `ver 3` against `SNAP_FORMAT_VERSION = 2`) prints a
clear error and rejects the file:

```
(error: snapshot format v3 is newer than this build supports (max v2); upgrade required)
```

This is intentionally strict. Silently downgrading a future file would
drop fields the file contains, and there's no way for the reader to
know which fields are safe to ignore vs. load-bearing — that's a
contract the writer of the newer version must declare in its migration
function.

Writers that want to add a NEW optional field WITHOUT a major bump add
it under a new key (e.g. `meta.session_id`) and update the reader to
parse it with a default. Such a writer keeps `SNAP_FORMAT_VERSION` at
the same major (still v2 in the current example) — only a MAJOR bump
requires the migration table to grow.

## Incremental delta snapshots (R13F)

Separate from the full-snapshot container above, CrossEngin's
persistence stack now writes **incremental delta snapshots** as
sibling files next to the parent full snapshot. A delta records only
the operations (ADD / MOD / DEL of KG atoms) accumulated since the
parent was written, so a save costs O(changed) bytes instead of
O(KG-size) bytes. Periodic compaction collapses N deltas into a new
full snapshot and prunes the deltas.

### Storage layout

For a parent full snapshot at `/tmp/foo.snap`, deltas live at:

```
/tmp/foo.snap            -- parent full snapshot (v2 + R8E format)
/tmp/foo.snap.delta.000  -- first delta after parent
/tmp/foo.snap.delta.001  -- second delta
...
/tmp/foo.snap.delta.NNN  -- Nth delta (3-digit zero-padded so a glob
                            sorts lexically into apply order)
```

A reader walks `.delta.NNN` indices contiguously from 0 until the
first missing file, then stops. A gap in the sequence (caused by a
partial unlink) terminates enumeration — later deltas in the gap are
intentionally NOT applied to keep ordering invariants honest.

### Wire format (delta v1)

Line-oriented ASCII, similar to the R5D snapshot but TAB-separated
for op lines so a header `key SP val` line can never collide with an
`OP\tid\t...` op line:

```
crossengin-delta v1
timestamp <int_ns>
parent_snapshot <fingerprint>
operations <N>
ADD\t<id>\t<kg>\t<kind>\t<label>\t<alpha>\t<beta>
MOD\t<id>\t<kg>\t<field>\t<value>
DEL\t<id>\t<kg>
...
end_delta
```

* `timestamp` — nanosecond wall-clock when the delta was written.
* `parent_snapshot` — fingerprint of the parent (currently
  `<instance>:<timestamp>:<parent_byte_len>`). A delta with a
  fingerprint that does not match the parent at load time is
  REFUSED loudly — applying a delta written against snapshot A to
  snapshot B would silently corrupt B.
* `operations` — declared op count (informational; the reader
  counts from the actual op lines, not this header).

The trailer `end_delta` must be present. A delta missing the trailer
is treated as a partial write (e.g. mid-fsync crash) and silently
discarded by the reader.

### Op semantics

| Op | Reader action |
|----|---------------|
| `ADD` | Spawn the named KG (idempotent); if no atom with `label` exists, create one with `kind` + initial `alpha/beta`. If one DOES exist, refresh its belief (replace-by-label, matching R5D's `kg_section_apply` policy). |
| `MOD` | Look up the atom by id within the named KG; patch one of the known integer fields (`alpha`, `beta`). Unknown field names are SILENTLY skipped (forward-compat). |
| `DEL` | Look up the atom by id within the named KG; call `kg_remove_atom` (P2.4 tombstone — list slot stays, indexes are forgotten). |

Atoms targeted at an UNKNOWN KG label are SKIPPED (matches the same
soft-fail policy R5D's `kg_section_apply` uses for unknown-KG atoms).

### Compaction

`snap_delta_compact(parent_path, live_snap, max_deltas)` is the
operator-facing entry point:

1. Check the delta count for `parent_path`; if below `max_deltas`,
   return 0 (no-op).
2. Write `live_snap` as the new full snapshot at `parent_path` via
   `snap_save` (full crash-safe contract: write_tmp → fsync →
   atomic_rename → parent fsync).
3. Unlink every delta file; return the count unlinked.

The crash-safety contract: a crash at step (2) leaves the OLD parent
+ ALL deltas intact (rename hasn't landed yet); a crash mid-step-3
leaves the NEW parent + a partial subset of deltas, whose fingerprints
no longer match the new parent — so the next load drops them via the
fingerprint-mismatch path (loud rejection, not silent corruption).

### Schema-migration interop (R8E)

Deltas operate on atom OBJECTS, not on the snapshot's wire bytes, so
the parent's `schema.atoms_version` stamp travels through unchanged.
The post-load `snap_post_load_migrate` hook runs AFTER the delta-apply
pass and brings every atom — including delta-applied ones — up to
`SCHEMA_CURRENT_VERSION`. A delta whose parent was at schema v1 plus
a current-build reader produces the same migrated KG as a current-build
parent.

### R6F episodic preservation

Episodic moments / episodes / promoted atoms live in the EPISODIC
section of the parent snapshot. Deltas record only KG-section
mutations (ADD/MOD/DEL of atoms in the KGs section); episodic state
survives the delta round-trip because the parent's EPISODIC blob is
reloaded verbatim before deltas are applied, and the compaction
re-emits the live episodic blob as part of the new full snapshot.

### Performance characteristics

Measured on a 1000-atom KG (R13F bench, in
`tests/integration/scenario_fff_snap_delta.sh`):

| Op                            | Time           | Bytes      |
|-------------------------------|----------------|------------|
| Full snapshot write           | ~4 ms          | 152861     |
| Delta write (10 ADD ops)      | ~2.4 ms        | 523        |

The hot path is dominated by the fsync floor (~2 ms on tmpfs/ext4
on the test machine), so the delta speedup at 1000 atoms is ~1.6x.
At 5000 atoms — where serialize + write dominate the fsync floor —
the speedup climbs to ~3-4x (full ~13 ms vs delta ~3 ms). The
architecture scales linearly with KG size on the full path while
the delta path stays roughly constant per delta-op count.

### Compaction threshold (env-overridable)

`$CE_DELTA_COMPACT_THRESHOLD` (default 100) — the substrate's
compaction trigger. The R13F default mirrors the brief's "fold N
deltas into a fresh full" policy.

### See also (delta)

* `src/persistence/snapshot_delta.nova` — the R13F module:
  `delta_writer_*`, `delta_parse`, `delta_reader_apply`,
  `snap_parent_fingerprint`, `delta_path_for`,
  `delta_apply_all_for_parent`, `delta_prune_all`.
* `src/persistence/snapshot_disk.nova` — wire-up:
  `snap_make_delta_writer`, `snap_delta_save`,
  `snap_load_with_deltas`, `snap_delta_compact`,
  `snap_delta_count_for`.
* `tests/unit/test_snapshot_delta.nova` — 84 assertions covering
  the writer / parser / apply / compact / fingerprint-mismatch /
  schema-migration interop / episodic preservation surfaces.
* `tests/integration/scenario_fff_snap_delta.sh` — end-to-end
  benchmark + correctness scenario (14 assertions).

## See also

* `src/persistence/snapshot_writer.nova` — `SNAP_FORMAT_VERSION`, the
  meta block constants, and `snap_migrate_v1_to_v2`.
* `src/persistence/snapshot_disk.nova` — `snap_to_text` / `snap_from_text`
  (the wire format encoder/decoder + migration dispatch).
* `src/persistence/snapshot_reader.nova` — `snap_parse` (the framed-value
  parser + migration dispatch) and `snap_valid` (post-migration validity
  check).
* `examples/migrate_snap.nova` — the runnable migration helper.
* `scripts/migrate_snapshot.sh` — operator-facing shell wrapper.
* `tests/unit/test_snapshot_migrate.nova` — unit tests for the migration
  helper and the parser's version-dispatch path.
* `tests/integration/scenario_dd_snap_migrate.sh` — end-to-end test of
  the wrapper on a hand-rolled v1 fixture.
