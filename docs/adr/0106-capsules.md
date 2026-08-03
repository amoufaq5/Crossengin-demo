# ADR-0106: Capsules — named shareable bundles on top of atoms

## Status

Proposed

## Date

2026-08-15

## Context

ADR-0100 named CrossEngin's architecture as Moment-Signal Cognition
(MSC) with four primitives: node, signal, moment, attribution. Every
piece of knowledge today lives directly as atoms in a KG — a bag of
labeled nodes grouped by domain-name string. That is sufficient for a
demo but insufficient for the vision:

1. **Users cannot say "I want the medical expertise" as one unit.**
   Today they say "install the medical_pack.nova and the anatomy_pack
   and the drug_interactions_pack and the medical_history_pack" — five
   separate imports, no cohesion, no versioning.
2. **Knowledge cannot be traded or federated as a unit.** A community
   member who authors a well-vetted "constitutional law" bundle has
   no shippable primitive — only a loose `.cerec` file with no
   metadata about what capsule it belongs to, what version, what
   dependencies, or what license.
3. **There is no primitive for "trainable expertise."** A domain
   expert who wants to iterate on a bundle across dozens of ingest
   passes (adding sources, refining beliefs, retracting mistakes) has
   no name for the thing being iterated on — just "the atoms tagged
   `src:pack:medical:*`."
4. **Downstream layers need capsules.** Skills (ADR-0103) will declare
   `capsules[] = ["coding", "debug_pattern", "code_style"]` in their
   manifest. Personas (ADR-0102) will reference a preferred style
   capsule. NL surface (ADR-0104) will consult a style capsule when
   rendering. Without capsules as a first-class primitive, every
   downstream layer has to reinvent the "named bundle of atoms" idea.

The user's architectural choice (R45) is **Option A, shareable**:
capsules are a NEW layer built ON TOP of atoms; atoms can belong to
multiple capsules; existing atom code doesn't change.

## Decision

We introduce **Capsules** as a first-class primitive: named,
versioned, shareable bundles of atoms + implications + provenance.
Capsules are built ON TOP of atoms (atoms remain the base MSC node);
atoms can belong to multiple capsules simultaneously (shareable).

### The Capsule shape

```
Capsule = [
  name:            string,         primary key within a Registry
  version:         string,         semver-shaped ("1.0.0", "2.1.3-beta")
  description:     string,         one-line human-readable purpose
  source_prefix:   string,         "src:cap:medical:v1"  (feeds meta-observer)
  atom_refs:       list<atom_id>,  atoms this capsule declares membership over
  imp_refs:        list<imp_id>,   implications this capsule declares
  deps:            list<capsule_ref>, required-capsules this one composes over
  license:         string,         "CC-BY-4.0", "proprietary", "public-domain", etc.
  installed:       bool,           true if currently active in this session
  installed_at:    moment          when installed
]
```

Capsules do NOT own atoms. Atoms live in KGs (as today). A capsule is
a **membership set** — it names atoms + implications that together
constitute the capsule's declared knowledge. Shareability comes for
free: two capsules can both declare membership over the same atom
(e.g. `mitochondria` in `biology_v1` and `medicine_v1`); the atom
exists once, in one KG.

### The CapsuleRegistry

```
CapsuleRegistry = [
  capsules:        list<Capsule>,      registered but not-necessarily-active
  active_by_name:  list<[name, capsule_id]>,  fast install-status lookup
]
```

One registry per session (following the Session/KG-registry pattern).
Registered vs active is deliberate: a capsule can be installed on the
disk snapshot (registered, atoms + imps present in the KGs) without
being currently active (skills asking "is medical_v1 active?" get 0
until an explicit install). This matches the mental model of
installing then enabling a package.

### The .capsule.cerec file — how a capsule is shipped

The `.cerec` file format extends with two OPTIONAL directives at the
top of a record that mark it as a capsule declaration:

```
CAPSULE      medical
VERSION      1.0.0
DESCRIPTION  Reference clinical medicine at Merck Manual level
LICENSE      CC-BY-4.0
DEPS         biology:1.0.0, human_anatomy:1.0.0
KG           medicine
SRC          src:cap:medical:v1
ATOM         infection 1 950
ATOM         antibiotic 1 950
IMP          infection antibiotic EMPIRICAL
...
```

CAPSULE, VERSION, DESCRIPTION, LICENSE, DEPS are new directives.
KG/SRC/ATOM/IMP/OBS/CITE stay as-is (see ADR earlier). A `.cerec`
file without a CAPSULE directive stays a plain KG record (backwards
compatible).

`/ingest cerec <file>` handles both. If CAPSULE is present:
1. The atoms + implications ingest into the target KG as today.
2. A Capsule entry is created in the CapsuleRegistry with all the
   metadata.
3. Every atom seeded by this record adds its id to `atom_refs`; every
   implication adds its id to `imp_refs`.
4. The source tag defaults to `src:cap:<name>:v<version>` if SRC is
   omitted.

### Chat commands (new)

```
/capsule list                          -- installed + registered capsules
/capsule info NAME                     -- detail: version, deps, atom count, sources
/capsule install NAME [VERSION]        -- mark active; run deps first
/capsule uninstall NAME                -- mark inactive (atoms stay; membership stays)
/capsule remove NAME                   -- remove capsule metadata (atoms stay)
/capsule diff NAME1 NAME2              -- shared atoms + disagreements
/capsule sources NAME                  -- meta-observer atrophy for this capsule's src tag
```

`/capsule install` is idempotent. `/capsule uninstall` does NOT
remove atoms — other capsules may share them. Skills querying "is X
capsule active" get an accurate answer without atoms disappearing
underneath them.

### Semantics: what "active" means

An active capsule advertises itself to skills and other consumers:

- `capsule_is_active(reg, name)` returns 1/0.
- `capsule_active_atoms(reg, name)` returns the list of atom refs.
- Skills declare required capsules in their manifest; the supervisor
  refuses to start if any required capsule is not active.

Inactive capsules still have atoms present in the KGs (so cross-KG
consistency scans still see everything), but skills that gate on
capsule activation won't fire.

### Shareable atom semantics

An atom belongs to a capsule if any capsule declaration ingested it
OR added it via `capsule_claim_atom(reg, cap_name, atom_id)`. An atom
can belong to MANY capsules simultaneously — the same `mitochondria`
atom is claimed by both `biology_v1` and `medicine_v1`; both see it
in their `atom_refs`; neither owns it exclusively.

Uninstalling a capsule REMOVES that capsule from the atom's set of
member-capsules but leaves the atom alive so long as at least one
other capsule still claims it, OR the atom is referenced from an
active KG-level implication, OR the atom's belief mass is non-trivial
(above the atrophy floor). The existing atom_death_monitor handles
GC of orphaned atoms.

## Options Considered

1. **Option A — Capsules ON TOP of atoms, shareable (CHOSEN).**
   Atoms unchanged, capsules are membership sets, atoms can belong to
   many capsules. Zero refactoring of existing code. Natural for
   shared vocabulary (`person` atom claimed by biology, history,
   religion, politics, etc.).
2. **Option B — Everything IS a capsule; unify atom + capsule under
   one abstraction.** Cleaner ontology; requires reworking every KG
   test. Rejected by the user in R45.
3. **Option C — Capsules as trainable containers, atoms as labels
   only.** Belief moves to capsule level. Big departure from
   MSC-0100. Rejected by the user in R45.
4. **Owning (non-shareable) capsules.** Each atom belongs to exactly
   one capsule. Cleaner ownership but breaks the shared-vocabulary
   case (biology/medicine both need `mitochondria`). Rejected by the
   user in R45 in favor of shareable.

## Consequences

- **Positive:** Users get a shippable primitive — "install medical_v1"
  is a single operation. Community-authored capsules become
  distributable content. Skills declare required capsules in one
  manifest field. Downstream layers (ADR-0103 Skills, ADR-0102
  Persona, ADR-0104 NL) reference capsules directly without
  reinventing "named bundle."
- **Positive:** Zero-atom-refactor. Existing tests continue passing
  as-is because atoms and KGs are unchanged. Capsules are pure add-on.
- **Positive:** Subtypes (Pattern capsules ADR-0107, Style capsules
  ADR-0108) are free — same primitive, different atom-kind
  conventions, different consumers. No new plumbing per subtype.
- **Neutral:** `.cerec` grows five new OPTIONAL directives (CAPSULE,
  VERSION, DESCRIPTION, LICENSE, DEPS). Files without them stay valid.
- **Negative:** Adds a Registry to the Session shape. Snapshots must
  round-trip capsule registry state. Manageable via the existing
  presence-flag serialization pattern.
- **Negative:** Capsule dependency resolution can loop if authors
  create cycles. Runtime detection + error message on install.
- **Future work:** ADR-0107 formalizes Pattern Capsules (ATOM_RULE
  atoms as step sequences). ADR-0108 formalizes Style Capsules
  (stylistic-constraint atoms consumed by the NL templater).
  A "capsule marketplace" for federated distribution is a much later
  ADR; for v1, capsules are a local + file-based primitive.

## Implementation Notes

**Modules to add:**

```
src/capsules/capsule.nova
    Capsule shape, constructors, accessors, install/uninstall
    semantics, atom-membership operations.

src/capsules/capsule_registry.nova
    Per-session registry. Register / lookup / list. Active-status
    tracking. Dependency resolution on install.

src/capsules/capsule_dep.nova
    Semver comparison + dependency graph traversal + cycle detection.
```

**Files to extend:**

```
src/ingest/importers/records.nova
    Parse the five new OPTIONAL directives (CAPSULE / VERSION /
    DESCRIPTION / LICENSE / DEPS). Emit a Capsule declaration
    alongside the KG record when CAPSULE is present.

src/ingest/pipeline.nova
    On ingest, if the record has capsule metadata, register the
    capsule + claim atoms/imps in the registry.

src/session/session.nova
    Add SES_CAPSULE_REGISTRY slot (16th slot).

examples/crossengin_chat.nova
    /capsule list | info | install | uninstall | remove | diff |
    sources commands.
```

**Snapshot round-trip:** capsule registry serializes as
`[capsule_count, capsule_1, capsule_2, ...]` under a presence flag
(`CAPSULE_REG_VERSION`) so old snapshots without capsules restore
cleanly.

**Migration path for existing packs:**

The seven `.cerec` packs currently shipped (`data/packs/*.cerec`) can
be upgraded to declare capsule membership by adding four directives at
the top of each. That upgrade is separate from this ADR — the ADR
just makes the addition possible; a follow-up commit migrates the
packs.

**Test plan:**

- `test_capsule_new_and_accessors` — shape + slot integrity.
- `test_capsule_registry_register_lookup` — register, lookup by name,
  duplicate rejection.
- `test_capsule_install_activates` — install marks active, uninstall
  marks inactive, atoms stay.
- `test_capsule_shareable_atom` — same atom claimed by two capsules.
- `test_capsule_deps_resolve_in_order` — dependency install order.
- `test_capsule_dep_cycle_detected` — cycle → error.
- `test_capsule_semver_ordering` — 1.0.0 < 1.0.1 < 1.1.0 < 2.0.0.
- `test_cerec_parse_capsule_directives` — CAPSULE/VERSION/... parse.
- `test_ingest_capsule_registers_in_registry` — end-to-end.
- `test_capsule_snapshot_roundtrip` — save + load with capsules.

DEPENDS ON: ADR-0100 (Moment-Signal Cognition), ADR-0051 (Session
struct), ADR-0043 (audit log, for install events),
ADR-0050 (meta-observer, for per-capsule source atrophy).
FEEDS INTO: ADR-0102 (Persona will reference a preferred style
capsule), ADR-0103 (Skills will declare required capsules),
ADR-0104 (NL templater will consult a style capsule), ADR-0107
(Pattern Capsules subtype), ADR-0108 (Style Capsules subtype).
