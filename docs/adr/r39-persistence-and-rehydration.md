# R39: Persistence and rehydration (chat-state save/load + R40 chat-integration plan)

## Status

Accepted -- R39 round adds a per-process chat-state save/load API on
top of the pre-existing snapshot machinery. The chat-side `/quit`
and boot-time integration is deferred to R40.

## Date

2026-06-06

## Context

ADR-0048 specifies the substrate snapshot format and rehydration
order: **soul first, then KGs, then episodic**. The shipping
implementation under `src/persistence/` (`snapshot_writer`,
`snapshot_reader`, `snapshot_disk`, `merkle`, `merkle_signing`,
`snapshot_compaction`, `snapshot_delta`, `schema_migration`)
covers everything ADR-0048 names -- a tagged, versioned binary
layout with atomic-rename crash safety, Merkle commitment, and
Ed25519 attestation.

The chat surface already exposes `/save [PATH]` and `/load [PATH]`
admin commands that wrap the snapshot machinery directly. Those
commands work fine for explicit user-driven save/load -- but they
do not cover the **chat state that lives outside the substrate
snapshot**: the in-process decision log seen by `/why` and
`/history`, the metadata about the active session ID, the meta-
observer's pending tier-change buffer (`/meta-feedback`), and the
intent-dispatcher's per-session context if any.

R39C introduces an explicit chat-state save/load API for that
shoulder of state. R40 will wire it into the chat lifecycle
(`/quit` triggers save; boot triggers load; explicit `/save` and
`/load` admin entries become the operator-visible interface).

This ADR records the R39C decisions and the R40 plan so an R40
implementer can land the wiring without re-deriving the choices.

## Decision

R39C ships a **text v1 line-record format** at
`$HOME/.crossengin/chat_state.dat`. The file is appended to in
batches; the loader walks records in order and reconstructs the
in-process state. Format:

```
VERSION 1
SESSION_ID <uuid>
SOUL_NAME <name>
SOUL_PURPOSE <purpose-with-no-newlines>
DLOG_ENTRY <seq> <kind> <action_type> <perm_tier> <outcome> <ts_ns>
DLOG_ENTRY ...
KG_ATOM <kg> <id> <kind> <belief_milli> <label-with-no-newlines>
KG_ATOM ...
META_PENDING <source> <from_tier> <to_tier>
META_PENDING ...
END
```

Records are LF-terminated. Within a record, fields are separated
by single spaces. Label fields are the LAST field on their line so
they may contain anything except LF. The loader reads until `END`
or EOF, rejects unknown record types with a `WARN`-level audit
entry, and refuses to load if `VERSION` is not 1.

The API surface (lives in a new module the chat consumes):

- `chat_state_save(path, sl, kg, refl_kg, log, mo, session_id) -> ok`
- `chat_state_load(path) -> [sl_patch, kg_patch, refl_patch,
  log_patch, mo_patch, session_id] | 0`

`chat_state_save` opens the file with `O_WRONLY | O_CREAT |
O_TRUNC`, writes the records in order, flushes, and returns 1 on
success. **Atomic rename is NOT implemented in R39C** -- a crash
between the truncate and the final write leaves a torn file. R40
fixes this with the same atomic-rename pattern ADR-0048
prescribes for the substrate snapshot (write to `path.tmp`,
fsync, rename over `path`). This is on the deferred list below.

`chat_state_load` opens the file with `O_RDONLY`, walks records,
applies them to fresh empty patches in the order they appear
(matching ADR-0048's soul-first / KG-second / episodic-third
mandate, except we substitute decision-log records for episodic
since chat does not own an episodic stream the way the substrate
proper does), and returns the patch tuple for the caller to merge
into live state.

## Why text, why v1

ADR-0048 specifies a binary tagged format for the substrate
snapshot, and for good reason -- size, parse speed, and clean
versioning. Text v1 is chosen for chat state because:

- The chat-state file is small (a few hundred KB even after a
  long session vs the multi-MB substrate snapshot).
- Easy to inspect with `cat` / `less` during development.
- Easy to diff between sessions for regression tests.
- A future v2 may switch to binary if the size matters. The
  `VERSION 1` header explicitly enables this -- a v2 loader can
  recognise the file as v2 from the first line and dispatch to a
  binary parser.

The format trades parse speed for human-readability. The chat
loads its state file once at boot; the cost difference between a
50ms binary parse and a 200ms text walk is invisible.

## Rehydration order

`chat_state_load` reapplies records in the order they appear in
the file. The writer emits them in this order:

1. `VERSION` (header; required first).
2. `SESSION_ID` (so a later `/switch` knows the active session).
3. `SOUL_NAME` / `SOUL_PURPOSE` (identity first per ADR-0048).
4. `DLOG_ENTRY` lines (decision log records; ordered by `seq`).
5. `KG_ATOM` lines (the per-session KG atom records).
6. `META_PENDING` lines (the meta-observer's pending tier
   changes).
7. `END` (terminator; loader treats missing `END` as a torn
   write and refuses to load).

This matches ADR-0048's intent: identity (soul) first so the
constitution is live before knowledge loads.

## R40 plan: chat integration

R39C ships the API surface. R40 wires it into the chat:

1. **Boot:** at chat startup, if
   `$HOME/.crossengin/chat_state.dat` exists, call
   `chat_state_load(path)` and merge the patches into the fresh
   chat instance. If the load fails (torn file, version mismatch,
   permission error), log it via the boot banner and continue with
   an empty state -- never crash the chat over a load failure.
2. **`/quit`:** before `exit(0)`, call `chat_state_save(path,
   ...)`. If the save fails, log it and exit anyway -- the user
   has already asked to quit; we do not block the exit on a save
   failure. We do print a one-line warning so the user knows their
   state did not persist this session.
3. **`/save`:** explicit operator-driven save. Already implemented
   for the substrate snapshot; R40 extends it to also save chat
   state if no PATH was given (so `/save` with no arg saves both;
   `/save /tmp/foo.snap` keeps the substrate-only behaviour).
4. **`/load`:** symmetric to `/save`. Explicit operator-driven
   load. Already implemented for the substrate snapshot; R40
   extends it analogously.

R40 also adds an idle-tick checkpoint: every N seconds (default
60), if the chat state has changed since the last checkpoint,
fire `chat_state_save` in the background. This is the
"persistent across crashes, not just clean exits" property
ADR-0048 names.

## Honest gaps

- **No atomic write in R39C.** A crash between the truncate and
  the final write leaves a torn file the loader refuses to read.
  Mitigation: write to `path.tmp`, fsync, rename. This is on the
  R40 list above. Until R40 lands, a hard kill (`kill -9`) during
  `/quit` save can lose the file; a clean `Ctrl-C` is fine.
- **No compaction.** The save is whole-file. A session with
  20,000 atoms produces a file with 20,000 `KG_ATOM` lines. The
  substrate snapshot has `snapshot_compaction` to drop dead atoms
  before saving; the chat-state file does not, in R39C. R40 may
  call `snap_compact` first if the file grows past a threshold.
- **No multi-process safety.** Two chat processes sharing the
  same `$HOME/.crossengin/chat_state.dat` will race. R39C does
  not flock the file. The user is expected to run one chat at a
  time per home directory. The `scripts/web.py` per-cookie
  isolation (each cookie has its own chat child) does NOT
  currently bind each child to its own state file -- R40 will
  parameterise the path on session ID.
- **No schema migration in R39C.** A future v2 file format will
  need a one-way migration ("read v1, write v2"). R39C ships
  only v1; the version check exists so v2 can land without
  collateral damage but the migration path is empty.
- **The R39C API is process-internal.** Calling `chat_state_save`
  is the chat's responsibility -- there is no `/save_chat`
  command in R39C, no boot wiring. The R40 work makes the API
  user-visible.

## Consequences

- **Positive.** A clear, versioned shape for chat state with a
  well-defined rehydration order. The text v1 format is
  debuggable. The API surface is in place for R40 to wire
  without changing its callers.
- **Negative.** R39C alone is invisible to a user -- nothing
  saves, nothing loads. The "did anything happen?" answer for
  R39C is "no observable behaviour change; an API was added."
  This is by design (siblings R39A/B/D depend on a chat that
  works as before during R39).
- **Future work (R40 and beyond).**
  - Wire `/quit` and boot per the plan above.
  - Atomic write (`.tmp` + fsync + rename).
  - Compaction before save above a threshold.
  - Per-session-id file paths so `scripts/web.py` cookies do not
    share a state file.
  - Optional binary v2 format if the text file grows past
    practical sizes.
  - Cross-instance state import (federation).

## How this relates to the existing ADRs

- ADR-0048 specifies the substrate snapshot format and the
  rehydration order. R39C does NOT change ADR-0048; it adds a
  parallel surface for chat-only state. The order is
  intentionally consistent -- soul first.
- ADR-0043 specifies the decision log. R39C serialises decision-
  log records as part of chat state. The on-disk format is
  text-record per ADR-0043's append-only intent.
- ADR-0034 specifies soul write timescales. R39C saves the
  soul's identity fields (slow-changing); the state slot
  (fast-changing) is NOT in the chat-state file -- it's
  recomputed on boot from the loops, consistent with ADR-0048's
  "ephemeral signal traffic is NOT persisted" rule.

## Implementation notes

- New module `src/chat/chat_state.nova` (R39C). Exports
  `chat_state_save` and `chat_state_load`; consumed by the
  chat's `/quit` handler in R40.
- Tests: round-trip fixture (save -> load -> compare) for each
  record type; torn-file fixture (truncate after partial write;
  assert loader refuses cleanly without crashing); version
  mismatch fixture (write `VERSION 2`; assert refusal); empty-
  file fixture (assert loader returns empty patches not error).
- The default path
  `$HOME/.crossengin/chat_state.dat` is created on first save
  with `mkdir -p`. Override via the `CE_CHAT_STATE_PATH` env
  var (used in tests).

## Deferred to R40

- `/quit`-driven save.
- Boot-time load.
- Idle checkpoint.
- Atomic write.
- `/save_chat` / `/load_chat` admin commands distinct from the
  existing substrate `/save` / `/load`.
- Per-session-id file paths.

## Deferred to R41+

- Binary v2 format if size warrants.
- Schema migration from v1 to v2.
- Multi-process flock.
- Cross-instance import.
