# CrossEngin Agent Platform

A CrossEngin **agent** is a self-contained unit of pattern + knowledge + policy, bundled into a single Ed25519-signed file that one daemon can hand to another. There are no weights, no tensors, no model files — the agent *is* its atoms, synapses, and operators. `tar czf` → ship → `/load` and the agent moves with it.

## What's in a bundle

Bundles are produced by `bake_child` / `bake_child_ex` in `src/factory/bake.nova` and have a stable line-based layout:

```
#CROSSENGIN-CHILD-BUNDLE v1
#name    <agent name>
#version <semver>
#domain  <topic>
#baked-at <unix ts>
#mother-fingerprint <hex>

#PERSONA v1
   ... persona entries ...
#OWNERSHIP v1
   ... overlay owners ...
#POLICY v1
   ... per-cap tier policies ...
#PATTERN v1
   ... pattern atoms ...
#SKILL v1
   ... skill manifests ...
#AGENT v1
   ... per-agent config: DESC, CAPSULE_DEP, SKILL_DEP, PATTERN_DEP,
       STYLE_PIN, PERSONA_PIN, MIN_CONFIDENCE_MILLI, LICENSE ...
#KG v1
   ... atoms + operators + beliefs ...

#SIGNATURE <hex>
#SIGNER-PK <hex>
```

The `#SIGNATURE` line covers the whole prefix — any edit anywhere in the bundle invalidates it. The mother's Ed25519 private key signs; the child verifies against the trust-anchor pubkey.

## The read-only Rx surface (Phase 5 pt1)

Three slash commands let an operator audit a bundle before applying it. All three are side-effect-free apart from the attestation log entry on `verify`.

### `/agent list`

Reads `<CE_AGENTS_DIR>/index` (default `~/.crossengin/agents/index`), one bundle path per line, blank lines and `#`-comments ignored. For each bundle: parses the top-of-file header lines and prints one row:

```
> /agent list
  bundle=clinical.bundle name=clinical-rx-v1 version=0.1.0 domain=clinical baked_at=1762105900
  bundle=coding.bundle   name=coding-reviewer version=0.3.1 domain=code     baked_at=1762108400
agents_listed=2
```

NOVA has no `sys_readdir` primitive (see `docs/NOVA_RUNTIME_GAPS.md`), so the index file is the convention. Keep it short; a line is just `<name>.bundle` relative to the dir or an absolute path.

### `/agent info <path>`

Full read-only summary: headers, signer-pk fingerprint (first 16 hex chars), and one line per section with entry count:

```
> /agent info /home/user/.crossengin/agents/clinical.bundle
path=/home/user/.crossengin/agents/clinical.bundle
  name=clinical-rx-v1
  version=0.1.0
  domain=clinical
  baked_at=1762105900
  mother_fp=deadbeefcafebabe
  signer_pk_fp=ffeeddccbbaa9988...
  section=PERSONA entries=2
  section=OWNERSHIP entries=1
  section=POLICY entries=1
  section=PATTERN entries=0
  section=SKILL entries=2
  section=AGENT entries=1
  section=KG entries=2
```

No signature check — this is the "what's in it" command. For signature verification, run `/agent verify` next.

### `/agent verify <path>`

Delegates to `bake_verify_bundle(text, pubkey_bytes)` with the pk from `CE_AGENT_VERIFY_PUBKEY_HEX` (64-char hex, mother's Ed25519 public key). Prints `verified: <path>` on success or `REFUSED: <reason>` on failure. Writes a `delete`-cap attestation to the decision log (yes = `allow`, no = `deny`), so every signature decision ends up on the same hash-chained audit trail as retracts and snapshot loads.

```
> export CE_AGENT_VERIFY_PUBKEY_HEX=<64 hex chars from the mother>
> /agent verify /home/user/.crossengin/agents/clinical.bundle
verified: /home/user/.crossengin/agents/clinical.bundle

> /__safety__
safety_attestations=1
  #0 attest delete -> allow
```

Without the pubkey env, verify refuses to run — the whole point is to compare against a trust anchor, and silently accepting an unverified bundle would defeat the surface.

## Why Rx first

A one-step `/agent install` requires:

1. Reading the bundle (same as `/agent verify`).
2. Verifying the signature (same).
3. Calling `session_snapshot_apply_ex` — which **overwrites** the active session's soul / KG / registries from the bundle's sections. Destructive.
4. Attesting under `CAP_DELETE` and prompting the operator per `_gate_or_prompt`.
5. Attestation hooks for every applied section, so `/why` can trace back to the install event.

Pt1 lands steps 1 + 2 as a read-only command. The destructive apply path lands in Phase 5 pt2 with its own cap-gate smoke tests.

## Mother-mode baking

The producer side already exists:

- `bake_child(manifest, persona_reg, kgreg, capreg, skill_reg, policy_reg, overlay, signer_seed, signer_pk, now)` → `BakeResult`.
- `bake_child_ex(..., agent_reg, ...)` → the 11-arg variant that also carries `#AGENT v1` entries.
- `bake_result_bundle(r)` returns the signed text.

A convenience script `scripts/bake_child.sh` (if present in the deployment) wraps those calls for operator ergonomics. The mother manages the signer seed; children never see it, they only hold the pubkey.

## Vertical agents (roadmap, not shipped)

| Role | Suggested manifest | Core packs |
|---|---|---|
| Code reviewer | `code_reviewer.yaml` | `code_review` (already seeded with 7 review-rule operators: `race → add_lock`, `leak → add_cleanup`, `missing_test → request_coverage`, `regression → request_revert`, `magic_number → extract_const`, `null_deref → guard_clause`, `deadlock → request_changes`) + The Stack permissive subset |
| Paralegal / contract reviewer | `legal_contract_reviewer.yaml` | legal_pack + USC/CFR/EUR-Lex |
| AP/AR clerk | `finance_officer.yaml` | ops_runbook_pack + accounting templates |
| HR policy assistant | `hr_policy_assistant.yaml` | hr_policy_pack |
| Clinical reference | `clinical_reference.yaml` | medical_pack + PubMed + RxNorm |
| Research assistant | `research_assistant.yaml` | wiki + arxiv + openstax |
| Customer support rep | `support_rep.yaml` | ops_runbook_pack |
| Procurement reviewer | `procurement_reviewer.yaml` | legal_pack + vendor templates |

The `code_review_pack.nova` operators form the kernel of a shipped code-reviewer agent. Expanding to ~100 hand-seeded + ~500 LLM-extracted pattern atoms is Phase 5 pt2+ work.

## Positioning vs an LLM-based reviewer

| Dimension | CrossEngin agent | LLM reviewer |
|---|---|---|
| **Form factor** | Signed bundle, RAM-resident. Diff-updateable (sign a delta, ship, verify, apply). | Fine-tuned weights (GB), opaque, retrain to update. |
| **Hardware** | CPU + a few hundred MB RAM per agent. | GPU-class, or an API round-trip. |
| **Audit** | Every claim traces to a specific atom + source tag. `/why <atom>`. | Token-level attribution is best-effort post-hoc at best. |
| **Deploy** | One bundle per tenant; `/agent install` replaces atomically. | Per-tenant fine-tune and shipping are heavyweight. |
| **Multi-model** | Can wrap any LLM as the fluency layer (Phase 2 composer). | Model-locked. |

The CrossEngin position: the agent is the pattern + knowledge; the LLM, when present, is the stylist that wraps the symbolic answer. Both can run on a laptop.

## Env-var reference

| Variable | Default | Role |
|---|---|---|
| `CE_AGENTS_DIR` | `$HOME/.crossengin/agents` | Dir scanned by `/agent list` (reads `<dir>/index`) |
| `CE_AGENT_VERIFY_PUBKEY_HEX` | unset | 64-char hex pk required for `/agent verify` |
| `CROSSENGIN_CHILD_MODE` | unset | When `1`, every non-read capability (including the attested `/agent verify`) refuses. See Phase 1 pt2. |
