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
