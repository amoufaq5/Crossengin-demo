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

- `crossengin_daemon.nova` gossip-boot wiring (R5.2 defer): add the
  four Session slots + boot path + three env flags; call the hook from
  the idle-checkpoint branch at `:791`. Alternatively, land the call
  site inside `crossengin_fed_daemon.nova` when its own `snap_save` or
  equivalent save path exists.
- A `test_fed_daemon_attest` subtest exercising the hook via the daemon
  integration, once R5.2 ships.

Unrelated to this ADR: `_gossip_forward_bin_dtls` (ADR-0110 Phase P R4
defer, needs daemon-key-plumbing refactor), the real-socket DTLS
roundtrip (upstream), and the Phase R4 planner-driven payload (part of
the R-arc, not the M-arc).
