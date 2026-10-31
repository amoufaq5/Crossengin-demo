# ADR-0203: Mother/Child Factory Runtime

## Status

Proposed. Realizes the bake pipeline promised by ADR-0200
Sub-decision 5. Defines the BakeManifest schema, the filtered
snapshot mechanics that produce a child bundle, the signing pattern
extended from R54.2 skill signing to whole bundles, and the KG-delta
update channel that keeps a deployed child current. Every primitive
this ADR composes already exists in tree; the work is wiring, not
invention. Roadmap R95-R100.

## Date

2026-08-22

## Context

ADR-0200 declares that CrossEngin's shipping shape is a mother that
bakes children. The mother is the full daemon; a child is a
domain-scoped bundle plus the same NOVA binary launched with
`--child-mode` (ADR-0204). The mother owns ingest, bake, and update-
publication; the child owns answer and audit for its domain.

The mother-side machinery to make this real is a bake pipeline. The
pipeline takes a manifest (what to include), produces a filtered
snapshot (the domain slice), wraps it in a signed bundle (the
distributable artifact), and publishes signed KG-deltas over its
lifetime (the update channel).

Every primitive on the path already ships:

- Session snapshot serialization: `session_snapshot_serialize_ex` at
  `src/sandbox/session_snapshot.nova`. Called with a redaction flag
  of `0` for CAPS+TRUST, it redacts bearer tokens and trust-anchor
  material — exactly the redaction shape a distributable bundle
  needs.
- Ownership visibility: `ownership_visible(reg, kind, name, holder)`
  at `src/sandbox/ownership.nova` — the same filter that gates
  per-user overlays scopes a bake to a persona / holder set.
- Merkle signing: `merkle_sign(root_bytes, seed, pk)` at
  `src/persistence/merkle_signing.nova`. R54.2 uses this for skill
  signatures; extending it to whole-bundle signatures is a wrapper.
- KG section builders: `_snap_persona_section`,
  `_snap_ownership_section`, `_snap_policy_section`,
  `_snap_pattern_section`, `_snap_skill_section` (in
  `src/persistence/snapshot_disk.nova`) — the shape the bake filters
  through.
- KG serializer: `kg_section_build_r` in the same file — needs a
  predicate-filtered variant to drop non-domain atoms.

What is missing is the composition. This ADR specifies it.

## Decision

### BakeManifest schema

The manifest is the authoritative statement of what a child contains.
It is a NOVA record with the following fields:

```
BakeManifest = [
  name:              string           // child name (LegalUK, MedRefUS, ...)
  version:           semver           // child version (1.0.0)
  domain:            string           // free-text domain label
  kg_atom_filter:    predicate_ref    // which atoms bake in
  capsule_allowlist: list<name>       // which capsules bake in
  skill_allowlist:   list<name>       // which skills bake in
  pattern_allowlist: list<name>       // which patterns bake in
  persona_user_ids:  list<user_id>    // which personas bake in
  policy_allowlist:  list<name>       // which policies bake in
  style_pin:         style_capsule_ref // optional forced style
  nl_llm_config:     nl_adapter_config // sidecar config (or null)
  runtime_bitmask:   uint64           // ADR-0204 verb-disable bits
  sandbox_shape:     enum             // unified | partitioned (ADR-0202)
  update_key:        pubkey_ref       // mother key signing deltas
  bake_key:          pubkey_ref       // mother key signing the bundle
  timestamp:         unix_seconds     // bake wall-clock
]
```

The manifest is itself part of the signed bundle. Tampering with the
manifest post-bake invalidates the signature.

### Filtered snapshot mechanics

The bake operation walks the mother's live state and produces a
filtered snapshot. Each section builder gains a `_scoped` variant:

- `_snap_persona_section_scoped(reg, allowlist_ids)` — emits only
  personas whose owner_id is in `persona_user_ids`.
- `_snap_ownership_section_scoped(reg, holder_allowlist)` — emits
  only overlay rows whose holder is in the persona set.
- `_snap_policy_section_scoped(reg, name_allowlist)` — emits only
  named policies.
- `_snap_pattern_section_scoped(reg, name_allowlist)` — emits only
  allowlisted patterns. Note: the pattern registry is a process-
  wide singleton; the scoped variant must explicitly thread the
  allowlist rather than assume it can filter in place.
- `_snap_skill_section_scoped(reg, name_allowlist)` — emits only
  allowlisted skills, each still carrying its R54.2 signature.

The KG itself needs a predicate-filtered serializer variant of
`kg_section_build_r`. Call it `kg_section_build_r_filtered`. It
accepts a `predicate_ref` (the `kg_atom_filter` from the manifest)
and emits only atoms whose evaluation returns true. The predicate
runs against the same atom shape the reasoning engines walk, so a
domain like "legal_uk" can be expressed as a namespace prefix
predicate, and a domain like "runbook_reference" can be expressed as
a capsule-membership predicate.

### Capsule atom-id resolution

Capsules embed raw `atom_id` values in their descriptor. Atom IDs are
not stable across load — a child booting a fresh KG will assign new
IDs. The bake must therefore resolve capsule references by **label**
(the same pattern already in use for cross-KG xref resolution). Each
capsule descriptor in the bundle is emitted with its labels; the
child re-resolves labels to fresh atom IDs at boot-load time.

The pattern was pioneered by the R77 xref persistence work; the bake
adopts it wholesale. No new mechanism.

### Signed bundle format

The output artifact is a bundle:

```
child_bundle_v1 = [
  manifest_bytes:      bytes           // BakeManifest serialized
  snapshot_bytes:      bytes           // filtered session snapshot
  merkle_root:         hash            // Merkle root over all sections
  bundle_signature:    bytes           // ed25519(merkle_root, bake_key)
  bake_key_certificate: bytes          // R55.1 trust-anchor evidence
]
```

`bundle_pkg_sign(bundle, bake_key)` extends the R54.2 skill-signing
call site: `merkle_sign` produces the section root, the section root
is signed by `bake_key`, and the certificate proving the bake key is
authorized is embedded so the child can verify without external
trust-anchor lookup. Verification on the child is
`bundle_pkg_verify(bundle, expected_mother_pubkey)`.

### KG-delta update channel

A deployed child does not re-bake for updates. The mother produces
signed **KG-deltas**:

```
kg_delta_v1 = [
  parent_bundle_id:   bytes           // which bundle this applies to
  parent_version:     semver          // and which version
  new_version:        semver          // resulting version
  atom_adds:          list<atom>      // atoms to insert
  atom_retracts:      list<atom_id>   // atoms to retract
  edge_adds:          list<edge>
  edge_removes:       list<edge_id>
  capsule_updates:    list<capsule_delta>
  provenance_appends: list<provenance>
  merkle_root:        hash
  delta_signature:    bytes           // ed25519(merkle_root, update_key)
]
```

The child receives the delta (poll-model: the child pulls, the mother
does not push into customer infrastructure), verifies against the
`update_key` embedded in its bundle, applies via the same ownership-
overlay machinery R55.x already runs, and bumps its running version
in the ownership audit log. Failure to verify refuses the delta and
alerts the operator.

### Bake command shape

Operator-facing:

```
crossengin bake --manifest legal_uk_v1.manifest \
                --out ./children/legal_uk_v1.bundle \
                --bake-key ~/.crossengin/keys/bake_legal.priv \
                --update-key ~/.crossengin/keys/update_legal.pub
```

The command binds the mother daemon over its local wire, streams a
`bake_child` verb call with the manifest and the two key references,
and writes the resulting bundle to the output path. The mother's
audit log records every bake operation as a first-class event.

## Consequences

### Positive

- Whole pipeline composes existing primitives. No new crypto, no new
  serializer, no new overlay mechanism. Every load-bearing part
  already has test coverage from its original use.
- The bake is fully deterministic given a manifest. Repeat-bakes
  from the same mother state produce byte-identical bundles (except
  for the signature, which depends on the ed25519 nonce or, for the
  deterministic ed25519 in `src/safety/ed25519.nova`, is also
  byte-identical).
- Domain scoping is explicit. A compliance audit can enumerate
  exactly which atoms, capsules, skills, and patterns are in a
  child by reading its manifest.
- Update path is surgical. One KG-delta adds one record; the child
  applies it in seconds; no re-bake, no restart.
- Redaction is built in. `session_snapshot_serialize_ex` with the
  CAPS+TRUST flag redacts bearer tokens and trust-anchor secret
  material by design; the bundle cannot accidentally distribute a
  mother's operational secrets.

### Negative

- Manifest authorship is real work. Operators must decide which
  atoms belong in which child. Bake tooling (a manifest linter, a
  domain-analyzer, a preview command) is a follow-on epic.
- Predicate expressiveness is capped by what the filter language
  supports. A predicate that needs to consult external state at
  bake time (an LDAP group, a compliance tag database) is out of
  scope; predicates must be pure over the mother's live KG state.
- Pattern-registry singleton refactor is nontrivial. Threading the
  allowlist through code that assumed process-wide access will
  touch several files; not a huge change but not zero.
- Bake keys must be managed. An operator loses the bake key; they
  cannot rotate the child's update trust anchor without re-baking
  and re-shipping the bundle. Key management runbook is a
  documentation deliverable.

### Neutral

- Bundle format is versioned (`_v1`). A future format bump is a
  clean migration since the manifest embeds the format version.
- Update channel is poll-only by default. Push-mode is a future
  option and is out of scope here.

## Alternatives Considered

1. **Bake by re-training weights (rejected).** There are no weights.
   The whole ADR-0200 frame rejects this.

2. **Bake as a KG namespace filter only, no capsule / skill /
   pattern allowlists (rejected).** Simpler manifest but does not
   express the real domain scoping enterprises need. A legal child
   should not ship every skill just because the KG slice is legal.

3. **Bake as a fork rather than a filter (rejected).** Forking the
   mother's whole state and letting the child mutate freely gives
   up the update channel — the mother could no longer reason about
   what the child has diverged into. The filter-and-sign shape
   preserves the mother's authority.

4. **Bundle format as a tarball (rejected).** Tarballs are opaque
   to signature verification. A structured signed bundle with a
   Merkle root over named sections gives per-section verification
   without unpacking.

5. **Update channel over TLS wire only, no bundle (rejected).**
   Would require the child to always be connected. Bundles let
   children deploy to air-gapped environments; updates then arrive
   as signed deltas whenever a connection is available (or via
   sneakernet if not).

6. **Deltas as full re-snapshots (rejected for the common case).**
   Full re-snapshots are the fallback for a child that has drifted
   too far to catch up. The common case is incremental deltas so
   updates take seconds, not minutes.

## See Also

- ADR-0200 — Mother/Child factory; the north-star this ADR realizes.
- ADR-0204 — Slim runtime; the `--child-mode` flag and the runtime
  bitmask this manifest field wires into.
- ADR-0205 — Per-user selective load; an alternative consumption
  mode that avoids the hard bake.
- ADR-0202 — Cognitive sandbox; `sandbox_shape` field on this
  manifest.
- ADR-0206 — Beliefs and self-awareness; belief state serializes as
  part of the snapshot.
- R54.2 — Ed25519 skill signing (extended to whole bundles).
- R55.x — Per-user ownership overlay (reused for delta application).
- R73..R75 — Snapshot format (the child KG payload rides this).
- `src/sandbox/session_snapshot.nova` —
  `session_snapshot_serialize_ex`.
- `src/sandbox/ownership.nova` — `ownership_visible`.
- `src/persistence/merkle_signing.nova` — `merkle_sign`.
- `src/persistence/snapshot_disk.nova` — section builders and
  `kg_section_build_r`.
