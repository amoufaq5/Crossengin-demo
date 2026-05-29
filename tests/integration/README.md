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
