# ADR-0204: Slim Runtime Mode (`--child-mode`)

## Status

Proposed. Defines the boot-time flag that turns the standard
CrossEngin daemon into the immutable-KG, no-bake, no-ingest
appliance a baked child (ADR-0203) requires. The flag sets a bitmask
on `rpc_ctx` at boot; every verb consults the bitmask via
`capability_authorize`. No verb code needs to change beyond the one
authorization check. Same binary, different launch flag, verifiably
narrower attack surface.

## Date

2026-08-22

## Context

ADR-0203 produces a signed child bundle. That bundle presumes a
runtime posture that is materially narrower than the mother's:

- The KG is immutable after boot-load. No new atoms.
- Ingest is disabled. No new observations enter the KG through the
  ingest pipeline.
- No new capsules, skills, or patterns can be installed.
- No new bakes can be produced from within the child.
- Admin verbs (rotate keys, publish deltas, reload cert material)
  are unavailable.
- Session snapshotting from within the child is disabled (the child's
  state is derived from its bundle plus the deltas it has applied;
  a lateral snapshot would fork the update channel).

The mother's binary is the same NOVA program; the child inherits
every reasoning engine, every skill, every transducer, every learner
the mother has. What the child does NOT inherit is the mother's
authority to change any of its own state beyond what the mother
publishes through the update channel.

The narrow-posture question is how to enforce this. Three shapes are
possible: a separate binary, a runtime capability tokens config, or
a bitmask on `rpc_ctx` that verbs consult through
`capability_authorize`. The first is a fork we do not want (drift
risk, doubled maintenance). The second is what capability tokens
already do at the caller granularity — but this is not a per-caller
policy, it is a per-process posture. The third fits: one bitmask, set
once at boot, consulted uniformly, verifiable from the daemon banner.

## Decision

### The flag

The daemon accepts `--child-mode` at launch. When present, the
runtime bitmask `rpc_ctx.child_mode_disabled` is initialized to the
value carried in the loaded bundle's `runtime_bitmask` (ADR-0203),
which by default disables the following verbs:

- `ingest.file`, `ingest.review`, `ingest.approve`, `ingest.deny`
- `capsule.install`
- `skill.install`
- `pattern.install`
- `admin.*` (all admin-tier verbs)
- `session.save`
- `bake_child`

The following verbs remain enabled:

- `nl.ask`, `nl.parse_only`
- `kg.list`
- `capsule.list`, `skill.list`, `pattern.list`
- `skill.run`
- `capability.list`
- `session.load`
- `persona.show`, `persona.project`
- `user.preference.*` (ADR-0205)

The exact bitmask is per-bundle so that a specialized child can
enable a narrower set (for example, a strict read-only child could
also disable `persona.project` if the operator does not want any
per-user state observed on the child).

### Authorization check

`capability_authorize` is the single entry point. Every verb calls
it. Its shape becomes:

```
capability_authorize(ctx, verb_id, ...) ->
  (allowed | denied_by_capability | denied_by_child_mode)
```

The bitmask is consulted immediately after the capability-token
check. A verb disabled by child-mode refuses with a distinguishable
reason so a caller can tell the difference between "you lack the
capability" and "this daemon posture forbids this verb."

### KG immutability

The KG becomes immutable at boot-load. Concretely:

- `kg_add_atom`, `kg_remove_atom`, `kg_update_edge` are no-ops that
  return `ERR_CHILD_MODE_IMMUTABLE` when the bitmask is set.
- The update channel (ADR-0203 KG-deltas) is the one exception: it
  uses a distinct internal write path that verifies the delta
  signature before applying. That write path is not exposed as a
  wire verb.
- The learner kernels (`predictive_coding_runtime`,
  `forward_forward`, `bayesian_updates`, `belief_decay`) are
  suspended by default. A child that opts in to on-device learning
  can enable them by leaving the corresponding bitmask bit clear;
  the sandbox output still lands in a review queue that only the
  mother can drain over the update channel.

### Boot banner and status

The daemon prints its posture at boot:

```
CrossEngin daemon (NOVA build 2026-08-22)
mode: child (bundle: legal_uk_v1, mother pubkey ed25519:abcd..., 41 atoms, 3 skills)
disabled verbs (bitmask 0x1F3): ingest.*, capsule.install, skill.install,
pattern.install, admin.*, session.save, bake_child
```

A wire verb `daemon.status` returns the same posture programmatically,
so a compliance auditor can query the running daemon without
inspecting stdout. `capability_authorize` refusals name the exact
bitmask bit that fired, so a support runbook can point at a specific
line of the banner.

## Consequences

### Positive

- Verifiable read-only appliance. An auditor can query
  `daemon.status`, confirm the bitmask, and know exactly which
  verbs will refuse. The refusal is visible at the wire, not buried
  in per-verb code.
- Smaller attack surface. A compromised caller with full capability
  tokens still cannot install a skill, mint a capsule, or drain the
  ingest queue on a child. The bitmask is enforced by the daemon
  process, not by the caller's token.
- Same binary. Every reasoning engine that runs on the mother runs
  on the child; there is no separate "child NOVA" to maintain, no
  behavior drift between the two.
- Composable with ADR-0203. The bundle carries the bitmask; the
  child boots with the bundle's bitmask; a specialized child can be
  narrower than the default.
- Admin operations still possible. They require a mother-mode
  connection or a re-bake; the child cannot admin itself, but the
  operator running the mother can push a new bundle or apply a
  delta.

### Negative

- Recovery from a bad delta is more work than a mutable child would
  be. A child that receives a bad delta has to be rolled back via
  the mother's delta-rollback path (ADR-0203); it cannot patch
  itself.
- On-device learning is subject to review-queue drainage back to the
  mother. Children that operate air-gapped can accumulate a review
  queue faster than deltas can drain it if the mother connection is
  intermittent.
- Adds one bit of coupling to `capability_authorize`. The check is
  small but every verb path passes through it; a bug here has broad
  blast radius.

### Neutral

- Boot banner is verbose. Operators that want quieter output can
  suppress with `--quiet`; the wire verb `daemon.status` is the
  supported way to introspect anyway.

## Alternatives Considered

1. **Separate `crossengin-child` binary (rejected).** Would drift
   from the mother. Two binaries means two test surfaces, two
   release cadences, two bug pools.

2. **Per-verb capability tokens (rejected).** Capability tokens are
   per-caller policy. Child-mode is per-process posture. Mixing the
   two would let a mis-issued token relax the process posture,
   which defeats the point.

3. **File-system chroot / systemd sandboxing instead of an in-
   process bitmask (partial, not-in-scope).** Runtime sandboxing at
   the OS level is complementary to the bitmask, not a replacement.
   An operator deploying a hardened child should do both; this ADR
   specifies only the daemon-side control.

4. **Immutable KG via read-only mmap (rejected).** Would enforce
   immutability at the storage layer but complicates the update
   channel (which does need to write). The bitmask approach lets
   the internal delta-application path write while the wire path
   cannot.

5. **Compile-time strip of the disabled verbs (rejected for the
   common case).** Would produce a genuinely smaller binary but
   forbid the same-binary property. A specialized deployment that
   needs a minimum-code child can still build with strip flags;
   the default shape does not.

## See Also

- ADR-0203 — Bake pipeline; produces the bundle the child boots.
- ADR-0200 — Mother/Child factory; describes the deployment shape.
- ADR-0205 — Per-user selective load; alternative consumption mode
  that does not disable verbs, only projects a subset.
- ADR-0206 — Beliefs and self-awareness; the child can still report
  its own beliefs and gaps.
- ADR-0209 — Deployment form factors; child-mode is mode 3.
- `src/wire/capability_authorize` — the single enforcement point.
- `src/wire/rpc_ctx` — carries the bitmask.
