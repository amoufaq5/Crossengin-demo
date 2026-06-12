# ADR-0068: dtls12 epoch-rotation / SRTP-export — the 10 failing assertions are all TEST bugs

## Status

Accepted (test-level fix applied; `src/federation/dtls12.nova` unchanged)

## Date

2026-06-12

## Context

ADR-0065 fixed the dtls12 compile hang (the `dtls_stats_line` long `+`-chain
blowup), which had meant `tests/unit/test_dtls12.nova` had literally never
run. Once it ran it reported **440 passed, 10 FAILED**. ADR-0067 triaged
those 10 into the epoch-rotation / SRTP-export area and deferred the fix to
this ADR. ADR-0065's "Honest gaps" section guessed they might be a mix of
`dtls_advance_epoch` logic bugs and a test typo, but did not resolve
code-vs-test per failure.

The 10 failures:

```
FAIL: recv_seq reset to 0 expected=0 got=17
FAIL: aead_records_out preserved across CCS expected=7 got=0
FAIL: aead_records_in preserved across CCS expected=11 got=0
FAIL: label[14] == 's' (0x73) expected=115 got=95
FAIL: key_block pointer changed (fresh allocation)
FAIL: client_write_key pointer changed
FAIL: server_write_key pointer changed
FAIL: client_write_iv pointer changed
FAIL: server_write_iv pointer changed
FAIL: post-advance km is fresh non-zero pointer
```

This ADR's mandate: for EACH failure decide code-bug-vs-test-bug by reading
both the assertion and the implementation (`dtls_advance_epoch`,
`dtls_export_srtp_keying_material`, the `DTLS_S_SLOT_*` constants) and
checking against DTLS 1.2 / RFC semantics — no guessing. The investigation
shows **all 10 are TEST bugs**: `src/federation/dtls12.nova` is correct and
was not modified. Two distinct root causes drive them.

## Decision

### Root cause A — wrong raw slot indices in the poke-and-read tests (3 failures)

`test_dtls12.nova` pokes state slots by RAW index (`st[N] = v`) rather than by
the `DTLS_S_SLOT_*` constant, and the indices it used did not match the slot
map in `dtls12.nova`:

| Slot constant (dtls12.nova) | index |
| --------------------------- | ----- |
| `DTLS_S_SLOT_SEND_SEQ`        | 25 |
| `DTLS_S_SLOT_RECV_SEQ`        | 26 |
| `DTLS_S_SLOT_TAMPER_CT`       | 27 |
| `DTLS_S_SLOT_AEAD_RECORDS_OUT`| 30 |
| `DTLS_S_SLOT_AEAD_RECORDS_IN` | 31 |

- **`recv_seq reset to 0` (got 17) — TEST BUG.** `test_r33b_advance_epoch_resets_sequences`
  did `st[31] = 17` and asserted `st[31] == 0`, calling slot 31 "RECV_SEQ".
  But slot 31 is `AEAD_RECORDS_IN`; RECV_SEQ is slot 26. `dtls_advance_epoch`
  correctly resets slot 26 to 0 (and correctly PRESERVES the cumulative
  AEAD counter at slot 31). DTLS justification: RFC 6347 §4.1 makes the
  record sequence number per-epoch — it MUST reset on epoch advance — and the
  code does exactly that on slot 26. Fix: poke/read `st[26]`.

- **`aead_records_out/in preserved` (got 0) — TEST BUGS.**
  `test_r33b_advance_epoch_preserves_cumulative_stats` did `st[26] = 7` /
  `st[27] = 11` (slots RECV_SEQ / TAMPER_CT) but then read back via the
  accessors `dtls_aead_records_out` (slot 30) and `dtls_aead_records_in`
  (slot 31), which were untouched (0). The AEAD record counters are
  cumulative lifetime telemetry that must span epochs; `dtls_advance_epoch`
  correctly never zeroes slots 30/31. Fix: poke `st[30] = 7` / `st[31] = 11`.

Empirical confirmation (probe, since `nova run` executes the test binary):
poking the CORRECT constant slots and advancing yields `send_seq=0`,
`recv_seq=0`, `aead_out=7`, `aead_in=11` — exactly the reset/preserve
contract the tests intend. The code already implements it.

### Root cause B — NOVA `==`/`!=` on heap pointers is type-tag identity, not address equality (6 failures)

The five `*_pointer changed (fresh allocation)` assertions and the
`post-advance km is fresh non-zero pointer` assertion detect a fresh
allocation with `ptr_pre != ptr_post`. In NOVA, `==`/`!=` applied to two
heap pointers (values returned by `alloc`) compares by TYPE-TAG — every
alloc'd buffer is the same "pointer" kind — so two DISTINCT buffers always
test EQUAL under `!=`. Measured directly:

```
x = alloc(40); y = alloc(40)
x = 76386624, y = 76386664      // distinct addresses, delta = 40
x == y  -> 1   (reported EQUAL!)
x != y  -> 0
x <  y  -> 1   // ordered/arithmetic ops DO see the address
y -  x  -> 40
```

So `ptr_pre != ptr_post` can NEVER be true for two distinct allocations,
regardless of what the code does. These are **TEST BUGS**: the assertions use
an idiom NOVA does not support.

The implementation is in fact correct: `dtls_advance_epoch` re-runs
`dtls_prf_sha256(master_secret,"key expansion",server_random||client_random,40)`,
which `alloc`s a fresh 40-byte `key_block`, then calls `_dtls_slice_key_block`
which `alloc`s four fresh sub-buffers (cwk/swk/civ/siv). The SRTP exporter
likewise re-`alloc`s a 60-byte buffer after the cache slot is cleared.
DTLS/RFC justification: RFC 5246 §6.3 fixes the `key expansion` label and the
`server_random || client_random` seed order, and a CCS / epoch advance
re-derives the traffic keys — fresh buffers are the intended behaviour.
Empirical probe inside the running test binary:
`ms != 0`, `cr/sr` non-zero, `rekeys == 1`, `kb_pre = 856340368`,
`kb_post = 858797848` (genuinely different addresses) — yet `kb_pre != kb_post`
evaluated to 0 under NOVA's tag-equality. The allocation IS fresh; only the
comparison operator was wrong.

Fix: detect a fresh pointer with the numeric ADDRESS delta, which the ordered
operators expose: `(ptr_post - ptr_pre) != 0`. The null check `km_post != 0`
is kept verbatim — `0` is the integer sentinel (not a heap pointer), so
`!= 0` is reliable, as the already-passing `km != 0` / `pub != 0` assertions
demonstrate.

### Root cause C — wrong expected byte in the RFC 5764 label assertion (1 failure)

- **`label[14] == 's' (0x73)` — TEST BUG.** The RFC 5764 §4.2 DTLS-SRTP
  exporter label is `"EXTRACTOR-dtls_srtp"`. Counting:
  `E0 X1 T2 R3 A4 C5 T6 O7 R8 -9 d10 t11 l12 s13 _14 s15 r16 t17 p18`.
  Byte 14 is the underscore between `dtls` and `srtp` → `_` = 0x5F = 95, not
  `s` (115). The sibling assertions (`len == 19`, `label[0] == 'E'`,
  `label[10] == 'd'`, `label[18] == 'p'`) all pass and are consistent with
  95 at index 14. The exporter (`dtls_export_srtp_keying_material`) already
  passes the correct literal `"EXTRACTOR-dtls_srtp"`. Fix: expect 95.

### Per-failure verdict table

| # | Failure | Verdict | Fix |
| - | ------- | ------- | --- |
| 1 | recv_seq reset to 0 (got 17) | TEST | `st[31]`→`st[26]` (RECV_SEQ) |
| 2 | aead_records_out preserved (got 0) | TEST | `st[26]`→`st[30]` (AEAD_OUT) |
| 3 | aead_records_in preserved (got 0) | TEST | `st[27]`→`st[31]` (AEAD_IN) |
| 4 | label[14] == 's' | TEST | expect 95 (`_`) not 115 (`s`) |
| 5 | key_block pointer changed | TEST | `kb_pre != kb_post` → `(kb_post-kb_pre)!=0` |
| 6 | client_write_key pointer changed | TEST | address-delta idiom |
| 7 | server_write_key pointer changed | TEST | address-delta idiom |
| 8 | client_write_iv pointer changed | TEST | address-delta idiom |
| 9 | server_write_iv pointer changed | TEST | address-delta idiom |
| 10 | post-advance km fresh non-zero ptr | TEST | `km_post != 0 && (km_post-km_pre)!=0` |

`src/federation/dtls12.nova` was NOT changed — the code's reset/preserve/
re-allocate contract and the RFC 5764 label were correct all along.

## Consequences

- `timeout 120 nova run tests/unit/test_dtls12.nova` is now **fully green:
  `dtls12: OK (450 checks)`** (was 440 passed, 10 FAILED). The passed count
  rose by exactly the 10 fixed (440 → 450), with no previously-green check
  regressed.
- `dtls12.nova` still compiles fast: `nova build src/federation/dtls12.nova
  -o /tmp/d.bin` completes in **0.16 s**. No long `+` chain was introduced
  (the only edits were in the test file; `dtls_stats_line` is untouched).
- Reverse-dependency tests all green (see Implementation Notes).

## Honest gaps

- **The fix is to the tests, not the code, because the code was already
  correct.** This is the right call (the assertions were measurably wrong),
  but it does mean the suite never exercised a genuine `dtls_advance_epoch`
  defect — the original assertions could not have caught one either, given the
  wrong slot indices and the unusable `!=` idiom.
- **NOVA pointer `==`/`!=` is tag-identity, not address-identity.** This ADR
  documents the behaviour and works around it (`(post-pre)!=0`). Any other
  test in the tree that uses `ptrA != ptrB` to mean "different buffer" is
  silently broken the same way; this ADR only audited the dtls12 suite. A
  tree-wide sweep for that idiom is left as follow-up.
- The "fresh allocation" assertions now prove the address CHANGED, which (with
  the existing byte-equality checks via `_tdtls_buf_eq`) is the full
  "fresh-but-byte-identical, variant A" contract. They do not, and cannot in
  NOVA, prove the OLD buffer was freed.

## Implementation Notes

### Files changed

- `tests/unit/test_dtls12.nova` — 6 edits, all in test functions:
  - `test_r33b_advance_epoch_resets_sequences`: `st[31]`→`st[26]` (poke + assert) for RECV_SEQ.
  - `test_r33b_advance_epoch_preserves_cumulative_stats`: `st[26]`/`st[27]`→`st[30]`/`st[31]` for AEAD_RECORDS_OUT/IN.
  - `test_r35a_label_is_19_ascii_bytes`: expected `label[14]` 115→95 (`_`).
  - `test_r38b_advance_reallocates_key_block_and_subbuffers`: 5 `pre != post` → `(post - pre) != 0`.
  - `test_r38b_srtp_keying_material_recomputes_deterministically`: `km_post != km_pre` → `(km_post - km_pre) != 0` (null check kept).
- `src/federation/dtls12.nova` — UNCHANGED.
- `docs/adr/0068-dtls12-epoch-rotation-fix.md` — this file (new).

### Before / after check counts

- Before: `dtls12: 440 passed, 10 FAILED`.
- After:  `dtls12: OK (450 checks)`.

### Compile timing

- `nova build src/federation/dtls12.nova -o /tmp/d.bin`: real 0.159 s
  (well under the few-seconds budget; no `+`-chain regression).

### Investigation method

- `nova run` compiles AND executes the test binary, but only for the full
  suite file; small standalone probes printed nothing, so probes were run by
  temporarily appending a `_PROBE_*()` function to a copy of
  `test_dtls12.nova` and calling it first in `main`, then grepping the
  `PROBE ` lines. All probe copies were `/tmp` or `_tmp_*` scratch files and
  were deleted.
- Probe 1 (correct slots): post-advance `send_seq=0`, `recv_seq=0`,
  `aead_out=7`, `aead_in=11` — proves the reset/preserve contract.
- Probe 2 (pointers): `kb_pre`/`kb_post` are different addresses, `rekeys=1`,
  yet `kb_pre != kb_post == 0` — isolating the operator, not the allocation.
- Probe 3 (operator): two fresh `alloc(40)` buffers 40 bytes apart report
  `==`→1, `!=`→0, `<`→1, `(y-x)`→40 — confirming tag-identity `==`/`!=`.

### Reverse-dependency results (no regression)

`grep -rl dtls12 src/ tests/` → only `src/federation/srtp.nova` imports
dtls12 (plus the dtls12 test itself). Federation suite re-run:

| test | result |
| ---- | ------ |
| test_dtls12 | OK (450 checks) |
| test_srtp   | OK (135 checks) |
| test_turn   | OK (452 checks) |
| test_webrtc | OK (59 checks) |
| test_ice    | OK (70 checks) |
| test_noise_xk | OK (44 checks) |
