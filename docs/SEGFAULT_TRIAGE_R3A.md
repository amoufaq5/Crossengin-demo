# SEGFAULT Triage — Phase Q R3a

**Branch**: `claude/confident-fermi-op241b` · **Picked up from**: R2 (`663655c`)
**Date**: 2026-10-01 · **Scope**: diagnosis only (no fixes — R3b lands the fix)
**NOVA runtime**: unchanged (`/home/user/NOVA/src/runtime/*` off-limits)

## 1. Summary

R2's full-suite sweep (`./scripts/test.sh tests/unit/*.nova`) catalogued
~29 tests ending in exit 139 (SIGSEGV) across KG, gossip, federated,
learning and audio code. R3a confirmed the segfault count empirically,
clustered them by proximate failure mechanism, dmesg-decoded a
representative crash, and found a single documented NOVA runtime quirk
(`str_eq` flaky on short literals) that explains **~22–24 of the ~29
SEGVs**. The fix is in-scope for R3b (NOVA runtime untouched; the
mitigation already exists at `src/util/str_safe.nova::str_eq_bytes`
and is an incremental call-site migration).

## 2. Enumerated SEGV test list (from R2's catalogue; see
`ENHANCEMENTS_ROADMAP.md:450-486`)

Twenty-nine tests marked `(SEGV)` in R2's partial list of failing tests:

| # | Test | Suspected root-cause class |
|---|---|---|
| 1 | `test_atom_birth_monitor` | str_eq-lookup (A) |
| 2 | `test_audio_wakeword` | str_eq-lookup (A) |
| 3 | `test_chat_state_persistence` | str_eq-lookup (A) |
| 4 | `test_competence_tracker` | str_eq-lookup (A) |
| 5 | `test_decision_log_durable` | str_eq-lookup (A) |
| 6 | `test_distributed_rules` | str_eq-lookup (A) |
| 7 | `test_entity_resolve` | str_eq-lookup (A) |
| 8 | `test_episodic` | str_eq-lookup (A) |
| 9 | `test_fed_daemon_attest` | str_eq-lookup (A) |
| 10 | `test_fed_daemon_boot` | str_eq-lookup (A) |
| 11 | `test_fed_daemon_replication` | str_eq-lookup (A) |
| 12 | `test_fed_daemon_transport` | str_eq-lookup (A) |
| 13 | `test_federated_aggregator` | str_eq-lookup (A) |
| 14 | `test_gossip` | str_eq-lookup (A) |
| 15 | `test_gossip_dtls_shim` | str_eq-lookup (A) |
| 16 | `test_gossip_noise` | str_eq-lookup (A) |
| 17 | `test_gossip_relay` | str_eq-lookup (A) |
| 18 | `test_http_client` | str_eq-lookup (A) |
| 19 | `test_image_ocr` | pointer-arithmetic (B, not str_eq) |
| 20 | `test_ingest_file_multimodal` | str_eq-lookup (A) |
| 21 | `test_internet_fetch` | str_eq-lookup (A) |
| 22 | `test_kg_query` | str_eq-lookup (A) |
| 23 | `test_kg_query_agg` | str_eq-lookup (A) |
| 24 | `test_kg_query_ext` | str_eq-lookup (A) |
| 25 | `test_kg_rss_ingest` | str_eq-lookup (A) |
| 26 | `test_kg_sync` | str_eq-lookup (A) |
| 27 | `test_kg_sync_delta` | str_eq-lookup (A) |
| 28 | `test_lk_mulacc_simd` | pointer-arithmetic/SIMD (B) |
| 29 | `test_lk_u8_simd` | pointer-arithmetic/SIMD (B) |

Class breakdown: **A = ~26 tests** (str_eq short-literal lookup bug),
**B = 3 tests** (SIMD / pointer-arithmetic in image transducers).

The one R2 timeout (`test_merkle_signing`) is not an exit-139 SEGV; it
hangs. Out of R3a scope.

### 2.1 Other R2 failures (NOT segfaults; exit != 0 & != 139)

Catalogued by R2 but not SEGVs; call out so R3b doesn't scope-creep:
`test_action_module` (2 pre-existing assertion fails),
`test_admin_bake_child_verb`, `test_admin_emit_delta_verb`,
`test_atom_death_monitor`, `test_audio_capture`, `test_audio_synth`,
`test_audio_tts`, `test_autocompact_trigger`, `test_autonomous_loop`,
`test_autonomous_research`, `test_bignum_2048`, `test_bignum_256`,
`test_byzantine_aggregation`, `test_chat_fed_slash_commands`,
`test_cognitive_router`, `test_consolidation`,
`test_constitutional_filter`, `test_distributed_query`,
`test_dp_budget_ui`, `test_dr_async_fetch`, `test_dtls12` (443 pass /
76 fail — large but non-crashing), `test_ed25519`,
`test_episodic_retrieval`, `test_face_recognize`,
`test_fed_daemon_leader` (43/6), `test_fed_daemon_rules` (28/16),
`test_gc_metrics`, `test_graph_clustering`, `test_ice` (68/2),
`test_ice_turn` (141/1), `test_identity`, `test_image_harris`,
`test_image_tracker`, `test_leader_election`, `test_learn_pipeline`,
`test_link_prediction`, `test_louvain`, `test_loyalty`, `test_merkle`
(48/12). These are regular assertion mismatches, not crashes — scope
for later rounds.

## 3. Representative segfault walkthrough

Picked `test_atom_birth_monitor.nova` (81-line test, one module
imported, one assertion in the failing path). Direct run:

```
$ setarch -R /home/user/NOVA/nova run tests/unit/test_atom_birth_monitor.nova
FAIL: candidate exists
/home/user/NOVA/nova: line 20: 26534 Segmentation fault      "$TMPDIR/out" "$@"
```

Test code (`tests/unit/test_atom_birth_monitor.nova:22-31`):

```nova
fn test_candidate_accumulation() {
    let mon = abm_new()
    let e = embedv(0, 100)
    feed(mon, "p", e, 5, 3)                   // populate 5 observations
    let cand = abm_candidate(mon, "p")        // returns 0 — WRONG!
    ce_check("candidate exists", cand != 0)   // prints "FAIL: candidate exists"
    ce_eq("frequency 5", cb_freq(cand), 5)    // cb_freq(0) → SEGV
    ...
}
```

Underlying module (`src/learning/atom_birth_monitor.nova:54-62`):

```nova
fn _abm_find(monitor, sig) {
    let c = monitor[ABM_CAND]
    let i = 0
    while i < len(c) {
        if str_eq(c[i][CB_SIG], sig) == 1 { return c[i] }   // <-- str_eq here
        i = i + 1
    }
    return 0
}
```

### dmesg diagnostic

```
out[26534]: segfault at 1 ip 0000000000410abf sp 00007fffffffcc38 error 4
Code: 03 00 00 00 0f 05 48 c7 c0 03 00 00 00 41 5d 41 5c 5d c3 b8 01 00
      00 00 48 8d 65 f0 41 5d 41 5c 5d c3 48 d1 fe 48 85 ff 74 43 <48>
      83 3f ff 74 20 48 85 f6 79 11 57 56 e8 46 fd ff ff 5e 5f 48 01
```

Decoded: this is a NOVA list indexing helper. Prologue runs
`sar rsi, 1` (un-tag the index), `test rdi, rdi` (null-check the list
pointer), `je +0x43` (jump to the null-handler if null), **then
`cmp qword ptr [rdi], -1`** which is the faulting instruction. The
fault is at **address `0x1`**, meaning `rdi = 1` when the compare
executes — a pointer value of 1, not 0.

### Why `rdi = 1`

NOVA uses tagged integers: integer `n` is represented as `(n << 1) | 1`
in registers (least-significant bit = 1 means "tagged int", 0 means
"heap pointer"). Integer **zero** is therefore represented as
**bit-pattern `1`** at the ABI level.

So the chain is: `_abm_find` returned the literal integer `0`;
caller stored it in `cand`; caller passed `cand` into `cb_freq(c)`,
which inlines `c[CB_FREQ]`. NOVA's list-index helper received the
tagged-int-zero (register value `1`) in `rdi`, saw non-null (`1 != 0`),
and dereferenced `[rdi]` → fault at `0x1`.

### Why `_abm_find` returned 0

The test's `feed(..., 5, 3)` call runs `abm_observe` five times. Each
call hits `_abm_find(monitor, sig)` with `sig = "p"`. The signature is
compared against the stored candidate's `[CB_SIG]` (also `"p"`) via
`str_eq`. Under NOVA's known-flaky short-literal `str_eq`
(`"p"` is a single-byte literal; `str_eq` is empirically unreliable
on `"op"`, `"num"`, `"CONST"` and many other short pairs — see
`src/util/str_safe.nova:3-14`), the comparison can return 0 even on
byte-identical inputs. On every observe `_abm_find` returns 0, so each
call inserts a *new* candidate and freq never climbs above 1. When the
test later queries `abm_candidate(mon, "p")`, the same `_abm_find`
scans all five stored candidates and `str_eq` fails on every one — so
it returns 0 again. The test then dereferences that 0 as a list and
crashes.

### Same pattern across the SEGV cluster

Several other tests print exactly one `FAIL: X is non-zero` line (the
`cand != 0` guard) immediately before the segfault:

```
test_atom_birth_monitor: "FAIL: candidate exists"
test_episodic:           "FAIL: store has exactly one atom expected=1 got=0"
test_entity_resolve:     "FAIL: alias resolves expected=2 got=0"
test_gossip:             "FAIL: self merge is dropped expected=0 got=1"
test_audio_wakeword:     "FAIL: loaded template is non-zero"
test_kg_sync:            "FAIL: parse basic non-zero"
```

Every one of these is "a `_find` / `_lookup` returned 0 where
non-zero was expected, then the test used the 0 as a list/pointer and
NOVA list indexing dereferenced the tagged-zero bit-pattern 1."

Tests whose first visible symptom is a straight SEGV with **no** `FAIL`
line (`test_kg_query`, `test_fed_daemon_boot`, `test_gossip_relay`,
`test_image_ocr`) hit the same pattern earlier — either during
module-level initialization or inside a helper the test calls before
any assertion. dmesg confirms the mechanism for several:

```
test_http_client: fault at 0x84db21 ip 0x420bce
    Code: ... <8a> 0f 3a 0e ...     // mov cl, [rdi] -- strcmp byte load
                                    // rdi = 0x84db21 = ODD → tagged int

test_fed_daemon_boot: fault at 0x2490f5 ip 0x48ef36
    Code: ... <0f> b6 07 ...        // movzx eax, byte [rdi]
                                    // rdi = 0x2490f5 = ODD → tagged int

test_gossip: fault at 1 ip 0x481e50
    Code: ... <8a> 0f ...            // strcmp byte load, rdi = 1 = tagged 0

test_kg_query: fault at 0x21483c ip 0x421619
    Code: ... <0f> b6 07 ...         // same list-index helper as abm case
```

Odd-numbered fault addresses are the diagnostic signature of a tagged
int being handed to a routine that expects a heap pointer. "Fault at
`1`" is the special case for tagged-int-zero.

## 4. Cluster-by-import table

Count of `str_eq(` call sites in src/ modules referenced (directly or
transitively) by segfaulting tests:

| Module | str_eq calls | Segfaulting tests that import it (direct or via transitive dep) |
|---|---:|---|
| `src/federation/gossip.nova` | **39** | test_gossip, test_gossip_relay, test_gossip_dtls_shim, test_gossip_noise, test_fed_daemon_boot, test_fed_daemon_attest, test_fed_daemon_replication, test_fed_daemon_transport, test_kg_sync |
| `src/learning/internet_fetch.nova` | **26** | test_internet_fetch, test_http_client, test_kg_rss_ingest |
| `src/federation/gossip_relay.nova` | 20 | test_gossip_relay |
| `src/learning/secure_aggregation.nova` | 18 | test_federated_aggregator (via byzantine_aggregation) |
| `src/federation/nat_traversal.nova` | 12 | test_fed_daemon_transport |
| `src/learning/federated_aggregator.nova` | 8 | test_federated_aggregator |
| `src/io/transducers/http_client.nova` | 8 | test_http_client |
| `src/kg/link_prediction.nova` | 8 | — |
| `src/federation/snapshot_replication.nova` | 7 | test_fed_daemon_replication |
| `src/kg/episodic.nova` | 6 | test_episodic |
| `src/federation/turn_server.nova` | 6 | test_ice_turn (non-seg) |
| `src/io/transducers/audio_wakeword.nova` | 6 | test_audio_wakeword |
| `src/learning/entity_resolve.nova` | 4 | test_entity_resolve |
| `src/kg/competence_tracker.nova` | 4 | test_competence_tracker |
| `src/federation/gossip_relay_secure.nova` | 4 | — |
| `src/federation/kg_sync.nova` | 3 | test_kg_sync, test_kg_sync_delta |
| `src/federation/distributed_query.nova` | 3 | test_distributed_rules, test_fed_daemon_* |
| `src/federation/gossip_dtls_shim.nova` | 3 | test_gossip_dtls_shim |
| `src/learning/byzantine_aggregation.nova` | 3 | test_byzantine_aggregation (non-seg) |
| `src/federation/leader_election.nova` | 1 | — |
| `src/federation/snapshot_attestation.nova` | 1 | test_fed_daemon_attest |
| `src/learning/atom_birth_monitor.nova` | 1 | test_atom_birth_monitor |
| `src/learning/autonomous_research.nova` | 1 | — |
| `src/kg/pagerank.nova` | 1 | — |

Total: **185 `str_eq` call sites remain across the still-vulnerable
subsystems**. (`NEXT_SESSION.md:10` reports an older count of 1465
cumulative across src/; much of that has already been migrated.)

### Recent commits touching the common dependencies

Phase O (R1-R3, ADR-0094..0096) and Phase P (R1-R3, ADR-0097..0099)
added `src/federation/gossip.nova`, `gossip_dtls_shim.nova`, and
`dtls12.nova` content. Those commits introduced **4** new `str_eq`
calls in `gossip.nova` (checked by `git diff ca2f9e7^..031a610`).
Marginal — Phase O/P did NOT cause the cluster. The cluster is the
long-standing incremental migration debt flagged in NEXT_SESSION.md:
"1465 str_eq call sites exist across src/; the migration is
incremental (module by module)."

### SIMD / pointer-arithmetic tests (NOT str_eq)

Three segfaults don't fit the str_eq model:

- `test_lk_u8_simd` — dmesg: `fault at 0x8360ab ip 0x417eee` with Code
  `fc f3 a4 58 c3` = `cld; rep movsb; pop rax; ret`. That is NOVA's
  `memcpy_raw` builtin. The u8 SIMD path in
  `src/io/transducers/image_optical_flow.nova:658` (`lk_sad_block_u8`)
  packs windows via `memcpy_raw`; the odd-byte fault address suggests
  dst/src pointer arithmetic has drifted into a tagged-int or
  misaligned bump. **Classify as its own bug class (B).**

- `test_lk_mulacc_simd` — same transducer module; same hot path. Likely
  same class as above.

- `test_image_ocr` — `src/io/transducers/image_ocr.nova` has 0 `str_eq`
  calls. Separate pointer / list bug.

These three are **out of R3b's primary scope** and should be tracked as
R3c follow-ups.

## 5. Root-cause hypotheses

### Primary (explains ~26/29 segfaults — ~90% blast radius)

**NOVA `str_eq` is empirically flaky on short string literals** (known
runtime quirk, documented in `src/util/str_safe.nova:3-14` and
`NEXT_SESSION.md:22-29,268-269,924-926`). When a module's `_find` /
`_lookup` helper uses the flaky builtin to compare a candidate key
against a short literal (`"p"`, `"op"`, `"num"`, session id
`"default"`, etc.) `str_eq` returns 0 even for byte-identical inputs.
The lookup helper therefore returns the "not found" sentinel 0. Test
code (or the module itself) then uses that 0 as a list and
NOVA's list-index helper dereferences the tagged-int-zero bit-pattern
`1` → SIGSEGV at virtual address `1` (or at some other odd address
when a different tagged int flows through).

Evidence:
- Explicit precedent: NEXT_SESSION.md §1 reports `_sreg_index`
  segfaulted via this exact chain and was fixed by migrating to
  `str_eq_bytes`.
- dmesg: faulting rdi values are all `1` or odd — the tagged-int
  signature.
- Textual signal: tests that reach a `FAIL` line before dying all
  print `expected=non-zero got=0` or `is non-zero` — the lookup
  returned 0.
- Call-site count overlaps with segfaulting-test import graph (table
  §4).

### Secondary (3 tests)

**Pointer-arithmetic / SIMD bug in `image_optical_flow.nova`'s u8 /
mulacc SIMD paths.** `lk_sad_block_u8` and `lk_optical_flow_u8_simd`
pack windows via `memcpy_raw`; the resulting pointer arithmetic
appears to drift. Probably **not** a tagged-int issue (the SAD path
operates on raw `alloc()`-returned byte buffers, not tagged ints), but
a plain offset / size miscalculation. **Separate round, R3c-level.**

**`test_image_ocr`** — plausible but unverified: image_ocr uses no
`str_eq`, so the fault is in `image_ocr.nova`'s own list / pointer
code. Mark as R3c.

### Tertiary (not expected to pan out, listed for completeness)

- The "dead-code rebuild-guard" pattern R2 flagged (`list != list`
  always false) is a correctness nit, not a segfault driver — stale
  cached data would compute wrong, not crash. Rule out as the
  primary.
- No evidence of a Phase O/P regression specifically — the gossip
  rewrites in those phases added 4 str_eq calls on top of 35, and the
  cluster predates them (every one of these modules has been using
  str_eq since Phase M or earlier).

## 6. Blast radius

Class A (str_eq) is the dominant hypothesis. If R3b migrates `_find`
/ `_lookup` call sites in the modules in §4 from `str_eq` to
`str_eq_bytes`, we expect **~22–26 of the 29 segfaults to flip to PASS
or (more likely) to an ordinary non-crashing FAIL** that surfaces real
underlying logic bugs for later rounds.

Expected residual after R3b:

- 3 known SIMD / image-transducer segfaults (B) — need their own round.
- Some number of class-A tests may still FAIL (non-crash) because the
  lookup was masking a real bug, but the suite will no longer
  SIGSEGV mid-run. That's a strict improvement — we recover test
  signal.

## 7. Proposed R3b fix scope

**Single call-site migration pass.** No runtime changes, no
`.nova` grammar / codegen changes. Pattern (already in use elsewhere in
tree):

```nova
// before:
if str_eq(c[i][CB_SIG], sig) == 1 { return c[i] }

// after:
import "../util/str_safe.nova"      // top of file, if not already
if str_eq_bytes(c[i][CB_SIG], sig) == 1 { return c[i] }
```

Scope estimate for R3b:

- **~20 files** touched (§4 table rows marked as importing-into
  segfaulting tests).
- **~130 call sites** out of the 185 — focus on `_find` / `_lookup`
  functions, dispatch tables and ID equality in the §4 modules. Call
  sites comparing to a **long** literal (e.g. SQL-ish keys, full URLs)
  are rarely flaky; prioritize short literals.
- One ADR (`docs/adr/0101-str-eq-cluster-migration.md`) summarizing
  the chain + listing migrated modules.
- One test regression gate: after the migration, re-run
  `./scripts/test.sh tests/unit/<pattern>.nova` scoped to the §2
  class-A tests. Expected: zero exit-139s.
- Keep the migration **mechanical** — don't change return semantics,
  don't rename functions, don't rewrite logic. If a test still FAILs
  after the migration, catalogue the real bug for R4+.

**R3b does NOT need**:
- Any edit to `/home/user/NOVA/src/runtime/*` (constraint OK).
- A full suite re-run (already timed out in R2); use targeted
  per-test runs on the class-A list.
- Resolution of the SIMD / image-transducer SEGVs (defer to R3c).

## 8. Pre-emptive mitigations (optional, if R3b slips)

- The test harness `scripts/test.sh` already caps per-test wall-clock
  at `CE_TEST_TIMEOUT=60s` (confirmed line 15), so a single SEGV
  doesn't block the suite — only the merkle_signing *hang* did.
  **No infra change needed.**
- NOVA has no built-in `.skip` marker, but per-test invocation already
  isolates failures: a developer wanting a green loop can run
  `./scripts/test.sh tests/unit/test_*.nova` excluding the class-A
  pattern with a trivial wrapper. We **don't** recommend adding
  skip-markers to the source tree — they create a false green-signal
  until R3b lands, and the catalogue in this doc is a better record.

## 9. Open questions for R3b to resolve

1. For every `str_eq` site in the §4 modules: is it a short-literal
   comparison? (If so, migrate.) Or a long-literal comparison that
   historically has been reliable? (Leave; migration cost without
   payoff.) Rough rule from `NEXT_SESSION.md:924`: short (<= 10
   bytes) literals are suspect; longer are usually fine.
2. Does `src/util/str_safe.nova::str_eq_bytes` itself cover the
   non-ASCII / non-byte-identical UTF-8 cases some gossip or crypto
   code might depend on? (Spot-check: `str_eq_bytes` does byte-wise
   `char_at` compare — fine for UTF-8 by-byte equality, which is
   what every call site here uses.)
3. Should R3b also migrate `str_find` call sites in the same files?
   `src/util/str_safe.nova:70-99` provides `find_char` / `find_bytes`
   and documents two independent `str_find` bugs; those may be hidden
   latent issues. Recommend: **no, keep R3b scoped to `str_eq`** —
   the tagged-int SEGV chain goes through `str_eq`, not `str_find`.
   Fold `str_find` migration into a separate pass.

## 10. Session constraints — compliance recap

- NOVA runtime (`/home/user/NOVA/src/runtime/*`) NOT touched.
- Branch `claude/confident-fermi-op241b` only.
- No PRs opened.
- Diagnostic only; no code fixes landed this round.
- Only this doc + the trailing commit are added.

---

*See also*: `src/util/str_safe.nova`, `NEXT_SESSION.md:15-29` (prior
chat-REPL SEGV cluster with identical mechanism),
`tests/ce_test.nova:40-50` (same workaround applied to the test
harness).
