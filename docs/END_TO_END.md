# End-to-end integration transcript

Nine PRs have shipped surfaces across Phases 0–6 pt1. This document is **one scripted session** that chains every pt1 command in order, captures the real output, and annotates each step with the phase + PR that introduced it. Read this to verify the whole stack works together.

## Running the script

```bash
export CE_AGENTS_DIR=/home/user/crossengin_agents   # Phase 5 pt1
./bin/crossengin-chat <<'EOF'
/seed
/seed logic
/seed medical
/seed code_review
/__corpora__
fever
/good
fever
/good
# ... (repeat to 10 total) ...
/__learning__
/__routing__
/__compiled__
learn antibiotics
null_deref
sql_injection
/cap list
/retract fever
n
/__safety__
/mcp register weather sunny-72F
/mcp call weather
/agent info /home/user/crossengin_agents/sample.bundle
/learn_prepare antibiotics
y
/quit
EOF
```

Captured output appears inline below, grouped by phase.

---

## 1. Startup (seed KG, Phase 0 baseline)

```
=== CrossEngin chat ===
state persists across turns; type 'quit' / 'exit' / empty / Ctrl-D to leave
type /help for admin commands (/teach, /pin, /status, /halt, ...)

(seed: 584 atoms, Aurora ready)
```

584 atoms is the baseline from `src/seed/first_atoms.nova` — unchanged by any phase.

---

## 2. Seeded packs — Phase 4 pt1 (logic) + Phase 5 pt2 lite (code_review)

```
> /seed
domain seed packs (4 available):
  medical (~60 atoms) -- anatomy + symptoms + drugs + common-condition operators
  ops_runbook (~45 atoms) -- service / alert / metric concepts + common-incident operators
  code_review (~80 atoms) -- review vocabulary + smells + review-rule operators
  logic (~50 atoms) -- logical primitives + named inference rules + chain scaffolding
(usage: /seed <name>  or  /seed --reset <name>)

> /seed logic
(seed pack 'logic' installed: 50 atoms + 38 operators; KG now 668 atoms)

> /seed medical
(seed pack 'medical' installed: 60 atoms + 11 operators; KG now 730 atoms)

> /seed code_review
(seed pack 'code_review' installed: 80 atoms + 37 operators; KG now 846 atoms)

> /__corpora__
  pack=src:pack:logic  atoms=50  promo_rate_milli=0  atrophy_rate_milli=0
  pack=src:pack:medical  atoms=60  promo_rate_milli=0  atrophy_rate_milli=0
  pack=src:pack:code_review  atoms=80  promo_rate_milli=0  atrophy_rate_milli=0
packs_installed=3
```

- `/seed` and `/seed <name>` existed before the phase-arc; **Phase 4 pt1 (PR #24)** added `logic`; **Phase 5 pt2 lite (PR #28)** doubled `code_review` from 40 to 80 atoms + 7 to 37 operators.
- **Phase 4 pt1** also added `/__corpora__` — the focused view on seeded packs over `mo_report(mo)`.

KG climbs from 584 → 668 → 730 → 846 as each pack lands. Idempotent: re-running `/seed logic` prints `(already installed; use /seed --reset logic to re-apply)`.

---

## 3. The frequency-adaptive-latency demo — Phase 0 pt1-pt4

10× `fever` + `/good`. Each cycle:

```
> fever
agent> infection leads to headache (infection->symptom->fever->headache).
       perceive(m=1,unk=0)
       reasoning: unknown: forward-chain infection->symptom->fever->headache
> /good
thanks -- reinforced 3 inference(s).
```

Then the observability triplet:

```
> /__learning__
synapse_live=11
synapse_total=11
synapse_mean_weight=272
ff_goodness=605000
mc_entries=1
mc_hits=9
mc_misses=1
ia_proto_strength_unknown=10
dlog_entries=20
tick=10

> /__routing__
routing_entries=1
  topic=21663 shape=2459 kg=reasoning hits=10 mean_lat_ticks=0

> /__compiled__
compiled_count=2
compile_threshold=500
  cc:infection->fever [via symptom] (infection -> fever)
  cc:symptom->headache [via fever] (symptom -> headache)
```

Every number here comes from a specific pt wire-up:

| Metric | What it proves | Shipped by |
|---|---|---|
| `mc_hits=9 / mc_misses=1` | HDC moment cache (Phase 0 pt4) short-circuits 9 of 10 near-identical queries via `hdc_cosine >= 900` | PR #20 |
| `ff_goodness=605000` | Forward-Forward layer (Phase 0 pt3) trains on the active moment via `ff_train_pair` on `/good` | PR #19 |
| `ia_proto_strength_unknown=10` | Adaptive intent prototypes (pt4) bundle the user utterance HDC into the matched CAT_* prototype | PR #20 |
| `routing_entries=1` | kg_router (pt4) records one (topic_hash, shape_hash) → (kg_label, hits, mean_lat) row | PR #20 |
| `compiled_count=2` | Chain compiler (pt3) mints direct `A → C [via B]` operators once both legs clear `syn_weight ≥ 500` | PR #19 |
| `synapse_mean_weight=272` | Hebbian plasticity via `router_apply_feedback` bumps each chain edge by +100 milli per `/good`; mean averages across live synapses | PR #19 |

The 272-not-300 mean (vs. the Phase 0 pt2 PR's 300) reflects the pre-session pack-loading: more atoms exist, more synapses live, un-reinforced edges drag the mean down. The chain's reinforced edges still saturate at `W_MAX=1000`.

---

## 4. Free prompting — Phase 3 pt1

`learn antibiotics` typed **without** a slash auto-prefixes to `/learn antibiotics`:

```
> learn antibiotics
(no cache for 'antibiotics' [topic] at /tmp/crossengin_learn_antibiotics.txt)
  run first:  scripts/learn.sh antibiotics
```

- **Phase 3 pt1 (PR #22)** added `_try_auto_prefix` with an allowlist (`learn`, `teach`, `why`, `know`, …) + denylist (`halt`, `save`, `retract`, `fed_*`, `gossip_*`, …).
- Topic-mode `/learn <topic>` already existed; it reads `/tmp/crossengin_learn_<tag>.txt` written by `scripts/learn.sh`.

Try a denylisted verb bare — `retract fever` — and auto-prefix declines, letting NL handle the retract (which now goes through the pt1-safety cap gate, see §6).

---

## 5. Coding-reviewer traversal — Phase 5 pt2 lite

`null_deref` and `sql_injection` as bare NL inputs — the forward-chainer walks the `smell → remedy` edge the pack installs:

```
> null_deref
agent> null_deref leads to guard_clause (null_deref->guard_clause).
       reasoning: unknown: forward-chain null_deref->guard_clause

> sql_injection
agent> sql_injection leads to parameterize_query (sql_injection->parameterize_query).
       reasoning: unknown: forward-chain sql_injection->parameterize_query
```

- 37 operators in `src/seed/packs/code_review_pack.nova` map smells to remedies (**Phase 5 pt2 lite, PR #28**).
- Multi-remedy smells (`sql_injection → parameterize_query` AND `sanitize_input`; `xss_vuln → escape_output` AND `sanitize_input`) let `/good` feedback tune the reviewer's preference via Phase 0's synapse-weighted retrieval.

---

## 6. Capability gate + attestation — Phase 1 pt1 + pt1-safety ext

```
> /cap list
  read_kb override=default default=allow
  answer override=default default=allow
  autonomous_fetch override=default default=require_approval
  ingest_atom override=default default=allow
  promote_atom override=default default=require_approval
  self_update override=default default=require_approval
  edit_governance override=default default=require_approval
  network_send override=default default=require_approval
  delete override=default default=require_approval

> /retract fever
agent> would like to retract atom: fever. approve? [y/N/why]
> n
agent> declined (retract atom).

> /__safety__
safety_attestations=1
  #24 attest delete -> deny
```

- **Phase 1 pt1 (PR #21)** shipped `cap_session.nova`, `approval_prompt.nova`, `safety_log.nova`, and the `_gate_or_prompt` helper; `/cap list` renders the per-cap effective policy; `/retract` runs the inline `y/N/why` prompt.
- **pt1-safety ext (PR #23)** routes the NL-grammar `retract` path through the same gate; **pt1-safety ext2 (PR #26)** extended the gate to `capsule_install`, `skill_install`, `skill_run`.
- `/__safety__` renders the hash-chained attestation log (`dl_append`-backed) filtered to `DREC_ATTEST=20` entries.

---

## 7. MCP registry — Phase 6 pt1

```
> /mcp register weather sunny-72F
registered: weather

> /mcp call weather
ok=1  bytes=9  body="sunny-72F"
```

- **Phase 6 pt1 (PR #29)** exposes `effector_mcp.nova`'s existing canned-response registry via `/mcp list | register | call`.
- NOT a real MCP server — see `docs/MCP_INBOUND.md` for the scope gap and Phase 6 pt2+ roadmap.
- The shim is inlined locally to work around NOVA runtime gap **D-3** (`_g_TR_TAG` symbol collision via `tool.nova`'s two transitive import paths).

---

## 8. Agent Rx surface — Phase 5 pt1

Against a 517-byte fabricated bundle at `/home/user/crossengin_agents/sample.bundle`:

```
> /agent info /home/user/crossengin_agents/sample.bundle
path=/home/user/crossengin_agents/sample.bundle
  name=clinical-rx-sample
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

- **Phase 5 pt1 (PR #25)** shipped `src/factory/agent_bundle.nova` parsers (header, signer-pk, section-count) and the `/agent list | info | verify` chat surface.
- `ab_read_file` uses the proven `alloc + _sys_read_tagged + load8` pattern (workaround for NOVA runtime gap **F-4**, documented in PR #27).

With `CE_AGENT_VERIFY_PUBKEY_HEX` set, `/agent verify <path>` delegates to `bake_verify_bundle` and attests `CAP_DELETE → allow/deny` for every signature decision.

---

## 9. Topic-fetch guide — Phase 2 pt2 + Phase 3 pt1

```
> /learn_prepare antibiotics
agent> would like to fetch topic via scripts/learn.sh: antibiotics. approve? [y/N/why]
> y
# Phase 3 pt1: run this command to cache 'antibiotics'
# then come back to the chat and type `learn antibiotics`.
scripts/learn.sh antibiotics
```

- **Phase 3 pt1 (PR #22)** introduced `/learn_prepare` as the operator-guide convenience command.
- Approval is `CAP_AUTONOMOUS_FETCH`-gated — the attestation log records the operator's intent to fetch even though the shell runs the fetch itself.
- Pt2-ollama (`/ingest_ollama`) and `/learn_prepare` both follow the same "print the exact two-step command, don't exec" pattern, because the in-tree `exec_program` hits NOVA runtime gaps P-3 + B-5 + P-4 (documented in PR #27).

---

## 10. Quit

```
> /quit
bye.
```

---

## Phase / PR cross-reference

| Phase + part | PR | What this transcript proves |
|---|---|---|
| Phase 0 pt1-pt3 | #19 | synapse-weighted retrieval, chain compiler, Forward-Forward, HDC |
| Phase 0 pt4 | #20 | moment cache LRU, kg_router, intent-adaptive prototypes |
| Phase 1 pt1 | #21 | `_gate_or_prompt`, `/cap`, `/__safety__` |
| Phase 1 pt2 | — | verify-on-load, child-mode, review queue, deny-list/whitelist (not exercised here) |
| Phase 2 pt1 | — | reply composer (dormant without `CE_OLLAMA_COMPOSER=1`) |
| Phase 2 pt2 | — | `/ingest_ollama` guide (same pattern as `/learn_prepare` above) |
| Phase 3 pt1 | #22 | auto-prefix router (`learn antibiotics`), `/learn_prepare` |
| pt1-safety ext | #23 | NL `retract` path through cap gate |
| Phase 4 pt1 | #24 | `logic` pack, `/__corpora__` |
| Phase 5 pt1 | #25 | `/agent list | info | verify` |
| pt1-safety ext2 | #26 | NL `capsule_install` / `skill_install` / `skill_run` through cap gate |
| NOVA gaps doc | #27 | `docs/NOVA_RUNTIME_GAPS.md` entries + upstream issues nova#7-10 |
| Phase 5 pt2 lite | #28 | coding-reviewer pack (80 atoms + 37 operators), `docs/CODING_REVIEWER.md` |
| Phase 6 pt1 | #29 | `/mcp list | register | call`, `docs/MCP_INBOUND.md` |

## What's deferred

- Phase 1 pt2 full exercise (snapshot verify-on-load, child mode) — needs a signed test bundle.
- Phase 2 pt1 reply composer in action — needs a running Ollama daemon.
- Phase 4 pt2 (bulk corpora) — needs compute + licensing.
- Phase 5 pt2+ (full lifecycle: `/agent install | new | teach | bake`) — needs destructive-path wiring.
- Phase 5 pt3 (code-reviewer ~400 extra pattern atoms from Stack Overflow via Ollama extractor) — needs the Phase 2 extractor + the review queue end-to-end.
- Phase 6 pt2+ (real MCP server) — needs NOVA upstream issues #7-10 + a JSON parser.
- Phase 7 (cowork orchestrator) — needs federation layer + agent discovery.

Each deferred item is tracked either in a scoped section of this plan or in an open upstream issue.
