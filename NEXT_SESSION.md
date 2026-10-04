# CrossEngin — Next Session

This file is the source of truth for what works, what does not, and where to
continue. It is updated at every session boundary.

## R44 -- chat REPL back to life + first 4 real domain packs + hash-indexed scan

**Status: complete.** R43 built the ingestion layer but couldn't yet demo it
interactively because the chat REPL had been segfaulting on startup for many
commits. R44 fixed the chat, then landed the first four production `.cerec`
packs and hardened `mkgc_scan_conflicts` for real-corpus scale.

### 1. Chat REPL fixed (3 root causes)

The chat had been segfaulting immediately for ~10+ commits before this round.
Three interacting bugs, each an interaction between chat code and a
NOVA-runtime quirk that CrossEngin already routes around elsewhere.

- `io_println` / `io_input` from `std/io` segfault in this NOVA runtime.
  Migrated **626+4 sites** in `crossengin_chat.nova` to the builtins
  `println` / `read_line` (same pattern the working daemon uses).
- `src/session/session.nova::_sreg_index` used flaky `str_eq` on the
  session id "default" (short-literal bug). `sreg_lookup` returned 0,
  `session_log(0)` segfaulted. Migrated to `str_eq_bytes`.
- `crossengin_chat.nova` had **185 slash-command `str_eq` calls** subject
  to the same short-literal flakiness. Migrated all to `str_eq_bytes`.
- Regression: `test_session.nova` had 23 `str_eq` calls on
  "edge"/"fresh"/"stale" that had been silently cancelling with the
  broken `sreg_lookup`; migrated too. Back to 66 checks green.

**Verified end-to-end**: chat boots, ingests, runs `/kg_consistency`, exits
cleanly.

### 2. Four real domain packs landed

The first content demonstrating that the R43 layer works with actual
authored corpora:

| Pack | Atoms | Focus |
|---|---|---|
| `solar_system.cerec` | 33 | Planets, Sun, moons, IAU 2006 taxonomy |
| `physics.cerec` | 35 | Classical + particle physics; overlaps astronomy |
| `world_history.cerec` | 43 | Antiquity → 20th century milestones |
| `folk_astronomy.cerec` | 5 | Low-belief historical / folk beliefs |
| **Total** | **116** | Across 4 KGs |

**Cross-KG conflict demonstration (in the chat REPL):**

```
> /ingest cerec data/packs/solar_system.cerec  astronomy       src:pack:solar_system:v1
> /ingest cerec data/packs/physics.cerec       physics         src:pack:physics:v1
> /ingest cerec data/packs/folk_astronomy.cerec folk_astronomy src:pack:folk_astronomy:v1
> /kg_consistency 200
(empirical belief conflicts across KGs, spread >= 200 milli:)
  'planet': astronomy believes 950 vs folk_astronomy believes 400
  'sun':    astronomy believes 1000 vs folk_astronomy believes 200
  'earth':  astronomy believes 1000 vs folk_astronomy believes 600
  'planet': folk_astronomy believes 400 vs physics believes 1000
  'sun':    folk_astronomy believes 200 vs physics believes 1000
  'earth':  folk_astronomy believes 600 vs physics believes 1000
```

Physics **agrees with astronomy** on all shared labels (0 astronomy↔physics
conflicts at spread 200) and **contradicts folk_astronomy** on the same
labels the scientific packs disagree with — exactly the shape the vision
promised.

### 3. Hash-indexed `mkgc_scan_conflicts`

Replaced the O(kgs² · atoms²) pair-scan with a label hash-index:
- FNV-1a-flavored byte fold over labels; 256 buckets.
- Build: O(N) over all atoms across all KGs.
- Match: O(sum of squared bucket sizes) — essentially O(N) for typical
  corpora where most labels appear in one or two KGs.
- Worst case: still O(N²) on adversarial input, but no worse than before.

Unblocks the roadmap item "million-atom Wikidata subset" — the scan cost is
now sub-quadratic for the realistic case.

### R44 test scoreboard (new/refreshed)

| Test | Checks |
|---|---|
| test_ingest_records | 36 → **39** (blank-line semantic change) |
| test_session | back to **66** (regression fix) |
| test_pack_solar_system | **16** |
| test_pack_physics | **6** |
| test_pack_world_history | **9** |
| test_mkgc_scale (new) | **5** |
| **New R44 total** | **35 new + refreshed** |

Full ingest + pack layer: **~380 checks green across 17 test files.**

### Where to go next

**Highest-leverage:**
1. Author packs for the remaining vision domains: religion, politics,
   biology, medicine (medical_pack.nova exists but as compiled NOVA, not
   `.cerec` — a rewrite would let it participate in the review-queue and
   cross-KG scans uniformly).
2. Real Wikidata subset ingest — the hash index unblocks this; needs a
   scoped subset (~10k atoms) to prove the pipeline holds under actual
   Wikidata URI conventions + labels TSV.
3. NOVA-0007 page-indexed atom store — currently a snapshot is one blob;
   million-atom KGs need per-atom addressability on disk.

**Structural improvements:**
- JSON parser adapter so LLM outputs can arrive as JSONL directly
  (currently the LLM must emit `.cerec`).
- Web-fetch scheduler: wire the real `tls13_client` into
  `ws_step_via_stub`'s slot.
- Structured → NL renderer (deterministic templater) so answers can go
  back through NL without an LLM in the answer path.

**Deferred (upstream / off-limits):**
- NOVA runtime bug fixes for the 7 catalogued in `src/util/str_safe.nova`,
  `_x509v_bytes_to_str`, and now `std/io::io_println/io_input`.

---

## Earlier rounds

R43 and all earlier session notes live in
[`docs/session_log/archive.md`](docs/session_log/archive.md) to keep this
file short and fast to read. The archive is reverse-chronological (R43
newest, oldest round at the end).
