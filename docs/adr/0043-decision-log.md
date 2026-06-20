# ADR-0043: Decision log (append-only, full trace per action, user-inspectable)

## Status

Proposed

## Date

2026-05-25

## Context
A substrate where intelligence emerges from dynamics (ADR-0001) is intrinsically hard to debug and hard to trust: there is no orchestration script to read. For a system that acts autonomously, we need an authoritative, durable record of *what it did and why* — both to honor the safety contract (ADR-0041, ADR-0042) and to give the user (and, in v2, an enterprise auditor per ADR-0047) a way to inspect, challenge, and override decisions (ADR-0044). Episodic memory (ADR-0022) is lossy by design (it decays and consolidates); it cannot serve as the audit record. We need a separate, non-decaying, append-only log.

The forces: a desktop app can crash or lose power mid-action, so the log must be crash-safe (an action that executed must have a durable log entry, and the log must never be silently truncated). The trace must be rich enough to reconstruct the causal chain that produced an action without re-running the substrate, yet cheap enough to write on the action loop's hot path. And it must be inspectable in plain language through pure-substrate output (ADR-0013) — NO LLM in the explanation path.

This is the concrete consumer of NOVA enhancement #9 (append-only, fsync-backed decision/audit log) and ties directly to the internet-fetch audit requirement of ADR-0028.

## Decision
We add an append-only, crash-safe decision log to `core/safety.nova`, persisted via `runtime/db.nova` with fsync on commit (NOVA enhancement #9). Every action that passes through `safety_gate` (ADR-0041) — auto, notify, or approve — writes one immutable entry BEFORE the effector runs, and a completion/undo record after. Each entry carries a **full per-action trace** reusing the `trace` field already defined in the `core/signal.nova` layout `[TAG, type, moment, origin, destination, priority, trace, metadata]`. The trace is the visited-node list accumulated as the signal propagated, so a log entry records the actual substrate path that culminated in the action.

A log entry is a tag-prefixed record: `[LOG_ENTRY, seq, timestamp, action_class, action_type, perm_tier, rev_class, originating_goal, signal_trace, soul_state_snapshot_ref, outcome]`. `seq` is a monotonic counter; entries are content-hash-chained (each entry stores the hash of the prior entry) so any tampering or truncation is detectable. `originating_goal` links to the `core/goal.nova` node that drove the action (supporting "why did you do this?"). `soul_state_snapshot_ref` points at the relevant soul state/values at decision time (ADR-0034) so the user can see the emotional/value context. Entries are never updated or deleted; corrections are themselves appended `SIG_CORRECTION`-tagged entries.

## Options Considered
1. **Reuse episodic memory as the audit trail (rejected).** Zero new machinery. But episodic memory decays, consolidates, and is mutable (ADR-0022, ADR-0025) — exactly the wrong properties for an audit log. An auditor needs a record that cannot quietly change. Rejected.

2. **Structured DB table with updatable rows (rejected).** Convenient querying. But mutable rows undermine trust and complicate crash-safety guarantees; an append-only file with fsync is simpler to make durable and tamper-evident. Rejected in favor of append-only with a derived/queryable index.

3. **Log only NOTIFY/APPROVE actions, skip AUTO (considered, rejected).** Cheaper hot path. But AUTO actions are precisely the ones the user never sees in real time, so omitting them creates a blind spot for after-the-fact inspection. We log all three tiers; we make AUTO entries lighter (smaller snapshot reference) to control cost. Rejected as written.

4. **Full-trace, hash-chained, fsync append-only log for all gated actions (CHOSEN).** Durable, tamper-evident, complete, and reuses the existing signal `trace` so the cost is mostly already paid. Chosen.

## Consequences
- **Positive:** Every autonomous action is durably explainable and tamper-evident; the user can ask "why did you do X?" and get a real causal trace, not a post-hoc rationalization; satisfies ADR-0028's audit requirement and underpins ADR-0044 overrides and v2 enterprise audit (ADR-0047).
- **Negative:** fsync-on-commit adds latency to the action path (mitigated by batching AUTO entries and only hard-syncing before irreversible actions); the log grows unbounded (mitigated by rotation/compaction of *old* segments while preserving the hash chain across rotations); storing soul-state references couples the log format to ADR-0034.
- **Future work:** A queryable index over the append-only log for fast "show me all sends last week"; signed log export for enterprise compliance (ADR-0047); replay-for-explanation that re-walks a stored trace to render a natural-language account via pure substrate output (ADR-0013, ADR-0038).

## Implementation Notes
`core/safety.nova` gains `decision_log_open`, `decision_log_append(entry)`, `decision_log_iter`, and `decision_log_verify` (re-checks the hash chain). Storage uses `runtime/db.nova` segment files with fsync; entries serialized via `runtime/json.nova` or a compact binary record. The `signal_trace` field is taken directly from the gating signal's `trace` per `core/signal.nova`. Hash chaining uses `runtime/crypto.nova`. Write ordering: append intent entry + fsync (for `REV_IRREVERSIBLE`, ADR-0042) -> run effector -> append outcome entry. Inspection surfaces through the self-model query API (ADR-0038) rendering log entries as language via pure substrate (ADR-0013) — explicitly NOT through `runtime/llm.nova`. Snapshot/rehydration (ADR-0048) treats the log as durable-but-separate (it is not rolled back by a substrate snapshot restore). DEPENDS ON: NOVA enhancement #9 — append-only, crash-safe (fsync) decision/audit log atop `runtime/db.nova` + `core/safety.nova`. Tests: kill-process-mid-action and assert no executed action lacks an entry; assert hash-chain verification fails on a mutated entry; assert AUTO actions still log.

## Implementation Status

**Increment 3 (landed): the chat path is audited.**
`src/agent/cognitive_router.nova` gains a session-scoped audit-log register
(`cr_set_audit_log`, `_cr_audit_log` — a 1-element list NOVA-idiomatic
module-mutable handle, wired-or-not the way `dl_open` is). The NL-answer path
in the router (yes/no + how-many) reads the register; if a log is wired, the
call goes through `nlq_respond_audited` and CONTESTED replies leave a
DLK_DECISION trail, otherwise the original unaudited `nlq_respond` runs. This
bypasses the 6-arg passing limit that prevented threading the log down
`router_reply` directly. `examples/crossengin_chat.nova` calls
`cr_set_audit_log(_boot_log)` once at chat boot, right after `dl_open` -- so
every contested answer in a real session writes through automatically. Verified:
`router_audit` 6 checks (default off; wire/read round-trips; rewire replaces
without leaking; unwire restores off). `cognitive_router` baseline is unchanged
(no regression from the `_cr_nlq_answer` 3-arg signature).

**Increment 2 (landed): the answer path is audited.**
`src/language/nl_audit.nova` wraps `nlq_respond` as
`nlq_respond_audited(kg, aliases, text, log, moment)`: when the answer comes
back CONTESTED (the debate engine reported a multi-extension contention), the
wrapper persists the debate trace for the same claim atom as one DLK_DECISION
entry alongside the steelmanned reply the user sees. So every time the user is
told "this is contested", `drec_render` on that entry can later reconstruct
which arguments were weighed and what verdict the debate engine returned. The
answer record carries the claim atom id out via a `nlq_claim` accessor (set by
`_nlq_ans_set_claim` to sidestep NOVA's 6-arg passing limit). Non-contested
answers don't write -- the per-effector audit (`audit_writer`) already covers
the action surface, and this log is reserved for adjudications. Verified:
`nl_audit` 12 checks.

**Increment 1 (landed): reasoning adjudications persist to the decision log.**
`src/parts/reasoning/decision_record.nova` bridges the truth-seeking engine
(ADR-0089/0090/0092) to this log. The core gains a `DLK_DECISION` kind; a debate
trace, a steelman position-set, or a governed-promotion outcome each appends one
immutable, hash-chained `DLK_DECISION` entry. The reasoning semantics live in the
recorder (the core stays domain-free, the way `audit_writer` owns the effector
semantics): `goal` = the claim atom id, `desc = [ACLASS_REASONING, subtype,
scalar, flag]` where subtype is debate/promotion/steelman, scalar is the
adjudicated confidence / assigned grade / surviving-position count, and flag is
the contested bit / terminal `cand_state`; `outcome` is OK for a decided/promoted
claim, VETOED for a contested/failed one. The `trace` field holds the premise
atom ids weighed (the field's flat-int contract — the full per-argument structure
stays in the debate trace object, reconstructible from the snapshot, as this ADR
already documents the trace to be). `drec_render` reconstructs each entry in
plain language with no LLM (ADR-0014/0038). Verified via the bootstrap:
`decision_record` 33 checks (decided debate → OK + premise trace; contested debate
→ VETOED; promotion grade/state → OK vs VETOED; contested steelman → 2 positions;
a mixed debate→promotion chain verifies and a field-tamper is caught). The
durable file seam (`dl_open`/fsync) is unchanged and already covered by
`decision_log` + `chat_state`.
