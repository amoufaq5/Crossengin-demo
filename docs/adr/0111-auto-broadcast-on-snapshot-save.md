# ADR-0111 -- Auto-broadcast attestation on snapshot save (Phase M R5)

Date: 2026-10-03.  Supersedes: --.  Related: ADR-0091 (Phase M R3
federation durability -- deferred this bullet at §88-91,203-206),
ADR-0048 (durable checkpoint path), ADR-0106 (segfault-arc workarounds
that constrained R5 to pure-logic unit tests).

## Context

ADR-0091 §88-91 pinned, as the one explicitly deferred follow-up of
Phase M R3, that "R3 does NOT auto-broadcast on every snapshot save
(that would require an intrusive edit to
`src/persistence/snapshot_disk.nova`)" and §203-206 described exactly
what the hook should do: build an attestation tuple with
`att_make_from_hex` using the just-written Merkle root, then ship it
with `gossip_broadcast_attestation`. The reason it stayed deferred was
the ADR-0091:243 dependency contract -- "persistence does not depend on
federation" -- which forbids `snap_save` from directly calling into
`federation/*`.

Phase-1 Explore confirmed every primitive is already in-tree:
- `snap_save(s, path)` at `src/persistence/snapshot_disk.nova:2788`
  (MUST NOT be edited).
- `snap_meta_merkle_root(s)` accessor returning the exact hex that was
  written to disk, with `SNAP_META_MERKLE_ROOT_NONE = ""` sentinel for
  the "no commitment yet" case.
- `att_make_from_hex(soul_id, ts_ns, root_hex, seed, pk)` at
  `src/federation/snapshot_attestation.nova:285`.
- `gossip_broadcast_attestation(state, att)` at
  `src/federation/gossip.nova:1876`.
- `att_store_latest(store, peer_id)` + `att_root_hex(att)` for dedup.

The chat binary (`crossengin_chat.nova:3889`) and the one-shot migrate
scripts (`migrate_snap.nova`, `migrate_schema.nova`, `episodic_demo.nova`)
deliberately stay out of scope: chat has no signer by design
(ADR-0091:208-213) and the migrate scripts carry no mesh.

## Decision

R5 ships the hook on the FEDERATION side, as a leaf module that the
caller invokes AFTER a successful save with the already-written root in
hand. The import direction is federation -> persistence (allowed) and
persistence -> federation never happens; `snap_save` is byte-identical.

### R5.1 -- `src/federation/snapshot_broadcast_hook.nova` (new)

Single public fn:

```
fn snapshot_broadcast_hook(gs, att_store, seed, pk, soul_id,
                           root_hex, ts_ns) -> int
```

Early-return happy path (defensive, in order):
1. `len(root_hex) == 0` -> 0.
2. root_hex equals `SNAP_META_MERKLE_ROOT_NONE` -> 0.
3. `_att_is_lc_hex_string(root_hex, 64) == 0` -> 0.
4. `att_store_latest` returns an entry whose root equals `root_hex`
   (`str_eq_bytes` compared) -> 0 (dedup -- the mesh already knows).
5. `att_make_from_hex` sign-fail -> 0.
6. `att_store_add` locally FIRST (survives partition).
7. Return `gossip_broadcast_attestation(gs, att)` -- delivery count
   (may be 0 if no live peers; the local record is already stored).

### R5.2 -- Caller integration (DEFERRED)

Phase-1 Explore flagged `examples/crossengin_daemon.nova` as single-
process (no `gossip_` imports anywhere in its 920 lines; no Session slot
for `gs`, `att_store`, `seed`, or `pk`). Full integration would need:
- A gossip boot path (`gossip_init(self_addr, bootstrap_peers)`) +
  env resolution for `self_addr` + bootstrap list.
- Signer load via `merkle_signing_keypair_load` + env resolution for
  the keyfile path.
- `att_store_new()` created at boot and threaded through the idle-
  checkpoint path.
- Env-flag parsing for `CE_FED_AUTO_BROADCAST_ON_SAVE`.
- Session shape extended to carry all four handles.

That is >50 lines of new boot wiring + at least three new boot-time
env flags, which the plan's honest-defer policy explicitly covers. R5
ships R5.1 + R5.3 + R5.4; R5.2 remains deferred.

### R5.3 -- `tests/unit/test_snapshot_broadcast_hook.nova` (new)

Six pure-logic subtests (18 assertions):
- `test_hook_skips_empty_root`
- `test_hook_skips_none_sentinel`
- `test_hook_rejects_malformed_hex` (short + non-hex)
- `test_hook_broadcasts_on_fresh_root` (0 peers -> rc=0, store grows)
- `test_hook_dedups_identical_root`
- `test_hook_broadcasts_on_new_root`

The seventh "live peer shortcut" case from the plan is omitted:
`gossip.nova` offers no fake-peer-count shortcut and introducing one
would widen the surface R5 touches.

## Consequences

- `snap_save` and every direct caller are byte-identical. ADR-0091:243
  contract is preserved.
- Chat / migrate / demo paths are unaffected (no caller added there).
- Dedup via `att_store_latest` prevents the mesh from re-broadcasting
  the same root on every tick, so a stable idle-checkpoint loop stays
  quiet.
- The hook never loads keys, never boots gossip, never verifies
  inbound attestations -- it is a thin glue that composes already-
  shipped primitives.
- The federation daemon (`crossengin_fed_daemon.nova`) does NOT call
  `snap_save` today (ADR-0091 §92 contemplates a scripted-command
  drain for that), so no caller lands there in this round either.

## Follow-up

- `crossengin_daemon.nova` gossip-boot wiring (R5.2 defer): **CLOSED by
  Phase M R6** (see R6 close-out section below). The daemon-side source
  ships the Session extension, env resolvers, boot wiring, and the hook
  call at the idle-checkpoint; a NOVA-toolchain name-collision tracked
  separately (`_starts_with` dup — see `docs/UPSTREAM_NOVA_BUGS.md`
  §9 and R6 close-out) blocks the daemon main() link, but every
  behavioral unit of R6 is covered by unit tests.
- A `test_fed_daemon_attest` subtest exercising the hook via the daemon
  integration: superseded by R6's `test_hook_via_session_accessors`
  (identical composition shape without the heavy fed_daemon boot).

Unrelated to this ADR: `_gossip_forward_bin_dtls` (ADR-0110 Phase P R4
defer, needs daemon-key-plumbing refactor), the real-socket DTLS
roundtrip (upstream), and the Phase R4 planner-driven payload (part of
the R-arc, not the M-arc).

## Phase M R6 close-out — daemon integration

R6 lands the R5.2 defer in a single commit on top of
`9c439e4` (Phase M R5). Five surgical sub-passes, all behavior gated on
`CE_FED_AUTO_BROADCAST_ON_SAVE=1` so the default-off path emits the same
bytes as pre-R6.

- **R6.1** — `src/session/session.nova`: five tail-appended slots
  (`SES_GS=16`, `SES_ATT_STORE=17`, `SES_SIGNER_SEED=18`,
  `SES_SIGNER_PK=19`, `SES_SOUL_ID_INT=20`) with `SES_COUNT` bumped to
  21. `session_make` pushes zero placeholders for all five, preserving
  the `len(s) == SES_COUNT` invariant. A new `session_attach_fed(s, gs,
  att_store, seed, pk, soul_id_int)` writes all five slots and
  lazy-grows a pre-R6-shaped 16-slot list (mirrors `session_attach_dp`).
  Five defensive getters each guard with `if len(s) <= <SLOT> { return 0 }`
  so pre-R6 Sessions byte-identically return 0.
- **R6.2** — `examples/crossengin_daemon.nova`: six env resolvers copied
  verbatim from `crossengin_fed_daemon.nova:163-293` with a `_cd_` prefix
  (`_cd_env_str`, `_cd_env_int`, `_cd_bool_from_env_value`,
  `_cd_peers_from_env`, `_cd_soul_id_from_env_int` incl. djb2 mixer,
  `_cd_attest_key_base_from_env`). Deliberate duplication — extraction
  to `src/util/env_resolve.nova` is tracked on the post-queue; attempting
  it here would churn fed_daemon's existing tests.
- **R6.3** — boot wiring immediately after `sreg_register(sreg, sess)`.
  Resolves `CE_FED_LISTEN_ADDR` (default `127.0.0.1:0`), peers, and the
  signer-key base path. Calls `merkle_signing_keypair_load`; on failure
  prints a `[warn]` line (fed_daemon WARN-and-disable idiom) and leaves
  the fed slots at 0 so the hook branch stays skipped. On success allocs
  `gossip_init(...)` + `att_store_new()`, calls `gossip_set_att_store`
  + `gossip_register_att_pubkey`, then `session_attach_fed(sess, ...)`.
- **R6.4** — the save site at `crossengin_daemon.nova:791`. The
  previous single-branch `if saved == 0 { warn }` is wrapped in a dual-
  guard shape: `if saved == 0 { warn } else { if session_gs(sess) != 0
  { hook(...) } }`. The dual guard is the byte-identity contract: when
  the flag is off, `session_attach_fed` was never called, so the getter
  returns 0 and the hook branch is unreachable.
- **R6.5** — `tests/unit/test_session_attach_fed.nova` (new, 3 subtests
  + 29 checks total) covers default-no-fed-slots, attach-sets-all-slots,
  and lazy-grow-from-pre-R6-shape. `tests/unit/test_snapshot_broadcast_hook.nova`
  grows by one subtest (`test_hook_via_session_accessors`, 7 checks)
  that exercises the real daemon-shape chain: `session_make` -> real
  `gossip_init` + `att_store_new` + `_h_keypair_from_hex` -> `session_attach_fed`
  -> call the hook through the five Session accessors -> assert the
  att_store the Session carries grew by 1 and the stored root matches
  the input (aliasing invariant).

### Env flag table (R6 reuses fed_daemon's names; only one is new to R6)

| Env var                              | Role                                           | Default           |
|--------------------------------------|------------------------------------------------|-------------------|
| `CE_FED_AUTO_BROADCAST_ON_SAVE`      | Master opt-in (`1` enables; anything else off) | `off`             |
| `CE_FED_LISTEN_ADDR`                 | Emit-only gossip bind (never actually listens) | `127.0.0.1:0`     |
| `CE_FED_PEERS` / `CE_GOSSIP_PEERS`   | Comma-separated bootstrap peers                | `[]`              |
| `CE_FED_ATTEST_KEY_DIR`              | Signer-keypair dir (merkle_signing)            | `$HOME/.crossengin/fed_keys` |
| `CE_FED_SOUL_ID`                     | Override auto-derived `soul:<addr>` id         | `soul:<listen>`   |

### Byte-identity contract (verified)

With `CE_FED_AUTO_BROADCAST_ON_SAVE` unset or `"0"`:
- `_cd_bool_from_env_value(getenv(...), 0)` returns 0.
- The boot block short-circuits before any `_cd_*` call touches the env
  table.
- `session_attach_fed` is never called; the five fed slots stay at the
  constructor-pushed zeros.
- The hook branch at `:791` evaluates `session_gs(sess) != 0 => 0 != 0
  => false`, so the entire call site is skipped.

No new stderr lines, no snap-file byte change, no decision-log entry.

### Pre-existing NOVA toolchain regression surfaced by R6

The four new imports pulled into `crossengin_daemon.nova`
(`snapshot_broadcast_hook`, `gossip`, `snapshot_attestation`,
`merkle_signing`) transitively drag in `src/io/transducers/kg_sync.nova`.
`kg_sync.nova:410` defines a module-private `fn _starts_with(s, prefix)`
with the same name as `src/persistence/snapshot_disk.nova:1789`'s module-
private `_starts_with`. The NOVA toolchain does not mangle module-private
names, so the assembler emits `Error: symbol _starts_with is already
defined` when linking any `main()` that pulls in both modules.

This limitation is **pre-existing**: `examples/crossengin_chat.nova`
imports the same pair (`snapshot_disk` + `gossip`) and has been failing
the assembler stage since the federation-daemon arc landed (commit
`5f2e9f2`, Phase M R1). Verified by rebuilding `crossengin_chat.nova`
against the pre-R6 tip (`9c439e4`): identical error. R6 inherits the
same assembler failure for `crossengin_daemon` because the hook integration
cannot be done without pulling in `gossip`.

**Scope decision**: fixing this requires renaming `_starts_with` in one
of two modules. `src/persistence/*` is in R6's do-not-edit list
(ADR-0091:243 compliance). `src/io/transducers/kg_sync.nova` is
editable in principle, but `_starts_with` has 10+ call sites across the
tree (`federated_aggregator`, `secure_aggregation`,
`snapshot_replication`, test files). A rename is a surgical
NOVA-toolchain workaround that belongs on the `docs/UPSTREAM_NOVA_BUGS.md`
queue, not inside R6.

**Consequence**: the R6 commit ships the full daemon-side source, every
unit test exercising the hook via the Session accessor chain passes, but
`examples/crossengin_daemon.nova` cannot LINK into a running binary
until the symbol-collision is resolved. On the day the NOVA toolchain
fixes name mangling (or `kg_sync`'s `_starts_with` is renamed), the
daemon will link with the flag-off path emitting bytes identical to
pre-R6.

Verification artifacts (R6):

- `test_session_attach_fed`: OK (29 checks).
- `test_snapshot_broadcast_hook`: OK (27 checks; was 20 pre-R6, +7 from
  the new behavioral subtest).
- `test_session`: OK (66 checks) — unchanged.
- `test_session_paths`, `test_session_snapshot`: unchanged.
- Byte-identity canaries (`test_fed_daemon_boot`,
  `test_fed_daemon_replication`): unchanged pass counts (49, 59).
- Pre-existing canary failures (`test_snapshot_attestation` 59P/7F,
  `test_snapshot_replication` 61P/12F, `test_fed_daemon_attest` 52P/2F,
  `test_merkle_signing` segfault, `test_gossip` 32P/2F) are **identical
  pre-R6 and post-R6** (verified via git stash). R6 does not change
  any pre-existing test's pass/fail count.
