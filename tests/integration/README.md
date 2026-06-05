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
| `failmode_unknown_kg_load.sh` | A hand-rewritten snapshot with `kgs.atoms[0].kg unknownkg` loads successfully but the unknown-kg atom is dropped: `kg_section_apply` enforces a strict-or-skip policy -- the atom's `kg` label is validated against the known-KG set (reasoning / language / imagination / world) and an unknown label triggers a `warning: snapshot atom #N has unknown kg 'X' -- skipped` line, then the atom is rejected (`new_atoms=0`). Blocks a malicious snapshot from auto-spawning arbitrary KGs. |
| `failmode_kgsync_subscriber_drop.sh` | Killing the subscriber `-9` mid-stream is detected via the v2 PING/PONG heartbeat (5s ping + 2s timeout): the publisher emits `send failed (subscriber gone)` or its tally line on the next send rather than continuing to write into the void. Publisher still exits cleanly on `bye` / EOF for the happy-path case. |
| `failmode_web_concurrent_burst.sh` | 20 concurrent POSTs against the same `ce_sid` all complete without errors; no response is empty / has a missing `reply` field; the web server is still answering after the burst. |
| `failmode_web_huge_payload.sh` | A 1MB POST to `/api/chat` does NOT crash the web server (the response or follow-up error is returned cleanly); a fresh cookie can still spawn a working chat child. KNOWN: the chat segfaults on the huge percept; the server catches the dead child via `chat process has exited`. |
| `failmode_chat_long_line.sh` | A ~70-token line is processed cleanly AND a ~200-token line is now processed cleanly (no segfault): the chat's `_take_line` + helpers were hardened against the NOVA codegen pointer-threshold overflow that previously crashed on long inputs. Both line sizes now exit 0 with a `bye.` trailer; the safe-line path still works after the big-line path proves no shared corruption. |
| `failmode_session_eviction.sh` | With `CE_WEB_MAX_SESSIONS=2`, hitting web.py with 5 unique cookies leaves exactly 2 in `/api/sessions` -- the most-recent 2; the first 3 were evicted in LRU order. |
| `failmode_save_load_ping_pong.sh` | 20 alternations of `/save` + `/load` in one chat session leave knowledge count, soul name, and taught words EXACTLY as before -- the round-trip is bit-stable (no ±1 drift; `_restore_word_senses` is fully idempotent so the same snapshot replayed 20 times never grows the xref count). |
| `failmode_constitution_bypass_attempts.sh` | 9 forbidden rephrasings of the "exfiltrate ..." intent all trigger `[refused]` + `outcome : vetoed` -- 5 literal "exfiltrate" variants AND 4 paraphrases that AVOID the literal trigger ("leak", "smuggle", "share ... attacker", "send ... external server"). The safety stack now anchors on a canonical concept (`exfiltrate`) and walks the P14 neighborhood, catching the seeded synonym chain (leak / smuggle / send_external / share_secret) in addition to the literal-substring rule (defence in depth). A benign trailer ("send a friendly hello") must NOT trip the gate -- guards against accidental promotion of "send" itself. |

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
