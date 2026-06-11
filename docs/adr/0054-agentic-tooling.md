# ADR-0054: Agentic tooling (P4)

## Status

Proposed

## Date

2026-06-11

## Context

CrossEngin's effectors are speech-centric (`effector_speak`, audio): the agent
can *say* things but cannot *do* things — no code execution, no web/API calls,
no file I/O, no external-service connectors. And there is no machinery to plan a
sequence of actions or to learn which action works. P4 of the roadmap adds tools
the agent can wield, a way to plan and select among them, and a learning loop
that improves selection from outcomes — building on P2's reward/competence idea
and reusing the existing safety scaffolding rather than inventing new gating.

## Decision

**Tools as skill-shaped atoms (`src/io/effectors/tool.nova`).** A tool is a
record with a capability label (which plan step it satisfies), a backend kind, an
action type (its reversibility), a cost, and a Bayesian COMPETENCE (alpha/beta,
the same posterior-mean semantics skill atoms and atom belief use). A registry
holds tools; `tool_select(capability)` returns the highest-competence tool for a
step; `tool_observe(success)` updates competence after every call. So the agent
reasons about tools as knowledge and *learns to use them* with no retraining — a
tool that starts failing is simply chosen less.

**Four effectors (`src/io/effectors/`).** `effector_code_exec` (safe arithmetic
evaluation — "compute" without a shell), `effector_file_ops` (sandbox-confined
read/write), `effector_http_action` (outbound call), `effector_mcp` (MCP-style
service connector). Each returns the shared tool-result shape `[ok, value, text]`.

**Planner / executor (`src/agent/tool_use.nova`).** A plan is a sequence of
capability steps. For each step the planner selects a tool by competence, GATES
it through `permission_tiers` + `reversibility_classifier`, INVOKES the matching
effector, THREADS the result into the next step's argument, and LEARNS from the
outcome (`tool_observe`). Each result is surfaced as a lightweight moment in the
trace (the seam for re-ingestion). A `tool_presimulate` hook predicts a result
before acting (forward-sim seam).

**Safety is the existing scaffolding.** A tool's action type drives the same
permission tiers as everything else: AUTO actions run, NOTIFY actions run with a
log obligation, and APPROVE-tier (irreversible: send, spend, hard-delete,
self-modify) actions are refused unless approval is granted in the call context.

## Options Considered

- **Competence as Bayesian belief (CHOSEN)** — identical to skill-atom
  reliability (ADR-0019/0023), so tools are genuinely skill-atom-shaped and the
  posterior mean gives calibrated selection. A bare scalar score was rejected as
  not capturing evidence/confidence.
- **Dispatch by kind (CHOSEN)** over storing a function pointer/closure per tool:
  NOVA closures use static per-source-position capture slots (shared across
  instances), so a small `kind -> effector` dispatch in the planner is clearer
  and safe.
- **Safe arithmetic "code exec" (CHOSEN)** over shelling out (a huge,
  unsandboxable attack surface). The evaluator is deterministic and side-effect
  free, so it runs at AUTO tier.
- **Simulated http/mcp with a real seam (CHOSEN)** so tests are hermetic and
  offline; the live transports (`lp_fetch` for HTTP, an MCP socket) swap in
  behind the same result shape.
- **Gate via `permission_tiers` directly (CHOSEN, light)** over routing every
  call through the full `effector_gate` + `decision_log` + constitutional-veto +
  halt pipeline. That richer audit path is the production integration; the tool
  layer uses the same tier logic without the heavier context.

## Consequences

- **Positive.** Both acceptance criteria pass (measured): a 3-step plan
  search → compute → write runs end-to-end with results threaded between steps
  (search "6" → compute "6 * 7" = 42 → file contains "42"); and a tool that
  starts ahead but then fails has its competence fall (800 → 400) so selection
  flips to the alternative. Irreversible actions (send/spend) are gated to
  APPROVE and refused without approval. The agent can now act, and learn which
  actions work, with no retraining.
- **Negative / costs.** The outward-facing backends are simulated by default;
  the planner is not yet driven by the goal engine or the live moment/reward
  loop. Tool plans are currently hand-built.

## Honest gaps

- **Live backends are seams.** `http_action` real fetch (the gated `lp_fetch`
  transport) and `mcp` real transport are not wired — tests run them simulated.
  `code_exec` evaluates arithmetic, not arbitrary code; a real sandboxed
  interpreter is future work. `file_ops` does touch the real filesystem but is
  confined to a fixed sandbox prefix.
- **Not wired into the cognitive loop.** Plans are built by hand, not decomposed
  by `goal_engine`; `tool_presimulate` is a local dry-run, not the
  `imagination/forward_sim` engine; results are lightweight trace moments, not
  emitted into `moment_stream` for ingestion; and learning is the competence
  update only — the P2 `XSIG_REWARD` → three-factor plasticity wiring is not yet
  connected. These are the P4 → P5 integration points.
- **Gating is the tier logic, not the full audit path.** Routing through
  `effector_gate` + `decision_log` (ADR-0043) would add the intent/outcome audit
  record and constitutional veto / hard-stop; the tool layer uses
  `permission_tiers` + `reversibility_classifier` directly for now.
- **Self-directed tool acquisition is not automated.** The roadmap's "read an
  API's docs (P3) → mint a new skill-atom → try it → competence records success"
  is now *composable* (P3 ingestion + P4 tools + competence), but the loop that
  does it autonomously is not built.

## Implementation Notes

- Competence is a local alpha/beta belief mirroring `atom_store`'s, so the tool
  layer needs only the safety import (no `atom_store` dependency). The four
  effectors are pure `*_run` functions returning `tr_new(ok, value, text)`; the
  planner owns the `kind -> effector` dispatch and the gate.
- **Tests.** `test_tool` (25: accessors, competence updates, selection +
  failure-flips-selection, cost tie-break, the AUTO/NOTIFY/DENY gate, result
  type), `test_effectors` (16: code_exec valid/invalid, file_ops sandbox
  enforcement + roundtrip, http simulated/empty/live, mcp registry/direct/
  unknown), `test_tool_use` (11: the 3-step plan acceptance, failure lowers
  competence via the planner, failure changes selection, gated-step denial,
  pre-simulation). All six modules are new and imported by nothing else, so the
  existing suite is unaffected.
- **Next (P4 → P5).** Drive `plan_execute` from `goal_engine`; route
  `tool_presimulate` through `forward_sim`; emit results into `moment_stream` and
  feed outcomes to the three-factor reward loop; wire the live HTTP/MCP
  transports; then P5 (a simulation world + self-improvement) closes the loop.
```
P1 HDC embeddings ─► P2 predictive coding + 3-factor ─► P3 ingestion/OpenIE
                                                              │
                        P5 sim + self-improve ◄── P4 agentic tooling
```
