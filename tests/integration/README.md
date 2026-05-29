# Integration tests

End-to-end tests that drive the built binaries (`bin/crossengin`,
`bin/crossengin-chat`, `scripts/web.py`) and assert on their observable
behaviour. Catches the bug class that unit tests miss: race conditions,
durability failures across abrupt restarts, IPC corner cases, multi-command
interactions.

Run the whole suite:

```sh
make integration                 # builds the binaries first, then runs every *.sh
```

Each script is independent and self-summarizing — it prints per-assertion
PASS/FAIL lines and a final `integration <name>: pass=N fail=M` line.

## Suite layout

### Scenarios (multi-step, one acceptance test each)

| Script | What it proves |
|--------|---------------|
| `scenario_a_durability.sh` | `/teach` -> `/save` -> SIGKILL -> relaunch -> `/load` -> the taught atom survives. The P11 acceptance test. |
| `scenario_b_neighborhood.sh` | Seeded "fever" surfaces operator-chain neighbors (infection / treat / headache) via the P14 neighborhood activation. |
| `scenario_c_learn.sh` | `/learn TOPIC` and `/learn /file` both grow the KG; the chat logs the correct `[topic|url|file]` tag from P15. |
| `scenario_d_meta.sh` | `/meta` reports `seed` + `user-teach` rows with the expected promotion / atrophy rates (P13). |
| `scenario_e_constitution.sh` | A forbidden message ("exfiltrate ...") triggers a constitutional veto; `/why` reports `outcome=vetoed`. |
| `scenario_f_web.sh` | `scripts/web.py` default-binds 127.0.0.1, serves `/api/chat`, and cleans up on shutdown. |
| `scenario_h_session_switch.sh` | `/switch` flips the active session per-cookie inside one chat process; teaching `widget` in default and `gadget` in alice leaves each session knowing only its own word (P18 Half A). |
| `scenario_i_web_isolation.sh` | `scripts/web.py` spawns one ChatChild per unique `ce_sid` cookie; A teaches widget, B never sees it; `/api/sessions` lists both with diagnostics (P18 Half B). |

### Admin-command coverage (single-step edge cases)

| Script | Commands covered |
|--------|------------------|
| `admin_help_status.sh` | `/help`, `/status` |
| `admin_teach_pin.sh` | `/teach` (empty arg, twice with same word), `/pin` (missing args, out-of-range C) |
| `admin_save_load.sh` | `/save` (default + explicit path + invalid dir), `/load` (missing + corrupt + valid) |
| `admin_reflect_halt.sh` | `/reflect` (empty context + with depth), `/halt` -> drain -> `/resume` |
| `admin_learn_meta.sh` | `/learn` (TOPIC + FILE), `/meta` table shape |

### Failure-mode probes (P1.7)

The `failmode_*.sh` scripts target the bug class that drove several Agent-C-style
code-review findings: durability under crash, hostile / oversized input, IPC
peer death, runaway-input gating, and concurrent access. Each script either
asserts the system's *correct* response to the failure, OR -- when the test
revealed a real bug -- pins the *current observed behavior* with a `# KNOWN:`
comment so a future fix is detected (the test will start failing in the
opposite direction once the bug is closed, and must be updated then).

| Script | What it proves |
|--------|---------------|
| `failmode_disk_full_save.sh` | `/save` to a non-existent dir / read-only dir reports `(save FAILED: ...)` cleanly; the chat stays alive; a subsequent good-path save works. |
| `failmode_killed_mid_fsync.sh` | `kill -9` at three offsets inside the `/save` pipeline (0ms, 50ms, 200ms) never leaves a partial snapshot at the final path; the file always ends with `end\n`; a `/load` of the surviving file succeeds. |
| `failmode_corrupt_snap_recovery.sh` | A snapshot truncated to 100 bytes makes `/load` report FAILED; the running chat session's previously taught word is still recognized (failed load does NOT clobber live state). |
| `failmode_dlog_corrupt_tail.sh` | Appending garbage to the dlog tail triggers `dl_open: warning -- truncated corrupt tail of <path>` on restart; the original entry count is preserved; the on-disk file is rewritten to the good prefix. |
| `failmode_runaway_atom_births.sh` | Feeding 200 distinct unknown words yields a knowledge-count delta in [200, 800]; the auto-learn fires; the chat stays responsive. |
| `failmode_soul_mood_overflow.sh` | 50 alternating high-arousal turns leave `valence` and `arousal` inside [0, 1000]; no integer wrap or negative readings appear in any `/status` line. |
| `failmode_unknown_kg_load.sh` | A hand-rewritten snapshot with `kgs.atoms[0].kg unknownkg` loads successfully because `kg_spawn` is idempotent on label -- a NEW KG with that label is auto-created. Pins current behavior; documented for future "skip-with-warning" policy. |
| `failmode_kgsync_subscriber_drop.sh` | Killing the subscriber `-9` mid-stream does NOT cause the publisher to detect the drop on its next send (TCP buffer absorbs it); the publisher continues, then exits on `bye` / EOF. KNOWN: no liveness check; no reconnect-resume. |
| `failmode_web_concurrent_burst.sh` | 20 concurrent POSTs against the same `ce_sid` all complete without errors; no response is empty / has a missing `reply` field; the web server is still answering after the burst. |
| `failmode_web_huge_payload.sh` | A 1MB POST to `/api/chat` does NOT crash the web server (the response or follow-up error is returned cleanly); a fresh cookie can still spawn a working chat child. KNOWN: the chat segfaults on the huge percept; the server catches the dead child via `chat process has exited`. |
| `failmode_chat_long_line.sh` | A ~70-token line is processed cleanly; a ~200-token line currently SEGFAULTs the chat binary. CURRENT-BEHAVIOR pin -- KNOWN: chat segfaults on input lines longer than ~470 bytes. |
| `failmode_session_eviction.sh` | With `CE_WEB_MAX_SESSIONS=2`, hitting web.py with 5 unique cookies leaves exactly 2 in `/api/sessions` -- the most-recent 2; the first 3 were evicted in LRU order. |
| `failmode_save_load_ping_pong.sh` | 20 alternations of `/save` + `/load` in one chat session leave knowledge count, soul name, and taught words exactly as before -- no progressive corruption. |
| `failmode_constitution_bypass_attempts.sh` | 5 different rephrasings of "exfiltrate ..." all trigger `[refused]` + `outcome : vetoed`; no normal `agent> see X` reply slips through. KNOWN: the safety stack is a keyword filter today; rephrasings that avoid the trigger word are still allowed -- documented for future semantic-intent extension. |

### Shared library

`_lib.sh` holds the assertion harness (`assert_eq`, `assert_match`,
`assert_nomatch`), path constants, the `run_chat`/`it_section`/`summary`
helpers, and the require-binary guards. Every script begins with
`. "$(dirname "$0")/_lib.sh"`.

## Writing a new test

1. Copy a small script like `admin_help_status.sh` as a template.
2. Source `_lib.sh`, declare a section heading, run the binary with
   piped stdin, capture stdout, and assert on the structure (not exact
   strings — the agent's natural-language reply varies).
3. End with `summary "<script-stem>"`. The Makefile target picks up
   `*.sh` (not `_*.sh`), so the leading underscore on `_lib.sh` keeps
   it out of the run-set.

## When integration tests fail

A failing script prints `FAIL  <name>` lines with `expected:` / `got:`
diffs. Re-run a single script directly to iterate:

```sh
bash tests/integration/scenario_a_durability.sh
```

Most flakiness comes from timing (the chat needs a beat after a command
before its reply lands in the output capture). Bump the `sleep` calls
in the script, NOT in `_lib.sh`.

**Governing ADR:** ADR-0049 (testing and benchmarks).
