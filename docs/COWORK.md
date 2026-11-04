# Multi-agent cowork — Phase 7 pt1

A single `crossengin-chat` can host **one** agent (one baked bundle, or the default session). Phase 7 is multi-agent cowork: a task that crosses role boundaries (legal + finance + clinical) fans out to multiple agents, each handles its slice, results compose back into one audited answer.

Pt1 ships the **planner only** — not the fan-out. The planner reads a natural-language task, matches sub-tasks to installed agents by domain, and prints the DAG. Fan-out (bytes over the wire via the federation layer) is Phase 7 pt2+.

## What's in pt1

- `src/agent/cowork_planner.nova` — pure keyword-triggered planner. 26 trigger words → 6 domains (`legal`, `clinical`, `code`, `finance`, `research`, `procurement`).
- `/cowork plan <description>` chat command — walks `cw_plan`, resolves each sub-task's domain against `<CE_AGENTS_DIR>/index` (via `ab_parse_header`'s `#domain` field from Phase 5 pt1), prints the DAG with the matching agent name or a hint to install one.

## Trigger table

| Domain | Triggers |
|---|---|
| legal | `legal, law, contract, gdpr, compliance` |
| clinical | `clinical, patient, medical, drug, symptom` |
| code | `code, review, bug, lint, refactor` |
| finance | `finance, cost, budget, accounting, money` |
| research | `research, study, paper, arxiv` |
| procurement | `procurement, vendor, purchase` |

Words that fire triggers across multiple domains (e.g. `contract` in both legal and a potential procurement-only reading) land in the DAG under the first matching domain in the trigger order above. Pt2 can add disambiguation via context.

## Example

```
> /cowork plan is this GDPR contract also financially acceptable?
cowork_tasks=3
  task_1  domain=legal   trigger="contract"       agent=? (no installed agent for domain='legal' -- try /agent list / install one)
  task_2  domain=legal   trigger="gdpr"           agent=? (no installed agent for domain='legal' -- try /agent list / install one)
  task_3  domain=finance trigger="financially"    agent=? (no installed agent for domain='finance' -- try /agent list / install one)

> /cowork plan clinical trial research on aspirin
cowork_tasks=2
  task_1  domain=clinical  trigger="clinical"  agent=clinical-rx-sample
  task_2  domain=research  trigger="research"  agent=? (no installed agent for domain='research' -- try /agent list / install one)
```

The `agent=clinical-rx-sample` row shows the planner resolving to the fabricated bundle indexed at `<CE_AGENTS_DIR>/index` (Phase 5 pt1).

## Why print-only

A real fan-out needs:

1. **Transport.** CrossEngin's federation layer (`distributed_query`, `gossip`, Noise XK) exists but is unexercised from the chat path. Pt2 wires it to `/cowork run`.
2. **Agent reachability.** Not every indexed agent runs locally — some live on peer daemons. Discovery goes through `agent.list` RPC or the gossip layer.
3. **Capability bridging.** Every sub-task dispatched to a peer agent routes through the Phase 1 pt1 cap gate on the receiving side. Pt1's planner doesn't speak that protocol yet.
4. **Result aggregation + citation chain.** Each peer returns an answer plus its atom citations; the originating agent composes a unified answer whose audit trail spans every contributor.

Those four are Phase 7 pt2+ scope. Pt1's planner is the shape — pt2's work is routing bytes, not negotiating semantics.

## Phase / PR cross-reference

- `src/agent/cowork_planner.nova` + `/cowork plan` + this doc — Phase 7 pt1, PR TBD.
- `src/factory/agent_bundle.nova` — Phase 5 pt1, PR [#25](https://github.com/amoufaq5/Crossengin-demo/pull/25). Reused for header + `#domain` parsing.
- `_agents_dir()` + `<CE_AGENTS_DIR>/index` convention — Phase 5 pt1 + `docs/AGENT_PLATFORM.md`.

## Deferred

- `/cowork run <description>` — actually dispatches each sub-task. Needs federation wiring (prerequisite: a real peer daemon or in-process multi-agent runtime).
- Cross-domain result aggregation and composed-answer rendering.
- Benchmark corpus: ≥3-agent tasks (e.g. "is this GDPR-compliant contract financially acceptable and procurement-eligible?") with end-to-end latency, accuracy, citation rate per contributing agent.
