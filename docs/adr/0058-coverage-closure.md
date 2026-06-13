# ADR-0058: Coverage closure — the last 6 untested modules (NL_AND_COVERAGE C1)

## Status

Proposed

## Date

2026-06-11

## Context

`NL_AND_COVERAGE.md` measured the baseline: 232 of 238 source modules were
imported by some unit test. The 6 that were not were all I/O
transducers/effectors whose *device/socket* paths are integration-only, but
whose *pure, deterministic logic* (shell-quoting, IP parsing, line framing, seam
state + decoder registries, accessors) had no coverage at all. This is the C1
phase: close those gaps by unit-testing the pure logic, leaving the genuinely
I/O-bound paths to integration.

## Decision

Add a `tests/unit/test_<module>.nova` for each of the six, exercising only the
deterministic logic (no real audio/video/sockets):

- **`audio_speak`** — `_shell_quote_single`: POSIX single-quote escaping
  (`'` → `'\''`), the injection-safety property that the quoted result always
  begins and ends with `'`, and `audio_modes_available` returns a non-empty
  capability string.
- **`stream_http`** — `_stream_http_is_digits`; `_stream_http_ip_to_int`
  (dotted-quad parsing, octet packing, malformed-input rejection); the
  `stream_http_new` state object + accessors/counters.
- **`stream_audio`** — `stream_audio_new` defaults (`/tmp/ce_input.wav`, poll
  100), the disabled/uninitialised gates, counters, and the embedded STT/capture
  structs.
- **`stream_unix_socket`** — `_stream_unix_split_first_newline` (splits at the
  FIRST newline only; leading-newline and no-newline cases) + the state object.
- **`video_perception` / `visual_perception`** — the seam decoder registry
  (`*_seam_new` registering the builtins → enabled), name↔id resolution
  (`*_decoder_id_for`), default selection + `*_decoder_name`, `*_set_default`,
  custom `*_register_decoder`, and the fresh-result accessors.

Tests call the modules' `_`-prefixed helpers directly (NOVA has no visibility
enforcement — top-level functions are importable), which is the right level for
covering pure internal logic.

## Consequences

- **Coverage is complete: 0 of 238 source modules are untested** (every module is
  now imported and asserted by at least one unit test). 73 new checks across 6
  suites, all green; no source module was modified, so the existing suite is
  unaffected.
- Closing the gap surfaced a **latent bug** (below) that had been invisible
  precisely because the module was untested — the value of the exercise.

## Honest gaps

- **Device/socket paths remain integration-only.** These tests cover the pure
  logic, not real audio output (`fork`/`exec` of `aplay`/`espeak`), real socket
  bind/listen/accept, or real video/image decoding. Those need the integration
  harness (a device, a peer, a media file), not a unit test.
- **`stream_http`'s `_stream_http_ip_to_int` overflows on high octets.** Its
  `octet * 256 * 256 * 256` chain makes an intermediate operand exceed NOVA
  codegen bug #11's 0x100000 threshold once the 4th octet ≥ 16, so it would
  miscompile for addresses like `255.255.255.255`. The tests cover low/loopback
  octets (≤ 15), which is what the production bind path uses; **the fix (rewrite
  the packing with `int_mul`, as the HDC/PRNG code does) is left to a follow-up**
  — flagged here as a real finding, not silently worked around.
- `*_default_decoder` reads an env var (`CE_VID_DECODER` / `CE_VP_DECODER`); the
  tests assume it is unset (the normal test environment) when asserting the y4m /
  pgm default. The env-independent registry/`set_default` paths are also tested.

## Implementation Notes

- New test files only; no production module touched. Suites:
  `test_stream_http` (20), `test_audio_speak` (6), `test_stream_audio` (10),
  `test_stream_unix_socket` (14), `test_video_perception` (11),
  `test_visual_perception` (12).
- Next on `NL_AND_COVERAGE.md`: Track N (natural-language depth), starting with
  N1 — the NL-question → structured-KG-answer bridge.
