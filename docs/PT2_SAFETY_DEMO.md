# Phase 1 pt2 — verify-on-load demo

Phase 1 pt2 (shipped in PR [#21](https://github.com/amoufaq5/Crossengin-demo/pull/21)) wires `snap_verify_signature` into the `/load` path and into the broader snapshot reader. The `docs/END_TO_END.md` transcript didn't exercise it — this one does.

The demo shows three scenarios:

1. **Save with signing enabled** — `CE_SNAPSHOT_SIGN_KEY` set → the writer stamps a `meta.merkle_signature` line over the recomputed Merkle root.
2. **Load verified** — `CE_SNAPSHOT_VERIFY_PUBKEY` set → the reader recomputes the Merkle root over the KGS section, verifies the signature under the trust-anchor pubkey, load succeeds.
3. **Load tampered** — change one atom label in the KGS section → the recomputed root no longer matches the on-disk signature under the trusted pubkey → load **refused**.

Phase 1 pt2 pushed the verify primitive; Phase 1 pt1's cap gate (`CAP_DELETE` on `/load`) wraps it so every load — tampered or not — attests to `/__safety__`.

## 1. Generate the keypair

`scripts/snap_keygen.sh` wraps `openssl genpkey -algorithm Ed25519` + DER byte extraction to write the raw-32-byte priv + pub files `merkle_signing.nova` expects.

```
$ scripts/snap_keygen.sh /home/user/crossengin_test_keys/snap_key
wrote /home/user/crossengin_test_keys/snap_key.priv (32 bytes, 0600)
wrote /home/user/crossengin_test_keys/snap_key.pub  (32 bytes, 0644)

To use:
  export CE_SNAPSHOT_SIGN_KEY=/home/user/crossengin_test_keys/snap_key.priv       # sign on /save
  export CE_SNAPSHOT_VERIFY_PUBKEY=/home/user/crossengin_test_keys/snap_key.pub   # verify on /load
```

## 2. Save a signed snapshot

```
$ export CE_SNAPSHOT_SIGN_KEY=/home/user/crossengin_test_keys/snap_key.priv
$ ./bin/crossengin-chat
> /save /home/user/crossengin_test_keys/test.snap
(saved soul=Aurora kg=584 atom(s) + lang=553 atom(s) + 0 moment(s) + 0 syn(s) + 0 competence record(s) -> /home/user/crossengin_test_keys/test.snap durably)

> /snap_sign_status /home/user/crossengin_test_keys/test.snap
(snap_sign_status /home/user/crossengin_test_keys/test.snap: signature=present pubkey=set last_verify=verified)
```

The snapshot file now carries a `meta.merkle_signature` line:

```
$ grep "^meta" /home/user/crossengin_test_keys/test.snap
meta.creator crossengin/0.1.0
meta.created_ns 0
meta.compaction_threshold -1
meta.encryption none
meta.merkle_root 72c920ac55dd5500735bb80b4152e258d7c32bfd2b118cbbec11118bbe530e64
meta.merkle_signature cb97054d5e53408ca1d89e71e16a76bffb7d0244cc74b142fecd8da9009b97709b67b3ebc7788b9a3ceefe19ac415235524101f5a48eee5939855d3dd19c980c
```

128 hex chars = 64-byte Ed25519 signature, over the SHA-256 root recomputed from the KGS section's atom records.

## 3. Load verified (pubkey matches)

```
$ export CE_SNAPSHOT_VERIFY_PUBKEY=/home/user/crossengin_test_keys/snap_key.pub
$ cp /home/user/crossengin_test_keys/test.snap /home/user/crossengin_test_keys/test_good.snap
$ ./bin/crossengin-chat
> /load /home/user/crossengin_test_keys/test_good.snap
agent> would like to load snapshot: /home/user/crossengin_test_keys/test_good.snap. approve? [y/N/why]
> y
(loaded /home/user/crossengin_test_keys/test_good.snap: ver=2 instance=1 ts=0)
  reasoning KG: 584 -> 584 atoms
  language KG : 553 -> 553 atoms

> /__safety__
safety_attestations=1
  #0 attest delete -> allow
```

Phase 1 pt1's cap gate prompts first (`CAP_DELETE` on `/load`); `y` grants it; `snap_load` internally recomputes the root, verifies the signature under the trust-anchor pubkey, succeeds; the load applies.

## 4. Load tampered (KGS section changed, signature stale)

Simulate an attacker who edits the atom-store contents in the file without the signing key. Flip one atom's label:

```
$ cp /home/user/crossengin_test_keys/test.snap /home/user/crossengin_test_keys/test_tampered.snap
$ sed -i '0,/kgs.atoms\[0\].label self/s//kgs.atoms[0].label evil/' /home/user/crossengin_test_keys/test_tampered.snap
$ grep "kgs.atoms\[0\].label" /home/user/crossengin_test_keys/test_tampered.snap
kgs.atoms[0].label evil

$ ./bin/crossengin-chat
> /load /home/user/crossengin_test_keys/test_tampered.snap
agent> would like to load snapshot: /home/user/crossengin_test_keys/test_tampered.snap. approve? [y/N/why]
> y
(load FAILED: Merkle signature mismatch -- snapshot /home/user/crossengin_test_keys/test_tampered.snap is TAMPERED, the on-disk signature does not match the recomputed root under the trusted pubkey)
(load FAILED: /home/user/crossengin_test_keys/test_tampered.snap missing, unreadable, or not a snapshot)

> /__safety__
safety_attestations=1
  #0 attest delete -> allow
```

**Refused.** The operator approved the load, but the integrity check inside `snap_load` caught the tamper and refused. The attestation records `delete → allow` (approval granted) rather than `delete → deny` because the gate fired before the verify — the refusal was downstream of the cap decision. This is intentional: an operator who cheerfully approves every load of a tampered file still can't actually load it.

## 5. What the sig covers + what it doesn't

The Merkle root is recomputed over the **KGS section's atom records only** (see `merkle_root_for_kgs_blob` in `src/persistence/merkle_signing.nova`). That means:

- **Caught**: atom label changes, atom belief changes, atom-kind changes, atom added/removed, atom-id rewrite.
- **NOT caught**: soul-section edits (name / purpose / OCEAN scores), episodic-section edits, synapse-section edits, selfmodel edits. These sections are *outside* the signed blob by design — the soul can be reseeded without re-signing the KG — but that's a trust tradeoff worth being aware of.

A future pt3 extension could stamp a second Merkle root over the soul+episodic+synapse blob, or an outer signature over the whole snapshot text, but neither ships today.

## 6. Interaction with `CE_SNAPSHOT_REQUIRE_SIGNATURE`

Setting `CE_SNAPSHOT_REQUIRE_SIGNATURE=1` makes an un-signed snapshot refuse to load, even when `CE_SNAPSHOT_VERIFY_PUBKEY` is set:

```
$ export CE_SNAPSHOT_REQUIRE_SIGNATURE=1
$ unset CE_SNAPSHOT_SIGN_KEY        # save WITHOUT a sig
$ ./bin/crossengin-chat
> /save /home/user/crossengin_test_keys/unsigned.snap
(saved ... -> /home/user/crossengin_test_keys/unsigned.snap durably)
> /load /home/user/crossengin_test_keys/unsigned.snap
agent> would like to load snapshot: ...  approve? [y/N/why]
> y
(load FAILED: ... carries no meta.merkle_signature line, but CE_SNAPSHOT_REQUIRE_SIGNATURE=1)
```

Default (env unset / `=0`) is **lenient**: unsigned snapshots proceed with a warning, so dev builds without a pubkey configured still work.

## 7. Phase / PR cross-reference

| Component | Phase | PR |
|---|---|---|
| `snap_verify_signature` + `merkle_signing_*` primitives | pre-session | — |
| `_admin_load` wraps through `_gate_or_prompt(CAP_DELETE, ...)` | Phase 1 pt1 | [#21](https://github.com/amoufaq5/Crossengin-demo/pull/21) |
| `_admin_load` consults `snap_verify_signature` when `CE_SNAPSHOT_VERIFY_PUBKEY` is set | Phase 1 pt2 | [#21](https://github.com/amoufaq5/Crossengin-demo/pull/21) |
| `scripts/snap_keygen.sh` | this PR | — |
| This walkthrough doc | this PR | — |

## 8. Rollback of the demo

Doc + script are additive. Removing `scripts/snap_keygen.sh` leaves the Phase 1 pt1 + pt2 primitives in place; `/save` and `/load` continue to work unsigned without any env set. Signed snapshots remain verifiable with any 32-byte Ed25519 keypair the operator produces via openssl (or a NOVA tool using `ed25519_keygen`).
