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
